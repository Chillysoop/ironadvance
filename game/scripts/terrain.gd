class_name Terrain
extends RefCounted
## Destructible cell terrain: generation, carving, and the collapse simulation
## (unsupported pieces detach into falling chunks that crush whatever is below).

const CELL := 4
const ROWS := 135
const GRATE := 5   # steel grating: soldiers stand on it, bullets, rockets and grenades go through
const FENCE := 6   # chain-link: stops soldiers and Jackals, not bullets, rockets or grenades
const ICE := 7     # sheet ice: anything that lands on it keeps sliding
const RUBBER := 8  # rubber tarp: soldiers and grenades bounce off it, no fall damage
const STEEL := 9   # M2/M7 riveted plate: train cars and the carrier deck. Blasts barely dent it
const FLOOD_LIMIT := 5000
const WATER_ROW := Data.WATER_Y / CELL  # first row of cells under the water

var b  # the Battle that owns this terrain
var cols := 0
var world_w := 0
var grid := PackedByteArray()
var data := PackedByteArray()  # RG8 texture bytes: material, scorch
var heights := PackedFloat32Array()
var vstamp := PackedInt32Array()
var astamp := PackedInt32Array()
var qbuf := PackedInt32Array()
var vid := 1
var img: Image
var tex: ImageTexture
var dirty := false
var rev := 0  # bumped on every cell change so decorations can re-read the surface
var ladders: Array = []
var pits: Array = []
var sandbags: Array = []
var structs: Array = []
var spawns: Array = []
var chunks: Array = []
var bridges: Array = []  # standing bridge structs: posts are checked after every carve
var arena_x := 0
var yard: Array = []     # [x0, x1] of the clearing after the mid camp, where a detour plays out
var stretches: Array = []  # [x0, x1] of each fighting stretch, in order
var camps: Array = []    # safe camps inside the level: {x0, x1, used}
var ice_runs: Array = []  # [x0, x1] of each sheet of ice on the ground
var tarps: Array = []     # [x0, x1] of each rubber tarp on the ground
var pins := {}            # N2: cell index -> rivet unit id; a bolted girder hangs from these
var lakes: Array = []     # M1: [x0, x1] of each frozen crust over open water
var cars: Array = []      # M2: train car structs, with "roof" set once built
var lifts: Array = []     # M7: carrier deck elevators
var runways: Array = []   # M7: taxi lanes a jet rolls down
var ceiling := false      # M4: the level is underground
var props: Array = []     # M4: propped slabs still standing
var orig := PackedByteArray()  # M6: the map as built, for the Hive to grow back toward

func _init(battle) -> void:
	b = battle

static func hash2(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return float((h ^ (h >> 16)) & 0xFFFFFFFF) / 4294967296.0

# ---------------------------------------------------------------- queries
func solid(x: float, y: float) -> bool:
	if x < 0 or x >= world_w:
		return true
	if y < 0 or y >= Data.H:
		return false
	return grid[int(y / CELL) * cols + int(x / CELL)] != 0

func hard(x: float, y: float) -> bool:
	## Solid to bullets, sight lines and thrown things: everything but grating and chain-link.
	if x < 0 or x >= world_w:
		return true
	if y < 0 or y >= Data.H:
		return false
	var m := grid[int(y / CELL) * cols + int(x / CELL)]
	return m != 0 and m != GRATE and m != FENCE

func mat(x: float, y: float) -> int:
	if x < 0 or x >= world_w or y < 0 or y >= Data.H:
		return 0
	return grid[int(y / CELL) * cols + int(x / CELL)]

func set_cell(cx: int, cy: int, m: int) -> void:
	if cx < 0 or cy < 0 or cx >= cols or cy >= ROWS:
		return
	var i := cy * cols + cx
	grid[i] = m
	data[i * 2] = m
	if m == 0:
		data[i * 2 + 1] = 0
	dirty = true
	rev += 1

func fill_r(x: float, y: float, w: float, h: float, m: int) -> void:
	for cy in range(int(floor(y / CELL)), int(ceil((y + h) / CELL))):
		for cx in range(int(floor(x / CELL)), int(ceil((x + w) / CELL))):
			set_cell(cx, cy, m)

func fill_disc(x: float, y: float, r: float, m: int) -> void:
	for cy in range(int(floor((y - r) / CELL)), int(ceil((y + r) / CELL)) + 1):
		for cx in range(int(floor((x - r) / CELL)), int(ceil((x + r) / CELL)) + 1):
			var dx := cx * CELL + 2 - x
			var dy := cy * CELL + 2 - y
			if dx * dx + dy * dy <= r * r:
				set_cell(cx, cy, m)

func ground_at(x: float) -> float:
	return round(heights[clampi(int(floor(x / CELL)), 0, cols - 1)] / CELL) * CELL

func stand_y(x: float, from_y: float):
	## First standing spot at or below from_y, or null if only water.
	var y := maxf(CELL, floor(from_y / CELL) * CELL)
	while y < Data.WATER_Y:
		if solid(x, y) and not solid(x, y - 1) and not (ceiling and solid(x, y - 12)):
			return y  # (in the mine, the crack over a propped slab is no place to stand)
		y += CELL
	return null

# ---------------------------------------------------------------- generation
func build(mission: Dictionary) -> void:
	# lay segments end to end
	var x := 0
	var shapes: Array = []
	var open_pits: Array = []
	pins.clear(); pits.clear(); sandbags.clear(); structs.clear(); spawns.clear(); ladders.clear(); bridges.clear(); camps.clear(); yard = []
	lakes = []; cars = []; lifts = []; runways = []; props = []; orig = PackedByteArray()
	arena_x = 1 << 20  # outposts have no arena
	var rules: Dictionary = mission.get("rules", {})
	stretches = []   # fighting stretches, where a biome's extra fuel and mines and encounters go
	for sname in mission.segments:
		var s: Dictionary = Data.SEGMENTS[sname]
		if s.get("yard", false):
			yard = [x, x + s.w]
		elif sname != "start" and not s.get("camp", false) and not s.get("flat", false):
			stretches.append([x + 60, x + s.w - 60])
		if s.get("flat", false):
			arena_x = x
		if s.get("camp", false):
			camps.append({"x0": x, "x1": x + s.w, "fire": x + s.w / 2, "used": false})
		for p in s.pits:
			pits.append([p[0] + x, p[1] + x])
		for p in s.get("gaps", []):
			# M2/M7: open drops with no planks over them, between train cars and off the deck edge
			pits.append([p[0] + x, p[1] + x])
			open_pits.append([p[0] + x, p[1] + x])
		for sb in s.sandbags:
			sandbags.append(sb + x)
		for g in s.get("ground", []):
			var gg: Dictionary = g.duplicate()
			gg.x0 += x; gg.x1 += x
			shapes.append(gg)
		for st in s.structs:
			var t: Dictionary = st.duplicate(true)
			for k in ["px", "x0", "x1", "x", "col", "bx", "post", "jib", "hook"]:
				if t.has(k):
					t[k] += x
			if t.has("posts"):
				t.posts = t.posts.map(func(v): return v + x)
			# bridges and docks span open water: their gap is a pit with no planks over it
			if t.t == "bridge" or t.t == "docks" or t.t == "crust" or t.t == "lift":
				pits.append([t.x0, t.x1])
				open_pits.append([t.x0, t.x1])
			structs.append(t)
		for sp in s.spawns:
			spawns.append([sp[0], sp[1] + x, sp[2] if sp.size() > 2 else {}])
		x += s.w
	var pad_order := stretches.duplicate()
	pad_order.shuffle()  # bonus pads go one to a stretch
	var walls := structs.filter(func(t): return t.t == "fence")
	for k in ["fuel", "mines", "pads"]:
		for i in int(rules.get(k, 2 if k == "pads" else 0)):
			if stretches.is_empty():
				break
			var st: Array = pad_order[i % pad_order.size()] if k == "pads" else stretches[randi() % stretches.size()]
			var sx := randf_range(st[0], st[1])
			for tries in 8:
				if not pits.any(func(p): return sx > p[0] - 24 and sx < p[1] + 24) and not walls.any(func(f): return absf(sx - f.x) < 40):
					break
				sx = randf_range(st[0], st[1])
			spawns.append([{"fuel": "fuel", "mines": "mine", "pads": "pad"}[k], sx, {}])
	# T2 surfaces: ice sheets, rubber tarps and live wires, each on clear ground in some stretch
	ice_runs = []; tarps = []
	var taken: Array = []
	for k in ["ice", "tarps", "wires"]:
		for i in int(rules.get(k, 0)):
			if stretches.is_empty():
				break
			var w: float = {"ice": 160.0, "tarps": 40.0, "wires": 120.0}[k]
			# every clear spot on an 8px grid, then one at random
			var spots: Array = []
			for st in stretches:
				var cx: float = st[0]
				while cx <= st[1] - w:
					var lo := cx - 20
					var hi := cx + w + 20
					if not pits.any(func(p): return hi > p[0] and lo < p[1]) and not sandbags.any(func(sb): return sb + 20 > lo and sb < hi) \
							and not structs.any(func(t): return struct_span(t)[1] > lo and struct_span(t)[0] < hi) and not taken.any(func(r): return r[1] > lo and r[0] < hi):
						spots.append(cx)
					cx += 8
			if spots.is_empty():
				continue  # nowhere clear enough on this map
			var sx: float = spots[randi() % spots.size()]
			taken.append([sx, sx + w])
			if k == "ice":
				ice_runs.append([sx, sx + w])
			elif k == "tarps":
				tarps.append([sx, sx + w])
			else:
				spawns.append(["jbox", sx, {}])
	world_w = int(ceil(x / 160.0)) * 160
	cols = world_w / CELL
	var n := cols * ROWS
	grid = PackedByteArray(); grid.resize(n)
	data = PackedByteArray(); data.resize(n * 2)
	vstamp = PackedInt32Array(); vstamp.resize(n)
	astamp = PackedInt32Array(); astamp.resize(n)
	qbuf = PackedInt32Array(); qbuf.resize(n)
	heights = PackedFloat32Array(); heights.resize(cols)
	var amp: float = rules.get("amp", 1.0)
	for cx in cols:
		var wx := float(cx * CELL)
		var h := 392.0 - amp * (26.0 * sin(wx / 290.0 + 0.5) + 18.0 * sin(wx / 131.0 + 1.3) + 9.0 * sin(wx / 47.0 + 0.7))
		if wx < 460:
			h = lerpf(404, h, wx / 460.0)
		if wx > arena_x + 280:
			h = lerpf(h, 404, clampf((wx - arena_x - 280) / 320.0, 0, 1))
		heights[cx] = h
	for c in camps:
		# a level clearing to pitch the tents on
		for cx in range(maxi(0, int((c.x0 - 120) / CELL)), mini(cols, int((c.x1 + 120) / CELL))):
			var wx := float(cx * CELL)
			var k := clampf(minf(wx - (c.x0 - 120), (c.x1 + 120) - wx) / 120.0, 0, 1)
			heights[cx] = lerpf(heights[cx], 400.0, k)
	for g in shapes:
		shape_ground(g)
	for p in pits:
		flatten(p[0], p[1], 70)
	for s in structs:
		if s.t == "bunker":
			flatten(s.x - 110, s.x + s.w, 20)
		if s.t == "over":
			flatten(minf(s.px, s.x0), maxf(s.px, s.x1), 10)
		if s.t == "fort":
			flatten(s.x - 30, s.x + s.w + 10, 10)
		if s.t == "crane":
			flatten(s.x - 12, s.x + 24, 6)
		if s.t == "catwalk":
			flatten(s.x0 - 10, s.x1 + 10, 10)
		if s.t == "fence":
			flatten(s.x - 20, s.x + 24, 10)
	for cx in cols:
		var cxx := cx * CELL + 2
		var in_pit := false
		for p in pits:
			if cxx >= p[0] and cxx < p[1]:
				in_pit = true
		if in_pit:
			continue
		var top := int(round(heights[cx] / CELL))
		var deep := top + 16 + int(hash2(cx, 7) * 4)
		# the ground stops at the waterline like Worms: dig through it and there is only water
		for cy in range(top, WATER_ROW):
			set_cell(cx, cy, STEEL if rules.get("deck", false) else (4 if cy > deep else 1))
		for r in ice_runs:
			if cxx >= r[0] and cxx < r[1]:
				set_cell(cx, top, ICE)
				set_cell(cx, top + 1, ICE)
		for r in tarps:
			if cxx >= r[0] and cxx < r[1]:
				set_cell(cx, top, RUBBER)
	for p in pits:
		if open_pits.has(p):
			continue
		var y := ground_at(p[0] - 12)
		fill_r(p[0] - 8, y, p[1] - p[0] + 16, 8, 3)
	ceiling = rules.get("ceiling", false)
	if ceiling:
		# M4: solid rock overhead, so nothing is lobbed high and nothing falls from the sky
		for cx in cols:
			for cy in range(0, int(ceil_at(cx * CELL + 2.0) / CELL) + 1):
				if grid[cy * cols + cx] == 0:
					set_cell(cx, cy, 4)
	for s in structs:
		build_struct(s)
	for sx in sandbags:
		# the top sits one step above the ground just before the bags, so a soldier walking up
		# a slope can still hop them; the bottom reaches down to wherever the ground under them is
		var g := ground_at(sx - CELL)
		var deep := maxf(maxf(ground_at(sx), ground_at(sx + 10)), ground_at(sx + 19))
		fill_r(sx, g - 12, 20, maxf(24, deep - g + 12), 2)
	if rules.get("regrow", 0) > 0:
		orig = grid.duplicate()
	img = Image.create_from_data(cols, ROWS, false, Image.FORMAT_RG8, data)
	tex = ImageTexture.create_from_image(img)
	dirty = false

func check_props(cause) -> void:
	## M4: once a beam is cut clean through, what's left of it above the cut splinters and the
	## slab drops flat onto whoever is under it.
	for p in props:
		if p.down:
			continue
		var cut := -1.0
		var yy: float = p.top + 24
		while yy < p.g:
			if not solid(p.post - 2, yy) and not solid(p.post + 2, yy):
				cut = yy
				break
			yy += CELL
		if cut < 0:
			continue
		p.down = true
		var yb: float = p.top + 24
		while yb < cut:
			for xx in [p.post - 2, p.post + 2]:
				if solid(xx, yb):
					b.debris(xx, yb, 3, true)
					set_cell(int(xx / CELL), int(yb / CELL), 0)
			yb += CELL
		vid += 1
		flood(int((p.top + 12) / CELL) * cols + int((p.x + p.w / 2.0) / CELL), cause)

func ceil_at(x: float) -> float:
	## M4: the bottom of the mine's rock ceiling at x.
	return 150.0 + 26.0 * sin(x / 170.0) + 12.0 * sin(x / 61.0 + 1.0)

func lift_cells(l: Dictionary, on: bool) -> void:
	## M7: lay (or lift away) an elevator platform. Its cells are pinned so it never falls.
	var y: float = l.y_up if l.up else l.y_dn
	for cy in range(int(y / CELL), int((y + 8) / CELL)):
		for cx in range(int(l.x0 / CELL), int(ceil(l.x1 / CELL))):
			set_cell(cx, cy, STEEL if on else 0)
			if on:
				pins[cy * cols + cx] = -1
			else:
				pins.erase(cy * cols + cx)

func struct_span(t: Dictionary) -> Array:
	## Rough [x0, x1] a struct covers, for keeping ice, tarps and wires out from under it.
	var xs: Array = []
	for k in ["px", "x0", "x1", "x", "col", "bx", "post"]:
		if t.has(k):
			xs.append(float(t[k]))
	if t.has("x") and t.has("w"):
		xs.append(float(t.x + t.w))
	if xs.is_empty():
		return [-1e9, -1e9]
	return [xs.min() - 24.0, xs.max() + 24.0]

func shape_ground(g: Dictionary) -> void:
	## raise a ridge (dh > 0) or dig a trench (dh < 0) between x0 and x1, with ramps of g.ramp px.
	## A ridge with no ramp is a cliff, and gets a ladder up its near face.
	var ramp: float = g.get("ramp", 40)
	var c0 := maxi(0, int(floor((g.x0 - ramp) / CELL)))
	var c1 := mini(cols - 1, int(ceil((g.x1 + ramp) / CELL)))
	for cx in range(c0, c1 + 1):
		var wx := float(cx * CELL)
		var k := 1.0
		if wx < g.x0:
			k = 1.0 - (g.x0 - wx) / ramp if ramp > 0 else 0.0
		elif wx > g.x1:
			k = 1.0 - (wx - g.x1) / ramp if ramp > 0 else 0.0
		k = clampf(k, 0, 1)
		k = k * k * (3 - 2 * k)
		heights[cx] -= g.dh * k
	if g.dh > 0 and ramp <= 8:
		var top := ground_at(g.x0 + 8)
		ladders.append({"x": g.x0 - 10, "top": top, "bot": ground_at(g.x0 - 20), "offx": g.x0 + 10})

func flatten(a: float, bb: float, margin: float) -> void:
	var ref := heights[clampi(int(floor((a - margin) / CELL)), 0, cols - 1)]
	for cx in range(int(floor((a - margin - 60) / CELL)), int(ceil((bb + margin + 60) / CELL)) + 1):
		if cx < 0 or cx >= cols:
			continue
		var x := float(cx * CELL)
		var d := 0.0
		if x < a - margin:
			d = (a - margin - x) / 60.0
		elif x > bb + margin:
			d = (x - bb - margin) / 60.0
		heights[cx] = lerpf(ref, heights[cx], clampf(d, 0, 1))

func build_struct(s: Dictionary) -> void:
	match s.t:
		"crust":
			# M1: a sheet of lake ice flush with both banks over open water. Heavies and blasts break it
			var g := ground_at(s.x0 - 12)
			fill_r(s.x0 - 4, g, s.x1 - s.x0 + 8, 8, ICE)
			lakes.append([s.x0, s.x1])
		"car":
			# M2: a steel train car on its chassis: doors at both ends at floor level, a roof you can
			# fight on, and a hatch with a ladder at the back end. A flatcar is just the deck.
			var g := ground_at(s.x + s.w / 2.0)
			var roof: float = g - s.h
			s["roof"] = roof
			fill_r(s.x, roof, s.w, Data.WATER_Y + 8 - roof, STEEL)
			if s.h >= 40:
				fill_r(s.x + 8, roof + 8, s.w - 16, s.h - 8, 0)
				fill_r(s.x, g - 36, 8, 36, 0)
				fill_r(s.x + s.w - 8, g - 36, 8, 36, 0)
				fill_r(s.x + s.w - 34, roof, 18, 8, 0)
				ladders.append({"x": s.x + s.w - 25, "top": roof, "bot": g, "offx": s.x + s.w - 46})
				cars.append(s)
		"coupler":
			# M2: the walkway between two cars, a plate at floor level
			var g := ground_at(s.x0 - 12)
			fill_r(s.x0 - 4, g, s.x1 - s.x0 + 8, 4, STEEL)
		"prop":
			# M4: a rock slab hanging just under the ceiling on one wooden beam. Cut the beam and it drops
			var top := 0.0
			for xx in range(int(s.x), int(s.x + s.w), CELL):
				top = maxf(top, ceil_at(xx))
			top = (floor(top / CELL) + 2) * CELL
			var g := ground_at(s.post)
			# the ceiling comes down to one crack above the slab, so nobody fits up there
			fill_r(s.x - 8, 0, s.w + 16, top - CELL, 4)
			fill_r(s.x, top, s.w, 24, 4)
			fill_r(s.post - 4, top + 24, 8, g - top - 24, 3)
			s["top"] = top
			s["g"] = g
			s["down"] = false
			props.append(s)
		"lift":
			# M7: a deck elevator. It drops a storey and comes back up on a fixed count
			var g := ground_at(s.x0 - 12)
			var l := {"x0": s.x0, "x1": s.x1, "y_up": g, "y_dn": g + s.get("drop", 64), "up": true, "every": s.get("every", 2), "t": s.get("every", 2)}
			lifts.append(l)
			lift_cells(l, true)
		"runway":
			runways.append({"x0": s.x0, "x1": s.x1})
		"tower":
			var g := ground_at(s.x)
			var top: float = g - s.h
			fill_r(s.x - 4, top, 8, s.h + 8, 3)
			fill_r(s.x - 24, top - 8, 48, 8, 3)
			fill_r(s.x - 24, top - 16, 4, 8, 3)
			fill_r(s.x + 20, top - 16, 4, 8, 3)
			fill_r(s.x - 14, top + 8, 4, 12, 3)
			fill_r(s.x + 10, top + 8, 4, 12, 3)
			fill_r(s.x - 14, top + 8, 28, 4, 3)
			ladders.append({"x": s.x - 30, "top": top - 8, "bot": g, "offx": s.x - 16})
		"over":
			var g := ground_at(s.px)
			var top: float = g - s.h
			fill_r(s.px, top, 12, s.h + 8, 4)
			fill_r(s.x0 - 6, top - 12, s.x1 - s.x0 + 12, 12, 4)
			fill_disc(s.x0 + (s.x1 - s.x0) * 0.3, top - 12, 9, 4)
		"ledge":
			var g := ground_at(s.post)
			var top: float = g - s.dy
			fill_r(s.post, top, 8, s.dy + 8, 4)
			fill_r(s.x, top - 12, s.w, 12, 4)
			ladders.append({"x": s.x - 8, "top": top - 12, "bot": ground_at(s.x - 8), "offx": s.x + 8})
		"boulder":
			var g := ground_at(s.col)
			var top: float = g - s.colH
			fill_r(s.col, top, 22, s.colH + 8, 4)
			fill_r(s.col + 22, top, s.bx - s.col - 18, 8, 3)
			fill_r(s.bx - 2, top + 8, 4, s.rope, 3)
			fill_disc(s.bx, top + 8 + s.rope + s.r - 2, s.r, 4)
		"fort":
			# a multi-storey outpost: wooden walls and floors, a concrete roof, windows and a door in
			# the near wall and ladders zigzagging inside. The far wall is the one unbroken column
			# holding it all up: blow its base and the whole fort drops a storey onto the ground floor.
			var g := ground_at(s.x + s.w / 2.0)
			var n: int = s.floors
			var fh: float = s.fh
			var top: float = g - n * fh
			s["top"] = top
			fill_r(s.x, top, 8, n * fh + 8, 3)
			fill_r(s.x + s.w - 8, top, 8, n * fh + 8, 3)
			for k in range(1, n + 1):
				var fy: float = g - k * fh
				fill_r(s.x, fy, s.w, 8, 2 if k == n else 3)
				# windows: chest-high slits in the near wall for upper floors, a doorway at the bottom
				if k < n:
					fill_r(s.x, fy - 30, 8, 16, 0)
			fill_r(s.x, g - 38, 8, 38, 0)
			# roof parapet
			fill_r(s.x - 4, top - 8, 8, 8, 2)
			fill_r(s.x + s.w - 4, top - 8, 8, 8, 2)
			for k in n:
				var bot: float = g - k * fh
				var lx: float = s.x + (s.w - 22.0 if k % 2 == 0 else 22.0)
				var off: float = s.x + (s.w - 44.0 if k % 2 == 0 else 44.0)
				ladders.append({"x": lx, "top": bot - fh, "bot": bot, "offx": off})
		"bridge":
			# a plank deck flush with both banks on posts driven into the riverbed. check_bridges
			# cuts the deck loose; the posts that survive stay up as stepping stones to hop across.
			var g := ground_at(s.x0 - 12)
			s["y"] = g
			s["down"] = false
			fill_r(s.x0, g, s.x1 - s.x0, 8, 3)
			s["post_cells"] = []
			for px in s.posts:
				fill_r(px - 4, g + 8, 8, Data.H - g - 8, 3)
				fill_r(px - 12, g + 8, 24, 4, 3)
				s.post_cells.append(_count(px - 4, g + 8, 8, Data.WATER_Y + 12 - g - 8))
			bridges.append(s)
		"docks":
			# a pier over open water on pilings driven into the bed
			var g := ground_at(s.x0 - 12)
			fill_r(s.x0, g, s.x1 - s.x0, 8, 3)
			var px: float = s.x0 + s.pile / 2.0
			while px < s.x1:
				fill_r(px - 4, g + 8, 8, Data.H - g - 8, 4)
				fill_r(px - 10, g + 8, 20, 4, 3)
				px += s.pile
		"crane":
			# mast on the bank, a jib reaching back over the field, and a steel container on a cable
			var g := ground_at(s.x + 6)
			var top: float = g - s.h
			fill_r(s.x, top, 12, s.h + 8, 4)
			fill_r(s.x - 8, g - 8, 28, 8, 2)
			var j0: float = minf(s.jib, s.x)
			var j1: float = maxf(s.jib, s.x + 12) + 24
			fill_r(j0, top, j1 - j0, 8, 3)
			fill_r(j1 - 20, top + 8, 16, 12, 2)
			fill_r(s.hook - 2, top + 8, 4, s.rope, 3)
			var cy: float = top + 8 + s.rope
			fill_r(s.hook - s.cw / 2.0, cy, s.cw, 4, 3)
			fill_r(s.hook - s.cw / 2.0, cy + 4, s.cw, s.ch, 2)
		"catwalk":
			# a steel grating deck on steel legs, with a ladder up the near end. You stand on it,
			# but bullets, rockets and grenades go straight through: shoot up through the floor.
			var top: float = ground_at(s.x0) - s.dy
			s["y"] = top
			fill_r(s.x0, top, s.x1 - s.x0, 8, GRATE)
			# the near leg stands well back from the ladder, so a shot or a grenade aimed through
			# the ladder isn't stopped by steel hiding right behind its rails
			fill_r(s.x0 + 28, top + 8, 8, ground_at(s.x0 + 32) - top, 4)
			var px: float = s.x0 + s.get("leg", 96)
			while px <= s.x1 - 8:
				fill_r(px, top + 8, 8, ground_at(px + 4) - top, 4)
				px += s.get("leg", 96)
			fill_r(s.x1 - 8, top + 8, 8, ground_at(s.x1 - 4) - top, 4)
			ladders.append({"x": s.x0 - 8, "top": top, "bot": ground_at(s.x0 - 8), "offx": s.x0 + 12})
		"fence":
			# chain-link on the ground: too tall for a Jackal to vault, low enough for a Hop.
			# Bullets and grenades pass through it, people don't. Blasts and Brutes tear it down.
			var g := ground_at(s.x + 6)
			fill_r(s.x, g - s.h, 12, s.h + 8, FENCE)
		"bunker":
			var g := ground_at(s.x + 4)
			var top: float = g - s.h
			s["top"] = top
			fill_r(s.x, top, s.w, s.h + 8, 2)
			fill_r(s.x + 8, top + 12, s.w - 16, s.h - 12, 0)
			fill_r(s.x, top + 16, 8, 12, 0)
			var n := int(ceil(s.h / 8.0))
			for i in n:
				var sh := (i + 1) * 8
				fill_r(s.x - 24 - 12 * (n - i), g - sh, 12, sh + 8, 1)
			fill_r(s.x - 24, top, 24, 4, 3)

func flush() -> void:
	if dirty:
		img.set_data(cols, ROWS, false, Image.FORMAT_RG8, data)
		tex.update(img)
		dirty = false

# ---------------------------------------------------------------- destruction
func carve(x: float, y: float, r: float, cause) -> void:
	var R := r + 7
	var r2 := r * r
	var R2 := R * R
	var c0 := int(floor((x - R) / CELL))
	var c1 := int(floor((x + R) / CELL))
	var y0 := int(floor((y - R) / CELL))
	var y1 := int(floor((y + R) / CELL))
	var any := false
	for cy in range(y0, y1 + 1):
		for cx in range(c0, c1 + 1):
			if cx < 0 or cy < 0 or cx >= cols or cy >= ROWS:
				continue
			var i := cy * cols + cx
			var m := grid[i]
			if m == 0:
				continue
			var dx := cx * CELL + 2 - x
			var dy := cy * CELL + 2 - y
			var d2 := dx * dx + dy * dy
			if d2 > R2:
				continue
			if d2 <= r2 and not (m == 2 and d2 > r2 * 0.45 and r > 6) and not (m == STEEL and d2 > r2 * 0.2):
				set_cell(cx, cy, 0)
				any = true
				if randf() < 0.1:
					b.debris(cx * CELL + 2, cy * CELL + 2, m)
			elif r > 6:
				data[i * 2 + 1] = mini(255, data[i * 2 + 1] + 70)
				dirty = true
	if any:
		check_props(cause)
		check_floating(x, y, r + 8, cause)
		check_bridges(cause)

func bore(x: float, y0: float, y1: float, r: float) -> bool:
	## The Drill: clears every cell of any material inside an upright capsule from (x, y0) up to
	## (x, y1). No scorch and no steel exception. Returns whether anything was cut.
	var any := false
	for cy in range(int(floor((y1 - r) / CELL)), int(floor((y0 + r) / CELL)) + 1):
		for cx in range(int(floor((x - r) / CELL)), int(floor((x + r) / CELL)) + 1):
			if cx < 0 or cy < 0 or cx >= cols or cy >= ROWS:
				continue
			var i := cy * cols + cx
			var m := grid[i]
			if m == 0:
				continue
			var px := cx * CELL + 2.0
			var py := clampf(cy * CELL + 2.0, y1, y0)
			var dx := px - x
			var dy := cy * CELL + 2.0 - py
			if dx * dx + dy * dy <= r * r:
				set_cell(cx, cy, 0)
				any = true
				if randf() < 0.06:
					b.debris(px, cy * CELL + 2, m)
	return any

func _count(x: float, y: float, w: float, h: float) -> int:
	var n := 0
	for cy in range(int(floor(y / CELL)), int(ceil((y + h) / CELL))):
		for cx in range(int(floor(x / CELL)), int(ceil((x + w) / CELL))):
			if cx >= 0 and cy >= 0 and cx < cols and cy < ROWS and grid[cy * cols + cx] != 0:
				n += 1
	return n

func _severed(px: float, y0: float, y1: float) -> bool:
	## true when some row of the post between y0 and y1 has been shot clean through
	for cy in range(int(floor(y0 / CELL)), int(floor(y1 / CELL))):
		var any := false
		for cx in range(int(floor((px - 4) / CELL)), int(ceil((px + 4) / CELL))):
			if grid[cy * cols + cx]:
				any = true
		if not any:
			return true
	return false

func check_bridges(cause) -> void:
	## A bridge goes down as soon as any of its posts is shot through or half gone: the deck snaps free of
	## both banks and its posts and drops, with everything standing on it. The posts left
	## standing keep their cap, so the squad can hop across one post at a time.
	for s in bridges:
		if s.down:
			continue
		var weak := false
		for i in s.posts.size():
			var px: float = s.posts[i]
			if _count(px - 4, s.y + 8, 8, Data.WATER_Y + 12 - s.y - 8) < s.post_cells[i] * 0.5 or _severed(px, s.y + 12, Data.WATER_Y):
				weak = true
		if not weak:
			continue
		s.down = true
		for ex in [s.x0, s.x0 + CELL, s.x1 - CELL, s.x1 - 2 * CELL]:
			for k in 3:
				var cx := int(floor(ex / CELL))
				var cy := int(floor(s.y / CELL)) + k
				if cx >= 0 and cy >= 0 and cx < cols and cy < ROWS and grid[cy * cols + cx]:
					b.debris(cx * CELL + 2, cy * CELL + 2, grid[cy * cols + cx])
					set_cell(cx, cy, 0)
		# break the deck over every post so the planks fall between them instead of resting on them
		for px in s.posts:
			for cx in range(int(floor((px - 14) / CELL)), int(ceil((px + 14) / CELL))):
				var cy := int(floor(s.y / CELL))
				if randf() < 0.5 and grid[cy * cols + cx]:
					b.debris(cx * CELL + 2, cy * CELL + 2, 3)
			fill_r(px - 14, s.y, 28, 8, 0)
		b.bridge_down(s)
		check_floating((s.x0 + s.x1) / 2.0, s.y + 40, (s.x1 - s.x0) / 2.0 + 16, cause)

func check_floating(x: float, y: float, R: float, cause) -> void:
	vid += 1
	var c0 := maxi(0, int(floor((x - R) / CELL)))
	var c1 := mini(cols - 1, int(floor((x + R) / CELL)))
	var r0 := maxi(0, int(floor((y - R) / CELL)))
	var r1 := mini(ROWS - 1, int(floor((y + R) / CELL)))
	for cy in range(r0, r1 + 1):
		for cx in range(c0, c1 + 1):
			var i := cy * cols + cx
			if grid[i] != 0 and vstamp[i] != vid:
				flood(i, cause)

func flood(start: int, cause) -> void:
	var head := 0
	var tail := 0
	qbuf[tail] = start
	tail += 1
	vstamp[start] = vid
	var anchored := false
	while head < tail:
		var i := qbuf[head]
		head += 1
		var cy := i / cols
		var cx := i - cy * cols
		if cy >= WATER_ROW - 1 or pins.has(i):
			anchored = true  # the seabed holds up anything still joined to the bottom row of ground
			break
		for k in 4:
			var nb := -1
			if k == 0 and cx > 0: nb = i - 1
			elif k == 1 and cx < cols - 1: nb = i + 1
			elif k == 2 and cy > 0: nb = i - cols
			elif k == 3: nb = i + cols
			if nb < 0 or grid[nb] == 0:
				continue
			if vstamp[nb] == vid:
				if astamp[nb] == vid:
					anchored = true
				continue
			vstamp[nb] = vid
			qbuf[tail] = nb
			tail += 1
		if anchored or tail > FLOOD_LIMIT:
			anchored = true
			break
	if anchored:
		for k in tail:
			astamp[qbuf[k]] = vid
	else:
		detach(qbuf.slice(0, tail), cause)

func detach(cells: PackedInt32Array, cause) -> void:
	if cells.size() < 4:
		for i in cells:
			var cy := i / cols
			var cx := i - cy * cols
			b.debris(cx * CELL + 2, cy * CELL + 2, grid[i], true)
			set_cell(cx, cy, 0)
		return
	var x0 := 1 << 30
	var y0 := 1 << 30
	var x1 := -1
	var y1 := -1
	for i in cells:
		var cy := i / cols
		var cx := i - cy * cols
		x0 = mini(x0, cx); x1 = maxi(x1, cx); y0 = mini(y0, cy); y1 = maxi(y1, cy)
	var w := x1 - x0 + 1
	var h := y1 - y0 + 1
	var mask := PackedByteArray(); mask.resize(w * h)
	var sc := PackedByteArray(); sc.resize(w * h)
	for i in cells:
		var cy := i / cols
		var cx := i - cy * cols
		mask[(cy - y0) * w + (cx - x0)] = grid[i]
		sc[(cy - y0) * w + (cx - x0)] = data[i * 2 + 1]
		set_cell(cx, cy, 0)
	var c := make_chunk(x0, y0, w, h, mask, sc, cause)
	if cells.size() > 30:
		b.shake += 2

# ---------------------------------------------------------------- falling chunks
# A chunk is a small rigid body: it falls, slides, tips over edges and spins as it tumbles. It
# collides with the cell grid at the centres of its edge cells, and a hard landing splinters it
# into smaller pieces that fall on in turn. Once it comes to rest it is stamped back into the grid
# (at whatever angle it lies) and the area is re-checked, so a collapse can cascade.
const CH_E := 0.15          # bounce on a hard hit
const CH_MU := 0.7          # friction against the ground
const CH_BREAK := 4.6       # impact speed (px/tick) that splinters a 30-cell piece (about a 50px drop); big ones break sooner
const CH_CHIP := 30.0       # impact speed x sqrt(cells) at which a heavy piece also gouges what it hits
const CH_MAX := 48          # never more pieces than this in the air at once
const CH_LIFE := 300        # a piece still moving after this many ticks is set down where it is

func make_chunk(x0: int, y0: int, w: int, h: int, mask: PackedByteArray, sc: PackedByteArray, cause) -> Dictionary:
	## x0, y0: the world cell the mask's top-left cell came from (it also keeps the shader pattern stable).
	var n := 0
	var sx := 0.0
	var sy := 0.0
	for ry in h:
		for rx in w:
			if mask[ry * w + rx]:
				n += 1
				sx += rx * CELL + 2.0
				sy += ry * CELL + 2.0
	var com: Vector2 = Vector2(sx, sy) / maxf(1, n)
	var inertia := 0.0
	var edge: Array = []
	var steel := 0
	for ry in h:
		for rx in w:
			var m: int = mask[ry * w + rx]
			if not m:
				continue
			if m == STEEL:
				steel += 1
			var r: Vector2 = Vector2(rx * CELL + 2.0, ry * CELL + 2.0) - com
			inertia += r.length_squared() + CELL * CELL / 6.0
			if rx == 0 or ry == 0 or rx == w - 1 or ry == h - 1 or not mask[ry * w + rx - 1] or not mask[ry * w + rx + 1] \
					or not mask[(ry - 1) * w + rx] or not mask[(ry + 1) * w + rx]:
				edge.append(r)
	var c := {"x0": x0, "y0": y0, "w": w, "h": h, "mask": mask, "sc": sc, "n": n, "com": com, "edge": edge,
		"pos": Vector2(x0 * CELL, y0 * CELL) + com, "ang": 0.0, "vel": Vector2.ZERO, "av": 0.0,
		"inv_m": 1.0 / maxf(1, n), "inv_i": 1.0 / maxf(1.0, inertia), "rad": sqrt(w * w + h * h) * CELL / 2.0,
		"tough": 1.6 if steel * 2 > n else 1.0, "tall": h >= w * 1.4 and w >= 4 and h >= 8,
		"hit": {}, "cause": cause, "shake": 0, "life": 0, "rest": 0, "felt": -99, "drift": Vector2(INF, INF), "drift_ang": 0.0, "nudge": 0, "gen": 0, "thud": 0,
		"touch": [], "crack": null, "anchor": Vector2.ZERO, "gouged": -99, "anchor_ang": 0.0, "timber": false, "leaned": false, "dead": false, "node": null}
	chunks.append(c)
	b.chunk_created(c)
	return c

func chunk_from_cells(cells: Array, cause):
	cells = cells.filter(func(cl): return cl[0] >= 0 and cl[0] < cols and cl[1] < ROWS)
	if cells.size() < 4:
		return null
	var x0 := 1 << 30
	var y0 := 1 << 30
	var x1 := -(1 << 30)
	var y1 := -(1 << 30)
	for cl in cells:
		x0 = mini(x0, cl[0]); x1 = maxi(x1, cl[0]); y0 = mini(y0, cl[1]); y1 = maxi(y1, cl[1])
	var w := x1 - x0 + 1
	var h := y1 - y0 + 1
	var mask := PackedByteArray(); mask.resize(w * h)
	var sc := PackedByteArray(); sc.resize(w * h)
	for cl in cells:
		mask[(cl[1] - y0) * w + (cl[0] - x0)] = cl[2]
		sc[(cl[1] - y0) * w + (cl[0] - x0)] = cl[3]
	return make_chunk(x0, y0, w, h, mask, sc, cause)

func is_instance_valid_unit(u) -> bool:
	return u is Object and u.get("x") != null

func _normal_at(p: Vector2) -> Vector2:
	## Which way is "out of the ground" at p: away from the solid cells around it.
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	var g := Vector2.ZERO
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx == 0 and dy == 0:
				continue
			if solid((cx + dx) * CELL + 2, (cy + dy) * CELL + 2):
				g -= Vector2(dx, dy) / float(dx * dx + dy * dy)
	if g.length_squared() < 0.04:
		return Vector2.UP
	return g.normalized()

func _point_vel(c: Dictionary, r: Vector2) -> Vector2:
	return c.vel + Vector2(-c.av * r.y, c.av * r.x)

func _collide(c: Dictionary) -> void:
	var rot: Transform2D = Transform2D(c.ang, Vector2.ZERO)
	var pts: Array = []
	for e in c.edge:
		var wp: Vector2 = c.pos + rot * e
		if solid(wp.x, wp.y):
			pts.append(wp)
	c.touch = pts
	if pts.is_empty():
		return
	var ns: Array = []
	var push := Vector2.ZERO
	var deep := 0.0
	for wp in pts:
		var n: Vector2 = _normal_at(wp)
		ns.append(n)
		push += n
		var d: float = 1.0
		while d < 8 and solid(wp.x + n.x * d, wp.y + n.y * d):
			d += 1.0
		deep = maxf(deep, d)
	# how hard did it hit: the fastest closing speed at any contact, before the impulses soak it up
	var hard := 0.0
	var at: Vector2 = pts[0]
	var hitv := Vector2.ZERO
	for k in pts.size():
		var v: Vector2 = _point_vel(c, pts[k] - c.pos)
		var vn: float = -v.dot(ns[k])
		if vn > hard:
			hard = vn
			at = pts[k]
			hitv = v
	for it in 4:
		for k in pts.size():
			var n: Vector2 = ns[k]
			var r: Vector2 = pts[k] - c.pos
			var vp: Vector2 = _point_vel(c, r)
			var vn: float = vp.dot(n)
			if vn >= 0:
				continue
			var rn: float = r.x * n.y - r.y * n.x
			var j: float = -(1.0 + (CH_E if it == 0 and vn < -1.5 else 0.0)) * vn / (c.inv_m + rn * rn * c.inv_i)
			c.vel += n * j * c.inv_m
			c.av += rn * j * c.inv_i
			var t := Vector2(-n.y, n.x)
			vp = _point_vel(c, r)
			var rt: float = r.x * t.y - r.y * t.x
			var jt: float = clampf(-vp.dot(t) / (c.inv_m + rt * rt * c.inv_i), -CH_MU * j, CH_MU * j)
			c.vel += t * jt * c.inv_m
			c.av += rt * jt * c.inv_i
	# push it back out of the ground along the average contact normal
	if push.length_squared() < 0.01:
		push = Vector2.UP
	c.pos += push.normalized() * minf(deep, 3.0) * 0.8
	if hard > 2.5 and c.life - c.thud > 8:
		c.thud = c.life
		b.shake = minf(18, b.shake + sqrt(c.n) * hard * 0.1)
		Sfx.play("thud")
		for k in range(0, pts.size(), 3):
			b.dust(pts[k].x, pts[k].y, Color("c9b38a"), 2)
	# a tall piece landing on its foot is never perfectly true: give it the lean it was going to find
	if c.tall and c.gen == 0 and absf(c.ang) < 0.1 and hard > 1.0 and not c.leaned:
		c.leaned = true
		c.av += _lean_dir(c) * (0.004 + randf() * 0.004)
	# fall damage: the bigger the piece, the less of a drop it takes to break it
	var stress: float = hard * pow(c.n / 30.0, 0.25) / c.tough
	if stress > CH_BREAK and c.crack == null and c.n >= 10 and c.gen < 3:
		c.crack = {"at": at, "hard": stress}
	if hard * sqrt(c.n) > CH_CHIP and c.n >= 30 and c.gen < 2 and c.life - c.gouged > 10:
		c.gouged = c.life
		_gouge(at, hard * sqrt(c.n), hitv, c.cause)

func _lean_dir(c: Dictionary) -> float:
	## Tip toward the side the centre of mass already favours over the contacts, else away from whoever caused it.
	var lo := INF
	var hi := -INF
	for p in c.touch:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	if lo < INF and absf(c.pos.x - (lo + hi) / 2.0) > 1:
		return signf(c.pos.x - (lo + hi) / 2.0)
	if c.cause != null and is_instance_valid_unit(c.cause) and c.cause.x != c.pos.x:
		return signf(c.pos.x - c.cause.x)
	return 1.0 if randf() < 0.5 else -1.0

func _gouge(at: Vector2, force: float, hitv: Vector2, cause) -> void:
	## A heavy piece coming down hard breaks off a lump of whatever it hits and knocks it along,
	## and anything that lump was holding up comes down after it.
	var r: float = minf(18.0, 6.0 + (force - CH_CHIP) / 3.0)
	var cells: Array = []
	for cy in range(int(floor((at.y - r) / CELL)), int(floor((at.y + r) / CELL)) + 1):
		for cx in range(int(floor((at.x - r) / CELL)), int(floor((at.x + r) / CELL)) + 1):
			if cx < 0 or cy < 0 or cx >= cols or cy >= WATER_ROW - 1:
				continue
			var i: int = cy * cols + cx
			var m: int = grid[i]
			# plain ground holds unless the hit is huge; riveted steel always holds
			if m == 0 or m == STEEL or pins.has(i) or (m == 1 and force < 80):
				continue
			if Vector2(cx * CELL + 2, cy * CELL + 2).distance_to(at) <= r and randf() < 0.8:
				cells.append([cx, cy, m, data[i * 2 + 1]])
				set_cell(cx, cy, 0)
	if cells.is_empty():
		return
	if cells.size() < 4 or chunks.size() >= CH_MAX:
		for cl in cells:
			b.debris(cl[0] * CELL + 2, cl[1] * CELL + 2, cl[2])
	else:
		var nc = chunk_from_cells(cells, cause)
		if nc != null:
			nc.vel = hitv * 0.4
			nc.shake = 6
			nc.gen = 2
	check_floating(at.x, at.y, r + 40, cause)

func _splinter(c: Dictionary) -> void:
	## Break a piece that hit too hard into 2-6 smaller ones along jagged cracks; crumbs near the impact turn to dust.
	var cr: Dictionary = c.crack
	var hard: float = cr.hard
	var inv: Transform2D = Transform2D(c.ang, c.pos).affine_inverse()
	var hit_l: Vector2 = inv * cr.at + c.com   # impact point in mask pixels
	var w: int = c.w
	var cells: Array = []
	for i in c.mask.size():
		if c.mask[i]:
			cells.append(i)
	var k: int = clampi(2 + int((hard - CH_BREAK) / 1.6) + (1 if c.n > 160 else 0), 2, 6)
	k = mini(k, cells.size() / 5)
	if k < 2 or chunks.size() + k > CH_MAX:
		return
	var seeds: Array = []
	for s in k:
		var i: int = cells[randi() % cells.size()]
		seeds.append(Vector2(i % w, i / w) * CELL + Vector2(2, 2))
	var dust_r: float = 3.0 + hard * 0.8
	var part := PackedInt32Array(); part.resize(c.mask.size()); part.fill(-1)
	var dusted := 0
	for i in cells:
		var p: Vector2 = Vector2(i % w, i / w) * CELL + Vector2(2, 2)
		if p.distance_to(hit_l) < dust_r and randf() < 0.6:
			if dusted % 2 == 0:
				var wp: Vector2 = Transform2D(c.ang, c.pos) * (p - c.com)
				b.debris(wp.x, wp.y, c.mask[i])
			dusted += 1
			continue
		var best := 0
		var bd := INF
		for s in k:
			var d: float = p.distance_to(seeds[s]) + hash2(c.x0 * 7 + i % w, c.y0 * 13 + i / w) * 6.0
			if d < bd:
				bd = d
				best = s
		part[i] = best
	# every connected run of cells inside one region becomes its own piece
	var seen := PackedByteArray(); seen.resize(c.mask.size())
	var rot: Transform2D = Transform2D(c.ang, Vector2.ZERO)
	var made := 0
	for i0 in cells:
		if part[i0] < 0 or seen[i0]:
			continue
		var reg: int = part[i0]
		var comp: Array = [i0]
		seen[i0] = 1
		var h: int = 0
		while h < comp.size():
			var i: int = comp[h]
			h += 1
			var x: int = i % w
			for nb in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
				if nb >= 0 and nb < part.size() and not seen[nb] and part[nb] == reg:
					seen[nb] = 1
					comp.append(nb)
		if comp.size() < 4:
			for i in comp:
				var wp: Vector2 = c.pos + rot * (Vector2(i % w, i / w) * CELL + Vector2(2, 2) - c.com)
				b.debris(wp.x, wp.y, c.mask[i], true)
			continue
		var bx0 := 1 << 30
		var by0 := 1 << 30
		var bx1 := -1
		var by1 := -1
		for i in comp:
			bx0 = mini(bx0, i % w); bx1 = maxi(bx1, i % w); by0 = mini(by0, i / w); by1 = maxi(by1, i / w)
		var nw: int = bx1 - bx0 + 1
		var nh: int = by1 - by0 + 1
		var mask := PackedByteArray(); mask.resize(nw * nh)
		var sc := PackedByteArray(); sc.resize(nw * nh)
		for i in comp:
			var j: int = (i / w - by0) * nw + (i % w - bx0)
			mask[j] = c.mask[i]
			sc[j] = c.sc[i]
		var nc: Dictionary = make_chunk(c.x0 + bx0, c.y0 + by0, nw, nh, mask, sc, c.cause)
		# place it where it sat inside the parent, moving the way that part of the parent was moving
		var off: Vector2 = Vector2(bx0, by0) * CELL + nc.com - c.com
		var r: Vector2 = rot * off
		nc.pos = c.pos + r
		nc.ang = c.ang
		var away: Vector2 = r.normalized() if r.length_squared() > 1 else Vector2(randf() - 0.5, -1).normalized()
		nc.vel = _point_vel(c, r) * 0.6 + away * (0.3 + randf() * 0.3 + hard * 0.04) + Vector2(0, -0.2 - randf() * 0.3)
		nc.av = c.av * 0.6 + (randf() - 0.5) * 0.03
		nc.hit = c.hit.duplicate()
		nc.shake = 6
		nc.gen = c.gen + 1
		nc.timber = true
		nc.thud = 0
		made += 1
	c.dead = true
	Sfx.play("thud")
	b.shake = minf(18, b.shake + 3 + made)
	if c.n > 40 and c.gen == 0:
		b.float_at(cr.at.x, cr.at.y - 16, "CRUMBLE!", Color("e8dcc2"), true)

func update_chunk(c: Dictionary) -> void:
	c.shake += 1
	if c.shake < 6:
		return  # a beat of creak before it drops
	c.life += 1
	c.vel.y += Data.GRAV
	if c.vel.length() > 10:
		c.vel = c.vel.normalized() * 10
	c.av = clampf(c.av * (0.9 if c.touch.size() else 0.997), -0.15, 0.15)  # scraping along the ground soaks up spin
	var sub: int = clampi(int(ceil(maxf(c.vel.length(), absf(c.av) * c.rad) / 2.0)), 1, 6)
	var touched := false
	var feet: Array = []
	for s in sub:
		c.pos += c.vel / sub
		c.ang += c.av / sub
		_collide(c)
		touched = touched or c.touch.size() > 0
		feet.append_array(c.touch)
		if c.crack != null:
			_splinter(c)
			if c.dead:
				return
			c.crack = null
	if c.tall and not c.timber and absf(c.ang) > 0.2:
		c.timber = true
		Sfx.play("thud")
		b.float_at(c.pos.x, c.pos.y - c.h * CELL / 2.0 - 10, "TIMBER!", Color("ffd23a"), true)
	if c.pos.y > Data.WATER_Y + 8 or c.pos.y > Data.H + 40:
		b.splash(c.pos.x)
		if c.n > 20:
			b.splash(c.pos.x + c.w * CELL / 4.0)
		c.dead = true
		return
	_crush_units(c)
	# at rest once it has sat on something without going anywhere for a few ticks. A piece sitting on
	# the ground hops a pixel off its contacts every other tick, so a recent touch counts as touching.
	if touched:
		c.felt = c.life
	if c.life - c.felt < 8 and c.pos.distance_to(c.anchor) < 1.5 and absf(c.ang - c.anchor_ang) < 0.1:
		c.rest += 1
	else:
		c.rest = 0
		c.anchor = c.pos
		c.anchor_ang = c.ang
	if c.rest >= 12:
		# no perfect balancing acts: a piece resting with its weight right at the edge of what holds it goes over
		var lo := INF
		var hi := -INF
		for p in feet:
			lo = minf(lo, p.x)
			hi = maxf(hi, p.x)
		var margin: float = maxf(2.0, (hi - lo) * 0.2)
		if c.n >= 8 and c.nudge < 6 and (c.pos.x < lo + margin or c.pos.x > hi - margin):
			c.nudge += 1
			c.rest = 0
			c.anchor = Vector2(INF, INF)
			c.av += signf(c.pos.x - (lo + hi) / 2.0) * 0.012
			c.vel.x += signf(c.pos.x - (lo + hi) / 2.0) * 0.3
			return
		settle_chunk(c)
	elif c.life > CH_LIFE:
		settle_chunk(c)
	elif c.life % 30 == 0:
		# small pieces can rock and shuffle in place on their contacts for ages: if it has been on the
		# ground and gone nowhere in half a second, it is rubble
		if c.life - c.felt < 8 and c.pos.distance_to(c.drift) < 3.0 and absf(c.ang - c.drift_ang) < 0.15:
			settle_chunk(c)
			return
		c.drift = c.pos
		c.drift_ang = c.ang

func _crush_units(c: Dictionary) -> void:
	var inv: Transform2D = Transform2D(c.ang, c.pos).affine_inverse()
	var w: int = c.w
	for u in b.units:
		if u.dead or u.gone or u.sunk or u.kind == "pow" or c.hit.has(u.id):
			continue
		if absf(u.x - c.pos.x) > c.rad + u.w or absf(u.y - c.pos.y) > c.rad + u.h:
			continue
		var xs: Array = [u.x - u.w / 3.0, u.x, u.x + u.w / 3.0] if u.w > 40 else [u.x]
		var done := false
		for ux in xs:
			for py in [u.y - u.h + 3, u.y - u.h * 0.5]:
				var l: Vector2 = inv * Vector2(ux, py) + c.com
				var lx: int = int(floor(l.x / CELL))
				var ly: int = int(floor(l.y / CELL))
				if lx < 0 or ly < 0 or lx >= w or ly >= c.h or not c.mask[ly * w + lx]:
					continue
				c.hit[u.id] = true
				var vp: Vector2 = _point_vel(c, Vector2(ux, py) - c.pos)
				var sp: float = vp.length()
				if sp > 1.2:
					var d: int = clampi(int(round(sqrt(c.n) * sp * 0.45)), 3, 50)
					var kvx: float = signf(vp.x) * 4.0 if absf(vp.x) > 1 else (-1.0 if u.x < c.pos.x else 1.0) * 3.5
					b.crush(u, d, c.cause, kvx, 1.0 if vp.y > absf(vp.x) else -1.0)
				done = true
				break
			if done:
				break

func settle_chunk(c: Dictionary) -> void:
	## Stamp the resting piece back into the grid at the angle it came to rest, then look for anything it left hanging.
	var ang: float = c.ang
	var q: float = roundf(ang / (PI / 2)) * (PI / 2)
	if absf(ang - q) < 0.12:
		ang = q  # near enough square: lay it square
	var xf: Transform2D = Transform2D(ang, c.pos)
	var inv: Transform2D = xf.affine_inverse()
	var w: int = c.w
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in 4:
		var p: Vector2 = xf * (Vector2(w * CELL if k & 1 else 0, c.h * CELL if k & 2 else 0) - c.com)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	# debris that came down on a vehicle shatters; elsewhere it settles around bodies instead of lifting them
	var shatter := false
	for u in b.units:
		if c.hit.has(u.id) and u.w > 40:
			shatter = true
	var boxes: Array = b.units.filter(func(u): return not u.dead and not u.gone and not u.sunk and u.kind != "pow")
	for cy in range(int(floor(lo.y / CELL)), int(ceil(hi.y / CELL)) + 1):
		for cx in range(int(floor(lo.x / CELL)), int(ceil(hi.x / CELL)) + 1):
			if cx < 0 or cy < 0 or cx >= cols or cy >= ROWS:
				continue
			var wx := cx * CELL + 2.0
			var wy := cy * CELL + 2.0
			var l: Vector2 = inv * Vector2(wx, wy) + c.com
			var lx: int = int(floor(l.x / CELL))
			var ly: int = int(floor(l.y / CELL))
			if lx < 0 or ly < 0 or lx >= w or ly >= c.h:
				continue
			var m: int = c.mask[ly * w + lx]
			if not m:
				continue
			var inside := shatter
			if not inside:
				for u in boxes:
					if wx > u.x - u.w / 2.0 - 2 and wx < u.x + u.w / 2.0 + 2 and wy > u.y - u.h and wy < u.y:
						inside = true
						break
			if inside:
				if randf() < 0.25:
					b.debris(wx, wy, m)
				continue
			var i: int = cy * cols + cx
			if not grid[i]:
				set_cell(cx, cy, m)
				data[i * 2 + 1] = c.sc[ly * w + lx]
	for u in b.units:
		if u.dead or u.gone or u.sunk:
			continue
		var k := 0
		while solid(u.x, u.y - 2) and k < 30:
			u.y -= CELL
			k += 1
	c.dead = true
	check_floating(c.pos.x, c.pos.y, c.rad + 8, c.cause)

var chunk_usec := 0  # time spent moving falling pieces, for the crumble test

func chunks_falling() -> bool:
	## True while any piece is still dropping, sliding or spinning. Rubble that has landed and is only
	## rocking on its contacts doesn't count: the turn goes on while it beds down.
	for c in chunks:
		if c.shake < 6 or c.life - c.felt >= 8 or c.vel.length() > 0.8 or absf(c.av) > 0.06:
			return true
	return false

func update_chunks() -> void:
	var t0 := Time.get_ticks_usec()
	for c in chunks.duplicate():
		update_chunk(c)
	chunk_usec += Time.get_ticks_usec() - t0
	var keep: Array = []
	for c in chunks:
		if c.dead:
			b.chunk_removed(c)
		else:
			keep.append(c)
	chunks = keep

func paint_cells(x: float, y: float, w: float, h: float) -> void:
	dirty = true

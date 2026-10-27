class_name Terrain
extends RefCounted
## Destructible cell terrain: generation, carving, and the collapse simulation
## (unsupported pieces detach into falling chunks that crush whatever is below).

const CELL := 4
const ROWS := 135
const FLOOD_LIMIT := 5000

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
var camps: Array = []    # safe camps inside the level: {x0, x1, used}

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
		if solid(x, y) and not solid(x, y - 1):
			return y
		y += CELL
	return null

# ---------------------------------------------------------------- generation
func build(mission: Dictionary) -> void:
	# lay segments end to end
	var x := 0
	var shapes: Array = []
	var open_pits: Array = []
	pits.clear(); sandbags.clear(); structs.clear(); spawns.clear(); ladders.clear(); bridges.clear(); camps.clear()
	arena_x = 1 << 20  # outposts have no arena
	var rules: Dictionary = mission.get("rules", {})
	var stretches: Array = []   # fighting stretches, where a biome's extra fuel and mines go
	for sname in mission.segments:
		var s: Dictionary = Data.SEGMENTS[sname]
		if sname != "start" and not s.get("camp", false) and not s.get("flat", false):
			stretches.append([x + 60, x + s.w - 60])
		if s.get("flat", false):
			arena_x = x
		if s.get("camp", false):
			camps.append({"x0": x, "x1": x + s.w, "fire": x + s.w / 2, "used": false})
		for p in s.pits:
			pits.append([p[0] + x, p[1] + x])
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
			if t.t == "bridge" or t.t == "docks":
				pits.append([t.x0, t.x1])
				open_pits.append([t.x0, t.x1])
			structs.append(t)
		for sp in s.spawns:
			spawns.append([sp[0], sp[1] + x, sp[2] if sp.size() > 2 else {}])
		x += s.w
	for k in ["fuel", "mines"]:
		for i in int(rules.get(k, 0)):
			if stretches.is_empty():
				break
			var st: Array = stretches[randi() % stretches.size()]
			var sx := randf_range(st[0], st[1])
			for tries in 8:
				if not pits.any(func(p): return sx > p[0] - 24 and sx < p[1] + 24):
					break
				sx = randf_range(st[0], st[1])
			spawns.append(["fuel" if k == "fuel" else "mine", sx, {}])
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
		for cy in range(top, ROWS):
			set_cell(cx, cy, 4 if cy > deep else 1)
	for p in pits:
		if open_pits.has(p):
			continue
		var y := ground_at(p[0] - 12)
		fill_r(p[0] - 8, y, p[1] - p[0] + 16, 8, 3)
	for s in structs:
		build_struct(s)
	for sx in sandbags:
		# the top sits one step above the ground just before the bags, so a soldier walking up
		# a slope can still hop them; the bottom reaches down to wherever the ground under them is
		var g := ground_at(sx - CELL)
		var deep := maxf(maxf(ground_at(sx), ground_at(sx + 10)), ground_at(sx + 19))
		fill_r(sx, g - 12, 20, maxf(24, deep - g + 12), 2)
	img = Image.create_from_data(cols, ROWS, false, Image.FORMAT_RG8, data)
	tex = ImageTexture.create_from_image(img)
	dirty = false

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
			# a plank deck flush with both banks, held up only by its posts. The posts stop short of
			# the riverbed, so the deck hangs off the banks; check_bridges cuts it loose.
			var g := ground_at(s.x0 - 12)
			s["y"] = g
			s["down"] = false
			fill_r(s.x0, g, s.x1 - s.x0, 8, 3)
			s["post_cells"] = []
			for px in s.posts:
				fill_r(px - 4, g + 8, 8, Data.WATER_Y + 12 - g - 8, 3)
				fill_r(px - 8, g + 8, 16, 4, 3)
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
			if d2 <= r2 and not (m == 2 and d2 > r2 * 0.45 and r > 6):
				set_cell(cx, cy, 0)
				any = true
				if randf() < 0.1:
					b.debris(cx * CELL + 2, cy * CELL + 2, m)
			elif r > 6:
				data[i * 2 + 1] = mini(255, data[i * 2 + 1] + 70)
				dirty = true
	if any:
		check_floating(x, y, r + 8, cause)
		check_bridges(cause)

func _count(x: float, y: float, w: float, h: float) -> int:
	var n := 0
	for cy in range(int(floor(y / CELL)), int(ceil((y + h) / CELL))):
		for cx in range(int(floor(x / CELL)), int(ceil((x + w) / CELL))):
			if cx >= 0 and cy >= 0 and cx < cols and cy < ROWS and grid[cy * cols + cx] != 0:
				n += 1
	return n

func check_bridges(cause) -> void:
	## A bridge goes down as soon as any of its posts is half gone: the deck snaps free of
	## both banks and drops, with everything standing on it.
	for s in bridges:
		if s.down:
			continue
		var weak := false
		for i in s.posts.size():
			var px: float = s.posts[i]
			if _count(px - 4, s.y + 8, 8, Data.WATER_Y + 12 - s.y - 8) < s.post_cells[i] * 0.5:
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
		if cy >= ROWS - 1:
			anchored = true
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

func make_chunk(x0: int, y0: int, w: int, h: int, mask: PackedByteArray, sc: PackedByteArray, cause) -> Dictionary:
	var bottoms: Array = []
	var n := 0
	for ry in h:
		for rx in w:
			if mask[ry * w + rx]:
				n += 1
				if ry == h - 1 or not mask[(ry + 1) * w + rx]:
					bottoms.append(Vector2i(rx, ry))
	var c := {"x0": x0, "y0": y0, "w": w, "h": h, "mask": mask, "sc": sc, "oy": 0.0, "vy": 0.0, "n": n,
		"bottoms": bottoms, "hit": {}, "cause": cause, "shake": 0, "tip": null, "tipN": 0, "topple": null, "dead": false, "node": null}
	chunks.append(c)
	b.chunk_created(c)
	return c

func chunk_fits(c: Dictionary, x0: int, oy: float) -> bool:
	var d0 := int(floor(oy / CELL))
	var d1 := int(ceil(oy / CELL))
	var w: int = c.w
	for ry in c.h:
		for rx in w:
			if not c.mask[ry * w + rx]:
				continue
			var cx: int = x0 + rx
			if cx < 0 or cx >= cols:
				return false
			for d in [d0, d1]:
				var cy: int = c.y0 + ry + d
				if cy >= 0 and cy < ROWS and grid[cy * cols + cx]:
					return false
	return true

func _com_dir(c: Dictionary, cols_hit: Dictionary) -> int:
	var sx := 0.0
	var n := 0
	for i in c.mask.size():
		if c.mask[i]:
			sx += i % int(c.w)
			n += 1
	var com := sx / maxf(1, n)
	var mid := 0.0
	for k in cols_hit:
		mid += k
	mid /= cols_hit.size()
	if absf(com - mid) > 1:
		return int(signf(com - mid))
	if c.cause != null and is_instance_valid_unit(c.cause):
		var s := signf((c.x0 + c.w / 2.0) * CELL - c.cause.x)
		return int(s) if s != 0 else 1
	return 1

func is_instance_valid_unit(u) -> bool:
	return u is Object and u.get("x") != null

func update_chunk(c: Dictionary) -> void:
	c.shake += 1
	if c.shake < 6:
		return  # a beat of creak before it drops
	if c.topple != null:
		update_topple(c)
		return
	c.vy = minf(c.vy + Data.GRAV, 10)
	var move: float = c.vy
	while move > 0:
		var st := minf(2, move)
		move -= st
		var noy: float = c.oy + st
		var hit := false
		var cols_hit := {}
		for bt in c.bottoms:
			var py: float = (c.y0 + bt.y + 1) * CELL + noy - 0.01
			if py >= Data.H:
				continue
			if solid((c.x0 + bt.x) * CELL + 2, py):
				hit = true
				cols_hit[bt.x] = true
		if hit:
			# a tall piece caught on a narrow stub topples over instead of balancing there
			if c.tip == null and c.h >= c.w * 1.4 and c.w >= 5 and cols_hit.size() <= 3:
				var dir := _com_dir(c, cols_hit)
				var by := 0
				for bt in c.bottoms:
					if cols_hit.has(bt.x):
						by = maxi(by, bt.y)
				var ks: Array = cols_hit.keys()
				var px: float = (c.x0 + (ks.max() + 1 if dir > 0 else ks.min())) * CELL
				c.topple = {"dir": dir, "rot": 0.0, "rv": 0.004, "px": px, "py": (c.y0 + by + 1) * CELL + c.oy}
				Sfx.play("thud")
				b.float_at((c.x0 + c.w / 2.0) * CELL, c.y0 * CELL - 10, "TIMBER!", Color("ffd23a"), true)
				return
			if c.tip == null and c.w >= 8 and cols_hit.size() <= 3 and c.oy < 20:
				c.tip = _com_dir(c, cols_hit)
				c.tipN = 0
			if c.tip != null and c.tip != 0 and c.tipN < c.w + 4 and chunk_fits(c, c.x0 + c.tip, c.oy):
				c.x0 += c.tip
				c.tipN += 1
				c.vy = minf(c.vy, 1)
				return
			c.oy = noy
			land_chunk(c)
			return
		c.oy = noy
	if c.y0 * CELL + c.oy > Data.WATER_Y:
		b.splash((c.x0 + c.w / 2.0) * CELL)
		if c.n > 20:
			b.splash((c.x0 + c.w / 4.0) * CELL)
		c.dead = true
		return
	for u in b.units:
		if u.dead or u.gone or u.sunk or u.kind == "pow" or c.hit.has(u.id):
			continue
		var xs: Array = [u.x - u.w / 3.0, u.x, u.x + u.w / 3.0] if u.w > 40 else [u.x]
		var done := false
		for ux in xs:
			var lx: int = int(floor(ux / CELL)) - c.x0
			if lx < 0 or lx >= c.w:
				continue
			for py in [u.y - u.h + 3, u.y - u.h * 0.5]:
				var ly: int = int(floor((py - c.oy) / CELL)) - c.y0
				if ly >= 0 and ly < c.h and c.mask[ly * c.w + lx]:
					c.hit[u.id] = true
					if c.vy > 1.2:
						var d := clampi(int(round(sqrt(c.n) * c.vy * 0.45)), 3, 50)
						b.crush(u, d, c.cause, (-1 if u.x < (c.x0 + c.w / 2.0) * CELL else 1) * 3.5, 1.0)
					done = true
					break
			if done:
				break

func update_topple(c: Dictionary) -> void:
	var t: Dictionary = c.topple
	t.rv = minf(t.rv + 0.0035, 0.09)
	t.rot += t.rv
	var a: float = t.dir * minf(t.rot, PI / 2)
	var ca := cos(a)
	var sa := sin(a)
	for u in b.units:
		if u.dead or u.gone or u.sunk or u.kind == "pow" or c.hit.has(u.id):
			continue
		for py in [u.y - u.h + 3, u.y - u.h * 0.5]:
			var rx: float = u.x - t.px
			var ry: float = py - t.py
			var lx := rx * ca + ry * sa
			var ly := -rx * sa + ry * ca
			var mx: int = int(floor((lx + t.px) / CELL)) - c.x0
			var my: int = int(floor((ly + t.py - c.oy) / CELL)) - c.y0
			if mx >= 0 and mx < c.w and my >= 0 and my < c.h and c.mask[my * c.w + mx]:
				c.hit[u.id] = true
				var sp := maxf(2, t.rv * Vector2(rx, ry).length())
				var d := clampi(int(round(sqrt(c.n) * sp * 0.45)), 3, 50)
				b.crush(u, d, c.cause, t.dir * 4.0, -1.0)
				break
	if t.rot < PI / 2:
		return
	# lay it down: rotate every cell a quarter turn about the pivot, then drop it as a normal chunk
	var cells: Array = []
	for ry in c.h:
		for rx in c.w:
			var m: int = c.mask[ry * c.w + rx]
			if not m:
				continue
			var wx: float = (c.x0 + rx) * CELL + 2 - t.px
			var wy: float = (c.y0 + ry) * CELL + 2 + c.oy - t.py
			var nx: float = t.px + (-wy if t.dir > 0 else wy)
			var ny: float = t.py + (wx if t.dir > 0 else -wx)
			cells.append([int(floor(nx / CELL)), int(floor(ny / CELL)), m, c.sc[ry * c.w + rx]])
	var lift := 0
	while lift < 40 and _blocked(cells, lift):
		lift += 1
	c.dead = true
	for cl in cells:
		cl[1] -= lift
	var nc = chunk_from_cells(cells, c.cause)
	if nc != null:
		nc.hit = c.hit
		nc.shake = 6
		nc.vy = 2.0
		nc.tip = 0
	b.shake += 6
	Sfx.play("thud")

func _blocked(cells: Array, k: int) -> bool:
	for cl in cells:
		var cx: int = cl[0]
		var cy: int = cl[1] - k
		if cx < 0 or cx >= cols:
			return true
		if cy >= 0 and cy < ROWS and grid[cy * cols + cx]:
			return true
	return false

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
	var c := make_chunk(x0, y0, w, h, mask, sc, cause)
	c.tip = 0
	return c

func land_chunk(c: Dictionary) -> void:
	var dy := maxi(0, int(floor((c.oy - 0.01) / CELL)))
	var s := dy * CELL
	# debris that came down on a vehicle shatters; elsewhere it settles around bodies instead of lifting them
	var shatter := false
	for u in b.units:
		if c.hit.has(u.id) and u.w > 40:
			shatter = true
	var boxes: Array = b.units.filter(func(u): return not u.dead and not u.gone and not u.sunk and u.kind != "pow")
	for ry in c.h:
		for rx in c.w:
			var m: int = c.mask[ry * c.w + rx]
			if not m:
				continue
			var cx: int = c.x0 + rx
			var cy: int = c.y0 + ry + dy
			if cx < 0 or cy < 0 or cx >= cols or cy >= ROWS:
				continue
			var wx := cx * CELL + 2.0
			var wy := cy * CELL + 2.0
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
			var i := cy * cols + cx
			if not grid[i]:
				set_cell(cx, cy, m)
				data[i * 2 + 1] = c.sc[ry * c.w + rx]
	if c.vy > 2.5:
		b.shake = minf(18, b.shake + sqrt(c.n) * c.vy * 0.12)
		Sfx.play("thud")
		for k in range(0, c.bottoms.size(), 3):
			var bt: Vector2i = c.bottoms[k]
			b.dust((c.x0 + bt.x) * CELL + 2, (c.y0 + bt.y + 1) * CELL + s, Color("c9b38a"), 2)
	for u in b.units:
		if u.dead or u.gone or u.sunk:
			continue
		var k := 0
		while solid(u.x, u.y - 2) and k < 30:
			u.y -= CELL
			k += 1
	c.dead = true
	check_floating((c.x0 + c.w / 2.0) * CELL, (c.y0 + c.h / 2.0) * CELL + s, maxf(c.w, c.h) * CELL / 2.0 + 8, c.cause)

func update_chunks() -> void:
	for c in chunks.duplicate():
		update_chunk(c)
	var keep: Array = []
	for c in chunks:
		if c.dead:
			b.chunk_removed(c)
		else:
			keep.append(c)
	chunks = keep

func paint_cells(x: float, y: float, w: float, h: float) -> void:
	dirty = true

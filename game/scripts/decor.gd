extends Node2D
## Ground life drawn between the terrain and the units: grass that sways in the wind and
## parts around boots, set dressing (tents, signs, lamps, campfires), flags on the towers,
## and critters that peck about until gunfire or a soldier sends them scattering.
## Purely cosmetic: nothing here touches the simulation.

@onready var b: Battle = get_parent()

var tops := PackedInt32Array()   # per terrain column: first solid row, -1 = not read yet
var tops_rev := -1
var props: Array = []            # {kind, x, y}
var flags: Array = []            # {x, y, px, py}: flag pole base and the post that holds it
var crits: Array = []
var last_t := 0
var spawn_cd := 0
var tex := {}
var flower_cols: Array = []
var fire_cd := 90
var bursts: Array = []           # pending cosmetic shots: {u, tg, at}
var posts: Array = []            # W11: friendly sandbag posts on ground the company holds: {x, y, guards}
var liberated := false

const CRIT_ROW := {"crow": 0, "gull": 1, "parrot": 2, "frog": 3, "rat": 4, "fly": 5}
const SCARE := 64.0

func _ready() -> void:
	for n in ["tent", "sign", "lamp", "logs", "drum", "flag", "reeds"]:
		tex[n] = load("res://assets/sprites/dc_%s.png" % n)
	tex.crit = load("res://assets/sprites/critters.png")

func setup() -> void:
	var T: Terrain = b.T
	tops = PackedInt32Array()
	tops.resize(T.cols)
	tops.fill(-1)
	tops_rev = T.rev
	flower_cols = {"dusk": [Color("ffd23a"), Color("ece6d0")], "jungle": [Color("ff5a7a"), Color("ffb23e"), Color("e8e0ff")], "night": [Color("9fb4e8"), Color("d8e0f0")]}[b.theme]
	for s in T.structs:
		if s.t == "tower":
			var top: float = T.ground_at(s.x) - s.h
			flags.append({"x": s.x + 21.0, "y": top - 16, "px": s.x + 21.0, "py": top - 12})
	place_props()
	liberated = b.mission.get("liberated", false)
	if liberated:
		# W11: held ground looks held. A garrison post at the start, more up the line, company flags.
		for x in [70.0, b.world_w * 0.35, b.world_w * 0.65]:
			var y := surface(x)
			if y > 0:
				posts.append({"x": x, "y": y, "guards": 2 if x < 100 else 1})
	# a few critters already about when the mission opens
	for i in 4:
		spawn_critter(b.cam_x + 260 + i * 170 + randf() * 80)

func busy_spot(x: float, pad: float) -> bool:
	var T: Terrain = b.T
	if x < 260 or x > T.world_w - 120:
		return true
	for L in T.ladders:
		if absf(L.x - x) < pad or absf(L.offx - x) < pad:
			return true
	for s in T.structs:
		for k in ["x", "px", "x0", "x1", "col", "bx", "post"]:
			if s.has(k) and absf(s[k] - x) < pad + 20:
				return true
	for p in T.pits:
		if x > p[0] - pad and x < p[1] + pad:
			return true
	for sb in T.sandbags:
		if absf(sb - x) < pad:
			return true
	for sp in T.spawns:
		if absf(sp[1] - x) < pad * 0.6:
			return true
	return false

func place_props() -> void:
	var T: Terrain = b.T
	var kinds: Array = {"dusk": ["sign", "drum", "camp", "tent", "drum"],
		"jungle": ["camp", "tent", "sign", "drum"],
		"night": ["lamp", "drum", "camp", "lamp", "sign"]}[b.theme]
	var x := 320.0
	var i := 0
	while x < T.world_w - 200:
		var k: String = kinds[int(Terrain.hash2(int(x), 5) * kinds.size())]
		var pad := 40.0 if k in ["tent", "camp"] else 26.0
		if not busy_spot(x, pad):
			var y := surface(x)
			var flat := absf(surface(x - 12) - y) <= 4 and absf(surface(x + 12) - y) <= 4
			if y > 0 and flat and T.mat(x, y + 2) == 1:
				props.append({"kind": k, "x": x, "y": y})
				if k == "tent":
					props.append({"kind": "camp", "x": x + 46, "y": surface(x + 46)})
				x += 260 + Terrain.hash2(i, 9) * 260
				i += 1
				continue
		x += 40
	# reeds along the banks of every pit
	if b.theme != "night":
		for p in T.pits:
			for ex in [p[0] - 14.0, p[1] + 14.0, p[0] + 10.0, p[1] - 10.0]:
				var y := surface(ex)
				if y > 0:
					props.append({"kind": "reeds", "x": ex, "y": y})

# ---------------------------------------------------------------- surface lookup
func top_row(cx: int) -> int:
	var T: Terrain = b.T
	if cx < 0 or cx >= T.cols:
		return -1
	if T.rev != tops_rev:
		tops.fill(-1)
		tops_rev = T.rev
	var r := tops[cx]
	if r == -1:
		r = Terrain.ROWS
		for y in Terrain.ROWS:
			if T.grid[y * T.cols + cx] != 0:
				r = y
				break
		tops[cx] = r
	return r

func surface(x: float) -> float:
	## World y of the highest solid cell in this column, or -1 if the column is open to the water.
	var r := top_row(int(floor(x / Terrain.CELL)))
	if r < 0 or r >= Terrain.ROWS or r * Terrain.CELL >= Battle.WATER_Y:
		return -1.0
	return float(r * Terrain.CELL)

# ---------------------------------------------------------------- update
func _process(_d: float) -> void:
	if b.T == null:
		return
	if tops.is_empty():
		setup()
	var steps := mini(b.t - last_t, 6)
	last_t = b.t
	for i in steps:
		step()
	queue_redraw()

func step() -> void:
	spawn_cd -= 1
	if spawn_cd <= 0:
		spawn_cd = 150 + randi() % 150
		var n := crits.filter(func(c): return c.st == "idle").size()
		if n < 5:
			spawn_critter(b.cam_x + randf_range(80, Battle.W + 220))
	ambient_fire()
	var threats := threat_points()
	for c in crits:
		c.t += 1
		match c.st:
			"idle":
				idle_step(c, threats)
			"flee":
				flee_step(c)
	crits = crits.filter(func(c): return not c.get("gone", false))

# ---------------------------------------------------------------- ambient gunfire
## While the player is thinking, soldiers and Jackals trade the odd pot shot over each
## other's heads so the line feels like a live firefight. Only the arm, the muzzle flash,
## a tracer and a puff of dirt: no damage, no alert, no state the battle reads.
func can_plink(u: Unit) -> bool:
	if u.dead or u.gone or u.sunk or u == b.sel or u.walk != null or u.air or u.para or u.pose != "":
		return false
	if u.team == "squad":
		return u.sheet != ""
	return u.team == "enemy" and u.active and u.sheet != "" and u.type not in ["brute", "boss"]

func ambient_fire() -> void:
	for bs in bursts:
		if b.t >= bs.at:
			bs.done = true
			if can_plink(bs.u) and not b.busy and b.state == "player":
				plink(bs.u, bs.tg, bs.aim)
	bursts = bursts.filter(func(bs): return not bs.get("done", false))
	if b.busy or b.state != "player" or b.card_idx >= 0:
		return
	fire_cd -= 1
	if fire_cd > 0:
		return
	fire_cd = 40 + randi() % 80
	var pairs: Array = []
	for u in b.units:
		if not can_plink(u) or absf(u.x - b.cam_x - Battle.W / 2.0) > Battle.W / 2.0 + 20:
			continue
		for tg in b.units:
			if tg.dead or tg.gone or tg.team == u.team or not (tg.team in ["squad", "enemy"]) or (tg.team == "enemy" and not tg.active):
				continue
			var dx: float = tg.x - u.x
			if dx * u.face > 40 and absf(dx) < 620:
				pairs.append([u, tg])
	if pairs.is_empty():
		return
	var pr: Array = pairs[randi() % pairs.size()]
	var n := 1 + randi() % 3
	var aim := Vector2(pr[1].x + randf_range(-30, 30), pr[1].y - pr[1].h - 16 - randf() * 40)
	raise(pr[0], aim)
	for i in n:
		bursts.append({"u": pr[0], "tg": pr[1], "aim": aim + Vector2(0, randf_range(-8, 8)), "at": b.t + 10 + i * 7})

func raise(u: Unit, aim: Vector2) -> float:
	## Swing the arm toward the aim point; returns the firing angle in world space.
	var o := Vector2(u.x, u.y - u.h + 15)
	var ang := atan2(aim.y - o.y, aim.x - o.x)
	u.gun_target = clampf(atan2(sin(ang), cos(ang) * u.face), -1.35, 1.1)
	return ang

func gun_tip(u: Unit) -> Vector2:
	if u.type == "mg":
		return b.muzzle(u)
	var a: Array = b.view.pick_anim(u)
	var mo := Art.muzzle_offset(u.sheet, a[0], a[1], u.gun_angle)
	return Vector2(u.x + mo.x * u.face, u.y + mo.y)

func plink(u: Unit, tg: Unit, aim: Vector2) -> void:
	if tg.dead or tg.gone:
		return
	var m := gun_tip(u)
	if (aim.x - m.x) * u.face <= 0:
		return
	raise(u, aim)
	var ang := atan2(aim.y - m.y, aim.x - m.x)
	# a small plain flash: effects.gd only adds the big Sprite Fusion flash from 3 up
	u.muzzle = 2
	var end := b.cast_ray(m.x, m.y, ang, 760)
	# R6: a faint short streak off the muzzle, so idle pot shots never read as fire aimed at the squad
	var col := Color(1, 0.89, 0.42, 0.4) if u.team == "squad" else Color(1, 0.54, 0.35, 0.4)
	var tip := Vector2(m.x, m.y).move_toward(Vector2(end.x, end.y), 70.0)
	b.tracer(m.x, m.y, tip.x, tip.y, col)
	b.tracers[-1]["_fx"] = true   # no Sprite Fusion strike at the far end either
	if end.hit:
		b.dust(end.x, end.y, Color("b9a27a"), 2)
	Sfx.play("mg" if u.type == "mg" else "shot", -16.0, randf_range(0.9, 1.1))

func threat_points() -> Array:
	## Things critters run from: soldiers and Jackals nearby, shells in flight, fresh blasts.
	var pts: Array = []
	for u in b.units:
		if not u.dead and not u.gone and u.kind != "pow" and not u.is_prop() and u.kind != "fuel" and u.kind != "charge":
			pts.append([u.x, u.y, SCARE])
	for p in b.projs:
		pts.append([p.x, p.y, 90.0])
	for f in b.fx:
		if f.kind == "boom" and f.t < 3:
			pts.append([f.x, f.y, 320.0])
	for tr in b.tracers:
		pts.append([tr.x2, tr.y2, 120.0])
		pts.append([(tr.x1 + tr.x2) / 2, (tr.y1 + tr.y2) / 2, 80.0])
	return pts

func spawn_critter(x: float) -> void:
	var y := surface(x)
	if y < 0 or busy_spot(x, 10):
		return
	for u in b.units:
		if not u.dead and absf(u.x - x) < SCARE * 1.6:
			return
	var pool: Array = {"dusk": ["crow", "crow", "rat"], "jungle": ["parrot", "frog", "frog", "fly"], "night": ["gull", "rat", "gull"]}[b.theme]
	var k: String = pool[randi() % pool.size()]
	var c := {"k": k, "x": x, "y": y, "vx": 0.0, "vy": 0.0, "st": "idle", "t": randi() % 200, "face": 1 if randf() < 0.5 else -1, "fr": 0, "hop": 0.0, "alpha": 0.0}
	if k == "fly":
		c.y = y - 20 - randf() * 30
		c.base = c.y
	crits.append(c)

func idle_step(c: Dictionary, threats: Array) -> void:
	c.alpha = minf(1.0, c.alpha + 0.05)
	for p in threats:
		if absf(p[0] - c.x) < p[2] and absf(p[1] - c.y) < p[2] * 0.9:
			scare(c, p[0])
			return
	if c.k == "fly":
		c.x += sin(c.t / 40.0) * 0.4
		c.y = c.base + sin(c.t / 23.0) * 8
		c.face = 1 if cos(c.t / 40.0) > 0 else -1
		return
	var ground := surface(c.x)
	if ground < 0 or ground > c.y + 3:
		scare(c, c.x - c.face)  # the floor went away
		return
	c.y = ground
	if c.hop > 0:
		c.hop -= 1
		c.x += c.face * (0.6 if c.k != "frog" else 1.0)
		return
	if c.t % 30 == 0:
		var r := randf()
		if r < 0.15:
			c.face = -c.face
		elif r < 0.3 and surface(c.x + c.face * 12) > 0 and absf(surface(c.x + c.face * 12) - c.y) < 8:
			c.hop = 8 if c.k != "frog" else 14
		elif r < 0.7:
			c.fr = 1 - c.fr

func scare(c: Dictionary, from_x: float) -> void:
	c.st = "flee"
	c.t = 0
	c.face = 1 if c.x >= from_x else -1
	if c.k in ["crow", "gull", "parrot", "fly"]:
		c.vx = c.face * randf_range(1.6, 2.8)
		c.vy = randf_range(-3.2, -2.0)
	elif c.k == "frog":
		c.vx = c.face * 1.6
		c.vy = -3.0
	else:
		c.vx = c.face * 3.0

func flee_step(c: Dictionary) -> void:
	match c.k:
		"crow", "gull", "parrot", "fly":
			c.x += c.vx
			c.y += c.vy
			c.vy = maxf(-3.5, c.vy - 0.03)
			c.vx *= 1.01
		"frog":
			c.x += c.vx
			c.y += c.vy
			c.vy += 0.25
			var g := surface(c.x)
			if g > 0 and c.y >= g and c.vy > 0:
				c.y = g
				c.vy = -3.0  # keep bounding away
			elif g < 0 and c.y > Battle.WATER_Y:
				b.splash(c.x)
				c.gone = true
		_:
			c.x += c.vx
			var g2 := surface(c.x)
			if g2 > 0 and absf(g2 - c.y) < 14:
				c.y = g2
			else:
				c.vx = -c.vx * 0.9
	if c.t > 40:
		c.alpha -= 0.025
	if c.alpha <= 0 or c.y < -30 or c.x < b.cam_x - 100 or c.x > b.cam_x + Battle.W + 300:
		c.gone = true

# ---------------------------------------------------------------- draw
func _draw() -> void:
	if b.T == null or tops.is_empty():
		return
	for p in props:
		if p.x > b.cam_x - 80 and p.x < b.cam_x + Battle.W + 80:
			draw_prop(p)
	draw_flags()
	if liberated:
		draw_posts()
	draw_grass()
	for c in crits:
		draw_crit(c)

func supported(x: float, y: float) -> bool:
	return b.T.solid(x, y + 2) and not b.T.solid(x, y - 6)

func draw_prop(p: Dictionary) -> void:
	if p.get("dead", false):
		return
	if not supported(p.x, p.y):
		p.dead = true
		b.puff(p.x, p.y - 8, 1.2)
		return
	var tint := Color(b.th.tint, 1.0)
	match p.kind:
		"camp":
			sprite("logs", p.x, p.y, tint)
			draw_fire(p.x, p.y - 6)
		"lamp":
			sprite("lamp", p.x, p.y, tint)
			var on := Terrain.hash2(int(p.x), b.t / 6) > 0.03
			if on:
				var lp := Vector2(p.x, p.y - 60)
				draw_colored_polygon(PackedVector2Array([lp + Vector2(-6, 4), lp + Vector2(6, 4), Vector2(p.x + 34, p.y), Vector2(p.x - 34, p.y)]), Color(1, 0.9, 0.55, 0.10))
				draw_circle(lp, 26, Color(1, 0.88, 0.5, 0.10))
				draw_circle(lp, 10, Color(1, 0.92, 0.6, 0.25))
				draw_rect(Rect2(p.x - 30, p.y - 1, 60, 2), Color(1, 0.9, 0.55, 0.18))
		"reeds":
			var sway := sin(b.t / 50.0 + p.x) * 0.6 + b.wind * 0.08
			var tx: Texture2D = tex.reeds
			var w := tx.get_width()
			var h := tx.get_height()
			for col in w:
				var lean := roundf(sway * (h - 1) / 4.0) * Art.PX
				draw_texture_rect_region(tx, Rect2(p.x - w * Art.PX / 2 + col * Art.PX + lean, p.y - h * Art.PX, Art.PX, h * Art.PX), Rect2(col, 0, 1, h), tint)
		_:
			sprite(p.kind, p.x, p.y, tint)

func sprite(key: String, x: float, y: float, mod := Color.WHITE) -> void:
	var tx: Texture2D = tex[key]
	draw_texture_rect(tx, Rect2(roundf(x - tx.get_width() * Art.PX / 2), roundf(y - tx.get_height() * Art.PX + Art.PX), tx.get_width() * Art.PX, tx.get_height() * Art.PX), false, mod)

func draw_fire(x: float, y: float) -> void:
	var t := b.t
	var fl := 0.75 + 0.25 * sin(t * 0.37 + x) * sin(t * 0.23)
	draw_circle(Vector2(x, y - 6), 34, Color(1, 0.55, 0.2, 0.07 * fl))
	draw_circle(Vector2(x, y - 4), 16, Color(1, 0.6, 0.25, 0.14 * fl))
	for k in 3:
		var fx := x - 6 + k * 6
		var h := roundf((6 + 5 * fl + 3 * sin(t * 0.5 + k * 2.3)) / 2) * 2
		if k == 1:
			h += 4
		draw_rect(Rect2(fx - 2, y - h, 4, h), Color("ff7a2a"))
		draw_rect(Rect2(fx - 2, y - h + 4, 4, maxf(0, h - 4)), Color("ffb23e"))
		draw_rect(Rect2(fx, y - h + 8, 2, maxf(0, h - 8)), Color("fff3a0"))
	for k in 4:
		var age := (t + k * 23) % 90
		var ex := x + sin(age * 0.12 + k) * 5
		var ey := y - 12 - age * 0.6
		draw_rect(Rect2(roundf(ex), roundf(ey), 2, 2), Color(1, 0.7 - age / 300.0, 0.3, 1 - age / 90.0))
	for k in 3:
		var age := (t + k * 40) % 120
		var s := 4 + age / 20.0
		draw_rect(Rect2(roundf(x - s / 2 + age * 0.15 * signf(b.wind + 0.1)), roundf(y - 22 - age * 0.5), s, s), Color(0.55, 0.5, 0.48, 0.28 * (1 - age / 120.0)))

func draw_posts() -> void:
	## W11: sandbags, a company flag, and a garrison trading idle shots up the line now and then.
	var guards := ["sq_rook", "sq_moss"]
	for p in posts:
		if p.x < b.cam_x - 80 or p.x > b.cam_x + Battle.W + 80:
			continue
		for g in int(p.guards):
			var gx: float = p.x - 18 + g * 22
			Art.draw_char(self, guards[g % 2], "idle", (b.t / 12 + g) % 4, Vector2(gx, p.y), 1, false, 0, 0.9, -0.08, true, 1.0, Color(0.85, 0.95, 0.85))
			if (b.t + g * 37 + int(p.x)) % 150 < 4:
				var tip := Vector2(gx + 16, p.y - 13)
				draw_line(tip, tip + Vector2(26, -1), Color(1.0, 0.85, 0.4, 0.8), 1)
				draw_circle(tip, 2, Color(1.0, 0.9, 0.5))
		for k in 5:
			var sx: float = p.x - 26 + k * 11
			draw_rect(Rect2(sx, p.y - 8 - (4 if k % 2 == 1 else 0), 12, 8), Color("18120e"))
			draw_rect(Rect2(sx + 1, p.y - 7 - (4 if k % 2 == 1 else 0), 10, 6), Color("8a7a52"))
		draw_rect(Rect2(p.x + 30, p.y - 40, 2, 40), Color("18120e"))
		var wave := sin(b.t / 8.0) * 1.5
		draw_rect(Rect2(p.x + 32, p.y - 40 + wave * 0.3, 14, 8), Color("62d26f"))
		draw_rect(Rect2(p.x + 32, p.y - 36 + wave * 0.3, 14, 1), Color("2c5a33"))

func draw_flags() -> void:
	var tx: Texture2D = tex.flag
	var w := tx.get_width()
	var h := tx.get_height()
	var tint := Color(b.th.tint, 1.0) if not liberated else Color(0.45, 1.0, 0.55)  # W11: company colours on held ground
	for f in flags:
		if f.get("dead", false):
			continue
		if not b.T.solid(f.px, f.py):
			f.dead = true
			continue
		if f.x < b.cam_x - 60 or f.x > b.cam_x + Battle.W + 60:
			continue
		var top: float = f.y - 30
		draw_rect(Rect2(f.x - 1, top, 3, 30), Color("18120e"))
		draw_rect(Rect2(f.x, top, 1, 30), Color("8a8a90"))
		var dir := -1.0 if b.wind < 0 else 1.0
		var strength := 0.6 + absf(b.wind) * 0.12
		for col in w:
			var k := col / float(w)
			var wave := roundf(sin(b.t / 7.0 - col * 0.7) * 1.4 * k * strength) * Art.PX
			var droop := roundf((1 - strength) * k * 3) * Art.PX
			var x: float = f.x + 1 + dir * col * Art.PX
			if dir < 0:
				x -= Art.PX
			draw_texture_rect_region(tx, Rect2(x, top + 1 + wave + droop, Art.PX, h * Art.PX), Rect2(col, 0, 1, h), tint)

func draw_grass() -> void:
	var T: Terrain = b.T
	var gc: Color = b.th.grass
	var tint: Color = b.th.tint
	var shades := [gc * Color(1.18, 1.18, 1.18) * tint, gc * tint, gc * Color(0.78, 0.78, 0.78) * tint]
	var walkers: Array = []
	for u in b.units:
		if not u.dead and not u.gone and absf(u.x - b.cam_x - Battle.W / 2.0) < Battle.W:
			walkers.append(u)
	var c0 := int(b.cam_x / Terrain.CELL) - 2
	var c1 := int((b.cam_x + Battle.W) / Terrain.CELL) + 2
	var breeze := b.wind * 0.18
	for cx in range(maxi(0, c0), mini(T.cols, c1)):
		var r := top_row(cx)
		if r <= 0 or r >= Terrain.ROWS or T.grid[r * T.cols + cx] != 1:
			continue
		var gy := float(r * Terrain.CELL)
		if gy >= Battle.WATER_Y:
			continue
		for sub in 2:
			var ax := cx * 2 + sub
			var hsh := Terrain.hash2(ax, 77)
			if hsh > 0.6:
				continue
			var x := float(ax) * Art.PX
			var hgt := 2 + int(Terrain.hash2(ax, 13) * 4)
			var lean := sin(b.t * 0.03 + x * 0.045) * 0.7 + breeze
			for u in walkers:
				var dx: float = x - u.x
				if absf(dx) < 16 and absf(u.y - gy) < 24:
					lean += signf(dx + 0.01) * (16 - absf(dx)) / 16.0 * 2.6
			var col: Color = shades[int(Terrain.hash2(ax, 31) * 3)]
			for s in hgt:
				var k := (s + 1) / float(hgt)
				var off := roundf(lean * k * k * hgt * 0.5) * Art.PX
				draw_rect(Rect2(x + off, gy - (s + 1) * Art.PX, Art.PX, Art.PX), col)
			if hsh < 0.035:
				var off2 := roundf(lean * hgt * 0.5) * Art.PX
				var fc: Color = flower_cols[int(Terrain.hash2(ax, 3) * flower_cols.size())] * tint
				draw_rect(Rect2(x + off2 - Art.PX, gy - (hgt + 1) * Art.PX, Art.PX * 2, Art.PX * 2), fc)

func draw_crit(c: Dictionary) -> void:
	if c.x < b.cam_x - 40 or c.x > b.cam_x + Battle.W + 40:
		return
	var row: int = CRIT_ROW[c.k]
	var fr: int = c.fr
	var flyer: bool = c.k in ["crow", "gull", "parrot", "fly"]
	var bob := 0.0
	if c.k == "fly":
		fr = (c.t / 4) % 4
	elif c.st == "flee":
		if flyer:
			fr = 2 + (c.t / 4) % 2
		else:
			fr = 2 + (c.t / 4) % 2
	elif c.hop > 0:
		if c.k == "frog":
			fr = 2
			bob = sin((14 - c.hop) / 14.0 * PI) * 6
		elif c.k == "rat":
			fr = 2 + (c.t / 3) % 2
		else:
			bob = sin((8 - c.hop) / 8.0 * PI) * 3
	elif c.k == "frog" and c.t % 90 < 20:
		fr = 1
	var s := Art.PX
	draw_set_transform(Vector2(roundf(c.x), roundf(c.y - bob)), 0, Vector2(s * c.face, s))
	draw_texture_rect_region(tex.crit, Rect2(-6, -9, 12, 10), Rect2(fr * 12, row * 10, 12, 10), Color(b.th.tint, c.alpha))
	draw_set_transform_matrix(Transform2D.IDENTITY)

extends Node2D
## Cosmetic battle effects over the world: brass and smoke for every shot, sparks and chips
## where bullets land (by material), helmets that pop off the fallen, a hot flash and flying
## chunks for every blast, and flames under Jet Boots. It only watches the battle: nothing
## here feeds back into the simulation.

@onready var b: Battle = get_parent()
var bits: Array = []    # {k, x, y, vx, vy, life, max, rot, vr, c, s}
var flashes: Array = [] # {x, y, t, sc}
var muz := {}           # unit id -> muzzle value last tick
var fallen := {}        # unit id -> 1 helmet popped, 2 body landed
var last_t := -1

const C_DARK := Color(0.05, 0.035, 0.03)
const BRASS := [Color("ffd890"), Color("d8a040"), Color("a07028")]
const CHIPS := {
	1: [Color("8a5a30"), Color("6a4424"), Color("b08a5a")],   # dirt
	2: [Color("a0a4ac"), Color("6c7078"), Color("d0d4da")],   # concrete
	3: [Color("c88a4a"), Color("8c5a2c"), Color("e8b070")],   # wood
	4: [Color("7a6a5a"), Color("5a4a3e"), Color("a09080")],   # rock
}
const SPARK := [Color("ffffff"), Color("fff3a0"), Color("ffb23e")]
## Helmet / cap colours per sheet ([main, shade]); the shapes are drawn in code.
const HELMET := {
	"sq_moss": [Color("9cb04c"), Color("748a34")], "sq_hex": [Color("f4f2ea"), Color("cccac0")],
	"sq_vee": [Color("ff5a40"), Color("d63a2a")], "sq_rook": [Color("6c9cf0"), Color("3c6ad0")],
	"en_grunt": [Color("d84a3a"), Color("a8302a")], "en_shield": [Color("9aa2ae"), Color("6c7480")],
	"en_nade": [Color("d84a3a"), Color("a8302a")], "en_mg": [Color("d84a3a"), Color("a8302a")],
	"en_radio": [Color("5a86c8"), Color("3a5e9c")], "en_engineer": [Color("ffd23a"), Color("d8a420")],
	"en_sapper": [Color("3a3a3a"), Color("262626")], "en_mortarcrew": [Color("8a6a3a"), Color("6a4e26")],
	"en_para": [Color("d84a3a"), Color("a8302a")],
}

func _process(_d: float) -> void:
	if b.T == null:
		return
	if last_t < 0:
		last_t = b.t
	var steps := mini(b.t - last_t, 6)
	last_t = b.t
	if steps > 0:
		watch()
	for i in steps:
		step()
	queue_redraw()

# ---------------------------------------------------------------- watching the battle
func watch() -> void:
	for u in b.units:
		if u.gone or u.sunk or u.sheet == "":
			continue
		var m: int = u.muzzle
		if m > muz.get(u.id, 0) and m >= 3 and on_screen(u.x):
			shot(u)
		muz[u.id] = m
		if u.dead:
			var st: int = fallen.get(u.id, 0)
			if st == 0:
				fallen[u.id] = 1
				if HELMET.has(u.sheet) and on_screen(u.x):
					pop_helmet(u)
			elif st == 1 and u.dead_t >= 15:
				fallen[u.id] = 2
				b.dust(u.x, u.y, Color("b9a27a"), 6)
		if u.jetting and not u.dead:
			jet_bits(u)
	for tr in b.tracers:
		if not tr.has("_fx"):
			tr["_fx"] = true
			impact(tr.x1, tr.y1, tr.x2, tr.y2)
	for f in b.fx:
		if f.kind == "boom" and f.t >= 0 and not f.has("_fx"):
			f["_fx"] = true
			blast(f.x, f.y, f.sc)

func on_screen(x: float) -> bool:
	return x > b.cam_x - 80 and x < b.cam_x + Battle.W + 80

func gun_tip(u: Unit) -> Vector2:
	if u.type == "mg" or u.type == "boss" or not Art.meta.has(u.sheet):
		return b.muzzle(u)
	var a: Array = b.view.pick_anim(u)
	var mo := Art.muzzle_offset(u.sheet, a[0], a[1], u.gun_angle)
	return Vector2(u.x + mo.x * u.face, u.y + mo.y)

func add(d: Dictionary) -> void:
	var base := {"vx": 0.0, "vy": 0.0, "rot": 0.0, "vr": 0.0, "g": 0.2, "s": 2.0, "bounce": 0.0}
	base.merge(d, true)
	base["max"] = base.life
	bits.append(base)

func shot(u: Unit) -> void:
	var tip := gun_tip(u)
	var f: int = u.face
	# brass flips out of the ejection port, back over the shoulder
	add({"k": "brass", "x": u.x + f * 4, "y": u.y - u.h + 16, "vx": -f * randf_range(0.8, 2.0), "vy": randf_range(-3.2, -2.0),
		"life": 70, "vr": randf_range(0.3, 0.6), "c": BRASS[randi() % 2], "g": 0.22, "bounce": 0.45})
	for i in 3:
		add({"k": "smoke", "x": tip.x + f * i * 3, "y": tip.y, "vx": f * randf_range(0.1, 0.5) + b.wind * 0.02, "vy": randf_range(-0.5, -0.2),
			"life": 30 + i * 8, "g": -0.005, "s": 3.0 + i, "c": Color(0.78, 0.76, 0.74)})

func impact(x1: float, y1: float, x2: float, y2: float) -> void:
	if not on_screen(x2):
		return
	var dir := Vector2(x2 - x1, y2 - y1).normalized()
	var m := 0
	for k in 4:  # the tracer stops just short of the surface it hit
		var p := Vector2(x2, y2) + dir * k * 2
		m = b.T.mat(p.x, p.y)
		if m != 0:
			break
	var back := -dir
	if m != 0:
		var cols: Array = CHIPS.get(m, SPARK)
		for i in 5:
			var a := back.angle() + randf_range(-1.0, 1.0)
			var sp := randf_range(1.5, 3.5)
			add({"k": "chip", "x": x2, "y": y2, "vx": cos(a) * sp, "vy": sin(a) * sp - 1.0, "life": 26 + randi() % 14,
				"c": cols[randi() % cols.size()], "s": 2.0 if i % 2 else 3.0, "g": 0.2, "vr": 0.4, "bounce": 0.3})
		if m == 1 or m == 4:
			add({"k": "smoke", "x": x2, "y": y2, "vx": back.x * 0.4, "vy": -0.4, "life": 26, "g": -0.004, "s": 4.0, "c": cols[2]})
	else:
		# a body or open air: a short white-hot spark burst
		for i in 4:
			var a := back.angle() + randf_range(-1.2, 1.2)
			add({"k": "spark", "x": x2, "y": y2, "vx": cos(a) * randf_range(2, 4), "vy": sin(a) * randf_range(2, 4), "life": 8 + randi() % 6, "c": SPARK[i % 3], "g": 0.1})
	add({"k": "star", "x": x2, "y": y2, "life": 5, "g": 0.0, "c": Color.WHITE})

func pop_helmet(u: Unit) -> void:
	var away := signf(u.vx) if absf(u.vx) > 0.5 else -float(u.face)
	var hc: Array = HELMET[u.sheet]
	add({"k": "helmet", "x": u.x, "y": u.y - u.h + 4, "vx": away * randf_range(1.5, 2.8), "vy": randf_range(-5.0, -3.8),
		"life": 260, "vr": away * 0.35, "c": hc[0], "c2": hc[1], "g": 0.22, "bounce": 0.4})

func blast(x: float, y: float, sc: float) -> void:
	if not on_screen(x):
		return
	flashes.append({"x": x, "y": y, "t": 0, "sc": sc})
	var m := 1
	for k in 6:
		m = b.T.mat(x, y + k * 4)
		if m != 0:
			break
	var cols: Array = CHIPS.get(m, CHIPS[1])
	for i in int(5 + sc * 4):
		var a := -PI / 2 + randf_range(-1.1, 1.1)
		var sp := randf_range(3.0, 6.5) * (0.7 + sc * 0.2)
		add({"k": "chunk", "x": x, "y": y - 4, "vx": cos(a) * sp, "vy": sin(a) * sp, "life": 60 + randi() % 30,
			"c": cols[randi() % cols.size()], "s": [3.0, 4.0, 5.0][randi() % 3], "g": 0.22, "vr": randf_range(-0.4, 0.4), "bounce": 0.25})

func jet_bits(u: Unit) -> void:
	for f in [-4.0, 4.0]:
		add({"k": "flame", "x": u.x + f, "y": u.y + 2, "vx": randf_range(-0.4, 0.4) - u.vx * 0.3, "vy": randf_range(2.0, 3.5),
			"life": 10 + randi() % 5, "g": 0.0, "s": 3.0})
	if b.t % 3 == 0:
		add({"k": "smoke", "x": u.x, "y": u.y + 10, "vx": randf_range(-0.3, 0.3), "vy": 0.6, "life": 40, "g": -0.01, "s": 4.0, "c": Color(0.6, 0.58, 0.56)})

# ---------------------------------------------------------------- simulation
func step() -> void:
	for p in bits:
		p.life -= 1
		p.vy += p.g
		p.x += p.vx
		p.y += p.vy
		p.rot += p.vr
		if p.k == "smoke":
			p.s += 0.12
			p.vx *= 0.97
			continue
		if p.bounce > 0 and p.vy > 0 and b.T.solid(p.x, p.y):
			p.y -= p.vy
			if absf(p.vy) < 1.2:
				p.vy = 0.0
				p.vx *= 0.6
				p.vr *= 0.5
				p.g = 0.0
			else:
				p.vy = -p.vy * p.bounce
				p.vx *= 0.7
				if p.k == "brass" and on_screen(p.x):
					p.vr = -p.vr
		elif p.g == 0.0 and p.bounce > 0 and not b.T.solid(p.x, p.y + 2):
			p.g = 0.22  # the ground under it went away
		if p.k == "chunk" and p.life % 3 == 0 and absf(p.vx) + absf(p.vy) > 2:
			add({"k": "smoke", "x": p.x, "y": p.y, "life": 18, "g": -0.01, "s": 2.0, "c": Color(0.35, 0.32, 0.3)})
	bits = bits.filter(func(p): return p.life > 0 and p.y < Battle.WATER_Y + 4)
	if bits.size() > 700:
		bits = bits.slice(bits.size() - 700)
	for f in flashes:
		f.t += 1
	flashes = flashes.filter(func(f): return f.t < 10)

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	for f in flashes:
		var k: float = 1.0 - f.t / 10.0
		var r: float = 40.0 * f.sc
		draw_circle(Vector2(f.x, f.y - 6), r * (1.2 + f.t * 0.08), Color(1, 0.7, 0.35, 0.16 * k))
		draw_circle(Vector2(f.x, f.y - 6), r * 0.6, Color(1, 0.9, 0.6, 0.30 * k))
	for u in b.units:
		if u.jetting and not u.dead and on_screen(u.x):
			draw_jet(u)
	for p in bits:
		var a: float = clampf(float(p.life) / p.max * 3.0, 0.0, 1.0)
		var pos := Vector2(roundf(p.x), roundf(p.y))
		match p.k:
			"brass":
				var c: Color = p.c
				if int(p.rot * 2) % 3 == 0:
					c = BRASS[0]
				if int(p.rot) % 2 == 0:
					draw_rect(Rect2(pos.x - 1, pos.y, 3, 2), Color(c, a))
				else:
					draw_rect(Rect2(pos.x, pos.y - 1, 2, 3), Color(c, a))
			"smoke":
				var k: float = float(p.life) / p.max
				var s: float = roundf(p.s / 2) * 2
				draw_rect(Rect2(pos.x - s / 2, pos.y - s / 2, s, s), Color(p.c, 0.35 * k))
			"chip", "chunk":
				var s: float = p.s
				var wide := int(p.rot) % 2 == 0
				var r := Rect2(pos.x - s / 2, pos.y - s / 2, s if wide else s - 1, s - 1 if wide else s)
				if p.k == "chunk":
					draw_rect(r.grow(1), Color(C_DARK, a))
				draw_rect(r, Color(p.c, a))
			"spark":
				draw_rect(Rect2(pos.x - 1, pos.y - 1, 2, 2), p.c)
			"star":
				var s: float = 3.0 + p.life
				draw_rect(Rect2(pos.x - s, pos.y - 1, s * 2, 2), Color(1, 1, 0.8, 0.9))
				draw_rect(Rect2(pos.x - 1, pos.y - s, 2, s * 2), Color(1, 1, 0.8, 0.9))
			"flame":
				var k: float = float(p.life) / p.max
				var c := Color("fff3b0") if k > 0.7 else (Color("ffd23a") if k > 0.45 else (Color("ff7a3d") if k > 0.2 else Color("b8322a")))
				var s: float = roundf(p.s * (0.5 + k * 0.7))
				draw_rect(Rect2(pos.x - s / 2, pos.y - s / 2, s, s), c)
			"helmet":
				draw_helmet(pos, p, a)

func draw_helmet(pos: Vector2, p: Dictionary, a: float) -> void:
	## A little dome and brim, tumbling: upright or upside down as it spins.
	var up := cos(p.rot) >= 0
	var sy := 1.0 if up else -1.0
	var c: Color = Color(p.c, a)
	var c2: Color = Color(p.c2, a)
	var dk := Color(C_DARK, a)
	draw_rect(Rect2(pos.x - 5, pos.y - 6 * sy if up else pos.y, 10, 7), dk)
	draw_rect(Rect2(pos.x - 3, pos.y - 5 if up else pos.y + 3, 6, 2), c)
	draw_rect(Rect2(pos.x - 4, pos.y - 3 if up else pos.y + 1, 8, 2), c)
	draw_rect(Rect2(pos.x - 4, pos.y - 1 if up else pos.y - 1 + 2, 8, 1), c2)
	draw_rect(Rect2(pos.x - 2, pos.y - 5 if up else pos.y + 4, 2, 1), Color(1, 1, 1, 0.5 * a))

func draw_jet(u: Unit) -> void:
	## Twin thruster flames under the boots, flickering, with a hot glow.
	var fl := 0.7 + 0.3 * sin(b.t * 1.7) * sin(b.t * 0.9 + u.id)
	draw_circle(Vector2(u.x, u.y + 8), 18, Color(1, 0.6, 0.25, 0.18 * fl))
	for f in [-4.0, 4.0]:
		var x := roundf(u.x + f)
		var y := roundf(u.y)
		var L := roundf((10 + 8 * fl) / 2) * 2
		draw_rect(Rect2(x - 2, y - 2, 4, 3), Color("4a4e58"))
		draw_rect(Rect2(x - 2, y + 1, 4, L), Color("ff7a3d"))
		draw_rect(Rect2(x - 1, y + 1, 2, L - 2), Color("ffd23a"))
		draw_rect(Rect2(x - 1, y + 1, 2, roundf(L * 0.35)), Color("fff3b0"))

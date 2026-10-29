class_name SfEnergy
extends RefCounted
## V12, Sprite Fusion energy.ts, two of its kits.
## Bolt: a short charge-up at the emitter, then a glowing ball with a tapering trail that flies
## to the target and pops in a cross, a ring and plasma sparks.
## Beam: motes gather at the emitter, then a banded ray with a pulse running down it and a
## helix wrapped round it, a flare at both ends, and it tapers off.

const MOTE := 0
const STAR := 1
const PLASMA := 2
const CYAN := ["ffffff", "d6ffff", "7ff3ff", "1ab8e6", "2b6fd2", "25449c", "1b2662", "0f1538"]
const PINK := ["ffffff", "ffd8f5", "ff9ee4", "ff5fd0", "d43cc4", "8a2bb0", "4b1a7a", "250d42"]
const VHARR := ["ffffff", "eeffd8", "c8f79e", "9df25c", "5cbf3a", "2f8a2a", "1d5a22", "10301a"]

class Part:
	var k := 0
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var life := 0.0
	var mx := 0.0
	var col := Color()
	var size := 1.0
	var seed := 0.0

var R := Sf.Rng.new()
var kind := "bolt"
var C: Array = []
var ground: Callable
var from := Vector2()
var to := Vector2()
var t := 0.0
var pt := 0.0
var list: Array[Part] = []
var lights: Array = []  # [x, y, r, color, k, life, max]
# bolt
var CH := 0.0
var SPEED := 1100.0
var T := 1.0
var trail: Array = []
var launched := false
var hit := -1.0
# beam
var FIRE := 0.1
var TAPER := 0.3
var OFF := 0.7
var W := 3.0

static func bolt(a: Vector2, b: Vector2, ground_fn: Callable, palette: Array = CYAN, charge := 0.0, speed := 1100.0) -> SfEnergy:
	var e := SfEnergy.new()
	e.kind = "bolt"
	e.setup(a, b, ground_fn, palette)
	e.CH = charge
	e.SPEED = speed
	return e

static func beam(a: Vector2, b: Vector2, ground_fn: Callable, palette: Array = CYAN, charge := 0.1, hold := 0.2, width := 3.0) -> SfEnergy:
	var e := SfEnergy.new()
	e.kind = "beam"
	e.setup(a, b, ground_fn, palette)
	e.FIRE = charge
	e.TAPER = charge + hold
	e.OFF = e.TAPER + 0.4
	e.W = width
	return e

func setup(a: Vector2, b: Vector2, ground_fn: Callable, palette: Array) -> void:
	from = a
	to = b
	ground = ground_fn
	for h in palette:
		C.append(Color(h))

func spawn(k: int, x: float, y: float, vx: float, vy: float, life: float, col := Color(), size := 1.0) -> void:
	var p := Part.new()
	p.k = k; p.x = x; p.y = y; p.vx = vx; p.vy = vy; p.life = life; p.mx = life
	p.col = col; p.size = size; p.seed = R.next() * 100
	list.append(p)

func done() -> bool:
	var over := (hit >= 0 and t - hit > 0.4) if kind == "bolt" else t > OFF
	return over and list.is_empty() and lights.is_empty()

func update(dt: float) -> void:
	t += dt
	if kind == "bolt":
		update_bolt()
	else:
		update_beam(dt)
	step(dt)

func update_bolt() -> void:
	if t < CH:
		if R.chance(0.7):
			var a := R.rnd(0, TAU)
			var d := R.rnd(20, 50)
			var sp := d / 0.12
			spawn(MOTE, from.x + cos(a) * d, from.y + sin(a) * d, -cos(a) * sp, -sin(a) * sp, 0.12, R.pick([C[0], C[1], C[2]]), 0.8)
		return
	if not launched:
		launched = true
		T = maxf(0.05, from.distance_to(to) / SPEED)
		lights.append([from.x, from.y, 70.0, C[2], 0.8, 0.1, 0.1])
	if hit < 0:
		var h := head()
		trail.append(h)
		if trail.size() > 7:
			trail.pop_front()
		if R.chance(0.7):
			spawn(MOTE, h.x, h.y, R.rnd(-60, 60), R.rnd(-60, 60), R.rnd(0.15, 0.3), R.pick([C[1], C[2]]), 0.7)
		if t - CH >= T:
			hit = t
			trail.clear()
			var on_ground := absf(ground.call(h.x) - h.y) < 8
			for i in 26:
				var a := (-PI / 2 + R.rnd(-1.4, 1.4)) if on_ground else R.rnd(0, TAU)
				var sp := R.rnd(200, 700)
				spawn(PLASMA, h.x, h.y - 1, cos(a) * sp, sin(a) * sp, R.rnd(0.15, 0.45))
			for i in 14:
				var a := R.rnd(0, TAU)
				var sp := R.rnd(80, 300)
				spawn(STAR if i % 2 else MOTE, h.x, h.y, cos(a) * sp, sin(a) * sp - (120 if on_ground else 0), R.rnd(0.25, 0.6), R.pick([C[0], C[1], C[2]]), R.rnd(0.8, 1.6))
			lights.append([h.x, h.y, 150.0, C[3], 0.9, 0.25, 0.25])

func head() -> Vector2:
	return from.lerp(to, clampf((t - CH) / T, 0, 1))

func width(tt: float) -> float:
	if tt < FIRE:
		return 0.0
	if tt < TAPER:
		return W * (1 + 0.35 * exp(-(tt - FIRE) * 10))
	return lerpf(W, 0.4, Sf.out_cubic((tt - TAPER) / (OFF - TAPER)))

func update_beam(_dt: float) -> void:
	if t < FIRE:
		var k := clampf(t / FIRE, 0, 1)
		for i in 2 + floori(k * 4):
			var a := R.rnd(0, TAU)
			var d := R.rnd(34, 96) * (1 - k * 0.45)
			var sp := d * R.rnd(6, 9)
			spawn(PLASMA, from.x + cos(a) * d, from.y + sin(a) * d, -cos(a) * sp - sin(a) * sp * 0.45, -sin(a) * sp + cos(a) * sp * 0.45, R.rnd(0.1, 0.14))
		lights.append([from.x, from.y, 30 + 70 * k, C[3], 0.5 + 0.7 * k, 0.05, 0.05])
	elif t < OFF:
		var k := width(t) / W
		for i in ceili(4 * k):
			var a := -PI / 2 + R.rnd(-1.3, 0.9) - 0.4
			var sp := R.rnd(150, 560)
			spawn(PLASMA, to.x + R.rnd(-6, 6), to.y - 2, cos(a) * sp, sin(a) * sp, R.rnd(0.15, 0.5))
		if R.chance(0.5 * k):
			var p := from.lerp(to, R.next())
			spawn(PLASMA, p.x, p.y, R.rnd(-60, 60), R.rnd(-90, 30), R.rnd(0.1, 0.25))

func step(dt: float) -> void:
	pt += dt
	for i in range(list.size() - 1, -1, -1):
		var p := list[i]
		p.life -= dt
		if p.life <= 0:
			list.remove_at(i)
			continue
		match p.k:
			MOTE:
				p.vx -= p.vx * 0.6 * dt
				p.vy -= p.vy * 0.6 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
			STAR:
				p.vx -= p.vx * 1.6 * dt
				p.vy -= p.vy * 1.6 * dt + 10 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
			PLASMA:
				p.vy += Sf.GRAVITY * 0.45 * dt
				p.vx -= p.vx * 2.2 * dt
				p.vy -= p.vy * 2.2 * dt
				var g: float = ground.call(p.x)
				var ny := p.y + p.vy * dt
				p.x += p.vx * dt
				if p.vy > 0 and p.y <= g and ny >= g:
					p.vy = -p.vy * 0.45
					p.vx *= 0.7
					p.y = g - 0.5
				else:
					p.y = ny
	for i in range(lights.size() - 1, -1, -1):
		lights[i][5] -= dt
		if lights[i][5] <= 0:
			lights.remove_at(i)

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		return
	if kind == "bolt":
		draw_bolt(buf, light)
	else:
		draw_beam(buf, light)
	for p in list:
		draw_one(buf, light, p)
	for l in lights:
		var k: float = l[5] / l[6]
		light.glow(l[0] / Sf.PX, l[1] / Sf.PX, (l[2] / Sf.PX) * (0.55 + 0.45 * k), l[3], l[4] * k * k)

func seg(buf: Sf.Px, x0: float, y0: float, x1: float, y1: float, c: Color, a := 1.0) -> void:
	var n := maxi(1, ceili(Vector2(x1 - x0, y1 - y0).length() * 2))
	for i in n + 1:
		buf.dot(x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n, c, a)

func cross(buf: Sf.Px, x: float, y: float, l: float) -> void:
	for d in range(-floori(l), floori(l) + 1):
		var a := absf(d) / l
		var c: Color = C[0] if a < 0.3 else (C[1] if a < 0.65 else C[2])
		buf.dot(x + d, y, c, 1.15 - a)
		buf.dot(x, y + d * 0.7, c, 1.15 - a)

func draw_bolt(buf: Sf.Px, light: Sf.Px) -> void:
	var m := from / Sf.PX
	if t < CH:
		var k := t / CH
		var r := 0.8 + 2.6 * k
		buf.disc(m.x, m.y, r + 1, C[3])
		buf.disc(m.x, m.y, r, C[1])
		buf.disc(m.x, m.y, r * 0.5, C[0])
		light.glow(m.x, m.y, 10 + 14 * k, C[2], 0.6 * k)
		return
	if hit < 0 and launched:
		var h := head() / Sf.PX
		for i in trail.size() - 1:
			var p0: Vector2 = trail[i]
			var p1: Vector2 = trail[i + 1]
			var u := float(i + 1) / trail.size()
			for j in 4:
				var d := j / 3.0
				var p := p0.lerp(p1, d) / Sf.PX
				var w := 0.6 + 2.6 * (u - 0.1 + d * 0.1)
				if w > 1.6:
					buf.disc(p.x, p.y, w, C[3])
				buf.disc(p.x, p.y, maxf(0.6, w * 0.55), C[1] if u > 0.6 else C[2])
			light.glow(p0.x / Sf.PX, p0.y / Sf.PX, 8 * u + 2, C[3], 0.3 * u)
		for i in 4:
			var a := t * 22 + i * TAU / 4
			var l := 5 + 1.5 * sin(t * 50 + i)
			seg(buf, h.x + cos(a) * 3, h.y + sin(a) * 3, h.x + cos(a) * l, h.y + sin(a) * l, C[1])
		buf.disc(h.x, h.y, 4.2, C[4])
		buf.disc(h.x, h.y, 3.3, C[2])
		buf.disc(h.x, h.y, 2.3, C[1])
		buf.disc(h.x, h.y, 1.3, C[0])
		light.glow(h.x, h.y, 26, C[3], 0.7)
		light.glow(h.x, h.y, 9, C[0], 0.5)
	if hit >= 0 and t - hit < 0.35:
		var q := (t - hit) / 0.35
		var a := to / Sf.PX
		if q < 0.15:
			buf.disc(a.x, a.y, 9 * (1 - q * 3) + 1.5, C[3])
			buf.disc(a.x, a.y, 9 * (1 - q * 3), C[0])
		if q < 0.4:
			cross(buf, a.x, a.y, 18 * (1 - q / 0.4) + 3)
		buf.ring(a.x, a.y, 3 + 22 * Sf.out_cubic(q), maxf(1, 3 * (1 - q)), C[0] if q < 0.3 else C[2], 1.2 - q)

func draw_beam(buf: Sf.Px, light: Sf.Px) -> void:
	var a := from / Sf.PX
	var b := to / Sf.PX
	if t < FIRE:
		var k := t / FIRE
		var r := 1 + 3.5 * k * k
		buf.disc(a.x, a.y, r + 1, C[3])
		buf.disc(a.x, a.y, r, C[2])
		buf.disc(a.x, a.y, r * 0.5, C[0])
		return
	if t >= OFF:
		return
	var L0 := maxf(1, a.distance_to(b))
	var dir := (b - a) / L0
	var n := Vector2(-dir.y, dir.x)
	var L := L0 * Sf.out_expo((t - FIRE) / 0.07)
	var w0 := width(t)
	var k := w0 / W
	var flat := absf(dir.x) >= absf(dir.y)
	# (the original fills the cross-section dot by dot; here each band at each step is one run
	# across the beam, outer bands first)
	var bands := [1.3, 1.0, 0.85, 0.62, 0.4, 0.2]
	var d := 0.0
	while d <= L:
		var w := w0 * (1 + 0.12 * sin(d * 0.35 - t * 42)) * minf(1, (d + 3) / 7)
		var p := a + dir * d
		var pulse := 1 if fposmod(d * 0.025 - t * 3.4, 1.0) < 0.07 else 0
		for j in bands.size():
			var hw: float = w * bands[j] / maxf(0.5, absf(n.y) if flat else absf(n.x))
			var lvl := maxi(0, 5 - j - pulse)
			var col: Color = C[lvl]
			if j == 0:
				col = Color(col, 0.5)
			if flat:
				draw_col(buf, floori(p.x), floori(p.y - hw), floori(p.y + hw), col)
			else:
				var y := floori(p.y)
				buf.span(floori(p.x - hw), floori(p.x + hw), y, col)
		for s in [0.0, PI]:
			var ph: float = d * 0.2 - t * 28 + s
			var q0 := sin(ph) * w * 0.85
			if cos(ph) > -0.2:
				buf.dot(p.x + n.x * q0, p.y + n.y * q0, C[0] if cos(ph) > 0.5 else C[1])
		if (roundi(d * 2) & 11) == 0:
			light.glow(p.x, p.y, w * 2.2 + 4, C[3], 0.1 * k)  # (dimmer than the original: our light layer adds straight onto the scene)
		d += 1.0
	var fr := 3 + 2 * k + sin(t * 50) * 0.6
	buf.disc(a.x, a.y, fr + 1.5, C[3])
	buf.disc(a.x, a.y, fr, C[2])
	buf.disc(a.x, a.y, fr * 0.6, C[0])
	for i in 4:
		var ang := t * 9 + i * TAU / 4
		var l := (6 + 3 * sin(t * 30 + i)) * k
		seg(buf, a.x, a.y, a.x + cos(ang) * l, a.y + sin(ang) * l, C[2] if i % 2 else C[0])
	light.glow(a.x, a.y, 26 * k + 8, C[2], 0.5 * k)
	if L >= L0 - 0.5:
		var ir := 4 + 2.5 * k + sin(t * 60) * 0.8
		buf.disc(b.x, b.y, ir + 1.5, C[3])
		buf.disc(b.x, b.y, ir, C[1])
		buf.disc(b.x, b.y, ir * 0.55, C[0])
		for i in 7:
			var ang := -PI / 2 + (i - 3) * 0.32 - 0.5
			var l := (8 + 7 * absf(Sf.noise(t * 18 + i * 3, i))) * k
			seg(buf, b.x, b.y - 1, b.x + cos(ang) * l, b.y + sin(ang) * l, C[2] if i % 2 else C[1])
		light.glow(b.x, b.y, 50 * k + 10, C[2], 0.5 * k)
		light.glow(b.x, b.y, 14, C[0], 0.7 * k)

func draw_col(buf: Sf.Px, x: int, ya: int, yb: int, c: Color) -> void:
	if x < buf.x0 or x >= buf.x1:
		return
	ya = maxi(ya, buf.y0)
	yb = mini(yb, buf.y1 - 1)
	if ya > yb:
		return
	RenderingServer.canvas_item_add_rect(buf.ci, Rect2(x * Sf.PX, ya * Sf.PX, Sf.PX, (yb - ya + 1) * Sf.PX), c)

func draw_one(buf: Sf.Px, light: Sf.Px, p: Part) -> void:
	var k := p.life / p.mx
	var ax := p.x / Sf.PX
	var ay := p.y / Sf.PX
	var px := floori(ax)
	var py := floori(ay)
	match p.k:
		MOTE:
			var sp := maxf(0.001, Vector2(p.vx, p.vy).length())
			var ux := p.vx / sp
			var uy := p.vy / sp
			var ln := minf(16, 0.5 + sp * 0.013) * p.size
			if k < 0.35 and Sf.bayer(px, py) > k / 0.35:
				return
			buf.line(ax - ux * ln, ay - uy * ln, ax - ux * ln * 0.35, ay - uy * ln * 0.35, Sf.scale(p.col, 0.55))
			buf.line(ax - ux * ln * 0.4, ay - uy * ln * 0.4, ax, ay, p.col)
			light.glow(ax, ay, 2.5 + p.size, p.col, 0.4 * k)
		STAR:
			var tw := 0.6 + 0.4 * sin(pt * (8 + fmod(p.seed, 5)) + p.seed)
			if p.size < 1:
				if tw * k > 0.25:
					buf.put(px, py, C[0] if tw > 0.8 else p.col)
				light.glow(ax, ay, 3, p.col, 0.4 * k * tw)
				return
			var arm := maxi(1, roundi(p.size * tw * minf(1, k * 3)))
			var tip := Sf.scale(p.col, 0.75)
			for d in range(1, arm + 1):
				var cc := tip if d == arm and arm > 1 else p.col
				buf.put(px + d, py, cc)
				buf.put(px - d, py, cc)
				buf.put(px, py + d, cc)
				buf.put(px, py - d, cc)
			buf.put(px, py, C[0])
			light.glow(ax, ay, 3 + arm * 2, p.col, 0.5 * k * tw)
		PLASMA:
			var hot: Color = C[0] if k > 0.5 else (C[2] if k > 0.25 else C[3])
			var sp := maxf(0.001, Vector2(p.vx, p.vy).length())
			var ux := p.vx / sp
			var uy := p.vy / sp
			var ln := minf(9, 1 + sp * 0.011)
			buf.line(ax - ux * ln, ay - uy * ln, ax - ux * ln * 0.4, ay - uy * ln * 0.4, hot if k > 0.5 else C[3])
			buf.line(ax - ux * ln * 0.45, ay - uy * ln * 0.45, ax, ay, hot)
			light.glow(ax, ay, 3, hot, 0.45 * k)

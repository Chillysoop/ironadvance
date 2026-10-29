class_name SfSlash
extends RefCounted
## V7, Sprite Fusion slash.ts: a steel crescent swept in a flash with a thinner echo inside it,
## a glint where the blade ends, a scatter of sparks off the tip and shavings off the arc.

const STEEL := ["ffffff", "e8f1ff", "b8c9e8", "62c8f4", "3a8bd8", "2c58aa", "212f6b"]
const HOT := [Color("fff3a6"), Color("ffe26b"), Color("ff8a2a"), Color("f2561d")]
const WHITE := Color("ffffff")
const SPARK := 0
const MOTE := 1

var R := Sf.Rng.new()
var ground: Callable
var C: Array = []
var S := 1.0
var A := {}
var E := {}
var t := 0.0
var landed := false
var list: Array = []  # [k, x, y, vx, vy, life, max, col, size]

func _init(x: float, y: float, facing: float, ground_fn: Callable, size := 1.0, ramp: Array = STEEL) -> void:
	S = size
	ground = ground_fn
	for h in ramp:
		C.append(Color(h))
	var F := -1.0 if facing < 0 else 1.0
	var ra := 84.0 * S / Sf.PX
	var a0 := -2.55
	var a1 := 0.95
	var ang := func(a: float) -> float: return PI - a if F < 0 else a
	A = {"cx": x / Sf.PX, "cy": y / Sf.PX, "R": ra, "sy": 0.6, "rot": -0.38 * F, "a0": ang.call(a0), "a1": ang.call(a1), "W": 24.0 * S / Sf.PX, "t0": 0.0, "sweep": 0.06, "hold": 0.06, "trail": 0.24, "ramp": C}
	E = A.duplicate()
	E.R = ra * 33.0 / 42.0
	E.W = ra * 4.5 / 42.0
	E.a0 = ang.call(a0 + (a1 - a0) * 0.1)
	E.a1 = ang.call(a1 - (a1 - a0) * (0.15 / 3.5))
	E.t0 = 0.017
	E.hold = A.hold * 0.5
	E.trail = A.trail * 5.0 / 6.0
	E.ramp = C.slice(1)

static func on_arc(s: Dictionary, r: float, a: float) -> Vector2:
	var lx := cos(a) * r
	var ly: float = sin(a) * r * s.sy
	var c := cos(s.rot)
	var sn := sin(s.rot)
	return Vector2(s.cx + lx * c - ly * sn, s.cy + lx * sn + ly * c)

func slash_end(s: Dictionary) -> Array:
	var p := on_arc(s, s.R - s.W * 0.3, s.a1)
	var p2 := on_arc(s, s.R - s.W * 0.3, s.a1 + signf(s.a1 - s.a0) * 0.05)
	return [p, (p2 - p).normalized()]

func done() -> bool:
	return t > 0.5 and list.is_empty()

func update(dt: float) -> void:
	t += dt
	if not landed and t >= A.sweep:
		landed = true
		var e := slash_end(A)
		for i in 10:
			var a := atan2(e[1].y, e[1].x) + R.rnd(-0.5, 0.5)
			var sp := R.rnd(300, 800)
			list.append([SPARK, e[0].x * Sf.PX, e[0].y * Sf.PX, cos(a) * sp, sin(a) * sp, R.rnd(0.12, 0.35), 0.0, WHITE, 1.0])
		for i in 16:
			var a: float = A.a0 + (A.a1 - A.a0) * R.rnd(0.3, 1)
			var p := on_arc(A, A.R, a)
			var o := (p - Vector2(A.cx, A.cy)).normalized()
			var sp := R.rnd(60, 200)
			list.append([MOTE, p.x * Sf.PX, p.y * Sf.PX, o.x * sp, o.y * sp - 20, R.rnd(0.25, 0.55), 0.0, C[2 + R.ri(0, 1)], 0.6])
		for p in list:
			p[6] = p[5]
	for i in range(list.size() - 1, -1, -1):
		var p: Array = list[i]
		p[5] -= dt
		if p[5] <= 0:
			list.remove_at(i)
			continue
		if p[0] == SPARK:
			p[4] += Sf.GRAVITY * 0.45 * dt
			p[3] -= p[3] * 2.2 * dt
			p[4] -= p[4] * 2.2 * dt
			var g: float = ground.call(p[1])
			var ny: float = p[2] + p[4] * dt
			p[1] += p[3] * dt
			if p[4] > 0 and p[2] <= g and ny >= g:
				p[4] = -p[4] * 0.45
				p[3] *= 0.7
				p[2] = g - 0.5
			else:
				p[2] = ny
		else:
			p[3] -= p[3] * 0.6 * dt
			p[4] -= p[4] * 0.6 * dt
			p[1] += p[3] * dt
			p[2] += p[4] * dt

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		return
	draw_slash(buf, light, E)
	draw_slash(buf, light, A)
	glint(buf, light)
	if t < 0.3:
		var p := on_arc(A, A.R - 4, A.a0 + (A.a1 - A.a0) * Sf.out_expo(t / A.sweep))
		light.glow(p.x, p.y, 40 * S, C[3], 0.5 * (1 - t / 0.3))
	for p in list:
		var k: float = p[5] / p[6]
		var ax: float = p[1] / Sf.PX
		var ay: float = p[2] / Sf.PX
		var sp := maxf(0.001, Vector2(p[3], p[4]).length())
		var ux: float = p[3] / sp
		var uy: float = p[4] / sp
		if p[0] == SPARK:
			var head: Color = HOT[0] if k > 0.6 else (HOT[1] if k > 0.3 else HOT[2])
			var ln := minf(9, 1 + sp * 0.011)
			buf.line(ax - ux * ln, ay - uy * ln, ax - ux * ln * 0.4, ay - uy * ln * 0.4, head if k > 0.5 else HOT[3])
			buf.line(ax - ux * ln * 0.45, ay - uy * ln * 0.45, ax, ay, head)
			light.glow(ax, ay, 3, head, 0.45 * k)
		else:
			var ln: float = minf(16, 0.5 + sp * 0.013) * p[8]
			if k < 0.35 and Sf.bayer(floori(ax), floori(ay)) > k / 0.35:
				continue
			buf.line(ax - ux * ln, ay - uy * ln, ax - ux * ln * 0.35, ay - uy * ln * 0.35, Sf.scale(p[7], 0.55))
			buf.line(ax - ux * ln * 0.4, ay - uy * ln * 0.4, ax, ay, p[7])
			light.glow(ax, ay, 2.5 + p[8], p[7], 0.4 * k)

func crescent(buf: Sf.Px, light: Sf.Px, s: Dictionary, ta: float, L: float, W: float, ramp: Array, age: float) -> void:
	if absf(L) < 0.02 or W < 0.3:
		return
	var dir := signf(L)
	var span := absf(L)
	var c := cos(s.rot)
	var sn := sin(s.rot)
	var n := ramp.size()
	var rr: float = s.R
	var B := ceili(rr + 2)
	var cx: float = s.cx
	var cy: float = s.cy
	for py in range(floori(cy - B), ceili(cy + B) + 1):
		for px in range(floori(cx - B), ceili(cx + B) + 1):
			var dx := px + 0.5 - cx
			var dy := py + 0.5 - cy
			var lx := dx * c + dy * sn
			var ly: float = (-dx * sn + dy * c) / s.sy
			var r := sqrt(lx * lx + ly * ly)
			if r > rr + 0.5 or r < rr - W - 1:
				continue
			var u := fposmod(dir * (atan2(ly, lx) - ta), TAU)
			if u > span:
				continue
			var v := u / span
			var w := W * pow(sin(PI * pow(v, 2.2)), 0.6)
			if w < 0.35:
				continue
			var q := (rr - r) / w
			if q < 0 or q > 1:
				continue
			var f := minf(1, v / 0.4)
			if f < 1 and f <= Sf.bayer(px, py):
				continue
			var ci := 0 if q < 0.22 and age < 0.5 else roundi(q * (n - 1) * 0.75 + age * 2.4 - v * 0.8 + 0.4)
			buf.put(px, py, ramp[clampi(ci, 0, n - 1)])
	var u2 := 0.0
	while u2 <= span:
		var p := on_arc(s, rr - W * 0.4, ta + dir * u2)
		light.glow(p.x, p.y, 5 + W, ramp[2], 0.22 * (1 - age) * (u2 / span))
		u2 += 0.3

func draw_slash(buf: Sf.Px, light: Sf.Px, s: Dictionary) -> void:
	var u: float = t - s.t0
	if u < 0:
		return
	var head := Sf.out_expo(u / s.sweep)
	var tail := Sf.smooth(s.sweep + s.hold, s.sweep + s.hold + s.trail, u)
	var span: float = s.a1 - s.a0
	var age := clampf(u / (s.sweep + s.hold + s.trail), 0, 1)
	if tail < 1:
		crescent(buf, light, s, s.a0 + span * tail, span * (head - tail), s.W * (1 - tail * 0.55), s.ramp, age)
	var th := 0.7 * (1 - clampf((u - s.sweep - s.hold) / (s.trail + 0.2), 0, 1))
	if tail > 0.02 and th > 0:
		var k := 0.0
		var step: float = 0.6 / (absf(span) * s.R)
		while k <= tail:
			var p := on_arc(s, s.R - 0.5, s.a0 + span * k)
			buf.dot(p.x, p.y, s.ramp[s.ramp.size() - 2], th * (0.4 + 0.6 * k))
			k += step

func glint(buf: Sf.Px, light: Sf.Px) -> void:
	var g: float = t - A.t0 - A.sweep * 0.6
	var life := 0.22
	if g <= 0 or g >= life:
		return
	var e := slash_end(A)
	var n := roundi(9 * S * Sf.out_back(minf(1, g / 0.05)) * (1 - g / life))
	if n < 1:
		return
	var px := roundi(e[0].x)
	var py := roundi(e[0].y)
	for d in range(1, n + 1):
		var cc: Color = C[3] if d > n * 0.6 else C[1]
		buf.put(px + d, py, cc)
		buf.put(px - d, py, cc)
		buf.put(px, py + d, cc)
		buf.put(px, py - d, cc)
	if n >= 3:
		for o in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			buf.put(px + o.x, py + o.y, C[1])
	if n >= 6:
		for o in [Vector2i(2, 2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(-2, -2)]:
			buf.put(px + o.x, py + o.y, C[3])
	buf.put(px, py, WHITE)
	light.glow(e[0].x, e[0].y, 4 + n * 2, C[1], 0.6)

class_name SfIce
extends RefCounted
## V16, Sprite Fusion ice.ts, its shatter scene laid flat for the Frozen Lake crust: white cracks
## race out along the ice from under the weight, then the slab bursts into tumbling shards and
## faceted chunks with frost mist rolling off and glints hanging in the air. Ice.ts's shard, chunk,
## mist and glint pieces are kept as they are.

const ICE := ["ffffff", "dcfbff", "a6ecff", "62c8f4", "3a8bd8", "2c58aa", "212f6b", "151a3d"]
const WHITE := Color("ffffff")
const SHARD := 0
const CHUNK := 1
const DUST := 0
const STAR := 1
const FLAKE := 3
const CROSS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var R := Sf.Rng.new()
var C: Array = []
var ground: Callable
var S := 1.0
var cx := 0.0
var cy := 0.0
var CRACK := 0.16
var t := 0.0
var broke := false
var cracks: Array = []  # each a PackedVector2Array of art px points
var bits: Array = []    # [x, y, vx, vy, life, max, a, va, s, c, kind, g, drag, bounce, rest]
var ps: Array = []      # [k, x, y, vx, vy, life, max, col, size, seed]
var lights: Array = []  # [x, y, r, c, k, life, max]

func _init(x: float, y: float, ground_fn: Callable, size := 1.0) -> void:
	ground = ground_fn
	S = size
	for h in ICE:
		C.append(Color(h))
	cx = x / Sf.PX
	cy = roundf(y / Sf.PX)
	for i in 7:
		var dir := -1.0 if i % 2 == 0 else 1.0
		var pts := PackedVector2Array([Vector2(cx + R.rnd(-1, 1), cy)])
		var p := pts[0]
		var a := (PI if dir < 0 else 0.0) + dir * R.rnd(-0.25, 0.6)
		var n := R.ri(4, 7)
		for k in n:
			a += R.rnd(-0.5, 0.5)
			p += Vector2(cos(a), absf(sin(a)) * 0.6) * R.rnd(2.5, 4.5) * S
			p.y = minf(p.y, cy + 4)
			pts.append(p)
		cracks.append(pts)
	lights.append([x, y - 4, 60.0, WHITE, 0.9, 0.12, 0.12])
	mist(6, 0.5)

func done() -> bool:
	return broke and t > 1 and ps.is_empty() and bits.is_empty()

func mist(n: int, sp: float) -> void:
	for i in n:
		var life := R.rnd(0.6, 1.2)
		ps.append([DUST, cx * Sf.PX + R.rnd(-10, 10), cy * Sf.PX - R.rnd(0, 6), R.sgn() * R.rnd(30, 160) * sp, -R.rnd(2, 14), life, life, C[2] if R.chance(0.5) else C[3], R.rnd(2, 4), R.next() * 100])

func spawn(k: int, x: float, y: float, vx: float, vy: float, life: float, col: Color, size: float) -> void:
	ps.append([k, x, y, vx, vy, life, life, col, size, R.next() * 100])

func bit(kind: int, x: float, y: float, vx: float, vy: float, life: float, s: float, c: Color) -> void:
	bits.append([x, y, vx, vy, life, life, R.rnd(0, TAU), R.rnd(-20, 20), s, c, kind, 0.9, 0.5, 0.25, false])

func update(dt: float) -> void:
	t += dt
	if not broke and t >= CRACK:
		broke = true
		lights.append([cx * Sf.PX, cy * Sf.PX - 20, 140.0 * S, C[2], 0.8, 0.3, 0.3])
		for i in roundi(26 * S):
			var a := -PI / 2 + R.rnd(-1.2, 1.2)
			var sp := R.rnd(140, 460)
			bit(CHUNK if R.chance(0.25) else SHARD, (cx + R.rnd(-12, 12) * S) * Sf.PX, (cy - R.rnd(0, 3)) * Sf.PX, cos(a) * sp, sin(a) * sp, R.rnd(1, 1.6), R.rnd(1.5, 4.5) * S, R.pick([C[1], C[2], C[3], C[4]]))
		for i in 10:
			var a := -PI / 2 + R.rnd(-1.4, 1.4)
			var sp := R.rnd(60, 220)
			spawn(FLAKE, cx * Sf.PX + R.rnd(-10, 10), cy * Sf.PX - 4, cos(a) * sp, sin(a) * sp, R.rnd(1.1, 1.9), WHITE if R.chance(0.5) else C[1], R.rnd(0.5, 1.6))
		mist(12, 1)
		for i in 6:
			spawn(STAR, cx * Sf.PX + R.rnd(-24, 24), cy * Sf.PX - R.rnd(4, 60), R.rnd(-20, 20), R.rnd(-30, 0), R.rnd(0.4, 1), C[1] if R.chance(0.5) else C[2], R.rnd(1, 2.6))
	for i in range(bits.size() - 1, -1, -1):
		var b: Array = bits[i]
		b[4] -= dt
		if b[4] <= 0:
			bits.remove_at(i)
			continue
		if b[14]:
			continue
		b[3] += Sf.GRAVITY * b[11] * dt
		b[2] -= b[2] * b[12] * dt
		b[3] -= b[3] * b[12] * dt
		b[0] += b[2] * dt
		b[1] += b[3] * dt
		b[6] += b[7] * dt
		var fl: float = ground.call(b[0])
		var sp: float = b[3]
		if b[1] < fl or sp <= 0:
			continue
		b[1] = fl - 0.01
		if b[10] == SHARD:
			b[2] *= 1.6
		if sp > 140:
			b[3] = -sp * b[13]
			b[2] *= 0.7
			b[7] *= 0.6
		else:
			b[14] = true
			b[2] = 0
			b[3] = 0
	for i in range(ps.size() - 1, -1, -1):
		var p: Array = ps[i]
		p[5] -= dt
		if p[5] <= 0:
			ps.remove_at(i)
			continue
		if p[0] == FLAKE:
			p[3] -= p[3] * 2.2 * dt
			p[4] -= p[4] * 2.2 * dt - 70 * dt
			p[1] += sin(t * 2.5 + p[9]) * 14 * dt
		else:
			var drag := 4.0 if p[0] == DUST else 1.6
			p[3] -= p[3] * drag * dt
			p[4] -= p[4] * drag * dt + 10 * dt
		p[1] += p[3] * dt
		p[2] += p[4] * dt
	for i in range(lights.size() - 1, -1, -1):
		lights[i][5] -= dt
		if lights[i][5] <= 0:
			lights.remove_at(i)

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		frost(buf, 1 - Sf.smooth(0.8, 1.8, t))
		for p in ps:
			if p[0] == DUST:
				var k: float = p[5] / p[6]
				buf.alpha_disc(p[1] / Sf.PX, p[2] / Sf.PX, p[8] * (0.6 + (1 - k) * 0.9), p[7], pow(k, 1.3) * 0.7)
		return
	if t < CRACK + 0.05:
		var k := clampf(t / CRACK, 0, 1)
		for pts in cracks:
			var n := maxi(1, roundi((pts.size() - 1) * k))
			for i in n:
				buf.line(pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y, WHITE if i < 2 or broke else C[1])
		light.glow(cx, cy - 2, 12 + 20 * k, C[2], 0.3 + 0.5 * k)
	for b in bits:
		var a := minf(1, b[4] / 0.4)
		if b[10] == SHARD:
			shard(buf, b, a)
		else:
			chunk(buf, b, a)
	for p in ps:
		if p[0] == DUST:
			continue
		var k: float = p[5] / p[6]
		var ax: float = p[1] / Sf.PX
		var ay: float = p[2] / Sf.PX
		if p[0] == FLAKE:
			var a := minf(1, k * 3)
			buf.dot(ax, ay, p[7], a)
			if p[8] > 1.3:
				for o in CROSS:
					buf.dot(ax + o.x, ay + o.y, C[1], a * 0.8)
			continue
		var tw := 0.6 + 0.4 * sin(t * (8 + fmod(p[9], 5)) + p[9])
		var px := floori(ax)
		var py := floori(ay)
		if p[8] < 1:
			if tw * k > 0.25:
				buf.put(px, py, WHITE if tw > 0.8 else p[7])
			continue
		var arm := maxi(1, roundi(p[8] * tw * minf(1, k * 3)))
		var tip := Sf.scale(p[7], 0.75)
		for d in range(1, arm + 1):
			for o in CROSS:
				buf.put(px + o.x * d, py + o.y * d, tip if d == arm and arm > 1 else p[7])
		buf.put(px, py, WHITE)
		light.glow(ax, ay, 3 + arm * 2, p[7], 0.5 * k * tw)
	for l in lights:
		var k: float = l[5] / l[6]
		light.glow(l[0] / Sf.PX, l[1] / Sf.PX, (l[2] / Sf.PX) * (0.55 + 0.45 * k), l[3], l[4] * k * k)

func frost(buf: Sf.Px, a: float) -> void:
	if a <= 0:
		return
	var w := 22.0 * S
	for x in range(floori(cx - w), ceili(cx + w) + 1):
		var gy: float = ground.call(x * Sf.PX)
		if gy > 1e8:
			continue
		var y := gy / Sf.PX
		var h := Sf.hsh(x, 17)
		var d := minf(1, (w - absf(x - cx)) / 6.0)
		if h < 0.75 * minf(1, d * 2):
			buf.dot(x, y, C[1] if h < 0.3 else C[2], a)
		if h < 0.4 * minf(1, d * 2):
			buf.dot(x, y + 1, C[3], a * 0.7)

func shard(buf: Sf.Px, b: Array, a: float) -> void:
	var x: float = b[0] / Sf.PX
	var y: float = b[1] / Sf.PX
	var ca := cos(b[6])
	var sa := sin(b[6])
	var d: float = -b[8] / 2
	while d <= b[8] / 2:
		buf.dot(x + ca * d, y + sa * d, WHITE if d > b[8] / 2 - 0.6 else b[9], a)
		d += 0.5

func chunk(buf: Sf.Px, b: Array, a: float) -> void:
	var x := roundi(b[0] / Sf.PX)
	var y := roundi(b[1] / Sf.PX)
	var ca := cos(b[6])
	var sa := sin(b[6])
	var s: float = b[8]
	var r := ceili(s) + 1
	for py in range(-r, r + 1):
		for px in range(-r, r + 1):
			var u := (px + 0.5) * ca + (py + 0.5) * sa
			var v := -(px + 0.5) * sa + (py + 0.5) * ca
			var d := absf(u) / s + absf(v) / (s * 0.62)
			if d <= 1.3 and (a >= 1 or a > Sf.bayer(x + px, y + py)):
				buf.put(x + px, y + py, C[7] if d > 1 else (C[1] if u < 0 else C[2]) if v < 0 else (C[3] if u < 0 else C[5]))

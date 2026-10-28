class_name SfImpact
extends RefCounted
## V2, Sprite Fusion impact.ts: a bullet strike. A two-frame star burst, shards flying off in
## crescents, a ring and sparks; on a surface it also kicks out chips and dust in the surface's
## colour, and a ricochet leaves a scorch streak and a tracer glancing away.

const SPARK := 0
const CHIP := 1
const DUST := 2
const SMOKE := 3
const SOOT := Color("0d0a12")
const SMOKE_C := Color("6a6278")
const SMOKE_RAMP := [Color("7b6f72"), Color("5d5660"), Color("433d48"), Color("2b2630"), Color("1a171e")]
const WARM_RAMP := [Color("ffffff"), Color("fff3a6"), Color("ffe26b"), Color("ff8a2a"), Color("f2561d"), Color("c9281f")]
const STREAK := 0.16
const SPEED := 1500.0

class Part:
	var k := 0
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var life := 0.0
	var mx := 0.0
	var col := Color(0, 0, 0, 0)
	var size := 1.0
	var seed := 0.0
	var delay := 0.0

var R := Sf.Rng.new()
var ground: Callable
var list: Array[Part] = []
var pt := 0.0
var t := 0.0
var glance := false
var on_surface := false
var C: Array = WARM_RAMP
var S := 1.0
var A := 0.0
var B := 0.0
var N := -PI / 2
var ax := 0.0
var ay := 0.0
var spikes: Array = []  # [a, len, w]
var shards: Array = []  # [a, r, v, arc]
var tx := 0.0
var ty := 0.0
var sx := 0.0
var sy := 0.0

## angle is the travel direction, normal the surface normal (only used with a surface colour).
func _init(x: float, y: float, angle: float, ground_fn: Callable, ricochet := false, surface = null, normal := -PI / 2, size := -1.0, ramp_cols: Array = []) -> void:
	ground = ground_fn
	glance = ricochet
	on_surface = surface != null
	A = angle
	N = normal
	S = size if size > 0 else (0.9 if glance else 1.0)
	if not ramp_cols.is_empty():
		C = ramp_cols
	ax = x / Sf.PX
	ay = y / Sf.PX
	var dx := cos(A)
	var dy := sin(A)
	var nx := cos(N)
	var ny := sin(N)
	var dn := dx * nx + dy * ny
	B = atan2(dy - 2 * dn * ny, dx - 2 * dn * nx) if on_surface else A
	for i in 8:
		var a := B + i / 8.0 * TAU + R.rnd(-0.18, 0.18)
		var cb := cos(a - B)
		var into := cos(a - N) < -0.2 if on_surface else false
		var ln := (7 + R.rnd(0, 3)) * S * (1 + (2.6 if glance else 1.8) * pow(maxf(0, cb), 3) + 0.6 * pow(maxf(0, -cb), 3)) * (0.3 if into else 1.0) * (0.6 if glance and absf(sin(a - B)) > 0.6 else 1.0)
		spikes.append([a, ln, (1.5 + R.rnd(0, 0.6)) * S])
	var opens := spikes.filter(func(p): return is_open(p[0]))
	opens.sort_custom(func(p, q): return p[1] > q[1])
	for s in opens.slice(0, 4):
		shards.append([s[0] + R.rnd(-0.15, 0.15), s[1] * 0.8, s[1] * R.rnd(5, 8), R.rnd(0.35, 0.6)])
	var n := roundi((10.0 if glance else 6.0) + 12 * S)
	for i in n:
		var back := not on_surface and R.chance(0.2)
		var a := (A + PI if back else B) + R.rnd(-1, 1) * (0.3 if glance else (0.85 if on_surface else 0.6))
		var sp := R.rnd(260, 900) * (0.6 + 0.4 * S) * (1.2 if glance else 1.0)
		spawn(SPARK, x, y, cos(a) * sp, sin(a) * sp - (20.0 if glance else 60.0), R.rnd(0.1, 0.3) * (1.3 if glance else 1.0))
	if on_surface:
		var sc: Color = surface
		var dc := Sf.mix(sc, Color8(150, 140, 150), 0.35)
		for i in roundi((2.0 if glance else 3.0) + 5 * S):
			var a := (B if glance else N) + R.rnd(-0.8, 0.8) * (0.6 if glance else 1.0)
			var sp := R.rnd(150, 420) * S
			var c := Sf.scale(sc, 1.25) if R.chance(0.5) else (sc if R.chance(0.5) else Sf.scale(sc, 0.7))
			spawn(CHIP, x, y + ny * 2, cos(a) * sp, sin(a) * sp, R.rnd(0.8, 1.4), c, 2 if R.chance(0.3) else 1)
		for i in roundi(3 + 4 * S):
			var a := N + R.rnd(-1, 1)
			var sp := R.rnd(20, 90) * S
			spawn(DUST, x + nx * 3, y + ny * 3, cos(a) * sp, sin(a) * sp, R.rnd(0.35, 0.7), dc, R.rnd(1.4, 2.8) * sqrt(S))
		spawn(SMOKE, x + nx * 4, y + ny * 4, R.rnd(-8, 8), R.rnd(-30, -14), R.rnd(0.8, 1.3), SMOKE_C, R.rnd(1.6, 2.4) * sqrt(S), 0.05)
	tx = cos(B)
	ty = sin(B)
	var side := N + PI / 2
	var sg := signf(cos(A - side))
	if sg == 0:
		sg = 1
	sx = cos(side) * sg
	sy = sin(side) * sg

func is_open(a: float) -> bool:
	return not on_surface or cos(a - N) > -0.25

func spawn(k: int, x: float, y: float, vx: float, vy: float, life: float, col := Color(0, 0, 0, 0), size := 1.0, delay := 0.0) -> void:
	var p := Part.new()
	p.k = k; p.x = x; p.y = y; p.vx = vx; p.vy = vy; p.life = life; p.mx = life
	p.col = col; p.size = size; p.seed = R.next() * 100; p.delay = delay
	list.append(p)

func done() -> bool:
	return t > (1.1 if glance else 0.2) and list.is_empty()

func update(dt: float) -> void:
	t += dt
	pt += dt
	for i in range(list.size() - 1, -1, -1):
		var p := list[i]
		if p.delay > 0:
			p.delay -= dt
			continue
		p.life -= dt
		if p.life <= 0:
			list.remove_at(i)
			continue
		match p.k:
			SPARK:
				var g: float = ground.call(p.x)
				p.vy += Sf.GRAVITY * 0.45 * dt
				p.vx -= p.vx * 2.2 * dt
				p.vy -= p.vy * 2.2 * dt
				var ny := p.y + p.vy * dt
				p.x += p.vx * dt
				if p.vy > 0 and p.y <= g and ny >= g:
					p.vy = -p.vy * 0.45
					p.vx *= 0.7
					p.y = g - 0.5
				else:
					p.y = ny
			CHIP:
				var g: float = ground.call(p.x)
				p.vy += Sf.GRAVITY * dt
				p.vx -= p.vx * 0.6 * dt
				var ny := p.y + p.vy * dt
				p.x += p.vx * dt
				if p.vy > 0 and p.y <= g and ny >= g:
					p.y = g - 0.5
					if p.vy > 220:
						p.vy = -p.vy * 0.3
						p.vx = p.vx * 0.5 + R.rnd(-20, 20)
					else:
						p.vx = 0
						p.vy = 0
						p.life = minf(p.life, 0.5)
				else:
					p.y = ny
			DUST:
				p.vx -= p.vx * 4 * dt
				p.vy -= p.vy * 4 * dt + 10 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
			SMOKE:
				p.vy -= 32 * dt
				p.vx += sin(pt * 1.3 + p.seed) * 16 * dt
				p.vx -= p.vx * 1.6 * dt
				p.vy -= p.vy * 1.2 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		if glance and on_surface and t < 1.1:
			var T := clampf(1 - t / 0.9, 0, 1)
			var L := 9 * S
			var d := 0.0
			while d <= L:
				var k := d / L
				var px := ax - sx * d
				var py := ay - sy * d
				var c: Color = C[1] if T * (1 - k) > 0.5 else (C[3] if T * (1 - k) > 0.25 else (C[5] if T > 0 else SOOT))
				buf.dot(px, py, c, 1 - k * 0.6)
				if T > 0.2 and int(d) % 3 == 0:
					light.glow(px, py, 4, C[3], 0.3 * T * (1 - k))
				d += 0.5
		draw_parts(buf, light, true)
		return
	var f := maxi(1, ceili(t * 60 - 1e-6))
	if f == 1:
		star(buf, 1, 1, C[0], C[1], C[2], C[4])
	elif f == 2:
		star(buf, 1.25, 0.55, C[1], C[2], C[3], C[4])
	if f >= 3 and t < 0.13:
		var k := (t - 2 / 60.0) / (0.13 - 2 / 60.0)
		for s in shards:
			crescent(buf, s[0], s[1] + s[2] * (t - 2 / 60.0), s[3] * (1 - 0.4 * k), C[2] if k < 0.4 else (C[3] if k < 0.7 else C[4]), 1 - k)
	if f >= 3 and t < 0.2:
		var k := (t - 2 / 60.0) / (0.2 - 2 / 60.0)
		var r := (8 + 12 * (1 - pow(1 - k, 3))) * S
		var th := maxf(1, 2 * (1 - k) * S)
		var col: Color = C[1] if k < 0.3 else (C[2] if k < 0.6 else C[3])
		var n := ceili(r * TAU * 1.3)
		for j in n:
			var a := float(j) / n * TAU
			if not is_open(a):
				continue
			var o := -th / 2
			while o <= th / 2:
				buf.dot(ax + cos(a) * (r + o), ay + sin(a) * (r + o), col, 1.15 - k)
				o += 0.5
	if glance and t < STREAK:
		var head := (SPEED * t) / Sf.PX + 6 * S
		var tail := maxf(2, head - (40 + 220 * t) / Sf.PX)
		var k := t / STREAK
		var d := tail
		while d <= head:
			var u := (d - tail) / maxf(1, head - tail)
			buf.dot(ax + tx * d, ay + ty * d, C[0] if u > 0.8 else (C[1] if u > 0.4 else C[3]), 1.0 if u > 0.4 else 1 - k)
			d += 0.5
		light.glow(ax + tx * head, ay + ty * head, 9, C[2], 0.6 * (1 - k))
	draw_parts(buf, light, false)
	var pop := exp(-t / 0.05)
	if pop > 0.02:
		light.glow(ax, ay, 22 * S + 6, C[3], 0.9 * pop)
		light.glow(ax, ay, 8 * S + 2, C[0], 0.7 * pop)

func star(buf: Sf.Px, sc: float, th: float, core: Color, body: Color, inner: Color, rim: Color) -> void:
	for pass_i in 3:
		for s in spikes:
			var c := cos(s[0])
			var sn := sin(s[0])
			var L: float = s[1] * sc
			var d := 0.0
			var last := Vector2i(1 << 30, 0)
			while d <= L:
				var hw0: float = s[2] * th * (1 - d / L) * minf(1, 0.5 + d / 3)
				var hw := hw0 + 0.8 if pass_i == 0 else (hw0 if pass_i == 1 else hw0 * 0.45)
				if pass_i == 2 and d > L * 0.55:
					break
				var col := rim if pass_i == 0 else ((inner if d < L * 0.35 else body) if pass_i == 1 else core)
				var o := -hw
				while o <= hw:
					var p := Vector2i(floori(ax + c * d - sn * o), floori(ay + sn * d + c * o))
					if p != last:
						buf.put(p.x, p.y, col)
						last = p
					o += 0.5
				d += 0.5
	var r := 2.4 * S * sc * sqrt(th)
	buf.disc(ax, ay, r + 0.8, inner)
	buf.disc(ax, ay, r, core)

func crescent(buf: Sf.Px, a: float, r: float, arc: float, c: Color, k: float) -> void:
	var n := ceili(r * arc * 2.2)
	if n <= 0:
		return
	for j in n + 1:
		var u := float(j) / n - 0.5
		var th := a + u * arc
		var w := 1.4 * (1 - absf(u) * 2)
		var o := -w * 0.5
		while o <= w * 0.5 + 0.01:
			buf.dot(ax + cos(th) * (r + o), ay + sin(th) * (r + o), c, k)
			o += 0.5

func draw_parts(buf: Sf.Px, light: Sf.Px, back: bool) -> void:
	for p in list:
		if p.delay > 0 or (p.k == SPARK) == back:
			continue
		var k := p.life / p.mx
		var px_x := p.x / Sf.PX
		var px_y := p.y / Sf.PX
		var px := floori(px_x)
		var py := floori(px_y)
		match p.k:
			SPARK:
				var hot: Color = C[1] if k > 0.6 else (C[2] if k > 0.3 else C[3])
				var sp := maxf(0.001, Vector2(p.vx, p.vy).length())
				var ux := p.vx / sp
				var uy := p.vy / sp
				var ln := minf(9, 1 + sp * 0.011)
				buf.line(px_x - ux * ln, px_y - uy * ln, px_x - ux * ln * 0.4, px_y - uy * ln * 0.4, hot if k > 0.5 else C[4])
				buf.line(px_x - ux * ln * 0.45, px_y - uy * ln * 0.45, px_x, px_y, hot)
				light.glow(px_x, px_y, 3, hot, 0.45 * k)
			CHIP:
				if k > 0.25 or Sf.bayer(px, py) < k * 4:
					buf.put(px, py, p.col)
					if p.size >= 2:
						buf.put(px + 1, py, p.col)
						buf.put(px, py + 1, Sf.scale(p.col, 0.8))
			DUST:
				buf.alpha_disc(px_x, px_y, p.size * (0.6 + (1 - k) * 0.9), p.col, pow(k, 1.3) * 0.7)
			SMOKE:
				var age := 1 - k
				var r := p.size * (0.65 + minf(1, age * 2.5) * 0.45 + age * 0.4)
				var a := minf(1, age * 12) * minf(1, k * 2.4) * 0.5
				var c := Sf.mix(p.col, Sf.ramp(SMOKE_RAMP, age), age)
				buf.alpha_disc(px_x, px_y, r, c, a * 0.45)
				buf.alpha_disc(px_x + r * 0.05, px_y + r * 0.06, r * 0.74, c, a * 0.62)

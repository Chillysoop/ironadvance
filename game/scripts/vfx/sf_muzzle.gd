class_name SfMuzzle
extends RefCounted
## V3, Sprite Fusion muzzle-flash.ts: a two-frame lobed flash (a long main tongue, side
## tongues and a back puff) with a hot core, sparks out of the barrel, gun smoke and wisps
## curling up, and a hard pop of light. The brass casing stays effects.gd's own.

const SPARK := 0
const SMOKE := 1
const WHITE := Color("ffffff")
const HOT := Color("fff3a6")
const YELLOW := Color("ffe26b")
const ORANGE := Color("ff8a2a")
const DEEP := Color("f2561d")
const RED := Color("c9281f")
const WARM := Color8(255, 176, 96)
const SMOKE_C := Color("5b5566")
const WISP := Color("7a7186")
const SMOKE_RAMP := [Color("7b6f72"), Color("5d5660"), Color("433d48"), Color("2b2630"), Color("1a171e")]

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
var X := 0.0
var Y := 0.0
var A := 0.0
var S := 1.0
var shape: Array = []
var seed_x := 0.0

func _init(x: float, y: float, angle: float, size: float, ground_fn: Callable, smoke := true, sparks := -1) -> void:
	X = x
	Y = y
	A = angle
	S = size
	ground = ground_fn
	seed_x = x
	var c := cos(A)
	var s := sin(A)
	var spin := R.rnd(-0.35, 0.35)
	var jit: Array = []
	for i in 9:
		jit.append(R.rnd(0.8, 1.2))
	shape = [lobes(1, spin, jit), lobes(2, spin, jit)]
	for i in (sparks if sparks >= 0 else roundi(4 + 3 * S)):
		var a := A + R.rnd(-1, 1) * 0.32
		var sp := R.rnd(300, 760) * (0.7 + 0.3 * S)
		spawn(SPARK, X + c * 4, Y + s * 4, cos(a) * sp, sin(a) * sp, R.rnd(0.05, 0.15))
	if smoke:
		for i in roundi(1 + S * 2.5):
			var a := A + R.rnd(-0.5, 0.5)
			var sp := R.rnd(20, 90) * S
			spawn(SMOKE, X + c * 3, Y + s * 3, cos(a) * sp, sin(a) * sp - 10, R.rnd(0.45, 0.9), SMOKE_C, R.rnd(1.2, 2.2) * sqrt(S))
		for i in 4:
			var k := i / 3.0
			spawn(SMOKE, X + c * 2, Y + s * 2, c * (40 - 30 * k) * S + R.rnd(-6, 6), s * (40 - 30 * k) * S - (14 + 26 * k), R.rnd(0.9, 1.4), WISP, R.rnd(0.9, 1.4) * sqrt(S), 0.04 + i * 0.05)

func lobes(f: int, spin: float, jit: Array) -> Array:
	## [off, a, len, wid, core]
	var k := 1.0 if f == 1 else 0.6
	var w := 1.0 if f == 1 else 0.7
	var L := [[0.5, 0.0, 9 * S * k, 2.4 * S * w, 0.55], [2.0, 0.0, 21 * S * k * jit[0], 1.15 * S * w, 0.4]]
	for side in [-1, 1]:
		L.append([2.0, side * (0.72 + spin * side * 0.4), 8.5 * S * k * jit[side + 2], 1.35 * S * w, 0.3])
		if f == 1:
			L.append([1.0, side * (2.2 - spin * side * 0.4), 4 * S * jit[side + 4], 1.1 * S, 0.0])
	return L

static func profile(l: Array, u: float) -> float:
	var k: float = u / l[2]
	return l[3] * pow(maxf(0, 1 - k), 0.8) * minf(1, 0.45 + k * 3)

func spawn(k: int, x: float, y: float, vx: float, vy: float, life: float, col := Color(0, 0, 0, 0), size := 1.0, delay := 0.0) -> void:
	var p := Part.new()
	p.k = k; p.x = x; p.y = y; p.vx = vx; p.vy = vy; p.life = life; p.mx = life
	p.col = col; p.size = size; p.seed = R.next() * 100; p.delay = delay
	list.append(p)

func done() -> bool:
	return t > 0.2 and list.is_empty()

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
		if p.k == SPARK:
			p.vy += Sf.GRAVITY * 0.45 * dt
			p.vx -= p.vx * 2.2 * dt
			p.vy -= p.vy * 2.2 * dt
			var ny := p.y + p.vy * dt
			var g: float = ground.call(p.x)
			p.x += p.vx * dt
			if p.vy > 0 and p.y <= g and ny >= g:
				p.vy = -p.vy * 0.45
				p.vx *= 0.7
				p.y = g - 0.5
			else:
				p.y = ny
		else:
			p.vy -= 32 * dt
			p.vx += sin(pt * 1.3 + p.seed) * 16 * dt
			p.vx -= p.vx * 1.6 * dt
			p.vy -= p.vy * 1.2 * dt
			p.x += p.vx * dt
			p.y += p.vy * dt

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		draw_parts(buf, light, true)
		return
	var f := maxi(1, ceili(t * 60 - 1e-6))
	var ax := X / Sf.PX
	var ay := Y / Sf.PX
	if f <= 2:
		flash(buf, ax, ay, f, shape[f - 1], floori(t * 1000 + seed_x))
	draw_parts(buf, light, false)
	var pop := exp(-t / 0.03)
	if pop > 0.02:
		light.glow(ax + cos(A) * 4 * S, ay + sin(A) * 4 * S, 18 * S + 8, WARM, 0.85 * pop)
		light.glow(ax + cos(A) * 2, ay + sin(A) * 2, 6 * S + 3, WHITE, 0.6 * pop)

func flash(buf: Sf.Px, ax: float, ay: float, f: int, L: Array, seed: int) -> void:
	var c := cos(A)
	var s := sin(A)
	var ext := 2.0
	for l in L:
		ext = maxf(ext, l[0] + l[2] + 2)
	var core := WHITE if f == 1 else HOT
	var body := YELLOW if f == 1 else ORANGE
	var inner := HOT if f == 1 else YELLOW
	var rim := DEEP if f == 1 else RED
	var lc: Array = []
	for l in L:
		lc.append(Vector2(cos(l[1]), sin(l[1])))
	for py in range(floori(ay - ext), ceili(ay + ext) + 1):
		for px in range(floori(ax - ext), ceili(ax + ext) + 1):
			var dx := px + 0.5 - ax
			var dy := py + 0.5 - ay
			var along := dx * c + dy * s
			var across := -dx * s + dy * c
			var m := -9.0
			var hot := false
			var warm := false
			for li in L.size():
				var l: Array = L[li]
				var ca: float = lc[li].x
				var sa: float = lc[li].y
				var lu: float = (along - l[0]) * ca + across * sa
				var lv: float = -(along - l[0]) * sa + across * ca
				if lu < -1.5 or lu > l[2] + 1:
					continue
				var r := profile(l, maxf(0, lu))
				var mm := r - absf(lv)
				if mm > m:
					m = mm
				if lu < l[2] * l[4] and absf(lv) <= r * 0.5:
					hot = true
				if mm > r * 0.4:
					warm = true
			var dm := 1.6 - Vector2(along - 0.5, across).length()
			if dm > m:
				m = dm
			if dm > 0.5:
				hot = true
			m += (Sf.hsh(px * 73 + py * 151, seed) - 0.5) * 0.5 * minf(1, ext / 14)
			if m < -0.85:
				continue
			buf.put(px, py, rim if m < 0 else (core if hot else (inner if warm else body)))

func draw_parts(buf: Sf.Px, light: Sf.Px, back: bool) -> void:
	for p in list:
		if p.delay > 0 or (p.k == SMOKE) != back:
			continue
		var k := p.life / p.mx
		var ax := p.x / Sf.PX
		var ay := p.y / Sf.PX
		if p.k == SMOKE:
			var age := 1 - k
			var r := p.size * (0.65 + minf(1, age * 2.5) * 0.45 + age * 0.4)
			var a := minf(1, age * 12) * minf(1, k * 2.4) * 0.58
			var c := Sf.mix(p.col, Sf.ramp(SMOKE_RAMP, age), age)
			buf.alpha_disc(ax, ay, r, c, a * 0.45)
			buf.alpha_disc(ax + r * 0.05, ay + r * 0.06, r * 0.74, c, a * 0.62)
			if age < 0.5:
				buf.alpha_disc(ax - r * 0.22, ay - r * 0.3, r * 0.5, Sf.mix(c, WHITE, 0.12), a * 0.4 * (1 - age * 2))
		else:
			var hot := HOT if k > 0.6 else (YELLOW if k > 0.3 else ORANGE)
			var sp := maxf(0.001, Vector2(p.vx, p.vy).length())
			var ux := p.vx / sp
			var uy := p.vy / sp
			var ln := minf(9, 1 + sp * 0.011)
			buf.line(ax - ux * ln, ay - uy * ln, ax - ux * ln * 0.4, ay - uy * ln * 0.4, hot if k > 0.5 else DEEP)
			buf.line(ax - ux * ln * 0.45, ay - uy * ln * 0.45, ax, ay, hot)
			light.glow(ax, ay, 3, hot, 0.45 * k)

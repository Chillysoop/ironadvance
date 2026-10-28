class_name SfFire
extends RefCounted
## V4, Sprite Fusion fire.ts: flames that cling to a body's outline. Tongues rise from the top of
## each pair of columns of the silhouette, lean with movement and wind, shed licks, flames,
## embers and smoke, and the body itself flickers with heat. Follows its source every tick and
## burns down over 1.2 s once stopped.

const FLAME := 0
const SMOKE_K := 1
const EMBER := 2
const SEED := 37
const GL := 0.9
const FIRE := [Color("ffffff"), Color("fff3a6"), Color("ffe26b"), Color("ffc23d"), Color("ff8a2a"), Color("f2561d"), Color("c9281f"), Color("8a1f17"), Color("4a1712")]
const SMOKE_RAMP := [Color("7b6f72"), Color("5d5660"), Color("433d48"), Color("2b2630"), Color("1a171e")]
const SOOT := Color("0d0a12")
const WARM := Color8(255, 176, 96)
const LAYERS := [[1.0, 1.0, 6], [0.76, 0.86, 4], [0.54, 0.68, 2], [0.3, 0.42, 0]]

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
	var smokes := false

var R := Sf.Rng.new()
var src: Callable  # -> [xs, ys, feet] or [] when the source is gone
var RAMP: Array = FIRE
var HEAT: Array = []
var GLOW := WARM
var SMOKE := Color()
var S := 1.0
var sS := 1.0
var WIND := 0.0
var list: Array[Part] = []
var licks: Array = []  # [x, y, vx, vy, s, life, max]
var bx := PackedInt32Array()
var by := PackedInt32Array()
var top := {}
var tongues: Array = []  # [dx, h, w, dy]
var t := 0.0
var stop_at := 1e9
var lv := 0.0
var ax := 0.0
var ay := 0.0
var x := 0.0
var y := 0.0
var vx := 0.0
var vy := 0.0
var lean := 0.0
var stretch := 0.0
var placed := false

func _init(source: Callable, size := 1.0, wind := 0.0, duration := 1e9) -> void:
	src = source
	S = size
	sS = sqrt(S)
	WIND = wind
	stop_at = duration
	HEAT = RAMP.slice(0, 8) + [Sf.mix(RAMP[8], SOOT, 0.35), Sf.mix(RAMP[8], SOOT, 0.65)]
	SMOKE = Sf.mix(Color("5b5566"), RAMP[6], 0.25)

func stop() -> void:
	stop_at = minf(stop_at, t)

func done() -> bool:
	return t > stop_at + 1.2 and list.is_empty()

func lit() -> float:
	return Sf.smooth(0, 0.3, t) * clampf(1 - (t - stop_at) / 1.2, 0, 1)

func read() -> void:
	var s: Array = src.call()
	if s.is_empty():
		stop()
		return
	bx = s[0]
	by = s[1]
	ax = s[2].x
	ay = s[2].y

func place() -> void:
	if bx.is_empty():
		return
	var x0 := 1 << 30
	for v in bx:
		x0 = mini(x0, v)
	top.clear()
	for i in bx.size():
		var j := bx[i] - x0
		if not top.has(j) or by[i] < top[j]:
			top[j] = by[i]
	var fx := ax / Sf.PX
	var fy := ay / Sf.PX
	tongues = []
	var keys := top.keys()
	keys.sort()
	for j in keys:
		if j % 2 == 0:
			tongues.append([x0 + j - fx, 5 + 5 * Sf.hsh(j, 2), 1.5 + 0.6 * Sf.hsh(j, 3), top[j] - fy + 1])
	for k in 4:
		var i := int(Sf.hsh(k, 9) * bx.size())
		tongues.append([bx[i] - fx, 4 + 3 * Sf.hsh(k, 4), 1.3, by[i] - fy + 1])

func flick(tt: float) -> float:
	return 0.74 + 0.16 * Sf.noise(tt * 7.3, 1) + 0.1 * Sf.noise(tt * 19, 2)

func height(i: int) -> float:
	var h: float = tongues[i][1]
	var n := SEED + i
	var leap := maxf(0, Sf.noise(t * 2.6 + n * 3.1, n + 70) - 0.55) * 1.6
	return (h + 0.25 * h * Sf.noise(t * 3.3 + n * 1.7, n) + h * leap) * (0.9 + 0.1 * flick(t)) * S * lv * (1 + stretch)

func tip(i: int) -> Vector2:
	var h := height(i)
	return Vector2(x + (tongues[i][0] + lean * h * 0.9) * Sf.PX, y + (tongues[i][3] - h * 0.88 + 4) * Sf.PX)

func move(dt: float) -> void:
	if not placed:
		x = ax
		y = ay
		placed = true
	var k := 1 - exp(-dt * 10)
	var kl := 1 - exp(-dt * 7)
	vx += ((ax - x) / dt - vx) * k
	vy += ((ay - y) / dt - vy) * k
	x = ax
	y = ay
	lean += (clampf((-vx + WIND) / 520, -1.3, 1.3) - lean) * kl
	stretch += (clampf(vy / 900, -0.3, 0.45) - stretch) * kl

func spawn(k: int, px: float, py: float, pvx: float, pvy: float, life: float, col := Color(0, 0, 0, 0), size := 1.0, smokes := false) -> void:
	var p := Part.new()
	p.k = k; p.x = px; p.y = py; p.vx = pvx; p.vy = pvy; p.life = life; p.mx = life
	p.col = col; p.size = size; p.seed = R.next() * 100; p.smokes = smokes
	list.append(p)

func shed(dt: float) -> void:
	var speed := Vector2(vx, vy).length()
	var L := lv * 0.7
	for i in tongues.size():
		if L <= 0.02:
			continue
		if R.chance(0.18 * L):
			var tp := tip(i)
			spawn(FLAME, tp.x + R.rnd(-2, 2), tp.y + R.rnd(0, 8), R.rnd(-8, 8) + WIND * 0.3, R.rnd(-60, -30), R.rnd(0.14, 0.3), Color(0, 0, 0, 0), R.rnd(0.8, 1.6) * sS, R.chance(0.45))
		if R.chance((0.075 + speed / 2700) * L):
			var tp := tip(i)
			licks.append([tp.x / Sf.PX, tp.y / Sf.PX, R.rnd(-6, 6) + WIND * 0.15, R.rnd(-40, -24), R.rnd(0.9, 1.7) * sS, 0.26, 0.26])
		if R.chance(0.024 * L * S):
			spawn(EMBER, x + (tongues[i][0] + R.rnd(-3, 3)) * Sf.PX, y - R.rnd(10, 24) * S, R.rnd(-30, 30) + WIND * 0.4, R.rnd(-120, -50), R.rnd(0.9, 2.2))
		if R.chance(0.017 * L):
			var tp := tip(i)
			spawn(SMOKE_K, tp.x, tp.y - 6, R.rnd(-5, 5) + WIND * 0.5, R.rnd(-34, -20), R.rnd(1.6, 2.6), SMOKE, R.rnd(1.6, 2.8) * sS)
	for i in range(licks.size() - 1, -1, -1):
		var l: Array = licks[i]
		l[5] -= dt
		if l[5] <= 0:
			licks.remove_at(i)
			continue
		l[0] += l[2] * dt + Sf.noise(t * 8 + i, 3) * 0.15
		l[1] += l[3] * dt

func update(dt: float) -> void:
	t += dt
	read()
	place()
	lv = lit()
	move(dt)
	shed(dt)
	if bx.size() and R.chance(0.7 * lv):
		var i := int(R.next() * bx.size())
		spawn(FLAME, bx[i] * Sf.PX, by[i] * Sf.PX, R.rnd(-10, 10) - vx * 0.2, R.rnd(-80, -40), R.rnd(0.16, 0.3), Color(0, 0, 0, 0), R.rnd(1, 1.8) * sS)
	if bx.size() and R.chance(0.16 * lv):
		spawn(SMOKE_K, bx[0] * Sf.PX, by[0] * Sf.PX - 8, R.rnd(-6, 6) - vx * 0.3, R.rnd(-40, -20), R.rnd(1.2, 2), SMOKE, R.rnd(2, 3.2))
	for i in range(list.size() - 1, -1, -1):
		var p := list[i]
		p.life -= dt
		if p.life <= 0:
			if p.smokes:
				spawn(SMOKE_K, p.x, p.y, p.vx * 0.6, p.vy * 0.6 - 12, R.rnd(0.8, 1.4), Color(0, 0, 0, 0), p.size * 0.7)
			list.remove_at(i)
			continue
		if p.k == FLAME:
			p.vy -= 190 * dt
			p.vx += sin(t * 17 + p.seed) * 60 * dt
			p.vx -= p.vx * 5 * dt
			p.vy -= p.vy * 3.2 * dt
		elif p.k == SMOKE_K:
			p.vy -= 32 * dt
			p.vx += sin(t * 1.3 + p.seed) * 16 * dt
			p.vx -= p.vx * 1.6 * dt
			p.vy -= p.vy * 1.2 * dt
		else:
			p.vy += (-60 + sin(t * 3 + p.seed) * 40) * dt
			p.vx += cos(t * 2.3 + p.seed) * 90 * dt
			p.vx -= p.vx * 1.6 * dt
			p.vy -= p.vy * 1.6 * dt
		p.x += p.vx * dt
		p.y += p.vy * dt

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		draw_parts(buf, light, true)
	else:
		flames(buf, light)
		draw_parts(buf, light, false)

func flames(buf: Sf.Px, light: Sf.Px) -> void:
	for i in bx.size():
		var h := Sf.hsh(bx[i] * 73 + by[i] * 151, 5)
		if h > 0.2:
			continue
		var T := clampf(0.4 + 0.6 * Sf.noise(t * (5 + h * 20), bx[i] * 7 + by[i]), 0, 1) * lv
		if T > 0.45:
			buf.put(bx[i], by[i], HEAT[mini(9, 2 + int((1 - T) * 7))])
	var fx := x / Sf.PX
	var fy := y / Sf.PX
	var n := tongues.size()
	var order := range(n)
	order.sort_custom(func(a, b2): return absf(tongues[a][0]) > absf(tongues[b2][0]))
	for i in order:
		var tg: Array = tongues[i]
		var h := height(i)
		var m: int = SEED + i
		if h < 1:
			continue
		tongue(buf, fx + tg[0], fy + tg[3] + 1, h, tg[2] * sS * (1 - 0.25 * absf(lean)), Sf.noise(t * 2.2 + m, m + 40) * 2 * S + lean * h * 0.9 - clampf(tg[0] * 0.25, -2, 2), m * 13)
	for l in licks:
		var k: float = l[5] / l[6]
		var r: float = l[4] * (0.4 + 0.6 * k)
		buf.disc(l[0], l[1], r + 0.6, RAMP[5] if k > 0.5 else RAMP[6])
		if k > 0.35:
			buf.disc(l[0], l[1] - 0.3, r * 0.6, RAMP[2] if k > 0.7 else RAMP[4])
	var fl := flick(t)
	var br := 0.92 + 0.08 * sin(t * 2.1)
	if n <= 7:
		var k := fl * maxf(0.15, lv if n else 0.0) * minf(1, (lv if n else 0.0) * 4)
		var g := GL * sS
		light.glow(fx + lean * 4, fy - 8 * S, 70 * g * br * (0.9 + 0.1 * fl), GLOW, 0.4 * k)
		light.glow(fx, fy - 6 * S, 22 * g, RAMP[2], 0.32 * k)
		light.glow(fx, fy - 2, 9 * GL, RAMP[0], 0.18 * k)
	else:
		for i in range(2, n, 5):
			var tg: Array = tongues[i]
			light.glow(fx + tg[0], fy + tg[3] - 10 * S, 50 * GL * sS * br, GLOW, 0.36 * fl * lv)
			light.glow(fx + tg[0], fy + tg[3] - 3, 16 * GL * sS, RAMP[2], 0.26 * fl * lv)

func tongue(buf: Sf.Px, tx: float, ty: float, h: float, w: float, sx: float, n: int) -> void:
	if h < 1:
		return
	for L in LAYERS:
		var H: float = h * L[1]
		var col: Color = RAMP[L[2]]
		for r in range(0, int(H) + 1):
			var u: float = r / maxf(1, H)
			var half: float = w * L[0] * pow(1 - u, 0.85) * minf(1, (r + 1.5) / 3.5) + Sf.noise(t * 9 + r * 0.45, n) * 0.5
			var cx: float = tx + sx * u * u * L[1] + Sf.noise(t * 4 + r * 0.2, n + 7) * u * 1.1
			if half < 0.3:
				continue
			buf.span(roundi(cx - half), roundi(cx + half), roundi(ty - r), col)

func draw_parts(buf: Sf.Px, light: Sf.Px, smoke: bool) -> void:
	for p in list:
		if (p.k == SMOKE_K) != smoke:
			continue
		var k := p.life / p.mx
		var age := 1 - k
		var px := p.x / Sf.PX
		var py := p.y / Sf.PX
		if p.k == SMOKE_K:
			var r := p.size * (0.65 + minf(1, age * 2.5) * 0.45 + age * 0.4)
			var a := minf(1, age * 12) * minf(1, k * 2.4) * 0.55
			var c := Sf.mix(p.col, Sf.ramp(SMOKE_RAMP, age), age) if p.col.a > 0 else Sf.ramp(SMOKE_RAMP, age * 1.05)
			buf.alpha_disc(px, py, r, c, a * 0.45)
			buf.alpha_disc(px + r * 0.05, py + r * 0.06, r * 0.74, c, a * 0.62)
			if age < 0.5:
				buf.alpha_disc(px - r * 0.22, py - r * 0.3, r * 0.5, Sf.mix(c, RAMP[0], 0.12), a * 0.4 * (1 - age * 2))
		elif p.k == FLAME:
			var heat := minf(0.999, pow(age, 0.62) + fmod(p.seed, 1.0) * 0.1)
			var idx := mini(7, int(heat * 8))
			var r := p.size * (0.55 + 0.45 * minf(1, age * 7)) * (1 - age * 0.55)
			var c: Color = RAMP[idx]
			if idx >= 7:
				buf.alpha_disc(px, py, r, c, minf(1, k * 3) * 0.85)
			else:
				buf.disc(px, py, r, RAMP[mini(8, idx + 2)])
				buf.disc(px - r * 0.16, py - r * 0.22, r * 0.78, c)
				if r > 1.6:
					buf.disc(px, py - r * 0.9, r * 0.42, c)
				if idx <= 3 and r > 1.8:
					buf.disc(px - r * 0.28, py - r * 0.34, r * 0.36, RAMP[maxi(0, idx - 1)])
				if idx < 6:
					light.glow(px, py, r * 2.4 + 2, c, 0.18 * k)
		else:
			var c: Color = ((RAMP[2] if sin(t * 22 + p.seed * 3) > -0.2 else RAMP[4]) if k > 0.5 else (RAMP[4] if k > 0.2 else RAMP[6]))
			buf.put(floori(px), floori(py), c)
			light.glow(px, py, 3, c, 0.3 * k)

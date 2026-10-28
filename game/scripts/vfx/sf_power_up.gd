class_name SfPowerUp
extends RefCounted
## V13, Sprite Fusion power-up.ts: motes rush in, the body flashes, a shock line runs along the
## ground, then a flickering aura of flame-light hugs the outline (taller above the waist) with
## streaks, wisps and twinkling stars, and fades after about three seconds. The aura is a
## distance field around the soldier's silhouette, taken once when it starts.

const BURST := 0.32
const HOLD := 1.75
const FADE := 2.35
const END := 2.95
const PULSE1 := BURST + 0.55
const PULSE2 := BURST + 1.0
const BW := 64
const BH := 76
const IN := 0
const DUSTK := 1
const STREAK := 2
const STAR := 3
const WISP := 4
const WHITE := Color("ffffff")
const DUSTC := Color("6a5e82")
const CYAN := ["ffffff", "e0fcff", "8ff0ff", "3fd0ff", "2290e6", "1f4fab", "172a68"]
const EMBER := ["ffffff", "fff3a6", "ffe26b", "ff8a2a", "f2561d", "c9281f", "4a1712"]

var R := Sf.Rng.new()
var C: Array = []
var TOP: Array = []
var S := 1.0
var feet: Callable   # -> Vector2 world
var motes: Array = []  # [k, x, y, vx, vy, life, max, c, s, front]
var mask := PackedByteArray()
var on_body: Array = []  # mask cells as Vector2i
var cells: Array = []    # aura cells [x, y, d]
var t := 0.0
var burst := false
var bx0 := 0
var by0 := 0
var mid_y := 0.0
var base := Vector2i()   # feet (art px) when the mask was taken

func _init(feet_fn: Callable, sil: Array, palette: Array = CYAN, size := 1.0) -> void:
	feet = feet_fn
	S = size
	for h in palette:
		C.append(Color(h))
	TOP = [C[0], C[1], C[2]]
	build(sil)

func build(sil: Array) -> void:
	var f: Vector2 = feet.call()
	var cx := roundi(f.x / Sf.PX)
	var cy := roundi(f.y / Sf.PX)
	base = Vector2i(cx, cy)
	mask.resize(BW * BH)
	mask.fill(0)
	var x0 := cx - BW / 2
	var y0 := cy - BH + 6
	var xs: PackedInt32Array = sil[0]
	var ys: PackedInt32Array = sil[1]
	for i in xs.size():
		var x := xs[i] - x0
		var y := ys[i] - y0
		if x >= 0 and y >= 0 and x < BW and y < BH:
			mask[y * BW + x] = 1
	var dist := PackedInt32Array()
	dist.resize(BW * BH)
	for i in mask.size():
		dist[i] = 0 if mask[i] else 255
		if mask[i]:
			on_body.append(Vector2i(i % BW, i / BW))
	for y in BH:
		for x in BW:
			var i := y * BW + x
			if x > 0:
				dist[i] = mini(dist[i], dist[i - 1] + 3)
			if y > 0:
				dist[i] = mini(dist[i], dist[i - BW] + 3)
				if x > 0:
					dist[i] = mini(dist[i], dist[i - BW - 1] + 4)
				if x < BW - 1:
					dist[i] = mini(dist[i], dist[i - BW + 1] + 4)
	for y in range(BH - 1, -1, -1):
		for x in range(BW - 1, -1, -1):
			var i := y * BW + x
			if x < BW - 1:
				dist[i] = mini(dist[i], dist[i + 1] + 3)
			if y < BH - 1:
				dist[i] = mini(dist[i], dist[i + BW] + 3)
				if x < BW - 1:
					dist[i] = mini(dist[i], dist[i + BW + 1] + 4)
				if x > 0:
					dist[i] = mini(dist[i], dist[i + BW - 1] + 4)
	var cap := minf(24.0, 32.0 * S)
	for y in BH:
		for x in BW:
			var d := dist[y * BW + x] / 3.0
			if d > 0 and d <= cap:
				cells.append([x, y, d])

func origin() -> Vector2i:
	## Where the mask sits now: it was taken at base and follows the feet.
	var f: Vector2 = feet.call()
	var cx := roundi(f.x / Sf.PX)
	var cy := roundi(f.y / Sf.PX)
	bx0 = cx - BW / 2
	by0 = cy - BH + 6
	mid_y = cy - 22 * S
	return Vector2i(cx, cy)

func aura() -> float:
	return Sf.smooth(BURST - 0.04, BURST + 0.12, t) * (1 - Sf.smooth(HOLD, FADE, t)) * (0.85 + 0.15 * sin(t * 13))

func flare() -> float:
	return maxf(exp(-pow((t - PULSE1) / 0.07, 2)), exp(-pow((t - PULSE2) / 0.07, 2))) + exp(-pow((t - BURST) / 0.08, 2))

func body_pt() -> Vector2:
	if on_body.is_empty():
		return Vector2(bx0 + BW / 2.0, mid_y)
	var c: Vector2i = R.pick(on_body)
	return Vector2(bx0 + c.x + 0.5, by0 + c.y + 0.5)

func done() -> bool:
	return t > END and motes.is_empty()

func update(dt: float) -> void:
	t += dt
	origin()
	var f: Vector2 = feet.call()
	var ccx := f.x / Sf.PX
	var ccy := mid_y
	if t < BURST:
		for i in roundi(3 * S):
			var a := R.rnd(0, TAU)
			var r := R.rnd(34, 64) * sqrt(S)
			var sp := R.rnd(260, 420)
			motes.append([IN, ccx + cos(a) * r, ccy + sin(a) * r * 0.8, -cos(a) * sp, -sin(a) * sp * 0.8, r * Sf.PX / sp, r * Sf.PX / sp, C[1] if R.chance(0.3) else C[2], 1.0, true])
	if not burst and t >= BURST:
		burst = true
		for i in int(18 * S):
			var side := R.sgn()
			motes.append([DUSTK, ccx + side * R.rnd(2, 10), f.y / Sf.PX - R.rnd(0, 3), side * R.rnd(60, 170), -R.rnd(2, 16), R.rnd(0.45, 0.8), 0.8, Sf.mix(DUSTC, C[4], 0.25), R.rnd(1.5, 3), false])
		for i in int(22 * S):
			var p := body_pt()
			motes.append([STAR, p.x, p.y, R.rnd(-40, 40), -R.rnd(30, 110), R.rnd(0.6, 1.3), 1.3, R.pick(TOP), 2.0 if R.chance(0.35) else (1.0 if R.chance(0.5) else 0.0), R.chance(0.6)])
	var a := aura()
	if burst and a > 0.05:
		var n := 0.0
		while n < (5 + 5 * flare()) * a * S * dt * 10:
			var p := body_pt()
			var side := R.sgn()
			motes.append([STREAK, p.x + side * R.rnd(5, 16) * sqrt(S), ccy + R.rnd(-16, 26) * S, 0.0, -R.rnd(220, 420), R.rnd(0.14, 0.3), 0.3, C[2] if R.chance(0.5) else C[1], R.rnd(6, 16) * S, R.chance(0.5)])
			n += 1
		n = 0.0
		while n < 9 * a * S * dt:
			var p := body_pt()
			var up := clampf((mid_y - p.y) / 16, 0, 1)
			n += 1
			if R.chance(1 - up * 0.8):
				continue
			motes.append([WISP, p.x + R.rnd(-4, 4), p.y - R.rnd(6, 12) * S, R.rnd(-15, 15), -R.rnd(70, 130), R.rnd(0.3, 0.55), 0.55, C[2], R.rnd(1.4, 2.4) * sqrt(S), false])
		if R.chance(0.5 * a):
			var p := body_pt()
			motes.append([STAR, p.x + R.rnd(-8, 8), p.y, R.rnd(-10, 10), -R.rnd(25, 70), R.rnd(0.6, 1.1), 1.1, R.pick(TOP), 1.0 if R.chance(0.25) else 0.0, R.chance(0.5)])
	for i in range(motes.size() - 1, -1, -1):
		var m: Array = motes[i]
		m[5] -= dt
		if m[5] <= 0:
			motes.remove_at(i)
			continue
		var drag := 3.5 if m[0] == DUSTK else (1.4 if m[0] == STAR else 0.0)
		m[3] -= m[3] * drag * dt
		m[4] -= m[4] * drag * dt
		if m[0] == STAR:
			m[4] -= 18 * dt
		m[1] += m[3] * dt / Sf.PX
		m[2] += m[4] * dt / Sf.PX

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	var o := origin()
	var cx := float(o.x)
	var gy := float(o.y)
	var a := aura()
	var fl := flare()
	if layer == 0:
		for m in motes:
			if m[0] == DUSTK:
				buf.alpha_disc(m[1], m[2], m[8] * (1.6 - (m[5] / m[6]) * 0.6), m[7], (m[5] / m[6]) * 0.6)
		if a > 0.02:
			var ncache := {}
			for c in cells:
				var px: int = bx0 + c[0]
				var py: int = by0 + c[1]
				var d: float = c[2]
				var nk := Vector2i(px >> 1, py)
				var nz: float
				if ncache.has(nk):
					nz = ncache[nk]
				else:
					nz = pow(Sf.noise2(px * 0.5, (py + t * 34) * 0.26, 7) * 0.5 + 0.5, 1.4)
					ncache[nk] = nz
				var up := clampf((mid_y - py) / 16, 0, 1)
				var reach := a * S * (3.4 + 14 * nz * (0.3 + 1.15 * up)) * (1 + 0.3 * fl)
				if d > reach:
					continue
				var band := d / reach
				if band < 0.22:
					buf.put(px, py, C[0] if fl > 0.35 and band < 0.14 else C[1])
				elif band < 0.45:
					buf.put(px, py, C[2])
				elif band < 0.7:
					buf.put(px, py, C[3])
				elif Sf.bayer(px, py) < (1 - band) * 2.6:
					buf.put(px, py, C[4] if band < 0.86 else C[5])
		for m in motes:
			if not m[9]:
				draw_mote(buf, light, m)
		light.glow(cx, mid_y, (34 + 20 * fl) * S, C[3], (0.35 * a + 0.3 * fl) * minf(1.4, S))
		light.glow(cx, gy - 2, 30 * S, C[2], 0.25 * a)
		return
	if burst:
		shockline(buf, light, cx, gy, t - BURST, 0.45 * S)
	var e := 0.0
	if burst:
		for p in [BURST, PULSE1, PULSE2]:
			e = maxf(e, exp(-pow((t - p) / 0.07, 2)))
	if e > 0.03 and not on_body.is_empty():
		var sx := 0.0
		var top_y := 1e9
		var bot := -1.0
		for c in on_body:
			var x: int = bx0 + c.x
			var y: int = by0 + c.y
			sx += x
			top_y = minf(top_y, y)
			bot = maxf(bot, y)
			buf.dot(x, y, (C[0] if e > 0.75 else C[1]), e * 1.5)
		light.glow(sx / on_body.size(), (top_y + bot) / 2, 26, C[3], 0.45 * e)
	for m in motes:
		if m[9]:
			draw_mote(buf, light, m)

func draw_mote(buf: Sf.Px, light: Sf.Px, m: Array) -> void:
	var k: float = m[5] / m[6]
	var x: float = m[1]
	var y: float = m[2]
	var c: Color = m[7]
	match m[0]:
		IN:
			var sp := maxf(0.001, Vector2(m[3], m[4]).length())
			var ux: float = m[3] / sp
			var uy: float = m[4] / sp
			buf.line(x - ux * 7, y - uy * 7, x - ux * 3, y - uy * 3, c)
			buf.line(x - ux * 2.5, y - uy * 2.5, x, y, WHITE)
		STREAK:
			var l: float = m[8] * (0.5 + 0.5 * k)
			for j in int(l) + 1:
				buf.dot(x, y + j, WHITE if j < 1.5 else c, 1.0 if j < l * 0.5 else (1 - j / (l + 1)) * 1.6)
			light.glow(x, y + l * 0.3, 4, c, 0.3 * k)
		WISP:
			var r: float = m[8] * (0.35 + 0.65 * k)
			buf.disc(x, y, r + 0.7, c if k > 0.5 else Sf.scale(c, 0.7))
			if k > 0.35:
				buf.disc(x - 0.3, y - 0.4, r * 0.55, WHITE if k > 0.7 else c)
			light.glow(x, y, 5 + r * 2, c, 0.3 * k)
		STAR:
			var px := floori(x)
			var py := floori(y)
			var tw := 0.6 + 0.4 * sin(m[5] * 26 + x)
			if tw * k < 0.2:
				return
			var arm := roundi(m[8] * tw * minf(1, k * 2.5))
			for d in range(1, arm + 1):
				var cc := Sf.scale(c, 0.75) if d == arm and arm > 1 else c
				buf.put(px + d, py, cc)
				buf.put(px - d, py, cc)
				buf.put(px, py + d, cc)
				buf.put(px, py - d, cc)
			buf.put(px, py, WHITE if tw > 0.75 else c)
			light.glow(x, y, 3 + arm * 2, c, 0.45 * k * tw)

func shockline(buf: Sf.Px, light: Sf.Px, cx: float, fy: float, tt: float, z: float) -> void:
	var Rr := 72 * z
	var q := tt / 0.55
	if q < 0 or q >= 1.8:
		return
	if q < 0.5:
		for dx in range(-roundi(14 * z), int(14 * z) + 1):
			var u := absf(dx) / (14 * z)
			var a := (1 - q / 0.5) * (1 - u) * 2.2
			buf.dot(cx + dx, fy, WHITE if u < 0.3 else (C[1] if u < 0.6 else C[2]), a)
			buf.dot(cx + dx, fy - 1, C[1] if u < 0.4 else C[2], a * 0.7)
			buf.dot(cx + dx, fy + 1, C[2], a * 0.5)
	var reach := 4 + Rr * Sf.out_expo(minf(1, q))
	var after := 1 - clampf((q - 0.25) / 1.4, 0, 1)
	var f := floori(tt * 20)
	for dx in range(-roundi(reach), int(reach) + 1):
		var u := absf(dx) / reach
		var g := Sf.hsh(roundi(cx + dx) * 7 + f * 613) < 0.04 * after
		buf.dot(cx + dx, fy, WHITE if g else (C[2] if u < 0.5 else C[3]), 1.0 if g else after * 0.8 * (1 - u * 0.5))
		buf.dot(cx + dx, fy - 1, C[3], after * 0.3 * (1 - u))
	if q < 1:
		var head := 4 + Rr * Sf.out_expo(q)
		var ln := (6 + 22 * (1 - q)) * z
		var crest := 6 * z * pow(1 - q, 0.7)
		for sd in [-1, 1]:
			for j in int(ceil(ln)):
				var x: float = cx + sd * (head - j)
				var a := (1 - j / ln) * (1 - q) * 2.2
				var lift := roundi(crest * maxf(0, 1 - j / (ln * 0.5)))
				buf.dot(x, fy, WHITE if j < 2 else (C[1] if j < ln * 0.35 else (C[2] if j < ln * 0.7 else C[3])), a)
				for r in range(1, lift + 1):
					buf.dot(x, fy - r, WHITE if j < 2 and r > lift - 2 else (C[1] if r == lift else C[2]), a * (1 - r / (lift + 2.0)) * 1.4)
			for r in int(ceil(crest + 3)):
				buf.dot(cx + sd * head, fy - r, WHITE, (1 - q) * 1.6 * (1 - r / (crest + 3)))
			light.glow(cx + sd * head, fy - 3, 12 * z, C[2], 0.8 * (1 - q))
		light.glow(cx, fy, reach, C[3], 0.25 * (1 - q))
	for i in roundi(24 * z):
		var t0 := Sf.hsh(i, 1) * 0.32
		var age := tt - t0
		var life := 0.3 + Sf.hsh(i, 4) * 0.3
		if age < 0 or age > life:
			continue
		var sd := 1 if i % 2 else -1
		var x := cx + sd * (4 + Rr * Sf.out_expo(t0 / 0.55)) + sd * (15 + Sf.hsh(i, 2) * 70) * age
		var y := fy - 1 - ((60 + Sf.hsh(i, 3) * 90) * age - 110 * age * age)
		var k := 1 - age / life
		if y > fy - 1:
			continue
		buf.dot(x, y, WHITE if age < life * 0.3 else C[1], 1.4 * k)
		if Sf.hsh(i, 5) < 0.4 and k > 0.4:
			for o in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				buf.dot(x + o.x, y + o.y, C[2], k * 1.2)
		light.glow(x, y, 4, C[2], 0.45 * k)

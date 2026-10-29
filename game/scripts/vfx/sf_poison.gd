class_name SfPoison
extends RefCounted
## V10, Sprite Fusion poison.ts, three of its scenes, all running until stop():
## puddle (acid pools): a bulging green pool with a rippling lit skin, bubbles that swell and pop
##   into droplets and wisps, and a glow.
## gas (toxic clouds): the original's thrown-flask cloud kept going: soft puffs churn through the
##   cloud's area, with drifting motes and a stained floor under it.
## aura (TOXIC units): a sickly band sweeping up the body, drips, bubbles and fumes coming off it.

const POISON := ["f6ffc2", "cfff63", "8eea3f", "55b92f", "318232", "23552e", "173320", "0e1d14"]
const WHITE := Color("ffffff")
const OUTLINE := Color("1a1422")
const DROP := 1
const BUBBLE := 2

var R := Sf.Rng.new()
var kind := "puddle"
var P: Array = []
var ground: Callable
var t := 0.0
var stop_at := 1e9
var puffs: Array = []   # [x, y, vx, vy, r0, r1, t0, end, seed, rise, hug]
var bits: Array = []    # [kind, x, y, vx, vy, life, max, g, s, rest]
var motes: Array = []   # [x, y, vx, vy, life, max, col, size, seed]
var n_puff := 0
# puddle
var X := 0.0
var cx := 0.0
var cy := 0.0
var W := 44.0
var bubbles: Array = []  # [x, t0, life, r]
var pops: Array = []     # [x, y, t]
# gas
var Y := 0.0
var RAD := 60.0
# aura
var sil_fn: Callable
var feet: Callable
var sil: Array = []
var box := Rect2i()
var stains: Array = []

static func puddle(x: float, y: float, width_world: float, ground_fn: Callable) -> SfPoison:
	var e := SfPoison.new()
	e.kind = "puddle"
	e.setup(ground_fn)
	e.X = x
	e.cx = x / Sf.PX
	e.cy = roundf(y / Sf.PX)
	e.W = width_world / Sf.PX
	for i in 10:
		e.bit(DROP, x + e.R.rnd(-10, 10), y - 4, e.R.rnd(-180, 180), -e.R.rnd(80, 260), 1.2, 0.9, e.R.ri(1, 2))
	return e

static func gas(x: float, y: float, r: float, ground_fn: Callable) -> SfPoison:
	var e := SfPoison.new()
	e.kind = "gas"
	e.setup(ground_fn)
	e.X = x
	e.Y = y
	e.RAD = r
	for i in roundi(r / 6.0):
		e.puff_in(0.0, true)
	return e

static func aura(feet_fn: Callable, sil_src: Callable, ground_fn: Callable) -> SfPoison:
	var e := SfPoison.new()
	e.kind = "aura"
	e.setup(ground_fn)
	e.feet = feet_fn
	e.sil_fn = sil_src
	return e

func setup(ground_fn: Callable) -> void:
	ground = ground_fn
	for h in POISON:
		P.append(Color(h))

func stop() -> void:
	stop_at = minf(stop_at, t)

func done() -> bool:
	var over := t > stop_at + (1.5 if kind == "puddle" else 0.9)
	return over and puffs.is_empty() and bits.is_empty() and motes.is_empty()

func bit(k: int, x: float, y: float, vx: float, vy: float, life: float, g: float, s: float) -> void:
	bits.append([k, x, y, vx, vy, life, life, g, s, false])

func mote(x: float, y: float, vx: float, vy: float, life: float, col: Color, size: float) -> void:
	motes.append([x, y, vx, vy, life, life, col, size, R.next() * 100])

func add_puff(x: float, y: float, vx: float, vy: float, r0: float, r1: float, end: float, rise := 0.0, hug := false) -> void:
	puffs.append([x, y, vx, vy, r0, r1, t, end, fmod(n_puff * 37.7, 100.0), rise, hug])
	n_puff += 1

func puff_in(age0: float, first := false) -> void:
	## A gas puff somewhere in the cloud's area, drifting a little.
	var a := R.rnd(0, TAU)
	var d := sqrt(R.next()) * RAD * 0.75
	add_puff(X + cos(a) * d, Y + sin(a) * d * 0.45, R.rnd(-20, 20), R.rnd(-14, 6), RAD / 14.0, RAD / 6.5, t + R.rnd(1.8, 3.0) - age0)
	if first:
		puffs[-1][6] = t - R.rnd(0, 1.2)

func update(dt: float) -> void:
	t += dt
	var live := t < stop_at
	match kind:
		"puddle":
			update_puddle(live)
		"gas":
			if live:
				var alive := puffs.filter(func(p): return t < p[7] - 0.6).size()
				if alive < roundi(RAD / 6.0) and R.chance(0.5):
					puff_in(0.0)
				if R.chance(0.12):
					mote(X + R.rnd(-RAD, RAD) * 0.8, Y + R.rnd(-RAD, RAD) * 0.3, R.rnd(-12, 12), -R.rnd(14, 36), R.rnd(1.2, 2.2), P[2] if R.chance(0.6) else P[1], R.rnd(1, 2.2))
				if R.chance(0.06):
					var bx := X + R.rnd(-RAD, RAD) * 0.8
					bit(BUBBLE, bx, Y + R.rnd(-RAD, RAD) * 0.3, R.rnd(-10, 10), -R.rnd(16, 40), R.rnd(0.5, 1), 0, 2.0 if R.chance(0.3) else 1.4)
		"aura":
			update_aura(live)
	for i in range(bits.size() - 1, -1, -1):
		var b: Array = bits[i]
		b[5] -= dt
		if b[5] <= 0:
			bits.remove_at(i)
			continue
		if b[9]:
			continue
		b[4] += 1900 * b[7] * dt
		b[1] += b[3] * dt
		b[2] += b[4] * dt
		var fl: float = ground.call(b[1])
		if b[7] > 0 and b[2] >= fl and b[4] > 0:
			b[2] = fl - 0.01
			b[9] = true
			b[3] = 0
			b[4] = 0
			if b[0] == DROP:
				b[5] = minf(b[5], 0.25)
				if b[8] > 1 and kind == "aura":
					stains.append([b[1] / Sf.PX, roundi(b[2] / Sf.PX), t, R.rnd(1.2, 2.6)])
					if stains.size() > 40:
						stains.pop_front()
	for i in range(motes.size() - 1, -1, -1):
		var m: Array = motes[i]
		m[4] -= dt
		if m[4] <= 0:
			motes.remove_at(i)
			continue
		m[2] -= m[2] * 0.8 * dt
		m[3] -= m[3] * 0.8 * dt
		m[0] += m[2] * dt
		m[1] += m[3] * dt
	puffs = puffs.filter(func(p): return t <= p[7])

func width() -> float:
	return W * Sf.out_cubic(t / 0.6) * (1 - Sf.smooth(stop_at, stop_at + 1.4, t))

func surface(x: float, w: float) -> int:
	var d := minf(1, absf(x + 0.5 - cx) / maxf(1, w))
	return roundi(cy - roundf(sqrt(1 - d * d) * minf(2.4, 0.9 + w * 0.04)))

func update_puddle(live: bool) -> void:
	var w := width()
	if live and t > 0.3 and R.chance(0.09 * W / 44.0 + 0.04):
		bubbles.append([cx + R.rnd(-0.8, 0.8) * w, t, R.rnd(0.45, 1), R.rnd(1.5, 3.4)])
	for i in range(bubbles.size() - 1, -1, -1):
		var b: Array = bubbles[i]
		if t - b[1] < b[2]:
			continue
		bubbles.remove_at(i)
		if absf(b[0] - cx) > w:
			continue
		pops.append([b[0], surface(b[0], w), t])
		for j in 2 + roundi(b[3]):
			bit(DROP, b[0] * Sf.PX, (cy - 2) * Sf.PX, R.rnd(-90, 90), -R.rnd(90, 200), 0.9, 0.8, 1)
		add_puff(b[0] * Sf.PX, (cy - 3) * Sf.PX, R.rnd(-15, 15), -R.rnd(30, 50), b[3] * 0.9, b[3] * 2.6, t + R.rnd(1.4, 2), 18)
		if R.chance(0.5):
			mote(b[0] * Sf.PX, (cy - 4) * Sf.PX, R.rnd(-10, 10), -R.rnd(20, 40), R.rnd(1.2, 2), P[2] if R.chance(0.6) else P[1], R.rnd(1, 2))
	pops = pops.filter(func(p): return t - p[2] <= 0.1)
	if live and t > 0.2 and R.chance(0.075 * W / 44.0):
		add_puff(X + R.rnd(-0.8, 0.8) * w * Sf.PX, cy * Sf.PX - 4, R.rnd(-12, 12), -R.rnd(20, 40), R.rnd(2, 3), R.rnd(6, 9), t + R.rnd(1.6, 2.4), 22)
	if live and R.chance(0.05):
		mote(X + R.rnd(-0.8, 0.8) * w * Sf.PX, cy * Sf.PX - R.rnd(10, 40), R.rnd(-8, 8), -R.rnd(14, 30), R.rnd(1.4, 2.2), P[2] if R.chance(0.6) else P[1], R.rnd(1, 2))

func update_aura(live: bool) -> void:
	sil = sil_fn.call()
	if sil.is_empty():
		return
	var xs: PackedInt32Array = sil[0]
	var ys: PackedInt32Array = sil[1]
	if xs.is_empty():
		return
	var x0 := 1 << 30
	var y0 := 1 << 30
	var x1 := -(1 << 30)
	var y1 := -(1 << 30)
	for i in xs.size():
		x0 = mini(x0, xs[i]); x1 = maxi(x1, xs[i]); y0 = mini(y0, ys[i]); y1 = maxi(y1, ys[i])
	box = Rect2i(x0, y0, x1 - x0, y1 - y0)
	if not live:
		return
	if R.chance(0.11):
		var p := on_body(0.35, 0.95)
		bit(DROP, p.x * Sf.PX, p.y * Sf.PX, R.rnd(-10, 10), R.rnd(0, 30), 1.4, 0.7, 2.0 if R.chance(0.5) else 1.0)
	if R.chance(0.09):
		var p := on_body(0.1, 0.8)
		bit(BUBBLE, p.x * Sf.PX, p.y * Sf.PX, R.rnd(-14, 14), -R.rnd(20, 46), R.rnd(0.4, 0.8), 0, 1.6 if R.chance(0.3) else 1.1)
	if R.chance(0.1):
		var p := on_body(0, 0.35)
		add_puff(p.x * Sf.PX, p.y * Sf.PX, R.rnd(-10, 10), -R.rnd(26, 44), R.rnd(1.5, 2.5), R.rnd(4.5, 7), t + R.rnd(1.2, 1.8), 26)
	if R.chance(0.06):
		mote((box.position.x + box.end.x) * 0.5 * Sf.PX + R.rnd(-20, 20), box.position.y * Sf.PX + R.rnd(0, 40), R.rnd(-10, 10), -R.rnd(16, 34), R.rnd(1.2, 2), P[2] if R.chance(0.6) else P[1], R.rnd(0.8, 1.8))

func on_body(u0: float, u1: float) -> Vector2:
	var xs: PackedInt32Array = sil[0]
	var ys: PackedInt32Array = sil[1]
	var lo := box.position.y + box.size.y * u0
	var hi := box.position.y + box.size.y * u1
	for k in 24:
		var i := R.ri(0, xs.size() - 1)
		if ys[i] >= lo and ys[i] <= hi:
			return Vector2(xs[i] + R.next(), ys[i] + R.next())
	return Vector2(box.get_center().x, lerpf(lo, hi, 0.5))

func puff_at(p: Array) -> Array:
	var age: float = t - p[6]
	var e := 1 - exp(-age * 2.2)
	var x: float = p[0] + (p[2] / 2.2) * e + Sf.noise(t * 0.7 + p[8], 1) * 6 * minf(1, age)
	var y: float = p[1] + (p[3] / 2.2) * e - p[9] * age + Sf.noise(t * 0.6 + p[8], 2) * 4 * minf(1, age)
	var r: float = p[4] + (p[5] - p[4]) * Sf.out_cubic(age / 1.4)
	if p[10]:
		y = minf(y, ground.call(x) - r * Sf.PX * 0.7)
	var a := Sf.smooth(0, 0.15, age) * (1 - Sf.smooth(p[7] - (0.9 if p[10] else (p[7] - p[6]) * 0.6), p[7], t))
	if kind == "gas" and t > stop_at:
		a *= 1 - Sf.smooth(stop_at, stop_at + 0.8, t)
	return [x / Sf.PX, y / Sf.PX, r, a, clampf(age / (2.6 if p[10] else p[7] - p[6]), 0, 1)]

func draw_gas(buf: Sf.Px, light: Sf.Px, opacity: float) -> void:
	for i in puffs.size():
		var g := puff_at(puffs[i])
		var a: float = g[3] * opacity
		if a < 0.02:
			continue
		var base: Color = P[4] if Sf.hsh(i + n_puff - puffs.size(), 70) < 0.5 else P[4].lerp(P[3], 0.4)
		var c := base.lerp(P[6], g[4] * 0.85)
		var r: float = g[2]
		buf.alpha_disc(g[0], g[1], r * 1.08, c, a * 0.4)
		buf.alpha_disc(g[0] + r * 0.05, g[1] + r * 0.08, r * 0.76, c, a * 0.55)
		buf.alpha_disc(g[0] - r * 0.22, g[1] - r * 0.3, r * 0.48, c.lerp(P[1], 0.22), a * 0.38 * (1 - g[4] * 0.6))
		if r > 9:
			light.glow(g[0], g[1], r * 1.5, P[3], 0.06 * a)

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		match kind:
			"puddle":
				back_puddle(buf, light)
			"gas":
				var k := Sf.smooth(0, 0.8, t) * (1 - Sf.smooth(stop_at, stop_at + 0.8, t))
				var gx := X / Sf.PX
				var gy: float = ground.call(X)
				if gy < 1e8 and gy - Y < RAD * 1.5:
					var w := RAD / Sf.PX * 0.8
					var fy := roundi(gy / Sf.PX)
					for x in range(floori(gx - w), ceili(gx + w) + 1):
						var d := absf(x - gx) / w
						var h := Sf.hsh(x, 41)
						if h * 0.6 + d < k * 1.1:
							buf.dot(x, fy, P[4] if d < 0.5 else P[5])
							if h < 0.5:
								buf.dot(x, fy + 1, P[6], k)
				light.glow(gx, Y / Sf.PX, RAD / Sf.PX * 1.4, P[3], 0.22 * k * (0.85 + 0.15 * sin(t * 4)))
			"aura":
				back_aura(buf, light)
		return
	match kind:
		"puddle":
			front_puddle(buf, light)
		"gas":
			draw_gas(buf, light, 1.0)
		"aura":
			front_aura(buf, light)
	for b in bits:
		var x: float = b[1] / Sf.PX
		var y: float = b[2] / Sf.PX
		var fa := minf(1, b[5] / 0.3)
		if b[0] == DROP:
			buf.dot(x, y, P[1], fa)
			if b[8] > 1:
				buf.dot(x, y - 1, P[3], fa)
		elif b[5] < 0.06:
			for o in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
				buf.dot(x + o.x, y + o.y, P[1])
		else:
			buf.ring(x, y, b[8], 1, P[2])
			buf.dot(x - 0.6, y - 0.8, WHITE)
	for m in motes:
		var k: float = m[4] / m[5]
		var br := 0.7 + 0.3 * sin(t * (2 + fmod(m[8], 3)) + m[8])
		var a := minf(1, (1 - k) * 5) * minf(1, k * 3) * br
		if a < 0.05:
			continue
		buf.alpha_disc(m[0] / Sf.PX, m[1] / Sf.PX, m[7], m[6], 0.45 * a)
		buf.alpha_disc(m[0] / Sf.PX, m[1] / Sf.PX, m[7] * 0.5, WHITE, 0.5 * a)
		light.glow(m[0] / Sf.PX, m[1] / Sf.PX, 3 + m[7] * 3, m[6], 0.35 * a)

func back_puddle(buf: Sf.Px, light: Sf.Px) -> void:
	var w := width()
	if w < 1:
		return
	var dry := Sf.smooth(stop_at, stop_at + 1.4, t)
	for x in range(floori(cx - w * 1.3), floori(cx + w * 1.3) + 1):
		var d := absf(x - cx) / w
		if d > 1 and Sf.hsh(x, 41) < 1.3 - d:
			buf.dot(x, cy, P[5], 1 - dry * 0.6)
	var icy := int(cy)
	for x in range(floori(cx - w), ceili(cx + w) + 1):
		var d := absf(x + 0.5 - cx) / w
		if d > 1:
			continue
		var top := surface(x, w)
		var nn := Sf.noise(x * 0.18 - t * 1.6, 3) + Sf.noise(x * 0.07 + t * 0.9, 4) * 0.6
		var skin: Color = P[4] if d > 0.9 else (WHITE if nn > 0.95 and Sf.hsh(x, floori(t * 6)) < 0.3 else (P[1] if nn > 0.55 else P[2]))
		buf.put(x, top, skin)
		if icy - 1 > top:
			var under: Color = P[3] if d < 0.85 and Sf.noise(x * 0.12 + t * 0.7, 5) > 0.3 else (P[5] if d > 0.9 else P[4])
			buf.put(x, top + 1, under)
			if icy - 1 > top + 1:
				for y in range(top + 2, icy):
					buf.put(x, y, P[5] if d > 0.9 else P[4])
		if icy > top:
			buf.put(x, icy, P[5])
		if d > 0.97:
			buf.put(x, top - 1, OUTLINE)
	light.glow(cx, cy - 6, w * 2.4 + 10, P[3], 0.34 * (1 - dry) * (0.85 + 0.15 * sin(t * 3.4)) * Sf.smooth(0, 0.4, t))
	light.glow(cx, cy - 2, w * 1.1, P[2], 0.18 * (1 - dry))

func front_puddle(buf: Sf.Px, light: Sf.Px) -> void:
	var w := width()
	for b in bubbles:
		var k: float = (t - b[1]) / b[2]
		var r: float = b[3] * (0.3 + 0.7 * Sf.out_cubic(k * 1.3))
		var sy := surface(b[0], w)
		for y in range(floori(sy - r), sy + 1):
			for x in range(floori(b[0] - r - 1), ceili(b[0] + r + 1) + 1):
				var dx: float = x + 0.5 - b[0]
				var dy := y + 0.5 - sy
				var d := sqrt(dx * dx + dy * dy)
				if d > r + 0.5:
					continue
				if d > r - 0.7:
					buf.put(x, y, P[1] if dx < 0 and dy < -r * 0.3 else P[3])
				else:
					buf.blend(x, y, P[2], 0.3)
		buf.dot(b[0] - r * 0.4, sy - r * 0.6, WHITE)
		light.glow(b[0], sy - r * 0.5, r * 2 + 3, P[2], 0.2)
	for p in pops:
		var k: float = (t - p[2]) / 0.1
		for o in [Vector2(1, 0), Vector2(-1, 0), Vector2(0.6, -0.7), Vector2(-0.6, -0.7), Vector2(0, -1)]:
			buf.dot(p[0] + o.x * (2 + 3 * k), p[1] + o.y * (2 + 3 * k), P[1], 1 - k)
	draw_gas(buf, light, 0.5)

func level() -> float:
	return Sf.smooth(0, 0.4, t) * (1 - Sf.smooth(stop_at, stop_at + 0.7, t))

func back_aura(buf: Sf.Px, light: Sf.Px) -> void:
	if box.size == Vector2i():
		return
	var k := level()
	var fx: float = box.get_center().x
	var gy: float = ground.call(fx * Sf.PX)
	if gy > 1e8:
		return
	var fy := roundi(gy / Sf.PX)
	var w := 6 + 8 * Sf.smooth(0, 3, t)
	for x in range(floori(fx - w), floori(fx + w) + 1):
		if Sf.hsh(x, 43) < 1.15 - absf(x - fx) / w:
			buf.dot(x, fy, P[4] if Sf.hsh(x, 44) < 0.5 else P[5], 0.85 * maxf(k, 0.3))
	for s in stains:
		var a := 1 - Sf.smooth(s[2] + 1.5, s[2] + 3, t)
		for x in range(floori(s[0] - s[3]), floori(s[0] + s[3]) + 1):
			buf.dot(x, s[1], P[4] if absf(x - s[0]) < s[3] * 0.5 else P[5], a)
	light.glow(fx, fy - 2, 18, P[3], 0.2 * k)

func front_aura(buf: Sf.Px, light: Sf.Px) -> void:
	var k := level()
	if k <= 0.01 or sil.is_empty():
		return
	var xs: PackedInt32Array = sil[0]
	var ys: PackedInt32Array = sil[1]
	var v := fmod(t * 0.9, 1.15) / 0.95
	var H := maxf(1, box.size.y)
	var y1 := box.end.y
	for i in xs.size():
		var u := (y1 - ys[i]) / H
		var band := exp(-pow((u - v) / 0.13, 2))
		var a := k * (0.12 + 0.42 * band)
		if a > 0.2 or Sf.bayer(xs[i], ys[i]) < a * 3:
			buf.blend(xs[i], ys[i], P[1] if band > 0.5 else P[2], a)
	draw_gas(buf, light, 0.55)
	light.glow(box.get_center().x, box.get_center().y, box.size.y * 0.9 + 8, P[3], 0.28 * k * (0.8 + 0.2 * sin(t * 7)))

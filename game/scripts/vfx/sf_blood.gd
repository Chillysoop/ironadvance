class_name SfBlood
extends RefCounted
## V6, Sprite Fusion blood.ts: a burst of strands out of the wound, droplets and a fine mist
## thrown away from the shot, drips running off the wound, and splats that stain the ground and
## darken as they dry before fading. Vharr bleed green ichor. Off with the BLOOD option.

const RED := ["ff8a7a", "f2384a", "c71e33", "931327", "5e0c1b", "350711"]
const ICHOR := ["e8ffb0", "b4f25c", "7cc93a", "4f8f2a", "2e5a1d", "173312"]

var R := Sf.Rng.new()
var C: Array = []
var ground: Callable
var feet: Callable  # -> Vector2 world, so drips follow the unit
var X := 0.0
var Y := 0.0
var A := 0.0
var S := 1.0
var LIFE := 6.0
var off := Vector2()
var t := 0.0
var drops: Array = []   # [x, y, vx, vy, s, delay, life, crown, seed]
var stains: Array = []  # [x, y, w, lean, dir, t0, sats, tone]
var mist: Array = []    # [x, y, vx, vy, r, life, max, t0]
var strands: Array = [] # [a, l, w]
var drips: Array = []   # [t0, fell]

func _init(x: float, y: float, angle: float, ground_fn: Callable, feet_fn: Callable, amount := 1.0, size := 1.0, ramp: Array = RED, stain_life := 6.0) -> void:
	X = x
	Y = y
	A = angle
	S = size
	LIFE = stain_life
	ground = ground_fn
	feet = feet_fn
	off = Vector2(x, y) - (feet_fn.call() as Vector2)
	for h in ramp:
		C.append(Color(h))
	var ux := cos(A)
	var uy := sin(A)
	for i in 7:
		var u := (i - 3) / 3.0
		strands.append([A + u * 0.62 + R.rnd(-0.08, 0.08), (11 + 7 * (1 - absf(u)) + R.rnd(-2, 3)) * S, (1.3 + 0.6 * (1 - absf(u))) * S])
	for t0 in ([R.rnd(0.22, 0.32), R.rnd(0.6, 0.8), R.rnd(1.1, 1.4)] if amount >= 1 else [R.rnd(0.22, 0.32), R.rnd(0.6, 0.8)]):
		drips.append([t0, false])
	for i in roundi(46 * amount):
		var s := 3 if R.chance(0.12) else (2 if R.chance(0.35) else 1)
		var spread := R.rnd(-1, 1) * R.rnd(0.1, 0.65) * (1.2 if s == 1 else 0.8)
		var delay := R.rnd(0, 0.07)
		var sp := (R.rnd(260, 950) if s == 1 else (R.rnd(200, 650) if s == 2 else R.rnd(150, 460))) * (1 - delay * 4) * sqrt(S)
		var a := A + spread
		drops.append([X + ux * R.rnd(0, 8), Y + uy * R.rnd(0, 8), cos(a) * sp, sin(a) * sp - R.rnd(0, 150), s, delay, 3.0, false, R.next()])
	for i in roundi(14 * amount):
		var a := A + R.rnd(-0.12, 0.12)
		var sp := R.rnd(620, 1050) * sqrt(S)
		drops.append([X, Y, cos(a) * sp, sin(a) * sp - R.rnd(0, 60), 2 if R.chance(0.25) else 1, (i / 14.0) * 0.05, 3.0, false, R.next()])
	for i in roundi(6 * sqrt(amount)):
		var a := A + R.rnd(-0.5, 0.5)
		var sp := R.rnd(30, 110)
		var life := R.rnd(0.35, 0.6)
		mist.append([X + ux * R.rnd(2, 14), Y + uy * R.rnd(2, 14), cos(a) * sp, sin(a) * sp - 12, R.rnd(2.5, 5) * S, life, life, R.rnd(0, 0.05)])

func wound() -> Vector2:
	return (feet.call() as Vector2) + off

func done() -> bool:
	return t > 1 and drops.is_empty() and stains.all(func(s): return t - s[5] > LIFE + 1.2)

func splat(d: Array, g: float) -> void:
	var sp := Vector2(d[2], d[3]).length()
	var dir := signf(d[2]) if d[2] != 0 else 1.0
	var w: float = (0.5 + minf(0.6, sp / 1200) if d[4] == 1 else d[4] * 0.6 + minf(0.9, sp / 800)) * (0.5 if d[7] else 1.0)
	var sats: Array = []
	for k in (2 if d[4] >= 2 and sp > 350 else (1 if sp > 450 else 0)):
		sats.append([R.rnd(1, 3) + k * R.rnd(1.5, 3), 2 if R.chance(0.2) else 1])
	stains.append([d[0] / Sf.PX, roundi(g / Sf.PX), w, minf(1, absf(d[2]) / 400), dir, t, sats, 1 if R.chance(0.3) else 0])
	if stains.size() > 60:
		stains.pop_front()
	if not d[7] and d[4] >= 2 and sp > 260:
		for k in R.ri(1, 3):
			drops.append([d[0], g - 1, dir * R.rnd(10, 130) + R.rnd(-70, 70), -R.rnd(80, 170), 1, 0.0, 0.8, true, R.next()])

func update(dt: float) -> void:
	t += dt
	for i in range(drops.size() - 1, -1, -1):
		var d: Array = drops[i]
		if d[5] > 0:
			d[5] -= dt
			continue
		d[6] -= dt
		if d[6] <= 0:
			drops.remove_at(i)
			continue
		var drag: float = 0.7 / d[4]
		d[3] += Sf.GRAVITY * dt
		d[2] -= d[2] * drag * dt
		d[3] -= d[3] * drag * 0.5 * dt
		var py: float = d[1]
		d[0] += d[2] * dt
		d[1] += d[3] * dt
		var g: float = ground.call(d[0])
		if d[3] > 0 and py <= g and d[1] >= g:
			splat(d, g)
			drops.remove_at(i)
	var w := wound()
	for d in drips:
		if not d[1] and t >= d[0] + 0.2:
			d[1] = true
			drops.append([w.x + R.rnd(-1, 1), w.y + 6, R.rnd(-10, 10), 30.0, 2 if R.chance(0.5) else 1, 0.0, 3.0, false, R.next()])
	for i in range(mist.size() - 1, -1, -1):
		var m: Array = mist[i]
		if m[7] > 0:
			m[7] -= dt
			continue
		m[5] -= dt
		if m[5] <= 0:
			mist.remove_at(i)
			continue
		m[2] -= m[2] * 3 * dt
		m[3] -= m[3] * 3 * dt + 6 * dt
		m[0] += m[2] * dt
		m[1] += m[3] * dt

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		draw_stains(buf)
		return
	for m in mist:
		if m[7] > 0:
			continue
		var k: float = m[5] / m[6]
		buf.alpha_disc(m[0] / Sf.PX, m[1] / Sf.PX, m[4] * (1.6 - 0.6 * k), C[3], 0.4 * k * minf(1, (1 - k) * 8))
	if t < 0.09:
		var grow := Sf.out_cubic(t / 0.045)
		var brk := clampf((t - 0.04) / 0.05, 0, 1)
		var wx := X / Sf.PX
		var wy := Y / Sf.PX
		for s in strands:
			var L: float = s[1] * grow
			var d0 := L * brk
			var ca := cos(s[0])
			var sa := sin(s[0])
			for ps in 3:
				var d := d0
				while d <= L:
					var u := d / maxf(1, L)
					var r: float = s[2] * pow(1 - u, 0.6) * (1 - brk * 0.5) + (0.5 if u > 0.85 else 0.0)
					if r >= 0.35:
						var x := wx + ca * d
						var y := wy + sa * d
						if ps == 0:
							buf.disc(x, y, r + 0.7, C[4])
						elif ps == 1:
							buf.disc(x, y, r, C[1] if d < L * 0.35 else C[2])
						elif d < L * 0.5 and r > 0.9:
							buf.put(roundi(x - sa * r * 0.4), roundi(y + ca * r * 0.4 - 0.4), C[0])
					d += 0.5 if ps < 2 else 1.0
		if t < 0.035:
			buf.disc(wx, wy, 2.6 * S, C[1])
			buf.disc(wx, wy, 1.5 * S, C[0])
		light.glow(wx, wy, 16 * S, C[1], 0.25 * (1 - t / 0.09))
	var w := wound() / Sf.PX
	for d in drips:
		var u: float = t - d[0]
		if u < 0 or u > 1.6:
			continue
		var run := minf(3, 3 * Sf.smooth(0, 0.18, u))
		var fade := 1 - clampf((u - 1) / 0.6, 0, 1)
		for k in floori(run) + 1:
			buf.dot(w.x, w.y + k, C[3], fade)
		if not d[1]:
			buf.dot(w.x, w.y + run + 1, C[2])
			if Sf.smooth(0, 0.2, u) > 0.6:
				buf.dot(w.x + 1, w.y + run + 1, C[3])
				buf.dot(w.x, w.y + run + 2, C[2])
				buf.dot(w.x, w.y + run + 1, C[0])
	for d in drops:
		if d[5] <= 0:
			draw_drop(buf, d)

func draw_stains(buf: Sf.Px) -> void:
	for s in stains:
		var age: float = t - s[5]
		var fade := 1 - clampf((age - LIFE) / 1.2, 0, 1)
		if fade <= 0:
			continue
		var spread := Sf.smooth(0, 0.12, age)
		var hw: float = s[2] * (0.55 + 0.45 * spread)
		var dry := mini(4, (1 if age < 0.35 else (2 if age < 1.4 else (3 if age < 3.2 else 4))) + s[7])
		var body: Color = C[dry]
		var under: Color = C[mini(5, dry + 1)]
		var sx: float = s[0]
		var sy: int = s[1]
		var lean: float = s[3]
		var dir: float = s[4]
		var x0 := sx - hw * (1 - 0.3 * lean)
		var x1 := sx + hw * (1 + 0.8 * lean)
		var lo := x0 if dir > 0 else 2 * sx - x1
		var hi := x1 if dir > 0 else 2 * sx - x0
		for x in range(floori(lo), ceili(hi) + 1):
			var q := absf(x + 0.5 - sx) / maxf(0.5, (hi - lo) / 2)
			if fade < 1 and fade <= Sf.bayer(x, sy):
				continue
			buf.put(x, sy, under if q > 0.85 and s[2] > 1 else body)
			if s[2] > 1.6 and q < 0.6:
				buf.put(x, sy + 1, under)
			if s[2] > 2.2 and q < 0.45:
				buf.put(x, sy - 1, C[1] if q < 0.2 and age < 1 else body)
		if age < 0.4 and s[2] > 1:
			buf.dot(sx - dir * hw * 0.3, sy, C[0])
		for st in s[6]:
			var px: float = sx + dir * (hw * (1 + 0.6 * lean) + st[0] * spread)
			if fade < 1 and fade <= Sf.bayer(floori(px), sy):
				continue
			buf.dot(px, sy, body)
			if st[1] > 1:
				buf.dot(px + dir, sy, under)

func draw_drop(buf: Sf.Px, d: Array) -> void:
	var x: float = d[0] / Sf.PX
	var y: float = d[1] / Sf.PX
	var sp := maxf(1, Vector2(d[2], d[3]).length())
	var ux: float = d[2] / sp
	var uy: float = d[3] / sp
	var tail := minf(6, sp * 0.008)
	if tail >= 1:
		buf.line(x - ux * tail, y - uy * tail, x - ux, y - uy, C[2] if d[4] >= 2 else C[3])
	if d[4] == 3:
		buf.disc(x, y, 1.7, C[4])
		buf.disc(x, y, 1.15, C[1])
		buf.put(roundi(x - 0.7), roundi(y - 0.7), C[0])
	elif d[4] == 2:
		var px := floori(x)
		var py := floori(y)
		buf.put(px, py, C[0])
		buf.put(px + 1, py, C[1])
		buf.put(px, py + 1, C[2])
		buf.put(px + 1, py + 1, C[3])
	else:
		buf.put(floori(x), floori(y), C[1] if d[8] < 0.5 else C[2])

class_name SfHeal
extends RefCounted
## V14, Sprite Fusion heal.ts: green crosses float up around the soldier, a light ring spreads on
## the floor with sparks rising off it, bright bands sweep up the body three times and streaks
## stream upward behind it, then it all fades by about 2.7 seconds.

const GREEN := ["ffffff", "e6ffdc", "acff92", "62e26a", "30b55b", "20804c", "175237", "0f3125"]
const WHITE := Color("ffffff")
const OUTLINE := Color("1a1422")

var R := Sf.Rng.new()
var L: Array = []
var feet: Callable   # -> Vector2 world
var sil_fn: Callable
var t := 0.0
var glyphs: Array = []  # [x, y, vy, life, max, s, seed, delay]
var ps: Array = []      # [x, y, vx, vy, life, max, col, size, seed]

func _init(feet_fn: Callable, sil_src: Callable, count := 18, palette: Array = GREEN) -> void:
	feet = feet_fn
	sil_fn = sil_src
	for h in palette:
		L.append(Color(h))
	var f: Vector2 = feet.call()
	for i in count:
		var life := R.rnd(1, 1.4)
		glyphs.append([f.x + R.rnd(-46, 46), f.y - R.rnd(4, 70), -R.rnd(50, 90), life, life, 1 if R.chance(0.45) else 0, R.next() * 1000, 0.06 + i * 0.085 + R.rnd(0, 0.05)])

func fade() -> float:
	return 1 - Sf.smooth(1.9, 2.7, t)

func done() -> bool:
	return t > 2.8 and ps.is_empty()

func update(dt: float) -> void:
	t += dt
	var f: Vector2 = feet.call()
	for i in range(glyphs.size() - 1, -1, -1):
		var b: Array = glyphs[i]
		if b[7] > 0:
			b[7] -= dt
			continue
		b[3] -= dt
		if b[3] <= 0:
			glyphs.remove_at(i)
			continue
		b[1] += b[2] * dt
		b[0] += sin((b[4] - b[3]) * 4.5 + b[6]) * 16 * dt
	if t < 2 and R.chance(0.45):
		var life := R.rnd(0.5, 0.95)
		ps.append([f.x + R.rnd(-34, 34), f.y - R.rnd(0, 76), R.rnd(-8, 8), -R.rnd(30, 80), life, life, L[1] if R.chance(0.5) else L[2], R.rnd(1.6, 2.6) if R.chance(0.3) else R.rnd(0.4, 0.9), R.next() * 100])
	for i in range(ps.size() - 1, -1, -1):
		var p: Array = ps[i]
		p[4] -= dt
		if p[4] <= 0:
			ps.remove_at(i)
			continue
		p[2] -= p[2] * 1.6 * dt
		p[3] -= p[3] * 1.6 * dt + 10 * dt
		p[0] += p[2] * dt
		p[1] += p[3] * dt

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	var f: Vector2 = feet.call()
	var cx := f.x / Sf.PX
	var fy := f.y / Sf.PX
	if layer == 0:
		var k := fade() * Sf.smooth(0, 0.2, t)
		if k <= 0:
			return
		for h in range(0, 78, 6):
			light.glow(cx, fy - h, 22, L[3], 0.13 * k * (1 - h / 90.0))
		for i in 22:
			var ph := fmod(t * (1.1 + Sf.hsh(i, 3) * 0.8) + Sf.hsh(i, 1), 1.0)
			var sx := cx + (Sf.hsh(i, 2) - 0.5) * 34 * (1 - ph * 0.3)
			var sy := fy - 2 - ph * 74
			var a := sin(ph * PI) * k
			for d in 5:
				buf.dot(sx, sy + d, L[1] if d == 0 else (L[2] if d < 3 else L[4]), a * (1 - d / 6.0))
		return
	floor_ring(buf, light, cx, fy)
	sweep(buf, light)
	for b in glyphs:
		if b[7] > 0:
			continue
		var age: float = b[4] - b[3]
		var k: float = b[3] / b[4]
		var glint := sin(age * 14 + b[6]) > 0.75
		var big: int = 4 if b[5] else 2
		var lc := big - 1 if age < 0.05 else (big + 1 if age < 0.1 else big)
		cross(buf, b[0] / Sf.PX, b[1] / Sf.PX, lc, b[5], k / 0.4 if k < 0.4 else 1.0, glint)
		light.glow(b[0] / Sf.PX, b[1] / Sf.PX, 9 + b[5] * 3, L[2], 0.4 * minf(1, k * 2))
	for p in ps:
		var k: float = p[4] / p[5]
		var ax: float = p[0] / Sf.PX
		var ay: float = p[1] / Sf.PX
		var px := floori(ax)
		var py := floori(ay)
		var tw := 0.6 + 0.4 * sin(t * (8 + fmod(p[8], 5)) + p[8])
		if p[7] < 1:
			if tw * k > 0.25:
				buf.put(px, py, WHITE if tw > 0.8 else p[6])
			light.glow(ax, ay, 3, p[6], 0.4 * k * tw)
			continue
		var arm := maxi(1, roundi(p[7] * tw * minf(1, k * 3)))
		var tip := Sf.scale(p[6], 0.75)
		for d in range(1, arm + 1):
			var cc: Color = tip if d == arm and arm > 1 else p[6]
			buf.put(px + d, py, cc)
			buf.put(px - d, py, cc)
			buf.put(px, py + d, cc)
			buf.put(px, py - d, cc)
		buf.put(px, py, WHITE)
		light.glow(ax, ay, 3 + arm * 2, p[6], 0.5 * k * tw)

func floor_ring(buf: Sf.Px, light: Sf.Px, cx: float, fy: float) -> void:
	var k := fade()
	var w := 19.5 * (1 - pow(1 - clampf(t / 0.45, 0, 1), 3))
	for dx in range(-ceili(w), floori(w) + 1):
		var u := absf(dx) / maxf(1, w)
		var a := k * sqrt(1 - minf(1, u)) * 1.04
		buf.dot(cx + dx, fy, L[1] if u < 0.3 else (L[2] if u < 0.65 else L[3]), a)
		if u < 0.75:
			buf.dot(cx + dx, fy - 1, L[2] if u < 0.35 else L[3], a * 0.35)
		if dx % 5 == 0:
			light.glow(cx + dx, fy, 10, L[3], 0.22 * k * (1 - u))
	for i in 8:
		var ph := fmod(t * (0.9 + Sf.hsh(i, 1) * 0.6) + Sf.hsh(i, 2), 1.0)
		var x := cx + (Sf.hsh(i, 3) - 0.5) * 2 * w
		var a := sin(ph * PI) * k
		buf.dot(x, fy - 1 - ph * 22, WHITE if ph < 0.25 else L[1], a)
		buf.dot(x, fy - ph * 22, L[2], a * 0.6)

func sweep(buf: Sf.Px, light: Sf.Px) -> void:
	var k := Sf.smooth(0, 0.25, t) * fade()
	if k <= 0 or t > 1.9:
		return
	var sil: Array = sil_fn.call()
	if sil.is_empty():
		return
	var xs: PackedInt32Array = sil[0]
	var ys: PackedInt32Array = sil[1]
	if xs.is_empty():
		return
	var top := 1 << 30
	var bot := -(1 << 30)
	var sx := 0
	var on := {}
	for i in xs.size():
		top = mini(top, ys[i])
		bot = maxi(bot, ys[i])
		sx += xs[i]
		on[Vector2i(xs[i], ys[i])] = true
	var mx := float(sx) / xs.size()
	for p in [0.1, 0.65, 1.2]:
		var q: float = (t - p) / 0.4
		if q < 0 or q > 1.3:
			continue
		var yb := bot + 2 - q * (bot - top + 6)
		for i in xs.size():
			var d := ys[i] - yb
			if d < -1 or d >= 10:
				continue
			buf.dot(xs[i], ys[i], WHITE if d < 1 else (L[1] if d < 4 else L[2]), k * (1.5 if d < 1 else (1 - d / 10.0) * 1.4))
			if d < 1.5:
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
					var n: Vector2i = Vector2i(xs[i], ys[i]) + o
					if not on.has(n):
						buf.dot(n.x, n.y, L[1], k)
		light.glow(mx, yb, 14, L[2], 0.5 * k * (1 - q / 1.3))

func cross(buf: Sf.Px, x: float, y: float, ln: int, w: int, a: float, glint: bool) -> void:
	var px := roundi(x)
	var py := roundi(y)
	var ins := func(dx: int, dy: int) -> bool: return (absi(dx) <= w and absi(dy) <= ln) or (absi(dy) <= w and absi(dx) <= ln)
	for dy in range(-ln - 1, ln + 2):
		for dx in range(-ln - 1, ln + 2):
			var c: Color
			if ins.call(dx, dy):
				if w == 0:
					c = L[1] if dy < 0 or dx < 0 else L[3]
				elif not ins.call(dx, dy - 1) or not ins.call(dx - 1, dy):
					c = L[1]
				elif not ins.call(dx, dy + 1) or not ins.call(dx + 1, dy):
					c = L[4]
				else:
					c = L[2]
				if glint and ((dx == 0 and dy == 0) or (w > 0 and dx == -w and dy == -ln)):
					c = WHITE
			elif ins.call(dx - 1, dy) or ins.call(dx + 1, dy) or ins.call(dx, dy - 1) or ins.call(dx, dy + 1):
				c = OUTLINE
			else:
				continue
			buf.dot(px + dx, py + dy, c, a)

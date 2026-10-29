class_name SfBubbles
extends RefCounted
## V22, Sprite Fusion bubbles.ts cut down to one vent: where something sinks, wobbling lit
## bubbles stream and burst up to the surface, merging as they meet, and pop in little arcs on
## top. The original's water tint, caustics and specks are left to the game's own sea.

const COLORS := ["ffffff", "c6f3ff", "68bfe6", "2f7fb6"]

var R := Sf.Rng.new()
var HI: Color
var LIT: Color
var RIM: Color
var SHADE: Color
var FILL: Color
var X := 0.0
var TOP := 0.0
var BOT := 0.0
var t := 0.0
var stop_at := 1.2
var acc := 0.0
var burst := 0.0
var list: Array = []  # [x0, x, y, r, vy, ph, wob]
var pops: Array = []  # [x, y, r, t]

func _init(x: float, surface: float, bottom: float, life := 1.2) -> void:
	HI = Color(COLORS[0])
	LIT = Color(COLORS[1])
	RIM = Color(COLORS[2])
	SHADE = Color(COLORS[3])
	FILL = RIM.lerp(SHADE, 0.5)
	X = x
	TOP = surface
	BOT = bottom
	stop_at = life
	for i in R.ri(6, 9):
		spawn(BOT - 3 - i * 5, R.rnd(0.7, 1.1))

func stop() -> void:
	stop_at = minf(stop_at, t)

func done() -> bool:
	return t > stop_at and list.is_empty() and pops.is_empty()

func spawn(y: float, big: float) -> void:
	var r := R.rnd(1.5, 3.2) * big if big > 0 else (R.rnd(0.5, 1.4) if R.chance(0.7) else R.rnd(1.4, 2.6))
	list.append([X + R.rnd(-6, 6), X, y, r, -(40 + 26 * r), R.rnd(0, TAU), 0.0])

func update(dt: float) -> void:
	t += dt
	if t < stop_at:
		acc += dt * 9 * (0.7 + 0.3 * Sf.noise(t * 0.8, 3))
		while acc > 1:
			acc -= 1
			spawn(BOT - 3, 0)
		burst -= dt
		if burst < 0:
			burst = R.rnd(0.4, 0.7)
			for i in R.ri(3, 6):
				spawn(BOT - 3 - i * 5, R.rnd(0.6, 1))
	for i in range(list.size() - 1, -1, -1):
		var b: Array = list[i]
		b[4] += (-(40 + 26 * b[3]) - b[4]) * minf(1, dt * 3)
		b[2] += b[4] * dt
		b[5] += dt * (4 + 2 / b[3])
		b[1] = b[0] + sin(b[5]) * (1 + b[3] * 1.6)
		b[0] += Sf.noise(t * 0.4 + i * 0.13, 5) * 6 * dt
		b[3] = minf(5, b[3] + dt * 0.12)
		b[6] *= 1 - minf(1, dt * 4)
		if b[2] < TOP + 2:
			pops.append([b[1], TOP, b[3], 0.0])
			list.remove_at(i)
	var i := 0
	while i < list.size():
		var a: Array = list[i]
		if a[3] >= 1:
			var j := i + 1
			while j < list.size():
				var b: Array = list[j]
				if b[3] >= 1 and Vector2(a[1] - b[1], a[2] - b[2]).length() / Sf.PX <= (a[3] + b[3]) * 0.75:
					a[3] = pow(pow(a[3], 3) + pow(b[3], 3), 1.0 / 3.0)
					a[0] = (a[0] + b[0]) / 2
					a[6] = 1.0
					list.remove_at(j)
				else:
					j += 1
		i += 1
	for p in pops:
		p[3] += dt
	pops = pops.filter(func(p): return p[3] <= 0.2)

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		return
	for b in list:
		bubble(buf, light, b)
	for p in pops:
		var k: float = p[3] / 0.2
		var x: float = p[0] / Sf.PX
		var y: float = p[1] / Sf.PX
		var r: float = p[2] + 1 + k * 3
		var a := 0.0
		while a < TAU:
			if sin(a) < 0.2:
				buf.dot(x + cos(a) * r, y + sin(a) * r * 0.5, HI if k < 0.5 else LIT, 1 - k)
			a += 0.5 / r
		if p[2] > 1.5:
			buf.dot(x - 2, y - 2 - k * 4, LIT, 1 - k)
			buf.dot(x + 2, y - 3 - k * 5, LIT, 1 - k)

func bubble(buf: Sf.Px, light: Sf.Px, b: Array) -> void:
	var cx: float = b[1] / Sf.PX
	var cy: float = b[2] / Sf.PX
	var r: float = b[3]
	if r < 0.9:
		buf.put(floori(cx), floori(cy), RIM if r < 0.7 else LIT)
		return
	if r < 1.5:
		var px := floori(cx)
		var py := floori(cy)
		buf.put(px, py, HI)
		buf.put(px + 1, py, LIT)
		buf.put(px, py + 1, RIM)
		buf.put(px + 1, py + 1, SHADE)
		light.glow(cx + 0.5, cy + 0.5, 3, LIT, 0.12)
		return
	var sq: float = 0.1 * sin(b[5] * 2) * minf(1, (r - 1.5) / 2) + b[6] * 0.25
	var rx := r * (1 + sq)
	var ry := r * (1 - sq)
	for y in range(floori(cy - ry - 1), ceili(cy + ry + 1) + 1):
		for x in range(floori(cx - rx - 1), ceili(cx + rx + 1) + 1):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			var d := sqrt(dx * dx + dy * dy) * r
			if d > r + 0.5:
				continue
			var lit := (-dx - dy) / sqrt(2.0) / maxf(0.01, d / r)
			if d > r - 0.6:
				buf.put(x, y, LIT if lit > 0.45 else (SHADE if lit < -0.55 else RIM))
			elif Sf.bayer(x, y) < 0.12:
				buf.put(x, y, FILL)
	var hx := roundi(cx - rx * 0.45)
	var hy := roundi(cy - ry * 0.45)
	buf.put(hx, hy, HI)
	if r >= 2.5:
		buf.put(hx + 1, hy, LIT)
		buf.put(hx, hy + 1, LIT)
	if r >= 2:
		buf.put(roundi(cx + rx * 0.5), roundi(cy + ry * 0.5), LIT)
	light.glow(cx, cy, r * 2.4 + 2, RIM, 0.14)

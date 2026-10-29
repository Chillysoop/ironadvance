class_name SfPillar
extends RefCounted
## V17, Sprite Fusion holy-light.ts recoloured as a red targeting beacon for Steel Rain: a thin
## guide line drops from the sky, the column slams down with a flash, shock rings and a spray of
## sparks, holds with pulsing strands, halos climbing it and motes rising, then narrows out.
## (The feathers stayed with the holy version.)

const RED := ["ffffff", "ffe2dc", "ffa69a", "ff6a5a", "e23a3a", "a8202a", "5a1018"]
const WHITE := Color("ffffff")
const STAR := 0
const BOKEH := 1
const SLAM := 0.42

var R := Sf.Rng.new()
var H: Array = []
var SPARKS: Array = []
var cx := 0.0
var cy := 0.0
var X := 0.0
var Y := 0.0
var W := 13.0
var NARROW := 1.4
var OUT := 1.9
var t := 0.0
var slammed := false
var last_halo := 0.0
var halos: Array = []
var strands: Array = []
var ps: Array = []  # [k, x, y, vx, vy, life, max, col, size, seed]

func _init(x: float, y: float, hold := 1.0, width := 13.0, start := 0.0, colors: Array = RED) -> void:
	for h in colors:
		H.append(Color(h))
	SPARKS = [WHITE, H[1], H[2], H[3]]
	X = x
	Y = y
	cx = x / Sf.PX
	cy = roundf(y / Sf.PX)
	W = width
	NARROW = SLAM + hold
	OUT = NARROW + 0.5
	t = start
	for i in 11:
		strands.append([(Sf.hsh(i, 1) - 0.5) * 1.7, 0.04 + Sf.hsh(i, 2) * 0.07, 1 + Sf.hsh(i, 3) * 2])

func done() -> bool:
	return t > OUT + 0.5 and ps.is_empty()

func spawn(k: int, x: float, y: float, vx: float, vy: float, life: float, col: Color, size: float) -> void:
	ps.append([k, x, y, vx, vy, life, life, col, size, R.next() * 100])

func width() -> float:
	if t < SLAM:
		return 0.0
	if t < NARROW:
		return W * (1 + 0.35 * exp(-(t - SLAM) * 9))
	return lerpf(W, 0.6, Sf.out_cubic((t - NARROW) / 0.4))

func update(dt: float) -> void:
	t += dt
	if t >= SLAM and not slammed:
		slammed = true
		for i in 50:
			var s := R.sgn()
			spawn(STAR, X + s * R.rnd(0, 20), Y - 4, s * R.rnd(120, 520), -R.rnd(40, 260), R.rnd(0.4, 1), R.pick(SPARKS), R.rnd(0.8, 2.2))
	var w := width()
	if t > SLAM and t < OUT:
		for i in 2:
			if R.chance(0.7 * clampf(w / W, 0, 1)):
				spawn(STAR if R.chance(0.7) else BOKEH, X + R.rnd(-w, w) * Sf.PX * 1.4, Y - R.rnd(0, 200), R.rnd(-10, 10), -R.rnd(60, 170), R.rnd(0.6, 1.3), R.pick(SPARKS), R.rnd(0.7, 2))
		if t - last_halo > 0.42 and t < NARROW:
			last_halo = t
			halos.append(t)
	elif t < SLAM and R.chance(0.4):
		var a := R.rnd(0, TAU)
		var d := R.rnd(40, 90)
		spawn(STAR, X + cos(a) * d, Y - 6 + sin(a) * d * 0.3, -cos(a) * d * 2.5, -sin(a) * d * 0.6, 0.38, H[2], R.rnd(0.6, 1.2))
	for i in range(ps.size() - 1, -1, -1):
		var p: Array = ps[i]
		p[5] -= dt
		if p[5] <= 0:
			ps.remove_at(i)
			continue
		var drag := 1.6 if p[0] == STAR else 0.8
		p[3] -= p[3] * drag * dt
		p[4] -= p[4] * drag * dt + (10 * dt if p[0] == STAR else 0.0)
		p[1] += p[3] * dt
		p[2] += p[4] * dt

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		var gl := Sf.smooth(0, SLAM, t) * 0.5 if t < SLAM else 1 - Sf.smooth(NARROW, OUT, t)
		if gl > 0.01:
			var rx := 10 + (14 * t if t < SLAM else 34 + 4 * sin(t * 5))
			var ry := 5.0 if t < SLAM else 8.0
			for y in range(floori(cy - ry), floori(cy + ry) + 1):
				for x in range(floori(cx - rx), floori(cx + rx) + 1):
					var dx := (x + 0.5 - cx) / rx
					var dy := (y + 0.5 - cy) / ry
					var d := sqrt(dx * dx + dy * dy)
					if d > 1:
						continue
					var u := d / maxf(0.05, gl)
					if d < 0.7 * gl or Sf.bayer(x, y) < gl * (1 - d) * 2.2:
						buf.put(x, y, H[1] if u < 0.35 else (H[2] if u < 0.65 else (H[3] if u < 0.9 else H[4])))
			light.glow(cx, cy, rx * 2.2, H[3], 0.5 * gl)
		column(buf, light)
		return
	for i in 2:
		var k := (t - SLAM - 0.1 * i) / 0.55
		var sc := 0.7 if i else 1.0
		if k < 0 or k > 1:
			continue
		var e := Sf.out_cubic(k)
		ring_e(buf, cx, cy, 14 + 90 * e * sc, 3 + 13 * e * sc, 3 * (1 - k) + 0.5, WHITE if k < 0.25 else H[2], 1.15 - k)
	if t > SLAM and t < SLAM + 0.12:
		light.glow(cx, cy - 20, 140, H[2], 1.0 * (1 - (t - SLAM) / 0.12))
	for p in ps:
		var k: float = p[5] / p[6]
		var ax: float = p[1] / Sf.PX
		var ay: float = p[2] / Sf.PX
		if p[0] == BOKEH:
			var br := 0.7 + 0.3 * sin(t * (2 + fmod(p[9], 3)) + p[9])
			var a := minf(1, (1 - k) * 5) * minf(1, k * 3) * br
			if a < 0.05:
				continue
			buf.alpha_disc(ax, ay, p[8], p[7], 0.45 * a)
			buf.alpha_disc(ax, ay, p[8] * 0.5, WHITE, 0.5 * a)
			light.glow(ax, ay, 3 + p[8] * 3, p[7], 0.35 * a)
			continue
		var px := floori(ax)
		var py := floori(ay)
		var tw := 0.6 + 0.4 * sin(t * (8 + fmod(p[9], 5)) + p[9])
		if p[8] < 1:
			if tw * k > 0.25:
				buf.put(px, py, WHITE if tw > 0.8 else p[7])
			light.glow(ax, ay, 3, p[7], 0.4 * k * tw)
			continue
		var arm := maxi(1, roundi(p[8] * tw * minf(1, k * 3)))
		var tip := Sf.scale(p[7], 0.75)
		for d in range(1, arm + 1):
			var cc: Color = tip if d == arm and arm > 1 else p[7]
			buf.put(px + d, py, cc)
			buf.put(px - d, py, cc)
			buf.put(px, py + d, cc)
			buf.put(px, py - d, cc)
		if arm >= 3:
			for o in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				buf.put(px + o.x, py + o.y, tip)
		buf.put(px, py, WHITE)
		light.glow(ax, ay, 3 + arm * 2, p[7], 0.5 * k * tw)

func column(buf: Sf.Px, light: Sf.Px) -> void:
	var w := width()
	var top := buf.y0 - 2
	if t < SLAM:
		var a := Sf.smooth(0, SLAM * 0.8, t) * 0.7
		for y in range(top, int(cy)):
			buf.dot(cx, y, H[1], a * (0.4 + 0.6 * ((y - top) / (cy - top))))
		light.glow(cx, top + 10, 40, H[3], a * 0.4)
		return
	if w <= 0.05 or t > OUT + 0.2:
		return
	var fade := 1 - Sf.smooth(OUT - 0.25, OUT + 0.2, t)
	var y_end := cy
	if t - SLAM < 0.07:
		var u := clampf((t - SLAM) / 0.07, 0, 1) * 0.5 + 0.5
		y_end = lerpf(top, cy, u * u * u)
	var xa := floori(cx - w * 1.3)
	var xb := ceili(cx + w * 1.3)
	# The level of each column of the beam only changes with time, so work it out once a frame.
	var lv := PackedInt32Array()
	var al := PackedFloat32Array()
	var qs := PackedFloat32Array()
	for x in range(xa, xb + 1):
		var q := absf((x + 0.5 - cx) / w)
		var l := 0 if q < 0.2 else (1 if q < 0.42 else (2 if q < 0.66 else (3 if q < 0.88 else 4)))
		for s in strands:
			if absf((x + 0.5 - cx) / w - s[0] - 0.05 * sin(t * s[2] + s[0] * 9)) < s[1]:
				l = maxi(0, l - 1)
		lv.append(l)
		qs.append(q)
		al.append((1.0 if q < 0.88 else (1.3 - q) / 0.42) * fade)
	for y in range(top, int(y_end) + 1):
		var pulse := 1 if fposmod((y - top) * 0.02 - t * 1.9, 1.0) < 0.07 else 0
		var run_c := Color(0, 0, 0, 0)
		var run_x := 0
		for i in lv.size():
			var x := xa + i
			var c := Color(0, 0, 0, 0)
			if al[i] > Sf.bayer(x, y) * (0.2 if qs[i] < 0.66 else 1.0):
				# one step redder than the holy column, so the core reads as a red beam, not white
				var l := mini(5, maxi(0, lv[i] + 1 - pulse))
				c = WHITE if l == 0 else H[l]
			if c != run_c:
				if run_c.a > 0:
					buf.span(run_x, x - 1, y, run_c)
				run_c = c
				run_x = x
		if run_c.a > 0:
			buf.span(run_x, xb, y, run_c)
		if (y & 7) == 0:
			light.glow(cx, y, w * 2.4 + 6, H[2], 0.32 * fade)
	light.glow(cx, top + 8, 70, H[3], 0.4 * fade)
	for h0 in halos:
		var k: float = (t - h0) / 0.9
		if k < 0 or k > 1:
			continue
		ring_e(buf, cx, cy - 4 - k * (cy - top) * 0.9, w * 1.35 * (1 + k * 0.3), 2.2, 1, WHITE if k < 0.3 else H[1], (1 - k) * fade)

func ring_e(buf: Sf.Px, x: float, y: float, rx: float, ry: float, thick: float, c: Color, a: float) -> void:
	var n := ceili(maxf(rx, ry) * TAU * 1.3)
	for j in n:
		var ang := (float(j) / n) * TAU
		var ca := cos(ang)
		var sa := sin(ang)
		var o := -thick / 2
		while o <= thick / 2:
			buf.dot(x + ca * (rx + o), y + sa * (ry + o * (ry / maxf(1, rx))), c, a)
			o += 0.5

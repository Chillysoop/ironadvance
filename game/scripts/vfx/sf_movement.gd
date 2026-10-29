class_name SfMovement
extends RefCounted
## V9, Sprite Fusion movement.ts, two kits.
## Dash (Combat Roll, Sprint): a dust kick where it starts, afterimages of the soldier dropped
## along the way, speed lines, then a skid with sparks and a scuff mark where it stops. Here it
## follows the unit while the game moves it, until stop().
## Blink (Blink, Phase Shift, the Blinker): the outline crackles, the body flashes and comes
## apart into bits, a streak runs to the far side, and the body is put back together there from
## motes rushing in.

const SPARK := 0
const PLASMA := 1
const STAR := 2
const SMOKE := 3
const DUSTK := 4
const WHITE := Color("ffffff")
const DASH := ["ffffff", "ccf6ff", "a3dcff", "5eb0ff", "5b6cff", "773ae4", "4c25ab"]
const ICE := ["ffffff", "dcfbff", "a6ecff", "62c8f4", "3a8bd8", "2c58aa", "212f6b", "151a3d"]
const ARCANE := ["ffffff", "f4ddff", "d6a0ff", "a862ff", "773ae4", "4c25ab", "2b1569", "170b3b"]
const DUSTC := Color8(96, 84, 112)
const SKID := Color("221a33")
const S_HOT := Color("fff3a6")
const S_YELLOW := Color("ffe26b")
const S_ORANGE := Color("ff8a2a")
const S_TAIL := Color("f2561d")
const P_CYAN := Color("7ff3ff")
const P_DEEP := Color("1ab8e6")
const SMOKE_RAMP := [Color("7b6f72"), Color("5d5660"), Color("433d48"), Color("2b2630"), Color("1a171e")]

class Part:
	var k := 0
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var life := 0.0
	var mx := 0.0
	var col := Color()
	var size := 1.0
	var seed := 0.0

var R := Sf.Rng.new()
var kind := "dash"
var ground: Callable
var feet: Callable      # -> Vector2 world
var sil_fn: Callable    # -> silhouette [xs, ys, feet, shade]
var C: Array = []
var A: Array = []
var t := 0.0
var pt := 0.0
var pace := 1.0
var list: Array[Part] = []
var lights: Array = []  # [x, y, r, color, k, life, max]

# dash
var F := 1.0
var DX0 := 0.0
var G := 0.0
var stop_at := 1e9
var ghosts: Array = []  # [xs, ys, shade, t]
var lines: Array = []   # [x, y, len, t]
var last_x := NAN
var stopped := false
var skid_v := 0.0
var stop_x := 0.0
var end_x := 0.0
var skid_y := 0.0

# blink
var AX := 0.0
var FY := 0.0
var BX := 0.0
var BY := 0.0
var OUT := 0.3
var IN := 0.55
var ARRIVE := 0.9
var COLS: Array = []
var sil := {}           # x0, y0, w, h, px (PackedByteArray of shades)
var edge: Array = []    # Vector2i cells just outside the outline
var bits: Array = []    # [x, y, vx, vy, life, max, c, delay]
var inbound: Array = [] # [tx, ty, ox, oy, t0, c]
var gone := false
var unhid := false
var arrived := false
var cx := 0.0
var my := 0.0
var shift := Vector2i()

static func dash(feet_fn: Callable, sil_src: Callable, facing: float, ground_fn: Callable) -> SfMovement:
	var e := SfMovement.new()
	e.kind = "dash"
	e.feet = feet_fn
	e.sil_fn = sil_src
	e.ground = ground_fn
	e.F = signf(facing) if facing != 0 else 1.0
	for h in DASH:
		e.C.append(Color(h))
	var f: Vector2 = feet_fn.call()
	e.DX0 = f.x
	e.G = f.y
	e.kick(f.x, f.y, 14, 1.6)
	for i in 8:
		e.spawn(SMOKE, f.x + e.R.rnd(-6, 6), f.y - e.R.rnd(2, 12), -e.F * e.R.rnd(80, 260), -e.R.rnd(10, 50), e.R.rnd(0.6, 1.1), DUSTC, e.R.rnd(3, 6))
	return e

static func blink(from: Vector2, to: Vector2, silh: Array, ground_fn: Callable, speed := 1.4) -> SfMovement:
	## speed > 1 plays it faster than the original (a turn-based hop shouldn't take a second).
	var e := SfMovement.new()
	e.kind = "blink"
	e.ground = ground_fn
	e.pace = speed
	e.AX = from.x
	e.FY = from.y
	e.BX = to.x
	e.BY = to.y
	for h in ICE:
		e.C.append(Color(h))
	for h in ARCANE:
		e.A.append(Color(h))
	e.COLS = [WHITE, e.C[1], e.C[2], e.A[1], e.A[2], e.C[3]]
	e.grab(silh)
	return e

func timing(sec: float) -> int:
	## Battle ticks from the start until a blink moment (OUT, IN, ARRIVE) at this pace.
	return ceili(sec / pace * 60.0)

func grab(s: Array) -> void:
	var box_x0 := roundi(AX / Sf.PX) - 20
	var box_y0 := roundi(FY / Sf.PX) - 48
	cx = box_x0 + 20
	shift = Vector2i(roundi((BX - AX) / Sf.PX), roundi((BY - FY) / Sf.PX))
	if s.is_empty() or (s[0] as PackedInt32Array).is_empty():
		my = box_y0 + 50 * 0.55
		return
	var xs: PackedInt32Array = s[0]
	var ys: PackedInt32Array = s[1]
	var sh: PackedByteArray = s[3] if s.size() > 3 else PackedByteArray()
	var x0 := 1 << 30
	var y0 := 1 << 30
	var x1 := -(1 << 30)
	var y1 := -(1 << 30)
	for i in xs.size():
		x0 = mini(x0, xs[i]); y0 = mini(y0, ys[i]); x1 = maxi(x1, xs[i]); y1 = maxi(y1, ys[i])
	var w := x1 - x0 + 1
	var h := y1 - y0 + 1
	var px := PackedByteArray()
	px.resize(w * h)
	px.fill(0)
	for i in xs.size():
		px[(ys[i] - y0) * w + xs[i] - x0] = sh[i] if i < sh.size() else 2
	sil = {"x0": x0, "y0": y0, "w": w, "h": h, "px": px}
	cx = x0 + w / 2.0
	my = y0 + h * 0.55
	for y in range(-1, h + 1):
		for x in range(-1, w + 1):
			if sil_at(x, y):
				continue
			if sil_at(x - 1, y) or sil_at(x + 1, y) or sil_at(x, y - 1) or sil_at(x, y + 1):
				edge.append(Vector2i(x, y))

func sil_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= sil.w or y >= sil.h:
		return 0
	return sil.px[y * sil.w + x]

func stop() -> void:
	stop_at = minf(stop_at, t)

func done() -> bool:
	if kind == "dash":
		return t > stop_at + 1.2 and list.is_empty()
	return t > ARRIVE + 0.5 and bits.is_empty() and list.is_empty()

func kick(x: float, y: float, n: int, spread: float) -> void:
	for i in n:
		spawn(DUSTK, x + R.rnd(-3, 3), y - 1, R.sgn() * R.rnd(20, 110) * spread, -R.rnd(5, 45), R.rnd(0.3, 0.65), DUSTC, R.rnd(1.3, 2.8))

func spawn(k: int, x: float, y: float, vx: float, vy: float, life: float, col := Color(), size := 1.0) -> void:
	var p := Part.new()
	p.k = k; p.x = x; p.y = y; p.vx = vx; p.vy = vy; p.life = life; p.mx = life
	p.col = col; p.size = size; p.seed = R.next() * 100
	list.append(p)

func update(dt: float) -> void:
	dt *= pace
	t += dt
	if kind == "dash":
		update_dash(dt)
	else:
		update_blink(dt)
	step(dt)

func update_dash(dt: float) -> void:
	var f: Vector2 = feet.call()
	if t < stop_at and t < 2.0:
		if is_nan(last_x) or (absf(f.x - last_x) > 44 and t > 0.06):
			last_x = f.x
			var s: Array = sil_fn.call()
			if not s.is_empty():
				ghosts.append([s[0], s[1], s[3] if s.size() > 3 else PackedByteArray(), t])
		for k in 4:
			lines.append([f.x / Sf.PX - F * R.rnd(4, 16), f.y / Sf.PX - R.rnd(2, 44), R.rnd(16, 64), t])
	elif not stopped:
		stopped = true
		stop_at = minf(stop_at, t)
		skid_v = 700 if absf(f.x - DX0) > 10 else 0.0  # (a dash that went nowhere, Sprint, doesn't skid)
		end_x = f.x
		skid_y = f.y
	if stopped and skid_v > 60:
		skid_v = maxf(0, skid_v - 4600 * dt)
		stop_x = f.x
		var gy := f.y
		spawn(DUSTK, f.x + F * 8, gy - 2, F * R.rnd(60, 260), -R.rnd(20, 90), R.rnd(0.4, 0.8), DUSTC, R.rnd(1.5, 3))
		if R.chance(0.6):
			spawn(SPARK, f.x + F * 6, gy - 1, F * R.rnd(200, 600), -R.rnd(40, 200), R.rnd(0.1, 0.25))
		if R.chance(0.4):
			spawn(SMOKE, f.x, gy - 4, F * R.rnd(40, 140), -R.rnd(10, 40), R.rnd(0.6, 1), DUSTC, R.rnd(3, 5))
	lines = lines.filter(func(l): return t - l[3] <= 0.2)
	ghosts = ghosts.filter(func(g): return t - g[3] <= 0.4)

func update_blink(dt: float) -> void:
	if t < OUT and R.chance(0.6):
		var a := R.rnd(0, TAU)
		var d := R.rnd(40, 80)
		spawn(PLASMA, AX + cos(a) * d, FY - 36 + sin(a) * d, -cos(a) * d * 5, -sin(a) * d * 5, R.rnd(0.14, 0.2))
	if t >= OUT and not gone:
		gone = true
		lights.append([AX, FY - 36, 150.0, C[3], 0.9, 0.3, 0.3])
		if not sil.is_empty():
			for y in sil.h:
				for x in sil.w:
					if not sil.px[y * sil.w + x] or R.chance(0.15):
						continue
					var px: float = sil.x0 + x
					var py: float = sil.y0 + y
					bits.append([px, py, (px - cx) * R.rnd(3, 9) + R.rnd(-14, 14), -R.rnd(10, 60), R.rnd(0.35, 0.8), 0.8, R.pick(COLS), float(y) / sil.h * 0.1])
	if t >= IN and not unhid:
		unhid = true
		if not sil.is_empty():
			for y in sil.h:
				for x in sil.w:
					if not sil.px[y * sil.w + x] or R.chance(0.2):
						continue
					var a := R.rnd(0, TAU)
					var d := R.rnd(14, 34)
					inbound.append([sil.x0 + x + shift.x, sil.y0 + y + shift.y, cos(a) * d, sin(a) * d - 10, IN + R.rnd(0, 0.12), R.pick(COLS)])
	if t >= ARRIVE and not arrived:
		arrived = true
		for i in 30:
			var a := R.rnd(0, TAU)
			var sp := R.rnd(60, 260)
			spawn(STAR, BX, BY - 36, cos(a) * sp, sin(a) * sp * 0.7 - 40, R.rnd(0.4, 0.9), R.pick(COLS), R.rnd(0.6, 1.6))
	for i in range(bits.size() - 1, -1, -1):
		var b: Array = bits[i]
		if b[7] > 0:
			b[7] -= dt
			continue
		b[4] -= dt
		if b[4] <= 0:
			bits.remove_at(i)
			continue
		b[3] -= 60 * dt
		b[2] -= b[2] * 2.5 * dt
		b[0] += b[2] * dt
		b[1] += b[3] * dt

func step(dt: float) -> void:
	pt += dt
	for i in range(list.size() - 1, -1, -1):
		var p := list[i]
		p.life -= dt
		if p.life <= 0:
			list.remove_at(i)
			continue
		match p.k:
			SPARK, PLASMA:
				p.vy += Sf.GRAVITY * 0.45 * dt
				p.vx -= p.vx * 2.2 * dt
				p.vy -= p.vy * 2.2 * dt
				var g: float = ground.call(p.x)
				var ny := p.y + p.vy * dt
				p.x += p.vx * dt
				if p.vy > 0 and p.y <= g and ny >= g:
					p.vy = -p.vy * 0.45
					p.vx *= 0.7
					p.y = g - 0.5
				else:
					p.y = ny
			STAR:
				p.vx -= p.vx * 1.6 * dt
				p.vy -= p.vy * 1.6 * dt + 10 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
			SMOKE:
				p.vy -= 32 * dt
				p.vx += sin(pt * 1.3 + p.seed) * 16 * dt
				p.vx -= p.vx * 1.6 * dt
				p.vy -= p.vy * 1.2 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
			DUSTK:
				p.vx -= p.vx * 4 * dt
				p.vy -= p.vy * 4 * dt + 10 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
	for i in range(lights.size() - 1, -1, -1):
		lights[i][5] -= dt
		if lights[i][5] <= 0:
			lights.remove_at(i)

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		parts(buf, light, true)
	if kind == "dash":
		draw_dash(buf, light, layer)
	elif layer == 1:
		draw_blink(buf, light)
	if layer == 1:
		parts(buf, light, false)
		for l in lights:
			var k: float = l[5] / l[6]
			light.glow(l[0] / Sf.PX, l[1] / Sf.PX, (l[2] / Sf.PX) * (0.55 + 0.45 * k), l[3], l[4] * k * k)

func draw_dash(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		if stopped:
			var a := 0.8 * (1 - Sf.smooth(0.6, 1.4, t - stop_at))
			var x0 := (end_x - F * 70) / Sf.PX
			var x1 := stop_x / Sf.PX
			var gy := floori(skid_y / Sf.PX)
			for x in range(floori(minf(x0, x1)), floori(maxf(x0, x1)) + 1):
				buf.dot(x, gy, SKID, a * minf(1, absf(x - x0) / 12))
		for gh in ghosts:
			var k: float = (t - gh[3]) / 0.4
			var i := mini(C.size() - 3, 1 + floori(k * (C.size() - 3)))
			var a := 1.0 if k < 0.45 else (1 - k) / 0.55
			var xs: PackedInt32Array = gh[0]
			var ys: PackedInt32Array = gh[1]
			var sh: PackedByteArray = gh[2]
			for j in xs.size():
				var v: int = sh[j] if j < sh.size() else 2
				buf.dot(xs[j], ys[j], C[i + 2] if v == 1 else C[i + 2 - v], a)
		for l in lines:
			# (the original dithers each line dot by dot; here a few blended runs, same fade)
			var k: float = (t - l[3]) / 0.2
			var ln: float = l[2] * (1 - k * 0.6)
			var y := floori(l[1])
			var x := floori(l[0])
			var cuts := [0.0, 3.0, l[2] * 0.4, ln * 0.7, ln]
			for c in 4:
				var d0: float = cuts[c]
				var d1: float = minf(cuts[c + 1], ln)
				if d1 <= d0:
					continue
				var col: Color = C[0] if c == 0 else (C[1] if c == 1 else C[3])
				var a: float = (1 - (d0 + d1) * 0.5 / l[2]) * (1 - k)
				var xa := x - roundi(F * d0)
				var xb := x - roundi(F * d1)
				buf.span(mini(xa, xb), maxi(xa, xb), y, Color(col, clampf(a, 0, 1)))
		return
	var f: Vector2 = feet.call()
	if t < 0.08:
		var k := t / 0.08
		buf.ellipse_ring(DX0 / Sf.PX, G / Sf.PX, 6 + 18 * k, (2 + 3 * k) / (6 + 18 * k), 1.5, C[2], 1 - k, true)
		buf.ellipse_ring(DX0 / Sf.PX, G / Sf.PX, 6 + 18 * k, (2 + 3 * k) / (6 + 18 * k), 1.5, C[2], 1 - k, false)
	if t < stop_at + 0.1:
		light.glow(f.x / Sf.PX, f.y / Sf.PX - 20, 40, C[3], 0.35)

func draw_blink(buf: Sf.Px, light: Sf.Px) -> void:
	for spot in [[AX, FY, OUT], [BX, BY, ARRIVE - 0.02]]:
		var k: float = (t - spot[2]) / 0.45
		if k < 0 or k > 1:
			continue
		var e := Sf.out_cubic(k)
		var rx := 4 + 30 * e
		buf.ellipse_ring(spot[0] / Sf.PX, spot[1] / Sf.PX, rx, (1 + 6 * e) / rx, 2 * (1 - k) + 0.5, WHITE if k < 0.3 else C[2], 1.1 - k, true)
		buf.ellipse_ring(spot[0] / Sf.PX, spot[1] / Sf.PX, rx, (1 + 6 * e) / rx, 2 * (1 - k) + 0.5, WHITE if k < 0.3 else C[2], 1.1 - k, false)
	if t > OUT + 0.04 and t < OUT + 0.3:
		var k := (t - OUT - 0.04) / 0.26
		var hd := Vector2(AX, FY - 40).lerp(Vector2(BX, BY - 40), Sf.out_expo(k)) / Sf.PX
		var tl := Vector2(AX, FY - 40).lerp(Vector2(BX, BY - 40), Sf.out_expo(k - 0.25)) / Sf.PX
		var n := maxi(1, ceili(hd.distance_to(tl) * 2))
		for i in n + 1:
			var u := float(i) / n
			var p := tl.lerp(hd, u)
			buf.dot(p.x, p.y, WHITE if u > 0.8 else C[2], u + 0.1)
			buf.dot(p.x, p.y + 1, A[2], u * 0.6)
		light.glow(hd.x, hd.y, 14, C[2], 0.6)
	if not sil.is_empty():
		if t > 0 and t < OUT:
			var k := t / OUT
			var ft := floori(t * 30) * 977
			for c in edge:
				if Sf.hsh(c.x * 61 + c.y + ft) < 0.35 + 0.6 * k:
					buf.put(sil.x0 + c.x, sil.y0 + c.y, WHITE if k > 0.7 and Sf.hsh(c.x + c.y * 7) < 0.5 else C[2])
			light.glow(cx, sil.y0 + sil.h * 0.6, 30, C[3], 0.5 * k)
		if t >= OUT and t < OUT + 0.18:
			var k := (t - OUT) / 0.1
			if k < 1:
				squash(buf, cx, 1 - k, WHITE if k < 0.5 else C[1], C[2], 1)
			else:
				var hh: float = (sil.h / 2.0) * (1 - (t - OUT - 0.1) / 0.08)
				for y in range(floori(-hh - 4), ceili(hh + 4) + 1):
					buf.dot(cx, my + y, WHITE if absf(y) < hh else C[2])
			light.glow(cx, my, 40, C[2], 0.8)
		if t > OUT + 0.18 and t < OUT + 0.9:
			squash(buf, cx, 1, A[2], A[4], 0.45 * (1 - (t - OUT - 0.18) / 0.72))
		if t > IN and t < ARRIVE + 0.02:
			var k := (t - IN) / (ARRIVE - IN)
			if k < 0.55:
				var hh: float = (sil.h / 2.0 + 3) * Sf.out_cubic(k / 0.55)
				for y in range(floori(-hh), ceili(hh) + 1):
					buf.dot(cx + shift.x, my + shift.y + y, WHITE, 1 - (absf(y) / (hh + 1)) * 0.6)
			else:
				squash(buf, cx, Sf.out_cubic((k - 0.55) / 0.45), WHITE if k > 0.85 else C[1], C[2] if k > 0.85 else C[3], 1, shift)
			light.glow(cx + shift.x, my + shift.y, 34, C[2], 0.7 * k)
	elif t > IN and t < ARRIVE + 0.02:
		var k := (t - IN) / (ARRIVE - IN)
		var hh := 28 * Sf.out_cubic(k / 0.55) * (1 - Sf.smooth(0.8, 1, k))
		for y in range(floori(-hh), ceili(hh) + 1):
			buf.dot(cx + shift.x, my + shift.y + y, WHITE, 1 - (absf(y) / (hh + 1)) * 0.6)
		light.glow(cx + shift.x, my + shift.y, 34, C[2], 0.7 * k)
	for p in inbound:
		var k: float = (t - p[4]) / (ARRIVE - p[4])
		if k < 0 or k >= 1:
			continue
		var e := Sf.out_cubic(k)
		buf.dot(p[0] + p[2] * (1 - e), p[1] + p[3] * (1 - e), WHITE if k > 0.8 else p[5], 0.4 + 0.6 * k)
	for b in bits:
		if b[7] <= 0:
			buf.dot(b[0], b[1], WHITE if b[4] / b[5] > 0.75 else b[6], minf(1, (b[4] / b[5]) * 1.6))

func squash(buf: Sf.Px, ccx: float, sx: float, c: Color, edge_c: Color, a: float, d := Vector2i()) -> void:
	## The silhouette squeezed sideways about its middle (drawSil).
	if sx <= 0.02:
		return
	var half: float = sil.w / 2.0 + 2
	for y in sil.h:
		for x in range(floori(ccx - half * sx), ceili(ccx + half * sx) + 1):
			var i := roundi(ccx + (x + 0.5 - ccx) / sx - 0.5) - int(sil.x0)
			var v := 0 if i < 0 or i >= sil.w else int(sil.px[y * sil.w + i])
			if v:
				buf.dot(x + d.x, sil.y0 + y + d.y, edge_c if v == 1 else c, a)

func parts(buf: Sf.Px, light: Sf.Px, back: bool) -> void:
	for p in list:
		var behind := p.k == SMOKE or p.k == DUSTK
		if behind != back:
			continue
		var k := p.life / p.mx
		var ax := p.x / Sf.PX
		var ay := p.y / Sf.PX
		var px := floori(ax)
		var py := floori(ay)
		match p.k:
			SMOKE:
				var age := 1 - k
				var r := p.size * (0.65 + minf(1, age * 2.5) * 0.45 + age * 0.4)
				var a := minf(1, age * 12) * minf(1, k * 2.4) * 0.58
				var c := p.col.lerp(Sf.ramp(SMOKE_RAMP, age), age)
				buf.alpha_disc(ax, ay, r, c, a * 0.45)
				buf.alpha_disc(ax + r * 0.05, ay + r * 0.06, r * 0.74, c, a * 0.62)
				if age < 0.5:
					buf.alpha_disc(ax - r * 0.22, ay - r * 0.3, r * 0.5, c.lerp(WHITE, 0.12), a * 0.4 * (1 - age * 2))
			DUSTK:
				buf.alpha_disc(ax, ay, p.size * (0.6 + (1 - k) * 0.9), p.col, pow(k, 1.3) * 0.7)
			SPARK, PLASMA:
				var hot: Color
				if p.k == PLASMA:
					hot = WHITE if k > 0.5 else (P_CYAN if k > 0.25 else P_DEEP)
				else:
					hot = S_HOT if k > 0.6 else (S_YELLOW if k > 0.3 else S_ORANGE)
				var sp := maxf(0.001, Vector2(p.vx, p.vy).length())
				var ux := p.vx / sp
				var uy := p.vy / sp
				var ln := minf(9, 1 + sp * 0.011)
				buf.line(ax - ux * ln, ay - uy * ln, ax - ux * ln * 0.4, ay - uy * ln * 0.4, hot if k > 0.5 else (P_DEEP if p.k == PLASMA else S_TAIL))
				buf.line(ax - ux * ln * 0.45, ay - uy * ln * 0.45, ax, ay, hot)
				light.glow(ax, ay, 3, hot, 0.45 * k)
			STAR:
				var tw := 0.6 + 0.4 * sin(pt * (8 + fmod(p.seed, 5)) + p.seed)
				if p.size < 1:
					if tw * k > 0.25:
						buf.put(px, py, WHITE if tw > 0.8 else p.col)
					light.glow(ax, ay, 3, p.col, 0.4 * k * tw)
					continue
				var arm := maxi(1, roundi(p.size * tw * minf(1, k * 3)))
				var tip := Sf.scale(p.col, 0.75)
				for d in range(1, arm + 1):
					var cc := tip if d == arm and arm > 1 else p.col
					buf.put(px + d, py, cc)
					buf.put(px - d, py, cc)
					buf.put(px, py + d, cc)
					buf.put(px, py - d, cc)
				if arm >= 3:
					for o in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
						buf.put(px + o.x, py + o.y, tip)
				buf.put(px, py, WHITE)
				light.glow(ax, ay, 3 + arm * 2, p.col, 0.5 * k * tw)

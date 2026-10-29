class_name SfBlackHole
extends RefCounted
## V11, Sprite Fusion black-hole.ts, recoloured from its orange disk to Vharr violet: a bang of
## rings, then a black core with a tilted accretion disk that swirls motes and dust in, tears
## slabs off the ground and eats them, and finally implodes and bursts. The lens warp of the
## original needs the screen behind it and is left out.

const PLASMA := 0
const MOTE := 1
const DUSTK := 2
const INK := 3
const FORM := 0.4
const COLLAPSE := 0.42
const SWIRL := 0.55
const RAMP := [Color("1a0b2e"), Color("3b1569"), Color("5b23a3"), Color("7b3ae4"), Color("a862ff"), Color("c890ff"), Color("e2c4ff"), Color("f6ecff"), Color("ffffff")]
const BLUE_WHITE := Color("f2e4ff")
const SHADOW := Color8(2, 1, 5)
const HOLE_LIGHT := Color8(196, 123, 255)
const JET_CORE := Color("f4fbff")
const JET := Color("9fd8ff")
const JET_EDGE := Color("7a5cff")
const VIOLET := Color("b37bff")
const VOID := Color8(26, 12, 44)
const SHREDS := [Color("e4ddf4"), Color("b5abd4"), Color("8b80b4"), Color("5d5488")]
const WHITE := Color("ffffff")
const OUTLINE := Color("1a1422")
const P_CYAN := Color("7ff3ff")
const P_DEEP := Color("1ab8e6")

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

var R := Sf.Rng.new()
var ground: Callable
var X := 0.0
var Y := 0.0
var RAD := 34.0
var LIFE := 3.8
var END := 0.0
var REACH := 0.0
var G := 0.0
var pace := 1.0
var stone := Color("4a3f69")
var list: Array[Part] = []
var rings: Array = []   # [x, y, r0, r1, life, max, thick, color]
var lights: Array = []  # [x, y, r, color, k, life, max]
var slabs: Array = []   # [x, y, vx, vy, a, va, w, h, pull, pull_a, c]
var bursts: Array = []  # [t, dur, s]
var DISK: Array = []
var t := 0.0
var tilt := 0.0
var flare := 0.0
var gulp := 0.0
var grow := 0.0
var jet := 0.0
var jet_cd := 0.0
var colors: Array = []
var collapsed := false
var ended := 0.0
var slab_acc := 0.0

func _init(x: float, y: float, radius: float, ground_fn: Callable, life := 3.8, speed := 1.0, surface = null) -> void:
	X = x
	Y = y
	RAD = radius
	LIFE = life
	pace = speed
	ground = ground_fn
	if surface is Color:
		stone = surface
	END = FORM + LIFE + COLLAPSE
	REACH = RAD * 12.4
	G = 4.2e7 * pow(RAD / 34.0, 3)
	DISK = [RAMP[4], RAMP[5], RAMP[6], RAMP[7]]
	var u := R.next()
	tilt = (-1.0 if u < 0.5 else 1.0) * (0.14 + fmod(u, 0.5) * 0.5)
	ring(X, Y, 190 * RAD / 34, 6, 0.34, 2, VIOLET)
	ring(X, Y, 115 * RAD / 34, 4, 0.24, 1.2, WHITE)
	bursts.append([0.0, 0.18, 0.35])
	lights.append([X, Y, 280.0 * RAD / 34, VIOLET, 1.3, 0.4, 0.4])
	for i in 70:
		var a := R.rnd(0, TAU)
		var r := R.rnd(70, 230) * RAD / 34
		var sp := R.rnd(60, 160)
		spawn(MOTE, X + cos(a) * r, Y + sin(a) * r, sin(a) * sp, -cos(a) * sp, R.rnd(0.6, 1.2), VIOLET if R.chance(0.45) else R.pick(DISK), R.rnd(0.8, 1.4))

func ticks_to_burst() -> int:
	## Battle ticks from the start until it implodes and bursts.
	return ceili(END / pace * 60.0)

func ring(x: float, y: float, r0: float, r1: float, life: float, thick: float, c: Color) -> void:
	rings.append([x, y, r0, r1, life, life, thick, c])

func spawn(k: int, x: float, y: float, vx: float, vy: float, life: float, col := Color(), size := 1.0) -> void:
	var p := Part.new()
	p.k = k; p.x = x; p.y = y; p.vx = vx; p.vy = vy; p.life = life; p.mx = life; p.col = col; p.size = size
	list.append(p)

func beat() -> float:
	if t < FORM or implosion() > 0:
		return 0.0
	var p := fmod(t - FORM, 0.85) / 0.85
	return exp(-pow((p - 0.06) / 0.045, 2)) + 0.7 * exp(-pow((p - 0.26) / 0.045, 2))

func implosion() -> float:
	return clampf((t - FORM - LIFE) / COLLAPSE, 0, 1)

func radius() -> float:
	var rr := RAD * (1 + grow) * (1 + 0.1 * gulp) * (1 + 0.045 * beat())
	if t < FORM:
		var k := t / FORM
		return rr * (1 + 1.7 * pow(k - 1, 3) + 0.7 * pow(k - 1, 2)) * minf(1, k * 3)
	var breath := 1 + sin(t * 3.1) * 0.025 + sin(t * 7.3) * 0.01
	var k := implosion()
	if k <= 0:
		return rr * breath
	if k < 0.3:
		return rr * breath * (1 + 0.14 * sin((k / 0.3) * (PI / 2)))
	return rr * breath * 1.14 * (1 - pow((k - 0.3) / 0.7, 2))

func strength() -> float:
	return Sf.smooth(0, FORM * 0.8, t) * (1 + 0.8 * implosion() + 0.45 * beat())

func feed(amount: float, col = null) -> void:
	if collapsed:
		return
	flare = minf(2.5, flare + amount * 0.05)
	gulp = minf(1, gulp + amount * 0.06)
	grow = minf(0.3, grow + amount * 0.0015)
	if col is Color:
		if colors.size() < 32:
			colors.append(col)
		else:
			colors[R.ri(0, 31)] = col
	if amount >= 3 and jet_cd <= 0 and implosion() <= 0:
		jet = 1
		jet_cd = 1.1
		var rr := radius()
		var nx := -sin(tilt)
		var ny := cos(tilt)
		for side in [-1, 1]:
			var px: float = X + nx * rr * side
			var py: float = Y + ny * rr * side
			var a0 := atan2(ny * side, nx * side)
			for i in 18:
				var a := a0 + R.rnd(-0.14, 0.14)
				var sp := R.rnd(500, 1300)
				spawn(PLASMA, px, py, cos(a) * sp, sin(a) * sp, R.rnd(0.15, 0.4))
			lights.append([px, py, 110.0, JET, 1.0, 0.25, 0.25])
			ring(px, py, 3, 22, 0.14, 1, JET_CORE)

func collapse() -> void:
	collapsed = true
	bursts.append([0.0, 0.45, 1.0])
	ring(X, Y, RAD * 1.4, RAD * 7, 0.5, 3, WHITE)
	ring(X, Y, RAD * 0.8, RAD * 4.5, 0.6, 1.8, VIOLET)
	ring(X, Y, RAD * 2.2, RAD * 9.5, 0.32, 1, JET)
	lights.append([X, Y, 420.0 * RAD / 34, Color8(240, 222, 255), 1.5, 0.5, 0.5])
	lights.append([X, Y, 280.0 * RAD / 34, VIOLET, 1.0, 0.8, 0.8])
	for i in 150:
		var a := R.rnd(0, TAU)
		var sp := R.rnd(180, 950)
		spawn(MOTE, X, Y, cos(a) * sp, sin(a) * sp, R.rnd(0.3, 0.9), VIOLET if R.chance(0.3) else (WHITE if R.chance(0.3) else R.pick(DISK)), R.rnd(1, 1.8))
	for i in 40:
		var a := R.rnd(0, TAU)
		var sp := R.rnd(400, 1200)
		spawn(PLASMA, X, Y, cos(a) * sp, sin(a) * sp, R.rnd(0.15, 0.45))
	var cols: Array = colors if not colors.is_empty() else [WHITE]
	for i in 130:
		var a := R.rnd(0, TAU)
		var sp := R.rnd(200, 900)
		spawn(INK, X + cos(a) * RAD * 0.3, Y + sin(a) * RAD * 0.3, cos(a) * sp, sin(a) * sp - R.rnd(0, 200), R.rnd(1.2, 2.4), R.pick(cols), 2.0 if R.chance(0.4) else 1.0)
	for p in list:
		var dx := p.x - X
		var dy := p.y - Y
		var d := maxf(0.001, sqrt(dx * dx + dy * dy))
		if d > RAD * 9:
			continue
		var f := 950 * (1 - d / (RAD * 9)) * (0.35 if p.k == DUSTK else 1.0)
		p.vx += dx / d * f
		p.vy += dy / d * f - f * 0.3
	for s in slabs:
		var dx: float = s[0] - X
		var dy: float = s[1] - Y
		var d := maxf(0.001, sqrt(dx * dx + dy * dy))
		var f := 850 * maxf(0, 1 - d / (RAD * 7))
		s[2] += dx / d * f
		s[3] += dy / d * f - 150
		s[5] += R.rnd(-8, 8)
		s[8] = 0.0

func done() -> bool:
	return collapsed and ended > 2.5 and list.is_empty()

func update(dt: float) -> void:
	dt *= pace
	var before := implosion()
	var beat0 := beat()
	t += dt
	for i in range(bursts.size() - 1, -1, -1):
		bursts[i][0] += dt
		if bursts[i][0] >= bursts[i][1]:
			bursts.remove_at(i)
	if not collapsed and t >= END:
		collapse()
	if collapsed:
		ended += dt
		step_slabs(dt, false)
		step(dt)
		return
	flare -= flare * 3 * dt
	gulp -= gulp * 5 * dt
	jet = maxf(0, jet - dt / 0.5)
	jet_cd -= dt
	var rr := maxf(1, radius())
	var imp := implosion()
	var k := strength()
	feed(attract(G * k, rr, dt) * 0.03)
	if imp <= 0:
		var b := beat()
		var n := (1 if R.chance(0.5) else 0) + roundi(3 * b)
		for i in n:
			var a := R.rnd(0, TAU)
			var r := R.rnd(rr * 1.8, rr * 7)
			var px := X + cos(a) * r
			var py := Y + sin(a) * r
			var pc: Color = R.pick(SHREDS)
			var vin := R.rnd(220, 520) * (1 + b)
			var vt := R.rnd(200, 400)
			var vx := sin(a) * vt - cos(a) * vin
			var vy := -cos(a) * vt - sin(a) * vin
			if i % 4 == 3:
				spawn(DUSTK, px, py, vx * 0.35, vy * 0.35, R.rnd(0.5, 0.9), pc.lerp(VOID, 0.5), R.rnd(1.6, 3.4))
			else:
				spawn(MOTE, px, py, vx, vy, minf(1.1, (r / vin) * 1.3), pc if R.chance(0.35) else pc.lerp(VOID, R.rnd(0.45, 0.8)), R.rnd(0.8, 1.5))
		if R.chance(0.5):
			var side := R.sgn()
			var r := R.rnd(rr * 2.4, rr * 3.4)
			spawn(MOTE, X + cos(tilt) * r * side, Y + sin(tilt) * r * side, -sin(tilt) * side * 120, cos(tilt) * side * 120, R.rnd(0.3, 0.6), R.pick(DISK), 1)
		var gy: float = ground.call(X)
		slab_acc += dt * (0.7 + 2.2 * b) * Sf.smooth(0.3, 1.2, t)
		if gy - Y < REACH * 0.85 and slab_acc > 1:
			slab_acc -= 1
			var sx := X + R.rnd(-1, 1) * sqrt(maxf(0, pow(REACH * 0.7, 2) - pow(gy - Y, 2))) * 0.6
			var w := R.ri(4, 9)
			var hh := R.ri(3, 5)
			var sg: float = ground.call(sx)
			if sg < 1e8:
				slabs.append([sx, sg - hh, 0.0, -R.rnd(60, 160), R.rnd(-0.2, 0.2), R.rnd(-3, 3), w, hh, 0.0, 0.0, stone])
				for i in 4:
					spawn(DUSTK, sx + R.rnd(-6, 6), sg - 2, R.rnd(-40, 40), -R.rnd(20, 70), R.rnd(0.5, 0.9), stone.lerp(Color8(150, 140, 150), 0.35), R.rnd(1.5, 3))
	else:
		if before <= 0:
			ring(X, Y, rr * 6, rr, COLLAPSE, 1.6, VIOLET)
		for i in 5:
			var a := R.rnd(0, TAU)
			var r := R.rnd(rr * 2, rr * 6)
			spawn(MOTE, X + cos(a) * r, Y + sin(a) * r, -cos(a) * 500 + sin(a) * 200, -sin(a) * 500 - cos(a) * 200, 0.4, WHITE if R.chance(0.5) else VIOLET, 1.2)
	step_slabs(dt, true)
	step(dt)

func attract(g: float, eat: float, dt: float) -> float:
	var eaten := 0
	var soft := eat * eat
	for i in range(list.size() - 1, -1, -1):
		var p := list[i]
		var dx := X - p.x
		var dy := Y - p.y
		var d2 := dx * dx + dy * dy
		if d2 > REACH * REACH:
			continue
		var d := maxf(0.001, sqrt(d2))
		if d < eat:
			list.remove_at(i)
			eaten += 1
			continue
		var mote := p.k == MOTE
		var w := 0.55 if p.k == DUSTK else (1.4 if mote else 1.0)
		var a := (g / (d2 + soft)) * minf(1, (REACH - d) / (REACH * 0.25)) * w * dt
		var ux := dx / d
		var uy := dy / d
		p.vx += (ux - uy * SWIRL) * a
		p.vy += (uy + ux * SWIRL) * a
		var drag := minf(0.2, (1 - d / REACH) * (1.0 if mote else 3.2) * dt)
		p.vx -= p.vx * drag
		p.vy -= p.vy * drag
	return eaten

func step_slabs(dt: float, pulling: bool) -> void:
	var rr := maxf(1, radius())
	var k := strength()
	for i in range(slabs.size() - 1, -1, -1):
		var s: Array = slabs[i]
		var dx: float = X - s[0]
		var dy: float = Y - s[1]
		var d := maxf(0.001, sqrt(dx * dx + dy * dy))
		var size: float = maxf(s[6], s[7]) * Sf.PX
		if pulling:
			if d < rr * 0.9 + size * 0.15:
				slabs.remove_at(i)
				feed(2 + minf(6, size / 10), s[10])
				continue
			var a := (G * k) / (d * d + rr * rr) * minf(1, (REACH - d) / (REACH * 0.25))
			var ux := dx / d
			var uy := dy / d
			var lift := Sf.GRAVITY * minf(1, k) * sqrt(maxf(0, 1 - d / REACH))
			s[2] += (ux - uy * SWIRL) * a * dt
			s[3] += ((uy + ux * SWIRL) * a - lift) * dt
			var drag := minf(0.2, (1 - d / REACH) * 2 * dt)
			s[2] -= s[2] * drag
			s[3] -= s[3] * drag
			s[8] = maxf(s[8] * 0.9, minf(1, maxf(0, (rr * 3.4 - d) / (rr * 2.6))) * 0.8)
			s[9] = atan2(dy, dx)
		else:
			s[8] *= 0.9
		s[3] += Sf.GRAVITY * dt
		s[0] += s[2] * dt
		s[1] += s[3] * dt
		s[4] += s[5] * dt
		if s[1] > ground.call(s[0]) + 40:
			slabs.remove_at(i)

func step(dt: float) -> void:
	for i in range(list.size() - 1, -1, -1):
		var p := list[i]
		p.life -= dt
		if p.life <= 0:
			list.remove_at(i)
			continue
		match p.k:
			PLASMA:
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
			MOTE:
				p.vx -= p.vx * 0.6 * dt
				p.vy -= p.vy * 0.6 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
			DUSTK:
				p.vx -= p.vx * 4 * dt
				p.vy -= p.vy * 4 * dt + 10 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
			INK:
				p.vy += Sf.GRAVITY * dt
				p.vx -= p.vx * 0.5 * dt
				var g: float = ground.call(p.x)
				var ny := p.y + p.vy * dt
				p.x += p.vx * dt
				if p.vy > 0 and p.y <= g and ny >= g:
					p.y = g - 0.5
					if p.vy > 260 and R.chance(0.45):
						p.vy = -p.vy * 0.22
						p.vx = p.vx * 0.55 + R.rnd(-30, 30)
					else:
						p.vx = 0
						p.vy = 0
						p.life = minf(p.life, 0.5)
				else:
					p.y = ny
	for a in [rings, lights]:
		var li := 4 if a == rings else 5
		for i in range(a.size() - 1, -1, -1):
			a[i][li] -= dt
			if a[i][li] <= 0:
				a.remove_at(i)

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		parts(buf, light, true)
		return
	for s in slabs:
		draw_slab(buf, s)
	if not collapsed:
		draw_hole(buf, light, radius(), implosion(), Sf.smooth(0, FORM, t))
	for b in bursts:
		draw_burst(buf, light, X / Sf.PX, Y / Sf.PX, b[0] / b[1], (RAD / Sf.PX) * b[2])
	parts(buf, light, false)
	for r in rings:
		var k: float = r[4] / r[5]
		var e := 1 - pow(k, 3)
		buf.ring(r[0] / Sf.PX, r[1] / Sf.PX, (r[2] + (r[3] - r[2]) * e) / Sf.PX, maxf(1, r[6] * k + 0.4), r[7], minf(1, k * 1.6))
	for l in lights:
		var k: float = l[5] / l[6]
		light.glow(l[0] / Sf.PX, l[1] / Sf.PX, (l[2] / Sf.PX) * (0.55 + 0.45 * k), l[3], l[4] * k * k)

func tone(I: float, x: int, y: int, blue: float):
	if I < 0.08 and Sf.bayer(x, y) > I / 0.08:
		return null
	var n := RAMP.size() - 1
	var f := clampf((I / 1.12) * n, 0, n)
	var idx := floori(f)
	if f - idx > Sf.bayer(x, y):
		idx = mini(n, idx + 1)
	var c: Color = RAMP[idx]
	return c.lerp(BLUE_WHITE, minf(1, blue)) if blue > 0.05 and idx >= n - 2 else c

func tex(rho: float, th: float, tt: float) -> float:
	var a := th + 5 * pow(rho, -1.5) * tt
	var streak := 0.66 + 0.2 * sin(a * 6 + rho * 9.5) + 0.14 * sin(a * 13 - rho * 21 + 1.7)
	var lane := 0.78 + 0.22 * cos(rho * 12.5 + sin(a * 2) * 0.6)
	var knot := maxf(0, sin(a * 3 + rho * 7 + sin(tt * 1.3) * 2) * sin(a * 5 - rho * 11 + tt * 0.9))
	return streak * lane + knot * knot * knot * 0.55

func dop(s: float) -> Array:
	var D := 1 + 0.5 * -s
	return [pow(D, 1.25), maxf(0, D - 1.25) * 1.6]

func draw_hole(buf: Sf.Px, light: Sf.Px, rw: float, imp: float, form: float) -> void:
	if rw < 0.6:
		return
	var rs := rw / Sf.PX
	var shk := gulp * 0.9 + imp * 0.8
	var ax := X / Sf.PX + sin(t * 71) * shk
	var ay := Y / Sf.PX + cos(t * 63) * shk
	var bright := form * (1 + 2.2 * imp) * (1 + 0.45 * minf(2, flare))
	var q := 0.2
	var rin := 1.4
	var rout := 3.5
	var tl := tilt + sin(t * 1.7) * 0.04
	var ct := cos(tl)
	var st := sin(tl)
	var ext := ceili(rs * rout * 1.05) + 2
	var flicker := 1 + sin(t * 23) * 0.04 + sin(t * 57) * 0.03 + flare * 0.15 * sin(t * 90)
	# (rows of same-coloured pixels go out as one rect)
	for py in range(floori(ay - ext), ceili(ay + ext) + 1):
		var run_x := 0
		var run_n := 0
		var run_c := Color()
		for px in range(floori(ax - ext), ceili(ax + ext) + 2):
			var c = null
			var dx := (px + 0.5 - ax) / rs
			var dy := (py + 0.5 - ay) / rs
			var u := dx * ct + dy * st
			var v := -dx * st + dy * ct
			var r := sqrt(u * u + v * v)
			if r <= rout * 1.05:
				var I := 0.0
				var lit := false
				var blue := 0.0
				if r >= 1:
					var s := maxf(0, -v / r)
					var hh := 0.1 + 0.62 * pow(s, 1.3)
					var e := (r - 1) / hh
					if v < 0.25 and e < 1:
						var dd := dop(u / r)
						blue = dd[1]
						I = maxf(I, (1 - pow(e, 1.6)) * (0.72 + 0.28 * tex(rin + e * 1.5, atan2(v, u), t)) * 0.9 * dd[0])
						lit = true
					var s2 := maxf(0, v / r)
					var h2 := 0.04 + 0.2 * pow(s2, 1.3)
					var e2 := (r - 1) / h2
					if v > -0.25 and e2 < 1:
						var dd := dop(u / r)
						blue = dd[1]
						I = maxf(I, (1 - pow(e2, 1.4)) * 0.5 * dd[0])
						lit = true
					if r < 1.075 + 0.04 * flare:
						var dd := dop(u / r)
						blue = dd[1]
						I = maxf(I, 1.05 * flicker * (0.75 + 0.25 * dd[0]))
						lit = true
				var shadow := r < 1
				var rho := sqrt(u * u + (v / q) * (v / q))
				if rho >= rin and rho <= rout and (v >= 0 or r >= 1):
					var k := (rho - rin) / (rout - rin)
					var dd := dop(u / rho)
					var Id: float = 1.25 * pow(1 - k, 1.1) * (0.7 + 0.3 * Sf.smooth(0, 0.05, k)) * (1 - Sf.smooth(0.72, 1, k)) * tex(rho, atan2(v / q, u), t) * dd[0]
					if v >= 0:
						if Id > 0.08:
							I = Id
							shadow = false
							lit = true
							blue = dd[1]
					elif Id > I:
						I = Id
						lit = true
						blue = dd[1]
				if not shadow and lit:
					c = tone(I * bright, px, py, blue)
				if c == null and r < 1:
					c = SHADOW
				if c != null and I * bright > 0.35 and ((px + py) & 1) == 0:
					light.add(px, py, c, 0.22 * minf(1.3, I * bright))
			if c != null and run_n > 0 and c == run_c:
				run_n += 1
				continue
			if run_n > 0:
				buf.span(run_x, run_x + run_n - 1, py, run_c)
				run_n = 0
			if c != null:
				run_x = px
				run_n = 1
				run_c = c
	var jet_l := rs * (4 + 6 * jet) if jet > 0.02 else 0.0
	if jet_l > 0:
		var nx := -st
		var ny := ct
		for side in [-1, 1]:
			var s := rs * 0.9
			while s < jet_l:
				var f := (s - rs * 0.9) / (jet_l - rs * 0.9)
				var wob := sin(s * 0.45 - t * 40 + side) * 0.35 * f
				var px: float = ax + nx * s * side + ct * wob
				var py: float = ay + ny * s * side + st * wob
				var w := (1 + 3.2 * jet) * pow(1 - f, 0.6) * (0.8 + 0.2 * sin(t * 70 + s))
				if w > 1.3:
					buf.disc(px, py, w + 0.6, JET_EDGE)
				if w > 0.6:
					buf.disc(px, py, w, JET)
				buf.disc(px, py, maxf(0.5, w * 0.6), JET_CORE)
				if int(s * 2) % 5 == 0:
					light.glow(px, py, 8 + 12 * jet * (1 - f), JET, 0.45 * jet)
				s += 0.7
	light.glow(ax, ay, rs * 5.5, HOLE_LIGHT, 0.42 * bright)
	light.glow(ax, ay, rs * 2.2, Color8(235, 210, 255), 0.25 * bright)

func draw_burst(buf: Sf.Px, light: Sf.Px, ax: float, ay: float, k: float, r0: float) -> void:
	var e := 1 - pow(1 - k, 3)
	var fade := 1 - k
	var rc := r0 * (0.5 + 1.3 * e)
	for py in range(floori(ay - rc), ceili(ay + rc) + 1):
		for px in range(floori(ax - rc), ceili(ax + rc) + 1):
			var d := Vector2(px + 0.5 - ax, py + 0.5 - ay).length() / rc
			if d > 1:
				continue
			var a := fade * (1 - d * d)
			if a < Sf.bayer(px, py):
				continue
			buf.put(px, py, JET_CORE if a > 0.55 else (BLUE_WHITE if a > 0.3 else VIOLET))
	var ct := cos(tilt)
	var st := sin(tilt)
	var spikes := [[ct, st, 1.0], [-ct, -st, 1.0], [-st, ct, 0.8], [st, -ct, 0.8], [ct - st, st + ct, 0.45], [-ct + st, -st - ct, 0.45], [ct + st, st - ct, 0.45], [-ct - st, -st + ct, 0.45]]
	for sp in spikes:
		var n: float = Vector2(sp[0], sp[1]).length()
		var L: float = r0 * (2 + 6 * fade) * sp[2]
		var r := rc * 0.6
		while r < rc + L:
			var f := (r - rc * 0.6) / (rc * 0.4 + L)
			var px := roundi(ax + (sp[0] / n) * r)
			var py := roundi(ay + (sp[1] / n) * r)
			r += 0.8
			if f > fade * 1.2 or (f > 0.6 and Sf.bayer(px, py) < f - 0.4):
				continue
			buf.put(px, py, JET_CORE if f < 0.35 else JET)
	light.glow(ax, ay, r0 * (4 + 5 * e), JET_CORE, 0.9 * fade)
	light.glow(ax, ay, r0 * (6 + 6 * e), VIOLET, 0.5 * fade)

func draw_slab(buf: Sf.Px, s: Array) -> void:
	var cx: float = s[0] / Sf.PX
	var cy: float = s[1] / Sf.PX
	var sx: float = 1 + 2.2 * s[8]
	var sy: float = 1 - 0.55 * s[8]
	var cp := cos(s[9])
	var sp := sin(s[9])
	var ca := cos(s[4])
	var sa := sin(s[4])
	var r := ceili(Vector2(s[6], s[7]).length() * 0.5 * sx) + 2
	var hw: float = s[6] / 2.0 + 0.5
	var hh: float = s[7] / 2.0 + 0.5
	var c: Color = s[10]
	var lit := c.lerp(WHITE, 0.25)
	var dark := c.lerp(SHADOW, 0.45)
	for py in range(floori(cy - r), ceili(cy + r) + 1):
		for px in range(floori(cx - r), ceili(cx + r) + 1):
			var dx := px + 0.5 - cx
			var dy := py + 0.5 - cy
			var along := (dx * cp + dy * sp) / sx
			var across := (-dx * sp + dy * cp) / sy
			var wx := along * cp - across * sp
			var wy := along * sp + across * cp
			var u := wx * ca + wy * sa
			var v := -wx * sa + wy * ca
			var au := absf(u)
			var av := absf(v)
			if au > hw + 0.7 or av > hh + 0.7:
				continue
			buf.put(px, py, OUTLINE if au > hw or av > hh else (lit if v < -hh + 1 else (dark if v > hh - 1 else c)))

func parts(buf: Sf.Px, light: Sf.Px, back: bool) -> void:
	for p in list:
		if (p.k == DUSTK or p.k == INK) != back:
			continue
		var k := p.life / p.mx
		var ax := p.x / Sf.PX
		var ay := p.y / Sf.PX
		var px := floori(ax)
		var py := floori(ay)
		match p.k:
			DUSTK:
				buf.alpha_disc(ax, ay, p.size * (0.6 + (1 - k) * 0.9), p.col, pow(k, 1.3) * 0.7)
			INK:
				if k > 0.25 or Sf.bayer(px, py) < k * 4:
					buf.put(px, py, p.col)
					if p.size >= 2:
						buf.put(px + 1, py, p.col)
						buf.put(px, py + 1, Sf.scale(p.col, 0.85))
						buf.put(px + 1, py + 1, Sf.scale(p.col, 0.75))
			PLASMA:
				var hot := WHITE if k > 0.5 else (P_CYAN if k > 0.25 else P_DEEP)
				var sp := maxf(0.001, Vector2(p.vx, p.vy).length())
				var ux := p.vx / sp
				var uy := p.vy / sp
				var ln := minf(9, 1 + sp * 0.011)
				buf.line(ax - ux * ln, ay - uy * ln, ax - ux * ln * 0.4, ay - uy * ln * 0.4, hot if k > 0.5 else P_DEEP)
				buf.line(ax - ux * ln * 0.45, ay - uy * ln * 0.45, ax, ay, hot)
				light.glow(ax, ay, 3, hot, 0.45 * k)
			MOTE:
				var sp := maxf(0.001, Vector2(p.vx, p.vy).length())
				var ux := p.vx / sp
				var uy := p.vy / sp
				var ln := minf(16, 0.5 + sp * 0.013) * p.size
				if k < 0.35 and Sf.bayer(px, py) > k / 0.35:
					continue
				buf.line(ax - ux * ln, ay - uy * ln, ax - ux * ln * 0.35, ay - uy * ln * 0.35, Sf.scale(p.col, 0.55))
				buf.line(ax - ux * ln * 0.4, ay - uy * ln * 0.4, ax, ay, p.col)
				light.glow(ax, ay, 2.5 + p.size, p.col, 0.4 * k)

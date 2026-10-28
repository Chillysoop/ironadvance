class_name SfLightning
extends RefCounted
## V5, Sprite Fusion lightning.ts in three of its modes:
##  ARC     a chain from a source through each hop, re-jagged 30 times a second, with plasma
##          sparks, crawling sparks at each target and scorch marks where a hop meets the ground.
##  CRACKLE little arcs jumping across a body's outline (a stunned Jackal), with jolts.
##  IMPACT  a strike point: star of bolts, ring, arcs and a strobing glow (a Storm Cage hit).
## Positions are world units; the arc's ends can follow callables.

enum { ARC, CRACKLE, IMPACT }
const SPARK := 0
const PLASMA := 1
const SMOKE := 2
const DUST := 3
const VOLT := [Color("ffffff"), Color("e9f8ff"), Color("a3dcff"), Color("5eb0ff"), Color("5b6cff"), Color("4733c4"), Color("2a1b78")]
const PLASMA_C := [Color("ffffff"), Color("7ff3ff"), Color("1ab8e6")]
const SPARKS := [Color("fff3a6"), Color("ffe26b"), Color("ff8a2a"), Color("f2561d")]
const HEAT_RAMP := [Color("ffffff"), Color("fff3a6"), Color("ffe26b"), Color("ffc23d"), Color("ff8a2a"), Color("f2561d"), Color("c9281f"), Color("8a1f17"), Color("4f1a13"), Color("2a120e")]
const SMOKE_RAMP := [Color("7b6f72"), Color("5d5660"), Color("433d48"), Color("2b2630"), Color("1a171e")]
const SMOKE_TINT := Color("5b5566")
const DUST_C := Color("7a6e8e")
const SOOT := Color("0d0a12")
const SOOT2 := Color("17121d")
const LINK := 0.05

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
var mode := ARC
var V: Array = VOLT
var PL: Array = PLASMA_C
var ground: Callable
var list: Array[Part] = []
var lights: Array = []  # [x, y, r, color, k, life, max]
var t := 0.0
var pt := 0.0
var at := -1
var stop_at := 0.9
# ARC
var from_fn: Callable
var hops: Array = []    # Vector2 world
var links: Array = []   # [on, hit, bolt]
var crawls: Array = []  # [bolt, t, life]
var marks: Array = []   # [x, y, t]
# CRACKLE
var src: Callable       # -> [xs, ys, feet]
var edge: Array = []
var centre := Vector2()
var shock := 0.0
var next_shock := 0.12
var arcs: Array = []    # [bolt, t, life]
# IMPACT
var ix := 0.0
var iy := 0.0
var S := 1.0
var star: Array = []
var star_at := -1

static func arc(from: Callable, to: Array, ground_fn: Callable, duration := 0.9) -> SfLightning:
	var e := SfLightning.new()
	e.mode = ARC
	e.from_fn = from
	e.hops = to
	e.ground = ground_fn
	e.stop_at = duration
	for i in to.size():
		e.links.append([i * LINK, false, null])
	return e

static func crackle(source: Callable, ground_fn: Callable, duration := 1.8) -> SfLightning:
	var e := SfLightning.new()
	e.mode = CRACKLE
	e.src = source
	e.ground = ground_fn
	e.stop_at = duration
	return e

static func impact(x: float, y: float, ground_fn: Callable, size := 1.0, sparks := 64) -> SfLightning:
	var e := SfLightning.new()
	e.mode = IMPACT
	e.ground = ground_fn
	e.S = size
	e.ix = x / Sf.PX
	e.iy = y / Sf.PX
	for i in sparks:
		var a := e.R.rnd(0, TAU)
		var sp := e.R.rnd(240, 900) * sqrt(size)
		e.spawn(PLASMA, x, y, cos(a) * sp, sin(a) * sp - 100, e.R.rnd(0.2, 0.75))
	for i in 5:
		e.spawn(SMOKE, x + e.R.rnd(-14, 14) * size, y + e.R.rnd(-10, 10) * size, e.R.rnd(-10, 10), e.R.rnd(-30, -12), e.R.rnd(1.2, 2), Sf.mix(SMOKE_TINT, VOLT[4], 0.35), e.R.rnd(3, 5) * size, e.R.rnd(0.08, 0.25))
	return e

func stop() -> void:
	stop_at = minf(stop_at, t)

func done() -> bool:
	var over := false
	match mode:
		ARC:
			over = t > stop_at + 1.7
		CRACKLE:
			over = t > stop_at + 0.4 and arcs.is_empty()
		IMPACT:
			over = t > 1.6
	return over and list.is_empty() and lights.is_empty()

func spawn(k: int, x: float, y: float, vx: float, vy: float, life: float, col := Color(0, 0, 0, 0), size := 1.0, delay := 0.0) -> void:
	var p := Part.new()
	p.k = k; p.x = x; p.y = y; p.vx = vx; p.vy = vy; p.life = life; p.mx = life
	p.col = col; p.size = size; p.seed = R.next() * 100; p.delay = delay
	list.append(p)

func on_ground(x: float, y: float) -> bool:
	return absf(float(ground.call(x)) - y) < 8

# ---------------------------------------------------------------- bolts
func bolt(x0: float, y0: float, x1: float, y1: float, jag := 0.32, forks := 0.35, w := 1.0, depth := 0) -> Array:
	## A list of paths [pts: PackedVector2Array, w]: midpoint-displaced trunk plus forks.
	var out: Array = []
	var L := Vector2(x1 - x0, y1 - y0).length()
	var pts := PackedVector2Array([Vector2(x0, y0), Vector2(x1, y1)])
	var off := L * jag
	while pts.size() < 2 + L / 3:
		var nxt := PackedVector2Array([pts[0]])
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var l := maxf(0.001, a.distance_to(b))
			var o := R.rnd(-off, off)
			nxt.append((a + b) / 2 + Vector2(-(b.y - a.y) / l, (b.x - a.x) / l) * o)
			nxt.append(b)
		pts = nxt
		off *= 0.52
	out.append([pts, w])
	if depth < 2:
		for i in range(2, pts.size() - 3):
			if R.chance(forks / (1 + depth) / maxf(4, pts.size() / 6.0)):
				var a := pts[i]
				var b := pts[mini(pts.size() - 1, i + 3)]
				var ang := atan2(b.y - a.y, b.x - a.x) + R.sgn() * R.rnd(0.35, 0.9)
				var l := (L - (float(i) / pts.size()) * L) * R.rnd(0.25, 0.55)
				out.append_array(bolt(a.x, a.y, a.x + cos(ang) * l, a.y + sin(ang) * l, jag * 1.1, forks, w * 0.55, depth + 1))
	return out

func hop(x0: float, y0: float, x1: float, y1: float) -> Array:
	var mx := (x0 + x1) / 2 + R.rnd(-4, 4)
	var my := minf(y0, y1) - Vector2(x1 - x0, y1 - y0).length() * R.rnd(0.16, 0.28)
	var a := bolt(x0, y0, mx, my, 0.2, 0.4)
	var b := bolt(mx, my, x1, y1, 0.2, 0.4)
	var trunk: PackedVector2Array = a[0][0].duplicate()
	trunk.append_array(b[0][0].slice(1))
	return [[trunk, 1.0]] + a.slice(1) + b.slice(1)

func stroke(buf: Sf.Px, light: Sf.Px, b: Array, k: float, s: float) -> void:
	for pass_i in 3:
		for p in b:
			var pts: PackedVector2Array = p[0]
			var w: float = p[1]
			var trunk := w >= 1
			if not trunk and (k < 0.5 or (pass_i == 2 and w < 0.5)):
				continue
			for i in pts.size() - 1:
				var a := pts[i]
				var c := pts[i + 1]
				var l := maxf(1, a.distance_to(c))
				var d := 0.0
				var r0 := ((2.1 if k > 0.6 else 1.6) if trunk else 1.1) * s
				var r1 := ((1.3 if k > 0.6 else 0.8) if trunk else 0.5) * s
				while d <= l:
					var q := a + (c - a) * (d / l)
					if pass_i == 0:
						buf.disc(q.x, q.y, r0, V[5])
					elif pass_i == 1:
						buf.disc(q.x, q.y, r1, V[2] if trunk else V[3])
					elif trunk and k > 0.3:
						buf.put(floori(q.x), floori(q.y), V[0])
					d += 0.5 if pass_i == 2 else 1.0
				if pass_i == 0 and i % 3 == 0:
					light.glow(a.x, a.y, (14.0 if trunk else 7.0) * s, V[3], 0.5 * k * w)

func draw_bolt(buf: Sf.Px, light: Sf.Px, b: Array, k := 1.0, glow_k := 0.5) -> void:
	for p in b:
		var pts: PackedVector2Array = p[0]
		var w: float = p[1]
		var thick := w >= 1
		for i in pts.size() - 1:
			var a := pts[i]
			var c := pts[i + 1]
			var l := maxf(1, a.distance_to(c))
			var d := 0.0
			while d <= l:
				var q := a + (c - a) * (d / l)
				if k > 0.45 and thick:
					for o in [Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
						buf.dot(q.x + o.x, q.y + o.y, V[4], (k - 0.45) * 1.6)
				if k > 0.25 and (thick or w > 0.4):
					buf.dot(q.x + 1, q.y, V[2])
					buf.dot(q.x, q.y + 1, V[2])
				buf.put(floori(q.x), floori(q.y), V[0] if thick and k > 0.3 else V[2])
				d += 0.5
			if i % 3 == 0:
				light.glow(a.x, a.y, (9.0 if thick else 5.0) * (0.5 + k * 0.5), V[3], glow_k * k * w)

# ---------------------------------------------------------------- update
func update(dt: float) -> void:
	t += dt
	match mode:
		ARC:
			update_arc()
		CRACKLE:
			update_crackle(dt)
		IMPACT:
			update_impact()
	update_parts(dt)
	for i in range(lights.size() - 1, -1, -1):
		lights[i][5] -= dt
		if lights[i][5] <= 0:
			lights.remove_at(i)

func level_arc() -> float:
	var flick := (0.6 if floori(t * 60) % 3 == 1 else 1.0) if t < 0.12 else 0.8 + 0.2 * sin(t * 61) * sin(t * 23)
	return flick if t < stop_at else flick * clampf(1 - (t - stop_at) / 0.18, 0, 1)

func points() -> Array:
	return [from_fn.call()] + hops

func update_arc() -> void:
	var P := points()
	var k := level_arc()
	var f := floori(t * 30)
	for i in links.size():
		var l: Array = links[i]
		if l[1] or t < l[0]:
			continue
		l[1] = true
		var p: Vector2 = P[i + 1]
		var g: float = ground.call(p.x)
		var og := absf(g - p.y) < 8
		for j in 14:
			var a := (-PI / 2 if og else 0.0) + R.rnd(-1.4, 1.4) + (0.0 if og else R.rnd(0, TAU))
			var sp := R.rnd(200, 620)
			spawn(PLASMA, p.x, p.y - 2, cos(a) * sp, sin(a) * sp, R.rnd(0.15, 0.45))
		if og:
			dust(p.x, g, 4, 0.9)
			marks.append([p.x, g, t])
		lights.append([p.x, p.y, 120.0, V[3], 0.8, 0.2, 0.2])
	if f != at and k > 0:
		at = f
		for i in links.size():
			var l: Array = links[i]
			if not l[1]:
				continue
			var a: Vector2 = P[i] / Sf.PX
			var c: Vector2 = P[i + 1] / Sf.PX
			l[2] = hop(a.x, a.y, c.x, c.y) if on_ground(P[i].x, P[i].y) and on_ground(P[i + 1].x, P[i + 1].y) else bolt(a.x, a.y, c.x, c.y, 0.22, 0.45)
	if k > 0.3:
		for i in links.size():
			if not links[i][1] or not R.chance(0.3):
				continue
			var p: Vector2 = P[i + 1]
			var a := R.rnd(0, TAU)
			var d := R.rnd(4, 14)
			crawls.append([bolt(p.x / Sf.PX, p.y / Sf.PX, p.x / Sf.PX + cos(a) * d, p.y / Sf.PX + sin(a) * d * (0.3 if on_ground(p.x, p.y) else 1.0), 0.4, 0.2, 0.6), t, 0.07])
		if R.chance(0.5):
			var i := R.ri(0, links.size() - 1)
			if links[i][1]:
				var q: Vector2 = (P[i] as Vector2).lerp(P[i + 1], R.next())
				spawn(PLASMA, q.x, q.y, R.rnd(-120, 120), R.rnd(-160, 40), R.rnd(0.1, 0.25))
	for i in range(crawls.size() - 1, -1, -1):
		if t - crawls[i][1] > crawls[i][2]:
			crawls.remove_at(i)

func level_crackle() -> float:
	return Sf.smooth(0, 0.08, t) * (1.0 if t < stop_at else clampf(1 - (t - stop_at) / 0.3, 0, 1))

func outline() -> void:
	var s: Array = src.call()
	if s.is_empty():
		stop()
		return
	var xs: PackedInt32Array = s[0]
	var ys: PackedInt32Array = s[1]
	var on := {}
	for i in xs.size():
		on[Vector2i(xs[i], ys[i])] = true
	edge = []
	for i in xs.size():
		var x := xs[i]
		var y := ys[i]
		if not on.has(Vector2i(x - 1, y)) or not on.has(Vector2i(x + 1, y)) or not on.has(Vector2i(x, y - 1)) or not on.has(Vector2i(x, y + 1)):
			edge.append(Vector2(x + 0.5, y + 0.5))
	if edge.is_empty():
		var c: Vector2 = s[2] / Sf.PX
		for i in 48:
			var a := R.rnd(0, TAU)
			edge.append(c + Vector2(cos(a), sin(a)) * 18 * sqrt(R.next()))
	var sum := Vector2()
	for p in edge:
		sum += p
	centre = sum / edge.size()

func update_crackle(dt: float) -> void:
	shock = maxf(0, shock - dt)
	var f := floori(t * 30)
	var k := level_crackle()
	if f != at and f % 2 == 0 and k > 0.05 and t < stop_at:
		at = f
		outline()
		if not edge.is_empty():
			for n in 2 + R.ri(0, 1):
				var a: Vector2 = R.pick(edge)
				var u := a - centre
				var ang := u.angle() + R.rnd(-1.2, 1.2)
				var d := R.rnd(6, 15)
				var e := a + Vector2(cos(ang), sin(ang)) * d
				for tries in 10:
					var c: Vector2 = R.pick(edge)
					if c.distance_to(e) < 4 and c.distance_to(a) > 4:
						e = c
				arcs.append([bolt(a.x, a.y, e.x, e.y, 0.42, 0.35), t, R.rnd(0.05, 0.09)])
				if R.chance(0.4):
					spawn(PLASMA, e.x * Sf.PX, e.y * Sf.PX, R.rnd(-140, 140), R.rnd(-200, 20), R.rnd(0.1, 0.25))
			var low: Vector2 = edge[0]
			for p in edge:
				if p.y > low.y:
					low = p
			var g: float = float(ground.call(low.x * Sf.PX)) / Sf.PX
			if R.chance(0.25) and g - low.y < 14:
				arcs.append([bolt(low.x, low.y, low.x + R.rnd(-9, 9), g - 0.5, 0.45, 0.3), t, 0.07])
	if t >= next_shock and t < stop_at and not edge.is_empty():
		next_shock = t + R.rnd(0.5, 0.8)
		shock = 0.05
		for i in 6:
			var a := R.rnd(0, TAU)
			var sp := R.rnd(150, 400)
			var p: Vector2 = R.pick(edge)
			spawn(PLASMA, p.x * Sf.PX, p.y * Sf.PX, cos(a) * sp, sin(a) * sp - 60, R.rnd(0.1, 0.3))
	for i in range(arcs.size() - 1, -1, -1):
		if t - arcs[i][1] > arcs[i][2]:
			arcs.remove_at(i)

func update_impact() -> void:
	var f := floori(t * 30)
	if t < 0.3 and f != star_at:
		star_at = f
		var ln := Sf.out_back(t / 0.07, 2.2) if t < 0.07 else 1 - (t - 0.07) / 0.3
		star = []
		for i in 7:
			var a := i / 7.0 * TAU + Sf.hsh(i, 3) * 0.6 + R.rnd(-0.12, 0.12)
			var L := (18 + 18 * Sf.hsh(i, 5)) * maxf(0.15, ln) * S
			star.append(bolt(ix, iy, ix + cos(a) * L, iy + sin(a) * L, 0.28, 0.5))
	if t > 0.04 and t < 0.9 and R.chance(0.5 * (1 - t / 0.9)):
		var a := R.rnd(0, TAU)
		var d := R.rnd(6, 26) * S
		var a2 := a + R.rnd(-1.4, 1.4)
		var l := R.rnd(6, 14) * S
		var x0 := ix + cos(a) * d
		var y0 := iy + sin(a) * d
		arcs.append([bolt(x0, y0, x0 + cos(a2) * l, y0 + sin(a2) * l, 0.4, 0.2, 0.6), t, 0.07])
		if R.chance(0.4):
			spawn(PLASMA, x0 * Sf.PX, y0 * Sf.PX, R.rnd(-200, 200), R.rnd(-260, 40), R.rnd(0.12, 0.3))
	for i in range(arcs.size() - 1, -1, -1):
		if t - arcs[i][1] > arcs[i][2]:
			arcs.remove_at(i)

func update_parts(dt: float) -> void:
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
			SMOKE:
				p.vy -= 32 * dt
				p.vx += sin(pt * 1.3 + p.seed) * 16 * dt
				p.vx -= p.vx * 1.6 * dt
				p.vy -= p.vy * 1.2 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
			DUST:
				p.vx -= p.vx * 4 * dt
				p.vy -= p.vy * 4 * dt + 10 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt

func dust(x: float, y: float, n: int, spread: float) -> void:
	for i in n:
		spawn(DUST, x + R.rnd(-3, 3), y - 1, R.sgn() * R.rnd(20, 110) * spread, -R.rnd(5, 45), R.rnd(0.3, 0.65), DUST_C, R.rnd(1.3, 2.8))

# ---------------------------------------------------------------- draw
func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		if mode == ARC:
			for m in marks:
				scorch(buf, light, m[0] / Sf.PX, m[1] / Sf.PX, 6, pow(clampf(1 - (t - m[2]) / 1.6, 0, 1), 1.3))
		draw_parts(buf, light, true)
		return
	match mode:
		ARC:
			draw_arc(buf, light)
		CRACKLE:
			var k := level_crackle()
			for a in arcs:
				stroke(buf, light, a[0], maxf(0.35, (1 - (t - a[1]) / (a[2] + 0.04)) * k), 0.45)
			if k > 0.02:
				light.glow(centre.x, centre.y, 34, V[3], (0.18 + 0.12 * sin(t * 57) + (0.35 if shock > 0 else 0.0)) * k)
		IMPACT:
			draw_impact(buf, light)
	draw_parts(buf, light, false)
	for l in lights:
		var k: float = l[5] / l[6]
		light.glow(l[0] / Sf.PX, l[1] / Sf.PX, (l[2] / Sf.PX) * (0.55 + 0.45 * k), l[3], l[4] * k * k)

func draw_arc(buf: Sf.Px, light: Sf.Px) -> void:
	var P := points()
	var k := level_arc()
	if k > 0:
		for l in links:
			if l[1] and l[2] != null:
				stroke(buf, light, l[2], k, 0.7)
		for i in links.size():
			if not links[i][1]:
				continue
			var a: Vector2 = P[i + 1] / Sf.PX
			var r := (2.2 + sin(t * 47 + i) * 0.6) * k
			buf.disc(a.x, a.y, r + 1.4, V[5])
			buf.disc(a.x, a.y, r + 0.6, V[2])
			buf.disc(a.x, a.y, r * 0.6, V[0])
			light.glow(a.x, a.y, 20, V[3], 0.5 * k)
		var h: Vector2 = P[0] / Sf.PX
		var hr := (2 + sin(t * 53) * 0.5) * k
		buf.disc(h.x, h.y, hr + 1, V[3])
		buf.disc(h.x, h.y, hr, V[0])
		light.glow(h.x, h.y, 16, V[2], 0.6 * k)
	elif t - stop_at < 0.45:
		var g := 1 - (t - stop_at - 0.18) / 0.27
		for l in links:
			if l[2] != null:
				for p in l[2]:
					if p[1] >= 1:
						for q in p[0]:
							buf.dot(q.x, q.y, V[5], g * 0.7)
	for c in crawls:
		draw_bolt(buf, light, c[0], 1 - (t - c[1]) / 0.09, 0.3)

func draw_impact(buf: Sf.Px, light: Sf.Px) -> void:
	if t < 0.05:
		buf.disc(ix, iy, (10 - t * 60) * S, V[3])
		buf.disc(ix, iy, (8 - t * 60) * S, V[1])
		buf.disc(ix, iy, (6 - t * 50) * S, V[0])
	if t < 0.32:
		var k := t / 0.32
		var r := (4 + 34 * (1 - pow(1 - k, 3))) * S
		buf.ring(ix, iy, r, maxf(1, 3 * (1 - k)), V[1] if k < 0.4 else V[3], 1.2 - k)
	if t < 0.3:
		for b in star:
			draw_bolt(buf, light, b, 1 - t / 0.36, 0.6)
	for a in arcs:
		draw_bolt(buf, light, a[0], 1 - (t - a[1]) / 0.1, 0.35)
	if t > 0.15 and t < 1.5:
		for i in int(10 * (1 - t / 1.5)):
			var s := floori(t * 40) * 13 + i
			var a := Sf.hsh(s, 1) * TAU
			var d := (4 + Sf.hsh(s, 2) * 30) * S
			var x := ix + cos(a) * d
			var y := iy + sin(a) * d
			buf.dot(x, y, V[0] if Sf.hsh(s, 3) < 0.3 else V[2])
			if Sf.hsh(s, 4) < 0.4:
				buf.dot(x + (1 if Sf.hsh(s, 5) < 0.5 else -1), y + 1, V[3])
	var strobe := ((0.7 if floori(t * 60) % 2 else 1.0) if t < 0.3 else 0.5 + 0.5 * sin(t * 70))
	light.glow(ix, iy, 70 * S * maxf(0, 1 - t / 1.7), V[3], 0.9 * exp(-t * 4) * strobe)
	light.glow(ix, iy, 26 * S, V[0], 0.9 * exp(-t * 9))

func scorch(buf: Sf.Px, light: Sf.Px, cx: float, cy: float, rx: float, T0: float) -> void:
	var ry := maxf(2.5, rx * 0.09)
	for y in range(floori(cy), floori(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			var d := sqrt(dx * dx + dy * dy)
			if d > 1:
				continue
			var kh := Sf.hsh(x * 31 + y * 7)
			var T := T0 * (1.25 - d) - kh * 0.35
			if T > 0.06:
				var c: Color = HEAT_RAMP[mini(HEAT_RAMP.size() - 1, int((1 - minf(1, T)) * (HEAT_RAMP.size() - 1)))]
				buf.put(x, y, c)
				if (x & 3) == 0:
					light.glow(x + 0.5, y, 6, c, 0.18 * T)
			elif d < 0.95 - kh * 0.3 or Sf.bayer(x, y) < 1 - d:
				buf.put(x, y, SOOT if d < 0.5 else SOOT2)

func draw_parts(buf: Sf.Px, light: Sf.Px, back: bool) -> void:
	for p in list:
		if p.delay > 0 or (p.k == SMOKE or p.k == DUST) != back:
			continue
		var k := p.life / p.mx
		var ax := p.x / Sf.PX
		var ay := p.y / Sf.PX
		match p.k:
			SMOKE:
				var age := 1 - k
				var r := p.size * (0.65 + minf(1, age * 2.5) * 0.45 + age * 0.4)
				var a := minf(1, age * 12) * minf(1, k * 2.4) * 0.58
				var c := Sf.mix(p.col, Sf.ramp(SMOKE_RAMP, age), age) if p.col.a > 0 else Sf.ramp(SMOKE_RAMP, age * 1.05)
				buf.alpha_disc(ax, ay, r, c, a * 0.45)
				buf.alpha_disc(ax + r * 0.05, ay + r * 0.06, r * 0.74, c, a * 0.62)
			DUST:
				buf.alpha_disc(ax, ay, p.size * (0.6 + (1 - k) * 0.9), p.col, pow(k, 1.3) * 0.7)
			_:
				var C: Array = PL if p.k == PLASMA else SPARKS
				var hot: Color = (C[0] if k > 0.5 else (C[1] if k > 0.25 else C[2])) if p.k == PLASMA else (C[0] if k > 0.6 else (C[1] if k > 0.3 else C[2]))
				var sp := maxf(0.001, Vector2(p.vx, p.vy).length())
				var ux := p.vx / sp
				var uy := p.vy / sp
				var ln := minf(9, 1 + sp * 0.011)
				buf.line(ax - ux * ln, ay - uy * ln, ax - ux * ln * 0.4, ay - uy * ln * 0.4, hot if k > 0.5 else C[C.size() - 1])
				buf.line(ax - ux * ln * 0.45, ay - uy * ln * 0.45, ax, ay, hot)
				light.glow(ax, ay, 3, hot, 0.45 * k)

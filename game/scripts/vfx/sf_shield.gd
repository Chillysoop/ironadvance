class_name SfShield
extends RefCounted
## V8, Sprite Fusion shield.ts: a hex-panel dome that builds from the ground up over a unit,
## shimmers with a sweep and a bright rim, ripples and throws sparks where shots hit it, and
## falls apart panel by panel when it drops. The far half is drawn behind the unit.

const STAR := 0
const MOTE := 1
const GLINT := 2
const SPARK := 3
const S3 := 1.7320508
const GRID := 6.2
const WHITE := Color("ffffff")
const HOT := Color("fff3a6")
const YELLOW := Color("ffe26b")
const ORANGE := Color("ff8a2a")
const DEEP := Color("f2561d")
const ICE := ["ffffff", "dcfbff", "a6ecff", "62c8f4", "3a8bd8", "2c58aa", "212f6b", "151a3d"]
const VHARR := ["ffffff", "eeffd8", "c8f79e", "9df25c", "5cbf3a", "2f8a2a", "1d5a22", "10301a"]

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
var ground: Callable
var feet: Callable  # -> Vector2 world
var RAD := 40.0
var C: Array = []
var SPARKS_C: Array = []
var GONE := 1e9
var t := 0.0
var pt := 0.0
var hits: Array = []    # [t, lon, lat, done]
var list: Array[Part] = []
var lights: Array = []  # [x, y, r, color, k, life, max]
var cells: Array = []   # [far, near] dome pixels: [dx, dy, lon, lat, appear, gone delay, edge, rim]

func _init(feet_fn: Callable, radius: float, ground_fn: Callable, palette: Array = ICE, hold := 1e9) -> void:
	feet = feet_fn
	RAD = radius
	ground = ground_fn
	GONE = hold
	for h in palette:
		C.append(Color(h))
	SPARKS_C = [WHITE, C[1], C[2]]

func centre() -> Vector2:
	return feet.call() / Sf.PX

func surf(lon: float, lat: float) -> Vector2:
	var c := centre()
	return Vector2(c.x + RAD * sin(lon) * cos(lat), c.y - RAD * sin(lat))

func cell(gx: float, gy: float) -> Array:
	var q := (S3 / 3) * gx - gy / 3
	var r := (2.0 / 3) * gy
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	var hx := S3 * (rq + rr / 2)
	var hy := 1.5 * rr
	var dx := absf(gx - hx)
	var dy := gy - hy
	var id := (int(rq) * 73856093) ^ (int(rr) * 19349663)
	return [id, maxf(dx, maxf(absf(dx / 2 + dy * S3 / 2), absf(dx / 2 - dy * S3 / 2))) / (S3 / 2)]

func ripple(lon: float, lat: float) -> float:
	var hit := 0.0
	for hh in hits:
		var k: float = t - hh[0]
		if k < 0 or k > 0.7 or not hh[3]:
			continue
		var d := acos(clampf(cos(lat) * cos(hh[2]) * cos(lon - hh[1]) + sin(lat) * sin(hh[2]), -1, 1))
		var front := k * 3.2
		if absf(d - front) < 0.22:
			hit = maxf(hit, 1 - k / 0.7)
		elif d < front and d < 0.5:
			hit = maxf(hit, 0.4 * (1 - k / 0.7))
	return hit

func hit(x: float, y: float) -> void:
	## A shot stopped at world x, y.
	var c := centre()
	var lat := asin(clampf((c.y - y / Sf.PX) / RAD, 0, 1))
	hits.append([t, asin(clampf((x / Sf.PX - c.x) / RAD / maxf(0.05, cos(lat)), -1, 1)), lat, false])

func drop() -> void:
	GONE = minf(GONE, t)

func stop() -> void:
	drop()

func done() -> bool:
	return t > GONE + 0.6 and list.is_empty()

func spawn(k: int, x: float, y: float, vx: float, vy: float, life: float, col: Color, size := 1.0) -> void:
	var p := Part.new()
	p.k = k; p.x = x; p.y = y; p.vx = vx; p.vy = vy; p.life = life; p.mx = life
	p.col = col; p.size = size; p.seed = R.next() * 100
	list.append(p)

func update(dt: float) -> void:
	t += dt
	pt += dt
	if t < 0.75:
		for i in 3:
			var p := surf(R.rnd(-PI / 2, PI / 2), minf(t / 0.65 * PI / 2, 1.5))
			spawn(STAR, p.x * Sf.PX, p.y * Sf.PX, R.rnd(-20, 20), R.rnd(-30, 10), R.rnd(0.2, 0.4), R.pick(SPARKS_C), R.rnd(0.6, 1.2))
	for h in hits:
		if t >= h[0] and not h[3]:
			h[3] = true
			var p := surf(h[1], h[2])
			lights.append([p.x * Sf.PX, p.y * Sf.PX, 80.0, C[2], 0.9, 0.18, 0.18])
			spawn(GLINT, p.x * Sf.PX, p.y * Sf.PX, 0, 0, 0.05, WHITE, 1.8)
			for j in 14:
				var a := R.rnd(-1, 1) + (-0.6 if h[2] > 0.9 else 0.0)
				var sp := R.rnd(200, 600)
				spawn(SPARK, p.x * Sf.PX, p.y * Sf.PX, cos(a) * sp * (1 if p.x > centre().x else -1), sin(a) * sp - 80, R.rnd(0.1, 0.35), WHITE)
	if t > GONE - 0.05 and t < GONE + 0.6:
		for i in 4:
			var p := surf(R.rnd(-1.4, 1.4), R.rnd(0, 1.4))
			spawn(STAR if R.chance(0.5) else MOTE, p.x * Sf.PX, p.y * Sf.PX, R.rnd(-30, 30), -R.rnd(20, 80), R.rnd(0.3, 0.7), R.pick(SPARKS_C), R.rnd(0.6, 1.4))
	for i in range(list.size() - 1, -1, -1):
		var p := list[i]
		p.life -= dt
		if p.life <= 0:
			list.remove_at(i)
			continue
		match p.k:
			STAR:
				p.vx -= p.vx * 1.6 * dt
				p.vy -= p.vy * 1.6 * dt + 10 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
			MOTE:
				p.vx -= p.vx * 0.6 * dt
				p.vy -= p.vy * 0.6 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
			SPARK:
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
	for i in range(lights.size() - 1, -1, -1):
		lights[i][5] -= dt
		if lights[i][5] <= 0:
			lights.remove_at(i)

func build() -> void:
	## Everything about a dome pixel that doesn't change with time (where it sits on the sphere,
	## its hex panel, how near the rim), once, so a dome that stays up for turns stays cheap.
	for far in [true, false]:
		var out: Array = []
		for y in range(-ceili(RAD) - 1, 1):
			for x in range(-ceili(RAD) - 1, ceili(RAD) + 2):
				var u := (x + 0.5) / RAD
				var v := (-y - 0.5) / RAD
				var q := u * u + v * v
				if q > 1 or v < 0:
					continue
				var z := sqrt(1 - q) * (-1.0 if far else 1.0)
				var lon := atan2(u, z)
				var lat := asin(clampf(v, 0, 1))
				var ce := cell(lon * GRID, lat * GRID * 1.15)
				var id: int = ce[0]
				var h := Sf.hsh(id & 0xffff, (id >> 16) & 0xffff)
				out.append([x, y, lon, lat, 0.05 + (lat / (PI / 2)) * 0.6 + h * 0.08, h * 0.55, ce[1], 1 - absf(z)])
		cells.append(out)

func dome(buf: Sf.Px, light: Sf.Px, far: bool) -> void:
	var c := centre()
	var cx := roundi(c.x)
	var cy := roundi(c.y)
	if cells.is_empty():
		build()
	var any_hit := false
	for hh in hits:
		if t - hh[0] <= 0.7 and hh[3]:
			any_hit = true
	for pc in cells[0 if far else 1]:
		var appear: float = pc[4]
		var gone: float = GONE + pc[5]
		if t < appear or t > gone:
			continue
		var x: int = cx + pc[0]
		var y: int = cy + pc[1]
		var e: float = pc[6]
		if far:
			if e > 0.82 and Sf.bayer(x, y) < 0.5:
				buf.put(x, y, C[4])
			continue
		var lon: float = pc[2]
		var lat: float = pc[3]
		var rim: float = pc[7]
		var age := t - appear
		var end := gone - t
		var hit_k := ripple(lon, lat) if any_hit else 0.0
		var flash := age < 0.1 or end < 0.08
		var sweep := absf(fposmod(lon * 0.35 + lat * 0.45 - t * 0.55, 1.0) - 0.5) < 0.04
		if e > 0.8:
			var col: Color = WHITE if flash or hit_k > 0.6 else (C[1] if hit_k > 0.2 or sweep or rim > 0.75 else (C[2] if rim > 0.4 else C[3]))
			if flash or hit_k > 0.2 or sweep or 0.5 + rim > Sf.bayer(x, y):
				buf.put(x, y, col)
		else:
			var a := (0.7 if flash else 0.08 + 0.3 * rim * rim) + hit_k * 0.6
			if a > Sf.bayer(x, y):
				buf.put(x, y, C[1] if flash or hit_k > 0.5 else (C[3] if rim > 0.7 else C[4]))
		if ((x * 7 + y * 3) & 31) == 0:
			light.glow(x, y, 7, C[3], 0.15 + 0.4 * hit_k)
	if far:
		return
	var a := Sf.smooth(0, 0.15, t) * (1 - Sf.smooth(GONE - 0.05, GONE + 0.45, t))
	if a > 0:
		buf.ellipse_ring(cx, cy, RAD, 3.0 / RAD, 1, C[2], a, true)
	light.glow(cx, cy - RAD * 0.5, RAD * 1.3, C[3], 0.22 * a)

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		dome(buf, light, true)
		return
	dome(buf, light, false)
	for p in list:
		draw_one(buf, light, p)
	for l in lights:
		var k: float = l[5] / l[6]
		light.glow(l[0] / Sf.PX, l[1] / Sf.PX, (l[2] / Sf.PX) * (0.55 + 0.45 * k), l[3], l[4] * k * k)

func draw_one(buf: Sf.Px, light: Sf.Px, p: Part) -> void:
	var k := p.life / p.mx
	var ax := p.x / Sf.PX
	var ay := p.y / Sf.PX
	var px := floori(ax)
	var py := floori(ay)
	match p.k:
		STAR:
			var tw := 0.6 + 0.4 * sin(pt * (8 + fmod(p.seed, 5)) + p.seed)
			if p.size < 1:
				if tw * k > 0.25:
					buf.put(px, py, WHITE if tw > 0.8 else p.col)
				light.glow(ax, ay, 3, p.col, 0.4 * k * tw)
				return
			var arm := maxi(1, roundi(p.size * tw * minf(1, k * 3)))
			var tipc := Sf.scale(p.col, 0.75)
			for d in range(1, arm + 1):
				var cc := tipc if d == arm and arm > 1 else p.col
				buf.put(px + d, py, cc)
				buf.put(px - d, py, cc)
				buf.put(px, py + d, cc)
				buf.put(px, py - d, cc)
			buf.put(px, py, WHITE)
			light.glow(ax, ay, 3 + arm * 2, p.col, 0.5 * k * tw)
		MOTE:
			var sp := maxf(0.001, Vector2(p.vx, p.vy).length())
			var ux := p.vx / sp
			var uy := p.vy / sp
			var ln := minf(16, 0.5 + sp * 0.013) * p.size
			if k < 0.35 and Sf.bayer(px, py) > k / 0.35:
				return
			buf.line(ax - ux * ln, ay - uy * ln, ax - ux * ln * 0.35, ay - uy * ln * 0.35, Sf.scale(p.col, 0.55))
			buf.line(ax - ux * ln * 0.4, ay - uy * ln * 0.4, ax, ay, p.col)
			light.glow(ax, ay, 2.5 + p.size, p.col, 0.4 * k)
		GLINT:
			var r := p.size * (0.5 + k * 0.5)
			buf.disc(ax, ay, r + 0.8, DEEP)
			buf.disc(ax, ay, r, HOT)
			light.glow(ax, ay, p.size * 4, p.col, 0.6 * k)
		SPARK:
			var hot := HOT if k > 0.6 else (YELLOW if k > 0.3 else ORANGE)
			var sp := maxf(0.001, Vector2(p.vx, p.vy).length())
			var ux := p.vx / sp
			var uy := p.vy / sp
			var ln := minf(9, 1 + sp * 0.011)
			buf.line(ax - ux * ln, ay - uy * ln, ax - ux * ln * 0.4, ay - uy * ln * 0.4, hot if k > 0.5 else DEEP)
			buf.line(ax - ux * ln * 0.45, ay - uy * ln * 0.45, ax, ay, hot)
			light.glow(ax, ay, 3, hot, 0.45 * k)

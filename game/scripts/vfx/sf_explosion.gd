class_name SfExplosion
extends RefCounted
## V1, Sprite Fusion explosion.ts: a white flash and fireball, shock rings, sparks, embers and
## burning brands that light small fires where they land, rolling smoke, rocks and grit thrown
## out of the ground in its colour, a glowing scorch mark and a ring running along the floor.
## World units in, art pixels out (Sf.PX).

const SPARK := 0
const EMBER := 1
const SMOKE := 2
const FIRE := 3
const BRAND := 4
const DUST := 5
const GRIT := 6
const SMOKES := 1
const BIG := 2
const BACK := 4

const WHITE := Color("ffffff")
const OUTLINE := Color("1a1422")
const SOOT := Color("0d0a12")
const SOOT2 := Color("17121d")
const WARM := Color8(255, 176, 96)
const HOT := Color("fff3a6")
const YELLOW := Color("ffe26b")
const GOLD := Color("ffc23d")
const ORANGE := Color("ff8a2a")
const DEEP := Color("f2561d")
const RED := Color("c9281f")
const FIRE_RAMP := [WHITE, HOT, YELLOW, GOLD, ORANGE, DEEP, RED, Color("8a1f17"), Color("4a1712")]
const HEAT_RAMP := [WHITE, HOT, YELLOW, GOLD, ORANGE, DEEP, RED, Color("8a1f17"), Color("4f1a13"), Color("2a120e")]
const SMOKE_RAMP := [Color("7b6f72"), Color("5d5660"), Color("433d48"), Color("2b2630"), Color("1a171e")]

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
	var flag := 0

class Rock:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var life := 0.0
	var a := 0.0
	var va := 0.0
	var s := 1.0
	var rest := false

var R := Sf.Rng.new()
var ground: Callable
var list: Array[Part] = []
var rocks: Array[Rock] = []
var flashes: Array = []  # [x, y, r, life, max]
var rings: Array = []    # [x, y, r0, r1, life, max, thick, color]
var lights: Array = []   # [x, y, r, color, k, life, max]
var blazes: Array = []   # [x, y, life, max, acc, power]
var pt := 0.0            # particle clock
var t := 0.0
var gx := 0.0
var gy := 0.0
var scorch_r := 22.0
var cool := 1.0
var ring_r := 80.0
var thick := 2.0
var st := {}
var ring_cols: Array = []

func _init(x: float, y: float, size: float, ground_fn: Callable, surface := Color("4a3f69"), fire := 0.3, earth := 1.6) -> void:
	ground = ground_fn
	var S := size
	var RAD := 36.0 * S
	var POWER := 0.9 * pow(S, 0.8)
	ring_r = 80.0 * S
	scorch_r = 22.0 * S
	var G: float = ground.call(x)
	if G > y + RAD * 2:
		G = y  # nothing under it (mid-air): the ground effects sit at the blast
	st = stone(surface)
	gx = x / Sf.PX
	gy = G / Sf.PX
	cool = 1.2 + RAD / 28.0
	thick = 2.0 + RAD / 18.0
	ring_cols = [WHITE, HOT, ORANGE, st.light, st.body]
	explosion(x, minf(y, G - RAD * 0.3), RAD, POWER, fire)
	for i in roundi(RAD * 0.5):
		var s := R.sgn()
		spawn(SMOKE, x + s * R.rnd(0, RAD * 0.6), G - R.rnd(2, 10 + RAD * 0.08), s * R.rnd(3, 9.5) * RAD, -R.rnd(4, 30), R.rnd(1.1, 2.2) + RAD / 80.0, st.dust, R.rnd(4, 7) + RAD / 12.0, R.rnd(0, 0.06), BIG)
	for i in int(26 * minf(1.5, S)):
		var b := Rock.new()
		b.x = x + R.rnd(-0.4, 0.4) * RAD
		b.y = G - 6
		b.vx = R.rnd(-9, 9) * RAD * 0.4
		b.vy = -R.rnd(7, 16) * RAD * 1.5
		b.life = R.rnd(1.8, 2.6) + RAD / 60.0
		b.a = R.rnd(0, TAU)
		b.va = R.rnd(-16, 16)
		b.s = R.ri(1, 3)
		rocks.append(b)
	for i in roundi(earth * RAD * 2.6):
		var u := R.rnd(-1, 1)
		var a := -PI / 2 + u * 0.5
		var sp := R.rnd(6, 19) * RAD * (1 - 0.45 * absf(u))
		spawn(GRIT, x + u * 0.25 * RAD, G - 2, cos(a) * sp, sin(a) * sp, R.rnd(1.2, 2.2), R.pick([st.light, st.body, st.body, st.shade]), 2 if R.chance(0.45) else 1)
	for i in roundi(earth * 12):
		spawn(SMOKE, x + R.rnd(-0.3, 0.3) * RAD, G - R.rnd(4, RAD * 0.6), R.rnd(-30, 30), -R.rnd(120, 380) * sqrt(S) * earth * 0.6, R.rnd(1.6, 2.8), st.dust, R.rnd(5, 9) * sqrt(S) + RAD / 14.0, R.rnd(0, 0.15), BIG)

static func stone(c: Color) -> Dictionary:
	return {"light": Sf.mix(Sf.scale(c, 1.35), WHITE, 0.08), "body": c, "shade": Sf.scale(c, 0.64), "dust": Sf.mix(Sf.scale(c, 1.2), Color8(150, 140, 150), 0.3)}

func spawn(k: int, x: float, y: float, vx: float, vy: float, life: float, col := Color(0, 0, 0, 0), size := 1.0, delay := 0.0, flag := 0) -> void:
	var p := Part.new()
	p.k = k; p.x = x; p.y = y; p.vx = vx; p.vy = vy; p.life = life; p.mx = life
	p.col = col; p.size = size; p.seed = R.next() * 100; p.delay = delay; p.flag = flag
	list.append(p)

func done() -> bool:
	return t > 1.0 and list.is_empty() and rocks.is_empty() and flashes.is_empty() and rings.is_empty() and lights.is_empty() and blazes.is_empty()

# ---------------------------------------------------------------- simulation
func update(dt: float) -> void:
	t += dt
	step_rocks(dt)
	update_fx(dt)
	update_parts(dt)

func step_rocks(dt: float) -> void:
	for i in range(rocks.size() - 1, -1, -1):
		var b := rocks[i]
		b.life -= dt
		if b.life <= 0:
			rocks.remove_at(i)
			continue
		if b.rest:
			continue
		b.vy += Sf.GRAVITY * dt
		b.vx -= b.vx * 0.25 * dt
		b.vy -= b.vy * 0.25 * dt
		b.x += b.vx * dt
		b.y += b.vy * dt
		b.a += b.va * dt
		var floor_y: float = ground.call(b.x)
		if b.y >= floor_y and b.vy > 0:
			var sp := b.vy
			b.y = floor_y - 0.01
			if sp > 200:
				dust(b.x, b.y, 3, 0.6, st.body)
			if sp > 140:
				b.vy = -sp * 0.32
				b.vx *= 0.7
				b.va *= 0.6
			else:
				b.rest = true
				b.vx = 0
				b.vy = 0

func update_fx(dt: float) -> void:
	for arr in [flashes, rings, lights]:
		var li: int = 3 if arr == flashes else (4 if arr == rings else 5)
		for i in range(arr.size() - 1, -1, -1):
			arr[i][li] -= dt
			if arr[i][li] <= 0:
				arr.remove_at(i)
	for i in range(blazes.size() - 1, -1, -1):
		var b: Array = blazes[i]
		b[2] -= dt
		if b[2] <= 0:
			blazes.remove_at(i)
			continue
		var k: float = b[2] / b[3]
		var intensity: float = b[5] * (1.0 if k > 0.7 else 0.35 + (k / 0.7) * 0.65)
		b[4] += dt * (6 + 16 * intensity)
		while b[4] > 1:
			b[4] -= 1
			var s := R.rnd(1.2, 2.8) * intensity
			spawn(FIRE, b[0] + R.rnd(-3, 3), b[1] - s * 0.6, R.rnd(-12, 12), R.rnd(-60, -25), R.rnd(0.28, 0.6), Color(0, 0, 0, 0), s, 0, BACK | (SMOKES if R.chance(0.3) else 0))
			if R.chance(0.06):
				spawn(EMBER, b[0], b[1] - 3, R.rnd(-30, 30), R.rnd(-90, -30), R.rnd(0.6, 1.4), ORANGE, 1, 0, BACK)

func update_parts(dt: float) -> void:
	pt += dt
	for i in range(list.size() - 1, -1, -1):
		var p := list[i]
		if p.delay > 0:
			p.delay -= dt
			continue
		p.life -= dt
		if p.life <= 0:
			if p.k == FIRE and p.flag & SMOKES:
				var big := p.flag & BIG
				spawn(SMOKE, p.x, p.y, p.vx * 0.6, p.vy * 0.6 - 12, R.rnd(1.3, 2.3) if big else R.rnd(0.8, 1.4), Color(0, 0, 0, 0), p.size * (0.85 if big else 0.7), 0, BIG if big else 0)
			list.remove_at(i)
			continue
		match p.k:
			SPARK:
				var g: float = ground.call(p.x)
				p.vy += Sf.GRAVITY * 0.45 * dt
				p.vx -= p.vx * 2.2 * dt
				p.vy -= p.vy * 2.2 * dt
				var ny := p.y + p.vy * dt
				p.x += p.vx * dt
				if p.vy > 0 and p.y <= g and ny >= g:
					p.vy = -p.vy * 0.45
					p.vx *= 0.7
					p.y = g - 0.5
				else:
					p.y = ny
			EMBER:
				p.vy += (-60 + sin(pt * 3 + p.seed) * 40) * dt
				p.vx += cos(pt * 2.3 + p.seed) * 90 * dt
				p.vx -= p.vx * 1.6 * dt
				p.vy -= p.vy * 1.6 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
			SMOKE:
				p.vy -= (46.0 if p.flag & BIG else 32.0) * dt
				p.vx += sin(pt * 1.3 + p.seed) * 16 * dt
				p.vx -= p.vx * 1.6 * dt
				p.vy -= p.vy * 1.2 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
			FIRE:
				p.vy -= 190 * dt
				p.vx += sin(pt * 17 + p.seed) * 60 * dt
				p.vx -= p.vx * 5 * dt
				p.vy -= p.vy * 3.2 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
			DUST:
				p.vx -= p.vx * 4 * dt
				p.vy -= p.vy * 4 * dt + 10 * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
			GRIT:
				var g: float = ground.call(p.x)
				p.vy += Sf.GRAVITY * dt
				p.vx -= p.vx * 0.8 * dt
				var ny := p.y + p.vy * dt
				p.x += p.vx * dt
				if p.vy > 0 and p.y <= g and ny >= g:
					p.y = g - 0.5
					if p.vy > 260 and R.chance(0.4):
						p.vy = -p.vy * 0.25
						p.vx = p.vx * 0.5 + R.rnd(-20, 20)
					else:
						p.vx = 0
						p.vy = 0
						p.life = minf(p.life, 0.5)
				else:
					p.y = ny
			BRAND:
				var g: float = ground.call(p.x)
				p.vy += Sf.GRAVITY * 0.8 * dt
				p.vx -= p.vx * 0.9 * dt
				if R.chance(0.9):
					spawn(FIRE, p.x, p.y, p.vx * 0.1 + R.rnd(-15, 15), p.vy * 0.1 - 20, R.rnd(0.16, 0.32), Color(0, 0, 0, 0), R.rnd(0.9, 1.7) * (0.5 + (p.life / p.mx) * 0.6), 0, SMOKES if R.chance(0.4) else 0)
				var ny := p.y + p.vy * dt
				p.x += p.vx * dt
				if p.vy > 0 and p.y <= g and ny >= g:
					blazes.append([p.x, g - 0.5, 0.0, 0.0, R.next(), R.rnd(0.55, 0.85)])
					var bl: Array = blazes[-1]
					bl[2] = R.rnd(2.2, 4.5)
					bl[3] = bl[2]
					list.remove_at(i)
				else:
					p.y = ny

# ---------------------------------------------------------------- drawing
func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	if layer == 0:
		scorch(buf, light)
		draw_parts(buf, light, true)
		for b in blazes:
			var k: float = b[2] / b[3]
			var ax: float = b[0] / Sf.PX
			var ay: float = b[1] / Sf.PX
			buf.put(floori(ax), floori(ay), (YELLOW if sin(b[2] * 31 + b[0]) > 0 else ORANGE) if k > 0.4 else RED)
			light.glow(ax, ay, 6 + 5 * k * b[5], ORANGE, 0.3 * k * b[5])
		floor_ring(buf, true)
	else:
		floor_ring(buf, false)
		for r in rocks:
			rock(buf, r)
		draw_parts(buf, light, false)
		for f in flashes:
			var k: float = f[3] / f[4]
			var ax: float = f[0] / Sf.PX
			var ay: float = f[1] / Sf.PX
			var r: float = f[2] * (0.8 + 0.2 * k)
			buf.disc(ax, ay, r + 1.2, DEEP)
			buf.disc(ax, ay, r, HOT if k > 0.45 else YELLOW)
			buf.disc(ax, ay, r * 0.6, WHITE if k > 0.45 else HOT)
		for r in rings:
			var k: float = r[4] / r[5]
			var e := 1.0 - pow(k, 3)
			buf.ring(r[0] / Sf.PX, r[1] / Sf.PX, (r[2] + (r[3] - r[2]) * e) / Sf.PX, maxf(1, r[6] * k + 0.4), r[7], minf(1, k * 1.6))
		for l in lights:
			var k: float = l[5] / l[6]
			light.glow(l[0] / Sf.PX, l[1] / Sf.PX, (l[2] / Sf.PX) * (0.55 + 0.45 * k), l[3], l[4] * k * k)

func scorch(buf: Sf.Px, light: Sf.Px) -> void:
	var rx := scorch_r * minf(1, t / 0.08)
	var ry := 4.0
	if rx < 0.5:
		return
	for y in range(floori(gy), floori(gy + 2) + 1):
		for x in range(floori(gx - rx), ceili(gx + rx) + 1):
			var dx := (x + 0.5 - gx) / rx
			var dy := (y + 0.5 - gy) / ry
			var d := sqrt(dx * dx + dy * dy)
			if d > 1:
				continue
			var kh := Sf.hsh(x * 31 + y)
			var T := pow(clampf(1 - t / cool, 0, 1), 1.4) * (1.25 - d) - kh * 0.35
			if T > 0.06:
				var c: Color = HEAT_RAMP[mini(HEAT_RAMP.size() - 1, int((1 - minf(1, T)) * (HEAT_RAMP.size() - 1)))]
				buf.put(x, y, c)
				if (x & 3) == 0:
					light.glow(x + 0.5, y, 6, c, 0.18 * T)
			elif d < 0.95 - kh * 0.3 or Sf.bayer(x, y) < 1 - d:
				buf.put(x, y, SOOT if d < 0.5 else SOOT2)

func floor_ring(buf: Sf.Px, back: bool) -> void:
	var k := t / 0.5
	if k >= 1 or k < 0:
		return
	var r := ring_r * Sf.out_cubic(k)
	var col: Color = ring_cols[mini(ring_cols.size() - 1, int(k * ring_cols.size()))]
	buf.ellipse_ring(gx, gy + 0.5, r, 0.16, maxf(1, thick * (1 - k)), col, 1.15 - k, not back)

func rock(buf: Sf.Px, b: Rock) -> void:
	var x := b.x / Sf.PX
	var y := b.y / Sf.PX
	var r := 0.6 + b.s * 0.75
	var fade := minf(1, b.life / 0.5)
	var lx := cos(b.a) * r * 0.4
	var ly := sin(b.a) * r * 0.4
	for py in range(floori(y - r - 1), ceili(y + r + 1) + 1):
		for px in range(floori(x - r - 1), ceili(x + r + 1) + 1):
			var dx := px + 0.5 - x
			var dy := py + 0.5 - y
			var d := Vector2(dx * 1.15, dy).length()
			if d > r + 0.9 or (fade < 1 and fade <= Sf.bayer(px, py)):
				continue
			var lit := dx * lx + dy * ly
			buf.put(px, py, OUTLINE if d > r else (st.light if lit < -0.4 else (st.shade if lit > 0.6 else st.body)))

func draw_parts(buf: Sf.Px, light: Sf.Px, back: bool) -> void:
	if back:
		for p in list:
			if p.delay <= 0 and (p.k == SMOKE or p.k == DUST):
				draw_one(p, buf, light)
	for p in list:
		if p.delay <= 0 and p.k != SMOKE and p.k != DUST and ((p.flag & BACK) != 0) == back:
			draw_one(p, buf, light)

func draw_one(p: Part, buf: Sf.Px, light: Sf.Px) -> void:
	var k := p.life / p.mx
	var ax := p.x / Sf.PX
	var ay := p.y / Sf.PX
	var px := floori(ax)
	var py := floori(ay)
	match p.k:
		SMOKE:
			var age := 1 - k
			var big := p.flag & BIG
			var r := p.size * (0.65 + minf(1, age * 2.5) * 0.45 + age * (0.5 if big else 0.4))
			var a := minf(1, age * 12) * minf(1, k * 2.4) * (0.7 if big else 0.58)
			var c := Sf.mix(p.col, Sf.ramp(SMOKE_RAMP, age), age) if p.col.a > 0 else Sf.ramp(SMOKE_RAMP, age * 1.05)
			buf.alpha_disc(ax, ay, r, c, a * 0.45)
			buf.alpha_disc(ax + r * 0.05, ay + r * 0.06, r * 0.74, c, a * 0.62)
			if age < 0.5:
				buf.alpha_disc(ax - r * 0.22, ay - r * 0.3, r * 0.5, Sf.mix(c, WHITE, 0.12), a * 0.4 * (1 - age * 2))
		DUST:
			buf.alpha_disc(ax, ay, p.size * (0.6 + (1 - k) * 0.9), p.col, pow(k, 1.3) * 0.7)
		GRIT:
			if k > 0.25 or Sf.bayer(px, py) < k * 4:
				buf.put(px, py, p.col)
				if p.size >= 2:
					buf.put(px + 1, py, p.col)
					buf.put(px, py + 1, Sf.scale(p.col, 0.8))
					buf.put(px + 1, py + 1, Sf.scale(p.col, 0.7))
		FIRE:
			var age := 1 - k
			var heat := minf(0.999, pow(age, 0.62) + fmod(p.seed, 1.0) * 0.1)
			var n := FIRE_RAMP.size()
			var idx := mini(n - 2, int(heat * (n - 1)))
			var r := p.size * (0.55 + 0.45 * minf(1, age * 7)) * (1 - age * 0.55)
			var c: Color = FIRE_RAMP[idx]
			if idx >= n - 2:
				buf.alpha_disc(ax, ay, r, c, minf(1, k * 3) * 0.85)
			else:
				buf.disc(ax, ay, r, FIRE_RAMP[mini(n - 1, idx + 2)])
				buf.disc(ax - r * 0.16, ay - r * 0.22, r * 0.78, c)
				if r > 1.6:
					buf.disc(ax, ay - r * 0.9, r * 0.42, c)
				if idx <= 3 and r > 1.8:
					buf.disc(ax - r * 0.28, ay - r * 0.34, r * 0.36, FIRE_RAMP[maxi(0, idx - 1)])
				if idx < 6:
					light.glow(ax, ay, r * 2.4 + 2, c, 0.18 * k)
		BRAND:
			buf.disc(ax, ay, 1.6, DEEP)
			buf.put(px, py, HOT if sin(pt * 40 + p.seed) > 0 else YELLOW)
			buf.put(px + 1, py, YELLOW)
			light.glow(ax, ay, 7, ORANGE, 0.45)
		SPARK:
			var hot := HOT if k > 0.6 else (YELLOW if k > 0.3 else ORANGE)
			var sp := maxf(0.001, Vector2(p.vx, p.vy).length())
			var ux := p.vx / sp
			var uy := p.vy / sp
			var ln := minf(9, 1 + sp * 0.011)
			buf.line(ax - ux * ln, ay - uy * ln, ax - ux * ln * 0.4, ay - uy * ln * 0.4, hot if k > 0.5 else DEEP)
			buf.line(ax - ux * ln * 0.45, ay - uy * ln * 0.45, ax, ay, hot)
			light.glow(ax, ay, 3, hot, 0.45 * k)
		EMBER:
			var c := ((YELLOW if sin(pt * 22 + p.seed * 3) > -0.2 else ORANGE) if k > 0.5 else (ORANGE if k > 0.2 else RED))
			buf.put(px, py, c)
			light.glow(ax, ay, 3, c, 0.3 * k)

# ---------------------------------------------------------------- the blast itself
func explosion(x: float, y: float, rad: float, power: float, fire: float) -> void:
	var ar := rad / Sf.PX
	flashes.append([x, y, ar * 1.05, 0.06, 0.06])
	rings.append([x, y, rad * 0.45, rad * 2.7, 0.34, 0.34, 3.0, YELLOW])
	rings.append([x, y, rad * 0.3, rad * 1.6, 0.22, 0.22, 1.8, ORANGE])
	lights.append([x, y, rad * 3.4, WARM, 0.6 * power, 0.7, 0.7])
	lights.append([x, y, rad * 1.6, WHITE, 0.6, 0.08, 0.08])
	for i in 5:
		spawn(FIRE, x + R.rnd(-5, 5), y + R.rnd(-5, 5), R.rnd(-40, 40), R.rnd(-80, -20), R.rnd(0.18, 0.3), Color(0, 0, 0, 0), R.rnd(ar * 0.4, ar * 0.55))
	for i in roundi(28 * power * fire):
		var a := R.rnd(0, TAU)
		var d := R.rnd(0, rad * 0.55)
		var sp := R.rnd(80, 420) * power
		spawn(FIRE, x + cos(a) * d, y + sin(a) * d, cos(a) * sp, sin(a) * sp * 0.8 - 80, R.rnd(0.55, 1.15), Color(0, 0, 0, 0), R.rnd(ar * 0.22, ar * 0.46), 0, (SMOKES | BIG) if R.chance(0.45) else 0)
	for i in 5:
		var a := R.rnd(0, TAU)
		var d := R.rnd(rad * 0.1, rad * 0.5)
		spawn(SMOKE, x + cos(a) * d, y + sin(a) * d, cos(a) * 60, sin(a) * 40 - 60, R.rnd(0.9, 1.5), Color8(34, 29, 38), R.rnd(ar * 0.15, ar * 0.26), R.rnd(0.06, 0.2), BIG)
	for i in roundi(5 * fire):
		spawn(FIRE, x + R.rnd(-rad * 0.25, rad * 0.25), y, R.rnd(-25, 25), R.rnd(-360, -200), R.rnd(0.8, 1.3), Color(0, 0, 0, 0), R.rnd(ar * 0.24, ar * 0.36), R.rnd(0, 0.1), (SMOKES | BIG) if R.chance(0.6) else 0)
	for i in roundi(10 * power):
		var a := R.rnd(0, TAU)
		var d := R.rnd(0, rad * 0.7)
		var sp := R.rnd(30, 200)
		spawn(SMOKE, x + cos(a) * d, y + sin(a) * d, cos(a) * sp, sin(a) * sp * 0.6 - 70, R.rnd(1.8, 3), Color(0, 0, 0, 0), R.rnd(ar * 0.26, ar * 0.44), R.rnd(0.12, 0.45), BIG)
	for i in roundi(80 * power):
		var a := R.rnd(0, TAU)
		var sp := R.rnd(320, 1200) * power
		spawn(SPARK, x, y, cos(a) * sp, sin(a) * sp - 140, R.rnd(0.18, 0.7))
	for i in roundi(40 * power * fire):
		var a := R.rnd(0, TAU)
		var sp := R.rnd(60, 360)
		spawn(EMBER, x + cos(a) * rad * 0.4, y + sin(a) * rad * 0.4, cos(a) * sp, sin(a) * sp - 150, R.rnd(1.2, 3.2), ORANGE)
	for i in roundi(R.rnd(9, 14) * maxf(0, power - 0.55) * fire):
		var a := -PI / 2 + R.rnd(-1.35, 1.35)
		var sp := R.rnd(380, 820)
		spawn(BRAND, x, y, cos(a) * sp, sin(a) * sp, R.rnd(0.7, 1.5))
	impulse(x, y, rad * 2.6, 720 * power)

func impulse(x: float, y: float, r: float, force: float) -> void:
	for p in list:
		if p.k == FIRE:
			continue
		var dx := p.x - x
		var dy := p.y - y
		var d := maxf(0.001, Vector2(dx, dy).length())
		if d > r:
			continue
		var f := force * (1 - d / r) * (0.35 if p.k == SMOKE or p.k == DUST else 1.0)
		p.vx += (dx / d) * f
		p.vy += (dy / d) * f - f * 0.3

func dust(x: float, y: float, n: int, spread: float, color: Color) -> void:
	var dc := Sf.mix(color, Color8(150, 140, 150), 0.35)
	for i in n:
		spawn(DUST, x + R.rnd(-3, 3), y - 1, R.sgn() * R.rnd(20, 110) * spread, -R.rnd(5, 45), R.rnd(0.3, 0.65), dc, R.rnd(1.3, 2.8))

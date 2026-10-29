class_name SfPickup
extends RefCounted
## V15, Sprite Fusion pickup.ts: the item hops up, arcs into the soldier's chest with a short
## trail and pops into a ring of star sparks that home back into them, each catch leaving a small
## ring and rising motes. Scrip is a spinning coin; anything else is a gem.

const LIFT := 0.1
const FLY := 0.34
const PALETTES := {
	"gem": ["ffffff", "e0faff", "7fe0ff", "2f9ee8", "1d4aa8", "101a3e"],
	"orb": ["ffffff", "e6ffe0", "8cff7a", "2fc95a", "157a46", "0b2e1f"],
	"coin": ["fffbe8", "ffec92", "ffd243", "f4a923", "a8601a", "3a1d0c"],
}
const SPRITES := {
	"gem": ["...ooooo...", "..ohwhlmo..", ".ohwhllmmo.", "olllllmmmdo", "odmmmmmmddo", ".odlmmmmdo.", "..odlmmdo..", "...odmdo...", "....odo....", ".....o....."],
	"orb": ["..ooooo..", ".ollllmo.", "olwhllmmo", "olhlllmmo", "ollllmmmo", "ommmmmmdo", "ommmmmddo", ".odmlddo.", "..ooooo.."],
	"coin": ["..ooooo..", ".ohllllo.", "ohlmmmmdo", "olmhlmmdo", "olmlmmmdo", "olmmmmmdo", "olddmmddo", ".odddddo.", "..ooooo.."],
}
const WHITE := Color("ffffff")

var R := Sf.Rng.new()
var kind := "gem"
var C: Array = []
var spr: Array = []   # rows of Color or null
var sw := 0
var sh := 0
var target: Callable  # -> Vector2 world
var t := 0.0
var pop_t := 1e9
var px := 0.0
var py := 0.0
var from := Vector2()
var trail: Array = []
var sparks: Array = []  # [x, y, vx, vy, life, max, s, c, tr]
var motes: Array = []
var rings: Array = []   # [x, y, t, r]
var absorbed := 0

func _init(x: float, y: float, item: String, target_fn: Callable) -> void:
	kind = item if PALETTES.has(item) else "gem"
	for h in PALETTES[kind]:
		C.append(Color(h))
	var pal := {"w": C[0], "h": C[1], "l": C[2], "m": C[3], "d": C[4], "o": C[5]}
	for row in SPRITES[kind]:
		var r: Array = []
		for ch in row:
			r.append(pal.get(ch))
		spr.append(r)
		sw = maxi(sw, row.length())
	sh = spr.size()
	target = target_fn
	px = x
	py = y
	from = Vector2(x, y)

func done() -> bool:
	return pop_t < 1e8 and t - pop_t > 0.5 and sparks.is_empty() and motes.is_empty()

func pop() -> void:
	pop_t = t
	rings.append([px, py, t, 20.0])
	var burst := [C[0], C[1], C[2]]
	for i in 14:
		var a := (i / 14.0) * TAU + R.rnd(-0.2, 0.2)
		var sp := R.rnd(150, 300)
		sparks.append([px, py, cos(a) * sp, sin(a) * sp - 40, R.rnd(0.75, 1.05), 1.05, 2 if R.chance(0.4) else 1, R.pick(burst), []])

func update(dt: float) -> void:
	t += dt
	var tg: Vector2 = target.call()
	if pop_t > 1e8:
		var k := t
		if k < LIFT:
			py = from.y - 8 * Sf.out_cubic(k / LIFT)
		else:
			var u := pow(clampf((k - LIFT) / FLY, 0, 1), 2.2)
			var sx := from.x
			var sy := from.y - 8
			var mx := (sx + tg.x) / 2
			var my := minf(sy, tg.y) - maxf(40, Vector2(tg.x - sx, tg.y - sy).length() * 0.35)
			px = (1 - u) * (1 - u) * sx + 2 * (1 - u) * u * mx + u * u * tg.x
			py = (1 - u) * (1 - u) * sy + 2 * (1 - u) * u * my + u * u * tg.y
			trail.push_front(Vector2(px, py))
			if trail.size() > 7:
				trail.pop_back()
			if u >= 1:
				pop()
	elif not trail.is_empty():
		trail.pop_back()
	for i in range(sparks.size() - 1, -1, -1):
		var s: Array = sparks[i]
		var age: float = s[5] - s[4]
		s[8].push_front(Vector2(s[0], s[1]))
		if s[8].size() > 5:
			s[8].pop_back()
		s[4] -= dt
		if s[4] <= 0:
			sparks.remove_at(i)
			continue
		if age > 0.12:
			var dx: float = tg.x - s[0]
			var dy: float = tg.y - s[1]
			var d := maxf(0.001, sqrt(dx * dx + dy * dy))
			var want := 380 + 900 * age
			var k := minf(1, dt * (3 + 22 * age))
			s[2] += (dx / d * want - s[2]) * k
			s[3] += (dy / d * want - s[3]) * k
			if d < 9:
				sparks.remove_at(i)
				if absorbed % 3 == 0:
					rings.append([tg.x, tg.y, t, 12.0])
				absorbed += 1
				for j in 2:
					var life := R.rnd(0.4, 0.8)
					motes.append([tg.x + R.rnd(-10, 10), tg.y + R.rnd(-14, 10), R.rnd(-12, 12), -R.rnd(30, 80), life, 0.8, 1 if R.chance(0.3) else 0, C[1] if R.chance(0.5) else C[2]])
				continue
		else:
			s[2] -= s[2] * 3 * dt
			s[3] -= s[3] * 3 * dt
			s[3] += 60 * dt
		s[0] += s[2] * dt
		s[1] += s[3] * dt
	for i in range(motes.size() - 1, -1, -1):
		var m: Array = motes[i]
		m[4] -= dt
		if m[4] <= 0:
			motes.remove_at(i)
			continue
		m[2] -= m[2] * 1.5 * dt
		m[0] += m[2] * dt
		m[1] += m[3] * dt
	rings = rings.filter(func(r): return t - r[2] <= 0.4)

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	var ax := px / Sf.PX
	var ay := py / Sf.PX
	var alive := pop_t > 1e8
	if layer == 0:
		orbit(buf, light, ax, ay, false, alive)
		return
	for i in range(1, trail.size()):
		buf.line(trail[i - 1].x / Sf.PX, trail[i - 1].y / Sf.PX, trail[i].x / Sf.PX, trail[i].y / Sf.PX, C[2] if i < 3 else C[3])
	if alive:
		var flying := clampf((t - LIFT) / FLY, 0, 1)
		var spin := cos(t * 5.2) if kind == "coin" else 1.0
		var sx := maxf(0.15, absf(spin)) * (1 - 0.25 * flying)
		var sy := 1 - 0.25 * flying
		var lift := Sf.out_cubic(t / LIFT) if t < LIFT else 0.0
		blit(buf, ax, ay, sx * (1 - 0.15 * lift), sy * (1 + 0.2 * lift), C[4] if absf(spin) < 0.3 and kind == "coin" else null)
		orbit(buf, light, ax, ay, true, alive)
		light.glow(ax, ay, 14 + 2 * sin(t * 4), C[3], 0.45 + 0.4 * flying)
		light.glow(ax, ay, 5, C[0], 0.25)
	else:
		var k := t - pop_t
		if k < 0.1:
			blit(buf, ax, ay, 1.5 if k < 0.05 else 0.7, 0.6 if k < 0.05 else 1.45, null if k < 0.05 else WHITE)
		if k < 0.08:
			buf.disc(ax, ay, 7 * (1 - k / 0.08) + 1, C[0])
		if k < 0.3:
			light.glow(ax, ay, 30, C[2], 0.9 * (1 - k / 0.3))
	for r in rings:
		var k: float = (t - r[2]) / 0.4
		var e := Sf.out_cubic(k)
		buf.ring(r[0] / Sf.PX, r[1] / Sf.PX, 2 + (r[3] / Sf.PX) * e * 2, maxf(1, 2 * (1 - k)), C[0] if k < 0.3 else C[2], 1.2 - k)
		light.glow(r[0] / Sf.PX, r[1] / Sf.PX, 16, C[2], 0.5 * (1 - k))
	for s in sparks:
		var k: float = s[4] / s[5]
		for i in range(1, s[8].size()):
			buf.dot(s[8][i].x / Sf.PX, s[8][i].y / Sf.PX, C[2] if i < 2 else C[3], 1 - i / 5.0)
		star(buf, light, s[0] / Sf.PX, s[1] / Sf.PX, roundi(s[6] * minf(1, k * 3)), s[7])
	for m in motes:
		var k: float = m[4] / m[5]
		if k * (0.6 + 0.4 * sin(m[4] * 30)) > 0.25:
			star(buf, light, m[0] / Sf.PX, m[1] / Sf.PX, m[6], m[7])

func orbit(buf: Sf.Px, light: Sf.Px, ax: float, ay: float, front: bool, alive: bool) -> void:
	if not alive:
		return
	for i in 2:
		var a := t * 2.6 + i * PI
		var ox := cos(a) * 9
		var oy := sin(a) * 2.6 - 1
		if (sin(a) > 0) != front:
			continue
		buf.dot(ax + ox, ay + oy, C[1] if front else C[3])
		light.glow(ax + ox, ay + oy, 4, C[2], 0.35)

func blit(buf: Sf.Px, cx: float, cy: float, sx: float, sy: float, tint) -> void:
	var hw := sw * sx / 2
	var hh := sh * sy / 2
	for y in range(floori(cy - hh), ceili(cy + hh) + 1):
		for x in range(floori(cx - hw), ceili(cx + hw) + 1):
			var u := floori((x + 0.5 - cx) / sx + sw / 2.0)
			var v := floori((y + 0.5 - cy) / sy + sh / 2.0)
			if u < 0 or v < 0 or v >= sh or u >= spr[v].size():
				continue
			var c = spr[v][u]
			if c != null:
				buf.put(x, y, tint if tint != null else c)

func star(buf: Sf.Px, light: Sf.Px, x: float, y: float, arm: int, c: Color) -> void:
	var px0 := floori(x)
	var py0 := floori(y)
	for d in range(1, arm + 1):
		var cc: Color = Sf.scale(c, 0.8) if d == arm and arm > 1 else c
		buf.put(px0 + d, py0, cc)
		buf.put(px0 - d, py0, cc)
		buf.put(px0, py0 + d, cc)
		buf.put(px0, py0 - d, cc)
	buf.put(px0, py0, WHITE if arm > 0 else c)
	light.glow(x, y, 3 + arm * 2.5, c, 0.4)

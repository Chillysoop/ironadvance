class_name SfWeather
extends RefCounted
## V18-V21 and V23: the Sprite Fusion ambient effects as biome weather. Snow (Frozen Lake) blows
## with the battle wind, embers rise over the Volcano, rain falls on the jungle, the harbor and the
## Ruined City, fog banks roll through the Deep Mine and the Hive, and fireflies, falling leaves
## and sparkle glints replace the old foreground motes. They live in world space inside a window
## around the camera (x0..x1) and wrap across it, so the scroll never runs out of weather.

const WIN := 100.0  # how far past each screen edge the window reaches

var kind := ""
var R := Sf.Rng.new()
var t := 0.0
var x0 := 0.0
var x1 := 960.0
var top := -20.0
var ground: Callable  # world x -> world y of the surface below the sky
var wind := 0.0       # the battle wind (-ish ±3); snow and leaves lean with it
var list: Array = []
var bits: Array = []
var splashes: Array = []
var extra: Array = []

static func make(k: String, ground_fn: Callable, cam_x: float) -> SfWeather:
	var w := SfWeather.new()
	w.kind = k
	w.ground = ground_fn
	w.follow(cam_x)
	w.seed_all()
	return w

func follow(cam_x: float) -> void:
	x0 = cam_x - WIN
	x1 = cam_x + Battle.W + WIN

func wrapx(x: float) -> float:
	return x0 + fposmod(x - x0, x1 - x0)

func done() -> bool:
	return false

func seed_all() -> void:
	match kind:
		"snow":
			for l in [[0, 200], [1, 110], [2, 22]]:
				for i in l[1]:
					var f := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, l[0], -1.0, 0]  # x y vy sway f ph layer rest kind
					snow_reset(f, false)
					list.append(f)
		"rain":
			for l in [[0, 170], [1, 90], [2, 26]]:
				for i in l[1]:
					var d := [0.0, 0.0, l[0], 0.0, 0.0]  # x y layer sp stop
					rain_reset(d, false)
					list.append(d)
		"leaves":
			for i in 22:
				var l := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, false, -1.0, 0.0]
				leaf_reset(l, false)
				list.append(l)
		"fireflies":
			for i in 6:
				var cx := x0 + 40 + i * ((x1 - x0 - 80) / 5.0) + R.rnd(-30, 30)
				extra.append([cx, R.rnd(60, 200), i * 17 + 3, R.rnd(1.6, 2.6), R.rnd(0, 1)])
		"fog":
			build_fog()

func gy(x: float) -> float:
	return ground.call(x)

# --- V18 snow -----------------------------------------------------------------------------------

const S_FALL := [26.0, 52.0, 86.0]
const S_SWAY := [8.0, 16.0, 30.0]
const FW := Color("ffffff")
const Fw := Color("e3edff")
const Fb := Color("9fb1e6")
const Fd := Color("6c7cb8")
const CRYSTAL := [
	["...b...", ".b.w.b.", "..bwb..", "bwwWwwb", "..bwb..", ".b.w.b.", "...b..."],
	["b..b..b", ".b.w.b.", "..wWw..", "bwWWWwb", "..wWw..", ".b.w.b.", "b..b..b"],
	["..b..", ".bwb.", "bwWwb", ".bwb.", "..b.."],
]

func snow_reset(f: Array, at_top: bool) -> void:
	f[0] = R.rnd(x0, x1)
	f[1] = top - R.rnd(0, 40) if at_top else R.rnd(top, minf(gy(f[0]), 520))
	f[2] = S_FALL[f[6]] * R.rnd(0.75, 1.25)
	f[3] = S_SWAY[f[6]] * R.rnd(0.6, 1.2)
	f[4] = R.rnd(0.8, 1.8)
	f[5] = R.rnd(0, TAU)
	f[7] = -1.0
	f[8] = R.ri(0, 2)

func snow_update(dt: float) -> void:
	var w := wind * 14.0 + 16 * Sf.noise(t * 0.3, 5)
	for f in list:
		if f[7] >= 0:
			f[7] -= dt
			if f[7] < 0:
				snow_reset(f, true)
			continue
		f[1] += f[2] * dt
		f[0] = wrapx(f[0] + (w * (0.5 + f[6] * 0.4) + cos(t * f[4] + f[5]) * f[3]) * dt)
		var g := gy(f[0])
		if f[1] >= g - 1:
			if f[6] == 0:
				snow_reset(f, true)
			else:
				f[1] = g - 1
				f[7] = R.rnd(1, 2.6)
		elif f[6] == 0 and f[1] > g - 30 and Sf.hsh(floori(f[5] * 1000)) < 0.4:
			snow_reset(f, true)

func snow_draw(buf: Sf.Px, layer: int) -> void:
	for f in list:
		if f[6] != layer:
			continue
		var x: float = f[0] / Sf.PX
		var y: float = f[1] / Sf.PX
		if f[7] >= 0:
			var a := minf(1, f[7] / 0.8)
			buf.dot(x, y, FW, a)
			if layer == 2:
				buf.dot(x - 1, y, Fw, a)
				buf.dot(x + 1, y, Fb, a)
			continue
		if layer == 0:
			buf.dot(x, y, Fd if Sf.hsh(floori(f[5] * 100), 1) < 0.5 else Fb)
		elif layer == 1:
			buf.dot(x, y, FW)
			buf.dot(x + 1, y, Fw)
			buf.dot(x, y + 1, Fw)
			buf.dot(x + 1, y + 1, Fb)
		else:
			var spr: Array = CRYSTAL[2 if f[8] == 2 else (floori(t * 3 + f[5]) & 1)]
			var h := spr.size()
			var wd: int = spr[0].length()
			var px := roundi(x) - wd / 2
			var py := roundi(y) - h / 2
			for j in h:
				for i in wd:
					var ch: String = spr[j][i]
					if ch != ".":
						buf.put(px + i, py + j, FW if ch == "W" else (Fw if ch == "w" else Fb))

# --- V19 embers ---------------------------------------------------------------------------------

const HOT := Color("fff3a6")
const YELLOW := Color("ffe26b")
const ORANGE := Color("ff8a2a")
const DEEP := Color("f2561d")
const RED := Color("c9281f")
const ASH := [Color("5a5160"), Color("3a3442")]
const BOTTOM := 520.0

func embers_update(dt: float) -> void:
	for i in 2:
		if R.chance(0.8):
			var life := R.rnd(2.2, 4.2)
			list.append([R.rnd(x0, x1), R.rnd(BOTTOM - 10, BOTTOM + 40), R.rnd(-40, 40), -R.rnd(90, 240), life, life, R.next() * 100])
	if R.chance(0.22):
		var life := R.rnd(3.5, 6)
		bits.append([R.rnd(x0, x1), BOTTOM + 10, R.rnd(-20, 20), -R.rnd(50, 110), life, life, R.next() * 100, 2 if R.chance(0.3) else 1, false])
	if R.chance(0.05):
		var life := R.rnd(5, 7)
		bits.append([R.rnd(x0, x1), BOTTOM + 10, R.rnd(-20, 20), -R.rnd(30, 60), life, life, R.next() * 100, 1, true])
	for i in range(bits.size() - 1, -1, -1):
		var c: Array = bits[i]
		c[4] -= dt
		if c[4] <= 0:
			bits.remove_at(i)
			continue
		c[2] += Sf.noise(t * 0.9 + c[6], 1) * 60 * dt + wind * 6 * dt
		c[2] -= c[2] * 0.8 * dt
		c[0] = wrapx(c[0] + c[2] * dt + sin(t * 2 + c[6]) * 10 * dt)
		c[1] += c[3] * dt
	for i in range(list.size() - 1, -1, -1):
		var p: Array = list[i]
		p[4] -= dt
		if p[4] <= 0:
			list.remove_at(i)
			continue
		p[3] += (-60 + sin(t * 3 + p[6]) * 40) * dt
		p[2] += cos(t * 2.3 + p[6]) * 90 * dt
		p[2] -= p[2] * 1.6 * dt
		p[3] -= p[3] * 1.6 * dt
		p[0] = wrapx(p[0] + p[2] * dt)
		p[1] += p[3] * dt

func embers_draw(buf: Sf.Px, light: Sf.Px) -> void:
	for c in bits:
		var k: float = c[4] / c[5]
		var x: float = c[0] / Sf.PX
		var y: float = c[1] / Sf.PX
		var a := minf(1, k * 3) * minf(1, (1 - k) * 8)
		if c[8]:
			buf.dot(x, y, ASH[0], a)
			buf.dot(x + (1 if sin(t * 3 + c[6]) > 0 else 0), y + 1, ASH[1], a)
			continue
		var fl := 0.65 + 0.35 * Sf.noise(t * 9 + c[6], 2)
		var hot := k * fl
		var core := HOT if hot > 0.55 else (YELLOW if hot > 0.35 else ORANGE)
		var rim := ORANGE if hot > 0.45 else DEEP
		if c[7] == 2:
			buf.dot(x - 1, y, rim, a)
			buf.dot(x + 1, y, rim, a)
			buf.dot(x, y - 1, rim, a)
			buf.dot(x, y + 1, rim, a)
			buf.dot(x, y, core, a)
			light.glow(x, y, 9, ORANGE, 0.45 * a * fl)
		else:
			buf.dot(x, y, core, a)
			buf.dot(x, y + 1, rim, a * 0.6)
			light.glow(x, y, 5, ORANGE, 0.35 * a * fl)
	for p in list:
		var k: float = p[4] / p[5]
		var ax: float = p[0] / Sf.PX
		var ay: float = p[1] / Sf.PX
		var c := (YELLOW if sin(t * 22 + p[6] * 3) > -0.2 else ORANGE) if k > 0.5 else (ORANGE if k > 0.2 else RED)
		buf.put(floori(ax), floori(ay), c)
		light.glow(ax, ay, 3, c, 0.3 * k)
	# the heat glow off the lava below the screen
	var y1 := BOTTOM / Sf.PX
	var xa := floori(x0 / Sf.PX)
	var xb := ceili(x1 / Sf.PX)
	for x in range(xa - posmod(xa, 24), xb, 24):
		light.glow(x, y1 + 6, 80, Color("ff7832"), 0.2 * (0.7 + 0.3 * Sf.noise(x * 0.02 + t * 0.6, 7)))

# --- V20 rain -----------------------------------------------------------------------------------

const R_SPEED := [760.0, 1050.0, 1450.0]
const R_LEN := [3.0, 6.0, 12.0]
const R_BODY := [Color("38446e"), Color("5f74ab"), Color("6f86bd")]
const R_HEAD := [Color("56659a"), Color("9ab0e0"), Color("d6e5ff")]
const R_MID := Color("5f74ab")
const R_MIDH := Color("9ab0e0")

func slant() -> Vector2:
	var dx := clampf(-0.22 + wind * 0.08, -0.6, 0.6)
	return Vector2(dx, 1).normalized()

func rain_reset(d: Array, at_top: bool) -> void:
	d[0] = R.rnd(x0, x1)
	d[1] = top - R.rnd(0, 200) if at_top else R.rnd(top - 200, minf(gy(d[0]), 520))
	d[3] = R_SPEED[d[2]] * R.rnd(0.9, 1.1)
	d[4] = gy(d[0]) - R.rnd(10, 140)

func rain_update(dt: float) -> void:
	var u := slant()
	for d in list:
		d[0] = wrapx(d[0] + u.x * d[3] * dt)
		d[1] += u.y * d[3] * dt
		if d[2] == 0 and d[1] > d[4]:
			rain_reset(d, true)
			continue
		var g := gy(d[0])
		if d[1] >= g:
			if g < 1e8 and (d[2] == 2 or R.chance(0.6)):
				splashes.append([d[0], g, t])
			if g < 1e8:
				for k in (3 if d[2] == 2 else R.ri(0, 2)):
					bits.append([d[0], g - 1, R.rnd(-90, 70), -R.rnd(110, 230), R.rnd(0.18, 0.32), g])
			rain_reset(d, true)
	for i in range(bits.size() - 1, -1, -1):
		var b: Array = bits[i]
		b[4] -= dt
		if b[4] <= 0 or b[1] > b[5]:
			bits.remove_at(i)
			continue
		b[3] += Sf.GRAVITY * dt
		b[0] += b[2] * dt
		b[1] += b[3] * dt
	splashes = splashes.filter(func(s): return t - s[2] <= 0.4)

func rain_draw(buf: Sf.Px, layer: int) -> void:
	var u := slant()
	var L: float = R_LEN[layer]
	var c: Color = R_BODY[layer]
	var h: Color = R_HEAD[layer]
	for d in list:
		if d[2] != layer:
			continue
		var x: float = d[0] / Sf.PX
		var y: float = d[1] / Sf.PX
		buf.line(x - u.x * L, y - u.y * L, x - u.x * L * 0.4, y - u.y * L * 0.4, c)
		buf.line(x - u.x * L * 0.4, y - u.y * L * 0.4, x, y, h)

func rain_ground(buf: Sf.Px) -> void:
	for s in splashes:
		var k: float = (t - s[2]) / 0.4
		var rx := 1 + 5 * sqrt(k)
		var ry := rx * 0.25
		var cx: float = s[0] / Sf.PX
		var cy: float = s[1] / Sf.PX
		var n := ceili(rx * TAU * 1.3)
		for j in n:
			var ang := (float(j) / n) * TAU
			if sin(ang) < -0.2:
				continue
			buf.dot(cx + cos(ang) * rx, cy + sin(ang) * ry, R_MIDH if k < 0.3 else R_MID, 1 - k)
	for b in bits:
		buf.dot(b[0] / Sf.PX, b[1] / Sf.PX, R_HEAD[2])

# --- V21 fog ------------------------------------------------------------------------------------
# The original samples a noise field per pixel every frame; that is far too slow here, so each of
# the three banks is baked once into a tiling texture with the same bands, crests and dither, and
# the banks slide past each other at their own speeds.

const TONES := [Color("3b3f63"), Color("5a6185"), Color("8389a8")]
const T0 := 0.3
const T1 := 0.52
const T2 := 0.74
const BW := 0.07
const NW := 256
const NH := 128
var field := PackedFloat32Array()
var fog_tex: Array = []   # [ImageTexture, width art px, height art px, top offset, speed, alpha]

func bake_field(sd: int) -> void:
	field.resize(NW * NH)
	field.fill(0)
	var amp := 0.5
	var total := 0.0
	for cells in [4, 8, 16, 32]:
		var cs: float = NW / float(cells)
		var rows := int(NH / cs)
		for y in NH:
			for x in NW:
				var gx := x / cs
				var gyy := y / cs
				var ix := floori(gx)
				var iy := floori(gyy)
				var u := gx - ix
				var v := gyy - iy
				var su := u * u * (3 - 2 * u)
				var sv := v * v * (3 - 2 * v)
				var h00 := Sf.hsh(posmod(ix, cells) + posmod(iy, rows) * 1000, sd * 31 + cells)
				var h10 := Sf.hsh(posmod(ix + 1, cells) + posmod(iy, rows) * 1000, sd * 31 + cells)
				var h01 := Sf.hsh(posmod(ix, cells) + posmod(iy + 1, rows) * 1000, sd * 31 + cells)
				var h11 := Sf.hsh(posmod(ix + 1, cells) + posmod(iy + 1, rows) * 1000, sd * 31 + cells)
				var tp := h00 + (h10 - h00) * su
				var bt := h01 + (h11 - h01) * su
				field[y * NW + x] += (tp + (bt - tp) * sv) * amp
		total += amp
		amp *= 0.5
	for i in field.size():
		field[i] /= total

func sample(u: float, v: float) -> float:
	var x := floori(u)
	var y := floori(v)
	var fx := u - x
	var fy := v - y
	var xa := x & (NW - 1)
	var xb := (xa + 1) & (NW - 1)
	var ya := y & (NH - 1)
	var yb := (ya + 1) & (NH - 1)
	var a := field[ya * NW + xa]
	var b := field[ya * NW + xb]
	var c := field[yb * NW + xa]
	var d := field[yb * NW + xb]
	return a + (b - a) * fx + (c - a + (a - b - c + d) * fx) * fy

func bake_bank(d: float, i: int, H: float, mask := false, width := 0) -> Array:
	## One fog bank as an image: tile width chosen so the field wraps seamlessly.
	var sx := 0.3 + 0.25 * d
	var sy := 1.5 + 0.8 * d
	var w := int(roundf(NW / sx)) if width == 0 else width
	sx = NW / float(w)
	var tp := 0.0 if mask else H * 0.62 * d
	var base := tp + (H - tp) * 0.8
	var bottom := H + H * (0.03 + 0.16 * d)
	var h := ceili(bottom) + 1
	if mask:
		base = H * 0.3
		bottom = H
		h = int(H)
	var off := i * 97.3
	var crest := TONES[2].lerp(Color.WHITE, 0.14 + 0.12 * d)
	var alpha := 0.42 + 0.2 * d  # thicker than the original: the banks are a fixed bake here
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var prof := func(y: float) -> float: return Sf.smooth(tp, base, y) * (1 - Sf.smooth(bottom - 3, bottom + 1, y))
	var thick := func(P: float, n: float) -> float: return (P * 0.72 + (clampf((n - 0.5) * 2.6 + 0.5, 0, 1) - 0.5) * 0.95) * 1.1
	for y in h:
		var p: float = prof.call(y)
		var pu: float = prof.call(y - 2)
		if p <= 0.02:
			continue
		for x in w:
			var wu := sample(x * 0.35 + off, y * 0.6) - 0.5
			var u := x * sx + wu * 30 + off
			var f: float = thick.call(p, sample(u, y * sy + wu * 12))
			if mask:
				var dx := (x + 0.5) / w * 2 - 1
				var dy := (y + 0.5) / h * 2 - 1
				f *= clampf((1 - sqrt(dx * dx + dy * dy)) * 2.2, 0, 1)
			var bb := Sf.bayer(x, y)
			var c := -1
			if f > T2 + BW or (f > T2 and (f - T2) / BW > bb):
				c = 2
			elif f > T1 + BW or (f > T1 and (f - T1) / BW > bb):
				c = 1
			elif f > T0 + BW or (f > T0 and (f - T0) / BW > bb):
				c = 0
			if c < 0:
				continue
			if c >= 1 and float(thick.call(pu, sample(u, (y - 2) * sy + wu * 12))) < (T2 if c == 2 else T1) - 0.03:
				img.set_pixel(x, y, Color(crest, alpha * (0.95 + 0.15 * c)))
			else:
				img.set_pixel(x, y, Color(TONES[c], alpha * (0.6 + 0.2 * c)))
	return [ImageTexture.create_from_image(img), w, h]

func build_fog() -> void:
	for i in 3:
		var tex: Texture2D = load("res://assets/vfx/fog_bank%d.png" % i)
		fog_tex.append([tex, tex.get_width(), tex.get_height(), 0.0, 22.0 * (0.4 + 0.5 * i), 1.0])

static func bake_pngs(dir: String) -> void:
	## Writes the fog banks and the Smoke Can puff (art px) for assets/vfx; run by --scenario=bakefog.
	var w := SfWeather.new()
	w.bake_field(7)
	for i in 3:
		var b := w.bake_bank(i / 2.0, i, 60.0)
		b[0].get_image().save_png(dir + "/fog_bank%d.png" % i)
	w.bake_smoke().save_png(dir + "/fog_smoke.png")

const SMOKE := [Color("6e7380"), Color("9aa0ac"), Color("c6cad2"), Color("e8ebf0")]

func bake_smoke() -> Image:
	## The Smoke Can puff: the fog's banded noise inside a soft ellipse, grey and thick enough
	## to read as a wall the Jackals cannot see through.
	var w := 112
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dx := (x + 0.5) / w * 2 - 1
			var dy := (y + 0.5) / h * 2 - 1
			var rad := 1 - sqrt(dx * dx + dy * dy)
			if rad <= 0:
				continue
			var n := sample(x * 1.1 + 31, y * 1.6 + 7)
			var f := rad * 1.5 + (n - 0.5) * 1.1
			var up := (1 - sqrt(dx * dx + pow(dy - 0.12, 2))) * 1.5 + (sample(x * 1.1 + 31, (y - 3) * 1.6 + 7) - 0.5) * 1.1
			var bb := Sf.bayer(x, y)
			var c := -1
			if f > 0.95 or (f > 0.85 and (f - 0.85) / 0.1 > bb):
				c = 2
			elif f > 0.6 or (f > 0.5 and (f - 0.5) / 0.1 > bb):
				c = 1
			elif f > 0.25 or (f > 0.15 and (f - 0.15) / 0.1 > bb):
				c = 0
			if c < 0:
				continue
			if c >= 1 and up < f - 0.12:
				c += 1
			img.set_pixel(x, y, Color(SMOKE[c], 0.7 + 0.08 * c))
	return img

func fog_draw(buf: Sf.Px, layer: int, bot: float) -> void:
	## Banks 0 and 1 roll in front of the fight, bank 2 (the deepest) behind it. The front banks
	## are thinned so soldiers and Jackals stay readable through them.
	var tint := Color(1, 1, 1, 1.0 if layer == 0 else 0.45)
	for i in fog_tex.size():
		if (i == 2) != (layer == 0):
			continue
		var f: Array = fog_tex[i]
		var w: int = f[1]
		var h: int = f[2]
		var y := (bot - i * 50.0) / Sf.PX - 60.0
		var drift: float = t * f[4] / Sf.PX + i * 57
		var xa := floorf(x0 / Sf.PX)
		var start := xa - fposmod(xa + drift, w)
		var x := start
		while x < x1 / Sf.PX:
			RenderingServer.canvas_item_add_texture_rect(buf.ci, Rect2(x * Sf.PX, y * Sf.PX, w * Sf.PX, h * Sf.PX), f[0].get_rid(), false, tint)
			x += w

# --- V23 fireflies, falling leaves, sparkle -----------------------------------------------------

const FLY_CORE := Color("faffbe")
const FLY_GLOW := Color("c8ff5a")
const FLY_DIM := Color("6f8f2a")
const FLY_BODY := Color("2a2418")
const FLY_WING := Color("8a96a8")

func flies_update(dt: float) -> void:
	if R.chance(0.12):
		var x := R.rnd(x0, x1)
		var life := R.rnd(4, 8)
		list.append([x, minf(gy(x), 500) - R.rnd(12, 230), R.rnd(-20, 20), R.rnd(-15, 15), life, life, R.next() * 100])
	for i in range(list.size() - 1, -1, -1):
		var p: Array = list[i]
		p[4] -= dt
		if p[4] <= 0:
			list.remove_at(i)
			continue
		var a: float = p[6] * 0.63 + t * (0.7 + fmod(p[6], 1) * 0.9)
		var k := minf(1, dt * 1.5)
		p[2] += (cos(a) * 55 - p[2]) * k
		p[3] += (sin(a * 1.3) * 38 - 8 - p[3]) * k
		p[0] = wrapx(p[0] + p[2] * dt)
		p[1] += p[3] * dt
	for c in extra:
		c[0] = wrapx(c[0])

func flies_draw(buf: Sf.Px, light: Sf.Px) -> void:
	for p in list:
		var k: float = p[4] / p[5]
		var blink := maxf(0, sin(t * (2.2 + fmod(p[6], 3) * 0.7) + p[6]))
		var a := minf(1, (1 - k) * 6) * minf(1, k * 4) * blink
		if a < 0.08:
			continue
		var ax: float = p[0] / Sf.PX
		var ay: float = p[1] / Sf.PX
		buf.put(floori(ax), floori(ay), FLY_CORE if a > 0.5 else FLY_GLOW)
		light.glow(ax, ay, 7, FLY_GLOW, 0.55 * a)
	for fl in extra:
		var wx: float = fl[0] + Sf.noise(t * 0.32, fl[2]) * 140
		var g := minf(gy(wx), 500)
		var x := wx / Sf.PX
		var y: float = (g - fl[1] + Sf.noise(t * 0.27, fl[2] + 9) * 60) / Sf.PX
		var u := fmod(t / fl[3] + fl[4], 1.0)
		var pulse := pow(sin((u / 0.6) * PI), 0.7) if u < 0.6 else 0.0
		var px := roundi(x)
		var py := roundi(y)
		var dir := 1 if Sf.noise(t * 0.32 + 0.05, fl[2]) > Sf.noise(t * 0.32, fl[2]) else -1
		var wy := py - (2 if sin(t * 50 + fl[2]) > 0 else 1)
		buf.dot(px - dir, wy, FLY_WING, 0.6)
		buf.dot(px, wy, FLY_WING, 0.6)
		buf.put(px + dir, py, FLY_BODY)
		buf.put(px + dir * 2, py, FLY_BODY)
		buf.put(px, py, FLY_CORE if pulse > 0.25 else FLY_DIM)
		buf.put(px - dir, py, FLY_CORE if pulse > 0.5 else (FLY_GLOW if pulse > 0.15 else FLY_DIM))
		if pulse > 0.6:
			buf.put(px - dir, py + 1, FLY_GLOW)
		light.glow(x, y, 26, FLY_GLOW, 0.5 * pulse)
		light.glow(x, y, 8, FLY_CORE, 0.6 * pulse)
		if pulse > 0.4:
			var a := (pulse - 0.4) * 1.2
			buf.dot(px - dir, py - 2, FLY_GLOW, a)
			buf.dot(px - dir, py + 2, FLY_GLOW, a)
			buf.dot(px - dir - 2, py, FLY_GLOW, a)
			buf.dot(px - dir + 2, py, FLY_GLOW, a)

const LEAF_SHAPES := [
	["......DDDD..", "...DDDLLLBD.", ".DDLLLRLBBBD", "TRRRRRRRRRRD", ".DDBBBBBRSSD", "...DDDSSSSD.", "......DDDD.."],
	["...DDD...", "..DLLBD..", ".DLLLBBD.", "DLLRBBBSD", "DLBBRBSSD", ".DBBBRSD.", "..DDSSD..", "....T...."],
	[".....D.....", "....DLD....", ".DD.DLD.DD.", ".DLDDLDDLD.", "..DLLLBBD..", "DDDLLRBBDDD", ".DLLBRBSSD.", "..DDBRSDD..", "....DRD....", ".....T....."],
]
# the jungle keeps green leaves, with a few of the original's golden ones
const LEAF_PALS := [
	["b6e86a", "5fb83a", "3a7f2a", "1d3f17"],
	["9ad85a", "4ca83a", "2f6e28", "173816"],
	["fff09a", "f0c83a", "b88a1c", "5a3f10"],
]

func leaf_reset(l: Array, at_top: bool) -> void:
	# [x0, x, y, vy, amp, w, ph, flip, shape, pal, near, rest, ang]
	l[0] = R.rnd(x0, x1)
	l[2] = top - R.rnd(0, 40) if at_top else R.rnd(top, minf(gy(l[0]), 500) - 20)
	l[3] = R.rnd(34, 56)
	l[4] = R.rnd(14, 34)
	l[5] = R.rnd(1.8, 2.8)
	l[6] = R.rnd(0, TAU)
	l[7] = R.rnd(0, TAU)
	l[10] = R.chance(0.35)
	l[8] = R.ri(0, 2)
	l[9] = 2 if R.chance(0.2) else R.ri(0, 1)
	l[11] = -1.0
	l[12] = 0.0
	l[1] = l[0]

func leaves_update(dt: float) -> void:
	for l in list:
		if l[11] >= 0:
			l[11] -= dt
			if l[11] < 0:
				leaf_reset(l, true)
			continue
		l[6] += l[5] * dt
		l[0] = wrapx(l[0] + (12 + wind * 10) * dt)
		l[1] = l[0] + sin(l[6]) * l[4]
		l[2] += l[3] * (0.45 + 0.9 * absf(cos(l[6]))) * dt
		l[12] = cos(l[6]) * 0.75 + (0.0 if l[10] else 0.3)
		l[7] += (6.0 if Sf.hsh(floori(l[6] / PI), floori(l[0])) < 0.25 else 0.4) * dt
		var g := gy(l[1])
		if l[2] >= g - 2:
			l[2] = g - 2
			l[11] = R.rnd(2.5, 5)

func leaves_draw(buf: Sf.Px, near: bool) -> void:
	for l in list:
		if l[10] != near:
			continue
		if l[11] >= 0:
			blit_leaf(buf, l[8], l[9], l[1] / Sf.PX, l[2] / Sf.PX - 2, l[12] * 0.3, minf(1, l[11]), 1.0)
		else:
			blit_leaf(buf, l[8], l[9], l[1] / Sf.PX, l[2] / Sf.PX, l[12], 1.0, 0.35 + 0.65 * absf(cos(l[7])))

func blit_leaf(buf: Sf.Px, shape: int, pal: int, cx: float, cy: float, ang: float, a: float, sq: float) -> void:
	var rows: Array = LEAF_SHAPES[shape]
	var P: Array = LEAF_PALS[pal]
	var h := rows.size()
	var w: int = rows[0].length()
	var ca := cos(ang)
	var sa := sin(ang)
	var r := ceili(maxf(w, h) / 2.0) + 1
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var u := (x * ca + y * sa) + w / 2.0
			var v := (-x * sa + y * ca) / maxf(0.2, sq) + h / 2.0
			var iu := floori(u)
			var iv := floori(v)
			if iu < 0 or iv < 0 or iv >= h or iu >= w:
				continue
			var ch: String = rows[iv][iu]
			if ch == ".":
				continue
			var c: Color = P[0] if ch == "L" else (P[1] if ch == "B" else (P[2] if ch == "S" or ch == "R" else P[3]))
			buf.dot(roundi(cx) + x, roundi(cy) + y, c, a)

const SP_WARM := [Color("fffbe2"), Color("fff0a6"), Color("ffd862")]
const SP_COOL := [Color("dcfbff"), Color("a6ecff"), Color("62c8f4")]

func sparkle_update(dt: float) -> void:
	## Glints that flare up out of the air and fade (sparkle.ts's satellite flares, ambient).
	if R.chance(0.05):
		var x := R.rnd(x0 + WIN, x1 - WIN)
		list.append([x, R.rnd(60, minf(gy(x), 500) - 20), t, R.rnd(0.35, 0.6), R.rnd(3, 6.5), R.rnd(-2, 2), R.chance(0.35)])
	list = list.filter(func(s): return t - s[2] < s[3])

func sparkle_draw(buf: Sf.Px, light: Sf.Px) -> void:
	for s in list:
		var u: float = (t - s[2]) / s[3]
		var L: float = s[4] * pow(sin(u * PI), 0.7)
		if L < 0.8:
			continue
		var pal: Array = SP_COOL if s[6] else SP_WARM
		var x: float = s[0] / Sf.PX
		var y: float = s[1] / Sf.PX
		var ang: float = s[5] * u + 0.4
		for i in 8:
			var diag := i % 2 == 1
			var an := ang + i * TAU / 8
			var ln := L * 0.42 if diag else L
			var ca := cos(an)
			var sa := sin(an)
			var d := 0.0
			while d <= ln:
				var q := d / ln
				var c: Color = (pal[1] if q < 0.5 else pal[2]) if diag else (Color.WHITE if q < 0.3 else (pal[1] if q < 0.65 else pal[2]))
				buf.dot(x + ca * d, y + sa * d, c, 1.0 if q < 0.7 else 1 - (q - 0.7) / 0.35)
				d += 0.5
		buf.put(floori(x), floori(y), Color.WHITE)
		light.glow(x, y, 4 + L * 1.4, pal[1], 0.5)

# --- shared -------------------------------------------------------------------------------------

func update(dt: float) -> void:
	t += dt
	match kind:
		"snow": snow_update(dt)
		"embers": embers_update(dt)
		"rain": rain_update(dt)
		"fireflies": flies_update(dt)
		"leaves": leaves_update(dt)
		"sparkle": sparkle_update(dt)

func draw(buf: Sf.Px, light: Sf.Px, layer: int) -> void:
	match kind:
		"snow":
			if layer == 0:
				snow_draw(buf, 0)
				snow_draw(buf, 1)
			else:
				snow_draw(buf, 2)
		"embers":
			if layer == 1:
				embers_draw(buf, light)
		"rain":
			if layer == 0:
				rain_draw(buf, 0)
				rain_draw(buf, 1)
				rain_ground(buf)
			else:
				rain_draw(buf, 2)
		"fog":
			fog_draw(buf, layer, 470.0)
		"fireflies":
			if layer == 1:
				flies_draw(buf, light)
		"leaves":
			leaves_draw(buf, layer == 1)
		"sparkle":
			if layer == 1:
				sparkle_draw(buf, light)

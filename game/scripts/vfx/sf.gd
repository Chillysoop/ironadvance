class_name Sf
## Shared pieces of the Sprite Fusion pixel VFX ports (https://www.spritefusion.com/pixel-art-vfx,
## MIT, see assets/vfx/LICENSE_SpriteFusion.txt). The originals paint into a colour buffer and an
## additive light buffer one art pixel at a time; here Px turns the same calls into rects on a
## canvas item (runs of a row become one rect) and glows become cached radial sprites drawn
## additively. Coordinates handed to Px are art pixels (world / PX), like the originals.

const PX := 2.0
const GRAVITY := 1900.0
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

static var glow_tex := {}  # radius -> ImageTexture
static var disc_tex := {}  # quarter-pixel radius * 4 + centre quadrant -> [ImageTexture, offset, size]

static func bayer(x: int, y: int) -> float:
	return (BAYER[((y & 3) << 2) | (x & 3)] + 0.5) / 16.0

static func hsh(n: int, k := 0) -> float:
	return float((((n + 1 + k * 7919) * 2654435761) & 0xFFFFFFFF) % 100000) / 100000.0

static func mix(c1: Color, c2: Color, t: float) -> Color:
	return c1.lerp(c2, t)

static func scale(c: Color, k: float) -> Color:
	return Color(minf(1.0, c.r * k), minf(1.0, c.g * k), minf(1.0, c.b * k), c.a)

static func ramp(stops: Array, t: float) -> Color:
	var u := clampf(t, 0.0, 0.9999) * (stops.size() - 1)
	var i := int(u)
	return (stops[i] as Color).lerp(stops[i + 1], u - i)

static func out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3)

static func glow_texture(r: int) -> ImageTexture:
	if glow_tex.has(r):
		return glow_tex[r]
	var img := Image.create(r * 2, r * 2, false, Image.FORMAT_RGBA8)
	for y in r * 2:
		var dy := (y + 0.5 - r) / r
		for x in r * 2:
			var dx := (x + 0.5 - r) / r
			var d := dx * dx + dy * dy
			var f := 0.0 if d >= 1.0 else 1.0 - sqrt(d)
			img.set_pixel(x, y, Color(1, 1, 1, f * f))
	var t := ImageTexture.create_from_image(img)
	glow_tex[r] = t
	return t

static func disc_texture(r: float, fx: float, fy: float) -> Array:
	## The pixels of a disc of radius r centred fx, fy into its pixel (the same test as the
	## originals' per-pixel loop), white, so one textured rect draws the whole disc.
	var rq := clampi(roundi(r * 4), 3, 640)
	var qx := 1 if fx >= 0.5 else 0
	var qy := 1 if fy >= 0.5 else 0
	var key := rq * 4 + qx * 2 + qy
	if disc_tex.has(key):
		return disc_tex[key]
	var rr := rq / 4.0
	var cx := 0.25 + qx * 0.5
	var cy := 0.25 + qy * 0.5
	var o := -ceili(rr) - 1
	var n := ceili(rr) * 2 + 3
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for j in n:
		var dy := o + j + 0.5 - cy
		for i in n:
			var dx := o + i + 0.5 - cx
			if dx * dx + dy * dy <= rr * rr:
				img.set_pixel(i, j, Color.WHITE)
	var e := [ImageTexture.create_from_image(img), o, n]
	disc_tex[key] = e
	return e

## A seeded random source with the helpers the originals use.
class Rng:
	var g := RandomNumberGenerator.new()
	func _init(seed_v := 0) -> void:
		if seed_v != 0:
			g.seed = seed_v
		else:
			g.randomize()
	func next() -> float:
		return g.randf()
	func rnd(a: float, b: float) -> float:
		return a + (b - a) * g.randf()
	func ri(a: int, b: int) -> int:
		return a + int(g.randf() * (b - a + 1))
	func sgn() -> float:
		return -1.0 if g.randf() < 0.5 else 1.0
	func chance(p: float) -> bool:
		return g.randf() < p
	func pick(a: Array):
		return a[int(g.randf() * a.size()) % a.size()]

## The painter: what the originals call Px, writing rects onto a canvas item instead of a buffer.
## Later writes cover earlier ones, alpha writes blend over them, so the result matches.
class Px:
	var ci: RID
	var light := false
	var x0 := 0
	var y0 := 0
	var x1 := 0
	var y1 := 0

	func _init(canvas: RID, is_light: bool, clip: Rect2i) -> void:
		ci = canvas
		light = is_light
		x0 = clip.position.x
		y0 = clip.position.y
		x1 = clip.end.x
		y1 = clip.end.y

	func put(x: int, y: int, c: Color) -> void:
		if x < x0 or y < y0 or x >= x1 or y >= y1:
			return
		RenderingServer.canvas_item_add_rect(ci, Rect2(x * PX, y * PX, PX, PX), c)

	func span(xa: int, xb: int, y: int, c: Color) -> void:
		if y < y0 or y >= y1:
			return
		xa = maxi(xa, x0)
		xb = mini(xb, x1 - 1)
		if xa > xb:
			return
		RenderingServer.canvas_item_add_rect(ci, Rect2(xa * PX, y * PX, (xb - xa + 1) * PX, PX), c)

	func blend(x: int, y: int, c: Color, a: float) -> void:
		put(x, y, Color(c, c.a * a))

	func add(x: int, y: int, c: Color, k: float) -> void:
		## (light) additive: the light canvas draws with an add material
		put(x, y, Color(c, clampf(k, 0.0, 1.0)))

	func dot(x: float, y: float, c: Color, a := 1.0) -> void:
		var px := floori(x)
		var py := floori(y)
		if a >= 1.0 or a > Sf.bayer(px, py):
			put(px, py, c)

	func disc(cx: float, cy: float, r: float, c: Color) -> void:
		if r <= 0.5:
			put(roundi(cx), roundi(cy), c)
			return
		var bx := floori(cx)
		var by := floori(cy)
		var d := Sf.disc_texture(r, cx - bx, cy - by)
		var o: int = d[1]
		var n: int = d[2]
		if bx + o + n < x0 or by + o + n < y0 or bx + o >= x1 or by + o >= y1:
			return
		RenderingServer.canvas_item_add_texture_rect(ci, Rect2((bx + o) * PX, (by + o) * PX, n * PX, n * PX), d[0].get_rid(), false, c)

	func alpha_disc(cx: float, cy: float, r: float, c: Color, a: float) -> void:
		if a <= 0.01:
			return
		disc(cx, cy, r, Color(c, c.a * minf(1.0, a)))

	func ring(cx: float, cy: float, r: float, thick: float, c: Color, alpha := 1.0) -> void:
		var ro := r + thick * 0.5
		var ri := maxf(0.0, r - thick * 0.5)
		for y in range(floori(cy - ro), ceili(cy + ro) + 1):
			var dy := y + 0.5 - cy
			var wo2 := ro * ro - dy * dy
			if wo2 < 0.0:
				continue
			var wo := sqrt(wo2)
			var xa := ceili(cx - 0.5 - wo)
			var xb := floori(cx - 0.5 + wo)
			var wi2 := ri * ri - dy * dy
			var ea := xb + 1
			var eb := xb
			if wi2 > 0.0:
				var wi := sqrt(wi2)
				ea = floori(cx - 0.5 - wi) + 1
				eb = ceili(cx - 0.5 + wi) - 1
			if alpha >= 1.0 or r > 24.0:
				# (a big ring blends instead of dithering pixel by pixel: same look, far fewer rects)
				var col := c if alpha >= 1.0 else Color(c, c.a * alpha)
				span(xa, mini(xb, ea - 1), y, col)
				if eb >= ea:
					span(maxi(xa, eb + 1), xb, y, col)
			else:
				for x in range(xa, mini(xb, ea - 1) + 1):
					if alpha > Sf.bayer(x, y):
						put(x, y, c)
				for x in range(maxi(xa, eb + 1) if eb >= ea else xb + 1, xb + 1):
					if alpha > Sf.bayer(x, y):
						put(x, y, c)

	func ellipse_ring(cx: float, cy: float, rx: float, q: float, thick: float, c: Color, alpha: float, lower: bool) -> void:
		## The rim of the ellipse rx * (1, q), thick wide, upper or lower half only, as blended row
		## spans (the originals stipple it dot by dot). Each row covers the stretch of rim that
		## passes through it, so a flat ellipse stays unbroken.
		var h := thick * 0.5
		var col := c if alpha >= 1.0 else Color(c, c.a * clampf(alpha, 0.0, 1.0))
		var ext := (rx + h) * q
		var ya := floori(cy) if lower else floori(cy - ext)
		var yb := ceili(cy + ext) if lower else floori(cy) - 1
		for y in range(ya, yb + 1):
			var d0 := absf(y - cy)
			var d1 := absf(y + 1 - cy)
			var dmin := 0.0 if (y <= cy and y + 1 >= cy) else minf(d0, d1)
			var dmax := maxf(d0, d1)
			var smin := dmin / maxf(0.001, q)
			var smax := dmax / maxf(0.001, q)
			if smin > rx + h:
				continue
			var outer := sqrt(maxf(0.0, rx * rx - smin * smin)) + h
			if smax >= rx:
				span(floori(cx - outer), floori(cx + outer), y, col)
			else:
				var inner := maxf(0.0, sqrt(rx * rx - smax * smax) - h)
				span(floori(cx - outer), floori(cx - inner), y, col)
				span(floori(cx + inner), floori(cx + outer), y, col)

	func line(fx0: float, fy0: float, fx1: float, fy1: float, c: Color) -> void:
		var ax := roundi(fx0)
		var ay := roundi(fy0)
		var bx := roundi(fx1)
		var by := roundi(fy1)
		var dx := absi(bx - ax)
		var dy := -absi(by - ay)
		var sx := 1 if ax < bx else -1
		var sy := 1 if ay < by else -1
		var err := dx + dy
		for n in 4096:
			put(ax, ay, c)
			if ax == bx and ay == by:
				break
			var e2 := 2 * err
			if e2 >= dy:
				err += dy
				ax += sx
			if e2 <= dx:
				err += dx
				ay += sy

	func glow(cx: float, cy: float, r: float, c: Color, k: float) -> void:
		if r < 1.0 or k <= 0.01:
			return
		var R := clampi(roundi(r), 1, 160)
		var gx := roundi(cx) - R
		var gy := roundi(cy) - R
		if gx + R * 2 < x0 or gy + R * 2 < y0 or gx >= x1 or gy >= y1:
			return
		var tex := Sf.glow_texture(R)
		RenderingServer.canvas_item_add_texture_rect(ci, Rect2(gx * PX, gy * PX, R * 2 * PX, R * 2 * PX), tex.get_rid(), false, Color(c, minf(1.0, k)))

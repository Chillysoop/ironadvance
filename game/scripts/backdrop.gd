extends Node2D
## Parallax sky, drifting clouds, three lit silhouette layers and the animated water line,
## plus the background life between them: artillery flashes behind the hills, smoke
## columns over the ruins, searchlights at night, bird flocks and sun shafts.

@onready var b: Battle = get_parent()
var sky: Texture2D
var clouds: Texture2D
var layers: Array = []  # [texture, parallax, y]
var theme := "dusk"

const FAR := 0.12
const MID := 0.3
const NEAR := 0.5
const SUN := Vector2(700, 240)  # where the sky texture puts the sun / moon on screen

func setup(th: String) -> void:
	theme = th
	modulate = b.th.get("sky", Color.WHITE)  # a biome can warm or cool the whole backdrop
	sky = load("res://assets/bg/%s_sky.png" % th)
	clouds = load("res://assets/bg/%s_clouds.png" % th)
	layers = [
		[load("res://assets/bg/%s_far.png" % th), FAR, 360.0],
		[load("res://assets/bg/%s_mid.png" % th), MID, 392.0],
		[load("res://assets/bg/%s_near.png" % th), NEAR, 420.0],
	]

func _process(_d: float) -> void:
	queue_redraw()

static func h1(n: int) -> float:
	return Terrain.hash2(n, 91)

func tile(tx: Texture2D, par: float, bottom: float, drift := 0.0) -> void:
	var cx := b.cam_x
	var w := tx.get_width() * Art.PX
	var hgt := tx.get_height() * Art.PX
	var off := fposmod(cx * par + drift, w)
	var x := cx - off - 8
	while x < cx + Battle.W + 8:
		draw_texture_rect(tx, Rect2(roundf(x), bottom - hgt, w, hgt), false)
		x += w

func _draw() -> void:
	if sky == null:
		return
	var cx := b.cam_x
	draw_texture_rect(sky, Rect2(cx - 8, -8, Battle.W + 16, Battle.H + 16), false)
	draw_flock(cx, 0.04)
	tile(clouds, 0.05, 40 + clouds.get_height() * Art.PX, b.t * 0.05)
	if theme == "dusk" or theme == "night":
		draw_flashes(cx)
	tile(layers[0][0], FAR, layers[0][2])
	if theme == "night":
		draw_searchlights(cx)
	if theme != "jungle":
		draw_smoke_columns(cx)
	tile(layers[1][0], MID, layers[1][2])
	if theme == "jungle":
		draw_mist(cx)
	draw_flock(cx, 0.4)
	tile(layers[2][0], NEAR, layers[2][2])
	if theme != "night":
		draw_shafts(cx)
	draw_water(cx)

# ---------------------------------------------------------------- distant life
func draw_flashes(cx: float) -> void:
	## Artillery somewhere past the hills: a short glow that the far ridge hides the bottom of.
	var slot := b.t / 40
	for k in 2:
		var s := slot - k
		if h1(s) > 0.3:
			continue
		var age := b.t - s * 40
		if age > 14:
			continue
		var x := cx + h1(s + 7) * Battle.W
		var y := 300.0 + h1(s + 3) * 30
		var a := (1.0 - age / 14.0)
		var col := Color("ffd890") if theme == "dusk" else Color("ffb070")
		draw_circle(Vector2(x, y), 46 + age * 2, Color(col, 0.10 * a))
		draw_circle(Vector2(x, y), 22 + age, Color(col, 0.22 * a))

func draw_smoke_columns(cx: float) -> void:
	## Burning ruins in the mid layer: a fire glow at the base and a leaning column of puffs.
	var spacing := 420.0
	var lx0 := cx * MID
	var k0 := int(floor((lx0 - 200) / spacing))
	var lean := 1.0 if b.wind >= 0 else -1.0
	var smoke := Color("2a2026") if theme == "dusk" else Color("1a1c2c")
	for k in range(k0, k0 + 5):
		if h1(k) > 0.55:
			continue
		var sx := cx + (k * spacing + h1(k + 11) * spacing * 0.6) - lx0
		if sx < cx - 200 or sx > cx + Battle.W + 200:
			continue
		var base := 352.0 + h1(k + 5) * 24
		var n := 30
		var per := 520
		for i in n:
			var age := (b.t + i * per / n + int(h1(k + 2) * per)) % per
			var f := age / float(per)
			var x := sx + f * f * 90 * lean + sin(f * 7.0 + i) * 4
			var y := base - f * 200
			var r := roundf((6 + f * 30) / 2) * 2
			var a := minf(1.0, f * 8) * (1 - f) * 0.38
			draw_circle(Vector2(roundf(x), roundf(y)), r, Color(smoke.lerp(Color(b.th.water[1]), f * 0.3), a))
		var fl := 0.6 + 0.4 * sin(b.t * 0.3 + k) * sin(b.t * 0.17 + k * 3)
		draw_circle(Vector2(sx, base + 6), 20, Color(1, 0.5, 0.2, 0.10 * fl))
		draw_rect(Rect2(roundf(sx) - 4, base, 8, 4), Color(1, 0.55, 0.2, 0.7 * fl))
		draw_rect(Rect2(roundf(sx) - 2, base - 2 - roundf(fl * 2), 4, 2 + roundf(fl * 2)), Color(1, 0.85, 0.4, 0.8 * fl))

func draw_searchlights(cx: float) -> void:
	var spacing := 640.0
	var lx0 := cx * MID
	var k0 := int(floor((lx0 - 300) / spacing))
	for k in range(k0, k0 + 4):
		var sx := cx + (k * spacing + h1(k + 31) * 200) - lx0
		var base := Vector2(sx, 350)
		var a := -PI / 2 + sin(b.t / 170.0 + k * 2.1) * 0.55
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x)
		var tip := base + dir * 520
		for layer in 2:
			var wdt := 34.0 if layer == 0 else 14.0
			var col := Color(0.75, 0.82, 1.0, 0.07 if layer == 0 else 0.09)
			draw_colored_polygon(PackedVector2Array([base - side * 2, base + side * 2, tip + side * wdt, tip - side * wdt]), col)
		draw_circle(base, 4, Color(0.9, 0.95, 1.0, 0.6))

func draw_mist(cx: float) -> void:
	## Low jungle mist banks drifting between the canopy and the near trees.
	for i in 4:
		var y := 360.0 + i * 12
		var off := fposmod(b.t * (0.12 + i * 0.05) - cx * (0.35 + i * 0.04), 600.0)
		var x := cx - off - 600
		while x < cx + Battle.W + 600:
			var w := 300.0 + 80 * sin(i * 3.0)
			draw_rect(Rect2(roundf(x), y, w, 10 - i * 2), Color(0.75, 0.9, 0.78, 0.07))
			draw_rect(Rect2(roundf(x) + 40, y - 4, w - 90, 4), Color(0.75, 0.9, 0.78, 0.05))
			x += 600

func draw_shafts(cx: float) -> void:
	## Soft light shafts fanning out from the sun, breathing slowly.
	var o := Vector2(cx, 0) + SUN
	for i in 5:
		var a := PI * 0.62 + i * 0.13 + sin(b.t / 300.0 + i) * 0.02
		var w := 0.025 + 0.01 * (i % 2)
		var L := 700.0
		var p1 := o + Vector2(cos(a - w), sin(a - w)) * L
		var p2 := o + Vector2(cos(a + w), sin(a + w)) * L
		var al := (0.035 + 0.02 * sin(b.t / 90.0 + i * 1.7)) * (1.0 if theme == "dusk" else 0.8)
		draw_colored_polygon(PackedVector2Array([o, p1, p2]), Color(1, 0.92, 0.7, al))

func draw_flock(cx: float, par: float) -> void:
	## A loose V of birds (bats at night) crossing now and then; two depths.
	var per := 1500 if par < 0.1 else 2300
	var slot := (b.t + (0 if par < 0.1 else 700)) / per
	var age := (b.t + (0 if par < 0.1 else 700)) % per
	var dur := 900
	if age > dur:
		return
	var dir := 1.0 if h1(slot + int(par * 100)) < 0.5 else -1.0
	var f := age / float(dur)
	var y0 := 90.0 + h1(slot + 5) * 120 + (120 if par > 0.1 else 0)
	var startx := -60.0 if dir > 0 else Battle.W + 60.0
	var sx := cx + startx + dir * f * (Battle.W + 120) - fposmod(cx * par, 1.0)
	var n := 5 + int(h1(slot + 9) * 5)
	var sz := 2.0 if par > 0.1 else 1.0
	var col := Color("1a1420") if theme != "night" else Color("0a0a16")
	if par < 0.1:
		col = col.lerp(Color(b.th.water[1]), 0.25)
	for i in n:
		var row := (i + 1) / 2
		var sgn := -1 if i % 2 else 1
		var bx := sx - dir * row * 14 * sz
		var by := y0 + sgn * row * 7 * sz + sin(b.t / 20.0 + i) * 3
		if theme == "night":
			bx += sin(b.t / 7.0 + i * 2) * 6
			by += cos(b.t / 5.0 + i) * 5
		var flap := (b.t / (5 if theme == "night" else 8) + i) % 2
		var p := Vector2(roundf(bx), roundf(by))
		draw_rect(Rect2(p.x - sz, p.y, sz * 2, sz), col)
		if flap == 0:
			draw_rect(Rect2(p.x - sz * 3, p.y - sz, sz * 2, sz), col)
			draw_rect(Rect2(p.x + sz, p.y - sz, sz * 2, sz), col)
		else:
			draw_rect(Rect2(p.x - sz * 3, p.y + sz, sz * 2, sz), col)
			draw_rect(Rect2(p.x + sz, p.y + sz, sz * 2, sz), col)

func draw_water(cx: float) -> void:
	var th: Dictionary = b.th
	var wy := float(Battle.WATER_Y)
	draw_rect(Rect2(cx - 8, wy, Battle.W + 16, Battle.H - wy + 8), th.water[0])
	var x2 := floorf(cx / 8) * 8 - 8
	while x2 < cx + Battle.W + 8:
		var yy := wy + roundf(sin(x2 / 23.0 + b.t / 18.0) * 2)
		draw_rect(Rect2(x2, yy, 8, 3), th.water[1])
		if int(x2 / 8) % 5 == 0:
			draw_rect(Rect2(x2 + 2, yy + 8 + roundf(sin(x2 + b.t / 30.0) * 2), 4, 1), th.water[1])
		# glints, thickest under the sun / moon
		var near_sun := absf(x2 - cx - SUN.x) < 60
		if Terrain.hash2(int(x2 / 8), b.t / 10) < (0.35 if near_sun else 0.04):
			draw_rect(Rect2(x2 + 2, yy + 4 + (int(x2) % 3) * 6, 4 if near_sun else 2, 1), Color(1, 0.95, 0.8, 0.8))
		x2 += 8

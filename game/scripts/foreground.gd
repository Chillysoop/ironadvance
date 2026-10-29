extends Node2D
## Drawn over the world: dark close-up silhouettes sliding along the bottom edge faster
## than the ground, and the air itself (embers and ash at dusk, pollen and leaves in the
## jungle, fireflies at the harbor). Particles are stateless: each one's position is a
## function of time, so there is nothing to simulate or save.

@onready var b: Battle = get_parent()
var fore: Texture2D
var theme := ""

const FORE_PAR := 1.35

func _process(_d: float) -> void:
	if theme != b.theme and b.T != null:
		theme = b.theme
		fore = load("res://assets/bg/%s_fore.png" % theme)
	queue_redraw()

static func hf(i: int, salt: int) -> float:
	return Terrain.hash2(i, salt)

func _draw() -> void:
	if fore == null:
		return
	var cx := b.cam_x
	# biomes with Sprite Fusion weather (vfx.gd WEATHER) drop these old motes
	var sf: bool = b.vfx != null and not b.vfx.weather.is_empty()
	match theme if not sf else "":
		"dusk":
			motes(cx, 26, Color("ffb23e"), Vector2(0.15, -0.35), 2.0, true)
			motes(cx, 18, Color(0.55, 0.5, 0.52, 0.7), Vector2(0.1, 0.25), 2.0, false, 40)
		"jungle":
			motes(cx, 26, Color(0.95, 1.0, 0.7, 0.75), Vector2(0.08, -0.06), 2.0, false)
			leaves(cx, 7)
		"night":
			fireflies(cx, 18)
			motes(cx, 14, Color(0.7, 0.75, 0.95, 0.35), Vector2(0.05, 0.12), 2.0, false, 60)
	# close foreground silhouettes along the bottom edge
	var w := fore.get_width() * Art.PX
	var hgt := fore.get_height() * Art.PX
	var off := fposmod(cx * FORE_PAR, w)
	var x := cx - off - 8
	while x < cx + Battle.W + 8:
		draw_texture_rect(fore, Rect2(roundf(x), Battle.H - hgt + 10, w, hgt), false)
		x += w

func wrap_pos(i: int, salt: int, cx: float, vel: Vector2, par: float) -> Vector2:
	var span := Vector2(Battle.W + 80, Battle.H + 80)
	var v := Vector2(vel.x * (0.6 + hf(i, salt + 1)) + b.wind * 0.03, vel.y * (0.6 + hf(i, salt + 2)))
	var sx := fposmod(hf(i, salt) * span.x + b.t * v.x - cx * (par - 1.0), span.x) - 40
	var sy := fposmod(hf(i, salt + 3) * span.y + b.t * v.y, span.y) - 40
	sx += sin(b.t / 37.0 + i) * 6
	return Vector2(cx + sx, sy)

func motes(cx: float, n: int, col: Color, vel: Vector2, sz: float, flicker: bool, salt := 0) -> void:
	for i in n:
		var par := 0.8 + hf(i, salt + 9) * 0.5
		var p := wrap_pos(i, salt, cx, vel, par)
		var a := col.a
		if flicker:
			a *= 0.5 + 0.5 * sin(b.t / 6.0 + i * 1.7)
			# embers cool as they climb
			a *= clampf(p.y / 300.0, 0.15, 1.0)
		var s := sz * (2.0 if par > 1.2 else 1.0)
		draw_rect(Rect2(roundf(p.x), roundf(p.y), s, s), Color(col, a))

func leaves(cx: float, n: int) -> void:
	for i in n:
		var p := wrap_pos(i, 50, cx, Vector2(0.35, 0.45), 1.1 + hf(i, 59) * 0.2)
		var flip := int(b.t / 12 + i) % 2 == 0
		var col := Color("4ca83a") if i % 3 else Color("c0a040")
		col = col * Color(0.8, 0.8, 0.8)
		if flip:
			draw_rect(Rect2(roundf(p.x), roundf(p.y), 6, 2), col)
			draw_rect(Rect2(roundf(p.x) + 2, roundf(p.y) - 2, 2, 2), col)
		else:
			draw_rect(Rect2(roundf(p.x) + 2, roundf(p.y) - 2, 2, 6), col)

func fireflies(cx: float, n: int) -> void:
	for i in n:
		var par := 0.9 + hf(i, 79) * 0.3
		var sx := fposmod(hf(i, 70) * (Battle.W + 80) - cx * (par - 1.0) + sin(b.t / (60.0 + i * 3) + i) * 40, Battle.W + 80) - 40
		var sy := 260 + hf(i, 71) * 220 + sin(b.t / (45.0 + i * 2) + i * 2) * 18
		var glow := maxf(0.0, sin(b.t / (25.0 + hf(i, 72) * 30) + i * 4))
		if glow < 0.05:
			continue
		var p := Vector2(roundf(cx + sx), roundf(sy))
		draw_circle(p, 7, Color(0.8, 1, 0.5, 0.12 * glow))
		draw_rect(Rect2(p.x - 1, p.y - 1, 2, 2), Color(0.9, 1, 0.6, glow))

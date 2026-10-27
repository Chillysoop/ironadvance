extends Node2D
## Parallax sky, three silhouette layers and the animated water line.

@onready var b: Battle = get_parent()
var sky: Texture2D
var layers: Array = []  # [texture, parallax, y]

func setup(theme: String) -> void:
	sky = load("res://assets/bg/%s_sky.png" % theme)
	layers = [
		[load("res://assets/bg/%s_far.png" % theme), 0.12, 360.0],
		[load("res://assets/bg/%s_mid.png" % theme), 0.3, 392.0],
		[load("res://assets/bg/%s_near.png" % theme), 0.5, 420.0],
	]

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	if sky == null:
		return
	var cx := b.cam_x
	draw_texture_rect(sky, Rect2(cx - 8, -8, Battle.W + 16, Battle.H + 16), false)
	for L in layers:
		var tx: Texture2D = L[0]
		var par: float = L[1]
		var w := tx.get_width() * Art.PX
		var hgt := tx.get_height() * Art.PX
		var off := fmod(cx * par, w)
		var x := cx - off - 8
		while x < cx + Battle.W + 8:
			draw_texture_rect(tx, Rect2(roundf(x), L[2] - hgt, w, hgt), false)
			x += w
	var th: Dictionary = Data.THEMES[b.theme]
	var wy := float(Battle.WATER_Y)
	draw_rect(Rect2(cx - 8, wy, Battle.W + 16, Battle.H - wy + 8), th.water[0])
	var x2 := floorf(cx / 8) * 8 - 8
	while x2 < cx + Battle.W + 8:
		var yy := wy + roundf(sin(x2 / 23.0 + b.t / 18.0) * 2)
		draw_rect(Rect2(x2, yy, 8, 3), th.water[1])
		if int(x2 / 8) % 5 == 0:
			draw_rect(Rect2(x2 + 2, yy + 8 + roundf(sin(x2 + b.t / 30.0) * 2), 4, 1), th.water[1])
		x2 += 8

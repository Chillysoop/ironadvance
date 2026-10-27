extends Node
## Loads generated sprite sheets and fonts, and knows how to draw a character frame.

const PX := 2.0  # one art pixel = 2 world units

var meta := {}
var tex := {}
var font: Font      # Press Start 2P, for numbers and stencil labels
var font_b: Font    # VT323, for body text

func _ready() -> void:
	var f := FileAccess.open("res://assets/sprites/meta.json", FileAccess.READ)
	meta = JSON.parse_string(f.get_as_text())
	for k in meta:
		tex[k] = load("res://assets/sprites/%s.png" % k)
		if meta[k].has("gun_pivot"):
			tex[k + "_gun"] = load("res://assets/sprites/%s_gun.png" % k)
			tex[k + "_gun_w"] = load("res://assets/sprites/%s_gun_w.png" % k)
	for n in ["pow", "boss", "boss_barrel", "barrel", "barrel_w", "fuel", "fuel_w", "charge", "charge_w", "sandbags", "crate", "crate_w", "explosion", "muzzle", "puff", "slash", "parachute"]:
		tex[n] = load("res://assets/sprites/%s.png" % n)
	for n in ["panel", "hazard", "card", "tag", "bulb_off", "bulb_g", "bulb_y", "bulb_r"]:
		tex["ui_" + n] = load("res://assets/ui/%s.png" % n)
	for n in ["bolt", "heart", "flame", "coin", "skull", "shield", "radio", "star", "up", "card", "boot", "cross"]:
		tex["ic_" + n] = load("res://assets/ui/ic_%s.png" % n)
	font = load("res://assets/fonts/PressStart2P.woff")
	font_b = load("res://assets/fonts/VT323.woff")
	for fo in [font, font_b]:
		fo.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		fo.hinting = TextServer.HINTING_NONE
		fo.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED

func anim_info(sheet: String, anim: String) -> Dictionary:
	return meta[sheet].anims.get(anim, meta[sheet].anims.idle)

func draw_char(ci: CanvasItem, sheet: String, anim: String, frame: int, pos: Vector2, face: int, white := false, rot := 0.0, alpha := 1.0, gun_angle := 0.0, show_gun := true, scale := 1.0, tint := Color.WHITE) -> void:
	## Draws a body frame anchored at the feet, plus the arm+gun layer rotated to gun_angle
	## (radians, measured in the facing direction: 0 = straight ahead, negative = up).
	var m: Dictionary = meta[sheet]
	var info: Dictionary = m.anims.get(anim, m.anims.idle)
	var n: int = info.n
	var fi: int = frame % n
	var fw: int = m.frame[0]
	var fh: int = m.frame[1]
	var row: int = info.row + (m.flash_row_offset if white else 0)
	var src := Rect2(fi * fw, row * fh, fw, fh)
	var ax: float = m.anchor[0]
	var ay: float = m.anchor[1]
	var s := PX * scale
	ci.draw_set_transform(pos, rot, Vector2(s * face, s))
	var mod := Color(tint.r, tint.g, tint.b, alpha)
	ci.draw_texture_rect_region(tex[sheet], Rect2(-ax, -ay, fw, fh), src, mod)
	if show_gun and info.gun[fi] and m.has("gun_pivot"):
		var sh: Array = info.shoulder[fi]
		var gp: Array = m.gun_pivot
		var gt: Texture2D = tex[sheet + ("_gun_w" if white else "_gun")]
		var shoulder := Vector2(sh[0] - ax, sh[1] - ay)
		# draw in the unit's local (already mirrored) space, rotate around the shoulder
		var xf := Transform2D(rot, Vector2(s * face, s), 0.0, pos)
		xf = xf * Transform2D(gun_angle, shoulder)
		ci.draw_set_transform_matrix(xf)
		ci.draw_texture_rect(gt, Rect2(-gp[0], -gp[1], gt.get_width(), gt.get_height()), false, mod)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

func muzzle_offset(sheet: String, anim: String, frame: int, gun_angle: float) -> Vector2:
	## Muzzle position relative to the feet, in world units, for a unit facing right.
	var m: Dictionary = meta[sheet]
	if not m.has("gun_pivot"):
		return Vector2(14, -20)
	var info: Dictionary = m.anims.get(anim, m.anims.idle)
	var fi: int = frame % int(info.n)
	var sh: Array = info.shoulder[fi]
	var gt: Texture2D = tex[sheet + "_gun"]
	var gp: Array = m.gun_pivot
	var tip := Vector2(gt.get_width() - gp[0] - 1, 0).rotated(gun_angle)
	return (Vector2(sh[0] - m.anchor[0], sh[1] - m.anchor[1]) + tip) * PX

func text(ci: CanvasItem, s: String, pos: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, outline := 2, body := false, alpha := 1.0) -> void:
	## Pixel text with a hard dark outline and drop shadow, Metal Slug HUD style.
	var fo: Font = font_b if body else font
	var w := fo.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w / 2.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	var p := Vector2(round(x), round(pos.y))
	var dark := Color(0.05, 0.03, 0.02, alpha)
	if outline > 0:
		ci.draw_string_outline(fo, p + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline + 1, dark)
		ci.draw_string_outline(fo, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, dark)
	ci.draw_string(fo, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col, col.a * alpha))

func text_width(s: String, size: int, body := false) -> float:
	return (font_b if body else font).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

func draw_tags(ci: CanvasItem, pos: Vector2, n: int, sc := 1.0, total := -1) -> void:
	## Dog tags left: bright for each tag still worn, dark for each one spent.
	for i in (Data.DOG_TAGS if total < 0 else total):
		var p := pos + Vector2(i * 7 * sc, 0)
		ci.draw_rect(Rect2(p, Vector2(6, 8) * sc), Color(0.05, 0.035, 0.03))
		ci.draw_rect(Rect2(p + Vector2(1, 1) * sc, Vector2(4, 6) * sc), Color("d8dde4") if i < n else Color("3b3f45"))
		ci.draw_rect(Rect2(p + Vector2(2, 2) * sc, Vector2(2, 1) * sc), Color(0.05, 0.035, 0.03) if i < n else Color("2a2e34"))

func draw_gate(ci: CanvasItem, c: Vector2, r: float, t: int, chev := 0, open := 0.0, alpha := 1.0, spin := 0.0, burst := 0.0) -> void:
	## The captured Jackal gate: a steel ring on a plinth, nine chevrons that lock one by one
	## while the glyph track spins, and a rippling blue horizon once it opens.
	var a := alpha
	var dark := Color(0.05, 0.035, 0.03, a)
	# plinth
	ci.draw_rect(Rect2(c.x - r * 0.7, c.y + r - 2, r * 1.4, 10), dark)
	ci.draw_rect(Rect2(c.x - r * 0.7 + 2, c.y + r, r * 1.4 - 4, 6), Color(0.35, 0.37, 0.4, a))
	ci.draw_rect(Rect2(c.x - r * 0.5, c.y + r + 6, r, 6), Color(0.27, 0.28, 0.31, a))
	# horizon
	if open > 0.0:
		var hr := (r - 7) * open
		ci.draw_circle(c, hr, Color(0.12, 0.38, 0.72, a * 0.95))
		for k in 4:
			var rr := hr * (0.2 + 0.24 * k + 0.05 * sin(t / 9.0 + k * 1.7))
			ci.draw_arc(c, rr, 0, TAU, 40, Color(0.56, 0.9, 1.0, a * (0.55 - k * 0.1)), 2.0)
		for k in 10:
			var ang := k * 2.4 + t / 30.0
			var d := hr * (0.3 + 0.6 * fposmod(k * 0.37 + t / 70.0, 1.0))
			ci.draw_rect(Rect2(c.x + cos(ang) * d, c.y + sin(ang) * d, 2, 2), Color(0.85, 0.98, 1.0, a * 0.8))
	if burst > 0.0:
		ci.draw_circle(c, (r - 7) * (1.0 + burst * 0.7), Color(0.6, 0.92, 1.0, a * burst * 0.55))
	# ring: dark rim, steel body, glyph track
	ci.draw_arc(c, r, 0, TAU, 56, dark, 14.0)
	ci.draw_arc(c, r, 0, TAU, 56, Color(0.42, 0.45, 0.5, a), 10.0)
	ci.draw_arc(c, r - 3, 0, TAU, 56, Color(0.3, 0.32, 0.36, a), 3.0)
	for k in 36:
		var ang := spin + k * TAU / 36.0
		var p := c + Vector2(cos(ang), sin(ang)) * (r - 1)
		ci.draw_rect(Rect2(p.x - 1, p.y - 1, 2, 2), Color(0.62, 0.66, 0.72, a))
	# chevrons, locked from the top clockwise
	for k in 9:
		var ang := -PI / 2 + k * TAU / 9.0
		var p := c + Vector2(cos(ang), sin(ang)) * (r + 4)
		var lit := k < chev
		ci.draw_rect(Rect2(p.x - 4, p.y - 4, 8, 8), dark)
		ci.draw_rect(Rect2(p.x - 3, p.y - 3, 6, 6), Color(1.0, 0.48, 0.24, a) if lit else Color(0.36, 0.24, 0.18, a))
		if lit:
			ci.draw_rect(Rect2(p.x - 1, p.y - 1, 2, 2), Color(1.0, 0.9, 0.6, a))

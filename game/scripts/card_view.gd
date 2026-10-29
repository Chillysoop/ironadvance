class_name CardView
extends Control
## A pixel field card. Shows a deck card, a stat boost, an ability, gear or a
## shop service. Emits `pressed` when clicked.

signal pressed

var opt: Dictionary = {}     # {kind: card|stat|perk|gear|service, ...}
var cost := -1
var selected := false
var disabled := false
var supercharged := false
var hand_mode := false       # cards in hand peek up from the bottom edge and rise on hover
var label_top := ""          # small caption above the card (e.g. "TO MOSS'S DECK")
var price := -1
var sold := false            # shop only: greyed out with a SOLD stamp
var stamp := ""              # a stamp across the card like SOLD (e.g. REMOVED when you leave a vehicle)
var hotkey := ""
var hover := false
var ghost := false           # hand only: a card is armed, so the hand sinks out of the way of the aim
var lift := 0.0
var base_y := 0.0
var chain := ""              # signature chain this card would complete right now (hand only)
var badge := ""              # small purple pill on the top-right corner (e.g. fusion progress "2/3")
var corner := ""             # tiny origin tag at the bottom-left (SHOP, LVL, GUN)
var no_move := false         # hand only: Hop or Drill with no movement left, crossed out
var peek := 0.0              # hand only: how much of the card shows when the next card overlaps it (0 = all)
var cropped := ""            # the full text when the body didn't fit; hovering shows it (outside battle)
var tip: Control = null

const PAPER := Color("e4d6b0")
const PAPER_D := Color("bba57c")
const INK := Color("1c1410")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): hover = true; queue_redraw())
	mouse_exited.connect(func(): hover = false; queue_redraw())

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if disabled:
			Sfx.play("deny")
		else:
			pressed.emit()
		accept_event()

func _process(_d: float) -> void:
	var want_tip := hover and cropped != "" and not hand_mode and is_visible_in_tree()
	if want_tip and tip == null:
		tip = CardTip.new()
		tip.text = cropped
		add_child(tip)
	elif not want_tip and tip != null:
		tip.queue_free()
		tip = null
	if tip != null:
		tip.place(get_global_rect())
	if hand_mode:
		# cards you can't pay for sink and grey out so the playable ones stand up
		# a hovered card rises all the way even when you can't play it, so its text can be read
		var target := -60.0 if hover or selected else (14.0 if disabled else 0.0)
		if selected:
			target = -64.0
		if ghost:
			target = 0.0 if selected else 30.0
		lift = lerpf(lift, target, 0.3)
		position.y = base_y + roundf(lift)
		# the hovered or armed card draws over its neighbours in a crowded hand
		z_index = 2 if hover or selected else 0
	queue_redraw()

func type_color() -> Color:
	match opt.get("kind", "card"):
		"card":
			var c := Data.card(opt)
			if c.get("od", false) or opt.get("od", false):
				return Color("ffb23e")
			return Data.TYPES[c.type].c
		"stat":
			return Color("9fb4c9")
		"perk":
			return Color("ffd23a")
		"gear":
			return Color("62d26f")
		"item":
			return {"weapon": Color("ff7a3d"), "armor": Color("9fb4c9"), "kit": Color("53d4e2"), "belt": Color("62d26f")}.get(Data.ITEMS[opt.item.id].slot, Color("b48cff"))
	return Color("b48cff")

func tier() -> int:
	match opt.get("kind", "card"):
		"card":
			return Data.tier_of(opt)
		"stat", "perk", "gear", "item":
			return opt.get("tier", -1)
	return -1

func draw_rarity(w: float, h: float, t: int, dim: bool) -> void:
	## Rarity frame: colored border and gem, a shine sweep on Epic+, sparks on Legendary.
	var rc := Data.tier_color(t)
	if dim:
		rc = rc.darkened(0.5)
	if t >= 1:
		draw_rect(Rect2(-2, -2, w + 4, h + 2), rc, false, 2.0)
	draw_rect(Rect2(1, h - 6, w - 2, 3), rc)
	var g := Vector2(w - 9, 8)
	draw_colored_polygon(PackedVector2Array([g + Vector2(0, -5), g + Vector2(5, 0), g + Vector2(0, 5), g + Vector2(-5, 0)]), INK)
	draw_colored_polygon(PackedVector2Array([g + Vector2(0, -4), g + Vector2(4, 0), g + Vector2(0, 4), g + Vector2(-4, 0)]), rc)
	draw_rect(Rect2(g.x - 1, g.y - 2, 1, 1), Color(1, 1, 1, 0.8))
	if dim:
		return
	var ms := Time.get_ticks_msec()
	if t >= 3 and t != Data.OD_TIER:
		var k := fmod(ms / 1400.0, 1.6) - 0.3
		var x := k * (w + 40) - 20
		var pts := PackedVector2Array()
		for p in [Vector2(x, 2), Vector2(x + 10, 2), Vector2(x - 10, h - 4), Vector2(x - 20, h - 4)]:
			pts.append(Vector2(clampf(p.x, 1, w - 1), p.y))
		if pts[1].x - pts[0].x > 0.5 or pts[2].x - pts[3].x > 0.5:
			draw_colored_polygon(pts, Color(1, 1, 1, 0.22))
	if t == Data.TIER_MAX:
		for i in 5:
			var ph := fmod(ms / 700.0 + i * 0.37, 1.0)
			var a := sin(ph * PI)
			var px := Terrain.hash2(i, int(ms / 700.0 + i * 0.37)) * w
			var py := Terrain.hash2(i + 7, int(ms / 700.0 + i * 0.37)) * (h - 4)
			draw_rect(Rect2(px - 1, py, 3, 1), Color(1, 0.9, 0.5, a))
			draw_rect(Rect2(px, py - 1, 1, 3), Color(1, 0.9, 0.5, a))

func _draw() -> void:
	var w := size.x
	var h := size.y
	var col := type_color()
	# a priced card you can't buy greys out like an unplayable hand card
	var dim := disabled and (hand_mode or price >= 0 or sold)
	# frame
	draw_rect(Rect2(1, 2, w - 2, h - 2), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(0, 0, w, h - 2), INK)
	var paper := PAPER if not dim else Color("8a8070")
	if opt.get("kind", "card") == "perk":
		paper = Color("efe2b8") if not dim else paper
	draw_rect(Rect2(1, 1, w - 2, h - 4), paper)
	draw_rect(Rect2(1, h - 6, w - 2, 3), PAPER_D)
	for i in 14:
		var px := 4 + int(Terrain.hash2(i, 3) * (w - 8))
		var py := 20 + int(Terrain.hash2(i, 9) * (h - 30))
		draw_rect(Rect2(px, py, 1, 1), PAPER_D)
	# type band
	draw_rect(Rect2(1, 1, w - 2, 14), col.darkened(0.15) if not dim else col.darkened(0.5))
	draw_rect(Rect2(1, 1, w - 2, 2), col.lightened(0.3))
	draw_rect(Rect2(1, 15, w - 2, 1), INK)
	var title := ""
	var name_ := ""
	var stat := ""
	var body := ""
	var kind: String = opt.get("kind", "card")
	match kind:
		"card":
			var c := Data.card(opt)
			title = "OVERDRIVE" if c.get("od", false) else c.type
			name_ = c.name
			stat = Data.stat_line(c)
			body = c.text
			if c.get("mod_names", []).size():
				body = "[%s] %s" % [", ".join(c.mod_names), body]
		"stat":
			title = "STAT BOOST"; name_ = opt.name; body = opt.text
		"perk":
			title = opt.get("title", "ABILITY" if not opt.has("ptier") else Data.PERK_TIER[opt.ptier])
			name_ = opt.name; body = opt.text
		"gear":
			title = "SQUAD GEAR"; name_ = opt.name; body = opt.text
		"item":
			var it: Dictionary = opt.item
			var d: Dictionary = Data.ITEMS[it.id]
			title = Data.SLOT_NAMES[d.slot]
			name_ = d.name
			stat = "  ".join(Data.stat_lines(Data.item_stats(it)))
			body = d.text
			if d.has("set"):
				body += " SET: %s." % Data.SETS[d.set].name
			var evo := Data.evolve_hint(it.id)
			if evo != "":
				body += " " + evo
		"service":
			title = opt.get("title", "SERVICE"); name_ = opt.name; body = opt.text
	if compact():
		draw_compact(kind, title, name_, dim)
		return
	Art.text(self, title, Vector2(w / 2.0, 12), 8, Color.WHITE if not dim else Color("cccccc"), HORIZONTAL_ALIGNMENT_CENTER, 1)
	# cost bubble
	if kind == "card":
		var cc := cost if cost >= 0 else int(Data.card(opt).cost)
		draw_circle(Vector2(10, 24), 9, INK)
		draw_circle(Vector2(10, 24), 7, Color("ffd23a") if not dim else Color("8a7a40"))
		Art.text(self, str(cc), Vector2(10, 29), 8, INK, HORIZONTAL_ALIGNMENT_CENTER, 0)
	# vehicle cards wear a VEH tag under the cost: they only play from inside a vehicle
	if kind == "card" and Data.card(opt).get("mech", false):
		draw_rect(Rect2(2, 35, 30, 11), INK)
		draw_rect(Rect2(3, 36, 28, 9), Color("6a7a40") if not dim else Color("4a5030"))
		Art.text(self, "VEH", Vector2(17, 44), 8, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 0)
	if hotkey != "":
		Art.text(self, hotkey, Vector2(w - 8, 28), 8, Color("6a5a40"), HORIZONTAL_ALIGNMENT_RIGHT, 0)
	# pictogram
	draw_picto(kind, Vector2(w / 2.0, 44), dim)
	# name
	var y := 70.0
	for line in wrap_text(name_, w - 10, 16):
		Art.text(self, line, Vector2(w / 2.0, y), 16, INK if not dim else Color("4a4030"), HORIZONTAL_ALIGNMENT_CENTER, 0, true)
		y += 13
	if stat != "":
		draw_rect(Rect2(6, y - 6, w - 12, 1), PAPER_D)
		for sl in wrap_text(stat, w - 8, 16):
			Art.text(self, sl, Vector2(w / 2.0, y + 6), 16, Color("7a2a14") if not dim else Color("4a4030"), HORIZONTAL_ALIGNMENT_CENTER, 0, true)
			y += 12
		y += 4
	# a long body packs its lines tighter before anything is cut off
	var bl := wrap_text(body, w - 10, 16)
	var bottom := h - (22 if price >= 0 else 8)
	var cut := false
	var lh := 12.0
	if bl.size() > 1 and y + (bl.size() - 1) * lh > bottom:
		lh = maxf(10.0, floorf((bottom - y) / (bl.size() - 1)))
	for i in bl.size():
		if y > bottom:
			cut = true
			break
		var line: String = bl[i]
		if i < bl.size() - 1 and y + lh > bottom:
			line += "..."
			cut = true
		Art.text(self, line, Vector2(w / 2.0, y + 2), 16, Color("3a3024") if not dim else Color("4a4030"), HORIZONTAL_ALIGNMENT_CENTER, 0, true)
		y += lh
	cropped = (name_ + "\n" + (stat + "\n" if stat != "" else "") + body) if cut else ""
	if supercharged and not dim:
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 150.0)
		draw_rect(Rect2(0, 0, w, h - 2), Color(1, 0.48, 0.24, pulse), false, 2.0)
		Art.text(self, "PUMPED", Vector2(w - 6, 26), 8, Color("ff7a3d"), HORIZONTAL_ALIGNMENT_RIGHT, 1)
	if selected:
		draw_rect(Rect2(-2, -2, w + 4, h + 2), Color("ffd23a"), false, 2.0)
	elif hover and not dim:
		draw_rect(Rect2(-1, -1, w + 2, h), Color(1, 1, 1, 0.8), false, 1.0)
	var t := tier()
	if t >= 0:
		draw_rarity(w, h, t, dim)
		if not hand_mode and t != Data.OD_TIER:
			Art.text(self, Data.tier_name(t), Vector2(w / 2.0, h + 10), 8, Data.tier_color(t), HORIZONTAL_ALIGNMENT_CENTER, 1)
	if hand_mode and not dim and cost == 0 and kind == "card" and not selected:
		var pulse := 0.35 + 0.25 * sin(Time.get_ticks_msec() / 220.0)
		draw_rect(Rect2(0, 0, w, h - 2), Color(0.38, 0.82, 0.44, pulse), false, 1.0)
	if chain != "" and not dim:
		var cp := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
		draw_rect(Rect2(-2, -2, w + 4, h + 2), Color(0.88, 0.69, 1.0, cp), false, 2.0)
		draw_rect(Rect2(0, -14, w, 12), Color(0.2, 0.1, 0.3, 0.9))
		Art.text(self, chain, Vector2(w / 2.0, -4), 8, Color("e0b0ff"), HORIZONTAL_ALIGNMENT_CENTER)
	if price >= 0:
		draw_rect(Rect2(w / 2.0 - 26, h - 16, 52, 16), INK)
		draw_texture_rect(Art.tex.ic8_coin, Rect2(w / 2.0 - 22, h - 12, 8, 8), false)
		Art.text(self, str(price), Vector2(w / 2.0 + 8, h - 4), 8, Color("ffd23a") if not disabled else Color("8a7a40"), HORIZONTAL_ALIGNMENT_CENTER, 0)
	if corner != "":
		Art.text(self, corner, Vector2(1, -3), 8, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 1)
	if badge != "":
		var bw := Art.text_width(badge, 8) + 8
		draw_rect(Rect2(w - bw + 4, -7, bw, 13), INK)
		draw_rect(Rect2(w - bw + 5, -6, bw - 2, 11), Color("8b63d9"))
		Art.text(self, badge, Vector2(w + 4 - bw / 2.0, 4), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 1)
	if label_top != "":
		Art.text(self, label_top, Vector2(w / 2.0, -6), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
	if no_move:
		# a big red X and the reason, so nobody wonders why Hop or Drill won't play
		for k in [-1.0, 0.0, 1.0]:
			draw_line(Vector2(8 + k, 20), Vector2(w - 8 + k, h - 12), Color("c0392b"), 2.0)
			draw_line(Vector2(w - 8 + k, 20), Vector2(8 + k, h - 12), Color("c0392b"), 2.0)
		draw_rect(Rect2(4, 17, w - 8, 15), INK)
		Art.text(self, "NO MOVE LEFT", Vector2(w / 2.0, 28), 8, Color("ff7a5c"), HORIZONTAL_ALIGNMENT_CENTER, 0)
	if sold or stamp != "":
		draw_rect(Rect2(1, 1, w - 2, h - 4), Color(0.08, 0.06, 0.05, 0.55))
		draw_rect(Rect2(8, h / 2.0 - 12, w - 16, 22), INK)
		draw_rect(Rect2(10, h / 2.0 - 10, w - 20, 18), Color("8a3a2a"))
		var st := "SOLD" if sold else stamp
		var fs := 16 if Art.text_width(st, 16) < w - 24 else 8
		Art.text(self, st, Vector2(w / 2.0, h / 2.0 + (4 if fs == 16 else 2)), fs, Color("e4d6b0"), HORIZONTAL_ALIGNMENT_CENTER, 1)
	elif disabled and price >= 0 and hover and Run.scrip < price:
		var sh := "SHORT BY %d" % (price - Run.scrip)
		var sw := Art.text_width(sh, 8) + 10
		draw_rect(Rect2(w / 2.0 - sw / 2.0, h - 30, sw, 13), INK)
		Art.text(self, sh, Vector2(w / 2.0, h - 20), 8, Color("ff7a5c"), HORIZONTAL_ALIGNMENT_CENTER, 0)

func compact() -> bool:
	## A crowded hand overlaps its cards; each one shows only its left strip until it's hovered.
	return hand_mode and peek > 0.0 and peek < size.x - 4 and not hover and not selected

func draw_compact(kind: String, title: String, name_: String, dim: bool) -> void:
	## The strip of an overlapped hand card: cost, type and the full name wrapped into the part
	## that shows, so every card in a big hand can be told apart at a glance.
	var pw := peek
	var tw := pw - 6
	var tt := title
	while tt.length() > 1 and Art.text_width(tt, 8) > tw:
		tt = tt.left(tt.length() - 1)
	if kind == "card" and Data.card(opt).get("mech", false):
		tt = "VEH"
	Art.text(self, tt, Vector2(4, 12), 8, Color.WHITE if not dim else Color("cccccc"), HORIZONTAL_ALIGNMENT_LEFT, 1)
	if kind == "card":
		var cc := cost if cost >= 0 else int(Data.card(opt).cost)
		draw_circle(Vector2(10, 24), 9, INK)
		draw_circle(Vector2(10, 24), 7, Color("ffd23a") if not dim else Color("8a7a40"))
		Art.text(self, str(cc), Vector2(10, 29), 8, INK, HORIZONTAL_ALIGNMENT_CENTER, 0)
	if hotkey != "":
		Art.text(self, hotkey, Vector2(pw - 4, 28), 8, Color("6a5a40"), HORIZONTAL_ALIGNMENT_RIGHT, 0)
	var y := 45.0
	for line in wrap_text(name_, tw, 16):
		var ln: String = line
		while ln.length() > 1 and Art.text_width(ln, 16, true) > tw:
			ln = ln.left(ln.length() - 1)
		Art.text(self, ln, Vector2(4, y), 16, INK if not dim else Color("4a4030"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		y += 12
	if supercharged and not dim:
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 150.0)
		draw_rect(Rect2(0, 0, size.x, size.y - 2), Color(1, 0.48, 0.24, pulse), false, 2.0)
	var t := tier()
	if t >= 0:
		draw_rarity(size.x, size.y, t, dim)
	if not dim and cost == 0 and kind == "card":
		var pulse := 0.35 + 0.25 * sin(Time.get_ticks_msec() / 220.0)
		draw_rect(Rect2(0, 0, size.x, size.y - 2), Color(0.38, 0.82, 0.44, pulse), false, 1.0)
	if chain != "" and not dim:
		var cp := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
		draw_rect(Rect2(-2, -2, size.x + 4, size.y + 2), Color(0.88, 0.69, 1.0, cp), false, 2.0)
	if no_move:
		draw_line(Vector2(4, 18), Vector2(pw - 4, 66), Color("c0392b"), 2.0)
		draw_line(Vector2(pw - 4, 18), Vector2(4, 66), Color("c0392b"), 2.0)

func draw_picto(kind: String, c: Vector2, dim: bool) -> void:
	var mod := Color(1, 1, 1, 0.45 if dim else 1.0)
	var icon := ""
	if kind == "card":
		var cd := Data.card(opt)
		match cd.type:
			"AIM":
				var gun := "sq_moss_gun" if cd.get("pierce", false) else ("sq_hex_gun" if cd.key in ["pistol", "sa_pistol"] else "sq_rook_gun")
				if cd.key in ["hmg", "burst", "mounted"]:
					gun = "en_mg_gun"
				var tx: Texture2D = Art.tex[gun]
				draw_texture_rect(tx, Rect2(c.x - tx.get_width(), c.y - tx.get_height(), tx.get_width() * 2, tx.get_height() * 2), false, mod)
				return
			"ARC":
				draw_rect(Rect2(c.x - 7, c.y - 7, 14, 14), INK)
				draw_rect(Rect2(c.x - 6, c.y - 6, 12, 12), Color("4a6a2a") if not cd.get("smoke", false) else Color("9aa0a8"))
				draw_rect(Rect2(c.x - 2, c.y - 11, 4, 5), INK)
				draw_rect(Rect2(c.x - 4, c.y - 4, 3, 3), Color(1, 1, 1, 0.5))
				return
			"LINE":
				if cd.get("drill", false):
					draw_colored_polygon(PackedVector2Array([Vector2(c.x - 6, c.y - 8), Vector2(c.x + 14, c.y), Vector2(c.x - 6, c.y + 8)]), INK)
					draw_colored_polygon(PackedVector2Array([Vector2(c.x - 5, c.y - 6), Vector2(c.x + 11, c.y), Vector2(c.x - 5, c.y + 6)]), Color("a9b0b6").darkened(0.5 if dim else 0.0))
					for k in 3:
						draw_line(Vector2(c.x - 2 + k * 5, c.y - 5 + k * 1.6), Vector2(c.x + 1 + k * 5, c.y + 5 - k * 1.6), INK, 1.0)
					draw_rect(Rect2(c.x - 15, c.y - 5, 10, 10), INK)
					draw_rect(Rect2(c.x - 14, c.y - 4, 8, 8), Color("ffb23e").darkened(0.5 if dim else 0.0))
					return
				if cd.get("grapple", false) or cd.get("jump", false) or cd.get("rush", false) or cd.get("roll", false):
					icon = "ic_boot" if not cd.get("grapple", false) else "ic_up"
				else:
					draw_rect(Rect2(c.x - 15, c.y - 4, 26, 8), INK)
					draw_rect(Rect2(c.x - 14, c.y - 3, 22, 6), Color("d8d0b8"))
					draw_rect(Rect2(c.x + 6, c.y - 3, 4, 6), Color("ff4d3d"))
					draw_rect(Rect2(c.x - 20, c.y - 2, 6, 4), Color("ffb23e"))
					return
			"MELEE":
				draw_texture_rect_region(Art.tex.slash, Rect2(c.x - 15, c.y - 15, 30, 30), Rect2(20, 0, 20, 20), Color(0.2, 0.15, 0.1, mod.a))
				return
			"ALLY":
				icon = "ic_cross"
			"SELF":
				icon = "ic_shield" if cd.has("armor") else ("ic_flame" if cd.has("adrenal") or cd.get("surge", false) else ("ic_star" if cd.has("rally") or cd.get("overwatch", false) else "ic_boot"))
	else:
		if kind == "item":
			var d: Dictionary = Data.ITEMS[opt.item.id]
			if d.slot == "weapon":
				var sub := CardView.new()
				sub.opt = {"kind": "card", "key": d.cards[0]}
				var tmp := opt
				opt = sub.opt
				draw_picto("card", c, dim)
				opt = tmp
				sub.free()
				return
			icon = {"armor": "ic_shield", "kit": "ic_star", "belt": Data.BELT_ICONS.get(d.get("use", ""), "ic_heart")}.get(d.slot, "ic_card")
		else:
			icon = {"stat": "ic_up", "perk": "ic_star", "gear": "ic_shield", "service": "ic_heart"}.get(kind, "ic_card")
		if opt.has("icon"):
			icon = opt.icon
		if opt.has("soldier"):
			# a barracks soldier: their own figure instead of an icon
			Art.draw_char(self, Art.look_sheet(opt.soldier), "idle", 0, Vector2(c.x, c.y + 14), 1, false, 0, mod.a, 0, false, 0.8)
			return
	if icon != "":
		draw_texture_rect(Art.tex[icon], Rect2(c.x - 16, c.y - 16, 32, 32), false, mod)

static func wrap_text(s: String, width: float, size: int) -> Array:
	var out: Array = []
	var line := ""
	for word in s.split(" "):
		var t := word if line == "" else line + " " + word
		if Art.text_width(t, size, true) > width and line != "":
			out.append(line)
			line = word
		else:
			line = t
	if line != "":
		out.append(line)
	return out

class CardTip extends Control:
	## The whole text of a card whose body was cut short, beside the card while it's hovered.
	var text := ""
	var lines: Array = []
	const W := 240.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_level = true
		z_index = 100
		for para in text.split("\n"):
			lines.append_array(CardView.wrap_text(para, W - 16, 16))
		size = Vector2(W, lines.size() * 14 + 14)
	func place(card: Rect2) -> void:
		var x := card.end.x + 6 if card.end.x + 6 + W <= 956 else card.position.x - 6 - W
		position = Vector2(clampf(x, 4, 956 - W), clampf(card.position.y, 4, 536 - size.y))
	func _draw() -> void:
		draw_rect(Rect2(Vector2(-1, -1), size + Vector2(2, 2)), Color(0.05, 0.035, 0.03))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.11, 0.13, 0.97))
		draw_rect(Rect2(0, 0, size.x, 2), Color("ffd23a"))
		for i in lines.size():
			Art.text(self, lines[i], Vector2(8, 16 + i * 14), 16, Color("ffd23a") if i == 0 else Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)

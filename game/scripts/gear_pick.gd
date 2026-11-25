extends Control
## The mid-level gear choice: who gets the find, what they wear now, what's new and what it
## swaps out. Left: the squad tabs and the chosen soldier's four slots. Middle: the NEW item next
## to whatever COMES OFF, and what changes. Right: one row per slot it can go in, plus SEND TO STASH.
## AUTO-EQUIP picks the soldier and slot that suit the find best for their class.
## Lives in the HUD's modal box; hud.gear_pick() waits on its `chose` signal.

signal chose(idx: int)

const INK := Color(0.05, 0.035, 0.03)
const PANEL := Rect2(30, 54, 900, 446)
const ROW_X := 600.0
const ROW_W := 314.0
const ROW_H := 50.0
const ROW_Y := 132.0
const SLOT_LABEL := {"weapon": "WEAPON", "armor": "ARMOR", "kit1": "KIT 1", "kit2": "KIT 2"}

var title := ""
var it: Dictionary = {}
var units: Array = []        # alive squad Units who could take it
var finder = null            # the Unit who found it (or null for a supply drop)
var who := 0                 # index into units
var rows: Array = []         # [{slot, old, gain}] for the current soldier; slot "" = send to stash
var hover_row := -1
var hover_tab := -1
var best := {}               # {u, slot} the AUTO button would pick
var new_card: CardView
var old_card: CardView
var auto_btn
var shown_row := -2

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	new_card = CardView.new()
	new_card.opt = Run.item_opt(it, "")
	new_card.size = Vector2(132, 176)
	new_card.position = Vector2(274, 150)
	new_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(new_card)
	old_card = CardView.new()
	old_card.size = Vector2(132, 176)
	old_card.position = Vector2(448, 150)
	old_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	old_card.visible = false
	add_child(old_card)
	best = auto_pick()
	if finder != null and units.has(finder):
		who = units.find(finder)
	build_rows()
	var HudScript = load("res://scripts/hud.gd")
	auto_btn = HudScript.PixButton.new()
	auto_btn.text = "AUTO-EQUIP"
	auto_btn.sub = "A"
	auto_btn.color = Color("62d26f")
	auto_btn.size = Vector2(ROW_W, 32)
	auto_btn.position = Vector2(ROW_X, PANEL.end.y - 46)
	auto_btn.pressed.connect(press_auto)
	add_child(auto_btn)

func cur_u():
	return units[who] if who < units.size() else null

func auto_pick() -> Dictionary:
	## The soldier and slot where this find helps most for their class; {} when nobody gains.
	var out := {}
	var top := 0.05
	for u in units:
		var b := Run.best_slot(u.s, it)
		# the finder gets a small nudge so a tie keeps it where it was found
		var g: float = b.gain + (0.01 if u == finder else 0.0)
		if b.slot != "" and g > top:
			top = g
			out = {"u": u, "slot": b.slot}
	return out

func build_rows() -> void:
	rows = []
	var u = cur_u()
	if u != null:
		var group: String = Data.ITEMS[it.id].slot
		var mine := Run.gear_score(u.s, it)
		for slot in (["kit1", "kit2"] if group == "kit" else [group]):
			var old = u.s.equip[slot]
			rows.append({"slot": slot, "old": old, "gain": mine - Run.gear_score(u.s, old)})
	rows.append({"slot": "", "old": null, "gain": 0.0})
	hover_row = -1
	shown_row = -2

func result(idx: int) -> Dictionary:
	## What a pick means: {u, slot}; slot "" sends the find to the stash.
	if idx < 0 or idx >= rows.size():
		return {"u": cur_u(), "slot": ""}
	return {"u": cur_u(), "slot": rows[idx].slot}

func press_auto() -> void:
	Sfx.play("coin")
	if best.is_empty():
		chose.emit(rows.size() - 1)
		return
	who = units.find(best.u)
	build_rows()
	for i in rows.size():
		if rows[i].slot == best.slot:
			chose.emit(i)
			return

func row_rect(i: int) -> Rect2:
	return Rect2(ROW_X, ROW_Y + i * (ROW_H + 6), ROW_W, ROW_H)

func tab_rect(i: int) -> Rect2:
	var per := 5
	return Rect2(48 + (i % per) * 42, 110 + (i / per) * 50, 40, 36)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var m: Vector2 = ev.position
		hover_row = -1
		hover_tab = -1
		for i in rows.size():
			if row_rect(i).has_point(m):
				hover_row = i
		for i in units.size():
			if tab_rect(i).has_point(m):
				hover_tab = i
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		for i in units.size():
			if tab_rect(i).has_point(ev.position) and i != who:
				Sfx.play("click")
				who = i
				build_rows()
				return
		for i in rows.size():
			if row_rect(i).has_point(ev.position):
				Sfx.play("coin")
				chose.emit(i)
				return

func _unhandled_key_input(ev: InputEvent) -> void:
	if not is_visible_in_tree() or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	if ev.keycode == KEY_A:
		get_viewport().set_input_as_handled()
		press_auto()
	elif ev.keycode >= KEY_1 and ev.keycode < KEY_1 + rows.size():
		get_viewport().set_input_as_handled()
		chose.emit(ev.keycode - KEY_1)
	elif ev.keycode == KEY_TAB and units.size() > 1:
		get_viewport().set_input_as_handled()
		who = (who + 1) % units.size()
		build_rows()

func focus_row() -> int:
	## The row the middle and the loadout describe: the hovered one, else the best one here.
	if hover_row >= 0:
		return hover_row
	var u = cur_u()
	if not best.is_empty() and best.u == u:
		for i in rows.size():
			if rows[i].slot == best.slot:
				return i
	return rows.size() - 1 if rows.size() == 1 else 0

func _process(_d: float) -> void:
	var f := focus_row()
	if f != shown_row:
		shown_row = f
		var old = rows[f].old if f < rows.size() else null
		old_card.visible = old != null
		if old != null:
			old_card.opt = Run.item_opt(old, "")
			old_card.queue_redraw()
	if auto_btn != null:
		auto_btn.sub = "A:  %s, %s" % [best.u.def.name, SLOT_LABEL[best.slot]] if not best.is_empty() else "A:  NOBODY GAINS, STASH IT"
	queue_redraw()

func _draw() -> void:
	Tip.clear(self)
	draw_rect(Rect2(0, 0, 960, 540), Color(0.02, 0.02, 0.04, 0.8))
	var r := PANEL
	draw_rect(r.grow(2), INK)
	draw_rect(r, Color("3a3f48"))
	draw_rect(r.grow(-3), Color("2a2e34"))
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 2), Color("6c7480"))
	var hz: Texture2D = Art.tex.ui_hazard
	var x := r.position.x
	while x < r.end.x:
		draw_texture_rect_region(hz, Rect2(x, r.position.y - 16, minf(32, r.end.x - x), 8), Rect2(0, 0, minf(32, r.end.x - x), 8))
		x += 32
	Art.text(self, title, Vector2(480, r.position.y + 26), 16, Color("ffb23e"), HORIZONTAL_ALIGNMENT_CENTER, 2)
	var u = cur_u()
	var f := focus_row()
	var fr: Dictionary = rows[f] if f < rows.size() else {}
	draw_squad(u, fr)
	draw_middle(u, fr)
	draw_rows(u, f)

func draw_squad(u, fr: Dictionary) -> void:
	## Left column: who gets it (tabs), then that soldier and the four slots they wear.
	Art.text(self, "WHO GETS IT", Vector2(48, 92), 8, Color("9aa2ae"))
	if not best.is_empty():
		draw_rect(Rect2(178, 84, 7, 7), Color("62d26f"))
		Art.text(self, "best fit", Vector2(189, 92), 16, Color("62d26f"), HORIZONTAL_ALIGNMENT_LEFT, 1, true)
	for i in units.size():
		var o = units[i]
		var tr := tab_rect(i)
		var on := i == who
		draw_rect(tr, INK)
		draw_rect(tr.grow(-1), Color("4a505a") if on else (Color("3a4048") if i == hover_tab else Color("2a2e34")))
		var m: Dictionary = Art.meta[o.sheet]
		draw_texture_rect_region(Art.tex[o.sheet], Rect2(tr.position.x + 9, tr.position.y + 2, 22, 22), Rect2(4, 2, 11, 11) if m.frame[0] == 24 else Rect2(6, 3, 11, 11))
		Art.text(self, o.def.name, Vector2(tr.position.x + 20, tr.end.y - 3), 16, Color.WHITE if on else Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER, 1, true)
		if on:
			draw_rect(tr.grow(1), Color("ffd23a"), false, 2.0)
		if not best.is_empty() and best.u == o:
			draw_rect(Rect2(tr.end.x - 9, tr.position.y + 1, 8, 8), Color("62d26f"))
		if o == finder:
			Art.text(self, "FOUND", Vector2(tr.position.x + 20, tr.position.y - 1), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 1, true)
	if u == null:
		return
	var y0 := 110.0 + ceilf(units.size() / 5.0) * 50 - 8
	var t := Time.get_ticks_msec() / 200
	Art.draw_char(self, u.sheet, "idle", t % 4, Vector2(82, y0 + 62), 1, false, 0, 1.0, 0, true, 1.6)
	Art.text(self, u.def.name, Vector2(124, y0 + 20), 16, Color.WHITE)
	Art.text(self, "%s  LV%d" % [String(u.def.cls).to_upper(), u.s.lvl], Vector2(124, y0 + 34), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 1, true)
	Art.text(self, "Likes " + Run.CLASS_FOCUS.get(u.def.key, "anything"), Vector2(124, y0 + 47), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 1, true)
	Art.text(self, "HP %d/%d   %d CARDS" % [u.hp, u.max_hp, u.s.deck.size()], Vector2(124, y0 + 60), 16, Color("c9bfa8"), HORIZONTAL_ALIGNMENT_LEFT, 1, true)
	# the four slots, the one the focused choice fills lit up
	Art.text(self, "WEARING NOW", Vector2(48, y0 + 88), 8, Color("9aa2ae"))
	var group: String = Data.ITEMS[it.id].slot
	var slots := ["weapon", "armor", "kit1", "kit2"]
	for k in 4:
		var slot: String = slots[k]
		var sr := Rect2(48 + (k % 2) * 106, y0 + 96 + (k / 2) * 46, 102, 42)
		var cur = u.s.equip[slot]
		var target: bool = fr.get("slot", "") == slot
		var fits := Data.slot_group(slot) == group
		draw_rect(sr, INK)
		draw_rect(sr.grow(-1), Color("33383f") if fits else Color("24272c"))
		Art.text(self, SLOT_LABEL[slot], Vector2(sr.position.x + 5, sr.position.y + 12), 16, Color("9aa2ae") if not fits else Color("53d4e2"), HORIZONTAL_ALIGNMENT_LEFT, 1, true)
		if target:
			# the swap, right on the slot: old one struck out, new one in green
			draw_rect(sr.grow(1), Color("62d26f"), false, 2.0)
			if cur != null:
				var on := fit(Data.item_name(cur), 92)
				Art.text(self, on, Vector2(sr.position.x + 5, sr.position.y + 24), 16, Color("ff7a6a"), HORIZONTAL_ALIGNMENT_LEFT, 1, true)
				draw_rect(Rect2(sr.position.x + 4, sr.position.y + 20, minf(Art.text_width(on, 16, true), 92) + 2, 1), Color("ff7a6a"))
			Art.text(self, fit("> " + Data.item_name(it), 96), Vector2(sr.position.x + 5, sr.position.y + 36), 16, Color("62d26f"), HORIZONTAL_ALIGNMENT_LEFT, 1, true)
		elif cur != null:
			Art.text(self, fit(Data.item_name(cur), 94), Vector2(sr.position.x + 5, sr.position.y + 26), 16, Data.tier_color(int(cur.tier)).lightened(0.2), HORIZONTAL_ALIGNMENT_LEFT, 1, true)
			Art.text(self, Data.tier_name(int(cur.tier)), Vector2(sr.position.x + 5, sr.position.y + 38), 16, Color("6c7480"), HORIZONTAL_ALIGNMENT_LEFT, 1, true)
		else:
			Art.text(self, "empty", Vector2(sr.position.x + 5, sr.position.y + 28), 16, Color("6c7480"), HORIZONTAL_ALIGNMENT_LEFT, 1, true)
		if cur != null:
			Tip.zone(self, sr, Data.item_name(cur).to_upper(), "%s. %s" % [", ".join(Data.stat_lines(Data.item_stats(cur))), Data.ITEMS[cur.id].text], Data.tier_color(int(cur.tier)))

func draw_middle(u, fr: Dictionary) -> void:
	## NEW next to what COMES OFF, and the full list of what changes for this soldier.
	Art.text(self, "NEW", Vector2(340, 142), 8, Color("62d26f"), HORIZONTAL_ALIGNMENT_CENTER)
	var slot: String = fr.get("slot", "")
	var cx := 514.0
	if slot == "":
		Art.text(self, "TO STASH", Vector2(cx, 142), 8, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER)
		draw_box(Rect2(448, 150, 132, 176))
		var yy := 200.0
		for ln in CardView.wrap_text("Nothing changes on %s. The %s waits in the stash: equip it at the Armory between missions." % [u.def.name if u != null else "anyone", Data.item_name(it)], 116, 16):
			Art.text(self, ln, Vector2(cx, yy), 16, Color("c9bfa8"), HORIZONTAL_ALIGNMENT_CENTER, 1, true)
			yy += 13
	elif fr.old != null:
		Art.text(self, "COMES OFF", Vector2(cx, 142), 8, Color("ff7a6a"), HORIZONTAL_ALIGNMENT_CENTER)
		Art.text(self, "(goes to the stash)", Vector2(cx, 146 - 22), 16, Color("ff7a6a"), HORIZONTAL_ALIGNMENT_CENTER, 1, true)
		draw_swap_arrow()
	else:
		Art.text(self, "EMPTY SLOT", Vector2(cx, 142), 8, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER)
		draw_box(Rect2(448, 150, 132, 176))
		Art.text(self, "Nothing comes off.", Vector2(cx, 236), 16, Color("c9bfa8"), HORIZONTAL_ALIGNMENT_CENTER, 1, true)
		draw_swap_arrow()
	# what changes
	var y := 362.0
	Art.text(self, "WHAT CHANGES FOR %s" % (u.def.name if u != null else "?"), Vector2(274, y), 8, Color("9aa2ae"))
	y += 16
	var lines: Array = []
	if slot == "" or u == null:
		lines = [["Nothing: %s keeps what they wear." % (u.def.name if u != null else "the squad"), true]]
	else:
		lines = ArmoryRef().equip_changes(u.s, it, slot).filter(func(l): return not String(l[0]).ends_with("goes to the stash."))
		if lines.is_empty():
			lines = [["Same stats, different item.", true]]
	for l in lines.slice(0, 7):
		for w in CardView.wrap_text(String(l[0]), 300, 16):
			if y > PANEL.end.y - 12:
				break
			Art.text(self, w, Vector2(274, y), 16, Color("62d26f") if l[1] else Color("ff7a6a"), HORIZONTAL_ALIGNMENT_LEFT, 1, true)
			y += 12

func ArmoryRef():
	return load("res://scripts/armory.gd")

func draw_swap_arrow() -> void:
	var y := 238.0
	draw_rect(Rect2(410, y - 1, 34, 3), Color("ffd23a"))
	draw_colored_polygon(PackedVector2Array([Vector2(444, y - 6), Vector2(444, y + 7), Vector2(450, y + 0.5)]), Color("ffd23a"))
	draw_colored_polygon(PackedVector2Array([Vector2(410, y - 6), Vector2(410, y + 7), Vector2(404, y + 0.5)]), Color("ffd23a"))

func draw_box(r: Rect2) -> void:
	draw_rect(r, INK)
	draw_rect(r.grow(-1), Color("24272c"))
	for i in int(r.size.y / 8):
		draw_rect(Rect2(r.position.x + 2, r.position.y + 4 + i * 8, r.size.x - 4, 1), Color(1, 1, 1, 0.03))

func draw_rows(u, f: int) -> void:
	Art.text(self, "WHERE DOES IT GO?", Vector2(ROW_X, 112), 8, Color("9aa2ae"))
	Art.text(self, "TAB: next soldier", Vector2(ROW_X + ROW_W, 112), 16, Color("6c7480"), HORIZONTAL_ALIGNMENT_RIGHT, 1, true)
	for i in rows.size():
		var row: Dictionary = rows[i]
		var rr := row_rect(i)
		var on := i == f
		var stash: bool = row.slot == ""
		var c := Color("9aa2ae") if stash else Color("53d4e2")
		draw_rect(rr, INK)
		draw_rect(rr.grow(-1), Color("3a4048") if on else Color("2a2e34"))
		draw_rect(Rect2(rr.position.x + 1, rr.position.y + 1, 4, rr.size.y - 2), c)
		if on:
			draw_rect(rr.grow(1), Color("ffd23a") if i == hover_row else Color(1, 1, 1, 0.35), false, 2.0)
		Art.text(self, str(i + 1), Vector2(rr.position.x + 14, rr.position.y + 20), 8, Color("6c7480"), HORIZONTAL_ALIGNMENT_CENTER)
		var head := ""
		var line := ""
		if stash:
			head = "SEND TO STASH"
			line = "%s keeps everything they wear." % (u.def.name if u != null else "Nobody")
		else:
			head = "EQUIP AS %s" % SLOT_LABEL[row.slot]
			line = ("Swaps out %s (to stash)" % Data.item_name(row.old)) if row.old != null else "Fills an empty slot"
		Art.text(self, head, Vector2(rr.position.x + 26, rr.position.y + 19), 8, Color.WHITE)
		Art.text(self, fit(line, ROW_W - 34), Vector2(rr.position.x + 26, rr.position.y + 37), 16, Color("c9bfa8"), HORIZONTAL_ALIGNMENT_LEFT, 1, true)
		if not stash and u != null:
			var tag := ""
			var tc := Color("62d26f")
			if not best.is_empty() and best.u == u and best.slot == row.slot:
				tag = "BEST FOR %s" % u.def.name
			elif row.gain < -0.05:
				tag = "WORSE FIT"
				tc = Color("ff7a6a")
			elif row.gain > 0.05:
				tag = "UPGRADE"
			if tag != "":
				var tw := Art.text_width(tag, 16, true) + 10
				draw_rect(Rect2(rr.end.x - tw - 4, rr.position.y + 5, tw, 14), tc.darkened(0.55))
				Art.text(self, tag, Vector2(rr.end.x - 9 - tw / 2 + 5, rr.position.y + 16), 16, tc, HORIZONTAL_ALIGNMENT_CENTER, 1, true)

func fit(s: String, w: float) -> String:
	if Art.text_width(s, 16, true) <= w:
		return s
	while s.length() > 3 and Art.text_width(s + "...", 16, true) > w:
		s = s.substr(0, s.length() - 1)
	return s + "..."

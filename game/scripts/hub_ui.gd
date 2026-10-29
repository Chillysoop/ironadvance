extends RefCounted
## Widgets shared by the HQ screens: the squad bar pinned to the top of every HQ screen
## and the action tile that always says what it does, or why it can't.

const Services := preload("res://scripts/services.gd")
const INK := Color(0.05, 0.035, 0.03)
const ALL_W := 92.0
const ALL_PLATE := 99      # SquadBar.current / hover for the ALL DECKS plate (soldiers are 0-4)

static func field_dossier(parent: Node, i := 0) -> Control:
	## S6: the same Dossier from the field (debrief, camp, level-up, the battle deck view),
	## read-only, so you can check a deck before you pick.
	var d: Control = load("res://scripts/dossier.gd").new()
	d.readonly = true
	d.idx = clampi(i, 0, Run.soldiers.size() - 1)
	d.done.connect(d.queue_free)
	parent.add_child(d)
	return d

class SquadBar extends Control:
	## Four soldier plates: portrait, hotkey, HP, dog tags and the one thing worth doing for them.
	## Click one (or press 1-5 where the screen listens) to open that soldier.
	signal picked(i: int)
	signal all_decks           # D3: a fifth plate, shown only when the screen listens for it
	var current := -1         # the soldier whose screen is open, outlined in gold
	var pickable: Array = []   # when not empty, only these soldier indices light up and take clicks
	var hover := -1
	var t := 0
	func _ready() -> void:
		size = Vector2(928, 38)
		mouse_filter = Control.MOUSE_FILTER_STOP
	func has_all() -> bool:
		return pickable.is_empty() and get_signal_connection_list("all_decks").size() > 0
	func plate(i: int) -> Rect2:
		var room := size.x - (ALL_W + 8 if has_all() else 0.0)
		var n := maxi(4, Run.soldiers.size())  # X2: a freed specialist makes a fifth
		var w := (room - 8.0 * (n - 1)) / n
		return Rect2(i * (w + 8), 0, w, size.y)
	func all_rect() -> Rect2:
		return Rect2(size.x - ALL_W, 0, ALL_W, size.y)
	func _process(_d: float) -> void:
		t += 1
		queue_redraw()
	func usable(i: int) -> bool:
		return i < Run.soldiers.size() and (pickable.is_empty() or pickable.has(i))
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion:
			hover = -1
			for i in Run.soldiers.size():
				if plate(i).has_point(ev.position):
					hover = i
			if has_all() and all_rect().has_point(ev.position):
				hover = ALL_PLATE
		elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			for i in Run.soldiers.size():
				if plate(i).has_point(ev.position):
					if usable(i):
						Sfx.play("select")
						picked.emit(i)
					else:
						Sfx.play("deny")
			if has_all() and all_rect().has_point(ev.position):
				Sfx.play("select")
				all_decks.emit()
	func _draw() -> void:
		Tip.clear(self)
		if has_all():
			var ar := all_rect()
			draw_rect(ar, INK)
			draw_rect(ar.grow(-1), Color("3a4048") if hover == ALL_PLATE else Color("2a2e34"))
			if current == ALL_PLATE:
				draw_rect(ar.grow(1), Color("ffd23a"), false, 2.0)
			for k in 4:  # four little decks fanned out
				var cr := Rect2(ar.position + Vector2(8 + k * 7, 9 + (k % 2) * 3), Vector2(12, 18))
				draw_rect(cr, INK)
				draw_rect(cr.grow(-1), Color("e8dcc2"))
			Art.text(self, "ALL", Vector2(ar.end.x - 24, ar.position.y + 17), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
			Art.text(self, "DECKS", Vector2(ar.end.x - 24, ar.position.y + 30), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
		for i in Run.soldiers.size():
			var s: Dictionary = Run.soldiers[i]
			var r := plate(i)
			var lit := usable(i)
			draw_rect(r, INK)
			draw_rect(r.grow(-1), Color("3a4048") if hover == i and lit else Color("2a2e34"))
			if not pickable.is_empty() and lit:
				var pulse := 0.55 + 0.45 * sin(t / 8.0)
				draw_rect(r.grow(2), Color(1, 0.82, 0.23, pulse), false, 2.0)
			elif i == current:
				draw_rect(r.grow(1), Color("ffd23a"), false, 2.0)
			# portrait: the soldier from the waist up, in a dark box
			var pb := Rect2(r.position + Vector2(3, 3), Vector2(32, 32))
			draw_rect(pb, Color("1a1d22"))
			if s.alive:
				Art.draw_char(self, Art.look_sheet(s), "idle", (t / 14 + i) % 4, pb.position + Vector2(16, 31), 1, false, 0, 1.0, 0, false, 0.72)
			else:
				Art.text(self, "KIA", pb.get_center() + Vector2(0, 4), 8, Color("ff4d3d"), HORIZONTAL_ALIGNMENT_CENTER)
			var x := r.position.x + 42
			Art.text(self, s.def.name, Vector2(x, r.position.y + 14), 8, Color.WHITE if s.alive else Color("8a7a7a"))
			Art.text(self, "LV%d" % s.lvl, Vector2(x + 52, r.position.y + 14), 8, Color("ffd23a"))
			Art.text(self, str(i + 1), Vector2(r.end.x - 8, r.position.y + 14), 8, Color("6c7480"), HORIZONTAL_ALIGNMENT_RIGHT)
			if s.alive:
				var mx := Run.eff_max_hp(s)
				var bw := r.size.x - 52
				draw_rect(Rect2(x, r.position.y + 22, bw, 6), INK)
				draw_rect(Rect2(x + 1, r.position.y + 23, (bw - 2) * clampf(float(s.hp) / mx, 0, 1), 4), Color("62d26f") if s.hp > mx * 0.3 else Color("ff4d3d"))
				Art.text(self, "%d/%d" % [s.hp, mx], Vector2(x, r.position.y + 36), 8, Color("9aa2ae"))
				Art.draw_tags(self, Vector2(x + 62, r.position.y + 29), s.tags)
			var al := Services.alert(s)
			if al != "" and al != "KIA":
				var aw := Art.text_width(al, 8) + 8
				var ap := Vector2(r.end.x - aw - 2, r.position.y - 7 - (1 if (t / 20) % 2 == 0 else 0))
				draw_rect(Rect2(ap, Vector2(aw, 12)), INK)
				draw_rect(Rect2(ap + Vector2(1, 1), Vector2(aw - 2, 10)), Color("ff4d3d") if al == "HURT" else Color("ffd23a"))
				Art.text(self, al, ap + Vector2(aw / 2, 10), 8, INK, HORIZONTAL_ALIGNMENT_CENTER, 0)
				# D10: what the badge means and where to act on it
				var why: Array = {
					"FUSE": ["FUSE READY", "%s has 3 copies of a card at one rarity. Fuse them into one copy a rarity higher at the WORKSHOP, or from the Dossier's FUSE tab." % s.def.name],
					"EVOLVE": ["EVOLVE READY", "One of %s's cards can evolve into its upgraded form. Do it at the WORKSHOP." % s.def.name],
					"HURT": ["HURT", "%s is below full HP. Patch them up at DOC'S LAB." % s.def.name],
				}.get(al, [])
				if why.size():
					Tip.zone(self, Rect2(ap, Vector2(aw, 12)).grow(3), why[0], why[1], Color("ff4d3d") if al == "HURT" else Color("ffd23a"))

class ActionTile extends Control:
	## A service button big enough to explain itself: name and price on top, then what it
	## does, or (greyed) what is missing. Clicking a greyed tile only plays the deny sound.
	signal pressed
	var title := ""
	var cost := -1             # -1: no price shown, 0: FREE
	var desc := ""             # what the service is, always shown (Workshop tiles)
	var line := ""             # what happens
	var why := ""              # why it can't happen right now
	var ok := true
	var color := Color("53d4e2")
	var hover := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): hover = true)
		mouse_exited.connect(func(): hover = false)
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if ok:
				Sfx.play("click")
				pressed.emit()
			else:
				Sfx.play("deny")
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := color if ok else Color("5a616b")
		draw_rect(Rect2(0, 0, w, h), INK)
		draw_rect(Rect2(1, 1, w - 2, h - 2), Color("2a2f36") if hover and ok else Color("22262c"))
		draw_rect(Rect2(1, 1, w - 2, 3), c)
		if hover and ok:
			draw_rect(Rect2(0, 0, w, h), c, false, 1.0)
		Art.text(self, title, Vector2(6, 16), 8, c if ok else Color("8a9099"))
		if cost >= 0:
			Art.text(self, "FREE" if cost == 0 else "%d$" % cost, Vector2(w - 5, 16), 8, Color("ffd23a") if ok else Color("8a7a40"), HORIZONTAL_ALIGNMENT_RIGHT)
		var y := 30.0
		for ln in CardView.wrap_text(desc, w - 10, 16):
			Art.text(self, ln, Vector2(6, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
			y += 12
		if desc != "":
			y += 4
		var body := line if ok else why
		for ln in CardView.wrap_text(body, w - 10, 16):
			if y > h - 2:
				break
			Art.text(self, ln, Vector2(6, y), 16, (Color("62d26f") if desc != "" else Color("e8dcc2")) if ok else Color("8a9099"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
			y += 12

class NavStrip extends Control:
	## B2: every building one click (or one key) away, along the top of each HQ screen.
	## A dot marks a building that has something ready (the same checks as the HQ badges).
	signal go(id: String)
	const STOPS := [["HQ", "hq", "H"], ["QM TENT", "qm", "Q"], ["WORKSHOP", "workshop", "W"], ["ARMORY", "armory", "A"],
		["DOC'S LAB", "doc", "D"], ["BARRACKS", "barracks", "B"], ["MEMORIAL", "memorial", "M"]]
	var current := "hq"
	var badges := {}           # id -> short badge text
	var hover := -1
	func _ready() -> void:
		size = Vector2(928, 18)
		position = Vector2(16, 12)
		mouse_filter = Control.MOUSE_FILTER_STOP
	func cell(i: int) -> Rect2:
		var w := (size.x - 6 * 4) / 7.0
		return Rect2(i * (w + 4), 0, w, size.y)
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion:
			hover = -1
			for i in STOPS.size():
				if cell(i).has_point(ev.position):
					hover = i
		elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			for i in STOPS.size():
				if cell(i).has_point(ev.position) and STOPS[i][1] != current:
					go.emit(STOPS[i][1])
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		for i in STOPS.size():
			var r := cell(i)
			var on: bool = STOPS[i][1] == current
			draw_rect(r, INK)
			draw_rect(r.grow(-1), Color("ffd23a") if on else (Color("3a4048") if hover == i else Color("2a2e34")))
			Art.text(self, STOPS[i][0], Vector2(r.get_center().x, r.position.y + 13), 8, INK if on else Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 0)
			Art.text(self, STOPS[i][2], Vector2(r.position.x + 4, r.position.y + 13), 8, Color(0, 0, 0, 0.5) if on else Color("6c7480"), HORIZONTAL_ALIGNMENT_LEFT, 0)
			if badges.get(STOPS[i][1], "") != "":
				draw_rect(Rect2(r.end.x - 9, r.position.y + 5, 7, 7), INK)
				draw_rect(Rect2(r.end.x - 8, r.position.y + 6, 5, 5), Color("ff4d3d"))

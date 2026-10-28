extends Control
## X1: the squad draft before a quick run. Pick four of the classes you've unlocked; the specialists
## you haven't freed yet show as locked cards that say where to find them (X2).

signal go
signal back

var picked: Array = []
var t := 0
var hover := -1

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picked = Run.draft()
	build()

func card(i: int) -> Rect2:
	var n := Data.SQUAD_DEFS.size()
	var cols := n if n <= 5 else int(ceil(n / 2.0))  # one row, or two once there are more than five
	var w := minf(168.0, (900.0 - (cols - 1) * 12) / cols)
	var h := 184.0 if n <= 5 else 168.0
	var row := i / cols
	var in_row := mini(cols, n - row * cols)
	var x0 := 480.0 - (in_row * (w + 12) - 12) / 2.0
	return Rect2(x0 + (i % cols) * (w + 12), 112 + row * (h + 10), w, h)

func build() -> void:
	for c in get_children():
		c.queue_free()
	var PB = load("res://scripts/hud.gd").PixButton
	var bt = PB.new()
	bt.text = "DEPLOY" if picked.size() == 4 else "PICK %d MORE" % (4 - picked.size())
	bt.color = Color("62d26f") if picked.size() == 4 else Color("6c7480")
	bt.size = Vector2(220, 40)
	bt.position = Vector2(370, 478)
	bt.pressed.connect(func():
		if picked.size() != 4:
			Sfx.play("deny")
			return
		Run.set_draft(picked)
		go.emit())
	add_child(bt)
	var bk = PB.new()
	bk.text = "<< TITLE"
	bk.small = true
	bk.color = Color("9aa2ae")
	bk.size = Vector2(140, 30)
	bk.position = Vector2(30, 484)
	bk.pressed.connect(func(): back.emit())
	add_child(bk)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		hover = -1
		for i in Data.SQUAD_DEFS.size():
			if card(i).has_point(ev.position):
				hover = i
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		for i in Data.SQUAD_DEFS.size():
			if card(i).has_point(ev.position):
				toggle(Data.SQUAD_DEFS[i].key)

func toggle(key: String) -> void:
	if not Run.class_keys().has(key):
		Sfx.play("deny")
		return
	if picked.has(key):
		picked.erase(key)
	elif picked.size() < 4:
		picked.append(key)
	else:
		Sfx.play("deny")
		return
	Sfx.play("click")
	build()

func _process(_d: float) -> void:
	t += 1
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color("101418"))
	Art.text(self, "PICK YOUR SQUAD", Vector2(480, 54), 24, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 3)
	Art.text(self, "Four soldiers go in. Free specialists from Jackal camps to add them here for good.", Vector2(480, 86), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
	var keys := Run.class_keys()
	for i in Data.SQUAD_DEFS.size():
		var d: Dictionary = Data.SQUAD_DEFS[i]
		var r := card(i)
		var open := keys.has(d.key)
		var on := picked.has(d.key)
		draw_rect(r, Color(0.07, 0.07, 0.08))
		draw_rect(r, Color("62d26f") if on else (Color("ffd23a") if hover == i and open else Color("3a4048")), false, 3 if on else 2)
		if not open:
			Art.text(self, "?", r.get_center() + Vector2(0, -28), 32, Color("3a4048"), HORIZONTAL_ALIGNMENT_CENTER, 2)
			Art.text(self, d.cls.to_upper(), Vector2(r.get_center().x, r.position.y + 118), 8, Color("6c7480"), HORIZONTAL_ALIGNMENT_CENTER)
			Art.text(self, "LOCKED", Vector2(r.get_center().x, r.position.y + 140), 8, Color("ff7a3d"), HORIZONTAL_ALIGNMENT_CENTER)
			Art.text(self, "Held as a POW in a run", Vector2(r.get_center().x, r.position.y + 162), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
			continue
		Art.draw_char(self, "sq_" + d.key, "idle", (t / 10 + i * 3) % 12, Vector2(r.get_center().x, r.position.y + 90), 1, false, 0.0, 1.0 if on or picked.size() < 4 else 0.5, 0.0, true, 1.3)
		Art.text(self, d.name, Vector2(r.get_center().x, r.position.y + 116), 16, Color("ffd23a") if on else Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2)
		Art.text(self, d.cls.to_upper(), Vector2(r.get_center().x, r.position.y + 136), 8, Color("53d4e2"), HORIZONTAL_ALIGNMENT_CENTER)
		Art.text(self, d.trait[0], Vector2(r.get_center().x, r.position.y + 158), 16, Color("b48cff"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
		if on:
			Art.text(self, "IN", Vector2(r.position.x + 10, r.position.y + 20), 8, Color("62d26f"))
		if hover == i:
			Art.text(self, d.trait[1], Vector2(480, 456), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)

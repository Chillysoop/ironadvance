extends Control
## HQ: the base the squad comes home to through the gate after every boss. Each building
## opens its own screen (Quartermaster, Barracks, Armory, Memorial) and the gate dials the next stop.

signal dial

const HudScript := preload("res://scripts/hud.gd")
const ShopScript := preload("res://scripts/shop.gd")
const ArmoryScript := preload("res://scripts/armory.gd")

const GROUND := 430.0
const GATE := Vector2(480, 340)
const GATE_R := 72.0

var arrived := false        # true when the squad just stepped out of the gate
var t := 0
var sub: Control = null     # the building screen that is open, if any
var memorial_open := false
var held := {}              # textures must stay referenced until the frame renders

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if arrived:
		Sfx.play("power")
	build()

func build() -> void:
	for c in get_children():
		c.queue_free()
	sub = null
	var spots := [
		["QUARTERMASTER", "CARDS  GEAR  UPGRADES", 40, open_shop.bind("shop"), Color("ffb23e")],
		["BARRACKS", "RECRUITS  DOG TAGS", 230, open_shop.bind("barracks"), Color("62d26f")],
		["ARMORY", "GEAR %d  STASH %d" % [Run.soldiers.reduce(func(a, s): return a + s.equip.values().filter(func(x): return x != null).size(), 0), Run.stash.size()], 600, open_armory, Color("53d4e2")],
		["MEMORIAL", "%d NAMES" % Run.meta.memorial.size(), 780, open_memorial, Color("9aa2ae")],
	]
	for sp in spots:
		var bt := HudScript.PixButton.new()
		bt.text = sp[0]
		bt.sub = sp[1]
		bt.color = sp[4]
		bt.small = true
		bt.size = Vector2(150, 36)
		bt.position = Vector2(sp[2], 438)
		bt.pressed.connect(sp[3])
		add_child(bt)
	var go := HudScript.PixButton.new()
	go.text = "DIAL THE GATE"
	go.sub = "MISSION %d" % (next_mission_n())
	go.color = Color("ff4d3d")
	go.size = Vector2(220, 44)
	go.position = Vector2(370, 486)
	go.pressed.connect(func(): Sfx.play("start"); dial.emit())
	add_child(go)

func next_mission_n() -> int:
	return Run.mission + (2 if Run.history.size() else 1)

func open_shop(mode: String) -> void:
	Sfx.play("click")
	var s: Control = ShopScript.new()
	s.mode = mode
	s.done.connect(func(): build())
	add_child(s)
	sub = s

func open_armory() -> void:
	Sfx.play("click")
	var a: Control = ArmoryScript.new()
	a.done.connect(func(): build())
	add_child(a)
	sub = a

func open_memorial() -> void:
	Sfx.play("click")
	memorial_open = true
	var close := HudScript.PixButton.new()
	close.text = "CLOSE"
	close.color = Color("9aa2ae")
	close.size = Vector2(110, 26)
	close.position = Vector2(425, 470)
	close.pressed.connect(func(): memorial_open = false; build())
	for c in get_children():
		c.queue_free()
	add_child(close)
	sub = null

func bg(n: String) -> Texture2D:
	if not held.has(n):
		held[n] = load("res://assets/bg/%s.png" % n)
	return held[n]

func _process(_d: float) -> void:
	t += 1
	queue_redraw()

func gate_open() -> float:
	## Coming home: the horizon is open as the squad steps out, then shuts down.
	if not arrived or t > 90:
		return 0.0
	return 1.0 if t < 70 else 1.0 - (t - 70) / 20.0

func _draw() -> void:
	if sub != null and is_instance_valid(sub):
		return
	draw_texture_rect(bg("dusk_sky"), Rect2(0, 0, 960, 540), false)
	for L in [["far", 300.0], ["mid", 360.0]]:
		var tx: Texture2D = bg("dusk_%s" % L[0])
		var w := tx.get_width() * 2.0
		var x := 0.0
		while x < 960:
			draw_texture_rect(tx, Rect2(x, L[1] + 40 - tx.get_height() * 2, w, tx.get_height() * 2), false)
			x += w
	# ground
	draw_rect(Rect2(0, GROUND, 960, 110), Color("4a3a2c"))
	draw_rect(Rect2(0, GROUND, 960, 4), Color("7cb042"))
	draw_rect(Rect2(0, GROUND + 4, 960, 2), Color("3a5a24"))
	draw_quartermaster()
	draw_barracks()
	draw_armory()
	draw_memorial()
	Art.draw_gate(self, GATE, GATE_R, t, 9 if gate_open() > 0 else 0, gate_open(), 1.0, t * 0.004)
	# the squad, stepping out of the gate when they just came home
	var al: Array = Run.soldiers.filter(func(s): return s.alive)
	for i in al.size():
		var s: Dictionary = al[i]
		var x := 480 + (i - (al.size() - 1) / 2.0) * 46
		var a := 1.0
		if arrived and t < 70:
			a = clampf((t - 10 - i * 10) / 20.0, 0, 1)
		Art.draw_char(self, "sq_" + s.key, "idle", (t / 12 + i) % 4, Vector2(x, GROUND), 1 if x < 480 else -1, false, 0, a, 0, true, 1.4)
		if a >= 1.0:
			Art.text(self, s.def.name, Vector2(x, GROUND + 16), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	# header
	draw_rect(Rect2(0, 0, 960, 70), Color(0.05, 0.035, 0.03, 0.75))
	Art.text(self, "IRON ADVANCE HQ", Vector2(24, 34), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
	var line := "Back through the gate. Resupply, then dial the gate for mission %d." % next_mission_n() if Run.history.size() else "Kit out the squad, then dial the gate for mission 1."
	Art.text(self, line, Vector2(24, 56), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
	var sc := "%d SCRIP" % Run.scrip
	draw_texture_rect(Art.tex.ic_coin, Rect2(936 - Art.text_width(sc, 16) - 22, 20, 16, 16), false)
	Art.text(self, sc, Vector2(936, 36), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT, 2)
	if memorial_open:
		draw_memorial_panel()

func draw_quartermaster() -> void:
	## A supply tent with crates stacked beside it.
	var d := Color(0.05, 0.035, 0.03)
	draw_colored_polygon(PackedVector2Array([Vector2(38, GROUND), Vector2(120, 352), Vector2(202, GROUND)]), d)
	draw_colored_polygon(PackedVector2Array([Vector2(42, GROUND), Vector2(120, 356), Vector2(198, GROUND)]), Color("5a6b3a"))
	draw_colored_polygon(PackedVector2Array([Vector2(100, GROUND), Vector2(120, 392), Vector2(140, GROUND)]), Color("2a2418"))
	for c in [[150, 402, 26], [178, 410, 20], [160, 380, 22]]:
		draw_rect(Rect2(c[0], c[1], c[2], GROUND - c[1] if c[1] > 400 else 22), d)
		draw_rect(Rect2(c[0] + 1, c[1] + 1, c[2] - 2, (GROUND - c[1] if c[1] > 400 else 22) - 2), Color("8a6a3a"))
		draw_rect(Rect2(c[0] + 1, c[1] + 4, c[2] - 2, 2), Color("6a4e2a"))
	draw_rect(Rect2(60, 360, 34, 16), d)
	Art.text(self, "QM", Vector2(77, 373), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)

func draw_barracks() -> void:
	## A long hut with lit windows.
	var d := Color(0.05, 0.035, 0.03)
	draw_rect(Rect2(232, 374, 146, GROUND - 374), d)
	draw_rect(Rect2(234, 376, 142, GROUND - 376), Color("6b5a44"))
	draw_colored_polygon(PackedVector2Array([Vector2(222, 380), Vector2(305, 344), Vector2(388, 380)]), Color("3a2c20"))
	for i in 3:
		var lit := (t / 90 + i) % 5 != 0
		draw_rect(Rect2(246 + i * 30, 390, 14, 12), d)
		draw_rect(Rect2(247 + i * 30, 391, 12, 10), Color("ffd96a") if lit else Color("3b3f45"))
	draw_rect(Rect2(342, 392, 22, GROUND - 392), Color("2a2418"))

func draw_armory() -> void:
	## A concrete bunker behind sandbags, with a rifle rack.
	var d := Color(0.05, 0.035, 0.03)
	draw_rect(Rect2(604, 370, 140, GROUND - 370), d)
	draw_rect(Rect2(606, 372, 136, GROUND - 372), Color("7a7d80"))
	draw_rect(Rect2(606, 372, 136, 4), Color("9aa2ae"))
	draw_rect(Rect2(624, 386, 100, 8), Color("1a1d22"))
	for i in 6:
		draw_rect(Rect2(700 + i * 6, 398, 2, 22), Color("3a3020"))
	for i in 8:
		var x := 600 + i * 19
		draw_rect(Rect2(x, 414, 18, 9), d)
		draw_rect(Rect2(x + 1, 415, 16, 7), Color("b9a27a"))
	for i in 7:
		var x := 609 + i * 19
		draw_rect(Rect2(x, 421, 18, 9), d)
		draw_rect(Rect2(x + 1, 422, 16, 7), Color("a8916a"))

func draw_memorial() -> void:
	## A stone wall with one dog tag per fallen soldier, under a flag.
	var d := Color(0.05, 0.035, 0.03)
	draw_rect(Rect2(792, 384, 118, GROUND - 384), d)
	draw_rect(Rect2(794, 386, 114, GROUND - 386), Color("8a8478"))
	draw_rect(Rect2(794, 386, 114, 3), Color("a8a294"))
	draw_line(Vector2(800, 396), Vector2(902, 396), Color("3a3a3a"), 1.0)
	var n: int = mini(Run.meta.memorial.size(), 14)
	for i in n:
		var x := 802 + i * 7
		var sw := sin(t / 25.0 + i) * 0.8
		draw_rect(Rect2(x + sw, 397, 5, 7), d)
		draw_rect(Rect2(x + 1 + sw, 398, 3, 5), Color("d8dde4"))
	draw_rect(Rect2(920, 318, 3, GROUND - 318), Color("3a3a3a"))
	for i in 6:
		var wave := sin(t / 12.0 + i * 0.7) * 2
		draw_rect(Rect2(923 + i * 5, 320 + wave, 5, 16), Color("ff4d3d") if i % 2 == 0 else Color("e8dcc2"))

func draw_memorial_panel() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color(0.02, 0.02, 0.04, 0.86))
	Art.text(self, "THE MEMORIAL", Vector2(480, 70), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 2)
	var m: Array = Run.meta.memorial
	if m.is_empty():
		Art.text(self, "No names yet. Keep it that way.", Vector2(480, 120), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
		return
	Art.text(self, "Recruits of a fallen soldier's class can start with one of their abilities.", Vector2(480, 96), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
	var shown: Array = m.slice(maxi(0, m.size() - 16))
	shown.reverse()
	for i in shown.size():
		var e: Dictionary = shown[i]
		var col := 0 if i < 8 else 1
		var x := 120.0 + col * 380
		var y := 130.0 + (i % 8) * 40
		Art.draw_tags(self, Vector2(x, y - 10), 1, 1.0, 1)
		Art.text(self, e.name, Vector2(x + 16, y - 2), 8, Color.WHITE)
		Art.text(self, "%s  LV%d  FELL ON MISSION %d" % [e.cls.to_upper(), int(e.lvl), int(e.mission)], Vector2(x + 16, y + 12), 8, Color("9aa2ae"))

extends Node
## Game flow: title -> briefing -> mission -> results -> shop -> next briefing.

const BattleScene := preload("res://scenes/battle.tscn")
const HudScript := preload("res://scripts/hud.gd")
const ShopScript := preload("res://scripts/shop.gd")

var battle: Battle = null
var hud: CanvasLayer = null
var screen: Control = null
var ui_layer: CanvasLayer
var speed := 1.0

func _ready() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--speed="):
			speed = float(a.substr(8))
	if args.has("--iatest"):
		return  # the test harness drives everything
	show_title()

func clear() -> void:
	if screen != null:
		screen.queue_free()
		screen = null
	if battle != null:
		battle.queue_free()
		battle = null
	if hud != null:
		hud.queue_free()
		hud = null

func show_title() -> void:
	clear()
	var s := Screen.new()
	s.mode = "title"
	s.buttons = [["NEW CAMPAIGN", func(): start_run()]]
	open(s)

func start_run() -> void:
	Run.new_run()
	show_brief()

func show_brief() -> void:
	clear()
	var s := Screen.new()
	s.mode = "brief"
	s.buttons = [["DEPLOY", func(): start_battle(Run.mission)]]
	open(s)

func start_battle(idx: int) -> Battle:
	clear()
	battle = BattleScene.instantiate()
	add_child(battle)
	battle.speed = speed
	battle.setup(idx)
	battle.get_node("Backdrop").setup(battle.theme)
	hud = HudScript.new()
	add_child(hud)
	hud.setup(battle)
	battle.mission_over.connect(_on_mission_over)
	battle.begin()
	return battle

func _on_mission_over(won: bool) -> void:
	var st: Dictionary = battle.stats.duplicate()
	st["score"] = battle.score
	st["won"] = won
	var xp := {}
	for u in battle.squad():
		xp[u.def.key] = u.xp_gain
	st["xp"] = xp
	Run.history.append(st)
	clear()
	var s := Screen.new()
	s.stats = st
	if not won or Run.alive_count() == 0:
		s.mode = "lost"
		s.buttons = [["NEW CAMPAIGN", func(): start_run()], ["TITLE", func(): show_title()]]
	elif Run.mission >= Data.MISSIONS.size() - 1:
		s.mode = "final"
		s.buttons = [["NEW CAMPAIGN", func(): start_run()]]
	else:
		s.mode = "won"
		s.buttons = [["TO THE QUARTERMASTER", func(): show_shop()]]
	open(s)

func show_shop() -> void:
	clear()
	var s: Control = ShopScript.new()
	s.done.connect(func():
		Run.mission += 1
		show_brief())
	screen = s
	ui_layer.add_child(s)

func open(s: Control) -> void:
	screen = s
	ui_layer.add_child(s)

# ================================================================ simple full-screen panels
class Screen extends Control:
	var mode := "title"
	var stats := {}
	var buttons: Array = []
	var t := 0
	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		var n := buttons.size()
		var widths: Array = []
		var total := 0.0
		for i in n:
			var bw := maxf(250.0 if i == 0 else 140.0, Art.text_width(buttons[i][0], 16) + 40)
			widths.append(bw)
			total += bw + (10 if i > 0 else 0)
		var x := 480 - total / 2
		for i in n:
			var bt = load("res://scripts/hud.gd").PixButton.new()
			bt.text = buttons[i][0]
			bt.color = Color("ff4d3d") if i == 0 else Color("9aa2ae")
			bt.size = Vector2(widths[i], 40)
			bt.position = Vector2(x, 470)
			x += widths[i] + 10
			bt.pressed.connect(buttons[i][1])
			add_child(bt)
		if mode == "title":
			Sfx.play("start")
	var held := {}  # textures must stay referenced until the frame renders
	func bg(n: String) -> Texture2D:
		if not held.has(n):
			held[n] = load("res://assets/bg/%s.png" % n)
		return held[n]
	func _process(_d: float) -> void:
		t += 1
		queue_redraw()
	func _draw() -> void:
		var theme := "dusk"
		if mode == "brief":
			theme = Data.MISSIONS[Run.mission].theme
		var sky: Texture2D = bg("%s_sky" % theme)
		draw_texture_rect(sky, Rect2(0, 0, 960, 540), false)
		var off := t * 0.4
		for L in [["far", 0.3, 400.0], ["mid", 0.6, 440.0], ["near", 1.0, 480.0]]:
			var tx: Texture2D = bg("%s_%s" % [theme, L[0]])
			var w := tx.get_width() * 2.0
			var x := -fmod(off * L[1], w)
			while x < 960:
				draw_texture_rect(tx, Rect2(x, L[2] - tx.get_height() * 2, w, tx.get_height() * 2), false)
				x += w
		draw_rect(Rect2(0, 480, 960, 60), Color(0.05, 0.035, 0.03, 0.85))
		match mode:
			"title": draw_title()
			"brief": draw_brief()
			"won", "final", "lost": draw_result()
	func squad_line(y: float, anim: String) -> void:
		var i := 0
		for s in Run.soldiers if Run.soldiers.size() else Data.SQUAD_DEFS.map(func(d): return {"key": d.key, "alive": true, "def": d, "lvl": 1}):
			var x := 480 - 150 + i * 100
			var a := anim if s.alive else "die"
			Art.draw_char(self, "sq_" + s.key, a, (t / 6) % 8 if a == "run" else ((t / 12 + i) % 4 if a == "idle" else (t / 10) % 2 if a == "cheer" else 4), Vector2(x, y), 1, false, 0, 1.0, 0, a != "cheer" and a != "die", 2.0)
			Art.text(self, s.def.name, Vector2(x, y + 18), 8, Color.WHITE if s.alive else Color("8a7a7a"), HORIZONTAL_ALIGNMENT_CENTER)
			if s.has("lvl"):
				Art.text(self, "LV%d" % s.lvl, Vector2(x, y + 30), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
			i += 1
	func draw_title() -> void:
		var bob := sin(t / 20.0) * 3
		Art.text(self, "IRON ADVANCE", Vector2(484, 124 + bob), 48, Color("8a2a14"), HORIZONTAL_ALIGNMENT_CENTER, 4)
		Art.text(self, "IRON ADVANCE", Vector2(480, 120 + bob), 48, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 4)
		Art.text(self, "TURN-BASED RUN AND GUN", Vector2(480, 156), 16, Color("ff7a3d"), HORIZONTAL_ALIGNMENT_CENTER, 2)
		squad_line(330, "run")
		var lines := ["Aim every bullet. Lob every grenade. Knock towers onto the Jackals.",
			"Get hurt to get angry: adrenaline supercharges your attacks.",
			"Level up mid-mission, spend scrip at the quartermaster between missions."]
		for i in lines.size():
			Art.text(self, lines[i], Vector2(480, 210 + i * 18), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
		var ver := FileAccess.get_file_as_string("res://version.txt").strip_edges()
		Art.text(self, "BUILD " + (ver if ver != "" else "DEV"), Vector2(950, 530), 8, Color("6c7480"), HORIZONTAL_ALIGNMENT_RIGHT)
		if t % 60 < 40:
			Art.text(self, "3 MISSIONS  4 SOLDIERS  1 IRON BOAR TOO MANY", Vector2(480, 450), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	func draw_brief() -> void:
		var m: Dictionary = Data.MISSIONS[Run.mission]
		Art.text(self, "MISSION %d" % (Run.mission + 1), Vector2(480, 90), 16, Color("ff7a3d"), HORIZONTAL_ALIGNMENT_CENTER, 2)
		Art.text(self, m.name, Vector2(480, 130), 32, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 3)
		var y := 170.0
		for line in CardView.wrap_text(m.brief, 620, 16):
			Art.text(self, line, Vector2(480, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
			y += 16
		Art.text(self, "IRON BOAR HP %d   ARMOR %d   JACKALS +%d%% HP" % [m.boss_hp, m.plate, int((m.hp_mul - 1) * 100)], Vector2(480, y + 14), 8, Color("9fb4c9"), HORIZONTAL_ALIGNMENT_CENTER)
		draw_texture_rect(Art.tex.ic_coin, Rect2(410, y + 30, 10, 10), false)
		Art.text(self, "%d SCRIP" % Run.scrip, Vector2(426, y + 40), 8, Color("ffd23a"))
		squad_line(370, "idle")
	func draw_result() -> void:
		var title := "MISSION COMPLETE!" if mode == "won" else ("THE JACKALS GO HOME" if mode == "final" else "MISSION FAILED")
		var col := Color("62d26f") if mode != "lost" else Color("ff4d3d")
		Art.text(self, title, Vector2(480, 96), 32, col, HORIZONTAL_ALIGNMENT_CENTER, 3)
		if mode == "final":
			Art.text(self, "CAMPAIGN WON. THE ROAD EAST IS OPEN.", Vector2(480, 124), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
		elif mode == "lost":
			Art.text(self, "THE JACKALS HOLD THE LINE. REGROUP AND GO AGAIN.", Vector2(480, 124), 8, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER)
		var rows := [["SCORE", str(stats.get("score", 0))], ["KILLS", str(stats.get("kills", 0))], ["CRUSHES", str(stats.get("crushes", 0))], ["POWS FREED", str(stats.get("pows", 0))], ["PUSHES", str(stats.get("pushes", 0))], ["ROUNDS", str(stats.get("rounds", 0))], ["SCRIP EARNED", str(stats.get("scrip", 0))]]
		if mode == "final" or mode == "lost":
			rows.append(["CAMPAIGN SCORE", str(Run.total_score)])
		for i in rows.size():
			Art.text(self, rows[i][0], Vector2(330, 160 + i * 20), 8, Color("e8dcc2"))
			Art.text(self, rows[i][1], Vector2(630, 160 + i * 20), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		squad_line(420, "cheer" if mode != "lost" else "idle")

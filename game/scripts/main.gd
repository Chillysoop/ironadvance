extends Node
## Game flow: title -> briefing -> mission -> results -> shop -> next briefing.

const BattleScene := preload("res://scenes/battle.tscn")
const HudScript := preload("res://scripts/hud.gd")
const ShopScript := preload("res://scripts/shop.gd")
const DebriefScript := preload("res://scripts/debrief.gd")

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
	var tmax := mini(int(Run.meta.threat_max), Data.THREATS.size())
	if tmax > 0:
		# W5: every campaign win opens the next threat level
		s.buttons.append(["THREAT %d" % Run.threat, func():
			Run.threat = (Run.threat + 1) % (tmax + 1)
			Sfx.play("click")
			show_title()])
	open(s)

func start_run() -> void:
	Run.new_run()
	show_brief()

func show_brief() -> void:
	clear()
	Run.side = ""
	Run.roll_intel()
	var s := Screen.new()
	s.mode = "brief"
	s.buttons = [["DEPLOY", func(): start_battle(Run.mission)]]
	open(s)

func start_battle(idx: int, custom := {}) -> Battle:
	clear()
	battle = BattleScene.instantiate()
	add_child(battle)
	battle.speed = speed
	battle.setup(idx, custom)
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
	if Run.side == "outpost" and Run.alive_count() > 0:
		# W1: an outpost loss only costs the wounded; a win pays an Epic crate and a Boar part
		s.mode = "won" if won else "outpost_lost"
		s.buttons = [["OPEN THE SPOILS", func(): show_spoils([3], true)]] if won else [["NEXT MISSION", func(): next_mission()]]
		open(s)
		return
	if not won or Run.alive_count() == 0:
		s.mode = "lost"
		s.buttons = [["NEW CAMPAIGN", func(): start_run()], ["TITLE", func(): show_title()]]
	elif Run.mission >= Data.MISSIONS.size() - 1:
		s.mode = "final"
		s.buttons = [["NEW CAMPAIGN", func(): start_run()]]
		Run.meta.wins = int(Run.meta.wins) + 1
		Run.meta.threat_max = maxi(int(Run.meta.threat_max), mini(Run.threat + 1, Data.THREATS.size()))
		Run.save_meta()
		s.unlock = Run.feat("winrun")
	else:
		s.mode = "won"
		s.buttons = [["OPEN SUPPLY CRATES", func(): show_debrief(st)]]
	open(s)

func show_debrief(st: Dictionary) -> void:
	clear()
	var d: Control = DebriefScript.new()
	d.medals = Run.medals(st)
	d.done.connect(show_route)
	screen = d
	ui_layer.add_child(d)

func show_route() -> void:
	## W1: pick the next stop on the road. The depot is always offered.
	clear()
	var s := Screen.new()
	s.mode = "route"
	for k in Run.route_offers():
		var key: String = k
		s.buttons.append([Data.STOPS[key].name, func(): go_stop(key)])
	open(s)

func go_stop(key: String) -> void:
	Sfx.play("start")
	match key:
		"depot":
			show_shop()
		"outpost":
			Run.side = "outpost"
			var m: Dictionary = Data.MISSIONS[Run.mission].duplicate()
			var segs: Array = ["start", ["towers", "bunker", "boulder"][Run.mission % 3], "bunker"]
			m.merge({"name": "ELITE OUTPOST", "segments": segs, "outpost": true, "hp_mul": m.hp_mul + 0.1}, true)
			start_battle(Run.mission, m)
		"powcamp":
			Run.lvl_rerolls += 2
			Run.reroll_tokens += 1
			show_spoils([1], false)
		"hospital":
			for so in Run.soldiers:
				if so.alive:
					so.hp = so.max_hp
					so.tags = mini(Data.DOG_TAGS, so.tags + 1)
			var s := Screen.new()
			s.mode = "hospital"
			s.buttons = [["NEXT MISSION", func(): next_mission()]]
			open(s)

func show_spoils(tiers: Array, trophy: bool) -> void:
	## Crates from a side stop (outpost, POW camp), then straight on to the next mission.
	clear()
	if trophy:
		for part in Data.TROPHIES:
			if not Run.trophies.has(part):
				Run.trophies.append(part)
				break
	var d: Control = DebriefScript.new()
	d.fixed_tiers = tiers
	d.no_command = true
	d.done.connect(next_mission)
	screen = d
	ui_layer.add_child(d)

func next_mission() -> void:
	Run.mission += 1
	show_brief()

func show_shop() -> void:
	clear()
	var s: Control = ShopScript.new()
	s.done.connect(next_mission)
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
	var unlock := ""
	var t := 0
	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		var n := buttons.size()
		var widths: Array = []
		var total := 0.0
		for i in n:
			var bw := maxf(250.0 if i == 0 and mode != "route" else 140.0, Art.text_width(buttons[i][0], 16) + 40)
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
		if mode == "title":
			draw_title_stage()
		else:
			draw_rect(Rect2(0, 480, 960, 60), Color(0.05, 0.035, 0.03, 0.85))
		match mode:
			"title": draw_title()
			"brief": draw_brief()
			"won", "final", "lost", "outpost_lost": draw_result()
			"route": draw_route()
			"hospital":
				Art.text(self, "FIELD HOSPITAL", Vector2(480, 110), 32, Color("62d26f"), HORIZONTAL_ALIGNMENT_CENTER, 3)
				Art.text(self, "Everyone is patched up and gets one dog tag back. The dead stay dead.", Vector2(480, 150), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
				squad_line(370, "cheer")
	func squad_line(y: float, anim: String) -> void:
		var i := 0
		for s in Run.soldiers if Run.soldiers.size() else Data.SQUAD_DEFS.map(func(d): return {"key": d.key, "alive": true, "def": d, "lvl": 1}):
			var x := 480 - 150 + i * 100
			var a := anim if s.alive else "die"
			Art.draw_char(self, "sq_" + s.key, a, (t / 6) % 8 if a == "run" else ((t / 12 + i) % 4 if a == "idle" else (t / 10) % 2 if a == "cheer" else 4), Vector2(x, y), 1, false, 0, 1.0, 0, a != "cheer" and a != "die", 2.0)
			Art.text(self, s.def.name, Vector2(x, y + 18), 8, Color.WHITE if s.alive else Color("8a7a7a"), HORIZONTAL_ALIGNMENT_CENTER)
			if s.has("lvl"):
				Art.text(self, "LV%d" % s.lvl, Vector2(x, y + 30), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
			if s.has("tags") and s.alive:
				Art.draw_tags(self, Vector2(x - 9, y + 36), s.tags)
			i += 1
	const HEROES := [  # key, x, feet y, scale, face, gun angle: a pyramid on the rubble, Rook on top
		["hex", 314, 408, 2.5, -1, -0.15], ["moss", 392, 388, 2.75, -1, -0.35],
		["vee", 574, 388, 2.75, 1, -0.3], ["rook", 480, 372, 3.0, 1, -0.55]]
	func draw_title_stage() -> void:
		## Key art: the backdrop sinks into dusk, the sun flares up behind the mound, and the
		## squad stands on top as near-black silhouettes rimmed in hot light.
		draw_rect(Rect2(0, 0, 960, 540), Color(0.07, 0.03, 0.09, 0.62))
		for i in 8:  # darker toward the edges and the top
			var a := 0.05 * (8 - i) / 8.0
			draw_rect(Rect2(0, i * 12, 960, 12), Color(0.02, 0.01, 0.03, a * 3))
			draw_rect(Rect2(i * 14, 0, 14, 540), Color(0.02, 0.01, 0.03, a * 2.5))
			draw_rect(Rect2(946 - i * 14, 0, 14, 540), Color(0.02, 0.01, 0.03, a * 2.5))
		var c := Vector2(480, 330)
		var pulse := 1.0 + sin(t / 50.0) * 0.04
		for r in [[300, 0.06], [220, 0.08], [150, 0.12], [96, 0.18], [60, 0.28]]:
			draw_circle(c, r[0] * pulse, Color(1, 0.55, 0.25, r[1]))
		draw_circle(c, 40, Color(1, 0.85, 0.55, 0.55))
		for i in 9:  # god rays fanning up from behind the squad
			var a := -PI / 2 + (i - 4) * 0.2 + sin(t / 240.0 + i) * 0.03
			var w := 0.035 + 0.02 * (i % 2)
			var L := 620.0
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a - w), sin(a - w)) * L, c + Vector2(cos(a + w), sin(a + w)) * L]), Color(1, 0.75, 0.45, 0.07))
		for i in 26:  # embers and ash rising through the light
			var age := fposmod(t * (0.6 + Terrain.hash2(i, 1) * 0.6) + Terrain.hash2(i, 2) * 540, 540.0)
			var x := fposmod(Terrain.hash2(i, 3) * 960 + sin(age / 40.0 + i) * 20 + age * 0.15, 960.0)
			var y := 540 - age
			var col := Color(1, 0.6 + Terrain.hash2(i, 4) * 0.3, 0.3, 0.9 * (1 - age / 540.0)) if i % 3 else Color(0.5, 0.45, 0.5, 0.5)
			draw_rect(Rect2(roundf(x), roundf(y), 2 if i % 4 else 4, 2 if i % 4 else 4), col)
		var stage: Texture2D = bg("title_stage")
		draw_texture_rect(stage, Rect2(0, 0, 960, 540), false)
		draw_banner(Vector2(518, 372))
		for h in HEROES:
			var pos := Vector2(h[1], h[2])
			var fr := (t / 14 + int(h[1])) % 4
			# rim light: the flash sprite, warm, nudged toward the sun, then the body darkened over it
			for o in [Vector2(0, -2), Vector2(-2 * h[4], -1), Vector2(2 * h[4], -1)]:
				Art.draw_char(self, "sq_" + h[0], "idle", fr, pos + o, h[4], true, 0, 0.9, h[5], true, h[3], Color(1, 0.72, 0.42))
			Art.draw_char(self, "sq_" + h[0], "idle", fr, pos, h[4], false, 0, 1.0, h[5], true, h[3], Color(0.94, 0.88, 0.9))
		draw_rect(Rect2(0, 456, 960, 84), Color(0.03, 0.015, 0.03, 0.35))
	func draw_banner(base: Vector2) -> void:
		## The squad's flag planted on the peak, snapping in the wind.
		draw_rect(Rect2(base.x - 1, base.y - 150, 4, 150), Color("120a10"))
		draw_rect(Rect2(base.x, base.y - 150, 2, 150), Color("6a5a5a"))
		for col in 26:
			var k := col / 26.0
			var wave := roundf(sin(t / 6.0 - col * 0.45) * 4 * k / 2) * 2
			var x := base.x + 3 + col * 3
			var y := base.y - 148 + wave + k * 4
			var hgt := 40.0 - k * 6
			draw_rect(Rect2(x, y, 3, hgt), Color("4c5c20") if col % 13 != 0 else Color("3c4818"))
			draw_rect(Rect2(x, y, 3, 3), Color("f08a4a"))
			if col >= 9 and col <= 15:
				var sy := 14.0 - absf(col - 12) * 2
				draw_rect(Rect2(x, y + hgt / 2 - sy / 2, 3, sy), Color("ffd23a"))
	func draw_title() -> void:
		var bob := sin(t / 20.0) * 2
		Art.text(self, "IRON ADVANCE", Vector2(486, 98 + bob), 48, Color("1a0a08"), HORIZONTAL_ALIGNMENT_CENTER, 6)
		Art.text(self, "IRON ADVANCE", Vector2(483, 95 + bob), 48, Color("b8401c"), HORIZONTAL_ALIGNMENT_CENTER, 5)
		Art.text(self, "IRON ADVANCE", Vector2(480, 92 + bob), 48, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 4)
		draw_rect(Rect2(300, 112 + bob, 360, 3), Color("ffd23a"))
		draw_rect(Rect2(300, 115 + bob, 360, 2), Color("b8401c"))
		Art.text(self, "TURN-BASED RUN AND GUN", Vector2(480, 140), 16, Color("ffb070"), HORIZONTAL_ALIGNMENT_CENTER, 3)
		var ver := FileAccess.get_file_as_string("res://version.txt").strip_edges()
		Art.text(self, "BUILD " + (ver if ver != "" else "DEV"), Vector2(950, 530), 8, Color("6c7480"), HORIZONTAL_ALIGNMENT_RIGHT)
		if t % 60 < 40:
			Art.text(self, "3 MISSIONS  4 SOLDIERS  1 IRON BOAR TOO MANY", Vector2(480, 528), 8, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER)
	func draw_brief() -> void:
		var m: Dictionary = Data.MISSIONS[Run.mission]
		Art.text(self, "MISSION %d" % (Run.mission + 1), Vector2(480, 90), 16, Color("ff7a3d"), HORIZONTAL_ALIGNMENT_CENTER, 2)
		Art.text(self, m.name, Vector2(480, 130), 32, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 3)
		var y := 170.0
		for line in CardView.wrap_text(m.brief, 620, 16):
			Art.text(self, line, Vector2(480, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
			y += 16
		Art.text(self, "IRON BOAR HP %d   ARMOR %d   JACKALS +%d%% HP" % [m.boss_hp, m.plate, int((m.hp_mul - 1) * 100)], Vector2(480, y + 14), 8, Color("9fb4c9"), HORIZONTAL_ALIGNMENT_CENTER)
		var it: Dictionary = Data.INTEL[Run.intel] if Data.INTEL.has(Run.intel) else Data.INTEL.clear
		Art.text(self, "INTEL: %s  %s" % [it.name, it.text.to_upper()], Vector2(480, y + 58), 8, Color("53d4e2") if Run.intel != "clear" else Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER)
		if Run.threat > 0:
			Art.text(self, "THREAT %d: %s" % [Run.threat, ", ".join(Data.THREATS.slice(0, Run.threat).map(func(x): return x.name))], Vector2(480, y + 72), 8, Color("ff7a3d"), HORIZONTAL_ALIGNMENT_CENTER)
		draw_texture_rect(Art.tex.ic_coin, Rect2(410, y + 30, 10, 10), false)
		Art.text(self, "%d SCRIP" % Run.scrip, Vector2(426, y + 40), 8, Color("ffd23a"))
		squad_line(370, "idle")
	func draw_route() -> void:
		Art.text(self, "THE ROAD EAST", Vector2(480, 80), 32, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 3)
		Art.text(self, "Pick one stop before the next mission.", Vector2(480, 112), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
		var n := buttons.size()
		var fs := 16 if buttons.all(func(bt): return Art.text_width(bt[0], 16) < 190) else 8
		for i in n:
			var st: Dictionary = Data.STOPS.values().filter(func(x): return x.name == buttons[i][0])[0]
			var x := 480 - (n * 220) / 2.0 + i * 220 + 10
			draw_rect(Rect2(x, 150, 200, 150), Color(0.06, 0.05, 0.04, 0.85))
			draw_rect(Rect2(x, 150, 200, 150), Color("ffb23e") if i == 0 else Color("9aa2ae"), false, 2)
			Art.text(self, st.name, Vector2(x + 100, 176), fs, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 2)
			var y := 200.0
			for line in CardView.wrap_text(st.text, 180, 16):
				Art.text(self, line, Vector2(x + 100, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
				y += 16
		squad_line(390, "idle")
	func draw_result() -> void:
		var title := "MISSION COMPLETE!" if mode == "won" else ("THE JACKALS GO HOME" if mode == "final" else ("OUTPOST HOLDS" if mode == "outpost_lost" else "MISSION FAILED"))
		var col := Color("62d26f") if mode != "lost" else Color("ff4d3d")
		Art.text(self, title, Vector2(480, 96), 32, col, HORIZONTAL_ALIGNMENT_CENTER, 3)
		if mode == "final":
			Art.text(self, "CAMPAIGN WON. THE ROAD EAST IS OPEN.", Vector2(480, 124), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
			if Run.threat < Data.THREATS.size() and int(Run.meta.threat_max) > Run.threat:
				Art.text(self, "THREAT %d UNLOCKED: %s" % [Run.threat + 1, Data.THREATS[Run.threat].name], Vector2(480, 140), 8, Color("ff7a3d"), HORIZONTAL_ALIGNMENT_CENTER)
			if unlock != "":
				Art.text(self, "ARMORY UNLOCK: " + unlock.to_upper(), Vector2(480, 152), 8, Color("b48cff"), HORIZONTAL_ALIGNMENT_CENTER)
		elif mode == "lost":
			Art.text(self, "THE JACKALS HOLD THE LINE. REGROUP AND GO AGAIN.", Vector2(480, 124), 8, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER)
		var rows := [["SCORE", str(stats.get("score", 0))], ["KILLS", str(stats.get("kills", 0))], ["CRUSHES", str(stats.get("crushes", 0))], ["POWS FREED", str(stats.get("pows", 0))], ["PUSHES", str(stats.get("pushes", 0))], ["ROUNDS", str(stats.get("rounds", 0))], ["SCRIP EARNED", str(stats.get("scrip", 0))]]
		if stats.get("fallen", []).size():
			rows.append(["KILLED IN ACTION", ", ".join(stats.fallen)])
		if mode == "final" or mode == "lost":
			rows.append(["CAMPAIGN SCORE", str(Run.total_score)])
		for i in rows.size():
			Art.text(self, rows[i][0], Vector2(330, 160 + i * 20), 8, Color("e8dcc2"))
			Art.text(self, rows[i][1], Vector2(630, 160 + i * 20), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		squad_line(420, "cheer" if mode != "lost" else "idle")

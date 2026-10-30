extends Node
## Game flow: title -> HQ -> briefing -> mission -> results -> gate home to HQ -> road stop -> next briefing.

const BattleScene := preload("res://scenes/battle.tscn")
const HudScript := preload("res://scripts/hud.gd")
const ShopScript := preload("res://scripts/shop.gd")
const DebriefScript := preload("res://scripts/debrief.gd")
const HqScript := preload("res://scripts/hq.gd")
const WarRoomScript := preload("res://scripts/war_room.gd")
const OperatorCall := preload("res://scripts/operator_call.gd")
const DraftScript := preload("res://scripts/draft.gd")

var battle: Battle = null
var hud: CanvasLayer = null
var screen: Control = null
var ui_layer: CanvasLayer
var speed := 1.0

var call_layer: CanvasLayer = null
var pending_call: Array = []   # C4: radio lines waiting for the squad to hit the ground
var pending_intro = -1

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
	Run.sway_mul = 1.0   # a biome's sway rule only lasts while its battle is up
	if screen != null:
		screen.queue_free()
		screen = null
	if battle != null:
		battle.queue_free()
		battle = null
	if hud != null:
		hud.queue_free()
		hud = null

const BACK_WORDS := ["BACK", "DONE", "CLOSE", "CANCEL", "STAY"]

func _input(ev: InputEvent) -> void:
	## Right-click is always cancel / back: outside battle (and over the battle's deck viewer or
	## a field Dossier) it does exactly what Esc does. In the field the battle keeps it for
	## cancelling an armed card.
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT):
		return
	if battle != null and is_instance_valid(battle) and not field_overlay():
		return
	get_viewport().set_input_as_handled()
	for down in [true, false]:
		var k := InputEventKey.new()
		k.keycode = KEY_ESCAPE
		k.physical_keycode = KEY_ESCAPE
		k.pressed = down
		Input.parse_input_event(k)

func field_overlay() -> bool:
	## The deck viewer or a read-only Dossier is open over the battle.
	if hud == null or not is_instance_valid(hud):
		return false
	if hud.deck_open:
		return true
	return hud.get_children().any(func(c): return c is Control and c.get("readonly") != null)

func _unhandled_input(ev: InputEvent) -> void:
	## Esc that no screen used goes back: it presses the screen's BACK / DONE / CLOSE / CANCEL
	## (or << ...) button, the topmost one that's showing.
	if not (ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE) or battle != null:
		return
	var bt = back_button(ui_layer)
	if bt != null:
		get_viewport().set_input_as_handled()
		Sfx.play("click")
		bt.pressed.emit()

func back_button(n: Node):
	## The last (topmost) visible, enabled back button under n.
	var found = null
	for c in n.get_children():
		if c is CanvasItem and not c.visible:
			continue
		var sub = back_button(c)
		if sub != null:
			found = sub
		elif c is Control and c.has_signal("pressed") and c.get("text") is String and not c.get("disabled"):
			var t: String = c.text
			if t.begins_with("<<") or BACK_WORDS.has(t):
				found = c
	return found

func _notification(what: int) -> void:
	## Closing the window between ops keeps the campaign; mid-op it rolls back to the last HQ save.
	if what == NOTIFICATION_WM_CLOSE_REQUEST and Run.campaign() and battle == null:
		Run.save_campaign()

func call_in(lines: Array) -> void:
	## C4: someone calls in on the field tablet in the top-right corner. It sits on its own
	## layer, so it stays up while screens change underneath it.
	if lines.is_empty():
		return
	if call_layer == null:
		call_layer = CanvasLayer.new()
		call_layer.layer = 8
		add_child(call_layer)
	for c in call_layer.get_children():
		c.queue_free()
	var oc: Control = OperatorCall.new()
	oc.lines = lines
	call_layer.add_child(oc)

func show_title() -> void:
	clear()
	if call_layer != null:
		for c in call_layer.get_children():
			c.queue_free()
	pending_call = []
	Run.leave_campaign()
	var s := Screen.new()
	s.mode = "title"
	# N4: each mode says what it is
	s.buttons = [["CAMPAIGN", func(): show_slots(), "5 ACTS  COMPANY OF %d  SAVED" % Data.COMPANY_MAX],
		["QUICK RUN", func(): quick_run(), "%d LEVELS AND A FINALE" % Data.LEVELS.size()],
		["TRAINING", func(): start_training(), "OPTIONAL  LEARN THE BASICS", Color("9aa2ae") if Run.meta.get("trained", false) else Color("ffb23e")]]
	s.corner = ["DAILY OP", func(): start_daily()]  # D2
	# V6: the blood and ichor sprays can be switched off
	s.corner2 = ["BLOOD: " + ("ON" if Run.meta.get("blood", true) else "OFF"), func():
		Run.meta["blood"] = not Run.meta.get("blood", true)
		Run.save_meta()
		Sfx.play("click")
		show_title()]
	var tmax := mini(int(Run.meta.threat_max), Data.THREATS.size())
	if tmax > 0:
		# W5: every campaign win opens the next threat level
		s.buttons.append(["THREAT %d" % Run.threat, func():
			Run.threat = (Run.threat + 1) % (tmax + 1)
			Sfx.play("click")
			show_title()])
	open(s)

func quick_run() -> void:
	## X1: with more than four classes unlocked a run starts at the squad draft.
	if Run.class_keys().size() > 4:
		show_draft()
	else:
		start_run()

func show_draft() -> void:
	## X1: more than four classes unlocked, so the run starts with picking the squad.
	clear()
	var d: Control = DraftScript.new()
	d.go.connect(start_run)
	d.back.connect(show_title)
	open(d)

func start_run() -> void:
	Run.leave_campaign()
	Run.daily = ""
	Run.new_run()
	if not Run.meta.get("ran", false):
		Run.meta["ran"] = true  # P8: only the first quick run ever gets the plainer level 1
		Run.save_meta()
	show_hq(false)

func start_daily() -> void:
	## D2: today's seed, today's squad. The best score of the day is kept.
	Run.leave_campaign()
	Run.start_daily()
	show_hq(false)

# ---------------------------------------------------------------- campaign mode
func show_slots() -> void:
	clear()
	var p: Control = WarRoomScript.SlotPicker.new()
	p.picked.connect(func(slot: int, fresh: bool):
		Sfx.play("start")
		if fresh or not Run.load_campaign(slot):
			Run.new_campaign(slot)
		if Run.camp.get("done", false):
			show_ending()
		else:
			show_hq(false)
			if not Run.camp.get("landfall", false) and int(Run.camp.get("ops", 0)) == 0:
				Run.camp["landfall"] = true
				var sq: Array = Run.soldiers.filter(func(s): return s.alive)
				call_in(Data.RADIO_LANDFALL.map(func(r): return Run.radio_line(r[0], r[1], sq)).filter(func(l): return not l.is_empty())))
	p.back.connect(show_title)
	open(p)

func show_war_room() -> void:
	clear()
	Run.save_campaign()
	var w: Control = WarRoomScript.new()
	w.attack.connect(func(sc: Dictionary, patrol: bool):
		var intro_was = Run.camp.get("intro", -1)
		Run.start_op(sc, patrol)
		# C4: Command's word comes in on the tablet once the squad is on the ground
		pending_call = Run.radio_before()
		pending_intro = intro_was
		show_brief())
	w.back.connect(func(): show_hq(false))
	w.quit.connect(show_title)
	open(w)

func show_ending() -> void:
	## S5: the war is over. Service records, the Memorial, and a Second Tour.
	clear()
	var e: Control = WarRoomScript.EndingScreen.new()
	e.tour.connect(func(vet: Dictionary):
		Run.second_tour(vet)
		show_hq(false))
	e.title.connect(show_title)
	open(e)

func show_radio(lines: Array, then: Callable) -> void:
	## S2: radio chatter, then on to whatever comes next.
	clear()
	var r: Control = WarRoomScript.RadioScreen.new()
	r.lines = lines
	r.done.connect(then)
	open(r)

func campaign_home(st := {}) -> void:
	## After an op: the radio, held sectors pay, the squad is patched up, promotions and training
	## are picked, then HQ with the news.
	var talk := Run.radio_after(st) if st.has("won") else []
	var inc := Run.after_op(st)
	var news: Array = []
	for k in ["deserter", "engineer", "bonus"]:
		if inc[k] != "":
			news.append(inc[k])
	news.append_array(inc.challenges)
	if inc.nemesis != "":
		news.append(inc.nemesis)
	if inc.varga != "":
		news.append(inc.varga)
	news.append_array(inc.orders)
	news.append_array(inc.bonds)
	news.append_array(inc.promos)
	for m in inc.medals:
		news.append("Medal for " + m + ".")
	if int(inc.bench) > 0 and Run.bench().size():
		news.append("The bench trained: +%d XP each." % inc.bench)
	var parts: Array = []
	for k in ["scrip", "salvage", "bio"]:
		if int(inc[k]) > 0:
			parts.append("+%d %s" % [inc[k], k])
	if parts.size():
		news.append("Held sectors paid " + ", ".join(parts) + ".")
	news.append("Everyone is patched up and has their dog tags back.")
	if inc.rookies.size():
		news.append("Command sent replacements: %s." % ", ".join(inc.rookies))
	# W2: a stronghold that ends an act gets its own ceremony, and the act's MVP a field promotion
	var cleared := -1
	if st.get("op", {}).has("act_done") and not Run.camp.get("done", false):
		cleared = int(Run.camp.act) - 1
	var mvp := {}
	if cleared >= 0:
		mvp = Run.act_mvp(cleared)
		if not mvp.is_empty():
			mvp.promo = int(mvp.get("promo", 0)) + 1
			mvp["field"] = int(mvp.get("field", 0)) + 1
			news.append("%s was the MVP of Act %s: a field promotion pick." % [mvp.def.name, Run.act(cleared).roman])
	var home := func():
		if Run.camp.get("done", false):
			Run.save_campaign()
			show_ending()
		elif Run.pending_picks().size():
			show_picks(func(): show_hq(true); screen.news = news)
		else:
			show_hq(true)
			screen.news = news
	if cleared >= 0:
		# the act's radio waits for HQ, so it doesn't cover the next front on the ceremony
		show_act_end(cleared, mvp, func(): home.call(); call_in(talk))
		return
	home.call()
	call_in(talk)  # C4: Command's word comes in on the tablet over HQ

func show_act_end(a: int, mvp: Dictionary, then: Callable) -> void:
	## W2: the act's ceremony: what it took, its MVP, and the next front rolling out.
	clear()
	var e: Control = WarRoomScript.ActEndScreen.new()
	e.act_i = a
	e.mvp = mvp
	e.done.connect(then)
	open(e)

func show_picks(then: Callable) -> void:
	## C3/C4: promotions and the bench's training levels, one pick each.
	clear()
	var p: Control = WarRoomScript.PickQueue.new()
	p.done.connect(then)
	open(p)

func show_hq(arrived: bool) -> void:
	## Home base between missions. The gate dials straight into mission 1 at the start of a run,
	## and onto the road east after that.
	clear()
	if not Run.campaign():
		Run.mission = Run.history.size()  # the next level, so the Quartermaster restocks for it
	var h: Control = HqScript.new()
	h.arrived = arrived
	h.dial.connect(show_war_room if Run.campaign() else dial_gate)
	screen = h
	ui_layer.add_child(h)

func dial_gate() -> void:
	## The gate dial: two biomes for the next level, pick one and the other is burned.
	## After the third level the gate only dials one place, the harbor finale.
	Run.mission = Run.history.size()
	Run.discount = 0.0
	if Run.mission >= Data.LEVELS.size():
		Run.start_finale()
		show_brief()
		return
	if Run.dial.is_empty():
		Run.roll_dial()
	clear()
	var s := Screen.new()
	s.mode = "dial"
	for b in Run.dial:
		var id: String = b
		s.buttons.append([Data.BIOMES[id].name, func(): Sfx.play("start"); Run.pick_biome(id); show_brief()])
	s.buttons.append(["<< BACK TO HQ", func(): show_hq(false)])
	if Run.hq("gate") >= 2 and not Run.dial_rerolled:
		s.buttons.append(["REROLL THE DIAL", func(): Sfx.play("click"); Run.reroll_dial(); dial_gate()])
	open(s)

func show_brief() -> void:
	clear()
	Run.side = ""
	Run.roll_intel()
	var s := Screen.new()
	s.mode = "brief"
	s.buttons = [["DEPLOY", func(): start_battle(Run.mission, Run.current_mission())]]
	if Run.campaign():
		s.buttons = [["DEPLOY", func(): start_battle(int(Run.act().tier), Run.current_mission())], ["<< WAR ROOM", func():
			# backing out un-hears the call, so an act's opening still plays on the next attack
			Run.camp["intro"] = pending_intro
			pending_call = []
			Run.level = {}
			show_war_room()]]
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
	if pending_call.size():
		call_in(pending_call)
		pending_call = []
	return battle

func start_training() -> void:
	## N6: the optional drill. A fresh squad, the sergeant on the tablet, and nothing carries over.
	Run.new_run()
	var b := start_battle(0, Data.TRAINING.duplicate(true))
	b.mission_over.disconnect(_on_mission_over)
	b.mission_over.connect(func(won: bool):
		if won:
			Run.meta["trained"] = true
			Run.save_meta()
		Run.new_run()
		show_title()
		call_in((Data.TUT_DONE_LINES if won else Data.TUT_FAIL_LINES).map(func(l): return Run.radio_line("sarge", l, []))))

func start_practice(i: int) -> void:
	## D5: one soldier, their deck as it stands, dummies that never shoot back. Everything the
	## range touches (HP, scrip, cards, XP) is put back when you leave.
	var snap := Run.snapshot()
	var s: Dictionary = Run.soldiers[i]
	var lv := {"name": "PRACTICE RANGE", "theme": "dusk", "segments": ["start", "range"], "boss_hp": 1, "plate": 0,
		"hp_mul": 1.0, "brief": "", "rules": {"pads": 0}, "practice": true, "only": s.key}
	var b := start_battle(0, lv)
	b.mission_over.disconnect(_on_mission_over)
	b.mission_over.connect(func(_w): end_practice(snap, i))

func end_practice(snap: Dictionary, i: int) -> void:
	Run.restore(snap)
	show_hq(false)
	screen.open_dossier(i)

func _on_mission_over(won: bool) -> void:
	# a field call nobody closed is stale once the fight ends; it shouldn't sit over the results
	if call_layer != null:
		for c in call_layer.get_children():
			c.queue_free()
	var st: Dictionary = battle.stats.duplicate()
	st["score"] = battle.score
	st["won"] = won
	var xp := {}
	var kills := {}
	var downs := {}
	var by := {}
	for u in battle.squad():
		if u.s.has("guest"):
			st["varga_alive"] = not (u.dead and not u.downed)  # W13: still standing (or only down) when it ends
			continue
		xp[u.def.key] = u.xp_gain
		kills[u.def.key] = u.kills
		downs[u.def.key] = u.downed or u.dead
		if Run.campaign() and Run.roster.has(u.s):
			by[str(Run.roster.find(u.s))] = {"xp": u.xp_gain, "k": u.kills, "down": u.downed or u.dead}  # W9: two of a class on the pincer
	st["xp"] = xp
	if by.size():
		st["by"] = by
	st["kills_by"] = kills
	for u in battle.units:
		# W3: a named officer still standing when the op ends gets away
		if u.fl.has("quarry") and not u.dead and Run.campaign():
			st["nemesis_escaped"] = {"name": u.fl.get("nemesis", u.fl.quarry), "type": u.type, "elite": u.elite}
	st["downed_by"] = downs
	if won:
		st["bounties"] = Run.pay_bounties(st)  # R5; O1: campaign ops pay them into the company's scrip too
	Run.history.append(st)
	clear()
	var s := Screen.new()
	s.stats = st
	if Run.campaign():
		# P5: a lost op only sends the squad home; the sector stays open
		var res := Run.op_over(won and Run.alive_count() > 0)
		st["op"] = res
		s.mode = "op_won" if won and Run.alive_count() > 0 else "op_lost"
		if s.mode == "op_won":
			s.buttons = [["OPEN SUPPLY CRATES", func(): show_debrief(st)]]
		else:
			s.buttons = [["BACK TO HQ", func(): campaign_home(st)]]
		open(s)
		return
	if Run.side == "outpost" and Run.alive_count() > 0:
		# W1: an outpost loss only costs the wounded; a win pays an Epic crate and a Boar part
		s.mode = "won" if won else "outpost_lost"
		s.buttons = [["OPEN THE SPOILS", func(): show_spoils([3], true)]] if won else [["NEXT MISSION", func(): next_mission()]]
		open(s)
		return
	if not won or Run.alive_count() == 0 or Run.is_final_mission():
		Run.daily_over()
	if not won or Run.alive_count() == 0:
		s.mode = "lost"
		s.buttons = [["NEW RUN", func(): quick_run()], ["TITLE", func(): show_title()]]
	elif Run.is_final_mission():
		s.mode = "final"
		s.buttons = [["NEW RUN", func(): quick_run()], ["TITLE", func(): show_title()]]
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
	d.done.connect(func(): campaign_home(st) if Run.campaign() else show_hq(true))
	screen = d
	ui_layer.add_child(d)

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
	show_hq(false)

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
	var corner: Array = []  # a small extra button in the top-left corner: [label, callable]
	var corner2: Array = []  # and one in the top-right corner
	var t := 0
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if corner.size():
			var cb = load("res://scripts/hud.gd").PixButton.new()
			cb.text = corner[0]
			cb.small = true
			cb.color = Color("53d4e2")
			cb.size = Vector2(170, 28)
			cb.position = Vector2(20, 18)
			cb.pressed.connect(corner[1])
			add_child(cb)
		if corner2.size():
			var cb2 = load("res://scripts/hud.gd").PixButton.new()
			cb2.text = corner2[0]
			cb2.small = true
			cb2.color = Color("9aa2ae")
			cb2.size = Vector2(170, 28)
			cb2.position = Vector2(770, 18)
			cb2.pressed.connect(corner2[1])
			add_child(cb2)
		var n := buttons.size()
		var widths: Array = []
		var total := 0.0
		for i in n:
			var bw := maxf(250.0 if i == 0 or (mode in ["dial", "title"] and i < 2) else 140.0, Art.text_width(buttons[i][0], 16) + 40)
			if buttons[i].size() > 2:
				bw = maxf(bw, Art.text_width(buttons[i][2], 8) + 24)
			widths.append(bw)
			total += bw + (10 if i > 0 else 0)
		var x := 480 - total / 2
		for i in n:
			var bt = load("res://scripts/hud.gd").PixButton.new()
			bt.text = buttons[i][0]
			if buttons[i].size() > 2:
				bt.sub = buttons[i][2]
			var nd := Run.dial.size()
			bt.color = Color("ff4d3d") if i == 0 or (mode == "dial" and i < nd) or (mode == "title" and i == 1) else Color("9aa2ae")
			if buttons[i].size() > 3:
				bt.color = buttons[i][3]
			bt.size = Vector2(widths[i], 40)
			bt.position = Vector2(x, 470)
			if mode == "dial":  # one button under each biome card, then a small way back and the reroll
				if i < nd:
					var cr := dial_card(i)
					bt.size = Vector2(minf(250, cr.size.x - 30), 40)
					bt.position = Vector2(cr.position.x + (cr.size.x - bt.size.x) / 2, 470)
				else:
					bt.small = true
					bt.size = Vector2(170, 28)
					bt.position = Vector2(20, 18) if i == nd else Vector2(770, 18)
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
			theme = Run.current_mission().theme
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
			"won", "final", "lost", "outpost_lost", "op_won", "op_lost": draw_result()
			"dial": draw_dial()
			"hospital":
				Art.text(self, "FIELD HOSPITAL", Vector2(480, 110), 32, Color("62d26f"), HORIZONTAL_ALIGNMENT_CENTER, 3)
				Art.text(self, "Everyone is patched up and gets one dog tag back. The dead stay dead.", Vector2(480, 150), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
				squad_line(370, "cheer")
	func squad_line(y: float, anim: String) -> void:
		var i := 0
		var line: Array = Run.soldiers if Run.soldiers.size() else Data.SQUAD_DEFS.filter(func(d): return Data.BASE_CLASSES.has(d.key)).map(func(d): return {"key": d.key, "alive": true, "def": d, "lvl": 1})
		var gap := 100.0 if line.size() <= 4 else 72.0  # a fifth soldier squeezes in between the briefing's side panels
		for s in line:
			var x := 480 - (line.size() - 1) * gap / 2.0 + i * gap
			var a := anim if s.alive else "die"
			Art.draw_char(self, Art.look_sheet(s), a, (t / 6) % 8 if a == "run" else ((t / 12 + i) % 4 if a == "idle" else (t / 10) % 2 if a == "cheer" else 5), Vector2(x, y), 1, false, 0, 1.0, 0, a != "cheer" and a != "die", 2.0)
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
		if corner.size():
			var best := Run.daily_best()
			Art.text(self, ("TODAY'S BEST %d" % best) if best > 0 else "ONE SEED A DAY", Vector2(105, 60), 8, Color("53d4e2"), HORIZONTAL_ALIGNMENT_CENTER)
		var ver := FileAccess.get_file_as_string("res://version.txt").strip_edges()
		Art.text(self, "BUILD " + (ver if ver != "" else "DEV"), Vector2(950, 530), 8, Color("6c7480"), HORIZONTAL_ALIGNMENT_RIGHT)
		if t % 60 < 40:
			Art.text(self, "4 SOLDIERS  1 IRON BOAR TOO MANY", Vector2(480, 528), 8, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER)
	func draw_brief() -> void:
		var m: Dictionary = Run.current_mission()
		var head := "FINALE" if m.get("finale", false) else ("LEVEL %d OF %d" % [Run.mission + 1, Data.LEVELS.size()] if m.has("biome") else "MISSION %d" % (Run.mission + 1))
		if Run.campaign():
			head = "ACT %s  %s" % [Run.act().roman, m.banner]
		Art.text(self, head, Vector2(480, 90), 16, Color("ff7a3d"), HORIZONTAL_ALIGNMENT_CENTER, 2)
		Art.text(self, m.name, Vector2(480, 130), 32, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 3)
		var y := 170.0
		var jb: String = m.get("job", "push")
		var txt: String = m.brief if jb == "push" else Run.job_text(jb)
		if m.get("story", "") == "varga":
			txt = Data.VARGA_STAND_BRIEF  # W13: the prisoners are his garrison, not ours
		brief_plate(m, CardView.wrap_text(txt, 620, 16).size())
		for line in CardView.wrap_text(txt, 620, 16):
			Art.text(self, line, Vector2(480, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
			y += 16
		y += 4  # room between the last line of the brief and the GOOD FOR / ROUGH ON line
		if jb == "push":
			Art.text(self, "IRON BOAR HP %d   ARMOR %d   JACKALS +%d%% HP" % [m.boss_hp, m.plate, roundi((m.hp_mul - 1) * 100)], Vector2(480, y + 14), 8, Color("9fb4c9"), HORIZONTAL_ALIGNMENT_CENTER)
		else:
			Art.text(self, "%s: %s   JACKALS +%d%% HP   PAYS +%d SCRIP" % [Data.JOBS[jb].name, Data.JOBS[jb].goal, roundi((m.hp_mul - 1) * 100), Data.JOB_PAY], Vector2(480, y + 14), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
		if m.has("biome"):
			var bm: Dictionary = Data.BIOMES[m.biome]
			Art.text(self, "GOOD FOR %s   ROUGH ON %s" % [Data.STYLES[bm.favor], Data.STYLES[bm.rough]], Vector2(480, y - 2), 8, Color("ffb23e"), HORIZONTAL_ALIGNMENT_CENTER)
		# a long brief (3+ lines) closes up the rows under it, so the last one still clears the squad's heads
		var tight := y > 210.0
		var sy := y + (32.0 if tight else 40.0)
		var iy := sy + (14.0 if tight else 18.0)
		var it: Dictionary = Data.INTEL[Run.intel] if Data.INTEL.has(Run.intel) else Data.INTEL.clear
		Art.text(self, "INTEL: %s  %s" % [it.name, it.text.to_upper()], Vector2(480, iy), 8, Color("53d4e2") if Run.intel != "clear" else Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER)
		if Run.campaign() and Run.hq("comms") >= 1:
			var ros: Array = CardView.wrap_text("COMMS: " + Run.op_roster(m), 900, 16)
			for k in mini(2, ros.size()):
				Art.text(self, ros[k], Vector2(480, 440 + k * 15), 16, Color("62d26f"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
		var ny := iy + 14
		if Run.threat > 0:
			Art.text(self, "THREAT %d: %s" % [Run.threat, ", ".join(Data.THREATS.slice(0, Run.threat).map(func(x): return x.name))], Vector2(480, ny), 8, Color("ff7a3d"), HORIZONTAL_ALIGNMENT_CENTER)
		if m.get("nemesis", {}).size():
			# W3: an officer who got away before is waiting
			Art.text(self, "NEMESIS: %s IS HERE. KILL THEM FOR THEIR SIGNATURE GEAR." % Run.nemesis_name(m.nemesis), Vector2(480, ny + (14 if Run.threat > 0 else 0)), 8, Color("ff4d3d") if t % 50 < 34 else Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
			ny += 14
		if m.get("pincer", false):
			# W9: the two-squad assault
			Art.text(self, "PINCER: SQUAD B (%s) LANDS ON THE FAR SIDE. G JUMPS BETWEEN THEM." % ", ".join(Run.wing_b().map(func(s): return s.def.name)), Vector2(480, ny + (14 if Run.threat > 0 else 0)), 8, Color("53d4e2"), HORIZONTAL_ALIGNMENT_CENTER)
			ny += 14
		if m.get("story", "") == "varga":
			# W13: the colonel's last stand
			Art.text(self, "LAST STAND: BRING COLONEL VARGA OUT ALIVE AND HE JOINS THE COMPANY.", Vector2(480, ny + (14 if Run.threat > 0 else 0)), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
			ny += 14
		if m.get("specialist", "") != "":
			# X2: a specialist is held somewhere in this level
			var D: Dictionary = Run.class_def(m.specialist)
			Art.text(self, "SPECIALIST POW: %s THE %s IS HELD HERE. FREE THEM TO UNLOCK THE CLASS." % [D.name, D.cls.to_upper()], Vector2(480, ny + (14 if Run.threat > 0 else 0)), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
		draw_texture_rect(Art.tex.ic8_coin, Rect2(410, sy - 10, 10, 10), false)
		Art.text(self, "%d SCRIP" % Run.scrip, Vector2(426, sy), 8, Color("ffd23a"))
		squad_line(382, "idle")  # feet low enough that heads clear the SPECIALIST POW line
		draw_extras(m)  # over the squad, so no rifle pokes through the boards
	func brief_plate(m: Dictionary, n: int) -> void:
		## A dark plate under the brief's text, so the small lines read even over the dusk sun.
		## Mirrors draw_brief's row math: brief lines, GOOD FOR, intel, threat and specialist.
		var y := 170.0 + n * 16 + 4
		var sy := y + (32.0 if y > 210.0 else 40.0)
		var last := sy + (14.0 if y > 210.0 else 18.0)
		if Run.threat > 0:
			last += 14
		if m.get("specialist", "") != "":
			last += 14
		for k in ["nemesis", "pincer", "story"]:
			if m.get(k, false):
				last += 14  # W3/W9/W13 lines under the intel
		draw_rect(Rect2(122, 154, 716, last - 148), Color(0.05, 0.035, 0.03, 0.55))
	func draw_extras(m: Dictionary) -> void:
		## R2-R5: the level's event on the left, its bounty board on the right. D2: the daily tag.
		if Run.daily != "":
			Art.text(self, "DAILY OP  %s" % Run.daily, Vector2(480, 62), 8, Color("53d4e2"), HORIZONTAL_ALIGNMENT_CENTER)
		if Data.EVENTS.has(m.get("event", "")):
			var ev: Dictionary = Data.EVENTS[m.event]
			var evl: Array = CardView.wrap_text(ev.text, 246, 16)
			# 270 wide, so the panel stops short of Moss on the left of the squad line; as tall as its text
			# (full height beside a bounty board, so the two match)
			var eh := 150.0 if m.get("bounties", []).size() else minf(150.0, 54.0 + evl.size() * 16)
			draw_rect(Rect2(16, 296, 270, eh), Color(0.05, 0.035, 0.03, 0.94))  # solid enough that a rifle tip never shows through
			draw_rect(Rect2(16, 296, 270, eh), Color("ffb23e"), false, 1)
			Art.text(self, "EVENT: " + ev.name, Vector2(28, 316), 8, Color("ffb23e"))
			var y := 336.0
			for line in evl:
				Art.text(self, line, Vector2(28, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
				y += 16
		var bs: Array = m.get("bounties", [])
		if bs.size():
			draw_rect(Rect2(674, 296, 270, 150), Color(0.05, 0.035, 0.03, 0.94))
			draw_rect(Rect2(674, 296, 270, 150), Color("ffd23a"), false, 1)
			Art.text(self, "BOUNTY BOARD", Vector2(686, 316), 8, Color("ffd23a"))
			var y := 334.0
			for id in bs:
				var bt: Dictionary = Run.bounty(id)
				Art.text(self, bt.name, Vector2(686, y), 8, Color.WHITE)
				Art.text(self, "+%d$" % bt.pay, Vector2(932, y), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT)
				Art.text(self, bt.text, Vector2(686, y + 15), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
				y += 36
	func dial_card(i: int) -> Rect2:
		## Where biome card i sits: two wide cards, or three narrower ones with Gate Control.
		var n := Run.dial.size()
		var cw := 380.0 if n <= 2 else 296.0
		var gap := 40.0 if n <= 2 else 14.0
		var x0 := (960.0 - n * cw - (n - 1) * gap) / 2.0
		return Rect2(x0 + i * (cw + gap), 108, cw, 352)
	func draw_dial() -> void:
		Art.text(self, "DIAL THE GATE", Vector2(480, 58), 32, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 3)
		Art.text(self, "Level %d of %d. Pick one biome. The others are burned for this run." % [Run.mission + 1, Data.LEVELS.size()], Vector2(480, 90), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
		var al: Array = Run.soldiers.filter(func(so): return so.alive)
		for i in Run.dial.size():
			var id: String = Run.dial[i]
			var bm: Dictionary = Data.BIOMES[id]
			var cr := dial_card(i)
			var x := cr.position.x
			var cw := cr.size.x
			var cx := x + cw / 2
			draw_rect(cr, Color(0.06, 0.05, 0.04, 0.88))
			draw_rect(cr, Color("ffb23e"), false, 2)
			# a window onto the biome: its sky and far hills, tinted by its look
			var sky_mod: Color = bm.look.get("sky", Color.WHITE)
			draw_texture_rect_region(bg("%s_sky" % bm.theme), Rect2(x + 8, 116, cw - 16, 74), Rect2(300, 120, cw - 16, 74), sky_mod)
			var far: Texture2D = bg("%s_far" % bm.theme)
			draw_texture_rect_region(far, Rect2(x + 8, 150, cw - 16, 40), Rect2(0, far.get_height() - 20, (cw - 16) / 2, 20), sky_mod)
			draw_rect(Rect2(x + 8, 186, cw - 16, 4), bm.look.get("grass", Data.THEMES[bm.theme].grass))
			Art.text(self, bm.name, Vector2(cx, 150), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 3)
			if Run.dial_breach.get(id, false):
				Art.text(self, "BREACH: VHARR AND JACKALS AT WAR", Vector2(cx, 178), 8, Color("9df25c"), HORIZONTAL_ALIGNMENT_CENTER, 2)
			var y := 210.0
			for line in CardView.wrap_text(bm.text, cw - 28, 16):
				Art.text(self, line, Vector2(cx, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
				y += 16
			y = maxf(y + 6, 272)
			Art.text(self, "GOOD FOR " + Data.STYLES[bm.favor], Vector2(cx, y), 8, Color("62d26f"), HORIZONTAL_ALIGNMENT_CENTER)
			Art.text(self, "ROUGH ON " + Data.STYLES[bm.rough] + (": " + bm.why if bm.has("why") else ""), Vector2(cx, y + 14), 8, Color("ff7a5a"), HORIZONTAL_ALIGNMENT_CENTER)
			if Run.hq("gate") >= 3 and Run.dial_levels.has(id):
				# Gate Control 3: the address shows what is on the other side
				var lv: Dictionary = Run.dial_levels[id]
				var segs: Array = lv.segments.filter(func(sg): return not sg in ["start", "camp", "yard", "arena", "pier"])
				Art.text(self, " ".join(segs.map(func(sg): return sg.to_upper())), Vector2(cx, 438), 8, Color("53d4e2"), HORIZONTAL_ALIGNMENT_CENTER)
				if lv.get("boss", "") == "hiveship":
					Art.text(self, "HIVE SHIP HP %d   2 HULL PLATES" % lv.boss_hp, Vector2(cx, 452), 8, Color("c47bff"), HORIZONTAL_ALIGNMENT_CENTER)
				else:
					Art.text(self, "BOSS HP %d   ARMOR %d" % [lv.boss_hp, lv.plate], Vector2(cx, 452), 8, Color("53d4e2"), HORIZONTAL_ALIGNMENT_CENTER)
			# how each soldier's deck fits this biome
			y += 38
			# five soldiers still fit inside the card; the bottom is free unless Gate Control 3 prints there
			var bottom := 430.0 if Run.hq("gate") >= 3 and Run.dial_levels.has(id) else 456.0
			var step := minf(30.0, (bottom - y) / maxf(1, al.size()))
			for j in al.size():
				var so: Dictionary = al[j]
				var f := Run.fit(so, id)
				var fc: Color = {"great": Color("62d26f"), "ok": Color("e8dcc2"), "rough": Color("ff7a5a")}[f]
				var row := y + j * step
				Art.draw_char(self, Art.look_sheet(so), "idle", (t / 12 + j) % 4, Vector2(x + 32, row + 14), 1, false, 0, 1.0, 0, true, 0.8)
				Art.text(self, so.def.name, Vector2(x + 60, row + 8), 8, Color.WHITE)
				Art.text(self, f.to_upper(), Vector2(x + cw - 20, row + 8), 8, fc, HORIZONTAL_ALIGNMENT_RIGHT)
				var sh := Run.styles(so)
				var bw := cw - 260 if cw > 300 else cw - 196
				var bx := x + 150 if cw > 300 else x + 116
				var k := 0
				for st in ["long", "close", "arc"]:
					var w := int(round(sh[st] * bw))
					draw_rect(Rect2(bx + k, row + 1, w, 7), {"long": Color("53d4e2"), "close": Color("ffb23e"), "arc": Color("ff4d3d")}[st])
					k += w
				draw_rect(Rect2(bx, row + 1, bw, 7), Color("6c7480"), false, 1)
				if step >= 26:  # too tight for a second line: the bar already says it
					Art.text(self, loadout_line(so), Vector2(x + 60, row + 21), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		var lx := 330.0
		for lg in [["DECK BAR:", Color("9aa2ae")], ["LONG GUNS", Color("53d4e2")], ["CLOSE", Color("ffb23e")], ["EXPLOSIVES", Color("ff4d3d")]]:
			Art.text(self, lg[0], Vector2(lx, 528), 8, lg[1])
			lx += Art.text_width(lg[0], 8) + 18
	func loadout_line(so: Dictionary) -> String:
		## H5: what this soldier brings, in a few words: "8 AIM cards, Scoped Rifle".
		var types := {}
		for c in so.deck:
			var ty: String = Data.card(c).type
			types[ty] = types.get(ty, 0) + 1
		var top := ""
		for ty in types:
			if top == "" or types[ty] > types[top]:
				top = ty
		var out := "%d %s cards of %d" % [types.get(top, 0), top, so.deck.size()]
		var wp = so.equip.get("weapon")
		if wp != null:
			out += ", " + Data.item_name(wp)
		return out
	func draw_result() -> void:
		if mode in ["op_won", "op_lost"]:
			draw_op_result()
			return
		var title := "MISSION COMPLETE!" if mode == "won" else ("THE JACKALS GO HOME" if mode == "final" else ("OUTPOST HOLDS" if mode == "outpost_lost" else "MISSION FAILED"))
		var col := Color("62d26f") if mode != "lost" else Color("ff4d3d")
		Art.text(self, title, Vector2(480, 96), 32, col, HORIZONTAL_ALIGNMENT_CENTER, 3)
		if mode == "final":
			Art.text(self, "RUN WON. THE ROAD EAST IS OPEN.", Vector2(480, 124), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
			if Run.threat < Data.THREATS.size() and int(Run.meta.threat_max) > Run.threat:
				Art.text(self, "THREAT %d UNLOCKED: %s" % [Run.threat + 1, Data.THREATS[Run.threat].name], Vector2(480, 140), 8, Color("ff7a3d"), HORIZONTAL_ALIGNMENT_CENTER)
			if unlock != "":
				Art.text(self, "ARMORY UNLOCK: " + unlock.to_upper(), Vector2(480, 152), 8, Color("b48cff"), HORIZONTAL_ALIGNMENT_CENTER)
		elif mode == "lost":
			# N3: what ended it, and what the next run keeps
			var why := "SQUAD WIPED. LAST DOWN: %s." % stats.last_down if stats.has("last_down") else "SQUAD WIPED."
			Art.text(self, why, Vector2(480, 124), 8, Color("ff9a80"), HORIZONTAL_ALIGNMENT_CENTER)
			Art.text(self, "THIS RUN IS OVER. SALVAGE, BIO-PARTS, HQ UPGRADES AND UNLOCKS CARRY TO THE NEXT ONE.", Vector2(480, 140), 8, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER)
		var rows := [["SCORE", str(stats.get("score", 0))], ["KILLS", str(stats.get("kills", 0))], ["CRUSHES", str(stats.get("crushes", 0))], ["POWS FREED", str(stats.get("pows", 0))], ["PUSHES", str(stats.get("pushes", 0))], ["ROUNDS", str(stats.get("rounds", 0))], ["SCRIP EARNED", str(stats.get("scrip", 0))]]
		if int(stats.get("salvage", 0)) > 0:
			rows.append(["SALVAGE FOR HQ", str(stats.salvage)])
		if stats.get("fallen", []).size():
			rows.append(["KILLED IN ACTION", ", ".join(stats.fallen)])
		for bt in stats.get("bounties", []):
			rows.append(["BOUNTY " + bt[0], ("+%d$" % bt[1]) if bt[2] else "MISSED"])
		if mode == "final" or mode == "lost":
			rows.append(["RUN SCORE", str(Run.total_score)])
		draw_rows(rows, 172.0 if mode == "final" else 160.0)
		squad_line(420, "cheer" if mode != "lost" else "idle")
	func draw_rows(rows: Array, top: float) -> void:
		## The stat table squeezes its rows together so the last one stays clear of the squad's heads.
		var step := minf(20.0, (332.0 - top) / maxf(1, rows.size()))  # cheering arms reach up to ~335
		# a dark plate under the table, so the numbers read even over the dusk sun
		draw_rect(Rect2(286, top - 13, 388, (rows.size() - 1) * step + 20), Color(0.05, 0.035, 0.03, 0.55))
		for i in rows.size():
			Art.text(self, rows[i][0], Vector2(300, top + i * step), 8, Color("e8dcc2"))
			Art.text(self, rows[i][1], Vector2(660, top + i * step), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	func draw_op_result() -> void:
		var op: Dictionary = stats.get("op", {})
		var title := "OP FAILED"
		var line := "THE SQUAD IS CARRIED HOME. THE SECTOR STAYS OPEN. TRY AGAIN WITH ANYONE."
		if mode == "op_won":
			title = "PATROL COMPLETE" if Run.level.get("patrol", false) else "SECTOR TAKEN!"
			line = "HALF PAY. THE SECTOR WAS ALREADY YOURS." if Run.level.get("patrol", false) else ""
			if op.has("act_done"):
				title = "ACT %s CLEARED!" % Data.ACTS[maxi(0, Run.act_index(op.act_done))].roman
				line = "THE WAR IS WON." if Run.camp.get("done", false) else "THE FRONT MOVES ON: ACT %s, %s." % [Run.act().roman, Run.act().name]
			elif op.has("bonus"):
				title = "BONUS OP DONE!"
				line = "%s: %s" % [op.bonus, {"salvage": "+%d SALVAGE FOR HQ." % Data.BONUS_SALVAGE, "defector": "A JACKAL DEFECTOR JOINS THE COMPANY.", "crash": "ALIEN KILLS COUNT DOUBLE AT THE LAB."}.get(op.get("pay", ""), "EPIC GEAR IN THE STASH.")]
			elif op.has("perk"):
				line = "%s: %s" % [Data.SECTOR_PERKS[op.perk].name, Data.SECTOR_PERKS[op.perk].text.to_upper()]
			elif Run.level.get("story", "") == "varga" and not Run.level.get("patrol", false):
				# W13: the last stand's payoff, not just another sector
				line = "COLONEL VARGA MADE IT OUT. HE JOINS IRON COMPANY." if stats.get("varga_alive", false) else "COLONEL VARGA FELL COVERING HIS MEN."
			elif op.has("took"):
				line = "%s IS YOURS. IT PAYS AFTER EVERY OP FROM NOW ON." % op.took
		Art.text(self, title, Vector2(480, 96), 32, Color("62d26f") if mode == "op_won" else Color("ff4d3d"), HORIZONTAL_ALIGNMENT_CENTER, 3)
		Art.text(self, line, Vector2(480, 124), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
		if mode == "op_won" and stats.has("job_note"):
			Art.text(self, "JOB DONE: +%d SCRIP. %s" % [int(stats.get("job_pay", 0)), str(stats.job_note).to_upper()], Vector2(480, 140), 8, Color("62d26f"), HORIZONTAL_ALIGNMENT_CENTER)
		var rows := [["SCORE", str(stats.get("score", 0))], ["KILLS", str(stats.get("kills", 0))], ["POWS FREED", str(stats.get("pows", 0))], ["ROUNDS", str(stats.get("rounds", 0))], ["SCRIP EARNED", str(stats.get("scrip", 0))]]
		if int(stats.get("salvage", 0)) > 0:
			rows.append(["SALVAGE FOR HQ", str(stats.salvage)])
		if stats.get("fallen", []).size():
			rows.append(["KILLED IN ACTION", ", ".join(stats.fallen)])
		for bt in stats.get("bounties", []):
			rows.append(["BOUNTY " + bt[0], ("+%d$" % bt[1]) if bt[2] else "MISSED"])
		rows.append(["OPS FOUGHT", str(Run.camp.get("ops", 0))])
		draw_rows(rows, 160.0)
		squad_line(420, "cheer" if mode == "op_won" else "idle")

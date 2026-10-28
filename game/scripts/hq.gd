extends Control
## HQ: the base the squad comes home to through the gate after every boss. Each building
## opens its own screen (Quartermaster, Barracks, Armory, Memorial) and the gate dials the next stop.

signal dial

const HudScript := preload("res://scripts/hud.gd")
const ShopScript := preload("res://scripts/shop.gd")
const ArmoryScript := preload("res://scripts/armory.gd")
const DossierScript := preload("res://scripts/dossier.gd")
const WorkshopScript := preload("res://scripts/workshop.gd")
const HubUI := preload("res://scripts/hub_ui.gd")
const Services := preload("res://scripts/services.gd")

const GROUND := 430.0
const GATE := Vector2(480, 340)
const GATE_R := 72.0

var arrived := false        # true when the squad just stepped out of the gate
var t := 0
var sub: Control = null     # the building screen that is open, if any
var memorial_open := false
var upgrades_open := false
var doc_open := false
var lab_open := false        # B5: the Alien Lab board (campaign)
var held := {}              # textures must stay referenced until the frame renders
var hover_troop := -1       # the soldier in the scene under the mouse
var walk := {}              # H4: the squad trotting over to a building: {id, x, t}
var dial_btn: Control = null
var news: Array = []        # campaign: what happened since the last op, shown on arrival

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if arrived:
		Sfx.play("power")
	if news.is_empty() and not Run.campaign() and Run.history.is_empty() and Run.tips_on() and not Run.meta.get("hq_welcome", false):
		# N2: the first HQ a new player sees says what is urgent (nothing) and what can wait
		Run.meta["hq_welcome"] = true
		Run.save_meta()
		news = ["WELCOME TO HQ. You can DIAL THE GATE right away: level 1 is built for a fresh squad.",
			"The buildings are for between missions: scrip buys cards at the Quartermaster, salvage upgrades HQ.",
			"Hover a soldier to size them up; click one to open their Dossier."]
	build()

func build() -> void:
	for c in get_children():
		c.queue_free()
	sub = null
	var bar := HubUI.SquadBar.new()
	bar.position = Vector2(16, 76)
	bar.picked.connect(open_dossier)
	bar.all_decks.connect(func(): open_dossier(0, "squad"))
	add_child(bar)
	var spots := [
		["QUARTERMASTER", "BUY CARDS  GEAR", 40, "qm", Color("ffb23e")],
		["BARRACKS", "RECRUITS  DOG TAGS", 230, "barracks", Color("62d26f")],
		["ARMORY", "EQUIP  MERGE  COPY", 600, "armory", Color("53d4e2")],
		["MEMORIAL", "%d NAMES" % Run.meta.memorial.size(), 780, "memorial", Color("9aa2ae")],
	]
	for sp in spots:
		var bt := HudScript.PixButton.new()
		bt.text = sp[0]
		bt.sub = sp[1]
		bt.color = sp[4]
		bt.small = true
		bt.size = Vector2(150, 36)
		bt.position = Vector2(sp[2], 438)
		var id: String = sp[3]
		bt.pressed.connect(func(): walk_to(id))
		add_child(bt)
	var ws := HudScript.PixButton.new()
	ws.text = "WORKSHOP"
	ws.sub = "CHANGE CARDS"
	ws.color = Color("b48cff")
	ws.small = true
	ws.size = Vector2(140, 44)
	ws.position = Vector2(220, 486)
	ws.pressed.connect(func(): walk_to("workshop"))
	add_child(ws)
	var go := HudScript.PixButton.new()
	go.text = "DIAL THE GATE"
	go.sub = "FINALE" if next_mission_n() > Data.LEVELS.size() else "LEVEL %d OF %d" % [next_mission_n(), Data.LEVELS.size()]
	if Run.campaign():
		go.text = "WAR ROOM"
		go.sub = "ACT %s  %d OF %d TAKEN" % [Run.act().roman, mini(Run.held_count(), int(Run.act().need)), int(Run.act().need)]
	if Run.scrip >= Services.price(Services.PATCH):
		go.sub = "%d SCRIP UNSPENT" % Run.scrip
	dial_btn = go
	go.color = Color("ff4d3d")
	go.size = Vector2(220, 44)
	go.position = Vector2(370, 486)
	go.pressed.connect(func(): Sfx.play("start"); dial.emit())
	add_child(go)
	var up := HudScript.PixButton.new()
	up.text = "UPGRADE HQ"
	up.sub = "%d SALVAGE" % int(Run.meta.get("salvage", 0))
	up.color = Color("53d4e2")
	up.small = true
	up.size = Vector2(170, 44)
	up.position = Vector2(40, 486)
	up.pressed.connect(func(): walk_to("upgrades"))
	add_child(up)
	var doc := HudScript.PixButton.new()
	doc.text = "DOC'S LAB"
	doc.sub = "PATCH UP  SURGERY" if Run.hq("doc") >= 1 else "PATCH UP"
	doc.color = Color("9df25c")
	doc.small = true
	doc.size = Vector2(170, 44)
	doc.position = Vector2(750, 486)
	doc.pressed.connect(func(): walk_to("doc"))
	add_child(doc)
	if Run.campaign() and Run.hq("lab") >= 1:
		var lab := HudScript.PixButton.new()
		lab.text = "ALIEN LAB"
		lab.sub = "VHARR TECH"
		lab.color = Color("c47bff")
		lab.small = true
		lab.size = Vector2(170, 36)
		lab.position = Vector2(405, 438)
		lab.pressed.connect(func(): go("lab"))
		add_child(lab)

func lab_row(i: int) -> Rect2:
	return Rect2(32, 110 + i * 82, 896, 74)

func open_lab() -> void:
	## B5: the Alien Lab turns kills into Vharr tech, paid in Bio-parts and Salvage.
	Sfx.play("click")
	lab_open = true
	for c in get_children():
		c.queue_free()
	sub = null
	for i in Data.VHARR_TECH.size():
		var id: String = Data.VHARR_TECH[i].id
		var why := Run.tech_block(id)
		var r := lab_row(i)
		var bt := HudScript.PixButton.new()
		bt.small = true
		bt.size = Vector2(170, 30)
		bt.position = Vector2(r.end.x - 182, r.position.y + 22)
		bt.text = "BUILD" if why == "" else why
		bt.color = Color("c47bff")
		bt.disabled = why != ""
		bt.pressed.connect(func():
			var it := Run.build_tech(id)
			if it.is_empty():
				Sfx.play("deny")
			else:
				Sfx.play("power")
				open_lab())
		add_child(bt)
	var close := HudScript.PixButton.new()
	close.text = "BACK TO HQ"
	close.color = Color("9aa2ae")
	close.size = Vector2(150, 30)
	close.position = Vector2(405, 494)
	close.pressed.connect(func(): lab_open = false; build())
	add_child(close)

func draw_lab_panel() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color(0.04, 0.02, 0.06, 0.97))
	Art.text(self, "ALIEN LAB", Vector2(40, 58), 16, Color("c47bff"), HORIZONTAL_ALIGNMENT_LEFT, 2)
	Art.text(self, "Kill %d of an alien and the Lab can copy its tech. Built gear goes to the stash, and runs can find it from then on." % Run.tech_need(), Vector2(40, 80), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
	Art.text(self, "%d BIO-PARTS   %d SALVAGE" % [int(Run.meta.get("bio", 0)), int(Run.meta.get("salvage", 0))], Vector2(920, 58), 16, Color("9df25c"), HORIZONTAL_ALIGNMENT_RIGHT, 2)
	for i in Data.VHARR_TECH.size():
		var T: Dictionary = Data.VHARR_TECH[i]
		var I: Dictionary = Data.ITEMS[T.id]
		var r := lab_row(i)
		var n: int = Run.tech_kills(T.alien)
		var need: int = Run.tech_need()
		draw_rect(r, Color(0.08, 0.05, 0.1, 0.9))
		draw_rect(r, Color("c47bff") if n >= need else Color("4a3f55"), false, 1)
		var sheet: String = "en_" + T.alien
		if Art.meta.has(sheet):
			Art.draw_char(self, sheet, "idle", (t / 14) % 2, Vector2(r.position.x + 40, r.end.y - 6), 1, false, 0, 1.0, 0, false, minf(1.0, 62.0 / float(Art.meta[sheet].frame[1])))
		Art.text(self, I.name.to_upper(), Vector2(r.position.x + 84, r.position.y + 22), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
		Art.text(self, I.text, Vector2(r.position.x + 84, r.position.y + 42), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		var bx := r.position.x + 84
		var bw := 300.0
		draw_rect(Rect2(bx, r.position.y + 54, bw, 8), Color(0.05, 0.035, 0.03))
		draw_rect(Rect2(bx + 1, r.position.y + 55, (bw - 2) * minf(1.0, float(n) / need), 6), Color("c47bff"))
		Art.text(self, "%s KILLS %d / %d   COST %d BIO + %d SALVAGE" % [Data.ETYPES[T.alien].name.to_upper(), mini(n, need), need, Data.TECH_BIO, Data.TECH_SALVAGE], Vector2(bx + bw + 12, r.position.y + 63), 8, Color("9aa2ae"))

func doc_cell(i: int) -> Rect2:
	## Surgery i on the lab board: two columns of cards.
	return Rect2(32 + (i % 2) * 452, 96 + (i / 2) * 56, 444, 50)

func doc_targets() -> Array:
	## Who the Doc operates on: the four classes in a run, the deployed squad in the campaign (B3).
	if Run.campaign():
		return Run.soldiers.filter(func(s): return s.alive)
	return Data.SQUAD_DEFS.map(func(d): return d.key)

func open_doc() -> void:
	## The Doc's Lab: surgeries installed on a class, paid in Bio-parts and Salvage.
	Sfx.play("click")
	doc_open = true
	for c in get_children():
		c.queue_free()
	sub = null
	var ids: Array = Data.SURGERIES.keys()
	for i in ids.size():
		var id: String = ids[i]
		var cr := doc_cell(i)
		var who := doc_targets()
		for j in who.size():
			var cls = who[j]
			var why := Run.surgery_block(id, cls)
			var bt := HudScript.PixButton.new()
			bt.small = true
			bt.size = Vector2(58, 20)
			bt.position = Vector2(cr.end.x - 124 + (j % 2) * 62, cr.position.y + 4 + (j / 2) * 22)
			bt.text = (cls.def.name if cls is Dictionary else Data.SQUAD_DEFS[j].name) + (" OK" if why == "INSTALLED" else "")
			bt.color = Color("9df25c")
			bt.disabled = why != ""
			bt.pressed.connect(func():
				if Run.operate(id, cls):
					Sfx.play("power")
					open_doc()
				else:
					Sfx.play("deny"))
			add_child(bt)
	if Run.hq("doc") < 1:
		add_child(DocLock.new())
	var hurt: Array = Run.soldiers.filter(func(s): return s.alive and s.hp < Run.eff_max_hp(s))
	var pp := Services.price(Services.PATCH)
	var patch := HubUI.ActionTile.new()
	patch.title = "PATCH UP"
	patch.cost = pp
	patch.color = Color("62d26f")
	patch.line = "Heal every soldier to full. Hurt: %s." % ", ".join(hurt.map(func(s): return "%s %d/%d" % [s.def.name, s.hp, Run.eff_max_hp(s)]))
	patch.why = "Everyone is at full health." if hurt.is_empty() else Services.short(pp)
	patch.ok = hurt.size() > 0 and Run.scrip >= pp
	patch.size = Vector2(360, 44)
	patch.position = Vector2(32, 492)
	patch.pressed.connect(func():
		if Services.patch_up():
			Sfx.play("power")
		open_doc())
	add_child(patch)
	var close := HudScript.PixButton.new()
	close.text = "BACK TO HQ"
	close.color = Color("9aa2ae")
	close.size = Vector2(150, 30)
	close.position = Vector2(405, 500)
	close.pressed.connect(func(): doc_open = false; build())
	add_child(close)
	add_nav("doc")

func open_upgrades() -> void:
	## The HQ upgrade board: each building's next rank, bought with Salvage.
	Sfx.play("click")
	upgrades_open = true
	for c in get_children():
		c.queue_free()
	sub = null
	var blds := Run.hq_buildings()
	for i in blds.size():
		var B: Dictionary = blds[i]
		var r := Run.hq(B.id)
		var bt := HudScript.PixButton.new()
		bt.small = true
		bt.size = Vector2(170, 30)
		bt.position = Vector2(750, 108 + i * upgrade_step())
		if r >= Data.HQ_COST.size():
			bt.text = "FULLY BUILT"
			bt.disabled = true
		else:
			bt.text = "BUILD  %d SALVAGE" % Data.HQ_COST[r]
			bt.color = Color("53d4e2")
			bt.disabled = int(Run.meta.get("salvage", 0)) < Data.HQ_COST[r]
		var id: String = B.id
		bt.pressed.connect(func():
			if Run.hq_upgrade(id):
				Sfx.play("power")
				open_upgrades()
			else:
				Sfx.play("deny"))
		add_child(bt)
	var close := HudScript.PixButton.new()
	close.text = "BACK TO HQ"
	close.color = Color("9aa2ae")
	close.size = Vector2(150, 30)
	close.position = Vector2(405, 494)
	close.pressed.connect(func(): upgrades_open = false; build())
	add_child(close)
	add_nav("upgrades")

func open_dossier(i: int, tb := "deck") -> void:
	## S1: a soldier's sheet, gear and deck, from the squad bar, a click on them, or 1-4.
	Sfx.play("click")
	var d: Control = DossierScript.new()
	d.idx = i
	d.tab = tb
	d.done.connect(func(): build())
	add_child(d)
	sub = d

func idle() -> bool:
	## True when the HQ scene itself is showing (no building screen or board open).
	return (sub == null or not is_instance_valid(sub)) and not memorial_open and not upgrades_open and not doc_open and not lab_open

func troop_x(i: int) -> float:
	var n: int = Run.soldiers.filter(func(s): return s.alive).size()
	return 480 + (i - (n - 1) / 2.0) * 46

func troop_at(p: Vector2) -> int:
	## Index into Run.soldiers of the soldier standing at p, or -1.
	var al: Array = Run.soldiers.filter(func(s): return s.alive)
	for i in al.size():
		if absf(p.x - troop_x(i)) < 20 and p.y > GROUND - 64 and p.y < GROUND + 20:
			return Run.soldiers.find(al[i])
	return -1

func _gui_input(ev: InputEvent) -> void:
	if not idle() or not walk.is_empty():
		return
	if ev is InputEventMouseMotion:
		hover_troop = troop_at(ev.position)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hover_troop >= 0 else Control.CURSOR_ARROW
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var k := troop_at(ev.position)
		if k >= 0:
			accept_event()
			hover_troop = -1
			open_dossier(k)

const KEYS := {KEY_H: "hq", KEY_Q: "qm", KEY_W: "workshop", KEY_A: "armory", KEY_D: "doc", KEY_B: "barracks", KEY_M: "memorial", KEY_U: "upgrades"}

func _unhandled_input(ev: InputEvent) -> void:
	## H4: a key per building skips the walk; 1-4 open a soldier from the HQ scene; ESC goes home.
	if not (ev is InputEventKey and ev.pressed and not ev.echo) or sub_busy():
		return
	var at_hq := idle()
	if at_hq and ev.keycode >= KEY_1 and ev.keycode <= KEY_4 and ev.keycode - KEY_1 < Run.soldiers.size():
		get_viewport().set_input_as_handled()
		open_dossier(ev.keycode - KEY_1)
	elif KEYS.has(ev.keycode) and not (at_hq and KEYS[ev.keycode] == "hq"):
		get_viewport().set_input_as_handled()
		go(KEYS[ev.keycode])
	elif at_hq and ev.keycode == KEY_G:
		get_viewport().set_input_as_handled()
		Sfx.play("start")
		dial.emit()
	elif not at_hq and ev.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		go("hq")

func sub_busy() -> bool:
	## A Dossier, picker or preview is open: keys belong to it, and the nav strip steps aside.
	if sub == null or not is_instance_valid(sub):
		return false
	if sub.get_script() == DossierScript or sub.get("chooser") != null or str(sub.get("picking") if sub.get("picking") != null else "") != "":
		return true
	for c in sub.get_children():
		if c.get_script() == DossierScript or c.get_script() == ArmoryScript:
			return true
	return false

func go(id: String) -> void:
	## B2: jump straight from any building to another (or home), no walk.
	walk = {}
	memorial_open = false
	upgrades_open = false
	doc_open = false
	lab_open = false
	build()
	match id:
		"qm": open_shop("shop")
		"barracks": open_shop("barracks")
		"workshop": open_workshop()
		"armory": open_armory()
		"doc": open_doc()
		"memorial": open_memorial()
		"upgrades": open_upgrades()
		"lab": open_lab()

func walk_to(id: String) -> void:
	## H4: the squad trots over to the building, then it opens.
	if not walk.is_empty():
		return
	Sfx.play("click")
	var xs := {"qm": 120.0, "workshop": 170.0, "barracks": 305.0, "armory": 672.0, "memorial": 850.0, "doc": 850.0, "upgrades": 480.0}
	walk = {"id": id, "x": xs.get(id, 480.0), "t": 0}
	hover_troop = -1

func add_nav(cur: String) -> void:
	var old := get_node_or_null("Nav")
	if old != null:
		old.name = "NavGone"
		old.queue_free()
	var nav := HubUI.NavStrip.new()
	nav.current = cur
	nav.badges = badges()
	nav.go.connect(go)
	nav.name = "Nav"
	add_child(nav)

func badges() -> Dictionary:
	## H2: what's waiting at each building, only counting things the squad can do right now.
	var out := {}
	var al: Array = Run.soldiers.filter(func(s): return s.alive)
	if Run.qm_cache.get("mission", -1) != Run.mission or not Run.qm_cache.get("seen", false):
		out["qm"] = "NEW STOCK"
	var ready: int = al.reduce(func(a, s): return a + Run.fusable(s).size() + Run.evolutions(s).size(), 0)
	if ready > 0:
		out["workshop"] = "%d READY" % ready
	if Run.any_merge():
		out["armory"] = "TRIPLE READY"
	if al.any(func(s): return s.hp < Run.eff_max_hp(s)) and Run.scrip >= Services.price(Services.PATCH):
		out["doc"] = "HURT"
	elif Run.hq("doc") >= 1 and Data.SURGERIES.keys().any(func(id): return doc_targets().any(func(w): return Run.surgery_block(id, w) == "")):
		out["doc"] = "CAN OPERATE"
	if al.any(func(s): return s.get("train", false)):
		out["barracks"] = "TRAINING"
	elif not Run.campaign() and not Run.fallen_slots().is_empty() and Run.scrip >= Services.price(Data.RECRUIT_PRICE / (2 if Run.hq("barracks") >= 3 else 1)):
		out["barracks"] = "RECRUIT"
	elif al.any(func(s): return s.tags < Data.DOG_TAGS) and Run.scrip >= Services.price(Data.TAG_PRICE):
		out["barracks"] = "DOG TAG"
	return out

func reminders() -> Array:
	## H3: what the gate button mentions before you leave. Only a reminder: one click still dials.
	var out: Array = []
	if Run.scrip >= Services.price(Services.PATCH):
		out.append("%d scrip unspent." % Run.scrip)
	for s in Run.soldiers:
		if s.alive and s.hp < Run.eff_max_hp(s):
			out.append("%s is at %d/%d HP." % [s.def.name, s.hp, Run.eff_max_hp(s)])
	var b := badges()
	if b.has("workshop"):
		out.append("%s at the Workshop." % b.workshop.capitalize())
	if b.has("armory"):
		out.append("A triple is ready to merge at the Armory.")
	return out

func next_mission_n() -> int:
	return Run.history.size() + 1

func open_shop(mode: String) -> void:
	Sfx.play("click")
	var s: Control = ShopScript.new()
	s.mode = mode
	s.done.connect(func(): build())
	add_child(s)
	sub = s
	add_nav("qm" if mode == "shop" else "barracks")

func open_workshop() -> void:
	Sfx.play("click")
	var w: Control = WorkshopScript.new()
	w.done.connect(func(): build())
	add_child(w)
	sub = w
	add_nav("workshop")

func open_armory() -> void:
	Sfx.play("click")
	var a: Control = ArmoryScript.new()
	a.shop_mode = true
	a.done.connect(func(): build())
	add_child(a)
	sub = a
	add_nav("armory")

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
	add_nav("memorial")

func bg(n: String) -> Texture2D:
	if not held.has(n):
		held[n] = load("res://assets/bg/%s.png" % n)
	return held[n]

func _process(_d: float) -> void:
	t += 1
	if not walk.is_empty():
		walk.t += 1
		if walk.t >= 34:
			go(walk.id)
	var nav := get_node_or_null("Nav")
	if nav != null:
		nav.visible = not sub_busy()
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
	if Run.hq("mess") >= 1:
		draw_mess_hall()
	if Run.hq("motor") >= 1:
		draw_motor_pool()
	if Run.hq("doc") >= 1:
		draw_doc_lab()
	draw_workshop()
	draw_quartermaster()
	draw_barracks()
	draw_armory()
	draw_memorial()
	draw_rank_pips(230, "barracks")
	draw_rank_pips(600, "armory")
	if not memorial_open and not upgrades_open and not doc_open:
		for k in Run.hq("gate"):
			# Gate Control: a lit beacon on the ring for every rank
			var a := -PI / 2 + (k - 1) * 0.5
			draw_circle(GATE + Vector2(cos(a), sin(a)) * (GATE_R + 8), 4, Color("53d4e2"))
	Art.draw_gate(self, GATE, GATE_R, t, 9 if gate_open() > 0 else 0, gate_open(), 1.0, t * 0.004)
	# the squad, stepping out of the gate when they just came home
	var al: Array = Run.soldiers.filter(func(s): return s.alive)
	for i in al.size():
		var s: Dictionary = al[i]
		var x := troop_x(i)
		var a := 1.0
		if arrived and t < 70:
			a = clampf((t - 10 - i * 10) / 20.0, 0, 1)
		var face := 1 if x < 480 else -1
		var anim := "idle"
		var frame := (t / 12 + i) % 4
		if not walk.is_empty():
			var tx: float = walk.x + (i - (al.size() - 1) / 2.0) * 18
			var k := clampf((walk.t - i * 2) / 26.0, 0, 1)
			face = 1 if tx > x else -1
			if k < 1.0:
				anim = "run"
				frame = (walk.t / 3 + i) % 8
			x = lerpf(x, tx, k)
		Art.draw_char(self, Art.look_sheet(s), anim, frame, Vector2(x, GROUND), face, false, 0, a, 0, true, 1.4)
		if a >= 1.0:
			var on := Run.soldiers.find(s) == hover_troop
			Art.text(self, s.def.name, Vector2(x, GROUND + 16), 8, Color("ffd23a") if on else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	if idle() and walk.is_empty():
		draw_badges()
		if dial_btn != null and is_instance_valid(dial_btn) and dial_btn.hover:
			draw_reminders()
	if hover_troop >= 0 and idle():
		draw_troop_card(Run.soldiers[hover_troop], troop_x(al.find(Run.soldiers[hover_troop])))
	# header
	draw_rect(Rect2(0, 0, 960, 70), Color(0.05, 0.035, 0.03, 0.75))
	Art.text(self, "FIELD HQ  ACT %s" % Run.act().roman if Run.campaign() else "IRON ADVANCE HQ", Vector2(24, 34), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
	var line := "Kit out the squad, then dial the gate for level 1."
	if Run.campaign():
		line = "Act %s: %s. Kit out the squad, then pick the next op in the War Room." % [Run.act().roman, Run.act().name.capitalize()]
	elif Run.history.size():
		line = "Back through the gate. Resupply, then dial the gate for " + ("the finale." if next_mission_n() > Data.LEVELS.size() else "level %d." % next_mission_n())
	Art.text(self, line, Vector2(24, 56), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
	var cur := "%d SALVAGE   %d BIO-PARTS" % [int(Run.meta.get("salvage", 0)), int(Run.meta.get("bio", 0))]
	Art.text(self, cur, Vector2(936, 56), 8, Color("53d4e2"), HORIZONTAL_ALIGNMENT_RIGHT)
	var sc := "%d SCRIP" % Run.scrip
	draw_texture_rect(Art.tex.ic_coin, Rect2(936 - Art.text_width(sc, 16) - 22, 20, 16, 16), false)
	Art.text(self, sc, Vector2(936, 36), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT, 2)
	if news.size() and idle() and t < 420:
		draw_news()
	if memorial_open:
		draw_memorial_panel()
	elif upgrades_open:
		draw_upgrades_panel()
	elif doc_open:
		draw_doc_panel()
	elif lab_open:
		draw_lab_panel()

func draw_news() -> void:
	## Campaign: the after-op report, fading out after a few seconds.
	var a := clampf((420 - t) / 60.0, 0, 1)
	var w := 460.0
	for line in news:
		w = maxf(w, Art.text_width(line, 16, true) + 24)
	var r := Rect2(480 - w / 2, 132, w, 20 + news.size() * 16)
	draw_rect(r, Color(0.05, 0.035, 0.03, 0.9 * a))
	draw_rect(r, Color(0.38, 0.82, 0.44, a), false, 2)
	for i in news.size():
		Art.text(self, news[i], r.position + Vector2(12, 22 + i * 16), 16, Color(0.91, 0.86, 0.76, a), HORIZONTAL_ALIGNMENT_LEFT, 2, true, a)

func draw_badges() -> void:
	## H2: a bobbing tag over each building with something ready.
	var at := {"qm": Vector2(120, 336), "workshop": Vector2(176, 296), "barracks": Vector2(305, 334), "armory": Vector2(674, 356)}
	at["doc"] = Vector2(854, 314) if Run.hq("doc") >= 1 else Vector2(835, 474)
	var b := badges()
	for id in b:
		if not at.has(id):
			continue
		var txt: String = b[id]
		var w := Art.text_width(txt, 8) + 10
		var p: Vector2 = at[id] + Vector2(-w / 2, -(2 if (t / 20) % 2 == 0 else 0))
		draw_rect(Rect2(p, Vector2(w, 14)), Color(0.05, 0.035, 0.03))
		draw_rect(Rect2(p + Vector2(1, 1), Vector2(w - 2, 12)), Color("ff4d3d") if txt == "HURT" else Color("ffd23a"))
		Art.text(self, txt, p + Vector2(w / 2, 11), 8, Color(0.05, 0.035, 0.03), HORIZONTAL_ALIGNMENT_CENTER, 0)

func draw_reminders() -> void:
	## H3: hovering DIAL THE GATE lists what's still worth doing. It never blocks the dial.
	var lines := reminders()
	if lines.is_empty():
		lines = ["All set. Good hunting."]
	var w := 300.0
	var r := Rect2(330, 300 - lines.size() * 14, w, 22 + lines.size() * 14)
	draw_rect(r, Color(0.05, 0.035, 0.03, 0.95))
	draw_rect(r, Color("ff4d3d"), false, 2.0)
	Art.text(self, "BEFORE YOU GO", r.position + Vector2(10, 14), 8, Color("ffd23a"))
	for i in lines.size():
		Art.text(self, lines[i], r.position + Vector2(10, 30 + i * 14), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)

func draw_workshop() -> void:
	## The Workshop: a tall shed behind the QM tent, chimney and sparks from the grinder.
	var d := Color(0.05, 0.035, 0.03)
	draw_rect(Rect2(128, 318, 80, GROUND - 318), d)
	draw_rect(Rect2(130, 320, 76, GROUND - 320), Color("5a4e6a"))
	draw_colored_polygon(PackedVector2Array([Vector2(122, 322), Vector2(168, 300), Vector2(214, 322)]), Color("3a2c44"))
	draw_rect(Rect2(190, 288, 8, 24), d)
	draw_rect(Rect2(146, 326, 20, 12), Color("ffb23e") if (t / 6) % 7 != 0 else Color("6a4e2a"))
	for i in 3:
		var k := float((t * 3 + i * 37) % 60) / 60.0
		draw_rect(Rect2(156 + k * 14 * (1 if i % 2 == 0 else -1), 332 - k * 10 + k * k * 18, 2, 2), Color(1, 0.8, 0.3, 1.0 - k))

func draw_troop_card(s: Dictionary, x: float) -> void:
	## H1: hovering a soldier in the scene shows who they are and what's waiting for them.
	var r := Rect2(clampf(x - 110, 8, 732), GROUND - 150, 220, 70)
	draw_rect(r, Color(0.05, 0.035, 0.03, 0.95))
	draw_rect(r, Color("ffd23a"), false, 2.0)
	Art.text(self, "%s  %s" % [s.def.name, s.def.cls.to_upper()], r.position + Vector2(8, 16), 8, Color.WHITE)
	Art.text(self, "HP %d/%d   DECK %d   LV%d" % [s.hp, Run.eff_max_hp(s), s.deck.size(), s.lvl], r.position + Vector2(8, 32), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
	var al := Services.alert(s)
	var tip: String = {"FUSE": "3 copies ready to fuse", "EVOLVE": "a card can evolve", "HURT": "hurt: patch up at the Doc's Lab"}.get(al, "")
	if tip != "":
		Art.text(self, tip, r.position + Vector2(8, 46), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
	Art.text(self, "Click or press %d for the Dossier" % (Run.soldiers.find(s) + 1), r.position + Vector2(8, 62), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)

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

func draw_upgrades_panel() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color(0.02, 0.02, 0.04, 0.97))
	Art.text(self, "UPGRADE HQ", Vector2(40, 60), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
	Art.text(self, "%d SALVAGE" % int(Run.meta.get("salvage", 0)), Vector2(920, 58), 16, Color("53d4e2"), HORIZONTAL_ALIGNMENT_RIGHT, 2)
	Art.text(self, "Salvage comes from beaten Boars, Salvage yards and held sectors. This base belongs to this campaign." if Run.campaign() else "Salvage comes from beaten Boars and Salvage yards, and is kept when a run ends.", Vector2(40, 86), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
	var blds := Run.hq_buildings()
	for i in blds.size():
		var B: Dictionary = blds[i]
		var r := Run.hq(B.id)
		var y := 100.0 + i * upgrade_step()
		draw_rect(Rect2(32, y, 896, upgrade_step() - 4), Color(0.08, 0.07, 0.06, 0.9))
		draw_rect(Rect2(32, y, 896, upgrade_step() - 4), Color("53d4e2") if r > 0 else Color("4a505a"), false, 1)
		Art.text(self, B.name, Vector2(44, y + 18), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
		for k in 3:
			draw_rect(Rect2(44 + k * 16, y + 28, 12, 12), Color(0.05, 0.035, 0.03))
			draw_rect(Rect2(45 + k * 16, y + 29, 10, 10), Color("ffd23a") if k < r else Color("3a3f45"))
		for k in 3:
			var col := Color("62d26f") if k < r else (Color("e8dcc2") if k == r else Color("6c7480"))
			var mark := "OK " if k < r else ("NEXT " if k == r else "")
			Art.text(self, "%d  %s%s" % [k + 1, mark, B.ranks[k]], Vector2(262, y + 13 + k * 14), 8, col)
	if blds.size() <= 6:
		Art.text(self, "MEMORIAL is free: the fallen hang their tags there.", Vector2(480, 452), 8, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER)

func upgrade_step() -> float:
	## Rows close up once the campaign's story buildings join the board.
	return 56.0 if Run.hq_buildings().size() <= 6 else 49.0

func draw_doc_panel() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color(0.02, 0.03, 0.02, 0.97))
	Art.text(self, "THE DOC'S LAB", Vector2(40, 58), 16, Color("9df25c"), HORIZONTAL_ALIGNMENT_LEFT, 2)
	Art.text(self, "\"Hold still. Or don't, it's more fun.\"", Vector2(40, 76), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
	Art.text(self, "%d BIO-PARTS   %d SALVAGE" % [int(Run.meta.get("bio", 0)), int(Run.meta.get("salvage", 0))], Vector2(920, 58), 16, Color("9df25c"), HORIZONTAL_ALIGNMENT_RIGHT, 2)
	var r := Run.hq("doc")
	var line := "%d BIO + %d SALVAGE EACH. %d SLOT%s PER %s, OLDEST COMES OUT WHEN FULL." % [Data.SURGERY_BIO, Data.SURGERY_SALVAGE, r, "" if r == 1 else "S", "SOLDIER" if Run.campaign() else "CLASS"] if r >= 1 else "BUILD THE DOC'S LAB ON THE UPGRADE BOARD FIRST."
	Art.text(self, line, Vector2(920, 76), 8, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_RIGHT)
	var ids: Array = Data.SURGERIES.keys()
	for i in ids.size():
		var S: Dictionary = Data.SURGERIES[ids[i]]
		var cr := doc_cell(i)
		var on: Array = doc_targets().filter(func(w): return (Run.implants_of(w) if w is Dictionary else Run.implants(w)).has(ids[i]))
		draw_rect(cr, Color(0.06, 0.08, 0.06, 0.9))
		draw_rect(cr, Color("9df25c") if on.size() else Color("4a5a4a"), false, 1)
		Art.text(self, S.name, Vector2(cr.position.x + 10, cr.position.y + 20), 16, Color("ffd23a") if r >= 1 else Color("8a8a6a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
		Art.text(self, "+ " + S.up, Vector2(cr.position.x + 10, cr.position.y + 38), 8, Color("62d26f") if r >= 1 else Color("6a7a6a"))

func draw_doc_lab() -> void:
	## Doc's Lab: a back-row hut behind the Memorial with a green-lit window and a lightning rod.
	var d := Color(0.05, 0.035, 0.03)
	draw_rect(Rect2(806, 326, 96, 60), d)
	draw_rect(Rect2(808, 328, 92, 58), Color("4a5248"))
	var glow := 0.7 + 0.3 * sin(t / 9.0)
	draw_rect(Rect2(820, 340, 26, 16), Color(0.55 * glow, 1.0 * glow, 0.36 * glow))
	draw_rect(Rect2(872, 300, 2, 28), d)
	if t % 140 < 6:
		draw_line(Vector2(873, 298), Vector2(866, 286), Color("e8f8ff"), 2.0)

func draw_rank_pips(x: float, id: String) -> void:
	## Three little lamps over a building's button: one lit per rank bought.
	var r := Run.hq(id)
	for k in 3:
		draw_rect(Rect2(x + 51 + k * 16, 428, 10, 6), Color(0.05, 0.035, 0.03))
		draw_rect(Rect2(x + 52 + k * 16, 429, 8, 4), Color("ffd23a") if k < r else Color("3a3f45"))

func draw_mess_hall() -> void:
	## Mess Hall: a back-row hut peeking over the Barracks roof, smoke from the stove pipe.
	var r := Run.hq("mess")
	var d := Color(0.05, 0.035, 0.03)
	draw_rect(Rect2(250, 318, 110, 60), d)
	draw_rect(Rect2(252, 320, 106, 58), Color("5a4a36"))
	draw_rect(Rect2(330, 296, 8, 24), d)
	for i in 4:
		var k := float((t + i * 30) % 120) / 120.0
		draw_circle(Vector2(334 + sin(t / 20.0 + i) * 4 + k * 10, 292 - k * 50), 4 + k * 6, Color(0.6, 0.6, 0.62, 0.35 * (1 - k)))
	for i in r:
		draw_rect(Rect2(262 + i * 22, 330, 12, 8), Color("ffd96a"))

func draw_motor_pool() -> void:
	## Motor Pool: a back-row garage behind the Armory with the Slug's barrel poking out.
	var r := Run.hq("motor")
	var d := Color(0.05, 0.035, 0.03)
	draw_rect(Rect2(620, 322, 130, 52), d)
	draw_rect(Rect2(622, 324, 126, 50), Color("6a6e72"))
	draw_rect(Rect2(640, 334, 70, 40), Color("2a2c30"))
	for i in 5:
		draw_rect(Rect2(640, 338 + i * 7, 70, 2), Color("3a3d42"))
	draw_rect(Rect2(700, 342, 40, 5), Color("4c5c3a"))
	for i in r:
		draw_rect(Rect2(728 - i * 10, 328, 6, 4), Color("ff7a3d"))

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

class DocLock extends Control:
	## H5: before the lab is built, a lock banner sits over the surgery list so it doesn't read as open.
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		position = Vector2(230, 236)
		size = Vector2(500, 64)
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.035, 0.03, 0.95))
		draw_rect(Rect2(Vector2.ZERO, size), Color("ffd23a"), false, 2)
		Art.text(self, "LOCKED", Vector2(size.x / 2, 26), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 2)
		Art.text(self, "Build the Doc's Lab on the UPGRADE HQ board (salvage) to install these.", Vector2(size.x / 2, 48), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)

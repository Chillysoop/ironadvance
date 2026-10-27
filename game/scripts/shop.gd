extends Control
## The quartermaster between missions: buy cards and squad gear, upgrade or
## remove cards, heal and revive. Prices are paid in scrip earned in the field.

signal done
signal chosen(i: int)

const HudScript := preload("res://scripts/hud.gd")

var stock_cards: Array = []
var stock_gear: Array = []
var t := 0
var msg := ""
var msg_t := 0
var chooser: Control = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	restock()
	build()

func restock() -> void:
	var keys: Array = []
	for k in Data.CARDS:
		if Data.CARDS[k].rarity < 3:
			keys.append(k)
	keys.shuffle()
	stock_cards.clear()
	for i in 5:
		var up := randf() < 0.2 + Run.mission * 0.1
		stock_cards.append({"kind": "card", "key": keys[i], "up": up, "price": Data.card_price(keys[i], up)})
	var gear: Array = Data.GEAR.filter(func(g): return not Run.has_gear(g.id))
	gear.shuffle()
	stock_gear = gear.slice(0, 3).map(func(g): return {"kind": "gear", "id": g.id, "icon": g.icon, "name": g.name, "text": g.text, "price": g.price})

func say(s: String) -> void:
	msg = s
	msg_t = 200

func build() -> void:
	for c in get_children():
		c.queue_free()
	var cw := 104.0
	for i in stock_cards.size():
		var o: Dictionary = stock_cards[i]
		var cv := CardView.new()
		cv.opt = o
		cv.size = Vector2(cw, 146)
		cv.position = Vector2(24 + i * (cw + 8), 92)
		cv.price = o.price
		cv.disabled = o.get("sold", false) or Run.scrip < o.price
		if o.get("sold", false):
			cv.label_top = "SOLD"
		var idx := i
		cv.pressed.connect(func(): buy_card(idx))
		add_child(cv)
	for i in stock_gear.size():
		var o: Dictionary = stock_gear[i]
		var cv := CardView.new()
		cv.opt = o
		cv.size = Vector2(cw, 146)
		cv.position = Vector2(600 + i * (cw + 8), 92)
		cv.price = o.price
		cv.disabled = o.get("sold", false) or Run.scrip < o.price
		if o.get("sold", false):
			cv.label_top = "SOLD"
		var idx := i
		cv.pressed.connect(func(): buy_gear(idx))
		add_child(cv)
	var services := [
		["FIELD HOSPITAL", "Heal the whole squad to full.", 40, heal_all],
		["UPGRADE CARD", "Turn one card into its + version.", 60, upgrade_card],
		["REMOVE CARD", "Thin a deck: burn one card.", 50, remove_card],
		["REVIVE", "Bring a fallen soldier back at half HP.", 120, revive],
		["RESTOCK", "New cards and gear on the shelf.", 20, reroll],
	]
	for i in services.size():
		var sv: Array = services[i]
		var bt := HudScript.PixButton.new()
		bt.text = "%s  %d$" % [sv[0], sv[2]]
		bt.color = Color("53d4e2") if i < 3 else (Color("62d26f") if i == 3 else Color("9aa2ae"))
		bt.size = Vector2(176, 26)
		bt.position = Vector2(24 + i * 184, 270)
		bt.disabled = Run.scrip < sv[2]
		bt.pressed.connect(sv[3])
		add_child(bt)
	var go := HudScript.PixButton.new()
	go.text = "DEPLOY >>"
	go.sub = "MISSION %d" % (Run.mission + 2)
	go.color = Color("ff4d3d")
	go.size = Vector2(190, 44)
	go.position = Vector2(746, 482)
	go.pressed.connect(func(): Sfx.play("start"); done.emit())
	add_child(go)

func _process(_d: float) -> void:
	t += 1
	if msg_t > 0:
		msg_t -= 1
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color("1a1d22"))
	for y in range(0, 540, 24):
		for x in range(0, 960, 24):
			draw_texture_rect(Art.tex.ui_panel, Rect2(x, y, 24, 24), false, Color(0.55, 0.55, 0.6))
	var hz: Texture2D = Art.tex.ui_hazard
	for x in range(0, 960, 32):
		draw_texture_rect(hz, Rect2(x, 0, 32, 8), false)
		draw_texture_rect(hz, Rect2(x, 252, 32, 6), false)
	Art.text(self, "QUARTERMASTER", Vector2(24, 40), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
	Art.text(self, "Spend scrip before the next drop. Cards go to the soldier you pick.", Vector2(24, 60), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
	var sc := "%d SCRIP" % Run.scrip
	draw_texture_rect(Art.tex.ic_coin, Rect2(936 - Art.text_width(sc, 16) - 22, 26, 16, 16), false)
	Art.text(self, sc, Vector2(936, 42), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT, 2)
	Art.text(self, "FIELD CARDS", Vector2(24, 84), 8, Color("53d4e2"))
	Art.text(self, "SQUAD GEAR", Vector2(600, 84), 8, Color("62d26f"))
	# squad roster
	Art.text(self, "THE SQUAD", Vector2(24, 316), 8, Color("ffb23e"))
	for i in Run.soldiers.size():
		var s: Dictionary = Run.soldiers[i]
		var x := 24.0 + i * 180
		var y := 326.0
		draw_rect(Rect2(x, y, 172, 148), Color(0.05, 0.035, 0.03))
		draw_rect(Rect2(x + 1, y + 1, 170, 146), Color("2a2e34"))
		draw_rect(Rect2(x + 1, y + 1, 170, 2), Color("6c7480"))
		var anim := "idle" if s.alive else "die"
		Art.draw_char(self, "sq_" + s.key, anim, (t / 12 + i) % 4 if s.alive else 4, Vector2(x + 30, y + 80), 1, false, 0, 1.0, 0, false, 1.1)
		Art.text(self, s.def.name, Vector2(x + 62, y + 20), 8, Color.WHITE)
		Art.text(self, "LV%d" % s.lvl, Vector2(x + 164, y + 20), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT)
		Art.text(self, s.def.cls, Vector2(x + 62, y + 36), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		if s.alive:
			draw_rect(Rect2(x + 62, y + 44, 100, 6), Color(0.05, 0.035, 0.03))
			draw_rect(Rect2(x + 63, y + 45, 98.0 * s.hp / s.max_hp, 4), Color("62d26f") if s.hp > s.max_hp * 0.3 else Color("ff4d3d"))
			Art.text(self, "HP %d/%d" % [s.hp, s.max_hp], Vector2(x + 62, y + 64), 8, Color("e8dcc2"))
		else:
			Art.text(self, "KIA", Vector2(x + 62, y + 60), 16, Color("ff4d3d"), HORIZONTAL_ALIGNMENT_LEFT, 2)
		Art.text(self, "DECK %d  XP %d" % [s.deck.size(), s.xp], Vector2(x + 8, y + 94), 8, Color("e8dcc2"))
		var perks: Array = s.perks.map(func(p): return Data.perk(s.key, p).name)
		var yy := y + 112
		for line in CardView.wrap_text(", ".join(perks) if perks.size() else "No abilities yet", 156, 16):
			Art.text(self, line, Vector2(x + 8, yy), 16, Color("ffd23a") if perks.size() else Color("6c7480"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
			yy += 13
	# owned gear
	var gx := 24.0
	Art.text(self, "GEAR:", Vector2(gx, 500), 8, Color("62d26f"))
	var names: Array = Run.gear.map(func(g): return Data.gear(g).name)
	Art.text(self, ", ".join(names) if names.size() else "none", Vector2(gx + 50, 501), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
	if msg_t > 0:
		var w := Art.text_width(msg, 16, true) + 20
		draw_rect(Rect2(480 - w / 2, 296, w, 20), Color(0.05, 0.035, 0.03, 0.9))
		Art.text(self, msg, Vector2(480, 311), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 0, true)

# ---------------------------------------------------------------- choosers
func choose(title: String, opts: Array, card_size := Vector2(104, 146)) -> int:
	chooser = Chooser.new()
	chooser.title = title
	add_child(chooser)
	var n := opts.size()
	var per_row := mini(n, 8)
	var cw := card_size.x
	var x0 := 480 - (per_row * cw + (per_row - 1) * 8) / 2.0
	for i in n:
		var cv := CardView.new()
		cv.opt = opts[i]
		cv.size = card_size
		cv.position = Vector2(x0 + (i % per_row) * (cw + 8), 110 + (i / per_row) * (card_size.y + 16))
		if opts[i].has("label"):
			cv.label_top = opts[i].label
		var idx := i
		cv.pressed.connect(func(): chosen.emit(idx))
		chooser.add_child(cv)
	var cancel := HudScript.PixButton.new()
	cancel.text = "CANCEL"
	cancel.color = Color("9aa2ae")
	cancel.size = Vector2(110, 26)
	cancel.position = Vector2(425, 500)
	cancel.pressed.connect(func(): chosen.emit(-1))
	chooser.add_child(cancel)
	var r: int = await chosen
	chooser.queue_free()
	chooser = null
	return r

func choose_soldier(title: String, alive_only := true) -> Dictionary:
	var cand: Array = Run.soldiers.filter(func(s): return s.alive == alive_only)
	if cand.is_empty():
		return {}
	var opts: Array = cand.map(func(s): return {"kind": "service", "name": s.def.name, "text": "%s  LV%d  HP %d/%d  %d cards" % [s.def.cls, s.lvl, s.hp, s.max_hp, s.deck.size()], "icon": "ic_heart" if s.alive else "ic_skull"})
	var i := await choose(title, opts)
	return cand[i] if i >= 0 else {}

func choose_card(title: String, s: Dictionary, filter := Callable()) -> Dictionary:
	var cand: Array = s.deck if not filter.is_valid() else s.deck.filter(filter)
	if cand.is_empty():
		say("No cards to pick from.")
		return {}
	var opts: Array = cand.map(func(c): return {"kind": "card", "key": c.key, "up": c.up})
	var i := await choose(title, opts, Vector2(96, 132))
	return cand[i] if i >= 0 else {}

func pay(n: int) -> bool:
	if Run.scrip < n:
		Sfx.play("deny")
		say("Not enough scrip.")
		return false
	Run.scrip -= n
	Sfx.play("buy")
	return true

func buy_card(i: int) -> void:
	var o: Dictionary = stock_cards[i]
	if o.get("sold", false) or Run.scrip < o.price:
		Sfx.play("deny")
		return
	var s := await choose_soldier("WHO GETS %s?" % Data.card(o).name.to_upper())
	if s.is_empty() or not pay(o.price):
		return
	s.deck.append(Run.new_card(o.key, o.up))
	o["sold"] = true
	say("%s added to %s's deck." % [Data.card(o).name, s.def.name])
	build()

func buy_gear(i: int) -> void:
	var o: Dictionary = stock_gear[i]
	if o.get("sold", false) or not pay(o.price):
		return
	Run.gear.append(o.id)
	o["sold"] = true
	say("%s issued to the squad." % o.name)
	build()

func heal_all() -> void:
	if not Run.soldiers.any(func(s): return s.alive and s.hp < s.max_hp):
		say("Everyone is already at full health.")
		return
	if not pay(40):
		return
	for s in Run.soldiers:
		if s.alive:
			s.hp = s.max_hp
	say("The squad is patched up.")
	build()

func upgrade_card() -> void:
	if Run.scrip < 60:
		Sfx.play("deny")
		return
	var s := await choose_soldier("UPGRADE WHOSE CARD?")
	if s.is_empty():
		return
	var c := await choose_card("PICK A CARD TO UPGRADE", s, func(c): return not c.up and Data.CARDS[c.key].has("up"))
	if c.is_empty() or not pay(60):
		return
	c.up = true
	say("%s upgraded to %s." % [Data.CARDS[c.key].name, Data.card(c).name])
	build()

func remove_card() -> void:
	if Run.scrip < 50:
		Sfx.play("deny")
		return
	var s := await choose_soldier("THIN WHOSE DECK?")
	if s.is_empty():
		return
	if s.deck.size() <= 5:
		say("%s needs at least 5 cards." % s.def.name)
		return
	var c := await choose_card("PICK A CARD TO BURN", s)
	if c.is_empty() or not pay(50):
		return
	s.deck.erase(c)
	say("%s removed from %s's deck." % [Data.CARDS[c.key].name, s.def.name])
	build()

func revive() -> void:
	if Run.scrip < 120:
		Sfx.play("deny")
		return
	var s := await choose_soldier("REVIVE WHO?", false)
	if s.is_empty():
		say("Nobody needs reviving.")
		return
	if not pay(120):
		return
	s.alive = true
	s.hp = int(ceil(s.max_hp / 2.0))
	say("%s is back on their feet." % s.def.name)
	build()

func reroll() -> void:
	if not pay(20):
		return
	restock()
	build()

class Chooser extends Control:
	var title := ""
	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 540), Color(0.02, 0.02, 0.04, 0.86))
		Art.text(self, title, Vector2(480, 70), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 2)

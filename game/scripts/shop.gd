extends Control
## Two HQ buildings share this screen. The Quartermaster sells cards and squad gear and
## upgrades, removes and heals; the Barracks recruits replacements and restores dog tags.
## Prices are paid in scrip earned in the field.

signal done
signal chosen(i: int)

const HudScript := preload("res://scripts/hud.gd")
const ArmoryScript := preload("res://scripts/armory.gd")

var stock_cards: Array = []
var stock_gear: Array = []
var shelf: Array = []       # item shelf for the Armory: 3 items, a mystery crate, sometimes a black-market legendary
var t := 0
var msg := ""
var msg_t := 0
var chooser: Control = null
var mode := "shop"          # "shop" (Quartermaster) or "barracks"

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# the shelf stays put for the whole HQ visit, so leaving and coming back is not a free restock
	if Run.qm_cache.get("mission", -1) == Run.mission:
		stock_cards = Run.qm_cache.cards
		stock_gear = Run.qm_cache.gear
		shelf = Run.qm_cache.shelf
	else:
		restock()
	build()

func restock() -> void:
	var keys: Array = Data.offer_keys()
	keys.shuffle()
	stock_cards.clear()
	for i in 5:
		var t := Run.roll_card_tier(keys[i])
		stock_cards.append({"kind": "card", "key": keys[i], "tier": t, "price": price(Data.card_price(keys[i], t))})
	var gear: Array = Data.GEAR.filter(func(g): return not Run.has_gear(g.id))
	gear.shuffle()
	stock_gear = gear.slice(0, 3).map(func(g):
		var t := Run.roll_tier()
		return {"kind": "gear", "id": g.id, "icon": g.icon, "name": g.name, "text": Data.relic_text(g.id, t), "tier": t, "price": price(int(g.price * (1.0 + 0.35 * t)))})
	shelf.clear()
	for i in 3:
		var it := Run.roll_item() if i < 2 else Run.new_item(Run.random_item_id(["belt"]))
		shelf.append({"item": it, "price": Run.item_price(it)})
	shelf.append({"mystery": true, "price": 80})
	if randf() < 0.25:
		var lg := Run.roll_item(Data.TIER_MAX)
		shelf.append({"item": lg, "price": 300, "black": true})
	Run.qm_cache = {"mission": Run.mission, "cards": stock_cards, "gear": stock_gear, "shelf": shelf}

func price(n: int) -> int:
	return int(ceil(n * (1.0 - Run.discount)))

func open_armory() -> void:
	Sfx.play("click")
	var a: Control = ArmoryScript.new()
	a.shop_mode = true
	a.shelf = shelf
	a.done.connect(func(): a.queue_free(); build())
	add_child(a)

func say(s: String) -> void:
	msg = s
	msg_t = 200

func build() -> void:
	if mode == "barracks":
		build_barracks()
		return
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
	var fusable := Run.soldiers.any(func(s): return s.alive and (Run.fusable(s).size() > 0 or Run.evolutions(s).size() > 0))
	var services := [
		["HOSPITAL", "Heal the whole squad to full.", 40, heal_all, Color("53d4e2")],
		["UPGRADE", "Raise one card a rarity tier.", 60, upgrade_card, Color("53d4e2")],
		["MOD", "Gunsmith: add an upgrade branch to a card (2 per card).", Data.MOD_PRICE, mod_card, Color("53d4e2")],
		["REMOVE", "Thin a deck: burn one card.", 50, remove_card, Color("53d4e2")],
		["WORKBENCH", "Fuse three copies of a card into one a tier higher, or evolve an Epic card with its kit.", 0, fuse_cards, Color("b48cff")],
		["FABRICATOR", "Copy a Common or Uncommon item.", Data.FAB_PRICE, fabricate, Color("b48cff")],
		["RESTOCK", "New cards and gear on the shelf.", 20, reroll, Color("9aa2ae")],
	]
	for i in services.size():
		var sv: Array = services[i]
		var bt := HudScript.PixButton.new()
		bt.text = sv[0]
		bt.sub = "FREE" if sv[2] == 0 else "%d$" % price(sv[2])
		bt.color = sv[4]
		bt.size = Vector2(108, 34)
		bt.small = true
		bt.position = Vector2(24 + i * 114, 264)
		bt.disabled = Run.scrip < price(sv[2]) or (sv[3] == fuse_cards and not fusable) or (sv[3] == fabricate and Run.fab_options().is_empty())
		bt.tooltip_text = sv[1]
		bt.pressed.connect(sv[3])
		add_child(bt)
	var go := HudScript.PixButton.new()
	add_child(back_button())
	var arm := HudScript.PixButton.new()
	arm.text = "ARMORY"
	arm.sub = "GEAR %d  STASH %d" % [Run.soldiers.reduce(func(a, s): return a + s.equip.values().filter(func(x): return x != null).size(), 0), Run.stash.size()]
	arm.color = Color("53d4e2")
	arm.size = Vector2(190, 44)
	arm.position = Vector2(546, 482)
	arm.pressed.connect(open_armory)
	add_child(arm)

func back_button() -> Control:
	var go := HudScript.PixButton.new()
	go.text = "<< BACK TO HQ"
	go.color = Color("ff4d3d")
	go.size = Vector2(190, 44)
	go.position = Vector2(746, 482)
	go.pressed.connect(func(): Sfx.play("click"); done.emit())
	return go

func build_barracks() -> void:
	var services := [
		["RECRUIT", "Hire a replacement for a soldier killed in action.", Data.RECRUIT_PRICE, recruit, Run.fallen_slots().is_empty()],
		["DOG TAG", "Give a soldier back one spent dog tag.", Data.TAG_PRICE, restore_tag, not Run.soldiers.any(func(s): return s.alive and s.tags < Data.DOG_TAGS)],
	]
	for i in services.size():
		var sv: Array = services[i]
		var bt := HudScript.PixButton.new()
		bt.text = sv[0]
		bt.sub = "%d$" % price(sv[2])
		bt.color = Color("62d26f")
		bt.size = Vector2(200, 40)
		bt.position = Vector2(24 + i * 212, 236)
		bt.disabled = Run.scrip < price(sv[2]) or sv[4]
		bt.tooltip_text = sv[1]
		bt.pressed.connect(sv[3])
		add_child(bt)
	add_child(back_button())

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
	Art.text(self, "QUARTERMASTER" if mode == "shop" else "BARRACKS", Vector2(24, 40), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
	var sub := "Spend scrip before the next drop. Cards go to the soldier you pick." if mode == "shop" else "Hire replacements for the fallen. Buy back spent dog tags. Two tags each; lose the last and they are gone for good."
	Art.text(self, sub, Vector2(24, 60), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
	var sc := "%d SCRIP" % Run.scrip
	draw_texture_rect(Art.tex.ic_coin, Rect2(936 - Art.text_width(sc, 16) - 22, 26, 16, 16), false)
	Art.text(self, sc, Vector2(936, 42), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT, 2)
	if mode == "shop":
		Art.text(self, "FIELD CARDS", Vector2(24, 84), 8, Color("53d4e2"))
		Art.text(self, "SQUAD GEAR", Vector2(600, 84), 8, Color("62d26f"))
	else:
		var fallen: int = Run.fallen_slots().size()
		Art.text(self, "%d KILLED IN ACTION THIS RUN" % fallen if fallen else "THE SQUAD IS AT FULL STRENGTH", Vector2(24, 100), 8, Color("ff4d3d") if fallen else Color("62d26f"))
		Art.text(self, "%d NAMES ON THE MEMORIAL" % Run.meta.memorial.size(), Vector2(24, 120), 8, Color("9aa2ae"))
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
		if s.alive:
			Art.draw_tags(self, Vector2(x + 8, y + 8), s.tags)
		Art.text(self, s.def.cls, Vector2(x + 62, y + 36), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		if s.alive:
			draw_rect(Rect2(x + 62, y + 44, 100, 6), Color(0.05, 0.035, 0.03))
			draw_rect(Rect2(x + 63, y + 45, 98.0 * s.hp / Run.eff_max_hp(s), 4), Color("62d26f") if s.hp > Run.eff_max_hp(s) * 0.3 else Color("ff4d3d"))
			Art.text(self, "HP %d/%d" % [s.hp, Run.eff_max_hp(s)], Vector2(x + 62, y + 64), 8, Color("e8dcc2"))
		else:
			Art.text(self, "KIA", Vector2(x + 62, y + 60), 16, Color("ff4d3d"), HORIZONTAL_ALIGNMENT_LEFT, 2)
		Art.text(self, "DECK %d  XP %d" % [s.deck.size(), s.xp], Vector2(x + 8, y + 94), 8, Color("e8dcc2"))
		var perks: Array = Run.archetypes(s).map(func(a): return "%s %s" % [a[0], ["I", "II", "III"][a[1] - 1]])
		var yy := y + 112
		for line in CardView.wrap_text(", ".join(perks) if perks.size() else "No abilities yet", 156, 16):
			Art.text(self, line, Vector2(x + 8, yy), 16, Color("ffd23a") if perks.size() else Color("6c7480"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
			yy += 13
	# owned gear
	var gx := 24.0
	Art.text(self, "GEAR:", Vector2(gx, 500), 8, Color("62d26f"))
	var names: Array = Run.gear.map(func(g): return "%s (%s)" % [Data.gear(g).name, Data.tier_name(Run.gear_tier.get(g, 0)).capitalize()])
	var gl := ", ".join(names) if names.size() else "none"
	while Art.text_width(gl, 16, true) > 460 and gl.length() > 4:
		gl = gl.substr(0, gl.length() - 4) + "."
	Art.text(self, gl, Vector2(gx + 50, 501), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
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
	var opts: Array = cand.map(func(s): return {"kind": "service", "name": s.def.name, "text": "%s  LV%d  HP %d/%d  %d cards" % [s.def.cls, s.lvl, s.hp, Run.eff_max_hp(s), s.deck.size()], "icon": "ic_heart" if s.alive else "ic_skull"})
	var i := await choose(title, opts)
	return cand[i] if i >= 0 else {}

func choose_card(title: String, s: Dictionary, filter := Callable()) -> Dictionary:
	var cand: Array = s.deck if not filter.is_valid() else s.deck.filter(filter)
	if cand.is_empty():
		say("No cards to pick from.")
		return {}
	var opts: Array = cand.map(func(c): return {"kind": "card", "key": c.key, "tier": Data.tier_of(c)})
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
	s.deck.append(Run.new_card(o.key, o.tier))
	o["sold"] = true
	say("%s added to %s's deck." % [Data.card(o).name, s.def.name])
	build()

func buy_gear(i: int) -> void:
	var o: Dictionary = stock_gear[i]
	if o.get("sold", false) or not pay(o.price):
		return
	Run.add_gear(o.id, o.tier)
	o["sold"] = true
	say("%s issued to the squad." % o.name)
	build()

func heal_all() -> void:
	if not Run.soldiers.any(func(s): return s.alive and s.hp < Run.eff_max_hp(s)):
		say("Everyone is already at full health.")
		return
	if not pay(price(40)):
		return
	for s in Run.soldiers:
		if s.alive:
			s.hp = Run.eff_max_hp(s)
	say("The squad is patched up.")
	build()

func upgrade_card() -> void:
	if Run.scrip < price(60):
		Sfx.play("deny")
		return
	var s := await choose_soldier("UPGRADE WHOSE CARD?")
	if s.is_empty():
		return
	var c := await choose_card("PICK A CARD TO UPGRADE", s, Run.upgradable)
	if c.is_empty() or not pay(price(60)):
		return
	Run.raise_tier(c)
	say("%s is now %s." % [Data.CARDS[c.key].name, Data.tier_name(Data.tier_of(c)).capitalize()])
	build()

func remove_card() -> void:
	if Run.scrip < price(50):
		Sfx.play("deny")
		return
	var s := await choose_soldier("THIN WHOSE DECK?")
	if s.is_empty():
		return
	if s.deck.size() <= 5:
		say("%s needs at least 5 cards." % s.def.name)
		return
	var c := await choose_card("PICK A CARD TO BURN", s)
	if c.is_empty() or not pay(price(50)):
		return
	s.deck.erase(c)
	say("%s removed from %s's deck." % [Data.CARDS[c.key].name, s.def.name])
	build()

func mod_card() -> void:
	## P3: pick a card, then one of its upgrade branches. A card holds two mods.
	if Run.scrip < price(Data.MOD_PRICE):
		Sfx.play("deny")
		return
	var s := await choose_soldier("MOD WHOSE CARD?")
	if s.is_empty():
		return
	var c := await choose_card("PICK A CARD TO MOD", s, func(x): return Data.mod_options(x).size() > 0)
	if c.is_empty():
		return
	var mods := Data.mod_options(c)
	var opts: Array = mods.map(func(m): return {"kind": "service", "name": m.name, "text": m.text, "icon": "ic_up"})
	var i := await choose("%s: PICK A MOD" % Data.card(c).name.to_upper(), opts)
	if i < 0 or not pay(price(Data.MOD_PRICE)):
		return
	if not c.has("mods"):
		c["mods"] = []
	c.mods.append(mods[i].id)
	say("%s gets %s." % [Data.CARDS[c.key].name, mods[i].name])
	build()

func fuse_cards() -> void:
	## M3: three copies of one card at one rarity fuse into a single card a tier higher.
	var cand: Array = []
	for s in Run.soldiers:
		if s.alive:
			for g in Run.fusable(s):
				cand.append({"s": s, "g": g})
			for ev in Run.evolutions(s):
				cand.append({"s": s, "ev": ev})
	if cand.is_empty():
		say("Nothing to fuse or evolve yet.")
		return
	var opts: Array = cand.map(func(o):
		if o.has("ev"):
			return {"kind": "card", "key": o.ev.rule.into, "tier": Data.tier_of(o.ev.card), "label": "%s: EVOLVE" % o.s.def.name}
		return {"kind": "card", "key": o.g[0].key, "tier": Data.tier_of(o.g[0]) + 1, "label": "%s: 3 INTO 1" % o.s.def.name})
	var i := await choose("WORKBENCH: FUSE OR EVOLVE", opts)
	if i < 0:
		return
	if cand[i].has("ev"):
		var ev: Dictionary = cand[i].ev
		var from: String = Data.CARDS[ev.card.key].name
		Run.evolve(ev.card, ev.rule)
		Sfx.play("levelup")
		say("%s evolved into %s!" % [from, Data.CARDS[ev.rule.into].name])
		build()
		return
	var c := Run.fuse(cand[i].s, cand[i].g)
	Sfx.play("levelup")
	say("%s fused into %s %s." % [Data.CARDS[c.key].name, Data.tier_name(Data.tier_of(c)).capitalize(), Data.card(c).name])
	build()

func fabricate() -> void:
	## M5: duplicate a Common or Uncommon item to finish a triple.
	var cand := Run.fab_options()
	if cand.is_empty():
		say("The Fabricator only copies Common and Uncommon items.")
		return
	var i := await choose("COPY WHICH ITEM?", cand.map(func(it): return Run.item_opt(it)))
	if i < 0 or not pay(price(Data.FAB_PRICE)):
		return
	var cp := Run.fabricate(cand[i])
	say("Fabricated a copy of %s.%s" % [Data.item_name(cp), " A triple is ready at the Armory." if Run.merge_group_of(cp).size() == 3 else ""])
	build()

func recruit() -> void:
	var slots := Run.fallen_slots()
	if slots.is_empty():
		say("Nobody to replace. The squad is at full strength.")
		return
	if Run.scrip < price(Data.RECRUIT_PRICE):
		Sfx.play("deny")
		return
	var fallen: Dictionary = Run.soldiers[slots[0]]
	var offers := Run.recruit_offers()
	var opts: Array = offers.map(func(o):
		var d: Dictionary = Data.SQUAD_DEFS.filter(func(x): return x.key == o.key)[0]
		var txt := "%s. %s: %s" % [d.cls, o.trait.name, o.trait.text]
		if not o.legacy.is_empty():
			txt += " Legacy from %s: %s." % [o.legacy.from, Data.perk(o.key, o.legacy.id).name]
		return {"kind": "service", "name": o.name, "text": txt, "icon": "ic_heart"})
	var i := await choose("REPLACE %s WITH..." % fallen.def.name, opts)
	if i < 0 or not pay(price(Data.RECRUIT_PRICE)):
		return
	var s := Run.hire(slots[0], offers[i])
	say("%s joins the squad as a %s." % [s.def.name, s.def.cls])
	build()

func restore_tag() -> void:
	if Run.scrip < price(Data.TAG_PRICE):
		Sfx.play("deny")
		return
	var cand: Array = Run.soldiers.filter(func(s): return s.alive and s.tags < Data.DOG_TAGS)
	if cand.is_empty():
		say("Everyone still has all their dog tags.")
		return
	var opts: Array = cand.map(func(s): return {"kind": "service", "name": s.def.name, "text": "%s  %d of %d dog tags left" % [s.def.cls, s.tags, Data.DOG_TAGS], "icon": "ic_heart"})
	var i := await choose("WHO GETS A NEW DOG TAG?", opts)
	if i < 0 or not pay(price(Data.TAG_PRICE)):
		return
	cand[i].tags += 1
	say("%s has %d dog tags again." % [cand[i].def.name, cand[i].tags])
	build()

func reroll() -> void:
	if not pay(price(20)):
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

extends Control
## Two HQ buildings share this screen. The Quartermaster sells things: field cards for one
## soldier's deck, squad gear, and the item shelf. The Barracks recruits replacements and
## restores dog tags. Card changes live at the Workshop, healing at the Doc's Lab and
## item copying at the Armory. Prices are paid in scrip earned in the field.

signal done
signal chosen(i: int)

const HudScript := preload("res://scripts/hud.gd")
const ArmoryScript := preload("res://scripts/armory.gd")
const HubUI := preload("res://scripts/hub_ui.gd")
const Services := preload("res://scripts/services.gd")

const BAR := Vector2(16, 80)
const CARD_Y := 148.0
const SHELF_Y := 372.0
const BARKS := [
	"Cards up top go into one soldier's deck. Click a card, then the soldier. Or drag it onto them.",
	"Squad gear helps everyone at once. Shelf items go to the stash; equip them at the Armory or from a soldier's Dossier.",
	"Want a card changed? Polish, mods, fusing and burning are next door at the Workshop.",
]

var stock_cards: Array = []
var stock_gear: Array = []
var shelf: Array = []       # item shelf: 3 items, a mystery crate, sometimes a black-market legendary
var t := 0
var msg := ""
var msg_t := 0
var chooser: Control = null
var mode := "shop"          # "shop" (Quartermaster) or "barracks"
var bar: Control = null
var shelf_pick := -1
var bark := -1              # Q6: which Quartermaster line is showing, -1 for none

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# the shelf stays put for the whole HQ visit, so leaving and coming back is not a free restock
	if Run.qm_cache.get("mission", -1) == Run.mission:
		stock_cards = Run.qm_cache.cards
		stock_gear = Run.qm_cache.gear
		shelf = Run.qm_cache.shelf
	else:
		restock()
	if mode == "shop":
		if not Run.qm_cache.get("barked", false) and not Run.meta.get("tips_off", false):
			bark = 0
		Run.qm_cache["barked"] = true
		Run.qm_cache["seen"] = true
	build()

func restock() -> void:
	var keys: Array = Data.offer_keys()
	keys.shuffle()
	stock_cards.clear()
	for i in 5:
		var t := Run.roll_card_tier(keys[i])
		stock_cards.append({"kind": "card", "key": keys[i], "tier": t, "price": price(Data.card_price(keys[i], t))})
	var gear: Array = Data.GEAR.filter(func(g): return not Run.has_gear(g.id) and not g.get("boss", false) and g.get("from", 0) <= Run.mission)
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
	var keep := Run.qm_cache.duplicate() if Run.qm_cache.get("mission", -1) == Run.mission else {}
	Run.qm_cache = {"mission": Run.mission, "cards": stock_cards, "gear": stock_gear, "shelf": shelf,
		"barked": keep.get("barked", false), "seen": keep.get("seen", false)}

func price(n: int) -> int:
	return Services.price(n)

func recruit_price() -> int:
	return Data.RECRUIT_PRICE / (2 if Run.hq("barracks") >= 3 else 1)

func open_armory() -> void:
	Sfx.play("click")
	var a: Control = ArmoryScript.new()
	a.shop_mode = true
	a.done.connect(func(): a.queue_free(); build())
	add_child(a)

func say(s: String) -> void:
	msg = s
	msg_t = 200

func build() -> void:
	for c in get_children():
		c.queue_free()
	chooser = null
	bar = HubUI.SquadBar.new()
	bar.position = BAR
	bar.picked.connect(open_dossier)
	bar.all_decks.connect(func(): open_dossier(0, "squad"))
	add_child(bar)
	if mode == "barracks":
		build_barracks()
		return
	var cw := 104.0
	for i in stock_cards.size():
		var o: Dictionary = stock_cards[i]
		var cv := CardView.new()
		cv.opt = o
		cv.size = Vector2(cw, 146)
		cv.position = Vector2(24 + i * (cw + 8), CARD_Y)
		cv.price = o.price
		cv.disabled = o.get("sold", false) or Run.scrip < o.price
		cv.sold = o.get("sold", false)
		var idx := i
		cv.pressed.connect(func(): buy_card(idx))
		add_child(cv)
	for i in stock_gear.size():
		var o: Dictionary = stock_gear[i]
		var cv := CardView.new()
		cv.opt = o
		cv.size = Vector2(cw, 146)
		cv.position = Vector2(600 + i * (cw + 8), CARD_Y)
		cv.price = o.price
		cv.disabled = o.get("sold", false) or Run.scrip < o.price
		cv.sold = o.get("sold", false)
		var idx := i
		cv.pressed.connect(func(): buy_gear(idx))
		add_child(cv)
	for i in shelf.size():
		var o: Dictionary = shelf[i]
		var tile := ArmoryScript.ItemTile.new()
		tile.item = null if o.get("mystery", false) else o.item
		tile.mystery = o.get("mystery", false)
		tile.black = o.get("black", false)
		tile.price = -1 if o.get("sold", false) else price(o.price)
		tile.sold = o.get("sold", false)
		tile.position = Vector2(24 + i * 112, SHELF_Y)
		tile.selected = shelf_pick == i
		var idx := i
		tile.pressed.connect(func(): Sfx.play("click"); shelf_pick = -1 if shelf_pick == idx else idx; build())
		add_child(tile)
	if shelf_pick >= 0 and shelf_pick < shelf.size() and not shelf[shelf_pick].get("sold", false):
		var o: Dictionary = shelf[shelf_pick]
		var p := price(o.price)
		var tile := HubUI.ActionTile.new()
		tile.color = Color("62d26f")
		tile.size = Vector2(336, 64)
		tile.position = Vector2(600, SHELF_Y - 8)
		tile.cost = p
		if o.get("mystery", false):
			tile.title = "BUY MYSTERY CRATE"
			tile.line = "A random item of any rarity. Goes to the stash."
		else:
			var it: Dictionary = o.item
			tile.title = "BUY %s" % Data.item_name(it).to_upper()
			var sl: Array = Data.stat_lines(Data.item_stats(it))
			tile.line = "%s %s. Goes to the %s." % [Data.tier_name(it.tier).capitalize(), ", ".join(sl) if sl.size() else Data.ITEMS[it.id].text, "belt" if Data.ITEMS[it.id].slot == "belt" else "stash"]
		tile.ok = Run.scrip >= p
		tile.why = Services.short(p)
		tile.pressed.connect(buy_shelf)
		add_child(tile)
	var rs := HubUI.ActionTile.new()
	rs.title = "NEW STOCK"
	rs.cost = price(Services.RESTOCK)
	rs.color = Color("9aa2ae")
	rs.line = "Replace the cards, gear and shelf on sale."
	rs.ok = Run.scrip >= rs.cost
	rs.why = Services.short(rs.cost)
	rs.size = Vector2(220, 52)
	rs.position = Vector2(24, SHELF_Y + 64)
	rs.pressed.connect(reroll)
	add_child(rs)
	add_child(back_button())
	if bark >= 0:
		var b := Bark.new()
		b.shop = self
		add_child(b)

func open_dossier(i: int, tb := "deck") -> void:
	## The squad bar here opens the soldier's Dossier over the shop.
	var d: Control = load("res://scripts/dossier.gd").new()
	d.idx = i
	d.tab = tb
	d.done.connect(func(): d.queue_free(); build())
	add_child(d)

func back_button() -> Control:
	var go := HudScript.PixButton.new()
	go.text = "<< BACK TO HQ"
	go.color = Color("ff4d3d")
	go.size = Vector2(190, 44)
	go.position = Vector2(746, 482)
	go.pressed.connect(func(): Sfx.play("click"); done.emit())
	return go

func build_barracks() -> void:
	var fallen := Run.fallen_slots()
	var rp := price(recruit_price())
	var tp := price(Data.TAG_PRICE)
	var short_tags: Array = Run.soldiers.filter(func(s): return s.alive and s.tags < Data.DOG_TAGS)
	var tags_line := ", ".join(short_tags.map(func(s): return "%s has %d" % [s.def.name, s.tags])) if short_tags.size() else "Everyone has both"
	var trainee: Array = Run.soldiers.filter(func(s): return s.alive and s.get("train", false))
	var tiles := [
		["RECRUIT", rp, "Hire a replacement for a soldier killed in action. Pick from %d recruits." % (3 if Run.hq("barracks") >= 1 else 2), recruit,
			"Nobody has fallen. The squad is at full strength." if fallen.is_empty() else Services.short(rp), not fallen.is_empty() and Run.scrip >= rp],
		["DOG TAG", tp, "Give a soldier back one spent dog tag. %s." % tags_line, restore_tag,
			"Everyone still has both dog tags." if short_tags.is_empty() else Services.short(tp), short_tags.size() > 0 and Run.scrip >= tp],
	]
	if Run.campaign():
		# C1: the campaign hires into the company instead of into a dead soldier's slot
		var n := Run.company().size()
		tiles[0] = ["RECRUIT", rp, "Hire a new soldier into the company (%d of %d). Pick from %d recruits.%s" % [n, Data.COMPANY_MAX, 3 if Run.hq("barracks") >= 1 else 2, " They inherit %s's best cards." % Run.legacy_deck().name if not Run.legacy_deck().is_empty() else ""], recruit,
			"The company is full." if not Run.company_room() else Services.short(rp), Run.company_room() and Run.scrip >= rp]
	if trainee.size():
		tiles.append(["TRAINING", 0, "%s's free level from Barracks 2. Pick it like a level-up." % trainee[0].def.name, func(): train(trainee[0]), "", true])
	for i in tiles.size():
		var sv: Array = tiles[i]
		var tile := HubUI.ActionTile.new()
		tile.title = sv[0]
		tile.cost = sv[1]
		tile.line = sv[2]
		tile.why = sv[4]
		tile.ok = sv[5]
		tile.color = Color("62d26f")
		tile.size = Vector2(300, 74)
		tile.position = Vector2(24 + i * 312, 150)
		tile.pressed.connect(sv[3])
		add_child(tile)
	# U3: change any soldier's headgear and kit colors, free
	for i in Run.soldiers.size():
		if not Run.soldiers[i].alive:
			continue
		for j in 2:
			var lb := HudScript.PixButton.new()
			lb.text = ["HEADGEAR", "COLORS"][j]
			lb.color = Color("53d4e2")
			lb.size = Vector2(82, 20)
			lb.position = Vector2(24 + i * 180 + j * 90, 470)
			lb.tooltip_text = "Free. Cycle this soldier's headgear." if j == 0 else "Free. Roll new colors for hat, shirt and pants."
			var si := i
			lb.pressed.connect(func(): restyle(si, j == 0))
			add_child(lb)
	add_child(back_button())

func restyle(i: int, head: bool) -> void:
	var s: Dictionary = Run.soldiers[i]
	var lk: Dictionary = s.get("look", {}).duplicate()
	if head:
		var opts: Array = [""] + Art.LOOK_HEADS
		var cur: String = lk.get("head", "")
		lk["head"] = opts[(opts.find(cur) + 1) % opts.size()]
	else:
		var r := Art.random_look()
		for k in ["hat", "shirt", "pants"]:
			lk[k] = r[k]
	s["look"] = lk
	Sfx.play("click")
	say("%s: %s" % [s.def.name, "NEW HEADGEAR" if head else "NEW COLORS"])

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
	var title := "QUARTERMASTER" if mode == "shop" else "BARRACKS"
	Art.text(self, title, Vector2(24, 60), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
	var sub := "Buy cards, gear and items. Card changes are at the Workshop." if mode == "shop" else "Hire replacements. Buy back spent dog tags."
	Art.text(self, sub, Vector2(24 + Art.text_width(title, 16) + 24, 58), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
	var sc := "%d SCRIP" % Run.scrip
	draw_texture_rect(Art.tex.ic_coin, Rect2(936 - Art.text_width(sc, 16) - 22, 44, 16, 16), false)
	Art.text(self, sc, Vector2(936, 60), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT, 2)
	if mode == "shop":
		Art.text(self, "FIELD CARDS: ONE SOLDIER'S DECK", Vector2(24, 140), 8, Color("53d4e2"))
		Art.text(self, "SQUAD GEAR: HELPS EVERYONE", Vector2(600, 140), 8, Color("62d26f"))
		for x in range(0, 960, 32):
			draw_texture_rect(hz, Rect2(x, 346, 32, 6), false)
		Art.text(self, "ITEM SHELF: GOES TO THE STASH", Vector2(24, SHELF_Y - 8), 8, Color("ffb23e"))
		draw_card_fits()
	else:
		var fallen: int = Run.fallen_slots().size()
		if Run.campaign():
			Art.text(self, "COMPANY: %d OF %d SOLDIERS" % [Run.company().size(), Data.COMPANY_MAX], Vector2(24, 140), 8, Color("62d26f"))
		else:
			Art.text(self, "%d KILLED IN ACTION THIS RUN" % fallen if fallen else "THE SQUAD IS AT FULL STRENGTH", Vector2(24, 140), 8, Color("ff4d3d") if fallen else Color("62d26f"))
		var lore := "Lose the last dog tag and a soldier is gone for good. %d names on the Memorial; recruits of a fallen soldier's class can inherit one of their abilities." % Run.meta.memorial.size()
		var lines: Array = CardView.wrap_text(lore, 900, 16)
		for i in lines.size():
			Art.text(self, lines[i], Vector2(24, 250 + i * 16 - (lines.size() - 1) * 8), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		# U3: the squad's looks, each with its restyle buttons below
		Art.text(self, "SQUAD LOOKS: FREE", Vector2(24, 352), 8, Color("53d4e2"))
		for i in Run.soldiers.size():
			var s: Dictionary = Run.soldiers[i]
			var x := 24.0 + i * 180
			draw_rect(Rect2(x, 362, 172, 100), Color(0.05, 0.035, 0.03))
			draw_rect(Rect2(x + 1, 363, 170, 98), Color("2a2e34"))
			Art.draw_char(self, Art.look_sheet(s), "idle" if s.alive else "die", (t / 12 + i) % 4 if s.alive else 5, Vector2(x + 86, 450), 1, false, 0, 1.0, 0, true, 1.6)
			Art.text(self, s.def.name, Vector2(x + 8, 378), 8, Color.WHITE if s.alive else Color("8a7a7a"))
	if msg_t > 0 and not chooser is TilePicker:
		var w := Art.text_width(msg, 16, true) + 20
		draw_rect(Rect2(480 - w / 2, 316, w, 20), Color(0.05, 0.035, 0.03, 0.9))
		Art.text(self, msg, Vector2(480, 331), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 0, true)

func users(key: String) -> Array:
	## Living soldiers whose class pool has this card, so it fits how they fight.
	return Run.soldiers.filter(func(s): return s.alive and s.def.pool.has(key))

func draw_card_fits() -> void:
	## Q5: under each shop card, the faces of who it suits and any archetype it feeds.
	for i in stock_cards.size():
		var o: Dictionary = stock_cards[i]
		if o.get("sold", false):
			continue
		var x := 24.0 + i * 112
		var us := users(o.key)
		for k in us.size():
			Art.draw_char(self, Art.look_sheet(us[k]), "idle", 0, Vector2(x + 10 + k * 22, CARD_Y + 186), 1, false, 0, 1.0, 0, false, 0.6)
		if us.is_empty():
			Art.text(self, "ANYONE", Vector2(x, CARD_Y + 180), 8, Color("6c7480"))
		for s in Run.soldiers:
			if not s.alive:
				continue
			var fit := Services.branch_fit(s, o.key)
			if fit != "":
				Art.text(self, "FITS " + fit.to_upper(), Vector2(x + 52, CARD_Y + 196), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
				break

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

func choose_soldier(title: String, alive_only := true, focus := Rect2()) -> Dictionary:
	var cand: Array = Run.soldiers.filter(func(s): return s.alive == alive_only)
	if cand.is_empty():
		return {}
	var i := await pick_tile(title, cand, focus)
	return cand[i] if i >= 0 else {}

func tile_rect(i: int) -> Rect2:
	## A soldier's plate on the squad bar, in screen space.
	var r: Rect2 = bar.plate(i) if bar != null else Rect2()
	return Rect2(r.position + BAR, r.size)

func pick_tile(title: String, cand: Array, focus := Rect2(), hint := Callable(), drag := {}) -> int:
	## The squad bar plates light up and the soldier is picked by clicking one, or by
	## dropping a dragged card on one; everything else dims. Returns the index into cand, or -1.
	var tp := TilePicker.new()
	tp.title = title
	tp.focus = focus
	tp.tiles = cand.map(func(s): return tile_rect(Run.soldiers.find(s)))
	if hint.is_valid():
		tp.hint = func(k: int) -> String: return hint.call(cand[k])
	tp.drag = drag
	tp.picked.connect(func(k): chosen.emit(k))
	chooser = tp
	add_child(tp)
	var r: int = await chosen
	tp.queue_free()
	chooser = null
	return r

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
	if o.get("sold", false) or Run.scrip < o.price or chooser != null:
		Sfx.play("deny")
		return
	var hint := func(s: Dictionary) -> String:
		var fit := Services.branch_fit(s, o.key)
		return "%s: deck %d > %d.%s" % [s.def.name, s.deck.size(), s.deck.size() + 1, (" Feeds %s." % fit) if fit != "" else ""]
	var cand: Array = Run.soldiers.filter(func(s): return s.alive)
	if cand.is_empty():
		return
	var drag := {"opt": o, "held": Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)}
	var k := await pick_tile("WHO GETS %s?" % Data.card(o).name.to_upper(), cand, Rect2(24 + i * 112, CARD_Y, 104, 146), hint, drag)
	if k < 0 or not pay(o.price):
		return
	var s: Dictionary = cand[k]
	s.deck.append(Run.new_card(o.key, o.tier, "shop"))
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

func buy_shelf() -> void:
	if shelf_pick < 0:
		return
	var o: Dictionary = shelf[shelf_pick]
	var p := price(o.price)
	if o.get("sold", false) or not pay(p):
		return
	o.sold = true
	var it: Dictionary = o.item if not o.get("mystery", false) else Run.roll_item()
	var where := Run.add_loot(it)
	say("%s %s added to the %s." % [Data.tier_name(it.tier).capitalize(), Data.item_name(it), where])
	shelf_pick = -1
	build()

func recruit() -> void:
	if Run.campaign():
		await enlist()
		return
	var slots := Run.fallen_slots()
	if slots.is_empty():
		say("Nobody to replace. The squad is at full strength.")
		return
	if Run.scrip < price(recruit_price()):
		Sfx.play("deny")
		return
	var fallen: Dictionary = Run.soldiers[slots[0]]
	var offers := Run.recruit_offers()
	var opts: Array = offers.map(func(o):
		var d: Dictionary = Data.SQUAD_DEFS.filter(func(x): return x.key == o.key)[0]
		var tt: String = o.trait.text
		if o.trait.id == "drilled" and o.drill_card != "":
			tt = "Starts with %s one rarity up." % Data.CARDS[o.drill_card].name
		var txt := "%s. %s: %s" % [d.cls, o.trait.name, tt]
		if not o.legacy.is_empty():
			txt += " Legacy from %s: %s." % [o.legacy.from, Data.perk(o.key, o.legacy.id).name]
		return {"kind": "service", "name": o.name, "text": txt, "icon": "ic_heart"})
	var i := await choose("REPLACE %s WITH..." % fallen.def.name, opts)
	if i < 0 or not pay(price(recruit_price())):
		return
	var s := Run.hire(slots[0], offers[i])
	say("%s joins the squad as a %s." % [s.def.name, s.def.cls])
	build()
	if s.get("train", false):
		await train(s)

func enlist() -> void:
	if not Run.company_room() or Run.scrip < price(recruit_price()):
		Sfx.play("deny")
		return
	var offers := Run.recruit_offers()
	var opts: Array = offers.map(func(o):
		var d: Dictionary = Data.SQUAD_DEFS.filter(func(x): return x.key == o.key)[0]
		var txt := "%s. %s: %s" % [d.cls, o.trait.name, o.trait.text]
		if o.legacy_deck != "":
			txt += " Inherits %s's best cards." % o.legacy_deck
		return {"kind": "service", "name": o.name, "text": txt, "icon": "ic_heart"})
	var i := await choose("HIRE INTO THE COMPANY", opts)
	if i < 0 or not pay(price(recruit_price())):
		return
	var s := Run.enlist(offers[i])
	say("%s joins the company as a %s. Put them in the squad from the War Room." % [s.def.name, s.def.cls])
	build()

func train(s: Dictionary) -> void:
	## Barracks 2: the recruit's free level, picked like a level-up.
	var opts := Run.level_options(s)
	var i := await choose("%s'S TRAINING: PICK ONE" % s.def.name, opts, Vector2(132, 176))
	if i < 0:
		say("%s's training waits here at the Barracks." % s.def.name)
		build()
		return
	if int(s.train) > 1:
		s.train = int(s.train) - 1
	else:
		s.erase("train")
	say(Run.apply_option(s, opts[i]))
	build()

func restore_tag() -> void:
	if Run.scrip < price(Data.TAG_PRICE):
		Sfx.play("deny")
		return
	var cand: Array = Run.soldiers.filter(func(s): return s.alive and s.tags < Data.DOG_TAGS)
	if cand.is_empty():
		say("Everyone still has all their dog tags.")
		return
	var i := await pick_tile("WHO GETS A NEW DOG TAG?", cand)
	if i < 0 or not pay(price(Data.TAG_PRICE)):
		return
	cand[i].tags += 1
	say("%s has %d dog tags again." % [cand[i].def.name, cand[i].tags])
	build()

func reroll() -> void:
	if not pay(price(Services.RESTOCK)):
		return
	restock()
	shelf_pick = -1
	build()

class Chooser extends Control:
	var title := ""
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 540), Color(0.02, 0.02, 0.04, 0.86))
		Art.text(self, title, Vector2(480, 70), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 2)

class Bark extends Control:
	## Q6: the Quartermaster explains the tent once per run. Click to go on; SKIP or NEVER AGAIN.
	var shop
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var x := 560.0
		for b in [["NEXT", 0], ["SKIP", 1], ["DON'T SHOW AGAIN", 2]]:
			var bt := HudScript.PixButton.new()
			bt.text = b[0]
			bt.color = Color("ffd23a") if b[1] == 0 else Color("9aa2ae")
			bt.size = Vector2(Art.text_width(b[0], 8) + 30, 22)
			bt.position = Vector2(x, 504)
			x += bt.size.x + 8
			var k: int = b[1]
			bt.pressed.connect(func(): press(k))
			add_child(bt)
	func press(k: int) -> void:
		Sfx.play("click")
		if k == 2:
			Run.meta["tips_off"] = true
			Run.save_meta()
		if k == 0 and shop.bark < BARKS.size() - 1:
			shop.bark += 1
			return
		shop.bark = -1
		queue_free()
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			press(0)
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 540), Color(0.02, 0.02, 0.04, 0.45))
		var r := Rect2(24, 430, 912, 104)
		draw_rect(r, Color(0.05, 0.035, 0.03, 0.96))
		draw_rect(r, Color("ffd23a"), false, 2.0)
		draw_rect(Rect2(36, 442, 60, 60), Color("2e3a24"))
		Art.text(self, "QM", Vector2(66, 478), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 2)
		Art.text(self, "THE QUARTERMASTER  %d/%d" % [shop.bark + 1, BARKS.size()], Vector2(110, 452), 8, Color("ffd23a"))
		var y := 474.0
		for ln in CardView.wrap_text(BARKS[maxi(shop.bark, 0)], 800, 16):
			Art.text(self, ln, Vector2(110, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
			y += 16

class TilePicker extends Control:
	## Soldier pick over the shop: candidate squad-bar plates pulse and take the click (or the
	## drop of a dragged card); right-click, ESC or CANCEL backs out.
	signal picked(i: int)
	var title := ""
	var tiles: Array = []      # Rect2 per candidate
	var focus := Rect2()       # what is being handed out (a shop card), left undimmed
	var hint := Callable()     # k -> a line about what picking candidate k does
	var drag := {}             # {opt, held}: a shop card following the mouse until it is dropped
	var hover := -1
	var t := 0
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var cancel := HudScript.PixButton.new()
		cancel.text = "CANCEL"
		cancel.color = Color("9aa2ae")
		cancel.size = Vector2(130, 34)
		cancel.position = Vector2(24, 488)
		cancel.pressed.connect(func(): Sfx.play("click"); picked.emit(-1))
		add_child(cancel)
	func _process(_d: float) -> void:
		t += 1
		hover = -1
		var mp := get_local_mouse_position()
		for k in tiles.size():
			if tiles[k].has_point(mp):
				hover = k
		queue_redraw()
	func _input(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			picked.emit(-1)
		elif ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and drag.get("held", false):
			# the card was dragged: dropping it on a plate picks that soldier, anywhere else keeps the pick open
			drag.held = false
			for k in tiles.size():
				if tiles[k].has_point(get_local_mouse_position()):
					get_viewport().set_input_as_handled()
					Sfx.play("select")
					picked.emit(k)
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_RIGHT:
				picked.emit(-1)
			elif ev.button_index == MOUSE_BUTTON_LEFT:
				for k in tiles.size():
					if tiles[k].has_point(ev.position):
						Sfx.play("select")
						picked.emit(k)
			accept_event()
	func _draw() -> void:
		var dim := Color(0.02, 0.02, 0.04, 0.72)
		# dim everything except the candidate tiles and the focus card
		var holes: Array = tiles.duplicate()
		if focus.has_area():
			holes.append(focus.grow(4))
		var ys: Array = [0.0, 540.0]
		for h in holes:
			ys.append(h.position.y); ys.append(h.end.y)
		ys.sort()
		for k in ys.size() - 1:
			var y0: float = ys[k]
			var y1: float = ys[k + 1]
			if y1 <= y0:
				continue
			var xs: Array = []
			for h in holes:
				if h.position.y <= y0 and h.end.y >= y1:
					xs.append(Vector2(h.position.x, h.end.x))
			xs.sort_custom(func(a, b): return a.x < b.x)
			var x := 0.0
			for r in xs:
				if r.x > x:
					draw_rect(Rect2(x, y0, r.x - x, y1 - y0), dim)
				x = maxf(x, r.y)
			if x < 960:
				draw_rect(Rect2(x, y0, 960 - x, y1 - y0), dim)
		var by := 360.0
		draw_rect(Rect2(0, by, 960, 60), Color(0.05, 0.035, 0.03, 0.94))
		draw_rect(Rect2(0, by, 960, 2), Color("ffd23a"))
		draw_rect(Rect2(0, by + 58, 960, 2), Color("ffd23a"))
		Art.text(self, title, Vector2(480, by + 26), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 2)
		var sub := "Click a soldier on the bar at the top, or drag the card onto them. Right-click or ESC to cancel."
		if hover >= 0 and hint.is_valid():
			sub = hint.call(hover)
		Art.text(self, sub, Vector2(480, by + 46), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
		var pulse := 0.55 + 0.45 * sin(t / 8.0)
		for k in tiles.size():
			var r: Rect2 = tiles[k]
			var on := k == hover
			var col := Color("ffd23a") if not on else Color.WHITE
			draw_rect(r.grow(3), Color(col, 1.0 if on else pulse), false, 3.0)
			if on:
				draw_rect(r, Color(1, 1, 1, 0.08))
			# a bouncing arrow under each pickable soldier, pointing up at them
			var ax := r.get_center().x
			var ay := r.end.y + 6 + (2 if (t / 10) % 2 == 0 else 0)
			draw_colored_polygon(PackedVector2Array([Vector2(ax - 6, ay + 6), Vector2(ax + 6, ay + 6), Vector2(ax, ay)]), col)
		if drag.get("held", false):
			var mp := get_local_mouse_position()
			var r := Rect2(mp - Vector2(44, 20), Vector2(88, 40))
			draw_rect(r, Color(0.05, 0.035, 0.03, 0.9))
			draw_rect(r, Color("ffd23a"), false, 2.0)
			Art.text(self, Data.card(drag.opt).name, r.get_center() + Vector2(0, 5), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 0, true)

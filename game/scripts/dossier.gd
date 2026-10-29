extends Control
## The Dossier: everything about one soldier on one screen. SHEET (stats, archetypes, implants,
## duos), GEAR (their four slots and the shared stash) and DECK (every card, the cost curve,
## live chains). Card services sit on the selected card and show the result before you pay.
## Opens from the squad bar or 1-5 at HQ; Q/E or the arrow keys flip to the next soldier.

signal done

const HudScript := preload("res://scripts/hud.gd")
const HubUI := preload("res://scripts/hub_ui.gd")
const Services := preload("res://scripts/services.gd")
const ArmoryScript := preload("res://scripts/armory.gd")

const LEFT := Rect2(16, 92, 196, 440)
const MID := Rect2(224, 92, 540, 440)
const RIGHT := Rect2(776, 92, 168, 440)
const CW := 72.0
const CH := 124.0
const PER_PAGE := 14
const SLOTS := ["weapon", "armor", "kit1", "kit2"]

var idx := 0
var tab := "deck"            # sheet, gear, deck, or squad (all four decks side by side)
var readonly := false        # opened from the field: look, don't touch
var sel = null               # the selected card (deck tab)
var page := 0
var sort := "cost"           # cost, type, rarity
var filt := ""               # "", polish, mod, fuse, burn
var show_up := false         # deck tab: preview every card one rarity up
var gear_pick := {}          # gear tab: {where: stash|equip|belt, i, slot}
var modal: Control = null    # a before/after preview waiting for CONFIRM
var mod_pick := -1
var msg := ""
var msg_t := 0
var t := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	build()

func s() -> Dictionary:
	return Run.soldiers[idx]

func say(m: String) -> void:
	msg = m
	msg_t = 200

func switch_to(i: int) -> void:
	if i == idx:
		return
	idx = i
	sel = null
	page = 0
	gear_pick = {}
	Sfx.play("select")
	build()

func cycle(d: int) -> void:
	switch_to(posmod(idx + d, Run.soldiers.size()))

func set_tab(tb: String) -> void:
	Sfx.play("click")
	tab = tb
	build()

func _input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	if modal != null:
		if ev.keycode == KEY_ESCAPE:
			close_modal()
			get_viewport().set_input_as_handled()
		return
	match ev.keycode:
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			Sfx.play("click")
			done.emit()
		KEY_Q, KEY_LEFT:
			cycle(-1)
		KEY_E, KEY_RIGHT:
			cycle(1)
		KEY_T:
			if readonly or not s().alive or tab == "squad":
				return
			practice()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			var k: int = ev.keycode - KEY_1
			if k < Run.soldiers.size():
				switch_to(k)
		KEY_TAB:
			var tabs := ["sheet", "gear", "deck", "squad"]
			set_tab(tabs[(tabs.find(tab) + 1) % tabs.size()])
		_:
			if not readonly:  # in the field, keys must not reach the battle underneath
				return
	get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- layout
func build() -> void:
	for c in get_children():
		c.queue_free()
	modal = null
	var bar := HubUI.SquadBar.new()
	bar.position = Vector2(16, 44)
	bar.current = HubUI.ALL_PLATE if tab == "squad" else idx
	bar.picked.connect(func(i):
		if tab == "squad":
			tab = "deck"
			idx = -1
		switch_to(i))
	bar.all_decks.connect(func(): set_tab("squad"))
	add_child(bar)
	var tabs := [["SHEET", "sheet"], ["GEAR", "gear"], ["DECK %d" % s().deck.size(), "deck"], ["ALL DECKS", "squad"]]
	for i in tabs.size():
		var bt := HudScript.PixButton.new()
		bt.text = tabs[i][0]
		bt.color = Color("ffd23a") if tab == tabs[i][1] else Color("6c7480")
		bt.size = Vector2(96, 24)
		bt.position = Vector2((MID.position.x if tab != "squad" else LEFT.position.x) + i * 102, MID.position.y)
		var tb: String = tabs[i][1]
		bt.pressed.connect(func(): set_tab(tb))
		add_child(bt)
	var back := HudScript.PixButton.new()
	back.text = "BACK"
	back.sub = "ESC"
	back.color = Color("ff4d3d")
	back.size = Vector2(RIGHT.size.x, 40)
	back.position = Vector2(RIGHT.position.x, RIGHT.end.y - 40)
	back.pressed.connect(func(): Sfx.play("click"); done.emit())
	add_child(back)
	if not readonly and s().alive and tab != "squad":
		# D5: a free round at the practice range with this soldier's deck as it stands
		var pr := HudScript.PixButton.new()
		pr.text = "PRACTICE RANGE  (T)"
		pr.color = Color("62d26f")
		pr.size = Vector2(RIGHT.size.x, 28)
		pr.position = Vector2(RIGHT.position.x, RIGHT.end.y - 84)
		pr.pressed.connect(practice)
		add_child(pr)
	match tab:
		"deck":
			build_deck()
		"gear":
			build_gear()

func practice() -> void:
	var m := get_tree().current_scene
	if m != null and m.has_method("start_practice"):
		Sfx.play("start")
		m.start_practice(idx)

func small_btn(label: String, x: float, y: float, on: bool, fn: Callable, w := -1.0) -> float:
	var bt := HudScript.PixButton.new()
	bt.text = label
	bt.color = Color("53d4e2") if on else Color("4a5058")
	bt.size = Vector2(w if w > 0 else Art.text_width(label, 8) + 16, 20)
	bt.position = Vector2(x, y)
	bt.pressed.connect(fn)
	add_child(bt)
	return x + bt.size.x + 4

# ---------------------------------------------------------------- deck tab
func deck_list() -> Array:
	var me := s()
	var out: Array = me.deck.filter(func(c):
		match filt:
			"polish": return Services.polish_info(me, c).line != ""
			"mod": return Services.gunsmith_info(me, c).line != ""
			"fuse": return Services.fuse_group(me, c).size() >= 2 or Services.evolve_rule(c).size() > 0
			"burn": return Services.burn_info(me, c).line != ""
		return true)
	var key := func(c) -> Array:
		var cd := Data.card(c)
		match sort:
			"type": return [cd.type, int(cd.cost), cd.name]
			"rarity": return [-Data.tier_of(c), int(cd.cost), cd.name]
		return [int(cd.cost), cd.type, cd.name]
	out.sort_custom(func(a, b):
		var ka: Array = key.call(a)
		var kb: Array = key.call(b)
		for i in ka.size():
			if ka[i] != kb[i]:
				return ka[i] < kb[i]
		return a.id < b.id)
	return out

func build_deck() -> void:
	var me := s()
	var y := MID.position.y + 30
	var x := MID.position.x
	x = small_btn("SORT: " + sort.to_upper(), x, y, true, func():
		sort = {"cost": "type", "type": "rarity", "rarity": "cost"}[sort]
		page = 0
		build(), 112)
	for f in [["ALL", ""], ["POLISH", "polish"], ["MOD", "mod"], ["FUSE", "fuse"], ["BURN", "burn"]]:
		var fv: String = f[1]
		x = small_btn(f[0], x, y, filt == fv, func(): filt = fv; page = 0; build())
	x = small_btn("UPGRADED", x, y, show_up, func(): show_up = not show_up; build())
	var list := deck_list()
	var pages := maxi(1, ceili(list.size() / float(PER_PAGE)))
	page = clampi(page, 0, pages - 1)
	if pages > 1:
		small_btn("<", MID.end.x - 64, MID.position.y + 2, true, func(): page = posmod(page - 1, pages); build(), 28)
		small_btn(">", MID.end.x - 30, MID.position.y + 2, true, func(): page = (page + 1) % pages; build(), 28)
	var shown: Array = list.slice(page * PER_PAGE, (page + 1) * PER_PAGE)
	for i in shown.size():
		var c: Dictionary = shown[i]
		var cv := CardView.new()
		cv.opt = Services.next_tier(c) if show_up and Run.upgradable(c) and not Services.is_od(c) else c
		cv.size = Vector2(CW, CH)
		cv.position = Vector2(MID.position.x + (i % 7) * (CW + 5), MID.position.y + 66 + (i / 7) * (CH + 24))  # room for the rarity label and a fuse badge
		cv.selected = sel == c
		cv.corner = Services.src_tag(c)
		var g := Services.fuse_group(me, c).size()
		if Services.evolve_info(me, c).ok:
			cv.badge = "EVO"
		elif g >= 2:
			cv.badge = "%d/3" % mini(g, 3)
		cv.pressed.connect(func(): Sfx.play("click"); sel = null if sel == c else c; build())
		add_child(cv)
	if sel != null and not me.deck.has(sel):
		sel = null
	if sel != null and not readonly:
		var acts := Services.card_actions(me, sel)
		var cols := {"polish": Color("53d4e2"), "gunsmith": Color("53d4e2"), "fuse": Color("b48cff"), "evolve": Color("b48cff"), "burn": Color("ff4d3d")}
		var tw := (MID.size.x - 4 * 5) / 5.0
		for i in acts.size():
			var a: Dictionary = acts[i]
			var tile := HubUI.ActionTile.new()
			tile.title = a.name
			tile.cost = a.cost
			tile.line = a.line
			tile.why = a.why
			tile.ok = a.ok
			tile.color = cols[a.id]
			tile.size = Vector2(tw, 86)
			tile.position = Vector2(MID.position.x + i * (tw + 5), MID.end.y - 86)
			var id: String = a.id
			tile.pressed.connect(func(): open_preview(id))
			add_child(tile)

# ---------------------------------------------------------------- before / after previews
func close_modal() -> void:
	if modal != null:
		modal.queue_free()
		modal = null
	mod_pick = -1
	show_deck_cards(true)

func show_deck_cards(on: bool) -> void:
	## The deck's own cards hide under a preview: through the dimmer they read as part of it.
	for c in get_children():
		if c is CardView:
			c.visible = on

func preview_card(opt: Dictionary, pos: Vector2, big := true) -> CardView:
	var cv := CardView.new()
	cv.opt = opt
	cv.size = Vector2(118, 160) if big else Vector2(84, 116)
	cv.position = pos
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(cv)
	return cv

func modal_button(label: String, col: Color, x: float, fn: Callable, disabled := false) -> HudScript.PixButton:
	var bt := HudScript.PixButton.new()
	bt.text = label
	bt.color = col
	bt.size = Vector2(220, 36)
	bt.position = Vector2(x, 440)
	bt.disabled = disabled
	bt.pressed.connect(fn)
	modal.add_child(bt)
	return bt

func open_preview(id: String) -> void:
	## Q2: shows exactly what the service does to this card; nothing is paid until CONFIRM.
	var me := s()
	var c: Dictionary = sel
	var cd := Data.card(c)
	modal = Overlay.new()
	add_child(modal)
	show_deck_cards(false)
	var ov: Overlay = modal
	var go: Callable
	var cost := 0
	match id:
		"polish":
			var n := Services.next_tier(c)
			cost = Services.price(Services.POLISH)
			ov.title = "POLISH %s?" % cd.name.to_upper()
			ov.sub = "%s's deck. Cost stays %d." % [me.def.name, int(cd.cost)]
			preview_card(c, Vector2(300, 150))
			preview_card(n, Vector2(542, 150))
			ov.arrow = true
			ov.lines = [Services.change_line(c, n), "%s > %s" % [Data.tier_name(Data.tier_of(c)), Data.tier_name(n.tier)]]
			go = func():
				if Services.polish(c):
					say("%s is now %s." % [cd.name, Data.tier_name(Data.tier_of(c)).capitalize()])
		"burn":
			cost = Services.price(Services.BURN)
			ov.title = "BURN %s?" % cd.name.to_upper()
			ov.sub = "It leaves %s's deck for the rest of the run." % me.def.name
			preview_card(c, Vector2(421, 150))
			ov.lines = ["Deck %d > %d" % [me.deck.size(), me.deck.size() - 1], "Everything else comes up more often."]
			go = func():
				if Services.burn(me, c):
					sel = null
					say("%s burned. %s's deck is down to %d." % [cd.name, me.def.name, me.deck.size()])
		"fuse":
			var g := Services.fuse_group(me, c).slice(0, 3)
			var n := Services.next_tier(c)
			ov.title = "FUSE 3 %s?" % cd.name.to_upper()
			ov.sub = "Three %s copies become one %s card. Free." % [Data.tier_name(Data.tier_of(c)).capitalize(), Data.tier_name(n.tier).capitalize()]
			for i in 3:
				preview_card(g[i], Vector2(200 + i * 92, 166), false)
			preview_card(n, Vector2(600, 150))
			ov.arrow = true
			ov.arrow_x = 530
			ov.lines = [Services.change_line(c, n), "Deck %d > %d. Mods on the copies carry over." % [me.deck.size(), me.deck.size() - 2]]
			go = func():
				var out := Services.fuse(me, c)
				if not out.is_empty():
					sel = out
					Sfx.play("levelup")
					say("Fused into %s %s." % [Data.tier_name(Data.tier_of(out)).capitalize(), Data.card(out).name])
		"evolve":
			var r := Services.evolve_rule(c)
			var n := c.duplicate(true)
			n.key = r.into
			n.erase("mods")
			ov.title = "EVOLVE %s?" % cd.name.to_upper()
			ov.sub = "The %s kit turns it into a new weapon. Free, and the kit stays." % Data.ITEMS[r.kit].name
			preview_card(c, Vector2(300, 150))
			preview_card(n, Vector2(542, 150))
			ov.arrow = true
			ov.lines = ["Becomes %s." % Data.CARDS[r.into].name, "Rarity stays %s." % Data.tier_name(Data.tier_of(c)).capitalize()]
			go = func():
				if Services.evolve(me, c):
					Sfx.play("levelup")
					say("%s evolved into %s!" % [cd.name, Data.CARDS[r.into].name])
		"gunsmith":
			cost = Services.price(Data.MOD_PRICE)
			var mods := Data.mod_options(c)
			ov.title = "GUNSMITH: MOD %s" % cd.name.to_upper()
			ov.sub = "Pick a mod. Each card holds %d; this is mod %d." % [Data.MAX_MODS, c.get("mods", []).size() + 1]
			var n := mini(mods.size(), 6)
			var x0 := 480 - (n * 118 + (n - 1) * 10) / 2.0
			for i in n:
				var m: Dictionary = mods[i]
				var mc := c.duplicate(true)
				mc["mods"] = c.get("mods", []) + [m.id]
				var cv := preview_card(mc, Vector2(x0 + i * 128, 150))
				cv.mouse_filter = Control.MOUSE_FILTER_STOP
				cv.label_top = m.name.to_upper()
				var k := i
				cv.pressed.connect(func():
					Sfx.play("select")
					mod_pick = k
					for o in modal.get_children():
						if o is CardView:
							o.selected = o == cv
							o.position.y = 138.0 if o == cv else 150.0
					ov.lines = [m.text]
					ov.confirm.disabled = false)
			ov.lines = ["Click a card to pick its mod."]
			go = func():
				if mod_pick >= 0 and Services.gunsmith(c, mods[mod_pick].id):
					say("%s gets %s." % [cd.name, mods[mod_pick].name])
	ov.confirm = modal_button("CONFIRM" if cost == 0 else "CONFIRM %d$" % cost, Color("62d26f"), 250, func():
		go.call()
		close_modal()
		build(), Run.scrip < cost or id == "gunsmith")
	modal_button("BACK", Color("9aa2ae"), 490, close_modal)

class Overlay extends Control:
	## Dims the Dossier behind a before/after preview.
	var title := ""
	var sub := ""
	var lines: Array = []
	var arrow := false
	var arrow_x := 450.0
	var confirm = null
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			get_parent().close_modal()
		accept_event()
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 540), Color(0.02, 0.02, 0.04, 0.9))
		Art.text(self, title, Vector2(480, 80), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 2)
		Art.text(self, sub, Vector2(480, 106), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
		if arrow:
			Art.text(self, ">>", Vector2(arrow_x + 30, 240), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 2)
		var y := 360.0
		for i in lines.size():
			Art.text(self, lines[i], Vector2(480, y), 16, Color("62d26f") if i == 0 else Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
			y += 20

# ---------------------------------------------------------------- gear tab
func gear_item():
	match gear_pick.get("where", ""):
		"stash":
			return Run.stash[gear_pick.i] if gear_pick.i < Run.stash.size() else null
		"belt":
			return Run.belt[gear_pick.i] if gear_pick.i < Run.belt.size() else null
		"equip":
			return s().equip[gear_pick.slot]
	return null

func gear_select(p: Dictionary) -> void:
	var me := s()
	if not readonly and me.alive:
		# an empty (or full) slot picked, then gear that fits it, or the other way round: equip it
		var held = gear_item()
		var it = gear_at(p)
		if gear_pick.get("where", "") == "equip" and p.where == "stash" and ArmoryScript.fits(it, gear_pick.slot):
			equip_into(it, gear_pick.slot)
			return
		if gear_pick.get("where", "") == "stash" and p.where == "equip" and ArmoryScript.fits(held, p.slot):
			equip_into(held, p.slot)
			return
	Sfx.play("click")
	gear_pick = {} if gear_pick.hash() == p.hash() else p
	build()

func gear_at(p: Dictionary):
	var keep := gear_pick
	gear_pick = p
	var it = gear_item()
	gear_pick = keep
	return it

func equip_into(it: Dictionary, slot: String) -> void:
	var me := s()
	var delta := ArmoryScript.card_delta(it, me.equip[slot])
	Run.belt.erase(it)
	Run.equip(me, it, slot)
	Sfx.play("buy")
	say("%s equipped %s: %s." % [me.def.name, Data.item_name(it), ArmoryScript.deck_words(delta)])
	gear_pick = {}
	build()

func gear_fit(it, where: String, slot := "") -> int:
	## Lights the stash gear that fits a picked slot, or the slots a picked item fits.
	if readonly or not s().alive or gear_pick.is_empty():
		return 0
	var held = gear_item()
	if gear_pick.where == "equip" and where == "stash" and it != null:
		return 1 if ArmoryScript.fits(it, gear_pick.slot) else -1
	if gear_pick.where == "stash" and where == "equip" and held != null:
		return 1 if ArmoryScript.fits(held, slot) else -1
	return 0

func build_gear() -> void:
	var me := s()
	for k in SLOTS.size():
		var slot: String = SLOTS[k]
		var tile := ArmoryScript.ItemTile.new()
		tile.item = me.equip[slot]
		tile.tw = 128
		tile.empty_label = Data.SLOT_NAMES[Data.slot_group(slot)]
		tile.clickable_empty = not readonly
		tile.position = Vector2(MID.position.x + (k % 2) * 136, MID.position.y + 54 + (k / 2) * 52)
		tile.selected = gear_pick.get("where", "") == "equip" and gear_pick.slot == slot
		tile.fit = gear_fit(tile.item, "equip", slot)
		tile.pressed.connect(func(): gear_select({"where": "equip", "slot": slot}))
		add_child(tile)
	for i in maxi(Data.STASH_MAX, Run.stash.size()):
		var tile := ArmoryScript.ItemTile.new()
		tile.item = Run.stash[i] if i < Run.stash.size() else null
		tile.empty_label = "EMPTY"
		tile.position = Vector2(MID.position.x + (i % 4) * 110, MID.position.y + 190 + (i / 4) * 50)
		tile.selected = gear_pick.get("where", "") == "stash" and gear_pick.i == i
		tile.fit = gear_fit(tile.item, "stash")
		var k := i
		tile.pressed.connect(func(): gear_select({"where": "stash", "i": k}))
		add_child(tile)
	for i in Run.belt_max():
		var tile := ArmoryScript.ItemTile.new()
		tile.item = Run.belt[i] if i < Run.belt.size() else null
		tile.empty_label = "BELT"
		tile.position = Vector2(MID.position.x + i * 110, MID.position.y + 316)
		tile.selected = gear_pick.get("where", "") == "belt" and gear_pick.i == i
		var k := i
		tile.pressed.connect(func(): gear_select({"where": "belt", "i": k}))
		add_child(tile)
	var it = gear_item()
	if it == null:
		return
	var cv := CardView.new()
	cv.opt = Run.item_opt(it)
	cv.size = Vector2(110, 152)
	cv.position = Vector2(MID.end.x - 112, MID.position.y + 28)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cv)
	if readonly or not me.alive:
		return
	var where: String = gear_pick.where
	var bt := HudScript.PixButton.new()
	bt.size = Vector2(240, 34)
	bt.position = Vector2(MID.position.x, MID.end.y - 34)
	if where == "equip":
		bt.text = "UNEQUIP"
		bt.color = Color("9aa2ae")
		bt.pressed.connect(func():
			var delta := ArmoryScript.card_delta(null, it)
			Run.unequip(me, gear_pick.slot)
			Sfx.play("click")
			say("%s took off %s: %s." % [me.def.name, Data.item_name(it), ArmoryScript.deck_words(delta)])
			gear_pick = {}
			build())
	elif Data.ITEMS[it.id].slot != "belt":
		bt.text = "EQUIP ON %s" % me.def.name
		bt.color = Color("53d4e2")
		bt.pressed.connect(func(): equip_into(it, Run.slot_for(me, it)))
	else:
		return
	add_child(bt)

func equip_preview(it: Dictionary) -> Array:
	## S4: what equipping this item would change for the open soldier, as [text, good] lines.
	return ArmoryScript.equip_changes(s(), it)

# ---------------------------------------------------------------- reading the soldier
func stats() -> Array:
	var me := s()
	var gb := Run.gear_bonus(me)
	var hand: int = 4 + me.bonus.hand + (1 if me.perks.has("fieldkit") else 0) + (1 if Run.implanted(me, "thirdarm") else 0)
	var e1: int = me.bonus.energy1 + int(gb.get("energy1", 0))
	return [
		["MOVE", Data.meters(me.def.spd + me.bonus.move + int(gb.get("move", 0)))],
		["DODGE", "%d%%" % (me.def.dodge + me.bonus.dodge + int(gb.get("dodge", 0)))],
		["HAND", "%d cards" % hand],
		["ENERGY", "3 a turn" + (" +%d first" % e1 if e1 > 0 else "")],
		["XP", "%d / %d" % [me.xp, Run.xp_for_next(me)]],
	] + ([["RANK", Data.RANKS[Run.rank(me)].name], ["OPS / KILLS", "%d / %d" % [int(Run.svc(me).ops), int(Run.svc(me).kills)]]] if Run.campaign() else [])

func trait_line() -> Array:
	return s().def.trait

func recruit_trait() -> Dictionary:
	var me := s()
	for tr in Data.RECRUIT_TRAITS:
		if tr.id == str(me.get("trait", "")):
			return tr
	return {}

func chains() -> Array:
	## Each archetype's signature chain and the cards it still needs in this deck.
	var me := s()
	var have: Array = me.deck.map(func(c): return Data.CARDS[c.key].name)
	var out: Array = []
	for b in Data.BRANCHES.get(me.key, []):
		var need: Array = []
		for k in Data.CARDS:
			var nm: String = Data.CARDS[k].name
			if nm.length() > 3 and b.chain.text.contains(nm) and not have.has(nm) and not need.has(nm):
				need.append(nm)
		out.append({"name": b.chain.name, "branch": b.name, "need": need, "text": b.chain.text})
	return out

func _process(_d: float) -> void:
	t += 1
	if msg_t > 0:
		msg_t -= 1
	queue_redraw()

func panel(r: Rect2) -> void:
	draw_rect(r, Color(0.05, 0.035, 0.03))
	draw_rect(r.grow(-1), Color("23272d"))

func head(txt: String, p: Vector2, col := Color("ffd23a")) -> void:
	Art.text(self, txt, p, 8, col)

func para(txt: String, p: Vector2, w: float, col := Color("e8dcc2"), max_lines := 99) -> float:
	var y := p.y
	var n := 0
	for ln in CardView.wrap_text(txt, w, 16):
		if n >= max_lines:
			break
		Art.text(self, ln, Vector2(p.x, y), 16, col, HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		y += 12
		n += 1
	return y

func _draw() -> void:
	Tip.clear(self)
	draw_rect(Rect2(0, 0, 960, 540), Color("1a1d22"))
	for y in range(0, 540, 24):
		for x in range(0, 960, 24):
			draw_texture_rect(Art.tex.ui_panel, Rect2(x, y, 24, 24), false, Color(0.45, 0.45, 0.5))
	for x in range(0, 960, 32):
		draw_texture_rect(Art.tex.ui_hazard, Rect2(x, 0, 32, 8), false)
	var me := s()
	Art.text(self, "DOSSIER", Vector2(16, 32), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
	Art.text(self, "Q / E  NEXT SOLDIER    TAB  NEXT TAB" + ("    READ-ONLY IN THE FIELD" if readonly else ""), Vector2(150, 30), 8, Color("6c7480"))
	var sc := "%d SCRIP" % Run.scrip
	draw_texture_rect(Art.tex.ic_coin, Rect2(944 - Art.text_width(sc, 16) - 22, 16, 16, 16), false)
	Art.text(self, sc, Vector2(944, 32), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT, 2)
	if tab == "squad":
		draw_squad()
		return
	draw_left(me)
	draw_right(me)
	match tab:
		"sheet":
			draw_sheet(me)
		"gear":
			draw_gear(me)
		"deck":
			draw_deck(me)
	if msg_t > 0 and modal == null:
		var w := Art.text_width(msg, 16, true) + 20
		var my := MID.end.y - 112 if tab == "deck" else MID.end.y - 20
		draw_rect(Rect2(MID.get_center().x - w / 2, my, w, 20), Color(0.05, 0.035, 0.03, 0.94))
		Art.text(self, msg, Vector2(MID.get_center().x, my + 15), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 0, true)

func draw_left(me: Dictionary) -> void:
	panel(LEFT)
	var pr := Rect2(LEFT.position + Vector2(8, 8), Vector2(LEFT.size.x - 16, 108))
	draw_rect(pr, Color("15181c"))
	draw_rect(Rect2(pr.position.x, pr.end.y - 10, pr.size.x, 10), Color("2e3a24"))
	Art.draw_char(self, Art.look_sheet(me), "idle" if me.alive else "die", (t / 12) % 4 if me.alive else 4, Vector2(pr.get_center().x, pr.end.y - 10), 1, false, 0, 1.0, 0, true, 2.2)
	var x := LEFT.position.x + 10
	var y := pr.end.y + 18
	Art.text(self, me.def.name, Vector2(x, y), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 2)
	Art.text(self, "LV%d" % me.lvl, Vector2(LEFT.end.x - 10, y), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT)
	y += 14
	Art.text(self, Run.title_of(me), Vector2(x, y), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
	if me.alive:
		Art.draw_tags(self, Vector2(LEFT.end.x - 24, y - 10), me.tags)
		y += 10
		var mx := Run.eff_max_hp(me)
		draw_rect(Rect2(x, y, LEFT.size.x - 20, 8), Color(0.05, 0.035, 0.03))
		draw_rect(Rect2(x + 1, y + 1, (LEFT.size.x - 22) * clampf(float(me.hp) / mx, 0, 1), 6), Color("62d26f") if me.hp > mx * 0.3 else Color("ff4d3d"))
		y += 22
		Art.text(self, "HP %d / %d" % [me.hp, mx], Vector2(x, y), 8, Color("e8dcc2"))
	else:
		y += 22
		Art.text(self, "KILLED IN ACTION", Vector2(x, y), 8, Color("ff4d3d"))
	y += 16
	for row in stats():
		Art.text(self, row[0], Vector2(x, y), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		Art.text(self, row[1], Vector2(LEFT.end.x - 10, y), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 0, true)
		y += 13
	y += 8
	var tr := trait_line()
	head(tr[0].to_upper(), Vector2(x, y), Color("62d26f"))
	y = para(tr[1], Vector2(x, y + 14), LEFT.size.x - 20, Color("e8dcc2"), 3)
	y += 6
	head("IMPLANTS", Vector2(x, y))
	y += 14
	var imp := Run.implants_of(me)
	if imp.is_empty():
		y = para("None. The Doc's Lab installs them.", Vector2(x, y), LEFT.size.x - 20, Color("6c7480"), 2)
	for id in imp:
		y = para("%s: %s" % [Data.SURGERIES[id].name.capitalize(), Data.SURGERIES[id].up], Vector2(x, y), LEFT.size.x - 20, Color("9df25c"), 2)

func draw_right(me: Dictionary) -> void:
	panel(Rect2(RIGHT.position, RIGHT.size - Vector2(0, 46)))
	var x := RIGHT.position.x + 10
	var y := RIGHT.position.y + 16
	var w := RIGHT.size.x - 20
	head("COST CURVE", Vector2(x, y))
	var counts := [0, 0, 0, 0]
	var types := {}
	for c in me.deck:
		var cd := Data.card(c)
		counts[clampi(int(cd.cost), 0, 3)] += 1
		types[cd.type] = types.get(cd.type, 0) + 1
	var top: int = maxi(1, counts.max())
	var bw := (w - 18) / 4.0
	for i in 4:
		var bh: float = 46.0 * counts[i] / top
		var bx := x + i * (bw + 6)
		draw_rect(Rect2(bx, y + 62 - bh, bw, bh), Color(0.05, 0.035, 0.03))
		draw_rect(Rect2(bx + 1, y + 63 - bh, bw - 2, bh - 1), Color("ffd23a"))
		Art.text(self, str(counts[i]), Vector2(bx + bw / 2, y + 58 - bh), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		Art.text(self, ["0", "1", "2", "3+"][i], Vector2(bx + bw / 2, y + 76), 8, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER)
	draw_line(Vector2(x, y + 63), Vector2(x + w, y + 63), Color("4a505a"), 1.0)
	y += 96
	head("CARD TYPES", Vector2(x, y))
	y += 8
	var total := maxf(1.0, me.deck.size())
	var px := x
	var keys: Array = types.keys()
	keys.sort()
	for k in keys:
		var segw: float = w * types[k] / total
		draw_rect(Rect2(px, y, segw, 10), Data.TYPES[k].c)
		px += segw
	draw_rect(Rect2(x, y, w, 10), Color(0.05, 0.035, 0.03), false, 1.0)
	y += 24
	var lx := x
	for k in keys:
		var lab := "%s %d" % [k, types[k]]
		if lx + Art.text_width(lab, 16, true) > x + w:
			lx = x
			y += 12
		Art.text(self, lab, Vector2(lx, y), 16, Data.TYPES[k].c, HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		lx += Art.text_width(lab, 16, true) + 8
	y += 18
	if tab == "deck" and sel != null:
		head("THIS CARD", Vector2(x, y))
		y += 14
		var c: Dictionary = sel
		var bits: Array = []
		if c.has("nick"):
			bits.append("\"%s\"" % c.nick)
		var src := Services.source(me, c)
		if src != "":
			bits.append(src.capitalize() if not src.begins_with("from") else src.capitalize())
		bits.append("Kills this run: %d." % int(c.get("kills", 0)) if c.get("kills", 0) else "No kills yet.")
		if c.get("mods", []).size():
			bits.append("Mods: " + ", ".join(Data.card(c).get("mod_names", [])))
		var fit := Services.branch_fit(me, c.key)
		if fit != "":
			bits.append("Feeds %s." % fit)
		var g := Services.fuse_group(me, c).size()
		if g >= 2 and g < 3:
			bits.append("Fusion: %d of 3 copies." % g)
		for b in bits:
			y = para(b, Vector2(x, y), w, Color("e8dcc2"), 3)
		y += 8
	head("CHAINS", Vector2(x, y))
	y += 14
	for ch in chains():
		if y > RIGHT.end.y - (110 if not readonly else 70):
			break
		var ready: bool = ch.need.is_empty()
		Art.text(self, ch.name, Vector2(x, y), 8, Color("b48cff") if ready else Color("6c7480"))
		Tip.zone(self, Rect2(x - 2, y - 10, w + 4, 28), "CHAIN " + ch.name, "%s chain. %s" % [ch.branch, ch.text] + ("" if ready else " Needs %s in the deck." % ", ".join(ch.need)), Color("b48cff"))
		y += 4
		y = para("ready" if ready else "needs " + ", ".join(ch.need), Vector2(x, y + 10), w, Color("e8dcc2") if ready else Color("8a9099"), 1)
		y += 4

func draw_sheet(me: Dictionary) -> void:
	## D1: the four archetype branches, how far along each is, what's next and its chain.
	var x := MID.position.x
	var y := MID.position.y + 44
	head("ARCHETYPES", Vector2(x, y))
	Art.text(self, "Level-ups offer the next perk in each branch. A capstone swaps the Overdrive.", Vector2(x + 100, y), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
	y += 8
	for b in Data.BRANCHES.get(me.key, []):
		var n := 0
		for p in b.perks:
			if me.perks.has(p.id):
				n += 1
		var r := Rect2(x, y, MID.size.x, 66)
		draw_rect(r, Color(0.05, 0.035, 0.03))
		draw_rect(r.grow(-1), Color("2a2e34") if n > 0 else Color("202328"))
		if n > 0:
			draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(3, r.size.y - 2)), Color("ffd23a"))
		Art.text(self, b.name.to_upper(), Vector2(x + 10, y + 15), 8, Color("ffd23a") if n > 0 else Color("9aa2ae"))
		for k in 3:
			var p: Dictionary = b.perks[k]
			var on: bool = me.perks.has(p.id)
			var px := x + 10 + k * 176
			draw_rect(Rect2(px, y + 22, 8, 8), Color(0.05, 0.035, 0.03))
			draw_rect(Rect2(px + 1, y + 23, 6, 6), Color("ffd23a") if on else Color("3a3f45"))
			Art.text(self, p.name, Vector2(px + 12, y + 31), 16, Color.WHITE if on else (Color("e8dcc2") if k == n else Color("6c7480")), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		var nxt := "COMPLETE. Overdrive: %s." % Data.CARDS[b.od].name if n >= 3 else "Next: %s. %s" % [b.perks[n].name, b.perks[n].text]
		Art.text(self, nxt, Vector2(x + 10, y + 46), 16, Color("e8dcc2") if n > 0 else Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		Art.text(self, "CHAIN %s: %s" % [b.chain.name, b.chain.text], Vector2(x + 10, y + 60), 16, Color("b48cff"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		y += 70
	y += 10
	head("OVERDRIVE", Vector2(x, y))
	var od: Dictionary = Data.CARDS[Run.od_key(me)]
	para("%s: %s" % [od.name, od.text], Vector2(x + 90, y), MID.size.x - 90, Color("ffb23e"), 2)
	y += 26
	head("DUOS", Vector2(x, y))
	# the duos this squad can pull off, hover one for what it does; the class's others fold into one word
	var duos: Array = []
	var away: Array = []
	for d in Data.DUOS:
		if d.pair.has(me.key):
			var other: String = d.pair[0] if d.pair[1] == me.key else d.pair[1]
			var os := Run.soldier(other)
			if os.get("alive", false):
				duos.append({"kind": "duo", "name": Data.CARDS[d.card].name.to_upper(), "prog": "+ " + os.def.name, "done": true, "text": Run.duo_tip(d)})
			else:
				away.append("%s with %s" % [Data.CARDS[d.card].name, other.to_upper()])
	if away.size():
		duos.append({"kind": "duo", "name": "+%d" % away.size(), "prog": "", "done": false, "title": "OTHER DUOS",
			"text": "Recruit the partner to unlock: %s." % ", ".join(away)})
	if duos.is_empty():
		para("None for this class.", Vector2(x + 90, y), MID.size.x - 90, Color("9aa2ae"), 1)
	y = maxf(y + 30, Tip.chips(self, duos, Vector2(x + 90, y + 1), MID.size.x - 90) + 6)
	var rt := recruit_trait()
	if not rt.is_empty():
		head("RECRUIT", Vector2(x, y))
		Art.text(self, "%s: %s" % [rt.name, rt.text], Vector2(x + 90, y + 1), 16, Color("62d26f"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		y += 16
	if me.has("prestige"):
		var pt: Dictionary = Data.PRESTIGE_TRAITS[int(me.get("ptrait", 0))]
		head("PRESTIGE", Vector2(x, y))
		Art.text(self, "%s. %s: %s" % [Run.title_of(me), pt.name, pt.text], Vector2(x + 90, y + 1), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		y += 16
	if me.get("xtrain", []).size():
		head("CROSS", Vector2(x, y))
		Art.text(self, "Cross-trained in %s." % ", ".join(me.xtrain.map(func(k): return Data.CARDS[k].name)), Vector2(x + 90, y + 1), 16, Color("53d4e2"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		y += 16
	if Run.campaign():
		# C5: the service record instead of the bio
		var sv := Run.svc(me)
		head("SERVICE", Vector2(x, y + 4))
		var med: Array = sv.medals.map(func(m): return "%s (%s)" % [Data.MEDALS[m].name.capitalize(), Data.MEDALS[m].up])
		para("%s. %d ops, %d kills, down %d times. %s%s" % [Data.RANKS[Run.rank(me)].name.capitalize(), int(sv.ops), int(sv.kills), int(sv.downs),
			("Medals: " + ", ".join(med) + ". ") if med.size() else "No medals yet. ", ("Carries %s's cards." % me.legacy_from) if me.has("legacy_from") else ""], Vector2(x + 90, y + 4), MID.size.x - 90, Color("e8dcc2"), 3)
		return
	para(me.def.bio, Vector2(x, y + 4), MID.size.x, Color("9aa2ae"), 2)

func draw_deck(me: Dictionary) -> void:
	if me.deck.is_empty():
		Art.text(self, "No cards.", MID.get_center(), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
	var list := deck_list()
	if list.is_empty() and filt != "":
		Art.text(self, "No cards match this filter.", Vector2(MID.get_center().x, MID.position.y + 140), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
	var pages := maxi(1, ceili(list.size() / float(PER_PAGE)))
	if pages > 1:
		Art.text(self, "PAGE %d/%d" % [page + 1, pages], Vector2(MID.end.x - 70, MID.position.y + 16), 8, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_RIGHT)
	if readonly:
		return
	if sel == null:
		var hint := "Pick a card to Polish, Mod, Fuse, Evolve or Burn it. You see the result before you pay."
		draw_rect(Rect2(MID.position.x, MID.end.y - 86, MID.size.x, 86), Color(0.05, 0.035, 0.03, 0.7))
		# wrapped to the middle panel so it never runs into the side column's buttons
		var hl := CardView.wrap_text(hint, MID.size.x - 24, 16)
		for i in hl.size():
			Art.text(self, hl[i], Vector2(MID.get_center().x, MID.end.y - 38 - (hl.size() - 1) * 7 + i * 14), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER, 0, true)

func draw_gear(me: Dictionary) -> void:
	var x := MID.position.x
	head("%s'S SLOTS" % me.def.name, Vector2(x, MID.position.y + 46))
	head("STASH %d/%d  (SHARED)" % [Run.stash.size(), Data.STASH_MAX], Vector2(x, MID.position.y + 182), Color("ffb23e"))
	head("BELT  (SHARED, USE ANY TIME)", Vector2(x, MID.position.y + 308), Color("62d26f"))
	var it = gear_item()
	# gear sets and kit evolutions, each one hoverable
	Tip.chips(self, Run.synergies(me).filter(func(sy): return sy.kind != "duo"), Vector2(x + 280, MID.position.y + 46), MID.size.x - 280)
	var gb := Data.stat_lines(Run.gear_bonus(me))
	var y := MID.position.y + 380
	if not readonly and gear_pick.get("where", "") == "equip":
		# a picked slot: what fits it, and what the gear in it puts in the deck
		var cx := x + 280
		var cy := MID.position.y + 154
		var n: int = Run.stash.filter(func(o): return ArmoryScript.fits(o, gear_pick.slot)).size()
		var word: String = Data.SLOT_NAMES[Data.slot_group(gear_pick.slot)]
		if it != null:
			var cards := ArmoryScript.card_delta(it, null)
			para("In the deck: %s. Unequip and they leave." % ArmoryScript.deck_words(cards).replace("+", "") if cards.size() else "Adds no cards, stats only.", Vector2(x + 280, MID.position.y + 92), 140, Color("e8dcc2"), 4)
		Art.text(self, ("%d in the stash fit%s this %s slot: click one." % [n, "" if n > 1 else "s", word]) if n > 0 else "Nothing in the stash fits a %s slot." % word,
			Vector2(cx - 280, cy + 8), 16, Color("62d26f") if n > 0 else Color("e8a070"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
	if it == null:
		head("FROM GEAR AND IMPLANTS", Vector2(x, y))
		para(", ".join(gb) if gb.size() else "Nothing equipped yet.", Vector2(x, y + 14), MID.size.x, Color("e8dcc2"), 3)
		return
	if gear_pick.where in ["stash", "belt"] and Data.ITEMS[it.id].slot != "belt" and not readonly:
		var lines := equip_preview(it)
		var cx := x + 280
		var cy := MID.position.y + 76
		head("IF %s EQUIPS IT" % me.def.name, Vector2(cx, cy))
		cy += 14
		for ln in lines:
			if cy > MID.position.y + 180:
				break
			Art.text(self, ln[0], Vector2(cx, cy), 16, Color("62d26f") if ln[1] else Color("e8a070"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
			cy += 12

# ---------------------------------------------------------------- all decks (D3)
const SQUAD := Rect2(16, 122, 928, 362)

func squad_col(i: int) -> Rect2:
	var n := maxi(4, Run.soldiers.size())  # X2: room for a freed fifth soldier
	var w := (SQUAD.size.x - (n - 1) * 8) / n
	return Rect2(SQUAD.position.x + i * (w + 8), SQUAD.position.y, w, SQUAD.size.y)

func deck_rows(me: Dictionary) -> Array:
	## The deck as a compact list: one row per card and rarity, copies counted.
	var rows := {}
	for c in me.deck:
		var k := "%s:%d:%s" % [c.key, Data.tier_of(c), ",".join(c.get("mods", []))]
		if not rows.has(k):
			rows[k] = {"c": c, "n": 0}
		rows[k].n += 1
	var out: Array = rows.values()
	out.sort_custom(func(a, b):
		var ca := Data.card(a.c)
		var cb := Data.card(b.c)
		if int(ca.cost) != int(cb.cost):
			return int(ca.cost) < int(cb.cost)
		return ca.name < cb.name)
	return out

func _gui_input(ev: InputEvent) -> void:
	if tab == "squad" and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		for i in Run.soldiers.size():
			if squad_col(i).has_point(ev.position):
				accept_event()
				tab = "deck"
				idx = -1
				switch_to(i)
				return

func draw_squad() -> void:
	Art.text(self, "Every deck at once. Click a soldier to open their deck.", Vector2(SQUAD.position.x + 420, MID.position.y + 16), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
	for i in Run.soldiers.size():
		var me: Dictionary = Run.soldiers[i]
		var r := squad_col(i)
		panel(r)
		var x := r.position.x + 8
		var y := r.position.y + 16
		Art.text(self, me.def.name, Vector2(x, y), 8, Color.WHITE if me.alive else Color("8a7a7a"))
		Art.text(self, "%d CARDS" % me.deck.size(), Vector2(r.end.x - 8, y), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT)
		if not me.alive:
			Art.text(self, "KILLED IN ACTION", Vector2(x, y + 16), 8, Color("ff4d3d"))
			continue
		var cost := 0.0
		for c in me.deck:
			cost += int(Data.card(c).cost)
		Art.text(self, Run.title_of(me).to_upper(), Vector2(x, y + 12), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		Art.text(self, "AVG COST %.1f" % (cost / maxf(1.0, me.deck.size())), Vector2(r.end.x - 8, y + 12), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_RIGHT, 0, true)
		y += 30
		var rows := deck_rows(me)
		var max_rows := 19
		for k in mini(rows.size(), max_rows):
			var row: Dictionary = rows[k]
			var cd := Data.card(row.c)
			var tc := Data.tier_color(Data.tier_of(row.c))
			draw_rect(Rect2(x, y - 8, 4, 9), tc)
			Art.text(self, str(int(cd.cost)), Vector2(x + 8, y), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
			var nm: String = ("%dx " % row.n if row.n > 1 else "") + cd.name + (" +" if row.c.get("mods", []).size() else "")
			Art.text(self, nm, Vector2(x + 20, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
			Art.text(self, cd.type, Vector2(r.end.x - 8, y), 16, Data.TYPES[cd.type].c, HORIZONTAL_ALIGNMENT_RIGHT, 0, true)
			y += 12
		if rows.size() > max_rows:
			Art.text(self, "+%d more" % (rows.size() - max_rows), Vector2(x + 20, y), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		# what the deck is building toward: its Overdrive and duo partners
		var fy := r.end.y - 50
		var best = null
		for c in me.deck:
			if int(c.get("kills", 0)) > 0 and (best == null or c.kills > best.kills):
				best = c
		if best != null:
			Art.text(self, "TOP CARD", Vector2(x, fy - 34), 8, Color("ff7a5a"))
			Art.text(self, "%s, %d kills" % [best.get("nick", Data.card(best).name), best.kills], Vector2(x + 70, fy - 34), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		draw_line(Vector2(x, fy - 12), Vector2(r.end.x - 8, fy - 12), Color("4a505a"), 1.0)
		Art.text(self, "OVERDRIVE", Vector2(x, fy), 8, Color("ffb23e"))
		Art.text(self, Data.CARDS[Run.od_key(me)].name, Vector2(x, fy + 12), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		var duos: Array = Run.synergies(me).filter(func(sy): return sy.kind == "duo")
		Art.text(self, "DUOS", Vector2(x, fy + 28), 8, Color("b48cff"))
		if duos.is_empty():
			Art.text(self, "none in the squad", Vector2(x + 40, fy + 28), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		else:
			# just the partners' names here; the tip names the duo card
			Tip.chips(self, duos.map(func(sy): return {"kind": "duo", "name": sy.prog, "prog": "", "done": true, "title": sy.name, "text": sy.text}),
				Vector2(x + 40, fy + 28), r.end.x - 8 - x - 40)

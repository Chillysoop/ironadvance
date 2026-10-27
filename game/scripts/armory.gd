extends Control
## The Armory: four gear slots per soldier, the shared stash and the consumable belt.
## Opened from the Quartermaster (with the item shelf, selling and the gunsmith) or
## from the debrief. Click an item to select it, then use the action buttons.

signal done

const HudScript := preload("res://scripts/hud.gd")
const SLOTS := ["weapon", "armor", "kit1", "kit2"]

var shop_mode := false
var shelf: Array = []        # [{item, price, sold, mystery, black}] from the shop
var pick := {}               # current selection: {where, i, s, slot}
var msg := ""
var msg_t := 0
var t := 0
var detail: CardView = null
var merging := {}            # triple merge in progress: {group, chosen, step, opts}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	build()

func say(s: String) -> void:
	msg = s
	msg_t = 200

func price(n: int) -> int:
	return int(ceil(n * (1.0 - Run.discount)))

func selected_item():
	match pick.get("where", ""):
		"stash":
			return Run.stash[pick.i] if pick.i < Run.stash.size() else null
		"belt":
			return Run.belt[pick.i] if pick.i < Run.belt.size() else null
		"equip":
			return pick.s.equip[pick.slot]
		"shelf":
			return shelf[pick.i].item if not shelf[pick.i].get("mystery", false) else null
	return null

func build() -> void:
	for c in get_children():
		c.queue_free()
	detail = null
	for i in Run.soldiers.size():
		var s: Dictionary = Run.soldiers[i]
		var x := 24.0 + i * 230
		for k in SLOTS.size():
			var slot: String = SLOTS[k]
			var tile := ItemTile.new()
			tile.item = s.equip[slot]
			tile.empty_label = Data.SLOT_NAMES["kit" if slot.begins_with("kit") else slot]
			tile.position = Vector2(x + (k % 2) * 110, 74 + (k / 2) * 50)
			tile.selected = pick.get("where", "") == "equip" and pick.s == s and pick.slot == slot
			tile.pressed.connect(func(): select({"where": "equip", "s": s, "slot": slot}))
			add_child(tile)
	for i in Data.STASH_MAX:
		var tile := ItemTile.new()
		tile.item = Run.stash[i] if i < Run.stash.size() else null
		tile.empty_label = "EMPTY"
		tile.position = Vector2(24 + (i % 4) * 110, 222 + (i / 4) * 50)
		tile.selected = pick.get("where", "") == "stash" and pick.i == i
		var idx := i
		tile.pressed.connect(func(): select({"where": "stash", "i": idx}))
		add_child(tile)
	# overflow beyond the stash cap still shows, so nothing is ever hidden
	for i in range(Data.STASH_MAX, Run.stash.size()):
		var tile := ItemTile.new()
		tile.item = Run.stash[i]
		tile.position = Vector2(24 + (i % 4) * 110, 222 + (i / 4) * 50)
		tile.selected = pick.get("where", "") == "stash" and pick.i == i
		var idx := i
		tile.pressed.connect(func(): select({"where": "stash", "i": idx}))
		add_child(tile)
	for i in Run.belt_max():
		var tile := ItemTile.new()
		tile.item = Run.belt[i] if i < Run.belt.size() else null
		tile.empty_label = "BELT"
		var bw := 110 if Run.belt_max() <= 3 else 82
		tile.tw = bw - 6
		tile.position = Vector2(470 + i * bw, 222)
		tile.selected = pick.get("where", "") == "belt" and pick.i == i
		var idx := i
		tile.pressed.connect(func(): select({"where": "belt", "i": idx}))
		add_child(tile)
	if shop_mode:
		for i in shelf.size():
			var o: Dictionary = shelf[i]
			var tile := ItemTile.new()
			tile.item = null if o.get("mystery", false) else o.item
			tile.empty_label = "MYSTERY CRATE" if o.get("mystery", false) else ""
			tile.mystery = o.get("mystery", false)
			tile.black = o.get("black", false)
			tile.price = -1 if o.get("sold", false) else price(o.price)
			tile.sold = o.get("sold", false)
			tile.position = Vector2(470 + (i % 3) * 110, 296 + (i / 3) * 50)
			tile.selected = pick.get("where", "") == "shelf" and pick.i == i
			var idx := i
			tile.pressed.connect(func(): select({"where": "shelf", "i": idx}))
			add_child(tile)
	var it = selected_item()
	if it != null:
		detail = CardView.new()
		detail.opt = Run.item_opt(it)
		detail.size = Vector2(128, 176)
		detail.position = Vector2(808, 214)
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(detail)
	build_actions(it)
	var back := HudScript.PixButton.new()
	back.text = "BACK" if shop_mode else "DONE"
	back.color = Color("ffb23e")
	back.size = Vector2(150, 40)
	back.position = Vector2(786, 486)
	back.pressed.connect(func(): Sfx.play("click"); done.emit())
	add_child(back)

func action(label: String, col: Color, fn: Callable, x: float, disabled := false) -> float:
	var bt := HudScript.PixButton.new()
	bt.text = label
	bt.color = col
	bt.size = Vector2(maxf(80.0, Art.text_width(label, 8) + 24), 26)
	bt.position = Vector2(x, 440)
	bt.disabled = disabled
	bt.pressed.connect(fn)
	add_child(bt)
	return x + bt.size.x + 8

func build_actions(it) -> void:
	var x := 24.0
	if not merging.is_empty():
		build_merge_row()
		return
	var where: String = pick.get("where", "")
	if where == "shelf":
		var o: Dictionary = shelf[pick.i]
		if not o.get("sold", false):
			x = action("BUY %d$" % price(o.price), Color("62d26f"), buy_shelf, x, Run.scrip < price(o.price))
		return
	if it == null:
		return
	var slot_kind: String = Data.ITEMS[it.id].slot
	if where in ["stash", "belt"] and slot_kind != "belt":
		for s in Run.soldiers:
			var ss: Dictionary = s
			x = action("EQUIP ON %s" % s.def.name, Color("53d4e2"), func(): equip_on(ss), x)
	if where == "equip":
		x = action("UNEQUIP", Color("9aa2ae"), unequip_sel, x)
	if where == "stash" and slot_kind == "belt":
		x = action("TO BELT", Color("62d26f"), func(): move_belt(true), x, Run.belt.size() >= Run.belt_max())
	if where == "belt":
		x = action("TO STASH", Color("9aa2ae"), func(): move_belt(false), x)
	x = merge_actions(it, x)
	if shop_mode and where in ["stash", "belt"]:
		x = action("SELL %d$" % Run.sell_value(it), Color("ffd23a"), sell_sel, x)
	if shop_mode and it.get("affixes", []).size() > 0:
		var cost := 0 if Run.reroll_tokens > 0 else gunsmith_price()
		x = action("REROLL AFFIX %s" % ("FREE" if cost == 0 else "%d$" % cost), Color("b48cff"), reroll_sel, x, Run.scrip < cost)

func merge_actions(it, x: float) -> float:
	var g := Run.merge_group_of(it)
	if g.size() == 3:
		x = action("MERGE 3 > %s" % Data.tier_name(it.tier + 1), Data.tier_color(it.tier + 1), func(): start_merge(g), x)
	return x

func start_merge(g: Array) -> void:
	## M1/M2: keep one affix from the three, then pick one of two new ones.
	Sfx.play("click")
	merging = {"group": g, "chosen": [], "t": g[0].tier + 1}
	next_merge_step()

func next_merge_step() -> void:
	var t: int = merging.t
	var chosen: Array = merging.chosen
	if not merging.has("kept"):
		merging.kept = true
		var keep := Run.merge_keep_options(merging.group)
		if keep.size() > 1 and Data.AFFIX_COUNT[t] > 0:
			merging.step = "KEEP ONE AFFIX"
			merging.opts = keep
			build()
			return
		if keep.size() == 1:
			chosen.append(keep[0])
	if not merging.has("picked") and chosen.size() < Data.AFFIX_COUNT[t]:
		merging.picked = true
		merging.step = "ADD ONE NEW AFFIX"
		merging.opts = Run.merge_new_options(chosen)
		build()
		return
	var out := Run.merge_items(merging.group, chosen)
	merging = {}
	Sfx.play("levelup")
	say("Merged into %s %s." % [Data.tier_name(out.tier).capitalize(), Data.item_name(out)])
	pick = {"where": "stash", "i": Run.stash.find(out)} if Run.stash.has(out) else {}
	build()

func build_merge_row() -> void:
	var x := 24.0
	var t: int = merging.t
	for a in merging.opts:
		var aa: String = a
		x = action(Data.affix_text(aa, t).to_upper(), Color("b48cff"), func():
			merging.chosen.append(aa)
			next_merge_step(), x)
	x = action("CANCEL", Color("9aa2ae"), func(): merging = {}; build(), x)

func gunsmith_price() -> int:
	return price(40 + 20 * Run.gunsmith_uses)

func select(p: Dictionary) -> void:
	Sfx.play("click")
	pick = {} if pick.hash() == p.hash() else p
	build()

func equip_on(s: Dictionary) -> void:
	var it = selected_item()
	if it == null:
		return
	if not s.alive:
		say("%s is KIA. Revive them at the Quartermaster first." % s.def.name)
		Sfx.play("deny")
		return
	Run.belt.erase(it)
	if not Run.stash.has(it):
		Run.stash.append(it)
	Run.equip(s, it)
	Sfx.play("buy")
	say("%s equipped %s." % [s.def.name, Data.item_name(it)])
	pick = {}
	build()

func unequip_sel() -> void:
	Run.unequip(pick.s, pick.slot)
	Sfx.play("click")
	pick = {}
	build()

func move_belt(to_belt: bool) -> void:
	var it = selected_item()
	if to_belt:
		Run.stash.erase(it)
		Run.belt.append(it)
	else:
		Run.belt.erase(it)
		Run.stash.append(it)
	pick = {}
	build()

func sell_sel() -> void:
	var it = selected_item()
	Run.stash.erase(it)
	Run.belt.erase(it)
	Run.scrip += Run.sell_value(it)
	Sfx.play("coin")
	say("Sold %s for %d scrip." % [Data.item_name(it), Run.sell_value(it)])
	pick = {}
	build()

func reroll_sel() -> void:
	var it = selected_item()
	if Run.reroll_tokens > 0:
		Run.reroll_tokens -= 1
	else:
		var cost := gunsmith_price()
		if Run.scrip < cost:
			Sfx.play("deny")
			return
		Run.scrip -= cost
		Run.gunsmith_uses += 1
	# keep all but one affix, replace that one with something new
	var old: Array = it.affixes.duplicate()
	var drop := randi() % old.size()
	var pool: Array = Data.AFFIXES.keys().filter(func(a): return not old.has(a))
	old[drop] = pool[randi() % pool.size()]
	it.affixes = old
	for s in Run.soldiers:
		for sl in s.equip:
			if s.equip[sl] == it:
				s.hp = mini(s.hp, Run.eff_max_hp(s))
	Sfx.play("power")
	say("The gunsmith reworked %s." % Data.item_name(it))
	build()

func buy_shelf() -> void:
	var o: Dictionary = shelf[pick.i]
	var p := price(o.price)
	if o.get("sold", false) or Run.scrip < p:
		Sfx.play("deny")
		return
	Run.scrip -= p
	o.sold = true
	var it: Dictionary = o.item if not o.get("mystery", false) else Run.roll_item()
	Run.add_loot(it)
	Sfx.play("buy")
	say("%s %s added to the %s." % [Data.tier_name(it.tier).capitalize(), Data.item_name(it), "belt" if Run.belt.has(it) else "stash"])
	pick = {}
	build()

func _process(_d: float) -> void:
	t += 1
	if msg_t > 0:
		msg_t -= 1
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color("1a1d22"))
	for y in range(0, 540, 24):
		for x in range(0, 960, 24):
			draw_texture_rect(Art.tex.ui_panel, Rect2(x, y, 24, 24), false, Color(0.5, 0.5, 0.56))
	var hz: Texture2D = Art.tex.ui_hazard
	for x in range(0, 960, 32):
		draw_texture_rect(hz, Rect2(x, 0, 32, 8), false)
	Art.text(self, "ARMORY", Vector2(24, 40), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
	Art.text(self, "Click an item, then pick what to do with it. Weapons put their cards in that soldier's deck.", Vector2(150, 40), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
	var sc := "%d SCRIP" % Run.scrip
	draw_texture_rect(Art.tex.ic_coin, Rect2(936 - Art.text_width(sc, 8) - 14, 26, 10, 10), false)
	Art.text(self, sc, Vector2(936, 36), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT)
	for i in Run.soldiers.size():
		var s: Dictionary = Run.soldiers[i]
		var x := 24.0 + i * 230
		Art.text(self, s.def.name, Vector2(x, 66), 8, Color.WHITE if s.alive else Color("8a7a7a"))
		Art.text(self, ("HP %d/%d  DECK %d" % [s.hp, Run.eff_max_hp(s), s.deck.size()]) if s.alive else "KIA", Vector2(x + 214, 66), 8, Color("9aa2ae") if s.alive else Color("ff4d3d"), HORIZONTAL_ALIGNMENT_RIGHT)
		var sets := active_sets(s)
		if sets != "":
			Art.text(self, sets, Vector2(x, 186), 16, Color("62d26f"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
	Art.text(self, "STASH %d/%d" % [Run.stash.size(), Data.STASH_MAX], Vector2(24, 214), 8, Color("ffb23e") if Run.stash.size() <= Data.STASH_MAX else Color("ff4d3d"))
	Art.text(self, "BELT: USE MID-MISSION, NO CARD NEEDED", Vector2(470, 214), 8, Color("62d26f"))
	if shop_mode:
		Art.text(self, "ITEM SHELF" + ("  %d%% OFF" % int(Run.discount * 100) if Run.discount > 0 else ""), Vector2(470, 288), 8, Color("53d4e2"))
	if Run.reroll_tokens > 0:
		Art.text(self, "FREE REROLLS: %d" % Run.reroll_tokens, Vector2(808, 410), 8, Color("b48cff"))
	if Run.trophies.size():
		Art.text(self, "TROPHIES: " + ", ".join(Run.trophies), Vector2(24, 400), 8, Color("ffb21e"))
	if not merging.is_empty():
		Art.text(self, "MERGING 3x %s INTO %s: %s" % [Data.item_name(merging.group[0]).to_upper(), Data.tier_name(merging.t), merging.get("step", "")], Vector2(24, 432), 8, Data.tier_color(merging.t))
	elif Run.any_merge():
		Art.text(self, "TRIPLE READY: select one of three matching items and press MERGE", Vector2(24, 432), 8, Color("b48cff") if t % 60 < 40 else Color("7a5fb0"))
	if msg_t > 0:
		var w := Art.text_width(msg, 16, true) + 20
		draw_rect(Rect2(480 - w / 2, 470, w, 20), Color(0.05, 0.035, 0.03, 0.9))
		Art.text(self, msg, Vector2(480, 485), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 0, true)

func active_sets(s: Dictionary) -> String:
	var counts := {}
	for sl in s.equip:
		var it = s.equip[sl]
		if it != null and Data.ITEMS[it.id].has("set"):
			counts[Data.ITEMS[it.id].set] = counts.get(Data.ITEMS[it.id].set, 0) + 1
	var out: Array = []
	for k in counts:
		out.append("%s %d/2%s" % [Data.SETS[k].name, counts[k], " ACTIVE" if counts[k] >= 2 else ""])
	return "  ".join(out)

# ================================================================ item tile
class ItemTile extends Control:
	## A compact item slot: rarity frame, icon, name and its first stat.
	signal pressed
	var item = null
	var empty_label := ""
	var selected := false
	var hover := false
	var price := -1
	var sold := false
	var mystery := false
	var black := false
	var tw := 104
	func _ready() -> void:
		size = Vector2(tw, 44)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): hover = true)
		mouse_exited.connect(func(): hover = false)
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if item != null or mystery:
				pressed.emit()
	func _process(_d: float) -> void:
		queue_redraw()
	static func fit(s: String, maxw: float) -> String:
		if Art.text_width(s, 16, true) <= maxw:
			return s
		while s.length() > 1 and Art.text_width(s + ".", 16, true) > maxw:
			s = s.substr(0, s.length() - 1)
		return s.strip_edges() + "."
	func _draw() -> void:
		var ink := Color(0.05, 0.035, 0.03)
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), ink)
		if item == null and not mystery:
			draw_rect(Rect2(1, 1, w - 2, h - 2), Color("23262b"))
			Art.text(self, empty_label, Vector2(w / 2, h / 2 + 4), 8, Color("4a505a"), HORIZONTAL_ALIGNMENT_CENTER)
			return
		var t: int = item.tier if item != null else 2
		var rc := Data.tier_color(t) if item != null else Color("ffd23a")
		draw_rect(Rect2(1, 1, w - 2, h - 2), Color("2e3238") if not hover else Color("3a3f46"))
		draw_rect(Rect2(0, 0, w, h), rc, false, 2.0 if t >= 1 or mystery else 1.0)
		if selected:
			draw_rect(Rect2(-3, -3, w + 6, h + 6), Color("ffd23a"), false, 2.0)
		if mystery:
			Art.text(self, "?", Vector2(18, 30), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 1)
			Art.text(self, "MYSTERY", Vector2(36, 18), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 0, true)
			Art.text(self, "Any rarity", Vector2(36, 32), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		else:
			var d: Dictionary = Data.ITEMS[item.id]
			var icon: String = {"weapon": "ic_up", "armor": "ic_shield", "kit": "ic_star", "belt": "ic_heart"}.get(d.slot, "ic_card")
			if d.slot == "weapon":
				icon = "ic_card"
			draw_texture_rect(Art.tex[icon], Rect2(5, 6, 16, 16), false)
			Art.text(self, Data.SLOT_NAMES[d.slot].substr(0, 3), Vector2(13, 36), 8, rc, HORIZONTAL_ALIGNMENT_CENTER)
			var nm: String = d.name
			nm = ItemTile.fit(nm, w - 31)
			Art.text(self, nm, Vector2(27, 17), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 0, true)
			var sl: Array = Data.stat_lines(Data.item_stats(item))
			var line: String = sl[0] if sl.size() else d.text
			line = ItemTile.fit(line, w - 31)
			Art.text(self, line, Vector2(27, 32), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		if black:
			Art.text(self, "BLACK MKT", Vector2(27, h - 3), 8, Color("ff4d3d"))
		if sold:
			draw_rect(Rect2(1, 1, w - 2, h - 2), Color(0, 0, 0, 0.6))
			Art.text(self, "SOLD", Vector2(w / 2, h / 2 + 4), 8, Color("ff4d3d"), HORIZONTAL_ALIGNMENT_CENTER)
		elif price >= 0:
			draw_rect(Rect2(w - 40, h - 12, 40, 12), ink)
			Art.text(self, "%d$" % price, Vector2(w - 3, h - 2), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT)

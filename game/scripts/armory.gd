extends Control
## The Armory: four gear slots per soldier, the shared stash and the consumable belt.
## Opened at HQ (selling, the gunsmith's affix reroll and COPY ITEM) or from the debrief.
## Click an item to select it, then use the action buttons.

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
var tiles: Array = []        # every ItemTile on screen, with its ref ({where, i} or {where, s, slot})
var drag := {}               # gear being dragged: {ref, item, at, on}
var ghost: ItemTile = null   # the dragged tile following the mouse
var hover_tile: ItemTile = null
var mouse_p := Vector2(-99, -99)  # last mouse position seen, in this screen's coordinates
var equip_lbl := -1.0        # x of the EQUIP ON label in front of the soldier buttons

const STASH_AREA := Rect2(16, 206, 450, 116)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	build()

func say(s: String) -> void:
	msg = s
	msg_t = 200

func price(n: int) -> int:
	return int(ceil(n * (1.0 - Run.discount)))

func selected_item():
	return item_at(pick)

func cols() -> int:
	return maxi(4, Run.soldiers.size())  # X2: a freed specialist makes a fifth column

func col_x(i: int) -> float:
	return 24.0 + i * (col_w() + 10)

func col_w() -> float:
	return (912.0 - 10 * (cols() - 1)) / cols()

func add_tile(it, ref: Dictionary, pos: Vector2, empty_label := "", tw := 104) -> ItemTile:
	var tile := ItemTile.new()
	tile.item = it
	tile.ref = ref
	tile.empty_label = empty_label
	tile.tw = tw
	tile.position = pos
	tile.selected = same(pick, ref)
	tile.fit = fit_for(it, ref)
	tile.clickable_empty = ref.where == "equip"
	tile.pressed.connect(func(): select(ref))
	add_child(tile)
	tiles.append(tile)
	return tile

func build() -> void:
	for c in get_children():
		c.queue_free()
	detail = null
	ghost = null
	tiles = []
	var tw := int((col_w() - 4) / 2)
	for i in Run.soldiers.size():
		var s: Dictionary = Run.soldiers[i]
		for k in SLOTS.size():
			var slot: String = SLOTS[k]
			add_tile(s.equip[slot], {"where": "equip", "s": s, "slot": slot}, Vector2(col_x(i) + (k % 2) * (tw + 4), 72 + (k / 2) * 48),
				Data.SLOT_NAMES[Data.slot_group(slot)], tw)
	# overflow beyond the stash cap still shows, so nothing is ever hidden
	for i in maxi(Data.STASH_MAX, Run.stash.size()):
		add_tile(Run.stash[i] if i < Run.stash.size() else null, {"where": "stash", "i": i}, Vector2(24 + (i % 4) * 110, 222 + (i / 4) * 50), "EMPTY")
	var bw := 110 if Run.belt_max() <= 3 else 82
	for i in Run.belt_max():
		add_tile(Run.belt[i] if i < Run.belt.size() else null, {"where": "belt", "i": i}, Vector2(470 + i * bw, 222), "BELT", bw - 6)
	if shop_mode:
		for i in shelf.size():
			var o: Dictionary = shelf[i]
			var tile := add_tile(null if o.get("mystery", false) else o.item, {"where": "shelf", "i": i}, Vector2(470 + (i % 3) * 110, 296 + (i / 3) * 50),
				"MYSTERY CRATE" if o.get("mystery", false) else "")
			tile.mystery = o.get("mystery", false)
			tile.black = o.get("black", false)
			tile.price = -1 if o.get("sold", false) else price(o.price)
			tile.sold = o.get("sold", false)
	var it = selected_item()
	detail = CardView.new()
	detail.size = Vector2(128, 176)
	detail.position = Vector2(808, 214)
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.visible = false
	add_child(detail)
	build_actions(it)
	var back := HudScript.PixButton.new()
	back.text = "BACK" if shop_mode else "DONE"
	back.color = Color("ffb23e")
	back.size = Vector2(150, 40)
	back.position = Vector2(786, 486)
	back.pressed.connect(func(): Sfx.play("click"); done.emit())
	add_child(back)

# ---------------------------------------------------------------- what fits where
static func fits(it, slot: String) -> bool:
	return it != null and Data.ITEMS[it.id].slot == Data.slot_group(slot)

static func card_delta(it_new, it_old) -> Array:
	## The deck change of swapping it_old out for it_new, as [[text, good]]: "+2 Carbine Burst".
	var n := {}
	for src in [[it_new, 1], [it_old, -1]]:
		if src[0] == null:
			continue
		for k in Data.ITEMS[src[0].id].get("cards", []):
			n[k] = n.get(k, 0) + src[1]
	var out: Array = []
	for k in n:
		if n[k] != 0:
			out.append(["%s%d %s" % ["+" if n[k] > 0 else "-", absi(n[k]), Data.CARDS[k].name], n[k] > 0])
	return out

static func deck_words(delta: Array) -> String:
	return ", ".join(delta.map(func(l): return l[0])) if delta.size() else "no change to the deck"

static func equip_changes(s: Dictionary, it: Dictionary, slot := "") -> Array:
	## S4: what putting this item in that slot changes for the soldier, as [text, good] lines:
	## stats, the cards it adds to the deck and the cards the replaced item takes out.
	if slot == "":
		slot = Run.slot_for(s, it)
	var old = s.equip[slot]
	var a := Data.item_stats(it)
	var b: Dictionary = Data.item_stats(old) if old != null else {}
	var out: Array = []
	var keys: Array = a.keys()
	for k in b:
		if not keys.has(k):
			keys.append(k)
	for k in keys:
		var d = a.get(k, 0) - b.get(k, 0)
		if is_zero_approx(float(d)):
			continue
		var ln: String = Data.stat_lines({k: abs(d)})[0]
		out.append([("+ " if d > 0 else "- ") + ln, d > 0])
	for l in card_delta(it, old):
		out.append(["Deck: " + l[0], l[1]])
	if old != null:
		out.append(["%s goes to the stash." % Data.item_name(old), true])
	return out

func same(a: Dictionary, b: Dictionary) -> bool:
	if a.get("where", "") != b.get("where", "") or a.is_empty():
		return false
	if a.where == "equip":
		return is_same(a.s, b.s) and a.slot == b.slot
	return a.i == b.i

func item_at(ref: Dictionary):
	match ref.get("where", ""):
		"stash":
			return Run.stash[ref.i] if ref.i < Run.stash.size() else null
		"belt":
			return Run.belt[ref.i] if ref.i < Run.belt.size() else null
		"equip":
			return ref.s.equip[ref.slot]
		"shelf":
			return shelf[ref.i].item if not shelf[ref.i].get("mystery", false) else null
	return null

func can_drop(src: Dictionary, it, dst: Dictionary) -> bool:
	## Can the item at src go to dst? Gear goes into the slot it fits, back to the stash, or
	## belt items onto the belt.
	if it == null:
		return false
	match dst.get("where", ""):
		"equip":
			return fits(it, dst.slot) and dst.s.alive and not same(src, dst)
		"stash":
			return src.where in ["equip", "belt"]
		"belt":
			return src.where == "stash" and Data.ITEMS[it.id].slot == "belt" and Run.belt.size() < Run.belt_max()
	return false

func fit_for(it, ref: Dictionary) -> int:
	## Lights the tiles the current selection can go to (1) and dims the ones it can't (-1).
	if not merging.is_empty():
		return 0
	var src := pick
	var held = selected_item()
	if drag.get("on", false):
		src = drag.ref
		held = drag.item
	if src.is_empty():
		return 0
	if src.where == "equip" and not drag.get("on", false):
		# a picked slot lights the stash gear that fits it
		if ref.where == "stash" and it != null:
			return 1 if fits(it, src.slot) and src.s.alive else -1
		return 0
	if held == null or src.where == "shelf" or same(src, ref):
		return 0
	if can_drop(src, held, ref):
		return 1 if ref.where != "stash" or drag.get("on", false) else 0
	return -1 if ref.where == "equip" or (ref.where == "belt" and Data.ITEMS[held.id].slot == "belt") else 0

func put(src: Dictionary, dst: Dictionary) -> bool:
	## Moves an item by drag or click: into a slot (swapping what was there), back to the
	## stash, or onto the belt. Says what changed in the deck.
	var it = item_at(src)
	if not can_drop(src, it, dst):
		Sfx.play("deny")
		if it != null and dst.get("where", "") == "equip":
			if not dst.s.alive:
				say("%s is KIA. Revive them at the Quartermaster first." % dst.s.def.name)
			elif not fits(it, dst.slot):
				say("%s is %s gear. It doesn't fit the %s slot." % [Data.item_name(it), Data.SLOT_NAMES[Data.ITEMS[it.id].slot], Data.SLOT_NAMES[Data.slot_group(dst.slot)]])
		return false
	match dst.where:
		"equip":
			var s: Dictionary = dst.s
			var delta := card_delta(it, s.equip[dst.slot])
			if src.where == "equip":
				Run.unequip(src.s, src.slot)
			var old: Dictionary = Run.equip(s, it, dst.slot)
			# a straight swap between two slots: the replaced item goes where this one came from
			if src.where == "equip" and not old.is_empty() and fits(old, src.slot) and src.s.alive:
				Run.equip(src.s, old, src.slot)
			Sfx.play("buy")
			say("%s equipped %s: %s." % [s.def.name, Data.item_name(it), deck_words(delta)])
		"stash":
			if src.where == "equip":
				var delta := card_delta(null, it)
				Run.unequip(src.s, src.slot)
				say("%s took off %s: %s." % [src.s.def.name, Data.item_name(it), deck_words(delta)])
			else:
				Run.belt.erase(it)
				Run.stash.append(it)
			Sfx.play("click")
		"belt":
			Run.stash.erase(it)
			Run.belt.append(it)
			Sfx.play("click")
	pick = {}
	build()
	return true

# ---------------------------------------------------------------- drag and drop
func tile_under(p: Vector2) -> ItemTile:
	## The tile under a point in this screen's coordinates.
	for tl in tiles:
		if is_instance_valid(tl) and tl.visible and Rect2(tl.position, tl.size).has_point(p):
			return tl
	return null

func _input(ev: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# right-click backs out one step: a merge or a picked slot first, before it leaves the armory
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT and not drag.get("on", false) and (not merging.is_empty() or not pick.is_empty()):
		get_viewport().set_input_as_handled()
		Sfx.play("click")
		merging = {}
		pick = {}
		build()
		return
	if not merging.is_empty() or not ev is InputEventMouse:
		return
	var p: Vector2 = make_input_local(ev).position
	mouse_p = p
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			drag = {}
			var tl := tile_under(p)
			if tl != null and tl.item != null and tl.ref.where in ["stash", "belt", "equip"]:
				drag = {"ref": tl.ref, "item": tl.item, "at": p, "on": false}
		elif not drag.is_empty():
			var d := drag
			drag = {}
			if d.on:
				get_viewport().set_input_as_handled()
				drop_at(d, p)
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT and drag.get("on", false):
		get_viewport().set_input_as_handled()
		drag = {}
		say("Cancelled.")
		build()
	elif ev is InputEventMouseMotion and not drag.is_empty():
		if not drag.on and p.distance_to(drag.at) > 6:
			start_drag()
		if drag.on and ghost != null:
			ghost.position = p - ghost.size / 2

func start_drag() -> void:
	drag.on = true
	Sfx.play("select")
	pick = {}
	for tl in tiles:
		tl.selected = false
		tl.fit = fit_for(tl.item, tl.ref)
		tl.lifted = same(tl.ref, drag.ref)
	ghost = ItemTile.new()
	ghost.item = drag.item
	ghost.ghost = true
	ghost.z_index = 20
	ghost.position = mouse_p - Vector2(52, 22)
	add_child(ghost)

func drop_at(d: Dictionary, p: Vector2) -> void:
	var tl := tile_under(p)
	if tl != null and can_drop(d.ref, d.item, tl.ref):
		put(d.ref, tl.ref)
		return
	# anywhere over the stash counts as "back to the stash"
	if d.ref.where in ["equip", "belt"] and STASH_AREA.has_point(p):
		put(d.ref, {"where": "stash", "i": 0})
		return
	if tl != null and not same(d.ref, tl.ref):
		put(d.ref, tl.ref)  # says why it doesn't fit
	build()

func action(label: String, col: Color, fn: Callable, x: float, disabled := false, min_w := 80.0) -> float:
	var bt := HudScript.PixButton.new()
	bt.text = label
	bt.color = col
	bt.size = Vector2(maxf(min_w, Art.text_width(label, 8) + 24), 26)
	bt.position = Vector2(x, 440)
	bt.disabled = disabled
	bt.pressed.connect(fn)
	add_child(bt)
	return x + bt.size.x + 8

func build_actions(it) -> void:
	var x := 24.0
	equip_lbl = -1.0
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
		equip_lbl = x
		x += Art.text_width("EQUIP ON", 8) + 10
		for s in Run.soldiers:
			var ss: Dictionary = s
			x = action(s.def.name, Color("53d4e2"), func(): equip_on(ss), x, not s.alive, 64.0)
	if where == "equip":
		x = action("UNEQUIP", Color("9aa2ae"), unequip_sel, x)
	if where == "stash" and slot_kind == "belt":
		x = action("TO BELT", Color("62d26f"), func(): move_belt(true), x, Run.belt.size() >= Run.belt_max())
	if where == "belt":
		x = action("TO STASH", Color("9aa2ae"), func(): move_belt(false), x)
	x = merge_actions(it, x)
	if shop_mode and where in ["stash", "belt"]:
		x = action("SELL %d$" % Run.sell_value(it), Color("ffd23a"), sell_sel, x)
	if shop_mode and Run.fab_options().has(it):
		x = action("COPY %d$" % price(Data.FAB_PRICE), Color("b48cff"), copy_sel, x, Run.scrip < price(Data.FAB_PRICE))
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
	# a picked slot plus gear that fits it (or the other way round): equip it straight away
	var held = selected_item()
	if pick.get("where", "") == "equip" and p.where == "stash" and fits(item_at(p), pick.slot) and pick.s.alive:
		put(p, pick)
		return
	if pick.get("where", "") in ["stash", "equip"] and held != null and p.where == "equip" and can_drop(pick, held, p):
		put(pick, p)
		return
	Sfx.play("click")
	pick = {} if same(pick, p) else p
	build()

func equip_on(s: Dictionary) -> void:
	var it = selected_item()
	if it == null:
		return
	if not s.alive:
		say("%s is KIA. Revive them at the Quartermaster first." % s.def.name)
		Sfx.play("deny")
		return
	if Run.belt.has(it):
		Run.belt.erase(it)
		Run.stash.append(it)
	put({"where": "stash", "i": Run.stash.find(it)}, {"where": "equip", "s": s, "slot": Run.slot_for(s, it)})

func unequip_sel() -> void:
	put(pick, {"where": "stash", "i": 0})

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

func copy_sel() -> void:
	## M5, moved here from the Quartermaster: copy a Common or Uncommon item to finish a triple.
	var it = selected_item()
	var p := price(Data.FAB_PRICE)
	if it == null or Run.scrip < p:
		Sfx.play("deny")
		return
	Run.scrip -= p
	var cp := Run.fabricate(it)
	Sfx.play("buy")
	say("Copied %s.%s" % [Data.item_name(cp), " A triple is ready: press MERGE." if Run.merge_group_of(cp).size() == 3 else ""])
	pick = {"where": "stash", "i": Run.stash.find(cp)}
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
	hover_tile = tile_under(mouse_p)
	# the big card shows what the mouse is over, else the selection: full names on narrow tiles
	if detail != null and is_instance_valid(detail):
		var show = hover_tile.item if hover_tile != null and hover_tile.item != null and not hover_tile.ghost else selected_item()
		if drag.get("on", false):
			show = drag.item
		detail.visible = show != null
		if show != null and detail.opt.get("item") != show:
			detail.opt = Run.item_opt(show)
			detail.queue_redraw()
	queue_redraw()

func _draw() -> void:
	Tip.clear(self)
	draw_rect(Rect2(0, 0, 960, 540), Color("1a1d22"))
	for y in range(0, 540, 24):
		for x in range(0, 960, 24):
			draw_texture_rect(Art.tex.ui_panel, Rect2(x, y, 24, 24), false, Color(0.5, 0.5, 0.56))
	var hz: Texture2D = Art.tex.ui_hazard
	for x in range(0, 960, 32):
		draw_texture_rect(hz, Rect2(x, 0, 32, 8), false)
	Art.text(self, "ARMORY", Vector2(24, 50), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
	Art.text(self, "Drag gear onto a soldier, or click a slot to see what fits. Weapons put their cards in the deck.", Vector2(150, 48), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
	var sc := "%d SCRIP" % Run.scrip
	draw_texture_rect(Art.tex.ic8_coin, Rect2(936 - Art.text_width(sc, 8) - 14, 38, 10, 10), false)
	Art.text(self, sc, Vector2(936, 48), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT)
	for i in Run.soldiers.size():
		var s: Dictionary = Run.soldiers[i]
		var x := col_x(i)
		var w := col_w()
		Art.text(self, s.def.name, Vector2(x, 66), 8, Color.WHITE if s.alive else Color("8a7a7a"))
		Art.text(self, ("HP %d/%d" % [s.hp, Run.eff_max_hp(s)]) if s.alive else "KIA", Vector2(x + w, 66), 8, Color("9aa2ae") if s.alive else Color("ff4d3d"), HORIZONTAL_ALIGNMENT_RIGHT)
		var gear_cards: int = s.deck.filter(func(c): return c.get("src", -1) != -1).size()
		Art.text(self, "DECK %d%s" % [s.deck.size(), ", %d from gear" % gear_cards if gear_cards else " cards"], Vector2(x, 180), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		# gear sets and kit evolutions, each one hoverable
		Tip.chips(self, Run.synergies(s).filter(func(sy): return sy.kind != "duo"), Vector2(x, 194), w)
	Art.text(self, "STASH %d/%d" % [Run.stash.size(), Data.STASH_MAX], Vector2(24, 214), 8, Color("ffb23e") if Run.stash.size() <= Data.STASH_MAX else Color("ff4d3d"))
	Art.text(self, "BELT: USE MID-MISSION, NO CARD NEEDED", Vector2(470, 214), 8, Color("62d26f"))
	if shop_mode and shelf.size():
		Art.text(self, "ITEM SHELF" + ("  %d%% OFF" % int(Run.discount * 100) if Run.discount > 0 else ""), Vector2(470, 288), 8, Color("53d4e2"))
	if Run.reroll_tokens > 0:
		Art.text(self, "FREE REROLLS: %d" % Run.reroll_tokens, Vector2(808, 410), 8, Color("b48cff"))
	draw_help()
	if equip_lbl >= 0:
		Art.text(self, "EQUIP ON", Vector2(equip_lbl, 457), 8, Color("53d4e2"))
	if Run.trophies.size():
		Art.text(self, "TROPHIES: " + ", ".join(Run.trophies), Vector2(24, 412), 8, Color("ffb21e"))
	if not merging.is_empty():
		Art.text(self, "MERGING 3x %s INTO %s: %s" % [Data.item_name(merging.group[0]).to_upper(), Data.tier_name(merging.t), merging.get("step", "")], Vector2(24, 432), 8, Data.tier_color(merging.t))
	elif Run.any_merge():
		Art.text(self, "TRIPLE READY: select one of three matching items and press MERGE", Vector2(24, 432), 8, Color("b48cff") if t % 60 < 40 else Color("7a5fb0"))
	if msg_t > 0:
		var w := Art.text_width(msg, 16, true) + 20
		draw_rect(Rect2(480 - w / 2, 470, w, 20), Color(0.05, 0.035, 0.03, 0.9))
		Art.text(self, msg, Vector2(480, 485), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 0, true)

func draw_help() -> void:
	## The panel under the stash: what the selection fits and what it does to the deck.
	var x := 24.0
	var y := 340.0
	var lines: Array = []    # [text, color]
	var title := ""
	var held = selected_item()
	var src := pick
	if drag.get("on", false):
		src = drag.ref
		held = drag.item
	var tgt: Dictionary = hover_tile.ref if hover_tile != null and not hover_tile.ghost else {}
	var green := Color("62d26f")
	var red := Color("e8a070")
	var grey := Color("9aa2ae")
	if not merging.is_empty():
		return
	if src.is_empty():
		title = "GEAR"
		lines = [["Click an empty WEAPON, ARMOR or KIT slot to light up the stash gear that fits it.", grey],
			["Drag gear between the stash and the slots. Right-click cancels a drag.", grey]]
	elif src.where == "equip" and held == null:
		var slot_word: String = Data.SLOT_NAMES[Data.slot_group(src.slot)]
		title = "%s: EMPTY %s SLOT" % [src.s.def.name, slot_word]
		var n: int = Run.stash.filter(func(o): return fits(o, src.slot)).size()
		if tgt.get("where", "") == "stash" and fits(item_at(tgt), src.slot):
			title = "%s: EQUIP %s?" % [src.s.def.name, Data.item_name(item_at(tgt)).to_upper()]
			for l in equip_changes(src.s, item_at(tgt), src.slot):
				lines.append([l[0], green if l[1] else red])
		elif n > 0:
			lines.append(["%d item%s in the stash fit%s this slot (lit). Click one or drag it here." % [n, "s" if n > 1 else "", "" if n > 1 else "s"], green])
		else:
			lines.append(["Nothing in the stash fits a %s slot." % slot_word, red])
			lines.append(["The item shelf at the QM tent and loot crates bring new gear.", grey])
	elif held != null and src.where in ["stash", "equip", "belt"]:
		var kind: String = Data.ITEMS[held.id].slot
		title = Data.item_name(held).to_upper()
		if tgt.get("where", "") == "equip" and can_drop(src, held, tgt):
			title = "%s ON %s?" % [title, tgt.s.def.name]
			for l in equip_changes(tgt.s, held, tgt.slot):
				lines.append([l[0], green if l[1] else red])
		elif src.where == "equip" and tgt.get("where", "") == "stash" and fits(item_at(tgt), src.slot):
			title = "SWAP IN %s?" % Data.item_name(item_at(tgt)).to_upper()
			for l in equip_changes(src.s, item_at(tgt), src.slot):
				lines.append([l[0], green if l[1] else red])
		elif src.where == "equip":
			var cards := card_delta(held, null)
			lines.append(["In %s's deck: %s." % [src.s.def.name, deck_words(cards).replace("+", "")] if cards.size() else "Adds no cards. Stats only.", grey])
			if cards.size():
				lines.append(["Unequip (or drag it to the stash) and those cards leave the deck.", red])
			var n: int = Run.stash.filter(func(o): return fits(o, src.slot)).size()
			if n > 0:
				lines.append(["Lit stash gear fits this slot: click one to swap it in.", green])
		elif kind == "belt":
			lines.append(["Belt items are used mid-mission, no card needed. Drag it to the belt.", grey])
		else:
			var cards := card_delta(held, null)
			lines.append(["Adds to the wearer's deck: %s." % deck_words(cards) if cards.size() else "Adds no cards. Stats only.", green if cards.size() else grey])
			lines.append(["Fits any %s slot (lit). Click a slot, drag it there, or use a name below." % Data.SLOT_NAMES[kind], grey])
	if title == "":
		return
	Art.text(self, title, Vector2(x, y), 8, Color("ffd23a"))
	y += 14
	for l in lines:
		for ln in CardView.wrap_text(l[0], 436, 16):
			if y > 404:
				return
			Art.text(self, ln, Vector2(x, y), 16, l[1], HORIZONTAL_ALIGNMENT_LEFT, 0, true)
			y += 12

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
	var ref := {}              # where the tile sits: {where: stash|belt|equip|shelf, i} or {where, s, slot}
	var fit := 0               # 1: the held item can go here (lit), -1: it can't (dimmed)
	var clickable_empty := false
	var lifted := false        # the tile being dragged out
	var ghost := false         # the copy that follows the mouse
	var t := 0
	func _ready() -> void:
		size = Vector2(tw, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE if ghost else Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): hover = true)
		mouse_exited.connect(func(): hover = false)
	func _gui_input(ev: InputEvent) -> void:
		## Clicks land on release, so a press can turn into a drag instead.
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if not ev.pressed and Rect2(Vector2.ZERO, size).has_point(ev.position) and (item != null or mystery or clickable_empty):
				pressed.emit()
	func _process(_d: float) -> void:
		t += 1
		queue_redraw()
	static func fit_text(s: String, maxw: float, by_word := false) -> String:
		if Art.text_width(s, 16, true) <= maxw:
			return s
		# a stat or rules line drops whole words, so it never ends on half a word ("Smoke at y.")
		var words := s.split(" ")
		while by_word and words.size() > 1 and Art.text_width(" ".join(words) + "...", 16, true) > maxw:
			words.remove_at(words.size() - 1)
		s = " ".join(words)
		var dots := "..." if by_word else "."
		while s.length() > 1 and Art.text_width(s + dots, 16, true) > maxw:
			s = s.substr(0, s.length() - 1)
		return s.strip_edges().trim_suffix(",").trim_suffix(":") + dots
	func _draw() -> void:
		var ink := Color(0.05, 0.035, 0.03)
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), ink)
		if item == null and not mystery:
			draw_rect(Rect2(1, 1, w - 2, h - 2), Color("2a2e34") if hover and clickable_empty else Color("23262b"))
			Art.text(self, empty_label, Vector2(w / 2, h / 2 + 4), 8, Color("62d26f") if fit == 1 else (Color("6c7480") if hover and clickable_empty else Color("4a505a")), HORIZONTAL_ALIGNMENT_CENTER)
			if selected:
				draw_rect(Rect2(-3, -3, w + 6, h + 6), Color("ffd23a"), false, 2.0)
			draw_marks()
			return
		var t: int = item.tier if item != null else 2
		var rc := Data.tier_color(t) if item != null else Color("ffd23a")
		draw_rect(Rect2(1, 1, w - 2, h - 2), Color("2e3238") if not hover else Color("3a3f46"))
		draw_rect(Rect2(0, 0, w, h), rc, false, 2.0 if t >= 1 or mystery else 1.0)
		if selected:
			draw_rect(Rect2(-3, -3, w + 6, h + 6), Color("ffd23a"), false, 2.0)
		if mystery:
			Art.text(self, "?", Vector2(18, 30), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 1)
			Art.text(self, "MYSTERY", Vector2(36, 15), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 0, true)
			Art.text(self, "Any rarity", Vector2(36, 28), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		else:
			var d: Dictionary = Data.ITEMS[item.id]
			var icon: String = {"weapon": "ic_up", "armor": "ic_shield", "kit": "ic_star", "belt": "ic_heart"}.get(d.slot, "ic_card")
			if d.slot == "weapon":
				icon = "ic_card"
			elif d.slot == "belt":
				icon = Data.BELT_ICONS.get(d.get("use", ""), "ic_heart")
			draw_texture_rect(Art.tex[icon], Rect2(5, 6, 16, 16), false)
			var nm: String = d.name
			nm = ItemTile.fit_text(nm, w - 31)
			Art.text(self, nm, Vector2(27, 15), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 0, true)
			var sl: Array = Data.stat_lines(Data.item_stats(item))
			var line: String = sl[0] if sl.size() else d.text
			line = ItemTile.fit_text(line, w - 31, true)
			Art.text(self, line, Vector2(27, 28), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		# the full slot word along the bottom, clear of the icon and the price
		if item != null:
			var sn: String = Data.SLOT_NAMES[Data.ITEMS[item.id].slot]
			Art.text(self, sn, Vector2(4, h - 3), 8, rc)
		if black:
			Art.text(self, "BLACK MARKET", Vector2(w / 2, -3), 8, Color("ff4d3d"), HORIZONTAL_ALIGNMENT_CENTER, 1)
		if sold:
			draw_rect(Rect2(1, 1, w - 2, h - 2), Color(0, 0, 0, 0.6))
			Art.text(self, "SOLD", Vector2(w / 2, h / 2 + 4), 8, Color("ff4d3d"), HORIZONTAL_ALIGNMENT_CENTER)
		elif price >= 0:
			draw_rect(Rect2(w - 40, h - 12, 40, 12), ink)
			Art.text(self, "%d$" % price, Vector2(w - 3, h - 2), 8, Color("ffd23a") if Run.scrip >= price else Color("8a7a40"), HORIZONTAL_ALIGNMENT_RIGHT)
		draw_marks()
	func draw_marks() -> void:
		## Lit (fits), dimmed (doesn't) and the hole a dragged item left behind.
		var w := size.x
		var h := size.y
		if fit == -1 or lifted:
			draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.035, 0.03, 0.62))
		elif fit == 1:
			var a := 0.6 + 0.4 * sin(t / 6.0)
			draw_rect(Rect2(-2, -2, w + 4, h + 4), Color(0.38, 0.82, 0.44, a), false, 2.0)
			draw_rect(Rect2(w - 38, h - 12, 38, 12), Color(0.05, 0.035, 0.03))
			Art.text(self, "FITS", Vector2(w - 19, h - 2), 8, Color("62d26f"), HORIZONTAL_ALIGNMENT_CENTER)

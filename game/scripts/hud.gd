extends CanvasLayer
## Battle HUD: a riveted metal top bar (score, scrip, alert sirens, radio clock,
## wind sock), dog-tag roster, the card hand rising from the bottom edge, the
## NEXT / MOVE / END TURN buttons, banners and the pick-one modal for rewards and level-ups.

signal picked(i: int)

var b: Battle
var overlay: Control
var hand_box: Control
var roster_box: Control
var end_btn: PixButton
var next_btn: PixButton
var move_btn: PixButton
var deck_btn: PixButton
var jet_btn: PixButton
var modal: Control
var cards: Array = []
var tags: Array = []
var deck_view: Control = null
var deck_open := false    # the DECK viewer is up (it waits on nothing, so Esc may close it)
var hand_x0 := 270.0      # left edge of the hand, so the action meter can sit beside it
var coach_queue: Array = []  # N1/N5: [who, title, text] pages waiting for a quiet player turn
var coach_box: Control = null
var targeting := false    # a card is armed: the hand ghosts out so it doesn't hide what you aim at

const INK := Color(0.05, 0.035, 0.03)
const HubUI := preload("res://scripts/hub_ui.gd")

func setup(battle: Battle) -> void:
	b = battle
	b.hud = self
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	overlay = Overlay.new()
	overlay.hud = self
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)
	roster_box = Control.new()
	roster_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(roster_box)
	hand_box = Control.new()
	hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hand_box)
	# NEXT is the big plunger now; END TURN and MOVE (auto-advance) are small buttons above it
	next_btn = PixButton.new()
	next_btn.text = "NEXT"
	next_btn.sub = "SPACE"
	next_btn.color = Color("ff4d3d")
	next_btn.position = Vector2(830, 502)
	next_btn.size = Vector2(122, 32)
	next_btn.pressed.connect(func(): Sfx.play("click"); b.next_unit())
	root.add_child(next_btn)
	end_btn = PixButton.new()
	end_btn.text = "END TURN"
	end_btn.color = Color("9aa2ae")
	end_btn.position = Vector2(894, 478)
	end_btn.size = Vector2(58, 22)
	end_btn.pressed.connect(func(): Sfx.play("click"); b.end_turn())
	root.add_child(end_btn)
	move_btn = PixButton.new()
	move_btn.text = "MOVE"
	move_btn.color = Color("62d26f")
	move_btn.position = Vector2(830, 478)
	move_btn.size = Vector2(58, 22)
	move_btn.pressed.connect(func(): Sfx.play("click"); b.auto_advance())
	root.add_child(move_btn)
	jet_btn = PixButton.new()
	jet_btn.text = "JET"
	jet_btn.sub = "J"
	jet_btn.color = Color("53d4e2")
	jet_btn.size = Vector2(46, 26)
	jet_btn.visible = false
	jet_btn.pressed.connect(func(): b.toggle_jet())
	root.add_child(jet_btn)
	deck_btn = PixButton.new()
	deck_btn.text = "DECK"
	deck_btn.color = Color("53d4e2")
	deck_btn.position = Vector2(830, 456)
	deck_btn.size = Vector2(58, 20)
	deck_btn.pressed.connect(show_deck)
	root.add_child(deck_btn)
	var mute := PixButton.new()
	mute.text = "SND"
	mute.color = Color("9aa2ae")
	mute.position = Vector2(894, 456)
	mute.size = Vector2(58, 20)
	mute.pressed.connect(func(): Sfx.muted = not Sfx.muted; mute.text = "MUTE" if Sfx.muted else "SND")
	root.add_child(mute)
	for i in Run.belt_max():
		var bs := BeltSlot.new()
		bs.hud = self
		bs.idx = i
		bs.position = Vector2(830 + (i - (Run.belt_max() - 3)) * 41, 424)
		bs.size = Vector2(38, 30)
		root.add_child(bs)
	if b.practice():
		var lv := PixButton.new()
		lv.text = "LEAVE RANGE"
		lv.color = Color("62d26f")
		lv.position = Vector2(830, 394)
		lv.size = Vector2(122, 26)
		lv.pressed.connect(func(): Sfx.play("click"); b.leave_practice())
		root.add_child(lv)
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.visible = false
	root.add_child(modal)
	coach_box = Control.new()
	coach_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	coach_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(coach_box)
	for i in 5:
		var tg := Tag.new()
		tg.hud = self
		tg.position = Vector2(6, 434 + i * 26 if i < 4 else 408)  # a fifth for a guest (S3)
		tg.size = Vector2(150, 24)
		roster_box.add_child(tg)
		tags.append(tg)
	refresh()

func refresh() -> void:
	if b == null:
		return
	var sq := b.squad()
	for i in tags.size():
		tags[i].u = sq[i] if i < sq.size() else null
		tags[i].visible = i < sq.size()
	var u := b.sel
	var my_turn := b.state == "player" and not b.busy
	end_btn.disabled = not my_turn
	next_btn.disabled = not my_turn
	move_btn.disabled = not my_turn
	jet_btn.visible = my_turn and u != null and not u.dead and u.fuel_max > 0
	jet_btn.disabled = u == null or u.fuel <= 0
	jet_btn.position = Vector2(maxf(160.0, hand_x0 - 52), 410)
	# rebuild the hand when its contents change
	var want: Array = []
	if u != null and not u.dead and b.state == "player":
		want = u.hand
	var same := want.size() == cards.size()
	if same:
		for i in want.size():
			if cards[i].opt != want[i]:
				same = false
	if not same:
		for c in cards:
			c.queue_free()
		cards.clear()
		var n := want.size()
		var cw := 100.0
		var gap := 6.0
		# keep clear of the energy panel on the left and the belt/buttons on the right;
		# a big hand overlaps its cards instead of covering the panel
		var lo := 218.0
		var hi := 826.0
		var step := cw + gap
		if n > 1 and n * cw + (n - 1) * gap > hi - lo:
			step = (hi - lo - cw) / (n - 1)
		var total := cw + maxf(0, n - 1) * step
		var x0 := maxf(lo, 480 - total / 2.0)
		hand_x0 = x0
		for i in n:
			var cv := CardView.new()
			cv.opt = want[i]
			cv.hand_mode = true
			cv.size = Vector2(cw, 138)
			cv.base_y = 470
			cv.position = Vector2(x0 + i * step, 470)
			cv.hotkey = str(i + 1)
			var idx := i
			cv.pressed.connect(func(): b.select_card(idx))
			hand_box.add_child(cv)
			cards.append(cv)
	for i in cards.size():
		var cv: CardView = cards[i]
		var inst: Dictionary = cv.opt
		var c := Data.card(inst)
		cv.cost = b.card_cost(u, inst)
		cv.selected = b.card_idx == i
		cv.disabled = not my_turn or u.energy < cv.cost
		cv.supercharged = u.adr >= 50 and not inst.get("od", false) and Data.is_attack(c)
		cv.chain = b.chain_ready(u, inst) if my_turn else ""
	overlay.queue_redraw()

func _process(_d: float) -> void:
	if b == null:
		return
	if coach_queue.size() and coach_box.get_child_count() == 0 and b.state == "player" and not b.busy and not modal.visible and not deck_open:
		var cb := Coach.new()
		cb.hud = self
		coach_box.add_child(cb)
	# While a card is armed the hand sinks and fades, and over a unit it lets the click through,
	# so a Jackal lying behind the cards can still be aimed at and hit.
	targeting = b.card_idx >= 0 and b.state == "player"
	var over_unit: bool = targeting and b.unit_at_p(b.get_global_mouse_position()) != null
	var near_hand := hand_box.get_local_mouse_position().y > 440
	hand_box.modulate.a = lerpf(hand_box.modulate.a, (0.2 if near_hand else 0.45) if targeting else 1.0, 0.3)
	for cv in cards:
		cv.ghost = targeting
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE if over_unit else Control.MOUSE_FILTER_STOP
	# NEXT says how many soldiers can still act; once nobody can, it turns into END TURN.
	# The small END TURN button still asks twice while anyone can act.
	var n := b.ready_count() if b.state == "player" else 0
	if b.end_confirm_t > 0:
		end_btn.text = "AGAIN?"
		end_btn.color = Color("ffd23a") if b.t % 16 < 8 else Color("ff4d3d")
	else:
		end_btn.text = "END TURN"
		end_btn.color = Color("9aa2ae")
	if n > 0:
		next_btn.text = "NEXT"
		next_btn.sub = "%d CAN ACT" % n
		next_btn.color = Color("ff4d3d")
	elif b.state == "enemy":
		next_btn.text = "ENEMY TURN"
		next_btn.sub = ""
		next_btn.color = Color("9aa2ae")
	else:
		next_btn.text = "END TURN"
		next_btn.sub = "SPACE"
		next_btn.color = Color("ff4d3d") if b.t % 40 < 20 or b.state != "player" else Color("ff7a3d")

func preview_cost() -> int:
	## Energy the hovered (or armed) card would spend, for the blinking bolts.
	for cv in cards:
		if cv.hover and not cv.disabled:
			return cv.cost
	if b.card_idx >= 0 and b.card_idx < cards.size():
		return cards[b.card_idx].cost
	return 0

func hint_text() -> String:
	if b.state == "enemy":
		return "The Jackals are moving. Overwatch triggers automatically."
	var u := b.sel
	if b.state != "player" or u == null:
		return ""
	if b.jet_armed:
		return "JET BOOTS: hold the mouse button to fly toward the cursor. Let go to drop. Fuel %d/%d." % [u.fuel, u.fuel_max]
	if u.hang and b.card_idx < 0:
		return "TOP GUN: %s hangs at the top of the jump. Play an attack card for one mid-air shot (a kill is +15 adrenaline). Click the ground or ESC to drop." % u.def.name
	if b.card_idx >= 0 and b.card_idx < u.hand.size():
		var c := Data.card(u.hand[b.card_idx])
		if c.get("roll", false):
			return "COMBAT ROLL: click left or right of %s. Rolls through crawl-height gaps without using movement; the next Jackal shot goes over your head." % u.def.name
		if c.get("rush", false):
			return "OVERDRIVE: aim the launch. Anyone in the way gets smashed into the scenery."
		if c.get("drill", false):
			return "DRILL: aim through the terrain in your way. It bores until your movement runs out; click, SPACE or ESC stops it early."
		if c.get("eject", false):
			return "EJECT: aim the empty vehicle. It charges at the cursor and explodes; the driver pops out."
		if c.get("dog", "") == "bite":
			return "SIC 'EM: click a Jackal inside the ring around Rex. He leaps over and bites."
		if c.get("dog", "") == "fetch":
			return "FETCH: click loot, a crate or a POW inside the ring around Rex. He grabs it and brings it back."
		if c.get("girder", false):
			return "GIRDER: click where the beam goes, even in mid-air. Shoot its bolt later to drop it."
		if c.get("jump", false):
			return "JUMP PACK: aim the arc. You land soft. Landing in the push zone counts as a push."
		if c.get("beacon", false):
			return "BEACON: lob it onto the Jackals. Three bombs land there when their phase starts."
		if b.armed_fuse() != null:
			return "GRENADE: aim the throw. The mouse wheel (or [ and ]) sets the fuse from 1 to 4 seconds; the trail shows every bounce and where it bursts."
		return Data.TYPES[c.type].hint
	if u.move_left > 1:
		return "Click ground to move %s. Hold ALT for intel. Click a ladder top to climb. Ending in the push zone scrolls early and cuts the alert." % u.def.name
	return "%s is out of movement. Play cards, switch soldier (TAB) or end the turn." % u.def.name

# ---------------------------------------------------------------- modal: pick one
func pick(kind: String, title: String, sub: String, opts: Array, who = null) -> int:
	deck_open = false
	for c in modal.get_children():
		c.queue_free()
	var bg := ModalBG.new()
	bg.title = title
	bg.sub = sub
	bg.who = who
	bg.kind = kind
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(bg)
	var n := opts.size()
	var cw := 132.0
	var gap := 18.0
	var x0 := 480 - (n * cw + (n - 1) * gap) / 2.0 + (40 if who != null else 0)
	for i in n:
		var o: Dictionary = opts[i]
		var cv := CardView.new()
		cv.opt = o
		cv.size = Vector2(cw, 176)
		cv.position = Vector2(x0 + i * (cw + gap), 196)
		if o.get("label", "") != "":
			cv.label_top = o.label
		elif o.has("u"):
			cv.label_top = "TO %s" % o.u.def.name
		var idx := i
		cv.pressed.connect(func():
			Sfx.play("coin")
			picked.emit(-100 - idx if bg.banish else idx))
		modal.add_child(cv)
	var skip := PixButton.new()
	skip.text = {"level": "SKIP +15$", "loot": "TO STASH"}.get(kind, "SKIP")
	skip.color = Color("9aa2ae")
	skip.size = Vector2(120 if kind in ["level", "loot"] else 90, 26)
	skip.position = Vector2(480 - skip.size.x / 2, 392)
	skip.pressed.connect(func(): picked.emit(-1))
	modal.add_child(skip)
	if kind == "level":
		# P4: reroll the three options, or banish one from this soldier's pool for the run
		var rr := PixButton.new()
		rr.text = "REROLL (%d)" % Run.lvl_rerolls
		rr.color = Color("53d4e2")
		rr.size = Vector2(120, 26)
		rr.position = Vector2(480 - 60 - 130, 392)
		rr.disabled = Run.lvl_rerolls <= 0
		rr.pressed.connect(func(): picked.emit(-2))
		modal.add_child(rr)
		var bn := PixButton.new()
		bn.text = "BANISH (%d)" % Run.banishes
		bn.color = Color("ff7a3d")
		bn.size = Vector2(120, 26)
		bn.position = Vector2(480 + 60 + 10, 392)
		bn.disabled = Run.banishes <= 0
		bn.pressed.connect(func():
			bg.banish = not bg.banish
			bn.text = "PICK ONE TO BANISH" if bg.banish else "BANISH (%d)" % Run.banishes)
		modal.add_child(bn)
	# S6: check any deck before picking
	var who_i := 0
	if who != null and who is Unit:
		who_i = Run.soldiers.find(who.s)
	elif n and opts[0].has("u"):
		who_i = Run.soldiers.find(opts[0].u.s)
	elif b.sel != null:
		who_i = Run.soldiers.find(b.sel.s)
	modal.add_child(dossier_button(Vector2(700, 392), maxi(0, who_i)))
	modal.visible = true
	Sfx.play("levelup" if kind == "level" else "select")
	var r: int = await picked
	modal.visible = false
	for c in modal.get_children():
		c.queue_free()
	return r

func pick_grid(kind: String, title: String, sub: String, opts: Array, who = null) -> int:
	## A pick-one over many cards (a whole deck), in rows of eight.
	deck_open = false
	for c in modal.get_children():
		c.queue_free()
	var bg := ModalBG.new()
	bg.title = title
	bg.sub = sub
	bg.who = who
	bg.kind = "deck"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(bg)
	var cw := 84.0
	var per_row := 8
	for i in opts.size():
		var cv := CardView.new()
		cv.opt = opts[i]
		cv.size = Vector2(cw, 116)
		cv.position = Vector2(150 + (i % per_row) * (cw + 6), 156 + (i / per_row) * 128)
		if opts[i].get("label", "") != "":
			cv.label_top = opts[i].label
		var idx := i
		cv.pressed.connect(func(): Sfx.play("coin"); picked.emit(idx))
		modal.add_child(cv)
	var skip := PixButton.new()
	skip.text = "SKIP"
	skip.color = Color("9aa2ae")
	skip.size = Vector2(100, 26)
	skip.position = Vector2(430, 506)
	skip.pressed.connect(func(): picked.emit(-1))
	modal.add_child(skip)
	if who != null and who is Unit:
		modal.add_child(dossier_button(Vector2(540, 506), maxi(0, Run.soldiers.find(who.s))))
	modal.visible = true
	Sfx.play("select")
	var r: int = await picked
	modal.visible = false
	for c in modal.get_children():
		c.queue_free()
	return r

func show_deck() -> void:
	var u := b.sel
	if u == null:
		return
	if modal.visible:
		return
	for c in modal.get_children():
		c.queue_free()
	var bg := ModalBG.new()
	bg.title = "%s  LV%d  %s" % [u.def.name, u.s.lvl, u.def.cls.to_upper()]
	var perks: Array = u.s.perks.map(func(p): return Data.perk(u.def.key, p).name)
	var arch: Array = Run.archetypes(u.s).map(func(a): return "%s %s" % [a[0], ["I", "II", "III"][a[1] - 1]])
	bg.sub = "%s: %s   Abilities: %s%s" % [u.def.trait[0], u.def.trait[1], ", ".join(perks) if perks.size() else "none yet", ("   (" + ", ".join(arch) + ")") if arch.size() else ""]
	bg.who = u
	bg.kind = "deck"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(bg)
	var all: Array = []
	all.append_array(u.draw)
	all.append_array(u.hand.filter(func(c): return not c.get("od", false)))
	all.append_array(u.disc)
	var cw := 84.0
	var per_row := 8
	for i in all.size():
		var cv := CardView.new()
		cv.opt = all[i]
		cv.size = Vector2(cw, 116)
		cv.position = Vector2(150 + (i % per_row) * (cw + 6), 150 + (i / per_row) * 124)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		modal.add_child(cv)
	var close := PixButton.new()
	close.text = "CLOSE"
	close.color = Color("ffb23e")
	close.size = Vector2(100, 26)
	close.position = Vector2(430, 506)
	close.pressed.connect(close_deck)
	modal.add_child(close)
	var dz := dossier_button(Vector2(540, 506), maxi(0, Run.soldiers.find(u.s)))
	dz.pressed.connect(close_deck)
	modal.add_child(dz)
	modal.visible = true
	deck_open = true

func toggle_pause() -> void:
	## N7: Esc with nothing armed pauses the battle under a small menu.
	if get_tree().paused:
		return
	var pm := PauseMenu.new()
	pm.hud = self
	add_child(pm)
	get_tree().paused = true

func close_deck() -> bool:
	## Esc or CLOSE on the deck viewer. True when there was one to close.
	if not deck_open:
		return false
	deck_open = false
	modal.visible = false
	return true

func dossier_button(pos: Vector2, i: int) -> PixButton:
	var bt := PixButton.new()
	bt.text = "DOSSIER"
	bt.color = Color("53d4e2")
	bt.size = Vector2(110, 26)
	bt.position = pos
	bt.pressed.connect(func(): Sfx.play("click"); open_dossier(i))
	return bt

func open_dossier(i: int) -> Control:
	## S6: the HQ Dossier over the battle, read-only.
	return HubUI.field_dossier(self, i)

# ================================================================ widgets
class PixButton extends Control:
	signal pressed
	var text := ""
	var sub := ""
	var color := Color("ffb23e")
	var disabled := false
	var hover := false
	var small := false        # force the small font on a tall button
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): hover = true; queue_redraw())
		mouse_exited.connect(func(): hover = false; queue_redraw())
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if not disabled:
				pressed.emit()
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := color if not disabled else Color("4a505a")
		var press := 2.0 if hover and not disabled else 0.0
		draw_rect(Rect2(0, 2, w, h - 2), Color(0.05, 0.035, 0.03))
		draw_rect(Rect2(0, press, w, h - 2), Color(0.05, 0.035, 0.03))
		draw_rect(Rect2(1, 1 + press, w - 2, h - 4), c.darkened(0.35))
		draw_rect(Rect2(1, 1 + press, w - 2, h - 8), c)
		draw_rect(Rect2(1, 1 + press, w - 2, 2), c.lightened(0.35))
		for p in [Vector2(4, 4), Vector2(w - 6, 4)]:
			draw_rect(Rect2(p.x, p.y + press, 2, 2), c.darkened(0.5))
		var ty := (h - 2) / 2.0 + 5 + press
		if sub != "":
			ty -= 5
		# a label too wide for the big font drops to the small one instead of spilling past the edges
		var fs := 8 if h < 30 or small or Art.text_width(text, 16) > w - 12 else 16
		Art.text(self, text, Vector2(w / 2.0, ty), fs, Color.WHITE if not disabled else Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER, 2)
		if sub != "":
			Art.text(self, sub, Vector2(w / 2.0, ty + 12), 8, Color.WHITE if not disabled else Color("c8ccd2"), HORIZONTAL_ALIGNMENT_CENTER, 2)

class BeltSlot extends Control:
	## One consumable on the squad belt. Click to use it on the selected soldier.
	var hud
	var idx := 0
	var hover := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): hover = true)
		mouse_exited.connect(func(): hover = false)
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if idx < Run.belt.size():
				hud.b.use_belt(idx)
			else:
				Sfx.play("deny")
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var ink := Color(0.05, 0.035, 0.03)
		draw_rect(Rect2(0, 0, size.x, size.y), ink)
		draw_rect(Rect2(1, 1, size.x - 2, size.y - 2), Color("2a2e34") if not hover else Color("3a4048"))
		if idx >= Run.belt.size():
			Art.text(self, "BELT", Vector2(size.x / 2, 19), 8, Color("4a505a"), HORIZONTAL_ALIGNMENT_CENTER)
			return
		var it: Dictionary = Run.belt[idx]
		var icon: String = {"heal": "ic_heart", "ration": "ic_heart", "smoke": "ic_shield", "energy": "ic_bolt"}.get(Data.ITEMS[it.id].use, "ic_card")
		draw_texture_rect(Art.tex[icon], Rect2(size.x / 2 - 8, 3, 16, 16), false)
		Art.text(self, Data.item_name(it).split(" ")[0].to_upper().substr(0, 5), Vector2(size.x / 2, 28), 8, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER)
		if hover:
			var tip := "%s: %s" % [Data.item_name(it), Data.ITEMS[it.id].text]
			var tw := Art.text_width(tip, 16, true) + 12
			draw_rect(Rect2(size.x - tw, -24, tw, 20), Color(ink, 0.9))
			Art.text(self, tip, Vector2(size.x - 6, -9), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_RIGHT, 0, true)

class Tag extends Control:
	## A soldier's dog tag in the roster: portrait, name, level, HP and adrenaline.
	var hud
	var u: Unit = null
	var hover := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): hover = true)
		mouse_exited.connect(func(): hover = false)
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and u != null:
			accept_event()
			if hud.b.state == "player":
				hud.b.select_unit(u)
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		if u == null:
			return
		var w := size.x
		var h := size.y
		var sel: bool = u == hud.b.sel
		var base := Color("9aa2ae") if not u.dead else Color("4a3a3a")
		var x0 := 8.0 if sel else 0.0
		draw_rect(Rect2(x0, 0, w, h), Color(0.05, 0.035, 0.03))
		draw_rect(Rect2(x0 + 1, 1, w - 2, h - 2), base.darkened(0.25))
		draw_rect(Rect2(x0 + 1, 1, w - 2, 1), base.lightened(0.2))
		draw_circle(Vector2(x0 + 6, h / 2.0), 2.5, Color(0.05, 0.035, 0.03))
		if sel:
			draw_rect(Rect2(x0 - 1, -1, w + 2, h + 2), Color("ffd23a"), false, 1.0)
		elif hover:
			draw_rect(Rect2(x0, 0, w, h), Color(1, 1, 1, 0.5), false, 1.0)
		# portrait: head crop of the idle frame
		var m: Dictionary = Art.meta[u.sheet]
		draw_texture_rect_region(Art.tex[u.sheet], Rect2(x0 + 11, 1, 22, 22), Rect2(4, 2, 11, 11) if m.frame[0] == 24 else Rect2(6, 3, 11, 11))
		if u.dead:
			draw_texture_rect(Art.tex.ic_skull, Rect2(x0 + 16, 6, 12, 12), false)
		Art.draw_tags(self, Vector2(x0 + 20, 16), u.s.tags, 0.75)
		Art.text(self, u.def.name, Vector2(x0 + 36, 11), 8, Color.WHITE if not u.dead else Color("8a7a7a"))
		Art.text(self, "LV%d" % u.s.lvl, Vector2(x0 + w - 4, 11), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT)
		var b: Battle = hud.b
		if not u.dead and b.state == "player":
			# energy pips after the name, then a DONE stamp once they have nothing left
			var nb := maxi(3, u.energy)
			for i in nb:
				var bx := x0 + 74 + i * 7
				draw_rect(Rect2(bx, 4, 5, 7), Color(0.05, 0.035, 0.03))
				draw_rect(Rect2(bx + 1, 5, 3, 5), Color("ffd23a") if i < u.energy else Color("3b3f45"))
			if not b.can_act(u):
				draw_rect(Rect2(x0 + 1, 1, w - 2, h - 2), Color(0.05, 0.035, 0.03, 0.55))
				Art.text(self, "DONE", Vector2(x0 + w - 6, 20), 8, Color("ff4d3d"), HORIZONTAL_ALIGNMENT_RIGHT, 1)
		if not u.dead:
			var bw := w - 40
			draw_rect(Rect2(x0 + 36, 14, bw, 4), Color(0.05, 0.035, 0.03))
			draw_rect(Rect2(x0 + 36, 14, roundf(bw * u.hp / float(u.max_hp)), 4), Color("62d26f") if u.hp > u.max_hp * 0.3 else Color("ff4d3d"))
			draw_rect(Rect2(x0 + 36, 19, roundf(bw * u.adr / 100.0), 2), Color("ffb23e") if u.adr >= 100 else Color("ff7a3d"))
			var xp_lo := Run.xp_floor(u.s)
			var xp_hi := Run.xp_for_next(u.s)
			var f := clampf(float(u.s.xp - xp_lo) / maxf(1, xp_hi - xp_lo), 0, 1)
			draw_rect(Rect2(x0 + 36, 22, roundf(bw * f), 1), Color("53d4e2"))
		else:
			Art.text(self, "DOWN" if u.downed else "KIA", Vector2(x0 + 36, 21), 8, Color("ffb23e") if u.downed else Color("ff4d3d"))

class PauseMenu extends Control:
	## N7: RESUME, CONTROLS, QUIT TO TITLE. Runs while the tree is paused.
	var hud
	var page := "menu"     # "menu", "controls" or "quit"
	const CONTROLS := [
		["CLICK A CARD / 1-9", "Arm a card, then click to fire"],
		["RIGHT-CLICK / ESC", "Cancel the armed card"],
		["CLICK GROUND", "Walk the selected soldier"],
		["CLICK A SOLDIER / TAB, E, Q", "Select a soldier"],
		["SPACE", "NEXT: the next soldier who can act"],
		["ENTER", "END TURN (asks twice while anyone can act)"],
		["M", "Auto-move with mobility cards"],
		["WHEEL / [ ]", "Set a grenade's fuse"],
		["SHIFT", "Hold a steady aim"],
		["ALT / V", "Intel on every soldier"],
		["J", "Jet Boots, when equipped"],
	]
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		build()
	func build() -> void:
		for c in get_children():
			c.queue_free()
		var opts: Array = []
		match page:
			"menu":
				opts = [["RESUME", Color("62d26f"), resume], ["CONTROLS", Color("53d4e2"), func(): go("controls")], ["QUIT TO TITLE", Color("ff4d3d"), func(): go("quit")]]
			"controls":
				opts = [["BACK", Color("9aa2ae"), func(): go("menu")]]
			"quit":
				opts = [["QUIT", Color("ff4d3d"), quit], ["STAY", Color("62d26f"), func(): go("menu")]]
		var y := 300.0 if page != "controls" else 430.0
		if page == "menu":
			y = 210.0
		for i in opts.size():
			var bt := PixButton.new()
			bt.process_mode = Node.PROCESS_MODE_ALWAYS
			bt.text = opts[i][0]
			bt.color = opts[i][1]
			bt.size = Vector2(240, 36)
			if page == "quit":
				bt.position = Vector2(480 - 250 + i * 260, y)
			else:
				bt.position = Vector2(360, y + i * 46)
			bt.pressed.connect(opts[i][2])
			add_child(bt)
	func go(p: String) -> void:
		Sfx.play("click")
		page = p
		build()
	func resume() -> void:
		Sfx.play("click")
		get_tree().paused = false
		queue_free()
	func quit() -> void:
		get_tree().paused = false
		var main = hud.get_parent()
		if Run.campaign():
			# like closing the window mid-op: the war rolls back to the last HQ save
			Run.load_campaign(int(Run.camp.slot))
		main.show_title()
	func _input(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and not ev.echo:
			if ev.keycode == KEY_ESCAPE:
				if page == "menu":
					resume()
				else:
					go("menu")
			get_viewport().set_input_as_handled()
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 540), Color(0.02, 0.02, 0.04, 0.8))
		var r := Rect2(220, 110, 520, 380) if page == "controls" else Rect2(280, 130, 400, 220 if page == "menu" else 240)
		if page == "quit":
			r = Rect2(200, 170, 560, 190)
		draw_rect(r.grow(2), Color(0.05, 0.035, 0.03))
		draw_rect(r, Color("2a2e34"))
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 2), Color("6c7480"))
		match page:
			"menu":
				Art.text(self, "PAUSED", Vector2(480, 172), 32, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 3)
			"controls":
				Art.text(self, "CONTROLS", Vector2(480, 140), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 2)
				for i in CONTROLS.size():
					Art.text(self, CONTROLS[i][0], Vector2(470, 172 + i * 22), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT)
					Art.text(self, CONTROLS[i][1], Vector2(490, 172 + i * 22), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
			"quit":
				Art.text(self, "QUIT TO TITLE?", Vector2(480, 210), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 2)
				var line := "This op is lost. The war picks up from your last HQ save." if Run.campaign() else "This run is lost. Salvage, bio-parts, HQ upgrades and unlocks you already earned are kept."
				Art.text(self, line, Vector2(480, 246), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)

class Coach extends Control:
	## N1/N5: new-player tips in the Quartermaster's box style. NEXT pages through the queue;
	## SKIP drops the rest; DON'T SHOW AGAIN turns every tip off for good.
	var hud
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var x := 560.0
		for bb in [["NEXT", 0], ["SKIP", 1], ["DON'T SHOW AGAIN", 2]]:
			var bt := PixButton.new()
			bt.text = bb[0]
			bt.color = Color("ffd23a") if bb[1] == 0 else Color("9aa2ae")
			bt.size = Vector2(Art.text_width(bb[0], 8) + 30, 22)
			bt.position = Vector2(x, 118)
			x += bt.size.x + 8
			var k: int = bb[1]
			bt.pressed.connect(func(): press(k))
			add_child(bt)
	func press(k: int) -> void:
		Sfx.play("click")
		if k == 2:
			Run.meta["tips_off"] = true
			Run.save_meta()
		if k == 0 and hud.coach_queue.size() > 1:
			hud.coach_queue.pop_front()
			return
		hud.coach_queue.clear()
		queue_free()
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			accept_event()
			if ev.button_index == MOUSE_BUTTON_LEFT:
				press(0)
	func _input(ev: InputEvent) -> void:
		# keys page the tips too, and never reach the battle underneath
		if ev is InputEventKey and ev.pressed and not ev.echo:
			if ev.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
				press(0)
			elif ev.keycode == KEY_ESCAPE:
				press(1)
			get_viewport().set_input_as_handled()
	func _process(_d: float) -> void:
		if hud.coach_queue.is_empty():
			queue_free()
		queue_redraw()
	func _draw() -> void:
		if hud.coach_queue.is_empty():
			return
		var pg: Array = hud.coach_queue[0]
		draw_rect(Rect2(0, 0, 960, 540), Color(0.02, 0.02, 0.04, 0.35))
		var r := Rect2(24, 34, 912, 112)
		draw_rect(r, Color(0.05, 0.035, 0.03, 0.96))
		draw_rect(r, Color("ffd23a"), false, 2.0)
		draw_rect(Rect2(36, 46, 60, 60), Color("2e3a24"))
		Art.text(self, pg[0], Vector2(66, 82), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 2)
		var more: int = hud.coach_queue.size() - 1
		Art.text(self, pg[1] + ("   %d MORE" % more if more > 0 else ""), Vector2(110, 56), 8, Color("ffd23a"))
		var y := 78.0
		for ln in CardView.wrap_text(pg[2], 800, 16):
			Art.text(self, ln, Vector2(110, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
			y += 16

class ModalBG extends Control:
	var title := ""
	var sub := ""
	var who = null
	var kind := ""
	var banish := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 540), Color(0.02, 0.02, 0.04, 0.78))
		var r := Rect2(100, 120, 760, 310) if kind != "deck" else Rect2(60, 70, 840, 466)
		draw_rect(r.grow(2), Color(0.05, 0.035, 0.03))
		draw_rect(r, Color("3a3f48"))
		draw_rect(r.grow(-3), Color("2a2e34"))
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 2), Color("6c7480"))
		for p in [r.position + Vector2(6, 6), Vector2(r.end.x - 8, r.position.y + 6), Vector2(r.position.x + 6, r.end.y - 8), r.end - Vector2(8, 8)]:
			draw_rect(Rect2(p, Vector2(2, 2)), Color("9aa2ae"))
		# hazard strip header
		var hz: Texture2D = Art.tex.ui_hazard
		var x := r.position.x
		while x < r.end.x:
			draw_texture_rect_region(hz, Rect2(x, r.position.y - 16, minf(32, r.end.x - x), 8), Rect2(0, 0, minf(32, r.end.x - x), 8))
			x += 32
		Art.text(self, title, Vector2(480, r.position.y + 30), 16, Color("ffd23a") if kind == "level" else Color("ffb23e"), HORIZONTAL_ALIGNMENT_CENTER, 2)
		var y := r.position.y + 52
		for line in CardView.wrap_text(sub, r.size.x - 60, 16):
			Art.text(self, line, Vector2(480, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 0, true)
			y += 14
		if who != null and who is Unit and kind != "deck":
			var t := Time.get_ticks_msec() / 160
			Art.draw_char(self, who.sheet, "cheer", t % 2, Vector2(170, 360), 1, false, 0, 1.0, 0, false, 2.5)
			# the title names the level being picked for (it can trail the soldier's level when several queue up)
			var lv: int = title.get_slice(" ", title.get_slice_count(" ") - 1).to_int() if kind == "level" else 0
			Art.text(self, "LV %d" % (lv if lv > 0 else who.s.lvl), Vector2(170, 384), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
		if kind == "level":
			Art.text(self, "Abilities follow the soldier's two specialist paths (gold label): MINOR, then MAJOR, then CAPSTONE.", Vector2(480, 448), 16, Color("c9bfa8"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
			Art.text(self, "REROLL deals three new options.  BANISH removes one option from this soldier's pool for the run.", Vector2(480, 463), 16, Color("c9bfa8"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
		elif who != null and kind == "deck":
			Art.draw_char(self, who.sheet, "idle", (Time.get_ticks_msec() / 200) % 4, Vector2(100, 200), 1, false, 0, 1.0, 0, true, 2.0)

class Overlay extends Control:
	## Top bar, boss bar, log, hint, the selected soldier's action panel and banners.
	var hud
	func _process(_d: float) -> void:
		queue_redraw()
	func draw_action_panel(b: Battle) -> void:
		## Big energy bolts and a movement gauge for the selected soldier, docked left of the hand.
		var u: Unit = b.sel
		if b.state != "player" or u == null or u.dead:
			return
		var ink := Color(0.05, 0.035, 0.03)
		var r := Rect2(maxf(160.0, hud.hand_x0 - 52), 440, 46, 98)
		draw_rect(r.grow(1), ink)
		draw_rect(r, Color(0.16, 0.18, 0.2, 0.94))
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), Color("6c7480"))
		Art.text(self, "ENERGY", Vector2(r.get_center().x, r.position.y + 10), 8, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER)
		var cost: int = hud.preview_cost()
		var slots := clampi(maxi(3, u.energy), 3, 8)
		for i in slots:
			var bx := r.position.x + 4 + (i % 2) * 20
			var by := r.position.y + 14 + (i / 2) * 15
			var full := i < u.energy
			var spend := full and i >= u.energy - cost
			draw_rect(Rect2(bx, by, 18, 14), ink)
			if full:
				var a := 1.0
				if spend:
					a = 0.3 + 0.7 * float(b.t % 20 < 10)
				draw_rect(Rect2(bx + 1, by + 1, 16, 12), Color(0.4, 0.33, 0.08, a))
				draw_texture_rect(Art.tex.ic_bolt, Rect2(bx + 3, by + 1, 12, 12), false, Color(1, 1, 1, a))
			else:
				draw_rect(Rect2(bx + 1, by + 1, 16, 12), Color("2b2f35"))
		# C1 momentum: three purple pips, the third card played this turn refunds an energy
		var mom := u.played % Data.MOMENTUM
		for i in Data.MOMENTUM:
			var px := r.end.x + 3
			var py := r.position.y + 14 + i * 10
			draw_rect(Rect2(px, py, 7, 8), ink)
			draw_rect(Rect2(px + 1, py + 1, 5, 6), Color("b48cff") if i < mom else Color("2b2f35"))
		if mom == Data.MOMENTUM - 1 and b.t % 30 < 20:
			Art.text(self, "+1", Vector2(r.end.x + 7, r.position.y + 50), 8, Color("b48cff"), HORIZONTAL_ALIGNMENT_CENTER)
		var mv := maxf(0.0, u.move_left)
		var full_mv: float = maxf(1.0, b.full_move(u))
		var my := r.end.y - 26
		Art.text(self, "MOVE", Vector2(r.get_center().x, my), 8, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER)
		draw_rect(Rect2(r.position.x + 3, my + 3, 40, 7), ink)
		draw_rect(Rect2(r.position.x + 4, my + 4, 38.0 * clampf(mv / full_mv, 0, 1), 5), Color("62d26f") if mv > 1 else Color("4a505a"))
		if mv > full_mv:
			draw_rect(Rect2(r.position.x + 4, my + 4, 38, 1), Color("b48cff"))
		Art.text(self, "%d" % int(mv), Vector2(r.get_center().x, my + 21), 8, Color("62d26f") if mv > 1 else Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER)

	func _draw() -> void:
		var b: Battle = hud.b
		if b == null:
			return
		var ink := Color(0.05, 0.035, 0.03)
		# riveted metal top plate
		draw_rect(Rect2(0, 0, 960, 34), ink)
		draw_rect(Rect2(0, 0, 960, 32), Color("2a2e34"))
		draw_rect(Rect2(0, 0, 960, 2), Color("6c7480"))
		draw_rect(Rect2(0, 30, 960, 2), Color("1a1d22"))
		for x in range(8, 960, 120):
			draw_rect(Rect2(x, 4, 2, 2), Color("9aa2ae"))
			draw_rect(Rect2(x, 26, 2, 2), Color("9aa2ae"))
		var hz: Texture2D = Art.tex.ui_hazard
		for x in range(0, 960, 32):
			draw_texture_rect_region(hz, Rect2(x, 32, 32, 4), Rect2(0, 2, 32, 4))
		Art.text(self, "SCORE", Vector2(14, 14), 8, Color("ffb23e"))
		Art.text(self, str(b.score).pad_zeros(7), Vector2(14, 28), 8, Color.WHITE)
		draw_texture_rect(Art.tex.ic_coin, Rect2(90, 18, 10, 10), false)
		Art.text(self, "%d" % Run.scrip, Vector2(104, 28), 8, Color("ffd23a"))
		Art.text(self, "M%d %s" % [b.mission_idx + 1, b.mission.name], Vector2(150, 14), 8, Color("e8dcc2"))
		# alert siren bulbs
		var ax := 384.0
		Art.text(self, "ALERT", Vector2(ax - 6, 22), 8, Color("ff4d3d") if b.alert >= 10 and b.t % 30 < 15 else Color("e8dcc2"), HORIZONTAL_ALIGNMENT_RIGHT)
		for i in 10:
			var on := i < b.alert
			var key := "ui_bulb_off"
			if on:
				key = "ui_bulb_g" if i < 3 else ("ui_bulb_y" if i < 6 else "ui_bulb_r")
			var flick := on and i == b.alert - 1 and b.stalled() and b.t % 20 < 10
			draw_texture_rect(Art.tex[key], Rect2(ax + i * 20, 6 if not flick else 5, 20, 24), false)
		var info_x := ax + 206
		if b.stalled() and b.state != "title":
			Art.text(self, "STALLED!", Vector2(info_x, 15), 8, Color("ff4d3d") if b.t % 40 < 20 else Color("ff7a3d"))
		if b.radio_t != null and b.state != "title":
			draw_texture_rect(Art.tex.ic_radio, Rect2(info_x, 18, 10, 10), false)
			Art.text(self, "BACKUP %d" % b.radio_t, Vector2(info_x + 14, 28), 8, Color("ff4d3d") if b.radio_t <= 1 and b.t % 30 < 15 else Color("ffd23a"))
		# wind sock
		var wx := 700.0
		Art.text(self, "WIND", Vector2(wx, 14), 8, Color("e8dcc2"))
		draw_rect(Rect2(wx + 100, 6, 2, 24), Color("9aa2ae"))
		var n := absi(b.wind)
		var dirn := signf(b.wind) if b.wind != 0 else 1.0
		for k in 4:
			var on := k < int(ceil(n / 1.5))
			var flap := sin(b.t / 5.0 + k) * (1.5 if on else 0.5)
			var sx := wx + 101 + dirn * (k * 9) - (9 if dirn < 0 else 0)
			var col := (Color("ff4d3d") if k % 2 == 0 else Color.WHITE) if on else Color("4a505a")
			var hgt := 8.0 - k * 1.2 if on else 3.0
			draw_rect(Rect2(sx, 8 + (8 - hgt) / 2 + flap + (0 if on else 6), 9, hgt), col)
		Art.text(self, str(n) if n else "CALM", Vector2(wx + 150, 28), 8, Color("53d4e2") if n <= 4 else Color("ff7a3d"))
		Art.text(self, "RND", Vector2(912, 14), 8, Color("e8dcc2"))
		Art.text(self, str(b.round_n), Vector2(912, 28), 8, Color.WHITE)
		var jl: String = b.job_left()
		if jl != "":
			Art.text(self, jl, Vector2(480, 52), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
		# boss bar
		var boss = null
		for u in b.units:
			if u.type == "boss" or u.type == "hiveship":
				boss = u
		if boss == null or not b.boss_active:
			for u in b.units:
				if u.type == "queen" and u.active and not u.dead:
					boss = u
		if boss != null and boss.type == "queen":
			var bw := 360.0
			var bx := 480 - bw / 2
			Art.text(self, "BURROW QUEEN" + ("  UNDERGROUND: BLASTS ONLY" if boss.weight == "buried" else "  SURFACED: HIT HER NOW"), Vector2(bx, 52), 8, Color("c47bff") if boss.weight == "buried" else Color("9df25c"))
			draw_rect(Rect2(bx - 2, 56, bw + 4, 12), ink)
			draw_rect(Rect2(bx, 58, bw, 8), Color("2a0d3a"))
			draw_rect(Rect2(bx, 58, bw * boss.hp / float(boss.max_hp), 8), Color("b06ae0"))
		elif boss != null and boss.type == "hiveship" and b.boss_active and not boss.dead:
			var bw := 360.0
			var bx := 480 - bw / 2
			var plated: bool = b.ship_plated(boss)
			Art.text(self, "HIVE SHIP" + ("  PLATED: SHOOT THE PLATES DOWN, BLAST THE BELLY" if plated else "  HULL EXPOSED"), Vector2(bx, 52), 8, Color("c47bff") if plated else Color("9df25c"))
			draw_rect(Rect2(bx - 2, 56, bw + 4, 12), ink)
			draw_rect(Rect2(bx, 58, bw, 8), Color("2a0d3a"))
			draw_rect(Rect2(bx, 58, bw * boss.hp / float(boss.max_hp), 8), Color("b06ae0"))
		elif boss != null and b.boss_active and not boss.dead:
			var bw := 360.0
			var bx := 480 - bw / 2
			var bname := "VHARR BOAR" if boss.fl.get("vharr", false) else ("ROOKIE BOAR" if boss.fl.get("rookie", false) else "IRON BOAR")
			if boss.dome > 0:
				Art.text(self, bname + "  DOMED: CRUSH OR MELEE IT", Vector2(bx, 52), 8, Color("9df25c"))
			else:
				Art.text(self, bname + ("  ARMORED: CRUSH IT TO CRACK" if boss.plate > 0 else "  ARMOR CRACKED"), Vector2(bx, 52), 8, Color("9fb4c9") if boss.plate > 0 else Color("ffb23e"))
			draw_rect(Rect2(bx - 2, 56, bw + 4, 12), ink)
			draw_rect(Rect2(bx, 58, bw, 8), Color("3a0d0d"))
			draw_rect(Rect2(bx, 58, bw * boss.hp / float(boss.max_hp), 8), Color("ff4d3d"))
			if boss.plate > 0:
				draw_rect(Rect2(bx, 58, bw * minf(1, boss.plate / float(b.mission.plate)), 2), Color("9fb4c9"))
		# log
		var ly := 52.0 if boss == null or (not b.boss_active and boss.type != "queen") else 84.0
		for i in b.log_lines.size():
			var a := 0.55 + 0.45 * float(i + 1) / b.log_lines.size()
			Art.text(self, b.log_lines[i], Vector2(10, ly + i * 14), 16, Color(0.91, 0.86, 0.76, a), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		draw_action_panel(b)
		# U1 kill feed, top right: KILLER [HOW] VICTIM, sliding in, with a flashing stamp for the good ones
		var fy := 50.0
		for f in b.feed:
			var al: float = clampf((480 - f.t) / 40.0, 0, 1)
			var slide: float = maxf(0, 1 - f.t / 8.0) * 160
			var segs := [[f.killer, f.kc], [" [" + f.how + "] ", Color("e8dcc2")], [f.victim, f.vc]]
			var w := 0.0
			for sg in segs:
				w += Art.text_width(sg[0], 8)
			var sw: float = Art.text_width(f.stamp, 8) + 8 if f.stamp != "" else 0.0
			var x0 := 950 - w - sw + slide
			draw_rect(Rect2(x0 - 6, fy - 10, w + sw + 12, 14), Color(0.05, 0.035, 0.03, 0.78 * al))
			draw_rect(Rect2(x0 - 6, fy - 10, 3, 14), Color(f.kc, al))
			var x := x0
			for sg in segs:
				Art.text(self, sg[0], Vector2(x, fy), 8, sg[1], HORIZONTAL_ALIGNMENT_LEFT, 2, false, al)
				x += Art.text_width(sg[0], 8)
			if f.stamp != "":
				var hot: bool = f.t < 60 and f.t % 8 < 4
				Art.text(self, f.stamp, Vector2(x + 8, fy), 8, Color("ff4d3d") if hot else Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2, false, al)
			fy += 16
		# C6 kill combo meter, top right under the feed
		if b.combo >= 2 and b.state == "player":
			var cx := 940.0
			var cy := maxf(100.0, fy + 14)
			var pulse := 1.0 + 0.1 * sin(b.t / 4.0)
			Art.text(self, "COMBO x%d" % b.combo, Vector2(cx, cy + pulse), 16, Color("ff7a3d") if b.combo < 5 else Color("b48cff"), HORIZONTAL_ALIGNMENT_RIGHT, 2)
			var nxt := "x3: SQUAD +10 ADRENALINE" if b.combo < 3 else ("x5: NEXT CRATE +1 RARITY" if b.combo < 5 else "CRATE BONUS READY")
			Art.text(self, nxt, Vector2(cx, cy + 16), 8, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_RIGHT)
		# hint strip above the hand
		var h: String = hud.hint_text()
		if h != "":
			var lines := CardView.wrap_text(h, 640, 16)
			var hw := 0.0
			for l in lines:
				hw = maxf(hw, Art.text_width(l, 16, true))
			var top := 426.0 - lines.size() * 14
			var strip := Rect2(480 - hw / 2 - 8, top - 2, hw + 16, lines.size() * 14 + 4)
			# aiming at something behind the strip: fade it nearly away
			var al := 0.2 if hud.targeting and strip.grow(24).has_point(get_local_mouse_position()) else 1.0
			# a hovered card lifts into the strip's spot: get out of its way
			if hud.cards.any(func(cv): return cv.hover):
				al = 0.0
			draw_rect(strip, Color(0.05, 0.035, 0.03, 0.7 * al))
			for i in lines.size():
				Art.text(self, lines[i], Vector2(480, top + 11 + i * 14), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 0, true, al)
		if b.state == "enemy":
			var who: String = ("ENEMY: " + Data.ETYPES[b.acting.type].name.to_upper()) if b.acting != null else "ENEMY PHASE"
			Art.text(self, who, Vector2(480, 402), 8, Color("ff4d3d"), HORIZONTAL_ALIGNMENT_CENTER)
		# banner: a stencil plate that slams in from the left
		if b.banners.size():
			var bn: Dictionary = b.banners[0]
			var k := minf(1, bn.t / 8.0)
			var out: float = (bn.dur - bn.t) / 12.0 if bn.t > bn.dur - 12 else 1.0
			var al := clampf(out, 0, 1)
			var hgt := 92.0 if bn.sub != "" else 70.0
			draw_rect(Rect2(0, 170, 960, hgt), Color(0, 0, 0, 0.55 * al))
			draw_rect(Rect2(0, 170, 960, 2), Color(bn.c, 0.8 * al))
			draw_rect(Rect2(0, 170 + hgt - 2, 960, 2), Color(bn.c, 0.8 * al))
			var sz := 32 if Art.text_width(bn.text, 32) < 900 else 16
			Art.text(self, bn.text, Vector2(480 + (1 - k) * -300, 226), sz, bn.c, HORIZONTAL_ALIGNMENT_CENTER, 3, false, al)
			if bn.sub != "":
				Art.text(self, bn.sub, Vector2(480, 252), 8, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, false, al)

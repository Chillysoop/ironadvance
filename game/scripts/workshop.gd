extends Control
## The Workshop: every change to a card happens here (B1). Five services, each saying what it
## does and what it could do for the squad right now. Pick a service, then a soldier, and their
## Dossier opens on the cards it can touch. Fusions and evolutions that are ready get a
## one-click shortcut.

signal done

const HudScript := preload("res://scripts/hud.gd")
const HubUI := preload("res://scripts/hub_ui.gd")
const Services := preload("res://scripts/services.gd")
const DossierScript := preload("res://scripts/dossier.gd")

const BAR := Vector2(16, 80)

var picking := ""            # the service waiting for a soldier pick, "" when none
var bar: Control = null
var sub: Control = null      # an open Dossier
var t := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	build()

func living() -> Array:
	return Run.soldiers.filter(func(s): return s.alive)

func eligible(id: String, s: Dictionary) -> Array:
	## The cards in this soldier's deck the service could work on (scrip aside).
	match id:
		"polish": return s.deck.filter(func(c): return Services.polish_info(s, c).line != "")
		"gunsmith": return s.deck.filter(func(c): return Services.gunsmith_info(s, c).line != "")
		"fuse": return s.deck.filter(func(c): return Services.fuse_info(s, c).ok)
		"evolve": return s.deck.filter(func(c): return Services.evolve_info(s, c).ok)
		"burn": return s.deck.filter(func(c): return Services.burn_info(s, c).line != "")
	return []

func closest_fuse() -> String:
	## The nearest fusion when none is ready: "Moss has 2 Common Rifle Shots."
	var best := ""
	var n := 1
	for s in living():
		for c in s.deck:
			var g := Services.fuse_group(s, c).size()
			if g > n and g < 3:
				n = g
				best = "Closest: %s has %d %s %s." % [s.def.name, g, Data.tier_name(Data.tier_of(c)).capitalize(), Data.card(c).name]
	return best

func closest_evolve() -> String:
	for s in living():
		for c in s.deck:
			if not Services.evolve_rule(c).is_empty():
				return "%s's %s: %s" % [s.def.name, Data.card(c).name, Services.evolve_info(s, c).why]
	return "Evolving cards: %s, each with its kit, at Epic." % ", ".join(Data.EVOLUTIONS.map(func(e): return Data.CARDS[e.card].name))

func services() -> Array:
	## [id, title, price, description, status when usable, reason when not, usable]
	var al := living()
	var count := func(id: String) -> int:
		return al.reduce(func(a, s): return a + eligible(id, s).size(), 0)
	var ready_f: Array = []
	for s in al:
		for g in Run.fusable(s):
			ready_f.append("%s: 3 %s %s" % [s.def.name, Data.tier_name(Data.tier_of(g[0])).capitalize(), Data.card(g[0]).name])
	var ready_e: Array = []
	for s in al:
		for e in Run.evolutions(s):
			ready_e.append("%s: %s into %s" % [s.def.name, Data.card(e.card).name, Data.CARDS[e.rule.into].name])
	var pp := Services.price(Services.POLISH)
	var mp := Services.price(Data.MOD_PRICE)
	var bp := Services.price(Services.BURN)
	var np: int = count.call("polish")
	var nm: int = count.call("gunsmith")
	var nb: int = count.call("burn")
	return [
		["polish", "POLISH", pp, "Raise one card a rarity. Bigger numbers, same energy cost.",
			"%d cards can be polished." % np, "No card can go higher." if np == 0 else Services.short(pp), np > 0 and Run.scrip >= pp],
		["gunsmith", "GUNSMITH", mp, "Bolt a mod onto a card: pierce, more pellets, a cheaper cost. Each card holds %d." % Data.MAX_MODS,
			"%d cards have room for a mod." % nm, "Every card is fully modded." if nm == 0 else Services.short(mp), nm > 0 and Run.scrip >= mp],
		["fuse", "FUSE", 0, "Three copies of a card at one rarity become one copy a rarity higher.",
			"Ready: " + "; ".join(ready_f) + "." if ready_f.size() else "", "No three-of-a-kind yet. " + closest_fuse(), ready_f.size() > 0],
		["evolve", "EVOLVE", 0, "An Epic card plus its matching kit becomes a new weapon card.",
			"Ready: " + "; ".join(ready_e) + "." if ready_e.size() else "", closest_evolve(), ready_e.size() > 0],
		["burn", "BURN", bp, "Remove a card for good, so the rest of the deck comes up more often.",
			"Decks keep at least %d cards." % Services.MIN_DECK, "Every deck is down to %d cards." % Services.MIN_DECK if nb == 0 else Services.short(bp), nb > 0 and Run.scrip >= bp],
	]

func build() -> void:
	for c in get_children():
		c.queue_free()
	sub = null
	bar = HubUI.SquadBar.new()
	bar.position = BAR
	bar.picked.connect(on_pick)
	if picking != "":
		bar.pickable = []
		for i in Run.soldiers.size():
			if Run.soldiers[i].alive and eligible(picking, Run.soldiers[i]).size() > 0:
				bar.pickable.append(i)
	add_child(bar)
	var svs := services()
	var tw := (928.0 - 4 * 8) / 5.0
	for i in svs.size():
		var sv: Array = svs[i]
		var tile := HubUI.ActionTile.new()
		tile.title = sv[1]
		tile.cost = sv[2]
		tile.desc = sv[3]
		tile.line = sv[4]
		tile.why = sv[5]
		tile.ok = sv[6]
		tile.color = Color("b48cff") if sv[0] in ["fuse", "evolve"] else (Color("ff4d3d") if sv[0] == "burn" else Color("53d4e2"))
		tile.size = Vector2(tw, 132)
		tile.position = Vector2(16 + i * (tw + 8), 150)
		var id: String = sv[0]
		tile.pressed.connect(func(): start_pick(id))
		add_child(tile)
	# shortcuts straight to a ready fusion or evolution
	var x := 16.0
	var y := 330.0
	for s in living():
		for g in Run.fusable(s):
			x = shortcut("%s: FUSE 3 %s" % [s.def.name, Data.card(g[0]).name.to_upper()], s, g[0], "fuse", x, y)
		for e in Run.evolutions(s):
			x = shortcut("%s: EVOLVE %s" % [s.def.name, Data.card(e.card).name.to_upper()], s, e.card, "evolve", x, y)
	if picking != "":
		var cancel := HudScript.PixButton.new()
		cancel.text = "CANCEL"
		cancel.color = Color("9aa2ae")
		cancel.size = Vector2(130, 34)
		cancel.position = Vector2(16, 488)
		cancel.pressed.connect(func(): picking = ""; build())
		add_child(cancel)
	var back := HudScript.PixButton.new()
	back.text = "<< BACK TO HQ"
	back.color = Color("ff4d3d")
	back.size = Vector2(190, 44)
	back.position = Vector2(746, 482)
	back.pressed.connect(func(): Sfx.play("click"); done.emit())
	add_child(back)

func shortcut(label: String, s: Dictionary, c: Dictionary, id: String, x: float, y: float) -> float:
	var bt := HudScript.PixButton.new()
	bt.text = label
	bt.color = Color("b48cff")
	bt.size = Vector2(Art.text_width(label, 8) + 24, 26)
	if x + bt.size.x > 944:
		return x
	bt.position = Vector2(x, y)
	bt.pressed.connect(func(): open_dossier(Run.soldiers.find(s), "fuse", c, id))
	add_child(bt)
	return x + bt.size.x + 8

func start_pick(id: String) -> void:
	picking = id
	build()

func on_pick(i: int) -> void:
	var filt: String = {"polish": "polish", "gunsmith": "mod", "fuse": "fuse", "evolve": "fuse", "burn": "burn"}.get(picking, "")
	picking = ""
	open_dossier(i, filt)

func open_dossier(i: int, filt := "", sel = null, preview := "") -> void:
	Sfx.play("click")
	var d: Control = DossierScript.new()
	d.idx = i
	d.filt = filt
	d.sel = sel
	d.done.connect(func(): build())
	add_child(d)
	sub = d
	if preview != "":
		d.open_preview(preview)

func _input(ev: InputEvent) -> void:
	if picking != "" and ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		picking = ""
		build()

func _process(_d: float) -> void:
	t += 1
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color("1a1d22"))
	for y in range(0, 540, 24):
		for x in range(0, 960, 24):
			draw_texture_rect(Art.tex.ui_panel, Rect2(x, y, 24, 24), false, Color(0.5, 0.55, 0.6))
	for x in range(0, 960, 32):
		draw_texture_rect(Art.tex.ui_hazard, Rect2(x, 0, 32, 8), false)
	Art.text(self, "WORKSHOP", Vector2(24, 60), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
	Art.text(self, "Change cards. Pick a service, then a soldier. You see the result before you pay.", Vector2(184, 58), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
	var sc := "%d SCRIP" % Run.scrip
	draw_texture_rect(Art.tex.ic_coin, Rect2(936 - Art.text_width(sc, 16) - 22, 44, 16, 16), false)
	Art.text(self, sc, Vector2(936, 60), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT, 2)
	Art.text(self, "CARD SERVICES", Vector2(16, 142), 8, Color("53d4e2"))
	Art.text(self, "READY NOW", Vector2(16, 322), 8, Color("b48cff"))
	var any := living().any(func(s): return Run.fusable(s).size() > 0 or Run.evolutions(s).size() > 0)
	if not any:
		Art.text(self, "Nothing to fuse or evolve yet. Buy or level into a third copy of a card to fuse it.", Vector2(16, 346), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
	Art.text(self, "Or open any soldier from the bar above: select a card in their deck to see every service for it.", Vector2(16, 400), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
	if picking != "":
		var by := 300.0
		draw_rect(Rect2(0, by, 960, 50), Color(0.05, 0.035, 0.03, 0.94))
		draw_rect(Rect2(0, by, 960, 2), Color("ffd23a"))
		draw_rect(Rect2(0, by + 48, 960, 2), Color("ffd23a"))
		Art.text(self, "%s WHOSE CARD?" % picking.to_upper(), Vector2(480, by + 22), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 2)
		Art.text(self, "Lit soldiers have a card it works on. Their Dossier opens on those cards. ESC to cancel.", Vector2(480, by + 40), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)

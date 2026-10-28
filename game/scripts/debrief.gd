extends Control
## Debrief supply crates (L9): one per medal earned (at least one for a win, at most three).
## Click a crate: it shakes, its glow climbs through the rarity colors and stops on the item.

signal done

const HudScript := preload("res://scripts/hud.gd")
const HubUI := preload("res://scripts/hub_ui.gd")

var medals: Array = []
var crates: Array = []      # [{item, open_t (-1 closed), shown}]
var t := 0
var go: Control
var stage := "crates"       # crates, then command (P5: pick a commander perk)
var cmd_opts: Array = []
var fixed_tiers: Array = []  # side stops hand out set crates instead of medal crates
var no_command := false
var unlock := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var n := clampi(medals.size(), 1, 3) + (1 if Run.has_cmd("decorated") else 0)
	if medals.size() >= 2:
		Run.lvl_rerolls += 1
	if medals.size() >= 4:
		unlock = Run.feat("medals")
	if fixed_tiers.size():
		for tr in fixed_tiers:
			crates.append({"item": Run.roll_item(tr), "open_t": -1, "shown": false})
	else:
		for i in n:
			crates.append({"item": Run.roll_item(1 if i == 2 else 0), "open_t": -1, "shown": false})
	go = HudScript.PixButton.new()
	go.text = "ONWARD" if no_command else "BACK TO HQ"
	go.color = Color("ff4d3d")
	go.size = Vector2(340, 40)
	go.position = Vector2(310, 470)
	go.disabled = true
	go.pressed.connect(advance)
	add_child(go)
	var dz := HudScript.PixButton.new()  # S6: look at any deck before picking an order
	dz.text = "SQUAD DOSSIER"
	dz.color = Color("53d4e2")
	dz.size = Vector2(170, 32)
	dz.position = Vector2(24, 474)
	dz.pressed.connect(func(): Sfx.play("click"); HubUI.field_dossier(self, 0))
	add_child(dz)

func advance() -> void:
	## After the crates, the squad picks one commander perk; then on to the shop.
	cmd_opts = [] if no_command else Run.command_offers()
	if stage == "crates" and cmd_opts.size():
		stage = "command"
		for c in get_children():
			if c is CardView:
				c.queue_free()
		go.text = "SKIP"
		go.color = Color("9aa2ae")
		go.size = Vector2(160, 32)
		go.position = Vector2(400, 470)
		var x0 := 480 - (cmd_opts.size() * 150 + (cmd_opts.size() - 1) * 20) / 2.0
		for i in cmd_opts.size():
			var o: Dictionary = cmd_opts[i]
			var cv := CardView.new()
			cv.opt = {"kind": "perk", "name": o.name, "text": o.text, "tier": 3, "title": "ORDER"}
			cv.label_top = "COMMANDER"
			cv.size = Vector2(150, 190)
			cv.position = Vector2(x0 + i * 170, 190)
			var id: String = o.id
			cv.pressed.connect(func(): pick_command(id))
			add_child(cv)
		return
	Sfx.play("start")
	done.emit()

func pick_command(id: String) -> void:
	Run.cmd.append(id)
	Sfx.play("levelup")
	stage = "done"
	done.emit()

func crate_rect(i: int) -> Rect2:
	var n := crates.size()
	var w := 150.0
	var x0 := 480 - (n * w + (n - 1) * 40) / 2.0
	return Rect2(x0 + i * (w + 40), 210, w, 110)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		for i in crates.size():
			if crates[i].open_t < 0 and crate_rect(i).grow(10).has_point(ev.position):
				open_crate(i)
				accept_event()
				return

func open_crate(i: int) -> void:
	crates[i].open_t = 0
	Sfx.play("tick")

func open_all() -> void:
	## Tests and impatient players: pop every crate at once.
	for i in crates.size():
		if crates[i].open_t < 0:
			open_crate(i)

func _process(_d: float) -> void:
	t += 1
	var all := true
	for i in crates.size():
		var c: Dictionary = crates[i]
		if c.open_t >= 0:
			c.open_t += 1
			if c.open_t == 70 and not c.shown:
				c.shown = true
				Run.add_loot(c.item)
				Sfx.play("levelup" if c.item.tier >= 3 else "coin")
				var cv := CardView.new()
				cv.opt = Run.item_opt(c.item)
				var r := crate_rect(i)
				cv.size = Vector2(136, 210)
				cv.position = Vector2(r.get_center().x - 68, 172)
				cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(cv)
		if not c.shown:
			all = false
	go.disabled = not all and stage == "crates"
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color("16181c"))
	for y in range(0, 540, 24):
		for x in range(0, 960, 24):
			draw_texture_rect(Art.tex.ui_panel, Rect2(x, y, 24, 24), false, Color(0.45, 0.45, 0.5))
	var hz: Texture2D = Art.tex.ui_hazard
	for x in range(0, 960, 32):
		draw_texture_rect(hz, Rect2(x, 0, 32, 8), false)
	if stage == "command":
		Art.text(self, "COMMAND", Vector2(480, 62), 32, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 3)
		Art.text(self, "Pick one order for the whole squad. It lasts the rest of the %s." % ("war" if Run.campaign() else "run"), Vector2(480, 88), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
		if Run.cmd.size():
			Art.text(self, "STANDING ORDERS: " + ", ".join(Run.cmd.map(func(c): return Data.COMMANDS.filter(func(x): return x.id == c)[0].name)), Vector2(480, 140), 8, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER)
		return
	Art.text(self, "SUPPLY CRATES", Vector2(480, 62), 32, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 3)
	if unlock != "":
		Art.text(self, "ARMORY UNLOCK: %s CAN NOW DROP" % unlock.to_upper(), Vector2(480, 452), 8, Color("b48cff"), HORIZONTAL_ALIGNMENT_CENTER)
	Art.text(self, "Click a crate to open it. Everything goes to the stash; equip it at the Armory or from a soldier's Dossier.", Vector2(480, 88), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
	var y := 116.0
	if medals.is_empty():
		Art.text(self, "NO MEDALS THIS TIME. THE WIN STILL EARNS ONE CRATE.", Vector2(480, y + 8), 8, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER)
	for i in medals.size():
		var m: Array = medals[i]
		var x := 480 - (medals.size() * 210) / 2.0 + i * 210 + 105
		draw_texture_rect(Art.tex.ic_star, Rect2(x - 90, y - 4, 16, 16), false)
		Art.text(self, m[0], Vector2(x - 70, y + 8), 8, Color("ffd23a"))
		Art.text(self, m[1], Vector2(x - 70, y + 24), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
	for i in crates.size():
		var c: Dictionary = crates[i]
		if c.shown:
			continue
		var r := crate_rect(i)
		var k: int = c.open_t
		var shake := 0.0
		var glow := Color(1, 0.9, 0.5, 0.15 + 0.1 * sin(t / 10.0))
		if k >= 0:
			shake = sin(k * 1.7) * minf(6, k / 8.0)
			# the glow climbs one rarity step every 14 frames until it reaches the item's tier
			var step := mini(c.item.tier, k / 14)
			glow = Data.tier_color(step)
			glow.a = 0.35 + 0.25 * sin(k / 3.0)
		var rr := Rect2(r.position + Vector2(shake, 0), r.size)
		# soft halo: stacked faint rings instead of one hard disc
		for ring in 6:
			var g := glow
			g.a *= 0.22
			draw_circle(rr.get_center(), 40 + ring * 12, g)
		draw_rect(rr.grow(3), Color(0.05, 0.035, 0.03))
		draw_rect(rr, Color("6b4a26"))
		for yy in range(0, int(rr.size.y), 22):
			draw_rect(Rect2(rr.position.x, rr.position.y + yy, rr.size.x, 2), Color("4a3218"))
		draw_rect(Rect2(rr.position.x + 8, rr.position.y, 8, rr.size.y), Color("8a6234"))
		draw_rect(Rect2(rr.end.x - 16, rr.position.y, 8, rr.size.y), Color("8a6234"))
		Art.text(self, "SUPPLY", rr.get_center() + Vector2(0, 4), 8, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER)
		if k < 0 and t % 40 < 26:
			Art.text(self, "CLICK TO OPEN", Vector2(rr.get_center().x, rr.end.y + 22), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)

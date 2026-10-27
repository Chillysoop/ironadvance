extends Control
## Debrief supply crates (L9): one per medal earned (at least one for a win, at most three).
## Click a crate: it shakes, its glow climbs through the rarity colors and stops on the item.

signal done

const HudScript := preload("res://scripts/hud.gd")

var medals: Array = []
var crates: Array = []      # [{item, open_t (-1 closed), shown}]
var t := 0
var go: Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var n := clampi(medals.size(), 1, 3)
	for i in n:
		crates.append({"item": Run.roll_item(1 if i == 2 else 0), "open_t": -1, "shown": false})
	go = HudScript.PixButton.new()
	go.text = "TO THE QUARTERMASTER"
	go.color = Color("ff4d3d")
	go.size = Vector2(340, 40)
	go.position = Vector2(310, 470)
	go.disabled = true
	go.pressed.connect(func(): Sfx.play("start"); done.emit())
	add_child(go)

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
				cv.size = Vector2(124, 170)
				cv.position = Vector2(r.get_center().x - 62, 180)
				cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(cv)
		if not c.shown:
			all = false
	go.disabled = not all
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color("16181c"))
	for y in range(0, 540, 24):
		for x in range(0, 960, 24):
			draw_texture_rect(Art.tex.ui_panel, Rect2(x, y, 24, 24), false, Color(0.45, 0.45, 0.5))
	var hz: Texture2D = Art.tex.ui_hazard
	for x in range(0, 960, 32):
		draw_texture_rect(hz, Rect2(x, 0, 32, 8), false)
	Art.text(self, "SUPPLY CRATES", Vector2(480, 62), 32, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 3)
	Art.text(self, "Click a crate to open it. Everything goes to the stash; equip it at the Armory.", Vector2(480, 88), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
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

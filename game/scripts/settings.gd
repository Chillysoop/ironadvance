extends Control
## R5: the settings panel, opened from the title and the pause menu. Every change applies at once
## and is saved in meta.json. Volumes drive the Master, Music and SFX audio buses.

signal closed

const PixButton := preload("res://scripts/hud.gd").PixButton
const DEFAULTS := {"master": 8, "music": 7, "sfx": 8, "fullscreen": false, "shake": 100}
const SHAKES := [0, 50, 100]

# [key, label, kind]; blood and tips keep the meta keys they always had
const ROWS := [
	["master", "MASTER VOLUME", "vol"],
	["music", "MUSIC VOLUME", "vol"],
	["sfx", "EFFECTS VOLUME", "vol"],
	["fullscreen", "FULLSCREEN", "toggle"],
	["shake", "SCREEN SHAKE", "shake"],
	["tips", "NEW-PLAYER TIPS", "toggle"],
	["blood", "BLOOD AND ICHOR", "toggle"],
]
const ROW_Y := 150.0
const ROW_H := 40.0

static func get_value(k: String):
	if k == "tips":
		return not Run.meta.get("tips_off", false)
	if k == "blood":
		return Run.meta.get("blood", true)
	return Run.meta.get("settings", {}).get(k, DEFAULTS[k])

static func set_value(k: String, v) -> void:
	if k == "tips":
		Run.meta["tips_off"] = not v
	elif k == "blood":
		Run.meta["blood"] = v
	else:
		var st: Dictionary = Run.meta.get("settings", {})
		st[k] = v
		Run.meta["settings"] = st
	Run.save_meta()
	apply()

static func shake_mul() -> float:
	return float(get_value("shake")) / 100.0

static func bus(n: String) -> int:
	## The bus by name; made on the spot if the project's bus layout doesn't have it yet.
	var i := AudioServer.get_bus_index(n)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, n)
		AudioServer.set_bus_send(i, "Master")
	return i

static func apply() -> void:
	for k in ["master", "music", "sfx"]:
		var i := bus({"master": "Master", "music": "Music", "sfx": "SFX"}[k])
		var v := int(get_value(k))
		AudioServer.set_bus_mute(i, v <= 0)
		AudioServer.set_bus_volume_db(i, linear_to_db(v / 10.0) if v > 0 else -80.0)
	if OS.get_cmdline_user_args().has("--iatest"):
		return  # tests never resize the window
	var full: bool = get_value("fullscreen")
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if full != is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	build()

func build() -> void:
	for c in get_children():
		c.queue_free()
	for r in ROWS.size():
		var k: String = ROWS[r][0]
		var y := ROW_Y + r * ROW_H
		match ROWS[r][2]:
			"vol":
				button("-", Vector2(560, y), Vector2(36, 28), func(): step(k, -1))
				button("+", Vector2(724, y), Vector2(36, 28), func(): step(k, 1))
			"toggle":
				var on: bool = get_value(k)
				button("ON" if on else "OFF", Vector2(560, y), Vector2(200, 28), func(): set_value(k, not get_value(k)); click(), Color("62d26f") if on else Color("6c7480"))
			"shake":
				var cur := int(get_value(k))
				for j in SHAKES.size():
					var amt: int = SHAKES[j]
					button(["OFF", "LOW", "FULL"][j], Vector2(560 + j * 68, y), Vector2(64, 28), func(): set_value(k, amt); click(), Color("62d26f") if cur == amt else Color("6c7480"))
	button("BACK", Vector2(360, ROW_Y + ROWS.size() * ROW_H + 12), Vector2(240, 36), close, Color("9aa2ae"))

func button(t: String, pos: Vector2, sz: Vector2, cb: Callable, col := Color("53d4e2")) -> void:
	var bt := PixButton.new()
	bt.process_mode = Node.PROCESS_MODE_ALWAYS
	bt.text = t
	bt.color = col
	bt.position = pos
	bt.size = sz
	bt.pressed.connect(cb)
	add_child(bt)

func click() -> void:
	Sfx.play("click")
	build()

func step(k: String, d: int) -> void:
	set_value(k, clampi(int(get_value(k)) + d, 0, 10))
	Sfx.play("click")
	queue_redraw()

func close() -> void:
	Sfx.play("click")
	closed.emit()
	queue_free()

func _input(ev: InputEvent) -> void:
	var back: bool = ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT
	if back or (ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE):
		close()
		get_viewport().set_input_as_handled()

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 960, 540), Color(0.02, 0.02, 0.04, 0.85))
	var r := Rect2(180, 90, 600, ROWS.size() * ROW_H + 120)
	draw_rect(r.grow(2), Color(0.05, 0.035, 0.03))
	draw_rect(r, Color("2a2e34"))
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 2), Color("6c7480"))
	Art.text(self, "SETTINGS", Vector2(480, 124), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 2)
	for i in ROWS.size():
		var y := ROW_Y + i * ROW_H
		Art.text(self, ROWS[i][1], Vector2(220, y + 19), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2)
		if ROWS[i][2] == "vol":
			var v := int(get_value(ROWS[i][0]))
			# ten pips between the - and + buttons
			for p in 10:
				var on := p < v
				draw_rect(Rect2(604 + p * 12, y + 4, 10, 20), Color("ffb23e") if on else Color("3a3f47"))

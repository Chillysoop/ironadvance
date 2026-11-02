extends RefCounted
## H3: a short playtest diary, one readable line per event, kept next to the log in the user folder
## (user://playtest_diary.txt). Testers send it with their feedback: how long each mission took,
## who went down and to what, which boot camp lessons needed retries, and where they quit.

const PATH := "user://playtest_diary.txt"
const MAX_BYTES := 400000  # past this the oldest half is dropped

static func line(text: String) -> void:
	var stamp := Time.get_datetime_string_from_system(false, true).substr(0, 16)
	var old := ""
	if FileAccess.file_exists(PATH):
		old = FileAccess.get_file_as_string(PATH)
		if old.length() > MAX_BYTES:
			old = old.substr(old.length() / 2)
			old = old.substr(old.find("\n") + 1)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(old + "[%s] %s\n" % [stamp, text])

static func mode() -> String:
	if Run.campaign():
		return "CAMPAIGN"
	if str(Run.daily) != "":
		return "DAILY OP"
	return "QUICK RUN"

static func where(b) -> String:
	## "QUICK RUN level 2, FROZEN LAKE (lake)"
	var m: Dictionary = b.mission
	var s := mode()
	if not Run.campaign():
		s += " finale" if Run.is_final_mission() else " level %d" % (Run.history.size() + 1)
	return "%s, %s (%s)" % [s, str(m.get("name", "?")).to_upper(), m.get("biome", b.theme)]

static func minutes(ms: int) -> String:
	return "%.1f min" % (ms / 60000.0)

static func build() -> String:
	var v := FileAccess.get_file_as_string("res://version.txt").strip_edges()
	return v if v != "" else "dev"

static func folder() -> String:
	## Where the log, the diary and F12 screenshots live, as an OS path testers can open.
	return ProjectSettings.globalize_path("user://")

static func open_folder() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	OS.shell_open(folder())

class ShotKey extends Node:
	## H1: F12 saves a screenshot anywhere (paused too) to user://screenshots, named with the build.
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _input(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_F12:
			get_viewport().set_input_as_handled()
			snap()
	func snap() -> String:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
		var name := "ironadvance_%s_%s.png" % [load("res://scripts/diary.gd").build().replace(" ", "-"), stamp]
		var path := "user://screenshots/" + name
		img.save_png(path)
		Sfx.play("click")
		toast("SCREENSHOT SAVED   Esc > REPORT A BUG shows the folder")
		return path
	func toast(text: String) -> void:
		var layer := CanvasLayer.new()
		layer.layer = 120
		layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(layer)
		var t := Toast.new()
		t.text = text
		layer.add_child(t)
		get_tree().create_timer(2.2, true).timeout.connect(layer.queue_free)

class Toast extends Control:
	var text := ""
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := Art.text_width(text, 8) + 24
		var r := Rect2(480 - w / 2, 46, w, 22)
		draw_rect(r.grow(1), Color(0.05, 0.035, 0.03))
		draw_rect(r, Color("2a2e34"))
		Art.text(self, text, Vector2(480, 61), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)

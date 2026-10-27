extends Control
## Iron Advance launcher. On every start it:
##   1. fetches latest.json (version, pck url, sha256) from the release host,
##   2. downloads the new game pack if the version changed and verifies it,
##   3. deletes every older pack and leftover partial download,
##   4. relaunches this same executable with `--main-pack <pack>`, which runs the game.
## With no connection it plays the newest pack it already has.
## The launcher is the Godot runtime plus this small boot pack, so it only needs
## replacing when the engine version changes (the manifest's "engine" field says so).

const DEFAULT_MANIFEST := "https://github.com/chillysoopgood/ironadvance/releases/latest/download/latest.json"
const PACK_PREFIX := "IronAdvance-"

var manifest_url := DEFAULT_MANIFEST
var builds_dir := ""
var state := "checking"       # checking, downloading, launching, offline, error, engine
var status := "CHECKING FOR UPDATES"
var detail := ""
var progress := -1.0
var current := {}             # {"version": "...", "file": "IronAdvance-x.pck"}
var latest := {}
var http: HTTPRequest
var font: Font
var font_b: Font
var t := 0
var buttons: Array = []       # [[rect, label, callable]]
var hover := -1
var pass_args: Array = []
var offline_flag := false

func _ready() -> void:
	font = load("res://fonts/PressStart2P.woff")
	font_b = load("res://fonts/VT323.woff")
	for f in [font, font_b]:
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NONE
	builds_dir = OS.get_user_data_dir().path_join("builds")
	DirAccess.make_dir_recursive_absolute(builds_dir)
	read_config()
	current = read_json(builds_dir.path_join("current.json"))
	if current.has("file") and not FileAccess.file_exists(builds_dir.path_join(current.file)):
		current = {}
	http = HTTPRequest.new()
	http.use_threads = true
	add_child(http)
	if offline_flag:
		play_cached("OFFLINE MODE")
		return
	check()

func read_config() -> void:
	## A launcher.cfg next to the executable (or --manifest=URL) can point at another host.
	var cfg := ConfigFile.new()
	if cfg.load(OS.get_executable_path().get_base_dir().path_join("launcher.cfg")) == OK:
		manifest_url = cfg.get_value("update", "manifest", manifest_url)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--manifest="):
			manifest_url = a.substr(11)
		elif a == "--offline":
			offline_flag = true
		else:
			pass_args.append(a)

func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}

# ---------------------------------------------------------------- update flow
func check() -> void:
	state = "checking"
	status = "CHECKING FOR UPDATES"
	detail = ""
	buttons.clear()
	progress = -1
	http.download_file = ""
	http.timeout = 10.0
	http.request_completed.connect(_on_manifest, CONNECT_ONE_SHOT)
	if http.request(manifest_url) != OK:
		http.request_completed.disconnect(_on_manifest)
		play_cached("COULD NOT REACH THE UPDATE SERVER")

func _on_manifest(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		play_cached("UPDATE SERVER UNREACHABLE (%s)" % (str(code) if code else "offline"))
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary and d.has("version") and d.has("pck")):
		play_cached("UPDATE INFO WAS DAMAGED")
		return
	latest = d
	var eng := "%d.%d" % [Engine.get_version_info().major, Engine.get_version_info().minor]
	if str(latest.get("engine", eng)) != eng:
		state = "engine"
		status = "A NEW LAUNCHER IS NEEDED"
		detail = "Build %s needs engine %s. This launcher runs %s." % [latest.version, latest.engine, eng]
		buttons.clear()
		if latest.has("launcher_url"):
			add_button("GET NEW LAUNCHER", func(): OS.shell_open(latest.launcher_url))
		if current.has("file"):
			add_button("PLAY " + str(current.version), func(): launch())
		return
	if current.get("version", "") == str(latest.version):
		cleanup()
		launch()
		return
	download()

func pack_url() -> String:
	var u: String = latest.pck
	if u.begins_with("http://") or u.begins_with("https://"):
		return u
	return manifest_url.get_base_dir().path_join(u)

func download() -> void:
	state = "downloading"
	status = "DOWNLOADING BUILD " + str(latest.version)
	detail = str(latest.get("notes", ""))
	progress = 0.0
	var file := PACK_PREFIX + str(latest.version).validate_filename() + ".pck"
	http.download_file = builds_dir.path_join(file + ".part")
	http.timeout = 300.0
	http.request_completed.connect(_on_pack.bind(file), CONNECT_ONE_SHOT)
	if http.request(pack_url()) != OK:
		play_cached("DOWNLOAD FAILED TO START")

func _on_pack(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray, file: String) -> void:
	var part := builds_dir.path_join(file + ".part")
	http.download_file = ""
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(part)
		play_cached("DOWNLOAD FAILED (%s)" % (str(code) if code else "connection lost"))
		return
	var want := str(latest.get("sha256", "")).to_lower()
	if want != "" and FileAccess.get_sha256(part) != want:
		DirAccess.remove_absolute(part)
		play_cached("DOWNLOAD WAS CORRUPTED")
		return
	var dest := builds_dir.path_join(file)
	DirAccess.remove_absolute(dest)
	if DirAccess.rename_absolute(part, dest) != OK:
		play_cached("COULD NOT SAVE THE NEW BUILD")
		return
	current = {"version": str(latest.version), "file": file}
	var f := FileAccess.open(builds_dir.path_join("current.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(current))
	f.close()
	cleanup()
	launch()

func cleanup() -> void:
	## Delete every pack except the current one, plus any half-finished download.
	var dir := DirAccess.open(builds_dir)
	if dir == null:
		return
	for f in dir.get_files():
		if f == "current.json" or f == current.get("file", ""):
			continue
		if f.ends_with(".pck") or f.ends_with(".part"):
			dir.remove(f)

func play_cached(why: String) -> void:
	if current.has("file"):
		status = why
		detail = "Playing the build you already have (%s)." % current.version
		state = "offline"
		await get_tree().create_timer(1.2).timeout
		launch()
	else:
		state = "error"
		status = why
		detail = "No build downloaded yet. Check your connection and try again."
		buttons.clear()
		add_button("RETRY", func(): check())
		add_button("QUIT", func(): get_tree().quit())

func launch() -> void:
	state = "launching"
	status = "STARTING BUILD " + str(current.version)
	detail = ""
	progress = -1
	buttons.clear()
	await get_tree().create_timer(0.3).timeout
	var args := ["--main-pack", builds_dir.path_join(current.file)]
	if pass_args.size():
		args.append("--")
		args.append_array(pass_args)
	OS.create_process(OS.get_executable_path(), args)
	get_tree().quit()

# ---------------------------------------------------------------- drawing
func add_button(label: String, cb: Callable) -> void:
	var w := 200.0
	var n := buttons.size()
	buttons.append([Rect2(0, 0, w, 26), label, cb])
	var total := (n + 1) * w + n * 12
	for i in buttons.size():
		buttons[i][0].position = Vector2(240 - total / 2 + i * (w + 12), 214)

func _process(_d: float) -> void:
	t += 1
	if state == "downloading":
		var total := http.get_body_size()
		var got := http.get_downloaded_bytes()
		if total > 0:
			progress = float(got) / total
		detail = "%.1f / %.1f MB" % [got / 1048576.0, maxf(total, 0) / 1048576.0] if total > 0 else "%.1f MB" % (got / 1048576.0)
	queue_redraw()

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		hover = -1
		for i in buttons.size():
			if buttons[i][0].has_point(ev.position):
				hover = i
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		for b in buttons:
			if b[0].has_point(ev.position):
				b[2].call()
				return

func txt(s: String, pos: Vector2, size: int, col: Color, body := false) -> void:
	var f := font_b if body else font
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := Vector2(roundf(pos.x - w / 2), pos.y)
	if not body:
		draw_string(f, p + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.8))
	draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw() -> void:
	var ink := Color(0.05, 0.035, 0.03)
	# dusk sky bands with a hazard stripe floor
	var bands := [Color("2a1f45"), Color("3d2a55"), Color("5a3360"), Color("7e3d5e"), Color("a84f52")]
	for i in bands.size():
		draw_rect(Rect2(0, i * 36, 480, 36), bands[i])
	draw_circle(Vector2(360, 150), 34, Color("ffd27a"))
	for i in 7:
		var x := i * 74 - 10
		var h := 40 + int(abs(sin(i * 2.3)) * 50)
		draw_rect(Rect2(x, 180 - h, 52, h), Color("2a2034"))
		for k in 4:
			if (i + k) % 3 != 0:
				draw_rect(Rect2(x + 8 + k * 10, 180 - h + 10, 4, 4), Color("ffb23e"))
	draw_rect(Rect2(0, 180, 480, 90), ink)
	for x in range(0, 480, 16):
		draw_rect(Rect2(x, 180, 8, 4), Color("ffd23a"))
		draw_rect(Rect2(x + 8, 180, 8, 4), ink)
	var bob := sin(t / 25.0) * 2
	txt("IRON ADVANCE", Vector2(242, 62 + bob), 24, Color("8a2a14"))
	txt("IRON ADVANCE", Vector2(240, 60 + bob), 24, Color("ffd23a"))
	var col := Color("ff4d3d") if state == "error" or state == "engine" else Color("e8dcc2")
	var dots := ".".repeat((t / 20) % 4) if state in ["checking", "launching"] else ""
	txt(status + dots, Vector2(240, 200), 8, col)
	if progress >= 0:
		draw_rect(Rect2(90, 206, 300, 10), Color("e8dcc2"))
		draw_rect(Rect2(91, 207, 298, 8), ink)
		draw_rect(Rect2(92, 208, 296 * clampf(progress, 0, 1), 6), Color("62d26f"))
	if detail != "":
		txt(detail, Vector2(240, 236 if progress >= 0 else 214), 16, Color("9aa2ae"), true)
	for i in buttons.size():
		var r: Rect2 = buttons[i][0]
		draw_rect(r, ink)
		draw_rect(Rect2(r.position + Vector2(1, 1), r.size - Vector2(2, 3)), Color("ff4d3d") if hover == i else Color("c9372b"))
		txt(buttons[i][1], Vector2(r.position.x + r.size.x / 2, r.position.y + 17), 8, Color.WHITE)
	var ver := "LAUNCHER 1.0   " + (("BUILD " + str(current.version)) if current.has("version") else "NO BUILD YET")
	txt(ver, Vector2(240, 264), 8, Color("6c7480"))

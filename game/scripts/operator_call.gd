extends Control
## C4: someone calls in on a field tablet in a corner of the screen: their face on a
## scanlined screen, name and role, and the line typing out. It never blocks the screen
## around it. Click it (or wait) for the next line; the X hangs up.

signal done

const W := 352.0
const H := 104.0
const HOLD := 260          # frames a finished line stays up before the next one
var lines: Array = []      # Run.radio_line dictionaries
var i := 0
var shown := 0
var t := 0
var hold := 0
var slide := 1.0           # 1 = off screen at the nearest side, 0 = in place
var home := Vector2(596, 120)
var face: Control

func _ready() -> void:
	size = Vector2(W, H)
	position = home + Vector2(W + 40, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	face = FaceView.new()
	face.call_ = self
	face.position = Vector2(10, 10)
	face.size = Vector2(84, 84)
	face.clip_contents = true
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(face)
	Sfx.play("tick")
	if lines.is_empty():
		hang_up.call_deferred()

func line() -> Dictionary:
	return lines[i] if i >= 0 and i < lines.size() else {}

func advance() -> void:
	var L := line()
	if L.is_empty():
		return
	if shown < L.text.length():
		shown = L.text.length()
		return
	i += 1
	shown = 0
	hold = 0
	if i >= lines.size():
		hang_up()
	else:
		Sfx.play("tick")

func hang_up() -> void:
	if i < 0:
		return
	i = -1
	done.emit()

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if Rect2(W - 22, 4, 18, 16).has_point(ev.position):
			hang_up()
		else:
			advance()

func _process(_d: float) -> void:
	t += 1
	# in battle it sits just under the top bar, and below the new-player coach box while that is up
	var m = get_tree().current_scene
	home = Vector2(596, 120)
	if m != null and "battle" in m and m.battle != null:
		# top left, over the log: the right side holds the bounty board, kill feed and push lock
		home = Vector2(8, 34)
		if m.hud != null and m.hud.coach_box != null and m.hud.coach_box.get_child_count() > 0:
			home.y = 152.0
	# slide in, and back out once the call is over
	slide = move_toward(slide, 1.0 if i < 0 else 0.0, 0.08)
	var side := 1.0 if home.x > 480 else -1.0   # slides in from the nearest edge
	position = home + Vector2((W + 40) * slide * slide * side, 0)
	if i < 0 and slide >= 1.0:
		queue_free()
		return
	var L := line()
	if not L.is_empty():
		if shown < L.text.length():
			shown = mini(shown + 1, L.text.length())
		else:
			hold += 1
			if hold > HOLD:
				advance()
	queue_redraw()
	face.queue_redraw()

func _draw() -> void:
	var L := line()
	var col: Color = L.get("col", Color("62d26f"))
	var ink := Color(0.05, 0.035, 0.03)
	# the tablet: dark bezel, rounded-ish corners, a status LED
	draw_rect(Rect2(2, 3, W, H), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(0, 0, W, H), ink)
	draw_rect(Rect2(2, 2, W - 4, H - 4), Color("2a2e34"))
	draw_rect(Rect2(6, 6, W - 12, H - 12), Color("12171b"))
	draw_rect(Rect2(0, 0, W, H), col, false, 2.0)
	draw_circle(Vector2(W - 34, 12), 2.5, col if t % 40 < 26 else col.darkened(0.6))
	Art.text(self, "x", Vector2(W - 13, 16), 8, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER)
	if L.is_empty():
		return
	Art.text(self, "INCOMING  " + L.name, Vector2(104, 22), 8, col)
	Art.text(self, L.role, Vector2(104, 34), 8, Color("6c7480"))
	var y := 52.0
	for ln in CardView.wrap_text(L.text.substr(0, shown), W - 116, 16):
		Art.text(self, ln, Vector2(104, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		y += 14
	if lines.size() > 1:
		Art.text(self, "%d/%d" % [i + 1, lines.size()], Vector2(W - 10, H - 8), 8, Color("6c7480"), HORIZONTAL_ALIGNMENT_RIGHT)

class FaceView extends Control:
	## The caller's face, close up: their sprite drawn big so the head and shoulders fill the
	## screen, with scanlines and a flicker.
	var call_
	func _draw() -> void:
		var L: Dictionary = call_.line()
		var col: Color = L.get("col", Color("62d26f"))
		draw_rect(Rect2(Vector2.ZERO, size), col.darkened(0.82))
		var who: String = L.get("who", "")
		var sheet: String = {"cmd": "sq_moss_beret", "varga": "en_radio", "prime": "en_overseer", "sarge": "sq_rook_helmet"}.get(who, "")
		if who == "sq" and L.has("s"):
			sheet = Art.look_sheet(L.s)
		if Art.meta.has(sheet):
			var fh: float = Art.meta[sheet].frame[1]
			var sc := 3.0
			# feet far below the frame so the head sits near the top; mouth "moves" while text types
			var talking: bool = call_.shown < str(L.get("text", "")).length()
			var fr: int = (call_.t / 6) % 2 if talking else 0
			Art.draw_char(self, sheet, "idle", fr, Vector2(size.x / 2, fh * Art.PX * sc * 0.92), 1, false, 0, 1.0, 0, false, sc)
		for y in range(0, int(size.y), 3):
			draw_rect(Rect2(0, y, size.x, 1), Color(0, 0, 0, 0.22))
		if call_.t % 97 < 3:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08))
		draw_rect(Rect2(Vector2.ZERO, size), col, false, 1.0)

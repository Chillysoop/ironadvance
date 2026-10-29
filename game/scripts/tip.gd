extends CanvasLayer
## Hover tips for words drawn in a _draw() (synergies, sets, duos). A screen calls clear(self) as its
## draw starts and zone() over each word it wants explained; this layer shows that box when the
## mouse rests on one, above every other layer so tiles and cards never cover it.

const W := 230.0
var zones := {}    # owner instance id -> Array of {r, title, text, c}
var owners := {}   # owner instance id -> weakref
var cur := {}      # the zone under the mouse, plus "at": its rect in this layer's space
var view: Control

func _ready() -> void:
	layer = 120
	view = Control.new()
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.size = Vector2(960, 540)
	add_child(view)
	view.draw.connect(paint)

func clear(owner: CanvasItem) -> void:
	zones.erase(owner.get_instance_id())

func zone(owner: CanvasItem, r: Rect2, title: String, text: String, c := Color("b48cff")) -> void:
	var id := owner.get_instance_id()
	if not zones.has(id):
		zones[id] = []
		owners[id] = weakref(owner)
	zones[id].append({"r": r, "title": title, "text": text, "c": c})

func _process(_d: float) -> void:
	var hit := {}
	for id in zones.keys():
		var o = owners[id].get_ref()
		if o == null or not o.is_inside_tree():
			zones.erase(id)
			owners.erase(id)
			continue
		if not o.is_visible_in_tree():
			continue
		var m: Vector2 = o.get_local_mouse_position()
		for z in zones[id]:
			if z.r.has_point(m):
				hit = z.duplicate()
				var xf: Transform2D = view.get_global_transform_with_canvas().affine_inverse() * o.get_global_transform_with_canvas()
				hit["at"] = Rect2(xf * z.r.position, xf.basis_xform(z.r.size))
	if hit.is_empty() != cur.is_empty() or hit.get("title", "") != cur.get("title", "") or hit.get("at") != cur.get("at"):
		cur = hit
		view.queue_redraw()

func paint() -> void:
	if cur.is_empty():
		return
	var w := maxf(W, Art.text_width(cur.title, 8) + 16)
	var lines := CardView.wrap_text(cur.text, w - 16, 16)
	var h := 26.0 + lines.size() * 12
	var at: Rect2 = cur.at
	# a word gets it below (above when there is no room); a whole panel row gets it beside, so
	# the rows under it stay readable
	var x := clampf(at.position.x + at.size.x / 2 - w / 2, 4, 956 - w)
	var y := at.end.y + 4
	if at.size.x > 120:
		x = at.position.x - w - 6 if at.position.x - w - 6 >= 4 else minf(at.end.x + 6, 956 - w)
		y = at.position.y
	elif y + h > 536:
		y = at.position.y - h - 4
	y = clampf(y, 4, 536 - h)
	var c: Color = cur.c
	view.draw_rect(Rect2(x - 1, y - 1, w + 2, h + 2), Color(0.05, 0.035, 0.03, 0.95))
	view.draw_rect(Rect2(x, y, w, h), Color(0.1, 0.11, 0.13, 0.96))
	view.draw_rect(Rect2(x, y, w, 2), c)
	Art.text(view, cur.title, Vector2(x + 8, y + 15), 8, c, HORIZONTAL_ALIGNMENT_LEFT, 1)
	for i in lines.size():
		Art.text(view, lines[i], Vector2(x + 8, y + 28 + i * 12), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 1, true)

func chips(owner: CanvasItem, syn: Array, pos: Vector2, max_w: float) -> float:
	## A run of Run.synergies() entries as hoverable words ("DESERT RAT 1/2  DUO SPOTTER VEE"), wrapping
	## at max_w. Lit ones are the ones switched on. Returns the y under the last line.
	var x := pos.x
	var y := pos.y
	for sy in syn:
		var label: String = sy.name + (" " + sy.prog if sy.prog != "" else "")
		var c: Color = {"set": Color("62d26f"), "evo": Color("53d4e2"), "duo": Color("b48cff")}.get(sy.kind, Color("e8dcc2"))
		if not sy.done:
			c = c.darkened(0.35)
		var w := Art.text_width(label, 16, true)
		if x > pos.x and x + w > pos.x + max_w:
			x = pos.x
			y += 12
		Art.text(owner, label, Vector2(x, y), 16, c, HORIZONTAL_ALIGNMENT_LEFT, 0, true)
		owner.draw_rect(Rect2(x, y + 2, w, 1), Color(c, 0.5))  # the underline marks it as hoverable
		zone(owner, Rect2(x - 2, y - 11, w + 4, 15), sy.get("title", sy.name), sy.text, c)
		x += w + 10
	return y + 12

extends Node2D
## Runs the Sprite Fusion pixel effects (scripts/vfx/). Each effect paints a back pass (behind the
## soldiers, on VfxBack), a front pass (over them, on this node) and light (VfxLight, drawn
## additively). Effects step with the battle clock, so they freeze on pause and speed up with
## fast-forward, and they are cosmetic only: nothing here feeds back into the simulation.

const DT := 1.0 / 60.0
const MAX := 80

@onready var b: Battle = get_parent()
var back_node: Node2D
var light_node: Node2D
var list: Array = []
var last_t := -1

func _ready() -> void:
	back_node = b.get_node("VfxBack")
	light_node = b.get_node("VfxLight")
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	light_node.material = mat
	for n in [self, back_node, light_node]:
		n.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func add(e) -> void:
	list.append(e)
	if list.size() > MAX:
		list.pop_front()

func _process(_d: float) -> void:
	if b.T == null:
		return
	if last_t < 0:
		last_t = b.t
	var steps := mini(b.t - last_t, 6)
	last_t = b.t
	if steps <= 0:
		return
	for i in steps:
		for e in list:
			e.update(DT)
	list = list.filter(func(e): return not e.done())
	paint()

func paint() -> void:
	var cis := [back_node.get_canvas_item(), get_canvas_item(), light_node.get_canvas_item()]
	for ci in cis:
		RenderingServer.canvas_item_clear(ci)
	if list.is_empty():
		return
	var clip := Rect2i(floori(b.cam_x / Sf.PX) - 24, -60, int(Battle.W / Sf.PX) + 48, int(Battle.H / Sf.PX) + 84)
	var back := Sf.Px.new(cis[0], false, clip)
	var front := Sf.Px.new(cis[1], false, clip)
	var light := Sf.Px.new(cis[2], true, clip)
	for e in list:
		e.draw(back, light, 0)
	for e in list:
		e.draw(front, light, 1)

func ground_fn(y0: float) -> Callable:
	## The floor under x for particles that started near height y0: the first open-to-solid step
	## below y0 - 48, cached per column (the effect is short, so the terrain barely changes).
	var cache := {}
	var T: Terrain = b.T
	return func(x: float) -> float:
		var k := floori(x / Terrain.CELL)
		if cache.has(k):
			return cache[k]
		var gy := 1e9
		var y := floorf((y0 - 48) / Terrain.CELL) * Terrain.CELL
		var was := T.solid(x, y - Terrain.CELL)
		while y < Data.WATER_Y + 8:
			var s := T.solid(x, y)
			if s and not was:
				gy = y
				break
			was = s
			y += Terrain.CELL
		cache[k] = gy
		return gy

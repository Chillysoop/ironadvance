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
var attached := {}    # "unit id:kind" -> effect riding on that unit (burn fire, stun crackle)
var adr_seen := {}    # unit id -> adrenaline last tick, to catch PUMPED and Overdrive ready
var sil_cache := {}   # sheet|anim|frame -> [xs, ys] opaque pixels relative to the anchor
var sheet_img := {}   # sheet -> Image

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
	watch()
	for i in steps:
		for e in list:
			e.update(DT)
	list = list.filter(func(e): return not e.done())
	paint()

func watch() -> void:
	## Start and stop the effects that ride on units: V4 flames while BURNING, V5 crackle while
	## STUNNED, and a V13 power-up burst when a soldier turns PUMPED or has Overdrive ready.
	var seen := {}
	for u in b.units:
		if u.gone or u.sunk:
			continue
		var vis: bool = u.x > b.cam_x - 60 and u.x < b.cam_x + Battle.W + 60 and not u.dead
		keep(u, "burn", vis and u.has_st("burn"), seen)
		keep(u, "stun", vis and u.has_st("stun"), seen)
		if u.team == "squad":
			var was: int = adr_seen.get(u.id, u.adr)
			adr_seen[u.id] = u.adr
			if vis and was < 100 and u.adr >= 100:
				power_up(u, SfPowerUp.CYAN)
			elif vis and was < 50 and u.adr >= 50:
				power_up(u, SfPowerUp.EMBER)
	for key in attached.keys():
		if not seen.has(key):
			attached[key].stop()
			attached.erase(key)

func keep(u: Unit, kind: String, want: bool, seen: Dictionary) -> void:
	var key := "%d:%s" % [u.id, kind]
	if not want:
		return
	seen[key] = true
	if attached.has(key) and list.has(attached[key]):
		return
	var src := func(): return [] if u.dead or u.gone else silhouette(u)
	var e
	if kind == "burn":
		e = SfFire.new(src, 0.7, b.wind * 20.0)
	else:
		e = SfLightning.crackle(src, ground_fn(u.y), 1e9)
	attached[key] = e
	add(e)

func power_up(u: Unit, palette: Array) -> void:
	add(SfPowerUp.new(func(): return Vector2(u.x, u.y), silhouette(u), palette, 0.55))

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

func silhouette(u: Unit) -> Array:
	## The art pixels a unit's body covers right now, [xs, ys, feet], from its sprite frame (or a
	## box for sheetless units), so fire, crackle and auras can hug the real outline.
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	var fx := floori(u.x / Sf.PX)
	var fy := floori(u.y / Sf.PX)
	if u.sheet != "" and Art.meta.has(u.sheet) and Art.tex.has(u.sheet):
		var a: Array = b.view.pick_anim(u)
		var m: Dictionary = Art.meta[u.sheet]
		var info: Dictionary = m.anims.get(a[0], m.anims.idle)
		var fi: int = int(a[1]) % int(info.n)
		var key := "%s|%s|%d" % [u.sheet, a[0], fi]
		if not sil_cache.has(key):
			if not sheet_img.has(u.sheet):
				var img: Image = Art.tex[u.sheet].get_image()
				if img.is_compressed():
					img.decompress()
				sheet_img[u.sheet] = img
			var im: Image = sheet_img[u.sheet]
			var fw: int = m.frame[0]
			var fh: int = m.frame[1]
			var ox: int = fi * fw
			var oy: int = int(info.row) * fh
			var lx := PackedInt32Array()
			var ly := PackedInt32Array()
			for j in fh:
				for i in fw:
					if ox + i < im.get_width() and oy + j < im.get_height() and im.get_pixel(ox + i, oy + j).a > 0.5:
						lx.append(i - int(m.anchor[0]))
						ly.append(j - int(m.anchor[1]))
			sil_cache[key] = [lx, ly]
		var c: Array = sil_cache[key]
		var lx: PackedInt32Array = c[0]
		var ly: PackedInt32Array = c[1]
		xs.resize(lx.size())
		ys.resize(ly.size())
		for i in lx.size():
			xs[i] = fx + (lx[i] if u.face > 0 else -lx[i] - 1)
			ys[i] = fy + ly[i]
	if xs.is_empty():
		var hw := maxi(2, int(u.w / Sf.PX / 2))
		var hh := maxi(4, int(u.h / Sf.PX))
		for j in range(-hh, 0):
			for i in range(-hw, hw):
				xs.append(fx + i)
				ys.append(fy + j)
	return [xs, ys, Vector2(u.x, u.y)]

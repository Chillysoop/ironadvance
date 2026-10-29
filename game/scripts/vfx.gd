extends Node2D
## Runs the Sprite Fusion pixel effects (scripts/vfx/). Each effect paints a back pass (behind the
## soldiers, on VfxBack), a front pass (over them, on this node) and light (VfxLight, drawn
## additively). Effects step with the battle clock, so they freeze on pause and speed up with
## fast-forward, and they are cosmetic only: nothing here feeds back into the simulation.

const DT := 1.0 / 60.0
const MAX := 80
const NO_BLOOD := ["mg", "jwalker", "gunship", "dicokka", "prism", "burrow", "hiveship", "shipplate", "droppod", "vgate", "boss"]

@onready var b: Battle = get_parent()
var back_node: Node2D
var light_node: Node2D
var list: Array = []
var last_t := -1
var attached := {}    # "unit id:kind" -> effect riding on that unit (burn fire, stun crackle)
var adr_seen := {}    # unit id -> adrenaline last tick, to catch PUMPED and Overdrive ready
var sil_cache := {}   # sheet|anim|frame -> [xs, ys] opaque pixels relative to the anchor
var sheet_img := {}   # sheet -> Image
var hp_seen := {}     # unit id -> hp last tick, to catch heals (V14)
var pools: Array = [] # [acid or gas dictionary, effect] for the V10 puddles and clouds
var weather: Array = []  # the biome's V18-V21/V23 SfWeather, never culled
var weather_set := false
var sky_cache := {}      # terrain column -> surface y, for the weather
var smoke_tex: Texture2D
const WEATHER := {
	"lake": ["snow"], "volcano": ["embers"], "jungle": ["rain", "leaves", "sparkle"], "delta": ["rain", "leaves"],
	"harbor": ["rain"], "city": ["rain"], "mine": ["fog"], "hive": ["fog"], "palace": ["fireflies", "sparkle"],
}

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
	if not weather_set:
		start_weather()
	if b.t % 60 == 0:
		sky_cache.clear()
	for w in weather:
		w.follow(b.cam_x)
		w.wind = b.wind
	for i in steps:
		for e in list:
			e.update(DT)
		for w in weather:
			w.update(DT)
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
		keep(u, "dome", vis and u.dome > 0 and not u.fl.get("vharr", false), seen)
		keep(u, "toxic", vis and u.has_st("toxic"), seen)
		var hp0: int = hp_seen.get(u.id, u.hp)
		hp_seen[u.id] = u.hp
		if vis and u.hp > hp0 and hp0 > 0 and not u.is_prop() and not u.is_pickup():
			heal(u)
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
	watch_pools()

func watch_pools() -> void:
	## V10: a bubbling puddle for each acid pool and a churning cloud for each gas cloud, stopped
	## when the pool dries up or the cloud clears.
	var live: Array = b.acids + b.gases
	for i in range(pools.size() - 1, -1, -1):
		if not live.any(func(d): return is_same(d, pools[i][0])):
			pools[i][1].stop()
			pools.remove_at(i)
	for d in live:
		if pools.any(func(p): return is_same(p[0], d)):
			continue
		var e: SfPoison
		if b.acids.any(func(a): return is_same(a, d)):
			var gy: float = ground_fn(d.y).call(d.x)
			e = SfPoison.puddle(d.x, gy if gy < 1e8 else d.y, d.r, ground_fn(d.y))
		else:
			e = SfPoison.gas(d.x, d.y, d.r, ground_fn(d.y))
		pools.append([d, e])
		add(e)

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
	elif kind == "toxic":
		e = SfPoison.aura(func(): return Vector2(u.x, u.y), src, ground_fn(u.y))
	elif kind == "dome":
		e = SfShield.new(func(): return Vector2(u.x, u.y), dome_r(u), ground_fn(u.y), SfShield.VHARR)
	else:
		e = SfLightning.crackle(src, ground_fn(u.y), 1e9)
	attached[key] = e
	add(e)

func dome_r(u: Unit) -> float:
	## The V8 dome sits on the ground, so it has to clear the unit's head (art px).
	return roundf(maxf(u.h + 8.0, u.w / 2.0 + 10.0) / Sf.PX)

func dome_hit(u: Unit, src) -> void:
	## A shot the dome stopped: ripple and sparks on the side facing whoever fired it.
	var e = attached.get("%d:dome" % u.id)
	if e == null:
		return
	var d := Vector2(-u.face, -0.6)
	if src is Unit:
		d = Vector2(src.x - u.x, (src.y - src.h / 2.0) - (u.y - u.h / 2.0))
	d.y = minf(d.y, -absf(d.x) * 0.25 - 1.0)
	var p: Vector2 = d.normalized() * dome_r(u) * Sf.PX * 0.98
	e.hit(u.x + p.x, u.y + p.y)

func dash(u: Unit) -> SfMovement:
	var e := SfMovement.dash(func(): return Vector2(u.x, u.y), func(): return [] if u.dead or u.gone else silhouette(u), u.face, ground_fn(u.y))
	add(e)
	return e

func power_up(u: Unit, palette: Array) -> void:
	add(SfPowerUp.new(func(): return Vector2(u.x, u.y), silhouette(u), palette, 0.55))

func start_weather() -> void:
	weather_set = true
	for k in WEATHER.get(b.mission.get("biome", ""), []):
		weather.append(SfWeather.make(k, sky_fn, b.cam_x))

func sky_fn(x: float) -> float:
	## The first surface down from the sky at x (or the waterline), cached per column.
	var k := floori(x / Terrain.CELL)
	if not sky_cache.has(k):
		var y = b.T.stand_y(k * Terrain.CELL + Terrain.CELL / 2.0, -40)
		sky_cache[k] = minf(y if y != null else 1e9, Data.WATER_Y)
	return sky_cache[k]

func draw_smokes(back: Sf.Px, front: Sf.Px) -> void:
	## V21 for the Smoke Can: each cloud is a rolling fog puff, the deep half behind the fight.
	if b.smokes.is_empty():
		return
	if smoke_tex == null:
		smoke_tex = load("res://assets/vfx/fog_smoke.png")
	for s in b.smokes:
		var r: float = s.r
		for i in 2:
			var bob := sin(b.t / 50.0 + s.seed + i * 2.1) * 3.0
			var sc := 1.0 if i == 0 else 0.8
			var w := r * 2.2 * sc
			var h := r * 1.26 * sc
			var flip := -1.0 if i == 1 else 1.0
			var rect := Rect2(s.x - w / 2 * flip + i * flip * 8, s.y - h * 0.55 + bob, w * flip, h)
			RenderingServer.canvas_item_add_texture_rect((back if i == 1 else front).ci, rect, smoke_tex.get_rid(), false, Color(1, 1, 1, 0.92))

func heal(u: Unit) -> void:
	add(SfHeal.new(func(): return Vector2(u.x, u.y), func(): return [] if u.dead or u.gone else silhouette(u), 12 if u.h < 50 else 18))

func bleed(u: Unit, src, amt: int) -> void:
	## V6: flesh bleeds where it was hit, sprayed away from whoever hit it. Vharr bleed ichor.
	if not Run.meta.get("blood", true):
		return
	if not u.kind in ["soldier", "enemy", "pow", "dog"] or u.type in NO_BLOOD or b.is_boss(u) or u.mech != null:
		return
	if u.kind == "enemy" and Data.ETYPES.get(u.type, {}).get("static", false):
		return
	var hy := u.y - u.h * 0.55
	var a := -PI / 2 + randf_range(-0.6, 0.6)
	if src is Unit and src != u:
		a = atan2(clampf(hy - (src.y - src.h / 2.0), -60, 60) - 30, u.x - src.x)
	var vh: bool = b.faction(u) == "vharr"
	add(SfBlood.new(u.x, hy, a, ground_fn(u.y), func(): return Vector2(u.x, u.y), clampf(amt / 10.0, 0.35, 1.4), 1.0, SfBlood.ICHOR if vh else SfBlood.RED))

func slash(x: float, y: float, face: float, sc: float) -> void:
	add(SfSlash.new(x, y, face, ground_fn(y + 40), 0.5 * sc))

func pickup(u: Unit, p: Unit, scrip: bool) -> void:
	add(SfPickup.new(p.x, p.y - 10, "coin" if scrip else "gem", func(): return Vector2(u.x, u.y - u.h * 0.5)))

func paint() -> void:
	var cis := [back_node.get_canvas_item(), get_canvas_item(), light_node.get_canvas_item()]
	for ci in cis:
		RenderingServer.canvas_item_clear(ci)
	if list.is_empty() and weather.is_empty() and b.smokes.is_empty():
		return
	var clip := Rect2i(floori(b.cam_x / Sf.PX) - 24, -60, int(Battle.W / Sf.PX) + 48, int(Battle.H / Sf.PX) + 84)
	var back := Sf.Px.new(cis[0], false, clip)
	var front := Sf.Px.new(cis[1], false, clip)
	var light := Sf.Px.new(cis[2], true, clip)
	for w in weather:
		w.draw(back, light, 0)
	draw_smokes(back, front)
	for e in list:
		e.draw(back, light, 0)
	for e in list:
		e.draw(front, light, 1)
	for w in weather:
		w.draw(front, light, 1)

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
	## box for sheetless units), so fire, crackle and auras can hug the real outline. A fourth entry
	## holds each pixel's shade, 1 dark to 3 light, for the dash ghosts and blink.
	var xs := PackedInt32Array()
	var shade := PackedByteArray()
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
			var lv := PackedByteArray()
			for j in fh:
				for i in fw:
					if ox + i < im.get_width() and oy + j < im.get_height():
						var pc := im.get_pixel(ox + i, oy + j)
						if pc.a > 0.5:
							lx.append(i - int(m.anchor[0]))
							ly.append(j - int(m.anchor[1]))
							var l := Sf.lum(pc) * 255.0
							lv.append(1 if l < 60 else (2 if l < 170 else 3))
			sil_cache[key] = [lx, ly, lv]
		var c: Array = sil_cache[key]
		var lx: PackedInt32Array = c[0]
		var ly: PackedInt32Array = c[1]
		shade = c[2]
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
				shade.append(1 if i == -hw or i == hw - 1 or j == -hh else 2)
	return [xs, ys, Vector2(u.x, u.y), shade]

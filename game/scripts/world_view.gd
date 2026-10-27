extends Node2D
## Draws everything that lives in the world above the terrain: soldiers, props,
## projectiles, particles, explosions, and the in-world HUD (unit plates, aim
## lasers, move paths, floating text).

@onready var b: Battle = get_parent()

const C_DARK := Color(0.05, 0.035, 0.03)
const RIM := {"dusk": Color(1.0, 0.72, 0.42, 0.85), "jungle": Color(1.0, 0.95, 0.65, 0.75), "night": Color(0.6, 0.75, 1.0, 0.8)}
const C_ALIEN := Color("c47bff")  # Vharr markers and labels
const C_OOZE := Color("9df25c")

func _draw() -> void:
	if b.T == null:
		return
	var cx := b.cam_x
	draw_ladders(cx)
	draw_bridges()
	draw_strikes(cx)
	for c in b.T.camps:
		if on_screen(c.fire, 320):
			draw_camp(c)
	if b.gate != null:
		Art.draw_gate(self, Vector2(b.gate.x, b.gate.y), b.gate.r, b.t, b.gate.chev, b.gate.open, b.gate.alpha, b.gate.spin, b.gate.burst)
	for r in b.ropes:
		draw_line(Vector2(r.x, r.y), Vector2(r.u.x, r.u.y - 20), r.get("c", Color("d8d0b8")), 3.0 if r.has("c") else 1.0)
	draw_acids()
	draw_wells()
	for u in b.units:
		if u.dead:
			draw_unit(u)
	for u in b.units:
		if not u.dead:
			draw_unit(u)
			if u.drill != null:
				draw_drill(u, Vector2(u.drill.dx, u.drill.dy), true)
	draw_smokes()
	draw_projs()
	for tr in b.tracers:
		var c: Color = tr.c
		c.a = tr.t / 9.0
		draw_line(Vector2(tr.x1, tr.y1), Vector2(tr.x2, tr.y2), c, 2.0)
	draw_parts()
	draw_fx()
	for u in b.units:
		draw_plate(u)
	draw_targeting()
	draw_texts()
	draw_barks()
	draw_hover()

func draw_camp(c: Dictionary) -> void:
	## Two tents, a supply crate, a flag and a campfire that burns until the squad moves on.
	var T = b.T
	for tx in [c.fire - 150.0, c.fire + 110.0]:
		var g: float = T.ground_at(tx)
		draw_colored_polygon(PackedVector2Array([Vector2(tx - 44, g), Vector2(tx, g - 46), Vector2(tx + 44, g)]), C_DARK)
		draw_colored_polygon(PackedVector2Array([Vector2(tx - 40, g), Vector2(tx, g - 42), Vector2(tx + 40, g)]), Color("5a6b3a"))
		draw_colored_polygon(PackedVector2Array([Vector2(tx - 9, g), Vector2(tx, g - 22), Vector2(tx + 9, g)]), Color("2a2418"))
	var cg: float = T.ground_at(c.fire + 60)
	draw_rect(Rect2(c.fire + 50, cg - 20, 24, 20), C_DARK)
	draw_rect(Rect2(c.fire + 51, cg - 19, 22, 18), Color("8a6a3a"))
	draw_rect(Rect2(c.fire + 51, cg - 13, 22, 2), Color("6a4e2a"))
	var fx: float = c.fire - 60
	var fg: float = T.ground_at(fx)
	draw_rect(Rect2(fx - 1, fg - 70, 2, 70), Color("3a3a3a"))
	for i in 5:
		var wave := sin(b.t / 12.0 + i * 0.7) * 2
		draw_rect(Rect2(fx + 1 + i * 4, fg - 68 + wave, 4, 12), Color("62d26f") if i % 2 == 0 else Color("e8dcc2"))
	# the fire
	var g: float = T.ground_at(c.fire)
	draw_rect(Rect2(c.fire - 12, g - 4, 24, 4), Color("4a3020"))
	draw_rect(Rect2(c.fire - 8, g - 7, 16, 3), Color("5a3a24"))
	if not c.get("out", false):
		for k in 4:
			var h := 6 + 5 * absf(sin(b.t / (5.0 + k) + k * 1.3))
			var col: Color = [Color("ff4d3d"), Color("ff7a3d"), Color("ffb23e"), Color("ffe36a")][k]
			draw_rect(Rect2(c.fire - 6 + k * 3, g - 6 - h, 4, h), col)
		if b.t % 9 == 0:
			b.part({"x": c.fire + (randf() - 0.5) * 8, "y": g - 14, "vx": (randf() - 0.5) * 0.3, "vy": -0.6, "life": 40, "max": 40, "c": Color("ffb23e"), "s": 2.0, "g": -0.005})
		draw_circle(Vector2(c.fire, g - 8), 34, Color(1, 0.6, 0.2, 0.08))
	if not c.used:
		Art.text(self, "CAMP", Vector2(c.fire, g - 90), 8, Color("62d26f"), HORIZONTAL_ALIGNMENT_CENTER)

func on_screen(x: float, pad := 140.0) -> bool:
	return x > b.cam_x - pad and x < b.cam_x + Battle.W + pad

# ---------------------------------------------------------------- scenery
func draw_ladders(_cx: float) -> void:
	for L in b.T.ladders:
		if not b.T.solid(L.offx, L.top + 2) or not on_screen(L.x):
			continue
		var x := roundf(L.x)
		var top: float = L.top - 4
		var hgt: float = L.bot - L.top + 4
		draw_rect(Rect2(x - 7, top, 2, hgt), C_DARK)
		draw_rect(Rect2(x + 5, top, 2, hgt), C_DARK)
		draw_rect(Rect2(x - 6, top, 2, hgt), Color("8a5a2a"))
		draw_rect(Rect2(x + 4, top, 2, hgt), Color("8a5a2a"))
		var y: float = L.top
		while y < L.bot:
			draw_rect(Rect2(x - 6, y, 12, 2), Color("b88a4a"))
			draw_rect(Rect2(x - 6, y + 2, 12, 1), C_DARK)
			y += 8

func draw_bridges() -> void:
	## rope handrails on standing bridges, slung between the deck ends and the posts
	for s in b.T.bridges:
		if s.down or not (on_screen(s.x0, 300) or on_screen(s.x1, 300)):
			continue
		var pts: Array = [s.x0 + 2.0] + s.posts + [s.x1 - 2.0]
		for i in pts.size():
			var px: float = pts[i]
			if not b.T.solid(px, s.y + 2):
				continue
			draw_rect(Rect2(px - 2, s.y - 18, 4, 18), C_DARK)
			draw_rect(Rect2(px - 1, s.y - 17, 2, 17), Color("8a5a2a"))
			if i + 1 < pts.size() and b.T.solid(pts[i + 1], s.y + 2):
				var a := Vector2(px, s.y - 16)
				var bb := Vector2(pts[i + 1], s.y - 16)
				var prev := a
				for k in range(1, 9):
					var f := k / 8.0
					var p := a.lerp(bb, f) + Vector2(0, sin(f * PI) * 5)
					draw_line(prev, p, Color("d8c8a0"), 1.0)
					prev = p

func draw_strikes(_cx: float) -> void:
	for s in b.strikes:
		var gy = b.T.stand_y(s.x, 0)
		if gy == null:
			gy = Battle.WATER_Y
		var friendly: bool = s.get("friendly", false)
		var col := Color("62d26f") if friendly else (Color("ff4d3d") if b.t % 20 < 10 else Color("ffb23e"))
		draw_rect(Rect2(s.x - 48, 0, 96, gy), Color(col, 0.10))
		draw_arc(Vector2(s.x, gy - 6), 20, 0, TAU, 24, col, 2.0)
		draw_line(Vector2(s.x - 28, gy - 6), Vector2(s.x + 28, gy - 6), col, 2.0)
		draw_line(Vector2(s.x, gy - 34), Vector2(s.x, gy + 22), col, 2.0)
		Art.text(self, "!" if not friendly else "STRIKE", Vector2(s.x, gy - 40), 16 if not friendly else 8, col, HORIZONTAL_ALIGNMENT_CENTER)

# ---------------------------------------------------------------- units
func pick_anim(u: Unit) -> Array:
	## [anim, frame, show_gun]
	if u.dead:
		return ["die", mini(Art.anim_info(u.sheet, "die").n - 1, u.dead_t / 5) if u.sheet != "" else 0, false]
	if u.pose == "hurt":
		return ["hurt", (u.pose_t / 4) % 2, false]
	if u.pose == "throw":
		var n := 24
		return ["throw", clampi((n - u.pose_t) / 6, 0, 3), true]
	if u.pose == "cheer":
		return ["cheer", (b.t / 10) % 2, false]
	if u.drill != null:
		return ["run", (u.anim / 2) % 8, true]
	if u.para or u.air:
		return ["jump", 0 if u.vy < 0 else 1, true]
	if u.walk != null:
		var i: int = mini(u.walk_i, u.walk.size() - 1)
		if i >= 0 and u.walk[i].size() > 3:
			return ["climb", (b.t / 8) % 2, false]
		return ["run", (u.anim / 3) % 8, true]
	return ["idle", b.t / 10 + u.id * 5, true]

func draw_unit(u: Unit) -> void:
	if u.gone or u.sunk or not on_screen(u.x):
		return
	var pos := Vector2(roundf(u.x), roundf(u.y))
	var white: bool = u.flash > 0 and u.flash % 4 < 2
	match u.kind:
		"fuel":
			var lk: bool = u.leak != null
			draw_sprite("fuel_w" if (white or (lk and b.t % 20 < 10)) else "fuel", pos, Vector2(0.5, 1.0))
			if lk:
				Art.text(self, str(u.leak), pos + Vector2(0, -36), 16, Color("ff4d3d"), HORIZONTAL_ALIGNMENT_CENTER)
				if b.t % 8 == 0:
					b.part({"x": u.x + 8, "y": u.y - 6, "vx": 0.2, "vy": 0.5, "life": 30, "max": 30, "c": Color("ffe36a"), "s": 2.0, "g": 0.1})
			return
		"charge":
			draw_sprite("charge", pos, Vector2(0.5, 1.0))
			if b.t % 30 < 15:
				draw_rect(Rect2(pos.x - 1, pos.y - 14, 4, 4), Color("ff4d3d"))
			Art.text(self, "BOMB", pos + Vector2(0, -20), 8, Color("ff4d3d"), HORIZONTAL_ALIGNMENT_CENTER)
			return
		"barrel":
			draw_sprite("barrel_w" if white else "barrel", pos, Vector2(0.5, 1.0))
			return
		"crate":
			draw_sprite("crate_w" if white else "crate", pos, Vector2(0.5, 1.0))
			if b.t % 90 < 6:
				draw_rect(Rect2(pos.x + 4, pos.y - 14, 2, 2), Color(1, 1, 0.8))
			return
		"strongbox":
			draw_strongbox(pos, white)
			return
		"wreck":
			draw_wreck(u, pos)
			return
		"loot":
			draw_loot(u, pos)
			return
		"relay":
			draw_relay(u, pos)
			return
		"slug":
			draw_slug(u, pos, white)
			return
		"cache":
			# a glint in the dirt every couple of seconds
			var gy: float = b.T.ground_at(u.x)
			if (b.t + u.id * 37) % 120 < 10:
				var a := sin(((b.t + u.id * 37) % 120) / 10.0 * PI)
				draw_rect(Rect2(pos.x - 3, gy - 2, 7, 1), Color(1, 0.92, 0.5, a))
				draw_rect(Rect2(pos.x, gy - 5, 1, 7), Color(1, 0.92, 0.5, a))
			return
		"pad":
			draw_pad(u, pos)
			return
		"mine":
			# a dished steel plate half buried in the dirt, its light blinking faster when someone is close
			var near := b.squad_alive().any(func(s): return absf(s.x - u.x) < 70 and absf(s.y - u.y) < 40)
			draw_rect(Rect2(pos.x - 7, pos.y - 4, 14, 4), C_DARK)
			draw_rect(Rect2(pos.x - 6, pos.y - 4, 12, 3), Color("5a5f4a") if not white else Color.WHITE)
			draw_rect(Rect2(pos.x - 3, pos.y - 6, 6, 2), Color("3c4032"))
			var per := 8 if u.primed else (16 if near else 48)
			if b.t % per < per / 2:
				draw_rect(Rect2(pos.x - 1, pos.y - 7, 2, 2), Color("ff4d3d"))
				if near or u.primed:
					draw_circle(Vector2(pos.x, pos.y - 6), 4, Color(1, 0.3, 0.24, 0.35))
			return
		"pow":
			var fr := (b.t / 20) % 2
			var face := -1
			var jump := 0.0
			if u.freed:
				fr = 2 + (u.dead_t / 6) % 2
				jump = absf(sin(u.dead_t / 6.0)) * 10
				face = -1 if u.dead_t > 50 else 1
			draw_set_transform(pos + Vector2(0, -jump), 0, Vector2(Art.PX * face, Art.PX))
			draw_texture_rect_region(Art.tex.pow, Rect2(-12, -24, 24, 24), Rect2(fr * 24, 0, 24, 24))
			draw_set_transform_matrix(Transform2D.IDENTITY)
			if not u.freed:
				Art.text(self, "HELP!", pos + Vector2(0, -44 + sin(b.t / 10.0) * 2), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
			return
	if u.type == "boss":
		draw_boss(u, pos, white)
		return
	if u.type == "hive":
		draw_hive(u, pos, white)
		return
	if u.type == "burrow":
		draw_burrow(u, pos, white)
		return
	if u.type == "mg":
		var pa := pick_anim(u)
		Art.draw_char(self, u.sheet, "idle" if not u.dead else "die", pa[1], pos + Vector2(4, -8), -1, white, 0, u.alpha, u.gun_angle, not u.dead)
		draw_sprite("sandbags", pos + Vector2(-2, 0), Vector2(0.5, 1.0), u.alpha)
		if u.muzzle > 0 and not u.dead:
			draw_muzzle(Vector2(u.x - 22, u.y - 16), -1, 0)
		return
	if u.weight == "buried" and not u.dead:
		draw_mound(u, pos)
		return
	if u.sheet == "":
		return
	var a := pick_anim(u)
	var rot := 0.0
	if u.air and not u.para and not u.dead and Vector2(u.vx, u.vy).length() > 3 and not u.leaping and not u.jumping:
		rot = atan2(u.vy, u.vx) * 0.3 * u.face
	if u.rushing:
		rot = u.face * 0.5
	if u.dead and u.air:
		rot = u.rot
	if u.para:
		draw_set_transform(pos + Vector2(0, -50), 0, Vector2(Art.PX, Art.PX))
		var pt: Texture2D = Art.tex.parachute
		draw_texture(pt, Vector2(-pt.get_width() / 2.0, -pt.get_height() / 2.0))
		draw_set_transform_matrix(Transform2D.IDENTITY)
	if u.team == "squad" and not u.dead and u.adr >= 50:
		var glow := Color(1, 0.7, 0.24, 0.30) if u.adr >= 100 else Color(1, 0.48, 0.24, 0.20)
		var r := 18.0 + sin(b.t / 6.0) * 2
		draw_circle(pos + Vector2(0, -18), r, glow)
	if u.weight == "hover" and not u.dead:
		draw_pod(pos, white)
	var kick := Vector2(-u.face * 2, 0) if u.pose == "recoil" else Vector2.ZERO
	if u.team == "squad" and not u.dead and not white:
		# hero rim light: the flash silhouette in the theme's key light, peeking out above and behind
		var rim: Color = RIM.get(b.theme, RIM.dusk)
		for o in [Vector2(0, -2), Vector2(-u.face * 2, 0)]:
			Art.draw_char(self, u.sheet, a[0], a[1], pos + kick + o, u.face, true, rot, u.alpha * rim.a, u.gun_angle, false, 1.0, Color(rim, 1.0))
	var sc := 1.0 + 0.1 * maxi(0, u.fl.get("swell", 0)) if u.type == "bloater" else 1.0
	Art.draw_char(self, u.sheet, a[0], a[1], pos + kick, u.face, white, rot, u.alpha, u.gun_angle, a[2], sc)
	if not u.dead and (u.elite == "thrall" or u.fl.get("thrall", false)):
		# parasite veins showing through the Jackal's skin
		for k in 3:
			draw_rect(Rect2(pos.x - 6 + k * 5, pos.y - u.h * 0.75 + (k % 2) * 6, 2, 6), Color(C_OOZE, 0.75 + 0.2 * sin(b.t / 7.0 + k)))
	if u.dome > 0 and not u.dead:
		var r := maxf(u.w, u.h) / 2.0 + 8
		var c := pos + Vector2(0, -u.h / 2.0)
		draw_circle(c, r, Color(C_OOZE, 0.12 + 0.05 * sin(b.t / 8.0)))
		draw_arc(c, r, 0, TAU, 32, Color(C_OOZE, 0.7), 2.0)
		draw_arc(c, r - 4, -2.4, -1.6, 8, Color(1, 1, 1, 0.5), 2.0)
	if not u.dead:
		if u.shield:
			# riot shield held out front
			var sx := pos.x + u.face * 12
			draw_rect(Rect2(sx - 3, pos.y - 30, 7, 28), C_DARK)
			draw_rect(Rect2(sx - 2, pos.y - 29, 5, 26), Color.WHITE if white else Color("7d8590"))
			draw_rect(Rect2(sx + (1 if u.face > 0 else -2), pos.y - 29, 2, 26), Color("c9d1da"))
			draw_rect(Rect2(sx - 1, pos.y - 20, 3, 3), Color("2a6fb0"))
		if u.muzzle > 0 and u.sheet != "en_brute":
			var mo := Art.muzzle_offset(u.sheet, a[0], a[1], u.gun_angle)
			draw_muzzle(pos + kick + Vector2(mo.x * u.face, mo.y), u.face, u.gun_angle)

func draw_pad(u: Unit, pos: Vector2) -> void:
	## A bonus pad: a steel plate with a light strip. Counting down it projects the next bonus
	## and the rounds left; when ready the bonus floats over it for whoever gets there first.
	var L: Dictionary = u.loot
	var B: Dictionary = Data.BONUSES[b.pad_bonus(u)]
	draw_rect(Rect2(pos.x - 14, pos.y - 5, 28, 5), C_DARK)
	draw_rect(Rect2(pos.x - 13, pos.y - 4, 26, 3), Color("7d8590"))
	for i in 4:
		var on: bool = L.ready and (b.t / 6 + i) % 4 < 2
		draw_rect(Rect2(pos.x - 11 + i * 6, pos.y - 4, 4, 1), B.c if on or not L.ready and i < 4 - L.t else Color("3a3f46"))
	if L.ready:
		var by := pos.y - 24 + sin(b.t / 10.0) * 2
		draw_circle(Vector2(pos.x, by), 11 + sin(b.t / 5.0), Color(B.c, 0.22))
		draw_rect(Rect2(pos.x - 7, by - 7, 14, 14), C_DARK)
		draw_rect(Rect2(pos.x - 6, by - 6, 12, 12), B.c)
		draw_rect(Rect2(pos.x - 6, by - 6, 12, 2), Color(1, 1, 1, 0.45))
		Art.text(self, B.glyph, Vector2(pos.x + 1, by + 4), 8, C_DARK, HORIZONTAL_ALIGNMENT_CENTER, 0)
		Art.text(self, B.name, Vector2(pos.x, by - 12), 8, B.c, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var a := 0.35 + 0.15 * sin(b.t / 12.0)
		draw_rect(Rect2(pos.x - 6, pos.y - 26, 12, 22), Color(B.c, a * 0.25))
		draw_rect(Rect2(pos.x - 6, pos.y - 26, 12, 12), Color(B.c, a), false, 1.0)
		Art.text(self, B.glyph, Vector2(pos.x + 1, pos.y - 16), 8, Color(B.c, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 0)
		Art.text(self, "%s IN %d" % [B.name, L.t], Vector2(pos.x, pos.y - 30), 8, Color(B.c, 0.85), HORIZONTAL_ALIGNMENT_CENTER)

func draw_drill(u: Unit, d: Vector2, spin: bool) -> void:
	## A drill bit held out in front: a steel cone along the bore line, its threads turning.
	var base := Vector2(u.x + d.x * 6, u.y - u.h / 2.0 + d.y * 6)
	var tip := base + d * 16
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([base + n * 6, tip, base - n * 6]), Color("2a2622"))
	draw_colored_polygon(PackedVector2Array([base + n * 5 + d, tip - d, base - n * 5 + d]), Color("a9b0b6"))
	var ph := float(b.t % 4) / 4.0 if spin else 0.0
	for k in 3:
		var f := (k + ph) / 3.0
		var w := 5.0 * (1.0 - f)
		var m := base + d * (2 + 13 * f)
		draw_line(m + n * w, m - n * w + d * 2, Color("5d646b"), 1.0)
	draw_rect(Rect2(base.x - 4, base.y - 4, 8, 8), Color("ffb23e"))
	draw_rect(Rect2(base.x - 4, base.y - 4, 8, 8), Color("2a2622"), false, 1.0)

func draw_ghost(u: Unit, sim: Dictionary, col: Color, label: String) -> void:
	## Where a soldier will end up: a dotted path and a see-through copy of them at the end.
	var i := 0
	while i < sim.pts.size():
		var p: Vector2 = sim.pts[i]
		draw_rect(Rect2(p.x - 1, p.y - u.h / 2.0 - 1, 2, 2), Color(col, 0.75))
		i += 3
	var bad: bool = sim.water or sim.fall > 0
	var c := Color("ff4d3d") if bad else col
	if sim.water:
		label += ": INTO THE WATER"
	elif sim.fall > 0:
		label += ": FALL -%d" % sim.fall
	Art.draw_char(self, u.sheet, "idle", 0, Vector2(sim.x, sim.y), u.face, false, 0, 0.45, 0.0, false, 1.0, c)
	Art.text(self, label, Vector2(sim.x, sim.y - u.h - 8), 8, c, HORIZONTAL_ALIGNMENT_CENTER)

func draw_strongbox(pos: Vector2, white: bool) -> void:
	var r := Rect2(pos.x - 10, pos.y - 14, 20, 14)
	draw_rect(r.grow(1), C_DARK)
	draw_rect(r, Color.WHITE if white else Color("4a5a3a"))
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3), Color("6a7a52"))
	draw_rect(Rect2(r.position.x + 3, r.position.y, 2, r.size.y), Color("2e3a24"))
	draw_rect(Rect2(r.end.x - 5, r.position.y, 2, r.size.y), Color("2e3a24"))
	draw_rect(Rect2(pos.x - 2, pos.y - 9, 4, 4), Color("ffd23a"))
	draw_rect(Rect2(pos.x - 1, pos.y - 7, 2, 2), C_DARK)

func draw_loot(u: Unit, pos: Vector2) -> void:
	## A pickup: a small box glowing in its rarity color, a letter disc, a coin pile or a trophy.
	var L: Dictionary = u.loot
	var bob := sin((b.t + u.id * 13) / 9.0) * 2 if not u.air else 0.0
	var p := pos + Vector2(0, -6 + bob)
	match L.type:
		"letter":
			draw_circle(p + Vector2(0, -4), 10, C_DARK)
			draw_circle(p + Vector2(0, -4), 9, Color("ffd23a") if b.t % 20 < 14 else Color("ffb23e"))
			Art.text(self, L.key, p + Vector2(1, 1), 16, Color("8a1a0a"), HORIZONTAL_ALIGNMENT_CENTER)
		"scrip":
			draw_texture_rect(Art.tex.ic_coin, Rect2(p.x - 6, p.y - 10, 12, 12), false)
		"trophy":
			draw_circle(p + Vector2(0, -4), 11, Color(1, 0.7, 0.12, 0.3 + 0.2 * sin(b.t / 5.0)))
			draw_texture_rect(Art.tex.ic_star, Rect2(p.x - 8, p.y - 12, 16, 16), false)
		_:
			var t: int = L.item.tier
			var col := Data.tier_color(t)
			draw_circle(p + Vector2(0, -4), 9 + (2 if t >= 3 else 0), Color(col, 0.25 + 0.15 * sin(b.t / 6.0)))
			draw_rect(Rect2(p.x - 6, p.y - 10, 12, 10), C_DARK)
			draw_rect(Rect2(p.x - 5, p.y - 9, 10, 8), col.darkened(0.2))
			draw_rect(Rect2(p.x - 5, p.y - 9, 10, 2), col.lightened(0.3))
			draw_rect(Rect2(p.x - 1, p.y - 9, 2, 8), C_DARK)
			if t >= 3 and b.t % 30 < 4:
				draw_rect(Rect2(p.x + 5, p.y - 14, 2, 2), Color.WHITE)

func draw_sprite(key: String, pos: Vector2, anchor: Vector2, alpha := 1.0, flip := false) -> void:
	var tx: Texture2D = Art.tex[key]
	var sz := Vector2(tx.get_width(), tx.get_height())
	draw_set_transform(pos, 0, Vector2(Art.PX * (-1 if flip else 1), Art.PX))
	draw_texture(tx, -sz * anchor, Color(1, 1, 1, alpha))
	draw_set_transform_matrix(Transform2D.IDENTITY)

func draw_muzzle(p: Vector2, face: int, ang: float) -> void:
	var tx: Texture2D = Art.tex.muzzle
	var fr := (b.t / 2) % 3
	draw_circle(p + Vector2(face * 6, 0), 14, Color(1, 0.75, 0.35, 0.22))
	draw_set_transform(p, ang * face, Vector2(Art.PX * face, Art.PX))
	draw_texture_rect_region(tx, Rect2(0, -6, 16, 12), Rect2(fr * 16, 0, 16, 12))
	draw_set_transform_matrix(Transform2D.IDENTITY)

func draw_boss(u: Unit, pos: Vector2, white: bool) -> void:
	var tx: Texture2D = Art.tex.boss
	var ph := int(u.tread / 3) % 2
	var row := (0 if u.plate > 0 else 1) + (2 if white else 0)
	var mod := Color(0.45, 0.42, 0.4, u.alpha) if u.dead else Color(1, 1, 1, u.alpha)
	# barrel behind the turret
	var pv := b.boss_pivot(u)
	var bt: Texture2D = Art.tex.boss_barrel
	draw_set_transform(pv, u.aim_a, Vector2(-Art.PX, Art.PX))
	draw_texture(bt, Vector2(-2, -bt.get_height() / 2.0), mod)
	draw_set_transform(pos, 0, Vector2(Art.PX, Art.PX))
	draw_texture_rect_region(tx, Rect2(-32, -40, 64, 40), Rect2(ph * 64, row * 40, 64, 40), mod)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if u.muzzle > 0 and not u.dead:
		draw_muzzle(b.muzzle(u), -1, -u.aim_a)
	if u.dead and b.t % 6 == 0:
		b.puff(u.x + randf_range(-40, 40), u.y - 60, 1.8)
	if u.cracked and not u.dead and b.t % 10 == 0:
		b.puff(u.x + randf_range(-20, 30), u.y - 50, 1.0)

func draw_relay(u: Unit, pos: Vector2) -> void:
	## W3: a radio mast. Blinks red until a soldier ends a turn on it, then flies a green pennant.
	var taken: bool = u.loot.taken
	var metal := Color("6c7480")
	draw_rect(Rect2(pos.x - 1, pos.y - 34, 3, 34), metal)
	draw_line(pos + Vector2(-7, 0), pos + Vector2(0, -20), metal, 2)
	draw_line(pos + Vector2(8, 0), pos + Vector2(1, -20), metal, 2)
	draw_rect(Rect2(pos.x - 6, pos.y - 30, 6, 6), Color("9aa2ae"))
	var lit := Color("62d26f") if taken else (Color("ff4d3d") if b.t % 40 < 20 else Color("5a1a14"))
	draw_rect(Rect2(pos.x - 1, pos.y - 38, 3, 3), lit)
	if taken:
		draw_colored_polygon(PackedVector2Array([pos + Vector2(2, -34), pos + Vector2(14, -31), pos + Vector2(2, -28)]), Color("62d26f"))
	else:
		var bf: Dictionary = Data.RELAY_BUFFS[u.loot.buff]
		Art.text(self, "RELAY: " + bf.name, pos + Vector2(0, -44), 8, Color("53d4e2"), HORIZONTAL_ALIGNMENT_CENTER)

func draw_slug(u: Unit, pos: Vector2, white: bool) -> void:
	## The SV-001: the Boar's chassis, repainted in squad green and facing east.
	var tx: Texture2D = Art.tex.boss
	var ph := int(u.tread / 3) % 2
	var mod := Color(0.62, 1.0, 0.6) if not white else Color(1.6, 1.6, 1.6)
	var bt: Texture2D = Art.tex.boss_barrel
	draw_set_transform(pos + Vector2(10, -30), -0.25, Vector2(Art.PX, Art.PX))
	draw_texture(bt, Vector2(-2, -bt.get_height() / 2.0), mod)
	draw_set_transform(pos, 0, Vector2(-Art.PX, Art.PX))
	draw_texture_rect_region(tx, Rect2(-32, -40, 64, 40), Rect2(ph * 64, 0, 64, 40), mod)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	Art.text(self, "SV-001", pos + Vector2(0, -92), 8, Color("62d26f"), HORIZONTAL_ALIGNMENT_CENTER)

func draw_wreck(u: Unit, pos: Vector2) -> void:
	## A burnt-out jeep on its rims. Stripped ones lose the panels and the glint.
	var d := Color(0.05, 0.035, 0.03)
	var hull := Color("5a4a3a") if u.stripped else Color("7a5a3a")
	draw_rect(Rect2(pos.x - 17, pos.y - 14, 34, 10), d)
	draw_rect(Rect2(pos.x - 16, pos.y - 13, 32, 8), hull)
	draw_rect(Rect2(pos.x - 8, pos.y - 20, 14, 7), d)
	draw_rect(Rect2(pos.x - 7, pos.y - 19, 12, 5), hull.darkened(0.2))
	for wx in [-10, 10]:
		draw_circle(pos + Vector2(wx, -4), 4.0, d)
		draw_circle(pos + Vector2(wx, -4), 2.0, Color("3a3a3a"))
	if not u.stripped:
		draw_rect(Rect2(pos.x - 14, pos.y - 11, 6, 3), Color("9a6a3a"))
		draw_rect(Rect2(pos.x + 4, pos.y - 11, 8, 2), Color("a8a8a8"))
		if (b.t + u.id * 23) % 100 < 8:
			draw_rect(Rect2(pos.x + 6, pos.y - 17, 2, 2), Color("53d4e2"))
		Art.text(self, "SALVAGE", pos + Vector2(0, -26), 8, Color("53d4e2"), HORIZONTAL_ALIGNMENT_CENTER)

# ---------------------------------------------------------------- in-world HUD plates
func draw_plate(u: Unit) -> void:
	if u.dead or u.gone or u.sunk or u.kind in ["pow", "fuel", "charge", "barrel", "crate", "strongbox", "loot", "cache", "relay", "slug", "mine", "wreck", "pad"] or u.type == "boss" or not on_screen(u.x, 40):
		return
	var x := roundf(u.x)
	if u.team == "squad":
		draw_squad_plate(u, x)
		return
	# enemy: segmented red bar over the head
	var y := roundf(u.y - u.h - 10)
	var w := 24.0
	draw_rect(Rect2(x - w / 2 - 1, y - 1, w + 2, 5), C_DARK)
	draw_rect(Rect2(x - w / 2, y, w, 3), Color("3a0d0d"))
	draw_rect(Rect2(x - w / 2, y, roundf(w * u.hp / u.max_hp), 3), Color("ff4d3d"))
	for k in range(1, 4):
		draw_rect(Rect2(x - w / 2 + k * w / 4, y, 1, 3), C_DARK)
	if u.pod > 0 and u.weight == "hover":
		var pm: int = int(round(Data.ETYPES[u.type].pod * b.mission.hp_mul))
		draw_rect(Rect2(x - w / 2 - 1, y + 4, w + 2, 4), C_DARK)
		draw_rect(Rect2(x - w / 2, y + 5, roundf(w * u.pod / maxf(1, pm)), 2), C_ALIEN)
	if u.weight != "" and u.elite == "":
		Art.text(self, u.weight.to_upper(), Vector2(x, y - 4), 8, C_ALIEN, HORIZONTAL_ALIGNMENT_CENTER)
	if u.elite != "":
		draw_rect(Rect2(x - w / 2 - 2, y - 2, w + 4, 7), Color("ffd23a"), false, 1.0)
		Art.text(self, Data.ELITES[u.elite].name, Vector2(x, y - 4), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
	draw_statuses(u, x, y - (14 if u.elite != "" else 4))
	if u.type == "radio" and b.radio_t != null and u.active:
		var col := Color("ff4d3d") if b.radio_t <= 1 else Color("ffd23a")
		draw_texture_rect(Art.tex.ic_radio, Rect2(clampf(x, b.cam_x + 44, b.cam_x + 916) - 34, y - 16, 16, 16), false)
		Art.text(self, "BACKUP %d" % b.radio_t, Vector2(clampf(x, b.cam_x + 44, b.cam_x + 916) - 14, y - 4), 8, col)

func draw_squad_plate(u: Unit, x: float) -> void:
	# dog-tag style plate at the feet: HP blocks, adrenaline flame bar, energy bolts
	var y := roundf(u.y + 4)
	var w := 34.0
	var sel: bool = u == b.sel
	draw_rect(Rect2(x - w / 2 - 2, y - 1, w + 4, 11), Color(C_DARK, 0.85))
	draw_rect(Rect2(x - w / 2 - 2, y - 1, w + 4, 1), Color("9aa2ae") if sel else Color("4a505a"))
	var segs := u.max_hp
	var hpw := roundf(w * u.hp / float(u.max_hp))
	var hc := Color("62d26f") if u.hp > u.max_hp * 0.5 else (Color("ffd23a") if u.hp > u.max_hp * 0.25 else Color("ff4d3d"))
	draw_rect(Rect2(x - w / 2, y + 1, w, 4), Color("1e3a22"))
	draw_rect(Rect2(x - w / 2, y + 1, hpw, 4), hc)
	var k := 4
	while k < segs:
		draw_rect(Rect2(x - w / 2 + roundf(w * k / float(segs)), y + 1, 1, 4), Color(C_DARK, 0.8))
		k += 4
	var ac := Color("ffb23e") if u.adr >= 100 else Color("ff7a3d")
	draw_rect(Rect2(x - w / 2, y + 6, roundf(w * u.adr / 100.0), 2), ac)
	if u.fuel_max > 0:
		# Jet Boots fuel: a blue strip under the plate
		draw_rect(Rect2(x - w / 2 - 2, y + 10, w + 4, 4), Color(C_DARK, 0.85))
		draw_rect(Rect2(x - w / 2, y + 11, roundf(w * u.fuel / float(u.fuel_max)), 2), Color("53d4e2") if u.fuel > 0 else Color("4a505a"))
	if u.adr >= 50:
		draw_texture_rect(Art.tex.ic_flame, Rect2(x + w / 2 + 2, y - 2, 8, 8), false)
	if u.armor > 0:
		draw_texture_rect(Art.tex.ic_shield, Rect2(x - w / 2 - 12, y - 1, 8, 8), false)
		Art.text(self, str(u.armor), Vector2(x - w / 2 - 14, y + 7), 8, Color("9fb4c9"), HORIZONTAL_ALIGNMENT_RIGHT)
	if u.overwatch > 0:
		Art.text(self, "OW", Vector2(x, y + 18), 8, Color("53d4e2"), HORIZONTAL_ALIGNMENT_CENTER)
	draw_statuses(u, x, y + (28 if u.overwatch > 0 else 18))
	if b.state == "player":
		for i in u.energy:
			draw_texture_rect(Art.tex.ic_bolt, Rect2(x - u.energy * 4.5 + i * 9, y - 12 - u.h - 8, 8, 8), false)
	if b.inspect and b.state == "player":
		var info := "%dE  %dpx  ADR %d%s" % [u.energy, int(maxf(0, u.move_left)), u.adr, "  OW" if u.overwatch > 0 else ""]
		var tw := Art.text_width(info, 8) + 6
		var iy := u.y - u.h - 58 - b.squad().find(u) * 13
		draw_rect(Rect2(x - tw / 2, iy, tw, 12), Color(C_DARK, 0.85))
		Art.text(self, info, Vector2(x, iy + 10), 8, Color("62d26f") if b.can_act(u) else Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER)
	if sel and b.state == "player":
		var by := u.y - u.h - 36 + sin(b.t / 8.0) * 2
		var pts := PackedVector2Array([Vector2(x - 6, by), Vector2(x + 6, by), Vector2(x, by + 7)])
		draw_colored_polygon(PackedVector2Array([Vector2(x - 7, by - 1), Vector2(x + 7, by - 1), Vector2(x, by + 8)]), C_DARK)
		draw_colored_polygon(pts, Color("ffb23e"))
		Art.text(self, "%s LV%d" % [u.def.name, u.s.lvl], Vector2(x, by - 4), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)

func draw_statuses(u: Unit, x: float, y: float) -> void:
	## Short colored tags for C5 statuses, plus AIR for a body a squadmate launched (SKEET bait).
	var tags: Array = []
	if u.team == "enemy" and u.air and not u.para and u.last_hit_by is Unit and u.last_hit_by.team == "squad":
		tags.append(["AIR", Color("9fe3f0")])
	for k in u.st:
		if u.st[k] > 0:
			tags.append([Data.STATUS[k].short, Data.STATUS[k].c])
	if tags.is_empty():
		return
	var tw := 0.0
	for tg in tags:
		tw += Art.text_width(tg[0], 8) + 4
	var cx := x - tw / 2
	draw_rect(Rect2(cx - 2, y - 9, tw + 2, 11), Color(C_DARK, 0.8))
	for tg in tags:
		Art.text(self, tg[0], Vector2(cx, y), 8, tg[1])
		cx += Art.text_width(tg[0], 8) + 4

# ---------------------------------------------------------------- effects
func draw_smokes() -> void:
	for g in b.gases:
		for i in 8:
			var a: float = i / 8.0 * TAU + b.t / 160.0 + g.seed
			var r: float = g.r * 0.45
			var pulse := 0.05 * sin(b.t / 20.0 + i)
			draw_circle(Vector2(g.x + cos(a) * r * 0.9, g.y + sin(a) * r * 0.5), g.r * 0.45, Color(0.55 + pulse, 0.85, 0.3, 0.28))
	for s in b.smokes:
		for i in 9:
			var a: float = i / 9.0 * TAU + b.t / 200.0 + s.seed
			var r: float = s.r * 0.45
			var g := 0.75 + i * 0.015
			draw_circle(Vector2(s.x + cos(a) * r * 0.9, s.y + sin(a) * r * 0.55), s.r * 0.5, Color(g, g, g + 0.03, 0.42))

func draw_projs() -> void:
	for p in b.projs:
		var pos := Vector2(roundf(p.x), roundf(p.y))
		match p.kind:
			"rocket":
				var a := atan2(p.vy, p.vx)
				draw_set_transform(pos, a, Vector2.ONE)
				draw_rect(Rect2(-9, -3, 14, 6), C_DARK)
				draw_rect(Rect2(-8, -2, 12, 4), Color("d8d0b8"))
				draw_rect(Rect2(3, -2, 3, 4), Color("ff4d3d"))
				draw_rect(Rect2(-14 - (b.t % 3) * 2, -2, 6 + (b.t % 3) * 2, 4), Color("ffb23e"))
				draw_rect(Rect2(-12, -1, 4, 2), Color("fff3b0"))
				draw_set_transform_matrix(Transform2D.IDENTITY)
			"bomb":
				draw_rect(Rect2(pos.x - 5, pos.y - 11, 10, 16), C_DARK)
				draw_rect(Rect2(pos.x - 4, pos.y - 10, 8, 14), Color("3a3a3a"))
				draw_rect(Rect2(pos.x - 7, pos.y - 13, 14, 4), Color("7a7a7a"))
				draw_rect(Rect2(pos.x - 1, pos.y + 2, 2, 2), Color("ff4d3d"))
			_:
				var col := Color("2a2a2a")
				if p.cluster:
					col = Color("b8322a")
				elif p.kind == "frag":
					col = Color("4a6a2a")
				elif p.kind == "smoke":
					col = Color("9aa0a8")
				elif p.kind == "egren":
					col = Color("6a4a2a")
				elif p.kind == "beacon":
					col = Color("62d26f") if b.t % 10 < 5 else Color("2a6a34")
				var r := 5.0 if p.kind == "shell" else (3.0 if p.mini else 4.0)
				draw_rect(Rect2(pos.x - r - 1, pos.y - r - 1, r * 2 + 2, r * 2 + 2), C_DARK)
				draw_rect(Rect2(pos.x - r, pos.y - r, r * 2, r * 2), col)
				draw_rect(Rect2(pos.x - r, pos.y - r, 2, 2), Color(1, 1, 1, 0.5))
				if p.fuse != null and not p.mini:
					draw_rect(Rect2(pos.x - 1, pos.y - r - 3, 2, 2), Color("fff3a0") if b.t % 6 < 3 else Color("ff4d3d"))
					Art.text(self, "%.1f" % (p.fuse / 60.0), pos + Vector2(0, -12), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)

func draw_parts() -> void:
	for p in b.parts:
		if not on_screen(p.x, 40):
			continue
		var a: float = float(p.life) / p.max
		if p.get("ring", false):
			draw_arc(Vector2(p.x, p.y), p.r, 0, TAU, 32, Color(1, 0.94, 0.78, a), 3.0)
			continue
		var c: Color = p.c
		if p.get("smoke", false):
			c.a = a * 0.5
		else:
			c.a = minf(1, a * 1.5)
		var s: float = roundf(p.s)
		if p.get("helmet", false):
			# R2: the popped helmet, a dome with a brim
			draw_rect(Rect2(roundf(p.x) - 4, roundf(p.y) - 4, 8, 5), Color(C_DARK, c.a))
			draw_rect(Rect2(roundf(p.x) - 3, roundf(p.y) - 3, 6, 3), c)
			draw_rect(Rect2(roundf(p.x) - 5, roundf(p.y), 10, 2), c.darkened(0.3))
			continue
		if p.get("plus", false):
			draw_rect(Rect2(roundf(p.x) - 1, roundf(p.y) - 3, 2, 6), c)
			draw_rect(Rect2(roundf(p.x) - 3, roundf(p.y) - 1, 6, 2), c)
			continue
		draw_rect(Rect2(roundf(p.x - s / 2), roundf(p.y - s / 2), s, s), c)

func draw_fx() -> void:
	for f in b.fx:
		if f.t < 0:
			continue
		var pos := Vector2(roundf(f.x), roundf(f.y))
		match f.kind:
			"boom":
				var fr := clampi(int(f.t * 14 / f.dur), 0, 13)
				var s: float = Art.PX * f.sc * 0.5
				draw_set_transform(pos, 0, Vector2(s, s))
				draw_texture_rect_region(Art.tex.explosion, Rect2(-24, -32, 48, 48), Rect2(fr * 48, 0, 48, 48))
				draw_set_transform_matrix(Transform2D.IDENTITY)
			"puff":
				var fr := clampi(int(f.t * 6 / f.dur), 0, 5)
				var s: float = Art.PX * f.sc * 0.4
				draw_set_transform(pos, 0, Vector2(s, s))
				draw_texture_rect_region(Art.tex.puff, Rect2(-8, -8, 16, 16), Rect2(fr * 16, 0, 16, 16), Color(1, 1, 1, 0.85))
				draw_set_transform_matrix(Transform2D.IDENTITY)
			"slash":
				var fr := clampi(int(f.t * 3 / f.dur), 0, 2)
				var s: float = Art.PX * f.sc * 0.5
				draw_set_transform(pos, 0, Vector2(s * f.face, s))
				draw_texture_rect_region(Art.tex.slash, Rect2(-10, -10, 20, 20), Rect2(fr * 20, 0, 20, 20))
				draw_set_transform_matrix(Transform2D.IDENTITY)

# ---------------------------------------------------------------- targeting overlays
func draw_targeting() -> void:
	if b.state != "player" or b.busy:
		return
	var u: Unit = b.sel
	if u == null or u.dead:
		return
	var m: Vector2 = b.mouse
	var pz := b.cam_x + Battle.W * 0.72
	if b.cam_x < b.world_w - Battle.W:
		var yy := 48.0
		while yy < Battle.H:
			draw_rect(Rect2(pz, yy, 2, 6), Color(1, 0.7, 0.24, 0.5))
			yy += 12
		draw_rect(Rect2(pz, 40, Battle.W * 0.28, Battle.H - 40), Color(1, 0.7, 0.24, 0.05))
		Art.text(self, "PUSH ZONE >>", Vector2(pz + 8, 58), 8, Color("ffb23e"))
	if b.jet_armed:
		var sim := b.sim_body(u, 0.0, 0.0, m, u.fuel)
		draw_dashed_line(Vector2(u.x, u.y - u.h / 2.0), m, Color(0.33, 0.83, 0.89, 0.6), 1.0, 4.0)
		draw_ghost(u, sim, Color("53d4e2"), "JET")
		Art.text(self, "HOLD CLICK TO FLY   FUEL %d" % u.fuel, Vector2(m.x + 12, m.y + 22), 8, Color("53d4e2"))
		draw_reticle(m, Color("53d4e2"))
		return
	if b.card_idx < 0:
		if u.move_left > 1:
			var L := b.sim_walk(u, u.x - u.move_left, u.move_left)
			var R := b.sim_walk(u, u.x + u.move_left, u.move_left)
			for s in [L, R]:
				var i := 0
				while i < s.pts.size():
					draw_rect(Rect2(s.pts[i][0] - 1, s.pts[i][1] - 2, 3, 2), Color(0.38, 0.82, 0.44, 0.7))
					i += 2
				if s.pts.size():
					draw_rect(Rect2(s.x - 1, s.y - 12, 2, 12), Color("62d26f"))
			var hov = b.unit_at_p(m)
			var LD = b.ladder_at(m) if hov == null else null
			var pl = b.plan_climb(u, LD) if LD != null else null
			if LD != null and absf(u.y - LD.top) >= 8:
				if pl != null:
					var i := 0
					while i < pl.pts.size():
						draw_rect(Rect2(pl.pts[i][0] - 1, pl.pts[i][1] - 3, 3, 3), Color.WHITE)
						i += 4
					Art.draw_char(self, u.sheet, "idle", 0, Vector2(LD.offx, LD.top), u.face, false, 0, 0.45)
					Art.text(self, "CLIMB %dpx" % int(pl.cost), Vector2(LD.offx, LD.top - 44), 8, Color("62d26f"), HORIZONTAL_ALIGNMENT_CENTER)
				else:
					Art.text(self, "LADDER: OUT OF REACH", Vector2(LD.x, LD.top - 14), 8, Color("ff7a3d"), HORIZONTAL_ALIGNMENT_CENTER)
			elif hov == null:
				var sim := b.sim_walk(u, m.x, u.move_left)
				if sim.pts.size():
					var i := 0
					while i < sim.pts.size():
						draw_rect(Rect2(sim.pts[i][0] - 1, sim.pts[i][1] - 3, 3, 3), Color.WHITE)
						i += 4
					Art.draw_char(self, u.sheet, "idle", 0, Vector2(sim.x, sim.y), -1 if sim.x < u.x else 1, false, 0, 0.45)
					Art.text(self, "%dpx" % int(sim.used), Vector2(sim.x, sim.y - 44), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		return
	if b.card_idx >= u.hand.size():
		return
	var inst: Dictionary = u.hand[b.card_idx]
	var c := Data.card(inst)
	var sc: bool = u.adr >= 50 and not inst.get("od", false)
	match c.type:
		"AIM":
			var aa := b.aim_angle(u, c, m)
			var tr := b.trace_bullet(aa.mx, aa.my, aa.a, c.range, c.get("bounce", 0) + b.bounce_bonus(u, sc), u, c.get("pierce", false))
			# the laser only reveals the first stretch of the path; the bullet keeps going
			var L := b.laser_of(u, c)
			var acc := 0.0
			var tip := Vector2(aa.mx, aa.my)
			for i in tr.segs.size():
				var s: Array = tr.segs[i]
				var a0 := Vector2(s[0], s[1])
				var a1 := Vector2(s[2], s[3])
				var sl := a0.distance_to(a1)
				var cut := a1 if acc + sl <= L else a0.lerp(a1, clampf((L - acc) / maxf(sl, 0.001), 0, 1))
				if i == 0:
					draw_line(a0, cut, Color(1, 0.24, 0.24, 0.95), 2.0)
				else:
					draw_dashed_line(a0, cut, Color(1, 0.35, 0.35, 0.6), 1.0, 5.0)
				tip = cut
				acc += sl
				if acc >= L:
					break
			var cut_short: bool = tr.len > L
			if cut_short:
				draw_circle(tip, 2.0, Color(1, 0.35, 0.35, 0.5 + 0.3 * sin(b.t / 6.0)))
			for i in tr.pings.size():
				if tr.ping_d[i] <= L:
					var p: Vector2 = tr.pings[i]
					draw_rect(Rect2(p.x - 2, p.y - 2, 4, 4), Color.WHITE)
			if c.has("spread") and c.has("pellets"):
				var sp := minf(L, 400.0)
				for d in [-c.spread, c.spread]:
					draw_line(Vector2(aa.mx, aa.my), Vector2(aa.mx + cos(aa.a + d) * sp, aa.my + sin(aa.a + d) * sp), Color(1, 0.35, 0.35, 0.35), 1.0)
			var seen: Array = tr.hits.filter(func(hh): return hh.d <= L)
			for hh in seen:
				var tg: Unit = hh.u
				var col := Color("ffb23e") if hh.head else Color("ff4d3d")
				draw_brackets(Rect2(tg.x - tg.w / 2 - 4, tg.y - tg.h - 4, tg.w + 8, tg.h + 8), col)
				var lab := "BODY"
				if tg.dead: lab = "CORPSE BLOCKS"
				elif tg.kind == "fuel": lab = "LEAK"
				elif tg.kind == "charge": lab = "DEFUSE"
				elif tg.kind == "crate": lab = "OPEN"
				elif tg.kind == "strongbox": lab = "LOCKED: BLAST OR PRY"
				elif tg.is_prop(): lab = "BOOM"
				elif hh.head: lab = "HEAD!"
				elif tg.shield and hh.dx > 0: lab = "SHIELD"
				elif tg.type == "boss" and tg.plate > 0: lab = "ARMOR"
				Art.text(self, lab, Vector2(tg.x, tg.y - tg.h - 22), 16 if hh.head else 8, col, HORIZONTAL_ALIGNMENT_CENTER)
			if seen.is_empty() and not cut_short:
				var ls: Array = tr.segs[-1]
				var em: int = tr.end.m if tr.end != null else 0
				var lab := "MISS"
				if em == 3: lab = "CHIPS WOOD"
				elif em == 1: lab = "DIGS DIRT"
				elif em: lab = "BLOCKED"
				Art.text(self, lab, Vector2(ls[2], ls[3] - 10), 8, Color("ffd23a") if em == 3 else Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER)
			var gun: Dictionary = Data.GUNS.get(c.get("gun", "rifle"), Data.GUNS.rifle)
			Art.text(self, "%s SIGHT %s" % [gun.name, ("FULL" if L > 9999.0 else "%dpx" % int(L))], Vector2(m.x + 12, m.y + 22), 8, Color("ff8a80"))
			var sw := b.sway_of(u, c)
			Art.text(self, "STEADY" if sw < 0.01 else ("WILD SWAY" if sw > 0.06 else ("SWAY  [SHIFT] HOLD" if not b.aim_hold else "HOLDING")), Vector2(aa.mx, u.y + 30), 8, Color("ff7a3d") if sw > 0.06 else Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER)
			draw_reticle(m, Color(1, 0.3, 0.3))
			draw_recoil(u, c, aa.a)
		"ARC":
			var v := b.aim_vel(u, m)
			var fz = b.armed_fuse()
			if fz != null:
				# K1: the whole bouncing flight up to the fuse, and where it bursts
				var eff: int = int(fz / 2) if u.perk("shortfuse") else fz
				var gs := b.sim_grenade(v.hx, v.hy, v.vx, v.vy, c.get("wind", 1.0), eff)
				for i in gs.pts.size():
					if i % 3 == 0:
						var p: Vector2 = gs.pts[i]
						draw_rect(Rect2(p.x - 1, p.y - 1, 3, 3), Color(1, 1, 1, maxf(0.25, 1 - i / float(eff + 20))))
				var bp := Vector2(gs.x, gs.y)
				if not gs.lost:
					var rr: float = c.get("radius", 30) * b.blast_scale(u)
					draw_arc(bp, rr, 0, TAU, 32, Color(1, 0.45, 0.2, 0.7), 1.0)
					draw_rect(Rect2(bp.x - 3, bp.y - 3, 6, 6), Color("ff7a3d"))
				Art.text(self, "FUSE %.1fs  [WHEEL]" % (eff / 60.0), Vector2(m.x + 12, m.y + 22), 8, Color("ffd23a"))
			var sim := b.sim_arc(v.hx, v.hy, v.vx, v.vy, c.get("wind", 1.0), 40)
			for i in (sim.pts.size() if fz == null else 0):
				if i % 2 == 0:
					var p: Vector2 = sim.pts[i]
					draw_rect(Rect2(p.x - 1, p.y - 1, 3, 3), Color(1, 1, 1, 1 - i / 44.0))
			draw_line(Vector2(v.hx, v.hy), Vector2(v.hx + v.vx * 5, v.hy + v.vy * 5), Color("ffb23e"), 2.0)
			var px := u.x - 20
			var py := u.y + 22
			draw_rect(Rect2(px, py, 40, 6), C_DARK)
			draw_rect(Rect2(px + 1, py + 1, roundf(38 * v.pw / 13), 4), Color.from_hsv((120 - v.pw / 13 * 120) / 360.0, 0.9, 0.95))
			Art.text(self, "PWR", Vector2(px - 4, py + 7), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		"LINE":
			if c.get("grapple", false):
				var gs := b.grapple_spot(u, m, c.range)
				draw_dashed_line(Vector2(gs.hx, gs.hy), Vector2(gs.ax, gs.ay), Color("62d26f") if gs.ok else Color("ff4d3d"), 1.0, 4.0)
				if gs.ok:
					Art.draw_char(self, u.sheet, "idle", 0, Vector2(gs.x, gs.y), u.face, false, 0, 0.5)
				else:
					Art.text(self, "NO GRIP", Vector2(gs.ax, gs.ay - 10), 8, Color("ff4d3d"), HORIZONTAL_ALIGNMENT_CENTER)
			elif c.get("drill", false):
				var d := b.drill_dir(u, m)
				var reach: float = u.move_left + c.get("reach", 0)
				var sim := b.sim_drill(u, d, b.drill_len(u, c, m))
				var o := Vector2(u.x, u.y - u.h / 2.0)
				draw_dashed_line(o, o + d * reach, Color(1, 0.82, 0.23, 0.35), 1.0, 4.0)
				draw_drill(u, d, false)
				if sim.pts.size():
					draw_ghost(u, sim, Color("ffd23a"), "DRILL %dpx" % int(Vector2(sim.x, sim.y).distance_to(Vector2(u.x, u.y))))
				else:
					Art.text(self, "CAN'T DRILL THERE", Vector2(u.x, u.y - u.h - 8), 8, Color("ff4d3d"), HORIZONTAL_ALIGNMENT_CENTER)
			elif c.get("jump", false) or c.get("rush", false):
				var v := b.jump_vel(u, m, c.get("jpow", 1.0)) if c.get("jump", false) else b.rush_vel(u, m)
				var sim := b.sim_arc(u.x, u.y - u.h / 2.0, v.vx, v.vy, 0, 70 if c.get("jump", false) else 50)
				for i in sim.pts.size():
					if i % 2 == 0:
						var p: Vector2 = sim.pts[i]
						draw_rect(Rect2(p.x - 1, p.y - 1, 3, 3), Color("62d26f") if c.get("jump", false) else Color("ffb23e"))
			else:
				var hp_ := b.hand_pos(u)
				var a := atan2(m.y - hp_.y, m.x - hp_.x)
				var end := b.cast_ray(hp_.x, hp_.y, a, 900)
				draw_dashed_line(hp_, Vector2(end.x, end.y), Color(1, 0.48, 0.24, 0.9), 2.0, 8.0)
				if end.hit:
					var R: float = c.radius * (1.2 if sc else 1.0) * b.blast_scale(u)
					draw_arc(Vector2(end.x, end.y), R, 0, TAU, 32, Color("ff7a3d"), 2.0)
					var al := b.squad_alive().filter(func(s): return Vector2(s.x - end.x, s.y - s.h / 2.0 - end.y).length() < R + s.w / 2.0)
					if al.size():
						for s in al:
							draw_brackets(Rect2(s.x - s.w / 2 - 4, s.y - s.h - 4, s.w + 8, s.h + 8), Color("ff4d3d"))
						Art.text(self, "YOU ARE IN THE BLAST" if al.has(u) else "ALLY IN BLAST", Vector2(end.x, end.y - R - 8), 8, Color("ff4d3d"), HORIZONTAL_ALIGNMENT_CENTER)
				draw_reticle(m, Color("ff7a3d"))
				draw_recoil(u, c, a)
		"MELEE", "ALLY":
			var lst: Array
			if c.type == "MELEE":
				lst = b.units.filter(func(tg): return b.melee_valid(u, tg, c))
			else:
				lst = b.squad_alive().filter(func(tg): return b.ally_valid(u, tg, c))
			var col := Color("ff4d3d") if c.type == "MELEE" else Color("62d26f")
			for tg in lst:
				draw_arc(Vector2(tg.x, tg.y - tg.h / 2.0), tg.h * 0.75, 0, TAU, 28, col, 2.0)
			if lst.is_empty():
				Art.text(self, "NO ENEMY IN REACH" if c.type == "MELEE" else "NO SQUADMATE IN RANGE", Vector2(u.x, u.y + 30), 8, col, HORIZONTAL_ALIGNMENT_CENTER)
			if c.type == "ALLY":
				draw_rect(Rect2(u.x - c.range, u.y - 80, c.range * 2, 100), Color(0.38, 0.82, 0.44, 0.35), false, 1.0)

func draw_recoil(u: Unit, c: Dictionary, ang: float) -> void:
	var kv := b.recoil_vel(u, c, ang)
	if kv == Vector2.ZERO:
		return
	draw_ghost(u, b.sim_body(u, kv.x, kv.y), Color("c9d1da"), "RECOIL")

func draw_brackets(r: Rect2, col: Color) -> void:
	var l := 6.0
	for corner in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		draw_line(corner, corner + Vector2(l * sx, 0), col, 2.0)
		draw_line(corner, corner + Vector2(0, l * sy), col, 2.0)

func draw_hive(u: Unit, pos: Vector2, white: bool) -> void:
	## Hive Pod: a ribbed violet egg sac, its glow quickening as the hatch timer runs down.
	var a := u.alpha
	if u.dead:
		a *= 0.6
	var n: int = u.fl.get("hatch", Data.ETYPES.hive.hatch)
	var beat := 0.5 + 0.5 * sin(b.t / (4.0 if n <= 1 else 10.0))
	var body := Color.WHITE if white else Color("7d3cb0")
	draw_circle(pos + Vector2(0, -12), 15, Color(C_DARK, a))
	draw_circle(pos + Vector2(0, -12), 13, Color(body, a))
	draw_circle(pos + Vector2(-4, -15), 7, Color(Color("b06ae0"), a))
	for k in 3:
		draw_line(pos + Vector2(-10 + k * 10, -2), pos + Vector2(-6 + k * 6, -23), Color(Color("4a1f6e"), a), 2.0)
	if not u.dead:
		draw_circle(pos + Vector2(3, -10), 4 + beat * 2, Color(C_OOZE, 0.5 + 0.4 * beat))
		draw_circle(pos + Vector2(-5, -6), 2 + beat, Color(C_OOZE, 0.4 + 0.4 * beat))
	draw_rect(Rect2(pos.x - 14, pos.y - 2, 28, 3), Color(Color("4a1f6e"), a))

func draw_burrow(u: Unit, pos: Vector2, white: bool) -> void:
	## Skitter tunnel: a dirt mound around a dark hole, glowing eyes inside while waves are left.
	var dirt := Color.WHITE if white else Color("8c6a46")
	draw_rect(Rect2(pos.x - 17, pos.y - 9, 34, 9), C_DARK)
	draw_rect(Rect2(pos.x - 16, pos.y - 8, 32, 8), dirt)
	draw_rect(Rect2(pos.x - 11, pos.y - 13, 22, 5), dirt)
	draw_rect(Rect2(pos.x - 8, pos.y - 10, 16, 8), C_DARK)
	if not u.dead and u.fl.get("wave", 0) < Data.ETYPES.burrow.waves.size():
		for k in 3:
			if (b.t / 20 + k) % 3 != 0:
				draw_rect(Rect2(pos.x - 6 + k * 5, pos.y - 7, 2, 1), C_OOZE)

func draw_wells() -> void:
	## Gravity Warden wells: a slow violet swirl, and the threads from an Overseer to its Thralls.
	for w in b.wells:
		var c := Vector2(w.x, w.y)
		draw_circle(c, w.r, Color(0.48, 0.24, 0.69, 0.07))
		draw_arc(c, w.r, 0, TAU, 48, Color("c47bff", 0.45), 1.5)
		for k in 3:
			var a0: float = b.t / 30.0 + k * TAU / 3
			var rr: float = w.r * (0.35 + 0.2 * k)
			draw_arc(c, rr, a0, a0 + 1.6, 12, Color("c47bff", 0.5 - 0.1 * k), 2.0)
		draw_circle(c, 5, Color("e2b8ff", 0.8))
	for u in b.units:
		if u.dead or not u.fl.has("link"):
			continue
		for o in b.units:
			if o.id == u.fl.link and not o.dead:
				var p0 := Vector2(o.x, o.y - o.h * 0.6)
				var p1 := Vector2(u.x, u.y - u.h + 6)
				var mid := (p0 + p1) / 2 + Vector2(0, 14 + sin(b.t / 10.0 + u.id) * 4)
				var pts := PackedVector2Array()
				for i in 9:
					var t := i / 8.0
					pts.append(p0.lerp(mid, t).lerp(mid.lerp(p1, t), t))
				draw_polyline(pts, Color("ff6ad5", 0.7), 1.0)

func draw_acids() -> void:
	for a in b.acids:
		var w: float = a.r * 2
		for k in 3:
			var c := Color(C_OOZE, 0.25 + 0.1 * k)
			draw_rect(Rect2(a.x - w / 2 + k * 6, a.y - 3 + k, w - k * 12, 3), c)
		if b.t % 20 < 10:
			draw_rect(Rect2(a.x - 4 + (b.t % 40) / 4.0, a.y - 6, 2, 2), C_OOZE)

func draw_mound(u: Unit, pos: Vector2) -> void:
	## A buried Burrower: a heaving ridge of dirt with a glint of violet through the cracks.
	var heave := sin(b.t / 9.0 + u.id) * 1.5
	draw_rect(Rect2(pos.x - 17, pos.y - 7 - heave, 34, 8 + heave), C_DARK)
	draw_rect(Rect2(pos.x - 16, pos.y - 6 - heave, 32, 6 + heave), Color("8c6a46"))
	draw_rect(Rect2(pos.x - 9, pos.y - 10 - heave, 18, 4), Color("8c6a46"))
	draw_rect(Rect2(pos.x - 3, pos.y - 6 - heave, 2, 3), Color("7d3cb0"))
	draw_rect(Rect2(pos.x + 4, pos.y - 4 - heave, 2, 2), Color("7d3cb0"))

func draw_pod(pos: Vector2, white: bool) -> void:
	## The Squid Trooper's saucer: a steel dish under its tentacles, lights chasing round the rim.
	var c := Color.WHITE if white else Color("8e939a")
	draw_rect(Rect2(pos.x - 13, pos.y - 2, 26, 5), C_DARK)
	draw_rect(Rect2(pos.x - 12, pos.y - 1, 24, 3), c)
	draw_rect(Rect2(pos.x - 8, pos.y + 2, 16, 3), C_DARK)
	draw_rect(Rect2(pos.x - 7, pos.y + 2, 14, 2), Color("5c6068") if not white else c)
	for k in 4:
		var on: bool = (b.t / 6 + k) % 4 == 0
		draw_rect(Rect2(pos.x - 9 + k * 6, pos.y, 2, 1), C_OOZE if on else Color("3c3e46"))
	var a := 0.25 + 0.15 * sin(b.t / 5.0)
	draw_rect(Rect2(pos.x - 4, pos.y + 5, 8, 6), Color(C_OOZE, a))

func draw_reticle(p: Vector2, col: Color) -> void:
	var s := 7.0 + sin(b.t / 6.0)
	draw_arc(p, s, 0, TAU, 16, col, 1.0)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(p + d * (s - 3), p + d * (s + 4), col, 1.0)

# ---------------------------------------------------------------- text
func draw_texts() -> void:
	for tx in b.texts:
		var x: float = (tx.u.x if tx.u != null else tx.x)
		var y: float = tx.y - tx.t * 0.6
		var al: float = (70 - tx.t) / 20.0 if tx.t > 50 else 1.0
		var sz := 16 if tx.big else 8
		if tx.big and tx.t < 6:
			y -= (6 - tx.t)
		Art.text(self, tx.text, Vector2(x, y), sz, tx.c, HORIZONTAL_ALIGNMENT_CENTER, 2, false, al)

func draw_barks() -> void:
	for bk in b.barks:
		var u: Unit = bk.u
		if u.dead:
			continue
		var w := Art.text_width(bk.text, 16, true) + 14
		var x := u.x
		var y := u.y - u.h - 52
		var bx := clampf(x - w / 2, b.cam_x + 4, b.cam_x + Battle.W - w - 4)
		draw_rect(Rect2(bx - 1, y - 19, w + 2, 24), C_DARK)
		draw_rect(Rect2(bx, y - 18, w, 22), Color("efe7d2"))
		draw_colored_polygon(PackedVector2Array([Vector2(x - 4, y + 4), Vector2(x + 4, y + 4), Vector2(x, y + 10)]), Color("efe7d2"))
		Art.text(self, bk.text, Vector2(bx + 7, y - 2), 16, C_DARK, HORIZONTAL_ALIGNMENT_LEFT, 0, true)

func draw_hover() -> void:
	var h = b.unit_at_p(b.mouse)
	if h == null or h.kind == "pow" or (b.card_idx >= 0 and b.state == "player"):
		return
	var lines: Array = []
	if h.team == "enemy":
		var E: Dictionary = Data.ETYPES[h.type]
		lines = [E.name.to_upper(), "HP %d/%d" % [h.hp, h.max_hp], E.note]
		if h.weight == "hover":
			lines.append("POD %d: soaks damage first. Break it and it drops." % h.pod)
		elif h.weight == "light":
			lines.append("LIGHT: knockback sends it twice as far.")
		if h.type == "boss":
			lines.append("ARMOR PLATE %d" % h.plate if h.plate > 0 else "ARMOR CRACKED: TAKES +30%")
		if h.elite != "":
			lines.append("ELITE %s: %s Drops an item." % [Data.ELITES[h.elite].name, Data.ELITES[h.elite].text])
		for k in h.st:
			lines.append("%s %d: %s" % [Data.STATUS[k].name, h.st[k], Data.STATUS[k].text])
	elif h.kind == "fuel":
		lines = ["FUEL TANK", ("Leaking: blows after %d more enemy phase(s)." % h.leak) if h.leak != null else "Shoot it: it leaks and blows in 2 turns.", "Blast it: it goes up now. Blast 84."]
	elif h.kind == "charge":
		lines = ["SAPPER CHARGE", "Blows when the Jackals move next.", "Shoot it to defuse. Blast 48."]
	elif h.kind == "crate":
		lines = ["SUPPLY CRATE", "Shoot it or blast it open. The loot pops out:", "careful, it can roll into a pit."]
	elif h.kind == "wreck":
		lines = ["WRECK" + (" (STRIPPED)" if h.stripped else ""), "Walk over it to strip it: +%d Salvage for HQ." % Data.WRECK_SALVAGE]
	elif h.kind == "strongbox":
		lines = ["JACKAL STRONGBOX", "Pry it open with a MELEE card: quiet.", "Blast it: free, but ALERT +1 and it may damage the loot."]
	elif h.kind == "loot":
		var L: Dictionary = h.loot
		match L.type:
			"item": lines = ["%s %s" % [Data.tier_name(L.item.tier), Data.item_name(L.item).to_upper()], "Walk over it to pick it up."]
			"letter": lines = ["%s: %s" % [L.key, Data.CARDS[Data.LETTERS[L.key]].name.to_upper()], "3 free shots for whoever grabs it."]
			"scrip": lines = ["%d SCRIP" % L.n]
			_: lines = ["TROPHY: " + L.name]
		lines.append("Anything left behind goes to the stash.")
	elif h.kind == "pad":
		var B: Dictionary = Data.BONUSES[b.pad_bonus(h)]
		lines = ["BONUS PAD: " + B.name, "READY: whoever stands on it takes it." if h.loot.ready else "Ready in %d round%s." % [h.loot.t, "" if h.loot.t == 1 else "s"], B.text, "Jackals race for it too."]
	elif h.kind == "mine":
		lines = ["JACKAL MINE", "Your soldiers set it off by stepping on it.", "Jackals only trip it when they land on it: knock them onto it.", "Shoot or blast it to clear it. Blast 38."]
	elif h.is_prop():
		lines = ["FUEL BARREL", "Explodes when hit. Blast 44."]
	else:
		lines = ["%s  %s  LV%d" % [h.def.name, h.def.cls.to_upper(), h.s.lvl], "HP %d/%d   ADRENALINE %d" % [h.hp, h.max_hp, h.adr], "ENERGY %d   MOVE %dpx" % [h.energy, int(h.move_left)]]
	var w := 0.0
	for l in lines:
		w = maxf(w, Art.text_width(l, 16, true))
	w += 16
	var x := clampf(h.x - w / 2, b.cam_x + 4, b.cam_x + Battle.W - w - 4)
	var y := maxf(46, h.y - h.h - 34 - lines.size() * 16 - 10)
	var hgt := lines.size() * 16 + 8
	draw_rect(Rect2(x - 1, y - 1, w + 2, hgt + 2), C_DARK)
	draw_rect(Rect2(x, y, w, hgt), Color(0.1, 0.11, 0.13, 0.94))
	draw_rect(Rect2(x, y, w, 2), Color("ff4d3d") if h.team == "enemy" else Color("ffb23e"))
	for i in lines.size():
		Art.text(self, lines[i], Vector2(x + 8, y + 18 + i * 16), 16, Color.WHITE if i == 0 else Color("d7cfbb"), HORIZONTAL_ALIGNMENT_LEFT, 0, true)

class_name BattleBosses
extends RefCounted
## Shared boss rules and spectacle (epic bosses page, 2026-11-24):
##   R1 wind-ups: a boss's signature attack starts on one turn and lands at the start of its next.
##      Nothing is marked on the HUD: the boss itself shows it (a glowing gun, a red smoke flare).
##   R2 a slow-motion beat when a wind-up lands and when a boss dies.
##   X1 the entrance: black bars, the boss arrives, its name card slams in.
##   X2 the second phase at half health.
##   X4 parts you can shoot off a boss (Data.ETYPES.bosspart), each taking an attack away.
##   X5 the death: chain explosions in slow motion, and the wreck stays as steel terrain.
## Functions only: every piece of mission state lives on the Battle, reached through `bt`.

var bt: Battle

func _init(battle: Battle) -> void:
	bt = battle

# ---------------------------------------------------------------- names
func boss_name(u: Unit) -> String:
	if u.type == "boss":
		if u.fl.get("vharr", false):
			return "VHARR BOAR"
		if u.fl.get("rookie", false):
			return "ROOKIE BOAR"
		return Data.BOAR_KITS.get(bt.mission.get("boar_kit", ""), Data.BOAR_KITS.standard).name
	return Data.ETYPES[u.type].name.to_upper()

func boss_sub(u: Unit) -> String:
	if u.type == "boss":
		if u.fl.get("vharr", false):
			return "THE FLAGSHIP, REFIT WITH VHARR TECH"
		return Data.BOAR_KITS.get(bt.mission.get("boar_kit", ""), Data.BOAR_KITS.standard).get("sub", "IT HEARD YOU COMING")
	return Data.ETYPES[u.type].get("sub", "")

func bar_note(u: Unit) -> String:
	## The short line after the boss's name on its health bar.
	var parts := parts_of(u)
	if parts.size():
		return "%d PART%s LEFT TO SHOOT OFF" % [parts.size(), "S" if parts.size() > 1 else ""]
	return "ENRAGED" if phase(u) == 2 else ""

func boss_color(u: Unit) -> Color:
	return Color("c47bff") if bt.faction(u) == "vharr" or u.fl.get("vharr", false) else Color("ff4d3d")

# ---------------------------------------------------------------- X1 the entrance
func entrance(u: Unit) -> void:
	## Called when the boss first becomes active. Plays on its own; settled() waits for it, so the
	## turn that walked into the arena doesn't go on until it's done.
	if not bt.cine.is_empty() or u.fl.get("entered", false):
		return
	u.fl["entered"] = true
	bt.cine = {"t": 0, "dur": Data.BOSS_CINE, "name": boss_name(u), "sub": boss_sub(u), "c": boss_color(u), "u": u, "skip": false}
	_entrance_run(u)

func _entrance_run(u: Unit) -> void:
	var was_busy := bt.busy
	bt.busy = true
	Sfx.play("alarm")
	Music.play("boss")
	# the boss arrives: a flyer drops in from above, anything else rolls in from the right
	var flyer: bool = u.weight == "hover"
	var ent: Array = Data.ETYPES[u.type].get("enter", [0, -260] if flyer else [220, 0])
	var off := Vector2(ent[0], ent[1])
	u.fl["enter_off"] = off
	var n: int = 70
	for i in n:
		if bt.cine.get("skip", false):
			break
		var k := 1.0 - float(i + 1) / n
		u.fl["enter_off"] = off * (k * k)
		if i % 6 == 0 and not flyer:
			bt.dust(u.x + u.fl.enter_off.x - u.w / 2.0, u.y, Color("8a7a6a"), 2)
		if i % 10 == 0:
			bt.shake += 2
		await bt.tick
	u.fl.erase("enter_off")
	bt.shake += 8
	Sfx.play("bigboom")
	if not flyer:
		bt.dust(u.x, u.y, Color("8a7a6a"), 12)
	while bt.cine.t < bt.cine.dur and not bt.cine.get("skip", false):
		await bt.tick
	bt.cine = {}
	bt.busy = was_busy
	bt.log_msg(Data.ETYPES[u.type].note if u.type != "boss" else "The %s rolls in. Something heavy is hanging over it..." % boss_name(u))
	bt.ui_dirty = true

func cine_tick() -> void:
	if not bt.cine.is_empty():
		bt.cine.t += 1

func skip_cine() -> void:
	if not bt.cine.is_empty() and bt.cine.t > 20:
		bt.cine["skip"] = true

# ---------------------------------------------------------------- R2 slow motion
func slowmo(focus: Vector2, frames := 40, k := 0.25) -> void:
	## Time drops to k for a moment (counted in real frames) and the camera leans in.
	if preload("res://scripts/settings.gd").shake_mul() <= 0.0:
		return
	bt.slow = {"t": frames, "k": k, "focus": focus}

# ---------------------------------------------------------------- R1 wind-ups
func winding(u: Unit) -> bool:
	return u.fl.has("windup")

func start_windup(u: Unit, kind: String, data := {}) -> void:
	## The boss starts its signature attack. It still moves and shoots this turn as usual.
	var w := data.duplicate()
	w["kind"] = kind
	w["t0"] = bt.t
	u.fl["windup"] = w
	Sfx.play("power", -2)
	bt.shake += 2
	bt.float_text(u, Data.WINDUPS[kind].shout, boss_color(u), true)

func cancel_windup(u: Unit, why := "") -> void:
	if not u.fl.has("windup"):
		return
	u.fl.erase("windup")
	if why != "":
		bt.float_text(u, why, Color("ffd23a"), true)

func resolve_windup(u: Unit) -> void:
	## Start of the boss's turn: a wind-up from last turn lands first, before it moves.
	if not u.fl.has("windup") or u.dead:
		return
	var w: Dictionary = u.fl.windup
	u.fl.erase("windup")
	match w.kind:
		"bigshell":
			await fire_bigshell(u, w)
		"bellyray":
			await fire_bellyray(u, w)
		_:
			await bt.boss_ai.fire_windup(u, w)
	await bt.until(bt.settled)

func windup_reminder() -> void:
	## Start of the player's turn: each boss that's winding up hums again so you look at it.
	for u in bt.units:
		if bt.is_boss(u) and not u.dead and winding(u):
			Sfx.play("power", -6)
			bt.float_text(u, Data.WINDUPS[u.fl.windup.kind].shout, boss_color(u))

func boss_turns(u: Unit) -> int:
	## How many of its turns this boss has started (counted by tick_turn).
	return int(u.fl.get("bturns", 0))

func tick_turn(u: Unit) -> int:
	var n := boss_turns(u) + 1
	u.fl["bturns"] = n
	return n

func windup_due(u: Unit, every := 3, first := 2) -> bool:
	## Wind up on turn `first`, then every `every` turns after (2, 5, 8...).
	var n := boss_turns(u)
	return n >= first and (n - first) % every == 0 and not winding(u)

# Boar: a heavy shell. It fires a red smoke flare at a soldier this turn, the main gun glows and
# rises, and next turn the shell lands on the flare. Blow its ammo rack off and it can't.
func boar_windup(bo: Unit) -> void:
	if bo.fl.get("rack_gone", false) or not windup_due(bo) or bt.in_lesson() or bt.tutorial():
		return
	var sq := bt.squad_alive()
	if sq.is_empty():
		return
	var tg: Unit = bt.pick(sq)
	var gy = bt.T.stand_y(tg.x, tg.y - 20)
	var fy: float = gy if gy != null else tg.y
	start_windup(bo, "bigshell", {"x": tg.x, "y": fy})
	bt.boss_flares.append({"x": tg.x, "y": fy, "t": 0, "boss": bo.id})
	var pv := bt.boss_pivot(bo)
	Sfx.play("toss")
	for i in 8:
		bt.part({"x": pv.x - 40 + (tg.x - pv.x) * i / 8.0, "y": pv.y - 10 - sin(PI * i / 8.0) * 80 + (fy - pv.y) * i / 8.0, "vx": 0.0, "vy": -0.3, "life": 30, "max": 30, "c": Color("ff4d3d"), "s": 2.0, "g": 0.0})
	await bt.wait(20)

func fire_bigshell(bo: Unit, w: Dictionary) -> void:
	var pv := bt.boss_pivot(bo)
	var sol = bt.phys.solve_arc(pv.x - 40, pv.y - 10, w.x, w.y - 4, 1, 14)
	bt.boss_flares = bt.boss_flares.filter(func(f): return f.get("boss", -1) != bo.id)
	if sol == null:
		return
	bo.aim_a = clampf(atan2(-sol.vy, -sol.vx), -0.4, 1.2)
	await bt.wait(16)
	var m := bt.muzzle(bo)
	Sfx.play("bigboom")
	bt.shake += 10
	for j in 8:
		bt.puff(m.x, m.y, 2.6)
	slowmo(Vector2(w.x, w.y), 50)
	bt.projs.append(bt.phys.mk_proj({"kind": "shell", "x": m.x, "y": m.y, "vx": sol.vx, "vy": sol.vy, "wind": 0.0, "r": Data.BIGSHELL_R, "dmg": Data.BIGSHELL_DMG, "owner": bo, "trail": true, "big": true}))
	await bt.until(bt.settled)
	await bt.wait(10)

# Hive Ship: the belly ray. Its belly port swells and glows over a soldier; next turn a column of
# light burns straight down there, through everything, before the ship moves.
func ship_windup(sh: Unit) -> void:
	if not windup_due(sh) or bt.in_lesson():
		return
	start_windup(sh, "bellyray", {"x": sh.x})

func fire_bellyray(sh: Unit, w: Dictionary) -> void:
	var x: float = w.x
	Sfx.play("laser")
	bt.shake += 8
	slowmo(Vector2(x, 300), 40)
	var hit := {}
	for f in 24:
		for j in 5:
			bt.tracers.append({"x1": x - 8 + j * 4, "y1": sh.y, "x2": x - 8 + j * 4, "y2": float(bt.WATER_Y), "c": Color("9df25c") if j == 2 else Color("c47bff"), "t": 4})
		if f % 3 == 0:
			for y in range(int(sh.y) + 20, bt.WATER_Y, 14):
				if bt.T.solid(x, y) and bt.T.mat(x, y) != bt.T.STEEL:
					bt.T.carve(x, y, 9, null)
		for u in bt.units:
			if u.dead or u.gone or u.team == "enemy" or u.is_pickup() or hit.has(u.id):
				continue
			if absf(u.x - x) < 14 + u.w / 2.0 and u.y > sh.y:
				hit[u.id] = true
				bt.damage(u, Data.BELLYRAY_DMG, sh, {})
				bt.add_status(u, "burn", 2, sh)
		await bt.wait(1)
	await bt.wait(12)

# ---------------------------------------------------------------- X2 the second phase
func phase(u: Unit) -> int:
	return 2 if u.fl.get("phase2", false) else 1

func check_phase(u: Unit) -> void:
	## At half health a boss changes for the second half of the fight.
	if u.dead or u.fl.get("phase2", false) or u.hp > u.max_hp / 2:
		return
	u.fl["phase2"] = true
	bt.banner("%s ENRAGED!" % boss_name(u), boss_color(u), Data.ETYPES[u.type].get("phase2", "IT'S NOT DONE YET"))
	Sfx.play("roar")
	bt.shake += 10
	slowmo(Vector2(u.x, u.y - u.h / 2.0), 36, 0.3)
	for i in 14:
		bt.debris(u.x + randf_range(-u.w / 2.0, u.w / 2.0), u.y - randf_range(10, u.h), 9)
	for i in 4:
		bt.booms.append({"t": 4 + i * 8, "x": u.x + randf_range(-u.w / 3.0, u.w / 3.0), "y": u.y - randf_range(10, u.h), "r": 18.0, "dmg": 0, "owner": null, "show": true})
	u.pose = "recoil"; u.pose_t = 40
	bt.boss_ai.on_phase2(u)

# ---------------------------------------------------------------- X4 parts
func add_part(bo: Unit, key: String, dx: float, dy: float) -> Unit:
	## A breakable piece pinned to the boss at (dx, dy) from its feet. Data.BOSS_PARTS has its stats.
	var P: Dictionary = Data.BOSS_PARTS[key]
	var p := bt.mk_enemy("bosspart", bo.x + dx, bo.y + dy)
	p.w = P.w; p.h = P.h
	p.hp = int(round(P.hp * bt.mission.get("hp_mul", 1.0))); p.max_hp = p.hp
	p.fl["boss"] = bo
	p.fl["part"] = key
	p.fl["dx"] = dx
	p.fl["dy"] = dy
	p.immovable = true
	p.active = bo.active
	bt.units.append(p)
	return p

func parts_of(bo: Unit, key := "") -> Array:
	return bt.units.filter(func(o): return o.type == "bosspart" and not o.dead and o.fl.get("boss") == bo and (key == "" or o.fl.part == key))

func pin_part(p: Unit) -> void:
	var bo = p.fl.get("boss")
	if bo != null and not bo.gone:
		var off: Vector2 = bo.fl.get("enter_off", Vector2.ZERO)
		# offsets are for a boss facing left; a boss that turns round takes its parts with it
		var dx: float = p.fl.dx * (-1.0 if bo.face == 1 else 1.0)
		var tilt: float = bo.fl.get("tilt", 0.0)
		var dy: float = p.fl.dy + dx * tilt
		p.x = bo.x + dx + off.x
		p.y = bo.y + dy + off.y
		p.active = bo.active
	p.air = false
	p.vx = 0
	p.vy = 0

func part_down(p: Unit, src) -> void:
	## A part is shot off: it blows, falls and crushes what's under it, and the boss loses something.
	var bo = p.fl.get("boss")
	var P: Dictionary = Data.BOSS_PARTS[p.fl.part]
	p.gone = true
	Sfx.play("bigboom")
	bt.shake += 6
	if not p.fl.get("silent", false):
		bt.banner(P.down, Color("ffd23a"), P.lose)
	bt.booms.append({"t": 2, "x": p.x, "y": p.y - p.h / 2.0, "r": 30.0, "dmg": 0, "owner": null, "show": true})
	for i in 8:
		bt.debris(p.x + randf_range(-8, 8), p.y - randf_range(2, p.h), 9)
	if P.get("fall", true):
		var cells: Array = []
		var cx0 := int(floor((p.x - p.w / 2.0) / bt.CELL))
		var cy0 := int(floor((p.y - p.h) / bt.CELL))
		for ry in maxi(1, int(p.h / bt.CELL)):
			for rx in maxi(1, int(p.w / bt.CELL)):
				if not bt.T.solid((cx0 + rx) * bt.CELL + 2, (cy0 + ry) * bt.CELL + 2):
					cells.append([cx0 + rx, cy0 + ry, bt.T.STEEL, 0])
		var c = bt.T.chunk_from_cells(cells, src if src is Unit and src.team == "squad" else null)
		if c != null and bo != null:
			c.hit[bo.id] = true
	if bo != null and not bo.dead:
		if P.get("boss_dmg", 0) > 0:
			bt.damage(bo, P.boss_dmg, src, {"blast": true})
		match p.fl.part:
			"coil":
				bt.boss_ai.coil_down(bo)
			"sac":
				bt.boss_ai.sac_down(bo)
			"winch":
				bt.boss_ai.winch_down(bo)
			"rack":
				bo.fl["rack_gone"] = true
				cancel_windup(bo, "NO SHELLS!")
				bt.boss_flares = bt.boss_flares.filter(func(f): return f.get("boss", -1) != bo.id)
		if parts_of(bo).is_empty() and not bo.dead:
			check_phase_force(bo)

func check_phase_force(bo: Unit) -> void:
	## Breaking every part forces the second phase early.
	if not bo.fl.get("phase2", false) and Data.ETYPES[bo.type].get("parts_force", true):
		bo.hp = mini(bo.hp, bo.max_hp / 2)
		check_phase(bo)

# ---------------------------------------------------------------- X5 the death
func death(u: Unit) -> void:
	## Slow motion, explosions walking across the body, pieces flying off, then the wreck stays
	## on the field as steel you can stand on or hide behind.
	slowmo(Vector2(u.x, u.y - u.h / 2.0), 70, 0.22)
	Sfx.play("bigboom")
	bt.shake += 14
	var n := 9
	for i in n:
		var fx: float = u.x - u.w / 2.0 + u.w * float(i) / (n - 1)
		bt.booms.append({"t": 6 + i * 9, "x": fx + randf_range(-8, 8), "y": u.y - randf_range(8, u.h), "r": 30.0, "dmg": 0, "owner": null, "show": true})
	for i in 16:
		bt.debris(u.x + randf_range(-u.w / 2.0, u.w / 2.0), u.y - randf_range(6, u.h), 9)
	for p in parts_of(u):
		bt.kill(p, null)
	u.fl["wreck_t"] = 6 + n * 9 + 10
	_wreck_later(u)

func _wreck_later(u: Unit) -> void:
	await bt.wait(int(u.fl.wreck_t))
	make_wreck(u)

func make_wreck(u: Unit) -> void:
	## The body becomes a steel chunk shaped like it (a low hull for the Boar). Flyers fall.
	if u.fl.get("wrecked", false):
		return
	u.fl["wrecked"] = true
	var shape: Array = Data.ETYPES[u.type].get("wreck", [[-0.5, 0.5, 0.0, 0.55]])
	var cells: Array = []
	var seen := {}
	for r in shape:
		var x0: float = u.x + u.w * r[0]
		var x1: float = u.x + u.w * r[1]
		var y0: float = u.y - u.h * r[3]
		var y1: float = minf(u.y - u.h * r[2], u.y - 4)
		var cx := int(floor(x0 / bt.CELL))
		while cx * bt.CELL < x1:
			var cy := int(floor(y0 / bt.CELL))
			while cy * bt.CELL < y1:
				var key := cx * 10000 + cy
				var px := cx * bt.CELL + 2.0
				var py := cy * bt.CELL + 2.0
				if not seen.has(key) and py < bt.WATER_Y and not bt.T.solid(px, py):
					seen[key] = true
					cells.append([cx, cy, bt.T.STEEL, 1])
				cy += 1
			cx += 1
	if u.weight == "hover":
		u.gone = true
		# a flyer's wreck drops out of the sky and lands where it lands
		var c = bt.T.chunk_from_cells(cells, null)
		if c != null:
			for s in bt.units:
				if s.team != "enemy" and not s.dead:
					c.hit[s.id] = true  # the wreck lands hard, but not on the squad that downed it
	else:
		# a ground boss's hull stays where it died: steel under the burnt-out body
		for cl in cells:
			bt.T.set_cell(cl[0], cl[1], cl[2])
			bt.T.data[(cl[1] * bt.T.cols + cl[0]) * 2 + 1] = 1
		for s in bt.units:
			if s.dead or s.gone or s.sunk:
				continue
			var k := 0
			while bt.T.solid(s.x, s.y - 2) and k < 30:
				s.y -= bt.CELL
				k += 1
	bt.dust(u.x, u.y, Color("6a6a6a"), 14)

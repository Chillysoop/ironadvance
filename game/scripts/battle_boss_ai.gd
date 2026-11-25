class_name BattleBossAI
extends RefCounted
## The new bosses' turns (epic bosses page, B1 onward). The shared rules (wind-ups, entrances,
## phases, parts, wrecks) live in battle_bosses.gd; this file is what each boss does with them.
## Every boss still moves and attacks every turn; its signature attack is wound up one turn ahead.
## Functions only: every piece of mission state lives on the Battle, reached through `bt`.

var bt: Battle

func _init(battle: Battle) -> void:
	bt = battle

func handles(u: Unit) -> bool:
	return u.type in ["stormcrow", "railgun"]

func setup(u: Unit) -> void:
	## Called once when the boss is placed in the level: its parts and starting state.
	var B = bt.bosses
	match u.type:
		"stormcrow":
			# two engines under the near wing, two smaller ones further out along it
			for d in [[-22.0, -24.0], [0.0, -22.0], [24.0, -16.0], [44.0, -10.0]]:
				B.add_part(u, "engine", d[0], d[1])
			u.face = -1
		"railgun":
			for dx in [30.0, 41.0, 52.0]:
				B.add_part(u, "coil", dx, -56.0)
			u.aim_a = 0.12

func act(u: Unit) -> void:
	bt.bosses.tick_turn(u)
	var fired: bool = bt.bosses.winding(u)
	await bt.bosses.resolve_windup(u)
	if u.dead or bt.squad_alive().is_empty():
		return
	match u.type:
		"stormcrow":
			await stormcrow_turn(u, fired)
		"railgun":
			await railgun_turn(u, fired)

func on_phase2(u: Unit) -> void:
	match u.type:
		"stormcrow":
			crash(u)

func fire_windup(u: Unit, w: Dictionary) -> void:
	match w.kind:
		"bombrun":
			await bomb_run(u, w)
		"rail":
			await fire_rail(u, w)

# ---------------------------------------------------------------- B1 STORMCROW
func arena(u: Unit) -> Array:
	## The stretch of sky it works over: the screen, less a margin, so you can always see it.
	return [bt.cam_x + 110.0, bt.cam_x + bt.W - 110.0]

func engines(u: Unit) -> int:
	return bt.bosses.parts_of(u, "engine").size()

func strip_w(u: Unit) -> float:
	return Data.BOMB_STRIP[0] + Data.BOMB_STRIP[1] * engines(u)

func stormcrow_turn(u: Unit, passed: bool) -> void:
	if u.fl.get("crashed", false):
		await wreck_turn(u)
		return
	if not passed:
		# the bank turn: it swings round at the edge, and its searchlight picks next turn's strip
		var ar := arena(u)
		var edge: float = ar[1] if u.x > (ar[0] + ar[1]) / 2.0 else ar[0]
		if absf(edge - u.x) > 20:
			await fly_to(u, edge, 6.0)
		u.face = -1 if u.x > (ar[0] + ar[1]) / 2.0 else 1
		var sq := bt.squad_alive()
		if sq.size():
			var tg: Unit = bt.pick(sq)
			var w := strip_w(u)
			bt.bosses.start_windup(u, "bombrun", {"x0": tg.x - w / 2.0, "x1": tg.x + w / 2.0, "cx": tg.x})
			Sfx.play("engine", -2)
	await tail_gun(u)

func tail_gun(u: Unit) -> void:
	var best = bt.foe_ai.best_shot(u, bt.squad_alive(), Data.ETYPES.stormcrow.range)
	if best != null:
		var keep := u.face
		await bt.foe_ai.enemy_shoot(u, best.t, Data.ETYPES.stormcrow)
		u.face = keep  # the gunner swings round; the plane doesn't

func fly_to(u: Unit, tx: float, spd: float, bombs := {}) -> void:
	## Straight and level at its altitude; drops bombs over [x0, x1] on the way if asked.
	var dir := signf(tx - u.x)
	if dir == 0:
		return
	u.face = int(dir)
	var next_bomb: float = -INF
	while (tx - u.x) * dir > 0 and not u.dead:
		u.x += dir * minf(spd, absf(tx - u.x))
		u.tread += 1
		if bombs.size() and u.x >= bombs.x0 - 10 and u.x <= bombs.x1 + 10 and absf(u.x - next_bomb) >= 30:
			next_bomb = u.x
			drop_bomb(u)
		if int(u.tread) % 9 == 0:
			bt.shake += 0.8
		await bt.tick

func drop_bomb(u: Unit) -> void:
	Sfx.play("toss", -6)
	bt.projs.append(bt.phys.mk_proj({"kind": "bomb", "x": u.x, "y": u.y - 6, "vx": u.face * 1.4, "vy": 1.5, "r": 40.0, "dmg": Data.BOMB_DMG, "owner": u}))

func bomb_run(u: Unit, w: Dictionary) -> void:
	## Last turn's lit strip: it comes round and flies the whole arena, bombs falling over the strip.
	var ar := arena(u)
	var go_right: bool = u.x < (ar[0] + ar[1]) / 2.0
	var tx: float = ar[1] if go_right else ar[0]
	bt.float_text(u, "BOMBS AWAY!", Color("ff4d3d"), true)
	Sfx.play("alarm", -4)
	bt.bosses.slowmo(Vector2(w.cx, bt.WATER_Y - 160.0), 30, 0.4)
	# the strip shrinks if engines were shot off since it was picked
	var half: float = strip_w(u) / 2.0
	var x0: float = maxf(w.x0, w.cx - half)
	var x1: float = minf(w.x1, w.cx + half)
	await fly_to(u, tx, 9.0, {"x0": x0, "x1": x1})
	await bt.until(bt.settled)

func crash(u: Unit) -> void:
	## Phase 2: it falls out of the sky in a long dive and keeps fighting from the wreck.
	if u.fl.get("crashed", false):
		return
	u.fl["crashed"] = true
	bt.bosses.cancel_windup(u)
	for p in bt.bosses.parts_of(u, "engine"):
		p.fl["silent"] = true
		bt.kill(p, null)
	_crash_run(u)

func _crash_run(u: Unit) -> void:
	var was := bt.busy
	bt.busy = true
	u.fl["falling"] = true
	Sfx.play("alarm")
	var dir := float(u.face)
	var ar := arena(u)
	var tx: float = clampf(u.x + dir * 160.0, ar[0], ar[1])
	var gy = bt.T.stand_y(tx, u.y)
	var ty: float = gy if gy != null else bt.WATER_Y - 4.0
	var x0 := u.x
	var y0 := u.y
	var n := 60
	for i in n:
		var k := float(i + 1) / n
		u.x = lerpf(x0, tx, k)
		u.y = lerpf(y0, ty, k * k)
		u.fl["tilt"] = 0.35 * k * dir
		if i % 3 == 0:
			bt.part({"x": u.x - dir * 60, "y": u.y - 30, "vx": -dir * 0.5, "vy": -0.5, "life": 50, "max": 50, "c": Color("3a3a3a"), "s": 5.0, "g": -0.01, "smoke": true})
			bt.part({"x": u.x - dir * 30, "y": u.y - 24, "vx": 0.0, "vy": -1.0, "life": 22, "max": 22, "c": Color("ffb23e"), "s": 3.0, "g": -0.02, "fire": true})
		await bt.tick
	u.weight = ""
	u.h = 40
	u.fl["tilt"] = 0.08 * dir
	u.fl.erase("falling")
	bt.shake += 16
	Sfx.play("collapse")
	bt.bosses.slowmo(Vector2(u.x, u.y - 30), 40, 0.25)
	for i in 6:
		bt.booms.append({"t": 2 + i * 6, "x": u.x + randf_range(-80, 80), "y": u.y - randf_range(4, 30), "r": 30.0, "dmg": 0, "owner": null, "show": true})
	# whoever was under it when it hit the ground
	for o in bt.units:
		if o == u or o.dead or o.gone or o.is_pickup() or o.kind == "pow" or o.type == "bosspart":
			continue
		if absf(o.x - u.x) < u.w / 2.0 + 6 and absf(o.y - u.y) < 50:
			bt.damage(o, 14, u, {"melee": true})
			if not o.heavy and not o.dead:
				o.vx = signf(o.x - u.x) * 5.0; o.vy = -4.0; o.air = true; o.walk = null
	bt.dust(u.x, u.y, Color("8a7a6a"), 16)
	await bt.wait(20)
	bt.busy = was

func wreck_turn(u: Unit) -> void:
	## Phase 2: on the ground, burning. The tail gunner fires twice and the fire spreads.
	for k in 2:
		await tail_gun(u)
		if bt.squad_alive().is_empty():
			return
	for o in bt.squad_alive():
		if absf(o.x - u.x) < u.w / 2.0 + 70 and absf(o.y - u.y) < 60:
			bt.add_status(o, "burn", 2, u)
			bt.float_text(o, "BURNING WRECK", Color("ff7a3d"))

# ---------------------------------------------------------------- B2 RAILBREAKER
func pivot(u: Unit) -> Vector2:
	return Vector2(u.x - 10, u.y - 78)

func rail_dir(u: Unit, a: float) -> Vector2:
	## aim_a is how far the barrel dips below level, pointing left.
	return Vector2(-cos(a), sin(a))

func rail_muzzle(u: Unit) -> Vector2:
	return pivot(u) + rail_dir(u, u.aim_a) * 150.0

func coils(u: Unit) -> int:
	return bt.bosses.parts_of(u, "coil").size()

func railgun_turn(u: Unit, fired: bool) -> void:
	# its turret gun every turn
	var best = bt.foe_ai.best_shot(u, bt.squad_alive(), Data.ETYPES.railgun.range)
	if best != null:
		await bt.foe_ai.enemy_shoot(u, best.t, Data.ETYPES.railgun)
	if coils(u) == 0 or bt.squad_alive().is_empty():
		return
	# phase 1: charge, fire, rest. Phase 2 (overclocked): it charges again the turn it fires.
	if fired and bt.bosses.phase(u) == 1:
		u.fl["rest"] = true
		return
	if u.fl.get("rest", false):
		u.fl.erase("rest")
		bt.float_text(u, "VENTING", Color("9fb4c9"))
		return
	await rail_windup(u)

func rail_angle(u: Unit, tg: Unit) -> float:
	var p := pivot(u)
	var t := Vector2(tg.x, tg.y - tg.h / 2.0)
	if t.x >= p.x - 30:
		return INF  # behind or under the barrel
	return atan2(t.y - p.y, p.x - t.x)

func rail_windup(u: Unit) -> void:
	## The barrel swings onto a soldier it can reach, the coils light one by one.
	var opts: Array = []
	for s in bt.squad_alive():
		var a := rail_angle(u, s)
		if a != INF and a <= Data.RAIL_MIN and a >= -0.5:
			opts.append([s, a])
	if opts.is_empty():
		bt.float_text(u, "NO ANGLE", Color("9fb4c9"))
		return
	var pk: Array = bt.pick(opts)
	var a0 := u.aim_a
	for i in 24:
		u.aim_a = lerpf(a0, pk[1], float(i + 1) / 24.0)
		await bt.tick
	bt.bosses.start_windup(u, "rail", {"a": pk[1]})
	for i in 3:
		Sfx.play("power", -8 + i * 2)
		bt.shake += 1.5
		await bt.wait(10)

func fire_rail(u: Unit, w: Dictionary) -> void:
	## Straight through everything on the line: walls, cover, bodies, its own side.
	u.aim_a = w.a
	var d := rail_dir(u, w.a)
	var m := rail_muzzle(u)
	await bt.wait(10)
	Sfx.play("laser")
	Sfx.play("bigboom", -4)
	bt.shake += 14
	bt.bosses.slowmo(m + d * 300.0, 46, 0.25)
	u.pose = "recoil"; u.pose_t = 30
	var hit := {}
	var steps := int(Data.RAIL_LEN / 6.0)
	var end := m
	for k in steps:
		var p := m + d * (k * 6.0)
		if p.x < bt.cam_x - 200 or p.y > bt.WATER_Y + 10 or p.y < -40:
			break
		end = p
		if k % 2 == 0 and bt.T.solid(p.x, p.y):
			bt.T.carve(p.x, p.y, 10, null)
			if k % 6 == 0:
				bt.dust(p.x, p.y, Color("8a7a6a"), 1)
		for o in bt.units:
			if o == u or o.dead or o.gone or o.sunk or o.is_pickup() or o.kind == "pow" or hit.has(o.id) or o.fl.get("boss") == u:
				continue
			if absf(p.x - o.x) < o.w / 2.0 + 6 and p.y > o.y - o.h - 6 and p.y < o.y + 4:
				hit[o.id] = true
				bt.damage(o, Data.RAIL_DMG, u, {})
				if not o.dead and not o.heavy and not o.immovable:
					o.vx = d.x * 6.0; o.vy = -3.0; o.air = true; o.walk = null
	for j in 5:
		var off := (j - 2) * 2.0
		bt.tracers.append({"x1": m.x, "y1": m.y + off, "x2": end.x, "y2": end.y + off, "c": Color("e8f6ff") if j == 2 else Color("6ad0ff"), "t": 16})
	u.fl["rail_scar"] = {"a": m, "b": end, "t": 90}
	await bt.wait(16)

func coil_down(u: Unit) -> void:
	## A coil shot off: mid-charge the shot backfires into the bunker.
	if bt.bosses.winding(u):
		bt.bosses.cancel_windup(u)
		bt.banner("BACKFIRE!", Color("ffd23a"), "THE RAIL BLEW UP IN ITS OWN BUNKER")
		bt.bosses.slowmo(Vector2(u.x, u.y - 60), 30, 0.3)
		bt.booms.append({"t": 4, "x": u.x - 10, "y": u.y - 60, "r": 44.0, "dmg": 0, "owner": null, "show": true})
		bt.damage(u, Data.RAIL_DMG, null, {"blast": true})
	if coils(u) == 0 and not u.dead:
		bt.banner("THE RAIL IS DEAD", Color("ffd23a"), "ONLY ITS TURRET GUN LEFT")

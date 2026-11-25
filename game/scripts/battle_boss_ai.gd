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
	return u.type in ["stormcrow", "railgun", "gravemother", "ironjaw", "serpent"]

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
		"gravemother":
			# three egg sacs hanging under her belly
			for d in [[22.0, -82.0], [50.0, -84.0], [40.0, -54.0]]:
				B.add_part(u, "sac", d[0], d[1])
			u.face = -1
		"serpent":
			u.face = -1
			u.fl["cruise_y"] = u.y
			u.fl["scripted"] = true  # B5: it swims where its turn says; no hover physics
			u.fl["trail"] = []
			for i in Data.SERPENT_SEGS + 2:
				u.fl.trail.append(Vector2(u.x + i * Data.SEG_GAP, u.y + sin(i * 0.7) * 14))
			for i in Data.SERPENT_SEGS:
				var p = B.add_part(u, "seg", 0.0, 0.0)
				p.fl["i"] = i
			pin_segs(u)
		"ironjaw":
			u.face = -1
			B.add_part(u, "winch", 30.0, -96.0)
			B.add_part(u, "magnet", -34.0, -64.0)

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
		"gravemother":
			await gravemother_turn(u, fired)
		"ironjaw":
			await ironjaw_turn(u, fired)
		"serpent":
			await serpent_turn(u, fired)

func on_phase2(u: Unit) -> void:
	match u.type:
		"stormcrow":
			crash(u)
		"serpent":
			serpent_split(u)

func fire_windup(u: Unit, w: Dictionary) -> void:
	match w.kind:
		"bombrun":
			await bomb_run(u, w)
		"rail":
			await fire_rail(u, w)
		"brood":
			await brood_hatch(u, w)
		"swing":
			await ball_swing(u, w)
		"steam":
			await bt.vharr_ai.engine_ram(u)
		"rev":
			await drill_bore(u, w)
		"erupt":
			await eruption(u, w)
		"dive":
			await serpent_dive(u, w)

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

# ---------------------------------------------------------------- B3 GRAVEMOTHER
func sacs(u: Unit) -> int:
	return bt.bosses.parts_of(u, "sac").size()

func stalk(u: Unit, reach: float, keep: float) -> void:
	## A slow walk toward the nearest soldier on her long legs, stopping `keep` short of them.
	var tg = bt.nearest_squad(u)
	if tg == null:
		return
	var dir := signf(tg.x - u.x)
	if dir == 0:
		return
	u.face = int(dir)
	var go: float = clampf(absf(tg.x - u.x) - keep, 0.0, reach)
	var pts: Array = []
	var x := u.x
	var y := u.y
	var n := int(go / 2.0)
	for i in n:
		var nx := x + dir * 2.0
		if nx < bt.cam_x + 80 or nx > bt.cam_x + bt.W - 60:
			break
		var ny = bt.T.stand_y(nx, y - 40)
		if ny == null or absf(ny - y) > 30:
			break
		x = nx; y = ny
		pts.append([x, y, false])
	if pts.size():
		await bt.phys.walk_along(u, pts)
		# the legs come down on whoever is underfoot
		for o in bt.squad_alive():
			if absf(o.x - u.x) < u.w / 2.0 - 6 and absf(o.y - u.y) < 30:
				bt.damage(o, Data.STOMP_DMG, u, {"melee": true})
				if not o.dead:
					bt.spec_kits.fling(o, signf(o.x - u.x + 0.01), 4.0, u)
				bt.float_text(o, "STOMPED", Color("c47bff"))
		bt.shake += 3

func spit(u: Unit) -> void:
	## Acid from the head: a hit and a pool that burns for two turns.
	var tg = bt.nearest_squad(u)
	if tg == null or absf(tg.x - u.x) > 520:
		return
	u.face = 1 if tg.x >= u.x else -1
	u.pose = "throw"; u.pose_t = 18
	Sfx.play("splash")
	var h := Vector2(u.x + u.face * 70, u.y - 76)  # her mandibles
	bt.tracers.append({"x1": h.x, "y1": h.y, "x2": tg.x, "y2": tg.y - 10, "c": Color("9df25c"), "t": 16})
	await bt.wait(10)
	bt.acids.append({"x": tg.x, "y": tg.y, "r": 36.0, "turns": 2})
	bt.damage(tg, Data.SPIT_DMG, u, {})
	bt.float_text(tg, "ACID!", Color("9df25c"), true)
	await bt.wait(10)

func gravemother_turn(u: Unit, hatched: bool) -> void:
	await stalk(u, 70.0 if bt.bosses.phase(u) == 1 else 140.0, 50.0)
	if u.dead or bt.squad_alive().is_empty():
		return
	await spit(u)
	if u.dead or bt.squad_alive().is_empty():
		return
	# phase 1 broods every other turn; phase 2 every turn. No sacs left, no brood.
	if sacs(u) == 0:
		return
	if hatched and bt.bosses.phase(u) == 1:
		return
	bt.bosses.start_windup(u, "brood", {})
	Sfx.play("chitter", -2)
	bt.shake += 2

func brood_hatch(u: Unit, w: Dictionary) -> void:
	## Last turn's swelling sacs burst: a Skitter from every sac still hanging, and they act now.
	var live: Array = bt.bosses.parts_of(u, "sac")
	if live.is_empty():
		return
	bt.float_text(u, "THE BROOD HATCHES!", Color("9df25c"), true)
	Sfx.play("splash")
	bt.bosses.slowmo(Vector2(u.x, u.y - 40), 26, 0.4)
	var full: int = bt.units.filter(func(o): return o.type == "skitter" and not o.dead and not o.gone).size()
	for p in live:
		if full >= Data.BROOD_CAP:
			break
		for k in Data.BROOD_PER_SAC:
			bt.vharr_ai.spawn_skitter(p.x + (k * 2 - 1) * 10, u.y)
			full += 1
		bt.part({"x": p.x, "y": p.y - 6, "vx": 0.0, "vy": -1.0, "life": 26, "max": 26, "c": Color("9df25c"), "s": 4.0, "g": 0.05})
	await bt.wait(24)

func sac_down(u: Unit) -> void:
	## A sac shot off: mid-swell the brood dies inside and the acid burns her.
	if bt.bosses.winding(u):
		bt.bosses.cancel_windup(u)
		bt.banner("STILLBORN!", Color("9df25c"), "THE BROOD DIED IN THE SAC")
		bt.acids.append({"x": u.x, "y": u.y, "r": 50.0, "turns": 2})
		bt.damage(u, Data.SAC_BURST_DMG, null, {"blast": true})
	if sacs(u) == 0 and not u.dead:
		bt.banner("NO MORE BROOD", Color("9df25c"), "SHE CAN ONLY BITE AND SPIT NOW")

# ---------------------------------------------------------------- B4 IRONJAW
func boom_tip(u: Unit) -> Vector2:
	## The end of the crane's boom, out in front of the cab.
	return Vector2(u.x + u.face * 82, u.y - 162)

func ball_pos(u: Unit) -> Vector2:
	var a: float = u.fl.get("swing", 0.0)
	return boom_tip(u) + Vector2(sin(a), cos(a)) * Data.CABLE_LEN

func ironjaw_turn(u: Unit, swung: bool) -> void:
	# the cab gun every turn
	var best = bt.foe_ai.best_shot(u, bt.squad_alive(), Data.ETYPES.ironjaw.range)
	if best != null:
		await bt.foe_ai.enemy_shoot(u, best.t, Data.ETYPES.ironjaw)
	if u.dead or bt.squad_alive().is_empty():
		return
	var ball: bool = not u.fl.get("ball_gone", false)
	var has_magnet: bool = bt.bosses.parts_of(u, "magnet").size() > 0
	if not ball:
		if has_magnet:
			await magnet(u)
		return
	# phase 1: hoist, swing, magnet, and round again. Phase 2: the brake is shot and it hoists
	# again the turn it swings.
	if swung and bt.bosses.phase(u) == 1:
		u.fl["rest"] = true
		return
	if u.fl.get("rest", false):
		u.fl.erase("rest")
		if has_magnet:
			await magnet(u)
			return
	await hoist(u)

func hoist(u: Unit) -> void:
	## The crane rolls up until its boom is over a soldier and winches the ball back, high and held.
	var opts := bt.squad_alive()
	if opts.is_empty():
		return
	var tg: Unit = bt.pick(opts)
	var want: float = tg.x - u.face * 82.0
	var dir := signf(want - u.x)
	var pts: Array = []
	var x := u.x
	var y := u.y
	for i in int(minf(absf(want - u.x), Data.CRANE_ROLL) / 2.0):
		var nx := x + dir * 2.0
		if nx > bt.cam_x + bt.W - 60 or nx < bt.cam_x + 120:
			break
		var ny = bt.T.stand_y(nx, y - 30)
		if ny == null or absf(ny - y) > 16:
			break
		x = nx; y = ny
		pts.append([x, y, false])
	if pts.size():
		var keep := u.face
		await bt.phys.walk_along(u, pts)
		u.face = keep  # crawler tracks: it reverses, it doesn't turn round
	var back := float(u.face) * Data.SWING_BACK  # hauled out in front, high over the soldier
	var a0: float = u.fl.get("swing", 0.0)
	Sfx.play("engine", -4)
	for i in 30:
		u.fl["swing"] = lerpf(a0, back, float(i + 1) / 30.0)
		await bt.tick
	bt.bosses.start_windup(u, "swing", {"a": back})

func ball_swing(u: Unit, w: Dictionary) -> void:
	## The brake comes off: a real pendulum through everything in its arc, walls and soldiers.
	var a: float = w.a
	var om := 0.0
	var L: float = Data.CABLE_LEN
	var hit := {}
	bt.float_text(u, "BRAKE OFF!", Color("ffd23a"), true)
	Sfx.play("whoosh")
	var low := boom_tip(u) + Vector2(0, L)
	bt.bosses.slowmo(low, 40, 0.35)
	for i in 110:
		om += -Data.SWING_G / L * sin(a)
		om *= 0.993
		a += om
		u.fl["swing"] = a
		var p := ball_pos(u)
		var spd := absf(om) * L
		if spd > 2.0:
			if bt.T.solid(p.x, p.y + 4):
				bt.T.carve(p.x, p.y, Data.BALL_R + 2, null)
				bt.dust(p.x, p.y, Color("8a7a6a"), 2)
				if i % 4 == 0:
					bt.shake += 2
					Sfx.play("thud", -6)
			for o in bt.units:
				if o == u or o.dead or o.gone or o.sunk or o.is_pickup() or o.kind == "pow" or hit.has(o.id) or o.fl.get("boss") == u:
					continue
				if absf(p.x - o.x) < o.w / 2.0 + Data.BALL_R and p.y + Data.BALL_R > o.y - o.h and p.y - Data.BALL_R < o.y:
					hit[o.id] = true
					bt.damage(o, Data.SWING_DMG, u, {"melee": true})
					Sfx.play("bonk")
					bt.shake += 8
					if not o.dead:
						bt.spec_kits.fling(o, signf(om), 7.0, u)
		await bt.tick
	# it settles back under the boom
	var a1: float = u.fl.swing
	for i in 20:
		u.fl["swing"] = lerpf(a1, 0.0, float(i + 1) / 20.0)
		await bt.tick

func magnet(u: Unit) -> void:
	## The magnet on the second line: drags the nearest soldier off their feet toward the crane.
	var tg = bt.nearest_squad(u)
	if tg == null or absf(tg.x - u.x) > Data.MAGNET_RANGE:
		return
	bt.float_text(tg, "MAGNET!", Color("ff4d3d"), true)
	Sfx.play("power", -4)
	u.fl["magnet_t"] = 30
	await bt.wait(14)
	if tg.dead:
		return
	var dir: float = signf(u.x - tg.x)
	bt.damage(tg, Data.MAGNET_DMG, u, {})
	if tg.dead or tg.heavy or tg.immovable:
		await bt.wait(20)
		return
	# up off their feet and across toward the crane on an arc, until something solid is in the way
	var x0: float = tg.x
	var y0: float = tg.y
	var go: float = clampf(absf(u.x - tg.x) - u.w / 2.0 - 30.0, 0.0, Data.MAGNET_PULL)
	tg.walk = null
	tg.fl["carried"] = true
	for i in 30:
		var k := float(i + 1) / 30.0
		var nx: float = x0 + dir * go * k
		var ny: float = y0 - sin(k * PI) * 50.0 - 6.0 * k
		if bt.T.solid(nx + dir * 6, ny - tg.h / 2.0) or bt.T.solid(nx, ny - tg.h):
			break
		tg.x = nx
		tg.y = ny
		await bt.tick
	tg.fl.erase("carried")
	tg.vx = dir * 1.0; tg.vy = 0.0; tg.air = true
	await bt.wait(24)

func winch_down(u: Unit) -> void:
	## The winch shot off: the cable runs out and the ball drops on whatever is under it.
	if u.fl.get("ball_gone", false):
		return
	u.fl["ball_gone"] = true
	bt.bosses.cancel_windup(u)
	var p := ball_pos(u)
	var cells: Array = []
	var c0 := Vector2i(int(p.x / bt.CELL), int(p.y / bt.CELL))
	for cx in range(-3, 4):
		for cy in range(-3, 4):
			if cx * cx + cy * cy <= 10 and not bt.T.solid((c0.x + cx) * bt.CELL + 2, (c0.y + cy) * bt.CELL + 2):
				cells.append([c0.x + cx, c0.y + cy, bt.T.STEEL, 0])
	var c = bt.T.chunk_from_cells(cells, null)
	if c != null:
		c.hit[u.id] = true
	bt.shake += 10
	Sfx.play("collapse")

# ---------------------------------------------------------------- B6 the biome bosses' wind-ups
func engine_steam(u: Unit) -> void:
	## The Armored Engine builds a head of steam: the whistle, steam pouring off the boiler. It rams next turn.
	bt.bosses.start_windup(u, "steam", {})
	Sfx.play("engine", -2)

func drill_rev(u: Unit) -> void:
	## The Drill Rig picks the nearest soldier in front, revs, and the rock trembles where it will
	## come through. Next turn it bores straight there.
	var tg = null
	for o in bt.squad_alive():
		if o.x < u.x and (tg == null or absf(o.x - u.x) < absf(tg.x - u.x)):
			tg = o
	if tg == null:
		return
	Sfx.play("drill", -6)
	bt.bosses.start_windup(u, "rev", {"x": tg.x, "y": tg.y - tg.h / 2.0})

func drill_bore(u: Unit, w: Dictionary) -> void:
	## Through the rock to last turn's spot: anyone on the line or still standing there is hit.
	var from := Vector2(u.x - u.w / 2.0, u.y - 18)
	var to := Vector2(w.x, w.y)
	bt.float_text(u, "DRILLING!", Color("ffb23e"), true)
	Sfx.play("drill")
	bt.bosses.slowmo(to, 26, 0.4)
	var hit := {}
	var steps := int(from.distance_to(to) / 8.0)
	for k in steps + 1:
		var p := from.lerp(to, float(k) / maxf(1, steps))
		bt.T.carve(p.x, p.y, 12, null)
		for o in bt.squad_alive():
			if not hit.has(o.id) and absf(o.x - p.x) < o.w / 2.0 + 8 and p.y > o.y - o.h - 8 and p.y < o.y + 6:
				hit[o.id] = true
				bt.damage(o, Data.DRILL_DMG + 4, u, {"melee": true})
		if k % 3 == 0:
			bt.dust(p.x, p.y, Color("8a7a6a"), 1)
			bt.shake += 0.6
			await bt.wait(1)
	await bt.until(bt.settled)
	await bt.wait(8)

func magma_crack(u: Unit) -> void:
	## The Magma Crawler's shell splits and glows; cracks in the ground under the squad start to glow
	## and smoke. Next turn lava erupts out of each one.
	var spots: Array = []
	for o in bt.squad_alive():
		if spots.size() >= 3:
			break
		var gy = bt.T.stand_y(o.x, o.y - 10)
		spots.append([o.x, gy if gy != null else o.y])
	bt.bosses.start_windup(u, "erupt", {"spots": spots})
	Sfx.play("collapse", -8)

func eruption(u: Unit, w: Dictionary) -> void:
	bt.float_text(u, "ERUPTION!", Color("ff7a3d"), true)
	Sfx.play("bigboom")
	if w.spots.size():
		bt.bosses.slowmo(Vector2(w.spots[0][0], w.spots[0][1] - 40), 30, 0.35)
	for sp in w.spots:
		var x: float = sp[0]
		var y: float = sp[1]
		bt.shake += 6
		for k in 24:
			bt.part({"x": x + randf_range(-10, 10), "y": y - 2, "vx": randf_range(-1.2, 1.2), "vy": -randf_range(4.0, 8.0), "life": 40, "max": 40, "c": bt.pick([Color("ff7a3d"), Color("ffb23e"), Color("ffd23a")]), "s": 4.0, "g": 0.15, "fire": true})
		for o in bt.units:
			if o.dead or o.gone or o.team == "enemy" or o.is_pickup() or o.kind == "pow":
				continue
			if absf(o.x - x) < Data.ERUPT_R + o.w / 2.0 and o.y > y - 80 and o.y < y + 10:
				bt.damage(o, Data.ERUPT_DMG, u, {"blast": true})
				bt.add_status(o, "burn", 2, u)
		bt.vharr_ai.magma_burn(x, y)
		await bt.wait(10)
	await bt.until(bt.settled)

# ---------------------------------------------------------------- B5 SKY SERPENT
func segs(u: Unit) -> Array:
	var a: Array = bt.bosses.parts_of(u, "seg")
	a.sort_custom(func(x, y): return x.fl.i < y.fl.i)
	return a

func serpent_speed(u: Unit) -> float:
	var lost: int = int(u.fl.get("segs0", Data.SERPENT_SEGS)) - segs(u).size()
	return Data.SERPENT_SPD + Data.SERPENT_SPD_SEG * maxi(0, lost)

func trail_at(u: Unit, d: float) -> Array:
	## The point d px back along the head's path, and the direction there.
	var tr: Array = u.fl.trail
	var prev := Vector2(u.x, u.y)
	var acc := 0.0
	for q in tr:
		var L := prev.distance_to(q)
		if acc + L >= d and L > 0.01:
			var k := (d - acc) / L
			return [prev.lerp(q, k), (prev - q).angle()]
		acc += L
		prev = q
	return [prev, 0.0 if u.face < 0 else PI]

func pin_segs(u: Unit) -> void:
	## Each surviving segment rides its slot along the head's path; shot-off ones close up the gap.
	var n := 0
	for p in segs(u):
		n += 1
		var t := trail_at(u, n * Data.SEG_GAP)
		p.x = t[0].x
		p.y = t[0].y + p.h / 2.0
		p.fl["ang"] = t[1]
		p.active = u.active

func move_head(u: Unit, to: Vector2) -> void:
	## One frame of motion: the head moves, its path grows, the body follows.
	var from := Vector2(u.x, u.y)
	if from.distance_to(to) < 0.01:
		return
	u.fl["heading"] = (to - from).angle()
	u.face = -1 if to.x < from.x else 1
	u.x = to.x
	u.y = to.y
	var tr: Array = u.fl.trail
	if tr.is_empty() or tr[0].distance_to(from) >= 4.0:
		tr.push_front(from)
	var keep := (Data.SERPENT_SEGS + 3) * Data.SEG_GAP
	var acc := 0.0
	var prev := to
	for i in tr.size():
		acc += prev.distance_to(tr[i])
		prev = tr[i]
		if acc > keep:
			tr.resize(i + 1)
			break
	pin_segs(u)

func swim(u: Unit, path: Callable, n: int, whip := false) -> void:
	## Follows path(t) for t in 0..1 over n frames; the tail stinger whips whoever it passes over.
	var hit := {}
	for i in n:
		if u.dead:
			return
		var t := float(i + 1) / n
		move_head(u, path.call(t))
		if whip:
			var body := segs(u)
			var tail: Unit = body[-1] if body.size() else u
			for o in bt.squad_alive():
				if not hit.has(o.id) and absf(o.x - tail.x) < 30 and absf(o.y - o.h / 2.0 - tail.y) < 40:
					hit[o.id] = true
					bt.damage(o, Data.TAIL_DMG, u, {"melee": true})
					bt.float_text(o, "STUNG", Color("6ad0ff"))
					bt.spec_kits.fling(o, signf(o.x - tail.x + 0.01), 4.0, u)
					Sfx.play("slash")
		await bt.tick

func serpent_arena(u: Unit) -> Array:
	return [bt.cam_x + 90.0, bt.cam_x + bt.W - 90.0]

func serpent_turn(u: Unit, dove: bool) -> void:
	if dove and bt.bosses.phase(u) == 1:
		return  # the dive was its move this turn
	var sq := bt.squad_alive()
	if sq.is_empty():
		return
	var ar := serpent_arena(u)
	var cy: float = u.fl.cruise_y
	# the pass: a wide arc across the arena that dips low over the squad
	var x0 := u.x
	var y0 := u.y
	var x1: float = ar[0] if u.x > (ar[0] + ar[1]) / 2.0 else ar[1]
	var gmid: float = bt.T.ground_at((x0 + x1) / 2.0)
	var low: float = minf(gmid, bt.WATER_Y) - 70.0
	var n := int(absf(x1 - x0) / serpent_speed(u)) + 1
	Sfx.play("whoosh")
	await swim(u, func(t): return Vector2(lerpf(x0, x1, t), lerpf(y0, cy, t) + (low - cy) * sin(PI * t)), n, true)
	if u.dead or bt.squad_alive().is_empty():
		return
	# then it coils high over a soldier, its head glowing: next turn it dives there
	var tg: Unit = bt.pick(bt.squad_alive())
	var tx: float = clampf(tg.x, ar[0], ar[1])
	var hx := u.x
	var hy := u.y
	var top: float = cy - 40.0
	await swim(u, func(t): return Vector2(lerpf(hx, tx, t) + sin(t * TAU) * 40.0 * (1.0 - t), lerpf(hy, top, t) - sin(t * PI) * 30.0), 50)
	bt.bosses.start_windup(u, "dive", {"x": tx})
	Sfx.play("roar", -6)

func serpent_dive(u: Unit, w: Dictionary) -> void:
	## Straight down on last turn's spot, through the ground, along a tunnel and out again.
	var x: float = w.x
	var gy = bt.T.stand_y(x, u.y)
	var ground: float = gy if gy != null else bt.WATER_Y
	var hy := u.y
	var hx := u.x
	bt.float_text(u, "IT DIVES!", Color("6ad0ff"), true)
	Sfx.play("whoosh")
	var nd := int(maxf(10.0, (ground - hy) / 11.0))
	await swim(u, func(t): return Vector2(lerpf(hx, x, minf(1.0, t * 3.0)), lerpf(hy, ground, t * t)), nd)
	if u.dead:
		return
	# impact: a crater and everyone near it
	bt.shake += 14
	Sfx.play("bigboom")
	bt.bosses.slowmo(Vector2(x, ground - 30), 36, 0.3)
	bt.T.carve(x, ground, 34, null)
	bt.dust(x, ground, Color("8a7a6a"), 18)
	for o in bt.units:
		if o.dead or o.gone or o.team == "enemy" or o.is_pickup() or o.kind == "pow":
			continue
		if Vector2(o.x, o.y - o.h / 2.0).distance_to(Vector2(x, ground)) < Data.DIVE_R + o.w / 2.0:
			bt.damage(o, Data.DIVE_DMG, u, {"melee": true})
			bt.spec_kits.fling(o, signf(o.x - x + 0.01), 6.0, u)
	# the tunnel: down and along, away from the squad, then out
	var sx := 0.0
	for o in bt.squad_alive():
		sx += o.x
	sx /= maxf(1, bt.squad_alive().size())
	var ar := serpent_arena(u)
	var dir := 1.0 if x >= sx else -1.0
	var ex: float = clampf(x + dir * 200.0, ar[0], ar[1])
	if absf(ex - x) < 100:
		ex = clampf(x - dir * 200.0, ar[0], ar[1])
	var deep := ground + 46.0
	var cy: float = u.fl.cruise_y
	var steps := int(absf(ex - x) / 5.0) + 20
	var tunnel := func(t: float) -> Vector2:
		var ty: float = deep - sin(t * PI) * 10.0 if t < 0.85 else lerpf(deep, ground - 10.0, (t - 0.85) / 0.15)
		var p := Vector2(lerpf(x, ex, t), ty)
		if int(t * steps) % 2 == 0:
			bt.T.carve(p.x, p.y, 16, null)
		return p
	await swim(u, tunnel, steps)
	if u.dead:
		return
	# it bursts out of the ground
	var oy = bt.T.stand_y(ex, ground - 60)
	var out_y: float = oy if oy != null else ground
	bt.T.carve(ex, out_y, 26, null)
	for i in 10:
		bt.debris(ex + randf_range(-20, 20), out_y - randf_range(0, 10), 9)
	bt.shake += 8
	Sfx.play("collapse")
	var bx := u.x
	var by := u.y
	await swim(u, func(t): return Vector2(bx, lerpf(by, cy, t)), 40)
	await bt.until(bt.settled)

func serpent_split(u: Unit) -> void:
	## Phase 2: the back half of the body tears off and grows a head of its own.
	if u.fl.get("twin_of") != null:
		return
	var body := segs(u)
	if body.size() < 2:
		return
	bt.bosses.cancel_windup(u)
	var half := body.size() / 2
	var cut: Unit = body[half]
	var tw := bt.mk_enemy("serpent", cut.x, cut.y - cut.h / 2.0)
	tw.active = true
	tw.weight = "hover"
	tw.heavy = true
	tw.hp = maxi(1, u.hp / 2)
	tw.max_hp = u.max_hp / 2
	u.hp = maxi(1, u.hp - tw.hp)
	tw.face = -u.face
	tw.fl["phase2"] = true
	tw.fl["twin_of"] = u
	tw.fl["scripted"] = true
	tw.fl["cruise_y"] = u.fl.cruise_y + 30.0
	tw.fl["segs0"] = body.size() - half
	tw.fl["trail"] = []
	u.fl["segs0"] = half
	bt.units.append(tw)
	var k := 0
	for i in range(half + 1, body.size()):
		var p: Unit = body[i]
		p.fl["boss"] = tw
		p.fl["i"] = k
		tw.fl.trail.append(Vector2(p.x, p.y - p.h / 2.0))
		k += 1
	bt.kill(cut, null)  # the torn segment
	pin_segs(u)
	pin_segs(tw)
	bt.float_text(tw, "A SECOND HEAD!", Color("6ad0ff"), true)
	Sfx.play("roar")

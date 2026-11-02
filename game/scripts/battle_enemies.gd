class_name BattleEnemies
extends RefCounted
## The Jackals' side: the enemy phase, Jackal AI and the newer Jackal types.
## Split out of battle.gd (R3). Functions only: every piece of mission state lives on the Battle,
## reached through `bt`.

var bt: Battle

func _init(battle: Battle) -> void:
	bt = battle

# ---------------------------------------------------------------- E1-E5, E7, E8: new Jackals
func sniper_line(e: Unit) -> Dictionary:
	## E1: where the Jackal Sniper's laser runs right now, from his scope to the first wall.
	var o := Vector2(e.x + e.face * 10, e.y - e.h + 10)
	var a: float = e.fl.get("laser", PI if e.face < 0 else 0.0)
	var r := bt.cast_ray(o.x, o.y, a, Data.ETYPES.jsniper.range)
	return {"from": o, "to": Vector2(r.x, r.y), "a": a}

func sniper_act(e: Unit) -> void:
	## Fire down the laser he showed last turn, then lay it on the nearest soldier for next time.
	var E: Dictionary = Data.ETYPES.jsniper
	if e.fl.has("laser"):
		var L := sniper_line(e)
		e.muzzle = 4
		e.muzzle_kind = "snipe"
		Sfx.play("snipe")
		bt.fire_bullet(e, L.from.x, L.from.y, L.a, {"dmg": E.dmg, "range": E.range, "bounce": 0, "chip": 5}, false)
		await bt.wait(24)
	if e.dead or e.air:
		return
	var tg = null
	var o := Vector2(e.x, e.y - e.h + 10)
	for s in bt.foes_of(e):
		if s.team == "squad" and not bt.targetable(e, s):
			continue
		if bt.ray_clear(o.x, o.y, s.x, s.y - s.h / 2.0) and (tg == null or absf(s.x - e.x) < absf(tg.x - e.x)):
			tg = s
	if tg == null:
		tg = bt.nearest_squad(e)
	if tg == null:
		return
	e.face = 1 if tg.x >= e.x else -1
	var o2 := Vector2(e.x + e.face * 10, e.y - e.h + 10)
	e.fl["laser"] = atan2(tg.y - tg.h / 2.0 - o2.y, tg.x - o2.x)
	bt.float_text(e, "LASER ON " + (tg.def.name if tg.team == "squad" else "TARGET"), Color("ff4d3d"))
	Sfx.play("tick")
	await bt.wait(10)

func flamer_act(e: Unit) -> void:
	## E2: walk up and hose a short cone of fire. Wood in the cone burns away.
	var E: Dictionary = Data.ETYPES.flamer
	var tg = bt.nearest_squad(e)
	if tg == null:
		return
	if absf(tg.x - e.x) > E.range - 20 and not e.hold:
		await enemy_advance(e, tg.x - signf(tg.x - e.x) * (E.range - 40), E.speed, func():
			var t2 = bt.nearest_squad(e)
			return t2 != null and absf(t2.x - e.x) <= E.range - 20 and absf(t2.y - e.y) < 50)
	if e.dead or e.air:
		return
	tg = bt.nearest_squad(e)
	if tg == null or absf(tg.x - e.x) > E.range or absf(tg.y - e.y) > 50:
		return
	e.face = 1 if tg.x >= e.x else -1
	e.pose = "recoil"; e.pose_t = 30
	Sfx.play("flame")
	for f in 18:
		for k in 3:
			bt.part({"x": e.x + e.face * 14, "y": e.y - 18, "vx": e.face * randf_range(4, 7), "vy": randf_range(-1.2, 1.2), "life": 18, "max": 18, "c": bt.pick([Color("ffb23e"), Color("ff7a3d"), Color("ffe36a")]), "s": 3.0, "g": -0.03, "fire": true})
		await bt.wait(1)
	for o in bt.units:
		if o == e or o.dead or o.gone or o.sunk or o.is_pickup() or o.kind == "pow" or signf(o.x - e.x) != e.face:
			continue
		if absf(o.x - e.x) <= E.range and absf(o.y - e.y) < 44:
			bt.damage(o, int(round(E.dmg * (1 + bt.alert * 0.06))), e, {})
			bt.add_status(o, "burn", 2, e)
	var x := e.x + e.face * 16
	while absf(x - e.x) <= E.range:
		for dy in [6, 18, 30]:
			if bt.T.mat(x, e.y - dy) == 3:
				bt.T.carve(x, e.y - dy, 6, null)  # wood in the cone goes up
		x += e.face * 10
	await bt.wait(10)

func tank_hit(tg: Unit, dx: float, by) -> bool:
	## E2: a round into the Flametrooper's back finds the fuel tank.
	if tg.type != "flamer" or tg.dead or tg.fl.get("tank_gone", false) or signf(dx) != tg.face:
		return false
	tg.fl["tank_gone"] = true
	bt.float_text(tg, "TANK HIT!", Color("ffb23e"), true)
	bt.booms.append({"t": 1, "x": tg.x - tg.face * 6, "y": tg.y - 20, "r": 54.0, "dmg": 18, "owner": by, "burn": true})
	return true

func wall_mates(e: Unit) -> Array:
	## E5: the Riot Jackals locked in one Shield Wall with this one (itself included).
	if not e.fl.has("wall") or e.dead:
		return []
	return bt.units.filter(func(o): return not o.dead and not o.gone and o.fl.get("wall", -1) == e.fl.wall and absf(o.x - e.x) < 70 and absf(o.y - e.y) < 30)

func wall_locked(e: Unit) -> bool:
	return wall_mates(e).size() >= 2

func wall_act(e: Unit) -> bool:
	## The wall's front man walks it forward as one block; the others only shoot. Returns true if handled.
	var mates := wall_mates(e)
	if mates.size() < 2:
		return false
	mates.sort_custom(func(a, b2): return a.x < b2.x)
	var tg = bt.nearest_squad(e)
	if tg == null:
		return true
	var dir := 1.0 if tg.x > e.x else -1.0
	var lead: Unit = mates[-1] if dir > 0 else mates[0]
	if e == lead and e.fl.get("wall_moved", -1) != bt.round_n and not e.hold:
		var E: Dictionary = Data.ETYPES[e.type]
		var x0 := lead.x
		var stop: float = tg.x - dir * E.prefer
		if (stop - lead.x) * dir > 0:
			await enemy_advance(lead, stop, E.speed)
		var moved := lead.x - x0
		for m in mates:
			m.fl["wall_moved"] = bt.round_n
			if m != lead and absf(moved) > 1:
				var tx: float = m.x + moved
				var ty = bt.T.stand_y(tx, m.y - 30)
				if ty != null:
					var pts: Array = []
					var n := int(absf(moved) / 2.0)
					for k in n:
						pts.append([m.x + moved * (k + 1) / n, ty, false])
					await bt.phys.walk_along(m, pts)
		bt.float_text(lead, "SHIELD WALL", Color("c9d1da"))
	if e.dead or e.air:
		return true
	var E2: Dictionary = Data.ETYPES[e.type]
	var bs = best_shot(e, bt.foes_of(e), E2.range)
	if bs != null:
		await bt.wait(4)
		await enemy_shoot(e, bs.t, E2)
	return true

func chute_hit(tg: Unit, y: float) -> bool:
	## E3: a round through the parachute cuts it; the trooper drops like a stone.
	if not tg.para or y > tg.y - tg.h:
		return false
	tg.para = false
	tg.fl.erase("chute")
	tg.vy = 2.0
	bt.float_text(tg, "CHUTE CUT!", Color("ffd23a"), true)
	Sfx.play("ping")
	return true

func plane_drop(n: int) -> void:
	## E3: a plane crosses the top of the screen and drops troopers on chutes. They hang there
	## through your turn and come down in the next enemy phase.
	var drop: Array = ["grunt", "grunt", "shield", "nade"]
	bt.banner("PARATROOPERS!", Color("ff7a3d"), "SHOOT THE CHUTES BEFORE THEY LAND")
	Sfx.play("alarm")
	for i in n:
		var x: float = bt.cam_x + bt.W - 120 - i * 70
		var e := bt.mk_enemy(drop[i % drop.size()], x, 70.0 + (i % 2) * 22)
		e.active = true; e.heavy = false; e.air = true; e.para = true; e.vy = 0.0
		e.fl["chute"] = true
		bt.units.append(e)
		bt.puff(x, 50, 2.0)
		await bt.wait(8)
	bt.log_msg("Paratroopers hang over the field. Shoot a chute and its trooper falls hard.")

func gunship_act(e: Unit) -> void:
	## E7: fly over the marked strip and rake it, then mark the next strip by the nearest soldier.
	var E: Dictionary = Data.ETYPES.gunship
	if e.fl.has("strafe"):
		var sx: float = (e.fl.strafe.x0 + e.fl.strafe.x1) / 2.0
		await bt.vharr_ai.hover_move(e, sx, E.speed * 2)
		if e.dead:
			return
		Sfx.play("mg")
		var x0: float = e.fl.strafe.x0
		var x1: float = e.fl.strafe.x1
		for k in 8:
			var gx: float = lerpf(x0, x1, k / 7.0)
			var gy = bt.T.stand_y(gx, 0)
			bt.tracer(e.x, e.y - 6, gx, gy if gy != null else bt.WATER_Y, Color("ffb0a0"))
			if gy != null:
				bt.T.carve(gx, gy, 3, null)
				bt.dust(gx, gy, Color("c9b38a"), 2)
			await bt.wait(3)
		for o in bt.units:
			if o == e or o.dead or o.gone or o.sunk or o.is_pickup() or o.kind == "pow" or o.team == "enemy":
				continue
			if o.x >= x0 - o.w / 2.0 and o.x <= x1 + o.w / 2.0 and not o.has_st("cloak"):
				bt.damage(o, int(round(E.dmg * (1 + bt.alert * 0.06))), e, {})
		e.fl.erase("strafe")
		await bt.wait(10)
	var tg = bt.nearest_squad(e)
	if tg == null or e.dead:
		return
	e.face = 1 if tg.x >= e.x else -1
	e.fl["strafe"] = {"x0": tg.x - E.strafe / 2.0, "x1": tg.x + E.strafe / 2.0}
	bt.float_at(tg.x, tg.y - 50, "STRAFING RUN NEXT TURN", Color("ff4d3d"), true)

func rotor_check() -> void:
	## E7: a body or a barrel thrown into the gunship's rotor wrecks it.
	for g in bt.units:
		if g.type != "gunship" or g.dead or g.gone:
			continue
		for o in bt.units:
			if o == g or o.dead and not o.is_body() or o.gone or not o.air or o.fl.get("rotored", -1) == g.id:
				continue
			if absf(o.x - g.x) < g.w / 2.0 + 4 and o.y - o.h < g.y - g.h + 4 and o.y > g.y - g.h - 14:
				o.fl["rotored"] = g.id
				o.vy = 3.0
				o.vx *= -0.4
				bt.float_text(g, "ROTOR HIT!", Color("ffb23e"), true)
				Sfx.play("bonk")
				bt.sparks(o.x, g.y - g.h, 10)
				bt.damage(g, 18, o.last_hit_by if o.last_hit_by is Unit else null, {"blast": true})

func gunship_down(g: Unit) -> void:
	g.weight = ""
	g.air = true
	g.vy = 0.0
	g.walk = null
	g.fl["crashing"] = true  # it still has to come down
	bt.float_text(g, "GOING DOWN!", Color("ff7a3d"), true)

func gunship_crash(g: Unit) -> void:
	## E7: the wreck crushes whatever it lands on.
	g.fl.erase("crashing")
	g.dead = true
	g.gone = true
	bt.shake += 10
	bt.explode(g.x, g.y - 10, 64, 26, g.last_hit_by if g.last_hit_by is Unit else null)
	for k in 12:
		bt.debris(g.x + randf_range(-30, 30), g.y - randf_range(4, 30), 2)
	bt.float_at(g.x, g.y - 40, "GUNSHIP DOWN!", Color("ffb23e"), true)

func dicokka_act(e: Unit) -> void:
	## E8: roll back and forth a set step, then lob a shell. Flipped, it just lies there.
	var E: Dictionary = Data.ETYPES.dicokka
	if e.fl.get("flipped", 0) > 0:
		e.fl.flipped -= 1
		if e.fl.flipped <= 0:
			e.fl.erase("flipped")
			bt.float_text(e, "BACK ON ITS TRACKS", Color("ff7a3d"))
		else:
			bt.float_text(e, "FLIPPED", Color("ffd23a"))
		return
	if not e.fl.has("home"):
		e.fl["home"] = e.x
		e.fl["dir"] = -1.0
	var tx: float = e.fl.home + e.fl.dir * 110
	e.fl.dir = -e.fl.dir
	await enemy_advance(e, tx, E.speed)
	if e.dead or e.air:
		return
	var tg = bt.nearest_squad(e)
	if tg == null or absf(tg.x - e.x) > E.range:
		return
	e.face = 1 if tg.x >= e.x else -1
	await lob(e, tg, E.dmg, E.radius, 1.3)

func dicokka_dmg(tg: Unit, amt: int, src, o: Dictionary) -> int:
	## Armored front, soft from above and behind, and twice as soft flipped on its back.
	if tg.fl.get("flipped", 0) > 0:
		bt.float_text(tg, "BELLY HIT", Color("ffd23a"))
		return amt * 2
	if not (src is Unit) or o.get("status", false):
		return amt
	var above: bool = src.y < tg.y - tg.h - 10
	var front: bool = signf(src.x - tg.x) == tg.face
	if front and not above:
		bt.float_text(tg, "ARMOR", Color("9fb4c9"))
		return maxi(1, int(round(amt * 0.3)))
	return int(round(amt * 1.5))

func dicokka_land(u: Unit, imp: float) -> void:
	if u.type == "dicokka" and not u.dead and imp > 3.5 and u.last_hit_by is Unit and u.last_hit_by.team == "squad":
		u.fl["flipped"] = 2
		bt.float_text(u, "FLIPPED!", Color("ffd23a"), true)
		Sfx.play("thud")
		bt.shake += 4

func enemy_phase() -> void:
	if bt.practice():
		await bt.boot_camp.practice_round()
		return
	if (bt.tutorial() and bt.tut_step < bt.TUT_FIGHT) or (bt.in_lesson() and not bt.lesson().get("live", false)):
		# the drill's targets never shoot back
		bt.state = "enemy"
		bt.busy = true
		bt.ui_dirty = true
		await bt.wait(20)
		bt.start_player_turn()
		return
	bt.state = "enemy"
	bt.spec_kits.release_holds()
	if bt.squad_alive().any(func(h): return h.perk("netcall")):
		for s in bt.squad_alive():
			s.overwatch = maxi(s.overwatch, 1)
	bt.busy = true
	bt.ui_dirty = true
	bt.banner("ENEMY PHASE", Color("ff4d3d"))
	await bt.wait(45)
	bt.vtech.relay_waves()
	bt.camp_ops.hold_waves()
	for m in bt.units.filter(func(e): return e.elite == "medic" and not e.dead and e.active):
		for e in bt.units:
			if e.team == "enemy" and not e.dead and e != m and e.hp < e.max_hp and absf(e.x - m.x) < 140:
				e.hp = mini(e.max_hp, e.hp + 4)
				bt.float_text(e, "+4", Color("62d26f"))
	bt.tick_statuses("enemy")
	for u in bt.units:
		if u.dome > 0:
			u.dome -= 1
	await bt.until(bt.settled)
	if bt.strikes.size():
		var friendly := bt.strikes.filter(func(s): return s.get("friendly", false))
		bt.banner("AIRSTRIKE!", Color("62d26f") if friendly.size() == bt.strikes.size() else Color("ff4d3d"))
		Sfx.play("alarm")
		for s in bt.strikes:
			var n: int = s.get("n", 3) if s.get("friendly", false) else 1
			for k in n:
				var ox: float = 0.0 if n == 1 else (k - (n - 1) / 2.0) * 34.0
				bt.projs.append(bt.phys.mk_proj({"kind": "bomb", "x": s.x + ox, "y": -20.0 - k * 30, "vx": 0.0, "vy": 5.0, "r": 48.0, "dmg": 15, "owner": s.get("owner", null)}))
			await bt.wait(14)
		bt.strikes = []
		await bt.until(bt.settled)
		await bt.wait(10)
	if not bt.ambush.is_empty() and not bt.ambush.done and bt.squad_alive().any(func(q): return q.x >= bt.ambush.x - 120):
		await pod_ambush()
	for sl in bt.units.filter(func(u): return u.kind == "slug" and not u.gone):
		await bt.vtech.slug_act(sl)
	await bt.spec_kits.sentries_fire()
	var armed := bt.units.filter(func(u): return u.kind == "charge" and not u.dead and not u.gone and not u.primed)
	if armed.size():
		for c in armed:
			c.primed = true
			bt.booms.append({"t": 4, "x": c.x, "y": c.y - 4, "r": 48.0, "dmg": 16, "owner": null, "barrel": c})
		await bt.until(bt.settled)
		await bt.wait(10)
	# gone or sunk units are out of the tick, so they can't take a turn (a walk would wait forever)
	var es := bt.units.filter(func(u): return u.team == "enemy" and u.active and not u.dead and not u.gone and not u.sunk)
	es.sort_custom(func(a, b): return a.x < b.x)
	for e in es:
		if e.dead or e.gone or bt.squad_alive().is_empty() or bt.boss_dead:
			break
		if not bt.in_play(e.x, 60) and not e.fl.get("hunt", false):
			continue
		if bt.pincer.get("on", false):
			bt.camp_ops.set_view(bt.wing_at(e.x))  # W9: the camera jumps to whichever half of the pincer this enemy is in
		await bt.until(bt.settled)
		if e.dead:
			continue
		if e.has_st("stun"):
			e.st.erase("stun")
			bt.float_text(e, "STUNNED", Color("ffd23a"), true)
			await bt.wait(20)
			continue
		bt.acting = e
		if bt.squad_alive().any(func(h): return h.perk("hairtrigger") and h.overwatch > 0):
			await overwatch_check(e)
			if e.dead:
				continue
		await enemy_act(e)
		if not e.dead and bt.vharr_ai.alpha_near(e):
			await bt.until(bt.settled)
			bt.float_text(e, "ALPHA!", Color("ffd23a"), true)
			await bt.wait(10)
			await enemy_act(e)
		e.st.erase("supp")
		await bt.until(bt.settled)
		await bt.wait(10)
	bt.acting = null
	while bt.pow_queue.size():
		var q2: Dictionary = bt.pow_queue.pop_front()
		if q2.pow.fl.get("defector", false):
			bt.vharr_ai.sign_defector(q2.pow)
			continue
		bt.score += 500
		bt.stats.pows += 1
	await bt.camp_ops.check_detour()
	await bt.camp_ops.detour_round()
	await bt.camp_ops.job_round()
	if bt.squad_alive().is_empty():
		bt.game_over()
		return
	if bt.boss_dead:
		await bt.until(bt.settled)
		bt.victory()
		return
	if await bt.camp_ops.job_ends():
		return
	for s in bt.smokes:
		s.turns -= 1
		for u in bt.squad_alive():
			var doc := bt.squad_alive().any(func(h): return h.perk("smokedoc"))
			if doc and Vector2(u.x - s.x, u.y - u.h / 2.0 - s.y).length() < s.r:
				u.hp = mini(u.max_hp, u.hp + 3)
				bt.float_text(u, "+3 HP", Color("62d26f"))
	bt.smokes = bt.smokes.filter(func(s): return s.turns > 0)
	bt.vharr_ai.tick_acids()
	for g in bt.gases:
		g.turns -= 1
		if bt.ks(g.owner, "weathervane"):
			var near = null
			for e in bt.units:
				if e.team == "enemy" and not e.dead and (near == null or absf(e.x - g.x) < absf(near.x - g.x)):
					near = e
			if near != null:
				g.x += clampf(near.x - g.x, -36, 36)
		else:
			g.x += bt.wind * 5
	bt.gases = bt.gases.filter(func(g): return g.turns > 0)
	for f in bt.units.filter(func(u): return u.kind == "fuel" and u.leak != null and not u.primed and not u.gone):
		f.leak -= 1
		if f.leak <= 0:
			f.primed = true
			var mul := 2.0 if f.leak_by != null and f.leak_by.perk("chain") else 1.0
			bt.booms.append({"t": 6, "x": f.x, "y": f.y - 15, "r": 84.0, "dmg": int(20 * mul), "owner": f.leak_by, "barrel": f})
			bt.banner("FUEL TANK!", Color("ff7a3d"))
			await bt.until(bt.settled)
			await bt.wait(10)
		else:
			bt.float_text(f, "LEAKING %d" % f.leak, Color("ffd23a"), true)
	if bt.squad_alive().is_empty():
		bt.game_over()
		return
	# alert only climbs when you stall; the radioman's clock is what brings fresh bodies.
	# Digging in on a HOLD job is the order, not a stall.
	if bt.regroup:
		bt.regroup = false
		if bt.rounds_since_scroll >= bt.stall_limit() - 1:
			bt.log_msg("REGROUP: with a soldier down, the line holds one round before the alert climbs.")
	elif not (bt.job() == "hold" and bt.job_st.get("on", false)):
		bt.rounds_since_scroll += 1
	var before := bt.alert
	var calls := 0
	if bt.stalled():
		bt.alert = mini(10, bt.alert + 1)
	var radios := bt.units.filter(func(u): return u.type == "radio" and u.active and not u.dead)
	if radios.is_empty():
		bt.radio_t = null
	else:
		if bt.radio_t == null:
			bt.radio_t = 3 + bt.jammer_rounds()
		bt.radio_t -= 1
		if bt.radio_t <= 0:
			calls = 1
			bt.radio_t = 3 + bt.jammer_rounds()
			bt.alert = mini(10, bt.alert + 1)
			var r: Unit = radios[0]
			bt.part({"x": r.x, "y": r.y - 30, "vx": 0.0, "vy": -6.0, "life": 80, "max": 80, "c": Color("ff4d3d"), "s": 5.0, "g": 0.08, "fire": true})
	bt.stats.max_alert = maxi(bt.stats.max_alert, bt.alert)
	if bt.alert > before and [3, 6, 10].any(func(v): return before < v and bt.alert >= v):
		bt.banner("ALERT %d" % bt.alert, Color("ff4d3d"), "AIR SUPPORT AUTHORIZED" if bt.alert >= 10 else ("THEY KNOW YOU ARE HERE" if bt.alert >= 6 else "THE JACKALS ARE ORGANIZING"))
		Sfx.play("alarm")
		await bt.wait(50)
	if bt.rounds_since_scroll > bt.stall_limit() and bt.alert >= 6 and not bt.boss_dead and randf() < 0.4:
		calls += 1
	if calls and not bt.boss_dead and bt.mission_idx == 0 and not bt.breach and not bt.T.ceiling:
		await plane_drop(1 + bt.alert / 4)  # E3: the Jackals' own backup comes by plane
		calls = 0
	if calls and not bt.boss_dead:
		var n := 1 + bt.alert / 4
		var shields := 0
		for i in n:
			var drop: Array = ["grunt", "grunt", "shield", "sapper"] if bt.mission_idx == 0 else ["skitter", "blinker", "shield", "sapper"]
			if shields > 0:
				drop.erase("shield")  # one riot shield per drop, so a stall doesn't wall the screen with them
			var type: String = bt.pick(drop)
			if type == "shield":
				shields += 1
			var e := bt.mk_enemy(type, bt.cam_x + bt.W - 60 - randf() * 240, -30.0 - i * 40)
			e.active = true; e.heavy = false; e.air = true; e.para = true
			if bt.T.ceiling:
				# M4: no sky to drop from, so they come up the tunnel from the far end
				var ey = bt.T.stand_y(e.x, bt.T.ceil_at(e.x) + 12)
				e.y = ey if ey != null else bt.T.ground_at(e.x)
				e.para = false
			bt.units.append(e)
		bt.banner("REINFORCEMENTS!", Color("ff7a3d"))
		bt.log_msg("Paratroopers dropping in. Shoot them on the way down, and get the radioman next time.")
		await bt.wait(40)
	if bt.alert >= 10:
		var tg := bt.squad_alive()
		tg.shuffle()
		for s in tg.slice(0, 2):
			bt.strikes.append({"x": s.x + bt.ri(-16, 16), "owner": null})
		bt.banner("AIRSTRIKE INBOUND", Color("ff4d3d"), "MOVE OFF THE MARKERS")
		Sfx.play("alarm")
		await bt.wait(40)
	await bt.biome_rules.biome_round()
	await bt.mid_events.crumble_round()
	bt.spec_kits.classes_enemy_end()
	await bt.vehicle_ops.leg_check()
	if bt.squad_alive().is_empty():
		bt.game_over()
		return
	await unstack_squad()
	bt.start_player_turn()

func unstack_squad() -> void:
	## Q4: two squadmates parked on one spot (a recoil, a blast, a fall): the one that isn't selected
	## steps aside to the nearest free spot, so nobody hides behind a teammate. The step is free.
	for _pass in 4:
		var sq := bt.squad_alive().filter(func(o): return not o.air and o.walk == null and o.zip == null and o.drill == null and o.mech == null and not o.hang and not o.sunk)
		var moved := false
		for a in sq:
			for c in sq:
				if moved or a.id >= c.id or absf(a.x - c.x) >= 10 or absf(a.y - c.y) >= 20:
					continue
				var mover: Unit = a if c == bt.sel else c
				for d in [16.0, -16.0, 32.0, -32.0, 48.0, -48.0]:
					var nx: float = mover.x + d
					if nx < bt.cam_x + 14 or nx > bt.cam_x + bt.W - 14:
						continue
					var sim := bt.phys.sim_walk(mover, nx, absf(d) + 8)
					if sim.pts.is_empty() or absf(sim.x - nx) > 3 or absf(sim.y - mover.y) > 24 or bt.biome_rules.mine_under(mover, sim.x, sim.y, 6) != null:
						continue
					if sq.any(func(o): return o != mover and absf(o.x - sim.x) < 10 and absf(o.y - sim.y) < 20):
						continue
					await bt.phys.walk_along(mover, sim.pts)
					moved = true
					break
		if not moved:
			return

func best_shot(e: Unit, targets: Array, rng: float):
	var best = null
	if Run.intel == "fog" or Run.intel == "blizzard":
		rng *= 0.7
	rng *= bt.rules.get("sight", 1.0)
	for tg in targets:
		if tg.team == "squad" and not bt.targetable(e, tg):
			continue
		var d := bt.dist(e, tg)
		if d > rng:
			continue
		var vis := bt.visibility(e, tg)
		if not vis:
			continue
		var sc: float = vis * 30 - d / 10 + (-10 if tg.armor else 0) + (tg.max_hp - tg.hp) * 0.5 + (500 if tg == bt.taunter else 0) + (300 if bt.hunted(tg) else 0)
		if best == null or sc > best.sc:
			best = {"t": tg, "vis": vis, "sc": sc}
	return best

func enemy_shoot(e: Unit, tg: Unit, spec: Dictionary) -> void:
	e.st.erase("cloak")
	if await bt.spec_kits.guard_tackle(e, tg):
		return
	var shots: int = spec.get("shots", 1)
	for s in shots:
		if tg.dead or e.dead:
			break
		e.face = 1 if tg.x >= e.x else -1
		var m := bt.muzzle(e)
		var pts := bt.visible_points(m.x, m.y, tg)
		var py: float = bt.pick(pts) if pts.size() else tg.y - tg.h / 2.0
		var err := maxf(0.015, 0.075 - (10 if e.elite == "veteran" else bt.alert) * 0.005) + tg.dodge * 0.002
		if tg.has_st("roll"):
			# J3: the soldier tucked into a roll; this one goes over their head
			tg.st.erase("roll")
			py = tg.y - tg.h - 16
			err = 0.0
			bt.float_text(tg, "ROLLED UNDER", Color("e8dcc2"))
		var ang := atan2(py - m.y, tg.x - m.x) + bt.gauss() * err
		if e.type == "boss":
			e.aim_a = clampf(atan2(-(py - m.y), -(tg.x - m.x)), -0.4, 0.6)
		e.gun_target = atan2(sin(ang), cos(ang) * e.face)
		Sfx.play("mg" if shots > 1 else "shot")
		e.muzzle = 4
		e.muzzle_kind = "mg" if shots > 1 else "shot"
		e.pose = "recoil"; e.pose_t = 6
		bt.fire_bullet(e, m.x, m.y, ang, {"dmg": spec.dmg, "range": spec.get("range", 460) + 240, "bounce": 0}, false)
		await bt.wait(7 if shots > 1 else 14)

func overwatch_check(e: Unit) -> void:
	if e.fl.has("mind"):
		return
	for s in bt.squad_alive():
		if s.overwatch <= 0 or e.dead:
			continue
		if bt.dist(s, e) <= 520 and bt.visibility(s, e) > 0:
			s.overwatch -= 1
			bt.float_text(s, "OVERWATCH!", Color("53d4e2"), true)
			await bt.wait(10)
			s.face = 1 if e.x >= s.x else -1
			var m := bt.muzzle(s)
			var pts := bt.visible_points(m.x, m.y, e)
			var py: float = pts[0] if pts.size() else e.y - e.h / 2.0
			var ang := atan2(py - m.y, e.x - m.x) + bt.gauss() * 0.02
			s.gun_target = atan2(sin(ang), cos(ang) * s.face)
			Sfx.play("shot")
			s.muzzle = 4
			s.muzzle_kind = "shot"
			var oc := Data.card("rifle")
			oc["forcehead"] = s.fl.get("ow_crit", false)
			oc["boomhit"] = bt.ks(s, "claymore")
			bt.fire_bullet(s, m.x, m.y, ang, oc, s.adr >= 50)
			await bt.wait(16)

func enemy_advance(e: Unit, tx: float, budget: float, stop = null) -> void:
	## walk toward tx; vault walls up to 64px, leap gaps over water, brutes smash through.
	var E: Dictionary = Data.ETYPES[e.type]
	if e.has_st("supp"):
		budget *= 0.5
	var left := budget
	var k := 0
	while k < 5 and left > 6 and not e.dead and not e.air:
		k += 1
		var sim := bt.phys.sim_walk(e, tx, left)
		var pts: Array = sim.pts
		var cut := false
		if stop != null:
			var i := 0
			while i < pts.size():
				var ox := e.x
				var oy = e.y
				e.x = pts[i][0]
				e.y = pts[i][1]
				var ok: bool = stop.call()
				e.x = ox
				e.y = oy
				if ok:
					pts = pts.slice(0, i + 1)
					cut = true
					break
				i += 5
		await bt.phys.walk_along(e, pts)
		left -= pts.size() * 2
		await overwatch_check(e)
		if e.dead or cut:
			return
		if absf(e.x - tx) < 6 or left <= 6:
			return
		var dir := int(signf(tx - e.x))
		var ax := e.x + dir * 6
		if not bt.T.solid(ax, e.y + 2):
			# a drop we would not walk into: water or a pit. leap it if there is ground within reach
			var land = null
			var d := 28
			while d <= 116:
				var y = bt.T.stand_y(e.x + dir * d, maxf(0, e.y - 60))
				if y != null and y < bt.WATER_Y - 4 and y > e.y - 50:
					land = d
					break
				d += 4
			if land == null:
				return
			e.face = dir
			e.vx = dir * land / 46.0
			e.vy = -5
			e.air = true
			e.leaping = true
			bt.float_text(e, "JUMP", Color("e8dcc2"))
			await bt.until(func(): return not e.air or e.dead or e.sunk or e.gone)
			left -= land
			continue
		var top = null
		var hh := 4
		while hh <= 140:
			if not bt.T.solid(ax, e.y - hh):
				var room := true
				var yy: float = e.y - hh - e.h + 2
				while yy < e.y - hh:
					if bt.T.solid(ax, yy):
						room = false
						break
					yy += bt.CELL
				if room:
					top = hh
					break
			hh += 4
		if top != null and top <= (140 if E.get("climb", false) else 64):
			e.face = dir
			e.vx = 0
			e.vault = {"y": e.y - top - 3, "vx": dir * 1.8}
			e.vy = -sqrt(2 * bt.grav * (top + 18))
			e.air = true
			e.leaping = true
			await bt.until(func(): return not e.air or e.dead or e.sunk or e.gone)
			left -= top + 20
			continue
		if E.get("smash", false):
			e.face = dir
			bt.float_text(e, "SMASH!", Color("ff7a3d"), true)
			Sfx.play("thud")
			bt.shake += 4
			e.pose = "throw"; e.pose_t = 14
			await bt.wait(10)
			bt.T.carve(e.x + dir * 16, e.y - e.h * 0.3, 16, e)
			bt.T.carve(e.x + dir * 16, e.y - e.h * 0.8, 16, e)
			await bt.until(bt.settled)
			left -= 30
			continue
		return

func lob(e: Unit, tg: Unit, dmg: int, r: float, err_mul: float) -> bool:
	e.st.erase("cloak")
	e.face = 1 if tg.x >= e.x else -1
	var sx := e.x + e.face * 6
	var sy := e.y - e.h + 6
	var sol = bt.phys.solve_arc(sx, sy, tg.x, tg.y - 4, 1, 13)
	if sol == null:
		return false
	var err := maxf(0.025, 0.11 - bt.alert * 0.009) * err_mul
	var k := 1 + (randf() - .5) * err * 2
	var ang := (randf() - .5) * err
	var c := cos(ang)
	var s := sin(ang)
	e.pose = "throw"; e.pose_t = 24
	await bt.wait(8)
	Sfx.play("toss")
	var cl := 0
	if e.has_st("cluster"):
		cl = 3
		e.st.cluster -= 1
		if e.st.cluster <= 0:
			e.st.erase("cluster")
	bt.projs.append(bt.phys.mk_proj({"kind": "egren", "x": sx, "y": sy, "vx": (sol.vx * c - sol.vy * s) * k, "vy": (sol.vx * s + sol.vy * c) * k, "wind": 1.0, "r": r, "dmg": int(round(dmg * (1 + bt.alert * 0.06))), "owner": e, "cluster": cl}))
	await bt.wait(6)
	return true

func jet_roost(e: Unit):
	## J5: the highest roof a Jet Jackal can reach this turn, on screen, nearest first on a tie.
	var reach: float = Data.ETYPES[e.type].jet
	var best = null
	var x := e.x - reach
	while x <= e.x + reach:
		if x > bt.cam_x + 30 and x < bt.cam_x + bt.W - 30:
			var y = bt.T.stand_y(x, 0)
			var yl = bt.T.stand_y(x - 8, 0)
			var yr = bt.T.stand_y(x + 8, 0)
			var flat: bool = y != null and yl != null and yr != null and absf(yl - y) <= 4 and absf(yr - y) <= 4
			if flat and y < bt.WATER_Y - 8 and not bt.units.any(func(o): return o != e and not o.dead and not o.gone and o.team != "neutral" and absf(o.x - x) < 14 and absf(o.y - y) < 20):
				if best == null or y < best.y - 6 or (absf(y - best.y) <= 6 and absf(x - e.x) < absf(best.x - e.x)):
					best = Vector2(x, y)
		x += 12
	return best

func jet_fly(e: Unit, dest: Vector2) -> void:
	## Burn up above the roof, drift over and drop onto it. Hit in flight and the pack cuts out.
	e.jetting = true
	e.walk = null
	e.air = true
	e.face = 1 if dest.x >= e.x else -1
	Sfx.play("rocket", -6)
	var over := false
	for f in 300:
		await bt.wait(1)
		if e.dead or not e.jetting:
			break
		# climb to just above the roof first, then slide over and settle onto it
		var ty: float = dest.y - 40
		var want_vy := clampf((ty - e.y) * 0.08, -3.5, 2.0)
		var want_vx := 0.0
		if e.y < dest.y - 20 or absf(e.x - dest.x) < 40:
			want_vx = clampf((dest.x - e.x) * 0.06, -3.0, 3.0)
		e.vx = move_toward(e.vx, want_vx, 0.35)
		e.vy = move_toward(e.vy, want_vy, 0.35) - bt.grav  # the pack cancels gravity while it burns
		e.air = true
		if absf(e.x - dest.x) < 3 and absf(e.y - ty) < 12:
			over = true
			e.x = dest.x
			break
		if bt.t % 2 == 0:
			bt.part({"x": e.x - e.face * 6, "y": e.y - 12, "vx": (randf() - .5) * 0.6, "vy": 1.6 + randf(), "life": 14, "max": 14, "c": bt.pick([Color("ffd23a"), Color("ff7a3d")]), "s": 2.0, "g": 0.0, "fire": true})
		if f % 24 == 12:
			await overwatch_check(e)
	if e.jetting and not e.dead:
		e.jetting = false
		if over:
			e.vx = 0.0
			e.vy = 0.0
	await bt.until(func(): return not e.air or e.dead or e.sunk or e.gone)

func jetter_act(e: Unit) -> void:
	var E: Dictionary = Data.ETYPES[e.type]
	var r = jet_roost(e) if not e.hold else null
	if r != null and r.y < e.y - 24:
		bt.float_text(e, "JETS!", Color("53d4e2"))
		await jet_fly(e, r)
	elif not e.hold:
		var tg = bt.nearest_squad(e)
		if tg != null:
			await enemy_advance(e, tg.x + (E.prefer * 0.5 if tg.x < e.x else -E.prefer * 0.5), E.speed)
	if e.dead or e.air:
		return
	var best = best_shot(e, bt.foes_of(e), E.range)
	if best != null:
		await bt.wait(6)
		await enemy_shoot(e, best.t, E)

func jackal_nade(e: Unit) -> bool:
	## A Jackal that grabbed a grenade kit throws it at the nearest soldier.
	if not e.st.has("nades") or bt.faction(e) != "jackal":
		return false
	var tg = bt.nearest_squad(e)
	if tg == null or absf(tg.x - e.x) > 420:
		return false
	e.st.erase("nades")
	bt.float_text(e, "FIRE IN THE HOLE!", Color("ff7a3d"))
	return await lob(e, tg, 11, 36, 1.0)

func engineer_build(e: Unit) -> bool:
	var tg = bt.nearest_squad(e)
	if tg == null:
		return false
	var dir := int(signf(tg.x - e.x))
	if dir == 0:
		dir = -1
	var bx := e.x + dir * 22
	var g = bt.T.stand_y(bx, e.y - 40)
	if g == null or absf(g - e.y) > 12:
		return false
	var y: float = g - 20
	while y < g:
		if bt.T.solid(bx, y):
			return false  # already walled
		y += 4
	e.face = dir
	bt.float_text(e, "BUILDING", Color("d6a02f"))
	Sfx.play("thud")
	e.pose = "throw"; e.pose_t = 16
	await bt.wait(16)
	bt.T.fill_r(bx - 8, g - 20, 16, 24, 2)
	bt.dust(bx, g - 10, Color("c9c2b0"), 8)
	for u in bt.units:
		if u.dead or u.gone:
			continue
		var k := 0
		while bt.T.solid(u.x, u.y - 2) and k < 8:
			u.y -= bt.CELL
			k += 1
	e.built = 2
	return true

func enemy_act(e: Unit) -> void:
	var E: Dictionary = Data.ETYPES[e.type]
	var sq := bt.foes_of(e)
	if sq.is_empty() or e.air:
		return
	if e.type == "boss":
		await bt.vharr_ai.boss_act(e)
		return
	if e.type == "hiveship":
		await bt.vharr_ai.hiveship_act(e)
		return
	if e.type == "shipplate":
		return
	if e.type == "droppod":
		await bt.vharr_ai.droppod_act(e)
		return
	if e.type == "vgate":
		await vgate_act(e)
		return
	if await bt.vharr_ai.surrender(e):
		return
	if e.type == "gatetrooper":
		await bt.vharr_ai.trooper_act(e)
		return
	if await jackal_nade(e):
		return
	# only rank-and-file shooters run for a pad: the follow-up below is a plain rifle shot, and a
	# Flametrooper's or Di-Cokka's single dmg number isn't a rifle's [min, max] (it crashed the shot)
	var grabs: bool = not e.hold and E.get("speed", 0) > 0 and not E.get("static", false) and E.get("dmg") is Array
	var pad = bt.pad_in_reach(e, E.get("speed", 0)) if grabs else null
	if pad != null:
		# a bonus is up within reach: grab it, then shoot if there is a shot
		bt.float_text(e, "GRAB IT!", Color("ff7a3d"))
		await enemy_advance(e, pad.x, E.speed)
		if e.dead or e.air:
			return
		if await jackal_nade(e):
			return
		if E.has("range") and not E.get("melee", false) and not E.get("arc", false):
			var b3 = best_shot(e, bt.squad_alive(), E.range)
			if b3 != null:
				await bt.wait(6)
				await enemy_shoot(e, b3.t, E)
		return
	if e.elite == "hungry":
		await bt.vharr_ai.eat_body(e)
	if Data.ETYPES[e.type].get("wall", false) and await wall_act(e):
		return
	match e.type:
		"jsniper":
			await sniper_act(e)
			return
		"flamer":
			await flamer_act(e)
			return
		"jdog":
			await bt.vharr_ai.skitter_act(e)
			return
		"gunship":
			await gunship_act(e)
			return
		"dicokka":
			await dicokka_act(e)
			return
		"hive":
			await bt.vharr_ai.hive_act(e)
			return
		"burrow":
			await bt.vharr_ai.burrow_act(e)
			return
		"skitter":
			await bt.vharr_ai.skitter_act(e)
			return
		"squid":
			await bt.vharr_ai.squid_act(e)
			return
		"blinker":
			await bt.vharr_ai.blinker_act(e)
			return
		"burrower":
			await bt.vharr_ai.burrower_act(e)
			return
		"prism":
			await bt.vharr_ai.prism_act(e)
			return
		"queen":
			await bt.vharr_ai.queen_act(e)
			return
		"warden":
			await bt.vharr_ai.warden_act(e)
			return
		"stalker":
			await bt.vharr_ai.stalker_act(e)
			return
		"overseer":
			await bt.vharr_ai.overseer_act(e)
			return
		"grappler":
			await bt.vharr_ai.grappler_act(e)
			return
		"bloater":
			await bt.vharr_ai.bloater_act(e)
			return
		"weaver":
			await bt.vharr_ai.weaver_act(e)
			return
	if E.get("sapper", false):
		var tg = bt.nearest_squad(e)
		if tg == null:
			return
		if absf(tg.x - e.x) > 60:
			await enemy_advance(e, tg.x + (40 if tg.x < e.x else -40), E.speed)
		if e.dead or e.air:
			return
		var t2 = bt.nearest_squad(e)
		if t2 != null and absf(t2.x - e.x) <= 90 and not e.planted:
			var dir := int(signf(t2.x - e.x))
			if dir == 0:
				dir = -1
			var cx := e.x + dir * 10
			var cy = bt.T.stand_y(cx, e.y - 30)
			if cy != null:
				e.planted = true
				bt.float_text(e, "CHARGE SET", Color("ff4d3d"), true)
				Sfx.play("tick")
				var ch := bt.mk_unit()
				ch.team = "neutral"; ch.kind = "charge"; ch.x = cx; ch.y = cy; ch.w = 14; ch.h = 12
				bt.units.append(ch)
				bt.log_msg("A sapper planted a charge. It blows when the Jackals move next. Shoot it to defuse.")
				await bt.wait(14)
				await enemy_advance(e, e.x - dir * 70, 70)
		return
	if E.get("radio", false):
		var tg = bt.nearest_squad(e)
		if tg == null:
			return
		if absf(tg.x - e.x) < 240 and not e.hold:
			await enemy_advance(e, e.x + (90 if e.x >= tg.x else -90), E.speed)
		if e.dead or e.air:
			return
		var b = best_shot(e, bt.foes_of(e), E.range)
		if b != null:
			await bt.wait(6)
			await enemy_shoot(e, b.t, E)
		return
	if E.get("melee", false):
		var tg = bt.nearest_squad(e)
		if tg == null:
			return
		if absf(tg.x - e.x) > 26:
			await enemy_advance(e, tg.x + (20 if tg.x < e.x else -20), E.speed)
		if e.dead or e.air:
			return
		var tt = null
		for s in bt.foes_of(e):
			if absf(s.x - e.x) <= 32 and absf(s.y - e.y) <= 26:
				tt = s
				break
		if tt != null:
			e.face = 1 if tt.x >= e.x else -1
			e.pose = "throw"; e.pose_t = 16
			Sfx.play("slash")
			bt.spec_kits.slash_fx(tt.x, tt.y - tt.h / 2.0, 1.6, e.face)
			await bt.wait(8)
			if randf() * 100 < clampf(E.acc + bt.alert * 2 - tt.dodge, 10, 95):
				bt.damage(tt, int(round(bt.ri(E.dmg[0], E.dmg[1]) * (1 + bt.alert * 0.06))), e, {})
				if not tt.dead:
					tt.vx = e.face * 6; tt.vy = -3.5; tt.air = true; tt.walk = null; tt.bumped = null; tt.last_hit_by = e
			else:
				bt.float_text(tt, "DODGED", Color("9aa4b0"))
		return
	if E.get("arc", false):
		var cands := sq.filter(func(s): return absf(s.x - e.x) <= E.range and not s.has_st("cloak"))
		if not e.hold and E.speed:
			var tg = bt.nearest_squad(e)
			if tg == null:
				return
			await enemy_advance(e, tg.x, E.speed, func(): return bt.foes_of(e).any(func(s): return absf(s.x - e.x) <= E.range * 0.9))
			if e.dead or e.air:
				return
			cands = bt.foes_of(e).filter(func(s): return absf(s.x - e.x) <= E.range and not s.has_st("cloak"))
		if cands.is_empty():
			return
		var best = null
		var bsc := -1e9
		for s in cands:
			var sc: float = bt.foes_of(e).filter(func(o): return absf(o.x - s.x) < 45).size() * 10 - s.hp * 0.3
			if sc > bsc:
				bsc = sc
				best = s
		await lob(e, best, E.dmg, E.radius, 1.6 if E.get("heavyArc", false) else 1.0)
		return
	if E.get("jet", 0) > 0:
		await jetter_act(e)
		return
	var gun = bt.m2_near(e) if bt.faction(e) == "jackal" and E.has("range") and not E.get("static", false) else null
	if gun != null and gun.loot.en != bt.round_n:
		var bm = best_shot(e, bt.foes_of(e), 600)
		if bm != null:
			gun.loot.en = bt.round_n
			bt.float_text(e, "ON THE M2!", Color("ff4d3d"))
			await bt.wait(6)
			await enemy_shoot(e, bm.t, {"dmg": [3, 4], "shots": 5, "range": 560})
			return
	if E.get("builds", false):
		if e.built > 0:
			e.built -= 1
		elif await engineer_build(e):
			await bt.until(bt.settled)
	var best = best_shot(e, sq, E.range)
	if not E.get("static", false) and not e.hold:
		# Worms style: always move, then shoot. Close in until there's a shot from preferred range,
		# but take at least a few steps every turn.
		var tg = bt.nearest_squad(e)
		if tg == null:
			return
		var x0 := e.x
		await enemy_advance(e, tg.x + (E.prefer * 0.5 if tg.x < e.x else -E.prefer * 0.5), E.speed, func():
			if absf(e.x - x0) < 40:
				return false
			var b2 = best_shot(e, sq, E.range)
			return b2 != null and absf(b2.t.x - e.x) <= E.prefer)
		if e.dead or e.air:
			return
		best = best_shot(e, bt.foes_of(e), E.range)
	if best != null:
		await bt.wait(6)
		await enemy_shoot(e, best.t, E)
	elif E.has("nade") and not e.dead and randf() < E.nade:
		var near := bt.foes_of(e).filter(func(s): return absf(s.x - e.x) <= 380)
		near.sort_custom(func(a, b): return absf(a.x - e.x) < absf(b.x - e.x))
		if near.size():
			bt.float_text(e, "GRENADE!", Color("ff7a3d"))
			await lob(e, near[0], 7, 28, 1.3)

# ---------------------------------------------------------------- E3 and E6
func alien_pool() -> Array:
	return Data.BIOME_ALIENS.get(bt.mission.get("biome", ""), bt.ALIENS)

func pod_ambush() -> void:
	## E3: three pods crash down around the squad's front. They open next enemy phase.
	bt.ambush.done = true
	bt.banner("DROP POD AMBUSH!", Color("c47bff"), "BREAK THE PODS BEFORE THEY OPEN")
	Sfx.play("alarm")
	await bt.wait(30)
	var sq := bt.squad_alive()
	sq.sort_custom(func(a, b2): return a.x > b2.x)
	var pool: Array = alien_pool().filter(func(k): return Data.ETYPES[k].get("weight", "") != "hover")
	var xs: Array = []
	for k in 3:
		var tg: Unit = sq[k % sq.size()]
		var x: float = clampf(tg.x + randf_range(-40, 40), bt.cam_x + 20, bt.cam_x + bt.W - 20)
		for tries in 8:
			if not xs.any(func(o): return absf(o - x) < 70):
				break
			x = clampf(x + 70, bt.cam_x + 20, bt.cam_x + bt.W - 20) if tries % 2 == 0 else clampf(x - 140, bt.cam_x + 20, bt.cam_x + bt.W - 20)
		xs.append(x)  # spread out, so one pod's blast doesn't crack the next
		var cargo: Array = ["skitter", "skitter"] if k == 0 or pool.is_empty() else [bt.pick(pool)]
		bt.projs.append(bt.phys.mk_proj({"kind": "droppod", "x": x, "y": -40.0 - k * 40, "vx": 0.0, "vy": 6.0, "r": 30.0, "dmg": int(round(7 * (1 + bt.alert * 0.06))), "owner": null, "cargo": cargo}))
		Sfx.play("toss")
		await bt.wait(12)
	await bt.until(bt.settled)
	await bt.wait(10)

func vgate_act(e: Unit) -> void:
	## E6: one alien comes through the gate on the squad's side, until four from it are alive.
	var E: Dictionary = Data.ETYPES.vgate
	if bt.units.filter(func(o): return o.fl.get("from") == e and not o.dead).size() >= E.cap:
		return
	var tg = bt.nearest_squad(e)
	var dir := -1.0 if tg == null or tg.x < e.x else 1.0
	var x: float = e.x + dir * 30
	var y = bt.T.stand_y(x, e.y - 40)
	var c := bt.mk_enemy(bt.pick(alien_pool()), x, y if y != null else e.y)
	c.active = true
	c.fl["from"] = e
	bt.units.append(c)
	bt.place_alien(c)
	bt.float_text(e, "%s COMES THROUGH" % Data.ETYPES[c.type].name.to_upper(), Color("c47bff"), true)
	Sfx.play("power")
	for i in 8:
		bt.part({"x": x, "y": c.y - 20, "vx": (randf() - .5) * 3, "vy": (randf() - .5) * 3, "life": 30, "max": 30, "c": Color("c47bff"), "s": 2.0, "g": 0.0})
	await bt.wait(16)

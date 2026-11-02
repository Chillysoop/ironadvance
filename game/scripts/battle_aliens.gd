class_name BattleAliens
extends RefCounted
## The Vharr: alien turns, the Hive Ship and drop pods, the Boar.
## Split out of battle.gd (R3). Functions only: every piece of mission state lives on the Battle,
## reached through `bt`.

var bt: Battle

func _init(battle: Battle) -> void:
	bt = battle

# ---------------------------------------------------------------- Vharr aliens
# Like the Jackals, every alien moves and attacks in the same enemy phase. Nothing is marked ahead.
func hover_y(u: Unit, x: float, y: float) -> float:
	## Where a hovering alien floats over x: its altitude above the floor below (or the water),
	## lower when a ceiling is in the way.
	var fl = bt.T.stand_y(x, y - 2)
	var floor_y: float = bt.WATER_Y if fl == null else minf(fl, bt.WATER_Y)
	var hy: float = floor_y - Data.ETYPES[u.type].get("alt", 110)
	var cy := floor_y - 4
	while cy > hy - u.h:
		if bt.T.solid(x, cy):
			return minf(floor_y, cy + u.h + 4)
		cy -= bt.CELL
	return hy

func hover_physics(u: Unit) -> void:
	## Hovering: knockback pushes it sideways and it eases back to altitude; no gravity, no fall damage.
	if absf(u.vx) > 0.05:
		var nx := u.x + u.vx
		if bt.T.solid(nx, u.y - u.h * 0.5) or bt.T.solid(nx, u.y - 4):
			var imp := absf(u.vx)
			if imp > 4:
				bt.collision_dmg(u, (imp - 4) * 2.5, "SLAM")
			u.vx *= -0.25
		else:
			u.x = clampf(nx, 4, bt.world_w - 4)
		u.vx *= 0.9
		if not u.dead and Vector2(u.vx, 0).length() >= 3:
			bt.body_collisions(u)
	if u.dead or u.weight != "hover":
		return
	var ty := hover_y(u, u.x, u.y)
	var ny := u.y + clampf((ty - u.y) * 0.15, -3.0, 3.0)
	# only the leading edge has to be clear, so a tank shoved with its top into an overhang can still sink out of it
	var eased := false
	if not bt.T.solid(u.x, ny if ny > u.y else ny - u.h):
		u.y = ny
		eased = true
	# wedged short of its altitude anyway: it has settled where it is, or the action waiting on everything
	# to settle never ends (the playtest's frozen turns)
	u.air = absf(u.vx) > 0.3 or (eased and absf(ty - u.y) > 1.5)
	if not u.air:
		u.vx = 0
		u.vy = 0
		u.bumped = null

func break_pod(u: Unit) -> void:
	## The saucer pod is shot out: the squid drops, takes crash damage on landing, and crawls from now on.
	u.weight = ""
	u.pod = 0
	u.crash = true
	u.air = true
	u.vy = 0.0
	u.walk = null
	bt.float_text(u, "POD DOWN!", Color("c47bff"), true)
	Sfx.play("thud")
	for i in 6:
		bt.part({"x": u.x + (i - 3) * 4, "y": u.y + 2, "vx": (i - 3) * 0.6, "vy": -1.5, "life": 40, "max": 40, "c": Color("9df25c"), "s": 2.0, "g": 0.12})

func hover_move(e: Unit, tx: float, budget: float) -> void:
	## Glide toward tx at altitude, over gaps and water, until a wall is in the way.
	if e.has_st("supp"):
		budget *= 0.5
	var pts: Array = []
	var x := e.x
	var y: float = e.y
	var dir := signf(tx - x)
	for i in int(minf(absf(tx - x), budget) / 2.0):
		var nx := x + dir * 2
		var ny := y + clampf(hover_y(e, nx, y) - y, -3.0, 3.0)
		if bt.T.solid(nx, ny - e.h * 0.5) or bt.T.solid(nx, ny - 4) or bt.T.solid(nx, ny - e.h + 2):
			break
		x = nx
		y = ny
		pts.append([x, y, false])
	await bt.phys.walk_along(e, pts)

func leap_to(e: Unit, p: Vector2) -> void:
	## A fixed hop that always lands on the target spot (the same arc the grapple zip uses).
	e.face = 1 if p.x >= e.x else -1
	e.walk = null
	e.air = true
	e.zip = {"x0": e.x, "y0": e.y, "x1": p.x, "y1": p.y, "t": 0.0}
	await bt.until(func(): return e.zip == null or e.dead)

func skitter_act(e: Unit) -> void:
	## Scramble in close (climbing walls on the way), then pounce on the nearest target and bite.
	## E4 Jackal Hounds hunt the same way and pin whoever they bite.
	var E: Dictionary = Data.ETYPES[e.type]
	var tg = bt.nearest_squad(e)
	if tg == null:
		return
	if Vector2(tg.x - e.x, tg.y - e.y).length() > E.leap * 0.9:
		await bt.foe_ai.enemy_advance(e, tg.x, E.speed, func():
			var t2 = bt.nearest_squad(e)
			return t2 != null and Vector2(t2.x - e.x, t2.y - e.y).length() <= E.leap * 0.9)
	if e.dead or e.air:
		return
	tg = bt.nearest_squad(e)
	if tg == null or Vector2(tg.x - e.x, tg.y - e.y).length() > E.leap:
		return
	Sfx.play("toss")
	await leap_to(e, Vector2(tg.x - signf(tg.x - e.x) * 8, tg.y))
	if e.dead:
		return
	for o in bt.units:
		if o == e or o.dead or o.gone or o.sunk or o.type == e.type or (o.team != "squad" and o.team != "enemy"):
			continue
		if o.team == "enemy" and not bt.at_war(e, o):
			continue
		if absf(o.x - e.x) < 20 + o.w / 2.0 and absf(o.y - e.y) < 30:
			Sfx.play("slash")
			bt.spec_kits.slash_fx(o.x, o.y - o.h / 2.0, 1.0, e.face)
			bt.damage(o, E.dmg, e, {})
			if E.get("pin", false) and o.team == "squad" and not o.dead:
				bt.add_status(o, "pinned", 1, e)

func beam_path(e: Unit, ang: float, rng := -1.0, from = null) -> Dictionary:
	## The squid ray: a straight line that passes through one wall up to 28px thick.
	## Returns {end: Vector2, hits: [Unit]}; everything on the line is hit, Jackals included.
	var R: float = Data.ETYPES.squid.range if rng < 0 else rng
	var o: Vector2 = e.center() if from == null else from
	var dv := Vector2(cos(ang), sin(ang))
	var walls := 0
	var thick := 0.0
	var hits: Array = []
	var d := 8.0
	while d < R:
		var p := o + dv * d
		if p.y > bt.WATER_Y or p.y < -40:
			break
		if bt.T.solid(p.x, p.y):
			thick += 3
			if walls >= 1 or thick > 28:
				return {"end": p, "hits": hits}
		elif thick > 0:
			walls += 1
			thick = 0
		for u in bt.units:
			if u == e or u.dead or u.gone or u.sunk or u.is_pickup() or u.kind == "pow" or hits.has(u) or u.fl.get("ship") == e:
				continue
			if absf(u.x - p.x) < u.w / 2.0 + 1 and p.y > u.y - u.h and p.y < u.y + 1:
				hits.append(u)
		d += 3
	return {"end": o + dv * R, "hits": hits}

func fire_beam(e: Unit, ang: float) -> void:
	var E: Dictionary = Data.ETYPES[e.type]
	var bp := beam_path(e, ang, E.range)
	if bt.debug:
		print("[beam] from ", e.center(), " to ", bp.end, " hits ", bp.hits.map(func(h): return h.team + ":" + h.type))
	var o := e.center()
	e.face = 1 if cos(ang) >= 0 else -1
	Sfx.play("laser")
	e.muzzle = 4
	e.muzzle_kind = "beam"
	if bt.vfx != null:
		bt.vfx.add(SfEnergy.beam(o, bp.end, bt.vfx.ground_fn(bp.end.y), SfEnergy.VHARR, 0.05, 0.12, 2.5))
	else:
		for k in 3:
			bt.tracers.append({"x1": o.x, "y1": o.y + k - 1, "x2": bp.end.x, "y2": bp.end.y + k - 1, "c": Color("c47bff") if k != 1 else Color("9df25c"), "t": 14})
		bt.sparks(bp.end.x, bp.end.y, 5)
	for u in bp.hits:
		bt.damage(u, int(round(E.dmg * (1 + bt.alert * 0.06))), e, {})
	await bt.wait(14)

func trooper_act(e: Unit) -> void:
	## H7 Gate Trooper: walk in to its preferred range like any Jackal, then fire the stolen ray.
	var E: Dictionary = Data.ETYPES.gatetrooper
	var tg = bt.nearest_squad(e)
	if tg == null:
		return
	if not e.hold:
		var x0 := e.x
		await bt.foe_ai.enemy_advance(e, tg.x + (E.prefer if e.x >= tg.x else -E.prefer), E.speed, func():
			return absf(e.x - x0) >= 40 and bt.foe_ai.best_shot(e, bt.foes_of(e), E.range) != null)
	if e.dead or e.air:
		return
	var b = bt.foe_ai.best_shot(e, bt.foes_of(e), E.range)
	if b != null:
		var c := e.center()
		e.face = 1 if b.t.x >= e.x else -1
		e.pose = "recoil"; e.pose_t = 8
		await bt.wait(8)
		await fire_beam(e, atan2(b.t.y - b.t.h / 2.0 - c.y, b.t.x - c.x))

func sign_defector(p: Unit) -> void:
	## F3: a walked-out defector joins the recruit pool and is offered first at the next hire.
	Run.defectors.append(p.pow_name)
	bt.banner("DEFECTOR!", Color("ffd23a"), "%s WANTS TO JOIN THE SQUAD" % p.pow_name)
	bt.log_msg("%s, an ex-Jackal, will be first in line at the next hire. Defector: +3 max HP, +4 dodge." % p.pow_name)
	bt.score += 300
	Sfx.play("coin")

func surrender(e: Unit) -> bool:
	## F3: in a BREACH a cornered Jackal gives up instead of fighting: hurt, alone, with a soldier
	## close. Walk over him like a POW and he signs up as a recruit. One per level.
	if not bt.breach or bt.faction(e) != "jackal" or e.elite != "" or bt.is_thrall(e) or e.fl.get("turned", false) or bt.stats.get("defectors", 0) >= 1:
		return false
	if not e.type in ["grunt", "shield", "sapper", "engineer", "jetter", "gatetrooper"] or e.hp > e.max_hp * 0.4:
		return false
	if not bt.squad_alive().any(func(s): return absf(s.x - e.x) < 180 and absf(s.y - e.y) < 80):
		return false
	if bt.units.any(func(o): return o != e and o.team == "enemy" and o.active and not o.dead and bt.faction(o) == "jackal" and absf(o.x - e.x) < 260):
		return false
	bt.stats["defectors"] = int(bt.stats.get("defectors", 0)) + 1
	var names: Array = Data.CALLSIGNS.filter(func(c): return not Run.soldiers.any(func(s): return s.def.name == c) and not Run.defectors.has(c))
	e.team = "neutral"
	e.kind = "pow"
	e.active = false
	e.walk = null
	e.st.clear()
	e.shield = false
	e.fl["defector"] = true
	e.pow_name = names[randi() % names.size()] if names.size() else "TURNCOAT"
	e.face = -1
	bt.float_text(e, "DON'T SHOOT! I QUIT!", Color("ffd23a"), true)
	bt.log_msg("A cornered Jackal throws down his rifle. Walk him out like a POW and he'll sign up with you.")
	Sfx.play("deny")
	await bt.wait(20)
	return true

func squid_act(e: Unit) -> void:
	## Glide to its preferred range, then fire the ray at the nearest target.
	var E: Dictionary = Data.ETYPES.squid
	var tg = bt.nearest_squad(e)
	if tg == null:
		return
	var want: float = tg.x + (E.prefer if e.x >= tg.x else -E.prefer)
	if absf(want - e.x) > 20 and not e.hold:
		if e.weight == "hover":
			await hover_move(e, want, E.speed)
		else:
			await bt.foe_ai.enemy_advance(e, want, E.speed * 0.5)
	if e.dead or e.air:
		return
	tg = bt.nearest_squad(e)
	if tg != null and bt.dist(e, tg) <= E.range:
		var c := e.center()
		e.face = 1 if tg.x >= e.x else -1
		await bt.wait(8)
		await fire_beam(e, atan2(tg.y - tg.h / 2.0 - c.y, tg.x - c.x))

func rune_spot(e: Unit, tg: Unit):
	## Where the Blinker marks its rune: right behind the soldier (the side away from the Blinker), else in front.
	var dir := -1.0 if e.x >= tg.x else 1.0
	for off in [-30.0, 30.0, -60.0, 60.0]:
		var x: float = tg.x + off * -dir
		var y = bt.T.stand_y(x, tg.y - 40)
		if y != null and y < bt.WATER_Y - 4 and absf(y - tg.y) < 40 and not bt.units.any(func(o): return o != e and not o.dead and not o.gone and not o.is_pickup() and absf(o.x - x) < (o.w + e.w) / 2.0 and absf(o.y - y) < 30):
			return Vector2(x, y)
	return null

func blink(e: Unit, r: Vector2) -> void:
	Sfx.play("warp")
	e.face = 1 if r.x >= e.x else -1
	if bt.vfx != null:
		await teleport(e, r, e.face)
		await bt.wait(4)
		return
	for i in 8:
		bt.part({"x": e.x, "y": e.y - i * 4, "vx": 0.0, "vy": -1.0, "life": 24, "max": 24, "c": Color("c47bff"), "s": 3.0, "g": 0.0})
	e.x = r.x
	e.y = r.y
	e.air = false
	e.vx = 0
	e.vy = 0
	for i in 8:
		bt.part({"x": e.x + (i - 4) * 3, "y": e.y - 16, "vx": (i - 4) * 0.5, "vy": -0.5, "life": 24, "max": 24, "c": Color("9df25c"), "s": 3.0, "g": 0.0})
	await bt.wait(12)

func teleport(u: Unit, to: Vector2, face: int) -> void:
	## V9 blink: the body crackles and comes apart, and is rebuilt at the far spot. The unit is
	## hidden in between and lands when the effect says it has arrived.
	var e := SfMovement.blink(Vector2(u.x, u.y), to, bt.vfx.silhouette(u), bt.vfx.ground_fn(u.y))
	bt.vfx.add(e)
	await bt.wait(e.timing(e.OUT))
	var a0 := u.alpha
	u.alpha = 0.0
	u.x = to.x
	u.y = to.y
	u.vx = 0; u.vy = 0; u.air = false; u.walk = null
	u.face = face
	await bt.wait(e.timing(e.ARRIVE) - e.timing(e.OUT))
	u.alpha = a0

func blinker_act(e: Unit) -> void:
	## Teleport behind the nearest target (within 360px; else walk closer) and claw it.
	var E: Dictionary = Data.ETYPES.blinker
	var tg = bt.nearest_squad(e)
	if tg == null:
		return
	if absf(tg.x - e.x) > 360:
		await bt.foe_ai.enemy_advance(e, tg.x, E.speed)
		return
	var r = rune_spot(e, tg)
	if r == null:
		return
	await blink(e, r)
	if e.dead:
		return
	var tt = null
	for s in bt.foes_of(e):
		if absf(s.x - e.x) <= 34 and absf(s.y - e.y) <= 30:
			tt = s
			break
	if tt != null:
		e.face = 1 if tt.x >= e.x else -1
		e.pose = "throw"; e.pose_t = 16
		Sfx.play("slash")
		bt.spec_kits.slash_fx(tt.x, tt.y - tt.h / 2.0, 1.4, e.face)
		await bt.wait(8)
		bt.damage(tt, int(round(E.dmg * (1 + bt.alert * 0.06))), e, {})
		if not tt.dead and not tt.immovable and not tt.heavy:
			tt.vx = e.face * E.knock * bt.kb(tt); tt.vy = -3.5; tt.air = true; tt.walk = null; tt.bumped = null; tt.last_hit_by = e
		await bt.until(bt.settled)

func burrower_act(e: Unit) -> void:
	## Dive, tunnel up to 300px toward the nearest target digging a trench, and burst out under it.
	var E: Dictionary = Data.ETYPES.burrower
	var tg = bt.nearest_squad(e)
	if tg == null:
		return
	if e.weight != "buried":
		e.weight = "buried"
		bt.dust(e.x, e.y - 4, Color("c9b38a"), 10)
		Sfx.play("thud")
		await bt.wait(10)
	var dir := signf(tg.x - e.x)
	var tx: float = e.x + dir * minf(absf(tg.x - e.x), E.tunnel)
	var dug := 0.0
	while absf(tx - e.x) > 4 and not e.dead:
		var stepx: float = minf(12.0, absf(tx - e.x))
		e.x += dir * stepx
		dug += stepx
		var gy = bt.T.stand_y(e.x, 0)
		if gy != null and gy < bt.WATER_Y - 4:
			e.y = gy
			if dug >= 24:
				dug = 0.0
				bt.T.carve(e.x, gy + 3, 6, e)
				bt.dust(e.x, gy, Color("c9b38a"), 2)
		await bt.wait(2)
	if e.dead:
		return
	var gy2 = bt.T.stand_y(e.x, 0)
	if gy2 != null:
		e.y = gy2
	e.weight = ""
	e.face = int(dir) if dir != 0 else e.face
	e.pose = "throw"; e.pose_t = 16
	Sfx.play("bigboom")
	bt.shake += 6
	bt.T.carve(e.x, e.y - 4, 16, e)
	for o in bt.units:
		if o == e or o.dead or o.gone or o.sunk or o.is_pickup() or o.kind == "pow" or o.team == "neutral":
			continue
		if absf(o.x - e.x) < 30 + o.w / 2.0 and absf(o.y - e.y) < 40:
			bt.damage(o, int(round(E.dmg * (1 + bt.alert * 0.06))), e, {})
			if not o.dead and not o.heavy and not o.immovable:
				o.vx = signf(o.x - e.x if o.x != e.x else 1.0) * 2.5; o.vy = -7; o.air = true; o.walk = null; o.last_hit_by = e
	await bt.until(bt.settled)

func grappler_act(e: Unit) -> void:
	## Tongue the nearest target in a clear line within range and yank it in; bite if it lands close.
	var E: Dictionary = Data.ETYPES.grappler
	var tg = null
	var mouth := Vector2.ZERO
	for o in bt.foes_of(e):
		if Vector2(o.x - e.x, o.y - e.y).length() > E.range or o.heavy or o.immovable:
			continue
		var m := Vector2(e.x + (20 if o.x >= e.x else -20), e.y - 22)
		if not bt.ray_clear(m.x, m.y, o.x, o.y - o.h / 2.0):
			continue
		if tg == null or absf(o.x - e.x) < absf(tg.x - e.x):
			tg = o
			mouth = m
	if tg == null:
		var near = bt.nearest_squad(e)
		if near != null:
			await bt.foe_ai.enemy_advance(e, near.x, E.speed)
		return
	e.face = 1 if tg.x >= e.x else -1
	e.pose = "throw"; e.pose_t = 20
	Sfx.play("slash")
	bt.ropes.append({"x": mouth.x, "y": mouth.y, "u": tg, "t": 40, "c": Color("e05a8a")})
	await bt.wait(12)
	var gap: float = absf(tg.x - e.x) - (e.w + tg.w) / 2.0
	var pull := minf(E.yank, maxf(0.0, gap))
	if pull > 8:
		tg.vx = -e.face * pull / 36.0
		tg.vy = -3.5
		tg.air = true
		tg.walk = null
		tg.bumped = {e.id: true}
		tg.last_hit_by = e
		bt.float_text(tg, "YANKED!", Color("e05a8a"), true)
		await bt.until(func(): return not tg.air or tg.dead or tg.sunk)
	if not tg.dead and absf(tg.x - e.x) < 50 and absf(tg.y - e.y) < 40:
		Sfx.play("slash")
		bt.damage(tg, int(round(E.dmg * (1 + bt.alert * 0.06))), e, {"melee": true})
	await bt.until(bt.settled)

func bloater_act(e: Unit) -> void:
	## Swell, waddle at the nearest target, and pop on it when it gets there.
	var E: Dictionary = Data.ETYPES.bloater
	var sw: int = mini(4, e.fl.get("swell", 0) + 1)
	e.fl["swell"] = sw
	e.w = E.w + sw * 4
	e.h = E.h + sw * 4
	bt.float_text(e, "SWELLS", Color("9df25c"))
	var tg = bt.nearest_squad(e)
	if tg == null:
		return
	if absf(tg.x - e.x) > 34:
		await bt.foe_ai.enemy_advance(e, tg.x, E.speed, func():
			return bt.foes_of(e).any(func(o): return absf(o.x - e.x) < 40 and absf(o.y - e.y) < 40))
	if e.dead or e.air:
		return
	if bt.foes_of(e).any(func(o): return absf(o.x - e.x) < 44 and absf(o.y - e.y) < 40):
		bt.booms.append({"t": 1, "x": e.x, "y": e.y - e.h / 2.0, "r": E.radius + 10.0 * sw, "dmg": E.dmg, "owner": null})
		e.fl["swell"] = -99  # it popped itself: kill() must not pop it again
		bt.kill(e, null)
		await bt.until(bt.settled)

func weaver_act(e: Unit) -> void:
	## Keep its distance, dome the ally nearest your squad, and take a potshot.
	var E: Dictionary = Data.ETYPES.weaver
	var tg = bt.nearest_squad(e)
	if tg == null:
		return
	if not e.hold:
		await bt.foe_ai.enemy_advance(e, tg.x + (E.prefer if e.x >= tg.x else -E.prefer), E.speed)
	if e.dead or e.air:
		return
	var best = null
	for o in bt.units:
		if o == e or o.team != "enemy" or o.dead or not o.active or o.dome > 0 or bt.is_boss(o) or Data.ETYPES[o.type].get("static", false):
			continue
		if absf(o.x - e.x) > 260:
			continue
		if best == null or absf(o.x - tg.x) < absf(best.x - tg.x):
			best = o
	if best != null:
		e.pose = "throw"; e.pose_t = 18
		Sfx.play("power")
		best.dome = 2
		bt.float_text(best, "DOMED", Color("9df25c"), true)
		await bt.wait(14)
	var b = bt.foe_ai.best_shot(e, bt.foes_of(e), E.range)
	if b != null:
		await bt.foe_ai.enemy_shoot(e, b.t, E)

func prism_act(e: Unit) -> void:
	## Drift to its preferred range with the mirror turned on the nearest soldier, then zap.
	var E: Dictionary = Data.ETYPES.prism
	var tg = bt.nearest_squad(e)
	if tg == null:
		return
	var want: float = tg.x + (E.prefer if e.x >= tg.x else -E.prefer)
	if absf(want - e.x) > 20 and not e.hold:
		if e.weight == "hover":
			await hover_move(e, want, E.speed)
		else:
			await bt.foe_ai.enemy_advance(e, want, E.speed * 0.5)
	if e.dead or e.air:
		return
	tg = bt.nearest_squad(e)
	if tg == null:
		return
	e.face = 1 if tg.x >= e.x else -1
	var c := e.center()
	if bt.dist(e, tg) <= E.range and bt.ray_clear(c.x, c.y, tg.x, tg.y - tg.h / 2.0):
		await bt.wait(6)
		Sfx.play("snipe")
		if bt.vfx != null:
			bt.vfx.add(SfEnergy.bolt(c, Vector2(tg.x, tg.y - tg.h / 2.0), bt.vfx.ground_fn(tg.y), SfEnergy.CYAN, 0.0, 2600.0))
		else:
			bt.tracers.append({"x1": c.x, "y1": c.y, "x2": tg.x, "y2": tg.y - tg.h / 2.0, "c": Color("8ff0ff"), "t": 12})
		bt.damage(tg, int(round(E.dmg * (1 + bt.alert * 0.06))), e, {})
		await bt.wait(10)

func warden_act(e: Unit) -> void:
	## Keep its distance, drop the well on the most bunched-up soldiers, and pull everything in it.
	var E: Dictionary = Data.ETYPES.warden
	var tg = bt.nearest_squad(e)
	if tg == null:
		return
	if not e.hold:
		await bt.foe_ai.enemy_advance(e, tg.x + (E.prefer if e.x >= tg.x else -E.prefer), E.speed)
	if e.dead or e.air:
		return
	var best = null
	var best_n := -1
	for s in bt.foes_of(e):
		var n := bt.foes_of(e).filter(func(o): return absf(o.x - s.x) < E.well).size()
		if best == null or n > best_n or (n == best_n and absf(s.x - e.x) < absf(best.x - e.x)):
			best = s
			best_n = n
	if best == null:
		return
	bt.wells = bt.wells.filter(func(q): return q.by != e)
	var well := {"x": best.x, "y": best.y - 20.0, "r": float(E.well), "by": e}
	bt.wells.append(well)
	e.face = 1 if best.x >= e.x else -1
	e.pose = "throw"; e.pose_t = 18
	Sfx.play("power")
	bt.float_at(well.x, well.y - 40, "GRAVITY WELL", Color("c47bff"), true)
	await bt.wait(16)
	await pull_well(well)

func pull_well(w: Dictionary) -> void:
	## Everything loose in the well hops up to its pull toward the center.
	bt.spec_kits.black_hole(w.x, w.y, w.r, 0.15)
	var E: Dictionary = Data.ETYPES.warden
	var moved := false
	for u in bt.units:
		if u.dead or u.gone or u.sunk or u.heavy or u.immovable or u.is_pickup() or u.kind == "pow" or u == w.by:
			continue
		if w.get("foes", false) and u.team != "enemy":
			continue  # the squad's own well only pulls the enemy
		if u.weight == "hover" or u.weight == "buried" or u.type == "boss":
			continue
		var dx: float = w.x - u.x
		if absf(dx) > w.r or absf(u.y - w.y) > w.r or absf(dx) < 10:
			continue
		var pull := minf(float(E.pull), absf(dx) - 6)
		u.vx = signf(dx) * pull / 36.0 * bt.kb(u)
		u.vy = -3.5
		u.air = true
		u.walk = null
		u.bumped = {}
		u.last_hit_by = w.by
		moved = true
	if moved:
		await bt.wait(4)
		await bt.until(bt.settled)

func stalker_act(e: Unit) -> void:
	## The Phase Stalker flips between phased and solid every turn. Phased it walks straight through
	## rock; turning solid inside rock kills it. Either way it slashes whoever it ends up next to.
	var E: Dictionary = Data.ETYPES.stalker
	var phased: bool = not e.fl.get("phased", false)
	e.fl["phased"] = phased
	e.alpha = 0.45 if phased else 1.0
	if not phased and (bt.T.solid(e.x, e.y - e.h * 0.5) or bt.T.solid(e.x, e.y - e.h + 4)):
		bt.float_text(e, "SOLID IN THE ROCK!", Color("ff7a3d"), true)
		Sfx.play("thud")
		bt.damage(e, e.hp, null, {"impact": true})
		return
	bt.float_text(e, "PHASED" if phased else "SOLID", Color("8ff0ff") if phased else Color("c47bff"))
	var tg = bt.nearest_squad(e)
	if tg == null:
		return
	if not e.hold:
		var side := 1.0 if e.x >= tg.x else -1.0
		if phased:
			var tx: float = tg.x + side * 24
			tx = e.x + clampf(tx - e.x, -E.phase_move, E.phase_move)
			var ty = bt.T.stand_y(tx, tg.y - 60)
			if ty == null or ty >= bt.WATER_Y - 4:
				ty = bt.T.stand_y(tx, 0)
			if ty != null and ty < bt.WATER_Y - 4:
				var pts: Array = []
				var n := int(maxf(1, absf(tx - e.x) / 3.0))
				for k in range(1, n + 1):
					pts.append([lerpf(e.x, tx, float(k) / n), lerpf(e.y, ty, float(k) / n), false])
				Sfx.play("power")
				await bt.phys.walk_along(e, pts)
		else:
			await bt.foe_ai.enemy_advance(e, tg.x + side * 24, E.speed)
	if e.dead:
		return
	tg = bt.nearest_squad(e)
	if tg != null and absf(tg.x - e.x) < 44 and absf(tg.y - e.y) < 44:
		e.face = 1 if tg.x >= e.x else -1
		e.pose = "throw"; e.pose_t = 14
		Sfx.play("slash")
		await bt.wait(6)
		bt.damage(tg, int(round(E.dmg * (1 + bt.alert * 0.06))), e, {"melee": true})
		await bt.wait(10)

func overseer_act(e: Unit) -> void:
	## Link up to two Jackals as Thralls, hang back behind them, and lash out at the nearest soldier.
	var E: Dictionary = Data.ETYPES.overseer
	var linked := bt.units.filter(func(o): return o.fl.get("link", -1) == e.id and not o.dead)
	var outbreak: bool = e.fl.get("outbreak", false)
	if linked.size() < E.links or outbreak:
		var free := bt.units.filter(func(o): return o.team == "enemy" and not o.dead and o.active and bt.faction(o) == "jackal" and o.type != "boss" and not o.fl.has("link") and absf(o.x - e.x) < 460)
		free.sort_custom(func(a, b2): return absf(a.x - e.x) < absf(b2.x - e.x))
		for o in free.slice(0, 1 if outbreak else E.links - linked.size()):  # E5: one a turn, all of them in the end
			o.fl["link"] = e.id
			o.fl["thrall"] = true
			bt.float_text(o, "THRALL", Color("9df25c"), true)
			linked.append(o)
		if free.size():
			Sfx.play("power")
			await bt.wait(12)
	var tg = bt.nearest_squad(e)
	if tg == null:
		return
	var away := 1.0 if e.x >= tg.x else -1.0
	var anchor: float = tg.x + away * 320
	if linked.size():
		anchor = linked.map(func(o): return o.x).reduce(func(a, b2): return a + b2, 0.0) / linked.size() + away * 90
	if absf(anchor - e.x) > 20 and not e.hold:
		if e.weight == "hover":
			await hover_move(e, anchor, E.speed)
		else:
			await bt.foe_ai.enemy_advance(e, anchor, E.speed * 0.5)
	if e.dead or e.air:
		return
	tg = bt.nearest_squad(e)
	if tg == null:
		return
	var c := e.center()
	if bt.dist(e, tg) <= E.range and bt.ray_clear(c.x, c.y, tg.x, tg.y - tg.h / 2.0):
		e.face = 1 if tg.x >= e.x else -1
		await bt.wait(6)
		Sfx.play("power")
		for k in 2:
			bt.tracers.append({"x1": c.x, "y1": c.y + k * 2, "x2": tg.x, "y2": tg.y - tg.h / 2.0, "c": Color("ff6ad5") if k else Color("c47bff"), "t": 14})
		bt.damage(tg, int(round(E.dmg * (1 + bt.alert * 0.06))), e, {})
		await bt.wait(10)

func queen_act(e: Unit) -> void:
	## Q2 Burrow Queen. Buried: tunnel toward the nearest soldier, tearing up the ground, and burst out
	## under them. Surfaced: bite whoever is close or spit acid at the nearest, then dive again.
	var E: Dictionary = Data.ETYPES.queen
	var tg = bt.nearest_squad(e)
	if tg == null:
		return
	var dmul := 1 + bt.alert * 0.06
	if e.weight != "buried":
		e.face = 1 if tg.x >= e.x else -1
		e.pose = "throw"; e.pose_t = 18
		if absf(tg.x - e.x) < e.w / 2.0 + 40 and absf(tg.y - e.y) < 60:
			Sfx.play("slash")
			await bt.wait(8)
			bt.damage(tg, int(round(E.bite * dmul)), e, {"melee": true})
		else:
			Sfx.play("splash")
			var c := e.center()
			bt.tracers.append({"x1": c.x, "y1": c.y - 20, "x2": tg.x, "y2": tg.y - 10, "c": Color("9df25c"), "t": 16})
			await bt.wait(10)
			bt.acids.append({"x": tg.x, "y": tg.y, "r": 36.0, "turns": 2})
			bt.damage(tg, int(round(E.spit * dmul)), e, {})
			bt.float_text(tg, "ACID!", Color("9df25c"), true)
		await bt.wait(14)
		if e.dead:
			return
		e.weight = "buried"
		bt.dust(e.x, e.y - 6, Color("c9b38a"), 16)
		Sfx.play("thud")
		bt.shake += 4
		await bt.wait(10)
		return
	var dir := signf(tg.x - e.x)
	var tx: float = e.x + dir * minf(absf(tg.x - e.x), E.tunnel)
	var dug := 0.0
	while absf(tx - e.x) > 4 and not e.dead:
		var stepx: float = minf(10.0, absf(tx - e.x))
		e.x += dir * stepx
		dug += stepx
		var gy = bt.T.stand_y(e.x, 0)
		if gy != null and gy < bt.WATER_Y - 4:
			e.y = gy
			bt.shake = maxf(bt.shake, 2.0)
			if dug >= 30:
				dug = 0.0
				bt.T.carve(e.x, gy + 6, 12, e)  # she leaves the arena torn up behind her
				bt.dust(e.x, gy, Color("c9b38a"), 4)
		await bt.wait(2)
	if e.dead:
		return
	var gy2 = bt.T.stand_y(e.x, 0)
	if gy2 != null:
		e.y = gy2
	e.weight = ""
	e.face = int(dir) if dir != 0 else e.face
	e.pose = "throw"; e.pose_t = 24
	Sfx.play("bigboom")
	bt.shake += 12
	bt.T.carve(e.x, e.y - 6, 30, e)
	bt.float_text(e, "BURROW QUEEN!", Color("c47bff"), true)
	for o in bt.units:
		if o == e or o.dead or o.gone or o.sunk or o.is_pickup() or o.kind == "pow" or o.team == "neutral":
			continue
		if absf(o.x - e.x) < 50 + o.w / 2.0 and absf(o.y - e.y) < 70:
			bt.damage(o, int(round(E.burst * dmul)), e, {})
			if not o.dead and not o.heavy and not o.immovable:
				o.vx = signf(o.x - e.x if o.x != e.x else 1.0) * 3.5; o.vy = -6; o.air = true; o.walk = null; o.bumped = {e.id: true}; o.last_hit_by = e
	await bt.until(bt.settled)

func tick_acids() -> void:
	## End of the enemy phase: anyone but the Vharr standing in Hive acid takes 3.
	for a in bt.acids:
		var mine: bool = a.has("owner")  # Sable's spit only burns the other side
		for u in bt.units:
			if u.dead or u.gone or u.sunk or u.is_prop() or u.is_pickup() or u.kind == "pow" or (bt.faction(u) == "vharr" and not mine):
				continue
			if (mine and u.team != "enemy") or (u.team == "squad" and u.def.key == "sable"):
				continue
			if absf(u.x - a.x) < a.r and absf(u.y - a.y) < 20:
				bt.float_text(u, "ACID", Color("9df25c"))
				bt.damage(u, a.get("dmg", 3), a.get("owner"), {"status": true})
				if mine and a.owner is Unit and a.owner.perk("meltarmor"):
					bt.add_status(u, "toxic", 2, a.owner)
		a.turns -= 1
	bt.acids = bt.acids.filter(func(a): return a.turns > 0)

func spawn_skitter(x: float, y: float) -> Unit:
	Sfx.play("chitter", -6)
	var sy = bt.T.stand_y(x, y - 40)
	var k := bt.mk_enemy("skitter", x, sy if sy != null else y)
	k.active = true
	bt.units.append(k)
	return k

func hive_act(e: Unit) -> void:
	## Hive Pod (E2): counts down in plain sight, then hatches Skitters that act next phase.
	var E: Dictionary = Data.ETYPES.hive
	var n: int = e.fl.get("hatch", E.hatch) - 1
	if n > 0:
		e.fl["hatch"] = n
		return
	e.fl["hatch"] = E.hatch
	if bt.units.filter(func(o): return o.type == "skitter" and not o.dead and absf(o.x - e.x) < 400).size() >= 8:
		return  # the nest is full; it waits for room
	bt.float_text(e, "HATCH!", Color("9df25c"), true)
	Sfx.play("splash")
	for k in E.brood:
		spawn_skitter(e.x + (k * 2 - 1) * 22, e.y)
	await bt.wait(16)

func burrow_act(e: Unit) -> void:
	## Skitter tunnel (E1): one wave per enemy phase, the next wave's size shown over it, then it caves in.
	var E: Dictionary = Data.ETYPES.burrow
	var i: int = e.fl.get("wave", 0)
	if i >= E.waves.size():
		bt.float_text(e, "CAVED IN", Color("e8dcc2"), true)
		bt.dust(e.x, e.y - 4, Color("c9b38a"), 10)
		e.dead = true
		e.hp = 0
		return
	bt.float_text(e, "SWARM!", Color("9df25c"), true)
	Sfx.play("scream", -8)
	for k in E.waves[i]:
		spawn_skitter(e.x - 20 + k * 14, e.y)
		await bt.wait(4)
	e.fl["wave"] = i + 1
	await bt.wait(10)

# ---------------------------------------------------------------- Q1 Hive Ship and drop pods
func hang_plates(sh: Unit) -> void:
	## Two hull plates hang on tethers under the ship's belly.
	for dx in [-48.0, 48.0]:
		var p := bt.mk_enemy("shipplate", sh.x + dx, sh.y + 16)
		p.fl["ship"] = sh
		p.fl["dx"] = dx
		p.immovable = true
		bt.units.append(p)

func ship_plated(sh: Unit) -> bool:
	return bt.units.any(func(o): return o.type == "shipplate" and not o.dead and o.fl.get("ship") == sh)

func drop_plate(p: Unit, src) -> void:
	## A plate shot off its tethers falls like a girder and crushes whatever is under it.
	p.gone = true
	Sfx.play("thud")
	bt.float_text(p, "PLATE FALLS!", Color("ffd23a"), true)
	var cells: Array = []
	var cx0 := int(floor((p.x - p.w / 2.0) / bt.CELL))
	var cy0 := int(floor((p.y - p.h) / bt.CELL))
	for ry in int(p.h / bt.CELL):
		for rx in int(p.w / bt.CELL):
			cells.append([cx0 + rx, cy0 + ry, 2, 0])
	var c = bt.T.chunk_from_cells(cells, src if src is Unit and src.team == "squad" else null)
	if c != null and p.fl.get("ship") != null:
		c.hit[p.fl.ship.id] = true
	var sh = p.fl.get("ship")
	if sh != null and not sh.dead and not ship_plated(sh):
		bt.banner("HULL EXPOSED!", Color("ffb23e"), "THE HIVE SHIP TAKES +30% DAMAGE")

func hiveship_act(e: Unit) -> void:
	## Glide over the squad, sweep the ray across the ground under the nearest soldier, then drop
	## a pod of Vharr (two when it's below half health).
	var E: Dictionary = Data.ETYPES.hiveship
	var tg = bt.nearest_squad(e)
	if tg == null:
		return
	var want: float = tg.x + (70.0 if e.x >= tg.x else -70.0)
	if absf(want - e.x) > 20:
		await hover_move(e, want, E.speed)
	if e.dead:
		return
	tg = bt.nearest_squad(e)
	if tg != null:
		await ship_sweep(e, tg)
	var n := 2 if e.hp < e.max_hp / 2 else 1
	for k in n:
		if e.dead or bt.squad_alive().is_empty():
			return
		var vh := bt.units.filter(func(o): return o.team == "enemy" and not o.dead and bt.faction(o) == "vharr" and not Data.ETYPES[o.type].get("static", false) and not bt.is_boss(o) and absf(o.x - e.x) < 700)
		if vh.size() >= 8:
			break  # the arena is full; it holds the rest back
		await ship_pod(e, bt.pick(bt.squad_alive()))

func ship_sweep(e: Unit, tg: Unit) -> void:
	## The ray drags across the ground from one side of the target to the other. It goes through
	## one thin wall like the Squid's, and hits each body on its path once.
	var E: Dictionary = Data.ETYPES.hiveship
	var o := Vector2(e.x, e.y - 4)
	var dir := 1.0 if tg.x >= e.x else -1.0
	var x0: float = tg.x - dir * E.sweep / 2.0
	var hit := {}
	var dmg := int(round(E.beam * (1 + bt.alert * 0.06)))
	Sfx.play("snipe")
	for k in 9:
		var gx: float = x0 + dir * E.sweep * k / 8.0
		var gy = bt.T.stand_y(gx, o.y + 20)
		var ang := atan2((gy if gy != null else float(bt.WATER_Y)) - 6 - o.y, gx - o.x)
		var bp := beam_path(e, ang, E.beam_range, o)
		for j in 3:
			bt.tracers.append({"x1": o.x, "y1": o.y + j - 1, "x2": bp.end.x, "y2": bp.end.y + j - 1, "c": Color("c47bff") if j != 1 else Color("9df25c"), "t": 8})
		bt.sparks(bp.end.x, bp.end.y, 2)
		for u in bp.hits:
			if not hit.has(u.id):
				hit[u.id] = true
				bt.damage(u, dmg, e, {})
		await bt.wait(4)
	await bt.wait(10)

func ship_pod(e: Unit, tg: Unit) -> void:
	## A drop pod falls from the belly toward a soldier, crashes in with a blast and lands full of Vharr.
	var E: Dictionary = Data.ETYPES.hiveship
	var pool: Array = Data.BIOME_ALIENS.get(bt.mission.get("biome", ""), bt.ALIENS).filter(func(k): return Data.ETYPES[k].get("weight", "") != "hover")
	var cargo: Array = ["skitter", "skitter"] if randf() < 0.5 or pool.is_empty() else [bt.pick(pool)]
	var sx := e.x + randf_range(-20, 20)
	var sy := e.y + 4
	var tf := sqrt(2.0 * maxf(20.0, tg.y - sy) / bt.grav)
	var vx := clampf((tg.x + randf_range(-30, 30) - sx) / tf, -4.0, 4.0)
	bt.float_text(e, "POD DROP!", Color("c47bff"), true)
	Sfx.play("toss")
	bt.projs.append(bt.phys.mk_proj({"kind": "droppod", "x": sx, "y": sy, "vx": vx, "vy": 0.0, "r": 30.0, "dmg": int(round(E.pod_dmg * (1 + bt.alert * 0.06))), "owner": e, "cargo": cargo}))
	await bt.until(bt.settled)
	await bt.wait(8)

func land_pod(x: float, y: float, cargo: Array) -> void:
	## Where a drop pod comes to rest, closed. Over water it sinks with everything inside.
	var gy = bt.T.stand_y(x, y - 30)
	if gy == null or gy >= bt.WATER_Y - 4:
		bt.splash(x)
		return
	var u := bt.mk_enemy("droppod", x, gy)
	u.active = true
	u.fl["cargo"] = cargo
	bt.units.append(u)

func droppod_act(e: Unit) -> void:
	## The pod opens and what's inside comes out swinging, all in this same phase.
	var cargo: Array = e.fl.get("cargo", ["skitter"])
	bt.float_text(e, "POD OPENS!", Color("9df25c"), true)
	Sfx.play("splash")
	e.dead = true
	e.gone = true
	for i in 6:
		bt.part({"x": e.x + (i - 3) * 4, "y": e.y - 14, "vx": (i - 3) * 0.7, "vy": -2.0, "life": 40, "max": 40, "c": Color("9df25c"), "s": 2.0, "g": 0.12})
	var out: Array = []
	for k in cargo.size():
		var cx: float = e.x + (0.0 if cargo.size() == 1 else (k * 2 - 1) * 14.0)
		var cy = bt.T.stand_y(cx, e.y - 30)
		var c := bt.mk_enemy(cargo[k], cx, cy if cy != null else e.y)
		c.active = true
		bt.units.append(c)
		bt.place_alien(c)
		out.append(c)
	await bt.wait(14)
	for c in out:
		if not c.dead and not bt.squad_alive().is_empty():
			await bt.foe_ai.enemy_act(c)
			await bt.until(bt.settled)

# ---------------------------------------------------------------- Q3 Vharr Boar
func vboar_tricks(bo: Unit) -> void:
	## The finale BOAR's Vharr refit: a dome over the turret every third turn, and a tongue that
	## yanks the nearest soldier in a clear line up to the tracks.
	var cd: int = bo.fl.get("dome_cd", 0)
	if bo.dome <= 0 and cd <= 0:
		bo.dome = 1
		bo.fl["dome_cd"] = 2
		bt.float_text(bo, "DOME UP!", Color("9df25c"), true)
		Sfx.play("power")
		await bt.wait(14)
	elif bo.dome <= 0:
		bo.fl["dome_cd"] = cd - 1
	var mouth := Vector2(bo.x - 56, bo.y - 26)
	var tg = null
	for o in bt.squad_alive():
		if absf(o.x - bo.x) > 400 or o.heavy or o.immovable:
			continue
		if not bt.ray_clear(mouth.x, mouth.y, o.x, o.y - o.h / 2.0):
			continue
		if tg == null or absf(o.x - bo.x) < absf(tg.x - bo.x):
			tg = o
	if tg == null:
		return
	Sfx.play("slash")
	bt.ropes.append({"x": mouth.x, "y": mouth.y, "u": tg, "t": 40, "c": Color("e05a8a")})
	await bt.wait(12)
	var dir := signf(bo.x - tg.x) if tg.x != bo.x else -1.0
	var gap: float = absf(tg.x - bo.x) - (bo.w + tg.w) / 2.0
	var pull := minf(220.0, maxf(0.0, gap))
	if pull > 8:
		tg.vx = dir * pull / 36.0
		tg.vy = -3.5
		tg.air = true
		tg.walk = null
		tg.bumped = {bo.id: true}
		tg.last_hit_by = bo
		bt.float_text(tg, "YANKED!", Color("e05a8a"), true)
		await bt.until(func(): return not tg.air or tg.dead or tg.sunk)
	if not tg.dead and absf(tg.x - bo.x) < bo.w / 2.0 + 30:
		Sfx.play("slash")
		bt.damage(tg, int(round(6 * (1 + bt.alert * 0.06))), bo, {"melee": true})
	await bt.until(bt.settled)

func alpha_near(e: Unit) -> bool:
	## ALPHA elite: others of its kind within 160px act twice.
	return bt.units.any(func(o): return o != e and o.elite == "alpha" and o.type == e.type and not o.dead and absf(o.x - e.x) <= 160)

func eat_body(e: Unit) -> void:
	## HUNGRY elite: eats a fallen body within 60px to heal 8. The body is gone for good.
	for o in bt.units:
		if o.dead and not o.gone and not o.sunk and o.kind == "enemy" and o != e and absf(o.x - e.x) <= 60 and absf(o.y - e.y) < 40:
			o.gone = true
			e.hp = mini(e.max_hp, e.hp + 8)
			bt.float_text(e, "+8 FEEDS", Color("9df25c"), true)
			Sfx.play("slash")
			await bt.wait(12)
			return

func place_encounter(id: String) -> void:
	## The level's Vharr encounter (Data.ENCOUNTERS, or the Burrow Queen) in the first fighting
	## stretch after the mid camp's yard.
	if id == "" or bt.T.stretches.is_empty():
		return
	var st: Array = bt.T.stretches[-1]
	for s2 in bt.T.stretches:
		if bt.T.yard.size() and s2[0] > bt.T.yard[1]:
			st = s2
			break
	var w: float = st[1] - st[0]
	var put := func(type: String, f: float) -> Unit:
		var x: float = st[0] + w * f
		var y = bt.T.stand_y(x, 0)
		var k := 0
		while (y == null or y >= bt.WATER_Y - 4) and k < 20:
			x += 12
			y = bt.T.stand_y(x, 0)
			k += 1
		if y == null or y >= bt.WATER_Y - 4:
			return null
		var u := bt.mk_enemy(type, x, y)
		bt.units.append(u)
		bt.place_alien(u)
		return u
	if id == "nest":
		var stagger := 1
		for f in [0.3, 0.55, 0.8]:
			var h = put.call("hive", f)
			if h != null:
				h.fl["hatch"] = stagger + 1
				stagger += 1
		put.call("squid", 0.65)
	elif id == "queen":
		put.call("queen", 0.7)
		put.call("skitter", 0.4)
	elif id == "droppods":
		bt.ambush = {"x": st[0] + w * 0.35, "done": false}
	elif id == "hunt":
		var pool: Array = bt.foe_ai.alien_pool().filter(func(k): return Data.ETYPES[k].get("weight", "") != "hover")
		var hu = put.call(bt.pick(pool) if pool.size() else "stalker", 0.8)
		if hu != null:
			bt.make_elite(hu, bt.pick_elite(true))
			hu.fl["hunt"] = true
			hu.fl["lead"] = true
			for f in [0.74, 0.86]:
				var es = put.call("skitter", f)
				if es != null:
					es.fl["hunt"] = true
	elif id == "outbreak":
		for jt in [["grunt", 0.4], ["shield", 0.46], ["grunt", 0.52], ["brute", 0.58], ["grunt", 0.64]]:
			var j = put.call(jt[0], jt[1])
			if j != null:
				j.fl["camp"] = true
		var ov = put.call("overseer", 0.75)
		if ov != null:
			ov.fl["outbreak"] = true
	elif id == "gate":
		put.call("vgate", 0.62)
		put.call("skitter", 0.5)
	elif id == "swarm":
		put.call("burrow", 0.45)
		var b2 = put.call("burrow", 0.8)
		if b2 != null:
			b2.fl["wave"] = 1  # the far tunnel starts on its second wave: 4, then 3

func boss_act(bo: Unit) -> void:
	if bo.x > bt.cam_x + bt.W - 170:
		var pts: Array = []
		var x := bo.x
		for i in 20:
			x -= 2
			var y = bt.T.stand_y(x, bo.y - 40)
			pts.append([x, y if y != null else bo.y, false])
		await bt.phys.walk_along(bo, pts)
	if bo.fl.get("vharr", false):
		await vboar_tricks(bo)
		if bo.dead or bt.squad_alive().is_empty():
			return
	var shells := 2 if bo.hp < bo.max_hp / 2 else 1
	for i in shells:
		var sq := bt.squad_alive()
		if sq.is_empty():
			return
		var tg: Unit = bt.pick(sq)
		var pv := bt.boss_pivot(bo)
		var sol = bt.phys.solve_arc(pv.x - 40, pv.y - 10, tg.x, tg.y - 4, 1, 14)
		if sol != null:
			var k := 1 + (randf() - .5) * 0.08
			bo.aim_a = clampf(atan2(-sol.vy, -sol.vx), -0.4, 1.2)
			await bt.wait(10)
			var m := bt.muzzle(bo)
			Sfx.play("bigboom")
			bt.shake += 4
			for j in 4:
				bt.puff(m.x, m.y, 2.0)
			# B2: the shell keeps its base damage at any alert (alert already brings airstrikes and paratroopers)
			bt.projs.append(bt.phys.mk_proj({"kind": "shell", "x": m.x, "y": m.y, "vx": sol.vx * k, "vy": sol.vy * k, "wind": 1.0, "r": 44.0, "dmg": 11, "owner": bo, "trail": true}))
			await bt.until(bt.settled)
			await bt.wait(12)
	var best = bt.foe_ai.best_shot(bo, bt.squad_alive(), Data.ETYPES.boss.range)
	if best != null:
		await bt.foe_ai.enemy_shoot(bo, best.t, Data.ETYPES.boss)

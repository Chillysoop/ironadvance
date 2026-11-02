class_name BattleVehicles
extends RefCounted
## Gears, hijacked vehicles and the Jackal Walker.
## Split out of battle.gd (R3). Functions only: every piece of mission state lives on the Battle,
## reached through `bt`.

var bt: Battle

func _init(battle: Battle) -> void:
	bt = battle

# ---------------------------------------------------------------- N3 Gears, R1 hijacked vehicles, E6 Jackal Walker
func mech_max(u: Unit, type: String, own: bool) -> int:
	var hp := float(Data.VEHICLES[type].hp)
	if u.team == "squad":
		if own and u.perk("armorplate"):
			hp += 15
		if own and bt.ks(u, "jumpjets"):
			hp += 20
		if bt.squad_alive().any(func(o): return bt.ks(o, "toolkit")):
			hp *= 1.5
	return int(hp)

func mount(u: Unit, type: String, hp := -1, own := false) -> void:
	## Climb into a vehicle. Its HP soaks every hit until it breaks; a hijacker gets its cards in hand.
	if u.mech != null:
		return
	var V: Dictionary = Data.VEHICLES[type]
	Sfx.play("engine", -4)
	var mx := mech_max(u, type, own)
	u.mech = {"type": type, "hp": mx if hp < 0 else mini(hp, mx), "max": mx, "own": own, "h0": u.h, "w0": u.w}
	u.h += V.seat
	u.w = maxf(u.w, 26.0)
	u.heavy = true
	if not own:
		mech_cards(u)
	if u.mech_stash.size():
		# back in a vehicle: the deck's own vehicle cards are shuffled back into the draw pile
		for c in u.mech_stash:
			u.draw.insert(randi() % (u.draw.size() + 1), c)
		u.mech_stash = []
		bt.ui_dirty = true

func mech_cards(u: Unit) -> void:
	## A hijacked vehicle's own guns go in the driver's hand, and come back every turn.
	if u.mech == null or u.mech.own:
		return
	for k in Data.VEHICLES[u.mech.type].cards:
		if not u.hand.any(func(h): return h.key == k and h.get("mechtemp", false)):
			u.hand.append({"id": -7, "key": k, "tier": Data.base_tier(k), "temp": true, "mechtemp": true})

func vehicle_pop(u: Unit, mode: String, type: String, added: Array, removed: Array) -> void:
	## Pop the boarding card over the field: what the vehicle does and which cards came or went.
	if u.team != "squad":
		return
	bt.vpop = {"u": u, "mode": mode, "type": type, "added": added, "removed": removed, "t0": bt.t}
	bt.ui_dirty = true

func dismount(u: Unit, launch := true) -> void:
	if u.mech == null:
		return
	# on foot, vehicle cards are gone at once: the hijacked guns from the hand, and the deck's own
	# vehicle cards (Gears' walker) from the hand, draw and discard piles until the next mount
	var is_veh := func(h): return h.get("mechtemp", false) or Data.card(h).get("mech", false)
	var gone: Array = u.hand.filter(is_veh).map(func(h): return h.key)
	for pile in [u.hand, u.draw, u.disc]:
		for h in pile:
			if is_veh.call(h) and not h.get("mechtemp", false) and not h.get("temp", false):
				u.mech_stash.append(h)
	u.hand = u.hand.filter(func(h): return not is_veh.call(h))
	u.draw = u.draw.filter(func(h): return not is_veh.call(h))
	u.disc = u.disc.filter(func(h): return not is_veh.call(h))
	vehicle_pop(u, "out", u.mech.type, [], gone)
	u.h = u.mech.h0
	u.w = u.mech.w0
	u.heavy = u.immovable
	u.mech = null
	if launch:
		u.vx = -u.face * 1.5; u.vy = -6.0; u.air = true; u.walk = null; u.bumped = {}; u.jumping = true
	bt.ui_dirty = true

func mech_hit(u: Unit, amt: int) -> void:
	## The vehicle takes the hit instead of the driver. At 0 it falls apart and the driver tumbles out.
	if u.mech.own and u.perk("reactive"):
		amt = maxi(1, amt - 2)
	u.mech.hp -= amt
	u.flash = 8
	bt.sparks(u.x, u.y - 12, 3)
	bt.float_text(u, "-%d %s" % [amt, Data.VEHICLES[u.mech.type].name], Color("ffb23e"))
	if u.mech.hp <= 0:
		var nm: String = Data.VEHICLES[u.mech.type].name
		for k in 8:
			bt.debris(u.x + randf_range(-12, 12), u.y - randf_range(4, 20), 2)
		bt.puff(u.x, u.y - 10, 2.0)
		Sfx.play("boom", -6)
		var tp: String = u.mech.type
		var own: bool = u.mech.own
		dismount(u)
		if bt.vpop.get("u") == u:
			bt.vpop.mode = "wreck"
		elif own:
			vehicle_pop(u, "wreck", tp, [], [])
		bt.float_text(u, nm + " WRECKED", Color("ff7a3d"), true)
		bt.log_msg("%s's %s is wrecked. %s" % [u.def.name, nm.to_lower(), "Patch Job puts him back in one." if u.def.key == "gears" else "They're on foot."])
	bt.ui_dirty = true

func mech_ok(u: Unit, c: Dictionary) -> String:
	## Why this card can't be played right now ("" when it can).
	if c.get("mech", false) and u.mech == null:
		return "NEEDS A VEHICLE"
	if c.get("patch", false) and u.mech != null:
		return "ALREADY DRIVING"
	if c.get("bodythrow", false) and u.held == null:
		return "NOTHING TO THROW"
	return ""

func _act_eject(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	## Eject!: the driver pops out, the empty vehicle charges at the cursor and blows.
	bt.spend_card(u, idx, c)
	u.attacked = true
	var type: String = u.mech.type
	var v := bt.rush_vel(u, p)
	var hk := bt.mk_unit()
	hk.team = "neutral"; hk.kind = "hulk"; hk.x = u.x; hk.y = u.y; hk.w = 26; hk.h = 24; hk.hp = 1; hk.max_hp = 1; hk.heavy = true
	hk.face = 1 if p.x >= u.x else -1
	hk.loot = {"type": type, "by": u}
	hk.y = u.y - 2
	hk.vx = v.vx; hk.vy = v.vy; hk.air = true; hk.bumped = {u.id: true}; hk.last_hit_by = u; hk.rushing = true
	dismount(u)
	bt.units.append(hk)
	bt.banner("EJECT!", Color("ffb23e"))
	Sfx.play("power")
	if u.perk("softlanding"):
		u.armor += 8
		bt.float_text(u, "+8 ARMOR", Color("9fb4c9"))
	if bt.ks(u, "ejectseat"):
		bt.draw_cards(u, 2)
		u.energy += 1
	var t0 := bt.t
	await bt.until(func(): return not hk.air or bt.t - t0 > 240 or bt.units.any(func(e): return e.team == "enemy" and not e.dead and not e.gone and absf(e.x - hk.x) < e.w / 2.0 + 12 and hk.y > e.y - e.h - 6 and hk.y - 24 < e.y))
	hk.gone = true
	var r: float = c.radius * (1.5 if u.perk("biggerboom") else 1.0) * bt.blast_scale(u)
	bt.explode(hk.x, hk.y - 10, r, c.dmg, u)
	for k in 10:
		bt.debris(hk.x + randf_range(-14, 14), hk.y - randf_range(4, 24), 2)
	await bt.wait(20)
	if c.get("rebuild", false) and not u.dead:
		await bt.until(func(): return not u.air or u.dead)
		mount(u, "walker", -1, true)
		bt.float_text(u, "FRESH WALKER", Color("62d26f"), true)

func patch_job(u: Unit) -> void:
	mount(u, "tank" if bt.ks(u, "treads") else "walker", -1, true)
	for k in 6:
		bt.sparks(u.x + randf_range(-12, 12), u.y - randf_range(4, 30), 2)
	bt.float_text(u, "PATCH JOB", Color("62d26f"), true)
	Sfx.play("ping")

func ride_along(u: Unit) -> void:
	var rk = null
	for s in bt.squad_alive():
		if s.def.key == "rook":
			rk = s
	bt.banner("RIDE ALONG!", Color("ffb23e"))
	if rk != null:
		var gy = bt.T.stand_y(u.x - u.face * 22.0, u.y - 40)
		await bt.vharr_ai.leap_to(rk, Vector2(u.x - u.face * 22.0, gy if gy != null else u.y))
		rk.armor += 6
		bt.float_text(rk, "+6 ARMOR", Color("9fb4c9"), true)
		rk.hand.append({"id": -2, "key": "burst", "tier": Data.base_tier("burst"), "temp": true, "free": true})
	u.armor += 6
	bt.float_text(u, "+6 ARMOR", Color("9fb4c9"), true)
	u.hand.append({"id": -2, "key": "vulcan", "tier": Data.base_tier("vulcan"), "temp": true, "free": true})

func field_refit(u: Unit, heal: int) -> void:
	bt.banner("FIELD REFIT!", Color("62d26f"))
	if u.mech != null:
		u.mech.hp = u.mech.max
	else:
		patch_job(u)
	for s in bt.squad_alive():
		s.hp = mini(s.max_hp, s.hp + heal)
		bt.float_text(s, "+%d HP" % heal, Color("62d26f"), true)
		Sfx.play("heal", -4)
	Sfx.play("coin")

func vehicles_new_turn() -> void:
	## Start of the squad's turn: hijackers get their vehicle's guns back, Tune-Up repairs.
	var tune := bt.squad_alive().any(func(o): return o.perk("tuneup"))
	for s in bt.squad_alive():
		if s.mech == null:
			continue
		mech_cards(s)
		if tune and s.mech.hp < s.mech.max:
			s.mech.hp = mini(s.mech.max, s.mech.hp + 6)
			bt.float_text(s, "TUNE-UP +6", Color("62d26f"))

func hijack(u: Unit, r: Unit) -> void:
	## R1: walk onto a parked vehicle and you're driving it.
	r.gone = true
	var before: Array = u.hand.duplicate()
	mount(u, r.loot.type, r.loot.get("hp", -1))
	Sfx.play("power")  # the boarding card is the announcement: no banner on top of it
	if bt.squad_alive().any(func(o): return o.perk("hotwire")):
		u.energy += 1
		u.hand.append({"id": -2, "key": "vulcan", "tier": Data.base_tier("vulcan"), "temp": true, "free": true})
		bt.float_text(u, "HOTWIRED +1", Color("ffb23e"))
	vehicle_pop(u, "in", r.loot.type, u.hand.filter(func(h): return not before.has(h)).map(func(h): return h.key), [])
	bt.log_msg("%s takes the %s. Its HP soaks every hit until it breaks." % [u.def.name, Data.VEHICLES[r.loot.type].name.to_lower()])
	bt.ui_dirty = true

func park_ride(x: float, type: String, hp := -1) -> Unit:
	var gy = bt.T.stand_y(x, 0)
	if gy == null or gy >= bt.WATER_Y - 4:
		return null
	if bt.T.lakes.any(func(l): return x > l[0] - 20 and x < l[1] + 20):
		return null  # M1: lake crust breaks under any vehicle, so the first driver would sink on boarding
	var r := bt.mk_unit()
	r.team = "neutral"; r.kind = "ride"; r.x = x; r.y = gy; r.w = 30; r.h = 24; r.face = -1
	r.loot = {"type": type, "hp": hp}
	bt.units.append(r)
	return r

func place_vehicles() -> void:
	## R1: a parked Jackal vehicle in the first stretch, and E6: a Jackal Walker guarding the second
	## half of it. Neither in a breach, a detour yard or the finale harbor.
	if bt.T.stretches.is_empty() or bt.mission.get("finale", false) or bt.mission.get("tutorial", false) or bt.in_lesson():
		return
	var st: Array = bt.T.stretches[0]
	var w: float = st[1] - st[0]
	var kind: String = bt.pick(["bike", "walker", "tank"])
	for f in [0.3, 0.2, 0.4, 0.15, 0.5]:
		if park_ride(st[0] + w * f, kind) != null:
			break
	if bt.mission.get("walker", false):
		var mb: String = bt.mission.get("miniboss", "jwalker")
		# E6: both feet on solid ground, or leg_check topples it before the squad has moved
		var x: float = st[0] + w * 0.75
		for f in [0.75, 0.7, 0.8, 0.65, 0.85]:
			x = st[0] + w * f
			var y0 = bt.T.stand_y(x, 0)
			if y0 != null and bt.T.solid(x - 13, y0 + 3) and bt.T.solid(x + 13, y0 + 3):
				break
		var y = bt.T.stand_y(x, 0)
		if y != null and y < bt.WATER_Y - 4:
			var e := bt.mk_enemy(mb, x, y)
			if mb == "jwalker":
				e.mech = {"type": "walker", "hp": 0, "max": 0, "own": false, "h0": 34, "w0": 16}
			bt.place_alien(e)
			bt.units.append(e)

func leg_check() -> void:
	## E6: a Jackal Walker with the ground blown out under one leg topples that way and crushes.
	for e in bt.units.duplicate():
		if e.type != "jwalker" or e.dead or e.gone or e.air:
			continue
		var l := bt.T.solid(e.x - 13, e.y + 3)
		var r := bt.T.solid(e.x + 13, e.y + 3)
		if l == r:
			continue
		var dir := -1.0 if not l else 1.0
		bt.banner("WALKER TOPPLED!", Color("ffd23a"))
		Sfx.play("bigboom")
		bt.shake += 8
		e.face = int(dir)
		var by = e.last_hit_by if e.last_hit_by is Unit and e.last_hit_by.team == "squad" else (bt.squad_alive()[0] if bt.squad_alive().size() else null)
		for o in bt.units.duplicate():
			if o == e or o.dead or o.gone or o.is_pickup() or o.kind in ["pow", "ride", "rivet", "loot"]:
				continue
			var dx: float = (o.x - e.x) * dir
			if dx > 4 and dx < 84 and absf(o.y - e.y) < 50:
				bt.damage(o, 25, by, {"crush": true})
				bt.float_text(o, "CRUSHED", Color("ffd23a"))
		for k in 10:
			bt.dust(e.x + dir * randf_range(10, 80), e.y)
		bt.kill(e, by)
		await bt.wait(30)

func walker_wreck(e: Unit) -> void:
	## A dead Jackal Walker leaves its walker behind, banged up but drivable.
	e.gone = true
	for k in 10:
		bt.debris(e.x + randf_range(-14, 14), e.y - randf_range(4, 40), 2)
	bt.puff(e.x, e.y - 20, 2.5)
	var r := park_ride(e.x, "walker", 18)
	if r != null:
		bt.float_at(r.x, r.y - 40, "WALKER UP FOR GRABS", Color("ffb23e"), true)

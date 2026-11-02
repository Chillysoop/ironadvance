class_name BattleBiomes
extends RefCounted
## Biome rules and level hazards.
## Split out of battle.gd (R3). Functions only: every piece of mission state lives on the Battle,
## reached through `bt`.

var bt: Battle

func _init(battle: Battle) -> void:
	bt = battle

# ---------------------------------------------------------------- M1-M7: new biomes
func setup_biome() -> void:
	bt.lava_k = 0
	bt.sweeps = []
	if bt.rules.get("tunnel", 0) > 0 and bt.T.cars.size():
		bt.sweeps.append({"k": "tunnel", "x0": 0.0, "x1": float(bt.world_w), "every": int(bt.rules.tunnel), "left": int(bt.rules.tunnel), "t0": -999})
	for r in bt.T.runways:
		var n := int(bt.rules.get("planes", 3))
		bt.sweeps.append({"k": "plane", "x0": r.x0, "x1": r.x1, "every": n, "left": n, "t0": -999})

func biome_round() -> void:
	## End of every enemy phase: the biome's clockwork moves one tick, always on a count you can see.
	# V1: the lava holds still for the first rounds on a screen, the same stall clock as the alert
	if bt.rules.get("lava", 0.0) > 0 and bt.lava_k < bt.LAVA_MAX and bt.rounds_since_scroll > bt.stall_limit():
		bt.lava_k += 1
		bt.float_at(bt.cam_x + bt.W / 2.0, lava_y() - 16, "THE LAVA RISES", Color("ff7a3d"), true)
		Sfx.play("splash")
		lava_eat()
		await bt.wait(24)
	if bt.rules.get("regrow", 0) > 0 and regrow(int(bt.rules.regrow)) > 0:
		bt.float_at(bt.cam_x + bt.W / 2.0, 120, "THE HIVE GROWS BACK", Color("c47bff"), true)
		await bt.wait(16)
	for l in bt.T.lifts:
		l.t -= 1
		if l.t <= 0:
			move_lift(l)
			await bt.wait(16)
	for sw in bt.sweeps:
		sw.left -= 1
		if sw.left <= 0:
			sw.left = sw.every
			await run_sweep(sw)

# --- M1 Frozen Lake
func ice_crack(u: Unit) -> void:
	## A heavy Jackal or any vehicle that stops on the lake crust goes through it.
	if bt.T.lakes.is_empty() or u.dead or u.gone or u.air:
		return
	if not (u.mech != null or (u.team == "enemy" and (u.heavy or bt.ICE_HEAVY.has(u.type)))):
		return
	if bt.T.mat(u.x, u.y + 1) != Terrain.ICE or not bt.T.lakes.any(func(l): return u.x > l[0] and u.x < l[1]):
		return
	bt.float_text(u, "THE ICE BREAKS!", Color("9fe3f0"), true)
	Sfx.play("splash")
	if bt.vfx != null:
		bt.vfx.add(SfIce.new(u.x, u.y, bt.vfx.ground_fn(u.y), clampf(u.w / 40.0, 0.8, 1.6)))
	bt.T.carve(u.x, u.y + 2, 20.0, null)
	u.air = true
	u.walk = null

# --- M4 Deep Mine
func push_cart(c: Unit, src) -> void:
	## Anything that hits a mine cart sends it rolling away from whoever hit it.
	if c.slide != 0 or c.air:
		return
	var dir := 1.0
	if src is Unit and src != c:
		dir = signf(c.x - src.x) if absf(c.x - src.x) > 1 else float(src.face)
	c.slide = dir * 7.0
	c.last_hit_by = src if src is Unit else null
	c.fl["ran"] = {}
	bt.float_text(c, "RUNAWAY CART!", Color("ffd23a"), true)
	Sfx.play("land")

func cart_ram(c: Unit) -> void:
	## A rolling cart runs over every Jackal it reaches: 18 damage and thrown on down the line.
	for o in bt.units:
		if o == c or o.dead or o.gone or o.sunk or o.team != "enemy" or bt.is_boss(o) or c.fl.get("ran", {}).has(o.id):
			continue
		if absf(o.x - c.x) < (o.w + c.w) / 2.0 and o.y > c.y - c.h - 4 and o.y - o.h < c.y + 2:
			c.fl.ran[o.id] = true
			bt.float_text(o, "RUN OVER!", Color("ffd23a"), true)
			bt.damage(o, 18, c.last_hit_by, {"blast": true})
			bt.spec_kits.fling(o, signf(c.slide), 6.0, c.last_hit_by)
			bt.shake += 3

# --- M5 Volcano
func lava_y() -> float:
	return bt.WATER_Y - bt.lava_k * lava_step()

func lava_step() -> float:
	## V2: half steps on level 2 or earlier, so the first volcano a squad meets reaches half as high.
	## F5: 20% shorter steps on level 3, where the lava was downing more soldiers than anything else.
	if bt.mission.get("finale", false) or Run.campaign():
		return float(bt.rules.get("lava", 10.0))
	return float(bt.rules.get("lava", 10.0)) * (0.5 if bt.mission_idx <= 1 else 0.8)

func lava_eat() -> void:
	## The lava burns away wood, ice and rubber below its line, and scorches everything else.
	Sfx.play("sizzle", -6)
	var r0 := int(ceil(lava_y() / bt.CELL))
	for cy in range(r0, Terrain.WATER_ROW):
		for cx in bt.T.cols:
			var i := cy * bt.T.cols + cx
			var m := bt.T.grid[i]
			if m == 3 or m == Terrain.ICE or m == Terrain.RUBBER:
				bt.T.set_cell(cx, cy, 0)
			elif m != 0:
				bt.T.data[i * 2 + 1] = maxi(bt.T.data[i * 2 + 1], 150)
				bt.T.dirty = true
	bt.T.check_bridges(null)
	for u in bt.units:
		lava_check(u)

func lava_check(u: Unit) -> void:
	if bt.lava_k <= 0 or u.dead or u.gone or u.sunk or u.weight == "hover" or u.kind == "pow" or u.y < lava_y() + 2:
		return
	if u.is_pickup():
		u.gone = true
		return
	if u.is_prop():
		if u.kind == "mine" or u.kind == "cart":
			u.gone = true
		else:
			bt.damage(u, 99, null, {"blast": true})
		return
	bt.float_text(u, "BURNED UP", Color("ff7a3d"), true)
	bt.part({"x": u.x, "y": u.y - 8, "vx": 0.0, "vy": -3.0, "life": 40, "max": 40, "c": Color("ff7a1e"), "s": 4.0, "g": 0.05, "fire": true})
	bt.kill(u, u.last_hit_by if u.last_hit_by is Unit and u.last_hit_by.team == "squad" else null)

func lava_drain() -> void:
	if bt.lava_k > 0:
		bt.lava_k = 0
		bt.float_at(bt.cam_x + bt.W / 2.0, bt.WATER_Y - 20, "THE LAVA DRAINS", Color("ffd23a"), true)

# --- M6 Vharr Hive
func regrow(n: int) -> int:
	## Up to n blown-away blocks on screen grow back, from the bottom up, never inside anyone.
	if bt.T.orig.is_empty():
		return 0
	var c0 := maxi(0, int((bt.cam_x - 80) / bt.CELL))
	var c1 := mini(bt.T.cols - 1, int((bt.cam_x + bt.W + 80) / bt.CELL))
	var live := bt.units.filter(func(u): return not u.dead and not u.gone and not u.sunk)
	var got := 0
	for cy in range(Terrain.WATER_ROW - 1, 0, -1):
		for cx in range(c0, c1 + 1):
			var i := cy * bt.T.cols + cx
			if bt.T.grid[i] != 0 or bt.T.orig[i] == 0:
				continue
			if bt.T.grid[i + bt.T.cols] == 0 and (cx == 0 or bt.T.grid[i - 1] == 0) and (cx == bt.T.cols - 1 or bt.T.grid[i + 1] == 0) and bt.T.grid[i - bt.T.cols] == 0:
				continue
			var px := cx * bt.CELL + 2.0
			var py := cy * bt.CELL + 2.0
			if live.any(func(u): return absf(u.x - px) < u.w / 2.0 + 4 and py > u.y - u.h - 4 and py < u.y + 4):
				continue
			bt.T.set_cell(cx, cy, bt.T.orig[i])
			got += 1
			if got >= n:
				return got
	return got

# --- M7 Carrier Deck
func move_lift(l: Dictionary) -> void:
	## The elevator drops a storey (or comes back up), carrying whoever stands on it.
	var y0: float = l.y_up if l.up else l.y_dn
	var riders := bt.units.filter(func(u): return not u.dead and not u.gone and not u.air and u.x > l.x0 - 2 and u.x < l.x1 + 2 and absf(u.y - y0) < 3)
	bt.T.lift_cells(l, false)
	l.up = not l.up
	bt.T.lift_cells(l, true)
	var y1: float = l.y_up if l.up else l.y_dn
	for u in riders:
		u.y = y1
		u.walk = null
	l.t = l.every
	bt.float_at((l.x0 + l.x1) / 2.0, y1 - 30, "LIFT UP" if l.up else "LIFT DOWN", Color("ffd23a"), true)
	Sfx.play("land")

# --- M2 tunnel and M7 jet
func sweep_hits(sw: Dictionary) -> Array:
	## Who a sweep would hit right now: on a car roof for the tunnel, on the deck in the lane for the jet.
	var out: Array = []
	for u in bt.units:
		if u.dead or u.gone or u.sunk or u.is_pickup() or u.kind == "pow" or u.kind == "loot" or bt.is_boss(u):
			continue
		if sw.k == "tunnel":
			if bt.T.cars.any(func(c): return u.x >= c.x and u.x <= c.x + c.w and u.y <= c.roof + 2 and u.y > c.roof - 80):
				out.append(u)
		elif u.x >= sw.x0 and u.x <= sw.x1 and not u.air and absf(u.y - bt.T.ground_at(u.x)) <= 4:
			out.append(u)
	return out

func run_sweep(sw: Dictionary) -> void:
	var tunnel: bool = sw.k == "tunnel"
	if tunnel:
		bt.banner("TUNNEL!", Color("ff7a3d"), "EVERYONE ON THE ROOFS GETS HIT")
	else:
		bt.banner("JET TAXIING!", Color("ff7a3d"), "CLEAR THE PAINTED LANE")
	Sfx.play("alarm")
	sw.t0 = bt.t
	await bt.wait(30)
	bt.shake += 6
	for u in sweep_hits(sw):
		bt.float_text(u, "TUNNEL!" if tunnel else "JET WASH!", Color("ff7a3d"), true)
		if u.is_prop():
			bt.damage(u, 99, null, {"blast": true})
			continue
		bt.damage(u, 12 if tunnel else 14, null)
		bt.spec_kits.fling(u, -1.0 if tunnel else 1.0, 6.0, null)
	await bt.wait(24)
	await bt.until(bt.settled)

func hazard_word() -> String:
	## What going into the "water" means here.
	if bt.rules.get("train", false):
		return "UNDER THE WHEELS"
	if bt.rules.get("lava", 0.0) > 0:
		return "INTO THE LAVA"
	return ""

# ---------------------------------------------------------------- level hazards
func prime_mine(m: Unit, owner, delay: int) -> void:
	m.primed = true
	m.flash = 40
	Sfx.play("beep")
	bt.booms.append({"t": delay, "x": m.x, "y": m.y - 3, "r": 38.0, "dmg": 15, "owner": owner, "barrel": m})

func mine_under(u: Unit, x: float, y: float, pad: float = 0.0):
	## The armed mine a soldier standing at (x, y) would set off, with pad px of margin, or null.
	if u.team == "squad" and u.def.key == "finch":
		return null  # Light Feet
	for m in bt.units:
		if m.kind == "mine" and not m.primed and not m.gone and absf(x - m.x) < u.w / 2.0 + 5 + pad and absf(y - m.y) < 8:
			return m
	return null

func stop_before_mines(u: Unit, sim: Dictionary) -> Dictionary:
	## Automatic walks (MOVE) stop short of the first armed mine on the path; stepping on one is
	## always the player's own call.
	var pts: Array = sim.pts
	var cut := pts.size()
	for i in pts.size():
		if mine_under(u, pts[i][0], pts[i][1], 4) != null or live_wire_at(pts[i][0], pts[i][1], 4) != null:
			cut = i
			break
	if cut == pts.size():
		return sim
	pts = pts.slice(0, cut)
	while pts.size() and pts[-1][2]:
		pts.pop_back()
	if pts.is_empty():
		return {"pts": pts, "x": u.x, "y": u.y, "used": 0.0}
	return {"pts": pts, "x": pts[-1][0], "y": pts[-1][1], "used": absf(pts[-1][0] - u.x)}

func make_jbox(x: float):
	## T2 live wire: a junction box with a sparking cable laid along the ground to its right.
	var by = bt.T.stand_y(x, bt.T.ground_at(x) - 40)
	if by == null:
		return null
	var u := bt.mk_unit(); u.team = "neutral"; u.kind = "jbox"; u.x = x; u.y = by; u.w = 14; u.h = 20
	u.hp = 1; u.max_hp = 1; u.heavy = true; u.face = 1
	var ys: Array = []
	var wx := x + 10.0
	while wx <= x + 120.0:
		var wy = bt.T.stand_y(wx, bt.T.ground_at(wx) - 40)
		ys.append(wy if wy != null else float(bt.WATER_Y))
		wx += bt.CELL
	u.loot = {"x0": x + 10.0, "ys": ys, "on": true, "hit": {}}
	bt.units.append(u)
	return u

func wire_y(j: Unit, x: float):
	## Height of a junction box's cable at x, or null if x is off its run.
	var i := int(round((x - j.loot.x0) / bt.CELL))
	if i < 0 or i >= j.loot.ys.size():
		return null
	return j.loot.ys[i]

func live_wire_at(x: float, y: float, pad := 0.0):
	## The live junction box whose cable runs under (x, y), or null.
	for j in bt.units:
		if j.kind == "jbox" and j.loot.on and not j.gone:
			for dx in [-pad, 0.0, pad]:
				var wy = wire_y(j, x + dx)
				if wy != null and absf(y - wy) < 6:
					return j
	return null

func update_wires() -> void:
	## T2: anyone standing on a live cable gets 4 damage and (Jackals) a stun, once a round each.
	for j in bt.units:
		if j.kind != "jbox" or not j.loot.on or j.gone:
			continue
		if bt.t % 9 == 0:
			var k: int = randi() % j.loot.ys.size()
			bt.sparks(j.loot.x0 + k * bt.CELL, j.loot.ys[k] - 1, 1)
		for u in bt.units:
			if u.dead or u.gone or u.sunk or u.air or u.is_prop() or u.is_pickup() or u.kind == "pow" or u.kind == "jbox" or u.kind == "m2" or u.weight == "hover":
				continue
			if u.kind != "soldier" and u.kind != "enemy":
				continue
			var wy = wire_y(j, u.x)
			if wy == null or absf(u.y - wy) > 6 or j.loot.hit.get(u.id, -1) == bt.round_n:
				continue
			j.loot.hit[u.id] = bt.round_n
			var by = u.last_hit_by if u.team == "enemy" else null
			bt.sparks(u.x, u.y - u.h / 2.0, 8)
			Sfx.play("click", 0, 2.2)
			bt.float_text(u, "ZAP!", Color("53d4e2"), true)
			var was := bt.kill_how
			bt.kill_how = "ZAPPED"
			bt.damage(u, 4, by, {"status": true})
			bt.kill_how = was
			if not u.dead:
				bt.add_status(u, "stun", 1, by)

func update_mines() -> void:
	## Jackal mines: your soldiers set them off by stepping on them. Jackals know where they
	## are buried and only set them off when they land on one, so knock them onto the field.
	var mines := bt.units.filter(func(m): return m.kind == "mine" and not m.primed and not m.gone)
	for u in bt.units:
		var was_air: bool = bt.mine_air.get(u.id, false)
		bt.mine_air[u.id] = u.air
		if u.air:
			bt.mine_by[u.id] = u.last_hit_by
		if mines.is_empty() or (u.dead and not u.is_body()) or u.gone or u.sunk or u.air or u.is_prop() or u.kind == "pow" or u.para:
			continue
		if u.team != "squad" and not was_air:
			continue
		for m in mines:
			if not m.primed and absf(u.x - m.x) < u.w / 2.0 + 5 and absf(u.y - m.y) < 8:
				bt.float_text(m, "CLICK!", Color("ff4d3d"), true)
				var by = bt.mine_by.get(u.id) if was_air else null
				prime_mine(m, by if by is Unit and by.team == "squad" else null, 16)

func bridge_down(s: Dictionary) -> void:
	bt.banner("BRIDGE DOWN!", Color("ffb23e"))
	Sfx.play("thud")
	bt.shake += 8
	bt.score += 200
	bt.log_msg("The bridge is coming down. Anyone on it is going for a swim.")

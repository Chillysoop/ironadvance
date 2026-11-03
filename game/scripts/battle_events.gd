class_name BattleEvents
extends RefCounted
## Mid-level events, transformations and fun toggles.
## Split out of battle.gd (R3). Functions only: every piece of mission state lives on the Battle,
## reached through `bt`.

var bt: Battle

func _init(battle: Battle) -> void:
	bt = battle

# ---------------------------------------------------------------- R2-R6 mid-level events, D3 fun toggles
func setup_events() -> void:
	bt.crumble = {}
	if bt.T.stretches.is_empty() or bt.mission.get("finale", false) or bt.tutorial() or bt.in_lesson():
		return
	var st0: Array = bt.T.stretches[0]
	match bt.mission.get("event", ""):
		"fireteam":
			# R2: two friendly riflemen pinned down in the middle of the first stretch
			# on open ground, not up a tower they could never climb down from
			var spots: Array = []
			var x: float = (st0[0] + st0[1]) / 2.0
			while spots.size() < 2 and x < st0[1]:
				var gy = bt.T.stand_y(x, bt.T.ground_at(x) - 40)
				if gy != null and absf(gy - bt.T.ground_at(x)) < 9:
					spots.append([x, gy])
					x += 26.0
				else:
					x += 8.0
			for sp in spots:
				var x2: float = sp[0]
				var y: float = sp[1]
				var tr := bt.spec_kits.make_sentry(null, x2, y, 20, [3, 4])
				tr.loot["trooper"] = true
				tr.loot["pinned"] = true
				tr.heavy = false
				tr.w = 14; tr.h = 30
				tr.face = 1
			if bt.units.any(func(o): return o.kind == "sentry" and o.loot.get("trooper", false)):
				bt.log_msg("A friendly fire team is pinned down up ahead. Reach them and they join you until camp.")
		"collapse":
			# R3: the second stretch falls away behind the squad
			if bt.T.stretches.size() >= 2:
				bt.crumble = {"x0": bt.T.stretches[1][0] - 60.0, "x1": bt.T.stretches[1][1] + 60.0, "x": bt.T.stretches[1][0] - 60.0, "on": false}
		"dealer":
			# R4: a trader at the end of the first stretch with three items rolled now, shown before you buy
			var x: float = st0[1] - 30.0
			var y = bt.T.stand_y(x, bt.T.ground_at(x) - 40)
			if y != null:
				var d := bt.mk_unit(); d.team = "neutral"; d.kind = "dealer"; d.x = x; d.y = y; d.w = 20; d.h = 30; d.face = -1
				d.loot = {"stock": [Run.roll_item(1), Run.roll_item(1), Run.roll_item(2)]}
				bt.units.append(d)

func open_spot(st: Array) -> Array:
	## V11: a spot on open ground near the middle of a stretch, or [] if there is none.
	var mid: float = (st[0] + st[1]) / 2.0
	for d in range(0, int((st[1] - st[0]) / 2.0), 8):
		for x in [mid + d, mid - d]:
			var gy = bt.T.stand_y(x, bt.T.ground_at(x) - 40)
			if gy != null and absf(gy - bt.T.ground_at(x)) < 9 and not bt.T.pits.any(func(p): return x > p[0] - 20 and x < p[1] + 20):
				return [x, gy]
	return []

func setup_road() -> void:
	## V4: the extra on the road the squad took, in the second fighting stretch.
	var id: String = bt.mission.get("road", "")
	if id == "" or bt.T.stretches.size() < 2 or bt.tutorial() or bt.in_lesson():
		return
	var st: Array = bt.T.stretches[1]
	match id:
		"supply", "scrap", "prison":
			var n: int = {"supply": 3, "scrap": 2, "prison": 1}[id]
			for i in n:
				var x: float = lerpf(st[0], st[1], (i + 0.5) / n) + 20.0
				var sp := open_spot([x - 60.0, x + 60.0])
				if sp.is_empty():
					continue
				var u := bt.mk_unit(); u.team = "neutral"; u.x = sp[0]; u.y = sp[1]
				match id:
					"supply":
						u.kind = "crate"; u.w = 16; u.h = 14; u.hp = 1; u.max_hp = 1
					"scrap":
						u.kind = "wreck"; u.w = 40; u.h = 18
					"prison":
						u.kind = "pow"; u.face = -1
						u.pow_name = Data.POW_NAMES[randi() % Data.POW_NAMES.size()]
						bt.stats.pows_total += 1
				bt.units.append(u)
		"quiet":
			# two of the stretch's Jackals stayed home
			var foes: Array = bt.units.filter(func(e): return e.team == "enemy" and not bt.is_boss(e) and e.x >= st[0] and e.x <= st[1] and bt.faction(e) == "jackal")
			for k in mini(2, foes.size()):
				foes[foes.size() - 1 - k].gone = true

var rare_at := -1.0  # P3: where the level's rare encounter stands, until the squad first sees it

func rare_check() -> void:
	## P3: a banner the first time the rare encounter comes into view.
	if rare_at < 0.0 or not bt.in_play(rare_at, 0.0):
		return
	rare_at = -1.0
	var id: String = bt.mission.get("rare", "")
	if not Data.RARES.has(id):
		return
	var sub: String = {"merc": "A HIRED GUN IS PINNED DOWN AHEAD: REACH HIM", "wreck": "A CRASHED SCOUT SHIP: WALK ONTO IT TO STRIP IT",
		"market": "A SMUGGLER SELLS A LEGENDARY AND TWO EPICS", "ace": "A VETERAN JACKAL: KILL HIM FOR %d SCRIP AND AN EPIC" % Data.ACE_PAY}.get(id, "")
	bt.banner("RARE: " + Data.RARES[id].name, Color("9df25c"), sub)
	Sfx.play("coin")

func setup_rare() -> void:
	## V11: the level's rare encounter, in the second fighting stretch (or the first if there is one).
	var id: String = bt.mission.get("rare", "")
	if id == "" or bt.T.stretches.is_empty() or bt.mission.get("finale", false) or bt.tutorial() or bt.in_lesson():
		return
	var st: Array = bt.T.stretches[mini(1, bt.T.stretches.size() - 1)]
	var sp := open_spot(st)
	if sp.is_empty():
		return
	var x: float = sp[0]
	var y: float = sp[1]
	match id:
		"merc":
			var tr := bt.spec_kits.make_sentry(null, x, y, 40, [6, 8])
			tr.loot["trooper"] = true
			tr.loot["pinned"] = true
			tr.loot["merc"] = true
			tr.heavy = false
			tr.w = 14; tr.h = 30
			tr.face = 1
		"wreck":
			var w := bt.mk_unit(); w.team = "neutral"; w.kind = "wreck"; w.x = x; w.y = y; w.w = 40; w.h = 18
			w.loot = {"rare": true}
			bt.units.append(w)
		"market":
			var d := bt.mk_unit(); d.team = "neutral"; d.kind = "dealer"; d.x = x; d.y = y; d.w = 20; d.h = 30; d.face = -1
			d.loot = {"stock": [Run.roll_item(Data.TIER_MAX), Run.roll_item(3), Run.roll_item(3)], "market": true}
			bt.units.append(d)
		"ace":
			var e := bt.mk_enemy("brute" if randf() < 0.5 else "jsniper", x, y)
			bt.make_elite(e, bt.pick_elite(false))
			e.hp *= 2; e.max_hp = e.hp
			e.fl["ace"] = true
			bt.units.append(e)
	bt.log_msg("RARE: %s. %s" % [Data.RARES[id].name, Run.rare_text(id)])
	rare_at = x

func troopers() -> Array:
	return bt.units.filter(func(o): return o.kind == "sentry" and o.loot.get("trooper", false) and not o.dead and not o.gone)

func check_troopers(u: Unit) -> void:
	## R2: a soldier who reaches the pinned fire team brings them into the fight.
	for tr in troopers():
		if tr.loot.get("pinned", false) and absf(tr.x - u.x) < 140 and absf(tr.y - u.y) < 60:
			for o in troopers():
				o.loot.erase("pinned")
			bt.banner("FIRE TEAM JOINS!", Color("62d26f"), "THEY SHOOT AT THE END OF YOUR TURN UNTIL CAMP")
			Sfx.play("power")
			return

func troopers_follow() -> void:
	## R2: the fire team keeps up just behind whoever is out in front.
	var sq := bt.squad_alive()
	if sq.is_empty():
		return
	var lead: Unit = sq[0]
	for s in sq:
		if s.x > lead.x:
			lead = s
	var i := 0
	for tr in troopers():
		if tr.loot.get("pinned", false):
			continue
		var tx: float = lead.x - 40.0 - i * 26.0
		i += 1
		if absf(tx - tr.x) < 20:
			continue
		var pts: Array = []
		var x: float = tr.x
		var y: float = tr.y
		var dir := signf(tx - x)
		while absf(tx - x) > 3 and pts.size() < 240:
			var nx := x + dir * 3.0
			var ny = bt.T.stand_y(nx, y - 30)
			if ny == null or ny - y < -30 or ny - y > 40:  # scrambles up a sandbag, drops down off a ledge
				break
			x = nx
			y = ny
			pts.append([x, y])
		if pts.size():
			tr.walk = pts
			tr.walk_i = 0
			tr.face = int(dir)

func troopers_leave() -> void:
	for tr in troopers():
		bt.float_text(tr, "BACK TO THE LINES", Color("62d26f"), true)
		tr.gone = true

func dealer_price(it: Dictionary) -> int:
	return int(round(Run.item_price(it) * Data.DEALER_MUL))

func check_dealer(u: Unit, x0 = null) -> void:
	## R4: walk up to (or past) the arms dealer to see his three items and their prices.
	if u.dead or u.team != "squad" or bt.state != "player":
		return
	var lo := minf(u.x, x0 if x0 != null else u.x) - 44
	var hi := maxf(u.x, x0 if x0 != null else u.x) + 44
	for d in bt.units:
		if d.kind != "dealer" or d.gone or d.x < lo or d.x > hi or absf(d.y - u.y) > 30 or d.loot.get("seen", -1) == bt.round_n:
			continue
		d.loot["seen"] = bt.round_n
		var stock: Array = d.loot.stock
		while stock.size():
			var opts: Array = stock.map(func(it): return Run.item_opt(it, "%d SCRIP" % dealer_price(it)))
			var k := await bt.ask("dealer", "ARMS DEALER", "Fixed prices. You have %d scrip." % Run.scrip, opts)
			if k < 0:
				break
			var it: Dictionary = stock[k]
			if Run.scrip < dealer_price(it):
				bt.float_text(u, "NOT ENOUGH SCRIP", Color("ff7a5a"))
				Sfx.play("deny")
				break
			Run.scrip -= dealer_price(it)
			stock.remove_at(k)
			bt.float_text(u, "%s TO %s" % [Data.item_name(it).to_upper(), Run.add_loot(it).to_upper()], Color("62d26f"), true)
			Sfx.play("coin")
			bt.ui_dirty = true
		return

func crumble_round() -> void:
	## R3: once the squad is into the stretch, the ground behind falls away 120px every round.
	if bt.crumble.is_empty() or bt.crumble.x >= bt.crumble.x1:
		return
	if not bt.crumble.on:
		if not bt.squad_alive().any(func(s): return s.x > bt.crumble.x0 + 80):
			return
		bt.crumble.on = true
		bt.banner("THE GROUND IS GIVING WAY!", Color("ff7a3d"), "IT FALLS 120PX BEHIND YOU EVERY ROUND")
		await bt.wait(30)
		return
	if int(bt.crumble.get("hold", 0)) > 0:
		# F7: the last bite took a soldier, so the ground holds for one round
		bt.crumble.hold = int(bt.crumble.hold) - 1
		bt.float_at(bt.crumble.x, 200, "THE GROUND HOLDS... FOR NOW", Color("ffd23a"), true)
		await bt.wait(16)
		return
	var x0: float = bt.crumble.x
	var x1: float = minf(bt.crumble.x1, x0 + Data.CRUMBLE_STEP)
	bt.crumble.x = x1
	for cx in range(int(x0 / bt.CELL), int(x1 / bt.CELL)):
		for cy in Terrain.WATER_ROW:
			if bt.T.grid[cy * bt.T.cols + cx] != 0:
				if (cx + cy) % 9 == 0:
					bt.debris(cx * bt.CELL + 2, cy * bt.CELL + 2, bt.T.grid[cy * bt.T.cols + cx], true)
				bt.T.set_cell(cx, cy, 0)
	# the line holds: ground past the hatched strip stays put even when the collapse cut the only
	# thing it hung from (a pier or ice shelf dropped soldiers standing clear of FALLS NEXT ROUND)
	var ec := int(x1 / bt.CELL)
	if ec < bt.T.cols:
		for cy in Terrain.WATER_ROW:
			if bt.T.grid[cy * bt.T.cols + ec] != 0:
				bt.T.pins[cy * bt.T.cols + ec] = -2
	bt.T.check_floating(x1 + 20, 300, 260, null)
	bt.T.check_bridges(null)
	bt.shake += 6
	Sfx.play("collapse")
	var caught: Array = []
	for u in bt.units:
		if not u.dead and not u.gone and u.x >= x0 - 8 and u.x < x1 + 4:
			u.air = true
			u.walk = null
			if u.team == "squad":
				caught.append(u)
	await bt.wait(20)
	await bt.until(bt.settled)
	if caught.any(func(u): return u.sunk):
		bt.crumble["hold"] = 1  # F7: one round's grace for the rest of the squad

# --- R6 transformations
func transform_bonus(k: String, u: Unit) -> bool:
	## The Metal Slug pad powers. Returns false for anything that isn't one.
	match k:
		"fat":
			u.hp += 10
			u.max_hp += 10
			u.fl["fat_hp"] = int(u.fl.get("fat_hp", 0)) + 10
			u.st["fat"] = Data.BONUS_TURNS
		"zombie":
			if u.team == "squad":
				for i in 2:
					u.hand.append({"id": -2, "key": "vomit", "tier": Data.base_tier("vomit"), "temp": true})
				u.st["zombie"] = Data.BONUS_TURNS
		"monkey":
			if u.team == "squad":
				for i in 2:
					u.hand.append({"id": -2, "key": "monkeyclimb", "tier": Data.base_tier("monkeyclimb"), "temp": true})
		_:
			return false
	return true

func fat_end(u: Unit) -> void:
	if u.fl.has("fat_hp") and not u.has_st("fat"):
		u.max_hp -= int(u.fl.fat_hp)
		u.hp = mini(u.hp, u.max_hp)
		u.fl.erase("fat_hp")

# --- D3 fun toggles
func bounce_body(u: Unit, imp: float) -> bool:
	## BOUNCY BODIES: the dead come back up off the floor.
	if not Run.toggle_on("bouncy") or not u.dead or imp < 2.0:
		return false
	u.vy = -imp * 0.7
	return true

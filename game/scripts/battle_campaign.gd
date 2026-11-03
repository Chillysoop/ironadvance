class_name BattleCampaign
extends RefCounted
## Campaign-only pieces: op jobs, the pincer, camp detours and the reinforcement flare.
## Split out of battle.gd (R3). Functions only: every piece of mission state lives on the Battle,
## reached through `bt`.

var bt: Battle

func _init(battle: Battle) -> void:
	bt = battle

# ---------------------------------------------------------------- W9: the pincer at Iron Harbor
func set_view(w: String) -> void:
	## Jump the camera to one half of the pincer. Each half keeps its own camera.
	if not bt.pincer.get("on", false) or bt.pincer.view == w:
		return
	bt.pincer[bt.pincer.view + "_cam"] = bt.cam_tx
	bt.pincer.view = w
	bt.cam_x = float(bt.pincer[w + "_cam"])
	bt.cam_tx = bt.cam_x
	activate_enemies()
	bt.ui_dirty = true

func switch_wing() -> void:
	## The SQUAD A / SQUAD B button: select the other half's first soldier and jump there.
	if not bt.pincer.get("on", false) or bt.state != "player" or bt.busy:
		return
	var w := "b" if bt.pincer.view == "a" else "a"
	var al: Array = bt.squad_alive().filter(func(s): return bt.wing(s) == w)
	if al.size():
		bt.sel = al[0]
		bt.card_idx = -1
	set_view(w)
	Sfx.play("click")

func bar_squad() -> Array:
	## The soldiers the HUD's squad bar shows: on the pincer op, the half on screen.
	if bt.pincer.get("on", false):
		return bt.squad().filter(func(s): return bt.wing(s) == bt.pincer.view)
	return bt.squad()

func follow_b() -> void:
	## Squad B fights right to left: its view slides left as they advance, and the two halves
	## join up once the windows meet.
	var bs: Array = bt.squad_alive().filter(func(s): return bt.wing(s) == "b")
	if bs.is_empty():
		return
	var bx: float = bs.map(func(s): return s.x).min()
	if bx - bt.cam_tx < bt.W * 0.3:
		bt.cam_tx = clampf(bx - bt.W * 0.5, 0, bt.cam_tx)
		await bt.until(func(): return absf(bt.cam_x - bt.cam_tx) < 0.5)
		bt.cam_x = bt.cam_tx
		activate_enemies()
	if bt.cam_tx <= float(bt.pincer.a_cam) + bt.W * 0.6:
		pincer_meet()

func pincer_meet() -> void:
	## The halves meet: one squad of eight, one camera, and the flagship between them.
	var tx: float = maxf(float(bt.pincer.a_cam), bt.cam_tx if bt.pincer.view == "b" else float(bt.pincer.b_cam))
	bt.pincer.on = false
	bt.pincer["met"] = true
	for s in bt.squad():
		s.wing = "a"
	bt.cam_x = minf(bt.cam_x, tx)
	bt.cam_tx = tx
	bt.banner("THE PINCER CLOSES!", Color("62d26f"), "BOTH SQUADS FIGHT AS ONE")
	Sfx.play("start")
	bt.log_msg("Squad A and Squad B have joined up. Finish the flagship together.")
	bt.ui_dirty = true

func push_blockers() -> Array:
	## Enemies still alive on this screen short of the push zone line. While any are left, a push won't scroll.
	var line := bt.cam_x + bt.W * 0.72
	return bt.units.filter(func(e): return e.team == "enemy" and not e.dead and not e.gone and not e.sunk and e.active and not e.fl.get("turned", false) and e.x < line and e.x > bt.cam_x - 10)

func fall_in(who: Unit) -> void:
	## After a push, the squadmates left behind regroup behind the soldier who pushed, for free,
	## and get their full movement back for the rest of the turn.
	var back: Array = bt.squad_alive().filter(func(s): return s != who and not s.downed and s.zip == null and s.x < who.x - 80)
	if back.is_empty():
		return
	back.sort_custom(func(a, c): return a.x > c.x)
	var slot := who.x - 34
	for s in back:
		# first look for footing level with the pusher (a roof he's on), then for any safe ground
		var tx: float = s.x
		var ty = null
		for near in [true, false]:
			tx = maxf(slot, s.x)
			var k := 0
			while ty == null and k < 80 and tx > s.x:
				for lift in ([40.0, 120.0, 240.0] if near else [400.0]):
					ty = bt.T.stand_y(tx, maxf(0, who.y - lift))
					if ty != null and (ty > bt.WATER_Y - 2 or bt.biome_rules.mine_under(s, tx, ty, 6) != null or (near and absf(ty - who.y) > 160)):
						ty = null
					if ty != null:
						break
				if ty == null:
					tx -= 6
				k += 1
			if ty != null:
				break
		if ty != null and tx > s.x + 4:
			s.walk = null; s.vx = 0; s.vy = 0; s.hang = false
			s.face = 1
			s.zip = {"x0": s.x, "y0": s.y, "x1": tx, "y1": float(ty), "t": 0.0, "arc": 30.0 + absf(tx - s.x) * 0.15}
			slot = tx - 30
		else:
			slot -= 30
		s.move_left = 0.0 if s.has_st("pinned") else maxf(s.move_left, bt.full_move(s))
		bt.float_text(s, "FALL IN!", Color("62d26f"))
	await bt.until(func(): return back.all(func(s): return s.zip == null or s.dead))
	bt.ui_dirty = true

func check_camp(u: Unit) -> void:
	## Reaching a camp with the area clear makes camp: the downed get back up, everyone patches up,
	## and the squad picks one camp perk before moving on.
	if u.dead or u.team != "squad" or bt.state != "player":
		return
	for c in bt.T.camps:
		if c.used or u.x < c.x0 + 40 or u.x > c.x1:
			continue
		var hostile := bt.units.filter(func(e): return e.team == "enemy" and not e.dead and e.active and e.x < c.x1 + 200)
		if hostile.size():
			if not c.get("warned", false):
				c["warned"] = true
				bt.float_text(u, "CLEAR THE AREA TO MAKE CAMP", Color("ffb23e"))
			return
		c.used = true
		await make_camp(c)
		return

func make_camp(c: Dictionary) -> void:
	bt.busy = true
	bt.banner("CAMP", Color("62d26f"), "SAFE FOR NOW")
	bt.biome_rules.lava_drain()
	bt.mid_events.troopers_leave()
	Sfx.play("levelup")
	await bt.wait(30)
	var i := 0
	for s in bt.squad():
		s.s.erase("law_spent")  # B1: the LAW is reloaded at camp
		if s.dead and s.downed:
			# back on their feet at half HP, by the fire
			s.dead = false
			s.downed = false
			s.gone = false
			s.sunk = false  # one who drowned too, or the update loop skips them and their first walk never ends
			s.alpha = 1.0
			s.hp = int(ceil(s.max_hp / 2.0))
			# by the fire, unless the screen has already scrolled past it: then at the near edge
			s.x = maxf(c.fire - 40, bt.cam_x + 16) + i * 26
			var sy = bt.T.stand_y(s.x, 0)
			s.y = float(sy) if sy != null else s.y
			s.vx = 0; s.vy = 0; s.air = false; s.walk = null
			s.st = {}
			s.pose = "cheer"; s.pose_t = 60
			bt.float_text(s, "BACK IN THE FIGHT", Color("62d26f"), true)
			bt.log_msg("%s rejoins the squad at camp." % s.def.name)
			i += 1
		elif not s.dead:
			var add := int(ceil(s.max_hp * Data.CAMP_HEAL * (2.0 if Run.run_order == "medics" else 1.0))) + (5 if Run.hq("mess") >= 1 else 0)
			s.hp = mini(s.max_hp, s.hp + add)
			bt.float_text(s, "+%d" % add, Color("62d26f"))
		if not s.dead and s.def.key == "gears":
			# Grease Monkey: the walker is rebuilt to full at every camp
			if s.mech == null:
				bt.vehicle_ops.patch_job(s)
			else:
				s.mech.hp = s.mech.max
	await bt.wait(30)
	if c == bt.T.camps[0] and bt.T.yard.size() and bt.mission.has("detours"):
		await pick_detour()
	else:
		await camp_pick(c)
	bt.stats["camps"] = int(bt.stats.get("camps", 0)) + 1
	bt.busy = false
	bt.ui_dirty = true

func camp_pick(c: Dictionary) -> void:
	var opts: Array = Data.CAMP_PICKS.map(func(p): return {"kind": "service", "name": p.name, "text": p.text, "id": p.id})
	var ch := await bt.ask("camp", "MAKE CAMP", "The downed are back on their feet and everyone patched up a little. Pick one more.", opts)
	match opts[maxi(ch, 0)].id:
		"patch":
			for s in bt.squad_alive():
				s.hp = s.max_hp
			Sfx.play("power")
		"upgrade":
			# each soldier picks the card; the grid shows every card already one rarity up
			for s in bt.squad_alive():
				var cands := bt.upgrade_choices(s.s)
				if cands.is_empty():
					continue
				var shown: Array = cands.map(func(cd): return bt.Services.next_tier(cd))
				var k := await bt.ask("camp_up", "%s: FIELD UPGRADE" % s.def.name, "Pick one card to go up a rarity. Shown as it will be.", shown, s)
				if k < 0:
					continue
				var cd: Dictionary = cands[k]
				Run.raise_tier(cd)
				bt.float_text(s, Data.card(cd).name.to_upper(), Color("b48cff"))
			Sfx.play("levelup")
		"cache":
			bt.give_scrip(60, c.fire, bt.T.ground_at(c.fire) - 40, "L6587")
		"quiet":
			bt.alert = 0
			for s in bt.squad_alive():
				s.energy += 1
			Sfx.play("power")

# ---------------------------------------------------------------- camp detours
func detour_text(id: String) -> String:
	var t: String = Data.DETOURS[id].text
	if id == "pow":
		return t % Data.POW_RESCUE_ROUNDS
	if id == "salvage":
		return t % Data.WRECK_SALVAGE
	if id == "signal":
		var sg: Dictionary = Data.SIGNALS[signal_kind()]
		return "%s: %s" % [sg.name, sg.text]
	return t

func detour_pays(id: String) -> String:
	var p: String = Data.DETOURS[id].pays
	if id == "signal":
		var sp: String = Data.SIGNALS[signal_kind()].pays
		return sp % Data.SIGNAL_SALVAGE if signal_kind() == "gate" else sp
	return p % Data.COLORS_SALVAGE if id == "colors" else p

func signal_kind() -> String:
	## Which Strange Signal this level holds (rolled with the level, shown on the card).
	var k: String = bt.detour.get("ev", bt.mission.get("signal", "gate"))
	return k if Data.SIGNALS.has(k) else "gate"

func colors_post() -> float:
	## O1: the green post the stolen colors go back to, at the near end of the clearing (never off screen).
	return maxf(bt.detour.x0 + 40, bt.cam_x + 40)

func pick_detour() -> void:
	## The mid-level camp: pick one side job for the clearing ahead, or press on.
	var opts: Array = bt.mission.detours.map(func(id): return {"kind": "service", "title": "DETOUR", "icon": Data.DETOURS[id].icon, "name": Data.DETOURS[id].name, "text": "%s PAYS: %s" % [detour_text(id), detour_pays(id)], "id": id})
	opts.append({"kind": "service", "title": "NO DETOUR", "icon": "ic_boot", "name": "PRESS ON", "text": "Leave the clearing empty and keep moving.", "id": ""})
	var ch := await bt.ask("detour", "PICK A DETOUR", "The clearing past camp has room for one side job. Each pays in a different currency.", opts)
	var id: String = opts[ch].id if ch >= 0 else ""  # skipping the pick means pressing on
	if id == "tent":
		await field_tent()
	elif id != "":
		start_detour(id)

func field_tent() -> void:
	## The Doc's field tent: no fight. Pick a soldier, then one of three surgeries for them, free.
	bt.detour = {"id": "tent", "x0": bt.T.yard[0], "x1": bt.T.yard[1], "done": true, "left": 0, "scav": 0, "mod": ""}
	bt.stats["detour"] = "tent"
	var D: Dictionary = Data.DETOURS.tent
	bt.banner(D.name, Color("9df25c"), "PAYS: " + D.pays)
	var who: Array = bt.squad_alive().filter(func(u): return u.s.has("key") and not u.s.get("guest", false))
	if who.is_empty():
		return
	var who_opts: Array = who.map(func(u): return {"kind": "service", "title": u.def.cls.to_upper(), "name": u.def.name,
		"text": "HP %d/%d. %d surgeries so far." % [u.hp, u.max_hp, Run.implants_of(u.s).size() + u.s.get("field_ops", []).size()], "soldier": u.s})
	var w := await bt.ask("supply_who", "WHO GOES UNDER THE KNIFE?", "The Doc operates for free. It lasts as long as they do.", who_opts)
	if w < 0:
		return
	var u: Unit = who[w]
	var pool: Array = Data.SURGERIES.keys().filter(func(k): return int(Data.SURGERIES[k].get("rank", 1)) <= 1 and not Run.implanted(u.s, k))
	pool.shuffle()
	pool = pool.slice(0, 3)
	if pool.is_empty():
		return
	var opts: Array = pool.map(func(k): return {"kind": "service", "title": "FIELD SURGERY", "icon": "ic_heart", "name": Data.SURGERIES[k].name, "text": Data.SURGERIES[k].up, "id": k})
	var ch := await bt.ask("tent", "%s: FIELD SURGERY" % u.def.name, "Pick one. It stays with %s until they fall." % u.def.name, opts, u)
	if ch < 0:
		return
	var sid: String = opts[ch].id
	var hp0 := u.max_hp
	Run.field_op(u.s, sid)
	u.gb = Run.gear_bonus(u.s)
	u.max_hp = Run.eff_max_hp(u.s)
	u.hp = mini(u.max_hp, u.hp + maxi(0, u.max_hp - hp0))
	u.dodge = u.def.dodge + u.s.bonus.dodge
	bt.float_text(u, Data.SURGERIES[sid].name, Color("9df25c"), true)
	Sfx.play("power")
	bt.log_msg("The Doc's field tent: %s gets the %s. %s" % [u.def.name, Data.SURGERIES[sid].name.capitalize(), Data.SURGERIES[sid].up])
	Run.save_meta()
	bt.ui_dirty = true

func start_detour(id: String) -> void:
	var x0: float = bt.T.yard[0]
	var x1: float = bt.T.yard[1]
	bt.detour = {"id": id, "x0": x0, "x1": x1, "done": false, "left": Data.POW_RESCUE_ROUNDS, "scav": 0, "mod": ""}
	match id:
		"elite":
			bt.detour.mod = bt.pick_elite(false)
			for sp in [["grunt", 300], ["shield", 400], ["nade", 560], ["brute", 650]]:
				var de := detour_enemy(sp[0], x0 + sp[1], bt.detour.mod)
				if sp[1] == 650:
					de.carry = "bow"  # O2: the bowman; kill him and the Rambo Bow is yours
		"colors":
			for sp in [["grunt", 470], ["shield", 590], ["grunt", 690]]:
				detour_enemy(sp[0], x0 + sp[1], "")
			bt.drop_loot(x0 + 650, bt.T.stand_y(x0 + 650, 0) - 4, {"type": "colors"}, 0.0)
		"pow":
			var pi := randi()
			for dx in [220, 430, 620]:
				var p := bt.mk_unit(); p.team = "neutral"; p.kind = "pow"; p.x = x0 + dx; p.y = bt.T.stand_y(p.x, 0); p.face = -1
				p.pow_name = Data.POW_NAMES[pi % Data.POW_NAMES.size()]; pi += 1
				p.detour = true
				bt.stats.pows_total += 1
				bt.units.append(p)
			detour_enemy("grunt", x0 + 320, "")
			detour_enemy("grunt", x0 + 530, "")
		"salvage":
			for i in 5:
				var w := bt.mk_unit(); w.team = "neutral"; w.kind = "wreck"; w.x = x0 + 130 + i * 125; w.y = bt.T.stand_y(w.x, 0)
				w.w = 34; w.h = 18; w.hp = 1; w.max_hp = 1; w.detour = true
				bt.units.append(w)
		"cache":
			for sp in [["grunt", 300], ["grunt", 470], ["nade", 600]]:
				detour_enemy(sp[0], x0 + sp[1], "")
			var cu := bt.mk_unit(); cu.team = "neutral"; cu.kind = "crate"; cu.x = x0 + 660; cu.y = bt.T.stand_y(cu.x, 0); cu.w = 16; cu.h = 14; cu.hp = 1; cu.max_hp = 1
			bt.units.append(cu)
		"signal":
			bt.detour.ev = signal_kind()
			if bt.detour.ev == "tank":
				var r: Unit = null
				for dx in [420, 360, 480, 300, 540]:
					r = bt.vehicle_ops.park_ride(x0 + dx, "tank")
					if r != null:
						break
				if r == null:
					bt.detour.ev = "gate"  # nowhere solid to park it: the gate misfires instead
				else:
					r.detour = true
					detour_enemy("grunt", r.x - 40, "")
					detour_enemy("grunt", r.x + 50, "")
			if bt.detour.ev == "deserter":
				var p := bt.mk_unit(); p.team = "neutral"; p.kind = "pow"; p.x = x0 + 640; p.y = bt.T.stand_y(p.x, 0); p.face = -1
				p.pow_name = "THE DESERTER"
				p.detour = true
				bt.units.append(p)
				detour_enemy("grunt", x0 + 420, "")
			if bt.detour.ev == "gate":
				for dx in [380, 470, 560]:
					detour_enemy("skitter", x0 + dx, "")
	var D: Dictionary = Data.DETOURS[id]
	bt.banner(Data.SIGNALS[bt.detour.ev].name if id == "signal" else D.name, Color("ffb23e"), "PAYS: " + detour_pays(id))
	bt.log_msg("Detour: %s %s" % [D.name.capitalize(), detour_text(id)])
	bt.stats["detour"] = id
	activate_enemies()
	bt.ui_dirty = true

func detour_enemy(type: String, x: float, mod: String) -> Unit:
	if type == "nade":
		type = "grunt"  # the Bomber is retired
	var u := bt.mk_enemy(type, x, bt.T.stand_y(x, 0))
	u.detour = true
	if mod != "":
		bt.make_elite(u, mod)
	bt.units.append(u)
	return u

func strip_wreck(w: Unit, u: Unit) -> void:
	w.stripped = true
	if w.loot is Dictionary and w.loot.get("rare", false):
		# V11: the crashed scout ship
		Run.meta.salvage = int(Run.meta.get("salvage", 0)) + Data.RARE_WRECK_SALVAGE
		bt.stats["salvage"] = int(bt.stats.get("salvage", 0)) + Data.RARE_WRECK_SALVAGE
		bt.float_text(w, "+%d SALVAGE" % Data.RARE_WRECK_SALVAGE, Color("9df25c"), true)
		bt.dust(w.x, w.y, Color("8a7a6a"), 6)
		Sfx.play("coin")
		bt.log_msg("%s strips the scout ship: +%d salvage." % [u.def.name, Data.RARE_WRECK_SALVAGE])
		return
	Run.meta.salvage = int(Run.meta.get("salvage", 0)) + Data.WRECK_SALVAGE
	bt.stats["salvage"] = int(bt.stats.get("salvage", 0)) + Data.WRECK_SALVAGE
	bt.float_text(w, "+%d SALVAGE" % Data.WRECK_SALVAGE, Color("53d4e2"), true)
	bt.dust(w.x, w.y, Color("8a7a6a"), 6)
	Sfx.play("coin")
	bt.log_msg("%s strips a wreck: +%d salvage for HQ." % [u.def.name, Data.WRECK_SALVAGE])

func check_detour() -> void:
	## Pays out a detour the moment its job is done.
	if bt.detour.is_empty() or bt.detour.done:
		return
	match bt.detour.id:
		"elite", "cache":
			if bt.units.any(func(e): return e.detour and e.team == "enemy" and not e.dead):
				return
		"pow":
			if bt.units.any(func(p): return p.detour and p.kind == "pow" and not p.freed):
				return
		"salvage":
			if bt.units.any(func(w): return w.kind == "wreck" and not w.stripped):
				return
		"signal":
			match bt.detour.ev:
				"tank":
					if bt.units.any(func(r): return r.detour and r.kind == "ride" and not r.gone):
						return
				"deserter":
					if bt.units.any(func(p): return p.detour and p.kind == "pow" and not p.freed):
						return
				_:
					if bt.units.any(func(e): return e.detour and e.team == "enemy" and not e.dead):
						return
		"colors":
			var post := colors_post()
			if not bt.squad_alive().any(func(s): return s.carry == "colors" and absf(s.x - post) < 34):
				return
			for s in bt.squad_alive():
				if s.carry == "colors":
					s.carry = ""
					s.move_left = minf(s.move_left, bt.full_move(s))
	bt.detour.done = true
	bt.busy = true
	await bt.wait(20)
	var cx: float = (bt.detour.x0 + bt.detour.x1) / 2.0
	match bt.detour.id:
		"elite":
			bt.banner("OUTPOST TAKEN!", Color("62d26f"), "EPIC GEAR + %d SALVAGE" % Data.ELITE_SALVAGE)
			bt.drop_loot(cx, bt.T.ground_at(cx) - 40, {"type": "item", "item": Run.roll_item(Data.TIER_MAX if Run.hq("armory") >= 3 else 3)})
			Run.meta.salvage = int(Run.meta.get("salvage", 0)) + Data.ELITE_SALVAGE
			bt.stats["salvage"] = int(bt.stats.get("salvage", 0)) + Data.ELITE_SALVAGE
			bt.log_msg("The outpost is ours: an Epic crate and %d salvage for HQ." % Data.ELITE_SALVAGE)
		"pow":
			var slots := Run.fallen_slots()
			if Run.campaign():
				slots = [-1] if Run.company_room() else []
			if slots.size():
				var o: Dictionary = Run.recruit_offers(1)[0]
				var s := Run.hire(slots[0], o)
				bt.banner("ALL PRISONERS FREE!", Color("62d26f"), "%s JOINS THE SQUAD AT HQ" % s.def.name)
				bt.log_msg("%s, a freed %s, signs up. They will be waiting at HQ%s." % [s.def.name, s.def.cls, ", with a training pick at the Barracks" if s.get("train", false) else ""])
			elif not Run.campaign() and Run.reserve.size() < Data.RESERVE_MAX:
				# the squad is full: the freed prisoner signs up and waits in the barracks
				var s := Run.make_recruit(Run.recruit_offers(1)[0])
				Run.reserve.append(s)
				bt.banner("ALL PRISONERS FREE!", Color("62d26f"), "%s WAITS IN THE BARRACKS" % s.def.name)
				bt.log_msg("%s, a freed %s, signs up and waits in the barracks. Swap them in at HQ, or parachute them in with a reinforcement flare." % [s.def.name, s.def.cls])
			else:
				var need: Array = bt.squad_alive().filter(func(u): return u.s.tags < Data.DOG_TAGS)
				need.sort_custom(func(a, b): return a.s.tags < b.s.tags)
				if need.size():
					need[0].s.tags += 1
					bt.banner("ALL PRISONERS FREE!", Color("62d26f"), "%s GETS A DOG TAG BACK" % need[0].def.name)
					bt.float_text(need[0], "+1 DOG TAG", Color("62d26f"), true)
				else:
					bt.banner("ALL PRISONERS FREE!", Color("62d26f"), "+50 SCRIP")
					bt.give_scrip(50, cx, bt.T.ground_at(cx) - 40, "L6738")
		"salvage":
			bt.banner("YARD STRIPPED!", Color("62d26f"), "%d SALVAGE FOR HQ" % int(bt.stats.get("salvage", 0)))
		"colors":
			Run.meta.salvage = int(Run.meta.get("salvage", 0)) + Data.COLORS_SALVAGE
			bt.stats["salvage"] = int(bt.stats.get("salvage", 0)) + Data.COLORS_SALVAGE
			bt.banner("COLORS CAPTURED!", Color("62d26f"), "%d SALVAGE FOR HQ" % Data.COLORS_SALVAGE)
			bt.log_msg("Their battle flag is ours: %d salvage for HQ." % Data.COLORS_SALVAGE)
		"signal":
			match bt.detour.ev:
				"tank":
					bt.banner("TANK DUG OUT!", Color("62d26f"), "IT'S YOURS TO DRIVE")
					bt.log_msg("The buried tank is ours.")
				"deserter":
					var p: Unit = bt.units.filter(func(p): return p.detour and p.kind == "pow")[0]
					var lu = bt.squad_alive().reduce(func(a, s): return s if a == null or absf(s.x - p.x) < absf(a.x - p.x) else a, null)
					bt.banner("THE DESERTER PAYS UP", Color("62d26f"), "A LEGENDARY ITEM")
					bt.drop_loot(p.x, bt.T.ground_at(p.x) - 40, {"type": "item", "item": Run.roll_item(Data.TIER_MAX)})
					bt.log_msg("The deserter hands over his best kit%s and slips away." % (" to %s" % lu.def.name if lu != null else ""))
				_:
					Run.meta.salvage = int(Run.meta.get("salvage", 0)) + Data.SIGNAL_SALVAGE
					bt.stats["salvage"] = int(bt.stats.get("salvage", 0)) + Data.SIGNAL_SALVAGE
					bt.banner("THE GATE GOES QUIET", Color("62d26f"), "%d SALVAGE" % Data.SIGNAL_SALVAGE)
					bt.log_msg("Picking through what came out of the gate: %d salvage for HQ." % Data.SIGNAL_SALVAGE)
		"cache":
			bt.banner("CACHE SECURED!", Color("62d26f"), "+80 SCRIP AND A CARD")
			bt.give_scrip(80, cx, bt.T.ground_at(cx) - 40, "L6748")
			await bt.wait(30)
			await bt.supply_drop("SUPPLY CACHE", null)
	Run.save_meta()
	Sfx.play("levelup")
	await bt.wait(40)
	bt.busy = false
	bt.ui_dirty = true

func detour_round() -> void:
	## After each enemy phase: the prisoner clock ticks and scavengers drift into the yard.
	if bt.detour.is_empty() or bt.detour.done:
		return
	if bt.detour.id == "pow":
		bt.detour.left -= 1
		var left: Array = bt.units.filter(func(p): return p.detour and p.kind == "pow" and not p.freed and not p.gone)
		if bt.detour.left <= 0:
			for p in left:
				p.gone = true
				bt.dust(p.x, p.y, Color("b9a27a"), 6)
			bt.detour.done = true
			bt.banner("THE PRISONERS ARE GONE", Color("ff7a3d"), "MOVED OUT BEFORE YOU GOT THERE")
			await bt.wait(40)
		else:
			for p in left:
				bt.float_text(p, "%d ROUND%s LEFT" % [bt.detour.left, "" if bt.detour.left == 1 else "S"], Color("ffb23e"), true)
	elif bt.detour.id == "salvage" and bt.detour.scav < 4 and bt.squad_alive().any(func(s): return s.x > bt.detour.x0 - 200) and bt.units.any(func(w): return w.kind == "wreck" and not w.stripped):
		var x := minf(bt.detour.x1 + 60, bt.cam_x + bt.W - 30)
		var e := bt.mk_enemy("grunt", x, bt.T.stand_y(x, 0))
		e.active = true; e.detour = true
		bt.units.append(e)
		bt.detour.scav += 1
		bt.float_text(e, "SCAVENGER", Color("ff7a3d"), true)

# ---------------------------------------------------------------- reinforcement flare: the barracks parachutes in
func downed_squad() -> Array:
	## Squad soldiers out of this fight (downed or killed) whose place a reinforcement can take.
	return bt.units.filter(func(u): return u.team == "squad" and u.dead and not u.gone and not u.s.has("guest"))

func flare_on_field() -> bool:
	return bt.units.any(func(o): return o.kind == "loot" and not o.gone and o.loot.type == "flare") or bt.para_queue.size() > 0

func roll_flare(force := false) -> Unit:
	## A new screen sometimes holds a reinforcement flare, but only while someone is down and
	## somebody waits in the barracks to answer it.
	if downed_squad().is_empty() or Run.barracks_pool().is_empty() or flare_on_field():
		return null
	if not force and randf() >= Data.FLARE_CHANCE:
		return null
	for k in 12:
		var x := bt.cam_x + bt.W * 0.45 + randf() * bt.W * 0.35
		var sy = bt.T.stand_y(x, bt.T.ceil_at(x) + 12 if bt.T.ceiling else 0)
		if sy == null or sy > bt.WATER_Y - 4:
			continue
		var f := bt.drop_loot(x, sy - 30.0, {"type": "flare"}, 0.3)
		bt.float_at(x, sy - 50.0, "REINFORCEMENT FLARE", Color("62d26f"), true)
		bt.log_msg("A reinforcement flare up ahead. Grab it to parachute soldiers in from the barracks.")
		return f
	return null

func call_reinforcements(u: Unit) -> void:
	## The flare is lit: pick soldiers from the barracks, one for each soldier who is down. Each
	## jumps in under a chute and takes a downed soldier's place in the squad; the downed go home
	## to the barracks to recover (the killed go to the Memorial as usual).
	var downed := downed_squad()
	downed.sort_custom(func(a, b): return not a.downed and b.downed)  # the killed make room first
	var pool := Run.barracks_pool()
	if downed.is_empty() or pool.is_empty():
		bt.float_text(u, "NOBODY TO CALL IN", Color("9aa2ae"))
		return
	var picked: Array = []
	var n := mini(downed.size(), pool.size())
	while picked.size() < n:
		var takes: Unit = downed[picked.size()]
		var left: Array = pool.filter(func(s): return not picked.has(s))
		if Run.campaign():
			# a campaign squad is one of each class: the bench sends someone whose class isn't already in it
			var taken: Array = Run.soldiers.filter(func(o): return o != takes.s).map(func(o): return Run.slot_key(o)) + picked.map(func(o): return Run.slot_key(o))
			left = left.filter(func(s): return not taken.has(Run.slot_key(s)))
			if left.is_empty():
				break
		var opts: Array = left.slice(0, 6).map(func(s): return {"kind": "service", "title": "PARADROP", "soldier": s,
			"name": s.def.name.to_upper(), "text": "LV %d %s. %d HP, %d dog tag%s." % [s.lvl, s.def.cls.to_upper(), Run.eff_max_hp(s), s.tags, "" if s.tags == 1 else "s"]})
		var ch := await bt.ask("reinforce", "CALL IN REINFORCEMENTS  %d OF %d" % [picked.size() + 1, n],
			"Who jumps in for %s? %s" % [takes.def.name, "%s goes home to the barracks to recover." % takes.def.name if takes.downed else "They take the fallen soldier's place."], opts)
		if ch < 0:
			break
		picked.append(left[ch])
	if picked.is_empty():
		bt.log_msg("The flare burns out. Nobody jumps.")
		return
	bt.busy = true
	bt.banner("REINFORCEMENTS!", Color("62d26f"), "%d SOLDIER%s INBOUND" % [picked.size(), "" if picked.size() == 1 else "S"])
	Sfx.play("start")
	for k in picked.size():
		var out: Unit = downed[k]
		evacuate(out)
		var s: Dictionary = picked[k]
		Run.swap_in(s, out.s)
		var x := clampf(u.x - 30 + k * 34, bt.cam_x + 30, bt.cam_x + bt.W - 30)
		var nu := bt.deploy_unit(s, x)
		nu.face = 1
		nu.energy = 0
		nu.move_left = 0
		if not bt.T.ceiling and s.def.key != "gears":
			# under a chute from above the screen; Gears' walker and tunnel levels just walk in
			nu.y = -30.0 - k * 40
			nu.air = true
			nu.para = true
			nu.vy = 0.0
		bt.float_text(nu, "REPORTING IN", Color("62d26f"), true)
		bt.log_msg("%s jumps in for %s." % [s.def.name, out.def.name])
	bt.ui_dirty = true
	for i in 300:
		if not bt.units.any(func(o): return o.team == "squad" and o.para and not o.gone):
			break
		await bt.wait(1)
	await bt.until(bt.settled)
	await bt.wait(20)
	bt.busy = false
	bt.ui_dirty = true

func evacuate(out: Unit) -> void:
	## A downed soldier is flown out to the barracks (or a killed one taken off the field), so the
	## squad never holds more than four.
	if out.downed:
		out.s.hp = int(ceil(Run.eff_max_hp(out.s) / 2.0))
	else:
		out.s.alive = false
		out.s.hp = 0
		Run.memorialize(out.s)
	out.gone = true
	out.team = "evac"
	for o in bt.units:
		if o.kind == "dog" and o.loot.get("by") == out:
			o.gone = true  # Rex goes home with Track
	if bt.sel == out:
		var al := bt.squad_alive()
		bt.sel = al[0] if al.size() else null
		bt.card_idx = -1

func sweep_loot(edge: float) -> void:
	## Loot the squad left behind (or that sank) goes straight to the global inventory (L8).
	var n := 0
	for u in bt.units:
		if u.kind == "loot" and not u.gone and (u.x < edge or u.sunk):
			u.gone = true
			stash_payload(u.loot)
			n += 1
	if n:
		bt.log_msg("%d item%s left behind went to the stash." % [n, "s" if n > 1 else ""])

func stash_payload(p: Dictionary) -> void:
	match p.type:
		"item":
			Run.add_loot(p.item)
			bt.stats.loot += 1
		"scrip":
			Run.scrip += p.n
			bt.stats.scrip += p.n
			if bt.debug:
				print("[scrip] %d stash" % p.n)
		"relic":
			Run.add_gear(p.id, Data.TIER_MAX)
		"trophy":
			if not Run.trophies.has(p.name):
				Run.trophies.append(p.name)

func drag_stragglers() -> void:
	var al := bt.squad_alive()
	for s in al:
		var lane := bt.cam_x + 16 + al.find(s) * 40
		if s.x >= lane or s.zip != null:
			continue
		s.walk = null
		var nx := lane
		var ny = null
		var k := 0
		while k < 60 and ny == null:
			# look from just above the straggler first; one stuck low in a pit or a drill bore would
			# only find solid ground under the lane there, so then look from higher up
			for lift in [60.0, 160.0, 260.0, 400.0]:
				ny = bt.T.stand_y(nx, maxf(0, s.y - lift))
				if ny != null and bt.biome_rules.mine_under(s, nx, ny, 6) != null:
					ny = null  # never drop a straggler onto an armed mine
				if ny != null:
					break
			if ny == null:
				nx += 4
			k += 1
		if ny != null:
			s.x = nx; s.y = ny; s.air = false; s.vx = 0; s.vy = 0
			if not s.dragged:
				s.dragged = true
				bt.float_text(s, "KEEP UP!", Color("e8dcc2"))

func activate_enemies() -> void:
	for e in bt.units:
		if e.team != "enemy" or e.dead or e.active:
			continue
		if bt.in_play(e.x, 40) or (e.fl.get("hunt", false) and e.x < bt.cam_x + bt.W + 700):
			e.active = true
			bt.meet(e)
			if e.fl.get("lead", false):
				bt.banner("YOU ARE BEING HUNTED", Color("c47bff"), "AN ELITE %s IS STALKING THE SQUAD" % Data.ETYPES[e.type].name.to_upper())
				Sfx.play("alarm")
				bt.log_msg("Something elite is tracking you through this stretch. Bring it down: it pays like an elite outpost.")
			if e.type == "vgate":
				bt.banner("VHARR GATE!", Color("c47bff"), "ONE ALIEN COMES THROUGH EVERY TURN")
				Sfx.play("alarm")
				bt.log_msg("A Vharr gate is open ahead. Blast it, or drop something heavy on it.")
			if e.fl.get("outbreak", false):
				bt.banner("THRALL OUTBREAK", Color("9df25c"), "AN OVERSEER IS TAKING THE JACKAL CAMP")
				bt.log_msg("An Overseer is turning that Jackal camp into Thralls, one a turn. Kill it fast and the rest turn on the Vharr.")
			if e.type == "radio" and bt.radio_t == null:
				bt.radio_t = 3 + bt.jammer_rounds()
				bt.log_msg("A radioman is calling for backup. Paratroopers in %d rounds unless you drop him." % bt.radio_t)
			if e.type == "queen":
				bt.banner("WARNING!!", Color("c47bff"), "THE BURROW QUEEN STIRS")
				Sfx.play("alarm")
				bt.log_msg("Something huge is moving under the sand. Only blasts reach her down there: hit her when she surfaces, and bring the ruins down on her head.")
			if e.type == "hiveship" and not bt.boss_active:
				bt.boss_active = true
				bt.banner("WARNING!!", Color("c47bff"), "HIVE SHIP OVERHEAD")
				Sfx.play("alarm")
				bt.log_msg("A Vharr HIVE SHIP blots out the sky. Shoot its hull plates off the tethers and drop them on whatever is under it. Blasts in its belly always hurt.")
			if e.type == "boss" and not bt.boss_active:
				bt.boss_active = true
				if e.fl.get("vharr", false):
					bt.banner("WARNING!!", Color("c47bff"), "VHARR BOAR APPROACHING")
					bt.log_msg("The flagship BOAR rolls in refit with Vharr tech: a dome over the turret and a tongue. Crushing and melee go through the dome.")
				else:
					bt.banner("WARNING!!", Color("ff4d3d"), "ROOKIE BOAR APPROACHING" if e.fl.get("rookie", false) else "%s APPROACHING" % Data.BOAR_KITS.get(bt.mission.get("boar_kit", ""), Data.BOAR_KITS.standard).name)
					bt.log_msg("The IRON BOAR rolls in. Something heavy is hanging over it...")
				Sfx.play("alarm")
	bt.mid_events.rare_check()  # P3

# ---------------------------------------------------------------- O2-O6: campaign op jobs
func job_spot(x: float) -> float:
	## Nearest dry, pit-free ground to x, for a prisoner, a dump or the truck.
	for k in 40:
		for sx in [x + k * 16.0, x - k * 16.0]:
			if sx > 160 and sx < bt.world_w - 60 and bt.T.stand_y(sx, bt.T.ground_at(sx) - 40) != null and not bt.T.pits.any(func(p): return sx > p[0] - 24 and sx < p[1] + 24):
				return sx
	return x

func trap_varga() -> void:
	## T6: on his last stand the colonel starts deep in the fort, pinned down with his garrison. He
	## can't act until someone reaches him; if he falls before that, he fell.
	if bt.mission.get("story", "") != "varga":
		return
	for u in bt.squad():
		if u.s.get("guest", "") != "varga":
			continue
		var x := job_spot(bt.world_w * 0.7 + 40)
		var y = bt.T.stand_y(x, bt.T.ground_at(x) - 40)
		if y == null:
			return
		u.x = x; u.y = y; u.face = -1
		u.trapped = true
		bt.log_msg("Colonel Varga is pinned down deep in the fort with his men. Fight through to him and he joins the fight.")

func free_varga() -> void:
	## T6: a squadmate close enough to the colonel breaks him out.
	for v in bt.squad_alive():
		if not v.trapped:
			continue
		if bt.squad_alive().any(func(o): return o != v and not o.trapped and absf(o.x - v.x) < 180 and absf(o.y - v.y) < 140):
			v.trapped = false
			v.face = -1
			bt.float_text(v, "ABOUT TIME, IRON COMPANY", Color("ff7a3d"), true)
			bt.log_msg("Colonel Varga is out. He fights with you from here.")
			Sfx.play("select")
			bt.ui_dirty = true

func place_job() -> void:
	## Lays out the op's objective: prisoners, supply dumps, the truck or the marked officer.
	match bt.job():
		"rescue":
			# F4: on the Flooded Delta the prisoners are held 15% nearer the landing zone
			var near: float = 0.85 if bt.mission.get("biome", "") == "delta" else 1.0
			for f in [0.45, 0.7, 0.9]:
				var x := job_spot(bt.world_w * f * near)
				var u := bt.mk_unit(); u.team = "neutral"; u.kind = "pow"; u.x = x; u.y = bt.T.stand_y(x, bt.T.ground_at(x) - 40); u.face = -1
				u.pow_name = Data.POW_NAMES[randi() % Data.POW_NAMES.size()]
				u.fl["job"] = true
				bt.stats.pows_total += 1
				bt.units.append(u)
		"demolish":
			for f in [0.4, 0.65, 0.9]:
				var x := job_spot(bt.world_w * f)
				var u := bt.mk_unit(); u.team = "neutral"; u.kind = "dump"; u.x = x; u.y = bt.T.stand_y(x, bt.T.ground_at(x) - 40); u.w = 30; u.h = 24
				u.hp = Data.TARGET_HP; u.max_hp = u.hp; u.heavy = true; u.immovable = true
				bt.units.append(u)
		"escort":
			var x := job_spot(275.0)  # just ahead of the squad line (50-215), so nobody deploys hidden behind it
			var u := bt.mk_unit(); u.team = "neutral"; u.kind = "truck"; u.x = x; u.y = bt.T.stand_y(x, bt.T.ground_at(x) - 40); u.w = 56; u.h = 32; u.face = 1
			u.hp = Data.TRUCK_HP; u.max_hp = u.hp; u.heavy = true; u.immovable = true
			bt.units.append(u)
		"hunt":
			var foes := bt.units.filter(func(e): return e.team == "enemy" and not e.dead and e.type != "boss" and e.type != "hiveship" and e.type != "queen")
			foes.sort_custom(func(a, b): return a.x > b.x)
			if foes.is_empty():
				return
			var q: Unit = foes[0]
			if q.elite == "":
				bt.make_elite(q, bt.pick_elite(bt.faction(q) == "vharr"))
			q.hp *= 2
			q.max_hp = q.hp
			var taken: Array = Run.camp.get("nemeses", []).map(func(n): return n.name) if Run.campaign() else []
			var names: Array = Data.QUARRY_NAMES.filter(func(n): return not taken.has(n))
			q.fl["quarry"] = (names if names.size() else Data.QUARRY_NAMES)[randi() % (names.size() if names.size() else Data.QUARRY_NAMES.size())]
		"hold":
			bt.job_st = {"on": false, "left": Data.HOLD_PHASES}

func place_nemesis() -> void:
	## W3: an officer who got away on an earlier op is back: the farthest foe, with a new elite trick
	## and more health for every escape. WANTED over their head like a hunt's target.
	var nem: Dictionary = bt.mission.get("nemesis", {})
	if nem.is_empty():
		return
	var foes := bt.units.filter(func(e): return e.team == "enemy" and not e.dead and not bt.is_boss(e) and not e.fl.has("quarry") and e.type != "radio" and not Data.ETYPES[e.type].get("static", false))
	if foes.is_empty():
		return
	foes.sort_custom(func(a, b): return a.x > b.x)
	var q: Unit = foes[0]
	var tricks := Data.ELITES.keys().filter(func(k): return Data.ELITES[k].get("vharr", false) == (bt.faction(q) == "vharr") and k != str(nem.get("elite", "")))
	bt.make_elite(q, tricks[randi() % tricks.size()] if tricks.size() else bt.pick_elite(bt.faction(q) == "vharr"))
	q.hp = int(q.hp * (2.0 + Data.NEMESIS_HP * int(nem.rank)))
	q.max_hp = q.hp
	q.fl["quarry"] = Run.nemesis_name(nem)
	q.fl["nemesis"] = nem.name
	bt.stats["nemesis"] = Run.nemesis_name(nem)

func truck():
	for u in bt.units:
		if u.kind == "truck":
			return u
	return null

func job_left() -> String:
	## The HUD line for the op's objective, or "" on a push.
	match bt.job():
		"rescue":
			var n := bt.units.filter(func(p): return p.fl.get("job", false) and p.freed).size()
			return "RESCUE: %d OF 3 PRISONERS FREE" % n
		"demolish":
			return "DEMOLISH: %d OF 3 DUMPS DOWN" % (3 - bt.units.filter(func(d): return d.kind == "dump" and not d.dead).size())
		"hold":
			if bt.job_st.get("on", false):
				return "HOLD: %d MORE ENEMY PHASE%s" % [int(bt.job_st.left), "" if int(bt.job_st.left) == 1 else "S"]
			return "HOLD: REACH THE FAR END"
		"escort":
			var tr = truck()
			if tr == null:
				return ""
			return "ESCORT: TRUCK %d/%d HP, %d%% OF THE WAY" % [maxi(0, tr.hp), tr.max_hp, int(clampf(tr.x / (bt.world_w - 150.0), 0, 1) * 100)]
		"hunt":
			for e in bt.units:
				if e.fl.has("quarry"):
					return "HUNT: %s %s" % [e.fl.quarry, "IS DOWN" if e.dead else ("SPOTTED" if e.active else "IS OUT THERE")]
	return ""

func job_done() -> bool:
	match bt.job():
		"rescue":
			return not bt.units.any(func(p): return p.fl.get("job", false) and p.kind == "pow" and not p.freed)
		"demolish":
			return not bt.units.any(func(d): return d.kind == "dump" and not d.dead)
		"hold":
			return bt.job_st.get("on", false) and int(bt.job_st.left) <= 0
		"escort":
			var tr = truck()
			return tr != null and not tr.dead and tr.x >= bt.world_w - 150
		"hunt":
			return not bt.units.any(func(e): return e.fl.has("quarry") and not e.dead)
	return false

func job_ends() -> bool:
	## Wins the op when its job is done, or fails it when the truck is lost. True if the battle is over.
	if bt.job() == "push" or bt.won or bt.lost:
		return false
	var tr = truck()
	if tr != null and tr.dead:
		bt.lost = true
		bt.state = "over"
		bt.busy = true
		bt.banner("THE TRUCK IS GONE", Color("ff4d3d"), "OP FAILED. THE SQUAD FALLS BACK")
		Sfx.play("bad")
		bt.sync_back()
		await bt.wait(110)
		bt.mission_over.emit(false)
		return true
	if job_done():
		await bt.until(bt.settled)
		await bt.flush_rewards()
		bt.victory()
		return true
	return false

func start_hold() -> void:
	## O4: the hold starts once the squad stands at the far end of the map.
	if bt.job() != "hold" or bt.job_st.get("on", false) or bt.cam_x < bt.world_w - bt.W - 2:
		return
	if not bt.squad_alive().any(func(s): return s.x > bt.world_w - bt.W * 0.6):
		return
	bt.job_st.on = true
	bt.banner("HOLD THE LINE!", Color("ffd23a"), "SURVIVE %d ENEMY PHASES. THEY COME FROM BOTH SIDES" % int(bt.job_st.left))
	Sfx.play("alarm")

func hold_waves() -> void:
	## O4: while holding, Jackals come in from both edges at the start of every enemy phase.
	if bt.job() != "hold" or not bt.job_st.get("on", false) or int(bt.job_st.left) <= 0:
		return
	var xs := [minf(bt.world_w - 20.0, bt.cam_x + bt.W - 30), minf(bt.world_w - 42.0, bt.cam_x + bt.W - 52), bt.cam_x + 30]
	for i in xs.size():
		var px: float = xs[i]
		var y = bt.T.stand_y(px, bt.T.ground_at(px) - 40)
		if y == null:
			continue
		var e := bt.mk_enemy("nade" if i == 1 and bt.mission_idx >= 2 else "grunt", px, y)
		e.active = true
		bt.units.append(e)
	bt.float_at(bt.cam_x + bt.W / 2.0, 90, "THEY'RE COMING!", Color("ff7a3d"), true)

func job_round() -> void:
	## After each enemy phase: the hold clock ticks, and the truck takes fire and rolls on.
	match bt.job():
		"hold":
			if bt.job_st.get("on", false) and int(bt.job_st.left) > 0:
				bt.job_st.left = int(bt.job_st.left) - 1
				if int(bt.job_st.left) > 0:
					bt.banner("HOLDING", Color("ffd23a"), "%d MORE ENEMY PHASE%s" % [int(bt.job_st.left), "" if int(bt.job_st.left) == 1 else "S"])
					await bt.wait(30)
		"escort":
			var tr = truck()
			if tr == null or tr.dead:
				return
			# Jackals right next to the truck shoot it up
			for e in bt.units.filter(func(e): return e.team == "enemy" and not e.dead and e.active and absf(e.x - tr.x) < 90).slice(0, 3):
				bt.damage(tr, 4, e)
			if tr.dead:
				return
			if bt.units.any(func(e): return e.team == "enemy" and not e.dead and e.x > tr.x and e.x - tr.x < 260 and e.x < bt.cam_x + bt.W + 40):
				bt.float_text(tr, "BLOCKED: CLEAR THE ROAD", Color("ffb23e"), true)
				await bt.wait(20)
				return
			var nx := minf(tr.x + Data.TRUCK_STEP, minf(bt.cam_x + bt.W - 70, bt.world_w - 60.0))
			var ford := false
			while nx < bt.world_w - 60 and not truck_road(nx, tr.y):
				nx += 16  # rolls over a hole or open water to the far side
				ford = true
			if nx <= tr.x + 4 or (nx > bt.cam_x + bt.W - 30 and not ford):
				bt.float_text(tr, "WAITING FOR THE SQUAD", Color("9fb4c9"))
				await bt.wait(20)
				return
			bt.float_text(tr, "ROLLING", Color("62d26f"))
			bt.rounds_since_scroll = 0  # the truck sets the pace on an escort: while it rolls, the line isn't stalled
			var x0: float = tr.x
			for i in 20:
				tr.x = lerpf(x0, nx, (i + 1) / 20.0)
				var y = bt.T.stand_y(tr.x, bt.T.ground_at(tr.x) - 40)
				if y != null:
					tr.y = y
				tr.anim += 1
				await bt.wait(1)

func truck_road(x: float, from_y: float) -> bool:
	## Somewhere the truck can stand: dry, and not down in a hole well below where it is now.
	var y = bt.T.stand_y(x, bt.T.ground_at(x) - 40)
	return y != null and y < from_y + 40

func job_reward() -> void:
	## A finished job pays on top of the usual: scrip, plus a recruit, a crate or a trophy.
	var j := bt.job()
	if bt.mission.get("bonus", "") != "":
		# W6: each kind of bonus op pays its own way
		match str(Data.BONUS_OPS[bt.mission.bonus].get("pay", "epic")):
			"salvage":
				Run.meta.salvage = int(Run.meta.get("salvage", 0)) + Data.BONUS_SALVAGE
				bt.stats["salvage"] = int(bt.stats.get("salvage", 0)) + Data.BONUS_SALVAGE
				bt.log_msg("The yard's parts are ours: %d Salvage for HQ." % Data.BONUS_SALVAGE)
			"defector":
				if Run.company_room():
					var used: Array = Run.roster.map(func(x): return x.def.name)
					var names: Array = Data.CALLSIGNS.filter(func(c): return not used.has(c))
					var d := Run.enlist(Run.spec_offer("defector", names[randi() % names.size()] if names.size() else "TURNCOAT"))
					bt.log_msg("%s, a Jackal Defector, signs up with the company." % d.def.name)
				else:
					Run.meta.salvage = int(Run.meta.get("salvage", 0)) + Data.BONUS_SALVAGE
					bt.stats["salvage"] = int(bt.stats.get("salvage", 0)) + Data.BONUS_SALVAGE
					bt.log_msg("The company is full, so the defectors hand over %d Salvage instead." % Data.BONUS_SALVAGE)
			"crash":
				bt.log_msg("The wreck is held. Every alien killed here counts double at the Alien Lab.")
			_:
				var bx: float = bt.squad_alive()[0].x if bt.squad_alive().size() else bt.cam_x + bt.W / 2.0
				bt.drop_loot(bx, bt.T.ground_at(bx) - 40, {"type": "item", "item": Run.roll_item(3)})
				bt.stats["bonus_gear"] = true
	if j == "push":
		return
	Run.scrip += Data.JOB_PAY
	bt.stats.scrip += Data.JOB_PAY
	bt.stats["job_pay"] = Data.JOB_PAY
	match j:
		"rescue":
			if Run.campaign() and Run.company_room():
				var s := Run.enlist(Run.recruit_offers(1)[0])
				bt.stats["job_note"] = "%s, one of the freed prisoners, joins the company." % s.def.name
		"hunt":
			for e in bt.units:
				if e.fl.has("quarry"):
					bt.drop_loot(e.x, e.y - 20, {"type": "item", "item": Run.roll_item(3)})
					bt.stats["job_note"] = "%s carried Epic gear." % e.fl.quarry
		"escort":
			Run.meta.salvage = int(Run.meta.get("salvage", 0)) + 2
			bt.stats["salvage"] = int(bt.stats.get("salvage", 0)) + 2
			bt.stats["job_note"] = "The truck brought 2 salvage home."
		"demolish", "hold":
			var tk := Data.ELITE_SALVAGE
			Run.meta.salvage = int(Run.meta.get("salvage", 0)) + tk
			bt.stats["salvage"] = int(bt.stats.get("salvage", 0)) + tk
			bt.stats["job_note"] = "%d salvage from the field." % tk

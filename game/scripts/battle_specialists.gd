class_name BattleSpecialists
extends RefCounted
## Specialist soldiers' kits and the fifth skill branches.
## Split out of battle.gd (R3). Functions only: every piece of mission state lives on the Battle,
## reached through `bt`.

var bt: Battle

func _init(battle: Battle) -> void:
	bt = battle

# ---------------------------------------------------------------- N2 Bolt: building into the terrain
func build_scale(u) -> float:
	## Toolbelt: everything Bolt builds is 50% bigger.
	return 1.5 if u is Unit and u.team == "squad" and u.def.key == "bolt" else 1.0

func is_build(c: Dictionary) -> bool:
	return c.has("build") or c.get("girder", false)

func clear_of_units(x: float, y: float) -> bool:
	for o in bt.units:
		if o.dead or o.gone or o.sunk or o.is_pickup() or o.kind == "rivet":
			continue
		if x >= o.x - o.w / 2.0 - 1 and x <= o.x + o.w / 2.0 + 1 and y >= o.y - o.h - 1 and y <= o.y + 1:
			return false
	return true

func build_cells(x: float, y: float, w: float, h: float, m: int) -> Array:
	## Fills empty cells of a rectangle, never on top of a body. Returns the cell indices it set.
	var out: Array = []
	for cy in range(int(floor(y / bt.CELL)), int(ceil((y + h) / bt.CELL))):
		for cx in range(int(floor(x / bt.CELL)), int(ceil((x + w) / bt.CELL))):
			if cx < 0 or cy < 0 or cx >= bt.T.cols or cy >= Terrain.ROWS or cy * bt.CELL >= bt.WATER_Y:
				continue
			if bt.T.grid[cy * bt.T.cols + cx] != 0 or not clear_of_units(cx * bt.CELL + 2.0, cy * bt.CELL + 2.0):
				continue
			bt.T.set_cell(cx, cy, m)
			out.append(cy * bt.T.cols + cx)
	return out

func build_wall(u, x: float, gy: float, w: float, h: float) -> void:
	var m := 4 if u is Unit and u.perk("concrete") else 1
	var cells := build_cells(x - w / 2.0, gy - h, w, h, m)
	if cells.size():
		bt.walls.append(Rect2(x - w / 2.0, gy - h, w, h))
		for k in 5:
			bt.puff(x + randf_range(-w / 2.0, w / 2.0), gy - randf_range(0, h), 1.5)

func build_at(p: Dictionary) -> void:
	## A thrown build card landed (Sandbags, Sentry Gun, Jump Pad).
	var u = p.owner
	var pc: Dictionary = p.card
	var sc := build_scale(u)
	var gy = bt.T.stand_y(p.x, p.y - 30)
	if gy == null:
		bt.float_at(p.x, p.y - 10, "SPLASH", Color("9aa2ae"))
		return
	match pc.build:
		"wall":
			var big := 2.0 if bt.ks(u, "rebar") else 1.0
			build_wall(u, p.x, gy, pc.bw * sc * big, pc.bh * sc * big)
			bt.float_at(p.x, gy - pc.bh * sc - 10, "SANDBAGS", Color("c9b38a"))
			Sfx.play("land")
		"sentry":
			var n := 2 if u is Unit and u.perk("secondsentry") else 1
			for k in n:
				var sx: float = p.x + (k - (n - 1) / 2.0) * 26.0
				var sy = bt.T.stand_y(sx, gy - 30)
				if sy != null:
					make_sentry(u, sx, sy, int(round(pc.shp * sc)), pc.sdmg)
			Sfx.play("select")
		"pad":
			var w: float = pc.pw * sc
			for cx in range(int(floor((p.x - w / 2.0) / bt.CELL)), int(ceil((p.x + w / 2.0) / bt.CELL))):
				var ty = bt.T.stand_y(cx * bt.CELL + 2.0, gy - 24)
				if ty != null and absf(ty - gy) < 24:
					bt.T.set_cell(cx, int(ty / bt.CELL), Terrain.RUBBER)
			bt.T.tarps.append([p.x - w / 2.0, p.x + w / 2.0])
			bt.float_at(p.x, gy - 14, "JUMP PAD", Color("ff9a3d"))
			Sfx.play("bonk")
	after_build(u)

func after_build(u) -> void:
	## Scrapper perks and the Magnet Glove keystone pay out on every build.
	if not (u is Unit) or u.team != "squad" or u.dead:
		return
	if u.perk("scraparmor"):
		u.armor += 3
		bt.float_text(u, "+3 ARMOR", Color("9fb4c9"))
	if u.perk("recycler"):
		bt.draw_cards(u, 1)
	bt.ui_dirty = true

func make_sentry(u, x: float, y: float, hp: int, dmg: Array) -> Unit:
	var st := bt.mk_unit()
	st.team = "ally"; st.kind = "sentry"; st.x = x; st.y = y; st.w = 16; st.h = 20; st.heavy = true
	st.hp = hp; st.max_hp = hp; st.face = 1
	st.loot = {"by": u, "dmg": dmg}
	bt.units.append(st)
	if u != null:
		bt.puff(x, y - 8, 1.5)
		bt.float_at(x, y - 30, "SENTRY UP", Color("62d26f"))
	return st

func sentry_target(st: Unit):
	## The nearest Jackal (or Vharr) the sentry can see, within 520px. Drawn as its laser.
	var best = null
	var bd := 520.0
	for e in bt.units:
		if e.team != "enemy" or e.dead or e.gone or e.sunk or e.weight == "buried" or e.has_st("cloak"):
			continue
		var d := Vector2(e.x - st.x, e.y - st.y).length()
		if d < bd and not los_blocked(st.x, st.y - 14, e.x, e.y - e.h * 0.55):
			best = e
			bd = d
	return best

func los_blocked(x0: float, y0: float, x1: float, y1: float) -> bool:
	var L := Vector2(x1 - x0, y1 - y0).length()
	for k in range(8, int(L), 6):
		if bt.T.hard(x0 + (x1 - x0) * k / L, y0 + (y1 - y0) * k / L):
			return true
	return false

func sentry_fire(st: Unit) -> void:
	var tg = sentry_target(st)
	if tg == null:
		return
	var by = st.loot.by
	var ksc: bool = bt.ks(by, "turretcore")
	var dmg: Array = st.loot.dmg
	if ksc:
		dmg = [dmg[0] + 2, dmg[1] + 2]
	var shots := 2 if by is Unit and by.perk("twinbarrel") else 1
	for k in shots:
		if tg.dead:
			tg = sentry_target(st)
			if tg == null:
				break
		var mx := st.x
		var my := st.y - 14
		st.face = 1 if tg.x >= st.x else -1
		# make every burst obvious, hit or miss: a callout over the turret, a fat orange tracer,
		# and MISS over the target when nothing landed
		if k == 0:
			bt.float_at(st.x, st.y - 34, "SENTRY FIRES", Color("ff9a3d"))
			await bt.wait(10)
		st.muzzle = 10
		Sfx.play("mg")
		var hp0: int = tg.hp
		var ang := atan2(tg.y - tg.h * 0.55 - my, tg.x - mx)
		var tr := bt.trace_bullet(mx, my, ang, 560, 0, by if by is Unit else st, ksc)
		for sg in tr.segs:
			bt.tracers.append({"x1": sg[0], "y1": sg[1] - 1, "x2": sg[2], "y2": sg[3] - 1, "c": Color("ff9a3d"), "t": 22})
			bt.tracers.append({"x1": sg[0], "y1": sg[1] + 1, "x2": sg[2], "y2": sg[3] + 1, "c": Color("ff9a3d"), "t": 22})
		bt.fire_bullet(by if by is Unit else st, mx, my, ang, {"dmg": dmg, "range": 560, "bounce": 0, "pierce": ksc}, false)
		bt.sparks(mx + st.face * 20, my - 1, 5)
		if not tg.dead and tg.hp >= hp0:
			bt.float_text(tg, "SENTRY MISSED", Color("c9d1da"))
		await bt.wait(16)

func sentries_fire() -> void:
	var sts := bt.units.filter(func(o): return o.kind == "sentry" and not o.dead and not o.gone and not o.loot.get("pinned", false))
	if sts.is_empty():
		return
	for st in sts:
		await sentry_fire(st)
	await bt.until(bt.settled)

func _act_girder(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	bt.spend_card(u, idx, c)
	var reach: float = c.reach * (2.0 if u.perk("longspan") else 1.0)
	var from := Vector2(u.x, u.y - 22)
	var d := p - from
	var L := minf(d.length(), reach)
	var dir := d.normalized() if d.length() > 0.1 else Vector2(u.face, 0)
	var at := from + dir * L
	for k in range(8, int(L), 4):
		var q := from + dir * k
		if bt.T.hard(q.x, q.y):
			at = from + dir * maxf(0, k - 6)
			break
	u.face = 1 if at.x >= u.x else -1
	u.pose = "throw"; u.pose_t = 18
	Sfx.play("toss")
	bt.ropes.append({"u": u, "x": at.x, "y": at.y, "t": 14})
	await bt.wait(10)
	var w: float = c.gw * build_scale(u) * (1.5 if u.perk("longspan") else 1.0)
	var th := 16.0 if u.perk("heavysteel") or bt.ks(u, "rivetdriver") else 8.0
	var cells := build_cells(at.x - w / 2.0, at.y, w, th, 2)
	if cells.is_empty():
		bt.float_at(at.x, at.y - 10, "NO ROOM", Color("ff7a3d"))
		return
	var rv := bt.mk_unit()
	rv.team = "neutral"; rv.kind = "rivet"; rv.x = at.x; rv.y = at.y + 4; rv.w = 10; rv.h = 10; rv.hp = 1; rv.max_hp = 1
	rv.loot = {"cells": cells, "by": u, "w": w, "turn": bt.round_n}
	for i in cells:
		bt.T.pins[i] = rv.id
	bt.units.append(rv)
	Sfx.play("ping")
	bt.sparks(at.x, at.y, 6)
	bt.float_at(at.x, at.y - 14, "GIRDER", Color("c9d1da"))
	after_build(u)
	if u.perk("piledriver") and bt.units.any(func(e): return e.team == "enemy" and not e.dead and absf(e.x - at.x) < w / 2.0 + 6 and e.y > at.y and e.y - at.y < 260):
		await bt.wait(16)
		drop_girder(rv, u)

func drop_girder(rv: Unit, by) -> void:
	## The bolt is shot out: unpin the beam and let the terrain drop it as a falling chunk.
	if rv.dead:
		return
	rv.dead = true
	rv.gone = true
	for i in rv.loot.cells:
		if bt.T.pins.get(i, -1) == rv.id:
			bt.T.pins.erase(i)
	var by_u = rv.loot.by if rv.loot.by is Unit else by
	bt.sparks(rv.x, rv.y, 8)
	Sfx.play("ping")
	bt.float_at(rv.x, rv.y - 12, "BOLT SHOT!", Color("ffd23a"), true)
	if by_u is Unit and by_u.team == "squad" and by_u.def.key == "bolt" and rv.loot.turn == bt.round_n and bt.state == "player" and not by_u.fl.has("cutloose"):
		by_u.fl["cutloose"] = true
		bt.chain(by_u, "CUT LOOSE")
		by_u.energy += 1
	bt.T.check_floating(rv.x, rv.y + 4, rv.loot.w / 2.0 + 12, by_u)

func steel_rain(x: float, n: int, by) -> void:
	## Steel Rain / Demo Team: girders appear high over the marker and fall.
	bt.banner("STEEL RAIN!", Color("c9d1da"))
	Sfx.play("alarm")
	if bt.vfx != null:
		# V17: a red beacon marks where the girders come down
		var by_y = bt.T.stand_y(x, 0)
		bt.vfx.add(SfPillar.new(x, by_y if by_y != null else bt.WATER_Y, 0.9, 6.0 + n * 3.0, 0.2))
	for k in n:
		var gx := x + (k - (n - 1) / 2.0) * 44.0
		var gy := 20.0 + (k % 2) * 16.0
		var cells := build_cells(gx - 22, gy, 44, 12, 2)
		if cells.size():
			bt.T.check_floating(gx, gy + 6, 34, by)

func scrap_heap(x: float, y: float, by) -> void:
	## Junk Cannon: the scrap lands as a heap of steel.
	var gy = bt.T.stand_y(x, y - 40)
	if gy != null:
		build_cells(x - 20, gy - 14, 40, 14, 2)

func fortify(u: Unit, c: Dictionary) -> void:
	## Fortify / Iron Curtain / Build Crew: armor for the squad nearby and a wall in front of each.
	bt.banner("FORTIFY!", Color("c9d1da"))
	Sfx.play("power")
	var foe = null
	for e in bt.units:
		if e.team == "enemy" and not e.dead and (foe == null or absf(e.x - u.x) < absf(foe.x - u.x)):
			foe = e
	var dir := 1.0 if foe == null or foe.x >= u.x else -1.0
	if c.get("curtain", false):
		var cx := u.x + dir * 60.0
		if foe != null:
			cx = (u.x + foe.x) / 2.0
		var gy = bt.T.stand_y(cx, 0)
		if gy != null:
			build_cells(cx - 8, gy - 90, 16, 90, 4)
	for s in bt.squad_alive():
		if s == u or absf(s.x - u.x) <= c.range:
			s.armor += c.fortify
			bt.float_text(s, "+%d ARMOR" % c.fortify, Color("9fb4c9"), true)
			if not c.get("curtain", false):
				var wx: float = s.x + dir * 22.0
				var gy = bt.T.stand_y(wx, s.y - 30)
				if gy != null:
					build_cells(wx - 4, gy - 32, 8, 32, 4)
	if c.get("rook_wall", false):
		var rk = null
		for s in bt.squad_alive():
			if s.def.key == "rook":
				rk = s
		if rk != null and foe != null:
			foe.vx = signf(foe.x - rk.x) * 9.0; foe.vy = -3.0; foe.air = true; foe.walk = null; foe.bumped = {}; foe.last_hit_by = rk
			bt.float_text(foe, "BOOT!", Color("ffd23a"), true)
	await bt.wait(20)

# ---------------------------------------------------------------- N7 Track and Rex, K9 Handler
func make_rex(u: Unit) -> Unit:
	## Rex deploys beside Track. He is on the squad's side but never moves on his own.
	var rx := bt.mk_unit()
	rx.team = "ally"; rx.kind = "dog"; rx.w = 18; rx.h = 14; rx.face = 1
	rx.max_hp = 18 * (2 if bt.ks(u, "k9vest") else 1); rx.hp = rx.max_hp
	rx.loot = {"by": u, "guard": null, "ko": false, "tackled": {}}
	rx.x = u.x - 16
	var gy = bt.T.stand_y(rx.x, u.y - 30)
	rx.y = gy if gy != null else u.y
	bt.units.append(rx)
	return rx

func rex_of(u) -> Unit:
	if not (u is Unit):
		return null
	for o in bt.units:
		if o.kind == "dog" and o.loot.get("by") == u and not o.loot.get("temp", false):
			return o
	return null

func rex_ready(u) -> Unit:
	## Rex, if he is on his feet.
	var rx := rex_of(u)
	return rx if rx != null and not rx.loot.ko and not rx.dead else null

func dog_reach(u: Unit, c: Dictionary) -> float:
	return c.get("reach", 260) * (1.5 if u.perk("longleash") else 1.0)

func dog_target(u: Unit, c: Dictionary, p: Vector2) -> Dictionary:
	## Where a Sic 'Em or Fetch sends Rex: the Jackal (or pickup) nearest the cursor within his reach.
	var rx := rex_ready(u)
	if rx == null:
		return {"ok": false, "why": "REX IS DOWN"}
	var reach := dog_reach(u, c)
	var from := Vector2(rx.x, rx.y)
	var tg = null
	var bd := 70.0
	for o in bt.units:
		if o.dead or o.gone or o.sunk:
			continue
		var fits: bool = (o.team == "enemy" and o.weight != "buried" and not bt.is_boss(o)) if c.dog == "bite" else (o.kind == "loot" or o.kind == "crate" or (o.kind == "pow" and not o.freed))
		if not fits:
			continue
		var d := Vector2(o.x - p.x, o.y - o.h / 2.0 - p.y).length()
		if d < bd and from.distance_to(Vector2(o.x, o.y)) <= reach:
			tg = o
			bd = d
	var to := p
	if tg != null:
		to = Vector2(tg.x - signf(tg.x - rx.x) * (tg.w / 2.0 + 8) if c.dog == "bite" else tg.x, tg.y)
	elif from.distance_to(p) > reach:
		to = from + (p - from).normalized() * reach
	var gy = bt.T.stand_y(to.x, to.y - 30)
	if gy == null:
		gy = bt.T.stand_y(to.x, 0)
	if gy == null or gy >= bt.WATER_Y:
		return {"ok": false, "why": "NO FOOTING", "rex": rx, "to": to}
	return {"ok": true, "rex": rx, "tg": tg, "to": Vector2(to.x, gy)}

func dog_leap(rx: Unit, to: Vector2) -> void:
	rx.loot.guard = null
	rx.walk = null; rx.vx = 0; rx.vy = 0
	Sfx.play("toss", -6)
	await bt.vharr_ai.leap_to(rx, to)
	bt.dust(rx.x, rx.y)

func heel(u: Unit, rx: Unit) -> void:
	## Rex runs back to Track's side.
	var bx := u.x - u.face * 16.0
	var gy = bt.T.stand_y(bx, u.y - 30)
	await dog_leap(rx, Vector2(bx, gy if gy != null else u.y))
	rx.face = u.face

func slash_fx(x: float, y: float, sc: float, face: int) -> void:
	## A melee cut: the V7 pixel slash when the effects layer is up, the old swipe otherwise.
	if bt.vfx != null:
		bt.vfx.slash(x, y, face, sc)
	else:
		bt.fx.append({"kind": "slash", "x": x, "y": y, "t": 0, "dur": 12 if sc > 1 else 10, "sc": sc, "face": face})

func dog_bite(u: Unit, by: Unit, tg: Unit, dmg: Array, o := {}) -> void:
	## One bite. Track's perks ride on every dog, his own Rex or the pack's.
	if tg.dead:
		return
	by.face = 1 if tg.x >= by.x else -1
	by.pose = "throw"; by.pose_t = 10
	Sfx.play("slash", -4)
	slash_fx(tg.x, tg.y - tg.h / 2.0, 1.0, by.face)
	var d := bt.ri(dmg[0], dmg[1]) + (3 if u.perk("bigdog") else 0)
	if o.get("double", false):
		d *= 2
	bt.damage(tg, d, u, {"melee": true})
	if u.perk("alpha") or o.get("stun", false):
		bt.add_status(tg, "stun", 1, u)
	if u.perk("markbite") or o.get("mark", false):
		bt.add_status(tg, "mark", 2, u)
	if o.get("knock", 0) > 0 and not tg.dead and not tg.heavy and not tg.is_prop() and not tg.immovable:
		tg.vx = by.face * o.knock * bt.kb(tg); tg.vy = -3.0; tg.air = true; tg.walk = null; tg.bumped = null; tg.last_hit_by = u
	await bt.wait(10)

func _act_dog(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	var dt := dog_target(u, c, p)
	bt.spend_card(u, idx, c)
	var rx: Unit = dt.rex
	var hunt: bool = u.fl.get("hunt", false)
	u.fl.erase("hunt")
	await dog_leap(rx, dt.to)
	if c.dog == "bite":
		u.attacked = true
		if dt.tg != null:
			for k in (2 if u.perk("secondbite") else 1):
				await dog_bite(u, rx, dt.tg, c.dmg, {"knock": c.knock, "double": hunt, "mark": hunt})
		else:
			bt.float_text(rx, "GRRR", Color("e8dcc2"))
		return
	# Fetch: grab everything within a few steps of the spot, then trot back
	var got := 0
	for o in bt.units.duplicate():
		if o.dead or o.gone or absf(o.x - rx.x) > 40 or absf(o.y - rx.y) > 40:
			continue
		if o.kind == "loot":
			bt.collect(u, o)
			got += 1
		elif o.kind == "crate":
			bt.open_crate(o, false)
			got += 1
		elif o.kind == "pow" and not o.freed:
			o.freed = true
			o.dead_t = 0
			bt.float_text(o, "GOOD DOG!", Color("62d26f"), true)
			bt.pow_queue.append({"pow": o, "u": u})
			got += 1
	if u.perk("pockets"):
		bt.draw_cards(u, 1)
	if u.perk("scrounger"):
		bt.give_scrip(10, rx.x, rx.y - 20, "L964")
	bt.float_text(rx, "FETCHED!" if got else "SNIFF...", Color("62d26f") if got else Color("9aa2ae"))
	await bt.wait(12)
	if got:
		# the loot dropped by crates lands near him: one more sweep before heading home
		await bt.wait(20)
		for o in bt.units.duplicate():
			if o.kind == "loot" and not o.gone and absf(o.x - rx.x) < 60 and absf(o.y - rx.y) < 60:
				bt.collect(u, o)
	await heel(u, rx)

func rex_guard(u: Unit, tg: Unit) -> void:
	var rx := rex_ready(u)
	if rx == null:
		return
	var bx := tg.x + (16.0 if tg != u else -u.face * 16.0)
	var gy = bt.T.stand_y(bx, tg.y - 30)
	await dog_leap(rx, Vector2(bx, gy if gy != null else tg.y))
	rx.loot.guard = tg
	rx.loot.tackled = {}
	rx.face = 1
	bt.float_text(rx, "ON GUARD", Color("53d4e2"), true)

func guard_tackle(e: Unit, tg: Unit) -> bool:
	## Guard: a Jackal lines up a shot on the guarded squadmate, and Rex hits it first.
	if e.team != "enemy" or bt.is_boss(e) or tg == null or tg.team != "squad":
		return false
	for rx in bt.units:
		if rx.kind != "dog" or rx.loot.get("temp", false) or rx.loot.ko or rx.dead or rx.gone:
			continue
		var by: Unit = rx.loot.by
		var g = rx.loot.guard
		if g == null and by.perk("watchdog") and not by.dead:
			g = by
		if g != tg or rx.loot.tackled.has(e.id):
			continue
		bt.banner("REX!", Color("ffd23a"))
		var spot := Vector2(e.x - signf(e.x - rx.x) * (e.w / 2.0 + 8), e.y)
		var gy = bt.T.stand_y(spot.x, spot.y - 30)
		var keep = rx.loot.guard
		await dog_leap(rx, Vector2(spot.x, gy if gy != null else e.y))
		await dog_bite(by, rx, e, [4 + (6 if by.perk("hardtackle") else 0), 4 + (6 if by.perk("hardtackle") else 0)], {"stun": true, "knock": 8 if by.perk("hardtackle") else 0})
		bt.float_text(e, "TACKLED!", Color("ffd23a"), true)
		if by.perk("loyal"):
			rx.loot.tackled[e.id] = true
			rx.loot.guard = keep
			var gy2 = bt.T.stand_y(g.x + 16, g.y - 30)
			await bt.vharr_ai.leap_to(rx, Vector2(g.x + 16, gy2 if gy2 != null else g.y))
		return true
	return false

func release_hounds(u: Unit, c: Dictionary, n: int) -> void:
	## Release the Hounds / Wolfpack / Skyfall / K9 Strike: each dog (or the hawk) takes a different Jackal.
	var hawk: bool = c.get("hawk", false)
	bt.banner("SKYFALL!" if hawk else "RELEASE THE HOUNDS!", Color("ffb23e"))
	Sfx.play("alarm")
	var foes := bt.units.filter(func(e): return e.team == "enemy" and not e.dead and not e.gone and not e.sunk and e.weight != "buried" and e.x > bt.cam_x - 20 and e.x < bt.cam_x + bt.W + 20)
	foes.sort_custom(func(a, b2): return absf(a.x - u.x) < absf(b2.x - u.x))
	for e in foes.slice(0, n):
		if e.dead:
			continue
		if hawk:
			await hawk_dive(u, e, 6)
			continue
		var dg := bt.mk_unit()
		dg.team = "ally"; dg.kind = "dog"; dg.w = 18; dg.h = 14; dg.hp = 1; dg.max_hp = 1
		dg.loot = {"by": u, "temp": true, "ko": false, "guard": null, "tackled": {}}
		dg.x = u.x; dg.y = u.y
		bt.units.append(dg)
		var gy = bt.T.stand_y(e.x - signf(e.x - u.x) * (e.w / 2.0 + 8), e.y - 30)
		await bt.vharr_ai.leap_to(dg, Vector2(e.x - signf(e.x - u.x) * (e.w / 2.0 + 8), gy if gy != null else e.y))
		await dog_bite(u, dg, e, [8, 10], {"stun": c.get("hstun", false), "mark": c.get("hmark", false), "knock": 4})
		dg.gone = true
		dg.dead = true
		bt.puff(dg.x, dg.y - 6, 1.0)
	await bt.wait(12)

func hawk_dive(u: Unit, e: Unit, dmg: int) -> void:
	## The hawk stoops out of the sky: a streak down onto the Jackal, damage and a Mark.
	var sx := e.x - 60.0
	bt.tracer(sx, e.y - 220, e.x, e.y - e.h / 2.0, Color("e8dcc2"))
	Sfx.play("toss", -2)
	await bt.wait(8)
	var d := dmg + (6 if u.perk("talons") else 0)
	if d > 0:
		bt.damage(e, d, u, {"melee": true})
	bt.add_status(e, "mark", 2, u)
	bt.float_text(e, "HAWK!", Color("e8dcc2"))
	await bt.wait(8)

func supply_run(u: Unit) -> void:
	var rx := rex_ready(u)
	if rx == null:
		rx = rex_of(u)
		if rx == null:
			return
		revive_rex(u, rx)
	bt.banner("SUPPLY RUN!", Color("62d26f"))
	var goods := bt.units.filter(func(o): return not o.dead and not o.gone and (o.kind == "loot" or o.kind == "crate") and o.x > bt.cam_x - 20 and o.x < bt.cam_x + bt.W + 20)
	goods.sort_custom(func(a, b2): return a.x < b2.x)
	for o in goods.slice(0, 10):
		if o.gone or o.dead:
			continue
		var gy = bt.T.stand_y(o.x, o.y - 30)
		await dog_leap(rx, Vector2(o.x, gy if gy != null else o.y))
		if o.kind == "crate":
			bt.open_crate(o, false)
			await bt.wait(16)
		elif not o.gone:
			bt.collect(u, o)
	for o in bt.units.duplicate():
		if o.kind == "loot" and not o.gone and absf(o.x - rx.x) < 80:
			bt.collect(u, o)
	await heel(u, rx)

func revive_rex(u: Unit, rx: Unit) -> void:
	## Best Friend: a knocked-out Rex is back at Track's side.
	rx.loot.ko = false
	rx.loot.guard = null
	rx.gone = false
	rx.dead = false
	rx.hp = rx.max_hp
	rx.x = u.x - u.face * 16.0
	var gy = bt.T.stand_y(rx.x, u.y - 30)
	rx.y = gy if gy != null else u.y
	rx.zip = null; rx.vx = 0; rx.vy = 0; rx.air = false
	bt.puff(rx.x, rx.y - 6, 1.2)
	bt.float_text(rx, "REX IS BACK", Color("62d26f"))

func rex_hurt(rx: Unit, amt: int) -> void:
	if rx.loot.get("temp", false):
		rx.gone = true
		rx.dead = true
		return
	if bt.ks(rx.loot.by, "k9vest"):
		amt = maxi(0, amt - 3)
	if amt <= 0:
		bt.float_text(rx, "VEST", Color("9fb4c9"))
		return
	rx.hp -= amt
	rx.flash = 8
	bt.float_text(rx, "-%d" % amt, Color("ff4d3d"))
	if rx.hp <= 0:
		rx.hp = 0
		rx.loot.ko = true
		rx.loot.guard = null
		rx.gone = true
		bt.puff(rx.x, rx.y - 6, 1.5)
		bt.float_at(rx.x, rx.y - 26, "REX KNOCKED OUT", Color("ff7a3d"), true)
		bt.log_msg("Rex is knocked out. He'll be back at Track's side next turn.")

func dogs_new_turn() -> void:
	## Start of the squad's turn: Rex shakes off a knockout or catches up, and the Hawk Hood marks a Jackal.
	for u in bt.squad_alive():
		if u.def.key != "track" and not bt.ks(u, "hawkhood"):
			continue
		var rx := rex_of(u)
		if rx != null and (rx.loot.ko or absf(rx.x - u.x) > 560 or rx.sunk):
			rx.sunk = false
			revive_rex(u, rx)
		if bt.ks(u, "hawkhood"):
			var best = null
			for e in bt.units:
				if e.team == "enemy" and not e.dead and not e.gone and e.x > bt.cam_x - 20 and e.x < bt.cam_x + bt.W + 20 and (best == null or absf(e.x - u.x) < absf(best.x - u.x)):
					best = e
			if best != null:
				await hawk_dive(u, best, 0)

# ---------------------------------------------------------------- N1 Finch, N4 Kage, N5 Volta, N6 Brass, N8 Sable
func vis_foes() -> Array:
	## Hostile Jackals and aliens on screen (not the ones Sable has taken over).
	return bt.units.filter(func(e): return e.team == "enemy" and not e.dead and not e.gone and not e.fl.has("mind") and not Data.ETYPES[e.type].get("static", false) and e.x > bt.cam_x - 20 and e.x < bt.cam_x + bt.W + 20)

func wind_of(u, c: Dictionary) -> float:
	## Volta's throws (and anything she hands out) ignore the wind.
	if u is Unit and u.team == "squad" and u.def.key == "volta":
		return 0.0
	return c.get("wind", 1.0)

func temp_card(s: Unit, key: String, free := true, extra := {}) -> void:
	var inst := {"id": -2, "key": key, "tier": Data.base_tier(key), "temp": true, "free": free}
	inst.merge(extra)
	s.hand.append(inst)

func squad_of(key: String):
	for s in bt.squad_alive():
		if s.def.key == key:
			return s
	return null

func fling(o: Unit, dir: float, pw: float, by) -> void:
	## Throws a body sideways; heavies and anchors barely budge.
	if o.dead or o.gone or o.immovable or bt.is_boss(o):
		return
	o.vx = dir * pw * (0.35 if o.heavy else 1.0) * bt.kb(o)
	o.vy = -3.5 - pw * 0.25
	o.air = true; o.walk = null; o.bumped = null; o.last_hit_by = by

func lightning(a: Vector2, b2: Vector2) -> void:
	if bt.vfx != null:
		var key := Vector4i(roundi(a.x), roundi(a.y), roundi(b2.x), roundi(b2.y))
		if bt.zaps.get(key, -99) > bt.t - 10:
			return
		bt.zaps[key] = bt.t
		bt.vfx.add(SfLightning.arc(func(): return a, [b2], bt.vfx.ground_fn(b2.y), 0.25))
		return
	var prev := a
	for k in range(1, 6):
		var t := k / 5.0
		var nxt := a.lerp(b2, t) + (Vector2(randf_range(-6, 6), randf_range(-6, 6)) if k < 5 else Vector2.ZERO)
		bt.tracer(prev.x, prev.y, nxt.x, nxt.y, Color("9fe8ff"))
		prev = nxt

# --- N1 Finch
func zip_spot(u: Unit, c: Dictionary, p: Vector2) -> Dictionary:
	var reach: float = c.reach * (1.5 if u.perk("longline") else 1.0)
	var from := Vector2(u.x, u.y - u.h)
	var to := from + (p - from).limit_length(reach)
	var x := clampf(to.x, bt.cam_x + 14, bt.cam_x + bt.W - 14)
	var y = bt.T.stand_y(x, to.y - 12)
	if y == null:
		return {"ok": false, "x": x, "y": to.y, "hx": from.x, "hy": from.y}
	return {"ok": true, "x": x, "y": float(y), "hx": from.x, "hy": from.y}

func _act_zip(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	c = bt.spend_card(u, idx, c)
	var zs := zip_spot(u, c, p)
	var pull: float = c.pull + (70.0 if u.perk("longline") else 0.0)
	var riders: Array = [u]
	for s in bt.squad_alive():
		if s != u and s.mech == null and s.kind != "dog" and Vector2(s.x - u.x, s.y - u.y).length() <= pull:
			riders.append(s)
	Sfx.play("rocket")
	var dir := 1.0 if zs.x >= u.x else -1.0
	var starts: Array = riders.map(func(r): return Vector2(r.x, r.y))
	var ends: Array = []
	for i in riders.size():
		var off: float = -dir * 20.0 * i
		var ex: float = clampf(zs.x + off, bt.cam_x + 14, bt.cam_x + bt.W - 14)
		var ey = bt.T.stand_y(ex, zs.y - 30)
		ends.append(Vector2(ex, ey if ey != null else zs.y))
	for f in 14:
		bt.tracer(zs.hx, zs.hy, zs.x, zs.y - 30, Color("e8dcc2"))
		for i in riders.size():
			var r: Unit = riders[i]
			var pt: Vector2 = starts[i].lerp(ends[i], (f + 1) / 14.0)
			r.x = pt.x; r.y = pt.y - sin((f + 1) / 14.0 * PI) * 16
			r.vx = 0; r.vy = 0; r.air = false; r.walk = null; r.face = int(dir)
		await bt.wait(1)
	for i in riders.size():
		var r: Unit = riders[i]
		r.x = ends[i].x; r.y = ends[i].y; r.air = false
		if u.perk("groupride"):
			r.move_left += 40
	bt.float_text(u, "ZIPLINE" if riders.size() == 1 else "ALL ABOARD x%d" % riders.size(), Color("e8dcc2"), true)
	if u.perk("freefall"):
		bt.draw_cards(u, 1)
	u.moved = true
	await bt.check_push(u)

func flare_at(x: float, y: float, r: float, by) -> void:
	for e in bt.units:
		if e.team == "enemy" and not e.dead and not e.gone and Vector2(e.x - x, e.y - e.h / 2.0 - y).length() < r + e.w / 2.0:
			bt.add_status(e, "flared", 2, by)
			if by is Unit and by.perk("illum"):
				bt.add_status(e, "supp", 1, by)
	for i in 14:
		bt.part({"x": x + randf_range(-r, r) * 0.4, "y": y - randf_range(0, 30), "vx": randf_range(-1, 1), "vy": -randf_range(0.2, 1.4), "life": 40, "max": 40, "c": Color("ffe36a"), "s": 3.0, "g": 0.0, "fire": true})
	bt.float_at(x, y - 30, "FLARE", Color("ffe36a"), true)
	Sfx.play("power")

func flare_bonus() -> int:
	return 6 if bt.squad_alive().any(func(s): return s.perk("spotcrit")) else 3

func drone_runs(u: Unit, c: Dictionary) -> void:
	var n: int = c.drone * (2 if u.perk("twindrone") else 1)
	var reach := 2000.0 if c.get("od", false) else 420.0
	var foes := vis_foes().filter(func(e): return absf(e.x - u.x) <= reach)
	foes.sort_custom(func(a, b2): return absf(a.x - u.x) < absf(b2.x - u.x))
	if foes.is_empty():
		bt.float_text(u, "NO TARGETS", Color("9aa2ae"))
		return
	Sfx.play("power")
	bt.float_text(u, "DRONE UP", Color("e8dcc2"), true)
	for k in n:
		var e: Unit = foes[k % foes.size()]
		if e.dead:
			continue
		var dy: float = e.y - e.h - 60
		if u.perk("dronegun"):
			for s in 3:
				bt.tracer(e.x - 10, dy, e.x, e.y - e.h / 2.0, Color("fff4c0"))
				bt.damage(e, 3, u)
				await bt.wait(3)
		if u.perk("dronemark") and not e.dead:
			bt.add_status(e, "flared", 2, u)
		var r: float = c.get("radius", 32) * bt.blast_scale(u)
		bt.projs.append(bt.phys.mk_proj({"kind": "bomb", "x": e.x, "y": dy, "vx": 0.0, "vy": 3.0, "r": r, "dmg": c.get("dmg", 9), "owner": u}))
		Sfx.play("toss")
		await bt.wait(14)
	await bt.until(bt.settled)

func rig_all(u: Unit) -> void:
	bt.banner("RIGGED!", Color("ffb23e"))
	for o in bt.units.duplicate():
		if o.gone or o.dead or o.x < bt.cam_x - 20 or o.x > bt.cam_x + bt.W + 20:
			continue
		if o.kind == "barrel" or o.kind == "fuel":
			bt.damage(o, 1, u, {"blast": true})
		elif o.kind == "mine" and not o.primed:
			o.primed = true
			bt.booms.append({"t": 6, "x": o.x, "y": o.y - 3, "r": 38.0, "dmg": 15, "owner": u, "barrel": o})
	await bt.wait(20)
	await bt.until(bt.settled)

# --- N4 Kage
func iaido_line(u: Unit, c: Dictionary, p: Vector2) -> Dictionary:
	var from := Vector2(u.x, u.y - u.h / 2.0)
	var to := from + (p - from).normalized() * float(c.reach)
	var hit: Array = []
	for o in bt.units:
		if o == u or o.dead or o.gone or o.team == "squad" or o.is_pickup() or o.kind in ["pow", "ride", "hulk", "sticky"]:
			continue
		var ctr := Vector2(o.x, o.y - o.h / 2.0)
		var q := Geometry2D.get_closest_point_to_segment(ctr, from, to)
		if q.distance_to(ctr) < o.w / 2.0 + 8:
			hit.append(o)
	return {"from": from, "to": to, "hit": hit}

func _act_iaido(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	c = bt.spend_card(u, idx, c)
	u.attacked = true
	var L := iaido_line(u, c, p)
	u.face = 1 if p.x >= u.x else -1
	u.pose = "throw"; u.pose_t = 16
	Sfx.play("slash")
	for f in 6:
		bt.tracer(L.from.x, L.from.y, L.to.x, L.to.y, Color("e0f4ff"))
		await bt.wait(1)
	var n := int(L.from.distance_to(L.to) / 10.0)
	for k in n:
		var pt: Vector2 = L.from.lerp(L.to, k / float(maxi(1, n)))
		if bt.T.solid(pt.x, pt.y):
			bt.T.carve(pt.x, pt.y, 7, u)
	for o in L.hit:
		bt.damage(o, c.iaido, u, {"melee": true})
		slash_fx(o.x, o.y - o.h / 2.0, 1.6, u.face)
	bt.float_text(u, "IAIDO", Color("e0f4ff"), true)
	await bt.wait(16)

# --- N5 Volta
func magnet_line(u: Unit, c: Dictionary, p: Vector2) -> Dictionary:
	## The bodies a Magnet Gun, Repulsor or Tongue would grab, nearest first.
	var reach: float = c.reach * (1.5 if c.magnet > 0 and u.perk("strongpush") else 1.0)
	var from := bt.hand_pos(u)
	var dir := (p - from).normalized()
	var hit: Array = []
	var end := from + dir * reach
	var d := 8.0
	while d < reach:
		var pt := from + dir * d
		if bt.T.hard(pt.x, pt.y):
			end = pt
			break
		for o in bt.units:
			if o == u or o.dead or o.gone or hit.has(o) or o.is_pickup() or bt.is_boss(o) or o.kind in ["pow", "ride", "hulk", "sticky", "slug", "sentry", "dog", "rivet"]:
				continue
			if o.team == "squad" and not c.get("tongue", false):
				continue
			if o.team == "enemy" and Data.ETYPES[o.type].get("static", false):
				continue
			if absf(pt.x - o.x) < o.w / 2.0 + 4 and pt.y > o.y - o.h - 4 and pt.y < o.y + 2:
				hit.append(o)
		if hit.size() and not u.perk("magstorm"):
			end = pt
			break
		d += 6.0
	return {"from": from, "to": end, "hit": hit}

func _act_magnet(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	c = bt.spend_card(u, idx, c)
	var L := magnet_line(u, c, p)
	u.face = 1 if p.x >= u.x else -1
	Sfx.play("power")
	if bt.vfx != null and not c.get("tongue", false):
		# V12: Repulsor pushes in pink, Magnet pulls in cyan
		bt.vfx.add(SfEnergy.beam(L.from, L.to, bt.vfx.ground_fn(L.to.y), SfEnergy.PINK if c.magnet > 0 else SfEnergy.CYAN, 0.04, 0.1, 2.5))
		await bt.wait(6)
	else:
		for f in 6:
			if c.get("tongue", false):
				bt.tracer(L.from.x, L.from.y, L.to.x, L.to.y, Color("d36ba0"))
			else:
				lightning(L.from, L.to)
			await bt.wait(1)
	if L.hit.is_empty():
		bt.float_text(u, "NOTHING CAUGHT", Color("9aa2ae"))
	var pw: float = 7.5 * (1.5 if u.perk("heavypull") else 1.0)
	for o in L.hit:
		var dir := signf(o.x - u.x) if c.magnet > 0 else signf(u.x - o.x)
		if dir == 0:
			dir = u.face
		var d := absf(o.x - u.x)
		fling(o, dir, pw if c.magnet > 0 else clampf(d / 26.0, 3.0, pw), u)
		if o.team == "enemy":
			u.attacked = true
			if u.perk("kinimpact"):
				bt.damage(o, 6, u)
			if u.perk("fieldlock"):
				bt.add_status(o, "supp", 1, u)
	if c.magnet > 0 and u.perk("recoilshield"):
		u.armor += 4
		bt.float_text(u, "+4 ARMOR", Color("9fb4c9"))
	await bt.wait(4)
	await bt.until(bt.settled)

func tesla_arc(u: Unit, c: Dictionary) -> void:
	var n: int = c.tesla + (2 if u.perk("arcjump") else 0) + (2 if bt.ks(u, "teslacoil") else 0)
	var from := Vector2(u.x, u.y - u.h / 2.0)
	var reach := 300.0
	var hit: Array = []
	for k in n:
		var best = null
		for e in vis_foes():
			if hit.has(e):
				continue
			var dd := from.distance_to(Vector2(e.x, e.y - e.h / 2.0))
			if dd <= reach and (best == null or dd < from.distance_to(Vector2(best.x, best.y - best.h / 2.0))):
				best = e
		if best == null:
			break
		hit.append(best)
		var to := Vector2(best.x, best.y - best.h / 2.0)
		Sfx.play("zap")
		for f in 4:
			lightning(from, to)
			await bt.wait(1)
		var dm: int = bt.ri(c.dmg[0], c.dmg[1]) + (3 if u.perk("overload") else 0)
		if c.get("od", false):
			bt.vfx.add(SfLightning.impact(to.x, to.y, bt.vfx.ground_fn(to.y), 0.6, 32))
		bt.damage(best, dm, u)
		if c.get("tstun", false) or u.perk("stunbolt"):
			bt.add_status(best, "stun", 1, u)
		from = to
		reach = 220.0 if c.get("od", false) else 140.0
	if hit.is_empty():
		bt.float_text(u, "NO TARGETS", Color("9aa2ae"))
	else:
		u.attacked = true
	await bt.wait(8)

func singularity_at(x: float, y: float, r: float, crush: int, by) -> void:
	var caught: Array = bt.units.filter(func(o): return not o.dead and not o.gone and (o.team == "enemy" or o.kind == "barrel" or o.kind == "fuel") and not bt.is_boss(o) and not o.immovable and not (o.team == "enemy" and Data.ETYPES[o.type].get("static", false)) and Vector2(o.x - x, o.y - o.h / 2.0 - y).length() < r + o.w / 2.0)
	bt.float_at(x, y - 30, "SINGULARITY", Color("c47bff"), true)
	Sfx.play("power")
	var hole = black_hole(x, y, r, 0.35)
	for f in 16:
		for o in caught:
			o.x = lerpf(o.x, x, 0.12)
			o.walk = null
		if hole == null:
			for k in 3:
				var a := randf() * TAU
				bt.part({"x": x + cos(a) * r, "y": y + sin(a) * r * 0.5, "vx": -cos(a) * 3, "vy": -sin(a) * 1.5, "life": 20, "max": 20, "c": Color("c47bff"), "s": 2.0, "g": 0.0})
		await bt.wait(1)
	if hole != null:
		# everything is thrown when the hole bursts
		await bt.wait(maxi(0, hole.ticks_to_burst() - 16))
	bt.shake += 4
	for i in caught.size():
		var o: Unit = caught[i]
		if crush > 0 and o.team == "enemy":
			bt.damage(o, crush, by)
		var dir := signf(o.x - x)
		if dir == 0:
			dir = 1.0 if i % 2 == 0 else -1.0
		fling(o, dir, 7.0, by)
	await bt.wait(6)
	await bt.until(bt.settled)

func black_hole(x: float, y: float, r: float, life: float):
	## V11: a violet black hole over a gravity well or singularity of reach r (cosmetic).
	if bt.vfx == null:
		return null
	var gy: float = bt.vfx.ground_fn(y).call(x)
	var e := SfBlackHole.new(x, y, clampf(r / 9.0, 10.0, 24.0), bt.vfx.ground_fn(y), life, 1.5, bt.MATCOL.get(bt.T.mat(x, gy + 2), Color("6a5a48")))
	bt.vfx.add(e)
	return e

func shockwave(u: Unit, r: float) -> void:
	bt.shake += 5
	Sfx.play("thud")
	bt.part({"ring": true, "x": u.x, "y": u.y - u.h / 2.0, "r": 4.0, "max": r, "life": 16, "c": Color("9fe8ff")})
	for o in bt.units:
		if o == u or o.dead or o.gone or o.team == "squad" or o.is_pickup() or o.kind in ["pow", "slug", "ride", "hulk", "sticky", "sentry", "dog"]:
			continue
		if o.team == "enemy" and Data.ETYPES[o.type].get("static", false):
			continue
		if Vector2(o.x - u.x, o.y - u.y).length() < r:
			fling(o, signf(o.x - u.x) if o.x != u.x else float(u.face), 8.0, u)
	u.attacked = true
	await bt.wait(6)
	await bt.until(bt.settled)

func slingshot(u: Unit) -> void:
	var rk = squad_of("rook")
	var foes := vis_foes().filter(func(e): return not e.heavy)
	if rk == null or foes.is_empty():
		bt.float_text(u, "NO TARGETS", Color("9aa2ae"))
		return
	foes.sort_custom(func(a, b2): return absf(a.x - u.x) < absf(b2.x - u.x))
	var e: Unit = foes[0]
	var nx: float = rk.x + rk.face * (rk.w / 2.0 + e.w / 2.0 + 4)
	var ny = bt.T.stand_y(nx, rk.y - 40)
	lightning(Vector2(u.x, u.y - 14), Vector2(e.x, e.y - e.h / 2.0))
	e.x = nx; e.y = ny if ny != null else rk.y; e.vx = 0; e.vy = 0; e.walk = null
	await bt.wait(8)
	rk.pose = "throw"; rk.pose_t = 16
	Sfx.play("thud")
	bt.damage(e, 12, rk, {"melee": true})
	fling(e, rk.face, 9.0, rk)
	bt.float_text(rk, "SLINGSHOT!", Color("ffb23e"), true)
	await bt.wait(8)
	await bt.until(bt.settled)

# --- N6 Brass
func brass_supply(u: Unit, n: int) -> void:
	for k in n:
		var pool: Array = u.def.pool.filter(func(k2): return k2 != "supplydrop")
		pool.shuffle()
		var opts: Array = []
		for i in mini(3, pool.size()):
			opts.append({"kind": "card", "key": pool[i], "tier": Run.roll_card_tier(pool[i]), "u": u})
		Sfx.play("coin")
		var ch := await bt.ask("supply", "SUPPLY DROP", "Pick a card for %s's hand. It's free this turn." % u.def.name, opts)
		if ch >= 0:
			u.hand.append({"id": -2, "key": opts[ch].key, "tier": opts[ch].tier, "temp": true, "free": true})
			bt.float_text(u, Data.CARDS[opts[ch].key].name.to_upper(), Color("62d26f"), true)
	if u.perk("provisions"):
		for s in bt.squad_alive():
			s.hp = mini(s.max_hp, s.hp + 6)
			bt.float_text(s, "+6 HP", Color("62d26f"))
	if u.perk("stockpile"):
		for s in bt.squad_alive():
			bt.draw_cards(s, 1)
	bt.ui_dirty = true

func beacon_bonus(u: Unit, c: Dictionary) -> int:
	var n := 0
	if c.get("key", "") == "designator":
		n += (1 if u.perk("spotround") else 0) + (2 if bt.ks(u, "fieldphone") else 0)
	if u.perk("ffe"):
		n += 2
	if bt.squad_alive().any(func(s): return s.perk("airsupport")):
		n += 1
	return n

# --- N8 Sable
func can_link(u: Unit, tg, c: Dictionary) -> bool:
	if tg == null or tg.dead or tg.team != "enemy" or bt.is_boss(tg) or tg.fl.has("mind") or Data.ETYPES[tg.type].get("static", false):
		return false
	if tg.hp > 30 and not u.perk("biglink"):
		return false
	return absf(tg.x - u.x) <= c.range and absf(tg.y - u.y) <= 140

func mind_link(u: Unit, tg: Unit, turns: int) -> void:
	tg.fl["mind"] = turns
	tg.active = true
	tg.st.erase("cloak")
	lightning(Vector2(u.x, u.y - u.h), Vector2(tg.x, tg.y - tg.h))
	bt.float_text(tg, "MINDLINKED", Color("c47bff"), true)
	Sfx.play("power")

func brood_call(u: Unit, n: int) -> void:
	bt.banner("BROOD CALL!", Color("9df25c"))
	for k in n:
		var x: float = clampf(u.x + (k - (n - 1) / 2.0) * 30.0 + u.face * 30, bt.cam_x + 20, bt.cam_x + bt.W - 20)
		var y = bt.T.stand_y(x, u.y - 50)
		if y == null:
			continue
		var e := bt.mk_enemy("skitter", x, y)
		e.active = true
		e.fl["mind"] = 1
		e.fl["brood"] = true
		bt.units.append(e)
		bt.dust(x, y, Color("9df25c"), 8)
	Sfx.play("splash")
	await bt.wait(12)

func acid_puddle(x: float, y: float, r: float, by) -> void:
	var potent: bool = by is Unit and by.perk("potent")
	bt.acids.append({"x": x, "y": y, "r": r * (1.5 if potent else 1.0), "turns": 4 if potent else 3, "dmg": 5 if bt.ks(by, "acidgland") else 3, "owner": by})
	if by is Unit and by.perk("dissolve"):
		bt.T.carve(x, y, 20, by)
	Sfx.play("splash")

func minds_tick() -> void:
	## Linked Jackals come back to themselves after the enemy phase; the brood melts away.
	for e in bt.units:
		if e.dead or not e.fl.has("mind"):
			continue
		e.fl.mind -= 1
		if e.fl.mind <= 0:
			e.fl.erase("mind")
			if e.fl.get("brood", false):
				e.gone = true
				e.dead = true
				bt.dust(e.x, e.y, Color("9df25c"), 6)
			else:
				bt.float_text(e, "LINK BROKEN", Color("9aa2ae"))

func classes_enemy_end() -> void:
	minds_tick()

func classes_new_turn() -> void:
	## Turn-start traits and perks of the five new classes.
	for b2 in bt.squad_alive():
		match b2.def.key:
			"brass":
				var others := bt.squad_alive().filter(func(s): return s != b2)
				others.sort_custom(func(a, c2): return absf(a.x - b2.x) < absf(c2.x - b2.x))
				for s in others.slice(0, 2 if b2.perk("inspire") else 1):
					s.energy += 1
					bt.float_text(s, "CHAIN OF COMMAND +1", Color("ffb23e"))
				if b2.perk("leadfront"):
					for s in others:
						if absf(s.x - b2.x) <= 140:
							s.move_left += 40
				if b2.perk("intelrep"):
					var fs := vis_foes()
					fs.sort_custom(func(a, c2): return absf(a.x - b2.x) < absf(c2.x - b2.x))
					if fs.size():
						bt.add_status(fs[0], "mark", 2, b2)
				if bt.round_n == 1 and bt.ks(b2, "radiopack"):
					b2.hand.append({"id": -3, "key": "slugcall", "tier": Data.OD_TIER, "temp": true})
			"kage":
				if bt.round_n == 1 and b2.perk("ambush"):
					bt.add_status(b2, "cloak", 2, b2)
				if b2.perk("freerunning"):
					b2.move_left += 60
			"finch":
				if b2.perk("freefall"):
					b2.move_left += 60
			"sable":
				if b2.perk("domeself"):
					b2.armor += 3
				if bt.ks(b2, "wardencore"):
					b2.dome = maxi(b2.dome, 1)

# ---------------------------------------------------------------- B1-B4: fifth branches for the original four
func _act_handoff(u: Unit, idx: int, c: Dictionary, tg: Unit) -> void:
	## Hand-Off: the card to the right of it (or the left, at the end of the hand) goes to a squadmate.
	var give = null
	if idx + 1 < u.hand.size():
		give = u.hand[idx + 1]
	elif idx > 0:
		give = u.hand[idx - 1]
	bt.spend_card(u, idx, c)
	if give == null or not u.hand.has(give):
		bt.float_text(u, "NOTHING TO PASS", Color("9aa2ae"))
		return
	u.hand.erase(give)
	tg.hand.append(give)
	bt.tracer(u.x, u.y - 24, tg.x, tg.y - 24, Color("53d4e2"))
	bt.float_text(tg, Data.CARDS[give.key].name.to_upper(), Color("53d4e2"), true)
	Sfx.play("select")
	if u.perk("assist"):
		bt.draw_cards(tg, 1)
	if bt.ks(u, "radiohq"):
		tg.energy += 1
		bt.float_text(tg, "+1 ENERGY", Color("ffb23e"))
	await bt.wait(14)

func switch_places(u: Unit, tg: Unit) -> void:
	var a := Vector2(u.x, u.y)
	bt.puff(u.x, u.y - 14, 1.2)
	bt.puff(tg.x, tg.y - 14, 1.2)
	u.x = tg.x; u.y = tg.y
	tg.x = a.x; tg.y = a.y
	u.walk = null; tg.walk = null
	Sfx.play("power", -6)
	bt.float_text(u, "SWITCHEROO", Color("53d4e2"), true)
	await bt.wait(12)

func plant_sticky(x: float, y: float, by, dmg: int, r: float) -> Unit:
	var gy = bt.T.stand_y(x, y - 20)
	if gy == null:
		gy = y
	var sk := bt.mk_unit()
	sk.team = "neutral"; sk.kind = "sticky"; sk.x = x; sk.y = gy; sk.w = 10; sk.h = 6
	if by is Unit and by.perk("bigcharge"):
		r += 10
	sk.loot = {"by": by, "dmg": dmg, "r": r, "n": bt.round_n * 1000 + bt.stickies.size()}
	bt.units.append(sk)
	bt.stickies.append(sk)
	Sfx.play("land", -6)
	return sk

func blow_sticky(sk: Unit, bonus := 0, mul := 1.0) -> void:
	if sk.gone:
		return
	sk.gone = true
	bt.stickies.erase(sk)
	bt.explode(sk.x, sk.y - 4, sk.loot.r * mul * bt.blast_scale(sk.loot.by), sk.loot.dmg + bonus, sk.loot.by)

func clacker(u: Unit) -> void:
	## Clacker: the oldest Sticky Charge blows (Chain Reaction: all of them).
	var mine := bt.stickies.filter(func(o): return o.loot.by == u and not o.gone)
	if mine.is_empty():
		bt.float_text(u, "NO CHARGES OUT", Color("9aa2ae"))
		return
	mine.sort_custom(func(a, b2): return a.loot.n < b2.loot.n)
	var mul := 1.5 if u.fl.get("setforget", false) else 1.0
	u.fl.erase("setforget")
	Sfx.play("tick")
	bt.float_text(u, "CLACK!", Color("ffd23a"))
	await bt.wait(10)
	if u.perk("chainreact"):
		for sk in mine:
			blow_sticky(sk, 4, mul)
			await bt.wait(6)
	else:
		blow_sticky(mine[0], 0, mul)

func sticky_watch() -> void:
	## Sticky Charges blow under a Jackal that steps on them (Tripwire: within 50px).
	for sk in bt.stickies.duplicate():
		if sk.gone:
			bt.stickies.erase(sk)
			continue
		var reach := 50.0 if sk.loot.by is Unit and sk.loot.by.perk("tripwire") else 14.0
		for e in bt.units:
			if e.team == "enemy" and not e.dead and not e.gone and absf(e.x - sk.x) < reach + e.w / 2.0 and absf(e.y - sk.y) < 30:
				bt.float_text(sk, "TRIPPED!", Color("ff4d3d"))
				blow_sticky(sk)
				break

func _act_daisy(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	bt.spend_card(u, idx, c)
	bt.banner("DAISY CHAIN!", Color("ffb23e"))
	var dir := 1.0 if p.x >= u.x else -1.0
	var base: Dictionary = Data.card("stickycharge")
	for k in c.daisy:
		var x: float = u.x + dir * (40.0 + k * 36.0)
		var gy = bt.T.stand_y(x, u.y - 60)
		if gy == null or gy >= bt.WATER_Y - 4:
			continue
		plant_sticky(x, gy, u, base.dmg, base.radius)
		await bt.wait(6)

func can_grab(u: Unit, tg: Unit) -> bool:
	if tg == null or tg.team != "enemy" or tg.dead or bt.is_boss(tg) or tg.is_prop() or Data.ETYPES[tg.type].get("static", false) or tg.weight == "buried":
		return false
	if (tg.heavy or tg.weight == "hover" or tg.type == "brute") and not u.perk("titan"):
		return false
	return true

func hold_fast() -> void:
	## Every frame: a carried Jackal rides on the Wrestler's shoulder.
	for s in bt.squad():
		if s.held == null:
			continue
		var e: Unit = s.held
		if e.dead or e.gone or s.dead or not e.fl.has("carried"):
			if not e.dead:
				e.fl.erase("carried")
			s.held = null
			continue
		e.x = s.x + s.face * 6
		e.y = s.y - s.h + 6
		e.face = -s.face
		e.vx = 0; e.vy = 0; e.walk = null; e.air = false

func release_holds() -> void:
	## The Jackals' phase: anyone still carried wriggles free.
	for s in bt.squad():
		if s.held != null:
			var e: Unit = s.held
			e.fl.erase("carried")
			e.x = s.x + s.face * 18
			e.air = true
			s.held = null
			bt.float_text(e, "BROKE FREE", Color("ff7a3d"))
		s.hand = s.hand.filter(func(h): return h.key != "bodythrow")

func _act_grab(u: Unit, c: Dictionary, tg: Unit) -> void:
	u.face = 1 if tg.x >= u.x else -1
	bt.damage(tg, bt.ri(c.dmg[0], c.dmg[1]), u, {"melee": true})
	if tg.dead:
		return
	u.held = tg
	tg.fl["carried"] = u.id
	if u.hang:
		bt.drop_hang(u)
	if not u.hand.any(func(h): return h.key == "bodythrow"):
		u.hand.append({"id": -8, "key": "bodythrow", "tier": Data.base_tier("bodythrow"), "temp": true})
	bt.float_text(tg, "GRABBED!", Color("ffd23a"), true)
	Sfx.play("bonk")
	await bt.wait(10)

func _act_bodythrow(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	bt.spend_card(u, idx, c)
	var e: Unit = u.held
	u.held = null
	e.fl.erase("carried")
	var v := bt.aim_vel(u, p)
	u.face = v.f
	u.pose = "throw"; u.pose_t = 20
	Sfx.play("toss")
	e.x = v.hx; e.y = v.hy + 10
	e.vx = v.vx; e.vy = v.vy; e.air = true; e.walk = null; e.bumped = {u.id: true}; e.last_hit_by = u
	var t0 := bt.t
	await bt.until(func(): return not e.air or e.dead or e.sunk or bt.t - t0 > 300)
	if not e.dead:
		var d: int = c.dmg + (6 if u.perk("bodyslam") else 0) + (6 if bt.ks(u, "luchamask") else 0)
		bt.damage(e, d, u, {"melee": true})
		if bt.ks(u, "luchamask"):
			bt.add_status(e, "stun", 1, u)
		bt.float_text(e, "THROWN!", Color("ffd23a"), true)
		bt.shake += 3
	await bt.wait(8)

func _act_suplex(u: Unit, c: Dictionary, tg: Unit, sc: bool) -> void:
	u.face = 1 if tg.x >= u.x else -1
	tg.fl["carried"] = u.id
	tg.x = u.x; tg.y = u.y - u.h - 4
	tg.vx = 0; tg.vy = 0; tg.walk = null; tg.air = false
	Sfx.play("toss")
	await bt.wait(14)
	tg.fl.erase("carried")
	tg.x = u.x - u.face * 22
	tg.vy = 7.0; tg.vx = 0; tg.air = true; tg.bumped = {u.id: true}; tg.last_hit_by = u
	var t0 := bt.t
	await bt.until(func(): return not tg.air or tg.dead or bt.t - t0 > 120)
	var d := bt.ri(c.dmg[0], c.dmg[1]) + (6 if u.perk("bodyslam") else 0) + (6 if bt.ks(u, "luchamask") else 0)
	if sc:
		d = int(round(d * 1.25))
	bt.damage(tg, d, u, {"melee": true})
	if bt.ks(u, "luchamask"):
		bt.add_status(tg, "stun", 1, u)
	bt.float_text(tg, "SUPLEX!", Color("ffd23a"), true)
	bt.shake += 4
	for k in 6:
		bt.dust(tg.x + randf_range(-12, 12), tg.y)
	await bt.wait(10)

func _act_piledrive(u: Unit, c: Dictionary, tg: Unit) -> void:
	u.face = 1 if tg.x >= u.x else -1
	u.held = tg
	tg.fl["carried"] = u.id
	bt.banner("PILEDRIVER!", Color("ffb23e"))
	Sfx.play("power")
	await bt.vharr_ai.leap_to(u, Vector2(u.x, u.y - 70))
	u.vy = 10.0; u.vx = 0; u.air = true; u.jumping = true; u.walk = null
	await bt.until(func(): return not u.air or u.dead)
	u.held = null
	tg.fl.erase("carried")
	tg.x = u.x + u.face * 10
	var gy = bt.T.stand_y(tg.x, u.y - 40)
	tg.y = gy if gy != null else u.y
	bt.damage(tg, bt.ri(c.dmg[0], c.dmg[1]), u, {"melee": true})
	bt.T.carve(tg.x, tg.y + 6, 24, u)
	bt.shake += 10
	Sfx.play("bigboom")
	for e in bt.units:
		if e.team == "enemy" and not e.dead and e != tg and absf(e.x - tg.x) < 80 and absf(e.y - tg.y) < 50:
			bt.add_status(e, "stun", 1, u)
	await bt.wait(14)

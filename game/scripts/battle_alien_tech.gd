class_name BattleAlienTech
extends RefCounted
## Vharr tech in the squad's hands.
## Split out of battle.gd (R3). Functions only: every piece of mission state lives on the Battle,
## reached through `bt`.

var bt: Battle

func _init(battle: Battle) -> void:
	bt = battle

func vharr_blink(u: Unit, reach: float) -> void:
	## Blink Pack: step out of the air right behind the nearest enemy, facing it.
	var foes := bt.units.filter(func(e): return e.team == "enemy" and not e.dead and not e.gone and absf(e.x - u.x) <= reach and not bt.is_boss(e))
	foes.sort_custom(func(a, b): return absf(a.x - u.x) < absf(b.x - u.x))
	for e in foes:
		var side := 1 if e.x >= u.x else -1
		var nx: float = e.x + side * (e.w / 2.0 + 16)
		var ny = bt.T.stand_y(nx, e.y - 40)
		if ny == null or nx < bt.cam_x + 10 or nx > bt.cam_x + bt.W - 10:
			continue
		Sfx.play("warp")
		if bt.vfx != null:
			await bt.vharr_ai.teleport(u, Vector2(nx, ny), -side)
		else:
			for k in 6:
				bt.puff(u.x + randf_range(-8, 8), u.y - randf_range(0, 30), 1.5)
			u.x = nx
			u.y = ny
			u.vx = 0; u.vy = 0; u.air = false; u.walk = null
			u.face = -side
			for k in 6:
				bt.puff(u.x + randf_range(-8, 8), u.y - randf_range(0, 30), 1.5)
		bt.float_text(u, "BLINK", Color("c47bff"), true)
		await bt.wait(10)
		return
	bt.float_text(u, "NOTHING TO BLINK TO", Color("9aa2ae"))

func vharr_well(u: Unit, r: float) -> void:
	## Gravity Grenade: a Warden's well on the biggest bunch of enemies within reach, pulling them in.
	var foes := bt.units.filter(func(e): return e.team == "enemy" and not e.dead and not e.gone and absf(e.x - u.x) < 460 and e.x > bt.cam_x and e.x < bt.cam_x + bt.W)
	var best = null
	var best_n := -1
	for e in foes:
		var n := foes.filter(func(o): return absf(o.x - e.x) < r).size()
		if n > best_n:
			best = e
			best_n = n
	if best == null:
		bt.float_text(u, "NO TARGETS", Color("9aa2ae"))
		return
	var well := {"x": best.x, "y": best.y - 20.0, "r": r, "by": u, "foes": true}
	bt.float_at(well.x, well.y - 40, "GRAVITY WELL", Color("c47bff"), true)
	Sfx.play("power")
	await bt.vharr_ai.pull_well(well)
	if u.perk("crushwell"):
		for e in bt.spec_kits.vis_foes():
			if absf(e.x - well.x) < r:
				bt.damage(e, 5, u)

func relay_waves() -> void:
	## O4: while a relay is being held, Jackals pour in from the right at the start of each enemy phase.
	for r in bt.units.filter(func(o): return o.kind == "relay" and o.loot.hold >= 1 and o.loot.hold < Data.RELAY_HOLD):
		var x := minf(bt.world_w - 20.0, bt.cam_x + bt.W - 30)
		for k in 2:
			var px := x - k * 22
			var e := bt.mk_enemy("grunt", px, bt.T.stand_y(px, 0))
			e.active = true
			bt.units.append(e)
		bt.float_at(x - 10, bt.T.ground_at(x) - 60, "RELAY WAVE", Color("ff7a3d"), true)

func call_slug(by: Unit) -> void:
	## The SV-001 drops in beside the caller and stays for one round.
	var sl := bt.mk_unit()
	sl.team = "ally"; sl.kind = "slug"; sl.heavy = true
	sl.x = clampf(by.x + 40, bt.cam_x + 60, bt.cam_x + bt.W - 120); sl.y = -60.0; sl.air = true; sl.vy = 4.0
	sl.w = 64; sl.h = 40; sl.hp = 99; sl.max_hp = 99; sl.face = 1
	sl.last_hit_by = by
	sl.loot = {"turns": 2 if Run.hq("motor") >= 2 else 1, "by": by}
	bt.units.append(sl)
	bt.banner("SV-001 SLUG!", Color("62d26f"), "METAL SLUG ON THE FIELD")
	Sfx.play("power")
	bt.shake += 6

func slug_act(sl: Unit) -> void:
	## Rolls forward crushing whatever is in front, then shells the three nearest Jackals.
	bt.banner("SLUG ATTACK", Color("62d26f"))
	sl.rushing = true; sl.bumped = {}; sl.air = true; sl.vx = 6.5; sl.vy = -3.2; sl.walk = null
	# it can roll off a ledge into the water, and step() never lands a sunk unit
	await bt.until(func(): return not sl.air or sl.sunk or sl.gone or sl.dead)
	sl.rushing = false
	if sl.sunk or sl.gone or sl.dead:
		return
	var foes: Array = bt.units.filter(func(e): return e.team == "enemy" and not e.dead and e.x > bt.cam_x - 20 and e.x < bt.cam_x + bt.W + 40)
	foes.sort_custom(func(a, b2): return absf(a.x - sl.x) < absf(b2.x - sl.x))
	for e in foes.slice(0, 3):
		var mx := sl.x + 30
		var my := sl.y - 34
		var a := atan2(e.y - e.h / 2.0 - my, e.x - mx)
		Sfx.play("rocket")
		bt.projs.append(bt.phys.mk_proj({"kind": "rocket", "x": mx, "y": my, "vx": cos(a) * 11, "vy": sin(a) * 11, "grav": 0.0, "r": 40.0, "dmg": 16, "owner": sl.loot.by, "trail": true}))
		await bt.wait(16)
	await bt.until(bt.settled)

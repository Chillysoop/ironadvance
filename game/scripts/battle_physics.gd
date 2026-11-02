class_name BattlePhysics
extends RefCounted
## Walking, falling and thrown things.
## Split out of battle.gd (R3). Functions only: every piece of mission state lives on the Battle,
## reached through `bt`.

var bt: Battle

func _init(battle: Battle) -> void:
	bt = battle

# ---------------------------------------------------------------- movement
func walk_bounds(u: Unit) -> Vector2:
	if u.team == "squad":
		return Vector2(bt.cam_x + 12, bt.cam_x + bt.W - 16)
	var mn := bt.cam_x + 24
	for s in bt.squad_alive():
		if s.x < u.x and not s.trapped:
			mn = maxf(mn, s.x + 26)
	return Vector2(mn, bt.world_w - 20)

func thin_post(x: float, y: float, dir: int) -> bool:
	## posts and pillars (wood or rock, up to 24px thick) are scenery you walk in front of
	var m := bt.T.mat(x, y)
	if m != 3 and m != 4:
		return false
	for k in range(1, 7):
		if not bt.T.solid(x + dir * k * bt.CELL, y):
			return true
	return false

func blocks(x: float, y: float, dir: int) -> bool:
	return bt.T.solid(x, y) and not thin_post(x, y, dir)

func sim_walk(u: Unit, tx: float, budget: float) -> Dictionary:
	var bnd := walk_bounds(u)
	tx = clampf(tx, bnd.x, bnd.y)
	var x := u.x
	var y: float = u.y
	var used := 0.0
	var pts: Array = []
	var dir := int(signf(tx - x))
	if dir == 0 or u.air or u.dead:
		return {"pts": pts, "x": x, "y": y, "used": used}
	while used < budget - 0.01:
		var rem := absf(tx - x)
		if rem < 0.5:
			break
		var st := minf(2, minf(rem, budget - used))
		var nx := x + dir * st
		var ny := y
		if blocks(nx, ny - 1, dir):
			var c := 0
			while blocks(nx, ny - 1, dir) and c < 3:
				ny -= bt.CELL
				c += 1
			if blocks(nx, ny - 1, dir):
				break
		elif not bt.T.solid(nx, ny):
			while not bt.T.solid(nx, ny) and ny < bt.WATER_Y:
				ny += bt.CELL
			if ny >= bt.WATER_Y:
				break
		var blocked := false
		var inside := false
		var hy := ny - u.h + 2
		while hy < ny - 1:
			if bt.T.solid(nx, hy):
				inside = true
				if blocks(nx, hy, dir):
					blocked = true
					break
			hy += bt.CELL
		if blocked:
			break
		x = nx
		y = ny
		used += st
		pts.append([x, y, inside])
	# never stop inside a pillar: back up to the last clear spot
	while pts.size() and pts[-1][2]:
		pts.pop_back()
	if pts.size():
		x = pts[-1][0]
		y = pts[-1][1]
		used = absf(x - u.x)
	else:
		x = u.x
		y = u.y
		used = 0
	return {"pts": pts, "x": x, "y": y, "used": used}

func walk_along(u: Unit, pts: Array) -> void:
	if pts.is_empty():
		return
	u.walk = pts
	u.walk_i = 0
	# the tick skips gone and sunk units, so their walk would never finish: stop waiting on them too
	await bt.until(func(): return u.walk == null or u.dead or u.gone or u.sunk)
	if u.gone or u.sunk:
		u.walk = null

# ---------------------------------------------------------------- projectiles
func mk_proj(o: Dictionary) -> Dictionary:
	var p := {"age": 0, "vx": 0.0, "vy": 0.0, "wind": 0.0, "grav": 1.0, "r": 30.0, "dmg": 10, "bounce": false, "fuse": null, "dead": false, "smoke": false, "gas": false, "card": {}, "x0": 0.0, "srad": 64.0, "sturns": 2, "bombs": 3, "cluster": 0, "beacon": false, "trail": false, "mini": false, "owner": null}
	p.merge(o, true)
	return p

func unit_hit(p: Dictionary):
	for u in bt.units:
		if u.dead or u.gone or u.kind == "pow" or u.is_pickup() or u.weight == "buried":
			continue
		if u == p.owner and p.age < 24:
			continue
		if p.owner != null and u != p.owner and u.team == p.owner.team:
			continue
		if p.x >= u.x - u.w / 2.0 and p.x <= u.x + u.w / 2.0 and p.y >= u.y - u.h and p.y <= u.y:
			return u
	return null

func detonate(p: Dictionary) -> void:
	p.dead = true
	if p.kind == "droppod":
		bt.explode(p.x, p.y, p.r, p.dmg, p.owner)
		bt.vharr_ai.land_pod(p.x, p.y, p.get("cargo", ["skitter"]))
		return
	var pc: Dictionary = p.card
	if pc.has("build"):
		bt.spec_kits.build_at(p)
		return
	if pc.get("sticky", false):
		bt.spec_kits.plant_sticky(p.x, p.y, p.owner, p.dmg, p.r)
		return
	if pc.has("flare"):
		bt.spec_kits.flare_at(p.x, p.y - 10, pc.flare + (40.0 if p.owner is Unit and p.owner.perk("brightflare") else 0.0), p.owner)
		return
	if pc.has("singularity"):
		bt.spec_kits.singularity_at(p.x, p.y - 14, pc.singularity, pc.get("crushdmg", 0), p.owner)
		return
	if p.beacon and pc.get("rain", 0) > 0:
		bt.spec_kits.steel_rain(p.x, pc.rain, p.owner)
		if pc.get("barrage", 0) <= 0:
			return
	if p.smoke and pc.get("multi", 0) > 1:
		for k in pc.multi:
			var ox: float = (k - (pc.multi - 1) / 2.0) * p.srad * 1.3
			bt.smokes.append({"x": p.x + ox, "y": p.y - 24, "r": p.srad, "turns": p.sturns, "seed": randf() * 10})
		Sfx.play("splash")
		return
	if pc.get("markall", false):
		for o2 in bt.units:
			if o2.team == "enemy" and not o2.dead and absf(o2.x - p.x) < 170:
				bt.add_status(o2, "mark", 2, p.owner)
	if pc.get("fuelgas", false):
		bt.gases.append({"x": p.x, "y": p.y - 20, "r": 70.0, "turns": 1, "seed": 0.0, "owner": p.owner})
	if p.beacon and pc.get("barrage", 0) > 0:
		var dir := 1.0 if p.owner == null or p.x >= p.owner.x else -1.0
		for k in pc.barrage:
			bt.projs.append(mk_proj({"kind": "bomb", "x": p.x + dir * (k - 1) * 38, "y": -20.0 - k * 26, "vx": 0.0, "vy": 5.0, "r": 46.0, "dmg": 14, "owner": p.owner}))
		bt.float_at(p.x, p.y - 20, "BARRAGE!", Color("ffb23e"), true)
		Sfx.play("alarm")
		return
	if p.owner is Unit and p.owner.team == "squad" and p.owner.perk("rangefinder") and p.dmg > 0:
		p.dmg += 2 * int(absf(p.x - p.x0) / 200.0)
	if p.gas:
		bt.gases.append({"x": p.x, "y": p.y - 20, "r": p.srad, "turns": p.sturns, "seed": randf() * 10, "owner": p.owner})
		Sfx.play("splash")
		bt.float_at(p.x, p.y - 30, "GAS", Color("9be34a"), true)
		return
	if p.smoke:
		bt.smokes.append({"x": p.x, "y": p.y - 24, "r": p.srad, "turns": p.sturns, "seed": randf() * 10})
		Sfx.play("splash")
		for i in 6:
			bt.puff(p.x + randf_range(-30, 30), p.y - randf_range(0, 40), 3.0)
		return
	if p.beacon:
		bt.strikes.append({"x": p.x, "owner": p.owner, "friendly": true, "n": p.bombs})
		bt.float_at(p.x, p.y - 20, "BEACON SET", Color("62d26f"), true)
		Sfx.play("tick")
		return
	if bt.debug:
		print("[proj r%d] %s owner %s dmg%d" % [bt.round_n, p.kind, (p.owner.type if p.owner.team != "squad" else p.owner.def.key) if p.owner is Unit else "null", p.dmg])
	bt.explode(p.x, p.y, p.r, p.dmg, p.owner, pc.get("burnblast", false))
	if pc.has("acid"):
		bt.spec_kits.acid_puddle(p.x, bt.T.ground_at(p.x) if not bt.T.solid(p.x, p.y + 4) else p.y, pc.acid, p.owner)
	if pc.get("junk", false):
		bt.spec_kits.scrap_heap(p.x, p.y, p.owner)
	if pc.has("carve"):
		bt.T.carve(p.x, p.y, pc.carve, p.owner)
	if pc.get("flash", false):
		for o2 in bt.units:
			if o2.team == "enemy" and not o2.dead and Vector2(o2.x - p.x, o2.y - o2.h / 2.0 - p.y).length() < p.r + 10:
				bt.add_status(o2, "stun", 1, p.owner)
	if pc.get("napalm", false):
		for k in range(-3, 4):
			if k != 0:
				bt.booms.append({"t": 6 + absi(k) * 6, "x": p.x + k * 40, "y": p.y - 6, "r": 24.0, "dmg": 4, "owner": p.owner, "burn": true})
	if pc.get("shrapnel", 0) > 0 and p.owner is Unit:
		for k in pc.shrapnel:
			var a: float = -PI + PI * (k + 0.5) / pc.shrapnel
			bt.fire_bullet(p.owner, p.x, p.y - 6, a, {"dmg": [3, 4], "range": 220, "bounce": 0}, false)
	if pc.get("key", "") == "mortar" and p.owner is Unit and p.owner.perk("fireforeffect"):
		bt.strikes.append({"x": p.x, "owner": p.owner, "friendly": true, "n": 1})
		bt.float_at(p.x, p.y - 34, "FIRE FOR EFFECT", Color("ffb23e"))
	if p.cluster:
		for i in p.cluster:
			bt.projs.append(mk_proj({"kind": "frag", "x": p.x, "y": p.y - 8, "vx": (randf() - .5) * 7, "vy": -3 - randf() * 4, "wind": 0.5, "r": 24.0, "dmg": 7, "bounce": true, "fuse": 40 + bt.ri(0, 45), "owner": p.owner, "mini": true}))

func update_proj(p: Dictionary) -> void:
	p.age += 1
	if p.trail and p.age % 2 == 0:
		bt.part({"x": p.x, "y": p.y, "vx": 0.0, "vy": -0.2, "life": 24, "max": 24, "c": Color("ffb23e") if p.kind == "rocket" else Color("9a9a9a"), "s": 3.0, "g": 0.0, "smoke": p.kind != "rocket"})
	if p.get("homing", false) and p.age > 10:
		var best = null
		for e in bt.units:
			if e.team == "enemy" and not e.dead and e.active and Vector2(e.x - p.x, e.y - e.h / 2.0 - p.y).length() < 520:
				if best == null or absf(e.x - p.x) < absf(best.x - p.x):
					best = e
		if best != null:
			var sp := Vector2(p.vx, p.vy).length()
			var cur := atan2(p.vy, p.vx)
			var want := atan2(best.y - best.h / 2.0 - p.y, best.x - p.x)
			var da := wrapf(want - cur, -PI, PI)
			cur += clampf(da, -0.07, 0.07)
			p.vx = cos(cur) * sp
			p.vy = sin(cur) * sp
	p.vx += bt.wind * 0.006 * p.wind
	p.vy += bt.grav * p.grav
	if p.grav > 0 and bt.wells.size():
		var wa := bt.well_acc(p.x, p.y)
		p.vx += wa.x; p.vy += wa.y
	var n := maxi(1, int(ceil(Vector2(p.vx, p.vy).length() / 2.0)))
	for i in n:
		var px: float = p.x
		var py: float = p.y
		p.x += p.vx / n
		p.y += p.vy / n
		if p.y > bt.WATER_Y + 4:
			bt.splash(p.x)
			p.dead = true
			return
		if p.x < 0 or p.x > bt.world_w:
			p.dead = true
			return
		var hu = unit_hit(p) if p.age > 2 else null
		if p.get("lizard", false) and hu == null and proj_solid(p, p.x, p.y):
			# Iron Lizard: hug the ground and keep crawling until it meets a body or a tall wall
			var sy = bt.T.stand_y(p.x, p.y - 14)
			p.crawl = p.get("crawl", 0.0) + absf(p.vx / n)
			if sy != null and absf(sy - p.y) < 18 and p.crawl < 420:
				p.y = sy - 3
				p.vy = 0.0
				p.vx = signf(p.vx) * 5.0
				continue
		if proj_solid(p, p.x, p.y) or hu != null:
			if p.bounce:
				if hu != null:
					p.x = px; p.y = py; p.vx *= -0.2; p.vy *= -0.2
					break
				var sx := proj_solid(p, p.x, py)
				var sy := proj_solid(p, px, p.y)
				var rub := bt.T.mat(p.x, p.y) == Terrain.RUBBER
				p.x = px
				p.y = py
				if sx or not sy:
					p.vx = -p.vx * (0.9 if rub else 0.45)
				if sy or not sx:
					p.vy = -p.vy * (0.95 if rub else 0.4)
				p.vx *= 0.85
				if absf(p.vy) > 1:
					Sfx.play("tick")
				break
			p.x = px
			p.y = py
			detonate(p)
			return
	if p.fuse != null:
		p.fuse -= 1
		if p.fuse <= 0:
			detonate(p)
			return
	if p.age > 700:
		detonate(p)

func proj_solid(p: Dictionary, x: float, y: float) -> bool:
	## Thrown things (grenades, bombs) bounce off grating and chain-link; rockets fly through like bullets.
	return bt.T.solid(x, y) if p.grav > 0 else bt.T.hard(x, y)

func sim_arc(sx: float, sy: float, vx: float, vy: float, wind_f: float, steps: int) -> Dictionary:
	## Thrown things and jumping bodies both land on grating and chain-link.
	var pts: Array = []
	var x := sx
	var y := sy
	for i in steps:
		vx += bt.wind * 0.006 * wind_f
		vy += bt.grav
		if bt.wells.size():
			var wa := bt.well_acc(x, y)
			vx += wa.x; vy += wa.y
		x += vx
		y += vy
		pts.append(Vector2(x, y))
		if y > bt.WATER_Y or x < 0 or x > bt.world_w or bt.T.solid(x, y):
			return {"pts": pts, "x": x, "y": y, "end": true}
	return {"pts": pts, "x": x, "y": y, "end": false}

func sim_grenade(sx: float, sy: float, vx: float, vy: float, wind_f: float, frames: int) -> Dictionary:
	## A bouncing grenade's whole flight up to its fuse, with the same bounces update_proj gives it.
	var pts: Array = []
	var x := sx
	var y := sy
	for f in frames:
		vx += bt.wind * 0.006 * wind_f
		vy += bt.grav
		if bt.wells.size():
			var wa := bt.well_acc(x, y)
			vx += wa.x; vy += wa.y
		var n := maxi(1, int(ceil(Vector2(vx, vy).length() / 2.0)))
		for i in n:
			var px := x
			var py := y
			x += vx / n
			y += vy / n
			if y > bt.WATER_Y + 4 or x < 0 or x > bt.world_w:
				pts.append(Vector2(x, y))
				return {"pts": pts, "x": x, "y": y, "lost": true}
			if bt.T.solid(x, y):
				var hx := bt.T.solid(x, py)
				var hy := bt.T.solid(px, y)
				var rub := bt.T.mat(x, y) == Terrain.RUBBER
				x = px
				y = py
				if hx or not hy:
					vx = -vx * (0.9 if rub else 0.45)
				if hy or not hx:
					vy = -vy * (0.95 if rub else 0.4)
				vx *= 0.85
				break
		pts.append(Vector2(x, y))
	return {"pts": pts, "x": x, "y": y, "lost": false}

func solve_arc(sx: float, sy: float, tx: float, ty: float, wind_f: float, pmax: float):
	var dir := -1.0 if tx < sx else 1.0
	var best = null
	var a := 12.0
	while a <= 80:
		var p := 3.0
		while p <= pmax:
			var vx := cos(deg_to_rad(a)) * p * dir
			var vy := -sin(deg_to_rad(a)) * p
			var r := sim_arc(sx, sy, vx, vy, wind_f, 320)
			if r.end and r.pts.size() >= 4:
				var e := Vector2(r.x - tx, r.y - ty).length()
				if best == null or e < best.e:
					best = {"e": e, "vx": vx, "vy": vy}
			p += 0.5
		a += 2.5
	return best

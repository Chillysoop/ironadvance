extends RefCounted
## Trailer capture: stages one cinematic clip per run, HUD hidden, for Godot's movie writer.
##   godot --path . --resolution 960x540 --fixed-fps 60 --write-movie out/clip.png -- --iatest --scenario=trailer --clip=<name>
## Clips: title, firefight, frag, topple, bridge, fort, crane, boss, aliens, jet, gate.
## v2 clips (cine view, picked squads, other biomes): see V2 below.
## Prints "[mark] <name> <frame>" at the beats so the edit can cut on them.

var t: Node  # the test runner (until, frames_wait, cam_on, spawn_alien ...)
var main: Node

var b_now: Battle = null
var cine := false  # v2 clips hide plates, barks and push zone words

func mark(what: String, at = null) -> void:
	## frame number, plus where on screen the beat happens (for the edit's crop)
	var p := Vector2(-1, -1)
	if at is Unit:
		p = Vector2(at.x, at.y - at.h * 0.5)
	elif at is Vector2:
		p = at
	if b_now != null and p.x >= 0:
		p.x -= b_now.cam_x
	print("[mark] ", what, " ", Engine.get_frames_drawn(), " ", int(p.x), " ", int(p.y))

func battle(idx: int, custom := {}) -> Battle:
	var b: Battle = main.start_battle(idx, custom)
	await t.until(func(): return b.state == "player" and not b.busy)
	main.hud.visible = false
	b.autopick = 1
	b.view.cine = cine
	b_now = b
	return b

func frame_on(b: Battle, x: float) -> void:
	t.cam_on(b, x)

func run(runner: Node, clip: String) -> void:
	t = runner
	main = runner.main
	Run.new_run()
	cine = clip not in ["title", "gate"]
	match clip:
		"title":
			main.show_title()
			mark("start")
			await t.frames_wait(300)
		"firefight":
			await firefight()
		"frag":
			await frag()
		"topple":
			await topple()
		"bridge":
			await bridge()
		"fort":
			await fort()
		"crane":
			await crane()
		"boss":
			await boss()
		"aliens":
			await aliens()
		"jet":
			await jet()
		"gate":
			await gate()
		_:
			if V2.has(clip):
				await call(V2[clip])
			else:
				print("unknown clip ", clip)
	mark("end")

func aim_and_fire(b: Battle, u: Unit, key: String, at: Vector2, hold := 40) -> void:
	b.state = "player"; b.busy = false
	b.select_unit(u)
	u.energy = 3
	var idx: int = t.force_card(u, key)
	b.select_card(idx)
	b.mouse = at
	await t.frames_wait(hold)
	b.commit_aim(b.mouse)
	b.mouse = Vector2(-500, -500)
	await t.until(func(): return not b.busy, 900)

func firefight() -> void:
	var b := await battle(0)
	var sq: Array = b.squad_alive()
	var e: Unit = t.nearest_enemy(b, sq[0])
	# close the gap so shooter and target share a tight frame
	for i in sq.size():
		t.ground_unit(b, sq[i], e.x - 250 - i * 22, e.y - 80)
	frame_on(b, e.x - 120)
	await t.frames_wait(40)
	var u: Unit = sq[0]
	mark("aim", u)
	mark("target", e)
	await aim_and_fire(b, u, "rifle", Vector2(e.x, e.y - e.h * 0.8), 50)
	var v: Unit = sq[2]
	e = t.nearest_enemy(b, v)
	mark("rocket", v)
	mark("target", e)
	if e != null:
		await aim_and_fire(b, v, "bazooka", Vector2(e.x, e.y - 10), 30)
	await t.frames_wait(60)

func frag() -> void:
	var b := await battle(0)
	var u: Unit = b.squad_alive()[1]
	var e: Unit = t.nearest_enemy(b, u)
	frame_on(b, (u.x + e.x) / 2.0)
	await t.frames_wait(20)
	mark("aim", u)
	mark("target", e)
	await aim_and_fire(b, u, "frag", Vector2(e.x, e.y - 20), 40)
	await t.frames_wait(40)

func topple() -> void:
	var b := await battle(0)
	var tw: Dictionary = b.T.structs.filter(func(s): return s.t == "tower")[0]
	frame_on(b, tw.x + 60)
	await t.frames_wait(40)
	mark("boom", Vector2(tw.x, b.T.ground_at(tw.x) - 60))
	b.explode(tw.x, b.T.ground_at(tw.x) - 14, 16, 0, b.sel)
	await t.until(func(): return b.settled(), 600)
	await t.frames_wait(40)

func bridge() -> void:
	var b := await battle(0)
	var br: Dictionary = t.find_struct(b, "bridge")
	frame_on(b, (br.x0 + br.x1) / 2.0)
	await t.frames_wait(40)
	mark("boom", Vector2((br.x0 + br.x1) / 2.0, br.y))
	b.explode(br.posts[0], br.y + 40, 22, 0, b.squad()[0])
	await t.until(func(): return b.settled(), 1200)
	await t.frames_wait(40)

func fort() -> void:
	var b := await battle(0)
	var ft: Dictionary = t.find_struct(b, "fort")
	frame_on(b, ft.x + ft.w / 2.0)
	await t.frames_wait(40)
	var g: float = b.T.ground_at(ft.x + ft.w / 2.0)
	mark("boom", Vector2(ft.x + ft.w / 2.0, g - 60))
	b.explode(ft.x + ft.w - 4, g - 16, 24, 0, b.squad()[0])
	await t.until(func(): return b.settled(), 1500)
	await t.frames_wait(40)

func find_boss(b: Battle) -> Unit:
	for u in b.units:
		if u.type == "boss":
			return u
	return null

func crane() -> void:
	var b := await battle(2)
	var cr: Dictionary = b.T.structs.filter(func(s): return s.t == "crane")[-1]
	frame_on(b, cr.hook)
	await t.frames_wait(50)
	mark("cut", Vector2(cr.hook, b.T.ground_at(cr.hook) - 80))
	var top: float = b.T.ground_at(cr.x + 6) - cr.h
	b.T.carve(cr.hook, top + 8 + cr.rope / 2.0, 5, b.squad()[0])
	await t.until(func(): return b.settled(), 1200)
	await t.frames_wait(40)

func boss() -> void:
	## the Iron Boar opens up on a soldier, then eats a rocket back
	var b := await battle(2)
	var bo := find_boss(b)
	var s: Unit = b.squad()[0]
	for o in b.units:
		if o != bo and (o.team == "enemy" or o.kind == "pow") and absf(o.x - bo.x) < 700:
			o.dead = true; o.gone = true  # a clean duel
	for o in b.squad():
		t.ground_unit(b, o, bo.x - 360 + b.squad().find(o) * 26, bo.y - 60)
	frame_on(b, bo.x - 170)
	await t.frames_wait(40)
	mark("boss", bo)
	mark("target", s)
	bo.active = true
	await b.enemy_act(bo)
	await t.until(func(): return b.settled(), 900)
	await t.frames_wait(20)
	var v: Unit = b.squad_alive()[0]
	for o in b.squad_alive():
		if o.def.key == "vee":
			v = o
	mark("rocket", v)
	await aim_and_fire(b, v, "bazooka", Vector2(bo.x - 10, bo.y - 16), 30)
	await t.frames_wait(50)

func aliens() -> void:
	Run.level = Run.make_level("fortress", 1)
	var b := await battle(1, Run.level)
	b.speed = 1.0
	var x0 := 300.0
	while not t.flat_open(b, x0 - 120, 420):
		x0 += 20
	var s: Unit = t.alien_field(b, x0)
	var pack: Array = []
	for i in 3:
		pack.append(t.spawn_alien(b, "skitter", x0 + 220 + i * 26))
	var sq: Unit = t.spawn_alien(b, "squid", x0 + 340)
	sq.hold = true
	var bl: Unit = t.spawn_alien(b, "blinker", x0 + 300)
	await t.frames_wait(40)
	mark("skitter", pack[0])
	mark("target", s)
	await b.enemy_act(pack[0])
	await t.until(func(): return b.settled(), 600)
	mark("squid", sq)
	await b.enemy_act(sq)
	await t.until(func(): return b.settled(), 600)
	mark("blinker", bl)
	s.hp = s.max_hp
	await b.enemy_act(bl)
	await t.until(func(): return b.settled(), 600)
	await t.frames_wait(30)

func jet() -> void:
	var b := await battle(0)
	var s: Unit = b.squad()[3]
	Run.equip(s.s, Run.new_item("jetboots", 0))
	b.refresh_unit_gear(s)
	frame_on(b, s.x + 220)
	b.state = "player"; b.busy = false
	b.select_unit(s)
	var jt := Vector2(s.x + 200, s.y - 220)
	b.toggle_jet()
	b.mouse = jt
	await t.frames_wait(30)
	mark("jet", s)
	b.jet_armed = false
	b.mouse = Vector2(-500, -500)
	b.resolve(func(): await b._act_jet(s, func(): return jt, func(): return true))
	await t.until(func(): return not b.busy, 1200)
	mark("landed", s)
	var e: Unit = t.nearest_enemy(b, s)
	if e != null:
		await aim_and_fire(b, s, "rifle", Vector2(e.x, e.y - e.h * 0.7), 25)
	await t.frames_wait(40)

func gate() -> void:
	main.start_run()
	main.screen.dial.emit()
	await t.frames_wait(5)
	t.press_first()
	await t.frames_wait(5)
	t.press_first()
	await t.frames_wait(5)
	var b: Battle = main.battle
	await t.until(func(): return b.state == "player" and not b.busy)
	main.hud.visible = false
	mark("victory")
	b.boss_dead = true
	b.victory()
	await t.until(func(): return b.gate != null and b.gate.chev >= 1, 3000)
	main.hud.visible = false
	mark("dial")
	await t.until(func(): return main.battle == null, 4000)
	mark("hq")
	t.press_first()
	await t.frames_wait(20)
	main.screen.open_all()
	await t.frames_wait(90)
	main.screen.done.emit()
	await t.frames_wait(150)

# ---------------------------------------------------------------- v2: one set piece per clip
const V2 := {
	"jumppack": "v_jumppack", "grapple": "v_grapple", "drill": "v_drill", "rocketjump": "v_rocketjump",
	"blink": "v_blink", "cannonball": "v_cannonball", "blackhole": "v_blackhole", "cuts": "v_cuts",
	"hounds": "v_hounds", "slug": "v_slug", "eject": "v_eject", "barrage": "v_barrage",
	"steelrain": "v_steelrain", "gasfire": "v_gasfire", "cluster": "v_cluster", "rush": "v_rush",
	"tesla": "v_tesla", "zantetsu": "v_zantetsu", "napalm": "v_napalm", "collapse": "v_collapse",
	"haymaker": "v_haymaker", "tank": "v_tank", "queen": "v_queen", "shotgun": "v_shotgun",
	"levelup": "v_levelup", "meta": "v_meta", "played": "v_played",
}

func squad_battle(draft: Array, biome := "", tier := 0) -> Battle:
	for k in draft:
		if not Run.meta.unlocked.has("cls_" + k):
			Run.meta.unlocked.append("cls_" + k)
	Run.meta["draft"] = draft
	Run.leave_campaign()
	Run.new_run()
	if biome != "":
		Run.level = Run.make_level(biome, tier)
		return await battle(tier, Run.level)
	return await battle(0)

func who(b: Battle, key: String) -> Unit:
	for u in b.squad():
		if u.def.key == key:
			return u
	return null

func arena(b: Battle, w := 520.0, from := 820.0) -> float:
	## Real ground (rolling is fine, no water or cliffs) at least w wide, every enemy and prop around it cleared away.
	var x := from
	while x < b.world_w - w - 300:
		var y0 = b.T.stand_y(x, 0)
		var ok: bool = y0 != null and y0 < Data.WATER_Y - 20
		var k := 0.0
		while ok and k <= w:
			var y = b.T.stand_y(x + k, 0)
			ok = y != null and absf(y - y0) < 36 and y < Data.WATER_Y - 20
			k += 16
		if ok:
			break
		x += 24
	for o in b.units:
		if (o.team == "enemy" or o.is_prop() or o.is_pickup() or o.kind in ["pow", "ride", "mine", "charge", "barrel", "fuel"]) and absf(o.x - x - w / 2.0) < w / 2.0 + 560:
			o.dead = true; o.gone = true
	b.wind = 0
	return x

func line_up(b: Battle, x: float, keys := []) -> void:
	## The squad stands at x and to the left, the named soldiers first.
	var order: Array = b.squad().duplicate()
	order.sort_custom(func(a, c): return keys.find(a.def.key) > keys.find(c.def.key) if keys.has(a.def.key) and keys.has(c.def.key) else keys.has(a.def.key))
	for i in order.size():
		t.ground_unit(b, order[i], x - i * 26, 0)
		order[i].face = 1
		order[i].st.clear()

func foe(b: Battle, type: String, x: float, hp := 40) -> Unit:
	var y = b.T.stand_y(x, 0)
	var e := b.mk_enemy(type, x, y if y != null else b.T.ground_at(x))
	e.active = true
	e.hp = hp; e.max_hp = hp
	b.units.append(e)
	return e

func pack(b: Battle, x: float, n: int, gap := 28.0, hp := 40, types := ["grunt"]) -> Array:
	var out: Array = []
	for i in n:
		out.append(foe(b, types[i % types.size()], x + i * gap, hp))
	return out

func play(b: Battle, u: Unit, key: String, at = null, hold := 30) -> void:
	## Put the card in u's hand and play it the way a player would: aim, hold, release.
	b.state = "player"; b.busy = false
	b.select_unit(u)
	u.energy = 6
	var c: Dictionary = Data.CARDS[key]
	if c.get("od", false):
		u.hand.append({"id": -1, "key": key, "tier": Data.OD_TIER, "od": true})
	else:
		u.hand.append(Run.new_card(key))
	var idx: int = u.hand.size() - 1
	if c.type == "SELF":
		b.play_self(idx)
	else:
		b.select_card(idx)
		var p: Vector2 = Vector2(at.x, at.y - at.h * 0.6) if at is Unit else at
		if c.type == "ARC":
			# thrown: find the throw that lands on p, then point the mouse the way the player would drag it
			var tx: float = at.x if at is Unit else p.x
			var ty: float = at.y - 4 if at is Unit else p.y
			var hx: float = u.x + (6 if tx > u.x else -6)
			var hy: float = u.y - u.h + 10
			var sol = b.solve_arc(hx, hy, tx, ty, c.get("wind", 1.0), 13)
			if sol != null:
				var pw := Vector2(sol.vx, sol.vy).length()
				p = Vector2(hx, hy) + Vector2(sol.vx, sol.vy).normalized() * (pw / 13.0 * 220)
		b.mouse = p
		await t.frames_wait(hold)
		if c.type in ["MELEE", "ALLY"] and at is Unit:
			b.play_on_target(at)
		else:
			b.commit_aim(p)
		b.mouse = Vector2(-500, -500)
	await settle(b)

func settle(b: Battle, n := 1500) -> void:
	for i in n:
		if not b.busy:
			break
		if t.modal_title(b) != "":
			b.hud.picked.emit(0)
		await t.get_tree().process_frame

func foes_act(b: Battle, list: Array) -> void:
	for e in list:
		if not e.dead and not e.gone:
			await b.enemy_act(e)
			await t.until(func(): return b.settled(), 400)

func v_jumppack() -> void:
	var b := await squad_battle(["moss", "hex", "vee", "rook"], "desert")
	var x := arena(b, 600)
	line_up(b, x, ["rook"])
	var r := who(b, "rook")
	var es := pack(b, x + 420, 3, 30)
	frame_on(b, x + 220)
	await t.frames_wait(30)
	mark("jump", r)
	await play(b, r, "jumppack", Vector2(x + 330, r.y - 150), 40)
	mark("landed", r)
	await play(b, r, "shotgun", es[0], 20)
	await t.frames_wait(60)

func v_grapple() -> void:
	var b := await squad_battle(["moss", "hex", "vee", "rook"], "fortress")
	var ft: Dictionary = t.find_struct(b, "fort")
	if ft.is_empty():
		ft = t.find_struct(b, "warehouse")
	var fx: float = ft.x + ft.w / 2.0 if not ft.is_empty() else 900.0
	var g: float = b.T.ground_at(fx)
	for o in b.units:
		if o.team == "enemy" and absf(o.x - fx) < 900:
			o.dead = true; o.gone = true
	var m := who(b, "moss")
	line_up(b, fx - 200, ["moss"])
	var e := foe(b, "grunt", fx + 260)
	frame_on(b, fx)
	await t.frames_wait(30)
	mark("grapple", m)
	# the highest standable roof near the middle of the building
	var top = b.T.stand_y(fx, g - 400)
	await play(b, m, "grapple", Vector2(fx, (top if top != null else g - 120) - 4), 30)
	mark("roof", m)
	await play(b, m, "snipe", e, 30)
	await t.frames_wait(60)

func v_drill() -> void:
	var b := await squad_battle(["moss", "hex", "vee", "rook"], "mountain")
	var x := 600.0
	var v := who(b, "vee")
	for o in b.units:
		if o.team == "enemy" and absf(o.x - x) < 700:
			o.dead = true; o.gone = true
	line_up(b, x, ["vee"])
	frame_on(b, x + 160)
	await t.frames_wait(30)
	mark("drill", v)
	await play(b, v, "drill", Vector2(v.x + 260, v.y + 120), 30)
	await t.frames_wait(20)
	mark("out", v)
	await play(b, v, "drill", Vector2(v.x + 200, v.y - 140), 10)
	await t.frames_wait(60)

func v_rocketjump() -> void:
	var b := await squad_battle(["moss", "hex", "vee", "rook"], "refinery")
	var x := arena(b, 560)
	line_up(b, x, ["vee"])
	var v := who(b, "vee")
	var es := pack(b, x + 380, 3, 26)
	frame_on(b, x + 200)
	await t.frames_wait(30)
	mark("rj", v)
	await play(b, v, "rocketjump", Vector2(x + 200, v.y - 160), 30)
	mark("air", v)
	await play(b, v, "frag", Vector2(es[1].x, es[1].y - 40), 15)
	await t.frames_wait(60)

func v_blink() -> void:
	var b := await squad_battle(["moss", "hex", "vee", "rook"], "palace")
	var x := arena(b, 500)
	line_up(b, x, ["hex"])
	var h := who(b, "hex")
	var e := foe(b, "grunt", x + 300, 30)
	e.face = -1
	frame_on(b, x + 180)
	await t.frames_wait(30)
	mark("blink", h)
	await play(b, h, "blink")
	mark("stab", h)
	await play(b, h, "haymaker", e, 15)
	await t.frames_wait(60)

func v_cannonball() -> void:
	var b := await squad_battle(["moss", "hex", "vee", "rook"], "jungle")
	var x := arena(b, 620)
	line_up(b, x, ["rook", "vee"])
	var r := who(b, "rook")
	var es := pack(b, x + 440, 4, 22)
	frame_on(b, x + 260)
	await t.frames_wait(30)
	mark("cannon", r)
	await play(b, r, "cannonball", Vector2(es[1].x, es[1].y - 20), 40)
	mark("boom", es[1])
	await t.frames_wait(80)

func v_blackhole() -> void:
	var b := await squad_battle(["volta", "kage", "brass", "finch"], "hive")
	var x := arena(b, 640)
	line_up(b, x, ["volta"])
	var vo := who(b, "volta")
	var es := pack(b, x + 300, 5, 34, 40, ["skitter", "grunt", "skitter", "grunt", "skitter"])
	frame_on(b, x + 300)
	await t.frames_wait(30)
	mark("hole", vo)
	await play(b, vo, "blackhole", Vector2(es[2].x, es[2].y - 40), 40)
	await t.frames_wait(80)

func v_cuts() -> void:
	var b := await squad_battle(["kage", "volta", "brass", "finch"], "lake")
	var x := arena(b, 600)
	line_up(b, x, ["kage"])
	var k := who(b, "kage")
	pack(b, x + 140, 5, 40, 30)
	frame_on(b, x + 250)
	await t.frames_wait(30)
	mark("cuts", k)
	await play(b, k, "thousandcuts", Vector2(x + 420, k.y - 10), 30)
	await t.frames_wait(80)

func v_hounds() -> void:
	var b := await squad_battle(["track", "moss", "hex", "vee"], "delta")
	var x := arena(b, 600)
	line_up(b, x, ["track"])
	var tr := who(b, "track")
	pack(b, x + 220, 3, 70, 40)
	frame_on(b, x + 250)
	await t.frames_wait(30)
	mark("hounds", tr)
	await play(b, tr, "wolfpack")
	await t.frames_wait(60)

func v_slug() -> void:
	var b := await squad_battle(["gears", "moss", "hex", "rook"], "desert")
	var x := arena(b, 700)
	line_up(b, x, ["gears"])
	var g := who(b, "gears")
	pack(b, x + 260, 4, 50, 40)
	frame_on(b, x + 300)
	await t.frames_wait(30)
	mark("slug", g)
	b.call_slug(g)
	await t.frames_wait(30)
	await settle(b)
	for o in b.units:
		if o.kind == "slug" and not o.gone:
			mark("roll", o)
			await b.slug_act(o)
			await t.until(func(): return b.settled(), 600)
	await t.frames_wait(150)

func v_eject() -> void:
	var b := await squad_battle(["gears", "moss", "hex", "rook"], "harbor")
	var x := arena(b, 600)
	line_up(b, x, ["gears"])
	var g := who(b, "gears")
	var es := pack(b, x + 380, 3, 24, 40)
	frame_on(b, x + 220)
	await t.frames_wait(30)
	mark("vulcan", g)
	await play(b, g, "vulcan", es[2], 25)
	mark("eject", g)
	await play(b, g, "eject", es[0], 25)
	await t.frames_wait(80)

func v_barrage() -> void:
	var b := await squad_battle(["vee", "moss", "hex", "rook"], "volcano")
	var x := arena(b, 700)
	line_up(b, x, ["vee"])
	var v := who(b, "vee")
	var es := pack(b, x + 270, 5, 30, 40)
	frame_on(b, x + 330)
	await t.frames_wait(30)
	mark("barrage", v)
	await play(b, v, "barrage", Vector2(es[2].x, es[2].y - 20), 30)
	await t.frames_wait(220)

func v_steelrain() -> void:
	var b := await squad_battle(["bolt", "vee", "moss", "hex"], "city")
	var x := arena(b, 640)
	line_up(b, x, ["bolt"])
	var bo := who(b, "bolt")
	var es := pack(b, x + 270, 4, 34, 40)
	frame_on(b, x + 320)
	await t.frames_wait(30)
	mark("steel", bo)
	await play(b, bo, "steelrain", Vector2(es[1].x + 16, es[1].y - 20), 30)
	await t.frames_wait(220)

func v_gasfire() -> void:
	var b := await squad_battle(["vee", "moss", "hex", "rook"], "refinery")
	var x := arena(b, 600)
	line_up(b, x, ["vee", "moss"])
	b.wind = 0
	var v := who(b, "vee")
	var m := who(b, "moss")
	var es := pack(b, x + 250, 4, 26, 40)
	frame_on(b, x + 280)
	await t.frames_wait(30)
	mark("gas", v)
	await play(b, v, "gasnade", Vector2(es[1].x + 10, es[1].y - 30), 25)
	await t.frames_wait(40)
	mark("light", m)
	await play(b, m, "flameshot", es[1], 25)
	await t.frames_wait(80)

func v_cluster() -> void:
	var b := await squad_battle(["vee", "moss", "hex", "rook"], "jungle")
	var x := arena(b, 600)
	line_up(b, x, ["vee"])
	var v := who(b, "vee")
	var es := pack(b, x + 230, 5, 24, 40)
	frame_on(b, x + 260)
	await t.frames_wait(30)
	mark("cluster", v)
	await play(b, v, "cluster", es[2], 30)
	await t.frames_wait(90)

func v_rush() -> void:
	var b := await squad_battle(["rook", "moss", "hex", "vee"], "lake")
	var x := arena(b, 600)
	line_up(b, x, ["rook"])
	var r := who(b, "rook")
	pack(b, x + 160, 4, 28, 40)
	frame_on(b, x + 250)
	await t.frames_wait(30)
	mark("rush", r)
	await play(b, r, "rush", Vector2(x + 300, r.y - 10), 30)
	await t.frames_wait(90)

func v_tesla() -> void:
	var b := await squad_battle(["volta", "kage", "brass", "finch"], "mine")
	var x := arena(b, 560)
	line_up(b, x, ["volta"])
	var vo := who(b, "volta")
	pack(b, x + 110, 3, 90, 40)
	frame_on(b, x + 220)
	await t.frames_wait(30)
	mark("tesla", vo)
	await play(b, vo, "tesla")
	await t.frames_wait(60)

func v_zantetsu() -> void:
	var b := await squad_battle(["moss", "hex", "vee", "rook"], "palace")
	var x := arena(b, 500)
	line_up(b, x, ["rook"])
	var r := who(b, "rook")
	var e := foe(b, "grunt", x + 34, 30)
	var e2 := foe(b, "grunt", x + 58, 30)
	frame_on(b, x + 120)
	await t.frames_wait(30)
	mark("slash", r)
	await play(b, r, "zantetsu", e, 20)
	await t.frames_wait(70)

func v_napalm() -> void:
	var b := await squad_battle(["vee", "moss", "hex", "rook"], "jungle")
	var x := arena(b, 640)
	line_up(b, x, ["vee"])
	var v := who(b, "vee")
	var es := pack(b, x + 250, 4, 34, 40)
	frame_on(b, x + 300)
	await t.frames_wait(30)
	mark("napalm", v)
	await play(b, v, "napalmstrike", Vector2(es[1].x, es[1].y - 20), 30)
	await t.frames_wait(90)

func v_collapse() -> void:
	var b := await squad_battle(["vee", "moss", "hex", "rook"], "city")
	var tw: Dictionary = {}
	for s in b.T.structs:
		if s.t in ["tower", "chimney", "building"] and s.x > 500:
			tw = s
			break
	var tx: float = tw.x if not tw.is_empty() else 900.0
	for o in b.units:
		if o.team == "enemy" and absf(o.x - tx) < 800:
			o.dead = true; o.gone = true
	var v := who(b, "vee")
	line_up(b, tx - 260, ["vee"])
	frame_on(b, tx - 60)
	await t.frames_wait(30)
	mark("collapse", v)
	await play(b, v, "collapse", Vector2(tx, b.T.ground_at(tx) - 10), 30)
	await t.until(func(): return b.settled(), 900)
	await t.frames_wait(40)

func v_haymaker() -> void:
	var b := await squad_battle(["rook", "moss", "hex", "vee"], "mountain")
	var x := arena(b, 500)
	line_up(b, x, ["rook"])
	var r := who(b, "rook")
	var e := foe(b, "grunt", x + 30, 60)
	pack(b, x + 160, 3, 22, 40)
	frame_on(b, x + 160)
	await t.frames_wait(30)
	mark("punch", r)
	await play(b, r, "haymaker", e, 20)
	await t.until(func(): return b.settled(), 600)
	await t.frames_wait(40)

func v_tank() -> void:
	var b := await squad_battle(["gears", "moss", "hex", "rook"], "carrier")
	var x := arena(b, 640)
	line_up(b, x, ["gears"])
	var g := who(b, "gears")
	var es := pack(b, x + 380, 4, 26, 40)
	frame_on(b, x + 260)
	await t.frames_wait(30)
	mark("buster", g)
	await play(b, g, "tankbuster", es[1], 25)
	await t.frames_wait(80)

func v_shotgun() -> void:
	var b := await squad_battle(["moss", "hex", "vee", "rook"], "train")
	var x := arena(b, 500)
	line_up(b, x, ["hex"])
	var h := who(b, "hex")
	var es := pack(b, x + 70, 3, 24, 30)
	frame_on(b, x + 120)
	await t.frames_wait(30)
	mark("shotgun", h)
	await play(b, h, "shotgun", es[0], 20)
	await t.frames_wait(60)

func v_queen() -> void:
	## the Vharr strike back: a skitter pack and a squid on the squad, then the squad answers
	var b := await squad_battle(["moss", "hex", "vee", "rook"], "hive")
	var x := arena(b, 600)
	line_up(b, x, [])
	var pk: Array = []
	for i in 3:
		pk.append(t.spawn_alien(b, "skitter", x + 200 + i * 26))
	var sq: Unit = t.spawn_alien(b, "squid", x + 330)
	frame_on(b, x + 180)
	await t.frames_wait(30)
	mark("aliens", pk[0])
	await foes_act(b, [pk[0], pk[1], sq])
	var v := who(b, "vee")
	mark("answer", v)
	if not v.dead:
		await play(b, v, "bazooka", pk[2] if not pk[2].dead else sq, 20)
	await t.frames_wait(60)

func v_levelup() -> void:
	var b := await squad_battle(["moss", "hex", "vee", "rook"], "desert")
	b.autopick = -1
	var m := who(b, "moss")
	frame_on(b, m.x + 200)
	main.hud.visible = true
	mark("levelup", m)
	b.level_up(m)
	await t.frames_wait(150)
	b.hud.picked.emit(0)
	await t.frames_wait(30)

func v_meta() -> void:
	## A flash of the HQ: hub, Quartermaster, Workshop, Dossier, War Room.
	Run.new_run()
	Run.scrip = 600
	main.show_hq(false)
	await t.frames_wait(30)
	var hq: Control = main.screen
	mark("hq")
	await t.frames_wait(60)
	hq.go("qm")
	await t.frames_wait(10)
	mark("qm")
	await t.frames_wait(60)
	hq.go("workshop")
	await t.frames_wait(10)
	mark("workshop")
	await t.frames_wait(60)
	hq.go("armory")
	await t.frames_wait(10)
	mark("armory")
	await t.frames_wait(60)
	hq.open_dossier(0)
	await t.frames_wait(10)
	mark("dossier")
	await t.frames_wait(60)
	main.show_draft()
	await t.frames_wait(10)
	mark("draft")
	await t.frames_wait(60)

# ---------------------------------------------------------------- v3: real missions, played by the bot
# Cards the bot knows how to play, dealt one a turn so the fights show the deck's range.
const SHOW := {
	"moss": ["snipe", "railshot", "ricochet", "lasergun", "hmg", "bazooka"],
	"hex": ["shotgun", "tesla", "zantetsu", "haymaker", "flameshot", "dropshot"],
	"vee": ["cluster", "clusterfrag", "mortar", "barrage", "napalmstrike", "molotov", "rocket", "missilepod"],
	"rook": ["minigun", "haymaker", "shotgun", "thundershot", "bazooka", "superhmg"],
	"bolt": ["junkcannon", "rivetgun", "sentrynest", "steelrain"],
	"track": ["wolfpack", "hounds", "skyfall"],
	"gears": ["bigslug", "missilepod", "tankbuster"],
	"volta": ["tesla", "blackhole", "singularity"],
	"kage": ["zantetsu", "shotgun", "haymaker"],
	"brass": ["barrage", "m79", "dangerclose"],
	"finch": ["snipe", "hmg"],
	"sable": ["broodcall", "gasnade"],
}

func arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return d

func deal(b: Battle) -> void:
	main.hud.visible = false  # no banners or hint lines over the fight; plates and aim lines stay
	if b.view.tip != null:
		b.view.tip.visible = false  # the bot's cursor rests on enemies; no hover cards over the fight
	for u in b.squad_alive():
		var pool: Array = SHOW.get(u.def.key, [])
		if pool.is_empty() or randf() < 0.25:
			continue
		var key: String = pool[randi() % pool.size()]
		var c: Dictionary = Data.CARDS[key]
		if c.get("od", false):
			u.hand.append({"id": -1, "key": key, "tier": Data.OD_TIER, "od": true})
		else:
			u.hand.append(Run.new_card(key))
		u.energy = maxi(u.energy, 3)

func v_played() -> void:
	## A real mission from the start, the bot playing it at normal speed.
	seed(int(arg("seed", "1")))
	var draft: Array = Array(arg("draft", "moss,hex,vee,rook").split(","))
	for k in draft:
		if not Run.meta.unlocked.has("cls_" + k):
			Run.meta.unlocked.append("cls_" + k)
	Run.meta["draft"] = draft
	Run.leave_campaign()
	Run.new_run()
	var biome := arg("biome", "")
	var tier := int(arg("tier", "0"))
	var custom := {}
	if biome != "":
		Run.level = Run.make_level(biome, tier)
		custom = Run.level
	Run.meta["tips_off"] = true
	t.bot_speed = 1.0
	t.bot_hold = 36
	t.bot_hook = deal
	mark("start")
	await t.bot(tier, int(arg("rounds", "6")), false, custom)

extends RefCounted
## Trailer capture: stages one cinematic clip per run, HUD hidden, for Godot's movie writer.
##   godot --path . --resolution 960x540 --fixed-fps 60 --write-movie out/clip.png -- --iatest --scenario=trailer --clip=<name>
## Clips: title, firefight, frag, topple, bridge, fort, crane, boss, aliens, jet, gate.
## Prints "[mark] <name> <frame>" at the beats so the edit can cut on them.

var t: Node  # the test runner (until, frames_wait, cam_on, spawn_alien ...)
var main: Node

var b_now: Battle = null

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
	b_now = b
	return b

func frame_on(b: Battle, x: float) -> void:
	t.cam_on(b, x)

func run(runner: Node, clip: String) -> void:
	t = runner
	main = runner.main
	Run.new_run()
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

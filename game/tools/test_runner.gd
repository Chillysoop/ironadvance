extends Node
## Headless-ish test harness. Does nothing unless the game is launched with
##   godot --path . -- --iatest --scenario=<name> --out=<dir> [--speed=N]
## Scenarios: title, start, aim, arc, bot, shop, level, topple, campaign, alive, levels, hazards.
## --mission=N picks the mission for bot.

var out_dir := "user://shots"
var scenario := ""
var main: Node
var frames := 0
var mission_arg := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--iatest"):
		set_process(false)
		return
	for a in args:
		if a.begins_with("--scenario="):
			scenario = a.substr(11)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--mission="):
			mission_arg = int(a.substr(10))
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().process_frame
	main = get_tree().current_scene
	run.call_deferred()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("[shot] ", name)

func frames_wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func until(cond: Callable, max_frames := 6000) -> bool:
	var n := 0
	while not cond.call():
		await get_tree().process_frame
		n += 1
		if n > max_frames:
			return false
	return true

func run() -> void:
	print("[test] scenario ", scenario)
	match scenario:
		"title":
			main.show_title()
			await frames_wait(30)
			await shot("title")
		"start":
			Run.new_run()
			var b: Battle = main.start_battle(0)
			await until(func(): return b.state == "player" and not b.busy)
			await frames_wait(10)
			await shot("start")
			b.mouse = Vector2(420, 380)
			await frames_wait(4)
			await shot("start_move")
		"aim":
			Run.new_run()
			var b: Battle = main.start_battle(0)
			await until(func(): return b.state == "player" and not b.busy)
			var u: Unit = b.sel
			var idx := force_card(u, "rifle")
			b.select_card(idx)
			var e := nearest_enemy(b, u)
			b.mouse = Vector2(e.x, e.y - e.h * 0.8)
			await frames_wait(20)
			await shot("aim")
			b.commit_aim(b.mouse)
			await frames_wait(6)
			await shot("aim_fire")
			await until(func(): return not b.busy)
			await shot("aim_after")
		"arc":
			Run.new_run()
			var b: Battle = main.start_battle(0)
			await until(func(): return b.state == "player" and not b.busy)
			var u: Unit = b.squad_alive()[2]
			b.select_unit(u)
			var idx := force_card(u, "frag")
			b.select_card(idx)
			b.mouse = Vector2(u.x + 160, u.y - 120)
			await frames_wait(10)
			await shot("arc")
			b.commit_aim(b.mouse)
			await frames_wait(170)
			await shot("arc_boom")
			await until(func(): return not b.busy)
			idx = force_card(u, "bazooka")
			b.select_card(idx)
			var e := nearest_enemy(b, u)
			b.mouse = Vector2(e.x, e.y - 10)
			await frames_wait(6)
			await shot("rocket_aim")
			b.commit_aim(b.mouse)
			await frames_wait(30)
			await shot("rocket_boom")
		"topple":
			Run.new_run()
			var b: Battle = main.start_battle(0)
			await until(func(): return b.state == "player" and not b.busy)
			var tw: Dictionary = b.T.structs.filter(func(s): return s.t == "tower")[0]
			# blow out the tower's post with a charge and watch it come down
			b.explode(tw.x, b.T.ground_at(tw.x) - 14, 14, 0, b.sel)
			await frames_wait(40)
			await shot("topple_1")
			await frames_wait(60)
			await shot("topple_2")
		"level":
			Run.new_run()
			var b: Battle = main.start_battle(0)
			await until(func(): return b.state == "player" and not b.busy)
			var u: Unit = b.sel
			b.give_xp(u, 20)
			b.resolve(func(): await b.wait(2))
			await frames_wait(120)
			await shot("levelup")
			main.hud.picked.emit(2)
			await frames_wait(30)
			main.hud.show_deck()
			await frames_wait(10)
			await shot("deck")
		"shop":
			Run.new_run()
			Run.scrip = 400
			Run.soldiers[0].hp = 10
			Run.soldiers[3].alive = false
			main.show_shop()
			await frames_wait(20)
			await shot("shop")
		"flow":
			# title -> brief -> each mission (forced win) -> results -> shop -> next brief
			main.show_title()
			await frames_wait(20)
			press_first()
			await frames_wait(20)
			await shot("flow_brief0")
			for m in 3:
				press_first()
				await frames_wait(5)
				var b: Battle = main.battle
				await until(func(): return b.state == "player" and not b.busy)
				await frames_wait(10)
				await shot("flow_m%d" % m)
				b.victory()
				await until(func(): return main.battle == null, 2000)
				await frames_wait(20)
				await shot("flow_result%d" % m)
				if m == 2:
					break
				press_first()
				await frames_wait(20)
				await shot("flow_shop%d" % m)
				main.screen.done.emit()
				await frames_wait(20)
				await shot("flow_brief%d" % (m + 1))
		"alive":
			# ambient life: idle gunfire, critters, flags, smoke; then a blast to scatter the critters
			for m in 3:
				Run.new_run()
				var b: Battle = main.start_battle(m)
				await until(func(): return b.state == "player" and not b.busy)
				await frames_wait(240)
				await shot("alive_m%d_a" % m)
				await until(func(): return b.tracers.size() > 0, 900)
				await frames_wait(1)
				await shot("alive_m%d_b" % m)
				b.explode(b.cam_x + 500, b.T.ground_at(b.cam_x + 500) - 4, 20, 0, null)
				await frames_wait(12)
				await shot("alive_m%d_blast" % m)
		"bot":
			await bot(mission_arg, 70)
		"levels":
			# pan across every mission and photograph each screen of the layout
			for m in 3:
				Run.new_run()
				var b: Battle = main.start_battle(m)
				await until(func(): return b.state == "player" and not b.busy)
				var x := 0.0
				var i := 0
				while x < b.world_w - Battle.W + Battle.W * 0.75:
					b.cam_x = minf(x, b.world_w - Battle.W); b.cam_tx = b.cam_x
					await frames_wait(6)
					await shot("level_m%d_%02d" % [m, i])
					x += Battle.W * 0.75
					i += 1
				# walk a soldier along the whole mission and list every spot where walking stops
				var u: Unit = b.squad()[0]
				var stops: Array = []
				var guard := 0
				while u.x < b.world_w - 80 and guard < 400:
					guard += 1
					b.cam_x = clampf(u.x - 200, 0, b.world_w - Battle.W); b.cam_tx = b.cam_x
					var sim := b.sim_walk(u, u.x + 300, 300)
					if sim.used >= 1:
						u.x = sim.x; u.y = sim.y
						continue
					var L = null
					for l in b.T.ladders:
						if absf(l.x - u.x) < 30 and absf(l.bot - u.y) < 16:
							L = l
					var y = null
					var nx := u.x
					while y == null or y >= Battle.WATER_Y - 4:
						nx += 4
						y = b.T.stand_y(nx, maxf(0, u.y - 130))
						if nx > u.x + 400:
							break
					stops.append("%d%s%s" % [u.x, " ladder" if L != null else "", " water" if nx - u.x > 40 else ""])
					u.x = nx; u.y = y if y != null else u.y
				print("[walk] mission ", m, " stops ", stops)
				print("[levels] mission ", m, " width ", b.world_w, " structs ", b.T.structs.map(func(s): return s.t), " ladders ", b.T.ladders.size(), " mines ", b.units.filter(func(u): return u.kind == "mine").size())
		"hazards":
			await hazards()
		"campaign":
			Run.new_run()
			for m in 3:
				Run.mission = m
				var ok := await bot(m, 60, false)
				print("[campaign] mission ", m, " won=", ok, " scrip=", Run.scrip, " alive=", Run.alive_count())
				if not ok:
					break
				Run.scrip += 0
		_:
			print("unknown scenario")
	print("[test] done")
	get_tree().quit()

func cam_on(b: Battle, x: float) -> void:
	b.cam_x = clampf(x - Battle.W / 2.0, 0, b.world_w - Battle.W); b.cam_tx = b.cam_x
	b.activate_enemies()

func find_struct(b: Battle, t: String) -> Dictionary:
	for s in b.T.structs:
		if s.t == t:
			return s
	return {}

func check(ok: bool, what: String) -> void:
	print("[hazard] ", "PASS " if ok else "FAIL ", what)

func hazards() -> void:
	## Set off each new set piece directly and check the physics does what the layout promises.
	# bridge: blow a post, the deck and the Jackal on it go into the river
	Run.new_run()
	var b: Battle = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	b.speed = 2.0
	var br := find_struct(b, "bridge")
	cam_on(b, (br.x0 + br.x1) / 2.0)
	var rider: Unit = null
	for u in b.units:
		if u.team == "enemy" and u.x > br.x0 and u.x < br.x1:
			rider = u
	await frames_wait(10)
	await shot("hz_bridge_before")
	b.explode(br.posts[0], br.y + 40, 22, 0, b.squad()[0])
	await frames_wait(20)
	await shot("hz_bridge_falling")
	await until(func(): return b.settled(), 1200)
	await frames_wait(30)
	await shot("hz_bridge_after")
	check(br.down, "bridge collapses when a post is blown")
	check(rider != null and (rider.sunk or rider.dead), "the Jackal on the bridge goes into the river")
	# fort: blow the base of the far wall and the whole fort drops onto its ground floor
	var ft := find_struct(b, "fort")
	cam_on(b, ft.x + ft.w / 2.0)
	await frames_wait(10)
	await shot("hz_fort_before")
	var g: float = b.T.ground_at(ft.x + ft.w / 2.0)
	var upper := b.units.filter(func(u): return u.team == "enemy" and not u.dead and absf(u.x - ft.x - ft.w / 2.0) < ft.w / 2.0 and u.y < g - 30)
	b.explode(ft.x + ft.w - 4, g - 16, 24, 0, b.squad()[0])
	await frames_wait(30)
	await shot("hz_fort_falling")
	await until(func(): return b.settled(), 1500)
	await frames_wait(20)
	await shot("hz_fort_after")
	var roof_y := -1.0
	for yy in range(int(ft.top) - 20, int(g) + 8, 2):
		if b.T.mat(ft.x + ft.w / 2.0, yy) == 2:
			roof_y = yy
			break
	check(roof_y < 0 or roof_y > ft.top + 24, "fort roof came down (roof was at %d, now %d, ground %d)" % [ft.top, roof_y, g])
	check(upper.any(func(u): return u.dead or u.hp < u.max_hp), "Jackals upstairs were hurt in the collapse (%d upstairs)" % upper.size())
	# mines: knock a Jackal onto one and walk a soldier onto another
	Run.new_run()
	b = main.start_battle(1)
	await until(func(): return b.state == "player" and not b.busy)
	b.speed = 2.0
	var mines := b.units.filter(func(u): return u.kind == "mine")
	check(mines.size() >= 5, "mission 2 has a minefield (%d mines)" % mines.size())
	var m0: Unit = mines[0]
	cam_on(b, m0.x)
	await frames_wait(10)
	await shot("hz_mine_before")
	var s0: Unit = b.squad()[0]
	s0.x = m0.x - 30; s0.y = b.T.stand_y(s0.x, m0.y - 40)
	var hp0 := s0.hp
	var sim := b.sim_walk(s0, m0.x + 10, 80)
	b.walk_along(s0, sim.pts)
	await frames_wait(6)
	await shot("hz_mine_click")
	await until(func(): return m0.gone, 400)
	await until(func(): return b.settled(), 800)
	check(m0.gone and s0.hp < hp0, "a soldier stepping on a mine sets it off")
	var m1: Unit = mines[1]
	var e := b.mk_enemy("grunt", m1.x - 4, m1.y - 50)
	b.units.append(e)
	e.vx = 0.3; e.vy = -2.0; e.air = true
	await until(func(): return m1.gone or (not e.air and e.vx == 0), 400)
	await until(func(): return b.settled(), 800)
	check(m1.gone, "a Jackal knocked onto a mine sets it off (landed %d, mine %d)" % [e.x, m1.x])
	var walker := b.mk_enemy("grunt", mines[2].x - 30, b.T.stand_y(mines[2].x - 30, mines[2].y - 40))
	b.units.append(walker)
	var ws := b.sim_walk(walker, mines[2].x + 30, 80)
	await b.walk_along(walker, ws.pts)
	await frames_wait(30)
	check(not mines[2].primed, "a Jackal walking over its own mine leaves it alone")
	# crane: shoot the cable, the container drops on the Boar
	Run.new_run()
	b = main.start_battle(2)
	await until(func(): return b.state == "player" and not b.busy)
	b.speed = 2.0
	var cranes := b.T.structs.filter(func(s): return s.t == "crane")
	var cr: Dictionary = cranes[-1]
	cam_on(b, cr.hook)
	await frames_wait(20)
	var boss: Unit = null
	for u in b.units:
		if u.type == "boss":
			boss = u
	await shot("hz_crane_before")
	var top: float = b.T.ground_at(cr.x + 6) - cr.h
	b.T.carve(cr.hook, top + 8 + cr.rope / 2.0, 5, b.squad()[0])
	await frames_wait(40)
	await shot("hz_crane_falling")
	await until(func(): return b.settled(), 1200)
	await frames_wait(20)
	await shot("hz_crane_after")
	check(boss != null and (boss.cracked or boss.hp < boss.max_hp), "the crane container hits the Boar (hp %d/%d cracked %s)" % [boss.hp, boss.max_hp, boss.cracked])

func force_card(u: Unit, key: String) -> int:
	for i in u.hand.size():
		if u.hand[i].key == key:
			return i
	u.hand.append(Run.new_card(key))
	u.energy = maxi(u.energy, 3)
	return u.hand.size() - 1

func nearest_enemy(b: Battle, u: Unit) -> Unit:
	var best: Unit = null
	for e in b.units:
		if e.team == "enemy" and not e.dead and e.active:
			if best == null or absf(e.x - u.x) < absf(best.x - u.x):
				best = e
	return best

func bot(mission: int, max_rounds: int, fresh := true) -> bool:
	## A simple autoplayer: shoot the nearest visible enemy, lob at clusters, heal, push right.
	if fresh:
		Run.new_run()
	var b: Battle = main.start_battle(mission)
	b.autopick = 0
	b.debug = true
	b.speed = 8.0
	var res := {"done": false, "won": false, "line": ""}
	b.mission_over.connect(func(w):
		res.done = true; res.won = w
		res.line = "rounds %d score %d kills %d cam %d/%d alive %d" % [b.round_n, b.score, b.stats.kills, int(b.cam_x), b.world_w, b.squad_alive().size()], CONNECT_ONE_SHOT)
	var last_shot := 0
	while not res.done and b.round_n < max_rounds:
		await until(func(): return res.done or (b.state == "player" and not b.busy), 20000)
		if res.done:
			break
		for u in b.squad_alive():
			if res.done or b.state != "player":
				break
			b.select_unit(u)
			var guard := 0
			while guard < 8 and not res.done and b.state == "player":
				guard += 1
				await until(func(): return res.done or not b.busy, 20000)
				if res.done or u.dead:
					break
				var played := false
				for i in u.hand.size():
					var c := Data.card(u.hand[i])
					if u.energy < b.card_cost(u, u.hand[i]):
						continue
					var e := nearest_enemy(b, u)
					if c.type == "SELF" and not c.get("overwatch", false):
						b.select_card(i)
						played = true
						break
					if c.type == "ALLY":
						var hurt := b.squad_alive().filter(func(s): return s.hp < s.max_hp - 6 and b.ally_valid(u, s, c))
						if hurt.size():
							b.select_card(i)
							b.play_on_target(hurt[0])
							played = true
							break
						continue
					if e == null:
						continue
					if c.type == "AIM":
						var aa := b.aim_angle(u, c, Vector2(e.x, e.y - e.h * 0.6))
						var tr := b.trace_bullet(aa.mx, aa.my, aa.a, c.range, c.get("bounce", 0), u, c.get("pierce", false))
						if tr.hits.any(func(h): return h.u.team == "enemy" or h.u.is_prop()):
							b.select_card(i)
							b.commit_aim(Vector2(e.x, e.y - e.h * 0.6))
							played = true
							break
					elif c.type == "ARC" and absf(e.x - u.x) < 260 and absf(e.x - u.x) > 70 and not c.get("smoke", false) and not b.squad_alive().any(func(s): return absf(s.x - e.x) < 70):
						b.select_card(i)
						var sol = b.solve_arc(u.x + (6 if e.x > u.x else -6), u.y - u.h + 10, e.x, e.y - 4, c.get("wind", 1.0), 13)
						if sol != null:
							var hx: float = u.x + (6 if e.x > u.x else -6)
							var hy: float = u.y - u.h + 10
							var pw := Vector2(sol.vx, sol.vy).length()
							var d := pw / 13.0 * 220
							b.commit_aim(Vector2(hx, hy) + Vector2(sol.vx, sol.vy).normalized() * d)
						else:
							b.cancel_card()
							continue
						played = true
						break
					elif c.type == "LINE" and not c.get("grapple", false) and not c.get("jump", false) and not c.get("rush", false) and absf(e.x - u.x) > 80:
						b.select_card(i)
						b.commit_aim(Vector2(e.x, e.y - 12))
						played = true
						break
					elif c.type == "MELEE" and b.melee_valid(u, e, c):
						b.select_card(i)
						b.play_on_target(e)
						played = true
						break
				if not played:
					break
				await until(func(): return res.done or not b.busy, 20000)
			if res.done or b.state != "player":
				break
			await until(func(): return res.done or not b.busy, 20000)
			if u.move_left > 20 and not u.dead:
				var e2 := nearest_enemy(b, u)
				# keep spacing: each soldier stops 46px behind the one ahead
				var order := b.squad_alive()
				order.sort_custom(func(a, c): return a.x > c.x)
				var lead_x: float = u.x + u.move_left if order[0] == u else order[0].x
				var tx: float = minf(u.x + u.move_left, lead_x - 46.0 * order.find(u))
				if e2 != null and e2.x - u.x < 140:
					tx = minf(tx, u.x + 10)
				if tx < u.x + 4:
					tx = u.x - 30 if order.find(u) > 0 else u.x
				b.do_move(u, tx)
				await until(func(): return res.done or not b.busy, 20000)
				# take a ladder when one is right ahead and the way on foot is blocked
				for L in b.T.ladders:
					if not u.dead and u.move_left > 20 and L.x > u.x - 10 and L.x - u.x < 40 and absf(L.bot - u.y) < 16 and L.offx > L.x - 30:
						b.do_climb(u, L)
						await until(func(): return res.done or not b.busy, 20000)
						break
		if res.done:
			break
		if b.round_n - last_shot >= 3 or b.round_n == 1:
			last_shot = b.round_n
			await shot("bot_m%d_r%02d" % [mission, b.round_n])
		b.end_turn()
		await until(func(): return res.done or (b.state == "player" and not b.busy) or b.state == "over", 30000)
	if not res.done:
		res.line = "rounds %d score %d kills %d cam %d/%d alive %d" % [b.round_n, b.score, b.stats.kills, int(b.cam_x), b.world_w, b.squad_alive().size()]
	print("[bot] mission ", mission, " done ", res.done, " won ", res.won, " ", res.get("line", ""), " lv ", Run.soldiers.map(func(s): return s.lvl), " scrip ", Run.scrip)
	if res.done:
		await frames_wait(5)
	return res.won

func press_first() -> void:
	for c in main.screen.get_children():
		if c.has_signal("pressed"):
			c.pressed.emit()
			return

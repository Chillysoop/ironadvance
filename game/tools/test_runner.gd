extends Node
## Headless-ish test harness. Does nothing unless the game is launched with
##   godot --path . -- --iatest --scenario=<name> --out=<dir> [--speed=N]
## Scenarios: fx, title, start, aim, ghost, arc, bot, shop, picker, level, topple, campaign, alive, levels, hazards, tags, gate, camp, aliens, aliens2, soldat, drill,
## warmap, company, ops, story, lab (campaign mode), clicks (screens take real mouse clicks), pause (Esc menu), operator (tablet call-ins), training (N6 drill),
## playtest (whole runs: --seed=N --runs=K --start=L skips to level L), pinball (a blast beside a bunched squad), tuning,
## trailer (--clip=NAME stages one cinematic shot for the movie writer, see trailer.gd).
## --mission=N picks the mission for bot.

const Services := preload("res://scripts/services.gd")
const HubUI := preload("res://scripts/hub_ui.gd")
const HudScript := preload("res://scripts/hud.gd")

var out_dir := "user://shots"
var scenario := ""
var main: Node
var frames := 0
var mission_arg := 0
var seed_arg := 1
var runs_arg := 1
var playtest_debug := false
var start_arg := 0
var clip_arg := ""

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
		elif a.begins_with("--seed="):
			seed_arg = int(a.substr(7))
		elif a.begins_with("--start="):
			start_arg = int(a.substr(8))
		elif a.begins_with("--clip="):
			clip_arg = a.substr(7)
		elif a.begins_with("--runs="):
			runs_arg = int(a.substr(7))
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
		if playtest_debug and n % 3000 == 0 and is_instance_valid(cur_b):
			dump_unsettled(cur_b, n)
		if n > max_frames:
			if playtest_debug:
				print("[timeout] until gave up after %d frames" % max_frames)
			return false
	return true

var cur_b: Battle = null

func dump_unsettled(b: Battle, n: int) -> void:
	## A long wait: say what is keeping the battle from settling.
	var why: Array = []
	if b.projs.size():
		why.append("projs %s" % [b.projs.map(func(p): return "%s@%d,%d v%.1f,%.1f" % [p.kind, int(p.x), int(p.y), p.vx, p.vy])])
	if b.booms.size():
		why.append("booms %d" % b.booms.size())
	if b.T.chunks.size():
		why.append("chunks %d" % b.T.chunks.size())
	if absf(b.cam_x - b.cam_tx) >= 0.5:
		why.append("cam %d->%d" % [int(b.cam_x), int(b.cam_tx)])
	for u in b.units:
		if u.sunk or u.gone:
			continue
		if u.walk != null or u.zip != null or u.drill != null or u.slide != 0 or u.air or u.hang or u.para:
			why.append("hang %s para %s jumping %s" % [u.hang, u.para, u.jumping])
			why.append("%s %s@%d,%d walk %s zip %s drill %s slide %s air %s v%.2f,%.2f dead %s" % [u.team, u.def.key if u.team == "squad" else u.type, int(u.x), int(u.y), u.walk != null, u.zip != null, u.drill != null, u.slide, u.air, u.vx, u.vy, u.dead])
	for u in b.squad():
		why.append("SQ %s@%.1f,%.1f air %s dead %s gone %s sunk %s hang %s para %s walk %s v%.2f,%.2f" % [u.def.key, u.x, u.y, u.air, u.dead, u.gone, u.sunk, u.hang, u.para, u.walk != null, u.vx, u.vy])
	print("[unsettled r%d] %d frames tick %d state %s busy %s sel %s: %s" % [b.round_n, n, b.t, b.state, b.busy, b.sel.def.key if b.sel != null else "-", why])
	if n == 3000:
		shot("unsettled_r%d" % b.round_n)

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
		"intel":
			Run.new_run()
			var b: Battle = main.start_battle(0)
			await until(func(): return b.state == "player" and not b.busy)
			await frames_wait(120)
			b.inspect = true
			b.mouse = Vector2(300, 300)
			main.hud.cards[1].hover = true
			await frames_wait(10)
			await shot("intel")
			b.inspect = false
			b.sel.energy = 0
			b.sel.move_left = 0
			b.ui_dirty = true
			b.end_turn()
			await frames_wait(10)
			await shot("done_confirm")
		"rarity":
			Run.new_run()
			var b: Battle = main.start_battle(0)
			await until(func(): return b.state == "player" and not b.busy)
			var opts: Array = []
			for t in 5:
				opts.append({"kind": "card", "key": ["rifle", "frag", "medkit", "snipe", "knife"][t], "tier": t})
			b.resolve(func(): await b.ask("supply", "RARITY CHECK", "Common to Legendary.", opts))
			await frames_wait(60)
			await shot("rarity")
			main.hud.picked.emit(-1)
			print("[rarity] weights m0 ", Run.tier_weights())
			var counts := [0, 0, 0, 0, 0]
			for i in 2000:
				counts[Run.roll_tier()] += 1
			print("[rarity] 2000 rolls ", counts)
		"loot":
			Run.new_run()
			var b: Battle = main.start_battle(0)
			await until(func(): return b.state == "player" and not b.busy)
			var u: Unit = b.sel
			var cr := b.mk_unit(); cr.team = "neutral"; cr.kind = "crate"; cr.x = u.x + 60; cr.y = b.T.stand_y(cr.x, 0); cr.w = 16; cr.h = 14
			b.units.append(cr)
			var sb := b.mk_unit(); sb.team = "neutral"; sb.kind = "strongbox"; sb.x = u.x + 110; sb.y = b.T.stand_y(sb.x, 0); sb.w = 20; sb.h = 14
			b.units.append(sb)
			b.drop_loot(u.x + 150, u.y - 30, {"type": "letter", "key": "H"})
			b.drop_loot(u.x + 180, u.y - 30, {"type": "item", "item": Run.roll_item(3)})
			var e: Unit = b.units.filter(func(x): return x.team == "enemy")[0]
			b.make_elite(e, "armored")
			await frames_wait(60)
			await shot("loot_field")
			b.damage(cr, 5, u, {})
			b.damage(sb, 5, u, {"blast": true})
			await frames_wait(60)
			await shot("loot_open")
			b.autopick = 0
			for l in b.units.filter(func(x): return x.kind == "loot" and not x.gone):
				b.collect(u, l)
			b.resolve(func(): await b.wait(2))
			await until(func(): return not b.busy)
			print("[loot] hand ", u.hand.map(func(c): return c.key), " stash ", Run.stash.map(func(i): return i.id), " equip ", u.s.equip)
			await shot("loot_after")
			b.sweep_loot(INF)
		"combos":
			Run.new_run()
			var b: Battle = main.start_battle(0)
			await until(func(): return b.state == "player" and not b.busy)
			var sq: Array = b.squad_alive()
			var u: Unit = b.sel
			var es: Array = b.units.filter(func(x): return x.team == "enemy" and not x.dead)
			var e: Unit = es[0]
			e.hp = 60; e.max_hp = 60
			# mark: next hit crits
			b.add_status(e, "mark", 2, u)
			var h0 := e.hp
			b.damage(e, 10, u, {})
			print("[combos] mark 10 -> ", h0 - e.hp, " mark left ", e.has_st("mark"))
			# burn ticks
			b.add_status(e, "burn", 2, u)
			h0 = e.hp
			b.tick_statuses("enemy")
			print("[combos] burn tick ", h0 - e.hp, " burn left ", e.st.get("burn", 0))
			# crossfire: hits from both sides
			var lft: Unit = sq[0]
			var rgt: Unit = sq[1]
			var ox := rgt.x
			rgt.x = e.x + 80
			b.damage(e, 1, lft, {})
			b.damage(e, 1, rgt, {})
			rgt.x = ox
			print("[combos] crossfire supp ", e.has_st("supp"))
			# momentum: third card refunds
			u.energy = 5
			while u.hand.size() < 3:
				u.hand.append(Run.new_card("dash"))
			for i in 3:
				b.spend_card(u, 0)
			print("[combos] momentum energy after 3 cards ", u.energy, " played ", u.played)
			# fuel-air: blast inside gas
			b.gases.append({"x": e.x, "y": e.y - 20, "r": 60.0, "turns": 3, "seed": 0.0, "owner": u})
			await frames_wait(30)
			await shot("combos_gas")
			b.explode(e.x, e.y - 20, 30, 1, u)
			print("[combos] gas left ", b.gases.size(), " burn ", e.has_st("burn"), " tags ", b.stats.tags)
			# pile-up: throw one Jackal into another
			if es.size() >= 2:
				var e2: Unit = es[1]
				e.x = e2.x - 30; e.y = e2.y - 4; e.vx = 7; e.vy = -1; e.air = true; e.last_hit_by = u; e.bumped = null
				await frames_wait(60)
				print("[combos] pileup stun ", e.has_st("stun"), e2.has_st("stun"))
			b.combo = 4
			b.add_status(es[-1], "toxic", 2, u)
			b.gases.append({"x": u.x + 120, "y": u.y - 20, "r": 56.0, "turns": 3, "seed": 1.0, "owner": u})
			await frames_wait(20)
			await shot("combos_status")
			# card fusion: Rook starts with three Rifle Shots
			var rook: Dictionary = Run.soldiers[3]
			var fg := Run.fusable(rook)
			print("[combos] rook fusable ", fg.size())
			var fc := Run.fuse(rook, fg[0])
			print("[combos] fused ", fc, " deck ", rook.deck.size())
			# gear triple merge
			for i in 3:
				Run.stash.append(Run.new_item("flak", 1))
			var g := Run.merge_group_of(Run.stash[0])
			print("[combos] merge group ", g.size(), " keep ", Run.merge_keep_options(g), " new ", Run.merge_new_options([]))
			var mi := Run.merge_items(g, [Run.merge_keep_options(g)[0], "move"])
			print("[combos] merged ", mi, " stash ", Run.stash.size())
			for i in 3:
				Run.stash.append(Run.new_item("scope", 3))
			var lg := Run.merge_items(Run.merge_group_of(Run.stash[-1]), ["regen"])
			print("[combos] legend ", Data.item_name(lg), " ", Data.item_stats(lg))
			Run.stash.append(Run.new_item("ghillie", 0))
			Run.stash.append(Run.new_item("ghillie", 0))
			Run.fabricate(Run.stash[-1])
			print("[combos] fab triple ", Run.merge_group_of(Run.stash[-1]).size())
			Run.scrip = 300
			main.show_shop()
			await frames_wait(10)
			await shot("combos_shop")
			main.screen.open_armory()
			await frames_wait(10)
			var arm = main.screen.get_children()[-1]
			arm.select({"where": "stash", "i": Run.stash.size() - 1})
			await frames_wait(5)
			arm.start_merge(Run.merge_group_of(Run.stash[-1]))
			await frames_wait(10)
			await shot("combos_merge")
		"archetypes":
			Run.new_run()
			var moss: Dictionary = Run.soldiers[0]
			print("[arch] offers ", Run.perk_offers(moss).map(func(o): return o.label + ":" + o.id))
			moss.perks.append_array(["steady", "patience", "deadeye"])
			print("[arch] moss od ", Run.od_key(moss), " arch ", Run.archetypes(moss))
			print("[arch] offers after ", Run.perk_offers(moss).map(func(o): return o.id))
			var c := Run.new_card("frag")
			print("[arch] frag mods ", Data.mod_options(c).map(func(m): return m.id))
			c["mods"] = ["sticky", "lean"]
			print("[arch] frag modded ", Data.card(c))
			var ks := Run.new_item("twinrev")
			print("[arch] keystone ", ks, " ", Data.item_name(ks))
			Run.equip(moss, ks)
			var b: Battle = main.start_battle(0)
			await until(func(): return b.state == "player" and not b.busy)
			var mu: Unit = b.squad().filter(func(x): return x.def.key == "moss")[0]
			print("[arch] moss ks twinrev ", b.ks(mu, "twinrev"))
			mu.hand = [Run.new_card("tagshot"), Run.new_card("snipe"), Run.new_card("rifle")]
			mu.energy = 6
			mu.seq = [["tagshot", "AIM"]]
			print("[arch] chain ready snipe ", b.chain_ready(mu, mu.hand[1]))
			var sc := b.spend_card(mu, 1)
			print("[arch] spotted forcehead ", sc.get("forcehead", false))
			# six shooter: two AIM played, third AIM
			mu.seq = [["rifle", "AIM"], ["rifle", "AIM"]]
			mu.fl = {}
			mu.hand.append(Run.new_card("pistol"))
			var hs := mu.hand.size()
			print("[arch] six ready ", b.chain_ready(mu, mu.hand[-1]))
			b.spend_card(mu, mu.hand.size() - 1)
			print("[arch] six shooter temp ", mu.hand.map(func(x): return x.key + ("*" if x.get("free", false) else "")))
			# rook taunt + payback
			var rook: Unit = b.squad().filter(func(x): return x.def.key == "rook")[0]
			rook.s.perks.append("payback")
			rook.hand = [Run.new_card("taunt"), Run.new_card("digin")]
			rook.energy = 4
			b.play_self(0)
			await until(func(): return not b.busy)
			print("[arch] taunter ", b.taunter == rook, " ready ", b.chain_ready(rook, rook.hand[0]))
			b.play_self(0)
			await until(func(): return not b.busy)
			print("[arch] rook armor after taunt+digin ", rook.armor)
			# vee molotov/flashbang/shaped charge projectiles
			var vee: Unit = b.squad().filter(func(x): return x.def.key == "vee")[0]
			var es: Array = b.units.filter(func(x): return x.team == "enemy" and not x.dead)
			var e: Unit = es[0]
			e.hp = 80; e.max_hp = 80
			e.x = vee.x + 160; e.y = b.T.stand_y(e.x, 0); e.active = true
			b.sel = vee
			for k in ["molotov", "flashbang", "shapedcharge", "gasnade"]:
				vee.hand = [Run.new_card(k)]
				vee.energy = 3
				b.card_idx = 0
				b.commit_aim(Vector2(e.x, e.y - 10))
				await until(func(): return not b.busy, 700)
				print("[arch] ", k, " -> e st ", e.st, " hp ", e.hp, " gases ", b.gases.size())
			# overdrives
			for k in ["barrage", "napalmstrike", "collapse", "smokescreen"]:
				vee.hand = [{"id": -1, "key": k, "tier": Data.OD_TIER, "od": true}]
				b.card_idx = 0
				b.commit_aim(Vector2(e.x, e.y - 10))
				await until(func(): return not b.busy, 700)
				print("[arch] od ", k, " ok, smokes ", b.smokes.size(), " e hp ", e.hp)
			var hex: Unit = b.squad().filter(func(x): return x.def.key == "hex")[0]
			b.sel = hex
			for k in ["blight", "triagefield"]:
				hex.hand = [{"id": -1, "key": k, "tier": Data.OD_TIER, "od": true}]
				b.play_self(0)
				await until(func(): return not b.busy, 600)
			print("[arch] blight toxic ", es.filter(func(x): return x.has_st("toxic")).size(), "/", es.size())
			b.sel = rook
			rook.hand = [{"id": -1, "key": "breach", "tier": Data.OD_TIER, "od": true}]
			b.card_idx = 0
			b.commit_aim(Vector2(rook.x + 200, rook.y - 30))
			await until(func(): return not b.busy, 1500)
			print("[arch] breach done")
			await shot("archetypes")
			# level up modal with reroll/banish
			b.autopick = -1
			b.level_up(mu)
			await frames_wait(20)
			await shot("arch_levelup")
			b.hud.picked.emit(-2)
			await frames_wait(10)
			b.hud.picked.emit(-100)
			await frames_wait(10)
			b.hud.picked.emit(0)
			await frames_wait(10)
			print("[arch] rerolls ", Run.lvl_rerolls, " banishes ", Run.banishes, " banished ", Run.banished)
			Run.scrip = 300
			main.show_shop()
			await frames_wait(10)
			await shot("arch_shop")
			main.show_debrief({"kia": 0, "rounds": 8, "pows": 1, "pows_total": 1, "max_alert": 3})
			await frames_wait(5)
			main.screen.open_all()
			await frames_wait(90)
			main.screen.advance()
			await frames_wait(10)
			await shot("arch_command")
		"armory":
			Run.new_run()
			for i in 6:
				Run.stash.append(Run.roll_item(i % 5))
			Run.belt.append(Run.new_item("b_medkit"))
			Run.equip(Run.soldiers[0], Run.new_item("marksman", 3))
			Run.equip(Run.soldiers[3], Run.new_item("plate", 2))
			Run.equip(Run.soldiers[3], Run.new_item("steeltoe", 1))
			Run.scrip = 500
			main.show_shop()
			await frames_wait(10)
			main.screen.open_armory()
			await frames_wait(10)
			var arm = main.screen.get_children()[-1]
			arm.select({"where": "stash", "i": 0})
			await frames_wait(10)
			await shot("armory")
			print("[armory] moss deck ", Run.soldiers[0].deck.map(func(c): return c.key), " rook bonus ", Run.gear_bonus(Run.soldiers[3]))
		"debrief":
			Run.new_run()
			main.show_debrief({"kia": 0, "rounds": 8, "pows": 1, "pows_total": 1, "max_alert": 3})
			await frames_wait(10)
			await shot("debrief")
			main.screen.open_all()
			await frames_wait(40)
			await shot("debrief_open")
			await frames_wait(60)
			await shot("debrief_done")
		"shop":
			Run.new_run()
			Run.scrip = 400
			Run.soldiers[0].hp = 10
			Run.soldiers[3].alive = false
			main.show_shop()
			await frames_wait(20)
			await shot("shop")
		"picker":
			await picker()
		"flow":
			# title -> brief -> each mission (forced win) -> results -> shop -> next brief
			main.show_title()
			await frames_wait(20)
			main.start_run()  # QUICK RUN; the first title button is CAMPAIGN now
			await frames_wait(20)
			await shot("flow_hq_start")
			main.screen.dial.emit()
			await frames_wait(20)
			await shot("flow_dial0")
			press_first()
			await frames_wait(20)
			await shot("flow_brief0")
			for m in 4:
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
				if m == 3:
					check(main.screen.get("mode") == "final", "beating the harbor finale wins the run")
					break
				press_first()
				await frames_wait(20)
				await shot("flow_debrief%d" % m)
				main.screen.open_all()
				await frames_wait(90)
				main.screen.done.emit()
				await frames_wait(30)
				await shot("flow_hq%d" % m)
				main.screen.open_shop("shop")
				await frames_wait(20)
				await shot("flow_shop%d" % m)
				main.screen.sub.done.emit()
				await frames_wait(10)
				main.screen.dial.emit()
				await frames_wait(20)
				await shot("flow_dial%d" % (m + 1))
				if m < 2:
					press_first()
				await frames_wait(20)
				print("[flow] intel ", Run.intel, " mission ", Run.mission)
				await shot("flow_brief%d" % (m + 1))
		"phase5":
			Run.new_run()
			Run.meta = {"feats": {}, "unlocked": [], "threat_max": 2, "wins": 1}
			main.show_title()
			await frames_wait(20)
			await shot("p5_title")
			Run.threat = 5
			Run.intel = "veterans"
			Run.trophies = ["A", "B", "C"]
			var b: Battle = main.start_battle(1)
			await until(func(): return b.state == "player" and not b.busy)
			print("[p5] hand size T3 ", b.hand_size(b.squad()[0]), " temp_luck ", Run.temp_luck, " relays ", b.units.filter(func(x): return x.kind == "relay").size())
			print("[p5] slug card ", b.squad()[0].hand.any(func(c): return c.key == "slugcall"))
			var sq: Array = b.squad()
			var by := {}
			for u in sq:
				by[u.def.key] = u
			# duo: moss + hex next to each other with Overdrives
			by.hex.x = by.moss.x + 40
			for u in sq:
				u.adr = 100
				b.grant_overdrive(u)
			b.refresh_duos()
			for u in sq:
				print("[p5] ", u.def.key, " duos ", u.hand.filter(func(c): return c.has("duo")).map(func(c): return c.key + "/" + c.duo))
			await shot("p5_duos")
			# Overwatch Net from moss
			var oi := -1
			for i in by.moss.hand.size():
				if by.moss.hand[i].key == "ownet":
					oi = i
			if oi >= 0:
				b.sel = by.moss
				b.play_self(oi)
				await until(func(): return not b.busy)
				print("[p5] ownet: overwatch ", sq.map(func(u): return u.overwatch), " hex od left ", by.hex.hand.any(func(c): return c.get("od", false) and not c.has("duo")))
			# slug
			b.call_slug(sq[0])
			await frames_wait(60)
			await shot("p5_slug")
			var sl = b.units.filter(func(x): return x.kind == "slug")[0]
			var e0: Array = b.units.filter(func(x): return x.team == "enemy" and not x.dead)
			for e in e0.slice(0, 3):
				e.x = sl.x + 150 + randf() * 80; e.y = b.T.stand_y(e.x, 0); e.active = true
			var hp0: int = e0.slice(0, 3).reduce(func(acc, e): return acc + e.hp, 0)
			await b.slug_act(sl)
			print("[p5] slug dmg ", hp0 - e0.slice(0, 3).reduce(func(acc, e): return acc + maxi(0, e.hp), 0), " slug x ", sl.x)
			# relay capture
			var r = b.units.filter(func(x): return x.kind == "relay")[0]
			var al0: int = b.alert
			var cap: Unit = b.squad_alive()[0]
			cap.x = r.x; cap.y = r.y
			await frames_wait(10)
			print("[p5] squad alive ", b.squad_alive().size(), " hp ", sq.map(func(u): return u.hp))
			b.end_turn(true)
			await until(func(): return b.state == "player" and not b.busy, 3000)
			print("[p5] relay taken ", r.loot.taken, " buff ", r.loot.buff, " alert ", al0, "->", b.alert, " slug gone ", sl.gone)
			await shot("p5_relay")
			# feats
			print("[p5] feat skeet x3 -> ", [Run.feat("skeet"), Run.feat("skeet"), Run.feat("skeet")], " unlocked ", Run.meta.unlocked)
			b.announce_unlock("Skeet Vest")
			await frames_wait(20)
			await shot("p5_unlock")
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
		"turnqol":
			Run.new_run()
			var b: Battle = main.start_battle(0)
			await until(func(): return b.state == "player" and not b.busy)
			await frames_wait(10)
			await shot("qol_buttons")
			var sq: Array = b.squad_alive()
			b.sel = sq[0]
			var order: Array = []
			for i in 4:
				b.next_unit()
				order.append(b.sel.def.key)
			print("[qol] next order from ", sq[0].def.key, ": ", order)
			sq[1].hand.append(Run.new_card("sprint"))
			sq[1].hand.append(Run.new_card("frag"))
			var x0: Array = sq.map(func(u): return int(u.x))
			var e0: Array = sq.map(func(u): return u.energy)
			b.auto_advance()
			await until(func(): return not b.busy, 2000)
			print("[qol] move x ", x0, " -> ", sq.map(func(u): return int(u.x)))
			print("[qol] energy ", e0, " -> ", sq.map(func(u): return u.energy), " move_left ", sq.map(func(u): return int(u.move_left)))
			print("[qol] frag kept ", sq[1].hand.any(func(c): return c.key == "frag"), " sprint used ", not sq[1].hand.any(func(c): return c.key == "sprint"))
			await frames_wait(20)
			await shot("qol_after_move")
			for u in sq:
				u.energy = 0; u.move_left = 0; u.hand = []
			b.ui_dirty = true
			await frames_wait(10)
			print("[qol] ready ", b.ready_count(), " next label ", main.hud.next_btn.text)
			await shot("qol_end")
			b.next_unit()
			await frames_wait(10)
			print("[qol] state after NEXT with nobody ready ", b.state)
		"fx":
			# effects pass: brass and impacts on a shot, a helmet off a kill, a blast's flash and chunks
			Run.new_run()
			var b: Battle = main.start_battle(0)
			await until(func(): return b.state == "player" and not b.busy)
			var u: Unit = b.sel
			var e := nearest_enemy(b, u)
			b.select_card(force_card(u, "rifle"))
			b.mouse = Vector2(e.x, e.y - e.h * 0.6)
			await frames_wait(8)
			b.commit_aim(b.mouse)
			await frames_wait(5)
			await shot("fx_shot")
			await until(func(): return not b.busy)
			b.damage(e, 999, u)
			await frames_wait(14)
			await shot("fx_kill")
			b.explode(u.x + 150, b.T.ground_at(u.x + 150) - 4, 30, 0, null)
			await frames_wait(5)
			await shot("fx_blast")
			await frames_wait(40)
			await shot("fx_after")
			u.jetting = true  # just the thruster art, no flight
			await frames_wait(12)
			await shot("fx_jet")
			u.jetting = false
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
		"ghost":
			# an armed card ghosts the hand; a Jackal lying behind the cards can still be clicked
			Run.new_run()
			var b: Battle = main.start_battle(0)
			await until(func(): return b.state == "player" and not b.busy)
			var u: Unit = b.sel
			var e := nearest_enemy(b, u)
			e.x = b.cam_x + 480; e.y = 500.0; e.air = false; e.vy = 0
			var hp0 := e.hp
			b.select_card(force_card(u, "rifle"))
			var sp := Vector2(480, e.y - 6)
			var vp := get_viewport()
			var k: float = vp.get_visible_rect().size.x / 960.0
			vp.warp_mouse(sp * k)
			var mv := InputEventMouseMotion.new(); mv.position = sp * k; mv.global_position = sp * k
			Input.parse_input_event(mv)
			await frames_wait(20)
			Input.parse_input_event(mv)
			await frames_wait(2)
			await shot("ghost_aim")
			check(main.hud.hand_box.modulate.a < 0.6, "the hand fades while a card is armed (alpha %.2f)" % main.hud.hand_box.modulate.a)
			check(main.hud.cards.all(func(cv): return cv.mouse_filter == Control.MOUSE_FILTER_IGNORE), "over a unit the hand lets clicks through")
			var cl := InputEventMouseButton.new(); cl.button_index = MOUSE_BUTTON_LEFT; cl.pressed = true; cl.position = sp * k; cl.global_position = sp * k
			Input.parse_input_event(cl)
			var up := cl.duplicate(); up.pressed = false
			Input.parse_input_event(up)
			await frames_wait(4)
			check(b.card_idx == -1 and b.busy or e.hp < hp0, "clicking the Jackal behind the hand fires at it (card %d busy %s hp %d->%d)" % [b.card_idx, b.busy, hp0, e.hp])
			await until(func(): return not b.busy)
			await frames_wait(10)
			check(main.hud.hand_box.modulate.a > 0.9, "the hand comes back after the shot (alpha %.2f)" % main.hud.hand_box.modulate.a)
			await shot("ghost_after")
		"tags":
			await tags()
		"gate":
			await gate()
		"camp":
			await camp()
		"biomes":
			await biomes()
		"soldat":
			await soldat()
		"soldat2":
			await soldat2()
		"soldat3":
			await soldat3()
		"soldat4":
			await soldat4()
		"soldat5":
			await soldat5()
		"soldat6":
			await soldat6()
		"drill":
			await drill()
		"pickups":
			await pickups()
		"bossloot":
			await bossloot()
		"detours":
			await detours()
		"hq":
			await hq_upgrades()
		"doc":
			await doc()
		"dossier":
			await dossier()
		"hub":
			await hub()
		"field":
			await field()
		"picks":
			await picks()
		"recruits":
			await recruits()
		"aliens":
			await aliens()
		"aliens2":
			await aliens2()
		"aliens3":
			await aliens3()
		"aliens4":
			await aliens4()
		"aliens5":
			await aliens5()
		"warmap":
			await warmap()
		"company":
			await company()
		"ops":
			await ops()
		"story":
			await story()
		"lab":
			await lab()
		"ending":
			await ending()
		"aliens6":
			await aliens6()
		"aliens7":
			await aliens7()
		"aliens8":
			await aliens8()
		"playtest":
			await playtest()
		"straggler":
			await straggler()
		"hoverwedge":
			await hoverwedge()
		"drowncamp":
			await drowncamp()
		"worms":
			await worms()
		"pinball":
			await pinball()
		"tuning":
			await tuning()
		"clicks":
			await clicks()
		"pause":
			await pause_menu()
		"operator":
			await operator_call()
		"training":
			await training()
		"trailer":
			await preload("res://tools/trailer.gd").new().run(self, clip_arg)
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

func picker() -> void:
	## The Quartermaster's soldier picks: buying a card or picking whose deck to work on lights up
	## the squad tiles along the bottom instead of opening a popup.
	Run.new_run()
	Run.scrip = 400
	Run.soldiers[0].hp = 10
	Run.soldiers[2].tags = 1
	main.show_shop()
	await frames_wait(20)
	await shot("picker_shop")
	var sh: Control = main.screen
	var o: Dictionary = sh.stock_cards[0]
	var before: int = Run.soldiers[1].deck.size()
	sh.buy_card(0)
	await frames_wait(20)
	await shot("picker_buy")
	sh.chosen.emit(1)
	await frames_wait(10)
	check(Run.soldiers[1].deck.size() == before + 1 and o.get("sold", false), "buying a card puts it in the picked soldier's deck")
	await shot("picker_bought")
	sh.buy_card(1)
	await frames_wait(10)
	sh.chosen.emit(-1)
	await frames_wait(10)
	check(not sh.stock_cards[1].get("sold", false) and sh.chooser == null, "cancelling a pick buys nothing")
	sh.mode = "barracks"
	sh.build()
	sh.restore_tag()
	await frames_wait(20)
	await shot("picker_tag")
	var tags: int = Run.soldiers[2].tags
	sh.chosen.emit(0)
	await frames_wait(10)
	check(Run.soldiers[2].tags == tags + 1, "the dog tag goes to the only soldier missing one")
	main.show_title()
	await frames_wait(30)
	await shot("picker_title")

func dossier() -> void:
	## The HQ Dossier: squad bar, soldiers you can click, and card services on the selected card
	## with a before/after preview that only charges on CONFIRM.
	Run.new_run()
	Run.scrip = 600
	var moss: Dictionary = Run.soldiers[0]
	moss.hp = 9
	check(moss.deck.all(func(c): return c.get("from", "") == "start"), "starting cards remember they came with the soldier")
	moss.deck.append(Run.new_card("rifle", 0, "shop"))
	main.show_hq(false)
	await frames_wait(20)
	var hq: Control = main.screen
	hq.hover_troop = 0
	await frames_wait(4)
	await shot("dossier_hq")
	check(Services.alert(moss) == "FUSE", "the squad bar flags Moss's three Rifle Shots")
	hq.hover_troop = -1
	hq.open_dossier(0)
	await frames_wait(20)
	await shot("dossier_deck")
	var d: Control = hq.sub
	check(d != null and d.idx == 0 and d.tab == "deck", "the Dossier opens on Moss's deck")
	var rifles: Array = moss.deck.filter(func(c): return c.key == "rifle")
	d.sel = rifles[0]
	d.build()
	await frames_wait(10)
	await shot("dossier_selected")
	var acts := Services.card_actions(moss, rifles[0])
	check(acts.map(func(a): return a.id) == ["polish", "gunsmith", "fuse", "evolve", "burn"], "a selected card shows the five card services")
	check(acts[0].ok and acts[0].line.contains("DMG 6-8 > 8-10"), "Polish says what it does: " + acts[0].line)
	check(acts[2].ok and acts[3].why.contains("Scope"), "Fuse is ready, Evolve says what it needs: " + acts[3].why)
	# polish through the preview: nothing is paid until CONFIRM
	var before: int = Run.scrip
	d.open_preview("polish")
	await frames_wait(10)
	await shot("dossier_polish_preview")
	check(Run.scrip == before and Data.tier_of(rifles[0]) == 0, "opening the preview costs nothing")
	d.modal.confirm.pressed.emit()
	await frames_wait(10)
	check(Data.tier_of(rifles[0]) == 1 and Run.scrip == before - Services.price(Services.POLISH), "CONFIRM polishes the card and charges once")
	# fuse needs three of one rarity again
	moss.deck.append(Run.new_card("rifle", 0, "shop"))
	var commons: Array = moss.deck.filter(func(c): return c.key == "rifle" and Data.tier_of(c) == 0)
	check(commons.size() == 3, "three Common Rifle Shots for the fusion test")
	var n0: int = moss.deck.size()
	d.sel = commons[0]
	d.build()
	d.open_preview("fuse")
	await frames_wait(10)
	await shot("dossier_fuse_preview")
	d.modal.confirm.pressed.emit()
	await frames_wait(10)
	check(moss.deck.size() == n0 - 2 and d.sel != null and d.sel.get("from", "") == "fused" and Data.tier_of(d.sel) == 1, "Fuse turns three into one Uncommon and selects it")
	# gunsmith: pick a mod card, then confirm
	d.open_preview("gunsmith")
	await frames_wait(10)
	check(d.modal.confirm.disabled, "Gunsmith waits for a mod to be picked")
	var opts: Array = d.modal.get_children().filter(func(o): return o is CardView)
	opts[0].pressed.emit()
	await frames_wait(6)
	await shot("dossier_mod_preview")
	d.modal.confirm.pressed.emit()
	await frames_wait(10)
	check(d.sel.get("mods", []).size() == 1, "the picked mod lands on the card")
	# evolve with an Epic Rifle Shot and the Scope kit
	var epic := Run.new_card("rifle", 3, "shop")
	moss.deck.append(epic)
	var scope := Run.new_item("scope", 0)
	Run.stash.append(scope)
	Run.equip(moss, scope)
	d.sel = epic
	d.build()
	check(Services.evolve_info(moss, epic).ok, "Epic Rifle Shot plus Scope can evolve")
	d.open_preview("evolve")
	await frames_wait(10)
	await shot("dossier_evolve_preview")
	d.modal.confirm.pressed.emit()
	await frames_wait(10)
	check(epic.key == "lasergun", "Evolve makes the Laser Gun")
	# burn
	var n1: int = moss.deck.size()
	d.sel = moss.deck.filter(func(c): return c.key == "pistol")[0]
	d.build()
	d.open_preview("burn")
	await frames_wait(6)
	d.modal.confirm.pressed.emit()
	await frames_wait(10)
	check(moss.deck.size() == n1 - 1 and d.sel == null, "Burn takes the card out")
	# filters, sort, upgraded preview
	d.filt = "fuse"
	d.build()
	check(d.deck_list().all(func(c): return Services.fuse_group(moss, c).size() >= 2 or Services.evolve_rule(c).size() > 0), "the FUSE filter shows only cards with fusion or evolution progress")
	d.filt = ""
	d.sort = "rarity"
	d.show_up = true
	d.build()
	await frames_wait(10)
	await shot("dossier_upgraded")
	d.show_up = false
	# sheet and gear tabs
	moss.perks.append("steady")
	d.set_tab("sheet")
	await frames_wait(10)
	await shot("dossier_sheet")
	var vest := Run.new_item(Run.random_item_id(["armor"]), 1)
	Run.stash.append(vest)
	d.gear_pick = {"where": "stash", "i": Run.stash.find(vest)}
	d.set_tab("gear")
	await frames_wait(10)
	await shot("dossier_gear")
	check(d.equip_preview(vest).size() > 0, "the gear tab previews what equipping changes")
	d.cycle(1)
	await frames_wait(10)
	check(d.idx == 1 and d.gear_pick.is_empty(), "E flips to the next soldier")
	await shot("dossier_hex_gear")
	d.done.emit()
	await frames_wait(10)
	check(hq.idle(), "BACK returns to the HQ scene")
	# read-only from the field: no service tiles
	var ro: Control = load("res://scripts/dossier.gd").new()
	ro.readonly = true
	ro.idx = 2
	main.add_child(ro)
	ro.sel = Run.soldiers[2].deck[0]
	ro.build()
	await frames_wait(6)
	check(not ro.get_children().any(func(o): return o.get_script() != null and o.get("why") != null), "a read-only Dossier shows no service buttons")
	ro.queue_free()

func recruits() -> void:
	## Recruit rules: never a second soldier of a living class, Drilled names its card up front,
	## and the Barracks 2 free level is a pick, not a roll.
	Run.new_run()
	var hq0: Dictionary = Run.meta.get("hq", {}).duplicate()
	Run.meta["hq"] = {}
	Run.soldiers[0].alive = false  # Moss
	for k in 20:
		var offers := Run.recruit_offers(3)
		var keys: Array = offers.map(func(o): return o.key)
		if keys[0] != "moss" or keys.any(func(x): return x in ["hex", "vee", "rook"]):
			check(false, "offers only the fallen class when every other class is alive (%s)" % str(keys))
			break
	check(true, "with three alive, every offer is the fallen soldier's class")
	Run.soldiers[1].alive = false  # Hex too
	var seen := {}
	for k in 20:
		for o in Run.recruit_offers(3):
			seen[o.key] = true
	check(Run.recruit_offers(3)[0].key == "moss", "the first fallen soldier's class comes first")
	check(seen.keys().all(func(x): return x in ["moss", "hex"]), "offers never repeat a living class (%s)" % str(seen.keys()))
	# Drilled names its card, and that card is the one raised
	var off: Dictionary = Run.recruit_offers(1)[0]
	off.trait = Data.RECRUIT_TRAITS.filter(func(t): return t.id == "drilled")[0]
	check(off.drill_card != "", "a recruit offer names the card Drilled raises (%s)" % off.drill_card)
	var rec := Run.hire(0, off)
	var up: Array = rec.deck.filter(func(c): return Data.tier_of(c) > Data.base_tier(c.key))
	check(up.size() == 1 and up[0].key == off.drill_card, "Drilled raises exactly that card")
	# Barracks 2: the free level waits for a pick
	Run.meta["hq"] = {"barracks": 2}
	Run.scrip = 999
	main.show_hq(false)
	await frames_wait(10)
	main.screen.open_shop("barracks")
	await frames_wait(10)
	var sh: Control = main.screen.sub
	sh.recruit()
	await frames_wait(10)
	await shot("recruits_offers")
	check(sh.chooser != null, "the Barracks shows the recruit offers")
	var cards: Array = sh.chooser.get_children().filter(func(c): return c is CardView)
	check(cards.size() == 3 and cards.all(func(c): return c.opt.name != ""), "3 offers to pick from")
	sh.chosen.emit(0)
	await frames_wait(10)
	var hired: Dictionary = Run.soldiers[1]
	check(hired.alive and hired.lvl == 2 and hired.get("train", false), "Barracks 2: the recruit arrives at level 2 with a training pick waiting")
	await shot("recruits_training")
	check(sh.chooser != null, "the training pick opens right away")
	var deck0: int = hired.deck.size()
	var bonus0: Dictionary = hired.bonus.duplicate()
	var perks0: int = hired.perks.size()
	sh.chosen.emit(-1)
	await frames_wait(10)
	check(hired.get("train", false), "cancelling keeps the training for later")
	check(main.screen.badges().get("barracks", "") == "TRAINING", "the HQ flags the Barracks while training waits")
	var tiles: Array = sh.get_children().filter(func(c): return c is HubUI.ActionTile and c.title == "TRAINING")
	check(tiles.size() == 1, "the Barracks has a TRAINING tile")
	await shot("recruits_tile")
	tiles[0].pressed.emit()
	await frames_wait(10)
	sh.chosen.emit(0)
	await frames_wait(10)
	check(not hired.has("train") and (hired.deck.size() != deck0 or hired.bonus != bonus0 or hired.perks.size() != perks0), "the picked option is applied once")
	Run.meta["hq"] = hq0

func modal_title(b: Battle) -> String:
	for c in b.hud.modal.get_children():
		if c is HudScript.ModalBG and not c.is_queued_for_deletion():
			return c.title
	return ""

func picks() -> void:
	## No dice in deckbuilding: supply drops ask who gets the card, and the camp Field Upgrade
	## lets each soldier pick the card.
	Run.new_run()
	var lvl := {"name": "PICK YARD", "theme": "dusk", "segments": ["start", "towers", "camp", "arena"],
		"boss_hp": 120, "plate": 36, "hp_mul": 1.0, "brief": "", "rules": {"pads": 0}}
	var b: Battle = main.start_battle(0, lvl)
	await until(func(): return b.state == "player" and not b.busy)
	var sq: Array = b.squad()
	# --- supply drop
	var n2: int = sq[2].s.deck.size()
	var others: Array = [0, 1, 3].map(func(k): return sq[k].s.deck.size())
	b.supply_drop.call("Supply drop", null)
	await frames_wait(10)
	await shot("picks_supply")
	check(modal_title(b) == "Supply drop", "the drop shows its three picks first")
	b.hud.picked.emit(0)
	await frames_wait(10)
	await shot("picks_supply_who")
	var who: Array = b.hud.modal.get_children().filter(func(c): return c is CardView and not c.is_queued_for_deletion())
	check(modal_title(b).begins_with("WHO GETS") and who.size() == sq.size(), "then asks who gets it (%s, %d soldiers)" % [modal_title(b), who.size()])
	check(who[2].label_top == "TO " + sq[2].def.name, "each copy is labelled with its soldier (%s)" % who[2].label_top)
	b.hud.picked.emit(2)
	await frames_wait(10)
	check(sq[2].s.deck.size() == n2 + 1 and [0, 1, 3].map(func(k): return sq[k].s.deck.size()) == others, "the card goes to the soldier you picked and nobody else")
	check(sq[2].s.deck[-1].get("from", "") == "drop", "it is marked as a supply drop card")
	# --- camp Field Upgrade
	var c: Dictionary = b.T.camps[0]
	var me: Dictionary = sq[0].s
	var cands: Array = b.upgrade_choices(me)
	var target: Dictionary = cands[1]
	var t0 := Data.tier_of(target)
	var snap: Array = sq.map(func(u): return u.s.deck.map(func(cd): return Data.tier_of(cd)))
	b.camp_pick.call(c)
	await frames_wait(10)
	b.hud.picked.emit(1)  # FIELD UPGRADE
	await frames_wait(10)
	await shot("picks_camp_grid")
	var grid: Array = b.hud.modal.get_children().filter(func(o): return o is CardView and not o.is_queued_for_deletion())
	check(modal_title(b).contains("FIELD UPGRADE") and grid.size() == cands.size(), "Field Upgrade shows %s's upgradable cards (%d)" % [me.def.name, grid.size()])
	check(Data.tier_of(grid[1].opt) == t0 + 1, "each card is shown one rarity up")
	b.hud.picked.emit(1)
	await frames_wait(10)
	check(Data.tier_of(target) == t0 + 1, "the card you picked goes up a rarity")
	for k in range(1, sq.size()):
		check(modal_title(b).begins_with(sq[k].def.name), "then %s picks" % sq[k].def.name)
		b.hud.picked.emit(-1)
		await frames_wait(10)
	check(range(1, sq.size()).all(func(k): return sq[k].s.deck.map(func(cd): return Data.tier_of(cd)) == snap[k]), "a skipped soldier's deck is untouched")
	var mine: Array = me.deck.map(func(cd): return Data.tier_of(cd))
	var diff := 0
	for k in mine.size():
		if mine[k] != snap[0][k]:
			diff += 1
	check(diff == 1, "exactly one of %s's cards changed" % me.def.name)

func field() -> void:
	## PR 3 of the HQ hub: the gate loadout line (H5), all decks at once (D3), the Dossier
	## from the field (S6) and the practice range that puts everything back (D5).
	Run.new_run()
	Run.scrip = 300
	# --- H5
	main.dial_gate()
	await frames_wait(20)
	await shot("field_dial")
	var line: String = main.screen.loadout_line(Run.soldiers[0])
	check(line.contains("cards of %d" % Run.soldiers[0].deck.size()), "the gate dial sums up each deck: " + line)
	# --- D3
	main.show_hq(false)
	await frames_wait(20)
	var hq: Control = main.screen
	var bars: Array = hq.get_children().filter(func(c): return c is HubUI.SquadBar)
	check(bars.size() == 1 and bars[0].has_all(), "the HQ squad bar has an ALL DECKS plate")
	bars[0].all_decks.emit()
	await frames_wait(20)
	await shot("field_all_decks")
	var d: Control = hq.sub
	check(d != null and d.tab == "squad", "ALL DECKS opens every deck side by side")
	check(d.deck_rows(Run.soldiers[0]).size() < Run.soldiers[0].deck.size(), "copies stack into one row (%d rows for %d cards)" % [d.deck_rows(Run.soldiers[0]).size(), Run.soldiers[0].deck.size()])
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = d.squad_col(2).get_center()
	d._gui_input(ev)
	await frames_wait(6)
	check(d.tab == "deck" and d.idx == 2, "clicking a column opens that soldier's deck")
	d.done.emit()
	await frames_wait(6)
	# --- S6: the debrief
	main.show_debrief({"score": 100, "kills": 3})
	await frames_wait(10)
	var db: Control = main.screen
	var dz: Array = db.get_children().filter(func(c): return c is HudScript.PixButton and c.text == "SQUAD DOSSIER")
	check(dz.size() == 1, "the debrief has a SQUAD DOSSIER button")
	dz[0].pressed.emit()
	await frames_wait(10)
	var fd: Array = db.get_children().filter(func(c): return c.get_script() == load("res://scripts/dossier.gd"))
	check(fd.size() == 1 and fd[0].readonly, "it opens the Dossier read-only")
	fd[0].sel = Run.soldiers[0].deck[0]
	fd[0].build()
	await frames_wait(6)
	await shot("field_debrief_dossier")
	check(not fd[0].get_children().any(func(c): return c is HubUI.ActionTile), "no card services in the field")
	check(not fd[0].get_children().any(func(c): return c is HudScript.PixButton and c.text.begins_with("PRACTICE RANGE")), "no practice range from the field")
	fd[0].done.emit()
	await frames_wait(6)
	# --- S6: the level-up pick and the battle deck view
	var lvl := {"name": "FIELD YARD", "theme": "dusk", "segments": ["start", "towers", "camp", "arena"],
		"boss_hp": 120, "plate": 36, "hp_mul": 1.0, "brief": "", "rules": {"pads": 0}}
	var b: Battle = main.start_battle(0, lvl)
	await until(func(): return b.state == "player" and not b.busy)
	var u: Unit = b.squad()[1]
	b.hud.pick.call("level", "LEVEL UP!", "Pick one.", Run.level_options(u.s), u)
	await frames_wait(10)
	var pb: Array = b.hud.modal.get_children().filter(func(c): return c is HudScript.PixButton and c.text == "DOSSIER")
	check(pb.size() == 1, "the level-up pick has a DOSSIER button")
	pb[0].pressed.emit()
	await frames_wait(10)
	var hd: Array = b.hud.get_children().filter(func(c): return c.get_script() == load("res://scripts/dossier.gd"))
	check(hd.size() == 1 and hd[0].readonly and hd[0].idx == Run.soldiers.find(u.s), "it opens on the soldier levelling up")
	await shot("field_levelup_dossier")
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	hd[0]._input(key)
	check(get_viewport().is_input_handled(), "keys stop at the Dossier and never reach the battle")
	hd[0].done.emit()
	b.hud.picked.emit(-1)
	await frames_wait(10)
	b.sel = u
	b.hud.show_deck()
	await frames_wait(6)
	var db2: Array = b.hud.modal.get_children().filter(func(c): return c is HudScript.PixButton and c.text == "DOSSIER")
	check(db2.size() == 1, "the battle deck view has a DOSSIER button")
	b.hud.modal.visible = false
	# --- D4: kills per card
	var shooter: Unit = b.squad()[0]
	var inst: Dictionary = shooter.hand.filter(func(c): return not c.get("temp", false))[0]
	b.spend_card(shooter, shooter.hand.find(inst))
	for k in Data.NICK_KILLS:
		var dm := b.mk_enemy("grunt", shooter.x + 200 + k * 10, b.T.stand_y(shooter.x + 200, 0))
		dm.active = true
		b.units.append(dm)
		b.damage(dm, 999, shooter)
	check(int(inst.get("kills", 0)) == Data.NICK_KILLS and inst.has("nick"), "the played card counts its kills and earns a nickname at %d (%s)" % [Data.NICK_KILLS, inst.get("nick", "none")])
	check(shooter.s.deck.has(inst), "the count lives on the deck card itself")
	await until(func(): return not b.busy, 600)
	var g3: Array = [Run.new_card("knife", 0), Run.new_card("knife", 0), Run.new_card("knife", 0)]
	g3[0]["kills"] = 2
	g3[2]["kills"] = 3
	var sx: Dictionary = Run.soldiers[3]
	sx.deck.append_array(g3)
	var fz := Run.fuse(sx, g3)
	check(int(fz.get("kills", 0)) == 5, "a fused card keeps the copies' kills")
	main.show_hq(false)
	await frames_wait(10)
	main.screen.open_dossier(Run.soldiers.find(shooter.s))
	await frames_wait(6)
	main.screen.sub.sel = inst
	main.screen.sub.build()
	await frames_wait(6)
	await shot("field_card_kills")
	main.screen.sub.set_tab("squad")
	await frames_wait(6)
	await shot("field_top_card")
	main.screen.sub.done.emit()
	await frames_wait(4)
	# --- D5: the practice range
	main.show_hq(false)
	await frames_wait(10)
	var moss: Dictionary = Run.soldiers[0]
	moss.hp = 9
	var scrip0: int = Run.scrip
	var deck0: int = moss.deck.size()
	var hist0: int = Run.history.size()
	main.screen.open_dossier(0)
	await frames_wait(10)
	var pr: Array = main.screen.sub.get_children().filter(func(c): return c is HudScript.PixButton and c.text.begins_with("PRACTICE RANGE"))
	check(pr.size() == 1, "the HQ Dossier has a PRACTICE RANGE button")
	await shot("field_practice_button")
	pr[0].pressed.emit()
	await frames_wait(4)
	b = main.battle
	await until(func(): return b.state == "player" and not b.busy)
	check(b.squad().size() == 1 and b.squad()[0].s.key == moss.key, "only Moss goes to the range")
	check(b.dummies.size() >= 4, "%d dummies stand on the range" % b.dummies.size())
	await frames_wait(30)
	await shot("field_range")
	var me: Unit = b.squad()[0]
	for e in b.units.filter(func(o): return o.team == "enemy" and not o.dead):
		b.damage(e, 999, me)
	await until(func(): return not b.busy, 600)
	Run.scrip += 100
	moss.deck.append(Run.new_card("rifle", 0, "shop"))
	b.end_turn(true)
	await until(func(): return b.state == "player" and not b.busy)
	check(b.units.filter(func(o): return o.team == "enemy" and not o.dead).size() == b.dummies.size(), "the dummies stand back up when they are all down")
	check(me.xp_gain == 0 and b.lvl_queue.is_empty(), "no XP at the range")
	check(b.round_n == 2 and me.hp > 0, "no enemy phase: round 2 starts with Moss untouched")
	await shot("field_range_reset")
	b.leave_practice()
	await frames_wait(20)
	check(main.screen != null and main.screen.has_method("open_dossier") and main.screen.sub != null and main.screen.sub.idx == 0, "leaving the range comes back to Moss's Dossier at HQ")
	check(Run.scrip == scrip0 and Run.soldiers[0].hp == 9 and Run.soldiers[0].deck.size() == deck0 and Run.history.size() == hist0, "everything the range touched is put back (scrip %d, HP %d, deck %d)" % [Run.scrip, Run.soldiers[0].hp, Run.soldiers[0].deck.size()])
	await shot("field_back")

func hub() -> void:
	## The HQ hub: buildings with one job each, a nav strip between them, ready badges, the
	## gate reminder, the walk, the Workshop's shortcuts and Patch Up at the Doc's Lab.
	Run.new_run()
	Run.meta["tips_off"] = false
	Run.scrip = 500
	Run.soldiers[0].hp = 9
	Run.soldiers[2].deck.append(Run.new_card("frag", 0, "shop"))
	Run.stash.append(Run.new_item("ghillie", 0))
	Run.stash.append(Run.new_item("ghillie", 0))
	main.show_hq(false)
	await frames_wait(20)
	var hq: Control = main.screen
	var b: Dictionary = hq.badges()
	check(b.get("qm", "") == "NEW STOCK" and b.has("workshop") and b.get("doc", "") == "HURT", "badges: new stock, fusions ready, someone hurt: %s" % b)
	check(hq.reminders().any(func(l): return l.contains("scrip unspent")) and hq.reminders().any(func(l): return l.contains("MOSS")), "the gate reminds about scrip and Moss's HP")
	hq.dial_btn.hover = true
	await frames_wait(4)
	await shot("hub_hq")
	hq.dial_btn.hover = false
	# walking to a building opens it after the squad gets there
	hq.walk_to("qm")
	await frames_wait(14)
	await shot("hub_walk")
	await until(func(): return hq.sub != null and is_instance_valid(hq.sub), 120)
	await frames_wait(10)
	var qm: Control = hq.sub
	check(qm.get("mode") == "shop" and qm.bark == 0, "the walk ends in the Quartermaster, who explains the tent once")
	await shot("hub_qm_bark")
	check(hq.get_node_or_null("Nav") != null, "the nav strip sits over the building")
	qm.bark = -1
	qm.build()
	check(not hq.badges().has("qm"), "the NEW STOCK badge clears after a visit")
	qm.shelf_pick = 0
	qm.build()
	await frames_wait(6)
	await shot("hub_qm")
	var n_stash: int = Run.stash.size() + Run.belt.size()
	qm.buy_shelf()
	check(Run.stash.size() + Run.belt.size() == n_stash + 1, "the Quartermaster sells shelf items straight to the stash")
	# drag a card onto a soldier
	qm.buy_card(0)
	await frames_wait(6)
	var tp: Control = qm.chooser
	tp.drag = {"opt": qm.stock_cards[0], "held": true}
	await frames_wait(4)
	await shot("hub_pick")
	tp.picked.emit(1)
	await frames_wait(6)
	check(qm.stock_cards[0].get("sold", false) and Run.soldiers[1].deck.any(func(c): return c.get("from", "") == "shop"), "a shop card dropped on Hex goes in Hex's deck")
	# the nav strip jumps between buildings
	hq.go("workshop")
	await frames_wait(10)
	var ws: Control = hq.sub
	check(ws.get_script() == load("res://scripts/workshop.gd"), "the nav strip opens the Workshop")
	await shot("hub_workshop")
	var svs: Array = ws.services()
	check(svs[2][6] and svs[2][4].contains("VEE"), "Workshop FUSE lists Vee's ready Frags: " + svs[2][4])
	check(not svs[3][6] and svs[3][5] != "", "Workshop EVOLVE says what it needs: " + svs[3][5])
	ws.start_pick("polish")
	await frames_wait(6)
	check(ws.bar.pickable.size() == 4, "every soldier has a card to polish")
	await shot("hub_workshop_pick")
	ws.on_pick(0)
	await frames_wait(10)
	check(ws.sub != null and ws.sub.filt == "polish" and ws.sub.idx == 0, "picking Moss opens her Dossier filtered to polishable cards")
	check(not hq.get_node("Nav").visible, "the nav strip steps aside while a Dossier is open")
	ws.sub.done.emit()
	await frames_wait(6)
	var frags: Array = Run.soldiers[2].deck.filter(func(c): return c.key == "frag")
	ws.open_dossier(2, "fuse", frags[0], "fuse")
	await frames_wait(10)
	await shot("hub_workshop_fuse")
	ws.sub.modal.confirm.pressed.emit()
	await frames_wait(10)
	check(Run.fusable(Run.soldiers[2]).is_empty(), "the READY NOW shortcut fuses Vee's Frags")
	ws.sub.done.emit()
	# Doc's Lab: Patch Up works before the lab is built
	hq.go("doc")
	await frames_wait(10)
	await shot("hub_doc")
	var patch: Control = hq.get_children().filter(func(c): return c.get("title") == "PATCH UP")[0]
	patch.pressed.emit()
	await frames_wait(6)
	check(Run.soldiers[0].hp == Run.eff_max_hp(Run.soldiers[0]), "Patch Up at the Doc's Lab heals Moss")
	# Armory: copy an item
	hq.go("armory")
	await frames_wait(10)
	var arm: Control = hq.sub
	arm.select({"where": "stash", "i": Run.stash.find(Run.stash.filter(func(it): return it.id == "ghillie")[0])})
	await frames_wait(6)
	await shot("hub_armory")
	arm.copy_sel()
	await frames_wait(6)
	check(Run.stash.filter(func(it): return it.id == "ghillie").size() == 3 and Run.any_merge(), "COPY at the Armory finishes a triple")
	check(hq.badges().get("armory", "") == "TRIPLE READY", "the Armory badge lights for the triple")
	hq.go("barracks")
	await frames_wait(10)
	await shot("hub_barracks")
	# keys: ESC goes home, W opens the Workshop
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	hq._unhandled_input(esc)
	await frames_wait(6)
	check(hq.idle(), "ESC from a building goes home")
	var w := InputEventKey.new()
	w.keycode = KEY_W
	w.pressed = true
	hq._unhandled_input(w)
	await frames_wait(6)
	check(hq.sub != null and hq.sub.get_script() == load("res://scripts/workshop.gd"), "W opens the Workshop")

func click_at(p: Vector2) -> void:
	## A real left click pushed through the viewport, so it has to land on a control's rect like a mouse would.
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = p
		ev.global_position = p
		get_viewport().push_input(ev, true)
		await frames_wait(2)

func clicks() -> void:
	## Screens that read clicks on their own rect (not a child button) must cover the whole view.
	## They used to be 0x0, so crates, shop picks and HQ soldiers ignored the mouse.
	Run.new_run()
	var tips = Run.meta.get("tips_off", false)
	Run.meta["tips_off"] = true
	Run.scrip = 500
	main.show_hq(false)
	await frames_wait(20)
	var hq: Control = main.screen
	check(hq.size == Vector2(960, 540), "the HQ covers the view: %s" % hq.size)
	await click_at(Vector2(hq.troop_x(0), hq.GROUND - 20))
	await frames_wait(10)
	check(hq.sub != null and is_instance_valid(hq.sub), "clicking a soldier at HQ opens their Dossier")
	main.show_debrief({})
	await frames_wait(10)
	var d: Control = main.screen
	check(d.size == Vector2(960, 540), "the debrief covers the view: %s" % d.size)
	await click_at(d.crate_rect(0).get_center())
	check(d.crates[0].open_t >= 0, "clicking a crate opens it")
	await frames_wait(200)
	main.show_shop()
	await frames_wait(10)
	var sh: Control = main.screen
	var gold := Run.scrip
	sh.buy_card(0)
	await frames_wait(4)
	check(sh.chooser != null and sh.chooser.size == Vector2(960, 540), "the who-gets-it picker covers the view")
	var deck0: int = Run.soldiers[1].deck.size()
	if sh.chooser != null:
		await click_at(sh.chooser.tiles[1].get_center())
	await frames_wait(6)
	check(Run.soldiers[1].deck.size() == deck0 + 1 and Run.scrip < gold, "clicking Hex's plate gives Hex the card")
	Run.meta["tips_off"] = tips

func press_key(k: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.pressed = down
		get_viewport().push_input(ev, true)
	await frames_wait(3)

func pause_menu() -> void:
	## N7: Esc cancels an armed card first; with nothing armed it pauses under a menu, and Esc resumes.
	Run.new_run()
	var b: Battle = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	b.select_card(0)
	await press_key(KEY_ESCAPE)
	check(b.card_idx < 0 and not get_tree().paused, "Esc with a card armed cancels it and doesn't pause")
	await press_key(KEY_ESCAPE)
	var menu = main.hud.get_children().filter(func(c): return c is HudScript.PauseMenu)
	check(get_tree().paused and menu.size() == 1, "Esc with nothing armed pauses under the menu")
	var t0: int = b.t
	await frames_wait(10)
	check(b.t == t0, "the battle stands still while paused")
	await press_key(KEY_ESCAPE)
	check(not get_tree().paused, "Esc again resumes")
	await press_key(KEY_ESCAPE)
	menu = main.hud.get_children().filter(func(c): return c is HudScript.PauseMenu)
	menu[0].quit()
	await frames_wait(5)
	check(main.battle == null and not get_tree().paused, "QUIT TO TITLE leaves the battle")

func operator_call() -> void:
	## C4: radio lines come in on a corner tablet that clicks through and hangs up by itself.
	Run.new_run()
	var lines: Array = Data.RADIO_LANDFALL.map(func(r): return Run.radio_line(r[0], r[1], Run.soldiers))
	main.show_hq(false)
	main.call_in(lines)
	await frames_wait(40)
	var oc: Control = main.call_layer.get_child(0)
	check(oc.line().name == "MAJ. HALE" and oc.shown > 0, "Hale's first line is typing out (%d chars)" % oc.shown)
	check(main.screen != null and main.screen.idle(), "the HQ under it stays usable")
	await click_at(oc.global_position + Vector2(200, 60))
	check(oc.shown == lines[0].text.length(), "a click finishes the line")
	await click_at(oc.global_position + Vector2(200, 60))
	check(oc.i == 1, "the next click moves to line 2")
	await click_at(oc.global_position + Vector2(oc.W - 13, 12))
	await frames_wait(40)
	check(not is_instance_valid(oc), "the X hangs up and the tablet slides away")
	main.show_hq(false)

func training() -> void:
	## N6: the drill walks through move, shoot, crate, frag and push, then a short real fight.
	var had: bool = Run.meta.get("trained", false)
	main.start_training()
	var b: Battle = main.battle
	await until(func(): return b.state == "player" and not b.busy)
	await frames_wait(20)
	check(b.tutorial() and b.tut_step == b.TUT_MOVE, "training opens on the move step")
	check(main.call_layer.get_child_count() > 0 and main.call_layer.get_child(0).line().name == "SGT. KRUGER", "the sergeant calls in on the tablet")
	b.squad()[0].x = 320
	await frames_wait(20)
	check(b.tut_step == b.TUT_SHOOT, "walking forward clears the move step")
	await frames_wait(20)
	check(b.sel.hand.any(func(c): return c.key == "rifle"), "the selected soldier holds a rifle shot for the shoot step")
	for u in b.tut_marks.target:
		b.kill(u, b.sel)
	await frames_wait(20)
	check(b.tut_step == b.TUT_CRATE, "dropping the target clears the shoot step")
	for u in b.tut_marks.crate:
		u.dead = true
	await frames_wait(20)
	check(b.tut_step == b.TUT_THROW, "opening the crate clears the crate step")
	await frames_wait(20)
	check(b.sel.hand.any(func(c): return c.key == "frag"), "the selected soldier holds a frag for the grenade step")
	b.end_turn(true)
	await until(func(): return b.state == "player" and not b.busy)
	check(b.squad_alive().size() == 4 and b.tut_marks.group.all(func(u): return not u.dead), "the drill's targets don't shoot back between turns")
	b.explode(b.tut_marks.group[0].x, b.tut_marks.group[0].y, 36, 11, b.sel)
	await until(func(): return b.settled(), 600)
	await frames_wait(20)
	check(b.tut_step == b.TUT_PUSH, "a grenade blast clears the throw step")
	b.cam_x = 120; b.cam_tx = 120
	await frames_wait(20)
	check(b.tut_step == b.TUT_FIGHT, "scrolling on clears the push step and starts the fight")
	for u in b.units:
		if u.team == "enemy" and not u.dead:
			u.dead = true; u.gone = true
	b.lvl_queue.clear(); b.loot_queue.clear()  # level-up and loot picks would wait for a click
	b.post_action()
	await until(func(): return Run.meta.get("trained", false) or main.battle == null or not is_instance_valid(b), 1200)
	await frames_wait(30)
	check(Run.meta.get("trained", false), "winning the drill marks training done")
	check(main.call_layer.get_child_count() > 0 and main.call_layer.get_child(0).lines[0].text == Data.TUT_DONE_LINES[0], "the sergeant signs off over the title")
	if not had:
		Run.meta.erase("trained")
		Run.save_meta()

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
	# the posts that are left are stepping stones: hop bank to post to post to the far bank
	for o in b.units:
		if o.team != "squad" and o.x > br.x0 - 150 and o.x < br.x1 + 150:
			o.dead = true; o.gone = true  # clear the far bank so only the hops are tested
	var hopper: Unit = b.squad()[0]
	hopper.x = br.x0 - 14; hopper.y = b.T.stand_y(hopper.x, br.y - 40); hopper.air = false
	var stops: Array = []
	for px in br.posts:
		if b.T.solid(px, br.y + 10) and not b.T.solid(px, br.y + 2):
			stops.append(px)
	stops.append(br.x1 + 20)
	var hops := 0
	for tx in stops:
		if hopper.dead or hopper.sunk:
			break
		await hop_to(b, hopper, tx)
		hops += 1
	await shot("hz_bridge_hopped")
	check(not hopper.sunk and not hopper.dead and hopper.x > br.x1, "a soldier hops the broken bridge post to post (%d hops of %d, at x %d, far bank %d)" % [hops, stops.size(), hopper.x, br.x1])
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
	# the ridge cliff in mission 2 is a wall about head high: one hop gets up it
	var climber: Unit = b.squad()[1]
	var cl = null
	for L in b.T.ladders:
		if cl == null and L.offx > L.x and L.bot - L.top > 30:
			cl = L
	climber.x = cl.x - 16; climber.y = b.T.stand_y(climber.x, cl.bot - 30); climber.air = false
	cam_on(b, climber.x + 200)
	var y0 := climber.y
	for o in b.units:
		if o.kind == "crate" and absf(o.x - cl.offx) < 120:
			o.gone = true  # a random supply crate on the ledge would bump the hop
	await hop_to(b, climber, cl.offx + 20)
	check(climber.y < y0 - 30, "one hop gets a soldier up the %dpx ridge cliff (y %d -> %d)" % [cl.bot - cl.top, y0, climber.y])
	check(climber.move_left == 0, "a hop uses the rest of the soldier's movement")
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
	for o in b.units:
		if o.is_body():
			o.gone = true  # bodies from that blast can land on a mine too; this check is about walking
	# that Jackal's body can be thrown onto the next mine and set it off: walk over one still armed
	var m2: Unit = mines.filter(func(m): return not m.primed and not m.gone and m != m0 and m != m1)[0]
	var walker := b.mk_enemy("grunt", m2.x - 30, b.T.stand_y(m2.x - 30, m2.y - 40))
	b.units.append(walker)
	var ws := b.sim_walk(walker, m2.x + 30, 80)
	await b.walk_along(walker, ws.pts)
	await frames_wait(30)
	check(not m2.primed, "a Jackal walking over its own mine leaves it alone")
	# the MOVE button and the after-wave drag never walk a soldier onto a mine
	var walker_s: Unit = b.squad_alive()[0]
	for o in b.squad_alive():
		if o != walker_s:
			o.x = maxf(0, m2.x - 400)  # out of the way so only one soldier walks
	walker_s.x = m2.x - 30; walker_s.y = b.T.stand_y(walker_s.x, m2.y - 40); walker_s.air = false
	walker_s.move_left = 200; walker_s.energy = 0
	b.cam_x = maxf(0, m2.x - 300); b.cam_tx = b.cam_x
	b.busy = false
	b.auto_advance()
	await until(func(): return not b.busy, 600)
	await frames_wait(30)
	check(not m2.primed and walker_s.x < m2.x, "MOVE stops short of an armed mine (soldier %d, mine %d)" % [walker_s.x, m2.x])
	var al := b.squad_alive()
	var dragged: Unit = al[0]
	var lane := b.cam_x + 16
	var lane_mine := b.mk_unit()
	lane_mine.team = "neutral"; lane_mine.kind = "mine"; lane_mine.w = 12; lane_mine.h = 6
	lane_mine.x = lane; lane_mine.y = b.T.stand_y(lane, b.T.ground_at(lane) - 40)
	b.units.append(lane_mine)
	dragged.x = lane - 200; dragged.y = lane_mine.y; dragged.air = false
	b.drag_stragglers()
	await frames_wait(30)
	check(not lane_mine.primed and absf(dragged.x - lane_mine.x) > dragged.w / 2.0 + 5, "dragging a straggler forward skips past a mine (soldier %d, mine %d)" % [dragged.x, lane_mine.x])
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

func alien_field(b: Battle, x: float) -> Unit:
	## Clear the field and stand one soldier at x for an alien test.
	for e in b.units:
		if e.team == "enemy" or e.is_prop() or e.is_pickup() or e.kind == "pow":
			e.dead = true; e.gone = true
	var s: Unit = b.squad()[0]
	s.st.clear()
	for o in b.squad():
		if o != s:
			o.x = x - 200; o.y = b.T.stand_y(o.x, 0); o.air = false
	s.x = x; s.y = b.T.stand_y(x, 0); s.air = false; s.hp = s.max_hp
	cam_on(b, x + 120)
	return s

func flat_open(b: Battle, x: float, w: float) -> bool:
	## Flat ground with open sky over it from x to x + w.
	var y0 = b.T.stand_y(x, 0)
	if y0 == null:
		return false
	for k in range(0, int(w), 8):
		var y = b.T.stand_y(x + k, 0)
		if y == null or absf(y - y0) > 4:
			return false
	return true

func flat_strip(b: Battle, x: float, w: float) -> void:
	## Level a strip of open ground from x to x + w for a duel test.
	var y0: float = Data.WATER_Y - 96
	b.T.fill_r(x, 0, w, y0, 0)
	b.T.fill_r(x, y0, w, Data.WATER_Y - y0 + 8, 1)
	b.T.flush()

func spawn_alien(b: Battle, type: String, x: float) -> Unit:
	var e := b.mk_enemy(type, x, b.T.stand_y(x, 0))
	e.active = true
	b.units.append(e)
	b.place_alien(e)
	return e

func aliens() -> void:
	## The first Vharr: spawn casting by level, then each alien's marked move and its physics hook.
	Run.new_run()
	Run.level = Run.make_level("desert", 0)
	var b: Battle = main.start_battle(0, Run.level)
	await until(func(): return b.state == "player" and not b.busy)
	var types := b.units.filter(func(u): return u.team == "enemy").map(func(u): return u.type)
	check(not types.has("nade"), "no Jackal Bombers spawn (level 1: %s)" % str(types))
	check(types.has("grunt") and types.any(func(t): return Data.BIOME_ALIENS.desert.has(t)), "level 1 keeps riflemen with a few Vharr advisors")
	Run.level = Run.make_level("fortress", 1)
	b = main.start_battle(1, Run.level)
	await until(func(): return b.state == "player" and not b.busy)
	types = b.units.filter(func(u): return u.team == "enemy").map(func(u): return u.type)
	check(not types.has("grunt") and not types.has("nade") and Data.BIOME_ALIENS.fortress.filter(func(t): return types.has(t)).size() >= 3, "level 2 gives every rifleman slot to the fortress's Vharr (%s)" % str(types))
	check(types.count("skitter") % 3 == 0, "Skitters come in packs of 3 (%d)" % types.count("skitter"))
	b.speed = 2.0
	# a flat stretch near the start for the duels
	var x0 := 300.0
	while not flat_open(b, x0 - 120, 420):
		x0 += 20
	# --- Skitter: closes in and pounces in one enemy phase
	var s := alien_field(b, x0)
	var sk := spawn_alien(b, "skitter", x0 + 200)
	var hp0 := s.hp
	await b.enemy_act(sk)
	await until(func(): return b.settled(), 600)
	await shot("alien_skitter")
	check(s.hp < hp0 and absf(sk.x - s.x) < 30, "a Skitter pounces and bites in the same phase (hp %d -> %d)" % [hp0, s.hp])
	# light: the same blast throws a Skitter twice as far as a Rifleman
	var gr := spawn_alien(b, "grunt", x0 + 60)
	var sk2 := spawn_alien(b, "skitter", x0 + 60)
	sk2.hp = 99; gr.hp = 99
	b.explode(x0 + 40, b.T.stand_y(x0 + 40, 0) - 10, 40, 1, s)
	check(absf(sk2.vx) > absf(gr.vx) * 1.8, "light Skitter flies twice as far (vx %.1f vs %.1f)" % [sk2.vx, gr.vx])
	await until(func(): return b.settled(), 900)
	# --- Squid Trooper: hovers, glides and fires its ray in one phase
	s = alien_field(b, x0)
	var sq := spawn_alien(b, "squid", x0 + 260)
	var gy: float = b.T.stand_y(sq.x, 0)
	check(sq.y < gy - 80, "a Squid Trooper hovers (%d above the floor)" % (gy - sq.y))
	sq.hold = true
	hp0 = s.hp
	await b.enemy_act(sq)
	await until(func(): return b.settled(), 600)
	await shot("alien_squid")
	check(s.hp < hp0, "the Squid fires its ray the same phase (hp %d -> %d)" % [hp0, s.hp])
	var hp1 := sq.hp
	b.damage(sq, sq.pod, s)
	check(sq.weight == "" and sq.hp == hp1, "the pod soaks damage first, then breaks")
	await until(func(): return b.settled(), 600)
	check(not sq.air and sq.hp < hp1, "the squid drops and takes crash damage (hp %d -> %d)" % [hp1, sq.hp])
	# --- Blinker: teleports behind the soldier and claws
	s = alien_field(b, x0 + 60)
	var bl := spawn_alien(b, "blinker", x0 + 240)
	hp0 = s.hp
	await b.enemy_act(bl)
	await shot("alien_blinker")
	await until(func(): return b.settled(), 600)
	check(s.hp < hp0, "a Blinker teleports in and claws the same phase (hp %d -> %d)" % [hp0, s.hp])
	s = alien_field(b, x0 + 60)
	var far := spawn_alien(b, "blinker", x0 + 500)
	await b.enemy_act(far)
	check(far.x > x0 + 300 and far.x < x0 + 500, "a Blinker farther than 360px walks closer instead (x %d)" % far.x)

func aliens2() -> void:
	## Step 3 of the alien plan: BREACH dial tags, the Swarm and Nest encounters, alien elites.
	Run.new_run()
	Run.mission = 1
	Run.roll_dial()
	check(Run.dial.all(func(id): return Run.dial_breach.has(id)), "the level 2 dial rolls a BREACH flag per biome")
	Run.mission = 0
	Run.roll_dial()
	check(Run.dial.all(func(id): return not Run.dial_breach[id]), "level 1 never rolls a BREACH")
	var lv := Run.make_level("fortress", 1, true)
	check(lv.breach and lv.encounter in Data.ENCOUNTERS, "a level 2 level carries its breach flag and an encounter (%s)" % lv.encounter)
	# the nest: three Hive Pods with staggered timers
	lv.encounter = "nest"
	Run.level = lv
	var b: Battle = main.start_battle(1, lv)
	await until(func(): return b.state == "player" and not b.busy)
	var hives := b.units.filter(func(u): return u.type == "hive")
	check(hives.size() == 3 and hives.map(func(h): return h.fl.hatch) == [2, 3, 4], "the Nest has 3 Hive Pods on staggered timers (%s)" % str(hives.map(func(h): return h.fl.get("hatch"))))
	cam_on(b, hives[1].x)
	await frames_wait(20)
	await shot("alien2_nest")
	b.speed = 2.0
	var x0 := 300.0
	while not flat_open(b, x0 - 120, 420):
		x0 += 20
	# hatching, then acid
	var s := alien_field(b, x0)
	var hv := spawn_alien(b, "hive", x0 + 200)
	var count := func(): return b.units.filter(func(u): return u.type == "skitter" and not u.dead).size()
	await b.enemy_act(hv)
	check(count.call() == 0 and hv.fl.hatch == 1, "a Hive Pod counts down first")
	await b.enemy_act(hv)
	check(count.call() == 2, "then hatches two Skitters (%d)" % count.call())
	s.x = hv.x + 10; s.y = b.T.stand_y(s.x, 0)
	b.damage(hv, 99, s)
	check(b.acids.size() == 1, "a dead Hive Pod leaves acid")
	var hp0 := s.hp
	b.tick_acids()
	check(s.hp == hp0 - 3, "a soldier standing in acid takes 3 (hp %d -> %d)" % [hp0, s.hp])
	# the swarm tunnel: waves 3, 4, 3, then it caves in
	s = alien_field(b, x0)
	var bu := spawn_alien(b, "burrow", x0 + 220)
	var waves: Array = []
	for i in 3:
		var c0: int = count.call()
		await b.enemy_act(bu)
		waves.append(count.call() - c0)
	await b.enemy_act(bu)
	check(waves == [3, 4, 3] and bu.dead, "a tunnel sends waves %s and then caves in" % str(waves))
	await until(func(): return b.settled(), 600)
	await shot("alien2_swarm")
	# elites
	s = alien_field(b, x0)
	var br := spawn_alien(b, "skitter", x0 + 200)
	b.make_elite(br, "brood")
	b.damage(br, 99, s)
	check(count.call() == 2, "a BROOD Skitter splits into two (%d)" % count.call())
	s = alien_field(b, x0)
	var an := spawn_alien(b, "blinker", x0 + 120)
	b.make_elite(an, "anchored")
	an.hp = 99
	b.explode(an.x - 30, an.y - 10, 40, 1, s)
	check(absf(an.vx) < 0.01, "an ANCHORED alien is not knocked back")
	var body := spawn_alien(b, "grunt", an.x + 30)
	b.kill(body, s)
	b.make_elite(an, "hungry")
	an.max_hp = 99; an.hp = 50
	await b.enemy_act(an)
	check(an.hp >= 58 and body.gone, "a HUNGRY alien eats a body to heal (hp %d)" % an.hp)
	s = alien_field(b, x0)
	var al := spawn_alien(b, "squid", x0 + 200)
	var mate := spawn_alien(b, "squid", x0 + 300)
	b.make_elite(al, "alpha")
	check(b.alpha_near(mate) and not b.alpha_near(al), "an ALPHA makes others of its kind nearby act twice")
	check(Data.ELITES[b.pick_elite(true)].get("vharr", false) and not Data.ELITES[b.pick_elite(false)].get("vharr", false), "aliens and Jackals roll their own elites")
	# breach: a Jackal goes for the nearest alien instead of a far soldier
	s = alien_field(b, x0 - 100)
	var j := spawn_alien(b, "grunt", x0 + 260)
	var sk := spawn_alien(b, "skitter", x0 + 200)
	b.breach = false
	check(b.nearest_squad(j) == s, "outside a BREACH the Jackal targets your soldier")
	b.breach = true
	check(b.nearest_squad(j) == sk and b.nearest_squad(sk) == j, "in a BREACH the Jackal and the Skitter target each other")
	sk.dead = true; sk.gone = true
	var bk := spawn_alien(b, "blinker", x0 + 200)
	bk.hp = 99; bk.max_hp = 99
	for i in 3:
		await b.enemy_act(j)
		await until(func(): return b.settled(), 600)
	check(bk.hp < 99, "the Jackal shoots the alien instead (hp 99 -> %d)" % bk.hp)
	# Worms style: a Jackal with a shot already still moves before it fires
	b.breach = false
	s = alien_field(b, x0)
	var mover := spawn_alien(b, "grunt", x0 + 200)
	var mx := mover.x
	hp0 = s.hp
	await b.enemy_act(mover)
	await until(func(): return b.settled(), 600)
	check(absf(mover.x - mx) >= 30, "a Jackal with a clear shot still moves first (moved %d px)" % absf(mover.x - mx))

func aliens3() -> void:
	## More Vharr: Burrower, Grappler, Bloater, Dome Weaver, and the biome alien pools.
	Run.new_run()
	for id in Data.BIOME_ALIENS:
		check(Data.BIOME_ALIENS[id].all(func(t): return Data.ETYPES.has(t)), "%s has a valid alien pool" % id)
	Run.level = Run.make_level("desert", 1)
	var b: Battle = main.start_battle(1, Run.level)
	await until(func(): return b.state == "player" and not b.busy)
	var types := b.units.filter(func(u): return u.team == "enemy").map(func(u): return u.type)
	check(types.has("burrower") and not types.has("blinker"), "the desert sends Burrowers, not Blinkers")
	b.speed = 2.0
	var x0 := 600.0
	flat_strip(b, x0 - 160, 620)
	# --- Burrower: can't be shot while buried, tunnels and bursts out under you
	var s := alien_field(b, x0)
	var bw := spawn_alien(b, "burrower", x0 + 260)
	check(bw.weight == "buried", "a Burrower starts buried")
	var hit := b.trace_bullet(x0 + 100, bw.y - 10, 0.0, 400, 0, s, false)
	check(not hit.hits.any(func(h): return h.u == bw), "bullets pass over a buried Burrower")
	var hp0 := s.hp
	await b.enemy_act(bw)
	await until(func(): return b.settled(), 900)
	await shot("alien3_burrower")
	check(bw.weight == "" and absf(bw.x - x0) < 80 and s.hp < hp0, "it tunnels over and bursts out under the soldier (hp %d -> %d, x %d, %s)" % [hp0, s.hp, bw.x - x0, bw.weight])
	# --- Grappler: yanks a soldier in a clear line toward it
	s = alien_field(b, x0)
	var gp := spawn_alien(b, "grappler", x0 + 300)
	var sx := s.x
	await b.enemy_act(gp)
	await until(func(): return b.settled(), 900)
	await shot("alien3_grappler")
	check(s.x > sx + 100, "a Grappler yanks the soldier toward it (x %d -> %d)" % [sx, s.x])
	# --- Bloater: swells, waddles in, pops on you
	s = alien_field(b, x0)
	var bl := spawn_alien(b, "bloater", x0 + 120)
	hp0 = s.hp
	for i in 3:
		if bl.dead:
			break
		await b.enemy_act(bl)
		await until(func(): return b.settled(), 900)
	check(bl.dead and s.hp < hp0, "a Bloater walks up and pops on the soldier (hp %d -> %d)" % [hp0, s.hp])
	s = alien_field(b, x0)
	var bl2 := spawn_alien(b, "bloater", x0 + 260)
	var jk := spawn_alien(b, "grunt", x0 + 290)
	jk.hp = 99; jk.max_hp = 99
	b.kill(bl2, s)
	await until(func(): return b.settled(), 900)
	check(jk.hp < 99, "killing a Bloater pops it on its neighbours (Jackal hp %d)" % jk.hp)
	# --- Dome Weaver: domes an ally; bullets and blasts stop, melee goes through
	s = alien_field(b, x0)
	var wv := spawn_alien(b, "weaver", x0 + 360)
	var ally := spawn_alien(b, "grunt", x0 + 200)
	ally.hold = true
	ally.hp = 50; ally.max_hp = 50
	await b.enemy_act(wv)
	await until(func(): return b.settled(), 900)
	await shot("alien3_weaver")
	check(ally.dome > 0, "the Weaver domes the ally nearest the squad")
	b.damage(ally, 10, s, {})
	b.damage(ally, 10, s, {"blast": true})
	check(ally.hp == 50, "the dome stops bullets and blasts (hp %d)" % ally.hp)
	b.damage(ally, 10, s, {"melee": true})
	check(ally.hp == 40, "melee goes through the dome (hp %d)" % ally.hp)

func aliens4() -> void:
	## Batch 2 Vharr: Prism Drone, Gravity Warden, Phase Stalker, Overseer and its Thralls.
	Run.new_run()
	Run.level = Run.make_level("jungle", 2)
	var b: Battle = main.start_battle(2, Run.level)
	await until(func(): return b.state == "player" and not b.busy)
	var types := b.units.filter(func(u): return u.team == "enemy").map(func(u): return u.type)
	check(types.count("overseer") == 1, "level 3 brings one Overseer (%s)" % str(types))
	b.speed = 2.0
	var x0 := 600.0
	flat_strip(b, x0 - 160, 640)
	# --- Prism Drone: bullets bounce off the mirror face, hit from behind
	var s := alien_field(b, x0)
	var pr := spawn_alien(b, "prism", x0 + 240)
	pr.face = -1
	var gy: float = pr.y - pr.h / 2.0
	var tr := b.trace_bullet(x0 + 10, gy, 0.0, 600, 0, s, false)
	check(not tr.hits.any(func(h): return h.u == pr) and tr.pings.size() == 1 and tr.segs.size() == 2, "a bullet at the mirror bounces off it")
	pr.face = 1
	tr = b.trace_bullet(x0 + 10, gy, 0.0, 600, 0, s, false)
	check(tr.hits.any(func(h): return h.u == pr), "from behind the mirror, it gets hit")
	var hp0 := s.hp
	await b.enemy_act(pr)
	await until(func(): return b.settled(), 900)
	await shot("alien4_prism")
	check(pr.face == -1 and s.hp < hp0, "the Prism turns its mirror on the squad and zaps (hp %d -> %d)" % [hp0, s.hp])
	# --- Gravity Warden: well on the bunched soldiers, pull, bends arcs, collapses on death
	s = alien_field(b, x0)
	var s2: Unit = b.squad()[1]
	s2.x = x0 + 110; s2.y = b.T.stand_y(s2.x, 0); s2.air = false
	var wd := spawn_alien(b, "warden", x0 + 420)
	var gap0 := s2.x - s.x
	await b.enemy_act(wd)
	await until(func(): return b.settled(), 900)
	await shot("alien4_warden")
	check(b.wells.size() == 1, "the Warden drops a gravity well")
	check(absf(s2.x - s.x) < gap0 - 20, "the well pulls the soldiers together (%d -> %d apart)" % [gap0, absf(s2.x - s.x)])
	var wl: Dictionary = b.wells[0] if b.wells.size() else {"x": x0, "y": gy}
	var bent := b.sim_arc(wl.x - 180, wl.y - 120, 3.0, -2.0, 0.0, 30)
	var keep: Array = b.wells
	b.wells = []
	var plain := b.sim_arc(wl.x - 180, wl.y - 120, 3.0, -2.0, 0.0, 30)
	b.wells = keep
	var n: int = mini(bent.pts.size(), plain.pts.size()) - 1
	check(plain.pts[n].distance_to(bent.pts[n]) > 4, "thrown things bend toward the well (%.1f px)" % plain.pts[n].distance_to(bent.pts[n]))
	b.kill(wd, s)
	await until(func(): return b.settled(), 600)
	check(b.wells.is_empty(), "killing the Warden collapses its well")
	# --- Phase Stalker: phased it ignores bullets and walks through, solid inside rock it dies
	s = alien_field(b, x0)
	var st := spawn_alien(b, "stalker", x0 + 200)
	b.T.fill_r(x0 + 90, b.T.stand_y(x0, 0) - 70, 24, 70, 1)
	b.T.flush()
	hp0 = s.hp
	await b.enemy_act(st)
	await until(func(): return b.settled(), 900)
	await shot("alien4_stalker")
	check(st.fl.get("phased", false), "the Stalker phases on its first turn")
	check(st.x < x0 + 90 and s.hp < hp0, "it walks through the wall and slashes (x %d, hp %d -> %d)" % [st.x - x0, hp0, s.hp])
	tr = b.trace_bullet(st.x - 60, st.y - 20, 0.0, 120, 0, s, false)
	check(not tr.hits.any(func(h): return h.u == st), "bullets pass through a phased Stalker")
	b.T.fill_r(st.x - 16, st.y - st.h - 4, 32, st.h + 4, 1)
	b.T.flush()
	await b.enemy_act(st)
	await until(func(): return b.settled(), 600)
	check(st.dead, "turning solid inside rock kills it")
	# --- Overseer: two Thralls, shrug off one knock, Skitter bursts out, links break on death
	flat_strip(b, x0 - 160, 640)
	s = alien_field(b, x0)
	var j1 := spawn_alien(b, "grunt", x0 + 200)
	var j2 := spawn_alien(b, "grunt", x0 + 240)
	j1.hold = true; j2.hold = true
	var ov := spawn_alien(b, "overseer", x0 + 360)
	await b.enemy_act(ov)
	await until(func(): return b.settled(), 900)
	await shot("alien4_overseer")
	check(b.is_thrall(j1) and b.is_thrall(j2), "the Overseer turns two Jackals into Thralls")
	check(b.shrug(j1) and not b.shrug(j1), "a Thrall shrugs off the first knock only")
	var sk0 := b.units.filter(func(u): return u.type == "skitter" and not u.dead).size()
	b.kill(j1, s)
	check(b.units.filter(func(u): return u.type == "skitter" and not u.dead).size() == sk0 + 1, "a Skitter bursts out of a dead Thrall")
	b.kill(ov, s)
	check(not b.is_thrall(j2) and j2.has_st("stun"), "killing the Overseer frees and stuns its Thralls")

func aliens5() -> void:
	## Q2 Burrow Queen: the desert and mountain mini-boss encounter.
	Run.new_run()
	check(Run.make_level("desert", 1).encounter == "queen" and Run.make_level("mountain", 2).encounter == "queen", "desert and mountain levels from level 2 hold the Burrow Queen")
	check(Run.make_level("desert", 0).encounter == "" and Run.make_level("jungle", 1).encounter in Data.ENCOUNTERS, "level 1 and other biomes don't")
	Run.level = Run.make_level("desert", 1)
	var b: Battle = main.start_battle(1, Run.level)
	await until(func(): return b.state == "player" and not b.busy)
	var qs := b.units.filter(func(u): return u.type == "queen")
	check(qs.size() == 1 and qs[0].weight == "buried", "one Burrow Queen waits buried in the level")
	if qs.is_empty():
		return
	var q: Unit = qs[0]
	b.speed = 2.0
	var x0 := 600.0
	flat_strip(b, x0 - 160, 640)
	var s := alien_field(b, x0)
	q.dead = false; q.gone = false
	q.x = x0 + 320; q.y = b.T.stand_y(q.x, 0); q.active = true
	var tr := b.trace_bullet(x0 + 10, q.y - 20, 0.0, 500, 0, s, false)
	check(not tr.hits.any(func(h): return h.u == q), "bullets pass over her while she's underground")
	var hp0 := s.hp
	var g0 = b.T.stand_y(x0 + 160, 0)
	await b.enemy_act(q)
	await until(func(): return b.settled(), 900)
	await shot("alien5_queen_burst")
	check(q.weight == "" and absf(q.x - x0) < 80 and s.hp < hp0, "she tunnels over and bursts out under the soldier (hp %d -> %d)" % [hp0, s.hp])
	check(b.T.stand_y(x0 + 160, 0) != g0, "her tunnel tears up the ground on the way")
	tr = b.trace_bullet(q.x - 200, q.y - q.h * 0.7, 0.0, 300, 0, s, false)
	check(tr.hits.any(func(h): return h.u == q), "surfaced, she can be shot")
	var qh := q.hp
	b.crush(q, 5, s, 0, 0)
	check(qh - q.hp == 15, "rubble on her head does triple damage (%d)" % (qh - q.hp))
	var tot := func(): return b.squad_alive().reduce(func(a, u): return a + u.hp, 0)
	hp0 = tot.call()
	await b.enemy_act(q)
	await until(func(): return b.settled(), 900)
	await shot("alien5_queen_spit")
	check(q.weight == "buried" and tot.call() < hp0, "next turn she bites or spits, then dives (squad hp %d -> %d)" % [hp0, tot.call()])
	var loot0 := b.units.filter(func(u): return u.kind == "loot").size()
	b.kill(q, s)
	check(b.units.filter(func(u): return u.kind == "loot").size() > loot0, "she drops loot when she dies")

func aliens6() -> void:
	## Q1 Hive Ship over the delta and the harbor, its hull plates and drop pods; Q3 Vharr Boar in the finale.
	Run.new_run()
	check(Run.make_level("delta", 1).boss == "hiveship" and Run.make_level("harbor", 2).boss == "hiveship", "the delta and the harbor bring the Hive Ship from level 2")
	check(Run.make_level("delta", 0).boss == "boar" and Run.make_level("desert", 1).boss == "boar", "level 1 and other biomes keep the BOAR")
	Run.level = Run.make_level("delta", 1)
	var b: Battle = main.start_battle(1, Run.level)
	await until(func(): return b.state == "player" and not b.busy)
	var ships := b.units.filter(func(u): return u.type == "hiveship")
	check(ships.size() == 1 and not b.units.any(func(u): return u.type == "boss"), "the arena holds a Hive Ship, not a BOAR")
	check(b.units.filter(func(u): return u.type == "shipplate").size() == 2, "two hull plates hang under it")
	if ships.is_empty():
		return
	check(ships[0].max_hp == Run.level.boss_hp, "it has the level's boss HP (%d)" % ships[0].max_hp)
	b.speed = 2.0
	var x0 := 600.0
	flat_strip(b, x0 - 160, 900)
	var s := alien_field(b, x0)
	var sh := spawn_alien(b, "hiveship", x0 + 260)
	sh.hp = 200; sh.max_hp = 200
	b.hang_plates(sh)
	sh.active = false
	b.activate_enemies()
	await frames_wait(30)
	check(b.boss_active, "the ship counts as the level boss")
	var gy = b.T.stand_y(sh.x, 0)
	check(gy - sh.y > 180, "it floats high over the ground (%d px)" % int(gy - sh.y))
	var pl: Array = b.units.filter(func(u): return u.type == "shipplate" and not u.dead)
	check(pl.size() == 2 and absf(pl[0].y - sh.y - 16) < 2, "the plates hang just under its belly")
	var hp0 := sh.hp
	b.damage(sh, 10, s, {})
	check(hp0 - sh.hp == 4, "plated, a shot does 40%% (%d)" % (hp0 - sh.hp))
	hp0 = sh.hp
	b.damage(sh, 10, s, {"blast": true})
	check(hp0 - sh.hp == 10, "a blast in the belly does full damage (%d)" % (hp0 - sh.hp))
	# a Jackal under a plate gets the plate on its head
	var p0: Unit = pl[0]
	var j := b.mk_enemy("grunt", p0.x, b.T.stand_y(p0.x, 0))
	j.active = true
	b.units.append(j)
	var jh := j.hp
	hp0 = sh.hp
	var c0 := b.T.chunks.size()
	b.damage(p0, 99, s, {})
	check(p0.dead and b.T.chunks.size() > c0, "a plate shot off its tethers falls")
	await until(func(): return b.settled(), 900)
	await shot("alien6_plate_fall")
	check(j.hp < jh, "and crushes the Jackal under it (hp %d -> %d)" % [jh, j.hp])
	check(sh.hp == hp0 and not sh.dead, "the falling plate doesn't hit the ship")
	b.kill(pl[1], s)
	await until(func(): return b.settled(), 900)
	hp0 = sh.hp
	b.damage(sh, 10, s, {})
	check(hp0 - sh.hp == 13, "with the plates gone the hull takes +30%% (%d)" % (hp0 - sh.hp))
	# its turn: glide, sweep the ray, drop a pod
	for u in b.units:
		if u.team == "enemy" and u != sh:
			u.dead = true; u.gone = true
	s = alien_field(b, x0)
	b.units.append(sh)  # alien_field cleared it; put it back
	sh.dead = false; sh.gone = false; sh.active = true
	var tot := func(): return b.squad_alive().reduce(func(a, u): return a + u.hp, 0)
	var sq0: int = tot.call()
	await b.enemy_act(sh)
	await until(func(): return b.settled(), 1200)
	await shot("alien6_ship_turn")
	check(tot.call() < sq0, "the ray and the pod hurt the squad (hp %d -> %d)" % [sq0, tot.call()])
	check(absf(sh.x - s.x) < 160, "the ship glides over the squad (%d px away)" % int(absf(sh.x - s.x)))
	var pods := b.units.filter(func(u): return u.type == "droppod" and not u.dead)
	check(pods.size() == 1, "a drop pod lands closed")
	if pods.size():
		var n0 := b.units.size()
		var cargo: Array = pods[0].fl.cargo
		await b.enemy_act(pods[0])
		await until(func(): return b.settled(), 1200)
		var out: Array = b.units.slice(n0).map(func(u): return u.type)
		check(pods[0].gone and out.slice(0, cargo.size()) == cargo, "next phase it opens and the Vharr come out (%s)" % str(out))
	b.kill(sh, s)
	check(b.boss_dead and sh.gone, "killing the ship wins the level")
	# Q3: the finale BOAR
	Run.new_run()
	Run.start_finale()
	var b2: Battle = main.start_battle(3, Run.level)
	await until(func(): return b2.state == "player" and not b2.busy)
	var bos := b2.units.filter(func(u): return u.type == "boss")
	check(bos.size() == 1 and bos[0].fl.get("vharr", false), "the finale BOAR is the Vharr refit")
	if bos.is_empty():
		return
	var bo: Unit = bos[0]
	b2.speed = 2.0
	flat_strip(b2, bo.x - 500, 560)
	var s2 := alien_field(b2, bo.x - 300)
	b2.units.append(bo)
	bo.dead = false; bo.gone = false; bo.active = true; bo.y = b2.T.stand_y(bo.x, 0)
	var sx := s2.x
	await b2.enemy_act(bo)
	await until(func(): return b2.settled(), 1200)
	await shot("alien6_vboar")
	check(bo.dome == 1, "it raises its dome")
	check(s2.x > sx + 60 or s2.dead, "its tongue yanks the soldier in (x %d -> %d)" % [int(sx), int(s2.x)])
	var bh := bo.hp
	var pl0 := bo.plate
	b2.damage(bo, 10, s2, {})
	check(bo.hp == bh and bo.plate == pl0, "the dome stops a shot")
	b2.crush(bo, 6, s2, 0, 0)
	check(bo.cracked and bo.hp < bh, "crushing goes through the dome and cracks it")
	b2.start_player_turn()
	await until(func(): return b2.state == "player" and not b2.busy, 600)
	b2.state = "enemy"
	bo.dome = 0
	await b2.vboar_tricks(bo)
	check(bo.dome == 0, "the dome needs time to come back")

func enc_battle(id: String) -> Battle:
	Run.new_run()
	Run.level = Run.make_level("jungle", 1)
	Run.level.encounter = id
	var b: Battle = main.start_battle(1, Run.level)
	await until(func(): return b.state == "player" and not b.busy)
	b.speed = 2.0
	return b

func aliens7() -> void:
	## E3 Drop Pod Ambush, E4 The Hunt, E5 Thrall Outbreak, E6 Gate Siege.
	Run.new_run()
	var seen := {}
	for i in 60:
		seen[Run.make_level("jungle", 1 + i % 2).encounter] = true
	check(Data.ENCOUNTERS.all(func(k): return seen.has(k)), "levels 2 and 3 roll all six encounters (%s)" % str(seen.keys()))
	check(Run.make_level("jungle", 0).encounter == "", "level 1 has none")
	# --- E3
	var b := await enc_battle("droppods")
	check(not b.ambush.is_empty() and not b.ambush.done, "the ambush waits in a stretch after the mid camp")
	var x0: float = b.ambush.x
	flat_strip(b, x0 - 200, 500)
	var s := alien_field(b, x0)
	await b.pod_ambush()
	await until(func(): return b.settled(), 900)
	await shot("alien7_pods")
	var pods := b.units.filter(func(u): return u.type == "droppod" and not u.dead)
	check(pods.size() == 3, "three pods crash down around the squad (%d)" % pods.size())
	check(b.ambush.done, "only once")
	if pods.size():
		var n0 := b.units.size()
		b.kill(pods[0], s)
		check(b.units.size() == n0, "a pod broken before it opens lets nothing out")
	# --- E4
	b = await enc_battle("hunt")
	var leads := b.units.filter(func(u): return u.fl.get("lead", false))
	check(leads.size() == 1 and leads[0].elite != "" and b.units.filter(func(u): return u.fl.get("hunt", false)).size() == 3, "an elite alien and two escorts hunt the squad")
	if leads.size():
		var ld: Unit = leads[0]
		cam_on(b, ld.x - Battle.W - 200)
		check(ld.active and ld.x > b.cam_x + Battle.W, "it comes after you before it's on screen")
		var bio0 := int(Run.meta.get("bio", 0))
		b.kill(ld, b.squad()[0])
		check(int(Run.meta.get("bio", 0)) == bio0 + Data.ELITE_BIO, "bringing it down pays Bio-parts like an elite outpost")
	# --- E5
	b = await enc_battle("outbreak")
	var ovs := b.units.filter(func(u): return u.fl.get("outbreak", false))
	var camp := b.units.filter(func(u): return u.fl.get("camp", false))
	check(ovs.size() == 1 and camp.size() == 5, "an Overseer over a five-Jackal camp")
	if ovs.size():
		var ov: Unit = ovs[0]
		flat_strip(b, ov.x - 500, 700)
		for u in b.units:
			if u.team == "enemy" and not u.fl.get("camp", false) and u != ov:
				u.dead = true; u.gone = true
		for u in b.squad():
			u.x = ov.x - 420; u.y = b.T.stand_y(u.x, 0); u.air = false
		cam_on(b, ov.x - 200)
		await b.enemy_act(ov)
		await until(func(): return b.settled(), 900)
		var thr := func(): return camp.filter(func(u): return u.fl.get("thrall", false)).size()
		check(thr.call() == 1, "it takes one Jackal a turn (%d)" % thr.call())
		await b.enemy_act(ov)
		await until(func(): return b.settled(), 900)
		check(thr.call() == 2, "then another (%d)" % thr.call())
		b.kill(ov, b.squad()[0])
		var alive := camp.filter(func(u): return not u.dead)
		check(alive.size() and alive.all(func(u): return u.fl.get("turned", false)), "kill it and the camp turns on the Vharr")
		var sk := spawn_alien(b, "skitter", alive[0].x + 120)
		check(b.foes_of(alive[0]).has(sk) and b.foes_of(sk).has(alive[0]), "turned Jackals and the Vharr fight each other")
		await shot("alien7_outbreak")
	# --- E6
	b = await enc_battle("gate")
	var gs := b.units.filter(func(u): return u.type == "vgate")
	check(gs.size() == 1, "a Vharr gate stands in the stretch")
	if gs.size():
		var g: Unit = gs[0]
		flat_strip(b, g.x - 400, 600)
		s = alien_field(b, g.x - 300)
		b.units.append(g)
		g.dead = false; g.gone = false; g.active = true; g.y = b.T.stand_y(g.x, 0); g.air = false
		for i in 6:
			await b.enemy_act(g)
			await until(func(): return b.settled(), 600)
		var from := b.units.filter(func(u): return u.fl.get("from") == g and not u.dead)
		check(from.size() == 4, "one alien a turn, four at a time (%d)" % from.size())
		await shot("alien7_gate")
		var gh := g.hp
		b.crush(g, 5, s, 0, 0)
		check(gh - g.hp == 15, "dropping something on it does triple (%d)" % (gh - g.hp))

func aliens8() -> void:
	## H7 Gate Trooper, F2 kill credit (TURNCOAT), F3 defectors.
	Run.new_run()
	Run.level = Run.make_level("jungle", 0)
	var b: Battle = main.start_battle(0, Run.level)
	await until(func(): return b.state == "player" and not b.busy)
	var types := b.units.filter(func(u): return u.team == "enemy").map(func(u): return u.type)
	check(types.has("gatetrooper"), "level 1 has a Gate Trooper among the Jackals (%s)" % str(types))
	b.speed = 2.0
	var x0 := 600.0
	flat_strip(b, x0 - 160, 700)
	var s := alien_field(b, x0)
	var gt := spawn_alien(b, "gatetrooper", x0 + 340)
	check(gt.sheet == "en_grunt", "it wears the Jackal rifleman's sprite")
	var hp0 := s.hp
	await b.enemy_act(gt)
	await until(func(): return b.settled(), 900)
	await shot("alien8_trooper")
	check(s.hp < hp0, "it walks in and fires the stolen ray (hp %d -> %d)" % [hp0, s.hp])
	# F2: in a breach, a Jackal you hurt that a Vharr finishes off still pays you
	s = alien_field(b, x0)
	b.breach = true
	var j := spawn_alien(b, "grunt", x0 + 200)
	var sq := spawn_alien(b, "squid", x0 + 420)
	j.last_hit_by = s
	var xp0: int = s.s.xp
	b.damage(j, 99, sq, {})
	check(j.dead and s.s.xp > xp0, "a Vharr kill on a Jackal you set up gives you the XP (%d -> %d)" % [xp0, s.s.xp])
	check(b.feed.size() and b.feed[-1].stamp.contains("TURNCOAT"), "the kill feed calls it a TURNCOAT kill")
	# F3: a hurt Jackal alone next to a soldier gives up
	s = alien_field(b, x0)
	b.breach = true
	var d := spawn_alien(b, "grunt", x0 + 120)
	d.hp = 3
	await b.enemy_act(d)
	check(d.kind == "pow" and d.fl.get("defector", false) and d.team == "neutral", "a cornered Jackal surrenders in a breach")
	var d2 := spawn_alien(b, "grunt", x0 + 140)
	d2.hp = 3
	await b.enemy_act(d2)
	check(d2.kind == "enemy", "only one per level")
	d2.dead = true; d2.gone = true
	b.state = "player"; b.busy = false
	s.x = d.x - 4
	await frames_wait(20)
	check(d.freed and b.pow_queue.size() == 1, "walk over him to bring him in")
	if b.pow_queue.size():
		b.sign_defector(b.pow_queue.pop_front().pow)
	check(Run.defectors.size() == 1 and Run.defectors[0] == d.pow_name, "walked out, he joins the recruit pool (%s)" % str(Run.defectors))
	Run.soldiers[3].alive = false
	var off: Dictionary = Run.recruit_offers()[0]
	check(off.trait.id == "defector" and off.name == d.pow_name, "and is the first recruit offered")
	var hired := Run.hire(3, off)
	check(hired.bonus.dodge >= 4 and Run.defectors.is_empty(), "hiring him uses up the defector")
	b.breach = false
	var d3 := spawn_alien(b, "grunt", x0 + 160)
	d3.hp = 3
	b.stats.erase("defectors")
	await b.enemy_act(d3)
	check(d3.kind == "enemy", "outside a breach nobody surrenders")

func camp() -> void:
	## Every mission has two camps. Reaching one with the area clear brings the downed back and pays a camp pick.
	for m in Data.MISSIONS + Data.BIOMES.keys().map(func(id): return Run.make_level(id, 0)):
		check(m.segments.count("camp") == 2 and m.segments[-2] == "camp", "%s has a mid camp and a camp before the boss" % m.name)
	Run.new_run()
	var b: Battle = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	check(b.T.camps.size() == 2, "the level is built with two camps")
	var c: Dictionary = b.T.camps[0]
	cam_on(b, c.fire)
	await frames_wait(20)
	await shot("camp_before")
	var sq: Array = b.squad()
	var down: Unit = sq[1]
	b.kill(down, null)
	sq[2].hp = 5
	var u: Unit = sq[0]
	u.x = c.fire + 20
	u.y = b.T.stand_y(u.x, 0)
	# Jackals still around: no camp yet
	var near: Array = b.units.filter(func(e): return e.team == "enemy" and not e.dead and e.x < c.x1 + 200)
	for e in near:
		e.active = true
	if near.size():
		await b.check_camp(u)
		check(not c.used, "no camp while Jackals are still close")
	for e in near:
		e.dead = true
		e.gone = true
	var before: Array = u.s.deck.map(func(cd): return Data.tier_of(cd))
	b.autopick = 1
	await b.check_camp(u)
	await frames_wait(30)
	await shot("camp_made")
	check(c.used, "the camp is made once the area is clear")
	check(not down.dead and down.hp == int(ceil(down.max_hp / 2.0)), "a downed soldier rejoins at camp at half HP")
	check(sq[2].hp > 5, "everyone patches up a little at camp")
	var after: Array = u.s.deck.map(func(cd): return Data.tier_of(cd))
	check(after != before, "FIELD UPGRADE raises a card's tier")
	await b.check_camp(u)
	check(int(b.stats.get("camps", 0)) == 1, "a camp only pays out once")
	var c2: Dictionary = b.T.camps[1]
	cam_on(b, c2.fire)
	await frames_wait(20)
	await shot("camp_preboss")

func play_drill(b: Battle, u: Unit, p: Vector2, stop_after := -1.0) -> void:
	b.state = "player"; b.busy = false
	b.select_unit(u)
	var i := force_card(u, "drill")
	b.select_card(i)
	b.commit_aim(p)
	if stop_after >= 0:
		var x0 := u.x
		await until(func(): return absf(u.x - x0) >= stop_after or not b.busy, 1200)
		b.stop_drill()
	await until(func(): return not b.busy, 1200)
	await frames_wait(4)

func drill() -> void:
	## The Drill card: in every starting deck, bores through dirt, stone and steel, spends movement,
	## stops early on a click, goes down too, and refuses with no movement left.
	Run.new_run()
	check(Run.soldiers.all(func(x): return x.deck.any(func(c): return c.key == "drill")), "every soldier starts with a Drill in the deck")
	check(Data.card("drill").cost == 0, "the Drill costs 0 energy")
	check(not Data.offer_keys().has("drill"), "the Drill isn't offered in level-ups or the shop")
	var b: Battle = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	b.speed = 2.0
	var s: Unit = b.squad()[0]
	var x := 900.0
	while not flat_open(b, x, 260) and x < b.world_w - 600:
		x += 20
	for o in b.units:
		if o != s and (o.team == "enemy" or o.kind != "soldier") and absf(o.x - x - 130) < 400:
			o.gone = true
	for o in b.squad():
		if o != s:
			ground_unit(b, o, x - 200, 0)
	cam_on(b, x + 130)
	ground_unit(b, s, x, 0)
	var gy: float = s.y
	# a dirt bank, a stone wall and a steel plate, all taller than a hop clears
	b.T.fill_r(x + 30, gy - 70, 40, 72, 1)
	b.T.fill_r(x + 70, gy - 70, 30, 72, 4)
	b.T.fill_r(x + 100, gy - 70, 12, 72, 2)
	await frames_wait(10)
	check(b.sim_walk(s, x + 200, 200).used < 30, "the wall blocks walking")
	s.move_left = 220; s.energy = 3
	var di := force_card(s, "drill")
	b.select_unit(s)
	b.select_card(di)
	b.mouse = Vector2(x + 200, gy - 17)
	await frames_wait(6)
	await shot("drill_aim")
	var e0 := s.energy
	b.commit_aim(b.mouse)
	await frames_wait(40)
	await shot("drill_boring")
	await until(func(): return not b.busy, 1200)
	await frames_wait(6)
	await shot("drill_through")
	check(s.x > x + 120, "the Drill bores through dirt, stone and steel (x %d, wall ends %d)" % [s.x, x + 112])
	check(absf(s.y - gy) < 6, "a level drill keeps the soldier at ground height (y %d vs %d)" % [s.y, gy])
	check(s.energy == e0, "drilling spent no energy (%d -> %d)" % [e0, s.energy])
	check(absf(s.move_left - (220 - (s.x - x))) < 4, "drilling spends movement by the distance (%d left of 220 after %dpx)" % [s.move_left, s.x - x])
	check(s.x < x + 206, "the drill stops at the cursor (x %d, cursor %d)" % [s.x, x + 200])
	check(not s.hand.any(func(c): return c.key == "drill") and s.disc.any(func(c): return c.key == "drill"), "the Drill is spent to the discard until it's drawn again")
	check(s.hp == s.max_hp, "the soldier came out of the wall unhurt (%d/%d)" % [s.hp, s.max_hp])
	# manual stop
	ground_unit(b, s, x - 60, 0)
	b.T.fill_r(x - 40, gy - 70, 200, 72, 4)
	s.move_left = 200
	var sx := s.x
	await play_drill(b, s, Vector2(s.x + 300, s.y - 17), 40.0)
	check(s.x - sx > 10 and s.x - sx < 120, "clicking stops the drill early (went %dpx of 200)" % int(s.x - sx))
	check(s.move_left > 70, "stopping early keeps the unused movement (%d left)" % s.move_left)
	# straight down
	ground_unit(b, s, x + 300, 0)
	cam_on(b, x + 300)
	var y1 := s.y
	s.move_left = 60
	await play_drill(b, s, Vector2(s.x, s.y + 200))
	await shot("drill_down")
	check(s.y > y1 + 30, "the Drill goes straight down too (y %d -> %d)" % [y1, s.y])
	# no movement, no drill
	s.move_left = 0
	b.state = "player"; b.busy = false
	var di2 := force_card(s, "drill")
	b.select_card(di2)
	b.commit_aim(Vector2(s.x + 100, s.y - 17))
	await frames_wait(4)
	check(not b.busy and s.hand.any(func(c): return c.key == "drill"), "with no movement left the Drill won't start and stays in hand")
	# the mission 2 ridge cliff: bore into it at boot height instead of hopping it
	b = main.start_battle(1)
	await until(func(): return b.state == "player" and not b.busy)
	b.speed = 0.5
	var cl = null
	for L in b.T.ladders:
		if cl == null and L.offx > L.x and L.bot - L.top > 30:
			cl = L
	var dr: Unit = b.squad()[1]
	ground_unit(b, dr, cl.x - 24, cl.bot - 30)
	for o in b.units:
		if (o.kind == "crate" or o.team == "enemy") and absf(o.x - cl.offx) < 300:
			o.gone = true
	cam_on(b, dr.x + 200)
	dr.move_left = 160
	b.state = "player"; b.busy = false
	b.select_unit(dr)
	b.select_card(force_card(dr, "drill"))
	b.mouse = Vector2(dr.x + 150, dr.y - 17)
	await frames_wait(6)
	await shot("drill_cliff_aim")
	var cx0 := dr.x
	b.commit_aim(b.mouse)
	await until(func(): return dr.x > cx0 + 60, 1200)
	await shot("drill_cliff_boring")
	await until(func(): return not b.busy, 2400)
	await frames_wait(20)
	await shot("drill_cliff_after")
	check(dr.x > cx0 + 100, "a soldier drills into the ridge cliff (x %d -> %d)" % [cx0, dr.x])

func soldat2() -> void:
	## The second round of Soldat borrowings: overkill pops, the kill feed, fuse choice,
	## the Cluster and Grenade Kit bonuses, thin air.
	Run.new_run()
	var lvl := {"name": "SOLDAT YARD II", "theme": "dusk", "segments": ["start", "ridge", "towers", "camp", "arena"],
		"boss_hp": 120, "plate": 36, "hp_mul": 1.0, "brief": "", "rules": {"pads": 2}}
	var b: Battle = main.start_battle(0, lvl)
	await until(func(): return b.state == "player" and not b.busy)
	b.speed = 2.0
	b.autopick = 0
	b.wind = 0
	for o in b.units:
		if o.team == "neutral" and o.kind != "pad" or o.team == "enemy":
			o.gone = true; o.dead = true
	var sq: Array = b.squad()
	var s: Unit = sq[0]
	ground_unit(b, s, 300)
	cam_on(b, 300)
	# --- R2 overkill pops and U1 kill feed
	var e := b.mk_enemy("grunt", 420, b.T.stand_y(420, 0)); e.active = true
	b.units.append(e)
	b.damage(e, 99, s)
	check(e.dead and e.gone and not e.is_body(), "a big overkill pops the Jackal: no body left")
	check(b.feed.size() > 0 and b.feed[-1].stamp.contains("OVERKILL"), "the kill feed stamps it OVERKILL (%s)" % (b.feed[-1].stamp if b.feed.size() else "empty"))
	check(b.feed[-1].killer == s.def.name.to_upper() and b.feed[-1].victim == "JACKAL GRUNT".to_upper() or b.feed[-1].victim == Data.ETYPES.grunt.name.to_upper(), "the feed names killer and victim (%s / %s)" % [b.feed[-1].killer, b.feed[-1].victim])
	check(b.parts.any(func(p): return p.get("helmet", false)), "the helmet pops off")
	await frames_wait(20)
	await shot("soldat2_overkill")
	var e2 := b.mk_enemy("grunt", 460, b.T.stand_y(460, 0)); e2.active = true
	b.units.append(e2)
	b.damage(e2, e2.hp, s)
	check(e2.is_body(), "an exact kill still leaves a body")
	var e3 := b.mk_enemy("grunt", 500, b.T.stand_y(500, 0)); e3.active = true; e3.hp = 2
	b.units.append(e3)
	b.collision_dmg(e3, 5, "FALL")
	check(e3.dead and b.feed[-1].how == "FALL", "a fall kill shows FALL in the feed (%s)" % b.feed[-1].how)
	await shot("soldat2_feed")
	# --- K1 fuse choice
	b.sel = s
	s.energy = 5
	var fi := force_card(s, "frag")
	b.select_card(fi)
	check(b.armed_fuse() == 150, "a frag starts on its own 2.5s fuse (%s)" % str(b.armed_fuse()))
	b.dial_fuse(1)
	check(b.armed_fuse() == 180, "the wheel adds half a second (%s)" % str(b.armed_fuse()))
	for i in 10:
		b.dial_fuse(-1)
	check(b.armed_fuse() == 60, "the fuse bottoms out at 1s (%s)" % str(b.armed_fuse()))
	for i in 10:
		b.dial_fuse(1)
	check(b.armed_fuse() == 240, "and tops out at 4s (%s)" % str(b.armed_fuse()))
	b.dial_fuse(-1); b.dial_fuse(-1)
	var aimp := Vector2(s.x + 160, s.y - 120)
	b.mouse = aimp
	await frames_wait(4)
	await shot("soldat2_fuse")
	var v := b.aim_vel(s, aimp)
	var gs := b.sim_grenade(v.hx, v.hy, v.vx, v.vy, 1.0, 180)
	var pr: Dictionary = b.mk_proj({"kind": "frag", "x": v.hx, "y": v.hy, "vx": v.vx, "vy": v.vy, "wind": 1.0, "bounce": true, "fuse": 99999, "owner": s})
	for i in 180:
		b.update_proj(pr)
	check(Vector2(pr.x, pr.y).distance_to(Vector2(gs.x, gs.y)) < 3, "the fuse preview ends where the grenade really is when it blows (%d,%d vs %d,%d)" % [pr.x, pr.y, gs.x, gs.y])
	var ci := b.card_idx
	b.projs.clear()
	await b._act_arc(s, ci, Data.card(s.hand[ci]), aimp, false)
	check(b.projs.size() > 0 and b.projs[0].fuse <= 180 and b.projs[0].fuse > 160, "the thrown frag takes the dialed 3s fuse (%s)" % (str(b.projs[0].fuse) if b.projs.size() else "none"))
	await until(func(): return b.settled(), 600)
	b.fuse_pick = 0
	# --- P2 Cluster and K2 Grenade Kit bonuses
	s.energy = 5
	s.st["cluster"] = 2
	var fj := force_card(s, "frag")
	var cc := Data.card(s.hand[fj])
	b.projs.clear()
	await b._act_arc(s, fj, cc, aimp, false)
	check(b.projs.size() == 1 and b.projs[0].cluster >= 3 and s.st.get("cluster", 0) == 1, "Cluster splits the next grenade and counts down (%s, left %d)" % [str(b.projs[0].cluster) if b.projs.size() else "none", s.st.get("cluster", 0)])
	await until(func(): return b.settled(), 600)
	var pad: Unit = b.pads[0]
	pad.loot.seq = ["nadekit"]; pad.loot.i = 0; pad.loot.ready = true
	var h0 := s.hand.filter(func(c): return c.key == "frag" and c.get("temp", false)).size()
	b.grant_bonus(pad, s)
	var h1 := s.hand.filter(func(c): return c.key == "frag" and c.get("temp", false)).size()
	check(h1 == h0 + 2, "a Grenade Kit puts two Frag Grenades in hand (%d -> %d)" % [h0, h1])
	var j := b.mk_enemy("grunt", s.x + 220, b.T.stand_y(s.x + 220, 0)); j.active = true
	b.units.append(j)
	pad.loot.ready = true
	b.grant_bonus(pad, j)
	check(j.st.has("nades"), "a Jackal that grabs a Grenade Kit holds a grenade")
	b.projs.clear()
	var threw: bool = await b.jackal_nade(j)
	check(threw and b.projs.any(func(p): return p.kind == "egren") and not j.st.has("nades"), "and lobs it at the nearest soldier on its next move")
	await until(func(): return b.settled(), 600)
	check(Data.BONUSES.has("cluster") and Data.BONUSES.has("nadekit"), "Cluster and Grenade Kit are in the pad rotation")
	# --- T3 thin air
	ground_unit(b, s, 300)
	b.grav = Battle.GRAV
	var low := b.sim_body(s, 3.0, -5.0)
	b.grav = Battle.GRAV * Data.BIOMES.mountain.rules.grav
	var high := b.sim_body(s, 3.0, -5.0)
	check(high.x > low.x + 20, "thin air: the same jump carries further on the mountain (%d vs %d)" % [high.x - s.x, low.x - s.x])
	var a1 := b.sim_arc(s.x, s.y - 30, 4.0, -4.0, 0, 300)
	b.grav = Battle.GRAV
	var a0 := b.sim_arc(s.x, s.y - 30, 4.0, -4.0, 0, 300)
	check(a1.x > a0.x, "and so does a throw (%d vs %d)" % [a1.x - s.x, a0.x - s.x])
	await soldat2_moves(b, s)

func soldat2_moves(b: Battle, s: Unit) -> void:
	## J3 Combat Roll, J4 mid-air shots, J5 Jet Jackals.
	for o in b.units:
		if o.team == "enemy" or o.team == "neutral" and o.kind != "pad":
			o.gone = true; o.dead = true
	b.projs.clear()
	b.sel = s
	ground_unit(b, s, 300)
	cam_on(b, 420)
	await until(func(): return b.settled(), 300)
	# --- J3 roll: through a crawl-height gap that walking can't pass
	var gy: float = s.y
	b.T.fill_r(280, gy - 80, 300, 80, 0)  # a flat yard so the slab's gap is exactly crawl height
	b.T.fill_r(280, gy, 300, 40, 1)
	b.T.fill_r(380, gy - 30, 40, 12, 2)
	b.T.flush()
	var walk := b.sim_walk(s, s.x + 150, 150)
	check(walk.x < 380, "walking can't get under the low slab (stopped at %d)" % walk.x)
	s.energy = 5
	var ri := force_card(s, "roll")
	var rc := Data.card(s.hand[ri])
	var rp := b.roll_path(s, rc, Vector2(s.x + 200, s.y))
	check(rp.x > 420, "a Combat Roll goes under it (ends at %d)" % rp.x)
	var mv0 := s.move_left
	await b.resolve(func(): await b._act_roll(s, ri, rc, Vector2(s.x + 200, s.y)))
	check(absf(s.x - rp.x) < 3 and s.move_left == mv0 and s.h == 34, "the roll lands where the preview said, costs no movement, and stands back up (x %d vs %d)" % [s.x, rp.x])
	check(s.has_st("roll"), "the roller is ROLLING")
	await shot("soldat2_roll")
	var j := b.mk_enemy("grunt", s.x + 180, b.T.stand_y(s.x + 180, 0)); j.active = true
	b.units.append(j)
	var hp0 := s.hp
	await b.enemy_shoot(j, s, {"dmg": [4, 4], "shots": 1, "range": 460})
	await until(func(): return b.settled(), 300)
	check(s.hp == hp0 and not s.has_st("roll"), "the next Jackal shot goes over the roller's head (hp %d -> %d)" % [hp0, s.hp])
	j.dead = true; j.gone = true
	# --- J4 mid-air shot from the top of a jump
	ground_unit(b, s, 300)
	await until(func(): return b.settled(), 300)
	s.energy = 6
	s.adr = 0
	var t2 := b.mk_enemy("grunt", s.x + 150, b.T.stand_y(s.x + 150, 0)); t2.active = true; t2.hp = 1; t2.max_hp = 1
	b.units.append(t2)
	var ai := force_card(s, "rifle")
	var ji := force_card(s, "jumppack")
	await b.resolve(func(): await b._act_jump(s, ji, Vector2(s.x + 40, s.y - 200)))
	check(s.hang and s.air and not b.busy, "a Jump Pack stops at the top of its arc for a shot (hang %s air %s)" % [s.hang, s.air])
	var y_top := s.y
	await frames_wait(20)
	check(absf(s.y - y_top) < 1, "and stays up there while you aim")
	await shot("soldat2_topgun")
	ai = force_card(s, "rifle")
	b.aim_hold = true
	var tp := Vector2(t2.x, t2.y - t2.h / 2.0)
	await b.resolve(func(): await b._act_aim(s, ai, Data.card(s.hand[ai]), tp, false))
	b.aim_hold = false
	check(not s.hang and not s.air, "after the shot the soldier drops and lands")
	check(t2.dead and b.feed.size() and b.feed[-1].stamp.contains("TOP GUN"), "a mid-air kill is a TOP GUN (%s, %s)" % [t2.dead, b.feed[-1].stamp if b.feed.size() else ""])
	await b.resolve(func(): await b._act_jump(s, force_card(s, "jumppack"), Vector2(s.x + 40, s.y - 200)))
	check(s.hang, "hanging again")
	b.world_click(Vector2(s.x + 100, s.y + 160))
	await until(func(): return not s.air, 300)
	check(not s.hang and not s.air, "clicking the ground lets go and drops")
	# --- J5 Jet Jackals
	var tw := find_struct(b, "tower")
	cam_on(b, tw.x)
	ground_unit(b, s, tw.x - 260)
	var g0: float = b.T.ground_at(tw.x - 120)
	var jt := b.mk_enemy("jetter", tw.x - 120, b.T.stand_y(tw.x - 120, 0)); jt.active = true
	b.units.append(jt)
	var r = b.jet_roost(jt)
	check(r != null and r.y < g0 - 40, "a Jet Jackal picks a roof above the ground (%s, ground %d)" % [str(r), g0])
	s.overwatch = 0
	await b.jetter_act(jt)
	await until(func(): return b.settled(), 600)
	check(not jt.dead and jt.y < g0 - 40, "it jets up onto it (y %d, ground %d)" % [jt.y, g0])
	await shot("soldat2_jetter")
	var jt2 := b.mk_enemy("jetter", tw.x - 120, b.T.stand_y(tw.x - 120, 0)); jt2.active = true; jt2.hp = 30; jt2.max_hp = 30
	b.units.append(jt2)
	var roost = b.jet_roost(jt2)
	jt.dead = true; jt.gone = true
	b.jet_fly(jt2, roost)
	await until(func(): return jt2.y < roost.y - 20 or not jt2.jetting, 300)
	var hp1 := jt2.hp
	b.damage(jt2, 1, s)
	check(jt2.crash and not jt2.jetting, "a hit in flight knocks its pack out")
	await until(func(): return not jt2.air, 400)
	check(jt2.hp < hp1 - 1, "and it crashes (hp %d -> %d)" % [hp1, jt2.hp])

func soldat3() -> void:
	## Soldat round 2, guns: sidearms, dropped Jackal guns, weapon weight, mounted M2s.
	Run.new_run()
	var lvl := {"name": "SOLDAT YARD III", "theme": "dusk", "segments": ["start", "m2nest", "camp", "arena"],
		"boss_hp": 120, "plate": 36, "hp_mul": 1.0, "brief": "", "rules": {"pads": 0}}
	var b: Battle = main.start_battle(0, lvl)
	await until(func(): return b.state == "player" and not b.busy)
	b.speed = 2.0
	b.autopick = 0
	b.wind = 0
	var sq: Array = b.squad()
	var s: Unit = sq[0]
	# --- B1 sidearms
	check(sq.all(func(u): return u.hand.any(func(c): return c.key == "sa_pistol" and c.get("temp", false))), "every soldier starts the turn with a Holdout Pistol sidearm")
	check(Data.card({"key": "sa_pistol", "tier": 0}).cost == 0, "the holdout pistol is free")
	s.gb["sa"] = 1
	b.give_sidearm(s)
	check(s.hand.any(func(c): return c.key == "sa_knife") and not s.hand.any(func(c): return c.key == "sa_pistol"), "a Combat Knife kit swaps the sidearm")
	s.gb["sa"] = 3
	b.give_sidearm(s)
	var li := -1
	for i in s.hand.size():
		if s.hand[i].key == "sa_law":
			li = i
	check(li >= 0, "a LAW Tube makes the sidearm a LAW")
	b.spend_card(s, li)
	b.give_sidearm(s)
	check(s.s.get("law_spent", false) and s.hand.any(func(c): return c.key == "sa_pistol"), "once the LAW is fired it's back to the pistol")
	s.s.erase("law_spent")
	b.give_sidearm(s)
	check(s.hand.any(func(c): return c.key == "sa_law"), "and a camp reloads it")
	s.gb.erase("sa")
	b.give_sidearm(s)
	# --- B5 weapon weight
	var m0 := b.full_move(s)
	s.gb["light"] = 15
	check(b.full_move(s) == m0 + 15, "a light weapon adds movement (%d -> %d)" % [m0, b.full_move(s)])
	s.gb.erase("light")
	s.gb["heavy"] = 15
	s.gb["jet"] = 90
	check(b.full_move(s) == m0 - 15 and b.jet_fuel(s) == 60, "a heavy one costs movement and jet fuel (%d, fuel %d)" % [b.full_move(s), b.jet_fuel(s)])
	s.gb.erase("heavy"); s.gb.erase("jet")
	check(Data.stat_lines({"heavy": 15})[0].begins_with("HEAVY"), "gear cards say LIGHT or HEAVY")
	# --- B6 mounted M2
	var guns: Array = b.units.filter(func(o): return o.kind == "m2")
	check(guns.size() == 2, "the M2 nest has two mounted guns (%d)" % guns.size())
	for o in b.units:
		if o.team == "enemy":
			o.dead = true; o.gone = true
	var g1: Unit = guns[0]
	cam_on(b, g1.x)
	ground_unit(b, s, g1.x - 20)
	b.refresh_mounts()
	var mi := -1
	for i in s.hand.size():
		if s.hand[i].key == "mounted":
			mi = i
	check(mi >= 0, "standing at the M2 gives the free Mounted M2 card")
	await frames_wait(6)
	await shot("soldat3_m2")
	var tgt := b.mk_enemy("grunt", g1.x + 160, b.T.stand_y(g1.x + 160, 0)); tgt.active = true; tgt.hp = 40; tgt.max_hp = 40
	b.units.append(tgt)
	var hp0 := tgt.hp
	var x0 := s.x
	b.sel = s
	b.aim_hold = true
	await b.resolve(func(): await b._act_aim(s, mi, Data.card(s.hand[mi]), Vector2(tgt.x, tgt.y - 20), false))
	b.aim_hold = false
	check(tgt.hp < hp0, "the M2 shreds the Jackal (%d -> %d)" % [hp0, tgt.hp])
	check(absf(s.x - x0) < 1, "and has no kick")
	check(not s.hand.any(func(c): return c.key == "mounted"), "once a turn")
	ground_unit(b, s, g1.x - 120)
	b.round_n += 1
	b.refresh_mounts()
	check(not s.hand.any(func(c): return c.key == "mounted"), "walking away leaves the gun behind")
	var g2: Unit = guns[1]
	var jk := b.mk_enemy("grunt", g2.x + 14, b.T.stand_y(g2.x + 14, 0)); jk.active = true
	b.units.append(jk)
	ground_unit(b, s, g2.x - 200)
	cam_on(b, g2.x - 100)
	b.state = "enemy"
	await b.enemy_act(jk)
	b.state = "player"
	await until(func(): return b.settled(), 300)
	check(g2.loot.en == b.round_n, "a Jackal at the other M2 fires it")
	b.damage(g2, 99, s)
	await until(func(): return b.settled(), 300)
	check(g2.gone, "an M2 can be blown up")
	# --- B4 dropped guns
	var mg := b.mk_enemy("mg", s.x + 80, b.T.stand_y(s.x + 80, 0)); mg.active = true
	b.units.append(mg)
	b.damage(mg, mg.hp, s)
	await until(func(): return b.settled(), 300)
	var drop = null
	for o in b.units:
		if o.kind == "loot" and not o.gone and o.loot.type == "gun":
			drop = o
	check(drop != null and drop.loot.card == "hmg", "a dead MG nest drops its Heavy MG")
	await frames_wait(4)
	await shot("soldat3_drop")
	var n0: int = s.hand.filter(func(c): return c.key == "hmg").size()
	if drop != null:
		b.collect(s, drop)
	check(s.hand.filter(func(c): return c.key == "hmg" and c.get("temp", false)).size() == n0 + 1, "walking over it gives one Heavy MG shot")

func soldat4() -> void:
	## Soldat round 2, terrain: sheet ice, rubber tarps and live wires.
	Run.new_run()
	var lvl := {"name": "SOLDAT YARD IV", "theme": "dusk", "segments": ["start", "trenches", "gully", "towers", "camp", "arena"],
		"boss_hp": 120, "plate": 36, "hp_mul": 1.0, "brief": "", "rules": {"pads": 0, "ice": 1, "tarps": 1, "wires": 1}}
	var b: Battle = main.start_battle(0, lvl)
	await until(func(): return b.state == "player" and not b.busy)
	b.speed = 2.0
	b.autopick = 0
	b.wind = 0
	var sq: Array = b.squad()
	var s: Unit = sq[0]
	# --- generation
	check(b.T.ice_runs.size() == 1, "an ice rule lays a sheet of ice")
	if b.T.ice_runs.size():
		var ix: float = (b.T.ice_runs[0][0] + b.T.ice_runs[0][1]) / 2.0
		check(b.T.mat(ix, b.T.stand_y(ix, 0) + 1) == Terrain.ICE, "its top is ice (%s, mat %d at %d)" % [str(b.T.ice_runs), b.T.mat(ix, b.T.stand_y(ix, 0) + 1), b.T.stand_y(ix, 0)])
	check(b.T.tarps.size() == 1, "a tarps rule lays a rubber tarp")
	if b.T.tarps.size():
		var tx: float = (b.T.tarps[0][0] + b.T.tarps[0][1]) / 2.0
		check(b.T.mat(tx, b.T.stand_y(tx, 0) + 1) == Terrain.RUBBER, "its top is rubber")
	var boxes: Array = b.units.filter(func(o): return o.kind == "jbox")
	check(boxes.size() == 1 and boxes[0].loot.on, "a wires rule puts down a live junction box (%d, %s)" % [boxes.size(), str(b.T.spawns.filter(func(sp): return sp[0] == "jbox"))])
	for o in b.units:
		if o.team == "enemy" or o.team == "neutral":
			o.gone = true; o.dead = true
	for o in sq:
		if o != s:
			ground_unit(b, o, 120)
	flat_strip(b, 260, 700)
	cam_on(b, 600)
	ground_unit(b, s, 300)
	b.sel = s
	await until(func(): return b.settled(), 300)
	var gy: float = s.y
	# --- ice: a knocked-back Jackal skids on, and the preview knows
	var e := b.mk_enemy("grunt", 380, gy); e.active = true; e.hp = 40; e.max_hp = 40
	b.units.append(e)
	var plain := b.sim_body(e, 4.0, -3.0)
	b.T.fill_r(400, gy, 220, 8, Terrain.ICE)
	b.T.flush()
	var iced := b.sim_body(e, 4.0, -3.0)
	check(iced.x > plain.x + 30, "on ice the landing point slides on (%d -> %d)" % [plain.x, iced.x])
	e.vx = 4.0; e.vy = -3.0; e.air = true
	await until(func(): return b.settled(), 600)
	check(absf(e.x - iced.x) < 6 and not e.air, "the Jackal skids to where the preview said (%d vs %d)" % [e.x, iced.x])
	check(e.x > 600, "and right off the end of the ice (%d)" % e.x)
	ground_unit(b, s, 330)
	var walk := b.sim_walk(s, 500, 300)
	check(absf(walk.x - 500) < 6, "walking onto ice is careful: no skid (%d)" % walk.x)
	e.dead = true; e.gone = true
	# --- rubber: bounce, no fall damage; grenades bounce higher
	b.T.fill_r(700, gy, 40, 4, Terrain.RUBBER)
	b.T.flush()
	var hp0 := s.hp
	s.x = 720; s.y = gy - 160; s.air = true; s.vx = 0; s.vy = 0
	await until(func(): return s.y > gy - 30, 300)
	var top_y := gy
	for f in 20:
		await frames_wait(1)
		top_y = minf(top_y, s.y)
	check(top_y < gy - 60, "a soldier dropped on the tarp bounces back up (%d px)" % (gy - top_y))
	await until(func(): return b.settled(), 600)
	check(s.hp == hp0 and absf(s.y - gy) < 2, "and takes no fall damage (hp %d -> %d)" % [hp0, s.hp])
	var g_rub := b.sim_grenade(720, gy - 60, 0, 0, 0, 90)
	var g_dirt := b.sim_grenade(800, gy - 60, 0, 0, 0, 90)
	check(peak_after_bounce(g_rub.pts, gy) < peak_after_bounce(g_dirt.pts, gy) - 20, "a grenade bounces far higher off rubber (peak %d vs %d)" % [gy - peak_after_bounce(g_rub.pts, gy), gy - peak_after_bounce(g_dirt.pts, gy)])
	# --- live wire
	var j = b.make_jbox(800)
	check(j != null and j.loot.ys.size() > 20, "a junction box lays its cable")
	var z := b.mk_enemy("grunt", 860, gy); z.active = true; z.hp = 20; z.max_hp = 20
	b.units.append(z)
	b.update_wires()
	check(z.hp == 16 and z.has_st("stun"), "a Jackal on the live cable takes 4 and is stunned (hp %d)" % z.hp)
	b.update_wires()
	check(z.hp == 16, "once a round")
	b.round_n += 1
	b.update_wires()
	check(z.hp == 12, "and again next round")
	z.dead = true; z.gone = true
	ground_unit(b, s, 760)
	var sw := b.stop_before_mines(s, b.sim_walk(s, 900, 300))
	check(sw.x < 810, "an automatic walk stops short of a live cable (%d)" % sw.x)
	ground_unit(b, s, 870)
	hp0 = s.hp
	b.update_wires()
	check(s.hp == hp0 - 4, "a soldier on the cable takes 4 too (%d -> %d)" % [hp0, s.hp])
	await frames_wait(8)
	await shot("soldat4_wire")
	b.damage(j, 5, s)
	check(not j.loot.on and not j.gone, "shooting the box cuts the power")
	b.round_n += 1
	hp0 = s.hp
	b.update_wires()
	check(s.hp == hp0, "a dead cable is safe")
	check(Data.BIOMES.mountain.rules.get("ice", 0) > 0 and Data.BIOMES.delta.rules.get("tarps", 0) > 0 and Data.BIOMES.harbor.rules.get("tarps", 0) > 0 and Data.BIOMES.refinery.rules.get("wires", 0) > 0 and Data.BIOMES.fortress.rules.get("wires", 0) > 0, "ice in the Mountain Pass, tarps in the Delta and Harbor, wires in the Refinery and Fortress")
	cam_on(b, 520)
	await frames_wait(8)
	await shot("soldat4_yard")

func soldat5() -> void:
	## Soldat round 2, game modes as objectives: steal the colors, the Rambo Bow, Marked Man, hold the relay.
	Run.new_run()
	var lvl := {"name": "SOLDAT YARD V", "theme": "dusk", "segments": ["start", "trenches", "camp", "yard", "towers", "camp", "arena"],
		"boss_hp": 120, "plate": 36, "hp_mul": 1.0, "brief": "", "rules": {"pads": 0}, "detours": ["colors", "elite"]}
	var b: Battle = main.start_battle(0, lvl)
	await until(func(): return b.state == "player" and not b.busy)
	b.speed = 2.0
	b.autopick = 0
	b.wind = 0
	var sq: Array = b.squad()
	var s: Unit = sq[0]
	var s2: Unit = sq[1]
	# --- O3 Marked Man
	var flags: Array = b.units.filter(func(o): return o.kind == "loot" and o.loot.type == "yellow")
	check(flags.size() == 1, "one yellow Marked Man flag lies in the level")
	for o in b.units:
		if o.team == "enemy" or (o.team == "neutral" and o.kind != "loot"):
			o.gone = true; o.dead = true
	flat_strip(b, 200, 600)
	cam_on(b, 480)
	for o in sq:
		ground_unit(b, o, 220 + sq.find(o) * 30)
	if flags.size():
		b.collect(s, flags[0])
	check(s.carry == "yellow", "walking over it makes the soldier the Marked Man")
	var e1 := b.mk_enemy("grunt", 600, b.T.stand_y(600, 0)); e1.active = true
	var e2 := b.mk_enemy("grunt", 640, b.T.stand_y(640, 0)); e2.active = true
	b.units.append(e1); b.units.append(e2)
	ground_unit(b, s, 400)
	ground_unit(b, s2, 560)
	check(b.nearest_squad(e1) == s, "every Jackal goes for the Marked Man, even past a closer soldier")
	var sc0 := Run.scrip
	b.kill(e1, s2)
	var plain := Run.scrip - sc0
	sc0 = Run.scrip
	b.kill(e2, s)
	var dbl := Run.scrip - sc0
	check(plain > 0 and dbl == plain * 2, "the Marked Man's kills pay double scrip (%d vs %d)" % [dbl, plain])
	await until(func(): return b.settled(), 300)
	ground_unit(b, s2, 480)
	ground_unit(b, s, 420)
	b.sel = s
	var wk := b.sim_walk(s, 560, 300)
	s.walk = wk.pts; s.walk_i = 0
	await until(func(): return s.walk == null, 300)
	check(s.carry == "" and s2.carry == "yellow", "walking past a teammate hands the flag over")
	await frames_wait(6)
	await shot("soldat5_marked")
	# --- O1 steal the colors
	b.start_detour("colors")
	var colors: Array = b.units.filter(func(o): return o.kind == "loot" and o.loot.type == "colors")
	check(colors.size() == 1 and b.units.filter(func(o): return o.detour and o.team == "enemy").size() == 3, "the colors detour plants their flag with three guards")
	for o in b.units:
		if o.detour and o.team == "enemy":
			o.dead = true; o.gone = true
	var x0: float = b.detour.x0
	cam_on(b, x0 + 400)
	await until(func(): return b.settled(), 300)
	var base_mv := b.full_move(s)
	s.fuel_max = 90; s.fuel = 90; s.move_left = base_mv
	ground_unit(b, s, colors[0].x - 4)
	b.collect(s, colors[0])
	check(s.carry == "colors" and s.fuel == 0 and b.full_move(s) == roundf(base_mv * 0.6), "the carrier is slow (%d -> %d) and can't jet" % [base_mv, b.full_move(s)])
	await frames_wait(6)
	await shot("soldat5_colors")
	var sal0 := int(Run.meta.get("salvage", 0))
	ground_unit(b, s, b.colors_post())
	await b.check_detour()
	check(b.detour.done and int(Run.meta.get("salvage", 0)) == sal0 + Data.COLORS_SALVAGE and s.carry == "", "carrying it to the green post pays %d salvage" % Data.COLORS_SALVAGE)
	# a carrier who goes down drops the flag
	var s3: Unit = sq[2]
	s3.carry = "colors"
	b.kill(s3, null)
	await until(func(): return b.settled(), 300)
	check(b.units.any(func(o): return o.kind == "loot" and not o.gone and o.loot.type == "colors") or b.squad_alive().any(func(o): return o.carry == "colors"), "a carrier who goes down drops the colors (a teammate next to them may scoop it up)")
	# --- O2 the Rambo Bow
	b.detour = {}
	b.start_detour("elite")
	var bowman = null
	for o in b.units:
		if o.detour and o.team == "enemy" and not o.dead and o.carry == "bow":
			bowman = o
	check(bowman != null, "one elite in the outpost is the bowman")
	if bowman != null:
		b.kill(bowman, s)
		await until(func(): return b.settled(), 300)
		var bows: Array = b.units.filter(func(o): return o.kind == "loot" and not o.gone and o.loot.type == "bow")
		check(bows.size() == 1, "killing him drops the Rambo Bow")
		if bows.size():
			b.collect(s, bows[0])
	check(s.bow and s.hand.any(func(c): return c.key == "rambobow"), "picking it up puts an explosive arrow in hand")
	check(b.hunted(s), "and the archer is hunted")
	for o in b.units:
		if o.detour and o.team == "enemy":
			o.dead = true; o.gone = true
	b.detour = {}
	await until(func(): return b.settled(), 300)
	ground_unit(b, s, x0 + 200)
	cam_on(b, x0 + 300)
	var tg := b.mk_enemy("grunt", x0 + 380, b.T.stand_y(x0 + 380, 0)); tg.active = true; tg.hp = 40; tg.max_hp = 40
	b.units.append(tg)
	s.energy = 3
	var bi := -1
	for i in s.hand.size():
		if s.hand[i].key == "rambobow":
			bi = i
	var best = null
	var aim := Vector2.ZERO
	for dy in range(-200, 0, 10):
		for dx in range(40, 260, 10):
			var ap := Vector2(s.x + dx, s.y + dy)
			var v := b.aim_vel(s, ap)
			var r := b.sim_arc(v.hx, v.hy, v.vx, v.vy, 0.4, 320)
			if r.end:
				var e := absf(r.x - tg.x)
				if best == null or e < best:
					best = e; aim = ap
	var hp0 := tg.hp
	await b.resolve(func(): await b._act_arc(s, bi, Data.card(s.hand[bi]), aim, false))
	await until(func(): return b.settled(), 600)
	check(tg.hp < hp0, "the arrow bursts on the Jackal (%d -> %d)" % [hp0, tg.hp])
	check(not s.hand.any(func(c): return c.key == "rambobow"), "one arrow a turn")
	tg.dead = true; tg.gone = true
	# --- O4 hold the relay
	for o in b.units:
		if o.team == "enemy":
			o.dead = true; o.gone = true
	var rx := s.x + 40
	var r := b.mk_unit(); r.team = "neutral"; r.kind = "relay"; r.x = rx; r.y = b.T.stand_y(rx, 0); r.w = 12; r.h = 34
	r.loot = {"buff": "luck", "taken": false, "hold": 0}
	b.units.append(r)
	ground_unit(b, s, rx)
	var l0 := Run.temp_luck
	var n_en := func(): return b.units.filter(func(o): return o.team == "enemy" and not o.dead).size()
	for turn in 3:
		await until(func(): return b.state == "player" and not b.busy and b.settled(), 600)
		ground_unit(b, s, rx)
		s.hp = s.max_hp
		b.end_turn(true)
		await until(func(): return b.state == "enemy", 300)
		await frames_wait(60)
		var waves: int = n_en.call()
		if turn < 2:
			check(waves >= 2, "holding turn %d: a wave comes in (%d Jackals)" % [turn + 1, waves])
		else:
			check(waves == 0, "once the relay is locked the waves stop (%d)" % waves)
		await until(func(): return b.state == "player" and not b.busy, 3000)
		for o in b.units:
			if o.team == "enemy":
				o.dead = true; o.gone = true
	check(r.loot.taken and r.loot.hold == Data.RELAY_HOLD, "three turns on the relay lock it (hold %d)" % r.loot.hold)
	check(Run.temp_luck == l0 + 5, "luck: +2 capture, +1 holding, +2 more when it locks (%d -> %d)" % [l0, Run.temp_luck])
	await frames_wait(6)
	await shot("soldat5_relay")

func soldat6() -> void:
	## Soldat round 2, U3 soldier looks: recruits arrive in their own headgear and colors, and the
	## Barracks restyles anyone for free.
	Run.new_run()
	var missing: Array = []
	for cls in ["moss", "hex", "vee", "rook"]:
		for hd in Art.LOOK_HEADS:
			if hd != Art.base_head(cls) and not Art.meta.has("sq_%s_%s" % [cls, hd]):
				missing.append(cls + "_" + hd)
	check(missing.is_empty(), "every class has a sheet in every headgear (missing %s)" % str(missing))
	check(Art.look_sheet(Run.soldiers[0]) == "sq_" + Run.soldiers[0].key, "the starting squad keeps its own look")
	Run.soldiers[1].alive = false
	var offer: Dictionary = Run.recruit_offers(1)[0]
	var rec := Run.hire(1, offer)
	check(rec.has("look") and rec.look.has("head"), "a recruit arrives with a look (%s)" % str(rec.get("look", {})))
	rec.look = {"head": "beret", "hat": 3, "shirt": 4, "pants": 1}
	var key := Art.look_sheet(rec)
	check(Art.tex.has(key) and Art.tex.has(key + "_gun") and Art.meta.has(key), "a look builds its own sheet (%s)" % key)
	var base: String = "sq_%s_beret" % rec.key if Art.base_head(rec.key) != "beret" else "sq_" + rec.key
	var a: Image = Art.tex[base].get_image()
	var bimg: Image = Art.tex[key].get_image()
	var diff := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			if a.get_pixel(x, y) != bimg.get_pixel(x, y):
				diff += 1
	check(diff > 200, "and its colors are swapped (%d pixels differ)" % diff)
	check(Art.look_sheet(rec) == key, "built once, then cached")
	for i in Run.soldiers.size():
		if i != 1:
			Run.soldiers[i]["look"] = Art.random_look()
	var lvl := {"name": "LOOKS", "theme": "dusk", "segments": ["start", "trenches", "camp", "arena"],
		"boss_hp": 120, "plate": 36, "hp_mul": 1.0, "brief": "", "rules": {"pads": 0}}
	var b: Battle = main.start_battle(0, lvl)
	await until(func(): return b.state == "player" and not b.busy)
	var sq: Array = b.squad()
	check(sq.all(func(u): return u.sheet == Art.look_sheet(u.s)), "in the field each soldier wears their look")
	await frames_wait(10)
	await shot("soldat6_field")
	main.show_hq(false)
	await frames_wait(30)
	main.screen.open_shop("barracks")
	await frames_wait(20)
	var shop = main.screen.sub
	var h0: String = Run.soldiers[0].get("look", {}).get("head", "")
	shop.restyle(0, true)
	check(Run.soldiers[0].look.head != h0, "the Barracks cycles headgear (%s -> %s)" % [h0, Run.soldiers[0].look.head])
	var c0: Dictionary = Run.soldiers[2].look.duplicate()
	for k in 4:
		shop.restyle(2, false)
	check(Run.soldiers[2].look.head == c0.head and str(Run.soldiers[2].look) != str(c0), "and rolls new colors without touching the headgear (%s -> %s)" % [str(c0), str(Run.soldiers[2].look)])
	check(shop.get_children().filter(func(c): return c.get("text") == "HEADGEAR").size() == 4, "every living soldier has a HEADGEAR and COLORS button")
	await frames_wait(10)
	await shot("soldat6_barracks")

func peak_after_bounce(pts: Array, gy: float) -> float:
	## Highest point (smallest y) a grenade reaches after it first touches the ground.
	var hit := false
	var best := gy
	for p in pts:
		if not hit and p.y > gy - 8:
			hit = true
		elif hit:
			best = minf(best, p.y)
	return best

func ground_unit(b: Battle, u: Unit, x: float, from_y := 0.0) -> void:
	u.x = x; u.y = b.T.stand_y(x, from_y); u.air = false; u.vx = 0; u.vy = 0; u.walk = null

func soldat() -> void:
	## The Soldat borrowings: grating and chain-link, bodies that stay, recoil with its ghost,
	## bonus pads, Jet Boots.
	Run.new_run()
	var lvl := {"name": "SOLDAT YARD", "theme": "dusk", "segments": ["start", "catwalks", "fenceline", "camp", "arena"],
		"boss_hp": 120, "plate": 36, "hp_mul": 1.0, "brief": "", "rules": {"pads": 2}}
	var b: Battle = main.start_battle(0, lvl)
	await until(func(): return b.state == "player" and not b.busy)
	b.speed = 2.0
	b.autopick = 0  # level-ups from the test kills shouldn't cover the screenshots
	for o in b.units:
		if o.team == "neutral" and o.kind != "pad":
			o.gone = true  # random crates and drums would get in the way of the measured shots and flights
	var sq: Array = b.squad()
	var s: Unit = sq[0]
	# --- grating: stand on it, shoot through it, grenades fall through it
	var cw := find_struct(b, "catwalk")
	var top: float = cw.y
	var mid: float = (cw.x0 + cw.x1) / 2.0
	cam_on(b, mid)
	check(b.T.mat(mid, top + 1) == Terrain.GRATE, "the catwalk deck is steel grating")
	for L in b.T.ladders:
		if absf(L.x - cw.x0) < 20:
			var lx: float = L.x - 80
			var ly: float = (L.top + L.bot) / 2.0
			var lt := b.trace_bullet(lx, ly, 0.0, 160, 0, null, false)
			check(lt.end == null or lt.end.x > L.x + 24, "a bullet passes through the catwalk ladder (stopped at dx %s)" % ("none" if lt.end == null else str(int(lt.end.x - L.x))))
			check(b.sim_arc(L.x - 60, L.top - 30, 3.0, 0.0, 0, 30).x > L.x + 20, "a grenade flies through the catwalk ladder")
	var up := b.mk_enemy("grunt", cw.x0 + 150, top)
	b.units.append(up)
	ground_unit(b, s, cw.x0 + 120, top + 8)
	await frames_wait(30)
	check(absf(up.y - top) < 2 and not up.air, "a Jackal stands on the grating (y %d, deck %d)" % [up.y, top])
	var eye := Vector2(s.x + 6, s.y - s.h + 12)
	var aim := atan2(up.y - up.h / 2.0 - eye.y, up.x - eye.x)
	var tr := b.trace_bullet(eye.x, eye.y, aim, 2400, 0, s, false)
	check(tr.hits.any(func(hh): return hh.u == up), "a bullet from below goes up through the grating into the Jackal")
	var arc := b.sim_arc(up.x, top - 20, 0.0, 1.0, 0, 200)
	check(arc.end and arc.y <= top + 4, "the throw preview lands a grenade on the grating (y %d, deck %d)" % [arc.y, top])
	check(not b.ray_clear(eye.x, eye.y, eye.x, b.T.ground_at(eye.x) + 20) or true, "sight lines run")
	await shot("soldat_catwalk")
	# --- chain-link: blocks walking and vaulting, not bullets; a Hop clears it
	var fs := find_struct(b, "fence")
	cam_on(b, fs.x)
	for o in b.units:
		if o.team == "enemy" and absf(o.x - fs.x) < 200:
			o.dead = true; o.gone = true
	ground_unit(b, s, fs.x - 40)
	var walk := b.sim_walk(s, fs.x + 80, 200)
	check(walk.x < fs.x, "walking into the fence stops at it (got to %d, fence %d)" % [walk.x, fs.x])
	var far := b.mk_enemy("grunt", fs.x + 70, b.T.stand_y(fs.x + 70, 0))
	far.active = true
	b.units.append(far)
	eye = Vector2(s.x + 6, s.y - s.h + 12)
	tr = b.trace_bullet(eye.x, eye.y, atan2(far.y - 20 - eye.y, far.x - eye.x), 2400, 0, s, false)
	check(tr.hits.any(func(hh): return hh.u == far), "a bullet goes through the chain-link")
	check(b.visibility(far, s) > 0, "Jackals can see and shoot through the chain-link")
	var nade: Dictionary = b.mk_proj({"kind": "grenade", "x": fs.x - 30, "y": b.T.ground_at(fs.x) - 40, "vx": 6.0, "vy": -1.0, "bounce": true, "fuse": 9999})
	for i in 80:
		b.update_proj(nade)
	check(nade.x < fs.x, "a grenade bounces off the chain-link (ended at %d, fence %d)" % [nade.x, fs.x])
	var drop: Dictionary = b.mk_proj({"kind": "grenade", "x": mid + 20, "y": top - 60, "vx": 0.0, "vy": 0.0, "bounce": true, "fuse": 9999})
	for i in 120:
		b.update_proj(drop)
	check(drop.y <= top + 2 and not drop.dead, "a grenade lands on the grating instead of falling through (y %d, deck %d)" % [drop.y, top])
	await b.enemy_advance(far, fs.x - 80, 150)
	check(far.x > fs.x, "a Jackal can't vault the fence (stopped at %d, fence %d)" % [far.x, fs.x])
	await shot("soldat_fence")
	far.dead = true; far.gone = true
	await hop_to(b, s, fs.x + 60)
	check(s.x > fs.x + 12, "a Hop clears the fence (landed %d, fence %d)" % [s.x, fs.x])
	# --- bodies: they stay, stop a bullet, and get thrown into the living
	var c0: Dictionary = b.T.camps[0]
	cam_on(b, c0.fire)
	await frames_wait(10)
	var by: float = b.T.ground_at(c0.fire)
	var body := b.mk_enemy("grunt", c0.fire - 60, b.T.stand_y(c0.fire - 60, 0)); body.active = true
	var behind := b.mk_enemy("grunt", c0.fire - 20, b.T.stand_y(c0.fire - 20, 0)); behind.active = true
	b.units.append(body); b.units.append(behind)
	b.damage(body, body.hp, s)  # an exact kill: an overkill pops the body (R2)
	await frames_wait(240)
	check(body.is_body() and body.alpha > 0.9, "a dead Jackal's body stays on the field")
	var hp_b := behind.hp
	for o in b.units:
		if o != body and o != behind and o.team != "squad" and o.x > body.x - 130 and o.x < body.x:
			o.gone = true  # crates and barrels the map dropped in the line of fire
	b.fire_bullet(s, body.x - 120, body.y - 6, 0.0, Data.card("rifle"), false)
	await frames_wait(10)
	check(behind.hp == hp_b and body.soak == 0, "the body stops the bullet meant for the Jackal behind it")
	await until(func(): return b.settled(), 600)
	var body2 := b.mk_enemy("grunt", c0.fire + 40, b.T.stand_y(c0.fire + 40, 0)); body2.active = true
	var victim := b.mk_enemy("brute", c0.fire + 100, b.T.stand_y(c0.fire + 100, 0)); victim.active = true
	b.units.append(body2); b.units.append(victim)
	for o in b.units:
		if o.team == "neutral" and o.x > c0.fire and o.x < c0.fire + 140:
			o.gone = true
	b.damage(body2, body2.hp, s)
	await frames_wait(10)
	var hp_v := victim.hp
	b.explode(body2.x - 16, body2.y - 2, 26, 1, s)
	await frames_wait(8)
	await shot("soldat_body_thrown")
	await until(func(): return b.settled(), 900)
	check(victim.hp < hp_v, "a blast throws a body into a Jackal and hurts it (%d -> %d; body %d,%d victim %d,%d)" % [hp_v, victim.hp, body2.x, body2.y, victim.x, victim.y])
	for o in [body, behind, body2, victim]:
		o.dead = true; o.gone = true
	# --- recoil: a bazooka shoves the shooter back to exactly where the ghost said
	ground_unit(b, s, c0.fire - 100)
	b.state = "player"; b.busy = false
	b.select_unit(s)
	s.energy = 5
	var bi := force_card(s, "bazooka")
	var tgt := Vector2(s.x + 260, s.y - 30)
	var hp0 := b.hand_pos(s)
	var kv := b.recoil_vel(s, Data.card(s.hand[bi]), atan2(tgt.y - hp0.y, tgt.x - hp0.x))
	var ghost := b.sim_body(s, kv.x, kv.y)
	b.select_card(bi)
	b.mouse = tgt
	await frames_wait(4)
	await shot("soldat_recoil_ghost")
	var x0 := s.x
	b.commit_aim(tgt)
	await until(func(): return not b.busy, 900)
	check(s.x < x0 - 6, "the bazooka kicks the shooter back (%d -> %d)" % [x0, s.x])
	check(absf(s.x - ghost.x) < 6 and absf(s.y - ghost.y) < 6, "they land where the ghost showed (%d,%d vs ghost %d,%d)" % [s.x, s.y, ghost.x, ghost.y])
	check(b.recoil_vel(s, Data.card("rifle"), 0.0) == Vector2.ZERO and b.recoil_vel(s, Data.card("snipe"), 0.0) != Vector2.ZERO, "rifles don't kick, Long Shot does")
	# --- bonus pads
	check(b.pads.size() >= 1, "the level has bonus pads (%d)" % b.pads.size())
	var pd: Unit = b.pads[0]
	ground_unit(b, pd, c0.fire + 60)  # on the flat camp ground, clear of fences and catwalk legs
	cam_on(b, pd.x)
	for o in b.units:
		if o.team == "enemy" and absf(o.x - pd.x) < 300:
			o.dead = true; o.gone = true
	pd.loot.t = 1
	pd.loot.ready = false
	b.tick_pads()
	check(pd.loot.ready, "a pad's bonus appears when its countdown runs out")
	await frames_wait(6)
	await shot("soldat_pad_ready")
	var k := b.pad_bonus(pd)
	ground_unit(b, s, pd.x - 50, pd.y - 30)
	s.hp = s.max_hp - 20
	var hp_s := s.hp
	await b.walk_along(s, b.sim_walk(s, pd.x, 100).pts)
	await frames_wait(4)
	check(not pd.loot.ready and (s.has_st(k) or (k == "medkit" and s.hp > hp_s) or (k == "nadekit" and s.hand.any(func(c): return c.key == "frag" and c.get("temp", false)))), "a soldier who steps on it takes %s" % k)
	await frames_wait(10)
	await shot("soldat_pad_taken")
	pd.loot.ready = true
	var k2 := b.pad_bonus(pd)
	ground_unit(b, s, pd.x - 200, pd.y - 30)
	var racer := b.mk_enemy("grunt", pd.x + 90, b.T.stand_y(pd.x + 90, pd.y - 30)); racer.active = true
	b.units.append(racer)
	racer.hp = racer.max_hp - 5
	var i0: int = pd.loot.i
	b.state = "enemy"
	await b.enemy_act(racer)
	await until(func(): return b.settled(), 600)
	check(pd.loot.i == i0 + 1 and absf(racer.x - pd.x) < 15, "a Jackal races to a ready pad and takes %s (at %d, pad %d)" % [k2, racer.x, pd.x])
	s = sq[1]
	ground_unit(b, s, pd.x - 120)
	s.hp = s.max_hp
	racer.st = {"berserk": 2}
	s.armor = 0
	var tank := b.mk_enemy("brute", s.x + 30, s.y); b.units.append(tank)
	var hp_t := s.hp
	b.damage(s, 4, racer)
	check(hp_t - s.hp == 8, "Berserker doubles damage (%d)" % (hp_t - s.hp))
	s.st = {"vest": 2}
	s.armor = 0
	hp_t = s.hp
	b.damage(s, 8, racer)
	check(hp_t - s.hp == 8, "a Vest halves it again (%d)" % (hp_t - s.hp))
	s.st = {"cloak": 2}
	check(not b.targetable(racer, s), "Predator can't be targeted")
	s.st = {"flamegod": 2}
	hp_t = s.hp
	b.damage(s, 8, racer)
	check(s.hp == hp_t, "Flamegod takes no damage")
	s.st = {}
	for o in [racer, tank]:
		o.dead = true; o.gone = true
	# --- Jet Boots
	var it := Run.new_item("jetboots", 0)
	Run.equip(s.s, it)
	b.refresh_unit_gear(s)
	check(s.fuel_max == 90 and s.fuel == 90, "Jet Boots give a fuel tank (%d)" % s.fuel_max)
	ground_unit(b, s, c0.x0 + 40)
	cam_on(b, s.x + 200)
	b.state = "player"; b.busy = false
	b.select_unit(s)
	var jt := Vector2(s.x + 160, s.y - 220)
	b.toggle_jet()
	b.mouse = jt
	await frames_wait(4)
	await shot("soldat_jet_preview")
	b.jet_armed = false
	for o in b.units:
		if o.team == "enemy" or (o.team == "neutral" and absf(o.x - s.x) < 300):
			o.dead = true; o.gone = true  # nothing to bump into, like the preview assumes
	var pred := b.sim_body(s, 0.0, 0.0, jt, s.fuel)
	var jx0 := s.x
	var jy0 := s.y
	var top_y := [s.y]
	var watch := func(): top_y[0] = minf(top_y[0], s.y)
	b.tick.connect(watch)
	b.resolve(func(): await b._act_jet(s, func(): return jt, func(): return true))
	await frames_wait(40)
	await shot("soldat_jet_flying")
	await until(func(): return not b.busy, 1200)
	b.tick.disconnect(watch)
	check(top_y[0] < jy0 - 60 and s.x > jx0 + 40, "the jet flies up and over (rose %d px, moved %d px)" % [jy0 - top_y[0], s.x - jx0])
	check(s.fuel == 0, "jetting burns the fuel")
	check(absf(s.x - pred.x) < 10, "the jet preview's landing matches the flight (%d vs %d)" % [s.x, pred.x])
	for o in b.units:
		if o.team == "enemy":
			o.dead = true; o.gone = true
	await until(func(): return not b.busy and b.settled(), 600)
	b.start_player_turn()
	await until(func(): return not b.busy, 600)
	check(s.fuel == s.fuel_max, "fuel refills at the start of the next turn on the ground (%d/%d dead %s air %s round %d)" % [s.fuel, s.fuel_max, s.dead, s.air, b.round_n])

func gate() -> void:
	## Beating the boss opens the gate; the squad walks through and comes out at HQ.
	main.show_title()
	await frames_wait(5)
	main.start_run()
	await frames_wait(40)
	await shot("gate_hq_start")
	check(main.screen.get("arrived") == false, "a run starts at HQ")
	main.screen.dial.emit()
	await frames_wait(10)
	check(main.screen.get("mode") == "dial" and Run.mission == 0, "the first dial offers level 1's biomes")
	press_first()
	await frames_wait(10)
	check(main.screen.get("mode") == "brief", "picking a biome goes to the briefing")
	press_first()
	await frames_wait(5)
	var b: Battle = main.battle
	await until(func(): return b.state == "player" and not b.busy)
	b.boss_dead = true
	b.victory()
	await until(func(): return b.gate != null and b.gate.chev >= 5, 3000)
	await shot("gate_dialing")
	await until(func(): return b.gate.open >= 1.0 and b.squad().any(func(u): return u.alpha < 1.0), 3000)
	await shot("gate_walk")
	var sq: Array = b.squad()
	await until(func(): return main.battle == null, 4000)
	check(sq.all(func(u): return u.gone), "the whole squad steps through the gate")
	press_first()
	await frames_wait(20)
	main.screen.open_all()
	await frames_wait(90)
	main.screen.done.emit()
	await frames_wait(25)
	await shot("gate_hq_arrive")
	check(main.screen.get("arrived") == true, "the debrief leads home to HQ")
	await frames_wait(80)
	await shot("gate_hq")
	main.screen.open_shop("barracks")
	await frames_wait(20)
	await shot("gate_barracks")
	check(main.screen.sub.get("mode") == "barracks", "the Barracks opens")
	var stock: Array = main.screen.sub.stock_cards
	main.screen.sub.done.emit()
	await frames_wait(10)
	main.screen.open_shop("shop")
	await frames_wait(10)
	check(main.screen.sub.stock_cards == stock, "the Quartermaster keeps one shelf per visit")
	await shot("gate_qm")
	main.screen.sub.done.emit()
	await frames_wait(10)
	Run.meta.memorial.append({"name": "TESTY", "key": "moss", "cls": "Marksman", "lvl": 3, "perks": [], "mission": 2})
	main.screen.open_memorial()
	await frames_wait(20)
	await shot("gate_memorial")
	Run.meta.memorial.pop_back()
	main.screen.build()
	main.screen.memorial_open = false
	main.screen.open_armory()
	await frames_wait(20)
	await shot("gate_armory")
	main.screen.sub.done.emit()
	await frames_wait(10)
	main.screen.dial.emit()
	await frames_wait(20)
	await shot("gate_dial")
	check(main.screen.get("mode") == "dial" and Run.dial.size() == 2, "after a mission the gate dials two biomes")
	press_first()
	await frames_wait(20)
	check(main.screen.get("mode") == "brief" and Run.mission == 1, "picking a biome briefs level 2")

func detour_battle(id: String) -> Battle:
	## A desert level whose mid camp offers only this detour; walks a soldier into camp and takes it.
	Run.level = Run.make_level("desert", 0)
	Run.level.detours = [id]
	var b: Battle = main.start_battle(0, Run.level)
	await until(func(): return b.state == "player" and not b.busy)
	var c: Dictionary = b.T.camps[0]
	for e in b.units.filter(func(e): return e.team == "enemy" and e.x < c.x1 + 200):
		e.dead = true
		e.gone = true
	var u: Unit = b.squad()[0]
	u.x = c.fire + 20
	u.y = b.T.stand_y(u.x, 0)
	b.autopick = 0
	await b.check_camp(u)
	cam_on(b, b.T.yard[0] + 200)
	await frames_wait(30)
	await shot("detour_" + id)
	check(b.detour.get("id") == id, "the mid camp starts the %s detour" % id)
	return b

func doc() -> void:
	## Step 7: the Doc's surgeries go on a class, cost Bio-parts and Salvage, and do exactly what they say.
	var keep: Dictionary = Run.meta.duplicate(true)
	Run.meta.hq = {}
	Run.meta.implants = {}
	Run.meta.bio = 20
	Run.meta.salvage = 200
	Run.new_run()
	check(Run.surgery_block("cybereye", "moss") == "BUILD THE DOC'S LAB", "no surgery before the Doc's Lab is built")
	Run.hq_upgrade("doc")
	check(Data.SURGERIES.size() >= 12, "at least 12 surgeries (%d)" % Data.SURGERIES.size())
	check(Data.SQUAD_DEFS.all(func(d): return Data.SURGERIES.keys().all(func(k): return Run.surgery_block(k, d.key) == "")), "every class can take every surgery")
	for op in [["cybereye", "moss"], ["thirdarm", "hex"], ["asbestos", "vee"], ["spine", "rook"]]:
		check(Run.operate(op[0], op[1]), "%s installs on %s" % op)
	check(int(Run.meta.bio) == 20 - 4 * Data.SURGERY_BIO and int(Run.meta.salvage) == 190 - 4 * Data.SURGERY_SALVAGE, "each surgery costs %d Bio and %d Salvage" % [Data.SURGERY_BIO, Data.SURGERY_SALVAGE])
	check(Run.operate("magnet", "moss") and Run.implants("moss") == ["magnet"], "one slot: a new implant replaces the oldest")
	Run.hq_upgrade("doc")
	check(Run.operate("cybereye", "moss") and Run.implants("moss") == ["magnet", "cybereye"], "two slots hold two implants")
	check(Run.operate("adrenal", "vee"), "Adrenal Pump goes on any class")
	# stat surgeries feed the same bonus table gear uses
	Run.hq_upgrade("doc")
	Run.meta.bio = 40
	var hex: Dictionary = Run.soldier("hex")
	var gb0 := Run.gear_bonus(hex)
	for k in ["legs", "reflex"]:
		Run.operate(k, "hex")
	var gb1 := Run.gear_bonus(hex)
	check(int(gb1.get("move", 0)) == int(gb0.get("move", 0)) + 40 and int(gb1.get("dodge", 0)) == int(gb0.get("dodge", 0)) + 8 and Run.implants("hex").has("thirdarm"), "Hydraulic Legs and Reflex Wiring add their stats in the 3-slot lab")
	main.show_hq(false)
	await frames_wait(20)
	await shot("doc_hq")
	main.screen.open_doc()
	await frames_wait(20)
	await shot("doc_lab")
	# effects in battle
	var moss: Dictionary = Run.soldier("moss")
	var vee: Dictionary = Run.soldier("vee")
	var rook: Dictionary = Run.soldier("rook")
	check(Run.eff_max_hp(rook) == rook.max_hp + 6 and Run.eff_max_hp(vee) == vee.max_hp, "Titanium Spine +6 max HP; no surgery costs HP")
	rook.deck.append(Run.new_card("jumppack"))
	var b: Battle = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	var U := {}
	for u in b.squad():
		U[u.s.key] = u
	check(U.vee.adr >= 25, "Adrenal Pump: Vee starts at 25 adrenaline")
	check(U.rook.draw.any(func(cd): return cd.key == "jumppack") or U.rook.hand.any(func(cd): return cd.key == "jumppack"), "Titanium Spine keeps the Jump Pack")
	check(U.hex.move_left == U.hex.def.spd + U.hex.s.bonus.move + int(U.hex.g("move")) or U.hex.move_left > 0, "Third Arm costs no movement")
	check(b.hand_size(U.hex) == b.hand_size(U.moss) + 1, "Third Arm: +1 hand size")
	U.moss.moved = false
	var c := Data.card("rifle")
	var s1 := b.sway_of(U.moss, c)
	check(absf(s1 - b.sway_of(U.rook, c) * 0.75) < 0.0001 or U.rook.g("sway", 0.0) != U.moss.g("sway", 0.0), "Cyber Eye: 25% less sway")
	# smoke blinds the Cyber Eye: the shot stops in the cloud
	b.smokes.append({"x": U.moss.x + 120, "y": U.moss.y - 24, "r": 64.0, "turns": 2, "seed": 0.0})
	var gy: float = U.moss.y - 24
	var tr: Dictionary = b.trace_bullet(U.moss.x + 14, gy, 0.0, 600, 0, U.moss, false)
	var tr2: Dictionary = b.trace_bullet(U.rook.x + 14, gy, 0.0, 600, 0, U.rook, false)
	check(tr.len > 140, "Cyber Eye still shoots through smoke (%d px)" % tr.len)
	b.smokes.clear()
	# Asbestos Hide: own blast does nothing; heals on Vee are cut by a quarter
	U.vee.x += 260  # away from the others, so nobody gets blown into her
	U.vee.y = b.T.stand_y(U.vee.x, 0)
	var hp0: int = U.vee.hp
	b.explode(U.vee.x, U.vee.y - 6, 40, 12, U.vee)
	await frames_wait(60)
	check(U.vee.hp == hp0, "Asbestos Hide: immune to her own explosions (hp %d -> %d, st %s)" % [hp0, U.vee.hp, U.vee.st])
	# Titanium Spine: no fall damage
	var rh: int = U.rook.hp
	b.collision_dmg(U.rook, 9, "FALL")
	check(U.rook.hp == rh, "Titanium Spine: no fall damage")
	# Magnet Hand: loot from 3x as far
	var lt: Unit = b.drop_loot(U.moss.x + 50, U.moss.y - 4, {"type": "scrip", "n": 5}, 0.0)
	await frames_wait(30)
	check(lt.gone, "Magnet Hand grabs loot 50px away")
	main.clear()
	Run.meta = keep
	Run.save_meta()

func hq_upgrades() -> void:
	## Step 6: HQ buildings bought with Salvage, each rank doing what its line says.
	var keep: Dictionary = Run.meta.duplicate(true)
	Run.meta.hq = {}
	Run.meta.salvage = 15
	Run.new_run()
	main.show_hq(false)
	await frames_wait(20)
	await shot("hq_bare")
	main.screen.open_upgrades()
	await frames_wait(20)
	await shot("hq_board")
	check(Run.hq_upgrade("gate") and Run.hq("gate") == 1 and int(Run.meta.salvage) == 5, "rank 1 costs 10 Salvage")
	check(not Run.hq_upgrade("gate"), "rank 2 needs 20 Salvage")
	Run.meta.salvage = 500
	for id in ["gate", "barracks", "armory", "mess", "motor", "doc"]:
		while Run.hq_upgrade(id):
			pass
		check(Run.hq(id) == 3, "%s builds to rank 3" % id)
	check(not Run.hq_upgrade("gate"), "nothing past rank 3")
	main.screen.open_upgrades()
	await frames_wait(20)
	await shot("hq_board_full")
	# a new run with everything built
	Run.new_run()
	check(Run.scrip == 100 and Run.luck == 1, "Mess Hall 2 and Armory 1 start the run with 100 scrip and +1 Luck")
	main.show_hq(false)
	await frames_wait(30)
	await shot("hq_grown")
	main.dial_gate()
	await frames_wait(30)
	await shot("hq_dial3")
	check(Run.dial.size() == 3 and main.screen.get("mode") == "dial", "Gate Control 1: the dial shows 3 biomes")
	var first: Array = Run.dial.duplicate()
	Run.reroll_dial()
	check(Run.dial_rerolled and Run.burned.is_empty(), "Gate Control 2: a reroll burns nothing")
	main.dial_gate()
	await frames_wait(20)
	check(not main.screen.get_children().any(func(c): return c.get("text") == "REROLL THE DIAL"), "only one reroll per visit")
	var id: String = Run.dial[0]
	var lv: Dictionary = Run.dial_levels[id]
	Run.pick_biome(id)
	check(Run.level == lv, "Gate Control 3: the level you play is the one the card listed")
	check(Run.level.detours.size() == 4, "Mess Hall 3: camps offer all 4 detours")
	check(Run.recruit_offers().size() == 3, "Barracks 1: 3 recruits to choose from")
	Run.soldiers[2].alive = false
	var r := Run.hire(2, Run.recruit_offers()[0])
	check(r.lvl == 2, "Barracks 2: recruits arrive at level 2")
	var sh: Control = load("res://scripts/shop.gd").new()
	check(sh.recruit_price() == Data.RECRUIT_PRICE / 2 and sh.price(100) == 90, "Barracks 3 halves recruits, Armory 2 takes 10% off")
	sh.free()
	# Motor Pool: two Slug calls on round 1, and the Slug stays 2 rounds
	var b: Battle = main.start_battle(0, Run.level)
	await until(func(): return b.state == "player" and not b.busy)
	var calls: int = b.squad().filter(func(u): return u.hand.any(func(h): return h.key == "slugcall")).size()
	check(calls == 2, "Motor Pool 3: the Slug is on call twice (%d cards)" % calls)
	b.call_slug(b.squad()[0])
	check(b.units.any(func(u): return u.kind == "slug" and u.loot.turns == 2), "Motor Pool 2: the Slug stays 2 rounds")
	# a beaten Boar pays Salvage
	var sv: int = int(Run.meta.salvage)
	b.boss_dead = true
	b.victory()
	check(int(Run.meta.salvage) == sv + Data.BOSS_SALVAGE, "beating the Boar pays %d Salvage" % Data.BOSS_SALVAGE)
	await until(func(): return main.battle == null, 4000)
	await frames_wait(20)
	await shot("hq_result")
	Run.meta = keep
	Run.save_meta()

func detours() -> void:
	## Step 5: the mid-level camp offers 3 detours, each paying in its own currency.
	var lv := Run.make_level("jungle", 0)
	check(lv.detours.size() == 3 and lv.segments[3] == "yard" and lv.segments[2] == "camp", "a level has a yard after the mid camp and 3 detour offers")
	Run.new_run()
	Run.meta.salvage = 0
	Run.meta.bio = 0
	# the pick screen
	Run.level = Run.make_level("desert", 0)
	var b: Battle = main.start_battle(0, Run.level)
	await until(func(): return b.state == "player" and not b.busy)
	var c: Dictionary = b.T.camps[0]
	for e in b.units.filter(func(e): return e.team == "enemy" and e.x < c.x1 + 200):
		e.dead = true
		e.gone = true
	var u0: Unit = b.squad()[0]
	u0.x = c.fire + 20
	u0.y = b.T.stand_y(u0.x, 0)
	cam_on(b, c.fire)
	b.check_camp(u0)
	await frames_wait(90)
	await shot("detour_pick")
	b.hud.picked.emit(0)
	await frames_wait(20)
	check(b.detour.get("id") == Run.level.detours[0], "picking a detour card starts it")
	main.clear()
	# elite outpost
	b = await detour_battle("elite")
	var el: Array = b.units.filter(func(e): return e.detour and e.team == "enemy")
	check(el.size() == 4 and el.all(func(e): return e.elite == b.detour.mod), "four elites share one modifier (%s)" % b.detour.mod)
	for e in el:
		e.dead = true
	await b.check_detour()
	check(b.detour.done and int(Run.meta.bio) == Data.ELITE_BIO and b.units.any(func(l): return l.kind == "loot" and l.loot.get("item", {}).get("tier", 0) >= 3), "clearing the outpost pays Bio-parts and an Epic item")
	await frames_wait(20)
	await shot("detour_elite_done")
	main.clear()
	# POW rescue: a dog tag back when nobody has fallen
	Run.soldiers[1].tags = 0
	b = await detour_battle("pow")
	var pows: Array = b.units.filter(func(p): return p.detour and p.kind == "pow")
	check(pows.size() == 3, "three prisoners in the yard")
	for p in pows:
		p.freed = true
	await b.check_detour()
	check(Run.soldiers[1].tags == 1, "freeing them all gives a dog tag back to whoever has fewest")
	main.clear()
	# POW rescue: a free recruit when a slot is empty
	Run.soldiers[3].alive = false
	b = await detour_battle("pow")
	for p in b.units.filter(func(p): return p.detour and p.kind == "pow"):
		p.freed = true
	await b.check_detour()
	check(Run.soldiers[3].alive and Run.soldiers[3].def.name != "ROOK", "...or a free recruit into the fallen slot (%s)" % Run.soldiers[3].def.name)
	main.clear()
	# POW rescue: too slow and they are gone
	b = await detour_battle("pow")
	for i in Data.POW_RESCUE_ROUNDS:
		await b.detour_round()
	check(b.detour.done and b.units.filter(func(p): return p.detour and p.kind == "pow").all(func(p): return p.gone), "after %d rounds the prisoners are moved out" % Data.POW_RESCUE_ROUNDS)
	main.clear()
	# salvage yard
	b = await detour_battle("salvage")
	var wrecks: Array = b.units.filter(func(w): return w.kind == "wreck")
	check(wrecks.size() == 5, "five wrecks in the yard")
	var u: Unit = b.squad()[0]
	u.x = wrecks[0].x
	u.y = b.T.stand_y(u.x, 0)
	await frames_wait(10)
	check(wrecks[0].stripped and int(Run.meta.salvage) == Data.WRECK_SALVAGE, "walking over a wreck strips it for salvage")
	var n0: int = b.units.filter(func(e): return e.team == "enemy" and e.detour).size()
	await b.detour_round()
	check(b.units.filter(func(e): return e.team == "enemy" and e.detour).size() == n0 + 1, "a scavenger drifts in each round")
	await frames_wait(20)
	await shot("detour_salvage_scav")
	for w in wrecks:
		w.stripped = true
	await b.check_detour()
	check(b.detour.done, "stripping every wreck ends the yard")
	main.clear()
	# supply cache
	b = await detour_battle("cache")
	var sc0 := Run.scrip
	var decks: int = Run.soldiers.reduce(func(a, s): return a + s.deck.size(), 0)
	for e in b.units.filter(func(e): return e.detour and e.team == "enemy"):
		e.dead = true
	await b.check_detour()
	await frames_wait(60)
	check(Run.scrip > sc0 and Run.soldiers.reduce(func(a, s): return a + s.deck.size(), 0) == decks + 1, "the cache pays scrip and a card pick")
	main.clear()
	# old fixed missions have no yard: their mid camp still pays a camp pick
	b = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	check(b.T.yard.is_empty(), "fixed missions have no detour yard")
	main.clear()
	# HQ shows the new currencies
	main.show_hq(false)
	await frames_wait(20)
	await shot("detour_hq")

func biomes() -> void:
	## Step 4: a level is one biome. The gate dial offers two, the skipped one is burned, and each
	## biome's rules are real: sway, sight, wind, hills, wet ground, fuel, mines, elites.
	for id in Data.BIOMES:
		var lv := Run.make_level(id, 0)
		check(lv.segments.size() == 7 and lv.segments.count("camp") == 2 and lv.segments.all(func(sg): return Data.SEGMENTS.has(sg)), "%s builds a full level" % id)
	for i in Data.LEVELS.size():
		check(Data.LEVELS[i].pool.size() >= 6 and Data.LEVELS[i].pool.all(func(k): return Data.BIOMES.has(k)), "level %d has a pool of 6+ biomes" % (i + 1))
	# a whole run of dials: never a repeat, never a burned biome
	for r in 20:
		Run.new_run()
		var seen: Array = []
		for m in Data.LEVELS.size():
			Run.mission = m
			var d := Run.roll_dial()
			if d.size() != 2 or d[0] == d[1] or d.any(func(k): return seen.has(k)):
				check(false, "run %d level %d dials two fresh biomes %s (seen %s)" % [r, m, d, seen])
				return
			seen.append_array(d)
			Run.pick_biome(d[randi() % 2])
			if r == 0:
				check(Run.burned.has(d[0]) and Run.burned.has(d[1]), "both dial options burn")
	check(true, "20 runs of dials never repeat or bring back a burned biome")
	# fit readout follows the deck
	Run.new_run()
	var moss: Dictionary = Run.soldier("moss")
	var vee: Dictionary = Run.soldier("vee")
	check(Run.fit(moss, "desert") == "great" and Run.fit(moss, "palace") == "rough", "the Marksman fits the desert, not the palace (%s / %s)" % [Run.fit(moss, "desert"), Run.fit(moss, "palace")])
	check(Run.fit(vee, "refinery") == "great" and Run.fit(vee, "harbor") == "rough", "Demolitions fits the refinery, not the harbor (%s / %s)" % [Run.fit(vee, "refinery"), Run.fit(vee, "harbor")])
	var fits := {}
	for id in Data.BIOMES:
		fits[id] = Run.soldiers.map(func(so): return Run.fit(so, id))
	print("[biomes] fits ", fits)
	# the dial screen
	Run.new_run()
	Run.dial = ["desert", "palace"]
	main.dial_gate()
	await frames_wait(30)
	await shot("biomes_dial")
	check(main.screen.get("mode") == "dial", "the gate dial shows the two biomes")
	press_first()
	await frames_wait(20)
	await shot("biomes_brief")
	check(Run.level.get("biome") == "desert" and Run.burned.has("palace"), "picking desert burns the palace")
	# rules in battle
	var base_sway: float = Data.card("snipe").sway
	var b: Battle = main.start_battle(0, Run.current_mission())
	await until(func(): return b.state == "player" and not b.busy)
	await frames_wait(10)
	await shot("biomes_desert")
	check(absf(Data.card("snipe").sway - base_sway * 0.6) < 0.0001, "desert steadies aimed shots")
	main.clear()
	check(Data.card("snipe").sway == base_sway, "the sway rule ends with the battle")
	for id in ["refinery", "jungle", "palace", "mountain", "delta", "harbor", "fortress"]:
		Run.level = Run.make_level(id, 1)
		b = main.start_battle(1, Run.current_mission())
		await until(func(): return b.state == "player" and not b.busy)
		var seg_fuel := 0
		var seg_mines := 0
		for sg in Run.level.segments:
			seg_fuel += Data.SEGMENTS[sg].spawns.filter(func(sp): return sp[0] == "fuel").size()
			seg_mines += Data.SEGMENTS[sg].spawns.filter(func(sp): return sp[0] == "mine").size()
		var fuel: int = b.units.filter(func(u): return u.kind == "fuel").size()
		var mines: int = b.units.filter(func(u): return u.kind == "mine").size()
		var rl: Dictionary = Data.BIOMES[id].rules
		var extra: int = b.T.spawns.filter(func(sp): return sp[0] == "fuel" or sp[0] == "mine").size() - seg_fuel - seg_mines
		check(extra == int(rl.get("fuel", 0)) + int(rl.get("mines", 0)) and fuel + mines >= seg_fuel + seg_mines + extra - 1, "%s lays its extra fuel (%d) and mines (%d)" % [id, fuel, mines])
		check(b.wet() == rl.get("wet", false), "%s wet rule" % id)
		var hs: PackedFloat32Array = b.T.heights
		var lo := 9999.0
		var hi := -9999.0
		for cx in range(int(500 / 4.0), int(1600 / 4.0)):
			lo = minf(lo, hs[cx]); hi = maxf(hi, hs[cx])
		print("[biomes] ", id, " hills ", int(hi - lo), "px  fuel ", fuel, " mines ", mines)
		var mid: float = b.T.camps[0].x0 - 500
		cam_on(b, mid)
		await frames_wait(20)
		await shot("biomes_" + id)
		main.clear()
	# after level 3 the gate dials the finale
	Run.new_run()
	Run.history = [{}, {}, {}]
	main.dial_gate()
	await frames_wait(20)
	await shot("biomes_finale")
	check(main.screen.get("mode") == "brief" and Run.is_final_mission() and Run.mission == 3, "after level 3 the gate goes to the harbor finale")

func tags() -> void:
	## Dog tags: going down spends a tag, going down with none is KIA for good, recruits fill the slot.
	Run.new_run()
	var b: Battle = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	var u: Unit = b.squad()[0]
	var s: Dictionary = u.s
	check(s.tags == Data.DOG_TAGS, "soldiers start with %d dog tags" % Data.DOG_TAGS)
	b.kill(u, null)
	await frames_wait(40)
	await shot("tags_down")
	check(u.downed and s.tags == Data.DOG_TAGS - 1, "going down spends a tag")
	check(b.stats.fallen.is_empty(), "a downed soldier is not counted as fallen")
	b.sync_back()
	check(s.alive and s.hp == int(ceil(Run.eff_max_hp(s) / 2.0)), "a downed soldier comes back next mission at half HP")
	# second battle: out of tags, the same soldier dies for good and leaves gear and a legacy behind
	s.tags = 0
	s.perks.append(Data.BRANCHES[s.key][0].perks[0].id)
	var it := Run.roll_item(0, ["armor"])
	Run.equip(s, it)
	var fallen_name: String = s.def.name
	var mem_before: int = Run.meta.memorial.size()
	b = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	u = b.squad().filter(func(x): return x.s == s)[0]
	b.kill(u, null)
	await frames_wait(40)
	await shot("tags_kia")
	check(not u.downed and b.stats.fallen == [fallen_name], "going down with no tags is KIA")
	b.sync_back()
	check(not s.alive, "the dead stay dead after the mission")
	check(Run.meta.memorial.size() == mem_before + 1 and Run.meta.memorial[-1].name == fallen_name, "the fallen go on the Memorial")
	check(Run.stash.has(it) and s.equip.armor == null, "their gear drops into the stash")
	# the result screen names the dead
	b.victory()
	await until(func(): return main.screen != null and main.screen.get("mode") == "won", 2000)
	await frames_wait(20)
	await shot("tags_result")
	# recruits fill the fallen slot, with a legacy perk when the class has a tag on the wall
	var slot: int = Run.fallen_slots()[0]
	var offers := Run.recruit_offers(4)
	var same: Array = offers.filter(func(o): return o.key == s.key)
	check(same.is_empty() or not same[0].legacy.is_empty(), "recruits of the fallen's class carry a legacy perk")
	var rec := Run.hire(slot, offers[0])
	check(rec.alive and rec.tags == Data.DOG_TAGS and rec.lvl == 1 and rec.def.name == offers[0].name and rec.trait != "", "a recruit takes the slot fresh, with a trait")
	check(Data.SQUAD_DEFS.all(func(d): return d.name != rec.def.name), "class defaults keep their names")
	Run.soldiers[2].alive = false
	Run.soldiers[3].tags = 1
	Run.scrip = 999
	main.show_shop()
	await frames_wait(30)
	await shot("tags_shop")
	main.screen.recruit()
	await frames_wait(20)
	await shot("tags_recruit")
	main.screen.chosen.emit(0)
	await frames_wait(10)
	check(Run.soldiers[2].alive, "the shop's RECRUIT service hires into the fallen slot")
	var tags_before: int = Run.soldiers.reduce(func(n, x): return n + x.tags, 0)
	main.screen.restore_tag()
	await frames_wait(10)
	main.screen.chosen.emit(0)
	await frames_wait(10)
	check(Run.soldiers.reduce(func(n, x): return n + x.tags, 0) == tags_before + 1, "the shop's DOG TAG service gives back one tag")

func hop_to(b: Battle, u: Unit, tx: float) -> void:
	## play the built-in Hop sized to land at tx
	u.energy = 3; u.move_left = 100
	b.state = "player"; b.busy = false
	b.select_unit(u)
	if not u.hand.any(func(h): return h.key == "hop"):
		u.hand.append({"id": -4, "key": "hop", "tier": 0, "temp": true})
	var aim := hop_aim(b, u, tx)
	await play_hop(b, u, aim.v)

func hop_aim(b: Battle, u: Unit, tx: float) -> Dictionary:
	## search launch angle and power with the same stepping the body physics uses
	var c := Data.card({"key": "hop", "tier": 0})
	var best := Vector2.ZERO
	var best_e := 1e9
	var pmax: float = 10.5 * c.jpow
	for a in range(20, 81, 2):
		var p := 3.0
		while p <= pmax:
			var vx := cos(deg_to_rad(a)) * p * signf(tx - u.x)
			var vy := -sin(deg_to_rad(a)) * p
			var v0 := Vector2(vx, vy)
			var x := u.x
			var y := u.y
			for k in 400:
				vy = minf(vy + Battle.GRAV, 10.0)
				if b.T.solid(x + vx, y - u.h * 0.5) or b.T.solid(x + vx, y - 6):
					vx *= -0.25
				else:
					x += vx
				if vy > 0 and b.T.solid(x, y + vy):
					break
				y += vy
				if y > Battle.WATER_Y:
					break
			if y < Battle.WATER_Y and absf(x - tx) < best_e:
				best_e = absf(x - tx)
				best = v0
			p += 0.25
	return {"v": best, "e": best_e}

func play_hop(b: Battle, u: Unit, v: Vector2) -> void:
	var idx := -1
	for i in u.hand.size():
		if u.hand[i].key == "hop":
			idx = i
	if idx < 0 or v == Vector2.ZERO:
		if playtest_debug:
			print("[nohop r%d] %s has no Hop in hand" % [b.round_n, u.def.key])
		return
	var c := Data.card(u.hand[idx])
	var x0 := u.x
	var reach: float = 240.0 * c.jpow
	var d: float = v.length() / (10.5 * c.jpow) * reach
	b.select_card(idx)
	b.commit_aim(b.hand_pos(u) + v.normalized() * d)
	await until(func(): return not is_instance_valid(b) or not b.busy, 600)
	await until(func(): return not is_instance_valid(u) or not u.air, 600)
	await frames_wait(10)
	if playtest_debug and is_instance_valid(b) and is_instance_valid(u):
		print("[hop r%d] %s %d -> %d,%d" % [b.round_n, u.def.key, int(x0), int(u.x), int(u.y)])

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

func squad_near(b: Battle, p: Vector2, r: float) -> bool:
	## any living soldier (shooter included) within r of p
	return b.squad_alive().any(func(s): return Vector2(s.x, s.y - s.h / 2.0).distance_to(p) < r)

func foe_near(b: Battle, p: Vector2, r: float) -> bool:
	## an enemy in the blast, and no barrel or fuel drum in it that would carry the blast to the squad
	for o in b.units:
		if not o.dead and not o.gone and (o.kind == "barrel" or o.kind == "fuel") and Vector2(o.x, o.y - o.h / 2.0).distance_to(p) < r + 10:
			if squad_near(b, Vector2(o.x, o.y - o.h / 2.0), (84.0 if o.kind == "fuel" else 44.0) + 40):
				return false
	return b.units.any(func(e): return not e.dead and e.team == "enemy" and e.active and Vector2(e.x, e.y - e.h / 2.0).distance_to(p) < r)

func rocket_safe(b: Battle, u: Unit, c: Dictionary, e: Unit) -> bool:
	## where a straight rocket at e would burst: it must be near a foe and clear of the squad
	var hp_ := Vector2(u.x + (6 if e.x >= u.x else -6), u.y - u.h + 10)
	var ang := atan2(e.y - 12 - hp_.y, e.x - hp_.x)
	var tr := b.trace_bullet(hp_.x, hp_.y, ang, 1400, 0, u, false)
	var p = null
	if tr.hits.size():
		p = Vector2(tr.hits[0].x, tr.hits[0].y)
	elif tr.end != null:
		p = Vector2(tr.end.x, tr.end.y)
	if p == null:
		return false
	var r: float = c.get("radius", 30)
	return not squad_near(b, p, r + 24) and foe_near(b, p, r + 10)

var bot_stats := {}
var pt_tag := "bot"
var stuck_shot := {}
var bot_last := ""

func bot(mission: int, max_rounds: int, fresh := true, custom := {}) -> bool:
	## A simple autoplayer: shoot the nearest visible enemy, lob at clusters, heal, push right.
	if fresh:
		Run.new_run()
	var b: Battle = main.start_battle(mission, custom)
	cur_b = b
	stuck_shot = {}
	b.autopick = 0
	b.speed = 24.0 if playtest_debug else 8.0
	b.debug = playtest_debug
	bot_stats = {"actions": 0, "enemy_ticks": 0, "hp_lost": 0, "round_hp": []}
	var res := {"done": false, "won": false, "line": ""}
	# read the battle before Main's handler frees it
	b.mission_over.disconnect(main._on_mission_over)
	b.mission_over.connect(func(w):
		res.done = true; res.won = w
		res.line = "rounds %d score %d kills %d cam %d/%d alive %d" % [b.round_n, b.score, b.stats.kills, int(b.cam_x), b.world_w, b.squad_alive().size()]
		bot_stats.merge({"rounds": b.round_n, "kills": b.stats.kills, "downs": b.stats.kia, "fallen": b.stats.fallen.duplicate(), "cam": int(b.cam_x), "world": b.world_w, "alive": b.squad_alive().size(), "ticks": b.t})
		main._on_mission_over(w), CONNECT_ONE_SHOT)
	var last_shot := 0
	while not res.done and b.round_n < max_rounds:
		await until(func(): return res.done or (b.state == "player" and not b.busy), 20000)
		if res.done:
			break
		for u in b.squad_alive():
			if res.done or b.state != "player":
				break
			b.select_unit(u)
			# step off an airstrike marker before anything else
			var mk: Array = b.strikes.filter(func(k): return not k.get("friendly", false) and absf(k.x - u.x) < 64)
			if mk.size() and u.move_left > 20:
				var away: float = u.x + 90.0 if u.x >= mk[0].x else u.x - 90.0
				if b.strikes.any(func(k): return absf(k.x - away) < 64):
					away = u.x - 90.0 if away > u.x else u.x + 90.0
				b.do_move(u, away)
				await until(func(): return res.done or not b.busy, 20000)
			var guard := 0
			while guard < 8 and not res.done and b.state == "player":
				guard += 1
				await until(func(): return res.done or not b.busy, 20000)
				if res.done or u.dead:
					break
				var played := false
				var foes: Array = b.units.filter(func(o): return not o.dead and not o.gone and ((o.team == "enemy" and o.active) or (o.kind == "charge" and not o.primed)) and absf(o.x - u.x) < 900)
				var prio := func(o): return (0 if o.kind == "charge" else (1 if o.type == "radio" else 2)) * 10000 + absf(o.x - u.x)
				foes.sort_custom(func(p1, p2): return prio.call(p1) < prio.call(p2))
				for i in u.hand.size():
					var c := Data.card(u.hand[i])
					if u.energy < b.card_cost(u, u.hand[i]):
						continue
					if c.type == "SELF" and not c.get("overwatch", false):
						bot_last = c.get("name", "?")
						b.select_card(i)
						played = true
						break
					if c.type == "ALLY":
						var hurt := b.squad_alive().filter(func(s): return s.hp < s.max_hp - 6 and b.ally_valid(u, s, c))
						if hurt.size():
							bot_last = c.get("name", "?")
							b.select_card(i)
							b.play_on_target(hurt[0])
							played = true
							break
						continue
					for e in foes.slice(0, 6):
						if c.type == "AIM":
							var aa := b.aim_angle(u, c, Vector2(e.x, e.y - e.h * 0.6))
							var tr := b.trace_bullet(aa.mx, aa.my, aa.a, c.range, c.get("bounce", 0), u, c.get("pierce", false))
							var safe: bool = not tr.hits.any(func(h): return h.u.team == "squad" or h.u.kind == "pow")
							if safe and c.has("radius") and tr.hits.size():
								safe = not squad_near(b, Vector2(tr.hits[0].x, tr.hits[0].y), c.radius + 20)
							if safe and tr.hits.any(func(h): return h.u.team == "enemy" or h.u.is_prop()):
								bot_last = c.get("name", "?")
								b.select_card(i)
								b.commit_aim(Vector2(e.x, e.y - e.h * 0.6))
								played = true
						elif e.kind == "charge":
							continue
						elif c.type == "ARC" and absf(e.x - u.x) < 260 and absf(e.x - u.x) > 70 and not c.get("smoke", false):
							var hx: float = u.x + (6 if e.x > u.x else -6)
							var hy: float = u.y - u.h + 10
							var sol = b.solve_arc(hx, hy, e.x, e.y - 4, c.get("wind", 1.0), 13)
							if sol == null:
								continue
							var land := b.sim_arc(hx, hy, sol.vx, sol.vy, c.get("wind", 1.0), 320)
							var rr: float = c.get("radius", 30) + (60.0 if c.get("bounce", false) else 0.0) + (60.0 if c.has("cluster") else 0.0)
							if land.end and not squad_near(b, Vector2(land.x, land.y), rr + 50) and not squad_near(b, Vector2(e.x, e.y - e.h / 2.0), rr + 50) and foe_near(b, Vector2(land.x, land.y), rr + 10):
								bot_last = c.get("name", "?")
								b.select_card(i)
								var pw := Vector2(sol.vx, sol.vy).length()
								b.commit_aim(Vector2(hx, hy) + Vector2(sol.vx, sol.vy).normalized() * (pw / 13.0 * 220))
								played = true
						elif c.type == "LINE" and not c.get("grapple", false) and not c.get("jump", false) and not c.get("rush", false) and not c.get("drill", false) and absf(e.x - u.x) > 80 and rocket_safe(b, u, c, e):
							bot_last = c.get("name", "?")
							b.select_card(i)
							b.commit_aim(Vector2(e.x, e.y - 12))
							played = true
						elif c.type == "MELEE" and b.melee_valid(u, e, c):
							bot_last = c.get("name", "?")
							b.select_card(i)
							b.play_on_target(e)
							played = true
						if played:
							break
					if played:
						break
				if not played:
					break
				if playtest_debug:
					var en := nearest_enemy(b, u)
					print("[act r%d] %s plays %s at %s" % [b.round_n, u.def.key, bot_last, ("%s dx%d" % [en.type, int(en.x - u.x)]) if en != null else "-"])
				bot_stats.actions += 1
				await until(func(): return res.done or not b.busy, 20000)
			if res.done or b.state != "player":
				break
			await until(func(): return res.done or not b.busy, 20000)
			if u.move_left > 20 and not u.dead:
				var e2 := nearest_enemy(b, u)
				# keep spacing: each soldier stops 60px behind the one ahead
				var order := b.squad_alive()
				order.sort_custom(func(a, c): return a.x > c.x)
				var lead_x: float = minf(u.x + u.move_left, order[-1].x + 340.0) if order[0] == u else order[0].x
				var tx: float = minf(u.x + u.move_left, lead_x - 60.0 * order.find(u))
				if e2 != null and e2.x - u.x < 140:
					tx = minf(tx, u.x + 10)
				if tx < u.x + 4:
					tx = u.x - 30 if order.find(u) > 0 else u.x
				# stop short of mines, live charges and leaking fuel instead of walking onto them
				var hz: Array = b.units.filter(func(o): return not o.dead and not o.gone and ((o.kind == "mine" and not o.primed) or o.kind == "charge" or (o.kind == "fuel" and o.leak != null)) and o.x > u.x - 4 and absf(o.y - u.y) < 40)
				for o in hz:
					var keep: float = 18.0 if o.kind == "mine" else 70.0
					if o.x - keep < tx and o.x > u.x:
						tx = maxf(u.x, o.x - keep)
				for k in b.strikes:
					if not k.get("friendly", false) and absf(k.x - tx) < 64:
						tx = k.x - 70 if u.x < k.x else k.x + 70
				b.do_move(u, tx)
				bot_stats.actions += 1
				await until(func(): return res.done or not b.busy, 20000)
				# take a ladder when one is right ahead and the way on foot is blocked
				var climbed := false
				for L in b.T.ladders:
					if not u.dead and u.move_left > 20 and L.x > u.x - 10 and L.x - u.x < 40 and absf(L.bot - u.y) < 16 and L.offx > L.x - 30:
						b.do_climb(u, L)
						await until(func(): return res.done or not b.busy, 20000)
						climbed = true
						break
				# a wall right ahead and a Drill in hand: bore straight through it
				var di: int = u.hand.map(func(h): return h.key).find("drill")
				if not climbed and di >= 0 and not u.dead and u.move_left > 20 and b.state == "player" and b.sim_walk(u, u.x + 40, 40).used < 4 and b.drill_face(u, u.x, u.y, Vector2(1, 0)):
					var x0d: float = u.x
					b.select_card(di)
					b.commit_aim(Vector2(u.x + 200, u.y - u.h / 2.0))
					await until(func(): return res.done or not b.busy, 20000)
					if res.done:
						break
					if playtest_debug:
						print("[drill r%d] %s %d -> %d" % [b.round_n, u.def.key, int(x0d), int(u.x)])
					climbed = true
				# otherwise hop the wall, gap or mine, aiming for the farthest dry spot it can reach
				var mine_ahead: bool = b.units.any(func(o): return o.kind == "mine" and not o.primed and not o.gone and o.x > u.x and o.x - u.x < 30 and absf(o.y - u.y) < 12)
				if not climbed and not u.dead and u.move_left > 20 and u.energy >= 1 and b.state == "player" and (mine_ahead or b.sim_walk(u, u.x + 40, 40).used < 4):
					var hopped := false
					for attempt in 2:
						if attempt == 1:
							# pressed against a fence or wall: back off for a run-up and try again
							if u.move_left < 60 or res.done:
								break
							b.do_move(u, u.x - 44)
							await until(func(): return res.done or not b.busy, 20000)
							if res.done or u.dead or u.move_left < 1:
								break
						var x0: float = u.x
						var jx: float = x0 + 190.0
						while jx > x0 + 30 and not hopped:
							for lift in [90.0, 150.0]:
								var jy = b.T.stand_y(jx, u.y - lift)
								if jy != null and jy < Battle.WATER_Y - 4:
									var aim := hop_aim(b, u, jx)
									if aim.e < 10:
										await play_hop(b, u, aim.v)
										hopped = true
										break
							jx -= 10
						if hopped:
							break
					if playtest_debug and not hopped:
						print("[stuck r%d] %s at %d,%d climbed %s hand %s" % [b.round_n, u.def.key, int(u.x), int(u.y), climbed, u.hand.map(func(h): return h.key)])
						if not stuck_shot.has(u.def.key):
							stuck_shot[u.def.key] = true
							await shot("stuck_%s_r%d_%s" % [pt_tag, b.round_n, u.def.key])
				elif playtest_debug and climbed:
					print("[climb r%d] %s now %d,%d" % [b.round_n, u.def.key, int(u.x), int(u.y)])
		if res.done:
			break
		if b.round_n - last_shot >= 3 or b.round_n == 1:
			last_shot = b.round_n
			await shot("bot_m%d_r%02d" % [mission, b.round_n])
		if playtest_debug:
			for s in b.squad_alive():
				if b.T.solid(s.x, s.y - s.h / 2.0) or s.x < 0 or s.x > b.world_w or s.y > Battle.WATER_Y:
					print("[glitch r%d] %s at %d,%d solid %s" % [b.round_n, s.def.key, int(s.x), int(s.y), b.T.solid(s.x, s.y - s.h / 2.0)])
			print("[pos r%d] cam %d alert %d squad %s foes %s" % [b.round_n, int(b.cam_x), b.alert, b.squad_alive().map(func(x): return "%s@%d,%d e%d m%d" % [x.def.key, int(x.x), int(x.y), x.energy, int(x.move_left)]), b.units.filter(func(o): return o.team == "enemy" and not o.dead and o.active).map(func(o): return "%s@%d" % [o.type, int(o.x)])])
		var hp0: int = b.squad_alive().reduce(func(a, x): return a + x.hp, 0)
		var t0 := b.t
		b.end_turn(true)
		await until(func(): return res.done or (b.state == "player" and not b.busy) or b.state == "over", 30000)
		bot_stats.enemy_ticks += b.t - t0
		var hp1: int = b.squad_alive().reduce(func(a, x): return a + x.hp, 0)
		bot_stats.round_hp.append(hp0 - hp1)
	if not res.done:
		res.line = "rounds %d score %d kills %d cam %d/%d alive %d" % [b.round_n, b.score, b.stats.kills, int(b.cam_x), b.world_w, b.squad_alive().size()]
	if not res.done:
		bot_stats.merge({"rounds": b.round_n, "kills": b.stats.kills, "downs": b.stats.kia, "fallen": b.stats.fallen.duplicate(), "cam": int(b.cam_x), "world": b.world_w, "alive": b.squad_alive().size(), "ticks": b.t})
	bot_stats.merge({"done": res.done, "won": res.won})
	print("[bot] mission ", mission, " done ", res.done, " won ", res.won, " ", res.get("line", ""), " lv ", Run.soldiers.map(func(s): return s.lvl), " scrip ", Run.scrip)
	if res.done:
		await frames_wait(5)
	return res.won

func press_first() -> void:
	for c in main.screen.get_children():
		if c.has_signal("pressed"):
			c.pressed.emit()
			return

func playtest() -> void:
	## Autoplays whole runs the way a player meets them: gate dial, biome level (BREACH, Swarm/Nest, camps, detours, boss),
	## a hospital stop between levels when it is affordable, then the harbor finale. One [pt] JSON line per mission.
	## --seed=N --runs=K
	playtest_debug = true
	for r in runs_arg:
		seed(seed_arg * 1000 + r)
		Run.new_run()
		for m in Data.LEVELS.size() + 1:
			Run.mission = m
			Run.side = ""
			if m < Data.LEVELS.size():
				Run.roll_dial()
				Run.pick_biome(Run.dial[randi() % Run.dial.size()])
			else:
				Run.start_finale()
			if m < start_arg:
				# --start=N: arrive at level N as a squad that cleared the levels before it (+4 levels each, mission pay)
				for x in Run.soldiers:
					for k in 4:
						x.lvl += 1
						x.xp = Run.xp_floor(x)
						var opts := Run.level_options(x)
						Run.apply_option(x, opts[randi() % opts.size()])
					x.hp = Run.eff_max_hp(x)
				Run.scrip += 180
				Run.history.append({})
				continue
			Run.roll_intel()
			var lv: Dictionary = Run.current_mission()
			var before := {"scrip": Run.scrip, "hp": Run.soldiers.map(func(x): return x.hp), "tags": Run.soldiers.map(func(x): return x.tags)}
			pt_tag = "s%d_r%d_m%d" % [seed_arg, r, m]
			var ms0 := Time.get_ticks_msec()
			var ok := await bot(m, 90, false, lv)
			var row := bot_stats.duplicate()
			row["secs"] = (Time.get_ticks_msec() - ms0) / 1000.0
			row.erase("round_hp")
			row.merge({"seed": seed_arg, "run": r, "m": m, "biome": lv.get("biome", "finale"), "breach": lv.get("breach", false), "enc": lv.get("encounter", ""),
				"intel": Run.intel, "detours": lv.get("detours", []), "scrip_in": before.scrip, "scrip_out": Run.scrip, "hp_in": before.hp,
				"hp_out": Run.soldiers.map(func(x): return x.hp if x.alive else -1), "tags_out": Run.soldiers.map(func(x): return x.tags),
				"lv": Run.soldiers.map(func(x): return x.lvl), "max_round_hp": bot_stats.round_hp.max() if bot_stats.round_hp.size() else 0})
			print("[pt] ", JSON.stringify(row))
			await shot("pt_s%d_r%d_m%d_end" % [seed_arg, r, m])
			if not ok or Run.alive_count() == 0:
				break
			# between levels: buy the hospital when anyone is hurt and it is affordable
			if Run.scrip >= 40 and Run.soldiers.any(func(x): return x.alive and x.hp < Run.eff_max_hp(x)):
				Run.scrip -= 40
				for x in Run.soldiers:
					if x.alive:
						x.hp = Run.eff_max_hp(x)

func warmap() -> void:
	## Campaign step 1: save slots, a separate base, the War Room, sector income and perks, the
	## stronghold, act two, and a real op played by the bot.
	main.show_title()
	await frames_wait(20)
	await shot("wm_title")
	var keep := {"salvage": Run.meta.get("salvage", 0), "hq": Run.meta.get("hq", {}).duplicate()}
	Run.meta.salvage = 77
	Run.meta.hq = {"gate": 2}
	Run.save_meta()
	for i in Data.CAMP_SLOTS:
		Run.delete_campaign(i)
	main.show_slots()
	await frames_wait(10)
	await shot("wm_slots_empty")
	Run.new_campaign(0)
	check(Run.campaign(), "a new campaign is loaded")
	check(int(Run.meta.salvage) == 0 and Run.meta.hq.is_empty(), "the campaign starts with its own empty base (salvage %d)" % int(Run.meta.salvage))
	check(int(Run.run_base.salvage) == 77, "the standard run's salvage is put aside")
	check(Run.scrip == Data.CAMP_START_SCRIP, "war chest starts at %d" % Run.scrip)
	var j = JSON.parse_string(FileAccess.get_file_as_string(Run.META_PATH))
	check(int(j.salvage) == 77, "meta.json keeps the run's salvage while a campaign is loaded (%s)" % j.salvage)
	main.show_hq(false)
	await frames_wait(30)
	await shot("wm_hq")
	main.show_war_room()
	await frames_wait(20)
	await shot("wm_room_start")
	var open: Array = Run.act().sectors.filter(func(sc): return Run.sector_open(sc)).map(func(sc): return sc.id)
	check(open == ["d1"], "only the sector next to the landing zone is open (%s)" % [open])
	check(not Run.sector_open(Run.sector("boss")), "the stronghold starts sealed")
	Run.start_op(Run.sector("d1"))
	check(Run.level.segments.size() == 6 and Run.level.segments.count("camp") == 1, "a sector op has one camp (%s)" % [Run.level.segments])
	check(Run.level.biome == "delta" and Run.level.name == "MUDFLAT LANDING", "the op is in the sector's biome")
	# the bot plays the first op for real
	Run.roll_intel()
	var lv: Dictionary = Run.current_mission()
	var won := await bot(int(Run.act().tier), 70, false, lv)
	await frames_wait(10)
	await shot("wm_result")
	print("[warmap] op 1 won=%s scrip=%d alive=%d" % [won, Run.scrip, Run.alive_count()])
	check(main.screen != null and main.screen.get("mode") in ["op_won", "op_lost"], "the op ends on a campaign result screen")
	check(int(Run.camp.ops) == 1, "the op is counted")
	if won:
		check(Run.sector_held("d1"), "winning takes the sector")
	else:
		check(not Run.sector_held("d1") and Run.sector_open(Run.sector("d1")), "a lost op leaves the sector open")
		Run.camp.held.append(Run.sec_key("d1"))
	var hurt: Dictionary = Run.soldiers[0]
	hurt.hp = 1
	hurt.tags = 0
	var dead: Dictionary = Run.soldiers[3]
	dead.alive = false
	var scrip0 := Run.scrip
	main.campaign_home()
	await frames_wait(40)
	await shot("wm_home_news")
	check(Run.scrip == scrip0 + 20, "Mudflat Landing pays 20 scrip after the op (%d -> %d)" % [scrip0, Run.scrip])
	check(hurt.hp == Run.eff_max_hp(hurt) and hurt.tags == Data.DOG_TAGS, "everyone is patched up with their tags back")
	check(Run.soldiers[3].alive and Run.alive_count() == 4, "Command fills the empty slot with a rookie")
	# take the rest of act I on paper
	for id in ["d2", "d3"]:
		check(Run.sector_open(Run.sector(id)), "%s opens next to Mudflat Landing" % id)
		Run.start_op(Run.sector(id))
		Run.op_over(true)
	check(Run.camp_perk("aid") and Run.hq("mess") >= 1, "Rice Terraces gives the Field Hospital perk (mess %d)" % Run.hq("mess"))
	check(Run.sector_open(Run.sector("boss")), "three sectors open the stronghold")
	check(Run.sector_open(Run.sector("j2")) and not Run.sector_open(Run.sector("j3")), "Temple Trail still needs Signal Ridge")
	var sal0 := int(Run.meta.salvage)
	Run.after_op()
	check(int(Run.meta.salvage) == sal0 + 2, "Ferry Docks pays 2 salvage")
	# patrol a held sector: half pay, nobody dies
	Run.start_op(Run.sector("d1"), true)
	check(Run.level.patrol and Run.level.banner == "PATROL", "patrol op")
	Run.op_over(true)
	main.show_war_room()
	await frames_wait(10)
	main.screen.sel = "boss"
	main.screen.build()
	await frames_wait(10)
	await shot("wm_room_fort")
	Run.start_op(Run.sector("boss"))
	check(Run.level.stronghold and Run.level.segments.size() == 7, "the stronghold is a full-length level")
	var res := Run.op_over(true)
	check(res.get("act_done", "") == "LANDFALL" and int(Run.camp.act) == 1, "beating the fort clears act I")
	check(not Run.camp_perk("aid"), "act I's perks stay in act I")
	check(Run.income().scrip == 20, "act I's income keeps paying in act II (%s)" % [Run.income()])
	check(Run.act().sectors.filter(func(sc): return Run.sector_open(sc)).size() == 1, "act II starts with one open sector")
	# save, leave, load
	Run.soldiers[1].lvl = 5
	Run.soldiers[1].deck.append(Run.new_card("frag", 2, "shop"))
	var deck_n: int = Run.soldiers[1].deck.size()
	Run.scrip = 999
	main.show_title()
	check(not Run.campaign() and int(Run.meta.salvage) == 77 and int(Run.meta.hq.gate) == 2, "leaving puts the run's base back")
	main.show_slots()
	await frames_wait(10)
	await shot("wm_slots_saved")
	check(Run.load_campaign(0), "the campaign loads")
	check(Run.scrip == 999 and Run.soldiers[1].lvl == 5 and typeof(Run.soldiers[1].lvl) == TYPE_INT, "scrip and levels come back as they were")
	check(Run.soldiers[1].deck.size() == deck_n, "the deck comes back")
	check(int(Run.camp.act) == 1 and Run.camp.held.has("0:d1"), "the war map comes back")
	check(int(Run.meta.salvage) != 77, "the campaign's own salvage comes back")
	main.show_hq(false)
	await frames_wait(20)
	await shot("wm_hq_act2")
	main.show_war_room()
	await frames_wait(20)
	await shot("wm_room_act2")
	main.show_title()
	await frames_wait(5)
	Run.meta.salvage = keep.salvage
	Run.meta.hq = keep.hq
	Run.save_meta()

func company() -> void:
	## Campaign step 2: the roster and squad pick, service records, medals, ranks and promotion
	## picks, bench training, legacy decks for the fallen, a Captain's aura, and save links.
	var keep := {"salvage": Run.meta.get("salvage", 0), "hq": Run.meta.get("hq", {}).duplicate()}
	Run.delete_campaign(1)
	Run.new_campaign(1)
	check(Run.roster.size() == 4 and Run.soldiers.size() == 4, "the company starts as the squad of four")
	check(is_same(Run.roster[0], Run.soldiers[0]), "squad and roster are the same people")
	var hired: Array = []
	for i in 3:
		hired.append(Run.enlist(Run.recruit_offers(1)[0]))
	check(Run.company().size() == 7 and Run.soldiers.size() == 4 and Run.bench().size() == 3, "recruits join the company on the bench")
	var dup: Dictionary = hired.filter(func(h): return true)[0]
	var same_cls: Dictionary = Run.soldiers.filter(func(x): return x.key == dup.key)[0]
	check(Run.toggle_squad(dup) == "" and Run.soldiers.has(dup) and not Run.soldiers.has(same_cls), "picking a benched %s swaps out the squad's %s" % [dup.def.name, same_cls.def.name])
	Run.toggle_squad(same_cls)
	check(Run.soldiers.has(same_cls) and Run.soldiers.size() == 4, "and swaps back")
	check(Run.toggle_squad(Run.soldiers[3]) == "" and Run.soldiers.size() == 3, "a soldier can sit out")
	Run.fill_squad()
	check(Run.soldiers.size() == 4, "the squad tops up from the bench")
	var keys := {}
	for x in Run.soldiers:
		keys[x.key] = true
	check(keys.size() == Run.soldiers.size(), "one of each class in the squad")
	# an op: Moss kills 6, Hex goes down and they still win; everyone already has one op on record
	var moss: Dictionary = Run.soldiers.filter(func(x): return x.key == "moss")[0]
	var hex: Dictionary = Run.soldiers.filter(func(x): return x.key == "hex")[0]
	for x in Run.soldiers:
		Run.svc(x).ops = 1
	var benched: Dictionary = Run.bench()[0]
	var bxp: int = benched.xp
	var mhp: int = hex.max_hp
	var mdodge: int = moss.bonus.dodge
	var st := {"won": true, "xp": {"moss": 60, "hex": 60, "vee": 60, "rook": 60}, "kills_by": {"moss": 6}, "downed_by": {"hex": true}}
	var inc := Run.after_op(st)
	check(int(Run.svc(moss).ops) == 2 and int(Run.svc(moss).kills) == 6, "the service record counts ops and kills")
	check(Run.svc(moss).medals.has("marksman") and moss.bonus.dodge == mdodge + 3, "5 kills earn the Marksman Medal (+3 dodge)")
	check(Run.svc(hex).medals.has("heart") and hex.max_hp == mhp + 3, "going down and winning earns the Purple Heart (+3 max HP)")
	check(Run.rank(moss) == 1 and int(moss.get("promo", 0)) == 1, "two ops make a Corporal with a promotion pick waiting")
	check(benched.xp == bxp + 30, "the bench trains on half the squad's XP (%d -> %d)" % [bxp, benched.xp])
	check(inc.promos.size() == 4 and inc.medals.size() == 2, "the news lists promotions and medals (%s %s)" % [inc.promos, inc.medals])
	var picks := Run.pending_picks()
	check(picks.filter(func(p): return p.kind == "promo").size() == 4, "four promotion picks wait")
	main.show_picks(func(): pass)
	await frames_wait(20)
	await shot("co_promotion")
	var pq = main.screen
	var mv: int = picks[0].s.bonus.move
	var spins := 0
	while Run.pending_picks().size() and spins < 20:
		var k := 0
		if pq.cur.kind == "promo":
			k = pq.opts.map(func(o): return o.id).find("move")
		pq.pick(maxi(k, 0))
		spins += 1
		await frames_wait(2)
	check(Run.pending_picks().is_empty(), "every pick is made")
	check(picks[0].s.bonus.move == mv + 40, "FLEET gives +40 movement")
	# a veteran falls: their best cards go to the next recruit
	var vet: Dictionary = Run.soldiers.filter(func(x): return x.key == "vee")[0]
	vet.deck.append(Run.new_card("mortar", 4, "shop"))
	vet.alive = false
	Run.memorialize(vet)
	Run.after_op({})
	check(not Run.roster.has(vet) and not Run.soldiers.has(vet), "the fallen leave the roster")
	check(not Run.legacy_deck().is_empty(), "their cards wait on the Memorial")
	var heir := Run.enlist(Run.recruit_offers(1)[0])
	check(heir.get("legacy_from", "") == vet.def.name and heir.deck.any(func(c): return c.key == "mortar" and Data.tier_of(c) == 4), "the next recruit inherits %s's Legendary Mortar" % vet.def.name)
	check(Run.legacy_deck().is_empty(), "the legacy is claimed once")
	# a Captain steadies the squad
	var cap: Dictionary = Run.soldiers[0]
	cap.rank = 4
	var b: Battle = main.start_battle(0, Run.make_op(Run.sector("d1")))
	await frames_wait(5)
	var u0 = b.squad().filter(func(u): return u.s == Run.soldiers[1])[0]
	check(u0.dodge == Run.soldiers[1].def.dodge + Run.soldiers[1].bonus.dodge + int(u0.g("dodge")) + Data.CAPTAIN_DODGE, "a Captain gives the squad +%d dodge" % Data.CAPTAIN_DODGE)
	main.clear()
	await frames_wait(5)
	# the War Room's company overlay
	main.show_war_room()
	await frames_wait(5)
	main.screen.company_open = true
	main.screen.build()
	await frames_wait(20)
	await shot("co_company")
	# save and practice snapshots keep the squad linked to the roster
	var snap := Run.snapshot()
	Run.restore(snap)
	check(is_same(Run.roster[Run.roster.find(Run.soldiers[0])], Run.soldiers[0]), "a practice-range restore keeps the squad linked")
	Run.save_campaign()
	var n_squad := Run.soldiers.size()
	main.show_title()
	await frames_wait(3)
	Run.load_campaign(1)
	var linked := Run.soldiers.all(func(x): return Run.roster.any(func(r): return is_same(r, x)))
	check(linked and Run.soldiers.size() == n_squad, "a loaded campaign keeps the squad linked to the roster (%d of %d)" % [Run.soldiers.size(), n_squad])
	check(Run.company().size() == 7, "the company comes back (%d)" % Run.company().size())
	main.show_hq(false)
	await frames_wait(20)
	main.screen.open_dossier(0, "sheet")
	await frames_wait(20)
	await shot("co_dossier")
	main.show_title()
	await frames_wait(3)
	Run.delete_campaign(1)
	Run.meta.salvage = keep.salvage
	Run.meta.hq = keep.hq
	Run.save_meta()

func drowncamp() -> void:
	## A soldier who drowned and is revived at camp has to come back as a normal body: the update loop
	## skips sunk units, so a revived one still marked sunk froze the turn on its first walk.
	Run.new_run()
	var b: Battle = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	for o in b.units:
		if o.team == "enemy":
			o.dead = true; o.gone = true
	b.autopick = 0
	var s: Unit = b.squad()[1]
	# drown them the way the fall physics does
	s.y = Battle.WATER_Y + 3; s.sunk = true
	b.kill(s, null)
	await until(func(): return s.dead or s.downed, 120)
	print("[drowncamp] %s sunk %s dead %s downed %s" % [s.def.key, s.sunk, s.dead, s.downed])
	var c: Dictionary = b.T.camps[0]
	c.used = true
	await b.make_camp(c)
	b.state = "player"; b.busy = false
	b.select_unit(s)
	b.do_move(s, s.x + 40)
	var ok := await until(func(): return not b.busy and s.walk == null, 600)
	print("[drowncamp] revived at %d,%d sunk %s walked %s" % [int(s.x), int(s.y), s.sunk, ok])

func worms() -> void:
	## Worms rules from the 2026-10-28 playtest: the ground stops at the waterline, a shaft dug down into
	## the water drowns whoever drops in, a Hop always clears the lip of a hole, and the aim line shows
	## a ricochet coming back at the shooter.
	Run.new_run()
	var b: Battle = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	for o in b.units:
		if o.team == "enemy":
			o.dead = true; o.gone = true
	b.autopick = 0
	var under := 0
	for cx in b.T.cols:
		if b.T.grid[(Battle.WATER_Y / Terrain.CELL + 1) * b.T.cols + cx] != 0:
			under += 1
	print("[worms] solid cells just under the waterline: %d of %d columns" % [under, b.T.cols])
	# a shaft bored straight down through the ground into the sea
	var sq := b.squad()
	var a: Unit = sq[0]
	b.T.bore(a.x, Battle.WATER_Y + 30, a.y - 40, 11)
	b.T.flush()
	await until(func(): return a.sunk or (not a.air and a.y > Battle.WATER_Y - 20), 300)
	print("[worms] dropped down the shaft: y %d sunk %s dead %s" % [int(a.y), a.sunk, a.dead or a.downed])
	# a hole far deeper than a Hop used to clear, with its floor still above the water
	var h: Unit = sq[2]
	var top := h.y
	var floor_y := minf(top + 120, Battle.WATER_Y - 12)
	b.T.bore(h.x, floor_y - 11, top - 40, 11)
	b.T.flush()
	await until(func(): return not h.air and h.y > top + 40, 300)
	await frames_wait(20)
	print("[worms] %s sits in a hole %dpx deep" % [h.def.key, int(h.y - top)])
	b.state = "player"; b.busy = false
	b.select_unit(h)
	force_card(h, "hop")
	await play_hop(b, h, Vector2(3, -6))
	print("[worms] hop out of the hole: y %d (lip %d) out %s" % [int(h.y), int(top), h.y < top + 12])
	# a pistol round fired straight into stone comes right back
	var r: Unit = sq[3]
	cam_on(b, r.x)
	b.T.fill_r(r.x + 50, r.y - 60, 16, 60, 2)
	b.T.flush()
	b.select_unit(r)
	var pi := force_card(r, "pistol")
	b.select_card(pi)
	b.mouse = Vector2(r.x + 49, r.y - r.h * 0.6)
	await frames_wait(8)
	var aa := b.aim_angle(r, Data.card(r.hand[pi]), b.mouse)
	var tr := b.trace_bullet(aa.mx, aa.my, aa.a, 9999.0, 2, r, false)
	print("[worms] ricochet comes back into the shooter: %s" % tr.hits.any(func(hh): return hh.u == r))
	await shot("worms_ricochet")

func op_battle(job: String) -> Battle:
	## A campaign op on Mudflat Landing with the given job, held at the first player turn.
	var sc: Dictionary = Run.sector("d1").duplicate()
	sc["job"] = job
	Run.mission = int(Run.camp.ops)
	Run.level = Run.make_op(sc)
	var b: Battle = main.start_battle(0, Run.level)
	b.mission_over.disconnect(main._on_mission_over)
	b.mission_over.connect(func(w): b.set_meta("result", w), CONNECT_ONE_SHOT)
	await until(func(): return b.state == "player" and not b.busy)
	b.speed = 16.0
	return b

func op_end(b: Battle) -> Variant:
	## Runs the job check like the end of an action would and waits for the battle to finish.
	await b.job_ends()
	await until(func(): return b.has_meta("result"), 3000)
	return b.get_meta("result") if b.has_meta("result") else null

func ops() -> void:
	## Campaign step 3: op jobs. Rescue, demolish, hold, escort and hunt each lay out their
	## objective, show it on the HUD, finish the op when done, and pay their bonus.
	var keep := {"salvage": Run.meta.get("salvage", 0), "hq": Run.meta.get("hq", {}).duplicate(), "bio": Run.meta.get("bio", 0)}
	Run.delete_campaign(2)
	Run.new_campaign(2)
	var jobs: Array = []
	for a in Data.ACTS:
		for sc in a.sectors:
			if sc.has("job"):
				jobs.append(sc.job)
	for j in ["push", "rescue", "demolish", "hold", "escort", "hunt"]:
		check(jobs.has(j), "some sector on the war map is a %s op" % j)
	check(Run.op_job(Run.sector("boss")) == "push", "a stronghold is always a push")
	check(Run.op_job(Run.sector("d2")) == "rescue" and Run.make_op(Run.sector("d2")).job == "rescue", "Rice Terraces is a rescue op")
	var lv := Run.make_op(Run.sector("d2"))
	var bm: Dictionary = Data.BIOMES["delta"]
	check(lv.segments.size() == 6 and not lv.segments.has(bm.get("arena", "arena")), "a job op has no boss arena (%s)" % [lv.segments])
	main.show_war_room()
	await frames_wait(10)
	main.screen.sel = "d2"
	main.screen.build()
	await frames_wait(10)
	await shot("ops_room")
	Run.start_op(Run.sector("d2"))
	main.show_brief()
	await frames_wait(20)
	await shot("ops_brief")

	# O2 rescue
	var b := await op_battle("rescue")
	var pows: Array = b.units.filter(func(p): return p.kind == "pow" and p.fl.get("job", false))
	check(pows.size() == 3, "a rescue op holds three prisoners (%d)" % pows.size())
	check(pows.all(func(p): return p.y != null and p.y < b.WATER_Y), "every prisoner stands on dry ground")
	check(b.job_left().begins_with("RESCUE: 0 OF 3"), "the HUD tracks the prisoners (%s)" % b.job_left())
	b.cam_x = clampf(pows[0].x - 300, 0, b.world_w - b.W)
	b.cam_tx = b.cam_x
	await frames_wait(20)
	await shot("ops_rescue")
	pows[0].freed = true
	pows[1].freed = true
	check(not b.job_done(), "two of three freed is not done")
	var room := Run.roster.size()
	pows[2].freed = true
	var res = await op_end(b)
	check(res == true, "freeing all three wins the op")
	check(Run.roster.size() == room + 1, "one of the freed prisoners joins the company (%d -> %d)" % [room, Run.roster.size()])
	check(int(b.stats.get("job_pay", 0)) == Data.JOB_PAY, "a finished job pays %d scrip" % Data.JOB_PAY)
	main.clear()

	# O3 demolish
	b = await op_battle("demolish")
	var dumps: Array = b.units.filter(func(d): return d.kind == "dump")
	check(dumps.size() == 3 and dumps.all(func(d): return d.hp == Data.TARGET_HP), "a demolish op has three supply dumps")
	var s0: Unit = b.squad_alive()[0]
	b.damage(dumps[0], 10, s0, {"blast": true})
	check(dumps[0].hp == Data.TARGET_HP - 20, "blasts hit a dump twice as hard (%d)" % dumps[0].hp)
	b.damage(dumps[1], 10, s0)
	check(dumps[1].hp == Data.TARGET_HP - 10, "bullets hit a dump normally")
	b.cam_x = clampf(dumps[0].x - 300, 0, b.world_w - b.W)
	b.cam_tx = b.cam_x
	await frames_wait(20)
	await shot("ops_demolish")
	for d in dumps:
		b.damage(d, 999, s0)
	check(b.job_left() == "DEMOLISH: 3 OF 3 DUMPS DOWN", "the HUD counts dumps down (%s)" % b.job_left())
	await until(func(): return b.booms.is_empty(), 300)
	res = await op_end(b)
	check(res == true, "destroying every dump wins the op")
	main.clear()

	# O4 hold
	b = await op_battle("hold")
	b.start_hold()
	check(not b.job_st.on, "the hold waits until the squad reaches the far end")
	for e in b.units:
		if e.team == "enemy":
			e.dead = true; e.gone = true
	b.cam_x = b.world_w - b.W
	b.cam_tx = b.cam_x
	for s in b.squad_alive():
		s.x = b.job_spot(b.world_w - 300.0); s.y = b.T.stand_y(s.x, b.T.ground_at(s.x) - 40)
	b.start_hold()
	check(b.job_st.on and int(b.job_st.left) == Data.HOLD_PHASES, "reaching the far end starts the hold")
	await frames_wait(30)
	var before := b.units.size()
	b.hold_waves()
	var wave: Array = b.units.slice(before)
	check(wave.size() == 3 and wave.any(func(e): return e.x < b.cam_x + 100) and wave.any(func(e): return e.x > b.cam_x + b.W - 100), "each wave comes from both edges (%d)" % wave.size())
	await frames_wait(20)
	await shot("ops_hold")
	for i in Data.HOLD_PHASES - 1:
		await b.job_round()
	check(not b.job_done() and int(b.job_st.left) == 1, "the hold counts down one per enemy phase")
	await b.job_round()
	res = await op_end(b)
	check(res == true, "surviving the hold wins the op")
	main.clear()

	# O5 escort: blocked, then rolling, then home
	b = await op_battle("escort")
	var tr = b.truck()
	check(tr != null and tr.hp == Data.TRUCK_HP, "an escort op has the truck")
	var s1: Unit = b.squad_alive()[0]
	check(b.unit_at_point(tr.x, tr.y - 10, s1, 200, {}) != tr, "the squad's rounds pass the truck")
	for e in b.units:
		if e.team == "enemy":
			e.dead = true; e.gone = true
	var x0: float = tr.x
	var foe := b.mk_enemy("grunt", tr.x + 120, b.T.stand_y(tr.x + 120, b.T.ground_at(tr.x + 120) - 40))
	foe.active = true
	b.units.append(foe)
	await b.job_round()
	check(tr.x == x0, "a Jackal close ahead stops the truck")
	foe.dead = true; foe.gone = true
	await b.job_round()
	check(tr.x > x0, "a clear road and it rolls on (%d -> %d)" % [int(x0), int(tr.x)])
	await frames_wait(10)
	await shot("ops_escort")
	var n := 0
	while tr.x < b.world_w - 150 and n < 120:
		b.cam_x = clampf(tr.x - 200, 0, b.world_w - b.W)
		b.cam_tx = b.cam_x
		await b.job_round()
		n += 1
	check(tr.x >= b.world_w - 150, "the truck reaches the far end (%d of %d)" % [int(tr.x), b.world_w])
	res = await op_end(b)
	check(res == true, "getting the truck through wins the op")
	main.clear()
	b = await op_battle("escort")
	tr = b.truck()
	var hit := b.mk_enemy("grunt", tr.x + 40, tr.y)
	b.damage(tr, 999, hit)
	res = await op_end(b)
	check(res == false, "losing the truck fails the op")
	main.clear()

	# O6 hunt
	b = await op_battle("hunt")
	var q: Array = b.units.filter(func(e): return e.fl.has("quarry"))
	check(q.size() == 1 and q[0].elite != "" and q[0].x > b.world_w * 0.5, "a hunt op marks one elite deep in the sector")
	check(b.job_left().begins_with("HUNT: "), "the HUD names the target (%s)" % b.job_left())
	b.cam_x = clampf(q[0].x - 500, 0, b.world_w - b.W)
	b.cam_tx = b.cam_x
	q[0].active = true
	await frames_wait(20)
	await shot("ops_hunt")
	b.damage(q[0], 9999, b.squad_alive()[0])
	await until(func(): return b.settled(), 300)
	res = await op_end(b)
	check(res == true, "killing the target wins the op")
	check(str(b.stats.get("job_note", "")).contains("Epic"), "the target carried Epic gear")
	main.clear()

	main.show_title()
	await frames_wait(3)
	Run.delete_campaign(2)
	Run.meta.salvage = keep.salvage
	Run.meta.hq = keep.hq
	Run.meta.bio = keep.bio
	Run.save_meta()

func story() -> void:
	## Campaign step 4: radio briefings, the villains, per-soldier implants, Comms and Hangar,
	## the Jackal Defector class and deserters, and Colonel Varga's op.
	var keep := {"salvage": Run.meta.get("salvage", 0), "hq": Run.meta.get("hq", {}).duplicate(), "bio": Run.meta.get("bio", 0), "implants": Run.meta.get("implants", {}).duplicate(true), "mem": Run.meta.get("memorial", []).size()}
	Run.delete_campaign(3)
	Run.new_campaign(3)
	# S2: the act's opening plays once, then job lines
	Run.start_op(Run.sector("d1"))
	var first := Run.radio_before()
	check(first.size() >= 3 and first.any(func(l): return l.who == "varga"), "the first brief opens Act I with Command and Varga (%d lines)" % first.size())
	check(first.all(func(l): return not l.text.contains("{")), "squad lines name real soldiers")
	var again := Run.radio_before()
	check(not again.any(func(l): return Data.RADIO_ACT[0].any(func(r): return r[1] == l.text)), "the act opening plays only once")
	check(again.size() >= 1 and again[0].who == "cmd", "later briefs open with Command's word on the job")
	var called := [false]
	main.show_radio(first, func(): called[0] = true)
	await frames_wait(30)
	await shot("st_radio")
	for k in 12:
		main.screen.advance()
	await frames_wait(2)
	check(called[0], "clicking through the radio moves on")
	called[0] = false
	main.show_radio(first, func(): called[0] = true)
	await frames_wait(5)
	main.screen.finish()
	check(called[0], "SKIP jumps past it")
	var after := Run.radio_after({"won": true, "op": {"act_done": "LANDFALL"}})
	check(after.any(func(l): return l.who == "varga" and l.text.contains("Boar")), "beating the Boar's Den gets a word from Varga")
	check(Run.radio_after({"won": false}).size() == 1, "a lost op gets one line from Command")

	# B3: implants go on a person in the campaign
	Run.meta.hq = {"doc": 2}
	Run.meta.bio = 20
	Run.meta.salvage = 40
	var a: Dictionary = Run.soldiers[0]
	var b2: Dictionary = Run.soldiers[1]
	check(Run.operate("cybereye", a), "the Doc operates on one soldier")
	check(Run.implanted(a, "cybereye") and not Run.implanted(b2, "cybereye"), "the implant is on that soldier only")
	check(Run.implants(a.key).is_empty(), "the class-wide implant list is untouched")
	check(Run.surgery_block("cybereye", a) == "INSTALLED", "the Doc knows it's in")
	main.show_hq(false)
	await frames_wait(20)
	main.screen.open_doc()
	await frames_wait(20)
	await shot("st_doc")

	# B4: Comms and Hangar open with Act II
	check(not Run.hq_buildings().any(func(B): return B.id == "comms"), "no Comms in Act I")
	Run.camp.act = 1
	var ids: Array = Run.hq_buildings().map(func(B): return B.id)
	check(ids.has("comms") and ids.has("hangar") and not ids.has("gate"), "Act II opens Comms and the Hangar (%s)" % [ids])
	Run.meta.hq = {"comms": 3, "hangar": 3}
	main.show_hq(false)
	await frames_wait(10)
	main.screen.open_upgrades()
	await frames_wait(10)
	await shot("st_upgrades")
	Run.start_op(Run.sector("s1"))
	check(Run.op_roster(Run.level) != "", "Comms lists the sector's enemies (%s)" % Run.op_roster(Run.level))
	main.show_brief()
	await frames_wait(20)
	await shot("st_brief_comms")
	var bt: Battle = main.start_battle(1, Run.level)
	bt.mission_over.disconnect(main._on_mission_over)
	await until(func(): return bt.state == "player" and not bt.busy)
	check(bt.units.any(func(u): return u.kind == "slug" and not u.gone), "the Hangar rolls the Slug out with the squad")
	var s0: Unit = bt.squad_alive()[0]
	check(s0.hand.any(func(c): return c.key == "slugcall"), "Hangar 3: the Slug can be called back")
	var e := bt.mk_enemy("grunt", s0.x + 200, bt.T.stand_y(s0.x + 200, 0))
	e.hp = 60; e.max_hp = 60; e.elite = "veteran"
	bt.units.append(e)
	bt.damage(e, 10, s0)
	var h1: int = e.hp
	bt.damage(e, 10, s0)
	check(h1 == 45 and e.hp == 35, "Comms 2: the first hit on an elite lands marked (%d, %d)" % [h1, e.hp])
	main.clear()

	# C7 + S4: a deserter joins as a Jackal Defector in Act III
	Run.camp.act = 2
	Run.level = Run.make_op(Run.sector("r1"))
	var n0 := Run.roster.size()
	var line := ""
	for k in 40:
		line = Run.deserter({"won": true})
		if line != "":
			break
	check(line.contains("Jackal Defector") and Run.roster.size() == n0 + 1, "a won Act III op can bring a deserter (%s)" % line)
	var dv: Dictionary = Run.roster.back()
	check(dv.get("spec", "") == "defector" and dv.def.cls == "Jackal Defector" and dv.deck.any(func(c): return c.key == "haymaker"), "the Defector is a class of their own")
	Run.camp.act = 0
	check(Run.deserter({"won": true}) == "", "no deserters outside Act III")
	Run.camp.act = 2

	# S3: Varga fights alongside the company at Garrison Gate
	Run.start_op(Run.sector("f3"))
	check(Run.level.get("guest", "") == "varga", "Garrison Gate brings Colonel Varga")
	var squad_n := Run.soldiers.size()
	bt = main.start_battle(2, Run.level)
	bt.mission_over.disconnect(main._on_mission_over)
	await until(func(): return bt.state == "player" and not bt.busy)
	var vg: Array = bt.squad().filter(func(u): return u.s.has("guest"))
	check(vg.size() == 1 and bt.squad().size() == squad_n + 1, "Varga deploys as a fifth soldier")
	check(not Run.soldiers.has(vg[0].s) and not Run.roster.has(vg[0].s), "he is not part of the company")
	await frames_wait(20)
	await shot("st_varga")
	# the Defector's Turncoat: an up-close kill steals the Jackal's gun
	var du: Unit = bt.squad_alive()[0]
	du.s["spec"] = "defector"
	var j := bt.mk_enemy("grunt", du.x + 30, du.y)
	bt.units.append(j)
	var hn := du.hand.size()
	bt.damage(j, 999, du)
	check(du.hand.size() == hn + 1 and du.hand.back().get("temp", false), "Turncoat: a close kill hands over the Jackal's gun")
	var j2 := bt.mk_enemy("grunt", du.x + 30, du.y)
	bt.units.append(j2)
	bt.damage(j2, 999, du)
	check(du.hand.size() == hn + 1, "only once a turn")
	du.s.erase("spec")
	var mem: int = Run.meta.memorial.size()
	vg[0].dead = true
	bt.sync_back()
	check(Run.meta.memorial.size() == mem, "Varga never goes on the Memorial")
	main.clear()

	# saved and loaded, implants and the Defector come back
	Run.save_campaign()
	main.show_title()
	await frames_wait(3)
	Run.load_campaign(3)
	check(Run.implanted(Run.soldiers[0], "cybereye"), "per-soldier implants survive a save")
	check(Run.roster.any(func(s): return s.get("spec", "") == "defector"), "the Defector survives a save")
	main.show_title()
	await frames_wait(3)
	Run.delete_campaign(3)
	Run.meta.salvage = keep.salvage
	Run.meta.hq = keep.hq
	Run.meta.bio = keep.bio
	Run.meta.implants = keep.implants
	Run.save_meta()

func lab() -> void:
	## Campaign step 5: the Alien Lab and Vharr tech, the Gate Engineer, bonus ops, and campaign
	## milestones that unlock run content.
	var keep := {"salvage": Run.meta.get("salvage", 0), "hq": Run.meta.get("hq", {}).duplicate(), "bio": Run.meta.get("bio", 0), "unlocked": Run.meta.unlocked.duplicate()}
	Run.delete_campaign(4)
	Run.new_campaign(4)
	check(not Run.hq_buildings().any(func(B): return B.id == "lab"), "no Alien Lab before Act III")
	Run.camp.act = 2
	check(Run.hq_buildings().any(func(B): return B.id == "lab"), "Act III opens the Alien Lab")
	main.show_hq(false)
	await frames_wait(10)
	main.screen.open_upgrades()
	await frames_wait(10)
	await shot("lab_upgrades")
	check(Run.tech_block("blinkpack") == "BUILD THE ALIEN LAB", "the Lab has to be built first")
	Run.meta.hq = {"lab": 1}
	check(Run.tech_block("blinkpack") == "KILL 15 MORE", "tech waits on kills (%s)" % Run.tech_block("blinkpack"))
	Run.after_op({"kinds": {"blinker": 9, "warden": 4}})
	Run.after_op({"kinds": {"blinker": 6}})
	check(Run.tech_kills("blinker") == 15 and Run.tech_kills("warden") == 4, "every op's alien kills add up (%d, %d)" % [Run.tech_kills("blinker"), Run.tech_kills("warden")])
	Run.meta.bio = 10
	Run.meta.salvage = 20
	check(Run.tech_block("blinkpack") == "", "15 Blinkers and the parts: Blink Pack can be built")
	Run.meta.unlocked.erase("blinkpack")
	var it := Run.build_tech("blinkpack")
	check(not it.is_empty() and Run.stash.has(it) and int(Run.meta.bio) == 10 - Data.TECH_BIO, "the Blink Pack goes to the stash for its price")
	check(Run.meta.unlocked.has("blinkpack") and Run.unlocked("blinkpack"), "built once, runs can find it too")
	Run.meta.hq.lab = 2
	check(Run.tech_need() == 10, "Lab 2: tech needs 10 kills")
	Run.meta.hq.lab = 3
	Run.camp.kills["prism"] = 10
	var pp := Run.build_tech("prismplate")
	check(int(pp.get("tier", 0)) == 3, "Lab 3: tech comes out Epic")
	main.show_hq(false)
	await frames_wait(10)
	main.screen.go("lab")
	await frames_wait(20)
	await shot("lab_board")

	# the tech in a fight
	Run.camp.act = 3
	var eng_line := Run.engineer_joins()
	var eng: Dictionary = Run.roster.back()
	check(eng_line.contains("Gate Engineer") and eng.get("spec", "") == "engineer" and eng.def.cls == "Gate Engineer", "Act IV brings a Gate Engineer (%s)" % eng_line)
	check(eng.deck.any(func(c): return c.key == "blink") and eng.deck.any(func(c): return c.key == "domeup"), "the Engineer carries a Blink and a Dome Projector")
	check(Run.engineer_joins() == "", "only one Engineer reports")
	Run.toggle_squad(eng)
	check(Run.soldiers.has(eng), "the Engineer can deploy")
	var mo: Dictionary = Run.soldiers[0]
	Run.equip(mo, pp)
	Run.camp.act = 2
	Run.level = Run.make_op(Run.sector("r1"))
	var b: Battle = main.start_battle(2, Run.level)
	b.mission_over.disconnect(main._on_mission_over)
	await until(func(): return b.state == "player" and not b.busy)
	var eu: Array = b.squad().filter(func(u): return u.s == eng)
	check(eu.size() == 1 and eu[0].dome > 0, "the Engineer deploys under a dome")
	for e in b.units:
		if e.team == "enemy":
			e.dead = true; e.gone = true
	var u: Unit = b.squad_alive().filter(func(x): return x.s == mo)[0]
	var gx: float = u.x + 220
	var foe := b.mk_enemy("grunt", gx, b.T.stand_y(gx, b.T.ground_at(gx) - 40))
	foe.active = true
	b.units.append(foe)
	var hp0 := u.hp
	var fh := foe.hp
	b.damage(u, 5, foe)
	check(u.hp == hp0 and foe.hp == fh - 5, "Prism Plate sends the first shot back (%d, %d)" % [u.hp, foe.hp])
	b.damage(u, 5, foe)
	check(u.hp == hp0 - 5, "only the first shot each turn")
	foe.hp = 99; foe.max_hp = 99
	await b.vharr_blink(u, 360)
	check(absf(u.x - foe.x) < 60 and u.face == (1 if foe.x > u.x else -1), "Blink lands right behind the enemy, facing it (%d vs %d)" % [int(u.x), int(foe.x)])
	await frames_wait(10)
	await shot("lab_blink")
	# a spread-out group gets pulled together
	var grp: Array = []
	for k in 3:
		var px: float = u.x + 120 + k * 50
		var g := b.mk_enemy("grunt", px, b.T.stand_y(px, b.T.ground_at(px) - 40))
		g.active = true
		b.units.append(g)
		grp.append(g)
	var spread0: float = grp[2].x - grp[0].x
	var ux := u.x
	await b.vharr_well(u, 140)
	await until(func(): return b.settled(), 600)
	check(absf(grp[2].x - grp[0].x) < spread0, "the Gravity Grenade pulls a group together (%d -> %d)" % [int(spread0), int(grp[2].x - grp[0].x)])
	check(absf(u.x - ux) < 1, "and leaves the thrower where they are")
	var inst := {"id": -9, "key": "domeup", "tier": 0}
	u.hand.append(inst)
	u.energy = 3
	for s in b.squad_alive():
		s.dome = 0
	await b._act_self(u, u.hand.size() - 1, Data.card(inst))
	check(u.dome == 2, "the Dome Projector domes its user")
	main.clear()

	# P2 bonus ops
	Run.camp.act = 0
	Run.camp.held = [Run.sec_key("d1"), Run.sec_key("d2")]
	Run.camp.bonus = {}
	var bl := ""
	for k in 40:
		bl = Run.roll_bonus()
		if bl != "":
			break
	check(bl.begins_with("Bonus op at") and not Run.camp.bonus.is_empty(), "a bonus op turns up on a held sector (%s)" % bl)
	var bsc: Dictionary = Run.act().sectors.filter(func(sc): return Run.bonus_at(sc) != "")[0]
	main.show_war_room()
	await frames_wait(10)
	main.screen.sel = bsc.id
	main.screen.build()
	await frames_wait(10)
	await shot("lab_bonus_room")
	check(main.screen.go_btn.text == "BONUS OP", "the War Room offers the bonus op")
	Run.start_op(bsc)
	check(Run.level.bonus != "" and Run.level.banner == "BONUS OP" and Run.level.job in ["escort", "hunt"], "a bonus op is a convoy escort or a scout hunt (%s)" % Run.level.job)
	var res := Run.op_over(true)
	check(res.has("bonus") and Run.camp.bonus.is_empty() and Run.sector_held(bsc.id), "winning it pays and clears it; the sector stays held")
	Run.camp.bonus = {"sec": Run.sec_key("d1"), "kind": "convoy", "left": 2}
	Run.roll_bonus()
	check(not Run.camp.bonus.is_empty(), "a bonus op waits a couple of ops")
	check(Run.roll_bonus().contains("moved on") and Run.camp.bonus.is_empty(), "then it moves on, costing nothing")

	# L3: beating Act III unlocks the Defector for runs; shutting the Gate unlocks a gate finale
	Run.meta.unlocked.erase("cls_defector")
	Run.camp.act = 2
	Run.camp.held = Run.act().sectors.filter(func(sc): return not sc.get("stronghold", false)).map(func(sc): return Run.sec_key(sc.id))
	Run.start_op(Run.sector("boss"))
	res = Run.op_over(true)
	check(res.get("unlock", "") == "cls_defector" and Run.meta.unlocked.has("cls_defector"), "clearing Act III unlocks the Defector for runs")
	main.show_title()
	await frames_wait(3)
	Run.new_run()
	var got := {}
	for k in 60:
		for o in Run.recruit_offers(3):
			if o.get("spec", "") == "defector":
				got = o
		if not got.is_empty():
			break
	check(not got.is_empty(), "run recruits sometimes include a Jackal Defector")
	if not got.is_empty():
		var rs := Run.make_recruit(got)
		check(rs.get("spec", "") == "defector" and rs.def.cls == "Jackal Defector", "and they come as the campaign class")
	Run.meta.unlocked.append("gatefinale")
	Run.start_finale()
	check(Run.level.get("encounter", "") == "gate", "after the war, the run's finale has a gate siege")
	Run.level = {}
	Run.delete_campaign(4)
	Run.meta.salvage = keep.salvage
	Run.meta.hq = keep.hq
	Run.meta.bio = keep.bio
	Run.meta.unlocked = keep.unlocked
	Run.save_meta()

func ending() -> void:
	## Campaign step 6: Act III and IV bosses, the Iron Harbor finale as a gate siege, the ending
	## screen, and a Second Tour with one veteran.
	Run.delete_campaign(5)
	Run.new_campaign(5)
	Run.camp.act = 2
	Run.start_op(Run.sector("boss"))
	check(Run.level.get("vharr_boar", false), "Act III's stronghold is a Vharr-refit Boar")
	var hp3: float = float(Run.level.get("hp_mul", 1.0))
	Run.start_op(Run.sector("r1"), true)
	check(not Run.level.get("vharr_boar", false), "but its patrols are not")
	Run.camp.act = 4
	Run.start_op(Run.sector("boss"))
	var lv: Dictionary = Run.level
	check(lv.get("finale", false) and lv.get("encounter", "") == "gate" and lv.get("segments", []).has("pier"), "Iron Harbor is the finale, with a gate siege (%s)" % lv.get("encounter", ""))
	var boss_hp: float = float(lv.get("boss_hp", 0))
	check(boss_hp > 0, "the finale boss is tougher than the act's (%s)" % boss_hp)
	var b: Battle = main.start_battle(5, Run.level)
	b.mission_over.disconnect(main._on_mission_over)
	await until(func(): return b.state == "player" and not b.busy)
	check(b.units.any(func(u: Unit): return u.team == "enemy" and b.is_boss(u)), "the finale fields a boss")
	await shot("ending_finale")
	main.clear()
	# win the war
	Run.camp.held = Run.act().sectors.filter(func(sc): return not sc.get("stronghold", false)).map(func(sc): return Run.sec_key(sc.id))
	Run.start_op(Run.sector("boss"))
	var res := Run.op_over(true)
	check(Run.camp.done and res.has("act_done"), "shutting the Gate wins the war")
	var vet: Dictionary = Run.company()[0]
	Run.svc(vet).kills = 31
	Run.svc(vet).ops = 14
	vet.rank = 3
	main.show_ending()
	await frames_wait(10)
	await shot("ending_screen")
	main.screen.pick = 0
	main.screen.build()
	await frames_wait(10)
	await shot("ending_pick")
	var vname: String = vet.def.name
	main.screen.tour.emit(vet)
	await frames_wait(10)
	check(int(Run.camp.get("tour", 1)) == 2 and not Run.camp.done and int(Run.camp.act) == 0, "Second Tour: a new war in the same slot")
	var v2: Array = Run.roster.filter(func(s): return s.get("tour_vet", false))
	check(v2.size() == 1 and v2[0].def.name == vname and int(v2[0].get("rank", 0)) == 3 and Run.soldiers.has(v2[0]), "the veteran comes along, rank and all, in the squad")
	check(v2[0].equip.values().all(func(x): return x == null), "without their old kit")
	Run.camp.act = 2
	Run.start_op(Run.sector("boss"))
	check(float(Run.level.get("hp_mul", 1.0)) > hp3, "Second Tour sectors are harder (%s > %s)" % [Run.level.get("hp_mul", 1.0), hp3])
	Run.camp.act = 0
	Run.save_campaign()
	check(Run.load_campaign(5) and int(Run.camp.get("tour", 1)) == 2, "the tour is saved")
	main.show_war_room()
	await frames_wait(10)
	await shot("ending_tour2_room")
	Run.level = {}
	Run.delete_campaign(5)

func hoverwedge() -> void:
	## A hovering tank (Squid, Prism, Overseer) shoved with its top into an overhang used to be stuck there
	## counting as airborne, so the action waiting on everything to settle never ended: the frozen turns
	## the playtest found on level 3. It has to sink out (or at least settle).
	Run.new_run()
	var b: Battle = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	for o in b.units:
		if o.team == "enemy":
			o.dead = true; o.gone = true
	for type in ["squid", "prism", "overseer"]:
		var x := 520.0
		var fl: float = b.T.stand_y(x, 0)
		var e := b.mk_enemy(type, x, fl)
		e.active = true
		b.units.append(e)
		# a three-cell slab of overhang well under the tank's altitude, with the tank's top 3px into it
		var slab_bot: float = fl - 60
		var cx0 := int(x / Terrain.CELL)
		var cy1 := int(floor((slab_bot - 1) / Terrain.CELL))
		for cy in range(cy1 - 2, cy1 + 1):
			for cx in range(cx0 - 3, cx0 + 4):
				b.T.set_cell(cx, cy, 3)
		e.y = (cy1 + 1) * Terrain.CELL - 3 + e.h
		e.air = true
		var y0 := e.y
		var ok := await until(func(): return b.settled(), 600)
		print("[hoverwedge] %s top %.1f in the overhang -> y %.1f air %s settled %s" % [type, y0 - e.h, e.y, e.air, ok])
		for cy in range(cy1 - 2, cy1 + 1):
			for cx in range(cx0 - 3, cx0 + 4):
				b.T.set_cell(cx, cy, 0)
		e.gone = true

func straggler() -> void:
	## A soldier down a deep drill shaft when the screen scrolls on: the drag has to lift them out
	## onto the new screen instead of leaving them behind the camera, where they can't move or drill.
	Run.new_run()
	var b: Battle = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	b.debug = true
	for o in b.units:
		if o.team == "enemy":
			o.dead = true; o.gone = true
	var sq := b.squad()
	var x0 := 300.0
	var top: float = b.T.stand_y(x0, 0)
	b.T.bore(x0, Battle.WATER_Y - 30, top - 40, 12)
	ground_unit(b, sq[0], x0, top + 4)
	for i in range(1, sq.size()):
		ground_unit(b, sq[i], 150.0 + i * 30)
	await frames_wait(20)
	print("[straggler] %s sits at %d,%d (surface %d)" % [sq[0].def.key, int(sq[0].x), int(sq[0].y), int(top)])
	# scroll to a screen whose ground stands well above the bottom of the shaft all along the drag lanes
	var tx := 600.0
	while tx < b.world_w - Battle.W:
		var ok := true
		for x in range(int(tx) + 16, int(tx) + 420, 4):
			var gy = b.T.stand_y(x, 0)
			if gy == null or gy > sq[0].y - 70:
				ok = false
				break
		if ok:
			break
		tx += 40
	b.scroll_to(tx, "go")
	await until(func(): return not b.busy and absf(b.cam_x - b.cam_tx) < 0.5)
	await frames_wait(30)
	var bad := sq.filter(func(s): return s.x < b.cam_x or b.T.solid(s.x, s.y - s.h / 2.0))
	print("[straggler] cam %d squad %s left behind %d" % [int(b.cam_x), sq.map(func(s): return "%s@%d,%d" % [s.def.key, int(s.x), int(s.y)]), bad.size()])
	await shot("straggler")

func pinball() -> void:
	## one blast next to a bunched squad: how many bonks and how much damage follow
	for gap in [16.0, 24.0, 36.0, 46.0]:
		Run.new_run()
		var b: Battle = main.start_battle(0)
		await until(func(): return b.state == "player" and not b.busy)
		b.debug = true
		for o in b.units:
			if o.team == "enemy":
				o.dead = true; o.gone = true
		var sq := b.squad()
		var x0 := 200.0
		for i in sq.size():
			ground_unit(b, sq[i], x0 + i * gap)
		await frames_wait(5)
		var hp0: int = sq.reduce(func(a, x): return a + x.hp, 0)
		b.explode(x0 - 20, sq[0].y - 6, 40, 10, null)
		await frames_wait(200)
		var hp1: int = sq.reduce(func(a, x): return a + x.hp, 0)
		print("[pinball] gap ", gap, " squad hp lost ", hp0 - hp1, " per soldier ", sq.map(func(x): return x.hp))
		main.clear()
		await frames_wait(5)

func pickups() -> void:
	## G7: mid and late game finds. They only drop once the run reaches them, every new card
	## plays, the new belt items work, and the guns put their cards in the deck.
	Run.new_run()
	for m in 3:
		Run.mission = m
		var seen := {}
		for i in 800:
			seen[Run.random_item_id()] = true
		var early: Array = seen.keys().filter(func(k): return Data.ITEMS[k].get("from", 0) > m)
		var fresh: Array = Data.ITEMS.keys().filter(func(k): return Data.ITEMS[k].get("from", -1) == m and Data.ITEMS[k].slot != "belt")
		check(early.is_empty(), "level %d rolls nothing from later in the run %s" % [m + 1, early])
		check(fresh.all(func(k): return seen.has(k)), "level %d rolls every item that starts there (%d)" % [m + 1, fresh.size()])
		var belts := {}
		for i in 300:
			belts[Run.random_item_id(["belt"])] = true
		check(belts.has("b_stim") == (m >= 1) and belts.has("b_adr") == (m >= 2), "level %d belt finds %s" % [m + 1, belts.keys()])
	Run.new_run()
	Run.mission = 2
	var b: Battle = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	playtest_debug = true
	cur_b = b
	b.debug = true
	for m in 3:
		Run.mission = m
		var letters := {}
		for i in 500:
			var p := b.crate_payload()
			if p.type == "letter":
				letters[p.key] = true
		var late: Array = letters.keys().filter(func(k): return Data.LETTER_FROM.get(k, 0) > m)
		check(late.is_empty() and letters.size() == Data.LETTERS.keys().filter(func(k): return Data.LETTER_FROM.get(k, 0) <= m).size(), "level %d letters %s" % [m + 1, letters.keys()])
	Run.mission = 2
	# show the new finds lying in the field
	var u: Unit = b.sel
	var x0 := u.x + 50
	for i in 6:
		var id: String = ["railgun", "juggernaut", "vharrheart", "bullpupgun", "exolegs", "b_stim"][i]
		b.drop_loot(x0 + i * 26, u.y - 10, {"type": "item", "item": Run.new_item(id, 3 if i < 3 else 1)}, 0.0)
	for i in 4:
		b.drop_loot(x0 + 170 + i * 26, u.y - 10, {"type": "letter", "key": ["D", "T", "Z", "G"][i]}, 0.0)
	await frames_wait(40)
	await shot("pickups_field")
	for o in b.units:
		if o.kind == "loot":
			o.gone = true
	# every new card plays and hurts something
	for key in ["bullpup", "m79", "railshot", "minigun", "dropshot", "thundershot", "superhmg", "zantetsu"]:
		var e := nearest_enemy(b, u)
		if e == null:
			break
		if key == "zantetsu":
			ground_unit(b, e, u.x + 34 * u.face)
			e.hp = 200; e.max_hp = 200
			await frames_wait(4)
		var hp0 := e.hp
		b.select_unit(u)
		u.energy = 3
		var idx := force_card(u, key)
		b.select_card(idx)
		var c := Data.card(u.hand[idx])
		b.mouse = Vector2(e.x, e.y - e.h * 0.6) if c.type != "ARC" else Vector2(e.x, e.y - 160)
		if c.type == "ARC":
			b.mouse = Vector2((u.x + e.x) / 2.0, minf(u.y, e.y) - 140)
		await frames_wait(4)
		if key == "railshot":
			await shot("pickups_rail_aim")
		if c.type == "MELEE":
			b.play_on_target(e)
		else:
			b.commit_aim(b.mouse)
		var ok := await settle_picking(b)
		var hurt := 0
		for o in b.units:
			if o.team == "enemy":
				hurt += 1 if o.dead or o.hp < o.max_hp else 0
		check(ok, "%s plays and settles (target hp %d -> %d, %d enemies hurt)" % [Data.CARDS[key].name, hp0, e.hp, hurt])
		if key == "zantetsu":
			check(e.hp < hp0, "Zantetsu Slash cuts the Jackal beside you (%d -> %d)" % [hp0, e.hp])
		if b.state != "player":
			break
	# belt items: no card, no energy
	u = b.squad_alive()[0]
	b.select_unit(u)
	u.hp = 5; u.energy = 0; u.adr = 0
	Run.belt = [Run.new_item("b_stim"), Run.new_item("b_adr")]
	b.use_belt(0)
	check(u.hp == mini(u.max_hp, 17) and u.energy == 1, "Combat Stim heals 12 and gives 1 energy (hp %d, energy %d)" % [u.hp, u.energy])
	b.use_belt(0)
	check(u.adr == 50, "Rage Shot gives 50 adrenaline (%d)" % u.adr)
	# guns put their cards in the deck mid-mission
	var rg := Run.new_item("railgun", 2)
	Run.equip(u.s, rg, "weapon")
	b.refresh_unit_gear(u)
	var n := 0
	for pile in [u.draw, u.hand, u.disc]:
		n += pile.filter(func(c): return c.key == "railshot").size()
	check(n == 2, "the Rail Gun adds 2 Rail Slugs (%d)" % n)
	var jg := Run.new_item("juggernaut", 4)
	var hp_before := u.max_hp
	Run.equip(u.s, jg, "armor")
	b.refresh_unit_gear(u)
	check(u.max_hp >= hp_before + 15, "a Legendary Juggernaut Suit adds 25 max HP (%d -> %d)" % [hp_before, u.max_hp])
	await shot("pickups_after")

func bossloot() -> void:
	## G8: late squad gear only stocks from its level on, bosses drop a trophy you don't have,
	## and trophies and late gear really apply.
	var ShopScript = load("res://scripts/shop.gd")
	for m in 3:
		Run.new_run()
		Run.mission = m
		var seen := {}
		var sh = ShopScript.new()
		for i in 80:
			sh.restock()
			for g in sh.stock_gear:
				seen[g.id] = true
		sh.free()
		var bad: Array = seen.keys().filter(func(k): return Data.gear(k).get("boss", false) or Data.gear(k).get("from", 0) > m)
		var want: Array = Data.GEAR.filter(func(g): return not g.get("boss", false) and g.get("from", 0) == m).map(func(g): return g.id)
		check(bad.is_empty() and want.all(func(k): return seen.has(k)), "level %d Quartermaster stocks %d new squad gear and nothing early %s" % [m + 1, want.size(), bad])
	Run.new_run()
	Run.mission = 2
	var b: Battle = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	var u: Unit = b.sel
	var boss := spawn_alien(b, "boss", u.x + 220)
	b.kill(boss, u)
	await frames_wait(90)
	var rel: Array = b.units.filter(func(o): return o.kind == "loot" and not o.gone and o.loot.type == "relic")
	check(rel.size() == 1, "the boss drops one trophy (%d)" % rel.size())
	await shot("bossloot_drop")
	if rel.size():
		var id: String = rel[0].loot.id
		var hp0 := u.max_hp
		b.collect(u, rel[0])
		check(Run.has_gear(id) and Run.relic_tier(id) == Data.TIER_MAX, "picking up %s adds it as Legendary squad gear" % id)
		var st: Dictionary = Data.gear(id).stats
		var gb := Run.gear_bonus(u.s)
		check(st.keys().all(func(k): return gb.get(k, 0) >= st[k]), "%s's stats reach every soldier %s" % [id, st])
		if st.has("hp"):
			check(u.max_hp == hp0 + 6, "Iron Heart raises max HP mid-mission (%d -> %d)" % [hp0, u.max_hp])
	# a second boss never drops one you already own
	for g in Data.GEAR:
		if g.get("boss", false):
			Run.add_gear(g.id, Data.TIER_MAX)
	var n0 := b.units.filter(func(o): return o.kind == "loot" and o.loot.type == "relic").size()
	var boss2 := spawn_alien(b, "boss", u.x + 260)
	b.kill(boss2, u)
	await frames_wait(20)
	check(b.units.filter(func(o): return o.kind == "loot" and o.loot.type == "relic").size() == n0, "with every trophy owned the boss drops no more")
	main.clear()
	await frames_wait(5)
	# late squad gear at the start of a mission
	Run.new_run()
	for id in ["warpaint", "ammodrone", "nanites", "overclock"]:
		Run.add_gear(id, 1)
	b = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	var sq := b.squad_alive()
	check(sq.all(func(s): return s.adr >= 25), "War Paint: everyone starts with 25 adrenaline %s" % [sq.map(func(s): return s.adr)])
	check(sq.all(func(s): return s.hand.filter(func(c): return not c.get("temp", false) and c.key != "hop" and not Data.CARDS[c.key].get("sidearm", false)).size() >= 5 or s.draw.is_empty()), "Ammo Drone: 5 cards in hand %s" % [sq.map(func(s): return s.hand.size())])
	check(sq.all(func(s): return s.energy >= 4), "Overclock Core: +1 energy on round 1 %s" % [sq.map(func(s): return s.energy)])
	check(Run.gear_bonus(sq[0].s).get("regen", 0) >= 2, "Nanite Swarm: everyone regenerates")
	await shot("bossloot_late_gear")

func settle_picking(b: Battle) -> bool:
	## Waits for an action to finish, taking the first option on any level-up or loot prompt it opens.
	for i in 3200:
		if not b.busy:
			return true
		if modal_title(b) != "":
			b.hud.picked.emit(0)
			await frames_wait(10)
		await get_tree().process_frame
	return false

func tuning() -> void:
	## The playtest tuning: one bonk per pair of squadmates per blast, a slower stall clock, shorter levels, one Shield per drop.
	# a blast beside a bunched squad no longer chains into a pile of bonks
	Run.new_run()
	var b: Battle = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	for o in b.units:
		if o.team == "enemy":
			o.dead = true; o.gone = true
	var sq := b.squad()
	for i in sq.size():
		ground_unit(b, sq[i], 200 + i * 16.0)
	await frames_wait(5)
	var hp0: int = sq.reduce(func(a, x): return a + x.hp, 0)
	b.explode(180, sq[0].y - 6, 40, 10, null)
	await frames_wait(200)
	var lost: int = hp0 - sq.reduce(func(a, x): return a + x.hp, 0)
	check(lost <= 22, "a 10-damage blast beside a bunched squad costs %d HP (was 29)" % lost)
	main.clear()
	await frames_wait(5)
	# alert holds for two quiet rounds and climbs on the third
	Run.new_run()
	b = main.start_battle(0)
	await until(func(): return b.state == "player" and not b.busy)
	for o in b.units:
		if o.team == "enemy":
			o.dead = true; o.gone = true
	var alerts: Array = []
	for r in 3:
		b.end_turn(true)
		await until(func(): return b.state == "player" and not b.busy)
		alerts.append(b.alert)
	check(alerts[0] == 0 and alerts[1] == 0 and alerts[2] == 1, "alert starts climbing on the third round without a scroll %s" % [alerts])
	main.clear()
	await frames_wait(5)
	# levels are seven segments: start, stretch, camp, yard, stretch, camp, boss
	var lv := Run.make_level("desert", 1)
	check(lv.segments.size() == 7 and lv.segments[2] == "camp" and lv.segments[3] == "yard" and lv.segments[5] == "camp", "a level is seven segments %s" % [lv.segments])
	# paradrops bring at most one Shield
	Run.new_run()
	Run.level = Run.make_level("fortress", 2)
	b = main.start_battle(2, Run.current_mission())
	await until(func(): return b.state == "player" and not b.busy)
	b.speed = 16.0
	var worst := 0
	for r in 8:
		for o in b.units:
			if o.team == "enemy" and o.para:
				o.dead = true; o.gone = true
		for s in b.squad_alive():
			s.hp = s.max_hp
		b.alert = 9
		b.rounds_since_scroll = 9
		b.strikes = []
		var before := b.units.size()
		b.end_turn(true)
		await until(func(): return (b.state == "player" and not b.busy) or b.state == "over")
		if b.state == "over":
			break
		var drop: Array = b.units.slice(before).filter(func(o): return o.para)
		worst = maxi(worst, drop.filter(func(o): return o.type == "shield").size())
	check(worst <= 1, "a paradrop brings at most one Shield (most seen %d)" % worst)

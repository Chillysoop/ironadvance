class_name Battle
extends Node2D
## One mission: the turn loop, physics, weapons, enemy AI and the collapse hooks.
## Runs on a fixed 60 Hz step; long actions are coroutines that await `tick`.
signal tick
signal mission_over(won: bool)
signal lesson_done(result: String)  # the step-by-step tutorial: "pass", "fail" or "skip"
var debug := false

const W := 960
const H := 540
const CELL := 4
const WATER_Y := 500
const GRAV := 0.22
const BODY_MAX := 14     # oldest bodies past this many fade away
const JET_THRUST := 0.42 # Jet Boots: push per tick toward the cursor, plus a little lift
const JET_LIFT := 0.12
const JET_MAX_VX := 4.5
const JET_MAX_VY := 5.0
const Services := preload("res://scripts/services.gd")

var T: Terrain
var units: Array = []
var projs: Array = []
var parts: Array = []
var fx: Array = []
var texts: Array = []
var tracers: Array = []
var smokes: Array = []
var gases: Array = []     # toxic clouds: {x, y, r, turns, seed, owner}; drift with the wind
var strikes: Array = []
var booms: Array = []
var banners: Array = []
var barks: Array = []
var ropes: Array = []
const SettingsScript := preload("res://scripts/settings.gd")
var shake := 0.0
var cam_x := 0.0
var cam_tx := 0.0
var state := "title"
var busy := false
var round_n := 0
var alert := 0
var rounds_since_scroll := 0
var regroup := false  # X7: a soldier went down: the stall clock skips the next enemy phase
var push_warned := -1  # round the "clear the enemies behind first" warning was last shown
var pincer := {}       # W9: Iron Harbor with two squads: {on, view "a"/"b", a_cam, b_cam}; squad B wears fl.wing = "b"
const STALL_ROUNDS := 3   # rounds on one screen before alert starts climbing (one fewer on threat 1)
var wind := 0
var score := 0
var combo := 0
var t := 0
var sel: Unit = null
var card_idx := -1
var mouse := Vector2(200, 300)
var log_lines: Array = []
var log_at: Array = []       # X6: the frame each log line came in, so old news fades
var pow_queue: Array = []
var para_queue: Array = []   # soldiers who picked up a reinforcement flare, waiting on the call-in
var job_st := {}   # O4: {"on", "left"} while holding the far end
var lvl_queue: Array = []
var dummies: Array = []       # practice range: [type, x] of each dummy, to stand them back up
var tut_step := 0             # N6 training: the drill step the recruits are on
var tut_said := -1            # the last step the sergeant has called in
var tut_marks := {}           # drill step -> the units it is about
var tut_blast := false        # a squad blast went off on the grenade step
var lesson_over := false      # tutorial lesson: passed, failed or skipped, the next one is loading
var lesson_said := false      # tutorial lesson: the sergeant has called this lesson in
var lesson_why := ""          # tutorial lesson: why the last try failed, for the panel
var boss_active := false
var boss_dead := false
var gate = null          # the gate home to HQ, opened after the boss falls
var radio_t = null
var aim_hold := false
var sway_t := 0
var won := false
var lost := false
var ui_dirty := true
var end_confirm_t := 0   # frames left to confirm END TURN while soldiers can still act
var inspect := false     # ALT held: show every soldier's actions
var jet_armed := false   # J pressed: the next click-and-hold flies the selected soldier
var rummage_armed := false  # C1: the next card clicked is swapped for a fresh draw instead of played
var undo_walk := {}       # A2: the last walk, while nothing else has happened since it can be taken back
var walk_snap := {}       # A2: set just before a walk's resolve so it can tell whether the walk was quiet
var jet_hold := false    # the mouse button is down while jetting
var pads: Array = []     # bonus pads on this map
var stickies: Array = []  # B3 Sapper charges on the ground
var walls: Array = []    # N2: Rect2 of each wall Bolt built (Hunker Down)
var grav := GRAV         # this map's gravity: Mountain's thin air lowers it
var fuse_pick := 0       # frames of fuse the player dialed in with the wheel (0 = the card's own)
var feed: Array = []     # kill feed lines: {killer, how, victim, kc, stamp, t}
var kill_how := ""       # what is dealing the damage right now when it isn't a card (FALL, CRUSHED, BURN)
var act_card := ""       # name of the card behind the current action, for the kill feed
var act_type := ""       # its type (AIM, ARC, MELEE...), for personal orders (W5)
var pop_next := false    # the next kill was an overkill: the Jackal bursts instead of leaving a body
var stats := {"kills": 0, "pows": 0, "pushes": 0, "rounds": 0, "crushes": 0, "scrip": 0, "kia": 0, "max_alert": 0, "pows_total": 0, "loot": 0, "tags": 0, "best_combo": 0, "fallen": [], "falls": 0, "downs": 0, "melee_kills": 0}
var act_once := {}        # tag-team combos that pay out once per action
var squad_bonks := {}     # "id:id" or id -> tick of the last squadmate bonk for that pair or that soldier
const BONK_RESET := 120   # ticks before the same two soldiers can bonk again
var bonk_launch := {}     # id -> tick a body last got knocked into the air by another body
const RELAUNCH := 40      # ticks before a bonked body can be knocked up again (a pit of Jackals would juggle forever)
var act_crushed := 0      # Jackals crushed by debris during the current action (DOMINO)
var act_crush_at := Vector2.ZERO
var crate_bump := 0       # kill combo x5: the next crate rolls one rarity higher
var act_unit: Unit = null # who played the card that started the current action
var act_inst = null       # the deck card behind the current action, credited with its kills (D4)
var taunter: Unit = null  # Taunt: Jackals that can, shoot this soldier next phase
var lazarus_used := false
var last_hit_head := false
var burn_tick := false    # a burn status is dealing damage right now (feat tracking)
var relay_hand := 0       # captured relays (W3)
var relay_intel := false
var slug_given := false
var vpop := {}           # the boarding card: {u, type, mode: in|out|wreck, added, removed, t0}
var loot_queue: Array = []   # pickups waiting for a decision (equip or stash) after the current action
var drop_queue: Array = []   # X3: supply drops earned on the player's turn, [title, unit], opened at END TURN
var flushing := false        # X3: the queued rewards are being handed out now
var mission: Dictionary = {}
var mission_idx := 0
var uid := 1
var speed := 1.0
var acting: Unit = null
var hud = null
var acc := 0.0
var charm_used := 0
var autopick := -1        # tests: pick this option index in every modal instead of waiting
var theme := "dusk"
var breach := false       # BREACH biome: the Vharr and the Jackals are at war with each other too
var wells: Array = []     # Gravity Warden wells: {x, y, r, by}
var acids: Array = []     # acid pools from burst Hive Pods: {x, y, r, turns}; Sable's (N8) also carry dmg and owner
var ambush := {}          # E3 Drop Pod Ambush: {x, done}; pods rain down when the squad gets there
var detour := {}          # the camp detour being played: {id, x0, x1, done, left, scav, mod}
var th := {}              # the theme colors, with the biome's look laid over them
var rules := {}           # the biome's rules: sway, sight, wind, amp, wet, fuel, mines, elite
var world_w := 6400

@onready var cam: Camera2D = $Camera
@onready var terrain_sprite: Sprite2D = $TerrainSprite
@onready var chunk_layer: Node2D = $Chunks
@onready var view = $WorldView
@onready var vfx = $Vfx

# R3: the parts of the mission split out of this file. Each holds functions only; all state stays here.
var vehicle_ops: BattleVehicles  # Gears, hijacked vehicles and the Jackal Walker.
var spec_kits: BattleSpecialists  # Specialist soldiers' kits and the fifth skill branches.
var vtech: BattleAlienTech  # Vharr tech in the squad's hands.
var vharr_ai: BattleAliens  # The Vharr: alien turns, the Hive Ship and drop pods, the Boar.
var biome_rules: BattleBiomes  # Biome rules and level hazards.
var mid_events: BattleEvents  # Mid-level events, transformations and fun toggles.
var camp_ops: BattleCampaign  # Campaign-only pieces: op jobs, the pincer, camp detours and the reinforcement flare.
var boot_camp: BattleTutorial  # The training drill and the step-by-step boot camp.
var phys: BattlePhysics  # Walking, falling and thrown things.
var foe_ai: BattleEnemies  # The Jackals' side: the enemy phase, Jackal AI and the newer Jackal types.

func _init() -> void:
	vehicle_ops = BattleVehicles.new(self)
	spec_kits = BattleSpecialists.new(self)
	vtech = BattleAlienTech.new(self)
	vharr_ai = BattleAliens.new(self)
	biome_rules = BattleBiomes.new(self)
	mid_events = BattleEvents.new(self)
	camp_ops = BattleCampaign.new(self)
	boot_camp = BattleTutorial.new(self)
	phys = BattlePhysics.new(self)
	foe_ai = BattleEnemies.new(self)

# ---------------------------------------------------------------- setup
func setup(idx: int, custom := {}) -> void:
	mission_idx = idx
	mission = Data.MISSIONS[idx] if custom.is_empty() else custom
	rules = mission.get("rules", {})
	for rs in Run.soldiers:
		rs.erase("law_spent")
	breach = mission.get("breach", false)
	Run.sway_mul = rules.get("sway", 1.0)
	grav = GRAV * rules.get("grav", 1.0) * (0.5 if Run.toggle_on("moon") else 1.0)
	Run.temp_luck = 2 if Run.intel == "veterans" else 0
	theme = mission.theme
	th = Data.THEMES[theme].duplicate()
	th.merge(mission.get("look", {}), true)
	T = Terrain.new(self)
	T.build(mission)
	world_w = T.world_w
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("cells", Vector2(T.cols, Terrain.ROWS))
	mat.set_shader_parameter("tint", Vector3(th.tint.r, th.tint.g, th.tint.b))
	var gc: Color = th.grass
	mat.set_shader_parameter("grass_col", Vector3(gc.r, gc.g, gc.b))
	terrain_sprite.material = mat
	terrain_sprite.texture = T.tex
	terrain_sprite.centered = false
	terrain_sprite.scale = Vector2(CELL, CELL)
	terrain_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var i := 0
	var deployed: Array = Run.soldiers.duplicate()
	if mission.get("guest", "") != "":
		deployed.append(Run.make_guest(mission.guest))
	for s in deployed:
		if not s.alive or (mission.has("only") and s.key != mission.only):
			continue
		deploy_unit(s, 50.0 + i * 55)  # P2: far enough apart that tags, bars and clicks don't overlap
		i += 1
	if mission.get("pincer", false) and Run.campaign():
		# W9: squad B lands at the far end of the harbor and fights in from the right
		var j := 0
		for s in Run.wing_b():
			if not s.alive or Run.soldiers.has(s):
				continue
			var ub := deploy_unit(s, world_w - 140.0 - j * 50)  # clear of the HUD's button column on the right
			ub.face = -1
			ub.wing = "b"
			j += 1
		if j > 0:
			pincer = {"on": true, "view": "a", "a_cam": 0.0, "b_cam": float(world_w - W)}
	var pi := randi() % Data.POW_NAMES.size()
	var foot := 0  # plain rifleman and bomber slots seen so far (cast_foot)
	var walled := false
	for sp in T.spawns:
		var type: String = sp[0]
		var x: float = sp[1]
		var opt: Dictionary = sp[2]
		if type == "barrel":
			var u := mk_unit(); u.team = "neutral"; u.kind = "barrel"; u.x = x; u.y = T.stand_y(x, 0); u.w = 14; u.h = 18
			units.append(u); continue
		if type == "crate":
			var u := mk_unit(); u.team = "neutral"; u.kind = "crate"; u.x = x; u.y = T.stand_y(x, 0); u.w = 16; u.h = 14; u.hp = 1; u.max_hp = 1
			units.append(u)
			if opt.has("tut"):
				tut_marks[opt.tut] = tut_marks.get(opt.tut, []) + [u]
			continue
		if type == "pad":
			var py = T.stand_y(x, T.ground_at(x) - 40)
			if py == null:
				continue
			var u := mk_unit(); u.team = "neutral"; u.kind = "pad"; u.x = x; u.y = py; u.w = 26; u.h = 6
			var seq: Array = Data.BONUSES.keys()
			seq.shuffle()
			u.loot = {"seq": seq, "i": 0, "t": Data.PAD_FIRST[pads.size() % Data.PAD_FIRST.size()], "ready": false}
			units.append(u)
			pads.append(u)
			continue
		if type == "fuel" or type == "mine":
			var fy = T.stand_y(x, T.ground_at(x) - 40)
			if fy == null:  # a biome's extra drum or mine that landed over water
				continue
			var u := mk_unit(); u.team = "neutral"; u.kind = type; u.x = x; u.y = fy
			u.w = 22 if type == "fuel" else 12; u.h = 30 if type == "fuel" else 6
			units.append(u); continue
		if type == "jbox":
			biome_rules.make_jbox(x)
			continue
		if type == "acid":
			# M6: standing Hive acid that never dries up
			var ay = T.stand_y(x, 0)
			if ay != null:
				acids.append({"x": x, "y": ay, "r": 30.0, "turns": 9999})
			continue
		if type == "cart":
			var cy = T.stand_y(x, T.ground_at(x) - 40)
			if cy == null:
				continue
			var u := mk_unit(); u.team = "neutral"; u.kind = "cart"; u.x = x; u.y = cy; u.w = 26; u.h = 18; u.hp = 999; u.max_hp = 999
			units.append(u); continue
		if type == "m2":
			var u := mk_unit(); u.team = "neutral"; u.kind = "m2"; u.x = x; u.y = T.stand_y(x, T.ground_at(x) - 40); u.w = 26; u.h = 20
			u.hp = 30; u.max_hp = 30; u.heavy = true; u.face = -1; u.loot = {"sq": -1, "en": -1}
			units.append(u); continue
		if type == "pow":
			var u := mk_unit(); u.team = "neutral"; u.kind = "pow"; u.x = x; u.y = T.stand_y(x, T.ground_at(x) - opt.up) if opt.has("up") else T.stand_y(x, 0); u.face = -1
			u.pow_name = Data.POW_NAMES[pi % Data.POW_NAMES.size()]; pi += 1
			stats.pows_total += 1
			if not spec_placed():
				make_specialist(u)
			units.append(u); continue
		if (type == "grunt" or type == "nade") and not opt.has("tut"):
			type = cast_foot(foot)
			foot += 1
		elif rules.get("aliens", false) and type != "boss" and Data.ETYPES[type].get("faction", "jackal") != "vharr":
			type = cast_foot(foot)  # M6: nothing but Vharr in the Hive
			foot += 1
		if type == "boss" and mission.get("boss", "") == "hiveship":
			type = "hiveship"
		var E: Dictionary = Data.ETYPES[type]
		var y = T.stand_y(x, 0) if (opt.has("hold") or opt.has("top")) and not opt.has("inside") else T.stand_y(x, T.ground_at(x) - 40)
		if opt.has("up"):
			y = T.stand_y(x, T.ground_at(x) - opt.up)
		if type == "shield" and not walled and mission_idx >= 1 and not tutorial() and not in_lesson():
			type = "wallshield"  # E5: one Shield Wall per level from level 2
			walled = true
		var u := mk_enemy(type, x, y)
		u.hold = opt.has("hold")
		if Data.ETYPES[type].get("wall", false):
			u.fl["wall"] = u.id
		if type == "boss" or type == "hiveship":
			var bm := 1.4 if Run.threat_on(5) else 1.0
			u.hp = int(mission.boss_hp * bm); u.max_hp = u.hp; u.plate = int(mission.plate * bm) if type == "boss" else 0
			if type == "boss" and (mission.get("finale", false) or mission.get("vharr_boar", false)):
				u.fl["vharr"] = true  # Q3: the flagship comes refit with Vharr tech
			elif type == "boss" and rookie_boar():
				# D1: until a player has beaten one Boar, the level 1 Boar is a softer Rookie Boar
				u.fl["rookie"] = true
				u.hp = int(u.hp * ROOKIE_HP); u.max_hp = u.hp; u.plate = int(u.plate * ROOKIE_HP)
		elif not tutorial() and not in_lesson() and randf() < 0.12 + mission_idx * 0.06 + (0.25 if Run.intel == "veterans" else 0.0) + (0.15 if Run.threat_on(2) else 0.0) + (0.6 if mission.get("outpost", false) else 0.0) + rules.get("elite", 0.0):
			make_elite(u, pick_elite(faction(u) == "vharr"))
		units.append(u)
		if opt.has("tut"):
			tut_marks[opt.tut] = tut_marks.get(opt.tut, []) + [u]
			# drill dummies drop to one rifle shot or one frag, so each lesson lands first try
			if opt.tut in ["target", "group"]:
				u.hp = mini(u.hp, 5); u.max_hp = u.hp
		place_alien(u)
		if type == "hiveship":
			vharr_ai.hang_plates(u)
		for k in range(1, E.get("pack", 1)):
			var px := x + k * 18.0
			var mate := mk_enemy(type, px, T.stand_y(px, (y if y != null else 0.0) - 40))
			mate.hold = u.hold
			if u.fl.has("wall"):
				mate.fl["wall"] = u.fl.wall
			units.append(mate)
	if not spec_placed() and T.stretches.size():
		# X2: no prisoner in the level's segments, so the specialist is tied up mid-stretch
		var sx: float = (T.stretches[0][0] + T.stretches[0][1]) / 2.0
		var sy = T.stand_y(sx, 0)
		if sy != null:
			var p := mk_unit(); p.team = "neutral"; p.kind = "pow"; p.x = sx; p.y = sy; p.face = -1
			stats.pows_total += 1
			make_specialist(p)
			units.append(p)
	vharr_ai.place_encounter(mission.get("encounter", ""))
	vehicle_ops.place_vehicles()
	biome_rules.setup_biome()
	mid_events.setup_events()
	camp_ops.place_job()
	camp_ops.trap_varga()
	camp_ops.place_nemesis()
	spawn_map_loot()
	sel = null
	for u in units:
		if u.team == "squad" and not u.trapped:
			sel = u
			if pincer.get("on", false) and u.wing == "a":
				break  # W9: start on squad A
	for u in units:
		if u.y == null:
			u.y = WATER_Y - 4

func collect(u: Unit, p: Unit) -> void:
	## A soldier walks over a pickup. Scrip, letters, trophies and belt items apply at once;
	## gear waits for an equip-or-stash decision after the current action.
	p.gone = true
	var L: Dictionary = p.loot
	if vfx != null:
		vfx.pickup(u, p, L.type == "scrip")
	match L.type:
		"scrip":
			give_scrip(L.n, p.x, p.y - 20, "L308")
			Sfx.play("coin")
		"letter":
			var key: String = Data.LETTERS[L.key]
			for i in 3:
				u.hand.append({"id": -2, "key": key, "tier": maxi(2, Data.base_tier(key)), "temp": true})
			banner(Data.CARDS[key].name.to_upper() + "!", Color("ffd23a"), "%s GOT 3 SHOTS. THEY LAST THIS MISSION." % u.def.name)
			Sfx.play("power")
		"colors":
			u.carry = "colors"
			u.fuel = 0
			u.move_left = roundf(u.move_left * 0.6)
			banner("YOU HAVE THEIR COLORS!", Color("ffd23a"), "%s: CARRY IT TO THE GREEN POST. EVERY JACKAL IS COMING." % u.def.name)
			Sfx.play("alarm")
		"yellow":
			u.carry = "yellow"
			float_text(u, "MARKED MAN: DOUBLE SCRIP", Color("ffd23a"), true)
			log_msg("%s carries the yellow flag: their kills pay double scrip, and every Jackal wants them. Walk past a teammate to hand it over." % u.def.name)
			Sfx.play("power")
		"bow":
			u.bow = true
			u.hand.append({"id": -6, "key": "rambobow", "tier": Data.base_tier("rambobow"), "temp": true})
			banner("THE RAMBO BOW!", Color("ff7a3d"), "%s GETS AN EXPLOSIVE ARROW EVERY TURN. EVERY JACKAL HUNTS THEM." % u.def.name)
			Sfx.play("levelup")
		"gun":
			u.hand.append({"id": -2, "key": L.card, "tier": Data.base_tier(L.card), "temp": true})
			float_text(u, "GOT A " + Data.CARDS[L.card].name.to_upper() + "! ONE SHOT", Color("ffd23a"), true)
			Sfx.play("power")
		"relic":
			Run.add_gear(L.id, Data.TIER_MAX)
			for o in squad_alive():
				refresh_unit_gear(o)
			banner("BOSS TROPHY: " + Data.gear(L.id).name.to_upper(), Color("ffb21e"), Data.gear(L.id).text.to_upper())
			Sfx.play("levelup")
		"flare":
			float_text(u, "REINFORCEMENT FLARE!", Color("62d26f"), true)
			Sfx.play("power")
			para_queue.append(u)
		"trophy":
			if not Run.trophies.has(L.name):
				Run.trophies.append(L.name)
			banner("TROPHY: " + L.name, Color("ffb21e"), "%d OF 3 BOAR PARTS" % Run.trophies.size())
			Sfx.play("levelup")
		"item":
			stats.loot += 1
			if Data.ITEMS[L.item.id].slot == "belt":
				var where := Run.add_loot(L.item)
				float_text(u, "%s TO %s" % [Data.item_name(L.item).to_upper(), where.to_upper()], Color("62d26f"))
				Sfx.play("coin")
			else:
				float_text(u, Data.item_name(L.item).to_upper(), Data.tier_color(L.item.tier), true)
				Sfx.play("coin")
				loot_queue.append({"u": u, "item": L.item})
	ui_dirty = true

func offer_item(u: Unit, it: Dictionary) -> void:
	## Quick-equip prompt (G5): equip on the soldier who found it, or send it to the stash.
	var s: Dictionary = u.s
	var sl: String = Data.ITEMS[it.id].slot
	var title := "%s FOUND %s" % [u.def.name, Data.item_name(it).to_upper()]
	var opts: Array = []
	var slots: Array = []
	if sl == "kit" and s.equip.kit1 != null and s.equip.kit2 != null:
		opts = [Run.item_opt(it, "NEW: STASH IT"), Run.item_opt(s.equip.kit1, "SWAP THIS OUT"), Run.item_opt(s.equip.kit2, "SWAP THIS OUT")]
		slots = ["", "kit1", "kit2"]
	else:
		var slot := Run.slot_for(s, it)
		opts = [Run.item_opt(it, "EQUIP ON %s" % u.def.name)]
		slots = [slot]
		if s.equip[slot] != null:
			opts.append(Run.item_opt(s.equip[slot], "KEEP THIS"))
			slots.append("")
	var ch := await ask("loot", title, "Equip it now or send it to the stash. Gear can be swapped at the Armory between missions.", opts, u)
	if ch >= 0 and slots[ch] != "":
		if not Run.stash.has(it):
			Run.stash.append(it)
		Run.equip(s, it, slots[ch])
		refresh_unit_gear(u)
		log_msg("%s equipped %s." % [u.def.name, Data.item_name(it)])
	else:
		Run.add_loot(it)
		log_msg("%s sent to the stash." % Data.item_name(it))
	ui_dirty = true

func refresh_unit_gear(u: Unit) -> void:
	## Re-applies gear stats mid-mission and moves weapon cards in or out of the piles.
	var old_max := u.max_hp
	u.gb = Run.gear_bonus(u.s)
	u.max_hp = Run.eff_max_hp(u.s)
	if u.max_hp > old_max:
		u.hp += u.max_hp - old_max
	u.hp = mini(u.hp, u.max_hp)
	u.dodge = u.def.dodge + u.s.bonus.dodge + int(u.g("dodge"))
	var had_jets := u.fuel_max > 0
	u.fuel_max = jet_fuel(u)
	u.fuel = u.fuel_max if not had_jets else mini(u.fuel, u.fuel_max)
	var ids := {}
	for c in u.s.deck:
		ids[c.id] = true
	var keep := func(c): return not c.has("src") or ids.has(c.id)
	u.draw = u.draw.filter(keep)
	u.hand = u.hand.filter(keep)
	u.disc = u.disc.filter(keep)
	var have := {}
	for pile in [u.draw, u.hand, u.disc]:
		for c in pile:
			have[c.get("id", -9)] = true
	for c in u.s.deck:
		if not have.has(c.id):
			u.draw.insert(ri(0, u.draw.size()), c)

func use_belt(i: int) -> void:
	## Consumables need no card and no energy (G6).
	var u := sel
	if u == null or u.dead or busy or state != "player" or i >= Run.belt.size():
		return
	var it: Dictionary = Run.belt[i]
	var d: Dictionary = Data.ITEMS[it.id]
	Run.belt.remove_at(i)
	match d.use:
		"heal":
			var h := mini(d.n, u.max_hp - u.hp)
			u.hp += h
			float_text(u, "+%d HP" % h, Color("62d26f"), true)
			Sfx.play("heal", -4)
		"ration":
			var h := mini(d.n, u.max_hp - u.hp)
			u.hp += h
			float_text(u, "+%d HP" % h, Color("62d26f"))
			Sfx.play("heal", -4)
			give_scrip(15, u.x, u.y - 50, "L436")
		"smoke":
			smokes.append({"x": u.x, "y": u.y - 24, "r": 64.0, "turns": 2, "seed": randf() * 10})
			for k in 5:
				puff(u.x + randf_range(-30, 30), u.y - randf_range(0, 40), 3.0)
		"energy":
			u.energy += 1
			float_text(u, "+1 ENERGY", Color("ffd23a"), true)
		"stim":
			var h := mini(d.n, u.max_hp - u.hp)
			u.hp += h
			u.energy += 1
			float_text(u, "+%d HP  +1 ENERGY" % h, Color("62d26f"), true)
		"adr":
			gain_adr(u, d.n)
			float_text(u, "+%d ADRENALINE" % d.n, Color("ff7a3d"), true)
	Sfx.play("power")
	log_msg("%s used a %s." % [u.def.name, d.name])
	ui_dirty = true

func make_elite(u: Unit, mod: String) -> void:
	u.elite = mod
	u.hp = int(round(u.hp * 1.5)); u.max_hp = u.hp
	if mod == "shielded":
		u.shield = true
	if mod == "anchored":
		u.heavy = true

func pick_elite(alien: bool) -> String:
	## Jackals roll the Jackal elites, the Vharr roll their own.
	var keys := Data.ELITES.keys().filter(func(k): return Data.ELITES[k].get("vharr", false) == alien)
	return keys[randi() % keys.size()]

func spawn_map_loot() -> void:
	## Crates on roofs and in the open, the odd strongbox, and one buried cache per mission (L1, L3, L6).
	if tutorial() or in_lesson():
		return  # the drill lays out its own crate
	var lo := 520.0
	var hi := world_w - 900.0
	var n := int((hi - lo) / 360.0) * (2 if Run.intel == "surplus" else 1)
	for i in n:
		var x := lo + (i + randf_range(0.15, 0.85)) * (hi - lo) / n
		var k := "strongbox" if randf() < 0.22 else "crate"
		var ly = T.stand_y(x, 0)
		if ly == null:
			continue
		var u := mk_unit(); u.team = "neutral"; u.kind = k; u.x = x; u.y = ly
		u.w = 16 if k == "crate" else 20; u.h = 14 if k == "crate" else 14
		u.hp = 1; u.max_hp = 1
		units.append(u)
	for i in 1 + (1 if randf() < 0.4 else 0):
		var x := randf_range(lo + 200, hi)
		var gy: float = T.ground_at(x)
		if T.mat(x, gy + 16) != 1:
			continue  # only dirt hides a cache
		var c := mk_unit(); c.team = "neutral"; c.kind = "cache"; c.x = x; c.y = gy + 18; c.w = 10; c.h = 10
		units.append(c)
	# O3 Marked Man: one yellow flag lies somewhere in the level
	var fx := randf_range(lo + 300, maxf(lo + 300, hi - 300))
	var fy = T.stand_y(fx, 0)
	if fy != null:
		drop_loot(fx, fy - 4, {"type": "yellow"}, 0.0)
	# radio relays (W3): one or two per mission, each with its own buff
	var buffs: Array = Data.RELAY_BUFFS.keys()
	buffs.shuffle()
	for i in (2 if world_w > 4200 else 1):
		var x := lo + (hi - lo) * (0.3 + 0.4 * i) + randf_range(-60, 60)
		var y = T.stand_y(x, 0)
		if y == null:
			continue
		var r := mk_unit(); r.team = "neutral"; r.kind = "relay"; r.x = x; r.y = y; r.w = 12; r.h = 34
		r.loot = {"buff": buffs[i % buffs.size()], "taken": false, "hold": 0}
		units.append(r)

func drop_loot(x: float, y: float, payload: Dictionary, pop := 1.0) -> Unit:
	## A pickup that tumbles out with physics. Walk a soldier over it to collect.
	var u := mk_unit(); u.team = "neutral"; u.kind = "loot"; u.loot = payload
	u.x = x; u.y = y; u.w = 12; u.h = 12
	u.vx = randf_range(-2.2, 2.2) * pop; u.vy = -randf_range(3, 5) * pop; u.air = true
	units.append(u)
	return u

func crate_payload(min_tier := 0) -> Dictionary:
	var r := randf()
	if crate_bump > 0:
		crate_bump = 0
		return {"type": "item", "item": Run.roll_item(mini(Data.TIER_MAX, min_tier + 1))}
	if r < 0.18:
		var keys: Array = Data.LETTERS.keys().filter(func(k): return Data.LETTER_FROM.get(k, 0) <= Run.mission)
		return {"type": "letter", "key": keys[randi() % keys.size()]}
	if r < 0.36:
		return {"type": "item", "item": Run.new_item(Run.random_item_id(["belt"]))}
	if r < 0.5 and min_tier == 0:
		return {"type": "scrip", "n": ri(12, 30)}
	return {"type": "item", "item": Run.roll_item(min_tier)}

func open_crate(c: Unit, loud: bool) -> void:
	if c.dead:
		return
	c.dead = true
	c.gone = true
	debris(c.x, c.y - 6, 3)
	Sfx.play("crate")
	if c.kind == "strongbox":
		var p := crate_payload(1)
		if loud:
			alert = mini(10, alert + 1)
			float_at(c.x, c.y - 30, "LOUD! ALERT +1", Color("ff4d3d"))
			if p.type == "item" and p.item.tier > 0 and randf() < 0.3:
				p.item.tier -= 1
				Run.roll_affixes(p.item)
				float_at(c.x, c.y - 44, "CONTENTS DAMAGED", Color("ff7a3d"))
		drop_loot(c.x, c.y - 10, p)
		if randf() < 0.5:
			drop_loot(c.x, c.y - 10, {"type": "scrip", "n": ri(15, 35)})
	else:
		drop_loot(c.x, c.y - 8, crate_payload(1 if Run.mission >= 2 else 0))
	ui_dirty = true



var zaps := {}  # V5: arc ends -> tick it started, so a bolt redrawn each frame is one effect

func spec_placed() -> bool:
	## true when this level has no specialist (X2), or its POW is already on the map
	return mission.get("specialist", "") == "" or units.any(func(p): return p.fl.has("specialist"))

func make_specialist(p: Unit) -> void:
	var key: String = mission.specialist
	p.fl["specialist"] = key
	p.pow_name = Data.SPECIALISTS[key].pow

func free_specialist(q: Dictionary) -> void:
	## X2: a specialist POW is cut loose. Their class unlocks for good and they fight with you.
	if q.pow.gone:
		return  # already cut loose this action
	var key: String = q.pow.fl.specialist
	var D: Dictionary = Run.class_def(key)
	var s := Run.free_specialist(key)
	banner("%s RESCUED!" % D.name, Color("ffd23a"), "%s UNLOCKED" % D.cls.to_upper())
	Sfx.play("levelup")
	score += 800
	stats.pows += 1
	give_xp(q.u, 10)
	q.pow.gone = true
	if s.is_empty():
		log_msg("%s the %s is in the squad draft now. Pick them before your next run." % [D.name, D.cls])
		await wait(50)
		return
	if Run.reserve.has(s):
		float_at(q.pow.x, q.pow.y - 40, "TO THE BARRACKS", Color("62d26f"), true)
		log_msg("The squad is full, so %s the %s waits in the barracks. Swap them in at HQ, or parachute them in with a reinforcement flare." % [D.name, D.cls])
		await wait(50)
		return
	var u := deploy_unit(s, q.pow.x, q.pow.y)
	u.face = 1
	u.energy = 0
	u.move_left = 0
	float_text(u, "REPORTING IN", Color("62d26f"), true)
	bark(u, "Took you long enough. Hand me a wrench." if key == "bolt" else "Let's go.")
	log_msg("%s the %s joins the squad for the rest of this run, and is in the squad draft from now on." % [D.name, D.cls])
	ui_dirty = true
	await wait(50)

func deploy_unit(s: Dictionary, x: float, y = null) -> Unit:
	## Puts a squad record on the field as a unit (mission start, or a freed specialist, X2).
	var u := mk_unit()
	u.team = "squad"; u.kind = "soldier"; u.def = s.def; u.s = s; u.sheet = Art.look_sheet(s)
	u.gb = Run.gear_bonus(s)
	u.x = x; u.y = T.stand_y(x, 0); u.face = 1; u.max_hp = Run.eff_max_hp(s); u.hp = mini(s.hp, u.max_hp)
	u.dodge = s.def.dodge + s.bonus.dodge + int(u.g("dodge"))
	u.second_wind = s.perks.has("secondwind")
	u.fuel_max = jet_fuel(u)
	u.fuel = u.fuel_max
	var deck: Array = s.deck.duplicate()
	deck.shuffle()
	u.draw = deck
	if Run.implanted(s, "adrenal"):
		u.adr = 25
	if Run.has_gear("warpaint"):
		u.adr = maxi(u.adr, 50 if Run.relic_tier("warpaint") >= 3 else 25)
	if s.get("spec", "") == "engineer":
		u.dome = 2  # C7 Gate Tech: the Engineer deploys under a dome
	if Run.campaign() and Run.soldiers.any(func(o): return o.alive and Run.rank(o) >= Data.RANKS.size() - 1):
		u.dodge += Data.CAPTAIN_DODGE  # C3: a Captain in the squad steadies everyone
	if y != null:
		u.y = y
	units.append(u)
	if s.def.key == "track":
		spec_kits.make_rex(u)  # N7: Rex deploys at Track's side
	if s.def.key == "gears":
		vehicle_ops.mount(u, "tank" if ks(u, "treads") else "walker", -1, true)  # N3: Gears deploys in his walker
	return u

func mk_unit() -> Unit:
	var u := Unit.new()
	uid += 1
	u.id = uid
	return u

func mk_enemy(type: String, x: float, y) -> Unit:
	var E: Dictionary = Data.ETYPES[type]
	var u := mk_unit()
	u.team = "enemy"; u.kind = "enemy"; u.type = type; u.x = x; u.y = y if y != null else WATER_Y - 4
	u.w = E.w; u.h = E.h
	u.hp = int(round(E.hp * mission.hp_mul * (1.2 if Run.threat_on(4) else 1.0))); u.max_hp = u.hp; u.face = -1
	u.heavy = E.get("heavy", false); u.shield = E.get("shield", false)
	u.weight = E.get("weight", "")
	u.pod = int(round(E.get("pod", 0) * mission.hp_mul))
	var sk: String = E.get("sheet", "en_" + type)
	u.sheet = sk if Art.meta.has(sk) else ""
	return u

const ALIENS := ["skitter", "squid", "blinker"]

func cast_foot(n: int) -> String:
	## Who fills the nth plain rifleman or bomber slot. The Jackals' pact with the Vharr goes bad over
	## a run: level 1 keeps its riflemen with every fourth slot a Vharr advisor, later levels and the
	## finale give every slot to the Vharr. Bombers are gone either way.
	## Each biome sends its own Vharr (Data.BIOME_ALIENS).
	var pool: Array = Data.BIOME_ALIENS.get(mission.get("biome", ""), ALIENS)
	if rules.get("aliens", false):
		return pool[n % pool.size()]
	var tier := 2 if mission.get("finale", false) else mission_idx
	if tier == 0:
		if n % 8 == 5:
			return "gatetrooper"  # H7: a Jackal with a stolen Vharr ray
		match n % 12:
			2: return "jsniper"  # E1
			6: return "flamer"  # E2
			9: return "jdog"  # E4, a pack of three
		return "grunt" if n % 4 != 3 else pool[(n / 4) % pool.size()]
	if tier >= 2 and n == 1:
		return "overseer"  # from level 3 an Overseer runs the Jackals that are left
	if n % 10 == 4:
		return "jsniper"  # the Jackal snipers stay on through the whole war
	return pool[n % pool.size()]

func place_alien(u: Unit) -> void:
	## A hovering alien starts at its altitude instead of on the floor.
	if u.weight == "hover" and u.y != null:
		u.y = vharr_ai.hover_y(u, u.x, u.y)

func is_thrall(u: Unit) -> bool:
	return u.elite == "thrall" or u.fl.get("thrall", false)

func shrug(u: Unit) -> bool:
	## H6 Thrall: the parasite holds it upright through the first knockback.
	if u.dead or not is_thrall(u) or u.fl.get("shrugged", false):
		return false
	u.fl["shrugged"] = true
	float_text(u, "SHRUGS IT OFF", Color("9df25c"))
	return true

func well_acc(x: float, y: float) -> Vector2:
	## The pull of every Gravity Warden well on a thrown thing at x, y.
	var a := Vector2.ZERO
	for w in wells:
		var d := Vector2(w.x - x, w.y - y)
		var reach: float = w.r * 1.6
		var L := d.length()
		if L < reach and L > 4:
			a += d / L * 0.16 * (1.0 - L / reach)
	return a

func kb(u: Unit) -> float:
	## Knockback multiplier for a weight class: light aliens fly twice as far.
	return 2.0 if u.weight == "light" else 1.0

func _ready() -> void:
	set_process_unhandled_input(true)

func begin() -> void:
	Sfx.play("start")
	if practice():
		dummies = units.filter(func(e): return e.team == "enemy").map(func(e): return [e.type, e.x])
		banner("PRACTICE RANGE", Color("62d26f"), "FREE. NOTHING HERE CARRIES OVER")
		log_msg("The dummies never shoot back and come back when they are all down. LEAVE RANGE when you are done.")
	elif in_lesson():
		boot_camp.lesson_prep()
		if mission.get("retry", "") == "":
			banner(mission.banner, Color("ffb23e"), mission.name)
	else:
		banner(mission.get("banner", "MISSION %d START!" % (mission_idx + 1)), Color("ffb23e"), mission.name)
	if breach:
		log_msg("BREACH: the Vharr and the Jackals are fighting each other. Each shoots whoever is nearest, so let them.")
	if hud != null and Run.tips_on() and Run.history.is_empty() and not practice() and not tutorial() and not in_lesson():
		coach_start()
	camp_ops.activate_enemies()
	await wait(60 if mission.get("retry", "") == "" else 8)  # a retried lesson is straight back in
	if state == "title":
		start_player_turn()

const LAVA_MAX := 8      # M5: the most steps the lava climbs before it holds
const ICE_HEAVY := ["brute", "dicokka", "jwalker", "boss", "mortarcrew", "wallshield"]
var lava_k := 0          # M5: steps the lava has climbed since the squad last pushed or made camp
var sweeps: Array = []   # M2 tunnel, M7 taxiing jet: {k, x0, x1, every, left, t0}

var crumble := {}        # R3: {x0, x1, x, on} the edge of the stretch that is falling away

func synergy_board() -> Array:
	## The squad's switched-on synergies for the top right, above the bounty board: full gear sets,
	## duos whose card is in hand right now, and one line for every duo pair still on the field
	## ("quiet" until a pair is both pumped: then it only shows in the SYNERGIES header tip).
	var out: Array = []
	var sq := squad_alive()
	for u in sq:
		for sy in Run.synergies(u.s):
			if sy.kind == "set" and sy.done:
				out.append({"name": sy.name, "who": u.def.name, "text": sy.text, "c": Color("62d26f")})
	var pairs: Array = []
	var close := false  # P5: a pair with both soldiers pumped or past it is near its duo Overdrive
	for d in Data.DUOS:
		var pair: Array = sq.filter(func(u): return d.pair.has(u.def.key))
		if pair.size() < 2:
			continue
		pairs.append("%s (%s+%s)" % [Data.CARDS[d.card].name, pair[0].def.name, pair[1].def.name])
		close = close or pair.all(func(u): return u.adr >= 50)
		if pair.any(func(u): return u.hand.any(func(c): return c.get("duo", "") != "" and c.key == d.card)):
			out.append({"name": "DUO " + Data.CARDS[d.card].name.to_upper(), "who": "READY", "text": Run.duo_tip(d) + " In hand now.", "c": Color("ffb23e")})
	if pairs.size():
		out.append({"name": "DUO PAIRS", "who": str(pairs.size()), "c": Color("b48cff"), "quiet": not close,
			"text": "When both soldiers of a pair have an Overdrive ready and stand close, a duo Overdrive card appears. On the field: %s." % ", ".join(pairs)})
	return out

func bounty_board() -> Array:
	## R5 on the field: each of the level's bounties with "done", "lost" (no longer possible) or ""
	## and a short progress note, for the board in the top right.
	var out: Array = []
	var foes := units.filter(func(e): return e.team == "enemy" and not e.dead and not e.gone and not e.fl.get("turned", false))
	for id in mission.get("bounties", []):
		var bt: Dictionary = Run.bounty(id)
		var st := ""
		var prog := ""
		match id:
			"nofall":
				st = "lost" if stats.falls > 0 else ""
			"nodown":
				st = "lost" if stats.downs > 0 or stats.kia > 0 else ""
			"sniperfirst":
				if stats.has("first_kill"):
					st = "done" if stats.first_kill == "jsniper" else "lost"
			"crush2":
				prog = "%d/2" % mini(2, stats.crushes)
				if stats.crushes >= 2:
					st = "done"
				elif stats.crushes + foes.filter(func(e): return faction(e) == "jackal").size() < 2:
					st = "lost"
			"pows":
				prog = "%d/%d" % [stats.pows, stats.pows_total]
				if units.any(func(o): return o.kind == "pow" and o.dead and not o.freed):
					st = "lost"
			"push3":
				prog = "%d/3" % mini(3, stats.pushes)
				if stats.pushes >= 3:
					st = "done"
				elif cam_x >= world_w - W - 1:
					st = "lost"
			"fast":
				prog = "RND %d/18" % round_n
				st = "lost" if round_n > 18 else ""
			"melee3":
				prog = "%d/3" % mini(3, stats.melee_kills)
				if stats.melee_kills >= 3:
					st = "done"
				elif stats.melee_kills + foes.size() < 3:
					st = "lost"
		out.append({"name": bt.name, "pay": int(bt.pay), "text": bt.text, "state": st, "prog": prog})
	return out

# ---------------------------------------------------------------- helpers
func practice() -> bool:
	return mission.get("practice", false)

const TUT_MOVE := 0
const TUT_SHOOT := 1
const TUT_CRATE := 2
const TUT_THROW := 3
const TUT_PUSH := 4
const TUT_FIGHT := 5
const TUT_DONE := 6
const TUT_FLAG_X := 300.0     # D2: the walk step's flag; reaching it ends the step

func tutorial() -> bool:
	return mission.get("tutorial", false)

func in_lesson() -> bool:
	return mission.has("lesson")

func lesson() -> Dictionary:
	return mission.get("lesson", {})

func lesson_flag():
	## Where a lesson's flag stands (on top of whatever is there), or null for a lesson with none.
	var L := lesson()
	if L.get("goal", "") != "flag":
		return null
	var fx: float = L.fx
	var fy = T.stand_y(fx, 0)
	return Vector2(fx, fy if fy != null else T.ground_at(fx))

# ---------------------------------------------------------------- squad lists, waits and floating text
func squad() -> Array:
	return units.filter(func(u): return u.team == "squad")

func squad_alive() -> Array:
	return units.filter(func(u): return u.team == "squad" and not u.dead)

func log_msg(m: String) -> void:
	if debug:
		print("[log r%d] %s" % [round_n, m])
	log_lines.append(m)
	log_at.append(t)
	if log_lines.size() > 4:
		log_lines.pop_front()
		log_at.pop_front()
	ui_dirty = true

func wait(n: int) -> void:
	for i in n:
		await tick

func until(cond: Callable) -> void:
	while not cond.call():
		await tick

func settled() -> bool:
	if projs.size() or booms.size() or T.chunks_falling() or absf(cam_x - cam_tx) >= 0.5:
		return false
	for u in units:
		if u.sunk or u.gone:
			continue
		if u.walk != null or u.zip != null or u.drill != null or u.slide != 0 or (u.air and not u.para and not u.hang):
			return false
	return true

func gauss() -> float:
	return (randf() + randf() + randf() - 1.5) * 1.15

func wet() -> bool:
	## Monsoon intel or a soaked biome: fire does 1 damage and won't spread.
	return Run.intel == "monsoon" or rules.get("wet", false)

func ri(a: int, b: int) -> int:
	return randi_range(a, b)

func pick(a: Array):
	return a[randi() % a.size()]

# ---------------------------------------------------------------- fx
func float_text(u: Unit, text: String, c := Color.WHITE, big := false) -> void:
	var n := texts.filter(func(tx): return tx.u == u and tx.t < 20).size()
	texts.append({"u": u, "x": u.x, "y": clear_text_y(u.x, u.y - u.h - 10 - n * 14, text), "text": text, "c": c, "big": big, "t": 0})

func float_at(x: float, y: float, text: String, c := Color.WHITE, big := false) -> void:
	texts.append({"u": null, "x": x, "y": clear_text_y(x, y, text), "text": text, "c": c, "big": big, "t": 0})

func clear_text_y(x: float, y: float, text: String) -> float:
	## Lift a new floating text above any young one it would land on, so a big chain
	## (pile-up, combo, overkill, level ups) stacks into lines instead of one smear.
	var half := Art.text_width(text, 8) / 2.0 + 6
	for k in 10:
		var hit := false
		for tx in texts:
			var ty: float = tx.y - tx.t * 0.6
			var tx_x: float = tx.u.x if tx.u != null else tx.x
			var tw := Art.text_width(tx.text, 16 if tx.big else 8) / 2.0
			if tx.t < 45 and absf(ty - y) < (18 if tx.big else 12) and absf(tx_x - x) < half + tw:
				hit = true
				break
		if not hit:
			break
		y -= 14
	return y

func banner(text: String, c := Color("ffb23e"), sub := "") -> void:
	banners.append({"text": text, "c": c, "sub": sub, "t": 0, "dur": 90})

func bark(u: Unit, text: String) -> void:
	if u == null:
		return  # ownerless blasts (barrels, volatile elites) have no one to shout
	barks = barks.filter(func(b): return b.u != u)
	barks.append({"u": u, "text": text, "t": 0})

func tracer(x1: float, y1: float, x2: float, y2: float, c: Color) -> void:
	tracers.append({"x1": x1, "y1": y1, "x2": x2, "y2": y2, "c": c, "t": 9})

func part(d: Dictionary) -> void:
	parts.append(d)

func splash(x: float) -> void:
	Sfx.play("splash")
	for i in 18:
		part({"x": x + (randf() - .5) * 10, "y": WATER_Y, "vx": (randf() - .5) * 3, "vy": -randf() * 5 - 1, "life": 40, "max": 40, "c": Color("9fe3f0"), "s": 3.0, "g": 0.2})

func dust(x: float, y: float, c := Color("c9b38a"), n := 6) -> void:
	for i in n:
		part({"x": x, "y": y, "vx": (randf() - .5) * 2.5, "vy": -randf() * 2, "life": 30, "max": 30, "c": c, "s": 2.0, "g": 0.08})

func puff(x: float, y: float, sc := 1.0) -> void:
	fx.append({"kind": "puff", "x": x, "y": y, "t": 0, "dur": 24, "sc": sc, "vy": -0.4})

func sparks(x: float, y: float, n := 5) -> void:
	for i in n:
		part({"x": x, "y": y, "vx": (randf() - .5) * 4, "vy": -randf() * 3, "life": 14, "max": 14, "c": Color("fff3a0"), "s": 2.0, "g": 0.2, "fire": true})

const MATCOL := {1: Color("86582f"), 2: Color("8e939a"), 3: Color("80562e"), 4: Color("62503f"), 5: Color("6f777f"), 6: Color("a9b0b6"), 7: Color("bfe6f5"), 8: Color("2a332c"), 9: Color("7a8088")}

func debris(x: float, y: float, m: int, slow := false) -> void:
	var c: Color = MATCOL.get(m, Color("888888"))
	if slow:
		part({"x": x, "y": y, "vx": (randf() - .5) * 2, "vy": -1.0, "life": 50, "max": 50, "c": c, "s": 4.0, "g": 0.25})
	else:
		part({"x": x, "y": y, "vx": (randf() - .5) * 6, "vy": -randf() * 6 - 1, "life": 60, "max": 60, "c": c, "s": 3.0, "g": 0.25})

func fireball(x: float, y: float, r: float, burn := false) -> void:
	Sfx.play("flame", -4)
	# V1: the Sprite Fusion pixel blast (vfx/sf_explosion.gd). The boom entry stays so the critters
	# scatter and the effects layer still sees it, but the old sprite, embers and ring are not drawn.
	fx.append({"kind": "boom", "x": x, "y": y, "t": 0, "dur": 42, "sc": clampf(r / 24.0, 0.7, 3.2), "sf": true})
	if x > cam_x - 160 and x < cam_x + W + 160:
		var m := 0
		for k in 8:
			m = T.mat(x, y + k * 4)
			if m != 0:
				break
		vfx.add(SfExplosion.new(x, y, clampf(r / 48.0, 0.5, 2.0), vfx.ground_fn(y), MATCOL.get(m, Color("6a5a48")), 0.6 if burn else 0.3))

# ---------------------------------------------------------------- sight & bullets
func eye_of(u: Unit, x: float, y: float, face: int) -> Vector2:
	return Vector2(x + face * 5, y - u.h + 8)

func muzzle(u: Unit) -> Vector2:
	if u.type == "boss":
		return boss_pivot(u) + Vector2(-60, 0).rotated(u.aim_a)
	if u.type == "mg":
		return Vector2(u.x - 18, u.y - 16)
	return Vector2(u.x + u.face * 14, u.y - u.h + 15)

func boss_pivot(u: Unit) -> Vector2:
	return Vector2(u.x - 20, u.y - 56)

func smoke_at(x: float, y: float) -> bool:
	for s in smokes:
		var dx: float = x - s.x
		var dy: float = y - s.y
		if dx * dx + dy * dy < s.r * s.r * 0.7:
			return true
	return false

func gas_at(x: float, y: float):
	for g in gases:
		if Vector2(x - g.x, y - g.y).length() < g.r * 0.85:
			return g
	return null

func tag(key: String, x: float, y: float, once := true, who = null) -> bool:
	## A tag-team combo fired (C3). Returns false when it already paid out this action.
	## The soldier behind it earns style XP (P6); Brothers in Arms also draws them a card.
	if once and act_once.has(key):
		return false
	act_once[key] = true
	stats.tags += 1
	if key in ["skeet", "pinball"]:
		announce_unlock(Run.feat(key))
	if who == null:
		who = act_unit
	if who is Unit and who.team == "squad" and not who.dead:
		give_xp(who, 3)
		if Run.has_cmd("brothers") and state == "player":
			draw_cards(who, 1)
	float_at(x, y - 50, Data.TAGS[key].name, Color("b48cff"), true)
	if feed.size() and feed[-1].t < 90 and not feed[-1].stamp.contains(Data.TAGS[key].name):
		feed[-1].stamp = (feed[-1].stamp + " " + Data.TAGS[key].name).strip_edges()
	Sfx.play("power", -4)
	log_msg("%s %s" % [Data.TAGS[key].name, Data.TAGS[key].text])
	return true

func add_status(u: Unit, k: String, turns: int, by = null) -> void:
	## C5 statuses. Props, pickups and POWs ignore them; the boss shrugs off stun.
	if u == null or u.dead or u.gone or u.is_prop() or u.is_pickup() or u.kind == "pow":
		return
	if k == "stun" and (is_boss(u) or u.team == "squad"):
		return
	if k == "toxic" and u.team == "squad" and u.def.key == "sable":
		return
	if k == "burn" and ks(by, "fuelpack"):
		turns = maxi(turns, 4)
	var fresh := not u.has_st(k)
	u.st[k] = maxi(u.st.get(k, 0), turns)
	if k == "supp" and by is Unit and by.team == "squad":
		by.fl["supp_n"] = by.fl.get("supp_n", 0) + 1
	if by != null:
		u.st_by[k] = by
	if fresh:
		float_text(u, Data.STATUS[k].name, Data.STATUS[k].c)
	ui_dirty = true

func announce_unlock(name_: String) -> void:
	if name_ != "":
		banner("ARMORY UNLOCK!", Color("b48cff"), name_.to_upper() + " CAN NOW DROP")
		Sfx.play("levelup")
		log_msg("Armory unlock: %s joins the loot pool for every run." % name_)

func ks(u, id: String) -> bool:
	## Is this soldier wearing a keystone item?
	return u != null and u is Unit and u.team == "squad" and u.g("ks_" + id) > 0

func chain(u: Unit, name_: String) -> void:
	## A signature chain (C2) completed: big purple callout and a little style XP.
	float_text(u, name_ + "!", Color("e0b0ff"), true)
	Sfx.play("power", -4)
	give_xp(u, 2)
	log_msg("Chain: %s." % name_)

func chain_ready(u: Unit, inst: Dictionary) -> String:
	## The chain this card would complete if played now ("" if none), so the hand can glow.
	if u == null or u.team != "squad":
		return ""
	var c := Data.card(inst)
	var last: String = u.seq[-1][0] if u.seq.size() else ""
	match u.def.key:
		"moss":
			if last == "digin" and c.type == "AIM":
				return "KNOCK KNOCK"
			if last == "tagshot" and inst.key == "snipe":
				return "SPOTTED"
			if last == "digin" and c.get("overwatch", false):
				return "DUG IN"
			if c.type == "AIM" and u.fl.get("free_aim", false):
				return "DOUBLE BANK"
			if c.type == "AIM" and u.seq.size() >= 2 and u.seq[-1][1] == "AIM" and u.seq[-2][1] == "AIM" and not u.fl.has("sixgun"):
				return "SIX SHOOTER"
		"hex":
			if last == "handoff" and inst.key == "medkit":
				return "TEAMWORK"
			if Data.is_attack(c) and u.seq.size() >= 2 and u.seq[-1][0] == "sprint" and u.seq[-2][0] == "smoke":
				return "FROM THE FOG"
			if inst.key == "shotgun" and u.fl.get("healed", false):
				return "SCRUBBED IN"
		"vee":
			if last == "stickycharge" and inst.key == "clacker":
				return "SET AND FORGET"
			if c.type in ["ARC", "LINE"] and c.has("dmg") and u.fl.get("jumped", false):
				return "DEATH FROM ABOVE"
			if c.has("radius") and u.fl.get("molotov", false) and inst.key != "molotov":
				return "ACCELERANT"
		"gears":
			if last == "vulcan" and inst.key == "stomp":
				return "WALK THE LINE"
			if inst.key == "mcannon" and u.fl.get("cannoned", false) and not u.fl.has("broadside"):
				return "BROADSIDE"
			if last == "eject" and inst.key == "patchjob":
				return "BAIL OUT"
			if last == "patchjob" and Data.is_attack(c):
				return "PIT STOP"
		"track":
			if last == "sicem" and c.type == "AIM":
				return "TAG TEAM"
			if last == "fetch" and inst.key == "whistle":
				return "GOOD BOY"
			if Data.is_attack(c) and u.fl.has("guarded") and not u.fl.has("onguard"):
				return "ON GUARD"
			if last == "whistle" and inst.key == "sicem":
				return "THE HUNT"
		"bolt":
			if c.type == "AIM" and u.fl.get("sentried", false) and not u.fl.has("covered"):
				return "COVERING FIRE"
			if inst.key == "sandbags" and u.fl.get("bagged", false) and not u.fl.has("stacked"):
				return "DOUBLE STACK"
		"finch":
			if last == "zipline" and c.type == "AIM":
				return "ZIP AND SNIP"
			if last == "flare" and c.type == "AIM":
				return "LIGHT 'EM UP"
			if last == "drone" and inst.key == "knives":
				return "EYE IN THE SKY"
			if last == "knives" and inst.key == "knives":
				return "KNIFE PARTY"
		"kage":
			if last == "deflect" and inst.key == "katana":
				return "RIPOSTE"
			if last == "vanish" and inst.key == "katana":
				return "FROM NOWHERE"
			if last == "walljump" and inst.key == "katana":
				return "AIR STRIKE"
			if last == "katana" and inst.key == "katana":
				return "DRAW CUT"
		"volta":
			if last == "magnet" and inst.key == "repulsor":
				return "SLINGSHOT"
			if last == "gravnade" and inst.key == "magnet":
				return "EVENT HORIZON"
			if last == "tesla" and inst.key == "tesla":
				return "CONDUCTOR"
			if last == "repulsor" and inst.key == "magnet":
				return "NEWTON'S THIRD"
		"brass":
			if last == "designator" and inst.key == "designator":
				return "BRACKET"
			if last == "orders" and inst.key == "designator":
				return "ON MY MARK"
			if last == "supplydrop" and inst.key == "orders":
				return "RESUPPLY"
			if last == "designator" and c.type == "AIM":
				return "CALL IT IN"
		"sable":
			if last == "blink" and Data.is_attack(c):
				return "NOW YOU SEE ME"
			if last == "acidspit" and inst.key == "tongue":
				return "MELTDOWN"
			if last == "mindlink" and inst.key == "tongue":
				return "PUPPETEER"
			if last == "gravnade" and inst.key == "acidspit":
				return "HOLD STILL"
		"rook":
			if last == "grab" and inst.key == "bodythrow":
				return "TAG OUT"
			if last == "taunt" and inst.key == "digin":
				return "COME AND GET IT"
			if last == "grapple" and inst.key == "knife":
				return "ZIP STRIKE"
	if inst.get("od", false) and u.fl.get("juiced", false):
		return "JUICED"
	return ""

func targetable(e: Unit, tg: Unit) -> bool:
	## Ghillie (Hex capstone): squadmates in smoke who haven't attacked this turn are invisible.
	if tg.has_st("cloak"):
		return false
	if tg.attacked or not smoke_at(tg.x, tg.y - tg.h / 2.0):
		return true
	return not squad_alive().any(func(h): return h.perk("ghillie"))

func tick_statuses(team: String) -> void:
	## Burning and toxic hurt at the start of their side's turn. Gas poisons whoever stands in it.
	for u in units.filter(func(o): return o.team == team and not o.dead and not o.gone):
		var g = gas_at(u.x, u.y - u.h / 2.0)
		if g != null:
			add_status(u, "toxic", 2, g.owner)
		if u.has_st("burn"):
			for i in 4:
				part({"x": u.x + randf_range(-6, 6), "y": u.y - randf() * u.h, "vx": 0.0, "vy": -1.5, "life": 24, "max": 24, "c": Color("ff9a3d"), "s": 3.0, "g": -0.02, "fire": true})
			var bsrc = u.st_by.get("burn", null)
			var bd := 1 if wet() else 3 + (2 if bsrc is Unit and bsrc.perk("accelerant") else 0)
			burn_tick = true
			kill_how = "BURN"
			damage(u, bd, bsrc, {"status": true})
			kill_how = ""
			burn_tick = false
			if g != null:
				# fire meets gas: the whole cloud goes up
				gases.erase(g)
				explode(g.x, g.y, g.r * 0.8, 12, g.owner)
			elif T.mat(u.x, u.y + 2) == 3 and not wet():
				# the wood underfoot chars and the fire jumps to anyone else standing on wood nearby
				T.carve(u.x, u.y + 3, 6, null)
				for o in units:
					if o != u and not o.dead and absf(o.x - u.x) < 44 and absf(o.y - u.y) < 30 and T.mat(o.x, o.y + 2) == 3:
						add_status(o, "burn", 2, u.st_by.get("burn", null))
		if u.has_st("toxic") and not u.dead:
			var a: int = u.armor
			u.armor = 0
			kill_how = "TOXIC"
			damage(u, 2, u.st_by.get("toxic", null), {"status": true})
			kill_how = ""
			u.armor = a
		for k in ["burn", "toxic", "mark", "berserk", "cloak", "flamegod", "vest", "roll", "flared", "pinned", "fat", "zombie"]:
			if u.st.has(k):
				u.st[k] -= 1
				if u.st[k] <= 0:
					u.st.erase(k)
		mid_events.fat_end(u)

func ray_clear(x1: float, y1: float, x2: float, y2: float) -> bool:
	var dx := x2 - x1
	var dy := y2 - y1
	var n := int(ceil(sqrt(dx * dx + dy * dy) / 3.0))
	for i in range(2, n):
		var x := x1 + dx * i / n
		var y := y1 + dy * i / n
		if T.hard(x, y) or smoke_at(x, y):
			return false
	return true

func cast_ray(x: float, y: float, ang: float, max_len: float) -> Dictionary:
	var dx := cos(ang)
	var dy := sin(ang)
	var d := 4.0
	while d < max_len:
		var px := x + dx * d
		var py := y + dy * d
		if py > H or py < -50:
			return {"x": px, "y": py, "hit": false}
		if T.hard(px, py):
			return {"x": px, "y": py, "hit": true}
		d += 3
	return {"x": x + dx * max_len, "y": y + dy * max_len, "hit": false}

func visible_points(ex: float, ey: float, tg: Unit) -> Array:
	var out: Array = []
	for py in [tg.y - tg.h + 5, tg.y - tg.h / 2.0, tg.y - 5]:
		if ray_clear(ex, ey, tg.x, py):
			out.append(py)
	return out

func visibility(a: Unit, tg: Unit) -> int:
	var f := 1 if tg.x >= a.x else -1
	var e := muzzle(a) if a.type == "boss" or a.type == "mg" else eye_of(a, a.x, a.y, f)
	return visible_points(e.x, e.y, tg).size()

func dist(a: Unit, b: Unit) -> float:
	return Vector2(a.x - b.x, (a.y - a.h / 2.0) - (b.y - b.h / 2.0)).length()

func unit_at_point(x: float, y: float, shooter, travelled: float, skip: Dictionary):
	for u in units:
		if skip.has(u.id):
			continue
		if u.is_body() and u.soak > 0:
			# a body lying in the open is cover for both sides
			if x >= u.x - u.w / 2.0 and x <= u.x + u.w / 2.0 and y >= u.y - u.h and y <= u.y:
				return u
			continue
		if u.dead or u.gone or u.sunk or u.kind == "pow" or u.kind == "ride" or u.kind == "hulk" or u.kind == "sticky" or u.is_pickup() or u.weight == "buried" or u.fl.get("phased", false):
			continue
		if u.has_st("cloak") and shooter != null and shooter.team != u.team:
			continue  # PREDATOR: rounds pass right through the shimmer
		if u == shooter and travelled < 40:
			continue
		if shooter != null and u != shooter and u.team != "" and u.team == shooter.team and not at_war(u, shooter):
			continue  # bullets slip past teammates, explosions don't (in a BREACH the two factions aren't teammates)
		if u.kind == "slug" or ((u.kind == "truck" or u.kind == "sentry" or u.kind == "dog") and shooter != null and shooter.team == "squad"):
			continue
		if x >= u.x - u.w / 2.0 and x <= u.x + u.w / 2.0 and y >= u.y - u.h and y <= u.y:
			return u
		if u.para and shooter != null and shooter.team == "squad" and absf(x - u.x) < 16 and y >= u.y - 62 and y < u.y - u.h:
			return u  # E3: the chute above a paratrooper
	return null

func trace_bullet(x: float, y: float, ang: float, max_len: float, bounces: int, shooter, pierce: bool, pass_mat := 0, soft := 0, bodies := 0) -> Dictionary:
	## SteamWorld Heist style bullet: straight line, bounces off stone, stops in the first body unless it pierces.
	var segs: Array = []
	var hits: Array = []
	var pings: Array = []
	var ping_d: Array = []
	var dx := cos(ang)
	var dy := sin(ang)
	var sx := x
	var sy := y
	var px := x
	var py := y
	var trav := 0.0
	var skip := {}
	var in_soft := false  # B1 Wallbanger: inside a wall of wood or dirt it is punching through
	var walled := false
	while trav < max_len:
		var nx := px + dx * 2
		var ny := py + dy * 2
		trav += 2
		if ny > H or ny < -80 or nx < 0 or nx > world_w:
			segs.append([sx, sy, nx, ny])
			return {"segs": segs, "hits": hits, "pings": pings, "ping_d": ping_d, "len": trav, "end": null}
		var u = unit_at_point(nx, ny, shooter, trav, skip)
		if u != null and u.type == "prism" and dx * u.face < 0:
			# the Prism Drone's mirror face: the round bounces off it like off stone, free of charge
			dx = -dx
			skip[u.id] = true
			segs.append([sx, sy, px, py])
			pings.append(Vector2(px, py))
			ping_d.append(trav)
			sx = px
			sy = py
			continue
		if u != null:
			hits.append({"u": u, "x": nx, "y": ny, "dx": dx, "d": trav, "head": not u.heavy and not u.is_prop() and ny < u.y - u.h * 0.72, "thru": walled})
			skip[u.id] = true
			if not pierce and bodies > 0 and not u.is_prop():
				bodies -= 1
			elif not pierce:
				segs.append([sx, sy, nx, ny])
				return {"segs": segs, "hits": hits, "pings": pings, "ping_d": ping_d, "len": trav, "end": null}
		if in_soft and not T.hard(nx, ny):
			in_soft = false
			soft -= 1
		if soft > 0 and T.hard(nx, ny) and T.mat(nx, ny) in [1, 3]:
			in_soft = true
			walled = true
			px = nx
			py = ny
			continue
		if T.hard(nx, ny) and (pass_mat == 0 or (pass_mat > 0 and T.mat(nx, ny) != pass_mat)):
			var m := T.mat(nx, ny)
			if bounces > 0 and (m == 2 or m == 4):
				var hx := T.hard(nx, py)
				var hy := T.hard(px, ny)
				if hx and not hy:
					dx = -dx
				elif hy and not hx:
					dy = -dy
				else:
					dx = -dx
					dy = -dy
				segs.append([sx, sy, px, py])
				pings.append(Vector2(px, py))
				ping_d.append(trav)
				sx = px
				sy = py
				bounces -= 1
				continue
			segs.append([sx, sy, nx, ny])
			return {"segs": segs, "hits": hits, "pings": pings, "ping_d": ping_d, "len": trav, "end": {"x": nx, "y": ny, "m": m}}
		px = nx
		py = ny
	segs.append([sx, sy, px, py])
	return {"segs": segs, "hits": hits, "pings": pings, "ping_d": ping_d, "len": trav, "end": null}

func laser_of(u: Unit, c: Dictionary) -> float:
	## How far this soldier's aim laser reaches with this card. Bullets always go further.
	var step := 1 if Run.has_gear("laser") else 0
	var pct := 0.0
	if u != null and u.team == "squad":
		step += Run.laser_steps(u.s)
		pct += Run.laser_pct(u.s)
	return Data.laser_len(c, step, pct)

func bounce_bonus(a: Unit, sc: bool) -> int:
	var n := 1 if sc else 0
	if a.team == "squad" and a.perk("trick"):
		n += 1
	if a.team == "squad" and a.perk("mirrors"):
		n += 2
	return n

func aim_est(a: Unit, c: Dictionary, hh: Dictionary, tr: Dictionary) -> Array:
	## X1: what one shot of this card does to a target the laser touches, as [low, high, rounds].
	## Mirrors fire_bullet and damage() for the fixed modifiers; the dice, spread and skeet bonus stay out.
	var tg: Unit = hh.u
	var sc: bool = a.team == "squad" and a.adr >= 50
	var banks: int = tr.ping_d.filter(func(pd): return pd < hh.d).size()
	var add: int = int(a.g("aim_dmg")) + int(c.get("bankdmg", 0)) * banks
	if hh.get("thru", false) and ks(a, "xrayscope"):
		add += 4
	var head: bool = hh.head or (c.get("forcehead", false) and not tg.is_prop())
	var angled: bool = a.perk("angles") and banks > 0
	var out: Array = []
	for d0 in [c.dmg[0] + add, c.dmg[1] + add]:
		var d: int = d0
		if ks(a, "tungsten"):
			d = int(round(d * (1.0 + 0.25 * banks)))
		if a.perk("patience") and not a.moved:
			d = int(round(d * 1.3))
		if sc:
			d = int(round(d * 1.25))
		if tg.elite == "armored":
			d = maxi(1, int(round(d * 0.5)))
		if head:
			d = int(round(d * (2.0 if a.def.key == "moss" else 1.5)))
		if tg.team == "squad" and ks(tg, "riotshield") and signf(hh.dx) == -tg.face:
			d = maxi(1, int(round(d * 0.25)))
		elif tg.shield and hh.dx > 0 and not angled:
			d = maxi(1, int(round(d * (0.1 if foe_ai.wall_locked(tg) else 0.25))))
		if a.has_st("berserk"):
			d *= 2
		if tg.has_st("vest"):
			d = int(ceil(d / 2.0))
		if tg.team == "enemy" and tg.has_st("flared"):
			d += spec_kits.flare_bonus()
		if tg.team == "enemy" and tg.has_st("mark"):
			d = int(round(d * 1.5))
		if tg.team == "enemy":
			d += a.payback
		out.append(d)
	out.append(int(c.get("shots", 1)) * int(c.get("pellets", 1)))
	return out

func fire_bullet(a: Unit, x: float, y: float, ang: float, c: Dictionary, sc: bool) -> void:
	var pm := -1 if c.get("phase", false) else (3 if c.get("woodpass", false) else 0)
	var tr := trace_bullet(x, y, ang, c.range, c.get("bounce", 0) + bounce_bonus(a, sc), a, c.get("pierce", false), pm, c.get("softpass", 0), c.get("bodypass", 0))
	if pm != 0 or c.get("softpass", 0) > 0:
		for sg in tr.segs:
			# rounds that pass through terrain still chew a groove in it
			var L: float = Vector2(sg[2] - sg[0], sg[3] - sg[1]).length()
			for k in range(0, int(L), 18):
				var fx_: float = sg[0] + (sg[2] - sg[0]) * k / maxf(1, L)
				var fy_: float = sg[1] + (sg[3] - sg[1]) * k / maxf(1, L)
				if T.solid(fx_, fy_):
					T.carve(fx_, fy_, 4, a if a.team == "squad" else null, a)
	for s in tr.segs:
		tracer(s[0], s[1], s[2], s[3], (Color("ffcf70") if sc else Color("fff4c0")) if a.team == "squad" else Color("ffb0a0"))
	for p in tr.pings:
		sparks(p.x, p.y, 4)
	if tr.pings.size():
		Sfx.play("ricochet")
	var foes := 0
	for hh in tr.hits:
		var tg: Unit = hh.u
		if tg.is_body() and tg.soak > 0:
			tg.soak -= 1
			tg.vx += signf(hh.dx) * 1.2; tg.vy = -1.5; tg.air = true
			float_text(tg, "SHREDDED" if tg.soak <= 0 else "BODY BLOCKS", Color("c9b38a"))
			for i in 6:
				part({"x": hh.x, "y": hh.y, "vx": hh.dx * randf() * 2.0, "vy": -randf() * 2.5, "life": 22, "max": 22, "c": Color("e8d080"), "s": 2.0, "g": 0.15})
			continue
		if tg.dead:
			continue
		if tg.team == "enemy":
			foes += 1
		var d := ri(c.dmg[0], c.dmg[1]) + (int(a.g("aim_dmg")) if a.team == "squad" else 0)
		if hh.get("thru", false) and ks(a, "xrayscope"):
			d += 4
		var banks: int = tr.ping_d.filter(func(pd): return pd < hh.d).size()
		d += c.get("bankdmg", 0) * banks
		if ks(a, "tungsten"):
			d = int(round(d * (1.0 + 0.25 * banks)))
		if a.team == "squad" and a.perk("patience") and not a.moved:
			d = int(round(d * 1.3))
		if c.get("forcehead", false) and not tg.is_prop():
			hh.head = true
		if sc:
			d = int(round(d * 1.25))
		# SKEET: knocked into the air by a squadmate, shot before it lands
		if a.team == "squad" and tg.team == "enemy" and tg.air and not tg.para and tg.last_hit_by is Unit and tg.last_hit_by != a and tg.last_hit_by.team == "squad":
			d *= 2
			var launcher: Unit = tg.last_hit_by
			if tag("skeet", tg.x, tg.y - tg.h, true, a):
				a.energy += 1
				float_text(a, "+1 ENERGY", Color("ffd23a"))
				if launcher.def.key == "rook":
					launcher.energy += 1
					chain(launcher, "SPARE")
		if a.team == "enemy":
			d = int(round(d * (1 + alert * 0.06)))
		if tg.elite == "armored":
			d = maxi(1, int(round(d * 0.5)))
		if hh.head and a.team == "squad" and a.g("head_adr") > 0 and not tg.is_prop():
			gain_adr(a, int(a.g("head_adr")))
		if hh.head:
			d = int(round(d * (2.0 if a.team == "squad" and a.def.key == "moss" else 1.5)))
			float_text(tg, "HEADSHOT", Color("ffb23e"), true)
		var angled := a.team == "squad" and a.perk("angles") and banks > 0
		if tg.team == "squad" and ks(tg, "riotshield") and signf(hh.dx) == -tg.face and not tg.dead:
			d = maxi(1, int(round(d * 0.25)))
			float_text(tg, "SHIELD", Color("c9d1da"))
			sparks(hh.x, hh.y, 6)
		elif tg.shield and hh.dx > 0 and not tg.dead and not angled:
			var locked := foe_ai.wall_locked(tg)
			d = maxi(1, int(round(d * (0.1 if locked else 0.25))))
			float_text(tg, "SHIELD WALL" if locked else "SHIELD", Color("c9d1da"))
			sparks(hh.x, hh.y, 6)
		if foe_ai.chute_hit(tg, hh.y):
			continue
		if a.team == "squad":
			foe_ai.tank_hit(tg, hh.dx, a)
		if tg.team == "squad" and a.team == "enemy" and tg.fl.get("deflect", 0) > 0 and not a.dead:
			# Kage's blade sends it back where it came from
			tg.fl.deflect -= 1
			tracer(hh.x, hh.y, a.x, a.y - a.h / 2.0, Color("e0f4ff"))
			float_text(tg, "DEFLECTED", Color("e0f4ff"), true)
			Sfx.play("ricochet")
			damage(a, d * (2 if tg.perk("returnfire") else 1), tg)
			continue
		last_hit_head = hh.head
		damage(tg, d, a, {"crit": hh.head})
		last_hit_head = false
		if c.get("boomhit", false):
			booms.append({"t": 1, "x": hh.x, "y": hh.y, "r": 26.0, "dmg": 6, "owner": a})
		if not tg.dead and c.get("toxic", false):
			add_status(tg, "toxic", 3, a)
		if not tg.dead and (c.get("supp", false) or (a.team == "squad" and a.perk("pindown") and c.get("gun", "") == "mg")):
			add_status(tg, "supp", 1, a)
		if not tg.dead and c.get("mark", false):
			add_status(tg, "mark", 2, a)
		if not tg.dead and (c.get("burn", false) or a.has_st("flamegod")):
			add_status(tg, "burn", 2, a)
		if c.has("knock") and not tg.heavy and not tg.dead and not tg.is_prop() and not shrug(tg):
			tg.vx = signf(hh.dx if hh.dx != 0 else 1.0) * c.knock * kb(tg)
			tg.vy = -3
			tg.air = true
			tg.walk = null
			tg.bumped = null
			tg.last_hit_by = a
		if not tg.is_prop():
			for i in 5:
				part({"x": hh.x, "y": hh.y, "vx": hh.dx * randf() * 2.5, "vy": -randf() * 2.5, "life": 22, "max": 22, "c": Color("c0392b") if tg.team == "squad" else Color("e8d080"), "s": 2.0, "g": 0.15})
	if foes >= 2 and a.team == "squad" and state == "player" and tag("pinball", a.x, a.y - a.h, true, a):
		draw_cards(a, 1)
		if a.def.key == "moss":
			a.fl["free_aim"] = true
	if tr.end != null and c.get("boomhit", false) and tr.hits.is_empty():
		booms.append({"t": 1, "x": tr.end.x, "y": tr.end.y, "r": 26.0, "dmg": 6, "owner": a})
	if tr.end != null:
		var ch := maxf(c.get("chip", 3), 5.5 if tr.end.m == 3 else 0.0)
		T.carve(tr.end.x, tr.end.y, ch, a if a.team == "squad" else null, a)
		dust(tr.end.x, tr.end.y, MATCOL.get(tr.end.m, Color("c9b38a")))

# ---------------------------------------------------------------- damage, adrenaline, xp, death
func give_xp(u, n: int) -> void:
	if u == null or not (u is Unit) or u.team != "squad" or u.dead or n <= 0 or practice() or in_lesson() or u.s.has("guest"):
		return
	if mission.get("patrol", false):
		n = maxi(1, n / 2)
	u.xp_gain += n
	var gained := Run.add_xp(u.s, n)
	for i in gained:
		lvl_queue.append(u)
		float_text(u, "LEVEL UP!", Color("ffd23a"), true)
		u.pose = "cheer"; u.pose_t = 50
		Sfx.play("levelup")
	ui_dirty = true

func give_scrip(n: int, x: float, y: float, why := "") -> void:
	if n <= 0:
		return
	if debug:
		print("[scrip] %d %s" % [n, why])
	Run.scrip += n
	stats.scrip += n
	float_at(x, y, "+%d$" % n, Color("ffd23a"))
	ui_dirty = true

var last_hit_o := {}  # the options of the damage call in progress, for kill() to read

func damage(tg: Unit, amt: int, src, o := {}) -> void:
	if tg.dead or tg.gone or amt <= 0:
		return
	last_hit_o = o
	if tg.kind == "pow":
		return
	var own = src if src != null and src is Unit and src.team == "squad" else null
	if tg.kind == "crate":
		open_crate(tg, false)
		return
	if tg.kind == "cart":
		biome_rules.push_cart(tg, src)
		return
	if tg.kind == "strongbox":
		if o.get("blast", false):
			open_crate(tg, true)
		elif o.get("melee", false):
			float_text(tg, "PRIED OPEN", Color("62d26f"))
			open_crate(tg, false)
		else:
			float_text(tg, "CLANK", Color("c9d1da"))
			sparks(tg.x, tg.y - 8, 4)
		return
	if tg.kind == "loot" or tg.kind == "cache" or tg.kind == "relay" or tg.kind == "slug" or tg.kind == "pad" or tg.kind == "ride" or tg.kind == "hulk" or tg.kind == "sticky":
		return
	if src is Unit and src != tg and src.has_st("berserk") and not o.get("status", false):
		amt *= 2
	if tg.has_st("flamegod"):
		float_text(tg, "FLAMEGOD", Color("ff9a3d"))
		return
	if tg.has_st("vest"):
		amt = int(ceil(amt / 2.0))
	if tg.team == "enemy" and tg.has_st("flared") and not o.get("status", false):
		amt += spec_kits.flare_bonus()
	if tg.type == "dicokka":
		amt = foe_ai.dicokka_dmg(tg, amt, src, o)
	if tg.team == "squad" and tg.mech != null:
		vehicle_ops.mech_hit(tg, amt)  # N3/R1: the vehicle takes it
		return
	if own != null and tg.team == "enemy" and not o.get("status", false) and own.payback > 0:
		amt += own.payback
		float_text(tg, "PAYBACK +%d" % own.payback, Color("9fb4c9"), true)
		own.payback = 0
	if own != null and tg.team == "enemy" and not o.get("status", false):
		var intel: bool = tg.elite != "" and Run.campaign() and Run.hq("comms") >= 2 and not tg.fl.has("intel")
		if tg.has_st("mark") or intel:
			tg.st.erase("mark")
			tg.fl["intel"] = true  # B4 Comms 2: the first hit on an elite lands as marked
			amt = int(round(amt * 1.5))
			o = o.duplicate()
			o["crit"] = true
			float_text(tg, "MARKED", Color("ff4d3d"), true)
		# CROSSFIRE: two soldiers hit it from opposite sides this round
		var side := int(signf(tg.x - own.x))
		if side != 0:
			for k in tg.hit_sides:
				if k != own.id and tg.hit_sides[k] == -side and not tg.has_st("supp"):
					add_status(tg, "supp", 1, own)
					tag("crossfire", tg.x, tg.y - tg.h, false)
					break
			tg.hit_sides[own.id] = side
	if tg.kind == "barrel":
		if not tg.primed:
			tg.primed = true
			var mul := (2.0 if own != null and own.perk("chain") else 1.0) * (1.5 if ks(own, "detbox") else 1.0)
			booms.append({"t": 1 if ks(own, "detbox") else 14, "x": tg.x, "y": tg.y - 9, "r": 44.0, "dmg": int(13 * mul), "owner": own, "barrel": tg})
		return
	if tg.kind == "fuel":
		if tg.primed:
			return
		if o.get("blast", false) or ks(own, "detbox"):
			tg.primed = true
			var mul := (2.0 if own != null and own.perk("chain") else 1.0) * (1.5 if ks(own, "detbox") else 1.0)
			booms.append({"t": 1 if ks(own, "detbox") else 10, "x": tg.x, "y": tg.y - 15, "r": 84.0, "dmg": int(20 * mul), "owner": own, "barrel": tg})
		elif tg.leak == null:
			tg.leak = 2
			tg.leak_by = own
			float_text(tg, "LEAKING! 2 TURNS", Color("ffd23a"), true)
			Sfx.play("splash")
			log_msg("A fuel tank is leaking. It blows at the end of the next enemy phase.")
		return
	if tg.kind == "rivet":
		spec_kits.drop_girder(tg, own)
		return
	if tg.kind == "dog":
		spec_kits.rex_hurt(tg, amt)
		return
	if tg.kind == "sentry":
		tg.hp -= amt
		tg.flash = 8
		sparks(tg.x, tg.y - 10, 3)
		if tg.hp <= 0:
			tg.dead = true
			tg.gone = true
			booms.append({"t": 2, "x": tg.x, "y": tg.y - 8, "r": 22.0, "dmg": 3, "owner": null})
			float_text(tg, "SENTRY DOWN", Color("ff7a3d"), true)
		return
	if tg.kind == "jbox":
		if tg.loot.on:
			tg.loot.on = false
			tg.flash = 8
			sparks(tg.x, tg.y - 10, 8)
			Sfx.play("tick")
			float_text(tg, "POWER CUT", Color("53d4e2"), true)
		return
	if tg.kind == "m2":
		tg.hp -= amt
		tg.flash = 8
		sparks(tg.x, tg.y - 12, 3)
		if tg.hp <= 0:
			tg.dead = true
			tg.gone = true
			booms.append({"t": 4, "x": tg.x, "y": tg.y - 10, "r": 30.0, "dmg": 6, "owner": own})
			float_text(tg, "GUN DOWN", Color("ff7a3d"), true)
			refresh_mounts()
		return
	if tg.kind == "mine":
		if not tg.primed:
			biome_rules.prime_mine(tg, own, 4)
		return
	if tg.kind == "dump":
		# O3: a supply dump, twice as soft to blasts
		tg.hp -= amt * (2 if o.get("blast", false) else 1)
		tg.flash = 8
		sparks(tg.x, tg.y - 14, 4)
		if tg.hp <= 0:
			tg.dead = true
			tg.gone = true
			booms.append({"t": 4, "x": tg.x, "y": tg.y - 12, "r": 40.0, "dmg": 6, "owner": own, "barrel": tg})
			var left := units.filter(func(d): return d.kind == "dump" and not d.dead).size()
			float_text(tg, "DUMP DESTROYED" + (" %d LEFT" % left if left else ""), Color("62d26f"), true)
			Sfx.play("coin")
			if own != null:
				give_xp(own, 6)
		return
	if tg.kind == "truck":
		# O5: the squad's fire never touches the truck; Jackal fire does
		if own != null:
			return
		tg.hp -= amt
		tg.flash = 8
		sparks(tg.x, tg.y - 16, 3)
		float_text(tg, "-%d" % amt, Color("ff4d3d"))
		if tg.hp <= 0:
			tg.dead = true
			booms.append({"t": 4, "x": tg.x, "y": tg.y - 14, "r": 50.0, "dmg": 6, "owner": null, "barrel": tg})
		return
	if tg.kind == "charge":
		if tg.primed:
			return
		if o.get("blast", false):
			tg.primed = true
			booms.append({"t": 6, "x": tg.x, "y": tg.y - 4, "r": 48.0, "dmg": 16, "owner": null, "barrel": tg})
		else:
			tg.dead = true
			tg.gone = true
			float_text(tg, "DEFUSED", Color("62d26f"), true)
			Sfx.play("coin")
			if own != null:
				give_xp(own, 4)
		return
	if tg.team == "squad" and tg.g("reflect") > 0 and src is Unit and src.team == "enemy" and not src.dead and not o.get("blast", false) and not o.get("melee", false) and not o.get("status", false) and not tg.fl.has("reflected"):
		# B5 Prism Plate: the first enemy shot each turn goes back where it came from
		tg.fl["reflected"] = true
		float_text(tg, "REFLECT", Color("c47bff"), true)
		sparks(tg.x, tg.y - tg.h / 2.0, 5)
		damage(src, amt, tg, {"status": true})
		return
	if tg.dome > 0 and not o.get("melee", false) and not o.get("impact", false) and not o.get("status", false):
		float_text(tg, "DOME", Color("9df25c"))
		if vfx != null and vfx.attached.has("%d:dome" % tg.id):
			vfx.dome_hit(tg, src)
		else:
			sparks(tg.x, tg.y - tg.h / 2.0, 3)
		return
	if tg.type == "hiveship":
		if vharr_ai.ship_plated(tg):
			if o.get("blast", false):
				float_text(tg, "BELLY HIT!", Color("ffd23a"))
			else:
				amt = maxi(1, int(round(amt * 0.4)))
				float_text(tg, "ARMOR", Color("9fb4c9"))
		else:
			amt = int(round(amt * 1.3))
	if tg.type == "boss":
		if tg.plate > 0:
			var raw := amt
			amt = maxi(1, int(round(amt * 0.4)))
			tg.plate -= raw
			if tg.plate <= 0:
				crack_boss(tg)
			else:
				float_text(tg, "ARMOR", Color("9fb4c9"))
		else:
			amt = int(round(amt * 1.3))
	if tg.weight == "buried" and o.get("blast", false):
		amt = maxi(1, amt / 2)  # the ground above takes half of it
	if tg.pod > 0 and tg.weight == "hover":
		var pb := mini(tg.pod, amt)
		tg.pod -= pb
		amt -= pb
		sparks(tg.x, tg.y + 2, 4)
		if tg.pod <= 0:
			vharr_ai.break_pod(tg)
		else:
			float_text(tg, "POD -%d" % pb, Color("c47bff"))
		if amt <= 0:
			tg.flash = 10
			ui_dirty = true
			return
	if tg.armor > 0:
		var ab := mini(tg.armor, amt)
		tg.armor -= ab
		amt -= ab
		float_text(tg, "-%d ARMOR" % ab, Color("9fb4c9"))
		if amt <= 0:
			ui_dirty = true
			return
	tg.flash = 10
	if tg.jetting and tg.team == "enemy" and amt > 0:
		# J5: a hit in flight knocks the jet pack out
		tg.jetting = false
		tg.crash = true
		float_text(tg, "PACK HIT!", Color("ff7a3d"), true)
	if tg.team == "squad":
		if debug:
			print("[dmg r%d] %s -%d (hp %d) by %s %s how %s" % [round_n, tg.def.key, amt, tg.hp, (src.team + ":" + (src.type if src.team != "squad" else src.def.key)) if src is Unit else str(src), str(o), kill_how if kill_how != "" else "-"])
		if tg.hp - amt <= 0:
			if tg.second_wind:
				tg.second_wind = false
				amt = tg.hp - 1
				float_text(tg, "SECOND WIND!", Color("ffd23a"), true)
			elif Run.has_gear("charm") and charm_used < (2 if Run.relic_tier("charm") >= 3 else 1):
				charm_used += 1
				amt = tg.hp - 1
				float_text(tg, "LUCKY CHARM!", Color("62d26f"), true)
			elif not lazarus_used and squad_alive().any(func(h): return h != tg and h.perk("lazarus")):
				lazarus_used = true
				amt = 0
				tg.hp = int(ceil(tg.max_hp * 0.3))
				float_text(tg, "LAZARUS!", Color("62d26f"), true)
				log_msg("Hex drags %s back up." % tg.def.name)
		tg.hp -= amt
		if amt > 0:
			var hk := "hurt_" + hurt_kind(src)
			stats[hk] = int(stats.get(hk, 0)) + amt  # X2
		if vfx != null and amt > 0 and not o.get("status", false):
			vfx.bleed(tg, src, amt)
		tg.pose = "hurt"; tg.pose_t = 16
		Sfx.play("hurt")
		float_text(tg, "-%d" % amt, Color("ff4d3d"), o.get("crit", false))
		if tg.hp <= 0:
			kill(tg, src)
		elif own == null:
			gain_adr(tg, amt * 5)
	else:
		tg.hp -= amt
		if vfx != null and amt > 0 and not o.get("status", false):
			vfx.bleed(tg, src, amt)
		tg.pose = "hurt"; tg.pose_t = 12
		float_text(tg, str(amt), Color("ffb23e") if o.get("crit", false) else Color.WHITE, o.get("crit", false))
		if own != null and tg.team == "enemy":
			give_xp(own, maxi(1, int(amt / 3)))
		if tg.hp <= 0:
			# R2: overkill by half its health or more and the Jackal bursts into helmet, boots and smoke
			pop_next = tg.kind == "enemy" and not is_boss(tg) and not tg.type in ["shipplate", "droppod", "vgate"] and -tg.hp >= maxi(6, tg.max_hp / 2)
			kill(tg, src)
			pop_next = false
	ui_dirty = true

func crack_boss(bo: Unit) -> void:
	if bo.plate <= 0 and bo.cracked:
		return
	bo.plate = 0
	bo.cracked = true
	banner("ARMOR CRACKED!", Color("ffb23e"), "THE IRON BOAR TAKES +30% DAMAGE")
	shake += 8
	Sfx.play("bigboom")
	float_text(bo, "ARMOR CRACKED", Color("ffb23e"), true)
	for i in 14:
		part({"x": bo.x + (randf() - .5) * 80, "y": bo.y - 30, "vx": (randf() - .5) * 6, "vy": -randf() * 6, "life": 60, "max": 60, "c": Color("6b5a3a"), "s": 5.0, "g": 0.25})
	log_msg("The boar is cracked open. Pour it on.")

func gain_adr(u: Unit, n: int) -> void:
	if u == null or u.dead or u.team != "squad":
		return
	if Run.has_gear("stimpack"):
		n = int(n * (1.3 + 0.1 * Run.relic_tier("stimpack")))
	var b0 := u.adr
	u.adr = clampi(u.adr + n, 0, 100)
	if b0 < 50 and u.adr >= 50:
		float_text(u, "PUMPED", Color("ff7a3d"), true)
		log_msg("%s is pumped: attacks are supercharged." % u.def.name)
	if b0 < 100 and u.adr >= 100:
		grant_overdrive(u)
	ui_dirty = true

func grant_overdrive(u: Unit) -> void:
	if u.dead or u.hand.any(func(c): return c.get("od", false) and not c.has("duo") and not c.get("temp", false)):
		return
	var key: String = Run.od_key(u.s)
	u.hand.append({"id": -1, "key": key, "tier": Data.OD_TIER, "od": true})
	banner("%s: OVERDRIVE" % u.def.name, Color("ffb23e"), Data.CARDS[key].name.to_upper())
	bark(u, pick(Data.BARKS.od))
	Sfx.play("power")
	log_msg("%s unlocked %s. It's in their hand." % [u.def.name, Data.CARDS[key].name])
	ui_dirty = true

const ROOKIE_HP := 0.67   # D1: 120 HP / 36 plate becomes 80 / 24

func rookie_boar() -> bool:
	# the test harness keeps the full Boar so its numbers stay comparable
	return not Run.campaign() and Run.mission == 0 and not practice() and not Run.meta.get("boar_down", false) and not OS.get_cmdline_user_args().has("--iatest")

func who_did(tg: Unit, src) -> String:
	## N3: a plain name for whatever downed a soldier, for the mission-failed screen.
	## X2: own fire names the card, terrain names how (drowned, fall, bonk, burn).
	if tg.sunk:
		return "DROWNED"
	if src is Unit and src.team == "enemy":
		if src.type == "boss":
			return "THE VHARR BOAR" if src.fl.get("vharr", false) else "THE IRON BOAR"
		return "A " + str(Data.ETYPES[src.type].name).to_upper()
	var card := (" (%s)" % act_card.to_upper()) if act_card != "" and act_unit == src else ""
	if src is Unit and src == tg:
		return "THEIR OWN BLAST" + card
	if src is Unit and src.team == "squad":
		return "FRIENDLY FIRE: %s%s" % [src.def.name.to_upper(), card]
	var how := kill_how if kill_how != "" else str(last_hit_o.get("how", ""))
	match how:
		"BONK": return "A BONK INTO SOMETHING HARD"
		"FALL": return "A FALL"
		"BURN": return "FIRE"
		"TOXIC": return "POISON"
		"CRUSHED", "CRUSH", "SLAM": return "FALLING DEBRIS"
	if tg.y >= biome_rules.lava_y():
		return "LAVA"
	return "A FALL OR DEBRIS"

func hurt_kind(src) -> String:
	## X2: who hurt the squad, for the debrief's damage split
	if src is Unit and src.team == "enemy":
		return "enemy"
	if src is Unit and src.team == "squad":
		return "own"
	return "terrain"

const KILL_MOVE := 40  # D1: movement a soldier gets back for each kill on their turn

func kill(tg: Unit, src) -> void:
	if tg.dead:
		return
	if tg.team == "squad" and tg.has_st("zombie") and not tg.sunk and tg.y < biome_rules.lava_y():
		tg.hp = 1  # R6 ZOMBIE: can't go down
		float_text(tg, "UNDEAD!", Color("9df25c"), true)
		return
	if debug and tg.team == "squad":
		print("[down r%d] %s at %d,%d hp %d sunk %s lava %d by %s last %s" % [round_n, tg.def.key, int(tg.x), int(tg.y), tg.hp, tg.sunk, lava_k, (src.team + ":" + (src.type if src.team != "squad" else src.def.key)) if src is Unit else str(src), (tg.last_hit_by.team + ":" + (tg.last_hit_by.type if tg.last_hit_by.team != "squad" else tg.last_hit_by.def.key)) if tg.last_hit_by is Unit else "-"])
	tg.dead = true
	tg.hp = 0
	tg.dead_t = 0
	tg.walk = null
	tg.overwatch = 0
	if tg.carry != "":
		drop_loot(tg.x, tg.y - 14, {"type": tg.carry}, 0.4)
		if tg.carry == "colors":
			float_text(tg, "COLORS DROPPED", Color("ff7a3d"), true)
		tg.carry = ""
	if tg.bow:
		tg.bow = false
		drop_loot(tg.x, tg.y - 14, {"type": "bow"}, 0.4)
	feed_kill(tg, src)
	if tg.fl.has("nemesis"):
		# W3: a nemesis put down for good drops a Legendary with their name on it
		var it := Run.roll_item(Data.TIER_MAX)
		it["named"] = str(tg.fl.nemesis).capitalize()
		drop_loot(tg.x, tg.y - 20, {"type": "item", "item": it})
		stats["nemesis_killed"] = tg.fl.nemesis
		banner("NEMESIS DOWN!", Color("ffd23a"), "%s IS DEAD" % tg.fl.quarry)
	if tg.type == "shipplate":
		vharr_ai.drop_plate(tg, src)
	elif tg.type == "jwalker":
		vehicle_ops.walker_wreck(tg)
	elif tg.type == "gunship":
		foe_ai.gunship_down(tg)
	elif tg.type == "droppod" or tg.type == "vgate":
		tg.gone = true
		for i in 8:
			debris(tg.x + randf_range(-10, 10), tg.y - randf_range(4, 22), 2)
	elif pop_next and tg.kind == "enemy":
		overkill_pop(tg)
	elif tg.kind == "enemy" and not is_boss(tg):
		# the body stays where it drops: it stops one bullet, and blasts throw it like a sandbag
		tg.soak = 1
		tg.w = 26
		tg.h = 12
		var bodies := units.filter(func(o): return o.is_body())
		if bodies.size() > BODY_MAX:
			bodies[0].soak = 0
	if tg.team == "enemy":
		stats.kills += 1
		if not stats.has("first_kill"):
			stats["first_kill"] = tg.type  # R5: COUNTER-SNIPE
		if last_hit_o.get("melee", false) and src is Unit and src.team == "squad":
			stats.melee_kills += 1  # R5: UP CLOSE
		if Run.toggle_on("nades") and not is_boss(tg):
			drop_loot(tg.x, tg.y - 14, {"type": "gun", "card": "frag"}, 0.6)  # D3: GRENADE RAIN
		var kinds: Dictionary = stats.get("kinds", {})
		kinds[tg.type] = int(kinds.get(tg.type, 0)) + 1  # B5: the Alien Lab counts what you kill
		stats["kinds"] = kinds
		credit_card(src)
		if src is Unit and src.team == "squad":
			src.kills += 1  # C5: the service record
			if state == "player" and not src.dead:
				# D1 kill momentum: a kill opens up the next step
				src.move_left += KILL_MOVE
				float_text(src, "+%s MOVE" % Data.meters(KILL_MOVE), Color("b48cff"))
				if not act_once.has("moveup"):
					act_once["moveup"] = true
					bark(src, "MOVE UP!")
			var wrenched: bool = act_unit == src and act_inst is Dictionary and act_inst.get("key", "") == "wrench"
			if src.def.key == "bolt" and not src.fl.has("scrapped") and (wrenched or src.perk("salvager")):
				# SCRAPHEAP chain / Salvager: the wreck becomes a free Sandbags
				src.fl["scrapped"] = true
				if wrenched:
					chain(src, "SCRAPHEAP")
				src.hand.append({"id": -7, "key": "sandbags", "tier": Data.base_tier("sandbags"), "temp": true, "free": true})
			if src.s.get("spec", "") == "defector" and faction(tg) == "jackal" and absf(tg.x - src.x) < 70 and not src.fl.has("turncoat"):
				# C7 Turncoat: an up-close kill hands the Defector the Jackal's gun for one shot
				src.fl["turncoat"] = true
				var gk: String = Data.DROP_GUNS.get(tg.type, "rifle")
				src.hand.append({"id": -2, "key": gk, "tier": Data.base_tier(gk), "temp": true})
				float_text(src, "TURNCOAT: " + Data.CARDS[gk].name.to_upper(), Color("ffd23a"), true)
		var base: int = Data.ETYPES[tg.type].score
		if state == "player":
			combo += 1
			stats.best_combo = maxi(stats.best_combo, combo)
			var c3 := 2 if Run.has_cmd("killstreak") else 3
			var c5 := 4 if Run.has_cmd("killstreak") else 5
			if combo == c3:
				for s in squad_alive():
					gain_adr(s, 10)
				float_at(tg.x, tg.y - tg.h - 64, "COMBO x%d: +10 ADRENALINE" % c3, Color("ff7a3d"), true)
			elif combo == c5:
				crate_bump = 1
				float_at(tg.x, tg.y - tg.h - 64, "COMBO x%d: NEXT CRATE +1 RARITY" % c5, Color("b48cff"), true)
				Sfx.play("levelup")
		var mult := maxi(1, combo)
		score += base * mult
		float_text(tg, ("x%d " % mult if mult > 1 else "") + "+%d" % (base * mult), Color("ffb23e"), true)
		float_at(tg.x, tg.y - tg.h - 34, pick(Data.SCREAMS), Color("ffe9c0"))
		Sfx.play("alien_die" if faction(tg) == "vharr" else "scream", -6)
		if src is Unit and src.team == "enemy" and src != tg and at_war(src, tg):
			# F2 TURNCOAT: one faction killed the other. Whoever set it up gets the kill's XP, or the squad shares it.
			var setter = null
			for h in [tg.last_hit_by, src.last_hit_by]:
				if setter == null and h is Unit and h.team == "squad" and not h.dead:
					setter = h
			if setter != null:
				give_xp(setter, 4 + base / 50)
				gain_adr(setter, 8)
				float_text(setter, "TURNCOAT KILL", Color("ffd23a"))
			else:
				for h in squad_alive():
					give_xp(h, 2)
			stats["turncoat"] = int(stats.get("turncoat", 0)) + 1
		var marked: bool = src is Unit and src.team == "squad" and src.carry == "yellow"
		give_scrip(int(maxi(2, base / 25) * (1.5 if Run.has_cmd("warchest") else 1.0)) * (2 if marked else 1), tg.x, tg.y - tg.h - 50, "L4304")
		if tg.has_st("toxic") and squad_alive().any(func(h): return h.perk("pandemic")):
			for o2 in units:
				if o2.team == "enemy" and not o2.dead and o2 != tg and absf(o2.x - tg.x) < 90 and absf(o2.y - tg.y) < 60:
					add_status(o2, "toxic", 3, tg.st_by.get("toxic", null))
		if burn_tick:
			announce_unlock(Run.feat("pyro"))
		if src != null and src is Unit and src.team == "squad":
			if state == "player" and last_hit_head and src.perk("deadeye") and src.last_cost > 0 and not act_once.has("deadeye"):
				act_once["deadeye"] = true
				src.energy += src.last_cost
				float_text(src, "DEAD EYE: REFUND", Color("ffd23a"))
			if state == "player" and (src.air or src.zip != null) and src.last_cost > 0 and tag("skydiver", src.x, src.y - src.h):
				src.energy += src.last_cost
				float_text(src, "CARD REFUNDED", Color("ffd23a"))
			if src.hang and tag("topgun", src.x, src.y - src.h, true, src):
				gain_adr(src, 15)
			gain_adr(src, 8 + int(src.g("kill_adr")))
			give_xp(src, 4 + base / 50)
			# B3: everyone else still standing gets a third of the kill's XP, so the levels don't all pile onto one soldier
			for h in squad_alive():
				if h != src:
					give_xp(h, maxi(1, (4 + base / 50) / 3))
			if src.g("kill_draw") > 0 and not src.kill_drawn and state == "player":
				src.kill_drawn = true
				draw_cards(src, int(src.g("kill_draw")))
				float_text(src, "SPARE MAG: DRAW", Color("53d4e2"))
		if tg.type == "bloater" and tg.fl.get("swell", 0) >= 0:
			var sw: int = tg.fl.get("swell", 0)
			booms.append({"t": 6, "x": tg.x, "y": tg.y - tg.h / 2.0, "r": Data.ETYPES.bloater.radius + 10.0 * sw, "dmg": Data.ETYPES.bloater.dmg, "owner": src if src is Unit and src.team == "squad" else null})
			float_text(tg, "POP!", Color("9df25c"), true)
		if Data.DROP_GUNS.has(tg.type) and not tg.gone:
			# B4: the gun falls where it dies; whoever walks over it gets one shot of it
			drop_loot(tg.x, tg.y - 12, {"type": "gun", "card": Data.DROP_GUNS[tg.type]}, 0.6)
		if tg.type == "queen":
			drop_loot(tg.x, tg.y - 40, {"type": "item", "item": Run.roll_item(2)}, 1.2)
			banner("QUEEN SLAIN!", Color("9df25c"), "THE SAND GOES QUIET")
		if tg.type == "warden":
			for w in wells.filter(func(q): return q.by == tg):
				booms.append({"t": 4, "x": w.x, "y": w.y, "r": 40.0, "dmg": 6, "owner": src if src is Unit and src.team == "squad" else null})
				float_at(w.x, w.y - 20, "WELL COLLAPSES!", Color("c47bff"), true)
			wells = wells.filter(func(q): return q.by != tg)
		if tg.fl.get("lead", false):
			banner("THE HUNT IS OVER", Color("62d26f"), "EPIC GEAR + %d BIO-PARTS" % Data.ELITE_BIO)
			drop_loot(tg.x, tg.y - 30, {"type": "item", "item": Run.roll_item(3)})
			Run.meta.bio = int(Run.meta.get("bio", 0)) + Data.ELITE_BIO
			stats["bio"] = int(stats.get("bio", 0)) + Data.ELITE_BIO
		if tg.type == "vgate":
			banner("GATE DESTROYED!", Color("62d26f"))
			for i in 4:
				booms.append({"t": 4 + i * 10, "x": tg.x + (randf() - .5) * 40, "y": tg.y - randf() * 60, "r": 26.0, "dmg": 0, "owner": null})
		if tg.fl.get("outbreak", false):
			var camp := units.filter(func(o): return o.fl.get("camp", false) and not o.dead and not o.gone)
			if camp.size():
				banner("THE CAMP TURNS!", Color("ffd23a"), "THE JACKALS LEFT FIGHT THE VHARR")
			for o in camp:
				o.fl["turned"] = true
				o.fl.erase("thrall")
				o.fl.erase("link")
				float_text(o, "TURNS ON THE VHARR!", Color("ffd23a"), true)
		if tg.type == "overseer":
			for o in units:
				if o.fl.get("link", -1) == tg.id and not o.dead:
					o.fl.erase("link"); o.fl.erase("thrall")
					add_status(o, "stun", 1)
					float_text(o, "FREED", Color("ffd23a"), true)
		if is_thrall(tg):
			vharr_ai.spawn_skitter(tg.x, tg.y)
			float_text(tg, "IT BURSTS OUT!", Color("9df25c"), true)
		if tg.type == "hive":
			acids.append({"x": tg.x, "y": tg.y, "r": 40.0, "turns": 2})
			float_text(tg, "ACID!", Color("9df25c"), true)
			Sfx.play("splash")
		if tg.elite == "brood":
			for k in [-1, 1]:
				var bx: float = tg.x + k * 14
				var by = T.stand_y(bx, tg.y - 30)
				var c := mk_enemy(tg.type, bx, by if by != null else tg.y)
				c.hp = maxi(1, tg.max_hp / 3); c.max_hp = c.hp
				c.active = true
				units.append(c)
				place_alien(c)
			float_text(tg, "BROOD SPLITS!", Color("9df25c"), true)
		if tg.elite != "":
			drop_loot(tg.x, tg.y - tg.h / 2.0, {"type": "item", "item": Run.roll_item(1)})
			if tg.elite == "volatile":
				booms.append({"t": 16, "x": tg.x, "y": tg.y - tg.h / 2.0, "r": 46.0, "dmg": 12, "owner": null})
				float_text(tg, "VOLATILE!", Color("ff7a3d"), true)
			if src is Unit and src.team == "squad" and randf() < 0.3:
				bark(src, pick(Data.BARKS.kill))
		if tg.type == "hiveship":
			for o in units:
				if o.type == "shipplate" and o.fl.get("ship") == tg and not o.dead:
					kill(o, src)  # its plates come down with it
			tg.gone = true
			banner("HIVE SHIP DOWN!", Color("9df25c"), "THE SKY IS CLEAR")
		if is_boss(tg):
			boss_dead = true
			if tg.type == "boss":
				Run.meta["boar_down"] = true  # D1: no more Rookie Boars once one is beaten
			drop_loot(tg.x, tg.y - 40, {"type": "item", "item": Run.roll_item(Data.TIER_MAX)}, 1.4)
			var relics: Array = Data.GEAR.filter(func(g): return g.get("boss", false) and not Run.has_gear(g.id))
			if not relics.is_empty():
				drop_loot(tg.x - 20, tg.y - 40, {"type": "relic", "id": relics[randi() % relics.size()].id}, 1.2)
			var part_name: String = Data.TROPHIES[mini(mission_idx, Data.TROPHIES.size() - 1)]
			if not Run.trophies.has(part_name):
				drop_loot(tg.x + 20, tg.y - 40, {"type": "trophy", "name": part_name}, 1.2)
			for i in 7:
				booms.append({"t": 10 + i * 14, "x": tg.x + (randf() - .5) * 90, "y": tg.y - 20 - randf() * 40, "r": 34.0, "dmg": 0, "owner": null})
	elif tg.team == "squad":
		stats.kia += 1
		stats.downs += 1
		var cause := who_did(tg, src)
		stats["last_down"] = "%s, BY %s" % [tg.def.name.to_upper(), cause]
		stats["down_log"] = stats.get("down_log", []) + ["%s: %s, round %d" % [tg.def.name.to_upper(), cause, round_n]]  # H3: the playtest diary
		banner("%s DOWN" % tg.def.name.to_upper(), Color("ffb23e"), cause)  # X2: say what did it
		if state == "player" or state == "enemy":
			regroup = true  # X7: the line waits one round before the stall clock counts again
		if tg.s.tags > 0 or mission.get("patrol", false):
			# a dog tag buys their life: out until the next camp, or back next mission.
			# A campaign patrol (M5) never costs a life: an empty-tagged soldier is only knocked out.
			tg.s.tags = maxi(0, tg.s.tags - 1)
			tg.downed = true
			float_text(tg, "DOWN! %d TAG%s LEFT" % [tg.s.tags, "" if tg.s.tags == 1 else "S"], Color("ffb23e"), true)
			var back := "until the next camp" if T.camps.any(func(c): return not c.used) else "for the rest of this fight"
			log_msg("%s is down %s (%s). %d dog tag%s left." % [tg.def.name, back, cause.to_lower(), tg.s.tags, "" if tg.s.tags == 1 else "s"])
		else:
			stats.fallen.append(tg.def.name)
			float_text(tg, "KIA", Color("ff4d3d"), true)
			log_msg("%s is killed in action (%s). No dog tags left." % [tg.def.name, cause.to_lower()])
		Sfx.play("bad")
		Sfx.play("death", -2)
		for s in squad_alive():
			gain_adr(s, 25)
		if sel == tg:
			var al := squad_alive()
			sel = al[0] if al.size() else null
			card_idx = -1
	ui_dirty = true

func upgrade_choices(s: Dictionary) -> Array:
	## One of each upgradable card (same card, rarity and mods count once), cheapest first.
	var seen := {}
	var out: Array = []
	for c in s.deck:
		if not Run.upgradable(c) or Services.is_od(c):
			continue
		var k := "%s:%d:%s" % [c.key, Data.tier_of(c), ",".join(c.get("mods", []))]
		if seen.has(k):
			continue
		seen[k] = true
		out.append(c)
	out.sort_custom(func(a, b): return int(Data.card(a).cost) < int(Data.card(b).cost) or (int(Data.card(a).cost) == int(Data.card(b).cost) and Data.card(a).name < Data.card(b).name))
	return out

func credit_card(src) -> void:
	## D4: the card that made the kill keeps count for the run. Ten kills earn it a nickname.
	if not (src is Unit) or src != act_unit or act_inst == null or state != "player" or act_inst.get("temp", false) or act_inst.get("od", false):
		return
	var c: Dictionary = act_inst
	c["kills"] = int(c.get("kills", 0)) + 1
	if c.kills == Data.NICK_KILLS and not c.has("nick"):
		c["nick"] = Data.CARD_NICKS[randi() % Data.CARD_NICKS.size()]
		float_text(src, "%s IS NOW \"%s\"" % [Data.card(c).name.to_upper(), c.nick.to_upper()], Color("ffd23a"), true)
		log_msg("%s's %s has %d kills. The squad calls it \"%s\" now." % [src.def.name, Data.card(c).name, c.kills, c.nick])

func feed_kill(tg: Unit, src) -> void:
	## U1: one kill feed line, Metal Slug style: KILLER [HOW] VICTIM, with a stamp for the flashy ones.
	if tg.kind != "enemy" and tg.kind != "soldier":
		return
	var killer := "BOOM"
	var kc := Color("e8dcc2")
	if src is Unit:
		if src == tg:
			killer = "HIMSELF" if tg.team == "enemy" else "FRIENDLY FIRE"
		elif src.team == "squad":
			killer = src.def.name.to_upper()
			kc = Color("ffd23a")
		elif src.kind == "enemy":
			killer = Data.ETYPES[src.type].name.to_upper()
			kc = Color("ff4d3d")
	var how := kill_how
	if how == "":
		if src is Unit and src.team == "squad" and act_card != "" and state == "player":
			how = act_card.to_upper()
		elif src is Unit and src.kind == "enemy":
			how = "ATTACK"
		else:
			how = "BLAST"
	if Run.campaign() and src is Unit and src.team == "squad" and tg.team == "enemy" and src.s.has("order"):
		# W5: personal orders count the kills that match them
		var fin := ""
		match str(src.s.order.id):
			"headhunter": fin = Run.order_tick(src.s, "headhunter") if last_hit_head else ""
			"demo": fin = Run.order_tick(src.s, "demo") if act_type == "ARC" or how == "BLAST" else ""
			"brawler": fin = Run.order_tick(src.s, "brawler") if act_type == "MELEE" else ""
			"bughunter": fin = Run.order_tick(src.s, "bughunter") if faction(tg) == "vharr" else ""
			"wrecker": fin = Run.order_tick(src.s, "wrecker") if how in ["FALL", "SLAM", "BONK", "CRUSHED"] else ""
			"giantkiller": fin = Run.order_tick(src.s, "giantkiller") if tg.elite != "" or is_boss(tg) else ""
		if fin != "":
			log_msg(fin)
			float_text(src, Data.ORDERS[src.s.orders_done.back()].title + "!", Color("ffd23a"), true)
	var victim: String = (Data.ETYPES[tg.type].name if tg.team == "enemy" else tg.def.name).to_upper()
	var stamp := ""
	if pop_next:
		stamp = "OVERKILL!"
	elif last_hit_head and src is Unit and src.team == "squad":
		stamp = "HEADSHOT!"
	elif tg.air and how in ["FALL", "SLAM"]:
		stamp = "SPLAT!"
	if src is Unit and src.team == "enemy" and src != tg and at_war(src, tg):
		stamp = "TURNCOAT!"
	if state == "player" and combo >= 1 and tg.team == "enemy":
		stamp = (stamp + " " if stamp != "" else "") + ["", "", "DOUBLE!", "TRIPLE!", "MULTI KILL!"][mini(combo + 1, 4)]
	feed.append({"killer": killer, "kc": kc, "how": how, "victim": victim, "vc": Color("ff7a3d") if tg.team == "enemy" else Color("53d4e2"), "stamp": stamp.strip_edges(), "t": 0})
	if feed.size() > 4:
		feed.pop_front()

func overkill_pop(tg: Unit) -> void:
	## R2: cartoon only. The helmet pops off and bounces, the boots fly, and there is no body left.
	tg.gone = true
	tg.soak = 0
	var cx := tg.x
	var cy := tg.y - tg.h / 2.0
	if faction(tg) != "jackal":
		for i in 14:
			part({"x": cx, "y": cy, "vx": (randf() - .5) * 6, "vy": -randf() * 5 - 1, "life": 50, "max": 50, "c": Color("9df25c"), "s": 3.0, "g": 0.22})
	else:
		part({"x": cx, "y": tg.y - tg.h, "vx": (randf() - .5) * 3, "vy": -5.5, "life": 150, "max": 150, "c": Color("5a6b3a"), "s": 6.0, "g": 0.22, "helmet": true})
		for k in [-1, 1]:
			part({"x": cx + k * 4, "y": tg.y - 4, "vx": k * (1.5 + randf() * 2), "vy": -3.0 - randf() * 2, "life": 110, "max": 110, "c": Color("3a2a1a"), "s": 4.0, "g": 0.22})
	for k in 3:
		puff(cx + randf_range(-10, 10), cy + randf_range(-10, 10), 2.0)
	float_at(cx, tg.y - tg.h - 52, "OVERKILL!", Color("ffd23a"), true)
	shake += 2
	Sfx.play("thud")

func collision_dmg(u: Unit, amt: float, label: String) -> void:
	var d := int(round(amt))
	if label == "FALL" and u.team == "squad" and Run.implanted(u.s, "spine"):
		return
	if u.team == "squad" and Run.relic_tier("boots") >= 3:
		d = 0
	elif u.team == "squad" and (u.def.key == "rook" or Run.has_gear("boots") or u.g("fall_half") > 0):
		d = int(ceil(d / 2.0))
	if d < 1 or u.dead:
		return
	if debug:
		print("[coll r%d] %s %s %d" % [round_n, u.def.key if u.team == "squad" else u.type, label, d])
	float_text(u, label, Color("e8dcc2"))
	shake += 2
	Sfx.play("bonk")
	if label == "FALL" and u.team == "squad":
		stats.falls += 1  # R5: SURE FOOTED
	var src = u.last_hit_by if u.last_hit_by != null and u.last_hit_by != u else null
	if src != null and src is Unit and src.perk("bulldozer"):
		d *= 2
	var was := kill_how
	kill_how = label
	damage(u, d, src, {"impact": true})
	kill_how = was

func crush(u: Unit, d: int, cause, kvx: float, kvy: float) -> void:
	## Called by the terrain when falling or toppling debris lands on a body.
	if u.fl.get("phased", false):
		return  # rubble settles right through a phased Stalker (and buries it)
	if debug:
		print("[crush r%d] %s %s d=%d" % [round_n, u.team, u.type, d])
	if u.team == "squad" and u.def.key == "rook":
		d = int(ceil(d / 2.0))
	if cause is Unit and cause.team == "squad" and cause.perk("democrew"):
		d *= 2
	float_text(u, "CRUSHED", Color("e8dcc2"), true)
	Sfx.play("thud")
	u.last_hit_by = cause
	if u.team == "enemy":
		stats.crushes += 1
		if state == "player" and not u.dead:
			act_crushed += 1
			act_crush_at = Vector2(u.x, u.y - 20)
		if cause != null and cause is Unit:
			give_xp(cause, 3)
	if u.type == "boss":
		crack_boss(u)
	if u.type == "vgate":
		d *= 3
		float_text(u, "CAVED IN!", Color("ffd23a"), true)
	if u.type == "queen" and u.weight != "buried":
		d *= 3
		float_text(u, "CAVED IN!", Color("ffd23a"), true)
	var was := kill_how
	kill_how = "CRUSHED"
	damage(u, d, cause, {"impact": true})
	kill_how = was
	if not u.heavy and not u.is_prop() and not u.dead:
		u.vx = kvx
		u.vy = kvy
		u.air = true
		u.walk = null

func blast_scale(owner) -> float:
	if owner == null or not (owner is Unit):
		return 1.0
	return (1.2 if owner.perk("bigboom") else 1.0) + float(owner.g("blast", 0.0))

func explode(x: float, y: float, r: float, dmg: int, owner, burn := false) -> void:
	if dmg > 0:
		coach_hit("blast")
	if owner is Unit and owner.has_st("fat"):
		r *= 1.5  # R6 FAT: 50% bigger blasts
	# FUEL-AIR: a blast inside smoke or gas grows by half; a gas cloud is used up
	var g = gas_at(x, y)
	if dmg > 0 and (g != null or smoke_at(x, y)):
		var thermo: bool = g != null and g.owner is Unit and g.owner.def.key == "hex"
		r *= 2.0 if thermo else 1.5
		if thermo:
			chain(g.owner, "THERMOBARIC")
		burn = burn or g != null
		tag("fuelair", x, y, false)
		if g != null:
			gases.erase(g)
	var own_sq: bool = owner != null and owner is Unit and owner.team == "squad"
	if own_sq and tut_step == TUT_THROW:
		tut_blast = true
	if own_sq and owner.perk("napalm"):
		burn = true
	if own_sq and owner.fl.get("accel", false):
		burn = true
		owner.fl.erase("accel")
	T.carve(x, y, r * 0.8 * (1.35 if own_sq and owner.perk("weakpoints") else 1.0), owner)
	if own_sq and owner.def.key == "vee" and state == "player" and dmg > 0:
		# CRATER: two of Vee's blasts on one spot in a turn
		var spots: Array = owner.fl.get("blasts", [])
		if spots.any(func(q): return q.distance_to(Vector2(x, y)) < 44) and not act_once.has("crater"):
			act_once["crater"] = true
			T.carve(x, y + 8, r * 1.4, owner)
			chain(owner, "CRATER")
			for o2 in units:
				if o2.team == "enemy" and not o2.dead and Vector2(o2.x - x, o2.y - o2.h / 2.0 - y).length() < r * 1.4:
					add_status(o2, "stun", 1, owner)
		spots.append(Vector2(x, y))
		owner.fl["blasts"] = spots
	Sfx.play("bigboom" if r > 45 else "boom")
	shake = minf(18, shake + r * 0.28)
	if has_node("Lights"):
		$Lights.flash(x, y, r * 2.2, Color("ffb45a"), 24)  # G6: the blast lights up its surroundings
	fireball(x, y, r, burn)
	if dmg <= 0:
		return
	var bonus := 3 if owner != null and owner is Unit and owner.team == "squad" and owner.def.key == "vee" else 0
	for u in units:
		if u.is_body():
			# no damage to the dead, but the blast throws them into whoever is close
			var bd := maxf(0, Vector2(u.x - x, u.y - u.h / 2.0 - y).length() - u.w / 2.0)
			if bd <= r:
				var ba := atan2(u.y - u.h / 2.0 - y - 6, u.x - x)
				var bk := (1 - bd / r) * 7 + 3
				u.vx = cos(ba) * bk
				u.vy = minf(-1.5, sin(ba) * bk - 1.5)  # flatter than a living Jackal: it skids into the next one
				u.air = true
				u.bumped = null
				u.last_hit_by = owner
			continue
		if u.dead or u.gone or u.kind == "pow" or u.kind == "cache" or u.kind == "relay" or u.kind == "slug" or u.kind == "pad":
			continue
		var cx: float = u.x
		var cy: float = u.y - u.h / 2.0
		var d := maxf(0, Vector2(cx - x, cy - y).length() - u.w / 2.0)
		if d > r:
			continue
		var f := 1 - (d / r) * 0.6
		var dm := maxi(1, int(round(dmg * f))) + bonus
		if u == owner:
			dm = 0 if u.perk("blastproof") or (u.team == "squad" and Run.implanted(u.s, "asbestos")) else maxi(1, int(round(dm * 0.4)))
		if not u.heavy and not u.is_prop() and not u.immovable and u.dome <= 0 and u.weight != "buried" and not shrug(u):
			var ang := atan2(cy - y - 6, cx - x)
			var k := ((1 - d / r) * 6 + 2.5) * kb(u)
			if u == owner and u.perk("kinetic"):
				k *= 1.6
				u.jumping = true
			if u == owner and u.team == "squad" and Run.implanted(u.s, "asbestos"):
				u.jumping = true  # Asbestos Hide: her own blast can't hurt her, landing included
			u.vx = cos(ang) * k
			u.vy = minf(-2.5, sin(ang) * k - 3)
			u.air = true
			u.walk = null
			u.bumped = null
			u.last_hit_by = owner
		if dm > 0:
			damage(u, dm, owner, {"blast": true})
			if burn:
				add_status(u, "burn", 2, owner)

# ---------------------------------------------------------------- player actions
func resolve(fn: Callable) -> void:
	busy = true
	card_idx = -1
	rummage_armed = false
	var snap := walk_snap
	walk_snap = {}
	undo_walk = {}
	ui_dirty = true
	act_once = {}
	act_crushed = 0
	await fn.call()
	for s in squad():
		if s.hang and s.fl.get("hung_shot", false):
			s.fl.erase("hung_shot")
			drop_hang(s)
	await until(settled)
	if state == "player":
		await foe_ai.unstack_squad()
	await wait(8)
	if act_crushed >= 3:
		announce_unlock(Run.feat("timber"))
	if act_crushed >= 2 and tag("domino", act_crush_at.x, act_crush_at.y):
		for s in squad_alive():
			s.energy += 1
			float_text(s, "+1 ENERGY", Color("ffd23a"))
		if act_unit != null and act_unit.def.key == "vee" and act_unit.last_cost > 0:
			act_unit.energy += act_unit.last_cost
			chain(act_unit, "DEMOLITION")
		drop_loot(act_crush_at.x, act_crush_at.y, {"type": "item", "item": Run.roll_item()})
	act_crushed = 0
	await post_action()
	if state == "player":
		busy = false
		if not snap.is_empty() and quiet_walk(snap):
			undo_walk = snap
	ui_dirty = true

func card_cost(u: Unit, inst: Dictionary) -> int:
	var c := Data.card(inst)
	var cost: int = c.cost
	if inst.get("free", false):
		return 0
	if c.type == "AIM" and u.perk("doubletap") and not u.aim_discount:
		cost = maxi(0, cost - 1)
	if c.type == "AIM" and u.fl.get("free_aim", false):
		cost = 0
	if c.get("smoke", false) and ks(u, "canister"):
		cost = 0
	if c.get("beacon", false) and ks(u, "howitzer"):
		cost = maxi(0, cost - 1)
	if inst.key == "sandbags" and (u.perk("bulwark") or (u.def.key == "bolt" and u.fl.get("bagged", false) and not u.fl.has("stacked"))):
		cost = 0
	if c.get("girder", false) and ks(u, "rivetdriver"):
		cost = 0
	if u.fl.get("syncfree", false):
		cost = 0
	if (inst.key == "handoff" and u.perk("quickpass")) or (inst.key == "grab" and u.perk("grip")):
		cost = 0
	if inst.key in ["stomp", "mcannon"] and u.perk("crusher"):
		cost = maxi(0, cost - 1)
	if inst.key == "stomp" and ks(u, "jumpjets"):
		cost = 0
	if inst.key == "roll" and u.s.get("trait", "") == "stuntman":
		cost = 0
	if inst.key == "patchjob" and u.perk("quickpatch"):
		cost = maxi(0, cost - 1)
	if inst.key == "mcannon" and u.def.key == "gears" and u.fl.get("cannoned", false) and not u.fl.has("broadside"):
		cost = 0
	if (inst.key == "sicem" and ks(u, "chokechain")) or (inst.key == "fetch" and ks(u, "treatbag")):
		cost = 0
	if spec_kits.is_build(c) and ks(u, "magnetglove") and not u.fl.get("built", false):
		cost = 0
	var zero := {"zipline": ks(u, "carabiner"), "flare": ks(u, "flaregun"), "drone": ks(u, "dronebay"), "deflect": ks(u, "mirrorblade"),
		"vanish": u.perk("smokeghost"), "walljump": u.perk("springheel"), "magnet": ks(u, "magboots"), "gravnade": ks(u, "gravcore") or u.perk("wellsable"),
		"designator": u.perk("rangefind"), "orders": ks(u, "officersword"), "supplydrop": ks(u, "supplytag"), "blink": u.perk("doubleblink") and u.def.key == "sable"}
	if zero.get(inst.key, false):
		cost = 0
	if inst.key == "supplydrop" and u.perk("logistics"):
		cost = maxi(0, cost - 1)
	if inst.key == "mindlink" and u.perk("longlink"):
		cost = maxi(0, cost - 1)
	return cost

func spend_card(u: Unit, idx: int, c_in = null) -> Dictionary:
	## Pays for a card and applies everything that happens on play: signature chains (C2),
	## perks and keystones that change the card, momentum. Pass the card dict the action
	## will use so chain bonuses reach it.
	var inst: Dictionary = u.hand[idx]
	var c: Dictionary = c_in if c_in != null else Data.card(inst)
	var cost := card_cost(u, inst)
	if u.team == "squad":
		coach_hit("card")
	u.fl.erase("syncfree")
	var ch := chain_ready(u, inst)
	if Data.is_attack(c) and u.st.has("cloak"):
		u.st.erase("cloak")
		float_text(u, "DECLOAKED", Color("b48cff"))
	u.hand.remove_at(idx)
	u.energy -= cost
	u.last_cost = cost
	if c.get("law", false):
		u.s["law_spent"] = true
	if c.get("mounted", false):
		var m = m2_near(u)
		if m != null:
			m.loot.sq = round_n
		for o in squad_alive():
			if o != u:
				o.hand = o.hand.filter(func(h): return h.key != "mounted" or m2_near(o) != m)
	if u.hang:
		if Data.is_attack(c):
			u.fl["hung_shot"] = true
		else:
			drop_hang(u)
	act_unit = u
	act_card = c.get("name", "")
	act_type = c.get("type", "")
	act_inst = inst
	u.played += 1
	if ch != "":
		chain(u, ch)
	match ch:
		"SPOTTED":
			c["forcehead"] = true
		"DUG IN":
			u.fl["ow_crit"] = true
		"DOUBLE BANK":
			u.fl.erase("free_aim")
		"SIX SHOOTER":
			u.fl["sixgun"] = true
			u.hand.append({"id": -2, "key": "pistol", "tier": Data.base_tier("pistol"), "temp": true, "free": true})
		"FROM THE FOG":
			if c.type == "AIM":
				c["forcehead"] = true
			elif c.has("dmg"):
				c.dmg = [int(c.dmg[0] * 1.5), int(c.dmg[1] * 1.5)] if c.dmg is Array else int(c.dmg * 1.5)
		"SCRUBBED IN":
			c.pellets = c.get("pellets", 1) + 3
		"DEATH FROM ABOVE":
			c.dmg = int(c.dmg * 1.5) if not (c.dmg is Array) else [int(c.dmg[0] * 1.5), int(c.dmg[1] * 1.5)]
		"ACCELERANT":
			u.fl.erase("molotov")
			u.fl["accel"] = true
		"COME AND GET IT":
			c.armor = c.get("armor", 0) * 2
		"ZIP STRIKE":
			u.energy += 1
		"JUICED":
			u.fl.erase("juiced")
			u.hand.append(inst)
		"COVERING FIRE":
			u.fl["covered"] = true
			c["cover"] = true
		"DOUBLE STACK":
			u.fl["stacked"] = true
		"TAG TEAM":
			c["forcehead"] = true
		"GOOD BOY":
			u.fl["goodboy"] = true
		"ON GUARD":
			u.fl["onguard"] = true
			var gt = u.fl.guarded
			if gt is Unit and not gt.dead:
				gt.armor += 5
				float_text(gt, "+5 ARMOR", Color("9fb4c9"), true)
		"THE HUNT":
			u.fl["hunt"] = true
		"WALK THE LINE", "PIT STOP", "TAG OUT":
			u.energy += 1
		"TEAMWORK":
			u.energy += u.last_cost
		"SET AND FORGET":
			u.fl["setforget"] = true
		"BROADSIDE":
			u.fl["broadside"] = true
		"BAIL OUT":
			u.energy += u.last_cost
		"LIGHT 'EM UP", "CALL IT IN":
			c["forcehead"] = true
		"ZIP AND SNIP", "AIR STRIKE", "NEWTON'S THIRD", "ON MY MARK", "PUPPETEER":
			u.energy += 1
		"EYE IN THE SKY", "KNIFE PARTY", "DRAW CUT", "SLINGSHOT", "EVENT HORIZON", "CONDUCTOR", "BRACKET", "RESUPPLY", "MELTDOWN", "HOLD STILL":
			u.energy += u.last_cost
		"RIPOSTE":
			c["stun"] = true
		"FROM NOWHERE":
			c.dmg = [c.dmg[0] * 2, c.dmg[1] * 2]
		"NOW YOU SEE ME":
			if c.type == "AIM":
				c.dmg = [c.dmg[0] * 2, c.dmg[1] * 2]
			else:
				u.energy += 1
	u.seq.append([inst.key, c.type])
	if inst.key == "molotov":
		u.fl["molotov"] = true
	if inst.key == "sandbags":
		u.fl["bagged"] = true
	if inst.key == "sentry":
		u.fl["sentried"] = true
	if inst.key == "mcannon":
		u.fl["cannoned"] = true
	if u.def.key == "moss" and c.type == "AIM":
		# B1 Wallbanger
		var sp := 99 if u.perk("fullmetal") or ch == "KNOCK KNOCK" else (1 if u.perk("softpoint") else 0)
		if sp > 0:
			c["softpass"] = sp
		if u.perk("overpen"):
			c["bodypass"] = 1
	if u.perk("bigbore") and inst.key in ["mcannon", "tankshell"]:
		c.radius = c.radius + 10
	if u.perk("heavystomp") and inst.key == "stomp":
		c.dmg = [c.dmg[0] + 6, c.dmg[1] + 6]
		c["sweep"] = true
	if spec_kits.is_build(c):
		u.fl["built"] = true
	if inst.key == "katana":
		var kd := (3 if u.perk("keenedge") else 0) + (3 if ks(u, "ancestral") else 0) + (6 if u.perk("aerial") and u.air else 0)
		c.dmg = [c.dmg[0] + kd, c.dmg[1] + kd]
		if ks(u, "ancestral"):
			c.range = c.range + 40
		if u.perk("sweepcut"):
			c["sweep"] = true
		if u.perk("terraincut"):
			c["cut"] = true
		if u.perk("parry"):
			u.fl["deflect"] = u.fl.get("deflect", 0) + 1
	if inst.key == "knives" and u.perk("loaded"):
		c.dmg = [c.dmg[0] + 2, c.dmg[1] + 2]
	if inst.key == "knives" and ks(u, "thermite"):
		c["burn"] = true
	if inst.key == "walljump" and ks(u, "climbclaws"):
		draw_cards(u, 1)
	if inst.key == "blink" and ks(u, "phaseorgan"):
		draw_cards(u, 1)
	if inst.get("nowind", false) or (u.def.key == "volta" and c.type == "ARC"):
		c["wind"] = 0.0
	if inst.key == "pistol" and u.perk("cylinder"):
		draw_cards(u, 1)
	if c.get("echo", 0) > 0:
		draw_cards(u, c.echo)
	# perk and keystone tweaks to the card itself
	if ks(u, "twinrev") and inst.key == "pistol":
		c.shots = c.get("shots", 1) * 2
		c.dmg = [maxi(1, int(c.dmg[0] * 0.6)), maxi(1, int(c.dmg[1] * 0.6))]
	if ks(u, "ammobelt") and inst.key == "hmg":
		c.shots = c.get("shots", 1) + 3
	if ks(u, "varga") and inst.key == "snipe":
		c["woodpass"] = true
	if u.perk("hosepipe") and c.get("gun", "") == "mg":
		c["pierce"] = true
		c["chip"] = 9
	var period := Data.MOMENTUM
	if u.perk("highnoon") or (Run.has_cmd("tempo") and round_n == 1):
		period = 2
	if u.team == "squad" and u.played % period == 0:
		# C1 momentum: every third card in a turn pays one energy back
		u.energy += 1
		float_text(u, "MOMENTUM +1", Color("b48cff"), true)
		Sfx.play("power", -8)
	if c.type == "AIM":
		u.aim_discount = true
	if inst.has("duo"):
		# a duo spends both soldiers' Overdrives (or every soldier's, for the Slug)
		consume_od(u)
		for o2 in squad_alive():
			if inst.duo == "squad" or o2.def.key == inst.duo:
				consume_od(o2)
		banner(Data.CARDS[inst.key].name.to_upper(), Color("ffb23e"), "DUO OVERDRIVE" if inst.duo != "squad" else "ALL FOUR OVERDRIVES")
	elif inst.get("od", false):
		u.adr = 0
	elif not inst.get("temp", false) and ch != "JUICED":
		u.disc.append(inst)
	ui_dirty = true
	return c

func hand_pos(u: Unit) -> Vector2:
	return Vector2(u.x + u.face * 6, u.y - u.h + 10)

func aim_vel(u: Unit, p: Vector2) -> Dictionary:
	var f := 1 if p.x >= u.x else -1
	var hx := u.x + f * 6
	var hy := u.y - u.h + 10
	var dx := p.x - hx
	var dy := p.y - hy
	var d := maxf(0.001, sqrt(dx * dx + dy * dy))
	var pw := clampf(minf(d, 220) / 220.0 * 13, 2, 13)
	return {"vx": dx / d * pw, "vy": dy / d * pw, "pw": pw, "hx": hx, "hy": hy, "f": f}

func sway_of(u: Unit, c: Dictionary) -> float:
	var s: float = c.get("sway", 0.0) * (4.0 if c.get("still", false) and u.moved else (1.0 if u.moved else 0.6))
	if u.fl.has("breath") and c.type == "AIM":
		return 0.0
	if u.perk("steady"):
		s *= 0.5
	if u.perk("bipod") and c.get("key", "") in ["hmg", "burst", "suppress", "leadrain"]:
		s *= 0.5
	if Run.has_gear("laser"):
		s *= 0.7
	s *= maxf(0.2, 1.0 - float(u.g("sway", 0.0)))
	if u.team == "squad" and Run.implanted(u.s, "cybereye"):
		s *= 0.75
	return s

func aim_angle(u: Unit, c: Dictionary, p: Vector2) -> Dictionary:
	var f := 1 if p.x >= u.x else -1
	var mx := u.x + f * 14
	var my := u.y - u.h + 15
	var sw := sway_of(u, c)
	var a := atan2(p.y - my, p.x - mx) + sin(sway_t * 0.055) * sw + sin(sway_t * 0.137 + 1) * sw * 0.5
	return {"a": a, "mx": mx, "my": my, "f": f}

const LEGUP_MUL := 1.27  # B2: a Hop off a squadmate's shoulders goes about 60% higher

func legup_buddy(u: Unit, c: Dictionary):
	## B2: the squadmate standing right beside a soldier about to Hop, who boosts them; null if none.
	if not c.get("hop", false) or u.mech != null or u.air:
		return null
	for s in squad_alive():
		if s != u and s.mech == null and not s.air and absf(s.x - u.x) < 30 and absf(s.y - u.y) < 16:
			return s
	return null

func jump_pow(u: Unit, c: Dictionary) -> float:
	## How hard this jump card launches the soldier, with a leg-up counted in.
	return c.get("jpow", 1.0) * (LEGUP_MUL if legup_buddy(u, c) != null else 1.0)

func jump_vel(u: Unit, p: Vector2, mul := 1.0) -> Dictionary:
	var hp_ := hand_pos(u)
	var dx := p.x - hp_.x
	var dy := p.y - hp_.y
	var d := maxf(0.001, sqrt(dx * dx + dy * dy))
	var reach := 240.0 * mul
	var pw := clampf(minf(d, reach) / reach * 10.5 * mul, 3, 10.5 * mul)
	return {"vx": dx / d * pw, "vy": minf(-2.5, dy / d * pw), "hx": hp_.x, "hy": hp_.y}

func pit_rim(u: Unit, dir: float):
	## The lip of the hole a soldier stands in, on the dir side: the highest ground within 64px
	## that side, if it is well above their feet. null when they are not down in a hole.
	var rim = null
	var x := u.x + dir * 10
	while absf(x - u.x) <= 64:
		var y = T.stand_y(x, u.y - 240)
		if y != null and y < u.y - 30 and (rim == null or y < rim.y):
			rim = Vector2(x, y)
		x += dir * 4
	return rim

func hop_out(u: Unit, v: Dictionary) -> Dictionary:
	## A Hop from the bottom of a hole always clears its lip, however deep it was dug, so a soldier
	## is never stuck down there without a Drill. Straight up the shaft, then over onto the lip.
	var dir := 1.0 if v.vx >= 0 else -1.0
	var rim = pit_rim(u, dir)
	if rim == null:
		return v
	var vy := -sqrt(2.0 * GRAV * (u.y - rim.y + 28))
	if vy >= v.vy:
		return v  # the hop as aimed already gets there
	# about 22 frames from passing the lip to landing on it
	u.vault = {"y": rim.y - 14, "vx": dir * clampf((absf(rim.x - u.x) + 8) / 22.0, 1.5, 4.0)}
	return {"vx": 0.0, "vy": vy, "hx": v.hx, "hy": v.hy}

func rush_vel(u: Unit, p: Vector2) -> Dictionary:
	var hp_ := hand_pos(u)
	var a := atan2(p.y - hp_.y, p.x - hp_.x)
	return {"vx": cos(a) * 10, "vy": minf(-2, sin(a) * 10), "hx": hp_.x, "hy": hp_.y}

func grapple_spot(u: Unit, p: Vector2, rng: float) -> Dictionary:
	var hp_ := hand_pos(u)
	var ang := atan2(p.y - hp_.y, p.x - hp_.x)
	var dx := cos(ang)
	var dy := sin(ang)
	var hit = null
	var d := 6.0
	while d < rng:
		var x := hp_.x + dx * d
		var y := hp_.y + dy * d
		if y < 0 or y > WATER_Y:
			break
		if T.solid(x, y):
			hit = Vector2(x, y)
			break
		d += 2
	if hit == null:
		return {"ok": false, "ax": hp_.x + dx * rng, "ay": hp_.y + dy * rng, "hx": hp_.x, "hy": hp_.y}
	if hit.x < cam_x + 12 or hit.x > cam_x + W - 16:
		return {"ok": false, "ax": hit.x, "ay": hit.y, "hx": hp_.x, "hy": hp_.y}
	var y: float = floorf(hit.y / CELL) * CELL
	var c := 0
	while T.solid(hit.x, y - 1) and c < 14:
		y -= CELL
		c += 1
	if T.solid(hit.x, y - 1) or not T.solid(hit.x, y):
		return {"ok": false, "ax": hit.x, "ay": hit.y, "hx": hp_.x, "hy": hp_.y}
	var yy := y - u.h + 2
	while yy < y - 1:
		if T.solid(hit.x, yy):
			return {"ok": false, "ax": hit.x, "ay": hit.y, "hx": hp_.x, "hy": hp_.y}
		yy += CELL
	return {"ok": true, "ax": hit.x, "ay": hit.y, "x": hit.x, "y": y, "hx": hp_.x, "hy": hp_.y}

func fire_aim(u: Unit, c: Dictionary, p: Vector2, sc: bool) -> void:
	var shots: int = c.get("shots", 1)
	var aa := aim_angle(u, c, p)
	u.face = aa.f
	for s in shots:
		if u.dead:
			break
		Sfx.play("snipe" if c.get("pierce", false) else ("mg" if shots > 1 else "shot"))
		u.muzzle = 4
		u.muzzle_kind = "snipe" if c.get("pierce", false) else ("mg" if shots > 1 else "shot")
		u.gun_target = atan2(sin(aa.a), cos(aa.a) * u.face)
		u.pose = "recoil"; u.pose_t = 6
		var m := muzzle(u)
		for k in c.get("pellets", 1):
			var spr := 0.0
			if c.has("spread"):
				spr = (randf() - .5) * 2 * c.spread if c.has("pellets") else gauss() * c.spread * minf(1, s * 0.6 + 0.25)
			fire_bullet(u, m.x, m.y, aa.a + spr, c, sc)
		part({"x": m.x - u.face * 8, "y": m.y, "vx": -u.face * randf_range(1, 2), "vy": -randf_range(2, 3), "life": 40, "max": 40, "c": Color("ffd23a"), "s": 2.0, "g": 0.25})
		await wait(7 if shots > 1 else 14)

func commit_aim(p: Vector2) -> void:
	var u := sel
	if u == null or card_idx < 0 or busy:
		return
	if card_idx >= u.hand.size():
		return
	var inst: Dictionary = u.hand[card_idx]
	var c := Data.card(inst)
	var idx := card_idx
	var sc: bool = u.adr >= 50 and not inst.get("od", false)
	var why := vehicle_ops.mech_ok(u, c)
	if why != "":
		float_text(u, why, Color("ff7a3d"))
		Sfx.play("deny")
		return
	if c.get("eject", false):
		resolve(func(): await vehicle_ops._act_eject(u, idx, c, p))
		return
	if c.type == "AIM":
		if aim_hold and sway_of(u, c) >= 0.01 and u.move_left > 0:
			# X4: planting for a steady shot spends the rest of the walk
			u.move_left = 0
			float_text(u, "STEADIED: NO MORE MOVE", Color("e8dcc2"))
		resolve(func(): await _act_aim(u, idx, c, p, sc))
		return
	if c.get("bodythrow", false):
		resolve(func(): await spec_kits._act_bodythrow(u, idx, c, p))
		return
	if c.type == "ARC":
		resolve(func(): await _act_arc(u, idx, c, p, sc))
		return
	if c.type == "LINE":
		if c.get("grapple", false):
			var gs := grapple_spot(u, p, c.range)
			if not gs.ok:
				float_text(u, "NO GRIP", Color("ff7a3d"))
				return
			resolve(func(): await _act_grapple(u, idx, gs))
			return
		if c.get("girder", false):
			resolve(func(): await spec_kits._act_girder(u, idx, c, p))
			return
		if c.has("daisy"):
			resolve(func(): await spec_kits._act_daisy(u, idx, c, p))
			return
		if c.get("zipline", false):
			if not spec_kits.zip_spot(u, c, p).ok:
				float_text(u, "NOWHERE TO LAND", Color("ff7a3d"))
				Sfx.play("deny")
				return
			resolve(func(): await spec_kits._act_zip(u, idx, c, p))
			return
		if c.has("magnet"):
			resolve(func(): await spec_kits._act_magnet(u, idx, c, p))
			return
		if c.has("iaido"):
			resolve(func(): await spec_kits._act_iaido(u, idx, c, p))
			return
		if c.has("dog"):
			var dt := spec_kits.dog_target(u, c, p)
			if not dt.ok:
				float_text(u, dt.why, Color("ff7a3d"))
				Sfx.play("deny")
				return
			resolve(func(): await spec_kits._act_dog(u, idx, c, p))
			return
		if c.get("drill", false):
			if out_of_move(u, c):
				float_text(u, "NO MOVE LEFT", Color("ff7a3d"))
				Sfx.play("deny")
				return
			resolve(func(): await _act_drill(u, idx, c, p))
			return
		if c.get("jump", false):
			if out_of_move(u, c):
				float_text(u, "NO MOVE LEFT", Color("ff7a3d"))
				return
			resolve(func(): await _act_jump(u, idx, p))
			return
		if c.get("rush", false):
			resolve(func(): await _act_rush(u, idx, p))
			return
		if c.get("roll", false):
			if u.air:
				float_text(u, "NOT IN THE AIR", Color("ff7a3d"))
				Sfx.play("deny")
				return
			resolve(func(): await _act_roll(u, idx, c, p))
			return
		resolve(func(): await _act_rocket(u, idx, c, p, sc))

func _act_aim(u: Unit, idx: int, c: Dictionary, p: Vector2, sc: bool) -> void:
	if c.get("gun", "") == "mg" and not c.get("mounted", false):
		# B5: a heavy MG spins up; its second burst in a turn hits harder
		if u.fl.get("spun", false):
			c = c.duplicate()
			c.dmg = [c.dmg[0] + 1, c.dmg[1] + 1]
			float_text(u, "SPUN UP +1", Color("ffd23a"))
		u.fl["spun"] = true
	var kick := recoil_vel(u, c, aim_angle(u, c, p).a)
	spend_card(u, idx, c)
	if u.fl.has("breath"):
		c.dmg = [c.dmg[0] + u.fl.breath, c.dmg[1] + u.fl.breath]
		u.fl.erase("breath")
	u.attacked = true
	await fire_aim(u, c, p, sc)
	if c.get("cover", false):
		for st in units.filter(func(o): return o.kind == "sentry" and not o.dead and o.loot.by == u):
			await spec_kits.sentry_fire(st)
	await apply_recoil(u, kick)
	await wait(6)

func out_of_move(u: Unit, c: Dictionary) -> bool:
	## Drill spends movement: with none left it can't be played (the hand crosses it out). Hop works
	## at zero movement, so a soldier who walked up to a ledge can always get onto it.
	if c.get("drill", false):
		return u.move_left + c.get("reach", 0) < 4
	return false

func recoil_vel(u: Unit, c: Dictionary, ang: float) -> Vector2:
	## The shove a heavy gun gives its shooter: straight back from the shot, with a little lift.
	## Shooting down at your feet lifts you more. Immovable and heavy soldiers don't budge.
	var k := Data.recoil(c)
	if k <= 0.0 or u.heavy or u.immovable or u.air or u.team != "squad":
		return Vector2.ZERO
	return Vector2(-cos(ang) * k, -1.3 - maxf(0.0, sin(ang)) * k * 0.6)

func apply_recoil(u: Unit, v: Vector2) -> void:
	if v == Vector2.ZERO or u.dead:
		return
	u.vx = v.x; u.vy = v.y; u.air = true; u.walk = null; u.bumped = null
	float_text(u, "RECOIL", Color("c9d1da"))
	await until(func(): return not u.air or u.dead)

func sim_body(u: Unit, vx: float, vy: float, thrust = null, fuel := 0) -> Dictionary:
	## Where a body thrown with (vx, vy) comes down, stepped exactly like physics() does.
	## With a thrust target it also burns jet fuel toward that point first (Jet Boots preview).
	return sim_body_xy(u, u.x, u.y, vx, vy, thrust, fuel)

func sim_body_from(u: Unit, x: float, y: float, vx: float) -> Dictionary:
	return sim_body_xy(u, x, y, vx, 0.0)

func sim_body_xy(u: Unit, x: float, y: float, vx: float, vy: float, thrust = null, fuel := 0) -> Dictionary:
	var pts: Array = []
	for k in 600:
		if thrust != null and fuel > 0:
			var a := jet_accel(Vector2(x, y - u.h / 2.0), thrust)
			vx = clampf(vx + a.x, -JET_MAX_VX, JET_MAX_VX)
			vy = clampf(vy + a.y, -JET_MAX_VY, 10.0)
			fuel -= 1
		vy = minf(vy + grav, 10.0)
		var n := maxi(1, int(ceil(maxf(absf(vx), absf(vy)) / 2.0)))
		for i in n:
			var nx := x + vx / n
			if T.solid(nx, y - u.h * 0.5) or T.solid(nx, y - 6):
				vx *= -0.25
			else:
				x = nx
			if u.team == "squad":
				x = clampf(x, cam_x + 8, cam_x + W - 8)
			var ny := y + vy / n
			if vy > 0 and T.solid(x, ny):
				var ly := floorf(ny / CELL) * CELL
				while T.solid(x, ly - 1) and ly > 0:
					ly -= CELL
				var lm := T.mat(x, ly)
				if lm == Terrain.RUBBER and vy > 2.5:
					y = ly - 0.5
					vy = -vy * 0.85
					continue
				if lm == Terrain.ICE and absf(vx) > 0.6:
					# skid on: the ghost shows where the ice lets go of them
					var v := clampf(vx * 0.9, -4.0, 4.0)
					var fall := int(round((vy - 6.5) * 2.5)) if vy > 6.5 and thrust == null else 0
					for f in 300:
						var sl := ice_step(u, x, ly, v)
						x = sl.x; ly = sl.y; v = sl.v
						if f % 3 == 0:
							pts.append(Vector2(x, ly))
						if sl.air:
							var rest := sim_body_from(u, x, ly, v)
							pts.append_array(rest.pts)
							rest.pts = pts
							return rest
						if v == 0:
							break
					pts.append(Vector2(x, ly))
					return {"x": x, "y": ly, "pts": pts, "water": false, "fall": fall}
				pts.append(Vector2(x, ly))
				return {"x": x, "y": ly, "pts": pts, "water": false, "fall": int(round((vy - 6.5) * 2.5)) if vy > 6.5 and thrust == null else 0}
			if vy < 0 and T.solid(x, ny - u.h):
				vy = 0
			else:
				y = ny
		pts.append(Vector2(x, y))
		if y > WATER_Y + 2:
			return {"x": x, "y": y, "pts": pts, "water": true, "fall": 0}
	return {"x": x, "y": y, "pts": pts, "water": false, "fall": 0}

func _act_arc(u: Unit, idx: int, c: Dictionary, p: Vector2, sc: bool) -> void:
	spend_card(u, idx, c)
	if u.perk("thicksmoke") and (c.get("smoke", false) or c.get("gas", false)):
		c.srad = c.get("srad", 64.0) * 1.25
		c.sturns = c.get("sturns", 2) + 1
	if c.get("smoke", false) and ks(u, "canister"):
		c["bounce"] = true
		c["fuse"] = 90
	if c.get("beacon", false) and ks(u, "howitzer"):
		c.bombs = c.get("bombs", 3) + 2
	if c.get("beacon", false):
		c.bombs = c.get("bombs", 3) + spec_kits.beacon_bonus(u, c)
	u.attacked = true
	var v := aim_vel(u, p)
	u.face = v.f
	u.pose = "throw"; u.pose_t = 24
	await wait(8)
	Sfx.play("toss")
	var fuse = c.get("fuse", null)
	if fuse != null and fuse_pick > 0 and c.get("bounce", false):
		fuse = fuse_pick
	if fuse != null and u.has_st("cluster") and not c.get("smoke", false) and not c.get("gas", false):
		c.cluster = c.get("cluster", 0) + 3
		u.st.cluster -= 1
		if u.st.cluster <= 0:
			u.st.erase("cluster")
		float_text(u, "CLUSTER!", Color("ffd23a"))
	var dmg_bonus := 0
	if fuse != null and u.perk("shortfuse"):
		fuse = int(fuse / 2)
		dmg_bonus = 2
	var r: float = c.get("radius", 0) * (1.2 if sc else 1.0) * blast_scale(u)
	projs.append(phys.mk_proj({"kind": "smoke" if c.get("smoke", false) or c.get("gas", false) else ("beacon" if c.get("beacon", false) else ("frag" if fuse != null else "shell")),
		"x": v.hx, "y": v.hy, "vx": v.vx, "vy": v.vy, "wind": spec_kits.wind_of(u, c), "r": r,
		"dmg": int(round((c.get("dmg", 0) + dmg_bonus) * (1.25 if sc else 1.0))), "bounce": c.get("bounce", false), "fuse": fuse,
		"smoke": c.get("smoke", false), "gas": c.get("gas", false), "srad": c.get("srad", 64.0), "sturns": c.get("sturns", 2), "bombs": c.get("bombs", 3),
		"beacon": c.get("beacon", false), "cluster": c.get("cluster", 0), "owner": u, "trail": fuse == null, "card": c, "x0": u.x}))
	await wait(4)

func _act_grapple(u: Unit, idx: int, gs: Dictionary) -> void:
	spend_card(u, idx)
	u.face = 1 if gs.x >= u.x else -1
	Sfx.play("grapple")
	ropes.append({"u": u, "x": gs.ax, "y": gs.ay, "t": 30})
	u.zip = {"x0": u.x, "y0": u.y, "x1": gs.x, "y1": gs.y, "t": 0.0}
	await until(func(): return u.zip == null)
	u.moved = true
	if u.perk("hookshot"):
		for o2 in units:
			if o2.team == "enemy" and not o2.dead and not o2.heavy and absf(o2.x - u.x) < 70 and absf(o2.y - u.y) < 50:
				o2.vx = signf(u.x - o2.x) * 6.5; o2.vy = -3.0; o2.air = true; o2.walk = null; o2.bumped = null; o2.last_hit_by = u
				add_status(o2, "stun", 1, u)
				float_text(o2, "HOOKED", Color("ffd23a"), true)
				break
	await check_push(u)

func _act_jump(u: Unit, idx: int, p: Vector2) -> void:
	var c := spend_card(u, idx)
	var buddy = legup_buddy(u, c)
	u.fl["jumped"] = true
	if c.get("padbounce", false):
		u.fl["padbounced"] = true
		float_text(u, "BOING!", Color("ffd23a"))
	if buddy != null:
		bark(buddy, "UP YOU GO!")
		buddy.pose = "cheer"; buddy.pose_t = 30
		float_text(u, "LEG-UP", Color("62d26f"))
	if c.get("hop", false):
		u.move_left = 0  # a hop is the rest of your legwork for the turn
	if c.get("rjump", false):
		explode(u.x, u.y - 4, 30, 6, u)
		await wait(2)
	var v := jump_vel(u, p, c.get("jpow", 1.0) * (LEGUP_MUL if buddy != null else 1.0))
	var dir := 1 if v.vx >= 0 else -1
	if c.get("hop", false):
		v = hop_out(u, v)
	u.face = dir
	u.vx = v.vx; u.vy = v.vy; u.air = true; u.jumping = true; u.walk = null
	Sfx.play("rocket")
	for i in 10:
		part({"x": u.x, "y": u.y, "vx": (randf() - .5) * 2, "vy": randf() * 2, "life": 24, "max": 24, "c": pick([Color("ffb23e"), Color("ff7a3d"), Color("9a9a9a")]), "s": 3.0, "g": 0.05, "fire": true})
	if not c.get("hop", false):
		await until(func(): return u.vy >= 0 or not u.air or u.dead)
		for k in c.get("frags", 0):
			projs.append(phys.mk_proj({"kind": "frag", "x": u.x, "y": u.y - 10, "vx": (k - 1) * 1.6 + u.vx * 0.3, "vy": 1.0, "r": 34.0 * blast_scale(u), "dmg": 11, "bounce": true, "fuse": 50 + k * 10, "owner": u}))
		if c.get("frags", 0) > 0:
			Sfx.play("toss")
		hang_up(u)
		if u.hang:
			u.moved = true
			return
	await until(func(): return not u.air or u.dead)
	u.moved = true

const DRILL_SPEED := 2.0
const DRILL_R := 11.0

func drill_dir(u: Unit, p: Vector2) -> Vector2:
	## Toward the cursor, from straight across down to straight down; never steeper up than 45 degrees.
	var dx := p.x - u.x
	var face := 1.0 if dx >= 0 else -1.0
	var a := clampf(atan2(p.y - (u.y - u.h / 2.0), absf(dx)), -PI / 4.0, PI / 2.0)
	return Vector2(cos(a) * face, sin(a))

func drill_len(u: Unit, c: Dictionary, p: Vector2) -> float:
	## How far this drill goes: out to the cursor along the bore line, as far as movement allows.
	var d := drill_dir(u, p)
	var want := maxf(8.0, (p - Vector2(u.x, u.y - u.h / 2.0)).dot(d))
	return minf(want, u.move_left * drill_mul(u) + c.get("reach", 0))

func drill_mul(u: Unit) -> float:
	## P2 Miner: the Drill bores twice as far on the same movement.
	return 2.0 if u.team == "squad" and u.s.get("trait", "") == "miner" else 1.0

func drill_face(u: Unit, x: float, y: float, d: Vector2) -> bool:
	## Is there terrain right in front of the drill bit at a body standing at (x, y)?
	for k in [4.0, 12.0, 20.0, 28.0]:
		if T.solid(x + d.x * DRILL_R, y - k + d.y * DRILL_R):
			return true
	return false

func drill_step(u: Unit, D: Dictionary):
	## The next spot on the drill's line, or null where it has to stop: out of movement, the edge of
	## the screen, the waterline, an enemy in the way, or open air with nothing under the boots.
	## Squadmates are passed by, the way walking passes them.
	if D.stop or D.left < 0.5:
		return null
	var sp := minf(DRILL_SPEED, D.left)
	var nx: float = u.x + D.dx * sp
	var ny: float = u.y + D.dy * sp
	if nx < cam_x + 8 or nx > cam_x + W - 8 or ny < u.h + 6 or ny > WATER_Y - 4:
		return null
	for o in units:
		if o != u and not o.dead and not o.gone and o.team == "enemy" and absf(o.x - nx) < (o.w + u.w) / 2.0 - 2 and ny > o.y - o.h and ny - u.h < o.y:
			return null
	var d := Vector2(D.dx, D.dy)
	if not drill_face(u, nx, ny, d) and not T.solid(nx, ny + 2):
		# nothing to bore and nothing underfoot: step down a slope like walking would
		var sy = T.stand_y(nx, ny)
		if sy != null and sy - ny <= 12:
			return Vector2(nx, sy)
		D.air += 1
		if D.air > 3:
			return null
	else:
		D.air = 0
	return Vector2(nx, ny)

func sim_drill(u: Unit, d: Vector2, budget: float) -> Dictionary:
	## The aim preview: where the drill stops on untouched terrain.
	var D := {"dx": d.x, "dy": d.y, "left": budget, "stop": false, "air": 0}
	var save := Vector2(u.x, u.y)
	var pts: Array = []
	while true:
		var nxt = drill_step(u, D)
		if nxt == null:
			break
		D.left -= DRILL_SPEED
		u.x = nxt.x; u.y = nxt.y
		pts.append(Vector2(u.x, u.y))
	var end := Vector2(u.x, u.y)
	u.x = save.x; u.y = save.y
	return {"x": end.x, "y": end.y, "pts": pts, "water": false, "fall": 0}

func drill_tick(u: Unit) -> void:
	var D: Dictionary = u.drill
	var nxt = drill_step(u, D)
	if nxt == null or u.dead:
		u.drill = null
		T.check_floating(u.x, u.y - u.h / 2.0, u.h + 8, u)
		T.check_bridges(u)
		return
	D.left -= DRILL_SPEED
	D.n += 1
	u.x = nxt.x; u.y = nxt.y
	u.face = 1 if D.dx >= 0 else -1
	u.anim += 1
	var oy: float = maxf(0.0, D.dy) * 3.0
	if T.bore(u.x + D.dx * 3, u.y + oy - DRILL_R + 1, u.y + oy - u.h + DRILL_R - 2, DRILL_R):
		var tip := Vector2(u.x + D.dx * (DRILL_R + 4), u.y - u.h / 2.0 + D.dy * DRILL_R)
		if t % 3 == 0:
			sparks(tip.x, tip.y, 2)
		if t % 4 == 0:
			dust(tip.x, tip.y, Color("c9b38a"), 2)
		if D.n % 6 == 0:
			T.check_floating(u.x, u.y - u.h / 2.0, u.h + 8, u)
			T.check_bridges(u)
	if D.n % 9 == 0:
		Sfx.play("mg", -14)
	shake = maxf(shake, 1.2)

func _act_drill(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	## Worms' drill: bore toward the cursor through dirt, wood, stone and steel alike until the
	## movement runs out or the player clicks to stop. Spent once; it comes back on a later draw.
	spend_card(u, idx, c)
	var reach: float = c.get("reach", 0)
	var budget := drill_len(u, c, p)
	var d := drill_dir(u, p)
	u.walk = null
	u.vx = 0; u.vy = 0; u.air = false
	u.face = 1 if d.x >= 0 else -1
	u.drill = {"dx": d.x, "dy": d.y, "left": budget, "stop": false, "air": 0, "n": 0}
	var D: Dictionary = u.drill
	Sfx.play("power", -6)
	float_text(u, "DRILLING  CLICK TO STOP", Color("ffd23a"))
	await until(func(): return u.drill == null or u.dead)
	u.drill = null
	var used: float = budget - maxf(0.0, D.left)
	u.move_left = maxf(0.0, u.move_left - maxf(0.0, used - reach) / drill_mul(u))
	u.moved = true
	stats["drilled"] = stats.get("drilled", 0) + int(used)
	if not u.dead and not T.solid(u.x, u.y + 1):
		u.air = true
	await until(func(): return not u.air or u.dead)
	await check_push(u)

func stop_drill() -> bool:
	## Click (or SPACE/ESC) while drilling: stop where you are.
	for u in units:
		if u.drill != null:
			u.drill.stop = true
			return true
	return false

func jet_accel(from: Vector2, to: Vector2) -> Vector2:
	var d := to - from
	if d.length() < 4:
		return Vector2(0, -JET_LIFT)
	return d.normalized() * JET_THRUST + Vector2(0, -JET_LIFT)

func toggle_jet() -> void:
	## J / the JET button: arm the selected soldier's Jet Boots. Click and hold to fly at the cursor.
	if state != "player" or busy or sel == null or sel.dead or sel.fuel_max <= 0:
		return
	if sel.fuel <= 0:
		float_text(sel, "NO FUEL", Color("ff7a3d"))
		Sfx.play("deny")
		return
	jet_armed = not jet_armed
	card_idx = -1
	Sfx.play("click")
	ui_dirty = true

func start_jet(u: Unit) -> void:
	jet_armed = false
	jet_hold = true
	resolve(func(): await _act_jet(u, func(): return mouse, func(): return jet_hold))

func _act_jet(u: Unit, aim: Callable, held: Callable) -> void:
	## Soldat's jet boots: thrust toward the cursor while the button is held and fuel lasts.
	## Gravity takes over when you let go. You land soft, but nothing stops you over water.
	u.walk = null
	u.jetting = true
	u.fl["jumped"] = true
	Sfx.play("rocket", -4)
	while not u.dead:
		await wait(1)  # thrust at the top of each tick, before physics moves the body
		if not held.call() or u.fuel <= 0:
			break
		var a := jet_accel(Vector2(u.x, u.y - u.h / 2.0), aim.call())
		u.vx = clampf(u.vx + a.x, -JET_MAX_VX, JET_MAX_VX)
		u.vy = clampf(u.vy + a.y, -JET_MAX_VY, 10.0)
		if absf(u.vx) > 0.3:
			u.face = 1 if u.vx > 0 else -1
		u.air = true
		u.jumping = true
		u.fuel -= 1
		if t % 2 == 0:
			for f in [-4, 4]:
				part({"x": u.x + f, "y": u.y, "vx": (randf() - .5) * 0.8, "vy": 1.5 + randf() * 1.5, "life": 14, "max": 14, "c": pick([Color("ffd23a"), Color("ff7a3d"), Color("ffb23e")]), "s": 2.0, "g": 0.0, "fire": true})
	u.jetting = false
	if u.fuel <= 0:
		float_text(u, "FUEL OUT", Color("ff7a3d"))
	else:
		hang_up(u)  # let go of the jets with fuel left: time stops for a mid-air shot
	if u.hang:
		u.moved = true
		return
	await until(func(): return not u.air or u.dead)
	u.moved = true

func can_shoot(u: Unit) -> bool:
	return u.hand.any(func(inst): return Data.is_attack(Data.card(inst)) and u.energy >= card_cost(u, inst))

func hang_up(u: Unit) -> void:
	## J4 mid-air shots: at the top of a jump (or when the jets cut out) time stops for one shot.
	if u.dead or not u.air or u.team != "squad" or state != "player" or not can_shoot(u):
		return
	u.hang = true
	u.fl["hang_v"] = Vector2(u.vx, u.vy)  # the arc picks up where it paused once they let go
	u.vx = 0.0
	u.vy = 0.0
	u.fl["hung_shot"] = false
	float_text(u, "TOP GUN: TAKE THE SHOT", Color("ffd23a"))

func drop_hang(u) -> void:
	if u is Unit and u.hang:
		u.hang = false
		var v: Vector2 = u.fl.get("hang_v", Vector2.ZERO)
		u.fl.erase("hang_v")
		u.vx = v.x
		u.vy = v.y if v != Vector2.ZERO else 0.5

func drop_all_hangs() -> void:
	for u in squad():
		drop_hang(u)

func roll_path(u: Unit, c: Dictionary, p: Vector2) -> Dictionary:
	## J3: low enough to pass crawl-height gaps, but never stops where it can't stand up.
	var d: float = c.get("dist", 150)
	var dir := 1 if p.x >= u.x else -1
	var h0 := u.h
	u.h = 16
	var sim := phys.sim_walk(u, u.x + dir * d, d)
	u.h = h0
	while sim.pts.size():
		var q: Array = sim.pts[-1]
		var clear := true
		var hy: float = q[1] - h0 + 2
		while hy < q[1] - 1:
			if T.solid(q[0], hy):
				clear = false
				break
			hy += CELL
		if clear:
			break
		sim.pts.pop_back()
	if sim.pts.size():
		sim.x = sim.pts[-1][0]
		sim.y = sim.pts[-1][1]
	else:
		sim.x = u.x
		sim.y = u.y
	return sim

func _act_roll(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	c = spend_card(u, idx, c)
	var sim := roll_path(u, c, p)
	u.st["roll"] = 1
	u.face = 1 if p.x >= u.x else -1
	if sim.pts.is_empty():
		float_text(u, "TUCK", Color("e8dcc2"))
		return
	var h0 := u.h
	u.h = 16
	u.rolling = true
	Sfx.play("toss", -6)
	var dfx = vfx.dash(u) if vfx != null else null
	await phys.walk_along(u, sim.pts)
	if dfx != null:
		dfx.stop()
	u.rolling = false
	u.rot = 0.0
	u.h = h0
	dust(u.x, u.y, Color("b9a27a"), 4)
	u.moved = true

func _act_rush(u: Unit, idx: int, p: Vector2) -> void:
	var c := spend_card(u, idx)
	if c.has("stab"):
		u.fl["stab"] = c.stab
	if c.has("squadheal"):
		for s in squad_alive():
			s.hp = mini(s.max_hp, s.hp + c.squadheal)
			gain_adr(s, 25)
			float_text(s, "+%d HP" % c.squadheal, Color("62d26f"))
			Sfx.play("heal", -4)
	var v := rush_vel(u, p)
	if c.get("cannon", false):
		v.vx *= 1.35
		v.vy *= 1.2
	u.face = 1 if v.vx >= 0 else -1
	u.vx = v.vx; u.vy = v.vy; u.air = true; u.rushing = true; u.bumped = {}; u.last_hit_by = u; u.walk = null
	Sfx.play("power")
	await until(func(): return not u.air or u.dead)
	u.rushing = false
	u.fl.erase("stab")
	if c.get("pack", false) and not u.dead:
		await spec_kits.release_hounds(u, c, 2)
	if c.get("cannon", false) and not u.dead:
		explode(u.x, u.y - 8, 54, 18, u)
		float_text(u, "CANNONBALL!", Color("ffb23e"), true)
	u.moved = true
	await check_push(u)

func _act_rocket(u: Unit, idx: int, c: Dictionary, p: Vector2, sc: bool) -> void:
	spend_card(u, idx, c)
	u.attacked = true
	var hp_ := hand_pos(u)
	u.face = 1 if p.x >= u.x else -1
	var base := atan2(p.y - hp_.y, p.x - hp_.x)
	var kick := recoil_vel(u, c, base)
	u.gun_target = atan2(sin(base), cos(base) * u.face)
	var n: int = c.get("count", 1)
	for i in n:
		var a := base + ((i - 1) * 0.07 if n > 1 else 0.0)
		Sfx.play("rocket")
		u.muzzle = 4
		u.muzzle_kind = "rocket"
		u.pose = "recoil"; u.pose_t = 8
		projs.append(phys.mk_proj({"kind": "rocket", "x": hp_.x, "y": hp_.y, "vx": cos(a) * c.speed, "vy": sin(a) * c.speed, "grav": 0.0, "r": c.radius * (1.2 if sc else 1.0) * blast_scale(u), "dmg": int(round(c.dmg * (1.25 if sc else 1.0))), "owner": u, "trail": true, "homing": c.get("homing", false), "lizard": ks(u, "lizard"), "card": c, "x0": u.x}))
		for k in 4:
			puff(hp_.x - u.face * 10, hp_.y, 1.2)
		await wait(8)
	await apply_recoil(u, kick)

func play_on_target(tg: Unit) -> void:
	var u := sel
	if u == null or card_idx < 0 or busy or card_idx >= u.hand.size():
		return
	var idx := card_idx
	var inst: Dictionary = u.hand[idx]
	var c := Data.card(inst)
	var sc: bool = u.adr >= 50 and not inst.get("od", false)
	var why := vehicle_ops.mech_ok(u, c)
	if why != "":
		float_text(u, why, Color("ff7a3d"))
		Sfx.play("deny")
		return
	if c.type == "MELEE":
		if not melee_valid(u, tg, c):
			return
		resolve(func(): await _act_melee(u, idx, c, tg, sc))
	elif c.type == "ALLY":
		if not ally_valid(u, tg, c):
			return
		resolve(func(): await _act_ally(u, idx, c, tg))

func _act_melee(u: Unit, idx: int, c: Dictionary, tg: Unit, sc: bool) -> void:
	spend_card(u, idx, c)
	u.attacked = true
	if c.get("grab", false):
		await spec_kits._act_grab(u, c, tg)
		return
	if c.get("suplex", false):
		await spec_kits._act_suplex(u, c, tg, sc)
		return
	if c.get("piledrive", false):
		await spec_kits._act_piledrive(u, c, tg)
		return
	if c.has("mindlink"):
		u.attacked = false
		spec_kits.mind_link(u, tg, 2 if ks(u, "psicrown") else 1)
		if u.perk("linkheal"):
			u.hp = mini(u.max_hp, u.hp + 6)
			float_text(u, "+6 HP", Color("62d26f"))
		await wait(14)
		return
	u.face = 1 if tg.x >= u.x else -1
	u.pose = "throw"; u.pose_t = 16
	Sfx.play("slash")
	spec_kits.slash_fx(tg.x, tg.y - tg.h / 2.0, 1.6, u.face)
	await wait(6)
	var d := ri(c.dmg[0], c.dmg[1])
	if sc:
		d = int(round(d * 1.25))
	if u.s.get("trait", "") == "boxer":
		d += 3
	if c.get("key", "") == "katana" and u.perk("backstab") and tg.face == int(signf(tg.x - u.x)):
		d *= 2
		float_text(tg, "BACKSTAB", Color("e0f4ff"), true)
	if c.get("cut", false):
		T.carve(u.x + u.face * 30, u.y - 16, 14, u)
	var victims: Array = [tg]
	if (ks(u, "zantetsu") and c.key == "knife") or c.get("sweep", false):
		# Zantetsu: one sweep cuts every body in reach and the terrain in front
		for o2 in units:
			if o2 != tg and not o2.dead and not o2.gone and o2.team != "squad" and not o2.is_pickup() and o2.kind != "pow" and signf(o2.x - u.x) == u.face and absf(o2.x - u.x) <= c.range + 24 and absf(o2.y - u.y) < 40:
				victims.append(o2)
		T.carve(u.x + u.face * 30, u.y - 16, 14, u)
	for v in victims:
		damage(v, d, u, {"melee": true})
		if c.get("stun", false):
			add_status(v, "stun", 1, u)
		if c.get("mark", false):
			add_status(v, "mark", 2, u)
		if not v.heavy and not v.dead and not v.is_prop() and not v.immovable:
			v.vx = u.face * c.knock * kb(v); v.vy = -3.5; v.air = true; v.walk = null; v.bumped = null; v.last_hit_by = u
	if c.has("selfheal"):
		u.hp = mini(u.max_hp, u.hp + c.selfheal)
		float_text(u, "+%d HP" % c.selfheal, Color("62d26f"))
		Sfx.play("heal", -4)
	await wait(16)

func heal_amount(u: Unit, c: Dictionary) -> int:
	var h: int = c.heal
	if u.def.key == "hex":
		h += 3
	if u.perk("triage"):
		h += 4
	if u.s.get("trait", "") == "corpsman":
		h += 3
	return h + int(u.g("heal"))

func _act_ally(u: Unit, idx: int, c: Dictionary, tg: Unit) -> void:
	if c.get("handoff", false):
		await spec_kits._act_handoff(u, idx, c, tg)
		return
	spend_card(u, idx, c)
	if c.get("switch", false):
		await spec_kits.switch_places(u, tg)
	if c.get("guard", false):
		await spec_kits.rex_guard(u, tg)
		u.fl["guarded"] = tg
	if c.has("orders"):
		var en: int = c.orders + (1 if u.perk("command") else 0)
		tg.energy += en
		draw_cards(tg, 1)
		float_text(tg, "ORDERS: +%d ENERGY" % en, Color("ffb23e"), true)
		Sfx.play("select")
	if c.has("plate"):
		tg.armor += c.plate
		float_text(tg, "+%d ARMOR" % c.plate, Color("9fb4c9"), true)
		sparks(tg.x, tg.y - tg.h / 2.0, 6)
		Sfx.play("ping")
	if c.has("adrshot"):
		gain_adr(tg, c.adrshot)
		float_text(tg, "+%d ADRENALINE" % c.adrshot, Color("ff7a3d"), true)
		Sfx.play("power")
	if c.has("heal"):
		var h := heal_amount(u, c)
		var before := tg.hp
		var over := maxi(0, tg.hp + h - tg.max_hp)
		tg.hp = mini(tg.max_hp, tg.hp + h)
		u.fl["healed"] = true
		if over > 0 and u.perk("redline"):
			gain_adr(tg, over * 4)
		if over > 0 and u.perk("hardplates"):
			tg.armor += over
			float_text(tg, "+%d ARMOR" % over, Color("9fb4c9"))
		if ks(u, "medrig"):
			u.armor += h
		if c.get("medenergy", 0) > 0:
			tg.energy += c.medenergy
		if u.perk("badbatch"):
			for o2 in units:
				if o2.team == "enemy" and not o2.dead and absf(o2.x - tg.x) < 90 and absf(o2.y - tg.y) < 60:
					add_status(o2, "toxic", 2, u)
		float_text(tg, "+%d HP" % h, Color("62d26f"), true)
		Sfx.play("heal", -4)
		Sfx.play("coin")
		give_xp(u, maxi(1, (tg.hp - before) / 3))
		if u.perk("pumpup"):
			gain_adr(tg, 20)
		for i in 8:
			part({"x": tg.x + randf_range(-8, 8), "y": tg.y - randf_range(0, 30), "vx": 0.0, "vy": -randf_range(0.5, 1.2), "life": 40, "max": 40, "c": Color("62d26f"), "s": 2.0, "g": 0.0, "plus": true})
	if c.has("energy"):
		tg.energy += c.energy
		float_text(tg, "+1 ENERGY", Color("ffb23e"))
		if not u.perk("seconddose"):
			tg.hp = maxi(1, tg.hp - 3)
		if u.def.key == "hex":
			tg.fl["juiced"] = true
		gain_adr(tg, 15)
		Sfx.play("select")
	await wait(20)

func play_self(idx: int) -> void:
	var u := sel
	var inst: Dictionary = u.hand[idx]
	var c := Data.card(inst)
	if u.energy < card_cost(u, inst) or busy:
		return
	var why := vehicle_ops.mech_ok(u, c)
	if why == "" and self_no_target(u, c):
		why = "NO JACKAL IN RANGE"  # SELF cards fire on the hotkey, so one with nothing to hit stays in hand
	if why != "":
		float_text(u, why, Color("ff7a3d"))
		Sfx.play("deny")
		return
	resolve(func(): await _act_self(u, idx, c))

func self_no_target(u: Unit, c: Dictionary) -> bool:
	## A Tesla Arc, drone run or Slingshot with no enemy it could reach would only waste the card.
	var chest := Vector2(u.x, u.y - u.h / 2.0)
	if c.has("tesla"):
		return not spec_kits.vis_foes().any(func(e): return chest.distance_to(Vector2(e.x, e.y - e.h / 2.0)) <= 300.0)
	if c.has("drone"):
		var reach := 2000.0 if c.get("od", false) else 420.0
		return not spec_kits.vis_foes().any(func(e): return absf(e.x - u.x) <= reach)
	if c.get("slingshot", false):
		return spec_kits.squad_of("rook") == null or not spec_kits.vis_foes().any(func(e): return not e.heavy)
	return false

func _act_self(u: Unit, idx: int, c: Dictionary) -> void:
	spend_card(u, idx, c)
	if c.has("draw"):
		draw_cards(u, c.draw)
		float_text(u, "DRAW %d" % c.draw, Color("53d4e2"))
	if c.has("breath"):
		u.fl["breath"] = c.breath
		float_text(u, "HOLDING BREATH", Color("53d4e2"))
	if c.get("taunt", false):
		taunter = u
		u.fl["taunted"] = true
		float_text(u, "COME ON THEN!", Color("ff7a3d"), true)
		bark(u, "Over here, Jackals!")
	if c.get("blight", false):
		for o2 in units:
			if o2.team == "enemy" and not o2.dead and o2.x > cam_x - 20 and o2.x < cam_x + W + 20:
				add_status(o2, "toxic", 3, u)
		Sfx.play("splash")
	if c.has("triage"):
		for s in squad_alive():
			if absf(s.x - u.x) <= c.range:
				s.hp = mini(s.max_hp, s.hp + c.triage)
				s.st = {}
				float_text(s, "+%d HP" % c.triage, Color("62d26f"), true)
				Sfx.play("heal", -4)
	if c.get("immovable", false):
		u.immovable = true
		u.heavy = true
	if c.has("ownet"):
		for s in squad_alive():
			s.overwatch += c.ownet
			float_text(s, "OVERWATCH +%d" % c.ownet, Color("53d4e2"))
	if c.get("slug", false):
		vtech.call_slug(u)
		if c.has("slugturns"):
			units.back().loot.turns = maxi(units.back().loot.turns, c.slugturns)
	if c.has("squadarmor"):
		for s in squad_alive():
			s.armor += c.squadarmor
			float_text(s, "+%d ARMOR" % c.squadarmor, Color("9fb4c9"))
	if c.get("patch", false):
		vehicle_ops.patch_job(u)
	if c.get("sync", false):
		banner("SYNCHRONIZE!", Color("53d4e2"))
		for s in squad_alive():
			s.fl["syncfree"] = true
			float_text(s, "NEXT CARD FREE", Color("53d4e2"))
	if c.get("clacker", false):
		await spec_kits.clacker(u)
	if c.get("ridealong", false):
		await vehicle_ops.ride_along(u)
	if c.has("refit"):
		vehicle_ops.field_refit(u, c.refit)
	if c.has("blink"):
		await vtech.vharr_blink(u, c.blink)
		if u.perk("decoy"):
			add_status(u, "cloak", 2, u)
		if u.perk("blinkstrike"):
			var fs2 := spec_kits.vis_foes()
			fs2.sort_custom(func(a, b2): return absf(a.x - u.x) < absf(b2.x - u.x))
			if fs2.size() and absf(fs2[0].x - u.x) < 60:
				damage(fs2[0], 8, u, {"melee": true})
				u.attacked = true
	if c.has("gwell"):
		await vtech.vharr_well(u, c.gwell + (40.0 if u.perk("widewell") else 0.0))
		if u.perk("doublewell"):
			await vtech.vharr_well(u, c.gwell + (40.0 if u.perk("widewell") else 0.0))
	if c.has("domes"):
		for s in squad_alive():
			if s == u or absf(s.x - u.x) <= c.drange + (80.0 if u.perk("domeshare") else 0.0):
				s.dome = maxi(s.dome, c.domes)
				float_text(s, "DOME", Color("9df25c"))
		Sfx.play("power")
	if c.has("armor"):
		u.armor += c.armor
		float_text(u, "+%d ARMOR" % c.armor, Color("9fb4c9"))
		Sfx.play("select")
	if c.has("move"):
		if vfx != null:
			vfx.dash(u).stop_at = 0.15
		u.move_left += c.move
		float_text(u, "+%s MOVE" % Data.meters(c.move), Color("b48cff"))
		Sfx.play("select")
	if c.get("overwatch", false):
		u.overwatch = c.get("ow", 1) * (2 if u.perk("sentinel") else 1)
		float_text(u, "OVERWATCH", Color("53d4e2"))
		Sfx.play("select")
	if c.has("adrenal"):
		u.hp = maxi(1, u.hp - c.selfdmg)
		float_text(u, "-%d" % c.selfdmg, Color("ff4d3d"))
		gain_adr(u, c.adrenal)
		Sfx.play("power")
	if c.has("rally"):
		Sfx.play("power")
		bark(u, "ON ME! MOVE MOVE!")
		for s in squad_alive():
			if absf(s.x - u.x) <= c.range:
				s.move_left += c.rally
				gain_adr(s, 10)
				float_text(s, "+%s MOVE" % Data.meters(c.rally), Color("b48cff"))
	if c.has("fortify"):
		await spec_kits.fortify(u, c)
	if c.has("nest"):
		for k in c.nest:
			var sx: float = u.x + (k - (c.nest - 1) / 2.0) * 30.0
			var sy = T.stand_y(sx, u.y - 40)
			if sy != null:
				spec_kits.make_sentry(u, sx, sy, 16, [5, 6])
		Sfx.play("power")
	if c.get("whistle", false):
		var rx := spec_kits.rex_ready(u)
		if rx != null:
			Sfx.play("select")
			float_text(u, "HERE, BOY!", Color("e8dcc2"))
			await spec_kits.heel(u, rx)
		if u.fl.get("goodboy", false):
			u.fl.erase("goodboy")
			u.energy += 1
			float_text(u, "+1 ENERGY", Color("ffb23e"))
		draw_cards(u, 2 if u.perk("huntcall") else 1)
	if c.has("hounds"):
		await spec_kits.release_hounds(u, c, c.hounds)
	if c.get("supplyrun", false):
		await spec_kits.supply_run(u)
	if c.has("meddog"):
		banner("MED DOG!", Color("62d26f"))
		Sfx.play("coin")
		for s in squad_alive():
			s.hp = mini(s.max_hp, s.hp + c.meddog)
			s.energy += 1
			float_text(s, "+%d HP" % c.meddog, Color("62d26f"), true)
			Sfx.play("heal", -4)
	if c.has("hmark"):
		for s in squad_alive():
			if s.def.key == "moss":
				s.hand.append({"id": -2, "key": "snipe", "tier": Data.base_tier("snipe"), "temp": true, "free": true})
				float_text(s, "FREE LONG SHOT", Color("53d4e2"), true)
	if c.has("squadenergy"):
		for s in squad_alive():
			s.energy += c.squadenergy
			float_text(s, "+%d ENERGY" % c.squadenergy, Color("ffb23e"))
	if c.has("drone"):
		await spec_kits.drone_runs(u, c)
	if c.get("rigged", false):
		await spec_kits.rig_all(u)
	if c.get("paint", false):
		for e in spec_kits.vis_foes():
			add_status(e, "flared", 2, u)
		var ms = spec_kits.squad_of("moss")
		if ms != null:
			spec_kits.temp_card(ms, "snipe")
			float_text(ms, "FREE LONG SHOT", Color("53d4e2"), true)
	if c.has("deflect"):
		u.fl["deflect"] = u.fl.get("deflect", 0) + c.deflect * (2 if u.perk("doubledeflect") else 1)
		float_text(u, "DEFLECT", Color("e0f4ff"), true)
		Sfx.play("ping")
	if c.get("vanish", false):
		add_status(u, "cloak", 2, u)
		for k in 8:
			puff(u.x + randf_range(-12, 12), u.y - randf_range(0, 30), 2.0)
	if c.has("freekatana"):
		for k in c.freekatana:
			spec_kits.temp_card(u, "katana")
	if c.has("freejump"):
		for k in c.freejump:
			spec_kits.temp_card(u, "walljump")
	if c.get("mirror", false):
		var ms2 = spec_kits.squad_of("moss")
		if ms2 != null:
			spec_kits.temp_card(ms2, "ricochet")
			float_text(ms2, "FREE RICOCHET", Color("53d4e2"), true)
	if c.has("tesla"):
		await spec_kits.tesla_arc(u, c)
	if c.has("shockwave"):
		await spec_kits.shockwave(u, c.shockwave)
	if c.get("delivery", false):
		var vv = spec_kits.squad_of("vee")
		if vv != null:
			for k in 2:
				spec_kits.temp_card(vv, "frag", true, {"nowind": true})
			float_text(vv, "2 FREE FRAGS", Color("53d4e2"), true)
	if c.get("slingshot", false):
		await spec_kits.slingshot(u)
	if c.has("supply"):
		await spec_kits.brass_supply(u, c.supply)
	if c.has("brood"):
		await spec_kits.brood_call(u, c.brood)
	if c.has("hivemind"):
		var fs := spec_kits.vis_foes().filter(func(e): return e.hp <= 30 or u.perk("biglink"))
		fs.sort_custom(func(a, b2): return absf(a.x - u.x) < absf(b2.x - u.x))
		for e in fs.slice(0, c.hivemind):
			spec_kits.mind_link(u, e, 2 if ks(u, "psicrown") else 1)
	if c.get("surge", false):
		Sfx.play("power")
		for s in squad_alive():
			if absf(s.x - u.x) <= c.range:
				s.hp = mini(s.max_hp, s.hp + 10)
				s.energy += 1
				s.move_left += 80
				float_text(s, "SURGE +10", Color("62d26f"), true)
	await wait(14)

func melee_valid(u: Unit, tg, c: Dictionary) -> bool:
	if c.has("mindlink"):
		return spec_kits.can_link(u, tg, c)
	if (c.get("grab", false) or c.get("suplex", false) or c.get("piledrive", false)) and not spec_kits.can_grab(u, tg):
		return false
	return tg != null and not tg.dead and (tg.team == "enemy" or tg.is_prop()) and absf(tg.x - u.x) <= c.range + tg.w / 2.0 and absf(tg.y - u.y) <= 30

func ally_valid(u: Unit, tg, c: Dictionary) -> bool:
	if c.get("guard", false) and spec_kits.rex_ready(u) == null:
		return false
	if (c.get("handoff", false) or c.get("switch", false)) and tg == u:
		return false
	if c.get("switch", false):
		return tg != null and tg.team == "squad" and not tg.dead and absf(tg.x - u.x) <= c.range
	return tg != null and tg.team == "squad" and not tg.dead and absf(tg.x - u.x) <= c.range and absf(tg.y - u.y) <= 80

func ladder_at(p: Vector2):
	for l in T.ladders:
		if absf(p.x - l.x) < 26 and p.y < l.top + 24 and p.y > l.top - 70 and T.solid(l.offx, l.top + 2):
			return l
	return null

func plan_climb(u: Unit, L: Dictionary):
	if absf(u.y - L.top) < 8:
		return null
	var w := phys.sim_walk(u, L.x, u.move_left)
	var ex: float = w.x if w.pts.size() else u.x
	var ey: float = w.y if w.pts.size() else u.y
	if absf(ex - L.x) > 3 or absf(ey - L.bot) > 16:
		return null
	var cost: float = w.used + (ey - L.top) * 0.5 + absf(L.offx - L.x)
	if cost > u.move_left + 0.5:
		return null
	var pts: Array = w.pts.duplicate()
	var y := ey
	while y > L.top:
		pts.append([L.x, y, false, true])
		y -= 2
	var d := signf(L.offx - L.x)
	var x: float = L.x
	while absf(x - L.offx) > 1:
		pts.append([x, L.top, false])
		x += d * 2
	pts.append([L.offx, L.top, false])
	return {"pts": pts, "cost": cost}

func do_climb(u: Unit, L: Dictionary) -> void:
	var pl = plan_climb(u, L)
	if pl == null:
		float_text(u, "CAN'T REACH", Color("ff7a3d"))
		return
	Sfx.play("click")
	walk_snap = walk_snapshot(u)
	resolve(func(): await _act_walk(u, pl.pts, pl.cost))

func do_move(u: Unit, tx: float) -> void:
	var sim := phys.sim_walk(u, tx, u.move_left)
	if sim.pts.is_empty():
		return
	walk_snap = walk_snapshot(u)
	resolve(func(): await _act_walk(u, sim.pts, sim.used))

func walk_print(skip: Unit) -> String:
	## A2: everything a walk could have set off (a camera push, alert, a new log line, any unit
	## spotting, moving, getting hurt or picked up), minus the walker's own position and movement.
	var parts: Array = [int(cam_x), alert, log_lines, Run.scrip, units.size(), T.chunks.size(), stats, pow_queue.size()]
	for o in units:
		if o == skip:
			parts.append([o.hp, o.energy, o.hand.size(), o.overwatch, o.st.keys(), o.dead, o.carry])
		else:
			parts.append([o.dead, o.gone, o.hp, o.active, int(o.x), int(o.y), o.overwatch])
	return str(parts)

func walk_snapshot(u: Unit) -> Dictionary:
	return {"u": u, "x": u.x, "y": u.y, "face": u.face, "move": u.move_left, "moved": u.moved, "print": walk_print(u)}

func quiet_walk(snap: Dictionary) -> bool:
	## A2: the walk can be taken back only if it changed nothing but where the walker stands.
	var u: Unit = snap.u
	return not u.dead and not u.air and u.walk == null and u.move_left < snap.move and walk_print(u) == snap.print

func can_undo() -> bool:
	return state == "player" and not busy and not undo_walk.is_empty()

func undo_last_walk() -> void:
	## A2: back to where the soldier stood before the last walk, with the movement refunded.
	if not can_undo():
		return
	var w := undo_walk
	undo_walk = {}
	var u: Unit = w.u
	u.x = w.x; u.y = w.y; u.face = w.face
	u.move_left = w.move; u.moved = w.moved
	u.vx = 0; u.vy = 0; u.air = false; u.walk = null; u.slide = 0
	refresh_mounts()
	sel = u
	Sfx.play("click")
	float_text(u, "WALK UNDONE", Color("9aa2ae"))
	ui_dirty = true

func _act_walk(u: Unit, pts: Array, cost: float) -> void:
	u.move_left = maxf(0, u.move_left - cost)
	u.moved = true
	coach_left.erase("card")  # the MOVING page explains walking, and they just walked
	coach_hit("walk")
	var x0 := u.x
	await phys.walk_along(u, pts)
	await check_push(u, x0)

# ---------------------------------------------------------------- screen scrolling
func check_push(u: Unit, x0 = null) -> void:
	mid_events.check_troopers(u)
	camp_ops.free_varga()
	await mid_events.check_dealer(u, x0)
	await camp_ops.check_camp(u)
	if pincer.get("on", false):
		camp_ops.set_view(wing(u))
		if wing(u) == "b":
			await camp_ops.follow_b()
			return
	if u.dead or cam_x >= world_w - W:
		return
	if u.x - cam_x > W * 0.72:
		var blk := camp_ops.push_blockers()
		if blk.size():
			# the map only moves on once nothing hostile is left behind the line
			if push_warned != round_n:
				push_warned = round_n
				float_text(u, "CLEAR THE ENEMIES BEHIND FIRST", Color("ff7a5c"), true)
				log_msg("The push zone is locked: %d enem%s still alive behind the line." % [blk.size(), "y" if blk.size() == 1 else "ies"])
			return
		await scroll_to(clampf(u.x - W * 0.5, cam_x, world_w - W), "push", u)

func wing(u) -> String:
	return u.wing

func view_cam(w: String) -> float:
	return cam_tx if pincer.get("view", "a") == w else float(pincer.get(w + "_cam", cam_x))

func in_play(x: float, pad: float) -> bool:
	## Inside a live window. On the pincer op both halves are live: squad A's and squad B's.
	if not pincer.get("on", false):
		return x < cam_x + W + pad
	return x < view_cam("a") + W + pad or x > view_cam("b") - pad

func wing_at(x: float) -> String:
	return "b" if x > view_cam("b") - 60 else "a"

func stall_limit() -> int:
	if in_lesson():
		return 99  # no alert in boot camp
	return STALL_ROUNDS - (1 if Run.threat_on(1) else 0)

func stalled() -> bool:
	## The line has sat on one screen long enough for alert to climb each enemy phase.
	return rounds_since_scroll >= stall_limit()

func scroll_to(tx: float, reason: String, who = null) -> void:
	if pincer.get("on", false) and pincer.view != "a":
		camp_ops.set_view("a")  # only squad A's side of the pincer pushes the screen
		tx = maxf(tx, cam_x)
	tx = clampf(tx, 0, world_w - W)
	if tx <= cam_x + 4:
		return
	cam_tx = tx
	biome_rules.lava_drain()  # V1: any step forward drains the lava, as the volcano's brief says
	if reason == "push":
		banner("AGGRESSIVE PUSH!", Color("ffb23e"), "ALERT -1  +1 ENERGY")
		score += 250
		alert = maxi(0, alert - 1)
		stats.pushes += 1
		for s in squad_alive():
			if s.def.key == "rook" and s.fl.get("supp_n", 0) >= 2 and not s.fl.has("pinned"):
				s.fl["pinned"] = true
				chain(s, "PINNED")
				for s2 in squad_alive():
					s2.energy += 1
			if s.perk("blitz"):
				s.hand.append({"id": -2, "key": "knife", "tier": Data.base_tier("knife"), "temp": true, "free": true})
				float_text(s, "BLITZ: FREE KNIFE", Color("ffd23a"))
		if who != null and not who.dead:
			who.energy += 1
			float_text(who, "+1 ENERGY", Color("ffb23e"))
			give_xp(who, 3)
			if who.g("push_draw") > 0:
				draw_cards(who, int(who.g("push_draw")))
	else:
		banner("GO!  >>>", Color("62d26f"))
	Sfx.play("start")
	rounds_since_scroll = 0
	await until(func(): return absf(cam_x - cam_tx) < 0.5)
	cam_x = cam_tx
	if pincer.get("on", false) and cam_x + W * 0.6 >= float(pincer.b_cam):
		camp_ops.pincer_meet()
	camp_ops.sweep_loot(cam_x)
	camp_ops.roll_flare()
	camp_ops.activate_enemies()
	await until(settled)
	if reason == "push" and who != null and not who.dead and state == "player":
		await camp_ops.fall_in(who)
	ui_dirty = true

# ---------------------------------------------------------------- N1/N5: new-player tips
const COACH := {
	# P1: each page waits for the moment it is about, instead of five pages before the first shot
	"start": ["TIP", "YOUR TURN", "Each soldier has 3 ENERGY a turn. Cards cost energy (the yellow number). Click a card, aim with the mouse, click to fire. Right-click cancels."],
	"card": ["TIP", "MOVING", "Click the ground to walk the selected soldier. The MOVE gauge beside the hand shows how far they can still go. Click a soldier or their plate to switch."],
	"walk": ["TIP", "NEXT AND END TURN", "NEXT (SPACE) jumps to the next soldier who can still act. END TURN (ENTER) ends the round for the whole squad; it asks twice while someone can still act."],
	"end": ["TIP", "THE ENEMY TURN", "After you end the turn, every enemy moves and then shoots. The ALERT bar up top climbs while you stall, and a full bar calls in airstrikes. Push right: ending a turn in the PUSH ZONE scrolls on and cuts the alert."],
	"blast": ["TIP", "PHYSICS HURTS", "Blasts throw bodies around. Falls, slams and crushing debris do damage, to your squad too. Hold ALT any time to see each soldier's energy, movement and adrenaline on their plate, bottom left."],
}
var coach_left := {}  # P1: coach pages not shown yet, by the moment that shows them

func coach_start() -> void:
	coach_left = COACH.duplicate()
	coach_hit("start")

func coach_hit(key: String) -> void:
	## P1: queues the coach page for this moment the first time it happens; the box opens on the next quiet player turn.
	if hud == null or not coach_left.has(key):
		return
	hud.coach_queue.append(coach_left[key])
	coach_left.erase(key)

const INTROS := {
	"jackal": ["JKL", "THE JACKALS", "Mercenaries holding the gate worlds: riflemen, grenadiers, gun nests and radiomen who call in paratroopers. Knock them off ledges or bring the scenery down on them."],
	"vharr": ["VHR", "THE VHARR", "Aliens coming through the gates. They don't fight like the Jackals: some hover, some burrow. Where both factions are on the map they shoot each other too, so let them."],
	"boar": ["BOAR", "THE IRON BOAR", "The Jackals' war machine. Bullets barely scratch it until its armor plate cracks, and crushing cracks it: drop towers, crates or debris on it, then shoot."],
}

func meet(e: Unit) -> void:
	## N5: the first time a faction (or the Boar) shows up, the coach introduces it once, for good.
	if hud == null or not Run.tips_on() or (in_lesson() and not lesson().get("live", false)):
		return
	var key := "boar" if e.type == "boss" else faction(e)
	if not INTROS.has(key):
		return
	var met: Array = Run.meta.get("met", [])
	if met.has(key):
		return
	met.append(key)
	Run.meta["met"] = met
	if not Run.campaign():
		Run.save_meta()  # mid-op a campaign save would write a half-fought op; the next HQ save keeps it
	hud.coach_queue.append(INTROS[key])

# ---------------------------------------------------------------- rewards & level-ups
func ask(kind: String, title: String, sub: String, opts: Array, who = null) -> int:
	## Shows a pick-one modal on the HUD and waits for the answer (-1 = skip).
	if autopick >= 0 or hud == null:
		return mini(autopick if autopick >= 0 else 0, opts.size() - 1)
	if kind == "camp_up":
		return await hud.pick_grid(kind, title, sub, opts, who)
	return await hud.pick(kind, title, sub, opts, who)

func supply_drop(title: String, for_unit) -> void:
	var alive := squad_alive()
	if alive.is_empty():
		return
	if defer_rewards():
		drop_queue.append([title, for_unit])
		float_at(cam_x + W / 2.0, 150, "SUPPLY DROP WAITS FOR END TURN", Color("ffd23a"))
		ui_dirty = true
		return
	var pool: Array = Data.offer_keys(Run.squad_classes() if for_unit == null else [for_unit.def.key])
	pool.shuffle()
	var opts: Array = []
	for i in 3:
		var o: Dictionary
		if i == 2 and randf() < 0.35:
			var it := Run.roll_item()
			o = Run.item_opt(it, "")
		else:
			o = {"kind": "card", "key": pool[i], "tier": Run.roll_card_tier(pool[i])}
		if for_unit != null:
			o["u"] = for_unit
		opts.append(o)
	var sub := ("%s freed them. Pick one card for %s's deck." % [for_unit.def.name, for_unit.def.name]) if for_unit != null else "Pick one, then pick who gets it."
	var ch := await ask("supply", title, sub, opts)
	if ch >= 0 and not opts[ch].has("u"):
		# you choose who gets it, never the dice
		var o0: Dictionary = opts[ch]
		# a class card (Whistle, Vulcan) only goes to a soldier of that class
		var cls: Array = Data.card_classes(o0.key) if o0.kind == "card" else []
		var who: Array = alive.filter(func(s): return cls.is_empty() or cls.has(s.def.key))
		# D7: one tile per soldier (figure, name, HP, deck) instead of the same card four times
		var who_opts: Array = who.map(func(s): return {"kind": "service", "title": s.def.cls.to_upper(), "name": s.def.name,
			"text": "HP %d/%d. Level %d, %d cards in the deck." % [s.hp, s.max_hp, s.s.lvl, s.s.deck.size()], "soldier": s.s})  # Q6: the name shows once, under the figure
		var thing: String = Data.item_name(o0.item) if o0.kind == "item" else Data.card(o0).name
		var w := await ask("supply_who", "WHO GETS %s?" % thing.to_upper(), "It goes into that soldier's draw pile." if o0.kind == "card" else "They get the chance to equip it.", who_opts)
		if w < 0:
			ch = -1  # skipping the second pick passes on the drop, like skipping the first
		else:
			opts[ch] = o0.merged({"u": who[w]})
	if ch >= 0 and opts[ch].kind == "item":
		await offer_item(opts[ch].u, opts[ch].item)
	elif ch >= 0:
		var o: Dictionary = opts[ch]
		var inst := Run.new_card(o.key, o.tier, "drop")
		o.u.s.deck.append(inst)
		o.u.draw.insert(ri(0, o.u.draw.size()), inst)
		log_msg("%s added to %s's deck." % [Data.CARDS[o.key].name, o.u.def.name])
		Sfx.play("coin")
	ui_dirty = true

func level_up(u: Unit) -> void:
	if u.dead:
		return
	# several levels from one blast queue up: name each step and say how many are left
	var left: int = lvl_queue.count(u)
	var shown: int = u.s.lvl - left
	banner("LEVEL UP!", Color("ffd23a"), "%s IS NOW LEVEL %d" % [u.def.name, shown])
	bark(u, pick(Data.BARKS.lvl))
	var opts := Run.level_options(u.s)
	var picks := 1
	if Run.extra_picks > 0:
		Run.extra_picks -= 1
		picks = 2
	while picks > 0 and opts.size():
		var more := "  %d more level-up%s after this one." % [left, "s" if left > 1 else ""] if left > 0 else ""
		var ch := await ask("level", "%s  LEVEL %d" % [u.def.name, shown], "Pick %s: a new card, a stat boost or an ability.%s" % ["two" if picks > 1 else "one", more], opts, u)
		if ch == -2 and Run.lvl_rerolls > 0:
			Run.lvl_rerolls -= 1
			opts = Run.level_options(u.s)
			continue
		if ch <= -100 and Run.banishes > 0:
			# banished options never show up for this soldier again this run
			var bo: Dictionary = opts[-100 - ch]
			if not Run.banished.has(u.s.key):
				Run.banished[u.s.key] = []
			Run.banished[u.s.key].append(bo.get("key", bo.get("id", "")))
			Run.banishes -= 1
			log_msg("%s banished from %s's pool." % [bo.get("name", Data.CARDS.get(bo.get("key", ""), {}).get("name", "?")), u.def.name])
			opts = Run.level_options(u.s)
			continue
		if ch < 0:
			give_scrip(15, u.x, u.y - u.h - 20, "L7152")
			return
		var o: Dictionary = opts[ch]
		opts.remove_at(ch)
		picks -= 1
		apply_level_option(u, o)

func apply_level_option(u: Unit, o: Dictionary) -> void:
	var line := Run.apply_option(u.s, o)
	if o.kind == "card":
		u.draw.insert(ri(0, u.draw.size()), u.s.deck[-1])
	elif o.kind == "stat":
		match o.id:
			"hp":
				u.max_hp = Run.eff_max_hp(u.s)
				u.hp = mini(u.max_hp, u.hp + Run.STAT_TIERS.hp[o.tier])
			"move":
				u.move_left += Run.STAT_TIERS.move[o.tier]
			"dodge":
				u.dodge = u.def.dodge + u.s.bonus.dodge
	elif o.kind == "perk":
		if o.id == "secondwind":
			u.second_wind = true
		if u.s.get("prestige", "") != "" and Data.PRESTIGE.get(u.s.prestige, "") != "" and line.contains(" is now a "):
			u.max_hp = Run.eff_max_hp(u.s)
			u.dodge = u.def.dodge + u.s.bonus.dodge
			banner("PRESTIGE!", Color("ffd23a"), "%s IS NOW A %s" % [u.def.name, Run.title_of(u.s).to_upper()])
	log_msg(line)
	Sfx.play("power")
	ui_dirty = true

func defer_rewards() -> bool:
	## X3: level-ups, item finds and supply drops earned on the player's turn wait for END TURN
	return state == "player" and not flushing and not tutorial() and not won and not lost

func pending_rewards(u = null) -> int:
	if u == null:
		return lvl_queue.size() + loot_queue.size() + drop_queue.size()
	return lvl_queue.count(u) + loot_queue.filter(func(q): return q.u == u).size()

func flush_rewards() -> void:
	## X3: hand out everything the turn earned, item finds first, then supply drops, then level-ups
	if flushing:
		return
	flushing = true
	while loot_queue.size():
		var lq: Dictionary = loot_queue.pop_front()
		if lq.u.dead:
			Run.add_loot(lq.item)
			continue
		await offer_item(lq.u, lq.item)
	while drop_queue.size():
		var dq: Array = drop_queue.pop_front()
		await supply_drop(dq[0], null if dq[1] == null or dq[1].dead else dq[1])
	while lvl_queue.size():
		var u: Unit = lvl_queue.pop_front()
		await wait(20)
		await level_up(u)
	flushing = false
	ui_dirty = true

func post_action() -> void:
	refresh_mounts()
	await vehicle_ops.leg_check()
	var front: Array = squad_alive().filter(func(s): return not s.air and not s.trapped)
	front.sort_custom(func(a, b): return a.x > b.x)
	if front.size() and not boss_dead:
		await check_push(front[0])
	while pow_queue.size():
		var q: Dictionary = pow_queue.pop_front()
		if q.pow.detour and q.pow.pow_name == "THE DESERTER":
			continue  # the Strange Signal deserter pays out in check_detour
		if q.pow.fl.get("defector", false):
			vharr_ai.sign_defector(q.pow)
			give_xp(q.u, 8)
			continue
		if q.pow.fl.has("specialist"):
			await free_specialist(q)
			continue
		banner("POW RESCUED!", Color("62d26f"), "+500  +25$")
		score += 500
		stats.pows += 1
		give_scrip(25, q.pow.x, q.pow.y - 50, "L7202")
		give_xp(q.u, 8)
		Sfx.play("coin")
		drop_loot(q.pow.x, q.pow.y - 20, {"type": "item", "item": Run.roll_item(1)})
		var sp: Dictionary = Data.POW_SPECIAL.get(q.pow.pow_name, {})
		match sp.get("id", ""):
			"quartermaster":
				Run.discount = 0.2
			"gunsmith":
				Run.reroll_tokens += 1
			"medic":
				for s in squad_alive():
					s.hp = mini(s.max_hp, s.hp + 6)
					float_text(s, "+6 HP", Color("62d26f"))
			_:
				Run.luck += 1
		Run.lvl_rerolls += 1
		log_msg("%s: %s" % [q.pow.pow_name, sp.get("text", "LUCK +1. Your loot just got better.")])
		await wait(40)
		if not q.pow.detour:
			await supply_drop("%s says thanks" % q.pow.pow_name, null if q.u.dead else q.u)
	await camp_ops.check_detour()
	while para_queue.size():
		await camp_ops.call_reinforcements(para_queue.pop_front())
	if not defer_rewards() or squad_alive().is_empty() or boss_dead:
		await flush_rewards()
	refresh_duos()
	if squad_alive().is_empty():
		game_over()
		return
	if boss_dead:
		await until(settled)
		victory()
		return
	if mission.get("outpost", false) and not units.any(func(e): return e.team == "enemy" and not e.dead):
		await until(settled)
		await flush_rewards()
		victory()
		return
	if await camp_ops.job_ends():
		return
	camp_ops.start_hold()
	if tutorial() and tut_step >= TUT_FIGHT and not units.any(func(e): return e.team == "enemy" and not e.dead):
		await until(settled)
		victory()
		return
	if in_lesson():
		return  # lessons end through lesson_update: no wave clears, drops or scrolling
	var active := units.filter(func(e): return e.team == "enemy" and not e.dead and e.active)
	if active.is_empty() and (not tutorial() or tut_step >= TUT_FIGHT):
		var rest := units.filter(func(e): return e.team == "enemy" and not e.dead)
		if rest.size():
			banner("WAVE CLEAR!", Color("62d26f"), "+300  +15$")
			score += 300
			give_scrip(15, cam_x + W / 2.0, 200, "L7261")
			Sfx.play("coin")
			if Run.has_gear("rations"):
				var rh := 4 + 2 * Run.relic_tier("rations")
				for s in squad_alive():
					s.hp = mini(s.max_hp, s.hp + rh)
					float_text(s, "+%d HP" % rh, Color("62d26f"))
					Sfx.play("heal", -4)
			await wait(60)
			await supply_drop("Supply drop", null)
			var nx: float = rest.map(func(e): return e.x).min()
			await scroll_to(clampf(nx - W * 0.7, cam_x, world_w - W), "clear")
			if not units.any(func(e): return e.team == "enemy" and not e.dead and e.active):
				var n2: float = units.filter(func(e): return e.team == "enemy" and not e.dead).map(func(e): return e.x).min()
				await scroll_to(n2 - W * 0.6, "clear")

# ---------------------------------------------------------------- turns
func refresh_duos() -> void:
	## C4: two soldiers with Overdrive ready within 120px get a duo card; all four call the Slug.
	## Duo cards come and go as soldiers move.
	var sq := squad_alive()
	var ready := func(u: Unit) -> bool: return u.hand.any(func(c): return c.get("od", false) and not c.has("duo") and not c.get("temp", false))
	var want := {}
	for d in Data.DUOS:
		var a = null
		var b2 = null
		for u in sq:
			if u.def.key == d.pair[0]:
				a = u
			elif u.def.key == d.pair[1]:
				b2 = u
		if a == null or b2 == null or absf(a.x - b2.x) > Data.DUO_RANGE:
			continue
		var ra: bool = ready.call(a)
		var rb: bool = ready.call(b2)
		var oc := ks(a, "overcharger") or ks(b2, "overcharger")
		if (ra and rb) or (oc and (ra or rb)):
			var holder: Unit = a if a.def.key == d.holder else b2
			want[holder.id] = want.get(holder.id, []) + [[d.card, (b2 if holder == a else a).def.key]]
	if sq.size() == 4 and sq.all(func(u): return ready.call(u)):
		want[sq[0].id] = want.get(sq[0].id, []) + [["slugcall", "squad"]]
	for u in sq:
		var keep: Array = want.get(u.id, [])
		u.hand = u.hand.filter(func(c): return not c.has("duo") or keep.any(func(k): return k[0] == c.key and k[1] == c.duo))
		for k in keep:
			if not u.hand.any(func(c): return c.has("duo") and c.key == k[0]):
				u.hand.append({"id": -3, "key": k[0], "tier": Data.OD_TIER, "od": true, "duo": k[1]})
				float_text(u, "DUO: " + Data.CARDS[k[0]].name.to_upper(), Color("ffb23e"), true)
	ui_dirty = true

func capture_relay(r: Unit, s: Unit) -> void:
	r.loot.taken = true
	var bf: Dictionary = Data.RELAY_BUFFS[r.loot.buff]
	match r.loot.buff:
		"hand":
			relay_hand += 1
		"luck":
			Run.temp_luck += 2
		"intel":
			relay_intel = true
	r.loot.hold = 1
	alert = mini(10, alert + 1)
	banner("RELAY CAPTURED: " + bf.name, Color("53d4e2"), bf.text.to_upper() + "  ALERT +1")
	Sfx.play("power")
	give_xp(s, 4)
	log_msg("%s captured a radio relay: %s Alert +1." % [s.def.name, bf.text])

func hold_relay(r: Unit, s: Unit) -> void:
	## O4: every extra turn ended on a captured relay pays +1 Luck; the third locks it and doubles its buff.
	r.loot.hold += 1
	give_xp(s, 4)
	if r.loot.hold < Data.RELAY_HOLD:
		Run.temp_luck += 1
		float_text(r, "HOLDING %d/%d: +1 LUCK" % [r.loot.hold, Data.RELAY_HOLD], Color("53d4e2"), true)
		return
	match r.loot.buff:
		"hand":
			relay_hand += 1
		"luck":
			Run.temp_luck += 2
		"intel":
			Run.temp_luck += 2
	var bf: Dictionary = Data.RELAY_BUFFS[r.loot.buff]
	banner("RELAY LOCKED: " + bf.name + " x2", Color("53d4e2"), "HELD FOR %d TURNS" % Data.RELAY_HOLD)
	Sfx.play("levelup")
	log_msg("%s held the relay for %d turns: its buff doubles." % [s.def.name, Data.RELAY_HOLD])

func job() -> String:
	return mission.get("job", "push")

# ---------------------------------------------------------------- the player turn: hands, Overdrive, jump pads, ending the turn
func consume_od(u: Unit) -> void:
	for i in u.hand.size():
		var c: Dictionary = u.hand[i]
		if c.get("od", false) and not c.has("duo") and not c.get("temp", false):
			u.hand.remove_at(i)
			break
	u.adr = 0

func draw_cards(u: Unit, n: int) -> void:
	Sfx.play("draw", -12)
	for i in n:
		if u.draw.is_empty():
			u.draw = u.disc
			u.draw.shuffle()
			u.disc = []
		if u.draw.is_empty():
			break
		u.hand.append(u.draw.pop_back())

const BANK_MAX := 1  # C3: unspent energy carried into the next turn

func stow_hand(s: Unit) -> void:
	for c in s.hand:
		if not c.get("od", false) and not c.get("temp", false):
			s.disc.append(c)
	s.hand = s.hand.filter(func(c): return c.get("od", false) or c.get("temp", false))

func hand_size(s: Unit) -> int:
	return maxi(2, 4 + s.s.bonus.hand + (1 if s.perk("fieldkit") else 0) + (1 if Run.implanted(s.s, "thirdarm") else 0) + relay_hand - (1 if Run.threat_on(3) else 0) + (1 if Run.has_gear("ammodrone") else 0) + (1 if round_n == 1 and Run.relic_tier("ammodrone") >= 3 else 0))

func start_player_turn() -> void:
	Sfx.play("turn", -8)
	Music.boss_check(self)
	mid_events.troopers_follow()
	camp_ops.free_varga()
	round_n += 1
	stats.rounds = round_n
	wind = int(round(ri(-6, 6) * rules.get("wind", 1.0)))
	combo = 0
	for s in squad_alive():
		s.energy = 3 + s.banked
		s.banked = 0
		if round_n == 1:
			s.energy += s.s.bonus.energy1 + int(s.g("energy1")) + (1 if Run.has_gear("bandolier") else 0) + (1 if Run.campaign() and Run.buddy_deployed(s.s) else 0)
		elif round_n == 2 and Run.relic_tier("bandolier") >= 3:
			s.energy += 1
		if Run.has_gear("overclock") and (round_n % 2 == 1 or Run.relic_tier("overclock") >= 3):
			s.energy += 1
		s.move_left = 0.0 if s.has_st("pinned") else full_move(s)
		if s.has_st("pinned"):
			float_text(s, "PINNED", Color("ff7a3d"), true)
		s.moved = false
		s.attacked = false
		s.aim_discount = false
		s.kill_drawn = false
		s.played = 0
		s.seq = []
		s.fl = {}
		if s.immovable:
			s.immovable = false
			s.heavy = false
		if s.perk("payback") and s.armor > 0:
			s.payback = s.armor
		s.armor = (3 if s.perk("ironhide") else 0) + int(s.g("armor_turn"))
		if walls.size() and squad_alive().any(func(o): return o.perk("hunker")) and walls.any(func(r): return r.grow(16).has_point(Vector2(s.x, s.y - 8))):
			s.armor += 4
			float_text(s, "HUNKER +4", Color("9fb4c9"))
		if s.g("regen") > 0 and s.hp < s.max_hp:
			var rg := mini(int(s.g("regen")), s.max_hp - s.hp)
			s.hp += rg
			float_text(s, "+%d HP" % rg, Color("62d26f"))
			Sfx.play("heal", -4)
		s.overwatch = 0
		s.dragged = false
		if s.fuel_max > 0 and not s.air:
			s.fuel = 0 if s.carry == "colors" else s.fuel_max
		stow_hand(s)
		draw_cards(s, hand_size(s) + (1 if round_n == 1 and Run.campaign() and Run.hq("comms") >= 3 else 0))
		if not s.hand.any(func(c): return c.key == "hop"):
			s.hand.append({"id": -4, "key": "hop", "tier": Data.base_tier("hop"), "temp": true})
		give_sidearm(s)
		if s.bow and not s.hand.any(func(c): return c.key == "rambobow"):
			s.hand.append({"id": -6, "key": "rambobow", "tier": Data.base_tier("rambobow"), "temp": true})
		if s.adr >= 100 and not s.hand.any(func(c): return c.get("od", false) and not c.has("duo")):
			grant_overdrive(s)
	refresh_duos()
	refresh_mounts()
	vehicle_ops.vehicles_new_turn()
	spec_kits.classes_new_turn()
	for s in squad_alive():
		if s.perk("switcheroo") and not s.hand.any(func(h): return h.key == "switch"):
			s.hand.append({"id": -9, "key": "switch", "tier": Data.base_tier("switch"), "temp": true})
		if ks(s, "remotedet") and not s.hand.any(func(h): return h.key == "clacker"):
			s.hand.append({"id": -9, "key": "clacker", "tier": Data.base_tier("clacker"), "temp": true})
	var al0 := squad_alive()
	if round_n == 1:
		for s in al0:
			if s.s.get("trait", "") == "hunter":
				gain_adr(s, 25)
		for s in al0:
			if s.perk("motorpool"):
				s.hand.append({"id": -3, "key": "slugcall", "tier": Data.OD_TIER, "temp": true})
	if round_n == 1 and Run.campaign() and Run.hq("hangar") >= 1 and al0.size():
		# B4 Hangar: the Slug rolls out with the squad
		vtech.call_slug(al0[0])
		units.back().loot.turns += 2 if Run.hq("hangar") >= 2 else 1  # the tick below takes one right away
		if Run.hq("hangar") >= 3:
			al0[0].hand.append({"id": -3, "key": "slugcall", "tier": Data.OD_TIER, "temp": true})
	if round_n == 1 and (Run.trophies.size() >= 3 or Run.hq("motor") >= 1) and not slug_given and al0.size():
		# L7: three Boar parts rebuilt the SV-001, or the Motor Pool keeps it running. It answers one call
		# per mission, two with Motor Pool 3.
		slug_given = true
		var calls := 2 if Run.hq("motor") >= 3 else 1
		for i in mini(calls, al0.size()):
			al0[i].hand.append({"id": -3 - i * 100, "key": "slugcall", "tier": Data.OD_TIER, "temp": true})
		log_msg("The SV-001 Slug is on call this mission. The card is in %s's hand." % " and ".join(al0.slice(0, calls).map(func(x): return x.def.name)))
	for u in units:
		u.hit_sides = {}
		if u.kind == "slug" and not u.gone:
			u.loot.turns -= 1
			if u.loot.turns < 0:
				u.gone = true
				for k in 6:
					puff(u.x + randf_range(-30, 30), u.y - randf_range(0, 40), 2.0)
				float_at(u.x, u.y - 60, "SLUG OUT", Color("62d26f"), true)
	taunter = null
	tick_pads()
	tick_statuses("squad")
	state = "player"
	busy = false
	card_idx = -1
	if sel == null or sel.dead:
		var al := squad_alive()
		sel = al[-1] if al.size() else null
	banner("ROUND %d" % round_n, Color.WHITE, ("WIND %s %d" % [">>" if wind > 0 else "<<", absi(wind)]) if wind else "NO WIND")
	# P3: the round banner and alert bar already say the round and alert; the log only gets news
	if rounds_since_scroll == stall_limit():
		log_msg("The line has stalled: alert rises every round until you push.")
	ui_dirty = true
	if in_lesson():
		boot_camp.lesson_hand()
	var autoload := units.any(func(o): return o.kind == "sentry" and not o.dead and o.loot.by is Unit and o.loot.by.perk("autoloader"))
	resolve(func():
		await spec_kits.dogs_new_turn()
		if autoload:
			await spec_kits.sentries_fire()  # Autoloader: the sentries open the round too
		else:
			await wait(1))

func full_move(s: Unit) -> float:
	## B5: light weapons add movement, heavy ones take some away.
	var mv: float = s.def.spd + s.s.bonus.move + int(s.g("move")) + (60 if s.perk("charge") else 0) + int(s.g("light")) - int(s.g("heavy"))
	if s.mech != null:
		mv += Data.VEHICLES[s.mech.type].move + (60 if s.perk("legservos") else 0)
	return roundf(mv * 0.6) if s.carry == "colors" else mv

func jet_fuel(u: Unit) -> int:
	## Jet Boots fuel; a heavy weapon burns through it a third faster (so there is a third less).
	var f := int(u.g("jet"))
	if u.team == "squad" and u.s.get("trait", "") == "pilot":
		f = int(round(f * 1.5))
	return int(round(f * 0.67)) if u.g("heavy") > 0 else f

func sidearm_key(s: Unit) -> String:
	var i := clampi(int(s.g("sa")), 0, Data.SIDEARMS.size() - 1)
	if Data.SIDEARMS[i] == "sa_law" and s.s.get("law_spent", false):
		i = 0  # the LAW is fired: back to the holdout pistol until the next camp
	return Data.SIDEARMS[i]

func give_sidearm(s: Unit) -> void:
	## B1: a sidearm is always in hand once a turn, outside the deck, like Hop.
	var key := sidearm_key(s)
	s.hand = s.hand.filter(func(c): return not Data.CARDS[c.key].get("sidearm", false) or c.key == key)
	if not s.hand.any(func(c): return c.key == key):
		s.hand.append({"id": -5, "key": key, "tier": Data.base_tier(key), "temp": true})

func m2_near(u: Unit):
	for m in units:
		if m.kind == "m2" and not m.gone and absf(m.x - u.x) < 34 and absf(m.y - u.y) < 30:
			return m
	return null

func refresh_mounts() -> void:
	## B6: a soldier standing at a mounted M2 gets its free card; walking away takes it back.
	for s in squad_alive():
		var m = m2_near(s)
		var ok: bool = m != null and m.loot.sq != round_n
		var has: bool = s.hand.any(func(c): return c.key == "mounted")
		if ok and not has:
			s.hand.append({"id": -6, "key": "mounted", "tier": Data.base_tier("mounted"), "temp": true})
			float_text(s, "ON THE GUN", Color("ffd23a"))
			ui_dirty = true
		elif not ok and has:
			s.hand = s.hand.filter(func(c): return c.key != "mounted")
			ui_dirty = true
	refresh_padbounce()

func on_jump_pad(s: Unit) -> bool:
	## D2: standing on (or right at the edge of) a Jump Pad's rubber.
	if s.air or s.mech != null:
		return false
	for dx in [0.0, -12.0, 12.0]:
		if T.mat(s.x + dx, s.y + 2) == Terrain.RUBBER:
			return true
	return false

func refresh_padbounce() -> void:
	## D2: a soldier on a Jump Pad gets a free Pad Bounce, once a turn, even with no movement left.
	for s in squad_alive():
		var ok: bool = on_jump_pad(s) and not s.fl.get("padbounced", false)
		var has: bool = s.hand.any(func(c): return c.key == "padbounce")
		if ok and not has:
			s.hand.append({"id": -8, "key": "padbounce", "tier": Data.base_tier("padbounce"), "temp": true})
			float_text(s, "ON THE PAD", Color("ffd23a"))
			ui_dirty = true
		elif not ok and has:
			s.hand = s.hand.filter(func(c): return c.key != "padbounce")
			ui_dirty = true

func pad_bonus(p: Unit) -> String:
	return p.loot.seq[p.loot.i % p.loot.seq.size()]

func tick_pads() -> void:
	## Pads on screen count down a round; at zero their bonus appears for anyone to grab.
	for p in pads:
		if p.gone or p.sunk or p.loot.ready or p.x > cam_x + W:
			continue
		p.loot.t -= 1
		if p.loot.t <= 0:
			p.loot.ready = true
			var B: Dictionary = Data.BONUSES[pad_bonus(p)]
			float_at(p.x, p.y - 40, B.name + "!", B.c, true)
			Sfx.play("power", -4)

func check_pads() -> void:
	for p in pads:
		if not p.loot.ready or p.gone or p.sunk:
			continue
		for u in units:
			if u.dead or u.gone or u.sunk or u.air or not (u.kind == "soldier" or u.kind == "enemy") or is_boss(u):
				continue
			if absf(u.x - p.x) < 15 and absf(u.y - p.y) < 20:
				grant_bonus(p, u)
				break

func grant_bonus(p: Unit, u: Unit) -> void:
	var k := pad_bonus(p)
	var B: Dictionary = Data.BONUSES[k]
	p.loot.ready = false
	p.loot.i += 1
	p.loot.t = Data.PAD_RESET
	if k == "medkit":
		var hl := mini(15, u.max_hp - u.hp)
		u.hp += hl
		float_text(u, "+%d HP" % hl, Color("62d26f"))
		Sfx.play("heal", -4)
	elif mid_events.transform_bonus(k, u):
		pass
	elif k == "nadekit":
		# K2: a soldier gets two Frag Grenades that stay in hand until thrown; a Jackal lobs one on its next attack
		if u.team == "squad":
			for i in 2:
				u.hand.append({"id": -2, "key": "frag", "tier": Data.base_tier("frag"), "temp": true})
		else:
			u.st["nades"] = 1
	else:
		u.st[k] = Data.BONUS_TURNS
	float_at(u.x, u.y - u.h - 30, B.name + "!", B.c, true)
	Sfx.play("power")
	part({"x": p.x, "y": p.y - 6, "r": 4.0, "max": 30.0, "ring": true, "life": 16, "c": B.c})
	if u.team == "enemy":
		log_msg("A Jackal grabbed the %s bonus." % B.name)
	else:
		log_msg("%s grabbed the %s bonus." % [u.def.name, B.name])
	ui_dirty = true

func pad_in_reach(e: Unit, budget: float):
	## A ready pad a Jackal can walk to this phase.
	for p in pads:
		if p.loot.ready and not p.gone and absf(p.x - e.x) <= budget and absf(p.y - e.y) < 60:
			return p
	return null

func jammer_rounds() -> int:
	var t := Run.relic_tier("jammer")
	return 0 if t < 0 else (2 if t >= 3 else 1)

func can_act(u: Unit) -> bool:
	## True while a soldier still has something to do: movement left or a card they can pay for.
	if u == null or u.dead or u.team != "squad" or u.trapped:
		return false
	if u.move_left > 1:
		return true
	return u.hand.any(func(c): return card_cost(u, c) <= u.energy)

func ready_count() -> int:
	return squad_alive().filter(can_act).size()

func end_turn(force := false) -> void:
	if state != "player" or busy:
		return
	if coach_left.has("end") and hud != null:
		# Q5: the very first END TURN press opens THE ENEMY TURN tip, before the enemy moves
		coach_hit("end")
		ui_dirty = true
		return
	# first press warns when someone can still act; a second press within ~2.5s ends the turn
	if not force and ready_count() > 0 and end_confirm_t <= 0:
		end_confirm_t = 150
		Sfx.play("tick")
		ui_dirty = true
		return
	end_confirm_t = 0
	if in_lesson() and not lesson().get("live", false) and round_n >= int(lesson().get("turns", 1)):
		boot_camp.lesson_fail("turn")  # a lesson is one turn (or a few): out of turns, go again
		return
	if pending_rewards() > 0:
		# X3: the turn's promotions and finds come out before the enemy moves
		busy = true
		ui_dirty = true
		await flush_rewards()
		busy = false
		if state != "player" or won or lost:
			return
	coach_hit("end")
	for r in units.filter(func(o): return o.kind == "relay" and o.loot.hold < Data.RELAY_HOLD):
		var on = null
		for s in squad_alive():
			if absf(s.x - r.x) < 26 and absf(s.y - r.y) < 30:
				on = s
				break
		if on != null and not r.loot.taken:
			capture_relay(r, on)
		elif on != null:
			hold_relay(r, on)
		elif r.loot.taken:
			r.loot.hold = 99  # walked off: the hold is over, the buff stays
			float_text(r, "HOLD BROKEN", Color("ff7a3d"), true)
	undo_walk = {}
	rummage_armed = false
	for s in squad_alive():
		if s.perk("tracker") and s.energy > 0:
			s.overwatch += s.energy
			float_text(s, "TRACKING +%d" % s.energy, Color("53d4e2"))
			s.energy = 0
		# C3: one unspent energy is banked for next turn
		s.banked = mini(s.energy, BANK_MAX)
		if s.banked > 0:
			float_text(s, "+%d ENERGY BANKED" % s.banked, Color("ffd23a"))
		stow_hand(s)
	card_idx = -1
	drop_all_hangs()
	foe_ai.enemy_phase()

func hunted(u: Unit) -> bool:
	## O1-O3: the flag carrier and the archer are every Jackal's first pick.
	return u.team == "squad" and (u.carry != "" or u.bow)

func nearest_squad(e: Unit):
	if e.fl.has("mind"):
		var bt = null
		for o in foes_of(e):
			if bt == null or absf(o.x - e.x) < absf(bt.x - e.x):
				bt = o
		return bt
	if taunter != null and not taunter.dead and absf(taunter.x - e.x) < 520:
		return taunter
	for s in squad_alive():
		if hunted(s) and absf(s.x - e.x) < 520 and targetable(e, s):
			return s
	var best = null
	for s in foes_of(e):
		if s.team == "squad" and not targetable(e, s):
			continue
		if best == null or absf(s.x - e.x) < absf(best.x - e.x):
			best = s
	return best

func is_boss(u: Unit) -> bool:
	## The level's end boss: the Iron Boar, or the Hive Ship over the delta and the harbor.
	return u.type == "boss" or u.type == "hiveship"

func faction(u: Unit) -> String:
	return Data.ETYPES[u.type].get("faction", "jackal") if u.team == "enemy" else ""

func foes_of(e: Unit) -> Array:
	## Who an enemy fights: your squad, and in a BREACH biome the other faction's active units too.
	## Spawners (Hive Pods, tunnels) stay out of it.
	var out := [] if e.fl.has("mind") else squad_alive()
	if e.team == "enemy":
		for o in units:
			if o.active and not o.dead and not o.gone and not o.sunk and at_war(e, o) and not Data.ETYPES[o.type].get("static", false) and not is_boss(o):
				out.append(o)
	return out

func at_war(a: Unit, b2: Unit) -> bool:
	## Two enemies that fight each other: the two factions in a BREACH, or Jackals that turned on the Vharr (E5).
	if a.team != "enemy" or b2.team != "enemy":
		return false
	if a.fl.has("mind") != b2.fl.has("mind"):
		return true  # N8: Sable's linked Jackals and her brood fight their own side
	if faction(a) == faction(b2):
		return false
	return breach or a.fl.get("turned", false) or b2.fl.get("turned", false)

# ---------------------------------------------------------------- end states
func game_over() -> void:
	if in_lesson():
		boot_camp.lesson_fail("drowned" if units.any(func(u): return u.team == "squad" and u.sunk) else "down")
		return
	if lost:
		return
	lost = true
	state = "over"
	busy = true
	banner("MISSION FAILED", Color("ff4d3d"))
	Sfx.play("bad")
	sync_back()
	await wait(110)
	mission_over.emit(false)

func victory() -> void:
	if won:
		return
	won = true
	state = "over"
	busy = true
	banner("MISSION COMPLETE!", Color("62d26f"))
	if boss_dead:
		# the Boar's wreck is worth stripping for HQ
		Run.meta.salvage = int(Run.meta.get("salvage", 0)) + Data.BOSS_SALVAGE
		stats["salvage"] = int(stats.get("salvage", 0)) + Data.BOSS_SALVAGE
		Run.meta.bio = int(Run.meta.get("bio", 0)) + Data.BOSS_BIO
		stats["bio"] = int(stats.get("bio", 0)) + Data.BOSS_BIO
		Run.save_meta()
	Sfx.play("levelup")
	for s in squad_alive():
		s.pose = "cheer"; s.pose_t = 200
	var surv := squad_alive().size()
	var ab := (10 - alert) * 200
	var sb := surv * 1000
	score += ab + sb
	var pay := 100 + surv * 20 + (10 - alert) * 5
	if Run.campaign():
		pay = int(pay * (Data.PATROL_PAY if mission.get("patrol", false) else 1.0) * (1.0 + Data.CAMP_THREAT_PAY * Run.threat))
	Run.scrip += pay
	stats.scrip += pay
	if debug:
		print("[scrip] %d levelpay" % pay)
	stats["pay"] = pay
	stats["alert_bonus"] = ab
	stats["surv_bonus"] = sb
	camp_ops.job_reward()
	camp_ops.sweep_loot(INF)
	sync_back()
	if boss_dead and not mission.get("outpost", false):
		await gate_home()
	else:
		await wait(150)
	mission_over.emit(true)

func gate_home() -> void:
	## The boss is down: the captured gate spins up in the arena and the squad steps through to HQ.
	await wait(60)
	var al := squad_alive()
	var front: float = al.reduce(func(m, s): return maxf(m, s.x), cam_x + W * 0.3)
	var gx := clampf(front + 130, cam_x + 120, minf(cam_x + W - 110, world_w - 90))
	var gy = T.stand_y(gx, 0)
	if gy == null:
		gy = H * 0.7
	gate = {"x": gx, "y": float(gy) - 58, "r": 44.0, "alpha": 0.0, "chev": 0, "open": 0.0, "spin": 0.0, "burst": 0.0}
	banner("GATE ONLINE", Color("53d4e2"), "STEP THROUGH TO HQ")
	Sfx.play("power")
	for i in 40:
		gate.alpha = (i + 1) / 40.0
		if i % 4 == 0:
			sparks(gx + (randf() - 0.5) * 90, gate.y + (randf() - 0.5) * 90, 2)
		await wait(1)
	for k in 9:
		for i in 10:
			gate.spin += 0.05
			await wait(1)
		gate.chev = k + 1
		Sfx.play("tick")
	Sfx.play("bigboom")
	shake += 3
	for i in 24:
		gate.burst = 1.0 - absf(i - 8) / 16.0
		gate.open = minf(1.0, i / 10.0)
		await wait(1)
	gate.burst = 0.0
	# everyone walks in; each fades as they cross the horizon
	for s in al:
		var pts: Array = []
		var x: float = s.x
		var dir := signf(gx - x)
		while absf(gx - x) > 3:
			x += dir * 3
			var sy = T.stand_y(x, 0)
			pts.append([x, float(sy) if sy != null else s.y, false])
		s.pose = ""; s.pose_t = 0
		s.walk = pts
		s.walk_i = 0
	var n := 0
	while n < 360 and al.any(func(s): return not s.gone):
		for s in al:
			if not s.gone and absf(s.x - gx) < 14:
				s.alpha = maxf(0.0, s.alpha - 0.08)
				if s.alpha <= 0.0:
					s.gone = true
					s.walk = null
					Sfx.play("ping")
		n += 1
		await wait(1)
	for i in 20:
		gate.open = 1.0 - (i + 1) / 20.0
		await wait(1)
	await wait(20)

func sync_back() -> void:
	## Writes HP and deaths back to the persistent squad.
	Run.temp_luck = 0
	for u in squad():
		u.s.hp = maxi(0, u.hp)
		if u.dead and u.downed:
			u.s.hp = int(ceil(Run.eff_max_hp(u.s) / 2.0))
		elif u.dead and not u.s.has("guest"):
			u.s.alive = false
			u.s.hp = 0
			Run.memorialize(u.s)
	Run.total_score += score

# ---------------------------------------------------------------- update loop
const FAST_ENEMY := 3.0  # X5: enemy phase speed while Space is held (or F is toggled on)

func fast_forward() -> bool:
	return state == "enemy" and (Input.is_key_pressed(KEY_SPACE) or bool(Run.meta.get("ff", false)))

func _process(delta: float) -> void:
	var sp := speed * (FAST_ENEMY if fast_forward() else 1.0)
	acc += minf(0.1, delta) * 60.0 * sp
	var n := 0
	while acc >= 1.0 and n < int(4 * sp):
		step()
		acc -= 1.0
		n += 1
	T.flush()
	sync_chunks()
	var s := shake * SettingsScript.shake_mul() if shake > 0.6 else 0.0  # R5
	cam.position = Vector2(cam_x + W / 2.0 + round((randf() - .5) * s), H / 2.0 + round((randf() - .5) * s))
	view.queue_redraw()
	if ui_dirty and hud != null:
		ui_dirty = false
		hud.refresh()

func step() -> void:
	foe_ai.rotor_check()
	t += 1
	spec_kits.hold_fast()
	if stickies.size() and state == "enemy":
		spec_kits.sticky_watch()
	if t % 15 == 0 and tutorial():
		boot_camp.tut_update()
	if t % 5 == 0 and in_lesson():
		boot_camp.lesson_update()
	if end_confirm_t > 0:
		end_confirm_t -= 1
	if not aim_hold:
		sway_t += 1
	tick.emit()
	# the selected soldier turns and raises the weapon toward the cursor while a card is armed
	if state == "player" and not busy and sel != null and not sel.dead and card_idx >= 0 and card_idx < sel.hand.size():
		var c := Data.card(sel.hand[card_idx])
		if c.type in ["AIM", "LINE", "ARC"] and not sel.air and sel.walk == null:
			sel.face = 1 if mouse.x >= sel.x else -1
			var o := Vector2(sel.x, sel.y - sel.h + 15)
			sel.gun_target = clampf(atan2(mouse.y - o.y, (mouse.x - o.x) * sel.face), -1.35, 1.1)
	if cam_x < cam_tx:
		cam_x = minf(cam_tx, cam_x + minf(9, (cam_tx - cam_x) * 0.08 + 1.2))
		if pincer.get("view", "a") == "a":
			camp_ops.drag_stragglers()
	elif cam_x > cam_tx and pincer.get("on", false):
		cam_x = maxf(cam_tx, cam_x - minf(9, (cam_x - cam_tx) * 0.08 + 1.2))  # W9: squad B's view slides left
	if pincer.get("on", false) and state == "player" and not busy and sel != null and not sel.dead and sel.team == "squad" and wing(sel) != pincer.view:
		camp_ops.set_view(wing(sel))
	T.update_chunks()
	for u in units:
		if u.gone or u.sunk:
			continue
		if u.flash > 0:
			u.flash -= 1
		if u.muzzle > 0:
			u.muzzle -= 1
		if u.pose_t > 0:
			u.pose_t -= 1
			if u.pose_t == 0:
				u.pose = ""
		# arm drifts back to level after a shot
		u.gun_angle = lerpf(u.gun_angle, u.gun_target, 0.35)
		if u.muzzle == 0 and u.pose == "":
			u.gun_target = lerpf(u.gun_target, 0.0, 0.05)
		if u.dead:
			u.dead_t += 1
			if u.is_body() and u.soak > 0 and u.x > cam_x - 80:
				u.dead_t = mini(u.dead_t, 90)
				u.rot = u.rot + u.vx * 0.09 if u.air else 0.0
			elif u.team == "enemy" and u.dead_t > 90:
				u.alpha = maxf(0, 1 - (u.dead_t - 90) / 30.0)
				if u.alpha <= 0:
					u.gone = true
		if u.kind == "pow" and u.freed:
			u.dead_t += 1
			if u.dead_t > 50:
				u.x -= 3
				u.anim += 1
				if u.x < cam_x - 30:
					u.gone = true
			continue
		if u.kind == "cache":
			# buried until the dirt above it is blown or dug away
			if not T.solid(u.x, u.y - 8) or not T.solid(u.x, u.y + 2):
				u.gone = true
				float_at(u.x, u.y - 20, "CACHE FOUND!", Color("ffd23a"), true)
				Sfx.play("coin")
				drop_loot(u.x, u.y - 4, {"type": "item", "item": Run.roll_item(1)})
			continue
		if u.drill != null:
			drill_tick(u)
			continue
		if u.zip != null:
			var z: Dictionary = u.zip
			z.t += 1.0 / 20.0
			var k := minf(1, z.t)
			u.x = lerpf(z.x0, z.x1, k)
			u.y = lerpf(z.y0, z.y1, k) - sin(k * PI) * z.get("arc", 30.0)
			if k >= 1:
				u.x = z.x1
				u.y = z.y1
				u.zip = null
				u.air = false
			continue
		if u.walk != null:
			if u.rolling:
				u.rot += 0.42 * u.face
			for k in (3 if u.rolling else 2):
				if u.walk_i >= u.walk.size():
					u.walk = null
					biome_rules.ice_crack(u)
					break
				var pnt: Array = u.walk[u.walk_i]
				u.walk_i += 1
				if pnt[0] != u.x:
					u.face = 1 if pnt[0] > u.x else -1
				u.x = pnt[0]
				u.y = pnt[1]
			u.anim += 1
			if u.team == "squad" and u.anim % 10 == 0:
				dust(u.x, u.y, Color("b9a27a"), 1)
			if u.type == "boss":
				u.tread += 1
		else:
			physics(u)
		if lava_k > 0:
			biome_rules.lava_check(u)
		if u.team == "squad" and not u.dead:
			for p in units:
				if p.kind == "loot" and not p.gone and not p.sunk and absf(p.x - u.x) < (66 if Run.implanted(u.s, "magnet") else 22) and absf(p.y - u.y) < 30:
					if (p.loot.type == "colors" or p.loot.type == "yellow") and (u.carry != "" or p.air):
						continue  # one flag at a time, and a dropped one has to land first
					collect(u, p)
				if u.carry == "yellow" and u.walk != null and p.team == "squad" and p != u and not p.dead and absf(p.x - u.x) < 14 and absf(p.y - u.y) < 30 and p.carry == "":
					# O3: walk past a teammate to hand the yellow flag over
					p.carry = "yellow"
					u.carry = ""
					float_text(p, "MARKED MAN", Color("ffd23a"), true)
					Sfx.play("select")
				if p.kind == "wreck" and not p.stripped and absf(p.x - u.x) < 28 and absf(p.y - u.y) < 30:
					camp_ops.strip_wreck(p, u)
				if p.kind == "ride" and not p.gone and u.mech == null and absf(p.x - u.x) < 22 and absf(p.y - u.y) < 30:
					vehicle_ops.hijack(u, p)
				if p.kind == "pow" and not p.freed and absf(p.x - u.x) < 26 and absf(p.y - u.y) < 30:
					p.freed = true
					p.dead_t = 0
					float_text(p, "THANK YOU!", Color("62d26f"), true)
					pow_queue.append({"pow": p, "u": u})
	biome_rules.update_mines()
	biome_rules.update_wires()
	if pads.size():
		check_pads()
	for p in projs.duplicate():
		phys.update_proj(p)
	projs = projs.filter(func(p): return not p.dead)
	for b in booms:
		b.t -= 1
		if b.t <= 0:
			b["done"] = true
			if b.has("barrel") and b.barrel != null:
				b.barrel.dead = true
				b.barrel.gone = true
			if debug:
				print("[boom r%d] %s r%d dmg%d" % [round_n, (b.barrel.kind + ":" + b.barrel.type) if b.has("barrel") and b.barrel != null else ("owner:" + (b.owner.type if b.owner is Unit else "null")), int(b.r), b.dmg])
			explode(b.x, b.y, b.r, b.dmg, b.owner, b.get("burn", b.r >= 80))
	booms = booms.filter(func(b): return not b.get("done", false))
	for p in parts:
		p.life -= 1
		if p.get("ring", false):
			p.r += (p.max - p.r) * 0.3
			continue
		p.vy += p.g
		p.x += p.vx
		p.y += p.vy
		if p.get("smoke", false):
			p.s += 0.15
		elif not p.get("fire", false) and p.g > 0.1 and T.solid(p.x, p.y):
			p.vy *= -0.3
			p.vx *= 0.5
	parts = parts.filter(func(p): return p.life > 0)
	if parts.size() > 900:
		parts = parts.slice(parts.size() - 900)
	for f in fx:
		f.t += 1
		if f.has("vy"):
			f.y += f.vy
	fx = fx.filter(func(f): return f.t < f.dur)
	for tx in texts:
		tx.t += 1
	texts = texts.filter(func(tx): return tx.t < 70)
	for tr in tracers:
		tr.t -= 1
	tracers = tracers.filter(func(tr): return tr.t > 0)
	for b in barks:
		b.t += 1
	barks = barks.filter(func(b): return b.t < 170)
	for r in ropes:
		r.t -= 1
	ropes = ropes.filter(func(r): return r.t > 0)
	for f in feed:
		f.t += 1
	feed = feed.filter(func(f): return f.t < 480)
	if banners.size():
		banners[0].t += 1
		if banners[0].t > banners[0].dur:
			banners.pop_front()
	shake *= 0.86

func body_collisions(u: Unit) -> void:
	var sp := Vector2(u.vx, u.vy).length()
	if (sp < 3 and not u.rushing) or u.leaping:
		return  # a vault is footwork, not a tackle
	for o in units:
		if o == u or o.dead or o.gone or o.sunk or o.kind == "pow" or o.para or o.is_pickup() or u.is_pickup() or o.weight == "buried" or o.fl.get("phased", false):
			continue
		if (u.kind == "slug" and o.team == "squad") or (o.kind == "slug" and u.team != "enemy"):
			continue  # the Slug rolls over Jackals, never its own crew
		if u.bumped != null and u.bumped.has(o.id):
			continue
		if u.jumping and o.team == u.team:
			continue
		if absf(o.x - u.x) < (o.w + u.w) / 2.0 and u.y > o.y - o.h and u.y - u.h < o.y:
			var mates: bool = not u.rushing and u.team == "squad" and o.team == "squad"
			var mate_hurt: bool = o.type != "droppod" or u.rushing  # a thrown body bounces off a steel pod without denting it
			if mates:
				# one blast, one bonk: a pair of squadmates bonks once (no rebound bonks), it only hurts
				# the one knocked into, and each soldier takes at most one squadmate bonk per blast
				var pair := "%d:%d" % [mini(u.id, o.id), maxi(u.id, o.id)]
				if t - int(squad_bonks.get(pair, -BONK_RESET)) < BONK_RESET:
					continue
				squad_bonks[pair] = t
				mate_hurt = t - int(squad_bonks.get(o.id, -BONK_RESET)) >= BONK_RESET
				if mate_hurt:
					squad_bonks[o.id] = t
			if u.bumped == null:
				u.bumped = {}
			u.bumped[o.id] = true
			var cause = u if u.rushing else (u.last_hit_by if u.last_hit_by != null and u.last_hit_by.team == "squad" else null)
			var dmg: int = u.fl.get("stab", 14) if u.rushing else int(round(sp * 1.6))
			if not u.rushing and o.team == u.team:
				dmg = int(round(dmg / 3.0))  # squadmates tumbling into each other bruise, not break
			if not u.rushing and o.air and o.last_hit_by == u.last_hit_by:
				dmg = int(round(dmg / 2.0))  # both thrown by the same blast
			if cause != null and cause.perk("bulldozer"):
				dmg *= 2
			if ks(cause, "gauntlet"):
				dmg = int(dmg * 1.5)
			if cause != null and cause.perk("strike") and u != cause and o.team == "enemy" and u.bumped.size() == 3 and not act_once.has("strike"):
				act_once["strike"] = true
				cause.energy += 1
				draw_cards(cause, 1)
				float_at(o.x, o.y - 60, "STRIKE!", Color("ffd23a"), true)
			if debug:
				print("[bonk r%d] %s -> %s dmg %d" % [round_n, u.def.key if u.team == "squad" else u.type, o.def.key if o.team == "squad" else o.type, dmg])
			float_text(o, "SMASH" if u.rushing else "BONK", Color("ffd23a"), true)
			Sfx.play("bonk")
			shake += 3
			if not o.heavy and not o.is_prop() and not o.immovable and (u.rushing or t - int(bonk_launch.get(o.id, -RELAUNCH)) >= RELAUNCH):
				if not u.rushing:
					bonk_launch[o.id] = t
				var dir := signf(u.vx) if u.vx != 0 else 1.0
				o.vx = (dir * 8 if u.rushing else u.vx * 0.9) * kb(o)
				o.vy = -5 if u.rushing else minf(o.vy, -3)
				o.air = true
				o.walk = null
				o.bumped = {u.id: true}
				o.last_hit_by = cause
			if mate_hurt:
				damage(o, dmg, cause, {})
			if not u.rushing and cause != null and u.team == "enemy" and o.team == "enemy":
				add_status(u, "stun", 1, cause)
				add_status(o, "stun", 1, cause)
				tag("pileup", o.x, o.y - o.h, false)
			if not u.rushing:
				if not mates:
					collision_dmg(u, sp * (0.3 if o.team == u.team else 0.8), "BONK")
				if not ks(cause, "gauntlet"):
					u.vx *= 0.35

func physics(u: Unit) -> void:
	if u.kind == "rivet" or u.kind == "sticky":
		# pinned in place: a blast can't knock them loose (or the turn would wait on them landing)
		u.air = false
		u.vx = 0
		u.vy = 0
		return
	if u.walk != null or (u.kind == "pow" and u.freed) or u.fl.has("carried"):
		return
	if u.type == "shipplate" and not u.dead:
		# a hull plate hangs on its tethers under the Hive Ship and goes where the ship goes
		var sh = u.fl.get("ship")
		if sh != null and not sh.dead and not sh.gone:
			u.x = sh.x + u.fl.dx
			u.y = sh.y + 16
		u.air = false
		u.vx = 0
		u.vy = 0
		return
	if u.hang:
		# J4: hanging at the top of the arc until the shot; anything that pushes them lets go
		if u.vx == 0 and u.vy == 0 and not u.dead:
			return
		u.hang = false
		var hv: Vector2 = u.fl.get("hang_v", Vector2.ZERO)
		u.fl.erase("hang_v")
		u.vx += hv.x; u.vy += hv.y  # a knock mid-hang adds to the arc instead of wiping it
	if u.weight == "hover" and not u.dead:
		vharr_ai.hover_physics(u)
		return
	if u.para and u.fl.get("chute", false) and state != "enemy" and not u.dead:
		u.vx = 0.0
		u.vy = 0.0
		return  # E3: the troopers hang under their chutes until the enemy phase
	if not u.air:
		if u.y > WATER_Y + 2:
			drown(u)  # standing on anything below the waterline is standing in the water
			return
		if not T.solid(u.x, u.y):
			u.air = true
			u.vy = maxf(u.vy, 0)
			if u.slide != 0:
				u.vx = u.slide  # skidded off the edge of the ice
				u.slide = 0
		elif u.slide != 0:
			var sl := ice_step(u, u.x, u.y, u.slide)
			u.x = sl.x; u.y = sl.y; u.slide = sl.v
			if u.kind == "cart":
				biome_rules.cart_ram(u)
			if u.team == "squad" and (u.x < cam_x + 14 or u.x > cam_x + W - 14):
				u.x = clampf(u.x, cam_x + 14, cam_x + W - 14)
				u.slide = 0
			if sl.air:
				u.air = true
				u.vx = sl.v
				u.vy = 0
				u.slide = 0
			return
		else:
			return
	u.vy = minf(u.vy + grav, 2.4 if u.para else 10.0)
	if u.vault != null and u.y <= u.vault.y:
		u.vx = u.vault.vx  # clear the wall top before moving over it
	if u.para:
		u.vx = sin(t / 30.0 + u.id) * 0.4
	if (not u.dead or u.is_body()) and not u.is_prop() and u.kind != "hulk":
		body_collisions(u)
	var n := maxi(1, int(ceil(maxf(absf(u.vx), absf(u.vy)) / 2.0)))
	for i in n:
		var nx: float = u.x + u.vx / n
		if T.solid(nx, u.y - u.h * 0.5) or T.solid(nx, u.y - 6):
			var imp := absf(u.vx)
			if imp > 4 and not u.rushing and not u.jumping and not u.leaping:
				collision_dmg(u, (imp - 4) * 2.5, "SLAM")
				if imp > 7 and u.team == "enemy":
					add_status(u, "stun", 1, u.last_hit_by)
				for k in 4:
					dust(nx, u.y - u.h / 2.0, Color("c9b38a"), 1)
			if u.team == "enemy" and not u.rico and u.last_hit_by is Unit and u.last_hit_by.perk("ricobody") and imp > 3:
				u.rico = true
				u.vx *= -0.8
				u.bumped = null
				float_text(u, "RICOCHET!", Color("ffd23a"))
			else:
				u.vx *= -0.25
		else:
			u.x = nx
		if u.team == "squad" and not u.dead:
			# keep the whole body (and its name tag) on screen, not half of it
			u.x = clampf(u.x, cam_x + 14, cam_x + W - 14)
		else:
			u.x = clampf(u.x, 4, world_w - 4)
		var ny: float = u.y + u.vy / n
		if u.vy > 0 and T.solid(u.x, ny):
			var ly: float = floorf(ny / CELL) * CELL
			while T.solid(u.x, ly - 1) and ly > 0:
				ly -= CELL
			u.y = ly
			var imp: float = u.vy
			var lm := T.mat(u.x, ly)
			if mid_events.bounce_body(u, imp):
				continue
			if lm == Terrain.RUBBER and imp > 2.5 and not u.para:
				# rubber tarp: straight back up, and the bounce eats the fall
				u.y = ly - 0.5
				u.vy = -imp * 0.85
				if imp > 4:
					Sfx.play("land", -4)
					float_text(u, "BOING!", Color("ffd23a"))
				continue
			u.air = false
			u.slide = clampf(u.vx * 0.9, -4.0, 4.0) if lm == Terrain.ICE and absf(u.vx) > 0.6 and not u.para else 0.0
			if u.kind == "cart" and absf(u.vx) > 0.6:
				u.slide = u.vx  # M4: a cart that hops a dip keeps rolling
			biome_rules.ice_crack(u)
			u.vx = 0
			u.vy = 0
			if u.fl.get("crashing", false):
				foe_ai.gunship_crash(u)
			foe_ai.dicokka_land(u, imp)
			if u.crash:
				u.crash = false
				collision_dmg(u, Data.ETYPES[u.type].get("crash", 5) if u.kind == "enemy" else 5, "CRASH")
			if u.para:
				u.para = false
			elif imp > 6.5 and not u.rushing and not u.jumping and not u.leaping and not (u.team == "squad" and u.def.key == "kage"):
				collision_dmg(u, (imp - 6.5) * 2.5, "FALL")
			if imp > 3:
				Sfx.play("land", -8)
			if u.team == "squad" and u.perk("meteor") and imp > 4 and (u.jumping or u.rushing) and not u.dead:
				booms.append({"t": 1, "x": u.x, "y": u.y - 6, "r": 36.0, "dmg": 10, "owner": u})
				float_text(u, "METEOR!", Color("ff7a3d"), true)
			u.rico = false
			u.rushing = false
			u.jumping = false
			u.leaping = false
			u.vault = null
			u.bumped = null
			u.last_hit_by = null
			dust(u.x, u.y)
			return
		if u.vy < 0 and T.solid(u.x, ny - u.h):
			u.vy = 0
		else:
			u.y = ny
	if u.y > WATER_Y + 2:
		drown(u)

func undercut(x: float, y: float, r: float, by) -> void:
	## F3: an enemy shot just took ground out from under a soldier. Remembered for a round so a
	## drowning that follows can name who did it.
	if not (by is Unit) or by.team == "squad":
		return
	for u in units:
		if u.team == "squad" and not u.dead and not u.gone and absf(u.x - x) < r + 6 and u.y > y - r - 6 and u.y < y + r + 30:
			u.fl["undercut"] = [by, round_n]

func undercut_by(u: Unit):
	## F3: the enemy that cut the ground away under u this round or last, if nothing hit u since.
	var uc = u.fl.get("undercut", null)
	if uc == null or u.last_hit_by != null or int(uc[1]) < round_n - 1 or not (uc[0] is Unit):
		return null
	return uc[0]

func drown(u: Unit) -> void:
	## Worms rules: anything that ends up in the water goes under for good.
	Sfx.play("bubble")
	if u.team == "squad" and not u.dead and u.s.get("trait", "") == "lifeguard" and lifeguard_swim(u):
		return
	splash(u.x)
	if vfx != null:
		vfx.add(SfBubbles.new(u.x, WATER_Y, H + 16, 1.2))
	u.sunk = true
	var cutter = undercut_by(u) if u.team == "squad" and not u.dead else null
	if cutter != null:
		# F3: say what sank them, so the player learns where not to stand
		var nm := String(Data.ETYPES.get(cutter.type, {}).get("name", "the enemy")).to_upper()
		float_at(u.x, WATER_Y - 30, "%s DROWNED: GROUND SHOT AWAY" % u.def.name, Color("9fe3f0"), true)
		log_msg("%s drowned: the %s shot the ground out from under them." % [u.def.name, nm.to_lower() if nm != "THE ENEMY" else "enemy"])
		kill(u, null)
		return
	if not u.dead:
		var hw := biome_rules.hazard_word()
		float_at(u.x, WATER_Y - 30, ((u.def.name + " DROWNED") if u.team == "squad" else "SPLASH!") if hw == "" else ((u.def.name + " ") if u.team == "squad" else "") + hw, Color("9fe3f0") if hw == "" else Color("ff7a3d"), true)
		kill(u, u.last_hit_by if u.last_hit_by != null and u.last_hit_by is Unit and u.last_hit_by.team == "squad" else null)

func lifeguard_swim(u: Unit) -> bool:
	## P2 Lifeguard: swims to the nearest dry ground on screen instead of going under.
	for k in range(1, 60):
		for sgn in [-1, 1]:
			var x: float = u.x + sgn * k * 12.0
			if x < cam_x + 10 or x > cam_x + W - 10:
				continue
			var y = T.stand_y(x, 0)
			if y != null and y < WATER_Y - 6:
				splash(u.x)
				u.x = x; u.y = y; u.vx = 0; u.vy = 0; u.air = false; u.walk = null
				float_text(u, "LIFEGUARD", Color("9fe3f0"), true)
				return true
	return false

func ice_step(u: Unit, x: float, y: float, v: float) -> Dictionary:
	## One frame of a skid across ice: follow the surface a step up or down, stop at a wall,
	## go airborne off a drop. Ice barely slows you; anything else stops you quickly.
	var nx := x + v
	var air := false
	if nx < 4 or nx > world_w - 4 or T.solid(nx, y - u.h * 0.5) or T.solid(nx, y - 6):
		return {"x": x, "y": y, "v": 0.0, "air": false}
	var ny := y
	if T.solid(nx, y - 1):
		ny = y - CELL
		if T.solid(nx, ny - 1):
			return {"x": x, "y": y, "v": 0.0, "air": false}
	elif not T.solid(nx, y):
		if T.solid(nx, y + CELL):
			ny = y + CELL
		else:
			air = true
	v *= 0.99 if u.kind == "cart" else (0.975 if T.mat(nx, ny) == Terrain.ICE else 0.6)  # M4: carts roll on
	if absf(v) < 0.25 and not air:
		v = 0.0
	return {"x": nx, "y": ny, "v": v, "air": air}

var mine_air := {}  # unit id -> was airborne last frame
var mine_by := {}   # unit id -> who last sent it flying, kept past the landing that clears it

# ---------------------------------------------------------------- chunk sprites
func chunk_created(c: Dictionary) -> void:
	var holder := Node2D.new()
	var spr := Sprite2D.new()
	var im := Image.create(c.w, c.h, false, Image.FORMAT_RG8)
	var bytes := PackedByteArray()
	bytes.resize(c.w * c.h * 2)
	for i in c.w * c.h:
		bytes[i * 2] = c.mask[i]
		bytes[i * 2 + 1] = c.sc[i]
	im.set_data(c.w, c.h, false, Image.FORMAT_RG8, bytes)
	spr.texture = ImageTexture.create_from_image(im)
	var mat: ShaderMaterial = terrain_sprite.material.duplicate()
	mat.set_shader_parameter("cells", Vector2(c.w, c.h))
	mat.set_shader_parameter("cell_offset", Vector2(c.x0, c.y0))
	spr.material = mat
	spr.centered = false
	spr.scale = Vector2(CELL, CELL)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.add_child(spr)
	chunk_layer.add_child(holder)
	c.node = holder

func chunk_removed(c: Dictionary) -> void:
	if c.node != null:
		c.node.queue_free()
		c.node = null

func sync_chunks() -> void:
	for c in T.chunks:
		if c.node == null:
			continue
		var holder: Node2D = c.node
		var spr: Sprite2D = holder.get_child(0)
		# the holder sits on the piece's centre of mass and turns with it
		holder.position = c.pos
		holder.rotation = c.ang
		var jit := (randf() - .5) * 2 if c.shake < 6 else 0.0
		spr.position = -c.com + Vector2(jit, 0)

# ---------------------------------------------------------------- input
func unit_at_p(p: Vector2):
	var best = null
	for u in units:
		if u.dead or u.gone or u.sunk or u.kind == "cache":
			continue
		if p.x >= u.x - u.w / 2.0 - 6 and p.x <= u.x + u.w / 2.0 + 6 and p.y >= u.y - u.h - 6 and p.y <= u.y + 4:
			if best == null or absf(u.x - p.x) < absf(best.x - p.x):
				best = u
	return best

func select_card(i: int) -> void:
	var u := sel
	if u == null or busy or state != "player" or i >= u.hand.size():
		return
	if rummage_armed:
		rummage(u, i)
		return
	var inst: Dictionary = u.hand[i]
	var c := Data.card(inst)
	if u.energy < card_cost(u, inst):
		Sfx.play("deny")
		return
	Sfx.play("click")
	if c.type == "SELF":
		play_self(i)
		return
	card_idx = -1 if card_idx == i else i
	jet_armed = false
	fuse_pick = 0
	ui_dirty = true

const RUMMAGE_COST := 1

func can_rummage(u: Unit) -> bool:
	## C1: once a turn, 1 energy swaps a card in hand for a fresh draw.
	return u != null and not u.dead and u.team == "squad" and state == "player" and not busy and u.energy >= RUMMAGE_COST and not u.fl.get("rummaged", false) and u.hand.any(swappable)

func swappable(inst: Dictionary) -> bool:
	## Hop, sidearms, gun mounts and Overdrives aren't in the deck, so they can't be swapped out.
	return not inst.get("temp", false) and not inst.get("od", false)

func toggle_rummage() -> void:
	if rummage_armed:
		rummage_armed = false
	elif can_rummage(sel):
		rummage_armed = true
		card_idx = -1
		jet_armed = false
		float_text(sel, "PICK A CARD TO SWAP", Color("ffd23a"))
	else:
		Sfx.play("deny")
		if sel != null and sel.fl.get("rummaged", false):
			float_text(sel, "ALREADY SWAPPED THIS TURN", Color("ff7a3d"))
		return
	Sfx.play("click")
	ui_dirty = true

func rummage(u: Unit, i: int) -> void:
	rummage_armed = false
	ui_dirty = true
	if not can_rummage(u) or i >= u.hand.size() or not swappable(u.hand[i]):
		Sfx.play("deny")
		return
	var out: Dictionary = u.hand[i]
	u.hand.remove_at(i)
	u.energy -= RUMMAGE_COST
	u.fl["rummaged"] = true
	draw_cards(u, 1)
	u.disc.append(out)  # after the draw, so a reshuffle can't hand the same card straight back
	Sfx.play("select")
	float_text(u, "SWAPPED %s" % Data.card(out).name.to_upper(), Color("ffd23a"))

func cancel_card() -> void:
	rummage_armed = false
	card_idx = -1
	jet_armed = false
	fuse_pick = 0
	ui_dirty = true

func armed_fuse():
	## The armed card's fuse in frames if it is a bouncing grenade the wheel can dial, else null.
	if sel == null or card_idx < 0 or card_idx >= sel.hand.size():
		return null
	var c := Data.card(sel.hand[card_idx])
	if c.type != "ARC" or c.get("fuse", null) == null or not c.get("bounce", false):
		return null
	return fuse_pick if fuse_pick > 0 else int(c.fuse)

func dial_fuse(d: int) -> void:
	## K1: the wheel sets a grenade's fuse from 1 to 4 seconds in half-second steps.
	var f = armed_fuse()
	if f == null or busy or state != "player":
		return
	fuse_pick = clampi(int(round(f / 30.0)) * 30 + d * 30, 60, 240)
	Sfx.play("tick", -8)

func select_unit(u: Unit) -> void:
	if u == null or u.dead or busy:
		return
	if u.trapped:
		float_text(u, "PINNED DOWN: GET TO HIM", Color("ff7a3d"), true)  # T6
		return
	if pincer.get("on", false) and u.team == "squad":
		camp_ops.set_view(wing(u))
	if u != sel:
		drop_hang(sel)
	sel = u
	card_idx = -1
	jet_armed = false
	Sfx.play("click")
	ui_dirty = true

func world_click(p: Vector2) -> void:
	if state != "player" or busy:
		return
	var u := sel
	var tg = unit_at_p(p)
	if card_idx >= 0 and u != null and card_idx < u.hand.size():
		var c := Data.card(u.hand[card_idx])
		if c.type == "ALLY":
			if tg != null and tg.team == "squad":
				play_on_target(tg)
			return
		if c.type == "MELEE":
			if tg != null:
				play_on_target(tg)
			return
		commit_aim(p)
		return
	if tg != null and tg.team == "squad" and not tg.dead:
		if tg != u:
			select_unit(tg)
		return
	if u != null and u.hang:
		drop_hang(u)  # clicking the ground lets go and drops
		return
	if u != null and not u.dead and u.move_left > 1:
		var L = ladder_at(p)
		if L != null and plan_climb(u, L) != null:
			do_climb(u, L)
		else:
			do_move(u, p.x)

func next_unit() -> void:
	## NEXT: jump to the next soldier who can still act; with nobody left, it ends the turn.
	if state != "player" or busy:
		return
	if ready_count() == 0:
		end_turn(true)
		return
	var a := squad_alive()
	var i := a.find(sel)
	for k in range(1, a.size() + 1):
		var cand: Unit = a[(i + k) % a.size()]
		if can_act(cand) and (cand != sel or k == a.size()):
			select_unit(cand)
			return

func is_mobility(c: Dictionary) -> bool:
	return c.type == "SELF" and (c.has("move") or c.has("rally")) and not c.get("od", false)

func auto_advance() -> void:
	## MOVE: every soldier spends spare energy on Sprint, Dash and Rally, then walks as far east as
	## they can, front man first so nobody trips over a squadmate. Attack cards are left alone.
	if state != "player" or busy:
		return
	resolve(func(): await _act_advance())

func _act_advance() -> void:
	var sq := camp_ops.bar_squad().filter(func(s): return not s.dead)  # W9: on the pincer, the half on screen
	# rallies first, so the movement they hand out is there for everyone else's walk
	for pass_ in ["rally", "move"]:
		for u in sq:
			var played := true
			while played and not u.dead:
				played = false
				for i in u.hand.size():
					var c := Data.card(u.hand[i])
					if is_mobility(c) and c.has(pass_) and card_cost(u, u.hand[i]) <= u.energy:
						await _act_self(u, i, c)
						await wait(6)
						played = true
						break
	var west: bool = pincer.get("on", false) and pincer.view == "b"  # squad B advances west
	sq.sort_custom(func(a, b2): return a.x < b2.x if west else a.x > b2.x)
	for u in sq:
		if u.dead or u.move_left <= 1:
			continue
		var sim := biome_rules.stop_before_mines(u, phys.sim_walk(u, u.x - u.move_left if west else u.x + u.move_left, u.move_left))
		if sim.pts.is_empty():
			continue
		sel = u
		await _act_walk(u, sim.pts, sim.used)
	ui_dirty = true

func cycle_unit(d: int) -> void:
	## TAB skips soldiers who have nothing left to do, unless nobody can act.
	var a := squad_alive()
	if a.is_empty():
		return
	var i := a.find(sel)
	for k in range(1, a.size() + 1):
		var cand: Unit = a[(i + d * k + a.size() * k) % a.size()]
		if can_act(cand):
			select_unit(cand)
			return
	select_unit(a[(i + d + a.size()) % a.size()])

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		mouse = get_global_mouse_position()
	elif ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		jet_hold = false
	elif ev is InputEventMouseButton and ev.pressed:
		mouse = get_global_mouse_position()
		if busy and stop_drill():
			return
		if ev.button_index == MOUSE_BUTTON_LEFT:
			# a plain click on the HUD's top bar (score, alert, wind) is not a walk order
			if card_idx < 0 and not jet_armed and not rummage_armed and get_viewport().get_mouse_position().y < 34:
				return
			if jet_armed and state == "player" and not busy and sel != null and not sel.dead:
				start_jet(sel)
			else:
				world_click(mouse)
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			cancel_card()
		elif ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			dial_fuse(1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
	elif ev is InputEventKey:
		if ev.keycode == KEY_SHIFT:
			aim_hold = ev.pressed
			return
		if ev.keycode == KEY_ALT or ev.keycode == KEY_V:
			inspect = ev.pressed
			return
		if not ev.pressed or ev.echo:
			return
		if busy and ev.keycode in [KEY_SPACE, KEY_ESCAPE, KEY_ENTER] and stop_drill():
			return
		if ev.keycode == KEY_F and not (hud != null and hud.deck_open):
			# X5: F keeps every enemy phase on fast-forward
			Run.meta["ff"] = not bool(Run.meta.get("ff", false))
			Run.save_meta()
			float_at(cam_x + W / 2.0, 120, "FAST ENEMY TURNS " + ("ON" if Run.meta.ff else "OFF"), Color("53d4e2"), true)
			ui_dirty = true
			return
		if ev.keycode == KEY_ESCAPE and hud != null and hud.close_deck():
			return
		if hud != null and hud.deck_open:
			return  # keys stay out of the battle while the deck viewer is up
		if ev.keycode == KEY_ESCAPE:
			# N7: Esc cancels an armed card (or the jet, or a mid-air hang) first; with nothing to cancel it pauses
			if card_idx >= 0 or jet_armed or rummage_armed:
				cancel_card()
			elif sel != null and sel.hang:
				drop_hang(sel)
			elif hud != null:
				hud.toggle_pause()
			return
		if ev.keycode == KEY_T and in_lesson():
			boot_camp.lesson_fail("retry")  # T: start this lesson again, any time
			return
		if state != "player" or busy:
			return
		if ev.keycode == KEY_TAB or ev.keycode == KEY_E:
			cycle_unit(1)
		elif ev.keycode == KEY_Q:
			cycle_unit(-1)
		elif ev.keycode >= KEY_1 and ev.keycode <= KEY_9:
			select_card(ev.keycode - KEY_1)
		elif ev.keycode == KEY_SPACE:
			next_unit()
		elif ev.keycode == KEY_ENTER:
			end_turn()
		elif ev.keycode == KEY_M:
			auto_advance()
		elif ev.keycode == KEY_R:
			toggle_rummage()
		elif ev.keycode == KEY_BACKSPACE:
			undo_last_walk()
		elif ev.keycode == KEY_J:
			toggle_jet()
		elif ev.keycode == KEY_G:
			camp_ops.switch_wing()
		elif ev.keycode == KEY_BRACKETRIGHT or ev.keycode == KEY_EQUAL:
			dial_fuse(1)
		elif ev.keycode == KEY_BRACKETLEFT or ev.keycode == KEY_MINUS:
			dial_fuse(-1)

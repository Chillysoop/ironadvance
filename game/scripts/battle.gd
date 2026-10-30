class_name Battle
extends Node2D
## One mission: the turn loop, physics, weapons, enemy AI and the collapse hooks.
## Runs on a fixed 60 Hz step; long actions are coroutines that await `tick`.

signal tick
signal mission_over(won: bool)
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
var shake := 0.0
var cam_x := 0.0
var cam_tx := 0.0
var state := "title"
var busy := false
var round_n := 0
var alert := 0
var rounds_since_scroll := 0
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
var pow_queue: Array = []
var para_queue: Array = []   # soldiers who picked up a reinforcement flare, waiting on the call-in
var job_st := {}   # O4: {"on", "left"} while holding the far end
var lvl_queue: Array = []
var dummies: Array = []       # practice range: [type, x] of each dummy, to stand them back up
var tut_step := 0             # N6 training: the drill step the recruits are on
var tut_said := -1            # the last step the sergeant has called in
var tut_marks := {}           # drill step -> the units it is about
var tut_blast := false        # a squad blast went off on the grenade step
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
			make_jbox(x)
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
		if type == "shield" and not walled and mission_idx >= 1 and not tutorial():
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
		elif not tutorial() and randf() < 0.12 + mission_idx * 0.06 + (0.25 if Run.intel == "veterans" else 0.0) + (0.15 if Run.threat_on(2) else 0.0) + (0.6 if mission.get("outpost", false) else 0.0) + rules.get("elite", 0.0):
			make_elite(u, pick_elite(faction(u) == "vharr"))
		units.append(u)
		if opt.has("tut"):
			tut_marks[opt.tut] = tut_marks.get(opt.tut, []) + [u]
			# drill dummies drop to one rifle shot or one frag, so each lesson lands first try
			if opt.tut in ["target", "group"]:
				u.hp = mini(u.hp, 5); u.max_hp = u.hp
		place_alien(u)
		if type == "hiveship":
			hang_plates(u)
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
	place_encounter(mission.get("encounter", ""))
	place_vehicles()
	setup_biome()
	setup_events()
	place_job()
	trap_varga()
	place_nemesis()
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
		"ration":
			var h := mini(d.n, u.max_hp - u.hp)
			u.hp += h
			float_text(u, "+%d HP" % h, Color("62d26f"))
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
	if tutorial():
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
	Sfx.play("thud" if c.kind == "strongbox" else "bonk")
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



# ---------------------------------------------------------------- N2 Bolt: building into the terrain
func build_scale(u) -> float:
	## Toolbelt: everything Bolt builds is 50% bigger.
	return 1.5 if u is Unit and u.team == "squad" and u.def.key == "bolt" else 1.0

func is_build(c: Dictionary) -> bool:
	return c.has("build") or c.get("girder", false)

func clear_of_units(x: float, y: float) -> bool:
	for o in units:
		if o.dead or o.gone or o.sunk or o.is_pickup() or o.kind == "rivet":
			continue
		if x >= o.x - o.w / 2.0 - 1 and x <= o.x + o.w / 2.0 + 1 and y >= o.y - o.h - 1 and y <= o.y + 1:
			return false
	return true

func build_cells(x: float, y: float, w: float, h: float, m: int) -> Array:
	## Fills empty cells of a rectangle, never on top of a body. Returns the cell indices it set.
	var out: Array = []
	for cy in range(int(floor(y / CELL)), int(ceil((y + h) / CELL))):
		for cx in range(int(floor(x / CELL)), int(ceil((x + w) / CELL))):
			if cx < 0 or cy < 0 or cx >= T.cols or cy >= Terrain.ROWS or cy * CELL >= WATER_Y:
				continue
			if T.grid[cy * T.cols + cx] != 0 or not clear_of_units(cx * CELL + 2.0, cy * CELL + 2.0):
				continue
			T.set_cell(cx, cy, m)
			out.append(cy * T.cols + cx)
	return out

func build_wall(u, x: float, gy: float, w: float, h: float) -> void:
	var m := 4 if u is Unit and u.perk("concrete") else 1
	var cells := build_cells(x - w / 2.0, gy - h, w, h, m)
	if cells.size():
		walls.append(Rect2(x - w / 2.0, gy - h, w, h))
		for k in 5:
			puff(x + randf_range(-w / 2.0, w / 2.0), gy - randf_range(0, h), 1.5)

func build_at(p: Dictionary) -> void:
	## A thrown build card landed (Sandbags, Sentry Gun, Jump Pad).
	var u = p.owner
	var pc: Dictionary = p.card
	var sc := build_scale(u)
	var gy = T.stand_y(p.x, p.y - 30)
	if gy == null:
		float_at(p.x, p.y - 10, "SPLASH", Color("9aa2ae"))
		return
	match pc.build:
		"wall":
			var big := 2.0 if ks(u, "rebar") else 1.0
			build_wall(u, p.x, gy, pc.bw * sc * big, pc.bh * sc * big)
			float_at(p.x, gy - pc.bh * sc - 10, "SANDBAGS", Color("c9b38a"))
			Sfx.play("land")
		"sentry":
			var n := 2 if u is Unit and u.perk("secondsentry") else 1
			for k in n:
				var sx: float = p.x + (k - (n - 1) / 2.0) * 26.0
				var sy = T.stand_y(sx, gy - 30)
				if sy != null:
					make_sentry(u, sx, sy, int(round(pc.shp * sc)), pc.sdmg)
			Sfx.play("select")
		"pad":
			var w: float = pc.pw * sc
			for cx in range(int(floor((p.x - w / 2.0) / CELL)), int(ceil((p.x + w / 2.0) / CELL))):
				var ty = T.stand_y(cx * CELL + 2.0, gy - 24)
				if ty != null and absf(ty - gy) < 24:
					T.set_cell(cx, int(ty / CELL), Terrain.RUBBER)
			T.tarps.append([p.x - w / 2.0, p.x + w / 2.0])
			float_at(p.x, gy - 14, "JUMP PAD", Color("ff9a3d"))
			Sfx.play("bonk")
	after_build(u)

func after_build(u) -> void:
	## Scrapper perks and the Magnet Glove keystone pay out on every build.
	if not (u is Unit) or u.team != "squad" or u.dead:
		return
	if u.perk("scraparmor"):
		u.armor += 3
		float_text(u, "+3 ARMOR", Color("9fb4c9"))
	if u.perk("recycler"):
		draw_cards(u, 1)
	ui_dirty = true

func make_sentry(u, x: float, y: float, hp: int, dmg: Array) -> Unit:
	var st := mk_unit()
	st.team = "ally"; st.kind = "sentry"; st.x = x; st.y = y; st.w = 16; st.h = 20; st.heavy = true
	st.hp = hp; st.max_hp = hp; st.face = 1
	st.loot = {"by": u, "dmg": dmg}
	units.append(st)
	if u != null:
		puff(x, y - 8, 1.5)
		float_at(x, y - 30, "SENTRY UP", Color("62d26f"))
	return st

func sentry_target(st: Unit):
	## The nearest Jackal (or Vharr) the sentry can see, within 520px. Drawn as its laser.
	var best = null
	var bd := 520.0
	for e in units:
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
		if T.hard(x0 + (x1 - x0) * k / L, y0 + (y1 - y0) * k / L):
			return true
	return false

func sentry_fire(st: Unit) -> void:
	var tg = sentry_target(st)
	if tg == null:
		return
	var by = st.loot.by
	var ksc: bool = ks(by, "turretcore")
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
			float_at(st.x, st.y - 34, "SENTRY FIRES", Color("ff9a3d"))
			await wait(10)
		st.muzzle = 10
		Sfx.play("mg")
		var hp0: int = tg.hp
		var ang := atan2(tg.y - tg.h * 0.55 - my, tg.x - mx)
		var tr := trace_bullet(mx, my, ang, 560, 0, by if by is Unit else st, ksc)
		for sg in tr.segs:
			tracers.append({"x1": sg[0], "y1": sg[1] - 1, "x2": sg[2], "y2": sg[3] - 1, "c": Color("ff9a3d"), "t": 22})
			tracers.append({"x1": sg[0], "y1": sg[1] + 1, "x2": sg[2], "y2": sg[3] + 1, "c": Color("ff9a3d"), "t": 22})
		fire_bullet(by if by is Unit else st, mx, my, ang, {"dmg": dmg, "range": 560, "bounce": 0, "pierce": ksc}, false)
		sparks(mx + st.face * 20, my - 1, 5)
		if not tg.dead and tg.hp >= hp0:
			float_text(tg, "SENTRY MISSED", Color("c9d1da"))
		await wait(16)

func sentries_fire() -> void:
	var sts := units.filter(func(o): return o.kind == "sentry" and not o.dead and not o.gone and not o.loot.get("pinned", false))
	if sts.is_empty():
		return
	for st in sts:
		await sentry_fire(st)
	await until(settled)

func _act_girder(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	spend_card(u, idx, c)
	var reach: float = c.reach * (2.0 if u.perk("longspan") else 1.0)
	var from := Vector2(u.x, u.y - 22)
	var d := p - from
	var L := minf(d.length(), reach)
	var dir := d.normalized() if d.length() > 0.1 else Vector2(u.face, 0)
	var at := from + dir * L
	for k in range(8, int(L), 4):
		var q := from + dir * k
		if T.hard(q.x, q.y):
			at = from + dir * maxf(0, k - 6)
			break
	u.face = 1 if at.x >= u.x else -1
	u.pose = "throw"; u.pose_t = 18
	Sfx.play("toss")
	ropes.append({"u": u, "x": at.x, "y": at.y, "t": 14})
	await wait(10)
	var w: float = c.gw * build_scale(u) * (1.5 if u.perk("longspan") else 1.0)
	var th := 16.0 if u.perk("heavysteel") or ks(u, "rivetdriver") else 8.0
	var cells := build_cells(at.x - w / 2.0, at.y, w, th, 2)
	if cells.is_empty():
		float_at(at.x, at.y - 10, "NO ROOM", Color("ff7a3d"))
		return
	var rv := mk_unit()
	rv.team = "neutral"; rv.kind = "rivet"; rv.x = at.x; rv.y = at.y + 4; rv.w = 10; rv.h = 10; rv.hp = 1; rv.max_hp = 1
	rv.loot = {"cells": cells, "by": u, "w": w, "turn": round_n}
	for i in cells:
		T.pins[i] = rv.id
	units.append(rv)
	Sfx.play("ping")
	sparks(at.x, at.y, 6)
	float_at(at.x, at.y - 14, "GIRDER", Color("c9d1da"))
	after_build(u)
	if u.perk("piledriver") and units.any(func(e): return e.team == "enemy" and not e.dead and absf(e.x - at.x) < w / 2.0 + 6 and e.y > at.y and e.y - at.y < 260):
		await wait(16)
		drop_girder(rv, u)

func drop_girder(rv: Unit, by) -> void:
	## The bolt is shot out: unpin the beam and let the terrain drop it as a falling chunk.
	if rv.dead:
		return
	rv.dead = true
	rv.gone = true
	for i in rv.loot.cells:
		if T.pins.get(i, -1) == rv.id:
			T.pins.erase(i)
	var by_u = rv.loot.by if rv.loot.by is Unit else by
	sparks(rv.x, rv.y, 8)
	Sfx.play("ping")
	float_at(rv.x, rv.y - 12, "BOLT SHOT!", Color("ffd23a"), true)
	if by_u is Unit and by_u.team == "squad" and by_u.def.key == "bolt" and rv.loot.turn == round_n and state == "player" and not by_u.fl.has("cutloose"):
		by_u.fl["cutloose"] = true
		chain(by_u, "CUT LOOSE")
		by_u.energy += 1
	T.check_floating(rv.x, rv.y + 4, rv.loot.w / 2.0 + 12, by_u)

func steel_rain(x: float, n: int, by) -> void:
	## Steel Rain / Demo Team: girders appear high over the marker and fall.
	banner("STEEL RAIN!", Color("c9d1da"))
	Sfx.play("alarm")
	if vfx != null:
		# V17: a red beacon marks where the girders come down
		var by_y = T.stand_y(x, 0)
		vfx.add(SfPillar.new(x, by_y if by_y != null else WATER_Y, 0.9, 6.0 + n * 3.0, 0.2))
	for k in n:
		var gx := x + (k - (n - 1) / 2.0) * 44.0
		var gy := 20.0 + (k % 2) * 16.0
		var cells := build_cells(gx - 22, gy, 44, 12, 2)
		if cells.size():
			T.check_floating(gx, gy + 6, 34, by)

func scrap_heap(x: float, y: float, by) -> void:
	## Junk Cannon: the scrap lands as a heap of steel.
	var gy = T.stand_y(x, y - 40)
	if gy != null:
		build_cells(x - 20, gy - 14, 40, 14, 2)

func fortify(u: Unit, c: Dictionary) -> void:
	## Fortify / Iron Curtain / Build Crew: armor for the squad nearby and a wall in front of each.
	banner("FORTIFY!", Color("c9d1da"))
	Sfx.play("power")
	var foe = null
	for e in units:
		if e.team == "enemy" and not e.dead and (foe == null or absf(e.x - u.x) < absf(foe.x - u.x)):
			foe = e
	var dir := 1.0 if foe == null or foe.x >= u.x else -1.0
	if c.get("curtain", false):
		var cx := u.x + dir * 60.0
		if foe != null:
			cx = (u.x + foe.x) / 2.0
		var gy = T.stand_y(cx, 0)
		if gy != null:
			build_cells(cx - 8, gy - 90, 16, 90, 4)
	for s in squad_alive():
		if s == u or absf(s.x - u.x) <= c.range:
			s.armor += c.fortify
			float_text(s, "+%d ARMOR" % c.fortify, Color("9fb4c9"), true)
			if not c.get("curtain", false):
				var wx: float = s.x + dir * 22.0
				var gy = T.stand_y(wx, s.y - 30)
				if gy != null:
					build_cells(wx - 4, gy - 32, 8, 32, 4)
	if c.get("rook_wall", false):
		var rk = null
		for s in squad_alive():
			if s.def.key == "rook":
				rk = s
		if rk != null and foe != null:
			foe.vx = signf(foe.x - rk.x) * 9.0; foe.vy = -3.0; foe.air = true; foe.walk = null; foe.bumped = {}; foe.last_hit_by = rk
			float_text(foe, "BOOT!", Color("ffd23a"), true)
	await wait(20)

# ---------------------------------------------------------------- N7 Track and Rex, K9 Handler
func make_rex(u: Unit) -> Unit:
	## Rex deploys beside Track. He is on the squad's side but never moves on his own.
	var rx := mk_unit()
	rx.team = "ally"; rx.kind = "dog"; rx.w = 18; rx.h = 14; rx.face = 1
	rx.max_hp = 18 * (2 if ks(u, "k9vest") else 1); rx.hp = rx.max_hp
	rx.loot = {"by": u, "guard": null, "ko": false, "tackled": {}}
	rx.x = u.x - 16
	var gy = T.stand_y(rx.x, u.y - 30)
	rx.y = gy if gy != null else u.y
	units.append(rx)
	return rx

func rex_of(u) -> Unit:
	if not (u is Unit):
		return null
	for o in units:
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
	for o in units:
		if o.dead or o.gone or o.sunk:
			continue
		var fits: bool = (o.team == "enemy" and o.weight != "buried" and not is_boss(o)) if c.dog == "bite" else (o.kind == "loot" or o.kind == "crate" or (o.kind == "pow" and not o.freed))
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
	var gy = T.stand_y(to.x, to.y - 30)
	if gy == null:
		gy = T.stand_y(to.x, 0)
	if gy == null or gy >= WATER_Y:
		return {"ok": false, "why": "NO FOOTING", "rex": rx, "to": to}
	return {"ok": true, "rex": rx, "tg": tg, "to": Vector2(to.x, gy)}

func dog_leap(rx: Unit, to: Vector2) -> void:
	rx.loot.guard = null
	rx.walk = null; rx.vx = 0; rx.vy = 0
	Sfx.play("toss", -6)
	await leap_to(rx, to)
	dust(rx.x, rx.y)

func heel(u: Unit, rx: Unit) -> void:
	## Rex runs back to Track's side.
	var bx := u.x - u.face * 16.0
	var gy = T.stand_y(bx, u.y - 30)
	await dog_leap(rx, Vector2(bx, gy if gy != null else u.y))
	rx.face = u.face

func slash_fx(x: float, y: float, sc: float, face: int) -> void:
	## A melee cut: the V7 pixel slash when the effects layer is up, the old swipe otherwise.
	if vfx != null:
		vfx.slash(x, y, face, sc)
	else:
		fx.append({"kind": "slash", "x": x, "y": y, "t": 0, "dur": 12 if sc > 1 else 10, "sc": sc, "face": face})

func dog_bite(u: Unit, by: Unit, tg: Unit, dmg: Array, o := {}) -> void:
	## One bite. Track's perks ride on every dog, his own Rex or the pack's.
	if tg.dead:
		return
	by.face = 1 if tg.x >= by.x else -1
	by.pose = "throw"; by.pose_t = 10
	Sfx.play("slash", -4)
	slash_fx(tg.x, tg.y - tg.h / 2.0, 1.0, by.face)
	var d := ri(dmg[0], dmg[1]) + (3 if u.perk("bigdog") else 0)
	if o.get("double", false):
		d *= 2
	damage(tg, d, u, {"melee": true})
	if u.perk("alpha") or o.get("stun", false):
		add_status(tg, "stun", 1, u)
	if u.perk("markbite") or o.get("mark", false):
		add_status(tg, "mark", 2, u)
	if o.get("knock", 0) > 0 and not tg.dead and not tg.heavy and not tg.is_prop() and not tg.immovable:
		tg.vx = by.face * o.knock * kb(tg); tg.vy = -3.0; tg.air = true; tg.walk = null; tg.bumped = null; tg.last_hit_by = u
	await wait(10)

func _act_dog(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	var dt := dog_target(u, c, p)
	spend_card(u, idx, c)
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
			float_text(rx, "GRRR", Color("e8dcc2"))
		return
	# Fetch: grab everything within a few steps of the spot, then trot back
	var got := 0
	for o in units.duplicate():
		if o.dead or o.gone or absf(o.x - rx.x) > 40 or absf(o.y - rx.y) > 40:
			continue
		if o.kind == "loot":
			collect(u, o)
			got += 1
		elif o.kind == "crate":
			open_crate(o, false)
			got += 1
		elif o.kind == "pow" and not o.freed:
			o.freed = true
			o.dead_t = 0
			float_text(o, "GOOD DOG!", Color("62d26f"), true)
			pow_queue.append({"pow": o, "u": u})
			got += 1
	if u.perk("pockets"):
		draw_cards(u, 1)
	if u.perk("scrounger"):
		give_scrip(10, rx.x, rx.y - 20, "L964")
	float_text(rx, "FETCHED!" if got else "SNIFF...", Color("62d26f") if got else Color("9aa2ae"))
	await wait(12)
	if got:
		# the loot dropped by crates lands near him: one more sweep before heading home
		await wait(20)
		for o in units.duplicate():
			if o.kind == "loot" and not o.gone and absf(o.x - rx.x) < 60 and absf(o.y - rx.y) < 60:
				collect(u, o)
	await heel(u, rx)

func rex_guard(u: Unit, tg: Unit) -> void:
	var rx := rex_ready(u)
	if rx == null:
		return
	var bx := tg.x + (16.0 if tg != u else -u.face * 16.0)
	var gy = T.stand_y(bx, tg.y - 30)
	await dog_leap(rx, Vector2(bx, gy if gy != null else tg.y))
	rx.loot.guard = tg
	rx.loot.tackled = {}
	rx.face = 1
	float_text(rx, "ON GUARD", Color("53d4e2"), true)

func guard_tackle(e: Unit, tg: Unit) -> bool:
	## Guard: a Jackal lines up a shot on the guarded squadmate, and Rex hits it first.
	if e.team != "enemy" or is_boss(e) or tg == null or tg.team != "squad":
		return false
	for rx in units:
		if rx.kind != "dog" or rx.loot.get("temp", false) or rx.loot.ko or rx.dead or rx.gone:
			continue
		var by: Unit = rx.loot.by
		var g = rx.loot.guard
		if g == null and by.perk("watchdog") and not by.dead:
			g = by
		if g != tg or rx.loot.tackled.has(e.id):
			continue
		banner("REX!", Color("ffd23a"))
		var spot := Vector2(e.x - signf(e.x - rx.x) * (e.w / 2.0 + 8), e.y)
		var gy = T.stand_y(spot.x, spot.y - 30)
		var keep = rx.loot.guard
		await dog_leap(rx, Vector2(spot.x, gy if gy != null else e.y))
		await dog_bite(by, rx, e, [4 + (6 if by.perk("hardtackle") else 0), 4 + (6 if by.perk("hardtackle") else 0)], {"stun": true, "knock": 8 if by.perk("hardtackle") else 0})
		float_text(e, "TACKLED!", Color("ffd23a"), true)
		if by.perk("loyal"):
			rx.loot.tackled[e.id] = true
			rx.loot.guard = keep
			var gy2 = T.stand_y(g.x + 16, g.y - 30)
			await leap_to(rx, Vector2(g.x + 16, gy2 if gy2 != null else g.y))
		return true
	return false

func release_hounds(u: Unit, c: Dictionary, n: int) -> void:
	## Release the Hounds / Wolfpack / Skyfall / K9 Strike: each dog (or the hawk) takes a different Jackal.
	var hawk: bool = c.get("hawk", false)
	banner("SKYFALL!" if hawk else "RELEASE THE HOUNDS!", Color("ffb23e"))
	Sfx.play("alarm")
	var foes := units.filter(func(e): return e.team == "enemy" and not e.dead and not e.gone and not e.sunk and e.weight != "buried" and e.x > cam_x - 20 and e.x < cam_x + W + 20)
	foes.sort_custom(func(a, b2): return absf(a.x - u.x) < absf(b2.x - u.x))
	for e in foes.slice(0, n):
		if e.dead:
			continue
		if hawk:
			await hawk_dive(u, e, 6)
			continue
		var dg := mk_unit()
		dg.team = "ally"; dg.kind = "dog"; dg.w = 18; dg.h = 14; dg.hp = 1; dg.max_hp = 1
		dg.loot = {"by": u, "temp": true, "ko": false, "guard": null, "tackled": {}}
		dg.x = u.x; dg.y = u.y
		units.append(dg)
		var gy = T.stand_y(e.x - signf(e.x - u.x) * (e.w / 2.0 + 8), e.y - 30)
		await leap_to(dg, Vector2(e.x - signf(e.x - u.x) * (e.w / 2.0 + 8), gy if gy != null else e.y))
		await dog_bite(u, dg, e, [8, 10], {"stun": c.get("hstun", false), "mark": c.get("hmark", false), "knock": 4})
		dg.gone = true
		dg.dead = true
		puff(dg.x, dg.y - 6, 1.0)
	await wait(12)

func hawk_dive(u: Unit, e: Unit, dmg: int) -> void:
	## The hawk stoops out of the sky: a streak down onto the Jackal, damage and a Mark.
	var sx := e.x - 60.0
	tracer(sx, e.y - 220, e.x, e.y - e.h / 2.0, Color("e8dcc2"))
	Sfx.play("toss", -2)
	await wait(8)
	var d := dmg + (6 if u.perk("talons") else 0)
	if d > 0:
		damage(e, d, u, {"melee": true})
	add_status(e, "mark", 2, u)
	float_text(e, "HAWK!", Color("e8dcc2"))
	await wait(8)

func supply_run(u: Unit) -> void:
	var rx := rex_ready(u)
	if rx == null:
		rx = rex_of(u)
		if rx == null:
			return
		revive_rex(u, rx)
	banner("SUPPLY RUN!", Color("62d26f"))
	var goods := units.filter(func(o): return not o.dead and not o.gone and (o.kind == "loot" or o.kind == "crate") and o.x > cam_x - 20 and o.x < cam_x + W + 20)
	goods.sort_custom(func(a, b2): return a.x < b2.x)
	for o in goods.slice(0, 10):
		if o.gone or o.dead:
			continue
		var gy = T.stand_y(o.x, o.y - 30)
		await dog_leap(rx, Vector2(o.x, gy if gy != null else o.y))
		if o.kind == "crate":
			open_crate(o, false)
			await wait(16)
		elif not o.gone:
			collect(u, o)
	for o in units.duplicate():
		if o.kind == "loot" and not o.gone and absf(o.x - rx.x) < 80:
			collect(u, o)
	await heel(u, rx)

func revive_rex(u: Unit, rx: Unit) -> void:
	## Best Friend: a knocked-out Rex is back at Track's side.
	rx.loot.ko = false
	rx.loot.guard = null
	rx.gone = false
	rx.dead = false
	rx.hp = rx.max_hp
	rx.x = u.x - u.face * 16.0
	var gy = T.stand_y(rx.x, u.y - 30)
	rx.y = gy if gy != null else u.y
	rx.zip = null; rx.vx = 0; rx.vy = 0; rx.air = false
	puff(rx.x, rx.y - 6, 1.2)
	float_text(rx, "REX IS BACK", Color("62d26f"))

func rex_hurt(rx: Unit, amt: int) -> void:
	if rx.loot.get("temp", false):
		rx.gone = true
		rx.dead = true
		return
	if ks(rx.loot.by, "k9vest"):
		amt = maxi(0, amt - 3)
	if amt <= 0:
		float_text(rx, "VEST", Color("9fb4c9"))
		return
	rx.hp -= amt
	rx.flash = 8
	float_text(rx, "-%d" % amt, Color("ff4d3d"))
	if rx.hp <= 0:
		rx.hp = 0
		rx.loot.ko = true
		rx.loot.guard = null
		rx.gone = true
		puff(rx.x, rx.y - 6, 1.5)
		float_at(rx.x, rx.y - 26, "REX KNOCKED OUT", Color("ff7a3d"), true)
		log_msg("Rex is knocked out. He'll be back at Track's side next turn.")

func dogs_new_turn() -> void:
	## Start of the squad's turn: Rex shakes off a knockout or catches up, and the Hawk Hood marks a Jackal.
	for u in squad_alive():
		if u.def.key != "track" and not ks(u, "hawkhood"):
			continue
		var rx := rex_of(u)
		if rx != null and (rx.loot.ko or absf(rx.x - u.x) > 560 or rx.sunk):
			rx.sunk = false
			revive_rex(u, rx)
		if ks(u, "hawkhood"):
			var best = null
			for e in units:
				if e.team == "enemy" and not e.dead and not e.gone and e.x > cam_x - 20 and e.x < cam_x + W + 20 and (best == null or absf(e.x - u.x) < absf(best.x - u.x)):
					best = e
			if best != null:
				await hawk_dive(u, best, 0)

# ---------------------------------------------------------------- N3 Gears, R1 hijacked vehicles, E6 Jackal Walker
func mech_max(u: Unit, type: String, own: bool) -> int:
	var hp := float(Data.VEHICLES[type].hp)
	if u.team == "squad":
		if own and u.perk("armorplate"):
			hp += 15
		if own and ks(u, "jumpjets"):
			hp += 20
		if squad_alive().any(func(o): return ks(o, "toolkit")):
			hp *= 1.5
	return int(hp)

func mount(u: Unit, type: String, hp := -1, own := false) -> void:
	## Climb into a vehicle. Its HP soaks every hit until it breaks; a hijacker gets its cards in hand.
	if u.mech != null:
		return
	var V: Dictionary = Data.VEHICLES[type]
	var mx := mech_max(u, type, own)
	u.mech = {"type": type, "hp": mx if hp < 0 else mini(hp, mx), "max": mx, "own": own, "h0": u.h, "w0": u.w}
	u.h += V.seat
	u.w = maxf(u.w, 26.0)
	u.heavy = true
	if not own:
		mech_cards(u)
	if u.mech_stash.size():
		# back in a vehicle: the deck's own vehicle cards are shuffled back into the draw pile
		for c in u.mech_stash:
			u.draw.insert(randi() % (u.draw.size() + 1), c)
		u.mech_stash = []
		ui_dirty = true

func mech_cards(u: Unit) -> void:
	## A hijacked vehicle's own guns go in the driver's hand, and come back every turn.
	if u.mech == null or u.mech.own:
		return
	for k in Data.VEHICLES[u.mech.type].cards:
		if not u.hand.any(func(h): return h.key == k and h.get("mechtemp", false)):
			u.hand.append({"id": -7, "key": k, "tier": Data.base_tier(k), "temp": true, "mechtemp": true})

func vehicle_pop(u: Unit, mode: String, type: String, added: Array, removed: Array) -> void:
	## Pop the boarding card over the field: what the vehicle does and which cards came or went.
	if u.team != "squad":
		return
	vpop = {"u": u, "mode": mode, "type": type, "added": added, "removed": removed, "t0": t}
	ui_dirty = true

func dismount(u: Unit, launch := true) -> void:
	if u.mech == null:
		return
	# on foot, vehicle cards are gone at once: the hijacked guns from the hand, and the deck's own
	# vehicle cards (Gears' walker) from the hand, draw and discard piles until the next mount
	var is_veh := func(h): return h.get("mechtemp", false) or Data.card(h).get("mech", false)
	var gone: Array = u.hand.filter(is_veh).map(func(h): return h.key)
	for pile in [u.hand, u.draw, u.disc]:
		for h in pile:
			if is_veh.call(h) and not h.get("mechtemp", false) and not h.get("temp", false):
				u.mech_stash.append(h)
	u.hand = u.hand.filter(func(h): return not is_veh.call(h))
	u.draw = u.draw.filter(func(h): return not is_veh.call(h))
	u.disc = u.disc.filter(func(h): return not is_veh.call(h))
	vehicle_pop(u, "out", u.mech.type, [], gone)
	u.h = u.mech.h0
	u.w = u.mech.w0
	u.heavy = u.immovable
	u.mech = null
	if launch:
		u.vx = -u.face * 1.5; u.vy = -6.0; u.air = true; u.walk = null; u.bumped = {}; u.jumping = true
	ui_dirty = true

func mech_hit(u: Unit, amt: int) -> void:
	## The vehicle takes the hit instead of the driver. At 0 it falls apart and the driver tumbles out.
	if u.mech.own and u.perk("reactive"):
		amt = maxi(1, amt - 2)
	u.mech.hp -= amt
	u.flash = 8
	sparks(u.x, u.y - 12, 3)
	float_text(u, "-%d %s" % [amt, Data.VEHICLES[u.mech.type].name], Color("ffb23e"))
	if u.mech.hp <= 0:
		var nm: String = Data.VEHICLES[u.mech.type].name
		for k in 8:
			debris(u.x + randf_range(-12, 12), u.y - randf_range(4, 20), 2)
		puff(u.x, u.y - 10, 2.0)
		Sfx.play("boom", -6)
		var tp: String = u.mech.type
		var own: bool = u.mech.own
		dismount(u)
		if vpop.get("u") == u:
			vpop.mode = "wreck"
		elif own:
			vehicle_pop(u, "wreck", tp, [], [])
		float_text(u, nm + " WRECKED", Color("ff7a3d"), true)
		log_msg("%s's %s is wrecked. %s" % [u.def.name, nm.to_lower(), "Patch Job puts him back in one." if u.def.key == "gears" else "They're on foot."])
	ui_dirty = true

func mech_ok(u: Unit, c: Dictionary) -> String:
	## Why this card can't be played right now ("" when it can).
	if c.get("mech", false) and u.mech == null:
		return "NEEDS A VEHICLE"
	if c.get("patch", false) and u.mech != null:
		return "ALREADY DRIVING"
	if c.get("bodythrow", false) and u.held == null:
		return "NOTHING TO THROW"
	return ""

func _act_eject(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	## Eject!: the driver pops out, the empty vehicle charges at the cursor and blows.
	spend_card(u, idx, c)
	u.attacked = true
	var type: String = u.mech.type
	var v := rush_vel(u, p)
	var hk := mk_unit()
	hk.team = "neutral"; hk.kind = "hulk"; hk.x = u.x; hk.y = u.y; hk.w = 26; hk.h = 24; hk.hp = 1; hk.max_hp = 1; hk.heavy = true
	hk.face = 1 if p.x >= u.x else -1
	hk.loot = {"type": type, "by": u}
	hk.y = u.y - 2
	hk.vx = v.vx; hk.vy = v.vy; hk.air = true; hk.bumped = {u.id: true}; hk.last_hit_by = u; hk.rushing = true
	dismount(u)
	units.append(hk)
	banner("EJECT!", Color("ffb23e"))
	Sfx.play("power")
	if u.perk("softlanding"):
		u.armor += 8
		float_text(u, "+8 ARMOR", Color("9fb4c9"))
	if ks(u, "ejectseat"):
		draw_cards(u, 2)
		u.energy += 1
	var t0 := t
	await until(func(): return not hk.air or t - t0 > 240 or units.any(func(e): return e.team == "enemy" and not e.dead and not e.gone and absf(e.x - hk.x) < e.w / 2.0 + 12 and hk.y > e.y - e.h - 6 and hk.y - 24 < e.y))
	hk.gone = true
	var r: float = c.radius * (1.5 if u.perk("biggerboom") else 1.0) * blast_scale(u)
	explode(hk.x, hk.y - 10, r, c.dmg, u)
	for k in 10:
		debris(hk.x + randf_range(-14, 14), hk.y - randf_range(4, 24), 2)
	await wait(20)
	if c.get("rebuild", false) and not u.dead:
		await until(func(): return not u.air or u.dead)
		mount(u, "walker", -1, true)
		float_text(u, "FRESH WALKER", Color("62d26f"), true)

func patch_job(u: Unit) -> void:
	mount(u, "tank" if ks(u, "treads") else "walker", -1, true)
	for k in 6:
		sparks(u.x + randf_range(-12, 12), u.y - randf_range(4, 30), 2)
	float_text(u, "PATCH JOB", Color("62d26f"), true)
	Sfx.play("ping")

func ride_along(u: Unit) -> void:
	var rk = null
	for s in squad_alive():
		if s.def.key == "rook":
			rk = s
	banner("RIDE ALONG!", Color("ffb23e"))
	if rk != null:
		var gy = T.stand_y(u.x - u.face * 22.0, u.y - 40)
		await leap_to(rk, Vector2(u.x - u.face * 22.0, gy if gy != null else u.y))
		rk.armor += 6
		float_text(rk, "+6 ARMOR", Color("9fb4c9"), true)
		rk.hand.append({"id": -2, "key": "burst", "tier": Data.base_tier("burst"), "temp": true, "free": true})
	u.armor += 6
	float_text(u, "+6 ARMOR", Color("9fb4c9"), true)
	u.hand.append({"id": -2, "key": "vulcan", "tier": Data.base_tier("vulcan"), "temp": true, "free": true})

func field_refit(u: Unit, heal: int) -> void:
	banner("FIELD REFIT!", Color("62d26f"))
	if u.mech != null:
		u.mech.hp = u.mech.max
	else:
		patch_job(u)
	for s in squad_alive():
		s.hp = mini(s.max_hp, s.hp + heal)
		float_text(s, "+%d HP" % heal, Color("62d26f"), true)
	Sfx.play("coin")

func vehicles_new_turn() -> void:
	## Start of the squad's turn: hijackers get their vehicle's guns back, Tune-Up repairs.
	var tune := squad_alive().any(func(o): return o.perk("tuneup"))
	for s in squad_alive():
		if s.mech == null:
			continue
		mech_cards(s)
		if tune and s.mech.hp < s.mech.max:
			s.mech.hp = mini(s.mech.max, s.mech.hp + 6)
			float_text(s, "TUNE-UP +6", Color("62d26f"))

func hijack(u: Unit, r: Unit) -> void:
	## R1: walk onto a parked vehicle and you're driving it.
	r.gone = true
	var before: Array = u.hand.duplicate()
	mount(u, r.loot.type, r.loot.get("hp", -1))
	Sfx.play("power")  # the boarding card is the announcement: no banner on top of it
	if squad_alive().any(func(o): return o.perk("hotwire")):
		u.energy += 1
		u.hand.append({"id": -2, "key": "vulcan", "tier": Data.base_tier("vulcan"), "temp": true, "free": true})
		float_text(u, "HOTWIRED +1", Color("ffb23e"))
	vehicle_pop(u, "in", r.loot.type, u.hand.filter(func(h): return not before.has(h)).map(func(h): return h.key), [])
	log_msg("%s takes the %s. Its HP soaks every hit until it breaks." % [u.def.name, Data.VEHICLES[r.loot.type].name.to_lower()])
	ui_dirty = true

func park_ride(x: float, type: String, hp := -1) -> Unit:
	var gy = T.stand_y(x, 0)
	if gy == null or gy >= WATER_Y - 4:
		return null
	if T.lakes.any(func(l): return x > l[0] - 20 and x < l[1] + 20):
		return null  # M1: lake crust breaks under any vehicle, so the first driver would sink on boarding
	var r := mk_unit()
	r.team = "neutral"; r.kind = "ride"; r.x = x; r.y = gy; r.w = 30; r.h = 24; r.face = -1
	r.loot = {"type": type, "hp": hp}
	units.append(r)
	return r

func place_vehicles() -> void:
	## R1: a parked Jackal vehicle in the first stretch, and E6: a Jackal Walker guarding the second
	## half of it. Neither in a breach, a detour yard or the finale harbor.
	if T.stretches.is_empty() or mission.get("finale", false) or mission.get("tutorial", false):
		return
	var st: Array = T.stretches[0]
	var w: float = st[1] - st[0]
	var kind: String = pick(["bike", "walker", "tank"])
	for f in [0.3, 0.2, 0.4, 0.15, 0.5]:
		if park_ride(st[0] + w * f, kind) != null:
			break
	if mission.get("walker", false):
		var mb: String = mission.get("miniboss", "jwalker")
		# E6: both feet on solid ground, or leg_check topples it before the squad has moved
		var x: float = st[0] + w * 0.75
		for f in [0.75, 0.7, 0.8, 0.65, 0.85]:
			x = st[0] + w * f
			var y0 = T.stand_y(x, 0)
			if y0 != null and T.solid(x - 13, y0 + 3) and T.solid(x + 13, y0 + 3):
				break
		var y = T.stand_y(x, 0)
		if y != null and y < WATER_Y - 4:
			var e := mk_enemy(mb, x, y)
			if mb == "jwalker":
				e.mech = {"type": "walker", "hp": 0, "max": 0, "own": false, "h0": 34, "w0": 16}
			place_alien(e)
			units.append(e)

func leg_check() -> void:
	## E6: a Jackal Walker with the ground blown out under one leg topples that way and crushes.
	for e in units.duplicate():
		if e.type != "jwalker" or e.dead or e.gone or e.air:
			continue
		var l := T.solid(e.x - 13, e.y + 3)
		var r := T.solid(e.x + 13, e.y + 3)
		if l == r:
			continue
		var dir := -1.0 if not l else 1.0
		banner("WALKER TOPPLED!", Color("ffd23a"))
		Sfx.play("bigboom")
		shake += 8
		e.face = int(dir)
		var by = e.last_hit_by if e.last_hit_by is Unit and e.last_hit_by.team == "squad" else (squad_alive()[0] if squad_alive().size() else null)
		for o in units.duplicate():
			if o == e or o.dead or o.gone or o.is_pickup() or o.kind in ["pow", "ride", "rivet", "loot"]:
				continue
			var dx: float = (o.x - e.x) * dir
			if dx > 4 and dx < 84 and absf(o.y - e.y) < 50:
				damage(o, 25, by, {"crush": true})
				float_text(o, "CRUSHED", Color("ffd23a"))
		for k in 10:
			dust(e.x + dir * randf_range(10, 80), e.y)
		kill(e, by)
		await wait(30)

func walker_wreck(e: Unit) -> void:
	## A dead Jackal Walker leaves its walker behind, banged up but drivable.
	e.gone = true
	for k in 10:
		debris(e.x + randf_range(-14, 14), e.y - randf_range(4, 40), 2)
	puff(e.x, e.y - 20, 2.5)
	var r := park_ride(e.x, "walker", 18)
	if r != null:
		float_at(r.x, r.y - 40, "WALKER UP FOR GRABS", Color("ffb23e"), true)

# ---------------------------------------------------------------- E1-E5, E7, E8: new Jackals
func sniper_line(e: Unit) -> Dictionary:
	## E1: where the Jackal Sniper's laser runs right now, from his scope to the first wall.
	var o := Vector2(e.x + e.face * 10, e.y - e.h + 10)
	var a: float = e.fl.get("laser", PI if e.face < 0 else 0.0)
	var r := cast_ray(o.x, o.y, a, Data.ETYPES.jsniper.range)
	return {"from": o, "to": Vector2(r.x, r.y), "a": a}

func sniper_act(e: Unit) -> void:
	## Fire down the laser he showed last turn, then lay it on the nearest soldier for next time.
	var E: Dictionary = Data.ETYPES.jsniper
	if e.fl.has("laser"):
		var L := sniper_line(e)
		e.muzzle = 4
		e.muzzle_kind = "snipe"
		Sfx.play("snipe")
		fire_bullet(e, L.from.x, L.from.y, L.a, {"dmg": E.dmg, "range": E.range, "bounce": 0, "chip": 5}, false)
		await wait(24)
	if e.dead or e.air:
		return
	var tg = null
	var o := Vector2(e.x, e.y - e.h + 10)
	for s in foes_of(e):
		if s.team == "squad" and not targetable(e, s):
			continue
		if ray_clear(o.x, o.y, s.x, s.y - s.h / 2.0) and (tg == null or absf(s.x - e.x) < absf(tg.x - e.x)):
			tg = s
	if tg == null:
		tg = nearest_squad(e)
	if tg == null:
		return
	e.face = 1 if tg.x >= e.x else -1
	var o2 := Vector2(e.x + e.face * 10, e.y - e.h + 10)
	e.fl["laser"] = atan2(tg.y - tg.h / 2.0 - o2.y, tg.x - o2.x)
	float_text(e, "LASER ON " + (tg.def.name if tg.team == "squad" else "TARGET"), Color("ff4d3d"))
	Sfx.play("tick")
	await wait(10)

func flamer_act(e: Unit) -> void:
	## E2: walk up and hose a short cone of fire. Wood in the cone burns away.
	var E: Dictionary = Data.ETYPES.flamer
	var tg = nearest_squad(e)
	if tg == null:
		return
	if absf(tg.x - e.x) > E.range - 20 and not e.hold:
		await enemy_advance(e, tg.x - signf(tg.x - e.x) * (E.range - 40), E.speed, func():
			var t2 = nearest_squad(e)
			return t2 != null and absf(t2.x - e.x) <= E.range - 20 and absf(t2.y - e.y) < 50)
	if e.dead or e.air:
		return
	tg = nearest_squad(e)
	if tg == null or absf(tg.x - e.x) > E.range or absf(tg.y - e.y) > 50:
		return
	e.face = 1 if tg.x >= e.x else -1
	e.pose = "recoil"; e.pose_t = 30
	Sfx.play("rocket")
	for f in 18:
		for k in 3:
			part({"x": e.x + e.face * 14, "y": e.y - 18, "vx": e.face * randf_range(4, 7), "vy": randf_range(-1.2, 1.2), "life": 18, "max": 18, "c": pick([Color("ffb23e"), Color("ff7a3d"), Color("ffe36a")]), "s": 3.0, "g": -0.03, "fire": true})
		await wait(1)
	for o in units:
		if o == e or o.dead or o.gone or o.sunk or o.is_pickup() or o.kind == "pow" or signf(o.x - e.x) != e.face:
			continue
		if absf(o.x - e.x) <= E.range and absf(o.y - e.y) < 44:
			damage(o, int(round(E.dmg * (1 + alert * 0.06))), e, {})
			add_status(o, "burn", 2, e)
	var x := e.x + e.face * 16
	while absf(x - e.x) <= E.range:
		for dy in [6, 18, 30]:
			if T.mat(x, e.y - dy) == 3:
				T.carve(x, e.y - dy, 6, null)  # wood in the cone goes up
		x += e.face * 10
	await wait(10)

func tank_hit(tg: Unit, dx: float, by) -> bool:
	## E2: a round into the Flametrooper's back finds the fuel tank.
	if tg.type != "flamer" or tg.dead or tg.fl.get("tank_gone", false) or signf(dx) != tg.face:
		return false
	tg.fl["tank_gone"] = true
	float_text(tg, "TANK HIT!", Color("ffb23e"), true)
	booms.append({"t": 1, "x": tg.x - tg.face * 6, "y": tg.y - 20, "r": 54.0, "dmg": 18, "owner": by, "burn": true})
	return true

func wall_mates(e: Unit) -> Array:
	## E5: the Riot Jackals locked in one Shield Wall with this one (itself included).
	if not e.fl.has("wall") or e.dead:
		return []
	return units.filter(func(o): return not o.dead and not o.gone and o.fl.get("wall", -1) == e.fl.wall and absf(o.x - e.x) < 70 and absf(o.y - e.y) < 30)

func wall_locked(e: Unit) -> bool:
	return wall_mates(e).size() >= 2

func wall_act(e: Unit) -> bool:
	## The wall's front man walks it forward as one block; the others only shoot. Returns true if handled.
	var mates := wall_mates(e)
	if mates.size() < 2:
		return false
	mates.sort_custom(func(a, b2): return a.x < b2.x)
	var tg = nearest_squad(e)
	if tg == null:
		return true
	var dir := 1.0 if tg.x > e.x else -1.0
	var lead: Unit = mates[-1] if dir > 0 else mates[0]
	if e == lead and e.fl.get("wall_moved", -1) != round_n and not e.hold:
		var E: Dictionary = Data.ETYPES[e.type]
		var x0 := lead.x
		var stop: float = tg.x - dir * E.prefer
		if (stop - lead.x) * dir > 0:
			await enemy_advance(lead, stop, E.speed)
		var moved := lead.x - x0
		for m in mates:
			m.fl["wall_moved"] = round_n
			if m != lead and absf(moved) > 1:
				var tx: float = m.x + moved
				var ty = T.stand_y(tx, m.y - 30)
				if ty != null:
					var pts: Array = []
					var n := int(absf(moved) / 2.0)
					for k in n:
						pts.append([m.x + moved * (k + 1) / n, ty, false])
					await walk_along(m, pts)
		float_text(lead, "SHIELD WALL", Color("c9d1da"))
	if e.dead or e.air:
		return true
	var E2: Dictionary = Data.ETYPES[e.type]
	var bs = best_shot(e, foes_of(e), E2.range)
	if bs != null:
		await wait(4)
		await enemy_shoot(e, bs.t, E2)
	return true

func chute_hit(tg: Unit, y: float) -> bool:
	## E3: a round through the parachute cuts it; the trooper drops like a stone.
	if not tg.para or y > tg.y - tg.h:
		return false
	tg.para = false
	tg.fl.erase("chute")
	tg.vy = 2.0
	float_text(tg, "CHUTE CUT!", Color("ffd23a"), true)
	Sfx.play("ping")
	return true

func plane_drop(n: int) -> void:
	## E3: a plane crosses the top of the screen and drops troopers on chutes. They hang there
	## through your turn and come down in the next enemy phase.
	var drop: Array = ["grunt", "grunt", "shield", "nade"]
	banner("PARATROOPERS!", Color("ff7a3d"), "SHOOT THE CHUTES BEFORE THEY LAND")
	Sfx.play("alarm")
	for i in n:
		var x: float = cam_x + W - 120 - i * 70
		var e := mk_enemy(drop[i % drop.size()], x, 70.0 + (i % 2) * 22)
		e.active = true; e.heavy = false; e.air = true; e.para = true; e.vy = 0.0
		e.fl["chute"] = true
		units.append(e)
		puff(x, 50, 2.0)
		await wait(8)
	log_msg("Paratroopers hang over the field. Shoot a chute and its trooper falls hard.")

func gunship_act(e: Unit) -> void:
	## E7: fly over the marked strip and rake it, then mark the next strip by the nearest soldier.
	var E: Dictionary = Data.ETYPES.gunship
	if e.fl.has("strafe"):
		var sx: float = (e.fl.strafe.x0 + e.fl.strafe.x1) / 2.0
		await hover_move(e, sx, E.speed * 2)
		if e.dead:
			return
		Sfx.play("mg")
		var x0: float = e.fl.strafe.x0
		var x1: float = e.fl.strafe.x1
		for k in 8:
			var gx: float = lerpf(x0, x1, k / 7.0)
			var gy = T.stand_y(gx, 0)
			tracer(e.x, e.y - 6, gx, gy if gy != null else WATER_Y, Color("ffb0a0"))
			if gy != null:
				T.carve(gx, gy, 3, null)
				dust(gx, gy, Color("c9b38a"), 2)
			await wait(3)
		for o in units:
			if o == e or o.dead or o.gone or o.sunk or o.is_pickup() or o.kind == "pow" or o.team == "enemy":
				continue
			if o.x >= x0 - o.w / 2.0 and o.x <= x1 + o.w / 2.0 and not o.has_st("cloak"):
				damage(o, int(round(E.dmg * (1 + alert * 0.06))), e, {})
		e.fl.erase("strafe")
		await wait(10)
	var tg = nearest_squad(e)
	if tg == null or e.dead:
		return
	e.face = 1 if tg.x >= e.x else -1
	e.fl["strafe"] = {"x0": tg.x - E.strafe / 2.0, "x1": tg.x + E.strafe / 2.0}
	float_at(tg.x, tg.y - 50, "STRAFING RUN NEXT TURN", Color("ff4d3d"), true)

func rotor_check() -> void:
	## E7: a body or a barrel thrown into the gunship's rotor wrecks it.
	for g in units:
		if g.type != "gunship" or g.dead or g.gone:
			continue
		for o in units:
			if o == g or o.dead and not o.is_body() or o.gone or not o.air or o.fl.get("rotored", -1) == g.id:
				continue
			if absf(o.x - g.x) < g.w / 2.0 + 4 and o.y - o.h < g.y - g.h + 4 and o.y > g.y - g.h - 14:
				o.fl["rotored"] = g.id
				o.vy = 3.0
				o.vx *= -0.4
				float_text(g, "ROTOR HIT!", Color("ffb23e"), true)
				Sfx.play("bonk")
				sparks(o.x, g.y - g.h, 10)
				damage(g, 18, o.last_hit_by if o.last_hit_by is Unit else null, {"blast": true})

func gunship_down(g: Unit) -> void:
	g.weight = ""
	g.air = true
	g.vy = 0.0
	g.walk = null
	g.fl["crashing"] = true  # it still has to come down
	float_text(g, "GOING DOWN!", Color("ff7a3d"), true)

func gunship_crash(g: Unit) -> void:
	## E7: the wreck crushes whatever it lands on.
	g.fl.erase("crashing")
	g.dead = true
	g.gone = true
	shake += 10
	explode(g.x, g.y - 10, 64, 26, g.last_hit_by if g.last_hit_by is Unit else null)
	for k in 12:
		debris(g.x + randf_range(-30, 30), g.y - randf_range(4, 30), 2)
	float_at(g.x, g.y - 40, "GUNSHIP DOWN!", Color("ffb23e"), true)

func dicokka_act(e: Unit) -> void:
	## E8: roll back and forth a set step, then lob a shell. Flipped, it just lies there.
	var E: Dictionary = Data.ETYPES.dicokka
	if e.fl.get("flipped", 0) > 0:
		e.fl.flipped -= 1
		if e.fl.flipped <= 0:
			e.fl.erase("flipped")
			float_text(e, "BACK ON ITS TRACKS", Color("ff7a3d"))
		else:
			float_text(e, "FLIPPED", Color("ffd23a"))
		return
	if not e.fl.has("home"):
		e.fl["home"] = e.x
		e.fl["dir"] = -1.0
	var tx: float = e.fl.home + e.fl.dir * 110
	e.fl.dir = -e.fl.dir
	await enemy_advance(e, tx, E.speed)
	if e.dead or e.air:
		return
	var tg = nearest_squad(e)
	if tg == null or absf(tg.x - e.x) > E.range:
		return
	e.face = 1 if tg.x >= e.x else -1
	await lob(e, tg, E.dmg, E.radius, 1.3)

func dicokka_dmg(tg: Unit, amt: int, src, o: Dictionary) -> int:
	## Armored front, soft from above and behind, and twice as soft flipped on its back.
	if tg.fl.get("flipped", 0) > 0:
		float_text(tg, "BELLY HIT", Color("ffd23a"))
		return amt * 2
	if not (src is Unit) or o.get("status", false):
		return amt
	var above: bool = src.y < tg.y - tg.h - 10
	var front: bool = signf(src.x - tg.x) == tg.face
	if front and not above:
		float_text(tg, "ARMOR", Color("9fb4c9"))
		return maxi(1, int(round(amt * 0.3)))
	return int(round(amt * 1.5))

func dicokka_land(u: Unit, imp: float) -> void:
	if u.type == "dicokka" and not u.dead and imp > 3.5 and u.last_hit_by is Unit and u.last_hit_by.team == "squad":
		u.fl["flipped"] = 2
		float_text(u, "FLIPPED!", Color("ffd23a"), true)
		Sfx.play("thud")
		shake += 4

# ---------------------------------------------------------------- N1 Finch, N4 Kage, N5 Volta, N6 Brass, N8 Sable
func vis_foes() -> Array:
	## Hostile Jackals and aliens on screen (not the ones Sable has taken over).
	return units.filter(func(e): return e.team == "enemy" and not e.dead and not e.gone and not e.fl.has("mind") and not Data.ETYPES[e.type].get("static", false) and e.x > cam_x - 20 and e.x < cam_x + W + 20)

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
	for s in squad_alive():
		if s.def.key == key:
			return s
	return null

func fling(o: Unit, dir: float, pw: float, by) -> void:
	## Throws a body sideways; heavies and anchors barely budge.
	if o.dead or o.gone or o.immovable or is_boss(o):
		return
	o.vx = dir * pw * (0.35 if o.heavy else 1.0) * kb(o)
	o.vy = -3.5 - pw * 0.25
	o.air = true; o.walk = null; o.bumped = null; o.last_hit_by = by

var zaps := {}  # V5: arc ends -> tick it started, so a bolt redrawn each frame is one effect

func lightning(a: Vector2, b2: Vector2) -> void:
	if vfx != null:
		var key := Vector4i(roundi(a.x), roundi(a.y), roundi(b2.x), roundi(b2.y))
		if zaps.get(key, -99) > t - 10:
			return
		zaps[key] = t
		vfx.add(SfLightning.arc(func(): return a, [b2], vfx.ground_fn(b2.y), 0.25))
		return
	var prev := a
	for k in range(1, 6):
		var t := k / 5.0
		var nxt := a.lerp(b2, t) + (Vector2(randf_range(-6, 6), randf_range(-6, 6)) if k < 5 else Vector2.ZERO)
		tracer(prev.x, prev.y, nxt.x, nxt.y, Color("9fe8ff"))
		prev = nxt

# --- N1 Finch
func zip_spot(u: Unit, c: Dictionary, p: Vector2) -> Dictionary:
	var reach: float = c.reach * (1.5 if u.perk("longline") else 1.0)
	var from := Vector2(u.x, u.y - u.h)
	var to := from + (p - from).limit_length(reach)
	var x := clampf(to.x, cam_x + 14, cam_x + W - 14)
	var y = T.stand_y(x, to.y - 12)
	if y == null:
		return {"ok": false, "x": x, "y": to.y, "hx": from.x, "hy": from.y}
	return {"ok": true, "x": x, "y": float(y), "hx": from.x, "hy": from.y}

func _act_zip(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	c = spend_card(u, idx, c)
	var zs := zip_spot(u, c, p)
	var pull: float = c.pull + (70.0 if u.perk("longline") else 0.0)
	var riders: Array = [u]
	for s in squad_alive():
		if s != u and s.mech == null and s.kind != "dog" and Vector2(s.x - u.x, s.y - u.y).length() <= pull:
			riders.append(s)
	Sfx.play("rocket")
	var dir := 1.0 if zs.x >= u.x else -1.0
	var starts: Array = riders.map(func(r): return Vector2(r.x, r.y))
	var ends: Array = []
	for i in riders.size():
		var off: float = -dir * 20.0 * i
		var ex: float = clampf(zs.x + off, cam_x + 14, cam_x + W - 14)
		var ey = T.stand_y(ex, zs.y - 30)
		ends.append(Vector2(ex, ey if ey != null else zs.y))
	for f in 14:
		tracer(zs.hx, zs.hy, zs.x, zs.y - 30, Color("e8dcc2"))
		for i in riders.size():
			var r: Unit = riders[i]
			var pt: Vector2 = starts[i].lerp(ends[i], (f + 1) / 14.0)
			r.x = pt.x; r.y = pt.y - sin((f + 1) / 14.0 * PI) * 16
			r.vx = 0; r.vy = 0; r.air = false; r.walk = null; r.face = int(dir)
		await wait(1)
	for i in riders.size():
		var r: Unit = riders[i]
		r.x = ends[i].x; r.y = ends[i].y; r.air = false
		if u.perk("groupride"):
			r.move_left += 40
	float_text(u, "ZIPLINE" if riders.size() == 1 else "ALL ABOARD x%d" % riders.size(), Color("e8dcc2"), true)
	if u.perk("freefall"):
		draw_cards(u, 1)
	u.moved = true
	await check_push(u)

func flare_at(x: float, y: float, r: float, by) -> void:
	for e in units:
		if e.team == "enemy" and not e.dead and not e.gone and Vector2(e.x - x, e.y - e.h / 2.0 - y).length() < r + e.w / 2.0:
			add_status(e, "flared", 2, by)
			if by is Unit and by.perk("illum"):
				add_status(e, "supp", 1, by)
	for i in 14:
		part({"x": x + randf_range(-r, r) * 0.4, "y": y - randf_range(0, 30), "vx": randf_range(-1, 1), "vy": -randf_range(0.2, 1.4), "life": 40, "max": 40, "c": Color("ffe36a"), "s": 3.0, "g": 0.0, "fire": true})
	float_at(x, y - 30, "FLARE", Color("ffe36a"), true)
	Sfx.play("power")

func flare_bonus() -> int:
	return 6 if squad_alive().any(func(s): return s.perk("spotcrit")) else 3

func drone_runs(u: Unit, c: Dictionary) -> void:
	var n: int = c.drone * (2 if u.perk("twindrone") else 1)
	var reach := 2000.0 if c.get("od", false) else 420.0
	var foes := vis_foes().filter(func(e): return absf(e.x - u.x) <= reach)
	foes.sort_custom(func(a, b2): return absf(a.x - u.x) < absf(b2.x - u.x))
	if foes.is_empty():
		float_text(u, "NO TARGETS", Color("9aa2ae"))
		return
	Sfx.play("power")
	float_text(u, "DRONE UP", Color("e8dcc2"), true)
	for k in n:
		var e: Unit = foes[k % foes.size()]
		if e.dead:
			continue
		var dy: float = e.y - e.h - 60
		if u.perk("dronegun"):
			for s in 3:
				tracer(e.x - 10, dy, e.x, e.y - e.h / 2.0, Color("fff4c0"))
				damage(e, 3, u)
				await wait(3)
		if u.perk("dronemark") and not e.dead:
			add_status(e, "flared", 2, u)
		var r: float = c.get("radius", 32) * blast_scale(u)
		projs.append(mk_proj({"kind": "bomb", "x": e.x, "y": dy, "vx": 0.0, "vy": 3.0, "r": r, "dmg": c.get("dmg", 9), "owner": u}))
		Sfx.play("toss")
		await wait(14)
	await until(settled)

func rig_all(u: Unit) -> void:
	banner("RIGGED!", Color("ffb23e"))
	for o in units.duplicate():
		if o.gone or o.dead or o.x < cam_x - 20 or o.x > cam_x + W + 20:
			continue
		if o.kind == "barrel" or o.kind == "fuel":
			damage(o, 1, u, {"blast": true})
		elif o.kind == "mine" and not o.primed:
			o.primed = true
			booms.append({"t": 6, "x": o.x, "y": o.y - 3, "r": 38.0, "dmg": 15, "owner": u, "barrel": o})
	await wait(20)
	await until(settled)

# --- N4 Kage
func iaido_line(u: Unit, c: Dictionary, p: Vector2) -> Dictionary:
	var from := Vector2(u.x, u.y - u.h / 2.0)
	var to := from + (p - from).normalized() * float(c.reach)
	var hit: Array = []
	for o in units:
		if o == u or o.dead or o.gone or o.team == "squad" or o.is_pickup() or o.kind in ["pow", "ride", "hulk", "sticky"]:
			continue
		var ctr := Vector2(o.x, o.y - o.h / 2.0)
		var q := Geometry2D.get_closest_point_to_segment(ctr, from, to)
		if q.distance_to(ctr) < o.w / 2.0 + 8:
			hit.append(o)
	return {"from": from, "to": to, "hit": hit}

func _act_iaido(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	c = spend_card(u, idx, c)
	u.attacked = true
	var L := iaido_line(u, c, p)
	u.face = 1 if p.x >= u.x else -1
	u.pose = "throw"; u.pose_t = 16
	Sfx.play("slash")
	for f in 6:
		tracer(L.from.x, L.from.y, L.to.x, L.to.y, Color("e0f4ff"))
		await wait(1)
	var n := int(L.from.distance_to(L.to) / 10.0)
	for k in n:
		var pt: Vector2 = L.from.lerp(L.to, k / float(maxi(1, n)))
		if T.solid(pt.x, pt.y):
			T.carve(pt.x, pt.y, 7, u)
	for o in L.hit:
		damage(o, c.iaido, u, {"melee": true})
		slash_fx(o.x, o.y - o.h / 2.0, 1.6, u.face)
	float_text(u, "IAIDO", Color("e0f4ff"), true)
	await wait(16)

# --- N5 Volta
func magnet_line(u: Unit, c: Dictionary, p: Vector2) -> Dictionary:
	## The bodies a Magnet Gun, Repulsor or Tongue would grab, nearest first.
	var reach: float = c.reach * (1.5 if c.magnet > 0 and u.perk("strongpush") else 1.0)
	var from := hand_pos(u)
	var dir := (p - from).normalized()
	var hit: Array = []
	var end := from + dir * reach
	var d := 8.0
	while d < reach:
		var pt := from + dir * d
		if T.hard(pt.x, pt.y):
			end = pt
			break
		for o in units:
			if o == u or o.dead or o.gone or hit.has(o) or o.is_pickup() or is_boss(o) or o.kind in ["pow", "ride", "hulk", "sticky", "slug", "sentry", "dog", "rivet"]:
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
	c = spend_card(u, idx, c)
	var L := magnet_line(u, c, p)
	u.face = 1 if p.x >= u.x else -1
	Sfx.play("power")
	if vfx != null and not c.get("tongue", false):
		# V12: Repulsor pushes in pink, Magnet pulls in cyan
		vfx.add(SfEnergy.beam(L.from, L.to, vfx.ground_fn(L.to.y), SfEnergy.PINK if c.magnet > 0 else SfEnergy.CYAN, 0.04, 0.1, 2.5))
		await wait(6)
	else:
		for f in 6:
			if c.get("tongue", false):
				tracer(L.from.x, L.from.y, L.to.x, L.to.y, Color("d36ba0"))
			else:
				lightning(L.from, L.to)
			await wait(1)
	if L.hit.is_empty():
		float_text(u, "NOTHING CAUGHT", Color("9aa2ae"))
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
				damage(o, 6, u)
			if u.perk("fieldlock"):
				add_status(o, "supp", 1, u)
	if c.magnet > 0 and u.perk("recoilshield"):
		u.armor += 4
		float_text(u, "+4 ARMOR", Color("9fb4c9"))
	await wait(4)
	await until(settled)

func tesla_arc(u: Unit, c: Dictionary) -> void:
	var n: int = c.tesla + (2 if u.perk("arcjump") else 0) + (2 if ks(u, "teslacoil") else 0)
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
		Sfx.play("ping")
		for f in 4:
			lightning(from, to)
			await wait(1)
		var dm: int = ri(c.dmg[0], c.dmg[1]) + (3 if u.perk("overload") else 0)
		if c.get("od", false):
			vfx.add(SfLightning.impact(to.x, to.y, vfx.ground_fn(to.y), 0.6, 32))
		damage(best, dm, u)
		if c.get("tstun", false) or u.perk("stunbolt"):
			add_status(best, "stun", 1, u)
		from = to
		reach = 220.0 if c.get("od", false) else 140.0
	if hit.is_empty():
		float_text(u, "NO TARGETS", Color("9aa2ae"))
	else:
		u.attacked = true
	await wait(8)

func singularity_at(x: float, y: float, r: float, crush: int, by) -> void:
	var caught: Array = units.filter(func(o): return not o.dead and not o.gone and (o.team == "enemy" or o.kind == "barrel" or o.kind == "fuel") and not is_boss(o) and not o.immovable and not (o.team == "enemy" and Data.ETYPES[o.type].get("static", false)) and Vector2(o.x - x, o.y - o.h / 2.0 - y).length() < r + o.w / 2.0)
	float_at(x, y - 30, "SINGULARITY", Color("c47bff"), true)
	Sfx.play("power")
	var hole = black_hole(x, y, r, 0.35)
	for f in 16:
		for o in caught:
			o.x = lerpf(o.x, x, 0.12)
			o.walk = null
		if hole == null:
			for k in 3:
				var a := randf() * TAU
				part({"x": x + cos(a) * r, "y": y + sin(a) * r * 0.5, "vx": -cos(a) * 3, "vy": -sin(a) * 1.5, "life": 20, "max": 20, "c": Color("c47bff"), "s": 2.0, "g": 0.0})
		await wait(1)
	if hole != null:
		# everything is thrown when the hole bursts
		await wait(maxi(0, hole.ticks_to_burst() - 16))
	shake += 4
	for i in caught.size():
		var o: Unit = caught[i]
		if crush > 0 and o.team == "enemy":
			damage(o, crush, by)
		var dir := signf(o.x - x)
		if dir == 0:
			dir = 1.0 if i % 2 == 0 else -1.0
		fling(o, dir, 7.0, by)
	await wait(6)
	await until(settled)

func black_hole(x: float, y: float, r: float, life: float):
	## V11: a violet black hole over a gravity well or singularity of reach r (cosmetic).
	if vfx == null:
		return null
	var gy: float = vfx.ground_fn(y).call(x)
	var e := SfBlackHole.new(x, y, clampf(r / 9.0, 10.0, 24.0), vfx.ground_fn(y), life, 1.5, MATCOL.get(T.mat(x, gy + 2), Color("6a5a48")))
	vfx.add(e)
	return e

func shockwave(u: Unit, r: float) -> void:
	shake += 5
	Sfx.play("thud")
	part({"ring": true, "x": u.x, "y": u.y - u.h / 2.0, "r": 4.0, "max": r, "life": 16, "c": Color("9fe8ff")})
	for o in units:
		if o == u or o.dead or o.gone or o.team == "squad" or o.is_pickup() or o.kind in ["pow", "slug", "ride", "hulk", "sticky", "sentry", "dog"]:
			continue
		if o.team == "enemy" and Data.ETYPES[o.type].get("static", false):
			continue
		if Vector2(o.x - u.x, o.y - u.y).length() < r:
			fling(o, signf(o.x - u.x) if o.x != u.x else float(u.face), 8.0, u)
	u.attacked = true
	await wait(6)
	await until(settled)

func slingshot(u: Unit) -> void:
	var rk = squad_of("rook")
	var foes := vis_foes().filter(func(e): return not e.heavy)
	if rk == null or foes.is_empty():
		float_text(u, "NO TARGETS", Color("9aa2ae"))
		return
	foes.sort_custom(func(a, b2): return absf(a.x - u.x) < absf(b2.x - u.x))
	var e: Unit = foes[0]
	var nx: float = rk.x + rk.face * (rk.w / 2.0 + e.w / 2.0 + 4)
	var ny = T.stand_y(nx, rk.y - 40)
	lightning(Vector2(u.x, u.y - 14), Vector2(e.x, e.y - e.h / 2.0))
	e.x = nx; e.y = ny if ny != null else rk.y; e.vx = 0; e.vy = 0; e.walk = null
	await wait(8)
	rk.pose = "throw"; rk.pose_t = 16
	Sfx.play("thud")
	damage(e, 12, rk, {"melee": true})
	fling(e, rk.face, 9.0, rk)
	float_text(rk, "SLINGSHOT!", Color("ffb23e"), true)
	await wait(8)
	await until(settled)

# --- N6 Brass
func brass_supply(u: Unit, n: int) -> void:
	for k in n:
		var pool: Array = u.def.pool.filter(func(k2): return k2 != "supplydrop")
		pool.shuffle()
		var opts: Array = []
		for i in mini(3, pool.size()):
			opts.append({"kind": "card", "key": pool[i], "tier": Run.roll_card_tier(pool[i]), "u": u})
		Sfx.play("coin")
		var ch := await ask("supply", "SUPPLY DROP", "Pick a card for %s's hand. It's free this turn." % u.def.name, opts)
		if ch >= 0:
			u.hand.append({"id": -2, "key": opts[ch].key, "tier": opts[ch].tier, "temp": true, "free": true})
			float_text(u, Data.CARDS[opts[ch].key].name.to_upper(), Color("62d26f"), true)
	if u.perk("provisions"):
		for s in squad_alive():
			s.hp = mini(s.max_hp, s.hp + 6)
			float_text(s, "+6 HP", Color("62d26f"))
	if u.perk("stockpile"):
		for s in squad_alive():
			draw_cards(s, 1)
	ui_dirty = true

func beacon_bonus(u: Unit, c: Dictionary) -> int:
	var n := 0
	if c.get("key", "") == "designator":
		n += (1 if u.perk("spotround") else 0) + (2 if ks(u, "fieldphone") else 0)
	if u.perk("ffe"):
		n += 2
	if squad_alive().any(func(s): return s.perk("airsupport")):
		n += 1
	return n

# --- N8 Sable
func can_link(u: Unit, tg, c: Dictionary) -> bool:
	if tg == null or tg.dead or tg.team != "enemy" or is_boss(tg) or tg.fl.has("mind") or Data.ETYPES[tg.type].get("static", false):
		return false
	if tg.hp > 30 and not u.perk("biglink"):
		return false
	return absf(tg.x - u.x) <= c.range and absf(tg.y - u.y) <= 140

func mind_link(u: Unit, tg: Unit, turns: int) -> void:
	tg.fl["mind"] = turns
	tg.active = true
	tg.st.erase("cloak")
	lightning(Vector2(u.x, u.y - u.h), Vector2(tg.x, tg.y - tg.h))
	float_text(tg, "MINDLINKED", Color("c47bff"), true)
	Sfx.play("power")

func brood_call(u: Unit, n: int) -> void:
	banner("BROOD CALL!", Color("9df25c"))
	for k in n:
		var x: float = clampf(u.x + (k - (n - 1) / 2.0) * 30.0 + u.face * 30, cam_x + 20, cam_x + W - 20)
		var y = T.stand_y(x, u.y - 50)
		if y == null:
			continue
		var e := mk_enemy("skitter", x, y)
		e.active = true
		e.fl["mind"] = 1
		e.fl["brood"] = true
		units.append(e)
		dust(x, y, Color("9df25c"), 8)
	Sfx.play("splash")
	await wait(12)

func acid_puddle(x: float, y: float, r: float, by) -> void:
	var potent: bool = by is Unit and by.perk("potent")
	acids.append({"x": x, "y": y, "r": r * (1.5 if potent else 1.0), "turns": 4 if potent else 3, "dmg": 5 if ks(by, "acidgland") else 3, "owner": by})
	if by is Unit and by.perk("dissolve"):
		T.carve(x, y, 20, by)
	Sfx.play("splash")

func minds_tick() -> void:
	## Linked Jackals come back to themselves after the enemy phase; the brood melts away.
	for e in units:
		if e.dead or not e.fl.has("mind"):
			continue
		e.fl.mind -= 1
		if e.fl.mind <= 0:
			e.fl.erase("mind")
			if e.fl.get("brood", false):
				e.gone = true
				e.dead = true
				dust(e.x, e.y, Color("9df25c"), 6)
			else:
				float_text(e, "LINK BROKEN", Color("9aa2ae"))

func classes_enemy_end() -> void:
	minds_tick()

func classes_new_turn() -> void:
	## Turn-start traits and perks of the five new classes.
	for b2 in squad_alive():
		match b2.def.key:
			"brass":
				var others := squad_alive().filter(func(s): return s != b2)
				others.sort_custom(func(a, c2): return absf(a.x - b2.x) < absf(c2.x - b2.x))
				for s in others.slice(0, 2 if b2.perk("inspire") else 1):
					s.energy += 1
					float_text(s, "CHAIN OF COMMAND +1", Color("ffb23e"))
				if b2.perk("leadfront"):
					for s in others:
						if absf(s.x - b2.x) <= 140:
							s.move_left += 40
				if b2.perk("intelrep"):
					var fs := vis_foes()
					fs.sort_custom(func(a, c2): return absf(a.x - b2.x) < absf(c2.x - b2.x))
					if fs.size():
						add_status(fs[0], "mark", 2, b2)
				if round_n == 1 and ks(b2, "radiopack"):
					b2.hand.append({"id": -3, "key": "slugcall", "tier": Data.OD_TIER, "temp": true})
			"kage":
				if round_n == 1 and b2.perk("ambush"):
					add_status(b2, "cloak", 2, b2)
				if b2.perk("freerunning"):
					b2.move_left += 60
			"finch":
				if b2.perk("freefall"):
					b2.move_left += 60
			"sable":
				if b2.perk("domeself"):
					b2.armor += 3
				if ks(b2, "wardencore"):
					b2.dome = maxi(b2.dome, 1)

# ---------------------------------------------------------------- B1-B4: fifth branches for the original four
func _act_handoff(u: Unit, idx: int, c: Dictionary, tg: Unit) -> void:
	## Hand-Off: the card to the right of it (or the left, at the end of the hand) goes to a squadmate.
	var give = null
	if idx + 1 < u.hand.size():
		give = u.hand[idx + 1]
	elif idx > 0:
		give = u.hand[idx - 1]
	spend_card(u, idx, c)
	if give == null or not u.hand.has(give):
		float_text(u, "NOTHING TO PASS", Color("9aa2ae"))
		return
	u.hand.erase(give)
	tg.hand.append(give)
	tracer(u.x, u.y - 24, tg.x, tg.y - 24, Color("53d4e2"))
	float_text(tg, Data.CARDS[give.key].name.to_upper(), Color("53d4e2"), true)
	Sfx.play("select")
	if u.perk("assist"):
		draw_cards(tg, 1)
	if ks(u, "radiohq"):
		tg.energy += 1
		float_text(tg, "+1 ENERGY", Color("ffb23e"))
	await wait(14)

func switch_places(u: Unit, tg: Unit) -> void:
	var a := Vector2(u.x, u.y)
	puff(u.x, u.y - 14, 1.2)
	puff(tg.x, tg.y - 14, 1.2)
	u.x = tg.x; u.y = tg.y
	tg.x = a.x; tg.y = a.y
	u.walk = null; tg.walk = null
	Sfx.play("power", -6)
	float_text(u, "SWITCHEROO", Color("53d4e2"), true)
	await wait(12)

func plant_sticky(x: float, y: float, by, dmg: int, r: float) -> Unit:
	var gy = T.stand_y(x, y - 20)
	if gy == null:
		gy = y
	var sk := mk_unit()
	sk.team = "neutral"; sk.kind = "sticky"; sk.x = x; sk.y = gy; sk.w = 10; sk.h = 6
	if by is Unit and by.perk("bigcharge"):
		r += 10
	sk.loot = {"by": by, "dmg": dmg, "r": r, "n": round_n * 1000 + stickies.size()}
	units.append(sk)
	stickies.append(sk)
	Sfx.play("land", -6)
	return sk

func blow_sticky(sk: Unit, bonus := 0, mul := 1.0) -> void:
	if sk.gone:
		return
	sk.gone = true
	stickies.erase(sk)
	explode(sk.x, sk.y - 4, sk.loot.r * mul * blast_scale(sk.loot.by), sk.loot.dmg + bonus, sk.loot.by)

func clacker(u: Unit) -> void:
	## Clacker: the oldest Sticky Charge blows (Chain Reaction: all of them).
	var mine := stickies.filter(func(o): return o.loot.by == u and not o.gone)
	if mine.is_empty():
		float_text(u, "NO CHARGES OUT", Color("9aa2ae"))
		return
	mine.sort_custom(func(a, b2): return a.loot.n < b2.loot.n)
	var mul := 1.5 if u.fl.get("setforget", false) else 1.0
	u.fl.erase("setforget")
	Sfx.play("tick")
	float_text(u, "CLACK!", Color("ffd23a"))
	await wait(10)
	if u.perk("chainreact"):
		for sk in mine:
			blow_sticky(sk, 4, mul)
			await wait(6)
	else:
		blow_sticky(mine[0], 0, mul)

func sticky_watch() -> void:
	## Sticky Charges blow under a Jackal that steps on them (Tripwire: within 50px).
	for sk in stickies.duplicate():
		if sk.gone:
			stickies.erase(sk)
			continue
		var reach := 50.0 if sk.loot.by is Unit and sk.loot.by.perk("tripwire") else 14.0
		for e in units:
			if e.team == "enemy" and not e.dead and not e.gone and absf(e.x - sk.x) < reach + e.w / 2.0 and absf(e.y - sk.y) < 30:
				float_text(sk, "TRIPPED!", Color("ff4d3d"))
				blow_sticky(sk)
				break

func _act_daisy(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	spend_card(u, idx, c)
	banner("DAISY CHAIN!", Color("ffb23e"))
	var dir := 1.0 if p.x >= u.x else -1.0
	var base: Dictionary = Data.card("stickycharge")
	for k in c.daisy:
		var x: float = u.x + dir * (40.0 + k * 36.0)
		var gy = T.stand_y(x, u.y - 60)
		if gy == null or gy >= WATER_Y - 4:
			continue
		plant_sticky(x, gy, u, base.dmg, base.radius)
		await wait(6)

func can_grab(u: Unit, tg: Unit) -> bool:
	if tg == null or tg.team != "enemy" or tg.dead or is_boss(tg) or tg.is_prop() or Data.ETYPES[tg.type].get("static", false) or tg.weight == "buried":
		return false
	if (tg.heavy or tg.weight == "hover" or tg.type == "brute") and not u.perk("titan"):
		return false
	return true

func hold_fast() -> void:
	## Every frame: a carried Jackal rides on the Wrestler's shoulder.
	for s in squad():
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
	for s in squad():
		if s.held != null:
			var e: Unit = s.held
			e.fl.erase("carried")
			e.x = s.x + s.face * 18
			e.air = true
			s.held = null
			float_text(e, "BROKE FREE", Color("ff7a3d"))
		s.hand = s.hand.filter(func(h): return h.key != "bodythrow")

func _act_grab(u: Unit, c: Dictionary, tg: Unit) -> void:
	u.face = 1 if tg.x >= u.x else -1
	damage(tg, ri(c.dmg[0], c.dmg[1]), u, {"melee": true})
	if tg.dead:
		return
	u.held = tg
	tg.fl["carried"] = u.id
	if u.hang:
		drop_hang(u)
	if not u.hand.any(func(h): return h.key == "bodythrow"):
		u.hand.append({"id": -8, "key": "bodythrow", "tier": Data.base_tier("bodythrow"), "temp": true})
	float_text(tg, "GRABBED!", Color("ffd23a"), true)
	Sfx.play("bonk")
	await wait(10)

func _act_bodythrow(u: Unit, idx: int, c: Dictionary, p: Vector2) -> void:
	spend_card(u, idx, c)
	var e: Unit = u.held
	u.held = null
	e.fl.erase("carried")
	var v := aim_vel(u, p)
	u.face = v.f
	u.pose = "throw"; u.pose_t = 20
	Sfx.play("toss")
	e.x = v.hx; e.y = v.hy + 10
	e.vx = v.vx; e.vy = v.vy; e.air = true; e.walk = null; e.bumped = {u.id: true}; e.last_hit_by = u
	var t0 := t
	await until(func(): return not e.air or e.dead or e.sunk or t - t0 > 300)
	if not e.dead:
		var d: int = c.dmg + (6 if u.perk("bodyslam") else 0) + (6 if ks(u, "luchamask") else 0)
		damage(e, d, u, {"melee": true})
		if ks(u, "luchamask"):
			add_status(e, "stun", 1, u)
		float_text(e, "THROWN!", Color("ffd23a"), true)
		shake += 3
	await wait(8)

func _act_suplex(u: Unit, c: Dictionary, tg: Unit, sc: bool) -> void:
	u.face = 1 if tg.x >= u.x else -1
	tg.fl["carried"] = u.id
	tg.x = u.x; tg.y = u.y - u.h - 4
	tg.vx = 0; tg.vy = 0; tg.walk = null; tg.air = false
	Sfx.play("toss")
	await wait(14)
	tg.fl.erase("carried")
	tg.x = u.x - u.face * 22
	tg.vy = 7.0; tg.vx = 0; tg.air = true; tg.bumped = {u.id: true}; tg.last_hit_by = u
	var t0 := t
	await until(func(): return not tg.air or tg.dead or t - t0 > 120)
	var d := ri(c.dmg[0], c.dmg[1]) + (6 if u.perk("bodyslam") else 0) + (6 if ks(u, "luchamask") else 0)
	if sc:
		d = int(round(d * 1.25))
	damage(tg, d, u, {"melee": true})
	if ks(u, "luchamask"):
		add_status(tg, "stun", 1, u)
	float_text(tg, "SUPLEX!", Color("ffd23a"), true)
	shake += 4
	for k in 6:
		dust(tg.x + randf_range(-12, 12), tg.y)
	await wait(10)

func _act_piledrive(u: Unit, c: Dictionary, tg: Unit) -> void:
	u.face = 1 if tg.x >= u.x else -1
	u.held = tg
	tg.fl["carried"] = u.id
	banner("PILEDRIVER!", Color("ffb23e"))
	Sfx.play("power")
	await leap_to(u, Vector2(u.x, u.y - 70))
	u.vy = 10.0; u.vx = 0; u.air = true; u.jumping = true; u.walk = null
	await until(func(): return not u.air or u.dead)
	u.held = null
	tg.fl.erase("carried")
	tg.x = u.x + u.face * 10
	var gy = T.stand_y(tg.x, u.y - 40)
	tg.y = gy if gy != null else u.y
	damage(tg, ri(c.dmg[0], c.dmg[1]), u, {"melee": true})
	T.carve(tg.x, tg.y + 6, 24, u)
	shake += 10
	Sfx.play("bigboom")
	for e in units:
		if e.team == "enemy" and not e.dead and e != tg and absf(e.x - tg.x) < 80 and absf(e.y - tg.y) < 50:
			add_status(e, "stun", 1, u)
	await wait(14)

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
		make_rex(u)  # N7: Rex deploys at Track's side
	if s.def.key == "gears":
		mount(u, "tank" if ks(u, "treads") else "walker", -1, true)  # N3: Gears deploys in his walker
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
		u.y = hover_y(u, u.x, u.y)

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
	else:
		banner(mission.get("banner", "MISSION %d START!" % (mission_idx + 1)), Color("ffb23e"), mission.name)
	if breach:
		log_msg("BREACH: the Vharr and the Jackals are fighting each other. Each shoots whoever is nearest, so let them.")
	if hud != null and Run.tips_on() and Run.history.is_empty() and not practice() and not tutorial():
		coach_start()
	activate_enemies()
	await wait(60)
	if state == "title":
		start_player_turn()

# ---------------------------------------------------------------- M1-M7: new biomes
const LAVA_MAX := 8      # M5: the most steps the lava climbs before it holds
const ICE_HEAVY := ["brute", "dicokka", "jwalker", "boss", "mortarcrew", "wallshield"]
var lava_k := 0          # M5: steps the lava has climbed since the squad last pushed or made camp
var sweeps: Array = []   # M2 tunnel, M7 taxiing jet: {k, x0, x1, every, left, t0}

func setup_biome() -> void:
	lava_k = 0
	sweeps = []
	if rules.get("tunnel", 0) > 0 and T.cars.size():
		sweeps.append({"k": "tunnel", "x0": 0.0, "x1": float(world_w), "every": int(rules.tunnel), "left": int(rules.tunnel), "t0": -999})
	for r in T.runways:
		var n := int(rules.get("planes", 3))
		sweeps.append({"k": "plane", "x0": r.x0, "x1": r.x1, "every": n, "left": n, "t0": -999})

func biome_round() -> void:
	## End of every enemy phase: the biome's clockwork moves one tick, always on a count you can see.
	# V1: the lava holds still for the first rounds on a screen, the same stall clock as the alert
	if rules.get("lava", 0.0) > 0 and lava_k < LAVA_MAX and rounds_since_scroll > stall_limit():
		lava_k += 1
		float_at(cam_x + W / 2.0, lava_y() - 16, "THE LAVA RISES", Color("ff7a3d"), true)
		Sfx.play("splash")
		lava_eat()
		await wait(24)
	if rules.get("regrow", 0) > 0 and regrow(int(rules.regrow)) > 0:
		float_at(cam_x + W / 2.0, 120, "THE HIVE GROWS BACK", Color("c47bff"), true)
		await wait(16)
	for l in T.lifts:
		l.t -= 1
		if l.t <= 0:
			move_lift(l)
			await wait(16)
	for sw in sweeps:
		sw.left -= 1
		if sw.left <= 0:
			sw.left = sw.every
			await run_sweep(sw)

# --- M1 Frozen Lake
func ice_crack(u: Unit) -> void:
	## A heavy Jackal or any vehicle that stops on the lake crust goes through it.
	if T.lakes.is_empty() or u.dead or u.gone or u.air:
		return
	if not (u.mech != null or (u.team == "enemy" and (u.heavy or ICE_HEAVY.has(u.type)))):
		return
	if T.mat(u.x, u.y + 1) != Terrain.ICE or not T.lakes.any(func(l): return u.x > l[0] and u.x < l[1]):
		return
	float_text(u, "THE ICE BREAKS!", Color("9fe3f0"), true)
	Sfx.play("splash")
	if vfx != null:
		vfx.add(SfIce.new(u.x, u.y, vfx.ground_fn(u.y), clampf(u.w / 40.0, 0.8, 1.6)))
	T.carve(u.x, u.y + 2, 20.0, null)
	u.air = true
	u.walk = null

# --- M4 Deep Mine
func push_cart(c: Unit, src) -> void:
	## Anything that hits a mine cart sends it rolling away from whoever hit it.
	if c.slide != 0 or c.air:
		return
	var dir := 1.0
	if src is Unit and src != c:
		dir = signf(c.x - src.x) if absf(c.x - src.x) > 1 else float(src.face)
	c.slide = dir * 7.0
	c.last_hit_by = src if src is Unit else null
	c.fl["ran"] = {}
	float_text(c, "RUNAWAY CART!", Color("ffd23a"), true)
	Sfx.play("land")

func cart_ram(c: Unit) -> void:
	## A rolling cart runs over every Jackal it reaches: 18 damage and thrown on down the line.
	for o in units:
		if o == c or o.dead or o.gone or o.sunk or o.team != "enemy" or is_boss(o) or c.fl.get("ran", {}).has(o.id):
			continue
		if absf(o.x - c.x) < (o.w + c.w) / 2.0 and o.y > c.y - c.h - 4 and o.y - o.h < c.y + 2:
			c.fl.ran[o.id] = true
			float_text(o, "RUN OVER!", Color("ffd23a"), true)
			damage(o, 18, c.last_hit_by, {"blast": true})
			fling(o, signf(c.slide), 6.0, c.last_hit_by)
			shake += 3

# --- M5 Volcano
func lava_y() -> float:
	return WATER_Y - lava_k * lava_step()

func lava_step() -> float:
	## V2: half steps on level 2 or earlier, so the first volcano a squad meets reaches half as high.
	return float(rules.get("lava", 10.0)) * (0.5 if mission_idx <= 1 and not mission.get("finale", false) and not Run.campaign() else 1.0)

func lava_eat() -> void:
	## The lava burns away wood, ice and rubber below its line, and scorches everything else.
	var r0 := int(ceil(lava_y() / CELL))
	for cy in range(r0, Terrain.WATER_ROW):
		for cx in T.cols:
			var i := cy * T.cols + cx
			var m := T.grid[i]
			if m == 3 or m == Terrain.ICE or m == Terrain.RUBBER:
				T.set_cell(cx, cy, 0)
			elif m != 0:
				T.data[i * 2 + 1] = maxi(T.data[i * 2 + 1], 150)
				T.dirty = true
	T.check_bridges(null)
	for u in units:
		lava_check(u)

func lava_check(u: Unit) -> void:
	if lava_k <= 0 or u.dead or u.gone or u.sunk or u.weight == "hover" or u.kind == "pow" or u.y < lava_y() + 2:
		return
	if u.is_pickup():
		u.gone = true
		return
	if u.is_prop():
		if u.kind == "mine" or u.kind == "cart":
			u.gone = true
		else:
			damage(u, 99, null, {"blast": true})
		return
	float_text(u, "BURNED UP", Color("ff7a3d"), true)
	part({"x": u.x, "y": u.y - 8, "vx": 0.0, "vy": -3.0, "life": 40, "max": 40, "c": Color("ff7a1e"), "s": 4.0, "g": 0.05, "fire": true})
	kill(u, u.last_hit_by if u.last_hit_by is Unit and u.last_hit_by.team == "squad" else null)

func lava_drain() -> void:
	if lava_k > 0:
		lava_k = 0
		float_at(cam_x + W / 2.0, WATER_Y - 20, "THE LAVA DRAINS", Color("ffd23a"), true)

# --- M6 Vharr Hive
func regrow(n: int) -> int:
	## Up to n blown-away blocks on screen grow back, from the bottom up, never inside anyone.
	if T.orig.is_empty():
		return 0
	var c0 := maxi(0, int((cam_x - 80) / CELL))
	var c1 := mini(T.cols - 1, int((cam_x + W + 80) / CELL))
	var live := units.filter(func(u): return not u.dead and not u.gone and not u.sunk)
	var got := 0
	for cy in range(Terrain.WATER_ROW - 1, 0, -1):
		for cx in range(c0, c1 + 1):
			var i := cy * T.cols + cx
			if T.grid[i] != 0 or T.orig[i] == 0:
				continue
			if T.grid[i + T.cols] == 0 and (cx == 0 or T.grid[i - 1] == 0) and (cx == T.cols - 1 or T.grid[i + 1] == 0) and T.grid[i - T.cols] == 0:
				continue
			var px := cx * CELL + 2.0
			var py := cy * CELL + 2.0
			if live.any(func(u): return absf(u.x - px) < u.w / 2.0 + 4 and py > u.y - u.h - 4 and py < u.y + 4):
				continue
			T.set_cell(cx, cy, T.orig[i])
			got += 1
			if got >= n:
				return got
	return got

# --- M7 Carrier Deck
func move_lift(l: Dictionary) -> void:
	## The elevator drops a storey (or comes back up), carrying whoever stands on it.
	var y0: float = l.y_up if l.up else l.y_dn
	var riders := units.filter(func(u): return not u.dead and not u.gone and not u.air and u.x > l.x0 - 2 and u.x < l.x1 + 2 and absf(u.y - y0) < 3)
	T.lift_cells(l, false)
	l.up = not l.up
	T.lift_cells(l, true)
	var y1: float = l.y_up if l.up else l.y_dn
	for u in riders:
		u.y = y1
		u.walk = null
	l.t = l.every
	float_at((l.x0 + l.x1) / 2.0, y1 - 30, "LIFT UP" if l.up else "LIFT DOWN", Color("ffd23a"), true)
	Sfx.play("land")

# --- M2 tunnel and M7 jet
func sweep_hits(sw: Dictionary) -> Array:
	## Who a sweep would hit right now: on a car roof for the tunnel, on the deck in the lane for the jet.
	var out: Array = []
	for u in units:
		if u.dead or u.gone or u.sunk or u.is_pickup() or u.kind == "pow" or u.kind == "loot" or is_boss(u):
			continue
		if sw.k == "tunnel":
			if T.cars.any(func(c): return u.x >= c.x and u.x <= c.x + c.w and u.y <= c.roof + 2 and u.y > c.roof - 80):
				out.append(u)
		elif u.x >= sw.x0 and u.x <= sw.x1 and not u.air and absf(u.y - T.ground_at(u.x)) <= 4:
			out.append(u)
	return out

func run_sweep(sw: Dictionary) -> void:
	var tunnel: bool = sw.k == "tunnel"
	if tunnel:
		banner("TUNNEL!", Color("ff7a3d"), "EVERYONE ON THE ROOFS GETS HIT")
	else:
		banner("JET TAXIING!", Color("ff7a3d"), "CLEAR THE PAINTED LANE")
	Sfx.play("alarm")
	sw.t0 = t
	await wait(30)
	shake += 6
	for u in sweep_hits(sw):
		float_text(u, "TUNNEL!" if tunnel else "JET WASH!", Color("ff7a3d"), true)
		if u.is_prop():
			damage(u, 99, null, {"blast": true})
			continue
		damage(u, 12 if tunnel else 14, null)
		fling(u, -1.0 if tunnel else 1.0, 6.0, null)
	await wait(24)
	await until(settled)

func hazard_word() -> String:
	## What going into the "water" means here.
	if rules.get("train", false):
		return "UNDER THE WHEELS"
	if rules.get("lava", 0.0) > 0:
		return "INTO THE LAVA"
	return ""

# ---------------------------------------------------------------- R2-R6 mid-level events, D3 fun toggles
var crumble := {}        # R3: {x0, x1, x, on} the edge of the stretch that is falling away

func setup_events() -> void:
	crumble = {}
	if T.stretches.is_empty() or mission.get("finale", false) or tutorial():
		return
	var st0: Array = T.stretches[0]
	match mission.get("event", ""):
		"fireteam":
			# R2: two friendly riflemen pinned down in the middle of the first stretch
			# on open ground, not up a tower they could never climb down from
			var spots: Array = []
			var x: float = (st0[0] + st0[1]) / 2.0
			while spots.size() < 2 and x < st0[1]:
				var gy = T.stand_y(x, T.ground_at(x) - 40)
				if gy != null and absf(gy - T.ground_at(x)) < 9:
					spots.append([x, gy])
					x += 26.0
				else:
					x += 8.0
			for sp in spots:
				var x2: float = sp[0]
				var y: float = sp[1]
				var tr := make_sentry(null, x2, y, 20, [3, 4])
				tr.loot["trooper"] = true
				tr.loot["pinned"] = true
				tr.heavy = false
				tr.w = 14; tr.h = 30
				tr.face = 1
			if units.any(func(o): return o.kind == "sentry" and o.loot.get("trooper", false)):
				log_msg("A friendly fire team is pinned down up ahead. Reach them and they join you until camp.")
		"collapse":
			# R3: the second stretch falls away behind the squad
			if T.stretches.size() >= 2:
				crumble = {"x0": T.stretches[1][0] - 60.0, "x1": T.stretches[1][1] + 60.0, "x": T.stretches[1][0] - 60.0, "on": false}
		"dealer":
			# R4: a trader at the end of the first stretch with three items rolled now, shown before you buy
			var x: float = st0[1] - 30.0
			var y = T.stand_y(x, T.ground_at(x) - 40)
			if y != null:
				var d := mk_unit(); d.team = "neutral"; d.kind = "dealer"; d.x = x; d.y = y; d.w = 20; d.h = 30; d.face = -1
				d.loot = {"stock": [Run.roll_item(1), Run.roll_item(1), Run.roll_item(2)]}
				units.append(d)

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

func troopers() -> Array:
	return units.filter(func(o): return o.kind == "sentry" and o.loot.get("trooper", false) and not o.dead and not o.gone)

func check_troopers(u: Unit) -> void:
	## R2: a soldier who reaches the pinned fire team brings them into the fight.
	for tr in troopers():
		if tr.loot.get("pinned", false) and absf(tr.x - u.x) < 140 and absf(tr.y - u.y) < 60:
			for o in troopers():
				o.loot.erase("pinned")
			banner("FIRE TEAM JOINS!", Color("62d26f"), "THEY SHOOT AT THE END OF YOUR TURN UNTIL CAMP")
			Sfx.play("power")
			return

func troopers_follow() -> void:
	## R2: the fire team keeps up just behind whoever is out in front.
	var sq := squad_alive()
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
			var ny = T.stand_y(nx, y - 30)
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
		float_text(tr, "BACK TO THE LINES", Color("62d26f"), true)
		tr.gone = true

func dealer_price(it: Dictionary) -> int:
	return int(round(Run.item_price(it) * Data.DEALER_MUL))

func check_dealer(u: Unit, x0 = null) -> void:
	## R4: walk up to (or past) the arms dealer to see his three items and their prices.
	if u.dead or u.team != "squad" or state != "player":
		return
	var lo := minf(u.x, x0 if x0 != null else u.x) - 44
	var hi := maxf(u.x, x0 if x0 != null else u.x) + 44
	for d in units:
		if d.kind != "dealer" or d.gone or d.x < lo or d.x > hi or absf(d.y - u.y) > 30 or d.loot.get("seen", -1) == round_n:
			continue
		d.loot["seen"] = round_n
		var stock: Array = d.loot.stock
		while stock.size():
			var opts: Array = stock.map(func(it): return Run.item_opt(it, "%d SCRIP" % dealer_price(it)))
			var k := await ask("dealer", "ARMS DEALER", "Fixed prices. You have %d scrip." % Run.scrip, opts)
			if k < 0:
				break
			var it: Dictionary = stock[k]
			if Run.scrip < dealer_price(it):
				float_text(u, "NOT ENOUGH SCRIP", Color("ff7a5a"))
				Sfx.play("deny")
				break
			Run.scrip -= dealer_price(it)
			stock.remove_at(k)
			float_text(u, "%s TO %s" % [Data.item_name(it).to_upper(), Run.add_loot(it).to_upper()], Color("62d26f"), true)
			Sfx.play("coin")
			ui_dirty = true
		return

func crumble_round() -> void:
	## R3: once the squad is into the stretch, the ground behind falls away 120px every round.
	if crumble.is_empty() or crumble.x >= crumble.x1:
		return
	if not crumble.on:
		if not squad_alive().any(func(s): return s.x > crumble.x0 + 80):
			return
		crumble.on = true
		banner("THE GROUND IS GIVING WAY!", Color("ff7a3d"), "IT FALLS 120PX BEHIND YOU EVERY ROUND")
		await wait(30)
		return
	var x0: float = crumble.x
	var x1: float = minf(crumble.x1, x0 + Data.CRUMBLE_STEP)
	crumble.x = x1
	for cx in range(int(x0 / CELL), int(x1 / CELL)):
		for cy in Terrain.WATER_ROW:
			if T.grid[cy * T.cols + cx] != 0:
				if (cx + cy) % 9 == 0:
					debris(cx * CELL + 2, cy * CELL + 2, T.grid[cy * T.cols + cx], true)
				T.set_cell(cx, cy, 0)
	T.check_floating(x1 + 20, 300, 260, null)
	T.check_bridges(null)
	shake += 6
	Sfx.play("bigboom")
	for u in units:
		if not u.dead and not u.gone and u.x >= x0 - 8 and u.x < x1 + 4:
			u.air = true
			u.walk = null
	await wait(20)
	await until(settled)

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

# ---------------------------------------------------------------- helpers
func practice() -> bool:
	return mission.get("practice", false)

# ---------------------------------------------------------------- N6: the optional training drill
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

func tut_clear(key: String) -> bool:
	return tut_marks.get(key, []).all(func(u): return u.dead)

func tut_update() -> void:
	## One step at a time: the sergeant calls in what to do, the step ends when it's done.
	if state != "player" or busy:
		return
	var done := false
	match tut_step:
		TUT_MOVE:
			done = squad_alive().any(func(u): return u.x >= TUT_FLAG_X - 6)
		TUT_SHOOT:
			done = tut_clear("target")
		TUT_CRATE:
			done = tut_clear("crate")
		TUT_THROW:
			# any squad blast passes: the lesson is the throw, and the pair join the fight if they live
			done = tut_clear("group") or tut_blast
		TUT_PUSH:
			done = cam_x > 40
	if done:
		tut_step += 1
		Sfx.play("coin")
	# D1: the sergeant waits until the banner and any faction intro have closed
	var quiet: bool = banners.is_empty() and (hud == null or (hud.coach_queue.is_empty() and hud.coach_box.get_child_count() == 0))
	if quiet and tut_said < tut_step and tut_step < TUT_DONE:
		tut_said = tut_step
		var main = get_tree().current_scene
		if main != null and main.has_method("call_in"):
			main.call_in(Data.TUT_LINES[tut_step].map(func(l): return Run.radio_line("sarge", l, [])))
	# the card a step teaches is always in the selected soldier's hand
	var need: String = {TUT_SHOOT: "rifle", TUT_CRATE: "rifle", TUT_THROW: "frag"}.get(tut_step, "")
	if need != "" and sel != null and not sel.dead and sel.energy < Data.CARDS[need].cost:
		# the selected recruit is spent: hand the lesson to one who can still play it
		var fresh: Array = squad_alive().filter(func(s): return s.energy >= Data.CARDS[need].cost)
		if not fresh.is_empty():
			select_unit(fresh[0])
	if need != "" and sel != null and not sel.dead and (sel.hand.is_empty() or sel.hand[0].key != need):
		# D3: first in the hand, so "press its number" is always 1 (a drawn copy moves up front)
		var at: int = -1
		for i in sel.hand.size():
			if sel.hand[i].key == need:
				at = i
				break
		if card_idx >= 0 and (at < 0 or card_idx < at):
			card_idx += 1
		elif at >= 0 and card_idx == at:
			card_idx = 0
		sel.hand.insert(0, sel.hand.pop_at(at) if at >= 0 else {"id": -2, "key": need, "tier": Data.base_tier(need), "temp": true})
		ui_dirty = true

func practice_round() -> void:
	## D5: no enemy phase at the range. When every dummy is down, a fresh set stands up.
	state = "enemy"
	busy = true
	ui_dirty = true
	await wait(20)
	if not units.any(func(e): return e.team == "enemy" and not e.dead):
		for d in dummies:
			var e := mk_enemy(d[0], d[1], T.stand_y(d[1], 0))
			e.active = true
			units.append(e)
		banner("RANGE RESET", Color("62d26f"))
		await wait(30)
	start_player_turn()

func leave_practice() -> void:
	if state == "over":
		return
	state = "over"
	busy = true
	mission_over.emit(true)

func squad() -> Array:
	return units.filter(func(u): return u.team == "squad")

func squad_alive() -> Array:
	return units.filter(func(u): return u.team == "squad" and not u.dead)

func log_msg(m: String) -> void:
	if debug:
		print("[log r%d] %s" % [round_n, m])
	log_lines.append(m)
	if log_lines.size() > 4:
		log_lines.pop_front()
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
		fat_end(u)

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
					T.carve(fx_, fy_, 4, a if a.team == "squad" else null)
	for s in tr.segs:
		tracer(s[0], s[1], s[2], s[3], (Color("ffcf70") if sc else Color("fff4c0")) if a.team == "squad" else Color("ffb0a0"))
	for p in tr.pings:
		sparks(p.x, p.y, 4)
	if tr.pings.size():
		Sfx.play("ping")
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
			var locked := wall_locked(tg)
			d = maxi(1, int(round(d * (0.1 if locked else 0.25))))
			float_text(tg, "SHIELD WALL" if locked else "SHIELD", Color("c9d1da"))
			sparks(hh.x, hh.y, 6)
		if chute_hit(tg, hh.y):
			continue
		if a.team == "squad":
			tank_hit(tg, hh.dx, a)
		if tg.team == "squad" and a.team == "enemy" and tg.fl.get("deflect", 0) > 0 and not a.dead:
			# Kage's blade sends it back where it came from
			tg.fl.deflect -= 1
			tracer(hh.x, hh.y, a.x, a.y - a.h / 2.0, Color("e0f4ff"))
			float_text(tg, "DEFLECTED", Color("e0f4ff"), true)
			Sfx.play("ping")
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
		T.carve(tr.end.x, tr.end.y, ch, a if a.team == "squad" else null)
		dust(tr.end.x, tr.end.y, MATCOL.get(tr.end.m, Color("c9b38a")))

# ---------------------------------------------------------------- movement
func walk_bounds(u: Unit) -> Vector2:
	if u.team == "squad":
		return Vector2(cam_x + 12, cam_x + W - 16)
	var mn := cam_x + 24
	for s in squad_alive():
		if s.x < u.x and not s.trapped:
			mn = maxf(mn, s.x + 26)
	return Vector2(mn, world_w - 20)

func thin_post(x: float, y: float, dir: int) -> bool:
	## posts and pillars (wood or rock, up to 24px thick) are scenery you walk in front of
	var m := T.mat(x, y)
	if m != 3 and m != 4:
		return false
	for k in range(1, 7):
		if not T.solid(x + dir * k * CELL, y):
			return true
	return false

func blocks(x: float, y: float, dir: int) -> bool:
	return T.solid(x, y) and not thin_post(x, y, dir)

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
				ny -= CELL
				c += 1
			if blocks(nx, ny - 1, dir):
				break
		elif not T.solid(nx, ny):
			while not T.solid(nx, ny) and ny < WATER_Y:
				ny += CELL
			if ny >= WATER_Y:
				break
		var blocked := false
		var inside := false
		var hy := ny - u.h + 2
		while hy < ny - 1:
			if T.solid(nx, hy):
				inside = true
				if blocks(nx, hy, dir):
					blocked = true
					break
			hy += CELL
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
	await until(func(): return u.walk == null or u.dead)

# ---------------------------------------------------------------- damage, adrenaline, xp, death
func give_xp(u, n: int) -> void:
	if u == null or not (u is Unit) or u.team != "squad" or u.dead or n <= 0 or practice() or u.s.has("guest"):
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
		push_cart(tg, src)
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
		amt += flare_bonus()
	if tg.type == "dicokka":
		amt = dicokka_dmg(tg, amt, src, o)
	if tg.team == "squad" and tg.mech != null:
		mech_hit(tg, amt)  # N3/R1: the vehicle takes it
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
		drop_girder(tg, own)
		return
	if tg.kind == "dog":
		rex_hurt(tg, amt)
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
			prime_mine(tg, own, 4)
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
		if ship_plated(tg):
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
			break_pod(tg)
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
	if src is Unit and src.team == "enemy":
		if src.type == "boss":
			return "THE VHARR BOAR" if src.fl.get("vharr", false) else "THE IRON BOAR"
		return "A " + str(Data.ETYPES[src.type].name).to_upper()
	if src is Unit and src == tg:
		return "THEIR OWN BLAST"
	if src is Unit and src.team == "squad":
		return "FRIENDLY FIRE (%s)" % src.def.name.to_upper()
	return "A FALL OR DEBRIS"

const KILL_MOVE := 40  # D1: movement a soldier gets back for each kill on their turn

func kill(tg: Unit, src) -> void:
	if tg.dead:
		return
	if tg.team == "squad" and tg.has_st("zombie") and not tg.sunk and tg.y < lava_y():
		tg.hp = 1  # R6 ZOMBIE: can't go down
		float_text(tg, "UNDEAD!", Color("9df25c"), true)
		return
	if debug and tg.team == "squad":
		print("[down r%d] %s at %d,%d hp %d sunk %s lava %d by %s" % [round_n, tg.def.key, int(tg.x), int(tg.y), tg.hp, tg.sunk, lava_k, (src.team + ":" + (src.type if src.team != "squad" else src.def.key)) if src is Unit else str(src)])
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
		drop_plate(tg, src)
	elif tg.type == "jwalker":
		walker_wreck(tg)
	elif tg.type == "gunship":
		gunship_down(tg)
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
		Sfx.play("scream", -6)
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
			spawn_skitter(tg.x, tg.y)
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
		stats["last_down"] = "%s, BY %s" % [tg.def.name.to_upper(), who_did(tg, src)]
		if tg.s.tags > 0 or mission.get("patrol", false):
			# a dog tag buys their life: out until the next camp, or back next mission.
			# A campaign patrol (M5) never costs a life: an empty-tagged soldier is only knocked out.
			tg.s.tags = maxi(0, tg.s.tags - 1)
			tg.downed = true
			float_text(tg, "DOWN! %d TAG%s LEFT" % [tg.s.tags, "" if tg.s.tags == 1 else "S"], Color("ffb23e"), true)
			var back := "until the next camp" if T.camps.any(func(c): return not c.used) else "for the rest of this fight"
			log_msg("%s is down %s. %d dog tag%s left." % [tg.def.name, back, tg.s.tags, "" if tg.s.tags == 1 else "s"])
		else:
			stats.fallen.append(tg.def.name)
			float_text(tg, "KIA", Color("ff4d3d"), true)
			log_msg("%s is killed in action. No dog tags left." % tg.def.name)
		Sfx.play("bad")
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

# ---------------------------------------------------------------- projectiles
func mk_proj(o: Dictionary) -> Dictionary:
	var p := {"age": 0, "vx": 0.0, "vy": 0.0, "wind": 0.0, "grav": 1.0, "r": 30.0, "dmg": 10, "bounce": false, "fuse": null, "dead": false, "smoke": false, "gas": false, "card": {}, "x0": 0.0, "srad": 64.0, "sturns": 2, "bombs": 3, "cluster": 0, "beacon": false, "trail": false, "mini": false, "owner": null}
	p.merge(o, true)
	return p

func unit_hit(p: Dictionary):
	for u in units:
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
		explode(p.x, p.y, p.r, p.dmg, p.owner)
		land_pod(p.x, p.y, p.get("cargo", ["skitter"]))
		return
	var pc: Dictionary = p.card
	if pc.has("build"):
		build_at(p)
		return
	if pc.get("sticky", false):
		plant_sticky(p.x, p.y, p.owner, p.dmg, p.r)
		return
	if pc.has("flare"):
		flare_at(p.x, p.y - 10, pc.flare + (40.0 if p.owner is Unit and p.owner.perk("brightflare") else 0.0), p.owner)
		return
	if pc.has("singularity"):
		singularity_at(p.x, p.y - 14, pc.singularity, pc.get("crushdmg", 0), p.owner)
		return
	if p.beacon and pc.get("rain", 0) > 0:
		steel_rain(p.x, pc.rain, p.owner)
		if pc.get("barrage", 0) <= 0:
			return
	if p.smoke and pc.get("multi", 0) > 1:
		for k in pc.multi:
			var ox: float = (k - (pc.multi - 1) / 2.0) * p.srad * 1.3
			smokes.append({"x": p.x + ox, "y": p.y - 24, "r": p.srad, "turns": p.sturns, "seed": randf() * 10})
		Sfx.play("splash")
		return
	if pc.get("markall", false):
		for o2 in units:
			if o2.team == "enemy" and not o2.dead and absf(o2.x - p.x) < 170:
				add_status(o2, "mark", 2, p.owner)
	if pc.get("fuelgas", false):
		gases.append({"x": p.x, "y": p.y - 20, "r": 70.0, "turns": 1, "seed": 0.0, "owner": p.owner})
	if p.beacon and pc.get("barrage", 0) > 0:
		var dir := 1.0 if p.owner == null or p.x >= p.owner.x else -1.0
		for k in pc.barrage:
			projs.append(mk_proj({"kind": "bomb", "x": p.x + dir * (k - 1) * 38, "y": -20.0 - k * 26, "vx": 0.0, "vy": 5.0, "r": 46.0, "dmg": 14, "owner": p.owner}))
		float_at(p.x, p.y - 20, "BARRAGE!", Color("ffb23e"), true)
		Sfx.play("alarm")
		return
	if p.owner is Unit and p.owner.team == "squad" and p.owner.perk("rangefinder") and p.dmg > 0:
		p.dmg += 2 * int(absf(p.x - p.x0) / 200.0)
	if p.gas:
		gases.append({"x": p.x, "y": p.y - 20, "r": p.srad, "turns": p.sturns, "seed": randf() * 10, "owner": p.owner})
		Sfx.play("splash")
		float_at(p.x, p.y - 30, "GAS", Color("9be34a"), true)
		return
	if p.smoke:
		smokes.append({"x": p.x, "y": p.y - 24, "r": p.srad, "turns": p.sturns, "seed": randf() * 10})
		Sfx.play("splash")
		for i in 6:
			puff(p.x + randf_range(-30, 30), p.y - randf_range(0, 40), 3.0)
		return
	if p.beacon:
		strikes.append({"x": p.x, "owner": p.owner, "friendly": true, "n": p.bombs})
		float_at(p.x, p.y - 20, "BEACON SET", Color("62d26f"), true)
		Sfx.play("tick")
		return
	if debug:
		print("[proj r%d] %s owner %s dmg%d" % [round_n, p.kind, (p.owner.type if p.owner.team != "squad" else p.owner.def.key) if p.owner is Unit else "null", p.dmg])
	explode(p.x, p.y, p.r, p.dmg, p.owner, pc.get("burnblast", false))
	if pc.has("acid"):
		acid_puddle(p.x, T.ground_at(p.x) if not T.solid(p.x, p.y + 4) else p.y, pc.acid, p.owner)
	if pc.get("junk", false):
		scrap_heap(p.x, p.y, p.owner)
	if pc.has("carve"):
		T.carve(p.x, p.y, pc.carve, p.owner)
	if pc.get("flash", false):
		for o2 in units:
			if o2.team == "enemy" and not o2.dead and Vector2(o2.x - p.x, o2.y - o2.h / 2.0 - p.y).length() < p.r + 10:
				add_status(o2, "stun", 1, p.owner)
	if pc.get("napalm", false):
		for k in range(-3, 4):
			if k != 0:
				booms.append({"t": 6 + absi(k) * 6, "x": p.x + k * 40, "y": p.y - 6, "r": 24.0, "dmg": 4, "owner": p.owner, "burn": true})
	if pc.get("shrapnel", 0) > 0 and p.owner is Unit:
		for k in pc.shrapnel:
			var a: float = -PI + PI * (k + 0.5) / pc.shrapnel
			fire_bullet(p.owner, p.x, p.y - 6, a, {"dmg": [3, 4], "range": 220, "bounce": 0}, false)
	if pc.get("key", "") == "mortar" and p.owner is Unit and p.owner.perk("fireforeffect"):
		strikes.append({"x": p.x, "owner": p.owner, "friendly": true, "n": 1})
		float_at(p.x, p.y - 34, "FIRE FOR EFFECT", Color("ffb23e"))
	if p.cluster:
		for i in p.cluster:
			projs.append(mk_proj({"kind": "frag", "x": p.x, "y": p.y - 8, "vx": (randf() - .5) * 7, "vy": -3 - randf() * 4, "wind": 0.5, "r": 24.0, "dmg": 7, "bounce": true, "fuse": 40 + ri(0, 45), "owner": p.owner, "mini": true}))

func update_proj(p: Dictionary) -> void:
	p.age += 1
	if p.trail and p.age % 2 == 0:
		part({"x": p.x, "y": p.y, "vx": 0.0, "vy": -0.2, "life": 24, "max": 24, "c": Color("ffb23e") if p.kind == "rocket" else Color("9a9a9a"), "s": 3.0, "g": 0.0, "smoke": p.kind != "rocket"})
	if p.get("homing", false) and p.age > 10:
		var best = null
		for e in units:
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
	p.vx += wind * 0.006 * p.wind
	p.vy += grav * p.grav
	if p.grav > 0 and wells.size():
		var wa := well_acc(p.x, p.y)
		p.vx += wa.x; p.vy += wa.y
	var n := maxi(1, int(ceil(Vector2(p.vx, p.vy).length() / 2.0)))
	for i in n:
		var px: float = p.x
		var py: float = p.y
		p.x += p.vx / n
		p.y += p.vy / n
		if p.y > WATER_Y + 4:
			splash(p.x)
			p.dead = true
			return
		if p.x < 0 or p.x > world_w:
			p.dead = true
			return
		var hu = unit_hit(p) if p.age > 2 else null
		if p.get("lizard", false) and hu == null and proj_solid(p, p.x, p.y):
			# Iron Lizard: hug the ground and keep crawling until it meets a body or a tall wall
			var sy = T.stand_y(p.x, p.y - 14)
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
				var rub := T.mat(p.x, p.y) == Terrain.RUBBER
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
	return T.solid(x, y) if p.grav > 0 else T.hard(x, y)

func sim_arc(sx: float, sy: float, vx: float, vy: float, wind_f: float, steps: int) -> Dictionary:
	## Thrown things and jumping bodies both land on grating and chain-link.
	var pts: Array = []
	var x := sx
	var y := sy
	for i in steps:
		vx += wind * 0.006 * wind_f
		vy += grav
		if wells.size():
			var wa := well_acc(x, y)
			vx += wa.x; vy += wa.y
		x += vx
		y += vy
		pts.append(Vector2(x, y))
		if y > WATER_Y or x < 0 or x > world_w or T.solid(x, y):
			return {"pts": pts, "x": x, "y": y, "end": true}
	return {"pts": pts, "x": x, "y": y, "end": false}

func sim_grenade(sx: float, sy: float, vx: float, vy: float, wind_f: float, frames: int) -> Dictionary:
	## A bouncing grenade's whole flight up to its fuse, with the same bounces update_proj gives it.
	var pts: Array = []
	var x := sx
	var y := sy
	for f in frames:
		vx += wind * 0.006 * wind_f
		vy += grav
		if wells.size():
			var wa := well_acc(x, y)
			vx += wa.x; vy += wa.y
		var n := maxi(1, int(ceil(Vector2(vx, vy).length() / 2.0)))
		for i in n:
			var px := x
			var py := y
			x += vx / n
			y += vy / n
			if y > WATER_Y + 4 or x < 0 or x > world_w:
				pts.append(Vector2(x, y))
				return {"pts": pts, "x": x, "y": y, "lost": true}
			if T.solid(x, y):
				var hx := T.solid(x, py)
				var hy := T.solid(px, y)
				var rub := T.mat(x, y) == Terrain.RUBBER
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
		await unstack_squad()
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
	if is_build(c) and ks(u, "magnetglove") and not u.fl.get("built", false):
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
	if is_build(c):
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
	var why := mech_ok(u, c)
	if why != "":
		float_text(u, why, Color("ff7a3d"))
		Sfx.play("deny")
		return
	if c.get("eject", false):
		resolve(func(): await _act_eject(u, idx, c, p))
		return
	if c.type == "AIM":
		resolve(func(): await _act_aim(u, idx, c, p, sc))
		return
	if c.get("bodythrow", false):
		resolve(func(): await _act_bodythrow(u, idx, c, p))
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
			resolve(func(): await _act_girder(u, idx, c, p))
			return
		if c.has("daisy"):
			resolve(func(): await _act_daisy(u, idx, c, p))
			return
		if c.get("zipline", false):
			if not zip_spot(u, c, p).ok:
				float_text(u, "NOWHERE TO LAND", Color("ff7a3d"))
				Sfx.play("deny")
				return
			resolve(func(): await _act_zip(u, idx, c, p))
			return
		if c.has("magnet"):
			resolve(func(): await _act_magnet(u, idx, c, p))
			return
		if c.has("iaido"):
			resolve(func(): await _act_iaido(u, idx, c, p))
			return
		if c.has("dog"):
			var dt := dog_target(u, c, p)
			if not dt.ok:
				float_text(u, dt.why, Color("ff7a3d"))
				Sfx.play("deny")
				return
			resolve(func(): await _act_dog(u, idx, c, p))
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
			await sentry_fire(st)
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
		c.bombs = c.get("bombs", 3) + beacon_bonus(u, c)
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
	projs.append(mk_proj({"kind": "smoke" if c.get("smoke", false) or c.get("gas", false) else ("beacon" if c.get("beacon", false) else ("frag" if fuse != null else "shell")),
		"x": v.hx, "y": v.hy, "vx": v.vx, "vy": v.vy, "wind": wind_of(u, c), "r": r,
		"dmg": int(round((c.get("dmg", 0) + dmg_bonus) * (1.25 if sc else 1.0))), "bounce": c.get("bounce", false), "fuse": fuse,
		"smoke": c.get("smoke", false), "gas": c.get("gas", false), "srad": c.get("srad", 64.0), "sturns": c.get("sturns", 2), "bombs": c.get("bombs", 3),
		"beacon": c.get("beacon", false), "cluster": c.get("cluster", 0), "owner": u, "trail": fuse == null, "card": c, "x0": u.x}))
	await wait(4)

func _act_grapple(u: Unit, idx: int, gs: Dictionary) -> void:
	spend_card(u, idx)
	u.face = 1 if gs.x >= u.x else -1
	Sfx.play("toss")
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
			projs.append(mk_proj({"kind": "frag", "x": u.x, "y": u.y - 10, "vx": (k - 1) * 1.6 + u.vx * 0.3, "vy": 1.0, "r": 34.0 * blast_scale(u), "dmg": 11, "bounce": true, "fuse": 50 + k * 10, "owner": u}))
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
	var sim := sim_walk(u, u.x + dir * d, d)
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
	await walk_along(u, sim.pts)
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
		await release_hounds(u, c, 2)
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
		projs.append(mk_proj({"kind": "rocket", "x": hp_.x, "y": hp_.y, "vx": cos(a) * c.speed, "vy": sin(a) * c.speed, "grav": 0.0, "r": c.radius * (1.2 if sc else 1.0) * blast_scale(u), "dmg": int(round(c.dmg * (1.25 if sc else 1.0))), "owner": u, "trail": true, "homing": c.get("homing", false), "lizard": ks(u, "lizard"), "card": c, "x0": u.x}))
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
	var why := mech_ok(u, c)
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
		await _act_grab(u, c, tg)
		return
	if c.get("suplex", false):
		await _act_suplex(u, c, tg, sc)
		return
	if c.get("piledrive", false):
		await _act_piledrive(u, c, tg)
		return
	if c.has("mindlink"):
		u.attacked = false
		mind_link(u, tg, 2 if ks(u, "psicrown") else 1)
		if u.perk("linkheal"):
			u.hp = mini(u.max_hp, u.hp + 6)
			float_text(u, "+6 HP", Color("62d26f"))
		await wait(14)
		return
	u.face = 1 if tg.x >= u.x else -1
	u.pose = "throw"; u.pose_t = 16
	Sfx.play("slash")
	slash_fx(tg.x, tg.y - tg.h / 2.0, 1.6, u.face)
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
		await _act_handoff(u, idx, c, tg)
		return
	spend_card(u, idx, c)
	if c.get("switch", false):
		await switch_places(u, tg)
	if c.get("guard", false):
		await rex_guard(u, tg)
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
	var why := mech_ok(u, c)
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
		return not vis_foes().any(func(e): return chest.distance_to(Vector2(e.x, e.y - e.h / 2.0)) <= 300.0)
	if c.has("drone"):
		var reach := 2000.0 if c.get("od", false) else 420.0
		return not vis_foes().any(func(e): return absf(e.x - u.x) <= reach)
	if c.get("slingshot", false):
		return squad_of("rook") == null or not vis_foes().any(func(e): return not e.heavy)
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
	if c.get("immovable", false):
		u.immovable = true
		u.heavy = true
	if c.has("ownet"):
		for s in squad_alive():
			s.overwatch += c.ownet
			float_text(s, "OVERWATCH +%d" % c.ownet, Color("53d4e2"))
	if c.get("slug", false):
		call_slug(u)
		if c.has("slugturns"):
			units.back().loot.turns = maxi(units.back().loot.turns, c.slugturns)
	if c.has("squadarmor"):
		for s in squad_alive():
			s.armor += c.squadarmor
			float_text(s, "+%d ARMOR" % c.squadarmor, Color("9fb4c9"))
	if c.get("patch", false):
		patch_job(u)
	if c.get("sync", false):
		banner("SYNCHRONIZE!", Color("53d4e2"))
		for s in squad_alive():
			s.fl["syncfree"] = true
			float_text(s, "NEXT CARD FREE", Color("53d4e2"))
	if c.get("clacker", false):
		await clacker(u)
	if c.get("ridealong", false):
		await ride_along(u)
	if c.has("refit"):
		field_refit(u, c.refit)
	if c.has("blink"):
		await vharr_blink(u, c.blink)
		if u.perk("decoy"):
			add_status(u, "cloak", 2, u)
		if u.perk("blinkstrike"):
			var fs2 := vis_foes()
			fs2.sort_custom(func(a, b2): return absf(a.x - u.x) < absf(b2.x - u.x))
			if fs2.size() and absf(fs2[0].x - u.x) < 60:
				damage(fs2[0], 8, u, {"melee": true})
				u.attacked = true
	if c.has("gwell"):
		await vharr_well(u, c.gwell + (40.0 if u.perk("widewell") else 0.0))
		if u.perk("doublewell"):
			await vharr_well(u, c.gwell + (40.0 if u.perk("widewell") else 0.0))
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
		await fortify(u, c)
	if c.has("nest"):
		for k in c.nest:
			var sx: float = u.x + (k - (c.nest - 1) / 2.0) * 30.0
			var sy = T.stand_y(sx, u.y - 40)
			if sy != null:
				make_sentry(u, sx, sy, 16, [5, 6])
		Sfx.play("power")
	if c.get("whistle", false):
		var rx := rex_ready(u)
		if rx != null:
			Sfx.play("select")
			float_text(u, "HERE, BOY!", Color("e8dcc2"))
			await heel(u, rx)
		if u.fl.get("goodboy", false):
			u.fl.erase("goodboy")
			u.energy += 1
			float_text(u, "+1 ENERGY", Color("ffb23e"))
		draw_cards(u, 2 if u.perk("huntcall") else 1)
	if c.has("hounds"):
		await release_hounds(u, c, c.hounds)
	if c.get("supplyrun", false):
		await supply_run(u)
	if c.has("meddog"):
		banner("MED DOG!", Color("62d26f"))
		Sfx.play("coin")
		for s in squad_alive():
			s.hp = mini(s.max_hp, s.hp + c.meddog)
			s.energy += 1
			float_text(s, "+%d HP" % c.meddog, Color("62d26f"), true)
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
		await drone_runs(u, c)
	if c.get("rigged", false):
		await rig_all(u)
	if c.get("paint", false):
		for e in vis_foes():
			add_status(e, "flared", 2, u)
		var ms = squad_of("moss")
		if ms != null:
			temp_card(ms, "snipe")
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
			temp_card(u, "katana")
	if c.has("freejump"):
		for k in c.freejump:
			temp_card(u, "walljump")
	if c.get("mirror", false):
		var ms2 = squad_of("moss")
		if ms2 != null:
			temp_card(ms2, "ricochet")
			float_text(ms2, "FREE RICOCHET", Color("53d4e2"), true)
	if c.has("tesla"):
		await tesla_arc(u, c)
	if c.has("shockwave"):
		await shockwave(u, c.shockwave)
	if c.get("delivery", false):
		var vv = squad_of("vee")
		if vv != null:
			for k in 2:
				temp_card(vv, "frag", true, {"nowind": true})
			float_text(vv, "2 FREE FRAGS", Color("53d4e2"), true)
	if c.get("slingshot", false):
		await slingshot(u)
	if c.has("supply"):
		await brass_supply(u, c.supply)
	if c.has("brood"):
		await brood_call(u, c.brood)
	if c.has("hivemind"):
		var fs := vis_foes().filter(func(e): return e.hp <= 30 or u.perk("biglink"))
		fs.sort_custom(func(a, b2): return absf(a.x - u.x) < absf(b2.x - u.x))
		for e in fs.slice(0, c.hivemind):
			mind_link(u, e, 2 if ks(u, "psicrown") else 1)
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
		return can_link(u, tg, c)
	if (c.get("grab", false) or c.get("suplex", false) or c.get("piledrive", false)) and not can_grab(u, tg):
		return false
	return tg != null and not tg.dead and (tg.team == "enemy" or tg.is_prop()) and absf(tg.x - u.x) <= c.range + tg.w / 2.0 and absf(tg.y - u.y) <= 30

func ally_valid(u: Unit, tg, c: Dictionary) -> bool:
	if c.get("guard", false) and rex_ready(u) == null:
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
	var w := sim_walk(u, L.x, u.move_left)
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
	var sim := sim_walk(u, tx, u.move_left)
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
	await walk_along(u, pts)
	await check_push(u, x0)

# ---------------------------------------------------------------- screen scrolling
func check_push(u: Unit, x0 = null) -> void:
	check_troopers(u)
	free_varga()
	await check_dealer(u, x0)
	await check_camp(u)
	if pincer.get("on", false):
		set_view(wing(u))
		if wing(u) == "b":
			await follow_b()
			return
	if u.dead or cam_x >= world_w - W:
		return
	if u.x - cam_x > W * 0.72:
		var blk := push_blockers()
		if blk.size():
			# the map only moves on once nothing hostile is left behind the line
			if push_warned != round_n:
				push_warned = round_n
				float_text(u, "CLEAR THE ENEMIES BEHIND FIRST", Color("ff7a5c"), true)
				log_msg("The push zone is locked: %d enem%s still alive behind the line." % [blk.size(), "y" if blk.size() == 1 else "ies"])
			return
		await scroll_to(clampf(u.x - W * 0.5, cam_x, world_w - W), "push", u)

# ---------------------------------------------------------------- W9: the pincer at Iron Harbor
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

func set_view(w: String) -> void:
	## Jump the camera to one half of the pincer. Each half keeps its own camera.
	if not pincer.get("on", false) or pincer.view == w:
		return
	pincer[pincer.view + "_cam"] = cam_tx
	pincer.view = w
	cam_x = float(pincer[w + "_cam"])
	cam_tx = cam_x
	activate_enemies()
	ui_dirty = true

func switch_wing() -> void:
	## The SQUAD A / SQUAD B button: select the other half's first soldier and jump there.
	if not pincer.get("on", false) or state != "player" or busy:
		return
	var w := "b" if pincer.view == "a" else "a"
	var al: Array = squad_alive().filter(func(s): return wing(s) == w)
	if al.size():
		sel = al[0]
		card_idx = -1
	set_view(w)
	Sfx.play("click")

func bar_squad() -> Array:
	## The soldiers the HUD's squad bar shows: on the pincer op, the half on screen.
	if pincer.get("on", false):
		return squad().filter(func(s): return wing(s) == pincer.view)
	return squad()

func follow_b() -> void:
	## Squad B fights right to left: its view slides left as they advance, and the two halves
	## join up once the windows meet.
	var bs: Array = squad_alive().filter(func(s): return wing(s) == "b")
	if bs.is_empty():
		return
	var bx: float = bs.map(func(s): return s.x).min()
	if bx - cam_tx < W * 0.3:
		cam_tx = clampf(bx - W * 0.5, 0, cam_tx)
		await until(func(): return absf(cam_x - cam_tx) < 0.5)
		cam_x = cam_tx
		activate_enemies()
	if cam_tx <= float(pincer.a_cam) + W * 0.6:
		pincer_meet()

func pincer_meet() -> void:
	## The halves meet: one squad of eight, one camera, and the flagship between them.
	var tx: float = maxf(float(pincer.a_cam), cam_tx if pincer.view == "b" else float(pincer.b_cam))
	pincer.on = false
	pincer["met"] = true
	for s in squad():
		s.wing = "a"
	cam_x = minf(cam_x, tx)
	cam_tx = tx
	banner("THE PINCER CLOSES!", Color("62d26f"), "BOTH SQUADS FIGHT AS ONE")
	Sfx.play("start")
	log_msg("Squad A and Squad B have joined up. Finish the flagship together.")
	ui_dirty = true

func push_blockers() -> Array:
	## Enemies still alive on this screen short of the push zone line. While any are left, a push won't scroll.
	var line := cam_x + W * 0.72
	return units.filter(func(e): return e.team == "enemy" and not e.dead and not e.gone and not e.sunk and e.active and not e.fl.get("turned", false) and e.x < line and e.x > cam_x - 10)

func fall_in(who: Unit) -> void:
	## After a push, the squadmates left behind regroup behind the soldier who pushed, for free,
	## and get their full movement back for the rest of the turn.
	var back: Array = squad_alive().filter(func(s): return s != who and not s.downed and s.zip == null and s.x < who.x - 80)
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
					ty = T.stand_y(tx, maxf(0, who.y - lift))
					if ty != null and (ty > WATER_Y - 2 or mine_under(s, tx, ty, 6) != null or (near and absf(ty - who.y) > 160)):
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
		s.move_left = 0.0 if s.has_st("pinned") else maxf(s.move_left, full_move(s))
		float_text(s, "FALL IN!", Color("62d26f"))
	await until(func(): return back.all(func(s): return s.zip == null or s.dead))
	ui_dirty = true

func check_camp(u: Unit) -> void:
	## Reaching a camp with the area clear makes camp: the downed get back up, everyone patches up,
	## and the squad picks one camp perk before moving on.
	if u.dead or u.team != "squad" or state != "player":
		return
	for c in T.camps:
		if c.used or u.x < c.x0 + 40 or u.x > c.x1:
			continue
		var hostile := units.filter(func(e): return e.team == "enemy" and not e.dead and e.active and e.x < c.x1 + 200)
		if hostile.size():
			if not c.get("warned", false):
				c["warned"] = true
				float_text(u, "CLEAR THE AREA TO MAKE CAMP", Color("ffb23e"))
			return
		c.used = true
		await make_camp(c)
		return

func make_camp(c: Dictionary) -> void:
	busy = true
	banner("CAMP", Color("62d26f"), "SAFE FOR NOW")
	lava_drain()
	troopers_leave()
	Sfx.play("levelup")
	await wait(30)
	var i := 0
	for s in squad():
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
			s.x = maxf(c.fire - 40, cam_x + 16) + i * 26
			var sy = T.stand_y(s.x, 0)
			s.y = float(sy) if sy != null else s.y
			s.vx = 0; s.vy = 0; s.air = false; s.walk = null
			s.st = {}
			s.pose = "cheer"; s.pose_t = 60
			float_text(s, "BACK IN THE FIGHT", Color("62d26f"), true)
			log_msg("%s rejoins the squad at camp." % s.def.name)
			i += 1
		elif not s.dead:
			var add := int(ceil(s.max_hp * Data.CAMP_HEAL)) + (5 if Run.hq("mess") >= 1 else 0)
			s.hp = mini(s.max_hp, s.hp + add)
			float_text(s, "+%d" % add, Color("62d26f"))
		if not s.dead and s.def.key == "gears":
			# Grease Monkey: the walker is rebuilt to full at every camp
			if s.mech == null:
				patch_job(s)
			else:
				s.mech.hp = s.mech.max
	await wait(30)
	if c == T.camps[0] and T.yard.size() and mission.has("detours"):
		await pick_detour()
	else:
		await camp_pick(c)
	stats["camps"] = int(stats.get("camps", 0)) + 1
	busy = false
	ui_dirty = true

func camp_pick(c: Dictionary) -> void:
	var opts: Array = Data.CAMP_PICKS.map(func(p): return {"kind": "service", "name": p.name, "text": p.text, "id": p.id})
	var ch := await ask("camp", "MAKE CAMP", "The downed are back on their feet and everyone patched up a little. Pick one more.", opts)
	match opts[maxi(ch, 0)].id:
		"patch":
			for s in squad_alive():
				s.hp = s.max_hp
			Sfx.play("power")
		"upgrade":
			# each soldier picks the card; the grid shows every card already one rarity up
			for s in squad_alive():
				var cands := upgrade_choices(s.s)
				if cands.is_empty():
					continue
				var shown: Array = cands.map(func(cd): return Services.next_tier(cd))
				var k := await ask("camp_up", "%s: FIELD UPGRADE" % s.def.name, "Pick one card to go up a rarity. Shown as it will be.", shown, s)
				if k < 0:
					continue
				var cd: Dictionary = cands[k]
				Run.raise_tier(cd)
				float_text(s, Data.card(cd).name.to_upper(), Color("b48cff"))
			Sfx.play("levelup")
		"cache":
			give_scrip(60, c.fire, T.ground_at(c.fire) - 40, "L6587")
		"quiet":
			alert = 0
			for s in squad_alive():
				s.energy += 1
			Sfx.play("power")

# ---------------------------------------------------------------- camp detours
func detour_text(id: String) -> String:
	var t: String = Data.DETOURS[id].text
	if id == "pow":
		return t % Data.POW_RESCUE_ROUNDS
	if id == "salvage":
		return t % Data.WRECK_SALVAGE
	return t

func detour_pays(id: String) -> String:
	var p: String = Data.DETOURS[id].pays
	return p % Data.COLORS_SALVAGE if id == "colors" else p

func colors_post() -> float:
	## O1: the green post the stolen colors go back to, at the near end of the clearing (never off screen).
	return maxf(detour.x0 + 40, cam_x + 40)

func pick_detour() -> void:
	## The mid-level camp: pick one side job for the clearing ahead, or press on.
	var opts: Array = mission.detours.map(func(id): return {"kind": "service", "title": "DETOUR", "icon": Data.DETOURS[id].icon, "name": Data.DETOURS[id].name, "text": "%s PAYS: %s" % [detour_text(id), detour_pays(id)], "id": id})
	opts.append({"kind": "service", "title": "NO DETOUR", "icon": "ic_boot", "name": "PRESS ON", "text": "Leave the clearing empty and keep moving.", "id": ""})
	var ch := await ask("detour", "PICK A DETOUR", "The clearing past camp has room for one side job. Each pays in a different currency.", opts)
	var id: String = opts[ch].id if ch >= 0 else ""  # skipping the pick means pressing on
	if id != "":
		start_detour(id)

func start_detour(id: String) -> void:
	var x0: float = T.yard[0]
	var x1: float = T.yard[1]
	detour = {"id": id, "x0": x0, "x1": x1, "done": false, "left": Data.POW_RESCUE_ROUNDS, "scav": 0, "mod": ""}
	match id:
		"elite":
			detour.mod = pick_elite(false)
			for sp in [["grunt", 300], ["shield", 400], ["nade", 560], ["brute", 650]]:
				var de := detour_enemy(sp[0], x0 + sp[1], detour.mod)
				if sp[1] == 650:
					de.carry = "bow"  # O2: the bowman; kill him and the Rambo Bow is yours
		"colors":
			for sp in [["grunt", 470], ["shield", 590], ["grunt", 690]]:
				detour_enemy(sp[0], x0 + sp[1], "")
			drop_loot(x0 + 650, T.stand_y(x0 + 650, 0) - 4, {"type": "colors"}, 0.0)
		"pow":
			var pi := randi()
			for dx in [220, 430, 620]:
				var p := mk_unit(); p.team = "neutral"; p.kind = "pow"; p.x = x0 + dx; p.y = T.stand_y(p.x, 0); p.face = -1
				p.pow_name = Data.POW_NAMES[pi % Data.POW_NAMES.size()]; pi += 1
				p.detour = true
				stats.pows_total += 1
				units.append(p)
			detour_enemy("grunt", x0 + 320, "")
			detour_enemy("grunt", x0 + 530, "")
		"salvage":
			for i in 5:
				var w := mk_unit(); w.team = "neutral"; w.kind = "wreck"; w.x = x0 + 130 + i * 125; w.y = T.stand_y(w.x, 0)
				w.w = 34; w.h = 18; w.hp = 1; w.max_hp = 1; w.detour = true
				units.append(w)
		"cache":
			for sp in [["grunt", 300], ["grunt", 470], ["nade", 600]]:
				detour_enemy(sp[0], x0 + sp[1], "")
			var cu := mk_unit(); cu.team = "neutral"; cu.kind = "crate"; cu.x = x0 + 660; cu.y = T.stand_y(cu.x, 0); cu.w = 16; cu.h = 14; cu.hp = 1; cu.max_hp = 1
			units.append(cu)
	var D: Dictionary = Data.DETOURS[id]
	banner(D.name, Color("ffb23e"), "PAYS: " + detour_pays(id))
	log_msg("Detour: %s %s" % [D.name.capitalize(), detour_text(id)])
	stats["detour"] = id
	activate_enemies()
	ui_dirty = true

func detour_enemy(type: String, x: float, mod: String) -> Unit:
	if type == "nade":
		type = "grunt"  # the Bomber is retired
	var u := mk_enemy(type, x, T.stand_y(x, 0))
	u.detour = true
	if mod != "":
		make_elite(u, mod)
	units.append(u)
	return u

func strip_wreck(w: Unit, u: Unit) -> void:
	w.stripped = true
	Run.meta.salvage = int(Run.meta.get("salvage", 0)) + Data.WRECK_SALVAGE
	stats["salvage"] = int(stats.get("salvage", 0)) + Data.WRECK_SALVAGE
	float_text(w, "+%d SALVAGE" % Data.WRECK_SALVAGE, Color("53d4e2"), true)
	dust(w.x, w.y, Color("8a7a6a"), 6)
	Sfx.play("coin")
	log_msg("%s strips a wreck: +%d salvage for HQ." % [u.def.name, Data.WRECK_SALVAGE])

func check_detour() -> void:
	## Pays out a detour the moment its job is done.
	if detour.is_empty() or detour.done:
		return
	match detour.id:
		"elite", "cache":
			if units.any(func(e): return e.detour and e.team == "enemy" and not e.dead):
				return
		"pow":
			if units.any(func(p): return p.detour and p.kind == "pow" and not p.freed):
				return
		"salvage":
			if units.any(func(w): return w.kind == "wreck" and not w.stripped):
				return
		"colors":
			var post := colors_post()
			if not squad_alive().any(func(s): return s.carry == "colors" and absf(s.x - post) < 34):
				return
			for s in squad_alive():
				if s.carry == "colors":
					s.carry = ""
					s.move_left = minf(s.move_left, full_move(s))
	detour.done = true
	busy = true
	await wait(20)
	var cx: float = (detour.x0 + detour.x1) / 2.0
	match detour.id:
		"elite":
			banner("OUTPOST TAKEN!", Color("62d26f"), "EPIC GEAR + %d BIO-PARTS" % Data.ELITE_BIO)
			drop_loot(cx, T.ground_at(cx) - 40, {"type": "item", "item": Run.roll_item(Data.TIER_MAX if Run.hq("armory") >= 3 else 3)})
			Run.meta.bio = int(Run.meta.get("bio", 0)) + Data.ELITE_BIO
			stats["bio"] = int(stats.get("bio", 0)) + Data.ELITE_BIO
			log_msg("The outpost is ours: an Epic crate and %d Bio-parts for the Doc." % Data.ELITE_BIO)
		"pow":
			var slots := Run.fallen_slots()
			if Run.campaign():
				slots = [-1] if Run.company_room() else []
			if slots.size():
				var o: Dictionary = Run.recruit_offers(1)[0]
				var s := Run.hire(slots[0], o)
				banner("ALL PRISONERS FREE!", Color("62d26f"), "%s JOINS THE SQUAD AT HQ" % s.def.name)
				log_msg("%s, a freed %s, signs up. They will be waiting at HQ%s." % [s.def.name, s.def.cls, ", with a training pick at the Barracks" if s.get("train", false) else ""])
			elif not Run.campaign() and Run.reserve.size() < Data.RESERVE_MAX:
				# the squad is full: the freed prisoner signs up and waits in the barracks
				var s := Run.make_recruit(Run.recruit_offers(1)[0])
				Run.reserve.append(s)
				banner("ALL PRISONERS FREE!", Color("62d26f"), "%s WAITS IN THE BARRACKS" % s.def.name)
				log_msg("%s, a freed %s, signs up and waits in the barracks. Swap them in at HQ, or parachute them in with a reinforcement flare." % [s.def.name, s.def.cls])
			else:
				var need: Array = squad_alive().filter(func(u): return u.s.tags < Data.DOG_TAGS)
				need.sort_custom(func(a, b): return a.s.tags < b.s.tags)
				if need.size():
					need[0].s.tags += 1
					banner("ALL PRISONERS FREE!", Color("62d26f"), "%s GETS A DOG TAG BACK" % need[0].def.name)
					float_text(need[0], "+1 DOG TAG", Color("62d26f"), true)
				else:
					banner("ALL PRISONERS FREE!", Color("62d26f"), "+50 SCRIP")
					give_scrip(50, cx, T.ground_at(cx) - 40, "L6738")
		"salvage":
			banner("YARD STRIPPED!", Color("62d26f"), "%d SALVAGE FOR HQ" % int(stats.get("salvage", 0)))
		"colors":
			Run.meta.salvage = int(Run.meta.get("salvage", 0)) + Data.COLORS_SALVAGE
			stats["salvage"] = int(stats.get("salvage", 0)) + Data.COLORS_SALVAGE
			banner("COLORS CAPTURED!", Color("62d26f"), "%d SALVAGE FOR HQ" % Data.COLORS_SALVAGE)
			log_msg("Their battle flag is ours: %d salvage for HQ." % Data.COLORS_SALVAGE)
		"cache":
			banner("CACHE SECURED!", Color("62d26f"), "+80 SCRIP AND A CARD")
			give_scrip(80, cx, T.ground_at(cx) - 40, "L6748")
			await wait(30)
			await supply_drop("SUPPLY CACHE", null)
	Run.save_meta()
	Sfx.play("levelup")
	await wait(40)
	busy = false
	ui_dirty = true

func detour_round() -> void:
	## After each enemy phase: the prisoner clock ticks and scavengers drift into the yard.
	if detour.is_empty() or detour.done:
		return
	if detour.id == "pow":
		detour.left -= 1
		var left: Array = units.filter(func(p): return p.detour and p.kind == "pow" and not p.freed and not p.gone)
		if detour.left <= 0:
			for p in left:
				p.gone = true
				dust(p.x, p.y, Color("b9a27a"), 6)
			detour.done = true
			banner("THE PRISONERS ARE GONE", Color("ff7a3d"), "MOVED OUT BEFORE YOU GOT THERE")
			await wait(40)
		else:
			for p in left:
				float_text(p, "%d ROUND%s LEFT" % [detour.left, "" if detour.left == 1 else "S"], Color("ffb23e"), true)
	elif detour.id == "salvage" and detour.scav < 4 and squad_alive().any(func(s): return s.x > detour.x0 - 200) and units.any(func(w): return w.kind == "wreck" and not w.stripped):
		var x := minf(detour.x1 + 60, cam_x + W - 30)
		var e := mk_enemy("grunt", x, T.stand_y(x, 0))
		e.active = true; e.detour = true
		units.append(e)
		detour.scav += 1
		float_text(e, "SCAVENGER", Color("ff7a3d"), true)

func stall_limit() -> int:
	return STALL_ROUNDS - (1 if Run.threat_on(1) else 0)

func stalled() -> bool:
	## The line has sat on one screen long enough for alert to climb each enemy phase.
	return rounds_since_scroll >= stall_limit()

func scroll_to(tx: float, reason: String, who = null) -> void:
	if pincer.get("on", false) and pincer.view != "a":
		set_view("a")  # only squad A's side of the pincer pushes the screen
		tx = maxf(tx, cam_x)
	tx = clampf(tx, 0, world_w - W)
	if tx <= cam_x + 4:
		return
	cam_tx = tx
	lava_drain()  # V1: any step forward drains the lava, as the volcano's brief says
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
		pincer_meet()
	sweep_loot(cam_x)
	roll_flare()
	activate_enemies()
	await until(settled)
	if reason == "push" and who != null and not who.dead and state == "player":
		await fall_in(who)
	ui_dirty = true

# ---------------------------------------------------------------- reinforcement flare: the barracks parachutes in
func downed_squad() -> Array:
	## Squad soldiers out of this fight (downed or killed) whose place a reinforcement can take.
	return units.filter(func(u): return u.team == "squad" and u.dead and not u.gone and not u.s.has("guest"))

func flare_on_field() -> bool:
	return units.any(func(o): return o.kind == "loot" and not o.gone and o.loot.type == "flare") or para_queue.size() > 0

func roll_flare(force := false) -> Unit:
	## A new screen sometimes holds a reinforcement flare, but only while someone is down and
	## somebody waits in the barracks to answer it.
	if downed_squad().is_empty() or Run.barracks_pool().is_empty() or flare_on_field():
		return null
	if not force and randf() >= Data.FLARE_CHANCE:
		return null
	for k in 12:
		var x := cam_x + W * 0.45 + randf() * W * 0.35
		var sy = T.stand_y(x, T.ceil_at(x) + 12 if T.ceiling else 0)
		if sy == null or sy > WATER_Y - 4:
			continue
		var f := drop_loot(x, sy - 30.0, {"type": "flare"}, 0.3)
		float_at(x, sy - 50.0, "REINFORCEMENT FLARE", Color("62d26f"), true)
		log_msg("A reinforcement flare up ahead. Grab it to parachute soldiers in from the barracks.")
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
		float_text(u, "NOBODY TO CALL IN", Color("9aa2ae"))
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
		var ch := await ask("reinforce", "CALL IN REINFORCEMENTS  %d OF %d" % [picked.size() + 1, n],
			"Who jumps in for %s? %s" % [takes.def.name, "%s goes home to the barracks to recover." % takes.def.name if takes.downed else "They take the fallen soldier's place."], opts)
		if ch < 0:
			break
		picked.append(left[ch])
	if picked.is_empty():
		log_msg("The flare burns out. Nobody jumps.")
		return
	busy = true
	banner("REINFORCEMENTS!", Color("62d26f"), "%d SOLDIER%s INBOUND" % [picked.size(), "" if picked.size() == 1 else "S"])
	Sfx.play("start")
	for k in picked.size():
		var out: Unit = downed[k]
		evacuate(out)
		var s: Dictionary = picked[k]
		Run.swap_in(s, out.s)
		var x := clampf(u.x - 30 + k * 34, cam_x + 30, cam_x + W - 30)
		var nu := deploy_unit(s, x)
		nu.face = 1
		nu.energy = 0
		nu.move_left = 0
		if not T.ceiling and s.def.key != "gears":
			# under a chute from above the screen; Gears' walker and tunnel levels just walk in
			nu.y = -30.0 - k * 40
			nu.air = true
			nu.para = true
			nu.vy = 0.0
		float_text(nu, "REPORTING IN", Color("62d26f"), true)
		log_msg("%s jumps in for %s." % [s.def.name, out.def.name])
	ui_dirty = true
	for i in 300:
		if not units.any(func(o): return o.team == "squad" and o.para and not o.gone):
			break
		await wait(1)
	await until(settled)
	await wait(20)
	busy = false
	ui_dirty = true

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
	for o in units:
		if o.kind == "dog" and o.loot.get("by") == out:
			o.gone = true  # Rex goes home with Track
	if sel == out:
		var al := squad_alive()
		sel = al[0] if al.size() else null
		card_idx = -1

func sweep_loot(edge: float) -> void:
	## Loot the squad left behind (or that sank) goes straight to the global inventory (L8).
	var n := 0
	for u in units:
		if u.kind == "loot" and not u.gone and (u.x < edge or u.sunk):
			u.gone = true
			stash_payload(u.loot)
			n += 1
	if n:
		log_msg("%d item%s left behind went to the stash." % [n, "s" if n > 1 else ""])

func stash_payload(p: Dictionary) -> void:
	match p.type:
		"item":
			Run.add_loot(p.item)
			stats.loot += 1
		"scrip":
			Run.scrip += p.n
			stats.scrip += p.n
			if debug:
				print("[scrip] %d stash" % p.n)
		"relic":
			Run.add_gear(p.id, Data.TIER_MAX)
		"trophy":
			if not Run.trophies.has(p.name):
				Run.trophies.append(p.name)

func drag_stragglers() -> void:
	var al := squad_alive()
	for s in al:
		var lane := cam_x + 16 + al.find(s) * 40
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
				ny = T.stand_y(nx, maxf(0, s.y - lift))
				if ny != null and mine_under(s, nx, ny, 6) != null:
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
				float_text(s, "KEEP UP!", Color("e8dcc2"))

func activate_enemies() -> void:
	for e in units:
		if e.team != "enemy" or e.dead or e.active:
			continue
		if in_play(e.x, 40) or (e.fl.get("hunt", false) and e.x < cam_x + W + 700):
			e.active = true
			meet(e)
			if e.fl.get("lead", false):
				banner("YOU ARE BEING HUNTED", Color("c47bff"), "AN ELITE %s IS STALKING THE SQUAD" % Data.ETYPES[e.type].name.to_upper())
				Sfx.play("alarm")
				log_msg("Something elite is tracking you through this stretch. Bring it down: it pays like an elite outpost.")
			if e.type == "vgate":
				banner("VHARR GATE!", Color("c47bff"), "ONE ALIEN COMES THROUGH EVERY TURN")
				Sfx.play("alarm")
				log_msg("A Vharr gate is open ahead. Blast it, or drop something heavy on it.")
			if e.fl.get("outbreak", false):
				banner("THRALL OUTBREAK", Color("9df25c"), "AN OVERSEER IS TAKING THE JACKAL CAMP")
				log_msg("An Overseer is turning that Jackal camp into Thralls, one a turn. Kill it fast and the rest turn on the Vharr.")
			if e.type == "radio" and radio_t == null:
				radio_t = 3 + jammer_rounds()
				log_msg("A radioman is calling for backup. Paratroopers in %d rounds unless you drop him." % radio_t)
			if e.type == "queen":
				banner("WARNING!!", Color("c47bff"), "THE BURROW QUEEN STIRS")
				Sfx.play("alarm")
				log_msg("Something huge is moving under the sand. Only blasts reach her down there: hit her when she surfaces, and bring the ruins down on her head.")
			if e.type == "hiveship" and not boss_active:
				boss_active = true
				banner("WARNING!!", Color("c47bff"), "HIVE SHIP OVERHEAD")
				Sfx.play("alarm")
				log_msg("A Vharr HIVE SHIP blots out the sky. Shoot its hull plates off the tethers and drop them on whatever is under it. Blasts in its belly always hurt.")
			if e.type == "boss" and not boss_active:
				boss_active = true
				if e.fl.get("vharr", false):
					banner("WARNING!!", Color("c47bff"), "VHARR BOAR APPROACHING")
					log_msg("The flagship BOAR rolls in refit with Vharr tech: a dome over the turret and a tongue. Crushing and melee go through the dome.")
				else:
					banner("WARNING!!", Color("ff4d3d"), "ROOKIE BOAR APPROACHING" if e.fl.get("rookie", false) else "IRON BOAR APPROACHING")
					log_msg("The IRON BOAR rolls in. Something heavy is hanging over it...")
				Sfx.play("alarm")

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
	if hud == null or not Run.tips_on():
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

func post_action() -> void:
	refresh_mounts()
	await leg_check()
	var front: Array = squad_alive().filter(func(s): return not s.air and not s.trapped)
	front.sort_custom(func(a, b): return a.x > b.x)
	if front.size() and not boss_dead:
		await check_push(front[0])
	while pow_queue.size():
		var q: Dictionary = pow_queue.pop_front()
		if q.pow.fl.get("defector", false):
			sign_defector(q.pow)
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
	await check_detour()
	while loot_queue.size():
		var lq: Dictionary = loot_queue.pop_front()
		if lq.u.dead:
			Run.add_loot(lq.item)
			continue
		await offer_item(lq.u, lq.item)
	while para_queue.size():
		await call_reinforcements(para_queue.pop_front())
	while lvl_queue.size():
		var u: Unit = lvl_queue.pop_front()
		await wait(20)
		await level_up(u)
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
		victory()
		return
	if await job_ends():
		return
	start_hold()
	if tutorial() and tut_step >= TUT_FIGHT and not units.any(func(e): return e.team == "enemy" and not e.dead):
		await until(settled)
		victory()
		return
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

# ---------------------------------------------------------------- O2-O6: campaign op jobs
func job() -> String:
	return mission.get("job", "push")

func job_spot(x: float) -> float:
	## Nearest dry, pit-free ground to x, for a prisoner, a dump or the truck.
	for k in 40:
		for sx in [x + k * 16.0, x - k * 16.0]:
			if sx > 160 and sx < world_w - 60 and T.stand_y(sx, T.ground_at(sx) - 40) != null and not T.pits.any(func(p): return sx > p[0] - 24 and sx < p[1] + 24):
				return sx
	return x

func trap_varga() -> void:
	## T6: on his last stand the colonel starts deep in the fort, pinned down with his garrison. He
	## can't act until someone reaches him; if he falls before that, he fell.
	if mission.get("story", "") != "varga":
		return
	for u in squad():
		if u.s.get("guest", "") != "varga":
			continue
		var x := job_spot(world_w * 0.7 + 40)
		var y = T.stand_y(x, T.ground_at(x) - 40)
		if y == null:
			return
		u.x = x; u.y = y; u.face = -1
		u.trapped = true
		log_msg("Colonel Varga is pinned down deep in the fort with his men. Fight through to him and he joins the fight.")

func free_varga() -> void:
	## T6: a squadmate close enough to the colonel breaks him out.
	for v in squad_alive():
		if not v.trapped:
			continue
		if squad_alive().any(func(o): return o != v and not o.trapped and absf(o.x - v.x) < 180 and absf(o.y - v.y) < 140):
			v.trapped = false
			v.face = -1
			float_text(v, "ABOUT TIME, IRON COMPANY", Color("ff7a3d"), true)
			log_msg("Colonel Varga is out. He fights with you from here.")
			Sfx.play("select")
			ui_dirty = true

func place_job() -> void:
	## Lays out the op's objective: prisoners, supply dumps, the truck or the marked officer.
	match job():
		"rescue":
			for f in [0.45, 0.7, 0.9]:
				var x := job_spot(world_w * f)
				var u := mk_unit(); u.team = "neutral"; u.kind = "pow"; u.x = x; u.y = T.stand_y(x, T.ground_at(x) - 40); u.face = -1
				u.pow_name = Data.POW_NAMES[randi() % Data.POW_NAMES.size()]
				u.fl["job"] = true
				stats.pows_total += 1
				units.append(u)
		"demolish":
			for f in [0.4, 0.65, 0.9]:
				var x := job_spot(world_w * f)
				var u := mk_unit(); u.team = "neutral"; u.kind = "dump"; u.x = x; u.y = T.stand_y(x, T.ground_at(x) - 40); u.w = 30; u.h = 24
				u.hp = Data.TARGET_HP; u.max_hp = u.hp; u.heavy = true; u.immovable = true
				units.append(u)
		"escort":
			var x := job_spot(275.0)  # just ahead of the squad line (50-215), so nobody deploys hidden behind it
			var u := mk_unit(); u.team = "neutral"; u.kind = "truck"; u.x = x; u.y = T.stand_y(x, T.ground_at(x) - 40); u.w = 56; u.h = 32; u.face = 1
			u.hp = Data.TRUCK_HP; u.max_hp = u.hp; u.heavy = true; u.immovable = true
			units.append(u)
		"hunt":
			var foes := units.filter(func(e): return e.team == "enemy" and not e.dead and e.type != "boss" and e.type != "hiveship" and e.type != "queen")
			foes.sort_custom(func(a, b): return a.x > b.x)
			if foes.is_empty():
				return
			var q: Unit = foes[0]
			if q.elite == "":
				make_elite(q, pick_elite(faction(q) == "vharr"))
			q.hp *= 2
			q.max_hp = q.hp
			var taken: Array = Run.camp.get("nemeses", []).map(func(n): return n.name) if Run.campaign() else []
			var names: Array = Data.QUARRY_NAMES.filter(func(n): return not taken.has(n))
			q.fl["quarry"] = (names if names.size() else Data.QUARRY_NAMES)[randi() % (names.size() if names.size() else Data.QUARRY_NAMES.size())]
		"hold":
			job_st = {"on": false, "left": Data.HOLD_PHASES}

func place_nemesis() -> void:
	## W3: an officer who got away on an earlier op is back: the farthest foe, with a new elite trick
	## and more health for every escape. WANTED over their head like a hunt's target.
	var nem: Dictionary = mission.get("nemesis", {})
	if nem.is_empty():
		return
	var foes := units.filter(func(e): return e.team == "enemy" and not e.dead and not is_boss(e) and not e.fl.has("quarry") and e.type != "radio" and not Data.ETYPES[e.type].get("static", false))
	if foes.is_empty():
		return
	foes.sort_custom(func(a, b): return a.x > b.x)
	var q: Unit = foes[0]
	var tricks := Data.ELITES.keys().filter(func(k): return Data.ELITES[k].get("vharr", false) == (faction(q) == "vharr") and k != str(nem.get("elite", "")))
	make_elite(q, tricks[randi() % tricks.size()] if tricks.size() else pick_elite(faction(q) == "vharr"))
	q.hp = int(q.hp * (2.0 + Data.NEMESIS_HP * int(nem.rank)))
	q.max_hp = q.hp
	q.fl["quarry"] = Run.nemesis_name(nem)
	q.fl["nemesis"] = nem.name
	stats["nemesis"] = Run.nemesis_name(nem)

func truck():
	for u in units:
		if u.kind == "truck":
			return u
	return null

func job_left() -> String:
	## The HUD line for the op's objective, or "" on a push.
	match job():
		"rescue":
			var n := units.filter(func(p): return p.fl.get("job", false) and p.freed).size()
			return "RESCUE: %d OF 3 PRISONERS FREE" % n
		"demolish":
			return "DEMOLISH: %d OF 3 DUMPS DOWN" % (3 - units.filter(func(d): return d.kind == "dump" and not d.dead).size())
		"hold":
			if job_st.get("on", false):
				return "HOLD: %d MORE ENEMY PHASE%s" % [int(job_st.left), "" if int(job_st.left) == 1 else "S"]
			return "HOLD: REACH THE FAR END"
		"escort":
			var tr = truck()
			if tr == null:
				return ""
			return "ESCORT: TRUCK %d/%d HP, %d%% OF THE WAY" % [maxi(0, tr.hp), tr.max_hp, int(clampf(tr.x / (world_w - 150.0), 0, 1) * 100)]
		"hunt":
			for e in units:
				if e.fl.has("quarry"):
					return "HUNT: %s %s" % [e.fl.quarry, "IS DOWN" if e.dead else ("SPOTTED" if e.active else "IS OUT THERE")]
	return ""

func job_done() -> bool:
	match job():
		"rescue":
			return not units.any(func(p): return p.fl.get("job", false) and p.kind == "pow" and not p.freed)
		"demolish":
			return not units.any(func(d): return d.kind == "dump" and not d.dead)
		"hold":
			return job_st.get("on", false) and int(job_st.left) <= 0
		"escort":
			var tr = truck()
			return tr != null and not tr.dead and tr.x >= world_w - 150
		"hunt":
			return not units.any(func(e): return e.fl.has("quarry") and not e.dead)
	return false

func job_ends() -> bool:
	## Wins the op when its job is done, or fails it when the truck is lost. True if the battle is over.
	if job() == "push" or won or lost:
		return false
	var tr = truck()
	if tr != null and tr.dead:
		lost = true
		state = "over"
		busy = true
		banner("THE TRUCK IS GONE", Color("ff4d3d"), "OP FAILED. THE SQUAD FALLS BACK")
		Sfx.play("bad")
		sync_back()
		await wait(110)
		mission_over.emit(false)
		return true
	if job_done():
		await until(settled)
		victory()
		return true
	return false

func start_hold() -> void:
	## O4: the hold starts once the squad stands at the far end of the map.
	if job() != "hold" or job_st.get("on", false) or cam_x < world_w - W - 2:
		return
	if not squad_alive().any(func(s): return s.x > world_w - W * 0.6):
		return
	job_st.on = true
	banner("HOLD THE LINE!", Color("ffd23a"), "SURVIVE %d ENEMY PHASES. THEY COME FROM BOTH SIDES" % int(job_st.left))
	Sfx.play("alarm")

func hold_waves() -> void:
	## O4: while holding, Jackals come in from both edges at the start of every enemy phase.
	if job() != "hold" or not job_st.get("on", false) or int(job_st.left) <= 0:
		return
	var xs := [minf(world_w - 20.0, cam_x + W - 30), minf(world_w - 42.0, cam_x + W - 52), cam_x + 30]
	for i in xs.size():
		var px: float = xs[i]
		var y = T.stand_y(px, T.ground_at(px) - 40)
		if y == null:
			continue
		var e := mk_enemy("nade" if i == 1 and mission_idx >= 2 else "grunt", px, y)
		e.active = true
		units.append(e)
	float_at(cam_x + W / 2.0, 90, "THEY'RE COMING!", Color("ff7a3d"), true)

func job_round() -> void:
	## After each enemy phase: the hold clock ticks, and the truck takes fire and rolls on.
	match job():
		"hold":
			if job_st.get("on", false) and int(job_st.left) > 0:
				job_st.left = int(job_st.left) - 1
				if int(job_st.left) > 0:
					banner("HOLDING", Color("ffd23a"), "%d MORE ENEMY PHASE%s" % [int(job_st.left), "" if int(job_st.left) == 1 else "S"])
					await wait(30)
		"escort":
			var tr = truck()
			if tr == null or tr.dead:
				return
			# Jackals right next to the truck shoot it up
			for e in units.filter(func(e): return e.team == "enemy" and not e.dead and e.active and absf(e.x - tr.x) < 90).slice(0, 3):
				damage(tr, 4, e)
			if tr.dead:
				return
			if units.any(func(e): return e.team == "enemy" and not e.dead and e.x > tr.x and e.x - tr.x < 260 and e.x < cam_x + W + 40):
				float_text(tr, "BLOCKED: CLEAR THE ROAD", Color("ffb23e"), true)
				await wait(20)
				return
			var nx := minf(tr.x + Data.TRUCK_STEP, minf(cam_x + W - 70, world_w - 60.0))
			var ford := false
			while nx < world_w - 60 and not truck_road(nx, tr.y):
				nx += 16  # rolls over a hole or open water to the far side
				ford = true
			if nx <= tr.x + 4 or (nx > cam_x + W - 30 and not ford):
				float_text(tr, "WAITING FOR THE SQUAD", Color("9fb4c9"))
				await wait(20)
				return
			float_text(tr, "ROLLING", Color("62d26f"))
			rounds_since_scroll = 0  # the truck sets the pace on an escort: while it rolls, the line isn't stalled
			var x0: float = tr.x
			for i in 20:
				tr.x = lerpf(x0, nx, (i + 1) / 20.0)
				var y = T.stand_y(tr.x, T.ground_at(tr.x) - 40)
				if y != null:
					tr.y = y
				tr.anim += 1
				await wait(1)

func truck_road(x: float, from_y: float) -> bool:
	## Somewhere the truck can stand: dry, and not down in a hole well below where it is now.
	var y = T.stand_y(x, T.ground_at(x) - 40)
	return y != null and y < from_y + 40

func job_reward() -> void:
	## A finished job pays on top of the usual: scrip, plus a recruit, a crate or a trophy.
	var j := job()
	if mission.get("bonus", "") != "":
		# W6: each kind of bonus op pays its own way
		match str(Data.BONUS_OPS[mission.bonus].get("pay", "epic")):
			"salvage":
				Run.meta.salvage = int(Run.meta.get("salvage", 0)) + Data.BONUS_SALVAGE
				stats["salvage"] = int(stats.get("salvage", 0)) + Data.BONUS_SALVAGE
				log_msg("The yard's parts are ours: %d Salvage for HQ." % Data.BONUS_SALVAGE)
			"defector":
				if Run.company_room():
					var used: Array = Run.roster.map(func(x): return x.def.name)
					var names: Array = Data.CALLSIGNS.filter(func(c): return not used.has(c))
					var d := Run.enlist(Run.spec_offer("defector", names[randi() % names.size()] if names.size() else "TURNCOAT"))
					log_msg("%s, a Jackal Defector, signs up with the company." % d.def.name)
				else:
					Run.meta.salvage = int(Run.meta.get("salvage", 0)) + Data.BONUS_SALVAGE
					stats["salvage"] = int(stats.get("salvage", 0)) + Data.BONUS_SALVAGE
					log_msg("The company is full, so the defectors hand over %d Salvage instead." % Data.BONUS_SALVAGE)
			"crash":
				log_msg("The wreck is held. Every alien killed here counts double at the Alien Lab.")
			_:
				var bx: float = squad_alive()[0].x if squad_alive().size() else cam_x + W / 2.0
				drop_loot(bx, T.ground_at(bx) - 40, {"type": "item", "item": Run.roll_item(3)})
				stats["bonus_gear"] = true
	if j == "push":
		return
	Run.scrip += Data.JOB_PAY
	stats.scrip += Data.JOB_PAY
	stats["job_pay"] = Data.JOB_PAY
	match j:
		"rescue":
			if Run.campaign() and Run.company_room():
				var s := Run.enlist(Run.recruit_offers(1)[0])
				stats["job_note"] = "%s, one of the freed prisoners, joins the company." % s.def.name
		"hunt":
			for e in units:
				if e.fl.has("quarry"):
					drop_loot(e.x, e.y - 20, {"type": "item", "item": Run.roll_item(3)})
					stats["job_note"] = "%s carried Epic gear." % e.fl.quarry
		"escort":
			Run.meta.salvage = int(Run.meta.get("salvage", 0)) + 2
			stats["salvage"] = int(stats.get("salvage", 0)) + 2
			stats["job_note"] = "The truck brought 2 salvage home."
		"demolish", "hold":
			var tk := Data.ELITE_BIO
			Run.meta.bio = int(Run.meta.get("bio", 0)) + tk
			stats["bio"] = int(stats.get("bio", 0)) + tk
			stats["job_note"] = "%d Bio-parts from the field." % tk

# ---------------------------------------------------------------- B5: Vharr tech in the squad's hands
func vharr_blink(u: Unit, reach: float) -> void:
	## Blink Pack: step out of the air right behind the nearest enemy, facing it.
	var foes := units.filter(func(e): return e.team == "enemy" and not e.dead and not e.gone and absf(e.x - u.x) <= reach and not is_boss(e))
	foes.sort_custom(func(a, b): return absf(a.x - u.x) < absf(b.x - u.x))
	for e in foes:
		var side := 1 if e.x >= u.x else -1
		var nx: float = e.x + side * (e.w / 2.0 + 16)
		var ny = T.stand_y(nx, e.y - 40)
		if ny == null or nx < cam_x + 10 or nx > cam_x + W - 10:
			continue
		Sfx.play("power")
		if vfx != null:
			await teleport(u, Vector2(nx, ny), -side)
		else:
			for k in 6:
				puff(u.x + randf_range(-8, 8), u.y - randf_range(0, 30), 1.5)
			u.x = nx
			u.y = ny
			u.vx = 0; u.vy = 0; u.air = false; u.walk = null
			u.face = -side
			for k in 6:
				puff(u.x + randf_range(-8, 8), u.y - randf_range(0, 30), 1.5)
		float_text(u, "BLINK", Color("c47bff"), true)
		await wait(10)
		return
	float_text(u, "NOTHING TO BLINK TO", Color("9aa2ae"))

func vharr_well(u: Unit, r: float) -> void:
	## Gravity Grenade: a Warden's well on the biggest bunch of enemies within reach, pulling them in.
	var foes := units.filter(func(e): return e.team == "enemy" and not e.dead and not e.gone and absf(e.x - u.x) < 460 and e.x > cam_x and e.x < cam_x + W)
	var best = null
	var best_n := -1
	for e in foes:
		var n := foes.filter(func(o): return absf(o.x - e.x) < r).size()
		if n > best_n:
			best = e
			best_n = n
	if best == null:
		float_text(u, "NO TARGETS", Color("9aa2ae"))
		return
	var well := {"x": best.x, "y": best.y - 20.0, "r": r, "by": u, "foes": true}
	float_at(well.x, well.y - 40, "GRAVITY WELL", Color("c47bff"), true)
	Sfx.play("power")
	await pull_well(well)
	if u.perk("crushwell"):
		for e in vis_foes():
			if absf(e.x - well.x) < r:
				damage(e, 5, u)

func relay_waves() -> void:
	## O4: while a relay is being held, Jackals pour in from the right at the start of each enemy phase.
	for r in units.filter(func(o): return o.kind == "relay" and o.loot.hold >= 1 and o.loot.hold < Data.RELAY_HOLD):
		var x := minf(world_w - 20.0, cam_x + W - 30)
		for k in 2:
			var px := x - k * 22
			var e := mk_enemy("grunt", px, T.stand_y(px, 0))
			e.active = true
			units.append(e)
		float_at(x - 10, T.ground_at(x) - 60, "RELAY WAVE", Color("ff7a3d"), true)

func call_slug(by: Unit) -> void:
	## The SV-001 drops in beside the caller and stays for one round.
	var sl := mk_unit()
	sl.team = "ally"; sl.kind = "slug"; sl.heavy = true
	sl.x = clampf(by.x + 40, cam_x + 60, cam_x + W - 120); sl.y = -60.0; sl.air = true; sl.vy = 4.0
	sl.w = 64; sl.h = 40; sl.hp = 99; sl.max_hp = 99; sl.face = 1
	sl.last_hit_by = by
	sl.loot = {"turns": 2 if Run.hq("motor") >= 2 else 1, "by": by}
	units.append(sl)
	banner("SV-001 SLUG!", Color("62d26f"), "METAL SLUG ON THE FIELD")
	Sfx.play("power")
	shake += 6

func slug_act(sl: Unit) -> void:
	## Rolls forward crushing whatever is in front, then shells the three nearest Jackals.
	banner("SLUG ATTACK", Color("62d26f"))
	sl.rushing = true; sl.bumped = {}; sl.air = true; sl.vx = 6.5; sl.vy = -3.2; sl.walk = null
	# it can roll off a ledge into the water, and step() never lands a sunk unit
	await until(func(): return not sl.air or sl.sunk or sl.gone or sl.dead)
	sl.rushing = false
	if sl.sunk or sl.gone or sl.dead:
		return
	var foes: Array = units.filter(func(e): return e.team == "enemy" and not e.dead and e.x > cam_x - 20 and e.x < cam_x + W + 40)
	foes.sort_custom(func(a, b2): return absf(a.x - sl.x) < absf(b2.x - sl.x))
	for e in foes.slice(0, 3):
		var mx := sl.x + 30
		var my := sl.y - 34
		var a := atan2(e.y - e.h / 2.0 - my, e.x - mx)
		Sfx.play("rocket")
		projs.append(mk_proj({"kind": "rocket", "x": mx, "y": my, "vx": cos(a) * 11, "vy": sin(a) * 11, "grav": 0.0, "r": 40.0, "dmg": 16, "owner": sl.loot.by, "trail": true}))
		await wait(16)
	await until(settled)

func consume_od(u: Unit) -> void:
	for i in u.hand.size():
		var c: Dictionary = u.hand[i]
		if c.get("od", false) and not c.has("duo") and not c.get("temp", false):
			u.hand.remove_at(i)
			break
	u.adr = 0

func draw_cards(u: Unit, n: int) -> void:
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
	troopers_follow()
	free_varga()
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
	vehicles_new_turn()
	classes_new_turn()
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
		call_slug(al0[0])
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
	var autoload := units.any(func(o): return o.kind == "sentry" and not o.dead and o.loot.by is Unit and o.loot.by.perk("autoloader"))
	resolve(func():
		await dogs_new_turn()
		if autoload:
			await sentries_fire()  # Autoloader: the sentries open the round too
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
	elif transform_bonus(k, u):
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
	enemy_phase()

func enemy_phase() -> void:
	if practice():
		await practice_round()
		return
	if tutorial() and tut_step < TUT_FIGHT:
		# the drill's targets never shoot back
		state = "enemy"
		busy = true
		ui_dirty = true
		await wait(20)
		start_player_turn()
		return
	state = "enemy"
	release_holds()
	if squad_alive().any(func(h): return h.perk("netcall")):
		for s in squad_alive():
			s.overwatch = maxi(s.overwatch, 1)
	busy = true
	ui_dirty = true
	banner("ENEMY PHASE", Color("ff4d3d"))
	await wait(45)
	relay_waves()
	hold_waves()
	for m in units.filter(func(e): return e.elite == "medic" and not e.dead and e.active):
		for e in units:
			if e.team == "enemy" and not e.dead and e != m and e.hp < e.max_hp and absf(e.x - m.x) < 140:
				e.hp = mini(e.max_hp, e.hp + 4)
				float_text(e, "+4", Color("62d26f"))
	tick_statuses("enemy")
	for u in units:
		if u.dome > 0:
			u.dome -= 1
	await until(settled)
	if strikes.size():
		var friendly := strikes.filter(func(s): return s.get("friendly", false))
		banner("AIRSTRIKE!", Color("62d26f") if friendly.size() == strikes.size() else Color("ff4d3d"))
		Sfx.play("alarm")
		for s in strikes:
			var n: int = s.get("n", 3) if s.get("friendly", false) else 1
			for k in n:
				var ox: float = 0.0 if n == 1 else (k - (n - 1) / 2.0) * 34.0
				projs.append(mk_proj({"kind": "bomb", "x": s.x + ox, "y": -20.0 - k * 30, "vx": 0.0, "vy": 5.0, "r": 48.0, "dmg": 15, "owner": s.get("owner", null)}))
			await wait(14)
		strikes = []
		await until(settled)
		await wait(10)
	if not ambush.is_empty() and not ambush.done and squad_alive().any(func(q): return q.x >= ambush.x - 120):
		await pod_ambush()
	for sl in units.filter(func(u): return u.kind == "slug" and not u.gone):
		await slug_act(sl)
	await sentries_fire()
	var armed := units.filter(func(u): return u.kind == "charge" and not u.dead and not u.gone and not u.primed)
	if armed.size():
		for c in armed:
			c.primed = true
			booms.append({"t": 4, "x": c.x, "y": c.y - 4, "r": 48.0, "dmg": 16, "owner": null, "barrel": c})
		await until(settled)
		await wait(10)
	var es := units.filter(func(u): return u.team == "enemy" and u.active and not u.dead)
	es.sort_custom(func(a, b): return a.x < b.x)
	for e in es:
		if e.dead or squad_alive().is_empty() or boss_dead:
			break
		if not in_play(e.x, 60) and not e.fl.get("hunt", false):
			continue
		if pincer.get("on", false):
			set_view(wing_at(e.x))  # W9: the camera jumps to whichever half of the pincer this enemy is in
		await until(settled)
		if e.dead:
			continue
		if e.has_st("stun"):
			e.st.erase("stun")
			float_text(e, "STUNNED", Color("ffd23a"), true)
			await wait(20)
			continue
		acting = e
		if squad_alive().any(func(h): return h.perk("hairtrigger") and h.overwatch > 0):
			await overwatch_check(e)
			if e.dead:
				continue
		await enemy_act(e)
		if not e.dead and alpha_near(e):
			await until(settled)
			float_text(e, "ALPHA!", Color("ffd23a"), true)
			await wait(10)
			await enemy_act(e)
		e.st.erase("supp")
		await until(settled)
		await wait(10)
	acting = null
	while pow_queue.size():
		var q2: Dictionary = pow_queue.pop_front()
		if q2.pow.fl.get("defector", false):
			sign_defector(q2.pow)
			continue
		score += 500
		stats.pows += 1
	await check_detour()
	await detour_round()
	await job_round()
	if squad_alive().is_empty():
		game_over()
		return
	if boss_dead:
		await until(settled)
		victory()
		return
	if await job_ends():
		return
	for s in smokes:
		s.turns -= 1
		for u in squad_alive():
			var doc := squad_alive().any(func(h): return h.perk("smokedoc"))
			if doc and Vector2(u.x - s.x, u.y - u.h / 2.0 - s.y).length() < s.r:
				u.hp = mini(u.max_hp, u.hp + 3)
				float_text(u, "+3 HP", Color("62d26f"))
	smokes = smokes.filter(func(s): return s.turns > 0)
	tick_acids()
	for g in gases:
		g.turns -= 1
		if ks(g.owner, "weathervane"):
			var near = null
			for e in units:
				if e.team == "enemy" and not e.dead and (near == null or absf(e.x - g.x) < absf(near.x - g.x)):
					near = e
			if near != null:
				g.x += clampf(near.x - g.x, -36, 36)
		else:
			g.x += wind * 5
	gases = gases.filter(func(g): return g.turns > 0)
	for f in units.filter(func(u): return u.kind == "fuel" and u.leak != null and not u.primed and not u.gone):
		f.leak -= 1
		if f.leak <= 0:
			f.primed = true
			var mul := 2.0 if f.leak_by != null and f.leak_by.perk("chain") else 1.0
			booms.append({"t": 6, "x": f.x, "y": f.y - 15, "r": 84.0, "dmg": int(20 * mul), "owner": f.leak_by, "barrel": f})
			banner("FUEL TANK!", Color("ff7a3d"))
			await until(settled)
			await wait(10)
		else:
			float_text(f, "LEAKING %d" % f.leak, Color("ffd23a"), true)
	if squad_alive().is_empty():
		game_over()
		return
	# alert only climbs when you stall; the radioman's clock is what brings fresh bodies.
	# Digging in on a HOLD job is the order, not a stall.
	if not (job() == "hold" and job_st.get("on", false)):
		rounds_since_scroll += 1
	var before := alert
	var calls := 0
	if stalled():
		alert = mini(10, alert + 1)
	var radios := units.filter(func(u): return u.type == "radio" and u.active and not u.dead)
	if radios.is_empty():
		radio_t = null
	else:
		if radio_t == null:
			radio_t = 3 + jammer_rounds()
		radio_t -= 1
		if radio_t <= 0:
			calls = 1
			radio_t = 3 + jammer_rounds()
			alert = mini(10, alert + 1)
			var r: Unit = radios[0]
			part({"x": r.x, "y": r.y - 30, "vx": 0.0, "vy": -6.0, "life": 80, "max": 80, "c": Color("ff4d3d"), "s": 5.0, "g": 0.08, "fire": true})
	stats.max_alert = maxi(stats.max_alert, alert)
	if alert > before and [3, 6, 10].any(func(v): return before < v and alert >= v):
		banner("ALERT %d" % alert, Color("ff4d3d"), "AIR SUPPORT AUTHORIZED" if alert >= 10 else ("THEY KNOW YOU ARE HERE" if alert >= 6 else "THE JACKALS ARE ORGANIZING"))
		Sfx.play("alarm")
		await wait(50)
	if rounds_since_scroll > stall_limit() and alert >= 6 and not boss_dead and randf() < 0.4:
		calls += 1
	if calls and not boss_dead and mission_idx == 0 and not breach and not T.ceiling:
		await plane_drop(1 + alert / 4)  # E3: the Jackals' own backup comes by plane
		calls = 0
	if calls and not boss_dead:
		var n := 1 + alert / 4
		var shields := 0
		for i in n:
			var drop: Array = ["grunt", "grunt", "shield", "sapper"] if mission_idx == 0 else ["skitter", "blinker", "shield", "sapper"]
			if shields > 0:
				drop.erase("shield")  # one riot shield per drop, so a stall doesn't wall the screen with them
			var type: String = pick(drop)
			if type == "shield":
				shields += 1
			var e := mk_enemy(type, cam_x + W - 60 - randf() * 240, -30.0 - i * 40)
			e.active = true; e.heavy = false; e.air = true; e.para = true
			if T.ceiling:
				# M4: no sky to drop from, so they come up the tunnel from the far end
				var ey = T.stand_y(e.x, T.ceil_at(e.x) + 12)
				e.y = ey if ey != null else T.ground_at(e.x)
				e.para = false
			units.append(e)
		banner("REINFORCEMENTS!", Color("ff7a3d"))
		log_msg("Paratroopers dropping in. Shoot them on the way down, and get the radioman next time.")
		await wait(40)
	if alert >= 10:
		var tg := squad_alive()
		tg.shuffle()
		for s in tg.slice(0, 2):
			strikes.append({"x": s.x + ri(-16, 16), "owner": null})
		banner("AIRSTRIKE INBOUND", Color("ff4d3d"), "MOVE OFF THE MARKERS")
		Sfx.play("alarm")
		await wait(40)
	await biome_round()
	await crumble_round()
	classes_enemy_end()
	await leg_check()
	if squad_alive().is_empty():
		game_over()
		return
	await unstack_squad()
	start_player_turn()

func unstack_squad() -> void:
	## Q4: two squadmates parked on one spot (a recoil, a blast, a fall): the one that isn't selected
	## steps aside to the nearest free spot, so nobody hides behind a teammate. The step is free.
	for _pass in 4:
		var sq := squad_alive().filter(func(o): return not o.air and o.walk == null and o.zip == null and o.drill == null and o.mech == null and not o.hang and not o.sunk)
		var moved := false
		for a in sq:
			for c in sq:
				if moved or a.id >= c.id or absf(a.x - c.x) >= 10 or absf(a.y - c.y) >= 20:
					continue
				var mover: Unit = a if c == sel else c
				for d in [16.0, -16.0, 32.0, -32.0, 48.0, -48.0]:
					var nx: float = mover.x + d
					if nx < cam_x + 14 or nx > cam_x + W - 14:
						continue
					var sim := sim_walk(mover, nx, absf(d) + 8)
					if sim.pts.is_empty() or absf(sim.x - nx) > 3 or absf(sim.y - mover.y) > 24 or mine_under(mover, sim.x, sim.y, 6) != null:
						continue
					if sq.any(func(o): return o != mover and absf(o.x - sim.x) < 10 and absf(o.y - sim.y) < 20):
						continue
					await walk_along(mover, sim.pts)
					moved = true
					break
		if not moved:
			return

func best_shot(e: Unit, targets: Array, rng: float):
	var best = null
	if Run.intel == "fog" or Run.intel == "blizzard":
		rng *= 0.7
	rng *= rules.get("sight", 1.0)
	for tg in targets:
		if tg.team == "squad" and not targetable(e, tg):
			continue
		var d := dist(e, tg)
		if d > rng:
			continue
		var vis := visibility(e, tg)
		if not vis:
			continue
		var sc: float = vis * 30 - d / 10 + (-10 if tg.armor else 0) + (tg.max_hp - tg.hp) * 0.5 + (500 if tg == taunter else 0) + (300 if hunted(tg) else 0)
		if best == null or sc > best.sc:
			best = {"t": tg, "vis": vis, "sc": sc}
	return best

func enemy_shoot(e: Unit, tg: Unit, spec: Dictionary) -> void:
	e.st.erase("cloak")
	if await guard_tackle(e, tg):
		return
	var shots: int = spec.get("shots", 1)
	for s in shots:
		if tg.dead or e.dead:
			break
		e.face = 1 if tg.x >= e.x else -1
		var m := muzzle(e)
		var pts := visible_points(m.x, m.y, tg)
		var py: float = pick(pts) if pts.size() else tg.y - tg.h / 2.0
		var err := maxf(0.015, 0.075 - (10 if e.elite == "veteran" else alert) * 0.005) + tg.dodge * 0.002
		if tg.has_st("roll"):
			# J3: the soldier tucked into a roll; this one goes over their head
			tg.st.erase("roll")
			py = tg.y - tg.h - 16
			err = 0.0
			float_text(tg, "ROLLED UNDER", Color("e8dcc2"))
		var ang := atan2(py - m.y, tg.x - m.x) + gauss() * err
		if e.type == "boss":
			e.aim_a = clampf(atan2(-(py - m.y), -(tg.x - m.x)), -0.4, 0.6)
		e.gun_target = atan2(sin(ang), cos(ang) * e.face)
		Sfx.play("mg" if shots > 1 else "shot")
		e.muzzle = 4
		e.muzzle_kind = "mg" if shots > 1 else "shot"
		e.pose = "recoil"; e.pose_t = 6
		fire_bullet(e, m.x, m.y, ang, {"dmg": spec.dmg, "range": spec.get("range", 460) + 240, "bounce": 0}, false)
		await wait(7 if shots > 1 else 14)

func overwatch_check(e: Unit) -> void:
	if e.fl.has("mind"):
		return
	for s in squad_alive():
		if s.overwatch <= 0 or e.dead:
			continue
		if dist(s, e) <= 520 and visibility(s, e) > 0:
			s.overwatch -= 1
			float_text(s, "OVERWATCH!", Color("53d4e2"), true)
			await wait(10)
			s.face = 1 if e.x >= s.x else -1
			var m := muzzle(s)
			var pts := visible_points(m.x, m.y, e)
			var py: float = pts[0] if pts.size() else e.y - e.h / 2.0
			var ang := atan2(py - m.y, e.x - m.x) + gauss() * 0.02
			s.gun_target = atan2(sin(ang), cos(ang) * s.face)
			Sfx.play("shot")
			s.muzzle = 4
			s.muzzle_kind = "shot"
			var oc := Data.card("rifle")
			oc["forcehead"] = s.fl.get("ow_crit", false)
			oc["boomhit"] = ks(s, "claymore")
			fire_bullet(s, m.x, m.y, ang, oc, s.adr >= 50)
			await wait(16)

func enemy_advance(e: Unit, tx: float, budget: float, stop = null) -> void:
	## walk toward tx; vault walls up to 64px, leap gaps over water, brutes smash through.
	var E: Dictionary = Data.ETYPES[e.type]
	if e.has_st("supp"):
		budget *= 0.5
	var left := budget
	var k := 0
	while k < 5 and left > 6 and not e.dead and not e.air:
		k += 1
		var sim := sim_walk(e, tx, left)
		var pts: Array = sim.pts
		var cut := false
		if stop != null:
			var i := 0
			while i < pts.size():
				var ox := e.x
				var oy = e.y
				e.x = pts[i][0]
				e.y = pts[i][1]
				var ok: bool = stop.call()
				e.x = ox
				e.y = oy
				if ok:
					pts = pts.slice(0, i + 1)
					cut = true
					break
				i += 5
		await walk_along(e, pts)
		left -= pts.size() * 2
		await overwatch_check(e)
		if e.dead or cut:
			return
		if absf(e.x - tx) < 6 or left <= 6:
			return
		var dir := int(signf(tx - e.x))
		var ax := e.x + dir * 6
		if not T.solid(ax, e.y + 2):
			# a drop we would not walk into: water or a pit. leap it if there is ground within reach
			var land = null
			var d := 28
			while d <= 116:
				var y = T.stand_y(e.x + dir * d, maxf(0, e.y - 60))
				if y != null and y < WATER_Y - 4 and y > e.y - 50:
					land = d
					break
				d += 4
			if land == null:
				return
			e.face = dir
			e.vx = dir * land / 46.0
			e.vy = -5
			e.air = true
			e.leaping = true
			float_text(e, "JUMP", Color("e8dcc2"))
			await until(func(): return not e.air or e.dead or e.sunk or e.gone)
			left -= land
			continue
		var top = null
		var hh := 4
		while hh <= 140:
			if not T.solid(ax, e.y - hh):
				var room := true
				var yy: float = e.y - hh - e.h + 2
				while yy < e.y - hh:
					if T.solid(ax, yy):
						room = false
						break
					yy += CELL
				if room:
					top = hh
					break
			hh += 4
		if top != null and top <= (140 if E.get("climb", false) else 64):
			e.face = dir
			e.vx = 0
			e.vault = {"y": e.y - top - 3, "vx": dir * 1.8}
			e.vy = -sqrt(2 * grav * (top + 18))
			e.air = true
			e.leaping = true
			await until(func(): return not e.air or e.dead or e.sunk or e.gone)
			left -= top + 20
			continue
		if E.get("smash", false):
			e.face = dir
			float_text(e, "SMASH!", Color("ff7a3d"), true)
			Sfx.play("thud")
			shake += 4
			e.pose = "throw"; e.pose_t = 14
			await wait(10)
			T.carve(e.x + dir * 16, e.y - e.h * 0.3, 16, e)
			T.carve(e.x + dir * 16, e.y - e.h * 0.8, 16, e)
			await until(settled)
			left -= 30
			continue
		return

func lob(e: Unit, tg: Unit, dmg: int, r: float, err_mul: float) -> bool:
	e.st.erase("cloak")
	e.face = 1 if tg.x >= e.x else -1
	var sx := e.x + e.face * 6
	var sy := e.y - e.h + 6
	var sol = solve_arc(sx, sy, tg.x, tg.y - 4, 1, 13)
	if sol == null:
		return false
	var err := maxf(0.025, 0.11 - alert * 0.009) * err_mul
	var k := 1 + (randf() - .5) * err * 2
	var ang := (randf() - .5) * err
	var c := cos(ang)
	var s := sin(ang)
	e.pose = "throw"; e.pose_t = 24
	await wait(8)
	Sfx.play("toss")
	var cl := 0
	if e.has_st("cluster"):
		cl = 3
		e.st.cluster -= 1
		if e.st.cluster <= 0:
			e.st.erase("cluster")
	projs.append(mk_proj({"kind": "egren", "x": sx, "y": sy, "vx": (sol.vx * c - sol.vy * s) * k, "vy": (sol.vx * s + sol.vy * c) * k, "wind": 1.0, "r": r, "dmg": int(round(dmg * (1 + alert * 0.06))), "owner": e, "cluster": cl}))
	await wait(6)
	return true

func jet_roost(e: Unit):
	## J5: the highest roof a Jet Jackal can reach this turn, on screen, nearest first on a tie.
	var reach: float = Data.ETYPES[e.type].jet
	var best = null
	var x := e.x - reach
	while x <= e.x + reach:
		if x > cam_x + 30 and x < cam_x + W - 30:
			var y = T.stand_y(x, 0)
			var yl = T.stand_y(x - 8, 0)
			var yr = T.stand_y(x + 8, 0)
			var flat: bool = y != null and yl != null and yr != null and absf(yl - y) <= 4 and absf(yr - y) <= 4
			if flat and y < WATER_Y - 8 and not units.any(func(o): return o != e and not o.dead and not o.gone and o.team != "neutral" and absf(o.x - x) < 14 and absf(o.y - y) < 20):
				if best == null or y < best.y - 6 or (absf(y - best.y) <= 6 and absf(x - e.x) < absf(best.x - e.x)):
					best = Vector2(x, y)
		x += 12
	return best

func jet_fly(e: Unit, dest: Vector2) -> void:
	## Burn up above the roof, drift over and drop onto it. Hit in flight and the pack cuts out.
	e.jetting = true
	e.walk = null
	e.air = true
	e.face = 1 if dest.x >= e.x else -1
	Sfx.play("rocket", -6)
	var over := false
	for f in 300:
		await wait(1)
		if e.dead or not e.jetting:
			break
		# climb to just above the roof first, then slide over and settle onto it
		var ty: float = dest.y - 40
		var want_vy := clampf((ty - e.y) * 0.08, -3.5, 2.0)
		var want_vx := 0.0
		if e.y < dest.y - 20 or absf(e.x - dest.x) < 40:
			want_vx = clampf((dest.x - e.x) * 0.06, -3.0, 3.0)
		e.vx = move_toward(e.vx, want_vx, 0.35)
		e.vy = move_toward(e.vy, want_vy, 0.35) - grav  # the pack cancels gravity while it burns
		e.air = true
		if absf(e.x - dest.x) < 3 and absf(e.y - ty) < 12:
			over = true
			e.x = dest.x
			break
		if t % 2 == 0:
			part({"x": e.x - e.face * 6, "y": e.y - 12, "vx": (randf() - .5) * 0.6, "vy": 1.6 + randf(), "life": 14, "max": 14, "c": pick([Color("ffd23a"), Color("ff7a3d")]), "s": 2.0, "g": 0.0, "fire": true})
		if f % 24 == 12:
			await overwatch_check(e)
	if e.jetting and not e.dead:
		e.jetting = false
		if over:
			e.vx = 0.0
			e.vy = 0.0
	await until(func(): return not e.air or e.dead or e.sunk or e.gone)

func jetter_act(e: Unit) -> void:
	var E: Dictionary = Data.ETYPES[e.type]
	var r = jet_roost(e) if not e.hold else null
	if r != null and r.y < e.y - 24:
		float_text(e, "JETS!", Color("53d4e2"))
		await jet_fly(e, r)
	elif not e.hold:
		var tg = nearest_squad(e)
		if tg != null:
			await enemy_advance(e, tg.x + (E.prefer * 0.5 if tg.x < e.x else -E.prefer * 0.5), E.speed)
	if e.dead or e.air:
		return
	var best = best_shot(e, foes_of(e), E.range)
	if best != null:
		await wait(6)
		await enemy_shoot(e, best.t, E)

func jackal_nade(e: Unit) -> bool:
	## A Jackal that grabbed a grenade kit throws it at the nearest soldier.
	if not e.st.has("nades") or faction(e) != "jackal":
		return false
	var tg = nearest_squad(e)
	if tg == null or absf(tg.x - e.x) > 420:
		return false
	e.st.erase("nades")
	float_text(e, "FIRE IN THE HOLE!", Color("ff7a3d"))
	return await lob(e, tg, 11, 36, 1.0)

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

func engineer_build(e: Unit) -> bool:
	var tg = nearest_squad(e)
	if tg == null:
		return false
	var dir := int(signf(tg.x - e.x))
	if dir == 0:
		dir = -1
	var bx := e.x + dir * 22
	var g = T.stand_y(bx, e.y - 40)
	if g == null or absf(g - e.y) > 12:
		return false
	var y: float = g - 20
	while y < g:
		if T.solid(bx, y):
			return false  # already walled
		y += 4
	e.face = dir
	float_text(e, "BUILDING", Color("d6a02f"))
	Sfx.play("thud")
	e.pose = "throw"; e.pose_t = 16
	await wait(16)
	T.fill_r(bx - 8, g - 20, 16, 24, 2)
	dust(bx, g - 10, Color("c9c2b0"), 8)
	for u in units:
		if u.dead or u.gone:
			continue
		var k := 0
		while T.solid(u.x, u.y - 2) and k < 8:
			u.y -= CELL
			k += 1
	e.built = 2
	return true

func enemy_act(e: Unit) -> void:
	var E: Dictionary = Data.ETYPES[e.type]
	var sq := foes_of(e)
	if sq.is_empty() or e.air:
		return
	if e.type == "boss":
		await boss_act(e)
		return
	if e.type == "hiveship":
		await hiveship_act(e)
		return
	if e.type == "shipplate":
		return
	if e.type == "droppod":
		await droppod_act(e)
		return
	if e.type == "vgate":
		await vgate_act(e)
		return
	if await surrender(e):
		return
	if e.type == "gatetrooper":
		await trooper_act(e)
		return
	if await jackal_nade(e):
		return
	# only rank-and-file shooters run for a pad: the follow-up below is a plain rifle shot, and a
	# Flametrooper's or Di-Cokka's single dmg number isn't a rifle's [min, max] (it crashed the shot)
	var grabs: bool = not e.hold and E.get("speed", 0) > 0 and not E.get("static", false) and E.get("dmg") is Array
	var pad = pad_in_reach(e, E.get("speed", 0)) if grabs else null
	if pad != null:
		# a bonus is up within reach: grab it, then shoot if there is a shot
		float_text(e, "GRAB IT!", Color("ff7a3d"))
		await enemy_advance(e, pad.x, E.speed)
		if e.dead or e.air:
			return
		if await jackal_nade(e):
			return
		if E.has("range") and not E.get("melee", false) and not E.get("arc", false):
			var b3 = best_shot(e, squad_alive(), E.range)
			if b3 != null:
				await wait(6)
				await enemy_shoot(e, b3.t, E)
		return
	if e.elite == "hungry":
		await eat_body(e)
	if Data.ETYPES[e.type].get("wall", false) and await wall_act(e):
		return
	match e.type:
		"jsniper":
			await sniper_act(e)
			return
		"flamer":
			await flamer_act(e)
			return
		"jdog":
			await skitter_act(e)
			return
		"gunship":
			await gunship_act(e)
			return
		"dicokka":
			await dicokka_act(e)
			return
		"hive":
			await hive_act(e)
			return
		"burrow":
			await burrow_act(e)
			return
		"skitter":
			await skitter_act(e)
			return
		"squid":
			await squid_act(e)
			return
		"blinker":
			await blinker_act(e)
			return
		"burrower":
			await burrower_act(e)
			return
		"prism":
			await prism_act(e)
			return
		"queen":
			await queen_act(e)
			return
		"warden":
			await warden_act(e)
			return
		"stalker":
			await stalker_act(e)
			return
		"overseer":
			await overseer_act(e)
			return
		"grappler":
			await grappler_act(e)
			return
		"bloater":
			await bloater_act(e)
			return
		"weaver":
			await weaver_act(e)
			return
	if E.get("sapper", false):
		var tg = nearest_squad(e)
		if tg == null:
			return
		if absf(tg.x - e.x) > 60:
			await enemy_advance(e, tg.x + (40 if tg.x < e.x else -40), E.speed)
		if e.dead or e.air:
			return
		var t2 = nearest_squad(e)
		if t2 != null and absf(t2.x - e.x) <= 90 and not e.planted:
			var dir := int(signf(t2.x - e.x))
			if dir == 0:
				dir = -1
			var cx := e.x + dir * 10
			var cy = T.stand_y(cx, e.y - 30)
			if cy != null:
				e.planted = true
				float_text(e, "CHARGE SET", Color("ff4d3d"), true)
				Sfx.play("tick")
				var ch := mk_unit()
				ch.team = "neutral"; ch.kind = "charge"; ch.x = cx; ch.y = cy; ch.w = 14; ch.h = 12
				units.append(ch)
				log_msg("A sapper planted a charge. It blows when the Jackals move next. Shoot it to defuse.")
				await wait(14)
				await enemy_advance(e, e.x - dir * 70, 70)
		return
	if E.get("radio", false):
		var tg = nearest_squad(e)
		if tg == null:
			return
		if absf(tg.x - e.x) < 240 and not e.hold:
			await enemy_advance(e, e.x + (90 if e.x >= tg.x else -90), E.speed)
		if e.dead or e.air:
			return
		var b = best_shot(e, foes_of(e), E.range)
		if b != null:
			await wait(6)
			await enemy_shoot(e, b.t, E)
		return
	if E.get("melee", false):
		var tg = nearest_squad(e)
		if tg == null:
			return
		if absf(tg.x - e.x) > 26:
			await enemy_advance(e, tg.x + (20 if tg.x < e.x else -20), E.speed)
		if e.dead or e.air:
			return
		var tt = null
		for s in foes_of(e):
			if absf(s.x - e.x) <= 32 and absf(s.y - e.y) <= 26:
				tt = s
				break
		if tt != null:
			e.face = 1 if tt.x >= e.x else -1
			e.pose = "throw"; e.pose_t = 16
			Sfx.play("slash")
			slash_fx(tt.x, tt.y - tt.h / 2.0, 1.6, e.face)
			await wait(8)
			if randf() * 100 < clampf(E.acc + alert * 2 - tt.dodge, 10, 95):
				damage(tt, int(round(ri(E.dmg[0], E.dmg[1]) * (1 + alert * 0.06))), e, {})
				if not tt.dead:
					tt.vx = e.face * 6; tt.vy = -3.5; tt.air = true; tt.walk = null; tt.bumped = null; tt.last_hit_by = e
			else:
				float_text(tt, "DODGED", Color("9aa4b0"))
		return
	if E.get("arc", false):
		var cands := sq.filter(func(s): return absf(s.x - e.x) <= E.range and not s.has_st("cloak"))
		if not e.hold and E.speed:
			var tg = nearest_squad(e)
			if tg == null:
				return
			await enemy_advance(e, tg.x, E.speed, func(): return foes_of(e).any(func(s): return absf(s.x - e.x) <= E.range * 0.9))
			if e.dead or e.air:
				return
			cands = foes_of(e).filter(func(s): return absf(s.x - e.x) <= E.range and not s.has_st("cloak"))
		if cands.is_empty():
			return
		var best = null
		var bsc := -1e9
		for s in cands:
			var sc: float = foes_of(e).filter(func(o): return absf(o.x - s.x) < 45).size() * 10 - s.hp * 0.3
			if sc > bsc:
				bsc = sc
				best = s
		await lob(e, best, E.dmg, E.radius, 1.6 if E.get("heavyArc", false) else 1.0)
		return
	if E.get("jet", 0) > 0:
		await jetter_act(e)
		return
	var gun = m2_near(e) if faction(e) == "jackal" and E.has("range") and not E.get("static", false) else null
	if gun != null and gun.loot.en != round_n:
		var bm = best_shot(e, foes_of(e), 600)
		if bm != null:
			gun.loot.en = round_n
			float_text(e, "ON THE M2!", Color("ff4d3d"))
			await wait(6)
			await enemy_shoot(e, bm.t, {"dmg": [3, 4], "shots": 5, "range": 560})
			return
	if E.get("builds", false):
		if e.built > 0:
			e.built -= 1
		elif await engineer_build(e):
			await until(settled)
	var best = best_shot(e, sq, E.range)
	if not E.get("static", false) and not e.hold:
		# Worms style: always move, then shoot. Close in until there's a shot from preferred range,
		# but take at least a few steps every turn.
		var tg = nearest_squad(e)
		if tg == null:
			return
		var x0 := e.x
		await enemy_advance(e, tg.x + (E.prefer * 0.5 if tg.x < e.x else -E.prefer * 0.5), E.speed, func():
			if absf(e.x - x0) < 40:
				return false
			var b2 = best_shot(e, sq, E.range)
			return b2 != null and absf(b2.t.x - e.x) <= E.prefer)
		if e.dead or e.air:
			return
		best = best_shot(e, foes_of(e), E.range)
	if best != null:
		await wait(6)
		await enemy_shoot(e, best.t, E)
	elif E.has("nade") and not e.dead and randf() < E.nade:
		var near := foes_of(e).filter(func(s): return absf(s.x - e.x) <= 380)
		near.sort_custom(func(a, b): return absf(a.x - e.x) < absf(b.x - e.x))
		if near.size():
			float_text(e, "GRENADE!", Color("ff7a3d"))
			await lob(e, near[0], 7, 28, 1.3)

# ---------------------------------------------------------------- Vharr aliens
# Like the Jackals, every alien moves and attacks in the same enemy phase. Nothing is marked ahead.
func hover_y(u: Unit, x: float, y: float) -> float:
	## Where a hovering alien floats over x: its altitude above the floor below (or the water),
	## lower when a ceiling is in the way.
	var fl = T.stand_y(x, y - 2)
	var floor_y: float = WATER_Y if fl == null else minf(fl, WATER_Y)
	var hy: float = floor_y - Data.ETYPES[u.type].get("alt", 110)
	var cy := floor_y - 4
	while cy > hy - u.h:
		if T.solid(x, cy):
			return minf(floor_y, cy + u.h + 4)
		cy -= CELL
	return hy

func hover_physics(u: Unit) -> void:
	## Hovering: knockback pushes it sideways and it eases back to altitude; no gravity, no fall damage.
	if absf(u.vx) > 0.05:
		var nx := u.x + u.vx
		if T.solid(nx, u.y - u.h * 0.5) or T.solid(nx, u.y - 4):
			var imp := absf(u.vx)
			if imp > 4:
				collision_dmg(u, (imp - 4) * 2.5, "SLAM")
			u.vx *= -0.25
		else:
			u.x = clampf(nx, 4, world_w - 4)
		u.vx *= 0.9
		if not u.dead and Vector2(u.vx, 0).length() >= 3:
			body_collisions(u)
	if u.dead or u.weight != "hover":
		return
	var ty := hover_y(u, u.x, u.y)
	var ny := u.y + clampf((ty - u.y) * 0.15, -3.0, 3.0)
	# only the leading edge has to be clear, so a tank shoved with its top into an overhang can still sink out of it
	var eased := false
	if not T.solid(u.x, ny if ny > u.y else ny - u.h):
		u.y = ny
		eased = true
	# wedged short of its altitude anyway: it has settled where it is, or the action waiting on everything
	# to settle never ends (the playtest's frozen turns)
	u.air = absf(u.vx) > 0.3 or (eased and absf(ty - u.y) > 1.5)
	if not u.air:
		u.vx = 0
		u.vy = 0
		u.bumped = null

func break_pod(u: Unit) -> void:
	## The saucer pod is shot out: the squid drops, takes crash damage on landing, and crawls from now on.
	u.weight = ""
	u.pod = 0
	u.crash = true
	u.air = true
	u.vy = 0.0
	u.walk = null
	float_text(u, "POD DOWN!", Color("c47bff"), true)
	Sfx.play("thud")
	for i in 6:
		part({"x": u.x + (i - 3) * 4, "y": u.y + 2, "vx": (i - 3) * 0.6, "vy": -1.5, "life": 40, "max": 40, "c": Color("9df25c"), "s": 2.0, "g": 0.12})

func hover_move(e: Unit, tx: float, budget: float) -> void:
	## Glide toward tx at altitude, over gaps and water, until a wall is in the way.
	if e.has_st("supp"):
		budget *= 0.5
	var pts: Array = []
	var x := e.x
	var y: float = e.y
	var dir := signf(tx - x)
	for i in int(minf(absf(tx - x), budget) / 2.0):
		var nx := x + dir * 2
		var ny := y + clampf(hover_y(e, nx, y) - y, -3.0, 3.0)
		if T.solid(nx, ny - e.h * 0.5) or T.solid(nx, ny - 4) or T.solid(nx, ny - e.h + 2):
			break
		x = nx
		y = ny
		pts.append([x, y, false])
	await walk_along(e, pts)

func leap_to(e: Unit, p: Vector2) -> void:
	## A fixed hop that always lands on the target spot (the same arc the grapple zip uses).
	e.face = 1 if p.x >= e.x else -1
	e.walk = null
	e.air = true
	e.zip = {"x0": e.x, "y0": e.y, "x1": p.x, "y1": p.y, "t": 0.0}
	await until(func(): return e.zip == null or e.dead)

func skitter_act(e: Unit) -> void:
	## Scramble in close (climbing walls on the way), then pounce on the nearest target and bite.
	## E4 Jackal Hounds hunt the same way and pin whoever they bite.
	var E: Dictionary = Data.ETYPES[e.type]
	var tg = nearest_squad(e)
	if tg == null:
		return
	if Vector2(tg.x - e.x, tg.y - e.y).length() > E.leap * 0.9:
		await enemy_advance(e, tg.x, E.speed, func():
			var t2 = nearest_squad(e)
			return t2 != null and Vector2(t2.x - e.x, t2.y - e.y).length() <= E.leap * 0.9)
	if e.dead or e.air:
		return
	tg = nearest_squad(e)
	if tg == null or Vector2(tg.x - e.x, tg.y - e.y).length() > E.leap:
		return
	Sfx.play("toss")
	await leap_to(e, Vector2(tg.x - signf(tg.x - e.x) * 8, tg.y))
	if e.dead:
		return
	for o in units:
		if o == e or o.dead or o.gone or o.sunk or o.type == e.type or (o.team != "squad" and o.team != "enemy"):
			continue
		if o.team == "enemy" and not at_war(e, o):
			continue
		if absf(o.x - e.x) < 20 + o.w / 2.0 and absf(o.y - e.y) < 30:
			Sfx.play("slash")
			slash_fx(o.x, o.y - o.h / 2.0, 1.0, e.face)
			damage(o, E.dmg, e, {})
			if E.get("pin", false) and o.team == "squad" and not o.dead:
				add_status(o, "pinned", 1, e)

func beam_path(e: Unit, ang: float, rng := -1.0, from = null) -> Dictionary:
	## The squid ray: a straight line that passes through one wall up to 28px thick.
	## Returns {end: Vector2, hits: [Unit]}; everything on the line is hit, Jackals included.
	var R: float = Data.ETYPES.squid.range if rng < 0 else rng
	var o: Vector2 = e.center() if from == null else from
	var dv := Vector2(cos(ang), sin(ang))
	var walls := 0
	var thick := 0.0
	var hits: Array = []
	var d := 8.0
	while d < R:
		var p := o + dv * d
		if p.y > WATER_Y or p.y < -40:
			break
		if T.solid(p.x, p.y):
			thick += 3
			if walls >= 1 or thick > 28:
				return {"end": p, "hits": hits}
		elif thick > 0:
			walls += 1
			thick = 0
		for u in units:
			if u == e or u.dead or u.gone or u.sunk or u.is_pickup() or u.kind == "pow" or hits.has(u) or u.fl.get("ship") == e:
				continue
			if absf(u.x - p.x) < u.w / 2.0 + 1 and p.y > u.y - u.h and p.y < u.y + 1:
				hits.append(u)
		d += 3
	return {"end": o + dv * R, "hits": hits}

func fire_beam(e: Unit, ang: float) -> void:
	var E: Dictionary = Data.ETYPES[e.type]
	var bp := beam_path(e, ang, E.range)
	if debug:
		print("[beam] from ", e.center(), " to ", bp.end, " hits ", bp.hits.map(func(h): return h.team + ":" + h.type))
	var o := e.center()
	e.face = 1 if cos(ang) >= 0 else -1
	Sfx.play("snipe")
	e.muzzle = 4
	e.muzzle_kind = "beam"
	if vfx != null:
		vfx.add(SfEnergy.beam(o, bp.end, vfx.ground_fn(bp.end.y), SfEnergy.VHARR, 0.05, 0.12, 2.5))
	else:
		for k in 3:
			tracers.append({"x1": o.x, "y1": o.y + k - 1, "x2": bp.end.x, "y2": bp.end.y + k - 1, "c": Color("c47bff") if k != 1 else Color("9df25c"), "t": 14})
		sparks(bp.end.x, bp.end.y, 5)
	for u in bp.hits:
		damage(u, int(round(E.dmg * (1 + alert * 0.06))), e, {})
	await wait(14)

func trooper_act(e: Unit) -> void:
	## H7 Gate Trooper: walk in to its preferred range like any Jackal, then fire the stolen ray.
	var E: Dictionary = Data.ETYPES.gatetrooper
	var tg = nearest_squad(e)
	if tg == null:
		return
	if not e.hold:
		var x0 := e.x
		await enemy_advance(e, tg.x + (E.prefer if e.x >= tg.x else -E.prefer), E.speed, func():
			return absf(e.x - x0) >= 40 and best_shot(e, foes_of(e), E.range) != null)
	if e.dead or e.air:
		return
	var b = best_shot(e, foes_of(e), E.range)
	if b != null:
		var c := e.center()
		e.face = 1 if b.t.x >= e.x else -1
		e.pose = "recoil"; e.pose_t = 8
		await wait(8)
		await fire_beam(e, atan2(b.t.y - b.t.h / 2.0 - c.y, b.t.x - c.x))

func sign_defector(p: Unit) -> void:
	## F3: a walked-out defector joins the recruit pool and is offered first at the next hire.
	Run.defectors.append(p.pow_name)
	banner("DEFECTOR!", Color("ffd23a"), "%s WANTS TO JOIN THE SQUAD" % p.pow_name)
	log_msg("%s, an ex-Jackal, will be first in line at the next hire. Defector: +3 max HP, +4 dodge." % p.pow_name)
	score += 300
	Sfx.play("coin")

func surrender(e: Unit) -> bool:
	## F3: in a BREACH a cornered Jackal gives up instead of fighting: hurt, alone, with a soldier
	## close. Walk over him like a POW and he signs up as a recruit. One per level.
	if not breach or faction(e) != "jackal" or e.elite != "" or is_thrall(e) or e.fl.get("turned", false) or stats.get("defectors", 0) >= 1:
		return false
	if not e.type in ["grunt", "shield", "sapper", "engineer", "jetter", "gatetrooper"] or e.hp > e.max_hp * 0.4:
		return false
	if not squad_alive().any(func(s): return absf(s.x - e.x) < 180 and absf(s.y - e.y) < 80):
		return false
	if units.any(func(o): return o != e and o.team == "enemy" and o.active and not o.dead and faction(o) == "jackal" and absf(o.x - e.x) < 260):
		return false
	stats["defectors"] = int(stats.get("defectors", 0)) + 1
	var names: Array = Data.CALLSIGNS.filter(func(c): return not Run.soldiers.any(func(s): return s.def.name == c) and not Run.defectors.has(c))
	e.team = "neutral"
	e.kind = "pow"
	e.active = false
	e.walk = null
	e.st.clear()
	e.shield = false
	e.fl["defector"] = true
	e.pow_name = names[randi() % names.size()] if names.size() else "TURNCOAT"
	e.face = -1
	float_text(e, "DON'T SHOOT! I QUIT!", Color("ffd23a"), true)
	log_msg("A cornered Jackal throws down his rifle. Walk him out like a POW and he'll sign up with you.")
	Sfx.play("deny")
	await wait(20)
	return true

func squid_act(e: Unit) -> void:
	## Glide to its preferred range, then fire the ray at the nearest target.
	var E: Dictionary = Data.ETYPES.squid
	var tg = nearest_squad(e)
	if tg == null:
		return
	var want: float = tg.x + (E.prefer if e.x >= tg.x else -E.prefer)
	if absf(want - e.x) > 20 and not e.hold:
		if e.weight == "hover":
			await hover_move(e, want, E.speed)
		else:
			await enemy_advance(e, want, E.speed * 0.5)
	if e.dead or e.air:
		return
	tg = nearest_squad(e)
	if tg != null and dist(e, tg) <= E.range:
		var c := e.center()
		e.face = 1 if tg.x >= e.x else -1
		await wait(8)
		await fire_beam(e, atan2(tg.y - tg.h / 2.0 - c.y, tg.x - c.x))

func rune_spot(e: Unit, tg: Unit):
	## Where the Blinker marks its rune: right behind the soldier (the side away from the Blinker), else in front.
	var dir := -1.0 if e.x >= tg.x else 1.0
	for off in [-30.0, 30.0, -60.0, 60.0]:
		var x: float = tg.x + off * -dir
		var y = T.stand_y(x, tg.y - 40)
		if y != null and y < WATER_Y - 4 and absf(y - tg.y) < 40 and not units.any(func(o): return o != e and not o.dead and not o.gone and not o.is_pickup() and absf(o.x - x) < (o.w + e.w) / 2.0 and absf(o.y - y) < 30):
			return Vector2(x, y)
	return null

func blink(e: Unit, r: Vector2) -> void:
	Sfx.play("power")
	e.face = 1 if r.x >= e.x else -1
	if vfx != null:
		await teleport(e, r, e.face)
		await wait(4)
		return
	for i in 8:
		part({"x": e.x, "y": e.y - i * 4, "vx": 0.0, "vy": -1.0, "life": 24, "max": 24, "c": Color("c47bff"), "s": 3.0, "g": 0.0})
	e.x = r.x
	e.y = r.y
	e.air = false
	e.vx = 0
	e.vy = 0
	for i in 8:
		part({"x": e.x + (i - 4) * 3, "y": e.y - 16, "vx": (i - 4) * 0.5, "vy": -0.5, "life": 24, "max": 24, "c": Color("9df25c"), "s": 3.0, "g": 0.0})
	await wait(12)

func teleport(u: Unit, to: Vector2, face: int) -> void:
	## V9 blink: the body crackles and comes apart, and is rebuilt at the far spot. The unit is
	## hidden in between and lands when the effect says it has arrived.
	var e := SfMovement.blink(Vector2(u.x, u.y), to, vfx.silhouette(u), vfx.ground_fn(u.y))
	vfx.add(e)
	await wait(e.timing(e.OUT))
	var a0 := u.alpha
	u.alpha = 0.0
	u.x = to.x
	u.y = to.y
	u.vx = 0; u.vy = 0; u.air = false; u.walk = null
	u.face = face
	await wait(e.timing(e.ARRIVE) - e.timing(e.OUT))
	u.alpha = a0

func blinker_act(e: Unit) -> void:
	## Teleport behind the nearest target (within 360px; else walk closer) and claw it.
	var E: Dictionary = Data.ETYPES.blinker
	var tg = nearest_squad(e)
	if tg == null:
		return
	if absf(tg.x - e.x) > 360:
		await enemy_advance(e, tg.x, E.speed)
		return
	var r = rune_spot(e, tg)
	if r == null:
		return
	await blink(e, r)
	if e.dead:
		return
	var tt = null
	for s in foes_of(e):
		if absf(s.x - e.x) <= 34 and absf(s.y - e.y) <= 30:
			tt = s
			break
	if tt != null:
		e.face = 1 if tt.x >= e.x else -1
		e.pose = "throw"; e.pose_t = 16
		Sfx.play("slash")
		slash_fx(tt.x, tt.y - tt.h / 2.0, 1.4, e.face)
		await wait(8)
		damage(tt, int(round(E.dmg * (1 + alert * 0.06))), e, {})
		if not tt.dead and not tt.immovable and not tt.heavy:
			tt.vx = e.face * E.knock * kb(tt); tt.vy = -3.5; tt.air = true; tt.walk = null; tt.bumped = null; tt.last_hit_by = e
		await until(settled)

func burrower_act(e: Unit) -> void:
	## Dive, tunnel up to 300px toward the nearest target digging a trench, and burst out under it.
	var E: Dictionary = Data.ETYPES.burrower
	var tg = nearest_squad(e)
	if tg == null:
		return
	if e.weight != "buried":
		e.weight = "buried"
		dust(e.x, e.y - 4, Color("c9b38a"), 10)
		Sfx.play("thud")
		await wait(10)
	var dir := signf(tg.x - e.x)
	var tx: float = e.x + dir * minf(absf(tg.x - e.x), E.tunnel)
	var dug := 0.0
	while absf(tx - e.x) > 4 and not e.dead:
		var stepx: float = minf(12.0, absf(tx - e.x))
		e.x += dir * stepx
		dug += stepx
		var gy = T.stand_y(e.x, 0)
		if gy != null and gy < WATER_Y - 4:
			e.y = gy
			if dug >= 24:
				dug = 0.0
				T.carve(e.x, gy + 3, 6, e)
				dust(e.x, gy, Color("c9b38a"), 2)
		await wait(2)
	if e.dead:
		return
	var gy2 = T.stand_y(e.x, 0)
	if gy2 != null:
		e.y = gy2
	e.weight = ""
	e.face = int(dir) if dir != 0 else e.face
	e.pose = "throw"; e.pose_t = 16
	Sfx.play("bigboom")
	shake += 6
	T.carve(e.x, e.y - 4, 16, e)
	for o in units:
		if o == e or o.dead or o.gone or o.sunk or o.is_pickup() or o.kind == "pow" or o.team == "neutral":
			continue
		if absf(o.x - e.x) < 30 + o.w / 2.0 and absf(o.y - e.y) < 40:
			damage(o, int(round(E.dmg * (1 + alert * 0.06))), e, {})
			if not o.dead and not o.heavy and not o.immovable:
				o.vx = signf(o.x - e.x if o.x != e.x else 1.0) * 2.5; o.vy = -7; o.air = true; o.walk = null; o.last_hit_by = e
	await until(settled)

func grappler_act(e: Unit) -> void:
	## Tongue the nearest target in a clear line within range and yank it in; bite if it lands close.
	var E: Dictionary = Data.ETYPES.grappler
	var tg = null
	var mouth := Vector2.ZERO
	for o in foes_of(e):
		if Vector2(o.x - e.x, o.y - e.y).length() > E.range or o.heavy or o.immovable:
			continue
		var m := Vector2(e.x + (20 if o.x >= e.x else -20), e.y - 22)
		if not ray_clear(m.x, m.y, o.x, o.y - o.h / 2.0):
			continue
		if tg == null or absf(o.x - e.x) < absf(tg.x - e.x):
			tg = o
			mouth = m
	if tg == null:
		var near = nearest_squad(e)
		if near != null:
			await enemy_advance(e, near.x, E.speed)
		return
	e.face = 1 if tg.x >= e.x else -1
	e.pose = "throw"; e.pose_t = 20
	Sfx.play("slash")
	ropes.append({"x": mouth.x, "y": mouth.y, "u": tg, "t": 40, "c": Color("e05a8a")})
	await wait(12)
	var gap: float = absf(tg.x - e.x) - (e.w + tg.w) / 2.0
	var pull := minf(E.yank, maxf(0.0, gap))
	if pull > 8:
		tg.vx = -e.face * pull / 36.0
		tg.vy = -3.5
		tg.air = true
		tg.walk = null
		tg.bumped = {e.id: true}
		tg.last_hit_by = e
		float_text(tg, "YANKED!", Color("e05a8a"), true)
		await until(func(): return not tg.air or tg.dead or tg.sunk)
	if not tg.dead and absf(tg.x - e.x) < 50 and absf(tg.y - e.y) < 40:
		Sfx.play("slash")
		damage(tg, int(round(E.dmg * (1 + alert * 0.06))), e, {"melee": true})
	await until(settled)

func bloater_act(e: Unit) -> void:
	## Swell, waddle at the nearest target, and pop on it when it gets there.
	var E: Dictionary = Data.ETYPES.bloater
	var sw: int = mini(4, e.fl.get("swell", 0) + 1)
	e.fl["swell"] = sw
	e.w = E.w + sw * 4
	e.h = E.h + sw * 4
	float_text(e, "SWELLS", Color("9df25c"))
	var tg = nearest_squad(e)
	if tg == null:
		return
	if absf(tg.x - e.x) > 34:
		await enemy_advance(e, tg.x, E.speed, func():
			return foes_of(e).any(func(o): return absf(o.x - e.x) < 40 and absf(o.y - e.y) < 40))
	if e.dead or e.air:
		return
	if foes_of(e).any(func(o): return absf(o.x - e.x) < 44 and absf(o.y - e.y) < 40):
		booms.append({"t": 1, "x": e.x, "y": e.y - e.h / 2.0, "r": E.radius + 10.0 * sw, "dmg": E.dmg, "owner": null})
		e.fl["swell"] = -99  # it popped itself: kill() must not pop it again
		kill(e, null)
		await until(settled)

func weaver_act(e: Unit) -> void:
	## Keep its distance, dome the ally nearest your squad, and take a potshot.
	var E: Dictionary = Data.ETYPES.weaver
	var tg = nearest_squad(e)
	if tg == null:
		return
	if not e.hold:
		await enemy_advance(e, tg.x + (E.prefer if e.x >= tg.x else -E.prefer), E.speed)
	if e.dead or e.air:
		return
	var best = null
	for o in units:
		if o == e or o.team != "enemy" or o.dead or not o.active or o.dome > 0 or is_boss(o) or Data.ETYPES[o.type].get("static", false):
			continue
		if absf(o.x - e.x) > 260:
			continue
		if best == null or absf(o.x - tg.x) < absf(best.x - tg.x):
			best = o
	if best != null:
		e.pose = "throw"; e.pose_t = 18
		Sfx.play("power")
		best.dome = 2
		float_text(best, "DOMED", Color("9df25c"), true)
		await wait(14)
	var b = best_shot(e, foes_of(e), E.range)
	if b != null:
		await enemy_shoot(e, b.t, E)

func prism_act(e: Unit) -> void:
	## Drift to its preferred range with the mirror turned on the nearest soldier, then zap.
	var E: Dictionary = Data.ETYPES.prism
	var tg = nearest_squad(e)
	if tg == null:
		return
	var want: float = tg.x + (E.prefer if e.x >= tg.x else -E.prefer)
	if absf(want - e.x) > 20 and not e.hold:
		if e.weight == "hover":
			await hover_move(e, want, E.speed)
		else:
			await enemy_advance(e, want, E.speed * 0.5)
	if e.dead or e.air:
		return
	tg = nearest_squad(e)
	if tg == null:
		return
	e.face = 1 if tg.x >= e.x else -1
	var c := e.center()
	if dist(e, tg) <= E.range and ray_clear(c.x, c.y, tg.x, tg.y - tg.h / 2.0):
		await wait(6)
		Sfx.play("snipe")
		if vfx != null:
			vfx.add(SfEnergy.bolt(c, Vector2(tg.x, tg.y - tg.h / 2.0), vfx.ground_fn(tg.y), SfEnergy.CYAN, 0.0, 2600.0))
		else:
			tracers.append({"x1": c.x, "y1": c.y, "x2": tg.x, "y2": tg.y - tg.h / 2.0, "c": Color("8ff0ff"), "t": 12})
		damage(tg, int(round(E.dmg * (1 + alert * 0.06))), e, {})
		await wait(10)

func warden_act(e: Unit) -> void:
	## Keep its distance, drop the well on the most bunched-up soldiers, and pull everything in it.
	var E: Dictionary = Data.ETYPES.warden
	var tg = nearest_squad(e)
	if tg == null:
		return
	if not e.hold:
		await enemy_advance(e, tg.x + (E.prefer if e.x >= tg.x else -E.prefer), E.speed)
	if e.dead or e.air:
		return
	var best = null
	var best_n := -1
	for s in foes_of(e):
		var n := foes_of(e).filter(func(o): return absf(o.x - s.x) < E.well).size()
		if best == null or n > best_n or (n == best_n and absf(s.x - e.x) < absf(best.x - e.x)):
			best = s
			best_n = n
	if best == null:
		return
	wells = wells.filter(func(q): return q.by != e)
	var well := {"x": best.x, "y": best.y - 20.0, "r": float(E.well), "by": e}
	wells.append(well)
	e.face = 1 if best.x >= e.x else -1
	e.pose = "throw"; e.pose_t = 18
	Sfx.play("power")
	float_at(well.x, well.y - 40, "GRAVITY WELL", Color("c47bff"), true)
	await wait(16)
	await pull_well(well)

func pull_well(w: Dictionary) -> void:
	## Everything loose in the well hops up to its pull toward the center.
	black_hole(w.x, w.y, w.r, 0.15)
	var E: Dictionary = Data.ETYPES.warden
	var moved := false
	for u in units:
		if u.dead or u.gone or u.sunk or u.heavy or u.immovable or u.is_pickup() or u.kind == "pow" or u == w.by:
			continue
		if w.get("foes", false) and u.team != "enemy":
			continue  # the squad's own well only pulls the enemy
		if u.weight == "hover" or u.weight == "buried" or u.type == "boss":
			continue
		var dx: float = w.x - u.x
		if absf(dx) > w.r or absf(u.y - w.y) > w.r or absf(dx) < 10:
			continue
		var pull := minf(float(E.pull), absf(dx) - 6)
		u.vx = signf(dx) * pull / 36.0 * kb(u)
		u.vy = -3.5
		u.air = true
		u.walk = null
		u.bumped = {}
		u.last_hit_by = w.by
		moved = true
	if moved:
		await wait(4)
		await until(settled)

func stalker_act(e: Unit) -> void:
	## The Phase Stalker flips between phased and solid every turn. Phased it walks straight through
	## rock; turning solid inside rock kills it. Either way it slashes whoever it ends up next to.
	var E: Dictionary = Data.ETYPES.stalker
	var phased: bool = not e.fl.get("phased", false)
	e.fl["phased"] = phased
	e.alpha = 0.45 if phased else 1.0
	if not phased and (T.solid(e.x, e.y - e.h * 0.5) or T.solid(e.x, e.y - e.h + 4)):
		float_text(e, "SOLID IN THE ROCK!", Color("ff7a3d"), true)
		Sfx.play("thud")
		damage(e, e.hp, null, {"impact": true})
		return
	float_text(e, "PHASED" if phased else "SOLID", Color("8ff0ff") if phased else Color("c47bff"))
	var tg = nearest_squad(e)
	if tg == null:
		return
	if not e.hold:
		var side := 1.0 if e.x >= tg.x else -1.0
		if phased:
			var tx: float = tg.x + side * 24
			tx = e.x + clampf(tx - e.x, -E.phase_move, E.phase_move)
			var ty = T.stand_y(tx, tg.y - 60)
			if ty == null or ty >= WATER_Y - 4:
				ty = T.stand_y(tx, 0)
			if ty != null and ty < WATER_Y - 4:
				var pts: Array = []
				var n := int(maxf(1, absf(tx - e.x) / 3.0))
				for k in range(1, n + 1):
					pts.append([lerpf(e.x, tx, float(k) / n), lerpf(e.y, ty, float(k) / n), false])
				Sfx.play("power")
				await walk_along(e, pts)
		else:
			await enemy_advance(e, tg.x + side * 24, E.speed)
	if e.dead:
		return
	tg = nearest_squad(e)
	if tg != null and absf(tg.x - e.x) < 44 and absf(tg.y - e.y) < 44:
		e.face = 1 if tg.x >= e.x else -1
		e.pose = "throw"; e.pose_t = 14
		Sfx.play("slash")
		await wait(6)
		damage(tg, int(round(E.dmg * (1 + alert * 0.06))), e, {"melee": true})
		await wait(10)

func overseer_act(e: Unit) -> void:
	## Link up to two Jackals as Thralls, hang back behind them, and lash out at the nearest soldier.
	var E: Dictionary = Data.ETYPES.overseer
	var linked := units.filter(func(o): return o.fl.get("link", -1) == e.id and not o.dead)
	var outbreak: bool = e.fl.get("outbreak", false)
	if linked.size() < E.links or outbreak:
		var free := units.filter(func(o): return o.team == "enemy" and not o.dead and o.active and faction(o) == "jackal" and o.type != "boss" and not o.fl.has("link") and absf(o.x - e.x) < 460)
		free.sort_custom(func(a, b2): return absf(a.x - e.x) < absf(b2.x - e.x))
		for o in free.slice(0, 1 if outbreak else E.links - linked.size()):  # E5: one a turn, all of them in the end
			o.fl["link"] = e.id
			o.fl["thrall"] = true
			float_text(o, "THRALL", Color("9df25c"), true)
			linked.append(o)
		if free.size():
			Sfx.play("power")
			await wait(12)
	var tg = nearest_squad(e)
	if tg == null:
		return
	var away := 1.0 if e.x >= tg.x else -1.0
	var anchor: float = tg.x + away * 320
	if linked.size():
		anchor = linked.map(func(o): return o.x).reduce(func(a, b2): return a + b2, 0.0) / linked.size() + away * 90
	if absf(anchor - e.x) > 20 and not e.hold:
		if e.weight == "hover":
			await hover_move(e, anchor, E.speed)
		else:
			await enemy_advance(e, anchor, E.speed * 0.5)
	if e.dead or e.air:
		return
	tg = nearest_squad(e)
	if tg == null:
		return
	var c := e.center()
	if dist(e, tg) <= E.range and ray_clear(c.x, c.y, tg.x, tg.y - tg.h / 2.0):
		e.face = 1 if tg.x >= e.x else -1
		await wait(6)
		Sfx.play("power")
		for k in 2:
			tracers.append({"x1": c.x, "y1": c.y + k * 2, "x2": tg.x, "y2": tg.y - tg.h / 2.0, "c": Color("ff6ad5") if k else Color("c47bff"), "t": 14})
		damage(tg, int(round(E.dmg * (1 + alert * 0.06))), e, {})
		await wait(10)

func queen_act(e: Unit) -> void:
	## Q2 Burrow Queen. Buried: tunnel toward the nearest soldier, tearing up the ground, and burst out
	## under them. Surfaced: bite whoever is close or spit acid at the nearest, then dive again.
	var E: Dictionary = Data.ETYPES.queen
	var tg = nearest_squad(e)
	if tg == null:
		return
	var dmul := 1 + alert * 0.06
	if e.weight != "buried":
		e.face = 1 if tg.x >= e.x else -1
		e.pose = "throw"; e.pose_t = 18
		if absf(tg.x - e.x) < e.w / 2.0 + 40 and absf(tg.y - e.y) < 60:
			Sfx.play("slash")
			await wait(8)
			damage(tg, int(round(E.bite * dmul)), e, {"melee": true})
		else:
			Sfx.play("splash")
			var c := e.center()
			tracers.append({"x1": c.x, "y1": c.y - 20, "x2": tg.x, "y2": tg.y - 10, "c": Color("9df25c"), "t": 16})
			await wait(10)
			acids.append({"x": tg.x, "y": tg.y, "r": 36.0, "turns": 2})
			damage(tg, int(round(E.spit * dmul)), e, {})
			float_text(tg, "ACID!", Color("9df25c"), true)
		await wait(14)
		if e.dead:
			return
		e.weight = "buried"
		dust(e.x, e.y - 6, Color("c9b38a"), 16)
		Sfx.play("thud")
		shake += 4
		await wait(10)
		return
	var dir := signf(tg.x - e.x)
	var tx: float = e.x + dir * minf(absf(tg.x - e.x), E.tunnel)
	var dug := 0.0
	while absf(tx - e.x) > 4 and not e.dead:
		var stepx: float = minf(10.0, absf(tx - e.x))
		e.x += dir * stepx
		dug += stepx
		var gy = T.stand_y(e.x, 0)
		if gy != null and gy < WATER_Y - 4:
			e.y = gy
			shake = maxf(shake, 2.0)
			if dug >= 30:
				dug = 0.0
				T.carve(e.x, gy + 6, 12, e)  # she leaves the arena torn up behind her
				dust(e.x, gy, Color("c9b38a"), 4)
		await wait(2)
	if e.dead:
		return
	var gy2 = T.stand_y(e.x, 0)
	if gy2 != null:
		e.y = gy2
	e.weight = ""
	e.face = int(dir) if dir != 0 else e.face
	e.pose = "throw"; e.pose_t = 24
	Sfx.play("bigboom")
	shake += 12
	T.carve(e.x, e.y - 6, 30, e)
	float_text(e, "BURROW QUEEN!", Color("c47bff"), true)
	for o in units:
		if o == e or o.dead or o.gone or o.sunk or o.is_pickup() or o.kind == "pow" or o.team == "neutral":
			continue
		if absf(o.x - e.x) < 50 + o.w / 2.0 and absf(o.y - e.y) < 70:
			damage(o, int(round(E.burst * dmul)), e, {})
			if not o.dead and not o.heavy and not o.immovable:
				o.vx = signf(o.x - e.x if o.x != e.x else 1.0) * 3.5; o.vy = -6; o.air = true; o.walk = null; o.bumped = {e.id: true}; o.last_hit_by = e
	await until(settled)

func tick_acids() -> void:
	## End of the enemy phase: anyone but the Vharr standing in Hive acid takes 3.
	for a in acids:
		var mine: bool = a.has("owner")  # Sable's spit only burns the other side
		for u in units:
			if u.dead or u.gone or u.sunk or u.is_prop() or u.is_pickup() or u.kind == "pow" or (faction(u) == "vharr" and not mine):
				continue
			if (mine and u.team != "enemy") or (u.team == "squad" and u.def.key == "sable"):
				continue
			if absf(u.x - a.x) < a.r and absf(u.y - a.y) < 20:
				float_text(u, "ACID", Color("9df25c"))
				damage(u, a.get("dmg", 3), a.get("owner"), {"status": true})
				if mine and a.owner is Unit and a.owner.perk("meltarmor"):
					add_status(u, "toxic", 2, a.owner)
		a.turns -= 1
	acids = acids.filter(func(a): return a.turns > 0)

func spawn_skitter(x: float, y: float) -> Unit:
	var sy = T.stand_y(x, y - 40)
	var k := mk_enemy("skitter", x, sy if sy != null else y)
	k.active = true
	units.append(k)
	return k

func hive_act(e: Unit) -> void:
	## Hive Pod (E2): counts down in plain sight, then hatches Skitters that act next phase.
	var E: Dictionary = Data.ETYPES.hive
	var n: int = e.fl.get("hatch", E.hatch) - 1
	if n > 0:
		e.fl["hatch"] = n
		return
	e.fl["hatch"] = E.hatch
	if units.filter(func(o): return o.type == "skitter" and not o.dead and absf(o.x - e.x) < 400).size() >= 8:
		return  # the nest is full; it waits for room
	float_text(e, "HATCH!", Color("9df25c"), true)
	Sfx.play("splash")
	for k in E.brood:
		spawn_skitter(e.x + (k * 2 - 1) * 22, e.y)
	await wait(16)

func burrow_act(e: Unit) -> void:
	## Skitter tunnel (E1): one wave per enemy phase, the next wave's size shown over it, then it caves in.
	var E: Dictionary = Data.ETYPES.burrow
	var i: int = e.fl.get("wave", 0)
	if i >= E.waves.size():
		float_text(e, "CAVED IN", Color("e8dcc2"), true)
		dust(e.x, e.y - 4, Color("c9b38a"), 10)
		e.dead = true
		e.hp = 0
		return
	float_text(e, "SWARM!", Color("9df25c"), true)
	Sfx.play("scream", -8)
	for k in E.waves[i]:
		spawn_skitter(e.x - 20 + k * 14, e.y)
		await wait(4)
	e.fl["wave"] = i + 1
	await wait(10)

# ---------------------------------------------------------------- Q1 Hive Ship and drop pods
func hang_plates(sh: Unit) -> void:
	## Two hull plates hang on tethers under the ship's belly.
	for dx in [-48.0, 48.0]:
		var p := mk_enemy("shipplate", sh.x + dx, sh.y + 16)
		p.fl["ship"] = sh
		p.fl["dx"] = dx
		p.immovable = true
		units.append(p)

func ship_plated(sh: Unit) -> bool:
	return units.any(func(o): return o.type == "shipplate" and not o.dead and o.fl.get("ship") == sh)

func drop_plate(p: Unit, src) -> void:
	## A plate shot off its tethers falls like a girder and crushes whatever is under it.
	p.gone = true
	Sfx.play("thud")
	float_text(p, "PLATE FALLS!", Color("ffd23a"), true)
	var cells: Array = []
	var cx0 := int(floor((p.x - p.w / 2.0) / CELL))
	var cy0 := int(floor((p.y - p.h) / CELL))
	for ry in int(p.h / CELL):
		for rx in int(p.w / CELL):
			cells.append([cx0 + rx, cy0 + ry, 2, 0])
	var c = T.chunk_from_cells(cells, src if src is Unit and src.team == "squad" else null)
	if c != null and p.fl.get("ship") != null:
		c.hit[p.fl.ship.id] = true
	var sh = p.fl.get("ship")
	if sh != null and not sh.dead and not ship_plated(sh):
		banner("HULL EXPOSED!", Color("ffb23e"), "THE HIVE SHIP TAKES +30% DAMAGE")

func hiveship_act(e: Unit) -> void:
	## Glide over the squad, sweep the ray across the ground under the nearest soldier, then drop
	## a pod of Vharr (two when it's below half health).
	var E: Dictionary = Data.ETYPES.hiveship
	var tg = nearest_squad(e)
	if tg == null:
		return
	var want: float = tg.x + (70.0 if e.x >= tg.x else -70.0)
	if absf(want - e.x) > 20:
		await hover_move(e, want, E.speed)
	if e.dead:
		return
	tg = nearest_squad(e)
	if tg != null:
		await ship_sweep(e, tg)
	var n := 2 if e.hp < e.max_hp / 2 else 1
	for k in n:
		if e.dead or squad_alive().is_empty():
			return
		var vh := units.filter(func(o): return o.team == "enemy" and not o.dead and faction(o) == "vharr" and not Data.ETYPES[o.type].get("static", false) and not is_boss(o) and absf(o.x - e.x) < 700)
		if vh.size() >= 8:
			break  # the arena is full; it holds the rest back
		await ship_pod(e, pick(squad_alive()))

func ship_sweep(e: Unit, tg: Unit) -> void:
	## The ray drags across the ground from one side of the target to the other. It goes through
	## one thin wall like the Squid's, and hits each body on its path once.
	var E: Dictionary = Data.ETYPES.hiveship
	var o := Vector2(e.x, e.y - 4)
	var dir := 1.0 if tg.x >= e.x else -1.0
	var x0: float = tg.x - dir * E.sweep / 2.0
	var hit := {}
	var dmg := int(round(E.beam * (1 + alert * 0.06)))
	Sfx.play("snipe")
	for k in 9:
		var gx: float = x0 + dir * E.sweep * k / 8.0
		var gy = T.stand_y(gx, o.y + 20)
		var ang := atan2((gy if gy != null else float(WATER_Y)) - 6 - o.y, gx - o.x)
		var bp := beam_path(e, ang, E.beam_range, o)
		for j in 3:
			tracers.append({"x1": o.x, "y1": o.y + j - 1, "x2": bp.end.x, "y2": bp.end.y + j - 1, "c": Color("c47bff") if j != 1 else Color("9df25c"), "t": 8})
		sparks(bp.end.x, bp.end.y, 2)
		for u in bp.hits:
			if not hit.has(u.id):
				hit[u.id] = true
				damage(u, dmg, e, {})
		await wait(4)
	await wait(10)

func ship_pod(e: Unit, tg: Unit) -> void:
	## A drop pod falls from the belly toward a soldier, crashes in with a blast and lands full of Vharr.
	var E: Dictionary = Data.ETYPES.hiveship
	var pool: Array = Data.BIOME_ALIENS.get(mission.get("biome", ""), ALIENS).filter(func(k): return Data.ETYPES[k].get("weight", "") != "hover")
	var cargo: Array = ["skitter", "skitter"] if randf() < 0.5 or pool.is_empty() else [pick(pool)]
	var sx := e.x + randf_range(-20, 20)
	var sy := e.y + 4
	var tf := sqrt(2.0 * maxf(20.0, tg.y - sy) / grav)
	var vx := clampf((tg.x + randf_range(-30, 30) - sx) / tf, -4.0, 4.0)
	float_text(e, "POD DROP!", Color("c47bff"), true)
	Sfx.play("toss")
	projs.append(mk_proj({"kind": "droppod", "x": sx, "y": sy, "vx": vx, "vy": 0.0, "r": 30.0, "dmg": int(round(E.pod_dmg * (1 + alert * 0.06))), "owner": e, "cargo": cargo}))
	await until(settled)
	await wait(8)

func land_pod(x: float, y: float, cargo: Array) -> void:
	## Where a drop pod comes to rest, closed. Over water it sinks with everything inside.
	var gy = T.stand_y(x, y - 30)
	if gy == null or gy >= WATER_Y - 4:
		splash(x)
		return
	var u := mk_enemy("droppod", x, gy)
	u.active = true
	u.fl["cargo"] = cargo
	units.append(u)

func droppod_act(e: Unit) -> void:
	## The pod opens and what's inside comes out swinging, all in this same phase.
	var cargo: Array = e.fl.get("cargo", ["skitter"])
	float_text(e, "POD OPENS!", Color("9df25c"), true)
	Sfx.play("splash")
	e.dead = true
	e.gone = true
	for i in 6:
		part({"x": e.x + (i - 3) * 4, "y": e.y - 14, "vx": (i - 3) * 0.7, "vy": -2.0, "life": 40, "max": 40, "c": Color("9df25c"), "s": 2.0, "g": 0.12})
	var out: Array = []
	for k in cargo.size():
		var cx: float = e.x + (0.0 if cargo.size() == 1 else (k * 2 - 1) * 14.0)
		var cy = T.stand_y(cx, e.y - 30)
		var c := mk_enemy(cargo[k], cx, cy if cy != null else e.y)
		c.active = true
		units.append(c)
		place_alien(c)
		out.append(c)
	await wait(14)
	for c in out:
		if not c.dead and not squad_alive().is_empty():
			await enemy_act(c)
			await until(settled)

# ---------------------------------------------------------------- E3 and E6
func alien_pool() -> Array:
	return Data.BIOME_ALIENS.get(mission.get("biome", ""), ALIENS)

func pod_ambush() -> void:
	## E3: three pods crash down around the squad's front. They open next enemy phase.
	ambush.done = true
	banner("DROP POD AMBUSH!", Color("c47bff"), "BREAK THE PODS BEFORE THEY OPEN")
	Sfx.play("alarm")
	await wait(30)
	var sq := squad_alive()
	sq.sort_custom(func(a, b2): return a.x > b2.x)
	var pool: Array = alien_pool().filter(func(k): return Data.ETYPES[k].get("weight", "") != "hover")
	var xs: Array = []
	for k in 3:
		var tg: Unit = sq[k % sq.size()]
		var x: float = clampf(tg.x + randf_range(-40, 40), cam_x + 20, cam_x + W - 20)
		for tries in 8:
			if not xs.any(func(o): return absf(o - x) < 70):
				break
			x = clampf(x + 70, cam_x + 20, cam_x + W - 20) if tries % 2 == 0 else clampf(x - 140, cam_x + 20, cam_x + W - 20)
		xs.append(x)  # spread out, so one pod's blast doesn't crack the next
		var cargo: Array = ["skitter", "skitter"] if k == 0 or pool.is_empty() else [pick(pool)]
		projs.append(mk_proj({"kind": "droppod", "x": x, "y": -40.0 - k * 40, "vx": 0.0, "vy": 6.0, "r": 30.0, "dmg": int(round(7 * (1 + alert * 0.06))), "owner": null, "cargo": cargo}))
		Sfx.play("toss")
		await wait(12)
	await until(settled)
	await wait(10)

func vgate_act(e: Unit) -> void:
	## E6: one alien comes through the gate on the squad's side, until four from it are alive.
	var E: Dictionary = Data.ETYPES.vgate
	if units.filter(func(o): return o.fl.get("from") == e and not o.dead).size() >= E.cap:
		return
	var tg = nearest_squad(e)
	var dir := -1.0 if tg == null or tg.x < e.x else 1.0
	var x: float = e.x + dir * 30
	var y = T.stand_y(x, e.y - 40)
	var c := mk_enemy(pick(alien_pool()), x, y if y != null else e.y)
	c.active = true
	c.fl["from"] = e
	units.append(c)
	place_alien(c)
	float_text(e, "%s COMES THROUGH" % Data.ETYPES[c.type].name.to_upper(), Color("c47bff"), true)
	Sfx.play("power")
	for i in 8:
		part({"x": x, "y": c.y - 20, "vx": (randf() - .5) * 3, "vy": (randf() - .5) * 3, "life": 30, "max": 30, "c": Color("c47bff"), "s": 2.0, "g": 0.0})
	await wait(16)

# ---------------------------------------------------------------- Q3 Vharr Boar
func vboar_tricks(bo: Unit) -> void:
	## The finale BOAR's Vharr refit: a dome over the turret every third turn, and a tongue that
	## yanks the nearest soldier in a clear line up to the tracks.
	var cd: int = bo.fl.get("dome_cd", 0)
	if bo.dome <= 0 and cd <= 0:
		bo.dome = 1
		bo.fl["dome_cd"] = 2
		float_text(bo, "DOME UP!", Color("9df25c"), true)
		Sfx.play("power")
		await wait(14)
	elif bo.dome <= 0:
		bo.fl["dome_cd"] = cd - 1
	var mouth := Vector2(bo.x - 56, bo.y - 26)
	var tg = null
	for o in squad_alive():
		if absf(o.x - bo.x) > 400 or o.heavy or o.immovable:
			continue
		if not ray_clear(mouth.x, mouth.y, o.x, o.y - o.h / 2.0):
			continue
		if tg == null or absf(o.x - bo.x) < absf(tg.x - bo.x):
			tg = o
	if tg == null:
		return
	Sfx.play("slash")
	ropes.append({"x": mouth.x, "y": mouth.y, "u": tg, "t": 40, "c": Color("e05a8a")})
	await wait(12)
	var dir := signf(bo.x - tg.x) if tg.x != bo.x else -1.0
	var gap: float = absf(tg.x - bo.x) - (bo.w + tg.w) / 2.0
	var pull := minf(220.0, maxf(0.0, gap))
	if pull > 8:
		tg.vx = dir * pull / 36.0
		tg.vy = -3.5
		tg.air = true
		tg.walk = null
		tg.bumped = {bo.id: true}
		tg.last_hit_by = bo
		float_text(tg, "YANKED!", Color("e05a8a"), true)
		await until(func(): return not tg.air or tg.dead or tg.sunk)
	if not tg.dead and absf(tg.x - bo.x) < bo.w / 2.0 + 30:
		Sfx.play("slash")
		damage(tg, int(round(6 * (1 + alert * 0.06))), bo, {"melee": true})
	await until(settled)

func alpha_near(e: Unit) -> bool:
	## ALPHA elite: others of its kind within 160px act twice.
	return units.any(func(o): return o != e and o.elite == "alpha" and o.type == e.type and not o.dead and absf(o.x - e.x) <= 160)

func eat_body(e: Unit) -> void:
	## HUNGRY elite: eats a fallen body within 60px to heal 8. The body is gone for good.
	for o in units:
		if o.dead and not o.gone and not o.sunk and o.kind == "enemy" and o != e and absf(o.x - e.x) <= 60 and absf(o.y - e.y) < 40:
			o.gone = true
			e.hp = mini(e.max_hp, e.hp + 8)
			float_text(e, "+8 FEEDS", Color("9df25c"), true)
			Sfx.play("slash")
			await wait(12)
			return

func place_encounter(id: String) -> void:
	## The level's Vharr encounter (Data.ENCOUNTERS, or the Burrow Queen) in the first fighting
	## stretch after the mid camp's yard.
	if id == "" or T.stretches.is_empty():
		return
	var st: Array = T.stretches[-1]
	for s2 in T.stretches:
		if T.yard.size() and s2[0] > T.yard[1]:
			st = s2
			break
	var w: float = st[1] - st[0]
	var put := func(type: String, f: float) -> Unit:
		var x: float = st[0] + w * f
		var y = T.stand_y(x, 0)
		var k := 0
		while (y == null or y >= WATER_Y - 4) and k < 20:
			x += 12
			y = T.stand_y(x, 0)
			k += 1
		if y == null or y >= WATER_Y - 4:
			return null
		var u := mk_enemy(type, x, y)
		units.append(u)
		place_alien(u)
		return u
	if id == "nest":
		var stagger := 1
		for f in [0.3, 0.55, 0.8]:
			var h = put.call("hive", f)
			if h != null:
				h.fl["hatch"] = stagger + 1
				stagger += 1
		put.call("squid", 0.65)
	elif id == "queen":
		put.call("queen", 0.7)
		put.call("skitter", 0.4)
	elif id == "droppods":
		ambush = {"x": st[0] + w * 0.35, "done": false}
	elif id == "hunt":
		var pool: Array = alien_pool().filter(func(k): return Data.ETYPES[k].get("weight", "") != "hover")
		var hu = put.call(pick(pool) if pool.size() else "stalker", 0.8)
		if hu != null:
			make_elite(hu, pick_elite(true))
			hu.fl["hunt"] = true
			hu.fl["lead"] = true
			for f in [0.74, 0.86]:
				var es = put.call("skitter", f)
				if es != null:
					es.fl["hunt"] = true
	elif id == "outbreak":
		for jt in [["grunt", 0.4], ["shield", 0.46], ["grunt", 0.52], ["brute", 0.58], ["grunt", 0.64]]:
			var j = put.call(jt[0], jt[1])
			if j != null:
				j.fl["camp"] = true
		var ov = put.call("overseer", 0.75)
		if ov != null:
			ov.fl["outbreak"] = true
	elif id == "gate":
		put.call("vgate", 0.62)
		put.call("skitter", 0.5)
	elif id == "swarm":
		put.call("burrow", 0.45)
		var b2 = put.call("burrow", 0.8)
		if b2 != null:
			b2.fl["wave"] = 1  # the far tunnel starts on its second wave: 4, then 3

func boss_act(bo: Unit) -> void:
	if bo.x > cam_x + W - 170:
		var pts: Array = []
		var x := bo.x
		for i in 20:
			x -= 2
			var y = T.stand_y(x, bo.y - 40)
			pts.append([x, y if y != null else bo.y, false])
		await walk_along(bo, pts)
	if bo.fl.get("vharr", false):
		await vboar_tricks(bo)
		if bo.dead or squad_alive().is_empty():
			return
	var shells := 2 if bo.hp < bo.max_hp / 2 else 1
	for i in shells:
		var sq := squad_alive()
		if sq.is_empty():
			return
		var tg: Unit = pick(sq)
		var pv := boss_pivot(bo)
		var sol = solve_arc(pv.x - 40, pv.y - 10, tg.x, tg.y - 4, 1, 14)
		if sol != null:
			var k := 1 + (randf() - .5) * 0.08
			bo.aim_a = clampf(atan2(-sol.vy, -sol.vx), -0.4, 1.2)
			await wait(10)
			var m := muzzle(bo)
			Sfx.play("bigboom")
			shake += 4
			for j in 4:
				puff(m.x, m.y, 2.0)
			# B2: the shell keeps its base damage at any alert (alert already brings airstrikes and paratroopers)
			projs.append(mk_proj({"kind": "shell", "x": m.x, "y": m.y, "vx": sol.vx * k, "vy": sol.vy * k, "wind": 1.0, "r": 44.0, "dmg": 11, "owner": bo, "trail": true}))
			await until(settled)
			await wait(12)
	var best = best_shot(bo, squad_alive(), Data.ETYPES.boss.range)
	if best != null:
		await enemy_shoot(bo, best.t, Data.ETYPES.boss)

# ---------------------------------------------------------------- end states
func game_over() -> void:
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
	job_reward()
	sweep_loot(INF)
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
func _process(delta: float) -> void:
	acc += minf(0.1, delta) * 60.0 * speed
	var n := 0
	while acc >= 1.0 and n < int(4 * speed):
		step()
		acc -= 1.0
		n += 1
	T.flush()
	sync_chunks()
	var s := shake if shake > 0.6 else 0.0
	cam.position = Vector2(cam_x + W / 2.0 + round((randf() - .5) * s), H / 2.0 + round((randf() - .5) * s))
	view.queue_redraw()
	if ui_dirty and hud != null:
		ui_dirty = false
		hud.refresh()

func step() -> void:
	rotor_check()
	t += 1
	hold_fast()
	if stickies.size() and state == "enemy":
		sticky_watch()
	if t % 15 == 0 and tutorial():
		tut_update()
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
			drag_stragglers()
	elif cam_x > cam_tx and pincer.get("on", false):
		cam_x = maxf(cam_tx, cam_x - minf(9, (cam_x - cam_tx) * 0.08 + 1.2))  # W9: squad B's view slides left
	if pincer.get("on", false) and state == "player" and not busy and sel != null and not sel.dead and sel.team == "squad" and wing(sel) != pincer.view:
		set_view(wing(sel))
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
					ice_crack(u)
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
			lava_check(u)
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
					strip_wreck(p, u)
				if p.kind == "ride" and not p.gone and u.mech == null and absf(p.x - u.x) < 22 and absf(p.y - u.y) < 30:
					hijack(u, p)
				if p.kind == "pow" and not p.freed and absf(p.x - u.x) < 26 and absf(p.y - u.y) < 30:
					p.freed = true
					p.dead_t = 0
					float_text(p, "THANK YOU!", Color("62d26f"), true)
					pow_queue.append({"pow": p, "u": u})
	update_mines()
	update_wires()
	if pads.size():
		check_pads()
	for p in projs.duplicate():
		update_proj(p)
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
		hover_physics(u)
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
				cart_ram(u)
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
			if bounce_body(u, imp):
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
			ice_crack(u)
			u.vx = 0
			u.vy = 0
			if u.fl.get("crashing", false):
				gunship_crash(u)
			dicokka_land(u, imp)
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

func drown(u: Unit) -> void:
	## Worms rules: anything that ends up in the water goes under for good.
	if u.team == "squad" and not u.dead and u.s.get("trait", "") == "lifeguard" and lifeguard_swim(u):
		return
	splash(u.x)
	if vfx != null:
		vfx.add(SfBubbles.new(u.x, WATER_Y, H + 16, 1.2))
	u.sunk = true
	if not u.dead:
		var hw := hazard_word()
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

# ---------------------------------------------------------------- level hazards
var mine_air := {}  # unit id -> was airborne last frame
var mine_by := {}   # unit id -> who last sent it flying, kept past the landing that clears it

func prime_mine(m: Unit, owner, delay: int) -> void:
	m.primed = true
	m.flash = 40
	Sfx.play("tick")
	booms.append({"t": delay, "x": m.x, "y": m.y - 3, "r": 38.0, "dmg": 15, "owner": owner, "barrel": m})

func mine_under(u: Unit, x: float, y: float, pad: float = 0.0):
	## The armed mine a soldier standing at (x, y) would set off, with pad px of margin, or null.
	if u.team == "squad" and u.def.key == "finch":
		return null  # Light Feet
	for m in units:
		if m.kind == "mine" and not m.primed and not m.gone and absf(x - m.x) < u.w / 2.0 + 5 + pad and absf(y - m.y) < 8:
			return m
	return null

func stop_before_mines(u: Unit, sim: Dictionary) -> Dictionary:
	## Automatic walks (MOVE) stop short of the first armed mine on the path; stepping on one is
	## always the player's own call.
	var pts: Array = sim.pts
	var cut := pts.size()
	for i in pts.size():
		if mine_under(u, pts[i][0], pts[i][1], 4) != null or live_wire_at(pts[i][0], pts[i][1], 4) != null:
			cut = i
			break
	if cut == pts.size():
		return sim
	pts = pts.slice(0, cut)
	while pts.size() and pts[-1][2]:
		pts.pop_back()
	if pts.is_empty():
		return {"pts": pts, "x": u.x, "y": u.y, "used": 0.0}
	return {"pts": pts, "x": pts[-1][0], "y": pts[-1][1], "used": absf(pts[-1][0] - u.x)}

func make_jbox(x: float):
	## T2 live wire: a junction box with a sparking cable laid along the ground to its right.
	var by = T.stand_y(x, T.ground_at(x) - 40)
	if by == null:
		return null
	var u := mk_unit(); u.team = "neutral"; u.kind = "jbox"; u.x = x; u.y = by; u.w = 14; u.h = 20
	u.hp = 1; u.max_hp = 1; u.heavy = true; u.face = 1
	var ys: Array = []
	var wx := x + 10.0
	while wx <= x + 120.0:
		var wy = T.stand_y(wx, T.ground_at(wx) - 40)
		ys.append(wy if wy != null else float(WATER_Y))
		wx += CELL
	u.loot = {"x0": x + 10.0, "ys": ys, "on": true, "hit": {}}
	units.append(u)
	return u

func wire_y(j: Unit, x: float):
	## Height of a junction box's cable at x, or null if x is off its run.
	var i := int(round((x - j.loot.x0) / CELL))
	if i < 0 or i >= j.loot.ys.size():
		return null
	return j.loot.ys[i]

func live_wire_at(x: float, y: float, pad := 0.0):
	## The live junction box whose cable runs under (x, y), or null.
	for j in units:
		if j.kind == "jbox" and j.loot.on and not j.gone:
			for dx in [-pad, 0.0, pad]:
				var wy = wire_y(j, x + dx)
				if wy != null and absf(y - wy) < 6:
					return j
	return null

func update_wires() -> void:
	## T2: anyone standing on a live cable gets 4 damage and (Jackals) a stun, once a round each.
	for j in units:
		if j.kind != "jbox" or not j.loot.on or j.gone:
			continue
		if t % 9 == 0:
			var k: int = randi() % j.loot.ys.size()
			sparks(j.loot.x0 + k * CELL, j.loot.ys[k] - 1, 1)
		for u in units:
			if u.dead or u.gone or u.sunk or u.air or u.is_prop() or u.is_pickup() or u.kind == "pow" or u.kind == "jbox" or u.kind == "m2" or u.weight == "hover":
				continue
			if u.kind != "soldier" and u.kind != "enemy":
				continue
			var wy = wire_y(j, u.x)
			if wy == null or absf(u.y - wy) > 6 or j.loot.hit.get(u.id, -1) == round_n:
				continue
			j.loot.hit[u.id] = round_n
			var by = u.last_hit_by if u.team == "enemy" else null
			sparks(u.x, u.y - u.h / 2.0, 8)
			Sfx.play("click", 0, 2.2)
			float_text(u, "ZAP!", Color("53d4e2"), true)
			var was := kill_how
			kill_how = "ZAPPED"
			damage(u, 4, by, {"status": true})
			kill_how = was
			if not u.dead:
				add_status(u, "stun", 1, by)

func update_mines() -> void:
	## Jackal mines: your soldiers set them off by stepping on them. Jackals know where they
	## are buried and only set them off when they land on one, so knock them onto the field.
	var mines := units.filter(func(m): return m.kind == "mine" and not m.primed and not m.gone)
	for u in units:
		var was_air: bool = mine_air.get(u.id, false)
		mine_air[u.id] = u.air
		if u.air:
			mine_by[u.id] = u.last_hit_by
		if mines.is_empty() or (u.dead and not u.is_body()) or u.gone or u.sunk or u.air or u.is_prop() or u.kind == "pow" or u.para:
			continue
		if u.team != "squad" and not was_air:
			continue
		for m in mines:
			if not m.primed and absf(u.x - m.x) < u.w / 2.0 + 5 and absf(u.y - m.y) < 8:
				float_text(m, "CLICK!", Color("ff4d3d"), true)
				var by = mine_by.get(u.id) if was_air else null
				prime_mine(m, by if by is Unit and by.team == "squad" else null, 16)

func bridge_down(s: Dictionary) -> void:
	banner("BRIDGE DOWN!", Color("ffb23e"))
	Sfx.play("thud")
	shake += 8
	score += 200
	log_msg("The bridge is coming down. Anyone on it is going for a swim.")

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
		set_view(wing(u))
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
	var sq := bar_squad().filter(func(s): return not s.dead)  # W9: on the pincer, the half on screen
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
		var sim := stop_before_mines(u, sim_walk(u, u.x - u.move_left if west else u.x + u.move_left, u.move_left))
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
			switch_wing()
		elif ev.keycode == KEY_BRACKETRIGHT or ev.keycode == KEY_EQUAL:
			dial_fuse(1)
		elif ev.keycode == KEY_BRACKETLEFT or ev.keycode == KEY_MINUS:
			dial_fuse(-1)

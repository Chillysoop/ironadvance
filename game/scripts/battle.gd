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
var wind := 0
var score := 0
var combo := 0
var t := 0
var sel: Unit = null
var card_idx := -1
var mouse := Vector2(200, 300)
var log_lines: Array = []
var pow_queue: Array = []
var lvl_queue: Array = []
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
var jet_hold := false    # the mouse button is down while jetting
var pads: Array = []     # bonus pads on this map
var grav := GRAV         # this map's gravity: Mountain's thin air lowers it
var fuse_pick := 0       # frames of fuse the player dialed in with the wheel (0 = the card's own)
var feed: Array = []     # kill feed lines: {killer, how, victim, kc, stamp, t}
var kill_how := ""       # what is dealing the damage right now when it isn't a card (FALL, CRUSHED, BURN)
var act_card := ""       # name of the card behind the current action, for the kill feed
var pop_next := false    # the next kill was an overkill: the Jackal bursts instead of leaving a body
var stats := {"kills": 0, "pows": 0, "pushes": 0, "rounds": 0, "crushes": 0, "scrip": 0, "kia": 0, "max_alert": 0, "pows_total": 0, "loot": 0, "tags": 0, "best_combo": 0, "fallen": []}
var act_once := {}        # tag-team combos that pay out once per action
var act_crushed := 0      # Jackals crushed by debris during the current action (DOMINO)
var act_crush_at := Vector2.ZERO
var crate_bump := 0       # kill combo x5: the next crate rolls one rarity higher
var act_unit: Unit = null # who played the card that started the current action
var taunter: Unit = null  # Taunt: Jackals that can, shoot this soldier next phase
var lazarus_used := false
var last_hit_head := false
var burn_tick := false    # a burn status is dealing damage right now (feat tracking)
var relay_hand := 0       # captured relays (W3)
var relay_intel := false
var slug_given := false
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
var acids: Array = []     # acid pools from burst Hive Pods: {x, y, r, turns}
var detour := {}          # the camp detour being played: {id, x0, x1, done, left, scav, mod}
var th := {}              # the theme colors, with the biome's look laid over them
var rules := {}           # the biome's rules: sway, sight, wind, amp, wet, fuel, mines, elite
var world_w := 6400

@onready var cam: Camera2D = $Camera
@onready var terrain_sprite: Sprite2D = $TerrainSprite
@onready var chunk_layer: Node2D = $Chunks
@onready var view = $WorldView

# ---------------------------------------------------------------- setup
func setup(idx: int, custom := {}) -> void:
	mission_idx = idx
	mission = Data.MISSIONS[idx] if custom.is_empty() else custom
	rules = mission.get("rules", {})
	breach = mission.get("breach", false)
	Run.sway_mul = rules.get("sway", 1.0)
	grav = GRAV * rules.get("grav", 1.0)
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
	for s in Run.soldiers:
		if not s.alive:
			continue
		var x := 50.0 + i * 35
		var u := mk_unit()
		u.team = "squad"; u.kind = "soldier"; u.def = s.def; u.s = s; u.sheet = "sq_" + s.key
		u.gb = Run.gear_bonus(s)
		u.x = x; u.y = T.stand_y(x, 0); u.face = 1; u.max_hp = Run.eff_max_hp(s); u.hp = mini(s.hp, u.max_hp)
		u.dodge = s.def.dodge + s.bonus.dodge + int(u.g("dodge"))
		u.second_wind = s.perks.has("secondwind")
		u.fuel_max = int(u.g("jet"))
		u.fuel = u.fuel_max
		var deck: Array = s.deck.duplicate()
		deck.shuffle()
		u.draw = deck
		if Run.implanted(s, "adrenal"):
			u.adr = 25
		units.append(u)
		i += 1
	var pi := randi() % Data.POW_NAMES.size()
	var foot := 0  # plain rifleman and bomber slots seen so far (cast_foot)
	for sp in T.spawns:
		var type: String = sp[0]
		var x: float = sp[1]
		var opt: Dictionary = sp[2]
		if type == "barrel":
			var u := mk_unit(); u.team = "neutral"; u.kind = "barrel"; u.x = x; u.y = T.stand_y(x, 0); u.w = 14; u.h = 18
			units.append(u); continue
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
		if type == "pow":
			var u := mk_unit(); u.team = "neutral"; u.kind = "pow"; u.x = x; u.y = T.stand_y(x, T.ground_at(x) - opt.up) if opt.has("up") else T.stand_y(x, 0); u.face = -1
			u.pow_name = Data.POW_NAMES[pi % Data.POW_NAMES.size()]; pi += 1
			stats.pows_total += 1
			units.append(u); continue
		if type == "grunt" or type == "nade":
			type = cast_foot(foot)
			foot += 1
		var E: Dictionary = Data.ETYPES[type]
		var y = T.stand_y(x, 0) if (opt.has("hold") or opt.has("top")) and not opt.has("inside") else T.stand_y(x, T.ground_at(x) - 40)
		if opt.has("up"):
			y = T.stand_y(x, T.ground_at(x) - opt.up)
		var u := mk_enemy(type, x, y)
		u.hold = opt.has("hold")
		if type == "boss":
			var bm := 1.4 if Run.threat_on(5) else 1.0
			u.hp = int(mission.boss_hp * bm); u.max_hp = u.hp; u.plate = int(mission.plate * bm)
		elif randf() < 0.12 + mission_idx * 0.06 + (0.25 if Run.intel == "veterans" else 0.0) + (0.15 if Run.threat_on(2) else 0.0) + (0.6 if mission.get("outpost", false) else 0.0) + rules.get("elite", 0.0):
			make_elite(u, pick_elite(faction(u) == "vharr"))
		units.append(u)
		place_alien(u)
		for k in range(1, E.get("pack", 1)):
			var px := x + k * 18.0
			var mate := mk_enemy(type, px, T.stand_y(px, (y if y != null else 0.0) - 40))
			mate.hold = u.hold
			units.append(mate)
	place_encounter(mission.get("encounter", ""))
	spawn_map_loot()
	sel = null
	for u in units:
		if u.team == "squad":
			sel = u
	for u in units:
		if u.y == null:
			u.y = WATER_Y - 4

func collect(u: Unit, p: Unit) -> void:
	## A soldier walks over a pickup. Scrip, letters, trophies and belt items apply at once;
	## gear waits for an equip-or-stash decision after the current action.
	p.gone = true
	var L: Dictionary = p.loot
	match L.type:
		"scrip":
			give_scrip(L.n, p.x, p.y - 20)
			Sfx.play("coin")
		"letter":
			var key: String = Data.LETTERS[L.key]
			for i in 3:
				u.hand.append({"id": -2, "key": key, "tier": maxi(2, Data.base_tier(key)), "temp": true})
			banner(Data.CARDS[key].name.to_upper() + "!", Color("ffd23a"), "%s GOT 3 SHOTS. THEY LAST THIS MISSION." % u.def.name)
			Sfx.play("power")
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
	u.fuel_max = int(u.g("jet"))
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
			give_scrip(15, u.x, u.y - 50)
		"smoke":
			smokes.append({"x": u.x, "y": u.y - 24, "r": 64.0, "turns": 2, "seed": randf() * 10})
			for k in 5:
				puff(u.x + randf_range(-30, 30), u.y - randf_range(0, 40), 3.0)
		"energy":
			u.energy += 1
			float_text(u, "+1 ENERGY", Color("ffd23a"), true)
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
	# radio relays (W3): one or two per mission, each with its own buff
	var buffs: Array = Data.RELAY_BUFFS.keys()
	buffs.shuffle()
	for i in (2 if world_w > 4200 else 1):
		var x := lo + (hi - lo) * (0.3 + 0.4 * i) + randf_range(-60, 60)
		var y = T.stand_y(x, 0)
		if y == null:
			continue
		var r := mk_unit(); r.team = "neutral"; r.kind = "relay"; r.x = x; r.y = y; r.w = 12; r.h = 34
		r.loot = {"buff": buffs[i % buffs.size()], "taken": false}
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
		return {"type": "letter", "key": Data.LETTERS.keys()[randi() % Data.LETTERS.size()]}
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
		drop_loot(c.x, c.y - 8, crate_payload())
	ui_dirty = true

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
	u.sheet = "en_" + type if Art.meta.has("en_" + type) else ""
	return u

const ALIENS := ["skitter", "squid", "blinker"]

func cast_foot(n: int) -> String:
	## Who fills the nth plain rifleman or bomber slot. The Jackals' pact with the Vharr goes bad over
	## a run: level 1 keeps its riflemen with every fourth slot a Vharr advisor, later levels and the
	## finale give every slot to the Vharr. Bombers are gone either way.
	var tier := 2 if mission.get("finale", false) else mission_idx
	if tier == 0:
		return "grunt" if n % 4 != 3 else ALIENS[(n / 4) % ALIENS.size()]
	return ALIENS[n % ALIENS.size()]

func place_alien(u: Unit) -> void:
	## A hovering alien starts at its altitude instead of on the floor.
	if u.weight == "hover" and u.y != null:
		u.y = hover_y(u, u.x, u.y)

func kb(u: Unit) -> float:
	## Knockback multiplier for a weight class: light aliens fly twice as far.
	return 2.0 if u.weight == "light" else 1.0

func _ready() -> void:
	set_process_unhandled_input(true)

func begin() -> void:
	Sfx.play("start")
	banner("MISSION %d START!" % (mission_idx + 1), Color("ffb23e"), mission.name)
	if breach:
		log_msg("BREACH: the Vharr and the Jackals are fighting each other. Each shoots whoever is nearest, so let them.")
	activate_enemies()
	await wait(60)
	if state == "title":
		start_player_turn()

# ---------------------------------------------------------------- helpers
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
	if projs.size() or booms.size() or T.chunks.size() or absf(cam_x - cam_tx) >= 0.5:
		return false
	for u in units:
		if u.sunk or u.gone:
			continue
		if u.walk != null or u.zip != null or u.drill != null or (u.air and not u.para):
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
	texts.append({"u": u, "x": u.x, "y": u.y - u.h - 10 - n * 14, "text": text, "c": c, "big": big, "t": 0})

func float_at(x: float, y: float, text: String, c := Color.WHITE, big := false) -> void:
	texts.append({"u": null, "x": x, "y": y, "text": text, "c": c, "big": big, "t": 0})

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

const MATCOL := {1: Color("86582f"), 2: Color("8e939a"), 3: Color("80562e"), 4: Color("62503f"), 5: Color("6f777f"), 6: Color("a9b0b6")}

func debris(x: float, y: float, m: int, slow := false) -> void:
	var c: Color = MATCOL.get(m, Color("888888"))
	if slow:
		part({"x": x, "y": y, "vx": (randf() - .5) * 2, "vy": -1.0, "life": 50, "max": 50, "c": c, "s": 4.0, "g": 0.25})
	else:
		part({"x": x, "y": y, "vx": (randf() - .5) * 6, "vy": -randf() * 6 - 1, "life": 60, "max": 60, "c": c, "s": 3.0, "g": 0.25})

func fireball(x: float, y: float, r: float) -> void:
	# the big Metal Slug style sprite blast, plus embers and a shock ring
	fx.append({"kind": "boom", "x": x, "y": y, "t": 0, "dur": 42, "sc": clampf(r / 24.0, 0.7, 3.2)})
	if r > 40:
		fx.append({"kind": "boom", "x": x + randf_range(-r, r) * 0.4, "y": y - r * 0.3, "t": -6, "dur": 42, "sc": clampf(r / 40.0, 0.6, 2.0)})
	for i in int(r * 0.6):
		var a := randf() * TAU
		var s := randf() * r * 0.14 + 1
		part({"x": x, "y": y, "vx": cos(a) * s, "vy": sin(a) * s - 1.5, "life": 24 + ri(0, 20), "max": 44, "c": pick([Color("fff3b0"), Color("ffb23e"), Color("ff7a3d")]), "s": float(ri(2, 3)), "g": 0.12, "fire": true})
	for i in 6:
		puff(x + (randf() - .5) * r, y + (randf() - .5) * r * 0.5 - 6, randf_range(1.5, 2.6))
	part({"ring": true, "x": x, "y": y, "r": 4.0, "max": r * 1.25, "life": 14})

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
	if k == "stun" and (u.type == "boss" or u.team == "squad"):
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
			if last == "tagshot" and inst.key == "snipe":
				return "SPOTTED"
			if last == "digin" and c.get("overwatch", false):
				return "DUG IN"
			if c.type == "AIM" and u.fl.get("free_aim", false):
				return "DOUBLE BANK"
			if c.type == "AIM" and u.seq.size() >= 2 and u.seq[-1][1] == "AIM" and u.seq[-2][1] == "AIM" and not u.fl.has("sixgun"):
				return "SIX SHOOTER"
		"hex":
			if Data.is_attack(c) and u.seq.size() >= 2 and u.seq[-1][0] == "sprint" and u.seq[-2][0] == "smoke":
				return "FROM THE FOG"
			if inst.key == "shotgun" and u.fl.get("healed", false):
				return "SCRUBBED IN"
		"vee":
			if c.type in ["ARC", "LINE"] and c.has("dmg") and u.fl.get("jumped", false):
				return "DEATH FROM ABOVE"
			if c.has("radius") and u.fl.get("molotov", false) and inst.key != "molotov":
				return "ACCELERANT"
		"rook":
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
		for k in ["burn", "toxic", "mark", "berserk", "cloak", "flamegod", "vest"]:
			if u.st.has(k):
				u.st[k] -= 1
				if u.st[k] <= 0:
					u.st.erase(k)

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
		if u.dead or u.gone or u.sunk or u.kind == "pow" or u.is_pickup():
			continue
		if u.has_st("cloak") and shooter != null and shooter.team != u.team:
			continue  # PREDATOR: rounds pass right through the shimmer
		if u == shooter and travelled < 40:
			continue
		if shooter != null and u != shooter and u.team != "" and u.team == shooter.team and not (breach and faction(u) != faction(shooter)):
			continue  # bullets slip past teammates, explosions don't (in a BREACH the two factions aren't teammates)
		if u.kind == "slug":
			continue
		if x >= u.x - u.w / 2.0 and x <= u.x + u.w / 2.0 and y >= u.y - u.h and y <= u.y:
			return u
	return null

func trace_bullet(x: float, y: float, ang: float, max_len: float, bounces: int, shooter, pierce: bool, pass_mat := 0) -> Dictionary:
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
	while trav < max_len:
		var nx := px + dx * 2
		var ny := py + dy * 2
		trav += 2
		if ny > H or ny < -80 or nx < 0 or nx > world_w:
			segs.append([sx, sy, nx, ny])
			return {"segs": segs, "hits": hits, "pings": pings, "ping_d": ping_d, "len": trav, "end": null}
		var u = unit_at_point(nx, ny, shooter, trav, skip)
		if u != null:
			hits.append({"u": u, "x": nx, "y": ny, "dx": dx, "d": trav, "head": not u.heavy and not u.is_prop() and ny < u.y - u.h * 0.72})
			skip[u.id] = true
			if not pierce:
				segs.append([sx, sy, nx, ny])
				return {"segs": segs, "hits": hits, "pings": pings, "ping_d": ping_d, "len": trav, "end": null}
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
	var tr := trace_bullet(x, y, ang, c.range, c.get("bounce", 0) + bounce_bonus(a, sc), a, c.get("pierce", false), pm)
	if pm != 0:
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
			d = maxi(1, int(round(d * 0.25)))
			float_text(tg, "SHIELD", Color("c9d1da"))
			sparks(hh.x, hh.y, 6)
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
		if c.has("knock") and not tg.heavy and not tg.dead and not tg.is_prop():
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
		if s.x < u.x:
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
	if u == null or not (u is Unit) or u.team != "squad" or u.dead or n <= 0:
		return
	u.xp_gain += n
	var gained := Run.add_xp(u.s, n)
	for i in gained:
		lvl_queue.append(u)
		float_text(u, "LEVEL UP!", Color("ffd23a"), true)
		u.pose = "cheer"; u.pose_t = 50
		Sfx.play("levelup")
	ui_dirty = true

func give_scrip(n: int, x: float, y: float) -> void:
	if n <= 0:
		return
	Run.scrip += n
	stats.scrip += n
	float_at(x, y, "+%d$" % n, Color("ffd23a"))
	ui_dirty = true

func damage(tg: Unit, amt: int, src, o := {}) -> void:
	if tg.dead or tg.gone or amt <= 0:
		return
	if tg.kind == "pow":
		return
	var own = src if src != null and src is Unit and src.team == "squad" else null
	if tg.kind == "crate":
		open_crate(tg, false)
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
	if tg.kind == "loot" or tg.kind == "cache" or tg.kind == "relay" or tg.kind == "slug" or tg.kind == "pad":
		return
	if src is Unit and src != tg and src.has_st("berserk") and not o.get("status", false):
		amt *= 2
	if tg.has_st("flamegod"):
		float_text(tg, "FLAMEGOD", Color("ff9a3d"))
		return
	if tg.has_st("vest"):
		amt = int(ceil(amt / 2.0))
	if own != null and tg.team == "enemy" and not o.get("status", false) and own.payback > 0:
		amt += own.payback
		float_text(tg, "PAYBACK +%d" % own.payback, Color("9fb4c9"), true)
		own.payback = 0
	if own != null and tg.team == "enemy" and not o.get("status", false):
		if tg.has_st("mark"):
			tg.st.erase("mark")
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
	if tg.kind == "mine":
		if not tg.primed:
			prime_mine(tg, own, 4)
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
	if tg.team == "squad":
		if debug:
			print("[dmg r%d] %s -%d (hp %d) by %s %s" % [round_n, tg.def.key, amt, tg.hp, (src.team + ":" + (src.type if src.team != "squad" else src.def.key)) if src is Unit else str(src), str(o)])
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
		tg.pose = "hurt"; tg.pose_t = 16
		Sfx.play("hurt")
		float_text(tg, "-%d" % amt, Color("ff4d3d"), o.get("crit", false))
		if tg.hp <= 0:
			kill(tg, src)
		elif own == null:
			gain_adr(tg, amt * 5)
	else:
		tg.hp -= amt
		tg.pose = "hurt"; tg.pose_t = 12
		float_text(tg, str(amt), Color("ffb23e") if o.get("crit", false) else Color.WHITE, o.get("crit", false))
		if own != null and tg.team == "enemy":
			give_xp(own, maxi(1, int(amt / 3)))
		if tg.hp <= 0:
			# R2: overkill by half its health or more and the Jackal bursts into helmet, boots and smoke
			pop_next = tg.kind == "enemy" and tg.type != "boss" and -tg.hp >= maxi(6, tg.max_hp / 2)
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

func kill(tg: Unit, src) -> void:
	if tg.dead:
		return
	tg.dead = true
	tg.hp = 0
	tg.dead_t = 0
	tg.walk = null
	tg.overwatch = 0
	feed_kill(tg, src)
	if pop_next and tg.kind == "enemy":
		overkill_pop(tg)
	elif tg.kind == "enemy" and tg.type != "boss":
		# the body stays where it drops: it stops one bullet, and blasts throw it like a sandbag
		tg.soak = 1
		tg.w = 26
		tg.h = 12
		var bodies := units.filter(func(o): return o.is_body())
		if bodies.size() > BODY_MAX:
			bodies[0].soak = 0
	if tg.team == "enemy":
		stats.kills += 1
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
		give_scrip(int(maxi(2, base / 25) * (1.5 if Run.has_cmd("warchest") else 1.0)), tg.x, tg.y - tg.h - 50)
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
			gain_adr(src, 8 + int(src.g("kill_adr")))
			give_xp(src, 4 + base / 50)
			if src.g("kill_draw") > 0 and not src.kill_drawn and state == "player":
				src.kill_drawn = true
				draw_cards(src, int(src.g("kill_draw")))
				float_text(src, "SPARE MAG: DRAW", Color("53d4e2"))
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
		if tg.type == "boss":
			boss_dead = true
			drop_loot(tg.x, tg.y - 40, {"type": "item", "item": Run.roll_item(Data.TIER_MAX)}, 1.4)
			var part_name: String = Data.TROPHIES[mini(mission_idx, Data.TROPHIES.size() - 1)]
			if not Run.trophies.has(part_name):
				drop_loot(tg.x + 20, tg.y - 40, {"type": "trophy", "name": part_name}, 1.2)
			for i in 7:
				booms.append({"t": 10 + i * 14, "x": tg.x + (randf() - .5) * 90, "y": tg.y - 20 - randf() * 40, "r": 34.0, "dmg": 0, "owner": null})
	elif tg.team == "squad":
		stats.kia += 1
		if tg.s.tags > 0:
			# a dog tag buys their life: out until the next camp, or back next mission
			tg.s.tags -= 1
			tg.downed = true
			float_text(tg, "DOWN! %d TAG%s LEFT" % [tg.s.tags, "" if tg.s.tags == 1 else "S"], Color("ffb23e"), true)
			log_msg("%s is down until the next camp. %d dog tag%s left." % [tg.def.name, tg.s.tags, "" if tg.s.tags == 1 else "s"])
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
	var victim: String = (Data.ETYPES[tg.type].name if tg.team == "enemy" else tg.def.name).to_upper()
	var stamp := ""
	if pop_next:
		stamp = "OVERKILL!"
	elif last_hit_head and src is Unit and src.team == "squad":
		stamp = "HEADSHOT!"
	elif tg.air and how in ["FALL", "SLAM"]:
		stamp = "SPLAT!"
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
	float_text(u, label, Color("e8dcc2"))
	shake += 2
	Sfx.play("bonk")
	var src = u.last_hit_by if u.last_hit_by != null and u.last_hit_by != u else null
	if src != null and src is Unit and src.perk("bulldozer"):
		d *= 2
	var was := kill_how
	kill_how = label
	damage(u, d, src, {})
	kill_how = was

func crush(u: Unit, d: int, cause, kvx: float, kvy: float) -> void:
	## Called by the terrain when falling or toppling debris lands on a body.
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
	var was := kill_how
	kill_how = "CRUSHED"
	damage(u, d, cause, {})
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
	fireball(x, y, r)
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
		if not u.heavy and not u.is_prop() and not u.immovable:
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
		if u.dead or u.gone or u.kind == "pow" or u.is_pickup():
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
	var pc: Dictionary = p.card
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
				p.x = px
				p.y = py
				if sx or not sy:
					p.vx = -p.vx * 0.45
				if sy or not sx:
					p.vy = -p.vy * 0.4
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
				x = px
				y = py
				if hx or not hy:
					vx = -vx * 0.45
				if hy or not hx:
					vy = -vy * 0.4
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
	ui_dirty = true
	act_once = {}
	act_crushed = 0
	await fn.call()
	await until(settled)
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
	return cost

func spend_card(u: Unit, idx: int, c_in = null) -> Dictionary:
	## Pays for a card and applies everything that happens on play: signature chains (C2),
	## perks and keystones that change the card, momentum. Pass the card dict the action
	## will use so chain bonuses reach it.
	var inst: Dictionary = u.hand[idx]
	var c: Dictionary = c_in if c_in != null else Data.card(inst)
	var cost := card_cost(u, inst)
	var ch := chain_ready(u, inst)
	if Data.is_attack(c) and u.st.has("cloak"):
		u.st.erase("cloak")
		float_text(u, "DECLOAKED", Color("b48cff"))
	u.hand.remove_at(idx)
	u.energy -= cost
	u.last_cost = cost
	act_unit = u
	act_card = c.get("name", "")
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
	u.seq.append([inst.key, c.type])
	if inst.key == "molotov":
		u.fl["molotov"] = true
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

func jump_vel(u: Unit, p: Vector2, mul := 1.0) -> Dictionary:
	var hp_ := hand_pos(u)
	var dx := p.x - hp_.x
	var dy := p.y - hp_.y
	var d := maxf(0.001, sqrt(dx * dx + dy * dy))
	var reach := 240.0 * mul
	var pw := clampf(minf(d, reach) / reach * 10.5 * mul, 3, 10.5 * mul)
	return {"vx": dx / d * pw, "vy": minf(-2.5, dy / d * pw), "hx": hp_.x, "hy": hp_.y}

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
	if c.type == "AIM":
		resolve(func(): await _act_aim(u, idx, c, p, sc))
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
		if c.get("drill", false):
			if u.move_left + c.get("reach", 0) < 4:
				float_text(u, "NO MOVE LEFT", Color("ff7a3d"))
				Sfx.play("deny")
				return
			resolve(func(): await _act_drill(u, idx, c, p))
			return
		if c.get("jump", false):
			if c.get("hop", false) and u.move_left < 1:
				float_text(u, "NO MOVE LEFT", Color("ff7a3d"))
				return
			resolve(func(): await _act_jump(u, idx, p))
			return
		if c.get("rush", false):
			resolve(func(): await _act_rush(u, idx, p))
			return
		resolve(func(): await _act_rocket(u, idx, c, p, sc))

func _act_aim(u: Unit, idx: int, c: Dictionary, p: Vector2, sc: bool) -> void:
	var kick := recoil_vel(u, c, aim_angle(u, c, p).a)
	spend_card(u, idx, c)
	if u.fl.has("breath"):
		c.dmg = [c.dmg[0] + u.fl.breath, c.dmg[1] + u.fl.breath]
		u.fl.erase("breath")
	u.attacked = true
	await fire_aim(u, c, p, sc)
	await apply_recoil(u, kick)
	await wait(6)

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
	var x := u.x
	var y := u.y
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
		"x": v.hx, "y": v.hy, "vx": v.vx, "vy": v.vy, "wind": c.get("wind", 1.0), "r": r,
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
	u.fl["jumped"] = true
	if c.get("hop", false):
		u.move_left = 0  # a hop is the rest of your legwork for the turn
	if c.get("rjump", false):
		explode(u.x, u.y - 4, 30, 6, u)
		await wait(2)
	var v := jump_vel(u, p, c.get("jpow", 1.0))
	u.face = 1 if v.vx >= 0 else -1
	u.vx = v.vx; u.vy = v.vy; u.air = true; u.jumping = true; u.walk = null
	Sfx.play("rocket")
	for i in 10:
		part({"x": u.x, "y": u.y, "vx": (randf() - .5) * 2, "vy": randf() * 2, "life": 24, "max": 24, "c": pick([Color("ffb23e"), Color("ff7a3d"), Color("9a9a9a")]), "s": 3.0, "g": 0.05, "fire": true})
	if c.get("frags", 0) > 0:
		await until(func(): return u.vy >= 0 or not u.air or u.dead)
		for k in c.frags:
			projs.append(mk_proj({"kind": "frag", "x": u.x, "y": u.y - 10, "vx": (k - 1) * 1.6 + u.vx * 0.3, "vy": 1.0, "r": 34.0 * blast_scale(u), "dmg": 11, "bounce": true, "fuse": 50 + k * 10, "owner": u}))
		Sfx.play("toss")
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
	return minf(want, u.move_left + c.get("reach", 0))

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
	u.move_left = maxf(0.0, u.move_left - maxf(0.0, used - reach))
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
	await until(func(): return not u.air or u.dead)
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
	u.face = 1 if tg.x >= u.x else -1
	u.pose = "throw"; u.pose_t = 16
	Sfx.play("slash")
	fx.append({"kind": "slash", "x": tg.x, "y": tg.y - tg.h / 2.0, "t": 0, "dur": 12, "sc": 1.6, "face": u.face})
	await wait(6)
	var d := ri(c.dmg[0], c.dmg[1])
	if sc:
		d = int(round(d * 1.25))
	var victims: Array = [tg]
	if ks(u, "zantetsu") and c.key == "knife":
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
	return h + int(u.g("heal"))

func _act_ally(u: Unit, idx: int, c: Dictionary, tg: Unit) -> void:
	spend_card(u, idx, c)
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
	resolve(func(): await _act_self(u, idx, c))

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
	if c.has("armor"):
		u.armor += c.armor
		float_text(u, "+%d ARMOR" % c.armor, Color("9fb4c9"))
		Sfx.play("select")
	if c.has("move"):
		u.move_left += c.move
		float_text(u, "+%d MOVE" % c.move, Color("b48cff"))
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
				float_text(s, "+%d MOVE" % c.rally, Color("b48cff"))
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
	return tg != null and not tg.dead and (tg.team == "enemy" or tg.is_prop()) and absf(tg.x - u.x) <= c.range + tg.w / 2.0 and absf(tg.y - u.y) <= 30

func ally_valid(u: Unit, tg, c: Dictionary) -> bool:
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
	resolve(func(): await _act_walk(u, pl.pts, pl.cost))

func do_move(u: Unit, tx: float) -> void:
	var sim := sim_walk(u, tx, u.move_left)
	if sim.pts.is_empty():
		return
	resolve(func(): await _act_walk(u, sim.pts, sim.used))

func _act_walk(u: Unit, pts: Array, cost: float) -> void:
	u.move_left = maxf(0, u.move_left - cost)
	u.moved = true
	await walk_along(u, pts)
	await check_push(u)

# ---------------------------------------------------------------- screen scrolling
func check_push(u: Unit) -> void:
	await check_camp(u)
	if u.dead or cam_x >= world_w - W:
		return
	if u.x - cam_x > W * 0.72:
		await scroll_to(clampf(u.x - W * 0.5, cam_x, world_w - W), "push", u)

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
	Sfx.play("levelup")
	await wait(30)
	var i := 0
	for s in squad():
		if s.dead and s.downed:
			# back on their feet at half HP, by the fire
			s.dead = false
			s.downed = false
			s.gone = false
			s.alpha = 1.0
			s.hp = int(ceil(s.max_hp / 2.0))
			s.x = c.fire - 40 + i * 26
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
			for s in squad_alive():
				var cands: Array = s.s.deck.filter(func(cd): return Run.upgradable(cd))
				if cands.size():
					var cd: Dictionary = pick(cands)
					Run.raise_tier(cd)
					float_text(s, Data.card(cd).name.to_upper(), Color("b48cff"))
			Sfx.play("levelup")
		"cache":
			give_scrip(60, c.fire, T.ground_at(c.fire) - 40)
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

func pick_detour() -> void:
	## The mid-level camp: pick one side job for the clearing ahead, or press on.
	var opts: Array = mission.detours.map(func(id): return {"kind": "service", "title": "DETOUR", "icon": Data.DETOURS[id].icon, "name": Data.DETOURS[id].name, "text": "%s PAYS: %s" % [detour_text(id), Data.DETOURS[id].pays], "id": id})
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
				detour_enemy(sp[0], x0 + sp[1], detour.mod)
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
	banner(D.name, Color("ffb23e"), "PAYS: " + D.pays)
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
			if slots.size():
				var o: Dictionary = Run.recruit_offers(1)[0]
				var s := Run.hire(slots[0], o)
				banner("ALL PRISONERS FREE!", Color("62d26f"), "%s JOINS THE SQUAD AT HQ" % s.def.name)
				log_msg("%s, a freed %s, signs up. They will be waiting at HQ." % [s.def.name, s.def.cls])
			else:
				var need: Array = squad_alive().filter(func(u): return u.s.tags < Data.DOG_TAGS)
				need.sort_custom(func(a, b): return a.s.tags < b.s.tags)
				if need.size():
					need[0].s.tags += 1
					banner("ALL PRISONERS FREE!", Color("62d26f"), "%s GETS A DOG TAG BACK" % need[0].def.name)
					float_text(need[0], "+1 DOG TAG", Color("62d26f"), true)
				else:
					banner("ALL PRISONERS FREE!", Color("62d26f"), "+50 SCRIP")
					give_scrip(50, cx, T.ground_at(cx) - 40)
		"salvage":
			banner("YARD STRIPPED!", Color("62d26f"), "%d SALVAGE FOR HQ" % int(stats.get("salvage", 0)))
		"cache":
			banner("CACHE SECURED!", Color("62d26f"), "+80 SCRIP AND A CARD")
			give_scrip(80, cx, T.ground_at(cx) - 40)
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

func scroll_to(tx: float, reason: String, who = null) -> void:
	tx = clampf(tx, 0, world_w - W)
	if tx <= cam_x + 4:
		return
	cam_tx = tx
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
	sweep_loot(cam_x)
	activate_enemies()
	await until(settled)
	ui_dirty = true

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
			ny = T.stand_y(nx, maxf(0, s.y - 60))
			if ny != null and mine_under(s, nx, ny, 6) != null:
				ny = null  # never drop a straggler onto an armed mine
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
		if e.x < cam_x + W + 40:
			e.active = true
			if e.type == "radio" and radio_t == null:
				radio_t = 3 + jammer_rounds()
				log_msg("A radioman is calling for backup. Paratroopers in %d rounds unless you drop him." % radio_t)
			if e.type == "boss" and not boss_active:
				boss_active = true
				banner("WARNING!!", Color("ff4d3d"), "IRON BOAR APPROACHING")
				Sfx.play("alarm")
				log_msg("The IRON BOAR rolls in. Something heavy is hanging over it...")

# ---------------------------------------------------------------- rewards & level-ups
func ask(kind: String, title: String, sub: String, opts: Array, who = null) -> int:
	## Shows a pick-one modal on the HUD and waits for the answer (-1 = skip).
	if autopick >= 0 or hud == null:
		return mini(autopick if autopick >= 0 else 0, opts.size() - 1)
	return await hud.pick(kind, title, sub, opts, who)

func supply_drop(title: String, for_unit) -> void:
	var alive := squad_alive()
	if alive.is_empty():
		return
	var pool: Array = Data.offer_keys()
	pool.shuffle()
	var opts: Array = []
	for i in 3:
		var u: Unit = for_unit if for_unit != null else pick(alive)
		if i == 2 and randf() < 0.35:
			var it := Run.roll_item()
			opts.append(Run.item_opt(it, "").merged({"u": u}))
		else:
			opts.append({"kind": "card", "key": pool[i], "tier": Run.roll_card_tier(pool[i]), "u": u})
	var sub := ("%s freed them. Pick one card for %s's deck." % [for_unit.def.name, for_unit.def.name]) if for_unit != null else "Pick one card. It goes into that soldier's draw pile."
	var ch := await ask("supply", title, sub, opts)
	if ch >= 0 and opts[ch].kind == "item":
		await offer_item(opts[ch].u, opts[ch].item)
	elif ch >= 0:
		var o: Dictionary = opts[ch]
		var inst := Run.new_card(o.key, o.tier)
		o.u.s.deck.append(inst)
		o.u.draw.insert(ri(0, o.u.draw.size()), inst)
		log_msg("%s added to %s's deck." % [Data.CARDS[o.key].name, o.u.def.name])
		Sfx.play("coin")
	ui_dirty = true

func level_up(u: Unit) -> void:
	if u.dead:
		return
	banner("LEVEL UP!", Color("ffd23a"), "%s IS NOW LEVEL %d" % [u.def.name, u.s.lvl])
	bark(u, pick(Data.BARKS.lvl))
	var opts := Run.level_options(u.s)
	var picks := 1
	if Run.extra_picks > 0:
		Run.extra_picks -= 1
		picks = 2
	while picks > 0 and opts.size():
		var ch := await ask("level", "%s  LEVEL %d" % [u.def.name, u.s.lvl], "Pick %s: a new card, a stat boost or an ability." % ("two" if picks > 1 else "one"), opts, u)
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
			give_scrip(15, u.x, u.y - u.h - 20)
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
	log_msg(line)
	Sfx.play("power")
	ui_dirty = true

func post_action() -> void:
	var front: Array = squad_alive().filter(func(s): return not s.air)
	front.sort_custom(func(a, b): return a.x > b.x)
	if front.size() and not boss_dead:
		await check_push(front[0])
	while pow_queue.size():
		var q: Dictionary = pow_queue.pop_front()
		banner("POW RESCUED!", Color("62d26f"), "+500  +25$")
		score += 500
		stats.pows += 1
		give_scrip(25, q.pow.x, q.pow.y - 50)
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
	var active := units.filter(func(e): return e.team == "enemy" and not e.dead and e.active)
	if active.is_empty():
		var rest := units.filter(func(e): return e.team == "enemy" and not e.dead)
		if rest.size():
			banner("WAVE CLEAR!", Color("62d26f"), "+300  +15$")
			score += 300
			give_scrip(15, cam_x + W / 2.0, 200)
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
	alert = mini(10, alert + 1)
	banner("RELAY CAPTURED: " + bf.name, Color("53d4e2"), bf.text.to_upper() + "  ALERT +1")
	Sfx.play("power")
	give_xp(s, 4)
	log_msg("%s captured a radio relay: %s Alert +1." % [s.def.name, bf.text])

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
	await until(func(): return not sl.air)
	sl.rushing = false
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

func stow_hand(s: Unit) -> void:
	for c in s.hand:
		if not c.get("od", false) and not c.get("temp", false):
			s.disc.append(c)
	s.hand = s.hand.filter(func(c): return c.get("od", false) or c.get("temp", false))

func hand_size(s: Unit) -> int:
	return maxi(2, 4 + s.s.bonus.hand + (1 if s.perk("fieldkit") else 0) + (1 if Run.implanted(s.s, "thirdarm") else 0) + relay_hand - (1 if Run.threat_on(3) else 0))

func start_player_turn() -> void:
	round_n += 1
	stats.rounds = round_n
	wind = int(round(ri(-6, 6) * rules.get("wind", 1.0)))
	combo = 0
	for s in squad_alive():
		s.energy = 3
		if round_n == 1:
			s.energy += s.s.bonus.energy1 + int(s.g("energy1")) + (1 if Run.has_gear("bandolier") else 0)
		elif round_n == 2 and Run.relic_tier("bandolier") >= 3:
			s.energy += 1
		s.move_left = s.def.spd + s.s.bonus.move + int(s.g("move")) + (60 if s.perk("charge") else 0)
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
		if s.g("regen") > 0 and s.hp < s.max_hp:
			var rg := mini(int(s.g("regen")), s.max_hp - s.hp)
			s.hp += rg
			float_text(s, "+%d HP" % rg, Color("62d26f"))
		s.overwatch = 0
		s.dragged = false
		if s.fuel_max > 0 and not s.air:
			s.fuel = s.fuel_max
		stow_hand(s)
		draw_cards(s, hand_size(s))
		if not s.hand.any(func(c): return c.key == "hop"):
			s.hand.append({"id": -4, "key": "hop", "tier": Data.base_tier("hop"), "temp": true})
		if s.adr >= 100 and not s.hand.any(func(c): return c.get("od", false) and not c.has("duo")):
			grant_overdrive(s)
	refresh_duos()
	var al0 := squad_alive()
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
	log_msg("Round %d. Alert %d/10.%s" % [round_n, alert, " The line has stalled: alert is rising." if rounds_since_scroll >= 2 else ""])
	ui_dirty = true
	resolve(func(): await wait(1))

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
			if u.dead or u.gone or u.sunk or u.air or not (u.kind == "soldier" or u.kind == "enemy") or u.type == "boss":
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
	if u == null or u.dead or u.team != "squad":
		return false
	if u.move_left > 1:
		return true
	return u.hand.any(func(c): return card_cost(u, c) <= u.energy)

func ready_count() -> int:
	return squad_alive().filter(can_act).size()

func end_turn(force := false) -> void:
	if state != "player" or busy:
		return
	# first press warns when someone can still act; a second press within ~2.5s ends the turn
	if not force and ready_count() > 0 and end_confirm_t <= 0:
		end_confirm_t = 150
		Sfx.play("tick")
		ui_dirty = true
		return
	end_confirm_t = 0
	for r in units.filter(func(o): return o.kind == "relay" and not o.loot.taken):
		for s in squad_alive():
			if absf(s.x - r.x) < 26 and absf(s.y - r.y) < 30:
				capture_relay(r, s)
				break
	for s in squad_alive():
		if s.perk("tracker") and s.energy > 0:
			s.overwatch += s.energy
			float_text(s, "TRACKING +%d" % s.energy, Color("53d4e2"))
			s.energy = 0
		stow_hand(s)
	card_idx = -1
	enemy_phase()

func enemy_phase() -> void:
	state = "enemy"
	busy = true
	ui_dirty = true
	banner("ENEMY PHASE", Color("ff4d3d"))
	await wait(45)
	for m in units.filter(func(e): return e.elite == "medic" and not e.dead and e.active):
		for e in units:
			if e.team == "enemy" and not e.dead and e != m and e.hp < e.max_hp and absf(e.x - m.x) < 140:
				e.hp = mini(e.max_hp, e.hp + 4)
				float_text(e, "+4", Color("62d26f"))
	tick_statuses("enemy")
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
	for sl in units.filter(func(u): return u.kind == "slug" and not u.gone):
		await slug_act(sl)
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
		if e.x > cam_x + W + 60:
			continue
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
		pow_queue.pop_front()
		score += 500
		stats.pows += 1
	await check_detour()
	await detour_round()
	if squad_alive().is_empty():
		game_over()
		return
	if boss_dead:
		await until(settled)
		victory()
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
	# alert only climbs when you stall; the radioman's clock is what brings fresh bodies
	rounds_since_scroll += 1
	var before := alert
	var calls := 0
	if rounds_since_scroll >= (1 if Run.threat_on(1) else 2):
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
	if rounds_since_scroll >= 3 and alert >= 6 and not boss_dead and randf() < 0.4:
		calls += 1
	if calls and not boss_dead:
		var n := 1 + alert / 4
		for i in n:
			var type: String = pick(["grunt", "grunt", "shield", "sapper"] if mission_idx == 0 else ["skitter", "blinker", "shield", "sapper"])
			var e := mk_enemy(type, cam_x + W - 60 - randf() * 240, -30.0 - i * 40)
			e.active = true; e.heavy = false; e.air = true; e.para = true
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
	if squad_alive().is_empty():
		game_over()
		return
	start_player_turn()

func best_shot(e: Unit, targets: Array, rng: float):
	var best = null
	if Run.intel == "fog":
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
		var sc: float = vis * 30 - d / 10 + (-10 if tg.armor else 0) + (tg.max_hp - tg.hp) * 0.5 + (500 if tg == taunter else 0)
		if best == null or sc > best.sc:
			best = {"t": tg, "vis": vis, "sc": sc}
	return best

func enemy_shoot(e: Unit, tg: Unit, spec: Dictionary) -> void:
	e.st.erase("cloak")
	var shots: int = spec.get("shots", 1)
	for s in shots:
		if tg.dead or e.dead:
			break
		e.face = 1 if tg.x >= e.x else -1
		var m := muzzle(e)
		var pts := visible_points(m.x, m.y, tg)
		var py: float = pick(pts) if pts.size() else tg.y - tg.h / 2.0
		var err := maxf(0.015, 0.075 - (10 if e.elite == "veteran" else alert) * 0.005) + tg.dodge * 0.002
		var ang := atan2(py - m.y, tg.x - m.x) + gauss() * err
		if e.type == "boss":
			e.aim_a = clampf(atan2(-(py - m.y), -(tg.x - m.x)), -0.4, 0.6)
		e.gun_target = atan2(sin(ang), cos(ang) * e.face)
		Sfx.play("mg" if shots > 1 else "shot")
		e.muzzle = 4
		e.pose = "recoil"; e.pose_t = 6
		fire_bullet(e, m.x, m.y, ang, {"dmg": spec.dmg, "range": spec.get("range", 460) + 240, "bounce": 0}, false)
		await wait(7 if shots > 1 else 14)

func overwatch_check(e: Unit) -> void:
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
			await until(func(): return not e.air or e.dead)
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
			await until(func(): return not e.air or e.dead)
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

func nearest_squad(e: Unit):
	if taunter != null and not taunter.dead and absf(taunter.x - e.x) < 520:
		return taunter
	var best = null
	for s in foes_of(e):
		if s.team == "squad" and not targetable(e, s):
			continue
		if best == null or absf(s.x - e.x) < absf(best.x - e.x):
			best = s
	return best

func faction(u: Unit) -> String:
	return Data.ETYPES[u.type].get("faction", "jackal") if u.team == "enemy" else ""

func foes_of(e: Unit) -> Array:
	## Who an enemy fights: your squad, and in a BREACH biome the other faction's active units too.
	## Spawners (Hive Pods, tunnels) stay out of it.
	var out := squad_alive()
	if breach and e.team == "enemy":
		var f := faction(e)
		for o in units:
			if o.team == "enemy" and o.active and not o.dead and not o.gone and not o.sunk and faction(o) != f and not Data.ETYPES[o.type].get("static", false) and o.type != "boss":
				out.append(o)
	return out

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
	if await jackal_nade(e):
		return
	var pad = pad_in_reach(e, E.get("speed", 0)) if not e.hold and E.get("speed", 0) > 0 and not E.get("static", false) else null
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
	match e.type:
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
			fx.append({"kind": "slash", "x": tt.x, "y": tt.y - tt.h / 2.0, "t": 0, "dur": 12, "sc": 1.6, "face": e.face})
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
	if not T.solid(u.x, ny - u.h) and not T.solid(u.x, ny):
		u.y = ny
	u.air = absf(u.vx) > 0.3 or absf(ty - u.y) > 1.5
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
	var E: Dictionary = Data.ETYPES.skitter
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
		if o == e or o.dead or o.gone or o.sunk or o.type == "skitter" or (o.team != "squad" and o.team != "enemy"):
			continue
		if absf(o.x - e.x) < 20 + o.w / 2.0 and absf(o.y - e.y) < 30:
			Sfx.play("slash")
			fx.append({"kind": "slash", "x": o.x, "y": o.y - o.h / 2.0, "t": 0, "dur": 10, "sc": 1.0, "face": e.face})
			damage(o, E.dmg, e, {})

func beam_path(e: Unit, ang: float) -> Dictionary:
	## The squid ray: a straight line that passes through one wall up to 28px thick.
	## Returns {end: Vector2, hits: [Unit]}; everything on the line is hit, Jackals included.
	var E: Dictionary = Data.ETYPES.squid
	var o := e.center()
	var dv := Vector2(cos(ang), sin(ang))
	var walls := 0
	var thick := 0.0
	var hits: Array = []
	var d := 8.0
	while d < E.range:
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
			if u == e or u.dead or u.gone or u.sunk or u.is_pickup() or u.kind == "pow" or hits.has(u):
				continue
			if absf(u.x - p.x) < u.w / 2.0 + 1 and p.y > u.y - u.h and p.y < u.y + 1:
				hits.append(u)
		d += 3
	return {"end": o + dv * E.range, "hits": hits}

func fire_beam(e: Unit, ang: float) -> void:
	var E: Dictionary = Data.ETYPES.squid
	var bp := beam_path(e, ang)
	if debug:
		print("[beam] from ", e.center(), " to ", bp.end, " hits ", bp.hits.map(func(h): return h.team + ":" + h.type))
	var o := e.center()
	e.face = 1 if cos(ang) >= 0 else -1
	Sfx.play("snipe")
	e.muzzle = 4
	for k in 3:
		tracers.append({"x1": o.x, "y1": o.y + k - 1, "x2": bp.end.x, "y2": bp.end.y + k - 1, "c": Color("c47bff") if k != 1 else Color("9df25c"), "t": 14})
	sparks(bp.end.x, bp.end.y, 5)
	for u in bp.hits:
		damage(u, int(round(E.dmg * (1 + alert * 0.06))), e, {})
	await wait(14)

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
	for i in 8:
		part({"x": e.x, "y": e.y - i * 4, "vx": 0.0, "vy": -1.0, "life": 24, "max": 24, "c": Color("c47bff"), "s": 3.0, "g": 0.0})
	Sfx.play("power")
	e.face = 1 if r.x >= e.x else -1
	e.x = r.x
	e.y = r.y
	e.air = false
	e.vx = 0
	e.vy = 0
	for i in 8:
		part({"x": e.x + (i - 4) * 3, "y": e.y - 16, "vx": (i - 4) * 0.5, "vy": -0.5, "life": 24, "max": 24, "c": Color("9df25c"), "s": 3.0, "g": 0.0})
	await wait(12)

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
		fx.append({"kind": "slash", "x": tt.x, "y": tt.y - tt.h / 2.0, "t": 0, "dur": 12, "sc": 1.4, "face": e.face})
		await wait(8)
		damage(tt, int(round(E.dmg * (1 + alert * 0.06))), e, {})
		if not tt.dead and not tt.immovable and not tt.heavy:
			tt.vx = e.face * E.knock * kb(tt); tt.vy = -3.5; tt.air = true; tt.walk = null; tt.bumped = null; tt.last_hit_by = e
		await until(settled)

func tick_acids() -> void:
	## End of the enemy phase: anyone but the Vharr standing in Hive acid takes 3.
	for a in acids:
		for u in units:
			if u.dead or u.gone or u.sunk or u.is_prop() or u.is_pickup() or u.kind == "pow" or faction(u) == "vharr":
				continue
			if absf(u.x - a.x) < a.r and absf(u.y - a.y) < 20:
				float_text(u, "ACID", Color("9df25c"))
				damage(u, 3, null, {"status": true})
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
	## E1 Swarm or E2 Nest in the first fighting stretch after the mid camp's yard.
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
			projs.append(mk_proj({"kind": "shell", "x": m.x, "y": m.y, "vx": sol.vx * k, "vy": sol.vy * k, "wind": 1.0, "r": 44.0, "dmg": int(round(13 * (1 + alert * 0.06))), "owner": bo, "trail": true}))
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
	Run.scrip += pay
	stats.scrip += pay
	stats["pay"] = pay
	stats["alert_bonus"] = ab
	stats["surv_bonus"] = sb
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
		elif u.dead:
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
	t += 1
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
		drag_stragglers()
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
			u.y = lerpf(z.y0, z.y1, k) - sin(k * PI) * 30
			if k >= 1:
				u.x = z.x1
				u.y = z.y1
				u.zip = null
				u.air = false
			continue
		if u.walk != null:
			for k in 2:
				if u.walk_i >= u.walk.size():
					u.walk = null
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
		if u.team == "squad" and not u.dead:
			for p in units:
				if p.kind == "loot" and not p.gone and not p.sunk and absf(p.x - u.x) < (66 if Run.implanted(u.s, "magnet") else 22) and absf(p.y - u.y) < 30:
					collect(u, p)
				if p.kind == "wreck" and not p.stripped and absf(p.x - u.x) < 28 and absf(p.y - u.y) < 30:
					strip_wreck(p, u)
				if p.kind == "pow" and not p.freed and absf(p.x - u.x) < 26 and absf(p.y - u.y) < 30:
					p.freed = true
					p.dead_t = 0
					float_text(p, "THANK YOU!", Color("62d26f"), true)
					pow_queue.append({"pow": p, "u": u})
	update_mines()
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
		if o == u or o.dead or o.gone or o.sunk or o.kind == "pow" or o.para or o.is_pickup() or u.is_pickup():
			continue
		if (u.kind == "slug" and o.team == "squad") or (o.kind == "slug" and u.team != "enemy"):
			continue  # the Slug rolls over Jackals, never its own crew
		if u.bumped != null and u.bumped.has(o.id):
			continue
		if u.jumping and o.team == u.team:
			continue
		if absf(o.x - u.x) < (o.w + u.w) / 2.0 and u.y > o.y - o.h and u.y - u.h < o.y:
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
			float_text(o, "SMASH" if u.rushing else "BONK", Color("ffd23a"), true)
			Sfx.play("bonk")
			shake += 3
			if not o.heavy and not o.is_prop() and not o.immovable:
				var dir := signf(u.vx) if u.vx != 0 else 1.0
				o.vx = (dir * 8 if u.rushing else u.vx * 0.9) * kb(o)
				o.vy = -5 if u.rushing else minf(o.vy, -3)
				o.air = true
				o.walk = null
				o.bumped = {u.id: true}
				o.last_hit_by = cause
			damage(o, dmg, cause, {})
			if not u.rushing and cause != null and u.team == "enemy" and o.team == "enemy":
				add_status(u, "stun", 1, cause)
				add_status(o, "stun", 1, cause)
				tag("pileup", o.x, o.y - o.h, false)
			if not u.rushing:
				collision_dmg(u, sp * (0.3 if o.team == u.team else 0.8), "BONK")
				if not ks(cause, "gauntlet"):
					u.vx *= 0.35

func physics(u: Unit) -> void:
	if u.walk != null or (u.kind == "pow" and u.freed):
		return
	if u.weight == "hover" and not u.dead:
		hover_physics(u)
		return
	if not u.air:
		if not T.solid(u.x, u.y):
			u.air = true
			u.vy = maxf(u.vy, 0)
		else:
			return
	u.vy = minf(u.vy + grav, 2.4 if u.para else 10.0)
	if u.vault != null and u.y <= u.vault.y:
		u.vx = u.vault.vx  # clear the wall top before moving over it
	if u.para:
		u.vx = sin(t / 30.0 + u.id) * 0.4
	if (not u.dead or u.is_body()) and not u.is_prop():
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
			u.x = clampf(u.x, cam_x + 8, cam_x + W - 8)
		else:
			u.x = clampf(u.x, 4, world_w - 4)
		var ny: float = u.y + u.vy / n
		if u.vy > 0 and T.solid(u.x, ny):
			var ly: float = floorf(ny / CELL) * CELL
			while T.solid(u.x, ly - 1) and ly > 0:
				ly -= CELL
			u.y = ly
			var imp: float = u.vy
			u.air = false
			u.vx = 0
			u.vy = 0
			if u.crash:
				u.crash = false
				collision_dmg(u, 5, "CRASH")
			if u.para:
				u.para = false
			elif imp > 6.5 and not u.rushing and not u.jumping and not u.leaping:
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
		splash(u.x)
		u.sunk = true
		if not u.dead:
			float_at(u.x, WATER_Y - 30, (u.def.name + " DROWNED") if u.team == "squad" else "SPLASH!", Color("9fe3f0"), true)
			kill(u, u.last_hit_by if u.last_hit_by != null and u.last_hit_by is Unit and u.last_hit_by.team == "squad" else null)

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
		if mine_under(u, pts[i][0], pts[i][1], 4) != null:
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
		if c.topple != null:
			var tp: Dictionary = c.topple
			holder.position = Vector2(tp.px, tp.py)
			holder.rotation = tp.dir * minf(tp.rot, PI / 2)
			spr.position = Vector2(c.x0 * CELL - tp.px, c.y0 * CELL + c.oy - tp.py)
		else:
			holder.position = Vector2.ZERO
			holder.rotation = 0
			var jit := (randf() - .5) * 2 if c.shake < 6 else 0.0
			spr.position = Vector2(c.x0 * CELL + jit, c.y0 * CELL + c.oy)

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

func cancel_card() -> void:
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
	var sq := squad_alive()
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
	sq.sort_custom(func(a, b2): return a.x > b2.x)
	for u in sq:
		if u.dead or u.move_left <= 1:
			continue
		var sim := stop_before_mines(u, sim_walk(u, u.x + u.move_left, u.move_left))
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
		if ev.keycode == KEY_ESCAPE:
			cancel_card()
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
		elif ev.keycode == KEY_J:
			toggle_jet()
		elif ev.keycode == KEY_BRACKETRIGHT or ev.keycode == KEY_EQUAL:
			dial_fuse(1)
		elif ev.keycode == KEY_BRACKETLEFT or ev.keycode == KEY_MINUS:
			dial_fuse(-1)

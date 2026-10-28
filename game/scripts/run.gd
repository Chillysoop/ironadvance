extends Node
## Campaign state that survives between missions: the squad, their decks and
## levels, scrip (shop money), gear and which mission is next.

var soldiers: Array = []   # Array of Dictionary, one per squad member
var scrip := 0
var mission := 0
var gear: Array = []       # gear ids
var total_score := 0
var history: Array = []    # per-mission result dictionaries
var seed_val := 0
var uid := 1
var luck := 0              # shifts every rarity roll upward
var pity_rare := 0         # rolls since the last Rare or better
var pity_epic := 0         # rolls since the last Epic or better
var stash: Array = []      # unequipped items, shared by the squad
var belt: Array = []       # consumables usable mid-mission without a card
var gear_tier := {}        # squad gear (commander relic) id -> rarity tier
var trophies: Array = []   # Iron Boar parts brought home this run
var discount := 0.0        # next shop's price cut (Quartermaster POW)
var reroll_tokens := 0     # free affix rerolls at the gunsmith
var gunsmith_uses := 0     # each paid reroll costs more
var lvl_rerolls := 2       # level-up rerolls (P4); POWs and medals add more
var banishes := 2          # level-up banishes (P4)
var banished := {}         # soldier key -> option ids that never show up again
var cmd: Array = []        # commander perks (P5)
var extra_picks := 0       # Double Down: the next level-up takes two options
var intel := ""            # this mission's briefing condition (W2)
var side := ""             # "outpost" while an Elite Outpost side fight is running (W1)
var threat := 0            # threat level chosen for this run (W5)
var qm_cache := {}         # the Quartermaster's shelf for this HQ visit
var temp_luck := 0         # Luck that only lasts for the current mission
var level := {}            # the generated mission for the level being played (biome + tier)
var dial: Array = []       # the two biomes on the gate dial right now
var dial_breach := {}      # biome id -> true when the dial shows it as a BREACH (Vharr and Jackals at war)
var burned: Array = []     # biomes skipped or already played this run; they never come back
var dial_levels := {}      # biome id -> the level it would build, rolled with the dial (Gate Control 3 shows it)
var dial_rerolled := false # Gate Control 2: one reroll per HQ visit
var sway_mul := 1.0        # the current biome's sway rule, read by Data.card during a battle
var meta := {"feats": {}, "unlocked": [], "threat_max": 0, "wins": 0, "memorial": [], "salvage": 0, "bio": 0, "hq": {}, "implants": {}}   # kept across runs (W4, W5); memorial = the fallen; salvage (HQ) and bio (the Doc) are detour pay
const META_PATH := "user://meta.json"
# Campaign mode (B1): the campaign keeps its own HQ, Salvage, Bio-parts, implants and Memorial.
# While a campaign is loaded those keys in meta hold the campaign's values and run_base holds the
# standard run's, so every screen that reads meta works in both modes. Feats and Armory unlocks
# stay shared (L2).
const CAMP_KEYS := ["salvage", "bio", "hq", "implants", "memorial"]
var camp := {}             # campaign state; empty during a standard run
var run_base := {}         # the standard run's CAMP_KEYS while a campaign is loaded

func _ready() -> void:
	load_meta()

func load_meta() -> void:
	if not FileAccess.file_exists(META_PATH):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	if j is Dictionary:
		for k in j:
			meta[k] = j[k]

func snapshot() -> Dictionary:
	## Every bit of run state, deep-copied, for the practice range to put back afterwards (D5).
	var snap := {}
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v = get(p.name)
			snap[p.name] = v.duplicate(true) if v is Dictionary or v is Array else v
	return snap

func restore(snap: Dictionary) -> void:
	for k in snap:
		set(k, snap[k])
	save_meta()  # anything the range wrote to disk is undone too

func save_meta() -> void:
	var m := meta
	if campaign():
		m = meta.duplicate()
		for k in CAMP_KEYS:
			m[k] = run_base.get(k, m[k])
		save_campaign()
	var f := FileAccess.open(META_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(m))

func feat(id: String, n := 1) -> String:
	## Counts toward an Armory unlock feat. Returns the unlocked item's name the moment it unlocks.
	for fd in Data.FEATS:
		if fd.id != id:
			continue
		var c: int = int(meta.feats.get(id, 0)) + n
		meta.feats[id] = c
		var out := ""
		if c >= fd.n and not meta.unlocked.has(fd.item):
			meta.unlocked.append(fd.item)
			out = Data.ITEMS[fd.item].name
		save_meta()
		return out
	return ""

func unlocked(id: String) -> bool:
	return not Data.ITEMS[id].get("locked", false) or meta.unlocked.has(id)

func threat_on(n: int) -> bool:
	## Threat levels stack: level 3 includes the modifiers of levels 1 and 2.
	return threat >= n

func roll_intel() -> void:
	var pool: Array = []
	for k in Data.INTEL:
		for i in Data.INTEL[k].w:
			pool.append(k)
	intel = pool[randi() % pool.size()] if mission > 0 else "clear"
	if camp_perk("airfield"):
		intel = "surplus"

# ---------------------------------------------------------------- biomes and the gate dial
func current_mission() -> Dictionary:
	## The mission being played: the generated level, or the fixed list when none was generated.
	return level if not level.is_empty() else Data.MISSIONS[mini(mission, Data.MISSIONS.size() - 1)]

func roll_dial() -> Array:
	## Two biomes from this level's pool, never one already played or burned.
	var pool: Array = Data.LEVELS[mini(mission, Data.LEVELS.size() - 1)].pool.filter(func(b): return not burned.has(b))
	pool.shuffle()
	dial = pool.slice(0, 3 if hq("gate") >= 1 else 2)
	dial_breach = {}
	dial_levels = {}
	for b in dial:
		dial_breach[b] = mission >= 1 and randf() < 0.5
		dial_levels[b] = make_level(b, mission, dial_breach[b])
	return dial

func reroll_dial() -> void:
	## Gate Control 2: spin the dial once more. The first draw is not burned.
	dial_rerolled = true
	roll_dial()

func pick_biome(id: String) -> void:
	## Dial in a biome. Both dial options are burned: the one you skip and the one you play.
	for b in dial:
		if not burned.has(b):
			burned.append(b)
	level = dial_levels[id] if dial_levels.has(id) else make_level(id, mission, dial_breach.get(id, false))
	dial = []
	dial_levels = {}
	dial_rerolled = false

func make_level(id: String, tier: int, breach := false) -> Dictionary:
	## One continuous level: a start, a stretch, a camp, the detour yard, a stretch, a camp, the boss.
	var bm: Dictionary = Data.BIOMES[id]
	var lv: Dictionary = Data.LEVELS[mini(tier, Data.LEVELS.size() - 1)]
	var pool: Array = bm.segments.duplicate()
	pool.shuffle()
	while pool.size() < 2:
		pool.append(bm.segments[randi() % bm.segments.size()])
	var detours: Array = Data.DETOURS.keys()
	detours.shuffle()
	var nd := 4 if hq("mess") >= 3 else 3
	# from level 2 on, one stretch after the mid camp holds a Vharr encounter (E1 Swarm or E2 Nest)
	var enc: String = "" if tier < 1 else ["swarm", "nest"][randi() % 2]
	if tier >= 1 and (id == "desert" or id == "mountain"):
		enc = "queen"  # Q2: the Burrow Queen owns the sand and the scree
	# Q1: from level 2 the Hive Ship hangs over the delta and the harbor instead of a BOAR
	var boss := "hiveship" if tier >= 1 and (id == "delta" or id == "harbor") else "boar"
	return {"name": bm.name, "theme": bm.theme, "biome": id, "look": bm.look, "rules": bm.rules, "detours": detours.slice(0, nd), "breach": breach, "encounter": enc, "boss": boss,
		"segments": ["start", pool[0], "camp", "yard", pool[1], "camp", bm.get("arena", "arena")],
		"boss_hp": lv.boss_hp, "plate": lv.plate, "hp_mul": lv.hp_mul, "brief": bm.text}

func start_finale() -> void:
	level = Data.FINALE.duplicate(true)

func is_final_mission() -> bool:
	return current_mission().get("finale", false) or (level.is_empty() and mission >= Data.MISSIONS.size() - 1)

func card_style(key: String) -> String:
	## How a card fights, for the biome fit readout: long, close, arc, or "" for support cards.
	var c: Dictionary = Data.CARDS[key]
	if c.has("radius") and c.has("dmg"):
		return "arc"
	if c.type == "MELEE" or c.has("pellets"):
		return "close"
	if c.type == "LINE" and c.has("dmg"):
		return "close"
	if c.type == "AIM":
		return "long"
	return ""

func styles(s: Dictionary) -> Dictionary:
	## Share of a soldier's deck in each fighting style.
	var out := {"long": 0.0, "close": 0.0, "arc": 0.0}
	if s.deck.is_empty():
		return out
	for inst in s.deck:
		var st := card_style(inst if inst is String else inst.key)
		if st != "":
			out[st] += 1.0 / s.deck.size()
	return out

func fit(s: Dictionary, id: String) -> String:
	## "great", "ok" or "rough": how well this soldier's deck suits a biome.
	var bm: Dictionary = Data.BIOMES[id]
	var sh := styles(s)
	var sc: float = sh[bm.favor] - sh[bm.rough]
	return "great" if sc >= 0.3 else ("rough" if sc <= -0.25 else "ok")

func evolutions(s: Dictionary) -> Array:
	## M4: an Epic or better card plus the matching kit evolves into a Metal Slug weapon.
	var out: Array = []
	var kits: Array = []
	for sl in ["kit1", "kit2"]:
		if s.equip[sl] != null:
			kits.append(s.equip[sl].id)
	for rule in Data.EVOLUTIONS:
		if not kits.has(rule.kit):
			continue
		for c in s.deck:
			if c.key == rule.card and Data.tier_of(c) >= 3 and not c.has("src"):
				out.append({"card": c, "rule": rule})
				break
	return out

func evolve(c: Dictionary, rule: Dictionary) -> void:
	c.key = rule.into
	c["from"] = "evolved"
	c["got"] = mission + 1
	c.erase("mods")
	c.erase("nick")

func new_run() -> void:
	soldiers.clear()
	gear.clear()
	history.clear()
	scrip = 60 + (40 if hq("mess") >= 2 else 0)
	mission = 0
	luck = 1 if hq("armory") >= 1 else 0
	pity_rare = 0
	pity_epic = 0
	stash.clear()
	belt.clear()
	gear_tier.clear()
	trophies.clear()
	discount = 0.0
	reroll_tokens = 0
	gunsmith_uses = 0
	lvl_rerolls = 2
	banishes = 2
	banished = {}
	cmd = []
	extra_picks = 0
	intel = ""
	side = ""
	temp_luck = 0
	qm_cache = {}
	level = {}
	dial = []
	dial_levels = {}
	dial_rerolled = false
	burned = []
	sway_mul = 1.0
	total_score = 0
	uid = 1
	seed_val = randi()
	for d in Data.SQUAD_DEFS:
		soldiers.append(make_soldier(d))

func make_soldier(d: Dictionary) -> Dictionary:
	var deck: Array = []
	for k in d.deck:
		deck.append(new_card(k, -1, "start"))
	return {
		"key": d.key, "def": d, "hp": d.hp, "max_hp": d.hp, "alive": true,
		"lvl": 1, "xp": 0, "deck": deck, "perks": [], "tags": Data.DOG_TAGS, "trait": "",
		"bonus": {"move": 0, "dodge": 0, "hand": 0, "energy1": 0},
		"equip": {"weapon": null, "armor": null, "kit1": null, "kit2": null},
	}

# ---------------------------------------------------------------- dog tags, the fallen and recruits
func memorialize(s: Dictionary) -> void:
	## A soldier went down with no dog tags left. Their gear goes to the stash and their tag to the wall.
	for slot in s.equip.keys():
		unequip(s, slot)
	meta.memorial.append({"name": s.def.name, "key": s.key, "cls": s.def.cls, "lvl": s.lvl,
		"perks": s.perks.duplicate(), "mission": mission + 1})
	save_meta()

func legacy_perk(key: String) -> Dictionary:
	## Recruits of a class with a tag on the Memorial can start with the most recent fallen's first perk.
	for i in range(meta.memorial.size() - 1, -1, -1):
		var m: Dictionary = meta.memorial[i]
		if m.key == key and m.perks.size():
			return {"id": m.perks[0], "from": m.name}
	return {}

# ---------------------------------------------------------------- HQ upgrades
func hq(id: String) -> int:
	## Rank 0-3 of an HQ building. In the campaign some held sectors stand in for a rank (M3).
	var r := int(meta.get("hq", {}).get(id, 0))
	if campaign():
		match id:
			"motor": r = maxi(r, 1 if camp_perk("fuel") else 0)
			"mess": r = maxi(r, 1 if camp_perk("aid") else 0)
			"armory": r = maxi(r, 2 if camp_perk("supply") else 0)
	return r

func hq_buildings() -> Array:
	## The campaign has no gate dial, so no Gate Control.
	return Data.HQ_BUILDINGS.filter(func(B): return not (campaign() and B.id == "gate"))

func hq_upgrade(id: String) -> bool:
	## Buy the next rank of a building with Salvage.
	var r := hq(id)
	if r >= Data.HQ_COST.size() or int(meta.get("salvage", 0)) < Data.HQ_COST[r]:
		return false
	meta.salvage = int(meta.salvage) - Data.HQ_COST[r]
	if not meta.has("hq"):
		meta.hq = {}
	meta.hq[id] = r + 1
	save_meta()
	return true

# ---------------------------------------------------------------- the Doc's surgeries
func implants(cls: String) -> Array:
	## Surgeries installed on a class (a SQUAD_DEFS key).
	return meta.get("implants", {}).get(cls, [])

func implanted(s, id: String) -> bool:
	return s is Dictionary and s.has("key") and implants(s.key).has(id)

func surgery_block(id: String, cls: String) -> String:
	## Why this surgery can't go on this class right now, or "" when it can.
	var S: Dictionary = Data.SURGERIES[id]
	if hq("doc") < 1:
		return "BUILD THE DOC'S LAB"
	if S.cls != "" and S.cls != cls:
		return "WRONG CLASS"
	if implants(cls).has(id):
		return "INSTALLED"
	if int(meta.get("bio", 0)) < Data.SURGERY_BIO or int(meta.get("salvage", 0)) < Data.SURGERY_SALVAGE:
		return "NEED %d BIO + %d SALVAGE" % [Data.SURGERY_BIO, Data.SURGERY_SALVAGE]
	return ""

func operate(id: String, cls: String) -> bool:
	## Install a surgery on a class. Past the slot cap the oldest implant comes out.
	if surgery_block(id, cls) != "":
		return false
	meta.bio = int(meta.bio) - Data.SURGERY_BIO
	meta.salvage = int(meta.salvage) - Data.SURGERY_SALVAGE
	if not meta.has("implants"):
		meta.implants = {}
	var have: Array = implants(cls).duplicate()
	while have.size() >= hq("doc"):
		have.pop_front()
	have.append(id)
	meta.implants[cls] = have
	for s in soldiers:
		if s.key == cls and s.alive:
			s.hp = mini(s.hp, eff_max_hp(s))
	save_meta()
	return true

func recruit_offers(n := -1) -> Array:
	## Recruits for the first fallen slot: the fallen soldier's class first, then classes nobody
	## alive has, so the squad never holds two of one class.
	if n < 0:
		n = 3 if hq("barracks") >= 1 else 2
	var used: Array = soldiers.filter(func(s): return s.alive).map(func(s): return s.def.name)
	var names: Array = Data.CALLSIGNS.filter(func(c): return not used.has(c))
	names.shuffle()
	var traits: Array = Data.RECRUIT_TRAITS.duplicate()
	traits.shuffle()
	var keys := recruit_classes()
	var out: Array = []
	for i in n:
		var key: String = keys[i % keys.size()]
		out.append({"key": key, "name": names[i], "trait": traits[i % traits.size()], "legacy": legacy_perk(key), "look": Art.random_look(), "drill_card": drilled_card(key)})
	return out

func recruit_classes() -> Array:
	var held: Array = soldiers.filter(func(s): return s.alive).map(func(s): return s.key)
	var slots := fallen_slots()
	var first: String = soldiers[slots[0]].key if slots.size() else ""
	var others: Array = Data.SQUAD_DEFS.map(func(d): return d.key).filter(func(k): return k != first and not held.has(k))
	others.shuffle()
	var out: Array = ([first] if first != "" and not held.has(first) else []) + others
	return out if out.size() else Data.SQUAD_DEFS.map(func(d): return d.key)

func drilled_card(key: String) -> String:
	## The starting card a Drilled recruit of this class gets one rarity up: the strongest
	## (highest cost) upgradable card in the starting deck.
	var d: Dictionary = Data.SQUAD_DEFS.filter(func(x): return x.key == key)[0]
	var best := ""
	for k in d.deck:
		if upgradable(new_card(k)) and (best == "" or int(Data.CARDS[k].cost) > int(Data.CARDS[best].cost)):
			best = k
	return best

func hire(slot: int, o: Dictionary) -> Dictionary:
	## Puts a recruit into a fallen soldier's slot.
	var d: Dictionary = Data.SQUAD_DEFS.filter(func(x): return x.key == o.key)[0].duplicate()
	d.name = o.name
	var s := make_soldier(d)
	s.trait = o.trait.id
	s["look"] = o.get("look", Art.random_look())  # U3: recruits show up in their own kit
	match o.trait.id:
		"quick": s.bonus.move += 25
		"tough":
			s.max_hp += 5
			s.hp += 5
		"slippery": s.bonus.dodge += 6
		"drilled":
			var dk: String = o.get("drill_card", drilled_card(o.key))
			var cands: Array = s.deck.filter(func(c): return c.key == dk and upgradable(c))
			if cands.size():
				raise_tier(cands[0])
	if not o.legacy.is_empty():
		s.perks.append(o.legacy.id)
	if hq("barracks") >= 2:
		# Barracks 2: a recruit shows up at level 2 with one training pick waiting at the Barracks
		s.xp = xp_for_next(s)
		s.lvl = 2
		s["train"] = true
	soldiers[slot] = s
	return s

func fallen_slots() -> Array:
	var out: Array = []
	for i in soldiers.size():
		if not soldiers[i].alive:
			out.append(i)
	return out

func new_card(key: String, tier := -1, from := "") -> Dictionary:
	## from: where the card came from (start, shop, level, drop, fused, evolved), shown in the Dossier.
	uid += 1
	var c := {"id": uid, "key": key, "tier": Data.base_tier(key) if tier < 0 else maxi(tier, Data.base_tier(key))}
	if from != "":
		c["from"] = from
		c["got"] = mission + 1
	return c

func luck_total() -> int:
	var n := luck + (1 if camp_perk("lookout") else 0) + (2 if has_gear("charm") else 0) + (1 if has_gear("dogtags") else 0) + (2 if has_cmd("rabbit") else 0) + temp_luck
	for s in soldiers:
		if s.alive:
			n += int(gear_bonus(s).get("luck", 0))
	return n

func tier_weights() -> Array:
	## Rarity odds for this point in the run. Later missions and Luck move weight off Common.
	var w: Array = Data.RARITY.slice(0, Data.TIER_MAX + 1).map(func(r): return r.w)
	var step := mission * 6.0
	if campaign():
		step = int(camp.act) * 10.0 + mini(int(camp.act_ops), 5) * 2.0  # rarity climbs by act, not by op count
	var shift := minf(40.0, step + luck_total() * 3.0)
	w[0] -= shift
	var split := [0.0, 0.5, 0.3, 0.15, 0.05]
	for i in range(1, w.size()):
		w[i] += shift * split[i]
	return w

func roll_tier(min_tier := 0) -> int:
	## One rarity roll with a pity timer: never more than 7 rolls without a Rare, or 30 without an Epic.
	var w := tier_weights()
	var total := 0.0
	for x in w:
		total += x
	var r := randf() * total
	var t := 0
	for i in w.size():
		r -= w[i]
		if r <= 0:
			t = i
			break
	if pity_rare >= 7:
		t = maxi(t, 2)
	if pity_epic >= 30:
		t = maxi(t, 3)
	t = maxi(t, min_tier)
	pity_rare = 0 if t >= 2 else pity_rare + 1
	pity_epic = 0 if t >= 3 else pity_epic + 1
	return t

func roll_card_tier(key: String) -> int:
	return maxi(Data.base_tier(key), roll_tier())

func upgradable(c: Dictionary) -> bool:
	return Data.tier_of(c) < Data.TIER_MAX

func soldier(key: String) -> Dictionary:
	for s in soldiers:
		if s.key == key:
			return s
	return {}

func add_gear(id: String, tier := 0) -> void:
	if not gear.has(id):
		gear.append(id)
	gear_tier[id] = maxi(gear_tier.get(id, 0), tier)

func has_gear(id: String) -> bool:
	return gear.has(id)

func has_perk(s: Dictionary, id: String) -> bool:
	return s.perks.has(id)

func xp_for_next(s: Dictionary) -> int:
	var l: int = s.lvl
	if l < Data.XP_LEVELS.size():
		return Data.XP_LEVELS[l]
	return Data.XP_LEVELS[-1] + (l - Data.XP_LEVELS.size() + 1) * 60

func xp_floor(s: Dictionary) -> int:
	var l: int = s.lvl - 1
	if l < Data.XP_LEVELS.size():
		return Data.XP_LEVELS[l]
	return Data.XP_LEVELS[-1] + (l - Data.XP_LEVELS.size() + 1) * 60

func add_xp(s: Dictionary, n: int) -> int:
	## Adds XP and returns how many levels were gained.
	if n <= 0 or not s.alive:
		return 0
	if has_gear("dogtags"):
		n = int(ceil(n * (1.3 + 0.1 * relic_tier("dogtags"))))
	if has_cmd("veterans"):
		n = int(ceil(n * 1.25))
	s.xp += n
	var gained := 0
	while s.xp >= xp_for_next(s):
		s.lvl += 1
		gained += 1
	return gained

# Stat boost size by rarity tier (common .. legendary).
const STAT_TIERS := {
	"hp": [3, 5, 7, 10, 14],
	"move": [15, 25, 35, 50, 70],
	"dodge": [3, 5, 7, 10, 14],
	"upgrade": [1, 1, 2, 2, 3],
}

func stat_text(id: String, t: int) -> String:
	match id:
		"hp":
			return "+%d max HP and heal %d." % [STAT_TIERS.hp[t], STAT_TIERS.hp[t]]
		"move":
			return "+%d movement every turn." % STAT_TIERS.move[t]
		"dodge":
			return "+%d dodge. Enemy shots drift wider." % STAT_TIERS.dodge[t]
		"upgrade":
			var n: int = STAT_TIERS.upgrade[t]
			return "Raise %s in this deck one rarity tier." % ("a random card" if n == 1 else "%d random cards" % n)
	return Data.STAT_BOOSTS.filter(func(x): return x.id == id)[0].text

func level_options(s: Dictionary) -> Array:
	## Three choices for a level-up: a class card, a stat boost and an ability unlock.
	## Each option rolls its own rarity.
	var out: Array = []
	var d: Dictionary = s.def
	var ban: Array = banished.get(d.key, [])
	var pool: Array = d.pool.filter(func(k): return not ban.has(k))
	if pool.is_empty():
		pool = d.pool.duplicate()
	pool.shuffle()
	var ckey: String = pool[0]
	out.append({"kind": "card", "key": ckey, "tier": roll_card_tier(ckey)})
	var stats: Array = Data.STAT_BOOSTS.duplicate()
	stats.shuffle()
	for st in stats:
		if ban.has(st.id):
			continue
		if st.id == "hand" and s.bonus.hand >= 2:
			continue
		if st.id == "energy" and s.bonus.energy1 >= 1:
			continue
		if st.id == "upgrade" and not s.deck.any(upgradable):
			continue
		var t := roll_tier()
		if st.id == "hand":
			t = 3
		elif st.id == "energy":
			t = 2
		out.append({"kind": "stat", "id": st.id, "name": st.name, "text": stat_text(st.id, t), "tier": t})
		break
	var perks := perk_offers(s)
	if perks.size():
		var p: Dictionary = perks[randi() % perks.size()]
		out.append(p)
	else:
		for st in stats:
			if out.any(func(o): return o.get("id", "") == st.id):
				continue
			if st.id in ["hand", "energy", "upgrade"]:
				continue
			var t := roll_tier()
			out.append({"kind": "stat", "id": st.id, "name": st.name, "text": stat_text(st.id, t), "tier": t})
			break
	return out

func perk_offers(s: Dictionary) -> Array:
	## P1: the next untaken perk in each of the soldier's four branches.
	var out: Array = []
	var ban: Array = banished.get(s.key, [])
	for b in Data.BRANCHES[s.key]:
		for i in b.perks.size():
			var p: Dictionary = b.perks[i]
			if s.perks.has(p.id):
				continue
			if not ban.has(p.id):
				var txt: String = p.text
				if i == 2:
					txt += " Overdrive becomes %s." % Data.CARDS[b.od].name
				out.append({"kind": "perk", "id": p.id, "name": p.name, "text": txt, "tier": 2 + i, "branch": b.name, "ptier": i, "label": "%s %s" % [b.name.to_upper(), Data.PERK_TIER[i]]})
			break
	return out

func od_key(s: Dictionary) -> String:
	## P2: a capstone perk swaps the Overdrive for its archetype's.
	for b in Data.BRANCHES[s.key]:
		if s.perks.has(b.perks[2].id):
			return b.od
	return Data.OD[s.key]

func archetypes(s: Dictionary) -> Array:
	## Branch names with how deep this soldier is in each, for the squad panels.
	var out: Array = []
	for b in Data.BRANCHES[s.key]:
		var n := 0
		for p in b.perks:
			if s.perks.has(p.id):
				n += 1
		if n > 0:
			out.append([b.name, n])
	return out

func has_cmd(id: String) -> bool:
	return cmd.has(id)

func belt_max() -> int:
	return Data.BELT_MAX + (1 if has_cmd("supply") else 0)

func command_offers() -> Array:
	var pool: Array = Data.COMMANDS.filter(func(c): return not cmd.has(c.id))
	pool.shuffle()
	return pool.slice(0, 3)

func raise_tier(c: Dictionary) -> void:
	c.tier = mini(Data.TIER_MAX, Data.tier_of(c) + 1)
	c.erase("up")

func apply_option(s: Dictionary, o: Dictionary) -> String:
	## Applies a level-up choice to the persistent soldier. Returns a log line.
	var t: int = o.get("tier", 0)
	match o.kind:
		"card":
			var c := new_card(o.key, t, "level")
			s.deck.append(c)
			return "%s added %s %s to the deck." % [s.def.name, Data.tier_name(Data.tier_of(c)).capitalize(), Data.card(c).name]
		"perk":
			s.perks.append(o.id)
			return "%s unlocked %s." % [s.def.name, o.name]
		"stat":
			match o.id:
				"hp":
					s.max_hp += STAT_TIERS.hp[t]
					s.hp += STAT_TIERS.hp[t]
				"move":
					s.bonus.move += STAT_TIERS.move[t]
				"dodge":
					s.bonus.dodge += STAT_TIERS.dodge[t]
				"hand":
					s.bonus.hand += 1
				"energy":
					s.bonus.energy1 += 1
				"upgrade":
					var names: Array = []
					for i in STAT_TIERS.upgrade[t]:
						var cands: Array = s.deck.filter(upgradable)
						if cands.is_empty():
							break
						var c: Dictionary = cands[randi() % cands.size()]
						raise_tier(c)
						names.append("%s (%s)" % [Data.card(c).name, Data.tier_name(Data.tier_of(c)).capitalize()])
					return "%s upgraded %s." % [s.def.name, ", ".join(names)]
			return "%s: %s." % [s.def.name, o.name]
	return ""

func laser_steps(s: Dictionary) -> int:
	return int(gear_bonus(s).get("laser_step", 0)) + (1 if relic_tier("laser") >= Data.TIER_MAX else 0)

func laser_pct(s: Dictionary) -> float:
	return float(gear_bonus(s).get("laser_pct", 0.0))

# ---------------------------------------------------------------- gear and inventory
func relic_tier(id: String) -> int:
	return gear_tier.get(id, 0) if has_gear(id) else -1

func new_item(id: String, tier := -1) -> Dictionary:
	## A fresh item instance with rolled rarity and affixes.
	uid += 1
	var t := roll_tier() if tier < 0 else tier
	if Data.ITEMS[id].has("keystone"):
		t = Data.TIER_MAX
	var it := {"uid": uid, "id": id, "tier": t, "affixes": []}
	if Data.ITEMS[id].slot != "belt":
		roll_affixes(it)
	else:
		it.tier = 0
	return it

func roll_affixes(it: Dictionary) -> void:
	var pool: Array = Data.AFFIXES.keys()
	pool.shuffle()
	it.affixes = pool.slice(0, Data.AFFIX_COUNT[it.tier])

func random_item_id(slots := ["weapon", "armor", "kit"]) -> String:
	## Mid and late game items (G7) only drop once the run reaches them, and then they make up
	## a good share of every roll so the second half of a run feels like new kit.
	var ids: Array = Data.ITEMS.keys().filter(func(k): return Data.ITEMS[k].slot in slots and not Data.ITEMS[k].has("keystone") and unlocked(k) and Data.ITEMS[k].get("from", 0) <= mission)
	var fresh: Array = ids.filter(func(k): return Data.ITEMS[k].get("from", 0) > 0)
	if not fresh.is_empty() and randf() < 0.4:
		return fresh[randi() % fresh.size()]
	return ids[randi() % ids.size()]

func roll_item(min_tier := 0, slots := ["weapon", "armor", "kit"]) -> Dictionary:
	var t := roll_tier(min_tier)
	if t >= Data.TIER_MAX and slots.size() > 1 and randf() < 0.5:
		return new_item(Data.KEYSTONE_IDS[randi() % Data.KEYSTONE_IDS.size()], t)
	return new_item(random_item_id(slots), t)

func medals(st: Dictionary) -> Array:
	## Debrief medals (L9). Each one earns a supply crate, up to three; a win always earns one.
	var segs: int = current_mission().segments.filter(func(sg): return sg != "camp").size()
	var out: Array = []
	if st.get("kia", 0) == 0:
		out.append(["FLAWLESS", "Nobody went down"])
	if st.get("rounds", 99) <= segs * 2 + 2:
		out.append(["BLITZ", "Done in %d rounds or fewer" % (segs * 2 + 2)])
	if st.get("pows_total", 0) > 0 and st.get("pows", 0) >= st.pows_total:
		out.append(["LIBERATOR", "Every POW freed"])
	if st.get("max_alert", 10) < 6:
		out.append(["LOW PROFILE", "Alert never reached 6"])
	return out

func item_opt(it: Dictionary, label := "") -> Dictionary:
	## A pick-modal / CardView option for an item instance.
	return {"kind": "item", "item": it, "tier": it.tier, "label": label}

func item_price(it: Dictionary) -> int:
	if Data.ITEMS[it.id].slot == "belt":
		return 30
	return [60, 90, 130, 190, 280][it.tier]

func sell_value(it: Dictionary) -> int:
	return int(item_price(it) * 0.4)

func gear_bonus(s: Dictionary) -> Dictionary:
	## Every stat from a soldier's equipped items, their affixes and set bonuses.
	var out := {}
	if not s.has("equip"):
		return out
	var sets := {}
	for slot in s.equip:
		var it = s.equip[slot]
		if it == null:
			continue
		var st := Data.item_stats(it)
		for k in st:
			out[k] = out.get(k, 0) + st[k]
		if Data.ITEMS[it.id].has("keystone"):
			out["ks_" + it.id] = 1
		var set_id: String = Data.ITEMS[it.id].get("set", "")
		if set_id != "":
			sets[set_id] = sets.get(set_id, 0) + 1
	for set_id in sets:
		if sets[set_id] >= 2:
			for k in Data.SETS[set_id].bonus:
				out[k] = out.get(k, 0) + Data.SETS[set_id].bonus[k]
	if s.has("key"):
		for id in implants(s.key):
			var st: Dictionary = Data.SURGERIES[id].get("stats", {})
			for k in st:
				out[k] = out.get(k, 0) + st[k]
	return out

func eff_max_hp(s: Dictionary) -> int:
	return s.max_hp + int(gear_bonus(s).get("hp", 0)) + (6 if implanted(s, "spine") else 0)

func slot_for(s: Dictionary, it: Dictionary) -> String:
	## Where an item would go on this soldier: its slot, or the free kit slot (kit1 when both are full).
	var sl: String = Data.ITEMS[it.id].slot
	if sl == "kit":
		if s.equip.kit1 == null:
			return "kit1"
		if s.equip.kit2 == null:
			return "kit2"
		return "kit1"
	return sl

func equip(s: Dictionary, it: Dictionary, slot := "") -> Dictionary:
	## Puts an item on a soldier and returns whatever it replaced (or {}). Weapon cards
	## follow the weapon in and out of the deck.
	if slot == "":
		slot = slot_for(s, it)
	var old = s.equip[slot]
	if old != null:
		unequip(s, slot)
	stash.erase(it)
	s.equip[slot] = it
	var d: Dictionary = Data.ITEMS[it.id]
	for k in d.get("cards", []):
		var c := new_card(k, it.tier)
		c["src"] = it.uid
		s.deck.append(c)
	if s.hp > eff_max_hp(s):
		s.hp = eff_max_hp(s)
	return old if old != null else {}

func unequip(s: Dictionary, slot: String) -> void:
	var it = s.equip[slot]
	if it == null:
		return
	s.equip[slot] = null
	s.deck = s.deck.filter(func(c): return c.get("src", -1) != it.uid)
	stash.append(it)
	s.hp = mini(s.hp, eff_max_hp(s))

func add_loot(it: Dictionary) -> String:
	## Belt items go on the belt when there is room; everything else goes to the stash.
	if Data.ITEMS[it.id].slot == "belt" and belt.size() < belt_max():
		belt.append(it)
		return "belt"
	stash.append(it)
	return "stash"

func alive_count() -> int:
	return soldiers.filter(func(s): return s.alive).size()

# ---------------------------------------------------------------- merging (M1-M3, M5)
func all_items() -> Array:
	## Every gear item the squad owns: the stash plus what each soldier wears.
	var out: Array = stash.duplicate()
	for s in soldiers:
		for sl in s.equip:
			if s.equip[sl] != null:
				out.append(s.equip[sl])
	return out

func merge_group_of(it) -> Array:
	## Three items with the same name and rarity merge into one a tier higher (M1).
	if it == null or Data.ITEMS[it.id].slot == "belt" or it.tier >= Data.TIER_MAX:
		return []
	var g: Array = all_items().filter(func(o): return o.id == it.id and o.tier == it.tier)
	if g.size() < 3:
		return []
	# the selected item always takes part; prefer stash copies for the other two
	g.erase(it)
	g.sort_custom(func(a, b): return stash.has(a) and not stash.has(b))
	return [it, g[0], g[1]]

func any_merge() -> bool:
	return all_items().any(func(o): return merge_group_of(o).size() == 3)

func merge_keep_options(g: Array) -> Array:
	var out: Array = []
	for it in g:
		for a in it.affixes:
			if not out.has(a):
				out.append(a)
	return out

func merge_new_options(exclude: Array) -> Array:
	var pool: Array = Data.AFFIXES.keys().filter(func(a): return not exclude.has(a))
	pool.shuffle()
	return pool.slice(0, 2)

func merge_items(g: Array, chosen: Array) -> Dictionary:
	## M2: the player kept one affix from the three and picked one of two new ones;
	## any slots still open are rolled. A Legendary result gets a name and a unique line.
	var holder = null
	var slot := ""
	for s in soldiers:
		for sl in s.equip:
			if s.equip[sl] != null and g.has(s.equip[sl]):
				if holder == null:
					holder = s
					slot = sl
				unequip(s, sl)
	for it in g:
		stash.erase(it)
	uid += 1
	var t: int = g[0].tier + 1
	var out := {"uid": uid, "id": g[0].id, "tier": t, "affixes": []}
	var aff: Array = chosen.duplicate()
	var pool: Array = Data.AFFIXES.keys().filter(func(a): return not aff.has(a))
	pool.shuffle()
	while aff.size() < Data.AFFIX_COUNT[t] and pool.size():
		aff.append(pool.pop_back())
	out.affixes = aff.slice(0, Data.AFFIX_COUNT[t])
	if t >= Data.TIER_MAX:
		var names: Array = Data.LEGEND_NAMES[Data.slot_group(Data.ITEMS[g[0].id].slot)]
		out["named"] = names[randi() % names.size()]
	stash.append(out)
	if holder != null:
		equip(holder, out, slot)
	return out

func fusable(s: Dictionary) -> Array:
	## M3: three copies of one card at one rarity in a deck. Weapon cards and temps don't count.
	var groups := {}
	for c in s.deck:
		if c.has("src") or c.get("temp", false) or Data.tier_of(c) >= Data.TIER_MAX:
			continue
		var k := "%s:%d" % [c.key, Data.tier_of(c)]
		if not groups.has(k):
			groups[k] = []
		groups[k].append(c)
	return groups.values().filter(func(g): return g.size() >= 3).map(func(g): return g.slice(0, 3))

func fuse(s: Dictionary, g: Array) -> Dictionary:
	for c in g:
		s.deck.erase(c)
	var c := new_card(g[0].key, Data.tier_of(g[0]) + 1, "fused")
	var k: int = g.reduce(func(a, o): return a + int(o.get("kills", 0)), 0)
	if k > 0:
		c["kills"] = k  # the fused card keeps the copies' kill count
	for o in g:
		if o.get("mods", []).size():
			c["mods"] = o.mods.duplicate()
			break
	if Data.tier_of(c) >= Data.TIER_MAX:
		c["nick"] = Data.CARD_NICKS[randi() % Data.CARD_NICKS.size()]
	s.deck.append(c)
	return c

func fab_options() -> Array:
	## M5: the Fabricator copies one Common or Uncommon item.
	return all_items().filter(func(o): return Data.ITEMS[o.id].slot != "belt" and o.tier <= 1)

func fabricate(it: Dictionary) -> Dictionary:
	uid += 1
	var cp := {"uid": uid, "id": it.id, "tier": it.tier, "affixes": it.affixes.duplicate()}
	stash.append(cp)
	return cp

# ---------------------------------------------------------------- campaign mode
func campaign() -> bool:
	return not camp.is_empty()

func _process(delta: float) -> void:
	if campaign():
		camp.secs = float(camp.get("secs", 0.0)) + delta

func camp_path(slot: int) -> String:
	return "user://campaign_%d.save" % slot

func camp_head(slot: int) -> Dictionary:
	## What the slot picker shows for a save: act, ops fought, time played. {} when the slot is empty.
	if not FileAccess.file_exists(camp_path(slot)):
		return {}
	var f := FileAccess.open(camp_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var d = f.get_var()
	return d.get("head", {}) if d is Dictionary else {}

func _enter_base() -> void:
	## Put the standard run's HQ aside while a campaign is loaded.
	if run_base.is_empty():
		for k in CAMP_KEYS:
			var v = meta.get(k)
			run_base[k] = v.duplicate(true) if v is Dictionary or v is Array else v

func new_campaign(slot: int) -> void:
	## A fresh war: the starting four, a small war chest, an empty base.
	_enter_base()
	meta.salvage = 0
	meta.bio = 0
	meta.hq = {}
	meta.implants = {}
	meta.memorial = []
	camp = {"slot": slot, "act": 0, "held": [], "ops": 0, "act_ops": 0, "secs": 0.0, "done": false}
	new_run()  # campaign() is already true, so this reads the campaign's empty HQ
	threat = 0
	scrip = Data.CAMP_START_SCRIP
	save_campaign()

func load_campaign(slot: int) -> bool:
	if not FileAccess.file_exists(camp_path(slot)):
		return false
	var f := FileAccess.open(camp_path(slot), FileAccess.READ)
	var d = f.get_var() if f != null else null
	if not (d is Dictionary and d.has("data")):
		return false
	_enter_base()
	var data: Dictionary = d.data
	for k in data:
		if k in ["meta", "run_base", "base"]:
			continue
		set(k, data[k])
	for k in CAMP_KEYS:
		meta[k] = data.base.get(k, run_base[k])
	camp.slot = slot
	return true

func save_campaign() -> void:
	if not campaign():
		return
	var data := snapshot()
	data.erase("meta")
	data.erase("run_base")
	var base := {}
	for k in CAMP_KEYS:
		base[k] = meta.get(k)
	data["base"] = base
	var head := {"act": int(camp.act), "ops": int(camp.ops), "secs": float(camp.get("secs", 0.0)), "done": camp.get("done", false),
		"names": soldiers.filter(func(s): return s.alive).map(func(s): return s.def.name)}
	var f := FileAccess.open(camp_path(int(camp.slot)), FileAccess.WRITE)
	if f != null:
		f.store_var({"head": head, "data": data})

func delete_campaign(slot: int) -> void:
	if FileAccess.file_exists(camp_path(slot)):
		DirAccess.remove_absolute(camp_path(slot))

func leave_campaign() -> void:
	## Save and put the standard run's HQ back.
	if not campaign():
		return
	save_campaign()
	for k in CAMP_KEYS:
		meta[k] = run_base[k]
	run_base = {}
	camp = {}
	threat = 0
	new_run()

func act(a := -1) -> Dictionary:
	return Data.ACTS[clampi(int(camp.get("act", 0)) if a < 0 else a, 0, Data.ACTS.size() - 1)]

func sec_key(id: String, a := -1) -> String:
	return "%d:%s" % [int(camp.get("act", 0)) if a < 0 else a, id]

func sector(id: String, a := -1) -> Dictionary:
	for sc in act(a).sectors:
		if sc.id == id:
			return sc
	return {}

func sector_held(id: String) -> bool:
	return id == "lz" or camp.get("held", []).has(sec_key(id))

func held_count() -> int:
	## Sectors taken this act, not counting the stronghold.
	return act().sectors.filter(func(sc): return not sc.get("stronghold", false) and camp.held.has(sec_key(sc.id))).size()

func sector_open(sc: Dictionary) -> bool:
	## M1: open when it touches ground you hold. The stronghold waits for "need" sectors.
	if camp.held.has(sec_key(sc.id)):
		return false
	if sc.get("stronghold", false):
		return held_count() >= int(act().need)
	return sc.links.any(func(l): return sector_held(l))

func camp_perk(id: String) -> bool:
	## M3: a held sector's perk, only for the act it's in.
	return campaign() and act().sectors.any(func(sc): return sc.get("perk", "") == id and camp.held.has(sec_key(sc.id)))

func income() -> Dictionary:
	## M2: what every held sector in the war pays after each op.
	var out := {"scrip": 0, "salvage": 0, "bio": 0}
	if not campaign():
		return out
	for key in camp.held:
		var parts: PackedStringArray = key.split(":")
		var h: Dictionary = sector(parts[1], int(parts[0])).get("hold", {})
		for k in h:
			out[k] = out.get(k, 0) + int(h[k])
	return out

func make_op(sc: Dictionary, patrol := false) -> Dictionary:
	## One operation on the war map. A sector op is shorter than a run level: one camp, then the
	## sector's boss. A stronghold keeps the full length. A patrol replays a held sector (M5).
	var a := act()
	var lv := make_level(sc.biome, int(a.tier), randf() < float(a.breach))
	lv.hp_mul = a.hp_mul
	lv.boss_hp = a.boss_hp
	lv.plate = a.plate
	lv.name = sc.name
	var segs: Array = lv.segments
	if not sc.get("stronghold", false):
		lv.segments = ["start", segs[1], "camp", "yard", segs[4], segs[6]]
	else:
		lv.boss_hp = int(a.boss_hp * 1.2)
		lv.plate = int(a.plate * 1.2)
	if sc.get("queen", false):
		lv.encounter = "queen"
	lv["op"] = sc.id
	lv["patrol"] = patrol
	lv["stronghold"] = sc.get("stronghold", false) and not patrol
	lv["banner"] = "PATROL" if patrol else ("STRONGHOLD ASSAULT" if lv.stronghold else "OP %d START!" % (int(camp.ops) + 1))
	return lv

func start_op(sc: Dictionary, patrol := false) -> void:
	mission = int(camp.ops)   # the Quartermaster restocks after every op
	level = make_op(sc, patrol)
	history.clear()

func op_over(won: bool) -> Dictionary:
	## Book an op on the war map. Returns what changed for the result screen.
	camp.ops = int(camp.ops) + 1
	camp.act_ops = int(camp.act_ops) + 1
	var out := {}
	if not won or level.get("patrol", false):
		return out
	var sc := sector(level.op)
	if not camp.held.has(sec_key(sc.id)):
		camp.held.append(sec_key(sc.id))
		out["took"] = sc.name
		if sc.has("perk"):
			out["perk"] = sc.perk
	if sc.get("stronghold", false):
		out["act_done"] = act().name
		if int(camp.act) >= Data.ACTS.size() - 1:
			camp.done = true
		else:
			camp.act = int(camp.act) + 1
			camp.act_ops = 0
	return out

func after_op() -> Dictionary:
	## Back at HQ after an op: held sectors pay, everyone is patched up and gets their dog tags
	## back, and Command fills any empty slot with a rookie so you can always field a squad.
	var inc := income()
	scrip += inc.scrip
	meta.salvage = int(meta.get("salvage", 0)) + inc.salvage
	meta.bio = int(meta.get("bio", 0)) + inc.bio
	for s in soldiers:
		if s.alive:
			s.tags = Data.DOG_TAGS
			s.hp = eff_max_hp(s)
	var rookies: Array = []
	for i in fallen_slots():
		var o: Dictionary = recruit_offers(1)[0]
		rookies.append(hire(i, o).def.name)
	inc["rookies"] = rookies
	level = {}
	save_meta()
	return inc

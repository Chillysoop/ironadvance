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
var defectors: Array = []  # F3: callsigns of rescued Jackal defectors, offered first at the next hire
var spec_seen: Array = []  # X2: specialist classes held as POWs in this run so far
var level := {}            # the generated mission for the level being played (biome + tier)
var dial: Array = []       # the two biomes on the gate dial right now
var dial_breach := {}      # biome id -> true when the dial shows it as a BREACH (Vharr and Jackals at war)
var burned: Array = []     # biomes skipped or already played this run; they never come back
var dial_levels := {}      # biome id -> the level it would build, rolled with the dial (Gate Control 3 shows it)
var dial_rerolled := false # Gate Control 2: one reroll per HQ visit
var sway_mul := 1.0        # the current biome's sway rule, read by Data.card during a battle
var first_run := false     # P8: the player's first-ever quick run (level 1 skips bounties and the event)
var daily := ""            # D2: the date of today's Daily Op while one is running, else ""
var meta := {"feats": {}, "unlocked": [], "threat_max": 0, "wins": 0, "memorial": [], "salvage": 0, "bio": 0, "hq": {}, "implants": {}}   # kept across runs (W4, W5); memorial = the fallen; salvage (HQ) and bio (the Doc) are detour pay
const META_PATH := "user://meta.json"
# Campaign mode (B1): the campaign keeps its own HQ, Salvage, Bio-parts, implants and Memorial.
# While a campaign is loaded those keys in meta hold the campaign's values and run_base holds the
# standard run's, so every screen that reads meta works in both modes. Feats and Armory unlocks
# stay shared (L2).
const CAMP_KEYS := ["salvage", "bio", "hq", "implants", "memorial"]
var camp := {}             # campaign state; empty during a standard run
var roster: Array = []     # campaign: the whole company (C1); soldiers is the squad that deploys
var reserve: Array = []    # quick run: rescued soldiers waiting in the barracks while the squad is full
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
	if not roster.is_empty():
		# the squad is the same people as part of the roster: keep them linked through a copy
		snap.erase("soldiers")
		snap["_squad"] = soldiers.map(func(x): return roster.find(x))
	return snap

func restore(snap: Dictionary) -> void:
	set_state(snap)
	save_meta()  # anything the range wrote to disk is undone too

func set_state(snap: Dictionary) -> void:
	for k in snap:
		if not k.begins_with("_") and not k in ["meta", "run_base", "base"]:
			set(k, snap[k])
	if snap.has("_squad"):
		soldiers = snap._squad.filter(func(i): return i >= 0).map(func(i): return roster[i])

func tips_on() -> bool:
	## New-player tips (battle coach, faction intros, HQ welcome). DON'T SHOW AGAIN turns them all off;
	## the test harness never sees them.
	return not meta.get("tips_off", false) and not OS.get_cmdline_user_args().has("--iatest")

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
	## T7: the weather fits the ground: no monsoon on ice or lava, a blizzard only on ice and peaks.
	var bio: String = current_mission().get("biome", "")
	var pool: Array = []
	for k in Data.INTEL:
		var it: Dictionary = Data.INTEL[k]
		if it.get("not", []).has(bio) or (it.has("only") and not it.only.has(bio)):
			continue
		for i in it.w:
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
	var sp := next_specialist()
	if sp != "":
		level["specialist"] = sp
		spec_seen.append(sp)
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
	# from level 2 on, one stretch after the mid camp holds a Vharr encounter: E1 Swarm, E2 Nest,
	# E3 Drop Pod Ambush, E4 The Hunt, E5 Thrall Outbreak or E6 Gate Siege
	var encs: Array = Data.ENCOUNTERS.filter(func(k): return k != "droppods" or not bm.rules.get("ceiling", false))  # M4: no pods through rock
	var enc: String = "" if tier < 1 else encs[randi() % encs.size()]
	if tier >= 1 and (id == "desert" or id == "mountain"):
		enc = "queen"  # Q2: the Burrow Queen owns the sand and the scree
	# Q1: from level 2 the Hive Ship hangs over the delta and the harbor instead of a BOAR
	var boss := "hiveship" if (tier >= 1 and (id == "delta" or id == "harbor")) or id == "hive" else "boar"
	# E6: a Jackal Walker holds the first stretch on half of the first levels and every later one
	var walker: bool = (tier >= 1 or randf() < 0.5) and not bm.rules.get("aliens", false)  # M6: no Jackals in the Hive
	# E7, E8: or a Jackal Gunship or a Di-Cokka tank in its place
	var minis := ["jwalker", "dicokka"] if bm.rules.get("ceiling", false) else ["jwalker", "gunship", "dicokka"]
	var miniboss: String = minis[randi() % minis.size()]
	# R2-R4: one mid-level event, R5: three bounties, all on the briefing
	# (their own dice, so adding them left every level's layout as it was)
	var er := RandomNumberGenerator.new()
	er.seed = hash([id, tier, seed_val, mission])
	var event: String = Data.EVENTS.keys()[er.randi() % Data.EVENTS.size()]
	var bpool: Array = Data.BOUNTIES.map(func(x): return x.id).filter(func(k): return k != "sniperfirst" or not bm.rules.get("aliens", false))
	for i in range(bpool.size() - 1, 0, -1):
		var j := er.randi() % (i + 1)
		var t = bpool[i]; bpool[i] = bpool[j]; bpool[j] = t
	if tier == 0 and first_run and daily == "" and not campaign():
		event = ""  # P8: the first fight is the level, the POWs and the Boar; both start from level 2
		bpool = []
	return {"event": event, "bounties": bpool.slice(0, 3), "name": bm.name, "theme": bm.theme, "biome": id, "look": bm.look, "rules": bm.rules, "detours": detours.slice(0, nd), "breach": breach, "encounter": enc, "boss": boss, "walker": walker, "miniboss": miniboss,
		"segments": ["start", pool[0], "camp", "yard", pool[1], "camp", bm.get("arena", "arena")],
		"boss_hp": lv.boss_hp, "plate": lv.plate, "hp_mul": lv.hp_mul, "brief": bm.text}

func start_finale() -> void:
	level = Data.FINALE.duplicate(true)
	if meta.unlocked.has("gatefinale"):
		level["encounter"] = "gate"  # L3: once a campaign shut the Gate, the run's finale has a gate siege too
	# a full heal before the harbor: squads used to arrive at 22 to 42 HP and lose every finale
	for s in soldiers:
		if s.alive:
			s.hp = eff_max_hp(s)

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

func synergies(s: Dictionary) -> Array:
	## Every synergy a soldier is part of, for hover tips: gear sets, kit evolutions and duo partners.
	## Each is {kind, name, prog, done, text}; done means it is switched on right now.
	var out: Array = []
	if not s.has("equip"):
		return out
	var sets := {}
	for sl in s.equip:
		var it = s.equip[sl]
		if it != null and Data.ITEMS[it.id].has("set"):
			sets[Data.ITEMS[it.id].set] = sets.get(Data.ITEMS[it.id].set, 0) + 1
	for k in sets:
		out.append({"kind": "set", "name": Data.SETS[k].name.to_upper(), "prog": "%d/2" % mini(2, sets[k]), "done": sets[k] >= 2,
			"text": set_tip(k, sets[k])})
	for sl in ["kit1", "kit2"]:
		var it = s.equip.get(sl)
		if it == null:
			continue
		for rule in Data.EVOLUTIONS:
			if rule.kit != it.id:
				continue
			var cards: Array = s.deck.filter(func(c): return c.key == rule.card and not c.has("src"))
			var epic: bool = cards.any(func(c): return Data.tier_of(c) >= 3)
			var into: Dictionary = Data.CARDS[rule.into]
			var now := "READY: the Workshop can evolve your Epic %s now." % Data.CARDS[rule.card].name if epic else (
				"Polish a %s to Epic first." % Data.CARDS[rule.card].name if cards.size() else "No %s in this deck yet." % Data.CARDS[rule.card].name)
			out.append({"kind": "evo", "name": "EVOLVE " + into.name.to_upper(), "prog": "READY" if epic else "", "done": epic,
				"text": "%s kit + an Epic %s: the Workshop evolves it into %s. %s %s" % [Data.ITEMS[rule.kit].name, Data.CARDS[rule.card].name, into.name, into.text, now]})
	for d in Data.DUOS:
		if not d.pair.has(s.get("key", "")):
			continue
		var other := soldier(d.pair[0] if d.pair[1] == s.key else d.pair[1])
		if other.is_empty() or not other.get("alive", false):
			continue
		out.append({"kind": "duo", "name": "DUO " + Data.CARDS[d.card].name.to_upper(), "prog": other.def.name, "done": true, "text": duo_tip(d)})
	return out

func set_tip(k: String, n := -1) -> String:
	## What a gear set needs and gives, and how far this soldier is.
	var st: Dictionary = Data.SETS[k]
	var t := "Gear set. %s" % st.text
	if n >= 2:
		t += " ACTIVE on this soldier."
	elif n >= 0:
		t += " Wearing %d: one more piece on the same soldier switches it on." % n
	return t

func duo_tip(d: Dictionary) -> String:
	## A duo Overdrive: who, what it does, and how it shows up.
	var a := soldier(d.pair[0])
	var b := soldier(d.pair[1])
	var an: String = a.def.name if not a.is_empty() else d.pair[0].to_upper()
	var bn: String = b.def.name if not b.is_empty() else d.pair[1].to_upper()
	var h := soldier(d.holder)
	var c: Dictionary = Data.CARDS[d.card]
	return "%s + %s duo Overdrive. When both have an Overdrive ready and stand close, %s gets %s: %s" % [an, bn, h.def.name if not h.is_empty() else d.holder.to_upper(), c.name, c.text]

func evolve(c: Dictionary, rule: Dictionary) -> void:
	c.key = rule.into
	c["from"] = "evolved"
	c["got"] = mission + 1
	c.erase("mods")
	c.erase("nick")

func new_run() -> void:
	# P8: a brand-new player (no run, win, fallen soldier or beaten Boar on record) gets a plainer level 1
	first_run = not meta.get("ran", false) and meta.get("wins", 0) == 0 and meta.get("memorial", []).is_empty() and not meta.get("boar_down", false) and not OS.get_cmdline_user_args().has("--iatest")
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
	defectors = []
	reserve = []
	spec_seen = []
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
	for k in (daily_squad(daily) if daily != "" else draft()):
		soldiers.append(make_soldier(class_def(k)))

# ---------------------------------------------------------------- D2 Daily Op, D3 fun toggles
func daily_key() -> String:
	return Time.get_date_string_from_system()

func daily_squad(key: String) -> Array:
	## The same four classes for everyone on a given day, from every class in the game.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("ironadvance-squad-" + key)
	var keys: Array = Data.SQUAD_DEFS.map(func(d): return d.key)
	var out: Array = []
	while out.size() < 4:
		var k: String = keys[rng.randi() % keys.size()]
		if not out.has(k):
			out.append(k)
	return out

func start_daily() -> void:
	## A fresh run on today's seed: same squad, same dials and maps for everyone today.
	daily = daily_key()
	seed(hash("ironadvance-" + daily))
	new_run()

func daily_best() -> int:
	var d: Dictionary = meta.get("daily", {})
	return int(d.get("score", 0)) if d.get("day", "") == daily_key() else 0

func daily_over() -> void:
	## Keep today's best score. Yesterday's is dropped: the op comes back fresh each day.
	if daily == "":
		return
	if daily_best() < total_score or meta.get("daily", {}).get("day", "") != daily:
		meta["daily"] = {"day": daily, "score": maxi(total_score, daily_best())}
		save_meta()

func toggle_ready(id: String) -> bool:
	for tg in Data.TOGGLES:
		if tg.id == id:
			var fd: Array = Data.FEATS.filter(func(f): return f.id == tg.feat)
			return fd.size() > 0 and int(meta.feats.get(tg.feat, 0)) >= int(fd[0].n)
	return false

func toggle_on(id: String) -> bool:
	return toggle_ready(id) and meta.get("toggles", {}).get(id, false)

func flip_toggle(id: String) -> void:
	if not toggle_ready(id):
		return
	var t: Dictionary = meta.get("toggles", {})
	t[id] = not t.get(id, false)
	meta["toggles"] = t
	save_meta()

# ---------------------------------------------------------------- R5 bounty board
func bounty(id: String) -> Dictionary:
	return Data.BOUNTIES.filter(func(b): return b.id == id)[0]

func bounty_done(id: String, st: Dictionary) -> bool:
	match id:
		"nofall": return int(st.get("falls", 0)) == 0
		"nodown": return int(st.get("downs", 0)) == 0 and int(st.get("kia", 0)) == 0
		"sniperfirst": return st.get("first_kill", "") == "jsniper"
		"crush2": return int(st.get("crushes", 0)) >= 2
		"pows": return int(st.get("pows", 0)) >= int(st.get("pows_total", 0))
		"push3": return int(st.get("pushes", 0)) >= 3
		"fast": return int(st.get("rounds", 99)) <= 18
		"melee3": return int(st.get("melee_kills", 0)) >= 3
	return false

func pay_bounties(st: Dictionary) -> Array:
	## The level's bounties, each [name, pay, done]; the done ones are paid in scrip now.
	var out: Array = []
	for id in level.get("bounties", []):
		var bt := bounty(id)
		var ok := bounty_done(id, st)
		if ok:
			scrip += int(bt.pay)
		out.append([bt.name, int(bt.pay), ok])
	return out

# ---------------------------------------------------------------- X1/X2: the squad draft and specialists
func squad_classes() -> Array:
	## Class keys of the soldiers still in the fight, for class-card offers.
	return soldiers.filter(func(s): return s.alive).map(func(s): return s.key)

func class_def(key: String) -> Dictionary:
	return Data.SQUAD_DEFS.filter(func(x): return x.key == key)[0]

func class_keys() -> Array:
	## Every class you can field: the four you start with plus the specialists you've freed.
	return Data.SQUAD_DEFS.map(func(d): return d.key).filter(func(k): return Data.BASE_CLASSES.has(k) or meta.unlocked.has("cls_" + k))

func draft() -> Array:
	## The four classes a quick run starts with. Defaults to the originals.
	var keys := class_keys()
	var d: Array = meta.get("draft", []).filter(func(k): return keys.has(k))
	for k in Data.BASE_CLASSES + keys:
		if d.size() >= 4:
			break
		if not d.has(k):
			d.append(k)
	return d.slice(0, 4)

func set_draft(keys: Array) -> void:
	meta["draft"] = keys.duplicate()
	save_meta()

func next_specialist() -> String:
	## X2: the next locked specialist to hold as a POW, on the first two levels of a quick run.
	if campaign() or spec_seen.size() >= Data.RESCUES_PER_RUN or mission >= Data.RESCUES_PER_RUN or level.get("finale", false):
		return ""
	for k in Data.SPECIALISTS:
		if not meta.unlocked.has("cls_" + k) and not spec_seen.has(k) and not soldiers.any(func(s): return s.key == k):
			return k
	return ""

func free_specialist(key: String) -> Dictionary:
	## X2: a specialist POW was cut loose. The class is unlocked for good, and in a quick run they
	## join the squad for the rest of it, or wait in the barracks when four are already in it.
	## Returns the new soldier, or {} in the campaign.
	if not meta.unlocked.has("cls_" + key):
		meta.unlocked.append("cls_" + key)
		save_meta()
	if campaign():
		return {}
	var d: Dictionary = class_def(key).duplicate()
	var s := make_soldier(d)
	s["rescued"] = true
	join_or_barracks(s)
	return s

func join_or_barracks(s: Dictionary) -> String:
	## A rescued soldier takes a fallen soldier's slot, joins a squad short of four, or else waits
	## in the barracks. Returns "squad" or "barracks".
	var slots := fallen_slots()
	if slots.size():
		soldiers[slots[0]] = s
		return "squad"
	if soldiers.size() < Data.SQUAD_MAX:
		soldiers.append(s)
		return "squad"
	reserve.append(s)
	return "barracks"

func barracks_pool() -> Array:
	## Soldiers who can be called in from the barracks: the reserve in a quick run, the bench in a campaign.
	return bench() if campaign() else reserve.filter(func(s): return s.alive)

func swap_in(s: Dictionary, out) -> void:
	## Puts a barracks soldier into the squad. `out` is the soldier they replace (sent to the
	## barracks if still alive), or null to fill an open place in a squad short of four.
	## Time in the barracks is time to rest: they come in at full health.
	reserve.erase(s)
	s.hp = eff_max_hp(s)
	if out == null:
		var slots := fallen_slots()
		if slots.size():
			soldiers[slots[0]] = s
		else:
			soldiers.append(s)
		return
	var i := soldiers.find(out)
	if i < 0:
		soldiers.append(s)
		return
	soldiers[i] = s
	if out.alive and not campaign():
		reserve.append(out)

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
	var entry := {"name": s.def.name, "key": s.key, "cls": s.def.cls, "lvl": s.lvl,
		"perks": s.perks.duplicate(), "mission": mission + 1}
	if campaign():
		# C6: their best cards wait on the Memorial for the next recruit
		var best: Array = s.deck.filter(func(c): return not c.has("src") and not c.get("temp", false))
		best.sort_custom(func(a, b): return Data.tier_of(a) > Data.tier_of(b))
		entry["cards"] = best.slice(0, Data.LEGACY_CARDS).map(func(c): return {"key": c.key, "tier": Data.tier_of(c)})
		entry["rank"] = rank(s)
		entry["ops"] = int(svc(s).ops)
	meta.memorial.append(entry)
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
			"motor": r = maxi(r, mini(perk_power("fuel"), 2))
			"mess": r = maxi(r, int([0, 1, 3, 3][perk_power("aid")]))
			"armory": r = maxi(r, int([0, 2, 3, 3][perk_power("supply")]))
	return r

func hq_buildings() -> Array:
	## The campaign has no gate dial, so no Gate Control, and adds the story buildings as acts open them (B4).
	if not campaign():
		return Data.HQ_BUILDINGS
	var out: Array = Data.HQ_BUILDINGS.filter(func(B): return B.id != "gate")
	for B in Data.CAMP_BUILDINGS:
		if int(camp.get("act", 0)) >= int(B.act):
			out.append(B)
	return out

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

func implants_of(s: Dictionary) -> Array:
	## B3: in the campaign implants go on the person; in runs on the class, so they outlive permadeath.
	if campaign():
		return s.get("implants", [])
	return implants(s.key) if s.has("key") else []

func implanted(s, id: String) -> bool:
	return s is Dictionary and s.has("key") and implants_of(s).has(id)

func surgery_block(id: String, who) -> String:
	## Why this surgery can't go on this class (or, in the campaign, this soldier) right now, or "" when it can.
	var S: Dictionary = Data.SURGERIES[id]
	var cls: String = who.key if who is Dictionary else who
	if hq("doc") < 1:
		return "BUILD THE DOC'S LAB"
	if S.cls != "" and S.cls != cls:
		return "WRONG CLASS"
	if (implants_of(who) if who is Dictionary else implants(cls)).has(id):
		return "INSTALLED"
	if int(meta.get("bio", 0)) < Data.SURGERY_BIO or int(meta.get("salvage", 0)) < Data.SURGERY_SALVAGE:
		return "NEED %d BIO + %d SALVAGE" % [Data.SURGERY_BIO, Data.SURGERY_SALVAGE]
	return ""

func operate(id: String, who) -> bool:
	## Install a surgery on a class, or on one soldier in the campaign. Past the slot cap the oldest comes out.
	if surgery_block(id, who) != "":
		return false
	meta.bio = int(meta.bio) - Data.SURGERY_BIO
	meta.salvage = int(meta.salvage) - Data.SURGERY_SALVAGE
	var cls: String = who.key if who is Dictionary else who
	var have: Array = (implants_of(who) if who is Dictionary else implants(cls)).duplicate()
	while have.size() >= hq("doc"):
		have.pop_front()
	have.append(id)
	if who is Dictionary:
		who["implants"] = have
		save_meta()
		return true
	if not meta.has("implants"):
		meta.implants = {}
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
	var used: Array = (roster if campaign() else soldiers).filter(func(s): return s.alive).map(func(s): return s.def.name)
	var names: Array = Data.CALLSIGNS.filter(func(c): return not used.has(c))
	names.shuffle()
	var traits: Array = Data.RECRUIT_TRAITS.duplicate()
	traits.shuffle()
	var keys := recruit_classes()
	var out: Array = []
	var deck := legacy_deck()
	for i in n:
		var key: String = keys[i % keys.size()]
		if i < defectors.size():
			out.append({"key": Data.DEFECTOR_CLASS.base if campaign() else key, "name": defectors[i], "trait": Data.DEFECTOR_TRAIT, "legacy": {}, "look": Art.random_look(), "drill_card": "", "legacy_deck": ""})
			continue
		out.append({"key": key, "name": names[i], "trait": traits[i % traits.size()], "legacy": legacy_perk(key), "look": Art.random_look(), "drill_card": drilled_card(key), "legacy_deck": deck.get("name", "")})
	# L3: classes a campaign unlocked turn up among run recruits now and then
	if not campaign() and out.size():
		for sp in ["defector", "engineer"]:
			if meta.unlocked.has("cls_" + sp) and randf() < 0.25:
				out[out.size() - 1] = spec_offer(sp, out[out.size() - 1].name)
				break
	return out

func spec_offer(spec: String, nm: String) -> Dictionary:
	## A recruit offer for one of the campaign classes (C7).
	if spec == "defector":
		return {"key": Data.DEFECTOR_CLASS.base, "name": nm, "trait": Data.DEFECTOR_TRAIT, "legacy": {}, "look": Art.random_look(), "drill_card": "", "legacy_deck": "", "spec": "defector"}
	return {"key": Data.ENGINEER_CLASS.base, "name": nm, "trait": Data.ENGINEER_CLASS.trait, "legacy": {}, "look": Art.random_look(), "drill_card": "", "legacy_deck": "", "spec": "engineer"}

func recruit_classes() -> Array:
	if campaign():
		# the company may hold two of a class: offer the classes it has fewest of first
		var keys: Array = class_keys()
		keys.shuffle()
		keys.sort_custom(func(a, b): return roster.filter(func(s): return s.alive and s.key == a).size() < roster.filter(func(s): return s.alive and s.key == b).size())
		return keys
	var held: Array = soldiers.filter(func(s): return s.alive).map(func(s): return s.key)
	var slots := fallen_slots()
	var first: String = soldiers[slots[0]].key if slots.size() else ""
	var others: Array = class_keys().filter(func(k): return k != first and not held.has(k))
	others.shuffle()
	var out: Array = ([first] if first != "" and not held.has(first) else []) + others
	return out if out.size() else class_keys()

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
	## Puts a recruit into a fallen soldier's slot. In the campaign they join the company instead.
	if campaign():
		return enlist(o)
	var s := make_recruit(o)
	soldiers[slot] = s
	return s

func make_recruit(o: Dictionary) -> Dictionary:
	var d: Dictionary = Data.SQUAD_DEFS.filter(func(x): return x.key == o.key)[0].duplicate()
	d.name = o.name
	var spec: String = o.get("spec", "defector" if campaign() and o.trait.id == "defector" else "")
	if spec != "":
		# C7: the campaign's own classes (a deserter, a gate engineer), built on a base kit
		var C: Dictionary = Data.DEFECTOR_CLASS if spec == "defector" else Data.ENGINEER_CLASS
		d.cls = C.cls
		d.deck = d.deck + C.deck_add
	var s := make_soldier(d)
	if spec != "":
		s["spec"] = spec
	s.trait = o.trait.id
	s["look"] = o.get("look", Art.random_look())  # U3: recruits show up in their own kit
	match o.trait.id:
		"quick": s.bonus.move += 25
		"tough":
			s.max_hp += 5
			s.hp += 5
		"slippery": s.bonus.dodge += 6
		"excop": s.bonus.dodge += 4
		"farmhand":
			s.max_hp += 8
			s.hp += 8
		"defector":
			s.max_hp += 3
			s.hp += 3
			s.bonus.dodge += 4
			defectors.erase(o.name)
		"drilled":
			var dk: String = o.get("drill_card", drilled_card(o.key))
			var cands: Array = s.deck.filter(func(c): return c.key == dk and upgradable(c))
			if cands.size():
				raise_tier(cands[0])
	if o.trait.has("card"):
		s.deck.append(new_card(o.trait.card, -1, "start"))  # P2: the background's own card
	if not o.legacy.is_empty():
		s.perks.append(o.legacy.id)
	if hq("barracks") >= 2:
		# Barracks 2: a recruit shows up at level 2 with one training pick waiting at the Barracks
		s.xp = xp_for_next(s)
		s.lvl = 2
		s["train"] = true
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
	var n: int = luck + int([0, 1, 2, 2][perk_power("lookout")]) + (1 if perk_power("airfield") >= 2 else 0) + (2 if has_gear("charm") else 0) + (1 if has_gear("dogtags") else 0) + (2 if has_cmd("rabbit") else 0) + temp_luck
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

func drill_ok(s: Dictionary) -> bool:
	## B5: the Drill Sergeant only trains a soldier below the squad's highest level.
	var top := 0
	for x in soldiers:
		if x.alive:
			top = maxi(top, int(x.lvl))
	return s.alive and int(s.lvl) < top

func drill_level(s: Dictionary) -> void:
	s.lvl += 1
	s.xp = xp_floor(s)

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
			return "+%s movement every turn." % Data.meters(STAT_TIERS.move[t])
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
	var full: Array = d.pool + s.get("xtrain", [])  # P3: cross-trained cards join the offers
	var pool: Array = full.filter(func(k): return not ban.has(k))
	if pool.is_empty():
		pool = full.duplicate()
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

func prestige_from(s: Dictionary, perk_id: String) -> String:
	## P1: a capstone renames the soldier's class, pins a gold star on their headgear and adds a small
	## second trait. Returns the new title, or "" if this perk isn't a capstone.
	var bs: Array = Data.BRANCHES.get(s.key, [])
	for i in bs.size():
		var b: Dictionary = bs[i]
		if b.perks[2].id != perk_id or s.has("prestige"):
			continue
		s["prestige"] = b.id
		var tr: Dictionary = Data.PRESTIGE_TRAITS[i % Data.PRESTIGE_TRAITS.size()]
		s["ptrait"] = i % Data.PRESTIGE_TRAITS.size()
		s.max_hp += tr.get("hp", 0)
		s.hp += tr.get("hp", 0)
		s.bonus.move += tr.get("move", 0)
		s.bonus.dodge += tr.get("dodge", 0)
		return title_of(s)
	return ""

func title_of(s: Dictionary) -> String:
	## The class name shown for a soldier: their prestige title once they have one.
	return Data.PRESTIGE.get(s.get("prestige", ""), s.def.cls)

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
			var pr := prestige_from(s, o.id)
			if pr != "":
				return "%s unlocked %s and is now a %s." % [s.def.name, o.name, pr]
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
		# keystones for classes in the squad (X1: a drafted squad never sees another class's)
		var have: Array = soldiers.map(func(s): return s.key)
		var ks: Array = Data.KEYSTONE_IDS.filter(func(k): return have.has(Data.ITEMS[k].keystone))
		if ks.is_empty():
			ks = Data.KEYSTONE_IDS
		return new_item(ks[randi() % ks.size()], t)
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
	# G8: squad gear with stats (Nanite Swarm, boss trophies) counts as worn by everyone
	for id in gear:
		var gs: Dictionary = Data.gear(id).get("stats", {})
		for k in gs:
			out[k] = out.get(k, 0) + (3 if id == "nanites" and relic_tier(id) >= 3 else gs[k])
	for id in s.get("orders_done", []):  # W5: finished personal orders
		var os: Dictionary = Data.ORDERS[id].stats
		for k in os:
			out[k] = out.get(k, 0) + os[k]
	if s.has("key"):
		for id in implants_of(s):
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
	return deployed().filter(func(s): return s.alive).size()

func wing_b() -> Array:
	## W9: squad B on the pincer op, from the roster indices make_op picked.
	var out := []
	if campaign() and level.get("pincer", false):
		for i in level.get("wing_b", []):
			if int(i) < roster.size() and not soldiers.has(roster[int(i)]):
				out.append(roster[int(i)])
	return out

func deployed() -> Array:
	## Everyone who went in: the squad, plus squad B on the pincer.
	return soldiers + wing_b()

func pick_wing_b() -> Array:
	## W9: the four best on the bench by rank, then level, as roster indices. T2: anyone marked B on
	## the company screen goes first.
	var pool: Array = company().filter(func(s): return not soldiers.has(s) and not s.has("guest"))
	pool.sort_custom(func(a, b): return int(a.get("wing", "") == "b") * 10000 + rank(a) * 100 + int(a.lvl) > int(b.get("wing", "") == "b") * 10000 + rank(b) * 100 + int(b.lvl))
	return pool.slice(0, Data.SQUAD_MAX).map(func(s): return roster.find(s))

func pincer_ahead() -> bool:
	## T2: the company screen offers squad B picks in the last act, once the company is big enough.
	return int(camp.get("act", 0)) == Data.ACTS.size() - 1 and company().size() >= Data.PINCER_COMPANY

func toggle_wing(s: Dictionary) -> String:
	## T2: mark a bench soldier for squad B on the pincer, or unmark them.
	if s.get("wing", "") == "b":
		s.erase("wing")
		return ""
	if company().filter(func(x): return x.get("wing", "") == "b" and not soldiers.has(x)).size() >= Data.SQUAD_MAX:
		return "SQUAD B IS FULL: UNMARK SOMEONE"
	s["wing"] = "b"
	return ""

func svc_rec(st: Dictionary, s: Dictionary) -> Dictionary:
	## An op's kills, XP and downs for one soldier: by roster slot when booked that way (two of a class
	## can deploy on the pincer), else by class key.
	var r: Dictionary = st.get("by", {}).get(str(roster.find(s)), {})
	if not r.is_empty():
		return r
	return {"k": int(st.get("kills_by", {}).get(s.key, 0)), "down": st.get("downed_by", {}).get(s.key, false), "xp": int(st.get("xp", {}).get(s.key, 0))}

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
	roster = soldiers.duplicate()
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
	set_state(data)
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
	var head := {"act": int(camp.act), "ops": int(camp.ops), "secs": float(camp.get("secs", 0.0)), "done": camp.get("done", false), "tour": int(camp.get("tour", 1)), "act_name": act().name,
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
	roster = []
	threat = 0
	new_run()

func act(a := -1) -> Dictionary:
	var i := clampi(int(camp.get("act", 0)) if a < 0 else a, 0, Data.ACTS.size() - 1)
	var fr: Array = camp.get("fronts", [])
	if i < fr.size() and int(fr[i]) == 1 and Data.ALT_ACTS.has(i):
		return Data.ALT_ACTS[i]  # W14: this tour fights the act on its other front
	return Data.ACTS[i]

func act_index(act_name: String) -> int:
	for i in Data.ACTS.size():
		if act(i).name == act_name or Data.ACTS[i].name == act_name or Data.ALT_ACTS.get(i, {}).get("name", "") == act_name:
			return i
	return -1

func pick_fronts(tour: int, last: Array) -> Array:
	## W14: the first war runs the home fronts. A Second Tour runs every other front; later tours
	## roll each act but never replay the last war's map exactly.
	var fr := []
	for i in Data.ACTS.size():
		fr.append(0)
	if tour <= 1:
		return fr
	var alts: Array = Data.ALT_ACTS.keys()
	if tour == 2:
		for i in alts:
			fr[i] = 1
		return fr
	for i in alts:
		fr[i] = randi() % 2
	var old: Array = last if last.size() == fr.size() else pick_fronts(1, [])
	if fr == old:
		var k: int = alts[randi() % alts.size()]
		fr[k] = 1 - int(fr[k])
	return fr

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
	return act().sectors.filter(func(sc): return not sc.get("stronghold", false) and not sc.has("story") and camp.held.has(sec_key(sc.id))).size()

func sector_open(sc: Dictionary) -> bool:
	## M1: open when it touches ground you hold. The stronghold waits for "need" sectors.
	if camp.held.has(sec_key(sc.id)):
		return false
	if sc.get("stronghold", false):
		return held_count() >= int(act().need)
	return sc.links.any(func(l): return sector_held(l))

func camp_perk(id: String) -> bool:
	## M3: a held sector's perk, only for the act it's in (or the whole war once fortified, W4).
	return perk_power(id) > 0

func perk_power(id: String) -> int:
	## W4: 0 when no held sector gives this perk now, else its strength: 1 (rank 0-1), 2 or 3.
	if not campaign():
		return 0
	var best := 0
	for key in camp.get("held", []):
		var parts: PackedStringArray = key.split(":")
		var sc := sector(parts[1], int(parts[0]))
		if sc.get("perk", "") != id:
			continue
		var f := fort(key)
		if int(parts[0]) == int(camp.get("act", 0)) or f >= 1:
			best = maxi(best, maxi(1, f))
	return mini(best, 3)

func fort(key: String) -> int:
	## W4: how far a held sector ("act:id") is fortified, 0-3.
	return int(camp.get("fort", {}).get(key, 0))

func fortify_block(sc: Dictionary) -> String:
	## Why this sector can't be fortified right now, or "".
	var key := sec_key(sc.id)
	if sc.get("stronghold", false) or not camp.held.has(key):
		return "HOLD IT FIRST"
	if fort(key) >= Data.FORTIFY_COST.size():
		return "FULLY FORTIFIED"
	if scrip < Data.FORTIFY_COST[fort(key)]:
		return "NEED %d SCRIP" % Data.FORTIFY_COST[fort(key)]
	return ""

func fortify(sc: Dictionary) -> bool:
	if fortify_block(sc) != "":
		return false
	var key := sec_key(sc.id)
	scrip -= Data.FORTIFY_COST[fort(key)]
	var f: Dictionary = camp.get("fort", {})
	f[key] = fort(key) + 1
	camp["fort"] = f
	save_campaign()
	return true

func hold_pay(sc: Dictionary, f: int) -> Dictionary:
	## W4: what a held sector pays after each op at fortify rank f.
	var out := {}
	var h: Dictionary = sc.get("hold", {})
	for k in h:
		out[k] = ceili(int(h[k]) * (1.0 + 0.5 * f))
	if sc.has("perk") and f >= 3:
		out["salvage"] = 1
	return out

func income() -> Dictionary:
	## M2: what every held sector in the war pays after each op.
	var out := {"scrip": 0, "salvage": 0, "bio": 0}
	if not campaign():
		return out
	for key in camp.held:
		var parts: PackedStringArray = key.split(":")
		var h := hold_pay(sector(parts[1], int(parts[0])), fort(key))
		for k in h:
			out[k] = out.get(k, 0) + int(h[k])
	return out

func make_op(sc: Dictionary, patrol := false, bonus := "") -> Dictionary:
	## One operation on the war map. A sector op is shorter than a run level: one camp, then the
	## sector's boss. A stronghold keeps the full length. A patrol replays a held sector (M5).
	var a := act()
	var lv := make_level(sc.biome, int(a.tier), randf() < float(a.breach))
	lv.hp_mul = a.hp_mul
	lv.boss_hp = a.boss_hp
	lv.plate = a.plate
	lv.name = sc.name
	if sc.get("finale", false) and not patrol:
		# S1 Act V: the harbor flagship, refit with Vharr tech, with the Gate itself open on the pier
		lv = Data.FINALE.duplicate(true)
		lv["biome"] = sc.biome
		lv["encounter"] = "gate"
		lv.name = sc.name
		lv.hp_mul = a.hp_mul
		lv.boss_hp = int(a.boss_hp * 1.2)
		lv.plate = int(a.plate * 1.2)
	var segs: Array = lv.segments
	var job := op_job(sc, patrol) if bonus == "" else str(Data.BONUS_OPS[bonus].job)
	var opener: bool = int(camp.get("act", 0)) == 0 and sc.get("opener", false) and not patrol and bonus == "" and job == "push"
	if job != "push":
		# O2-O6: no boss at the end, one more fighting stretch instead
		var bm: Dictionary = Data.BIOMES[sc.biome]
		lv.segments = ["start", segs[1], "camp", "yard", segs[4], bm.segments[randi() % bm.segments.size()]]
	elif sc.get("finale", false) and not patrol:
		if company().size() >= Data.PINCER_COMPANY and pick_wing_b().size() >= Data.SQUAD_MAX:
			# W9: two squads of four, one in from each end of the harbor, the flagship between them
			lv["pincer"] = true
			lv["wing_b"] = pick_wing_b()
			lv.segments = ["start", "docks", "pier", "warehouse", "start"]
	elif opener:
		# M2/M3: the war's opener (Mudflat Landing or Dry Wadi) keeps the full quick-run layout, a camp before the Boar, and no river mortar crew
		var calm: Array = Data.BIOMES[sc.biome].segments.filter(func(k): return k != "river")
		calm.shuffle()
		lv.segments = ["start", segs[1] if segs[1] != "river" else calm[0], "camp", "yard", segs[4] if segs[4] != "river" else calm[1], "camp", segs[6]]
	elif not sc.get("stronghold", false):
		lv.segments = ["start", segs[1], "camp", "yard", segs[4], segs[6]]
	else:
		lv.boss_hp = int(a.boss_hp * 1.2)
		lv.plate = int(a.plate * 1.2)
	if sc.get("queen", false):
		lv.encounter = "queen"
	if int(camp.get("act", 0)) == 0 and sc.get("opener", false) and not patrol:
		# B4: Mudflat Landing (or T8 Dry Wadi), the first op of every war, is plain like a first quick run: no mini-boss, no event
		lv.walker = false
		lv.event = ""
		# M1: and it meets the quick run's level 1 Boar, not the Act I one
		lv.boss_hp = int(Data.LEVELS[0].boss_hp)
		lv.plate = int(Data.LEVELS[0].plate)
	if int(camp.get("act", 0)) == 2 and sc.get("stronghold", false) and not patrol:
		lv["vharr_boar"] = true  # S1 Act III: the Infested Works' Boar comes back refit by the Vharr
	var tour := int(camp.get("tour", 1))
	if tour > 1:
		var m := 1.0 + Data.TOUR_HARDER * (tour - 1)
		lv.hp_mul = lv.hp_mul * m
		lv.boss_hp = int(lv.boss_hp * m)
		lv.plate = int(lv.plate * m)
	lv["op"] = sc.id
	lv["act"] = int(camp.get("act", 0))
	lv["job"] = job
	var nem := next_nemesis()
	if not patrol and not nem.is_empty() and not lv.get("finale", false):
		lv["nemesis"] = nem.duplicate()  # W3: an officer who got away is waiting on this op
	if sc.get("varga", false) and not patrol and camp.get("varga", "") != "joined":
		lv["guest"] = "varga"  # S3: the colonel fights alongside the company this once
	lv["patrol"] = patrol
	lv["liberated"] = patrol or bonus != ""  # W11: the company already holds this ground
	if sc.has("story") and not patrol:
		lv["story"] = sc.story
	lv["stronghold"] = sc.get("stronghold", false) and not patrol
	lv["bonus"] = bonus
	lv["banner"] = "BONUS OP" if bonus != "" else "PATROL" if patrol else ("STRONGHOLD ASSAULT" if lv.stronghold else "OP %d START!" % (int(camp.ops) + 1))
	return lv

func op_job(sc: Dictionary, patrol := false) -> String:
	## A stronghold is always a push. A patrol picks any job at random, for variety.
	if sc.get("stronghold", false) and not patrol:
		return "push"
	if patrol:
		var ks: Array = Data.JOBS.keys()
		if Data.NO_TRUCK.has(sc.get("biome", "")):
			ks.erase("escort")
		return ks[randi() % ks.size()]
	return sc.get("job", "push")

func op_roster(lv: Dictionary) -> String:
	## B4 Comms 1: every enemy type waiting in the op's segments, for the brief.
	var n := {}
	for sname in lv.get("segments", []):
		for sp in Data.SEGMENTS[sname].spawns:
			var ty: String = sp[0]
			if ty == "boss" and lv.get("boss", "") == "hiveship":
				ty = "hiveship"
			if Data.ETYPES.has(ty):
				var nm: String = Data.ETYPES[ty].name.to_upper()
				n[nm] = int(n.get(nm, 0)) + 1
	var parts: Array = []
	for k in n:
		parts.append("%d %s" % [n[k], k])
	if lv.get("encounter", "") != "":
		parts.append("A VHARR " + str(lv.encounter).to_upper())
	return ", ".join(parts)

func job_text(job: String) -> String:
	var tx: String = Data.JOBS[job].text
	return tx % Data.HOLD_PHASES if job == "hold" else tx

func start_op(sc: Dictionary, patrol := false) -> void:
	## A held sector attacked (not patrolled) is its bonus op (P2).
	mission = int(camp.ops)   # the Quartermaster restocks after every op
	var bonus := bonus_at(sc) if not patrol and sector_held(sc.id) else ""
	level = make_op(sc, patrol, bonus)
	history.clear()
	camp["last"] = sc.id  # W10: where the company token waits on the map
	if not sector_held(sc.id):
		var tried: Array = camp.get("tried", [])
		if not tried.has(sec_key(sc.id)):
			tried.append(sec_key(sc.id))
		camp["tried"] = tried

func op_over(won: bool) -> Dictionary:
	## Book an op on the war map. Returns what changed for the result screen.
	camp.ops = int(camp.ops) + 1
	camp.act_ops = int(camp.act_ops) + 1
	var out := {}
	if level.get("bonus", "") != "" and won:
		camp.bonus = {}
		out["bonus"] = Data.BONUS_OPS[level.bonus].name
		out["pay"] = Data.BONUS_OPS[level.bonus].get("pay", "epic")
	if not won or level.get("patrol", false) or level.get("bonus", "") != "":
		return out
	var sc := sector(level.op)
	if not camp.held.has(sec_key(sc.id)):
		camp.held.append(sec_key(sc.id))
		out["took"] = sc.name
		if sc.has("perk"):
			out["perk"] = sc.perk
	if sc.get("stronghold", false):
		out["act_done"] = act().name
		# L3: campaign milestones unlock run content (the classes, then the gate finale)
		var unl: String = {2: "cls_defector", 3: "cls_engineer", 4: "gatefinale"}.get(int(camp.act), "")
		if unl != "" and not meta.unlocked.has(unl):
			meta.unlocked.append(unl)
			out["unlock"] = unl
		if int(camp.act) >= Data.ACTS.size() - 1:
			camp.done = true
		else:
			camp.act = int(camp.act) + 1
			camp.act_ops = 0
	return out

func after_op(st := {}) -> Dictionary:
	## Back at HQ after an op: service records and promotions, held sectors pay, the fallen leave
	## the roster, everyone is patched up with their dog tags back, Command sends rookies until
	## there are enough to field a squad, and the squad is topped up from the bench.
	var inc := income()
	inc.merge(book_service(st))
	inc["deserter"] = deserter(st)
	var kk: Dictionary = camp.get("kills", {})
	var crash := 2 if st.get("won", false) and Data.BONUS_OPS.get(level.get("bonus", ""), {}).get("pay", "") == "crash" else 1
	for ty in st.get("kinds", {}):
		kk[ty] = int(kk.get(ty, 0)) + int(st.kinds[ty]) * crash
	camp["kills"] = kk
	inc["engineer"] = engineer_joins()
	inc["bonus"] = roll_bonus()
	inc["challenges"] = check_challenges(st)
	inc["nemesis"] = book_nemesis(st)
	inc["varga"] = varga_stand(st)
	write_journal(st, inc)
	scrip += inc.scrip
	meta.salvage = int(meta.get("salvage", 0)) + inc.salvage
	meta.bio = int(meta.get("bio", 0)) + inc.bio
	roster = company()
	var rookies: Array = []
	while roster.size() < Data.SQUAD_MAX:
		rookies.append(enlist(recruit_offers(1)[0]).def.name)
	inc["rookies"] = rookies
	fill_squad()
	for s in roster:
		s.tags = Data.DOG_TAGS
		s.hp = eff_max_hp(s)
	level = {}
	save_meta()
	return inc

func deserter(st: Dictionary) -> String:
	## S4: in Act III a won op can end with a Jackal deserter asking to join. Returns a news line.
	var a := int(camp.get("act", 0)) - (1 if st.get("op", {}).has("act_done") else 0)
	if a != 2 or not st.get("won", false) or level.get("patrol", false) or randf() >= Data.DESERTER_CHANCE:
		return ""
	var used: Array = roster.map(func(s): return s.def.name) + defectors
	var names: Array = Data.CALLSIGNS.filter(func(c): return not used.has(c))
	if names.is_empty():
		return ""
	var nm: String = names[randi() % names.size()]
	if company_room():
		var s := enlist(spec_offer("defector", nm))
		return "%s, a Jackal deserter, joined the company as a %s." % [s.def.name, s.def.cls]
	defectors.append(nm)
	return "%s, a Jackal deserter, waits at the Barracks for a free bunk." % nm

func engineer_joins() -> String:
	## C7: when Act IV opens, a Gate Engineer reports to the company.
	if int(camp.get("act", 0)) < 3 or camp.get("engineer", false) or not company_room():
		return ""
	camp["engineer"] = true
	var used: Array = roster.map(func(s): return s.def.name)
	var names: Array = Data.CALLSIGNS.filter(func(c): return not used.has(c))
	var s := enlist(spec_offer("engineer", names[randi() % names.size()] if names.size() else "SPARKS"))
	return "%s, a Gate Engineer, joined the company with Vharr tech." % s.def.name

func next_nemesis() -> Dictionary:
	## W3: the oldest officer still at large.
	for n in camp.get("nemeses", []):
		if n.alive:
			return n
	return {}

func nemesis_name(n: Dictionary) -> String:
	var t: String = Data.NEMESIS_TITLES[clampi(int(n.rank), 0, Data.NEMESIS_TITLES.size() - 1)]
	return n.name + ("" if t == "" else " " + t)

func book_nemesis(st: Dictionary) -> String:
	## W3: an officer who got away comes back next op, one rank tougher; one who fell is done for good.
	var ns: Array = camp.get("nemeses", [])
	var out := ""
	if st.get("nemesis_killed", "") != "":
		for n in ns:
			if n.name == st.nemesis_killed:
				n.alive = false
				out = "%s is dead. Their signature gear is in the stash." % nemesis_name(n)
	var esc: Dictionary = st.get("nemesis_escaped", {})
	if not esc.is_empty():
		var found := false
		for n in ns:
			if n.name == esc.name:
				found = true
				n.rank = mini(int(n.rank) + 1, Data.NEMESIS_TITLES.size() - 1)
				n.elite = esc.get("elite", n.elite)
				out = "%s got away again. Next time they'll be tougher." % nemesis_name(n)
		if not found:
			var n := {"name": esc.name, "rank": 1, "type": esc.get("type", ""), "elite": esc.get("elite", ""), "alive": true}
			ns.append(n)
			out = "%s got away with a scar. They'll be back on the next op." % nemesis_name(n)
	camp["nemeses"] = ns
	return out

func write_journal(st: Dictionary, inc: Dictionary) -> void:
	## W8: one line per op in the war journal.
	if level.is_empty():
		return
	var a := int(level.get("act", camp.get("act", 0)))
	var sc := sector(str(level.get("op", "")), a)
	var j: Array = camp.get("journal", [])
	j.append({"n": int(camp.ops), "act": a, "sec": sc.get("name", str(level.get("name", ""))), "job": str(level.get("job", "push")),
		"bonus": Data.BONUS_OPS[level.bonus].name if level.get("bonus", "") != "" else "", "patrol": level.get("patrol", false),
		"stronghold": level.get("stronghold", false), "won": st.get("won", false),
		"took": st.get("op", {}).get("took", ""), "squad": st.get("xp", {}).keys().map(func(k): return soldier_name(k)), "kills": int(st.get("kills", 0)),
		"rounds": int(st.get("rounds", 0)), "medals": inc.get("medals", []).size(), "fallen": st.get("fallen", []).duplicate(),
		"nemesis": str(st.get("nemesis", ""))})
	camp["journal"] = j

func soldier_name(key: String) -> String:
	for s in soldiers:
		if s.key == key:
			return s.def.name
	return key.to_upper()

func act_mvp(a: int) -> Dictionary:
	## W2: the soldier with the most kills in act a, among those still in the company.
	var best := {}
	var bk := -1
	for s in company():
		var k := int(svc(s).get("acts", {}).get(str(a), 0))
		if k > bk:
			bk = k
			best = s
	return best

func act_summary(a: int) -> Dictionary:
	## W2: what the act took. Ops fought, ops won, kills, medals and the fallen, from the journal.
	var out := {"ops": 0, "won": 0, "kills": 0, "medals": 0, "fallen": []}
	for e in camp.get("journal", []):
		if int(e.act) != a:
			continue
		out.ops += 1
		out.won += 1 if e.won else 0
		out.kills += int(e.kills)
		out.medals += int(e.medals)
		out.fallen.append_array(e.fallen)
	return out

func check_challenges(st: Dictionary) -> Array:
	## W12: the act's three feats, each paid once. Returns a news line per feat done.
	var out: Array = []
	if level.is_empty() or level.get("patrol", false):
		return out
	var a := int(level.get("act", camp.get("act", 0)))
	var won: bool = st.get("won", false) and alive_count() > 0
	var fell: bool = st.get("downed_by", {}).values().any(func(v): return v)
	var took_fort: bool = st.get("op", {}).has("act_done")
	var done: Dictionary = camp.get("chal", {})
	for id in Data.ACT_CHALLENGES[a]:
		var key := "%d:%s" % [a, id]
		if done.has(key) or not won:
			continue
		var ok := false
		match id:
			"clean": ok = not fell
			"fast": ok = int(st.get("rounds", 99)) <= Data.BLITZ_ROUNDS
			"sweep": ok = took_fort and act(a).sectors.all(func(sc): return sc.get("stronghold", false) or sc.has("story") or camp.held.has(sec_key(sc.id, a)))
			"threat": ok = took_fort and threat >= 2
			"bonus": ok = level.get("bonus", "") != ""
		if not ok:
			continue
		done[key] = true
		meta.salvage = int(meta.get("salvage", 0)) + int(Data.CHALLENGE_PAY.salvage)
		meta.bio = int(meta.get("bio", 0)) + int(Data.CHALLENGE_PAY.bio)
		var it := roll_item(Data.TIER_MAX)
		add_loot(it)
		out.append("Challenge done: %s. +%d salvage, +%d bio and a Legendary %s." % [Data.CHALLENGES[id].name, Data.CHALLENGE_PAY.salvage, Data.CHALLENGE_PAY.bio, Data.item_name(it)])
	camp["chal"] = done
	return out

func challenge_text(id: String) -> String:
	var tx: String = Data.CHALLENGES[id].text
	return tx % Data.BLITZ_ROUNDS if id == "fast" else tx

func bonus_text(kind: String) -> String:
	var tx: String = Data.BONUS_OPS[kind].text
	return tx % Data.BONUS_SALVAGE if kind == "yard" else tx

func roll_bonus() -> String:
	## P2: a bonus op may turn up on a held sector; an old one counts down and leaves. Returns news.
	var b: Dictionary = camp.get("bonus", {})
	if not b.is_empty():
		b.left = int(b.left) - 1
		if int(b.left) <= 0:
			camp.bonus = {}
			return "The %s moved on." % Data.BONUS_OPS[b.kind].name.to_lower()
		return ""
	var held: Array = act().sectors.filter(func(sc): return not sc.get("stronghold", false) and sector_held(sc.id))
	if held.is_empty() or randf() >= Data.BONUS_CHANCE:
		return ""
	var sc: Dictionary = held[randi() % held.size()]
	# W14: no truck column on ice, rails or a carrier deck, same as a patrol
	var kinds: Array = Data.BONUS_OPS.keys().filter(func(k): return Data.BONUS_OPS[k].job != "escort" or not Data.NO_TRUCK.has(sc.get("biome", "")))
	var kind: String = kinds[randi() % kinds.size()]
	camp["bonus"] = {"sec": sec_key(sc.id), "kind": kind, "left": Data.BONUS_OPS_LEFT}
	return "Bonus op at %s: %s. It's there for %d ops." % [sc.name, Data.BONUS_OPS[kind].name.to_lower(), Data.BONUS_OPS_LEFT]

func bonus_at(sc: Dictionary) -> String:
	## The bonus op kind sitting on this sector, or "".
	var b: Dictionary = camp.get("bonus", {})
	return b.kind if not b.is_empty() and b.sec == sec_key(sc.id) else ""

# ---------------------------------------------------------------- B5 the Alien Lab
func tech_need() -> int:
	return Data.TECH_KILLS[mini(maxi(hq("lab"), 1), Data.TECH_KILLS.size()) - 1]

func tech_kills(alien: String) -> int:
	return int(camp.get("kills", {}).get(alien, 0))

func tech_block(id: String) -> String:
	## Why the Lab can't build this tech right now, or "".
	var T: Dictionary = Data.VHARR_TECH.filter(func(x): return x.id == id)[0]
	if hq("lab") < 1:
		return "BUILD THE ALIEN LAB"
	if tech_kills(T.alien) < tech_need():
		return "KILL %d MORE" % (tech_need() - tech_kills(T.alien))
	if int(meta.get("bio", 0)) < Data.TECH_BIO or int(meta.get("salvage", 0)) < Data.TECH_SALVAGE:
		return "NEED %d BIO + %d SALVAGE" % [Data.TECH_BIO, Data.TECH_SALVAGE]
	return ""

func build_tech(id: String) -> Dictionary:
	## Builds one piece of Vharr tech into the stash. The first build unlocks it for runs too (L2).
	if tech_block(id) != "":
		return {}
	meta.bio = int(meta.bio) - Data.TECH_BIO
	meta.salvage = int(meta.salvage) - Data.TECH_SALVAGE
	if not meta.unlocked.has(id):
		meta.unlocked.append(id)
	var it := new_item(id, 3 if hq("lab") >= 3 else maxi(1, roll_tier()))
	add_loot(it)
	save_meta()
	return it

func second_tour(vet: Dictionary) -> void:
	## S5: a new war in the same slot, harder, with one veteran of the last one along for it.
	var slot := int(camp.slot)
	var tour := int(camp.get("tour", 1)) + 1
	var last: Array = camp.get("fronts", [])
	var v: Dictionary = vet.duplicate(true)
	new_campaign(slot)
	camp["tour"] = tour
	camp["fronts"] = pick_fronts(tour, last)
	v.alive = true
	v.tags = Data.DOG_TAGS
	v.hp = eff_max_hp(v)
	v["tour_vet"] = true
	for slot_k in v.equip.keys():
		v.equip[slot_k] = null  # their kit stayed with the old war's stash; the cards they earned come along
	v.deck = v.deck.filter(func(c): return not c.has("src"))
	# the veteran takes the place of the fresh starter who shares their name, so there's one of each
	var twin: Array = roster.filter(func(s): return s.def.name == v.def.name)
	if twin.size():
		roster[roster.find(twin[0])] = v
		if soldiers.has(twin[0]):
			soldiers[soldiers.find(twin[0])] = v
	else:
		roster.append(v)
	if not soldiers.has(v):
		toggle_squad(v)
	save_campaign()

func varga_stand(st: Dictionary) -> String:
	## W13: win Varga's last stand with the colonel still standing and he joins the company for good.
	if level.get("story", "") != "varga" or not st.get("won", false) or camp.has("varga"):
		return ""
	if not st.get("varga_alive", false):
		camp["varga"] = "fell"
		return "Colonel Varga fell covering his men. They join the war in his name."
	camp["varga"] = "joined"
	var s := make_guest("varga")
	s.erase("guest")
	s["spec"] = "colonel"
	s.def["trait"] = ["JACKAL COLONEL", "Varga's own deck and a lifetime of bad habits. Joined Iron Company in Act IV."]
	roster.append(s)
	return "Colonel Varga joined Iron Company as a Jackal Colonel, with his own deck."

func make_guest(id: String) -> Dictionary:
	## S3: Colonel Varga, on loan for one op. Not part of the company, never on the Memorial.
	var d: Dictionary = Data.SQUAD_DEFS.filter(func(x): return x.key == "rook")[0].duplicate()
	d.name = "VARGA"
	d.cls = "Colonel"  # short enough for a roster card next to his level
	d.hp = 40
	d.deck = Data.VARGA_DECK.duplicate()
	var s := make_soldier(d)
	s["guest"] = id
	s.lvl = 5
	s["look"] = {"head": "beret", "hat": 4, "shirt": 1, "pants": 2}  # navy cap and tan coat, like his face on the radio
	return s

# ---------------------------------------------------------------- S2/S3 radio
func radio_line(who: String, text: String, sq: Array, by := {}, mate_name := "") -> Dictionary:
	## One line of chatter. A squad line goes to a random soldier; {name}/{rank}/{mate} are filled in.
	var out := {"who": who, "text": text}
	if who == "sq":
		if sq.is_empty():
			return {}
		var s: Dictionary = by if not by.is_empty() else sq[randi() % sq.size()]
		var mates: Array = sq.filter(func(m): return m != s)
		var mate: String = mate_name.capitalize() if mate_name != "" else mates[randi() % mates.size()].def.name.capitalize() if mates.size() else "Command"
		out["s"] = s
		out["name"] = "%s %s" % [rank_name(s), s.def.name]
		out["role"] = s.def.cls.to_upper()
		out["col"] = Color("ffd23a")
		out.text = text.format({"name": s.def.name.capitalize(), "rank": rank_name(s), "mate": mate})
	else:
		var C: Dictionary = Data.RADIO_CAST[who]
		out["name"] = C.name
		out["role"] = C.role
		out["col"] = C.col
	return out

func landfall_radio() -> Array:
	## C4: Hale's first call of a war. T1: on a Second Tour he greets the veteran instead.
	var sq: Array = soldiers.filter(func(s): return s.alive)
	var vets: Array = roster.filter(func(s): return s.get("tour_vet", false) and s.alive)
	if int(camp.get("tour", 1)) <= 1 or vets.is_empty():
		return Data.RADIO_LANDFALL.map(func(r): return radio_line(r[0], r[1], sq)).filter(func(l): return not l.is_empty())
	var v: Dictionary = vets[0]
	var fill := {"vet": "%s %s" % [rank_name(v), v.def.name.capitalize()], "tour": str(int(camp.tour)), "front": str(act(0).lz.name)}
	var out: Array = []
	for r in Data.RADIO_TOUR:
		var l := radio_line("sq", r[1], sq.filter(func(s): return s != v) + [v], v) if r[0] == "vet" else radio_line(r[0], r[1].format(fill), sq)
		if not l.is_empty():
			out.append(l)
	return out

func radio_before() -> Array:
	## S2: the act's opening the first time, the job, maybe a taunt, and the colonel on his op.
	var sq: Array = soldiers.filter(func(s): return s.alive)
	var a := int(camp.get("act", 0))
	var raw: Array = []
	if int(camp.get("intro", -1)) < a:
		camp["intro"] = a
		raw.append_array(act().get("radio", Data.RADIO_ACT[a]))
	else:
		var jl: Array = Data.RADIO_JOB[level.get("job", "push")]
		raw.append(jl[randi() % jl.size()])
		if randf() < 0.5:
			var tl: Array = act().get("taunt", Data.RADIO_TAUNT[a])
			raw.append(tl[randi() % tl.size()])
	if level.get("story", "") == "varga":
		raw.append_array(Data.RADIO_VARGA_STAND)
	elif level.get("guest", "") == "varga":
		raw.append_array(Data.RADIO_VARGA_OP)
	if level.get("pincer", false):
		raw.append_array(Data.RADIO_PINCER)  # W9: say in the field how the two squads work
	return raw.map(func(r): return radio_line(r[0], r[1], sq)).filter(func(l): return not l.is_empty())

func radio_after(st: Dictionary) -> Array:
	## S2: Command's word on the op, a squad cheer on a win, and the villains when an act falls.
	var sq: Array = soldiers.filter(func(s): return s.alive)
	var op: Dictionary = st.get("op", {})
	var raw: Array = []
	if not st.get("won", false):
		raw.append(Data.RADIO_LOST[randi() % Data.RADIO_LOST.size()])
	elif level.get("story", "") == "varga" and not camp.has("varga") and not level.get("patrol", false):
		raw.append_array(Data.RADIO_VARGA_SAVED if st.get("varga_alive", false) else Data.RADIO_VARGA_FELL)  # W13
	else:
		raw.append(Data.RADIO_WON[randi() % Data.RADIO_WON.size()])
		raw.append(["sq", Data.RADIO_SQ_WON[randi() % Data.RADIO_SQ_WON.size()]])
	if op.has("act_done"):
		var i: int = act_index(op.act_done)
		if i >= 0:
			raw.append_array(Data.RADIO_ACT_DONE[i])
	var lines: Array = raw.map(func(r): return radio_line(r[0], r[1], sq)).filter(func(l): return not l.is_empty())
	# W7: battle buddies in the squad get a line about each other
	for s in sq:
		var bud: Array = buddies(s).filter(func(n): return sq.any(func(x): return x.def.name == n))
		if bud.size():
			lines.append(radio_line("sq", Data.RADIO_BOND[randi() % Data.RADIO_BOND.size()], sq, s, bud[0]))
			break
	return lines

# ---------------------------------------------------------------- the company (C1-C6)
func svc(s: Dictionary) -> Dictionary:
	## C5: a soldier's service record.
	if not s.has("svc"):
		s["svc"] = {"ops": 0, "kills": 0, "downs": 0, "medals": []}
	return s.svc

func rank(s: Dictionary) -> int:
	return int(s.get("rank", 0))

func rank_name(s: Dictionary) -> String:
	if s.get("spec", "") == "colonel":
		return "COL"  # W13: Varga keeps his rank when he joins
	return Data.RANKS[rank(s)].short

func company() -> Array:
	return roster.filter(func(s): return s.alive)

func bench() -> Array:
	return company().filter(func(s): return not soldiers.has(s))

func company_room() -> bool:
	return company().size() < Data.COMPANY_MAX

func slot_key(s: Dictionary) -> String:
	## The squad slot a soldier fills: their class, except Colonel Varga (T4), who is his own.
	return "colonel" if s.get("spec", "") == "colonel" else str(s.key)

func fits_squad(s: Dictionary) -> bool:
	return soldiers.size() < Data.SQUAD_MAX and not soldiers.any(func(x): return slot_key(x) == slot_key(s))

func toggle_squad(s: Dictionary) -> String:
	## C1: put a soldier in or out of the squad. Picking someone whose class is already in it swaps them.
	if soldiers.has(s):
		if soldiers.size() <= 1:
			return "SOMEBODY HAS TO GO"
		soldiers.erase(s)
		return ""
	var same: Array = soldiers.filter(func(x): return slot_key(x) == slot_key(s))
	if same.size():
		soldiers[soldiers.find(same[0])] = s
		return ""
	if soldiers.size() >= Data.SQUAD_MAX:
		return "SQUAD IS FULL: TAKE SOMEONE OUT"
	soldiers.append(s)
	return ""

func fill_squad() -> void:
	## Top the squad up from the bench, one per class.
	soldiers = soldiers.filter(func(x): return x.alive)
	for s in company():
		if not soldiers.has(s) and fits_squad(s):
			soldiers.append(s)

func legacy_deck() -> Dictionary:
	## C6: the oldest unclaimed set of fallen cards on the Memorial.
	for m in meta.get("memorial", []):
		if m.get("cards", []).size() and not m.get("claimed", false):
			return m
	return {}

func enlist(o: Dictionary) -> Dictionary:
	## A new soldier joins the company. They pick up a fallen veteran's best cards when any wait.
	var s := make_recruit(o)
	var m := legacy_deck()
	if not m.is_empty():
		for c in m.cards:
			s.deck.append(new_card(c.key, int(c.tier), "legacy"))
		m["claimed"] = true
		s["legacy_from"] = m.name
	roster.append(s)
	return s

func promo_offers(s: Dictionary) -> Array:
	## The options for the oldest promotion this soldier hasn't picked yet.
	var real := int(s.get("promo", 0)) - int(s.get("field", 0))
	var r := rank(s) - real + 1 if real > 0 else rank(s)  # W2: a field promotion offers their current rank's picks
	return Data.PROMO_OFFERS[clampi(r, 1, Data.RANKS.size() - 1)]

func promote(s: Dictionary, id: String) -> String:
	## C3: apply a promotion pick. Returns a log line.
	match id:
		"hp":
			s.max_hp += 10
			s.hp += 10
		"move": s.bonus.move += 40
		"dodge": s.bonus.dodge += 8
		"hand": s.bonus.hand += 1
		"energy": s.bonus.energy1 += 1
		"legend":
			var best := ""
			for k in s.def.pool:
				if best == "" or int(Data.CARDS[k].cost) > int(Data.CARDS[best].cost) or (Data.CARDS[k].cost == Data.CARDS[best].cost and Data.base_tier(k) > Data.base_tier(best)):
					best = k
			s.deck.append(new_card(best, Data.TIER_MAX, "promotion"))
	if int(s.get("field", 0)) > 0 and int(s.get("promo", 1)) <= int(s.field):
		s.field = int(s.field) - 1  # W2: the act MVP's field promotion is picked after the earned ones
		if s.field <= 0:
			s.erase("field")
	s.promo = int(s.get("promo", 1)) - 1
	if s.promo <= 0:
		s.erase("promo")
	return "%s %s: %s" % [rank_name(s), s.def.name, Data.PROMOTIONS[id].text]

func award(s: Dictionary, id: String) -> bool:
	## C5: a medal, once per soldier, with its bonus.
	var sv := svc(s)
	if sv.medals.has(id):
		return false
	sv.medals.append(id)
	match id:
		"heart":
			s.max_hp += 3
			s.hp += 3
		"marksman": s.bonus.dodge += 3
		"veteran": s.bonus.move += 20
		"ace": s.bonus.energy1 += 1
	return true

func book_service(st: Dictionary) -> Dictionary:
	## After an op: service records, medals, promotions and bench XP. Returns lines for the news.
	var out := {"medals": [], "promos": [], "bench": 0, "orders": [], "bonds": []}
	var won: bool = st.get("won", false)
	var xps: Array = []
	for s in deployed():
		if not s.alive:
			continue
		var sv := svc(s)
		var rec := svc_rec(st, s)
		var k: int = int(rec.k)
		var down: bool = rec.down
		sv.ops = int(sv.ops) + 1
		sv.kills = int(sv.kills) + k
		var ak: Dictionary = sv.get("acts", {})  # W2: kills per act, for the act's MVP
		var a := str(level.get("act", camp.get("act", 0)))
		ak[a] = int(ak.get(a, 0)) + k
		sv["acts"] = ak
		if down:
			sv.downs = int(sv.downs) + 1
		xps.append(int(rec.xp))
		var got: Array = []
		if won and down and award(s, "heart"):
			got.append("heart")
		if k >= 5 and award(s, "marksman"):
			got.append("marksman")
		if sv.ops >= 10 and award(s, "veteran"):
			got.append("veteran")
		if sv.kills >= 30 and award(s, "ace"):
			got.append("ace")
		for m in got:
			out.medals.append("%s: %s" % [s.def.name, Data.MEDALS[m].name])
		if not down:
			var fin := order_tick(s, "ironside")
			if fin != "":
				out.orders.append(fin)
		var promoted := false
		while rank(s) < Data.RANKS.size() - 1 and int(sv.ops) >= int(Data.RANKS[rank(s) + 1].ops):
			s.rank = rank(s) + 1
			s.promo = int(s.get("promo", 0)) + 1
			promoted = true
			out.promos.append("%s is now a %s." % [s.def.name, Data.RANKS[rank(s)].name.capitalize()])
		if promoted and rank(s) >= 1 and not s.has("order"):
			var oid := assign_order(s)
			if oid != "":
				out.orders.append("%s has a personal order: %s" % [s.def.name, order_text(oid)])
	# W7: soldiers who keep finishing ops together become battle buddies
	var team: Array = deployed().filter(func(x): return x.alive and not x.has("guest"))
	for a in team:
		for b in team:
			if a == b:
				continue
			var m: Dictionary = svc(a).get("mates", {})
			m[b.def.name] = int(m.get(b.def.name, 0)) + 1
			svc(a)["mates"] = m
	for i in team.size():
		for k in range(i + 1, team.size()):
			var a: Dictionary = team[i]
			var b: Dictionary = team[k]
			if int(svc(a).mates.get(b.def.name, 0)) >= Data.BOND_OPS and not buddies(a).has(b.def.name) and buddies(a).size() < Data.BOND_MAX and buddies(b).size() < Data.BOND_MAX:
				a["buddies"] = buddies(a) + [b.def.name]
				b["buddies"] = buddies(b) + [a.def.name]
				out.bonds.append("%s and %s are battle buddies now: +1 energy on the first turn when they deploy together." % [a.def.name, b.def.name])
	# C4: the bench trains on half the squad's average XP; any level they gain is picked at HQ
	var avg := 0.0
	if xps.size():
		avg = float(xps.reduce(func(a, b): return a + b, 0)) / xps.size()
	var bx := int(avg * Data.BENCH_XP)
	if bx > 0:
		for s in bench():
			if wing_b().has(s):
				continue  # squad B earned their own XP in the fight
			var gained := add_xp(s, bx)
			if gained > 0:
				s["train"] = int(s.get("train", 0)) + gained
		out.bench = bx
	# a whole squad promoted (or handed the same order) at once reads as one line of news, not four
	out.promos = merge_news(out.promos, " is now a ", "%s are now %ss.")
	out.orders = merge_news(out.orders, " has a personal order: ", "%s have a personal order: %s.")
	return out

func merge_news(lines: Array, mid: String, many: String) -> Array:
	## Lines "<NAME><mid><rest>" that share their rest fold into one: many % [names, rest without its period].
	var groups := {}
	var order: Array = []
	for l in lines:
		var at: int = l.find(mid)
		var rest: String = l.substr(at + mid.length()) if at > 0 else l
		if not groups.has(rest):
			groups[rest] = []
			order.append(rest)
		if at > 0:
			groups[rest].append(l.substr(0, at))
	var out: Array = []
	for rest in order:
		var names: Array = groups[rest]
		if names.size() < 2:
			out.append(lines.filter(func(l): return l.ends_with(rest))[0])
			continue
		var who: String = ", ".join(names.slice(0, names.size() - 1)) + " and " + str(names.back())
		out.append(many % [who, rest.trim_suffix(".")])
	return out

func buddies(s: Dictionary) -> Array:
	return s.get("buddies", [])

func buddy_deployed(s: Dictionary) -> bool:
	## W7: a battle buddy is in the same squad.
	return buddies(s).any(func(n): return soldiers.any(func(x): return x.alive and x.def.name == n))

func order_text(id: String) -> String:
	return Data.ORDERS[id].text % int(Data.ORDERS[id].goal)

func assign_order(s: Dictionary) -> String:
	## W5: pick an order that fits the soldier's deck, one they haven't finished yet.
	var n := {"AIM": 0, "ARC": 0, "MELEE": 0}
	for c in s.get("deck", []):
		var ty: String = Data.CARDS.get(c.key, {}).get("type", "")
		if n.has(ty):
			n[ty] += 1
	var score := {"headhunter": n.AIM * 1.0, "demo": n.ARC * 1.5, "brawler": n.MELEE * 2.0, "giantkiller": n.AIM * 0.6 + 2.0,
		"bughunter": 6.0 if int(camp.get("act", 0)) >= 1 else 0.0, "wrecker": 3.0, "ironside": 3.0}
	# an order a squadmate already carries scores lower, so a promoted squad doesn't all get the same one
	var held: Array = company().filter(func(x): return x != s and x.has("order")).map(func(x): return x.order.id)
	for id in score:
		score[id] -= 4.0 * held.count(id)
	var best := ""
	for id in score:
		if s.get("orders_done", []).has(id):
			continue
		if best == "" or score[id] + randf() * 0.5 > score[best]:
			best = id
	if best != "":
		s["order"] = {"id": best, "n": 0}
	return best

func order_tick(s: Dictionary, id: String, k := 1) -> String:
	## W5: progress on a personal order. Returns a news line when it is finished, else "".
	var o: Dictionary = s.get("order", {})
	if o.is_empty() or o.id != id:
		return ""
	o.n = int(o.n) + k
	if int(o.n) < int(Data.ORDERS[id].goal):
		return ""
	s.erase("order")
	s["orders_done"] = s.get("orders_done", []) + [id]
	return "%s finished a personal order and earned the title %s: %s." % [s.def.name, Data.ORDERS[id].title, Data.ORDERS[id].up]

func title_line(s: Dictionary) -> String:
	return ", ".join(s.get("orders_done", []).map(func(id): return Data.ORDERS[id].title))

func pending_picks() -> Array:
	## Promotions and training levels waiting for a pick, across the company.
	var out: Array = []
	for s in company():
		for i in int(s.get("promo", 0)):
			out.append({"s": s, "kind": "promo"})
		for i in int(s.get("train", 0)):
			out.append({"s": s, "kind": "train"})
	return out

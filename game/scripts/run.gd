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

func new_run() -> void:
	soldiers.clear()
	gear.clear()
	history.clear()
	scrip = 60
	mission = 0
	total_score = 0
	uid = 1
	seed_val = randi()
	for d in Data.SQUAD_DEFS:
		var deck: Array = []
		for k in d.deck:
			deck.append(new_card(k))
		soldiers.append({
			"key": d.key, "def": d, "hp": d.hp, "max_hp": d.hp, "alive": true,
			"lvl": 1, "xp": 0, "deck": deck, "perks": [],
			"bonus": {"move": 0, "dodge": 0, "hand": 0, "energy1": 0},
		})

func new_card(key: String, up := false) -> Dictionary:
	uid += 1
	return {"id": uid, "key": key, "up": up}

func soldier(key: String) -> Dictionary:
	for s in soldiers:
		if s.key == key:
			return s
	return {}

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
		n = int(ceil(n * 1.5))
	s.xp += n
	var gained := 0
	while s.xp >= xp_for_next(s):
		s.lvl += 1
		gained += 1
	return gained

func level_options(s: Dictionary) -> Array:
	## Three choices for a level-up: a class card, a stat boost and an ability unlock.
	var out: Array = []
	var d: Dictionary = s.def
	var pool: Array = d.pool.duplicate()
	pool.shuffle()
	var ckey: String = pool[0]
	var up: bool = s.lvl >= 4 and randf() < 0.5
	out.append({"kind": "card", "key": ckey, "up": up})
	var stats: Array = Data.STAT_BOOSTS.duplicate()
	stats.shuffle()
	for st in stats:
		if st.id == "hand" and s.bonus.hand >= 2:
			continue
		if st.id == "energy" and s.bonus.energy1 >= 1:
			continue
		if st.id == "upgrade" and not s.deck.any(func(c): return not c.up and Data.CARDS[c.key].has("up")):
			continue
		out.append({"kind": "stat", "id": st.id, "name": st.name, "text": st.text})
		break
	var perks: Array = Data.PERKS[d.key].filter(func(p): return not s.perks.has(p.id))
	if perks.size():
		var p: Dictionary = perks[randi() % perks.size()]
		out.append({"kind": "perk", "id": p.id, "name": p.name, "text": p.text})
	else:
		for st in stats:
			if out.any(func(o): return o.get("id", "") == st.id):
				continue
			if st.id in ["hand", "energy", "upgrade"]:
				continue
			out.append({"kind": "stat", "id": st.id, "name": st.name, "text": st.text})
			break
	return out

func apply_option(s: Dictionary, o: Dictionary) -> String:
	## Applies a level-up choice to the persistent soldier. Returns a log line.
	match o.kind:
		"card":
			var c := new_card(o.key, o.up)
			s.deck.append(c)
			return "%s added %s to the deck." % [s.def.name, Data.card(c).name]
		"perk":
			s.perks.append(o.id)
			return "%s unlocked %s." % [s.def.name, o.name]
		"stat":
			match o.id:
				"hp":
					s.max_hp += 5
					s.hp += 5
				"move":
					s.bonus.move += 25
				"dodge":
					s.bonus.dodge += 6
				"hand":
					s.bonus.hand += 1
				"energy":
					s.bonus.energy1 += 1
				"upgrade":
					var cands: Array = s.deck.filter(func(c): return not c.up and Data.CARDS[c.key].has("up"))
					if cands.size():
						var c: Dictionary = cands[randi() % cands.size()]
						c.up = true
						return "%s's %s is now %s." % [s.def.name, Data.CARDS[c.key].name, Data.card(c).name]
			return "%s: %s." % [s.def.name, o.name]
	return ""

func alive_count() -> int:
	return soldiers.filter(func(s): return s.alive).size()

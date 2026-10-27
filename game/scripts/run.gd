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

func new_run() -> void:
	soldiers.clear()
	gear.clear()
	history.clear()
	scrip = 60
	mission = 0
	luck = 0
	pity_rare = 0
	pity_epic = 0
	stash.clear()
	belt.clear()
	gear_tier.clear()
	trophies.clear()
	discount = 0.0
	reroll_tokens = 0
	gunsmith_uses = 0
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
			"equip": {"weapon": null, "armor": null, "kit1": null, "kit2": null},
		})

func new_card(key: String, tier := -1) -> Dictionary:
	uid += 1
	return {"id": uid, "key": key, "tier": Data.base_tier(key) if tier < 0 else maxi(tier, Data.base_tier(key))}

func luck_total() -> int:
	var n := luck + (2 if has_gear("charm") else 0) + (1 if has_gear("dogtags") else 0)
	for s in soldiers:
		if s.alive:
			n += int(gear_bonus(s).get("luck", 0))
	return n

func tier_weights() -> Array:
	## Rarity odds for this point in the run. Later missions and Luck move weight off Common.
	var w: Array = Data.RARITY.slice(0, Data.TIER_MAX + 1).map(func(r): return r.w)
	var shift := minf(40.0, mission * 6.0 + luck_total() * 3.0)
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
	var pool: Array = d.pool.duplicate()
	pool.shuffle()
	var ckey: String = pool[0]
	out.append({"kind": "card", "key": ckey, "tier": roll_card_tier(ckey)})
	var stats: Array = Data.STAT_BOOSTS.duplicate()
	stats.shuffle()
	for st in stats:
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
	var perks: Array = Data.PERKS[d.key].filter(func(p): return not s.perks.has(p.id))
	if perks.size():
		var p: Dictionary = perks[randi() % perks.size()]
		out.append({"kind": "perk", "id": p.id, "name": p.name, "text": p.text, "tier": 2})
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

func raise_tier(c: Dictionary) -> void:
	c.tier = mini(Data.TIER_MAX, Data.tier_of(c) + 1)
	c.erase("up")

func apply_option(s: Dictionary, o: Dictionary) -> String:
	## Applies a level-up choice to the persistent soldier. Returns a log line.
	var t: int = o.get("tier", 0)
	match o.kind:
		"card":
			var c := new_card(o.key, t)
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
	var ids: Array = Data.ITEMS.keys().filter(func(k): return Data.ITEMS[k].slot in slots)
	return ids[randi() % ids.size()]

func roll_item(min_tier := 0, slots := ["weapon", "armor", "kit"]) -> Dictionary:
	return new_item(random_item_id(slots), roll_tier(min_tier))

func medals(st: Dictionary) -> Array:
	## Debrief medals (L9). Each one earns a supply crate, up to three; a win always earns one.
	var segs: int = Data.MISSIONS[mission].segments.size()
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
		var set_id: String = Data.ITEMS[it.id].get("set", "")
		if set_id != "":
			sets[set_id] = sets.get(set_id, 0) + 1
	for set_id in sets:
		if sets[set_id] >= 2:
			for k in Data.SETS[set_id].bonus:
				out[k] = out.get(k, 0) + Data.SETS[set_id].bonus[k]
	return out

func eff_max_hp(s: Dictionary) -> int:
	return s.max_hp + int(gear_bonus(s).get("hp", 0))

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
	if Data.ITEMS[it.id].slot == "belt" and belt.size() < Data.BELT_MAX:
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
	var c := new_card(g[0].key, Data.tier_of(g[0]) + 1)
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

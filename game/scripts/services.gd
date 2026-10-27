extends RefCounted
## HQ services in one place, so the Quartermaster tiles and the Dossier's card buttons price,
## explain and apply them the same way. Every check that says no also says why.

const POLISH := 60
const BURN := 50
const PATCH := 40
const RESTOCK := 20
const MIN_DECK := 5

static func price(n: int) -> int:
	return int(ceil(n * (1.0 - Run.discount - (0.1 if Run.hq("armory") >= 2 else 0.0))))

static func pay(n: int) -> bool:
	if Run.scrip < n:
		Sfx.play("deny")
		return false
	Run.scrip -= n
	Sfx.play("buy")
	return true

static func short(n: int) -> String:
	return "Short by %d scrip." % (n - Run.scrip)

# ---------------------------------------------------------------- what a card can have done to it
static func card_actions(s: Dictionary, c: Dictionary) -> Array:
	## The five card services for one card, in button order. Each is
	## {id, name, cost, line, ok, why}: line says what happens, why says what is missing.
	return [polish_info(s, c), gunsmith_info(s, c), fuse_info(s, c), evolve_info(s, c), burn_info(s, c)]

static func next_tier(c: Dictionary) -> Dictionary:
	var n := c.duplicate(true)
	n.tier = mini(Data.TIER_MAX, Data.tier_of(c) + 1)
	n.erase("up")
	return n

static func change_line(a: Dictionary, b: Dictionary) -> String:
	## "DMG 6-8 > DMG 8-10" from two resolved cards, or the rule text when the numbers match.
	var sa := Data.stat_line(Data.card(a))
	var sb := Data.stat_line(Data.card(b))
	if sa != sb and sa != "":
		# only the numbers that move: "DMG 6-8 BNC 1" vs "DMG 8-10 BNC 1" -> "DMG 6-8 > 8-10"
		var ta := sa.split(" ")
		var tb := sb.split(" ")
		if ta.size() != tb.size():
			return "%s > %s" % [sa, sb]
		var out: Array = []
		for i in ta.size():
			if ta[i] != tb[i]:
				out.append("%s%s > %s" % [(ta[i - 1] + " ") if i > 0 and not ta[i - 1].is_valid_float() and not ta[i - 1].contains("-") else "", ta[i], tb[i]])
		return ", ".join(out)
	var ta: String = Data.card(a).text
	var tb: String = Data.card(b).text
	return tb if ta != tb else "Stronger %s effect." % Data.tier_name(Data.tier_of(b)).capitalize()

static func is_od(c: Dictionary) -> bool:
	return c.get("od", false) or Data.CARDS[c.key].get("od", false)

static func polish_info(s: Dictionary, c: Dictionary) -> Dictionary:
	var p := price(POLISH)
	var o := {"id": "polish", "name": "POLISH", "cost": p, "ok": false, "why": "", "line": ""}
	if is_od(c):
		o.why = "Overdrive cards are already maxed."
	elif not Run.upgradable(c):
		o.why = "Legendary is the top rarity."
	else:
		var n := next_tier(c)
		o.line = "%s > %s. %s" % [Data.tier_name(Data.tier_of(c)), Data.tier_name(n.tier), change_line(c, n)]
		o.ok = Run.scrip >= p
		if not o.ok:
			o.why = short(p)
	return o

static func gunsmith_info(s: Dictionary, c: Dictionary) -> Dictionary:
	var p := price(Data.MOD_PRICE)
	var o := {"id": "gunsmith", "name": "GUNSMITH", "cost": p, "ok": false, "why": "", "line": ""}
	var have: int = c.get("mods", []).size()
	var opts := Data.mod_options(c)
	if is_od(c):
		o.why = "Overdrive cards take no mods."
	elif opts.is_empty():
		o.why = "Already holds %d mods, the most a card can." % Data.MAX_MODS
	else:
		o.line = "Mod %d of %d: %s." % [have + 1, Data.MAX_MODS, ", ".join(opts.map(func(m): return m.name))]
		o.ok = Run.scrip >= p
		if not o.ok:
			o.why = short(p)
	return o

static func fuse_group(s: Dictionary, c: Dictionary) -> Array:
	## Cards in this soldier's deck that could fuse with c (same card, same rarity), c first.
	if c.has("src") or c.get("temp", false) or is_od(c) or Data.tier_of(c) >= Data.TIER_MAX:
		return []
	var g: Array = [c]
	for o in s.deck:
		if o != c and o.key == c.key and Data.tier_of(o) == Data.tier_of(c) and not o.has("src") and not o.get("temp", false):
			g.append(o)
	return g

static func fuse_info(s: Dictionary, c: Dictionary) -> Dictionary:
	var o := {"id": "fuse", "name": "FUSE", "cost": 0, "ok": false, "why": "", "line": ""}
	var g := fuse_group(s, c)
	if c.has("src"):
		o.why = "Weapon cards come and go with the weapon."
	elif is_od(c) or Data.tier_of(c) >= Data.TIER_MAX:
		o.why = "Already at the top rarity."
	elif g.size() < 3:
		o.why = "Needs 3 %s %s. Have %d." % [Data.tier_name(Data.tier_of(c)).capitalize(), Data.card(c).name, g.size()]
	else:
		o.line = "3 %s into 1 %s. %s" % [Data.tier_name(Data.tier_of(c)).capitalize(), Data.tier_name(Data.tier_of(c) + 1).capitalize(), change_line(c, next_tier(c))]
		o.ok = true
	return o

static func evolve_rule(c: Dictionary) -> Dictionary:
	for r in Data.EVOLUTIONS:
		if r.card == c.key:
			return r
	return {}

static func evolve_info(s: Dictionary, c: Dictionary) -> Dictionary:
	var o := {"id": "evolve", "name": "EVOLVE", "cost": 0, "ok": false, "why": "", "line": ""}
	var r := evolve_rule(c)
	if r.is_empty():
		o.why = "Only %s evolve." % ", ".join(Data.EVOLUTIONS.map(func(e): return Data.CARDS[e.card].name))
		return o
	var kit: String = Data.ITEMS[r.kit].name
	var into: String = Data.CARDS[r.into].name
	if c.has("src"):
		o.why = "Weapon cards can't evolve."
	elif Data.tier_of(c) < 3:
		o.why = "Becomes %s at Epic with the %s kit. Now %s." % [into, kit, Data.tier_name(Data.tier_of(c)).capitalize()]
	elif not Run.evolutions(s).any(func(e): return e.card == c):
		o.why = "Equip the %s kit to turn it into %s." % [kit, into]
	else:
		o.line = "Becomes %s. %s" % [into, Data.CARDS[r.into].text]
		o.ok = true
	return o

static func burn_info(s: Dictionary, c: Dictionary) -> Dictionary:
	var p := price(BURN)
	var o := {"id": "burn", "name": "BURN", "cost": p, "ok": false, "why": "", "line": ""}
	if c.has("src"):
		o.why = "Unequip the weapon to drop its cards."
	elif s.deck.size() <= MIN_DECK:
		o.why = "Decks keep at least %d cards." % MIN_DECK
	else:
		o.line = "Deck %d > %d. Your other cards come up more." % [s.deck.size(), s.deck.size() - 1]
		o.ok = Run.scrip >= p
		if not o.ok:
			o.why = short(p)
	return o

# ---------------------------------------------------------------- doing it
static func polish(c: Dictionary) -> bool:
	if not Run.upgradable(c) or not pay(price(POLISH)):
		return false
	Run.raise_tier(c)
	return true

static func gunsmith(c: Dictionary, mod_id: String) -> bool:
	if not pay(price(Data.MOD_PRICE)):
		return false
	if not c.has("mods"):
		c["mods"] = []
	c.mods.append(mod_id)
	return true

static func fuse(s: Dictionary, c: Dictionary) -> Dictionary:
	var g := fuse_group(s, c)
	if g.size() < 3:
		return {}
	return Run.fuse(s, g.slice(0, 3))

static func evolve(s: Dictionary, c: Dictionary) -> bool:
	for e in Run.evolutions(s):
		if e.card == c:
			Run.evolve(c, e.rule)
			return true
	return false

static func burn(s: Dictionary, c: Dictionary) -> bool:
	if c.has("src") or s.deck.size() <= MIN_DECK or not pay(price(BURN)):
		return false
	s.deck.erase(c)
	return true

# ---------------------------------------------------------------- reading a soldier
static func source(s: Dictionary, c: Dictionary) -> String:
	## Where a card came from, in a few words.
	if c.has("src"):
		for sl in s.equip:
			var it = s.equip[sl]
			if it != null and it.uid == c.src:
				return "from the " + Data.item_name(it)
		return "from a weapon"
	match c.get("from", ""):
		"start": return "starting deck"
		"shop": return "bought, level %d" % c.get("got", 1)
		"level": return "level-up, level %d" % c.get("got", 1)
		"drop": return "supply drop, level %d" % c.get("got", 1)
		"fused": return "fused, level %d" % c.get("got", 1)
		"evolved": return "evolved, level %d" % c.get("got", 1)
	return ""

static func src_tag(c: Dictionary) -> String:
	## A four-letter corner tag for a card's origin.
	if c.has("src"):
		return "GUN"
	return {"shop": "SHOP", "level": "LVL", "drop": "DROP", "fused": "FUSE", "evolved": "EVO"}.get(c.get("from", ""), "")

static func branch_fit(s: Dictionary, key: String) -> String:
	## The started archetype this card feeds, if any: its name or type shows up in that
	## branch's chain or perks ("Overwatch fires twice", "+1 ricochet on every AIM card").
	var cd: Dictionary = Data.CARDS[key]
	for b in Data.BRANCHES.get(s.key, []):
		if not b.perks.any(func(p): return s.perks.has(p.id)):
			continue
		var txt: String = b.chain.text + " " + " ".join(b.perks.map(func(p): return p.text))
		if txt.contains(cd.name) or txt.contains(cd.type + " card"):
			return b.name
	return ""

static func alert(s: Dictionary) -> String:
	## The one thing most worth doing for this soldier right now, for the squad bar.
	if not s.alive:
		return "KIA"
	if Run.evolutions(s).size():
		return "EVOLVE"
	if Run.fusable(s).size():
		return "FUSE"
	if s.hp < Run.eff_max_hp(s) and Run.scrip >= price(PATCH):
		return "HURT"
	return ""

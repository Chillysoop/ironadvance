extends Node
## Static game data: cards, squad, enemies, perks, gear and mission layouts.
## Everything tunable lives here so balance passes never touch the simulation.

const W := 960
const H := 540
const CELL := 4
const ROWS := 135  # H / CELL
const WATER_Y := 500
const GRAV := 0.22

const TYPES := {
	"AIM": {"c": Color("53d4e2"), "hint": "AIM: the red laser is the bullet path. Bullets ricochet off stone and concrete and chew into wood and dirt. Hold Shift to freeze the sway, click to fire. Head hits are crits."},
	"ARC": {"c": Color("ffb23e"), "hint": "ARC: cursor direction sets the angle, distance sets the power. Wind drifts it. Click to throw."},
	"LINE": {"c": Color("ff7a3d"), "hint": "LINE: fires straight at the cursor. Click to fire."},
	"MELEE": {"c": Color("ff4d3d"), "hint": "MELEE: click an enemy right next to you. Sends them flying."},
	"ALLY": {"c": Color("62d26f"), "hint": "ALLY: click a squadmate in range (including yourself)."},
	"SELF": {"c": Color("b48cff"), "hint": "SELF: plays instantly."},
}

# Rarity tiers shared by cards, gear, level-up picks and crates. Rarity never sets a card's
# energy cost: a higher tier only improves what the card does.
const RARITY := [
	{"name": "COMMON", "c": Color("c9ccd1"), "w": 55.0},
	{"name": "UNCOMMON", "c": Color("62d26f"), "w": 27.0},
	{"name": "RARE", "c": Color("4f9dff"), "w": 12.0},
	{"name": "EPIC", "c": Color("b46cff"), "w": 5.0},
	{"name": "LEGENDARY", "c": Color("ffb21e"), "w": 1.0},
	{"name": "OVERDRIVE", "c": Color("ff4d3d"), "w": 0.0},
]
const TIER_MAX := 4
const OD_TIER := 5
# Bullets always fly the full distance. The aim laser only shows the first stretch of the
# path, and how far depends on the gun. Index into LASER_LEN; gear can push a gun up a step.
const FULL_RANGE := 2400
const LASER_LEN := [140.0, 220.0, 420.0, 99999.0]
const GUNS := {
	"pistol": {"name": "PISTOL", "laser": 0},
	"shotgun": {"name": "SHOTGUN", "laser": 0},
	"smg": {"name": "SMG", "laser": 1},
	"rifle": {"name": "RIFLE", "laser": 2},
	"mg": {"name": "MACHINE GUN", "laser": 2},
	"sniper": {"name": "SNIPER", "laser": 3},
}

# rarity: base tier of the card (0 common, 1 uncommon, 2 rare, 5 overdrive, never offered)
# "up" holds the changes the first tier-up of a card gets; later tiers scale it further.
const CARDS := {
	"rifle": {"name": "Rifle Shot", "type": "AIM", "cost": 1, "dmg": [6, 8], "range": FULL_RANGE, "gun": "rifle", "bounce": 1, "sway": 0.035, "text": "Ricochets once.", "rarity": 0, "up": {"dmg": [8, 10]}},
	"burst": {"name": "Burst Fire", "type": "AIM", "cost": 2, "dmg": [4, 5], "shots": 3, "range": FULL_RANGE, "gun": "smg", "bounce": 1, "sway": 0.05, "spread": 0.06, "text": "Three rounds. Recoil spreads them.", "rarity": 1, "up": {"shots": 4}},
	"pistol": {"name": "Sidearm", "type": "AIM", "cost": 1, "dmg": [4, 5], "range": FULL_RANGE, "gun": "pistol", "bounce": 2, "sway": 0.022, "text": "Steady. Ricochets twice.", "rarity": 0, "up": {"dmg": [5, 7], "bounce": 3}},
	"snipe": {"name": "Long Shot", "type": "AIM", "cost": 2, "dmg": [14, 18], "range": FULL_RANGE, "gun": "sniper", "bounce": 1, "sway": 0.007, "pierce": true, "still": true, "chip": 5, "text": "Pierces bodies. Sways 4x if you moved.", "rarity": 2, "up": {"dmg": [17, 22]}},
	"shotgun": {"name": "Shotgun", "type": "AIM", "cost": 1, "dmg": [3, 4], "pellets": 6, "range": FULL_RANGE, "gun": "shotgun", "bounce": 0, "sway": 0.02, "spread": 0.16, "knock": 5, "text": "Six pellets that fan out. Launches targets.", "rarity": 1, "up": {"pellets": 8}},
	"hmg": {"name": "Heavy MG", "type": "AIM", "cost": 1, "dmg": [3, 3], "shots": 5, "range": FULL_RANGE, "gun": "mg", "bounce": 0, "sway": 0.06, "spread": 0.07, "text": "Five rounds of spray. Shreds wood.", "rarity": 2, "up": {"shots": 7}},
	"frag": {"name": "Frag Grenade", "type": "ARC", "cost": 1, "radius": 36, "dmg": 11, "fuse": 150, "bounce": true, "wind": 1.0, "text": "Bounces. 2.5s fuse.", "rarity": 0, "up": {"dmg": 14, "radius": 42}},
	"clusterfrag": {"name": "Cluster Frag", "type": "ARC", "cost": 2, "radius": 30, "dmg": 9, "fuse": 120, "bounce": true, "wind": 1.0, "cluster": 3, "text": "Bursts into three bouncing bomblets.", "rarity": 2, "up": {"cluster": 5}},
	"mortar": {"name": "Mortar Shell", "type": "ARC", "cost": 2, "radius": 50, "dmg": 15, "wind": 1.6, "text": "Explodes on impact. Heavy wind drift.", "rarity": 1, "up": {"dmg": 19, "radius": 58}},
	"smoke": {"name": "Smoke Can", "type": "ARC", "cost": 1, "smoke": true, "srad": 64.0, "sturns": 2, "wind": 1.0, "text": "Enemies cannot see through it.", "rarity": 1, "up": {"srad": 92.0, "sturns": 3}},
	"beacon": {"name": "Airstrike Beacon", "type": "ARC", "cost": 3, "beacon": true, "wind": 0.6, "text": "Bombs hit around it at the start of the enemy phase.", "bombs": 3, "rarity": 2, "up": {"bombs": 5}},
	"bazooka": {"name": "Bazooka", "type": "LINE", "cost": 2, "radius": 34, "dmg": 13, "speed": 10.0, "text": "Straight rocket. Big knockback.", "rarity": 1, "up": {"dmg": 17, "radius": 40}},
	"rocket": {"name": "Rocket Pod", "type": "LINE", "cost": 2, "radius": 24, "dmg": 8, "speed": 11.0, "count": 3, "text": "Three rockets in a spread.", "rarity": 2, "up": {"count": 4}},
	"grapple": {"name": "Grapple Hook", "type": "LINE", "cost": 1, "grapple": true, "range": 280, "text": "Zip onto a ledge or roof in reach.", "rarity": 1, "up": {"range": 400}},
	"jumppack": {"name": "Jump Pack", "type": "LINE", "cost": 1, "jump": true, "jpow": 1.0, "text": "Launch yourself in an arc. Lands soft. Counts as a push.", "rarity": 1, "up": {"jpow": 1.3}},
	"knife": {"name": "Knife", "type": "MELEE", "cost": 1, "dmg": [8, 10], "range": 38, "knock": 6, "text": "Never misses. Kicks them away.", "rarity": 0, "up": {"dmg": [11, 13]}},
	"medkit": {"name": "Field Dressing", "type": "ALLY", "cost": 1, "heal": 9, "range": 110, "text": "Patch up a squadmate.", "rarity": 0, "up": {"heal": 13}},
	"stim": {"name": "Stim Shot", "type": "ALLY", "cost": 0, "energy": 1, "range": 110, "text": "+1 energy to a squadmate. Costs them 3 HP.", "rarity": 1, "up": {"range": 200}},
	"digin": {"name": "Dig In", "type": "SELF", "cost": 1, "armor": 6, "text": "Armor until your next turn.", "rarity": 0, "up": {"armor": 10}},
	"sprint": {"name": "Sprint", "type": "SELF", "cost": 1, "move": 130, "text": "Extra movement this turn.", "rarity": 0, "up": {"move": 190}},
	"dash": {"name": "Dash", "type": "SELF", "cost": 0, "move": 80, "text": "A quick burst of movement.", "rarity": 0, "up": {"move": 120}},
	"overwatch": {"name": "Overwatch", "type": "SELF", "cost": 1, "overwatch": true, "ow": 1, "text": "Fire at the first enemies that move into view.", "rarity": 1, "up": {"ow": 2}},
	"adrenal": {"name": "Adrenaline Spike", "type": "SELF", "cost": 0, "adrenal": 50, "selfdmg": 4, "text": "Hurt yourself to get angry.", "rarity": 1, "up": {"selfdmg": 2}},
	"rally": {"name": "Rally Cry", "type": "SELF", "cost": 1, "rally": 70, "range": 220, "text": "Squad in range: extra movement and 10 adrenaline.", "rarity": 1, "up": {"rally": 110}},
	# overdrives: unlocked by full adrenaline, free, single use
	"ricochet": {"name": "Ricochet Round", "type": "AIM", "cost": 0, "od": true, "dmg": [16, 20], "range": FULL_RANGE, "gun": "sniper", "bounce": 5, "sway": 0.0, "pierce": true, "chip": 5, "text": "Five bounces. Pierces every body it meets.", "rarity": 5},
	"surge": {"name": "Adrenal Surge", "type": "SELF", "cost": 0, "od": true, "surge": true, "range": 240, "text": "Squad within 240px: heal 10, +1 energy, +80 move.", "rarity": 5},
	"cluster": {"name": "Cluster Bomb", "type": "ARC", "cost": 0, "od": true, "radius": 40, "dmg": 12, "fuse": 110, "bounce": true, "wind": 1.0, "cluster": 5, "text": "Bursts into five bouncing bomblets.", "rarity": 5},
	"rush": {"name": "Bull Rush", "type": "LINE", "cost": 0, "od": true, "rush": true, "text": "Launch yourself. Everyone you hit goes flying.", "rarity": 5},
}
const OD := {"moss": "ricochet", "hex": "surge", "vee": "cluster", "rook": "rush"}
const SHOP_PRICE := [45, 70, 100]

const SQUAD_DEFS := [
	{"key": "moss", "name": "MOSS", "cls": "Marksman", "hp": 22, "dodge": 10, "spd": 180,
	 "deck": ["snipe", "snipe", "rifle", "rifle", "pistol", "overwatch", "digin", "dash"],
	 "pool": ["snipe", "rifle", "pistol", "burst", "overwatch", "digin", "dash", "grapple", "hmg", "adrenal"],
	 "trait": ["Eagle Eye", "Headshots deal 2x damage instead of 1.5x."], "bio": "Former game warden. Counts every round twice."},
	{"key": "hex", "name": "HEX", "cls": "Field Medic", "hp": 24, "dodge": 14, "spd": 210,
	 "deck": ["medkit", "medkit", "stim", "pistol", "pistol", "smoke", "sprint", "frag"],
	 "pool": ["medkit", "stim", "smoke", "pistol", "sprint", "rally", "frag", "adrenal", "digin", "shotgun"],
	 "trait": ["Bedside Manner", "Heals restore +3 HP."], "bio": "Patched up three wars. Still hates the sight of blood."},
	{"key": "vee", "name": "VEE", "cls": "Demolitions", "hp": 27, "dodge": 6, "spd": 185,
	 "deck": ["frag", "frag", "bazooka", "bazooka", "mortar", "pistol", "jumppack", "sprint"],
	 "pool": ["frag", "mortar", "bazooka", "rocket", "clusterfrag", "beacon", "jumppack", "shotgun", "smoke"],
	 "trait": ["Pyromaniac", "Explosions deal +3 damage. Her own blasts hurt her for 40%."], "bio": "Measures distance in fuse-seconds."},
	{"key": "rook", "name": "ROOK", "cls": "Vanguard", "hp": 32, "dodge": 8, "spd": 200,
	 "deck": ["rifle", "rifle", "rifle", "burst", "sprint", "knife", "frag", "grapple"],
	 "pool": ["rifle", "burst", "shotgun", "hmg", "knife", "digin", "grapple", "sprint", "rally", "adrenal"],
	 "trait": ["Thick Skull", "Takes half damage from falls, slams and crushing debris."], "bio": "First through every door. Usually the wrong one."},
]

# Ability unlocks offered on level-up, four per soldier.
const PERKS := {
	"moss": [
		{"id": "steady", "name": "Steady Hands", "text": "All of Moss's sway is halved."},
		{"id": "trick", "name": "Trick Shot", "text": "+1 ricochet on every AIM card."},
		{"id": "doubletap", "name": "Double Tap", "text": "The first AIM card each turn costs 1 less."},
		{"id": "sentinel", "name": "Sentinel", "text": "Overwatch fires twice."},
	],
	"hex": [
		{"id": "triage", "name": "Triage", "text": "Heals restore +4 more HP."},
		{"id": "pumpup", "name": "Pump Up", "text": "Anyone Hex heals gains 20 adrenaline."},
		{"id": "fieldkit", "name": "Field Kit", "text": "Hex draws 1 extra card each turn."},
		{"id": "smokedoc", "name": "Smoke Doctor", "text": "Squadmates inside smoke heal 3 each enemy phase."},
	],
	"vee": [
		{"id": "bigboom", "name": "Bigger Booms", "text": "Vee's blasts are 20% bigger."},
		{"id": "blastproof", "name": "Blast Proof", "text": "Vee takes no damage from her own blasts."},
		{"id": "shortfuse", "name": "Short Fuse", "text": "Vee's grenade fuses are halved and deal +2."},
		{"id": "chain", "name": "Chain Reaction", "text": "Barrels and fuel tanks Vee sets off hit twice as hard."},
	],
	"rook": [
		{"id": "bulldozer", "name": "Bulldozer", "text": "Bodies Rook launches deal double collision damage."},
		{"id": "ironhide", "name": "Iron Hide", "text": "Rook starts every turn with 3 armor."},
		{"id": "secondwind", "name": "Second Wind", "text": "Once per mission, survive a killing blow at 1 HP."},
		{"id": "charge", "name": "Charge!", "text": "+60 movement every turn."},
	],
}

const STAT_BOOSTS := [
	{"id": "hp", "name": "Tough As Nails", "text": "+5 max HP and heal 5."},
	{"id": "move", "name": "Fleet Footed", "text": "+25 movement every turn."},
	{"id": "dodge", "name": "Slippery", "text": "+6 dodge. Enemy shots drift wider."},
	{"id": "hand", "name": "Quick Draw", "text": "+1 card in hand each turn."},
	{"id": "upgrade", "name": "Field Mod", "text": "Upgrade a random card in this deck."},
	{"id": "energy", "name": "Second Breath", "text": "+1 energy on the first round of every mission."},
]

const GEAR := [
	{"id": "boots", "icon": "ic_boot", "name": "Steel-Toe Boots", "text": "Squad takes half fall and slam damage.", "price": 90},
	{"id": "jammer", "icon": "ic_radio", "name": "Radio Jammer", "text": "Radiomen need 4 rounds to call backup, not 3.", "price": 110},
	{"id": "rations", "icon": "ic_heart", "name": "Combat Rations", "text": "Every wave clear heals the squad 4 HP.", "price": 90},
	{"id": "laser", "icon": "ic_up", "name": "Laser Sights", "text": "Every gun's aim laser reaches one step further. Sway -30%.", "price": 100},
	{"id": "charm", "icon": "ic_star", "name": "Lucky Charm", "text": "The first soldier to die each mission lives at 1 HP.", "price": 140},
	{"id": "bandolier", "icon": "ic_bolt", "name": "Bandolier", "text": "+1 energy for everyone on round 1.", "price": 100},
	{"id": "dogtags", "icon": "ic_skull", "name": "Spare Dog Tags", "text": "Kills give 50% more XP.", "price": 80},
	{"id": "stimpack", "icon": "ic_flame", "name": "Adrenal Pump", "text": "Adrenaline builds 50% faster.", "price": 90},
]

const XP_LEVELS := [0, 14, 34, 60, 92, 130, 175, 230]

const ETYPES := {
	"grunt": {"name": "Jackal Rifleman", "hp": 12, "dmg": [3, 5], "range": 460, "speed": 120, "prefer": 240, "nade": 0.35, "score": 100, "w": 16, "h": 34, "note": "Advances, vaults low walls, and lobs a grenade when it has no shot."},
	"shield": {"name": "Riot Jackal", "hp": 16, "dmg": [3, 4], "range": 340, "speed": 95, "prefer": 140, "shield": true, "score": 150, "w": 18, "h": 34, "note": "Shield soaks 75% of bullets from the front. Ricochet behind it, or blow it up."},
	"nade": {"name": "Jackal Bomber", "hp": 10, "arc": true, "dmg": 9, "radius": 32, "range": 480, "speed": 100, "prefer": 380, "score": 150, "w": 16, "h": 34, "note": "Lobs grenades over cover. Aim tightens as alert rises."},
	"brute": {"name": "Jackal Brute", "hp": 20, "acc": 85, "melee": true, "smash": true, "dmg": [9, 12], "speed": 190, "score": 200, "w": 22, "h": 44, "note": "Charges 190px and smashes through walls. Its machete sends you flying."},
	"mg": {"name": "MG Nest", "hp": 24, "dmg": [2, 3], "shots": 4, "range": 520, "static": true, "heavy": true, "score": 250, "w": 28, "h": 24, "note": "Static. Four rounds a turn. Too heavy to launch."},
	"radio": {"name": "Jackal Radioman", "hp": 10, "dmg": [2, 3], "range": 380, "speed": 60, "prefer": 520, "radio": true, "score": 200, "w": 16, "h": 34, "note": "Calls in paratroopers when his timer hits zero. Kill him to stop it."},
	"engineer": {"name": "Jackal Engineer", "hp": 12, "dmg": [2, 3], "range": 360, "speed": 80, "prefer": 320, "builds": true, "score": 150, "w": 16, "h": 34, "note": "Builds concrete walls for the Jackal line."},
	"sapper": {"name": "Jackal Sapper", "hp": 11, "speed": 150, "sapper": true, "score": 175, "w": 16, "h": 34, "note": "Runs in and plants a charge that blows next turn. Shoot the charge to defuse it."},
	"mortarcrew": {"name": "Mortar Crew", "hp": 18, "arc": true, "heavyArc": true, "dmg": 12, "radius": 46, "range": 900, "speed": 0, "score": 250, "w": 18, "h": 34, "note": "Shells your cover from long range. Sits still. Something is hanging over it."},
	"boss": {"name": "IRON BOAR", "hp": 150, "dmg": [3, 4], "shots": 4, "range": 660, "heavy": true, "score": 3000, "w": 120, "h": 64, "note": "Armored tank: shrugs off 60% of damage until its armor cracks. Crushing debris cracks it at once."},
}

const POW_NAMES := ["Sgt. Bramble", "Pvt. Okonkwo", "Cpl. Teller", "Lt. Varga", "Pvt. Ishikawa", "Sgt. Duarte"]
const BARKS := {
	"od": ["That tickled. My turn.", "Now I am ANGRY.", "Bring it!", "You done? Good."],
	"kill": ["Scratch one.", "Next!", "Stay down.", "Timber!"],
	"lvl": ["Getting the hang of this.", "Feeling sharp!", "Oh yeah!", "Lock and load!"],
}
const SCREAMS := ["AAAGH!", "NOOO!", "URK!", "GYAAH!"]

# ---------------------------------------------------------------- level segments
# Each segment is laid out in its own local x space (0 = segment start). A mission strings
# segments together. Structures: over, tower, boulder, bunker, ledge.
const SEGMENTS := {
	"start": {"w": 460, "sandbags": [420], "structs": [], "pits": [], "spawns": []},
	"towers": {"w": 840, "sandbags": [600], "pits": [[700, 776]],
		"structs": [{"t": "over", "px": 136, "x0": 136, "x1": 244, "h": 70}, {"t": "tower", "x": 380, "h": 96}],
		"spawns": [["barrel", 124], ["grunt", 200, {"top": 1}], ["grunt", 380, {"hold": 1}], ["nade", 470]]},
	"boulder": {"w": 700, "sandbags": [710], "pits": [],
		"structs": [{"t": "boulder", "col": 150, "colH": 150, "bx": 232, "rope": 22, "r": 22}],
		"spawns": [["pow", 20], ["grunt", 162, {"hold": 1}], ["mg", 236], ["shield", 310], ["brute", 360], ["nade", 420], ["radio", 490]]},
	"bunker": {"w": 700, "sandbags": [], "pits": [[620, 696]],
		"structs": [{"t": "bunker", "x": 140, "w": 84, "h": 48}, {"t": "ledge", "x": 360, "w": 96, "dy": 96, "post": 440}],
		"spawns": [["barrel", 96], ["barrel", 112], ["mg", 182], ["grunt", 182, {"hold": 1, "inside": 1}], ["fuel", 252], ["grunt", 396], ["engineer", 420], ["brute", 480], ["radio", 560]]},
	"overhang": {"w": 800, "sandbags": [], "pits": [],
		"structs": [{"t": "over", "px": 224, "x0": 224, "x1": 400, "h": 76}, {"t": "tower", "x": 540, "h": 100}, {"t": "ledge", "x": 720, "w": 100, "dy": 112, "post": 766}],
		"spawns": [["pow", 100], ["shield", 310, {"hold": 1}], ["shield", 380], ["sapper", 460], ["brute", 490], ["nade", 540, {"hold": 1}], ["radio", 640]]},
	"mortar": {"w": 800, "sandbags": [110], "pits": [[760, 836]],
		"structs": [{"t": "bunker", "x": 330, "w": 84, "h": 48}, {"t": "boulder", "col": 430, "colH": 160, "bx": 500, "rope": 24, "r": 24}],
		"spawns": [["engineer", 140], ["fuel", 190], ["grunt", 260], ["mg", 372], ["grunt", 372, {"hold": 1, "inside": 1}], ["mortarcrew", 500, {"hold": 1}], ["barrel", 540], ["nade", 590], ["radio", 670]]},
	"gauntlet": {"w": 900, "sandbags": [210, 1020 - 900], "pits": [[780, 848]],
		"structs": [{"t": "over", "px": 436, "x0": 256, "x1": 444, "h": 80}, {"t": "tower", "x": 570, "h": 90}],
		"spawns": [["pow", 120], ["brute", 280], ["sapper", 320], ["shield", 350], ["brute", 410], ["grunt", 570, {"hold": 1}], ["radio", 660]]},
	"arena": {"w": 1200, "sandbags": [120, 360], "pits": [], "flat": true,
		"structs": [{"t": "tower", "x": 580, "h": 96}, {"t": "tower", "x": 760, "h": 110}, {"t": "boulder", "col": 850, "colH": 236, "bx": 960, "rope": 18, "r": 32}],
		"spawns": [["grunt", 580, {"hold": 1}], ["grunt", 760, {"hold": 1}], ["boss", 960]]},
}

const MISSIONS := [
	{"name": "THE JACKAL LINE", "theme": "dusk", "segments": ["start", "towers", "boulder", "bunker", "arena"],
	 "boss_hp": 120, "plate": 36, "hp_mul": 1.0, "brief": "Punch through the Jackal forward line and scrap the IRON BOAR guarding the road east."},
	{"name": "RIVER CROSSING", "theme": "jungle", "segments": ["start", "overhang", "mortar", "towers", "arena"],
	 "boss_hp": 160, "plate": 46, "hp_mul": 1.15, "brief": "The Jackals dug a mortar line along the river. Their second BOAR is waiting at the ford."},
	{"name": "IRON HARBOR", "theme": "night", "segments": ["start", "gauntlet", "bunker", "overhang", "mortar", "arena"],
	 "boss_hp": 210, "plate": 60, "hp_mul": 1.3, "brief": "Night raid on the harbor. Take down the flagship BOAR and the Jackal army goes home."},
]

const THEMES := {
	"dusk": {"water": [Color("14485a"), Color("2f8aa0")], "tint": Color(1, 1, 1), "grass": Color("7cb042")},
	"jungle": {"water": [Color("0e3a34"), Color("2a8a6a")], "tint": Color(0.92, 1.02, 0.95), "grass": Color("4ca83a")},
	"night": {"water": [Color("0a1830"), Color("24508a")], "tint": Color(0.62, 0.66, 0.86), "grass": Color("4a7a52")},
}

func base_tier(key: String) -> int:
	return int(CARDS[key].rarity)

func tier_of(inst) -> int:
	## A card instance's rarity tier. Old saves used a bool "up" for one tier-up.
	if inst is String:
		return base_tier(inst)
	if inst.get("od", false) or CARDS[inst.key].get("od", false):
		return OD_TIER
	if inst.has("tier"):
		return int(inst.tier)
	return base_tier(inst.key) + (1 if inst.get("up", false) else 0)

func card(inst) -> Dictionary:
	## Resolved stats for a card instance {key, tier}. Each tier above the card's base
	## rarity improves its effect; the energy cost never changes with rarity.
	var key: String = inst if inst is String else inst.key
	var base: Dictionary = CARDS[key].duplicate(true)
	var tier := tier_of(inst)
	var steps := tier - int(base.rarity) if tier != OD_TIER else 0
	if steps >= 1 and base.has("up"):
		for k in base.up:
			if k != "cost":
				base[k] = base.up[k]
	var extra := steps - (1 if base.has("up") else 0)
	for i in maxi(0, extra):
		if base.has("dmg"):
			if base.dmg is Array:
				base.dmg = [base.dmg[0] + 2, base.dmg[1] + 2]
			else:
				base.dmg += 3
		for k in [["heal", 3], ["armor", 3], ["move", 40], ["rally", 30], ["adrenal", 10]]:
			if base.has(k[0]):
				base[k[0]] += k[1]
		if base.has("radius"):
			base.radius += 4
		if base.has("srad"):
			base.srad += 14.0
		if base.get("grapple", false):
			base.range += 60
		if base.has("jpow"):
			base.jpow += 0.1
		if base.has("energy") and key == "stim":
			base.range += 40
	if tier >= TIER_MAX:
		for k in ["shots", "pellets", "count", "cluster", "bombs", "ow"]:
			if base.has(k):
				base[k] += 1
		if base.type == "AIM":
			base.bounce = base.get("bounce", 0) + 1
	base["key"] = key
	base["tier"] = tier
	return base

func tier_color(t: int) -> Color:
	return RARITY[clampi(t, 0, RARITY.size() - 1)].c

func tier_name(t: int) -> String:
	return RARITY[clampi(t, 0, RARITY.size() - 1)].name

func laser_len(c: Dictionary, step_bonus := 0, pct := 0.0) -> float:
	## How much of the bullet path the aim laser reveals for this card.
	var g: Dictionary = GUNS.get(c.get("gun", "rifle"), GUNS.rifle)
	var i: int = clampi(int(g.laser) + step_bonus, 0, LASER_LEN.size() - 1)
	var L: float = LASER_LEN[i]
	return L if L > 9999.0 else L * (1.0 + pct)

func stat_line(c: Dictionary) -> String:
	if c.type == "AIM":
		return "DMG %d-%d%s%s BNC %d" % [c.dmg[0], c.dmg[1], (" x%d" % c.shots) if c.has("shots") else "", (" x%d" % c.pellets) if c.has("pellets") else "", c.get("bounce", 0)]
	if c.has("radius"):
		return "DMG %d%s BLAST %d" % [c.dmg, (" x%d" % c.count) if c.has("count") else "", c.radius]
	if c.has("dmg"):
		return "DMG %d-%d" % [c.dmg[0], c.dmg[1]]
	if c.has("heal"):
		return "HEAL %d  RNG %d" % [c.heal, c.range]
	if c.get("grapple", false):
		return "RNG %d" % c.range
	if c.get("smoke", false):
		return "RADIUS %d  %d RNDS" % [int(c.srad), c.sturns]
	if c.get("beacon", false):
		return "%d BOMBS  DMG 15" % c.bombs
	if c.get("overwatch", false):
		return "%d SHOT%s" % [c.ow, "S" if c.ow > 1 else ""]
	if c.has("armor"):
		return "ARMOR +%d" % c.armor
	if c.has("move"):
		return "MOVE +%d" % c.move
	if c.has("energy"):
		return "ENERGY +1"
	if c.has("adrenal"):
		return "ADR +%d  HP -%d" % [c.adrenal, c.selfdmg]
	if c.has("rally"):
		return "MOVE +%d  RNG %d" % [c.rally, c.range]
	if c.get("rush", false):
		return "LAUNCH  SLAM 14"
	if c.get("jump", false):
		return "LAUNCH x%.1f  SOFT" % c.jpow
	if c.get("surge", false):
		return "SQUAD BOOST"
	return ""

func is_attack(c: Dictionary) -> bool:
	return c.type == "AIM" or c.type == "MELEE" or (c.type == "ARC" and not c.get("smoke", false) and not c.get("beacon", false)) or (c.type == "LINE" and not c.get("grapple", false) and not c.get("rush", false) and not c.get("jump", false))

func squad_def(key: String) -> Dictionary:
	for d in SQUAD_DEFS:
		if d.key == key:
			return d
	return {}

func perk(key: String, id: String) -> Dictionary:
	for p in PERKS.get(key, []):
		if p.id == id:
			return p
	return {}

func gear(id: String) -> Dictionary:
	for g in GEAR:
		if g.id == id:
			return g
	return {}

func card_price(key: String, tier := -1) -> int:
	var t: int = base_tier(key) if tier < 0 else tier
	return SHOP_PRICE[clampi(base_tier(key), 0, 2)] + maxi(0, t - base_tier(key)) * 40

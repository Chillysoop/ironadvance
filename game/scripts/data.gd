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

# rarity: 0 common, 1 uncommon, 2 rare, 3 overdrive (never offered)
# "up" holds the changes an upgraded (+) copy gets.
const CARDS := {
	"rifle": {"name": "Rifle Shot", "type": "AIM", "cost": 1, "dmg": [6, 8], "range": 720, "bounce": 1, "sway": 0.035, "text": "Ricochets once.", "rarity": 0, "up": {"dmg": [8, 10]}},
	"burst": {"name": "Burst Fire", "type": "AIM", "cost": 2, "dmg": [4, 5], "shots": 3, "range": 620, "bounce": 1, "sway": 0.05, "spread": 0.06, "text": "Three rounds. Recoil spreads them.", "rarity": 1, "up": {"shots": 4}},
	"pistol": {"name": "Sidearm", "type": "AIM", "cost": 1, "dmg": [4, 5], "range": 520, "bounce": 2, "sway": 0.022, "text": "Steady. Ricochets twice.", "rarity": 0, "up": {"dmg": [5, 7], "bounce": 3}},
	"snipe": {"name": "Long Shot", "type": "AIM", "cost": 2, "dmg": [14, 18], "range": 1200, "bounce": 1, "sway": 0.007, "pierce": true, "still": true, "chip": 5, "text": "Pierces bodies. Sways 4x if you moved.", "rarity": 2, "up": {"dmg": [17, 22]}},
	"shotgun": {"name": "Shotgun", "type": "AIM", "cost": 1, "dmg": [3, 4], "pellets": 6, "range": 170, "bounce": 0, "sway": 0.02, "spread": 0.16, "knock": 5, "text": "Six pellets. Launches targets up close.", "rarity": 1, "up": {"pellets": 8}},
	"hmg": {"name": "Heavy MG", "type": "AIM", "cost": 1, "dmg": [3, 3], "shots": 5, "range": 660, "bounce": 0, "sway": 0.06, "spread": 0.07, "text": "Five rounds of spray. Shreds wood.", "rarity": 2, "up": {"shots": 7}},
	"frag": {"name": "Frag Grenade", "type": "ARC", "cost": 1, "radius": 36, "dmg": 11, "fuse": 150, "bounce": true, "wind": 1.0, "text": "Bounces. 2.5s fuse.", "rarity": 0, "up": {"dmg": 14, "radius": 42}},
	"clusterfrag": {"name": "Cluster Frag", "type": "ARC", "cost": 2, "radius": 30, "dmg": 9, "fuse": 120, "bounce": true, "wind": 1.0, "cluster": 3, "text": "Bursts into three bouncing bomblets.", "rarity": 2, "up": {"cluster": 5}},
	"mortar": {"name": "Mortar Shell", "type": "ARC", "cost": 2, "radius": 50, "dmg": 15, "wind": 1.6, "text": "Explodes on impact. Heavy wind drift.", "rarity": 1, "up": {"dmg": 19, "radius": 58}},
	"smoke": {"name": "Smoke Can", "type": "ARC", "cost": 1, "smoke": true, "wind": 1.0, "text": "Enemies cannot see through it for 2 rounds.", "rarity": 1, "up": {"cost": 0}},
	"beacon": {"name": "Airstrike Beacon", "type": "ARC", "cost": 3, "beacon": true, "wind": 0.6, "text": "Three bombs hit around it at the start of the enemy phase.", "rarity": 2, "up": {"cost": 2}},
	"bazooka": {"name": "Bazooka", "type": "LINE", "cost": 2, "radius": 34, "dmg": 13, "speed": 10.0, "text": "Straight rocket. Big knockback.", "rarity": 1, "up": {"dmg": 17, "radius": 40}},
	"rocket": {"name": "Rocket Pod", "type": "LINE", "cost": 2, "radius": 24, "dmg": 8, "speed": 11.0, "count": 3, "text": "Three rockets in a spread.", "rarity": 2, "up": {"count": 4}},
	"grapple": {"name": "Grapple Hook", "type": "LINE", "cost": 1, "grapple": true, "range": 280, "text": "Zip onto a ledge or roof up to 280px away.", "rarity": 1, "up": {"cost": 0}},
	"jumppack": {"name": "Jump Pack", "type": "LINE", "cost": 1, "jump": true, "text": "Launch yourself in an arc. Lands soft. Counts as a push.", "rarity": 1, "up": {"cost": 0}},
	"knife": {"name": "Knife", "type": "MELEE", "cost": 1, "dmg": [8, 10], "range": 38, "knock": 6, "text": "Never misses. Kicks them away.", "rarity": 0, "up": {"dmg": [11, 13]}},
	"medkit": {"name": "Field Dressing", "type": "ALLY", "cost": 1, "heal": 9, "range": 110, "text": "Heal 9 HP.", "rarity": 0, "up": {"heal": 13}},
	"stim": {"name": "Stim Shot", "type": "ALLY", "cost": 0, "energy": 1, "range": 110, "text": "+1 energy to a squadmate. Costs them 3 HP.", "rarity": 1, "up": {"range": 200}},
	"digin": {"name": "Dig In", "type": "SELF", "cost": 1, "armor": 6, "text": "Gain 6 armor until your next turn.", "rarity": 0, "up": {"armor": 10}},
	"sprint": {"name": "Sprint", "type": "SELF", "cost": 1, "move": 130, "text": "+130px of movement this turn.", "rarity": 0, "up": {"move": 190}},
	"dash": {"name": "Dash", "type": "SELF", "cost": 0, "move": 80, "text": "+80px of movement. Free.", "rarity": 0, "up": {"move": 120}},
	"overwatch": {"name": "Overwatch", "type": "SELF", "cost": 1, "overwatch": true, "text": "Fire at the first enemy that moves into view.", "rarity": 1, "up": {"cost": 0}},
	"adrenal": {"name": "Adrenaline Spike", "type": "SELF", "cost": 0, "adrenal": 50, "selfdmg": 4, "text": "Lose 4 HP, gain 50 adrenaline.", "rarity": 1, "up": {"selfdmg": 2}},
	"rally": {"name": "Rally Cry", "type": "SELF", "cost": 1, "rally": 70, "range": 220, "text": "Squad within 220px: +70 move and 10 adrenaline.", "rarity": 1, "up": {"rally": 110}},
	# overdrives: unlocked by full adrenaline, free, single use
	"ricochet": {"name": "Ricochet Round", "type": "AIM", "cost": 0, "od": true, "dmg": [16, 20], "range": 1800, "bounce": 5, "sway": 0.0, "pierce": true, "chip": 5, "text": "Five bounces. Pierces every body it meets.", "rarity": 3},
	"surge": {"name": "Adrenal Surge", "type": "SELF", "cost": 0, "od": true, "surge": true, "range": 240, "text": "Squad within 240px: heal 10, +1 energy, +80 move.", "rarity": 3},
	"cluster": {"name": "Cluster Bomb", "type": "ARC", "cost": 0, "od": true, "radius": 40, "dmg": 12, "fuse": 110, "bounce": true, "wind": 1.0, "cluster": 5, "text": "Bursts into five bouncing bomblets.", "rarity": 3},
	"rush": {"name": "Bull Rush", "type": "LINE", "cost": 0, "od": true, "rush": true, "text": "Launch yourself. Everyone you hit goes flying.", "rarity": 3},
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
	{"id": "laser", "icon": "ic_up", "name": "Laser Sights", "text": "All AIM cards sway 30% less.", "price": 100},
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
# segments together. Structures: over, tower, boulder, bunker, ledge, fort, bridge, docks, crane.
# "ground" reshapes the terrain under a segment: dh > 0 raises a ridge, dh < 0 digs a trench,
# ramp 0 makes a cliff (it gets a ladder). Spawn option "up" places a unit that many px above
# the base ground, for fort floors and girders.
#   fort:   x, w, floors, fh (floor height). Wooden walls and floors, concrete roof, inner ladders.
#   bridge: x0, x1 over open water, posts. Half-destroy any post and the whole deck drops.
#   docks:  x0, x1 over open water, a plank pier on stone pilings every `pile` px.
#   crane:  mast at x (h tall), jib reaching to `jib`, container (cw x ch) on a `rope` at `hook`.
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
	# Worms-style dug-in line: a foxhole for you, a ridge for them with a fuel barrel by the rifleman
# on top, and their own trench behind it
	"trenches": {"w": 800, "sandbags": [262, 604], "pits": [],
		"ground": [{"x0": 150, "x1": 250, "dh": -26, "ramp": 18}, {"x0": 400, "x1": 580, "dh": 36, "ramp": 70}, {"x0": 640, "x1": 730, "dh": -20, "ramp": 18}],
		"structs": [],
		"spawns": [["grunt", 300], ["nade", 450], ["barrel", 500], ["grunt", 530, {"hold": 1}], ["grunt", 690], ["shield", 760]]},
	# SteamWorld Heist-style outpost: three floors of Jackals, a POW on the top floor
	"fort": {"w": 760, "sandbags": [190], "pits": [],
		"structs": [{"t": "fort", "x": 300, "w": 136, "floors": 3, "fh": 54}],
		"spawns": [["grunt", 240], ["barrel", 324], ["grunt", 370, {"hold": 1, "up": 10}], ["nade", 330, {"hold": 1, "up": 74}],
			["pow", 340, {"up": 128}], ["grunt", 405, {"hold": 1, "up": 128}], ["radio", 380, {"hold": 1, "up": 182}], ["brute", 560]]},
	# a gully with a plank bridge: drop it while they are on it
	"gully": {"w": 720, "sandbags": [520], "pits": [],
		"structs": [{"t": "bridge", "x0": 240, "x1": 440, "posts": [306, 374]}],
		"spawns": [["pow", 110], ["grunt", 340, {"hold": 1}], ["shield", 400], ["barrel", 470], ["nade", 560, {"hold": 1}], ["grunt", 620], ["radio", 670]]},
	# a raised jungle ridge sown with mines
	"ridge": {"w": 820, "sandbags": [], "pits": [],
		"ground": [{"x0": 260, "x1": 600, "dh": 46, "ramp": 0}, {"x0": 600, "x1": 640, "dh": 46, "ramp": 90}],
		"structs": [{"t": "tower", "x": 470, "h": 70}],
		"spawns": [["mine", 140], ["mine", 196], ["grunt", 300, {"hold": 1}], ["mine", 352], ["nade", 410, {"hold": 1}], ["pow", 440], ["grunt", 470, {"hold": 1}], ["mine", 530], ["nade", 600], ["mine", 690], ["sapper", 720], ["radio", 780]]},
	# the long river bridge, mortar fire from the far bank
	"river": {"w": 960, "sandbags": [590], "pits": [],
		"structs": [{"t": "bridge", "x0": 180, "x1": 500, "posts": [260, 340, 420]}, {"t": "ledge", "x": 680, "w": 96, "dy": 92, "post": 760}],
		"spawns": [["grunt", 300, {"hold": 1}], ["shield", 380, {"hold": 1}], ["grunt", 460], ["fuel", 540], ["mine", 620], ["brute", 650], ["nade", 720, {"hold": 1, "up": 120}], ["mortarcrew", 860, {"hold": 1}], ["radio", 900]]},
	# harbor pier over open water: steel girders above, a crane container over the middle
	"docks": {"w": 1000, "sandbags": [], "pits": [],
		"structs": [{"t": "docks", "x0": 120, "x1": 880, "pile": 76}, {"t": "ledge", "x": 290, "w": 110, "dy": 76, "post": 392},
			{"t": "ledge", "x": 600, "w": 104, "dy": 96, "post": 696}, {"t": "crane", "x": 916, "h": 170, "jib": 470, "hook": 520, "rope": 46, "cw": 52, "ch": 26}],
		"spawns": [["barrel", 200], ["grunt", 340, {"hold": 1, "up": 100}], ["shield", 450], ["grunt", 520, {"hold": 1, "up": 10}], ["sapper", 560], ["nade", 650, {"hold": 1, "up": 120}],
			["barrel", 740], ["grunt", 800], ["radio", 950]]},
	# a two-floor warehouse with an ammo dump on the ground floor and a minefield out back
	"warehouse": {"w": 820, "sandbags": [170], "pits": [],
		"structs": [{"t": "fort", "x": 260, "w": 190, "floors": 2, "fh": 64}],
		"spawns": [["grunt", 210], ["mg", 300], ["fuel", 400], ["barrel", 420], ["nade", 320, {"hold": 1, "up": 84}], ["pow", 380, {"up": 84}], ["grunt", 420, {"hold": 1, "up": 84}],
			["grunt", 360, {"hold": 1, "up": 148}], ["mine", 520], ["mine", 580], ["brute", 600], ["mine", 650], ["engineer", 700], ["radio", 760]]},
	"arena": {"w": 1200, "sandbags": [120, 360], "pits": [], "flat": true,
		"structs": [{"t": "tower", "x": 580, "h": 96}, {"t": "tower", "x": 760, "h": 110}, {"t": "boulder", "col": 850, "colH": 236, "bx": 960, "rope": 18, "r": 32}],
		"spawns": [["grunt", 580, {"hold": 1}], ["grunt", 760, {"hold": 1}], ["boss", 960]]},
	# the harbor's boss arena: the flagship BOAR parks under a loaded crane
	"pier": {"w": 1200, "sandbags": [120, 360], "pits": [], "flat": true,
		"structs": [{"t": "tower", "x": 560, "h": 96}, {"t": "ledge", "x": 700, "w": 96, "dy": 100, "post": 780}, {"t": "crane", "x": 1080, "h": 230, "jib": 880, "hook": 960, "rope": 30, "cw": 72, "ch": 34}],
		"spawns": [["grunt", 560, {"hold": 1}], ["nade", 740, {"hold": 1, "up": 120}], ["mine", 640], ["mine", 840], ["boss", 960]]},
}

const MISSIONS := [
	{"name": "THE JACKAL LINE", "theme": "dusk", "segments": ["start", "trenches", "fort", "gully", "boulder", "arena"],
	 "boss_hp": 120, "plate": 36, "hp_mul": 1.0, "brief": "Clear the trenches, storm the outpost and cross the gully before the IRON BOAR closes the road east."},
	{"name": "RIVER CROSSING", "theme": "jungle", "segments": ["start", "ridge", "overhang", "river", "mortar", "arena"],
	 "boss_hp": 160, "plate": 46, "hp_mul": 1.15, "brief": "The ridge is mined and the river bridge is held. Their second BOAR is waiting at the ford."},
	{"name": "IRON HARBOR", "theme": "night", "segments": ["start", "docks", "warehouse", "gauntlet", "pier"],
	 "boss_hp": 210, "plate": 60, "hp_mul": 1.3, "brief": "Night raid on the harbor. Fight along the piers, gut the warehouse, and drop a crane load on the flagship BOAR."},
]

const THEMES := {
	"dusk": {"water": [Color("14485a"), Color("2f8aa0")], "tint": Color(1, 1, 1), "grass": Color("7cb042")},
	"jungle": {"water": [Color("0e3a34"), Color("2a8a6a")], "tint": Color(0.92, 1.02, 0.95), "grass": Color("4ca83a")},
	"night": {"water": [Color("0a1830"), Color("24508a")], "tint": Color(0.62, 0.66, 0.86), "grass": Color("4a7a52")},
}

func card(inst) -> Dictionary:
	## Resolved stats for a card instance {key, up}.
	var key: String = inst if inst is String else inst.key
	var base: Dictionary = CARDS[key].duplicate(true)
	if not (inst is String) and inst.get("up", false) and base.has("up"):
		for k in base.up:
			base[k] = base.up[k]
		base.name = base.name + "+"
	base["key"] = key
	return base

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
		return "RADIUS 64  2 RNDS"
	if c.get("beacon", false):
		return "3 BOMBS  DMG 15"
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
		return "LAUNCH  SAFE LANDING"
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

func card_price(key: String, up := false) -> int:
	var r: int = clampi(CARDS[key].rarity, 0, 2)
	return SHOP_PRICE[r] + (40 if up else 0)

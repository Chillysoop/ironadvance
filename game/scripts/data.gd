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
# Recoil (Soldat-style, kept light): heavy guns shove the shooter back a step. The aim
# preview shows a ghost of where they will land, so a kick off a roof is never a surprise.
const RECOIL := {"sniper": 1.7, "mg": 1.4, "rocket": 2.3}
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
	# every soldier carries Hop: it is handed out each turn and never sits in a deck
	"hop": {"name": "Hop", "type": "LINE", "cost": 1, "jump": true, "jpow": 0.62, "hop": true, "pool": false, "text": "Everyone has one. Jump a short gap or up a wall about head high. Uses the rest of your movement.", "rarity": 0},
	# every soldier starts with one Drill in the deck; once it's spent it waits for the next draw
	"drill": {"name": "Drill", "type": "LINE", "cost": 0, "drill": true, "reach": 0, "pool": false, "text": "Bore through any terrain toward the cursor. Uses movement as you go. Click to stop early.", "rarity": 0, "up": {"reach": 60}},
	"jumppack": {"name": "Jump Pack", "type": "LINE", "cost": 1, "jump": true, "jpow": 1.0, "text": "Launch yourself in an arc. Lands soft. Counts as a push.", "rarity": 1, "up": {"jpow": 1.3}},
	"knife": {"name": "Knife", "type": "MELEE", "cost": 1, "dmg": [8, 10], "range": 38, "knock": 6, "text": "Never misses. Kicks them away.", "rarity": 0, "up": {"dmg": [11, 13]}},
	"medkit": {"name": "Field Dressing", "type": "ALLY", "cost": 1, "heal": 9, "range": 110, "text": "Patch up a squadmate.", "rarity": 0, "up": {"heal": 13}},
	"stim": {"name": "Stim Shot", "type": "ALLY", "cost": 0, "energy": 1, "range": 110, "text": "+1 energy to a squadmate. Costs them 3 HP.", "rarity": 1, "up": {"range": 200}},
	"digin": {"name": "Dig In", "type": "SELF", "cost": 1, "armor": 6, "text": "Armor until your next turn.", "rarity": 0, "up": {"armor": 10}},
	# B1 sidearms: one is always in hand once per turn, outside the deck, like Hop
	"sa_pistol": {"name": "Holdout Pistol", "type": "AIM", "cost": 0, "dmg": [2, 3], "range": FULL_RANGE, "gun": "pistol", "bounce": 1, "sway": 0.022, "sidearm": true, "pool": false, "text": "SIDEARM: free once a turn. Ricochets once.", "rarity": 0},
	"sa_knife": {"name": "Combat Knife", "type": "MELEE", "cost": 0, "dmg": [5, 6], "range": 36, "knock": 4, "sidearm": true, "pool": false, "text": "SIDEARM: free once a turn. Never misses.", "rarity": 1},
	"sa_chainsaw": {"name": "Chainsaw", "type": "MELEE", "cost": 1, "dmg": [11, 13], "range": 40, "knock": 1.5, "sidearm": true, "pool": false, "text": "SIDEARM: once a turn. Chews in deep and barely knocks them back.", "rarity": 2},
	"sa_law": {"name": "LAW", "type": "LINE", "cost": 0, "radius": 34, "dmg": 14, "speed": 11.0, "sidearm": true, "law": true, "pool": false, "text": "SIDEARM: one free rocket. Comes back at the next camp.", "rarity": 2},
	# O2: the Rambo Bow, a fresh arrow every turn for whoever took it off the elite bowman
	"rambobow": {"name": "Rambo Bow", "type": "ARC", "cost": 1, "radius": 46, "dmg": 14, "wind": 0.4, "bow": true, "pool": false, "text": "An explosive arrow that bursts on impact. A fresh one every turn this level. Every Jackal hunts the archer.", "rarity": 3},
	# B6: the free card a soldier gets standing at a mounted M2
	"mounted": {"name": "Mounted M2", "type": "AIM", "cost": 0, "dmg": [3, 4], "shots": 6, "range": FULL_RANGE, "gun": "mg", "bounce": 0, "sway": 0.02, "spread": 0.05, "mounted": true, "pool": false, "text": "Free while you stand at the gun. Six heavy rounds, no kick. Once a turn.", "rarity": 2},
	"roll": {"name": "Combat Roll", "type": "LINE", "cost": 1, "roll": true, "dist": 150, "text": "Roll up to 150px without using movement. Fits through crawl-height gaps, and the next Jackal shot at you goes over your head.", "rarity": 0, "up": {"dist": 210}},
	"sprint": {"name": "Sprint", "type": "SELF", "cost": 1, "move": 130, "text": "Extra movement this turn.", "rarity": 0, "up": {"move": 190}},
	"dash": {"name": "Dash", "type": "SELF", "cost": 0, "move": 80, "text": "A quick burst of movement.", "rarity": 0, "up": {"move": 120}},
	"overwatch": {"name": "Overwatch", "type": "SELF", "cost": 1, "overwatch": true, "ow": 1, "text": "Fire at the first enemies that move into view.", "rarity": 1, "up": {"ow": 2}},
	"adrenal": {"name": "Adrenaline Spike", "type": "SELF", "cost": 0, "adrenal": 50, "selfdmg": 4, "text": "Hurt yourself to get angry.", "rarity": 1, "up": {"selfdmg": 2}},
	"rally": {"name": "Rally Cry", "type": "SELF", "cost": 1, "rally": 70, "range": 220, "text": "Squad in range: extra movement and 10 adrenaline.", "rarity": 1, "up": {"rally": 110}},
	"tagshot": {"name": "Tag Round", "type": "AIM", "cost": 0, "dmg": [1, 2], "range": FULL_RANGE, "gun": "rifle", "bounce": 1, "sway": 0.02, "mark": true, "text": "Marks what it hits. The next hit on a marked target crits.", "rarity": 1, "up": {"dmg": [3, 4], "bounce": 2}},
	"gasnade": {"name": "Gas Canister", "type": "ARC", "cost": 1, "gas": true, "srad": 56.0, "sturns": 3, "wind": 1.0, "text": "A toxic cloud that drifts with the wind. Fire or a blast inside it explodes.", "rarity": 1, "up": {"srad": 76.0, "sturns": 4}},
	# archetype cards (Phase 4)
	"bankshot": {"name": "Bank Shot", "type": "AIM", "cost": 1, "dmg": [4, 5], "range": FULL_RANGE, "gun": "pistol", "bounce": 3, "sway": 0.025, "bankdmg": 3, "text": "+3 damage for every bounce before it hits.", "rarity": 1, "up": {"bankdmg": 5}},
	"holdbreath": {"name": "Hold Breath", "type": "SELF", "cost": 1, "breath": 6, "text": "Your next AIM card has no sway and +6 damage.", "rarity": 1, "up": {"breath": 9}},
	"fanhammer": {"name": "Fan the Hammer", "type": "AIM", "cost": 1, "dmg": [3, 4], "shots": 3, "range": FULL_RANGE, "gun": "pistol", "bounce": 1, "sway": 0.03, "spread": 0.1, "text": "Three wild pistol shots.", "rarity": 1, "up": {"shots": 4}},
	"quickdraw": {"name": "Quickdraw", "type": "SELF", "cost": 0, "draw": 2, "text": "Draw 2 cards.", "rarity": 1, "up": {"draw": 3}},
	"hotshot": {"name": "Hot Shot", "type": "ALLY", "cost": 1, "adrshot": 40, "range": 140, "text": "A squadmate gains adrenaline.", "rarity": 1, "up": {"adrshot": 60}},
	"flashbang": {"name": "Flashbang", "type": "ARC", "cost": 1, "radius": 52, "dmg": 2, "fuse": 70, "bounce": true, "wind": 1.0, "flash": true, "text": "Stuns every Jackal in the blast. Barely hurts.", "rarity": 2, "up": {"radius": 66}},
	"dartpistol": {"name": "Dart Pistol", "type": "AIM", "cost": 1, "dmg": [2, 3], "range": FULL_RANGE, "gun": "pistol", "bounce": 1, "sway": 0.02, "toxic": true, "text": "Poisons what it hits: Toxic for 3 rounds.", "rarity": 1, "up": {"dmg": [4, 5]}},
	"defib": {"name": "Defib Paddles", "type": "MELEE", "cost": 1, "dmg": [4, 6], "range": 38, "knock": 3, "stun": true, "selfheal": 5, "text": "Stuns the target and heals you.", "rarity": 1, "up": {"selfheal": 8}},
	"rocketjump": {"name": "Rocket Jump", "type": "LINE", "cost": 1, "jump": true, "jpow": 1.25, "rjump": true, "text": "A blast at your feet launches you and hurts anyone beside you.", "rarity": 1, "up": {"jpow": 1.5}},
	"molotov": {"name": "Molotov", "type": "ARC", "cost": 1, "radius": 30, "dmg": 4, "wind": 1.0, "burnblast": true, "text": "Smashes on impact. Everything caught is Burning.", "rarity": 1, "up": {"radius": 40}},
	"shapedcharge": {"name": "Shaped Charge", "type": "ARC", "cost": 1, "radius": 26, "dmg": 8, "fuse": 90, "wind": 0.6, "carve": 56, "text": "Small blast, huge hole. Drops structures.", "rarity": 1, "up": {"carve": 72}},
	"haymaker": {"name": "Haymaker", "type": "MELEE", "cost": 1, "dmg": [6, 8], "range": 38, "knock": 11, "text": "Sends them flying. Aim the body at their friends.", "rarity": 1, "up": {"knock": 14}},
	"taunt": {"name": "Taunt", "type": "SELF", "cost": 0, "taunt": true, "text": "Every Jackal that can targets you next phase.", "rarity": 1, "up": {"armor": 4}},
	"suppress": {"name": "Suppressing Fire", "type": "AIM", "cost": 1, "dmg": [2, 2], "shots": 5, "range": FULL_RANGE, "gun": "mg", "bounce": 0, "sway": 0.06, "spread": 0.09, "supp": true, "text": "Everything hit is Suppressed.", "rarity": 1, "up": {"shots": 7}},
	# weapon cards: only come from equipped weapons (G1)
	"carbine": {"name": "Carbine Burst", "type": "AIM", "cost": 1, "dmg": [4, 5], "shots": 2, "range": FULL_RANGE, "gun": "smg", "bounce": 1, "sway": 0.04, "spread": 0.05, "text": "Two quick rounds.", "rarity": 0, "pool": false, "up": {"shots": 3}},
	"huntshot": {"name": "Hunting Round", "type": "AIM", "cost": 1, "dmg": [8, 10], "range": FULL_RANGE, "gun": "rifle", "bounce": 1, "sway": 0.03, "text": "Heavy round. Ricochets once.", "rarity": 0, "pool": false, "up": {"dmg": [10, 13]}},
	# letter weapons: temporary cards picked up in the field (L2)
	"flameshot": {"name": "Flame Shot", "type": "AIM", "cost": 1, "dmg": [2, 3], "pellets": 7, "range": FULL_RANGE, "gun": "shotgun", "bounce": 0, "sway": 0.02, "spread": 0.12, "knock": 2, "chip": 7, "burn": true, "text": "A gout of fire. Chews wood.", "rarity": 2, "pool": false},
	"lasergun": {"name": "Laser Gun", "type": "AIM", "cost": 1, "dmg": [9, 11], "range": FULL_RANGE, "gun": "sniper", "bounce": 3, "sway": 0.0, "pierce": true, "chip": 2, "text": "Pierces and bounces. No sway.", "rarity": 2, "pool": false},
	"chaser": {"name": "Enemy Chaser", "type": "LINE", "cost": 1, "radius": 26, "dmg": 10, "speed": 6.5, "homing": true, "text": "A rocket that hunts the nearest Jackal.", "rarity": 2, "pool": false},
	# mid and late letters: only turn up from level 2 (D, T) and level 3 (Z, G) on, see LETTER_FROM
	"dropshot": {"name": "Drop Shot", "type": "ARC", "cost": 1, "radius": 38, "dmg": 14, "fuse": 200, "bounce": true, "wind": 0.3, "text": "A heavy bomb that bounces along the ground, then blows.", "rarity": 2, "pool": false},
	"thundershot": {"name": "Thunder Shot", "type": "LINE", "cost": 1, "radius": 40, "dmg": 18, "speed": 7.0, "homing": true, "text": "A big rocket that hunts the nearest enemy.", "rarity": 3, "pool": false},
	"zantetsu": {"name": "Zantetsu Slash", "type": "MELEE", "cost": 1, "dmg": [16, 20], "range": 56, "knock": 9, "sweep": true, "text": "One sweep cuts every body in reach and the ground in front.", "rarity": 3, "pool": false},
	"superhmg": {"name": "Super HMG", "type": "AIM", "cost": 1, "dmg": [4, 5], "shots": 8, "range": FULL_RANGE, "gun": "mg", "bounce": 0, "sway": 0.03, "spread": 0.05, "pierce": true, "chip": 4, "text": "Eight piercing heavy rounds.", "rarity": 3, "pool": false},
	# mid and late weapon cards: only come from the guns of the same name (ITEMS "from")
	"bullpup": {"name": "Bullpup Burst", "type": "AIM", "cost": 1, "dmg": [5, 6], "shots": 2, "range": FULL_RANGE, "gun": "rifle", "bounce": 1, "sway": 0.03, "spread": 0.03, "text": "Two accurate rifle rounds.", "rarity": 1, "pool": false, "up": {"shots": 3}},
	"m79": {"name": "M79 Shell", "type": "ARC", "cost": 1, "radius": 36, "dmg": 12, "wind": 0.5, "text": "Explodes on impact. Barely drifts.", "rarity": 1, "pool": false, "up": {"dmg": 15, "radius": 42}},
	"railshot": {"name": "Rail Slug", "type": "AIM", "cost": 2, "dmg": [22, 28], "range": FULL_RANGE, "gun": "sniper", "bounce": 0, "sway": 0.0, "pierce": true, "phase": true, "text": "No sway. Passes through walls and every body in the line.", "rarity": 2, "pool": false, "up": {"dmg": [27, 34]}},
	"minigun": {"name": "Mini-Gun", "type": "AIM", "cost": 2, "dmg": [3, 4], "shots": 10, "range": FULL_RANGE, "gun": "mg", "bounce": 0, "sway": 0.04, "spread": 0.07, "chip": 3, "text": "Ten rounds. Shreds wood and cover.", "rarity": 2, "pool": false, "up": {"shots": 13}},
	# overdrives: unlocked by full adrenaline, free, single use
	"ricochet": {"name": "Ricochet Round", "type": "AIM", "cost": 0, "od": true, "dmg": [16, 20], "range": FULL_RANGE, "gun": "sniper", "bounce": 5, "sway": 0.0, "pierce": true, "chip": 5, "text": "Five bounces. Pierces every body it meets.", "rarity": 5},
	"surge": {"name": "Adrenal Surge", "type": "SELF", "cost": 0, "od": true, "surge": true, "range": 240, "text": "Squad within 240px: heal 10, +1 energy, +80 move.", "rarity": 5},
	"cluster": {"name": "Cluster Bomb", "type": "ARC", "cost": 0, "od": true, "radius": 40, "dmg": 12, "fuse": 110, "bounce": true, "wind": 1.0, "cluster": 5, "text": "Bursts into five bouncing bomblets.", "rarity": 5},
	"rush": {"name": "Bull Rush", "type": "LINE", "cost": 0, "od": true, "rush": true, "text": "Launch yourself. Everyone you hit goes flying.", "rarity": 5},
	# archetype Overdrives: a capstone perk swaps the soldier's Overdrive for one of these (P2)
	"oneshot": {"name": "One Shot", "type": "AIM", "cost": 0, "od": true, "dmg": [28, 34], "range": FULL_RANGE, "gun": "sniper", "bounce": 0, "sway": 0.0, "pierce": true, "phase": true, "forcehead": true, "text": "No sway. A crit that passes through walls and bodies.", "rarity": 5},
	"holdline": {"name": "Hold the Line", "type": "SELF", "cost": 0, "od": true, "overwatch": true, "ow": 8, "text": "Eight overwatch shots: fire at everything that moves.", "rarity": 5},
	"deadmans": {"name": "Dead Man's Hand", "type": "AIM", "cost": 0, "od": true, "dmg": [5, 7], "shots": 6, "range": FULL_RANGE, "gun": "pistol", "bounce": 2, "sway": 0.01, "spread": 0.03, "text": "Six fast pistol rounds.", "rarity": 5},
	"smokescreen": {"name": "Smokescreen", "type": "ARC", "cost": 0, "od": true, "smoke": true, "multi": 3, "srad": 80.0, "sturns": 3, "wind": 0.6, "text": "Three big clouds in a row.", "rarity": 5},
	"blight": {"name": "Blight Shell", "type": "SELF", "cost": 0, "od": true, "blight": true, "text": "Every Jackal on screen is Toxic for 3 rounds.", "rarity": 5},
	"triagefield": {"name": "Triage Field", "type": "SELF", "cost": 0, "od": true, "triage": 15, "range": 260, "text": "Squad within 260px: heal 15 and clear statuses.", "rarity": 5},
	"barrage": {"name": "Barrage", "type": "ARC", "cost": 0, "od": true, "beacon": true, "barrage": 6, "wind": 0.6, "text": "Six shells walk across the marker. Right now.", "rarity": 5},
	"airraid": {"name": "Air Raid", "type": "LINE", "cost": 0, "od": true, "jump": true, "jpow": 1.3, "frags": 3, "text": "Jump and drop three frags from the top of the arc.", "rarity": 5},
	"napalmstrike": {"name": "Napalm Strike", "type": "ARC", "cost": 0, "od": true, "radius": 30, "dmg": 8, "wind": 0.6, "napalm": true, "text": "Lights a line of fire across the impact.", "rarity": 5},
	"collapse": {"name": "Controlled Collapse", "type": "ARC", "cost": 0, "od": true, "radius": 40, "dmg": 10, "fuse": 60, "wind": 0.4, "carve": 96, "text": "A charge that tears out a huge chunk of terrain.", "rarity": 5},
	"immovable": {"name": "Immovable", "type": "SELF", "cost": 0, "od": true, "immovable": true, "armor": 40, "text": "40 armor and no knockback until your next turn.", "rarity": 5},
	"leadrain": {"name": "Lead Rain", "type": "AIM", "cost": 0, "od": true, "dmg": [3, 3], "shots": 16, "range": FULL_RANGE, "gun": "mg", "bounce": 0, "sway": 0.04, "spread": 0.09, "supp": true, "text": "Sixteen rounds. Everything hit is Suppressed.", "rarity": 5},
	"breach": {"name": "Breach & Clear", "type": "LINE", "cost": 0, "od": true, "rush": true, "stab": 16, "text": "Charge through. 16 damage to every body you pass.", "rarity": 5},
	# duo Overdrives (C4): two soldiers with Overdrive ready, standing within 120px
	"spotter": {"name": "Spotter Strike", "type": "ARC", "cost": 0, "od": true, "duo": true, "beacon": true, "barrage": 8, "markall": true, "wind": 0.5, "text": "Moss marks everything near the marker, Vee walks 8 shells across it.", "rarity": 5},
	"cannonball": {"name": "Human Cannonball", "type": "LINE", "cost": 0, "od": true, "duo": true, "rush": true, "cannon": true, "text": "Vee fires Rook like a shell. He lands with a blast.", "rarity": 5},
	"adrenalcharge": {"name": "Adrenal Charge", "type": "LINE", "cost": 0, "od": true, "duo": true, "rush": true, "squadheal": 10, "text": "Rook charges while Hex juices the squad: heal 10 and +25 adrenaline each.", "rarity": 5},
	"ownet": {"name": "Overwatch Net", "type": "SELF", "cost": 0, "od": true, "duo": true, "ownet": 2, "text": "Every soldier gets 2 overwatch shots.", "rarity": 5},
	"shockawe": {"name": "Shock and Awe", "type": "AIM", "cost": 0, "od": true, "duo": true, "dmg": [5, 6], "shots": 10, "range": FULL_RANGE, "gun": "mg", "bounce": 1, "sway": 0.03, "spread": 0.06, "supp": true, "text": "Ten ricocheting rounds that Suppress.", "rarity": 5},
	"firestorm": {"name": "Firestorm", "type": "ARC", "cost": 0, "od": true, "duo": true, "radius": 52, "dmg": 16, "wind": 0.8, "burnblast": true, "fuelgas": true, "text": "Hex's gas, Vee's match: a huge burning FUEL-AIR blast.", "rarity": 5},
	"slugcall": {"name": "SV-001 Slug", "type": "SELF", "cost": 0, "od": true, "slug": true, "text": "Call in the Metal Slug for a round. It rolls forward crushing Jackals and shells them.", "rarity": 5},
	# evolutions (M4): Epic+ card plus a specific kit
	"heavym": {"name": "Heavy Machine Gun", "type": "AIM", "cost": 1, "dmg": [4, 4], "shots": 8, "range": FULL_RANGE, "gun": "mg", "bounce": 1, "sway": 0.04, "spread": 0.05, "pierce": true, "text": "H! Eight piercing rounds.", "rarity": 3, "pool": false},
	"firebomb": {"name": "Fire Bomb", "type": "ARC", "cost": 1, "radius": 46, "dmg": 15, "wind": 1.0, "burnblast": true, "text": "Blows on impact and sets everything Burning.", "rarity": 3, "pool": false},
}
# ---------------------------------------------------------------- combos (C1, C3, C5, C6)
const MOMENTUM := 3          # every 3rd card a soldier plays in a turn refunds 1 energy
const STATUS := {
	"burn": {"name": "BURNING", "short": "BURN", "c": Color("ff7a3d"), "text": "3 damage a turn. Spreads to bodies on wood and chars the wood."},
	"toxic": {"name": "TOXIC", "short": "TOX", "c": Color("9be34a"), "text": "2 damage a turn, armor does not help."},
	"supp": {"name": "SUPPRESSED", "short": "SUPP", "c": Color("c9d1da"), "text": "Half movement on its next turn."},
	"mark": {"name": "MARKED", "short": "MARK", "c": Color("ff4d3d"), "text": "The next hit on it is a critical (x1.5)."},
	"stun": {"name": "STUNNED", "short": "STUN", "c": Color("ffd23a"), "text": "Skips its next turn."},
	# bonus pad powerups (Soldat): they last the rest of this turn and the holder's next one
	"berserk": {"name": "BERSERKER", "short": "BERS", "c": Color("ff4d3d"), "text": "Deals double damage."},
	"cloak": {"name": "PREDATOR", "short": "PRED", "c": Color("b48cff"), "text": "Can't be targeted, and bullets pass through, until it attacks."},
	"flamegod": {"name": "FLAMEGOD", "short": "FLAME", "c": Color("ff9a3d"), "text": "Takes no damage. Its bullets set what they hit on fire."},
	"vest": {"name": "VEST", "short": "VEST", "c": Color("9fb4c9"), "text": "Takes half damage."},
	"roll": {"name": "ROLLING", "short": "ROLL", "c": Color("e8dcc2"), "text": "The next Jackal shot at it goes over its head."},
	"cluster": {"name": "CLUSTER", "short": "CLUS", "c": Color("ffd23a"), "text": "Its next grenades burst into bomblets (counts grenades, not turns)."},
	"nades": {"name": "GRENADE KIT", "short": "NADE", "c": Color("8fbf4a"), "text": "Throws a grenade on its next attack."},
}
# Bonus pads (Soldat): a marked pad shows which bonus it will give and in how many rounds.
# Whoever stands on it when it is ready takes it, soldier or Jackal. Then it starts over.
const BONUSES := {
	"berserk": {"name": "BERSERKER", "glyph": "B", "c": Color("ff4d3d"), "text": "Double damage for this turn and the next."},
	"cloak": {"name": "PREDATOR", "glyph": "P", "c": Color("b48cff"), "text": "Invisible to the other side until you attack. Lasts this turn and the next."},
	"flamegod": {"name": "FLAMEGOD", "glyph": "F", "c": Color("ff9a3d"), "text": "No damage taken, and your bullets set targets on fire. This turn and the next."},
	"vest": {"name": "VEST", "glyph": "V", "c": Color("9fb4c9"), "text": "Half damage taken for this turn and the next."},
	"medkit": {"name": "MEDKIT", "glyph": "+", "c": Color("62d26f"), "text": "Heals 15 at once."},
	"cluster": {"name": "CLUSTER", "glyph": "C", "c": Color("ffd23a"), "text": "Your next 2 grenades burst into bouncing bomblets."},
	"nadekit": {"name": "GRENADE KIT", "glyph": "G", "c": Color("8fbf4a"), "text": "Two Frag Grenades that stay in hand until thrown. A Jackal throws one on its next move."},
}
const BONUS_TURNS := 2
const PAD_FIRST := [1, 2]   # rounds until each pad's first bonus (pads take turns)
const PAD_RESET := 3        # rounds until a pad has its next bonus ready
const TAGS := {
	"topgun": {"name": "TOP GUN!", "text": "A kill from the top of a jump: +15 adrenaline."},
	"skeet": {"name": "SKEET!", "text": "Shot a Jackal another soldier launched: double damage, +1 energy."},
	"pileup": {"name": "PILE-UP", "text": "A launched body hit another Jackal: both stunned."},
	"pinball": {"name": "PINBALL", "text": "One bullet hit 2+ Jackals: draw a card."},
	"fuelair": {"name": "FUEL-AIR", "text": "Blast inside smoke or gas: radius +50%."},
	"domino": {"name": "DOMINO", "text": "Debris crushed 2+ Jackals: +1 energy to everyone and a loot drop."},
	"skydiver": {"name": "SKY DIVER", "text": "Kill while airborne: the card is refunded."},
	"crossfire": {"name": "CROSSFIRE", "text": "Hit from both sides in one turn: suppressed."},
}
# Legendary items made by a triple merge get a name and a unique line (M1).
const LEGEND_NAMES := {"weapon": ["Old Faithful", "Widowmaker", "Last Word"], "armor": ["Old Iron", "Second Skin", "Hard Luck"], "kit": ["Lucky Break", "Sixth Sense", "Hot Hands"]}
const LEGEND_BONUS := {"weapon": {"aim_dmg": 2}, "armor": {"armor_turn": 2}, "kit": {"luck": 1}}
const NICK_KILLS := 10  # D4: kills that earn a card a nickname
const CARD_NICKS := ["Old Faithful", "The Closer", "Sweet Talker", "Big Iron", "Last Call", "House Rules"]
const FAB_PRICE := 70

const OD := {"moss": "ricochet", "hex": "surge", "vee": "cluster", "rook": "rush"}
# Metal Slug letter drops: 3 temporary cards in the collector's hand for the rest of the mission.
const LETTERS := {"H": "hmg", "R": "bazooka", "F": "flameshot", "S": "shotgun", "L": "lasergun", "C": "chaser",
	"D": "dropshot", "T": "thundershot", "Z": "zantetsu", "G": "superhmg"}
# Letters that only drop from a given point in the run on (Run.mission: 1 = level 2, 2 = level 3 and the finale).
const LETTER_FROM := {"D": 1, "T": 1, "Z": 2, "G": 2}

# ---------------------------------------------------------------- gear (G1-G6)
# Four slots per soldier plus a squad stash and a 3-slot consumable belt.
# "stats" scale with the item's rarity (TIER_MUL); weapons add their cards to the deck.
const SLOT_NAMES := {"weapon": "WEAPON", "armor": "ARMOR", "kit": "KIT", "belt": "BELT"}
const TIER_MUL := [1.0, 1.25, 1.5, 2.0, 2.5]
const STASH_MAX := 8
const BELT_MAX := 3
const ITEMS := {
	"carbine": {"name": "M-16 Carbine", "slot": "weapon", "cards": ["carbine", "carbine"], "stats": {"light": 10}, "text": "Adds 2 Carbine Burst cards."},
	"huntrifle": {"name": "Hunting Rifle", "slot": "weapon", "cards": ["huntshot", "huntshot"], "text": "Adds 2 Hunting Round cards."},
	"marksman": {"name": "Marksman Rifle", "slot": "weapon", "cards": ["snipe", "snipe"], "stats": {"laser_pct": 0.2}, "text": "Adds 2 Long Shot cards."},
	"riotgun": {"name": "Riot Shotgun", "slot": "weapon", "cards": ["shotgun", "shotgun"], "text": "Adds 2 Shotgun cards."},
	"service": {"name": "Service Pistol", "slot": "weapon", "cards": ["pistol", "pistol"], "stats": {"light": 15}, "text": "Adds 2 Sidearm cards."},
	"greasegun": {"name": "Grease Gun", "slot": "weapon", "cards": ["burst", "burst"], "stats": {"light": 10}, "text": "Adds 2 Burst Fire cards."},
	"tube": {"name": "Bazooka Tube", "slot": "weapon", "cards": ["bazooka", "bazooka"], "stats": {"heavy": 15}, "set": "boar", "text": "Adds 2 Bazooka cards."},
	"combatknife": {"name": "Combat Knife", "slot": "kit", "stats": {"sa": 1}, "text": "Your sidearm becomes a free Combat Knife."},
	"chainsaw": {"name": "Chainsaw", "slot": "kit", "stats": {"sa": 2}, "text": "Your sidearm becomes a Chainsaw."},
	"lawtube": {"name": "LAW Tube", "slot": "kit", "stats": {"sa": 3}, "text": "Your sidearm becomes a free one-shot LAW rocket, reloaded at every camp."},
	"nadebelt": {"name": "Grenade Belt", "slot": "weapon", "cards": ["frag", "frag"], "text": "Adds 2 Frag Grenade cards."},
	"machete": {"name": "Machete", "slot": "weapon", "cards": ["knife", "knife"], "stats": {"light": 15}, "set": "desert", "text": "Adds 2 Knife cards."},
	"medbag": {"name": "Medic Bag", "slot": "weapon", "cards": ["medkit", "medkit"], "stats": {"heal": 1}, "text": "Adds 2 Field Dressing cards."},
	"flak": {"name": "Flak Vest", "slot": "armor", "stats": {"hp": 4}, "text": "Padding where it counts."},
	"plate": {"name": "Riot Plate", "slot": "armor", "stats": {"armor_turn": 2}, "set": "boar", "text": "Armor at the start of every turn."},
	"ghillie": {"name": "Ghillie Suit", "slot": "armor", "stats": {"dodge": 6}, "set": "desert", "text": "Hard to pin down."},
	"cboots": {"name": "Combat Boots", "slot": "armor", "stats": {"move": 25}, "text": "Broken in."},
	"steeltoe": {"name": "Steel-Toe Rig", "slot": "armor", "stats": {"hp": 2, "fall_half": 1}, "text": "Half damage from falls and slams."},
	"sparemag": {"name": "Spare Mag", "slot": "kit", "stats": {"kill_draw": 1}, "text": "ON KILL: draw a card (once a turn)."},
	"flashhider": {"name": "Flash Hider", "slot": "kit", "stats": {"head_adr": 15}, "text": "ON HEADSHOT: gain adrenaline."},
	"ammopouch": {"name": "Ammo Pouch", "slot": "kit", "stats": {"energy1": 1}, "text": "+1 energy on round 1."},
	"luckycoin": {"name": "Lucky Coin", "slot": "kit", "stats": {"luck": 1}, "text": "Better loot for the whole squad."},
	"scope": {"name": "4x Scope", "slot": "kit", "stats": {"laser_step": 1}, "text": "This soldier's aim laser reaches a step further."},
	"griptape": {"name": "Grip Tape", "slot": "kit", "stats": {"sway": 0.2}, "set": "desert", "text": "Less sway on every gun."},
	"medpatch": {"name": "Med Patch", "slot": "kit", "stats": {"regen": 2}, "text": "Heal at the start of every turn."},
	"detcord": {"name": "Det Cord", "slot": "kit", "stats": {"blast": 0.12}, "set": "boar", "text": "Bigger blasts."},
	"rallypatch": {"name": "Rally Patch", "slot": "kit", "stats": {"push_draw": 1}, "text": "ON PUSH: draw a card."},
	"adrenalgland": {"name": "Adrenal Gland", "slot": "kit", "stats": {"kill_adr": 10}, "text": "ON KILL: extra adrenaline."},
	"tungsten": {"name": "Tungsten Core", "slot": "kit", "keystone": "moss", "stats": {"aim_dmg": 1}, "text": "KEYSTONE: every bounce before a hit adds 25% damage."},
	"varga": {"name": "Varga's Scope", "slot": "kit", "keystone": "moss", "stats": {"laser_step": 1}, "text": "KEYSTONE: Long Shot passes through wood."},
	"claymore": {"name": "Claymore Satchel", "slot": "kit", "keystone": "moss", "stats": {"armor_turn": 1}, "text": "KEYSTONE: overwatch shots explode where they hit."},
	"twinrev": {"name": "Twin Revolvers", "slot": "weapon", "keystone": "moss", "cards": ["pistol", "pistol"], "text": "KEYSTONE: adds 2 Sidearms. Every Sidearm fires twice at 60%."},
	"overcharger": {"name": "Overcharger Rig", "slot": "armor", "keystone": "hex", "stats": {"hp": 3}, "text": "KEYSTONE: duo Overdrives with this soldier need only one full bar."},
	"canister": {"name": "Canister Launcher", "slot": "weapon", "keystone": "hex", "cards": ["smoke", "smoke"], "text": "KEYSTONE: adds 2 Smoke Cans. Smoke cards cost 0 and bounce."},
	"weathervane": {"name": "Weather Vane", "slot": "kit", "keystone": "hex", "stats": {"luck": 1}, "text": "KEYSTONE: your gas drifts toward the nearest Jackal, not with the wind."},
	"medrig": {"name": "Med-Rig Plate", "slot": "armor", "keystone": "hex", "stats": {"hp": 4}, "text": "KEYSTONE: every heal you give also gives you that much armor."},
	"howitzer": {"name": "Howitzer Sights", "slot": "kit", "keystone": "vee", "stats": {"blast": 0.08}, "text": "KEYSTONE: Airstrike Beacon costs 1 less and calls 2 more bombs."},
	"lizard": {"name": "Iron Lizard", "slot": "weapon", "keystone": "vee", "cards": ["bazooka", "bazooka"], "text": "KEYSTONE: adds 2 Bazookas. Rockets that hit the ground crawl along it."},
	"fuelpack": {"name": "Fuel Backpack", "slot": "armor", "keystone": "vee", "stats": {"hp": 3}, "text": "KEYSTONE: fire you start burns for 4 rounds."},
	"detbox": {"name": "Detonator Box", "slot": "kit", "keystone": "vee", "stats": {"blast": 0.1}, "text": "KEYSTONE: barrels and fuel tanks you set off blow at once for +50%."},
	"gauntlet": {"name": "Pneumatic Gauntlet", "slot": "weapon", "keystone": "rook", "cards": ["haymaker", "haymaker"], "text": "KEYSTONE: adds 2 Haymakers. Bodies you launch keep their speed and hit 50% harder."},
	"riotshield": {"name": "Riot Shield", "slot": "armor", "keystone": "rook", "stats": {"hp": 4}, "text": "KEYSTONE: blocks 75% of bullets from the front."},
	"ammobelt": {"name": "Ammo Belt", "slot": "kit", "keystone": "rook", "stats": {"move": 10}, "text": "KEYSTONE: Heavy MG fires 3 more rounds."},
	"zantetsu": {"name": "Zantetsu Sword", "slot": "weapon", "keystone": "rook", "cards": ["knife", "knife"], "text": "KEYSTONE: adds 2 Knives. Knife sweeps every body in reach and cuts terrain."},
	"jetboots": {"name": "Jet Boots", "slot": "kit", "stats": {"jet": 90}, "text": "Press J, then hold the mouse to fly toward the cursor. Fuel refills each turn you start on the ground."},
	"guidance": {"name": "Guidance Chip", "slot": "kit", "stats": {"aim_dmg": 1}, "text": "Rockets think for themselves."},
	"napalmmix": {"name": "Napalm Mix", "slot": "kit", "stats": {"blast": 0.06}, "text": "Sticky, smelly, very flammable."},
	# Armory unlocks (W4): locked until a feat is done once, in any run
	"boarplate": {"name": "Boar Plating", "slot": "armor", "stats": {"hp": 3, "armor_turn": 2}, "set": "boar", "locked": true, "text": "Cut from a cracked Iron Boar."},
	"skeetvest": {"name": "Skeet Vest", "slot": "armor", "stats": {"dodge": 8, "move": 10}, "locked": true, "text": "Pull!"},
	"deflector": {"name": "Deflector Rounds", "slot": "kit", "stats": {"aim_dmg": 2}, "locked": true, "text": "Ricochets keep their bite."},
	"zippo": {"name": "Zippo", "slot": "kit", "stats": {"blast": 0.06, "kill_adr": 4}, "locked": true, "text": "Never leave home without it."},
	"medalcase": {"name": "Medal Case", "slot": "kit", "stats": {"luck": 2}, "locked": true, "text": "Polished every night."},
	"antimat": {"name": "Anti-Materiel Rifle", "slot": "weapon", "cards": ["snipe", "snipe"], "stats": {"laser_step": 1, "aim_dmg": 1, "heavy": 15}, "locked": true, "text": "Adds 2 Long Shot cards."},
	# Mid and late game finds (G7): "from" is the first Run.mission they drop in, 1 = level 2,
	# 2 = level 3 and the finale. Crates, the shop and every drop roll them; none has a downside.
	"bullpupgun": {"name": "Bullpup Rifle", "slot": "weapon", "from": 1, "cards": ["bullpup", "bullpup"], "stats": {"aim_dmg": 1}, "text": "Adds 2 Bullpup Burst cards."},
	"m79gun": {"name": "M79 Launcher", "slot": "weapon", "from": 1, "cards": ["m79", "m79"], "stats": {"blast": 0.08}, "text": "Adds 2 M79 Shell cards."},
	"ceramic": {"name": "Ceramic Plate", "slot": "armor", "from": 1, "stats": {"hp": 6, "armor_turn": 1}, "text": "Light, hard, and a lot of it."},
	"exolegs": {"name": "Exo Legs", "slot": "armor", "from": 1, "stats": {"move": 40, "fall_half": 1}, "text": "Hydraulic knees. Half damage from falls and slams."},
	"tracers": {"name": "Tracer Rounds", "slot": "kit", "from": 1, "stats": {"aim_dmg": 2}, "text": "Every round finds its mark a little harder."},
	"battlecomp": {"name": "Battle Computer", "slot": "kit", "from": 1, "stats": {"laser_step": 1, "sway": 0.3}, "text": "Aim laser a step further, much less sway."},
	"railgun": {"name": "Rail Gun", "slot": "weapon", "from": 2, "cards": ["railshot", "railshot"], "stats": {"laser_step": 1}, "text": "Adds 2 Rail Slug cards."},
	"minigungun": {"name": "Mini-Gun", "slot": "weapon", "from": 2, "cards": ["minigun", "minigun"], "stats": {"hp": 4}, "text": "Adds 2 Mini-Gun cards."},
	"juggernaut": {"name": "Juggernaut Suit", "slot": "armor", "from": 2, "stats": {"hp": 10, "armor_turn": 3}, "text": "Bomb-disposal armor, rebuilt for the front."},
	"vharrheart": {"name": "Vharr Heart", "slot": "kit", "from": 2, "stats": {"regen": 3, "kill_adr": 12}, "text": "Still beating. Heals you and feeds on every kill."},
	"hkchip": {"name": "Hunter-Killer Chip", "slot": "kit", "from": 2, "stats": {"kill_draw": 1, "aim_dmg": 1}, "text": "ON KILL: draw a card (once a turn). +1 AIM damage."},
	"b_stim": {"name": "Combat Stim", "slot": "belt", "from": 1, "use": "stim", "n": 12, "text": "Heal 12 and +1 energy. No card or energy needed."},
	"b_adr": {"name": "Rage Shot", "slot": "belt", "from": 2, "use": "adr", "n": 50, "text": "+50 adrenaline right now."},
	"b_medkit": {"name": "Medkit", "slot": "belt", "use": "heal", "n": 10, "text": "Heal 10. No card or energy needed."},
	"b_smoke": {"name": "Smoke Pot", "slot": "belt", "use": "smoke", "text": "Smoke at your feet."},
	"b_ration": {"name": "Ration", "slot": "belt", "use": "ration", "n": 5, "text": "Heal 5 and find 15 scrip."},
	"b_ammo": {"name": "Ammo Crate", "slot": "belt", "use": "energy", "text": "+1 energy right now."},
}
# Affixes rolled onto gear: Common 0, Uncommon 1, Rare 2, Epic 2 (x1.5), Legendary 3 (x2).
const AFFIXES := {
	"hp": {"v": 3, "fmt": "+%d max HP"},
	"move": {"v": 15, "fmt": "+%d move"},
	"dodge": {"v": 3, "fmt": "+%d dodge"},
	"kill_adr": {"v": 6, "fmt": "ON KILL: +%d adrenaline"},
	"laser_pct": {"v": 0.25, "fmt": "+%d%% laser length", "pct": true},
	"armor_turn": {"v": 1, "fmt": "+%d armor each turn"},
	"aim_dmg": {"v": 1, "fmt": "+%d AIM damage"},
	"blast": {"v": 0.08, "fmt": "+%d%% blast size", "pct": true},
	"heal": {"v": 2, "fmt": "+%d healing"},
	"regen": {"v": 1, "fmt": "Heal %d each turn"},
}
const AFFIX_COUNT := [0, 1, 2, 2, 3]
const AFFIX_MUL := [1.0, 1.0, 1.0, 1.5, 2.0]
const SETS := {
	"desert": {"name": "Desert Rat", "bonus": {"move": 20, "dodge": 5}, "text": "Ghillie Suit, Grip Tape, Machete. 2 pieces: +20 move, +5 dodge."},
	"boar": {"name": "Boar Salvage", "bonus": {"armor_turn": 2, "hp": 4}, "text": "Riot Plate, Det Cord, Bazooka Tube. 2 pieces: +2 armor each turn, +4 max HP."},
}
const STAT_FMT := {
	"hp": "+%d max HP", "move": "+%d move", "dodge": "+%d dodge", "armor_turn": "+%d armor each turn",
	"kill_draw": "ON KILL: draw %d", "head_adr": "ON HEADSHOT: +%d adrenaline", "energy1": "+%d energy round 1",
	"luck": "+%d squad Luck", "laser_step": "+%d laser step", "sway": "-%d%% sway", "regen": "Heal %d each turn",
	"blast": "+%d%% blast size", "push_draw": "ON PUSH: draw %d", "kill_adr": "ON KILL: +%d adrenaline",
	"laser_pct": "+%d%% laser length", "heal": "+%d healing", "fall_half": "Half fall damage", "aim_dmg": "+%d AIM damage",
	"jet": "%d jet fuel", "light": "LIGHT: +%d move", "heavy": "HEAVY: -%d move, jets burn faster",
	"sa": "SIDEARM %d",
}
const PCT_STATS := ["sway", "blast", "laser_pct"]
const FLAT_STATS := ["kill_draw", "energy1", "luck", "laser_step", "push_draw", "fall_half", "light", "heavy", "sa"]
const SIDEARMS := ["sa_pistol", "sa_knife", "sa_chainsaw", "sa_law"]  # by the "sa" gear stat
# B4: Jackals that drop their gun when they die; walking over it gives one shot of it
const DROP_GUNS := {"mg": "hmg", "mortarcrew": "mortar", "nade": "frag"}

# Elite Jackals (L4): gold-outlined, one modifier, a guaranteed item drop.
const ELITES := {
	"armored": {"name": "ARMORED", "text": "Bullets do half damage. Blast or crush it."},
	"volatile": {"name": "VOLATILE", "text": "Explodes when it dies."},
	"veteran": {"name": "VETERAN", "text": "Shoots like the alert is maxed."},
	"medic": {"name": "MEDIC", "text": "Heals nearby Jackals each turn."},
	"shielded": {"name": "SHIELDED", "text": "Carries a riot shield."},
	# Vharr elites (E7): only aliens roll these, and only these.
	"brood": {"name": "BROOD", "vharr": true, "text": "Splits into two half-strength copies when it dies."},
	"alpha": {"name": "ALPHA", "vharr": true, "text": "Others of its kind within 160px act twice while it lives."},
	"anchored": {"name": "ANCHORED", "vharr": true, "text": "Can't be knocked back. Crush it or burn it."},
	"hungry": {"name": "HUNGRY", "vharr": true, "text": "Eats a body within 60px each turn to heal 8."},
	# H6: a Jackal carrying a Vharr parasite (also what an Overseer's link does)
	"thrall": {"name": "THRALL", "text": "Shrugs off the first knockback. A Skitter bursts out when it dies."},
}
# Named POWs with a specialty (L5). Anyone else gives +1 Luck.
const POW_SPECIAL := {
	"Sgt. Bramble": {"id": "quartermaster", "text": "QUARTERMASTER: 20% off at the next shop"},
	"Pvt. Okonkwo": {"id": "gunsmith", "text": "GUNSMITH: a free affix reroll"},
	"Cpl. Teller": {"id": "medic", "text": "MEDIC: the squad heals 6"},
}
const TROPHIES := ["BOAR TREAD", "BOAR CANNON", "BOAR ENGINE"]
const SHOP_PRICE := [45, 70, 100]

# ---------------------------------------------------------------- dog tags and recruits
const DOG_TAGS := 2        # going down spends a tag; going down with none left is KIA for good
const RECRUIT_PRICE := 80
const TAG_PRICE := 70
const CALLSIGNS := ["BISHOP", "DUKE", "FLINT", "GUNNER", "HAWK", "JINX", "KNOX", "LUCKY", "MAVERICK", "NOVA",
	"ONYX", "PATCH", "RAZOR", "SARGE", "SPUD", "TANK", "VIPER", "WREN", "YANK", "ZERO", "BLUE", "CROW", "DIESEL", "ROACH"]
# Recruit traits: shown before you hire, never rolled after.
const RECRUIT_TRAITS := [
	{"id": "quick", "name": "Quick", "text": "+25 movement."},
	{"id": "tough", "name": "Tough", "text": "+5 max HP."},
	{"id": "slippery", "name": "Slippery", "text": "+6 dodge."},
	{"id": "drilled", "name": "Drilled", "text": "Starts with one card upgraded."},
]

const SQUAD_DEFS := [
	{"key": "moss", "name": "MOSS", "cls": "Marksman", "hp": 22, "dodge": 10, "spd": 180,
	 "deck": ["snipe", "snipe", "rifle", "rifle", "pistol", "overwatch", "digin", "dash", "drill"],
	 "pool": ["snipe", "rifle", "pistol", "burst", "overwatch", "digin", "dash", "roll", "grapple", "hmg", "adrenal", "tagshot", "bankshot", "holdbreath", "fanhammer", "quickdraw"],
	 "trait": ["Eagle Eye", "Headshots deal 2x damage instead of 1.5x."], "bio": "Former game warden. Counts every round twice."},
	{"key": "hex", "name": "HEX", "cls": "Field Medic", "hp": 24, "dodge": 14, "spd": 210,
	 "deck": ["medkit", "medkit", "stim", "pistol", "pistol", "smoke", "sprint", "frag", "drill"],
	 "pool": ["medkit", "stim", "smoke", "pistol", "sprint", "roll", "rally", "frag", "adrenal", "digin", "shotgun", "gasnade", "hotshot", "flashbang", "dartpistol", "defib"],
	 "trait": ["Bedside Manner", "Heals restore +3 HP."], "bio": "Patched up three wars. Still hates the sight of blood."},
	{"key": "vee", "name": "VEE", "cls": "Demolitions", "hp": 27, "dodge": 6, "spd": 185,
	 "deck": ["frag", "frag", "bazooka", "bazooka", "mortar", "pistol", "jumppack", "sprint", "drill"],
	 "pool": ["frag", "mortar", "bazooka", "rocket", "clusterfrag", "beacon", "jumppack", "roll", "shotgun", "smoke", "gasnade", "rocketjump", "molotov", "shapedcharge"],
	 "trait": ["Pyromaniac", "Explosions deal +3 damage. Her own blasts hurt her for 40%."], "bio": "Measures distance in fuse-seconds."},
	{"key": "rook", "name": "ROOK", "cls": "Vanguard", "hp": 32, "dodge": 8, "spd": 200,
	 "deck": ["rifle", "rifle", "rifle", "burst", "sprint", "knife", "frag", "grapple", "drill"],
	 "pool": ["rifle", "burst", "shotgun", "hmg", "knife", "digin", "grapple", "sprint", "roll", "rally", "adrenal", "tagshot", "haymaker", "taunt", "suppress"],
	 "trait": ["Thick Skull", "Takes half damage from falls, slams and crushing debris."], "bio": "First through every door. Usually the wrong one."},
]

# Four archetype branches per soldier (P1). Each has Minor, Major and Capstone perks; a
# perk is offered only after the one before it. The Capstone swaps the Overdrive (P2).
# "chain" is the archetype's signature sequence (C2), live from the start of the run.
const BRANCHES := {
	"moss": [
		{"id": "ricochet", "name": "Ricochet Artist", "od": "ricochet", "keystone": "tungsten",
		 "chain": {"name": "DOUBLE BANK", "text": "After a PINBALL, your next AIM card this turn costs 0."},
		 "perks": [{"id": "trick", "name": "Trick Shot", "text": "+1 ricochet on every AIM card."},
			{"id": "angles", "name": "Angles", "text": "Rounds that bounced first ignore riot shields."},
			{"id": "mirrors", "name": "Hall of Mirrors", "text": "+2 ricochets on every AIM card."}]},
		{"id": "headhunter", "name": "Headhunter", "od": "oneshot", "keystone": "varga",
		 "chain": {"name": "SPOTTED", "text": "Tag Round, then Long Shot: the Long Shot is a guaranteed headshot."},
		 "perks": [{"id": "steady", "name": "Steady Hands", "text": "All of Moss's sway is halved."},
			{"id": "patience", "name": "Patience", "text": "AIM cards deal +30% damage if Moss hasn't moved this turn."},
			{"id": "deadeye", "name": "Dead Eye", "text": "Headshot kills refund the card."}]},
		{"id": "sentinel", "name": "Sentinel", "od": "holdline", "keystone": "claymore",
		 "chain": {"name": "DUG IN", "text": "Dig In, then Overwatch: overwatch shots are crits."},
		 "perks": [{"id": "sentinel", "name": "Sentinel", "text": "Overwatch fires twice."},
			{"id": "hairtrigger", "name": "Hair Trigger", "text": "Overwatch also fires when a Jackal shoots or throws, not only when it moves."},
			{"id": "tracker", "name": "Motion Tracker", "text": "Energy left at the end of your turn becomes overwatch shots."}]},
		{"id": "gunslinger", "name": "Gunslinger", "od": "deadmans", "keystone": "twinrev",
		 "chain": {"name": "SIX SHOOTER", "text": "Three AIM cards in a row: a free Sidearm lands in your hand."},
		 "perks": [{"id": "doubletap", "name": "Double Tap", "text": "The first AIM card each turn costs 1 less."},
			{"id": "cylinder", "name": "Spin the Cylinder", "text": "Playing a Sidearm draws a card."},
			{"id": "highnoon", "name": "High Noon", "text": "Momentum pays out every 2 cards instead of 3."}]},
	],
	"hex": [
		{"id": "juicer", "name": "Juicer", "od": "surge", "keystone": "overcharger",
		 "chain": {"name": "JUICED", "text": "Stim a squadmate, and the next Overdrive they play this turn stays in their hand."},
		 "perks": [{"id": "pumpup", "name": "Pump Up", "text": "Anyone Hex heals gains 20 adrenaline."},
			{"id": "seconddose", "name": "Second Dose", "text": "Stim Shot no longer costs HP."},
			{"id": "redline", "name": "Red Line", "text": "Healing past max HP turns into adrenaline (x4)."}]},
		{"id": "ghost", "name": "Ghost Doctor", "od": "smokescreen", "keystone": "canister",
		 "chain": {"name": "FROM THE FOG", "text": "Smoke, then Sprint, then any attack: that attack crits."},
		 "perks": [{"id": "smokedoc", "name": "Smoke Doctor", "text": "Squadmates inside smoke heal 3 each enemy phase."},
			{"id": "thicksmoke", "name": "Thick Smoke", "text": "Hex's clouds are 25% bigger and last a round longer."},
			{"id": "ghillie", "name": "Ghillie", "text": "Squadmates inside smoke can't be targeted unless they attacked this turn."}]},
		{"id": "chemist", "name": "Chemist", "od": "blight", "keystone": "weathervane",
		 "chain": {"name": "THERMOBARIC", "text": "A blast inside Hex's gas is a FUEL-AIR with double radius."},
		 "perks": [{"id": "fieldkit", "name": "Field Kit", "text": "Hex draws 1 extra card each turn."},
			{"id": "badbatch", "name": "Bad Batch", "text": "Hex's heals poison Jackals within 90px of the patient."},
			{"id": "pandemic", "name": "Pandemic", "text": "Toxic Jackals spread Toxic to their friends when they die."}]},
		{"id": "surgeon", "name": "Battle Surgeon", "od": "triagefield", "keystone": "medrig",
		 "chain": {"name": "SCRUBBED IN", "text": "Heal, then Shotgun on the same turn: +3 pellets."},
		 "perks": [{"id": "triage", "name": "Triage", "text": "Heals restore +4 more HP."},
			{"id": "hardplates", "name": "Hard Plates", "text": "Healing past max HP becomes armor."},
			{"id": "lazarus", "name": "Lazarus", "text": "Once a mission, a squadmate who drops gets back up at 30% HP."}]},
	],
	"vee": [
		{"id": "artillerist", "name": "Artillerist", "od": "barrage", "keystone": "howitzer",
		 "chain": {"name": "CRATER", "text": "Two of Vee's blasts on the same spot in one turn: a big crater, and everyone in it is stunned."},
		 "perks": [{"id": "bigboom", "name": "Bigger Booms", "text": "Vee's blasts are 20% bigger."},
			{"id": "rangefinder", "name": "Rangefinder", "text": "Vee's blasts deal +2 damage per 200px they travelled."},
			{"id": "fireforeffect", "name": "Fire for Effect", "text": "Mortar Shells land a second shell on the spot next enemy phase."}]},
		{"id": "rocketjumper", "name": "Rocket Jumper", "od": "airraid", "keystone": "lizard",
		 "chain": {"name": "DEATH FROM ABOVE", "text": "Jump, then any ARC or LINE attack on the same turn: +50% damage."},
		 "perks": [{"id": "blastproof", "name": "Blast Proof", "text": "Vee takes no damage from her own blasts."},
			{"id": "kinetic", "name": "Kinetic Boots", "text": "Vee's own blasts throw her 60% further, and she lands soft."},
			{"id": "meteor", "name": "Meteor", "text": "Landing from a jump or a blast explodes."}]},
		{"id": "pyro", "name": "Pyro", "od": "napalmstrike", "keystone": "fuelpack",
		 "chain": {"name": "ACCELERANT", "text": "Molotov, then any blast this turn: that blast sets everything Burning."},
		 "perks": [{"id": "shortfuse", "name": "Short Fuse", "text": "Vee's grenade fuses are halved and deal +2."},
			{"id": "accelerant", "name": "Accelerant", "text": "Fire Vee starts burns for +2 damage a turn."},
			{"id": "napalm", "name": "Napalm Mix", "text": "All of Vee's blasts leave things Burning."}]},
		{"id": "wrecker", "name": "Wrecker", "od": "collapse", "keystone": "detbox",
		 "chain": {"name": "DEMOLITION", "text": "A DOMINO from Vee's action refunds the card."},
		 "perks": [{"id": "chain", "name": "Chain Reaction", "text": "Barrels and fuel tanks Vee sets off hit twice as hard."},
			{"id": "weakpoints", "name": "Weak Points", "text": "Vee's blasts tear 35% more terrain."},
			{"id": "democrew", "name": "Demolition Crew", "text": "Debris Vee brings down crushes for double damage."}]},
	],
	"rook": [
		{"id": "bowler", "name": "Bowler", "od": "rush", "keystone": "gauntlet",
		 "chain": {"name": "SPARE", "text": "When a squadmate SKEETs a Jackal Rook launched, Rook gets +1 energy too."},
		 "perks": [{"id": "bulldozer", "name": "Bulldozer", "text": "Bodies Rook launches deal double collision damage."},
			{"id": "ricobody", "name": "Ricochet Body", "text": "Jackals Rook launches bounce off the first wall instead of stopping."},
			{"id": "strike", "name": "STRIKE!", "text": "One body that hits 3 others: +1 energy and a card for Rook."}]},
		{"id": "juggernaut", "name": "Juggernaut", "od": "immovable", "keystone": "riotshield",
		 "chain": {"name": "COME AND GET IT", "text": "Taunt, then Dig In: double armor."},
		 "perks": [{"id": "ironhide", "name": "Iron Hide", "text": "Rook starts every turn with 3 armor."},
			{"id": "secondwind", "name": "Second Wind", "text": "Once per mission, survive a killing blow at 1 HP."},
			{"id": "payback", "name": "Payback", "text": "Armor left when Rook's turn starts is added to his next hit."}]},
		{"id": "heavy", "name": "Heavy Gunner", "od": "leadrain", "keystone": "ammobelt",
		 "chain": {"name": "PINNED", "text": "Suppress 2+ Jackals, then push the line: +1 energy for the squad."},
		 "perks": [{"id": "bipod", "name": "Bipod", "text": "Heavy MG, Burst Fire and Suppressing Fire sway half as much."},
			{"id": "pindown", "name": "Pin Down", "text": "Rook's machine-gun hits Suppress."},
			{"id": "hosepipe", "name": "Hosepipe", "text": "Rook's machine-gun rounds pierce bodies and shred wood."}]},
		{"id": "breacher", "name": "Breacher", "od": "breach", "keystone": "zantetsu",
		 "chain": {"name": "ZIP STRIKE", "text": "Grapple, then Knife: refund 1 energy."},
		 "perks": [{"id": "charge", "name": "Charge!", "text": "+60 movement every turn."},
			{"id": "hookshot", "name": "Hookshot", "text": "Grappling next to a Jackal yanks it off its feet toward Rook."},
			{"id": "blitz", "name": "Blitz", "text": "Every push puts a free Knife in Rook's hand."}]},
	],
}
const PERK_TIER := ["MINOR", "MAJOR", "CAPSTONE"]

# Legendary keystone items live in ITEMS (one per archetype). Anyone can wear one, which makes hybrids.
const KEYSTONE_IDS := ["tungsten", "varga", "claymore", "twinrev", "overcharger", "canister", "weathervane", "medrig", "howitzer", "lizard", "fuelpack", "detbox", "gauntlet", "riotshield", "ammobelt", "zantetsu"]

# Branching card upgrades (P3): the Gunsmith adds up to 2 mods per card. A cost cut is one option.
const MAX_MODS := 2
const CARD_MODS := {
	"frag": [{"id": "sticky", "name": "Impact", "text": "No bounce: blows on impact.", "erase": ["fuse"], "set": {"bounce": false}},
		{"id": "bigbang", "name": "Big Bang", "text": "+12 blast radius.", "add": {"radius": 12}},
		{"id": "quickfuse", "name": "Short Fuse", "text": "1s fuse and +3 damage.", "set": {"fuse": 60}, "add": {"dmg": 3}},
		{"id": "shrapnel", "name": "Shrapnel", "text": "Sprays 6 bullets when it bursts.", "set": {"shrapnel": 6}}],
	"shotgun": [{"id": "slug", "name": "Slug", "text": "One heavy slug that pierces.", "set": {"pellets": 1, "dmg": [11, 14], "pierce": true, "spread": 0.0}},
		{"id": "wide", "name": "Wide Choke", "text": "+3 pellets.", "add": {"pellets": 3}}],
	"snipe": [{"id": "hollow", "name": "Hollow Point", "text": "+5 damage, no pierce.", "add": {"dmg": [5, 5]}, "set": {"pierce": false}},
		{"id": "quickscope", "name": "Quickscope", "text": "No sway penalty for moving.", "erase": ["still"]}],
	"bazooka": [{"id": "tandem", "name": "Tandem", "text": "Fires 2 rockets.", "set": {"count": 2}},
		{"id": "heat", "name": "HEAT", "text": "+3 damage and +8 blast radius.", "add": {"dmg": 3, "radius": 8}}],
	"medkit": [{"id": "stimpack", "name": "Stim Pack", "text": "The patient also gets +1 energy.", "set": {"medenergy": 1}},
		{"id": "reach", "name": "Long Reach", "text": "+90 range.", "add": {"range": 90}}],
	"smoke": [{"id": "wall", "name": "Smoke Wall", "text": "+28 cloud radius.", "add": {"srad": 28.0}},
		{"id": "linger", "name": "Linger", "text": "Clouds last 2 more rounds.", "add": {"sturns": 2}}],
	"knife": [{"id": "lunge", "name": "Lunge", "text": "+40 reach.", "add": {"range": 40}},
		{"id": "serrated", "name": "Serrated", "text": "Marks the target.", "set": {"mark": true}}],
	"rifle": [{"id": "ap", "name": "AP Rounds", "text": "Pierces bodies.", "set": {"pierce": true}},
		{"id": "match", "name": "Match Grade", "text": "+2 damage, sway -40%.", "add": {"dmg": [2, 2]}, "mul": {"sway": 0.6}}],
	"mortar": [{"id": "airburst", "name": "Airburst", "text": "+14 blast radius.", "add": {"radius": 14}},
		{"id": "incendiary", "name": "Incendiary", "text": "Everything caught is Burning.", "set": {"burnblast": true}}],
}
const GEN_MODS := [
	{"id": "lean", "name": "Lean", "text": "Costs 1 less.", "add": {"cost": -1}},
	{"id": "echo", "name": "Echo", "text": "Draw a card when you play it.", "set": {"echo": 1}},
	{"id": "keen", "name": "Keen", "text": "+1 ricochet, 40% less sway.", "add": {"bounce": 1}, "mul": {"sway": 0.6}, "aim": true},
	{"id": "heavy", "name": "Heavy", "text": "Stronger: more damage, healing, armor or movement.", "heavy": true},
]
const MOD_PRICE := 45

# ---------------------------------------------------------------- Phase 5: campaign & extras
const DUOS := [
	{"pair": ["moss", "vee"], "card": "spotter", "holder": "vee"},
	{"pair": ["rook", "vee"], "card": "cannonball", "holder": "rook"},
	{"pair": ["hex", "rook"], "card": "adrenalcharge", "holder": "rook"},
	{"pair": ["hex", "moss"], "card": "ownet", "holder": "moss"},
	{"pair": ["moss", "rook"], "card": "shockawe", "holder": "rook"},
	{"pair": ["hex", "vee"], "card": "firestorm", "holder": "vee"},
]
const DUO_RANGE := 120.0

const EVOLUTIONS := [
	{"card": "hmg", "kit": "ammobelt", "into": "heavym"},
	{"card": "bazooka", "kit": "guidance", "into": "chaser"},
	{"card": "frag", "kit": "napalmmix", "into": "firebomb"},
	{"card": "rifle", "kit": "scope", "into": "lasergun"},
]

# Route stops between missions (W1). The Supply Depot is always on offer.
const STOPS := {
	"front": {"name": "STRAIGHT TO THE FRONT", "text": "No detour. The gate opens right on the next mission."},
	"depot": {"name": "SUPPLY DEPOT", "text": "The Quartermaster: cards, gear, services and the Armory."},
	"outpost": {"name": "ELITE OUTPOST", "text": "A short, hard fight against elite Jackals. Pays an Epic crate and a Boar part."},
	"powcamp": {"name": "POW CAMP", "text": "Free a camp: a free crate, 2 level-up rerolls and a gunsmith token."},
	"hospital": {"name": "FIELD HOSPITAL", "text": "Heal everyone to full and give back one dog tag each."},
}

# Camp choices: every camp revives the downed and heals a little, then the squad picks one of these.
const CAMP_PICKS := [
	{"id": "patch", "name": "PATCH UP", "text": "Everyone heals to full HP."},
	{"id": "upgrade", "name": "FIELD UPGRADE", "text": "Each soldier picks one card to go up a rarity tier."},
	{"id": "cache", "name": "SUPPLY CACHE", "text": "Dig up 60 scrip."},
	{"id": "quiet", "name": "LIE LOW", "text": "Alert drops to 0 and everyone gets +1 energy right now."},
]
const CAMP_HEAL := 0.25
# Detours (run structure step 5): the mid-level camp offers 3, each a short side stretch in the
# clearing right after camp. Each pays in a different currency, so elites are never the only good pick.
const DETOURS := {
	"elite": {"name": "ELITE OUTPOST", "pays": "EPIC GEAR + 2 BIO-PARTS", "icon": "ic_skull", "text": "Four elite Jackals, all with the same modifier, dug into the clearing. One of them carries the Rambo Bow."},
	"pow": {"name": "POW RESCUE", "pays": "A FREE RECRUIT OR A DOG TAG", "icon": "ic_cross", "text": "Three prisoners and two guards. Free all three in %d rounds or they are moved out."},
	"salvage": {"name": "SALVAGE YARD", "pays": "SALVAGE FOR HQ", "icon": "ic_bolt", "text": "Walk over wrecks to strip them, %d salvage each. Scavengers drift in every round. Leave whenever you like."},
	"cache": {"name": "SUPPLY CACHE", "pays": "SCRIP + A CARD PICK", "icon": "ic_coin", "text": "An easy fight: three Jackals sitting on a supply cache."},
	"colors": {"name": "STEAL THE COLORS", "pays": "%d SALVAGE FOR HQ", "icon": "ic_star", "text": "Their battle flag flies at the far end of the clearing. Grab it and carry it back to the green post. The carrier is slow, can't jet, and every Jackal goes for them."},
}
const COLORS_SALVAGE := 15
const POW_RESCUE_ROUNDS := 5

# HQ upgrades (run structure step 6): paid in Salvage, kept across runs. Ranks are bought in order.
# The Doc's Lab opens with the Doc's surgeries; the Memorial is free and fills itself.
const HQ_BUILDINGS := [
	{"id": "gate", "name": "GATE CONTROL", "ranks": ["The dial shows 3 biomes instead of 2.", "Reroll the dial once per HQ visit.", "Biome cards list their stretches and the boss's armor."]},
	{"id": "barracks", "name": "BARRACKS", "ranks": ["Choose from 3 recruits instead of 2.", "Recruits arrive at level 2.", "Recruits cost half."]},
	{"id": "armory", "name": "ARMORY", "ranks": ["+1 Luck at the start of every run.", "Quartermaster prices are 10% lower.", "Elite outposts pay Legendary gear."]},
	{"id": "mess", "name": "MESS HALL", "ranks": ["Camps heal 5 more HP.", "Start each run with 40 more scrip.", "Camps offer all 4 detours."]},
	{"id": "doc", "name": "DOC'S LAB", "ranks": ["Opens surgery: 1 implant slot per class.", "2 implant slots per class.", "3 implant slots per class."]},
	{"id": "motor", "name": "MOTOR POOL", "ranks": ["The SV-001 Slug is on call once per level.", "The Slug stays for 2 rounds.", "The Slug is on call twice per level."]},
]
const HQ_COST := [10, 20, 30]   # Salvage for rank 1, 2, 3
const BOSS_SALVAGE := 5         # every Boar you beat pays this much Salvage
const BOSS_BIO := 1             # ...and a Bio-part for the Doc

# The Doc's surgeries (step 7): installed on a CLASS, so every future soldier of that class has it
# and permadeath never erases it. Pure upgrades, no side effects: the only choice is what fills the slots.
# Any class can take any surgery. Slots per class = the Doc's Lab rank; past the cap the oldest comes out.
# "stats" feed the same bonus table gear uses (Run.gear_bonus); the rest have their own hooks in battle.
const SURGERIES := {
	"cybereye": {"name": "CYBER EYE", "cls": "", "up": "Aimed shots sway 25% less."},
	"thirdarm": {"name": "THIRD ARM", "cls": "", "up": "+1 hand size."},
	"asbestos": {"name": "ASBESTOS HIDE", "cls": "", "up": "Immune to your own explosions."},
	"spine": {"name": "TITANIUM SPINE", "cls": "", "up": "+6 max HP and no fall damage."},
	"adrenal": {"name": "ADRENAL PUMP", "cls": "", "up": "Start every fight at 25 adrenaline."},
	"magnet": {"name": "MAGNET HAND", "cls": "", "up": "Grab loot from 3x as far."},
	"legs": {"name": "HYDRAULIC LEGS", "cls": "", "up": "+40 movement every turn.", "stats": {"move": 40}},
	"reflex": {"name": "REFLEX WIRING", "cls": "", "up": "+8 dodge.", "stats": {"dodge": 8}},
	"plating": {"name": "SUBDERMAL PLATING", "cls": "", "up": "3 armor every turn.", "stats": {"armor_turn": 3}},
	"regen": {"name": "REGEN GLAND", "cls": "", "up": "Heal 2 HP every turn.", "stats": {"regen": 2}},
	"chip": {"name": "TARGETING CHIP", "cls": "", "up": "+2 damage on every aimed shot.", "stats": {"aim_dmg": 2}},
	"boom": {"name": "BLAST AMPLIFIER", "cls": "", "up": "Your explosions are 20% bigger.", "stats": {"blast": 0.2}},
	"instinct": {"name": "KILLER INSTINCT", "cls": "", "up": "Kills give 10 more adrenaline.", "stats": {"kill_adr": 10}},
	"medchip": {"name": "MED CHIP", "cls": "", "up": "Your heals restore 3 more HP.", "stats": {"heal": 3}},
}
const SURGERY_BIO := 2
const SURGERY_SALVAGE := 5
const WRECK_SALVAGE := 3
const ELITE_BIO := 2     # share of max HP everyone gets back just for reaching camp

# Briefing intel (W2): each mission rolls one condition.
const INTEL := {
	"clear": {"name": "CLEAR SKIES", "text": "No surprises.", "w": 3},
	"monsoon": {"name": "MONSOON", "text": "Everything is soaked: fire does 1 damage and doesn't spread.", "w": 2},
	"fog": {"name": "FOG", "text": "Jackals see 30% less far.", "w": 2},
	"surplus": {"name": "SURPLUS", "text": "Twice the crates on the map.", "w": 2},
	"veterans": {"name": "VETERAN JACKALS", "text": "Far more elites, and +2 Luck for this mission.", "w": 2},
}

# Radio relays (W3): end a turn standing on one to capture it. Alert +1.
const RELAY_BUFFS := {
	"hand": {"name": "SIGNAL BOOST", "text": "+1 card in hand for the squad this mission."},
	"luck": {"name": "INTERCEPT", "text": "+2 Luck this mission."},
	"intel": {"name": "SIGINT", "text": "Enemy intents always shown this mission."},
}
const RELAY_HOLD := 3  # O4: end this many turns on a relay to lock it; waves come in while you hold

# Armory unlock feats (W4), kept across runs.
const FEATS := [
	{"id": "timber", "name": "TIMBER!", "text": "Crush 3 Jackals in one action.", "n": 1, "item": "boarplate"},
	{"id": "skeet", "name": "PULL!", "text": "Score 3 SKEETs.", "n": 3, "item": "skeetvest"},
	{"id": "pinball", "name": "TILT", "text": "Score 5 PINBALLs.", "n": 5, "item": "deflector"},
	{"id": "pyro", "name": "SMOKEY", "text": "Kill 3 Jackals with fire.", "n": 3, "item": "zippo"},
	{"id": "medals", "name": "DECORATED", "text": "Earn all 4 medals in one mission.", "n": 1, "item": "medalcase"},
	{"id": "winrun", "name": "THE ROAD EAST", "text": "Win a campaign.", "n": 1, "item": "antimat"},
]

# Threat levels (W5): unlocked by winning; each adds to the ones below it.
const THREATS := [
	{"name": "JUMPY", "text": "Alert climbs after 1 stalled round instead of 2."},
	{"name": "ELITE CORPS", "text": "+15% elite Jackals."},
	{"name": "SHORT SUPPLY", "text": "-1 card in hand."},
	{"name": "HARDENED", "text": "Jackals have +20% HP."},
	{"name": "BOAR MK II", "text": "The Iron Boar has +40% HP and armor."},
]

# Commander perks (P5): one squad-wide pick after each mission win.
const COMMANDS := [
	{"id": "doubledown", "name": "Double Down", "text": "Your next level-up lets you take two of the three options."},
	{"id": "brothers", "name": "Brothers in Arms", "text": "Tag-team combos also draw a card."},
	{"id": "supply", "name": "Supply Lines", "text": "+1 belt slot."},
	{"id": "tempo", "name": "Tempo", "text": "On round 1 of each mission, Momentum pays out every 2 cards."},
	{"id": "decorated", "name": "Decorated", "text": "+1 supply crate after every mission."},
	{"id": "rabbit", "name": "Rabbit's Foot", "text": "+2 Luck."},
	{"id": "warchest", "name": "War Chest", "text": "Kills pay 50% more scrip."},
	{"id": "killstreak", "name": "Killstreak", "text": "Kill combo rewards come at x2 and x4."},
	{"id": "veterans", "name": "Veterans", "text": "+25% XP."},
]

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
	{"id": "dogtags", "icon": "ic_skull", "name": "Service Medal", "text": "Kills give 50% more XP.", "price": 80},
	{"id": "stimpack", "icon": "ic_flame", "name": "Adrenal Pump", "text": "Adrenaline builds 50% faster.", "price": 90},
]

const XP_LEVELS := [0, 14, 34, 60, 92, 130, 175, 230]

const ETYPES := {
	"grunt": {"name": "Jackal Rifleman", "hp": 12, "dmg": [3, 5], "range": 460, "speed": 120, "prefer": 240, "nade": 0.35, "score": 100, "w": 16, "h": 34, "note": "Advances, vaults low walls, and lobs a grenade when it has no shot."},
	"shield": {"name": "Riot Jackal", "hp": 16, "dmg": [3, 4], "range": 340, "speed": 95, "prefer": 140, "shield": true, "score": 150, "w": 18, "h": 34, "note": "Shield soaks 75% of bullets from the front. Ricochet behind it, or blow it up."},
	"nade": {"name": "Jackal Bomber", "hp": 10, "arc": true, "dmg": 9, "radius": 32, "range": 480, "speed": 100, "prefer": 380, "score": 150, "w": 16, "h": 34, "note": "Lobs grenades over cover. Aim tightens as alert rises."},
	"brute": {"name": "Jackal Brute", "hp": 20, "acc": 85, "melee": true, "smash": true, "dmg": [9, 12], "speed": 190, "score": 200, "w": 22, "h": 44, "note": "Charges 190px and smashes through walls. Its machete sends you flying."},
	"jetter": {"name": "Jet Jackal", "hp": 10, "dmg": [3, 5], "range": 480, "speed": 90, "prefer": 240, "jet": 300, "score": 175, "w": 16, "h": 34, "note": "Jets up to the highest roof within 300px and shoots down. Hit it in flight and it crashes."},
	"mg": {"name": "MG Nest", "hp": 24, "dmg": [2, 3], "shots": 4, "range": 520, "static": true, "heavy": true, "score": 250, "w": 28, "h": 24, "note": "Static. Four rounds a turn. Too heavy to launch."},
	"radio": {"name": "Jackal Radioman", "hp": 10, "dmg": [2, 3], "range": 380, "speed": 60, "prefer": 520, "radio": true, "score": 200, "w": 16, "h": 34, "note": "Calls in paratroopers when his timer hits zero. Kill him to stop it."},
	"engineer": {"name": "Jackal Engineer", "hp": 12, "dmg": [2, 3], "range": 360, "speed": 80, "prefer": 320, "builds": true, "score": 150, "w": 16, "h": 34, "note": "Builds concrete walls for the Jackal line."},
	"sapper": {"name": "Jackal Sapper", "hp": 11, "speed": 150, "sapper": true, "score": 175, "w": 16, "h": 34, "note": "Runs in and plants a charge that blows next turn. Shoot the charge to defuse it."},
	"mortarcrew": {"name": "Mortar Crew", "hp": 18, "arc": true, "heavyArc": true, "dmg": 12, "radius": 46, "range": 900, "speed": 0, "score": 250, "w": 18, "h": 34, "note": "Shells your cover from long range. Sits still. Something is hanging over it."},
	# Vharr aliens. Like the Jackals they move and attack in the same enemy phase, and
	# "weight" sets how physics moves them: light flies twice as far, hover holds altitude on a pod.
	"skitter": {"name": "Skitter", "faction": "vharr", "weight": "light", "hp": 6, "dmg": 4, "leap": 240, "speed": 140, "climb": true, "pack": 3, "score": 60, "w": 28, "h": 18, "note": "Comes in packs. Scrambles up walls and pounces from 240px. Light: flies twice as far when knocked."},
	"squid": {"name": "Squid Trooper", "faction": "vharr", "weight": "hover", "hp": 8, "pod": 8, "dmg": 4, "range": 520, "speed": 110, "prefer": 300, "alt": 110, "score": 150, "w": 36, "h": 46, "note": "Hovers on a saucer pod. Its ray goes through one thin wall and hits everything on the line. Break the pod and it drops."},
	"blinker": {"name": "Blinker", "faction": "vharr", "hp": 10, "dmg": 7, "knock": 4.5, "speed": 60, "score": 175, "w": 22, "h": 60, "note": "Teleports behind the nearest soldier within 360px and claws them."},
	"burrower": {"name": "Burrower", "faction": "vharr", "weight": "buried", "hp": 16, "dmg": 9, "tunnel": 300, "score": 175, "w": 30, "h": 56, "note": "Tunnels up to 300px under the ground, digging a trench, then bursts out under you. Bullets can't reach it while buried; blasts on the ground above can."},
	"grappler": {"name": "Grappler", "faction": "vharr", "hp": 22, "dmg": 6, "range": 360, "yank": 200, "speed": 40, "heavy": true, "score": 200, "w": 50, "h": 44, "note": "Heavy. Shoots its tongue at anyone in a clear line within 360px and yanks them up to 200px toward it, over ledges and into mines. Cover breaks the line."},
	"bloater": {"name": "Bloater", "faction": "vharr", "hp": 18, "dmg": 12, "speed": 80, "radius": 40, "score": 150, "w": 40, "h": 46, "note": "Swells every turn and pops when it reaches you. Kill it and it pops anyway: knock it into its friends first. Blast radius grows from 40 to 80."},
	"weaver": {"name": "Dome Weaver", "faction": "vharr", "hp": 10, "dmg": [2, 3], "range": 420, "speed": 70, "prefer": 300, "score": 175, "w": 26, "h": 56, "note": "Hangs back and covers an ally with a dome that stops bullets and blasts for 2 turns. Melee, crushing and slams go through. Kill the Weaver first."},
	"queen": {"name": "Burrow Queen", "faction": "vharr", "weight": "buried", "hp": 70, "heavy": true, "tunnel": 380, "burst": 9, "bite": 10, "spit": 5, "score": 1500, "w": 60, "h": 84, "note": "Mini-boss. Tunnels under the arena, digging it up as she goes, and bursts out under you. Surfaced she bites or spits acid, then dives. Underground only blasts reach her: hit her while she's up, and drop rubble on her head for triple damage."},
	"prism": {"name": "Prism Drone", "faction": "vharr", "weight": "hover", "hp": 12, "pod": 6, "dmg": 3, "range": 460, "speed": 60, "prefer": 260, "alt": 90, "score": 150, "w": 30, "h": 36, "note": "Floats slowly and turns its mirror toward you. Bullets that hit the mirror bounce off at the mirrored angle: bank shots off it. Hit it from behind, or use ARC and MELEE."},
	"warden": {"name": "Gravity Warden", "faction": "vharr", "hp": 14, "dmg": 3, "speed": 60, "prefer": 340, "well": 140, "pull": 60, "score": 175, "w": 30, "h": 50, "note": "Keeps its distance and drops a gravity well on the squad. Everything in the well is pulled to its center each turn, and ARC shots bend toward it. Kill the Warden and the well collapses with a small blast."},
	"stalker": {"name": "Phase Stalker", "faction": "vharr", "hp": 14, "dmg": 8, "speed": 140, "phase_move": 240, "score": 175, "w": 24, "h": 54, "note": "Phased every other turn: it walks through walls and bullets pass through it, blasts still hit. If it turns solid inside rock it is crushed, so bring the ceiling down on it."},
	"overseer": {"name": "Overseer", "faction": "vharr", "weight": "hover", "hp": 26, "pod": 10, "crash": 30, "dmg": 4, "range": 460, "speed": 70, "alt": 120, "links": 2, "score": 300, "w": 34, "h": 44, "note": "A brain in a floating tank that hides behind its Jackals and turns two of them into Thralls. Kill it and the links break, stunning the freed Jackals. Break the tank's pod and the fall shatters it."},
	"hive": {"name": "Hive Pod", "faction": "vharr", "hp": 20, "static": true, "heavy": true, "hatch": 2, "brood": 2, "score": 200, "w": 26, "h": 26, "note": "Hatches two Skitters when its timer runs out. Bursts into acid when killed: anyone standing in it at the end of the enemy phase takes 3."},
	"burrow": {"name": "Skitter Tunnel", "faction": "vharr", "hp": 14, "static": true, "heavy": true, "waves": [3, 4, 3], "score": 150, "w": 30, "h": 14, "note": "Sends a wave of Skitters each enemy phase (the next wave's size is shown), then caves in. Blow it up to stop the swarm."},
	# Q1: the level boss in the delta and the harbor from level 2. It floats over the arena on armor
	# plates hung from tethers; it sweeps a ray across the ground and drops pods full of Vharr.
	"hiveship": {"name": "HIVE SHIP", "faction": "vharr", "weight": "hover", "hp": 150, "alt": 230, "heavy": true, "speed": 150, "beam": 5, "sweep": 150, "beam_range": 420, "pod_dmg": 7, "score": 3000, "w": 150, "h": 44, "note": "Mothership. Floats over the arena, sweeps a ray across the ground and drops pods of Vharr on you. While its armor plates hang on, shots do 40%: shoot a plate off its tethers and it drops on whoever is under it. Blasts that reach its belly always do full damage."},
	"shipplate": {"name": "Hull Plate", "faction": "vharr", "hp": 14, "static": true, "heavy": true, "score": 100, "w": 44, "h": 12, "note": "Armor hanging under the Hive Ship. Shoot it off its tethers: it falls like a girder and crushes whatever is under it. With every plate gone the ship takes +30% damage."},
	"droppod": {"name": "Drop Pod", "faction": "vharr", "hp": 10, "static": true, "heavy": true, "score": 50, "w": 24, "h": 26, "note": "Crashed down full of Vharr. It opens on the next enemy phase and they come out swinging. Break it first and they die inside."},
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
#   catwalk: x0, x1, dy above the ground. A steel grating deck on legs every `leg` px (default 96):
#           you stand on it, bullets, rockets and grenades go through it. Ladder at the near end.
#   fence:  x, h. Chain-link: blocks people (too tall for a Jackal to vault), not bullets or grenades.
const SEGMENTS := {
	"start": {"w": 460, "sandbags": [420], "structs": [], "pits": [], "spawns": []},
	"towers": {"w": 840, "sandbags": [600], "pits": [[700, 776]],
		"structs": [{"t": "over", "px": 136, "x0": 136, "x1": 244, "h": 70}, {"t": "tower", "x": 380, "h": 96}],
		"spawns": [["barrel", 124], ["grunt", 200, {"top": 1}], ["grunt", 380, {"hold": 1}], ["nade", 470], ["jetter", 560]]},
	"boulder": {"w": 700, "sandbags": [710], "pits": [],
		"structs": [{"t": "boulder", "col": 150, "colH": 150, "bx": 232, "rope": 22, "r": 22}],
		"spawns": [["pow", 20], ["grunt", 162, {"hold": 1}], ["mg", 236], ["shield", 310], ["brute", 360], ["nade", 420], ["radio", 490]]},
	"bunker": {"w": 700, "sandbags": [], "pits": [[620, 696]],
		"structs": [{"t": "bunker", "x": 140, "w": 84, "h": 48}, {"t": "ledge", "x": 360, "w": 96, "dy": 96, "post": 440}],
		"spawns": [["barrel", 96], ["barrel", 112], ["mg", 182], ["grunt", 182, {"hold": 1, "inside": 1}], ["fuel", 252], ["grunt", 396], ["engineer", 420], ["brute", 480], ["radio", 560]]},
	"overhang": {"w": 800, "sandbags": [], "pits": [],
		"structs": [{"t": "over", "px": 224, "x0": 224, "x1": 400, "h": 76}, {"t": "tower", "x": 540, "h": 100}, {"t": "ledge", "x": 720, "w": 100, "dy": 112, "post": 766}],
		"spawns": [["pow", 100], ["shield", 310, {"hold": 1}], ["shield", 380], ["sapper", 460], ["brute", 490], ["nade", 540, {"hold": 1}], ["jetter", 600], ["radio", 640]]},
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
		"structs": [{"t": "bridge", "x0": 240, "x1": 440, "posts": [290, 340, 390]}],
		"spawns": [["pow", 110], ["grunt", 315, {"hold": 1}], ["shield", 365], ["barrel", 470], ["nade", 560, {"hold": 1}], ["grunt", 620], ["radio", 670]]},
	# a raised jungle ridge sown with mines
	"ridge": {"w": 820, "sandbags": [], "pits": [],
		"ground": [{"x0": 260, "x1": 600, "dh": 46, "ramp": 0}, {"x0": 600, "x1": 640, "dh": 46, "ramp": 90}],
		"structs": [{"t": "tower", "x": 470, "h": 70}],
		"spawns": [["mine", 140], ["mine", 196], ["grunt", 300, {"hold": 1}], ["mine", 352], ["nade", 410, {"hold": 1}], ["pow", 440], ["grunt", 470, {"hold": 1}], ["mine", 530], ["nade", 600], ["mine", 690], ["sapper", 720], ["radio", 780]]},
	# the long river bridge, mortar fire from the far bank
	"river": {"w": 960, "sandbags": [590], "pits": [],
		"structs": [{"t": "bridge", "x0": 180, "x1": 500, "posts": [236, 292, 348, 404, 452]}, {"t": "ledge", "x": 680, "w": 96, "dy": 92, "post": 760}],
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
	# a refinery yard under steel catwalks: shoot up through the grating, drop grenades down through it
	"catwalks": {"w": 860, "sandbags": [120], "pits": [],
		"structs": [{"t": "catwalk", "x0": 220, "x1": 500, "dy": 84}, {"t": "catwalk", "x0": 560, "x1": 720, "dy": 138, "leg": 80}],
		"spawns": [["grunt", 300, {"hold": 1, "up": 100}], ["nade", 440, {"hold": 1, "up": 100}], ["fuel", 360], ["grunt", 400], ["shield", 520],
			["grunt", 650, {"hold": 1, "up": 150}], ["brute", 690], ["jetter", 760], ["radio", 800]]},
	# a chain-link perimeter: they can shoot you through it and you them, but nobody walks through
	"fenceline": {"w": 820, "sandbags": [150], "pits": [],
		"structs": [{"t": "fence", "x": 280, "h": 72}, {"t": "fence", "x": 560, "h": 72}, {"t": "catwalk", "x0": 620, "x1": 740, "dy": 96}],
		"spawns": [["grunt", 330, {"hold": 1}], ["shield", 380], ["barrel", 420], ["nade", 470, {"hold": 1}], ["grunt", 520], ["brute", 600],
			["grunt", 680, {"hold": 1, "up": 110}], ["radio", 780]]},
	# B6: a sandbagged M2 anyone standing at can fire, held by a Jackal gunner
	"m2nest": {"w": 720, "sandbags": [300, 560], "pits": [], "structs": [],
		"spawns": [["m2", 330], ["grunt", 352, {"hold": 1}], ["barrel", 420], ["grunt", 470], ["shield", 520], ["m2", 590], ["nade", 640, {"hold": 1}], ["radio", 690]]},
	# a safe camp inside the level: a fire, two tents and a supply crate, no Jackals
	# D5: the HQ practice range. Dummies on the flat, one up the tower, one behind a shield
	"range": {"w": 820, "sandbags": [], "pits": [], "structs": [{"t": "tower", "x": 440, "h": 96}],
		"spawns": [["grunt", 200], ["barrel", 290], ["shield", 340], ["grunt", 440, {"hold": 1}], ["grunt", 580], ["mg", 700]]},
	"camp": {"w": 560, "sandbags": [60, 500], "pits": [], "camp": true, "structs": [], "spawns": []},
	# the open clearing after the mid-level camp, where a detour plays out (empty if you press on)
	"yard": {"w": 760, "sandbags": [], "pits": [], "yard": true, "structs": [], "spawns": []},
	"arena": {"w": 1200, "sandbags": [120, 360], "pits": [], "flat": true,
		"structs": [{"t": "tower", "x": 580, "h": 96}, {"t": "tower", "x": 760, "h": 110}, {"t": "boulder", "col": 850, "colH": 236, "bx": 960, "rope": 18, "r": 32}],
		"spawns": [["grunt", 580, {"hold": 1}], ["grunt", 760, {"hold": 1}], ["boss", 960]]},
	# the harbor's boss arena: the flagship BOAR parks under a loaded crane
	"pier": {"w": 1200, "sandbags": [120, 360], "pits": [], "flat": true,
		"structs": [{"t": "tower", "x": 560, "h": 96}, {"t": "ledge", "x": 700, "w": 96, "dy": 100, "post": 780}, {"t": "crane", "x": 1080, "h": 230, "jib": 880, "hook": 960, "rope": 30, "cw": 72, "ch": 34}],
		"spawns": [["grunt", 560, {"hold": 1}], ["nade", 740, {"hold": 1, "up": 120}], ["mine", 640], ["mine", 840], ["boss", 960]]},
}

const MISSIONS := [
	{"name": "THE JACKAL LINE", "theme": "dusk", "segments": ["start", "trenches", "fort", "camp", "gully", "boulder", "camp", "arena"],
	 "boss_hp": 120, "plate": 36, "hp_mul": 1.0, "brief": "Clear the trenches, storm the outpost and cross the gully before the IRON BOAR closes the road east."},
	{"name": "RIVER CROSSING", "theme": "jungle", "segments": ["start", "ridge", "overhang", "camp", "river", "mortar", "camp", "arena"],
	 "boss_hp": 160, "plate": 46, "hp_mul": 1.15, "brief": "The ridge is mined and the river bridge is held. Their second BOAR is waiting at the ford."},
	{"name": "IRON HARBOR", "theme": "night", "segments": ["start", "docks", "warehouse", "camp", "gauntlet", "fort", "camp", "pier"],
	 "boss_hp": 210, "plate": 60, "hp_mul": 1.3, "brief": "Night raid on the harbor. Fight along the piers, gut the warehouse, and drop a crane load on the flagship BOAR."},
]

# ---------------------------------------------------------------- biomes (run structure step 4)
# A level is one biome. At HQ the gate dial offers two biomes from that level's pool; the one you
# skip is burned for the run. Every biome pays the same. What changes is which builds it suits:
# "favor" and "rough" name a fighting style (long, close, arc) and every rule below is real.
#   sway: your aimed shots' sway   sight: how far Jackals see   wind: wind strength
#   amp: how hilly the ground is   wet: fire does 1 damage and won't spread
#   fuel / mines: extra fuel barrels / mines on the map   elite: extra chance a Jackal is elite
#   ice / tarps / wires: sheets of ice, rubber tarps and live wires on the map
# "look" tints the level: tint and grass go to the terrain, sky modulates the backdrop.
const STYLES := {"long": "LONG GUNS", "close": "CLOSE QUARTERS", "arc": "EXPLOSIVES"}
const BIOMES := {
	"desert": {"name": "DESERT RUINS", "theme": "dusk", "favor": "long", "rough": "close",
		"rules": {"sway": 0.6, "sight": 1.2, "amp": 0.4, "wind": 1.5},
		"look": {"tint": Color(1.08, 0.98, 0.82), "grass": Color("c8a85a"), "sky": Color(1.0, 0.92, 0.78)},
		"segments": ["trenches", "towers", "boulder", "gully", "overhang", "fenceline", "m2nest"],
		"text": "Flat sand and clear air. Your aimed shots sway 40% less, but Jackals see 20% farther."},
	"fortress": {"name": "FORTRESS TOWN", "theme": "dusk", "favor": "arc", "rough": "long",
		"rules": {"sway": 1.3, "fuel": 2, "wires": 1},
		"look": {"tint": Color(0.9, 0.9, 0.94), "grass": Color("7a8a5a"), "sky": Color(0.86, 0.86, 0.92)},
		"segments": ["fort", "warehouse", "bunker", "gauntlet", "fort", "fenceline", "m2nest"],
		"text": "Forts and warehouses wall to wall. Blow the floors out. Aimed shots sway 30% more. A live wire hums on the ground: shoot its junction box to cut it."},
	"jungle": {"name": "JUNGLE CANOPY", "theme": "jungle", "favor": "close", "rough": "long",
		"rules": {"sway": 1.4, "sight": 0.7, "mines": 3},
		"look": {},
		"segments": ["ridge", "overhang", "gully", "boulder"],
		"text": "Thick cover and buried mines. Jackals see 30% less far. Aimed shots sway 40% more."},
	"delta": {"name": "FLOODED DELTA", "theme": "jungle", "favor": "close", "rough": "arc",
		"rules": {"wet": true, "wind": 0.3, "mines": 2, "tarps": 2},
		"look": {"tint": Color(0.86, 0.98, 1.04), "grass": Color("3a9a6a"), "sky": Color(0.84, 0.94, 1.0)},
		"segments": ["river", "gully", "ridge", "docks", "catwalks"],
		"text": "Everything is soaked: fire does 1 damage and won't spread. Barely any wind. Rubber tarps bounce soldiers and grenades."},
	"refinery": {"name": "OIL REFINERY", "theme": "dusk", "favor": "arc", "rough": "close",
		"rules": {"fuel": 5, "sight": 1.1, "wires": 2},
		"look": {"tint": Color(1.06, 0.9, 0.8), "grass": Color("8a7a3a"), "sky": Color(1.0, 0.8, 0.66)},
		"segments": ["bunker", "mortar", "warehouse", "towers", "catwalks"],
		"text": "Fuel drums everywhere. Light them up, and don't stand next to one. Jackals see 10% farther. Live wires hum on the ground: shoot the junction box to cut one."},
	"mountain": {"name": "MOUNTAIN PASS", "theme": "dusk", "favor": "long", "rough": "arc",
		"rules": {"amp": 2.0, "wind": 2.0, "sway": 0.8, "grav": 0.75, "ice": 2},
		"look": {"tint": Color(0.92, 0.96, 1.06), "grass": Color("6a9a5a"), "sky": Color(0.84, 0.9, 1.04)},
		"segments": ["ridge", "boulder", "overhang", "towers", "trenches"],
		"text": "Steep hills, a gale and thin air. Double wind. Gravity is 25% lower: jumps, jets, grenades and knockback all carry further. Aimed shots sway 20% less. Sheets of ice: whatever lands on them keeps sliding."},
	"harbor": {"name": "NIGHT HARBOR", "theme": "night", "favor": "long", "rough": "arc", "arena": "pier",
		"rules": {"sight": 0.8, "wind": 1.6, "tarps": 1},
		"look": {},
		"segments": ["docks", "warehouse", "gauntlet", "mortar", "catwalks", "m2nest"],
		"text": "Piers in the dark and a sea wind. Jackals see 20% less far. Wind is 60% stronger. A rubber tarp bounces soldiers and grenades."},
	"palace": {"name": "NINJA PALACE", "theme": "night", "favor": "close", "rough": "long",
		"rules": {"sway": 1.6, "sight": 0.6, "elite": 0.2},
		"look": {"tint": Color(0.86, 0.62, 0.7), "grass": Color("5a4a6a"), "sky": Color(1.0, 0.7, 0.8)},
		"segments": ["fort", "overhang", "gauntlet", "warehouse"],
		"text": "Paper walls and shadows. Jackals see 40% less far, but more of them are elite. Aimed shots sway 60% more."},
}
# Each level of a run has its own pool. Played and burned biomes never come back.
# Which Vharr fill the rifleman slots in each biome (Z on the alien page).
const BIOME_ALIENS := {
	"desert": ["skitter", "burrower", "squid", "warden"],
	"fortress": ["blinker", "skitter", "weaver", "prism"],
	"jungle": ["grappler", "skitter", "blinker", "stalker"],
	"delta": ["squid", "bloater", "skitter", "prism"],
	"refinery": ["bloater", "weaver", "squid", "warden"],
	"mountain": ["squid", "burrower", "blinker", "warden"],
	"harbor": ["squid", "grappler", "bloater", "prism"],
	"palace": ["stalker", "weaver", "skitter", "blinker"],
}

const LEVELS := [
	{"pool": ["desert", "fortress", "jungle", "delta", "refinery", "mountain"], "hp_mul": 1.0, "boss_hp": 120, "plate": 36},
	{"pool": ["desert", "fortress", "jungle", "delta", "refinery", "mountain", "harbor", "palace"], "hp_mul": 1.15, "boss_hp": 160, "plate": 46},
	{"pool": ["desert", "fortress", "jungle", "delta", "refinery", "mountain", "harbor", "palace"], "hp_mul": 1.3, "boss_hp": 210, "plate": 60},
]
# After the third level: one fixed fight against the Jackal flagship.
const FINALE := {"name": "IRON HARBOR", "theme": "night", "segments": ["start", "docks", "pier"], "finale": true,
	"boss_hp": 260, "plate": 70, "hp_mul": 1.4, "brief": "The last gate opens on the harbor. The Jackal flagship BOAR is loading out. Sink it and the war is over."}

# ---------------------------------------------------------------- campaign mode (K3)
# The campaign is five acts. Each act is one front map: a landing zone you start on, six sectors
# and a stronghold. Any sector that touches one you hold is open (M1). Take "need" of them and the
# stronghold opens; beat it and the war moves to the next act. Held sectors pay something after
# every op for the rest of the war (M2), or give a perk that lasts for their act (M3).
# Positions are screen coordinates on the War Room map. "tier" picks the enemy mix (0 = mostly
# Jackals, 1 = Vharr arriving, 2 = Vharr everywhere) and hp_mul / boss_hp / plate set the numbers.
const CAMP_SLOTS := 3
const CAMP_START_SCRIP := 120
const CAMP_THREAT_PAY := 0.2      # each threat level picked for an op adds 20% to its pay (P3)
const PATROL_PAY := 0.5           # replaying a held sector pays half (M5)
const SECTOR_PERKS := {
	"aid": {"name": "FIELD HOSPITAL", "text": "Camps heal 5 more HP on every op this act."},
	"lookout": {"name": "LOOKOUT POST", "text": "+1 Luck on every op this act."},
	"fuel": {"name": "FUEL DEPOT", "text": "The SV-001 Slug is on call on every op this act."},
	"supply": {"name": "SUPPLY DUMP", "text": "Quartermaster prices are 10% lower this act."},
	"airfield": {"name": "AIRSTRIP", "text": "Twice the crates on the map on every op this act."},
}
# O1-O6: what an op on the war map asks of the squad. Strongholds are always a push to the boss.
const JOBS := {
	"push": {"name": "PUSH", "goal": "BREAK THROUGH", "text": "Fight to the far end and knock out the sector's armor."},
	"rescue": {"name": "RESCUE", "goal": "FREE 3 PRISONERS", "text": "Three of ours are held across the sector. Walk up to each one to cut them loose."},
	"demolish": {"name": "DEMOLISH", "goal": "DESTROY 3 TARGETS", "text": "Blow up three supply dumps. Blasts do double damage to them."},
	"hold": {"name": "HOLD", "goal": "HOLD THE FAR END", "text": "Reach the far end, then survive %d enemy phases while they come from both sides."},
	"escort": {"name": "ESCORT", "goal": "GET THE TRUCK THROUGH", "text": "A supply truck rolls forward each enemy phase, but stops while Jackals are close ahead. Keep it alive."},
	"hunt": {"name": "HUNT", "goal": "KILL THE TARGET", "text": "A named Jackal officer is somewhere in the sector. Kill them and take what they carry."},
}
const QUARRY_NAMES := ["MAJOR KROLL", "THE BUTCHER", "COLONEL VASK", "IRON MARTA", "THE SURGEON", "CAPTAIN RUST"]
const HOLD_PHASES := 5
const TARGET_HP := 40
const TRUCK_HP := 70
const TRUCK_STEP := 90.0
const JOB_PAY := 40   # scrip for finishing a job op that isn't a push
const ACTS := [
	{"id": "landfall", "name": "LANDFALL", "roman": "I", "tier": 0, "hp_mul": 1.0, "boss_hp": 120, "plate": 36, "need": 3, "breach": 0.0,
	 "text": "Hit the beach at the delta and push into the jungle. Plain war against the Jackals.",
	 "lz": {"name": "BEACHHEAD", "at": [70, 380]},
	 "sectors": [
		{"id": "d1", "name": "MUDFLAT LANDING", "biome": "delta", "job": "push", "at": [190, 380], "links": ["lz", "d2", "d3"], "hold": {"scrip": 20}},
		{"id": "d2", "name": "RICE TERRACES", "biome": "delta", "job": "rescue", "at": [280, 270], "links": ["d1", "j1", "j2"], "perk": "aid"},
		{"id": "d3", "name": "FERRY DOCKS", "biome": "delta", "job": "demolish", "at": [340, 410], "links": ["d1", "j2"], "hold": {"salvage": 2}},
		{"id": "j1", "name": "SIGNAL RIDGE", "biome": "jungle", "job": "hold", "at": [230, 160], "links": ["d2", "j3"], "perk": "lookout"},
		{"id": "j2", "name": "RIVER BATTERY", "biome": "jungle", "job": "demolish", "at": [440, 300], "links": ["d2", "d3", "boss"], "hold": {"scrip": 20}},
		{"id": "j3", "name": "TEMPLE TRAIL", "biome": "jungle", "job": "hunt", "at": [400, 150], "links": ["j1", "boss"], "hold": {"bio": 1}},
		{"id": "boss", "name": "BOAR'S DEN", "biome": "jungle", "at": [580, 220], "links": ["j2", "j3"], "stronghold": true}]},
	{"id": "breach", "name": "THE BREACH", "roman": "II", "tier": 1, "hp_mul": 1.15, "boss_hp": 160, "plate": 46, "need": 3, "breach": 0.4,
	 "text": "Desert ruins and the mountain pass. The Jackals made a deal with something that came through their gate.",
	 "lz": {"name": "AIRDROP ZONE", "at": [80, 200]},
	 "sectors": [
		{"id": "s1", "name": "BROKEN AQUEDUCT", "biome": "desert", "job": "escort", "at": [200, 150], "links": ["lz", "s2", "s3"], "hold": {"scrip": 25}},
		{"id": "s2", "name": "SALT FLATS", "biome": "desert", "job": "hold", "at": [220, 330], "links": ["s1", "m1"], "perk": "airfield"},
		{"id": "s3", "name": "SUNKEN TEMPLE", "biome": "desert", "job": "rescue", "at": [350, 180], "links": ["s1", "m1", "m2"], "hold": {"bio": 1}},
		{"id": "m1", "name": "SWITCHBACKS", "biome": "mountain", "job": "escort", "at": [380, 360], "links": ["s2", "s3", "m3"], "hold": {"salvage": 3}},
		{"id": "m2", "name": "OBSERVATORY", "biome": "mountain", "job": "hunt", "at": [480, 130], "links": ["s3", "boss"], "perk": "lookout"},
		{"id": "m3", "name": "CABLE CAR STATION", "biome": "mountain", "job": "demolish", "at": [520, 330], "links": ["m1", "boss"], "perk": "fuel"},
		{"id": "boss", "name": "THE QUEEN'S PIT", "biome": "desert", "at": [600, 220], "links": ["m2", "m3"], "stronghold": true, "queen": true}]},
	{"id": "pact", "name": "A BAD PACT", "roman": "III", "tier": 2, "hp_mul": 1.3, "boss_hp": 210, "plate": 60, "need": 3, "breach": 0.8,
	 "text": "The refinery and the fortress towns. The pact is cracking and Jackals and Vharr are shooting each other.",
	 "lz": {"name": "RAIL YARD", "at": [70, 300]},
	 "sectors": [
		{"id": "r1", "name": "PUMP STATION", "biome": "refinery", "job": "demolish", "at": [190, 220], "links": ["lz", "r2", "f1"], "hold": {"salvage": 3}},
		{"id": "r2", "name": "CRACKING TOWERS", "biome": "refinery", "job": "hold", "at": [300, 120], "links": ["r1", "r3"], "perk": "fuel"},
		{"id": "r3", "name": "TANK FARM", "biome": "refinery", "job": "escort", "at": [450, 140], "links": ["r2", "boss"], "hold": {"scrip": 30}},
		{"id": "f1", "name": "MARKET STREET", "biome": "fortress", "job": "rescue", "at": [220, 390], "links": ["r1", "f2"], "perk": "supply"},
		{"id": "f2", "name": "OLD CITADEL", "biome": "fortress", "job": "hunt", "at": [370, 330], "links": ["f1", "f3"], "hold": {"bio": 2}},
		{"id": "f3", "name": "GARRISON GATE", "biome": "fortress", "job": "push", "at": [500, 400], "links": ["f2", "boss"], "perk": "aid"},
		{"id": "boss", "name": "THE INFESTED WORKS", "biome": "refinery", "at": [590, 270], "links": ["r3", "f3"], "stronghold": true}]},
	{"id": "hive", "name": "HIVE TIDE", "roman": "IV", "tier": 2, "hp_mul": 1.45, "boss_hp": 240, "plate": 66, "need": 3, "breach": 0.5,
	 "text": "The palace and the night harbor. A Hive Ship parks over the coast and seeds nests everywhere.",
	 "lz": {"name": "CLIFF ROAD", "at": [70, 170]},
	 "sectors": [
		{"id": "p1", "name": "LANTERN GARDENS", "biome": "palace", "job": "hunt", "at": [190, 130], "links": ["lz", "p2", "p3"], "perk": "lookout"},
		{"id": "p2", "name": "SHOGUN'S HALL", "biome": "palace", "job": "rescue", "at": [320, 210], "links": ["p1", "h1"], "hold": {"bio": 2}},
		{"id": "p3", "name": "PAPER BRIDGE", "biome": "palace", "job": "escort", "at": [200, 300], "links": ["p1", "h2"], "hold": {"scrip": 30}},
		{"id": "h1", "name": "LIGHTHOUSE", "biome": "harbor", "job": "hold", "at": [470, 140], "links": ["p2", "boss"], "perk": "airfield"},
		{"id": "h2", "name": "FISH MARKET", "biome": "harbor", "job": "push", "at": [330, 400], "links": ["p3", "h3"], "hold": {"salvage": 3}},
		{"id": "h3", "name": "DRY DOCK", "biome": "harbor", "job": "demolish", "at": [490, 350], "links": ["h2", "boss"], "perk": "supply"},
		{"id": "boss", "name": "UNDER THE HIVE SHIP", "biome": "harbor", "at": [600, 240], "links": ["h1", "h3"], "stronghold": true}]},
	{"id": "gate", "name": "SHUT THE GATE", "roman": "V", "tier": 2, "hp_mul": 1.6, "boss_hp": 270, "plate": 74, "need": 2, "breach": 0.3,
	 "text": "Iron Harbor, where the Jackals keep the captured gate. Two big ops, then the flagship and the gate itself.",
	 "lz": {"name": "LANDING CRAFT", "at": [80, 280]},
	 "sectors": [
		{"id": "g1", "name": "SEA WALL", "biome": "harbor", "job": "hold", "at": [260, 180], "links": ["lz", "boss"], "hold": {"scrip": 40}},
		{"id": "g2", "name": "GATE BARRACKS", "biome": "fortress", "job": "rescue", "at": [270, 390], "links": ["lz", "boss"], "hold": {"bio": 2}},
		{"id": "boss", "name": "IRON HARBOR", "biome": "harbor", "at": [520, 280], "links": ["g1", "g2"], "stronghold": true, "finale": true}]},
]

# The company (C1-C6). The campaign keeps a roster of up to COMPANY_MAX soldiers and deploys a squad
# of up to SQUAD_MAX, one per class. Ranks come from ops survived (C3); each promotion is a pick
# from that rank's three options, and a Captain in the squad gives everyone CAPTAIN_DODGE.
const COMPANY_MAX := 10
const SQUAD_MAX := 4
const BENCH_XP := 0.5             # the bench gets half the squad's average XP from each op (C4)
const RANKS := [
	{"short": "PVT", "name": "PRIVATE", "ops": 0},
	{"short": "CPL", "name": "CORPORAL", "ops": 2},
	{"short": "SGT", "name": "SERGEANT", "ops": 5},
	{"short": "LT", "name": "LIEUTENANT", "ops": 9},
	{"short": "CPT", "name": "CAPTAIN", "ops": 14},
]
const PROMOTIONS := {
	"hp": {"name": "HARDENED", "text": "+10 max HP."},
	"move": {"name": "FLEET", "text": "+40 movement every turn."},
	"dodge": {"name": "SLIPPERY", "text": "+8 dodge."},
	"hand": {"name": "TACTICIAN", "text": "+1 card in hand."},
	"energy": {"name": "FIRST STRIKE", "text": "+1 energy on the first turn of every fight."},
	"legend": {"name": "SIGNATURE", "text": "A Legendary copy of their class's best card."},
}
const PROMO_OFFERS := [[], ["hp", "move", "dodge"], ["hand", "energy", "legend"], ["hp", "move", "dodge"], ["hand", "energy", "legend"]]
const CAPTAIN_DODGE := 5
# Medals (C5): earned once each, every one a small permanent bonus for that soldier.
const MEDALS := {
	"heart": {"name": "PURPLE HEART", "text": "Went down and still won the op.", "up": "+3 max HP"},
	"marksman": {"name": "MARKSMAN MEDAL", "text": "5 kills in one op.", "up": "+3 dodge"},
	"veteran": {"name": "CAMPAIGN STAR", "text": "Survived 10 ops.", "up": "+20 movement"},
	"ace": {"name": "SILVER STAR", "text": "30 kills in the war.", "up": "+1 energy on the first turn"},
}
const LEGACY_CARDS := 3           # a fallen veteran's best cards that the next recruit inherits (C6)

const THEMES := {
	"dusk": {"water": [Color("14485a"), Color("2f8aa0")], "tint": Color(1, 1, 1), "grass": Color("7cb042")},
	"jungle": {"water": [Color("0e3a34"), Color("2a8a6a")], "tint": Color(0.92, 1.02, 0.95), "grass": Color("4ca83a")},
	"night": {"water": [Color("0a1830"), Color("24508a")], "tint": Color(0.62, 0.66, 0.86), "grass": Color("4a7a52")},
}

func recoil(c: Dictionary) -> float:
	## How hard a card kicks its shooter back (0 for none).
	if c.get("mounted", false):
		return 0.0
	if c.type == "AIM":
		return RECOIL.get(c.get("gun", ""), 0.0)
	if c.type == "LINE" and c.has("radius") and c.has("speed"):
		return RECOIL.rocket
	return 0.0

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
		for k in [["heal", 3], ["armor", 3], ["move", 40], ["reach", 40], ["rally", 30], ["adrenal", 10]]:
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
	if base.type == "AIM" and base.has("sway") and Run.sway_mul != 1.0:
		base.sway = base.sway * Run.sway_mul
	base["key"] = key
	base["tier"] = tier
	if inst is Dictionary and inst.get("mods", []).size():
		var names: Array = []
		for mid in inst.mods:
			var m := find_mod(key, mid)
			if not m.is_empty():
				apply_mod(base, m)
				names.append(m.name)
		base["mod_names"] = names
	if inst is Dictionary and inst.get("nick", "") != "":
		base["base_name"] = base.name
		base.name = inst.nick
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
	if c.get("smoke", false) or c.get("gas", false):
		return "RADIUS %d  %d RNDS" % [int(c.srad), c.sturns]
	if c.get("beacon", false):
		return "%d BOMBS  DMG 15" % c.get("bombs", 3)
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

func relic_text(id: String, t: int) -> String:
	## Squad gear text at a given rarity tier.
	match id:
		"boots": return "Squad takes no fall or slam damage." if t >= 3 else "Squad takes half fall and slam damage."
		"jammer": return "Radiomen need %d more rounds to call backup." % (2 if t >= 3 else 1)
		"rations": return "Every wave clear heals the squad %d HP." % (4 + t * 2)
		"laser": return "Aim lasers reach %s further. Sway -30%%." % ("two steps" if t >= TIER_MAX else "one step")
		"charm": return "The first %s to die each mission live%s at 1 HP." % (["soldier", "s"] if t < 3 else ["two soldiers", ""])
		"bandolier": return "+1 energy for everyone on round 1%s." % (" and 2" if t >= 3 else "")
		"dogtags": return "Kills give %d%% more XP. +1 Luck." % int(30 + 10 * t)
		"stimpack": return "Adrenaline builds %d%% faster." % int(30 + 10 * t)
	return gear(id).get("text", "")

func offer_keys() -> Array:
	## Cards that can show up in level-ups, supply drops and the shop.
	var out: Array = []
	for k in CARDS:
		if not CARDS[k].get("od", false) and CARDS[k].get("pool", true):
			out.append(k)
	return out

func item_stats(it: Dictionary) -> Dictionary:
	## Base stats scaled by rarity plus rolled affixes, for one item instance.
	var d: Dictionary = ITEMS[it.id]
	var t: int = it.get("tier", 0)
	var out := {}
	for k in d.get("stats", {}):
		var v = d.stats[k]
		if k in FLAT_STATS:
			out[k] = v + (1 if t >= TIER_MAX and k in ["kill_draw", "push_draw", "laser_step"] else 0)
		elif k in PCT_STATS:
			out[k] = v * TIER_MUL[t]
		else:
			out[k] = int(round(v * TIER_MUL[t]))
	if it.get("named", "") != "":
		for k in LEGEND_BONUS[slot_group(d.slot)]:
			out[k] = out.get(k, 0) + LEGEND_BONUS[slot_group(d.slot)][k]
	for a in it.get("affixes", []):
		var A: Dictionary = AFFIXES[a]
		var v = A.v * AFFIX_MUL[t]
		if not A.get("pct", false):
			v = int(round(v))
		out[a] = out.get(a, 0) + v
	return out

func stat_lines(st: Dictionary) -> Array:
	var out: Array = []
	for k in st:
		var v = st[k]
		var fmt: String = STAT_FMT.get(k, k + " %d")
		if k in PCT_STATS:
			out.append(fmt % int(round(v * 100)))
		elif k == "fall_half":
			out.append(fmt)
		elif k == "sa":
			out.append("SIDEARM: " + CARDS[SIDEARMS[clampi(int(v), 0, SIDEARMS.size() - 1)]].name)
		else:
			out.append(fmt % v)
	return out

func item_name(it: Dictionary) -> String:
	if it.get("named", "") != "":
		return "%s \"%s\"" % [ITEMS[it.id].name, it.named]
	return ITEMS[it.id].name

func evolve_hint(item_id: String) -> String:
	for r in EVOLUTIONS:
		if r.kit == item_id:
			return "EVOLVES an Epic %s into %s." % [CARDS[r.card].name, CARDS[r.into].name]
	return ""

func slot_group(slot: String) -> String:
	return "kit" if slot.begins_with("kit") else slot

func affix_text(a: String, t: int) -> String:
	var A: Dictionary = AFFIXES[a]
	var v = A.v * AFFIX_MUL[t]
	return A.fmt % (int(round(v * 100)) if A.get("pct", false) else int(round(v)))

func squad_def(key: String) -> Dictionary:
	for d in SQUAD_DEFS:
		if d.key == key:
			return d
	return {}

func perk(key: String, id: String) -> Dictionary:
	for b in BRANCHES.get(key, []):
		for i in b.perks.size():
			if b.perks[i].id == id:
				var p: Dictionary = b.perks[i].duplicate()
				p["branch"] = b.name
				p["tier"] = i
				return p
	return {}

func branch(key: String, id: String) -> Dictionary:
	for b in BRANCHES.get(key, []):
		if b.id == id:
			return b
	return {}

func mod_options(inst: Dictionary) -> Array:
	## Upgrade branches a card can still take (P3).
	var taken: Array = inst.get("mods", [])
	if taken.size() >= MAX_MODS or CARDS[inst.key].get("od", false):
		return []
	var c := card(inst)
	var out: Array = CARD_MODS.get(inst.key, []).duplicate()
	for m in GEN_MODS:
		if m.id == "lean" and c.cost < 1:
			continue
		if m.get("aim", false) and c.type != "AIM":
			continue
		out.append(m)
	return out.filter(func(m): return not taken.has(m.id))

func find_mod(key: String, id: String) -> Dictionary:
	for m in CARD_MODS.get(key, []) + GEN_MODS:
		if m.id == id:
			return m
	return {}

func apply_mod(c: Dictionary, m: Dictionary) -> void:
	for k in m.get("erase", []):
		c.erase(k)
	for k in m.get("set", {}):
		c[k] = m.set[k]
	for k in m.get("add", {}):
		var v = m.add[k]
		if not c.has(k):
			continue
		if v is Array:
			c[k] = [c[k][0] + v[0], c[k][1] + v[1]]
		else:
			c[k] = c[k] + v
	for k in m.get("mul", {}):
		if c.has(k):
			c[k] = c[k] * m.mul[k]
	if m.get("heavy", false):
		if c.has("dmg"):
			c.dmg = [c.dmg[0] + 3, c.dmg[1] + 3] if c.dmg is Array else c.dmg + 4
		for k in [["heal", 4], ["armor", 4], ["move", 50], ["rally", 40], ["adrenal", 15], ["adrshot", 15], ["srad", 16.0], ["jpow", 0.15], ["draw", 1]]:
			if c.has(k[0]):
				c[k[0]] += k[1]
		if c.has("radius"):
			c.radius += 6
	c.cost = maxi(0, int(c.cost))

func gear(id: String) -> Dictionary:
	for g in GEAR:
		if g.id == id:
			return g
	return {}

func card_price(key: String, tier := -1) -> int:
	var t: int = base_tier(key) if tier < 0 else tier
	return SHOP_PRICE[clampi(base_tier(key), 0, 2)] + maxi(0, t - base_tier(key)) * 40

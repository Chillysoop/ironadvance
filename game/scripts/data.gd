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
	"hop": {"name": "Hop", "type": "LINE", "cost": 1, "jump": true, "jpow": 0.62, "hop": true, "pool": false, "text": "Everyone has one. Jump a short gap or up a wall about head high. Works with no movement left; uses up the rest. Next to a squadmate: a leg-up jumps higher.", "rarity": 0},
	"padbounce": {"name": "Pad Bounce", "type": "LINE", "cost": 0, "jump": true, "jpow": 1.0, "padbounce": true, "pool": false, "text": "Free while you stand on a Jump Pad, once a turn. Bounce off it, even with no movement left.", "rarity": 0},
	# every soldier starts with one Drill in the deck; once it's spent it waits for the next draw
	"drill": {"name": "Drill", "type": "LINE", "cost": 0, "drill": true, "reach": 0, "pool": false, "text": "Bore through any terrain toward the cursor. Uses movement as you go. Click to stop early.", "rarity": 0, "up": {"reach": 60}},
	# B5: Vharr tech, built in the Alien Lab
	"blink": {"name": "Blink", "type": "SELF", "cost": 1, "blink": 360.0, "text": "Teleport behind the nearest enemy within reach, facing it.", "rarity": 2, "up": {"blink": 480.0}},
	"gravnade": {"name": "Gravity Grenade", "type": "SELF", "cost": 1, "gwell": 140.0, "text": "Opens a gravity well on the biggest group of enemies nearby and pulls them together.", "rarity": 2, "up": {"gwell": 180.0}},
	"domeup": {"name": "Dome Projector", "type": "SELF", "cost": 1, "domes": 2, "drange": 90.0, "text": "A Vharr dome over you and squadmates close by. Stops bullets and blasts until your next turn.", "rarity": 2, "up": {"drange": 140.0}},
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
	"vomit": {"name": "Zombie Vomit", "type": "LINE", "cost": 0, "radius": 60, "dmg": 22, "speed": 9.0, "pool": false, "text": "ZOMBIE: a huge gout of vomit straight at the cursor. Blast 60.", "rarity": 3},
	"monkeyclimb": {"name": "Monkey Climb", "type": "LINE", "cost": 0, "grapple": true, "range": 400, "pool": false, "text": "MONKEY: scale any wall or roof in reach.", "rarity": 2},
	"rambobow": {"name": "Rambo Bow", "type": "ARC", "cost": 1, "radius": 46, "dmg": 14, "wind": 0.4, "bow": true, "pool": false, "text": "An explosive arrow that bursts on impact. A fresh one every turn this level. Every Jackal hunts the archer.", "rarity": 3},
	# B6: the free card a soldier gets standing at a mounted M2
	"mounted": {"name": "Mounted M2", "type": "AIM", "cost": 0, "dmg": [3, 4], "shots": 6, "range": FULL_RANGE, "gun": "mg", "bounce": 0, "sway": 0.02, "spread": 0.05, "mounted": true, "pool": false, "text": "Free while you stand at the gun. Six heavy rounds, no kick. Once a turn.", "rarity": 2},
	"roll": {"name": "Combat Roll", "type": "LINE", "cost": 1, "roll": true, "dist": 150, "text": "Roll up to 7.5m without using movement. Fits through crawl-height gaps, and the next Jackal shot at you goes over your head.", "rarity": 0, "up": {"dist": 210}},
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
	"taunt": {"name": "Taunt", "type": "SELF", "cost": 0, "taunt": true, "text": "Every Jackal with a shot at you takes it next phase.", "rarity": 1, "up": {"armor": 4}},
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
	"surge": {"name": "Adrenal Surge", "type": "SELF", "cost": 0, "od": true, "surge": true, "range": 240, "text": "Squad within 12m: heal 10, +1 energy, +4m move.", "rarity": 5},
	"cluster": {"name": "Cluster Bomb", "type": "ARC", "cost": 0, "od": true, "radius": 40, "dmg": 12, "fuse": 110, "bounce": true, "wind": 1.0, "cluster": 5, "text": "Bursts into five bouncing bomblets.", "rarity": 5},
	"rush": {"name": "Bull Rush", "type": "LINE", "cost": 0, "od": true, "rush": true, "text": "Launch yourself. Everyone you hit goes flying.", "rarity": 5},
	# archetype Overdrives: a capstone perk swaps the soldier's Overdrive for one of these (P2)
	"oneshot": {"name": "One Shot", "type": "AIM", "cost": 0, "od": true, "dmg": [28, 34], "range": FULL_RANGE, "gun": "sniper", "bounce": 0, "sway": 0.0, "pierce": true, "phase": true, "forcehead": true, "text": "No sway. A crit that passes through walls and bodies.", "rarity": 5},
	"holdline": {"name": "Hold the Line", "type": "SELF", "cost": 0, "od": true, "overwatch": true, "ow": 8, "text": "Eight overwatch shots: fire at everything that moves.", "rarity": 5},
	"deadmans": {"name": "Dead Man's Hand", "type": "AIM", "cost": 0, "od": true, "dmg": [5, 7], "shots": 6, "range": FULL_RANGE, "gun": "pistol", "bounce": 2, "sway": 0.01, "spread": 0.03, "text": "Six fast pistol rounds.", "rarity": 5},
	"smokescreen": {"name": "Smokescreen", "type": "ARC", "cost": 0, "od": true, "smoke": true, "multi": 3, "srad": 80.0, "sturns": 3, "wind": 0.6, "text": "Three big clouds in a row.", "rarity": 5},
	"blight": {"name": "Blight Shell", "type": "SELF", "cost": 0, "od": true, "blight": true, "text": "Every Jackal on screen is Toxic for 3 rounds.", "rarity": 5},
	"triagefield": {"name": "Triage Field", "type": "SELF", "cost": 0, "od": true, "triage": 15, "range": 260, "text": "Squad within 13m: heal 15 and clear statuses.", "rarity": 5},
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
	# N2 Bolt, Combat Engineer: builds into the terrain
	"sandbags": {"name": "Sandbags", "type": "ARC", "cost": 1, "build": "wall", "bw": 24, "bh": 20, "wind": 0.6, "text": "Throw a sandbag pack. A wall stacks up where it lands.", "rarity": 0, "up": {"bw": 32, "bh": 26}},
	"sentry": {"name": "Sentry Gun", "type": "ARC", "cost": 2, "build": "sentry", "shp": 14, "sdmg": [4, 5], "wind": 0.4, "text": "Deploys a turret where it lands. At the end of your turn it shoots the nearest Jackal along its laser.", "rarity": 1, "up": {"shp": 20, "sdmg": [5, 7]}},
	"girder": {"name": "Girder", "type": "LINE", "cost": 1, "girder": true, "reach": 320, "gw": 56, "text": "Bolt a steel beam in place at the cursor, even in mid-air. Shoot its bolt and it drops and crushes.", "rarity": 1, "up": {"gw": 76}},
	"jumppad": {"name": "Jump Pad", "type": "ARC", "cost": 1, "build": "pad", "pw": 28, "wind": 0.6, "text": "Throw a rubber pad. Soldiers and grenades bounce high off it.", "rarity": 0, "up": {"pw": 44}},
	"rivetgun": {"name": "Rivet Gun", "type": "AIM", "cost": 1, "dmg": [3, 4], "shots": 3, "range": FULL_RANGE, "gun": "smg", "bounce": 0, "sway": 0.03, "spread": 0.04, "chip": 3, "text": "Three rivets. Punch through wood.", "rarity": 0, "up": {"shots": 4}},
	"wrench": {"name": "Big Wrench", "type": "MELEE", "cost": 1, "dmg": [7, 9], "range": 38, "knock": 7, "text": "A heavy swing. Knocks them off their feet.", "rarity": 0, "up": {"dmg": [10, 12]}},
	"weld": {"name": "Weld Plate", "type": "ALLY", "cost": 1, "plate": 7, "range": 120, "text": "Bolt a steel plate onto a squadmate: armor until your next turn.", "rarity": 1, "up": {"plate": 11}},
	"fortify": {"name": "Fortify", "type": "SELF", "cost": 0, "od": true, "fortify": 8, "range": 220, "text": "Squad within 11m: 8 armor and a concrete wall in front of each of them.", "rarity": 5},
	"sentrynest": {"name": "Sentry Nest", "type": "SELF", "cost": 0, "od": true, "nest": 3, "text": "Three sentry guns unfold around Bolt.", "rarity": 5},
	"ironcurtain": {"name": "Iron Curtain", "type": "SELF", "cost": 0, "od": true, "fortify": 12, "range": 400, "curtain": true, "text": "A huge concrete wall between the squad and the nearest Jackal, and 12 armor for everyone.", "rarity": 5},
	"steelrain": {"name": "Steel Rain", "type": "ARC", "cost": 0, "od": true, "beacon": true, "rain": 5, "wind": 0.3, "text": "Five girders drop out of the sky across the marker.", "rarity": 5},
	"junkcannon": {"name": "Junk Cannon", "type": "LINE", "cost": 0, "od": true, "radius": 44, "dmg": 20, "speed": 8.0, "junk": true, "text": "Fires a ton of scrap. Big blast, and it lands as a heap of steel.", "rarity": 5},
	"buildcrew": {"name": "Build Crew", "type": "SELF", "cost": 0, "od": true, "duo": true, "fortify": 8, "range": 220, "rook_wall": true, "text": "Bolt walls up the squad while Rook kicks a Jackal into a fresh wall.", "rarity": 5},
	"demoteam": {"name": "Demo Team", "type": "ARC", "cost": 0, "od": true, "duo": true, "beacon": true, "rain": 3, "barrage": 4, "wind": 0.4, "text": "Bolt drops three girders and Vee walks four shells across them.", "rarity": 5},
	# N7 Track and Rex, K9 Handler: Rex never moves on his own, only when Track plays a dog card
	"sicem": {"name": "Sic 'Em", "type": "LINE", "cost": 1, "dog": "bite", "reach": 260, "dmg": [6, 8], "knock": 5, "text": "Rex leaps at the Jackal by the cursor and bites. Knocks them back, maybe off a ledge.", "rarity": 0, "up": {"dmg": [9, 11]}},
	"fetch": {"name": "Fetch!", "type": "LINE", "cost": 1, "dog": "fetch", "reach": 300, "text": "Rex runs to the cursor and brings back loot, a crate's contents, or a prisoner.", "rarity": 0, "up": {"reach": 420}},
	"guard": {"name": "Guard", "type": "ALLY", "cost": 1, "guard": true, "range": 260, "text": "Rex stands by a squadmate. The first Jackal that shoots at them gets tackled and Stunned instead.", "rarity": 1, "up": {"range": 400}},
	"whistle": {"name": "Whistle", "type": "SELF", "cost": 0, "whistle": true, "text": "Rex runs back to Track's side. Draw a card.", "rarity": 0},
	"hounds": {"name": "Release the Hounds", "type": "SELF", "cost": 0, "od": true, "hounds": 3, "text": "Three dogs burst out and each bites a different Jackal.", "rarity": 5},
	"wolfpack": {"name": "Wolfpack", "type": "SELF", "cost": 0, "od": true, "hounds": 5, "hstun": true, "text": "Five dogs, and every bite Stuns.", "rarity": 5},
	"supplyrun": {"name": "Supply Run", "type": "SELF", "cost": 0, "od": true, "supplyrun": true, "text": "Rex fetches every pickup and crate on screen.", "rarity": 5},
	"stampede": {"name": "Stampede", "type": "LINE", "cost": 0, "od": true, "rush": true, "stab": 10, "pack": true, "text": "Track charges with the pack: 10 damage to every body he passes, then two dogs bite.", "rarity": 5},
	"skyfall": {"name": "Skyfall", "type": "SELF", "cost": 0, "od": true, "hounds": 4, "hawk": true, "text": "The hawk dives on four Jackals: 6 damage and Marked.", "rarity": 5},
	"meddog": {"name": "Med Dog", "type": "SELF", "cost": 0, "od": true, "duo": true, "meddog": 12, "text": "Rex runs Hex's kit to everyone: heal 12 each and +1 energy.", "rarity": 5},
	"k9strike": {"name": "K9 Strike", "type": "SELF", "cost": 0, "od": true, "duo": true, "hounds": 3, "hmark": true, "text": "Dogs pin three Jackals and Mark them, and Moss gets a free Long Shot.", "rarity": 5},
	# N3 Gears, Slug Pilot, and R1 hijacked vehicles: "mech" cards only work from inside a vehicle
	"vulcan": {"name": "Vulcan", "type": "AIM", "cost": 1, "mech": true, "dmg": [2, 3], "shots": 6, "range": FULL_RANGE, "gun": "mg", "bounce": 0, "sway": 0.04, "spread": 0.05, "text": "VEHICLE: the twin machine gun. Six rounds.", "rarity": 0, "up": {"shots": 8}},
	"mcannon": {"name": "Walker Cannon", "type": "LINE", "cost": 2, "mech": true, "radius": 34, "dmg": 14, "speed": 9.0, "text": "VEHICLE: a shell straight at the cursor. Blast 34.", "rarity": 1, "up": {"dmg": 18}},
	"stomp": {"name": "Stomp", "type": "MELEE", "cost": 1, "mech": true, "dmg": [9, 11], "range": 34, "knock": 3, "stun": true, "text": "VEHICLE: crush a Jackal next to you. Stuns.", "rarity": 0, "up": {"dmg": [12, 14]}},
	"eject": {"name": "Eject!", "type": "LINE", "cost": 0, "mech": true, "eject": true, "radius": 56, "dmg": 20, "text": "VEHICLE: bail out. The empty vehicle charges where you aim and explodes. Blast 56.", "rarity": 1, "up": {"dmg": 26}},
	"tankshell": {"name": "Tank Shell", "type": "LINE", "cost": 1, "mech": true, "radius": 42, "dmg": 15, "speed": 8.0, "text": "VEHICLE: the tank's main gun. Blast 42.", "rarity": 1},
	"patchjob": {"name": "Patch Job", "type": "SELF", "cost": 2, "patch": true, "text": "On foot: climb back into a rebuilt walker at full HP.", "rarity": 1, "up": {"cost": 1}},
	"bigslug": {"name": "Big Slug", "type": "SELF", "cost": 0, "od": true, "slug": true, "slugturns": 2, "text": "The SV-001 drops in and Gears drives it for two rounds.", "rarity": 5},
	"missilepod": {"name": "Missile Pod", "type": "LINE", "cost": 0, "od": true, "count": 6, "radius": 26, "dmg": 9, "speed": 7.0, "text": "Six rockets in a spread at the cursor.", "rarity": 5},
	"tankbuster": {"name": "Tank Buster", "type": "LINE", "cost": 0, "od": true, "radius": 64, "dmg": 28, "speed": 9.0, "text": "One huge shell. Blast 64.", "rarity": 5},
	"fullsend": {"name": "Full Send", "type": "LINE", "cost": 0, "od": true, "eject": true, "rebuild": true, "radius": 90, "dmg": 30, "text": "The walker charges and blows with a 90 blast, and a fresh one is waiting for Gears.", "rarity": 5},
	"convoy": {"name": "Convoy", "type": "SELF", "cost": 0, "od": true, "slug": true, "slugturns": 3, "squadarmor": 6, "text": "The SV-001 rolls in for three rounds and everyone gets 6 armor.", "rarity": 5},
	"ridealong": {"name": "Ride Along", "type": "SELF", "cost": 0, "od": true, "duo": true, "ridealong": true, "text": "Rook jumps onto the walker: 6 armor each, a free Vulcan for Gears and a free Burst Fire for Rook.", "rarity": 5},
	"fieldrefit": {"name": "Field Refit", "type": "SELF", "cost": 0, "od": true, "duo": true, "refit": 10, "text": "Hex patches the walker to full and heals everyone 10.", "rarity": 5},
	# B1-B4: fifth branches for the original four
	"xray": {"name": "X-Ray", "type": "AIM", "cost": 0, "od": true, "dmg": [16, 20], "range": FULL_RANGE, "gun": "sniper", "bounce": 0, "sway": 0.0, "pierce": true, "phase": true, "text": "One round through the whole screen: every wall and every body on the line.", "rarity": 5},
	"handoff": {"name": "Hand-Off", "type": "ALLY", "cost": 1, "handoff": true, "range": 260, "text": "Pass the card to the right of this one to a squadmate.", "rarity": 1, "up": {"range": 400}},
	"switch": {"name": "Switcheroo", "type": "ALLY", "cost": 0, "switch": true, "range": 600, "text": "Swap places with a squadmate.", "rarity": 5, "pool": false},
	"synchronize": {"name": "Synchronize", "type": "SELF", "cost": 0, "od": true, "sync": true, "text": "Everyone's next card this turn is free.", "rarity": 5},
	"stickycharge": {"name": "Sticky Charge", "type": "ARC", "cost": 1, "sticky": true, "radius": 34, "dmg": 13, "wind": 0.6, "text": "Sticks where it lands. Blows when you play a Clacker, or when a Jackal steps on it.", "rarity": 0, "up": {"dmg": 17}},
	"clacker": {"name": "Clacker", "type": "SELF", "cost": 0, "clacker": true, "text": "Set off your oldest Sticky Charge.", "rarity": 0},
	"daisychain": {"name": "Daisy Chain", "type": "LINE", "cost": 0, "od": true, "daisy": 6, "text": "Lay six Sticky Charges in a line toward the cursor.", "rarity": 5},
	"grab": {"name": "Grab", "type": "MELEE", "cost": 1, "dmg": [2, 3], "range": 34, "grab": true, "text": "Pick a Jackal up and carry him. Body Throw goes in your hand. He breaks free when the Jackals move.", "rarity": 0},
	"bodythrow": {"name": "Body Throw", "type": "ARC", "cost": 0, "bodythrow": true, "dmg": 8, "wind": 0.2, "text": "Throw the Jackal you're holding. He takes the fall, and so does whatever he lands on.", "rarity": 5, "pool": false},
	"suplex": {"name": "Suplex", "type": "MELEE", "cost": 1, "dmg": [8, 10], "range": 34, "suplex": true, "text": "Lift a Jackal over your head and drive him into the ground behind you.", "rarity": 1, "up": {"dmg": [11, 13]}},
	"piledrive": {"name": "Piledriver", "type": "MELEE", "cost": 0, "od": true, "dmg": [22, 26], "range": 40, "piledrive": true, "text": "Leap up with a Jackal and slam down: a crater, and everything around it is Stunned.", "rarity": 5},
	# N1 Finch, Scout
	"zipline": {"name": "Zipline", "type": "LINE", "cost": 1, "zipline": true, "reach": 440, "pull": 70, "text": "Fire a line to the cursor. Finch and every squadmate within 3.5m ride it there.", "rarity": 0, "up": {"reach": 600}},
	"flare": {"name": "Flare", "type": "ARC", "cost": 1, "flare": 90, "wind": 0.5, "text": "Lights up every Jackal within 4.5m: FLARED, they take +3 from everyone for 2 turns.", "rarity": 0, "up": {"flare": 130}},
	"drone": {"name": "Recon Drone", "type": "SELF", "cost": 1, "drone": 1, "dmg": 9, "radius": 32, "text": "The drone flies over the nearest Jackal within 21m and drops a grenade on it.", "rarity": 1, "up": {"dmg": 13}},
	"knives": {"name": "Throwing Knives", "type": "AIM", "cost": 1, "dmg": [3, 4], "shots": 2, "range": 520, "gun": "pistol", "bounce": 0, "sway": 0.02, "spread": 0.03, "text": "Two quick knives.", "rarity": 0, "up": {"shots": 3}},
	"pathfinder": {"name": "Pathfinder", "type": "SELF", "cost": 0, "od": true, "rally": 120, "range": 2000, "squadenergy": 1, "text": "Every squadmate: +1 energy and +6m movement.", "rarity": 5},
	"skyline": {"name": "Skyline", "type": "LINE", "cost": 0, "od": true, "zipline": true, "reach": 900, "pull": 2000, "text": "A line across the screen. The whole squad rides it.", "rarity": 5},
	"starshell": {"name": "Starshell", "type": "ARC", "cost": 0, "od": true, "flare": 260, "wind": 0.3, "text": "A huge flare: every Jackal within 13m is FLARED.", "rarity": 5},
	"dronestrike": {"name": "Drone Strike", "type": "SELF", "cost": 0, "od": true, "drone": 3, "dmg": 12, "radius": 36, "text": "Three drone runs on three Jackals.", "rarity": 5},
	"rigged": {"name": "Rigged", "type": "SELF", "cost": 0, "od": true, "rigged": true, "text": "Every barrel, fuel tank and Jackal mine on screen blows.", "rarity": 5},
	"paintedtarget": {"name": "Painted Target", "type": "SELF", "cost": 0, "od": true, "duo": true, "paint": true, "text": "Every Jackal on screen is FLARED, and Moss gets a free Long Shot.", "rarity": 5},
	"payload": {"name": "Payload", "type": "SELF", "cost": 0, "od": true, "duo": true, "drone": 1, "dmg": 22, "radius": 54, "text": "The drone carries one of Vee's bazooka rounds onto the nearest Jackal.", "rarity": 5},
	# N4 Kage, Commando
	"katana": {"name": "Katana", "type": "MELEE", "cost": 1, "dmg": [9, 11], "range": 60, "knock": 4, "text": "A long-reach slash.", "rarity": 0, "up": {"dmg": [12, 14]}},
	"deflect": {"name": "Deflect", "type": "SELF", "cost": 1, "deflect": 1, "text": "Until your next turn, the next bullet that hits Kage flies back at whoever fired it.", "rarity": 0},
	"walljump": {"name": "Wall Jump", "type": "LINE", "cost": 1, "jump": true, "jpow": 1.2, "text": "A big leap. Kage always lands soft.", "rarity": 0, "up": {"jpow": 1.45}},
	"vanish": {"name": "Smoke Bomb", "type": "SELF", "cost": 1, "vanish": true, "text": "A puff of smoke and Kage is PREDATOR: untargetable until she attacks.", "rarity": 1},
	"thousandcuts": {"name": "Thousand Cuts", "type": "LINE", "cost": 0, "od": true, "rush": true, "stab": 14, "text": "Dash along a line. 14 damage to every body she passes.", "rarity": 5},
	"mirrorwall": {"name": "Mirror Wall", "type": "SELF", "cost": 0, "od": true, "deflect": 99, "armor": 6, "text": "Every bullet that hits Kage until your next turn flies back. +6 armor.", "rarity": 5},
	"shadowstrike": {"name": "Shadow Strike", "type": "SELF", "cost": 0, "od": true, "vanish": true, "freekatana": 2, "text": "Vanish, with two free Katanas in hand.", "rarity": 5},
	"wallrun": {"name": "Wall Run", "type": "SELF", "cost": 0, "od": true, "move": 220, "freejump": 2, "text": "+11m movement and two free Wall Jumps.", "rarity": 5},
	"iaido": {"name": "Iaido", "type": "LINE", "cost": 0, "od": true, "iaido": 18, "reach": 300, "text": "One cut along a line: 18 damage to every body on it, and the terrain is sliced through.", "rarity": 5},
	"mirrormatch": {"name": "Mirror Match", "type": "SELF", "cost": 0, "od": true, "duo": true, "mirror": true, "text": "Kage holds her blade up: Moss gets a free Ricochet Round.", "rarity": 5},
	# N5 Volta, Gravitech
	"magnet": {"name": "Magnet Gun", "type": "LINE", "cost": 1, "magnet": -1, "reach": 380, "text": "Yank the first body or barrel on the line toward Volta.", "rarity": 0, "up": {"reach": 520}},
	"repulsor": {"name": "Repulsor", "type": "LINE", "cost": 1, "magnet": 1, "reach": 300, "text": "Blast the first body or barrel on the line away from Volta.", "rarity": 0, "up": {"reach": 420}},
	"tesla": {"name": "Tesla Arc", "type": "SELF", "cost": 2, "tesla": 3, "dmg": [6, 7], "text": "Lightning hits the nearest Jackal within 15m and jumps to two more within 7m.", "rarity": 1, "up": {"dmg": [8, 9]}},
	"singularity": {"name": "Singularity", "type": "ARC", "cost": 0, "od": true, "singularity": 140, "wind": 0.2, "text": "Everything within 7m is sucked to one point, then thrown.", "rarity": 5},
	"railgun": {"name": "Rail Shot", "type": "AIM", "cost": 0, "od": true, "dmg": [20, 24], "range": FULL_RANGE, "gun": "sniper", "bounce": 0, "sway": 0.0, "pierce": true, "phase": true, "text": "A magnetic slug through every wall and body on the line.", "rarity": 5},
	"blackhole": {"name": "Black Hole", "type": "ARC", "cost": 0, "od": true, "singularity": 220, "crushdmg": 10, "wind": 0.2, "text": "Everything within 11m is crushed together for 10, then thrown.", "rarity": 5},
	"stormcage": {"name": "Storm Cage", "type": "SELF", "cost": 0, "od": true, "tesla": 7, "dmg": [8, 9], "tstun": true, "text": "Lightning jumps through seven Jackals and Stuns them.", "rarity": 5},
	"shockwave": {"name": "Shockwave", "type": "SELF", "cost": 0, "od": true, "shockwave": 180, "text": "Everything within 9m is blown away from Volta.", "rarity": 5},
	"delivery": {"name": "Delivery", "type": "SELF", "cost": 0, "od": true, "duo": true, "delivery": true, "text": "Vee gets two free Frag Grenades that ignore wind.", "rarity": 5},
	"slingshot": {"name": "Slingshot", "type": "SELF", "cost": 0, "od": true, "duo": true, "slingshot": true, "text": "Volta yanks the nearest Jackal into Rook's punch: 12 damage and sent flying.", "rarity": 5},
	# N6 Brass, Forward Officer
	"designator": {"name": "Designator", "type": "ARC", "cost": 1, "beacon": true, "bombs": 1, "wind": 0.3, "text": "Paint a spot. A shell lands there when the Jackals' phase starts.", "rarity": 0, "up": {"bombs": 2}},
	"supplydrop": {"name": "Supply Drop", "type": "SELF", "cost": 2, "supply": 1, "text": "A crate drops in: pick one of three cards for Brass's hand, free to play this turn.", "rarity": 1, "up": {"supply": 2}},
	"orders": {"name": "Orders", "type": "ALLY", "cost": 1, "orders": 1, "range": 320, "text": "A squadmate gets +1 energy and draws a card.", "rarity": 0, "up": {"range": 480}},
	"dangerclose": {"name": "Danger Close", "type": "ARC", "cost": 0, "od": true, "beacon": true, "bombs": 7, "wind": 0.3, "text": "A carpet of seven shells around the marker next phase.", "rarity": 5},
	"creeping": {"name": "Creeping Barrage", "type": "ARC", "cost": 0, "od": true, "beacon": true, "bombs": 10, "wind": 0.3, "text": "Ten shells around the marker next phase.", "rarity": 5},
	"rallycry": {"name": "Rally Cry", "type": "SELF", "cost": 0, "od": true, "squadenergy": 2, "text": "Every squadmate gets +2 energy.", "rarity": 5},
	"airdrop": {"name": "Airdrop", "type": "SELF", "cost": 0, "od": true, "supply": 3, "text": "Three crates: pick three cards.", "rarity": 5},
	"firemission": {"name": "Fire Mission", "type": "ARC", "cost": 0, "od": true, "duo": true, "beacon": true, "bombs": 8, "wind": 0.3, "text": "Vee's mortar and Brass's battery together: eight shells next phase.", "rarity": 5},
	# N8 Sable, Vharr Splicer
	"tongue": {"name": "Tongue", "type": "LINE", "cost": 1, "magnet": -1, "tongue": true, "reach": 320, "text": "Yank the first body on the line to Sable, Jackal or squadmate.", "rarity": 0, "up": {"reach": 440}},
	"acidspit": {"name": "Acid Spit", "type": "ARC", "cost": 1, "acid": 40, "dmg": 5, "radius": 24, "wind": 0.4, "text": "A glob that leaves an acid puddle for 3 turns: 3 damage to every Jackal in it after the Jackals move.", "rarity": 0, "up": {"dmg": 8}},
	"mindlink": {"name": "Mindlink", "type": "MELEE", "cost": 2, "mindlink": 1, "range": 300, "dmg": [1, 1], "knock": 0, "text": "Take over a Jackal or alien (30 HP or less) for one turn: it fights its own side.", "rarity": 1},
	"broodcall": {"name": "Brood Call", "type": "SELF", "cost": 0, "od": true, "brood": 3, "text": "Three Skitters burst out of the ground and fight for you through the next Jackal phase.", "rarity": 5},
	"phaseshift": {"name": "Phase Shift", "type": "SELF", "cost": 0, "od": true, "blink": 480.0, "vanish": true, "text": "Blink behind a Jackal and vanish.", "rarity": 5},
	"acidrain": {"name": "Acid Rain", "type": "ARC", "cost": 0, "od": true, "acid": 120, "dmg": 8, "radius": 60, "wind": 0.3, "text": "A downpour of acid: a 6m puddle.", "rarity": 5},
	"hivemind": {"name": "Hive Mind", "type": "SELF", "cost": 0, "od": true, "hivemind": 3, "text": "The three Jackals nearest Sable fight for you for a turn.", "rarity": 5},
	"domefield": {"name": "Dome Field", "type": "SELF", "cost": 0, "od": true, "domes": 2, "drange": 2000.0, "text": "A Vharr dome over every squadmate.", "rarity": 5},
	"bilebomb": {"name": "Bile Bomb", "type": "ARC", "cost": 0, "od": true, "duo": true, "acid": 90, "dmg": 16, "radius": 48, "wind": 0.6, "text": "Vee's grenade, Sable's bile: a big blast that leaves acid.", "rarity": 5},
}
# Vehicles (N3, R1, E6). seat: how far the driver sits above the ground; cards: what a hijacker
# gets in hand while driving. A soldier's own HP is safe until the vehicle breaks.
# pitch: the one-line reason to climb in, shown on hover and when boarding.
const VEHICLES := {
	"walker": {"name": "WALKER", "hp": 30, "seat": 22, "move": 0, "cards": ["vulcan", "stomp", "eject"], "pitch": "All-rounder: a twin MG, and Stomp crushes and stuns Jackals next to you."},
	"bike": {"name": "BIKE", "hp": 16, "seat": 8, "move": 140, "cards": ["vulcan", "eject"], "pitch": "Fast but flimsy: race across the map, then bail out as a bomb."},
	"tank": {"name": "TANK", "hp": 44, "seat": 16, "move": -40, "cards": ["tankshell", "vulcan", "eject"], "pitch": "The toughest hull and a big-blast main gun, but slow."},
}
const VEHICLE_RULES := "It takes every hit until it breaks: the driver's own HP is safe."

static func vehicle_move(type: String) -> String:
	var m: int = VEHICLES[type].move
	return "MOVE +%s" % meters(m) if m > 0 else ("MOVE -%s" % meters(-m) if m < 0 else "NORMAL MOVE")

static func vehicle_card_names(type: String) -> String:
	return ", ".join(VEHICLES[type].cards.map(func(k): return CARDS[k].name.to_upper()))
# ---------------------------------------------------------------- combos (C1, C3, C5, C6)
const MOMENTUM := 3          # every 3rd card a soldier plays in a turn refunds 1 energy
const STATUS := {
	"burn": {"name": "BURNING", "short": "BURN", "c": Color("ff7a3d"), "text": "3 damage a turn. Spreads to bodies on wood and chars the wood."},
	"toxic": {"name": "TOXIC", "short": "TOX", "c": Color("9be34a"), "text": "2 damage a turn, armor does not help."},
	"supp": {"name": "SUPPRESSED", "short": "SUPP", "c": Color("c9d1da"), "text": "Half movement on its next turn."},
	"mark": {"name": "MARKED", "short": "MARK", "c": Color("ff4d3d"), "text": "The next hit on it is a critical (x1.5)."},
	"flared": {"name": "FLARED", "short": "FLARE", "c": Color("ffe36a"), "text": "Lit up by a flare: takes +3 from every hit."},
	"pinned": {"name": "PINNED", "short": "PIN", "c": Color("ff7a3d"), "text": "A hound has it by the leg: no movement next turn."},
	"stun": {"name": "STUNNED", "short": "STUN", "c": Color("ffd23a"), "text": "Skips its next turn."},
	# bonus pad powerups (Soldat): they last the rest of this turn and the holder's next one
	"berserk": {"name": "BERSERKER", "short": "BERS", "c": Color("ff4d3d"), "text": "Deals double damage."},
	"cloak": {"name": "PREDATOR", "short": "PRED", "c": Color("b48cff"), "text": "Can't be targeted, and bullets pass through, until it attacks."},
	"flamegod": {"name": "FLAMEGOD", "short": "FLAME", "c": Color("ff9a3d"), "text": "Takes no damage. Its bullets set what they hit on fire."},
	"vest": {"name": "VEST", "short": "VEST", "c": Color("9fb4c9"), "text": "Takes half damage."},
	"fat": {"name": "FAT", "short": "FAT", "c": Color("ffb070"), "text": "+10 HP and 50% bigger blasts."},
	"zombie": {"name": "ZOMBIE", "short": "ZOMB", "c": Color("9df25c"), "text": "Can't go down."},
	"roll": {"name": "ROLLING", "short": "ROLL", "c": Color("e8dcc2"), "text": "The next Jackal shot at it goes over its head."},
	"cluster": {"name": "CLUSTER", "short": "CLUS", "c": Color("ffd23a"), "text": "Your next grenades burst into bomblets."},
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
	# R6: Metal Slug transformations. All upside for a soldier; a Jackal only gets the Fat HP
	"fat": {"name": "FAT", "glyph": "F", "c": Color("ffb070"), "text": "+10 HP and 50% bigger blasts for this turn and the next."},
	"zombie": {"name": "ZOMBIE", "glyph": "Z", "c": Color("9df25c"), "text": "Two huge Zombie Vomit cards, and you can't go down for this turn and the next."},
	"monkey": {"name": "MONKEY", "glyph": "M", "c": Color("c9a26a"), "text": "Two free Monkey Climbs: scale any wall or roof in reach. They stay until used."},
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

const OD := {"moss": "ricochet", "hex": "surge", "vee": "cluster", "rook": "rush", "bolt": "fortify", "track": "hounds", "gears": "bigslug", "finch": "pathfinder", "kage": "thousandcuts", "volta": "singularity", "brass": "dangerclose", "sable": "broodcall"}
# Metal Slug letter drops: 3 temporary cards in the collector's hand for the rest of the mission.
const LETTERS := {"H": "hmg", "R": "bazooka", "F": "flameshot", "S": "shotgun", "L": "lasergun", "C": "chaser",
	"D": "dropshot", "T": "thundershot", "Z": "zantetsu", "G": "superhmg"}
# Letters that only drop from a given point in the run on (Run.mission: 1 = level 2, 2 = level 3 and the finale).
const LETTER_FROM := {"D": 1, "T": 1, "Z": 2, "G": 2}

# ---------------------------------------------------------------- gear (G1-G6)
# Four slots per soldier plus a squad stash and a 3-slot consumable belt.
# "stats" scale with the item's rarity (TIER_MUL); weapons add their cards to the deck.
# the icon a belt consumable shows everywhere: shop shelf, Armory, battle belt
const BELT_ICONS := {"heal": "ic_heart", "ration": "ic_heart", "smoke": "ic_shield", "energy": "ic_bolt"}
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
	"ammopouch": {"name": "Ammo Pouch", "slot": "kit", "stats": {"energy1": 1}, "text": "Spare mags clipped where you can reach them."},
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
	"turretcore": {"name": "Turret Core", "slot": "kit", "keystone": "bolt", "stats": {"armor_turn": 1}, "text": "KEYSTONE: your sentries fire piercing rounds for +2 damage."},
	"rebar": {"name": "Rebar Spool", "slot": "armor", "keystone": "bolt", "stats": {"hp": 4}, "text": "KEYSTONE: your walls are twice as big."},
	"rivetdriver": {"name": "Rivet Driver", "slot": "weapon", "keystone": "bolt", "cards": ["girder", "girder"], "text": "KEYSTONE: adds 2 Girders. Girders cost 0."},
	"magnetglove": {"name": "Magnet Glove", "slot": "kit", "keystone": "bolt", "stats": {"luck": 1}, "text": "KEYSTONE: your first build each turn refunds its energy."},
	"carabiner": {"name": "Carabiner", "slot": "kit", "keystone": "finch", "stats": {"move": 30}, "text": "KEYSTONE: Zipline costs 0."},
	"flaregun": {"name": "Flare Gun", "slot": "weapon", "keystone": "finch", "cards": ["flare"], "text": "KEYSTONE: adds a Flare. Flares cost 0."},
	"dronebay": {"name": "Drone Bay", "slot": "kit", "keystone": "finch", "stats": {"luck": 1}, "text": "KEYSTONE: Recon Drone costs 0."},
	"thermite": {"name": "Thermite Blades", "slot": "kit", "keystone": "finch", "stats": {"aim_dmg": 1}, "text": "KEYSTONE: Finch's knives set Jackals Burning."},
	"mirrorblade": {"name": "Mirror Blade", "slot": "weapon", "keystone": "kage", "stats": {"aim_dmg": 1}, "text": "KEYSTONE: Deflect costs 0."},
	"shinobi": {"name": "Shinobi Garb", "slot": "armor", "keystone": "kage", "stats": {"hp": 3}, "text": "KEYSTONE: Kage's kills make her PREDATOR."},
	"climbclaws": {"name": "Climbing Claws", "slot": "kit", "keystone": "kage", "stats": {"move": 30}, "text": "KEYSTONE: Wall Jump draws a card."},
	"ancestral": {"name": "Ancestral Blade", "slot": "weapon", "keystone": "kage", "cards": ["katana"], "text": "KEYSTONE: adds a Katana. Katana reaches 2m farther and deals +3."},
	"magboots": {"name": "Mag Boots", "slot": "kit", "keystone": "volta", "stats": {"armor_turn": 1}, "text": "KEYSTONE: Magnet Gun costs 0."},
	"gravcore": {"name": "Gravity Core", "slot": "kit", "keystone": "volta", "stats": {"luck": 1}, "text": "KEYSTONE: Gravity Grenade costs 0."},
	"teslacoil": {"name": "Tesla Coil", "slot": "weapon", "keystone": "volta", "cards": ["tesla"], "text": "KEYSTONE: adds a Tesla Arc. Lightning jumps two more times."},
	"forcefield": {"name": "Force Field", "slot": "armor", "keystone": "volta", "stats": {"hp": 3, "armor_turn": 3}, "text": "KEYSTONE: Volta starts every turn with 3 more armor."},
	"fieldphone": {"name": "Field Phone", "slot": "kit", "keystone": "brass", "stats": {"luck": 1}, "text": "KEYSTONE: Designators drop two more shells."},
	"officersword": {"name": "Officer's Sabre", "slot": "weapon", "keystone": "brass", "stats": {"aim_dmg": 1}, "text": "KEYSTONE: Orders cost 0."},
	"supplytag": {"name": "Supply Tags", "slot": "kit", "keystone": "brass", "stats": {"luck": 1}, "text": "KEYSTONE: Supply Drop costs 0."},
	"radiopack": {"name": "Radio Pack", "slot": "kit", "keystone": "brass", "stats": {"armor_turn": 1}, "text": "KEYSTONE: Brass starts every mission with a Slug call."},
	"phaseorgan": {"name": "Phase Organ", "slot": "kit", "keystone": "sable", "stats": {"move": 30}, "text": "KEYSTONE: every Blink draws a card."},
	"acidgland": {"name": "Acid Gland", "slot": "weapon", "keystone": "sable", "cards": ["acidspit"], "text": "KEYSTONE: adds an Acid Spit. Acid deals 5 instead of 3."},
	"psicrown": {"name": "Psi Crown", "slot": "armor", "keystone": "sable", "stats": {"hp": 3}, "text": "KEYSTONE: mindlinked Jackals stay yours for two turns."},
	"wardencore": {"name": "Warden Core", "slot": "armor", "keystone": "sable", "stats": {"hp": 4}, "text": "KEYSTONE: Sable starts every turn under a dome."},
	"xrayscope": {"name": "X-Ray Scope", "slot": "weapon", "keystone": "moss", "stats": {"aim_dmg": 1}, "text": "KEYSTONE: AIM shots that pass through a wall deal +4 damage."},
	"radiohq": {"name": "Field Radio", "slot": "kit", "keystone": "hex", "stats": {"luck": 1}, "text": "KEYSTONE: Hand-Off also gives the receiver +1 energy."},
	"remotedet": {"name": "Remote Detonator", "slot": "kit", "keystone": "vee", "cards": ["stickycharge"], "text": "KEYSTONE: adds a Sticky Charge. Every turn starts with a free Clacker in hand."},
	"luchamask": {"name": "Luchador Mask", "slot": "armor", "keystone": "rook", "stats": {"hp": 4}, "text": "KEYSTONE: Suplex and Body Throw deal +6 and Stun."},
	"jumpjets": {"name": "Jump Jets", "slot": "kit", "keystone": "gears", "stats": {"move": 30}, "text": "KEYSTONE: Gears' walker has +20 HP and Stomp costs 0."},
	"treads": {"name": "Tank Treads", "slot": "armor", "keystone": "gears", "stats": {"hp": 4}, "cards": ["tankshell"], "text": "KEYSTONE: Gears deploys in a tank instead of a walker. Tank Shell joins his deck."},
	"ejectseat": {"name": "Ejector Seat", "slot": "kit", "keystone": "gears", "stats": {"luck": 1}, "text": "KEYSTONE: Eject! draws 2 cards and Gears lands with +1 energy."},
	"toolkit": {"name": "Mechanic's Toolkit", "slot": "kit", "keystone": "gears", "stats": {"armor_turn": 1}, "text": "KEYSTONE: every vehicle the squad drives has 50% more HP."},
	"chokechain": {"name": "Choke Chain", "slot": "weapon", "keystone": "track", "cards": ["sicem"], "text": "KEYSTONE: adds a Sic 'Em. Sic 'Em costs 0."},
	"treatbag": {"name": "Treat Bag", "slot": "kit", "keystone": "track", "stats": {"luck": 1}, "text": "KEYSTONE: Fetch costs 0."},
	"k9vest": {"name": "K9 Vest", "slot": "armor", "keystone": "track", "stats": {"hp": 4}, "text": "KEYSTONE: Rex has double HP and shrugs off 3 damage from every hit."},
	"hawkhood": {"name": "Hawk Hood", "slot": "kit", "keystone": "track", "stats": {"armor_turn": 1}, "text": "KEYSTONE: every turn the hawk dives on the Jackal nearest Track and Marks it."},
	"jetboots": {"name": "Jet Boots", "slot": "kit", "stats": {"jet": 90}, "text": "Press J, then hold the mouse to fly toward the cursor. Fuel refills each turn you start on the ground."},
	"guidance": {"name": "Guidance Chip", "slot": "kit", "stats": {"aim_dmg": 1}, "text": "Rockets think for themselves."},
	"napalmmix": {"name": "Napalm Mix", "slot": "kit", "stats": {"blast": 0.06}, "text": "Sticky, smelly, very flammable."},
	# B5: Vharr tech from the campaign's Alien Lab. Locked until built once; then runs roll it too (L2).
	"blinkpack": {"name": "Blink Pack", "slot": "kit", "cards": ["blink", "blink"], "locked": true, "vharr": true, "text": "Adds 2 Blink cards."},
	"gravlauncher": {"name": "Gravity Launcher", "slot": "weapon", "cards": ["gravnade", "gravnade"], "locked": true, "vharr": true, "text": "Adds 2 Gravity Grenade cards."},
	"domeprojector": {"name": "Dome Projector", "slot": "kit", "cards": ["domeup", "domeup"], "locked": true, "vharr": true, "text": "Adds 2 Dome Projector cards."},
	"prismplate": {"name": "Prism Plate", "slot": "armor", "stats": {"hp": 2, "reflect": 1}, "locked": true, "vharr": true, "text": "Reflects the first enemy shot each turn back at the shooter."},
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
	"move": {"v": 15, "fmt": "+%s move", "m": true},
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
	"desert": {"name": "Desert Rat", "bonus": {"move": 20, "dodge": 5}, "text": "Ghillie Suit, Grip Tape, Machete. 2 pieces: +1m move, +5 dodge."},
	"boar": {"name": "Boar Salvage", "bonus": {"armor_turn": 2, "hp": 4}, "text": "Riot Plate, Det Cord, Bazooka Tube. 2 pieces: +2 armor each turn, +4 max HP."},
}
const STAT_FMT := {
	"hp": "+%d max HP", "move": "+%s move", "dodge": "+%d dodge", "armor_turn": "+%d armor each turn",
	"kill_draw": "ON KILL: draw %d", "head_adr": "ON HEADSHOT: +%d adrenaline", "energy1": "+%d energy round 1",
	"luck": "+%d squad Luck", "laser_step": "+%d laser step", "sway": "-%d%% sway", "regen": "Heal %d each turn",
	"blast": "+%d%% blast size", "push_draw": "ON PUSH: draw %d", "kill_adr": "ON KILL: +%d adrenaline",
	"laser_pct": "+%d%% laser length", "heal": "+%d healing", "fall_half": "Half fall damage", "aim_dmg": "+%d AIM damage",
	"jet": "%d jet fuel", "light": "LIGHT: +%s move", "heavy": "HEAVY: -%s move, jets burn faster",
	"sa": "SIDEARM %d",
}
const PCT_STATS := ["sway", "blast", "laser_pct"]
const METER_STATS := ["move", "light", "heavy"]
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
	"alpha": {"name": "ALPHA", "vharr": true, "text": "Others of its kind within 8m act twice while it lives."},
	"anchored": {"name": "ANCHORED", "vharr": true, "text": "Can't be knocked back. Crush it or burn it."},
	"hungry": {"name": "HUNGRY", "vharr": true, "text": "Eats a body within 3m each turn to heal 8."},
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
const XTRAIN_PRICE := 60   # P3: Barracks cross-training
const DRILL_PRICE := 60    # B5: Drill Sergeant, one level for a soldier behind the squad's best

func cross_ok(key: String) -> bool:
	## Cards another class can learn: nothing that needs Rex, a vehicle or an Overdrive.
	var c: Dictionary = CARDS[key]
	return not c.get("od", false) and c.get("pool", true) and not c.has("dog") and not c.get("mech", false) and not key in ["whistle", "hounds", "guard", "supplyrun", "patchjob", "eject", "drill", "hop"]

func cross_pool(cls: String) -> Array:
	## Every other class's pool cards this class doesn't already have.
	var own: Array = []
	for d in SQUAD_DEFS:
		if d.key == cls:
			own = d.pool
	var out: Array = []
	for d in SQUAD_DEFS:
		if d.key == cls:
			continue
		for k in d.pool:
			if not own.has(k) and not out.has(k) and cross_ok(k):
				out.append(k)
	return out
# F3: a Jackal who surrendered in a BREACH and was walked out signs up as a recruit with this trait
const DEFECTOR_TRAIT := {"id": "defector", "name": "Defector", "text": "Ex-Jackal: knows their tricks. +3 max HP and +4 dodge."}
const CALLSIGNS := ["BISHOP", "DUKE", "FLINT", "GUNNER", "HAWK", "JINX", "KNOX", "LUCKY", "MAVERICK", "NOVA",
	"ONYX", "PATCH", "RAZOR", "SARGE", "SPUD", "TANK", "VIPER", "WREN", "YANK", "ZERO", "BLUE", "CROW", "DIESEL", "ROACH"]
# Recruit traits: shown before you hire, never rolled after.
const RECRUIT_TRAITS := [
	{"id": "quick", "name": "Quick", "text": "+1.2m movement. Starts with a Dash.", "card": "dash"},
	{"id": "tough", "name": "Tough", "text": "+5 max HP. Starts with Dig In.", "card": "digin"},
	{"id": "slippery", "name": "Slippery", "text": "+6 dodge. Starts with a Combat Roll.", "card": "roll"},
	{"id": "drilled", "name": "Drilled", "text": "Starts with one card upgraded."},
	# P2 backgrounds: a small buff and one starting card each
	{"id": "stuntman", "name": "Stuntman", "text": "Combat Roll costs 0. Starts with a Combat Roll.", "card": "roll"},
	{"id": "miner", "name": "Miner", "text": "The Drill bores twice as far. Starts with a second Drill.", "card": "drill"},
	{"id": "pilot", "name": "Pilot", "text": "Jet Boots carry 50% more fuel. Starts with a Jump Pack.", "card": "jumppack"},
	{"id": "excop", "name": "Ex-Cop", "text": "+4 dodge. Starts with a Flashbang.", "card": "flashbang"},
	{"id": "farmhand", "name": "Farmhand", "text": "+8 max HP. Starts with Sandbags.", "card": "sandbags"},
	{"id": "lifeguard", "name": "Lifeguard", "text": "Never drowns: swims back to the nearest shore. Starts with a Smoke Can.", "card": "smoke"},
	{"id": "boxer", "name": "Boxer", "text": "Melee cards deal +3. Starts with a Knife.", "card": "knife"},
	{"id": "hunter", "name": "Hunter", "text": "Starts every mission with 25 adrenaline. Starts with a Tag Round.", "card": "tagshot"},
	{"id": "corpsman", "name": "Corpsman", "text": "Heals 3 more. Starts with a Field Dressing.", "card": "medkit"},
]

const SQUAD_DEFS := [
	{"key": "moss", "name": "MOSS", "cls": "Marksman", "hp": 22, "dodge": 10, "spd": 180,
	 "deck": ["snipe", "snipe", "rifle", "rifle", "pistol", "overwatch", "digin", "dash", "drill"],
	 "pool": ["snipe", "rifle", "pistol", "burst", "overwatch", "digin", "dash", "roll", "grapple", "hmg", "adrenal", "tagshot", "bankshot", "holdbreath", "fanhammer", "quickdraw"],
	 "trait": ["Eagle Eye", "Headshots deal 2x damage instead of 1.5x."], "bio": "Former game warden. Counts every round twice."},
	{"key": "hex", "name": "HEX", "cls": "Field Medic", "hp": 24, "dodge": 14, "spd": 210,
	 "deck": ["medkit", "medkit", "stim", "pistol", "pistol", "smoke", "sprint", "frag", "drill"],
	 "pool": ["medkit", "stim", "smoke", "pistol", "sprint", "roll", "rally", "frag", "adrenal", "digin", "shotgun", "gasnade", "hotshot", "flashbang", "dartpistol", "defib", "handoff"],
	 "trait": ["Bedside Manner", "Heals restore +3 HP."], "bio": "Patched up three wars. Still hates the sight of blood."},
	{"key": "vee", "name": "VEE", "cls": "Demolitions", "hp": 27, "dodge": 6, "spd": 185,
	 "deck": ["frag", "frag", "bazooka", "bazooka", "mortar", "pistol", "jumppack", "sprint", "drill"],
	 "pool": ["frag", "mortar", "bazooka", "rocket", "clusterfrag", "beacon", "jumppack", "roll", "shotgun", "smoke", "gasnade", "rocketjump", "molotov", "shapedcharge", "stickycharge", "clacker"],
	 "trait": ["Pyromaniac", "Explosions deal +3 damage. Her own blasts hurt her for 40%."], "bio": "Measures distance in fuse-seconds."},
	{"key": "rook", "name": "ROOK", "cls": "Vanguard", "hp": 32, "dodge": 8, "spd": 200,
	 "deck": ["rifle", "rifle", "rifle", "burst", "sprint", "knife", "frag", "grapple", "drill"],
	 "pool": ["rifle", "burst", "shotgun", "hmg", "knife", "digin", "grapple", "sprint", "roll", "rally", "adrenal", "tagshot", "haymaker", "taunt", "suppress", "grab", "suplex"],
	 "trait": ["Thick Skull", "Takes half damage from falls, slams and crushing debris."], "bio": "First through every door. Usually the wrong one."},
	# N2: unlocked by freeing him as a specialist POW (X2)
	{"key": "bolt", "name": "BOLT", "cls": "Combat Engineer", "hp": 26, "dodge": 8, "spd": 190,
	 "deck": ["sandbags", "sandbags", "sentry", "girder", "rivetgun", "rivetgun", "pistol", "sprint", "drill"],
	 "pool": ["sandbags", "sentry", "girder", "jumppad", "rivetgun", "wrench", "weld", "shotgun", "pistol", "sprint", "digin", "frag", "roll", "rally", "shapedcharge"],
	 "trait": ["Toolbelt", "Everything Bolt builds is 50% bigger, and his sentries have 50% more HP."], "bio": "Built a bridge under fire once. Still sends the invoice."},
	# N7: Track fights with Rex, who only moves when Track plays a dog card
	{"key": "track", "name": "TRACK", "cls": "K9 Handler", "hp": 25, "dodge": 10, "spd": 195,
	 "deck": ["sicem", "sicem", "fetch", "whistle", "rifle", "rifle", "pistol", "sprint", "drill"],
	 "pool": ["sicem", "fetch", "guard", "whistle", "rifle", "pistol", "burst", "shotgun", "sprint", "roll", "digin", "smoke", "frag", "rally", "tagshot"],
	 "trait": ["Best Friend", "Rex deploys with Track. If Rex is knocked out he's back at Track's side next turn."], "bio": "Raised Rex from a pup. Talks to him more than to people."},
	# N3: Gears starts every mission in a walker. Its cards only work from inside a vehicle.
	{"key": "gears", "name": "GEARS", "cls": "Slug Pilot", "hp": 22, "dodge": 6, "spd": 170,
	 "deck": ["vulcan", "vulcan", "mcannon", "stomp", "eject", "patchjob", "pistol", "pistol", "drill"],
	 "pool": ["vulcan", "mcannon", "stomp", "eject", "patchjob", "tankshell", "pistol", "shotgun", "frag", "sprint", "roll", "digin", "rifle", "smoke"],
	 "trait": ["Grease Monkey", "Gears deploys in a walker, and every camp rebuilds it to full."], "bio": "Learned to drive in a stolen Slug. Never gave it back."},
	# N1, N4, N5, N6, N8
	{"key": "finch", "name": "FINCH", "cls": "Scout", "hp": 20, "dodge": 16, "spd": 260,
	 "deck": ["zipline", "flare", "drone", "knives", "knives", "pistol", "sprint", "roll", "drill"],
	 "pool": ["zipline", "flare", "drone", "knives", "pistol", "sprint", "roll", "dash", "smoke", "grapple", "frag", "tagshot", "quickdraw"],
	 "trait": ["Light Feet", "The fastest soldier in the squad, and she never sets off Jackal mines."], "bio": "Ran messages through three sieges. Never got caught."},
	{"key": "kage", "name": "KAGE", "cls": "Commando", "hp": 22, "dodge": 18, "spd": 215,
	 "deck": ["katana", "katana", "deflect", "walljump", "vanish", "pistol", "sprint", "knife", "drill"],
	 "pool": ["katana", "deflect", "walljump", "vanish", "knife", "pistol", "sprint", "roll", "smoke", "grapple", "dash"],
	 "trait": ["Cat's Landing", "Kage never takes fall damage."], "bio": "Trained in the palace the Jackals now hold. Wants it back."},
	{"key": "volta", "name": "VOLTA", "cls": "Gravitech", "hp": 23, "dodge": 10, "spd": 190,
	 "deck": ["magnet", "repulsor", "tesla", "gravnade", "pistol", "pistol", "frag", "sprint", "drill"],
	 "pool": ["magnet", "repulsor", "tesla", "gravnade", "frag", "pistol", "sprint", "roll", "smoke", "shotgun", "domeup"],
	 "trait": ["Physics Major", "Wind never moves anything Volta throws."], "bio": "Built her first gravity gun out of a fridge. Insists it was on purpose."},
	{"key": "brass", "name": "BRASS", "cls": "Forward Officer", "hp": 24, "dodge": 8, "spd": 180,
	 "deck": ["designator", "designator", "orders", "supplydrop", "pistol", "rifle", "rifle", "sprint", "drill"],
	 "pool": ["designator", "orders", "supplydrop", "rifle", "pistol", "rally", "smoke", "beacon", "digin", "overwatch", "sprint"],
	 "trait": ["Chain of Command", "Every turn the squadmate nearest Brass gets +1 energy."], "bio": "Thirty years of radio static. Can hear a shell's caliber in its whistle."},
	{"key": "sable", "name": "SABLE", "cls": "Vharr Splicer", "hp": 24, "dodge": 12, "spd": 200,
	 "deck": ["blink", "tongue", "acidspit", "acidspit", "mindlink", "pistol", "pistol", "sprint", "drill"],
	 "pool": ["blink", "tongue", "acidspit", "mindlink", "domeup", "gravnade", "pistol", "shotgun", "sprint", "roll", "smoke"],
	 "trait": ["Hybrid", "Immune to acid and Toxic."], "bio": "Volunteered for the splice. The doctors still won't say what else it did."},
]
# X1: the four you start with. Everyone else is a specialist you free once to unlock (X2).
const BASE_CLASSES := ["moss", "hex", "vee", "rook"]
# X2: each specialist is held in a run as a named POW. Free them and they join the squad for the
# rest of that run, and their class goes into the squad draft for good.
const SPECIALISTS := {
	"bolt": {"pow": "Sgt. Bolt", "text": "A combat engineer the Jackals grabbed fixing their own bridge."},
	"track": {"pow": "Cpl. Track", "text": "A K9 handler caught behind the lines. Rex wouldn't leave him."},
	"gears": {"pow": "Pvt. Gears", "text": "A slug pilot the Jackals pulled out of a wreck. He wants a new ride."},
	"finch": {"pow": "Pvt. Finch", "text": "The squad's fastest runner. She got caught carrying a message she'd already delivered."},
	"kage": {"pow": "Sgt. Kage", "text": "A commando the Jackals took by surprise, once."},
	"volta": {"pow": "Dr. Volta", "text": "A physicist the Jackals wanted for her magnet gun."},
	"brass": {"pow": "Maj. Brass", "text": "A forward officer held for the codes in his head."},
	"sable": {"pow": "Sable", "text": "A Vharr splice the Jackals keep in a cage. Sable wants a word with the Vharr."},
}
const RESCUES_PER_RUN := 2  # at most this many specialists turn up in one run (level 1 and level 2)

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
		{"id": "wallbanger", "name": "Wallbanger", "od": "xray", "keystone": "xrayscope",
		 "chain": {"name": "KNOCK KNOCK", "text": "Dig In, then any AIM card: the shot goes through every wall of wood and dirt."},
		 "perks": [{"id": "softpoint", "name": "Punch Through", "text": "Moss's AIM shots go through one wall of wood or dirt."},
			{"id": "overpen", "name": "Over-Penetration", "text": "Moss's AIM shots also go through one body."},
			{"id": "fullmetal", "name": "Full Metal", "text": "Moss's AIM shots go through all wood and dirt."}]},
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
			{"id": "badbatch", "name": "Bad Batch", "text": "Hex's heals poison Jackals within 4.5m of the patient."},
			{"id": "pandemic", "name": "Pandemic", "text": "Toxic Jackals spread Toxic to their friends when they die."}]},
		{"id": "surgeon", "name": "Battle Surgeon", "od": "triagefield", "keystone": "medrig",
		 "chain": {"name": "SCRUBBED IN", "text": "Heal, then Shotgun on the same turn: +3 pellets."},
		 "perks": [{"id": "triage", "name": "Triage", "text": "Heals restore +4 more HP."},
			{"id": "hardplates", "name": "Hard Plates", "text": "Healing past max HP becomes armor."},
			{"id": "lazarus", "name": "Lazarus", "text": "Once a mission, a squadmate who drops gets back up at 30% HP."}]},
		{"id": "coordinator", "name": "Coordinator", "od": "synchronize", "keystone": "radiohq",
		 "chain": {"name": "TEAMWORK", "text": "Hand-Off, then Medkit: the Medkit is free."},
		 "perks": [{"id": "quickpass", "name": "Quick Pass", "text": "Hand-Offs cost 0."},
			{"id": "assist", "name": "Assist", "text": "Whoever gets a Hand-Off also draws a card."},
			{"id": "switcheroo", "name": "Switcheroo", "text": "Every turn Hex gets a free Switcheroo: swap places with any squadmate."}]},
	],
	"vee": [
		{"id": "artillerist", "name": "Artillerist", "od": "barrage", "keystone": "howitzer",
		 "chain": {"name": "CRATER", "text": "Two of Vee's blasts on the same spot in one turn: a big crater, and everyone in it is stunned."},
		 "perks": [{"id": "bigboom", "name": "Bigger Booms", "text": "Vee's blasts are 20% bigger."},
			{"id": "rangefinder", "name": "Rangefinder", "text": "Vee's blasts deal +2 damage per 10m they travelled."},
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
		{"id": "sapper", "name": "Sapper", "od": "daisychain", "keystone": "remotedet",
		 "chain": {"name": "SET AND FORGET", "text": "Sticky Charge, then Clacker: the blast is 50% bigger."},
		 "perks": [{"id": "bigcharge", "name": "Shaped Charges", "text": "Sticky Charges blast +10 wider."},
			{"id": "tripwire", "name": "Tripwire", "text": "Sticky Charges blow when a Jackal comes within 2.5m, not just on top."},
			{"id": "chainreact", "name": "Chain Reaction", "text": "Clacker sets off every Sticky Charge at once, each +4 damage."}]},
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
		 "perks": [{"id": "charge", "name": "Charge!", "text": "+3m movement every turn."},
			{"id": "hookshot", "name": "Hookshot", "text": "Grappling next to a Jackal yanks it off its feet toward Rook."},
			{"id": "blitz", "name": "Blitz", "text": "Every push puts a free Knife in Rook's hand."}]},
		{"id": "wrestler", "name": "Wrestler", "od": "piledrive", "keystone": "luchamask",
		 "chain": {"name": "TAG OUT", "text": "Grab, then Body Throw: refund 1 energy."},
		 "perks": [{"id": "grip", "name": "Iron Grip", "text": "Grab costs 0."},
			{"id": "bodyslam", "name": "Body Slam", "text": "Thrown and suplexed Jackals take +6 damage."},
			{"id": "titan", "name": "Titan", "text": "Rook can grab and suplex Brutes and heavy aliens too."}]},
	],
	"bolt": [
		{"id": "turrettech", "name": "Turret Tech", "od": "sentrynest", "keystone": "turretcore",
		 "chain": {"name": "COVERING FIRE", "text": "Sentry Gun, then any AIM card: every one of Bolt's sentries fires with you."},
		 "perks": [{"id": "twinbarrel", "name": "Twin Barrels", "text": "Sentries fire twice."},
			{"id": "secondsentry", "name": "Spare Parts", "text": "Each Sentry Gun card deploys two sentries."},
			{"id": "autoloader", "name": "Autoloader", "text": "Sentries also fire at the start of your turn."}]},
		{"id": "fortifier", "name": "Fortifier", "od": "ironcurtain", "keystone": "rebar",
		 "chain": {"name": "DOUBLE STACK", "text": "The second Sandbags Bolt throws in a turn is free."},
		 "perks": [{"id": "concrete", "name": "Poured Concrete", "text": "Bolt's walls are concrete: bullets bounce off instead of chewing in."},
			{"id": "hunker", "name": "Hunker Down", "text": "Squadmates standing next to a wall Bolt built start their turn with 4 armor."},
			{"id": "bulwark", "name": "Bulwark", "text": "Sandbags cost 0."}]},
		{"id": "bridgewright", "name": "Bridgewright", "od": "steelrain", "keystone": "rivetdriver",
		 "chain": {"name": "CUT LOOSE", "text": "Girder, then drop it the same turn: refund 1 energy."},
		 "perks": [{"id": "heavysteel", "name": "Heavy Steel", "text": "Bolt's girders are twice as thick and crush harder."},
			{"id": "longspan", "name": "Long Span", "text": "Bolt's girders are 50% longer and reach twice as far."},
			{"id": "piledriver", "name": "Pile Driver", "text": "A girder placed over a Jackal drops on it at once."}]},
		{"id": "scrapper", "name": "Scrapper", "od": "junkcannon", "keystone": "magnetglove",
		 "chain": {"name": "SCRAPHEAP", "text": "A Big Wrench kill puts a free Sandbags in Bolt's hand."},
		 "perks": [{"id": "salvager", "name": "Salvager", "text": "Bolt's kills put a free Sandbags in his hand, once a turn."},
			{"id": "scraparmor", "name": "Scrap Armor", "text": "Bolt gains 3 armor every time he builds something."},
			{"id": "recycler", "name": "Recycler", "text": "Every build card Bolt plays draws a card."}]},
	],
	"track": [
		{"id": "packleader", "name": "Pack Leader", "od": "wolfpack", "keystone": "chokechain",
		 "chain": {"name": "TAG TEAM", "text": "Sic 'Em, then any AIM card: a guaranteed headshot."},
		 "perks": [{"id": "bigdog", "name": "Big Dog", "text": "Rex's bites deal +3 damage."},
			{"id": "secondbite", "name": "Second Helping", "text": "Sic 'Em bites twice."},
			{"id": "alpha", "name": "Alpha", "text": "Rex's bites Stun."}]},
		{"id": "retriever", "name": "Retriever", "od": "supplyrun", "keystone": "treatbag",
		 "chain": {"name": "GOOD BOY", "text": "Fetch, then Whistle: +1 energy."},
		 "perks": [{"id": "longleash", "name": "Long Leash", "text": "Fetch and Sic 'Em reach 50% farther."},
			{"id": "pockets", "name": "Deep Pockets", "text": "Every Fetch draws a card."},
			{"id": "scrounger", "name": "Scrounger", "text": "Every Fetch digs up 10 scrip."}]},
		{"id": "guarddog", "name": "Guard Dog", "od": "stampede", "keystone": "k9vest",
		 "chain": {"name": "ON GUARD", "text": "Guard, then any attack card: the guarded squadmate gets 5 armor."},
		 "perks": [{"id": "hardtackle", "name": "Hard Tackle", "text": "Guard tackles deal +6 damage and throw the Jackal back."},
			{"id": "watchdog", "name": "Watchdog", "text": "When Rex isn't guarding anyone, he guards Track."},
			{"id": "loyal", "name": "Loyal", "text": "Rex keeps guarding after a tackle, once per Jackal."}]},
		{"id": "falconer", "name": "Falconer", "od": "skyfall", "keystone": "hawkhood",
		 "chain": {"name": "THE HUNT", "text": "Whistle, then Sic 'Em: the bite deals double and Marks."},
		 "perks": [{"id": "markbite", "name": "Marked Prey", "text": "Rex's bites Mark."},
			{"id": "huntcall", "name": "Hunting Call", "text": "Whistle draws 2 cards instead of 1."},
			{"id": "talons", "name": "Talons", "text": "Hawk dives deal +6 damage."}]},
	],
	"gears": [
		{"id": "walkerbranch", "name": "Walker", "od": "missilepod", "keystone": "jumpjets",
		 "chain": {"name": "WALK THE LINE", "text": "Vulcan, then Stomp: refund 1 energy."},
		 "perks": [{"id": "heavystomp", "name": "Heavy Stomp", "text": "Stomp deals +6 and hits everything next to the walker."},
			{"id": "legservos", "name": "Leg Servos", "text": "+3m movement while in a vehicle."},
			{"id": "armorplate", "name": "Armor Plate", "text": "Gears' walker has +15 HP."}]},
		{"id": "tankslug", "name": "Tank Slug", "od": "tankbuster", "keystone": "treads",
		 "chain": {"name": "BROADSIDE", "text": "Walker Cannon twice in a turn: the second is free."},
		 "perks": [{"id": "bigbore", "name": "Big Bore", "text": "Walker Cannon and Tank Shell blasts +10."},
			{"id": "reactive", "name": "Reactive Armor", "text": "Gears' vehicle takes 2 less damage from every hit."},
			{"id": "crusher", "name": "Crusher", "text": "Stomp and Walker Cannon cost 1 less."}]},
		{"id": "ejectartist", "name": "Eject Artist", "od": "fullsend", "keystone": "ejectseat",
		 "chain": {"name": "BAIL OUT", "text": "Eject!, then Patch Job: Patch Job is free."},
		 "perks": [{"id": "biggerboom", "name": "Bigger Boom", "text": "Eject! blasts are 50% bigger."},
			{"id": "softlanding", "name": "Soft Landing", "text": "Ejecting gives Gears 8 armor."},
			{"id": "quickpatch", "name": "Quick Patch", "text": "Patch Job costs 1 less."}]},
		{"id": "mechanic", "name": "Mechanic", "od": "convoy", "keystone": "toolkit",
		 "chain": {"name": "PIT STOP", "text": "Patch Job, then any attack card: +1 energy."},
		 "perks": [{"id": "tuneup", "name": "Tune-Up", "text": "Every vehicle the squad drives repairs 6 HP each turn."},
			{"id": "hotwire", "name": "Hotwire", "text": "Anyone who hijacks a vehicle gets +1 energy and a free Vulcan."},
			{"id": "motorpool", "name": "Motor Pool", "text": "Gears starts each mission with a Slug call card."}]},
	],
	"finch": [
		{"id": "trailblazer", "name": "Trailblazer", "od": "skyline", "keystone": "carabiner",
		 "chain": {"name": "ZIP AND SNIP", "text": "Zipline, then any AIM card: +1 energy."},
		 "perks": [{"id": "longline", "name": "Long Line", "text": "Ziplines reach 50% farther and carry squadmates within 7m."},
			{"id": "freefall", "name": "Free Fall", "text": "Finch's movement is +60, and Zipline draws a card."},
			{"id": "groupride", "name": "Group Ride", "text": "Everyone who rides a Zipline gets +2m movement."}]},
		{"id": "spotterb", "name": "Spotter", "od": "starshell", "keystone": "flaregun",
		 "chain": {"name": "LIGHT 'EM UP", "text": "Flare, then any AIM card: a guaranteed headshot."},
		 "perks": [{"id": "brightflare", "name": "Bright Flare", "text": "Flares light up 2m wider."},
			{"id": "spotcrit", "name": "Spotter", "text": "FLARED Jackals take +6 instead of +3."},
			{"id": "illum", "name": "Illumination", "text": "Flares also Suppress."}]},
		{"id": "dronejockey", "name": "Drone Jockey", "od": "dronestrike", "keystone": "dronebay",
		 "chain": {"name": "EYE IN THE SKY", "text": "Recon Drone, then Throwing Knives: the knives are free."},
		 "perks": [{"id": "dronegun", "name": "Drone Gun", "text": "The drone also fires a 3-round burst at its target."},
			{"id": "twindrone", "name": "Second Drone", "text": "Recon Drone makes two runs on two Jackals."},
			{"id": "dronemark", "name": "Laser Designator", "text": "The drone's target is FLARED."}]},
		{"id": "saboteur", "name": "Saboteur", "od": "rigged", "keystone": "thermite",
		 "chain": {"name": "KNIFE PARTY", "text": "Throwing Knives twice in a turn: the second pair is free."},
		 "perks": [{"id": "loaded", "name": "Loaded Knives", "text": "Throwing Knives deal +2."},
			{"id": "boobytrap", "name": "Booby Trap", "text": "Jackals Finch kills explode: blast 30, 8 damage."},
			{"id": "demoexpert", "name": "Demo Expert", "text": "Barrels and fuel tanks Finch sets off hit twice as hard."}]},
	],
	"kage": [
		{"id": "reflector", "name": "Reflector", "od": "mirrorwall", "keystone": "mirrorblade",
		 "chain": {"name": "RIPOSTE", "text": "Deflect, then Katana: the cut Stuns."},
		 "perks": [{"id": "doubledeflect", "name": "Twin Guard", "text": "Deflect sends back two bullets."},
			{"id": "returnfire", "name": "Return to Sender", "text": "Deflected bullets hit twice as hard."},
			{"id": "parry", "name": "Parry", "text": "Every Katana also readies a Deflect."}]},
		{"id": "shadow", "name": "Shadow", "od": "shadowstrike", "keystone": "shinobi",
		 "chain": {"name": "FROM NOWHERE", "text": "Smoke Bomb, then Katana: double damage."},
		 "perks": [{"id": "ambush", "name": "Ambush", "text": "Kage starts every mission as PREDATOR."},
			{"id": "backstab", "name": "Backstab", "text": "Katana from behind a Jackal deals double."},
			{"id": "smokeghost", "name": "Ghost", "text": "Smoke Bomb costs 0."}]},
		{"id": "wallrunner", "name": "Wall Runner", "od": "wallrun", "keystone": "climbclaws",
		 "chain": {"name": "AIR STRIKE", "text": "Wall Jump, then Katana: +1 energy."},
		 "perks": [{"id": "freerunning", "name": "Free Running", "text": "+3m movement every turn."},
			{"id": "springheel", "name": "Spring Heel", "text": "Wall Jump costs 0."},
			{"id": "aerial", "name": "Aerial", "text": "Katana from the air deals +6."}]},
		{"id": "iaidoka", "name": "Iaido", "od": "iaido", "keystone": "ancestral",
		 "chain": {"name": "DRAW CUT", "text": "Katana twice in a turn: the second is free."},
		 "perks": [{"id": "keenedge", "name": "Keen Edge", "text": "Katana deals +3."},
			{"id": "sweepcut", "name": "Sweeping Cut", "text": "Katana hits every Jackal in reach."},
			{"id": "terraincut", "name": "Cut the Mountain", "text": "Katana cuts through the terrain in front of Kage."}]},
	],
	"volta": [
		{"id": "magnetist", "name": "Magnetist", "od": "railgun", "keystone": "magboots",
		 "chain": {"name": "SLINGSHOT", "text": "Magnet Gun, then Repulsor: the Repulsor is free."},
		 "perks": [{"id": "heavypull", "name": "Heavy Pull", "text": "Magnet Gun and Repulsor throw 50% harder."},
			{"id": "magstorm", "name": "Mag Storm", "text": "Magnet Gun and Repulsor move every body on the line."},
			{"id": "fieldlock", "name": "Field Lock", "text": "Jackals Volta moves are Suppressed."}]},
		{"id": "graviton", "name": "Graviton", "od": "blackhole", "keystone": "gravcore",
		 "chain": {"name": "EVENT HORIZON", "text": "Gravity Grenade, then Magnet Gun: the Magnet Gun is free."},
		 "perks": [{"id": "widewell", "name": "Wide Well", "text": "Gravity Grenades pull from 2m farther."},
			{"id": "crushwell", "name": "Crush Well", "text": "Jackals in Volta's wells take 5."},
			{"id": "doublewell", "name": "Aftershock", "text": "Gravity Grenades pull twice."}]},
		{"id": "teslab", "name": "Tesla", "od": "stormcage", "keystone": "teslacoil",
		 "chain": {"name": "CONDUCTOR", "text": "Tesla Arc twice in a turn: the second is free."},
		 "perks": [{"id": "arcjump", "name": "Arc Jump", "text": "Lightning jumps to two more Jackals."},
			{"id": "stunbolt", "name": "Stun Bolt", "text": "Lightning Stuns."},
			{"id": "overload", "name": "Overload", "text": "Lightning deals +3."}]},
		{"id": "kinetic", "name": "Kinetic", "od": "shockwave", "keystone": "forcefield",
		 "chain": {"name": "NEWTON'S THIRD", "text": "Repulsor, then Magnet Gun: +1 energy."},
		 "perks": [{"id": "strongpush", "name": "Big Push", "text": "Repulsor reaches 50% farther."},
			{"id": "kinimpact", "name": "Kinetic Impact", "text": "Magnet Gun and Repulsor deal 6 to every Jackal they move."},
			{"id": "recoilshield", "name": "Recoil Shield", "text": "Every Repulsor gives Volta 4 armor."}]},
	],
	"brass": [
		{"id": "observer", "name": "Observer", "od": "creeping", "keystone": "fieldphone",
		 "chain": {"name": "BRACKET", "text": "Designator twice in a turn: the second is free."},
		 "perks": [{"id": "spotround", "name": "Spotting Round", "text": "Designator drops one more shell."},
			{"id": "rangefind", "name": "Rangefinder", "text": "Designator costs 0."},
			{"id": "ffe", "name": "Fire for Effect", "text": "Every beacon Brass throws drops two more shells."}]},
		{"id": "officer", "name": "Officer", "od": "rallycry", "keystone": "officersword",
		 "chain": {"name": "ON MY MARK", "text": "Orders, then Designator: +1 energy."},
		 "perks": [{"id": "command", "name": "Command Voice", "text": "Orders give +2 energy instead of 1."},
			{"id": "inspire", "name": "Inspire", "text": "Chain of Command reaches the two nearest squadmates."},
			{"id": "leadfront", "name": "Lead from the Front", "text": "Squadmates within 7m of Brass start their turn with +2m movement."}]},
		{"id": "quartermaster", "name": "Quartermaster", "od": "airdrop", "keystone": "supplytag",
		 "chain": {"name": "RESUPPLY", "text": "Supply Drop, then Orders: the Orders are free."},
		 "perks": [{"id": "provisions", "name": "Provisions", "text": "Supply Drop also heals the squad 6."},
			{"id": "logistics", "name": "Logistics", "text": "Supply Drop costs 1 less."},
			{"id": "stockpile", "name": "Stockpile", "text": "Supply Drop draws a card for every squadmate."}]},
		{"id": "signals", "name": "Signals", "od": "slugcall", "keystone": "radiopack",
		 "chain": {"name": "CALL IT IN", "text": "Designator, then any AIM card: a guaranteed headshot."},
		 "perks": [{"id": "intelrep", "name": "Intel", "text": "Every turn the Jackal nearest Brass is Marked."},
			{"id": "airsupport", "name": "Air Support", "text": "Every beacon anyone throws drops one more shell."},
			{"id": "netcall", "name": "Net Call", "text": "When the Jackals move, every squadmate has at least 1 overwatch shot."}]},
	],
	"sable": [
		{"id": "blinker", "name": "Blinker", "od": "phaseshift", "keystone": "phaseorgan",
		 "chain": {"name": "NOW YOU SEE ME", "text": "Blink, then any attack card: double damage on an AIM card, +1 energy otherwise."},
		 "perks": [{"id": "doubleblink", "name": "Double Blink", "text": "Blink costs 0."},
			{"id": "decoy", "name": "Afterimage", "text": "Blink leaves Sable PREDATOR."},
			{"id": "blinkstrike", "name": "Blink Strike", "text": "Blink claws the Jackal Sable lands behind for 8."}]},
		{"id": "corroder", "name": "Corroder", "od": "acidrain", "keystone": "acidgland",
		 "chain": {"name": "MELTDOWN", "text": "Acid Spit, then Tongue: the Tongue is free."},
		 "perks": [{"id": "meltarmor", "name": "Melt Armor", "text": "Acid makes Jackals Toxic."},
			{"id": "dissolve", "name": "Dissolve", "text": "Acid Spit eats the terrain where it lands."},
			{"id": "potent", "name": "Potent", "text": "Acid puddles are 50% wider and last a turn longer."}]},
		{"id": "mindlinker", "name": "Mindlink", "od": "hivemind", "keystone": "psicrown",
		 "chain": {"name": "PUPPETEER", "text": "Mindlink, then Tongue: +1 energy."},
		 "perks": [{"id": "biglink", "name": "Strong Mind", "text": "Mindlink takes anything but a boss."},
			{"id": "longlink", "name": "Deep Link", "text": "Mindlink costs 1 less."},
			{"id": "linkheal", "name": "Feedback", "text": "Sable heals 6 for every Mindlink."}]},
		{"id": "wardenb", "name": "Warden", "od": "domefield", "keystone": "wardencore",
		 "chain": {"name": "HOLD STILL", "text": "Gravity Grenade, then Acid Spit: the Acid Spit is free."},
		 "perks": [{"id": "domeself", "name": "Carapace", "text": "Sable starts every turn with 3 armor."},
			{"id": "domeshare", "name": "Shared Dome", "text": "Dome Projector reaches 4m farther."},
			{"id": "wellsable", "name": "Gravity Gland", "text": "Gravity Grenade costs 0."}]},
	],
}
# P1: taking a branch's capstone earns a prestige title, a gold pin on the headgear and a small
# second trait (by the branch's place in the class: tough, fleet, slippery, seasoned).
const PRESTIGE := {
	"ricochet": "Trickshot Ace",
	"headhunter": "Deadeye",
	"sentinel": "Overwatch Master",
	"gunslinger": "Pistolero",
	"wallbanger": "Wall Breaker",
	"juicer": "Adrenaline Junkie",
	"ghost": "Phantom Medic",
	"chemist": "Mad Chemist",
	"surgeon": "Chief Surgeon",
	"coordinator": "Field Coordinator",
	"artillerist": "Master Gunner",
	"rocketjumper": "Sky Demon",
	"pyro": "Firestarter",
	"wrecker": "Demolisher",
	"sapper": "Master Sapper",
	"bowler": "Human Cannonball",
	"juggernaut": "Unstoppable",
	"heavy": "Bullet Hose",
	"breacher": "Door Kicker",
	"wrestler": "Champion",
	"turrettech": "Gun Wizard",
	"fortifier": "Bunker King",
	"bridgewright": "Master Builder",
	"scrapper": "Junk King",
	"packleader": "Alpha",
	"retriever": "Fetch Master",
	"guarddog": "Watchman",
	"falconer": "Hawkeye",
	"walkerbranch": "Mech Ace",
	"tankslug": "Tank Ace",
	"ejectartist": "Crash Test Pilot",
	"mechanic": "Grease Wizard",
	"trailblazer": "Pathfinder",
	"spotterb": "Lamplighter",
	"dronejockey": "Drone Ace",
	"saboteur": "Ghost Saboteur",
	"reflector": "Bulletproof Blade",
	"shadow": "Night Shadow",
	"wallrunner": "Free Runner",
	"iaidoka": "Sword Saint",
	"magnetist": "Magnet Queen",
	"graviton": "Event Horizon",
	"teslab": "Storm Caller",
	"kinetic": "Force of Nature",
	"observer": "Hammer of God",
	"officer": "Colonel",
	"quartermaster": "Supply Lord",
	"signals": "Voice of Command",
	"blinker": "Phase Walker",
	"corroder": "Acid Queen",
	"mindlinker": "Puppet Master",
	"wardenb": "Hive Warden",
}
const PRESTIGE_TRAITS := [
	{"name": "Battle-Hardened", "text": "+4 max HP.", "hp": 4},
	{"name": "Fleet", "text": "+1.2m movement.", "move": 25},
	{"name": "Ghosting", "text": "+5 dodge.", "dodge": 5},
	{"name": "Old Hand", "text": "+4 max HP and +0.5m movement.", "hp": 4, "move": 10},
]
const PERK_TIER := ["MINOR", "MAJOR", "CAPSTONE"]

# Legendary keystone items live in ITEMS (one per archetype). Anyone can wear one, which makes hybrids.
const KEYSTONE_IDS := ["tungsten", "varga", "claymore", "twinrev", "overcharger", "canister", "weathervane", "medrig", "howitzer", "lizard", "fuelpack", "detbox", "gauntlet", "riotshield", "ammobelt", "zantetsu", "turretcore", "rebar", "rivetdriver", "magnetglove", "chokechain", "treatbag", "k9vest", "hawkhood", "jumpjets", "treads", "ejectseat", "toolkit", "xrayscope", "radiohq", "remotedet", "luchamask", "carabiner", "flaregun", "dronebay", "thermite", "mirrorblade", "shinobi", "climbclaws", "ancestral", "magboots", "gravcore", "teslacoil", "forcefield", "fieldphone", "officersword", "supplytag", "radiopack", "phaseorgan", "acidgland", "psicrown", "wardencore"]

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
	{"pair": ["bolt", "rook"], "card": "buildcrew", "holder": "bolt"},
	{"pair": ["bolt", "vee"], "card": "demoteam", "holder": "bolt"},
	{"pair": ["finch", "moss"], "card": "paintedtarget", "holder": "finch"},
	{"pair": ["finch", "vee"], "card": "payload", "holder": "finch"},
	{"pair": ["kage", "moss"], "card": "mirrormatch", "holder": "kage"},
	{"pair": ["vee", "volta"], "card": "delivery", "holder": "volta"},
	{"pair": ["rook", "volta"], "card": "slingshot", "holder": "volta"},
	{"pair": ["brass", "vee"], "card": "firemission", "holder": "brass"},
	{"pair": ["sable", "vee"], "card": "bilebomb", "holder": "sable"},
	{"pair": ["gears", "rook"], "card": "ridealong", "holder": "gears"},
	{"pair": ["gears", "hex"], "card": "fieldrefit", "holder": "gears"},
	{"pair": ["hex", "track"], "card": "meddog", "holder": "track"},
	{"pair": ["moss", "track"], "card": "k9strike", "holder": "track"},
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
# R2-R4: one mid-level event per quick-run level, announced on the briefing
const EVENTS := {
	"fireteam": {"name": "ALLIED FIRE TEAM", "text": "Two friendly riflemen are pinned down in the first stretch. Reach them and they fight beside you until the next camp."},
	"collapse": {"name": "COLLAPSE RUN", "text": "The second stretch crumbles behind you, 6m every round. The edge is marked. Push or fall."},
	"dealer": {"name": "ARMS DEALER", "text": "A trader holds out in a bunker at the end of the first stretch: three items, fixed prices. Walk up to trade."},
}
const CRUMBLE_STEP := 120.0
const DEALER_MUL := 0.75  # the dealer's prices against the Quartermaster's

# R5: the bounty board. Three per level, fixed rewards paid on the debrief
const BOUNTIES := [
	{"id": "nofall", "name": "SURE FOOTED", "text": "Nobody in the squad takes fall damage.", "pay": 30},
	{"id": "nodown", "name": "NOBODY DOWN", "text": "No soldier goes down.", "pay": 40},
	{"id": "sniperfirst", "name": "COUNTER-SNIPE", "text": "The first Jackal you kill is a Sniper.", "pay": 35},
	{"id": "crush2", "name": "TIMBER", "text": "Crush 2 Jackals under falling terrain.", "pay": 35},
	{"id": "pows", "name": "NO ONE LEFT BEHIND", "text": "Free every POW.", "pay": 30},
	{"id": "push3", "name": "FORWARD", "text": "Push the screen forward 3 times.", "pay": 30},
	{"id": "fast", "name": "BLITZ", "text": "Beat the level in 18 rounds or fewer.", "pay": 40},
	{"id": "melee3", "name": "UP CLOSE", "text": "Kill 3 enemies with melee.", "pay": 30},
]

# D3: fun toggles, unlocked by Armory feats and switched on at the Memorial. Nothing gets harder
const TOGGLES := [
	{"id": "bigheads", "short": "Huge heads.", "name": "BIG HEADS", "feat": "skeet", "text": "Everyone's head is huge."},
	{"id": "moon", "short": "Half gravity.", "name": "MOON GRAVITY", "feat": "timber", "text": "Half gravity: jumps, throws and knockback carry twice as far."},
	{"id": "nades", "short": "Every kill drops a frag.", "name": "GRENADE RAIN", "feat": "pyro", "text": "Every Jackal drops a Frag Grenade when it dies."},
	{"id": "bouncy", "short": "Bodies bounce.", "name": "BOUNCY BODIES", "feat": "pinball", "text": "Bodies bounce."},
]

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
# B4: campaign-only buildings, each opening with an act (index into ACTS)
const CAMP_BUILDINGS := [
	{"id": "comms", "name": "COMMS", "act": 1, "ranks": ["The brief lists the sector's enemies.", "Your first hit on each elite is a marked hit (+50%).", "Everyone draws 1 extra card on the first turn of an op."]},
	{"id": "lab", "name": "ALIEN LAB", "act": 2, "ranks": ["Builds Vharr tech: 15 kills of an alien.", "Tech needs only 10 kills.", "Every tech you build comes out Epic."]},
	{"id": "hangar", "name": "HANGAR", "act": 1, "ranks": ["The Slug rolls out with the squad every op.", "It stays in the fight 1 round longer.", "The Slug can also be called back once per op."]},
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
	"legs": {"name": "HYDRAULIC LEGS", "cls": "", "up": "+2m movement every turn.", "stats": {"move": 40}},
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
	"clear": {"name": "QUIET SECTOR", "text": "No extra conditions.", "w": 3},
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
	{"id": "doubledown", "name": "Double Down", "text": "ONE USE: the squad's next level-up takes two of the three options."},
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
	{"id": "move", "name": "Fleet Footed", "text": "+1.2m movement every turn."},
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
	# G8 late squad gear: the Quartermaster only stocks these from "from" (Run.mission) on.
	# "stats" go to every soldier through Run.gear_bonus, like an item they all wear.
	{"id": "warpaint", "icon": "ic_flame", "name": "War Paint", "from": 1, "text": "Everyone starts each mission with 25 adrenaline.", "price": 120},
	{"id": "ammodrone", "icon": "ic_up", "name": "Ammo Drone", "from": 1, "text": "+1 card in hand each turn for everyone.", "price": 150},
	{"id": "nanites", "icon": "ic_heart", "name": "Nanite Swarm", "from": 2, "stats": {"regen": 2}, "text": "Everyone heals 2 HP at the start of every turn.", "price": 160},
	{"id": "overclock", "icon": "ic_bolt", "name": "Overclock Core", "from": 2, "text": "+1 energy for everyone on odd rounds.", "price": 200},
	# G8 boss trophies: never sold. A boss drops one you don't have yet, already Legendary.
	{"id": "boarcore", "icon": "ic_flame", "name": "Boar Reactor", "boss": true, "stats": {"blast": 0.2}, "text": "Every blast the squad sets off is 20% bigger.", "price": 0},
	{"id": "boarhide", "icon": "ic_skull", "name": "Boar Hide", "boss": true, "stats": {"armor_turn": 2}, "text": "Everyone gets 2 armor at the start of every turn.", "price": 0},
	{"id": "ironheart", "icon": "ic_heart", "name": "Iron Heart", "boss": true, "stats": {"hp": 6}, "text": "+6 max HP for everyone.", "price": 0},
	{"id": "hivecore", "icon": "ic_star", "name": "Hive Core", "boss": true, "stats": {"kill_draw": 1, "kill_adr": 10}, "text": "ON KILL: draw a card (once a turn) and +10 adrenaline. Everyone.", "price": 0},
]

const XP_LEVELS := [0, 14, 34, 60, 92, 130, 175, 230]

const ETYPES := {
	"grunt": {"name": "Jackal Rifleman", "hp": 12, "dmg": [3, 5], "range": 460, "speed": 120, "prefer": 240, "nade": 0.35, "score": 100, "w": 16, "h": 34, "note": "Advances, vaults low walls, and lobs a grenade when it has no shot."},
	"shield": {"name": "Riot Jackal", "hp": 16, "dmg": [3, 4], "range": 340, "speed": 95, "prefer": 140, "shield": true, "score": 150, "w": 18, "h": 34, "note": "Shield soaks 75% of bullets from the front. Ricochet behind it, or blow it up."},
	"nade": {"name": "Jackal Bomber", "hp": 10, "arc": true, "dmg": 9, "radius": 32, "range": 480, "speed": 100, "prefer": 380, "score": 150, "w": 16, "h": 34, "note": "Lobs grenades over cover. Aim tightens as alert rises."},
	"brute": {"name": "Jackal Brute", "hp": 20, "acc": 85, "melee": true, "smash": true, "dmg": [9, 12], "speed": 190, "score": 200, "w": 22, "h": 44, "note": "Charges 9.5m and smashes through walls. Its machete sends you flying."},
	"jetter": {"name": "Jet Jackal", "hp": 10, "dmg": [3, 5], "range": 480, "speed": 90, "prefer": 240, "jet": 300, "score": 175, "w": 16, "h": 34, "note": "Jets up to the highest roof within 15m and shoots down. Hit it in flight and it crashes."},
	"mg": {"name": "MG Nest", "hp": 24, "dmg": [2, 3], "shots": 4, "range": 520, "static": true, "heavy": true, "score": 250, "w": 28, "h": 24, "note": "Static. Four rounds a turn. Too heavy to launch."},
	"radio": {"name": "Jackal Radioman", "hp": 10, "dmg": [2, 3], "range": 380, "speed": 60, "prefer": 520, "radio": true, "score": 200, "w": 16, "h": 34, "note": "Calls in paratroopers when his timer hits zero. Kill him to stop it."},
	"engineer": {"name": "Jackal Engineer", "hp": 12, "dmg": [2, 3], "range": 360, "speed": 80, "prefer": 320, "builds": true, "score": 150, "w": 16, "h": 34, "note": "Builds concrete walls for the Jackal line."},
	"sapper": {"name": "Jackal Sapper", "hp": 11, "speed": 150, "sapper": true, "score": 175, "w": 16, "h": 34, "note": "Runs in and plants a charge that blows next turn. Shoot the charge to defuse it."},
	# E6: a two-legged mech mid-level. Blow the ground out under one leg and it topples.
	"jwalker": {"name": "Jackal Walker", "sheet": "en_grunt", "hp": 48, "dmg": [3, 4], "shots": 3, "range": 500, "speed": 60, "prefer": 300, "heavy": true, "score": 600, "w": 30, "h": 56, "note": "Mini-boss. A mech with a machine gun. Blow the ground out from under one leg and it topples, crushing whatever it lands on. Leaves a walker you can drive."},
	# E1-E5, E7, E8: more Jackals. Like everyone else they move and attack in one turn, and every
	# attack is in plain sight first: the sniper's laser, the gunship's marked strip.
	"jsniper": {"name": "Jackal Sniper", "hp": 12, "dmg": [11, 13], "range": 1400, "speed": 0, "hold": true, "score": 250, "w": 16, "h": 34, "note": "Sits back with a red laser always on. On his turn he fires down that line, then lays it on the nearest soldier for next time. Step out of the line or put a wall in it."},
	"flamer": {"name": "Flametrooper", "hp": 16, "dmg": 6, "range": 110, "speed": 110, "prefer": 80, "score": 200, "w": 18, "h": 34, "note": "Walks up and hoses a short cone of fire that sets you Burning and burns wood away. Shoot the fuel tank on his back and it blows."},
	"jdog": {"name": "Jackal Hound", "weight": "light", "hp": 7, "dmg": 4, "leap": 220, "speed": 170, "pack": 3, "pin": true, "score": 80, "w": 24, "h": 18, "note": "Comes in packs of three. Leaps gaps from 11m and bites; whoever it bites is PINNED: no movement next turn. Light: knock it flying."},
	"wallshield": {"name": "Shield Wall", "hp": 16, "dmg": [3, 4], "range": 340, "speed": 80, "prefer": 160, "shield": true, "pack": 3, "wall": true, "score": 150, "w": 18, "h": 34, "note": "Three Riot Jackals with locked shields: they advance as one and their shields stop 90% from the front. Flank them, lob over, or blow one out of line and the wall breaks."},
	"gunship": {"name": "Jackal Gunship", "weight": "hover", "hp": 70, "alt": 190, "heavy": true, "dmg": 9, "strafe": 140, "speed": 140, "score": 900, "w": 70, "h": 30, "note": "Mini-boss. Hovers high and rakes the strip marked on the ground, then marks the next one by the nearest soldier. Throw a body or a barrel into its rotor for 18. When it goes down it crushes what's under it."},
	"dicokka": {"name": "Di-Cokka", "hp": 50, "dmg": 12, "radius": 40, "range": 700, "speed": 80, "score": 800, "w": 44, "h": 26, "note": "Mini-boss. A small tank that rolls back and forth and lobs shells. Front armor stops 70%; hits from above or behind do +50%. Knock it into the air and it lands FLIPPED: stuck for 2 turns and takes double."},
	"mortarcrew": {"name": "Mortar Crew", "hp": 18, "arc": true, "heavyArc": true, "dmg": 12, "radius": 46, "range": 900, "speed": 0, "score": 250, "w": 18, "h": 34, "note": "Shells your cover from long range. Sits still. Something is hanging over it."},
	# Vharr aliens. Like the Jackals they move and attack in the same enemy phase, and
	# "weight" sets how physics moves them: light flies twice as far, hover holds altitude on a pod.
	# H7: a Jackal carrying a stolen Squid ray, the pact in action on level 1
	"gatetrooper": {"name": "Gate Trooper", "hp": 14, "dmg": 5, "range": 520, "speed": 100, "prefer": 300, "score": 175, "w": 16, "h": 34, "note": "A Jackal with a stolen Vharr ray. It goes through one thin wall and hits everything on the line, Jackals included."},
	"skitter": {"name": "Skitter", "faction": "vharr", "weight": "light", "hp": 6, "dmg": 4, "leap": 240, "speed": 140, "climb": true, "pack": 3, "score": 60, "w": 28, "h": 18, "note": "Comes in packs. Scrambles up walls and pounces from 12m. Light: flies twice as far when knocked."},
	"squid": {"name": "Squid Trooper", "faction": "vharr", "weight": "hover", "hp": 8, "pod": 8, "dmg": 4, "range": 520, "speed": 110, "prefer": 300, "alt": 110, "score": 150, "w": 36, "h": 46, "note": "Hovers on a saucer pod. Its ray goes through one thin wall and hits everything on the line. Break the pod and it drops."},
	"blinker": {"name": "Blinker", "faction": "vharr", "hp": 10, "dmg": 7, "knock": 4.5, "speed": 60, "score": 175, "w": 22, "h": 60, "note": "Teleports behind the nearest soldier within 18m and claws them."},
	"burrower": {"name": "Burrower", "faction": "vharr", "weight": "buried", "hp": 16, "dmg": 9, "tunnel": 300, "score": 175, "w": 30, "h": 56, "note": "Tunnels up to 15m under the ground, digging a trench, then bursts out under you. Bullets can't reach it while buried; blasts on the ground above can."},
	"grappler": {"name": "Grappler", "faction": "vharr", "hp": 22, "dmg": 6, "range": 360, "yank": 200, "speed": 40, "heavy": true, "score": 200, "w": 50, "h": 44, "note": "Heavy. Shoots its tongue at anyone in a clear line within 18m and yanks them up to 10m toward it, over ledges and into mines. Cover breaks the line."},
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
	"droppod": {"name": "Drop Pod", "faction": "vharr", "hp": 18, "static": true, "heavy": true, "score": 50, "w": 24, "h": 26, "note": "Crashed down full of Vharr. It opens on the next enemy phase and they come out swinging. Break it first and they die inside."},
	# E6: a small Vharr gate that sends one alien through every enemy phase
	"vgate": {"name": "Vharr Gate", "faction": "vharr", "hp": 40, "static": true, "heavy": true, "cap": 4, "score": 400, "w": 44, "h": 64, "note": "A small Vharr gate. Every enemy phase one alien comes through, up to four at a time. Blow it up, or drop something heavy on it: crushing does triple damage."},
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
	# M1 Frozen Lake: a crust of lake ice over open water. Heavies and blasts break it
	"lake": {"w": 900, "sandbags": [140], "pits": [],
		"structs": [{"t": "crust", "x0": 240, "x1": 620}],
		"spawns": [["grunt", 300], ["brute", 380], ["shield", 450], ["nade", 520], ["grunt", 580], ["barrel", 700], ["grunt", 750], ["radio", 820]]},
	"floes": {"w": 860, "sandbags": [], "pits": [],
		"structs": [{"t": "crust", "x0": 160, "x1": 340}, {"t": "ledge", "x": 380, "w": 80, "dy": 70, "post": 440}, {"t": "crust", "x0": 480, "x1": 690}],
		"spawns": [["pow", 100], ["grunt", 250], ["brute", 300], ["nade", 410, {"hold": 1, "up": 80}], ["shield", 560], ["grunt", 620], ["mg", 760], ["radio", 800]]},
	# M2 Armored Train: steel cars with open gaps between them and couplers to walk across.
	# The tunnel sweeps every roof on a count you can see
	"traincars": {"w": 1000, "sandbags": [], "pits": [], "gaps": [[290, 330], [640, 680]],
		"structs": [{"t": "car", "x": 10, "w": 280, "h": 64}, {"t": "coupler", "x0": 290, "x1": 330}, {"t": "car", "x": 330, "w": 310, "h": 64},
			{"t": "coupler", "x0": 640, "x1": 680}, {"t": "car", "x": 680, "w": 300, "h": 64}],
		"spawns": [["grunt", 150], ["grunt", 220, {"hold": 1, "up": 70}], ["shield", 420], ["nade", 500, {"hold": 1, "up": 70}], ["brute", 560], ["grunt", 760], ["grunt", 840, {"hold": 1, "up": 70}], ["radio", 920]]},
	"flatcars": {"w": 960, "sandbags": [], "pits": [], "gaps": [[300, 340], [620, 660]],
		"structs": [{"t": "car", "x": 20, "w": 280, "h": 14}, {"t": "coupler", "x0": 300, "x1": 340}, {"t": "car", "x": 340, "w": 280, "h": 64},
			{"t": "coupler", "x0": 620, "x1": 660}, {"t": "car", "x": 660, "w": 290, "h": 14}],
		"spawns": [["pow", 90], ["fuel", 180], ["grunt", 240], ["grunt", 420, {"hold": 1, "up": 70}], ["mg", 480], ["nade", 560, {"hold": 1, "up": 70}], ["m2", 740], ["grunt", 770, {"hold": 1}], ["radio", 900]]},
	"guncar": {"w": 900, "sandbags": [], "pits": [], "gaps": [[400, 440]],
		"structs": [{"t": "car", "x": 20, "w": 380, "h": 64}, {"t": "coupler", "x0": 400, "x1": 440}, {"t": "car", "x": 440, "w": 440, "h": 64}],
		"spawns": [["grunt", 120], ["barrel", 200], ["mortarcrew", 300, {"hold": 1, "up": 70}], ["shield", 520], ["grunt", 600, {"hold": 1, "up": 70}], ["brute", 700], ["nade", 780, {"hold": 1, "up": 70}], ["radio", 840]]},
	# M3 Ruined City: gutted high-rises and a crane, the most vertical fights in the war
	"ruins": {"w": 880, "sandbags": [120], "pits": [],
		"structs": [{"t": "fort", "x": 220, "w": 150, "floors": 4, "fh": 54}, {"t": "crane", "x": 790, "h": 210, "jib": 520, "hook": 580, "rope": 60, "cw": 48, "ch": 24}],
		"spawns": [["grunt", 180], ["grunt", 330, {"hold": 1, "up": 10}], ["nade", 300, {"hold": 1, "up": 74}], ["pow", 320, {"up": 128}],
			["grunt", 340, {"hold": 1, "up": 182}], ["grunt", 300, {"hold": 1, "up": 236}], ["brute", 480], ["shield", 600], ["radio", 820]]},
	"highrise": {"w": 920, "sandbags": [], "pits": [],
		"structs": [{"t": "fort", "x": 140, "w": 130, "floors": 5, "fh": 50}, {"t": "fort", "x": 540, "w": 160, "floors": 3, "fh": 56}],
		"spawns": [["grunt", 100], ["grunt", 220, {"hold": 1, "up": 66}], ["nade", 200, {"hold": 1, "up": 166}], ["grunt", 230, {"hold": 1, "up": 256}],
			["shield", 420], ["mg", 600], ["grunt", 620, {"hold": 1, "up": 78}], ["nade", 640, {"hold": 1, "up": 190}], ["brute", 780], ["radio", 860]]},
	"plaza": {"w": 840, "sandbags": [130], "pits": [],
		"structs": [{"t": "tower", "x": 220, "h": 110}, {"t": "over", "px": 380, "x0": 380, "x1": 520, "h": 80}, {"t": "fort", "x": 620, "w": 140, "floors": 2, "fh": 60}],
		"spawns": [["grunt", 220, {"hold": 1}], ["shield", 330], ["grunt", 450], ["nade", 480, {"hold": 1}], ["fuel", 560], ["grunt", 680, {"hold": 1, "up": 80}], ["brute", 700], ["radio", 790]]},
	# M4 Deep Mine: a rock ceiling, slabs propped on single beams, and carts on the rails
	"shaft": {"w": 880, "sandbags": [], "pits": [],
		"structs": [{"t": "prop", "x": 200, "w": 150, "post": 268}, {"t": "prop", "x": 560, "w": 140, "post": 622}],
		"spawns": [["cart", 120], ["grunt", 240], ["grunt", 300], ["nade", 420], ["brute", 600], ["grunt", 650], ["cart", 520], ["radio", 820]]},
	"tunnels": {"w": 840, "sandbags": [170], "pits": [],
		"ground": [{"x0": 420, "x1": 560, "dh": -24, "ramp": 30}],
		"structs": [{"t": "prop", "x": 250, "w": 130, "post": 312}, {"t": "bunker", "x": 640, "w": 84, "h": 48}],
		"spawns": [["cart", 90], ["grunt", 280], ["shield", 340], ["nade", 480], ["fuel", 520], ["mg", 682], ["grunt", 682, {"hold": 1, "inside": 1}], ["radio", 790]]},
	"drift": {"w": 860, "sandbags": [], "pits": [],
		"structs": [{"t": "prop", "x": 160, "w": 170, "post": 240}, {"t": "ledge", "x": 420, "w": 100, "dy": 80, "post": 500}, {"t": "prop", "x": 600, "w": 150, "post": 676}],
		"spawns": [["pow", 60], ["cart", 110], ["grunt", 220], ["sapper", 300], ["nade", 450, {"hold": 1, "up": 90}], ["grunt", 640], ["brute", 700], ["radio", 800]]},
	# M5 Volcano: low basins where the lava climbs first
	"caldera": {"w": 900, "sandbags": [130], "pits": [],
		"ground": [{"x0": 240, "x1": 420, "dh": -60, "ramp": 60}, {"x0": 560, "x1": 700, "dh": 40, "ramp": 50}],
		"structs": [{"t": "tower", "x": 630, "h": 70}],
		"spawns": [["grunt", 220], ["fuel", 330], ["grunt", 380], ["nade", 500], ["grunt", 630, {"hold": 1}], ["brute", 740], ["radio", 820]]},
	"flows": {"w": 860, "sandbags": [], "pits": [],
		"ground": [{"x0": 180, "x1": 300, "dh": -50, "ramp": 50}, {"x0": 520, "x1": 660, "dh": -56, "ramp": 50}],
		"structs": [{"t": "bridge", "x0": 360, "x1": 470, "posts": [415]}, {"t": "ledge", "x": 700, "w": 90, "dy": 90, "post": 780}],
		"spawns": [["pow", 90], ["grunt", 240], ["shield", 420], ["nade", 590], ["grunt", 730, {"hold": 1, "up": 100}], ["brute", 640], ["radio", 820]]},
	# M6 Vharr Hive: organic tunnels with Hive Pods and standing acid. The walls grow back
	"hivecore": {"w": 880, "sandbags": [], "pits": [],
		"ground": [{"x0": 300, "x1": 520, "dh": 40, "ramp": 60}],
		"structs": [{"t": "over", "px": 200, "x0": 200, "x1": 340, "h": 70}, {"t": "ledge", "x": 600, "w": 110, "dy": 90, "post": 690}],
		"spawns": [["acid", 150], ["grunt", 260], ["hive", 400], ["grunt", 460], ["nade", 560], ["acid", 600], ["grunt", 650, {"hold": 1, "up": 100}], ["hive", 780], ["radio", 820]]},
	"broodpit": {"w": 840, "sandbags": [], "pits": [],
		"ground": [{"x0": 200, "x1": 380, "dh": -40, "ramp": 40}, {"x0": 520, "x1": 700, "dh": 50, "ramp": 0}],
		"structs": [],
		"spawns": [["pow", 100], ["acid", 290], ["hive", 300], ["grunt", 360], ["grunt", 560, {"hold": 1}], ["nade", 620], ["hive", 680], ["grunt", 760], ["radio", 800]]},
	# M7 Carrier Deck: a flat steel deck, open sea off the edges, elevators and a taxi lane
	"flightdeck": {"w": 960, "sandbags": [], "pits": [], "gaps": [[700, 760]],
		"structs": [{"t": "runway", "x0": 120, "x1": 680}, {"t": "lift", "x0": 300, "x1": 380, "drop": 64}, {"t": "tower", "x": 860, "h": 120}],
		"spawns": [["grunt", 200], ["shield", 260], ["grunt", 340], ["nade", 450], ["barrel", 520], ["brute", 600], ["grunt", 860, {"hold": 1}], ["radio", 900]]},
	"hangar": {"w": 900, "sandbags": [], "pits": [], "gaps": [[120, 170]],
		"structs": [{"t": "fort", "x": 260, "w": 200, "floors": 2, "fh": 62}, {"t": "lift", "x0": 560, "x1": 640, "drop": 64}, {"t": "runway", "x0": 500, "x1": 880}],
		"spawns": [["pow", 60], ["grunt", 300], ["mg", 340], ["fuel", 420], ["nade", 380, {"hold": 1, "up": 80}], ["grunt", 600], ["shield", 700], ["grunt", 780], ["radio", 850]]},
	# a safe camp inside the level: a fire, two tents and a supply crate, no Jackals
	# D5: the HQ practice range. Dummies on the flat, one up the tower, one behind a shield
	"range": {"w": 820, "sandbags": [], "pits": [], "structs": [{"t": "tower", "x": 440, "h": 96}],
		"spawns": [["grunt", 200], ["barrel", 290], ["shield", 340], ["grunt", 440, {"hold": 1}], ["grunt", 580], ["mg", 700]]},
	"camp": {"w": 560, "sandbags": [60, 500], "pits": [], "camp": true, "structs": [], "spawns": []},
	# N6: the training drill. A target, a crate, a bunched pair for a grenade, then a short real fight
	"drill": {"w": 1000, "sandbags": [], "pits": [], "structs": [],
		"spawns": [["grunt", 430, {"tut": "target"}], ["crate", 510, {"tut": "crate"}], ["grunt", 600, {"tut": "group"}], ["grunt", 625, {"tut": "group"}]]},
	"drill2": {"w": 900, "sandbags": [260], "pits": [], "structs": [{"t": "tower", "x": 520, "h": 96}],
		"spawns": [["grunt", 380, {"tut": "fight"}], ["grunt", 520, {"tut": "fight", "hold": 1}], ["nade", 700, {"tut": "fight"}]]},
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
#   lake: crust breaks under heavies   tunnel: rounds between roof sweeps   ceiling: underground
#   lava: px the lava climbs a round   aliens: only Vharr   regrow: blocks the Hive regrows a round
#   deck: steel ground   planes: rounds between jets down each taxi lane
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
	# D4: the lake's sway is calm, so it was never rough on long guns; the ice slides brawlers past
	"lake": {"name": "FROZEN LAKE", "theme": "night", "favor": "arc", "rough": "close", "why": "SLICK ICE",
		"rules": {"lake": true, "ice": 3, "wind": 1.3, "sway": 0.9},
		"look": {"tint": Color(0.94, 1.0, 1.12), "grass": Color("dfeef6"), "sky": Color(0.86, 0.94, 1.08), "water": [Color("0c2a40"), Color("6fb6d6")]},
		"segments": ["lake", "floes", "ridge", "trenches", "towers", "fenceline"],
		"text": "Lake ice over black water. A heavy Jackal or a vehicle that walks onto it breaks through, and any blast punches a hole in it. Sheets of ice on the shore too."},
	"train": {"name": "ARMORED TRAIN", "theme": "dusk", "favor": "close", "rough": "long",
		"rules": {"train": true, "tunnel": 3, "amp": 0.0, "wind": 2.0},
		"look": {"tint": Color(1.02, 0.96, 0.9), "grass": Color("8a7a5a"), "sky": Color(1.0, 0.86, 0.74), "water": [Color("2e2824"), Color("6a5a48")]},
		"segments": ["traincars", "flatcars", "guncar"],
		"text": "Fight car to car along a moving train. Every 3 rounds a tunnel sweeps the roofs: the count is over every car. Anyone up there takes 12 and gets thrown back. Fall between the cars and you go under the wheels."},
	"city": {"name": "RUINED CITY", "theme": "dusk", "favor": "long", "rough": "close",
		"rules": {"sight": 1.2, "sway": 0.8, "amp": 0.3, "wind": 1.2},
		"look": {"tint": Color(0.94, 0.92, 0.9), "grass": Color("8a8a7a"), "sky": Color(0.9, 0.86, 0.84)},
		"segments": ["ruins", "highrise", "plaza", "fort", "warehouse", "towers"],
		"text": "Gutted high-rises four and five floors tall, and a crane. The most vertical fights in the war: blow a floor out and everyone on it drops. Aimed shots sway 20% less, but Jackals see 20% farther."},
	"mine": {"name": "DEEP MINE", "theme": "night", "favor": "arc", "rough": "long",
		"rules": {"ceiling": true, "wind": 0.0, "sight": 0.8, "fuel": 1},
		"look": {"tint": Color(1.04, 0.9, 0.76), "grass": Color("6a5a48"), "sky": Color(0.36, 0.3, 0.28)},
		"segments": ["shaft", "tunnels", "drift", "bunker"],
		"text": "Underground under a rock ceiling, with no wind. Slabs of rock hang on single wooden beams: shoot the beam and the slab comes down on whoever is under it. Hit a mine cart and it rolls away from you along the floor, running over the first Jackal in its path."},
	"volcano": {"name": "VOLCANO", "theme": "dusk", "favor": "long", "rough": "close",
		"rules": {"lava": 10.0, "amp": 1.5, "fuel": 2, "wind": 0.6},
		"look": {"tint": Color(1.1, 0.88, 0.8), "grass": Color("4a3a36"), "sky": Color(1.0, 0.7, 0.56), "water": [Color("8a1a08"), Color("ff7a1e")]},
		"segments": ["caldera", "flows", "ridge", "boulder", "trenches"],
		"text": "Lava sits low and rises one marked step every round the squad holds still. Push the screen forward or make camp and it drains. Lava burns up anyone it reaches, Jackal or soldier, and eats wood."},
	"hive": {"name": "VHARR HIVE", "theme": "night", "favor": "arc", "rough": "long",
		"rules": {"aliens": true, "regrow": 60, "sight": 0.8, "amp": 1.2},
		"look": {"tint": Color(0.96, 0.8, 1.06), "grass": Color("8a4aa0"), "sky": Color(0.8, 0.6, 0.9), "water": [Color("1e1430"), Color("7a4a9a")]},
		"segments": ["hivecore", "broodpit", "overhang", "boulder", "ridge"],
		"text": "Inside the Hive: only Vharr, Hive Pods and standing acid. The tunnels grow back: every enemy phase the Hive regrows up to 60 blocks of what you blew away."},
	"carrier": {"name": "CARRIER DECK", "theme": "dusk", "favor": "long", "rough": "arc",
		"rules": {"deck": true, "planes": 3, "amp": 0.0, "wind": 1.8, "sight": 1.1},
		"look": {"tint": Color(0.96, 0.98, 1.04), "grass": Color("8a9096"), "sky": Color(0.9, 0.94, 1.04)},
		"segments": ["flightdeck", "hangar", "m2nest", "catwalks"],
		"text": "A steel deck at sea: blasts barely dent it, and the edges drop into the water. Elevators drop a storey and come back up every 2 rounds. Every 3 rounds a jet taxis down the painted lane: anyone on it takes 14 and is thrown."},
}
# Each level of a run has its own pool. Played and burned biomes never come back.
# Which Vharr fill the rifleman slots in each biome (Z on the alien page).
const ENCOUNTERS := ["swarm", "nest", "droppods", "hunt", "outbreak", "gate"]
const BIOME_ALIENS := {
	"desert": ["skitter", "burrower", "squid", "warden"],
	"fortress": ["blinker", "skitter", "weaver", "prism"],
	"jungle": ["grappler", "skitter", "blinker", "stalker"],
	"delta": ["squid", "bloater", "skitter", "prism"],
	"refinery": ["bloater", "weaver", "squid", "warden"],
	"mountain": ["squid", "burrower", "blinker", "warden"],
	"harbor": ["squid", "grappler", "bloater", "prism"],
	"palace": ["stalker", "weaver", "skitter", "blinker"],
	"lake": ["squid", "skitter", "blinker", "warden"],
	"train": ["skitter", "grappler", "blinker", "stalker"],
	"city": ["squid", "prism", "weaver", "blinker"],
	"mine": ["burrower", "skitter", "grappler", "bloater"],
	"volcano": ["bloater", "squid", "warden", "prism"],
	"hive": ["skitter", "blinker", "weaver", "stalker", "grappler", "bloater"],
	"carrier": ["squid", "prism", "grappler", "skitter"],
}

const LEVELS := [
	{"pool": ["desert", "fortress", "jungle", "delta", "refinery", "mountain", "lake", "city", "mine"], "hp_mul": 1.0, "boss_hp": 100, "plate": 30},  # B1: a softer level 1 Boar
	{"pool": ["desert", "fortress", "jungle", "delta", "refinery", "mountain", "harbor", "palace", "lake", "city", "mine", "train", "volcano", "carrier"], "hp_mul": 1.15, "boss_hp": 160, "plate": 46},
	{"pool": ["desert", "fortress", "jungle", "delta", "refinery", "mountain", "harbor", "palace", "lake", "city", "mine", "train", "volcano", "carrier", "hive"], "hp_mul": 1.3, "boss_hp": 210, "plate": 60},
]
# After the third level: one fixed fight against the Jackal flagship.
const FINALE := {"name": "IRON HARBOR", "theme": "night", "segments": ["start", "docks", "pier"], "finale": true,
	"boss_hp": 260, "plate": 70, "hp_mul": 1.4, "brief": "The last gate opens on the harbor. The Jackal flagship BOAR is loading out. Sink it and the war is over. The squad goes in fully patched up."}

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
# C7: a campaign-only class. Deserters come over as Jackal Defectors on the Vanguard's kit.
const DEFECTOR_CLASS := {"base": "rook", "cls": "Jackal Defector", "deck_add": ["haymaker"],
	"text": "Turncoat: a kill within arm's reach steals the Jackal's gun as a one-shot card, once a turn."}
const DESERTER_CHANCE := 0.5
const ENGINEER_CLASS := {"base": "hex", "cls": "Gate Engineer", "deck_add": ["blink", "domeup"],
	"trait": {"id": "engineer", "name": "Gate Tech", "text": "Starts every op under a Vharr dome. Carries a Blink and a Dome Projector."}}

# B5: Vharr tech the Alien Lab can build, each from one alien type once enough have been killed
const VHARR_TECH := [
	{"id": "blinkpack", "alien": "blinker"},
	{"id": "gravlauncher", "alien": "warden"},
	{"id": "domeprojector", "alien": "weaver"},
	{"id": "prismplate", "alien": "prism"},
]
const TECH_KILLS := [15, 10]        # kills needed: Lab rank 1, rank 2+
const TECH_BIO := 2
const TECH_SALVAGE := 4

# P2: bonus ops that sit on a held sector for a couple of ops. Skipping one costs nothing.
# "pay" is what finishing one brings: an Epic crate, Salvage, a Jackal Defector, or double Alien Lab kills (W6).
const BONUS_OPS := {
	"convoy": {"name": "SUPPLY CONVOY", "job": "escort", "pay": "epic", "text": "A friendly convoy is passing through. Get it across for Epic gear."},
	"scout": {"name": "DOWNED VHARR SCOUT", "job": "hunt", "pay": "epic", "text": "A Vharr scout ship came down. Its pilot carries Epic gear."},
	"yard": {"name": "SALVAGE YARD", "job": "demolish", "pay": "salvage", "text": "A Jackal scrapyard full of parts. Blow its three dumps open for %d Salvage."},
	"column": {"name": "DEFECTOR COLUMN", "job": "escort", "pay": "defector", "text": "Jackals who want out are coming over in a truck. Get it across and one joins the company."},
	"crash": {"name": "VHARR CRASH SITE", "job": "hold", "pay": "crash", "text": "A Vharr ship went down. Hold the wreck: every alien killed here counts double at the Alien Lab."},
}
const BONUS_SALVAGE := 6
# W4: fortifying a held sector, paid in scrip. An income sector pays half its base again per rank;
# a perk sector's perk lasts the whole war from rank 1 and gets stronger at ranks 2 and 3.
const FORTIFY_COST := [150, 300, 500]
const FORTIFY_PERK := {
	"aid": ["Lasts the whole war.", "Camps also offer all 4 detours.", "Also pays +1 Salvage per op."],
	"lookout": ["Lasts the whole war.", "+2 Luck on every op.", "Also pays +1 Salvage per op."],
	"fuel": ["Lasts the whole war.", "The Slug stays for 2 rounds.", "Also pays +1 Salvage per op."],
	"supply": ["Lasts the whole war.", "Elite outposts pay Legendary gear.", "Also pays +1 Salvage per op."],
	"airfield": ["Lasts the whole war.", "+1 Luck on every op.", "Also pays +1 Salvage per op."],
}
# W12: three optional feats per act, shown in the War Book. Each pays CHALLENGE_PAY once.
const CHALLENGES := {
	"clean": {"name": "CLEAN SWEEP", "text": "Win an op this act with nobody going down."},
	"fast": {"name": "BLITZ", "text": "Win an op this act in %d rounds or fewer."},
	"sweep": {"name": "TOTAL CONTROL", "text": "Hold every sector of the act before its stronghold falls."},
	"threat": {"name": "HARD TARGET", "text": "Beat the act's stronghold on threat 2 or higher."},
	"bonus": {"name": "OPPORTUNIST", "text": "Win a bonus op this act."},
}
const ACT_CHALLENGES := [["clean", "fast", "sweep"], ["clean", "bonus", "threat"], ["fast", "sweep", "threat"], ["clean", "bonus", "sweep"], ["clean", "fast", "threat"]]
const BLITZ_ROUNDS := 10
const CHALLENGE_PAY := {"salvage": 3, "bio": 2}   # plus a Legendary item into the stash
const BONUS_CHANCE := 0.35
const BONUS_OPS_LEFT := 2
const TOUR_HARDER := 0.2   # S5: each Second Tour adds this much to enemy and boss HP   # S4: odds a won Act III op ends with a Jackal deserter asking to join

# S2/S3: radio chatter before and after ops. Speakers: "cmd" Command, "varga" the Jackal colonel,
# "prime" the Vharr Overseer Prime, "sq" a soldier from the squad ({name}, {rank}, {mate} filled in).
const RADIO_CAST := {
	"cmd": {"name": "MAJ. HALE", "role": "COMMAND", "col": Color("62d26f")},
	"varga": {"name": "COL. VARGA", "role": "JACKAL ARMY", "col": Color("ff7a3d")},
	"prime": {"name": "OVERSEER PRIME", "role": "VHARR", "col": Color("c47bff")},
	"sarge": {"name": "SGT. KRUGER", "role": "DRILL INSTRUCTOR", "col": Color("ffb23e")},
}
const RADIO_ACT := [
	[["cmd", "Iron Company, this is Hale. The Jackals hold the whole delta. Take it back one sector at a time."],
	 ["varga", "Colonel Varga, Jackal Army. You picked the wrong beach, little company."],
	 ["sq", "{mate}, you hear that? He knows our name already."]],
	[["cmd", "Bad news. The Jackals dug up a gate in the desert, and something came through it."],
	 ["prime", "THE GATE IS OPEN. YOUR KIND WILL MAKE USEFUL HOSTS."],
	 ["varga", "Our new friends are... persuasive. Stay out of the sand."]],
	[["cmd", "Comms picked up Jackal units shooting at Vharr. Their pact is cracking. Use it."],
	 ["varga", "They took my men for hosts. I am done with them. We may need to talk, Iron Company."],
	 ["sq", "Trust a Jackal? {mate}, tell me you're not buying this."]],
	[["cmd", "A Hive Ship is parked over the coast. Nests everywhere. This is the big one."],
	 ["prime", "THE TIDE RISES. THE HIVE REMEMBERS EVERY ONE OF YOU."],
	 ["sq", "Big ship, big target. Right, {mate}?"]],
	[["cmd", "Last push. The gate is in Iron Harbor. Shut it and this war is over."],
	 ["prime", "YOU CANNOT CLOSE WHAT YOU DO NOT UNDERSTAND."],
	 ["sq", "Watch me. Iron Company, let's go home."]],
]
# C4: Major Hale calls the field tablet the first time a new war reaches HQ
const RADIO_LANDFALL := [
	["cmd", "Iron Company, this is Major Hale. Welcome to the delta. The Jackals own every inch of it."],
	["cmd", "This beach is your field HQ. Kit out here, then open the WAR ROOM and pick a sector to hit."],
	["cmd", "Take three sectors and their Boar's Den opens. Break it and the front moves on."],
	["sq", "Nice beach, {mate}. Shame about the Jackals."],
]
# N6: the training drill, one list of lines per step (move, shoot, crate, throw, push, fight)
const TUT_LINES := [
	["Listen up, recruits. This is a drill: nothing here counts.", "Click the ground to walk. Walk anyone to the green flag."],
	["Target Jackal ahead. Click RIFLE SHOT, or press its number key.", "Aim at him with the mouse and click to fire. Right-click cancels. SHIFT steadies your aim."],
	["Supply crate up ahead. Shoot it open.", "Loot you leave lying around is collected when the screen moves on."],
	["Jackals bunched up ahead. Arm the FRAG GRENADE and lob it at their feet.", "Only the start of the throw is shown, so judge the bounces yourself. The mouse wheel sets the fuse."],
	["Each soldier gets 3 ENERGY a turn. NEXT (SPACE) picks who can still act. END TURN (ENTER) ends it.", "Now push. Walk someone into the PUSH ZONE on the right and the screen moves on."],
	["These ones shoot back. After your turn, every enemy moves and fires.", "Use cover, knock them off ledges, finish them. Go."],
]
const TUT_DONE_LINES := ["That's the drill, recruits. You're ready for the gate.", "QUICK RUN is one run of three levels. CAMPAIGN is the long war."]
const TUT_FAIL_LINES := ["Down in the dirt already? Get up. TRAINING is on the title screen whenever you want another go."]
const TRAINING := {"name": "BOOT CAMP", "theme": "dusk", "segments": ["drill", "drill2"], "boss_hp": 1, "plate": 0, "hp_mul": 1.0,
	"brief": "", "rules": {"pads": 0, "wind": 0.0, "amp": 0.3}, "tutorial": true}
const RADIO_JOB := {
	"push": [["cmd", "Push through to the far end and knock out their armor."], ["cmd", "Straight fight. Break their line and keep moving east."]],
	"rescue": [["cmd", "Three of ours are held in there. Bring them home."], ["cmd", "Prisoners spotted. Walk up and cut them loose, they'll do the rest."]],
	"demolish": [["cmd", "Three supply dumps. Blow them and the Jackals starve."], ["cmd", "Bring explosives. Those dumps go up nicely."]],
	"hold": [["cmd", "Take the far end and hold it. They'll come from both sides."], ["cmd", "We need that ground held for five turns. Dig in."]],
	"escort": [["cmd", "A supply truck is coming through. Keep the road clear and keep it alive."], ["cmd", "The truck can't fight. You can. Clear the road ahead of it."]],
	"hunt": [["cmd", "One of their officers is in that sector. Find them, drop them."], ["cmd", "High value target. They carry good kit, so take it off them."]],
}
const RADIO_TAUNT := [
	[["varga", "Every sector you take, I take two back. Eventually."], ["varga", "My rifles are older than you, and they still shoot straight."]],
	[["varga", "The sand eats armies. Ask the last one."], ["prime", "WE HAVE COUNTED YOUR SOLDIERS. THERE ARE NOT ENOUGH."]],
	[["varga", "Shoot the purple ones first. Then we can go back to shooting each other."], ["prime", "THE JACKALS BETRAY. ALL HOSTS BETRAY. IT DOES NOT MATTER."]],
	[["prime", "EVERY NEST IS A MOUTH. EVERY MOUTH IS HUNGRY."], ["prime", "THE SHIP SEES YOU, SMALL ONES."]],
	[["prime", "THE GATE HAS STOOD FOR TEN THOUSAND YEARS."], ["prime", "TURN BACK, AND WE WILL TAKE YOU LAST."]],
]
const RADIO_WON := [["cmd", "Good work. That sector is ours."], ["cmd", "Clean op. Get some rest, Iron Company."], ["cmd", "Command confirms: sector secure. The map is turning green."]]
const RADIO_LOST := [["cmd", "Fall back, fall back. We'll hit them again when you're ready."], ["cmd", "That one got away from us. Regroup and try again."]]
const RADIO_SQ_WON := ["Drinks are on {mate}.", "{mate}, did you see that? Tell me you saw that.", "That's how the {rank} does it.", "Another one for the wall map."]
const RADIO_ACT_DONE := [
	[["varga", "The Boar was my favorite tank. You will pay for that, Iron Company."]],
	[["varga", "The Queen is dead? Good. Maybe now the Vharr will listen to reason."], ["prime", "THE QUEEN WAS ONE OF MANY."]],
	[["varga", "That nest is clear. Fine. My men will not fight you anymore. We fight them."]],
	[["prime", "THE SHIP FALLS. THE GATE DOES NOT."]],
	[["cmd", "The gate is shut. It's over. Iron Company, come home."]],
]
# W13: Varga's last stand, the story op in Act IV
const RADIO_VARGA_STAND := [["varga", "Iron Company. The Vharr turned on my garrison. The fort is coming down around us."], ["varga", "Get my men out and I am yours. I have nowhere else to go."], ["cmd", "Your call, Iron Company. Bring him home or leave him to it."]]
const VARGA_DECK := ["hmg", "hmg", "burst", "rifle", "rifle", "haymaker", "frag", "sprint", "knife"]
const RADIO_VARGA_OP := [["varga", "Iron Company. I'll go in with you this once. Don't make me regret it."], ["sq", "Colonel Varga on our side. Write that down, {mate}."]]

# O1-O6: what an op on the war map asks of the squad. Strongholds are always a push to the boss.
const JOBS := {
	"push": {"name": "PUSH", "goal": "BREAK THROUGH", "text": "Fight to the far end and knock out the sector's armor."},
	"rescue": {"name": "RESCUE", "goal": "FREE 3 PRISONERS", "text": "Three of ours are held across the sector. Walk up to each one to cut them loose."},
	"demolish": {"name": "DEMOLISH", "goal": "DESTROY 3 TARGETS", "text": "Blow up three supply dumps. Blasts do double damage to them."},
	"hold": {"name": "HOLD", "goal": "HOLD THE FAR END", "text": "Reach the far end, then survive %d enemy phases while they come from both sides."},
	"escort": {"name": "ESCORT", "goal": "GET THE TRUCK THROUGH", "text": "A supply truck rolls forward each enemy phase, but stops while Jackals are close ahead. Keep it alive."},
	"hunt": {"name": "HUNT", "goal": "KILL THE TARGET", "text": "A named Jackal officer is somewhere in the sector. Kill them and take what they carry."},
}
# W3: a hunt's named officer who survives the op gets away and comes back on the next op, tougher
# each time, with a new trick. Killing one who came back drops a Legendary named after them.
const NEMESIS_TITLES := ["", "THE SCARRED", "ONE-EYE", "THE UNKILLABLE"]
const NEMESIS_HP := 0.5   # extra HP multiplier per escape, on top of a hunt quarry's double
# W5: personal orders. Each soldier gets one at Corporal and a new one with each rank, picked to fit
# their deck. Finishing one earns a title and a permanent bonus. Nothing happens if you never do it.
const ORDERS := {
	"headhunter": {"text": "Make %d headshot kills.", "goal": 4, "title": "DEADEYE", "stats": {"aim_dmg": 2}, "up": "+2 damage on aimed shots"},
	"demo": {"text": "Kill %d enemies with thrown or lobbed explosives.", "goal": 8, "title": "BOOMER", "stats": {"blast": 0.15}, "up": "+15% blast damage"},
	"brawler": {"text": "Make %d kills with melee cards.", "goal": 5, "title": "BRUISER", "stats": {"hp": 10}, "up": "+10 max HP"},
	"bughunter": {"text": "Kill %d Vharr.", "goal": 10, "title": "BUGSPLITTER", "stats": {"aim_dmg": 1, "kill_adr": 5}, "up": "+1 aimed damage, +5 adrenaline per kill"},
	"wrecker": {"text": "Kill %d enemies with falls, slams, crushes or bonks.", "goal": 5, "title": "WRECKING BALL", "stats": {"hp": 6, "dodge": 4}, "up": "+6 max HP, +4 dodge"},
	"giantkiller": {"text": "Kill %d elites or bosses.", "goal": 3, "title": "GIANT KILLER", "stats": {"aim_dmg": 2}, "up": "+2 damage on aimed shots"},
	"ironside": {"text": "Finish %d ops without going down.", "goal": 4, "title": "IRONSIDE", "stats": {"armor_turn": 2}, "up": "2 armor every turn"},
}
# W7: two soldiers who finish this many ops in the same squad become battle buddies (up to 2 each)
const BOND_OPS := 5
const BOND_MAX := 2
const RADIO_BOND := ["{mate}, you still owe me from the last op.", "Stick close, {mate}. Same as always.", "Me and {mate} have this side covered.", "{mate}, if I go down, you're buying the drinks."]
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
		{"id": "d2", "name": "RICE TERRACES", "biome": "delta", "job": "rescue", "at": [280, 270], "links": ["lz", "d1", "j1", "j2"], "perk": "aid"},
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
		{"id": "s2", "name": "SALT FLATS", "biome": "desert", "job": "hold", "at": [220, 330], "links": ["lz", "s1", "m1"], "perk": "airfield"},
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
		{"id": "f1", "name": "MARKET STREET", "biome": "fortress", "job": "rescue", "at": [220, 390], "links": ["lz", "r1", "f2"], "perk": "supply"},
		{"id": "f2", "name": "OLD CITADEL", "biome": "fortress", "job": "hunt", "at": [370, 330], "links": ["f1", "f3"], "hold": {"bio": 2}},
		{"id": "f3", "name": "GARRISON GATE", "biome": "fortress", "job": "push", "varga": true, "at": [500, 400], "links": ["f2", "boss"], "perk": "aid"},
		{"id": "boss", "name": "THE INFESTED WORKS", "biome": "refinery", "at": [590, 270], "links": ["r3", "f3"], "stronghold": true}]},
	{"id": "hive", "name": "HIVE TIDE", "roman": "IV", "tier": 2, "hp_mul": 1.45, "boss_hp": 240, "plate": 66, "need": 3, "breach": 0.5,
	 "text": "The palace and the night harbor. A Hive Ship parks over the coast and seeds nests everywhere.",
	 "lz": {"name": "CLIFF ROAD", "at": [70, 170]},
	 "sectors": [
		{"id": "p1", "name": "LANTERN GARDENS", "biome": "palace", "job": "hunt", "at": [190, 130], "links": ["lz", "p2", "p3"], "perk": "lookout"},
		{"id": "p2", "name": "SHOGUN'S HALL", "biome": "palace", "job": "rescue", "at": [320, 210], "links": ["p1", "h1"], "hold": {"bio": 2}},
		{"id": "p3", "name": "PAPER BRIDGE", "biome": "palace", "job": "escort", "at": [200, 300], "links": ["lz", "p1", "h2"], "hold": {"scrip": 30}},
		{"id": "h1", "name": "LIGHTHOUSE", "biome": "harbor", "job": "hold", "at": [470, 140], "links": ["p2", "boss"], "perk": "airfield"},
		{"id": "h2", "name": "FISH MARKET", "biome": "harbor", "job": "push", "at": [330, 400], "links": ["p3", "h3"], "hold": {"salvage": 3}},
		{"id": "h3", "name": "DRY DOCK", "biome": "harbor", "job": "demolish", "at": [490, 350], "links": ["h2", "boss"], "perk": "supply"},
		{"id": "v1", "name": "VARGA'S FORT", "biome": "fortress", "job": "rescue", "story": "varga", "varga": true, "at": [96, 410], "links": ["p3"], "hold": {"bio": 2}},
		{"id": "boss", "name": "UNDER THE HIVE SHIP", "biome": "harbor", "at": [600, 240], "links": ["h1", "h3"], "stronghold": true}]},
	{"id": "gate", "name": "SHUT THE GATE", "roman": "V", "tier": 2, "hp_mul": 1.6, "boss_hp": 270, "plate": 74, "need": 2, "breach": 0.3,
	 "text": "Iron Harbor, where the Jackals keep the captured gate. Two big ops, then the flagship and the gate itself.",
	 "lz": {"name": "LANDING CRAFT", "at": [80, 280]},
	 "sectors": [
		{"id": "g1", "name": "SEA WALL", "biome": "harbor", "job": "hold", "at": [260, 180], "links": ["lz", "boss"], "hold": {"scrip": 40}},
		{"id": "g2", "name": "GATE BARRACKS", "biome": "fortress", "job": "rescue", "at": [270, 390], "links": ["lz", "boss"], "hold": {"bio": 2}},
		{"id": "boss", "name": "IRON HARBOR", "biome": "harbor", "at": [520, 280], "links": ["g1", "g2"], "stronghold": true, "finale": true}]},
]

# W14: on a Second Tour, Acts II to IV can run on a different front: other biomes, other sectors,
# the same beats (the Queen's pit, the Vharr-refit Boar, Varga's garrison and his last stand).
const ALT_ACTS := {
	1: {"id": "whitepass", "name": "WHITE PASS", "roman": "II", "tier": 1, "hp_mul": 1.15, "boss_hp": 160, "plate": 46, "need": 3, "breach": 0.4,
	 "text": "The frozen lakes and the old mine under the pass. The Jackals dug too deep and something dug back.",
	 "lz": {"name": "ICE STRIP", "at": [80, 260]},
	 "radio": [["cmd", "Bad news. The Jackals broke into something under the pass, and it came up through the mine."],
		["prime", "THE GATE IS OPEN. YOUR KIND WILL MAKE USEFUL HOSTS."],
		["varga", "Our new friends are... persuasive. Stay off the ice."]],
	 "taunt": [["varga", "The ice eats armies. Ask the last one."], ["prime", "WE HAVE COUNTED YOUR SOLDIERS. THERE ARE NOT ENOUGH."]],
	 "sectors": [
		{"id": "k1", "name": "BLACK ICE", "biome": "lake", "job": "push", "at": [200, 160], "links": ["lz", "k2", "k3"], "hold": {"scrip": 25}},
		{"id": "k2", "name": "FISHING HUTS", "biome": "lake", "job": "rescue", "at": [210, 360], "links": ["lz", "k1", "n1"], "perk": "aid"},
		{"id": "k3", "name": "FROZEN FERRY", "biome": "lake", "job": "hunt", "at": [340, 130], "links": ["k1", "n2"], "hold": {"bio": 1}},
		{"id": "n1", "name": "MINE HEAD", "biome": "mine", "job": "demolish", "at": [360, 360], "links": ["k2", "n2", "n3"], "hold": {"salvage": 3}},
		{"id": "n2", "name": "LOWER DRIFT", "biome": "mine", "job": "hold", "at": [470, 200], "links": ["k3", "n1", "boss"], "perk": "lookout"},
		{"id": "n3", "name": "ORE CARTS", "biome": "mine", "job": "rescue", "at": [500, 390], "links": ["n1", "boss"], "perk": "fuel"},
		{"id": "boss", "name": "THE QUEEN'S SCREE", "biome": "mountain", "at": [600, 290], "links": ["n2", "n3"], "stronghold": true, "queen": true}]},
	2: {"id": "ironroad", "name": "IRON ROAD", "roman": "III", "tier": 2, "hp_mul": 1.3, "boss_hp": 210, "plate": 60, "need": 3, "breach": 0.8,
	 "text": "The rail line and the ruined city. The pact is cracking and Jackals and Vharr are shooting each other.",
	 "lz": {"name": "SIDING", "at": [70, 220]},
	 "sectors": [
		{"id": "t1", "name": "COAL TRAIN", "biome": "train", "job": "push", "at": [190, 130], "links": ["lz", "t2", "c1"], "hold": {"salvage": 3}},
		{"id": "t2", "name": "GUN CARRIAGE", "biome": "train", "job": "demolish", "at": [320, 110], "links": ["t1", "t3"], "perk": "fuel"},
		{"id": "t3", "name": "PRISON CARS", "biome": "train", "job": "rescue", "at": [460, 150], "links": ["t2", "boss"], "hold": {"scrip": 30}},
		{"id": "c1", "name": "TRAM DEPOT", "biome": "city", "job": "escort", "at": [200, 350], "links": ["lz", "t1", "c2"], "perk": "supply"},
		{"id": "c2", "name": "HIGHRISE ROW", "biome": "city", "job": "hunt", "at": [350, 300], "links": ["c1", "c3"], "hold": {"bio": 2}},
		{"id": "c3", "name": "CITY GARRISON", "biome": "city", "job": "push", "varga": true, "at": [490, 390], "links": ["c2", "boss"], "perk": "aid"},
		{"id": "boss", "name": "THE INFESTED YARDS", "biome": "city", "at": [590, 260], "links": ["t3", "c3"], "stronghold": true}]},
	3: {"id": "firecoast", "name": "FIRE COAST", "roman": "IV", "tier": 2, "hp_mul": 1.45, "boss_hp": 240, "plate": 66, "need": 3, "breach": 0.5,
	 "text": "The burning coast and the captured carrier. A Hive Ship parks over the harbor and seeds nests everywhere.",
	 "lz": {"name": "LAVA BEACH", "at": [70, 260]},
	 "sectors": [
		{"id": "x1", "name": "ASH FIELDS", "biome": "volcano", "job": "push", "at": [190, 150], "links": ["lz", "x2", "x3"], "perk": "lookout"},
		{"id": "x2", "name": "OBSIDIAN STEPS", "biome": "volcano", "job": "rescue", "at": [320, 120], "links": ["x1", "y1"], "hold": {"bio": 2}},
		{"id": "x3", "name": "MAGMA BRIDGE", "biome": "volcano", "job": "demolish", "at": [210, 340], "links": ["lz", "x1", "y2"], "hold": {"scrip": 30}},
		{"id": "y1", "name": "FLIGHT DECK", "biome": "carrier", "job": "hunt", "at": [470, 140], "links": ["x2", "boss"], "perk": "airfield"},
		{"id": "y2", "name": "HANGAR BAY", "biome": "carrier", "job": "hold", "at": [340, 400], "links": ["x3", "y3"], "hold": {"salvage": 3}},
		{"id": "y3", "name": "ISLAND TOWER", "biome": "carrier", "job": "demolish", "at": [490, 350], "links": ["y2", "boss"], "perk": "supply"},
		{"id": "v1", "name": "VARGA'S FORT", "biome": "fortress", "job": "rescue", "story": "varga", "varga": true, "at": [96, 410], "links": ["x3"], "hold": {"bio": 2}},
		{"id": "boss", "name": "UNDER THE HIVE SHIP", "biome": "harbor", "at": [600, 250], "links": ["y1", "y3"], "stronghold": true}]},
}
const NO_TRUCK := ["lake", "train", "carrier"]   # W14: biomes a patrol never rolls an escort in (ice, tunnels, jets)

# The company (C1-C6). The campaign keeps a roster of up to COMPANY_MAX soldiers and deploys a squad
# of up to SQUAD_MAX, one per class. Ranks come from ops survived (C3); each promotion is a pick
# from that rank's three options, and a Captain in the squad gives everyone CAPTAIN_DODGE.
const COMPANY_MAX := 10
const PINCER_COMPANY := 8  # W9: Iron Harbor goes in as a two-squad pincer once the company has this many
const SQUAD_MAX := 4
const RESERVE_MAX := 6    # quick run: rescued soldiers the barracks holds while the squad is full
const FLARE_CHANCE := 0.3 # odds a new screen holds a reinforcement flare while someone is down
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
	"move": {"name": "FLEET", "text": "+2m movement every turn."},
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
	"veteran": {"name": "CAMPAIGN STAR", "text": "Survived 10 ops.", "up": "+1m movement"},
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
	if inst is Dictionary and inst.get("nowind", false):
		base["wind"] = 0.0
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

const PX_PER_M := 20.0  # O2: distances read in meters; a soldier (34px) stands about 1.7m

static func meters(px: float) -> String:
	## "7.5m" under 10 meters, whole meters from there ("12m").
	var v := px / PX_PER_M
	if v >= 10.0:
		return "%dm" % roundi(v)
	return ("%.1f" % v).trim_suffix(".0") + "m"

func dmg_text(d) -> String:
	## "6-8", or just "3" when the range is one number (Heavy MG read "DMG 3-3").
	if not d is Array:
		return "%d" % d
	return ("%d" % d[0]) if int(d[0]) == int(d[1]) else "%d-%d" % [d[0], d[1]]

func stat_line(c: Dictionary) -> String:
	if c.type == "AIM":
		# Q2: BOUNCE spelled out, and left off when the shot doesn't bounce at all
		var bn: String = (" BOUNCE %d" % c.bounce) if int(c.get("bounce", 0)) > 0 else ""
		return "DMG %s%s%s%s" % [dmg_text(c.dmg), (" x%d" % c.shots) if c.has("shots") else "", (" x%d" % c.pellets) if c.has("pellets") else "", bn]
	if c.has("radius"):
		return "DMG %d%s BLAST %s" % [c.dmg, (" x%d" % c.count) if c.has("count") else "", meters(c.radius)]
	if c.has("dmg"):
		return "DMG " + dmg_text(c.dmg)
	if c.has("heal"):
		return "HEAL %d  RNG %s" % [c.heal, meters(c.range)]
	if c.get("grapple", false):
		return "RNG %s" % meters(c.range)
	if c.get("smoke", false) or c.get("gas", false):
		return "RADIUS %s  %d RNDS" % [meters(c.srad), c.sturns]
	if c.get("beacon", false):
		return "%d BOMBS  DMG 15" % c.get("bombs", 3)
	if c.get("overwatch", false):
		return "%d SHOT%s" % [c.ow, "S" if c.ow > 1 else ""]
	if c.has("armor"):
		return "ARMOR +%d" % c.armor
	if c.has("move"):
		return "MOVE +%s" % meters(c.move)
	if c.has("energy"):
		return "ENERGY +1"
	if c.has("adrenal"):
		return "ADRENALINE +%d  HP -%d" % [c.adrenal, c.selfdmg]
	if c.has("rally"):
		return "MOVE +%s  RNG %s" % [meters(c.rally), meters(c.range)]
	if c.get("rush", false):
		return "LAUNCH  SLAM 14"
	if c.get("jump", false):
		return "LAUNCH x%.1f  SOFT" % c.jpow
	if c.get("surge", false):
		return "SQUAD BOOST"
	return ""

func is_attack(c: Dictionary) -> bool:
	return c.type == "AIM" or c.type == "MELEE" or (c.type == "ARC" and not c.get("smoke", false) and not c.get("beacon", false)) or (c.type == "LINE" and not c.get("grapple", false) and not c.get("zipline", false) and not c.get("rush", false) and not c.get("jump", false) and c.get("dog", "bite") == "bite")

func relic_text(id: String, t: int) -> String:
	## Squad gear text at a given rarity tier.
	match id:
		"boots": return "Squad takes no fall or slam damage." if t >= 3 else "Squad takes half fall and slam damage."
		"jammer": return ("Radiomen need 2 more rounds to call backup." if t >= 3 else "Radiomen need 1 more round to call backup.")
		"rations": return "Every wave clear heals the squad %d HP." % (4 + t * 2)
		"laser": return "Aim lasers reach %s further. Sway -30%%." % ("two steps" if t >= TIER_MAX else "one step")
		"charm": return "The first %s to die each mission live%s at 1 HP." % (["soldier", "s"] if t < 3 else ["two soldiers", ""])
		"bandolier": return "+1 energy for everyone on round 1%s." % (" and 2" if t >= 3 else "")
		"dogtags": return "Kills give %d%% more XP. +1 Luck." % int(30 + 10 * t)
		"stimpack": return "Adrenaline builds %d%% faster." % int(30 + 10 * t)
		"warpaint": return "Everyone starts each mission with %d adrenaline." % (50 if t >= 3 else 25)
		"ammodrone": return "+1 card in hand each turn for everyone%s." % (", +2 on round 1" if t >= 3 else "")
		"nanites": return "Everyone heals %d HP at the start of every turn." % (3 if t >= 3 else 2)
		"overclock": return "+1 energy for everyone %s." % ("every round" if t >= 3 else "on odd rounds")
	return gear(id).get("text", "")

func offer_keys(squad: Array = []) -> Array:
	## Cards that can show up in level-ups, supply drops and the shop. A class card (one only a
	## specialist's pool has, like Whistle or Vulcan) only shows up when that class is in the squad.
	var out: Array = []
	for k in CARDS:
		if not CARDS[k].get("od", false) and CARDS[k].get("pool", true):
			var cls := card_classes(k)
			if cls.is_empty() or cls.any(func(x): return squad.has(x)):
				out.append(k)
	return out

func card_classes(key: String) -> Array:
	## The specialist classes a card belongs to, or [] when any soldier can use it
	## (it is in a base class's pool, or in nobody's).
	var out: Array = []
	for d in SQUAD_DEFS:
		if d.pool.has(key) or d.deck.has(key):
			if BASE_CLASSES.has(d.key):
				return []
			out.append(d.key)
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
		elif k in METER_STATS:
			out.append(fmt % meters(absf(v)))
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
	if A.get("m", false):
		return A.fmt % meters(v)
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

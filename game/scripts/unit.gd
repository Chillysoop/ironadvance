class_name Unit
extends RefCounted
## One body on the battlefield: a squadmate, a Jackal, a POW or a prop
## (barrel, fuel tank, planted charge). Plain data; Battle runs the rules.

var id := 0
var team := ""        # squad, enemy, neutral
var kind := ""        # soldier, enemy, pow, barrel, fuel, charge, mine
var type := ""        # enemy type key
var sheet := ""       # sprite sheet key
var x := 0.0
var y := 0.0
var w := 16.0
var h := 34.0
var vx := 0.0
var vy := 0.0
var air := false
var face := 1
var dead := false
var downed := false   # went down but spent a dog tag, so they come back next mission
var gone := false
var sunk := false
var flash := 0
var anim := 0
var walk = null       # Array of [x, y, inside]
var walk_i := 0
var zip = null        # grapple zip state
var vault = null
var alpha := 1.0
var dead_t := 0
var armor := 0
var muzzle := 0
var bumped = null     # Dictionary used as a set of unit ids
var last_hit_by = null
var rushing := false
var jumping := false
var leaping := false
var para := false
var hp := 1
var max_hp := 1
var dodge := 0
var heavy := false
var shield := false
var hold := false
var active := false
var plate := 0
var cracked := false
var aim_a := 0.18
var gun_angle := 0.0  # current arm angle for the sprite
var gun_target := 0.0
var pose := ""        # one-shot pose: throw, hurt, cheer, recoil
var pose_t := 0
var leak = null
var leak_by = null
var primed := false
var freed := false
var detour := false    # spawned by the camp detour (its guards, prisoners and wrecks)
var stripped := false  # a salvage wreck someone already stripped
var pow_name := ""
var planted := false
var built := 0
var dragged := false
var tread := 0.0
var elite := ""       # elite Jackal modifier (Data.ELITES key)
var weight := ""      # Vharr weight class: "light" (knocked twice as far) or "hover" (holds altitude on a pod)
var pod := 0          # hover: pod HP; when it breaks the alien drops
var crash := false    # pod just broke: takes crash damage when it lands
var loot = null       # payload for a loot pickup or a crate
var kill_drawn := false
var gb: Dictionary = {}  # squad: gear bonuses for this mission
var st: Dictionary = {}  # statuses (Data.STATUS key -> turns left)
var st_by: Dictionary = {}  # who applied each status, for kill credit
var hit_sides: Dictionary = {}  # this round: squad unit id -> side they hit from (CROSSFIRE)
var rico := false     # Ricochet Body: already bounced off a wall this flight
var soak := 0         # a Jackal's body: bullets it can still stop before it's shredded
var rot := 0.0        # a body's tumble while it flies
var fuel := 0         # Jet Boots: fuel left, refilled each turn that starts on the ground
var fuel_max := 0
var jetting := false
# squad only
var s: Dictionary = {}  # persistent Run soldier record
var def: Dictionary = {}
var adr := 0
var energy := 3
var move_left := 0.0
var draw: Array = []
var hand: Array = []
var disc: Array = []
var overwatch := 0
var moved := false
var attacked := false
var aim_discount := false
var played := 0       # cards played this turn (momentum)
var last_cost := 0    # energy paid for the last card (SKY DIVER refund)
var seq: Array = []   # [key, type] of each card played this turn (signature chains)
var fl: Dictionary = {}  # per-turn flags for chains and perks
var payback := 0      # Juggernaut capstone: armor carried into the next hit
var immovable := false
var second_wind := false
var xp_gain := 0

func center() -> Vector2:
	return Vector2(x, y - h / 2.0)

func is_prop() -> bool:
	return kind == "barrel" or kind == "fuel" or kind == "charge" or kind == "crate" or kind == "strongbox" or kind == "mine"

func is_pickup() -> bool:
	## Loot on the ground and buried caches: bullets and blasts pass through them.
	return kind == "loot" or kind == "cache" or kind == "relay" or kind == "wreck" or kind == "pad"

func is_body() -> bool:
	## A dead Jackal left lying on the field: cover, and something to throw at its friends.
	return dead and kind == "enemy" and type != "boss" and not gone and not sunk

func has_st(k: String) -> bool:
	return st.get(k, 0) > 0

func g(k: String, d = 0):
	return gb.get(k, d)

func perk(id_: String) -> bool:
	return s.has("perks") and s.perks.has(id_)

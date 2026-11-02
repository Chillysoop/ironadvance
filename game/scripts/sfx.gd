extends Node
## Tiny sound pool. Sfx.play("boom") from anywhere.

var streams := {}
var players: Array[AudioStreamPlayer] = []
var muted := false
var next := 0
var last_played := {}
var rng := RandomNumberGenerator.new()  # its own dice, so which sounds exist never shifts the game's RNG
# Newer cues fall back to the closest older sound until their own file is generated.
const FALLBACK := {
	"flame": "rocket", "zap": "ping", "laser": "snipe", "warp": "power", "crate": "bonk",
	"collapse": "bigboom", "beep": "tick", "grapple": "toss", "ricochet": "ping", "alien_die": "scream",
	"death": "", "bubble": "splash", "sizzle": "", "turn": "", "draw": "", "chitter": "", "engine": "",
	"heal": "", "roar": "bigboom",
}

func _ready() -> void:
	## Every sound in assets/sfx. "boom_2", "boom_3" are variants of "boom": play() picks one at
	## random so repeated hits don't sound like a loop. An exported build lists the files by their
	## .import/.remap stubs, so the names come from those too.
	var found := {}
	var dir := DirAccess.open("res://assets/sfx")
	if dir != null:
		for f in dir.get_files():
			f = f.trim_suffix(".import").trim_suffix(".remap")
			if f.get_extension() in ["wav", "ogg", "mp3"]:
				found[f.get_basename()] = "res://assets/sfx/" + f
	var names := found.keys()
	names.sort()
	for base in names:
		var stream = load(found[base])
		if stream == null:
			continue
		var n: String = base
		var cut := n.rfind("_")
		if cut > 0 and n.substr(cut + 1).is_valid_int():
			n = n.substr(0, cut)
		if not streams.has(n):
			streams[n] = []
		streams[n].append(stream)
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"  # R5: the settings menu sets this bus's volume
		add_child(p)
		players.append(p)

func has(n: String) -> bool:
	return streams.has(n)

func play(n: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(n):
		n = FALLBACK.get(n, "")
	if muted or not streams.has(n):
		return
	var now := Time.get_ticks_msec()
	if last_played.get(n, -1000) > now - 30:
		return  # several identical sounds in one frame just stack into noise
	last_played[n] = now
	var p := players[next]
	next = (next + 1) % players.size()
	var pool: Array = streams[n]
	p.stream = pool[rng.randi() % pool.size()]
	p.volume_db = vol_db - 4.0
	p.pitch_scale = pitch * rng.randf_range(0.96, 1.04)
	p.play()

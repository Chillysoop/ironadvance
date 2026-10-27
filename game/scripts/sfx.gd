extends Node
## Tiny sound pool. Sfx.play("boom") from anywhere.

var streams := {}
var players: Array[AudioStreamPlayer] = []
var muted := false
var next := 0
var last_played := {}

func _ready() -> void:
	var dir := DirAccess.open("res://assets/sfx")
	for n in ["shot", "mg", "snipe", "boom", "bigboom", "thud", "bonk", "ping", "click", "select", "hurt", "coin", "start", "power", "levelup", "alarm", "toss", "splash", "bad", "slash", "tick", "scream", "buy", "deny", "step", "land", "rocket"]:
		var path := "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(path):
			streams[n] = load(path)
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		players.append(p)

func play(n: String, vol_db := 0.0, pitch := 1.0) -> void:
	if muted or not streams.has(n):
		return
	var now := Time.get_ticks_msec()
	if last_played.get(n, -1000) > now - 30:
		return  # several identical sounds in one frame just stack into noise
	last_played[n] = now
	var p := players[next]
	next = (next + 1) % players.size()
	p.stream = streams[n]
	p.volume_db = vol_db - 4.0
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.play()

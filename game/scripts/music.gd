extends Node
## Music and ambience (R6). Music.play("battle_a") crossfades to a looping track on the "Music" bus;
## Music.ambience("jungle") crossfades the biome bed on the "SFX" bus; Music.sting("victory") plays
## a one-shot over a ducked track. Tracks live in res://assets/music, beds in res://assets/ambience
## (tools/gen_audio_elevenlabs.py makes both). A missing file is simply silence.

const FADE := 1.2
const MUSIC_DB := -9.0
const AMB_DB := -15.0
const BIOME_TRACK := {
	"jungle": "battle_jungle", "delta": "battle_jungle", "palace": "battle_jungle",
	"desert": "battle_desert", "mountain": "battle_desert", "lake": "battle_desert",
	"refinery": "battle_steel", "fortress": "battle_steel", "city": "battle_steel", "train": "battle_steel",
	"harbor": "battle_night", "carrier": "battle_night", "mine": "battle_night", "volcano": "battle_night",
	"hive": "alien",
}
const BIOME_AMB := {
	"jungle": "jungle", "palace": "palace", "delta": "swamp", "desert": "desert", "mountain": "wind",
	"lake": "snow", "refinery": "industry", "fortress": "warzone", "city": "warzone", "train": "train",
	"harbor": "harbor", "carrier": "carrier", "mine": "cave", "volcano": "volcano", "hive": "hive",
}

var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var amb_a: AudioStreamPlayer
var amb_b: AudioStreamPlayer
var sting_p: AudioStreamPlayer
var current := ""
var current_amb := ""
var cache := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	const S := preload("res://scripts/settings.gd")
	S.bus("Music")
	S.bus("SFX")
	music_a = _player("Music")
	music_b = _player("Music")
	amb_a = _player("SFX")
	amb_b = _player("SFX")
	sting_p = _player("Music")

func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

func stream(dir: String, n: String) -> AudioStream:
	var key := dir + "/" + n
	if cache.has(key):
		return cache[key]
	var s: AudioStream = null
	for ext in ["ogg", "mp3", "wav"]:
		var path := "res://assets/%s/%s.%s" % [dir, n, ext]
		if ResourceLoader.exists(path):
			s = load(path)
			break
	cache[key] = s
	return s

func _swap(a: AudioStreamPlayer, b: AudioStreamPlayer, s: AudioStream, db: float) -> Array:
	## Fade a out and b in. Returns the new [front, back] pair.
	var front := a if a.playing else b
	var back := b if front == a else a
	if front.playing:
		var t := create_tween()
		t.tween_property(front, "volume_db", -60.0, FADE)
		t.tween_callback(front.stop)
	if s != null:
		back.stream = s
		back.volume_db = -60.0
		back.play()
		create_tween().tween_property(back, "volume_db", db, FADE)
	return [back, front]

func play(n: String) -> void:
	if n == current:
		return
	current = n
	if sting_p.playing:
		await sting_p.finished  # let a victory or defeat cue finish first
		if current != n:
			return
	_swap(music_a, music_b, stream("music", n), MUSIC_DB)

func stop() -> void:
	current = ""
	_swap(music_a, music_b, null, MUSIC_DB)

func ambience(n: String) -> void:
	if n == current_amb:
		return
	current_amb = n
	_swap(amb_a, amb_b, stream("ambience", n) if n != "" else null, AMB_DB)

func sting(n: String) -> void:
	## A one-shot cue (victory, defeat). The loop drops out so the cue is heard clean.
	var s := stream("music", n)
	stop()
	if s == null:
		return
	sting_p.stream = s
	sting_p.volume_db = MUSIC_DB + 2.0
	sting_p.play()

func for_battle(b) -> void:
	## Pick the battle track and the bed from the mission's biome.
	var biome: String = b.mission.get("biome", "")
	var tr: String = BIOME_TRACK.get(biome, "battle_" + ("night" if b.theme == "night" else ("jungle" if b.theme == "jungle" else "desert")))
	if b.in_lesson() or b.tutorial() or b.practice():
		tr = "training"
	play(tr)
	ambience(BIOME_AMB.get(biome, "night" if b.theme == "night" else ("jungle" if b.theme == "jungle" else "desert")))

func boss_check(b) -> void:
	## The boss theme takes over once a boss is on the field.
	if current == "boss" or current == "":
		return
	for u in b.units:
		if not u.dead and (b.is_boss(u) or u.type == "queen"):
			play("boss")
			Sfx.play("roar")
			return

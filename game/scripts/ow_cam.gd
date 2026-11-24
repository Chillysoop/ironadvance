class_name OwCam
extends CanvasLayer
## Overwatch cinematic. When a soldier on overwatch snaps onto a mover, the battle clock slows,
## the camera eases in on shooter and target, thin black bars and a vignette close in, the music
## goes muffled, and a reticle tightens over the target with rising lock-on beeps. Then the shot:
## a camera kick, a beat of hitstop on a hit (longer and a white flash on a kill), the hit plays
## out in slow motion, and everything eases back. All easing runs on real time, so it stays smooth
## while the battle clock crawls. Space / fast enemy turns and the settings toggle skip it.

const SettingsScript := preload("res://scripts/settings.gd")
const SLOW := 0.3          # battle clock while the cinematic is on
const DUR_FULL := 0.75     # real seconds the reticle takes to lock on the first shot
const DUR_CHAIN := 0.32    # ...and on a shot that follows close behind another
const CHAIN_TICKS := 150   # a new shot this soon after the last one is part of the same moment
const ZOOM_MAX := 1.24
const C_LOCK := Color("53d4e2")
const C_HOT := Color("ff4a3a")

var b  # Battle
var on := false
var s: Unit = null
var e: Unit = null
var aim := Vector2.ZERO
var lock := 0.0
var dur := DUR_FULL
var beeps := 0
var fired := false
var fire_t := 0.0          # real seconds since the shot, for the snap ring
var result := ""
var amt := 0.0             # eased 0..1: bars, vignette, muffle
var zoom := 1.0
var zoom_to := 1.0
var focus := Vector2.ZERO
var focus_to := Vector2.ZERO
var slow := 1.0
var slow_to := 1.0
var hitstop := 0.0
var flash := 0.0
var last_t := -99999
var shots := 0             # shots in this moment
var force := false         # tests: play it even under --iatest
var testing := false
var pane: Node2D
var vig: Texture2D
var lp_bus := -1
var lp_fx := -1

func _init() -> void:
	layer = 2  # over the HUD (1), under the reward/menu layers (5+)

func _ready() -> void:
	testing = OS.get_cmdline_user_args().has("--iatest")
	pane = Node2D.new()
	add_child(pane)
	pane.draw.connect(_paint)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0.0, 0.01, 0.03, 0.85))
	g.add_point(0.55, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.08, 1.08)
	gt.width = 192
	gt.height = 108
	vig = gt
	lp_bus = AudioServer.get_bus_index("Music")
	if lp_bus >= 0:
		for i in AudioServer.get_bus_effect_count(lp_bus):
			if AudioServer.get_bus_effect(lp_bus, i) is AudioEffectLowPassFilter:
				lp_fx = i
		if lp_fx < 0:
			var f := AudioEffectLowPassFilter.new()
			f.cutoff_hz = 20000
			AudioServer.add_bus_effect(lp_bus, f)
			lp_fx = AudioServer.get_bus_effect_count(lp_bus) - 1

func _exit_tree() -> void:
	Sfx.pitch_mul = 1.0
	_muffle(0.0)

func enabled() -> bool:
	if testing and not force:
		return false
	return bool(SettingsScript.get_value("slowmo")) and not b.fast_forward()

func lineup(shooter: Unit, target: Unit, at: Vector2) -> void:
	## Slow down, frame the two of them and tighten the reticle until it locks.
	if not enabled():
		await b.wait(10)  # the old beat before an overwatch shot
		return
	var chain: bool = on or b.t - last_t < CHAIN_TICKS
	s = shooter
	e = target
	aim = at
	lock = 0.0
	beeps = 0
	fired = false
	result = ""
	fire_t = 0.0
	dur = DUR_CHAIN if chain else DUR_FULL
	if not on and amt < 0.05:
		focus = Vector2(b.cam_x + Battle.W / 2.0, Battle.H / 2.0)
		shots = 0
	on = true
	shots += 1
	slow_to = SLOW
	var a := Vector2(s.x, s.y - s.h * 0.6)
	var span := Vector2(absf(at.x - a.x) + 240.0, absf(at.y - a.y) + 190.0)
	zoom_to = clampf(minf(Battle.W / span.x, Battle.H / span.y), 1.0, ZOOM_MAX)
	focus_to = a.lerp(at, 0.58)
	if not chain:
		Sfx.play("warp", -9.0, 0.55)
	while on and lock < 1.0 and is_instance_valid(s) and not s.dead and not e.dead:
		await get_tree().process_frame
	lock = 1.0

func shot(hp0: int) -> void:
	## Right after the overwatch bullet: kick, hitstop and the hit readout.
	if not on:
		return
	fired = true
	fire_t = 0.0
	zoom += 0.045 * SettingsScript.shake_mul()
	if e.dead:
		result = "KILL"
		hitstop = 0.14
		flash = 1.0
	elif e.hp < hp0:
		result = "HIT"
		hitstop = 0.06
		flash = 0.35
	else:
		result = "MISS"

func finish() -> void:
	## The overwatch moment is over: ease back to full speed and the normal view.
	if not on:
		return
	on = false
	slow_to = 1.0
	zoom_to = 1.0
	last_t = b.t

func center(def: Vector2) -> Vector2:
	## Where the battle camera points: the normal view blended toward the framed pair, kept inside
	## the strip the battle draws (cam_x .. cam_x + W) so nothing culled ever shows.
	var c := def.lerp(focus, clampf(amt, 0.0, 1.0))
	var half := Vector2(Battle.W, Battle.H) / (2.0 * zoom)
	c.x = clampf(c.x, b.cam_x + half.x, b.cam_x + Battle.W - half.x)
	c.y = clampf(c.y, half.y, Battle.H - half.y)
	return c

func step(real: float) -> void:
	## Called from the battle's _process with the real frame time.
	amt = lerpf(amt, 1.0 if on else 0.0, 1.0 - exp(-real * (8.0 if on else 5.0)))
	if not on and amt < 0.002:
		amt = 0.0
	zoom = lerpf(zoom, zoom_to, 1.0 - exp(-real * 6.0))
	if absf(zoom - 1.0) < 0.001 and zoom_to == 1.0:
		zoom = 1.0
	if on:
		focus = focus.lerp(focus_to, 1.0 - exp(-real * 7.0))
	slow = lerpf(slow, slow_to, 1.0 - exp(-real * 10.0))
	if slow_to >= 1.0 and slow > 0.985:
		slow = 1.0
	hitstop = maxf(0.0, hitstop - real)
	flash = maxf(0.0, flash - real * 3.5)
	fire_t += real
	if on and not fired and is_instance_valid(s):
		lock = minf(1.0, lock + real / dur)
		var k := int(lock * 4.0)
		while beeps < k and beeps < 3:
			beeps += 1
			Sfx.play("beep", -12.0, 1.25 + beeps * 0.18)
		if k >= 4 and beeps < 4:
			beeps = 4
			Sfx.play("ping", -5.0, 1.7)
		var m: Vector2 = b.muzzle(s)
		var want := atan2(aim.y - m.y, aim.x - m.x)
		s.gun_target = lerp_angle(s.gun_target, atan2(sin(want), cos(want) * s.face), 1.0 - exp(-real * 14.0))
	var dip := clampf((1.0 - slow) / (1.0 - SLOW), 0.0, 1.0)
	Sfx.pitch_mul = lerpf(1.0, 0.78, dip)
	_muffle(amt)
	pane.queue_redraw()

func _muffle(a: float) -> void:
	if lp_bus < 0 or lp_fx < 0 or lp_fx >= AudioServer.get_bus_effect_count(lp_bus):
		return
	var f = AudioServer.get_bus_effect(lp_bus, lp_fx)
	if f is AudioEffectLowPassFilter:
		f.cutoff_hz = lerpf(20000.0, 700.0, pow(clampf(a, 0.0, 1.0), 0.7))

func draw_world(v: Node2D) -> void:
	## Laser sight and the tightening reticle, in world space (the camera zoom scales them too).
	if amt < 0.02 or s == null or e == null or not is_instance_valid(s):
		return
	var a := clampf(amt, 0.0, 1.0)
	if fired:
		# the lock snaps open as the round lands
		var f := clampf(fire_t / 0.3, 0.0, 1.0)
		var cs := Color(1, 1, 1, (1.0 - f) * a)
		v.draw_arc(aim, lerpf(9.0, 34.0, f), 0, TAU, 24, cs, 2.0)
		return
	if not on:
		return
	var m: Vector2 = b.muzzle(s)
	var tip := m.lerp(aim, clampf(lock * 1.5, 0.0, 1.0))
	var locked := lock >= 1.0
	var col := C_LOCK.lerp(C_HOT, clampf((lock - 0.6) / 0.4, 0.0, 1.0))
	v.draw_line(m, tip, Color(C_HOT.r, C_HOT.g, C_HOT.b, 0.5 * a), 1.0)
	var r := lerpf(46.0, 10.0, 1.0 - pow(1.0 - lock, 2.2))
	var rot := (1.0 - lock) * 2.2
	for k in 4:
		var ang := rot + k * PI / 2.0 + PI / 4.0
		v.draw_arc(aim, r, ang - 0.38, ang + 0.38, 6, Color(col.r, col.g, col.b, 0.9 * a), 2.0)
	var tl := 5.0 if locked else 3.0
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		v.draw_line(aim + d * (r + 2.0), aim + d * (r + 2.0 + tl), Color(col.r, col.g, col.b, 0.8 * a), 1.0)
	if locked:
		v.draw_rect(Rect2(aim - Vector2(1.5, 1.5), Vector2(3, 3)), Color(1, 1, 1, a))

func _paint() -> void:
	if amt <= 0.0 and flash <= 0.0:
		return
	var W := float(Battle.W)
	var H := float(Battle.H)
	var a := clampf(amt, 0.0, 1.0)
	pane.draw_texture_rect(vig, Rect2(0, 0, W, H), false, Color(1, 1, 1, a))
	var bh := roundf(34.0 * a)  # the top one just covers the HUD bar
	if bh >= 1.0:
		var bar := Color(0.0, 0.0, 0.02)
		pane.draw_rect(Rect2(0, 0, W, bh), bar)
		pane.draw_rect(Rect2(0, H - bh, W, bh), bar)
		var edge := Color(C_LOCK.r, C_LOCK.g, C_LOCK.b, 0.35 * a)
		pane.draw_rect(Rect2(0, bh, W, 1), edge)
		pane.draw_rect(Rect2(0, H - bh - 1, W, 1), edge)
		if a > 0.6 and s != null and is_instance_valid(s):
			var ta := Color(1, 1, 1, (a - 0.6) / 0.4)
			var who: String = str(s.def.get("name", "SOLDIER"))
			Art.text(pane, "OVERWATCH  //  " + who.to_upper(), Vector2(24, bh - 12), 8, C_LOCK * ta, HORIZONTAL_ALIGNMENT_LEFT)
			var txt := "LOCKING"
			var tc := C_LOCK
			if fired:
				txt = result
				tc = Color("ffd23a") if result == "KILL" else (Color("e8dcc2") if result == "HIT" else Color("8a929c"))
			elif lock >= 1.0:
				txt = "LOCKED"
				tc = C_HOT
			# lock meter: a row of pips that fill as the reticle closes
			var pips := 10
			var x0 := W - 24.0 - pips * 9.0
			for i in pips:
				var full := fired or lock >= float(i + 1) / pips
				pane.draw_rect(Rect2(x0 + i * 9.0, H - bh + 12, 6, 6), (tc if full else Color(1, 1, 1, 0.15)) * ta)
			Art.text(pane, txt, Vector2(x0 - 10, H - bh + 19), 8, tc * ta, HORIZONTAL_ALIGNMENT_RIGHT)
	if flash > 0.0:
		pane.draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, 0.28 * flash))

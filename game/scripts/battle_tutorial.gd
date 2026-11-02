class_name BattleTutorial
extends RefCounted
## The training drill and the step-by-step boot camp.
## Split out of battle.gd (R3). Functions only: every piece of mission state lives on the Battle,
## reached through `bt`.

var bt: Battle

func _init(battle: Battle) -> void:
	bt = battle

# ---------------------------------------------------------------- the step-by-step tutorial
func lesson_prep() -> void:
	## Kit the recruit out for the lesson: Jet Boots for the jet lesson, and the why of a failed try.
	var L := bt.lesson()
	bt.lesson_why = str(bt.mission.get("retry", ""))
	for u in bt.squad_alive():
		if L.get("jet", 0) > 0:
			u.gb["jet"] = L.jet
			u.fuel_max = bt.jet_fuel(u)
			u.fuel = u.fuel_max

func lesson_hand() -> void:
	## Every turn of a lesson deals the same cards, energy and movement, so every try is the same.
	var L := bt.lesson()
	if L.get("live", false):
		return
	for s in bt.squad_alive():
		s.hand = []
		var i := 0
		for k in L.hand:
			s.hand.append({"id": -20 - i, "key": k, "tier": Data.base_tier(k), "temp": true})
			i += 1
		s.draw = []
		s.energy = int(L.energy) + maxi(0, s.energy - 3)  # an energy banked last turn still counts
		s.move_left = float(L.move)
	bt.ui_dirty = true

func lesson_playable(u: Unit) -> bool:
	## Something left to try: a card you can pay for (and a Drill with movement), or jet fuel.
	if u.fuel_max > 0 and u.fuel > 0:
		return true
	return u.hand.any(func(c): return bt.card_cost(u, c) <= u.energy and not bt.out_of_move(u, Data.card(c)))

func lesson_met() -> bool:
	var L := bt.lesson()
	if L.goal == "kill":
		return not bt.units.any(func(e): return e.team == "enemy" and not e.dead)
	var f = bt.lesson_flag()
	return bt.squad_alive().any(func(u):
		if u.air or u.walk != null or u.drill != null or u.zip != null:
			return false
		if L.has("fy"):
			return absf(u.y - f.y) <= 6  # anywhere up on top
		return u.x >= f.x - 8)

func lesson_update() -> void:
	## Checks the lesson a few times a second: done, failed (drowned, down, nothing left to try), or going.
	if bt.lesson_over or bt.state == "title" or bt.state == "over":
		return
	var L := bt.lesson()
	var main = bt.get_tree().current_scene
	if not bt.lesson_said and bt.mission.get("retry", "") == "" and bt.banners.is_empty() and main != null and main.has_method("call_in"):
		bt.lesson_said = true
		main.call_in(L.radio.map(func(l): return Run.radio_line("sarge", l, [])))
	if bt.units.any(func(u): return u.team == "squad" and u.dead):
		lesson_fail("drowned" if bt.units.any(func(u): return u.team == "squad" and u.sunk) else "down")
		return
	if bt.state != "player" or bt.busy or not bt.settled():
		return
	if lesson_met():
		lesson_pass()
		return
	if L.get("live", false) or bt.round_n < int(L.get("turns", 1)):
		return
	var u: Unit = bt.sel
	if u == null or u.dead or u.air or u.walk != null:
		return
	# walking only helps on the walking lessons: elsewhere, nothing left to play means it's over
	if (u.move_left <= 6 or not L.get("legs", false)) and not lesson_playable(u):
		lesson_fail("ammo" if L.goal == "kill" else "stuck")

func lesson_pass() -> void:
	if bt.lesson_over:
		return
	bt.lesson_over = true
	bt.busy = true
	bt.card_idx = -1
	bt.jet_armed = false
	bt.ui_dirty = true
	var last: bool = int(bt.mission.lesson_i) >= Data.LESSONS.size() - 1
	bt.banner("BOOT CAMP COMPLETE!" if last else "LESSON COMPLETE!", Color("62d26f"), "NICE WORK, RECRUIT")
	Sfx.play("levelup" if last else "coin")
	for u in bt.squad_alive():
		u.pose = "cheer"; u.pose_t = 60
	await bt.wait(90)
	bt.lesson_done.emit("pass")

func lesson_fail(why: String) -> void:
	## Failing a lesson just runs it again, straight away, with the same cards, energy and fuel.
	if bt.lesson_over:
		return
	bt.lesson_over = true
	bt.busy = true
	bt.card_idx = -1
	bt.jet_armed = false
	bt.ui_dirty = true
	if why != "retry":
		bt.banner(Data.LESSON_FAIL.get(why, "AGAIN!"), Color("ff7a3d"), "SAME KIT, SAME SPOT")
		Sfx.play("deny")
		await bt.wait(55)
	bt.lesson_done.emit("fail:" + why)

func lesson_skip() -> void:
	if bt.lesson_over:
		return
	bt.lesson_over = true
	bt.busy = true
	bt.lesson_done.emit("skip")

func tut_clear(key: String) -> bool:
	return bt.tut_marks.get(key, []).all(func(u): return u.dead)

func tut_update() -> void:
	## One step at a time: the sergeant calls in what to do, the step ends when it's done.
	if bt.state != "player" or bt.busy:
		return
	var done := false
	match bt.tut_step:
		bt.TUT_MOVE:
			done = bt.squad_alive().any(func(u): return u.x >= bt.TUT_FLAG_X - 6)
		bt.TUT_SHOOT:
			done = tut_clear("target")
		bt.TUT_CRATE:
			done = tut_clear("crate")
		bt.TUT_THROW:
			# any squad blast passes: the lesson is the throw, and the pair join the fight if they live
			done = tut_clear("group") or bt.tut_blast
		bt.TUT_PUSH:
			done = bt.cam_x > 40
	if done:
		bt.tut_step += 1
		Sfx.play("coin")
	# D1: the sergeant waits until the banner and any faction intro have closed
	var quiet: bool = bt.banners.is_empty() and (bt.hud == null or (bt.hud.coach_queue.is_empty() and bt.hud.coach_box.get_child_count() == 0))
	if quiet and bt.tut_said < bt.tut_step and bt.tut_step < bt.TUT_DONE:
		bt.tut_said = bt.tut_step
		var main = bt.get_tree().current_scene
		if main != null and main.has_method("call_in"):
			main.call_in(Data.TUT_LINES[bt.tut_step].map(func(l): return Run.radio_line("sarge", l, [])))
	# the card a step teaches is always in the selected soldier's hand
	var need: String = {bt.TUT_SHOOT: "rifle", bt.TUT_CRATE: "rifle", bt.TUT_THROW: "frag"}.get(bt.tut_step, "")
	if need != "" and bt.sel != null and not bt.sel.dead and bt.sel.energy < Data.CARDS[need].cost:
		# the selected recruit is spent: hand the lesson to one who can still play it
		var fresh: Array = bt.squad_alive().filter(func(s): return s.energy >= Data.CARDS[need].cost)
		if not fresh.is_empty():
			bt.select_unit(fresh[0])
	if need != "" and bt.sel != null and not bt.sel.dead and (bt.sel.hand.is_empty() or bt.sel.hand[0].key != need):
		# D3: first in the hand, so "press its number" is always 1 (a drawn copy moves up front)
		var at: int = -1
		for i in bt.sel.hand.size():
			if bt.sel.hand[i].key == need:
				at = i
				break
		if bt.card_idx >= 0 and (at < 0 or bt.card_idx < at):
			bt.card_idx += 1
		elif at >= 0 and bt.card_idx == at:
			bt.card_idx = 0
		bt.sel.hand.insert(0, bt.sel.hand.pop_at(at) if at >= 0 else {"id": -2, "key": need, "tier": Data.base_tier(need), "temp": true})
		bt.ui_dirty = true

func practice_round() -> void:
	## D5: no enemy phase at the range. When every dummy is down, a fresh set stands up.
	bt.state = "enemy"
	bt.busy = true
	bt.ui_dirty = true
	await bt.wait(20)
	if not bt.units.any(func(e): return e.team == "enemy" and not e.dead):
		for d in bt.dummies:
			var e := bt.mk_enemy(d[0], d[1], bt.T.stand_y(d[1], 0))
			e.active = true
			bt.units.append(e)
		bt.banner("RANGE RESET", Color("62d26f"))
		await bt.wait(30)
	bt.start_player_turn()

func leave_practice() -> void:
	if bt.state == "over":
		return
	bt.state = "over"
	bt.busy = true
	bt.mission_over.emit(true)

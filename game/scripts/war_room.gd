extends Control
## The War Room (campaign mode): the act's front map. Click a sector to see what it pays and how
## each soldier fits it, then attack it, patrol a held one, or go back to HQ.

signal attack(sc: Dictionary, patrol: bool)
signal back
signal quit

const HudScript := preload("res://scripts/hud.gd")

const MAP := Rect2(16, 80, 664, 396)
const SIDE := Rect2(690, 80, 254, 396)
const NODE := 34.0

var t := 0
var sel := ""            # selected sector id
var held := {}           # textures must stay referenced until the frame renders
var go_btn: Control = null
var threat_btn: Control = null
var company_open := false  # C1: the roster overlay where you pick who deploys
var msg := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for sc in Run.act().sectors:
		if Run.sector_open(sc) and (sel == "" or sc.get("stronghold", false)):
			sel = sc.id
	build()

func build() -> void:
	for c in get_children():
		c.queue_free()
	var bk := HudScript.PixButton.new()
	bk.text = "<< HQ"
	bk.color = Color("9aa2ae")
	bk.small = true
	bk.size = Vector2(110, 32)
	bk.position = Vector2(16, 494)
	bk.pressed.connect(func(): Sfx.play("click"); back.emit())
	add_child(bk)
	var th := HudScript.PixButton.new()
	th.small = true
	th.size = Vector2(200, 32)
	th.position = Vector2(136, 494)
	th.color = Color("ff7a3d") if Run.threat > 0 else Color("9aa2ae")
	th.text = "THREAT %d" % Run.threat
	th.sub = "+%d%% PAY" % roundi(Run.threat * Data.CAMP_THREAT_PAY * 100) if Run.threat > 0 else "OPTIONAL, MORE PAY"
	th.pressed.connect(func():
		# P3: pick a threat level per op; each level stacks on the ones below it
		Run.threat = (Run.threat + 1) % (Data.THREATS.size() + 1)
		Sfx.play("click")
		build())
	add_child(th)
	threat_btn = th
	var sq := HudScript.PixButton.new()
	sq.text = "SAVE AND QUIT"
	sq.color = Color("9aa2ae")
	sq.small = true
	sq.size = Vector2(160, 32)
	sq.position = Vector2(784, 494)
	sq.pressed.connect(func(): Sfx.play("click"); quit.emit())
	add_child(sq)
	var cb := HudScript.PixButton.new()
	cb.small = true
	cb.size = Vector2(112, 32)
	cb.position = Vector2(662, 494)
	cb.color = Color("53d4e2")
	cb.text = "DONE" if company_open else "COMPANY"
	cb.sub = "" if company_open else "%d IN SQUAD, %d" % [Run.soldiers.size(), Run.company().size()]
	cb.pressed.connect(func(): Sfx.play("click"); company_open = not company_open; msg = ""; build())
	add_child(cb)
	var sc := Run.sector(sel)
	var go := HudScript.PixButton.new()
	go.size = Vector2(250, 40)
	go.position = Vector2(400, 490)
	go.color = Color("ff4d3d")
	if sc.is_empty():
		go.text = "PICK A SECTOR"
		go.disabled = true
	elif Run.sector_open(sc):
		go.text = "ASSAULT" if sc.get("stronghold", false) else "ATTACK"
		go.pressed.connect(func(): Sfx.play("start"); attack.emit(sc, false))
	elif Run.sector_held(sc.id) and Run.bonus_at(sc) != "":
		go.text = "BONUS OP"
		go.sub = "PAYS EPIC GEAR"
		go.color = Color("c47bff")
		go.pressed.connect(func(): Sfx.play("start"); attack.emit(sc, false))
	elif Run.sector_held(sc.id):
		go.text = "PATROL"
		go.sub = "HALF PAY, NOBODY DIES"
		go.color = Color("62d26f")
		go.pressed.connect(func(): Sfx.play("start"); attack.emit(sc, true))
	else:
		go.text = "NOT REACHABLE YET"
		go.disabled = true
	if Run.soldiers.is_empty():
		go.disabled = true
	add_child(go)
	go_btn = go

func node_pos(sc: Dictionary) -> Vector2:
	return Vector2(sc.at[0], sc.at[1])

func lz_pos() -> Vector2:
	var a: Array = Run.act().lz.at
	return Vector2(a[0], a[1])

func link_pos(id: String) -> Vector2:
	return lz_pos() if id == "lz" else node_pos(Run.sector(id))

func card_rect(i: int) -> Rect2:
	## Roster card i on the company overlay: two rows of five over the map.
	return Rect2(MAP.position.x + 8 + (i % 5) * 130, MAP.position.y + 36 + (i / 5) * 176, 124, 168)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and company_open:
		var co := Run.company()
		for i in co.size():
			if card_rect(i).has_point(ev.position):
				accept_event()
				msg = Run.toggle_squad(co[i])
				Sfx.play("deny" if msg != "" else "select")
				build()
				return
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		for sc in Run.act().sectors:
			var r := NODE / 2 + (6 if sc.get("stronghold", false) else 0)
			if ev.position.distance_to(node_pos(sc)) < r + 6:
				accept_event()
				sel = sc.id
				Sfx.play("select")
				build()
				return

func _process(_d: float) -> void:
	t += 1
	queue_redraw()

func bg(n: String) -> Texture2D:
	if not held.has(n):
		held[n] = load("res://assets/bg/%s.png" % n)
	return held[n]

func biome_col(id: String) -> Color:
	var bm: Dictionary = Data.BIOMES[id]
	return bm.look.get("grass", Data.THEMES[bm.theme].grass)

func state(sc: Dictionary) -> String:
	if Run.sector_held(sc.id):
		return "held"
	return "open" if Run.sector_open(sc) else "locked"

func _draw() -> void:
	var A: Dictionary = Run.act()
	draw_texture_rect(bg("night_sky"), Rect2(0, 0, 960, 540), false, Color(0.5, 0.5, 0.6))
	draw_rect(Rect2(0, 0, 960, 540), Color(0.04, 0.05, 0.06, 0.8))
	# header
	Art.text(self, "WAR ROOM", Vector2(24, 34), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
	Art.text(self, "ACT %s  %s%s" % [A.roman, A.name, "  TOUR %d" % int(Run.camp.get("tour", 1)) if int(Run.camp.get("tour", 1)) > 1 else ""], Vector2(190, 34), 16, Color("ff7a3d"), HORIZONTAL_ALIGNMENT_LEFT, 2)
	Art.text(self, A.text, Vector2(24, 60), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
	var sc_txt := "%d SCRIP" % Run.scrip
	Art.text(self, sc_txt, Vector2(944, 34), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT, 2)
	Art.text(self, "%d SALVAGE  %d BIO" % [int(Run.meta.get("salvage", 0)), int(Run.meta.get("bio", 0))], Vector2(944, 52), 8, Color("53d4e2"), HORIZONTAL_ALIGNMENT_RIGHT)
	# the map: dark water, a patch of ground under every sector in its biome's colour
	draw_rect(MAP, Color("16232c"))
	for sc in A.sectors:
		var c := biome_col(sc.biome)
		draw_circle(node_pos(sc), 96, Color(c.r, c.g, c.b, 0.10))
		draw_circle(node_pos(sc), 62, Color(c.r, c.g, c.b, 0.16))
	draw_circle(lz_pos(), 60, Color(0.85, 0.75, 0.5, 0.14))
	for i in 22:  # map grid
		draw_line(Vector2(MAP.position.x + i * 32, MAP.position.y), Vector2(MAP.position.x + i * 32, MAP.end.y), Color(1, 1, 1, 0.03))
	for i in 13:
		draw_line(Vector2(MAP.position.x, MAP.position.y + i * 32), Vector2(MAP.end.x, MAP.position.y + i * 32), Color(1, 1, 1, 0.03))
	draw_rect(MAP, Color("3a4048"), false, 2)
	# roads
	var done := {}
	for sc in A.sectors:
		for l in sc.links:
			var k := [sc.id, l]
			k.sort()
			if done.has(str(k)):
				continue
			done[str(k)] = true
			var a := node_pos(sc)
			var b := link_pos(l)
			var live := Run.sector_held(sc.id) or Run.sector_held(l)
			var col := Color(0.91, 0.86, 0.76, 0.6 if live else 0.22)
			var n := int(a.distance_to(b) / 10)
			for j in n:
				if j % 2 == 0:
					draw_line(a.lerp(b, float(j) / n), a.lerp(b, float(j + 1) / n), col, 3)
	# landing zone
	var lz := lz_pos()
	draw_rect(Rect2(lz - Vector2(NODE, NODE) / 2, Vector2(NODE, NODE)), Color(0.05, 0.035, 0.03))
	draw_rect(Rect2(lz - Vector2(NODE, NODE) / 2 + Vector2(2, 2), Vector2(NODE - 4, NODE - 4)), Color("62d26f"))
	Art.text(self, "LZ", lz + Vector2(0, 5), 8, Color(0.05, 0.035, 0.03), HORIZONTAL_ALIGNMENT_CENTER, 0)
	Art.text(self, A.lz.name, lz + Vector2(0, NODE / 2 + 14), 8, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER)
	# sectors
	for sc in A.sectors:
		var p := node_pos(sc)
		var big: bool = sc.get("stronghold", false)
		var sz := NODE + (12 if big else 0)
		var st := state(sc)
		var col: Color = {"held": Color("62d26f"), "open": Color("ffd23a"), "locked": Color("4a525c")}[st]
		if big and st != "held":
			col = Color("ff4d3d") if st == "open" else Color("6a3030")
		var r := Rect2(p - Vector2(sz, sz) / 2, Vector2(sz, sz))
		if st == "open" and (t / 20) % 2 == 0:
			draw_rect(r.grow(4), Color(col.r, col.g, col.b, 0.35))
		draw_rect(r, Color(0.05, 0.035, 0.03))
		draw_rect(r.grow(-2), col)
		if sc.id == sel:
			draw_rect(r.grow(3), Color.WHITE, false, 2)
		if Run.bonus_at(sc) != "":
			# P2: a bonus op waiting on this sector
			var bp := p + Vector2(sz / 2 + 4, -sz / 2 - 4)
			draw_circle(bp, 9 + (1 if (t / 15) % 2 == 0 else 0), Color(0.05, 0.035, 0.03))
			draw_circle(bp, 7 + (1 if (t / 15) % 2 == 0 else 0), Color("c47bff"))
			Art.text(self, "!", bp + Vector2(0, 4), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		var tag: String = "FORT" if big else sc.id.to_upper()
		Art.text(self, tag, p + Vector2(0, 5), 8, Color(0.05, 0.035, 0.03) if st != "locked" or big else Color("c9ccd1"), HORIZONTAL_ALIGNMENT_CENTER, 0)
		Art.text(self, sc.name, p + Vector2(0, sz / 2 + 14), 8, Color.WHITE if st != "locked" else Color("8a929c"), HORIZONTAL_ALIGNMENT_CENTER)
		if sc.has("perk") or sc.has("hold"):
			var what: String = Data.SECTOR_PERKS[sc.perk].name if sc.has("perk") else hold_text(sc.hold)
			Art.text(self, what, p + Vector2(0, sz / 2 + 30), 16, Color("62d26f") if st == "held" else Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
	var need := int(A.need)
	Art.text(self, "%d OF %d TAKEN" % [mini(Run.held_count(), need), need], Vector2(MAP.end.x - 12, MAP.position.y + 20), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT)
	var lx := MAP.position.x + 12
	for lg in [["HELD", Color("62d26f")], ["OPEN", Color("ffd23a")], ["NOT YET", Color("4a525c")], ["STRONGHOLD", Color("ff4d3d")]]:
		draw_rect(Rect2(lx, MAP.position.y + 10, 10, 10), lg[1])
		Art.text(self, lg[0], Vector2(lx + 14, MAP.position.y + 20), 8, Color("9aa2ae"))
		lx += Art.text_width(lg[0], 8) + 30
	draw_side()
	if company_open:
		draw_company()

func draw_company() -> void:
	## C1: the whole company with each soldier's fit for the picked sector. Click to put them in or out.
	draw_rect(MAP, Color(0.04, 0.05, 0.06, 0.97))
	draw_rect(MAP, Color("53d4e2"), false, 2)
	var sc := Run.sector(sel)
	Art.text(self, "THE COMPANY  %d OF %d" % [Run.company().size(), Data.COMPANY_MAX], Vector2(MAP.position.x + 12, MAP.position.y + 22), 8, Color("53d4e2"))
	Art.text(self, msg if msg != "" else "Click to put a soldier in or out. One of each class per squad, up to %d." % Data.SQUAD_MAX, Vector2(MAP.end.x - 12, MAP.position.y + 22), 16, Color("ff7a5a") if msg != "" else Color("9aa2ae"), HORIZONTAL_ALIGNMENT_RIGHT, 2, true)
	var co := Run.company()
	for i in co.size():
		var s: Dictionary = co[i]
		var r := card_rect(i)
		var on := Run.soldiers.has(s)
		draw_rect(r, Color(0.05, 0.035, 0.03))
		draw_rect(r.grow(-1), Color("24302a") if on else Color("1e2126"))
		if on:
			draw_rect(r, Color("62d26f"), false, 2)
		Art.draw_char(self, Art.look_sheet(s), "idle", (t / 12 + i) % 4, Vector2(r.get_center().x, r.position.y + 62), 1, false, 0, 1.0 if on else 0.75, 0, true, 1.4)
		for k in Run.rank(s):  # chevrons
			var cx := r.position.x + 10
			var cy := r.position.y + 10 + k * 5
			draw_line(Vector2(cx, cy + 3), Vector2(cx + 5, cy), Color("ffd23a"), 2)
			draw_line(Vector2(cx + 5, cy), Vector2(cx + 10, cy + 3), Color("ffd23a"), 2)
		Art.text(self, "IN SQUAD" if on else "BENCH", Vector2(r.end.x - 6, r.end.y - 8), 8, Color("62d26f") if on else Color("6c7480"), HORIZONTAL_ALIGNMENT_RIGHT)
		var y := r.position.y + 82
		Art.text(self, "%s %s" % [Run.rank_name(s), s.def.name], Vector2(r.position.x + 8, y), 8, Color.WHITE)
		Art.text(self, "%s  LV%d" % [s.def.cls, s.lvl], Vector2(r.position.x + 8, y + 16), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		var sv := Run.svc(s)
		Art.text(self, "%d OPS  %d KILLS" % [int(sv.ops), int(sv.kills)], Vector2(r.position.x + 8, y + 32), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		if sv.medals.size():
			Art.text(self, "%d MEDAL%s" % [sv.medals.size(), "" if sv.medals.size() == 1 else "S"], Vector2(r.position.x + 8, y + 48), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		if not sc.is_empty():
			var f := Run.fit(s, sc.biome)
			Art.text(self, f.to_upper(), Vector2(r.position.x + 8, r.end.y - 8), 8, {"great": Color("62d26f"), "ok": Color("e8dcc2"), "rough": Color("ff7a5a")}[f])

func hold_text(h: Dictionary) -> String:
	var parts: Array = []
	for k in h:
		parts.append("+%d %s" % [h[k], k.to_upper()])
	return " ".join(parts) + " PER OP"

func draw_side() -> void:
	draw_rect(SIDE, Color(0.06, 0.06, 0.07, 0.95))
	draw_rect(SIDE, Color("3a4048"), false, 2)
	var sc := Run.sector(sel)
	var x := SIDE.position.x + 12
	var y := SIDE.position.y + 22
	if sc.is_empty():
		Art.text(self, "CLICK A SECTOR", Vector2(x, y), 8, Color("ffd23a"))
		return
	var bm: Dictionary = Data.BIOMES[sc.biome]
	Art.text(self, sc.name, Vector2(x, y), 8, Color("ffd23a"))
	y += 22
	var st := state(sc)
	var rows: Array = []
	rows.append(["STATUS", {"held": "HELD", "open": "OPEN", "locked": "NOT REACHABLE"}[st]])
	var jb: String = Run.op_job(sc) if Run.bonus_at(sc) == "" else str(Data.BONUS_OPS[Run.bonus_at(sc)].job)
	rows.append(["JOB", "STRONGHOLD" if sc.get("stronghold", false) else ("PUSH TO THE BOSS" if jb == "push" else Data.JOBS[jb].goal)])
	rows.append(["BIOME", bm.name])
	var a: Dictionary = Run.act()
	rows.append(["ENEMY", ["JACKALS", "JACKALS + VHARR", "VHARR"][int(a.tier)] + (" + BREACH" if float(a.breach) >= 0.5 else "")])
	for r in rows:
		Art.text(self, r[0], Vector2(x, y), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		Art.text(self, r[1], Vector2(SIDE.end.x - 12, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_RIGHT, 2, true)
		y += 18
	y += 4
	if Run.bonus_at(sc) != "":
		var B: Dictionary = Data.BONUS_OPS[Run.bonus_at(sc)]
		Art.text(self, "BONUS: " + B.name, Vector2(x, y), 8, Color("c47bff"))
		y += 6
		for line in CardView.wrap_text(B.text + " %d ops left." % int(Run.camp.bonus.left), SIDE.size.x - 24, 16):
			y += 16
			Art.text(self, line, Vector2(x, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		y += 18
	elif sc.has("hold"):
		Art.text(self, "HOLDING IT", Vector2(x, y), 8, Color("62d26f"))
		y += 6
		for line in CardView.wrap_text(hold_text(sc.hold) + " for the rest of the war.", SIDE.size.x - 24, 16):
			y += 16
			Art.text(self, line, Vector2(x, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		y += 18
	elif sc.has("perk"):
		var P: Dictionary = Data.SECTOR_PERKS[sc.perk]
		Art.text(self, "HOLDING IT: " + P.name, Vector2(x, y), 8, Color("62d26f"))
		y += 6
		for line in CardView.wrap_text(P.text, SIDE.size.x - 24, 16):
			y += 16
			Art.text(self, line, Vector2(x, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		y += 18
	elif sc.get("stronghold", false):
		var need := int(a.need)
		Art.text(self, "OPENS AFTER %d SECTORS (%d HELD)" % [need, Run.held_count()], Vector2(x, y), 8, Color("ff7a3d") if st == "locked" else Color("62d26f"))
		Art.text(self, "Beat it to end Act %s." % a.roman, Vector2(x, y + 16), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		y += 40
	# M4: how each soldier's deck suits this biome
	Art.text(self, "FIT", Vector2(x, y + 4), 8, Color("ffb23e"))
	Art.text(self, "GOOD FOR " + Data.STYLES[bm.favor], Vector2(SIDE.end.x - 12, y + 4), 8, Color("62d26f"), HORIZONTAL_ALIGNMENT_RIGHT)
	y += 12
	var al: Array = Run.soldiers.filter(func(s): return s.alive)
	for j in al.size():
		var so: Dictionary = al[j]
		var f := Run.fit(so, sc.biome)
		var row := y + j * 26
		Art.draw_char(self, Art.look_sheet(so), "idle", (t / 12 + j) % 4, Vector2(x + 12, row + 22), 1, false, 0, 1.0, 0, true, 0.8)
		Art.text(self, so.def.name, Vector2(x + 30, row + 16), 8, Color.WHITE)
		var stars: String = {"great": "***", "ok": "**", "rough": "*"}[f]
		Art.text(self, "%s %s" % [stars, f.to_upper()], Vector2(SIDE.end.x - 12, row + 16), 8, {"great": Color("62d26f"), "ok": Color("e8dcc2"), "rough": Color("ff7a5a")}[f], HORIZONTAL_ALIGNMENT_RIGHT)
	# M2: the war's income, paid after every op
	var inc := Run.income()
	var parts: Array = []
	for k in ["scrip", "salvage", "bio"]:
		if int(inc[k]) > 0:
			parts.append("+%d %s" % [inc[k], k.to_upper()])
	Art.text(self, "WAR INCOME AFTER EVERY OP", Vector2(x, SIDE.end.y - 30), 8, Color("62d26f"))
	Art.text(self, "  ".join(parts) if parts.size() else "Hold sectors to earn it.", Vector2(x, SIDE.end.y - 12), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)


# ================================================================ save slots (L1)
class SlotPicker extends Control:
	## Three campaign save slots: continue one, start a new war in an empty one, or start over.
	signal picked(slot: int, fresh: bool)
	signal back
	var t := 0
	var confirm := -1   # the slot whose START OVER was clicked once
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		build()
	func card(i: int) -> Rect2:
		return Rect2(60 + i * 290, 120, 260, 300)
	func build() -> void:
		for c in get_children():
			c.queue_free()
		for i in Data.CAMP_SLOTS:
			var h := Run.camp_head(i)
			var cr := card(i)
			var bt = load("res://scripts/hud.gd").PixButton.new()
			bt.size = Vector2(cr.size.x - 40, 40)
			bt.position = Vector2(cr.position.x + 20, cr.end.y - 100)
			bt.color = Color("ff4d3d")
			var slot := i
			if h.is_empty():
				bt.text = "NEW CAMPAIGN"
				bt.pressed.connect(func(): picked.emit(slot, true))
			else:
				bt.text = "CONTINUE"
				bt.pressed.connect(func(): picked.emit(slot, false))
				var ov = load("res://scripts/hud.gd").PixButton.new()
				ov.small = true
				ov.size = Vector2(cr.size.x - 80, 26)
				ov.position = Vector2(cr.position.x + 40, cr.end.y - 48)
				ov.color = Color("ff7a3d") if confirm == i else Color("9aa2ae")
				ov.text = "CLICK AGAIN TO ERASE" if confirm == i else "START OVER"
				ov.pressed.connect(func():
					if confirm == slot:
						Run.delete_campaign(slot)
						picked.emit(slot, true)
					else:
						confirm = slot
						Sfx.play("deny")
						build())
				add_child(ov)
			add_child(bt)
		var bk = load("res://scripts/hud.gd").PixButton.new()
		bk.text = "<< TITLE"
		bk.small = true
		bk.color = Color("9aa2ae")
		bk.size = Vector2(140, 30)
		bk.position = Vector2(410, 470)
		bk.pressed.connect(func(): back.emit())
		add_child(bk)
	func _process(_d: float) -> void:
		t += 1
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 540), Color("101418"))
		Art.text(self, "CAMPAIGN", Vector2(480, 58), 32, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 3)
		Art.text(self, "One company, a whole war. Nothing resets. Pick a save slot.", Vector2(480, 92), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
		for i in Data.CAMP_SLOTS:
			var cr := card(i)
			var h := Run.camp_head(i)
			draw_rect(cr, Color(0.07, 0.07, 0.08))
			draw_rect(cr, Color("ffb23e") if h.size() else Color("3a4048"), false, 2)
			Art.text(self, "SLOT %d" % (i + 1), Vector2(cr.position.x + 16, cr.position.y + 26), 8, Color("9aa2ae"))
			if h.is_empty():
				Art.text(self, "EMPTY", Vector2(cr.get_center().x, cr.position.y + 110), 16, Color("6c7480"), HORIZONTAL_ALIGNMENT_CENTER, 2)
				continue
			var A: Dictionary = Data.ACTS[clampi(int(h.act), 0, Data.ACTS.size() - 1)]
			Art.text(self, ("WAR WON" if h.get("done", false) else "ACT %s" % A.roman) + ("  TOUR %d" % int(h.get("tour", 1)) if int(h.get("tour", 1)) > 1 else ""), Vector2(cr.position.x + 16, cr.position.y + 58), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
			Art.text(self, A.name, Vector2(cr.position.x + 16, cr.position.y + 80), 8, Color("ff7a3d"))
			var mins := int(float(h.secs) / 60.0)
			Art.text(self, "%d OPS   %dH %02dM" % [int(h.ops), mins / 60, mins % 60], Vector2(cr.position.x + 16, cr.position.y + 104), 8, Color("e8dcc2"))
			var names: Array = h.get("names", [])
			for j in names.size():
				Art.text(self, names[j], Vector2(cr.position.x + 16 + (j % 2) * 120, cr.position.y + 130 + (j / 2) * 18), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)


# ================================================================ promotions and training (C3, C4)
class PickQueue extends Control:
	## After an op: each promotion and each level the bench trained up to, one pick of three.
	signal done
	var t := 0
	var cur := {}
	var opts: Array = []
	var log_line := ""
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		next()
	func next() -> void:
		for c in get_children():
			c.queue_free()
		var q := Run.pending_picks()
		if q.is_empty():
			Run.save_campaign()
			done.emit()
			return
		cur = q[0]
		var s: Dictionary = cur.s
		if cur.kind == "promo":
			opts = Run.promo_offers(s).map(func(id): return {"kind": "promo", "id": id, "name": Data.PROMOTIONS[id].name, "text": Data.PROMOTIONS[id].text})
		else:
			opts = Run.level_options(s)
		for i in opts.size():
			var bt = load("res://scripts/hud.gd").PixButton.new()
			bt.text = "PICK"
			bt.color = Color("ffd23a")
			bt.size = Vector2(180, 36)
			bt.position = Vector2(card(i).get_center().x - 90, card(i).end.y + 14)
			var k := i
			bt.pressed.connect(func(): pick(k))
			add_child(bt)
	func card(i: int) -> Rect2:
		return Rect2(120 + i * 250, 220, 220, 120)
	func pick(i: int) -> void:
		var s: Dictionary = cur.s
		var o: Dictionary = opts[i]
		Sfx.play("levelup")
		if cur.kind == "promo":
			log_line = Run.promote(s, o.id)
		else:
			log_line = Run.apply_option(s, o)
			if int(s.train) > 1:
				s.train = int(s.train) - 1
			else:
				s.erase("train")
		next()
	func _process(_d: float) -> void:
		t += 1
		queue_redraw()
	func opt_name(o: Dictionary) -> String:
		if o.kind == "card":
			return "%s %s" % [Data.tier_name(o.tier).capitalize(), Data.CARDS[o.key].name]
		return o.name
	func opt_text(o: Dictionary) -> String:
		return Data.CARDS[o.key].text if o.kind == "card" else o.text
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 540), Color("101418"))
		if cur.is_empty():
			return
		var s: Dictionary = cur.s
		var promo: bool = cur.kind == "promo"
		Art.text(self, "PROMOTION" if promo else "TRAINING", Vector2(480, 58), 32, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 3)
		var rk: int = Run.rank(s) - int(s.get("promo", 1)) + 1 if promo else Run.rank(s)
		var line := "%s is now a %s. Pick what the new stripes bring." % [s.def.name, Data.RANKS[clampi(rk, 0, Data.RANKS.size() - 1)].name.capitalize()] if promo else "%s trained on the bench and reached level %d. Pick it like a level-up." % [s.def.name, s.lvl - int(s.get("train", 1)) + 1]
		Art.text(self, line, Vector2(480, 92), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
		if promo and rk >= Data.RANKS.size() - 1:
			Art.text(self, "A CAPTAIN IN THE SQUAD GIVES EVERYONE +%d DODGE" % Data.CAPTAIN_DODGE, Vector2(480, 114), 8, Color("62d26f"), HORIZONTAL_ALIGNMENT_CENTER)
		Art.draw_char(self, Art.look_sheet(s), "cheer", (t / 10) % 2, Vector2(480, 180), 1, false, 0, 1.0, 0, false, 1.8)
		for i in opts.size():
			var r := card(i)
			var o: Dictionary = opts[i]
			draw_rect(r, Color(0.05, 0.035, 0.03))
			draw_rect(r.grow(-1), Color("22262c"))
			draw_rect(r, Color("ffd23a"), false, 2)
			Art.text(self, opt_name(o), Vector2(r.get_center().x, r.position.y + 28), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
			var y := r.position.y + 52
			for ln in CardView.wrap_text(opt_text(o), r.size.x - 20, 16):
				Art.text(self, ln, Vector2(r.get_center().x, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
				y += 16
		if log_line != "":
			Art.text(self, log_line, Vector2(480, 500), 16, Color("62d26f"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)

class RadioScreen extends Control:
	## S2: a few lines of radio chatter with a portrait. Click to go on, SKIP to jump past it all.
	signal done
	var lines: Array = []
	var i := 0
	var t := 0
	var shown := 0
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var sk = load("res://scripts/hud.gd").PixButton.new()
		sk.text = "SKIP"
		sk.color = Color("9aa2ae")
		sk.small = true
		sk.size = Vector2(90, 28)
		sk.position = Vector2(850, 16)
		sk.pressed.connect(finish)
		add_child(sk)
		if lines.is_empty():
			finish.call_deferred()
	func finish() -> void:
		if i < 0:
			return
		i = -1
		done.emit()
	func advance() -> void:
		if i < 0:
			return
		var full: int = lines[i].text.length()
		if shown < full:
			shown = full
			return
		i += 1
		shown = 0
		Sfx.play("tick")
		if i >= lines.size():
			finish()
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			advance()
	func _unhandled_input(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and (ev.keycode == KEY_ENTER or ev.keycode == KEY_SPACE):
			advance()
		elif ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			finish()
	func _process(_d: float) -> void:
		t += 1
		if i >= 0 and i < lines.size():
			shown = mini(shown + 2, lines[i].text.length())
		queue_redraw()
	func portrait(L: Dictionary, r: Rect2) -> void:
		## The speaker in a lit frame: a soldier in their kit, or the officer behind the voice.
		draw_rect(r, Color(0.05, 0.035, 0.03))
		draw_rect(r.grow(-2), L.col.darkened(0.75))
		for y in range(int(r.position.y) + 4, int(r.end.y) - 2, 4):
			draw_rect(Rect2(r.position.x + 2, y, r.size.x - 4, 1), Color(0, 0, 0, 0.25))
		var sheet: String = {"cmd": "sq_moss_beret", "varga": "en_radio", "prime": "en_overseer"}.get(L.who, "")
		if L.who == "sq":
			sheet = Art.look_sheet(L.s)
		if Art.meta.has(sheet):
			var fh: float = Art.meta[sheet].frame[1]
			var sc := minf(3.0, (r.size.y - 14) / fh)
			Art.draw_char(self, sheet, "idle", (t / 14) % 2, Vector2(r.get_center().x, r.end.y - 6), 1, false, 0, 1.0, 0, L.who == "sq", sc)
		draw_rect(r, L.col, false, 2)
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 540), Color("0c1013"))
		for y in range(0, 540, 3):
			draw_rect(Rect2(0, y, 960, 1), Color(1, 1, 1, 0.02))
		Art.text(self, "RADIO", Vector2(40, 40), 16, Color("62d26f") if t % 50 < 35 else Color("2c5a33"), HORIZONTAL_ALIGNMENT_LEFT, 2)
		Art.text(self, "CLICK TO GO ON   ESC SKIPS", Vector2(480, 40), 8, Color("6c7480"), HORIZONTAL_ALIGNMENT_CENTER)
		# earlier lines stay up the screen, faded
		var y := 90.0
		for k in mini(i, lines.size()) if i >= 0 else 0:
			var P: Dictionary = lines[k]
			Art.text(self, P.name + ":", Vector2(70, y), 8, P.col.darkened(0.3))
			Art.text(self, P.text, Vector2(70, y + 16), 16, Color(0.6, 0.6, 0.6), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
			y += 44
		if i < 0 or i >= lines.size():
			return
		var L: Dictionary = lines[i]
		var box := Rect2(40, 330, 880, 170)
		draw_rect(box, Color(0.05, 0.035, 0.03))
		draw_rect(box.grow(-2), Color("161b20"))
		draw_rect(box, L.col, false, 2)
		portrait(L, Rect2(56, 346, 138, 138))
		Art.text(self, L.name, Vector2(214, 370), 16, L.col, HORIZONTAL_ALIGNMENT_LEFT, 2)
		Art.text(self, L.role, Vector2(214, 388), 8, Color("9aa2ae"))
		var ty := 420.0
		for ln in CardView.wrap_text(L.text.substr(0, shown), 680, 16):
			Art.text(self, ln, Vector2(214, ty), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
			ty += 18
		if shown >= L.text.length() and t % 40 < 26:
			Art.text(self, ">>", Vector2(896, 488), 8, L.col, HORIZONTAL_ALIGNMENT_RIGHT)
		Art.text(self, "%d / %d" % [i + 1, lines.size()], Vector2(896, 352), 8, Color("6c7480"), HORIZONTAL_ALIGNMENT_RIGHT)

class EndingScreen extends Control:
	## S5: the war is won. The company's service records and the Memorial, then a Second Tour
	## with one veteran of your choice.
	signal tour(vet: Dictionary)
	signal title
	var t := 0
	var pick := -1
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		build()
	func build() -> void:
		for c in get_children():
			c.queue_free()
		var go = load("res://scripts/hud.gd").PixButton.new()
		go.text = "SECOND TOUR"
		go.sub = "WITH %s" % Run.company()[pick].def.name if pick >= 0 else "PICK A VETERAN TO BRING"
		go.color = Color("ffd23a")
		go.size = Vector2(260, 40)
		go.position = Vector2(250, 486)
		go.disabled = pick < 0
		go.pressed.connect(func(): Sfx.play("start"); tour.emit(Run.company()[pick]))
		add_child(go)
		var tt = load("res://scripts/hud.gd").PixButton.new()
		tt.text = "TITLE"
		tt.color = Color("9aa2ae")
		tt.size = Vector2(160, 40)
		tt.position = Vector2(530, 486)
		tt.pressed.connect(func(): Sfx.play("click"); title.emit())
		add_child(tt)
	func card(i: int) -> Rect2:
		return Rect2(24 + (i % 5) * 132, 150 + (i / 5) * 150, 124, 142)
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			for i in Run.company().size():
				if card(i).has_point(ev.position):
					accept_event()
					pick = i
					Sfx.play("select")
					build()
					return
	func _process(_d: float) -> void:
		t += 1
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 540), Color("0c1013"))
		var g := 0.6 + 0.4 * sin(t / 20.0)
		Art.text(self, "THE GATE IS SHUT", Vector2(480, 60), 32, Color(1.0, 0.82 * g + 0.1, 0.23), HORIZONTAL_ALIGNMENT_CENTER, 3)
		var tour := int(Run.camp.get("tour", 1))
		var hrs := float(Run.camp.get("secs", 0.0)) / 3600.0
		Art.text(self, "%sTHE WAR IS WON IN %d OPS, %.1f HOURS. IRON COMPANY GOES HOME." % ["TOUR %d.  " % tour if tour > 1 else "", int(Run.camp.ops), hrs], Vector2(480, 92), 8, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER)
		Art.text(self, "SERVICE RECORDS", Vector2(24, 136), 8, Color("62d26f"))
		Art.text(self, "Click a veteran to bring them on a Second Tour: a new war, harder sectors.", Vector2(680, 136), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_RIGHT, 2, true)
		var co := Run.company()
		for i in co.size():
			var s: Dictionary = co[i]
			var r := card(i)
			var on := i == pick
			draw_rect(r, Color(0.05, 0.035, 0.03))
			draw_rect(r.grow(-1), Color("2a2a1e") if on else Color("1a1e22"))
			draw_rect(r, Color("ffd23a") if on else Color("3a4048"), false, 2)
			Art.draw_char(self, Art.look_sheet(s), "cheer" if on else "idle", (t / 10 + i) % (2 if on else 4), Vector2(r.get_center().x, r.position.y + 58), 1, false, 0, 1.0, 0, not on, 1.3)
			Art.text(self, "%s %s" % [Run.rank_name(s), s.def.name], Vector2(r.get_center().x, r.position.y + 76), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
			Art.text(self, s.def.cls, Vector2(r.get_center().x, r.position.y + 92), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
			var sv := Run.svc(s)
			Art.text(self, "%d OPS  %d KILLS" % [int(sv.ops), int(sv.kills)], Vector2(r.get_center().x, r.position.y + 110), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
			if sv.medals.size():
				Art.text(self, "%d MEDAL%s" % [sv.medals.size(), "" if sv.medals.size() == 1 else "S"], Vector2(r.get_center().x, r.position.y + 128), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
		# the Memorial
		var mx := 696.0
		draw_rect(Rect2(mx, 150, 240, 292), Color(0.05, 0.035, 0.03))
		draw_rect(Rect2(mx, 150, 240, 292), Color("9aa2ae"), false, 2)
		Art.text(self, "THE MEMORIAL", Vector2(mx + 120, 170), 8, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER)
		var mem: Array = Run.meta.get("memorial", [])
		if mem.is_empty():
			Art.text(self, "Nobody fell. Everyone came home.", Vector2(mx + 120, 200), 16, Color("62d26f"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
		for k in mini(mem.size(), 14):
			var m: Dictionary = mem[k]
			var rk: String = Data.RANKS[int(m.get("rank", 0))].short if m.has("rank") else ""
			Art.text(self, "%s %s, %s" % [rk, m.name, m.cls], Vector2(mx + 12, 196 + k * 17), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		if mem.size() > 14:
			Art.text(self, "AND %d MORE" % (mem.size() - 14), Vector2(mx + 120, 436), 8, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER)

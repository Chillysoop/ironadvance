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

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
	elif Run.sector_held(sc.id):
		go.text = "PATROL"
		go.sub = "HALF PAY, NOBODY DIES"
		go.color = Color("62d26f")
		go.pressed.connect(func(): Sfx.play("start"); attack.emit(sc, true))
	else:
		go.text = "NOT REACHABLE YET"
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

func _gui_input(ev: InputEvent) -> void:
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
	Art.text(self, "ACT %s  %s" % [A.roman, A.name], Vector2(190, 34), 16, Color("ff7a3d"), HORIZONTAL_ALIGNMENT_LEFT, 2)
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
	rows.append(["JOB", "STRONGHOLD" if sc.get("stronghold", false) else "PUSH TO THE BOSS"])
	rows.append(["BIOME", bm.name])
	var a: Dictionary = Run.act()
	rows.append(["ENEMY", ["JACKALS", "JACKALS + VHARR", "VHARR"][int(a.tier)] + (" + BREACH" if float(a.breach) >= 0.5 else "")])
	for r in rows:
		Art.text(self, r[0], Vector2(x, y), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		Art.text(self, r[1], Vector2(SIDE.end.x - 12, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_RIGHT, 2, true)
		y += 18
	y += 4
	if sc.has("hold"):
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
		set_anchors_preset(Control.PRESET_FULL_RECT)
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
			Art.text(self, "WAR WON" if h.get("done", false) else "ACT %s" % A.roman, Vector2(cr.position.x + 16, cr.position.y + 58), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2)
			Art.text(self, A.name, Vector2(cr.position.x + 16, cr.position.y + 80), 8, Color("ff7a3d"))
			var mins := int(float(h.secs) / 60.0)
			Art.text(self, "%d OPS   %dH %02dM" % [int(h.ops), mins / 60, mins % 60], Vector2(cr.position.x + 16, cr.position.y + 104), 8, Color("e8dcc2"))
			var names: Array = h.get("names", [])
			for j in names.size():
				Art.text(self, names[j], Vector2(cr.position.x + 16 + (j % 2) * 120, cr.position.y + 130 + (j / 2) * 18), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)

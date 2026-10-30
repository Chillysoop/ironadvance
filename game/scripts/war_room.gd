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
var book_open := false     # W12: the War Book overlay (the act's challenges)
var fort_btn: Control = null
var book_tab := 0          # 0 challenges, 1 the war journal (W8)
var book_scroll := 0
var tok := Vector2.ZERO    # W10: the company token on the map
var tok_path: Array = []   # points still to drive through before the attack goes in
var tok_go := Callable()
var msg := ""
var note := ""   # a squad swap on the company overlay, said out loud

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for sc in Run.act().sectors:
		if Run.sector_open(sc) and (sel == "" or sc.get("stronghold", false)):
			sel = sc.id
	var last := Run.sector(str(Run.camp.get("last", "")))
	tok = node_pos(last) if not last.is_empty() and Run.sector_held(last.id) else lz_pos()
	build()

func drive_to(sc: Dictionary, then: Callable) -> void:
	## W10: the company token drives the roads (through ground you hold) to the sector, then the op starts.
	var adj := {}
	for x in Run.act().sectors:
		for l in x.links:
			adj[x.id] = adj.get(x.id, []) + [l]
			adj[l] = adj.get(l, []) + [x.id]
	var start := "lz"
	for x in Run.act().sectors:
		if node_pos(x).distance_to(tok) < 2:
			start = x.id
	var prev := {start: ""}
	var q := [start]
	while q.size():
		var c: String = q.pop_front()
		if c == sc.id:
			break
		for n in adj.get(c, []):
			if prev.has(n) or (n != sc.id and not Run.sector_held(n)):
				continue
			prev[n] = c
			q.append(n)
	var path: Array = []
	var c2: String = sc.id if prev.has(sc.id) else ""
	while c2 != "":
		path.push_front(link_pos(c2))
		c2 = prev[c2]
	tok_path = path if path.size() else [node_pos(sc)]
	tok_go = then
	if go_btn != null:
		go_btn.disabled = true

func build() -> void:
	for c in get_children():
		c.queue_free()
	var bk := HudScript.PixButton.new()
	bk.text = "<< HQ"
	bk.color = Color("9aa2ae")
	bk.small = true
	bk.size = Vector2(90, 32)
	bk.position = Vector2(16, 494)
	bk.pressed.connect(func(): Sfx.play("click"); back.emit())
	add_child(bk)
	var th := HudScript.PixButton.new()
	th.small = true
	th.size = Vector2(150, 32)
	th.position = Vector2(114, 494)
	th.color = Color("ff7a3d") if Run.threat > 0 else Color("9aa2ae")
	th.text = "THREAT %d" % Run.threat
	th.sub = "+%d%% PAY" % roundi(Run.threat * Data.CAMP_THREAT_PAY * 100) if Run.threat > 0 else "OPTIONAL"
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
	cb.sub = "" if company_open else "SQUAD %d OF %d" % [Run.soldiers.size(), Run.company().size()]
	cb.pressed.connect(func(): Sfx.play("click"); company_open = not company_open; book_open = false; msg = ""; note = ""; build())
	add_child(cb)
	var wb := HudScript.PixButton.new()
	wb.small = true
	wb.size = Vector2(120, 32)
	wb.position = Vector2(272, 494)
	wb.color = Color("ffb23e")
	wb.text = "DONE" if book_open else "WAR BOOK"
	wb.sub = "" if book_open else "%d/3 DONE" % challenges_done()
	wb.pressed.connect(func(): Sfx.play("click"); book_open = not book_open; company_open = false; build())
	add_child(wb)
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
		go.pressed.connect(func(): Sfx.play("start"); drive_to(sc, func(): attack.emit(sc, false)))
	elif Run.sector_held(sc.id) and Run.bonus_at(sc) != "":
		go.text = "BONUS OP"
		go.sub = {"salvage": "PAYS %d SALVAGE" % Data.BONUS_SALVAGE, "defector": "PAYS A RECRUIT", "crash": "LAB KILLS COUNT DOUBLE"}.get(Data.BONUS_OPS[Run.bonus_at(sc)].get("pay", ""), "PAYS EPIC GEAR")
		go.color = Color("c47bff")
		go.pressed.connect(func(): Sfx.play("start"); drive_to(sc, func(): attack.emit(sc, false)))
	elif Run.sector_held(sc.id):
		go.text = "PATROL"
		go.sub = "HALF PAY, NOBODY DIES"
		go.color = Color("62d26f")
		go.pressed.connect(func(): Sfx.play("start"); drive_to(sc, func(): attack.emit(sc, true)))
	else:
		go.text = "NOT REACHABLE YET"
		go.disabled = true
	if Run.soldiers.is_empty():
		go.disabled = true
	add_child(go)
	go_btn = go
	fort_btn = null
	if not sc.is_empty() and Run.sector_held(sc.id) and sc.id != "lz" and not sc.get("stronghold", false):
		# W4: fortify a held sector with scrip
		go.size = Vector2(160, 40)
		if go.sub == "HALF PAY, NOBODY DIES":
			go.sub = "HALF PAY, SAFE"
		var fb := HudScript.PixButton.new()
		fb.small = true
		fb.size = Vector2(84, 40)
		fb.position = Vector2(566, 490)
		fb.color = Color("c9a46a")
		var f := Run.fort(Run.sec_key(sc.id))
		fb.text = "FORTIFY"
		fb.sub = "MAX" if f >= Data.FORTIFY_COST.size() else "%d SCRIP" % Data.FORTIFY_COST[f]
		fb.disabled = Run.fortify_block(sc) != ""
		fb.pressed.connect(func():
			if Run.fortify(sc):
				Sfx.play("levelup")
				build())
		add_child(fb)
		fort_btn = fb

func challenges_done() -> int:
	var a := int(Run.camp.get("act", 0))
	return Data.ACT_CHALLENGES[a].filter(func(id): return Run.camp.get("chal", {}).has("%d:%s" % [a, id])).size()

func node_pos(sc: Dictionary) -> Vector2:
	return Vector2(sc.at[0], sc.at[1])

func lz_pos() -> Vector2:
	var a: Array = Run.act().lz.at
	return Vector2(a[0], a[1])

func link_pos(id: String) -> Vector2:
	return lz_pos() if id == "lz" else node_pos(Run.sector(id))

func wing_rect(i: int) -> Rect2:
	## T2: the SQUAD B box in a bench card's corner.
	var r := card_rect(i)
	return Rect2(r.end.x - 30, r.position.y + 6, 24, 18)

func card_rect(i: int) -> Rect2:
	## Roster card i on the company overlay: two rows of five over the map.
	return Rect2(MAP.position.x + 8 + (i % 5) * 130, MAP.position.y + 36 + (i / 5) * 176, 124, 168)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and company_open:
		var co := Run.company()
		for i in co.size():
			if Run.pincer_ahead() and not Run.soldiers.has(co[i]) and wing_rect(i).has_point(ev.position):
				accept_event()
				msg = Run.toggle_wing(co[i])  # T2: squad B for the pincer
				Sfx.play("deny" if msg != "" else "select")
				note = ""
				build()
				return
			if card_rect(i).has_point(ev.position):
				accept_event()
				var was: Array = Run.soldiers.duplicate()
				msg = Run.toggle_squad(co[i])
				Sfx.play("deny" if msg != "" else "select")
				note = ""
				var out: Array = was.filter(func(x): return not Run.soldiers.has(x))
				if msg == "" and out.size() and Run.soldiers.has(co[i]):
					# one of each class: say who stepped aside, or a swap looks like a misclick
					note = "%s TAKES %s'S %s SLOT." % [co[i].def.name, out[0].def.name, str(out[0].def.cls).to_upper()]
				build()
				return
		return
	if book_open:
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_LEFT:
				for i in 2:
					if book_tab_rect(i).has_point(ev.position):
						accept_event()
						book_tab = i
						book_scroll = 0
						Sfx.play("click")
			elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				book_scroll = mini(book_scroll + 1, maxi(0, Run.camp.get("journal", []).size() - 9))
			elif ev.button_index == MOUSE_BUTTON_WHEEL_UP:
				book_scroll = maxi(0, book_scroll - 1)
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
	if tok_path.size():
		tok = tok.move_toward(tok_path[0], 5.0)
		if tok.distance_to(tok_path[0]) < 0.5:
			tok_path.pop_front()
			if tok_path.is_empty() and tok_go.is_valid():
				var f := tok_go
				tok_go = Callable()
				f.call()
				return
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
		if Run.sector_held(sc.id):
			draw_circle(node_pos(sc), 70, Color(0.38, 0.82, 0.44, 0.13))  # W10: held ground in the company's colour
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
	# W10: smoke still rising over ground you fought for and haven't taken yet
	for sc in A.sectors:
		if Run.camp.get("tried", []).has(Run.sec_key(sc.id)) and not Run.sector_held(sc.id):
			for k in 4:
				var ph := fmod(t / 70.0 + k * 0.25, 1.0)
				var sp := node_pos(sc) + Vector2(10 + sin(ph * 6.0 + k) * 6, -14 - ph * 46)
				draw_circle(sp, 4 + ph * 8, Color(0.55, 0.55, 0.58, 0.32 * (1.0 - ph)))
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
		var fr := Run.fort(Run.sec_key(sc.id)) if st == "held" else 0
		if fr > 0:
			# W4: sandbags along the bottom and a flag per rank
			for k in 4:
				draw_rect(Rect2(r.position.x - 4 + k * (sz + 8) / 4.0, r.end.y - 3, (sz + 8) / 4.0 - 1, 6), Color("c9a46a"))
				draw_rect(Rect2(r.position.x - 4 + k * (sz + 8) / 4.0, r.end.y - 3, (sz + 8) / 4.0 - 1, 6), Color(0.05, 0.035, 0.03), false, 1)
			for k in fr:
				var fx := r.position.x + 2 + k * 8
				draw_line(Vector2(fx, r.position.y), Vector2(fx, r.position.y - 12), Color(0.05, 0.035, 0.03), 2)
				draw_rect(Rect2(fx + 1, r.position.y - 12, 6, 4), Color("62d26f"))
		if Run.bonus_at(sc) != "":
			# P2: a bonus op waiting on this sector
			var bp := p + Vector2(sz / 2 + 4, -sz / 2 - 4)
			draw_circle(bp, 9 + (1 if (t / 15) % 2 == 0 else 0), Color(0.05, 0.035, 0.03))
			draw_circle(bp, 7 + (1 if (t / 15) % 2 == 0 else 0), Color("c47bff"))
			Art.text(self, "!", bp + Vector2(0, 4), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		var tag: String = "FORT" if big else sc.id.to_upper()
		Art.text(self, tag, p + Vector2(0, 5), 8, Color(0.05, 0.035, 0.03) if st != "locked" or big else Color("c9ccd1"), HORIZONTAL_ALIGNMENT_CENTER, 0)
		# a soft plate under the name and perk, so a link running past never cuts through the words
		var what_w := 0.0
		if sc.has("perk") or sc.has("hold"):
			what_w = Art.text_width(Data.SECTOR_PERKS[sc.perk].name if sc.has("perk") else hold_text(Run.hold_pay(sc, Run.fort(Run.sec_key(sc.id)))), 16, true)
		var pw := maxf(Art.text_width(sc.name, 8), what_w) + 8
		draw_rect(Rect2(p.x - pw / 2, p.y + sz / 2 + 4, pw, 32.0 if what_w > 0 else 14.0), Color(0.06, 0.1, 0.12, 0.55))
		Art.text(self, sc.name, p + Vector2(0, sz / 2 + 14), 8, Color.WHITE if st != "locked" else Color("8a929c"), HORIZONTAL_ALIGNMENT_CENTER)
		if sc.has("perk") or sc.has("hold"):
			var what: String = Data.SECTOR_PERKS[sc.perk].name if sc.has("perk") else hold_text(Run.hold_pay(sc, Run.fort(Run.sec_key(sc.id))))
			Art.text(self, what, p + Vector2(0, sz / 2 + 30), 16, Color("62d26f") if st == "held" else Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
	var need := int(A.need)
	# C2: say what taking them unlocks
	var fort: Array = A.sectors.filter(func(x): return x.get("stronghold", false))
	var lx := MAP.position.x + 12
	for lg in [["HELD", Color("62d26f")], ["OPEN", Color("ffd23a")], ["NOT YET", Color("4a525c")], ["STRONGHOLD", Color("ff4d3d")]]:
		draw_rect(Rect2(lx, MAP.position.y + 10, 10, 10), lg[1])
		Art.text(self, lg[0], Vector2(lx + 14, MAP.position.y + 20), 8, Color("9aa2ae"))
		lx += Art.text_width(lg[0], 8) + 30
	var opens := ("  %s OPENS AT %d" % [fort[0].name, need]) if fort.size() and Run.held_count() < need else ""
	var took := "%d OF %d TAKEN" % [mini(Run.held_count(), need), need]
	if Art.text_width(took + opens, 8) > MAP.end.x - 12 - (lx - 10):
		opens = "  FORT OPENS AT %d" % need  # a long stronghold name would run into the legend; the map tags it FORT
	Art.text(self, took + opens, Vector2(MAP.end.x - 12, MAP.position.y + 20), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_RIGHT)
	draw_token()
	draw_side()
	if company_open:
		draw_company()
	elif book_open:
		draw_book()

func draw_company() -> void:
	## C1: the whole company with each soldier's fit for the picked sector. Click to put them in or out.
	draw_rect(MAP, Color(0.04, 0.05, 0.06, 0.97))
	draw_rect(MAP, Color("53d4e2"), false, 2)
	var sc := Run.sector(sel)
	Art.text(self, "THE COMPANY  %d OF %d" % [Run.company().size(), Data.COMPANY_MAX], Vector2(MAP.position.x + 12, MAP.position.y + 22), 8, Color("53d4e2"))
	var tip := msg if msg != "" else note if note != "" else ("Click to put a soldier in or out. Tick B on the bench to pick squad B for the pincer." if Run.pincer_ahead() else "Click to put a soldier in or out. One of each class per squad, up to %d." % Data.SQUAD_MAX)
	var wb: Array = Run.pick_wing_b().map(func(k): return Run.roster[k]) if Run.pincer_ahead() else []
	Art.text(self, tip, Vector2(MAP.end.x - 12, MAP.position.y + 22), 16, Color("ff7a5a") if msg != "" else Color("ffd23a") if note != "" else Color("9aa2ae"), HORIZONTAL_ALIGNMENT_RIGHT, 2, true)
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
		var b_side := wb.has(s)
		Art.text(self, ("SQUAD A" if wb.size() else "IN SQUAD") if on else "SQUAD B" if b_side else "BENCH", Vector2(r.end.x - 6, r.end.y - 8), 8, Color("62d26f") if on else Color("53d4e2") if b_side else Color("6c7480"), HORIZONTAL_ALIGNMENT_RIGHT)
		if wb.size() and not on:
			# T2: tick B to send them in with squad B; unticked, the best four on the bench go
			var br := wing_rect(i)
			var mk: bool = s.get("wing", "") == "b"
			draw_rect(br, Color("1e4a54") if mk else Color(0.05, 0.035, 0.03))
			draw_rect(br, Color("53d4e2"), false, 1)
			Art.text(self, "B", br.get_center() + Vector2(0, 5), 8, Color.WHITE if mk else Color("53d4e2"), HORIZONTAL_ALIGNMENT_CENTER)
		var y := r.position.y + 82
		Art.text(self, "%s %s" % [Run.rank_name(s), s.def.name], Vector2(r.position.x + 8, y), 8, Color.WHITE)
		Art.text(self, "%s  LV%d" % [s.def.cls, s.lvl], Vector2(r.position.x + 8, y + 16), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		var sv := Run.svc(s)
		Art.text(self, "%d OP%s  %d KILL%s" % [int(sv.ops), "" if int(sv.ops) == 1 else "S", int(sv.kills), "" if int(sv.kills) == 1 else "S"], Vector2(r.position.x + 8, y + 32), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		if sv.medals.size():
			Art.text(self, "%d MEDAL%s" % [sv.medals.size(), "" if sv.medals.size() == 1 else "S"], Vector2(r.position.x + 8, y + 48), 16, Color("ffd23a"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		if not sc.is_empty():
			var f := Run.fit(s, sc.biome)
			# a row above IN SQUAD / BENCH, so "GREAT" doesn't read as part of "GREAT IN SQUAD"
			Art.text(self, "FIT " + f.to_upper(), Vector2(r.position.x + 8, r.end.y - 22), 8, {"great": Color("62d26f"), "ok": Color("e8dcc2"), "rough": Color("ff7a5a")}[f])

func draw_token() -> void:
	## W10: the company's truck on the map.
	var p := tok + Vector2(0, -NODE / 2 - 10 if tok_path.is_empty() else 0)
	var bob := 1.0 if tok_path.size() and (t / 4) % 2 == 0 else 0.0
	draw_rect(Rect2(p + Vector2(-11, -7 + bob), Vector2(22, 10)), Color(0.05, 0.035, 0.03))
	draw_rect(Rect2(p + Vector2(-10, -6 + bob), Vector2(14, 8)), Color("4e5a30"))
	draw_rect(Rect2(p + Vector2(4, -4 + bob), Vector2(6, 6)), Color("6a7a40"))
	draw_circle(p + Vector2(-6, 4), 3, Color(0.05, 0.035, 0.03))
	draw_circle(p + Vector2(6, 4), 3, Color(0.05, 0.035, 0.03))
	draw_line(p + Vector2(-8, -6 + bob), p + Vector2(-8, -16 + bob), Color(0.05, 0.035, 0.03), 1)
	draw_rect(Rect2(p + Vector2(-7, -16 + bob), Vector2(7, 4)), Color("62d26f"))

func book_tab_rect(i: int) -> Rect2:
	return Rect2(MAP.position.x + 12 + i * 150, MAP.position.y + 8, 140, 24)

func draw_book() -> void:
	## W12: the War Book. This act's three challenges, each paid once; W8: the war journal.
	draw_rect(MAP, Color(0.04, 0.05, 0.06, 0.97))
	draw_rect(MAP, Color("ffb23e"), false, 2)
	for i in 2:
		var r := book_tab_rect(i)
		draw_rect(r, Color("b8741c") if book_tab == i else Color("1e2126"))
		draw_rect(r, Color("ffb23e"), false, 1)
		Art.text(self, ["CHALLENGES", "JOURNAL"][i], r.get_center() + Vector2(0, 5), 8, Color.WHITE if book_tab == i else Color("ffb23e"), HORIZONTAL_ALIGNMENT_CENTER)
	if book_tab == 1:
		draw_journal()
		return
	var a := int(Run.camp.get("act", 0))
	Art.text(self, "Act %s. Optional, each pays %d salvage, %d bio and a Legendary item once." % [Run.act().roman, Data.CHALLENGE_PAY.salvage, Data.CHALLENGE_PAY.bio], Vector2(MAP.end.x - 12, MAP.position.y + 25), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_RIGHT, 2, true)
	var ids: Array = Data.ACT_CHALLENGES[a]
	for i in ids.size():
		var id: String = ids[i]
		var done: bool = Run.camp.get("chal", {}).has("%d:%s" % [a, id])
		var r := Rect2(MAP.position.x + 12, MAP.position.y + 40 + i * 70, MAP.size.x - 24, 62)
		draw_rect(r, Color("1e2a22") if done else Color("1e2126"))
		draw_rect(r, Color("62d26f") if done else Color("3a4048"), false, 2)
		draw_rect(Rect2(r.position.x + 14, r.position.y + 18, 24, 24), Color(0.05, 0.035, 0.03))
		if done:
			draw_line(Vector2(r.position.x + 18, r.position.y + 30), Vector2(r.position.x + 24, r.position.y + 37), Color("62d26f"), 3)
			draw_line(Vector2(r.position.x + 24, r.position.y + 37), Vector2(r.position.x + 35, r.position.y + 22), Color("62d26f"), 3)
		Art.text(self, Data.CHALLENGES[id].name, Vector2(r.position.x + 52, r.position.y + 26), 8, Color("62d26f") if done else Color("ffd23a"))
		Art.text(self, Run.challenge_text(id), Vector2(r.position.x + 52, r.position.y + 48), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		Art.text(self, "DONE" if done else "OPEN", Vector2(r.end.x - 14, r.position.y + 26), 8, Color("62d26f") if done else Color("6c7480"), HORIZONTAL_ALIGNMENT_RIGHT)

static func journal_line(e: Dictionary) -> Array:
	## W8: one op as two lines: where and how it went, then who went and what it cost.
	var what: String = "PATROL" if e.patrol else e.bonus if e.bonus != "" else "STRONGHOLD" if e.stronghold else Data.JOBS.get(e.job, {}).get("name", "PUSH")
	var head := "OP %d  ACT %s  %s  %s  %s" % [int(e.n), Data.ACTS[clampi(int(e.act), 0, Data.ACTS.size() - 1)].roman, e.sec, what, "WON" if e.won else "FAILED"]
	var tail := "%s.  %d kills, %d rounds" % [", ".join(e.squad).capitalize(), int(e.kills), int(e.rounds)]
	if int(e.medals) > 0:
		tail += ", %d medal%s" % [int(e.medals), "" if int(e.medals) == 1 else "s"]
	if str(e.get("nemesis", "")) != "":
		tail += ". Met %s" % str(e.nemesis).capitalize()
	if e.fallen.size():
		tail += ". Fell: " + ", ".join(e.fallen).capitalize()
	return [head, tail + "."]

func draw_journal() -> void:
	var j: Array = Run.camp.get("journal", [])
	Art.text(self, "Every op of the war, newest first. Scroll for more.", Vector2(MAP.end.x - 12, MAP.position.y + 25), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_RIGHT, 2, true)
	if j.is_empty():
		Art.text(self, "No ops yet. The first one goes in the book.", Vector2(MAP.position.x + 20, MAP.position.y + 64), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		return
	for i in mini(9, j.size() - book_scroll):
		var e: Dictionary = j[j.size() - 1 - book_scroll - i]
		var y := MAP.position.y + 54 + i * 38
		var ln := journal_line(e)
		Art.text(self, ln[0], Vector2(MAP.position.x + 16, y), 8, Color("62d26f") if e.won else Color("ff7a5a"))
		Art.text(self, ln[1], Vector2(MAP.position.x + 16, y + 17), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)

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
	var story := ""
	if sc.get("story", "") == "varga" and not Run.camp.has("varga"):
		story = "STORY OP: VARGA'S LAST STAND|Save him and he joins for good."
	elif sc.get("finale", false) and st != "held":
		var wb: Array = Run.pick_wing_b().map(func(i): return Run.roster[i].def.name)
		if Run.company().size() >= Data.PINCER_COMPANY and wb.size() >= Data.SQUAD_MAX:
			story = "PINCER: TWO SQUADS|Squad B (%s) lands on the far side. The four best on the bench go." % ", ".join(wb)
		else:
			story = "PINCER AT %d|A company of %d storms it as two squads. You have %d." % [Data.PINCER_COMPANY, Data.PINCER_COMPANY, Run.company().size()]
	if story != "":
		# W9/W13: say what makes this op different before it's picked
		var sp := story.split("|")
		Art.text(self, sp[0], Vector2(x, y), 8, Color("ffd23a") if sc.has("story") else Color("53d4e2"))
		y += 6
		for line in CardView.wrap_text(sp[1], SIDE.size.x - 24, 16):
			y += 16
			Art.text(self, line, Vector2(x, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		y += 14  # tighter than the blocks below, so the FIT list still clears the income line
	if Run.bonus_at(sc) != "":
		var B: Dictionary = Data.BONUS_OPS[Run.bonus_at(sc)]
		Art.text(self, "BONUS: " + B.name, Vector2(x, y), 8, Color("c47bff"))
		y += 6
		for line in CardView.wrap_text(Run.bonus_text(Run.bonus_at(sc)) + " %d ops left." % int(Run.camp.bonus.left), SIDE.size.x - 24, 16):
			y += 16
			Art.text(self, line, Vector2(x, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		y += 18
	elif sc.has("hold"):
		var f := Run.fort(Run.sec_key(sc.id))
		Art.text(self, "HOLDING IT" + ("  FORTIFIED %d/3" % f if f > 0 else ""), Vector2(x, y), 8, Color("62d26f"))
		y += 6
		var nxt := "" if f >= 3 or st != "held" else " Fortified: " + hold_text(Run.hold_pay(sc, f + 1)).to_lower().replace(" per op", "") + "."
		for line in CardView.wrap_text(hold_text(Run.hold_pay(sc, f)) + " for the rest of the war." + nxt, SIDE.size.x - 24, 16):
			y += 16
			Art.text(self, line, Vector2(x, y), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		y += 18
	elif sc.has("perk"):
		var P: Dictionary = Data.SECTOR_PERKS[sc.perk]
		var f := Run.fort(Run.sec_key(sc.id))
		Art.text(self, ("FORTIFIED %d/3: " % f if f > 0 else "HOLDING IT: ") + P.name, Vector2(x, y), 8, Color("62d26f"))
		y += 6
		var ptx: String = P.text if f == 0 else P.text.replace(" this act", " for the rest of the war")
		for k in range(1, f):
			ptx += " " + Data.FORTIFY_PERK[sc.perk][k]
		if st == "held" and f < 3:
			ptx += " Fortify: " + Data.FORTIFY_PERK[sc.perk][f].to_lower()
		for line in CardView.wrap_text(ptx, SIDE.size.x - 24, 16):
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
	y += 18  # room for the first soldier's head under the FIT line
	var al: Array = Run.soldiers.filter(func(s): return s.alive)
	for j in al.size():
		var so: Dictionary = al[j]
		var f := Run.fit(so, sc.biome)
		var row := y + j * 26
		Art.draw_char(self, Art.look_sheet(so), "idle", (t / 12 + j) % 4, Vector2(x + 12, row + 22), 1, false, 0, 1.0, 0, true, 0.8)
		Art.text(self, so.def.name, Vector2(x + 40, row + 16), 8, Color.WHITE)  # clear of the rifle
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
			Art.text(self, str(h.get("act_name", A.name)), Vector2(cr.position.x + 16, cr.position.y + 80), 8, Color("ff7a3d"))
			var mins := int(float(h.secs) / 60.0)
			Art.text(self, "%d OP%s   %dH %02dM" % [int(h.ops), "" if int(h.ops) == 1 else "S", mins / 60, mins % 60], Vector2(cr.position.x + 16, cr.position.y + 104), 8, Color("e8dcc2"))
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
		return Rect2(120 + i * 250, 236, 220, 120)  # starts under a field call in the top right (it ends at y 224)
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
		var real: int = int(s.get("promo", 1)) - int(s.get("field", 0))
		var rk: int = (Run.rank(s) - real + 1 if real > 0 else Run.rank(s)) if promo else Run.rank(s)
		var line := "%s is now a %s. Pick what the new stripes bring." % [s.def.name, Data.RANKS[clampi(rk, 0, Data.RANKS.size() - 1)].name.capitalize()] if promo else "%s trained on the bench and reached level %d. Pick it like a level-up." % [s.def.name, s.lvl - int(s.get("train", 1)) + 1]
		if promo and real <= 0:
			line = "%s was the MVP of the act. A field promotion: pick what it brings." % s.def.name
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
			get_viewport().set_input_as_handled()
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
	var show_j := false   # W8: the war journal instead of the service records
	var jscroll := 0
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
		var jb = load("res://scripts/hud.gd").PixButton.new()
		jb.text = "RECORDS" if show_j else "JOURNAL"
		jb.small = true
		jb.color = Color("ffb23e")
		jb.size = Vector2(150, 40)
		jb.position = Vector2(710, 486)
		jb.pressed.connect(func(): Sfx.play("click"); show_j = not show_j; jscroll = 0; build())
		add_child(jb)
	func card(i: int) -> Rect2:
		return Rect2(24 + (i % 5) * 132, 150 + (i / 5) * 150, 124, 142)
	func _gui_input(ev: InputEvent) -> void:
		if show_j:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				jscroll = mini(jscroll + 1, maxi(0, Run.camp.get("journal", []).size() - 7))
			elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_UP:
				jscroll = maxi(0, jscroll - 1)
			return
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
		var co := Run.company()
		if show_j:
			Art.text(self, "WAR JOURNAL", Vector2(24, 136), 8, Color("ffb23e"))
			Art.text(self, "%d ops, newest first. Scroll for more." % Run.camp.get("journal", []).size(), Vector2(680, 136), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_RIGHT, 2, true)
			var j: Array = Run.camp.get("journal", [])
			for i in mini(7, j.size() - jscroll):
				var e: Dictionary = j[j.size() - 1 - jscroll - i]
				var ln: Array = load("res://scripts/war_room.gd").journal_line(e)
				Art.text(self, ln[0], Vector2(24, 166 + i * 40), 8, Color("62d26f") if e.won else Color("ff7a5a"))
				Art.text(self, ln[1], Vector2(24, 183 + i * 40), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
			co = []
		else:
			Art.text(self, "SERVICE RECORDS", Vector2(24, 136), 8, Color("62d26f"))
			Art.text(self, "Pick a veteran for a Second Tour: new fronts, harder sectors.", Vector2(680, 136), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_RIGHT, 2, true)
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
			Art.text(self, "%d OP%s  %d KILL%s" % [int(sv.ops), "" if int(sv.ops) == 1 else "S", int(sv.kills), "" if int(sv.kills) == 1 else "S"], Vector2(r.get_center().x, r.position.y + 110), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_CENTER, 2, true)
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

# ================================================================ W2: the act-end ceremony
class ActEndScreen extends Control:
	## A stronghold fell: what the act took, its MVP, and the next front rolling out on the map.
	signal done
	var act_i := 0
	var mvp := {}
	var t := 0
	const PREV := Rect2(586, 150, 350, 220)
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var go = load("res://scripts/hud.gd").PixButton.new()
		var nx: Dictionary = Run.act(act_i + 1)
		go.text = "ON TO ACT %s" % nx.roman
		go.color = Color("ffd23a")
		go.size = Vector2(260, 40)
		go.position = Vector2(350, 486)
		go.pressed.connect(func(): Sfx.play("start"); done.emit())
		add_child(go)
		Sfx.play("levelup")
	func _process(_d: float) -> void:
		t += 1
		queue_redraw()
	func mp(at: Array) -> Vector2:
		## A War Room map position, shrunk into the preview box.
		return PREV.position + Vector2((float(at[0]) - 16.0) / 664.0 * PREV.size.x, (float(at[1]) - 80.0) / 396.0 * PREV.size.y)
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 540), Color("0c1013"))
		var A: Dictionary = Run.act(act_i)
		var g := 0.7 + 0.3 * sin(t / 18.0)
		Art.text(self, "ACT %s CLEARED" % A.roman, Vector2(480, 56), 32, Color(1.0, 0.82 * g + 0.1, 0.23), HORIZONTAL_ALIGNMENT_CENTER, 3)
		Art.text(self, A.name, Vector2(480, 84), 16, Color("ff7a3d"), HORIZONTAL_ALIGNMENT_CENTER, 2)
		# the act in numbers
		var sm := Run.act_summary(act_i)
		var held: int = A.sectors.filter(func(sc): return Run.camp.held.has(Run.sec_key(sc.id, act_i))).size()
		var rows := [["OPS FOUGHT", "%d  (%d WON)" % [sm.ops, sm.won]], ["KILLS", str(sm.kills)], ["MEDALS", str(sm.medals)],
			["SECTORS HELD", "%d OF %d" % [held, A.sectors.size()]], ["FALLEN", ", ".join(sm.fallen) if sm.fallen.size() else "NOBODY"]]
		draw_rect(Rect2(24, 112, 540, 150), Color(0.07, 0.07, 0.08))
		draw_rect(Rect2(24, 112, 540, 150), Color("3a4048"), false, 2)
		Art.text(self, "THE ACT IN NUMBERS", Vector2(40, 134), 8, Color("62d26f"))
		for i in rows.size():
			Art.text(self, rows[i][0], Vector2(40, 160 + i * 20), 16, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
			Art.text(self, rows[i][1], Vector2(548, 160 + i * 20), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_RIGHT, 2, true)
		# the MVP
		draw_rect(Rect2(24, 274, 540, 96), Color("2a2a1e"))
		draw_rect(Rect2(24, 274, 540, 96), Color("ffd23a"), false, 2)
		if not mvp.is_empty():
			Art.draw_char(self, Art.look_sheet(mvp), "cheer", (t / 10) % 2, Vector2(80, 362), 1, false, 0, 1.0, 0, false, 1.6)
			Art.text(self, "ACT MVP", Vector2(140, 300), 8, Color("ffd23a"))
			Art.text(self, "%s %s" % [Run.rank_name(mvp), mvp.def.name], Vector2(140, 324), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 2)
			Art.text(self, "%d kills this act. A field promotion pick waits at HQ." % int(Run.svc(mvp).get("acts", {}).get(str(act_i), 0)), Vector2(140, 350), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
		# the company, with their kills this act
		var co := Run.company()
		for i in co.size():
			var s: Dictionary = co[i]
			var x := 48.0 + i * 52.0
			Art.draw_char(self, Art.look_sheet(s), "idle", (t / 12 + i) % 4, Vector2(x, 440), 1, false, 0, 1.0, 0, true, 1.0)
			Art.text(self, s.def.name, Vector2(x, 456), 8, Color("9aa2ae"), HORIZONTAL_ALIGNMENT_CENTER)
			Art.text(self, str(int(Run.svc(s).get("acts", {}).get(str(act_i), 0))), Vector2(x, 472), 8, Color("ffd23a"), HORIZONTAL_ALIGNMENT_CENTER)
		# the next front, drawn in road by road
		var N: Dictionary = Run.act(act_i + 1)
		Art.text(self, "NEXT FRONT  ACT %s" % N.roman, Vector2(PREV.position.x, 134), 8, Color("62d26f"))
		Art.text(self, N.name, Vector2(PREV.end.x, 134), 8, Color("ff7a3d"), HORIZONTAL_ALIGNMENT_RIGHT)
		draw_rect(PREV, Color("16232c"))
		draw_rect(PREV, Color("3a4048"), false, 2)
		var reveal := clampf((t - 20) / 90.0, 0.0, 1.0)
		var secs: Array = N.sectors
		var pos := {"lz": mp(N.lz.at)}
		for sc in secs:
			pos[sc.id] = mp(sc.at)
		var roads: Array = []
		for sc in secs:
			for l in sc.links:
				roads.append([pos[sc.id], pos[l]])
		for i in roads.size():
			var f := clampf(reveal * roads.size() - i, 0.0, 1.0)
			if f > 0:
				draw_line(roads[i][0], roads[i][0].lerp(roads[i][1], f), Color(0.91, 0.86, 0.76, 0.5), 2)
		draw_rect(Rect2(pos.lz - Vector2(8, 8), Vector2(16, 16)), Color("62d26f"))
		for i in secs.size():
			if reveal * secs.size() < i + 0.5:
				continue
			var big: bool = secs[i].get("stronghold", false)
			var w := 20.0 if big else 14.0
			draw_rect(Rect2(pos[secs[i].id] - Vector2(w, w) / 2, Vector2(w, w)), Color("ff4d3d") if big else Color("ffd23a") if secs[i].links.has("lz") else Color("4a525c"))
		var ty := PREV.end.y + 22
		for ln in CardView.wrap_text(N.text, PREV.size.x, 16):
			Art.text(self, ln, Vector2(PREV.position.x, ty), 16, Color("e8dcc2"), HORIZONTAL_ALIGNMENT_LEFT, 2, true)
			ty += 18

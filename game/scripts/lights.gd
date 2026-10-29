extends Node2D
## G6: real 2D lights. Blasts, muzzle flashes, burning units and camp fires light up whatever is
## around them, and the character sheets carry Sprite Fusion normal maps (Art.lit_tex) so a soldier
## is lit from the side the light is on. Night maps get a darker canvas so the lights read. Lights
## step with the battle clock like the VFX, and are cosmetic only.

const POOL := 24

@onready var b: Battle = get_parent()
var lights: Array[PointLight2D] = []
var flashes: Array = []   # {x, y, r, col, t, life}
var shade: CanvasModulate
var last_t := -1

func _ready() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	for i in POOL:
		var l := PointLight2D.new()
		l.texture = gt
		l.enabled = false
		l.height = 24.0  # lights sit a little in front of the sprites so normal maps shade them
		add_child(l)
		lights.append(l)
	shade = CanvasModulate.new()
	shade.color = Color.WHITE
	add_child(shade)

func flash(x: float, y: float, r: float, col: Color, life := 18) -> void:
	flashes.append({"x": x, "y": y, "r": r, "col": col, "t": 0, "life": life})
	if flashes.size() > POOL:
		flashes.pop_front()

func _process(_d: float) -> void:
	if b.T == null:
		return
	shade.color = Color(0.74, 0.76, 0.9) if b.theme == "night" else Color.WHITE
	if last_t < 0:
		last_t = b.t
	var steps := b.t - last_t
	last_t = b.t
	for f in flashes:
		f.t += steps
	flashes = flashes.filter(func(f): return f.t < f.life)
	var want: Array = []
	for f in flashes:
		var k: float = 1.0 - float(f.t) / f.life
		want.append([Vector2(f.x, f.y), f.r * (0.6 + 0.4 * k), f.col, 1.6 * k])
	for u in b.units:
		if u.dead or u.gone or not b.view.on_screen(u.x):
			continue
		if u.muzzle > 0 and u.sheet != "" and Art.meta.has(u.sheet):
			var a: Array = b.view.pick_anim(u)
			var mo := Art.muzzle_offset(u.sheet, a[0], a[1], u.gun_angle)
			want.append([Vector2(u.x + mo.x * u.face, u.y + mo.y), 70.0, Color("ffd27a"), 1.2])
		if u.has_st("burn"):
			var fl := 0.85 + 0.15 * sin(b.t / 3.0 + u.id)
			want.append([Vector2(u.x, u.y - u.h / 2.0), 60.0 * fl, Color("ff8a3d"), 0.9 * fl])
	for c in b.T.camps:
		if b.view.on_screen(c.fire, 120):
			var gy = b.T.stand_y(c.fire, 0)
			if gy != null:
				var fl := 0.9 + 0.1 * sin(b.t / 5.0)
				want.append([Vector2(c.fire, gy - 6), 110.0 * fl, Color("ffb25a"), 0.8 if b.theme == "night" else 0.45])
	for i in POOL:
		var l := lights[i]
		if i >= want.size():
			l.enabled = false
			continue
		var w: Array = want[i]
		l.enabled = true
		l.position = w[0]
		l.texture_scale = w[1] / 64.0
		l.color = w[2]
		l.energy = w[3]

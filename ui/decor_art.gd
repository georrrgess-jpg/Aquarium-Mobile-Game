class_name DecorArt
extends RefCounted
## Procedural reef decor. Every item stands on the bottom edge of `rect`,
## centred horizontally, and stays inside it. Silhouettes are deliberately
## different so they read at 48px wide:
##   coral fan   = wide fan of branches
##   bubble col. = low rock + tall rising bubble stream
##   sea lantern = thin post + glowing glass lantern with halo
##   statue      = stone figure on a plinth with seaweed
##   light shaft = slanted translucent beam + dust motes on a small stone

const KIND_CORAL_FAN := 0
const KIND_BUBBLE_COLUMN := 1
const KIND_SEA_LANTERN := 2
const KIND_SUNKEN_STATUE := 3
const KIND_LIGHT_SHAFT := 4
const KIND_COUNT := 5

## opts: alpha (float, 1.0), animate (bool, true; false = still pose, ignores t),
##       glow (bool, true).
static func draw(ci: CanvasItem, kind: int, rect: Rect2, t: float, opts: Dictionary = {}) -> void:
	var alpha: float = float(opts.get("alpha", 1.0))
	var animate: bool = bool(opts.get("animate", true))
	var glow: bool = bool(opts.get("glow", true))
	var tt: float = t if animate else 0.0
	# local frame: o.x = centre x, o.y = base y, o.z = unit (item is 1 wide, up to 1.3 tall)
	var k: float = minf(rect.size.x, rect.size.y / 1.3)
	var o := Vector3(rect.position.x + rect.size.x * 0.5, rect.end.y, k)
	match kind:
		KIND_CORAL_FAN:
			_coral_fan(ci, o, tt, alpha)
		KIND_BUBBLE_COLUMN:
			_bubble_column(ci, o, tt, alpha, animate)
		KIND_SEA_LANTERN:
			_sea_lantern(ci, o, tt, alpha, glow)
		KIND_SUNKEN_STATUE:
			_statue(ci, o, tt, alpha)
		KIND_LIGHT_SHAFT:
			_light_shaft(ci, o, tt, alpha, glow)

static func _p(o: Vector3, x: float, y: float) -> Vector2:
	return Vector2(o.x + x * o.z, o.y - y * o.z)

static func _a(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)

static func _lw(o: Vector3, f: float) -> float:
	return maxf(1.0, o.z * f)

static func _qb(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)

# ---------------------------------------------------------------- coral fan

static func _coral_fan(ci: CanvasItem, o: Vector3, t: float, alpha: float) -> void:
	var coral: Color = _a(Pal.CORAL, alpha)
	var dark: Color = _a(Pal.CORAL_DARK, alpha)
	var pink: Color = _a(Color("ffb3c1"), alpha)
	var base := Vector2(0.0, 0.10)
	# translucent fan membrane behind the branches
	var mem := PackedVector2Array([_p(o, 0.0, 0.10)])
	for i in 9:
		var a: float = lerpf(-0.95, 0.95, float(i) / 8.0)
		mem.append(_p(o, sin(a) * 0.43, 0.12 + cos(a) * 0.98 * (0.86 + 0.14 * absf(sin(a * 2.0)))))
	ci.draw_colored_polygon(mem, _a(Color("ff9aa8"), alpha * 0.40))
	# holdfast / rock
	ci.draw_colored_polygon(PackedVector2Array([_p(o, -0.30, 0.0), _p(o, -0.20, 0.10), _p(o, 0.18, 0.12), _p(o, 0.32, 0.0)]), _a(Pal.SAND_DEEP, alpha))
	ci.draw_line(_p(o, 0.0, 0.08), _p(o, 0.0, 0.26), dark, _lw(o, 0.10), true)
	# main branches (7), each a gentle curve with two twigs
	var n: int = 7
	for i in n:
		var u: float = float(i) / float(n - 1)
		var a: float = lerpf(-0.90, 0.90, u)
		var sway: float = sin(t * 1.4 + float(i) * 0.7) * 0.025
		var len_f: float = 0.86 + 0.14 * (1.0 - absf(u - 0.5) * 2.0)
		var start: Vector2 = Vector2(0.0, 0.24)
		var tip: Vector2 = Vector2(sin(a) * 0.46 + sway, 0.14 + cos(a) * len_f * 0.98)
		var ctrl: Vector2 = Vector2(sin(a) * 0.20, 0.24 + cos(a) * len_f * 0.42)
		var pts := PackedVector2Array()
		for s in 4:
			var q: Vector2 = _qb(start, ctrl, tip, float(s) / 3.0)
			pts.append(_p(o, q.x, q.y))
		ci.draw_polyline(pts, coral if i % 2 == 0 else _a(Color("ff6f8a"), alpha), _lw(o, 0.065), true)
		# twigs from 60% along the branch
		var mid: Vector2 = _qb(start, ctrl, tip, 0.62)
		for sgn in [-1.0, 1.0]:
			var tw := Vector2(mid.x + float(sgn) * 0.10 + sway, mid.y + 0.13)
			ci.draw_line(_p(o, mid.x, mid.y), _p(o, tw.x, tw.y), coral, _lw(o, 0.045), true)
		ci.draw_circle(_p(o, tip.x, tip.y), maxf(1.2, o.z * 0.042), pink)
	# trunk top highlight
	ci.draw_circle(_p(o, 0.0, 0.22), maxf(1.5, o.z * 0.07), coral)

# ------------------------------------------------------------ bubble column

static func _bubble_column(ci: CanvasItem, o: Vector3, t: float, alpha: float, animate: bool) -> void:
	var rock: Color = _a(Color("6d7e86"), alpha)
	var rock_d: Color = _a(Color("455660"), alpha)
	var rock_l: Color = _a(Color("93a5ac"), alpha)
	var water: Color = _a(Color("bfeaff"), alpha)
	# faint column of disturbed water
	var colw: float = 0.30
	ci.draw_colored_polygon(PackedVector2Array([_p(o, -colw * 0.45, 0.20), _p(o, -colw * 0.9, 1.26), _p(o, colw * 0.9, 1.26), _p(o, colw * 0.45, 0.20)]), _a(Color("bfeaff"), alpha * 0.10))
	# rock vent mound
	ci.draw_colored_polygon(PackedVector2Array([_p(o, -0.46, 0.0), _p(o, -0.36, 0.12), _p(o, -0.16, 0.22), _p(o, 0.16, 0.22), _p(o, 0.36, 0.11), _p(o, 0.48, 0.0)]), rock_d)
	ci.draw_colored_polygon(PackedVector2Array([_p(o, -0.40, 0.0), _p(o, -0.32, 0.10), _p(o, -0.14, 0.19), _p(o, 0.14, 0.19), _p(o, 0.32, 0.09), _p(o, 0.42, 0.0)]), rock)
	ci.draw_colored_polygon(PackedVector2Array([_p(o, -0.30, 0.06), _p(o, -0.22, 0.13), _p(o, -0.08, 0.17), _p(o, -0.16, 0.10)]), rock_l)
	# vent mouth
	ci.draw_colored_polygon(PackedVector2Array([_p(o, -0.11, 0.20), _p(o, -0.07, 0.24), _p(o, 0.07, 0.24), _p(o, 0.11, 0.20), _p(o, 0.0, 0.17)]), _a(Color("1c2a31"), alpha))
	# rising bubbles
	var nb: int = 11
	for i in nb:
		var seed_v: float = fposmod(float(i) * 0.618034, 1.0)       # stable pseudo-random 0..1
		var speed: float = 0.16 + seed_v * 0.10
		var ph: float = fposmod(t * speed + float(i) / float(nb), 1.0)
		var y: float = 0.25 + ph * 0.98
		var spread: float = 0.05 + ph * 0.20
		var x: float = sin(ph * 7.0 + float(i) * 1.9) * spread
		var r: float = o.z * (0.028 + 0.050 * seed_v) * (0.75 + 0.5 * ph)
		r = maxf(r, 1.4)
		var fade: float = clampf((1.24 - y) * 7.0, 0.0, 1.0)
		var pos: Vector2 = _p(o, x, y)
		ci.draw_circle(pos, r, _a(water, 0.22 * fade))
		ci.draw_arc(pos, r, 0.0, TAU, 12, _a(water, 0.85 * fade), maxf(1.0, r * 0.28), true)
		if r > 3.0:
			ci.draw_circle(pos + Vector2(-r * 0.35, -r * 0.35), maxf(0.8, r * 0.22), _a(Color.WHITE, 0.9 * fade * alpha))

# -------------------------------------------------------------- sea lantern

static func _sea_lantern(ci: CanvasItem, o: Vector3, t: float, alpha: float, glow: bool) -> void:
	var iron: Color = _a(Color("3a4a52"), alpha)
	var iron_l: Color = _a(Color("66808a"), alpha)
	var warm: Color = _a(Color("ffd27a"), alpha)
	var flick: float = 0.85 + 0.15 * sin(t * 3.1) * sin(t * 1.7 + 1.0)
	var lc: Vector2 = _p(o, 0.0, 0.84)
	if glow:
		ci.draw_circle(lc, o.z * 0.50 * flick, _a(Color("ffd27a"), alpha * 0.10))
		ci.draw_circle(lc, o.z * 0.38 * flick, _a(Color("ffd27a"), alpha * 0.16))
		ci.draw_circle(lc, o.z * 0.26 * flick, _a(Color("ffe3a0"), alpha * 0.26))
	# base: stone footing and post
	ci.draw_colored_polygon(PackedVector2Array([_p(o, -0.34, 0.0), _p(o, -0.26, 0.09), _p(o, 0.26, 0.09), _p(o, 0.34, 0.0)]), iron)
	ci.draw_colored_polygon(PackedVector2Array([_p(o, -0.17, 0.09), _p(o, -0.10, 0.17), _p(o, 0.10, 0.17), _p(o, 0.17, 0.09)]), iron_l)
	ci.draw_line(_p(o, 0.0, 0.14), _p(o, 0.0, 0.54), iron, _lw(o, 0.075), true)
	ci.draw_circle(_p(o, 0.0, 0.34), maxf(1.5, o.z * 0.06), iron_l)
	# curled bracket arms
	ci.draw_arc(_p(o, -0.10, 0.50), o.z * 0.10, PI * 0.5, PI * 1.5, 8, iron, _lw(o, 0.04), true)
	ci.draw_arc(_p(o, 0.10, 0.50), o.z * 0.10, -PI * 0.5, PI * 0.5, 8, iron, _lw(o, 0.04), true)
	# lantern cage: bottom cup, glass, frame, roof, finial
	ci.draw_colored_polygon(PackedVector2Array([_p(o, -0.16, 0.54), _p(o, 0.16, 0.54), _p(o, 0.13, 0.60), _p(o, -0.13, 0.60)]), iron)
	var glass := PackedVector2Array([_p(o, -0.13, 0.60), _p(o, 0.13, 0.60), _p(o, 0.19, 0.78), _p(o, 0.13, 1.02), _p(o, -0.13, 1.02), _p(o, -0.19, 0.78)])
	ci.draw_colored_polygon(glass, _a(Color("ffd98a"), alpha * 0.95))
	ci.draw_circle(lc, o.z * 0.085 * flick, _a(Color("fff6d0"), alpha))
	ci.draw_polyline(PackedVector2Array([_p(o, -0.13, 0.60), _p(o, -0.19, 0.78), _p(o, -0.13, 1.02)]), iron, _lw(o, 0.04), true)
	ci.draw_polyline(PackedVector2Array([_p(o, 0.13, 0.60), _p(o, 0.19, 0.78), _p(o, 0.13, 1.02)]), iron, _lw(o, 0.04), true)
	ci.draw_line(_p(o, 0.0, 0.60), _p(o, 0.0, 1.02), _a(iron, 0.7), _lw(o, 0.025), true)
	ci.draw_colored_polygon(PackedVector2Array([_p(o, -0.20, 1.02), _p(o, 0.20, 1.02), _p(o, 0.08, 1.14), _p(o, -0.08, 1.14)]), iron)
	ci.draw_circle(_p(o, 0.0, 1.17), maxf(1.5, o.z * 0.045), iron_l)

# -------------------------------------------------------------------- statue

static func _statue(ci: CanvasItem, o: Vector3, t: float, alpha: float) -> void:
	var st: Color = _a(Color("8e9ca3"), alpha)
	var st_d: Color = _a(Color("56666f"), alpha)
	var st_l: Color = _a(Color("bccacf"), alpha)
	var weed: Color = _a(Color("3fae7a"), alpha)
	var weed_d: Color = _a(Color("2a8660"), alpha)
	# plinth: two stacked blocks
	ci.draw_rect(Rect2(_p(o, -0.40, 0.14), Vector2(0.80, 0.14) * o.z), st_d)
	ci.draw_rect(Rect2(_p(o, -0.37, 0.14), Vector2(0.74, 0.11) * o.z), st)
	ci.draw_rect(Rect2(_p(o, -0.29, 0.30), Vector2(0.58, 0.12) * o.z), st_d)
	ci.draw_rect(Rect2(_p(o, -0.26, 0.30), Vector2(0.52, 0.10) * o.z), st)
	# robed figure
	ci.draw_colored_polygon(PackedVector2Array([_p(o, -0.22, 0.42), _p(o, -0.15, 0.78), _p(o, 0.15, 0.78), _p(o, 0.22, 0.42)]), st_d)
	ci.draw_colored_polygon(PackedVector2Array([_p(o, -0.18, 0.43), _p(o, -0.12, 0.77), _p(o, 0.12, 0.77), _p(o, 0.18, 0.43)]), st)
	ci.draw_line(_p(o, -0.04, 0.46), _p(o, -0.02, 0.74), st_d, _lw(o, 0.03), true)
	ci.draw_line(_p(o, 0.07, 0.46), _p(o, 0.05, 0.70), st_d, _lw(o, 0.03), true)
	# raised arm (right) holding a shell, stump on the left (weathered)
	ci.draw_line(_p(o, 0.12, 0.74), _p(o, 0.30, 0.94), st_d, _lw(o, 0.115), true)
	ci.draw_line(_p(o, 0.12, 0.74), _p(o, 0.30, 0.94), st, _lw(o, 0.075), true)
	ci.draw_circle(_p(o, 0.32, 0.98), maxf(2.0, o.z * 0.075), st_d)
	ci.draw_circle(_p(o, 0.32, 0.98), maxf(1.5, o.z * 0.055), st_l)
	ci.draw_line(_p(o, -0.13, 0.74), _p(o, -0.24, 0.62), st_d, _lw(o, 0.10), true)
	ci.draw_line(_p(o, -0.13, 0.74), _p(o, -0.24, 0.62), st, _lw(o, 0.065), true)
	# head
	ci.draw_circle(_p(o, 0.0, 0.89), o.z * 0.125, st_d)
	ci.draw_circle(_p(o, 0.0, 0.89), o.z * 0.10, st_l)
	ci.draw_circle(_p(o, 0.04, 0.86), maxf(1.0, o.z * 0.022), st)   # worn chip
	# seaweed ribbons on both sides of the plinth
	for i in 2:
		var sx: float = -0.36 + float(i) * 0.12
		var pts := PackedVector2Array()
		for s in 5:
			var h: float = float(s) / 4.0
			pts.append(_p(o, sx + sin(t * 1.3 + h * 2.4 + float(i) * 1.3) * 0.045 * h, 0.04 + h * (0.36 + 0.12 * float(i))))
		ci.draw_polyline(pts, weed if i == 0 else weed_d, _lw(o, 0.05), true)
	var pr := PackedVector2Array()
	for s in 4:
		var h2: float = float(s) / 3.0
		pr.append(_p(o, 0.38 + sin(t * 1.1 + h2 * 2.0) * 0.03 * h2, 0.05 + h2 * 0.30))
	ci.draw_polyline(pr, weed, _lw(o, 0.05), true)

# --------------------------------------------------------------- light shaft

static func _light_shaft(ci: CanvasItem, o: Vector3, t: float, alpha: float, glow: bool) -> void:
	var stone: Color = _a(Color("7d8d92"), alpha)
	var stone_d: Color = _a(Color("4c5d64"), alpha)
	var stone_l: Color = _a(Color("a9b9bd"), alpha)
	# slanted beam: wide at the top-left, landing on the stone at the bottom-right
	var gl: float = 1.0 if glow else 0.6
	var shimmer: float = 1.0 + 0.10 * sin(t * 1.2)
	var beam := PackedVector2Array([_p(o, -0.50, 1.28), _p(o, -0.06, 1.28), _p(o, 0.46, 0.20), _p(o, 0.12, 0.20)])
	var bc := PackedColorArray([
		_a(Color("fff4c0"), alpha * 0.36 * gl * shimmer), _a(Color("fff4c0"), alpha * 0.36 * gl * shimmer),
		_a(Color("fff4c0"), alpha * 0.10 * gl), _a(Color("fff4c0"), alpha * 0.10 * gl)])
	ci.draw_polygon(beam, bc)
	var core := PackedVector2Array([_p(o, -0.34, 1.28), _p(o, -0.20, 1.28), _p(o, 0.32, 0.20), _p(o, 0.22, 0.20)])
	var cc := PackedColorArray([
		_a(Color("ffffff"), alpha * 0.30 * gl), _a(Color("ffffff"), alpha * 0.30 * gl),
		_a(Color("ffffff"), alpha * 0.06 * gl), _a(Color("ffffff"), alpha * 0.06 * gl)])
	ci.draw_polygon(core, cc)
	# stone the light falls on
	ci.draw_colored_polygon(PackedVector2Array([_p(o, -0.04, 0.0), _p(o, 0.0, 0.20), _p(o, 0.14, 0.30), _p(o, 0.36, 0.28), _p(o, 0.50, 0.14), _p(o, 0.50, 0.0)]), stone_d)
	ci.draw_colored_polygon(PackedVector2Array([_p(o, 0.01, 0.0), _p(o, 0.05, 0.18), _p(o, 0.15, 0.26), _p(o, 0.35, 0.24), _p(o, 0.45, 0.12), _p(o, 0.45, 0.0)]), stone)
	ci.draw_colored_polygon(PackedVector2Array([_p(o, 0.14, 0.25), _p(o, 0.35, 0.23), _p(o, 0.42, 0.15), _p(o, 0.18, 0.17)]), _a(Color("fff0b0"), alpha * (0.9 if glow else 0.5)))
	ci.draw_circle(_p(o, 0.09, 0.12), maxf(1.2, o.z * 0.03), stone_l)
	# a few grass-like weeds at left of the stone
	ci.draw_line(_p(o, -0.14, 0.0), _p(o, -0.18 + sin(t * 1.5) * 0.03, 0.22), _a(Color("3fae7a"), alpha), _lw(o, 0.045), true)
	ci.draw_line(_p(o, -0.08, 0.0), _p(o, -0.07 + sin(t * 1.5 + 1.0) * 0.03, 0.17), _a(Color("2a8660"), alpha), _lw(o, 0.04), true)
	# drifting dust motes inside the beam
	for i in 9:
		var sv: float = fposmod(float(i) * 0.618034, 1.0)
		var ph: float = fposmod(t * (0.03 + 0.03 * sv) + float(i) / 9.0, 1.0)
		var y: float = 1.24 - ph * 1.0
		# beam centre line x at height y, plus wander
		var cx: float = lerpf(-0.28, 0.30, (1.28 - y) / 1.08)
		var x: float = cx + (sv - 0.5) * 0.30 * (0.45 + (y - 0.2) * 0.4) + sin(t * 0.9 + float(i) * 2.0) * 0.025
		var fade: float = clampf(minf(ph * 6.0, (1.0 - ph) * 6.0), 0.0, 1.0)
		ci.draw_circle(_p(o, x, y), maxf(1.0, o.z * (0.016 + 0.014 * sv)), _a(Color("fffbe0"), alpha * 0.9 * fade))

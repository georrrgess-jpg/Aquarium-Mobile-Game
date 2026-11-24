class_name DecorArt
extends RefCounted
## Procedural reef decor. Every item stands on the bottom edge of `rect`, centred
## horizontally, and stays inside it (rect is ~1 : 1.3). Silhouettes are deliberately
## different so they read at 48px wide:
##   coral fan   = wide pink fan of forked branches on a rock
##   bubble col. = dark vent rock + tall widening stream of bubbles
##   sea lantern = ornate post + warm glass lantern with a shell roof and halo
##   statue      = weathered stone guardian with trident on a mossy plinth
##   light shaft = slanted beam of light landing on a small boulder
## Light comes from the top-left; fills have a darker 1-2px outline.
##
## draw(): opts alpha=1, animate=true, glow=true, state=0 (ItemArt.STATE_*:
##   LOCKED = dark silhouette + padlock, UNAFFORDABLE = desaturated, OWNED = full colour + seal,
##   SELECTED = soft ground glow), badge=true (lock / seal overlay).
## world_effect(): draw BEFORE the item; it paints onto the surrounding reef.

const KIND_CORAL_FAN := 0
const KIND_BUBBLE_COLUMN := 1
const KIND_SEA_LANTERN := 2
const KIND_SUNKEN_STATUE := 3
const KIND_LIGHT_SHAFT := 4
const KIND_COUNT := 5

# ---------------------------------------------------------------- drawing context

## Local frame: x in [-0.5, 0.5] across the item, y up from the base, unit k px.
## Colours pass through col() so alpha and item state apply uniformly.
class Cx extends RefCounted:
	var ci: CanvasItem
	var ox: float = 0.0
	var oy: float = 0.0
	var k: float = 1.0
	var alpha: float = 1.0
	var state: int = 0
	var t: float = 0.0
	var fx: bool = true      # glows / beams / light effects allowed
	var ow: float = 1.0      # outline width in px

	func p(x: float, y: float) -> Vector2:
		return Vector2(ox + x * k, oy - y * k)

	func col(c: Color) -> Color:
		if state == 2:
			var g: float = ItemArt.gray(c)
			c = Color(0.07 + g * 0.20, 0.12 + g * 0.24, 0.19 + g * 0.30, c.a)
		elif state == 3:
			c = ItemArt.tint(c, 3)
		return Color(c.r, c.g, c.b, c.a * alpha)

	func pts(f: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		var i: int = 0
		while i + 1 < f.size():
			out.append(p(f[i], f[i + 1]))
			i += 2
		return out

	## Filled polygon from a flat [x0,y0,x1,y1,...] list, with optional outline.
	func poly(f: Array, fill: Color, line: Color = Color(0, 0, 0, 0)) -> void:
		var pp: PackedVector2Array = pts(f)
		ci.draw_colored_polygon(pp, col(fill))
		if line.a > 0.0:
			var ring: PackedVector2Array = pp.duplicate()
			ring.append(pp[0])
			ci.draw_polyline(ring, col(line), ow, true)

	## Polygon with a per-vertex colour list.
	func gpoly(f: Array, colors: Array) -> void:
		var cc := PackedColorArray()
		for c in colors:
			cc.append(col(c))
		ci.draw_polygon(pts(f), cc)

	func line(x0: float, y0: float, x1: float, y1: float, c: Color, wf: float) -> void:
		ci.draw_line(p(x0, y0), p(x1, y1), col(c), maxf(1.0, k * wf), true)

	func pline(f: Array, c: Color, wf: float) -> void:
		ci.draw_polyline(pts(f), col(c), maxf(1.0, k * wf), true)

	func circ(x: float, y: float, rf: float, c: Color) -> void:
		ci.draw_circle(p(x, y), maxf(0.8, k * rf), col(c))

	func ring(x: float, y: float, rf: float, c: Color, wf: float = 0.0) -> void:
		var r: float = maxf(1.0, k * rf)
		ci.draw_arc(p(x, y), r, 0.0, TAU, 14, col(c), maxf(1.0, k * wf) if wf > 0.0 else ow, true)

	func glow(x: float, y: float, rxf: float, ryf: float, c: Color) -> void:
		ItemArt.glow(ci, p(x, y), rxf * k, ryf * k, col(c))

# ---------------------------------------------------------------- entry points

static func draw(ci: CanvasItem, kind: int, rect: Rect2, t: float, opts: Dictionary = {}) -> void:
	var animate: bool = bool(opts.get("animate", true))
	var cx := Cx.new()
	cx.ci = ci
	cx.alpha = float(opts.get("alpha", 1.0))
	cx.state = int(opts.get("state", 0))
	cx.t = t if animate else 0.0
	cx.k = minf(rect.size.x, rect.size.y / 1.3)
	cx.ox = rect.position.x + rect.size.x * 0.5
	cx.oy = rect.end.y
	cx.ow = clampf(cx.k * 0.012, 1.0, 2.0)
	cx.fx = bool(opts.get("glow", true)) and cx.state != 2
	if cx.state == 1:
		cx.glow(0.0, 0.1, 0.62, 0.28, Color("ffe08a"))
		cx.glow(0.0, 0.1, 0.4, 0.16, Color(1, 1, 1, 0.5))
	match kind:
		KIND_CORAL_FAN:
			_coral_fan(cx)
		KIND_BUBBLE_COLUMN:
			_bubble_column(cx)
		KIND_SEA_LANTERN:
			_sea_lantern(cx)
		KIND_SUNKEN_STATUE:
			_statue(cx)
		KIND_LIGHT_SHAFT:
			_light_shaft(cx)
	if bool(opts.get("badge", true)) and cx.alpha > 0.0:
		if cx.state == 2:
			ItemArt.draw_lock(ci, cx.p(0.0, 0.52), cx.k * 0.46, Color("a9bcc6"))
		elif cx.state == 4:
			ItemArt.draw_check_seal(ci, cx.p(0.34, 1.12), cx.k * 0.3)

static func _wob(t: float, ph: float, f: float = 1.0) -> float:
	return sin(t * f + ph)

# ---------------------------------------------------------------- coral fan

static func _coral_fan(c: Cx) -> void:
	var t: float = c.t
	var pink: Color = Color("ff6b8e")
	var pink_d: Color = Color("a8284a")
	var pink_l: Color = Color("ffc2d0")
	var line: Color = Color("8e2442")
	# holdfast rock
	c.poly([-0.36, 0.0, -0.32, 0.07, -0.2, 0.125, 0.1, 0.135, 0.27, 0.09, 0.38, 0.0], Color("c9a577"), Color("6f4f31"))
	c.poly([-0.31, 0.015, -0.28, 0.065, -0.19, 0.105, -0.05, 0.115, -0.2, 0.045], Color("ead2a2"))
	# stem
	c.poly([-0.05, 0.1, 0.05, 0.1, 0.035, 0.27, -0.035, 0.27], Color("c43c62"), line)
	# fan membrane (scalloped outline follows the branch tips)
	var mem: Array = [0.0, 0.25]
	var n: int = 21
	for i in n:
		var u: float = float(i) / float(n - 1)
		var a: float = lerpf(-1.0, 1.0, u)
		var lobe: float = 0.93 + 0.07 * absf(sin(u * PI * 6.0))
		mem.append(sin(a) * 0.52 * lobe + sin(t * 1.2 + u * 5.0) * 0.012 * absf(a))
		mem.append(0.25 + cos(a) * 0.93 * lobe * (0.9 + 0.1 * cos(a * 1.5)))
	c.poly(mem, Color(1.0, 0.58, 0.7, 0.78), pink_d)
	# fine mesh arcs
	for rf in [0.52, 0.78]:
		var arc: Array = []
		for i in 11:
			var a2: float = lerpf(-0.9, 0.9, float(i) / 10.0)
			arc.append(sin(a2) * 0.52 * rf)
			arc.append(0.25 + cos(a2) * 0.93 * rf)
		c.pline(arc, Color(1.0, 0.82, 0.88, 0.5), 0.012)
	# branches: dark underlay + colour, forks and polyps
	for i in 7:
		var u2: float = float(i) / 6.0
		var a3: float = lerpf(-0.95, 0.95, u2)
		var lf: float = 0.80 + 0.2 * (1.0 - absf(u2 - 0.5) * 2.0)
		var sw: float = sin(t * 1.2 + float(i) * 0.8) * 0.02
		var tip := Vector2(sin(a3) * 0.52 * lf + sw, 0.25 + cos(a3) * 0.93 * lf)
		var base := Vector2(0.0, 0.25)
		var bow: float = 0.05 * (1.0 if i % 2 == 0 else -1.0)
		var mid: Vector2 = base.lerp(tip, 0.5) + Vector2(bow * cos(a3), bow * -sin(a3) * 0.0)
		var q1: Vector2 = base.lerp(mid, 0.5).lerp(mid.lerp(tip, 0.5), 0.5)
		var path: Array = [base.x, base.y, q1.x, q1.y, mid.x, mid.y, mid.lerp(tip, 0.5).x, mid.lerp(tip, 0.5).y + 0.0, tip.x, tip.y]
		var main_col: Color = pink if i % 2 == 0 else Color("ff5a7c")
		c.pline(path, pink_d, 0.062)
		c.pline(path, main_col, 0.04)
		# forks
		var f1: Vector2 = base.lerp(tip, 0.45) + Vector2(bow, 0.0) * 0.5
		var f2: Vector2 = base.lerp(tip, 0.72) + Vector2(bow, 0.0) * 0.2
		var dirv: Vector2 = (tip - base).normalized()
		var perp := Vector2(-dirv.y, dirv.x)
		var s1: float = 1.0 if i < 3 else -1.0
		if i == 3:
			s1 = 1.0
		var fe1: Vector2 = f1 + (dirv * 0.55 + perp * 0.5 * s1).normalized() * 0.2
		var fe2: Vector2 = f2 + (dirv * 0.6 - perp * 0.5 * s1).normalized() * 0.14
		c.line(f1.x, f1.y, fe1.x, fe1.y, main_col, 0.03)
		c.line(f2.x, f2.y, fe2.x, fe2.y, main_col, 0.028)
		c.circ(tip.x, tip.y, 0.034, pink_l)
		c.circ(fe2.x, fe2.y, 0.026, pink_l)
		c.circ(fe1.x, fe1.y, 0.022, Color("ffe3ea"))
	# base highlight + sparkle
	c.line(-0.02, 0.15, -0.02, 0.26, Color("ff9db6"), 0.016)
	c.circ(-0.012, 0.74, 0.012, Color.WHITE)

# ------------------------------------------------------------ bubble column

static func _bubble_column(c: Cx) -> void:
	var t: float = c.t
	var rock: Color = Color("62727f")
	var rock_d: Color = Color("2f3b46")
	var rock_l: Color = Color("93a8b6")
	# disturbed-water column
	if c.fx:
		c.gpoly([-0.14, 0.2, 0.14, 0.2, 0.36, 1.3, -0.36, 1.3],
			[Color(0.75, 0.95, 1.0, 0.22), Color(0.75, 0.95, 1.0, 0.22), Color(0.75, 0.95, 1.0, 0.0), Color(0.75, 0.95, 1.0, 0.0)])
	# rock mound
	c.poly([-0.5, 0.0, -0.46, 0.07, -0.36, 0.13, -0.22, 0.2, -0.1, 0.25, 0.1, 0.25, 0.22, 0.2, 0.36, 0.12, 0.47, 0.06, 0.5, 0.0], rock, rock_d)
	c.poly([-0.44, 0.02, -0.4, 0.07, -0.3, 0.12, -0.19, 0.18, -0.1, 0.22, -0.2, 0.1, -0.34, 0.04], rock_l)
	c.poly([0.14, 0.06, 0.25, 0.14, 0.4, 0.1, 0.44, 0.03, 0.3, 0.0], Color("4a5967"))
	c.line(-0.05, 0.2, -0.12, 0.1, rock_d, 0.014)
	c.line(0.1, 0.19, 0.18, 0.1, rock_d, 0.014)
	# small foreground rocks
	c.poly([-0.5, 0.0, -0.47, 0.05, -0.38, 0.07, -0.33, 0.0], Color("77899a"), rock_d)
	c.poly([0.3, 0.0, 0.33, 0.05, 0.42, 0.06, 0.48, 0.0], Color("56677a"), rock_d)
	# tube worms + tiny coral on the right for colour
	for i in 3:
		var bx: float = 0.34 + float(i) * 0.045
		var sw: float = sin(t * 2.0 + float(i)) * 0.012
		c.line(bx, 0.07, bx + sw, 0.16 + 0.03 * float(i % 2), Color("e5506e"), 0.03)
		c.circ(bx + sw, 0.17 + 0.03 * float(i % 2), 0.024, Color("ffa3b5"))
	# vent mouth
	c.poly([-0.12, 0.23, -0.07, 0.275, 0.07, 0.275, 0.12, 0.23, 0.0, 0.195], Color("17242c"), Color("0c141a"))
	if c.fx:
		c.glow(0.0, 0.24, 0.16, 0.08, Color(0.7, 0.95, 1.0, 0.8))
	# rising bubbles
	var nb: int = 13
	for i in nb:
		var sv: float = fposmod(float(i) * 0.618034, 1.0)
		var sp: float = 0.14 + sv * 0.1
		var ph: float = fposmod(t * sp + float(i) / float(nb), 1.0)
		var y: float = 0.27 + ph * 1.0
		var spread: float = 0.03 + ph * 0.2
		var x: float = sin(ph * 6.5 + float(i) * 1.9) * spread
		var rf: float = (0.026 + 0.05 * sv) * (0.7 + 0.6 * ph)
		var fade: float = clampf((1.28 - y) * 6.0, 0.0, 1.0) * clampf(ph * 12.0, 0.0, 1.0)
		var pos: Vector2 = c.p(x, y)
		var r: float = maxf(1.5, rf * c.k)
		c.ci.draw_circle(pos, r, c.col(Color(0.8, 0.96, 1.0, 0.2 * fade)))
		c.ci.draw_arc(pos, r, 0.0, TAU, 14, c.col(Color(0.88, 0.98, 1.0, 0.95 * fade)), maxf(1.0, r * 0.22), true)
		if r > 3.2:
			c.ci.draw_circle(pos + Vector2(-r * 0.38, -r * 0.38), maxf(0.9, r * 0.2), c.col(Color(1, 1, 1, 0.95 * fade)))

# -------------------------------------------------------------- sea lantern

static func _sea_lantern(c: Cx) -> void:
	var t: float = c.t
	var flick: float = 0.88 + 0.12 * sin(t * 3.1) * sin(t * 1.7 + 1.0)
	var iron: Color = Color("2f4a52")
	var iron_d: Color = Color("172a30")
	var iron_l: Color = Color("5f8591")
	var brass: Color = Color("e5b04a")
	var brass_d: Color = Color("7a5416")
	var coral: Color = Color("ff7a6b")
	var coral_d: Color = Color("a8403a")
	if c.fx:
		c.glow(0.0, 0.88, 0.62 * flick, 0.55 * flick, Color(1.0, 0.82, 0.45, 0.4))
		c.glow(0.0, 0.88, 0.32 * flick, 0.3 * flick, Color(1.0, 0.93, 0.7, 0.5))
	# stepped stone pedestal with a carved scallop
	c.poly([-0.31, 0.0, -0.31, 0.065, 0.31, 0.065, 0.31, 0.0], Color("a5b6bb"), Color("4e6068"))
	c.poly([-0.23, 0.065, -0.23, 0.14, 0.23, 0.14, 0.23, 0.065], Color("c5d3d6"), Color("4e6068"))
	c.poly([-0.31, 0.0, -0.25, 0.0, -0.25, 0.062, -0.31, 0.062], Color(1, 1, 1, 0.28))
	ItemArt.draw_shell(c.ci, c.p(0.0, 0.105), c.k * 0.06, c.col(Color("8ea2a8")), c.col(Color("e6f0f2")), c.col(Color("4e6068")), 1.0, false)
	# column: tapered, with brass rings and a lit left edge
	c.poly([-0.06, 0.14, 0.06, 0.14, 0.038, 0.62, -0.038, 0.62], iron, iron_d)
	c.poly([-0.055, 0.15, -0.03, 0.15, -0.022, 0.61, -0.034, 0.61], iron_l)
	for yy in [0.2, 0.4, 0.58]:
		c.poly([-0.075, yy, 0.075, yy, 0.075, yy + 0.035, -0.075, yy + 0.035], brass, brass_d)
		c.line(-0.07, yy + 0.026, 0.0, yy + 0.026, Color(1, 0.95, 0.7, 0.8), 0.01)
	# small scroll brackets at the column
	c.ci.draw_arc(c.p(-0.085, 0.47), c.k * 0.055, PI * 0.5, PI * 1.5, 8, c.col(iron_d), maxf(1.6, c.k * 0.035), true)
	c.ci.draw_arc(c.p(-0.085, 0.47), c.k * 0.055, PI * 0.5, PI * 1.5, 8, c.col(brass), maxf(1.0, c.k * 0.018), true)
	c.ci.draw_arc(c.p(0.085, 0.47), c.k * 0.055, -PI * 0.5, PI * 0.5, 8, c.col(iron_d), maxf(1.6, c.k * 0.035), true)
	c.ci.draw_arc(c.p(0.085, 0.47), c.k * 0.055, -PI * 0.5, PI * 0.5, 8, c.col(brass), maxf(1.0, c.k * 0.018), true)
	# lantern base cup
	c.poly([-0.2, 0.655, 0.2, 0.655, 0.17, 0.72, -0.17, 0.72], brass, brass_d)
	c.line(-0.18, 0.69, 0.0, 0.69, Color(1, 0.95, 0.7, 0.8), 0.012)
	# glass (hexagonal): amber outer, lighter inner, bright core
	var glass: Array = [-0.17, 0.72, 0.17, 0.72, 0.22, 0.88, 0.17, 1.04, -0.17, 1.04, -0.22, 0.88]
	c.poly(glass, Color("ffb347"))
	c.poly([-0.12, 0.74, 0.12, 0.74, 0.16, 0.88, 0.12, 1.02, -0.12, 1.02, -0.16, 0.88], Color("ffd37a"))
	c.circ(0.0, 0.88, 0.1 * flick, Color("fff3c4"))
	c.circ(0.0, 0.88, 0.055 * flick, Color.WHITE)
	# flame tongue
	c.poly([-0.03, 0.82, 0.03, 0.82, 0.0, 0.97 + 0.01 * sin(t * 6.0)], Color("fff8dc"))
	# frame bars + glass glint
	c.pline([-0.17, 0.72, -0.22, 0.88, -0.17, 1.04], iron_d, 0.04)
	c.pline([0.17, 0.72, 0.22, 0.88, 0.17, 1.04], iron_d, 0.04)
	c.line(-0.065, 0.73, -0.065, 1.03, iron_d, 0.022)
	c.line(0.065, 0.73, 0.065, 1.03, iron_d, 0.022)
	c.line(-0.17, 1.0, -0.2, 0.9, Color(1, 1, 1, 0.8), 0.02)
	# scallop-shell roof with brass collar and finial
	c.poly([-0.2, 1.03, 0.2, 1.03, 0.2, 1.07, -0.2, 1.07], brass, brass_d)
	ItemArt.draw_shell(c.ci, c.p(0.0, 1.12), c.k * 0.3, c.col(coral), c.col(Color("ffc4b8")), c.col(coral_d), maxf(1.0, c.ow), true)
	c.circ(0.0, 1.27, 0.032, brass)
	c.ring(0.0, 1.27, 0.032, brass_d)
	# hanging charms
	c.line(-0.2, 0.7, -0.2, 0.6, brass_d, 0.012)
	c.circ(-0.2, 0.58, 0.022, Color("ffd0c0"))
	c.line(0.2, 0.7, 0.2, 0.6, brass_d, 0.012)
	c.circ(0.2, 0.58, 0.022, Color("ffd0c0"))
	if c.fx:
		var ph: float = fposmod(t * 0.6, 1.0)
		ItemArt.sparkle(c.ci, c.p(0.24, 1.0 + 0.1 * ph), c.k * 0.07 * sin(ph * PI), c.col(Color(1, 1, 0.9, 0.95)))

# -------------------------------------------------------------------- statue

static func _statue(c: Cx) -> void:
	var t: float = c.t
	var st: Color = Color("97a8b0")
	var st_d: Color = Color("4d5f69")
	var st_l: Color = Color("cad8dc")
	var st_line: Color = Color("33434c")
	var weed: Color = Color("3fb07c")
	var weed_d: Color = Color("2a8461")
	var moss: Color = Color("5fb36a")
	# seaweed behind
	for i in 2:
		var sx: float = -0.43 + float(i) * 0.1
		var w: Array = []
		for s in 6:
			var h: float = float(s) / 5.0
			w.append(sx + sin(t * 1.3 + h * 2.6 + float(i) * 1.3) * 0.05 * h)
			w.append(0.02 + h * (0.5 + 0.14 * float(i)))
		c.pline(w, weed_d if i == 0 else weed, 0.05)
	# plinth (two blocks)
	c.poly([-0.42, 0.0, 0.42, 0.0, 0.42, 0.13, -0.42, 0.13], st, st_line)
	c.poly([-0.42, 0.0, -0.3, 0.0, -0.3, 0.13, -0.42, 0.13], st_l)
	c.poly([-0.32, 0.13, 0.32, 0.13, 0.32, 0.27, -0.32, 0.27], st, st_line)
	c.poly([-0.32, 0.13, -0.22, 0.13, -0.22, 0.27, -0.32, 0.27], st_l)
	# moss + barnacles on the plinth
	c.poly([-0.42, 0.0, -0.42, 0.09, -0.34, 0.07, -0.28, 0.03, -0.3, 0.0], moss)
	c.circ(0.3, 0.06, 0.022, Color("e8eadf"))
	c.circ(0.27, 0.1, 0.014, Color("cfd4c8"))
	# robe / skirt
	c.poly([-0.23, 0.27, 0.23, 0.27, 0.16, 0.62, -0.16, 0.62], st, st_line)
	c.poly([-0.23, 0.27, -0.12, 0.27, -0.09, 0.62, -0.16, 0.62], st_l)
	c.poly([0.03, 0.27, 0.23, 0.27, 0.16, 0.62, 0.03, 0.62], Color(0.2, 0.28, 0.36, 0.3))
	c.line(-0.02, 0.3, -0.01, 0.6, st_d, 0.016)
	c.line(0.09, 0.3, 0.07, 0.58, st_d, 0.016)
	# belt
	c.poly([-0.17, 0.59, 0.17, 0.59, 0.17, 0.65, -0.17, 0.65], st_d, st_line)
	# torso with shell breastplate
	c.poly([-0.17, 0.65, 0.17, 0.65, 0.22, 0.82, 0.12, 0.88, -0.12, 0.88, -0.22, 0.82], st, st_line)
	c.poly([-0.17, 0.65, -0.08, 0.65, -0.07, 0.88, -0.12, 0.88, -0.22, 0.82], st_l)
	c.poly([0.05, 0.65, 0.17, 0.65, 0.22, 0.82, 0.12, 0.88, 0.05, 0.88], Color(0.2, 0.28, 0.36, 0.3))
	c.pline([-0.11, 0.82, 0.0, 0.7, 0.11, 0.82], st_d, 0.018)
	# right arm holds the trident, left arm is broken off (weathered stump)
	c.line(0.18, 0.82, 0.28, 0.68, st_line, 0.095)
	c.line(0.18, 0.82, 0.28, 0.68, st, 0.065)
	c.line(0.28, 0.27, 0.28, 1.2, Color("5c6e78"), 0.026)
	var tri: Color = Color("7f929c")
	c.pline([0.215, 1.2, 0.215, 1.12, 0.345, 1.12, 0.345, 1.2], st_line, 0.04)
	c.line(0.28, 1.09, 0.28, 1.22, st_line, 0.04)
	c.pline([0.215, 1.2, 0.215, 1.12, 0.345, 1.12, 0.345, 1.2], tri, 0.022)
	c.line(0.28, 1.09, 0.28, 1.22, tri, 0.022)
	for tx in [0.215, 0.28, 0.345]:
		var txf: float = tx
		c.poly([txf - 0.03, 1.2, txf + 0.03, 1.2, txf, 1.29], tri, st_line)
	c.circ(0.28, 0.7, 0.04, st_l)
	c.poly([-0.22, 0.82, -0.28, 0.76, -0.25, 0.68, -0.18, 0.74], st, st_line)
	# pauldrons
	c.circ(-0.2, 0.82, 0.062, st_line)
	c.circ(-0.2, 0.82, 0.052, st_l)
	c.circ(0.2, 0.82, 0.062, st_line)
	c.circ(0.2, 0.82, 0.052, st)
	# head: face, domed helmet and a swept fin crest
	c.poly([-0.035, 1.07, -0.05, 1.15, -0.01, 1.22, 0.06, 1.21, 0.1, 1.15, 0.1, 1.07], Color("8fa2ab"), st_line)
	c.poly([-0.03, 1.08, -0.04, 1.15, -0.01, 1.2, 0.01, 1.14], st_l)
	c.circ(0.0, 0.98, 0.104, st_line)
	c.circ(0.0, 0.98, 0.092, st)
	c.circ(-0.03, 0.995, 0.055, st_l)
	var dome: Array = []
	for i in 9:
		var da: float = PI - float(i) / 8.0 * PI
		dome.append(cos(da) * 0.108)
		dome.append(1.0 + sin(da) * 0.1)
	c.poly(dome, Color("86999f"), st_line)
	c.line(-0.055, 0.96, -0.022, 0.96, st_line, 0.018)
	c.line(0.022, 0.96, 0.055, 0.96, st_line, 0.018)
	# weathering: chip, crack, moss on the shoulder, barnacles
	c.poly([0.1, 0.88, 0.2, 0.84, 0.15, 0.8], Color(0.05, 0.3, 0.4, 0.8))
	c.line(-0.12, 0.86, -0.09, 0.76, st_line, 0.011)
	c.poly([-0.22, 0.82, -0.14, 0.88, -0.07, 0.87, -0.15, 0.82], moss)
	c.circ(-0.12, 0.45, 0.022, Color("e8eadf"))
	# foreground seaweed
	var fw: Array = []
	for s in 5:
		var h2: float = float(s) / 4.0
		fw.append(0.4 + sin(t * 1.1 + h2 * 2.0) * 0.035 * h2)
		fw.append(0.03 + h2 * 0.38)
	c.pline(fw, weed, 0.05)

# --------------------------------------------------------------- light shaft

static func _light_shaft(c: Cx) -> void:
	var t: float = c.t
	var stone: Color = Color("8a9aa0")
	var stone_d: Color = Color("485860")
	var stone_l: Color = Color("c3d0d2")
	var shim: float = 1.0 + 0.1 * sin(t * 1.2)
	if c.fx:
		# the beam: wide at the top-left, landing on the boulder
		var bw: float = 1.0 * shim
		c.gpoly([-0.5, 1.3, -0.02, 1.3, 0.5, 0.22, 0.1, 0.22],
			[Color(1, 0.96, 0.7, 0.4 * bw), Color(1, 0.96, 0.7, 0.4 * bw), Color(1, 0.96, 0.7, 0.12), Color(1, 0.96, 0.7, 0.12)])
		c.gpoly([-0.36, 1.3, -0.2, 1.3, 0.34, 0.22, 0.22, 0.22],
			[Color(1, 1, 1, 0.34), Color(1, 1, 1, 0.34), Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.08)])
		c.line(-0.5, 1.3, 0.1, 0.22, Color(1, 0.98, 0.8, 0.5), 0.012)
		c.line(-0.02, 1.3, 0.5, 0.22, Color(1, 0.98, 0.8, 0.28), 0.012)
	# sea grass behind
	for i in 3:
		var gx: float = -0.12 + float(i) * 0.07
		c.line(gx, 0.0, gx - 0.02 + sin(t * 1.5 + float(i)) * 0.03, 0.2 + 0.05 * float(i % 2), Color("3fae7a") if i != 1 else Color("2a8660"), 0.04)
	# boulder
	c.poly([0.0, 0.0, 0.01, 0.1, 0.08, 0.2, 0.2, 0.28, 0.36, 0.28, 0.47, 0.18, 0.5, 0.0], stone, Color("2f3f46"))
	c.poly([0.03, 0.02, 0.04, 0.1, 0.1, 0.18, 0.2, 0.24, 0.12, 0.1], stone_d)
	# lit top (beam hits it)
	c.poly([0.1, 0.19, 0.2, 0.26, 0.36, 0.26, 0.44, 0.18, 0.3, 0.2], Color("fff0b8"))
	c.poly([0.16, 0.21, 0.22, 0.25, 0.3, 0.25, 0.26, 0.21], Color(1, 1, 1, 0.85))
	c.line(0.32, 0.02, 0.36, 0.14, Color("2f3f46"), 0.012)
	c.poly([0.06, 0.0, 0.1, 0.06, 0.18, 0.0], Color("3fae7a"))
	c.poly([0.35, 0.0, 0.4, 0.05, 0.48, 0.0], Color("2a8660"))
	if c.fx:
		c.glow(0.27, 0.24, 0.28, 0.12, Color(1, 0.95, 0.65, 0.5))
	# pebbles
	c.poly([-0.12, 0.0, -0.1, 0.04, -0.03, 0.04, -0.01, 0.0], stone, Color("2f3f46"))
	c.circ(-0.2, 0.02, 0.02, stone_l)
	# dust motes drifting down the beam
	if c.fx:
		for i in 9:
			var sv: float = fposmod(float(i) * 0.618034, 1.0)
			var ph: float = fposmod(t * (0.04 + 0.03 * sv) + float(i) / 9.0, 1.0)
			var y: float = 1.26 - ph * 1.0
			var cxm: float = lerpf(-0.3, 0.3, (1.3 - y) / 1.08)
			var x: float = cxm + (sv - 0.5) * 0.3 * (0.5 + (y - 0.2) * 0.4) + sin(t * 0.9 + float(i) * 2.0) * 0.025
			var fade: float = clampf(minf(ph * 6.0, (1.0 - ph) * 6.0), 0.0, 1.0)
			c.circ(x, y, 0.016 + 0.012 * sv, Color(1, 0.99, 0.88, 0.95 * fade))
		var sp: float = fposmod(t * 0.5, 1.0)
		ItemArt.sparkle(c.ci, c.p(0.3, 0.3), c.k * 0.07 * sin(sp * PI), c.col(Color(1, 1, 1, 0.95)))

# ---------------------------------------------------------------- world effects

## Paints an item's effect on the surrounding reef. Call BEFORE drawing the item itself.
## slot_rect = the item's rect (it stands on slot_rect.end.y = the sand line),
## reef_rect = the whole reef water area (top = surface), night 0..1.
static func world_effect(ci: CanvasItem, kind: int, slot_rect: Rect2, reef_rect: Rect2, t: float, night: float) -> void:
	var k: float = minf(slot_rect.size.x, slot_rect.size.y / 1.3)
	var cx: float = slot_rect.position.x + slot_rect.size.x * 0.5
	var gy: float = slot_rect.end.y
	var top: float = reef_rect.position.y
	match kind:
		KIND_SEA_LANTERN:
			var flick: float = 0.92 + 0.08 * sin(t * 3.1) * sin(t * 1.7 + 1.0)
			var s: float = (0.55 + 0.45 * night) * flick
			var ly: float = gy - k * 0.88
			# halo in the water, a warm cone, then a pool of light on the sand
			ItemArt.glow(ci, Vector2(cx, ly), k * 3.0, k * 2.6, Color(1.0, 0.78, 0.38, 0.26 * s))
			ItemArt.glow(ci, Vector2(cx, ly), k * 1.4, k * 1.3, Color(1.0, 0.88, 0.55, 0.36 * s))
			var cone := PackedVector2Array([Vector2(cx - k * 0.14, ly), Vector2(cx + k * 0.14, ly), Vector2(cx + k * 1.6, gy), Vector2(cx - k * 1.6, gy)])
			var cc := PackedColorArray([Color(1, 0.88, 0.55, 0.2 * s), Color(1, 0.88, 0.55, 0.2 * s), Color(1, 0.88, 0.55, 0.0), Color(1, 0.88, 0.55, 0.0)])
			ci.draw_polygon(cone, cc)
			ItemArt.glow(ci, Vector2(cx, gy + k * 0.05), k * 3.4, k * 0.5, Color(1.0, 0.82, 0.42, 0.7 * s))
			ItemArt.glow(ci, Vector2(cx, gy + k * 0.05), k * 1.5, k * 0.22, Color(1.0, 0.95, 0.72, 0.75 * s))
			for i in 6:
				var ph: float = fposmod(t * 0.15 + float(i) * 0.17, 1.0)
				var mx: float = cx + sin(float(i) * 2.3 + t * 0.6) * k * 1.0
				var my: float = ly + k * 0.8 - ph * k * 2.0
				ci.draw_circle(Vector2(mx, my), maxf(1.0, k * 0.028), Color(1, 0.92, 0.65, 0.8 * s * sin(ph * PI)))
		KIND_LIGHT_SHAFT:
			var d: float = 1.0 - 0.5 * night
			var sh: float = 1.0 + 0.08 * sin(t * 0.9)
			var span: float = gy - top
			var xb: float = cx + k * 0.27
			var xt: float = maxf(xb - span * 0.48, reef_rect.position.x - k)
			var wt: float = k * 1.7
			var wb: float = k * 0.9
			var beam := PackedVector2Array([Vector2(xt - wt * 0.5, top), Vector2(xt + wt * 0.5, top), Vector2(xb + wb * 0.5, gy), Vector2(xb - wb * 0.5, gy)])
			var bc := PackedColorArray([Color(1, 0.97, 0.75, 0.4 * d * sh), Color(1, 0.97, 0.75, 0.4 * d * sh), Color(1, 0.97, 0.75, 0.12 * d), Color(1, 0.97, 0.75, 0.12 * d)])
			ci.draw_polygon(beam, bc)
			var beam2 := PackedVector2Array([Vector2(xt - wt * 0.12, top), Vector2(xt + wt * 0.22, top), Vector2(xb + wb * 0.16, gy), Vector2(xb - wb * 0.12, gy)])
			var bc2 := PackedColorArray([Color(1, 1, 1, 0.26 * d), Color(1, 1, 1, 0.26 * d), Color(1, 1, 1, 0.05 * d), Color(1, 1, 1, 0.05 * d)])
			ci.draw_polygon(beam2, bc2)
			ci.draw_line(Vector2(xt - wt * 0.5, top), Vector2(xb - wb * 0.5, gy), Color(1, 0.98, 0.8, 0.25 * d), 1.5, true)
			ItemArt.glow(ci, Vector2(xb, gy + k * 0.05), k * 2.0, k * 0.34, Color(1, 0.97, 0.75, 0.6 * d))
			for i in 12:
				var ph2: float = fposmod(t * (0.03 + 0.02 * float(i % 3)) + float(i) * 0.083, 1.0)
				var yy: float = top + ph2 * span
				var xx: float = lerpf(xt, xb, ph2) + sin(float(i) * 3.1 + t * 0.7) * lerpf(wt, wb, ph2) * 0.4
				ci.draw_circle(Vector2(xx, yy), maxf(1.0, k * 0.022), Color(1, 1, 0.9, 0.85 * d * sin(ph2 * PI)))
		KIND_BUBBLE_COLUMN:
			var vy: float = gy - k * 0.27
			var span2: float = vy - top
			var col := PackedVector2Array([Vector2(cx - k * 0.12, vy), Vector2(cx + k * 0.12, vy), Vector2(cx + k * 0.6, top), Vector2(cx - k * 0.6, top)])
			var cc2 := PackedColorArray([Color(0.8, 0.96, 1, 0.16), Color(0.8, 0.96, 1, 0.16), Color(0.8, 0.96, 1, 0.0), Color(0.8, 0.96, 1, 0.0)])
			ci.draw_polygon(col, cc2)
			for i in 16:
				var sv: float = fposmod(float(i) * 0.618034, 1.0)
				var ph3: float = fposmod(t * (0.07 + 0.05 * sv) + float(i) / 16.0, 1.0)
				var yy2: float = vy - ph3 * span2
				var xx2: float = cx + sin(ph3 * 9.0 + float(i) * 1.9) * k * (0.08 + 0.34 * ph3)
				var r2: float = maxf(1.4, k * (0.024 + 0.036 * sv) * (0.8 + 0.5 * ph3))
				var fa: float = clampf((1.0 - ph3) * 4.0, 0.0, 1.0) * clampf(ph3 * 10.0, 0.0, 1.0)
				ci.draw_arc(Vector2(xx2, yy2), r2, 0.0, TAU, 10, Color(0.9, 0.99, 1, 0.7 * fa), 1.2, true)
			ItemArt.glow(ci, Vector2(cx, gy), k * 1.3, k * 0.2, Color(0.8, 0.95, 1.0, 0.3))
		KIND_CORAL_FAN:
			var wob: float = 0.5 + 0.5 * sin(t * 0.8)
			ItemArt.glow(ci, Vector2(cx, gy + k * 0.04), k * 2.4, k * 0.4, Color(1.0, 0.42, 0.58, 0.5))
			ItemArt.glow(ci, Vector2(cx, gy - k * 0.5), k * 1.4, k * 1.2, Color(1.0, 0.55, 0.65, 0.14 + 0.06 * wob))
			for i in 20:
				var sv2: float = fposmod(float(i) * 0.618034, 1.0)
				var ph4: float = fposmod(t * (0.06 + 0.05 * sv2) + float(i) / 20.0, 1.0)
				var xx3: float = cx + (sv2 - 0.5) * k * 1.4 + sin(ph4 * 7.0 + float(i)) * k * 0.2 + ph4 * k * 0.7
				var yy3: float = gy - k * 0.6 - ph4 * k * 1.6
				var fa2: float = sin(ph4 * PI)
				ci.draw_circle(Vector2(xx3, yy3), maxf(1.2, k * (0.02 + 0.02 * sv2)), Color(1.0, 0.7 + 0.2 * sv2, 0.8, 0.9 * fa2))
			for i in 6:
				ci.draw_circle(Vector2(cx + (float(i) - 2.5) * k * 0.45, gy + k * 0.03 + 0.0), maxf(1.2, k * 0.028), Color(1.0, 0.55, 0.68, 0.7))
		KIND_SUNKEN_STATUE:
			# soft shadow on the sand, a dim halo behind, and a few small fish
			ItemArt.glow(ci, Vector2(cx + k * 0.3, gy + k * 0.05), k * 1.5, k * 0.24, Color(0.02, 0.1, 0.18, 0.65))
			ItemArt.glow(ci, Vector2(cx, gy - k * 0.55), k * 0.9, k * 1.1, Color(0.02, 0.12, 0.2, 0.28))
			for i in 4:
				var fp: float = t * (0.5 + 0.1 * float(i)) + float(i) * 1.7
				var fxp: float = cx + cos(fp) * k * (0.8 + 0.12 * float(i))
				var fyp: float = gy - k * (0.5 + 0.22 * float(i)) + sin(fp * 1.3) * k * 0.07
				var sgn: float = 1.0 if -sin(fp) >= 0.0 else -1.0
				var fl: float = k * (0.1 + 0.01 * float(i % 2))
				var fcs: Array = [Color("ffb84d"), Color("6fe0ff"), Color("ff7f9e"), Color("ffe36a")]
				var fc: Color = fcs[i]
				ci.draw_colored_polygon(PackedVector2Array([Vector2(fxp - sgn * fl * 0.8, fyp), Vector2(fxp - sgn * fl * 1.6, fyp - fl * 0.55), Vector2(fxp - sgn * fl * 1.6, fyp + fl * 0.55)]), fc.darkened(0.2))
				ci.draw_colored_polygon(PackedVector2Array([Vector2(fxp - fl, fyp), Vector2(fxp, fyp - fl * 0.55), Vector2(fxp + fl, fyp), Vector2(fxp, fyp + fl * 0.55)]), fc)
				ci.draw_circle(Vector2(fxp + sgn * fl * 0.5, fyp - fl * 0.1), maxf(0.9, fl * 0.13), Color(0.05, 0.1, 0.15))

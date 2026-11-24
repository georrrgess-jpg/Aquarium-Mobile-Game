class_name ItemArt
extends RefCounted
## Procedural vector art for the game's "things": coin, pearl, Current token, Reef Gate,
## offline chest, shop/roster card frames, padlock and check seal.
## Everything is drawn through CanvasItem draw_* calls. Light comes from the top-left,
## outlines are 1.5-2px darker versions of the fill, highlights are crisp.
##
## Shared item states (coin, pearl, token, gate, card frame, DecorArt):
##   AVAILABLE   normal colours
##   SELECTED    glow / gold ring
##   LOCKED      dull + padlock
##   UNAFFORDABLE desaturated with a faint red tint
##   OWNED       full colour + check seal

const STATE_AVAILABLE := 0
const STATE_SELECTED := 1
const STATE_LOCKED := 2
const STATE_UNAFFORDABLE := 3
const STATE_OWNED := 4

const CHEST_CLOSED := 0
const CHEST_FULL := 1
const CHEST_OPEN := 2

const GOLD_LIGHT := Color("ffe58a")
const GOLD_MID := Color("f6b834")
const GOLD_DARK := Color("b9701a")
const GOLD_LINE := Color("6e3f0c")
const BRASS := Color("e0a93a")
const BRASS_D := Color("8a5a16")
const WOOD_L := Color("b0764a")
const WOOD_M := Color("8a5532")
const WOOD_D := Color("5a3420")
const WOOD_LINE := Color("33180d")
const STONE_L := Color("f0d3bd")
const STONE_M := Color("d9a98c")
const STONE_D := Color("a8745f")
const STONE_LINE := Color("6b3f35")
const MINT := Color("56e0a0")
const MINT_D := Color("1f7d56")

static var _glow_mesh: ArrayMesh = null

# ---------------------------------------------------------------- shared helpers

static func gray(c: Color) -> float:
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114

## One place that turns a colour into its state-treated colour.
static func tint(c: Color, state: int) -> Color:
	if state == STATE_LOCKED:
		var g: float = gray(c)
		return Color(lerpf(c.r, g, 0.82) * 0.80, lerpf(c.g, g, 0.82) * 0.83, lerpf(c.b, g, 0.82) * 0.90 + 0.02, c.a)
	if state == STATE_UNAFFORDABLE:
		var g2: float = gray(c)
		var d := Color(lerpf(c.r, g2, 0.68), lerpf(c.g, g2, 0.68), lerpf(c.b, g2, 0.68), c.a)
		return d.lerp(Color(0.86, 0.28, 0.25, c.a), 0.14)
	return c

static func _a(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)

static func _dk(c: Color, f: float) -> Color:
	return Color(c.r * (1.0 - f), c.g * (1.0 - f), c.b * (1.0 - f), c.a)

static func _lt(c: Color, f: float) -> Color:
	return Color(lerpf(c.r, 1.0, f), lerpf(c.g, 1.0, f), lerpf(c.b, 1.0, f), c.a)

static func _lw(size: float, f: float, lo: float = 1.0, hi: float = 2.2) -> float:
	return clampf(size * f, lo, hi)

static func _glow_mesh_get() -> ArrayMesh:
	if _glow_mesh != null:
		return _glow_mesh
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var segs: int = 28
	var rings: Array = [[0.0, 1.0], [0.3, 0.62], [0.62, 0.22], [1.0, 0.0]]
	verts.append(Vector2.ZERO)
	cols.append(Color(1, 1, 1, 1))
	for ri in range(1, 4):
		var rr: float = rings[ri][0]
		var aa: float = rings[ri][1]
		for s in segs:
			var a: float = TAU * float(s) / float(segs)
			verts.append(Vector2(cos(a), sin(a)) * rr)
			cols.append(Color(1, 1, 1, aa))
	for s in segs:
		idx.append(0)
		idx.append(1 + s)
		idx.append(1 + (s + 1) % segs)
	for ri in range(2, 4):
		var base: int = 1 + (ri - 1) * segs
		var prev: int = 1 + (ri - 2) * segs
		for s in segs:
			var s2: int = (s + 1) % segs
			idx.append(prev + s)
			idx.append(base + s)
			idx.append(base + s2)
			idx.append(prev + s)
			idx.append(base + s2)
			idx.append(prev + s2)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	_glow_mesh = ArrayMesh.new()
	_glow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _glow_mesh

## Soft radial glow (one draw call, smooth falloff). col.a is the centre alpha.
static func glow(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	ci.draw_mesh(_glow_mesh_get(), null, Transform2D(Vector2(rx, 0.0), Vector2(0.0, ry), c), col)

static func rrect_pts(r: Rect2, rad: float, seg: int = 5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rr: float = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	for k in 4:
		var cx: float = r.end.x - rr if k < 2 else r.position.x + rr
		var cy: float = r.position.y + rr if (k == 0 or k == 3) else r.end.y - rr
		var a0: float = -PI * 0.5 + float(k) * PI * 0.5
		for s in seg + 1:
			var a: float = a0 + float(s) / float(seg) * PI * 0.5
			pts.append(Vector2(cx + cos(a) * rr, cy + sin(a) * rr))
	return pts

static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var ring: PackedVector2Array = pts.duplicate()
	ring.append(pts[0])
	return ring

## Vertical-gradient rounded rect with an optional AA outline.
static func fill_rrect(ci: CanvasItem, r: Rect2, rad: float, top: Color, bot: Color, line: Color = Color(0, 0, 0, 0), lw: float = 0.0, seg: int = 5) -> void:
	var pts: PackedVector2Array = rrect_pts(r, rad, seg)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(bot, clampf((p.y - r.position.y) / maxf(r.size.y, 1.0), 0.0, 1.0)))
	ci.draw_polygon(pts, cols)
	if lw > 0.0 and line.a > 0.0:
		ci.draw_polyline(_closed(pts), line, lw, true)

static func _poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, line: Color, lw: float) -> void:
	if fill.a > 0.0:
		ci.draw_colored_polygon(pts, fill)
	if lw > 0.0:
		ci.draw_polyline(_closed(pts), line, lw, true)

## Four-point sparkle star.
static func sparkle(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	var q: float = r * 0.22
	ci.draw_colored_polygon(PackedVector2Array([
		p + Vector2(0, -r), p + Vector2(q, -q), p + Vector2(r, 0), p + Vector2(q, q),
		p + Vector2(0, r), p + Vector2(-q, q), p + Vector2(-r, 0), p + Vector2(-q, -q)]), col)

## Scallop shell fan. `c` is the centre of the shell's bounding box, `r` its width/1.63.
## Hinge at the bottom, fan opens upward. Returns nothing; uses 3 + ribs calls.
static func draw_shell(ci: CanvasItem, c: Vector2, r: float, base: Color, light: Color, dark: Color, lw: float, ribs: bool = true) -> void:
	var apex: Vector2 = c + Vector2(0.0, r * 0.52)
	var pts := PackedVector2Array([apex])
	var n: int = 20
	var a0: float = -PI * 0.5 - 0.95
	var a1: float = -PI * 0.5 + 0.95
	for i in n + 1:
		var u: float = float(i) / float(n)
		var a: float = lerpf(a0, a1, u)
		var rr: float = r * (0.86 + 0.14 * absf(sin(u * PI * 5.0)))
		pts.append(apex + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, base)
	# lit upper-left half
	var half := PackedVector2Array([apex])
	for i in range(0, 11):
		half.append(pts[1 + i])
	ci.draw_colored_polygon(half, _a(light, 0.55))
	if ribs:
		for k in range(1, 5):
			var u2: float = float(k) / 5.0
			var a2: float = lerpf(a0, a1, u2)
			ci.draw_line(apex + Vector2(cos(a2), sin(a2)) * r * 0.2, apex + Vector2(cos(a2), sin(a2)) * r * 0.84, _a(dark, 0.6), maxf(1.0, lw * 0.7), true)
	ci.draw_polyline(_closed(pts), dark, lw, true)
	# hinge ears
	ci.draw_colored_polygon(PackedVector2Array([apex + Vector2(-r * 0.2, 0.0), apex + Vector2(r * 0.2, 0.0), apex + Vector2(r * 0.13, r * 0.14), apex + Vector2(-r * 0.13, r * 0.14)]), dark)

# ---------------------------------------------------------------- lock & seal

## Padlock. `size` = overall height, `col` = body colour (shackle uses a lighter metal).
static func draw_lock(ci: CanvasItem, center: Vector2, size: float, col: Color = Color("c4d0d8")) -> void:
	var s: float = size
	var c: Vector2 = center + Vector2(0.0, -0.06 * s)
	var lw: float = _lw(s, 0.09, 1.2, 2.4)
	var dark: Color = _dk(col, 0.62)
	# shackle (dark thick underlay + metal)
	var sh := PackedVector2Array()
	sh.append(c + Vector2(-0.19 * s, 0.02 * s))
	for i in 9:
		var a: float = PI + float(i) / 8.0 * PI
		sh.append(c + Vector2(0.0, -0.06 * s) + Vector2(cos(a), sin(a)) * 0.19 * s)
	sh.append(c + Vector2(0.19 * s, 0.02 * s))
	ci.draw_polyline(sh, dark, lw * 2.0 + 1.2, true)
	ci.draw_polyline(sh, _lt(col, 0.35), lw * 1.5, true)
	# body
	var body := Rect2(c + Vector2(-0.34 * s, -0.02 * s), Vector2(0.68 * s, 0.50 * s))
	fill_rrect(ci, body, s * 0.1, _lt(col, 0.30), _dk(col, 0.12), dark, lw)
	ci.draw_line(body.position + Vector2(s * 0.09, s * 0.07), body.position + Vector2(body.size.x - s * 0.12, s * 0.07), _a(Color.WHITE, 0.55), maxf(1.0, lw * 0.8), true)
	# keyhole
	var kc: Vector2 = body.position + body.size * 0.5 + Vector2(0.0, -0.01 * s)
	ci.draw_circle(kc + Vector2(0.0, -0.03 * s), 0.065 * s, dark)
	ci.draw_colored_polygon(PackedVector2Array([kc + Vector2(-0.03 * s, 0.0), kc + Vector2(0.03 * s, 0.0), kc + Vector2(0.045 * s, 0.14 * s), kc + Vector2(-0.045 * s, 0.14 * s)]), dark)

## Scalloped mint seal with a white check mark. `size` = diameter.
static func draw_check_seal(ci: CanvasItem, center: Vector2, size: float) -> void:
	var r: float = size * 0.5
	var pts := PackedVector2Array()
	for i in 40:
		var a: float = TAU * float(i) / 40.0
		pts.append(center + Vector2(cos(a), sin(a)) * r * (0.9 + 0.1 * cos(a * 10.0)))
	var lw: float = _lw(size, 0.07, 1.2, 2.0)
	ci.draw_circle(center + Vector2(0.0, r * 0.1), r * 0.96, Color(0, 0, 0, 0.2))
	ci.draw_colored_polygon(pts, MINT)
	ci.draw_polyline(_closed(pts), MINT_D, lw, true)
	ci.draw_circle(center + Vector2(-r * 0.12, -r * 0.14), r * 0.62, _lt(MINT, 0.32))
	ci.draw_arc(center, r * 0.68, 0.0, TAU, 20, _a(MINT_D, 0.6), maxf(1.0, lw * 0.7), true)
	var ck := PackedVector2Array([center + Vector2(-0.30, 0.02) * r * 1.0, center + Vector2(-0.08, 0.26) * r, center + Vector2(0.34, -0.22) * r])
	ci.draw_polyline(ck, Color(0.05, 0.3, 0.2, 0.55), lw * 2.4 + 1.0, true)
	ci.draw_polyline(ck, Color.WHITE, lw * 2.0, true)

## Corner badge for a state (lock / seal), drawn over an item.
static func _badge(ci: CanvasItem, c: Vector2, size: float, state: int) -> void:
	if state == STATE_LOCKED:
		draw_lock(ci, c, size)
	elif state == STATE_OWNED:
		draw_check_seal(ci, c, size)
	elif state == STATE_UNAFFORDABLE:
		_price_tag_x(ci, c, size)

static func _price_tag_x(ci: CanvasItem, c: Vector2, size: float) -> void:
	var s: float = size
	var lw: float = _lw(s, 0.07, 1.2, 2.0)
	var tag := PackedVector2Array([
		c + Vector2(-0.48, 0.0) * s, c + Vector2(-0.22, -0.28) * s, c + Vector2(0.46, -0.28) * s,
		c + Vector2(0.46, 0.28) * s, c + Vector2(-0.22, 0.28) * s])
	_poly(ci, tag, Color("f3dfc8"), Color("7a2f2a"), lw)
	ci.draw_circle(c + Vector2(-0.2, 0.0) * s, 0.06 * s, Color("7a2f2a"))
	ci.draw_line(c + Vector2(-0.02, -0.05) * s, c + Vector2(0.34, -0.05) * s, _a(Color("7a2f2a"), 0.6), maxf(1.0, lw * 0.8), true)
	ci.draw_line(c + Vector2(-0.02, 0.1) * s, c + Vector2(0.26, 0.1) * s, _a(Color("7a2f2a"), 0.6), maxf(1.0, lw * 0.8), true)
	ci.draw_line(c + Vector2(-0.5, 0.42) * s, c + Vector2(0.5, -0.42) * s, Color("5a1612"), lw * 2.6 + 1.0, true)
	ci.draw_line(c + Vector2(-0.5, 0.42) * s, c + Vector2(0.5, -0.42) * s, Color("ff5a4a"), lw * 1.7, true)

## Public name for the same corner treatment (used by card frames and DecorArt).
static func draw_state_badge(ci: CanvasItem, c: Vector2, size: float, state: int) -> void:
	_badge(ci, c, size, state)

# ---------------------------------------------------------------- coin

## Gold shell-coin. `size` = diameter. opts: "t" (float) shine animation time.
static func draw_coin(ci: CanvasItem, center: Vector2, size: float, state: int = 0, opts: Dictionary = {}) -> void:
	var r: float = size * 0.5
	var lw: float = _lw(size, 0.05, 1.2, 2.0)
	var big: bool = size >= 44.0
	if state == STATE_SELECTED:
		glow(ci, center, r * 1.75, r * 1.75, _a(GOLD_LIGHT, 0.85))
	ci.draw_circle(center + Vector2(0.0, r * 0.12), r * 0.98, Color(0, 0, 0, 0.22))
	var c_line: Color = tint(GOLD_LINE, state)
	var c_rim: Color = tint(GOLD_MID, state)
	var c_rim_d: Color = tint(GOLD_DARK, state)
	var c_face: Color = tint(Color("f9c747"), state)
	var c_face_l: Color = tint(GOLD_LIGHT, state)
	ci.draw_circle(center, r, c_line)
	ci.draw_circle(center, r - lw, c_rim_d)
	ci.draw_circle(center + Vector2(-r * 0.04, -r * 0.05), r - lw * 1.4, c_rim)
	if big:
		# milled edge ticks
		for i in 16:
			var a: float = TAU * float(i) / 16.0 + 0.1
			var d := Vector2(cos(a), sin(a))
			ci.draw_line(center + d * r * 0.80, center + d * (r - lw * 1.6), _a(c_rim_d, 0.9), maxf(1.0, size * 0.025), true)
	var fr: float = r * (0.76 if big else 0.72)
	ci.draw_circle(center, fr + lw * 0.5, c_rim_d)
	ci.draw_circle(center, fr, c_face)
	ci.draw_circle(center + Vector2(-fr * 0.14, -fr * 0.16), fr * 0.80, c_face_l)
	ci.draw_circle(center + Vector2(fr * 0.06, fr * 0.07), fr * 0.66, c_face)
	# emblem: scallop shell, embossed (dark shifted, light on top)
	var er: float = fr * 0.92
	var ec: Vector2 = center + Vector2(0.0, -fr * 0.04)
	var eb: Color = tint(Color("e5a226"), state)
	draw_shell(ci, ec, er, eb, tint(GOLD_LIGHT, state), tint(Color("8a5410"), state), maxf(1.0, lw * 0.8), size >= 30.0)
	# rim highlight (top-left) and sparkle
	ci.draw_arc(center, r - lw * 1.2, PI * 1.05, PI * 1.55, 10, _a(Color.WHITE, 0.85), maxf(1.0, lw * 0.9), true)
	if big and state != STATE_LOCKED:
		var t: float = float(opts.get("t", 0.0))
		var ph: float = fposmod(t * 0.5, 1.0)
		if opts.has("t") and ph < 0.3:
			sparkle(ci, center + Vector2(-r * 0.45, -r * 0.5), r * 0.22 * sin(ph / 0.3 * PI), _a(Color.WHITE, 0.95))
	_overlay(ci, center, size, state)

static func _overlay(ci: CanvasItem, center: Vector2, size: float, state: int) -> void:
	if state == STATE_LOCKED or state == STATE_OWNED or state == STATE_UNAFFORDABLE:
		var bs: float = clampf(size * 0.5, 12.0, 40.0)
		_badge(ci, center + Vector2(size * 0.30, size * 0.30), bs, state)

# ---------------------------------------------------------------- pearl

## Lustrous pearl on a small shell cradle (cradle only at size >= 40). `size` = overall size.
static func draw_pearl(ci: CanvasItem, center: Vector2, size: float, state: int = 0, opts: Dictionary = {}) -> void:
	var cradle: bool = size >= 48.0
	var lw: float = _lw(size, 0.05, 1.2, 2.0)
	var pr: float = size * (0.27 if cradle else 0.46)
	var pc: Vector2 = center + (Vector2(0.0, -size * 0.02) if cradle else Vector2.ZERO)
	if state == STATE_SELECTED:
		glow(ci, center, size * 0.85, size * 0.85, _a(Color("bfeaff"), 0.8))
	if cradle:
		var sr: float = size * 0.64
		var rose: Color = tint(Color("ff9db0"), state)
		var rose_l: Color = tint(Color("ffd7de"), state)
		var rose_d: Color = tint(Color("a2485c"), state)
		glow(ci, center + Vector2(0.0, size * 0.4), size * 0.5, size * 0.09, Color(0, 0, 0, 0.4))
		# back shell fan standing behind the pearl
		draw_shell(ci, center + Vector2(0.0, -size * 0.17), sr, rose, rose_l, rose_d, lw)
		_pearl_ball(ci, pc, pr, state, lw)
		# front lip of the shell (cradle)
		var lip := PackedVector2Array()
		for i in 13:
			var a: float = lerpf(0.0, PI, float(i) / 12.0)
			lip.append(center + Vector2(cos(a) * size * 0.4, size * 0.16 + sin(a) * size * 0.24))
		ci.draw_colored_polygon(lip, tint(Color("ff86a0"), state))
		ci.draw_colored_polygon(PackedVector2Array([lip[0], lip[1], lip[2], lip[3], lip[4], lip[5], lip[6]]), _a(rose_l, 0.4))
		for k in range(-2, 3):
			ci.draw_line(center + Vector2(float(k) * size * 0.075, size * 0.2), center + Vector2(float(k) * size * 0.11, size * 0.38), _a(rose_d, 0.6), maxf(1.0, lw * 0.7), true)
		ci.draw_polyline(lip, rose_d, lw, true)
		ci.draw_line(lip[0], lip[12], rose_d, lw, true)
	else:
		_pearl_ball(ci, pc, pr, state, lw)
	# sparkle
	var t: float = float(opts.get("t", 0.0))
	var sp: float = 0.85 + 0.15 * sin(t * 4.0)
	if state != STATE_LOCKED:
		sparkle(ci, pc + Vector2(pr * 1.05, -pr * 1.0), size * (0.16 if cradle else 0.2) * sp, _a(Color.WHITE, 0.95))
	_overlay(ci, center, size, state)

static func _pearl_ball(ci: CanvasItem, pc: Vector2, pr: float, state: int, lw: float) -> void:
	var line: Color = tint(Color("5b7fa6"), state)
	ci.draw_circle(pc, pr + lw * 0.5, line)
	ci.draw_circle(pc, pr, tint(Color("c6d2ee"), state))
	ci.draw_circle(pc + Vector2(-pr * 0.1, -pr * 0.1), pr * 0.88, tint(Color("e3e9f9"), state))
	ci.draw_circle(pc + Vector2(-pr * 0.2, -pr * 0.22), pr * 0.62, tint(Color("f8f6ff"), state))
	# iridescent rim light (bottom-right)
	ci.draw_arc(pc, pr * 0.84, 0.15, 1.4, 8, _a(tint(Color("ffb8dc"), state), 0.85), maxf(1.2, pr * 0.16), true)
	ci.draw_arc(pc, pr * 0.84, 1.5, 2.5, 7, _a(tint(Color("a6ecff"), state), 0.85), maxf(1.2, pr * 0.16), true)
	# specular
	ci.draw_circle(pc + Vector2(-pr * 0.38, -pr * 0.42), pr * 0.2, Color(1, 1, 1, 0.98))
	ci.draw_circle(pc + Vector2(pr * 0.32, pr * 0.34), pr * 0.07, Color(1, 1, 1, 0.8))

# ---------------------------------------------------------------- current token

## The Current control. `charges` count shown in a badge; `charges <= 0` renders spent (dim).
## State SELECTED = glowing/active; LOCKED = dim + padlock; UNAFFORDABLE treated as spent.
static func draw_current_token(ci: CanvasItem, rect: Rect2, charges: int, state: int = 0, t: float = 0.0) -> void:
	var m: float = minf(rect.size.x, rect.size.y)
	var spent: bool = charges <= 0 or state == STATE_UNAFFORDABLE
	var locked: bool = state == STATE_LOCKED
	var dim: bool = spent or locked
	var active: bool = state == STATE_SELECTED and not dim
	var cen: Vector2 = rect.position + rect.size * 0.5
	var lw: float = _lw(m, 0.04, 1.5, 2.2)
	var face: Rect2 = rect.grow(-m * 0.04)
	var rad: float = m * 0.3
	if active:
		var pulse: float = 0.5 + 0.5 * sin(t * 4.0)
		glow(ci, cen, rect.size.x * (0.78 + 0.06 * pulse), rect.size.y * (0.9 + 0.08 * pulse), _a(Color("a8ecff"), 0.6 + 0.2 * pulse))
	elif not dim:
		glow(ci, cen, rect.size.x * 0.62, rect.size.y * 0.7, _a(Color("8fd8ff"), 0.22))
	var top: Color = Color("8fe3ff")
	var bot: Color = Color("2f86c8")
	var line: Color = Color("14466e")
	if dim:
		top = tint(top, STATE_LOCKED)
		bot = tint(bot, STATE_LOCKED)
		line = tint(line, STATE_LOCKED)
	# drop shadow + body
	ci.draw_colored_polygon(rrect_pts(Rect2(face.position + Vector2(0.0, m * 0.06), face.size), rad), Color(0, 0, 0, 0.25))
	fill_rrect(ci, face, rad, top, bot, line, lw * 1.4)
	if active:
		ci.draw_polyline(_closed(rrect_pts(face.grow(m * 0.035), rad + m * 0.035)), Color("ffd24d"), maxf(2.5, m * 0.06), true)
	# inner bevel
	var inner: Rect2 = face.grow(-m * 0.07)
	ci.draw_polyline(_closed(rrect_pts(inner, rad * 0.75)), _a(Color.WHITE if not dim else Color("9fb0b8"), 0.35), maxf(1.0, lw * 0.7), true)
	ci.draw_line(face.position + Vector2(rad * 0.9, m * 0.1), face.position + Vector2(face.size.x * 0.55, m * 0.1), _a(Color.WHITE, 0.55 if not dim else 0.25), maxf(1.2, lw), true)
	# curling current symbol
	var sc: float = m * 0.285
	var sc_c: Vector2 = cen + Vector2(-m * 0.03, -m * 0.02)
	var ink: Color = Color("0d3a63") if not dim else tint(Color("0d3a63"), STATE_LOCKED)
	var foam: Color = Color("f4fcff") if not dim else tint(Color("d8eef8"), STATE_LOCKED)
	var wave := PackedVector2Array()
	for i in 10:
		var u: float = float(i) / 9.0
		var bz: Vector2 = _bez(Vector2(-1.0, 0.55), Vector2(-0.35, 0.55), Vector2(-0.4, -0.7), Vector2(0.28, -0.72), u)
		wave.append(sc_c + bz * sc)
	for i in range(1, 15):
		var u2: float = float(i) / 14.0
		var ang: float = -PI * 0.5 + u2 * PI * 1.55
		var rr: float = lerpf(0.52, 0.17, u2)
		wave.append(sc_c + (Vector2(0.28, -0.2) + Vector2(cos(ang), sin(ang)) * rr) * sc)
	var w2 := PackedVector2Array()
	for i in 11:
		var u3: float = float(i) / 10.0
		w2.append(sc_c + Vector2(lerpf(-0.9, 0.35, u3), 1.04 + sin(u3 * TAU * 1.0 + t * (0.0 if dim else 2.5)) * 0.09) * sc)
	ci.draw_polyline(wave, ink, m * 0.15, true)
	ci.draw_polyline(w2, ink, m * 0.1, true)
	ci.draw_polyline(wave, foam, m * 0.085, true)
	ci.draw_polyline(w2, foam, m * 0.05, true)
	for sp_i in 3:
		var spd: Vector2 = sc_c + Vector2(0.72 + 0.16 * float(sp_i % 2), -0.62 + 0.28 * float(sp_i)) * sc
		ci.draw_circle(spd, m * 0.05, ink)
		ci.draw_circle(spd, m * 0.032, foam)
	if active:
		var ph: float = fposmod(t * 0.7, 1.0)
		sparkle(ci, face.position + Vector2(face.size.x * (0.15 + 0.2 * ph), face.size.y * 0.3), m * 0.1 * sin(ph * PI), Color(1, 1, 1, 0.95))
	# charge badge (top-right)
	var br: float = clampf(m * 0.21, 9.0, 18.0)
	var bc: Vector2 = Vector2(face.end.x - br * 0.55, face.position.y + br * 0.55)
	var b_fill: Color = Pal.GOLD if not dim else Color("8a9aa0")
	var b_line: Color = Color("7a4a10") if not dim else Color("46565c")
	ci.draw_circle(bc + Vector2(0.0, 1.5), br + lw * 0.5, Color(0, 0, 0, 0.25))
	ci.draw_circle(bc, br + lw * 0.5, b_line)
	ci.draw_circle(bc, br, b_fill)
	ci.draw_circle(bc + Vector2(-br * 0.15, -br * 0.2), br * 0.62, _lt(b_fill, 0.3))
	var font: Font = ThemeDB.fallback_font
	var fs: int = int(br * 1.25)
	var txt: String = str(maxi(charges, 0))
	ci.draw_string(font, bc + Vector2(-br, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_CENTER, br * 2.0, fs, Color("3a2208") if not dim else Color("1d282c"))
	if locked:
		draw_lock(ci, face.position + Vector2(face.size.x * 0.5, face.size.y * 0.58), m * 0.5)

static func _bez(a: Vector2, b: Vector2, c: Vector2, d: Vector2, u: float) -> Vector2:
	var ab: Vector2 = a.lerp(b, u)
	var bc: Vector2 = b.lerp(c, u)
	var cd: Vector2 = c.lerp(d, u)
	return ab.lerp(bc, u).lerp(bc.lerp(cd, u), u)

# ---------------------------------------------------------------- reef gate

## The Reef Gate portal. rect ~84x470 (any size with that aspect); the bottom 60/470 of the
## rect is left clear for the caller's resident badge. opts: "animate" (true).
static func draw_reef_gate(ci: CanvasItem, rect: Rect2, state: int, t: float, residents: int = 0, opts: Dictionary = {}) -> void:
	var animate: bool = bool(opts.get("animate", true))
	var tt: float = t if animate else 0.0
	var locked: bool = state == STATE_LOCKED
	var sel: bool = state == STATE_SELECTED
	var w: float = rect.size.x
	var h: float = rect.size.y
	var u: float = w / 84.0
	var reserve: float = h * 60.0 / 470.0
	var cx: float = rect.position.x + w * 0.5
	var y0: float = rect.position.y + 2.0 * u
	var yb: float = rect.end.y - reserve
	var rad: float = w * 0.5 - 1.5 * u
	var pw: float = rad * 0.34
	var ri: float = rad - pw
	var yc: float = y0 + rad            # centre of the arch semicircle
	var lw: float = maxf(1.5, 1.8 * u)
	var st_t: int = STATE_LOCKED if locked else STATE_AVAILABLE
	var s_l: Color = tint(STONE_L, st_t)
	var s_m: Color = tint(STONE_M, st_t)
	var s_d: Color = tint(STONE_D, st_t)
	var s_line: Color = tint(STONE_LINE, st_t)
	var coral: Color = tint(Color("ff6f61"), st_t)
	var coral_d: Color = tint(Color("a83a3a"), st_t)
	# halo
	if sel:
		var pulse: float = 0.5 + 0.5 * sin(tt * 4.0)
		glow(ci, Vector2(cx, (y0 + yb) * 0.5), w * (1.1 + 0.08 * pulse), (yb - y0) * 0.6, _a(Color("8ff7e6"), 0.75 + 0.2 * pulse))
	elif not locked:
		glow(ci, Vector2(cx, yc + rad * 1.2), w * 0.85, (yb - y0) * 0.4, _a(Color("8ff7e6"), 0.16))
	# ground shadow
	ci.draw_colored_polygon(rrect_pts(Rect2(cx - rad - 3.0 * u, yb - 3.0 * u, rad * 2.0 + 6.0 * u, 6.0 * u), 3.0 * u), Color(0, 0, 0, 0.22))
	# stone silhouette
	var outer := PackedVector2Array()
	outer.append(Vector2(cx - rad, yb))
	for i in 17:
		var a: float = PI + float(i) / 16.0 * PI
		outer.append(Vector2(cx + cos(a) * rad, yc + sin(a) * rad))
	outer.append(Vector2(cx + rad, yb))
	if sel:
		var rp2: float = 0.5 + 0.5 * sin(tt * 4.0)
		ci.draw_polyline(_closed(outer), _a(Color("a8fff0"), 0.35 + 0.25 * rp2), lw * 6.0, true)
		ci.draw_polyline(_closed(outer), _a(Color("e8fffa"), 0.8), lw * 2.8, true)
	ci.draw_colored_polygon(outer, s_m)
	# lit left pillar / shaded right pillar
	ci.draw_rect(Rect2(cx - rad, yc, pw * 0.42, yb - yc), _a(s_l, 0.85))
	ci.draw_rect(Rect2(cx + rad - pw * 0.4, yc, pw * 0.4, yb - yc), _a(s_d, 0.75))
	# arch ring shading: lit upper-left arc, shaded upper-right arc
	ci.draw_arc(Vector2(cx, yc), rad - pw * 0.2, PI, PI * 1.5, 10, _a(s_l, 0.9), pw * 0.4, true)
	ci.draw_arc(Vector2(cx, yc), rad - pw * 0.8, PI * 1.5, TAU, 10, _a(s_d, 0.7), pw * 0.4, true)
	# stone courses on the pillars + voussoirs
	for k in range(1, 9):
		var yy: float = yc + (yb - yc) * float(k) / 9.0
		ci.draw_line(Vector2(cx - rad, yy), Vector2(cx - ri, yy), _a(s_line, 0.55), maxf(1.0, u), true)
		ci.draw_line(Vector2(cx + ri, yy + (u * 10.0 if k % 2 == 0 else 0.0)), Vector2(cx + rad, yy + (u * 10.0 if k % 2 == 0 else 0.0)), _a(s_line, 0.55), maxf(1.0, u), true)
	for k in range(1, 6):
		var a2: float = PI + float(k) / 6.0 * PI
		var d := Vector2(cos(a2), sin(a2))
		ci.draw_line(Vector2(cx, yc) + d * ri, Vector2(cx, yc) + d * rad, _a(s_line, 0.55), maxf(1.0, u), true)
	ci.draw_polyline(_closed(outer), s_line, lw * 1.3, true)
	# portal water
	var inner := PackedVector2Array()
	inner.append(Vector2(cx - ri, yb))
	for i in 17:
		var a3: float = PI + float(i) / 16.0 * PI
		inner.append(Vector2(cx + cos(a3) * ri, yc + sin(a3) * ri))
	inner.append(Vector2(cx + ri, yb))
	var ic := PackedColorArray()
	var c_top: Color = Color("c8fff4") if sel else Color("6ee8dc")
	var c_mid: Color = Color("42d0d6") if sel else Color("22a6bc")
	var c_bot: Color = Color("1a86b8") if sel else Color("0e5f86")
	if locked:
		c_top = Color("1a3a48")
		c_mid = Color("11303f")
		c_bot = Color("0a2230")
	for p in inner:
		var uu: float = clampf((p.y - y0) / (yb - y0), 0.0, 1.0)
		ic.append(c_top.lerp(c_mid, minf(uu * 2.0, 1.0)).lerp(c_bot, clampf(uu * 2.0 - 1.0, 0.0, 1.0)))
	ci.draw_polygon(inner, ic)
	# water motion: rising light streaks, bubbles, centre glow
	if not locked:
		glow(ci, Vector2(cx, yc + (yb - yc) * 0.35), ri * 1.1, (yb - y0) * 0.45, _a(Color("e8fffa"), 0.5 if sel else 0.26))
		for k in 3:
			var xo: float = (float(k) - 1.0) * ri * 0.5
			var streak := PackedVector2Array()
			for j in 7:
				var v: float = float(j) / 6.0
				var yy2: float = lerpf(yb - 4.0 * u, yc + 4.0 * u, v)
				streak.append(Vector2(cx + xo + sin(tt * 1.3 + v * 5.0 + float(k) * 2.0) * ri * 0.22, yy2))
			ci.draw_polyline(streak, _a(Color.WHITE, 0.16 + 0.1 * (1.0 if sel else 0.0)), maxf(1.5, ri * 0.22), true)
		for k in 5:
			var sv: float = fposmod(float(k) * 0.618, 1.0)
			var ph: float = fposmod(tt * (0.12 + 0.08 * sv) + float(k) * 0.21, 1.0)
			var by: float = lerpf(yb - 6.0 * u, yc - ri * 0.3, ph)
			var bx: float = cx + sin(ph * 6.0 + float(k) * 1.7) * ri * 0.5
			var br: float = maxf(1.3, (1.8 + 1.6 * sv) * u)
			ci.draw_arc(Vector2(bx, by), br, 0.0, TAU, 10, _a(Color.WHITE, 0.8 * minf(1.0, (1.0 - ph) * 3.0)), maxf(1.0, u), true)
		# rising rings of light: the "lift" that carries a resident up into the reef
		for k in 3:
			var ph3: float = fposmod(tt * 0.22 + float(k) / 3.0, 1.0)
			var ry: float = lerpf(yb - 10.0 * u, yc - ri * 0.55, ph3)
			var rw: float = ri * 0.88
			if ry < yc:
				rw = minf(rw, sqrt(maxf(ri * ri - (yc - ry) * (yc - ry), 0.0)) * 0.88)
			var rp := PackedVector2Array()
			for j in 9:
				var xx: float = lerpf(-rw, rw, float(j) / 8.0)
				rp.append(Vector2(cx + xx, ry - (1.0 - (xx / maxf(rw, 1.0)) * (xx / maxf(rw, 1.0))) * 6.0 * u))
			ci.draw_polyline(rp, _a(Color.WHITE, (0.55 if sel else 0.3) * sin(ph3 * PI)), maxf(1.2, 1.6 * u), true)
		if sel:
			for k in 3:
				var ph2: float = fposmod(tt * 0.6 + float(k) / 3.0, 1.0)
				sparkle(ci, Vector2(cx + (float(k) - 1.0) * ri * 0.55, lerpf(yb - 10.0 * u, yc, ph2)), 4.0 * u * sin(ph2 * PI), _a(Color.WHITE, 0.95))
	# inner shadow on the left/top lip, rim highlight on right
	ci.draw_polyline(inner, tint(Color("ff9a86"), st_t), lw * 1.7, true)
	ci.draw_polyline(_closed(inner), _a(s_line, 0.9), lw, true)
	ci.draw_arc(Vector2(cx, yc), ri - lw * 0.8, PI * 1.05, PI * 1.55, 8, _a(Color(0, 0.1, 0.2), 0.35), lw * 1.4, true)
	# keystone with carved scallop
	var kw: float = pw * 0.95
	var ky: float = yc - rad + pw * 0.5
	var key := PackedVector2Array([
		Vector2(cx - kw * 0.55, ky - pw * 0.62), Vector2(cx + kw * 0.55, ky - pw * 0.62),
		Vector2(cx + kw * 0.72, ky + pw * 0.62), Vector2(cx - kw * 0.72, ky + pw * 0.62)])
	_poly(ci, key, coral, coral_d, lw)
	ci.draw_colored_polygon(PackedVector2Array([key[0], key[1], Vector2(cx, ky)]), _a(Color.WHITE, 0.25 if not locked else 0.1))
	draw_shell(ci, Vector2(cx, ky + pw * 0.02), pw * 0.58, tint(Color("ffd0c0"), st_t), tint(Color.WHITE, st_t), coral_d, maxf(1.0, u))
	# carved wave spirals down the pillars
	var carve: Color = _a(s_line, 0.85)
	var nrow: int = 5
	for k in nrow:
		var yy3: float = yc + (yb - yc) * (float(k) + 0.5) / float(nrow)
		for side in 2:
			var sx: float = cx + (-1.0 if side == 0 else 1.0) * (ri + pw * 0.5)
			var sp := PackedVector2Array()
			for j in 9:
				var uu2: float = float(j) / 8.0
				var an: float = uu2 * PI * 2.6 + (0.0 if side == 0 else PI)
				var rr: float = pw * 0.34 * (1.0 - uu2 * 0.75)
				sp.append(Vector2(sx + cos(an) * rr, yy3 + sin(an) * rr))
			ci.draw_polyline(sp, carve, maxf(1.0, 1.3 * u), true)
	# imposts where the arch springs from the pillars
	for side in 2:
		var ix: float = cx - rad - 1.5 * u if side == 0 else cx + ri - 0.5 * u
		var ir := Rect2(ix, yc - 3.5 * u, pw + 2.0 * u, 7.0 * u)
		fill_rrect(ci, ir, 2.0 * u, coral.lightened(0.15), coral_d.lightened(0.1), coral_d.darkened(0.2), lw, 3)
	# footings
	var foot_h: float = 9.0 * u
	for side in 2:
		var fx: float = cx - rad - 3.0 * u if side == 0 else cx + ri - 1.0 * u
		var fr := Rect2(fx, yb - foot_h, pw + 4.0 * u, foot_h)
		fill_rrect(ci, fr, 2.5 * u, s_l if side == 0 else s_m, s_d, s_line, lw, 3)
	# coral growth on the footings
	for side in 2:
		var bx2: float = cx + (-1.0 if side == 0 else 1.0) * (ri + pw * 0.4)
		for k in 3:
			var ang: float = -PI * 0.5 + (float(k) - 1.0) * 0.55 + (0.2 if side == 0 else -0.2)
			var base := Vector2(bx2 + (float(k) - 1.0) * 3.0 * u, yb - foot_h)
			var tip: Vector2 = base + Vector2(cos(ang), sin(ang)) * (13.0 + 4.0 * float((k + side) % 2)) * u
			ci.draw_line(base, tip, coral_d, 4.6 * u, true)
			ci.draw_line(base, tip, coral, 2.8 * u, true)
			ci.draw_circle(tip, 2.4 * u, tint(Color("ffc0cc"), st_t))
	if locked and bool(opts.get("lock", false)):
		draw_lock(ci, Vector2(cx, yc + (yb - yc) * 0.4), w * 0.5)
	if state == STATE_OWNED:
		pass

# ---------------------------------------------------------------- chest

static func _lid_y(x: float) -> float:
	return 0.40 + 0.27 * sqrt(maxf(0.0, 1.0 - (x / 0.46) * (x / 0.46)))

## Offline-earnings chest. state: CHEST_CLOSED / CHEST_FULL (lid ajar, glowing coins) / CHEST_OPEN (empty).
static func draw_chest(ci: CanvasItem, rect: Rect2, state: int, t: float) -> void:
	var u: float = minf(rect.size.x, rect.size.y / 0.95)
	var o := Vector2(rect.position.x + rect.size.x * 0.5, rect.end.y - u * 0.02)
	var lw: float = _lw(u, 0.014, 1.3, 2.2)
	var bl: Color = WOOD_LINE
	var full: bool = state == CHEST_FULL
	var opened: bool = state == CHEST_OPEN
	# shadow
	ci.draw_colored_polygon(rrect_pts(Rect2(o.x - u * 0.52, o.y - u * 0.035, u * 1.04, u * 0.07), u * 0.035), Color(0, 0, 0, 0.25))
	if full:
		var pulse: float = 0.5 + 0.5 * sin(t * 3.0)
		glow(ci, o + Vector2(0.0, -u * 0.5), u * 0.85, u * 0.7, _a(Color("ffe08a"), 0.35 + 0.15 * pulse))
		# rays through the gap
		for k in 3:
			var xo: float = (float(k) - 1.0) * 0.24
			var ray := PackedVector2Array([o + Vector2(xo - 0.07, -0.52) * u, o + Vector2(xo + 0.07, -0.52) * u, o + Vector2(xo * 2.1 + 0.12, -0.98) * u, o + Vector2(xo * 2.1 - 0.12, -0.98) * u])
			var rc := PackedColorArray([_a(Color("fff0b0"), 0.55), _a(Color("fff0b0"), 0.55), _a(Color("fff0b0"), 0.0), _a(Color("fff0b0"), 0.0)])
			ci.draw_polygon(ray, rc)
	if opened:
		# lid standing open behind the body, underside visible
		var back := PackedVector2Array()
		back.append(o + Vector2(-0.44, -0.42) * u)
		for i in 13:
			var a: float = PI + float(i) / 12.0 * PI
			back.append(o + Vector2(cos(a) * 0.44, -0.62 + sin(a) * 0.28 - 0.0) * u)
		back.append(o + Vector2(0.44, -0.42) * u)
		ci.draw_colored_polygon(back, WOOD_D)
		var lin: PackedVector2Array = PackedVector2Array()
		lin.append(o + Vector2(-0.37, -0.44) * u)
		for i in 13:
			var a2: float = PI + float(i) / 12.0 * PI
			lin.append(o + Vector2(cos(a2) * 0.37, -0.62 + sin(a2) * 0.2) * u)
		lin.append(o + Vector2(0.37, -0.44) * u)
		ci.draw_colored_polygon(lin, Color("7b2d3a"))
		ci.draw_colored_polygon(lin, _a(Color("c7566a"), 0.25))
		ci.draw_polyline(_closed(back), bl, lw, true)
		ci.draw_line(o + Vector2(-0.44, -0.6) * u, o + Vector2(-0.44, -0.44) * u, BRASS, lw * 2.2, true)
		ci.draw_line(o + Vector2(0.44, -0.6) * u, o + Vector2(0.44, -0.44) * u, BRASS_D, lw * 2.2, true)
	# interior opening (visible when full / open)
	if full or opened:
		var inn := PackedVector2Array([o + Vector2(-0.43, -0.40) * u, o + Vector2(0.43, -0.40) * u, o + Vector2(0.38, -0.52) * u, o + Vector2(-0.38, -0.52) * u])
		ci.draw_colored_polygon(inn, Color("2a1209"))
		if full:
			ci.draw_colored_polygon(inn, _a(Color("ffd25a"), 0.55))
			# coin mound
			for k in 9:
				var cxk: float = -0.36 + float(k) * 0.09
				var cyk: float = -0.45 - 0.07 * sin(float(k) / 8.0 * PI) - 0.02 * float(k % 2)
				var cr: float = u * 0.068
				ci.draw_circle(o + Vector2(cxk * u, cyk * u), cr + lw * 0.5, GOLD_LINE)
				ci.draw_circle(o + Vector2(cxk * u, cyk * u), cr, GOLD_MID if k % 2 == 0 else GOLD_LIGHT)
		else:
			ci.draw_polyline(PackedVector2Array([o + Vector2(-0.2, -0.43) * u, o + Vector2(-0.05, -0.46) * u, o + Vector2(0.12, -0.43) * u]), _a(Color("5a3a22"), 0.9), lw * 2.0, true)
			ci.draw_circle(o + Vector2(0.18, -0.44) * u, u * 0.032, GOLD_DARK)
	# body
	var body := Rect2(o + Vector2(-0.46, -0.40) * u, Vector2(0.92, 0.40) * u)
	fill_rrect(ci, body, u * 0.03, WOOD_L, WOOD_D, bl, lw * 1.2, 3)
	for k in range(1, 4):
		ci.draw_line(o + Vector2(-0.45, -0.1 * float(k)) * u, o + Vector2(0.45, -0.1 * float(k)) * u, _a(bl, 0.5), maxf(1.0, lw * 0.8), true)
	ci.draw_rect(Rect2(body.position + Vector2(lw, lw), Vector2(u * 0.05, body.size.y - lw * 2.0)), _a(Color("ffd9a8"), 0.35))
	# brass bands + rivets (body)
	for sx in [-0.29, 0.29]:
		var bx: float = float(sx)
		ci.draw_rect(Rect2(o + Vector2(bx - 0.045, -0.40) * u, Vector2(0.09, 0.40) * u), BRASS)
		ci.draw_rect(Rect2(o + Vector2(bx - 0.045, -0.40) * u, Vector2(0.025, 0.40) * u), _a(Color.WHITE, 0.35))
		ci.draw_line(o + Vector2(bx - 0.045, -0.40) * u, o + Vector2(bx - 0.045, 0.0) * u, BRASS_D, lw, true)
		ci.draw_line(o + Vector2(bx + 0.045, -0.40) * u, o + Vector2(bx + 0.045, 0.0) * u, BRASS_D, lw, true)
		ci.draw_circle(o + Vector2(bx, -0.34) * u, u * 0.014, BRASS_D)
		ci.draw_circle(o + Vector2(bx, -0.06) * u, u * 0.014, BRASS_D)
	# corner studs
	ci.draw_circle(o + Vector2(-0.42, -0.04) * u, u * 0.02, BRASS)
	ci.draw_circle(o + Vector2(0.42, -0.04) * u, u * 0.02, BRASS_D)
	# lid
	var dy: float = 0.0
	if full:
		dy = 0.15 + 0.012 * sin(t * 2.0)
	if not opened:
		_chest_lid(ci, o, u, dy, lw)
	# lock plate
	var lp := Rect2(o + Vector2(-0.07, -0.43 - dy * 0.0) * u, Vector2(0.14, 0.16) * u)
	if opened or full:
		lp = Rect2(o + Vector2(-0.07, -0.30) * u, Vector2(0.14, 0.14) * u)
	fill_rrect(ci, lp, u * 0.025, _lt(BRASS, 0.35), BRASS_D, GOLD_LINE, lw, 3)
	ci.draw_circle(lp.position + lp.size * Vector2(0.5, 0.42), u * 0.022, GOLD_LINE)
	ci.draw_rect(Rect2(lp.position + lp.size * Vector2(0.47, 0.45), Vector2(u * 0.012, u * 0.05)), GOLD_LINE)
	# coral growth + shell on the left corner
	var cb: Vector2 = o + Vector2(-0.44, -0.02) * u
	for k in 4:
		var ang: float = -PI * 0.5 + (float(k) - 1.5) * 0.5
		var tip: Vector2 = cb + Vector2(cos(ang), sin(ang)) * u * (0.13 + 0.03 * float(k % 2))
		ci.draw_line(cb + Vector2(float(k) * u * 0.02, 0.0), tip, Color("a83a4a"), u * 0.034, true)
		ci.draw_line(cb + Vector2(float(k) * u * 0.02, 0.0), tip, Color("ff7f8f"), u * 0.02, true)
		ci.draw_circle(tip, u * 0.022, Color("ffc3cc"))
	draw_shell(ci, o + Vector2(0.42, -0.05) * u, u * 0.1, Color("ffd9c2"), Color.WHITE, Color("b86a58"), maxf(1.0, lw * 0.8))
	# twinkles
	if full:
		for k in 4:
			var ph: float = fposmod(t * 0.7 + float(k) * 0.27, 1.0)
			var px: float = (-0.3 + 0.2 * float(k) + 0.04 * sin(t + float(k)))
			sparkle(ci, o + Vector2(px, -0.58 - 0.3 * ph) * u, u * 0.07 * sin(ph * PI), Color(1, 0.97, 0.75, 0.95))
	elif opened:
		var ph2: float = fposmod(t * 0.4, 1.0)
		sparkle(ci, o + Vector2(0.18, -0.46 - 0.2 * ph2) * u, u * 0.045 * sin(ph2 * PI), Color(1, 1, 1, 0.5))

static func _chest_lid(ci: CanvasItem, o: Vector2, u: float, dy: float, lw: float) -> void:
	# lid arch: straight sides then ellipse top; lifted by dy and tilted for the "ajar" look.
	var rot: float = -0.0
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in 17:
		var x: float = -0.46 + 0.92 * float(i) / 16.0
		pts.append(o + Vector2(x, -_lid_y(x) - dy) * u)
		cols.append(WOOD_M.lerp(WOOD_L, clampf(0.5 - x * 0.8, 0.0, 1.0)))
	pts.append(o + Vector2(0.46, -0.40 - dy) * u)
	cols.append(WOOD_D)
	pts.append(o + Vector2(-0.46, -0.40 - dy) * u)
	cols.append(WOOD_D)
	ci.draw_polygon(pts, cols)
	# plank seams following the arch
	for k in range(1, 3):
		var f: float = float(k) / 3.0
		var seam := PackedVector2Array()
		for i in 13:
			var x2: float = -0.45 + 0.9 * float(i) / 12.0
			seam.append(o + Vector2(x2, -(0.40 + (_lid_y(x2) - 0.40) * f) - dy) * u)
		ci.draw_polyline(seam, _a(WOOD_LINE, 0.5), maxf(1.0, lw * 0.8), true)
	# top-left sheen
	var sheen := PackedVector2Array()
	for i in 8:
		var x3: float = -0.40 + 0.5 * float(i) / 7.0
		sheen.append(o + Vector2(x3, -(_lid_y(x3) - 0.035) - dy) * u)
	ci.draw_polyline(sheen, _a(Color("ffe2b8"), 0.5), lw * 1.6, true)
	# brass bands following the arch
	for sx in [-0.29, 0.29]:
		var bx: float = float(sx)
		var band := PackedVector2Array([o + Vector2(bx - 0.045, -0.40 - dy) * u])
		for i in 3:
			var xx: float = bx - 0.045 + 0.09 * float(i) / 2.0
			band.append(o + Vector2(xx, -_lid_y(xx) - dy) * u)
		band.append(o + Vector2(bx + 0.045, -0.40 - dy) * u)
		ci.draw_colored_polygon(band, BRASS)
		ci.draw_line(band[1], band[0], BRASS_D, lw, true)
		ci.draw_line(band[3], band[4], BRASS_D, lw, true)
		ci.draw_line(band[1], band[3], _lt(BRASS, 0.5), maxf(1.0, lw * 0.8), true)
	# outline + brass rim strip
	ci.draw_polyline(_closed(pts), WOOD_LINE, lw * 1.2, true)
	ci.draw_rect(Rect2(o + Vector2(-0.46, -0.42 - dy) * u, Vector2(0.92, 0.04) * u), BRASS)
	ci.draw_line(o + Vector2(-0.46, -0.42 - dy) * u, o + Vector2(0.46, -0.42 - dy) * u, _lt(BRASS, 0.5), maxf(1.0, lw * 0.8), true)
	ci.draw_line(o + Vector2(-0.46, -0.38 - dy) * u, o + Vector2(0.46, -0.38 - dy) * u, BRASS_D, lw, true)

# ---------------------------------------------------------------- card frame

## Rounded sand/teal card for shop and roster rows. Content is drawn by the caller on top.
## opts: "badge" (true) draw the corner lock/tag/seal, "badge_size" (float), "t" (float).
static func draw_card_frame(ci: CanvasItem, rect: Rect2, state: int = 0, opts: Dictionary = {}) -> void:
	var m: float = minf(rect.size.x, rect.size.y)
	var rad: float = clampf(m * 0.16, 8.0, 18.0)
	var top: Color = Color("fbefcf")
	var bot: Color = Color("ecd5a2")
	var line: Color = Pal.SAND_DARK
	var lw: float = 2.0
	match state:
		STATE_LOCKED:
			top = Color("4a6b78")
			bot = Color("33505c")
			line = Color("253b45")
		STATE_UNAFFORDABLE:
			top = Color("e6dccb")
			bot = Color("d2c3a8")
			line = Color("b5584d")
		STATE_OWNED:
			top = Color("eaf6d2")
			bot = Color("c6e2a8")
			line = Color("3f9a64")
		STATE_SELECTED:
			top = Color("fff6d8")
			bot = Color("f4dfa0")
			line = Color("d9a31c")
	if state == STATE_SELECTED:
		var t: float = float(opts.get("t", 0.0))
		glow(ci, rect.get_center(), rect.size.x * 0.62, rect.size.y * 0.78, _a(Color("ffd36a"), 0.34 + 0.08 * sin(t * 4.0)))
	# shadow
	ci.draw_colored_polygon(rrect_pts(Rect2(rect.position + Vector2(0.0, 3.0), rect.size), rad), Color(0, 0, 0, 0.22))
	fill_rrect(ci, rect, rad, top, bot, line, lw)
	var inner: Rect2 = rect.grow(-4.0)
	var tealish: Color = Color("2f9aa8") if state != STATE_LOCKED else Color("8fb2bb")
	ci.draw_polyline(_closed(rrect_pts(inner, rad - 3.0)), _a(tealish, 0.4), 1.5, true)
	ci.draw_line(rect.position + Vector2(rad, 2.5), rect.position + Vector2(rect.size.x - rad, 2.5), _a(Color.WHITE, 0.6 if state != STATE_LOCKED else 0.2), 1.5, true)
	if state == STATE_LOCKED:
		# diagonal "closed shop" stripes along the bottom edge
		var sy: float = rect.end.y - 5.0
		for k in int(rect.size.x / 14.0):
			var x0: float = rect.position.x + rad * 0.6 + float(k) * 14.0
			if x0 + 8.0 < rect.end.x - rad * 0.6:
				ci.draw_line(Vector2(x0, sy), Vector2(x0 + 7.0, sy - 4.0), _a(Color("a6c4cc"), 0.28), 2.0, true)
	if state == STATE_SELECTED:
		# gold ring + corner brackets
		var ring: Rect2 = rect.grow(3.0)
		ci.draw_polyline(_closed(rrect_pts(ring, rad + 3.0)), Color("ffc93d"), 3.0, true)
		var bl: float = clampf(m * 0.22, 10.0, 18.0)
		var ob: Rect2 = rect.grow(6.0)
		for k in 4:
			var cx: float = ob.position.x if k % 2 == 0 else ob.end.x
			var cy: float = ob.position.y if k < 2 else ob.end.y
			var sx: float = 1.0 if k % 2 == 0 else -1.0
			var sy2: float = 1.0 if k < 2 else -1.0
			var br := PackedVector2Array([Vector2(cx + sx * bl, cy), Vector2(cx, cy), Vector2(cx, cy + sy2 * bl)])
			ci.draw_polyline(br, Color("7a4a10"), 5.0, true)
			ci.draw_polyline(br, Color("ffd24d"), 3.0, true)
	if bool(opts.get("badge", true)) and state != STATE_AVAILABLE and state != STATE_SELECTED:
		var bs: float = float(opts.get("badge_size", clampf(m * 0.34, 18.0, 30.0)))
		var bc: Vector2 = Vector2(rect.end.x - bs * 0.62, rect.position.y + bs * 0.62)
		_badge(ci, bc, bs, state)

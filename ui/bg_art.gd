class_name BgArt
extends RefCounted
## Procedural background art for the reef (side view) and the pool (puzzle screen).
## Everything is static functions drawing through CanvasItem draw_* calls. Key light is
## top-left everywhere. Static and animated drawing are separate so callers can cache the
## static layer. No allocations beyond small per-call point arrays.

const HUD_BAND: float = 176.0     ## logical px at the top of the pool kept quiet for HUD chips/text

static var _sb: StyleBoxFlat = null

# --- small helpers ---------------------------------------------------------------------------

static func _h(n: int, salt: float) -> float:
	return fposmod(sin(float(n) * 12.9898 + salt * 78.233) * 43758.5453, 1.0)

static func _a(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)

static func _lit(c: Color, f: float) -> Color:
	return c.lerp(Color(1, 1, 1, c.a), f)

static func _shade(c: Color, f: float) -> Color:
	return c.lerp(Color(0.02, 0.05, 0.12, c.a), f)

static func _ellipse(c: Vector2, rx: float, ry: float, n: int = 14, rot: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cr: float = cos(rot)
	var sr: float = sin(rot)
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var p := Vector2(cos(a) * rx, sin(a) * ry)
		pts.append(c + Vector2(p.x * cr - p.y * sr, p.x * sr + p.y * cr))
	return pts

static func _clamped_circle(c: Vector2, r: float, n: int, clip: Rect2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var p: Vector2 = c + Vector2(cos(a), sin(a)) * r
		pts.append(Vector2(clampf(p.x, clip.position.x, clip.end.x), clampf(p.y, clip.position.y, clip.end.y)))
	return pts

## Soft glow: stacked translucent discs (clipped to `clip`).
static func _halo(ci: CanvasItem, c: Vector2, r: float, col: Color, clip: Rect2, steps: int = 7) -> void:
	for k in steps:
		var f: float = 1.0 - float(k) / float(steps)
		ci.draw_colored_polygon(_clamped_circle(c, r * f, 26, clip), _a(col, 1.0 / float(steps)))

static func _vgrad(ci: CanvasItem, r: Rect2, stops: Array) -> void:
	for i in stops.size() - 1:
		var f0: float = float(stops[i][0])
		var f1: float = float(stops[i + 1][0])
		var c0: Color = stops[i][1]
		var c1: Color = stops[i + 1][1]
		var y0: float = r.position.y + r.size.y * f0
		var y1: float = r.position.y + r.size.y * f1
		ci.draw_polygon(PackedVector2Array([Vector2(r.position.x, y0), Vector2(r.end.x, y0), Vector2(r.end.x, y1), Vector2(r.position.x, y1)]),
			PackedColorArray([c0, c0, c1, c1]))

static func _hgrad(ci: CanvasItem, r: Rect2, c0: Color, c1: Color) -> void:
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([c0, c1, c1, c0]))

static func _rrect(ci: CanvasItem, r: Rect2, radius: float, col: Color, bot: float = 0.0, bot_col: Color = Color(0, 0, 0, 0), top: float = 0.0) -> void:
	if _sb == null:
		_sb = StyleBoxFlat.new()
		_sb.anti_aliasing = true
	_sb.bg_color = col
	_sb.set_corner_radius_all(int(radius))
	_sb.set_border_width_all(0)
	if bot > 0.0:
		_sb.border_width_bottom = int(bot)
		_sb.border_color = bot_col
	if top > 0.0:
		_sb.border_width_top = int(top)
		_sb.border_color = bot_col
	ci.draw_style_box(_sb, r)

static func _smooth(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)

# --- palettes --------------------------------------------------------------------------------

static func palette(phase: int) -> Dictionary:
	var p: Dictionary = Tide.palette(phase).duplicate()
	var e: Dictionary
	match phase:
		Tide.DAWN:
			e = {"water_mid": Color("63a9b6"), "ray_color": Color("ffe0c0"), "far": Color("4f95a6"),
				"kelp_dark": Color("2f8a5e"), "kelp_light": Color("86d89c"),
				"coral_a": Color("ff8fa3"), "coral_b": Color("ffae7a"), "coral_c": Color("c79ae8"),
				"rock_a": Color("b9aaa2"), "rock_b": Color("5d6d77"), "shell": Color("fff0e6"),
				"tile_a": Color("1f8195"), "tile_b": Color("1b7689"), "tile_empty": Color("125e6f"), "gap": Color("0a3340"),
				"board_frame": Color("d4a583"), "board_frame_dark": Color("94694c"), "ink": Color("0b2a33"),
				"fish": Color("1d6376"), "fish_hi": Color("ffd2b4"), "glow": Color("ffc9a8")}
		Tide.DUSK:
			e = {"water_mid": Color("7f6da6"), "ray_color": Color("ffc29a"), "far": Color("5b5a95"),
				"kelp_dark": Color("2e7a62"), "kelp_light": Color("73c498"),
				"coral_a": Color("ff6f8a"), "coral_b": Color("ff9a5c"), "coral_c": Color("a283ea"),
				"rock_a": Color("a090ad"), "rock_b": Color("4d4a6c"), "shell": Color("ffdcd2"),
				"tile_a": Color("266f93"), "tile_b": Color("226288"), "tile_empty": Color("17476a"), "gap": Color("0b1e3f"),
				"board_frame": Color("c98e7d"), "board_frame_dark": Color("8a5a58"), "ink": Color("0b2a33"),
				"fish": Color("2b3a72"), "fish_hi": Color("ffb3a0"), "glow": Color("ff9d7a")}
		Tide.NIGHT:
			e = {"water_mid": Color("0f2a4c"), "ray_color": Color("a9c8ff"), "far": Color("1b4470"),
				"kelp_dark": Color("1d5a50"), "kelp_light": Color("45a98a"),
				"coral_a": Color("c76b9a"), "coral_b": Color("d98a6a"), "coral_c": Color("8a7ad6"),
				"rock_a": Color("6f86a5"), "rock_b": Color("2c3f5e"), "shell": Color("c9d6ea"),
				"tile_a": Color("17506a"), "tile_b": Color("134760"), "tile_empty": Color("0d3347"), "gap": Color("040f1d"),
				"board_frame": Color("62768c"), "board_frame_dark": Color("3a4a60"), "ink": Color("0b2a33"),
				"fish": Color("a8d4f0"), "fish_hi": Color("e6f4ff"), "glow": Color("9bbcf0")}
		_:
			e = {"water_mid": Color("1c93b0"), "ray_color": Color("fff7c8"), "far": Color("1f7f9c"),
				"kelp_dark": Color("1f7a4e"), "kelp_light": Color("66d28c"),
				"coral_a": Color("ff7f95"), "coral_b": Color("ffa05c"), "coral_c": Color("b78cf0"),
				"rock_a": Color("8ba4a8"), "rock_b": Color("4e6870"), "shell": Color("fbe8dc"),
				"tile_a": Color("1b8196"), "tile_b": Color("187789"), "tile_empty": Color("126173"), "gap": Color("072f3b"),
				"board_frame": Color("c9a574"), "board_frame_dark": Color("876943"), "ink": Color("0b2a33"),
				"fish": Color("0c5069"), "fish_hi": Color("ffe3a0"), "glow": Color("fff2b0")}
	p.merge(e, true)
	return p

# --- shared drawing pieces -------------------------------------------------------------------

static func _rock(ci: CanvasItem, base: Vector2, w: float, h: float, seed: int, pal: Dictionary, a: float = 1.0, moss: bool = false) -> void:
	var n: int = 10
	var top := PackedVector2Array()
	var prof: Array = []
	for i in n:
		var u: float = float(i) / float(n - 1)
		var pr: float = pow(sin(PI * u), 0.62) * (0.70 + 0.30 * _h(seed + i, 3.0))
		prof.append(pr)
		top.append(base + Vector2(-w * 0.5 + w * u, -h * pr))
	ci.draw_colored_polygon(_ellipse(base + Vector2(w * 0.06, h * 0.03), w * 0.56, h * 0.10, 16), Color(0, 0, 0, 0.18 * a))
	var body := top.duplicate()
	body.append(base + Vector2(w * 0.5, h * 0.05))
	body.append(base + Vector2(-w * 0.5, h * 0.05))
	var rb: Color = pal["rock_b"]
	var ra: Color = pal["rock_a"]
	ci.draw_colored_polygon(body, _a(_lit(rb, 0.10), a))
	# shaded right flank
	var k: int = int(float(n) * 0.52)
	var sh := PackedVector2Array()
	for i in range(k, n):
		sh.append(top[i])
	sh.append(base + Vector2(w * 0.5, h * 0.05))
	sh.append(base + Vector2(-w * 0.5 + w * float(k) / float(n - 1) - w * 0.04, h * 0.05))
	ci.draw_colored_polygon(sh, _a(_shade(rb, 0.38), a * 0.75))
	# lit crest band, thick where the rock is tall
	var lit := PackedVector2Array()
	for i in n:
		lit.append(top[i])
	for i in range(n - 2, 0, -1):
		var q: float = float(prof[i])
		lit.append(top[i] + Vector2(0.0, 1.0 + h * 0.30 * q * (1.0 - float(i) / float(n))))
	ci.draw_colored_polygon(lit, _a(ra, a * 0.85))
	var crest := PackedVector2Array()
	for i in range(0, int(float(n) * 0.65)):
		crest.append(top[i] + Vector2(0.0, 1.0))
	ci.draw_polyline(crest, _a(_lit(ra, 0.55), a * 0.7), maxf(1.5, w * 0.02), true)
	if moss:
		ci.draw_polyline(top.slice(1, n - 1), _a(pal["kelp_dark"], a * 0.55), maxf(2.0, w * 0.035), true)

static func _brain(ci: CanvasItem, base: Vector2, r: float, col: Color, seed: int, a: float = 1.0) -> void:
	ci.draw_colored_polygon(_ellipse(base + Vector2(r * 0.08, r * 0.03), r * 1.1, r * 0.2, 16), Color(0, 0, 0, 0.16 * a))
	var dome := PackedVector2Array()
	var lit := PackedVector2Array()
	for i in 17:
		var ang: float = PI + PI * float(i) / 16.0
		var wob: float = 1.0 + 0.04 * sin(float(i) * 2.3 + float(seed))
		dome.append(base + Vector2(cos(ang) * r * wob, sin(ang) * r * 0.78 * wob))
		lit.append(base + Vector2(-r * 0.07 + cos(ang) * r * 0.88, sin(ang) * r * 0.74 * wob))
	ci.draw_colored_polygon(dome, _a(_shade(col, 0.30), a))
	ci.draw_colored_polygon(lit, _a(col, a))
	for g in 5:
		var yy: float = -r * 0.78 * (0.14 + 0.17 * float(g))
		var half: float = r * sqrt(maxf(0.0, 1.0 - pow(yy / (r * 0.78), 2.0))) * 0.88
		var pts := PackedVector2Array()
		for j in 9:
			var f: float = float(j) / 8.0
			pts.append(base + Vector2(-half + 2.0 * half * f, yy + sin(f * 9.0 + float(g) * 1.7 + float(seed)) * r * 0.05))
		ci.draw_polyline(pts, _a(_shade(col, 0.42), a * 0.65), maxf(1.4, r * 0.06), true)
	ci.draw_colored_polygon(_ellipse(base + Vector2(-r * 0.34, -r * 0.52), r * 0.26, r * 0.12, 10, -0.5), Color(1, 1, 1, 0.30 * a))

static func _branch(ci: CanvasItem, p: Vector2, ang: float, len: float, wid: float, depth: int, seed: int, col: Color, hi: Color, a: float) -> void:
	var e: Vector2 = p + Vector2(cos(ang), sin(ang)) * len
	ci.draw_line(p, e, _a(col, a), wid, true)
	ci.draw_circle(e, wid * 0.5, _a(col, a))
	if depth == 0:
		ci.draw_circle(e + Vector2(-wid * 0.12, -wid * 0.12), wid * 0.34, _a(hi, a))
		return
	var kids: int = 3 if _h(seed, 5.0) > 0.55 else 2
	for k in kids:
		var da: float = (float(k) - float(kids - 1) * 0.5) * (0.60 + 0.25 * _h(seed + k * 7, 2.0)) + (_h(seed + k, 9.0) - 0.5) * 0.25
		_branch(ci, e, ang + da, len * (0.74 + 0.12 * _h(seed + k * 3, 4.0)), wid * 0.74, depth - 1, seed * 3 + k + 1, col, hi, a)

static func _tubes(ci: CanvasItem, base: Vector2, s: float, col: Color, seed: int, a: float = 1.0) -> void:
	ci.draw_colored_polygon(_ellipse(base + Vector2(s * 4.0, s * 1.0), s * 22.0, s * 4.0, 14), Color(0, 0, 0, 0.14 * a))
	for i in 5:
		var tx: float = base.x + (float(i) - 2.0) * s * 8.5 + (_h(seed + i, 1.0) - 0.5) * s * 3.0
		var th: float = s * (16.0 + 26.0 * _h(seed + i, 2.0))
		var tw: float = s * (7.0 + 4.0 * _h(seed + i, 3.0))
		var by: float = base.y - absf(float(i) - 2.0) * s * 1.5 * 0.0
		var ty: float = by - th
		var left := PackedVector2Array([Vector2(tx - tw * 0.5, by), Vector2(tx - tw * 0.55, ty), Vector2(tx, ty), Vector2(tx, by)])
		var right := PackedVector2Array([Vector2(tx, by), Vector2(tx, ty), Vector2(tx + tw * 0.55, ty), Vector2(tx + tw * 0.5, by)])
		ci.draw_colored_polygon(left, _a(_lit(col, 0.08), a))
		ci.draw_colored_polygon(right, _a(_shade(col, 0.28), a))
		var mouth: Vector2 = Vector2(tx, ty)
		ci.draw_colored_polygon(_ellipse(mouth, tw * 0.56, tw * 0.2, 12), _a(_lit(col, 0.28), a))
		ci.draw_colored_polygon(_ellipse(mouth + Vector2(0, tw * 0.03), tw * 0.40, tw * 0.13, 10), _a(_shade(col, 0.68), a))

static func _fan(ci: CanvasItem, base: Vector2, r: float, col: Color, seed: int, a: float = 1.0) -> void:
	var apex: Vector2 = base + Vector2(0, -r * 0.35)
	ci.draw_line(base, apex, _a(_shade(col, 0.4), a), maxf(2.0, r * 0.07), true)
	var fan := PackedVector2Array()
	fan.append(apex)
	var rim: Array = []
	for i in 13:
		var ang: float = -PI * 0.93 + PI * 0.86 * float(i) / 12.0
		var rr: float = r * (0.92 + 0.10 * sin(float(i) * 1.9 + float(seed)))
		var pt: Vector2 = apex + Vector2(cos(ang) * rr, sin(ang) * rr * 0.9)
		fan.append(pt)
		rim.append(pt)
	ci.draw_colored_polygon(fan, _a(col, a * 0.45))
	for i in range(0, rim.size(), 1):
		ci.draw_line(apex, rim[i], _a(_lit(col, 0.25), a * 0.85), 1.5, true)
	ci.draw_arc(apex, r * 0.62, -PI * 0.93, -PI * 0.07, 14, _a(_lit(col, 0.35), a * 0.8), 1.5, true)
	ci.draw_arc(apex, r * 0.34, -PI * 0.93, -PI * 0.07, 10, _a(_lit(col, 0.35), a * 0.7), 1.3, true)
	ci.draw_polyline(PackedVector2Array(rim), _a(_lit(col, 0.5), a), 2.2, true)

static func _tuft(ci: CanvasItem, base: Vector2, s: float, pal: Dictionary, seed: int, a: float = 1.0) -> void:
	for i in 4:
		var lean: float = (float(i) - 1.5) * s * 4.0 + (_h(seed + i, 1.0) - 0.5) * s * 3.0
		var hh: float = s * (14.0 + 14.0 * _h(seed + i, 2.0))
		var col: Color = pal["kelp_light"] if i % 2 == 0 else pal["kelp_dark"]
		var pts := PackedVector2Array([base + Vector2(lean * 0.2, 0), base + Vector2(lean * 0.5, -hh * 0.55), base + Vector2(lean, -hh)])
		ci.draw_polyline(pts, _a(col, a), maxf(2.0, s * 2.6), true)

static func _scallop(ci: CanvasItem, p: Vector2, s: float, pal: Dictionary, seed: int) -> void:
	var col: Color = pal["shell"]
	var poly := PackedVector2Array()
	poly.append(p)
	for i in 9:
		var ang: float = -PI * 0.92 + PI * 0.84 * float(i) / 8.0
		poly.append(p + Vector2(cos(ang) * s * 1.0, sin(ang) * s * 0.85))
	ci.draw_colored_polygon(_ellipse(p + Vector2(s * 0.2, s * 0.12), s * 1.05, s * 0.22, 10), Color(0, 0, 0, 0.14))
	ci.draw_colored_polygon(poly, col)
	for i in 5:
		var ang2: float = -PI * 0.92 + PI * 0.84 * float(i * 2 + 1) / 10.0 * 1.0
		ci.draw_line(p, p + Vector2(cos(ang2) * s * 0.95, sin(ang2) * s * 0.8), _a(pal["coral_a"], 0.45), 1.0, true)
	ci.draw_rect(Rect2(p + Vector2(-s * 0.25, -s * 0.02), Vector2(s * 0.5, s * 0.16)), _shade(col, 0.25))

static func _spiral(ci: CanvasItem, p: Vector2, s: float, pal: Dictionary) -> void:
	var col: Color = pal["shell"]
	ci.draw_colored_polygon(_ellipse(p + Vector2(s * 0.2, s * 0.5), s * 1.0, s * 0.22, 10), Color(0, 0, 0, 0.14))
	ci.draw_circle(p, s * 0.78, _shade(col, 0.12))
	ci.draw_circle(p + Vector2(-s * 0.08, -s * 0.08), s * 0.66, col)
	ci.draw_arc(p, s * 0.42, 0.4, 5.0, 12, _a(pal["coral_b"], 0.55), 1.3, true)
	ci.draw_arc(p, s * 0.2, 1.5, 6.0, 8, _a(pal["coral_b"], 0.55), 1.2, true)

static func _pebbles(ci: CanvasItem, p: Vector2, s: float, pal: Dictionary, seed: int, n: int) -> void:
	for i in n:
		var q: Vector2 = p + Vector2((_h(seed + i, 1.0) - 0.5) * s * 8.0, (_h(seed + i, 2.0) - 0.3) * s * 2.0)
		var rr: float = s * (1.4 + 1.6 * _h(seed + i, 3.0))
		var col: Color = pal["rock_a"] if i % 2 == 0 else pal["rock_b"]
		ci.draw_colored_polygon(_ellipse(q + Vector2(1, 1.2), rr * 1.1, rr * 0.62, 8), Color(0, 0, 0, 0.14))
		ci.draw_colored_polygon(_ellipse(q, rr, rr * 0.66, 8), _lit(col, 0.05))
		ci.draw_colored_polygon(_ellipse(q + Vector2(-rr * 0.25, -rr * 0.2), rr * 0.45, rr * 0.22, 6), Color(1, 1, 1, 0.22))

static func _sway_blade(ci: CanvasItem, base: Vector2, height: float, wid: float, t: float, seed: float, col: Color, hi: Color, amp: float, a: float, clip: Rect2) -> void:
	var n: int = 8
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var mid := PackedVector2Array()
	for i in n + 1:
		var f: float = float(i) / float(n)
		var sx: float = sin(t * 0.8 + seed + f * 2.4) * amp * pow(f, 1.2) + sin(t * 1.7 + seed * 1.7 + f * 4.0) * amp * 0.18 * f
		var c: Vector2 = Vector2(clampf(base.x + sx, clip.position.x + 1.0, clip.end.x - 1.0), base.y - height * f)
		var hw: float = wid * 0.5 * (1.0 - f * 0.78)
		left.append(c + Vector2(-hw, 0))
		right.append(c + Vector2(hw, 0))
		mid.append(c + Vector2(-hw * 0.35, 0))
	var poly := left.duplicate()
	for i in range(n, -1, -1):
		poly.append(right[i])
	ci.draw_colored_polygon(poly, _a(col, a))
	ci.draw_polyline(mid, _a(hi, a * 0.8), maxf(1.2, wid * 0.22), true)

# ===========================================================================================
# REEF
# ===========================================================================================

static func _reef_scale(rect: Rect2) -> float:
	return clampf(minf(rect.size.x / 520.0, rect.size.y / 340.0), 0.55, 1.6)

static func _sand_y(rect: Rect2, u: float) -> float:
	var h: float = rect.size.y
	var edge: float = pow(absf(u - 0.5) * 2.0, 3.0)
	return rect.position.y + h * (0.800 - 0.032 * edge + sin(u * 5.4 + 1.0) * 0.010 + sin(u * 12.0 + 0.5) * 0.005)

static func draw_reef_far(ci: CanvasItem, rect: Rect2, pal: Dictionary) -> void:
	var w: float = rect.size.x
	var h: float = rect.size.y
	var x0: float = rect.position.x
	var y0: float = rect.position.y
	var rc: Color = pal["ray_color"]
	_vgrad(ci, rect, [[0.0, pal["top"]], [0.55, pal["water_mid"]], [1.0, pal["bottom"]]])
	# sun glow from the top-left (key light)
	_halo(ci, Vector2(x0 + w * 0.10, y0 + h * 0.02), h * 0.95, _a(pal["glow"], 0.20), rect, 8)
	# distant god rays: slanted down and to the right, fading with depth
	var ray_a: float = clampf(float(pal["ray"]) * 2.4, 0.03, 0.30)
	for k in 7:
		var u: float = (float(k) + 0.2 + 0.6 * _h(k, 1.0)) / 7.0
		var xt: float = x0 + w * (u * 1.0 - 0.18)
		var wt: float = w * (0.025 + 0.045 * _h(k, 2.0))
		var xb: float = xt + h * 0.62
		var wb: float = wt * 2.0
		var pts := PackedVector2Array([
			Vector2(clampf(xt, x0, x0 + w), y0), Vector2(clampf(xt + wt, x0, x0 + w), y0),
			Vector2(clampf(xb + wb, x0, x0 + w), y0 + h * 0.92), Vector2(clampf(xb, x0, x0 + w), y0 + h * 0.92)])
		var ca: Color = _a(rc, ray_a * (0.55 + 0.45 * _h(k, 3.0)))
		var cz: Color = _a(rc, 0.0)
		ci.draw_polygon(pts, PackedColorArray([ca, ca, cz, cz]))
	# faraway seabed: soft hills, two arches, thin coral silhouettes. Very low contrast.
	var far: Color = pal["far"]
	var hz: float = y0 + h * 0.70
	var hills := PackedVector2Array()
	hills.append(Vector2(x0, y0 + h * 0.86))
	for i in 25:
		var u2: float = float(i) / 24.0
		hills.append(Vector2(x0 + w * u2, hz + sin(u2 * 7.0 + 0.8) * h * 0.018 + sin(u2 * 15.0) * h * 0.007 - pow(absf(u2 - 0.5) * 2.0, 2.5) * h * 0.05))
	hills.append(Vector2(x0 + w, y0 + h * 0.86))
	ci.draw_colored_polygon(hills, _a(far, 0.42))
	for ar in [[0.27, 0.115, 0.15], [0.74, 0.10, 0.13]]:
		var cx: float = x0 + w * float(ar[0])
		var rr: float = h * float(ar[1])
		var th: float = h * float(ar[2]) * 0.34
		ci.draw_arc(Vector2(cx, hz + h * 0.04), rr, PI, TAU, 22, _a(far, 0.40), th, true)
		ci.draw_colored_polygon(_ellipse(Vector2(cx - rr, hz + h * 0.04), th * 0.8, th * 1.1, 10), _a(far, 0.40))
		ci.draw_colored_polygon(_ellipse(Vector2(cx + rr, hz + h * 0.04), th * 0.8, th * 1.1, 10), _a(far, 0.40))
	for i in 7:
		var bx: float = x0 + w * (0.06 + 0.88 * _h(i, 11.0))
		var by: float = hz + h * 0.05 + _h(i, 12.0) * h * 0.04
		var hh: float = h * (0.05 + 0.06 * _h(i, 13.0))
		for j in 3:
			var dx: float = (float(j) - 1.0) * hh * 0.34
			ci.draw_line(Vector2(bx, by), Vector2(bx + dx * 1.3, by - hh * (0.8 + 0.25 * float(j % 2))), _a(far, 0.32), maxf(2.0, hh * 0.12), true)
	# atmospheric haze: fades the far layer into the water
	var haze: Color = pal["water_mid"].lerp(pal["bottom"], 0.45)
	ci.draw_polygon(PackedVector2Array([Vector2(x0, y0 + h * 0.52), Vector2(x0 + w, y0 + h * 0.52), Vector2(x0 + w, y0 + h * 0.88), Vector2(x0, y0 + h * 0.88)]),
		PackedColorArray([_a(haze, 0.0), _a(haze, 0.0), _a(haze, 0.40), _a(haze, 0.40)]))

static func draw_reef_mid(ci: CanvasItem, rect: Rect2, pal: Dictionary) -> void:
	var w: float = rect.size.x
	var h: float = rect.size.y
	var x0: float = rect.position.x
	var y0: float = rect.position.y
	var s: float = _reef_scale(rect)
	var sand: Color = pal["sand"]
	var sand2: Color = pal["sand2"]
	# --- back dune: lit crest fading to the deeper sand
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var crest := PackedVector2Array()
	for i in 41:
		var u: float = float(i) / 40.0
		var p := Vector2(x0 + w * u, _sand_y(rect, u))
		pts.append(p)
		cols.append(_lit(sand, 0.12))
		crest.append(p + Vector2(0, 1.5))
	pts.append(Vector2(x0 + w, y0 + h))
	cols.append(sand2)
	pts.append(Vector2(x0, y0 + h))
	cols.append(sand2)
	ci.draw_polygon(pts, cols)
	# --- coral and rock groups standing on the back dune (edges; centre stays open)
	var items: Array = [
		# [kind, u, depth_offset, size, seed]
		["rock", 0.045, 0.012, 1.0, 3], ["rock", 0.965, 0.014, 0.95, 8],
		["branch", 0.155, 0.022, 0.9, 5], ["branch", 0.915, 0.020, 1.0, 12],
		["tubes", 0.020, 0.040, 1.0, 21], ["fan", 0.865, 0.016, 0.9, 4],
		["brain", 0.105, 0.030, 1.0, 2], ["brain", 0.975, 0.045, 0.75, 6],
		["rocksm", 0.235, 0.020, 0.5, 31], ["rocksm", 0.775, 0.022, 0.55, 34],
		["branch", 0.255, 0.012, 0.45, 40], ["fan", 0.700, 0.014, 0.48, 41],
	]
	var order: Array = items.duplicate()
	order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[2]) < float(b[2]))
	for it in order:
		var u: float = float(it[1])
		var base := Vector2(x0 + w * u, _sand_y(rect, u) + h * float(it[2]))
		var sz: float = float(it[3]) * s
		var seed: int = int(it[4])
		var far_a: float = 1.0 if sz > 0.7 * s else 0.8
		match String(it[0]):
			"rock":
				_rock(ci, base, 150.0 * sz, 100.0 * sz, seed, pal, 1.0, true)
			"rocksm":
				_rock(ci, base, 84.0 * sz, 48.0 * sz, seed, pal, far_a)
			"branch":
				_branch(ci, base, -PI * 0.5, 30.0 * sz, 9.5 * sz, 2, seed, pal["coral_a"], _lit(pal["coral_a"], 0.5), far_a)
			"tubes":
				_tubes(ci, base, sz * 1.3, pal["coral_c"], seed)
			"fan":
				_fan(ci, base, 54.0 * sz, pal["coral_c"], seed, far_a)
			"brain":
				_brain(ci, base, 36.0 * sz, pal["coral_b"], seed)
	# --- front dune with its own highlight
	var f_pts := PackedVector2Array()
	var f_cols := PackedColorArray()
	var f_crest := PackedVector2Array()
	for i in 41:
		var u3: float = float(i) / 40.0
		var yy: float = y0 + h * (0.885 + sin(u3 * 4.3 + 2.0) * 0.014 + sin(u3 * 9.0 + 1.0) * 0.006 - pow(absf(u3 - 0.5) * 2.0, 3.0) * 0.018)
		f_pts.append(Vector2(x0 + w * u3, yy))
		f_cols.append(_lit(sand, 0.06))
		f_crest.append(Vector2(x0 + w * u3, yy + 1.0))
	f_pts.append(Vector2(x0 + w, y0 + h))
	f_cols.append(_shade(sand2, 0.10))
	f_pts.append(Vector2(x0, y0 + h))
	f_cols.append(_shade(sand2, 0.10))
	# soft shadow where the front dune overlaps the back dune
	ci.draw_polyline(f_crest, _a(_shade(sand2, 0.4), 0.22), 7.0 * s, true)
	ci.draw_polygon(f_pts, f_cols)
	ci.draw_polyline(f_crest, _a(_lit(sand, 0.6), 0.55), 2.0, true)
	ci.draw_polyline(crest, _a(_lit(sand, 0.65), 0.50), 2.0, true)
	# sand ripples
	for r in 8:
		var ry: float = y0 + h * (0.915 + 0.075 * _h(r, 1.0))
		var rx: float = x0 + w * (0.04 + 0.78 * _h(r, 2.0))
		var rl: float = w * (0.10 + 0.10 * _h(r, 3.0))
		var rp := PackedVector2Array()
		for j in 9:
			var f: float = float(j) / 8.0
			rp.append(Vector2(rx + rl * f, ry + sin(f * PI * 2.0 + float(r)) * 1.6 * s))
		ci.draw_polyline(rp, _a(_lit(sand, 0.7), 0.30), 1.6, true)
		for j in 9:
			rp[j] += Vector2(0, 3.0 * s)
		ci.draw_polyline(rp, _a(_shade(sand2, 0.35), 0.18), 1.6, true)
	# shells, pebbles, grass tufts on the lower sand
	_scallop(ci, Vector2(x0 + w * 0.34, y0 + h * 0.935), 8.0 * s, pal, 1)
	_spiral(ci, Vector2(x0 + w * 0.60, y0 + h * 0.955), 6.0 * s, pal)
	_scallop(ci, Vector2(x0 + w * 0.79, y0 + h * 0.925), 6.0 * s, pal, 3)
	_pebbles(ci, Vector2(x0 + w * 0.46, y0 + h * 0.965), s, pal, 7, 3)
	_pebbles(ci, Vector2(x0 + w * 0.185, y0 + h * 0.95), s, pal, 17, 3)
	_pebbles(ci, Vector2(x0 + w * 0.88, y0 + h * 0.965), s, pal, 27, 2)
	for tp in [[0.06, 0.945, 5], [0.205, 0.915, 9], [0.39, 0.90, 13], [0.665, 0.905, 17], [0.93, 0.94, 22]]:
		_tuft(ci, Vector2(x0 + w * float(tp[0]), y0 + h * float(tp[1])), 0.8 * s, pal, int(tp[2]), 0.95)
	# tide tint
	var ov: Color = pal["overlay"]
	if ov.a > 0.0:
		ci.draw_rect(rect, _a(ov, 0.9))

static func draw_reef_front(ci: CanvasItem, rect: Rect2, pal: Dictionary, t: float, animate: bool) -> void:
	var tt: float = t if animate else 6.5
	var w: float = rect.size.x
	var h: float = rect.size.y
	var x0: float = rect.position.x
	var y0: float = rect.position.y
	var s: float = _reef_scale(rect)
	# kelp, edges only
	var kelp: Array = [[0.020, 0.50, 11.0], [0.075, 0.36, 9.0], [0.135, 0.26, 7.0],
		[0.870, 0.30, 8.0], [0.935, 0.50, 11.0], [0.985, 0.38, 9.0]]
	for i in kelp.size():
		var u: float = float(kelp[i][0])
		var base := Vector2(x0 + w * u, _sand_y(rect, u) + h * 0.05)
		var col: Color = pal["kelp_dark"] if i % 2 == 0 else pal["kelp_dark"].lerp(pal["kelp_light"], 0.35)
		_sway_blade(ci, base, h * float(kelp[i][1]), float(kelp[i][2]) * s, tt, float(i) * 1.9, col, pal["kelp_light"], 9.0 * s, 0.92, rect)
	# bubbles from two vents
	var bub: Color = pal["bubble"]
	for k in 7:
		var vx: float = x0 + w * (0.31 if k % 2 == 0 else 0.69)
		var spd: float = 0.07 + 0.05 * _h(k, 4.0)
		var f: float = fposmod(tt * spd + _h(k, 5.0), 1.0)
		var by: float = lerpf(y0 + h * 0.90, y0 + h * 0.06, f)
		var bx: float = vx + sin(tt * 1.3 + float(k) * 2.0) * 6.0 * s + (_h(k, 6.0) - 0.5) * 16.0 * s
		var rr: float = (2.0 + 2.8 * _h(k, 7.0)) * s * (0.6 + 0.4 * f)
		var fade: float = _smooth(0.0, 0.08, f) * (1.0 - _smooth(0.88, 1.0, f))
		ci.draw_arc(Vector2(bx, by), rr, 0.0, TAU, 10, _a(bub, fade), 1.3, true)
		ci.draw_arc(Vector2(bx, by), rr * 0.62, PI * 1.05, PI * 1.55, 4, _a(Color.WHITE, 0.7 * fade), 1.2, true)
	# drifting light motes
	for k in 9:
		var mx: float = x0 + w * fposmod(_h(k, 8.0) + tt * (0.004 + 0.004 * _h(k, 9.0)) * (1.0 if k % 2 == 0 else -1.0), 1.0)
		var my: float = y0 + h * (0.12 + 0.62 * _h(k, 10.0)) + sin(tt * 0.5 + float(k) * 1.7) * 6.0 * s
		var tw: float = 0.5 + 0.5 * sin(tt * 1.1 + float(k) * 2.3)
		ci.draw_circle(Vector2(mx, my), (1.1 + 0.9 * _h(k, 11.0)) * s, _a(pal["ray_color"], 0.15 + 0.35 * tw))
	# ambient fish: two small schools crossing the water
	var fc: Color = pal["fish"]
	var school: Array = [[5, 0.26, 26.0, 1.0, 0.0, 12.0], [4, 0.46, 34.0, -1.0, 0.45, 15.0], [3, 0.62, 41.0, 1.0, 0.7, 10.0]]
	for si in school.size():
		var sc: Array = school[si]
		var span: float = w + 90.0 * s
		var prog: float = fposmod(tt / float(sc[2]) + float(sc[4]), 1.0)
		var dir: float = float(sc[3])
		var lead: float = (prog * span - 45.0 * s) if dir > 0.0 else (w + 45.0 * s - prog * span)
		for j in int(sc[0]):
			var fx: float = x0 + lead - dir * (float(j) * 13.0 + _h(j + si * 9, 1.0) * 10.0) * s
			var fy: float = y0 + h * float(sc[1]) + (_h(j + si * 9, 2.0) - 0.5) * 26.0 * s + sin(tt * 0.9 + float(j) * 1.3) * 3.0 * s
			if fx < x0 + 6.0 or fx > x0 + w - 6.0:
				continue
			var edge: float = minf(_smooth(x0, x0 + 40.0 * s, fx), 1.0 - _smooth(x0 + w - 40.0 * s, x0 + w, fx))
			var len: float = float(sc[5]) * s * (0.85 + 0.3 * _h(j + si, 3.0))
			var wag: float = sin(tt * 9.0 + float(j) * 2.1 + float(si)) * 0.12
			var body := PackedVector2Array()
			var shape: Array = [[0.5, 0.0], [0.3, -0.22], [0.0, -0.28], [-0.3, -0.18], [-0.5, -0.04], [-0.80, -0.30 + wag], [-0.80, 0.30 + wag], [-0.5, 0.04], [-0.3, 0.18], [0.0, 0.28], [0.3, 0.22]]
			for q in shape:
				body.append(Vector2(fx + dir * float(q[0]) * len, fy + float(q[1]) * len))
			var col: Color = pal["fish"] if si != 2 else pal["fish_hi"]
			ci.draw_colored_polygon(body, _a(col, (0.62 if si != 2 else 0.5) * edge))

# ===========================================================================================
# POOL
# ===========================================================================================

## 0 where detail must stay calm (HUD band, directly around the board), rising to 1 further out.
static func _quiet(p: Vector2, g: Rect2) -> float:
	var gr: Rect2 = g.grow(18.0)
	var dx: float = maxf(maxf(gr.position.x - p.x, p.x - gr.end.x), 0.0)
	var dy: float = maxf(maxf(gr.position.y - p.y, p.y - gr.end.y), 0.0)
	var d: float = sqrt(dx * dx + dy * dy)
	var m: float = _smooth(0.0, 44.0, d)
	return m * (0.30 + 0.70 * _smooth(HUD_BAND - 6.0, HUD_BAND + 40.0, p.y))

static func draw_pool_backdrop_static(ci: CanvasItem, rect: Rect2, grid_rect: Rect2, pal: Dictionary) -> void:
	var w: float = rect.size.x
	var h: float = rect.size.y
	var x0: float = rect.position.x
	var y0: float = rect.position.y
	var bt: Color = pal["bg_top"]
	var bb: Color = pal["bg_bottom"]
	var mid: Color = bt.lerp(bb, 0.62)
	# --- water: surface teal at the top (HUD band), deeper around the board
	_vgrad(ci, rect, [[0.0, bt.lerp(bb, 0.12)], [0.20, bt.lerp(bb, 0.40)], [0.42, mid], [0.80, bb.lerp(mid, 0.35)], [1.0, bb]])
	var ov: Color = pal["overlay"]
	if ov.a > 0.0:
		ci.draw_rect(rect, _a(ov, 0.8))
	# light entering from the top-left: only in the lower/side parts, never over the board
	var rc: Color = pal["ray_color"]
	_halo(ci, Vector2(x0 - w * 0.05, y0 + h * 0.52), w * 0.62, _a(pal["glow"], 0.07), rect, 6)
	_halo(ci, Vector2(x0 + w * 0.35, y0 + h * 0.96), w * 0.55, _a(pal["glow"], 0.07), rect, 6)
	for k in 6:
		var xt: float = x0 + w * (-0.15 + 0.22 * float(k) + 0.05 * _h(k, 1.0))
		var wt: float = w * (0.05 + 0.05 * _h(k, 2.0))
		var sl: float = h * 0.55
		var cc: Color = _a(rc, 0.030 + 0.015 * _h(k, 3.0))
		var cz: Color = _a(rc, 0.0)
		var cl: Callable = func(x: float) -> float: return clampf(x, x0, x0 + w)
		ci.draw_polygon(PackedVector2Array([Vector2(cl.call(xt), y0), Vector2(cl.call(xt + wt), y0), Vector2(cl.call(xt + sl + wt * 2.0), y0 + h * 0.85), Vector2(cl.call(xt + sl), y0 + h * 0.85)]), PackedColorArray([cc, cc, cz, cz]))
	# --- distant layer: dark far rocks and kelp silhouettes along the sides, reef-like bumps at the floor
	var far: Color = _shade(pal["far"], 0.35)
	for side in 2:
		var sx: float = x0 if side == 0 else x0 + w
		var dir: float = 1.0 if side == 0 else -1.0
		for i in 5:
			var bx: float = sx + dir * (2.0 + float(i) * 7.0 + _h(i + side * 7, 1.0) * 6.0)
			var hh: float = h * (0.10 + 0.17 * _h(i + side * 7, 2.0))
			var pts := PackedVector2Array()
			for j in 7:
				var f: float = float(j) / 6.0
				pts.append(Vector2(bx + dir * sin(f * 3.0 + float(i) + float(side)) * 9.0, y0 + h * 0.84 - hh * f))
			ci.draw_polyline(pts, _a(far, 0.30), 6.5 - float(i) * 0.5, true)
	var hills := PackedVector2Array()
	hills.append(Vector2(x0, y0 + h))
	for i in 28:
		var u: float = float(i) / 27.0
		hills.append(Vector2(x0 + w * u, y0 + h * (0.770 + 0.02 * sin(u * 6.5 + 1.0) + 0.008 * sin(u * 17.0))))
	hills.append(Vector2(x0 + w, y0 + h))
	ci.draw_colored_polygon(hills, _a(far, 0.30))
	# --- static caustic network: soft light cells, only where the mask allows
	for gy in range(int(y0 / 44.0), int((y0 + h) / 44.0) + 1):
		for gx in range(-1, int(w / 44.0) + 1):
			var n: int = gx * 131 + gy * 977 + 7
			var c: Vector2 = Vector2(x0 + (float(gx) + 0.5 + (_h(n, 1.0) - 0.5) * 0.9) * 44.0, y0 + (float(gy) + 0.5 + (_h(n, 2.0) - 0.5) * 0.9) * 44.0)
			var m: float = _quiet(c, grid_rect)
			if m < 0.06 or c.y > y0 + h * 0.84:
				continue
			var cell := PackedVector2Array()
			var rr: float = 12.0 + 10.0 * _h(n, 3.0)
			var rot: float = _h(n, 4.0) * TAU
			for j in 6:
				var a: float = rot + TAU * float(j) / 6.0
				var q: float = rr * (0.7 + 0.5 * _h(n + j, 5.0))
				cell.append(c + Vector2(cos(a) * q, sin(a) * q * 0.7))
			cell.append(cell[0])
			ci.draw_polyline(cell, _a(rc, 0.12 * m), 1.6, true)
			ci.draw_colored_polygon(_ellipse(c, rr * 0.42, rr * 0.28, 8, rot), _a(rc, 0.05 * m))
	# deep shadow pooled around the board keeps the surroundings calm and lets the frame float
	for k in 8:
		_rrect(ci, grid_rect.grow(36.0 - float(k) * 4.0), 32.0 - float(k) * 3.0, Color(0.0, 0.03, 0.08, 0.05))
	# --- shore: shallow wet edge, sand floor, rocks, shells
	var sand: Color = pal["sand"].lerp(bb, 0.08)
	var sand2: Color = pal["sand2"].lerp(bb, 0.22)
	var shore := PackedVector2Array()
	var scol := PackedColorArray()
	var wet := PackedVector2Array()
	for i in 41:
		var u2: float = float(i) / 40.0
		var yy: float = y0 + h * (0.835 + 0.016 * sin(u2 * 5.0 + 0.5) + 0.008 * sin(u2 * 13.0 + 2.0) - 0.03 * pow(absf(u2 - 0.5) * 2.0, 3.0))
		shore.append(Vector2(x0 + w * u2, yy))
		scol.append(_lit(sand, 0.10))
		wet.append(Vector2(x0 + w * u2, yy))
	var wet_poly := PackedVector2Array()
	var wet_col := PackedColorArray()
	for i in wet.size():
		wet_poly.append(wet[i] + Vector2(0, -h * 0.13))
		wet_col.append(_a(pal["water_mid"], 0.0))
	for i in range(wet.size() - 1, -1, -1):
		wet_poly.append(wet[i])
		wet_col.append(_a(pal["water_mid"], 0.55))
	ci.draw_polygon(wet_poly, wet_col)
	shore.append(Vector2(x0 + w, y0 + h))
	scol.append(sand2)
	shore.append(Vector2(x0, y0 + h))
	scol.append(sand2)
	ci.draw_polygon(shore, scol)
	ci.draw_polyline(wet, _a(Color.WHITE, 0.30), 2.0, true)
	for r in 6:
		var ry: float = y0 + h * (0.88 + 0.09 * _h(r, 1.0))
		var rx: float = x0 + w * (0.02 + 0.72 * _h(r, 2.0))
		var rp := PackedVector2Array()
		for j in 8:
			var f: float = float(j) / 7.0
			rp.append(Vector2(rx + w * 0.16 * f, ry + sin(f * TAU + float(r)) * 2.0))
		ci.draw_polyline(rp, _a(_lit(sand, 0.6), 0.22), 1.5, true)
	# corner rocks (lit from the top-left), clusters overlapping
	var fl: float = y0 + h
	_rock(ci, Vector2(x0 + w * 0.04, fl - h * 0.015), w * 0.30, h * 0.115, 5, pal, 1.0, true)
	_rock(ci, Vector2(x0 + w * 0.20, fl - h * 0.005), w * 0.20, h * 0.065, 12, pal, 1.0)
	_rock(ci, Vector2(x0 + w * 0.97, fl - h * 0.02), w * 0.34, h * 0.13, 9, pal, 1.0, true)
	_rock(ci, Vector2(x0 + w * 0.78, fl), w * 0.16, h * 0.05, 15, pal, 1.0)
	# sea-floor life under the board (below the frame): corals peeking, shells, tufts
	var cb: float = y0 + h * 0.865
	_branch(ci, Vector2(x0 + w * 0.34, cb + 6.0), -PI * 0.5, 15.0, 5.5, 2, 3, pal["coral_a"], _lit(pal["coral_a"], 0.5), 0.9)
	_brain(ci, Vector2(x0 + w * 0.60, cb + 12.0), 17.0, pal["coral_b"], 4)
	_fan(ci, Vector2(x0 + w * 0.46, cb + 7.0), 26.0, pal["coral_c"], 2, 0.9)
	_tubes(ci, Vector2(x0 + w * 0.70, cb + 12.0), 0.55, pal["coral_c"], 17)
	_scallop(ci, Vector2(x0 + w * 0.12, y0 + h * 0.935), 7.0, pal, 1)
	_spiral(ci, Vector2(x0 + w * 0.55, y0 + h * 0.965), 5.5, pal)
	_scallop(ci, Vector2(x0 + w * 0.86, y0 + h * 0.94), 6.0, pal, 2)
	_pebbles(ci, Vector2(x0 + w * 0.40, y0 + h * 0.955), 1.0, pal, 21, 4)
	_pebbles(ci, Vector2(x0 + w * 0.68, y0 + h * 0.975), 0.9, pal, 31, 3)
	for tp in [[0.30, 0.90, 5], [0.52, 0.915, 9], [0.74, 0.90, 14]]:
		_tuft(ci, Vector2(x0 + w * float(tp[0]), y0 + h * float(tp[1])), 0.8, pal, int(tp[2]), 0.95)
	# rocky walls down both edges of the pool (narrow: most of the width belongs to the board)
	var wall: Color = pal["rock_b"].lerp(bb, 0.62)
	for side in 2:
		var dir2: float = 1.0 if side == 0 else -1.0
		var ax: float = x0 if side == 0 else x0 + w
		var wp := PackedVector2Array([Vector2(ax, y0)])
		var edge_line := PackedVector2Array()
		for i in 25:
			var f: float = float(i) / 24.0
			var ww: float = 8.0 + 7.0 * sin(f * 11.0 + float(side) * 2.0) + 9.0 * _h(i + side * 31, 6.0)
			ww *= 0.6 + 1.3 * pow(1.0 - f, 6.0) * 1.0 + 0.9 * pow(f, 6.0)
			var pt := Vector2(ax + dir2 * ww, y0 + h * 0.86 * f)
			wp.append(pt)
			edge_line.append(pt)
		wp.append(Vector2(ax, y0 + h * 0.86))
		ci.draw_colored_polygon(wp, _a(wall, 0.85))
		ci.draw_polyline(edge_line, _a(_lit(pal["rock_a"], 0.2), 0.10 if side == 0 else 0.05), 2.0, true)
		ci.draw_polyline(edge_line, _a(pal["kelp_dark"].lerp(bb, 0.55), 0.35), 5.0, true)
	# edge vignette keeps the sides soft and the middle readable
	var vg: Color = Color(0.0, 0.03, 0.08, 0.28)
	_hgrad(ci, Rect2(x0, y0, 40.0, h), vg, _a(vg, 0.0))
	_hgrad(ci, Rect2(x0 + w - 40.0, y0, 40.0, h), _a(vg, 0.0), vg)

static func draw_pool_backdrop_anim(ci: CanvasItem, rect: Rect2, grid_rect: Rect2, pal: Dictionary, t: float, animate: bool) -> void:
	var tt: float = t if animate else 3.0
	var w: float = rect.size.x
	var h: float = rect.size.y
	var x0: float = rect.position.x
	var y0: float = rect.position.y
	var rc: Color = pal["ray_color"]
	# slow caustic shimmer: soft bright streaks that breathe, only outside the quiet zone
	for k in 14:
		var base := Vector2(x0 + w * _h(k, 21.0), y0 + h * (0.24 + 0.58 * _h(k, 22.0)))
		var c: Vector2 = base + Vector2(sin(tt * 0.21 + float(k)) * 12.0, cos(tt * 0.17 + float(k) * 1.3) * 7.0)
		var m: float = _quiet(c, grid_rect)
		if m < 0.1:
			continue
		var br: float = 0.5 + 0.5 * sin(tt * 0.6 + float(k) * 2.1)
		ci.draw_colored_polygon(_ellipse(c, 26.0 + 14.0 * _h(k, 23.0), 7.0 + 3.0 * _h(k, 24.0), 10, -0.35), _a(rc, (0.035 + 0.055 * br) * m))
	# a little kelp at the edges (kept inside the lower/side margins)
	var clip: Rect2 = rect
	var kelp: Array = [[0.012, 0.19, 12.0, 0.0], [0.045, 0.12, 9.0, 1.7], [0.990, 0.20, 12.0, 3.1], [0.955, 0.125, 9.0, 4.4]]
	for kk in kelp:
		var base2 := Vector2(x0 + w * float(kk[0]), y0 + h * 0.985)
		_sway_blade(ci, base2, h * float(kk[1]), float(kk[2]), tt, float(kk[3]), pal["kelp_dark"], pal["kelp_light"], 9.0, 0.85, clip)
	# two short strands hanging from the top corners: dark, so the HUD band stays calm
	for side in 2:
		var hx: float = x0 + 16.0 if side == 0 else x0 + w - 16.0
		_sway_blade(ci, Vector2(hx, y0 + 52.0), -60.0, 7.0, tt, float(side) * 2.0 + 0.5, _shade(pal["kelp_dark"], 0.45), _shade(pal["kelp_dark"], 0.1), 5.0, 0.7, clip)
	# drifting motes
	for k in 8:
		var mx: float = x0 + w * _h(k, 31.0) + sin(tt * 0.3 + float(k)) * 8.0
		var my: float = y0 + h * fposmod(_h(k, 32.0) - tt * 0.006 * (0.6 + _h(k, 33.0)), 1.0)
		var mm: float = _quiet(Vector2(mx, my), grid_rect)
		if mm < 0.2:
			continue
		ci.draw_circle(Vector2(mx, my), 1.3 + _h(k, 34.0), _a(rc, 0.28 * mm))

# --- board frame and tiles --------------------------------------------------------------------

static func draw_board_frame(ci: CanvasItem, grid_rect: Rect2, pal: Dictionary) -> void:
	var rim: Rect2 = grid_rect.grow(8.0)
	var wood: Color = pal["board_frame"]
	var dark: Color = pal["board_frame_dark"]
	# soft shadow on the water (down-right of the key light)
	_rrect(ci, rim.grow(4.0), 22.0, Color(0, 0.02, 0.06, 0.10))
	_rrect(ci, Rect2(rim.position + Vector2(3, 4), rim.size).grow(1.0), 20.0, Color(0, 0.02, 0.06, 0.26))
	# rim: darker base, lit slab on top-left
	_rrect(ci, rim, 18.0, dark)
	_rrect(ci, Rect2(rim.position, rim.size - Vector2(2, 3)), 18.0, wood)
	# light along the top-left edge, shade along the bottom-right
	var tl := PackedVector2Array([Vector2(rim.position.x + 10, rim.position.y + 1.5), Vector2(rim.end.x - 14, rim.position.y + 1.5)])
	ci.draw_polyline(tl, _a(_lit(wood, 0.6), 0.65), 1.6, true)
	ci.draw_polyline(PackedVector2Array([Vector2(rim.position.x + 1.5, rim.position.y + 12), Vector2(rim.position.x + 1.5, rim.end.y - 16)]), _a(_lit(wood, 0.5), 0.45), 1.4, true)
	# driftwood grain: faint long strokes in the four bands
	var gr: Color = _a(dark, 0.30)
	for i in 3:
		var yy: float = rim.position.y + 2.5 + float(i) * 2.3
		var o: float = 14.0 + 40.0 * _h(i, 3.0)
		ci.draw_polyline(PackedVector2Array([Vector2(rim.position.x + o, yy), Vector2(rim.position.x + o + rim.size.x * 0.28, yy + 0.6), Vector2(rim.position.x + o + rim.size.x * 0.52, yy - 0.4)]), gr, 1.0, true)
		var yb: float = rim.end.y - 5.5 + float(i) * 1.8
		ci.draw_polyline(PackedVector2Array([Vector2(rim.end.x - o - rim.size.x * 0.4, yb), Vector2(rim.end.x - o, yb + 0.5)]), gr, 1.0, true)
	# inner water bed
	var bed: Rect2 = grid_rect.grow(1.0)
	_rrect(ci, bed, 11.0, pal["gap"])
	# inner shade top/left (the rim casts it), faint light bottom/right
	var sh: Color = Color(0, 0.02, 0.06, 0.34)
	ci.draw_polygon(PackedVector2Array([bed.position + Vector2(9, 0), Vector2(bed.end.x - 9, bed.position.y), Vector2(bed.end.x - 9, bed.position.y + 7), bed.position + Vector2(9, 7)]), PackedColorArray([sh, sh, _a(sh, 0), _a(sh, 0)]))
	ci.draw_polygon(PackedVector2Array([bed.position + Vector2(0, 9), bed.position + Vector2(7, 9), Vector2(bed.position.x + 7, bed.end.y - 9), Vector2(bed.position.x, bed.end.y - 9)]), PackedColorArray([sh, _a(sh, 0), _a(sh, 0), sh]))
	ci.draw_polyline(PackedVector2Array([Vector2(bed.position.x + 12, bed.end.y - 0.5), Vector2(bed.end.x - 12, bed.end.y - 0.5)]), _a(_lit(pal["tile_empty"], 0.3), 0.5), 1.2, true)
	# stones and a shell seated in the rim: corners and a few spots along the edges
	var spots: Array = [[0.0, 0.0, 1.0], [1.0, 0.0, 0.9], [0.0, 1.0, 0.95], [1.0, 1.0, 1.0], [0.62, 0.0, 0.55], [0.0, 0.58, 0.55], [1.0, 0.36, 0.55], [0.3, 1.0, 0.6]]
	for i in spots.size():
		var sp: Array = spots[i]
		var cpos := Vector2(rim.position.x + rim.size.x * float(sp[0]), rim.position.y + rim.size.y * float(sp[1]))
		cpos += Vector2(4.0 if float(sp[0]) < 0.5 else -4.0, 4.0 if float(sp[1]) < 0.5 else -4.0) * (1.0 if (float(sp[0]) == 0.0 or float(sp[0]) == 1.0) and (float(sp[1]) == 0.0 or float(sp[1]) == 1.0) else 0.0)
		var rr: float = 5.0 * float(sp[2]) + 1.5
		var col: Color = pal["rock_a"] if i % 2 == 0 else pal["coral_a"].lerp(pal["shell"], 0.5)
		ci.draw_colored_polygon(_ellipse(cpos + Vector2(1.0, 1.6), rr * 1.05, rr * 0.8, 9), Color(0, 0, 0, 0.25))
		ci.draw_colored_polygon(_ellipse(cpos, rr, rr * 0.78, 9), _shade(col, 0.30))
		ci.draw_colored_polygon(_ellipse(cpos + Vector2(-rr * 0.2, -rr * 0.25), rr * 0.6, rr * 0.36, 8), _lit(col, 0.05))

static func draw_tile(ci: CanvasItem, rect: Rect2, parity: int, occupied: bool, pal: Dictionary) -> void:
	var rad: float = clampf(minf(rect.size.x, rect.size.y) * 0.17, 5.0, 12.0)
	var base: Color = pal["tile_a"] if parity % 2 == 0 else pal["tile_b"]
	if not occupied:
		# recessed: darker lip on top
		_rrect(ci, rect, rad, pal["tile_empty"], 0.0, _shade(pal["tile_empty"], 0.40), 2.0)
		return
	_rrect(ci, rect, rad, base, 3.0, _shade(base, 0.40), 0.0)
	# soft gloss on the upper half, plus a small catch-light on the top-left corner
	_rrect(ci, Rect2(rect.position + Vector2(3.0, 3.0), Vector2(rect.size.x - 6.0, rect.size.y * 0.40)), maxf(rad - 3.0, 3.0), Color(1, 1, 1, 0.07))
	ci.draw_arc(rect.position + Vector2(rad, rad), rad - 1.5, PI, PI * 1.5, 6, Color(1, 1, 1, 0.22), 1.4, true)

class_name CreatureArt
extends RefCounted
## Placeholder creature drawing. Everything is vector shapes so there are no
## art assets to manage. Shrimp = curved body with tail fan and antennae;
## Starfish = five-armed star. Tier is shown by the badge, the ring colour,
## a glow for tier 4+ (Reef Gate eligible) and a slight size increase.

static func scale_for_tier(tier: int) -> float:
	return 0.70 + 0.045 * float(tier)

## Draw a creature centred at `center` inside a square of side `size`.
## opts: alpha (float), flip (bool), phase (float, radians), rot (float),
##       badge (bool, default true), glow (bool, default true)
static func draw_creature(ci: CanvasItem, code: int, center: Vector2, size: float, opts: Dictionary = {}) -> void:
	if code <= 0:
		return
	var family: int = Creature.family_of(code)
	var tier: int = Creature.tier_of(code)
	var alpha: float = float(opts.get("alpha", 1.0))
	var flip: bool = bool(opts.get("flip", false))
	var phase: float = float(opts.get("phase", 0.0))
	var rot: float = float(opts.get("rot", 0.0))
	var u: float = size * 0.5 * scale_for_tier(tier)   # body "radius"
	var tcol: Color = Pal.tier_color(tier)
	if bool(opts.get("glow", true)) and tier >= GameConfig.RELEASE_MIN_TIER:
		var g: Color = tcol
		g.a = 0.22 * alpha
		ci.draw_circle(center, u * 1.15, g)
		g.a = 0.14 * alpha
		ci.draw_circle(center, u * 1.32, g)
	# ring under the body marks the tier at a glance, even in greyscale thickness
	var ring: Color = tcol
	ring.a = 0.9 * alpha
	ci.draw_arc(center, u * 1.02, 0.0, TAU, 40, ring, 1.5 + float(tier) * 0.55, true)
	var sx: float = -1.0 if flip else 1.0
	ci.draw_set_transform(center, rot, Vector2(sx, 1.0))
	if family == Creature.SHRIMP:
		_draw_shrimp(ci, u * 0.92, alpha, phase)
	else:
		_draw_star(ci, u * 0.95, alpha, phase)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if bool(opts.get("badge", true)):
		draw_badge(ci, tier, center + Vector2(size * 0.30, size * 0.30), size * 0.17, alpha)

static func draw_badge(ci: CanvasItem, tier: int, pos: Vector2, r: float, alpha: float = 1.0) -> void:
	var tcol: Color = Pal.tier_color(tier)
	var dark: Color = Pal.INK
	dark.a = 0.9 * alpha
	ci.draw_circle(pos, r + 1.8, dark)
	var fill: Color = tcol
	fill.a = alpha
	ci.draw_circle(pos, r, fill)
	var font: Font = ThemeDB.fallback_font
	var fs: int = int(r * 1.5)
	var tc: Color = Pal.INK
	tc.a = alpha
	ci.draw_string(font, pos + Vector2(-r, fs * 0.36), str(tier), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, tc)

static func _draw_shrimp(ci: CanvasItem, u: float, alpha: float, phase: float) -> void:
	var body: Color = Pal.SHRIMP_BODY
	var dark: Color = Pal.SHRIMP_DARK
	var light: Color = Pal.SHRIMP_LIGHT
	body.a = alpha
	dark.a = alpha
	light.a = alpha
	var wob: float = sin(phase) * 0.04 * u
	# body segments: [x, y, radius] along a curl (head right, tail curling down-left)
	var segs: Array = [
		[0.46, -0.06, 0.34], [0.16, -0.22, 0.33], [-0.14, -0.22, 0.30],
		[-0.38, -0.06, 0.26], [-0.46, 0.18, 0.21],
	]
	# antennae
	ci.draw_polyline(PackedVector2Array([Vector2(0.62, -0.22) * u, Vector2(0.9, -0.55 + wob / u) * u, Vector2(1.0, -0.9) * u]), dark, maxf(1.2, u * 0.06), true)
	ci.draw_polyline(PackedVector2Array([Vector2(0.66, -0.12) * u, Vector2(1.0, -0.2 + wob / u) * u, Vector2(1.12, -0.5) * u]), dark, maxf(1.0, u * 0.05), true)
	# tail fan
	var tail_c: Vector2 = Vector2(-0.5, 0.40) * u
	for k in 3:
		var a: float = 2.35 + float(k - 1) * 0.5
		var dir := Vector2(cos(a), sin(a))
		var perp := Vector2(-dir.y, dir.x)
		ci.draw_colored_polygon(PackedVector2Array([tail_c, tail_c + dir * u * 0.38 + perp * u * 0.10, tail_c + dir * u * 0.38 - perp * u * 0.10]), dark)
	# rostrum
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0.62, -0.30) * u, Vector2(1.02, -0.18) * u, Vector2(0.66, -0.02) * u]), dark)
	# legs
	for k in 3:
		var lx: float = 0.34 - float(k) * 0.26
		ci.draw_line(Vector2(lx, 0.04) * u, Vector2(lx - 0.06, 0.3 + wob / u * float(k % 2)) * u, dark, maxf(1.0, u * 0.05), true)
	# outline pass then fill pass
	for s in segs:
		ci.draw_circle(Vector2(s[0], s[1]) * u, (float(s[2]) + 0.06) * u, dark)
	for s in segs:
		ci.draw_circle(Vector2(s[0], s[1]) * u, float(s[2]) * u, body)
	# belly shine and shell bands
	for i in range(1, segs.size() - 1):
		var s: Array = segs[i]
		ci.draw_arc(Vector2(s[0], s[1]) * u, float(s[2]) * u * 0.78, 0.4, 2.2, 10, light, maxf(1.2, u * 0.07), true)
	# eye
	var eye := Vector2(0.58, -0.16) * u
	var w := Color(1, 1, 1, alpha)
	ci.draw_circle(eye, u * 0.12, w)
	ci.draw_circle(eye + Vector2(0.02, 0.0) * u, u * 0.06, Color(Pal.INK, alpha))

static func _draw_star(ci: CanvasItem, u: float, alpha: float, phase: float) -> void:
	var body: Color = Pal.STAR_BODY
	var dark: Color = Pal.STAR_DARK
	var light: Color = Pal.STAR_LIGHT
	body.a = alpha
	dark.a = alpha
	light.a = alpha
	var pts := PackedVector2Array()
	var inner := PackedVector2Array()
	var outer_r: float = 0.96
	var inner_r: float = 0.46
	var wig: float = sin(phase) * 0.05
	for k in 10:
		var ang: float = -PI * 0.5 + float(k) * PI / 5.0 + wig
		var r: float = outer_r if k % 2 == 0 else inner_r
		pts.append(Vector2(cos(ang), sin(ang)) * r * u)
		var r2: float = (outer_r - 0.22) if k % 2 == 0 else (inner_r - 0.10)
		inner.append(Vector2(cos(ang), sin(ang)) * r2 * u)
	# outline: draw bigger star in dark, tips rounded with circles
	var outline := PackedVector2Array()
	for p in pts:
		outline.append(p * 1.07)
	ci.draw_colored_polygon(outline, dark)
	ci.draw_colored_polygon(pts, body)
	ci.draw_colored_polygon(inner, light)
	for k in 5:
		var ang2: float = -PI * 0.5 + float(k) * TAU / 5.0 + wig
		var tip := Vector2(cos(ang2), sin(ang2))
		ci.draw_circle(tip * u * 0.9, u * 0.07, body)
		# a few arm spots
		ci.draw_circle(tip * u * 0.62, u * 0.055, dark)
		ci.draw_circle(tip * u * 0.40, u * 0.045, dark)
	ci.draw_circle(Vector2.ZERO, u * 0.16, dark)
	ci.draw_circle(Vector2.ZERO, u * 0.10, body)

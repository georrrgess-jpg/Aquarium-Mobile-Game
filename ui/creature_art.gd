class_name CreatureArt
extends RefCounted
## Procedural creature drawing. Everything is vector shapes so there are no
## art assets to manage. Shrimp = curled segmented body with tail fan and
## antennae; Starfish = five-armed star; Lantern Ray (visitor) = blue-violet
## manta with a glowing lantern on its tail. Tier is shown by the badge, the
## ring colour, a glow for tier 4+ (Reef Gate eligible), a slight size
## increase AND by shape/pattern details that accumulate per tier
## (bands -> spots/long antennae -> crest/fins -> sparkles -> crown/halo).

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
		_draw_shrimp(ci, u * 0.92, alpha, phase, tier)
	elif family == Creature.RAY:
		_draw_ray(ci, u * 0.95, alpha, phase, tier)
	else:
		_draw_star(ci, u * 0.95, alpha, phase, tier)
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

## Shrimp body colours per tier: pale glass -> coral -> warm orange-gold.
const _SHRIMP_BODY: Array = [Color("ffdcd2"), Color("ff8a7a"), Color("ff7d6e"), Color("ff9a5c"), Color("ffa24f"), Color("ffb347")]
const _SHRIMP_DARK: Array = [Color("c98d84"), Color("b8453d"), Color("a83c35"), Color("b5502a"), Color("b0521f"), Color("a8571a")]
const _STAR_BODY: Array = [Color("efdfb4"), Color("f2cf6e"), Color("f6c453"), Color("ffb447"), Color("ffab33"), Color("ffcf4a")]
const _STAR_DARK: Array = [Color("a8935f"), Color("b9791f"), Color("b9791f"), Color("b5601c"), Color("b0541a"), Color("b8741a")]

static func _a(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)

static func _sparkle(ci: CanvasItem, p: Vector2, r: float, col: Color, w: float) -> void:
	ci.draw_line(p + Vector2(-r, 0.0), p + Vector2(r, 0.0), col, w, true)
	ci.draw_line(p + Vector2(0.0, -r), p + Vector2(0.0, r), col, w, true)

static func _qbez(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var ab: Vector2 = a.lerp(b, t)
	var bc: Vector2 = b.lerp(c, t)
	return ab.lerp(bc, t)

static func _draw_shrimp(ci: CanvasItem, u: float, alpha: float, phase: float, tier: int) -> void:
	var ti: int = clampi(tier, 1, 6) - 1
	var body: Color = _a(_SHRIMP_BODY[ti], alpha)
	var dark: Color = _a(_SHRIMP_DARK[ti], alpha)
	var light: Color = _a(Pal.SHRIMP_LIGHT, alpha)
	var gold: Color = _a(Pal.GOLD, alpha)
	var wob: float = sin(phase) * 0.04 * u
	var lw: float = maxf(1.2, u * 0.06)
	# body segments: [x, y, radius] along a curl (head right, tail curling down-left)
	var segs: Array = [
		[0.46, -0.06, 0.34], [0.16, -0.22, 0.33], [-0.14, -0.22, 0.30],
		[-0.38, -0.06, 0.26], [-0.46, 0.18, 0.21],
	]
	var curl := Vector2(-0.05, 0.12)   # centre the body curls around
	# T6 radiant halo behind everything
	if tier >= 6:
		ci.draw_circle(Vector2(0.0, 0.02) * u, u * 0.98, _a(Pal.GOLD, alpha * 0.22))
		for k in 8:
			var ha: float = float(k) * TAU / 8.0 + phase * 0.15
			var hd := Vector2(cos(ha), sin(ha))
			ci.draw_line(hd * u * 0.92, hd * u * 1.12, _a(Pal.GOLD, alpha * 0.85), maxf(1.5, u * 0.07), true)
	elif tier >= 5:
		ci.draw_circle(Vector2(0.0, 0.02) * u, u * 0.95, _a(Pal.GOLD, alpha * 0.16))
	# antennae: short at T1, longer + curled from T3
	if tier <= 1:
		ci.draw_polyline(PackedVector2Array([Vector2(0.62, -0.22) * u, Vector2(0.84, -0.42 + wob / u) * u]), dark, lw, true)
		ci.draw_polyline(PackedVector2Array([Vector2(0.66, -0.12) * u, Vector2(0.88, -0.14 + wob / u) * u]), dark, lw * 0.8, true)
	elif tier == 2:
		ci.draw_polyline(PackedVector2Array([Vector2(0.62, -0.22) * u, Vector2(0.9, -0.55 + wob / u) * u, Vector2(1.0, -0.9) * u]), dark, lw, true)
		ci.draw_polyline(PackedVector2Array([Vector2(0.66, -0.12) * u, Vector2(1.0, -0.2 + wob / u) * u, Vector2(1.12, -0.5) * u]), dark, lw * 0.85, true)
	else:
		var wb: float = wob / u
		ci.draw_polyline(PackedVector2Array([Vector2(0.62, -0.22) * u, Vector2(0.84, -0.6) * u, Vector2(0.78, -0.95 + wb) * u, Vector2(0.96, -1.18 + wb) * u]), dark, lw, true)
		ci.draw_polyline(PackedVector2Array([Vector2(0.66, -0.12) * u, Vector2(1.02, -0.30) * u, Vector2(1.12, -0.62 + wb) * u, Vector2(1.0, -0.8 + wb) * u]), dark, lw * 0.85, true)
	# tail fan: 3 blades, 5 broader blades with gold tips from T4
	var tail_c: Vector2 = Vector2(-0.5, 0.40) * u
	var nb: int = 5 if tier >= 4 else 3
	var spread: float = 0.40 if tier >= 4 else 0.5
	var blen: float = 0.46 if tier >= 4 else 0.38
	for k in nb:
		var a: float = 2.35 + (float(k) - float(nb - 1) * 0.5) * spread
		var dir := Vector2(cos(a), sin(a))
		var perp := Vector2(-dir.y, dir.x)
		var tip: Vector2 = tail_c + dir * u * blen
		var wd: float = 0.11 if tier < 4 else 0.13
		ci.draw_colored_polygon(PackedVector2Array([tail_c, tip + perp * u * wd, tip - perp * u * wd]), dark)
		if tier >= 4:
			ci.draw_circle(tip, u * 0.07, gold)
	# rostrum
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0.62, -0.30) * u, Vector2(1.02, -0.18) * u, Vector2(0.66, -0.02) * u]), dark)
	# legs (+ pincer from T3)
	for k in 3:
		var lx: float = 0.34 - float(k) * 0.26
		ci.draw_line(Vector2(lx, 0.04) * u, Vector2(lx - 0.06, 0.3 + wob / u * float(k % 2)) * u, dark, maxf(1.0, u * 0.05), true)
	if tier >= 3:
		ci.draw_line(Vector2(0.66, 0.08) * u, Vector2(1.0, 0.2 + wob / u) * u, dark, maxf(1.4, u * 0.07), true)
		ci.draw_circle(Vector2(1.04, 0.2 + wob / u) * u, u * 0.09, dark)
	# dorsal crest spikes from T4 (behind the body so only the points show)
	if tier >= 4:
		for i in range(0, 4):
			var s: Array = segs[i]
			var c := Vector2(s[0], s[1])
			var out: Vector2 = (c - curl).normalized()
			var r: float = float(s[2])
			var perp2 := Vector2(-out.y, out.x)
			var base: Vector2 = (c + out * r * 0.70) * u
			var spike: float = 0.40 if i > 0 else 0.30
			ci.draw_colored_polygon(PackedVector2Array([base + perp2 * u * 0.15 - out * u * 0.04, base + out * u * (spike + 0.05), base - perp2 * u * 0.15 - out * u * 0.04]), dark)
			ci.draw_colored_polygon(PackedVector2Array([base + perp2 * u * 0.10, base + out * u * spike, base - perp2 * u * 0.10]), gold)
	# outline pass then fill pass
	for s in segs:
		ci.draw_circle(Vector2(s[0], s[1]) * u, (float(s[2]) + 0.06) * u, dark)
	for s in segs:
		ci.draw_circle(Vector2(s[0], s[1]) * u, float(s[2]) * u, body)
	# belly shine
	for i in range(1, segs.size() - 1):
		var s: Array = segs[i]
		ci.draw_arc(Vector2(s[0], s[1]) * u, float(s[2]) * u * 0.78, 0.4, 2.2, 10, light, maxf(1.2, u * 0.07), true)
	# shell bands (T2+): a dark chord across each middle segment; white back spots (T3+)
	if tier >= 2:
		for i in range(1, 4):
			var s: Array = segs[i]
			var c := Vector2(s[0], s[1])
			var out: Vector2 = (c - curl).normalized()
			var r: float = float(s[2])
			var bw: float = maxf(1.5, u * (0.09 if tier == 2 else 0.11))
			ci.draw_line((c + out * r * 0.92) * u, (c - out * r * 0.62) * u, _a(dark, 0.9), bw, true)
	if tier >= 3:
		for i in range(1, 4):
			var s: Array = segs[i]
			var c := Vector2(s[0], s[1])
			var out: Vector2 = (c - curl).normalized()
			var along := Vector2(-out.y, out.x)
			ci.draw_circle((c + out * float(s[2]) * 0.50 + along * float(s[2]) * 0.46) * u, u * 0.075, Color(1, 1, 1, alpha * 0.95))
	# eye
	var eye := Vector2(0.58, -0.16) * u
	var w := Color(1, 1, 1, alpha)
	ci.draw_circle(eye, u * 0.12, w)
	ci.draw_circle(eye + Vector2(0.02, 0.0) * u, u * 0.06, Color(Pal.INK, alpha))
	# T5 sparkles
	if tier >= 5:
		var sp: Color = _a(Color("fff6c8"), alpha)
		for k in 2:
			var pulse: float = 0.75 + 0.25 * sin(phase * 1.3 + float(k) * 2.1)
			var pos: Vector2 = [Vector2(-0.05, -0.74), Vector2(-0.78, -0.18)][k]
			_sparkle(ci, pos * u, u * 0.17 * pulse, sp, maxf(1.2, u * 0.05))
	# T6 crown
	if tier >= 6:
		var cr: Array = [Vector2(0.28, -0.34), Vector2(0.27, -0.64), Vector2(0.37, -0.52), Vector2(0.46, -0.72), Vector2(0.55, -0.52), Vector2(0.65, -0.64), Vector2(0.64, -0.34)]
		var big := PackedVector2Array()
		var sm := PackedVector2Array()
		var cc := Vector2(0.46, -0.50)
		for p in cr:
			sm.append(p * u)
			big.append((cc + (p - cc) * 1.22) * u)
		ci.draw_colored_polygon(big, dark)
		ci.draw_colored_polygon(sm, _a(Color("ffd84d"), alpha))
		ci.draw_circle(Vector2(0.46, -0.44) * u, u * 0.05, _a(Pal.CORAL, alpha))

static func _draw_star(ci: CanvasItem, u: float, alpha: float, phase: float, tier: int) -> void:
	var ti: int = clampi(tier, 1, 6) - 1
	var body: Color = _a(_STAR_BODY[ti], alpha)
	var dark: Color = _a(_STAR_DARK[ti], alpha)
	var light: Color = _a(Pal.STAR_LIGHT, alpha)
	if tier <= 1:
		light = _a(Color("fff6d8"), alpha)
	var pts := PackedVector2Array()
	var inner := PackedVector2Array()
	# arms get longer and slimmer with tier
	var outer_r: float = [0.80, 0.88, 0.94, 0.98, 0.98, 1.0][ti]
	var inner_r: float = [0.54, 0.50, 0.46, 0.42, 0.42, 0.42][ti]
	var wig: float = sin(phase) * 0.05
	# T5/T6 aura behind the star
	if tier >= 5:
		ci.draw_circle(Vector2.ZERO, u * 1.04, _a(Pal.GOLD, alpha * (0.22 if tier >= 6 else 0.15)))
	if tier >= 6:
		for k in 5:
			var na: float = -PI * 0.5 + (float(k) + 0.5) * TAU / 5.0 + wig
			var nd := Vector2(cos(na), sin(na))
			ci.draw_line(nd * u * 0.52, nd * u * 0.98, _a(Pal.GOLD, alpha * 0.9), maxf(1.6, u * 0.08), true)
	for k in 10:
		var ang: float = -PI * 0.5 + float(k) * PI / 5.0 + wig
		var r: float = outer_r if k % 2 == 0 else inner_r
		pts.append(Vector2(cos(ang), sin(ang)) * r * u)
		var r2: float = (outer_r - 0.22) if k % 2 == 0 else (inner_r - 0.10)
		inner.append(Vector2(cos(ang), sin(ang)) * r2 * u)
	# outline: draw bigger star in dark
	var outline := PackedVector2Array()
	for p in pts:
		outline.append(p * 1.07)
	ci.draw_colored_polygon(outline, dark)
	ci.draw_colored_polygon(pts, body)
	if tier >= 2:
		ci.draw_colored_polygon(inner, light)
	else:
		ci.draw_colored_polygon(inner, _a(light, 0.55))
	var lw: float = maxf(1.2, u * 0.05)
	for k in 5:
		var ang2: float = -PI * 0.5 + float(k) * TAU / 5.0 + wig
		var tip := Vector2(cos(ang2), sin(ang2))
		if tier >= 3:
			# central ridge down each arm + round knob at the tip
			ci.draw_line(tip * u * 0.18, tip * u * (outer_r - 0.08), dark, lw, true)
			ci.draw_circle(tip * u * (outer_r - 0.02), u * (0.085 if tier < 5 else 0.10), light if tier >= 5 else body)
		if tier >= 2:
			ci.draw_circle(tip * u * 0.64, u * 0.055, dark)
			ci.draw_circle(tip * u * 0.42, u * 0.045, dark)
	# T4+: raised centre medallion ringed with beads
	if tier >= 4:
		ci.draw_circle(Vector2.ZERO, u * 0.30, dark)
		ci.draw_circle(Vector2.ZERO, u * 0.25, light)
		for k in 5:
			var ba: float = -PI * 0.5 + (float(k) + 0.5) * TAU / 5.0 + wig
			ci.draw_circle(Vector2(cos(ba), sin(ba)) * u * 0.30, u * 0.06, dark)
	else:
		ci.draw_circle(Vector2.ZERO, u * 0.16, dark)
		ci.draw_circle(Vector2.ZERO, u * 0.10, body)
	# T5+ sparkles in the notches
	if tier >= 5:
		var sp: Color = _a(Color("ffffff"), alpha * 0.95)
		for k in 3:
			var pulse: float = 0.75 + 0.25 * sin(phase * 1.3 + float(k) * 2.1)
			var ka: float = -PI * 0.5 + (float(k) * 2.0 + 1.0) * TAU / 10.0 * 1.0
			_sparkle(ci, Vector2(cos(ka), sin(ka)) * u * 0.70, u * 0.15 * pulse, sp, maxf(1.2, u * 0.05))
	# T6 crown on the centre
	if tier >= 6:
		var cr: Array = [Vector2(-0.22, 0.10), Vector2(-0.24, -0.20), Vector2(-0.11, -0.05), Vector2(0.0, -0.28), Vector2(0.11, -0.05), Vector2(0.24, -0.20), Vector2(0.22, 0.10)]
		var big := PackedVector2Array()
		var sm := PackedVector2Array()
		var cc := Vector2(0.0, -0.05)
		for p in cr:
			sm.append(p * u)
			big.append((cc + (p - cc) * 1.25) * u)
		ci.draw_colored_polygon(big, dark)
		ci.draw_colored_polygon(sm, _a(Color("fff0a0"), alpha))
		ci.draw_circle(Vector2(0.0, 0.0) * u, u * 0.045, _a(Pal.CORAL, alpha))

## Lantern Ray: blue-violet manta facing right, wide flapping wings, long thin
## tail ending in a warm glowing lantern. Tier adds bioluminescent dots and a
## brighter lantern.
static func _draw_ray(ci: CanvasItem, u: float, alpha: float, phase: float, tier: int) -> void:
	var body: Color = _a(Color("6a6ee8"), alpha)
	var dark: Color = _a(Color("2b2a7c"), alpha)
	var light: Color = _a(Color("a9b8ff"), alpha)
	var dot: Color = _a(Color("8ff6ff"), alpha)
	var lamp: Color = _a(Color("ffd27a"), alpha)
	var f: float = 1.0 + 0.16 * sin(phase)
	var oy: float = -0.10   # whole body sits slightly high; the tail hangs low
	# tail first (behind wings): thin curve to the lantern
	var lan := Vector2(-0.84, 0.46 + oy)
	var tpts := PackedVector2Array()
	for i in 7:
		tpts.append(_qbez(Vector2(-0.50, 0.00 + oy), Vector2(-0.92, -0.10 + oy), lan, float(i) / 6.0) * u)
	ci.draw_polyline(tpts, dark, maxf(1.8, u * 0.07), true)
	# lantern halo
	var hr: float = 0.34 + 0.05 * float(clampi(tier - 4, 0, 2)) + 0.03 * sin(phase * 1.5)
	ci.draw_circle(lan * u, u * hr * 1.35, _a(lamp, alpha * 0.14))
	ci.draw_circle(lan * u, u * hr, _a(lamp, alpha * 0.30))
	# wings: broad, leading edge bulging out and sweeping back to a pointed tip
	var wings: Array = []
	for si in 2:
		var s: float = -1.0 if si == 0 else 1.0
		var lead := PackedVector2Array()
		var tip := Vector2(-0.30, s * 0.72 * f + oy)
		for i in 6:
			lead.append(_qbez(Vector2(0.72, s * 0.08 + oy), Vector2(0.34, s * 0.78 * f + oy), tip, float(i) / 5.0))
		for i in range(1, 6):
			lead.append(_qbez(tip, Vector2(-0.12, s * 0.22 + oy), Vector2(-0.56, s * 0.04 + oy), float(i) / 5.0))
		wings.append(lead)
	for wing in wings:
		var ow := PackedVector2Array()
		var wc := Vector2(0.0, oy)
		for p in wing:
			ow.append((wc + (p - wc) * 1.07) * u)
		ci.draw_colored_polygon(ow, dark)
	for wing in wings:
		var sc := PackedVector2Array()
		for p in wing:
			sc.append(p * u)
		ci.draw_colored_polygon(sc, body)
	# lighter rib along each wing and a pale shoulder stripe
	for si in 2:
		var s: float = -1.0 if si == 0 else 1.0
		ci.draw_line(Vector2(0.50, s * 0.14 + oy) * u, Vector2(-0.14, s * 0.62 * f + oy) * u, _a(light, 0.6), maxf(1.2, u * 0.05), true)
	# body: tapered central ridge + head lobes
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0.70, oy) * u, Vector2(0.30, -0.24 + oy) * u, Vector2(-0.50, -0.05 + oy) * u, Vector2(-0.50, 0.05 + oy) * u, Vector2(0.30, 0.24 + oy) * u]), dark)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0.64, oy) * u, Vector2(0.30, -0.18 + oy) * u, Vector2(-0.42, -0.03 + oy) * u, Vector2(-0.42, 0.03 + oy) * u, Vector2(0.30, 0.18 + oy) * u]), light)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0.62, -0.05 + oy) * u, Vector2(1.0, -0.20 + oy) * u, Vector2(0.88, 0.0 + oy) * u]), dark)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0.62, 0.05 + oy) * u, Vector2(1.0, 0.20 + oy) * u, Vector2(0.88, 0.0 + oy) * u]), dark)
	ci.draw_circle(Vector2(0.48, -0.12 + oy) * u, u * 0.06, Color(1, 1, 1, alpha))
	ci.draw_circle(Vector2(0.48, 0.12 + oy) * u, u * 0.06, Color(1, 1, 1, alpha))
	ci.draw_circle(Vector2(0.50, -0.12 + oy) * u, u * 0.03, Color(Pal.INK, alpha))
	ci.draw_circle(Vector2(0.50, 0.12 + oy) * u, u * 0.03, Color(Pal.INK, alpha))
	# bioluminescent dots along the wings
	var nd: int = 3 + clampi(tier - 4, 0, 2) * 2
	for k in nd:
		var s2: float = -1.0 if k % 2 == 0 else 1.0
		var tt: float = 0.30 + 0.16 * float(k / 2)
		var dp := Vector2(0.30 - tt * 0.70, s2 * (0.20 + tt * 0.85) * (1.0 + (f - 1.0) * 0.8) + oy)
		var pulse: float = 0.6 + 0.4 * sin(phase * 1.4 + float(k))
		if tier >= 5:
			ci.draw_circle(dp * u, u * 0.09, _a(dot, alpha * 0.25 * pulse))
		ci.draw_circle(dp * u, u * 0.045, dot)
	# lantern orb on top
	ci.draw_circle(lan * u, u * 0.15, _a(Color("c4781c"), alpha))
	ci.draw_circle(lan * u, u * 0.12, lamp)
	ci.draw_circle(lan * u + Vector2(-0.02, -0.02) * u, u * 0.06, Color(1, 0.97, 0.85, alpha))
	if tier >= 6:
		_sparkle(ci, lan * u, u * 0.30, _a(Color("fff3c0"), alpha), maxf(1.2, u * 0.05))

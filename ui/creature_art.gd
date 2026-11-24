class_name CreatureArt
extends RefCounted
## Procedural illustrated creatures (all vector, no image files).
##   Shrimp  - glass-pink curled baby -> armoured, crowned gold shrimp (faces right)
##   Starfish- plump pale-gold star -> long-armed, patterned, radiant crowned star
##   Lantern Ray - blue-violet manta with a glowing lantern tail (visitor family)
## Light comes from the top-left; each shape = vertex-shaded mesh + a 1.5-2.5px
## outline in the family's dark tone. Shapes are built once per (code, flip, phase
## bucket) into a display list (see CreatureParts) and replayed cheaply.
##
## opts (all optional): alpha, flip, phase (radians; flap / idle), rot (radians),
##   badge (bool, draw_creature only), glow (bool, draw_creature only),
##   detail (0 auto from size, 1 small, 2 full).
## Auto detail: < 56px small, < 110px medium, otherwise full.

const _INSET := 0.92            # body radius as a fraction of half the cell (margin for outline)

static var _cache: Dictionary = {}

static func scale_for_tier(tier: int) -> float:
	return 0.70 + 0.045 * float(tier)

# ------------------------------------------------------------------ public API
## Full creature: soft glow (T4+), tier ring, body, tier badge.
static func draw_creature(ci: CanvasItem, code: int, center: Vector2, size: float, opts: Dictionary = {}) -> void:
	if code <= 0:
		return
	var tier: int = Creature.tier_of(code)
	var alpha: float = float(opts.get("alpha", 1.0))
	var u: float = size * 0.5 * scale_for_tier(tier)
	var tcol: Color = Pal.tier_color(tier)
	if bool(opts.get("glow", true)) and tier >= GameConfig.RELEASE_MIN_TIER:
		var gc: Color = tcol
		gc.a = 0.42 * alpha
		ci.draw_mesh(CreatureParts.glow_mesh(), null, Transform2D(Vector2(u * 1.42, 0.0), Vector2(0.0, u * 1.42), center), gc)
	# ring under the body marks the tier at a glance
	var ring: Color = tcol
	ring.a = 0.92 * alpha
	var rw: float = 1.5 + float(tier) * 0.5
	var rdark: Color = Pal.INK
	rdark.a = 0.28 * alpha
	ci.draw_arc(center, u * 1.0, 0.0, TAU, 44, rdark, rw + 1.6, true)
	ci.draw_arc(center, u * 1.0, 0.0, TAU, 44, ring, rw, true)
	draw_body(ci, code, center, size, opts)
	if bool(opts.get("badge", true)):
		draw_badge(ci, tier, center + Vector2(size * 0.30, size * 0.30), size * 0.17, alpha)

static func draw_badge(ci: CanvasItem, tier: int, pos: Vector2, r: float, alpha: float = 1.0) -> void:
	var tcol: Color = Pal.tier_color(tier)
	var dark: Color = Pal.INK
	dark.a = 0.92 * alpha
	ci.draw_circle(pos, r + 1.8, dark)
	var fill: Color = tcol
	fill.a = alpha
	ci.draw_circle(pos, r, fill)
	# soft shading: darker lower-right rim, glossy top-left highlight
	var shade: Color = tcol.darkened(0.28)
	shade.a = 0.75 * alpha
	ci.draw_arc(pos, r * 0.80, -0.1, 1.9, 12, shade, maxf(1.0, r * 0.34), true)
	var gloss := Color(1, 1, 1, 0.55 * alpha)
	ci.draw_arc(pos, r * 0.74, 3.35, 4.55, 8, gloss, maxf(1.0, r * 0.2), true)
	var font: Font = ThemeDB.fallback_font
	var fs: int = int(r * 1.5)
	var tc: Color = Pal.INK
	tc.a = alpha
	ci.draw_string(font, pos + Vector2(-r, fs * 0.36), str(tier), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, tc)

## Body only: outline + shading + markings. Stays inside a square of side `size`
## centred on `center`, on a transparent background.
static func draw_body(ci: CanvasItem, code: int, center: Vector2, size: float, opts: Dictionary = {}) -> void:
	if code <= 0:
		return
	var tier: int = Creature.tier_of(code)
	var alpha: float = float(opts.get("alpha", 1.0))
	var flip: bool = bool(opts.get("flip", false))
	var phase: float = float(opts.get("phase", 0.0))
	var rot: float = float(opts.get("rot", 0.0))
	var lod: int = _lod_for(size, int(opts.get("detail", 0)))
	var u: float = size * 0.5 * _INSET * scale_for_tier(tier)
	var ub: int = maxi(int(round(u)), 6)     # geometry is built per integer unit size; a <=3% draw scale absorbs the rest
	var ops: Array = _ops_for(code, flip, phase, ub)
	_run(ci, ops, center, rot, u / float(ub), lod, alpha, phase)

## Dev helper: bounding box (in units of `size`, centred on 0) of the body drawn at `size`.
static func body_bounds(code: int, size: float) -> Rect2:
	var tier: int = Creature.tier_of(code)
	var u: float = size * 0.5 * _INSET * scale_for_tier(tier)
	var ub: int = maxi(int(round(u)), 6)
	var ops: Array = _ops_for(code, false, 0.0, ub)
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	var k: float = u / float(ub)
	for op in ops:
		var t: int = int(op[0])
		var pts := PackedVector2Array()
		if t == CreatureParts.OP_STROKE or t == CreatureParts.OP_FILL:
			pts = op[2]
		elif t == CreatureParts.OP_MESH:
			var arr: Array = (op[2] as ArrayMesh).surface_get_arrays(0)
			pts = arr[Mesh.ARRAY_VERTEX]
		for p in pts:
			mn = mn.min(p * k)
			mx = mx.max(p * k)
	return Rect2(mn / size, (mx - mn) / size)

static func _lod_for(size: float, detail: int) -> int:
	if detail == 1:
		return 1
	if detail >= 2:
		return 3
	if size < 56.0:
		return 1
	if size < 110.0:
		return 2
	return 3

# --------------------------------------------------------------------- replay
static func _ops_for(code: int, flip: bool, phase: float, ub: int) -> Array:
	var fam: int = Creature.family_of(code)
	var bucket: int = 0
	if fam == Creature.RAY:
		bucket = int(round(fposmod(phase, TAU) / TAU * 12.0)) % 12
	var key: int = ((code * 512 + ub) * 2 + (1 if flip else 0)) * 16 + bucket
	if _cache.has(key):
		return _cache[key]
	var b := CreatureParts.Builder.new()
	b.fx = -1.0 if flip else 1.0
	b.u = float(ub)
	var tier: int = clampi(Creature.tier_of(code), 1, 6)
	b.ow = clampf(float(ub) / (0.46 * scale_for_tier(tier)) * 0.028, 1.5, 2.4)
	var tf: float = float(tier - 1) / 5.0
	if fam == Creature.SHRIMP:
		b.gs = lerpf(1.25, 1.0, tf)
		b.off = Vector2(_SH_OFF_X[tier - 1], _SH_OFF_Y[tier - 1])
		_build_shrimp(b, tier)
	elif fam == Creature.RAY:
		b.gs = 1.07
		_build_ray(b, tier, float(bucket) / 12.0 * TAU)
	else:
		b.gs = lerpf(1.16, 1.0, tf)
		_build_star(b, tier)
	_cache[key] = b.ops
	return b.ops

static func _mul(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)

static func _run(ci: CanvasItem, ops: Array, center: Vector2, rot: float, k: float, lod: int, alpha: float, phase: float) -> void:
	var mod := Color(1, 1, 1, alpha)
	ci.draw_set_transform(center, rot, Vector2(k, k))
	for op in ops:
		if int(op[1]) > lod:
			continue
		var t: int = int(op[0])
		if t == CreatureParts.OP_MESH:
			ci.draw_mesh(op[2], null, Transform2D.IDENTITY, mod)
		elif t == CreatureParts.OP_STROKE:
			ci.draw_polyline(op[2], _mul(op[3], alpha), float(op[4]), true)
		elif t == CreatureParts.OP_FILL:
			ci.draw_colored_polygon(op[2], _mul(op[3], alpha))
		elif t == CreatureParts.OP_CIRCLE:
			ci.draw_circle(op[2], float(op[3]), _mul(op[4], alpha))
		elif t == CreatureParts.OP_ARC:
			ci.draw_arc(op[2], float(op[3]), float(op[4]), float(op[5]), 14, _mul(op[6], alpha), float(op[7]), true)
		elif t == CreatureParts.OP_LINES:
			ci.draw_multiline(op[2], _mul(op[3], alpha), float(op[4]), true)
		elif t == CreatureParts.OP_GLOW:
			var gr: float = float(op[3])
			var gc: Vector2 = op[2]
			ci.draw_mesh(CreatureParts.glow_mesh(), null, Transform2D(Vector2(gr, 0.0), Vector2(0.0, gr), gc), _mul(op[4], alpha))
		elif t == CreatureParts.OP_DYN:
			_dyn(ci, op, phase, alpha)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func _dyn(ci: CanvasItem, op: Array, phase: float, alpha: float) -> void:
	var kind: int = int(op[2])
	if kind == CreatureParts.DYN_WHISKER:
		var a: Vector2 = op[3]
		var c: Vector2 = op[4]
		var tip: Vector2 = op[5]
		var sd: float = float(op[8])
		var uu: float = float(op[9])
		var sw: float = sin(phase * 1.3 + sd)
		var d: Vector2 = tip - a
		var perp := Vector2(-d.y, d.x).normalized()
		c += perp * sw * 0.025 * uu
		tip += perp * sw * 0.07 * uu
		var pts := PackedVector2Array()
		for i in 7:
			pts.append(CreatureParts.bezier2(a, c, tip, float(i) / 6.0))
		ci.draw_polyline(pts, _mul(op[7], alpha), float(op[6]), true)
	elif kind == CreatureParts.DYN_SPARKLE:
		var p: Vector2 = op[3]
		var pulse: float = 0.72 + 0.28 * sin(phase * 1.3 + float(op[6]) * 2.1)
		var r: float = float(op[4]) * pulse
		var col: Color = _mul(op[5], alpha)
		var w: float = maxf(float(op[7]), 1.2)
		ci.draw_line(p + Vector2(-r, 0.0), p + Vector2(r, 0.0), col, w, true)
		ci.draw_line(p + Vector2(0.0, -r), p + Vector2(0.0, r), col, w, true)
		ci.draw_line(p + Vector2(-r, -r) * 0.45, p + Vector2(r, r) * 0.45, _mul(col, 0.6), w * 0.8, true)
		ci.draw_line(p + Vector2(-r, r) * 0.45, p + Vector2(r, -r) * 0.45, _mul(col, 0.6), w * 0.8, true)

# =================================================================== SHRIMP
## [hi, base, lo, dark outline, accent band]
const _SH: Array = [
	[Color("fff3ee"), Color("ffd3ca"), Color("eba6a2"), Color("b8706c"), Color("fff8f4")],
	[Color("ffc9b9"), Color("ff937f"), Color("d9604f"), Color("9c3b36"), Color("ffe6dc")],
	[Color("ffb6a2"), Color("ff7461"), Color("cc4638"), Color("8e2d2b"), Color("fff0e6")],
	[Color("ffcb92"), Color("ff8f52"), Color("cf5a2f"), Color("86381c"), Color("ffd96a")],
	[Color("ffdc90"), Color("ffa344"), Color("d46f24"), Color("824418"), Color("fff1c4")],
	[Color("fff3b0"), Color("ffbf3c"), Color("e1862a"), Color("85501a"), Color("fff7d2")],
]
const _SH_OFF_X: Array = [-0.06, -0.06, -0.07, -0.08, -0.09, -0.09]
const _SH_OFF_Y: Array = [0.0, 0.0, -0.02, -0.04, -0.06, -0.08]
const _GOLD := Color("ffd45c")
const _GOLD_D := Color("c88a1a")
const _EYE := Color("1a1a2a")

const _CUR: Array = [Vector2(0.38, 0.00), Vector2(0.10, -0.27), Vector2(-0.19, -0.32), Vector2(-0.44, -0.18), Vector2(-0.55, 0.08), Vector2(-0.44, 0.33)]
const _UPR: Array = [Vector2(0.32, -0.28), Vector2(0.03, -0.38), Vector2(-0.27, -0.31), Vector2(-0.49, -0.09), Vector2(-0.55, 0.19), Vector2(-0.44, 0.45)]
const _RAD_CUR: Array = [0.31, 0.26, 0.245, 0.21, 0.17, 0.13]
const _RAD_UPR: Array = [0.35, 0.285, 0.27, 0.235, 0.195, 0.155]

static func _build_shrimp(b: CreatureParts.Builder, tier: int) -> void:
	var ti: int = tier - 1
	var pal: Array = _SH[ti]
	var hi: Color = pal[0]
	var base: Color = pal[1]
	var lo: Color = pal[2]
	var dark: Color = pal[3]
	var acc: Color = pal[4]
	var k: float = [0.0, 0.12, 0.34, 0.58, 0.80, 1.0][ti]
	var tf: float = float(ti) / 5.0
	if tier == 1:      # glass: slightly see-through
		hi.a = 0.92
		base.a = 0.86
		lo.a = 0.82
	# ---- spine
	var S: Array = []
	var R: Array = []
	var cc := Vector2.ZERO
	for i in 6:
		var p: Vector2 = (_CUR[i] as Vector2).lerp(_UPR[i], k)
		S.append(p)
		R.append(lerpf(_RAD_CUR[i], _RAD_UPR[i], k) * (0.92 + 0.10 * tf))
		cc += p
	cc /= 6.0
	var C0: Vector2 = S[0]
	var ang: Array = []
	var dors: Array = []
	for i in 6:
		var fwd: Vector2
		if i == 0:
			fwd = S[0] - S[1]
		elif i == 5:
			fwd = S[4] - S[5]
		else:
			fwd = S[i - 1] - S[i + 1]
		ang.append(fwd.angle())
		dors.append((S[i] as Vector2 - cc).normalized())
	if tier >= 5:
		b.glow(C0 + Vector2(0.0, -0.05), 0.62 if tier == 6 else 0.5, Color(1.0, 0.86, 0.4, 0.55 if tier == 6 else 0.30), 1)
	# ---- whiskers (behind everything)
	var wl: float = 0.30 + 0.70 * tf
	var wb := C0 + Vector2(0.24, -0.14)
	var wcol: Color = dark.lerp(base, 0.12)
	b.whisker(wb, wb + Vector2(0.24, -0.22) * wl, wb + Vector2(0.16 + 0.20 * wl, -0.12 - 0.50 * wl), 0.032 + 0.006 * tf, wcol, 0.0)
	if tier >= 2:
		b.whisker(wb + Vector2(0.03, 0.04), wb + Vector2(0.20, -0.02 - 0.06 * tf), wb + Vector2(0.28 + 0.06 * tf, 0.10 - 0.30 * wl), 0.028, wcol, 2.2)
	else:
		b.whisker(wb + Vector2(0.03, 0.04), wb + Vector2(0.10, 0.0), wb + Vector2(0.17, -0.02), 0.028, wcol, 2.2)
	# ---- claws: far one first (behind the body)
	var cs: float = [0.052, 0.080, 0.120, 0.158, 0.178, 0.196][ti]
	var hand: Vector2 = C0 + Vector2(0.36, 0.27 - 0.10 * k)
	var th: float = lerpf(0.30, -0.12, k)
	var far_hand: Vector2 = hand + Vector2(-0.10, 0.10)
	_shrimp_claw(b, C0 + Vector2(0.06, 0.10), far_hand, th + 0.22, cs * 0.86, lo.lerp(dark, 0.25), lo, dark.lerp(lo, 0.2), dark, dark, false, acc, tier)
	# ---- legs (walking legs + swimmerets)
	var pairs := PackedVector2Array()
	for j in 3:
		var s0: Vector2 = C0 + Vector2(0.12 - 0.13 * float(j), 0.20 - 0.01 * float(j))
		pairs.append(s0)
		pairs.append(s0 + Vector2(0.07 - 0.04 * float(j), 0.17 + 0.03 * float(j)))
	for i in range(1, 5):
		var s1: Vector2 = S[i] - (dors[i] as Vector2) * float(R[i]) * 0.74
		var tl: Vector2 = -Vector2(cos(float(ang[i])), sin(float(ang[i])))
		pairs.append(s1)
		pairs.append(s1 - (dors[i] as Vector2) * 0.10 + tl * 0.03)
	b.lines(pairs, dark, 0.034, 1)
	# ---- tail fan
	var fa: float = lerpf(deg_to_rad(18.0), deg_to_rad(112.0), k)
	var f_dir := Vector2(cos(fa), sin(fa))
	var F: Vector2 = S[5] + f_dir * float(R[5]) * 0.80
	var fl: float = lerpf(0.30, 0.42, tf)
	var nb: int = [3, 3, 4, 5, 5, 7][ti]
	var hs: float = lerpf(0.40, 0.72, tf)
	var fpts := PackedVector2Array([F - f_dir * 0.03])
	var rib := PackedVector2Array()
	for j in nb:
		var ac: float = fa - hs + 2.0 * hs * (float(j) + 0.5) / float(nb)
		var aw: float = hs / float(nb) * 0.97
		for q in 5:
			var s: float = -1.0 + 2.0 * float(q) / 4.0
			var rr: float = fl * (0.70 + 0.30 * sqrt(maxf(1.0 - s * s, 0.0)))
			var a2: float = ac + s * aw
			fpts.append(F + Vector2(cos(a2), sin(a2)) * rr)
		rib.append(F)
		rib.append(F + Vector2(cos(ac), sin(ac)) * fl * 0.90)
	var fan_base: Color = base.lerp(hi, 0.34)
	b.poly(fpts, fan_base, hi, lo, dark, 1, -1.0, 0.0)
	b.lines(rib, _mul(lo.lerp(dark, 0.3), 0.7), 0.02, 2)
	if tier >= 4:
		var tips: Array = []
		for j in nb:
			var ac2: float = fa - hs + 2.0 * hs * (float(j) + 0.5) / float(nb)
			tips.append(F + Vector2(cos(ac2), sin(ac2)) * fl * 0.88)
		b.dots(tips, 0.034 + 0.004 * float(tier - 4), _GOLD, 2, 8)
	# ---- abdomen shingles, tail -> head
	for i in range(5, 0, -1):
		var r: float = R[i]
		var seg: PackedVector2Array = CreatureParts.ellipse(S[i], r * 0.96, r * 1.03, float(ang[i]), 20)
		b.poly(seg, base, hi, lo, dark, 1, -1.0, 0.28)
	# ---- carapace (head)
	var cr: float = R[0]
	var cm := PackedVector2Array([Vector2(-0.30, -0.02), Vector2(-0.24, -0.24), Vector2(0.0, -0.31), Vector2(0.26, -0.21), Vector2(0.45, -0.05), Vector2(0.30, 0.14), Vector2(0.04, 0.26), Vector2(-0.22, 0.22)])
	var cs2 := PackedVector2Array()
	var cscale: float = cr / 0.31
	for p in cm:
		cs2.append(C0 + p * cscale)
	# rostrum (blade between eyes), behind the carapace so only the blade shows
	var rlen: float = lerpf(0.10, 0.19, tf)
	var rb: Vector2 = C0 + Vector2(0.10, -0.25) * cscale
	var rt: Vector2 = C0 + Vector2(0.42 + rlen * 0.8, -0.26 - rlen * 0.25) * cscale
	var rcol: Color = dark.lerp(base, 0.15) if tier < 4 else _GOLD_D
	var rfill: Color = base.lerp(lo, 0.2) if tier < 4 else _GOLD
	var rpts := PackedVector2Array([rb + Vector2(-0.02, 0.0), rt, C0 + Vector2(0.26, -0.15) * cscale])
	b.fill(rpts, rfill)
	b.stroke(rpts, rcol, -0.75, true)
	var cpts: PackedVector2Array = b.blob(cs2, 4, base, hi, lo, dark, 1, -1.0, 0.30)
	# band across the carapace/abdomen joint
	var bw: float = [0.0, 0.032, 0.05, 0.052, 0.054, 0.056][ti]
	if tier >= 2:
		var bl := PackedVector2Array()
		for i in range(1, 5):
			var bc: Vector2 = S[i]
			var ba: float = float(ang[i]) + PI
			var rr: float = float(R[i]) * 0.80
			bl.append_array(CreatureParts.Builder.arc_pairs(bc, rr, ba - 0.85, ba + 0.85, 4))
		var bcol: Color = acc
		bcol.a = 0.85
		b.lines(bl, bcol, bw, 1)
	# translucent glass: gut line + chromatophores
	if tier <= 2:
		var gut := PackedVector2Array([S[1] + Vector2(0, 0.02), S[2], S[3], S[4], S[5]])
		for g in gut.size():
			gut[g] = gut[g] + (dors[mini(g + 1, 5)] as Vector2) * -0.02
		var gc: Color = Color("d2605a")
		gc.a = 0.55 if tier == 1 else 0.28
		b.stroke(CreatureParts.spline_open(gut, 3), gc, 0.04, false, 1)
	if tier == 1:
		var dts: Array = [S[1] + Vector2(0.02, -0.12), S[2] + Vector2(-0.02, -0.1), S[3] + Vector2(0.0, -0.08), C0 + Vector2(-0.10, -0.06)]
		b.dots(dts, 0.026, Color("e8706a"), 2)
	# lod 3: carapace groove + shell speckles
	if tier >= 2:
		var gv := PackedVector2Array([C0 + Vector2(0.04, -0.27) * cscale, C0 + Vector2(-0.08, -0.06) * cscale, C0 + Vector2(-0.04, 0.20) * cscale])
		b.stroke(CreatureParts.spline_open(gv, 4), _mul(dark, 0.5), 0.022, false, 3)
	if tier >= 3:
		var spk: Array = []
		for i in range(1, 5):
			var d4: Vector2 = dors[i]
			var pr := Vector2(-d4.y, d4.x)
			spk.append((S[i] as Vector2) + d4 * float(R[i]) * 0.30 + pr * 0.06)
			spk.append((S[i] as Vector2) + d4 * float(R[i]) * 0.10 - pr * 0.05)
		spk.append(C0 + Vector2(-0.12, -0.10) * cscale)
		spk.append(C0 + Vector2(-0.02, 0.06) * cscale)
		b.dots(spk, 0.016, _mul(dark, 0.30), 3, 6)
	# dorsal highlights
	var hl := PackedVector2Array()
	for i in 5:
		var d: Vector2 = dors[i]
		if d.dot(CreatureParts.LIGHT) > 0.1:
			var hp: Vector2 = (S[i] as Vector2) + d * float(R[i]) * 0.66
			var tg := Vector2(-d.y, d.x) * 0.075
			hl.append(hp - tg)
			hl.append(hp + tg)
	hl.append(C0 + Vector2(-0.06, -0.22) * cscale)
	hl.append(C0 + Vector2(0.12, -0.24) * cscale)
	b.lines(hl, Color(1, 1, 1, 0.62), 0.04, 2)
	# T4+ dorsal crest
	if tier >= 4:
		var spikes: Array = []
		var scols: Array = []
		var sl := PackedVector2Array()
		var nsp: int = 3 if tier == 4 else 4
		for j in nsp:
			var si: int = j + 1
			var d2: Vector2 = dors[si]
			var tgn := Vector2(d2.y, -d2.x)   # toward the head/tail along the curve
			var bp: Vector2 = (S[si] as Vector2) + d2 * float(R[si]) * 0.88
			var h: float = 0.115 + 0.025 * float(tier - 4) + (0.02 if j == 1 else 0.0)
			var tipp: Vector2 = bp + d2 * h + tgn * 0.07
			var pa: Vector2 = bp - tgn * 0.085
			var pb: Vector2 = bp + tgn * 0.085
			spikes.append(PackedVector2Array([pa, tipp, pb]))
			scols.append(_GOLD)
			sl.append(pa)
			sl.append(tipp)
			sl.append(tipp)
			sl.append(pb)
		b.flat_mesh(spikes, scols, 1)
		b.lines(sl, _GOLD_D, -0.8, 1)
	# T5+ pearl armour plates + sparkle
	if tier >= 5:
		var pl: Array = []
		var pc: Array = []
		for i in range(1, 4):
			var d3: Vector2 = dors[i]
			var cp: Vector2 = (S[i] as Vector2) + d3 * float(R[i]) * 0.42 + (Vector2(-d3.y, d3.x)) * 0.02
			var q: float = 0.060 if tier == 5 else 0.068
			pl.append(PackedVector2Array([cp + Vector2(0, -q), cp + Vector2(q * 0.8, 0), cp + Vector2(0, q), cp + Vector2(-q * 0.8, 0)]))
			pc.append(Color(1, 1, 0.92, 0.88))
		b.flat_mesh(pl, pc, 2)
		b.sparkle(S[2] + Vector2(-0.02, -0.40), 0.10, Color("fff6c8"), 0.0, 1)
		b.sparkle(S[3] + Vector2(-0.12, -0.04), 0.08, Color("fff6c8"), 1.0, 2)
	# ---- eye (big dark bead with a glint)
	var ep: Vector2 = C0 + Vector2(0.17, -0.12) * cscale
	var er: float = lerpf(0.094, 0.078, tf)
	b.circle(ep, er * 1.18, Color(0.05, 0.10, 0.13, 0.9))
	b.circle(ep, er, _EYE)
	b.circle(ep + Vector2(-0.025, -0.03), er * 0.38, Color(1, 1, 1, 0.95))
	if tier >= 3:
		b.circle(ep + Vector2(0.03, 0.03), er * 0.18, Color(1, 1, 1, 0.55), 2)
	# ---- near claw (on top of the head)
	_shrimp_claw(b, C0 + Vector2(0.04, 0.16), hand, th, cs, base.lerp(lo, 0.5), hi.lerp(base, 0.3), lo.darkened(0.22), dark, dark, true, acc, tier)
	# ---- T6 crown + halo
	if tier >= 6:
		var cb: Vector2 = C0 + Vector2(0.08, -0.30)
		var cw := PackedVector2Array([Vector2(-0.15, 0.02), Vector2(-0.16, -0.20), Vector2(-0.075, -0.10), Vector2(0.0, -0.26), Vector2(0.075, -0.10), Vector2(0.16, -0.20), Vector2(0.15, 0.02)])
		var cwp := PackedVector2Array()
		for p in cw:
			cwp.append(cb + p)
		b.poly(cwp, _GOLD, Color("fff3b0"), _GOLD_D, Color("7c4a10"), 1, -0.85, 0.15)
		b.circle(cb + Vector2(0.0, -0.06), 0.034, Color("ff5d73"), 1)
		b.circle(cb + Vector2(-0.01, -0.07), 0.012, Color(1, 1, 1, 0.9), 2)
		b.dots([cb + Vector2(-0.12, -0.17), cb + Vector2(0.0, -0.23), cb + Vector2(0.12, -0.17)], 0.018, Color("fffbe0"), 2)

## A shrimp claw: arm (2 segments) + chela mitten with two fingers.
static func _shrimp_claw(b: CreatureParts.Builder, shoulder: Vector2, hand: Vector2, th: float, s: float, base: Color, hi: Color, lo: Color, dark: Color, line: Color, near: bool, acc: Color, tier: int) -> void:
	var elbow: Vector2 = shoulder.lerp(hand, 0.55) + Vector2(0.02, 0.07)
	var arm := PackedVector2Array([shoulder, elbow, hand - Vector2(cos(th), sin(th)) * s * 0.4])
	b.stroke(arm, line, 0.115 if near else 0.095, false, 1)
	b.stroke(arm, base.lerp(lo, 0.3), 0.07 if near else 0.055, false, 1)
	var open: float = 0.06 + 0.12 * float(tier) / 6.0
	var ch := PackedVector2Array([
		Vector2(-0.60, 0.0), Vector2(-0.45, -0.55), Vector2(0.10, -0.76), Vector2(0.65, -0.62), Vector2(1.25, -0.46),
		Vector2(1.80, -0.38 - open * 1.6), Vector2(1.22, -0.12), Vector2(0.86, 0.03), Vector2(1.16, 0.15), Vector2(1.66, 0.30 + open),
		Vector2(1.20, 0.52), Vector2(0.65, 0.64), Vector2(0.10, 0.76), Vector2(-0.45, 0.55)])
	var pts: PackedVector2Array = CreatureParts.xform(ch, hand, th, s)
	b.poly(pts, base, hi, lo, line, 1, -0.9, 0.25)
	if near and tier >= 6:
		var g: PackedVector2Array = CreatureParts.xform(PackedVector2Array([Vector2(-0.2, -0.40), Vector2(0.6, -0.38)]), hand, th, s)
		b.stroke(g, Color(1, 1, 1, 0.8), 0.04, false, 1)
		b.sparkle(hand + Vector2(cos(th), sin(th)) * s * 1.55, 0.11, Color("ffffff"), 2.0, 2)
	elif near and tier >= 3:
		var g2: PackedVector2Array = CreatureParts.xform(PackedVector2Array([Vector2(-0.2, -0.40), Vector2(0.5, -0.38)]), hand, th, s)
		b.stroke(g2, Color(1, 1, 1, 0.55), 0.03, false, 2)

# =================================================================== STAR
## [hi, base, lo, dark, accent]
const _ST: Array = [
	[Color("fff6d8"), Color("f6e4b0"), Color("d9bb7a"), Color("a77f3e"), Color("fffaf0")],
	[Color("ffeeaa"), Color("f8d068"), Color("dca040"), Color("a96f1d"), Color("fff3c8")],
	[Color("ffe58f"), Color("fcc24c"), Color("db8c2a"), Color("a45f1a"), Color("fff0b8")],
	[Color("ffd884"), Color("ffab40"), Color("d4701f"), Color("984a14"), Color("ffe9b0")],
	[Color("ffdc9c"), Color("ff9a3a"), Color("cf5d22"), Color("8c3e12"), Color("fff0c8")],
	[Color("ffeeaa"), Color("ffb23a"), Color("e0702c"), Color("924212"), Color("fff6d0")],
]

static func _star_half(rr: float, rv: float, R: float, p: float) -> float:
	var sv: float = clampf((rr - rv) / (R - rv), 0.001, 0.999)
	sv = pow(sv, 1.0 / p)
	return acos(clampf(2.0 * sv - 1.0, -1.0, 1.0)) / 5.0

static func _star_radius(th: float, th0: float, rv: float, R: float, p: float) -> float:
	var c: float = cos(5.0 * (th - th0))
	return rv + (R - rv) * pow((c + 1.0) * 0.5, p)

static func _build_star(b: CreatureParts.Builder, tier: int) -> void:
	var ti: int = tier - 1
	var pal: Array = _ST[ti]
	var hi: Color = pal[0]
	var base: Color = pal[1]
	var lo: Color = pal[2]
	var dark: Color = pal[3]
	var acc: Color = pal[4]
	var R: float = [0.80, 0.86, 0.91, 0.94, 0.96, 0.98][ti]
	var rv: float = R * [0.62, 0.56, 0.50, 0.46, 0.43, 0.42][ti]
	var p: float = [0.95, 1.15, 1.4, 1.65, 1.85, 2.0][ti]
	var oy: float = 0.04
	var th0: float = -PI * 0.5
	# soft aura behind T5/T6
	if tier >= 5:
		b.glow(Vector2(0, oy), 1.0 if tier == 6 else 0.92, Color(1.0, 0.82, 0.35, 0.55 if tier == 6 else 0.38), 1)
	# silhouette
	var pts := PackedVector2Array()
	var per: int = 14
	for i in 5 * per:
		var th: float = th0 + TAU * float(i) / float(5 * per)
		var c: float = cos(5.0 * (th - th0))
		var s: float = (c + 1.0) * 0.5
		var r: float = rv + (R - rv) * pow(s, p)
		pts.append(Vector2(cos(th), sin(th)) * r + Vector2(0, oy))
	b.poly(pts, base, hi, lo, dark, 1, -1.0, 0.22, 0.9, 1.0)
	# helpers: arm half-angle at radius rho
	var arm_dirs: Array = []
	for j in 5:
		arm_dirs.append(th0 + TAU * float(j) / 5.0)
	# smooth freckles (T1) / dots (T2)
	if tier == 1:
		var fr: Array = [Vector2(-0.12, -0.10), Vector2(0.10, -0.16), Vector2(0.14, 0.06), Vector2(-0.06, 0.12), Vector2(-0.30, -0.42), Vector2(0.28, -0.40)]
		var fr2: Array = []
		for q in fr:
			fr2.append((q as Vector2) + Vector2(0, oy))
		b.dots(fr2, 0.024, _mul(dark, 0.45), 2)
	# groove (ambulacral) down each arm
	if tier >= 3:
		var gp := PackedVector2Array()
		for j in 5:
			var d := Vector2(cos(arm_dirs[j]), sin(arm_dirs[j]))
			gp.append(d * 0.16 + Vector2(0, oy))
			gp.append(d * (R - 0.10) + Vector2(0, oy))
		b.lines(gp, _mul(dark, 0.55), 0.03, 1)
	# dots along arms (T2) / ridge chords (T3+)
	if tier == 2:
		var dp: Array = []
		for j in 5:
			var d2 := Vector2(cos(arm_dirs[j]), sin(arm_dirs[j]))
			for rho in [0.44, 0.60, 0.75]:
				dp.append(d2 * (R * float(rho) + 0.06) + Vector2(0, oy))
		b.dots(dp, 0.036, _mul(dark, 0.62), 1)
	elif tier >= 3:
		var cp := PackedVector2Array()
		var rhos: Array = [0.46, 0.60, 0.74] if tier == 3 else [0.50, 0.68]
		for j in 5:
			for rho in rhos:
				var rr: float = lerpf(rv, R, float(rho)) + 0.0
				var sv: float = clampf((rr - rv) / (R - rv), 0.001, 0.999)
				sv = pow(sv, 1.0 / p)
				var dl: float = acos(clampf(2.0 * sv - 1.0, -1.0, 1.0)) / 5.0 * 0.78
				var a1: float = arm_dirs[j] - dl
				var a2: float = arm_dirs[j] + dl
				var am: float = arm_dirs[j]
				var e1 := Vector2(cos(a1), sin(a1)) * rr + Vector2(0, oy)
				var e2 := Vector2(cos(a2), sin(a2)) * rr + Vector2(0, oy)
				var em := Vector2(cos(am), sin(am)) * (rr + 0.035) + Vector2(0, oy)
				cp.append(e1)
				cp.append(em)
				cp.append(em)
				cp.append(e2)
		b.lines(cp, _mul(dark, 0.62), 0.032 if tier == 3 else 0.026, 1)
	# beaded rows (T4+): dark socket + pale bead along each arm, tapering outward
	if tier >= 4:
		var bd: Array = []
		var br: Array = []
		var nb: int = 5 if tier == 4 else 6
		for j in 5:
			var d3 := Vector2(cos(arm_dirs[j]), sin(arm_dirs[j]))
			for q in nb:
				var t: float = float(q) / float(nb - 1)
				var rho2: float = lerpf(0.38, R - 0.13, t)
				bd.append(d3 * rho2 + Vector2(0, oy))
				br.append(lerpf(0.050, 0.026, t) * (1.0 if tier == 4 else 1.12))
		var br2: Array = []
		for x in br:
			br2.append(float(x) * 1.35)
		b.dots(bd, br2, _mul(dark, 0.75), 1)
		b.dots(bd, br, acc, 1)
	# central disc
	var dr: float = [0.0, 0.20, 0.23, 0.26, 0.27, 0.28][ti]
	if tier >= 2:
		var disc: PackedVector2Array = CreatureParts.ellipse(Vector2(0, oy), dr, dr, 0.0, 20)
		b.poly(disc, base.lerp(hi, 0.45), hi, base, dark, 1, -0.7, 0.25, 0.6, 0.8)
	if tier >= 4:
		# patterned disc: pentagon star ring of tiny beads between the arms
		var vb: Array = []
		for j in 5:
			var va: float = th0 + TAU * (float(j) + 0.5) / 5.0
			vb.append(Vector2(cos(va), sin(va)) * dr * 0.62 + Vector2(0, oy))
		b.dots(vb, 0.026, _mul(dark, 0.8), 2)
		var pen := PackedVector2Array()
		for j in 5:
			pen.append(Vector2(cos(arm_dirs[j]), sin(arm_dirs[j])) * dr * 0.5 + Vector2(0, oy))
		b.stroke(pen, _mul(dark, 0.6), 0.022, true, 2)
	# lod 3: tube-foot dots along the arm edges + skin granules
	if tier >= 2:
		var tf2: Array = []
		var nfeet: int = 5 if tier < 4 else 6
		for j in 5:
			for q in nfeet:
				var t2: float = float(q) / float(nfeet - 1)
				var rr: float = lerpf(0.32, R - 0.16, t2)
				var dl2: float = _star_half(rr, rv, R, p) * 0.70
				for sg in [-1.0, 1.0]:
					var aa: float = arm_dirs[j] + sg * dl2
					tf2.append(Vector2(cos(aa), sin(aa)) * rr + Vector2(0, oy))
		b.dots(tf2, 0.016, _mul(acc, 0.85), 3, 6)
	if tier >= 3:
		var gr: Array = []
		for i in 44:
			var ga: float = float(i) * 2.39996
			var gd: float = 0.14 + 0.85 * sqrt(float(i) / 44.0)
			if gd < _star_radius(ga + th0, th0, rv, R, p) * 0.80:
				gr.append(Vector2(cos(ga + th0), sin(ga + th0)) * gd + Vector2(0, oy))
		b.dots(gr, 0.014, _mul(dark, 0.22), 3, 6)
	# spec highlights on the lit side of each arm
	var hp: Array = []
	var hc: Array = []
	for j in 5:
		var d4 := Vector2(cos(arm_dirs[j]), sin(arm_dirs[j]))
		var lit: float = maxf(d4.dot(CreatureParts.LIGHT), -0.2)
		var pc: Vector2 = d4 * (R * 0.62) + CreatureParts.LIGHT * 0.045 + Vector2(0, oy)
		var tg := Vector2(-d4.y, d4.x)
		var ln: float = 0.15
		var wd: float = 0.03
		hp.append(PackedVector2Array([pc - d4 * ln - tg * wd * 0.6, pc - d4 * ln * 0.2 - tg * wd, pc + d4 * ln - tg * wd * 0.5, pc + d4 * ln + tg * wd * 0.5, pc + d4 * ln * 0.2 + tg * wd, pc - d4 * ln + tg * wd * 0.6]))
		hc.append(Color(1, 1, 1, clampf(0.20 + 0.42 * lit, 0.14, 0.62)))
	b.flat_mesh(hp, hc, 2)
	# T5+: glitter
	if tier >= 5:
		b.sparkle(Vector2(0.50, -0.12 + oy), 0.13, Color("ffffff"), 0.0, 1)
		b.sparkle(Vector2(-0.42, 0.34 + oy), 0.11, Color("ffffff"), 1.0, 2)
		b.sparkle(Vector2(-0.14, -0.62 + oy), 0.10, Color("fff6c8"), 2.0, 2)
		b.dots([Vector2(0.18, 0.30 + oy), Vector2(-0.52, -0.16 + oy), Vector2(0.56, 0.36 + oy), Vector2(0.06, -0.34 + oy), Vector2(-0.28, 0.58 + oy)], 0.022, Color(1, 1, 0.95, 0.95), 2)
	# T6: radiant crown + luminous core
	if tier >= 6:
		var cw := PackedVector2Array()
		for j in 10:
			var va2: float = th0 + TAU * (float(j) + 0.5) / 10.0
			var rr2: float = 0.40 if j % 2 == 0 else 0.25
			cw.append(Vector2(cos(va2), sin(va2)) * rr2 + Vector2(0, oy))
		b.poly(cw, Color("ffd45c"), Color("fff3b0"), Color("d48a1a"), Color("7c4a10"), 1, -0.9, 0.1)
		var ring: PackedVector2Array = CreatureParts.ellipse(Vector2(0, oy), 0.22, 0.22, 0.0, 20)
		b.poly(ring, Color("fff0b4"), Color("ffffff"), Color("ffc85a"), Color("a86a14"), 1, -0.7, 0.2, 0.9, 0.9)
		b.glow(Vector2(0, oy), 0.34, Color(1, 0.97, 0.8, 0.95), 1)
		b.circle(Vector2(-0.03, -0.04 + oy), 0.045, Color(1, 1, 1, 0.95), 1)

# =================================================================== RAY
const _RAY: Array = [
	[Color("a8b4ff"), Color("6f74ea"), Color("463cb2"), Color("29277a")],
	[Color("a8b4ff"), Color("6f74ea"), Color("463cb2"), Color("29277a")],
	[Color("a8b4ff"), Color("6f74ea"), Color("463cb2"), Color("29277a")],
	[Color("a6b6ff"), Color("6c74ee"), Color("4a3db8"), Color("29277a")],
	[Color("b4bcff"), Color("786df2"), Color("5240c2"), Color("2d2580")],
	[Color("c6baff"), Color("8a6cf6"), Color("5b3ec9"), Color("30237f")],
]
const _LAMP := Color("ffd27a")
const _BIO := Color("8ff6ff")

static func _build_ray(b: CreatureParts.Builder, tier: int, phase: float) -> void:
	var ti: int = tier - 1
	var pal: Array = _RAY[ti]
	var hi: Color = pal[0]
	var base: Color = pal[1]
	var lo: Color = pal[2]
	var dark: Color = pal[3]
	var f: float = 1.0 + 0.12 * sin(phase)
	var bend: float = 0.07 * sin(phase)        # wingtips sweep back/forth with the flap
	var oy: float = -0.06
	var sway: float = 0.06 * sin(phase - 0.9)
	# halo (T5/T6): soft cyan wash + ring behind the body
	if tier >= 5:
		b.glow(Vector2(0.0, oy), 1.0, Color(0.55, 0.95, 1.0, 0.42 if tier == 6 else 0.28), 1)
		var rp: PackedVector2Array = CreatureParts.Builder.arc_pairs(Vector2(0.0, oy), 0.93, 0.0, TAU, 40)
		if tier == 5:
			var seg := PackedVector2Array()
			for i in range(0, rp.size(), 4):
				seg.append(rp[i])
				seg.append(rp[i + 1])
			rp = seg
		b.lines(rp, Color(0.75, 1.0, 1.0, 0.55 if tier == 6 else 0.4), 0.024, 1)
	# tail with sway, behind the wings
	var lan := Vector2(-0.70 + sway, 0.58 + oy)
	var tail0 := Vector2(-0.44, 0.0 + oy)
	var tail_c := Vector2(-0.80 + sway * 0.4, 0.12 + oy)
	var tp := PackedVector2Array()
	for i in 9:
		tp.append(CreatureParts.bezier2(tail0, tail_c, lan, float(i) / 8.0))
	b.stroke(tp, dark, 0.075, false, 1)
	b.stroke(tp, base.lerp(lo, 0.3), 0.04, false, 1)
	# lantern glow behind wings keeps it readable
	var lr: float = [0.28, 0.30, 0.32, 0.34, 0.40, 0.46][ti]
	b.glow(lan, lr * 1.5 + 0.03 * sin(phase * 1.5), Color(1.0, 0.82, 0.4, 0.55), 1)
	# cephalic head lobes (behind the body): two short horns curling forward
	for sg in [-1.0, 1.0]:
		var hl := PackedVector2Array([Vector2(0.50, sg * 0.13), Vector2(0.68, sg * 0.14), Vector2(0.86, sg * 0.11), Vector2(0.93, sg * 0.06), Vector2(0.78, sg * 0.04), Vector2(0.60, sg * 0.02)])
		for q in hl.size():
			hl[q] = hl[q] + Vector2(0.0, oy)
		b.blob(hl, 3, base, hi, lo, dark, 1, -1.0, 0.2)
	# body + wings in one silhouette: broad head edge, swept leading edge, concave trailing edge
	var fu: float = f
	var ctrl := PackedVector2Array([
		Vector2(0.64, oy), Vector2(0.60, -0.13 + oy), Vector2(0.50, -0.28 * fu + oy), Vector2(0.38, -0.52 * fu + oy),
		Vector2(0.22, -0.74 * fu + oy), Vector2(0.03 - bend, -0.90 * fu + oy), Vector2(-0.12 - bend, -0.88 * fu + oy),
		Vector2(-0.16, -0.66 * fu + oy), Vector2(-0.24, -0.42 + oy), Vector2(-0.36, -0.20 + oy), Vector2(-0.50, -0.07 + oy), Vector2(-0.54, oy),
		Vector2(-0.50, 0.07 + oy), Vector2(-0.36, 0.20 + oy), Vector2(-0.24, 0.42 + oy), Vector2(-0.16, 0.66 * fu + oy), Vector2(-0.12 - bend, 0.88 * fu + oy),
		Vector2(0.03 - bend, 0.90 * fu + oy), Vector2(0.22, 0.74 * fu + oy), Vector2(0.38, 0.52 * fu + oy),
		Vector2(0.50, 0.28 * fu + oy), Vector2(0.60, 0.13 + oy)])
	var body: PackedVector2Array = b.blob(ctrl, 4, base, hi, lo, dark, 1, -1.0, 0.12)
	# wing ribs
	var rib := PackedVector2Array()
	for sg in [-1.0, 1.0]:
		for q in 3:
			var t: float = float(q) / 2.0
			var a := Vector2(0.30 - 0.14 * t, sg * (0.12 + 0.04 * t) + oy)
			var m := Vector2(0.24 - 0.12 * t - bend * 0.5, sg * (0.42 + 0.06 * t) * fu + oy)
			var e := Vector2(0.09 - 0.24 * t - bend, sg * (0.76 - 0.14 * t) * fu + oy)
			for j in 4:
				var t2: float = float(j) / 3.0
				var t3: float = float(j + 1) / 3.0
				rib.append(CreatureParts.bezier2(a, m, e, t2))
				rib.append(CreatureParts.bezier2(a, m, e, t3))
	b.lines(rib, Color(hi.r, hi.g, hi.b, 0.34), 0.02, 2)
	# leading-edge sheen (lod 2) + fine speckle and gill lines (lod 3)
	var sheen := PackedVector2Array()
	for sg in [-1.0, 1.0]:
		var lp: Array = [Vector2(0.52, sg * 0.22 + oy), Vector2(0.40, sg * 0.46 * fu + oy), Vector2(0.24, sg * 0.69 * fu + oy), Vector2(0.06 - bend, sg * 0.83 * fu + oy)]
		for j in 3:
			sheen.append(lp[j])
			sheen.append(lp[j + 1])
	b.lines(sheen, Color(1, 1, 1, 0.30 if tier < 5 else 0.42), 0.03, 2)
	var gl := PackedVector2Array()
	for sg in [-1.0, 1.0]:
		for q in 3:
			var gx: float = 0.28 - 0.17 * float(q)
			gl.append(Vector2(gx, sg * 0.10 + oy))
			gl.append(Vector2(gx - 0.05, sg * 0.20 + oy))
	b.lines(gl, _mul(dark, 0.45), 0.02, 3)
	var spc: Array = []
	for i in 30:
		var ga2: float = float(i) * 2.39996
		var gd2: float = 0.2 + 0.55 * sqrt(float(i) / 30.0)
		var pp := Vector2(0.05 + cos(ga2) * gd2 * 0.6, sin(ga2) * gd2 * fu + oy)
		if absf(pp.y - oy) > 0.2 and pp.x > -0.2 and pp.x < 0.3 and absf(pp.y - oy) < 0.7:
			spc.append(pp)
	b.dots(spc, 0.014, Color(hi.r, hi.g, hi.b, 0.55), 3, 6)
	# pale belly spindle + shoulder chevrons
	var belly := PackedVector2Array([Vector2(0.56, oy), Vector2(0.38, -0.09 + oy), Vector2(0.0, -0.12 + oy), Vector2(-0.30, -0.07 + oy), Vector2(-0.46, oy), Vector2(-0.30, 0.07 + oy), Vector2(0.0, 0.12 + oy), Vector2(0.38, 0.09 + oy)])
	var pale_hi := Color("e9e6ff")
	var pale := Color("d9d6fb")
	var pale_lo := Color("a9a7e6")
	b.blob(belly, 4, pale, pale_hi, pale_lo, dark.lerp(pale, 0.35), 1, -0.6, 0.25)
	if tier >= 2:
		var ch: Array = []
		var cc: Array = []
		for sg in [-1.0, 1.0]:
			ch.append(PackedVector2Array([Vector2(0.45, sg * 0.21 + oy), Vector2(0.31, sg * 0.46 * fu + oy), Vector2(0.20, sg * 0.40 * fu + oy), Vector2(0.30, sg * 0.17 + oy)]))
			cc.append(Color(0.93, 0.92, 1.0, 0.55))
		b.flat_mesh(ch, cc, 2)
	# eyes
	for sg in [-1.0, 1.0]:
		var ep := Vector2(0.50, sg * 0.20 + oy)
		b.circle(ep, 0.058, Color(0.05, 0.05, 0.2, 0.9))
		b.circle(ep, 0.045, Color("151538"))
		b.circle(ep + Vector2(-0.015, -0.017), 0.016, Color(1, 1, 1, 0.95))
	# bioluminescent markings: dots (T4+), stripes (T5+), rim glow + stars (T6)
	var dots_u: Array = []
	var d_t: Array = [Vector2(0.27, -0.44), Vector2(0.12, -0.60), Vector2(0.0, -0.72)]
	if tier >= 5:
		d_t.append_array([Vector2(0.40, -0.32), Vector2(-0.12, -0.36), Vector2(0.04, -0.46)])
	if tier >= 6:
		d_t.append_array([Vector2(0.16, -0.28), Vector2(-0.08, -0.52), Vector2(-0.24, -0.20)])
	if tier <= 3:
		d_t = [Vector2(0.14, -0.52)]
	for q in d_t:
		var dq: Vector2 = q
		dots_u.append(Vector2(dq.x - bend * 0.5 * (-dq.y), dq.y * fu + oy))
		dots_u.append(Vector2(dq.x - bend * 0.5 * (-dq.y), -dq.y * fu + oy))
	b.dots(dots_u, 0.082, Color(_BIO.r, _BIO.g, _BIO.b, 0.28), 1, 10)
	var core_r: Array = []
	for i in dots_u.size():
		core_r.append(0.038 if i % 4 < 2 else 0.030)
	b.dots(dots_u, core_r, _BIO, 1, 8)
	b.dots(dots_u, 0.016, Color(1, 1, 1, 0.9), 2, 6)
	if tier >= 5:
		var st := PackedVector2Array()
		for sg in [-1.0, 1.0]:
			var a1 := Vector2(0.42, sg * 0.22 * fu + oy)
			var m1 := Vector2(0.28, sg * 0.46 * fu + oy)
			var e1 := Vector2(0.10 - bend, sg * 0.74 * fu + oy)
			for j in 6:
				st.append(CreatureParts.bezier2(a1, m1, e1, float(j) / 6.0))
				st.append(CreatureParts.bezier2(a1, m1, e1, float(j + 1) / 6.0))
		b.lines(st, Color(_BIO.r, _BIO.g, _BIO.b, 0.34), 0.07, 2)
		b.lines(st, Color(0.85, 1, 1, 0.85), 0.022, 1)
	if tier >= 6:
		var rm := PackedVector2Array()
		for sg in [-1.0, 1.0]:
			var pts: Array = [Vector2(0.0 - bend, sg * 0.74 * fu + oy), Vector2(-0.09 - bend * 0.6, sg * 0.58 * fu + oy), Vector2(-0.16, sg * 0.40 + oy), Vector2(-0.31, sg * 0.20 + oy)]
			for j in 3:
				rm.append(pts[j])
				rm.append(pts[j + 1])
		b.lines(rm, Color(0.8, 1.0, 1.0, 0.65), 0.028, 2)
		b.sparkle(Vector2(0.30, -0.50 * fu + oy), 0.10, Color("e8ffff"), 0.5, 2)
		b.sparkle(Vector2(-0.02, 0.60 * fu + oy), 0.08, Color("e8ffff"), 1.5, 2)
	# lantern orb on top
	b.circle(lan + Vector2(0.0, -0.095), 0.04, dark, 1)
	b.circle(lan, lr * 0.44, Color("b9731a"), 1)
	b.circle(lan, lr * 0.36, _LAMP, 1)
	b.circle(lan + Vector2(0.015, 0.015), lr * 0.22, Color("fff0b8"), 1)
	b.circle(lan + Vector2(-0.035, -0.04), lr * 0.10, Color(1, 1, 1, 0.95), 2)
	if tier >= 6:
		b.sparkle(lan, 0.20, Color("fff3c0"), 0.0, 1)

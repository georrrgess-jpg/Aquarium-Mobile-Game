class_name CreatureParts
extends RefCounted
## Geometry + shading helpers for CreatureArt. Creatures are described once as a
## small retained "display list" of ops in unit space (radius ~1), cached per
## (code, flip, phase-bucket), and replayed with a scaled draw transform. Shaded
## fills are cached ArrayMeshes (triangle fans with vertex colours), so a creature
## costs a handful of cheap draw_* calls and no per-frame polygon triangulation.
## Key light comes from the top-left: gradients and highlights follow LIGHT.

const LIGHT := Vector2(-0.5547, -0.8321)

const OP_MESH := 0     # [0, lod, mesh]
const OP_FILL := 1     # [1, lod, pts, col]
const OP_STROKE := 2   # [2, lod, pts, col, w, closed]
const OP_CIRCLE := 3   # [3, lod, c, r, col]
const OP_ARC := 4      # [4, lod, c, r, a0, a1, col, w]
const OP_LINES := 5    # [5, lod, pairs, col, w]
const OP_DYN := 6      # [6, lod, kind, ...]
const OP_GLOW := 7     # [7, lod, c, r, col]

const DYN_WHISKER := 0 # [6, lod, 0, base, ctrl, tip, w, col, seed]
const DYN_SPARKLE := 1 # [6, lod, 1, pos, r, col, seed]

## Stroke width marker: "the outline width" (a few px, set per draw size).
const OUTLINE := -1.0

static var _glow: ArrayMesh

# ---------------------------------------------------------------- geometry
static func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

static func spline_closed(c: PackedVector2Array, sub: int) -> PackedVector2Array:
	var n: int = c.size()
	var out := PackedVector2Array()
	for i in n:
		var p0: Vector2 = c[(i - 1 + n) % n]
		var p1: Vector2 = c[i]
		var p2: Vector2 = c[(i + 1) % n]
		var p3: Vector2 = c[(i + 2) % n]
		for s in sub:
			out.append(_cr(p0, p1, p2, p3, float(s) / float(sub)))
	return out

static func spline_open(c: PackedVector2Array, sub: int) -> PackedVector2Array:
	var n: int = c.size()
	var out := PackedVector2Array()
	for i in n - 1:
		var p0: Vector2 = c[maxi(i - 1, 0)]
		var p1: Vector2 = c[i]
		var p2: Vector2 = c[i + 1]
		var p3: Vector2 = c[mini(i + 2, n - 1)]
		for s in sub:
			out.append(_cr(p0, p1, p2, p3, float(s) / float(sub)))
	out.append(c[n - 1])
	return out

static func ellipse(c: Vector2, a: float, b: float, ang: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ca: float = cos(ang)
	var sa: float = sin(ang)
	for i in n:
		var t: float = TAU * float(i) / float(n)
		var x: float = cos(t) * a
		var y: float = sin(t) * b
		out.append(c + Vector2(x * ca - y * sa, x * sa + y * ca))
	return out

static func bezier2(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)

static func centroid(pts: PackedVector2Array) -> Vector2:
	var s := Vector2.ZERO
	for p in pts:
		s += p
	return s / float(maxi(pts.size(), 1))

static func xform(pts: PackedVector2Array, off: Vector2, ang: float, sc: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ca: float = cos(ang)
	var sa: float = sin(ang)
	for p in pts:
		var q: Vector2 = p * sc
		out.append(off + Vector2(q.x * ca - q.y * sa, q.x * sa + q.y * ca))
	return out

# ------------------------------------------------------------ colour helpers
static func shade_cols(pts: PackedVector2Array, cen: Vector2, base: Color, hi: Color, lo: Color, k_hi: float, k_lo: float) -> PackedColorArray:
	var cols := PackedColorArray()
	for p in pts:
		var d: Vector2 = p - cen
		var l: float = d.length()
		var t: float = 0.0 if l < 0.0001 else d.dot(LIGHT) / l
		if t >= 0.0:
			cols.append(base.lerp(hi, clampf(t, 0.0, 1.0) * k_hi))
		else:
			cols.append(base.lerp(lo, clampf(-t, 0.0, 1.0) * k_lo))
	return cols

static func fan_mesh(pts: PackedVector2Array, cols: PackedColorArray, centre: Vector2, ccol: Color) -> ArrayMesh:
	var n: int = pts.size()
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	verts.append(centre)
	colors.append(ccol)
	for i in n:
		verts.append(pts[i])
		colors.append(cols[i])
		idx.append(0)
		idx.append(i + 1)
		idx.append((i + 1) % n + 1)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## One mesh from many small flat-coloured fans (each poly star-shaped about its mean).
static func merged_mesh(polys: Array, cols: Array) -> ArrayMesh:
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	for k in polys.size():
		var pts: PackedVector2Array = polys[k]
		var col: Color = cols[k]
		var base: int = verts.size()
		verts.append(centroid(pts))
		colors.append(col)
		var n: int = pts.size()
		for i in n:
			verts.append(pts[i])
			colors.append(col)
			idx.append(base)
			idx.append(base + i + 1)
			idx.append(base + (i + 1) % n + 1)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## Unit radial glow disc: white, alpha 1 in the middle fading to 0 at radius 1.
static func glow_mesh() -> ArrayMesh:
	if _glow != null:
		return _glow
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var segs: int = 28
	verts.append(Vector2.ZERO)
	colors.append(Color(1, 1, 1, 1.0))
	var rings: Array = [[0.45, 0.62], [0.75, 0.22], [1.0, 0.0]]
	for ri in rings.size():
		for i in segs:
			var a: float = TAU * float(i) / float(segs)
			verts.append(Vector2(cos(a), sin(a)) * float(rings[ri][0]))
			colors.append(Color(1, 1, 1, float(rings[ri][1])))
	for i in segs:
		var i2: int = (i + 1) % segs
		idx.append(0); idx.append(1 + i); idx.append(1 + i2)
		for ri in 2:
			var a0: int = 1 + ri * segs
			var b0: int = 1 + (ri + 1) * segs
			idx.append(a0 + i); idx.append(b0 + i); idx.append(b0 + i2)
			idx.append(a0 + i); idx.append(b0 + i2); idx.append(a0 + i2)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = idx
	_glow = ArrayMesh.new()
	_glow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _glow

# ----------------------------------------------------------------- Builder
class Builder extends RefCounted:
	## Everything is emitted in PIXEL space at the builder's unit size `u`
	## (design space radius 1 -> u px), so AA'd lines keep crisp 1-2px feathers.
	var ops: Array = []
	var fx: float = 1.0
	var u: float = 24.0
	var ow: float = 1.9
	var gs: float = 1.0                 # design-space growth factor (geometry only, not line widths)
	var off: Vector2 = Vector2.ZERO     # design-space centring offset (before the flip)

	func pv(v: Vector2) -> Vector2:
		return Vector2((v.x + off.x) * fx, v.y + off.y) * (u * gs)

	func fl(pts: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		var g: float = u * gs
		for p in pts:
			out.append(Vector2((p.x + off.x) * fx, p.y + off.y) * g)
		return out

	func px(w: float) -> float:
		if w < 0.0:
			return ow * -w
		return maxf(w * u, 1.0)

	func closed(pts: PackedVector2Array) -> PackedVector2Array:
		var out := pts.duplicate()
		out.append(pts[0])
		return out

	## Shaded filled polygon (+ outline stroke). pts in design space (facing right).
	func poly(pts_in: PackedVector2Array, base: Color, hi: Color, lo: Color, line: Color, lod: int = 1, line_w: float = -1.0, shift: float = 0.30, k_hi: float = 0.85, k_lo: float = 1.0) -> PackedVector2Array:
		var pts: PackedVector2Array = fl(pts_in)
		var cen: Vector2 = CreatureParts.centroid(pts)
		var rad: float = 0.0
		for p in pts:
			rad += (p - cen).length()
		rad /= float(pts.size())
		var cols: PackedColorArray = CreatureParts.shade_cols(pts, cen, base, hi, lo, k_hi, k_lo)
		var ctr: Vector2 = cen + CreatureParts.LIGHT * rad * shift
		var m: ArrayMesh = CreatureParts.fan_mesh(pts, cols, ctr, base.lerp(hi, 0.8))
		ops.append([CreatureParts.OP_MESH, lod, m])
		if line_w != 0.0:
			ops.append([CreatureParts.OP_STROKE, lod, closed(pts), line, px(line_w), true])
		return pts

	func blob(ctrl: PackedVector2Array, sub: int, base: Color, hi: Color, lo: Color, line: Color, lod: int = 1, line_w: float = -1.0, shift: float = 0.30) -> PackedVector2Array:
		return poly(CreatureParts.spline_closed(ctrl, sub), base, hi, lo, line, lod, line_w, shift)

	func fill(pts: PackedVector2Array, col: Color, lod: int = 1) -> void:
		ops.append([CreatureParts.OP_FILL, lod, fl(pts), col])

	func flat_mesh(polys: Array, cols: Array, lod: int = 1) -> void:
		var fp: Array = []
		for p in polys:
			fp.append(fl(p))
		ops.append([CreatureParts.OP_MESH, lod, CreatureParts.merged_mesh(fp, cols)])

	func stroke(pts: PackedVector2Array, col: Color, w: float, is_closed: bool = false, lod: int = 1) -> void:
		var p: PackedVector2Array = fl(pts)
		if is_closed:
			p = closed(p)
		ops.append([CreatureParts.OP_STROKE, lod, p, col, px(w), is_closed])

	func circle(c: Vector2, r: float, col: Color, lod: int = 1) -> void:
		ops.append([CreatureParts.OP_CIRCLE, lod, pv(c), r * u * gs, col])

	## Many flat dots in a single mesh. radii: float or Array.
	func dots(centres: Array, radii: Variant, col: Color, lod: int = 1, n: int = 8) -> void:
		var polys: Array = []
		var cols: Array = []
		for i in centres.size():
			var r: float = float(radii[i]) if radii is Array else float(radii)
			polys.append(CreatureParts.ellipse(centres[i], r, r, 0.0, n))
			cols.append(col)
		flat_mesh(polys, cols, lod)

	func arc(c: Vector2, r: float, a0: float, a1: float, col: Color, w: float, lod: int = 1) -> void:
		var s: float = a0
		var e: float = a1
		if fx < 0.0:
			s = PI - a1
			e = PI - a0
		ops.append([CreatureParts.OP_ARC, lod, pv(c), r * u * gs, s, e, col, px(w)])

	func lines(pairs: PackedVector2Array, col: Color, w: float, lod: int = 1) -> void:
		ops.append([CreatureParts.OP_LINES, lod, fl(pairs), col, px(w)])

	func glow(c: Vector2, r: float, col: Color, lod: int = 1) -> void:
		ops.append([CreatureParts.OP_GLOW, lod, pv(c), r * u * gs, col])

	func whisker(base: Vector2, ctrl: Vector2, tip: Vector2, w: float, col: Color, seed_v: float, lod: int = 1) -> void:
		ops.append([CreatureParts.OP_DYN, lod, CreatureParts.DYN_WHISKER, pv(base), pv(ctrl), pv(tip), px(w), col, seed_v, u * gs])

	func sparkle(pos: Vector2, r: float, col: Color, seed_v: float, lod: int = 1) -> void:
		ops.append([CreatureParts.OP_DYN, lod, CreatureParts.DYN_SPARKLE, pv(pos), r * u * gs, col, seed_v, px(0.03)])

	## Polyline of a sampled arc, turned into segment pairs for OP_LINES.
	static func arc_pairs(c: Vector2, r: float, a0: float, a1: float, steps: int) -> PackedVector2Array:
		var out := PackedVector2Array()
		var prev: Vector2 = c + Vector2(cos(a0), sin(a0)) * r
		for i in range(1, steps + 1):
			var a: float = lerpf(a0, a1, float(i) / float(steps))
			var p: Vector2 = c + Vector2(cos(a), sin(a)) * r
			out.append(prev)
			out.append(p)
			prev = p
		return out

class_name ReefView
extends Control
## Side-view aquarium. Two draw layers keep it cheap:
##  * the STATIC layer (water, sand, rocks, still decorations and the residents that
##    are not currently animated) redraws only when its content or size changes;
##  * the DYNAMIC layer (weeds, bubbles, animated decorations, the few animated
##    residents, placement markers, highlights) redraws at a gentle 30 fps, or not
##    at all with reduced motion / when the view is hidden.
## Every resident lives in the roster; only MAX_DRAWN are drawn here and only
## MAX_ANIMATED of those move (newest and highest tiers first).

signal tapped
signal slot_tapped(slot: int)
signal visitor_tapped

var residents: Array = []
var decorations: Array = []
var highlight_ids: Array = []          # resident ids to show as "new"
var placing_kind: int = -1             # decoration being placed (marks free slots), -1 = none
var selected_slot: int = -1
var visitor: Dictionary = {}           # Update 3: {visible, accepted, progress_text, t0}
## 0 (day) .. 1 (night): how strongly lanterns glow and light shafts fade.
var night_amount: float = 0.0
var _arrival_t0: float = -10.0         # when the newest residents arrived (swim-in + splash)
var palette: Dictionary = BgArt.palette(Tide.MIDDAY):
	set(v):
		palette = v
		_invalidate()
var reduced_motion: bool = false:
	set(v):
		reduced_motion = v
		_dyn.queue_redraw()
## Compact mode is the strip under the pool: fewer, smaller creatures and a caption.
var compact: bool = false:
	set(v):
		compact = v
		_invalidate()
var caption: String = "":
	set(v):
		caption = v
		_static.invalidate()
var empty_text: String = "Your reef is empty. Release a tier 4+ creature through the Reef Gate to start it."

## Set by the owner to rest the idle animation (e.g. while the pool is busy).
var paused: bool = false
var _static: BakedLayer
var _dyn: Layer
var _t: float = 0.0
var _since_draw: float = 0.0
var _press_pos: Vector2 = Vector2.ZERO
var _drawn: Array = []                 # prepared resident draw records
var _animated: Array = []
var _more: int = 0
var _prepared_size: Vector2 = Vector2.ZERO
var _sb_marker: StyleBoxFlat = StyleBoxFlat.new()

class Layer extends Control:
	var view: Control
	var mode: int = 0
	func _init(v: Control, m: int) -> void:
		view = v
		mode = m
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		view.call("_draw_layer", self, mode)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_static = BakedLayer.new()
	_static.painter = func(ci: Control) -> void: _draw_layer(ci, 0)
	_dyn = Layer.new(self, 1)
	add_child(_static)
	add_child(_dyn)
	_sb_marker.bg_color = Color(0, 0, 0, 0)
	_sb_marker.set_corner_radius_all(10)
	_sb_marker.anti_aliasing = true
	resized.connect(_on_resized)

func _on_resized() -> void:
	_static.size = size
	_dyn.size = size
	_invalidate()

func _invalidate() -> void:
	_prepared_size = Vector2.ZERO
	if _static != null:
		_static.invalidate()
		_dyn.queue_redraw()

func set_residents(list: Array) -> void:
	residents = list
	_invalidate()

func set_decorations(list: Array) -> void:
	decorations = list
	_invalidate()

func set_highlight(ids: Array) -> void:
	highlight_ids = ids
	if not ids.is_empty():
		_arrival_t0 = _t
	_invalidate()

func set_placement(kind: int, slot: int) -> void:
	placing_kind = kind
	selected_slot = slot
	_dyn.queue_redraw()

func _process(delta: float) -> void:
	if paused or reduced_motion or not is_visible_in_tree():
		return
	_t += delta
	_since_draw += delta
	# gentle idle motion: the small strip under the pool needs far fewer redraws than the hub
	if _since_draw >= (1.0 / (12.0 if compact else 15.0)):
		_since_draw = 0.0
		_dyn.queue_redraw()

# --- Input ---------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_press_pos = mb.position
		return
	if _press_pos.distance_to(mb.position) >= 14.0:
		return
	if placing_kind >= 0:
		for i in GameConfig.DECOR_SLOTS.size():
			if slot_rect(i).grow(10.0).has_point(mb.position) and not _slot_owned(i):
				slot_tapped.emit(i)
				return
		return
	if bool(visitor.get("visible", false)) and visitor_rect().has_point(mb.position):
		visitor_tapped.emit()
		return
	tapped.emit()

func _slot_owned(i: int) -> bool:
	for d in decorations:
		if int(d["slot"]) == i:
			return true
	return false

func sand_top() -> float:
	return size.y * 0.80

## Where decoration slot i stands (base on the sand).
func slot_rect(i: int) -> Rect2:
	var w: float = clampf(size.x * 0.15, 44.0, 96.0)
	var hh: float = w * 1.3
	var cx: float = size.x * float(GameConfig.DECOR_SLOTS[i])
	var base_y: float = sand_top() + size.y * 0.115
	return Rect2(cx - w * 0.5, base_y - hh, w, hh)

func visitor_rect() -> Rect2:
	var s: float = clampf(size.x * 0.22, 60.0, 120.0)
	var p: Vector2 = _visitor_pos()
	return Rect2(p - Vector2(s, s * 0.7) * 0.5, Vector2(s, s * 0.7))

func _visitor_pos() -> Vector2:
	var arrive: float = clampf((_t - float(visitor.get("t0", 0.0))) / 2.2, 0.0, 1.0)
	if reduced_motion:
		arrive = 1.0
	var ease_v: float = 1.0 - pow(1.0 - arrive, 3.0)
	var hover_y: float = size.y * 0.30 + (0.0 if reduced_motion else sin(_t * 1.1) * 5.0)
	var x: float = lerpf(-size.x * 0.15, size.x * 0.72, ease_v) + (0.0 if reduced_motion else sin(_t * 0.5) * 8.0 * ease_v)
	return Vector2(x, hover_y)

static func _hash01(n: int, salt: float) -> float:
	return fposmod(sin(float(n) * 12.9898 + salt * 78.233) * 43758.5453, 1.0)

# --- Preparation ---------------------------------------------------------------------------------

func _prepare() -> void:
	_prepared_size = size
	var cap_drawn: int = 8 if compact else GameConfig.MAX_DRAWN_RESIDENTS
	var cap_anim: int = 4 if compact else GameConfig.MAX_ANIMATED_RESIDENTS
	var order: Array = residents.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var na: bool = highlight_ids.has(int(a["id"]))
		var nb: bool = highlight_ids.has(int(b["id"]))
		if na != nb:
			return na
		if int(a["tier"]) != int(b["tier"]):
			return int(a["tier"]) > int(b["tier"])
		return int(a["id"]) > int(b["id"]))
	_more = maxi(0, order.size() - cap_drawn)
	if order.size() > cap_drawn:
		order.resize(cap_drawn)
	_drawn = []
	_animated = []
	var w: float = size.x
	var h: float = size.y
	var base: float = clampf(w / maxf(4.0, float(order.size()) * 0.55 + 2.0), 38.0 if compact else 46.0, 78.0 if compact else 92.0)
	if compact:
		base = minf(base, h * 0.40)
	base = floorf(base)                        # whole pixels: creature art caches by integer size
	var sand: float = sand_top()
	for i in order.size():
		var r: Dictionary = order[i]
		var id: int = int(r["id"])
		var spread: float = fposmod(float(i) * 0.6180339 + 0.11, 1.0)
		var cx: float = w * (0.07 + 0.86 * spread)
		var fam: int = int(r["family"])
		var rec: Dictionary = {
			"code": int(r["code"]), "id": id, "base": base, "cx": cx, "family": fam,
			"phase": _hash01(id, 8.0) * TAU, "speed": 0.18 + 0.22 * _hash01(id, 7.0),
			"range": minf(w / maxf(4.0, float(order.size())) * 0.5, 60.0),
			"lane": (0.28 + 0.34 * _hash01(id, 9.0)) * (0.92 if compact else 1.0),
			"star": fam == Creature.STAR, "ray": fam == Creature.RAY, "new": highlight_ids.has(id),
			"sand_y": sand + (h - sand) * (0.16 + 0.22 * _hash01(id, 11.0)) - base * 0.10,
		}
		if fam == Creature.RAY:                # rays glide high and wide
			rec["lane"] = (0.16 + 0.16 * _hash01(id, 9.0)) * (0.92 if compact else 1.0)
			rec["range"] = minf(w * 0.30, 130.0)
			rec["speed"] = 0.10 + 0.08 * _hash01(id, 7.0)
		rec["animated"] = i < cap_anim
		if i < cap_anim:
			_animated.append(rec)
		_drawn.append(rec)

## Where a resident is at time t, plus its facing and rotation. Each family has its own idle loop:
## shrimp bob and, every few seconds, flick backwards in a quick dart; starfish sway very slowly and
## creep; rays glide in long lazy arcs with a steady wing beat.
func _resident_pose(rec: Dictionary, t: float) -> Dictionary:
	var base: float = float(rec["base"])
	var w: float = size.x
	var cx: float = float(rec["cx"])
	var ph: float = float(rec["phase"])
	var pos: Vector2
	var facing_right: bool = true
	var rot: float = 0.0
	if bool(rec["star"]):
		var px: float = cx + sin(t * 0.12 + ph) * minf(24.0, float(rec["range"]) * 0.5)
		pos = Vector2(px, float(rec["sand_y"]))
		rot = sin(t * 0.35 + ph) * 0.12
	elif bool(rec["ray"]):
		var ang: float = t * float(rec["speed"]) + ph
		pos = Vector2(cx + sin(ang) * float(rec["range"]), size.y * float(rec["lane"]) + sin(ang * 1.7) * size.y * 0.06)
		facing_right = cos(ang) > 0.0
		rot = cos(ang * 1.7) * 0.10 * (1.0 if facing_right else -1.0)
	else:
		var ang2: float = t * float(rec["speed"]) + ph
		var px2: float = cx + sin(ang2) * float(rec["range"])
		var py: float = size.y * float(rec["lane"]) * 0.85 + sin(t * 1.1 + ph) * 5.0
		facing_right = cos(ang2) > 0.0
		# the dart: a short, fast backwards flick once per ~5 s
		var cyc: float = fposmod(t / 5.0 + ph / TAU, 1.0)
		if cyc < 0.07:
			var k: float = sin(PI * cyc / 0.07)
			px2 += (-1.0 if facing_right else 1.0) * 34.0 * k
			py -= 6.0 * k
		pos = Vector2(px2, py)
		rot = sin(t * 1.4 + ph) * 0.06
	if bool(rec["ray"]):
		pos.y = clampf(pos.y, base * 0.5 + 6.0, sand_top() - base * 0.7)
	elif not bool(rec["star"]):
		pos.y = clampf(pos.y, base * 0.5 + 6.0, sand_top() - base * 0.5)
	pos.x = clampf(pos.x, base * 0.62, w - base * 0.62)
	return {"pos": pos, "right": facing_right, "rot": rot}

func _resident_pos(rec: Dictionary, t: float) -> Vector2:
	return _resident_pose(rec, t)["pos"]

func _draw_resident(layer: Control, rec: Dictionary, t: float, animated: bool) -> void:
	var pose: Dictionary = _resident_pose(rec, t if animated else 0.0)
	var pos: Vector2 = pose["pos"]
	var base: float = float(rec["base"])
	var alpha: float = 1.0
	# arrival: a new resident drops in from above and settles with a splash ring
	if bool(rec["new"]) and animated:
		var age: float = t - _arrival_t0
		if age >= 0.0 and age < 1.3:
			var k: float = clampf(age / 0.9, 0.0, 1.0)
			var e: float = 1.0 - pow(1.0 - k, 3.0)
			pos.y = lerpf(-base, pos.y, e)
			alpha = clampf(age / 0.25, 0.0, 1.0)
			if age > 0.8 and age < 1.3:
				var rk: float = (age - 0.8) / 0.5
				layer.draw_arc(Vector2(pos.x, pos.y + base * 0.35), base * (0.4 + 0.9 * rk), PI * 1.1, PI * 1.9, 18, Color(1, 1, 1, 0.7 * (1.0 - rk)), 3.0, true)
	var opts: Dictionary = {"alpha": alpha, "rot": float(pose["rot"]) if animated else 0.0}
	if bool(rec["star"]):
		opts["phase"] = t * 0.8 + float(rec["phase"])
	elif bool(rec["ray"]):
		opts["phase"] = t * 3.2 + float(rec["phase"])       # steady wing beat
		opts["flip"] = not bool(pose["right"])
	else:
		opts["flip"] = not bool(pose["right"])
		opts["phase"] = t * 3.0 + float(rec["phase"])
	CreatureArt.draw_creature(layer, int(rec["code"]), pos, base, opts)

# --- Drawing -----------------------------------------------------------------------------------

func _draw_layer(layer: Control, mode: int) -> void:
	if size.x < 4.0 or size.y < 4.0:
		return
	if _prepared_size != size:
		_prepare()
	if mode == 0:
		_draw_static(layer)
	else:
		_draw_dynamic(layer as Layer)

func _draw_static(ci: Control) -> void:
	var w: float = size.x
	var h: float = size.y
	var rect := Rect2(0, 0, w, h)
	BgArt.draw_reef_far(ci, rect, palette)
	BgArt.draw_reef_mid(ci, rect, palette)
	# residents that are not animated (they stand still on the sand or hang in the water)
	for rec in _drawn:
		if not bool(rec["animated"]):
			_draw_resident(ci, rec, 0.0, false)
	if residents.is_empty():
		var font: Font = ThemeDB.fallback_font
		var fs: int = 15 if compact else 18
		var txt: String = "Empty so far. Release a tier 4+ creature to start your reef." if compact else empty_text
		_draw_wrapped(ci, font, txt, Vector2(w * 0.5, h * (0.62 if compact else 0.38)), w * 0.86, fs, Color(Pal.TEXT, 0.95))
	if caption != "":
		var f2: Font = ThemeDB.fallback_font
		var tw: float = f2.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		ci.draw_rect(Rect2(8, 6, tw + 14, 24), Color(0.03, 0.2, 0.26, 0.7))
		ci.draw_string(f2, Vector2(15, 24), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.TEXT)
	if _more > 0:
		var f3: Font = ThemeDB.fallback_font
		var label: String = "+%d more in the roster" % _more
		var lw: float = f3.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		ci.draw_rect(Rect2(w - lw - 20, h - 28, lw + 14, 22), Color(0.03, 0.2, 0.26, 0.7))
		ci.draw_string(f3, Vector2(w - lw - 13, h - 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Pal.TEXT)

func _draw_dynamic(ci: Layer) -> void:
	var w: float = size.x
	var h: float = size.y
	var t: float = 0.0 if reduced_motion else _t
	var rect := Rect2(0, 0, w, h)
	# decorations: each one changes the scene around it (light pool, beam, bubble stream, ...)
	for d in decorations:
		var kind: int = _kind_of(String(d["id"]))
		if kind >= 0:
			var sr: Rect2 = slot_rect(int(d["slot"]))
			DecorArt.world_effect(ci, kind, sr, rect, t, night_amount)
	for d in decorations:
		var kind2: int = _kind_of(String(d["id"]))
		if kind2 >= 0:
			DecorArt.draw(ci, kind2, slot_rect(int(d["slot"])), t, {"animate": not reduced_motion, "badge": false})
	# animated residents
	for rec in _animated:
		_draw_resident(ci, rec, t, not reduced_motion)
	# drifting kelp, bubbles and the ambient fish school pass in front
	BgArt.draw_reef_front(ci, rect, palette, t, not reduced_motion)
	# "new resident" highlight: pulsing ring + NEW tag (shape, not just colour)
	for rec in _drawn:
		if bool(rec["new"]):
			var pos: Vector2 = _resident_pos(rec, t if bool(rec["animated"]) else 0.0)
			var pulse: float = 0.5 + 0.5 * sin(t * 5.0) if not reduced_motion else 0.5
			var rr: float = float(rec["base"]) * (0.68 + 0.05 * pulse)
			ci.draw_arc(pos, rr, 0.0, TAU, 28, Color(Pal.GOLD, 0.7 + 0.3 * pulse), 3.0, true)
			var font: Font = ThemeDB.fallback_font
			var tag := Rect2(pos + Vector2(-17, -rr - 20), Vector2(34, 18))
			ci.draw_rect(tag, Pal.GOLD)
			ci.draw_string(font, tag.position + Vector2(0, 14), "NEW", HORIZONTAL_ALIGNMENT_CENTER, 34, 13, Pal.INK)
	# placement markers and ghost
	if placing_kind >= 0:
		for i in GameConfig.DECOR_SLOTS.size():
			var rc: Rect2 = slot_rect(i)
			var taken: bool = _slot_owned(i)
			var chosen: bool = i == selected_slot
			if taken:
				continue
			var base_rc := Rect2(rc.position + Vector2(0, rc.size.y * 0.55), Vector2(rc.size.x, rc.size.y * 0.45))
			var col: Color = Pal.GOLD if chosen else Color(Pal.TARGET, 0.9)
			_dashed_rect(ci, base_rc, col, 3.0 if chosen else 2.0)
			# slot number: a shape/label cue as well as colour
			var f4: Font = ThemeDB.fallback_font
			ci.draw_string(f4, base_rc.position + Vector2(0, base_rc.size.y * 0.62), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, base_rc.size.x, 18, col)
			if chosen:
				DecorArt.draw(ci, placing_kind, rc, t, {"alpha": 0.62, "animate": not reduced_motion})
	# Update 3 visitor
	if bool(visitor.get("visible", false)):
		_draw_visitor(ci, t)

func _draw_visitor(ci: Layer, t: float) -> void:
	var pos: Vector2 = _visitor_pos()
	var s: float = clampf(size.x * 0.22, 60.0, 120.0)
	var accepted: bool = bool(visitor.get("accepted", false))
	CreatureArt.draw_creature(ci, Creature.make(Creature.RAY, 4), pos, s, {"flip": false, "phase": t * 4.0, "badge": false})
	var pulse: float = 0.5 + 0.5 * sin(t * 4.0) if not reduced_motion else 0.5
	if not accepted:
		# tap-me cue: ring + "!" bubble
		var bc: Vector2 = pos + Vector2(s * 0.38, -s * 0.34)
		ci.draw_circle(bc, 13.0, Pal.GOLD)
		ci.draw_arc(bc, 13.0 + 3.0 * pulse, 0.0, TAU, 18, Color(Pal.GOLD, 0.6), 2.0, true)
		ci.draw_string(ThemeDB.fallback_font, bc + Vector2(-6, 7), "!", HORIZONTAL_ALIGNMENT_CENTER, 12, 20, Pal.INK)

func _kind_of(id: String) -> int:
	for i in GameConfig.DECORATIONS.size():
		if String(GameConfig.DECORATIONS[i]["id"]) == id:
			return i
	return -1

func _decor_animated(kind: int) -> bool:
	return kind == DecorArt.KIND_BUBBLE_COLUMN or kind == DecorArt.KIND_SEA_LANTERN or kind == DecorArt.KIND_LIGHT_SHAFT

func _dashed_rect(ci: Control, r: Rect2, col: Color, width: float) -> void:
	var dash: float = 8.0
	var corners: Array = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var len: float = a.distance_to(b)
		var dir: Vector2 = (b - a) / maxf(len, 0.001)
		var d: float = 0.0
		while d < len:
			ci.draw_line(a + dir * d, a + dir * minf(d + dash, len), col, width)
			d += dash * 2.0

func _draw_wrapped(ci: Control, font: Font, text: String, center: Vector2, width: float, fs: int, col: Color) -> void:
	var words: PackedStringArray = text.split(" ")
	var lines: Array = []
	var cur: String = ""
	for wd in words:
		var trial: String = wd if cur == "" else cur + " " + wd
		if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width and cur != "":
			lines.append(cur)
			cur = wd
		else:
			cur = trial
	if cur != "":
		lines.append(cur)
	var y: float = center.y - float(lines.size()) * fs * 0.6
	# a dark plate behind the text: the water and creatures behind it can be bright (Midday)
	var plate_w: float = 0.0
	for ln0 in lines:
		plate_w = maxf(plate_w, font.get_string_size(String(ln0), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var plate := Rect2(center.x - plate_w * 0.5 - 10.0, y - float(fs) - 4.0, plate_w + 20.0, float(lines.size()) * fs * 1.3 + 10.0)
	ci.draw_rect(plate, Color(0.03, 0.2, 0.26, 0.78))
	for ln in lines:
		ci.draw_string(font, Vector2(center.x - width * 0.5, y), String(ln), HORIZONTAL_ALIGNMENT_CENTER, width, fs, col)
		y += fs * 1.3

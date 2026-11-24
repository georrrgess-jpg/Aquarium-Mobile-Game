class_name ReefView
extends Control
## Side-view aquarium. Every resident is a permanent creature the player has
## released. Shrimp swim lazily around their own patch of water; Starfish creep
## along the sand. With reduced motion everything holds still.

signal tapped

var residents: Array = []
var reduced_motion: bool = false:
	set(v):
		reduced_motion = v
		queue_redraw()
## Compact mode is the little strip under the pool: smaller creatures and a caption.
var compact: bool = false
var caption: String = ""
var empty_text: String = "Your reef is empty. Release a tier 4+ creature through the Reef Gate to start it."
var _t: float = 0.0
var _since_draw: float = 0.0
var _press_pos: Vector2 = Vector2.ZERO

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

func set_residents(list: Array) -> void:
	residents = list
	queue_redraw()

func _process(delta: float) -> void:
	if not visible or not is_visible_in_tree():
		return
	if not reduced_motion:
		_t += delta
		_since_draw += delta
		if _since_draw >= 1.0 / 30.0:   # idle motion is gentle; 30 fps is plenty
			_since_draw = 0.0
			queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press_pos = mb.position
		elif _press_pos.distance_to(mb.position) < 14.0:
			tapped.emit()

static func _hash01(n: int, salt: float) -> float:
	return fposmod(sin(float(n) * 12.9898 + salt * 78.233) * 43758.5453, 1.0)

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 4.0 or h < 4.0:
		return
	var t: float = _t
	# --- water gradient
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color("1d7fa6"), Color("1d7fa6"), Color("0a3550"), Color("0a3550")]))
	# --- light rays
	for k in 4:
		var x0: float = w * (0.12 + 0.24 * float(k)) + sin(t * 0.3 + float(k)) * 18.0
		draw_colored_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x0 + w * 0.10, 0), Vector2(x0 + w * 0.22, h), Vector2(x0 - w * 0.02, h)]), Color(1, 1, 1, 0.045))
	# --- sand
	var sand_top: float = h * 0.82
	var sand := PackedVector2Array()
	sand.append(Vector2(0, h))
	for i in 17:
		var x: float = w * float(i) / 16.0
		sand.append(Vector2(x, sand_top + sin(float(i) * 0.9) * h * 0.018))
	sand.append(Vector2(w, h))
	draw_colored_polygon(sand, Color("d9bd82"))
	var sand2 := PackedVector2Array()
	sand2.append(Vector2(0, h))
	for i in 17:
		var x2: float = w * float(i) / 16.0
		sand2.append(Vector2(x2, sand_top + h * 0.06 + sin(float(i) * 1.3 + 1.0) * h * 0.012))
	sand2.append(Vector2(w, h))
	draw_colored_polygon(sand2, Color("c4a468"))
	# --- rocks and coral (static decor)
	_draw_rock(Vector2(w * 0.07, sand_top + h * 0.03), h * 0.13)
	_draw_rock(Vector2(w * 0.93, sand_top + h * 0.04), h * 0.16)
	_draw_coral(Vector2(w * 0.22, sand_top + h * 0.02), h * 0.20, Color("ff8fab"))
	_draw_coral(Vector2(w * 0.80, sand_top + h * 0.02), h * 0.17, Color("b79cff"))
	# --- seaweed
	for k in 6:
		var bx: float = w * (0.06 + 0.17 * float(k)) + _hash01(k, 1.0) * 14.0
		_draw_weed(Vector2(bx, sand_top + h * 0.03), h * (0.20 + 0.10 * _hash01(k, 2.0)), t, float(k))
	# --- bubbles
	for k in 9:
		var bx2: float = w * _hash01(k, 3.0)
		var speed: float = 14.0 + 22.0 * _hash01(k, 4.0)
		var by: float = fposmod(h - (t * speed + _hash01(k, 5.0) * h), h)
		draw_arc(Vector2(bx2 + sin(t + float(k)) * 5.0, by), 2.0 + 3.0 * _hash01(k, 6.0), 0.0, TAU, 12, Color(1, 1, 1, 0.35), 1.2, true)
	# --- residents
	var n: int = residents.size()
	if n == 0:
		var font: Font = ThemeDB.fallback_font
		var fs: int = 15 if compact else 18
		var tc: Color = Pal.TEXT
		tc.a = 0.9
		var txt: String = "Empty so far. Release a tier 4+ creature to start your reef." if compact else empty_text
		_draw_wrapped(font, txt, Vector2(w * 0.5, h * (0.62 if compact else 0.40)), w * 0.86, fs, tc)
	else:
		_draw_residents(w, h, sand_top, t)
	if caption != "":
		var f2: Font = ThemeDB.fallback_font
		var bg := Color(0.03, 0.12, 0.2, 0.6)
		var tw: float = f2.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_rect(Rect2(8, 6, tw + 14, 24), bg)
		draw_string(f2, Vector2(15, 24), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.TEXT)

func _draw_wrapped(font: Font, text: String, center: Vector2, width: float, fs: int, col: Color) -> void:
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
	for ln in lines:
		draw_string(font, Vector2(center.x - width * 0.5, y), String(ln), HORIZONTAL_ALIGNMENT_CENTER, width, fs, col)
		y += fs * 1.3

func _draw_residents(w: float, h: float, sand_top: float, t: float) -> void:
	var n: int = residents.size()
	var base: float = clampf(w / maxf(4.0, float(n) * 0.55 + 2.0), 38.0 if compact else 46.0, 78.0 if compact else 96.0)
	if compact:
		base = minf(base, h * 0.40)
	# slots: shrimp lanes through the water, starfish along the sand
	var shrimp: Array = []
	var stars: Array = []
	for r in residents:
		if int(r["family"]) == Creature.SHRIMP:
			shrimp.append(r)
		else:
			stars.append(r)
	for i in shrimp.size():
		var r: Dictionary = shrimp[i]
		var id: int = int(r["id"])
		var slot_w: float = w / float(shrimp.size())
		var cx: float = slot_w * (float(i) + 0.5)
		var rng_x: float = minf(slot_w * 0.5, 70.0)
		var spd: float = 0.18 + 0.22 * _hash01(id, 7.0)
		var ph: float = _hash01(id, 8.0) * TAU
		var ang: float = t * spd + ph
		var px: float = cx + sin(ang) * rng_x
		var lane: float = 0.30 + 0.30 * _hash01(id, 9.0)
		var py: float = h * lane * (0.78 if not compact else 0.9) + sin(t * 1.1 + ph) * 5.0
		px = clampf(px, base * 0.62, w - base * 0.62)
		py = clampf(py, base * 0.5 + 6.0, sand_top - base * 0.5)
		var facing_right: bool = cos(ang) > 0.0
		CreatureArt.draw_creature(self, int(r["code"]), Vector2(px, py), base, {"flip": not facing_right, "phase": t * 3.0 + ph, "rot": sin(t * 1.4 + ph) * 0.06})
	for i in stars.size():
		var r2: Dictionary = stars[i]
		var id2: int = int(r2["id"])
		var slot_w2: float = w / float(stars.size())
		var cx2: float = slot_w2 * (float(i) + 0.5)
		var ph2: float = _hash01(id2, 10.0) * TAU
		var px2: float = cx2 + sin(t * 0.12 + ph2) * minf(slot_w2 * 0.3, 26.0)
		px2 = clampf(px2, base * 0.62, w - base * 0.62)
		var py2: float = sand_top + (h - sand_top) * (0.18 + 0.25 * _hash01(id2, 11.0)) - base * 0.12
		CreatureArt.draw_creature(self, int(r2["code"]), Vector2(px2, py2), base, {"rot": sin(t * 0.35 + ph2) * 0.10, "phase": t * 0.8 + ph2})

func _draw_rock(base: Vector2, s: float) -> void:
	draw_colored_polygon(PackedVector2Array([base + Vector2(-s, 0), base + Vector2(-s * 0.7, -s * 0.8), base + Vector2(-s * 0.1, -s), base + Vector2(s * 0.6, -s * 0.6), base + Vector2(s, 0)]), Color("5b6f7d"))
	draw_colored_polygon(PackedVector2Array([base + Vector2(-s * 0.7, -s * 0.8), base + Vector2(-s * 0.1, -s), base + Vector2(0.0, -s * 0.5)]), Color("7b92a1"))

func _draw_coral(base: Vector2, s: float, col: Color) -> void:
	for k in 5:
		var a: float = -PI * 0.5 + (float(k) - 2.0) * 0.5
		var tip: Vector2 = base + Vector2(cos(a), sin(a)) * s
		draw_line(base, tip, col, maxf(3.0, s * 0.12), true)
		draw_circle(tip, maxf(3.0, s * 0.09), col.lightened(0.2))

func _draw_weed(base: Vector2, s: float, t: float, seed: float) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var f: float = float(i) / 7.0
		pts.append(base + Vector2(sin(t * 0.9 + seed + f * 2.2) * s * 0.12 * f, -s * f))
	draw_polyline(pts, Color("3fae6b"), 5.0, true)

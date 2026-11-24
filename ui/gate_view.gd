class_name GateView
extends Control
## The Reef Gate: an arch beside the board. Highlights when a releasable creature
## (tier 4+) is selected or dragged, and counts the residents already inside.

signal tapped

var residents: int = 0:
	set(v):
		residents = v
		queue_redraw()
## 0 = idle, 1 = a tier 4+ creature is selected (glow), 2 = a drag is hovering it.
var state: int = 0:
	set(v):
		state = v
		queue_redraw()
var hint: bool = false:
	set(v):
		hint = v
		queue_redraw()
var reduced_motion: bool = false
var _t: float = 0.0
var _press: Vector2 = Vector2.ZERO
var _flash: float = 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func pulse() -> void:
	_flash = 1.0
	queue_redraw()

func _process(delta: float) -> void:
	var animate: bool = (state > 0 or hint or _flash > 0.0) and not reduced_motion
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.0)
		queue_redraw()
	if animate:
		_t += delta
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press = mb.position
		elif _press.distance_to(mb.position) < GameConfig.DRAG_THRESHOLD * 1.5:
			tapped.emit()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var glow: float = 0.0
	if state == 1:
		glow = 0.55 + (0.0 if reduced_motion else 0.25 * sin(_t * 5.0))
	elif state == 2:
		glow = 1.0
	elif hint:
		glow = 0.5 + (0.0 if reduced_motion else 0.3 * sin(_t * 4.0))
	glow = maxf(glow, _flash)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Pal.PANEL_DARK
	sb.set_corner_radius_all(16)
	sb.corner_radius_top_left = int(w * 0.5)
	sb.corner_radius_top_right = int(w * 0.5)
	sb.border_color = Pal.TEAL if glow > 0.0 else Pal.TEXT_DIM.darkened(0.3)
	sb.set_border_width_all(3 if glow > 0.0 else 2)
	sb.anti_aliasing = true
	if glow > 0.0:
		var og := StyleBoxFlat.new()
		og.bg_color = Color(0, 0, 0, 0)
		og.border_color = Color(Pal.TEAL, 0.35 * glow)
		og.set_border_width_all(6)
		og.set_corner_radius_all(18)
		og.corner_radius_top_left = int(w * 0.5) + 3
		og.corner_radius_top_right = int(w * 0.5) + 3
		og.anti_aliasing = true
		draw_style_box(og, Rect2(Vector2(-3, -3), size + Vector2(6, 6)))
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	# water inside the arch
	var inner := Rect2(Vector2(8, 8), size - Vector2(16, 16))
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color("1d8fb8").lerp(Color("5eead4"), glow * 0.6)
	isb.set_corner_radius_all(10)
	isb.corner_radius_top_left = int(inner.size.x * 0.5)
	isb.corner_radius_top_right = int(inner.size.x * 0.5)
	isb.anti_aliasing = true
	draw_style_box(isb, inner)
	# ripples
	for k in 4:
		var y: float = h * (0.32 + 0.14 * float(k))
		var pts := PackedVector2Array()
		for i in 9:
			var f: float = float(i) / 8.0
			pts.append(Vector2(lerpf(14.0, w - 14.0, f), y + sin(f * TAU * 1.5 + _t * 2.0 + float(k)) * 3.0))
		draw_polyline(pts, Color(1, 1, 1, 0.22), 2.0, true)
	var font: Font = ThemeDB.fallback_font
	var tc: Color = Pal.TEXT
	draw_string(font, Vector2(0, h * 0.13), "REEF", HORIZONTAL_ALIGNMENT_CENTER, w, 17, tc)
	draw_string(font, Vector2(0, h * 0.13 + 19), "GATE", HORIZONTAL_ALIGNMENT_CENTER, w, 17, tc)
	var tier_txt := "tier %d+" % GameConfig.RELEASE_MIN_TIER
	draw_string(font, Vector2(0, h * 0.62), tier_txt, HORIZONTAL_ALIGNMENT_CENTER, w, 16, Pal.GOLD)
	draw_string(font, Vector2(0, h * 0.62 + 20), "drop or", HORIZONTAL_ALIGNMENT_CENTER, w, 14, Pal.TEXT_DIM)
	draw_string(font, Vector2(0, h * 0.62 + 36), "tap here", HORIZONTAL_ALIGNMENT_CENTER, w, 14, Pal.TEXT_DIM)
	# residents counter
	var cy: float = h - 34.0
	draw_circle(Vector2(w * 0.5, cy + 6.0), 17.0, Pal.INK)
	draw_string(font, Vector2(0, cy + 13.0), str(residents), HORIZONTAL_ALIGNMENT_CENTER, w, 22, Pal.GOLD)
	draw_string(font, Vector2(0, h - 4.0), "in reef", HORIZONTAL_ALIGNMENT_CENTER, w, 13, Pal.TEXT_DIM)

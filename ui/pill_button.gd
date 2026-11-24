class_name PillButton
extends Control
## Touch-sized rounded button with a drawn icon. Works with mouse and with
## touch (touch is emulated to mouse by the engine, see project settings).

signal pressed

var text: String = "":
	set(v):
		text = v
		queue_redraw()
var icon: String = "":
	set(v):
		icon = v
		queue_redraw()
var accent: Color = Pal.CURRENT:
	set(v):
		accent = v
		queue_redraw()
## Primary actions are solid (accent fill, dark text); secondary ones are outlined.
var filled: bool = false:
	set(v):
		filled = v
		queue_redraw()
var enabled: bool = true:
	set(v):
		enabled = v
		queue_redraw()
var toggled: bool = false:
	set(v):
		toggled = v
		queue_redraw()
var font_size: int = 20
var _down: bool = false
var _hover: bool = false
var _sb: StyleBoxFlat = StyleBoxFlat.new()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sb.set_corner_radius_all(14)
	_sb.anti_aliasing = true

func _ready() -> void:
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		_down = false
		queue_redraw())

func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_down = true
			queue_redraw()
			accept_event()
		else:
			var was_down: bool = _down
			_down = false
			queue_redraw()
			if was_down and Rect2(Vector2.ZERO, size).has_point(mb.position):
				pressed.emit()
			accept_event()

func _draw() -> void:
	var col: Color = accent
	if not enabled:
		col = Color(0.35, 0.45, 0.52)
	var fill: Color = col.darkened(0.55)
	if toggled:
		fill = col.darkened(0.15)
	if filled and enabled:
		fill = col
	if _down:
		fill = fill.lightened(0.15)
	elif _hover and enabled:
		fill = fill.lightened(0.06)
	_sb.bg_color = fill
	_sb.border_color = col
	_sb.set_border_width_all(2)
	draw_style_box(_sb, Rect2(Vector2.ZERO, size))
	var tc: Color = Pal.TEXT if enabled else Color(0.6, 0.7, 0.75)
	if filled and enabled:
		tc = Pal.INK
	var font: Font = ThemeDB.fallback_font
	var icon_size: float = minf(size.y * 0.5, 26.0)
	var fs: int = fitted_font_size()
	var icon_w: float = 0.0
	if icon != "":
		icon_w = icon_size + (8.0 if text != "" else 0.0)
	var text_w: float = 0.0
	if text != "":
		text_w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var total: float = icon_w + text_w
	var x: float = (size.x - total) * 0.5
	if icon != "":
		draw_icon(self, icon, Vector2(x + icon_size * 0.5, size.y * 0.5), icon_size, tc)
	if text != "":
		draw_string(font, Vector2(x + icon_w, size.y * 0.5 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)

## Largest font size (down to 12) at which icon + text fit inside the button.
func fitted_font_size() -> int:
	var font: Font = ThemeDB.fallback_font
	var icon_size: float = minf(size.y * 0.5, 26.0)
	var icon_w: float = 0.0
	if icon != "":
		icon_w = icon_size + (8.0 if text != "" else 0.0)
	var fs: int = font_size
	while fs > 12 and text != "" and icon_w + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 14.0:
		fs -= 1
	return fs

func content_fits() -> bool:
	var font: Font = ThemeDB.fallback_font
	var icon_size: float = minf(size.y * 0.5, 26.0)
	var icon_w: float = (icon_size + (8.0 if text != "" else 0.0)) if icon != "" else 0.0
	var w: float = icon_w + (font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted_font_size()).x if text != "" else 0.0)
	return w <= size.x - 8.0

## Shared simple icon set, drawn with polygons so no glyph fonts are needed.
static func draw_icon(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var h: float = s * 0.5
	match kind:
		"left":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h, 0), c + Vector2(h * 0.7, -h), c + Vector2(h * 0.7, h)]), col)
		"right":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(h, 0), c + Vector2(-h * 0.7, -h), c + Vector2(-h * 0.7, h)]), col)
		"up":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(-h, h * 0.7), c + Vector2(h, h * 0.7)]), col)
		"down":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, h), c + Vector2(-h, -h * 0.7), c + Vector2(h, -h * 0.7)]), col)
		"wave":
			var pts := PackedVector2Array()
			for i in 13:
				var t: float = float(i) / 12.0
				pts.append(c + Vector2(lerpf(-h, h, t), sin(t * TAU * 1.25) * h * 0.45))
			ci.draw_polyline(pts, col, maxf(2.0, s * 0.14), true)
			var pts2 := PackedVector2Array()
			for i in 13:
				var t2: float = float(i) / 12.0
				pts2.append(c + Vector2(lerpf(-h, h, t2), h * 0.55 + sin(t2 * TAU * 1.25) * h * 0.3))
			ci.draw_polyline(pts2, col, maxf(2.0, s * 0.14), true)
		"check":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-h, 0), c + Vector2(-h * 0.25, h * 0.7), c + Vector2(h, -h * 0.7)]), col, maxf(2.5, s * 0.18), true)
		"x":
			ci.draw_line(c + Vector2(-h, -h) * 0.8, c + Vector2(h, h) * 0.8, col, maxf(2.5, s * 0.16), true)
			ci.draw_line(c + Vector2(-h, h) * 0.8, c + Vector2(h, -h) * 0.8, col, maxf(2.5, s * 0.16), true)
		"home":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(-h, 0)]), col)
			ci.draw_rect(Rect2(c + Vector2(-h * 0.7, 0), Vector2(h * 1.4, h)), col)
		"reef":
			# little coral fan
			for k in 5:
				var a: float = -PI * 0.5 + (float(k) - 2.0) * 0.42
				ci.draw_line(c + Vector2(0, h * 0.8), c + Vector2(cos(a), sin(a)) * h * 1.05 + Vector2(0, h * 0.1), col, maxf(2.0, s * 0.14), true)
		"motion":
			ci.draw_arc(c, h * 0.8, 0.3, 2.6, 12, col, maxf(2.0, s * 0.12), true)
			ci.draw_arc(c, h * 0.8, 3.45, 5.75, 12, col, maxf(2.0, s * 0.12), true)
		"motion_off":
			ci.draw_arc(c, h * 0.8, 0.3, 2.6, 12, col, maxf(2.0, s * 0.12), true)
			ci.draw_arc(c, h * 0.8, 3.45, 5.75, 12, col, maxf(2.0, s * 0.12), true)
			ci.draw_line(c + Vector2(-h, h), c + Vector2(h, -h), col, maxf(2.5, s * 0.14), true)
		"sound":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h, -h * 0.35), c + Vector2(-h * 0.35, -h * 0.35), c + Vector2(h * 0.2, -h * 0.9), c + Vector2(h * 0.2, h * 0.9), c + Vector2(-h * 0.35, h * 0.35), c + Vector2(-h, h * 0.35)]), col)
			ci.draw_arc(c + Vector2(h * 0.2, 0), h * 0.7, -0.9, 0.9, 8, col, maxf(2.0, s * 0.12), true)
		"sound_off":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h, -h * 0.35), c + Vector2(-h * 0.35, -h * 0.35), c + Vector2(h * 0.2, -h * 0.9), c + Vector2(h * 0.2, h * 0.9), c + Vector2(-h * 0.35, h * 0.35), c + Vector2(-h, h * 0.35)]), col)
			ci.draw_line(c + Vector2(-h, h), c + Vector2(h, -h), col, maxf(2.5, s * 0.14), true)
		"coin":
			ci.draw_circle(c, h, Pal.GOLD)
			ci.draw_circle(c, h * 0.68, Pal.GOLD.darkened(0.2))
			ci.draw_circle(c, h * 0.5, Pal.GOLD)
		"pearl":
			ci.draw_circle(c, h + 1.5, Color("5b86a8"))
			ci.draw_circle(c, h, Color("e8f4ff"))
			ci.draw_circle(c + Vector2(-h * 0.25, -h * 0.25), h * 0.35, Color(1, 1, 1, 0.95))
			ci.draw_arc(c, h, 0.2, 2.9, 12, Color("9cc7ff"), maxf(1.5, s * 0.1), true)
		"tide":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-h, -h * 0.4), c + Vector2(0, h * 0.5), c + Vector2(h, -h * 0.4)]), col, maxf(2.5, s * 0.16), true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-h, h * 0.1), c + Vector2(0, h), c + Vector2(h, h * 0.1)]), col, maxf(2.5, s * 0.16), true)
		_:
			pass

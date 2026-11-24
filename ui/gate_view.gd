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
var _sb: StyleBoxFlat = StyleBoxFlat.new()
var _isb: StyleBoxFlat = StyleBoxFlat.new()
var _ogb: StyleBoxFlat = StyleBoxFlat.new()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sb.anti_aliasing = true
	_isb.anti_aliasing = true
	_ogb.anti_aliasing = true
	_ogb.bg_color = Color(0, 0, 0, 0)

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
	var st: int = ItemArt.STATE_SELECTED if glow > 0.0 else ItemArt.STATE_AVAILABLE
	var animate: bool = glow > 0.0 and not reduced_motion
	ItemArt.draw_reef_gate(self, Rect2(Vector2.ZERO, size), st, _t, residents, {"animate": animate})
	var font: Font = ThemeDB.fallback_font
	# labels sit inside the portal; a dark outline keeps them readable over the bright water
	_label(font, "REEF", Vector2(0, h * 0.20), w, 17, Pal.TEXT)
	_label(font, "GATE", Vector2(0, h * 0.20 + 19), w, 17, Pal.TEXT)
	_label(font, "tier %d+" % GameConfig.RELEASE_MIN_TIER, Vector2(0, h * 0.58), w, 16, Pal.GOLD)
	_label(font, "drop or", Vector2(0, h * 0.58 + 20), w, 14, Pal.TEXT)
	_label(font, "tap here", Vector2(0, h * 0.58 + 36), w, 14, Pal.TEXT)
	# residents counter in the clear space at the foot of the arch
	var cy: float = h - 40.0
	draw_circle(Vector2(w * 0.5, cy + 6.0), 17.0, Pal.INK)
	draw_arc(Vector2(w * 0.5, cy + 6.0), 17.0, 0.0, TAU, 20, Pal.GOLD, 2.0, true)
	draw_string(font, Vector2(0, cy + 13.0), str(residents), HORIZONTAL_ALIGNMENT_CENTER, w, 22, Pal.GOLD)
	_label(font, "in reef", Vector2(0, h - 10.0), w, 13, Pal.TEXT_DIM)

func _label(font: Font, text: String, pos: Vector2, width: float, fs: int, col: Color) -> void:
	for off in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
		draw_string(font, pos + off, text, HORIZONTAL_ALIGNMENT_CENTER, width, fs, Color(Pal.INK, 0.85))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, fs, col)

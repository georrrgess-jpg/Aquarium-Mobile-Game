class_name Backdrop
extends Control
## The tidepool behind every screen. Static scenery (rocks, sand, kelp, caustics) is drawn on one
## layer that redraws only when the tide or the layout changes; a light animated layer (drifting
## kelp, shimmer) sits on top at a low frame rate and rests when hidden or with reduced motion.
## The area behind the puzzle grid and the HUD band stays quiet so text and tiles stay readable.

var palette: Dictionary = BgArt.palette(Tide.MIDDAY):
	set(v):
		palette = v
		_static.invalidate()
		_anim.queue_redraw()
var grid_rect: Rect2 = Rect2(10, 184, 422, 488):
	set(v):
		if v != grid_rect:
			grid_rect = v
			_static.invalidate()
			_anim.queue_redraw()
var reduced_motion: bool = false:
	set(v):
		if v != reduced_motion:
			reduced_motion = v
			_anim.queue_redraw()
var animate_enabled: bool = true         # the owner turns this off while a non-pool screen covers it
var _static: BakedLayer
var _anim: Layer
var _t: float = 0.0
var _since: float = 0.0

class Layer extends Control:
	var owner_bd: Control
	var mode: int = 0
	func _init(o: Control, m: int) -> void:
		owner_bd = o
		mode = m
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		owner_bd.call("_draw_layer", self, mode)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_static = BakedLayer.new()
	_static.painter = func(ci: Control) -> void: _draw_layer(ci, 0)
	_anim = Layer.new(self, 1)
	add_child(_static)
	add_child(_anim)
	resized.connect(func() -> void:
		_static.size = size
		_anim.size = size
		_static.invalidate()
		_anim.queue_redraw())

func _process(delta: float) -> void:
	if reduced_motion or not animate_enabled or not is_visible_in_tree():
		return
	_t += delta
	_since += delta
	if _since >= 1.0 / 12.0:
		_since = 0.0
		_anim.queue_redraw()

func _draw_layer(layer: Control, mode: int) -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	var rect := Rect2(Vector2.ZERO, size)
	if mode == 0:
		BgArt.draw_pool_backdrop_static(layer, rect, grid_rect, palette)
	else:
		BgArt.draw_pool_backdrop_anim(layer, rect, grid_rect, palette, _t, not reduced_motion)

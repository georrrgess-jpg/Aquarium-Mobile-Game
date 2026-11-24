class_name BakedLayer
extends Control
## A static drawing rendered once into a texture. Software and mobile GPUs pay for every polygon of
## every layered scene on every frame, so scenery that changes rarely (backdrop, reef terrain) is
## painted into a SubViewport and shown as a single textured quad. `invalidate()` re-renders it
## once, on the next frame the layer is visible; nothing is drawn while it stays valid.
##
## `painter` is called as painter.call(canvas_item) and draws in this layer's own coordinates.

var painter: Callable
var bake_count: int = 0                  # for tests and the profiler: how many times it was re-rendered
var _vp: SubViewport
var _canvas: Canvas
var _tex: TextureRect
var _dirty: bool = true

class Canvas extends Control:
	var layer: BakedLayer
	func _init(l: BakedLayer) -> void:
		layer = l
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if layer.painter.is_valid():
			layer.painter.call(self)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.gui_disable_input = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_canvas = Canvas.new(self)
	_vp.add_child(_canvas)
	_tex = TextureRect.new()
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.texture = _vp.get_texture()
	add_child(_tex)
	resized.connect(invalidate)

func invalidate() -> void:
	_dirty = true

func _process(_delta: float) -> void:
	if _dirty and size.x >= 4.0 and size.y >= 4.0 and is_visible_in_tree():
		_rebake()

## Texture pixels per logical pixel: match the window so the bake is crisp but never oversized.
func _px_scale() -> float:
	var win: Window = get_window()
	if win == null:
		return 1.0
	var vis: float = get_viewport().get_visible_rect().size.x
	if vis <= 1.0:
		return 1.0
	return clampf(float(win.size.x) / vis, 0.6, 2.0)

func _rebake() -> void:
	_dirty = false
	bake_count += 1
	var k: float = _px_scale()
	_vp.size = Vector2i(ceili(size.x * k), ceili(size.y * k))
	_canvas.size = size
	_canvas.scale = Vector2(k, k)
	_canvas.queue_redraw()
	_tex.size = size
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

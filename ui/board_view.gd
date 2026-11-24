class_name BoardView
extends Control
## Draws the 6x7 pool, handles pointer input (mouse, and touch via the engine's
## touch->mouse emulation) and replays resolved action events as animation.
##
## It never mutates game state: it reports intent through signals and the
## PoolScreen asks the GameSession to resolve it.

signal drop_requested(src: int, dst: int)
signal release_requested(src: int)
signal selection_changed(cell: int)
signal line_picked(axis: int, index: int)
signal line_dragged(axis: int, index: int, dir: int)
signal reward_popped(global_pos: Vector2, coins: int, pearls: int, step: int, tier: int)
signal refund_earned
signal chain_cue(step: int, global_pos: Vector2)

const TAB: float = 26.0

var session: GameSession
var sfx: Sfx
var gate: GateView
var cs: float = 66.0:
	set(v):
		cs = v
		_relayout()
var interactive: bool = true:
	set(v):
		interactive = v
		if not v:
			cancel_gesture()
var mode_current: bool = false:
	set(v):
		mode_current = v
		_pressing = false
		_dragging = false
		_over.queue_redraw()
		_under.queue_redraw()
var reduced_motion: bool = false
var anim_speed: float = 1.0

var selected: int = -1
var hint_cells: PackedInt32Array = PackedInt32Array()
## {axis, index, dir} - dir 0 means "line chosen, direction not chosen yet".
var line_preview: Dictionary = {}
var hint_line: Dictionary = {}
## Tutorial / Hint guidance: {cells: [..], from: cell, to: cell, to_gate: bool, label: String, style: "coach"|"hint"}.
## Drawn as ringed cells, a dashed arrow with a travelling dot and a short label that is placed
## so it never covers the cells the player has to use.
var guide: Dictionary = {}
## Where the guide label was drawn last (empty when none fits); tests check it clears the targets.
var guide_label_rect: Rect2 = Rect2()
var surge_preview: Array = []
var flood_flash: bool = false

var _under: Layer
var _creatures: Control
var _over: Layer
var _fx: Control
var _nodes: Dictionary = {}
var _t: float = 0.0
var _since_redraw: float = 0.0
var _pressing: bool = false
var _dragging: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _press_cell: int = -1
var _press_selected_before: int = -1
var _press_is_target: bool = false
var _line_drag_cell: int = -1
var _last_drag_dir: int = 0
var _drag_pos: Vector2 = Vector2.ZERO
var _shake: Dictionary = {}
var _bursts: Array = []
var _links: Array = []          # chain links: a line from the previous merge to the next, drawn briefly
var _chain_prev: int = -1
var _tile: StyleBoxFlat = StyleBoxFlat.new()
var _ring: StyleBoxFlat = StyleBoxFlat.new()

# --- Inner helper classes ---------------------------------------------------------

class Layer extends Control:
	var board: Control
	var mode: int = 0
	func _init(b: Control, m: int) -> void:
		board = b
		mode = m
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		board.call("_draw_layer", self, mode)

class CreatureView extends Control:
	var code: int = 0
	var phase: float = 0.0
	func _init(c: int, s: float) -> void:
		code = c
		size = Vector2(s, s)
		pivot_offset = Vector2(s, s) * 0.5
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_code(c: int) -> void:
		code = c
		queue_redraw()
	func _draw() -> void:
		CreatureArt.draw_creature(self, code, size * 0.5, size.x, {"phase": phase})

# --- Setup -------------------------------------------------------------------------

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_tile.set_corner_radius_all(10)
	_tile.anti_aliasing = true
	_ring.bg_color = Color(0, 0, 0, 0)
	_ring.set_corner_radius_all(10)
	_ring.anti_aliasing = true
	_base = BakedLayer.new()
	_base.painter = func(ci: Control) -> void: _paint_base(ci)
	_under = Layer.new(self, 0)
	_creatures = Control.new()
	_creatures.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_creatures.clip_contents = true
	_over = Layer.new(self, 1)
	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_base)
	add_child(_under)
	add_child(_creatures)
	add_child(_over)
	add_child(_fx)

func _ready() -> void:
	_relayout()

func board_pixel_size() -> Vector2:
	return Vector2(TAB + cs * GameConfig.COLS, TAB + cs * GameConfig.ROWS)

func _relayout() -> void:
	if _under == null:
		return
	var bs: Vector2 = board_pixel_size()
	custom_minimum_size = bs
	size = bs
	for l in [_base, _under, _over, _fx]:
		var c: Control = l
		c.position = Vector2.ZERO
		c.size = bs
	_creatures.position = Vector2(TAB, TAB)
	_creatures.size = Vector2(cs * GameConfig.COLS, cs * GameConfig.ROWS)
	for k in _nodes:
		var n: CreatureView = _nodes[k]
		n.size = Vector2(cs, cs)
		n.pivot_offset = Vector2(cs, cs) * 0.5
		n.position = _cell_pos(int(k))
	_base.invalidate()
	_under.queue_redraw()
	_over.queue_redraw()

## Top-left of a cell relative to the creature layer.
func _cell_pos(i: int) -> Vector2:
	return Vector2(Board.col_of(i), Board.row_of(i)) * cs

## Cell rectangle relative to this control.
var palette: Dictionary = BgArt.palette(Tide.MIDDAY):
	set(v):
		palette = v
		if _base != null:
			_base.invalidate()
		if _under != null:
			_under.queue_redraw()
var _base: BakedLayer              # frame + tiles: rendered to a texture, redone only when the tile occupancy changes
var _base_mask: String = ""

func cell_rect(i: int) -> Rect2:
	return Rect2(Vector2(TAB, TAB) + _cell_pos(i), Vector2(cs, cs))

func cell_center_global(i: int) -> Vector2:
	return get_global_transform() * cell_rect(i).get_center()

func cell_at(p: Vector2) -> int:
	var q: Vector2 = (p - Vector2(TAB, TAB)) / cs
	if q.x < 0.0 or q.y < 0.0 or q.x >= GameConfig.COLS or q.y >= GameConfig.ROWS:
		return -1
	return Board.idx(int(q.y), int(q.x))

func _tab_at(p: Vector2) -> Dictionary:
	if p.x < TAB and p.y >= TAB and p.y < TAB + cs * GameConfig.ROWS:
		return {"axis": Board.AXIS_ROW, "index": int((p.y - TAB) / cs)}
	if p.y < TAB and p.x >= TAB and p.x < TAB + cs * GameConfig.COLS:
		return {"axis": Board.AXIS_COL, "index": int((p.x - TAB) / cs)}
	return {}

# --- State ---------------------------------------------------------------------------

## Drop any half-finished pointer gesture: stops a drag, clears press state and restores
## the dimmed source piece. Called when input is locked, the pointer leaves the window,
## focus is lost, the view is hidden, or the player cancels (Esc / right click).
func cancel_gesture() -> void:
	var was_dragging: bool = _dragging
	_pressing = false
	_dragging = false
	_press_cell = -1
	_press_is_target = false
	_line_drag_cell = -1
	_restore_drag_node()
	if was_dragging:
		_update_gate_state(false)
		_over.queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_gesture()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		cancel_gesture()

func select(cell: int) -> void:
	selected = cell
	if cell >= 0:
		Haptics.tick()
		if sfx != null:
			sfx.play("select")
	_update_gate_state()
	selection_changed.emit(cell)
	_over.queue_redraw()

func clear_selection() -> void:
	_dragging = false
	_pressing = false
	if selected != -1:
		selected = -1
		selection_changed.emit(-1)
	_restore_drag_node()
	_update_gate_state()
	_over.queue_redraw()

func _restore_drag_node() -> void:
	for k in _nodes:
		var n: CreatureView = _nodes[k]
		if is_instance_valid(n):
			n.modulate.a = 1.0

func _update_gate_state(hover: bool = false) -> void:
	if gate == null:
		return
	if selected >= 0 and session != null and session.run != null:
		var t: Dictionary = session.valid_targets(selected)
		gate.state = (2 if hover else 1) if bool(t["gate"]) else 0
	else:
		gate.state = 0

func _targets() -> Dictionary:
	if selected >= 0 and session != null and session.run != null and not mode_current:
		return session.valid_targets(selected)
	return {"merge": PackedInt32Array(), "move": PackedInt32Array(), "gate": false}

func _is_target(cell: int) -> bool:
	var t: Dictionary = _targets()
	return t["merge"].has(cell) or t["move"].has(cell)

# --- Sync ----------------------------------------------------------------------------

## Make the displayed creatures match `board` exactly (authoritative).
func sync(board: Board) -> void:
	for i in board.cells.size():
		var code: int = board.code_at(i)
		if code == 0:
			_drop_node(i)
			continue
		if _nodes.has(i):
			var n: CreatureView = _nodes[i]
			if n.code != code:
				n.set_code(code)
			n.position = _cell_pos(i)
			n.scale = Vector2.ONE
			n.rotation = 0.0
			n.modulate = Color.WHITE
		else:
			_spawn(i, code)
	var mask: String = ""
	for k in board.cells.size():
		mask += "1" if board.code_at(k) != 0 else "0"
	if mask != _base_mask:
		_base_mask = mask
		_base.invalidate()
	_under.queue_redraw()
	_over.queue_redraw()

func _spawn(cell: int, code: int, at: Vector2 = Vector2(-1, -1)) -> CreatureView:
	var n := CreatureView.new(code, cs)
	n.phase = float(cell) * 0.7
	_creatures.add_child(n)
	n.position = _cell_pos(cell) if at.x < 0.0 else at
	_nodes[cell] = n
	return n

func _drop_node(cell: int) -> void:
	if _nodes.has(cell):
		var n: CreatureView = _nodes[cell]
		_nodes.erase(cell)
		if is_instance_valid(n):
			n.queue_free()

func _ensure(cell: int, code: int) -> CreatureView:
	if not _nodes.has(cell):
		_spawn(cell, code)
	return _nodes[cell]

# --- Input ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		cancel_gesture()
		clear_selection()
		accept_event()
		return
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_on_press(mb.position)
		else:
			_on_release(mb.position)
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _pressing:
		_on_motion(mm.position)
		accept_event()

func _on_press(pos: Vector2) -> void:
	if session == null or session.run == null:
		return
	_pressing = true
	_dragging = false
	_press_pos = pos
	_press_cell = cell_at(pos)
	_press_selected_before = selected
	_press_is_target = false
	_line_drag_cell = -1
	_last_drag_dir = 0
	var tab: Dictionary = _tab_at(pos)
	if not tab.is_empty():
		# tapping a tab starts a Current even when Current mode is off
		line_picked.emit(int(tab["axis"]), int(tab["index"]))
		_pressing = false
		return
	if mode_current:
		_line_drag_cell = _press_cell
		return
	if _press_cell < 0:
		return
	if selected >= 0 and _press_cell != selected and (_is_target(_press_cell) or session.run.board.code_at(_press_cell) == 0):
		_press_is_target = true
		return
	if session.run.board.code_at(_press_cell) != 0 and _press_cell != selected:
		select(_press_cell)

func _on_motion(pos: Vector2) -> void:
	var dist: float = pos.distance_to(_press_pos)
	if mode_current:
		if _line_drag_cell >= 0 and dist > GameConfig.DRAG_THRESHOLD:
			var d: Vector2 = pos - _press_pos
			var axis: int = Board.AXIS_ROW if absf(d.x) >= absf(d.y) else Board.AXIS_COL
			var dir: int = (1 if d.x > 0.0 else -1) if axis == Board.AXIS_ROW else (1 if d.y > 0.0 else -1)
			var index: int = Board.row_of(_line_drag_cell) if axis == Board.AXIS_ROW else Board.col_of(_line_drag_cell)
			var key: int = axis * 100 + (dir + 1) * 10 + index
			if key != _last_drag_dir:
				_last_drag_dir = key
				line_dragged.emit(axis, index, dir)
		return
	if not _dragging and selected >= 0 and _press_cell == selected and dist > GameConfig.DRAG_THRESHOLD:
		_dragging = true
		if _nodes.has(selected):
			(_nodes[selected] as CreatureView).modulate.a = 0.3
	if _dragging:
		_drag_pos = pos
		var hover: bool = _over_gate(pos)
		_update_gate_state(hover)
		_over.queue_redraw()

func _over_gate(local_pos: Vector2) -> bool:
	if gate == null:
		return false
	return gate.get_global_rect().has_point(get_global_transform() * local_pos)

func _on_release(pos: Vector2) -> void:
	if not _pressing:
		return
	_pressing = false
	if mode_current:
		return
	if _dragging:
		_dragging = false
		_restore_drag_node()
		var src: int = selected
		var to_gate: bool = _over_gate(pos)
		var dst: int = cell_at(pos)
		_update_gate_state(false)
		_over.queue_redraw()
		if to_gate:
			release_requested.emit(src)
		elif dst >= 0 and dst != src:
			drop_requested.emit(src, dst)
		return
	# a tap
	var c: int = _press_cell
	if c < 0 or session == null or session.run == null:
		return
	if selected >= 0:
		if c == selected:
			if _press_selected_before == selected:
				clear_selection()
		elif _press_is_target:
			drop_requested.emit(selected, c)

func _process(delta: float) -> void:
	if not _links.is_empty():
		for l in _links:
			l["age"] = float(l["age"]) + delta
		_links = _links.filter(func(l: Dictionary) -> bool: return float(l["age"]) < 0.75)
		_over.queue_redraw()
	var animating: bool = not reduced_motion and (selected >= 0 or not surge_preview.is_empty() or not hint_cells.is_empty() or not guide.is_empty() or not line_preview.is_empty() or not hint_line.is_empty() or flood_flash or not _bursts.is_empty())
	if animating:
		_t += delta
		for b in _bursts:
			b["age"] = float(b["age"]) + delta
		_bursts = _bursts.filter(func(b: Dictionary) -> bool: return float(b["age"]) < 0.45)
		_since_redraw += delta
		if _since_redraw >= 1.0 / 30.0:      # pulses are gentle; 30 fps redraw is plenty
			_since_redraw = 0.0
			_over.queue_redraw()
	elif not _bursts.is_empty():
		_bursts.clear()

# --- Drawing -------------------------------------------------------------------------

func _draw_layer(layer: Control, mode: int) -> void:
	if session == null or session.run == null:
		return
	if mode == 0:
		_draw_under(layer)
	else:
		_draw_over(layer)

func _draw_under(ci: Control) -> void:
	var board: Board = session.run.board
	var font: Font = ThemeDB.fallback_font
	# row and column tabs
	var tab_active: bool = mode_current
	for r in GameConfig.ROWS:
		var rect := Rect2(1, TAB + float(r) * cs + 3, TAB - 4, cs - 6)
		_draw_tab(ci, rect, tab_active, (line_preview.get("axis", -1) == Board.AXIS_ROW and line_preview.get("index", -1) == r) or (line_preview.is_empty() and hint_line.get("axis", -1) == Board.AXIS_ROW and hint_line.get("index", -1) == r), true)
	for c in GameConfig.COLS:
		var rect2 := Rect2(TAB + float(c) * cs + 3, 1, cs - 6, TAB - 4)
		_draw_tab(ci, rect2, tab_active, (line_preview.get("axis", -1) == Board.AXIS_COL and line_preview.get("index", -1) == c) or (line_preview.is_empty() and hint_line.get("axis", -1) == Board.AXIS_COL and hint_line.get("index", -1) == c), false)
	if flood_flash:
		for i in board.cells.size():
			if board.code_at(i) == 0:
				var rr := Pal.RED
				rr.a = 0.35 + (0.0 if reduced_motion else 0.2 * sin(_t * 8.0))
				_tile.bg_color = rr
				ci.draw_style_box(_tile, cell_rect(i).grow(-2.0))
	# tutorial line hint tint
	if not hint_line.is_empty() and line_preview.is_empty():
		_tint_line(ci, int(hint_line["axis"]), int(hint_line["index"]), Pal.GOLD, 0.16 + (0.0 if reduced_motion else 0.08 * sin(_t * 4.0)))
	if not line_preview.is_empty():
		_tint_line(ci, int(line_preview["axis"]), int(line_preview["index"]), Pal.CURRENT, 0.22)

## The board's frame and tiles, painted into the baked layer (static scenery for the grid).
func _paint_base(ci: Control) -> void:
	if session == null or session.run == null:
		return
	var board: Board = session.run.board
	BgArt.draw_board_frame(ci, Rect2(Vector2(TAB, TAB), Vector2(cs * GameConfig.COLS, cs * GameConfig.ROWS)), palette)
	for i in board.cells.size():
		BgArt.draw_tile(ci, cell_rect(i).grow(-2.0), (Board.row_of(i) + Board.col_of(i)) % 2, board.code_at(i) != 0, palette)

func _draw_tab(ci: Control, rect: Rect2, active: bool, chosen: bool, horizontal: bool) -> void:
	var col: Color = Pal.CURRENT if (active or chosen) else Pal.TEXT_DIM.darkened(0.45)
	var fill: Color = col
	fill.a = 0.55 if chosen else (0.28 if active else 0.12)
	_tile.bg_color = fill
	_tile.set_corner_radius_all(6)
	_tile.set_border_width_all(0)
	ci.draw_style_box(_tile, rect)
	_tile.set_corner_radius_all(10)
	var c: Color = col
	c.a = 0.95 if active else 0.45
	var m: Vector2 = rect.get_center()
	var s: float = 5.5
	if horizontal:
		# row tab: a small double arrow  < >  pointing along the row
		ci.draw_colored_polygon(PackedVector2Array([m + Vector2(-s * 1.7, 0), m + Vector2(-s * 0.4, -s), m + Vector2(-s * 0.4, s)]), c)
		ci.draw_colored_polygon(PackedVector2Array([m + Vector2(s * 1.7, 0), m + Vector2(s * 0.4, -s), m + Vector2(s * 0.4, s)]), c)
	else:
		ci.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -s * 1.7), m + Vector2(-s, -s * 0.4), m + Vector2(s, -s * 0.4)]), c)
		ci.draw_colored_polygon(PackedVector2Array([m + Vector2(0, s * 1.7), m + Vector2(-s, s * 0.4), m + Vector2(s, s * 0.4)]), c)

func _tint_line(ci: Control, axis: int, index: int, col: Color, alpha: float) -> void:
	var cells: PackedInt32Array = Board.line_cells(axis, index)
	var first: Rect2 = cell_rect(cells[0])
	var last: Rect2 = cell_rect(cells[cells.size() - 1])
	var rect: Rect2 = first.merge(last).grow(-1.0)
	var f: Color = col
	f.a = alpha
	_tile.bg_color = f
	_tile.border_color = col
	_tile.set_border_width_all(3)
	ci.draw_style_box(_tile, rect)
	_tile.set_border_width_all(0)

func _ring_cell(ci: Control, cell: int, col: Color, width: int, grow: float = -1.0) -> void:
	_ring.border_color = col
	_ring.set_border_width_all(width)
	ci.draw_style_box(_ring, cell_rect(cell).grow(grow))

func _brackets(ci: Control, r: Rect2, col: Color, width: float, arm: float) -> void:
	# four corner brackets: a shape cue for "this piece is selected"
	var pts: Array = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var dirs: Array = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for i in 4:
		var c: Vector2 = pts[i]
		var d: Vector2 = dirs[i]
		ci.draw_line(c, c + Vector2(d.x * arm, 0), col, width)
		ci.draw_line(c, c + Vector2(0, d.y * arm), col, width)

func _dashed(ci: Control, r: Rect2, col: Color, width: float) -> void:
	var dash: float = 9.0
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

func _draw_over(ci: Control) -> void:
	var board: Board = session.run.board
	var pulse: float = 0.0 if reduced_motion else 0.5 + 0.5 * sin(_t * 5.0)
	# legal targets: merge = solid ring + diamond mark, slide = dotted circle + arrow dot
	if selected >= 0 and not mode_current:
		var t: Dictionary = _targets()
		for i in t["merge"]:
			var rc0: Rect2 = cell_rect(int(i))
			var c: Color = Pal.TARGET
			c.a = 0.28
			_tile.bg_color = c
			_tile.set_border_width_all(0)
			ci.draw_style_box(_tile, rc0.grow(-2.0))
			_ring_cell(ci, int(i), Pal.TARGET, 4)
			var m: Vector2 = rc0.position + Vector2(rc0.size.x - 13.0, 13.0)
			ci.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -9), m + Vector2(9, 0), m + Vector2(0, 9), m + Vector2(-9, 0)]), Pal.INK)
			ci.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -6.5), m + Vector2(6.5, 0), m + Vector2(0, 6.5), m + Vector2(-6.5, 0)]), Pal.TARGET)
		for i in t["move"]:
			var rc: Rect2 = cell_rect(int(i))
			var dc: Color = Pal.TARGET
			dc.a = 0.30
			ci.draw_circle(rc.get_center(), cs * 0.22, dc)
			dc.a = 1.0
			var steps: int = 10
			for k in steps:
				var a0: float = TAU * float(k) / float(steps)
				ci.draw_arc(rc.get_center(), cs * 0.22, a0, a0 + TAU / float(steps) * 0.55, 5, dc, 3.0, true)
		var sc: Color = Pal.GOLD
		sc.a = 0.8 + 0.2 * pulse
		_ring_cell(ci, selected, sc, 4, 0.0)
		_brackets(ci, cell_rect(selected).grow(3.0), Pal.INK, 7.0, 14.0)
		_brackets(ci, cell_rect(selected).grow(3.0), Pal.GOLD, 4.0, 14.0)
	if not guide.is_empty():
		_draw_guide(ci, pulse)
	# tutorial hint rings
	for h in hint_cells:
		var hc: Color = Pal.GOLD
		hc.a = 0.5 + 0.4 * pulse
		_ring_cell(ci, int(h), hc, 4, 0.0)
	# Current preview
	if not line_preview.is_empty() and int(line_preview.get("dir", 0)) != 0:
		_draw_line_preview(ci, board)
	# Surge preview: dashed outline + down-arrow tab + ghost creature (shapes as well as colour)
	for p in surge_preview:
		var cell: int = int(p["cell"])
		var rc2: Rect2 = cell_rect(cell)
		var f: Color = Pal.SURGE
		f.a = 0.22 + 0.12 * pulse
		_tile.bg_color = f
		_tile.set_border_width_all(0)
		ci.draw_style_box(_tile, rc2.grow(-2.0))
		CreatureArt.draw_creature(ci, int(p["code"]), rc2.get_center(), cs, {"alpha": 0.78, "glow": false})
		var rcol: Color = Pal.SURGE
		rcol.a = 0.75 + 0.25 * pulse
		_dashed(ci, rc2.grow(-3.0), rcol, 4.0)
		var m2: Vector2 = rc2.position + Vector2(13.0, 12.0)
		ci.draw_colored_polygon(PackedVector2Array([m2 + Vector2(-9, -7), m2 + Vector2(9, -7), m2 + Vector2(0, 8)]), Pal.INK)
		ci.draw_colored_polygon(PackedVector2Array([m2 + Vector2(-6.5, -5), m2 + Vector2(6.5, -5), m2 + Vector2(0, 5.5)]), rcol)
	# drag ghost follows the pointer
	if _dragging and selected >= 0 and session.run.board.code_at(selected) != 0:
		CreatureArt.draw_creature(ci, session.run.board.code_at(selected), _drag_pos, cs * 1.15, {"alpha": 0.92})
	# bursts
	for l in _links:
		var la: float = float(l["age"]) / 0.75
		var lc: Color = l["color"]
		lc.a = 0.9 * (1.0 - la * la)
		var pa: Vector2 = l["a"]
		var pb: Vector2 = l["b"]
		var reach: Vector2 = pa.lerp(pb, minf(1.0, la * 4.0))         # the link travels from one merge to the next
		ci.draw_line(pa, reach, Color(Pal.INK, 0.55 * lc.a), 7.0, true)
		ci.draw_line(pa, reach, lc, 4.0, true)
		for e in [pa, pb]:
			ci.draw_arc(e, cs * (0.34 + 0.12 * la), 0.0, TAU, 24, lc, 3.0, true)
	for b in _bursts:
		var a: float = float(b["age"]) / 0.45
		var bc: Color = b["color"]
		bc.a = 0.8 * (1.0 - a)
		var center: Vector2 = b["pos"]
		ci.draw_arc(center, cs * (0.3 + 0.55 * a), 0.0, TAU, 28, bc, 4.0 * (1.0 - a) + 1.0, true)
		for k in 6:
			var ang: float = float(k) * TAU / 6.0 + 0.3
			ci.draw_circle(center + Vector2(cos(ang), sin(ang)) * cs * (0.25 + 0.6 * a), 3.0 * (1.0 - a) + 1.0, bc)

func _guide_cells() -> PackedInt32Array:
	var out := PackedInt32Array()
	for c in guide.get("cells", []):
		out.append(int(c))
	return out

func _draw_guide(ci: Control, pulse: float) -> void:
	var style: String = String(guide.get("style", "coach"))
	var col: Color = Pal.GOLD if style == "coach" else Pal.CORAL
	var cells: PackedInt32Array = _guide_cells()
	for c in cells:
		var rc: Color = col
		rc.a = 0.6 + 0.4 * pulse
		_ring_cell(ci, c, Color(Pal.INK, 0.9), 7, 0.0)
		_ring_cell(ci, c, rc, 4, 0.0)
	var from_c: int = int(guide.get("from", -1))
	var to_c: int = int(guide.get("to", -1))
	var a: Vector2 = Vector2.ZERO
	var b: Vector2 = Vector2.ZERO
	var has_arrow: bool = false
	if from_c >= 0 and to_c >= 0 and from_c != to_c:
		a = cell_rect(from_c).get_center()
		b = cell_rect(to_c).get_center()
		has_arrow = true
	elif from_c >= 0 and bool(guide.get("to_gate", false)):
		a = cell_rect(from_c).get_center()
		b = Vector2(TAB + cs * GameConfig.COLS + 8.0, a.y)
		has_arrow = true
	if has_arrow:
		var dir: Vector2 = (b - a).normalized()
		var p0: Vector2 = a + dir * cs * 0.55
		var p1: Vector2 = b - dir * cs * 0.55
		if p0.distance_to(p1) > 6.0 or bool(guide.get("to_gate", false)):
			var len: float = p0.distance_to(p1)
			var d: float = 0.0
			while d < len:
				ci.draw_line(p0 + dir * d, p0 + dir * minf(d + 8.0, len), Color(Pal.INK, 0.85), 6.0)
				ci.draw_line(p0 + dir * d, p0 + dir * minf(d + 8.0, len), col, 3.0)
				d += 16.0
			var perp: Vector2 = Vector2(-dir.y, dir.x)
			var tip: Vector2 = p1
			var tri := PackedVector2Array([tip, tip - dir * 14.0 + perp * 8.0, tip - dir * 14.0 - perp * 8.0])
			ci.draw_colored_polygon(tri, Pal.INK)
			var tri2 := PackedVector2Array([tip - dir * 2.0, tip - dir * 13.0 + perp * 6.0, tip - dir * 13.0 - perp * 6.0])
			ci.draw_colored_polygon(tri2, col)
			# a travelling dot shows which way to drag
			var phase: float = 0.5 if reduced_motion else fposmod(_t * 0.8, 1.0)
			var dot: Vector2 = p0.lerp(p1, phase)
			ci.draw_circle(dot, 8.0, Color(Pal.INK, 0.9))
			ci.draw_circle(dot, 5.5, Color(1, 1, 1, 0.95))
	var label: String = String(guide.get("label", ""))
	if label != "" and not cells.is_empty():
		_draw_guide_label(ci, label, cells, col)

func _draw_guide_label(ci: Control, label: String, cells: PackedInt32Array, col: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	var fs: int = 17
	var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 22.0
	var h: float = 30.0
	var bounds := Rect2(Vector2(TAB, TAB), Vector2(cs * GameConfig.COLS, cs * GameConfig.ROWS))
	var avoid: Array = []
	for c in cells:
		avoid.append(cell_rect(c).grow(2.0))
	var anchor: Rect2 = cell_rect(cells[0])
	# candidate positions around the first target: above, below, right, left (then the others' sides)
	var cands: Array = [
		Vector2(anchor.get_center().x - w * 0.5, anchor.position.y - h - 5.0),
		Vector2(anchor.get_center().x - w * 0.5, anchor.end.y + 5.0),
		Vector2(anchor.end.x + 5.0, anchor.get_center().y - h * 0.5),
		Vector2(anchor.position.x - w - 5.0, anchor.get_center().y - h * 0.5),
	]
	for c2 in cells:                                   # also try around the other targets
		var ar: Rect2 = cell_rect(c2)
		cands.append(Vector2(ar.get_center().x - w * 0.5, ar.position.y - h - 5.0))
		cands.append(Vector2(ar.get_center().x - w * 0.5, ar.end.y + 5.0))
	var chosen: Rect2 = Rect2(cands[0], Vector2(w, h))
	guide_label_rect = Rect2()
	var found: bool = false
	for c in cands:
		var r := Rect2(Vector2(clampf(c.x, bounds.position.x, bounds.end.x - w), clampf(c.y, bounds.position.y, bounds.end.y - h)), Vector2(w, h))
		var clash: bool = false
		for a in avoid:
			if r.intersects(a):
				clash = true
		if not clash:
			chosen = r
			found = true
			break
	if not found:
		return                                  # never cover a target: skip the label instead
	guide_label_rect = chosen
	_tile.bg_color = Pal.INK
	_tile.border_color = col
	_tile.set_border_width_all(2)
	ci.draw_style_box(_tile, chosen)
	_tile.set_border_width_all(0)
	ci.draw_string(font, chosen.position + Vector2(0, h * 0.5 + fs * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Pal.TEXT)

func _draw_line_preview(ci: Control, board: Board) -> void:
	var axis: int = int(line_preview["axis"])
	var index: int = int(line_preview["index"])
	var dir: int = int(line_preview["dir"])
	var cells: PackedInt32Array = Board.line_cells(axis, index)
	var dvec: Vector2 = Vector2(dir, 0) if axis == Board.AXIS_ROW else Vector2(0, dir)
	var phase: float = 0.0 if reduced_motion else fposmod(_t * 1.2, 1.0)
	var col: Color = Pal.CURRENT.lightened(0.3)
	# moving chevrons
	for i in cells:
		var rc: Rect2 = cell_rect(i)
		var cen: Vector2 = rc.get_center() + dvec * cs * (phase - 0.5) * 0.9
		var perp: Vector2 = Vector2(-dvec.y, dvec.x)
		var s: float = cs * 0.13
		var c2: Color = col
		c2.a = 0.85 * (1.0 - absf(phase - 0.5) * 1.2)
		ci.draw_colored_polygon(PackedVector2Array([cen + dvec * s * 1.4, cen - dvec * s + perp * s * 1.2, cen - dvec * s - perp * s * 1.2]), c2)
	# where the shift sets up an immediate merge (from the real Current rules): bracket every
	# piece that will merge and mark the result cell
	var info: Dictionary = line_preview.get("info", {})
	for st in info.get("steps", []):
		for sc in st["sources"]:
			_brackets(ci, cell_rect(int(sc)).grow(1.0), Pal.INK, 7.0, 13.0)
			_brackets(ci, cell_rect(int(sc)).grow(1.0), Pal.GOLD, 4.0, 13.0)
		var rcell: Rect2 = cell_rect(int(st["result_cell"]))
		ci.draw_circle(rcell.get_center(), cs * 0.13, Pal.INK)
		ci.draw_circle(rcell.get_center(), cs * 0.09, Pal.GOLD)
	# ghosts at the destination and wrap markers
	for i in cells:
		var code: int = board.code_at(i)
		if code == 0:
			continue
		var dest: int = Board.shifted_destination(i, axis, dir)
		var drc: Rect2 = cell_rect(dest)
		CreatureArt.draw_creature(ci, code, drc.get_center(), cs * 0.92, {"alpha": 0.5, "badge": true, "glow": false})
		_ring_cell(ci, dest, Color(Pal.CURRENT.lightened(0.4), 0.9), 2, -4.0)
		if Board.shift_wraps(i, axis, dir):
			# arrow leaving the board edge from the source, entering at the opposite edge
			var src_c: Vector2 = cell_rect(i).get_center()
			var out_pos: Vector2 = src_c + dvec * cs * 0.62
			var in_pos: Vector2 = drc.get_center() - dvec * cs * 0.62
			var wc: Color = Pal.GOLD
			var perp2: Vector2 = Vector2(-dvec.y, dvec.x)
			var sz: float = cs * 0.15
			ci.draw_colored_polygon(PackedVector2Array([out_pos + dvec * sz, out_pos - dvec * sz * 0.4 + perp2 * sz, out_pos - dvec * sz * 0.4 - perp2 * sz]), wc)
			ci.draw_colored_polygon(PackedVector2Array([in_pos + dvec * sz, in_pos - dvec * sz * 0.4 + perp2 * sz, in_pos - dvec * sz * 0.4 - perp2 * sz]), wc)

# --- Animation -----------------------------------------------------------------------

func _wait(sec: float) -> void:
	await get_tree().create_timer(maxf(0.001, sec / anim_speed), true, false, true).timeout

func _dur(sec: float) -> float:
	var d: float = sec / anim_speed
	return maxf(0.001, d * (0.35 if reduced_motion else 1.0))

func _slide(node: Control, to: Vector2, sec: float) -> void:
	var tw: Tween = create_tween()
	tw.tween_property(node, "position", to, _dur(sec)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished

func _pop(node: Control) -> void:
	if not is_instance_valid(node):
		return
	if reduced_motion:
		node.modulate = Color(1.7, 1.7, 1.7)
		var tw0: Tween = create_tween()
		tw0.tween_property(node, "modulate", Color.WHITE, 0.25 / anim_speed)
		return
	node.scale = Vector2(1.45, 0.62)
	node.modulate = Color(1.9, 1.9, 1.6)                      # evolution: a bright flash that settles back
	var tw0: Tween = create_tween()
	tw0.tween_property(node, "modulate", Color.WHITE, _dur(0.28))
	var tw: Tween = create_tween()
	tw.tween_property(node, "scale", Vector2.ONE, _dur(GameConfig.T_POP + 0.12)).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## A chain: draw a link from the merge before this one to the cells that took part in this one.
func _chain_link(result_cell: int, participants: Array, step: int) -> void:
	if step >= 1 and _chain_prev >= 0 and _chain_prev != result_cell:
		_links.append({"a": cell_rect(_chain_prev).get_center(), "b": cell_rect(result_cell).get_center(), "age": 0.0, "color": Pal.GOLD})
	for p in participants:
		if int(p) != result_cell and step >= 1:
			_links.append({"a": cell_rect(int(p)).get_center(), "b": cell_rect(result_cell).get_center(), "age": 0.0, "color": Pal.CURRENT})
	_chain_prev = result_cell
	if not _links.is_empty():
		_over.queue_redraw()

func _burst(cell: int, col: Color) -> void:
	if reduced_motion:
		return
	_bursts.append({"pos": cell_rect(cell).get_center(), "age": 0.0, "color": col})

func float_text(cell: int, text: String, col: Color, size_px: int = 22) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size_px)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Pal.INK)
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(lbl)
	var start: Vector2 = cell_rect(cell).get_center() - Vector2(lbl.get_minimum_size().x * 0.5, 16.0)
	lbl.position = start
	var tw: Tween = create_tween()
	if reduced_motion:
		tw.tween_interval(0.5 / anim_speed)
		tw.tween_property(lbl, "modulate:a", 0.0, 0.25 / anim_speed)
	else:
		tw.set_parallel(true)
		tw.tween_property(lbl, "position:y", start.y - 38.0, 0.8 / anim_speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(lbl, "modulate:a", 0.0, 0.8 / anim_speed).set_delay(0.35 / anim_speed)
	tw.chain().tween_callback(lbl.queue_free)

func shake(cell: int) -> void:
	Haptics.reject()
	if sfx != null:
		sfx.play("reject")
	if not _nodes.has(cell):
		return
	var n: CreatureView = _nodes[cell]
	var home: Vector2 = _cell_pos(cell)
	if reduced_motion:
		n.modulate = Color(1.0, 0.55, 0.55)
		var tw0: Tween = create_tween()
		tw0.tween_property(n, "modulate", Color.WHITE, 0.4)
		return
	var tw: Tween = create_tween()
	tw.tween_property(n, "position:x", home.x + 7.0, 0.04)
	tw.tween_property(n, "position:x", home.x - 7.0, 0.07)
	tw.tween_property(n, "position:x", home.x + 4.0, 0.06)
	tw.tween_property(n, "position:x", home.x, 0.05)

## Replay the events of one resolved action, then snap to the authoritative board.
func play_events(events: Array, final_board: Board) -> void:
	_chain_prev = -1
	for ev in events:
		match String(ev["t"]):
			"move":
				await _ev_move(ev)
			"pair":
				await _ev_pair(ev)
			"shift":
				await _ev_shift(ev)
			"merge":
				await _ev_merge(ev)
			"release":
				await _ev_release(ev)
			"refund":
				refund_earned.emit()
	sync(final_board)

func _ev_move(ev: Dictionary) -> void:
	var from: int = int(ev["from"])
	var to: int = int(ev["to"])
	if not _nodes.has(from):
		return
	var n: CreatureView = _nodes[from]
	_nodes.erase(from)
	_nodes[to] = n
	_creatures.move_child(n, -1)
	await _slide(n, _cell_pos(to), GameConfig.T_SLIDE)

func _emit_reward(ev: Dictionary) -> void:
	var cell: int = int(ev["result_cell"])
	reward_popped.emit(cell_center_global(cell), int(ev.get("coins", 0)), int(ev.get("pearls", 0)), int(ev.get("step", 0)), int(ev.get("tier", 0)))
	if int(ev.get("step", 0)) >= 1:
		chain_cue.emit(int(ev["step"]), cell_center_global(cell))
	Haptics.merge(int(ev.get("step", 0)))
	if sfx != null:
		sfx.pop(int(ev.get("step", 0)))
	_burst(cell, Pal.tier_color(int(ev.get("tier", 1))))
	float_text(cell, "+%d" % int(ev.get("coins", 0)), Pal.GOLD)

## Contact: the pieces meet and hold for a beat before the new creature appears.
func _contact(cell: int) -> void:
	if reduced_motion:
		return
	_bursts.append({"pos": cell_rect(cell).get_center(), "age": 0.3, "color": Color(1, 1, 1)})   # short, white: no evolution colour yet
	await _wait(0.04)

func _ev_pair(ev: Dictionary) -> void:
	var from: int = int(ev["from"])
	var to: int = int(ev["to"])
	var code: int = int(ev["code"])
	var src: CreatureView = _nodes.get(from) as CreatureView
	var dst: CreatureView = _ensure(to, code - 1)
	_nodes.erase(from)
	if src != null:
		_creatures.move_child(src, -1)
		await _slide(src, _cell_pos(to), GameConfig.T_SLIDE)
		src.queue_free()
		await _contact(to)
	_chain_link(to, [from], int(ev.get("step", 0)))
	dst.set_code(code)
	_pop(dst)
	_emit_reward(ev)
	await _wait(GameConfig.T_CHAIN_GAP)

func _ev_merge(ev: Dictionary) -> void:
	var result_cell: int = int(ev["result_cell"])
	var code: int = int(ev["code"])
	var sources: PackedInt32Array = ev["sources"]
	var moving: Array = []
	for s in sources:
		if int(s) == result_cell:
			continue
		if _nodes.has(int(s)):
			moving.append(_nodes[int(s)])
			_nodes.erase(int(s))
	var tw: Tween = create_tween().set_parallel(true)
	for n in moving:
		_creatures.move_child(n, -1)
		tw.tween_property(n, "position", _cell_pos(result_cell), _dur(GameConfig.T_SLIDE)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if not moving.is_empty():
		await tw.finished
	else:
		tw.kill()
	for n in moving:
		(n as Control).queue_free()
	if not moving.is_empty():
		await _contact(result_cell)
	var parts: Array = []
	for s2 in sources:
		parts.append(int(s2))
	_chain_link(result_cell, parts, int(ev.get("step", 0)))
	var res_node: CreatureView = _ensure(result_cell, code)
	res_node.set_code(code)
	_pop(res_node)
	_emit_reward(ev)
	await _wait(GameConfig.T_CHAIN_GAP)

func _ev_shift(ev: Dictionary) -> void:
	var axis: int = int(ev["axis"])
	var index: int = int(ev["index"])
	var dir: int = int(ev["dir"])
	if sfx != null:
		sfx.play("shift")
	var cells: PackedInt32Array = Board.line_cells(axis, index)
	var dvec: Vector2 = Vector2(dir, 0) if axis == Board.AXIS_ROW else Vector2(0, dir)
	var movers: Array = []
	for c in cells:
		if _nodes.has(int(c)):
			movers.append({"node": _nodes[int(c)], "from": int(c), "to": Board.shifted_destination(int(c), axis, dir), "wrap": Board.shift_wraps(int(c), axis, dir)})
	for m in movers:
		_nodes.erase(int(m["from"]))
	var tw: Tween = create_tween().set_parallel(true)
	var leaving: Array = []
	for m in movers:
		var n: CreatureView = m["node"]
		var dest: Vector2 = _cell_pos(int(m["to"]))
		if bool(m["wrap"]):
			var exit_pos: Vector2 = _cell_pos(int(m["from"])) + dvec * cs
			var enter_pos: Vector2 = dest - dvec * cs
			var clone: CreatureView = _spawn(int(m["to"]), n.code, enter_pos)
			tw.tween_property(n, "position", exit_pos, _dur(GameConfig.T_SLIDE * 1.4)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(clone, "position", dest, _dur(GameConfig.T_SLIDE * 1.4)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			leaving.append(n)
		else:
			_nodes[int(m["to"])] = n
			tw.tween_property(n, "position", dest, _dur(GameConfig.T_SLIDE * 1.4)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if movers.is_empty():
		tw.kill()
		await _wait(GameConfig.T_SLIDE)
	else:
		await tw.finished
	for n in leaving:
		(n as Control).queue_free()
	await _wait(0.05)

func _ev_release(ev: Dictionary) -> void:
	var cell: int = int(ev["cell"])
	var code: int = int(ev["code"])
	_drop_node(cell)
	Haptics.release()
	if sfx != null:
		sfx.play("release")
	# fly a copy through the gate (outside the clipped creature layer)
	var g_center: Vector2 = cell_rect(cell).get_center()
	if gate != null:
		g_center = get_global_transform().affine_inverse() * (gate.get_global_rect().get_center())
	var fly := CreatureView.new(code, cs)
	_fx.add_child(fly)
	fly.position = cell_rect(cell).position
	var target: Vector2 = g_center - Vector2(cs, cs) * 0.5
	var tw: Tween = create_tween().set_parallel(true)
	if reduced_motion:
		tw.tween_property(fly, "modulate:a", 0.0, 0.35 / anim_speed)
	else:
		tw.tween_property(fly, "position", target, _dur(0.5)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(fly, "scale", Vector2(0.35, 0.35), _dur(0.5)).set_ease(Tween.EASE_IN)
		tw.tween_property(fly, "modulate:a", 0.2, _dur(0.5)).set_delay(_dur(0.25))
	await tw.finished
	fly.queue_free()
	if gate != null:
		gate.pulse()

func play_land(events: Array) -> void:
	if sfx != null:
		sfx.play("land")
	var made: Array = []
	for ev in events:
		var cell: int = int(ev["cell"])
		var n: CreatureView = _ensure(cell, int(ev["code"]))
		n.set_code(int(ev["code"]))
		made.append(n)
		if reduced_motion:
			n.modulate.a = 0.0
		else:
			n.scale = Vector2(0.2, 0.2)
			n.modulate.a = 0.0
	var tw: Tween = create_tween().set_parallel(true)
	for n in made:
		if reduced_motion:
			tw.tween_property(n, "modulate:a", 1.0, 0.3 / anim_speed)
		else:
			tw.tween_property(n, "scale", Vector2.ONE, _dur(0.35)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(n, "modulate:a", 1.0, _dur(0.15))
	await tw.finished
	for ev in events:
		_burst(int(ev["cell"]), Pal.SURGE)

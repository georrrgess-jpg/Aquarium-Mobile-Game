class_name BookView
extends Control
## The Tidepool Book page: every species, one tile per tier, plus a pinned detail card.
## Everything is drawn in one _draw; it redraws only on refresh / select / scroll / resize.
## Scrolls vertically (touch-drag or mouse wheel); a drag longer than TAP_SLOP is never a tap.
## Tile states come from Book.state_of: resident / found / next (silhouette) / hidden ("?").

const PAD := 10.0                 # side gutter (the selected-tile brackets reach ~8px out)
const GAP := 8.0
const TILE_MIN := 44.0
const TILE_MAX := 58.0
const TAP_SLOP := 10.0
const FS_TITLE := 17
const FS_HEAD := 15
const FS_BODY := 13
const DETAIL_MAX_FRAC := 0.55     # the pinned card never takes more than this share of the height
const SIL := Color("0b2a33")
const TOAST_TEXT := "Keep merging to find this one"

var selected_code: int = 0

var _session: GameSession = null
var _profile: Profile = null
var _user_picked: bool = false
var _scroll: float = 0.0
var _content_h: float = 0.0
var _view_h: float = 0.0          # height of the scrolling area (control height minus the card)
var _tile: float = TILE_MIN
var _cols: int = 6
var _counts: Dictionary = {"found": 0, "total": 13, "residents": 0}
var _sections: Array = []         # {name, tag, count_text, y, tiles: [{code, state, rect}]}
var _head_h: float = 0.0
var _empty_lines: PackedStringArray = PackedStringArray()
var _detail_h: float = 0.0
var _detail: Dictionary = {}
var _toast_until_msec: int = 0
var _press: Vector2 = Vector2.ZERO
var _pressed: bool = false
var _dragging: bool = false

func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

# ---------------------------------------------------------------- public API
func setup(s: GameSession) -> void:
	_session = s
	_user_picked = false
	_scroll = 0.0
	refresh()
	if _view_h < 160.0 and selected_code > 0:     # cramped: open on the selected tile, not the header
		_reveal(selected_code)
		queue_redraw()

func refresh() -> void:
	_profile = _session.profile if _session != null else null
	if _profile != null:
		if not _user_picked or not _selectable(selected_code):
			if _user_picked:
				_user_picked = false
			selected_code = _default_code()
	else:
		selected_code = 0
	_relayout()
	queue_redraw()

## Programmatic selection (hidden / unknown codes are ignored).
func select(code: int) -> void:
	if _profile == null or not _selectable(code):
		return
	selected_code = code
	_user_picked = true
	_relayout()
	_reveal(code)
	queue_redraw()

## Tile rects (code -> Rect2 in this control's coordinates, scroll applied) for tiles inside the visible area.
func tile_rects() -> Dictionary:
	var out: Dictionary = {}
	var view := Rect2(0.0, 0.0, size.x, _view_h)
	for sec in _sections:
		for t in sec["tiles"]:
			var r: Rect2 = Rect2(t["rect"])
			r.position.y -= _scroll
			if r.intersects(view):
				out[int(t["code"])] = r
	return out

func detail_rect() -> Rect2:
	return Rect2(0.0, size.y - _detail_h, size.x, _detail_h)

func content_height() -> float:
	return _content_h

## Tap at a point in this control's coordinates (used by input and by tests).
func tap(pos: Vector2) -> void:
	if _profile == null or pos.y >= _view_h:
		return
	var p: Vector2 = pos + Vector2(0.0, _scroll)
	for sec in _sections:
		for t in sec["tiles"]:
			if Rect2(t["rect"]).grow(GAP * 0.5).has_point(p):
				var code: int = int(t["code"])
				if String(t["state"]) == "hidden":
					_show_toast()
				else:
					select(code)
				return

# ---------------------------------------------------------------- state
func _state(code: int) -> String:
	return Book.state_of(_profile, Creature.family_of(code), Creature.tier_of(code))

func _selectable(code: int) -> bool:
	if _profile == null or code <= 0:
		return false
	for sp in Book.species():
		if int(sp["family"]) == Creature.family_of(code) and (sp["tiers"] as Array).has(Creature.tier_of(code)):
			return _state(code) != "hidden"
	return false

## Highest-tier resident, else highest-tier found creature, else nothing.
func _default_code() -> int:
	var best_res: int = 0
	var best_found: int = 0
	for sp in Book.species():
		for t in sp["tiers"]:
			var code: int = Creature.make(int(sp["family"]), int(t))
			var st: String = _state(code)
			if st == "resident" and (best_res == 0 or int(t) >= Creature.tier_of(best_res)):
				best_res = code
			elif st == "found" and (best_found == 0 or int(t) >= Creature.tier_of(best_found)):
				best_found = code
	return best_res if best_res != 0 else best_found

func _show_toast() -> void:
	_toast_until_msec = Time.get_ticks_msec() + 2200
	queue_redraw()
	if is_inside_tree():
		get_tree().create_timer(2.3).timeout.connect(queue_redraw)

# ---------------------------------------------------------------- text helpers
func _font() -> Font:
	return ThemeDB.fallback_font

func _tw(s: String, fs: int) -> float:
	return _font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x

func _lh(fs: int) -> float:
	return ceilf(_font().get_height(fs)) + 1.0

func _elide(s: String, width: float, fs: int) -> String:
	if _tw(s, fs) <= width:
		return s
	var n: int = s.length()
	while n > 1 and _tw(s.substr(0, n) + "…", fs) > width:
		n -= 1
	return s.substr(0, n).strip_edges() + "…"

## Greedy word wrap. max_lines > 0 truncates with an ellipsis on the last line.
func _wrap(s: String, width: float, fs: int, max_lines: int = 0) -> PackedStringArray:
	var lines := PackedStringArray()
	var cur: String = ""
	for w in s.split(" ", false):
		var trial: String = w if cur == "" else cur + " " + w
		if _tw(trial, fs) <= width or cur == "":
			cur = trial
			# a single word wider than the box: hard-break it
			while _tw(cur, fs) > width and cur.length() > 1:
				var n: int = cur.length() - 1
				while n > 1 and _tw(cur.substr(0, n), fs) > width:
					n -= 1
				lines.append(cur.substr(0, n))
				cur = cur.substr(n)
		else:
			lines.append(cur)
			cur = w
	if cur != "":
		lines.append(cur)
	if max_lines > 0 and lines.size() > max_lines:
		var joined: String = " ".join(lines.slice(max_lines - 1))
		lines = lines.slice(0, max_lines - 1)
		lines.append(_elide(joined, width, fs))
	return lines

func _text(s: String, x: float, top: float, fs: int, col: Color, width: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f: Font = _font()
	var str_out: String = s if width < 0.0 else _elide(s, width, fs)
	draw_string(f, Vector2(x, top + f.get_ascent(fs)), str_out, align, width, fs, col)

func _lines(arr: PackedStringArray, x: float, top: float, fs: int, col: Color) -> float:
	var y: float = top
	for l in arr:
		_text(l, x, y, fs, col)
		y += _lh(fs)
	return y

# ---------------------------------------------------------------- layout
func _relayout() -> void:
	_sections.clear()
	_empty_lines = PackedStringArray()
	if _profile == null or size.x <= 0.0 or size.y <= 0.0:
		_content_h = 0.0
		_detail_h = 0.0
		_view_h = size.y
		return
	_counts = Book.counts(_profile)
	var avail: float = maxf(size.x - 2.0 * PAD, TILE_MIN)
	_cols = clampi(int(floor((avail + GAP) / (TILE_MIN + GAP))), 1, 6)
	_tile = clampf((avail - GAP * float(_cols - 1)) / float(_cols), TILE_MIN, TILE_MAX)
	var y: float = PAD
	y += _lh(FS_TITLE) + 2.0
	y += _lh(FS_BODY) + 8.0
	if int(_counts["found"]) == 0:
		_empty_lines = _wrap("Nothing found yet. Merge two matching creatures and your first page fills in.", size.x - 2.0 * PAD, FS_BODY)
		y += float(_empty_lines.size()) * _lh(FS_BODY) + 8.0
	_head_h = y
	for sp in Book.species():
		var fam: int = int(sp["family"])
		var tiers: Array = sp["tiers"]
		var found: int = 0
		var tiles: Array = []
		var row_y: float = y + _lh(FS_HEAD) + 8.0
		for i in tiers.size():
			var code: int = Creature.make(fam, int(tiers[i]))
			var st: String = _state(code)
			if st == "found" or st == "resident":
				found += 1
			var col: int = i % _cols
			var row: int = i / _cols
			tiles.append({"code": code, "state": st, "rect": Rect2(PAD + float(col) * (_tile + GAP), row_y + float(row) * (_tile + GAP), _tile, _tile)})
		var rows: int = int(ceil(float(tiers.size()) / float(_cols)))
		_sections.append({"name": String(sp["name"]), "tag": "visitor" if fam == Creature.RAY else "",
			"count": "%d of %d" % [found, tiers.size()], "y": y, "tiles": tiles})
		y = row_y + float(rows) * (_tile + GAP) + 4.0
	_content_h = y + PAD - GAP
	_layout_detail()
	_view_h = size.y - _detail_h
	_scroll = clampf(_scroll, 0.0, _max_scroll())

func _max_scroll() -> float:
	return maxf(0.0, _content_h - _view_h)

func _art_box() -> float:
	return clampf(size.x * 0.17, 46.0, 64.0)

## Works out what the detail card says and how tall it is (capped; the note is trimmed to fit).
func _layout_detail() -> void:
	_detail = {}
	var W: float = size.x
	var cap: float = floorf(size.y * DETAIL_MAX_FRAC)
	if selected_code <= 0:
		var msg: String = "Tiles marked ? are still hidden. Keep merging to fill the Book." if int(_counts["found"]) == 0 else "Tap a creature to read about it."
		var ml: PackedStringArray = _wrap(msg, W - 2.0 * PAD, FS_BODY)
		_detail = {"empty": true, "lines": ml}
		_detail_h = minf(float(ml.size()) * _lh(FS_BODY) + 2.0 * PAD, cap)
		return
	var code: int = selected_code
	var st: String = _state(code)
	var tier: int = Creature.tier_of(code)
	var art: float = _art_box()
	var frame: float = art + 8.0
	var tx: float = PAD + frame + 10.0
	var wide: bool = W >= 330.0
	var name_s: String = Book.tier_name(code) if st != "next" else "???"
	var status: String = "Resident in your reef"
	var body: String = Book.note(code)
	if st == "found":
		status = "Found, not yet released — release a tier 4+ through the Reef Gate"
	elif st == "next":
		status = "Not found yet"
		body = "Merge two %s to reach it" % Book.tier_name(code - 1)
	var name_lines: PackedStringArray = _wrap(name_s, W - tx - PAD, FS_HEAD, 2)
	var top_h: float = float(name_lines.size()) * _lh(FS_HEAD) + _lh(FS_BODY)   # name + "Tier N"
	var col_w: float = W - tx - PAD
	var body_w: float = col_w if wide else W - 2.0 * PAD
	var status_lines: PackedStringArray = _wrap(status, col_w, FS_BODY)
	var body_lines_full: PackedStringArray = _wrap(body, body_w, FS_BODY)
	var fixed: float = 2.0 * 8.0
	var body_n: int = body_lines_full.size()
	var h: float = 0.0
	var side_h: float = top_h + 2.0 + float(status_lines.size()) * _lh(FS_BODY)    # name + tier + status column
	while true:
		var bh: float = float(body_n) * _lh(FS_BODY)
		if wide:
			h = fixed + maxf(frame, side_h + (4.0 + bh if body_n > 0 else 0.0))
		else:
			h = fixed + maxf(frame, side_h) + (4.0 + bh if body_n > 0 else 0.0)
		if h <= cap or body_n <= mini(2, body_lines_full.size()):
			break
		body_n -= 1
	var body_lines: PackedStringArray = _wrap(body, body_w, FS_BODY, body_n) if body_n > 0 else PackedStringArray()
	_detail = {"empty": false, "code": code, "state": st, "tier": tier, "art": art, "frame": frame, "tx": tx, "wide": wide,
		"name": name_lines, "status": status_lines, "body": body_lines, "top_h": top_h}
	_detail_h = minf(h, floorf(size.y * 0.7))

func _reveal(code: int) -> void:
	for sec in _sections:
		for t in sec["tiles"]:
			if int(t["code"]) == code:
				var r: Rect2 = t["rect"]
				if r.position.y - 10.0 < _scroll:
					_scroll = r.position.y - 10.0
				elif r.end.y + 10.0 > _scroll + _view_h:
					_scroll = r.end.y + 10.0 - _view_h
				_scroll = clampf(_scroll, 0.0, _max_scroll())
				return

# ---------------------------------------------------------------- input
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = mb.position
				_pressed = true
				_dragging = false
			elif _pressed:
				_pressed = false
				if not _dragging and _press.distance_to(mb.position) <= TAP_SLOP:
					tap(mb.position)
				_dragging = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_by(-44.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_by(44.0)
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _pressed:
		if not _dragging and _press.distance_to(mm.position) > TAP_SLOP:
			_dragging = true
		if _dragging:
			_scroll_by(-mm.relative.y)

func _scroll_by(dy: float) -> void:
	var n: float = clampf(_scroll + dy, 0.0, _max_scroll())
	if not is_equal_approx(n, _scroll):
		_scroll = n
		queue_redraw()

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if _profile == null:
		return
	var W: float = size.x
	var oy: float = -_scroll
	var view := Rect2(0.0, 0.0, W, _view_h)
	# header
	var y: float = PAD + oy
	_text("Tidepool Book", PAD, y, FS_TITLE, Pal.GOLD, W - 2.0 * PAD)
	y += _lh(FS_TITLE) + 2.0
	_text("%d of %d found · %d in your reef" % [int(_counts["found"]), int(_counts["total"]), int(_counts["residents"])], PAD, y, FS_BODY, Pal.TEXT, W - 2.0 * PAD)
	y += _lh(FS_BODY) + 8.0
	if not _empty_lines.is_empty():
		_lines(_empty_lines, PAD, y, FS_BODY, Pal.TEXT_DIM)
	# species
	for sec in _sections:
		var sy: float = float(sec["y"]) + oy
		var tiles: Array = sec["tiles"]
		if sy + _lh(FS_HEAD) < 0.0 or sy > _view_h:
			var last_r: Rect2 = Rect2((tiles[tiles.size() - 1] as Dictionary)["rect"])
			if last_r.end.y + oy < 0.0 or sy > _view_h:
				continue
		_draw_section_head(sec, sy, W)
		for t in tiles:
			var r: Rect2 = Rect2(t["rect"])
			r.position.y += oy
			if r.intersects(view):
				_draw_tile(int(t["code"]), String(t["state"]), r)
	# scroll indicator
	if _max_scroll() > 0.0:
		var track: float = _view_h - 12.0
		var bar: float = maxf(24.0, track * _view_h / _content_h)
		var by: float = 6.0 + (track - bar) * (_scroll / _max_scroll())
		draw_rect(Rect2(W - 5.0, by, 3.0, bar), Color(Pal.TEXT, 0.55))
	_draw_detail()
	if Time.get_ticks_msec() < _toast_until_msec:
		_draw_toast()

func _draw_section_head(sec: Dictionary, top: float, W: float) -> void:
	var name_s: String = String(sec["name"])
	var count_s: String = String(sec["count"])
	var cw: float = _tw(count_s, FS_BODY)
	var tag: String = String(sec["tag"])
	var left_w: float = W - 2.0 * PAD - cw - 10.0
	var nw: float = _tw(name_s, FS_HEAD)
	_text(name_s, PAD, top, FS_HEAD, Pal.TEXT, left_w)
	if tag != "" and nw + 8.0 < left_w:
		_text("· " + tag, PAD + nw + 6.0, top + 1.0, FS_BODY, Pal.TEAL, left_w - nw - 6.0)
	_text(count_s, W - PAD - cw, top + 1.0, FS_BODY, Pal.TEXT_DIM)
	var ly: float = top + _lh(FS_HEAD) + 2.0
	draw_line(Vector2(PAD, ly), Vector2(W - PAD, ly), Color(Pal.TEXT, 0.18), 1.0)

func _tier_chip(center: Vector2, tier: int, r: float, dim: bool) -> void:
	var tcol: Color = Pal.tier_color(tier)
	if dim:
		tcol = tcol.lerp(Color("6d8791"), 0.55)
	draw_circle(center, r + 1.8, Color(Pal.INK, 0.92))
	draw_circle(center, r, tcol)
	_glyph(str(tier), center, r * 2.0, Pal.INK)

## One short glyph/number centred on a point (digits and "?" sit on a baseline ~0.36 em below centre).
func _glyph(s: String, center: Vector2, width: float, col: Color, fs: int = FS_BODY, outline: bool = false) -> void:
	var pos := Vector2(center.x - width * 0.5, center.y + float(fs) * 0.36)
	if outline:
		draw_string_outline(_font(), pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, fs, 5, Color(SIL, 0.95))
	draw_string(_font(), pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, fs, col)

func _draw_tile(code: int, st: String, r: Rect2) -> void:
	var tier: int = Creature.tier_of(code)
	var sel: bool = code == selected_code
	var frame_state: int = ItemArt.STATE_AVAILABLE
	match st:
		"resident":
			frame_state = ItemArt.STATE_OWNED
		"hidden":
			frame_state = ItemArt.STATE_LOCKED
	if sel:
		frame_state = ItemArt.STATE_SELECTED
	ItemArt.draw_card_frame(self, r, frame_state, {"badge": false})
	var c: Vector2 = r.get_center()
	var s: float = r.size.x
	if st == "resident" or st == "found":
		CreatureArt.draw_creature(self, code, c + Vector2(0.0, s * 0.03), s * 0.74, {"badge": false, "glow": false})
	elif st == "next":
		CreatureArt.draw_body(self, code, c + Vector2(0.0, -s * 0.07), s * 0.62, {"silhouette": SIL})
		_text("next", r.position.x, r.end.y - _lh(FS_BODY) - 1.0, FS_BODY, Pal.INK, s, HORIZONTAL_ALIGNMENT_CENTER)
		var qc: Vector2 = Vector2(r.end.x - 11.0, r.position.y + 11.0)
		draw_circle(qc, 10.3, Color(SIL, 0.95))
		draw_circle(qc, 8.5, Pal.GOLD)
		_glyph("?", qc, 17.0, Pal.INK, 14)
	else:
		_glyph("?", c, s, Color("c9dde3"), 22)
	# tier chip (top-left) on every tile
	_tier_chip(r.position + Vector2(10.5, 10.5), tier, 8.5, st == "hidden")
	if st == "resident":
		ItemArt.draw_check_seal(self, Vector2(r.end.x - 11.0, r.position.y + 11.0), 18.0)

func _draw_detail() -> void:
	var W: float = size.x
	var card := Rect2(0.0, size.y - _detail_h, W, _detail_h)
	draw_rect(card, Color("0a3140"))
	draw_line(card.position, Vector2(W, card.position.y), Color(Pal.GOLD, 0.55), 2.0)
	if bool(_detail.get("empty", false)):
		_lines(_detail["lines"], PAD, card.position.y + PAD, FS_BODY, Pal.TEXT_DIM)
		return
	if _detail.is_empty():
		return
	var code: int = int(_detail["code"])
	var st: String = String(_detail["state"])
	var frame: float = float(_detail["frame"])
	var art: float = float(_detail["art"])
	var tx: float = float(_detail["tx"])
	var top: float = card.position.y + 8.0
	var fr := Rect2(PAD, top, frame, frame)
	var fstate: int = ItemArt.STATE_OWNED if st == "resident" else ItemArt.STATE_AVAILABLE
	ItemArt.draw_card_frame(self, fr, fstate, {"badge": false})
	if st == "next":
		CreatureArt.draw_body(self, code, fr.get_center() + Vector2(0.0, -2.0), art * 0.86, {"silhouette": SIL})
		_glyph("?", fr.get_center() + Vector2(0.0, -2.0), frame, Color("fff6d8"), 24, true)
	else:
		CreatureArt.draw_creature(self, code, fr.get_center() + Vector2(0.0, 2.0), art * 0.9, {"badge": false, "glow": false})
	if st == "resident":
		ItemArt.draw_check_seal(self, Vector2(fr.end.x - 4.0, fr.position.y + 4.0), 18.0)
	# text column
	var y: float = _lines(_detail["name"], tx, top, FS_HEAD, Pal.TEXT)
	_text("Tier %d" % int(_detail["tier"]), tx, y, FS_BODY, Pal.TEXT_DIM, size.x - tx - PAD)
	y += _lh(FS_BODY)
	y += 2.0
	var scol: Color = Color("8fd8b0") if st == "resident" else (Pal.GOLD if st == "found" else Pal.TEXT_DIM)
	y = _lines(_detail["status"], tx, y, FS_BODY, scol)
	var body: PackedStringArray = _detail["body"]
	if not body.is_empty():
		var bx: float = tx
		if not bool(_detail["wide"]):
			bx = PAD
			y = maxf(y, top + frame)
		_lines(body, bx, y + 4.0, FS_BODY, Pal.TEXT)

func _draw_toast() -> void:
	var w: float = minf(_tw(TOAST_TEXT, FS_BODY) + 24.0, size.x - 2.0 * PAD)
	var h: float = _lh(FS_BODY) + 10.0
	var r := Rect2((size.x - w) * 0.5, size.y - _detail_h - h - 8.0, w, h)
	ItemArt.fill_rrect(self, r, h * 0.5, Color("123f50"), Color("0a2b36"), Pal.GOLD, 1.5)
	_text(TOAST_TEXT, r.position.x, r.position.y + 5.0, FS_BODY, Pal.TEXT, w, HORIZONTAL_ALIGNMENT_CENTER)

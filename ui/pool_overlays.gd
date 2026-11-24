class_name PoolOverlays
extends RefCounted
## Small modal pieces used by the pool: the first-resident arrival card, the Help sheet and
## the "stuck? restart the guided board" bar. All layout is by explicit rectangles so text and
## buttons are measured, never allowed to run into each other.

static func card_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.2, 0.26, 1.0)
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(20)
	sb.anti_aliasing = true
	return sb

## Greedy word wrap into at most `max_lines`; returns the lines (last one ellipsised if cut).
static func wrap(font: Font, text: String, width: float, fs: int, max_lines: int = 99) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for para in text.split("\n"):
		var line: String = ""
		for w in para.split(" "):
			var trial: String = w if line == "" else line + " " + w
			if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width and line != "":
				out.append(line)
				line = w
			else:
				line = trial
		out.append(line)
	if out.size() > max_lines:
		out.resize(max_lines)
		out[max_lines - 1] += "…"
	return out

## "Your first resident joins the reef!" with the creature arriving, its income, and the way on.
class ArrivalCard extends Panel:
	signal visit_reef
	signal keep_playing
	var code: int = 0
	var rate: float = 0.0
	var decor_line: String = ""
	var btn_visit: PillButton
	var btn_keep: PillButton
	var _pop: float = 0.0
	var reduced_motion: bool = false
	var _lines: PackedStringArray = PackedStringArray()
	func _init() -> void:
		add_theme_stylebox_override("panel", PoolOverlays.card_style(Pal.GOLD))
		visible = false
		mouse_filter = Control.MOUSE_FILTER_STOP
		btn_visit = PillButton.new()
		btn_visit.text = "Visit the reef"
		btn_visit.icon = "reef"
		btn_visit.accent = Pal.CORAL
		btn_visit.filled = true
		btn_visit.font_size = 21
		add_child(btn_visit)
		btn_keep = PillButton.new()
		btn_keep.text = "Keep playing"
		btn_keep.icon = "wave"
		btn_keep.accent = Pal.SAND
		btn_keep.font_size = 20
		add_child(btn_keep)
		btn_visit.pressed.connect(func() -> void: visit_reef.emit())
		btn_keep.pressed.connect(func() -> void: keep_playing.emit())
	func open(resident_code: int, income_per_hour: float, decoration_text: String, reduced: bool) -> void:
		code = resident_code
		rate = income_per_hour
		decor_line = decoration_text
		reduced_motion = reduced
		visible = true
		_pop = 1.0 if reduced else 0.0
		_relayout()
		if not reduced:
			var tw: Tween = create_tween()
			tw.tween_method(func(v: float) -> void:
				_pop = v
				queue_redraw(), 0.0, 1.0, 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		queue_redraw()
	var max_h: float = 420.0
	var _fs: int = 17
	func _relayout() -> void:
		var font: Font = ThemeDB.fallback_font
		var text: String = "%s joins your reef for good." % Creature.full_name(code).split(" (")[0]
		if rate > 0.0:
			text += "\nIt earns +%s coins every hour, even while you are away." % (("%.1f" % rate) if rate < 100.0 else ("%.0f" % rate))
		if decor_line != "":
			text += "\n" + decor_line
		var bh: float = 46.0
		_fs = 17
		while true:
			_lines = PoolOverlays.wrap(font, text, size.x - 40.0, _fs)
			var need: float = 178.0 + float(_lines.size()) * float(_fs + 5) + 14.0 + 2.0 * bh + 30.0
			if need <= max_h or _fs <= 13:
				size.y = need
				break
			_fs -= 1
		btn_visit.position = Vector2(20, size.y - 2.0 * bh - 28.0)
		btn_visit.size = Vector2(size.x - 40.0, bh)
		btn_keep.position = Vector2(20, size.y - bh - 14.0)
		btn_keep.size = Vector2(size.x - 40.0, bh)
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED and visible:
			_relayout()
	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		draw_string(font, Vector2(0, 36), "Your first resident!", HORIZONTAL_ALIGNMENT_CENTER, size.x, 28, Pal.GOLD)
		var s: float = 96.0 * (0.4 + 0.6 * _pop)
		var c := Vector2(size.x * 0.5, 100.0)
		draw_circle(c, 52.0 * _pop, Color(Pal.GOLD, 0.25 * _pop))
		CreatureArt.draw_creature(self, code, c, s, {"badge": true})
		var y: float = 178.0
		for ln in _lines:
			draw_string(font, Vector2(20, y), ln, HORIZONTAL_ALIGNMENT_CENTER, size.x - 40.0, _fs, Pal.TEXT)
			y += float(_fs + 5)

## The Help sheet: a few short lines, a replayable guided practice, close.
class HelpSheet extends Panel:
	signal replay
	signal close
	var btn_replay: PillButton
	var btn_close: PillButton
	var restart_btn: PillButton
	var _lines: PackedStringArray = PackedStringArray()
	const TEXT: String = "Drag a creature onto an identical one, or tap one and then the other, to merge.\nSlide a piece into an empty neighbour. Three in a row make a bigger creature.\nCurrents slide a whole row or column; the edge wraps round. Preview first, then Shift.\nEvery third turn a Surge lands on the marked cells. Keep some cells free.\nTier 4+ creatures go through the Reef Gate to live in your reef and earn coins."
	func _init() -> void:
		add_theme_stylebox_override("panel", PoolOverlays.card_style(Pal.CORAL))
		visible = false
		mouse_filter = Control.MOUSE_FILTER_STOP
		btn_replay = PillButton.new()
		btn_replay.text = "Practice the guided start"
		btn_replay.icon = "goal"
		btn_replay.accent = Pal.CORAL
		btn_replay.filled = true
		btn_replay.font_size = 19
		add_child(btn_replay)
		btn_close = PillButton.new()
		btn_close.text = "Close"
		btn_close.icon = "x"
		btn_close.accent = Pal.SAND
		btn_close.font_size = 19
		add_child(btn_close)
		btn_replay.pressed.connect(func() -> void: replay.emit())
		btn_close.pressed.connect(func() -> void: close.emit())
	func open() -> void:
		visible = true
		_relayout()
		queue_redraw()
	var max_h: float = 440.0
	var _fs: int = 16
	func _relayout() -> void:
		var font: Font = ThemeDB.fallback_font
		var bh: float = 44.0
		_fs = 16
		while true:
			_lines = PoolOverlays.wrap(font, TEXT, size.x - 44.0, _fs)
			var need: float = 62.0 + float(_lines.size()) * float(_fs + 4) + 16.0 + 2.0 * bh + 26.0
			if need <= max_h or _fs <= 12:
				size.y = need
				break
			_fs -= 1
		btn_replay.position = Vector2(20, size.y - 2.0 * bh - 24.0)
		btn_replay.size = Vector2(size.x - 40.0, bh)
		btn_close.position = Vector2(20, size.y - bh - 12.0)
		btn_close.size = Vector2(size.x - 40.0, bh)
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED and visible:
			_relayout()
	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		draw_string(font, Vector2(0, 34), "How to play", HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Pal.GOLD)
		var y: float = 70.0
		for ln in _lines:
			draw_string(font, Vector2(22, y), ln, HORIZONTAL_ALIGNMENT_LEFT, size.x - 44.0, _fs, Pal.TEXT)
			y += float(_fs + 4)

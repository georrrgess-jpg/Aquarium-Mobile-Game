class_name RosterView
extends Control
## Every resident, as cards in a grid. Lives inside a ScrollContainer; only the rows
## currently in view are drawn, so a big reef stays cheap. Newest (unseen) residents
## come first with a NEW tag.

const CARD_H: float = 92.0
const GAP: float = 8.0

var residents: Array = []
var highlight_ids: Array = []
var columns: int = 4
var scroll: ScrollContainer
var _order: Array = []
var _sb: StyleBoxFlat = StyleBoxFlat.new()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_sb.set_corner_radius_all(12)
	_sb.anti_aliasing = true

func set_data(list: Array, new_ids: Array, available_width: float) -> void:
	residents = list
	highlight_ids = new_ids
	columns = clampi(int(available_width / 112.0), 3, 6)
	_order = list.duplicate()
	_order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var na: bool = new_ids.has(int(a["id"]))
		var nb: bool = new_ids.has(int(b["id"]))
		if na != nb:
			return na
		if int(a["tier"]) != int(b["tier"]):
			return int(a["tier"]) > int(b["tier"])
		return int(a["id"]) > int(b["id"]))
	var rows: int = int(ceil(float(_order.size()) / float(columns)))
	custom_minimum_size = Vector2(available_width, maxf(CARD_H, float(rows) * (CARD_H + GAP)))
	queue_redraw()

func card_width() -> float:
	return (size.x - GAP * float(columns - 1)) / float(columns)

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	if _order.is_empty():
		draw_string(font, Vector2(0, 40), "No residents yet. Send a tier 4+ creature", HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, Pal.TEXT)
		draw_string(font, Vector2(0, 64), "through the Reef Gate to start your reef.", HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, Pal.TEXT)
		return
	var top: float = 0.0
	var view_h: float = 400.0
	if scroll != null:
		top = float(scroll.scroll_vertical)
		view_h = scroll.size.y
	var cw: float = card_width()
	var first_row: int = maxi(0, int(top / (CARD_H + GAP)) - 1)
	var last_row: int = int((top + view_h) / (CARD_H + GAP)) + 1
	for row in range(first_row, last_row + 1):
		for col in columns:
			var i: int = row * columns + col
			if i >= _order.size():
				break
			var r: Dictionary = _order[i]
			var rc := Rect2(Vector2(float(col) * (cw + GAP), float(row) * (CARD_H + GAP)), Vector2(cw, CARD_H))
			var is_new: bool = highlight_ids.has(int(r["id"]))
			var tier: int = int(r["tier"])
			_sb.bg_color = Pal.SAND if not is_new else Pal.SAND.lightened(0.35)
			_sb.border_color = Pal.GOLD if is_new else Pal.tier_color(tier).darkened(0.25)
			_sb.set_border_width_all(4 if is_new else 2)
			draw_style_box(_sb, rc)
			CreatureArt.draw_creature(self, int(r["code"]), rc.position + Vector2(cw * 0.5, 36.0), 56.0, {})
			var nm: String = _short_name(int(r["code"]))
			draw_string(font, rc.position + Vector2(0, 70), nm, HORIZONTAL_ALIGNMENT_CENTER, cw, _fit(font, nm, cw - 8.0, 14), Pal.INK)
			var rate: String = "+%s/h" % _fmt_rate(ReefEconomy.resident_rate(tier))
			draw_string(font, rc.position + Vector2(0, 86), rate, HORIZONTAL_ALIGNMENT_CENTER, cw, 13, Pal.SAND_DEEP.darkened(0.45))
			if is_new:
				var tag := Rect2(rc.position + Vector2(4, 4), Vector2(36, 18))
				draw_rect(tag, Pal.GOLD)
				draw_string(font, tag.position + Vector2(0, 14), "NEW", HORIZONTAL_ALIGNMENT_CENTER, 36, 13, Pal.INK)

static func _short_name(code: int) -> String:
	var fam: int = Creature.family_of(code)
	var tier: int = Creature.tier_of(code)
	if fam == Creature.RAY:
		return "Lantern Ray"
	var names: Array = Creature.TIER_NAMES[fam]
	return "%s %s" % [names[tier - 1], Creature.FAMILY_NAMES[fam]]

static func _fmt_rate(r: float) -> String:
	return ("%.1f" % r) if r < 100.0 else ("%.0f" % r)

static func _fit(font: Font, text: String, width: float, fs: int) -> int:
	while fs > 10 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 1
	return fs

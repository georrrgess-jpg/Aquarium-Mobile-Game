class_name HudWidgets
extends RefCounted
## Small custom-drawn HUD pieces: value chips, the Surge strip and toasts.
## Style boxes are created once per widget and re-coloured, not allocated per redraw.

class Chip extends Control:
	var icon: String = ""
	var label: String = ""
	var value: String = "0":
		set(v):
			if v != value:
				value = v
				queue_redraw()
	var accent: Color = Pal.GOLD
	var punch: float = 0.0
	var _sb: StyleBoxFlat = StyleBoxFlat.new()
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sb.set_border_width_all(2)
		_sb.set_corner_radius_all(14)
		_sb.anti_aliasing = true
	func punch_now() -> void:
		var tw: Tween = create_tween()
		tw.tween_method(func(v: float) -> void:
			punch = v
			queue_redraw(), 1.0, 0.0, 0.35)
	func _draw() -> void:
		_sb.bg_color = Pal.SAND.lerp(accent.lightened(0.4), punch * 0.5)
		_sb.border_color = Pal.SAND_DARK.lerp(accent, punch)
		draw_style_box(_sb, Rect2(Vector2.ZERO, size))
		var font: Font = ThemeDB.fallback_font
		var ic: float = minf(size.y * 0.56, 28.0)
		PillButton.draw_icon(self, icon, Vector2(10 + ic * 0.5, size.y * 0.5), ic, accent.darkened(0.15))
		var tx: float = 18.0 + ic
		var lw: float = size.x - tx - 6.0
		draw_string(font, Vector2(tx, 17), label, HORIZONTAL_ALIGNMENT_LEFT, lw, 13, Pal.SAND_DEEP.darkened(0.35))
		draw_string(font, Vector2(tx, size.y - 8), value, HORIZONTAL_ALIGNMENT_LEFT, lw, fitted_font_size(), Pal.INK)
	## Largest font (24 down to 13) at which the value fits the chip.
	func fitted_font_size() -> int:
		var font: Font = ThemeDB.fallback_font
		var avail: float = size.x - (18.0 + minf(size.y * 0.56, 28.0)) - 6.0
		var fs: int = 24 if size.y >= 46 else 22
		while fs > 13 and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail:
			fs -= 1
		return fs
	func text_fits() -> bool:
		var font: Font = ThemeDB.fallback_font
		var avail: float = size.x - (18.0 + minf(size.y * 0.56, 28.0)) - 6.0
		return font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted_font_size()).x <= avail
	func icon_global_center() -> Vector2:
		var ic: float = minf(size.y * 0.56, 28.0)
		return get_global_transform() * Vector2(10 + ic * 0.5, size.y * 0.5)

class SurgeStrip extends Control:
	var cadence: int = GameConfig.SURGE_CADENCE
	var surge_count: int = GameConfig.SURGE_SIZE
	var turns_left: int = 3
	var incoming: Array = []     # [{cell, code}]
	var message: String = ""     # flood notice text
	var danger: bool = false
	var custom_text: String = "" # trial goal text (replaces the Surge readout)
	var reduced_motion: bool = false
	var _t: float = 0.0
	var _sb: StyleBoxFlat = StyleBoxFlat.new()
	var _slot_sb: StyleBoxFlat = StyleBoxFlat.new()
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sb.set_corner_radius_all(14)
		_sb.anti_aliasing = true
		_slot_sb.bg_color = Pal.INK
		_slot_sb.set_corner_radius_all(10)
	func refresh() -> void:
		queue_redraw()
	func _process(delta: float) -> void:
		if (not incoming.is_empty() or danger) and not reduced_motion and is_visible_in_tree():
			_t += delta
			queue_redraw()
	func _draw() -> void:
		var pending: bool = not incoming.is_empty()
		var col: Color = Pal.RED if danger else Pal.SURGE
		var pulse: float = 0.5 + 0.5 * sin(_t * 6.0) if not reduced_motion else 0.5
		var hot: bool = pending or danger
		_sb.bg_color = Pal.PANEL_DARK.lerp(col, (0.30 * pulse + 0.1) if hot else 0.0)
		_sb.border_color = col if hot else col.darkened(0.35)
		_sb.set_border_width_all(3 if hot else 2)
		draw_style_box(_sb, Rect2(Vector2.ZERO, size))
		var font: Font = ThemeDB.fallback_font
		if custom_text != "":
			draw_string(font, Vector2(14, size.y * 0.5 + 7), custom_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28.0, 18, Pal.TEXT)
			return
		# pips: one per turn of the cycle; filled = turns already taken this cycle
		var px: float = 16.0
		var filled: int = cadence - turns_left
		for i in cadence:
			var cen := Vector2(px + 9.0 + float(i) * 26.0, size.y * 0.5)
			var on: bool = i < filled or pending
			draw_circle(cen, 9.0, col if on else Pal.INK)
			draw_arc(cen, 9.0, 0.0, TAU, 20, col, 2.0, true)
		var tx: float = px + float(cadence) * 26.0 + 6.0
		if danger:
			draw_string(font, Vector2(tx, 22), "FLOOD!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Pal.RED)
			draw_string(font, Vector2(tx, 42), message, HORIZONTAL_ALIGNMENT_LEFT, size.x - tx - 8.0, 15, Pal.TEXT)
		elif pending:
			draw_string(font, Vector2(tx, 22), "SURGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
			draw_string(font, Vector2(tx, 42), "incoming", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Pal.TEXT)
			var slot: float = minf(size.y - 8.0, 44.0)
			var gx: float = size.x - 10.0 - float(incoming.size()) * (slot + 6.0)
			for i in incoming.size():
				var rc := Rect2(gx + float(i) * (slot + 6.0), (size.y - slot) * 0.5, slot, slot)
				draw_style_box(_slot_sb, rc)
				CreatureArt.draw_creature(self, int(incoming[i]["code"]), rc.get_center(), slot * 0.95, {"glow": false})
		else:
			var txt: String = "in %d turn%s" % [turns_left, "" if turns_left == 1 else "s"]
			draw_string(font, Vector2(tx, 22), "Next Surge", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.TEXT_DIM)
			draw_string(font, Vector2(tx, 43), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Pal.TEXT if turns_left > 1 else col)
			draw_string(font, Vector2(size.x - 190.0, size.y * 0.5 + 6.0), "%d creatures drop on empty cells" % surge_count, HORIZONTAL_ALIGNMENT_RIGHT, 180.0, 14, Pal.TEXT_DIM)

## One optional Tide Goal for the standard run, shown as a slim strip above the board.
class GoalStrip extends Control:
	var text: String = ""
	var progress: String = ""      # "3/12" or ""
	var done: bool = false
	var reward: String = ""        # "+80 coins +2 pearls"
	var flash: float = 0.0
	var _sb: StyleBoxFlat = StyleBoxFlat.new()
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sb.set_corner_radius_all(12)
		_sb.anti_aliasing = true
	func celebrate() -> void:
		flash = 1.0
		var tw: Tween = create_tween()
		tw.tween_property(self, "flash", 0.0, 1.2)
		tw.parallel().tween_method(func(_v: float) -> void: queue_redraw(), 0.0, 1.0, 1.2)
	func _draw() -> void:
		var col: Color = Pal.GOLD
		_sb.bg_color = Pal.PANEL_DARK.lerp(col, 0.10 + 0.35 * flash + (0.10 if done else 0.0))
		_sb.border_color = col if done else col.darkened(0.3)
		_sb.set_border_width_all(2)
		draw_style_box(_sb, Rect2(Vector2.ZERO, size))
		var font: Font = ThemeDB.fallback_font
		var cy: float = size.y * 0.5
		# bullseye / tick: a shape cue, not just colour
		var ic := Vector2(17.0, cy)
		if done:
			draw_circle(ic, 9.0, Color("3fae6a"))
			draw_polyline(PackedVector2Array([ic + Vector2(-4.5, 0.5), ic + Vector2(-1.2, 3.8), ic + Vector2(5.0, -3.5)]), Color.WHITE, 2.4, true)
		else:
			draw_arc(ic, 9.0, 0.0, TAU, 20, col, 2.0, true)
			draw_arc(ic, 4.5, 0.0, TAU, 14, col, 2.0, true)
		var right: String = ("Done  " + reward) if done else progress
		var rw: float = font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x if right != "" else 0.0
		var tx: float = 34.0
		var fs: int = 16
		var avail: float = size.x - tx - rw - 20.0
		while fs > 12 and font.get_string_size("Tide Goal: " + text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail:
			fs -= 1
		draw_string(font, Vector2(tx, cy + fs * 0.36), "Tide Goal: " + text, HORIZONTAL_ALIGNMENT_LEFT, avail, fs, Pal.TEXT)
		if right != "":
			draw_string(font, Vector2(size.x - rw - 12.0, cy + 5.5), right, HORIZONTAL_ALIGNMENT_LEFT, rw + 2.0, 15, col if not done else Color("8be0a8"))
	func fits() -> bool:
		var font: Font = ThemeDB.fallback_font
		var right: String = ("Done  " + reward) if done else progress
		var rw: float = font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x if right != "" else 0.0
		return font.get_string_size("Tide Goal: " + text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= size.x - 34.0 - rw - 20.0

class Toast extends PanelContainer:
	var label: Label
	var _view: Label
	var icon_box: Control
	var kind: String = "info"
	var _tw: Tween
	var _sb: StyleBoxFlat = StyleBoxFlat.new()
	const KINDS: Dictionary = {
		"info": {"color": Color("ff7f6b"), "icon": ""},
		"invalid": {"color": Color("ff7f6b"), "icon": "x"},        # not a legal target
		"capped": {"color": Color("ffd166"), "icon": "up"},        # top tier reached
		"nocurrent": {"color": Color("8fd8ff"), "icon": "wave"},   # no Current charge left
		"resolving": {"color": Color("ff9e5e"), "icon": "tide"},   # the tide is landing
		"ended": {"color": Color("ff6f61"), "icon": "tide"},
	}
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sb.bg_color = Color(0.04, 0.2, 0.26, 0.96)
		_sb.border_color = Pal.CORAL
		_sb.set_border_width_all(2)
		_sb.set_corner_radius_all(14)
		_sb.content_margin_left = 12
		_sb.content_margin_right = 14
		_sb.content_margin_top = 8
		_sb.content_margin_bottom = 8
		add_theme_stylebox_override("panel", _sb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		icon_box = Control.new()
		icon_box.custom_minimum_size = Vector2(26, 26)
		icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_box.draw.connect(func() -> void:
			var ic: String = String((KINDS[kind] as Dictionary)["icon"])
			if ic != "":
				PillButton.draw_icon(icon_box, ic, Vector2(13, 13), 22.0, (KINDS[kind] as Dictionary)["color"]))
		row.add_child(icon_box)
		# `label` carries the message text (and is what callers/tests read); `_view` shows it, already
		# wrapped by _fit(), because an auto-wrapping Label keeps a stale minimum height after its width changes.
		label = Label.new()
		label.visible = false
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)
		_view = Label.new()
		_view.add_theme_font_size_override("font_size", 18)
		_view.add_theme_color_override("font_color", Pal.TEXT)
		_view.autowrap_mode = TextServer.AUTOWRAP_OFF
		_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_view)
		modulate.a = 0.0
		visible = false
	## Placement, set by the screen's layout (screen-local rects). `place_in` is the region the toast sits in:
	## centred horizontally, bottom-aligned (growing upward) when `place_bottom`, else top-aligned.
	## It is chosen so a toast never covers the cells or buttons the player has to use next.
	var place_in: Rect2 = Rect2()
	var place_bottom: bool = false
	var max_text_w: float = 400.0
	var max_h: float = 0.0               # when > 0 the text shrinks (down to 14) to stay this tall
	const BASE_FS: int = 18
	const PAD_W: float = 12.0 + 14.0 + 26.0 + 10.0     # style margins + icon box + separation
	func show_text(text: String, secs: float = 1.6) -> void:
		show_kind(text, "info", secs)
	## Width follows the text (up to max_text_w) instead of a fixed 280 px column, so a long
	## announcement takes 2-3 lines instead of 6; the height is measured, not left to autowrap.
	func _fit(text: String) -> void:
		var font: Font = ThemeDB.fallback_font
		var fs: int = BASE_FS
		while true:
			var lines: PackedStringArray = PoolOverlays.wrap(font, text, max_text_w, fs)
			var w: float = 0.0
			for ln in lines:
				w = maxf(w, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
			var h: float = float(lines.size()) * font.get_height(fs)
			_view.text = "\n".join(lines)
			_view.add_theme_font_size_override("font_size", fs)
			_view.custom_minimum_size = Vector2(maxf(120.0, ceilf(w) + 4.0), ceilf(h) + 2.0)
			reset_size()
			if max_h <= 0.0 or size.y <= max_h or fs <= 14:
				break
			fs -= 1
	func _place() -> void:
		if place_in.size.x <= 0.0:
			return
		var x: float = place_in.position.x + (place_in.size.x - size.x) * 0.5
		var y: float = (place_in.end.y - size.y - 6.0) if place_bottom else (place_in.position.y + 6.0)
		position = Vector2(x, y)
	## `kind` picks the border colour and a symbol, so the five reasons a move can be refused
	## (invalid target, capped tier, no Current, tide landing, ended) look different at a glance.
	func show_kind(text: String, k: String, secs: float = 1.6) -> void:
		kind = k if KINDS.has(k) else "info"
		_sb.border_color = (KINDS[kind] as Dictionary)["color"]
		icon_box.visible = String((KINDS[kind] as Dictionary)["icon"]) != ""
		icon_box.queue_redraw()
		label.text = text
		visible = true
		_fit(text)
		_place()
		modulate.a = 1.0
		if _tw != null:
			_tw.kill()
		_tw = create_tween()
		_tw.tween_interval(secs)
		_tw.tween_property(self, "modulate:a", 0.0, 0.3)
		_tw.tween_callback(func() -> void: visible = false)
	func hide_now() -> void:
		if _tw != null:
			_tw.kill()
		visible = false

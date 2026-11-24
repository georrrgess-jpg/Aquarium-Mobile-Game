class_name HudWidgets
extends RefCounted
## Small custom-drawn HUD pieces: value chips, the Surge strip and toasts.

class Chip extends Control:
	var icon: String = ""
	var label: String = ""
	var value: String = "0":
		set(v):
			value = v
			queue_redraw()
	var accent: Color = Pal.GOLD
	var punch: float = 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func punch_now() -> void:
		punch = 1.0
		var tw: Tween = create_tween()
		tw.tween_method(func(v: float) -> void:
			punch = v
			queue_redraw(), 1.0, 0.0, 0.35)
	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Pal.PANEL_DARK.lerp(accent, punch * 0.35)
		sb.border_color = accent.darkened(0.2 + 0.0 * punch)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(14)
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var font: Font = ThemeDB.fallback_font
		var ic: float = minf(size.y * 0.56, 28.0)
		PillButton.draw_icon(self, icon, Vector2(10 + ic * 0.5, size.y * 0.5), ic, accent)
		var tx: float = 18.0 + ic
		var lw: float = size.x - tx - 6.0
		draw_string(font, Vector2(tx, 17), label, HORIZONTAL_ALIGNMENT_LEFT, lw, 13, Pal.TEXT_DIM)
		draw_string(font, Vector2(tx, size.y - 8), value, HORIZONTAL_ALIGNMENT_LEFT, lw, fitted_font_size(), Pal.TEXT)
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
	var turns_left: int = 3
	var incoming: Array = []     # [{cell, code}]
	var message: String = ""     # overrides the idle text (flood notice)
	var danger: bool = false
	var reduced_motion: bool = false
	var _t: float = 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func refresh() -> void:
		queue_redraw()
	func _process(delta: float) -> void:
		if (not incoming.is_empty() or danger) and not reduced_motion:
			_t += delta
			queue_redraw()
	func _draw() -> void:
		var pending: bool = not incoming.is_empty()
		var col: Color = Pal.RED if danger else Pal.SURGE
		var pulse: float = 0.5 + 0.5 * sin(_t * 6.0) if not reduced_motion else 0.5
		var sb := StyleBoxFlat.new()
		sb.bg_color = Pal.PANEL_DARK.lerp(col, (0.30 * pulse + 0.1) if (pending or danger) else 0.0)
		sb.border_color = col if (pending or danger) else col.darkened(0.45)
		sb.set_border_width_all(3 if (pending or danger) else 2)
		sb.set_corner_radius_all(14)
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var font: Font = ThemeDB.fallback_font
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
			# the three incoming creatures with their tiers
			var slot: float = minf(size.y - 8.0, 44.0)
			var gx: float = size.x - 10.0 - float(incoming.size()) * (slot + 6.0)
			for i in incoming.size():
				var rc := Rect2(gx + float(i) * (slot + 6.0), (size.y - slot) * 0.5, slot, slot)
				var b2 := StyleBoxFlat.new()
				b2.bg_color = Pal.INK
				b2.set_corner_radius_all(10)
				draw_style_box(b2, rc)
				CreatureArt.draw_creature(self, int(incoming[i]["code"]), rc.get_center(), slot * 0.95, {"glow": false})
		else:
			var txt: String = "in %d turn%s" % [turns_left, "" if turns_left == 1 else "s"]
			draw_string(font, Vector2(tx, 22), "Next Surge", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.TEXT_DIM)
			draw_string(font, Vector2(tx, 43), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Pal.TEXT if turns_left > 1 else col)
			draw_string(font, Vector2(size.x - 190.0, size.y * 0.5 + 6.0), "%d creatures drop on empty cells" % GameConfig.SURGE_SIZE, HORIZONTAL_ALIGNMENT_RIGHT, 180.0, 14, Pal.TEXT_DIM)

class Toast extends PanelContainer:
	var label: Label
	var _tw: Tween
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.1, 0.16, 0.94)
		sb.border_color = Pal.GOLD
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		add_theme_stylebox_override("panel", sb)
		label = Label.new()
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Pal.TEXT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(320, 0)
		add_child(label)
		modulate.a = 0.0
		visible = false
	func show_text(text: String, secs: float = 1.6) -> void:
		label.text = text
		visible = true
		reset_size()
		modulate.a = 1.0
		if _tw != null:
			_tw.kill()
		_tw = create_tween()
		_tw.tween_interval(secs)
		_tw.tween_property(self, "modulate:a", 0.0, 0.3)
		_tw.tween_callback(func() -> void: visible = false)

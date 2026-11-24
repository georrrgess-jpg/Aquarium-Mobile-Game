class_name ReefScreen
extends Control
## Full-size reef with a clear route back to the pool.

signal back_pressed

var session: GameSession
var reef: ReefView
var btn_back: PillButton
var title_label: Label
var tiers_label: Label
var back_text: String = "Back to the pool"

func setup(s: GameSession) -> void:
	session = s
	title_label = Label.new()
	title_label.text = "Your Reef"
	title_label.add_theme_font_size_override("font_size", 36)
	title_label.add_theme_color_override("font_color", Pal.TEXT)
	title_label.add_theme_color_override("font_outline_color", Pal.INK)
	title_label.add_theme_constant_override("outline_size", 8)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title_label)
	reef = ReefView.new()
	add_child(reef)
	tiers_label = Label.new()
	tiers_label.add_theme_font_size_override("font_size", 19)
	tiers_label.add_theme_color_override("font_color", Pal.TEXT)
	tiers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tiers_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(tiers_label)
	btn_back = PillButton.new()
	btn_back.accent = Pal.TEAL
	btn_back.font_size = 24
	btn_back.icon = "left"
	add_child(btn_back)
	btn_back.pressed.connect(func() -> void: back_pressed.emit())
	resized.connect(_layout)

func _layout() -> void:
	if reef == null:
		return
	var w: float = size.x
	var h: float = size.y
	var cw: float = minf(w, 540.0)
	var x0: float = (w - cw) * 0.5 + 12.0
	var iw: float = cw - 24.0
	title_label.position = Vector2(x0, 14)
	title_label.size = Vector2(iw, 50)
	reef.position = Vector2(x0, 72)
	reef.size = Vector2(iw, maxf(300.0, h - 72.0 - 168.0))
	tiers_label.position = Vector2(x0, 72.0 + reef.size.y + 8.0)
	tiers_label.size = Vector2(iw, 56)
	btn_back.position = Vector2(x0, h - 76.0)
	btn_back.size = Vector2(iw, 64)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or (what == NOTIFICATION_VISIBILITY_CHANGED and visible):
		_layout()

func refresh() -> void:
	_layout()
	var p: Profile = session.profile
	reef.reduced_motion = bool(p.settings.get("reduced_motion", false))
	reef.empty_text = "The reef is empty. Send a tier 4+ creature through the Reef Gate and it will live here forever."
	reef.set_residents(p.residents)
	btn_back.text = back_text
	var counts: Dictionary = p.tier_counts()
	var parts: PackedStringArray = PackedStringArray()
	for t in range(GameConfig.MAX_TIER, 0, -1):
		if counts.has(t):
			parts.append("Tier %d x%d" % [t, int(counts[t])])
	if p.residents.is_empty():
		tiers_label.text = "No residents yet."
	else:
		tiers_label.text = "%d resident%s · %s" % [p.residents.size(), "" if p.residents.size() == 1 else "s", " · ".join(parts)]

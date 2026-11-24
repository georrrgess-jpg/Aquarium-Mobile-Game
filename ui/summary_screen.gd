class_name SummaryScreen
extends Control
## Shown after a flood. Rewards are already banked; survivors worth keeping can
## still be released into the reef before the next run.

signal new_run_pressed
signal reef_pressed
signal home_pressed

var session: GameSession
var sfx: Sfx
var panel: Panel
var title_label: Label
var stats_label: Label
var surv_title: Label
var surv_flow: HFlowContainer
var surv_scroll: ScrollContainer
var btn_new: PillButton
var btn_reef: PillButton
var btn_home: PillButton
var btn_all: PillButton
var banked_label: Label
var band: ResultsBand
var goal_label: Label

func setup(s: GameSession, audio: Sfx) -> void:
	session = s
	sfx = audio
	panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.14, 0.22, 0.97)
	sb.border_color = Pal.CURRENT
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	title_label = _label(34, Pal.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	title_label.text = "The pool flooded"
	stats_label = _label(17, Pal.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	band = ResultsBand.new()
	band.screen = self
	panel.add_child(band)
	goal_label = _label(17, Pal.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	banked_label = _label(19, Pal.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	surv_title = _label(20, Pal.TEAL, HORIZONTAL_ALIGNMENT_LEFT)
	surv_scroll = ScrollContainer.new()
	surv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(surv_scroll)
	surv_flow = HFlowContainer.new()
	surv_flow.add_theme_constant_override("h_separation", 8)
	surv_flow.add_theme_constant_override("v_separation", 8)
	surv_scroll.add_child(surv_flow)
	btn_new = _button("Play Again", "wave", Pal.CORAL)
	btn_reef = _button("Visit Reef", "reef", Pal.CORAL)
	btn_home = _button("Home", "home", Pal.TEXT_DIM)
	btn_all = _button("Release all", "reef", Pal.CORAL)
	btn_new.pressed.connect(func() -> void: new_run_pressed.emit())
	btn_reef.pressed.connect(func() -> void: reef_pressed.emit())
	btn_home.pressed.connect(func() -> void: home_pressed.emit())
	btn_all.pressed.connect(_release_all)
	resized.connect(_layout)

func _label(fs: int, col: Color, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align as HorizontalAlignment
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(l)
	return l

func _button(text: String, icon: String, col: Color) -> PillButton:
	var b := PillButton.new()
	b.text = text
	b.icon = icon
	b.accent = col
	b.font_size = 20
	panel.add_child(b)
	return b

func _layout() -> void:
	if panel == null:
		return
	var w: float = size.x
	var h: float = size.y
	var cw: float = minf(w, 540.0)
	var pw: float = cw - 28.0
	var ph: float = minf(h - 40.0, 880.0)
	panel.position = Vector2((w - pw) * 0.5, (h - ph) * 0.5)
	panel.size = Vector2(pw, ph)
	var m: float = 18.0
	var iw: float = pw - 2.0 * m
	title_label.position = Vector2(m, 12)
	title_label.size = Vector2(iw, 44)
	stats_label.position = Vector2(m, 56)
	stats_label.size = Vector2(iw, 46)
	band.position = Vector2(m, 108)
	band.size = Vector2(iw, 116)
	goal_label.position = Vector2(m, 232)
	goal_label.size = Vector2(iw, 52)
	banked_label.position = Vector2(m, 292)
	banked_label.size = Vector2(iw, 26)
	surv_title.position = Vector2(m, 332)
	surv_title.size = Vector2(iw - 150.0, 28)
	btn_all.position = Vector2(pw - m - 140.0, 328)
	btn_all.size = Vector2(140, 38)
	btn_all.font_size = 17
	surv_scroll.position = Vector2(m, 372)
	surv_scroll.size = Vector2(iw, maxf(60.0, ph - 372.0 - 150.0))
	surv_flow.custom_minimum_size = Vector2(iw - 4.0, 0)
	var by: float = ph - 142.0
	var half: float = (iw - 8.0) * 0.5
	btn_new.position = Vector2(m, by)
	btn_new.size = Vector2(iw, 62)
	btn_new.font_size = 26
	btn_reef.position = Vector2(m, by + 70.0)
	btn_reef.size = Vector2(half, 52)
	btn_reef.font_size = 20
	btn_home.position = Vector2(m + half + 8.0, by + 70.0)
	btn_home.size = Vector2(half, 52)
	btn_home.font_size = 18

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or (what == NOTIFICATION_VISIBILITY_CHANGED and visible):
		_layout()

static func format_time(sec: float) -> String:
	var s: int = int(sec)
	return "%d:%02d" % [int(s / 60.0), s % 60]

func survivors() -> Array:
	var out: Array = []
	var b: Board = session.run.board
	for i in b.cells.size():
		var c: int = b.code_at(i)
		if c != 0 and Creature.tier_of(c) >= GameConfig.RELEASE_MIN_TIER:
			out.append(i)
	return out

func refresh() -> void:
	_layout()
	var run: RunState = session.run
	var st: Dictionary = run.stats
	var why: String = "The next wave had nowhere to land"
	if not run.flood_info.is_empty():
		why = "Only %d free cell%s, but the wave needs %d" % [int(run.flood_info.get("free", 0)), "" if int(run.flood_info.get("free", 0)) == 1 else "s", int(run.flood_info.get("need", 3))]
	stats_label.text = "%s." % why
	var g: Dictionary = run.goal
	if g.is_empty():
		goal_label.visible = false
	else:
		goal_label.visible = true
		if bool(g["done"]):
			goal_label.text = "Tide Goal complete: %s\n+%d coins +%d pearls (banked)" % [g["label"], int(g["coins"]), int(g["pearls"])]
			goal_label.add_theme_color_override("font_color", Color("8be0a8"))
		else:
			var pr: String = (" (%d of %d)" % [int(g["progress"]), int(g["target"])]) if int(g["target"]) > 1 else ""
			goal_label.text = "Tide Goal not met: %s%s\nNo penalty. Next run draws a new one." % [g["label"], pr]
			goal_label.add_theme_color_override("font_color", Pal.TEXT_DIM)
	band.queue_redraw()
	banked_label.text = "Earned %s coins · %s pearls   Banked: %s · %s" % [
		PoolScreen._fmt(int(st["coins"])), PoolScreen._fmt(int(st["pearls"])), PoolScreen.fmt_hud(session.profile.coins), PoolScreen.fmt_hud(session.profile.pearls)]
	_rebuild_survivors()
	_refresh_flow()

## The summary leads naturally onward: when residents were released and not yet seen the
## reef is the highlighted next step (it earns passive coins); otherwise the next pool is.
func _refresh_flow() -> void:
	var p: Profile = session.profile
	var fresh: int = p.unseen_residents.size()
	var rate: float = ReefEconomy.rate_per_hour(p)
	var rate_txt: String = ("%.1f" % rate) if rate < 100.0 else ("%.0f" % rate)
	if fresh > 0:
		btn_reef.text = "Visit Reef · %d new" % fresh
	else:
		btn_reef.text = "Visit Reef"
	btn_reef.filled = false
	btn_new.filled = true
	btn_reef.accent = Pal.CORAL
	btn_new.accent = Pal.CORAL

func _rebuild_survivors() -> void:
	for c in surv_flow.get_children():
		c.queue_free()
	var list: Array = survivors()
	btn_all.visible = list.size() > 1
	if list.is_empty():
		surv_title.text = "No tier %d+ survivors left on the board." % GameConfig.RELEASE_MIN_TIER
		return
	surv_title.text = "Survivors you can still release:"
	for cell in list:
		var code: int = session.run.board.code_at(int(cell))
		var card := Control.new()
		card.custom_minimum_size = Vector2(150, 104)
		card.draw.connect(func() -> void:
			var sbx := StyleBoxFlat.new()
			sbx.bg_color = Pal.PANEL_DARK
			sbx.border_color = Pal.tier_color(Creature.tier_of(code))
			sbx.set_border_width_all(2)
			sbx.set_corner_radius_all(12)
			card.draw_style_box(sbx, Rect2(Vector2.ZERO, card.size))
			CreatureArt.draw_creature(card, code, Vector2(card.size.x * 0.5, 34), 58.0))
		var btn := PillButton.new()
		btn.text = "Release"
		btn.accent = Pal.TEAL
		btn.font_size = 17
		btn.position = Vector2(10, 68)
		btn.size = Vector2(130, 30)
		btn.pressed.connect(func() -> void: _release_one(int(cell)))
		card.add_child(btn)
		surv_flow.add_child(card)

func _release_one(cell: int) -> void:
	var res: Dictionary = session.try_release(cell)
	if bool(res["ok"]):
		if sfx != null:
			sfx.play("release")
		Haptics.release()
		refresh()

func _release_all() -> void:
	for cell in survivors():
		session.try_release(int(cell))
	if sfx != null:
		sfx.play("release")
	refresh()


## The three result tiles: best merge (with its creature), releases, chains.
class ResultsBand extends Control:
	var screen: SummaryScreen
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _tile(rc: Rect2, title: String) -> void:
		ItemArt.draw_card_frame(self, rc, ItemArt.STATE_AVAILABLE, {"badge": false})
		var font: Font = ThemeDB.fallback_font
		draw_string(font, Vector2(rc.position.x + 4.0, rc.position.y + 17.0), title, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x - 8.0, 14, Pal.SAND_DEEP.darkened(0.5))
	func _draw() -> void:
		if screen == null or screen.session == null or screen.session.run == null:
			return
		var run: RunState = screen.session.run
		var st: Dictionary = run.stats
		var font: Font = ThemeDB.fallback_font
		var gap: float = 8.0
		var tw: float = (size.x - 2.0 * gap) / 3.0
		var t0 := Rect2(0, 0, tw, size.y)
		var t1 := Rect2(tw + gap, 0, tw, size.y)
		var t2 := Rect2(2.0 * (tw + gap), 0, tw, size.y)
		_tile(t0, "Best merge")
		var code: int = int(st.get("best_merge_code", 0))
		if code > 0:
			CreatureArt.draw_creature(self, code, Vector2(t0.get_center().x, t0.position.y + 54.0), 62.0)
			var nm: String = Book.tier_name(code)
			var fs: int = 14
			while fs > 11 and font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > tw - 10.0:
				fs -= 1
			draw_string(font, Vector2(t0.position.x + 5.0, t0.end.y - 8.0), nm, HORIZONTAL_ALIGNMENT_CENTER, tw - 10.0, fs, Pal.INK)
		else:
			draw_string(font, Vector2(t0.position.x, t0.position.y + 64.0), "none", HORIZONTAL_ALIGNMENT_CENTER, tw, 20, Pal.INK)
		_tile(t1, "Released")
		draw_string(font, Vector2(t1.position.x, t1.position.y + 66.0), str(int(st["releases"])), HORIZONTAL_ALIGNMENT_CENTER, tw, 40, Pal.INK)
		draw_string(font, Vector2(t1.position.x + 4.0, t1.end.y - 10.0), "to your reef", HORIZONTAL_ALIGNMENT_CENTER, tw - 8.0, 14, Pal.SAND_DEEP.darkened(0.5))
		_tile(t2, "Longest chain")
		draw_string(font, Vector2(t2.position.x, t2.position.y + 66.0), ("+%d" % int(st["best_chain"])) if int(st["best_chain"]) > 0 else "none", HORIZONTAL_ALIGNMENT_CENTER, tw, 40 if int(st["best_chain"]) > 0 else 24, Pal.INK)
		draw_string(font, Vector2(t2.position.x + 4.0, t2.end.y - 10.0), "%d merges · %d turns" % [int(st["merges"]), run.turn], HORIZONTAL_ALIGNMENT_CENTER, tw - 8.0, 13, Pal.SAND_DEEP.darkened(0.5))

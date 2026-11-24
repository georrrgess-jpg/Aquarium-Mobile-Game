class_name ReefHub
extends Control
## The home of the game: the living reef, what it earns, and one persistent
## Play / Resume / Back button. Opened from the start of the app, from the pool and
## from the run summary. Tabs below the aquarium hold the resident roster and the
## decoration shop (Update 3 adds goals and the Tide Trial); nothing covers the aquarium.

signal play_pressed

const PAD: float = 10.0
const MAX_COL_W: float = 540.0
const PANEL_H: float = 292.0

var session: GameSession
var sfx: Sfx
var context: String = "start"        # start | pool | summary

var title_label: Label
var chip_coins: HudWidgets.Chip
var chip_pearls: HudWidgets.Chip
var chip_res: HudWidgets.Chip
var reef: ReefView
var income: IncomeStrip
var chest_banner: ChestBanner
var btn_claim: PillButton
var tab_buttons: Array = []
var panel: Panel
var roster_scroll: ScrollContainer
var roster: RosterView
var decor_list: DecorList
var decor_summary: Label
var btn_buy: PillButton
var btn_cancel_buy: PillButton
var btn_play: PillButton
var btn_motion: PillButton
var btn_sound: PillButton
var btn_haptics: PillButton
var toast: HudWidgets.Toast
## extra tabs (Update 3 adds Goals / Trial through register_tab)
var _tabs: Array = []                 # [{id, label, control}]
var _active_tab: String = "residents"
var _sel_kind: int = -1
var _sel_slot: int = -1
var _buying: bool = false
var _signature: String = ""

func setup(s: GameSession, audio: Sfx) -> void:
	session = s
	sfx = audio
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", Pal.TEXT)
	title_label.add_theme_color_override("font_outline_color", Pal.INK)
	title_label.add_theme_constant_override("outline_size", 8)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title_label)
	chip_coins = _chip("coin", "Coins", Pal.GOLD)
	chip_pearls = _chip("pearl", "Pearls", Color("7fb2d8"))
	chip_res = _chip("reef", "Residents", Pal.CORAL)
	reef = ReefView.new()
	add_child(reef)
	reef.slot_tapped.connect(_select_slot)
	income = IncomeStrip.new()
	add_child(income)
	chest_banner = ChestBanner.new()
	add_child(chest_banner)
	btn_claim = _btn("Claim", "coin", Pal.CORAL)
	btn_claim.filled = true
	btn_claim.pressed.connect(_claim)
	panel = Panel.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Pal.PANEL_DARK
	psb.border_color = Pal.SAND_DARK
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", psb)
	add_child(panel)
	# residents tab
	roster_scroll = ScrollContainer.new()
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(roster_scroll)
	roster = RosterView.new()
	roster.scroll = roster_scroll
	roster_scroll.add_child(roster)
	roster_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: roster.queue_redraw())
	# decor tab
	decor_list = DecorList.new()
	decor_list.hub = self
	panel.add_child(decor_list)
	decor_list.row_tapped.connect(_select_decor)
	decor_summary = Label.new()
	decor_summary.add_theme_font_size_override("font_size", 15)
	decor_summary.add_theme_color_override("font_color", Pal.TEXT)
	decor_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(decor_summary)
	btn_buy = _btn("Buy and place", "coin", Pal.CORAL, panel)
	btn_buy.filled = true
	btn_buy.pressed.connect(_buy)
	btn_cancel_buy = _btn("Cancel", "x", Pal.TEXT_DIM, panel)
	btn_cancel_buy.pressed.connect(_cancel_placement)
	_tabs = [
		{"id": "residents", "label": "Residents", "controls": [roster_scroll]},
		{"id": "decor", "label": "Decor", "controls": [decor_list, decor_summary, btn_buy, btn_cancel_buy]},
	]
	btn_play = _btn("Play", "wave", Pal.CORAL)
	btn_play.filled = true
	btn_play.pressed.connect(func() -> void: play_pressed.emit())
	btn_motion = _btn("", "", Pal.TEXT_DIM)
	btn_sound = _btn("", "", Pal.TEXT_DIM)
	btn_haptics = _btn("", "", Pal.TEXT_DIM)
	btn_motion.pressed.connect(func() -> void: _toggle("reduced_motion"))
	btn_sound.pressed.connect(func() -> void: _toggle("sound"))
	btn_haptics.pressed.connect(func() -> void: _toggle("haptics"))
	toast = HudWidgets.Toast.new()
	add_child(toast)
	_rebuild_tab_buttons()
	resized.connect(_layout)

func _chip(icon: String, label: String, accent: Color) -> HudWidgets.Chip:
	var c := HudWidgets.Chip.new()
	c.icon = icon
	c.label = label
	c.accent = accent
	add_child(c)
	return c

func _btn(text: String, icon: String, accent: Color, parent: Node = null) -> PillButton:
	var b := PillButton.new()
	b.text = text
	b.icon = icon
	b.accent = accent
	(parent if parent != null else self).add_child(b)
	return b

## Update 3 hook: add another tab whose controls live inside the panel.
func register_tab(id: String, label: String, controls: Array) -> void:
	_tabs.append({"id": id, "label": label, "controls": controls})
	_rebuild_tab_buttons()

func _rebuild_tab_buttons() -> void:
	for b in tab_buttons:
		(b as Node).queue_free()
	tab_buttons.clear()
	for t in _tabs:
		var b := PillButton.new()
		b.text = String(t["label"])
		b.accent = Pal.SAND_DARK
		b.font_size = 17
		var id: String = String(t["id"])
		b.pressed.connect(func() -> void: _show_tab(id))
		add_child(b)
		tab_buttons.append(b)
	_layout()

func _show_tab(id: String) -> void:
	if _active_tab == "decor" and id != "decor":
		_cancel_placement()
	_active_tab = id
	for t in _tabs:
		for c in t["controls"]:
			(c as Control).visible = String(t["id"]) == id
	for i in _tabs.size():
		var b: PillButton = tab_buttons[i]
		b.toggled = String(_tabs[i]["id"]) == id
		b.filled = b.toggled
		b.accent = Pal.SAND if b.toggled else Pal.SAND_DARK
	_layout()
	_refresh_decor()

# --- Layout -------------------------------------------------------------------------------------

func _layout() -> void:
	if reef == null:
		return
	var w: float = size.x
	var h: float = size.y
	var cw: float = minf(w, MAX_COL_W)
	var x0: float = (w - cw) * 0.5 + PAD
	var iw: float = cw - 2.0 * PAD
	var g: float = 6.0
	title_label.clip_text = true
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.position = Vector2(x0, 2)
	title_label.size = Vector2(iw, 46)
	title_label.custom_minimum_size = Vector2(0, 46)
	var y: float = 52.0
	var chip_w: float = (iw - 2.0 * g) / 3.0
	for i in 3:
		var c: HudWidgets.Chip = [chip_coins, chip_pearls, chip_res][i]
		c.position = Vector2(x0 + float(i) * (chip_w + g), y)
		c.size = Vector2(chip_w, 52)
	y += 52.0 + 8.0
	var chest_on: bool = ReefEconomy.chest_amount(session.profile) > 0
	var below: float = 46.0 + 8.0 + (58.0 if chest_on else 0.0) + 42.0 + 6.0 + PANEL_H + 8.0 + 64.0 + 8.0 + 40.0 + 8.0
	var aq_h: float = maxf(180.0, h - y - below)
	reef.position = Vector2(x0, y)
	reef.size = Vector2(iw, aq_h)
	y += aq_h + 8.0
	income.position = Vector2(x0, y)
	income.size = Vector2(iw, 46)
	y += 46.0 + 8.0
	chest_banner.visible = chest_on
	btn_claim.visible = chest_on
	if chest_on:
		chest_banner.position = Vector2(x0, y)
		chest_banner.size = Vector2(iw, 50)
		btn_claim.position = Vector2(x0 + iw - 124.0, y + 5.0)
		btn_claim.size = Vector2(116, 40)
		y += 58.0
	var tab_w: float = (iw - g * float(_tabs.size() - 1)) / float(maxi(1, _tabs.size()))
	for i in tab_buttons.size():
		var b: PillButton = tab_buttons[i]
		b.position = Vector2(x0 + float(i) * (tab_w + g), y)
		b.size = Vector2(tab_w, 42)
	y += 42.0 + 6.0
	panel.position = Vector2(x0, y)
	panel.size = Vector2(iw, PANEL_H)
	var pw: float = iw - 16.0
	roster_scroll.position = Vector2(8, 8)
	roster_scroll.size = Vector2(pw, PANEL_H - 16.0)
	roster.custom_minimum_size.x = pw
	decor_list.position = Vector2(8, 6)
	decor_list.size = Vector2(pw, 200.0)
	decor_summary.position = Vector2(10, 208)
	decor_summary.size = Vector2(pw - 4.0, 42)
	btn_buy.position = Vector2(8, PANEL_H - 46.0)
	btn_buy.size = Vector2(pw * 0.62, 38)
	btn_cancel_buy.position = Vector2(8.0 + pw * 0.62 + 6.0, PANEL_H - 46.0)
	btn_cancel_buy.size = Vector2(pw * 0.38 - 6.0, 38)
	y += PANEL_H + 8.0
	btn_play.position = Vector2(x0, y)
	btn_play.size = Vector2(iw, 64)
	btn_play.font_size = 26
	y += 64.0 + 8.0
	var tw: float = (iw - 2.0 * g) / 3.0
	for i in 3:
		var tb: PillButton = [btn_motion, btn_sound, btn_haptics][i]
		tb.position = Vector2(x0 + float(i) * (tw + g), y)
		tb.size = Vector2(tw, 40)
		tb.font_size = 15
	toast.position = Vector2(x0 + 20.0, reef.position.y + 20.0)
	toast.size = Vector2(iw - 40.0, 0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or (what == NOTIFICATION_VISIBILITY_CHANGED and visible and reef != null):
		_layout()

# --- Refresh ----------------------------------------------------------------------------------------

func refresh(new_context: String) -> void:
	context = new_context
	session.settle_income()
	var p: Profile = session.profile
	title_label.text = "Tidepool Tycoon" if context == "start" else "Your Reef"
	var rm: bool = bool(p.settings.get("reduced_motion", false))
	reef.reduced_motion = rm
	reef.set_residents(p.residents)
	reef.set_decorations(p.decorations)
	reef.set_highlight(p.unseen_residents.duplicate())
	_signature = ""
	_refresh_numbers()
	_refresh_buttons()
	_show_tab(_active_tab)
	roster.set_data(p.residents, p.unseen_residents.duplicate(), roster_scroll.size.x if roster_scroll.size.x > 0 else 480.0)
	roster_scroll.scroll_vertical = 0
	_refresh_decor()
	_layout()

func _refresh_buttons() -> void:
	var p: Profile = session.profile
	var run: RunState = session.run
	match context:
		"pool":
			btn_play.text = "Back to the pool"
			btn_play.icon = "left"
		"summary":
			btn_play.text = "Back to the summary"
			btn_play.icon = "left"
		_:
			btn_play.icon = "wave"
			if run == null:
				btn_play.text = "Dive in"
			elif run.status == RunState.FLOODED:
				btn_play.text = "See run summary"
			else:
				btn_play.text = "Resume run"
	var rm: bool = bool(p.settings.get("reduced_motion", false))
	btn_motion.text = "Motion: reduced" if rm else "Motion: full"
	btn_motion.toggled = rm
	var snd: bool = bool(p.settings.get("sound", true))
	btn_sound.text = "Sound: on" if snd else "Sound: off"
	btn_sound.toggled = not snd
	var hap: bool = bool(p.settings.get("haptics", true))
	btn_haptics.text = "Haptics: on" if hap else "Haptics: off"
	btn_haptics.toggled = not hap
	if sfx != null:
		sfx.enabled = snd
	Haptics.enabled = hap
	Haptics.reduced_motion = rm

func _toggle(key: String) -> void:
	var cur: bool = bool(session.profile.settings.get(key, key != "reduced_motion"))
	session.set_setting(key, not cur)
	reef.reduced_motion = bool(session.profile.settings.get("reduced_motion", false))
	_refresh_buttons()

func _refresh_numbers() -> void:
	var p: Profile = session.profile
	chip_coins.value = PoolScreen.fmt_hud(p.coins)
	chip_pearls.value = PoolScreen.fmt_hud(p.pearls)
	chip_res.value = str(p.residents.size())
	income.rate = ReefEconomy.rate_per_hour(p)
	income.beauty = ReefEconomy.total_beauty(p)
	income.queue_redraw()
	chest_banner.amount = ReefEconomy.chest_amount(p)
	chest_banner.full = ReefEconomy.chest_full(p)
	chest_banner.secs = p.chest_secs
	chest_banner.queue_redraw()

## Called by Main once a second after passive income was settled in memory.
func on_income_tick() -> void:
	if not visible:
		return
	var had_chest: bool = chest_banner.visible
	_refresh_numbers()
	if had_chest != (ReefEconomy.chest_amount(session.profile) > 0):
		_layout()
	_refresh_decor_summary()

# --- Chest ---------------------------------------------------------------------------------------------

func _claim() -> void:
	btn_claim.enabled = false           # one press, one claim (the core is idempotent as well)
	var paid: int = session.claim_chest()
	if paid > 0:
		toast.show_text("Chest opened: +%s coins" % PoolScreen._fmt(paid), 2.0)
		if sfx != null:
			sfx.play("release")
		Haptics.release()
		chip_coins.punch_now()
	btn_claim.enabled = true
	_refresh_numbers()
	_layout()

# --- Decorations -----------------------------------------------------------------------------------------

func _select_decor(kind: int) -> void:
	var def: Dictionary = GameConfig.DECORATIONS[kind]
	if ReefEconomy.owns(session.profile, String(def["id"])):
		toast.show_text("%s is already in your reef." % String(def["name"]), 1.6)
		return
	if _sel_kind == kind:
		_cancel_placement()
		return
	_sel_kind = kind
	_sel_slot = -1
	reef.set_placement(kind, -1)
	if sfx != null:
		sfx.play("select")
	_refresh_decor()

func _select_slot(slot: int) -> void:
	if _sel_kind < 0:
		return
	_sel_slot = slot
	reef.set_placement(_sel_kind, slot)
	if sfx != null:
		sfx.play("select")
	_refresh_decor()

func _cancel_placement() -> void:
	_sel_kind = -1
	_sel_slot = -1
	if reef != null:
		reef.set_placement(-1, -1)
	_refresh_decor()

func _refresh_decor() -> void:
	if decor_list == null:
		return
	decor_list.queue_redraw()
	_refresh_decor_summary()

func _refresh_decor_summary() -> void:
	if decor_summary == null:
		return
	var p: Profile = session.profile
	btn_cancel_buy.visible = _active_tab == "decor" and _sel_kind >= 0
	btn_buy.visible = _active_tab == "decor"
	if _sel_kind < 0:
		decor_summary.text = "Pick a decoration. Beauty raises what the whole reef earns."
		btn_buy.text = "Choose a decoration"
		btn_buy.enabled = false
		return
	var def: Dictionary = GameConfig.DECORATIONS[_sel_kind]
	var price: int = int(def["price"])
	var now_rate: float = ReefEconomy.rate_per_hour(p)
	var new_rate: float = ReefEconomy.rate_with_decoration(p, String(def["id"]))
	var gain: String = "%.1f → %.1f coins/h (+%.1f)" % [now_rate, new_rate, new_rate - now_rate]
	if _sel_slot < 0:
		decor_summary.text = "%s · %d coins\nIncome %s. Tap a marked spot above." % [def["name"], price, gain]
		btn_buy.text = "Pick a spot"
		btn_buy.enabled = false
	elif p.coins < price:
		decor_summary.text = "%s · %d coins · need %d more\nIncome %s" % [def["name"], price, price - p.coins, gain]
		btn_buy.text = "Not enough coins"
		btn_buy.enabled = false
	else:
		decor_summary.text = "%s on spot %d · %d coins\nIncome %s" % [def["name"], _sel_slot + 1, price, gain]
		btn_buy.text = "Buy for %d" % price
		btn_buy.enabled = not _buying

func _buy() -> void:
	if _buying or _sel_kind < 0 or _sel_slot < 0:
		return
	_buying = true
	btn_buy.enabled = false             # the button cannot be pressed twice while this resolves
	var def: Dictionary = GameConfig.DECORATIONS[_sel_kind]
	var before: float = ReefEconomy.rate_per_hour(session.profile)
	var res: Dictionary = session.purchase_decoration(String(def["id"]), _sel_slot)
	if bool(res["ok"]):
		var after: float = ReefEconomy.rate_per_hour(session.profile)
		toast.show_text("%s placed! Income +%.1f/h" % [def["name"], after - before], 2.2)
		if sfx != null:
			sfx.pop(2)
		Haptics.release()
		reef.set_decorations(session.profile.decorations)
		chip_coins.punch_now()
		_cancel_placement()
	else:
		toast.show_text(String(res["reason"]), 2.0)
		if sfx != null:
			sfx.play("reject")
		Haptics.reject()
	_buying = false
	_refresh_numbers()
	_refresh_decor()

# --- Leaving -------------------------------------------------------------------------------------------------

## The player has looked at the reef: stop highlighting new arrivals.
func leave() -> void:
	_cancel_placement()
	session.acknowledge_residents()

# --- Inner controls ---------------------------------------------------------------------------------------

class IncomeStrip extends Control:
	var rate: float = 0.0
	var beauty: int = 0
	var _sb: StyleBoxFlat = StyleBoxFlat.new()
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sb.bg_color = Pal.SAND
		_sb.border_color = Pal.SAND_DARK
		_sb.set_border_width_all(2)
		_sb.set_corner_radius_all(14)
		_sb.anti_aliasing = true
	func _draw() -> void:
		draw_style_box(_sb, Rect2(Vector2.ZERO, size))
		var font: Font = ThemeDB.fallback_font
		PillButton.draw_icon(self, "coin", Vector2(24, size.y * 0.5), 24.0, Pal.GOLD)
		var main_txt: String = "+%s coins / hour" % (("%.1f" % rate) if rate < 100.0 else ("%.0f" % rate))
		draw_string(font, Vector2(44, size.y * 0.5 + 8), main_txt, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.55, 22, Pal.INK)
		var mult: String = "Beauty %d  ×%.2f" % [beauty, 1.0 + float(beauty) / GameConfig.BEAUTY_DIVISOR]
		draw_string(font, Vector2(size.x * 0.52, size.y * 0.5 + 6), mult, HORIZONTAL_ALIGNMENT_RIGHT, size.x * 0.48 - 14.0, 17, Pal.SAND_DEEP.darkened(0.5))

class ChestBanner extends Control:
	var amount: int = 0
	var full: bool = false
	var secs: int = 0
	var _sb: StyleBoxFlat = StyleBoxFlat.new()
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sb.bg_color = Pal.CORAL.darkened(0.35)
		_sb.border_color = Pal.GOLD
		_sb.set_border_width_all(3)
		_sb.set_corner_radius_all(14)
		_sb.anti_aliasing = true
	func _draw() -> void:
		draw_style_box(_sb, Rect2(Vector2.ZERO, size))
		var font: Font = ThemeDB.fallback_font
		# a little chest: lid + body + lock (shape cue)
		draw_rect(Rect2(12, 14, 30, 24), Pal.SAND_DEEP)
		draw_rect(Rect2(12, 14, 30, 9), Pal.SAND_DARK)
		draw_rect(Rect2(24, 20, 6, 8), Pal.GOLD)
		draw_string(font, Vector2(52, 22), "Offline chest", HORIZONTAL_ALIGNMENT_LEFT, size.x - 200.0, 15, Pal.TEXT)
		var away: String = "%dh %02dm away" % [int(secs / 3600.0), int(secs / 60.0) % 60]
		draw_string(font, Vector2(52, 42), "%s coins · %s%s" % [PoolScreen._fmt(amount), away, " (8h max)" if full else ""], HORIZONTAL_ALIGNMENT_LEFT, size.x - 190.0, 16, Pal.TEXT)

class DecorList extends Control:
	signal row_tapped(kind: int)
	var hub: Control
	var _press: Vector2 = Vector2.ZERO
	var _sb: StyleBoxFlat = StyleBoxFlat.new()
	const ROW_H: float = 38.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_sb.set_corner_radius_all(10)
		_sb.anti_aliasing = true
	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press = mb.position
		elif _press.distance_to(mb.position) < 12.0:
			var i: int = int(mb.position.y / ROW_H)
			if i >= 0 and i < GameConfig.DECORATIONS.size():
				row_tapped.emit(i)
	func _draw() -> void:
		if hub == null or hub.session == null:
			return
		var p: Profile = hub.session.profile
		var font: Font = ThemeDB.fallback_font
		for i in GameConfig.DECORATIONS.size():
			var def: Dictionary = GameConfig.DECORATIONS[i]
			var rc := Rect2(0, float(i) * ROW_H, size.x, ROW_H - 3.0)
			var owned: bool = ReefEconomy.owns(p, String(def["id"]))
			var chosen: bool = hub._sel_kind == i
			var afford: bool = p.coins >= int(def["price"])
			_sb.bg_color = Pal.SAND if chosen else (Pal.PANEL if not owned else Pal.PANEL.darkened(0.25))
			_sb.border_color = Pal.GOLD if chosen else Pal.SAND_DARK.darkened(0.2)
			_sb.set_border_width_all(3 if chosen else 1)
			draw_style_box(_sb, rc)
			var tc: Color = Pal.INK if chosen else Pal.TEXT
			DecorArt.draw(self, i, Rect2(6, rc.position.y + 1, 26, 33), 0.0, {"animate": false, "alpha": 0.4 if owned else 1.0})
			draw_string(font, Vector2(40, rc.position.y + 17), String(def["name"]), HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.45, 17, tc)
			draw_string(font, Vector2(40, rc.position.y + 32), "Beauty +%d" % int(def["beauty"]), HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.4, 13, tc if chosen else Pal.TEXT_DIM)
			var right: String = "Placed" if owned else "%d" % int(def["price"])
			var rcol: Color = tc
			if not owned and not afford:
				rcol = Pal.RED if not chosen else Pal.CORAL_DARK
			draw_string(font, Vector2(size.x * 0.5, rc.position.y + 25), right, HORIZONTAL_ALIGNMENT_RIGHT, size.x * 0.5 - 12.0, 18, rcol)

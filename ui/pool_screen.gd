class_name PoolScreen
extends Control
## The playable pool: HUD, Surge strip, board, Reef Gate, prompts, Current
## controls and a peek at the reef. It asks the GameSession to resolve every
## action and then replays the returned events.

signal open_reef
signal open_home
signal run_flooded
signal trial_exit
signal help_replay
signal open_reef_decor

const GATE_W: float = 84.0
const GAP: float = 8.0
const PAD: float = 10.0
const MAX_COL_W: float = 540.0

var session: GameSession
## Settings (motion, sound, haptics) always come from the REAL profile, also in the Trial
## whose own session carries a throwaway profile.
var settings_session: GameSession
var sfx: Sfx
var reduced_motion: bool = false
var anim_speed: float = 1.0
var busy: bool = false

# current-mode state
var cur_mode: bool = false
var cur_axis: int = -1
var cur_index: int = -1
var cur_dir: int = 0

var _shown_coins: int = 0
var _shown_pearls: int = 0
## Pearls still flying to the balance. The HUD only snaps to the true balance
## when none are in flight, so a late arrival can never be counted twice.
var _pearls_in_flight: int = 0
## Caches so selection taps stay cheap: the coach hint scans every Current preview, so it is
## computed once per committed state (bumped in _refresh_all), not once per tap.
var _state_version: int = 0
var _hint_cache: Dictionary = {}
var _hint_cache_version: int = -1
var _stuck_cache: bool = false
var _stuck_cache_version: int = -1
var _preview_info: Dictionary = {}
var _reef_sig: String = ""
var _income_label_rate: int = -1
var _tip_pos: int = 0
var _tip_done: bool = true

var board_view: BoardView
var gate: GateView
var reef_peek: ReefView
var chip_coins: HudWidgets.Chip
var chip_pearls: HudWidgets.Chip
var chip_turn: HudWidgets.Chip
var chip_currents: HudWidgets.Chip
var surge_strip: HudWidgets.SurgeStrip
var btn_home: PillButton
var btn_reef: PillButton
var btn_motion: PillButton
var btn_sound: PillButton
var btn_current: PillButton
var btn_dir_a: PillButton
var btn_dir_b: PillButton
var btn_confirm: PillButton
var btn_tide: PillButton
var prompt_panel: Panel
var prompt_label: Label
var toast: HudWidgets.Toast
var fx_layer: Control
## Tide Trial mode: the same pool UI on a separate, fixed board and its own session.
var trial_mode: bool = false
var trial: TideTrial = null
var claim_reward: Callable = Callable()      # set by Main: pays the first-clear reward on the REAL profile
var btn_hint: PillButton
var btn_retry: PillButton
var results_panel: Panel
var results_title: Label
var results_body: Label
var btn_res_retry: PillButton
var btn_res_back: PillButton
var chain_label: Label
## Update 4: guided start, Hint, Help, Calm/Help sandboxes
var help_mode: bool = false
var calm_mode: bool = false
var btn_skip: PillButton
var btn_help: PillButton
var btn_restart_guided: PillButton
var btn_keep_going: PillButton
var help_sheet: PoolOverlays.HelpSheet
var arrival: PoolOverlays.ArrivalCard
var _recovery: bool = false
var _recovery_version: int = -1
var _skip_armed: bool = false
var _tutorial_prompt: bool = false
var _tg_cache: Dictionary = {}
var _tg_version: int = -1

func is_sandbox() -> bool:
	return trial_mode or help_mode or calm_mode

func setup(s: GameSession, audio: Sfx) -> void:
	session = s
	settings_session = s
	sfx = audio
	_build()

func _build() -> void:
	clip_contents = true
	board_view = BoardView.new()
	board_view.session = session
	board_view.sfx = sfx
	gate = GateView.new()
	board_view.gate = gate
	add_child(board_view)
	add_child(gate)
	reef_peek = ReefView.new()
	reef_peek.compact = true
	reef_peek.caption = "Your reef"
	add_child(reef_peek)
	chip_coins = _chip("coin", "Coins", Pal.GOLD)
	chip_pearls = _chip("pearl", "Pearls", Color("bcdcff"))
	chip_turn = _chip("tide", "Turn", Pal.TEAL)
	chip_currents = _chip("wave", "Currents", Pal.CURRENT)
	surge_strip = HudWidgets.SurgeStrip.new()
	add_child(surge_strip)
	btn_home = _btn("", "home", Pal.TEXT_DIM)
	btn_reef = _btn("Reef", "reef", Pal.TEAL)
	btn_motion = _btn("", "motion", Pal.TEXT_DIM)
	btn_sound = _btn("", "sound", Pal.TEXT_DIM)
	btn_current = _btn("Current", "wave", Pal.CURRENT)
	btn_dir_a = _btn("", "left", Pal.CURRENT)
	btn_dir_b = _btn("", "right", Pal.CURRENT)
	btn_confirm = _btn("Shift", "check", Pal.CORAL)
	btn_confirm.filled = true
	btn_tide = _btn("No moves: advance the tide", "tide", Pal.SURGE)
	prompt_panel = Panel.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Pal.SAND
	psb.border_color = Pal.CORAL
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(14)
	prompt_panel.add_theme_stylebox_override("panel", psb)
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt_panel)
	prompt_label = Label.new()
	prompt_label.add_theme_font_size_override("font_size", 19)
	prompt_label.add_theme_color_override("font_color", Pal.INK)
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_panel.add_child(prompt_label)
	fx_layer = Control.new()
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)
	chain_label = Label.new()
	chain_label.add_theme_font_size_override("font_size", 40)
	chain_label.add_theme_color_override("font_color", Pal.GOLD)
	chain_label.add_theme_color_override("font_outline_color", Pal.INK)
	chain_label.add_theme_constant_override("outline_size", 10)
	chain_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chain_label.visible = false
	fx_layer.add_child(chain_label)
	toast = HudWidgets.Toast.new()
	fx_layer.add_child(toast)

	btn_home.pressed.connect(func() -> void: if not busy: open_home.emit())
	btn_reef.pressed.connect(func() -> void: if not busy: open_reef.emit())
	reef_peek.tapped.connect(func() -> void: if not busy: open_reef.emit())
	btn_motion.pressed.connect(_toggle_motion)
	btn_sound.pressed.connect(_toggle_sound)
	btn_current.pressed.connect(_on_current_button)
	btn_dir_a.pressed.connect(func() -> void: _set_dir(-1))
	btn_dir_b.pressed.connect(func() -> void: _set_dir(1))
	btn_confirm.pressed.connect(_on_confirm)
	btn_tide.pressed.connect(_on_tide)
	gate.tapped.connect(_on_gate_tapped)
	board_view.drop_requested.connect(_on_drop)
	board_view.release_requested.connect(_request_release)
	board_view.selection_changed.connect(func(_c: int) -> void: _update_prompt())
	board_view.line_picked.connect(_on_line_picked)
	board_view.line_dragged.connect(_on_line_dragged)
	board_view.reward_popped.connect(_on_reward)
	board_view.refund_earned.connect(func() -> void:
		chip_currents.punch_now()
		toast.show_text("Chain! +1 Current", 1.2))
	board_view.chain_cue.connect(_on_chain_cue)
	btn_hint = _btn("Hint", "hint", Pal.GOLD)
	btn_retry = _btn("Retry", "retry", Pal.CORAL)
	btn_retry.visible = false
	btn_hint.pressed.connect(_on_hint)
	btn_retry.pressed.connect(_on_trial_retry)
	btn_help = _btn("Help", "help", Pal.SAND)
	btn_help.pressed.connect(_on_help)
	btn_skip = PillButton.new()
	btn_skip.text = "Skip"
	btn_skip.accent = Pal.CORAL_DARK
	btn_skip.font_size = 16
	btn_skip.visible = false
	prompt_panel.add_child(btn_skip)
	btn_skip.pressed.connect(_on_skip)
	btn_restart_guided = _btn("Restart the guided board", "retry", Pal.CORAL)
	btn_restart_guided.filled = true
	btn_restart_guided.visible = false
	btn_restart_guided.pressed.connect(_on_restart_guided)
	btn_keep_going = _btn("Keep playing", "wave", Pal.SAND)
	btn_keep_going.visible = false
	btn_keep_going.pressed.connect(_on_keep_going)
	help_sheet = PoolOverlays.HelpSheet.new()
	add_child(help_sheet)
	help_sheet.close.connect(func() -> void: help_sheet.visible = false)
	help_sheet.replay.connect(func() -> void:
		help_sheet.visible = false
		help_replay.emit())
	arrival = PoolOverlays.ArrivalCard.new()
	add_child(arrival)
	arrival.keep_playing.connect(func() -> void:
		arrival.visible = false
		_update_buttons()
		_update_prompt())
	arrival.visit_reef.connect(func() -> void:
		arrival.visible = false
		open_reef_decor.emit())
	results_panel = Panel.new()
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.04, 0.2, 0.26, 0.97)
	rsb.border_color = Pal.CORAL
	rsb.set_border_width_all(3)
	rsb.set_corner_radius_all(20)
	results_panel.add_theme_stylebox_override("panel", rsb)
	results_panel.visible = false
	add_child(results_panel)
	results_title = Label.new()
	results_title.add_theme_font_size_override("font_size", 30)
	results_title.add_theme_color_override("font_color", Pal.GOLD)
	results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_panel.add_child(results_title)
	results_body = Label.new()
	results_body.add_theme_font_size_override("font_size", 18)
	results_body.add_theme_color_override("font_color", Pal.TEXT)
	results_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	results_panel.add_child(results_body)
	btn_res_retry = PillButton.new()
	btn_res_retry.accent = Pal.CORAL
	btn_res_retry.filled = true
	btn_res_retry.font_size = 20
	results_panel.add_child(btn_res_retry)
	btn_res_retry.pressed.connect(_on_trial_retry)
	btn_res_back = PillButton.new()
	btn_res_back.accent = Pal.SAND
	btn_res_back.text = "Return to the reef"
	btn_res_back.icon = "reef"
	btn_res_back.font_size = 18
	results_panel.add_child(btn_res_back)
	btn_res_back.pressed.connect(func() -> void: trial_exit.emit())
	resized.connect(_layout)

func _chip(icon: String, label: String, accent: Color) -> HudWidgets.Chip:
	var c := HudWidgets.Chip.new()
	c.icon = icon
	c.label = label
	c.accent = accent
	add_child(c)
	return c

func _btn(text: String, icon: String, accent: Color) -> PillButton:
	var b := PillButton.new()
	b.text = text
	b.icon = icon
	b.accent = accent
	add_child(b)
	return b

# --- Layout ------------------------------------------------------------------------

var _prompt_iw: float = 500.0

## The prompt text leaves room for the Skip button whenever it is shown.
func _layout_prompt() -> void:
	var skip_w: float = 74.0
	prompt_label.position = Vector2(12, 2)
	prompt_label.size = Vector2(_prompt_iw - 24.0 - ((skip_w + 6.0) if btn_skip.visible else 0.0), 54)
	btn_skip.position = Vector2(_prompt_iw - 10.0 - skip_w, 11)
	btn_skip.size = Vector2(skip_w, 36)

func _layout() -> void:
	if board_view == null:
		return
	var w: float = size.x
	var h: float = size.y
	var cw: float = minf(w, MAX_COL_W)
	var x0: float = (w - cw) * 0.5 + PAD
	var iw: float = cw - 2.0 * PAD
	var y: float = 8.0
	# row 1: home | coins | pearls | reef | motion | sound
	var small: float = 44.0
	var g: float = 6.0
	var chip_h: float = 52.0
	var fixed: float = small * 3.0 + g * 5.0 + 92.0
	var chip_w: float = (iw - fixed) * 0.5
	var x: float = x0
	btn_home.position = Vector2(x, y + 4.0)
	btn_home.size = Vector2(small, small)
	x += small + g
	chip_coins.position = Vector2(x, y)
	chip_coins.size = Vector2(chip_w, chip_h)
	x += chip_w + g
	chip_pearls.position = Vector2(x, y)
	chip_pearls.size = Vector2(chip_w, chip_h)
	x += chip_w + g
	btn_reef.position = Vector2(x, y + 4.0)
	btn_reef.size = Vector2(92, small)
	x += 92.0 + g
	btn_motion.position = Vector2(x, y + 4.0)
	btn_motion.size = Vector2(small, small)
	x += small + g
	btn_sound.position = Vector2(x, y + 4.0)
	btn_sound.size = Vector2(small, small)
	y += chip_h + 8.0
	# row 2: turn | currents
	var half: float = (iw - g) * 0.5
	chip_turn.position = Vector2(x0, y)
	chip_turn.size = Vector2(half, 48)
	chip_currents.position = Vector2(x0 + half + g, y)
	chip_currents.size = Vector2(half, 48)
	y += 48.0 + 8.0
	surge_strip.position = Vector2(x0, y)
	surge_strip.size = Vector2(iw, 52)
	y += 52.0 + 8.0
	# board
	var avail_w: float = iw - GATE_W - GAP - BoardView.TAB
	var below_min: float = 58.0 + 8.0 + 54.0 + 8.0 + 96.0 + 8.0 + 8.0
	var avail_h: float = h - y - below_min - BoardView.TAB
	var cs: float = floorf(minf(avail_w / GameConfig.COLS, avail_h / GameConfig.ROWS))
	board_view.cs = cs
	board_view.position = Vector2(x0, y)
	var bsz: Vector2 = board_view.board_pixel_size()
	gate.position = Vector2(x0 + bsz.x + GAP, y + BoardView.TAB)
	gate.size = Vector2(GATE_W, cs * GameConfig.ROWS)
	y += bsz.y + 8.0
	# prompt, action bar, reef peek
	prompt_panel.position = Vector2(x0, y)
	prompt_panel.size = Vector2(iw, 58)
	_prompt_iw = iw
	_layout_prompt()
	y += 58.0 + 8.0
	var bar_h: float = 54.0
	var slot: float = (iw - 3.0 * g) / 4.0
	btn_current.position = Vector2(x0, y)
	btn_current.size = Vector2(slot, bar_h)
	btn_dir_a.position = Vector2(x0 + (slot + g), y)
	btn_dir_a.size = Vector2(slot, bar_h)
	btn_dir_b.position = Vector2(x0 + 2.0 * (slot + g), y)
	btn_dir_b.size = Vector2(slot, bar_h)
	btn_confirm.position = Vector2(x0 + 3.0 * (slot + g), y)
	btn_confirm.size = Vector2(slot, bar_h)
	btn_tide.position = Vector2(x0 + (slot + g), y)
	btn_tide.size = Vector2(iw - (slot + g), bar_h)
	btn_help.position = Vector2(x0 + 2.0 * (slot + g), y)
	btn_help.size = Vector2(slot, bar_h)
	btn_restart_guided.position = Vector2(x0, y)
	btn_restart_guided.size = Vector2(2.0 * slot + g, bar_h)
	btn_keep_going.position = Vector2(x0 + 2.0 * (slot + g), y)
	btn_keep_going.size = Vector2(2.0 * slot + g, bar_h)
	y += bar_h + 8.0
	reef_peek.position = Vector2(x0, y)
	reef_peek.size = Vector2(iw, maxf(60.0, h - y - 8.0))
	toast.position = Vector2(x0 + 20.0, board_view.position.y + 40.0)
	toast.size = Vector2(iw - 40.0, 0)
	for b in [btn_home, btn_reef, btn_motion, btn_sound, btn_current, btn_dir_a, btn_dir_b, btn_confirm, btn_tide, btn_help, btn_restart_guided, btn_keep_going]:
		(b as PillButton).font_size = 19
	btn_tide.font_size = 18
	btn_restart_guided.font_size = 17
	btn_keep_going.font_size = 17
	# Trial mode: no balances, Reef Gate or reef strip; Hint / Retry take the strip's place
	var sb_mode: bool = is_sandbox()
	gate.visible = not trial_mode
	reef_peek.visible = not sb_mode
	chip_pearls.visible = not sb_mode
	btn_reef.visible = not sb_mode
	btn_retry.visible = sb_mode
	if sb_mode:
		chip_coins.size = Vector2(chip_w * 2.0 + g, chip_h)
		btn_home.icon = "x"
		var strip: Rect2 = Rect2(reef_peek.position, reef_peek.size)
		var bh: float = minf(64.0, strip.size.y)
		btn_hint.position = strip.position
		btn_hint.size = Vector2((strip.size.x - 8.0) * 0.5, bh)
		btn_retry.position = strip.position + Vector2((strip.size.x + 8.0) * 0.5, 0)
		btn_retry.size = Vector2((strip.size.x - 8.0) * 0.5, bh)
		btn_hint.font_size = 22
		btn_retry.font_size = 22
	else:
		btn_home.icon = "home"
		btn_hint.position = Vector2(x0 + (slot + g), y - bar_h - 8.0)
		btn_hint.size = Vector2(slot, bar_h)
		btn_hint.font_size = 19
	var ow: float = iw * 0.94
	var oh: float = minf(380.0, board_view.size.y - 20.0)
	for ov in [help_sheet, arrival]:
		(ov as Control).size = Vector2(ow, oh)
		(ov as Control).position = Vector2((w - ow) * 0.5, board_view.position.y + 14.0)
	help_sheet.max_h = board_view.size.y - 28.0
	arrival.max_h = board_view.size.y - 28.0
	var rw: float = iw * 0.92
	results_panel.size = Vector2(rw, 250)
	results_panel.position = Vector2((w - rw) * 0.5, board_view.position.y + 90.0)
	results_title.position = Vector2(10, 16)
	results_title.size = Vector2(rw - 20.0, 40)
	results_body.position = Vector2(20, 64)
	results_body.size = Vector2(rw - 40.0, 80)
	btn_res_retry.position = Vector2(20, 152)
	btn_res_retry.size = Vector2(rw - 40.0, 40)
	btn_res_back.position = Vector2(20, 198)
	btn_res_back.size = Vector2(rw - 40.0, 40)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if board_view != null and visible and not busy:
			leave()                 # a half-made selection or Current preview is dropped, not kept stale
			_update_buttons()
			_update_prompt()
	if what == NOTIFICATION_RESIZED:
		_layout()
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible and board_view != null:
		_layout()

# --- Entering the screen --------------------------------------------------------------

func set_trial(t: TideTrial) -> void:
	trial_mode = true
	trial = t
	session = t.session
	board_view.session = session
	board_view.gate = null                    # no Reef Gate in the Trial
	_layout()

func set_help(s: GameSession) -> void:
	help_mode = true
	session = s
	board_view.session = s
	_layout()

func _enter_trial() -> void:
	if trial_mode:
		session = trial.session
	board_view.session = session
	board_view.clear_selection()
	cur_mode = false
	board_view.mode_current = false
	_clear_line()
	board_view.hint_line = {}
	board_view.sync(session.run.board)
	results_panel.visible = false
	busy = false
	board_view.interactive = true
	_refresh_all()

## Called when the player leaves this screen (Back, Reef, Home): nothing half-finished is left
## behind: no stale selection, Current preview, guidance or open sheet.
func leave() -> void:
	if board_view == null:
		return
	board_view.cancel_gesture()
	board_view.clear_selection()
	if cur_mode:
		_exit_current_mode()
	board_view.guide = {}
	board_view.hint_line = {}
	help_sheet.visible = false
	arrival.visible = false
	_skip_armed = false

func enter() -> void:
	leave()
	_layout()
	_apply_motion_setting()
	if trial_mode or help_mode or calm_mode:
		_enter_trial()
		return
	board_view.session = session
	cur_mode = false
	_clear_line()
	board_view.clear_selection()
	board_view.sync(session.run.board)
	_shown_coins = session.profile.coins
	_shown_pearls = session.profile.pearls
	_refresh_all()
	_recovery_version = -1
	_check_recovery()
	_update_buttons()
	_update_prompt()
	board_view.interactive = true
	busy = false
	if session.run.status == RunState.FLOODED:
		run_flooded.emit()
		return
	if not session.run.pending_surge.is_empty():
		_run_surge_sequence()

func _process(delta: float) -> void:
	if visible and session != null and session.run != null and session.run.status == RunState.ACTIVE:
		session.tick(delta)
		_advance_tip_scan()
	if reef_peek != null:
		reef_peek.paused = busy or not visible          # the strip is decoration: rest while the pool animates

## Called by Main once a second after passive income was settled in memory.
func on_income_tick() -> void:
	if trial_mode or not visible or busy or _pearls_in_flight > 0 or session == null:
		return
	if _shown_coins != session.profile.coins:
		_shown_coins = session.profile.coins
		chip_coins.value = fmt_hud(_shown_coins)
	var rate: int = int(round(session.income_rate()))
	if rate != _income_label_rate:
		_income_label_rate = rate
		chip_coins.label = "Coins  +%d/h" % rate if rate > 0 else "Coins"
		chip_coins.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE and visible and not busy:
		if cur_mode:
			_exit_current_mode()
		elif board_view.selected >= 0:
			board_view.clear_selection()
			_update_prompt()
		get_viewport().set_input_as_handled()

# --- HUD -----------------------------------------------------------------------------

func _refresh_all() -> void:
	_state_version += 1
	_check_recovery()
	if trial_mode:
		_refresh_hud()
		_update_buttons()
		_update_prompt()
		return
	if _pearls_in_flight == 0:
		_shown_coins = session.profile.coins
		_shown_pearls = session.profile.pearls
	_refresh_hud()
	_update_buttons()
	_update_prompt()
	var sig: String = "%d|%d" % [session.profile.residents.size(), session.profile.decorations.size()]
	if sig != _reef_sig:        # only rebuild the reef strip when its content really changed
		_reef_sig = sig
		reef_peek.set_residents(session.profile.residents)
		reef_peek.set_decorations(session.profile.decorations)
		reef_peek.caption = "Your reef · %d resident%s · tap to visit" % [session.profile.residents.size(), "" if session.profile.residents.size() == 1 else "s"]
	gate.residents = session.profile.residents.size()

func _refresh_hud() -> void:
	if trial_mode:
		chip_coins.icon = "tide"
		chip_coins.label = "Moves left"
		chip_coins.value = "%d / %d" % [trial.moves_left, GameConfig.TRIAL_BUDGET]
		chip_turn.label = "Attempt"
		chip_turn.value = str(trial.attempts)
		chip_currents.value = "x%d" % session.run.currents
		surge_strip.custom_text = trial.goal_text()
		surge_strip.incoming = []
		surge_strip.refresh()
		return
	chip_coins.value = fmt_hud(_shown_coins)
	chip_pearls.value = fmt_hud(_shown_pearls)
	var run: RunState = session.run
	chip_turn.value = str(run.turn)
	chip_currents.value = "x%d" % run.currents
	if help_mode or calm_mode:
		chip_coins.icon = "goal" if help_mode else "wave"
		chip_coins.label = "Guided practice" if help_mode else "Calm Pool"
		chip_coins.value = "No payout" if help_mode else "No rewards"
	surge_strip.cadence = run.cadence
	surge_strip.turns_left = run.turns_until_surge()
	surge_strip.incoming = run.pending_surge
	surge_strip.refresh()

## Compact form for the HUD so very large balances still fit a chip.
static func fmt_hud(n: int) -> String:
	if n >= 1000000000:
		return ("%.2f" % (float(n) / 1000000000.0)).rstrip("0").rstrip(".") + "B"
	if n >= 1000000:
		return ("%.2f" % (float(n) / 1000000.0)).rstrip("0").rstrip(".") + "M"
	return _fmt(n)

static func _fmt(n: int) -> String:
	var s: String = str(n)
	var out: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out

func _apply_motion_setting() -> void:
	reduced_motion = bool(settings_session.profile.settings.get("reduced_motion", false))
	board_view.reduced_motion = reduced_motion
	board_view.anim_speed = anim_speed
	gate.reduced_motion = reduced_motion
	reef_peek.reduced_motion = reduced_motion
	surge_strip.reduced_motion = reduced_motion
	btn_motion.icon = "motion_off" if reduced_motion else "motion"
	btn_motion.toggled = reduced_motion
	var snd: bool = bool(settings_session.profile.settings.get("sound", true))
	sfx.enabled = snd
	Haptics.enabled = bool(settings_session.profile.settings.get("haptics", true))
	Haptics.reduced_motion = reduced_motion
	btn_sound.icon = "sound" if snd else "sound_off"

func _toggle_motion() -> void:
	settings_session.set_setting("reduced_motion", not bool(settings_session.profile.settings.get("reduced_motion", false)))
	_apply_motion_setting()
	toast.show_text("Reduced motion %s" % ("on" if reduced_motion else "off"), 1.2)

func _toggle_sound() -> void:
	settings_session.set_setting("sound", not bool(settings_session.profile.settings.get("sound", true)))
	_apply_motion_setting()

func _update_buttons() -> void:
	var run: RunState = session.run
	var playing: bool = run.status == RunState.ACTIVE
	var stuck: bool = playing and not busy and _is_stuck()
	var sb_mode: bool = is_sandbox()
	var guided: bool = not sb_mode and run.tutorial
	btn_skip.visible = guided
	btn_skip.text = "Sure?" if _skip_armed else "Skip"
	_layout_prompt()
	var recov: bool = _recovery and not cur_mode
	btn_restart_guided.visible = recov
	btn_keep_going.visible = recov
	btn_hint.visible = (sb_mode or (not cur_mode and not stuck)) and not recov
	btn_hint.enabled = playing and not busy
	btn_help.visible = not sb_mode and not cur_mode and not stuck and not recov
	btn_tide.visible = stuck and not cur_mode and not recov
	btn_current.visible = (not stuck or cur_mode) and not recov
	btn_current.enabled = playing and not busy       # tappable even when spent: it explains why not
	if cur_mode:
		btn_current.text = "Cancel"
		btn_current.icon = "x"
		btn_current.accent = Pal.RED
		btn_current.toggled = true
	else:
		btn_current.text = "Current x%d" % run.currents
		btn_current.icon = "wave"
		btn_current.accent = Pal.CURRENT if run.currents > 0 else Pal.TEXT_DIM.darkened(0.2)    # spent: dim
		btn_current.toggled = false
	var have_line: bool = cur_mode and cur_axis >= 0
	btn_dir_a.visible = have_line
	btn_dir_b.visible = have_line
	btn_confirm.visible = have_line
	if have_line:
		var is_row: bool = cur_axis == Board.AXIS_ROW
		btn_dir_a.icon = "left" if is_row else "up"
		btn_dir_b.icon = "right" if is_row else "down"
		btn_dir_a.text = "Left" if is_row else "Up"
		btn_dir_b.text = "Right" if is_row else "Down"
		btn_dir_a.toggled = cur_dir == -1
		btn_dir_b.toggled = cur_dir == 1
		btn_confirm.enabled = cur_dir != 0
		var info: Dictionary = _preview_info if cur_dir != 0 else {}
		btn_confirm.text = "Free" if (cur_dir != 0 and not bool(info.get("changes", true))) else "Shift"
		btn_confirm.enabled = cur_dir != 0
	gate.hint = false

# --- Prompt ----------------------------------------------------------------------------

func _line_name(axis: int, index: int) -> String:
	return ("Row %d" % (index + 1)) if axis == Board.AXIS_ROW else ("Column %d" % (index + 1))

func _dir_name(axis: int, dir: int) -> String:
	if axis == Board.AXIS_ROW:
		return "right" if dir > 0 else "left"
	return "down" if dir > 0 else "up"

func _update_prompt() -> void:
	if session == null or session.run == null:
		return
	var run: RunState = session.run
	var b: Board = run.board
	board_view.hint_cells = PackedInt32Array()
	board_view.hint_line = {}
	board_view.guide = {}
	gate.hint = false
	_tutorial_prompt = false
	var text: String = ""
	if _recovery and not cur_mode:
		prompt_label.text = "Stuck? Restart the guided board. Banked rewards stay; practice pays nothing."
		board_view._over.queue_redraw()
		board_view._under.queue_redraw()
		return
	if trial_mode and not cur_mode and board_view.selected < 0:
		if trial.status == TideTrial.WON:
			text = "Cleared! The wrap made your three in a row."
		elif trial.status == TideTrial.LOST:
			text = "Out of moves. Retry is free."
		else:
			text = "Goal: wrap a Current round the edge to make three in a row. %d move%s left." % [trial.moves_left, "" if trial.moves_left == 1 else "s"]
		prompt_label.text = text
		board_view.hint_line = board_view.hint_line
		board_view._over.queue_redraw()
		board_view._under.queue_redraw()
		return
	if run.status != RunState.ACTIVE:
		text = "The pool has flooded."
	elif not run.pending_surge.is_empty():
		text = "Surge incoming! Watch the glowing cells."
	elif cur_mode:
		if cur_axis < 0:
			text = "Current: tap a row or column tab, or drag along a line. The edge wraps round."
		elif cur_dir == 0:
			text = "%s chosen. Pick a direction." % _line_name(cur_axis, cur_index)
		else:
			var info: Dictionary = _preview_info
			var head: String = "%s %s: " % [_line_name(cur_axis, cur_index), _dir_name(cur_axis, cur_dir)]
			if not bool(info["changes"]):
				text = head + "nothing changes, so it is free."
			elif int(info["merges"]) > 0:
				text = head + "makes a merge! (reaches tier %d) Tap Shift." % int(info["best_tier"])
			else:
				text = head + "no merge. Tap Shift to commit."
	elif board_view.selected >= 0:
		var code: int = b.code_at(board_view.selected)
		text = "Tap a glowing match to merge, or a dot to slide there."
		if Creature.tier_of(code) >= GameConfig.RELEASE_MIN_TIER:
			text = "Tier %d! Drag it to the Reef Gate, or tap the gate." % Creature.tier_of(code)
			gate.hint = true
	elif _is_stuck():
		text = "No moves left. Advance the tide to the next Surge."
	elif run.tutorial:
		var tg: Dictionary = _tutorial_guide()
		text = String(tg["text"])
		board_view.guide = tg.get("guide", {})
		board_view.hint_line = tg.get("line", {})
		gate.hint = bool(tg.get("gate", false))
		_tutorial_prompt = true
	else:
		var hint: Dictionary = _cached_hint()
		text = String(hint["text"])
		board_view.hint_cells = hint["cells"]
		board_view.hint_line = hint["line"]
		gate.hint = bool(hint["gate"])
	prompt_label.text = text
	board_view._over.queue_redraw()
	board_view._under.queue_redraw()

func _cached_hint() -> Dictionary:
	if _hint_cache_version != _state_version:
		_hint_cache = _coach_hint()
		_hint_cache_version = _state_version
		_tip_pos = 0
		_tip_done = session.run.currents <= 0 or not String(_hint_cache["text"]).begins_with("Merge matching")
	return _hint_cache

## The Current tip ("Row 3 left would make a line") needs a preview of every row/column
## direction. That costs ~3 ms in one go, so it is spread over a few frames after an action.
const TIP_PER_FRAME: int = 4

func _advance_tip_scan() -> void:
	if trial_mode or _tip_done or busy or cur_mode or board_view.selected >= 0 or session.run == null or session.run.status != RunState.ACTIVE:
		return
	if _hint_cache_version != _state_version:
		return
	var total: int = (GameConfig.ROWS + GameConfig.COLS) * 2
	for n in TIP_PER_FRAME:
		if _tip_pos >= total:
			_tip_done = true
			return
		var k: int = _tip_pos
		_tip_pos += 1
		var axis: int = Board.AXIS_ROW if k < GameConfig.ROWS * 2 else Board.AXIS_COL
		var kk: int = k if axis == Board.AXIS_ROW else k - GameConfig.ROWS * 2
		var idx: int = int(kk / 2.0)
		var dir: int = -1 if kk % 2 == 0 else 1
		var inf: Dictionary = session.preview_current(axis, idx, dir)
		if bool(inf["changes"]) and int(inf["merges"]) > 0:
			_hint_cache["text"] = "Tip: %s %s would make a line. Try a Current!" % [_line_name(axis, idx), _dir_name(axis, dir)]
			_hint_cache["line"] = {"axis": axis, "index": idx}
			_tip_done = true
			_update_prompt()
			return

func _is_stuck() -> bool:
	if trial_mode:
		return false
	if _stuck_cache_version != _state_version:
		_stuck_cache = session.is_stuck()
		_stuck_cache_version = _state_version
	return _stuck_cache

## Short, contextual prompts. The first run teaches the three key actions.
func _coach_hint() -> Dictionary:
	var run: RunState = session.run
	var b: Board = run.board
	var out: Dictionary = {"text": "", "cells": PackedInt32Array(), "line": {}, "gate": false}
	# 1. a creature that can use the Reef Gate
	for i in b.cells.size():
		var c: int = b.code_at(i)
		if c != 0 and Creature.tier_of(c) >= GameConfig.RELEASE_MIN_TIER:
			out["text"] = "Tier %d! Send it through the Reef Gate to keep it forever." % Creature.tier_of(c)
			if Visitor.has_request(session.profile) and Creature.family_of(c) == int(session.profile.visitor["request"]["family"]) and bool(session.profile.visitor["request"]["created"]):
				out["text"] = "Release this one for the Lantern Ray! Drag it to the Reef Gate."
			out["cells"] = PackedInt32Array([i])
			out["gate"] = true
			return out
	if run.tutorial:
		var s1: int = Board.idx(4, 1)
		var s2: int = Board.idx(4, 2)
		if run.turn == 0 and b.code_at(s1) == Creature.make(1, 1) and b.code_at(s2) == Creature.make(1, 1):
			out["text"] = "1 · Merge the glowing shrimp: tap one, then tap its twin."
			out["cells"] = PackedInt32Array([s1, s2])
			return out
		if run.currents > 0:
			var info: Dictionary = session.preview_current(Board.AXIS_ROW, 1, -1)
			if bool(info["changes"]) and int(info["best_tier"]) >= 4:
				out["text"] = "2 · Spend a Current: slide row 2 left. The edge starfish wraps round into a line!"
				out["line"] = {"axis": Board.AXIS_ROW, "index": 1}
				return out
	# (the "a Current would make a merge right now" tip is found incrementally, see _process)
	out["text"] = "Merge matching pairs or slide into empty cells. A Surge lands every 3rd turn."
	if Visitor.has_request(session.profile):
		var req: Dictionary = session.profile.visitor["request"]
		if not bool(req["created"]):
			out["text"] = "Lantern Ray wants a tier %d+ %s. Merge your way up!" % [GameConfig.VISITOR_REQUEST_MIN_TIER, String(Creature.FAMILY_NAMES[int(req["family"])])]
	return out

## Guided-start prompts: short, one per step, with the guidance drawn on the board itself.
func _tutorial_guide() -> Dictionary:
	if _tg_version == _state_version and not _tg_cache.is_empty():
		return _tg_cache
	_tg_cache = _tutorial_guide_uncached()
	_tg_version = _state_version
	return _tg_cache

func _tutorial_guide_uncached() -> Dictionary:
	var run: RunState = session.run
	var step: int = Tutorial.step_of(run.tut_flags)
	var sug: Dictionary = Hints.suggest(session)
	var out: Dictionary = {"text": "", "guide": {}, "line": {}, "gate": false}
	match step:
		0:
			out["text"] = "Drag a creature onto its twin. Or tap one, then the other."
			if sug["cells"].size() == 2:
				out["guide"] = {"cells": sug["cells"], "from": int(sug["src"]), "to": int(sug["dst"]), "label": "Drag onto its twin", "style": "coach"}
		1:
			out["text"] = "Spend a Current: tap a row tab, pick a direction, check the preview, then Shift."
			var bp: Dictionary = _best_current_for_guide()
			if not bp.is_empty():
				out["line"] = {"axis": int(bp["axis"]), "index": int(bp["index"])}
		2:
			out["text"] = "Make another merge. Every 3rd turn a Surge lands, so watch the marked cells."
			if sug["kind"] in ["merge", "chain", "line"] and sug["cells"].size() == 2:
				out["guide"] = {"cells": sug["cells"], "from": int(sug["src"]), "to": int(sug["dst"]), "label": "Merge these", "style": "coach"}
		3:
			out["text"] = "Drag your tier 4 through the Reef Gate, or tap it and then the gate."
			if sug["kind"] == "release":
				out["guide"] = {"cells": sug["cells"], "from": int(sug["src"]), "to_gate": true, "label": "Send it to the gate", "style": "coach"}
				out["gate"] = true
	return out

func _best_current_for_guide() -> Dictionary:
	var run: RunState = session.run
	if run.currents <= 0:
		return {}
	var best: Dictionary = {}
	var best_score: int = -1
	for axis in [Board.AXIS_ROW, Board.AXIS_COL]:
		for idx in (GameConfig.ROWS if axis == Board.AXIS_ROW else GameConfig.COLS):
			for dir in [-1, 1]:
				var pv: Dictionary = session.preview_current(axis, idx, dir)
				if bool(pv["changes"]):
					var score: int = int(pv["merges"]) * 10 + int(pv["best_tier"])
					if score > best_score:
						best_score = score
						best = {"axis": axis, "index": idx, "dir": dir}
	return best

## The optional Hint: marks one legal, useful action. Never changes the board or random state.
func _on_hint() -> void:
	if busy or session == null or session.run == null:
		return
	if trial_mode and trial != null:
		_on_trial_hint()
		return
	if help_sheet.visible or arrival.visible:
		return
	var h: Dictionary = Hints.suggest(session)
	board_view.clear_selection()
	if cur_mode:
		_exit_current_mode()
	board_view.hint_line = {}
	board_view.guide = {}
	match String(h["kind"]):
		"release":
			board_view.guide = {"cells": h["cells"], "from": int(h["src"]), "to_gate": true, "label": "Release", "style": "hint"}
			gate.hint = true
		"chain", "line", "merge":
			board_view.guide = {"cells": h["cells"], "from": int(h["src"]), "to": int(h["dst"]), "label": "Merge", "style": "hint"}
		"slide":
			board_view.guide = {"cells": h["cells"], "from": int(h["src"]), "to": int(h["dst"]), "label": "Slide", "style": "hint"}
		"current":
			var c: Dictionary = h["current"]
			board_view.hint_line = {"axis": int(c["axis"]), "index": int(c["index"])}
		"tide":
			pass
	prompt_label.text = String(h["text"])
	toast.hide_now()
	if sfx != null:
		sfx.play("select")
	board_view._over.queue_redraw()
	board_view._under.queue_redraw()

func _on_help() -> void:
	if busy:
		return
	help_sheet.open()

func _on_skip() -> void:
	if busy or not session.run.tutorial:
		return
	if not _skip_armed:
		_skip_armed = true                       # two taps: a stray tap cannot throw the tutorial away
		btn_skip.text = "Sure?"
		var t: Tween = create_tween()
		t.tween_interval(2.5)
		t.tween_callback(func() -> void:
			_skip_armed = false
			btn_skip.text = "Skip")
		toast.show_text("Tap Skip again to leave the guided start. Rewards you earned are kept.", 2.4)
		return
	_skip_armed = false
	session.skip_tutorial()
	open_home.emit()

func _on_restart_guided() -> void:
	if busy:
		return
	session.restart_tutorial()
	_recovery = false
	enter_after_restart()
	toast.show_text("Guided board restarted. Practice earns nothing until you finish; your rewards are safe.", 3.2)

func enter_after_restart() -> void:
	cur_mode = false
	board_view.mode_current = false
	_clear_line()
	board_view.clear_selection()
	board_view.sync(session.run.board)
	_refresh_all()
	busy = false
	board_view.interactive = true

func _on_keep_going() -> void:
	_recovery = false
	_recovery_version = _state_version
	_update_buttons()
	_update_prompt()

## After each committed action in the guided run: if the current step can no longer be done,
## offer the restart instead of leaving the player stranded.
func _check_recovery() -> void:
	if is_sandbox() or not session.run.tutorial or session.run.status != RunState.ACTIVE:
		_recovery = false
		return
	if _recovery_version == _state_version:
		return
	_recovery = not Tutorial.goal_reachable(session) and session.run.pending_surge.is_empty()

# --- Toast / feedback --------------------------------------------------------------------

func _reject(res: Dictionary, shake_cell: int = -1) -> void:
	toast.show_kind(String(res["reason"]), String(res.get("kind", "invalid")), 1.8)
	if shake_cell >= 0:
		board_view.shake(shake_cell)
	elif sfx != null:
		sfx.play("reject")

# --- Actions -----------------------------------------------------------------------------

func _on_drop(src: int, dst: int) -> void:
	if busy:
		return
	var res: Dictionary = session.try_drop(src, dst)
	if not bool(res["ok"]):
		_reject(res, src)
		return
	board_view.clear_selection()
	await _play_result(res)

func _on_gate_tapped() -> void:
	if busy or cur_mode:
		return
	if board_view.selected >= 0:
		_request_release(board_view.selected)
	else:
		toast.show_text("Select a tier %d+ creature, then tap the Reef Gate." % GameConfig.RELEASE_MIN_TIER, 2.0)
		gate.pulse()

func _request_release(src: int) -> void:
	if busy:
		return
	var res: Dictionary = session.try_release(src)
	if not bool(res["ok"]):
		_reject(res, src)
		return
	board_view.clear_selection()
	await _play_result(res)

func _on_tide() -> void:
	if busy:
		return
	var res: Dictionary = session.advance_tide()
	if not bool(res["ok"]):
		_reject(res)
		return
	await _play_result(res)

## Replay a resolved action; then Surge preview / flood if one follows.
func _play_result(res: Dictionary) -> void:
	busy = true
	board_view.interactive = false
	_update_buttons()
	if bool(res["turn_used"]) and cur_mode:
		_exit_current_mode()
	var trial_done: bool = false
	if trial_mode:
		trial.evaluate(res)                       # resolve once (moves, win/lose), then play the feedback
		trial_done = trial.status != TideTrial.PLAYING
	var release_code: int = 0
	for ev in res["events"]:
		if String(ev["t"]) == "release":
			release_code = int(ev["code"])
	await board_view.play_events(res["events"], session.run.board)
	_refresh_all()
	if trial_mode:
		if trial_done:
			_show_trial_result()
			return
		busy = false
		board_view.interactive = true
		_update_buttons()
		_update_prompt()
		return
	if help_mode and bool(res.get("tutorial_done", false)):
		_show_help_done()
		return
	_announce_progress(res)
	if bool(res.get("tutorial_done", false)) and not help_mode:
		_show_arrival(release_code)
	else:
		_check_recovery()
		_update_buttons()
		_update_prompt()
	if bool(res["flood"]):
		await _run_flood_sequence()
		return
	if not session.run.pending_surge.is_empty():
		await _run_surge_sequence()
		return
	busy = false
	board_view.interactive = true
	_update_buttons()
	_update_prompt()

## Goals and Lantern Ray progress arrive with committed actions; say so once the animation is done.
func _announce_progress(res: Dictionary) -> void:
	var lines: PackedStringArray = PackedStringArray()
	for g in res.get("goals_done", []):
		var rw: String = "+%d coins" % int(g["coins"]) + (" +%d pearl%s" % [int(g["pearls"]), "" if int(g["pearls"]) == 1 else "s"] if int(g["pearls"]) > 0 else "")
		lines.append("Goal complete: %s  %s" % [g["label"], rw])
	if bool(res.get("visitor_created", false)):
		lines.append("Lantern Ray: now release it through the Reef Gate!")
	if bool(res.get("visitor_complete", false)):
		lines.append("The Lantern Ray joins your reef!")
		if sfx != null:
			sfx.pop(4)
	if not lines.is_empty():
		toast.show_text("\n".join(lines), 3.2)
		chip_coins.punch_now()

func _run_surge_sequence() -> void:
	busy = true
	board_view.interactive = false
	toast.visible = false
	var items: Array = session.run.pending_surge
	board_view.surge_preview = items
	surge_strip.incoming = items
	surge_strip.refresh()
	_update_buttons()
	_update_prompt()
	Haptics.surge()
	if sfx != null:
		sfx.play("surge")
	var dur: float = GameConfig.T_SURGE_PREVIEW_REDUCED if reduced_motion else GameConfig.T_SURGE_PREVIEW
	await get_tree().create_timer(dur / anim_speed, true, false, true).timeout
	var lr: Dictionary = session.land_surge()
	board_view.surge_preview = []
	await board_view.play_land(lr["events"])
	board_view.sync(session.run.board)
	_refresh_all()
	busy = false
	board_view.interactive = true
	_update_buttons()
	_update_prompt()

func _run_flood_sequence() -> void:
	toast.visible = false
	var info: Dictionary = session.run.flood_info
	board_view.flood_flash = true
	surge_strip.danger = true
	surge_strip.message = "Only %d free cell%s; the wave needs %d" % [int(info.get("free", 0)), "" if int(info.get("free", 0)) == 1 else "s", int(info.get("need", 3))]
	surge_strip.refresh()
	prompt_label.text = "The wave cannot fit! The pool floods. Your rewards are safe."
	Haptics.flood()
	if sfx != null:
		sfx.play("flood")
	await get_tree().create_timer(GameConfig.T_FLOOD_NOTICE / anim_speed, true, false, true).timeout
	board_view.flood_flash = false
	surge_strip.danger = false
	surge_strip.message = ""
	busy = false
	run_flooded.emit()

# --- Current mode -------------------------------------------------------------------------

func _on_current_button() -> void:
	if busy:
		return
	if cur_mode:
		_exit_current_mode()
	else:
		if session.run.currents <= 0:
			toast.show_kind("No Currents left. A chain earns one back.", "nocurrent", 1.8)
			if sfx != null:
				sfx.play("reject")
			return
		cur_mode = true
		toast.visible = false
		board_view.clear_selection()
		board_view.mode_current = true
		_clear_line()
	_update_buttons()
	_update_prompt()

func _exit_current_mode() -> void:
	cur_mode = false
	board_view.mode_current = false
	_clear_line()
	_update_buttons()
	_update_prompt()

func _clear_line() -> void:
	_preview_info = {}
	cur_axis = -1
	cur_index = -1
	cur_dir = 0
	board_view.line_preview = {}
	board_view._over.queue_redraw()
	board_view._under.queue_redraw()

func _apply_line_preview() -> void:
	_preview_info = {}
	if cur_axis >= 0 and cur_dir != 0:
		_preview_info = session.preview_current(cur_axis, cur_index, cur_dir)   # the real Current rules, once
	if cur_axis < 0:
		board_view.line_preview = {}
	else:
		board_view.line_preview = {"axis": cur_axis, "index": cur_index, "dir": cur_dir, "info": _preview_info}
	board_view._over.queue_redraw()
	board_view._under.queue_redraw()
	_update_buttons()
	_update_prompt()

func _on_line_picked(axis: int, index: int) -> void:
	if busy:
		return
	if not cur_mode:
		if session.run.currents <= 0:
			toast.show_kind("No Currents left. A chain earns one back.", "nocurrent", 1.8)
			return
		cur_mode = true
		toast.visible = false
		board_view.clear_selection()
		board_view.mode_current = true
		_clear_line()
	if cur_axis == axis and cur_index == index:
		_clear_line()
		_update_buttons()
		_update_prompt()
		return
	cur_axis = axis
	cur_index = index
	cur_dir = 0
	if sfx != null:
		sfx.play("select")
	_apply_line_preview()

func _on_line_dragged(axis: int, index: int, dir: int) -> void:
	if busy:
		return
	cur_axis = axis
	cur_index = index
	cur_dir = dir
	_apply_line_preview()

func _set_dir(dir: int) -> void:
	if busy or cur_axis < 0:
		return
	cur_dir = dir
	_apply_line_preview()

func _on_confirm() -> void:
	if busy or cur_axis < 0 or cur_dir == 0:
		return
	var res: Dictionary = session.try_current(cur_axis, cur_index, cur_dir)
	if not bool(res["ok"]):
		_reject(res)
		return
	if bool(res["free"]):
		toast.show_text("Nothing would change, so it is free. Pick another line.", 1.8)
		return
	await _play_result(res)

# --- Rewards FX ------------------------------------------------------------------------------

func _on_reward(global_pos: Vector2, coins: int, pearls: int, _step: int, _tier: int) -> void:
	if help_mode or calm_mode:
		return                       # practice boards show no balances, so there is nothing to fly to
	if reduced_motion:
		_pearl_arrived(coins, pearls)
		return
	_pearls_in_flight += 1
	var pearl := Control.new()
	pearl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pearl.size = Vector2(22, 22)
	pearl.draw.connect(func() -> void: PillButton.draw_icon(pearl, "pearl", Vector2(11, 11), 20.0, Color.WHITE))
	fx_layer.add_child(pearl)
	var start: Vector2 = fx_layer.get_global_transform().affine_inverse() * global_pos
	var target: Vector2 = fx_layer.get_global_transform().affine_inverse() * chip_pearls.icon_global_center()
	var ctrl: Vector2 = Vector2((start.x + target.x) * 0.5 + 60.0, minf(start.y, target.y) - 40.0)
	pearl.position = start - Vector2(11, 11)
	var tw: Tween = create_tween()
	tw.tween_method(func(t: float) -> void:
		var a: Vector2 = start.lerp(ctrl, t)
		var b2: Vector2 = ctrl.lerp(target, t)
		pearl.position = a.lerp(b2, t) - Vector2(11, 11)
		pearl.scale = Vector2.ONE * (1.0 - 0.25 * t), 0.0, 1.0, GameConfig.T_PEARL_FLIGHT / anim_speed).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		pearl.queue_free()
		_pearl_arrived(coins, pearls, true))

func _pearl_arrived(coins: int, pearls: int, flew: bool = false) -> void:
	if flew:
		_pearls_in_flight = maxi(0, _pearls_in_flight - 1)
	_shown_coins += coins
	_shown_pearls += pearls
	if _pearls_in_flight == 0 and session != null:
		_shown_coins = session.profile.coins
		_shown_pearls = session.profile.pearls
	chip_coins.value = fmt_hud(_shown_coins)
	chip_pearls.value = fmt_hud(_shown_pearls)
	chip_pearls.punch_now()
	chip_coins.punch_now()

func _on_chain_cue(step: int, _pos: Vector2) -> void:
	chain_label.text = "CHAIN  %s" % Rewards.multiplier_label(step)
	chain_label.visible = true
	chain_label.reset_size()
	var c: Vector2 = fx_layer.get_global_transform().affine_inverse() * (board_view.get_global_transform() * (board_view.board_pixel_size() * 0.5))
	chain_label.position = c - chain_label.size * 0.5 - Vector2(0, 30)
	chain_label.pivot_offset = chain_label.size * 0.5
	chain_label.modulate.a = 1.0
	var tw: Tween = create_tween()
	if reduced_motion:
		chain_label.scale = Vector2.ONE
		tw.tween_interval(0.7 / anim_speed)
	else:
		chain_label.scale = Vector2(0.6, 0.6)
		tw.tween_property(chain_label, "scale", Vector2.ONE * (1.0 + 0.1 * float(step)), 0.18 / anim_speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(chain_label, "position:y", chain_label.position.y - 30.0, 0.5 / anim_speed)
	tw.tween_property(chain_label, "modulate:a", 0.0, 0.25 / anim_speed)
	tw.tween_callback(func() -> void: chain_label.visible = false)


# --- Tide Trial ---------------------------------------------------------------------------------

func _on_trial_hint() -> void:
	if busy or not trial_mode or trial.status != TideTrial.PLAYING:
		return
	var h: Dictionary = trial.hint()
	board_view.hint_line = {"axis": int(h["axis"]), "index": int(h["index"])}
	board_view._under.queue_redraw()
	board_view._over.queue_redraw()
	toast.show_text("Hint: slide row %d to the LEFT. The edge piece wraps round to the far end." % (int(h["index"]) + 1), 3.2)
	if sfx != null:
		sfx.play("select")

func _on_trial_retry() -> void:
	if help_mode:
		session = GameSession.new_tutorial_sandbox()
		board_view.session = session
		_enter_trial()
		toast.hide_now()
		return
	if not trial_mode or (busy and not results_panel.visible):
		return
	trial.new_attempt()
	_enter_trial()
	toast.hide_now()

func _show_trial_result() -> void:
	board_view.interactive = false
	var won: bool = trial.status == TideTrial.WON
	results_title.text = "Cleared!" if won else "Out of moves"
	var body: String = ""
	if won:
		body = "A wrapped Current made your three in a row."
		if claim_reward.is_valid():
			var r: Dictionary = claim_reward.call()
			if bool(r.get("first", false)):
				body += "\nFirst clear reward: +%d coins, +%d pearls." % [int(r["coins"]), int(r["pearls"])]
			else:
				body += "\n(The first-clear reward is already yours.)"
		btn_res_retry.text = "Play again"
	else:
		body = "Hint: shift row 3 left, so the edge piece wraps round. Retries are free."
		btn_res_retry.text = "Try again"
	btn_res_retry.icon = "retry"
	results_body.text = body
	results_panel.visible = true
	if sfx != null:
		sfx.pop(4 if won else 0)
	if won:
		Haptics.release()


# --- First release: arrival; Help practice completion -------------------------------------------

func _show_arrival(code: int) -> void:
	var rate: float = session.income_rate()
	var decor: String = ""
	var cheapest: Dictionary = GameConfig.DECORATIONS[0]
	if session.profile.coins >= int(cheapest["price"]):
		decor = "You can afford a %s (%d coins). Visit the reef to place it." % [cheapest["name"], int(cheapest["price"])]
	toast.hide_now()
	arrival.open(code, rate, decor, reduced_motion)
	if sfx != null:
		sfx.pop(4)
	Haptics.release()
	busy = false
	board_view.interactive = true

func _show_help_done() -> void:
	board_view.interactive = false
	results_title.text = "That is the whole loop!"
	results_body.text = "Merge, use a Current, read the Surge, release a tier 4+. Practice pays nothing; your real pool is untouched."
	btn_res_retry.text = "Practice again"
	btn_res_retry.icon = "retry"
	results_panel.visible = true
	if sfx != null:
		sfx.pop(4)

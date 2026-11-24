extends Control
## Screen router. Command line (after `--`):
##   --save=NAME     use user://NAME.json instead of the default save
##   --fresh         delete that save first
##   --seed=N        base seed for runs (repeatable playtests)
##   --speed=X       animation speed multiplier (dev)
##   --playtest=NAME run res://dev/NAME.gd against the live UI

var session: GameSession
var sfx: Sfx
var hub: ReefHub
var pool_screen: PoolScreen
var trial_screen: PoolScreen
var help_screen: PoolScreen
var calm_screen: PoolScreen
var _trial_id: String = "wrap"
var backdrop: Backdrop
var safe_top: float = 0.0
var safe_bottom: float = 0.0
var summary_screen: SummaryScreen
var current: String = ""
var args: Dictionary = {}

func _ready() -> void:
	args = _parse_args()
	session = GameSession.new()
	if args.has("save"):
		session.save_path = "user://%s.json" % args["save"]
	if args.has("fresh") and FileAccess.file_exists(session.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(session.save_path))
	if args.has("seed"):
		session.base_seed = int(args["seed"])
	if args.has("tz"):
		GameClock.set_tz_bias_seconds(int(args["tz"]) * 60)
	if args.has("clock"):
		var unix: int = GameClock.parse_local(str(args["clock"]))
		if unix > 0:
			GameClock.set_running_at(unix)
	session.load_or_new()
	sfx = Sfx.new()
	add_child(sfx)
	backdrop = Backdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	hub = ReefHub.new()
	pool_screen = PoolScreen.new()
	summary_screen = SummaryScreen.new()
	trial_screen = PoolScreen.new()
	help_screen = PoolScreen.new()
	calm_screen = PoolScreen.new()
	for s in [hub, pool_screen, trial_screen, help_screen, calm_screen, summary_screen]:
		var c: Control = s
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(c)
	hub.setup(session, sfx)
	pool_screen.setup(session, sfx)
	pool_screen.anim_speed = float(args.get("speed", 1.0))
	summary_screen.setup(session, sfx)
	# the Tide Trial is the same pool UI on its own fixed board and session (see TideTrial)
	trial_screen.setup(session, sfx)
	trial_screen.set_trial(TideTrial.new())
	trial_screen.anim_speed = float(args.get("speed", 1.0))
	trial_screen.claim_reward = Callable(session, "claim_trial_reward")
	trial_screen.open_home.connect(func() -> void: _open_hub("start"))
	trial_screen.trial_exit.connect(func() -> void: _open_hub("start"))
	# guided practice from Help: the same pool UI on a separate board with no permanent payout
	help_screen.setup(session, sfx)
	help_screen.set_help(GameSession.new_tutorial_sandbox())
	help_screen.anim_speed = float(args.get("speed", 1.0))
	help_screen.open_home.connect(func() -> void: _open_hub("start"))
	help_screen.trial_exit.connect(func() -> void: _open_hub("start"))
	# Calm Pool: its own board and session (stored in the real profile), no rewards, quick exit
	calm_screen.setup(session, sfx)
	calm_screen.anim_speed = float(args.get("speed", 1.0))
	calm_screen.open_home.connect(func() -> void: _open_hub("start"))
	calm_screen.open_reef.connect(func() -> void: _open_hub("start"))
	calm_screen.trial_exit.connect(func() -> void: _open_hub("start"))
	calm_screen.help_replay.connect(func() -> void: show_screen("help"))
	calm_screen.calm_new_board.connect(func() -> void:
		calm_screen.set_calm(session.calm_session(true))
		calm_screen.enter())
	hub.calm_pressed.connect(func() -> void:
		hub.leave()
		show_screen("calm"))
	pool_screen.help_replay.connect(func() -> void: show_screen("help"))
	hub.help_replay.connect(func() -> void: show_screen("help"))
	pool_screen.open_reef_decor.connect(func() -> void:
		_open_hub("pool")
		hub.focus_decor())
	hub.trial_pressed.connect(_on_hub_trial)
	hub.play_pressed.connect(_on_hub_play)
	pool_screen.open_reef.connect(func() -> void:
		pool_screen.leave()
		_open_hub("pool"))
	pool_screen.open_home.connect(func() -> void:
		pool_screen.leave()
		_open_hub("start"))
	pool_screen.run_flooded.connect(func() -> void: show_screen("summary"))
	summary_screen.new_run_pressed.connect(_on_new_run)
	summary_screen.reef_pressed.connect(func() -> void: _open_hub("summary"))
	summary_screen.home_pressed.connect(func() -> void: _open_hub("start"))
	_apply_tide(true)
	_apply_safe_area()
	resized.connect(_apply_safe_area)
	show_screen("start")
	if args.has("screen") and str(args["screen"]) == "pool" and session.run != null:
		show_screen("pool")
	if args.has("playtest"):
		var script: GDScript = load("res://dev/%s.gd" % args["playtest"])
		var pt: Node = script.new()
		pt.set("main", self)
		add_child(pt)

func _notification(what: int) -> void:
	# Every action already saves a complete snapshot; this also captures the play
	# timer when the app is closed or sent to the background on a phone.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if session != null:
			session.save()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if session != null and hub != null:
			session.settle_income()       # time spent in the background is away time -> chest
			if hub.visible:
				hub.on_income_tick()

## Safe areas: phones with notches/home indicators report an inset; every screen is laid out
## inside it. `--safe=TOP,BOTTOM` (logical px) forces insets for testing on desktop.
func _apply_safe_area() -> void:
	var top: float = 0.0
	var bottom: float = 0.0
	if args.has("safe"):
		var parts: PackedStringArray = str(args["safe"]).split(",")
		top = float(parts[0]) if parts.size() > 0 else 0.0
		bottom = float(parts[1]) if parts.size() > 1 else 0.0
	else:
		var win: Vector2i = DisplayServer.window_get_size()
		var area: Rect2i = DisplayServer.get_display_safe_area()
		var scr: Vector2i = DisplayServer.screen_get_size()
		if win.x > 0 and scr.x > 0 and area.size.x > 0 and area.size.y > 0 and area.size != scr:
			var k: float = size.y / float(maxi(1, win.y))      # window px -> logical px
			top = maxf(0.0, float(area.position.y)) * k
			bottom = maxf(0.0, float(scr.y - area.end.y)) * k
	safe_top = top
	safe_bottom = bottom
	for sc in [hub, pool_screen, trial_screen, help_screen, calm_screen, summary_screen]:
		var c: Control = sc
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.offset_top = top
		c.offset_bottom = -bottom

func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var parts: PackedStringArray = s.split("=", true, 1)
		out[parts[0]] = parts[1] if parts.size() > 1 else true
	return out

## The backdrop's quiet zone follows the live board; animation runs only behind pool-style screens.
func _sync_backdrop() -> void:
	if backdrop == null:
		return
	var pool_like: bool = pool_screen.visible or trial_screen.visible or help_screen.visible or calm_screen.visible
	backdrop.animate_enabled = pool_like
	var want_vis: bool = pool_like or summary_screen.visible
	if backdrop.visible != want_vis:
		backdrop.visible = want_vis
	if not backdrop.visible:
		return
	var sc: PoolScreen = pool_screen
	for cand in [trial_screen, help_screen, calm_screen]:
		if (cand as PoolScreen).visible:
			sc = cand
	if pool_like and sc.board_view != null:
		var bv: BoardView = sc.board_view
		var tl: Vector2 = bv.get_global_transform() * Vector2(BoardView.TAB, BoardView.TAB)
		backdrop.grid_rect = Rect2(tl, Vector2(bv.cs * GameConfig.COLS, bv.cs * GameConfig.ROWS))
	backdrop.reduced_motion = sc.reduced_motion

## Screens: "start" and "reef" are both the reef hub (they differ only in where Play leads).
func show_screen(name: String) -> void:
	if name == "reef":
		name = "hub_pool"
	for sc in [pool_screen, trial_screen, help_screen, calm_screen]:
		if (sc as PoolScreen).visible:
			(sc as PoolScreen).leave()          # nothing half-finished is carried to the next screen
	current = name
	var is_hub: bool = name == "start" or name == "hub_pool" or name == "hub_summary"
	hub.visible = is_hub
	pool_screen.visible = name == "pool"
	trial_screen.visible = name == "trial"
	help_screen.visible = name == "help"
	calm_screen.visible = name == "calm"
	summary_screen.visible = name == "summary"
	match name:
		"start":
			hub.refresh("start")
		"hub_pool":
			hub.refresh("pool")
		"hub_summary":
			hub.refresh("summary")
		"pool":
			_apply_tide(true)
			pool_screen.enter()
		"trial":
			trial_screen.set_trial(TideTrial.new(_trial_id))      # a fresh attempt; the regular run stays suspended
			trial_screen.claim_reward = Callable(session, "claim_trial_reward").bind(_trial_id)
			trial_screen.enter()
		"calm":
			calm_screen.set_calm(session.calm_session())          # resumes the saved Calm board
			calm_screen.enter()
		"help":
			help_screen.set_help(GameSession.new_tutorial_sandbox())
			help_screen.enter()
		"summary":
			summary_screen.refresh()

func _open_hub(from: String) -> void:
	show_screen({"start": "start", "pool": "hub_pool", "summary": "hub_summary"}[from])

func _on_hub_trial(id: String) -> void:
	_trial_id = id
	hub.leave()
	show_screen("trial")

## Tide lighting for the screen background and the pool's reef strip.
var _phase: int = -1

func _apply_tide(force: bool) -> void:
	var ph: int = Tide.phase_at()
	if ph == _phase and not force:
		return
	_phase = ph
	var pal: Dictionary = BgArt.palette(ph)
	var night: float = [0.15, 0.0, 0.45, 1.0][ph]
	backdrop.palette = pal
	for sc in [pool_screen, trial_screen, help_screen, calm_screen]:
		var p: PoolScreen = sc
		p.reef_peek.palette = pal
		p.reef_peek.night_amount = night
		p.board_view.palette = pal

## Play / Resume / Back: where it leads depends on where the hub was opened from.
func _on_hub_play() -> void:
	hub.leave()
	match hub.context:
		"pool":
			show_screen("pool")
		"summary":
			show_screen("summary")
		_:
			if session.run == null:
				session.start_run()
				show_screen("pool")
			elif session.run.status == RunState.FLOODED:
				show_screen("summary")
			else:
				show_screen("pool")

var _income_acc: float = 0.0

func _process(delta: float) -> void:
	_sync_backdrop()
	_income_acc += delta
	if _income_acc >= GameConfig.INCOME_TICK_SEC:
		_income_acc = 0.0
		session.settle_income()       # in memory; saved with the next committed action
		session.ensure_daily()
		_apply_tide(false)
		if OS.has_feature("web"):
			# read-only debug hook for browser tests: local clock and tide as the game sees them
			var d: Dictionary = GameClock.local_dict()
			JavaScriptBridge.eval("window.tidepoolDebug = {hour: %d, minute: %d, day: '%s', tide: %d};" % [int(d["hour"]), int(d["minute"]), GameClock.local_day_key(), Tide.phase_at()], true)
		pool_screen.on_income_tick()
		hub.on_income_tick()

func _on_new_run() -> void:
	session.end_run()
	session.start_run()
	show_screen("pool")

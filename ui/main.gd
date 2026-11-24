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
	hub = ReefHub.new()
	pool_screen = PoolScreen.new()
	summary_screen = SummaryScreen.new()
	trial_screen = PoolScreen.new()
	for s in [hub, pool_screen, trial_screen, summary_screen]:
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
	hub.trial_pressed.connect(_on_hub_trial)
	hub.play_pressed.connect(_on_hub_play)
	pool_screen.open_reef.connect(func() -> void: _open_hub("pool"))
	pool_screen.open_home.connect(func() -> void: _open_hub("start"))
	pool_screen.run_flooded.connect(func() -> void: show_screen("summary"))
	summary_screen.new_run_pressed.connect(_on_new_run)
	summary_screen.reef_pressed.connect(func() -> void: _open_hub("summary"))
	summary_screen.home_pressed.connect(func() -> void: _open_hub("start"))
	_apply_tide(true)
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

func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var parts: PackedStringArray = s.split("=", true, 1)
		out[parts[0]] = parts[1] if parts.size() > 1 else true
	return out

func _draw() -> void:
	var pal: Dictionary = Tide.palette(maxi(_phase, 0)) if _phase >= 0 else Tide.palette(Tide.MIDDAY)
	var top: Color = pal["bg_top"]
	var bottom: Color = pal["bg_bottom"]
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
		PackedColorArray([top, top, bottom, bottom]))

## Screens: "start" and "reef" are both the reef hub (they differ only in where Play leads).
func show_screen(name: String) -> void:
	if name == "reef":
		name = "hub_pool"
	current = name
	var is_hub: bool = name == "start" or name == "hub_pool" or name == "hub_summary"
	hub.visible = is_hub
	pool_screen.visible = name == "pool"
	trial_screen.visible = name == "trial"
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
			trial_screen.set_trial(TideTrial.new())      # a fresh attempt; the regular run stays suspended
			trial_screen.enter()
		"summary":
			summary_screen.refresh()

func _open_hub(from: String) -> void:
	show_screen({"start": "start", "pool": "hub_pool", "summary": "hub_summary"}[from])

func _on_hub_trial() -> void:
	hub.leave()
	show_screen("trial")

## Tide lighting for the screen background and the pool's reef strip.
var _phase: int = -1

func _apply_tide(force: bool) -> void:
	var ph: int = Tide.phase_at()
	if ph == _phase and not force:
		return
	_phase = ph
	pool_screen.reef_peek.palette = Tide.palette(ph)
	queue_redraw()

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

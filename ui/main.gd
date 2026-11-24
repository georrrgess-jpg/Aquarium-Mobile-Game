extends Control
## Screen router. Command line (after `--`):
##   --save=NAME     use user://NAME.json instead of the default save
##   --fresh         delete that save first
##   --seed=N        base seed for runs (repeatable playtests)
##   --speed=X       animation speed multiplier (dev)
##   --playtest=NAME run res://dev/NAME.gd against the live UI

var session: GameSession
var sfx: Sfx
var start_screen: StartScreen
var pool_screen: PoolScreen
var reef_screen: ReefScreen
var summary_screen: SummaryScreen
var current: String = ""
var _reef_return: String = "start"
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
	session.load_or_new()
	sfx = Sfx.new()
	add_child(sfx)
	start_screen = StartScreen.new()
	pool_screen = PoolScreen.new()
	reef_screen = ReefScreen.new()
	summary_screen = SummaryScreen.new()
	for s in [start_screen, pool_screen, reef_screen, summary_screen]:
		var c: Control = s
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(c)
	start_screen.setup(session, sfx)
	pool_screen.setup(session, sfx)
	pool_screen.anim_speed = float(args.get("speed", 1.0))
	reef_screen.setup(session)
	summary_screen.setup(session, sfx)
	start_screen.play_pressed.connect(_on_play)
	start_screen.reef_pressed.connect(func() -> void: _open_reef("start"))
	pool_screen.open_reef.connect(func() -> void: _open_reef("pool"))
	pool_screen.open_home.connect(func() -> void: show_screen("start"))
	pool_screen.run_flooded.connect(func() -> void: show_screen("summary"))
	reef_screen.back_pressed.connect(func() -> void: show_screen(_reef_return))
	summary_screen.new_run_pressed.connect(_on_new_run)
	summary_screen.reef_pressed.connect(func() -> void: _open_reef("summary"))
	summary_screen.home_pressed.connect(func() -> void: show_screen("start"))
	show_screen("start")
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

func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var parts: PackedStringArray = s.split("=", true, 1)
		out[parts[0]] = parts[1] if parts.size() > 1 else true
	return out

func _draw() -> void:
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
		PackedColorArray([Pal.BG_TOP, Pal.BG_TOP, Pal.BG_BOTTOM, Pal.BG_BOTTOM]))

func show_screen(name: String) -> void:
	current = name
	start_screen.visible = name == "start"
	pool_screen.visible = name == "pool"
	reef_screen.visible = name == "reef"
	summary_screen.visible = name == "summary"
	match name:
		"start":
			start_screen.refresh()
		"pool":
			pool_screen.enter()
		"reef":
			reef_screen.refresh()
		"summary":
			summary_screen.refresh()

func _open_reef(from: String) -> void:
	_reef_return = from
	reef_screen.back_text = "Back to the pool" if from == "pool" else ("Back to the summary" if from == "summary" else "Back")
	show_screen("reef")

func _on_play() -> void:
	if session.run == null:
		session.start_run()
		show_screen("pool")
	elif session.run.status == RunState.FLOODED:
		show_screen("summary")
	else:
		show_screen("pool")

func _on_new_run() -> void:
	session.end_run()
	session.start_run()
	show_screen("pool")

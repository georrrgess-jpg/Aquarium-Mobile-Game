extends Node
## Performance benchmark, deliberately written against APIs that exist in BOTH the Update 1
## baseline and the current build so the identical scenarios can be run on each:
##   dev/run_perf.sh [baseline-worktree-dir]
## Records every frame of (1) a fixed dense-board action sequence and (2) a populated reef.
## Frames in which the benchmark itself was planning its next input are excluded.
##   --playtest=perfbench --scenario=pool|reef|micro

var main: Control
var out_dir: String = ""
var _rec_on: bool = false
var _rec_wall: Array = []
var _rec_proc: Array = []
var _rec_last: int = 0
var _skip_until_frame: int = -1
var _label: String = ""
var _slow: Array = []

func _ready() -> void:
	out_dir = ProjectSettings.globalize_path("res://dev/out")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().create_timer(0.6).timeout
	var scenario: String = str(main.args.get("scenario", "pool"))
	print("[bench] scenario=%s window=%s viewport=%s renderer=%s" % [scenario, DisplayServer.window_get_size(), get_viewport().get_visible_rect().size, RenderingServer.get_video_adapter_name()])
	# experiment switches (cost attribution): --nobd drops the backdrop, --noreefstrip hides the pool's reef strip
	if main.args.has("nobd") and main.get("backdrop") != null:
		main.backdrop.queue_free()
		main.backdrop = null
	await call("scenario_" + scenario)
	get_tree().quit(0)

# --- recorder ---------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not _rec_on:
		return
	var now: int = Time.get_ticks_usec()
	var f: int = Engine.get_process_frames()
	if _rec_last != 0 and f > _skip_until_frame:
		var ms: float = float(now - _rec_last) / 1000.0
		if ms > 20.0:
			_slow.append("%.1fms during '%s' busy=%s" % [ms, _label, str(main.pool_screen.busy)])
		_rec_wall.append(ms)
		_rec_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_rec_last = now

func skip_planning() -> void:
	_skip_until_frame = Engine.get_process_frames() + 2

func rec_start() -> void:
	_rec_wall.clear()
	_rec_proc.clear()
	_rec_last = 0
	_skip_until_frame = -1
	_rec_on = true

func rec_stop(label: String) -> void:
	_rec_on = false
	var arr: Array = _rec_wall.duplicate()
	arr.sort()
	var sum: float = 0.0
	for v in arr:
		sum += float(v)
	var over33: int = 0
	var over20: int = 0
	for v in arr:
		if float(v) > 33.4:
			over33 += 1
		if float(v) > 20.0:
			over20 += 1
	if str(main.args.get("verbose", "")) != "":
		for line in _slow:
			print("[bench]   slow frame: ", line)
	_slow.clear()
	print("[bench] %s | frames=%d | frame ms avg %.2f p50 %.2f p95 %.2f p99 %.2f max %.2f | frames >20ms: %d, >33ms: %d" % [
		label, arr.size(), sum / float(maxi(1, arr.size())), arr[int(arr.size() * 0.5)], arr[mini(arr.size() - 1, int(arr.size() * 0.95))],
		arr[mini(arr.size() - 1, int(arr.size() * 0.99))], arr[arr.size() - 1], over20, over33])

# --- input helpers (mouse) ------------------------------------------------------------------------

func frames(n: int = 2) -> void:
	for i in n:
		await get_tree().process_frame

func to_window(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p

func _button(p: Vector2, pressed: bool) -> void:
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.position = to_window(p)
	m.global_position = m.position
	m.pressed = pressed
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(m)

func _move(p: Vector2, rel: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = to_window(p)
	m.global_position = m.position
	m.relative = rel
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(m)

func click(p: Vector2) -> void:
	_button(p, true)
	await frames(2)
	_button(p, false)
	await frames(3)

func drag(a: Vector2, b: Vector2, steps: int = 8) -> void:
	_button(a, true)
	await frames(2)
	var prev: Vector2 = a
	for i in range(1, steps + 1):
		var p: Vector2 = a.lerp(b, float(i) / float(steps))
		_move(p, p - prev)
		prev = p
		await frames(1)
	await frames(1)
	_button(b, false)
	await frames(3)

func pool() -> Control:
	return main.pool_screen

func board() -> Control:
	return main.pool_screen.board_view

func cell_center(i: int) -> Vector2:
	return board().cell_center_global(i)

func click_btn(b: Control) -> void:
	await click(b.get_global_rect().get_center())
	await idle()

func idle() -> void:
	var guard: int = 0
	while main.pool_screen.busy and guard < 2000:
		await get_tree().process_frame
		guard += 1
	await frames(3)

func play_button() -> Control:
	if main.get("hub") != null:
		return main.hub.btn_play
	return main.start_screen.btn_play

func tab_pos(axis: int, index: int) -> Vector2:
	var bv: Control = board()
	var local: Vector2
	if axis == 0:
		local = Vector2(bv.TAB * 0.5, bv.TAB + (float(index) + 0.5) * bv.cs)
	else:
		local = Vector2(bv.TAB + (float(index) + 0.5) * bv.cs, bv.TAB * 0.5)
	return bv.get_global_transform() * local

func load_board(b: Board, turn: int, currents: int) -> void:
	var se: GameSession = main.session
	se.run.board = b
	se.run.turn = turn
	se.run.currents = currents
	se.run.tutorial = false
	se.run.pending_surge = []
	board().clear_selection()
	board().sync(b)
	pool()._refresh_all()

func dense_board(seed_v: int, empties: int) -> Board:
	var rng := SeededRng.new(seed_v)
	var b := Board.new()
	var cells: Array = range(Board.cell_count())
	for i in cells.size():
		var j: int = i + rng.int_range(0, cells.size() - 1 - i)
		var t: Variant = cells[i]
		cells[i] = cells[j]
		cells[j] = t
	var weights: Array = []
	for e in GameConfig.SPAWN_TABLE:
		weights.append(e[2])
	for k in range(Board.cell_count() - empties):
		var e: Array = GameConfig.SPAWN_TABLE[rng.pick_weighted(weights)]
		b.set_code(int(cells[k]), Creature.make(e[0], e[1]))
	return b

func fake_residents(n: int) -> Array:
	var out: Array = []
	for i in n:
		var fam: int = 1 + (i % 2)
		var tier: int = 4 + (i % 3)
		out.append({"id": i + 1, "code": Creature.make(fam, tier), "family": fam, "tier": tier, "run": 1})
	return out

# --- scenarios -------------------------------------------------------------------------------------

## Fixed 14-step sequence on a 32-creature board: selection taps (no turn), a Current preview
## opened and cancelled, slides, pair merges (some chain) and three Surges (preview + landing).
func scenario_pool() -> void:
	var se: GameSession = main.session
	await click_btn(play_button())
	load_board(dense_board(7, 10), 0, 3)
	Engine.max_fps = 60
	await frames(30)
	rec_start()
	for step in 14:
		_label = "step %d (%s)" % [step, ["slide", "merge", "current", "merge", "slide", "merge", "merge"][step % 7]]
		skip_planning()
		var b: Board = se.run.board
		match step % 7:
			0, 4:
				var from: int = -1
				var to: int = -1
				for i in b.cells.size():
					if b.code_at(i) == 0:
						continue
					for n in b.neighbors(i):
						if n >= 0 and b.code_at(n) == 0 and from < 0:
							from = i
							to = n
				await click(cell_center(from))
				await click(cell_center(from))
				await drag(cell_center(from), cell_center(to))
			1, 3, 5, 6:
				var done: bool = false
				for i in b.cells.size():
					for j in range(i + 1, b.cells.size()):
						if not done and MergeRules.can_pair(b, i, j):
							await click(cell_center(i))
							await click(cell_center(j))
							done = true
			2:
				await click_btn(pool().btn_current)
				await click(tab_pos(0, 3))
				await click_btn(pool().btn_dir_a)
				await click_btn(pool().btn_dir_b)
				if step >= 7:
					await click_btn(pool().btn_confirm)           # second cycle: commit the Current
				else:
					await click_btn(pool().btn_current)           # first cycle: cancel the preview
		await idle()
		if se.run.status != RunState.ACTIVE:
			break
	rec_stop("pool_dense_sequence")
	print("[bench] sequence ended at turn %d, status %d, creatures %d" % [se.run.turn, se.run.status, se.run.board.creature_count()])

## Populated reef: 30 residents, ten seconds idle on the reef view and ten on the pool's strip.
func scenario_reef() -> void:
	var se: GameSession = main.session
	Engine.max_fps = 60
	se.profile.residents = fake_residents(30)
	se.profile.next_resident_id = 31
	main.show_screen("start")
	if str(main.args.get("tab", "")) != "" and main.get("hub") != null:
		main.hub._show_tab(str(main.args["tab"]))      # experiment: which tab is on screen
	await frames(30)
	rec_start()
	await get_tree().create_timer(10.0).timeout
	rec_stop("reef_populated_30_idle")
	await click_btn(play_button())
	await frames(30)
	var ps: Node = main.pool_screen
	for what in str(main.args.get("hide", "")).split(","):     # experiment: --hide=strip,gate,board,hud
		match what:
			"strip": ps.reef_peek.visible = false
			"gate": ps.gate.visible = false
			"board": ps.board_view.visible = false
			"bdanim": main.backdrop._anim.visible = false
			"bdstatic": main.backdrop._static.visible = false
	await frames(10)
	rec_start()
	await get_tree().create_timer(10.0).timeout
	rec_stop("pool_with_reef_strip_30_idle")

## Microsecond cost of per-tap / per-action calls on a dense board.
func scenario_micro() -> void:
	var se: GameSession = main.session
	await click_btn(play_button())
	load_board(dense_board(7, 10), 0, 3)
	await frames(5)
	var tests: Dictionary = {
		"session.is_stuck": func() -> void: se.is_stuck(),
		"session.preview_current (one line)": func() -> void: se.preview_current(0, 3, -1),
		"pool._update_prompt (runs on every selection change)": func() -> void: pool()._update_prompt(),
		"session.valid_targets": func() -> void: se.valid_targets(5),
		"session.save (JSON + atomic write)": func() -> void: se.save(),
		"pool._refresh_all (runs after every action)": func() -> void: pool()._refresh_all(),
	}
	for k in tests:
		var f: Callable = tests[k]
		var t0: int = Time.get_ticks_usec()
		var n: int = 200
		for i in n:
			f.call()
		print("[bench] micro %-56s %9.1f us/call" % [k, float(Time.get_ticks_usec() - t0) / float(n)])


## (Update 3 only) populated reef with the Lantern Ray visiting, all five decorations placed,
## tide lighting on and a Night overlay: ten seconds idle on the reef hub.
func scenario_reef_visitor() -> void:
	var se: GameSession = main.session
	Engine.max_fps = 60
	GameClock.set_tz_bias_seconds(0)
	GameClock.freeze(GameClock.unix_from_local(2026, 11, 24, 6, 40))
	se.profile.residents = fake_residents(30)
	se.profile.next_resident_id = 31
	se.profile.unseen_residents = [30]
	var slots: Array = [0, 1, 2, 3, 4]
	se.profile.decorations = []
	for i in 5:
		se.profile.decorations.append({"id": String(GameConfig.DECORATIONS[i]["id"]), "slot": int(slots[i])})
	se.profile.income_stamp = GameClock.now()
	main._apply_tide(true)
	main.show_screen("start")
	await frames(30)
	rec_start()
	await get_tree().create_timer(10.0).timeout
	rec_stop("reef_30_residents_5_decor_visitor_dawn")
	GameClock.freeze(GameClock.unix_from_local(2026, 11, 24, 23, 0))
	main._apply_tide(true)
	main.show_screen("start")
	await frames(30)
	rec_start()
	await get_tree().create_timer(10.0).timeout
	rec_stop("reef_30_residents_5_decor_night_overlay")

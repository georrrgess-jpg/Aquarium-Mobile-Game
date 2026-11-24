extends Node
## Dev-only live-UI driver. Launch the game with `-- --playtest=playtest --scenario=NAME`.
## It injects real pointer events into the running UI (mouse and emulated touch),
## waits for animations, writes screenshots to dev/out/ and prints a log line per
## check. See dev/run_playtest.sh.

var main: Control
var out_dir: String = ""
var failures: int = 0
var checks: int = 0
var _t0: float = 0.0
var use_touch: bool = false

func _ready() -> void:
	out_dir = ProjectSettings.globalize_path("res://dev/out")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_t0 = Time.get_ticks_msec() / 1000.0
	await get_tree().create_timer(0.6).timeout
	var scenario: String = str(main.args.get("scenario", "smoke"))
	use_touch = main.args.has("touch")
	print("[playtest] scenario=%s touch=%s window=%s viewport=%s" % [scenario, use_touch, DisplayServer.window_get_size(), get_viewport().get_visible_rect().size])
	await call("scenario_" + scenario)
	print("[playtest] done: %d checks, %d failures, wall %.1fs" % [checks, failures, Time.get_ticks_msec() / 1000.0 - _t0])
	get_tree().quit(1 if failures > 0 else 0)

# --- helpers ---------------------------------------------------------------------------

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
	print("[playtest] %s %s" % ["ok  " if cond else "FAIL", msg])

func frames(n: int = 2) -> void:
	for i in n:
		await get_tree().process_frame

func shot(name: String) -> void:
	await frames(3)
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("[playtest] shot %s (%dx%d)" % [name, img.get_width(), img.get_height()])

func to_window(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p

## Send pointer events. `p` is in logical (canvas) coordinates.
func _send_button(p: Vector2, pressed: bool) -> void:
	if use_touch:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = to_window(p)
		t.pressed = pressed
		Input.parse_input_event(t)
	else:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.position = to_window(p)
		m.global_position = m.position
		m.pressed = pressed
		m.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(m)

func _send_move(p: Vector2, rel: Vector2) -> void:
	if use_touch:
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = to_window(p)
		d.relative = rel
		Input.parse_input_event(d)
	else:
		var m := InputEventMouseMotion.new()
		m.position = to_window(p)
		m.global_position = m.position
		m.relative = rel
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)

func click(p: Vector2) -> void:
	_send_button(p, true)
	await frames(2)
	_send_button(p, false)
	await frames(3)

func drag(a: Vector2, b: Vector2, steps: int = 8) -> void:
	_send_button(a, true)
	await frames(2)
	var prev: Vector2 = a
	for i in range(1, steps + 1):
		var p: Vector2 = a.lerp(b, float(i) / float(steps))
		_send_move(p, p - prev)
		prev = p
		await frames(1)
	await frames(1)
	_send_button(b, false)
	await frames(3)

func idle() -> void:
	# wait until the pool has finished animating / previewing
	var guard: int = 0
	while main.pool_screen.busy and guard < 2000:
		await get_tree().process_frame
		guard += 1
	await frames(3)

func pool() -> PoolScreen:
	return main.pool_screen

func board() -> BoardView:
	return main.pool_screen.board_view

func cell_center(i: int) -> Vector2:
	return board().cell_center_global(i)

func gate_center() -> Vector2:
	return pool().gate.get_global_rect().get_center()

func click_btn(b: Control) -> void:
	await click(b.get_global_rect().get_center())
	await idle()

func tap_cells(a: int, b: int) -> void:
	await click(cell_center(a))
	await click(cell_center(b))
	await idle()

func drag_cells(a: int, b: int) -> void:
	await drag(cell_center(a), cell_center(b))
	await idle()

func i_(r: int, c: int) -> int:
	return Board.idx(r, c)

func session() -> GameSession:
	return main.session

# --- shared checks ----------------------------------------------------------------------------

func snapshot() -> Dictionary:
	var se: GameSession = session()
	return {
		"board": se.run.board.to_array() if se.run != null else [],
		"turn": se.run.turn if se.run != null else -1,
		"currents": se.run.currents if se.run != null else -1,
		"coins": se.profile.coins, "pearls": se.profile.pearls,
		"residents": se.profile.residents.size(),
		"pending": se.run.pending_surge.size() if se.run != null else -1,
	}

func start_pool(fresh_layout: Board = null) -> void:
	await click_btn(main.hub.btn_play)
	if fresh_layout != null:
		load_board(fresh_layout)

## Replace the live board with a reproducible state and refresh the UI.
func load_board(b: Board, turn: int = 0, currents: int = 2) -> void:
	var se: GameSession = session()
	se.run.board = b
	se.run.turn = turn
	se.run.currents = currents
	se.run.tutorial = false
	se.run.pending_surge = []
	board().clear_selection()
	board().sync(b)
	pool()._refresh_all()

func rows_board(rows: Array) -> Board:
	return Board.from_text(rows)

func tab_pos(axis: int, index: int) -> Vector2:
	var bv: BoardView = board()
	var local: Vector2
	if axis == Board.AXIS_ROW:
		local = Vector2(BoardView.TAB * 0.5, BoardView.TAB + (float(index) + 0.5) * bv.cs)
	else:
		local = Vector2(BoardView.TAB + (float(index) + 0.5) * bv.cs, BoardView.TAB * 0.5)
	return bv.get_global_transform() * local

func layout_named() -> Dictionary:
	var p: PoolScreen = pool()
	return {
		"coins": p.chip_coins, "pearls": p.chip_pearls, "turn": p.chip_turn, "currents": p.chip_currents,
		"surge": p.surge_strip, "home": p.btn_home, "reef_btn": p.btn_reef, "motion": p.btn_motion, "sound": p.btn_sound,
		"board": p.board_view, "gate": p.gate, "prompt": p.prompt_panel,
		"btn_current": p.btn_current, "dir_a": p.btn_dir_a, "dir_b": p.btn_dir_b, "confirm": p.btn_confirm, "tide": p.btn_tide,
		"reef_peek": p.reef_peek,
	}

## No visible element may overlap another or leave the screen.
func check_layout(label: String) -> void:
	var vp: Rect2 = get_viewport().get_visible_rect()
	var named: Dictionary = layout_named()
	var rects: Dictionary = {}
	for k in named:
		var c: Control = named[k]
		if c.is_visible_in_tree():
			rects[k] = c.get_global_rect()
	var bad: PackedStringArray = PackedStringArray()
	for k in rects:
		var r: Rect2 = rects[k]
		# column column: allow the content column to be centred inside a wider viewport
		if r.position.x < vp.position.x - 0.5 or r.position.y < vp.position.y - 0.5 or r.end.x > vp.end.x + 0.5 or r.end.y > vp.end.y + 0.5:
			bad.append("%s leaves the screen %s" % [k, r])
	var keys: Array = rects.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var inter: Rect2 = (rects[keys[i]] as Rect2).intersection(rects[keys[j]])
			if inter.get_area() > 1.0:
				bad.append("%s overlaps %s (%.0f px2)" % [keys[i], keys[j], inter.get_area()])
	for bk in ["btn_current", "dir_a", "dir_b", "confirm", "tide", "reef_btn"]:
		var pb: PillButton = named[bk]
		if pb.is_visible_in_tree() and not pb.content_fits():
			bad.append("button %s '%s' content does not fit" % [bk, pb.text])
	# text must fit: prompt <= 2 lines, chips show their whole value
	var p: PoolScreen = pool()
	if p.prompt_label.get_line_count() > 2:
		bad.append("prompt wraps to %d lines" % p.prompt_label.get_line_count())
	for ck in ["coins", "pearls", "turn", "currents"]:
		var chip: HudWidgets.Chip = named[ck]
		if not chip.text_fits():
			bad.append("chip %s value '%s' does not fit" % [ck, chip.value])
	check(bad.is_empty(), "layout[%s] %d elements, no overlap, all on screen%s" % [label, rects.size(), "" if bad.is_empty() else "  -> " + "; ".join(bad)])

# --- scenarios -----------------------------------------------------------------------------

func scenario_smoke() -> void:
	await shot("00_start")
	await click_btn(main.hub.btn_play)
	await shot("01_pool_start")

## First-run walkthrough using real pointer input: opening merge + chain, illegal
## move, wrapped Current, Reef Gate release, Surge on turn 3.
func scenario_tutorial() -> void:
	await shot("t00_start")
	await click_btn(main.hub.btn_play)
	var se: GameSession = session()
	check(se.run != null and se.run.turn == 0 and se.run.board.creature_count() == 12, "first run starts with 12 creatures, turn 0")
	check(se.run.currents == 2, "two starting Currents")
	check(pool().prompt_label.text.find("Merge the glowing shrimp") >= 0, "prompt beside the board explains the opening merge")
	check(board().hint_cells.has(i_(4, 1)) and board().hint_cells.has(i_(4, 2)), "opening pair is highlighted")
	await shot("t01_pool")

	# 1. opening merge by DRAG; chain resolves into tier 3
	await drag_and_peek(i_(4, 1), i_(4, 2), 0.42, "t02_chain_midflight")
	var s1: Dictionary = snapshot()
	check(se.run.board.code_at(i_(4, 2)) == Creature.make(1, 3), "opening merge chained into a tier-3 Shrimp at (4,2)")
	check(s1["turn"] == 1 and s1["currents"] == 3, "chain cost one turn and earned a Current (2 -> 3)")
	check(s1["coins"] == 48 and s1["pearls"] == 3, "paid 10 + 38 coins, 1 + 2 pearls (got %d / %d)" % [s1["coins"], s1["pearls"]])
	await get_tree().create_timer(0.8).timeout
	check(pool().chip_coins.value == "48" and pool().chip_pearls.value == "3", "HUD balances match once the pearls have landed (%s / %s)" % [pool().chip_coins.value, pool().chip_pearls.value])
	await shot("t03_after_chain")

	# 2. illegal move: rejected, free
	await drag_cells(i_(0, 2), i_(3, 3))
	var s2: Dictionary = snapshot()
	check(s2["turn"] == 1 and s2["coins"] == 48 and s2["board"] == s1["board"], "illegal drag rejected: no turn, no payout, board unchanged")
	check(pool().toast.visible, "rejection explains itself in a toast")
	await shot("t04_rejected")

	# 3. Current: tab -> direction -> preview -> confirm (wraps into a line)
	await click_btn(pool().btn_current)
	await shot("t05_current_mode")
	await click(tab_pos(Board.AXIS_ROW, 1))
	await click_btn(pool().btn_dir_a)
	check(board().line_preview.get("dir", 0) == -1, "preview shows row 2 shifting left")
	check(pool().prompt_label.text.find("makes a merge") >= 0, "preview text says it makes a merge before committing")
	var pinfo: Dictionary = board().line_preview.get("info", {})
	check(pinfo.get("steps", []).size() == 1 and (pinfo["steps"][0]["sources"] as PackedInt32Array).has(i_(1, 3)) and (pinfo["steps"][0]["sources"] as PackedInt32Array).has(i_(1, 5)), "preview marks the cells that will form the three-in-a-row (from the real rules)")
	check(se.run.currents == 3 and se.run.turn == 1, "nothing is spent while previewing")
	await shot("t06_current_preview")
	await click_btn(pool().btn_confirm)
	var s3: Dictionary = snapshot()
	check(se.run.board.code_at(i_(1, 4)) == Creature.make(2, 4), "wrapped Current made a tier-4 Starfish in the middle of the line")
	check(s3["turn"] == 2 and s3["currents"] == 2, "Current used one turn and one charge (3 -> 2), no chain refund")
	await shot("t07_after_current")

	# 4. Reef Gate: select (glow) then tap the gate; costs no turn
	await click(cell_center(i_(1, 4)))
	check(pool().gate.state == 1, "Reef Gate glows when a tier 4+ creature is selected")
	await shot("t08_gate_glow")
	await click(gate_center())
	await idle()
	var s4: Dictionary = snapshot()
	check(s4["residents"] == 1 and se.run.board.code_at(i_(1, 4)) == 0, "release removed it from the board and created exactly one resident")
	check(s4["turn"] == 2, "release cost no turn")
	check(pool().gate.residents == 1, "gate counter shows 1 in reef")
	await shot("t09_after_release")

	# 5. third turn: move, then Surge preview + landing
	await drag(cell_center(i_(0, 2)), cell_center(i_(0, 3)))
	await get_tree().create_timer(0.55).timeout
	check(se.run.turn == 3 and se.run.pending_surge.size() == 3, "turn 3 resolves the move, then previews a 3-creature Surge")
	check(board().surge_preview.size() == 3, "the three incoming cells are highlighted on the board")
	await shot("t10_surge_preview")
	var before_cnt: int = se.run.board.creature_count()
	await idle()
	check(se.run.pending_surge.is_empty() and se.run.board.creature_count() == before_cnt + 3, "Surge landed exactly three creatures")
	await shot("t11_after_surge")

	# 6. leave a record for the reload check in a separate process
	var snap: Dictionary = snapshot()
	var f := FileAccess.open(out_dir + "/expected.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(snap))
	f.close()
	print("[playtest] expected state recorded: turn=%d currents=%d coins=%d pearls=%d residents=%d" % [snap["turn"], snap["currents"], snap["coins"], snap["pearls"], snap["residents"]])

func drag_and_peek(a: int, b: int, delay: float, shot_name: String) -> void:
	await drag(cell_center(a), cell_center(b))
	await get_tree().create_timer(delay).timeout
	await shot(shot_name)
	await idle()

## A fresh process opens the save written by `tutorial`: it must resume exactly.
func scenario_reload_check() -> void:
	var f := FileAccess.open(out_dir + "/expected.json", FileAccess.READ)
	var exp: Dictionary = JSON.parse_string(f.get_as_text())
	await shot("r00_start_after_reload")
	check(main.hub.btn_play.text == "Resume run", "start screen offers 'Resume run'")
	check(main.hub.chip_res.value == str(int(exp["residents"])), "start-screen reef shows the resident count (%s)" % main.hub.chip_res.value)
	await click_btn(main.hub.btn_play)
	var now: Dictionary = snapshot()
	check(str(now["board"]) == str(exp["board"]), "board identical after reload")
	check(now["turn"] == int(exp["turn"]) and now["currents"] == int(exp["currents"]), "turn count (%d) and Current charges (%d) identical" % [now["turn"], now["currents"]])
	check(now["coins"] == int(exp["coins"]) and now["pearls"] == int(exp["pearls"]), "coins and pearls identical (%d / %d)" % [now["coins"], now["pearls"]])
	check(now["residents"] == int(exp["residents"]), "resident count identical (%d)" % now["residents"])
	check(now["pending"] == 0, "no Surge replayed")
	check(pool().chip_coins.value == PoolScreen._fmt(int(exp["coins"])), "HUD shows the banked coins")
	await shot("r01_pool_after_reload")

## Same key flow with TOUCH events (engine emulates mouse from touch).
func scenario_touch() -> void:
	await click_btn(main.hub.btn_play)
	var se: GameSession = session()
	check(use_touch, "driver is sending touch events")
	# tap-select, tap-target merge of the starter pair
	await tap_cells(i_(4, 1), i_(4, 2))
	check(se.run.turn == 1 and se.run.board.code_at(i_(4, 2)) == Creature.make(1, 3), "touch tap-select + tap-target merged and chained")
	# drag-merge: starfish pair anywhere on the board
	load_board(rows_board([". . . . . .", ". . . . . .", ". . . . . .", ". . . . . .", "F2 . . . . .", ". . . . . .", ". . . . F2 ."]), 1, 2)
	await drag_cells(i_(4, 0), i_(6, 4))
	check(se.run.board.code_at(i_(6, 4)) == Creature.make(2, 3) and se.run.turn == 2, "touch drag merge across the board")
	# Current by dragging along a row, then confirm
	load_board(rows_board([". . . . . .", "S2 . . . S2 S2", ". . . . . ."]), 2, 2)
	await click_btn(pool().btn_current)
	await drag(cell_center(i_(1, 3)), cell_center(i_(1, 1)))
	check(board().line_preview.get("axis", -1) == Board.AXIS_ROW and board().line_preview.get("dir", 0) == -1, "touch drag along a row previews a left shift")
	await click_btn(pool().btn_confirm)
	check(se.run.board.code_at(i_(1, 4)) == Creature.make(1, 4), "wrapped Current made a line by touch")
	# drag to the Reef Gate
	await drag(cell_center(i_(1, 4)), gate_center())
	await idle()
	check(se.profile.residents.size() == 1 and se.run.board.code_at(i_(1, 4)) == 0, "touch drag onto the Reef Gate released it")
	await shot("touch_done")

## Tier cap, line, trio and the flood, via the live UI on reproducible boards.
func scenario_rules_ui() -> void:
	await click_btn(main.hub.btn_play)
	var se: GameSession = session()
	# pair merge anywhere
	load_board(rows_board(["S1 . . . . .", ". . . . . .", ". . . . . .", ". . . . . S1"]), 0, 2)
	await drag_cells(i_(0, 0), i_(3, 5))
	check(se.run.board.code_at(i_(3, 5)) == Creature.make(1, 2) and se.run.board.code_at(i_(0, 0)) == 0 and se.run.turn == 1, "UI pair merge: destination holds the next tier")
	# three in a row
	load_board(rows_board([". . . . . .", ". . . . . .", "F1 F1 . F1 . .", ". . . . . ."]), 0, 2)
	await drag_cells(i_(2, 3), i_(2, 2))
	check(se.run.board.code_at(i_(2, 1)) == Creature.make(2, 3) and se.run.board.creature_count() == 1, "UI three-in-a-row: tier+2 in the middle cell")
	await shot("rules_line")
	# tier cap: two tier 6 refuse to merge, spend nothing; gate accepts
	load_board(rows_board(["S6 . . . S6 .", ". . . . . ."]), 0, 2)
	var coins: int = se.profile.coins
	await drag_cells(i_(0, 0), i_(0, 4))
	check(se.run.turn == 0 and se.run.board.code_at(i_(0, 0)) == Creature.make(1, 6) and se.profile.coins == coins, "UI tier cap: tier 6 pair rejected, no turn, no payout")
	check(pool().toast.visible, "tier-cap rejection is explained")
	await shot("rules_tier_cap")
	# flood: 40 creatures, slide on turn 3
	var rows: Array = []
	for r in GameConfig.ROWS:
		var toks: PackedStringArray = PackedStringArray()
		for c in GameConfig.COLS:
			toks.append("S1" if (r + c) % 2 == 0 else "F2")
		rows.append(" ".join(toks))
	var fb: Board = rows_board(rows)
	fb.set_code(i_(6, 4), 0)
	fb.set_code(i_(6, 5), 0)
	fb.set_code(i_(0, 0), Creature.make(1, 5))     # a survivor to release at the summary
	load_board(fb, 2, 2)
	await drag(cell_center(i_(6, 3)), cell_center(i_(6, 4)))
	await get_tree().create_timer(0.5).timeout
	check(se.run.status == RunState.FLOODED and se.run.pending_surge.is_empty(), "UI flood: fewer than 3 free cells ends the run with no partial wave")
	check(pool().surge_strip.danger, "the strip shows why: wave cannot fit")
	await shot("rules_flood_notice")
	var before: int = se.run.board.creature_count()
	await idle_until_summary()
	check(main.current == "summary", "run summary is shown")
	check(se.run.board.creature_count() == before, "nothing spawned")
	await shot("rules_summary")
	# release the survivor from the summary
	var survivors: Array = main.summary_screen.survivors()
	check(survivors.size() == 1, "summary lists the tier 5 survivor")
	await click(main.summary_screen.surv_flow.get_child(0).get_child(0).get_global_rect().get_center())
	check(se.profile.residents.size() == 1, "survivor released from the summary: resident count 1")
	await shot("rules_summary_released")
	# new run carries rewards and residents
	var banked: int = se.profile.coins
	await click_btn(main.summary_screen.btn_new)
	check(se.profile.residents.size() == 1 and se.profile.coins == banked and se.run.turn == 0 and se.run.currents == 2, "new run keeps coins and residents, resets turn and Currents")
	await shot("rules_new_run")

func idle_until_summary() -> void:
	var guard: int = 0
	while main.current != "summary" and guard < 1200:
		await get_tree().process_frame
		guard += 1

## Layout/overlap checks at the viewport size this process was launched with.
func scenario_layout() -> void:
	var se: GameSession = session()
	await shot("L00_start")
	await click_btn(main.hub.btn_play)
	var tag: String = "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	var vp: Vector2 = get_viewport().get_visible_rect().size
	print("[playtest] layout run: window %s logical %s cell=%.0f px (physical %.1f)" % [tag, vp, board().cs, board().cs * DisplayServer.window_get_size().x / vp.x])
	# worst-case content: big balances, tier badges, selection
	se.profile.coins = 1234567
	se.profile.pearls = 98765
	load_board(rows_board(["S1 F1 S2 F2 S3 F3", "F4 S5 . . S6 F6", ". . . . . .", "S1 . S2 . F3 .", ". . . . . .", "F1 . . . . S4", ". . F2 . . ."]), 5, 12)
	check_layout("normal " + tag)
	await shot("L01_normal_" + tag)
	await click(cell_center(i_(1, 0)))
	check_layout("tier4 selected " + tag)
	await shot("L02_selected_" + tag)
	board().clear_selection()
	await click_btn(pool().btn_current)
	await click(tab_pos(Board.AXIS_ROW, 1))
	await click_btn(pool().btn_dir_b)
	check_layout("current preview " + tag)
	await shot("L03_current_" + tag)
	pool()._exit_current_mode()
	# Surge preview on screen
	load_board(rows_board(["S1 F1 S2 . . .", ". . . . . ."]), 2, 2)
	var res: Dictionary = se.try_drop(i_(0, 2), i_(0, 3))
	pool()._play_result(res)
	await get_tree().create_timer(0.7).timeout
	check_layout("surge preview " + tag)
	await shot("L04_surge_" + tag)
	await idle()
	# forced stuck -> tide button
	se.force_stuck_for_testing = true
	bump_ui()
	pool()._update_buttons()
	pool()._update_prompt()
	check_layout("advance tide " + tag)
	await shot("L05_tide_" + tag)
	se.force_stuck_for_testing = false
	bump_ui()
	pool()._update_buttons()
	# flood notice
	pool().surge_strip.danger = true
	pool().surge_strip.message = "Only 2 free cells; the wave needs 3"
	pool().surge_strip.refresh()
	check_layout("flood notice " + tag)
	await shot("L06_flood_" + tag)
	pool().surge_strip.danger = false
	# other screens
	main.show_screen("summary")
	await shot("L07_summary_" + tag)
	main.show_screen("reef")
	await shot("L08_reef_" + tag)
	main.show_screen("start")
	await shot("L09_start_" + tag)

## Tide advance through the real button (stuck is unreachable naturally, so force it).
## Stuck is flag-forced in tests, so invalidate the UI's per-state caches the way a committed action does.
func bump_ui() -> void:
	pool()._state_version += 1

func scenario_tide() -> void:
	await click_btn(main.hub.btn_play)
	var se: GameSession = session()
	load_board(rows_board(["S1 F1 S2 F2 S3 F3"]), 4, 0)
	se.force_stuck_for_testing = true
	bump_ui()
	pool()._update_buttons()
	pool()._update_prompt()
	check(pool().btn_tide.visible, "Advance-the-tide button appears when there is no legal action")
	await click(pool().btn_tide.get_global_rect().get_center())
	await get_tree().create_timer(0.5).timeout
	check(se.run.turn == 6 and se.run.pending_surge.size() == 3, "advancing jumps from turn 4 to the next Surge (turn 6) and previews it")
	await idle()
	check(se.run.pending_surge.is_empty() and se.run.board.creature_count() == 9, "the Surge landed")

## Reduced motion: toggle in the HUD, run a chain, confirm nothing flies and state is identical.
func scenario_reduced_motion() -> void:
	await click_btn(main.hub.btn_motion)
	check(session().profile.settings["reduced_motion"] == true, "reduced motion toggled on from the start screen")
	await click_btn(main.hub.btn_play)
	check(board().reduced_motion and pool().reduced_motion, "pool honours reduced motion")
	await drag_cells(i_(4, 1), i_(4, 2))
	check(session().run.board.code_at(i_(4, 2)) == Creature.make(1, 3) and session().profile.coins == 48, "same chain and payout with reduced motion")
	check(pool().chip_coins.value == "48", "balance updates without pearl flight")
	await shot("reduced_motion_after_chain")
	load_board(rows_board(["S1 . . . . .", ". . . . . ."]), 2, 2)
	await drag(cell_center(i_(0, 0)), cell_center(i_(0, 1)))
	await get_tree().create_timer(0.5).timeout
	await shot("reduced_motion_surge_preview")
	await idle()
	check(session().run.pending_surge.is_empty(), "static Surge preview still lands")

## Reload while a Surge is previewing: close the app mid-preview, reopen, and the
## Surge must replay and land exactly once (same cells, same tiers).
func scenario_surge_reload_a() -> void:
	await click_btn(main.hub.btn_play)
	var se: GameSession = session()
	load_board(rows_board(["S1 . . . . .", ". . . . . .", ". . . . . ."]), 2, 2)
	se.profile.coins = 500
	await drag(cell_center(i_(0, 0)), cell_center(i_(0, 1)))
	await get_tree().create_timer(0.4).timeout
	check(se.run.pending_surge.size() == 3, "Surge is previewing (pending, not landed)")
	var rec: Dictionary = snapshot()
	rec["pending_cells"] = se.run.pending_surge.duplicate(true)
	var f := FileAccess.open(out_dir + "/expected_surge.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rec))
	f.close()
	print("[playtest] quitting mid-preview")

func scenario_surge_reload_b() -> void:
	var f := FileAccess.open(out_dir + "/expected_surge.json", FileAccess.READ)
	var exp: Dictionary = JSON.parse_string(f.get_as_text())
	var se: GameSession = session()
	check(se.run.pending_surge.size() == 3, "pending Surge restored from the save")
	check(str(se.run.board.to_array()) == str(exp["board"]), "board identical (Surge not yet landed)")
	var want: Dictionary = {}
	for p in exp["pending_cells"]:
		want[int(p["cell"])] = int(p["code"])
	await click(main.hub.btn_play.get_global_rect().get_center())
	await get_tree().create_timer(0.4).timeout
	check(board().surge_preview.size() == 3, "preview replays after resume")
	await shot("surge_resume_preview")
	await idle()
	var ok: bool = true
	for cell in want:
		ok = ok and se.run.board.code_at(int(cell)) == int(want[cell])
	check(ok, "landed on the same cells with the same tiers")
	check(se.run.board.creature_count() == 4 and se.profile.coins == 500 and se.run.turn == 3, "landed once; no extra payout or turn")

## Release, then close immediately.
func scenario_release_reload_a() -> void:
	await click_btn(main.hub.btn_play)
	var se: GameSession = session()
	load_board(rows_board(["F4 . . . . .", ". . . . S5 ."]), 1, 2)
	await drag(cell_center(i_(0, 0)), gate_center())
	await idle()
	check(se.profile.residents.size() == 1 and se.run.board.code_at(i_(0, 0)) == 0, "released by drag")
	var rec: Dictionary = snapshot()
	var f := FileAccess.open(out_dir + "/expected_release.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rec))
	f.close()

func scenario_release_reload_b() -> void:
	var f := FileAccess.open(out_dir + "/expected_release.json", FileAccess.READ)
	var exp: Dictionary = JSON.parse_string(f.get_as_text())
	var se: GameSession = session()
	check(se.profile.residents.size() == 1, "resident count is 1 after reload (no duplicate, none lost)")
	check(str(se.run.board.to_array()) == str(exp["board"]), "the released creature is still gone from the board")
	await click_btn(main.hub.btn_play)
	check(pool().gate.residents == 1, "gate counter shows 1")
	await shot("release_reload")
	await click_btn(pool().btn_reef)
	check(main.current == "hub_pool", "reef screen opens from the pool")
	await shot("reef_one_resident")
	await click_btn(main.hub.btn_play)
	check(main.current == "pool", "route back to the pool works")

## Free (no-change) Current through the UI.
func scenario_free_current() -> void:
	await click_btn(main.hub.btn_play)
	var se: GameSession = session()
	load_board(rows_board(["S1 F1 S2 . . .", ". . . . . .", ". . . . . ."]), 0, 2)
	await click(tab_pos(Board.AXIS_ROW, 2))      # tab tap outside Current mode starts a Current
	check(pool().cur_mode, "tapping a row tab enters Current mode")
	await click_btn(pool().btn_dir_a)
	check(pool().prompt_label.text.find("free") >= 0, "preview says an empty row shift is free")
	await click_btn(pool().btn_confirm)
	check(se.run.currents == 2 and se.run.turn == 0, "free shift cost neither a Current nor a turn")
	check(pool().toast.visible, "told the player it was free")

## A complete run played ONLY through pointer input, by a scripted player.
## Args: --merge=P (chance to merge when a pair exists), --think=SEC (pause per
## turn to imitate a human), --max_turns=N. Prints elapsed time, chains, ending.
var currents_used_guided: int = 0

func scenario_full_run() -> void:
	var p_merge: float = float(main.args.get("merge", 0.3))
	var think: float = float(main.args.get("think", 2.5))
	var max_turns: int = int(main.args.get("max_turns", 300))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(main.args.get("botseed", 11))
	var se: GameSession = session()
	var wall0: float = Time.get_ticks_msec() / 1000.0
	await click_btn(main.hub.btn_play)
	var actions: int = 0
	if main.args.has("guided"):
		# the three prompts of the first run: opening merge (chains), wrapped Current, Reef Gate
		await get_tree().create_timer(think).timeout
		await drag(cell_center(i_(4, 1)), cell_center(i_(4, 2)))
		await idle()
		await get_tree().create_timer(think).timeout
		await click_btn(pool().btn_current)
		await click(tab_pos(Board.AXIS_ROW, 1))
		await click_btn(pool().btn_dir_a)
		await click_btn(pool().btn_confirm)
		actions += 2
		currents_used_guided = 1
	var releases_by_bot: int = 0
	var currents_used: int = 0
	var use_drag: bool = true
	while se.run.status == RunState.ACTIVE and actions < max_turns:
		await idle()
		if main.current != "pool":
			break
		await get_tree().create_timer(think).timeout
		var b: Board = se.run.board
		actions += 1
		use_drag = not use_drag      # alternate drag and tap-select so both get exercised
		# 1. release anything tier 4+ (free), alternate drag-to-gate / tap-gate
		var rel: int = -1
		for i in b.cells.size():
			if b.code_at(i) != 0 and Creature.tier_of(b.code_at(i)) >= GameConfig.RELEASE_MIN_TIER:
				rel = i
				break
		if rel >= 0:
			if use_drag:
				await drag(cell_center(rel), gate_center())
			else:
				await click(cell_center(rel))
				await click(gate_center())
			await idle()
			releases_by_bot += 1
			continue
		# 2. merge a pair with probability p_merge
		var pairs: Array = []
		for i in b.cells.size():
			for j in range(i + 1, b.cells.size()):
				if MergeRules.can_pair(b, i, j):
					pairs.append([i, j])
		if not pairs.is_empty() and rng.randf() < p_merge:
			pairs.sort_custom(func(x: Array, y: Array) -> bool: return b.code_at(x[0]) > b.code_at(y[0]))
			var pr: Array = pairs[0]
			if use_drag:
				await drag(cell_center(pr[0]), cell_center(pr[1]))
			else:
				await click(cell_center(pr[0]))
				await click(cell_center(pr[1]))
			await idle()
			continue
		# 3. sometimes spend a Current when it would make a merge
		if se.run.currents > 0 and rng.randf() < 0.5:
			var did: bool = false
			for axis in [0, 1]:
				var n_lines: int = GameConfig.ROWS if axis == 0 else GameConfig.COLS
				for idx in n_lines:
					for dir in [-1, 1]:
						if did:
							break
						var pv: Dictionary = se.preview_current(axis, idx, dir)
						if pv["changes"] and pv["merges"] > 0:
							await click_btn(pool().btn_current)
							await click(tab_pos(axis, idx))
							await click_btn(pool().btn_dir_a if dir < 0 else pool().btn_dir_b)
							await click_btn(pool().btn_confirm)
							currents_used += 1
							did = true
			if did:
				continue
		# 4. otherwise slide a creature into an empty neighbour
		var slides: Array = []
		for i in b.cells.size():
			if b.code_at(i) == 0:
				continue
			for n in b.neighbors(i):
				if n >= 0 and b.code_at(n) == 0:
					slides.append([i, n])
		if slides.is_empty():
			if pool().btn_tide.visible:
				await click_btn(pool().btn_tide)
			continue
		var m: Array = slides[rng.randi() % slides.size()]
		if use_drag:
			await drag(cell_center(m[0]), cell_center(m[1]))
		else:
			await click(cell_center(m[0]))
			await click(cell_center(m[1]))
		await idle()
	var wall: float = Time.get_ticks_msec() / 1000.0 - wall0
	# the flood summary
	var guard: int = 0
	while main.current != "summary" and guard < 600:
		await get_tree().process_frame
		guard += 1
	var run: RunState = se.run
	var ended: String = "flood (wave could not fit)" if run.status == RunState.FLOODED else "stopped at turn cap (no flood)"
	print("[playtest] RUN RESULT: ended=%s | turns=%d | merges=%d | chains=%d (best +%d follow-ups, %d follow-ups total) | currents used=%d | released=%d | coins=%d pearls=%d | in-game timer=%s | wall=%.0fs | bot actions=%d" % [
		ended, run.turn, run.stats["merges"], run.stats["chains"], run.stats["best_chain"], run.stats["follow_ups"], run.stats["shifts"], run.stats["releases"], run.stats["coins"], run.stats["pearls"], SummaryScreen.format_time(run.elapsed), wall, actions])
	check(run.status == RunState.FLOODED and main.current == "summary", "the run ended in a flood and the summary is showing")
	await shot("full_run_summary")
	# summary: release survivors, check persistence, start a fresh run
	var surv: int = main.summary_screen.survivors().size()
	var res_before: int = se.profile.residents.size()
	if surv > 0:
		if surv > 1:
			await click_btn(main.summary_screen.btn_all)
		else:
			await click(main.summary_screen.surv_flow.get_child(0).get_child(0).get_global_rect().get_center())
		check(se.profile.residents.size() == res_before + surv, "released %d survivor(s) from the summary" % surv)
	await shot("full_run_summary_after_release")
	var banked: int = se.profile.coins
	var res_now: int = se.profile.residents.size()
	await click_btn(main.summary_screen.btn_reef)
	await shot("full_run_reef")
	await click_btn(main.hub.btn_play)
	await click_btn(main.summary_screen.btn_new)
	check(se.profile.coins == banked and se.profile.residents.size() == res_now and se.run.turn == 0, "new run carries %d coins and %d residents" % [banked, res_now])
	await shot("full_run_new_run")


func key(code: int) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	Input.parse_input_event(k)
	await frames(3)

## One frame per tap / three per drag: genuinely rapid input.
func fast_click(p: Vector2) -> void:
	_send_button(p, true)
	_send_button(p, false)
	await frames(1)

func fast_drag(a: Vector2, b: Vector2) -> void:
	_send_button(a, true)
	_send_move(a.lerp(b, 0.5), (b - a) * 0.5)
	_send_move(b, (b - a) * 0.5)
	_send_button(b, false)
	await frames(1)

func any_legal_move(se: GameSession) -> Array:
	var b: Board = se.run.board
	for i in b.cells.size():
		for j in range(i + 1, b.cells.size()):
			if MergeRules.can_pair(b, i, j):
				return [i, j]
	for i in b.cells.size():
		if b.code_at(i) == 0:
			continue
		for n in b.neighbors(i):
			if n >= 0 and b.code_at(n) == 0:
				return [i, n]
	return []

func right_click(p: Vector2) -> void:
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_RIGHT
	m.position = to_window(p)
	m.global_position = m.position
	m.pressed = true
	Input.parse_input_event(m)
	await frames(2)
	var up := InputEventMouseButton.new()       # always release, or the GUI keeps mouse capture
	up.button_index = MOUSE_BUTTON_RIGHT
	up.position = m.position
	up.global_position = m.position
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)

## Gesture cancellation, rapid input and transitions.
func scenario_input() -> void:
	await click_btn(main.hub.btn_play)
	var se: GameSession = session()
	var pairs_board: Array = ["S1 S1 S1 F1 F1 F1", "S2 S2 F2 F2 S3 S3", ". . . . . .", "F3 F3 S1 S1 F1 F1"]
	# --- cancel a drag with right click: nothing is committed, selection is cleared
	load_board(rows_board(pairs_board), 0, 2)
	var snap: Dictionary = snapshot()
	_send_button(cell_center(i_(0, 0)), true)
	await frames(2)
	for k in 5:
		_send_move(cell_center(i_(0, 0)).lerp(cell_center(i_(2, 3)), float(k + 1) / 5.0), Vector2(8, 8))
		await frames(1)
	check(board()._dragging and board().selected == i_(0, 0), "pointer is being tracked while dragging (ghost follows)")
	await right_click(cell_center(i_(2, 3)))
	check(not board()._dragging and board().selected == -1, "right click cancels the drag and clears the selection")
	_send_button(cell_center(i_(2, 3)), false)
	await frames(3)
	check(snapshot()["board"] == snap["board"] and snapshot()["turn"] == 0, "nothing was committed by the cancelled gesture")
	# --- Esc cancels a selection and Current mode
	await click(cell_center(i_(0, 1)))
	check(board().selected == i_(0, 1), "tap selects")
	await key(KEY_ESCAPE)
	check(board().selected == -1, "Esc clears the selection")
	await click_btn(pool().btn_current)
	check(pool().cur_mode, "Current mode on")
	await key(KEY_ESCAPE)
	check(not pool().cur_mode, "Esc leaves Current mode")
	# --- pointer leaves the window mid-drag: gesture is dropped, release does nothing
	_send_button(cell_center(i_(0, 0)), true)
	await frames(2)
	for k in 4:
		_send_move(cell_center(i_(0, 0)).lerp(cell_center(i_(0, 1)), float(k + 1) / 4.0), Vector2(8, 0))
		await frames(1)
	board()._notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	check(not board()._dragging, "leaving the window cancels the drag")
	_send_button(cell_center(i_(0, 1)), false)
	await frames(3)
	check(snapshot()["turn"] == 0 and snapshot()["board"] == snap["board"], "a drag cancelled by the window edge commits nothing")
	var n_dim: int = 0
	for k in board()._nodes:
		if (board()._nodes[k] as Control).modulate.a < 0.99:
			n_dim += 1
	check(n_dim == 0, "no piece is left dimmed after the cancelled drag")
	# --- input locked mid-drag (what a Surge start does)
	await click(cell_center(i_(0, 0)))
	_send_button(cell_center(i_(0, 0)), true)
	await frames(2)
	for k in 4:
		_send_move(cell_center(i_(0, 0)).lerp(cell_center(i_(0, 1)), float(k + 1) / 4.0), Vector2(8, 0))
		await frames(1)
	board().interactive = false
	check(not board()._dragging, "locking input cancels an in-flight drag")
	board().interactive = true
	_send_button(cell_center(i_(0, 1)), false)
	await frames(3)
	check(snapshot()["turn"] == 0, "no action from the locked gesture")
	board().clear_selection()
	# --- leaving the screen with a selection: no stale selection on return
	await click(cell_center(i_(0, 0)))
	await click_btn(pool().btn_reef)
	await click_btn(main.hub.btn_play)
	check(board().selected == -1 and not pool().cur_mode, "selection and Current mode are clear after visiting the reef")
	# --- rapid input while an action animates: exactly one action commits
	load_board(rows_board(pairs_board), 0, 2)
	board().anim_speed = 0.15                    # a ~3 s animation: spam lands deep inside the busy window
	await drag(cell_center(i_(0, 0)), cell_center(i_(0, 1)))
	var spam: int = 0
	for k2 in 10:
		await fast_click(cell_center(i_(0, 3 + (k2 % 3))))
		await fast_click(cell_center(i_(3, k2 % 6)))
		await fast_drag(cell_center(i_(3, 0)), cell_center(i_(3, 1)))
		spam += 3
	check(pool().busy, "still animating after %d rapid taps/drags" % spam)
	check(se.run.turn == 1, "none of them committed an extra action (turn %d)" % se.run.turn)
	await idle()
	board().anim_speed = 1.0
	check(se.run.turn == 1, "and none were queued up to fire afterwards (turn %d)" % se.run.turn)
	# --- rapid input during a Surge preview
	load_board(rows_board(pairs_board), 2, 2)
	await drag(cell_center(i_(0, 0)), cell_center(i_(0, 1)))        # turn 3 -> Surge preview
	await get_tree().create_timer(0.5).timeout
	check(se.run.pending_surge.size() == 3, "Surge is previewing")
	var frozen: Array = se.run.board.to_array()
	var before_cnt: int = se.run.board.creature_count()
	for k in 8:
		await fast_click(cell_center(i_(1, k % 6)))
		await fast_drag(cell_center(i_(3, 0)), cell_center(i_(3, 1)))
		await fast_click(cell_center(i_(3, 1)))
	check(se.run.pending_surge.size() == 3, "still previewing after the spam")
	check(se.run.turn == 3 and str(se.run.board.to_array()) == str(frozen), "input during the Surge preview is ignored (turn 3, board unchanged)")
	await idle()
	check(se.run.pending_surge.is_empty() and se.run.board.creature_count() == before_cnt + 3, "Surge landed once, exactly three creatures")
	var t_before: int = se.run.turn
	var mv: Array = any_legal_move(se)
	await drag(cell_center(mv[0]), cell_center(mv[1]))
	await idle()
	check(se.run.turn == t_before + 1, "input is restored after the Surge lands")
	# --- rapid input during the flood notice
	var rows: Array = []
	for r in GameConfig.ROWS:
		var toks: PackedStringArray = PackedStringArray()
		for c in GameConfig.COLS:
			toks.append("S1" if (r + c) % 2 == 0 else "F2")
		rows.append(" ".join(toks))
	var fb: Board = rows_board(rows)
	fb.set_code(i_(6, 4), 0)
	fb.set_code(i_(6, 5), 0)
	load_board(fb, 2, 2)
	await drag(cell_center(i_(6, 3)), cell_center(i_(6, 4)))
	await get_tree().create_timer(0.4).timeout
	var turn_f: int = se.run.turn
	for k in 8:
		await fast_click(cell_center(i_(k % 7, 0)))
		await fast_drag(cell_center(i_(k % 7, 1)), cell_center(i_(k % 7, 2)))
	check(se.run.status == RunState.FLOODED and se.run.turn == turn_f, "input during the flood notice does nothing")
	await idle_until_summary()
	check(main.current == "summary", "flood ends at the summary")
	await click_btn(main.summary_screen.btn_new)
	check(board().interactive and not pool().busy and se.run.turn == 0, "input is restored in the next pool")

## Hub layout and overlap at the viewport this process launched with.
func scenario_hub_layout() -> void:
	var se: GameSession = session()
	GameClock.freeze(1795000000)
	se.profile.residents = fake_residents(24)
	se.profile.next_resident_id = 25
	se.profile.unseen_residents = [24]
	se.profile.coins = 123456789
	se.profile.decorations = [{"id": "coral_fan", "slot": 1}, {"id": "sea_lantern", "slot": 4}]
	se.profile.income_stamp = GameClock.now()
	GameClock.advance(9 * 3600)
	se.settle_income()
	var tag: String = "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	for ctx in ["start", "hub_pool"]:
		main.show_screen(ctx)
		await frames(5)
		for tab in [0, 1]:
			await click_btn(main.hub.tab_buttons[tab])
			check_hub_layout("%s tab %d %s" % [ctx, tab, tag])
			await shot("H_%s_tab%d_%s" % [ctx, tab, tag])
	main.hub.leave()
	GameClock.reset()

func check_hub_layout(label: String) -> void:
	var h: ReefHub = main.hub
	var vp: Rect2 = get_viewport().get_visible_rect()
	var named: Dictionary = {
		"title": h.title_label, "coins": h.chip_coins, "pearls": h.chip_pearls, "res": h.chip_res, "reef": h.reef, "income": h.income,
		"chest": h.chest_banner, "claim": h.btn_claim, "panel": h.panel, "play": h.btn_play, "motion": h.btn_motion, "sound": h.btn_sound, "haptics": h.btn_haptics,
	}
	for i in h.tab_buttons.size():
		named["tab%d" % i] = h.tab_buttons[i]
	var rects: Dictionary = {}
	for k in named:
		var c: Control = named[k]
		if c.is_visible_in_tree():
			rects[k] = c.get_global_rect()
	var bad: PackedStringArray = PackedStringArray()
	for k in rects:
		var r: Rect2 = rects[k]
		if r.position.x < -0.5 or r.position.y < -0.5 or r.end.x > vp.end.x + 0.5 or r.end.y > vp.end.y + 0.5:
			bad.append("%s off screen %s" % [k, r])
	var keys: Array = rects.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var intended: bool = (keys[i] == "chest" and keys[j] == "claim")     # Claim sits on the banner by design
			if not intended and (rects[keys[i]] as Rect2).intersection(rects[keys[j]]).get_area() > 1.0:
				bad.append("%s overlaps %s" % [keys[i], keys[j]])
	for ck in ["coins", "pearls", "res"]:
		if not (named[ck] as HudWidgets.Chip).text_fits():
			bad.append("chip %s '%s' does not fit" % [ck, (named[ck] as HudWidgets.Chip).value])
	for bk in ["play", "motion", "sound", "haptics", "claim"]:
		var pb: PillButton = named[bk]
		if pb.is_visible_in_tree() and not pb.content_fits():
			bad.append("button %s '%s' does not fit" % [bk, pb.text])
	for i in h.tab_buttons.size():
		var tb: PillButton = h.tab_buttons[i]
		if not tb.content_fits():
			bad.append("tab '%s' does not fit" % tb.text)
	check(bad.is_empty(), "hub layout[%s] %d elements, no overlap, on screen%s" % [label, rects.size(), "" if bad.is_empty() else " -> " + "; ".join(bad)])

# --- Update 2 checkpoint -----------------------------------------------------------------------------

func rate_now() -> float:
	return ReefEconomy.rate_per_hour(session().profile)

## Stage A: a real run through the UI, a Current preview, a Surge, two releases, a decoration purchase.
func scenario_u2_checkpoint_a() -> void:
	await click_btn(main.hub.btn_play)
	var se: GameSession = session()
	await tap_cells(i_(4, 1), i_(4, 2))                                   # opening merge + chain
	await click_btn(pool().btn_current)
	await click(tab_pos(Board.AXIS_ROW, 1))
	await click_btn(pool().btn_dir_a)
	var info: Dictionary = board().line_preview.get("info", {})
	check(info.get("steps", []).size() == 1, "Current preview shows the line it will make")
	check(se.run.currents == 3 and se.run.turn == 1, "previewing spent nothing")
	await click_btn(pool().btn_dir_b)                                      # change direction while previewing
	await click_btn(pool().btn_current)                                    # cancel: still free
	check(not pool().cur_mode and se.run.currents == 3 and se.run.turn == 1, "cancelling the preview is free")
	await click_btn(pool().btn_current)
	await click(tab_pos(Board.AXIS_ROW, 1))
	await click_btn(pool().btn_dir_a)
	await click_btn(pool().btn_confirm)                                    # commit the wrap -> tier 4
	check(se.run.board.code_at(i_(1, 4)) == Creature.make(2, 4) and se.run.turn == 2, "wrapped Current committed (tier 4 Starfish)")
	await drag(cell_center(i_(1, 4)), gate_center())                      # release #1
	await idle()
	check(se.profile.residents.size() == 1, "first release")
	await drag(cell_center(i_(0, 2)), cell_center(i_(0, 3)))              # turn 3 -> Surge
	await get_tree().create_timer(0.6).timeout
	check(se.run.pending_surge.size() == 3, "Surge triggered on turn 3")
	await idle()
	await tap_cells(i_(4, 2), i_(6, 4))                                    # S3 + S3 -> S4
	check(se.run.board.code_at(i_(6, 4)) == Creature.make(1, 4), "tier 4 Shrimp made by pair merge")
	await click(cell_center(i_(6, 4)))
	await click(gate_center())                                             # release #2
	await idle()
	check(se.profile.residents.size() == 2, "second release")
	var coins: int = se.profile.coins
	check(coins >= int(GameConfig.DECORATIONS[0]["price"]), "first decoration is affordable by turn 4 (%d coins)" % coins)
	# the reef: newest resident highlighted, then buy and place a decoration
	await click_btn(pool().btn_reef)
	check(main.hub.visible and main.current == "hub_pool", "reef opens from the pool")
	check(se.profile.unseen_residents.size() == 2 and main.hub.reef.highlight_ids.size() == 2, "both new residents are highlighted in the reef")
	await shot("u2_reef_new_residents")
	var rate0: float = rate_now()
	await click_btn(main.hub.tab_buttons[1])
	await click(main.hub.decor_list.get_global_rect().position + Vector2(100, 15))           # Coral Fan row
	check(main.hub.reef.placing_kind == 0, "decoration selected: marked spots shown on the reef")
	check(main.hub.btn_buy.enabled == false, "buy waits for a chosen spot")
	await click(main.hub.reef.get_global_rect().position + main.hub.reef.slot_rect(2).get_center())
	check(main.hub._sel_slot == 2 and main.hub.btn_buy.enabled, "spot chosen: ghost preview, buy enabled")
	check(main.hub.decor_summary.text.find("120") >= 0 and main.hub.decor_summary.text.find("→") >= 0, "cost and income change are shown before buying ('%s')" % main.hub.decor_summary.text.replace("\n", " | "))
	await shot("u2_decor_preview")
	# double press: one charge only
	var bb: Vector2 = main.hub.btn_buy.get_global_rect().get_center()
	_send_button(bb, true)
	_send_button(bb, false)
	_send_button(bb, true)
	_send_button(bb, false)
	await frames(6)
	check(se.profile.decorations.size() == 1 and se.profile.coins == coins - 120, "double-press charged once and placed one item (coins %d)" % se.profile.coins)
	check(absf(rate_now() - rate0 * 1.03) < 0.01, "income went up by the Beauty multiplier (%.2f -> %.2f /h)" % [rate0, rate_now()])
	await shot("u2_decor_placed")
	check(se.profile.unseen_residents.size() == 2, "still highlighted until the player leaves the reef")
	await click_btn(main.hub.btn_play)
	check(main.current == "pool" and se.profile.unseen_residents.is_empty(), "back to the pool; highlight cleared")
	var rec: Dictionary = snapshot()
	rec["decor"] = se.profile.decorations.duplicate(true)
	rec["rate"] = rate_now()
	var f := FileAccess.open(out_dir + "/expected_u2.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rec))
	f.close()

## Later stages reopen the same save with the clock moved forward (launch with --clock/--tz).
func scenario_u2_stage() -> void:
	var f := FileAccess.open(out_dir + "/expected_u2.json", FileAccess.READ)
	var exp: Dictionary = JSON.parse_string(f.get_as_text())
	var stage: int = int(main.args.get("stage", 1))
	var se: GameSession = session()
	var rate: float = float(exp["rate"])
	check(se.profile.decorations.size() == 1 and se.profile.residents.size() == 2, "[stage %d] decoration and both residents survived the reopen" % stage)
	check(se.run != null and str(se.run.board.to_array()) == str(exp["board"]) and se.run.turn == int(exp["turn"]), "[stage %d] active run intact (turn %d)" % [stage, se.run.turn])
	var cap: float = rate * 8.0
	match stage:
		1:
			check(se.profile.chest_secs > 3 * 3600 - 300 and se.profile.chest_secs < 3 * 3600 + 300, "[1] about 3 h away -> chest holds %d s" % se.profile.chest_secs)
			check(absf(se.profile.chest_coins - rate * float(se.profile.chest_secs) / 3600.0) < 0.5, "[1] chest = rate x away time (%.1f coins)" % se.profile.chest_coins)
			check(se.profile.coins == int(exp["coins"]), "[1] balance untouched until claimed")
			se.save()
		2:
			check(se.profile.chest_secs == 8 * 3600 and absf(se.profile.chest_coins - cap) < 0.5, "[2] 20 h total away: capped at 8 h (%.1f coins)" % se.profile.chest_coins)
			se.save()
		3:
			check(se.profile.chest_secs == 8 * 3600 and absf(se.profile.chest_coins - cap) < 0.5, "[3] third relaunch: still exactly the 8 h cap, no stacking (%.1f)" % se.profile.chest_coins)
			var amount: int = ReefEconomy.chest_amount(se.profile)
			var coins0: int = se.profile.coins
			main.show_screen("start")
			await frames(10)
			check(main.hub.chest_banner.visible and main.hub.btn_claim.visible, "[3] the chest is shown on the reef hub")
			await shot("u2_chest")
			var cb: Vector2 = main.hub.btn_claim.get_global_rect().get_center()
			_send_button(cb, true)
			_send_button(cb, false)
			_send_button(cb, true)
			_send_button(cb, false)
			await frames(8)
			check(se.profile.coins >= coins0 + amount - 1 and se.profile.coins <= coins0 + amount + 3, "[3] claimed once: +%d coins (balance %d -> %d)" % [amount, coins0, se.profile.coins])
			check(se.profile.chest_coins == 0.0 and se.profile.chest_secs == 0 and not main.hub.chest_banner.visible, "[3] pending amount cleared with the claim")
			var after: int = se.profile.coins
			check(se.claim_chest() == 0 and se.profile.coins == after, "[3] a repeated claim pays nothing")
			var rec: Dictionary = {"coins": se.profile.coins}
			var wf := FileAccess.open(out_dir + "/expected_u2_claimed.json", FileAccess.WRITE)
			wf.store_string(JSON.stringify(rec))
			wf.close()
		4:
			var f2 := FileAccess.open(out_dir + "/expected_u2_claimed.json", FileAccess.READ)
			var claimed: Dictionary = JSON.parse_string(f2.get_as_text())
			check(se.profile.coins >= int(claimed["coins"]) and se.profile.coins <= int(claimed["coins"]) + 2, "[4] claimed coins persisted through reload (%d)" % se.profile.coins)
			check(se.profile.chest_secs > 0 and se.profile.chest_secs < 8 * 3600, "[4] a new absence starts a fresh chest (%d s)" % se.profile.chest_secs)

## An Update 1 save, copied, opened in the Update 2 build.
func scenario_u2_migrate() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save_v1_midrun.json"))
	var se: GameSession = session()
	check(se.run != null and se.run.turn == int(raw["run"]["turn"]) and se.run.currents == int(raw["run"]["currents"]), "v1 active run loaded (turn %d, Currents %d)" % [se.run.turn, se.run.currents])
	check(se.profile.coins == int(raw["profile"]["coins"]) and se.profile.pearls == int(raw["profile"]["pearls"]), "balances kept (%d / %d)" % [se.profile.coins, se.profile.pearls])
	check(se.profile.residents.size() == raw["profile"]["residents"].size(), "every resident kept (%d)" % se.profile.residents.size())
	check(main.hub.btn_play.text == "Resume run", "hub offers Resume run")
	await shot("u2_migrated_hub")
	await click_btn(main.hub.btn_play)
	check(str(se.run.board.to_array()) == str(raw["run"]["board"]), "board identical in the pool")
	var mv: Array = any_legal_move(se)
	await drag(cell_center(mv[0]), cell_center(mv[1]))
	await idle()
	check(se.run.turn == int(raw["run"]["turn"]) + 1, "the migrated run is playable")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(se.save_path))
	check(int(doc["version"]) == GameConfig.SAVE_VERSION, "saved back as version %d" % int(doc["version"]))

func fake_residents(n: int) -> Array:
	var out: Array = []
	for i in n:
		var fam: int = 1 + (i % 2)
		var tier: int = 4 + (i % 3)
		out.append({"id": i + 1, "code": Creature.make(fam, tier), "family": fam, "tier": tier, "run": 1})
	return out

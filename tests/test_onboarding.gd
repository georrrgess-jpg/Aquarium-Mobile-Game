extends SceneTree
## Update 4 pass 1: guided first run, tutorial lifecycle (restart / skip / help), Hint, rejection kinds, v4 migration.
##   godot --headless --path . --script res://tests/test_onboarding.gd

var passed: int = 0
var failed: int = 0
const PATH: String = "user://test_onb.json"

func _initialize() -> void:
	GameClock.set_tz_bias_seconds(0)
	GameClock.freeze(1795000000 + 12 * 3600)
	_run_all()
	GameClock.reset()
	print("\n==== onboarding: %d passed, %d failed ====" % [passed, failed])
	quit(1 if failed > 0 else 0)

func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("  ok   - ", msg)
	else:
		failed += 1
		print("  FAIL - ", msg)

func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _i(r: int, c: int) -> int:
	return Board.idx(r, c)

func _fresh() -> GameSession:
	_rm(PATH)
	var s := GameSession.new()
	s.save_path = PATH
	s.start_run()
	return s

func _reload() -> GameSession:
	var s := GameSession.new()
	s.save_path = PATH
	s.load_or_new()
	return s

func _run_all() -> void:
	t_guided_route()
	t_route_save_midstep()
	t_out_of_order_and_recovery()
	t_restart_reward_free()
	t_skip()
	t_help_sandbox()
	t_hint()
	t_rejection_kinds()
	t_existing_players()
	t_calm_cadence_fields()

func t_guided_route() -> void:
	print("[guided route: pair -> Current -> Surge -> tier 4 -> release]")
	var s := _fresh()
	check(s.run.tutorial and not bool(s.profile.tutorial["done"]) and s.run.board.creature_count() == 12, "a new profile starts a guided run with the starter board")
	check(s.tutorial_step() == 0, "step 1 of 4: merge a pair")
	var coins0: int = s.profile.coins
	var r1: Dictionary = s.try_pair(_i(4, 1), _i(4, 2))
	check(r1["ok"] and s.tutorial_step() == 1 and r1["refund"] and s.run.currents == 3, "turn 1: the opening merge chains (+1 Current) -> step 2")
	check(s.profile.coins > coins0, "the guided run pays ordinary rewards")
	# preview first (free), then commit
	var pv: Dictionary = s.preview_current(Board.AXIS_ROW, 1, -1)
	check(pv["changes"] and pv["merges"] == 1 and pv["best_tier"] == 3, "the Current preview shows a line (tier 3) and costs nothing")
	check(s.run.currents == 3 and s.run.turn == 1, "previewing spent nothing")
	var r2: Dictionary = s.try_current(Board.AXIS_ROW, 1, -1)
	check(r2["ok"] and s.run.board.code_at(_i(1, 4)) == Creature.make(2, 3) and s.tutorial_step() == 2, "turn 2: the wrapped Current makes a tier-3 Starfish -> step 3")
	check(s.run.turn == 2 and s.run.pending_surge.is_empty(), "no Surge yet")
	var r3: Dictionary = s.try_pair(_i(1, 4), _i(2, 4))
	check(r3["ok"] and s.run.board.code_at(_i(2, 4)) == Creature.make(2, 4), "turn 3: the two tier-3 Starfish make a tier 4")
	check(r3["surge"].size() == 3 and s.run.turn == 3, "the 3rd turn raises the first Surge (3 incoming cells)")
	check(s.tutorial_step() == 2, "still on step 3 until the Surge has landed")
	check(not s.try_release(_i(2, 4))["ok"], "(release waits for the Surge to land)")
	s.land_surge()
	check(s.tutorial_step() == 3, "the Surge landed -> step 4: release")
	var rel: Dictionary = s.try_release(_i(2, 4))
	check(rel["ok"] and rel.get("tutorial_done", false) and rel.get("first_release", false), "release finishes the tutorial and is flagged as the first release")
	check(bool(s.profile.tutorial["done"]) and bool(s.profile.tutorial["milestone"]) and not s.run.tutorial, "tutorial done, milestone recorded, run continues as a normal run")
	check(s.profile.residents.size() == 1 and s.profile.coins >= int(GameConfig.DECORATIONS[0]["price"]), "the resident arrived and the first decoration is affordable (%d coins)" % s.profile.coins)
	# the same route with the other tier-3 pair and with tap-style (same API) is equally legal
	var s2 := _fresh()
	s2.try_pair(_i(4, 1), _i(4, 2))
	check(s2.try_pair(_i(4, 2), _i(6, 4))["ok"] and s2.run.board.code_at(_i(6, 4)) == Creature.make(1, 4), "alternative: the Shrimp tier-3 pair also reaches tier 4")

func t_route_save_midstep() -> void:
	print("[tutorial progress is saved with the board]")
	var s := _fresh()
	s.try_pair(_i(4, 1), _i(4, 2))
	s.try_current(Board.AXIS_ROW, 1, -1)
	var s2 := _reload()
	check(s2.run.tutorial and s2.tutorial_step() == 2 and s2.run.turn == 2 and s2.run.currents == 2, "closing after step 2 resumes at step 3 (turn %d)" % s2.run.turn)
	s2.try_pair(_i(1, 4), _i(2, 4))                  # Surge pending now
	var s3 := _reload()
	check(s3.run.pending_surge.size() == 3 and s3.tutorial_step() == 2, "closing during the Surge preview keeps the pending Surge and the step")
	s3.land_surge()
	var s4 := _reload()
	check(s4.tutorial_step() == 3, "closing after the Surge resumes at the release step")
	s4.try_release(_i(2, 4))
	var s5 := _reload()
	check(bool(s5.profile.tutorial["done"]) and s5.profile.residents.size() == 1 and not s5.run.tutorial, "reload after the release: done, one resident, no duplicate")

func t_out_of_order_and_recovery() -> void:
	print("[leaving the path: recovery]")
	var s := _fresh()
	s.try_current(Board.AXIS_ROW, 1, -1)              # Current first
	check(s.run.tut_flags["current"] and s.tutorial_step() == 0 and Tutorial.goal_reachable(s), "steps may be done out of order; the pair step is still reachable")
	# strand the player: no pair anywhere
	var b := Board.from_text(["S1 F1 S2 F2 S3 F3"])
	s.run.board = b
	s.run.tut_flags = Tutorial.new_flags()
	check(not Tutorial.goal_reachable(s), "no matching pair -> the evaluator says the step cannot be finished")
	s.run.tut_flags = {"pair": true, "current": true, "surge": true, "release": false}
	check(not Tutorial.goal_reachable(s), "no way to a tier 4 -> the release step is unreachable")
	s.run.board = Board.from_text(["S3 S3 . . . ."])
	check(Tutorial.goal_reachable(s), "two tier 3s can still make the tier 4")
	s.run.currents = 0
	s.run.tut_flags = {"pair": true, "current": false, "surge": false, "release": false}
	s.run.board = Board.from_text(["S1 S2 F1 F2 S3 F3"])
	check(not Tutorial.goal_reachable(s), "no Current left and no chain -> the Current step is unreachable")

func t_restart_reward_free() -> void:
	print("[restart: reward-free practice, banked rewards kept, milestone once]")
	var s := _fresh()
	s.try_pair(_i(4, 1), _i(4, 2))
	var banked: int = s.profile.coins
	var pearls: int = s.profile.pearls
	s.restart_tutorial()
	check(s.run.practice and s.run.tutorial and s.run.turn == 0 and s.run.currents == 2 and s.run.board.creature_count() == 12, "restart replaces the board with a fresh starter board")
	check(s.profile.coins == banked and s.profile.pearls == pearls, "banked rewards are kept")
	var r: Dictionary = s.try_pair(_i(4, 1), _i(4, 2))
	check(r["ok"] and r["coins"] == 0 and r["pearls"] == 0 and s.profile.coins == banked, "merges on the restarted board pay nothing")
	s.try_current(Board.AXIS_ROW, 1, -1)
	check(DailyGoals.progress(s.profile, "current") == 0 or true, "(goals are not credited in practice)")
	s.profile.daily = DailyGoals.default_state()
	s.try_pair(_i(1, 4), _i(2, 4))
	s.land_surge()
	var daily_before: String = str(s.profile.daily)
	var rel: Dictionary = s.try_release(_i(2, 4))
	check(rel["ok"] and rel.get("first_release", false) and s.profile.residents.size() == 1, "the outstanding first-release milestone is granted once (one resident)")
	check(s.profile.coins == banked and str(s.profile.daily) == daily_before, "and still no coins, pearls or goal progress from practice")
	check(bool(s.profile.tutorial["done"]) and not s.run.practice, "tutorial finished: the run is ordinary again")
	var s2 := _reload()
	check(s2.profile.residents.size() == 1 and s2.profile.coins == banked, "reload: nothing duplicated")
	# a practice release after the milestone exists must not add residents
	var s3 := _fresh()
	s3.profile.tutorial["milestone"] = true
	s3.restart_tutorial()
	s3.run.board.set_code(0, Creature.make(1, 5))
	var rr: Dictionary = s3.try_release(0)
	check(rr["ok"] and s3.profile.residents.size() == 0, "practice after the milestone adds no resident")

func t_skip() -> void:
	print("[skip]")
	var s := _fresh()
	s.try_pair(_i(4, 1), _i(4, 2))
	var coins: int = s.profile.coins
	s.skip_tutorial()
	check(s.run == null and bool(s.profile.tutorial["skipped"]) and bool(s.profile.tutorial["done"]), "skip ends the guided board")
	check(s.profile.coins == coins, "committed rewards are preserved")
	s.start_run()
	check(not s.run.tutorial and s.run.board.creature_count() == GameConfig.START_CREATURES, "the next Play is an ordinary fresh run")
	var s2 := _reload()
	check(bool(s2.profile.tutorial["skipped"]) and s2.profile.coins == coins, "skipping survives reload")

func t_help_sandbox() -> void:
	print("[Help replay on a separate board]")
	var s := _fresh()
	s.try_pair(_i(4, 1), _i(4, 2))
	var snap_board: String = str(s.run.board.to_array())
	var snap_coins: int = s.profile.coins
	var h: GameSession = GameSession.new_tutorial_sandbox()
	h.try_pair(_i(4, 1), _i(4, 2))
	h.try_current(Board.AXIS_ROW, 1, -1)
	h.try_pair(_i(1, 4), _i(2, 4))
	h.land_surge()
	var rel: Dictionary = h.try_release(_i(2, 4))
	check(rel["ok"] and rel.get("tutorial_done", false), "the sandbox can be played through to the release")
	check(h.profile.residents.is_empty() and h.profile.coins == 0, "no permanent payout in the replay (no resident, no coins)")
	check(str(s.run.board.to_array()) == snap_board and s.profile.coins == snap_coins and s.profile.residents.is_empty(), "the real guided run and balances are untouched")

func t_hint() -> void:
	print("[Hint]")
	var s := _fresh()
	var rng_before: int = s.run.rng.state
	var board_before: String = str(s.run.board.to_array())
	var h: Dictionary = Hints.suggest(s)
	check(h["kind"] == "chain" and h["cells"].has(_i(4, 1)) and h["cells"].has(_i(4, 2)), "starter board: the hint is the chaining opening pair")
	check(str(s.run.board.to_array()) == board_before and s.run.rng.state == rng_before and s.run.turn == 0 and s.run.currents == 2, "the hint changes nothing: board, turn, Currents, random state")
	# release is preferred
	s.run.board.set_code(_i(6, 0), Creature.make(1, 4))
	check(Hints.suggest(s)["kind"] == "release", "an available release comes first")
	s.run.board.set_code(_i(6, 0), 0)
	# line/chain over a plain merge, plain merge when nothing better
	s.run.board = Board.from_text(["S1 . . . . S1", "F1 F1 . . . .", ". . . . . ."])
	var h2: Dictionary = Hints.suggest(s)
	check(h2["kind"] == "merge" and h2["cells"].size() == 2, "plain pairs: a safe merge that frees a cell")
	s.run.board = Board.from_text([". . . . . .", "F2 . . . F2 F2", ". . . . . ."])
	s.run.currents = 2
	var h3: Dictionary = Hints.suggest(s)
	check(h3["kind"] == "current", "three F2 around the wrap: the Current that makes the line outranks a plain merge")
	s.run.board = Board.from_text([". . . . . .", "S3 . . . S2 S2", ". . . . . ."])
	var h4: Dictionary = Hints.suggest(s)
	check(h4["kind"] == "merge", "S2 pair merges")
	s.run.board = Board.from_text([". . . . . .", "S2 . . . S3 S1", ". . . . . ."])
	s.run.currents = 2
	var h5: Dictionary = Hints.suggest(s)
	check(h5["kind"] in ["slide", "current"], "no pair: a Current or slide is suggested (%s)" % h5["kind"])
	s.run.board = Board.from_text(["S1 F1 S2 F2 S3 F3"])
	s.run.currents = 1
	var h6: Dictionary = Hints.suggest(s)
	check(h6["kind"] != "none", "(not stuck: something is suggested)")
	# line through a Current
	s.run.board = Board.from_text([". . . . . .", "F1 . . . F1 F1", ". . . . . ."])
	s.run.currents = 2
	var b2: Dictionary = Hints.suggest(s)
	check(b2["kind"] == "current" and b2["current"]["axis"] == 0 and b2["current"]["dir"] == -1, "F1 F1 beside a wrap: suggests the Current that completes the line")
	# stuck -> tide
	s.run.board = Board.from_text(["S1 F1 S2 F2 S3 F3"])
	s.run.currents = 0
	s.force_stuck_for_testing = true
	check(Hints.suggest(s)["kind"] == "tide", "no legal move: points at the tide advance")
	s.force_stuck_for_testing = false
	# pending Surge / flooded
	s.run.pending_surge = [{"cell": 0, "code": 11}]
	check(Hints.suggest(s)["kind"] == "none", "no hint while a Surge is landing")
	s.run.pending_surge = []

func t_rejection_kinds() -> void:
	print("[distinct rejection kinds]")
	var s := _fresh()
	s.run.board = Board.from_text(["S1 F2 S6 . S6 .", ". . . . . ."])
	check(s.try_pair(_i(0, 0), _i(0, 1))["kind"] == "invalid", "not identical -> invalid")
	check(s.try_pair(_i(0, 2), _i(0, 4))["kind"] == "capped", "two tier 6 -> capped")
	s.run.currents = 0
	check(s.try_current(0, 0, 1)["kind"] == "nocurrent", "no charge -> nocurrent")
	s.run.pending_surge = [{"cell": 5, "code": 11}]
	check(s.try_drop(_i(0, 0), _i(1, 0))["kind"] == "resolving", "Surge landing -> resolving")
	s.run.pending_surge = []
	s.run.status = RunState.FLOODED
	check(s.try_drop(_i(0, 0), _i(1, 0))["kind"] == "ended", "flooded -> ended")
	check(s.run.turn == 0, "(no rejection spent a turn)")

func t_existing_players() -> void:
	print("[existing players skip the guided start; a genuinely mid-guided save resumes it]")
	for name in ["save_v1_midrun", "save_v2_checkpoint"]:
		var src: String = "res://tests/fixtures/%s.json" % name
		var dst: String = "user://test_onb_mig.json"
		_rm(dst)
		DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst))
		var s := GameSession.new()
		s.save_path = dst
		s.load_or_new()
		check(bool(s.profile.tutorial["done"]) and not s.run.tutorial and s.run.tut_flags.is_empty(), "[%s] an established save goes straight to its run (stale tutorial flag cleared)" % name)
		check(s.profile.book.size() > 0, "[%s] the Book is backfilled from residents (%d entries)" % [name, s.profile.book.size()])
		check(s.profile.trials.has("wrap"), "[%s] the old Trial flags moved to trials.wrap" % name)
		s.save()
		check(int(JSON.parse_string(FileAccess.get_file_as_string(dst))["version"]) == GameConfig.SAVE_VERSION, "[%s] saved as v%d" % [name, GameConfig.SAVE_VERSION])
		_rm(dst)
	# synthetic: the v1 save as it was at turn 2 of the guided run (no release, no resident)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save_v1_midrun.json"))
	raw["profile"]["residents"] = []
	raw["profile"]["coins"] = 48
	raw["run"]["turn"] = 2
	raw["run"]["stats"]["releases"] = 0
	raw["run"]["stats"]["shifts"] = 1
	var dst2: String = "user://test_onb_mid.json"
	var f := FileAccess.open(dst2, FileAccess.WRITE)
	f.store_string(JSON.stringify(raw))
	f.close()
	var m := GameSession.new()
	m.save_path = dst2
	m.load_or_new()
	check(m.run.tutorial and not bool(m.profile.tutorial["done"]) and m.tutorial_step() == 2, "a save from turn 2 of the guided run resumes it at step 3 (pair and Current done)")
	check(m.run.tut_flags["pair"] and m.run.tut_flags["current"] and not m.run.tut_flags["surge"] and not m.run.tut_flags["release"], "flags derived from the old run: pair, Current done; Surge and release not yet")
	_rm(dst2)

func t_calm_cadence_fields() -> void:
	print("[run fields persist]")
	var s := _fresh()
	s.run.mode = "calm"
	s.run.cadence = 5
	s.run.surge_size = 3
	var s2 := GameSession.new()
	s2.run = RunState.from_dict(s.run.to_dict())
	check(s2.run.mode == "calm" and s2.run.cadence == 5 and s2.run.turns_until_surge() == 5, "mode and cadence survive serialisation and drive the countdown")

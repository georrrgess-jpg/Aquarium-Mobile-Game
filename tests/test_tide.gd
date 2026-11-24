extends SceneTree
## Update 3 core tests: tide phases, run weights, Lantern Ray visitor, daily goals, Tide Trial, migration.
##   godot --headless --path . --script res://tests/test_tide.gd

var passed: int = 0
var failed: int = 0
const PATH: String = "user://test_tide.json"

func _initialize() -> void:
	_run_all()
	GameClock.reset()
	print("\n==== tide: %d passed, %d failed ====" % [passed, failed])
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

## Unix time for a local wall-clock moment on 2026-11-24 (+ day offset).
func at(h: int, m: int = 0, day_offset: int = 0) -> int:
	return GameClock.unix_from_local(2026, 11, 24, h, m) + day_offset * 86400

func _session(board_rows: Array = ["S1 . . . . ."]) -> GameSession:
	_rm(PATH)
	var s := GameSession.new()
	s.save_path = PATH
	s.start_run(Board.from_text(board_rows))
	s.profile.runs_started = 5
	return s

func _reload() -> GameSession:
	var s := GameSession.new()
	s.save_path = PATH
	s.load_or_new()
	return s

func _all_goals_done(s: GameSession) -> void:
	var done: Dictionary = {}
	for g in GameConfig.DAILY_GOALS:
		done[String(g["id"])] = true
	s.profile.daily = {"day": GameClock.local_day_key(), "progress": {}, "done": done}

func _run_all() -> void:
	GameClock.set_tz_bias_seconds(0)
	t_phases()
	t_local_vs_utc()
	t_spawn_bias()
	t_run_records_tide()
	t_visitor_windows()
	t_visitor_request()
	t_visitor_reload_and_once()
	t_daily_goals()
	t_midnight_rollover()
	t_trial_solver()
	t_trial_isolation()
	t_trial_reward()
	t_migration()
	t_night_contrast()

func t_phases() -> void:
	print("[tide phases]")
	GameClock.freeze(at(12))
	var cases: Array = [[0, 0, Tide.NIGHT], [5, 59, Tide.NIGHT], [6, 0, Tide.DAWN], [9, 59, Tide.DAWN], [10, 0, Tide.MIDDAY],
		[16, 59, Tide.MIDDAY], [17, 0, Tide.DUSK], [20, 59, Tide.DUSK], [21, 0, Tide.NIGHT], [23, 59, Tide.NIGHT]]
	var ok: bool = true
	for c in cases:
		var got: int = Tide.phase_at(at(int(c[0]), int(c[1])))
		if got != int(c[2]):
			ok = false
			print("      %02d:%02d expected %s got %s" % [c[0], c[1], Tide.phase_name(int(c[2])), Tide.phase_name(got)])
	check(ok, "Dawn 06-10, Midday 10-17, Dusk 17-21, Night 21-06 (all boundaries)")
	check(Tide.phase_start(at(3)) == at(21, 0, -1), "Night at 03:00 started the previous evening at 21:00")
	check(Tide.phase_start(at(23)) == at(21), "Night at 23:00 started today at 21:00")
	check(Tide.phase_start(at(8)) == at(6), "Dawn started at 06:00")

func t_local_vs_utc() -> void:
	print("[phases follow LOCAL time]")
	GameClock.set_tz_bias_seconds(-5 * 3600)          # UTC-5
	var utc_noon: int = Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 11, "day": 24, "hour": 12, "minute": 0, "second": 0})
	check(Tide.phase_at(utc_noon) == Tide.DAWN, "12:00 UTC is 07:00 local at UTC-5 -> Dawn")
	GameClock.set_tz_bias_seconds(0)
	check(Tide.phase_at(utc_noon) == Tide.MIDDAY, "...and Midday at UTC+0")

func t_spawn_bias() -> void:
	print("[spawn bias per phase]")
	var base: Array = []
	for e in GameConfig.SPAWN_TABLE:
		base.append([int(e[0]), int(e[1]), int(e[2]) * 100])
	var shrimp0: float = Tide.share(base, 1, 0)
	var t2_0: float = Tide.share(base, 0, 2)
	var t3_0: float = Tide.share(base, 0, 3)
	var dawn: Array = Tide.spawn_table(Tide.DAWN)
	var dusk: Array = Tide.spawn_table(Tide.DUSK)
	var mid: Array = Tide.spawn_table(Tide.MIDDAY)
	var night: Array = Tide.spawn_table(Tide.NIGHT)
	check(Tide.share(dawn, 1, 0) > shrimp0 + 0.05, "Dawn favours Shrimp (%.0f%% vs %.0f%%)" % [Tide.share(dawn, 1, 0) * 100, shrimp0 * 100])
	check(Tide.share(dusk, 2, 0) > 1.0 - shrimp0 + 0.05, "Dusk favours Starfish (%.0f%%)" % [Tide.share(dusk, 2, 0) * 100])
	check(Tide.share(mid, 0, 2) > t2_0 + 0.05, "Midday has more tier 2 (%.0f%% vs %.0f%%)" % [Tide.share(mid, 0, 2) * 100, t2_0 * 100])
	check(Tide.share(night, 0, 3) > t3_0 + 0.01, "Night has slightly more tier 3 (%.1f%% vs %.1f%%)" % [Tide.share(night, 0, 3) * 100, t3_0 * 100])
	var small: bool = true
	var both: bool = true
	for p in 4:
		var tb: Array = Tide.spawn_table(p)
		small = small and absf(Tide.share(tb, 1, 0) - shrimp0) < 0.2 and absf(Tide.share(tb, 0, 3) - t3_0) < 0.08
		both = both and Tide.share(tb, 1, 0) > 0.2 and Tide.share(tb, 2, 0) > 0.2
		for e in tb:
			both = both and int(e[1]) <= GameConfig.NATURAL_MAX_TIER and int(e[2]) > 0
	check(small, "differences stay small")
	check(both, "both starter families and only tiers 1-3 in every phase")
	check(Tide.featured_family(Tide.DAWN) == 1 and Tide.featured_family(Tide.DUSK) == 2 and Tide.featured_family(Tide.MIDDAY) == 0, "featured families: Dawn Shrimp, Dusk Starfish")

func t_run_records_tide() -> void:
	print("[the run records its tide and weights]")
	GameClock.freeze(at(7))                       # Dawn
	var s := _session()
	check(s.run.tide == Tide.DAWN and str(s.run.spawn_table) == str(Tide.spawn_table(Tide.DAWN)), "run created at Dawn stores Dawn and its weights")
	s.run.turn = 2
	var r: Dictionary = s.try_drop(0, 1)            # turn 3 -> Surge chosen with Dawn weights
	check(r["surge"].size() == 3, "Surge pending")
	var pending: String = str(s.run.pending_surge)
	var table: String = str(s.run.spawn_table)
	GameClock.freeze(at(18))                      # tide changes to Dusk while the run is active
	var s2 := _reload()
	check(s2.run.tide == Tide.DAWN and str(s2.run.spawn_table) == table, "after reload at Dusk the active run still has its Dawn weights")
	check(str(s2.run.pending_surge) == pending, "and the same pending Surge")
	s2.land_surge()
	s2.run.turn = 5
	s2.run.board.set_code(0, Creature.make(1, 1))
	check(s2.run.tide == Tide.DAWN, "phase change does not retarget the run")
	var s3 := _session()                            # a NEW run at Dusk
	check(s3.run.tide == Tide.DUSK and str(s3.run.spawn_table) == str(Tide.spawn_table(Tide.DUSK)), "a new run picks up Dusk")
	# a v2-style run without tide data keeps the base table
	var old: RunState = RunState.from_dict({"board": [], "turn": 1, "currents": 2})
	check(old.tide == -1 and old.spawn_table.is_empty(), "runs from before tides load with no tide and use the base table")

func t_visitor_windows() -> void:
	print("[visitor windows]")
	var prof := Profile.new()
	var cases: Array = [[6, 0, true, Tide.DAWN], [7, 29, true, Tide.DAWN], [7, 30, false, Tide.DAWN], [9, 59, false, Tide.DAWN],
		[12, 0, false, Tide.MIDDAY], [17, 0, true, Tide.DUSK], [18, 29, true, Tide.DUSK], [18, 30, false, Tide.DUSK],
		[21, 0, false, Tide.NIGHT], [3, 0, false, Tide.NIGHT]]
	var ok: bool = true
	for c in cases:
		var w: Dictionary = Visitor.window_at(at(int(c[0]), int(c[1])))
		if bool(w["open"]) != bool(c[2]):
			ok = false
			print("      %02d:%02d expected open=%s" % [c[0], c[1], c[2]])
	check(ok, "open for the first 90 minutes of Dawn (06:00-07:30) and Dusk (17:00-18:30) only")
	check(Visitor.offered(prof, at(6, 30)) and not Visitor.offered(prof, at(8, 0)), "offered only inside a window")
	check(Visitor.window_at(at(6, 30))["family"] == 1 and Visitor.window_at(at(17, 30))["family"] == 2, "window features the tide's family")

func t_visitor_request() -> void:
	print("[visitor request]")
	GameClock.freeze(at(6, 40))
	var s := _session(["S1 . . . . .", "S2 S2 . . . ."])
	_all_goals_done(s)
	# progress begins AFTER acceptance: a tier 4 Shrimp made before accepting does not count
	s.run.board.set_code(Board.idx(3, 0), Creature.make(1, 3))
	s.run.board.set_code(Board.idx(3, 1), Creature.make(1, 3))
	s.try_pair(Board.idx(3, 0), Board.idx(3, 1))       # makes S4 before accepting
	check(not Visitor.has_request(s.profile), "no request yet")
	var rel0: Dictionary = s.try_release(Board.idx(3, 1))
	check(rel0["ok"] and not rel0["visitor_complete"] and s.profile.residents.size() == 1, "a release before accepting is a normal release")
	var acc: Dictionary = s.accept_visitor()
	check(acc["ok"] and acc["family"] == 1 and Visitor.has_request(s.profile), "tapping the visitor in the Dawn window accepts a request for Shrimp")
	check(not s.accept_visitor()["ok"], "cannot accept twice")
	check(Visitor.status_text(s.profile).begins_with("Step 1"), "reef text explains the goal: '%s'" % Visitor.status_text(s.profile))
	# wrong family does not progress
	s.run.board.set_code(Board.idx(4, 0), Creature.make(2, 3))
	s.run.board.set_code(Board.idx(4, 1), Creature.make(2, 3))
	s.try_pair(Board.idx(4, 0), Board.idx(4, 1))       # Starfish T4
	check(not s.profile.visitor["request"]["created"], "a tier 4 Starfish does not progress a Shrimp request")
	check(not s.try_release(Board.idx(4, 1))["visitor_complete"], "releasing it does not complete the request")
	# window closes (08:00): request persists; make the tier 4 Shrimp and finish after close
	GameClock.freeze(at(8, 0))
	check(not Visitor.window_at()["open"] and Visitor.has_request(s.profile), "window closed, request still active")
	s.run.board.set_code(Board.idx(5, 0), Creature.make(1, 3))
	s.run.board.set_code(Board.idx(5, 1), Creature.make(1, 3))
	var made: Dictionary = s.try_pair(Board.idx(5, 0), Board.idx(5, 1))
	check(made["visitor_created"] and s.profile.visitor["request"]["created"], "making the tier 4 Shrimp after the window closed still counts")
	check(not s.run.pending_surge.is_empty() and not s.try_release(Board.idx(5, 1))["ok"], "(turn 3 started a Surge preview: releasing is refused until it lands)")
	s.land_surge()
	check(Visitor.status_text(s.profile).begins_with("Step 2"), "reef text moves to step 2")
	# reload BEFORE the reward
	var s2 := _reload()
	check(Visitor.has_request(s2.profile) and s2.profile.visitor["request"]["created"], "accepted + created persists through reload")
	var before: int = s2.profile.residents.size()
	var rel: Dictionary = s2.try_release(Board.idx(5, 1))
	check(rel["visitor_complete"], "releasing it completes the request")
	var rays: int = 0
	for r in s2.profile.residents:
		if int(r["family"]) == Creature.RAY:
			rays += 1
	check(rays == 1 and s2.profile.residents.size() == before + 2, "exactly one Lantern Ray resident is granted (plus the Shrimp)")
	check(bool(s2.profile.visitor["done"]) and not Visitor.has_request(s2.profile), "request cleared, visitor marked done")
	check(s2.profile.unseen_residents.size() >= 2, "the ray is highlighted as new in the reef")
	# reload AFTER the reward: still exactly one
	var s3 := _reload()
	var rays3: int = 0
	for r in s3.profile.residents:
		if int(r["family"]) == Creature.RAY:
			rays3 += 1
	check(rays3 == 1 and s3.profile.residents.size() == before + 2, "after reload: still exactly one ray, nothing duplicated")
	GameClock.freeze(at(17, 10))
	check(not Visitor.offered(s3.profile) and not s3.accept_visitor()["ok"], "the visitor does not come back once it lives in the reef")
	check(ReefEconomy.resident_rate(4) == ReefEconomy.resident_rate(int(s3.profile.residents[s3.profile.residents.size() - 1]["tier"])), "the ray earns like a tier 4 resident")

func t_visitor_reload_and_once() -> void:
	print("[missed window -> next window is a fresh chance]")
	GameClock.freeze(at(6, 10))
	var s := _session()
	check(Visitor.offered(s.profile), "offered at 06:10")
	GameClock.freeze(at(9, 0))                           # window missed entirely
	check(not Visitor.offered(s.profile) and not s.accept_visitor()["ok"], "cannot accept after the Dawn window closed")
	GameClock.freeze(at(17, 30))
	var acc: Dictionary = s.accept_visitor()
	check(acc["ok"] and acc["family"] == 2, "the Dusk window is a fresh chance, now for Starfish")
	GameClock.freeze(at(6, 5, 1))                        # next dawn, request still open
	check(not Visitor.offered(s.profile) and Visitor.has_request(s.profile), "an accepted request is kept (no second one offered)")
	var s2 := _reload()
	check(Visitor.has_request(s2.profile) and int(s2.profile.visitor["request"]["family"]) == 2, "kept across reload")

func t_daily_goals() -> void:
	print("[daily goals]")
	GameClock.freeze(at(10))
	var s := _session()
	s.profile.coins = 0
	s.profile.pearls = 0
	s.profile.daily = DailyGoals.default_state()
	check(GameConfig.DAILY_GOALS.size() == 3, "three goals: merges, a Current, a release")
	# seven independent merges (spaced so results never chain into each other)
	var b2: Board = Board.new()
	s.run.board = b2
	var pairs: Array = []
	for r in 7:
		if r % 2 == 0:
			pairs.append([Board.idx(r, 0), Board.idx(r, 2)])
		else:
			pairs.append([Board.idx(r, 3), Board.idx(r, 5)])
	for pr in pairs:
		b2.set_code(pr[0], Creature.make(1, 1))
		b2.set_code(pr[1], Creature.make(1, 1))
	for pr in pairs:
		s.run.turn = 1                                  # stay clear of the Surge cadence
		s.try_pair(pr[0], pr[1])
	check(DailyGoals.progress(s.profile, "merges") == 7 and not DailyGoals.is_done(s.profile, "merges"), "7 merges: goal at 7/8")
	check(s.profile.coins == 7 * 10, "(only merge payouts so far: %d)" % s.profile.coins)
	var coins_before: int = s.profile.coins
	var pearls_before: int = s.profile.pearls
	b2.set_code(Board.idx(0, 4), Creature.make(2, 1))
	b2.set_code(Board.idx(0, 5), Creature.make(2, 1))
	s.run.turn = 1
	s.try_pair(Board.idx(0, 4), Board.idx(0, 5))
	check(DailyGoals.is_done(s.profile, "merges"), "the 8th merge completes the goal")
	check(s.profile.coins == coins_before + 10 + 60 and s.profile.pearls == pearls_before + 1 + 1, "reward (60 coins + 1 pearl) paid with the merge")
	b2.set_code(Board.idx(2, 4), Creature.make(2, 1))
	b2.set_code(Board.idx(2, 5), Creature.make(2, 1))
	var c2: int = s.profile.coins
	s.run.turn = 1
	s.try_pair(Board.idx(2, 4), Board.idx(2, 5))
	check(s.profile.coins == c2 + 10, "the goal pays only once per day")
	# Current goal: a no-op shift (free) does not count; a real one does
	s.run.currents = 3
	check(DailyGoals.progress(s.profile, "current") == 0, "no Current used yet")
	s.run.turn = 1
	var free_res: Dictionary = s.try_current(Board.AXIS_COL, 1, 1)       # column 1 is empty -> free
	check(free_res["free"] and DailyGoals.progress(s.profile, "current") == 0, "a free (no-change) Current does not count")
	s.run.turn = 1
	var cur_res: Dictionary = s.try_current(Board.AXIS_ROW, 5, 1)
	check(cur_res["ok"] and not cur_res["free"] and DailyGoals.is_done(s.profile, "current"), "using a Current completes its goal")
	# release goal: a rejected release does not count; a tier 4+ does
	check(not s.try_release(Board.idx(0, 0))["ok"], "(a tier 2 cannot be released)")
	check(not DailyGoals.is_done(s.profile, "release"), "a rejected release does not count")
	b2.set_code(Board.idx(6, 5), Creature.make(2, 4))
	var c3: int = s.profile.coins
	var rel: Dictionary = s.try_release(Board.idx(6, 5))
	check(rel["ok"] and DailyGoals.is_done(s.profile, "release") and s.profile.coins == c3 + 100, "releasing a tier 4+ completes its goal (+100 coins)")
	# reload: completion and reward were saved together; no double reward
	var coins_now: int = s.profile.coins
	var s2 := _reload()
	check(s2.profile.coins == coins_now and DailyGoals.is_done(s2.profile, "release") and DailyGoals.is_done(s2.profile, "merges") and DailyGoals.is_done(s2.profile, "current"), "reload keeps rewards and completion together")
	s2.run.board.set_code(Board.idx(3, 1), Creature.make(1, 5))
	var c4: int = s2.profile.coins
	s2.try_release(Board.idx(3, 1))
	check(s2.profile.coins == c4, "a second release the same day pays no second reward")

func t_midnight_rollover() -> void:
	print("[midnight rollover during an active run]")
	GameClock.set_tz_bias_seconds(-8 * 3600)
	GameClock.freeze(GameClock.unix_from_local(2026, 11, 24, 23, 59, 30))
	var s := _session(["S1 . . . . S1", "F1 . . . . F1"])
	s.profile.daily = DailyGoals.default_state()
	s.profile.coins = 0
	s.run.currents = 5
	s.try_pair(Board.idx(0, 0), Board.idx(0, 5))
	check(String(s.profile.daily["day"]) == "2026-11-24" and DailyGoals.progress(s.profile, "merges") == 1, "a merge at 23:59:30 counts for the 24th")
	GameClock.advance(60)                                  # 00:00:30 on the 25th, same run
	check(s.ensure_daily() and String(s.profile.daily["day"]) == "2026-11-25" and DailyGoals.progress(s.profile, "merges") == 0, "at local midnight the goals roll over to a new day")
	s.run.board.set_code(Board.idx(3, 0), Creature.make(1, 1))
	s.run.board.set_code(Board.idx(3, 4), Creature.make(1, 1))
	s.run.turn = 1
	s.try_pair(Board.idx(3, 0), Board.idx(3, 4))
	check(DailyGoals.progress(s.profile, "merges") == 1, "the run continues and counts toward the new day")
	var s2 := _reload()
	check(String(s2.profile.daily["day"]) == "2026-11-25" and DailyGoals.progress(s2.profile, "merges") == 1 and s2.run != null, "rollover state persisted; run intact")
	# a goal completed yesterday is available again today
	GameClock.set_tz_bias_seconds(0)
	GameClock.freeze(at(12))
	var s3 := _session()
	s3.profile.daily = {"day": "2026-11-23", "progress": {"current": 1}, "done": {"current": true}}
	s3.run.board.set_code(Board.idx(0, 1), Creature.make(1, 2))
	s3.run.currents = 2
	var coins: int = s3.profile.coins
	s3.try_current(Board.AXIS_ROW, 0, 1)
	check(DailyGoals.is_done(s3.profile, "current") and s3.profile.coins == coins + 40, "yesterday's completed goal pays again today")

# --- Tide Trial -----------------------------------------------------------------------------------

func _trial_actions(t: TideTrial) -> Array:
	var out: Array = []
	var b: Board = t.session.run.board
	for i in b.cells.size():
		if b.code_at(i) == 0:
			continue
		for n in b.neighbors(i):
			if n >= 0 and b.code_at(n) == 0:
				out.append(["drop", i, n, 0])
		for j in range(i + 1, b.cells.size()):
			if MergeRules.can_pair(b, i, j):
				out.append(["drop", i, j, 0])
	if t.session.run.currents > 0:
		for axis in [0, 1]:
			for idx in (GameConfig.ROWS if axis == 0 else GameConfig.COLS):
				for dir in [-1, 1]:
					out.append(["cur", axis, idx, dir])
	return out

func _apply_action(t: TideTrial, a: Array) -> Dictionary:
	var res: Dictionary
	if String(a[0]) == "drop":
		res = t.session.try_drop(int(a[1]), int(a[2]))
	else:
		res = t.session.try_current(int(a[1]), int(a[2]), int(a[3]))
	t.evaluate(res)
	return res

func t_trial_solver() -> void:
	print("[Tide Trial: solved with the real rules]")
	var base := TideTrial.new()
	check(GameConfig.TRIAL_BUDGET == 2 and base.moves_left == 2 and base.session.run.currents == 1, "fixed board, visible budget of 2 moves, one Current")
	check(base.session.run.board.creature_count() == 6, "six pieces on the handcrafted board")
	var first_actions: Array = _trial_actions(base)
	var wins: Array = []
	var line_without_win: int = 0
	var total: int = 0
	var any_win_without_current: int = 0
	for a1 in first_actions:
		var t1 := TideTrial.new()
		var r1: Dictionary = _apply_action(t1, a1)
		var line1: bool = _has_line(r1)
		total += 1
		if t1.status == TideTrial.WON:
			wins.append([a1])
			if String(a1[0]) != "cur":
				any_win_without_current += 1
		elif line1:
			line_without_win += 1
		if t1.status != TideTrial.PLAYING:
			continue
		for a2 in _trial_actions(t1):
			var t2 := TideTrial.new()
			_apply_action(t2, a1)
			var r2: Dictionary = _apply_action(t2, a2)
			total += 1
			var line2: bool = _has_line(r2)
			if t2.status == TideTrial.WON:
				wins.append([a1, a2])
				if String(a2[0]) != "cur" and String(a1[0]) != "cur":
					any_win_without_current += 1
			elif line2:
				line_without_win += 1
	check(total > 500, "searched all %d action sequences within the budget" % total)
	check(wins.size() > 0, "the trial is winnable (%d winning sequences)" % wins.size())
	var shortest: Array = []
	for w in wins:
		if shortest.is_empty() or w.size() < shortest.size():
			shortest = w
	check(shortest.size() == 1 and shortest[0] == ["cur", TideTrial.HINT_AXIS, TideTrial.HINT_INDEX, TideTrial.HINT_DIR], "the shortest solution is one Current: row 3, left (the hinted line)")
	check(any_win_without_current == 0, "no winning sequence avoids a Current")
	check(line_without_win == 0, "no sequence makes a three-in-a-row WITHOUT a wrap (so a wrap is required)")
	# play the winning sequence through the trial exactly as the UI does
	var t := TideTrial.new()
	var res: Dictionary = t.session.try_current(TideTrial.HINT_AXIS, TideTrial.HINT_INDEX, TideTrial.HINT_DIR)
	var won: bool = t.evaluate(res)
	check(won and t.status == TideTrial.WON and t.session.run.board.code_at(Board.idx(2, 4)) == Creature.make(1, 4), "winning move: wrapped Current makes a tier 4 Shrimp in the middle")
	# the opposite direction wraps too but makes no line
	var t2 := TideTrial.new()
	var r2: Dictionary = t2.session.try_current(TideTrial.HINT_AXIS, TideTrial.HINT_INDEX, 1)
	t2.evaluate(r2)
	check(t2.status == TideTrial.PLAYING and t2.moves_left == 1, "shifting the same row the wrong way costs a move and does not win")
	# out of moves -> lost; retry is free and fresh
	var t3 := TideTrial.new()
	t3.evaluate(t3.session.try_drop(Board.idx(0, 1), Board.idx(0, 2)))
	t3.evaluate(t3.session.try_drop(Board.idx(0, 2), Board.idx(0, 3)))
	check(t3.status == TideTrial.LOST and t3.moves_left == 0, "two wasted moves ends the attempt")
	var attempts_before: int = t3.attempts
	t3.new_attempt()
	check(t3.status == TideTrial.PLAYING and t3.moves_left == 2 and t3.session.run.currents == 1 and t3.attempts == attempts_before + 1 and str(t3.session.run.board.to_array()) == str(base.session.run.board.to_array()), "retry resets the board, budget and Current (free, unlimited)")
	check(TideTrial.wrap_destination(0, 2, -1) == Board.idx(2, 5), "hint line: the edge piece wraps onto the far end of row 3")

func _has_line(res: Dictionary) -> bool:
	for ev in res["events"]:
		if String(ev["t"]) == "merge" and String(ev["kind"]) == "line":
			return true
	return false

func t_trial_isolation() -> void:
	print("[Tide Trial cannot touch a suspended regular run]")
	GameClock.freeze(at(12))
	var s := _session(["S1 S1 . . . .", ". . F2 . . .", "S3 . . . . F1"])
	s.profile.coins = 500
	s.try_drop(Board.idx(0, 1), Board.idx(0, 2))
	var board_before: String = str(s.run.board.to_array())
	var turn_before: int = s.run.turn
	var cur_before: int = s.run.currents
	var coins_before: int = s.profile.coins
	var pearls_before: int = s.profile.pearls
	var stats_before: String = str(s.run.stats)
	var rng_before: int = s.run.rng.state
	var disk_before: String = FileAccess.get_file_as_string(PATH)
	for attempt in 3:
		var t := TideTrial.new()
		t.evaluate(t.session.try_current(2, 2, -1) if false else t.session.try_current(0, 2, -1))
		t.new_attempt()
		t.evaluate(t.session.try_drop(Board.idx(5, 3), Board.idx(5, 4)))
	check(str(s.run.board.to_array()) == board_before and s.run.turn == turn_before and s.run.currents == cur_before, "regular run: board, turn and Currents untouched after trial attempts")
	check(s.profile.coins == coins_before and s.profile.pearls == pearls_before and str(s.run.stats) == stats_before and s.run.rng.state == rng_before, "no merge payouts, stats or random draws leak from the trial (nothing farmable)")
	check(FileAccess.get_file_as_string(PATH) == disk_before, "trial turns never write the save")
	var s2 := _reload()
	check(str(s2.run.board.to_array()) == board_before and s2.run.turn == turn_before, "the suspended run resumes exactly after the trial")
	var t4 := TideTrial.new()
	t4.evaluate(t4.session.try_current(0, 2, -1))
	check(t4.session.profile != s.profile and t4.session.profile.coins > 0 and s.profile.coins == coins_before, "the trial pays into its own throwaway profile only")

func t_trial_reward() -> void:
	print("[first-clear reward]")
	var s := _session()
	s.profile.coins = 10
	s.profile.pearls = 0
	var r1: Dictionary = s.claim_trial_reward()
	check(r1["first"] and s.profile.coins == 10 + GameConfig.TRIAL_REWARD_COINS and s.profile.pearls == GameConfig.TRIAL_REWARD_PEARLS, "first clear pays %d coins + %d pearls" % [GameConfig.TRIAL_REWARD_COINS, GameConfig.TRIAL_REWARD_PEARLS])
	var r2: Dictionary = s.claim_trial_reward()
	check(not r2["first"] and s.profile.coins == 10 + GameConfig.TRIAL_REWARD_COINS, "clearing again pays nothing")
	var s2 := _reload()
	check(bool(s2.profile.trial["cleared"]) and bool(s2.profile.trial["claimed"]) and s2.profile.coins == 10 + GameConfig.TRIAL_REWARD_COINS, "cleared flag and reward saved together")
	check(s2.claim_trial_reward()["coins"] == 0, "no second reward after reload")

func t_migration() -> void:
	print("[earlier saves load in the Update 3 build]")
	for name in ["save_v1_midrun", "save_v1_flooded", "save_v2_checkpoint"]:
		var src: String = "res://tests/fixtures/%s.json" % name
		var dst: String = "user://test_mig3.json"
		_rm(dst)
		DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst))
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(src))
		GameClock.freeze(at(12))
		var s := GameSession.new()
		s.save_path = dst
		s.load_or_new()
		var rr: Dictionary = raw["run"]
		check(s.profile.coins == int(raw["profile"]["coins"]) and s.profile.residents.size() == raw["profile"]["residents"].size(), "[%s v%d] balances and %d residents kept" % [name, int(raw["version"]), s.profile.residents.size()])
		check(s.run != null and str(s.run.board.to_array()) == str(rr["board"]) and s.run.turn == int(rr["turn"]), "[%s] run board and turn kept" % name)
		check(s.run.tide == -1 and s.run.spawn_table.is_empty(), "[%s] pre-tide run keeps the base spawn table" % name)
		check(not bool(s.profile.visitor["done"]) and (s.profile.visitor["request"] as Dictionary).is_empty() and bool(s.profile.trial["claimed"]) == false, "[%s] new Update 3 state starts empty" % name)
		if int(raw["version"]) == 2:
			check(s.profile.decorations.size() == raw["profile"]["decorations"].size() and s.profile.decorations.size() > 0, "[%s] decorations kept" % name)
		s.save()
		var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dst))
		check(int(doc["version"]) == GameConfig.SAVE_VERSION, "[%s] re-saved as the current version" % name)
		var s2 := GameSession.new()
		s2.save_path = dst
		s2.load_or_new()
		check(str(s2.run.board.to_array()) == str(rr["board"]) and s2.profile.residents.size() == s.profile.residents.size(), "[%s] stable on a second load" % name)
		# an old run can still roll Surges
		s2.run.turn = 2
		s2.run.board = Board.from_text(["S1 . . . . ."])
		var rs: Dictionary = s2.try_drop(0, 1)
		check(rs["surge"].size() == 3, "[%s] old run still produces a Surge (base table)" % name)
		_rm(dst)

func t_night_contrast() -> void:
	print("[Night readability]")
	var night: Dictionary = Tide.palette(Tide.NIGHT)
	var worst_text: float = 99.0
	for phase in 4:
		var pal: Dictionary = Tide.palette(phase)
		worst_text = minf(worst_text, minf(Tide.contrast(Pal.TEXT, pal["bg_top"]), Tide.contrast(Pal.TEXT, pal["bg_bottom"])))
	check(worst_text >= 4.5, "HUD text (sand-white) keeps >= 4.5:1 on every phase's background (worst %.1f:1)" % worst_text)
	var tile_vs_bg: float = minf(Tide.contrast(Pal.CELL, night["bg_bottom"]), Tide.contrast(Pal.CELL, night["bg_top"]))
	check(tile_vs_bg >= 1.5, "grid tiles stay distinct from the Night background (%.2f:1)" % tile_vs_bg)
	var ink_on_sand: float = Tide.contrast(Pal.INK, Pal.SAND)
	check(ink_on_sand >= 7.0, "prompt text (ink on sand) is %.1f:1" % ink_on_sand)
	var shrimp_tile: float = Tide.contrast(Pal.SHRIMP_BODY, Pal.CELL)
	var star_tile: float = Tide.contrast(Pal.STAR_BODY, Pal.CELL)
	check(shrimp_tile >= 1.8 and star_tile >= 2.5, "creature bodies read on the grid tiles (shrimp %.1f:1, starfish %.1f:1; badge and ring add the rest)" % [shrimp_tile, star_tile])
	# the grid itself is not tinted by the tide, so Night cannot reduce its contrast
	check(night["overlay"].a <= 0.2, "Night overlay is light (alpha %.2f) and only applied to the reef" % night["overlay"].a)

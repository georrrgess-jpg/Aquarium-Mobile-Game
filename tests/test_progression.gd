extends SceneTree
## Update 4 pass 3: Tide Goals, Tidepool Book, Calm Pool and the three Trials (solver-verified).
##   godot --headless --path . --script res://tests/test_progression.gd

var passed: int = 0
var failed: int = 0
const PATH: String = "user://test_prog.json"

func _initialize() -> void:
	GameClock.set_tz_bias_seconds(0)
	GameClock.freeze(1795000000 + 12 * 3600)
	_run_all()
	GameClock.reset()
	print("\n==== progression: %d passed, %d failed ====" % [passed, failed])
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

## A finished-tutorial profile with a standard run (so the run gets a Tide Goal).
func _session() -> GameSession:
	_rm(PATH)
	var s := GameSession.new()
	s.save_path = PATH
	s.profile.tutorial = {"done": true, "skipped": true, "milestone": true, "restarts": 0}
	s.start_run()
	return s

func _reload() -> GameSession:
	var s := GameSession.new()
	s.save_path = PATH
	s.load_or_new()
	return s

func _run_all() -> void:
	t_goal_pick()
	t_goal_events()
	t_goal_reload_once()
	t_book()
	t_calm()
	t_trials_solver()
	t_trial_rewards()
	t_swell()

# --- Tide Goals ------------------------------------------------------------------------------

func t_goal_pick() -> void:
	print("[tide goals: drawn at run start, from a small template pool, saved]")
	var s := _session()
	check(not s.run.goal.is_empty() and not bool(s.run.goal["done"]) and int(s.run.goal["progress"]) == 0, "a standard run starts with one undone goal")
	var ids: Array = []
	for d in GameConfig.TIDE_GOALS:
		ids.append(d["id"])
	check(ids.has(String(s.run.goal["id"])), "the goal comes from the template pool (%s)" % s.run.goal["id"])
	var again: Dictionary = TideGoals.pick(s.run.seed_value, s.run.spawn_table)
	check(again["id"] == s.run.goal["id"] and again["label"] == s.run.goal["label"], "the pick is a pure function of the run seed")
	var seen: Dictionary = {}
	var fam_ok: bool = true
	for sd in 60:
		var g: Dictionary = TideGoals.pick(sd * 7919, Tide.spawn_table(Tide.MIDDAY))
		seen[String(g["id"])] = true
		if String(g["id"]) == "release_family":
			fam_ok = fam_ok and (int(g["family"]) == Creature.SHRIMP or int(g["family"]) == Creature.STAR)
	check(seen.size() == GameConfig.TIDE_GOALS.size(), "every template gets drawn across seeds")
	check(fam_ok, "a featured-family goal only names a family that is in the spawn pool")
	var rng_before: int = s.run.rng.state
	TideGoals.pick(5, s.run.spawn_table)
	check(s.run.rng.state == rng_before, "picking never touches the run's random stream")
	var s2 := _reload()
	check(s2.run.goal == s.run.goal, "the goal survives a reload unchanged")
	var s3 := GameSession.new()
	s3.profile.tutorial = {"done": false, "skipped": false, "milestone": false, "restarts": 0}
	s3.autosave = false
	s3.start_run()
	check(s3.run.tutorial and s3.run.goal.is_empty(), "the guided first run has no goal")

func _force_goal(s: GameSession, id: String, family: int = 0) -> void:
	var g: Dictionary = {"id": id, "label": id, "short": id, "family": family, "target": 1, "progress": 0, "done": false, "coins": GameConfig.TIDE_GOAL_COINS, "pearls": GameConfig.TIDE_GOAL_PEARLS}
	if id == "merges":
		g["target"] = 12
	s.run.goal = g

func t_goal_events() -> void:
	print("[tide goals: committed events complete each template once]")
	# merge pair + chain
	var s := _session()
	_force_goal(s, "chain")
	s.run.board = Board.from_text([". . . . . .", ". . . . . .", ". S1 S1 . . .", ". . . . . .", ". . . . . .", ". . . . . .", ". . . . . ."])
	var c0: int = s.profile.coins
	var r: Dictionary = s.try_pair(_i(2, 1), _i(2, 2))
	check(r.get("tide_goal_done", {}).is_empty() and not bool(s.run.goal["done"]), "a plain pair merge is not a chain")
	# chain: pair whose result meets two matching neighbours
	_force_goal(s, "chain")
	s.run.board = Board.from_text([". . . . . .", ". S2 . . . .", ". S1 S2 . . .", ". . . . . .", ". . . . . .", ". . . . S1 .", ". . . . . ."])
	s.run.board.set_code(_i(2, 2), Creature.make(1, 1))
	s.run.board.set_code(_i(2, 1), Creature.make(1, 2))
	s.run.board.set_code(_i(1, 2), Creature.make(1, 2))
	s.run.board.set_code(_i(1, 1), 0)
	var coins_before: int = s.profile.coins
	var pearls_before: int = s.profile.pearls
	var r2: Dictionary = s.try_pair(_i(5, 4), _i(2, 2))
	check(int(r2["chain"]) >= 1 and bool(s.run.goal["done"]), "a chain reaction completes the chain goal")
	check(s.profile.coins - coins_before >= GameConfig.TIDE_GOAL_COINS and s.profile.pearls - pearls_before >= GameConfig.TIDE_GOAL_PEARLS, "the goal pays its coins and pearls with the merge")
	check(not (r2.get("tide_goal_done", {}) as Dictionary).is_empty(), "the result carries the completed goal (for the toast)")
	var paid: int = s.profile.coins
	s.run.board = Board.from_text([". . . . . .", ". . . . . .", ". S1 S1 . . .", ". . . . . .", ". . . . . .", ". . . . . .", ". . . . . ."])
	s.try_pair(_i(2, 1), _i(2, 2))
	check(s.profile.coins - paid == Rewards.coins_for(2, 0) and s.profile.pearls - pearls_before - Rewards.pearls_for(2, 0) >= 0, "a finished goal never pays a second time")
	# tier 4
	var s4 := _session()
	_force_goal(s4, "tier4")
	s4.run.board = Board.from_text([". . . . . .", ". . . . . .", ". S3 S3 . . .", ". . . . . .", ". . . . . .", ". . . . . .", ". . . . . ."])
	s4.try_pair(_i(2, 1), _i(2, 2))
	check(bool(s4.run.goal["done"]), "making a tier 4 completes the tier-4 goal")
	# merges counter
	var sm := _session()
	_force_goal(sm, "merges")
	sm.run.board = Board.from_text([". . . . . .", ". . . . . .", ". S1 S1 . . .", ". . . . . .", ". . . . . .", ". . . . . .", ". . . . . ."])
	sm.try_pair(_i(2, 1), _i(2, 2))
	check(int(sm.run.goal["progress"]) == 1 and not bool(sm.run.goal["done"]), "the merge goal counts merges (1 of 12)")
	# release family
	var sr := _session()
	_force_goal(sr, "release_family", Creature.STAR)
	sr.run.board = Board.new()
	sr.run.board.set_code(_i(3, 3), Creature.make(Creature.SHRIMP, 4))
	sr.run.board.set_code(_i(3, 4), Creature.make(Creature.STAR, 4))
	sr.try_release(_i(3, 3))
	check(not bool(sr.run.goal["done"]), "releasing the wrong family does not count")
	var rr: Dictionary = sr.try_release(_i(3, 4))
	check(bool(sr.run.goal["done"]) and not (rr.get("tide_goal_done", {}) as Dictionary).is_empty(), "releasing the featured family completes it")
	# current merge
	var sc := _session()
	_force_goal(sc, "current_merge")
	sc.run.board = Board.from_text([". . . . . .", ". . . . . .", "S1 . . . S1 S1", ". . . . . .", ". . . . . .", ". . . . . .", ". . . . . ."])
	sc.try_current(Board.AXIS_ROW, 2, -1)
	check(bool(sc.run.goal["done"]), "a Current that makes a merge completes the Current goal")
	# practice and calm never record
	var sp := _session()
	_force_goal(sp, "merges")
	sp.run.practice = true
	sp.run.board = Board.from_text([". . . . . .", ". . . . . .", ". S1 S1 . . .", ". . . . . .", ". . . . . .", ". . . . . .", ". . . . . ."])
	sp.try_pair(_i(2, 1), _i(2, 2))
	check(int(sp.run.goal["progress"]) == 0, "a practice board does not advance the goal")
	# missed goal: flood still banks rewards
	var sf := _session()
	var bank: int = sf.profile.coins
	sf.run.board = Board.from_text([". . . . . .", ". . . . . .", ". S1 S1 . . .", ". . . . . .", ". . . . . .", ". . . . . .", ". . . . . ."])
	sf.try_pair(_i(2, 1), _i(2, 2))
	check(sf.profile.coins > bank, "normal merge rewards are paid whether or not the goal is met")

func t_goal_reload_once() -> void:
	print("[tide goals: reload never repeats the payout]")
	var s := _session()
	_force_goal(s, "tier4")
	s.run.board = Board.from_text([". . . . . .", ". . . . . .", ". S3 S3 . . .", ". . . . . .", ". . . . . .", ". . . . . .", ". . . . . ."])
	s.try_pair(_i(2, 1), _i(2, 2))
	var coins: int = s.profile.coins
	var s2 := _reload()
	check(s2.profile.coins == coins and bool(s2.run.goal["done"]), "reload restores the paid balance and the done goal together")
	s2.run.board = Board.from_text([". . . . . .", ". . . . . .", ". S3 S3 . . .", ". . . . . .", ". . . . . .", ". . . . . .", ". . . . . ."])
	var before: int = s2.profile.coins
	s2.try_pair(_i(2, 1), _i(2, 2))
	check(s2.profile.coins - before == Rewards.coins_for(4, 0), "after reload a second tier 4 pays only the merge reward")

# --- Tidepool Book -----------------------------------------------------------------------------

func t_book() -> void:
	print("[tidepool book]")
	var s := _session()
	var st1: String = Book.state_of(s.profile, Creature.SHRIMP, 1)
	check(st1 == "found" or st1 == "hidden", "tiers on the opening board are recorded when the run begins")
	for i in s.run.board.cells.size():
		var code: int = s.run.board.code_at(i)
		if code != 0:
			check(bool(Book.entry(s.profile, code).get("seen", false)), "the creature on the board (%s) is marked seen" % Book.key(code))
			break
	s.run.board = Board.from_text([". . . . . .", ". . . . . .", ". S3 S3 . . .", ". . . . . .", ". . . . . .", ". . . . . .", ". . . . . ."])
	var r: Dictionary = s.try_pair(_i(2, 1), _i(2, 2))
	var made: int = Creature.make(Creature.SHRIMP, 4)
	check(bool(Book.entry(s.profile, made)["made"]) and not bool(Book.entry(s.profile, made)["released"]), "a made tier is recorded as made, not yet a resident")
	check((r.get("book_new", []) as Array).has(made), "the result lists the newly found tier (for the toast)")
	check(Book.state_of(s.profile, Creature.SHRIMP, 5) == "next", "the tier above a found one shows as a reachable silhouette")
	check(Book.state_of(s.profile, Creature.SHRIMP, 6) == "hidden", "tiers further up stay hidden")
	var cell: int = -1
	for i in s.run.board.cells.size():
		if s.run.board.code_at(i) == made:
			cell = i
	s.try_release(cell)
	check(Book.state_of(s.profile, Creature.SHRIMP, 4) == "resident", "releasing marks the tier a resident")
	var s2 := _reload()
	check(Book.state_of(s2.profile, Creature.SHRIMP, 4) == "resident", "Book entries survive a reload")
	var c: Dictionary = Book.counts(s.profile)
	check(int(c["total"]) == 13 and int(c["found"]) >= 2 and int(c["residents"]) == 1, "counts: %d of %d found, %d resident" % [c["found"], c["total"], c["residents"]])
	check(Book.note(made) != "" and Book.tier_name(made).contains("Harlequin"), "found entries have a field note and a name")
	# practice and calm never write
	var p := Profile.new()
	var sp := GameSession.new()
	sp.autosave = false
	sp.profile = p
	sp.run = RunState.new()
	sp.run.practice = true
	sp.run.board = Board.from_text([". . . . . .", ". . . . . .", ". S3 S3 . . .", ". . . . . .", ". . . . . .", ". . . . . .", ". . . . . ."])
	sp.try_pair(_i(2, 1), _i(2, 2))
	check(p.book.is_empty(), "a practice board writes nothing to the Book")

# --- Calm Pool ---------------------------------------------------------------------------------

func t_calm() -> void:
	print("[calm pool]")
	var s := _session()
	var regular_board: PackedInt32Array = s.run.board.cells.duplicate()
	var regular_turn: int = s.run.turn
	var coins: int = s.profile.coins
	var calm: GameSession = s.calm_session()
	check(calm.run.mode == "calm" and calm.run.cadence == 5 and calm.run.board.creature_count() == GameConfig.CALM_START_CREATURES, "a Calm board starts: Surge every 5th turn, %d creatures" % GameConfig.CALM_START_CREATURES)
	check(calm.profile != s.profile, "Calm runs on its own throwaway profile")
	check(not (s.profile.calm["run"] as Dictionary).is_empty(), "its board is stored in the real profile")
	# play turns (a merge when there is one, else a slide) until the first Surge: cadence 5
	var book_before: Dictionary = s.profile.book.duplicate(true)
	var pearls: int = s.profile.pearls
	var surge_turn: int = 0
	for n in 40:
		var r: Dictionary = {}
		for i in calm.run.board.cells.size():
			if calm.run.board.code_at(i) == 0 or not (r.is_empty()):
				continue
			var tg: Dictionary = calm.valid_targets(i)
			if (tg["merge"] as PackedInt32Array).size() > 0:
				r = calm.try_pair(i, int((tg["merge"] as PackedInt32Array)[0]))
		if r.is_empty():
			for i in calm.run.board.cells.size():
				if calm.run.board.code_at(i) == 0 or not (r.is_empty()):
					continue
				var tg2: Dictionary = calm.valid_targets(i)
				if (tg2["move"] as PackedInt32Array).size() > 0:
					r = calm.try_move(i, int((tg2["move"] as PackedInt32Array)[0]))
		if r.is_empty():
			r = calm.advance_tide() if calm.is_stuck() else {}
		if not r.is_empty() and not (r["surge"] as Array).is_empty():
			surge_turn = calm.run.turn
			calm.land_surge()
			break
	check(surge_turn > 0 and surge_turn % 5 == 0, "the first Calm Surge arrives on turn %d (a multiple of 5)" % surge_turn)
	check(s.profile.coins == coins and s.profile.pearls == pearls and s.profile.residents.is_empty() and s.profile.book == book_before, "Calm paid and recorded nothing in the real profile")
	check(s.run.board.cells == regular_board and s.run.turn == regular_turn, "the suspended regular run is untouched")
	var s_goal: Dictionary = s.run.goal
	check(not bool(s_goal["done"]) and int(s_goal["progress"]) == 0, "no Tide Goal progress from Calm")
	check(s.profile.daily["progress"].is_empty() and (s.profile.visitor["request"] as Dictionary).is_empty(), "no daily or visitor progress from Calm")
	# resume after relaunch
	var turn: int = calm.run.turn
	var cells: PackedInt32Array = calm.run.board.cells.duplicate()
	var s2 := _reload()
	var calm2: GameSession = s2.calm_session()
	check(calm2.run.turn == turn and calm2.run.board.cells == cells and calm2.run.mode == "calm", "the Calm board resumes after a relaunch")
	check(s2.run != null and s2.run.board.cells == regular_board, "and the regular run is still there")
	# recoverable reset when the board fills
	var full: GameSession = s2.calm_session()
	var b: Board = full.run.board
	for i in b.cells.size():
		b.set_code(i, Creature.make(1 + (i % 2), 6) if i % 3 != 0 else Creature.make(2, 6))
	b.set_code(0, 0)
	full.run.turn = 4          # the next turn raises the Surge; 1 free cell < 3 needed
	var moved_ok: Dictionary = full.try_move(_i(0, 1), 0)
	check(full.run.status == RunState.ACTIVE and not bool(moved_ok["flood"]) and bool(moved_ok.get("calm_reset", false)), "a full Calm board resets instead of flooding")
	check(full.run.board.creature_count() == GameConfig.CALM_START_CREATURES and full.run.mode == "calm", "the reset board is a fresh playable one")
	# a fresh Calm board replaces the saved one
	var plays: int = int(s2.profile.calm["plays"])
	var fresh: GameSession = s2.calm_session(true)
	check(int(s2.profile.calm["plays"]) == plays + 1 and fresh.run.turn == 0, "'New board' starts a new Calm board")
	# releases in calm make no residents
	var rel: GameSession = s2.calm_session()
	rel.run.board = Board.new()
	rel.run.board.set_code(_i(3, 3), Creature.make(1, 5))
	var rres: Dictionary = rel.try_release(_i(3, 3))
	check(rres["ok"] and s2.profile.residents.is_empty() and rel.profile.residents.is_empty(), "releasing in Calm sets it free but creates no resident")

# --- Trials (solver) ---------------------------------------------------------------------------

## Every legal action on a trial's current board: [[kind, a, b, c]].
func _actions(t: TideTrial) -> Array:
	var out: Array = []
	var s: GameSession = t.session
	var b: Board = s.run.board
	for i in b.cells.size():
		if b.code_at(i) == 0:
			continue
		for j in b.cells.size():
			if i != j and MergeRules.can_pair(b, i, j):
				out.append(["pair", i, j, 0])
		for n in b.neighbors(i):
			if n >= 0 and b.code_at(n) == 0:
				out.append(["move", i, n, 0])
	if s.run.currents > 0:
		for axis in [Board.AXIS_ROW, Board.AXIS_COL]:
			var count: int = GameConfig.ROWS if axis == Board.AXIS_ROW else GameConfig.COLS
			for idx in count:
				for dir in [-1, 1]:
					out.append(["cur", axis, idx, dir])
	return out

func _apply(t: TideTrial, a: Array) -> Dictionary:
	var res: Dictionary
	match String(a[0]):
		"pair": res = t.session.try_pair(int(a[1]), int(a[2]))
		"move": res = t.session.try_move(int(a[1]), int(a[2]))
		_: res = t.session.try_current(int(a[1]), int(a[2]), int(a[3]))
	if bool(res.get("ok", false)) and not (res.get("surge", []) as Array).is_empty():
		t.session.land_surge()
	t.evaluate(res)
	return res

func _clone(t: TideTrial) -> TideTrial:
	var c := TideTrial.new(t.id)
	c.session.run = RunState.from_dict(t.session.run.to_dict())
	c.moves_left = t.moves_left
	c.status = t.status
	return c

## Depth-first over every action sequence within the budget. Returns {wins: [[actions]], lost: n, nodes: n}.
func _solve(t: TideTrial, path: Array, out: Dictionary) -> void:
	if t.status == TideTrial.WON:
		out["wins"].append(path.duplicate())
		return
	if t.status == TideTrial.LOST or t.moves_left <= 0:
		out["lost"] += 1
		return
	for a in _actions(t):
		var c: TideTrial = _clone(t)
		var res: Dictionary = _apply(c, a)
		if not bool(res.get("ok", false)) or bool(res.get("free", false)):
			continue
		path.append(a)
		_solve(c, path, out)
		path.pop_back()

func t_trials_solver() -> void:
	print("[trials: exhaustive search over the real rules]")
	for id in TideTrial.IDS:
		var t := TideTrial.new(id)
		var out: Dictionary = {"wins": [], "lost": 0}
		_solve(t, [], out)
		var wins: Array = out["wins"]
		var shortest: int = 99
		for w in wins:
			shortest = mini(shortest, (w as Array).size())
		print("    %s: %d winning sequences, shortest %d, %d losing leaves" % [id, wins.size(), shortest, out["lost"]])
		check(wins.size() > 0, "[%s] is winnable within %d moves" % [id, t.budget])
		check(out["lost"] > 0, "[%s] can also be lost (it is a puzzle, not a formality)" % id)
		match id:
			"wrap":
				check(shortest == 1, "[wrap] shortest solution is one Current")
				var all_cur: bool = true
				var wraps: bool = true
				for w in wins:
					var last: Array = (w as Array)[(w as Array).size() - 1]
					all_cur = all_cur and String(last[0]) == "cur"
					wraps = wraps and int(last[1]) == Board.AXIS_ROW
				check(all_cur and wraps, "[wrap] every win ends in a row Current")
			"chain":
				check(shortest == 2, "[chain] no one-move win: it needs a setup move first (shortest %d)" % shortest)
				var ends_pair: bool = true
				var starts_move: bool = true
				for w in wins:
					ends_pair = ends_pair and String(((w as Array)[(w as Array).size() - 1] as Array)[0]) == "pair"
					starts_move = starts_move and String(((w as Array)[0] as Array)[0]) == "move"
				check(ends_pair and starts_move, "[chain] every win is slide first, then a merge that chains")
			"space":
				var all_pair: bool = true
				for w in wins:
					var has_pair: bool = false
					for a in w:
						if String((a as Array)[0]) == "pair":
							has_pair = true
					all_pair = all_pair and has_pair
				check(all_pair and shortest == 2, "[space] every win merges the pair to free a cell (shortest %d: the Surge lands on turn 3)" % shortest)
		# the authored hint plays to a win
		var th := TideTrial.new(id)
		var guard: int = 0
		while th.status == TideTrial.PLAYING and guard < 4:
			guard += 1
			if id == "wrap":
				var h: Dictionary = th.hint()
				_apply(th, ["cur", int(h["axis"]), int(h["index"]), int(h["dir"])])
			else:
				var g: Dictionary = th.hint_guide()
				if g.is_empty():
					break
				_apply(th, ["move" if String(g["style"]) == "move" else "pair", int(g["from"]), int(g["to"]), 0])
		check(th.status == TideTrial.WON, "[%s] following the hint wins (%d actions)" % [id, guard])
	# the space trial floods when nothing frees a cell
	var ts := TideTrial.new("space")
	var moved: int = 0
	for i in ts.session.run.board.cells.size():
		if moved >= 2:
			break
		if ts.session.run.board.code_at(i) == 0:
			continue
		for n in ts.session.run.board.neighbors(i):
			if n >= 0 and ts.session.run.board.code_at(n) == 0 and moved < 2:
				_apply(ts, ["move", i, n, 0])
				moved += 1
				break
	check(ts.status == TideTrial.LOST and ts.session.run.status == RunState.FLOODED, "[space] two wasted moves flood the pool and lose")

func t_trial_rewards() -> void:
	print("[trials: first-clear rewards once, free retries, isolated]")
	var s := _session()
	var board: PackedInt32Array = s.run.board.cells.duplicate()
	var turn: int = s.run.turn
	var coins: int = s.profile.coins
	var total: int = 0
	for id in TideTrial.IDS:
		var r1: Dictionary = s.claim_trial_reward(id)
		var r2: Dictionary = s.claim_trial_reward(id)
		check(bool(r1["first"]) and int(r1["coins"]) > 0 and not bool(r2["first"]) and int(r2["coins"]) == 0, "[%s] first clear pays once (%d coins, %d pearls), a repeat pays nothing" % [id, r1["coins"], r1["pearls"]])
		total += int(r1["coins"])
		check(s.trial_cleared(id), "[%s] is marked cleared" % id)
	check(s.profile.coins == coins + total, "total paid equals the three first clears")
	var s2 := _reload()
	check(s2.trial_cleared("wrap") and s2.trial_cleared("chain") and s2.trial_cleared("space") and s2.profile.coins == s.profile.coins, "clear flags and balances survive a reload together")
	check(s2.run.board.cells == board and s2.run.turn == turn, "the suspended regular run is untouched by Trials")
	var t := TideTrial.new("chain")
	t.new_attempt()
	check(t.attempts == 2 and t.moves_left == t.budget and t.status == TideTrial.PLAYING, "a retry is free and unlimited")

# --- The swell (Surge growth, Update 4 tuning) -----------------------------------------------

func t_swell() -> void:
	print("[swell: the Surge grows later in a standard run; runs keep the rules they started with]")
	var s := _session()
	check(s.run.swell_start == GameConfig.SWELL_START and s.run.swell_every == GameConfig.SWELL_EVERY and s.run.swell_max == GameConfig.SWELL_MAX, "a standard run records the swell it started with")
	var r: RunState = s.run
	var sizes: Array = []
	for t in [0, 19, 20, 39, 40, 59, 60, 200]:
		r.turn = t
		sizes.append(r.surge_size_now())
	check(sizes == [3, 3, 4, 4, 5, 5, 6, 6], "Surge size by turn: %s (3 until turn 20, then +1 every 20, at most +3)" % str(sizes))
	var g := GameSession.new()
	g.autosave = false
	g.profile.tutorial = {"done": false, "skipped": false, "milestone": false, "restarts": 0}
	g.start_run()
	g.run.turn = 100
	check(g.run.surge_size_now() == 3, "the guided first run never swells")
	g.run.turn = 0
	g.run.turn = 3
	g.run.tut_flags = {"pair": true, "current": true, "surge": true, "release": true}
	g._finish_tutorial_if_done({})
	g.run.turn = 3 + GameConfig.SWELL_START - 1
	var before_sw: int = g.run.surge_size_now()
	g.run.turn = 3 + GameConfig.SWELL_START
	check(before_sw == 3 and g.run.surge_size_now() == 4, "once the guided start is finished the run swells %d turns later, so it too can end" % GameConfig.SWELL_START)
	var calm: GameSession = s.calm_session()
	calm.run.turn = 100
	check(calm.run.surge_size_now() == 3, "Calm Pool never swells")
	var t := TideTrial.new("space")
	t.session.run.turn = 100
	check(t.session.run.surge_size_now() == 3, "Trials never swell")
	# a run saved by an older build keeps its old rules
	var d: Dictionary = s.run.to_dict()
	d.erase("swell_start")
	d.erase("swell_every")
	d.erase("swell_max")
	var old: RunState = RunState.from_dict(d)
	old.turn = 100
	check(old.surge_size_now() == 3, "a run from before the swell stays at 3 for its whole life")
	# changing the config later does not change a run in progress
	s.run.swell_start = 5
	s.run.swell_every = 5
	s.run.swell_max = 1
	s.save()
	var s2 := _reload()
	check(s2.run.swell_start == 5 and s2.run.swell_every == 5 and s2.run.swell_max == 1, "the run's own swell values survive a reload")
	# a Surge at turn 30 needs 5 free cells: with 4 it floods and says so
	var f := _session()
	f.run.turn = 41
	var b := Board.new()
	for i in b.cells.size():
		b.set_code(i, Creature.make(1 + (i % 2), 6))
	b.set_code(0, 0)
	b.set_code(1, 0)
	b.set_code(2, 0)
	b.set_code(3, 0)
	f.run.board = b
	f.run.turn = 41
	var res: Dictionary = f.try_move(_i(0, 4), 3)
	check(bool(res["flood"]) and int(f.run.flood_info["need"]) == 5, "at turn 42 the Surge needs 5 free cells (flood reports need %s)" % str(f.run.flood_info.get("need")))

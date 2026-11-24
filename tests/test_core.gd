extends SceneTree
## Headless rules tests.  Run:
##   godot --headless --path . --script res://tests/test_core.gd
## Exits non-zero if any check fails.

var passed: int = 0
var failed: int = 0
const SAVE_A: String = "user://test_save_a.json"

func _initialize() -> void:
	GameClock.set_tz_bias_seconds(0)
	GameClock.freeze(1795000000 + 12 * 3600)     # fixed tide phase so seeded Surges are repeatable
	_run_all()
	GameClock.reset()
	print("\n==== %d passed, %d failed ====" % [passed, failed])
	quit(1 if failed > 0 else 0)

func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("  ok   - ", msg)
	else:
		failed += 1
		print("  FAIL - ", msg)

func _fresh(rows: Array, turn: int = 0, currents: int = 2, path: String = SAVE_A) -> GameSession:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var s := GameSession.new()
	s.save_path = path
	s.start_run(Board.from_text(rows))
	_goals_done(s)
	s.run.turn = turn
	s.run.currents = currents
	s.run.tutorial = false
	return s

## These older tests assert exact balances; daily goal rewards have their own tests (test_tide.gd).
func _goals_done(s: GameSession) -> void:
	var done: Dictionary = {}
	for g in GameConfig.DAILY_GOALS:
		done[String(g["id"])] = true
	s.profile.daily = {"day": GameClock.local_day_key(), "progress": {}, "done": done}

func _i(r: int, c: int) -> int:
	return Board.idx(r, c)

func _code(f: String, t: int) -> int:
	return Creature.make(1 if f == "S" else 2, t)

func _run_all() -> void:
	t_rng_and_rewards()
	t_pair_merge()
	t_illegal_moves_are_free()
	t_move_into_empty()
	t_starter_layout_opening_chain()
	t_line_via_pair_result()
	t_wrapped_current_line()
	t_current_free_and_wrap_rules()
	t_chain_refund_once()
	t_tier_cap()
	t_line_rules()
	t_trio_neighbor_order()
	t_preexisting_lines_dormant()
	t_surge_turn_three()
	t_surge_does_not_trigger_matches()
	t_flood_without_partial_wave()
	t_stuck_and_tide()
	t_release_and_persistence()
	t_midrun_reload()
	t_seed_determinism()
	t_starter_first_run_reachability()

# ---------------------------------------------------------------------------------

func t_rng_and_rewards() -> void:
	print("[rewards + rng]")
	check(Rewards.scale(25, 0) == 25, "step 0 is 1x")
	check(Rewards.scale(25, 1) == 38, "25 x1.5 = 37.5 rounds half up to 38")
	check(Rewards.scale(10, 2) == 23, "10 x2.25 = 22.5 rounds half up to 23")
	check(Rewards.scale(1, 1) == 2, "1 x1.5 = 1.5 -> 2")
	check(Rewards.scale(1, 2) == 2, "1 x2.25 = 2.25 -> 2")
	check(Rewards.scale(60, 3) == 203, "60 x3.375 = 202.5 -> 203")
	check(Rewards.multiplier_label(2) == "2.25x", "label 2.25x")
	var a := SeededRng.new(42)
	var b := SeededRng.new(42)
	var same: bool = true
	for k in 50:
		same = same and a.next_u32() == b.next_u32()
	check(same, "same seed -> same sequence")
	var c := SeededRng.new(43)
	check(SeededRng.new(42).next_u32() != c.next_u32(), "different seed -> different first value")
	var d := SeededRng.new(7)
	for k in 10:
		d.next_u32()
	var e := SeededRng.new(1)
	e.state = d.state
	check(d.next_u32() == e.next_u32(), "restoring state resumes the sequence")

func t_pair_merge() -> void:
	print("[pair merge]")
	var s := _fresh(["S1 . . . . .", ". . . . . .", ". . . . . .", ". . . . S1 ."])
	var r: Dictionary = s.try_pair(_i(0, 0), _i(3, 4))
	check(r["ok"], "identical pair anywhere on the board merges")
	check(s.run.board.code_at(_i(3, 4)) == _code("S", 2), "destination holds next tier")
	check(s.run.board.code_at(_i(0, 0)) == 0, "source cell is emptied")
	check(r["turn_used"] and s.run.turn == 1, "uses exactly one turn")
	check(s.profile.coins == 10 and s.profile.pearls == 1, "pays 10 coins + 1 pearl at 1x")
	check(int(r["chain"]) == 0 and not r["refund"], "no chain, no refund")

func t_illegal_moves_are_free() -> void:
	print("[illegal moves spend nothing]")
	var s := _fresh(["S1 S2 . . . .", ". . . . . .", ". . . . . F1", ". . . . . ."])
	var before: PackedInt32Array = s.run.board.cells.duplicate()
	var r1: Dictionary = s.try_pair(_i(0, 0), _i(0, 1))
	var r2: Dictionary = s.try_pair(_i(0, 0), _i(2, 5))
	var r3: Dictionary = s.try_drop(_i(0, 0), _i(3, 3))   # empty, not adjacent
	var r4: Dictionary = s.try_drop(_i(1, 1), _i(0, 0))   # empty source
	check(not r1["ok"] and not r2["ok"] and not r3["ok"] and not r4["ok"], "four illegal moves are rejected")
	check(s.run.turn == 0 and s.profile.coins == 0, "no turn, no payout")
	check(s.run.board.cells == before, "board untouched")
	check(s.run.currents == 2, "Currents untouched")
	var r5: Dictionary = s.try_release(_i(0, 0))
	check(not r5["ok"], "tier 1 cannot use the Reef Gate")

func t_move_into_empty() -> void:
	print("[move into empty cell]")
	var s := _fresh(["S1 . . . . .", ". . . . . ."])
	var r: Dictionary = s.try_drop(_i(0, 0), _i(0, 1))
	check(r["ok"] and s.run.board.code_at(_i(0, 1)) == _code("S", 1), "adjacent empty move is legal")
	check(s.run.turn == 1, "costs one turn")
	var r2: Dictionary = s.try_drop(_i(0, 1), _i(1, 2))   # diagonal
	check(not r2["ok"] and s.run.turn == 1, "diagonal rejected, turn kept")

func t_starter_layout_opening_chain() -> void:
	print("[starter layout: opening merge chains]")
	var path := "user://test_starter.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var s := GameSession.new()
	s.save_path = path
	s.start_run()
	_goals_done(s)
	check(s.run.tutorial and s.run.board.creature_count() == GameConfig.START_CREATURES, "first run: starter layout, 12 creatures")
	check(s.run.currents == 2, "two starting Currents")
	var has_family: Dictionary = {}
	var max_tier: int = 0
	for v in s.run.board.cells:
		if v != 0:
			has_family[Creature.family_of(v)] = true
			max_tier = maxi(max_tier, Creature.tier_of(v))
	check(has_family.size() == 2 and max_tier <= 3, "two families, only tiers 1-3 at start")
	var r: Dictionary = s.try_pair(_i(4, 1), _i(4, 2))
	check(r["ok"], "opening merge works")
	check(s.run.board.code_at(_i(4, 2)) == _code("S", 3), "result absorbed two adjacent tier-2 Shrimp into a tier 3")
	check(s.run.board.code_at(_i(3, 2)) == 0 and s.run.board.code_at(_i(4, 3)) == 0, "both neighbours consumed")
	check(int(r["chain"]) == 1, "chain of one follow-up")
	check(r["coins"] == 10 + 38 and r["pearls"] == 1 + 2, "pays 10 + 25x1.5(=38) coins and 1 + 1x1.5(=2) pearls")
	check(r["refund"] and s.run.currents == 3, "chain earns one Current back")
	check(s.run.turn == 1, "whole chain cost one turn")

func t_line_via_pair_result() -> void:
	print("[three in a row from a pair merge result]")
	var s := _fresh([". . . . . .", ". . . . . .", "S2 S2 S1 . . .", ". . . . . .", ". . . . S1 ."])
	var r: Dictionary = s.try_pair(_i(4, 4), _i(2, 2))
	check(s.run.board.code_at(_i(2, 1)) == _code("S", 4), "line of three tier-2 -> tier 4 in the MIDDLE cell")
	check(s.run.board.code_at(_i(2, 0)) == 0 and s.run.board.code_at(_i(2, 2)) == 0, "line ends consumed")
	check(r["coins"] == 10 + Rewards.scale(60, 1), "2nd merge of chain pays at 1.5x")
	check(s.run.board.creature_count() == 1, "only the tier 4 remains")

func t_wrapped_current_line() -> void:
	print("[wrapped Current makes a line]")
	var s := _fresh([". . . . . .", "F2 . . . F2 F2", ". . . . . ."], 0, 2)
	var pv: Dictionary = s.preview_current(Board.AXIS_ROW, 1, -1)
	check(pv["changes"] and pv["merges"] == 1 and pv["best_tier"] == 4, "preview reports the line before committing")
	check(s.run.board.code_at(_i(1, 0)) == _code("F", 2), "preview did not change the board")
	var r: Dictionary = s.try_current(Board.AXIS_ROW, 1, -1)
	check(r["ok"] and s.run.board.code_at(_i(1, 4)) == _code("F", 4), "wrap + line -> tier 4 in the middle (col 4)")
	check(s.run.board.creature_count() == 1, "three starfish became one")
	check(s.run.currents == 1, "Current spent")
	check(not r["refund"] and int(r["chain"]) == 0, "single merge is not a chain: no refund")
	check(r["coins"] == 60 and r["pearls"] == 3, "1x payout for the tier 4")
	check(s.run.turn == 1, "Current used one turn")

func t_current_free_and_wrap_rules() -> void:
	print("[Current: free no-op, wrap, empty cells shift]")
	var s := _fresh(["S1 S2 F1 . . ."], 0, 2)
	var r0: Dictionary = s.try_current(Board.AXIS_ROW, 3, 1)   # empty row
	check(r0["ok"] and r0["free"] and s.run.currents == 2 and s.run.turn == 0, "shift that changes nothing is free")
	var r00: Dictionary = s.try_current(Board.AXIS_ROW, 0, -1)
	check(s.run.board.code_at(_i(0, 5)) == _code("S", 1), "left shift wraps (0,0) to (0,5)")
	check(s.run.board.code_at(_i(0, 0)) == _code("S", 2) and s.run.board.code_at(_i(0, 2)) == 0, "others move left, empties travel")
	check(s.run.currents == 1 and s.run.turn == 1, "real shift spends a Current and a turn")
	var col := _fresh([". . . . . .", ". . . . . .", ". . . . . .", ". . . . . .", ". . . . . .", ". . . . . .", "F3 . . . . ."], 0, 2)
	col.try_current(Board.AXIS_COL, 0, 1)   # down: wraps to top
	check(col.run.board.code_at(_i(0, 0)) == _code("F", 3), "column shift down wraps bottom to top")
	var none := _fresh(["S1 . . . . ."], 0, 0)
	check(not none.try_current(Board.AXIS_ROW, 0, 1)["ok"], "no charges -> rejected")

func t_chain_refund_once() -> void:
	print("[chain refund at most once per turn]")
	# Merge S1+S1 -> S2 at (3,2). That joins three S2 into a vertical line (-> S4)
	# which sits next to two S4... build a 2-follow-up chain.
	var s := _fresh([
		". . . . . .",
		". . . . . .",
		". . S2 . . .",
		". . S2 . . .",
		". . S1 . . .",
		". . S1 . . .",
	], 0, 2)
	var r: Dictionary = s.try_pair(_i(5, 2), _i(4, 2))
	# (4,2) -> S2; vertical line (2,2),(3,2),(4,2) -> S4 at (3,2)
	check(s.run.board.code_at(_i(3, 2)) == _code("S", 4), "line completes from the pair result")
	var s2 := _fresh([
		". . . . . .",
		". . S4 S4 . .",
		". . . S3 . .",
		". . S2 S2 S1 .",
		". . . . . S1",
	], 0, 2)
	# S1+S1 -> S2 at (3,4): line (3,2),(3,3),(3,4) of S2 -> S4 at (3,3);
	# then S4 at (3,3)... neighbours: N=(2,3) is S3, no.  keep as 1 follow-up.
	var r2: Dictionary = s2.try_pair(_i(4, 5), _i(3, 4))
	check(int(r2["chain"]) == 1 and r2["refund"] and s2.run.currents == 3, "one follow-up -> +1 Current")
	# Two follow-ups: line -> S4 at (3,3) which then has two S4 neighbours N and... build it
	var s3 := _fresh([
		". . . . . .",
		". . . S4 . .",
		". . . . . .",
		". . S2 S2 S1 .",
		". . . S4 . S1",
	], 0, 2)
	var r3: Dictionary = s3.try_pair(_i(4, 5), _i(3, 4))
	# S2 line -> S4 at (3,3). Neighbours of (3,3): N (2,3) empty; S (4,3)=S4 only one -> stop.
	check(int(r3["chain"]) == 1, "single neighbour is not enough for a trio")
	var s4 := _fresh([
		". . . . . .",
		". . . S4 . .",
		". . . . . .",
		". . S2 S2 S1 .",
		". . . S4 . S1",
	], 0, 2)
	s4.run.board.set_code(_i(2, 3), _code("S", 4))   # now N (2,3) and S (4,3) neighbours both S4
	var r4: Dictionary = s4.try_pair(_i(4, 5), _i(3, 4))
	# line -> S4 at (3,3). Vertical windows through it: rows 1-3 (first in scan order) = S4 S4 S4
	# -> S6 in that window's middle cell (2,3); the S4 at (4,3) is left over.
	check(s4.run.board.code_at(_i(2, 3)) == _code("S", 6), "follow-up line from the result: 3 x tier 4 -> tier 6 in the window's middle")
	check(s4.run.board.code_at(_i(1, 3)) == 0 and s4.run.board.code_at(_i(3, 3)) == 0 and s4.run.board.code_at(_i(4, 3)) == _code("S", 4), "scan order picks rows 1-3; the spare S4 stays")
	check(int(r4["chain"]) == 2, "chain of two follow-ups")
	check(s4.run.currents == 3, "refund is +1 even though chain had 2 follow-ups")
	check(r4["coins"] == 10 + Rewards.scale(60, 1) + Rewards.scale(400, 2), "payouts at 1x, 1.5x, 2.25x")

func t_tier_cap() -> void:
	print("[tier cap]")
	var s := _fresh(["S6 . . S6 . .", ". . . . . .", "F5 F5 F5 . . ."], 0, 2)
	var r: Dictionary = s.try_pair(_i(0, 0), _i(0, 3))
	check(not r["ok"] and s.run.turn == 0, "two tier 6 cannot merge; rejected and free")
	check(s.run.board.code_at(_i(0, 0)) == _code("S", 6), "both tier 6 stay on the board")
	var v := s.valid_targets(_i(0, 0))
	check(v["merge"].is_empty() and v["gate"], "tier 6: no merge targets, Reef Gate valid")
	# a line of three tier-5 would make tier 7: ineligible, left untouched by a Current wrap
	var s2 := _fresh([". . . . . .", "F5 . . F5 F5 .", ". . . . . ."], 0, 2)
	s2.try_current(Board.AXIS_ROW, 1, -1)  # F5 F5 F5 wraps into a line at cols 2..4? (cols 2,3 + wrapped to 5)
	var n5: int = 0
	for v2 in s2.run.board.cells:
		if v2 == _code("F", 5):
			n5 += 1
	check(n5 == 3, "line of tier 5 would exceed tier 6, so it stays three tier-5s")
	# T5 pair -> T6 result; two adjacent T6 would make T7 so trio is ineligible
	var s3 := _fresh([". . . . . .", ". S5 S5 . . .", ". S6 . S6 . .", ". . . . . ."], 0, 2)
	s3.try_pair(_i(1, 1), _i(1, 2))
	check(s3.run.board.code_at(_i(1, 2)) == _code("S", 6) and s3.run.board.code_at(_i(2, 1)) == _code("S", 6), "tier 6 result with tier 6 neighbours: trio ineligible, all stay")
	# tier 5 trio -> tier 6 is allowed
	var s4 := _fresh([". . . . . .", ". S4 S4 . . .", ". S5 . . . .", ". S5 . . . ."], 0, 2)
	s4.try_pair(_i(1, 1), _i(1, 2))
	check(s4.run.board.code_at(_i(1, 2)) == _code("S", 5), "(sanity) tier 4 pair -> tier 5")
	# NOTE: neighbours of (1,2) are (1,1) empty now, (2,2) empty: S5 at (2,1) is diagonal -> no trio
	var s5 := _fresh([". . . . . .", ". . S4 S4 . .", ". . S5 . . .", ". . . S5 . ."], 0, 2)
	s5.try_pair(_i(1, 3), _i(1, 2))
	check(s5.run.board.code_at(_i(1, 2)) == _code("S", 5), "tier 5 result; only one orthogonal S5 neighbour")
	var s6 := _fresh([". . . . . .", ". S5 S4 S4 . .", ". . S5 . . .", ". . . . . ."], 0, 2)
	s6.try_pair(_i(1, 3), _i(1, 2))
	check(s6.run.board.code_at(_i(1, 2)) == _code("S", 6) and s6.run.board.creature_count() == 1, "tier-5 result + two tier-5 neighbours -> trio -> tier 6")

func t_line_rules() -> void:
	print("[line ordering]")
	# A move creates a horizontal AND a vertical line sharing a cell: horizontal first.
	var s := _fresh([
		". . S1 . . .",
		". . S1 . . .",
		"S1 S1 . S1 . .",
		". . . . . .",
	], 0, 2)
	# move S1 at (2,3) -> (2,2): now row 2 has S1 S1 S1 (cols 0-2) and column 2 has rows 0-2 S1 S1 S1
	var r: Dictionary = s.try_drop(_i(2, 3), _i(2, 2))
	var ev0: Dictionary = r["events"][1]
	check(ev0["kind"] == "line" and int(ev0["result_cell"]) == _i(2, 1), "horizontal line resolves first (middle cell (2,1))")
	check(s.run.board.code_at(_i(2, 1)) == _code("S", 3), "tier 1 line -> tier 3")
	# Column line remains broken: (2,2) consumed by horizontal line, so vertical (0..2,2) no longer complete
	check(s.run.board.code_at(_i(0, 2)) == _code("S", 1) and s.run.board.code_at(_i(1, 2)) == _code("S", 1), "overlapping vertical line was broken by the first resolution")
	# four in a row: leftmost three combine
	var s2 := _fresh([". . . . . .", "F1 F1 F1 . F1 .", ". . . . . ."], 0, 2)
	s2.try_drop(_i(1, 4), _i(1, 3))
	# Only windows that include a cell the move changed may fire (the old trio at
	# cols 0-2 was already on the board), so the first such window is cols 1-3.
	check(s2.run.board.code_at(_i(1, 2)) == _code("F", 3), "four in a row: first window containing the moved cell combines into its middle")
	check(s2.run.board.code_at(_i(1, 0)) == _code("F", 1), "the spare creature remains")
	# vertical line
	var s3 := _fresh([". . F1 . . .", ". . F1 . . .", ". F1 . . . .", ". . . . . ."], 0, 2)
	s3.try_drop(_i(2, 1), _i(2, 2))
	check(s3.run.board.code_at(_i(1, 2)) == _code("F", 3), "vertical line -> middle cell holds tier+2")

func t_trio_neighbor_order() -> void:
	print("[adjacent trio + fixed neighbour order]")
	# result at (2,2) has S2 neighbours N, E and W? Need a non-line trio: N and E only first.
	var s := _fresh([
		". . S2 . . .",
		". . . . . .",
		". S1 S1 S2 . .",
		". . S2 . . .",
	], 0, 2)
	# (2,2) result S2 after merge. Neighbours: N (1,2)? empty. rows: row0 col2 = S2, row1 empty -> N empty.
	# E (2,3)=S2, S (3,2)=S2 -> exactly two, an L shape (no line).
	s.try_pair(_i(2, 1), _i(2, 2))
	check(s.run.board.code_at(_i(2, 2)) == _code("S", 3), "L-shaped trio consumed into tier 3 at the result cell")
	check(s.run.board.code_at(_i(2, 3)) == 0 and s.run.board.code_at(_i(3, 2)) == 0, "E and S neighbours consumed")
	# Extra candidate: N,E,S all match -> but N+S is a vertical line (checked first).
	var s2 := _fresh([
		". . . . . .",
		". . S2 . . .",
		". S1 S1 S2 . .",
		". . S2 . . .",
	], 0, 2)
	s2.try_pair(_i(2, 1), _i(2, 2))
	check(s2.run.board.code_at(_i(2, 2)) == _code("S", 4) and s2.run.board.code_at(_i(2, 3)) == _code("S", 2), "a line through the result beats a trio: vertical line -> S4, the E neighbour is untouched")
	# Pure fixed-order case: four-neighbour with no collinear pair possible isn't possible,
	# so verify the helper directly: N=E=S=W all match -> picks N then E.
	var b := Board.from_text([". S2 .", "S2 S2 S2", ". S2 ."])
	var partners: PackedInt32Array = MergeRules.find_trio_partners(b, _i(1, 1))
	check(partners.size() == 2 and partners[0] == _i(0, 1) and partners[1] == _i(1, 2), "fixed order N, E, S, W picks North then East")

func t_preexisting_lines_dormant() -> void:
	print("[starting layouts and Surges do not trigger matches]")
	var s := _fresh(["S1 S1 S1 . . .", ". . . . . .", ". . . . F1 ."], 0, 2)
	var r: Dictionary = s.try_drop(_i(2, 4), _i(2, 5))
	check(r["ok"] and s.run.board.code_at(_i(0, 0)) == _code("S", 1) and s.run.board.code_at(_i(0, 1)) == _code("S", 1), "an existing line elsewhere is left alone by an unrelated move")
	check(r["events"].size() == 1, "no merge events for the unrelated move")

func t_surge_turn_three() -> void:
	print("[Surge on turn three]")
	var s := _fresh(["S1 . . . . .", ". . . . . ."], 0, 2)
	var r1: Dictionary = s.try_drop(_i(0, 0), _i(0, 1))
	var r2: Dictionary = s.try_drop(_i(0, 1), _i(0, 2))
	check(r1["surge"].is_empty() and r2["surge"].is_empty(), "no Surge on turns 1 and 2")
	check(s.run.turns_until_surge() == 1, "counter shows one turn until the Surge")
	var board_before: PackedInt32Array = s.run.board.cells.duplicate()
	var r3: Dictionary = s.try_drop(_i(0, 2), _i(0, 3))
	check(r3["surge"].size() == 3, "turn 3 resolves the move, then picks three incoming creatures")
	check(s.run.board.code_at(_i(0, 3)) == _code("S", 1), "the move resolved first")
	var cells: Dictionary = {}
	var ok_cells: bool = true
	var ok_tiers: bool = true
	for p in r3["surge"]:
		cells[p["cell"]] = true
		ok_cells = ok_cells and s.run.board.code_at(int(p["cell"])) == 0
		ok_tiers = ok_tiers and Creature.tier_of(int(p["code"])) <= GameConfig.NATURAL_MAX_TIER
	check(cells.size() == 3, "three DISTINCT cells")
	check(ok_cells, "all chosen from empty cells of the resolved board")
	check(ok_tiers, "only natural tiers 1-3 spawn")
	var after_prev: PackedInt32Array = s.run.board.cells
	check(after_prev.count(0) == board_before.count(0) , "preview alone does not place creatures")
	check(not s.try_drop(_i(0, 3), _i(0, 4))["ok"], "input is rejected while the Surge is pending")
	var lr: Dictionary = s.land_surge()
	check(lr["events"].size() == 3 and s.run.board.creature_count() == 4, "landing places exactly three creatures")
	check(s.run.pending_surge.is_empty(), "pending Surge cleared")
	var r4: Dictionary = s.try_drop(_i(0, 3), _i(0, 4))
	check(r4["ok"] and s.run.turn == 4 and r4["surge"].is_empty(), "turn 4 has no Surge")

func t_surge_does_not_trigger_matches() -> void:
	print("[landing Surge never matches]")
	var s := _fresh(["S1 . . . . .", ". . . . . ."], 2, 2)
	# Force a surge that completes a line next to existing creatures
	s.run.board = Board.from_text(["S1 S1 . . . .", ". . . . . ."])
	s.run.pending_surge = [{"cell": _i(0, 2), "code": _code("S", 1)}, {"cell": _i(1, 0), "code": _code("F", 1)}, {"cell": _i(1, 1), "code": _code("F", 1)}]
	s.land_surge()
	check(s.run.board.code_at(_i(0, 0)) == _code("S", 1) and s.run.board.code_at(_i(0, 2)) == _code("S", 1), "Surge that forms a line leaves it in place")

func t_flood_without_partial_wave() -> void:
	print("[flood when the wave cannot fit]")
	# 40 creatures, 2 empty cells; a slide on turn 3 keeps 2 empty -> cannot fit three.
	var rows: Array = []
	for r in GameConfig.ROWS:
		var toks: PackedStringArray = PackedStringArray()
		for c in GameConfig.COLS:
			toks.append("S1" if (r + c) % 2 == 0 else "F2")
		rows.append(" ".join(toks))
	var s := _fresh(rows, 2, 2)
	s.run.board.set_code(_i(6, 4), 0)   # (6,4): 6+4 even -> S1 originally; now empty
	s.run.board.set_code(_i(6, 5), 0)
	var coins_before: int = s.profile.coins
	var cells_before: PackedInt32Array = s.run.board.cells.duplicate()
	var r: Dictionary = s.try_drop(_i(6, 3), _i(6, 4))
	check(r["ok"], "the turn-3 move itself resolves")
	check(r["flood"] and s.run.status == RunState.FLOODED, "fewer than three free cells -> flood")
	check(r["surge"].is_empty() and s.run.pending_surge.is_empty(), "no partial wave spawned")
	var after_creatures: int = s.run.board.creature_count()
	check(after_creatures == cells_before.size() - 2, "no creature was added by the failed wave")
	check(s.profile.coins >= coins_before, "earned rewards are preserved")
	check(not s.try_drop(_i(0, 0), _i(0, 1))["ok"], "no more play after the flood")
	# survivors can still be released from the summary
	s.run.board.set_code(_i(0, 0), _code("F", 4))
	var rel: Dictionary = s.try_release(_i(0, 0))
	check(rel["ok"] and s.profile.residents.size() == 1, "tier 4+ survivor can be released after the flood")

func t_stuck_and_tide() -> void:
	print("[no legal move -> advance the tide]")
	# A genuinely stuck position cannot occur in this milestone: a full 42-cell board must repeat
	# creatures, repeats at tiers 1-3 are mergeable pairs and tiers 4-6 are releasable. The
	# fail-safe is therefore exercised with a test-only flag.
	var rows: Array = []
	for r in GameConfig.ROWS:
		var toks: PackedStringArray = PackedStringArray()
		for c in GameConfig.COLS:
			toks.append("S1")
		rows.append(" ".join(toks))
	var s := _fresh(rows, 0, 0)
	check(not s.is_stuck(), "a full board with pairs is not stuck")
	check(not s.advance_tide()["ok"], "advance_tide rejected while moves exist")
	var s2 := _fresh(["S1 F1 S2 F2 S3 F3"], 4, 0)
	check(not s2.is_stuck(), "creatures beside empty cells always have a move")
	s2.force_stuck_for_testing = true
	check(s2.is_stuck(), "(forced) stuck")
	var r: Dictionary = s2.advance_tide()
	check(r["ok"] and s2.run.turn == 6 and r["surge"].size() == 3, "advancing the tide jumps to the next Surge boundary (turn 4 -> 6) and previews it")
	check(s2.run.stats["tides"] == 1, "tide counted")
	# Stuck and full -> the advanced wave cannot fit -> flood
	var full := _fresh(rows, 1, 0)
	full.force_stuck_for_testing = true
	var rf: Dictionary = full.advance_tide()
	check(rf["flood"] and full.run.status == RunState.FLOODED and full.run.pending_surge.is_empty(), "stuck on a full board: tide advance floods without a partial wave")

func t_release_and_persistence() -> void:
	print("[release + persistence]")
	var s := _fresh([". . . . . .", ". F4 . . S5 .", ". . . . . ."], 5, 2)
	s.profile.coins = 123
	s.profile.pearls = 7
	var turn_before: int = s.run.turn
	var r: Dictionary = s.try_release(_i(1, 1))
	check(r["ok"], "tier 4 passes through the Reef Gate")
	check(s.run.board.code_at(_i(1, 1)) == 0, "removed from the board immediately")
	check(s.profile.residents.size() == 1 and s.profile.residents[0]["code"] == _code("F", 4), "exactly one resident created")
	check(s.run.turn == turn_before and not r["turn_used"], "costs no turn")
	var again: Dictionary = s.try_release(_i(1, 1))
	check(not again["ok"] and s.profile.residents.size() == 1, "cannot release the same creature twice")
	# reload
	var s2 := GameSession.new()
	s2.save_path = SAVE_A
	s2.load_or_new()
	check(s2.profile.residents.size() == 1, "resident survives reload (count 1)")
	check(s2.run.board.code_at(_i(1, 1)) == 0 and s2.run.board.code_at(_i(1, 4)) == _code("S", 5), "board identical after reload")
	check(s2.profile.coins == 123 and s2.profile.pearls == 7, "balances identical after reload")
	check(s2.run.turn == 5 and s2.run.currents == 2, "turn and Currents identical after reload")
	# second release then reload again: no duplicates
	s2.try_release(_i(1, 4))
	var s3 := GameSession.new()
	s3.save_path = SAVE_A
	s3.load_or_new()
	check(s3.profile.residents.size() == 2, "two releases -> two residents after reload")
	check(s3.profile.residents[0]["id"] != s3.profile.residents[1]["id"], "resident ids are unique")
	# a new run keeps residents and rewards
	s3.start_run()
	check(s3.profile.residents.size() == 2 and s3.profile.coins == 123, "fresh run carries rewards and residents")
	check(s3.run.currents == GameConfig.START_CURRENTS and s3.run.turn == 0, "fresh run resets turn and Currents")

func t_midrun_reload() -> void:
	print("[reload mid-run resumes exactly]")
	var s := _fresh(["S1 . . . . .", ". . . . . .", ". . . . . ."], 0, 2)
	s.try_drop(_i(0, 0), _i(0, 1))
	s.try_drop(_i(0, 1), _i(0, 2))
	var r3: Dictionary = s.try_drop(_i(0, 2), _i(0, 3))    # turn 3: surge pending
	var pending: Array = s.run.pending_surge.duplicate(true)
	var snapshot: PackedInt32Array = s.run.board.cells.duplicate()
	var coins: int = s.profile.coins
	var s2 := GameSession.new()
	s2.save_path = SAVE_A
	s2.load_or_new()
	check(s2.run.board.cells == snapshot, "board identical")
	check(s2.run.turn == 3 and s2.run.currents == 2, "turn count and Current charges identical")
	check(s2.run.pending_surge.size() == 3 and str(s2.run.pending_surge) == str(pending), "pending Surge restored (same cells and tiers)")
	check(s2.profile.coins == coins, "no payout duplicated")
	# RNG continues the same sequence
	var a: int = s.run.rng.next_u32()
	var b: int = s2.run.rng.next_u32()
	check(a == b, "random stream continues identically after reload")
	# paid action then reload: coins counted once
	var s3 := _fresh([". . . . . .", "S1 . . . . S1"], 0, 2)
	s3.try_pair(_i(1, 0), _i(1, 5))
	var s4 := GameSession.new()
	s4.save_path = SAVE_A
	s4.load_or_new()
	check(s4.profile.coins == 10 and s4.profile.pearls == 1, "payout saved once with the action that earned it")

func t_seed_determinism() -> void:
	print("[seeded determinism]")
	var out: Array = []
	for k in 2:
		var s := GameSession.new()
		s.save_path = "user://test_seed.json"
		s.autosave = false
		s.base_seed = 777
		s.start_run(Board.from_text(["S1 . . . . .", ". . . . . ."]))
		s.run.turn = 2
		s.run.tutorial = false
		var r: Dictionary = s.try_drop(0, 1)
		out.append(str(r["surge"]))
	check(out[0] == out[1] and out[0] != "[]", "same seed + same moves -> identical Surge")
	var s_a := GameSession.new()
	s_a.autosave = false
	s_a.base_seed = 5
	s_a.profile.runs_started = 1
	s_a.start_run()
	var s_b := GameSession.new()
	s_b.autosave = false
	s_b.base_seed = 5
	s_b.profile.runs_started = 1
	s_b.start_run()
	check(s_a.run.board.cells == s_b.run.board.cells and s_a.run.board.creature_count() == 12, "random start layout is seed-reproducible with 12 creatures")
	var has_pair: bool = false
	var seen: Dictionary = {}
	for v in s_a.run.board.cells:
		if v != 0:
			if seen.has(v):
				has_pair = true
			seen[v] = true
	check(has_pair, "random layout always contains an opening merge")

func t_starter_first_run_reachability() -> void:
	print("[starter layout: the designed 3-turn route to a release]")
	var path := "user://test_starter2.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var s := GameSession.new()
	s.save_path = path
	s.start_run()
	var pv: Dictionary = s.preview_current(Board.AXIS_ROW, 1, -1)
	check(pv["changes"] and pv["best_tier"] == 3, "starter row 1 shifted left makes a tier 3 (the wrap makes a line)")
	var r: Dictionary = s.try_current(Board.AXIS_ROW, 1, -1)
	check(r["ok"] and s.run.board.code_at(_i(1, 4)) == _code("F", 3), "wrapped Current builds a tier-3 Starfish")
	s.try_pair(_i(1, 4), _i(2, 4))
	check(s.run.board.code_at(_i(2, 4)) == _code("F", 4), "merged with the other tier-3 Starfish -> tier 4")
	s.land_surge()
	var rel: Dictionary = s.try_release(_i(2, 4))
	check(rel["ok"] and s.profile.residents.size() == 1, "and it can be released")
	var s2 := GameSession.new()
	s2.save_path = path
	s2.start_run()
	s2.try_pair(_i(4, 1), _i(4, 2))        # opening merge + chain -> S3 at (4,2)
	var r2: Dictionary = s2.try_pair(_i(4, 2), _i(6, 4))   # S3 + S3 -> S4
	check(r2["ok"] and s2.run.board.code_at(_i(6, 4)) == _code("S", 4), "pair route to tier 4 is reachable on turn 2")

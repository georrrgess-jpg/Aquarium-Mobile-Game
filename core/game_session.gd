class_name GameSession
extends RefCounted
## The game's rules front door. Every player action goes through here, is
## resolved completely (merges, payouts, refund, turn, Surge selection) and then
## saved in ONE write. The UI only replays the returned events as animation, so
## a reload at any moment lands on the already-resolved state and can never
## repeat a payout or a release.
##
## Action result dictionary:
##   ok, reason     - rejected actions have ok=false and spend nothing
##   turn_used      - whether a turn was spent
##   free           - a no-op Current (costs nothing)
##   events         - ordered animation events (see _step_event and friends)
##   coins, pearls  - total paid by this action
##   chain          - longest follow-up count in this action
##   refund         - a Current was earned back
##   surge          - [{cell, code}] chosen for the preview (not landed yet)
##   flood          - the Surge could not fit; the run is now FLOODED

var profile: Profile = Profile.new()
var run: RunState = null
var save_path: String = GameConfig.SAVE_PATH
var autosave: bool = true
var base_seed: int = GameConfig.DEFAULT_BASE_SEED
## Test/dev only: pretend there are no legal actions (see is_stuck).
var force_stuck_for_testing: bool = false

# --- Lifecycle -------------------------------------------------------------------

func load_or_new() -> void:
	var data: Dictionary = SaveStore.read(save_path)
	if data.is_empty():
		profile = Profile.new()
		run = null
	else:
		profile = data["profile"]
		run = data["run"]
	# first settlement after launch: any real gap since the last save is away time (-> chest)
	ReefEconomy.settle(profile, GameClock.now())

func save() -> void:
	if autosave:
		SaveStore.write(save_path, profile, run)

func has_active_run() -> bool:
	return run != null

func is_playing() -> bool:
	return run != null and run.status == RunState.ACTIVE

## Begin a fresh run. Banked rewards and residents carry over untouched.
## `layout` (optional) is a Board used instead of the generated start.
func start_run(layout: Board = null) -> void:
	if run != null:
		end_run(false)
	profile.runs_started += 1
	var n: int = profile.runs_started
	run = RunState.new()
	run.run_number = n
	run.seed_value = (base_seed + (n - 1) * 7919) & 0xFFFFFFFF
	run.rng = SeededRng.new(run.seed_value)
	run.currents = GameConfig.START_CURRENTS
	run.tide = Tide.phase_at()
	run.spawn_table = Tide.spawn_table(run.tide)       # fixed for the life of this run
	run.tutorial = (n == 1)
	if layout != null:
		run.board = layout
	elif run.tutorial:
		run.board = _starter_board()
	else:
		run.board = _random_board()
	save()

## Retire the finished run (rewards were paid as they happened).
func end_run(do_save: bool = true) -> void:
	if run != null:
		profile.runs_finished += 1
	run = null
	if do_save:
		save()

func tick(dt: float) -> void:
	if run != null and run.status == RunState.ACTIVE:
		run.elapsed += dt

func set_setting(key: String, value: bool) -> void:
	profile.settings[key] = value
	save()

# --- Layouts ---------------------------------------------------------------------

func _starter_board() -> Board:
	var b := Board.new()
	for e in GameConfig.STARTER_LAYOUT:
		b.set_code(Board.idx(e[0], e[1]), Creature.make(e[2], e[3]))
	return b

func _random_board() -> Board:
	var b := Board.new()
	var pool: Array = range(Board.cell_count())
	var placed: Array = []
	for i in GameConfig.START_CREATURES:
		var j: int = i + run.rng.int_range(0, pool.size() - 1 - i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
		placed.append(pool[i])
		b.set_code(pool[i], _roll_natural())
	# Guarantee an opening merge exists.
	var has_pair: bool = false
	var seen: Dictionary = {}
	for c in placed:
		var code: int = b.code_at(c)
		if seen.has(code):
			has_pair = true
		seen[code] = true
	if not has_pair:
		b.set_code(placed[1], b.code_at(placed[0]))
	return b

func _roll_natural() -> int:
	var table: Array = run.spawn_table if not run.spawn_table.is_empty() else GameConfig.SPAWN_TABLE
	var weights: Array = []
	for e in table:
		weights.append(e[2])
	var e: Array = table[run.rng.pick_weighted(weights)]
	return Creature.make(e[0], e[1])

# --- Queries ---------------------------------------------------------------------

## Why the player cannot act right now ("" when they can).
func _block_reason() -> String:
	if run == null:
		return "No run in progress"
	if run.status != RunState.ACTIVE:
		return "The pool has flooded"
	if not run.pending_surge.is_empty():
		return "A Surge is landing"
	return ""

func valid_targets(cell: int) -> Dictionary:
	var out: Dictionary = {"merge": PackedInt32Array(), "move": PackedInt32Array(), "gate": false}
	if run == null:
		return out
	var b: Board = run.board
	var code: int = b.code_at(cell)
	if code == 0:
		return out
	for i in b.cells.size():
		if MergeRules.can_pair(b, cell, i):
			out["merge"].append(i)
	for n in b.neighbors(cell):
		if n >= 0 and b.code_at(n) == 0:
			out["move"].append(n)
	out["gate"] = Creature.tier_of(code) >= GameConfig.RELEASE_MIN_TIER
	return out

## Preview what a Current would do without committing it.
func preview_current(axis: int, index: int, dir: int) -> Dictionary:
	var b: Board = run.board
	var shifted: PackedInt32Array = b.shifted(axis, index, dir)
	if shifted == b.cells:
		return {"changes": false, "merges": 0, "best_tier": 0, "steps": []}
	var sim: Board = b.copy()
	sim.cells = shifted
	var dirty: Dictionary = _changed_cells(b.cells, shifted)
	var steps: Array = MergeRules.resolve(sim, dirty, -1, 0)
	var best: int = 0
	var lines: Array = []
	for st in steps:
		best = maxi(best, int(st["tier"]))
		lines.append({"kind": st["kind"], "sources": st["sources"], "result_cell": st["result_cell"], "tier": st["tier"]})
	return {"changes": true, "merges": steps.size(), "best_tier": best, "steps": lines}

## True when nothing can be done: no pair, no slide into an empty cell, no
## Current that changes the board, and nothing eligible for the Reef Gate.
func is_stuck() -> bool:
	if _block_reason() != "":
		return false
	if force_stuck_for_testing:
		return true
	var b: Board = run.board
	var counts: Dictionary = {}
	for i in b.cells.size():
		var code: int = b.code_at(i)
		if code == 0:
			continue
		if Creature.tier_of(code) >= GameConfig.RELEASE_MIN_TIER:
			return false
		if Creature.tier_of(code) < GameConfig.MAX_TIER:
			counts[code] = int(counts.get(code, 0)) + 1
			if counts[code] >= 2:
				return false
		for n in b.neighbors(i):
			if n >= 0 and b.code_at(n) == 0:
				return false
	if run.currents > 0:
		for axis in [Board.AXIS_ROW, Board.AXIS_COL]:
			var n_lines: int = GameConfig.ROWS if axis == Board.AXIS_ROW else GameConfig.COLS
			for idx in n_lines:
				for dir in [-1, 1]:
					if b.shifted(axis, idx, dir) != b.cells:
						return false
	return true

# --- Actions ---------------------------------------------------------------------

func _new_result() -> Dictionary:
	return {
		"ok": true, "reason": "", "turn_used": false, "free": false,
		"events": [], "coins": 0, "pearls": 0, "chain": 0, "refund": false,
		"surge": [], "flood": false,
		"goals_done": [], "visitor_created": false, "visitor_complete": false,
	}

func _reject(reason: String) -> Dictionary:
	var r: Dictionary = _new_result()
	r["ok"] = false
	r["reason"] = reason
	return r

## Dispatch for a drag/tap from `src` onto `dst`.
func try_drop(src: int, dst: int) -> Dictionary:
	if run != null and dst >= 0 and dst < run.board.cells.size() and run.board.code_at(dst) != 0:
		return try_pair(src, dst)
	return try_move(src, dst)

func try_pair(src: int, dst: int) -> Dictionary:
	var why: String = _block_reason()
	if why != "":
		return _reject(why)
	var b: Board = run.board
	var n: int = b.cells.size()
	if src < 0 or src >= n or dst < 0 or dst >= n or src == dst:
		return _reject("Pick two different creatures")
	var code: int = b.code_at(src)
	if code == 0:
		return _reject("Pick a creature first")
	if b.code_at(dst) != code:
		return _reject("Only identical creatures merge")
	if Creature.tier_of(code) >= GameConfig.MAX_TIER:
		return _reject("Top tier! Send it through the Reef Gate")
	var res: Dictionary = _new_result()
	res["turn_used"] = true
	var result_code: int = code + 1
	b.set_code(src, 0)
	b.set_code(dst, result_code)
	run.stats["merges"] += 1
	var ev: Dictionary = {
		"t": "pair", "from": src, "to": dst, "result_cell": dst,
		"code": result_code, "tier": Creature.tier_of(result_code), "step": 0,
	}
	_pay(res, ev)
	res["events"].append(ev)
	var steps: Array = MergeRules.resolve(b, {dst: true}, dst, 0)
	_apply_steps(res, steps)
	_record_progress(res)
	_finish_turn(res)
	return res

func try_move(src: int, dst: int) -> Dictionary:
	var why: String = _block_reason()
	if why != "":
		return _reject(why)
	var b: Board = run.board
	var n: int = b.cells.size()
	if src < 0 or src >= n or dst < 0 or dst >= n or src == dst:
		return _reject("Pick a creature, then a spot")
	if b.code_at(src) == 0:
		return _reject("Pick a creature first")
	if b.code_at(dst) != 0:
		return _reject("Only identical creatures merge")
	if not b.is_adjacent(src, dst):
		return _reject("Creatures slide one cell at a time")
	var res: Dictionary = _new_result()
	res["turn_used"] = true
	b.set_code(dst, b.code_at(src))
	b.set_code(src, 0)
	res["events"].append({"t": "move", "from": src, "to": dst})
	var steps: Array = MergeRules.resolve(b, {dst: true}, -1, 0)
	_apply_steps(res, steps)
	_record_progress(res)
	_finish_turn(res)
	return res

func try_current(axis: int, index: int, dir: int) -> Dictionary:
	var why: String = _block_reason()
	if why != "":
		return _reject(why)
	if run.currents <= 0:
		return _reject("No Currents left")
	var b: Board = run.board
	var shifted: PackedInt32Array = b.shifted(axis, index, dir)
	var res: Dictionary = _new_result()
	if shifted == b.cells:
		res["free"] = true   # nothing would change: no turn, no Current spent
		return res
	var dirty: Dictionary = _changed_cells(b.cells, shifted)
	b.cells = shifted
	run.currents -= 1
	run.stats["shifts"] += 1
	res["turn_used"] = true
	res["events"].append({"t": "shift", "axis": axis, "index": index, "dir": dir})
	var steps: Array = MergeRules.resolve(b, dirty, -1, 0)
	_apply_steps(res, steps)
	_record_progress(res)
	_finish_turn(res)
	return res

## Send a tier 4+ creature through the Reef Gate. Costs no turn.
## Also valid on the flooded summary screen (survivors).
func try_release(cell: int) -> Dictionary:
	if run == null:
		return _reject("No run in progress")
	if run.status == RunState.ACTIVE and not run.pending_surge.is_empty():
		return _reject("A Surge is landing")
	var b: Board = run.board
	if cell < 0 or cell >= b.cells.size() or b.code_at(cell) == 0:
		return _reject("Pick a creature first")
	var code: int = b.code_at(cell)
	if Creature.tier_of(code) < GameConfig.RELEASE_MIN_TIER:
		return _reject("The Reef Gate wants tier %d or higher" % GameConfig.RELEASE_MIN_TIER)
	var res: Dictionary = _new_result()
	ReefEconomy.settle(profile, GameClock.now())   # old rate is paid before the roster changes it
	b.set_code(cell, 0)
	var rid: int = profile.next_resident_id
	profile.next_resident_id += 1
	profile.residents.append({
		"id": rid, "code": code, "family": Creature.family_of(code),
		"tier": Creature.tier_of(code), "run": run.run_number,
	})
	profile.unseen_residents.append(rid)
	run.stats["releases"] += 1
	res["events"].append({"t": "release", "cell": cell, "code": code, "resident_id": rid})
	# Update 3: this release may finish the Lantern Ray's request and count toward a daily goal.
	# Everything below is written by the single save() at the end, so a reload can never see
	# the release without the resident or the resident without the finished request.
	if Visitor.on_release(profile, code):
		var ray_id: int = profile.next_resident_id
		profile.next_resident_id += 1
		var ray_code: int = Creature.make(Creature.RAY, GameConfig.VISITOR_RESIDENT_TIER)
		profile.residents.append({"id": ray_id, "code": ray_code, "family": Creature.RAY, "tier": GameConfig.VISITOR_RESIDENT_TIER, "run": run.run_number})
		profile.unseen_residents.append(ray_id)
		res["visitor_complete"] = true
		res["events"].append({"t": "visitor_arrives", "resident_id": ray_id})
	res["goals_done"].append_array(DailyGoals.record(profile, "release", 1))
	save()
	return res

## When truly stuck, jump the tide to the next Surge.
func advance_tide() -> Dictionary:
	if not is_stuck():
		return _reject("You still have moves")
	var res: Dictionary = _new_result()
	res["turn_used"] = true
	var c: int = GameConfig.SURGE_CADENCE
	run.turn = (int(run.turn / float(c)) + 1) * c
	run.stats["tides"] += 1
	res["events"].append({"t": "tide"})
	_prepare_surge(res)
	save()
	return res

## Called by the UI once the preview has been shown.
func land_surge() -> Dictionary:
	var res: Dictionary = _new_result()
	if run == null or run.pending_surge.is_empty():
		return res
	for p in run.pending_surge:
		run.board.set_code(int(p["cell"]), int(p["code"]))
		res["events"].append({"t": "land", "cell": int(p["cell"]), "code": int(p["code"])})
	run.pending_surge = []
	# Landing never triggers matches (spec): no resolve() here.
	save()
	return res

# --- Reef (Update 2) ---------------------------------------------------------------------------

func income_rate() -> float:
	return ReefEconomy.rate_per_hour(profile)

## Credit passive income up to now (in memory; saved with the next committed action).
## Returns what the settlement did (see ReefEconomy.settle).
func settle_income() -> Dictionary:
	return ReefEconomy.settle(profile, GameClock.now())

## Pay the offline chest into the balance. Settles first so nothing is lost, then writes
## balance and cleared chest in ONE save; a second call pays nothing.
func claim_chest() -> int:
	ReefEconomy.settle(profile, GameClock.now())
	var paid: int = ReefEconomy.claim_chest(profile)
	save()
	return paid

## Buy and place a decoration. Income is settled at the old rate first; the charge, the
## new item and the new rate are written together. A repeat call is a free no-op.
func purchase_decoration(id: String, slot: int) -> Dictionary:
	var check: Dictionary = ReefEconomy.can_purchase(profile, id, slot)
	if not bool(check["ok"]):
		return check
	ReefEconomy.settle(profile, GameClock.now())
	var res: Dictionary = ReefEconomy.purchase(profile, id, slot)
	if bool(res["ok"]):
		save()
	return res

## The player has now looked at the reef: stop highlighting the newest residents.
func acknowledge_residents() -> void:
	if not profile.unseen_residents.is_empty():
		profile.unseen_residents = []
		save()

# --- Visitor, goals, trial (Update 3) --------------------------------------------------------

## Tap the Lantern Ray: accept its request (only while a window is open and none is active).
func accept_visitor() -> Dictionary:
	var r: Dictionary = Visitor.accept(profile, GameClock.now())
	if bool(r["ok"]):
		save()
	return r

## Keep the daily goals on today's local date (midnight rollover). In memory; saved with the next action.
func ensure_daily() -> bool:
	return DailyGoals.ensure_day(profile, GameClock.now())

## First clear of the Tide Trial pays a small reward once; repeats pay nothing. One write.
func claim_trial_reward() -> Dictionary:
	if bool(profile.trial.get("claimed", false)):
		return {"coins": 0, "pearls": 0, "first": false}
	profile.trial["cleared"] = true
	profile.trial["claimed"] = true
	profile.coins += GameConfig.TRIAL_REWARD_COINS
	profile.pearls += GameConfig.TRIAL_REWARD_PEARLS
	save()
	return {"coins": GameConfig.TRIAL_REWARD_COINS, "pearls": GameConfig.TRIAL_REWARD_PEARLS, "first": true}

# --- Internals -------------------------------------------------------------------

static func _changed_cells(before: PackedInt32Array, after: PackedInt32Array) -> Dictionary:
	var d: Dictionary = {}
	for i in before.size():
		if before[i] != after[i]:
			d[i] = true
	return d

func _pay(res: Dictionary, ev: Dictionary) -> void:
	var coins: int = Rewards.coins_for(int(ev["tier"]), int(ev["step"]))
	var pearls: int = Rewards.pearls_for(int(ev["tier"]), int(ev["step"]))
	ev["coins"] = coins
	ev["pearls"] = pearls
	profile.coins += coins
	profile.pearls += pearls
	run.stats["coins"] += coins
	run.stats["pearls"] += pearls
	res["coins"] += coins
	res["pearls"] += pearls
	res["chain"] = maxi(int(res["chain"]), int(ev["step"]))

func _apply_steps(res: Dictionary, steps: Array) -> void:
	var caused_follow_up: bool = false
	for s in steps:
		run.stats["merges"] += 1
		var ev: Dictionary = {
			"t": "merge", "kind": s["kind"], "sources": s["sources"],
			"emptied": s["emptied"], "result_cell": s["result_cell"],
			"code": s["code"], "tier": s["tier"], "step": s["step"],
		}
		_pay(res, ev)
		res["events"].append(ev)
		if bool(s["via_result"]):
			caused_follow_up = true
			run.stats["follow_ups"] += 1
	# An initial pair merge counts as the chain's step 0, so res.chain is the
	# follow-up count of the longest chain.
	if int(res["chain"]) >= 1:
		run.stats["chains"] += 1
		run.stats["best_chain"] = maxi(int(run.stats["best_chain"]), int(res["chain"]))
	if caused_follow_up:
		run.currents += GameConfig.CURRENT_REFUND_ON_CHAIN   # once per turn, by construction
		res["refund"] = true
		res["events"].append({"t": "refund"})

## Daily goals and the Lantern Ray's progress come from COMMITTED events only (never from a
## preview): the merges this action produced and whether it used a Current.
func _record_progress(res: Dictionary) -> void:
	var merges: int = 0
	var used_current: bool = false
	for ev in res["events"]:
		var t: String = String(ev["t"])
		if t == "pair" or t == "merge":
			merges += 1
			if Visitor.on_merge(profile, int(ev["code"])):
				res["visitor_created"] = true
		elif t == "shift":
			used_current = true
	if merges > 0:
		res["goals_done"].append_array(DailyGoals.record(profile, "merges", merges))
	if used_current:
		res["goals_done"].append_array(DailyGoals.record(profile, "current", 1))

func _finish_turn(res: Dictionary) -> void:
	run.turn += 1
	if run.surge_enabled and run.turn % GameConfig.SURGE_CADENCE == 0:
		_prepare_surge(res)
	save()

## Choose the Surge from the RESOLVED board. Too few empty cells -> flood, with
## no partial wave.
func _prepare_surge(res: Dictionary) -> void:
	var empties: PackedInt32Array = run.board.empty_cells()
	if empties.size() < GameConfig.SURGE_SIZE:
		run.status = RunState.FLOODED
		run.flood_info = {"free": empties.size(), "need": GameConfig.SURGE_SIZE}
		res["flood"] = true
		res["events"].append({"t": "flood", "free": empties.size(), "need": GameConfig.SURGE_SIZE})
		return
	var pool: Array = Array(empties)
	var picks: Array = []
	for i in GameConfig.SURGE_SIZE:
		var j: int = i + run.rng.int_range(0, pool.size() - 1 - i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
		picks.append(int(pool[i]))
	var pending: Array = []
	for cell in picks:
		pending.append({"cell": cell, "code": _roll_natural()})
	run.pending_surge = pending
	res["surge"] = pending.duplicate(true)

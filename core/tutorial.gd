class_name Tutorial
extends RefCounted
## The guided first run. Four steps, done in whatever order the player manages:
##   pair    - merge a matching pair
##   current - use a Current (after previewing it)
##   surge   - read the first Surge (it has landed)
##   release - send a tier 4+ creature through the Reef Gate  -> the tutorial is finished
## Progress lives in the run (RunState.tut_flags), so it is saved with the board and
## survives closing the game mid-step. Profile.tutorial records done / skipped / the
## first-release milestone.

const STEPS: Array = ["pair", "current", "surge", "release"]

static func default_state() -> Dictionary:
	return {"done": false, "skipped": false, "milestone": false, "restarts": 0}

static func new_flags() -> Dictionary:
	return {"pair": false, "current": false, "surge": false, "release": false}

## Index of the first step not done yet (STEPS.size() when everything is done).
static func step_of(flags: Dictionary) -> int:
	for i in STEPS.size():
		if not bool(flags.get(STEPS[i], false)):
			return i
	return STEPS.size()

## Update flags from a committed action's events.
static func observe(run: RunState, res: Dictionary) -> void:
	if not run.tutorial:
		return
	for ev in res["events"]:
		var t: String = String(ev["t"])
		if t == "pair":
			run.tut_flags["pair"] = true
		elif t == "shift":
			run.tut_flags["current"] = true
		elif t == "release" and Creature.tier_of(int(ev["code"])) >= GameConfig.RELEASE_MIN_TIER:
			run.tut_flags["release"] = true

## Can the player still finish the CURRENT step from this board? Used to offer a recovery
## (restart the guided board) when they have wandered off the example path. Uses the same
## rules and simulations as the Hint, and never changes the board or the random state.
static func goal_reachable(session: GameSession) -> bool:
	var run: RunState = session.run
	if run == null or run.status != RunState.ACTIVE:
		return true
	match step_of(run.tut_flags):
		0:
			return Hints.any_pair(run.board)
		1:
			if run.currents > 0 and Hints.any_effective_current(run.board):
				return true
			return Hints.has_chain_pair(run.board)       # a chain earns a Current back
		2:
			return true                                   # any move advances the tide; stuck -> advance it
		3:
			return Hints.can_reach_tier(run.board, GameConfig.RELEASE_MIN_TIER, 3)
	return true

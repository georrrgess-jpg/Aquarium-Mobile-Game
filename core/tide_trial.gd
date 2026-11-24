class_name TideTrial
extends RefCounted
## The handcrafted Tide Trial. It runs on its OWN GameSession with a throwaway Profile and
## a fixed board, so it can never touch a suspended regular run and nothing it pays is
## kept. Only the first clear grants a small reward, through GameSession.claim_trial_reward().
##
## Goal: wrap a Current round the edge so the wrapped piece completes a three-in-a-row,
## within a small move budget. Row 3 holds three Shrimp (one at each end, a pair at the
## other): shifting it LEFT wraps the end piece round and makes the line.

const PLAYING: int = 0
const WON: int = 1
const LOST: int = 2

const HINT_AXIS: int = Board.AXIS_ROW
const HINT_INDEX: int = 2
const HINT_DIR: int = -1

var session: GameSession
var moves_left: int = GameConfig.TRIAL_BUDGET
var status: int = PLAYING
var attempts: int = 0

static func layout_rows() -> Array:
	return [
		". F1 . . . .",
		". . . . . .",
		"S2 . . . S2 S2",
		". . . . . .",
		". . S3 . . .",
		". . . F1 . .",
		". . . . . .",
	]

func _init() -> void:
	new_attempt()

## A fresh try on the fixed board. Free and unlimited.
func new_attempt() -> void:
	attempts += 1
	session = GameSession.new()
	session.autosave = false              # trial turns are never saved
	session.profile = Profile.new()       # throwaway: nothing earned here is kept
	var run := RunState.new()
	run.board = Board.from_text(layout_rows())
	run.currents = GameConfig.TRIAL_CURRENTS
	run.run_number = 0
	run.tutorial = false
	run.surge_enabled = false
	run.rng = SeededRng.new(1)
	session.run = run
	moves_left = GameConfig.TRIAL_BUDGET
	status = PLAYING

## Cell the wrapped piece lands on for a shift of the given line/direction.
static func wrap_destination(axis: int, index: int, dir: int) -> int:
	var cells: PackedInt32Array = Board.line_cells(axis, index)
	var edge: int = cells[0] if dir < 0 else cells[cells.size() - 1]
	return Board.shifted_destination(edge, axis, dir)

## Update moves and win/lose after a session action. Returns true when the goal was met.
func evaluate(res: Dictionary) -> bool:
	if status != PLAYING or not bool(res.get("ok", false)):
		return false
	if bool(res.get("turn_used", false)):
		moves_left -= 1
	var shift: Dictionary = {}
	for ev in res["events"]:
		if String(ev["t"]) == "shift":
			shift = ev
	if not shift.is_empty():
		var wrapped: int = wrap_destination(int(shift["axis"]), int(shift["index"]), int(shift["dir"]))
		for ev in res["events"]:
			if String(ev["t"]) == "merge" and String(ev["kind"]) == "line" and (ev["sources"] as PackedInt32Array).has(wrapped):
				status = WON
				return true
	if moves_left <= 0:
		status = LOST
	return false

func hint() -> Dictionary:
	return {"axis": HINT_AXIS, "index": HINT_INDEX, "dir": HINT_DIR}

func goal_text() -> String:
	return "Wrap a Current round the edge to make three in a row. %d moves." % GameConfig.TRIAL_BUDGET

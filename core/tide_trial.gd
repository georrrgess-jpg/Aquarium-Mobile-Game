class_name TideTrial
extends RefCounted
## Handcrafted Tide Trials. Each runs on its OWN GameSession with a throwaway Profile and a
## fixed board, so it can never touch a suspended regular run and nothing it pays is kept.
## Only the first clear of each Trial grants a small reward (GameSession.claim_trial_reward).
## Retries are free and unlimited. Winning lines are proved against the real board rules by
## tests/test_trials.gd (an exhaustive search over every legal action within the budget).
##
##  wrap   Wrap a Current round the edge so the wrapped piece completes a three-in-a-row.
##  chain  Set up a chain: slide a piece beside the target, then drop its twin there so the
##         result finds two matching neighbours (a follow-up merge). Order matters.
##  space  Make room before a Surge: the pool has two free cells and the Surge needs three, so
##         a merge has to free one before the second move lands the wave.

const PLAYING: int = 0
const WON: int = 1
const LOST: int = 2

const IDS: Array = ["wrap", "chain", "space"]

const HINT_AXIS: int = Board.AXIS_ROW
const HINT_INDEX: int = 2
const HINT_DIR: int = -1

const DEFS: Dictionary = {
	"wrap": {
		"title": "Wrap Trial", "blurb": "Wrap a Current round the edge to make three in a row.",
		"budget": 2, "currents": 1, "surge": false, "turn": 0, "coins": 150, "pearls": 3,
		"rows": [". F1 . . . .", ". . . . . .", "S2 . . . S2 S2", ". . . . . .", ". . S3 . . .", ". . . F1 . .", ". . . . . ."],
		"goal": "Wrap a Current: make 3 in a row",
		"win": "A wrapped Current made your three in a row.",
		"lose": "Hint: shift row 3 left, so the edge piece wraps round. Retries are free.",
	},
	"chain": {
		"title": "Chain Trial", "blurb": "Set up a chain: slide first, then merge onto the right Shrimp.",
		"budget": 2, "currents": 0, "surge": false, "turn": 0, "coins": 120, "pearls": 2,
		"rows": [". . . . . .", ". . F2 . . .", ". . F1 . F2 .", ". . . . . .", "S1 . . . . .", ". . . . F1 .", ". S2 . . . S1"],
		"goal": "Slide, then merge to start a chain",
		"win": "The merge landed beside two matching Shrimp and set off a chain.",
		"lose": "Hint: slide the far Shrimp next to the pair target first, then drop its twin onto the marked Shrimp. Retries are free.",
	},
	"space": {
		"title": "Room Trial", "blurb": "Free a cell before the Surge lands, or the pool floods.",
		"budget": 2, "currents": 0, "surge": true, "turn": 1, "coins": 120, "pearls": 2,
		"rows": ["S6 F6 S6 F6 S6 F6", "F6 S6 F6 S6 F6 S6", "S6 F6 F1 S1 S6 F6", "F6 S6 F2 S2 F6 S6", "S6 F6 F3 S3 S6 F6", "F6 S6 F4 S4 F6 S6", "S6 F5 S5 S3 . ."],
		"goal": "Free a cell before the Surge lands",
		"win": "You made room, so the Surge landed safely.",
		"lose": "The Surge needed three free cells. Merge the matching pair to free one. Retries are free.",
	},
}

var id: String = "wrap"
var session: GameSession
var budget: int = 2
var moves_left: int = 2
var status: int = PLAYING
var attempts: int = 0

static func def_of(trial_id: String) -> Dictionary:
	return DEFS.get(trial_id, DEFS["wrap"])

static func layout_rows(trial_id: String = "wrap") -> Array:
	return def_of(trial_id)["rows"]

func _init(trial_id: String = "wrap") -> void:
	id = trial_id if DEFS.has(trial_id) else "wrap"
	budget = int(def_of(id)["budget"])
	new_attempt()

## A fresh try on the fixed board. Free and unlimited.
func new_attempt() -> void:
	attempts += 1
	var d: Dictionary = def_of(id)
	session = GameSession.new()
	session.autosave = false              # trial turns are never saved
	session.profile = Profile.new()       # throwaway: nothing earned here is kept
	var run := RunState.new()
	run.board = Board.from_text(layout_rows(id))
	run.currents = int(d["currents"])
	run.run_number = 0
	run.tutorial = false
	run.surge_enabled = bool(d["surge"])
	run.turn = int(d["turn"])
	run.rng = SeededRng.new(1)
	run.tide = Tide.MIDDAY
	run.spawn_table = Tide.spawn_table(Tide.MIDDAY)
	session.run = run
	moves_left = budget
	status = PLAYING

func title() -> String:
	return String(def_of(id)["title"])

func reward_coins() -> int:
	return int(def_of(id)["coins"])

func reward_pearls() -> int:
	return int(def_of(id)["pearls"])

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
	match id:
		"wrap":
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
		"chain":
			if int(res.get("chain", 0)) >= 1:
				status = WON
				return true
		"space":
			if bool(res.get("flood", false)):
				status = LOST
				return false
			if not (res.get("surge", []) as Array).is_empty():
				status = WON
				return true
	if moves_left <= 0:
		status = LOST
	return false

func goal_text() -> String:
	return String(def_of(id)["goal"])

func win_text() -> String:
	return String(def_of(id)["win"])

func lose_text() -> String:
	return String(def_of(id)["lose"])

## The idle prompt under the board.
func prompt_text() -> String:
	var left: String = "%d move%s left" % [moves_left, "" if moves_left == 1 else "s"]
	match id:
		"wrap":
			return "Goal: wrap a Current round the edge to make three in a row. %s." % left
		"chain":
			return "Goal: make a merge set off another. Slide, then merge. %s." % left
		_:
			return "Goal: free a cell before the Surge lands. %s." % left

## Wrap-trial hint (a row/direction), kept for the Current preview.
func hint() -> Dictionary:
	return {"axis": HINT_AXIS, "index": HINT_INDEX, "dir": HINT_DIR}

## One marked action for the other Trials, as a board `guide` dictionary
## ({from, to, label, style}); empty when there is nothing to mark.
func hint_guide() -> Dictionary:
	var b: Board = session.run.board
	match id:
		"chain":
			var target: int = Board.idx(2, 2)
			var beside: int = Board.idx(2, 3)
			if b.code_at(beside) == 0 and b.code_at(Board.idx(2, 4)) != 0:
				return {"from": Board.idx(2, 4), "to": beside, "label": "Slide it beside the target", "style": "move"}
			return {"from": Board.idx(5, 4), "to": target, "label": "Merge onto this one", "style": "pair"}
		"space":
			var cells: Array = []
			for i in b.cells.size():
				if b.code_at(i) != 0 and Creature.tier_of(b.code_at(i)) < GameConfig.MAX_TIER:
					for j in range(i + 1, b.cells.size()):
						if b.code_at(j) == b.code_at(i):
							return {"from": i, "to": j, "label": "These two merge", "style": "pair"}
	return {}

func hint_text() -> String:
	match id:
		"wrap":
			return "Hint: slide row %d to the LEFT. The edge piece wraps round to the far end." % (HINT_INDEX + 1)
		"chain":
			return "Hint: first slide the marked Shrimp beside the target, then drop its twin on the target."
		_:
			return "Hint: merge the matching pair. One fewer creature means one more free cell."

class_name RunState
extends RefCounted
## Everything about one run of the pool. Serialisable, UI-free.

const ACTIVE: int = 0
const FLOODED: int = 1

var board: Board = Board.new()
var turn: int = 0
var currents: int = 0
var seed_value: int = 0
var rng: SeededRng = SeededRng.new(1)
var status: int = ACTIVE
## Surge that has been chosen and is previewing but has not landed: [{cell, code}].
var pending_surge: Array = []
var flood_info: Dictionary = {}
var run_number: int = 1
var tutorial: bool = false
var elapsed: float = 0.0
var stats: Dictionary = {}

func _init() -> void:
	stats = default_stats()

static func default_stats() -> Dictionary:
	return {
		"merges": 0,
		"chains": 0,        # turns whose merges chained
		"best_chain": 0,    # most follow-ups in one chain
		"follow_ups": 0,    # total automatic follow-up merges
		"coins": 0,
		"pearls": 0,
		"releases": 0,
		"shifts": 0,
		"tides": 0,
	}

func to_dict() -> Dictionary:
	return {
		"board": board.to_array(),
		"turn": turn,
		"currents": currents,
		"seed": seed_value,
		"rng_state": rng.state,
		"status": status,
		"pending_surge": pending_surge.duplicate(true),
		"flood_info": flood_info.duplicate(true),
		"run_number": run_number,
		"tutorial": tutorial,
		"elapsed": elapsed,
		"stats": stats.duplicate(true),
	}

static func from_dict(d: Dictionary) -> RunState:
	var r := RunState.new()
	r.board = Board.from_array(d.get("board", []))
	r.turn = int(d.get("turn", 0))
	r.currents = int(d.get("currents", 0))
	r.seed_value = int(d.get("seed", 0))
	r.rng = SeededRng.new(1)
	r.rng.state = int(d.get("rng_state", 1))
	r.status = int(d.get("status", ACTIVE))
	r.pending_surge = []
	for p in d.get("pending_surge", []):
		r.pending_surge.append({"cell": int(p["cell"]), "code": int(p["code"])})
	r.flood_info = d.get("flood_info", {})
	r.run_number = int(d.get("run_number", 1))
	r.tutorial = bool(d.get("tutorial", false))
	r.elapsed = float(d.get("elapsed", 0.0))
	var s: Dictionary = RunState.default_stats()
	for k in d.get("stats", {}):
		s[k] = int(d["stats"][k])
	r.stats = s
	return r

func turns_until_surge() -> int:
	var c: int = GameConfig.SURGE_CADENCE
	return c - (turn % c)

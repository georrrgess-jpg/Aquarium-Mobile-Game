class_name Hints
extends RefCounted
## The optional Hint. Looks for one legal, useful action using the ACTIVE rules, on COPIES of
## the board, so the real board, the turn and the random state are never touched.
## Preference: a release, then a chain or a three-in-a-row, then a safe merge that frees
## space, with a Current suggested when a simulated shift clearly helps.
##
## Result: {kind, src, dst, current: {axis,index,dir}, cells: [..], text}
##   kind: release | chain | line | merge | current | slide | tide | none

const R_RELEASE: int = 100
const R_CHAIN: int = 60
const R_LINE: int = 50
const R_CURRENT: int = 40
const R_MERGE: int = 30

static func _none(text: String) -> Dictionary:
	return {"kind": "none", "src": -1, "dst": -1, "current": {}, "cells": [], "text": text}

static func any_pair(board: Board) -> bool:
	var seen: Dictionary = {}
	for i in board.cells.size():
		var c: int = board.code_at(i)
		if c != 0 and Creature.tier_of(c) < GameConfig.MAX_TIER:
			if seen.has(c):
				return true
			seen[c] = true
	return false

## Simulate merging src onto dst exactly as GameSession.try_pair does.
static func simulate_pair(board: Board, src: int, dst: int) -> Dictionary:
	var b: Board = board.copy()
	var code: int = b.code_at(src)
	b.set_code(src, 0)
	b.set_code(dst, code + 1)
	var steps: Array = MergeRules.resolve(b, {dst: true}, dst, 0)
	var chain: bool = false
	var line: bool = false
	var best_tier: int = Creature.tier_of(code + 1)
	for st in steps:
		chain = chain or bool(st["via_result"])
		line = line or String(st["kind"]) == MergeRules.KIND_LINE
		best_tier = maxi(best_tier, int(st["tier"]))
	return {"board": b, "chain": chain, "line": line, "freed": board.creature_count() - b.creature_count(), "tier": best_tier, "steps": steps.size()}

static func has_chain_pair(board: Board) -> bool:
	for i in board.cells.size():
		for j in board.cells.size():
			if i != j and MergeRules.can_pair(board, i, j) and bool(simulate_pair(board, i, j)["chain"]):
				return true
	return false

static func any_effective_current(board: Board) -> bool:
	for axis in [Board.AXIS_ROW, Board.AXIS_COL]:
		for idx in (GameConfig.ROWS if axis == Board.AXIS_ROW else GameConfig.COLS):
			for dir in [-1, 1]:
				if board.shifted(axis, idx, dir) != board.cells:
					return true
	return false

## Could a creature of at least `tier` appear within `depth` merges/Currents-free moves?
## Pair merges only (cheap, memoised); good enough to tell a dead guided board from a live one.
static func can_reach_tier(board: Board, tier: int, depth: int) -> bool:
	var memo: Dictionary = {}
	return _reach(board, tier, depth, memo)

static func _reach(board: Board, tier: int, depth: int, memo: Dictionary) -> bool:
	for c in board.cells:
		if Creature.tier_of(c) >= tier:
			return true
	if depth <= 0:
		return false
	var key: String = str(board.cells) + str(depth)
	if memo.has(key):
		return bool(memo[key])
	var found: bool = false
	var tried: Dictionary = {}
	for i in board.cells.size():
		var ci: int = board.code_at(i)
		if ci == 0 or tried.has(ci):
			continue
		for j in range(i + 1, board.cells.size()):
			if MergeRules.can_pair(board, i, j):
				tried[ci] = true
				if _reach(simulate_pair(board, i, j)["board"], tier, depth - 1, memo):
					found = true
				break
		if found:
			break
	memo[key] = found
	return found

## The single best suggestion for the player's pool right now.
static func suggest(session: GameSession) -> Dictionary:
	var run: RunState = session.run
	if run == null or run.status != RunState.ACTIVE:
		return _none("The pool has flooded.")
	if not run.pending_surge.is_empty():
		return _none("The Surge is landing. Hints come back in a moment.")
	var b: Board = run.board
	# 1. a release
	var best_cell: int = -1
	for i in b.cells.size():
		var c: int = b.code_at(i)
		if c != 0 and Creature.tier_of(c) >= GameConfig.RELEASE_MIN_TIER:
			if best_cell < 0 or c > b.code_at(best_cell):
				best_cell = i
	if best_cell >= 0:
		return {"kind": "release", "src": best_cell, "dst": -1, "current": {}, "cells": [best_cell],
			"text": "Hint: send this tier %d through the Reef Gate." % Creature.tier_of(b.code_at(best_cell))}
	# 2./3. pair merges (both directions: the result cell decides what chains)
	var best: Dictionary = {}
	var best_score: int = -1
	var tried: Dictionary = {}
	for i in b.cells.size():
		var ci: int = b.code_at(i)
		if ci == 0 or Creature.tier_of(ci) >= GameConfig.MAX_TIER:
			continue
		for j in b.cells.size():
			if i == j or b.code_at(j) != ci:
				continue
			var key: String = "%d>%d" % [i, j]
			if tried.has(key):
				continue
			tried[key] = true
			var sim: Dictionary = simulate_pair(b, i, j)
			var rank: int = R_MERGE
			var kind: String = "merge"
			var text: String = "Hint: merge these two. It frees a cell."
			if bool(sim["chain"]):
				rank = R_CHAIN
				kind = "chain"
				text = "Hint: merge these two. It chains and earns a Current back!"
			elif bool(sim["line"]):
				rank = R_LINE
				kind = "line"
				text = "Hint: merge these two. It makes a three in a row."
			var score: int = rank * 100 + int(sim["steps"]) * 10 + int(sim["freed"]) * 3 + int(sim["tier"])
			if score > best_score:
				best_score = score
				best = {"kind": kind, "src": i, "dst": j, "current": {}, "cells": [i, j], "text": text}
	# 4. a Current that obviously helps (a merge it sets up), when no chain/line merge is better
	if run.currents > 0:
		for axis in [Board.AXIS_ROW, Board.AXIS_COL]:
			for idx in (GameConfig.ROWS if axis == Board.AXIS_ROW else GameConfig.COLS):
				for dir in [-1, 1]:
					var pv: Dictionary = session.preview_current(axis, idx, dir)
					if bool(pv["changes"]) and int(pv["merges"]) > 0:
						var line_made: bool = false
						for st in pv["steps"]:
							line_made = line_made or String(st["kind"]) == MergeRules.KIND_LINE
						var rank2: int = R_CURRENT if line_made else R_MERGE - 1
						var score2: int = rank2 * 100 + int(pv["merges"]) * 10 + int(pv["best_tier"])
						if score2 > best_score:
							best_score = score2
							var dname: String = ("left" if dir < 0 else "right") if axis == Board.AXIS_ROW else ("up" if dir < 0 else "down")
							best = {"kind": "current", "src": -1, "dst": -1, "current": {"axis": axis, "index": idx, "dir": dir},
								"cells": [], "text": "Hint: slide %s %d %s. The wrap sets up a merge." % ["row" if axis == Board.AXIS_ROW else "column", idx + 1, dname]}
	if not best.is_empty():
		return best
	# 5. nothing to merge: a slide, or the tide
	if session.is_stuck():
		return {"kind": "tide", "src": -1, "dst": -1, "current": {}, "cells": [], "text": "No moves left. Use Advance the tide."}
	for i in b.cells.size():
		if b.code_at(i) == 0:
			continue
		for n in b.neighbors(i):
			if n >= 0 and b.code_at(n) == 0:
				return {"kind": "slide", "src": i, "dst": n, "current": {}, "cells": [i, n],
					"text": "No match yet. Slide a piece; the next Surge brings more."}
	return _none("No useful move found.")

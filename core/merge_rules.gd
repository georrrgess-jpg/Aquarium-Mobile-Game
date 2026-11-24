class_name MergeRules
extends RefCounted
## Pure merge rules. They mutate a Board but know nothing about turns, rewards
## or the UI.
##
## Order of resolution after a player action (pair merge / move / Current):
##  1. If the last merge produced a creature, look for a LINE of three through
##     it (horizontal before vertical). Otherwise a TRIO: two orthogonal
##     neighbours with the same family+tier (fixed neighbour order N,E,S,W).
##  2. If nothing follows from the last result, look for any LINE that includes
##     a "dirty" cell (a cell the action changed, or a merge result). Lines that
##     were already sitting on the board (starter layout, Surges) are not
##     touched, because they contain no dirty cell.
##  3. Repeat until stable. Scan order: top to bottom, left to right on the
##     window's first cell; every horizontal window is tried before any vertical.

const KIND_PAIR: String = "pair"
const KIND_LINE: String = "line"
const KIND_TRIO: String = "trio"

## Can the creature at `a` be merged onto `b` as a manual pair?
static func can_pair(board: Board, a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0:
		return false
	var ca: int = board.code_at(a)
	if ca == 0 or ca != board.code_at(b):
		return false
	return Creature.tier_of(ca) < GameConfig.MAX_TIER

## The three cells of the window starting at (r0, c0), or empty if off board.
static func window(r0: int, c0: int, horizontal: bool) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in 3:
		var r: int = r0 + (0 if horizontal else k)
		var c: int = c0 + (k if horizontal else 0)
		if r >= GameConfig.ROWS or c >= GameConfig.COLS:
			return PackedInt32Array()
		out.append(Board.idx(r, c))
	return out

static func _is_eligible_line(board: Board, w: PackedInt32Array) -> bool:
	var code: int = board.code_at(w[0])
	if code == 0 or board.code_at(w[1]) != code or board.code_at(w[2]) != code:
		return false
	return Creature.tier_of(code) + 2 <= GameConfig.MAX_TIER

## First eligible line window. `involving` >= 0 restricts to windows containing
## that cell; otherwise the window must contain at least one dirty cell.
static func find_line(board: Board, dirty: Dictionary, involving: int) -> PackedInt32Array:
	for horizontal in [true, false]:
		for r0 in GameConfig.ROWS:
			for c0 in GameConfig.COLS:
				var w: PackedInt32Array = window(r0, c0, horizontal)
				if w.is_empty():
					continue
				if involving >= 0:
					if not w.has(involving):
						continue
				else:
					if not (dirty.has(w[0]) or dirty.has(w[1]) or dirty.has(w[2])):
						continue
				if _is_eligible_line(board, w):
					return w
	return PackedInt32Array()

## Two same-family-and-tier neighbours of `cell`, in fixed N,E,S,W order.
static func find_trio_partners(board: Board, cell: int) -> PackedInt32Array:
	var code: int = board.code_at(cell)
	if code == 0 or Creature.tier_of(code) + 1 > GameConfig.MAX_TIER:
		return PackedInt32Array()
	var matches := PackedInt32Array()
	for n in board.neighbors(cell):
		if n >= 0 and board.code_at(n) == code:
			matches.append(n)
	if matches.size() < 2:
		return PackedInt32Array()
	return PackedInt32Array([matches[0], matches[1]])

## Resolve the automatic merges that follow an action. `dirty` is a set of
## cell indices (Dictionary used as a set), `last_result` the cell of the merge
## that started it (-1 for moves and Currents), `last_step` the chain step of
## that merge (0 for an initial pair merge).
## Returns an ordered list of step dictionaries and leaves `board` stable.
static func resolve(board: Board, dirty: Dictionary, last_result: int, last_step: int) -> Array:
	var steps: Array = []
	var current: int = last_result
	var chain_step: int = last_step
	var guard: int = 0
	while guard < 200:
		guard += 1
		var kind: String = ""
		var cells := PackedInt32Array()
		var via_result: bool = false
		if current >= 0:
			var w: PackedInt32Array = find_line(board, dirty, current)
			if not w.is_empty():
				kind = KIND_LINE
				cells = w
				via_result = true
			else:
				var partners: PackedInt32Array = find_trio_partners(board, current)
				if not partners.is_empty():
					kind = KIND_TRIO
					cells = PackedInt32Array([current, partners[0], partners[1]])
					via_result = true
		if kind == "":
			var w2: PackedInt32Array = find_line(board, dirty, -1)
			if not w2.is_empty():
				kind = KIND_LINE
				cells = w2
		if kind == "":
			break
		var result_cell: int
		var result_code: int
		var base_code: int = board.code_at(cells[0])
		var family: int = Creature.family_of(base_code)
		var tier: int = Creature.tier_of(base_code)
		var emptied := PackedInt32Array()
		if kind == KIND_LINE:
			result_cell = cells[1]
			result_code = Creature.make(family, tier + 2)
			emptied = PackedInt32Array([cells[0], cells[2]])
		else:
			result_cell = cells[0]
			result_code = Creature.make(family, tier + 1)
			emptied = PackedInt32Array([cells[1], cells[2]])
		for e in emptied:
			board.set_code(e, 0)
			dirty.erase(e)
		board.set_code(result_cell, result_code)
		dirty[result_cell] = true
		chain_step = (chain_step + 1) if via_result else 0
		steps.append({
			"kind": kind,
			"sources": cells,
			"emptied": emptied,
			"result_cell": result_cell,
			"code": result_code,
			"tier": Creature.tier_of(result_code),
			"step": chain_step,
			"via_result": via_result,
		})
		current = result_cell
	return steps

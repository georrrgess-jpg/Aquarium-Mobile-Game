class_name Board
extends RefCounted
## Plain grid data. No UI, no rules beyond geometry.

const AXIS_ROW: int = 0
const AXIS_COL: int = 1

var cells: PackedInt32Array = PackedInt32Array()

func _init() -> void:
	cells.resize(GameConfig.COLS * GameConfig.ROWS)
	cells.fill(0)

static func idx(row: int, col: int) -> int:
	return row * GameConfig.COLS + col

static func row_of(i: int) -> int:
	return int(i / float(GameConfig.COLS))

static func col_of(i: int) -> int:
	return i % GameConfig.COLS

static func cell_count() -> int:
	return GameConfig.COLS * GameConfig.ROWS

func code_at(i: int) -> int:
	return cells[i]

func set_code(i: int, code: int) -> void:
	cells[i] = code

func copy() -> Board:
	var b := Board.new()
	b.cells = cells.duplicate()
	return b

func empty_cells() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in cells.size():
		if cells[i] == 0:
			out.append(i)
	return out

func creature_count() -> int:
	return cells.size() - empty_cells().size()

## Orthogonal neighbours in the fixed order North, East, South, West (-1 = off board).
func neighbors(i: int) -> PackedInt32Array:
	var r: int = row_of(i)
	var c: int = col_of(i)
	var out := PackedInt32Array([-1, -1, -1, -1])
	if r > 0:
		out[0] = idx(r - 1, c)
	if c < GameConfig.COLS - 1:
		out[1] = idx(r, c + 1)
	if r < GameConfig.ROWS - 1:
		out[2] = idx(r + 1, c)
	if c > 0:
		out[3] = idx(r, c - 1)
	return out

func is_adjacent(a: int, b: int) -> bool:
	return neighbors(a).has(b)

## The cells of a row or column, in order.
static func line_cells(axis: int, index: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if axis == AXIS_ROW:
		for c in GameConfig.COLS:
			out.append(idx(index, c))
	else:
		for r in GameConfig.ROWS:
			out.append(idx(r, index))
	return out

## The board contents after shifting a line one cell. dir +1 = right/down,
## -1 = left/up. The edge cell wraps to the opposite end; empty cells travel too.
func shifted(axis: int, index: int, dir: int) -> PackedInt32Array:
	var out: PackedInt32Array = cells.duplicate()
	if axis == AXIS_ROW:
		for c in GameConfig.COLS:
			out[idx(index, c)] = cells[idx(index, posmod(c - dir, GameConfig.COLS))]
	else:
		for r in GameConfig.ROWS:
			out[idx(r, index)] = cells[idx(posmod(r - dir, GameConfig.ROWS), index)]
	return out

## Where the creature at `cell` ends up after a shift of its line.
static func shifted_destination(cell: int, axis: int, dir: int) -> int:
	var r: int = row_of(cell)
	var c: int = col_of(cell)
	if axis == AXIS_ROW:
		return idx(r, posmod(c + dir, GameConfig.COLS))
	return idx(posmod(r + dir, GameConfig.ROWS), c)

## True when the move wraps this cell round the edge.
static func shift_wraps(cell: int, axis: int, dir: int) -> bool:
	var r: int = row_of(cell)
	var c: int = col_of(cell)
	if axis == AXIS_ROW:
		return (dir > 0 and c == GameConfig.COLS - 1) or (dir < 0 and c == 0)
	return (dir > 0 and r == GameConfig.ROWS - 1) or (dir < 0 and r == 0)

func to_array() -> Array:
	var out: Array = []
	for v in cells:
		out.append(v)
	return out

static func from_array(arr: Array) -> Board:
	var b := Board.new()
	for i in mini(arr.size(), b.cells.size()):
		b.cells[i] = int(arr[i])
	return b

## Handy for tests and scenarios: rows of strings, e.g. "S1 .. F2".
## Tokens: ".", or S/F + tier digit.
static func from_text(rows: Array) -> Board:
	var b := Board.new()
	for r in rows.size():
		var tokens: PackedStringArray = String(rows[r]).split(" ", false)
		for c in tokens.size():
			var t: String = tokens[c]
			if t == "." or t == "..":
				continue
			var fam: int = Creature.SHRIMP if t[0] == "S" else Creature.STAR
			b.cells[idx(r, c)] = Creature.make(fam, int(t.substr(1)))
	return b

func to_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for r in GameConfig.ROWS:
		var toks: PackedStringArray = PackedStringArray()
		for c in GameConfig.COLS:
			var v: int = cells[idx(r, c)]
			if v == 0:
				toks.append(". ")
			else:
				toks.append("%s%d" % ["S" if Creature.family_of(v) == 1 else "F", Creature.tier_of(v)])
		lines.append(" ".join(toks))
	return "\n".join(lines)

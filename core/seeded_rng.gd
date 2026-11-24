class_name SeededRng
extends RefCounted
## Small deterministic PRNG (mulberry32). The whole state is one 32-bit integer,
## so it round-trips through JSON exactly and a reloaded run continues the same
## sequence as an uninterrupted one.

var state: int = 1

func _init(seed_value: int = 1) -> void:
	state = seed_value & 0xFFFFFFFF

func next_u32() -> int:
	state = (state + 0x6D2B79F5) & 0xFFFFFFFF
	var t: int = state
	t = ((t ^ (t >> 15)) * (t | 1)) & 0xFFFFFFFF
	t = (t ^ ((t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (t ^ (t >> 14)) & 0xFFFFFFFF

## Inclusive range.
func int_range(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + (next_u32() % (hi - lo + 1))

## Returns an index into weights, proportional to weight.
func pick_weighted(weights: Array) -> int:
	var total: int = 0
	for w in weights:
		total += int(w)
	var roll: int = int_range(0, total - 1)
	for i in weights.size():
		roll -= int(weights[i])
		if roll < 0:
			return i
	return weights.size() - 1

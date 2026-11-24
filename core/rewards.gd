class_name Rewards
extends RefCounted
## All payout maths. Integer only, so results are exact and reproducible.
##
## Rounding rule (the only place it is defined):
##   payout = round_half_up(base * (NUM/DEN)^step)
## where step 0 is the initial merge of a chain (1x) and each automatic
## follow-up adds one step. Computed as (2*base*NUM^step + DEN^step) / (2*DEN^step).

static func scale(base: int, step: int) -> int:
	var num: int = base
	var den: int = 1
	for i in step:
		num *= GameConfig.CHAIN_MULT_NUM
		den *= GameConfig.CHAIN_MULT_DEN
	return int((2 * num + den) / (2 * den))

static func coins_for(result_tier: int, step: int) -> int:
	return scale(int(GameConfig.COIN_BASE.get(result_tier, 0)), step)

static func pearls_for(result_tier: int, step: int) -> int:
	return scale(int(GameConfig.PEARL_BASE.get(result_tier, 0)), step)

## Display helper: "1x", "1.5x", "2.25x" ...
static func multiplier_label(step: int) -> String:
	var num: float = 1.0
	for i in step:
		num *= float(GameConfig.CHAIN_MULT_NUM) / float(GameConfig.CHAIN_MULT_DEN)
	if is_equal_approx(num, roundf(num)):
		return "%dx" % int(num)
	return ("%.2f" % num).rstrip("0").rstrip(".") + "x"

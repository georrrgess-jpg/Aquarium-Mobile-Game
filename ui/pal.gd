class_name Pal
extends RefCounted
## Colours for the placeholder look.

const BG_TOP := Color("0a2b40")
const BG_BOTTOM := Color("06192a")
const PANEL := Color("14455e")
const PANEL_DARK := Color("0d3248")
const CELL := Color("1d5a78")
const CELL_ALT := Color("1a5270")
const TEXT := Color("eaf7fc")
const TEXT_DIM := Color("9fc7d8")
const GOLD := Color("ffd166")
const TEAL := Color("5eead4")
const RED := Color("ff7a7a")
const SURGE := Color("ff9e5e")
const CURRENT := Color("6ec6ff")
const SHRIMP_BODY := Color("ff7d6e")
const SHRIMP_DARK := Color("b8453d")
const SHRIMP_LIGHT := Color("ffc2a8")
const STAR_BODY := Color("f6c453")
const STAR_DARK := Color("b9791f")
const STAR_LIGHT := Color("ffe9a0")
const INK := Color("0b1f2c")

## Ring/badge colour per tier (index = tier - 1).
const TIER_COLORS: Array = [
	Color("9fc7d8"), Color("5ad1a5"), Color("6fa8ff"),
	Color("ffd166"), Color("ff9a5c"), Color("ff6bb5"),
]

static func tier_color(tier: int) -> Color:
	return TIER_COLORS[clampi(tier - 1, 0, TIER_COLORS.size() - 1)]

class_name Pal
extends RefCounted
## Colours for the placeholder look.

# One look for pool, HUD and reef: clear teal water, warm sand, coral accents.
const BG_TOP := Color("0f6f84")
const BG_BOTTOM := Color("08394b")
const PANEL := Color("11697b")
const PANEL_DARK := Color("0a4555")
const CELL := Color("1b8196")
const CELL_ALT := Color("187789")
const TEXT := Color("fff6e0")
const TEXT_DIM := Color("e2d2a6")
const GOLD := Color("ffd166")
const TEAL := Color("5eead4")
const TARGET := Color("c4fff2")       # legal-target mint: light enough to read on teal tiles
const RED := Color("ff6f61")
const SURGE := Color("ff9e5e")
const CURRENT := Color("8fd8ff")
const CORAL := Color("ff7f6b")        # primary accent (buttons, highlights)
const CORAL_DARK := Color("b9473a")
const SAND := Color("f2dfb0")         # warm light surface (HUD chips, cards)
const SAND_DARK := Color("c9ad73")
const SAND_DEEP := Color("a98d55")
const SHRIMP_BODY := Color("ff7d6e")
const SHRIMP_DARK := Color("b8453d")
const SHRIMP_LIGHT := Color("ffc2a8")
const STAR_BODY := Color("f6c453")
const STAR_DARK := Color("b9791f")
const STAR_LIGHT := Color("ffe9a0")
const INK := Color("0b2a33")

## Ring/badge colour per tier (index = tier - 1).
const TIER_COLORS: Array = [
	Color("9fc7d8"), Color("5ad1a5"), Color("6fa8ff"),
	Color("ffd166"), Color("ff9a5c"), Color("ff6bb5"),
]

static func tier_color(tier: int) -> Color:
	return TIER_COLORS[clampi(tier - 1, 0, TIER_COLORS.size() - 1)]

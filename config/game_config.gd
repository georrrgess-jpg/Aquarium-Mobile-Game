class_name GameConfig
extends RefCounted
## Every tunable number for the first playable lives in this file:
## board size, spawn weights, surge cadence, starting Currents, reward values,
## chain rounding and UI timings. Nothing else in the project hardcodes them.

# --- Board ---------------------------------------------------------------------
const COLS: int = 6
const ROWS: int = 7
const MAX_TIER: int = 6
const NATURAL_MAX_TIER: int = 3     # only tiers 1-3 spawn naturally
const RELEASE_MIN_TIER: int = 4     # Reef Gate accepts tier 4+
const START_CREATURES: int = 12

# --- Turn / tide ---------------------------------------------------------------
const START_CURRENTS: int = 2
const SURGE_CADENCE: int = 3        # a Surge lands after every Nth turn
const SURGE_SIZE: int = 3           # creatures per Surge (needs this many empty cells)
const CURRENT_REFUND_ON_CHAIN: int = 1   # Currents earned by a chain, at most once per turn

## Natural spawn table: [family, tier, weight]. Used by Surges and by the
## random starting layouts of every run after the first.
const SPAWN_TABLE: Array = [
	[1, 1, 22], [1, 2, 9], [1, 3, 3],   # Shrimp
	[2, 1, 22], [2, 2, 9], [2, 3, 3],   # Starfish
]

# --- Rewards -------------------------------------------------------------------
## Base payout is looked up by the tier of the creature a merge PRODUCES.
const COIN_BASE: Dictionary = {2: 10, 3: 25, 4: 60, 5: 150, 6: 400}
const PEARL_BASE: Dictionary = {2: 1, 3: 1, 4: 3, 5: 6, 6: 12}
## Each automatic follow-up multiplies both base payouts by NUM/DEN again
## (1x, 1.5x, 2.25x, ...). Done in integers; see Rewards.scale() for rounding.
const CHAIN_MULT_NUM: int = 3
const CHAIN_MULT_DEN: int = 2

# --- First-run starter layout: [row, col, family, tier] ------------------------
# Shrimp = 1, Starfish = 2.
#  * Opening merge: the two tier-1 Shrimp at (4,1)+(4,2). The result touches two
#    tier-2 Shrimp, so it chains into a tier-3 and earns a Current back.
#  * Useful Current: row 1 holds three tier-2 Starfish. Shifting it LEFT wraps
#    the edge Starfish round and makes a line -> tier 4.
#  * Reachable tier 4 by plain pair merge: tier-3 Shrimp at (6,4) waits for the
#    chain's tier-3, and the two tier-3 Starfish merge anywhere on the board.
const STARTER_LAYOUT: Array = [
	[4, 1, 1, 1], [4, 2, 1, 1],
	[3, 2, 1, 2], [4, 3, 1, 2],
	[1, 0, 2, 2], [1, 4, 2, 2], [1, 5, 2, 2],
	[6, 4, 1, 3],
	[0, 2, 2, 1], [5, 5, 2, 1],
	[2, 4, 2, 3], [5, 1, 2, 3],
]

# --- Seeds ---------------------------------------------------------------------
const DEFAULT_BASE_SEED: int = 20260101

# --- Presentation timings (seconds) -----------------------------------------------
const T_SLIDE: float = 0.16
const T_POP: float = 0.26
const T_CHAIN_GAP: float = 0.20
const T_SURGE_PREVIEW: float = 1.5
const T_SURGE_PREVIEW_REDUCED: float = 1.8   # static, so give it a touch longer
const T_PEARL_FLIGHT: float = 0.55
const T_FLOOD_NOTICE: float = 1.8
const DRAG_THRESHOLD: float = 10.0

# --- Persistence ---------------------------------------------------------------
const SAVE_VERSION: int = 1
const SAVE_PATH: String = "user://tidepool_save.json"

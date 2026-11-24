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
#  * Useful Current: row 1 holds three tier-1 Starfish. Shifting it LEFT wraps the edge
#    Starfish round and makes a line -> a tier-3 Starfish in the middle (1,4).
#  * Guided route (3 turns): 1) merge the Shrimp pair (chain, +1 Current); 2) preview and
#    commit the Current on row 2, left (a line -> tier-3 Starfish); 3) merge the two tier-3
#    Starfish (or the two tier-3 Shrimp) -> tier 4, and the 3rd turn raises the first Surge.
#    Then release the tier 4 through the Reef Gate (free). Verified by tests/test_onboarding.gd.
const STARTER_LAYOUT: Array = [
	[4, 1, 1, 1], [4, 2, 1, 1],
	[3, 2, 1, 2], [4, 3, 1, 2],
	[1, 0, 2, 1], [1, 4, 2, 1], [1, 5, 2, 1],
	[6, 4, 1, 3],
	[0, 2, 2, 1], [5, 5, 2, 1],
	[2, 4, 2, 3], [5, 1, 2, 3],
]

# --- Reef economy (Update 2) -----------------------------------------------------------
## Passive coins per hour for one resident of tier t = PASSIVE_BASE * PASSIVE_TIER_GROWTH^(t-1).
## The whole reef is then multiplied by (1 + Beauty / BEAUTY_DIVISOR).
const PASSIVE_BASE_PER_HOUR: float = 5.0
const PASSIVE_TIER_GROWTH: float = 1.8
const BEAUTY_DIVISOR: float = 100.0
## Away time is banked in a chest and capped at this many hours (across repeated relaunches).
const OFFLINE_CAP_HOURS: int = 8
## A gap between two income settlements longer than this counts as "away" and goes to the chest
## instead of straight to the balance (the live game settles every second or so).
const OFFLINE_THRESHOLD_SEC: int = 90
const INCOME_TICK_SEC: float = 1.0
## Visual caps: every resident is always in the roster, but only these are drawn / animated.
const MAX_DRAWN_RESIDENTS: int = 18
const MAX_ANIMATED_RESIDENTS: int = 10

## Decorations, cheapest first. Each can be owned once and placed on one marked slot.
## Beauty adds to the reef multiplier; keep prices escalating and Beauty modest.
const DECORATIONS: Array = [
	{"id": "coral_fan", "name": "Coral Fan", "price": 120, "beauty": 3, "blurb": "A soft fan of pink coral."},
	{"id": "bubble_column", "name": "Bubble Column", "price": 450, "beauty": 5, "blurb": "A vent that never stops singing."},
	{"id": "sea_lantern", "name": "Sea Lantern", "price": 1200, "beauty": 8, "blurb": "Warm light for the night shift."},
	{"id": "sunken_statue", "name": "Sunken Statue", "price": 3000, "beauty": 12, "blurb": "Someone's old guardian."},
	{"id": "light_shaft", "name": "Light Shaft", "price": 7000, "beauty": 18, "blurb": "A beam straight from the surface."},
]
## Marked placement spots on the reef floor: x as a fraction of the aquarium width.
const DECOR_SLOTS: Array = [0.10, 0.27, 0.44, 0.61, 0.78, 0.92]

# --- Tide cycles, visitor, trial, daily goals (Update 3) --------------------------------------
## Local-time phases: 0 Dawn, 1 Midday, 2 Dusk, 3 Night. Hour each phase STARTS (Night runs 21:00-06:00).
const TIDE_START_HOURS: Dictionary = {0: 6, 1: 10, 2: 17, 3: 21}
## One readable spawn bias per phase. A rule multiplies the base weight of matching entries;
## family 0 = any family, tier 0 = any tier. Both starter families always stay available.
const TIDE_SPAWN_RULES: Dictionary = {
	0: [{"family": 1, "tier": 0, "mult": 1.5}],      # Dawn: Shrimp favoured
	1: [{"family": 0, "tier": 2, "mult": 1.8}],      # Midday: more mixed tier 2
	2: [{"family": 2, "tier": 0, "mult": 1.5}],      # Dusk: Starfish favoured
	3: [{"family": 0, "tier": 3, "mult": 1.7}],      # Night: slightly more tier 3
}
## The family a phase features (visitor requests ask for it). Midday and Night feature none.
const TIDE_FEATURED_FAMILY: Dictionary = {0: 1, 2: 2}

## The Lantern Ray visits during the first N minutes of these phases.
const VISITOR_PHASES: Array = [0, 2]
const VISITOR_WINDOW_MINUTES: int = 90
const VISITOR_RESIDENT_TIER: int = 4
const VISITOR_REQUEST_MIN_TIER: int = 4

## Tide Trial: fixed board, move budget, one Current, a small first-clear reward.
const TRIAL_BUDGET: int = 2
const TRIAL_CURRENTS: int = 1
const TRIAL_REWARD_COINS: int = 150
const TRIAL_REWARD_PEARLS: int = 3

## Daily goals, reset at local midnight; each pays once per local day when it completes.
const DAILY_GOALS: Array = [
	{"id": "merges", "label": "Make 8 merges", "target": 8, "coins": 60, "pearls": 1},
	{"id": "current", "label": "Use a Current", "target": 1, "coins": 40, "pearls": 0},
	{"id": "release", "label": "Release a tier 4+ creature", "target": 1, "coins": 100, "pearls": 2},
]

## Tide Goals (Update 4): one optional goal per standard run, drawn from this pool when the run
## begins and saved with it. Completing it pays once; missing it costs nothing.
const TIDE_GOAL_COINS: int = 80
const TIDE_GOAL_PEARLS: int = 2
const TIDE_GOALS: Array = [
	{"id": "chain", "label": "Set off a chain reaction", "short": "Chain reaction", "target": 1},
	{"id": "tier4", "label": "Make a tier 4 creature", "short": "Make a tier 4", "target": 1},
	{"id": "release_family", "label": "Release a tier 4+ %s", "short": "Release a %s", "target": 1},
	{"id": "merges", "label": "Make 12 merges", "short": "12 merges", "target": 12},
	{"id": "current_merge", "label": "Make a merge with a Current", "short": "Merge with a Current", "target": 1},
]

# --- Guided start, Calm Pool (Update 4) -----------------------------------------------------
const CALM_CADENCE: int = 5            # Calm Pool: a Surge every fifth turn
const CALM_START_CREATURES: int = 9    # a roomier start than a standard run

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
const SAVE_VERSION: int = 4
const SAVE_PATH: String = "user://tidepool_save.json"

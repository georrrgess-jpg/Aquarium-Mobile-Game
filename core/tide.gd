class_name Tide
extends RefCounted
## Four fixed local-time tide phases. Each run records the phase and its spawn weights
## when it is created, so a phase change later only affects future runs.

const DAWN: int = 0
const MIDDAY: int = 1
const DUSK: int = 2
const NIGHT: int = 3
const NAMES: Array = ["Dawn", "Midday", "Dusk", "Night"]

static func hour_secs(phase: int) -> int:
	return int(GameConfig.TIDE_START_HOURS[phase]) * 3600

## Phase for a unix time (local clock).
static func phase_at(unix: int = -1) -> int:
	var sod: int = GameClock.local_seconds_of_day(unix)
	if sod >= hour_secs(NIGHT) or sod < hour_secs(DAWN):
		return NIGHT
	if sod < hour_secs(MIDDAY):
		return DAWN
	if sod < hour_secs(DUSK):
		return MIDDAY
	return DUSK

## Unix time at which the phase containing `unix` started (Night may start the previous evening).
static func phase_start(unix: int = -1) -> int:
	var t: int = GameClock.now() if unix < 0 else unix
	var sod: int = GameClock.local_seconds_of_day(t)
	var day_start: int = t - sod
	var p: int = phase_at(t)
	if p == NIGHT and sod < hour_secs(DAWN):
		return day_start - (86400 - hour_secs(NIGHT))
	return day_start + hour_secs(p)

static func phase_name(phase: int) -> String:
	return String(NAMES[phase])

static func featured_family(phase: int) -> int:
	return int(GameConfig.TIDE_FEATURED_FAMILY.get(phase, 0))

## Spawn table [[family, tier, weight], ...] for a phase. Weights are integers (base x100,
## times the phase multiplier, rounded) so the seeded roll stays exact.
static func spawn_table(phase: int) -> Array:
	var out: Array = []
	var rules: Array = GameConfig.TIDE_SPAWN_RULES.get(phase, [])
	for e in GameConfig.SPAWN_TABLE:
		var w: float = float(e[2]) * 100.0
		for r in rules:
			var fam_ok: bool = int(r["family"]) == 0 or int(r["family"]) == int(e[0])
			var tier_ok: bool = int(r["tier"]) == 0 or int(r["tier"]) == int(e[1])
			if fam_ok and tier_ok:
				w *= float(r["mult"])
		out.append([int(e[0]), int(e[1]), int(round(w))])
	return out

## Share of spawns that are `family` (0 = any) and `tier` (0 = any) in a table.
static func share(table: Array, family: int, tier: int) -> float:
	var total: float = 0.0
	var hit: float = 0.0
	for e in table:
		total += float(e[2])
		if (family == 0 or int(e[0]) == family) and (tier == 0 or int(e[1]) == tier):
			hit += float(e[2])
	return hit / maxf(total, 1.0)

## Lighting for the reef (and the screen background). Light overlays/palette swaps only.
static func palette(phase: int) -> Dictionary:
	match phase:
		DAWN:
			return {"top": Color("f0b99a"), "bottom": Color("2c7f93"), "sand": Color("efd6a3"), "sand2": Color("d7b77a"),
				"ray": 0.12, "overlay": Color(1.0, 0.72, 0.55, 0.06), "weed": Color("4bb37a"), "bubble": Color(1, 1, 1, 0.45),
				"bg_top": Color("1c6f80"), "bg_bottom": Color("0d4658")}
		DUSK:
			return {"top": Color("d7849a"), "bottom": Color("2a3f75"), "sand": Color("e0b98a"), "sand2": Color("c1966b"),
				"ray": 0.09, "overlay": Color(0.55, 0.2, 0.45, 0.10), "weed": Color("3f9a73"), "bubble": Color(1, 0.9, 0.95, 0.4),
				"bg_top": Color("1b5679"), "bg_bottom": Color("162b57")}
		NIGHT:
			return {"top": Color("16355a"), "bottom": Color("050d22"), "sand": Color("a8946a"), "sand2": Color("8a7752"),
				"ray": 0.03, "overlay": Color(0.02, 0.05, 0.2, 0.18), "weed": Color("2f7f5c"), "bubble": Color(0.8, 0.9, 1, 0.3),
				"bg_top": Color("0c3550"), "bg_bottom": Color("040f1d")}
		_:
			return {"top": Color("33b0cc"), "bottom": Color("0a4a63"), "sand": Color("e9d196"), "sand2": Color("d0af6c"),
				"ray": 0.07, "overlay": Color(0, 0, 0, 0), "weed": Color("3fae6b"), "bubble": Color(1, 1, 1, 0.38),
				"bg_top": Color("0f6f84"), "bg_bottom": Color("08394b")}

## WCAG relative luminance and contrast ratio, to check text/grid readability per phase.
static func luminance(c: Color) -> float:
	var ch: Array = [c.r, c.g, c.b]
	var lin: Array = []
	for v in ch:
		lin.append(float(v) / 12.92 if float(v) <= 0.03928 else pow((float(v) + 0.055) / 1.055, 2.4))
	return 0.2126 * float(lin[0]) + 0.7152 * float(lin[1]) + 0.0722 * float(lin[2])

static func contrast(a: Color, b: Color) -> float:
	var la: float = luminance(a)
	var lb: float = luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

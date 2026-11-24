class_name Creature
extends RefCounted
## A creature on the board is a single int: family * 10 + tier. 0 means empty.

const NONE: int = 0
const SHRIMP: int = 1
const STAR: int = 2

const FAMILY_NAMES: Dictionary = {1: "Shrimp", 2: "Starfish"}
const TIER_NAMES: Dictionary = {
	1: ["Glass", "Cleaner", "Snapper", "Harlequin", "Mantis", "Emperor"],
	2: ["Sprig", "Sand", "Cushion", "Bat", "Sunflower", "Crown"],
}

static func make(family: int, tier: int) -> int:
	return family * 10 + tier

static func family_of(code: int) -> int:
	return int(code / 10.0)

static func tier_of(code: int) -> int:
	return code % 10

static func is_creature(code: int) -> bool:
	return code > 0

static func full_name(code: int) -> String:
	if code <= 0:
		return "empty"
	var names: Array = TIER_NAMES[family_of(code)]
	return "%s %s (T%d)" % [names[tier_of(code) - 1], FAMILY_NAMES[family_of(code)], tier_of(code)]

static func short_name(code: int) -> String:
	if code <= 0:
		return "-"
	return "%s T%d" % [FAMILY_NAMES[family_of(code)], tier_of(code)]

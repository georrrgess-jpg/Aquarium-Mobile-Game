class_name Book
extends RefCounted
## The Tidepool Book: which creatures the player has met. Entries are keyed by the stable
## id "family:tier" (family numbers and tier numbers never change), each
## {seen, made, released}. A tier is recorded the first time it is on the board or made, and
## marked a resident once released. Practice and Calm Pool never write to it.

const NOTES: Dictionary = {
	"1:1": "Glass shrimp are see-through; you can count their ribs by sunlight.",
	"1:2": "Cleaner shrimp tidy the shallows, nibbling parasites off passing fish.",
	"1:3": "A snapper's claw snaps shut with a crack louder than its body is long.",
	"1:4": "Harlequin shrimp wear spotted armour and hunt starfish arm by arm.",
	"1:5": "Mantis shrimp punch faster than a bullet and see colours nobody else can.",
	"1:6": "The emperor rides larger sea creatures and keeps a spotless shell.",
	"2:1": "Sprig stars are no wider than a thumbnail and hide under pebbles.",
	"2:2": "Sand stars slide just under the surface, leaving little zigzag trails.",
	"2:3": "A cushion star is almost round, as if it had forgotten its arms.",
	"2:4": "Bat stars browse the tide pools, webbed between the arms like a wing.",
	"2:5": "Sunflower stars have more than twenty arms and move in a hurry.",
	"2:6": "The crown star's spines ring its back like a coral reef in miniature.",
	"3:4": "The Lantern Ray glides in at the turn of the tide and lights the water it crosses.",
}

static func key(code: int) -> String:
	return "%d:%d" % [Creature.family_of(code), Creature.tier_of(code)]

static func entry(profile: Profile, code: int) -> Dictionary:
	return profile.book.get(key(code), {})

static func _touch(profile: Profile, code: int) -> Dictionary:
	var k: String = key(code)
	if not profile.book.has(k):
		profile.book[k] = {"seen": false, "made": false, "released": false}
	return profile.book[k]

## Record every creature currently on the board. Returns the codes seen for the first time.
static func observe_board(profile: Profile, board: Board) -> Array:
	var fresh: Array = []
	for i in board.cells.size():
		var code: int = board.code_at(i)
		if code == 0:
			continue
		var e: Dictionary = _touch(profile, code)
		if not bool(e["seen"]):
			e["seen"] = true
			fresh.append(code)
	return fresh

## A merge produced `code`. Returns true if the tier was new to the Book.
static func note_made(profile: Profile, code: int) -> bool:
	var e: Dictionary = _touch(profile, code)
	var was_new: bool = not bool(e["seen"])
	e["seen"] = true
	e["made"] = true
	return was_new

static func note_released(profile: Profile, code: int) -> bool:
	var e: Dictionary = _touch(profile, code)
	var was_new: bool = not bool(e["released"])
	e["seen"] = true
	e["made"] = true
	e["released"] = true
	return was_new

## "resident" (released), "found" (seen or made), "next" (not found, but the tier below is, so
## it can be reached by merging) or "hidden".
static func state_of(profile: Profile, family: int, tier: int) -> String:
	var code: int = Creature.make(family, tier)
	var e: Dictionary = entry(profile, code)
	if bool(e.get("released", false)):
		return "resident"
	if bool(e.get("seen", false)) or bool(e.get("made", false)):
		return "found"
	if family != Creature.RAY and tier > 1 and tier <= GameConfig.MAX_TIER:
		var below: Dictionary = entry(profile, Creature.make(family, tier - 1))
		if bool(below.get("seen", false)) or bool(below.get("made", false)):
			return "next"
	return "hidden"

## Everything the page needs, in display order.
static func species() -> Array:
	return [
		{"family": Creature.SHRIMP, "name": "Shrimp", "tiers": [1, 2, 3, 4, 5, 6]},
		{"family": Creature.STAR, "name": "Starfish", "tiers": [1, 2, 3, 4, 5, 6]},
		{"family": Creature.RAY, "name": "Lantern Ray", "tiers": [GameConfig.VISITOR_RESIDENT_TIER]},
	]

static func tier_name(code: int) -> String:
	var fam: int = Creature.family_of(code)
	if fam == Creature.RAY:
		return "Lantern Ray"
	return "%s %s" % [Creature.TIER_NAMES[fam][Creature.tier_of(code) - 1], Creature.FAMILY_NAMES[fam]]

static func note(code: int) -> String:
	return String(NOTES.get(key(code), ""))

static func counts(profile: Profile) -> Dictionary:
	var found: int = 0
	var total: int = 0
	var residents: int = 0
	for sp in species():
		for t in sp["tiers"]:
			total += 1
			var st: String = state_of(profile, int(sp["family"]), int(t))
			if st == "found" or st == "resident":
				found += 1
			if st == "resident":
				residents += 1
	return {"found": found, "total": total, "residents": residents}

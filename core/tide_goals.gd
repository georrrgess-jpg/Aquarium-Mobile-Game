class_name TideGoals
extends RefCounted
## One optional goal per standard run. It is drawn from GameConfig.TIDE_GOALS when the run
## begins (from the run's own seed, never the run's random stream, so boards stay reproducible)
## and stored on the run: {id, label, short, family, target, progress, done, coins, pearls}.
## It observes the same COMMITTED events the daily goals do and pays once, in the same save as
## the action that completed it. Missing it changes nothing else about the run.

## Pick the goal for a run. `spawn_table` = [[family, tier, weight]]; "release a featured family"
## only names a family that is actually in the table.
static func pick(seed_value: int, spawn_table: Array) -> Dictionary:
	var rng := SeededRng.new((seed_value ^ 0x7E1D) & 0xFFFFFFFF)
	var families: Array = []
	var table: Array = spawn_table if not spawn_table.is_empty() else GameConfig.SPAWN_TABLE
	for e in table:
		if int(e[2]) > 0 and not families.has(int(e[0])):
			families.append(int(e[0]))
	var defs: Array = GameConfig.TIDE_GOALS
	var def: Dictionary = defs[rng.int_range(0, defs.size() - 1)]
	var family: int = 0
	var label: String = String(def["label"])
	var short: String = String(def["short"])
	if String(def["id"]) == "release_family":
		family = int(families[rng.int_range(0, families.size() - 1)])
		var fname: String = String(Creature.FAMILY_NAMES[family])
		label = label % fname
		short = short % fname
	return {
		"id": String(def["id"]), "label": label, "short": short, "family": family,
		"target": int(def["target"]), "progress": 0, "done": false,
		"coins": GameConfig.TIDE_GOAL_COINS, "pearls": GameConfig.TIDE_GOAL_PEARLS,
	}

static func active(run: RunState) -> bool:
	return run != null and not run.goal.is_empty()

## Add progress from the events of one committed action. Returns the goal dictionary when this
## call completed it (and paid it), otherwise an empty dictionary.
static func observe(profile: Profile, run: RunState, res: Dictionary) -> Dictionary:
	if not active(run) or bool(run.goal["done"]) or run.practice or run.mode != "regular":
		return {}
	var id: String = String(run.goal["id"])
	var merges: int = 0
	var best_tier: int = 0
	var shifted: bool = false
	for ev in res["events"]:
		var t: String = String(ev["t"])
		if t == "pair" or t == "merge":
			merges += 1
			best_tier = maxi(best_tier, int(ev["tier"]))
		elif t == "shift":
			shifted = true
	var add: int = 0
	match id:
		"chain":
			add = 1 if int(res.get("chain", 0)) >= 1 else 0
		"tier4":
			add = 1 if best_tier >= 4 else 0
		"merges":
			add = merges
		"current_merge":
			add = 1 if (shifted and merges > 0) else 0
	return _add(profile, run, add)

## A release through the Reef Gate (committed). `code` is what was released.
static func observe_release(profile: Profile, run: RunState, code: int) -> Dictionary:
	if not active(run) or bool(run.goal["done"]) or run.practice or run.mode != "regular":
		return {}
	if String(run.goal["id"]) != "release_family":
		return {}
	if Creature.family_of(code) != int(run.goal["family"]):
		return {}
	return _add(profile, run, 1)

static func _add(profile: Profile, run: RunState, amount: int) -> Dictionary:
	if amount <= 0:
		return {}
	var g: Dictionary = run.goal
	g["progress"] = mini(int(g["target"]), int(g["progress"]) + amount)
	if int(g["progress"]) < int(g["target"]):
		return {}
	g["done"] = true
	profile.coins += int(g["coins"])
	profile.pearls += int(g["pearls"])
	return g.duplicate(true)

static func progress_text(run: RunState) -> String:
	if not active(run):
		return ""
	var g: Dictionary = run.goal
	if bool(g["done"]):
		return "Done"
	if int(g["target"]) > 1:
		return "%d/%d" % [int(g["progress"]), int(g["target"])]
	return ""

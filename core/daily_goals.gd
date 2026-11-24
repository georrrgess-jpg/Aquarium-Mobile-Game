class_name DailyGoals
extends RefCounted
## Three local daily goals driven by committed gameplay events. A goal pays once per local
## day; its reward and its completion are written in the same save. Rolls over at local midnight.
##
## profile.daily = { day: "YYYY-MM-DD", progress: {id: int}, done: {id: bool} }

static func default_state() -> Dictionary:
	return {"day": "", "progress": {}, "done": {}}

static func goal_def(id: String) -> Dictionary:
	for g in GameConfig.DAILY_GOALS:
		if String(g["id"]) == id:
			return g
	return {}

## Reset when the local day changed. Returns true if it rolled over.
static func ensure_day(profile: Profile, unix: int = -1) -> bool:
	var key: String = GameClock.local_day_key(unix)
	if String(profile.daily.get("day", "")) == key:
		return false
	profile.daily = {"day": key, "progress": {}, "done": {}}
	return true

static func progress(profile: Profile, id: String) -> int:
	return int((profile.daily.get("progress", {}) as Dictionary).get(id, 0))

static func is_done(profile: Profile, id: String) -> bool:
	return bool((profile.daily.get("done", {}) as Dictionary).get(id, false))

## Add progress from a committed event. Pays the reward the moment a goal completes (once).
## Returns the goals completed by this call: [{id, label, coins, pearls}].
static func record(profile: Profile, id: String, amount: int, unix: int = -1) -> Array:
	ensure_day(profile, unix)
	var def: Dictionary = goal_def(id)
	var finished: Array = []
	if def.is_empty() or amount <= 0 or is_done(profile, id):
		return finished
	var prog: Dictionary = profile.daily["progress"]
	prog[id] = mini(int(def["target"]), int(prog.get(id, 0)) + amount)
	if int(prog[id]) >= int(def["target"]):
		(profile.daily["done"] as Dictionary)[id] = true
		profile.coins += int(def["coins"])
		profile.pearls += int(def["pearls"])
		finished.append({"id": id, "label": String(def["label"]), "coins": int(def["coins"]), "pearls": int(def["pearls"])})
	return finished

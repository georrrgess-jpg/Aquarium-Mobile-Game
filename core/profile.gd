class_name Profile
extends RefCounted
## What survives between runs: banked rewards, reef residents, settings.

var coins: int = 0
var pearls: int = 0
## Each resident: {id, family, tier, code, run}
var residents: Array = []
var next_resident_id: int = 1
var runs_started: int = 0
var runs_finished: int = 0
var settings: Dictionary = {"reduced_motion": false, "sound": true, "haptics": true}
## Reef (Update 2). Decorations: [{id, slot}].
var decorations: Array = []
## Unix time income has been credited up to, and the fractional coin carried between settlements.
var income_stamp: int = 0
var income_frac: float = 0.0
## Offline chest: pending (unclaimed) coins and the away-seconds already counted toward the cap.
var chest_coins: float = 0.0
var chest_secs: int = 0
## Residents released since the player last looked at the reef (newest highlighted there).
var unseen_residents: Array = []
## Update 3: Lantern Ray visitor state, daily goals, Tide Trial first-clear flags.
var visitor: Dictionary = Visitor.default_state()
var daily: Dictionary = DailyGoals.default_state()
var trial: Dictionary = {"cleared": false, "claimed": false}

func to_dict() -> Dictionary:
	return {
		"coins": coins,
		"pearls": pearls,
		"residents": residents.duplicate(true),
		"next_resident_id": next_resident_id,
		"runs_started": runs_started,
		"runs_finished": runs_finished,
		"settings": settings.duplicate(true),
		"decorations": decorations.duplicate(true),
		"income_stamp": income_stamp,
		"income_frac": income_frac,
		"chest_coins": chest_coins,
		"chest_secs": chest_secs,
		"unseen_residents": unseen_residents.duplicate(),
		"visitor": visitor.duplicate(true),
		"daily": daily.duplicate(true),
		"trial": trial.duplicate(true),
	}

static func from_dict(d: Dictionary) -> Profile:
	var p := Profile.new()
	p.coins = int(d.get("coins", 0))
	p.pearls = int(d.get("pearls", 0))
	p.residents = []
	for r in d.get("residents", []):
		var code: int = int(r.get("code", 0))
		p.residents.append({
			"id": int(r.get("id", 0)),
			"code": code,
			"family": Creature.family_of(code),
			"tier": Creature.tier_of(code),
			"run": int(r.get("run", 0)),
		})
	p.next_resident_id = int(d.get("next_resident_id", p.residents.size() + 1))
	p.runs_started = int(d.get("runs_started", 0))
	p.runs_finished = int(d.get("runs_finished", 0))
	var s: Dictionary = d.get("settings", {})
	p.settings = {
		"reduced_motion": bool(s.get("reduced_motion", false)),
		"sound": bool(s.get("sound", true)),
		"haptics": bool(s.get("haptics", true)),
	}
	p.decorations = []
	for dd in d.get("decorations", []):
		p.decorations.append({"id": String(dd.get("id", "")), "slot": int(dd.get("slot", 0))})
	p.income_stamp = int(d.get("income_stamp", 0))
	p.income_frac = float(d.get("income_frac", 0.0))
	p.chest_coins = float(d.get("chest_coins", 0.0))
	p.chest_secs = int(d.get("chest_secs", 0))
	p.unseen_residents = []
	for u in d.get("unseen_residents", []):
		p.unseen_residents.append(int(u))
	var v: Dictionary = d.get("visitor", {})
	p.visitor = {"done": bool(v.get("done", false)), "request": {}}
	var rq: Dictionary = v.get("request", {})
	if not rq.is_empty():
		p.visitor["request"] = {"accepted_at": int(rq.get("accepted_at", 0)), "window_key": String(rq.get("window_key", "")), "family": int(rq.get("family", 0)), "created": bool(rq.get("created", false))}
	var dl: Dictionary = d.get("daily", {})
	p.daily = {"day": String(dl.get("day", "")), "progress": {}, "done": {}}
	for k in dl.get("progress", {}):
		p.daily["progress"][String(k)] = int(dl["progress"][k])
	for k in dl.get("done", {}):
		p.daily["done"][String(k)] = bool(dl["done"][k])
	var tr: Dictionary = d.get("trial", {})
	p.trial = {"cleared": bool(tr.get("cleared", false)), "claimed": bool(tr.get("claimed", false))}
	return p

func tier_counts() -> Dictionary:
	var out: Dictionary = {}
	for r in residents:
		var t: int = int(r["tier"])
		out[t] = int(out.get(t, 0)) + 1
	return out

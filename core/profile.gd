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
var settings: Dictionary = {"reduced_motion": false, "sound": true}

func to_dict() -> Dictionary:
	return {
		"coins": coins,
		"pearls": pearls,
		"residents": residents.duplicate(true),
		"next_resident_id": next_resident_id,
		"runs_started": runs_started,
		"runs_finished": runs_finished,
		"settings": settings.duplicate(true),
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
	}
	return p

func tier_counts() -> Dictionary:
	var out: Dictionary = {}
	for r in residents:
		var t: int = int(r["tier"])
		out[t] = int(out.get(t, 0)) + 1
	return out

class_name Visitor
extends RefCounted
## The Lantern Ray. It visits during the first VISITOR_WINDOW_MINUTES of Dawn and of Dusk
## and asks the player to make a tier 4+ creature of the phase's featured family and
## release it. Once accepted the request survives reload and the window closing. A missed
## window just means the next one is a fresh chance. Completing it grants ONE permanent
## Lantern Ray resident, exactly once.
##
## profile.visitor = { done: bool, request: {} | {accepted_at, window_key, family, created: bool} }

static func default_state() -> Dictionary:
	return {"done": false, "request": {}}

## The window the clock is currently in: {open, phase, key, starts, ends, family}.
static func window_at(unix: int = -1) -> Dictionary:
	var t: int = GameClock.now() if unix < 0 else unix
	var phase: int = Tide.phase_at(t)
	var out: Dictionary = {"open": false, "phase": phase, "key": "", "starts": 0, "ends": 0, "family": 0}
	if not GameConfig.VISITOR_PHASES.has(phase):
		return out
	var starts: int = Tide.phase_start(t)
	var ends: int = starts + GameConfig.VISITOR_WINDOW_MINUTES * 60
	out["starts"] = starts
	out["ends"] = ends
	out["key"] = "%s:%s" % [GameClock.local_day_key(starts), Tide.phase_name(phase).to_lower()]
	out["family"] = Tide.featured_family(phase)
	out["open"] = t >= starts and t < ends
	return out

static func has_request(profile: Profile) -> bool:
	return not (profile.visitor.get("request", {}) as Dictionary).is_empty()

## The visitor is on the reef and can be tapped to accept.
static func offered(profile: Profile, unix: int = -1) -> bool:
	if bool(profile.visitor.get("done", false)) or has_request(profile):
		return false
	return bool(window_at(unix)["open"])

## Accept the request. Fails outside a window, after completion, or while one is active.
static func accept(profile: Profile, unix: int = -1) -> Dictionary:
	var t: int = GameClock.now() if unix < 0 else unix
	if bool(profile.visitor.get("done", false)):
		return {"ok": false, "reason": "The Lantern Ray already lives in your reef"}
	if has_request(profile):
		return {"ok": false, "reason": "You already accepted its request"}
	var w: Dictionary = window_at(t)
	if not bool(w["open"]):
		return {"ok": false, "reason": "The Lantern Ray visits at dawn and dusk"}
	profile.visitor["request"] = {"accepted_at": t, "window_key": String(w["key"]), "family": int(w["family"]), "created": false}
	return {"ok": true, "reason": "", "family": int(w["family"])}

## A merge produced `code`. Progress begins after acceptance, so only called for committed actions.
static func on_merge(profile: Profile, code: int) -> bool:
	if not has_request(profile):
		return false
	var req: Dictionary = profile.visitor["request"]
	if bool(req["created"]):
		return false
	if Creature.family_of(code) == int(req["family"]) and Creature.tier_of(code) >= GameConfig.VISITOR_REQUEST_MIN_TIER:
		req["created"] = true
		return true
	return false

## A creature of `code` was released. Returns true when this completes the request (the
## caller then adds the resident and saves in the same write).
static func on_release(profile: Profile, code: int) -> bool:
	if not has_request(profile):
		return false
	var req: Dictionary = profile.visitor["request"]
	if not bool(req["created"]):
		return false
	if Creature.family_of(code) != int(req["family"]) or Creature.tier_of(code) < GameConfig.VISITOR_REQUEST_MIN_TIER:
		return false
	profile.visitor["request"] = {}
	profile.visitor["done"] = true
	return true

## Short reef-facing description of the active request / offer.
static func status_text(profile: Profile) -> String:
	if bool(profile.visitor.get("done", false)):
		return "The Lantern Ray lives in your reef."
	if not has_request(profile):
		return ""
	var req: Dictionary = profile.visitor["request"]
	var fam: String = String(Creature.FAMILY_NAMES[int(req["family"])])
	if bool(req["created"]):
		return "Step 2 of 2: release a tier %d+ %s through the Reef Gate." % [GameConfig.VISITOR_REQUEST_MIN_TIER, fam]
	return "Step 1 of 2: make a tier %d+ %s in a pool." % [GameConfig.VISITOR_REQUEST_MIN_TIER, fam]

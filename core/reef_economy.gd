class_name ReefEconomy
extends RefCounted
## Passive income, the offline chest and decoration purchases. Pure functions on a
## Profile plus the injectable GameClock; no UI, no saving (GameSession saves once
## per committed action, so a settlement/claim/purchase and its effects are written
## together).

# --- Rates -------------------------------------------------------------------------------

static func resident_rate(tier: int) -> float:
	return GameConfig.PASSIVE_BASE_PER_HOUR * pow(GameConfig.PASSIVE_TIER_GROWTH, float(tier - 1))

static func decoration_def(id: String) -> Dictionary:
	for d in GameConfig.DECORATIONS:
		if String(d["id"]) == id:
			return d
	return {}

static func total_beauty(profile: Profile) -> int:
	var b: int = 0
	for d in profile.decorations:
		b += int(decoration_def(String(d["id"])).get("beauty", 0))
	return b

static func multiplier(beauty: int) -> float:
	return 1.0 + float(beauty) / GameConfig.BEAUTY_DIVISOR

static func base_rate(profile: Profile) -> float:
	var r: float = 0.0
	for res in profile.residents:
		r += resident_rate(int(res["tier"]))
	return r

## Coins per hour for the reef as it stands.
static func rate_per_hour(profile: Profile) -> float:
	return base_rate(profile) * multiplier(total_beauty(profile))

## Coins per hour if one more decoration (by id) were placed.
static func rate_with_decoration(profile: Profile, id: String) -> float:
	var beauty: int = total_beauty(profile) + int(decoration_def(id).get("beauty", 0))
	return base_rate(profile) * multiplier(beauty)

## Coins per hour if one more resident of `tier` joined.
static func rate_with_resident(profile: Profile, tier: int) -> float:
	return (base_rate(profile) + resident_rate(tier)) * multiplier(total_beauty(profile))

static func chest_cap_seconds() -> int:
	return GameConfig.OFFLINE_CAP_HOURS * 3600

# --- Settlement --------------------------------------------------------------------------------

## Credit income earned since the last settlement at the CURRENT rate. Short gaps pay
## straight to the balance (fractions are carried, never lost); long gaps are away time
## and go to the offline chest, capped at OFFLINE_CAP_HOURS in total. A clock that went
## backwards earns nothing and re-anchors. Returns {coins, chest, away, clamped}.
static func settle(profile: Profile, now: int) -> Dictionary:
	var out: Dictionary = {"coins": 0, "chest": 0.0, "away": false, "clamped": false}
	if profile.income_stamp <= 0:
		profile.income_stamp = now
		return out
	var gap: int = now - profile.income_stamp
	if gap < 0:
		profile.income_stamp = now      # clock moved back: no income, no negative time
		out["clamped"] = true
		return out
	if gap == 0:
		return out
	var rate: float = rate_per_hour(profile)
	if gap <= GameConfig.OFFLINE_THRESHOLD_SEC:
		profile.income_frac += rate * float(gap) / 3600.0
		var whole: int = int(floor(profile.income_frac))
		profile.coins += whole
		profile.income_frac -= float(whole)
		out["coins"] = whole
	else:
		out["away"] = true
		var room: int = maxi(0, chest_cap_seconds() - profile.chest_secs)
		var secs: int = mini(gap, room)
		if rate > 0.0 and secs > 0:
			var add: float = rate * float(secs) / 3600.0
			profile.chest_coins += add
			out["chest"] = add
		profile.chest_secs += secs
	profile.income_stamp = now
	return out

static func chest_amount(profile: Profile) -> int:
	return int(floor(profile.chest_coins + profile.income_frac))

static func chest_full(profile: Profile) -> bool:
	return profile.chest_secs >= chest_cap_seconds()

## Move the chest into the balance and clear it. Claiming twice pays once.
static func claim_chest(profile: Profile) -> int:
	if profile.chest_coins <= 0.0:
		profile.chest_secs = 0
		return 0
	profile.income_frac += profile.chest_coins
	var whole: int = int(floor(profile.income_frac))
	profile.coins += whole
	profile.income_frac -= float(whole)
	profile.chest_coins = 0.0
	profile.chest_secs = 0
	return whole

# --- Decorations --------------------------------------------------------------------------------

static func owns(profile: Profile, id: String) -> bool:
	for d in profile.decorations:
		if String(d["id"]) == id:
			return true
	return false

static func slot_taken(profile: Profile, slot: int) -> bool:
	for d in profile.decorations:
		if int(d["slot"]) == slot:
			return true
	return false

## Validate a purchase without changing anything. Returns {ok, reason}.
static func can_purchase(profile: Profile, id: String, slot: int) -> Dictionary:
	var def: Dictionary = decoration_def(id)
	if def.is_empty():
		return {"ok": false, "reason": "Unknown decoration"}
	if owns(profile, id):
		return {"ok": false, "reason": "You already own the %s" % String(def["name"])}
	if slot < 0 or slot >= GameConfig.DECOR_SLOTS.size():
		return {"ok": false, "reason": "Pick a marked spot"}
	if slot_taken(profile, slot):
		return {"ok": false, "reason": "That spot is taken"}
	if profile.coins < int(def["price"]):
		return {"ok": false, "reason": "Needs %d coins (you have %d)" % [int(def["price"]), profile.coins]}
	return {"ok": true, "reason": ""}

## Buy and place in one step. Idempotent: owning an item makes any retry a no-op that
## charges nothing. Caller settles income at the old rate first and saves once after.
static func purchase(profile: Profile, id: String, slot: int) -> Dictionary:
	var check: Dictionary = can_purchase(profile, id, slot)
	if not bool(check["ok"]):
		return check
	var def: Dictionary = decoration_def(id)
	profile.coins -= int(def["price"])
	profile.decorations.append({"id": id, "slot": slot})
	return {"ok": true, "reason": "", "spent": int(def["price"])}

class_name GameClock
extends RefCounted
## The only place the game asks "what time is it?". Real time by default; tests
## and playtests can run a fake or frozen clock to cross phase boundaries, visitor
## windows, midnight and the offline cap without waiting.
##
## CLI (see ui/main.gd):  --clock=2026-11-24T06:30   start at that LOCAL time, then run normally
##                        --tz=0                      treat local time as UTC offset 0 (minutes east)

static var _offset: int = 0          # seconds added to the real clock
static var _frozen: bool = false
static var _frozen_at: int = 0
static var _tz_override: bool = false
static var _tz_bias: int = 0         # seconds east of UTC (only when overridden)

static func now() -> int:
	if _frozen:
		return _frozen_at
	return int(Time.get_unix_time_from_system()) + _offset

## Freeze the clock at a unix time (tests). Time only moves via advance().
static func freeze(unix: int) -> void:
	_frozen = true
	_frozen_at = unix

static func advance(seconds: int) -> void:
	if _frozen:
		_frozen_at += seconds
	else:
		_offset += seconds

## Jump to a unix time but keep running in real time from there.
static func set_running_at(unix: int) -> void:
	_frozen = false
	_offset = unix - int(Time.get_unix_time_from_system())

static func reset() -> void:
	_offset = 0
	_frozen = false
	_frozen_at = 0
	_tz_override = false
	_tz_bias = 0

static func set_tz_bias_seconds(seconds_east: int) -> void:
	_tz_override = true
	_tz_bias = seconds_east

static func tz_bias_seconds() -> int:
	if _tz_override:
		return _tz_bias
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60

## Local calendar fields for a unix time: year, month, day, hour, minute, second, weekday.
static func local_dict(unix: int = -1) -> Dictionary:
	var t: int = now() if unix < 0 else unix
	return Time.get_datetime_dict_from_unix_time(t + tz_bias_seconds())

static func local_day_key(unix: int = -1) -> String:
	var d: Dictionary = local_dict(unix)
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

## Seconds since local midnight.
static func local_seconds_of_day(unix: int = -1) -> int:
	var d: Dictionary = local_dict(unix)
	return int(d["hour"]) * 3600 + int(d["minute"]) * 60 + int(d["second"])

## Unix time for a LOCAL calendar moment.
static func unix_from_local(year: int, month: int, day: int, hour: int, minute: int = 0, second: int = 0) -> int:
	var as_utc: int = Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": second})
	return as_utc - tz_bias_seconds()

## Parse "YYYY-MM-DDTHH:MM" (local) into a unix time; -1 if malformed.
static func parse_local(text: String) -> int:
	var parts: PackedStringArray = text.replace("T", " ").replace(":", " ").replace("-", " ").split(" ", false)
	if parts.size() < 5:
		return -1
	return unix_from_local(int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4]))

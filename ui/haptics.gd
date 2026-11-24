class_name Haptics
extends RefCounted
## Brief vibration cues. Off when the player turns haptics off in settings; with reduced
## motion only the action confirmations (merge, release, surge, flood) remain, not selection ticks.

static var enabled: bool = true
static var reduced_motion: bool = false

static func tick() -> void:       # selecting a piece
	if enabled and not reduced_motion:
		Input.vibrate_handheld(8)

static func merge(step: int) -> void:
	if enabled:
		Input.vibrate_handheld(18 + 8 * mini(step, 3))

static func release() -> void:
	if enabled:
		Input.vibrate_handheld(40)

static func reject() -> void:
	if enabled:
		Input.vibrate_handheld(25)

static func surge() -> void:
	if enabled:
		Input.vibrate_handheld(35)

static func flood() -> void:
	if enabled:
		Input.vibrate_handheld(80)

class_name SaveStore
extends RefCounted
## Versioned, atomic JSON save. One document holds the profile AND the active
## run, so a single write is always a consistent snapshot: a payout and the
## board change that caused it can never be saved apart.

static func write(path: String, profile: Profile, run: RunState) -> bool:
	var doc: Dictionary = {
		"version": GameConfig.SAVE_VERSION,
		"profile": profile.to_dict(),
		"run": run.to_dict() if run != null else null,
	}
	var tmp: String = path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("SaveStore: cannot open %s (%d)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(doc))
	f.flush()
	f.close()
	var g_tmp: String = ProjectSettings.globalize_path(tmp)
	var g_path: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) and OS.get_name() == "Windows":
		DirAccess.remove_absolute(g_path)
	var err: int = DirAccess.rename_absolute(g_tmp, g_path)
	if err != OK:
		push_warning("SaveStore: rename failed (%d)" % err)
		return false
	return true

## Returns {"profile": Profile, "run": RunState or null} or {} when there is
## no usable save. A corrupt file is moved aside instead of crashing.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_quarantine(path)
		return {}
	var doc: Dictionary = migrate(parsed)
	if doc.is_empty():
		_quarantine(path)
		return {}
	var run: RunState = null
	if typeof(doc.get("run")) == TYPE_DICTIONARY:
		run = RunState.from_dict(doc["run"])
	return {"profile": Profile.from_dict(doc.get("profile", {})), "run": run}

## Upgrade older documents step by step. Version 1 is the first format.
static func migrate(doc: Dictionary) -> Dictionary:
	var v: int = int(doc.get("version", 0))
	if v < 1 or v > GameConfig.SAVE_VERSION:
		return {}
	# if v == 1: doc = _v1_to_v2(doc)   # future formats chain here
	return doc

static func _quarantine(path: String) -> void:
	var bad: String = path + ".corrupt"
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(bad))
	push_warning("SaveStore: unreadable save moved to %s" % bad)

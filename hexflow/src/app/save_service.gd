extends Node
## Atomic load/save with schema migration (§18). Knows nothing about the rules.

signal save_recovered(reason: String)

const PATH := "user://save.json"
const SCHEMA := 1

var data: Dictionary = {}


func _ready() -> void:
	data = _defaults()
	load_from_disk()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_to_disk()


static func _defaults() -> Dictionary:
	return {
		"schema": SCHEMA,
		"version": ProjectSettings.get_setting("application/config/version", "0.0.0"),
		"campaign": {},
		"endless": {"best_goals": 0, "best_placements_at_best": 0, "runs": 0},
		"daily": {"history": {}, "streak": 0},
		"tutorial_flags": {},
		"in_progress": null,
		"stats": {"playtime_seconds": 0, "total_placements": 0, "undos": 0},
		"achievements_mirror": [],
	}


func record_completion(level_id: String, placements: int, stars: int, hinted: bool) -> void:
	var campaign: Dictionary = data["campaign"]
	var entry: Dictionary = campaign.get(level_id, {"completed": false, "best_placements": 0, "stars": 0, "hinted": false})
	var best: int = int(entry.get("best_placements", 0))
	entry["completed"] = true
	entry["best_placements"] = placements if best == 0 else mini(best, placements)
	entry["stars"] = maxi(int(entry.get("stars", 0)), stars)
	entry["hinted"] = bool(entry.get("hinted", false)) or hinted
	campaign[level_id] = entry
	save_to_disk()


func level_entry(level_id: String) -> Dictionary:
	return (data["campaign"] as Dictionary).get(level_id, {})


func set_in_progress(payload: Variant) -> void:
	data["in_progress"] = payload
	save_to_disk()


func load_from_disk() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_quarantine("corrupt")
		return
	var loaded: Dictionary = parsed
	var schema: int = int(loaded.get("schema", 0))
	if schema > SCHEMA:
		# Never silently overwrite a newer save (§18.4).
		_quarantine("schema_%d" % schema)
		return
	data = _migrate(loaded, schema)


## Ordered migrations keyed by schema. Each step upgrades by exactly one version.
func _migrate(loaded: Dictionary, from_schema: int) -> Dictionary:
	var out: Dictionary = _defaults()
	out.merge(loaded, true)
	var s: int = from_schema
	while s < SCHEMA:
		# No migrations exist yet; each future one appends a `match s:` branch here.
		s += 1
	out["schema"] = SCHEMA
	return out


## §18.5 — back up, notify, continue with defaults. Never crash on a bad save.
func _quarantine(reason: String) -> void:
	var backup := "user://save.%s.bak" % reason
	if FileAccess.file_exists(PATH):
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(backup)
		)
	data = _defaults()
	save_recovered.emit(reason)
	push_warning("save quarantined (%s); starting fresh" % reason)


## Atomic: write `save.tmp`, flush, rename over `save.json`. Never truncate the
## live file (§18.2).
func save_to_disk() -> void:
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("could not write save")
		return
	f.store_string(JSON.stringify(data, "  "))
	f.flush()
	f.close()
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(PATH)
	)

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


## §7.2 — an endless run is scored on `goals_reached`, tie-broken by fewer
## placements (§5.10). Returns whether this run is the new personal best, because
## that is the one thing the run summary needs to say differently.
func record_endless_run(goals: int, placements: int) -> bool:
	var endless: Dictionary = _section("endless")
	endless["runs"] = int(endless.get("runs", 0)) + 1
	var better: bool = Scoring.compare_endless(
		goals, placements,
		int(endless.get("best_goals", 0)), int(endless.get("best_placements_at_best", 0))
	) < 0
	if better:
		endless["best_goals"] = goals
		endless["best_placements_at_best"] = placements
	save_to_disk()
	return better


## §7.3 — one puzzle per UTC day, "shows a 7-day streak indicator". The streak is
## consecutive *dates* played, so a day missed resets it to one; playing the same
## day twice does not extend it, because §7.3 allows unlimited retries and a streak
## you can grind in an afternoon measures nothing.
func record_daily(utc_date: String, placements: int, stars: int) -> void:
	var daily: Dictionary = _section("daily")
	var history: Dictionary = daily["history"]
	var first_today: bool = not history.has(utc_date)
	var previous: Dictionary = history.get(utc_date, {})
	history[utc_date] = {
		"placements": mini(int(previous.get("placements", placements)), placements),
		"stars": maxi(int(previous.get("stars", 0)), stars),
	}
	if first_today:
		daily["streak"] = 1 if not history.has(previous_date(utc_date)) \
			else int(daily.get("streak", 0)) + 1
	save_to_disk()


## The day before [param utc_date], as the same `YYYY-MM-DD` string. Done through
## the epoch rather than by subtracting one from the day number, so month ends and
## leap years are the calendar's problem and not this file's.
static func previous_date(utc_date: String) -> String:
	var unix: int = int(Time.get_unix_time_from_datetime_string(utc_date + "T12:00:00"))
	return Time.get_datetime_string_from_unix_time(unix - 86400, true).substr(0, 10)


## The last [param days] dates ending today, and whether each was played — §7.3's
## seven-day indicator, as data the view can draw as pips.
func daily_streak_days(utc_date: String, days: int = 7) -> Array[bool]:
	var history: Dictionary = _section("daily")["history"]
	var out: Array[bool] = []
	var at: String = utc_date
	for _i: int in range(days):
		out.push_front(history.has(at))
		at = previous_date(at)
	return out


func set_in_progress(payload: Variant) -> void:
	data["in_progress"] = payload
	save_to_disk()


## A top-level section of the save, created from the defaults if it is not there.
##
## `_migrate` merges the defaults over anything loaded from disk, so a real save
## always has all of them — but a payload assembled by hand, by an older tool or
## by a test may not, and §18's rule is that a save missing something costs the
## player that thing and never the game. A record that crashed on a missing key
## would lose the run it was recording *and* the ones after it.
func _section(name: String) -> Dictionary:
	var current: Variant = data.get(name)
	if not (current is Dictionary):
		data[name] = (_defaults()[name] as Dictionary).duplicate(true)
	return data[name]


func load_from_disk() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var text := FileAccess.get_file_as_string(PATH)
	# `JSON.parse_string` pushes an engine error on bad input. A corrupt save is a
	# case §18.5 *handles*, so it should not also shout — an error in the log that
	# the code deliberately recovers from is an error nobody looks at twice.
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		_quarantine("corrupt")
		return
	var loaded: Dictionary = json.data
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

## @core — Scenario: The developer tools cannot ship by accident (MAP-EDITOR §8).
##
## §27 lists "Level editor / Steam Workshop" as an explicit non-goal, and
## MAP-EDITOR §0 argues that an *authoring* tool is a different thing: it runs
## from the repo, its output is committed JSON, and it is not in the export.
##
## That argument only holds while the last clause is true, and "is not in the
## export" is not a property of the code — it is a line in a config file that
## nobody reads. So it is asserted here, along with the two other halves of §8:
## the dependency runs one way, and `tools/` is not the only thing that has no
## business in a player's build.
##
## The assertion is over **every** preset rather than over a named one. There is
## one today and M11 owes three; a Windows preset added later that forgets the
## filter is exactly the accident this exists to catch.
extends GutTest

const PRESETS := "res://export_presets.cfg"


func _presets() -> ConfigFile:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS), OK, "export_presets.cfg is committed on purpose — see .gitignore")
	return cfg


## Section names are `preset.0`, `preset.1`, … and each has a `preset.N.options`
## beside it, which is not a preset and has no filter.
func _preset_sections(cfg: ConfigFile) -> Array[String]:
	var out: Array[String] = []
	for section: String in cfg.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			out.append(section)
	return out


func test_there_is_at_least_one_preset_to_check() -> void:
	# Without this the rest passes vacuously on an empty file, which is the way a
	# guard like this usually dies.
	assert_gt(_preset_sections(_presets()).size(), 0)


func test_every_preset_leaves_the_tools_behind() -> void:
	var cfg := _presets()
	for section: String in _preset_sections(cfg):
		var filter := str(cfg.get_value(section, "exclude_filter", ""))
		assert_string_contains(filter, "tools/*",
			"%s would ship the map editor (MAP-EDITOR §8)" % section)


## The suite and the docs are in the same category: shipped bytes nobody plays.
## Not §8's requirement, but the same line, and a filter that lost them would
## have lost `tools/` for the same reason.
func test_every_preset_leaves_the_tests_behind() -> void:
	var cfg := _presets()
	for section: String in _preset_sections(cfg):
		var filter := str(cfg.get_value(section, "exclude_filter", ""))
		assert_string_contains(filter, "tests/*", "%s would ship the test suite" % section)
		assert_string_contains(filter, "addons/gut/*", "%s would ship GUT" % section)


## The arrow runs one way, the same way `src/core/` → `src/app/` → `src/view/`
## does: the editor may read `src/`, and nothing in `src/` may read the editor.
##
## `ci_gate.sh` enforces this over the whole tree; this covers the case the grep
## cannot see, which is a scene file naming a script under `tools/`.
func test_nothing_in_the_game_reaches_into_tools() -> void:
	var offenders: Array[String] = []
	_scan("res://src", offenders)
	assert_eq(offenders, [] as Array[String],
		"src/ must not reference tools/ (MAP-EDITOR §8)")


func _scan(dir_path: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name: String in dir.get_directories():
		_scan(dir_path + "/" + name, offenders)
	for name: String in dir.get_files():
		if not (name.ends_with(".tscn") or name.ends_with(".tres")):
			continue
		var path := dir_path + "/" + name
		if FileAccess.get_file_as_string(path).contains("res://tools/"):
			offenders.append(path)

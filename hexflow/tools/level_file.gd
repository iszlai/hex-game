## The one way a level file is written (§17.1, MAP-EDITOR §6).
##
## Four tools write into `src/data/levels/` — the sweep, the uid stamper, the map
## editor's Save and its `Apply order` — and until this existed they wrote three
## different formats:
##
##   * `author_levels.gd` wrote unsorted keys and no trailing newline;
##   * `stamp_uids.gd` wrote sorted keys with a newline, and, because it
##     round-tripped through `JSON.parse_string`, turned every integer in the file
##     into a float — which is why the sixty frozen files say `"chapter": 1.0`;
##   * the editor wrote sorted integers.
##
## None of that changes what a level *is*: [method LevelRepository.from_dict]
## reads `1.0` and `1` identically. It changes what a diff looks like, and a diff
## nobody can read is how a real change hides. Running `make levels` would have
## reformatted all sixty files, and saving one level from the editor would have
## left it as the only file in the tree in a different shape.
##
## **JSON has no integers.** That is the whole of the float problem: Godot's
## parser gives every number back as a double, so anything that reads a level file
## and writes it again re-floats it. The fix is not to normalise numbers after the
## fact but to go through [Level] — `from_dict` produces typed integers and
## `to_dict` writes them, so the round trip cannot drift. `tests/property/
## test_level_files.gd` asserts every shipped file is byte-identical to what this
## produces, so the format can only change on purpose.
##
## Not part of the shipped game.
class_name LevelFile

## Where a board that is not one of the sixty goes (MAP-EDITOR §6.1).
##
## Outside `src/`, so it is not shipped, and named in the export preset's exclude
## filter rather than merely happening to be somewhere the filter covers. Drafts
## are committable on purpose: a board someone is halfway through is worth keeping
## across a week, and `user://` would put it in a directory nobody can find.
const DRAFT_DIR := "res://drafts"

## The tree the game reads as frozen campaign data.
const CAMPAIGN_DIR := "res://src/data/levels"


## Whether [param path] is one of the sixty — the thing §6's refusal protects.
##
## The rule is about the **destination**, not about which button was pressed.
## Save-as exists so an unfinished board has somewhere to live, and if it could
## also aim at `chapter_3/level_07.json` it would be a way around the refusal
## rather than an alternative to it.
static func is_campaign_path(path: String) -> bool:
	var full: String = ProjectSettings.globalize_path(path).simplify_path()
	var campaign: String = ProjectSettings.globalize_path(CAMPAIGN_DIR).simplify_path()
	return full.begins_with(campaign + "/")


## Reads a level file without the validating loader's cache or its assertions —
## what a tool wants when it is about to rewrite the file rather than play it.
static func read(path: String) -> Level:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("%s is not a level file" % path)
		return null
	return LevelRepository.from_dict(parsed as Dictionary)


## Sorted keys, two-space indent, trailing newline. Sorted because a level file is
## read by people and `git diff`ed constantly, and a key order that follows
## whatever [method LevelRepository.to_dict] happens to build makes every
## unrelated edit look like a rewrite.
static func write(level: Level, path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % path)
		return false
	file.store_string(text_of(level))
	file.close()
	return true


## What [method write] would put on disk. Separated so a test can compare against
## a file without writing one.
static func text_of(level: Level) -> String:
	return JSON.stringify(LevelRepository.to_dict(level), "  ", true) + "\n"

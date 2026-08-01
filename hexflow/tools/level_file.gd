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

extends SceneTree
## Authoring tool: give every level file a permanent name (C-34).
##
##     Godot --headless --path . -s res://tools/stamp_uids.gd
##
## `id` — `"c3_l07"` — names a **slot**, not a level, and the save keyed every
## star on it. Reordering the campaign therefore left a level's stars behind for
## whatever took its place. This mints a `uid` per file so progress can key on the
## level instead, and position can become presentation.
##
## Idempotent: a file that already has a uid keeps it. That is the whole point —
## running this twice must not reissue names and orphan the progress recorded
## against the first set.
##
## The uid is **random, not a hash of the level**. A content hash would be tidier
## and would be wrong: the map editor exists to tweak a board, and a hash would
## give every tweak a new name and drop the stars earned on it. A name minted once
## survives editing, which is what a name is for.
##
## Not part of the shipped game. `randi()` here is fine — C2 bans it in `src/`,
## where determinism is the requirement; this runs once, by hand, and its output
## is committed.

const OUT_ROOT := "res://src/data/levels"
const UID_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789"
const UID_LENGTH := 10


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var seen: Dictionary = {}
	var stamped: int = 0
	var kept: int = 0

	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			var path := LevelRepository.path_for(chapter, index)
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				continue
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if not (parsed is Dictionary):
				push_error("%s is not a level file" % path)
				continue

			var d: Dictionary = parsed
			var uid: String = str(d.get("uid", ""))
			if uid != "" and not seen.has(uid):
				seen[uid] = true
				kept += 1
				continue

			# A blank uid, or — the case worth guarding — a duplicate, which would
			# have two levels sharing one row of progress.
			uid = _mint(rng, seen)
			seen[uid] = true
			d["uid"] = uid
			_write(path, d)
			stamped += 1
			print("c%d l%02d  %s" % [chapter, index, uid])

	print("\nstamped %d, kept %d" % [stamped, kept])
	quit()


func _mint(rng: RandomNumberGenerator, seen: Dictionary) -> String:
	while true:
		var out: String = ""
		for _i: int in range(UID_LENGTH):
			out += UID_CHARS[rng.randi_range(0, UID_CHARS.length() - 1)]
		if not seen.has(out):
			return out
	return ""


## Through [LevelFile], the one writer, so a stamped file does not show up in a
## diff as reformatted.
##
## It used to re-stringify the parsed dictionary directly, which is what turned
## every integer in the sixty frozen files into a float: JSON has no integers, so
## `JSON.parse_string` hands back doubles and stringifying them writes `1.0`.
## Going through [Level] instead means `from_dict` retypes them on the way in.
func _write(path: String, d: Dictionary) -> void:
	var level := LevelRepository.from_dict(d)
	if level == null:
		push_error("cannot rewrite %s" % path)
		return
	LevelFile.write(level, path)

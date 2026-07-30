extends SceneTree
## Authoring tool: generates, verifies and freezes the campaign level files (§9).
##
##     Godot --headless --path . -s res://tools/author_levels.gd -- [chapter]
##
## Sweeps a seed range per level slot, keeps the first candidate whose par falls
## in the chapter's target band, and writes it to
## `src/data/levels/chapter_N/level_MM.json`. Generated levels are then **frozen
## data** — never regenerated at runtime, never re-seeded on load.
##
## Not part of the shipped game. Autoloads are unavailable in a `-s` MainLoop
## script, so everything here goes through the pure core and the static
## [LevelRepository] API.

const SEEDS_PER_SLOT := 40
const OUT_ROOT := "res://src/data/levels"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var only_chapter: int = int(args[0]) if args.size() > 0 else 0

	var written: int = 0
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		if only_chapter > 0 and chapter != only_chapter:
			continue
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path("%s/chapter_%d" % [OUT_ROOT, chapter])
		)
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			var level := _author(chapter, index)
			if level == null:
				push_error("chapter %d level %d: no candidate met its par band" % [chapter, index])
				continue
			_write(level)
			written += 1
			print("c%d l%02d  par %2d  walls %2d  tiles %2d  goals %d" % [
				chapter, index, level.par, level.board.walls().size(),
				level.tiles.size(), level.board.goals.size()
			])
	print("wrote %d level files" % written)
	quit()


## Difficulty inside a chapter is monotonic in par (§9), so each slot has a target
## band and the sweep keeps the first candidate that lands inside it.
func _par_band(chapter: int, index: int) -> Vector2i:
	var floor_par: int = 6 if chapter > 1 else 4
	var low: int = floor_par + int(float(index - 1) * 0.6)
	return Vector2i(low, low + 4)


func _author(chapter: int, index: int) -> Level:
	var params := Generator.chapter_params(chapter, index)
	var band := _par_band(chapter, index)
	var base_seed: int = Generator.fnv1a_32("hexflow:c%d:l%d" % [chapter, index])
	var fallback: Level = null

	for attempt: int in range(SEEDS_PER_SLOT):
		var level := Generator.generate(base_seed + attempt * 7919, params)
		if level == null:
			continue
		if fallback == null:
			fallback = level
		if level.par >= band.x and level.par <= band.y:
			return _stamp(level, chapter, index)
	# Any verified level beats no level; the band is a preference, solvability
	# is the requirement.
	return _stamp(fallback, chapter, index) if fallback != null else null


func _stamp(level: Level, chapter: int, index: int) -> Level:
	level.id = LevelRepository.id_for(chapter, index)
	level.chapter = chapter
	level.index = index
	return level


func _write(level: Level) -> void:
	var path := LevelRepository.path_for(level.chapter, level.index)
	var problems := LevelRepository.verify(level)
	if not problems.is_empty():
		push_error("%s failed verification: %s" % [path, ", ".join(problems)])
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("could not write %s" % path)
		return
	f.store_string(JSON.stringify(LevelRepository.to_dict(level), "  "))
	f.close()

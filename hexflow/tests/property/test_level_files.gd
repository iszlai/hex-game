## @property — Scenario: Every shipped level file is valid (§24.2).
##
## Guards the frozen campaign data. A level file that stopped reproducing its par
## would silently break the star bands for everyone who has already played it, so
## this runs on every push, not nightly.
extends GutTest


func test_the_full_campaign_is_present() -> void:
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			assert_true(
				FileAccess.file_exists(LevelRepository.path_for(chapter, index)),
				"missing %s" % LevelRepository.path_for(chapter, index)
			)


func test_every_level_file_validates_and_reproduces_its_par() -> void:
	LevelRepository.clear_cache()
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			var level := LevelRepository.load_level(chapter, index)
			assert_not_null(level, "could not load c%d l%d" % [chapter, index])
			if level == null:
				continue
			var problems := LevelRepository.verify(level)
			assert_eq(problems, [] as Array[String],
				"%s: %s" % [level.id, ", ".join(problems)])


func test_every_level_round_trips_through_json() -> void:
	LevelRepository.clear_cache()
	var level := LevelRepository.load_level(4, 7)
	assert_not_null(level)
	var round_tripped := LevelRepository.from_dict(
		JSON.parse_string(JSON.stringify(LevelRepository.to_dict(level))) as Dictionary
	)
	assert_eq(round_tripped.tiles, level.tiles)
	assert_eq(round_tripped.par, level.par)
	assert_eq(round_tripped.board.walls(), level.board.walls())
	assert_eq(round_tripped.board.goals, level.board.goals)
	assert_eq(round_tripped.solution, level.solution)


func test_difficulty_rises_across_each_chapter() -> void:
	# §9 — par is monotonic across a chapter, allowing a little breathing room so
	# the generator is not forced into degenerate boards.
	LevelRepository.clear_cache()
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		var first := LevelRepository.load_level(chapter, 1)
		var last := LevelRepository.load_level(chapter, LevelRepository.LEVELS_PER_CHAPTER)
		assert_true(last.par >= first.par,
			"chapter %d ends easier than it starts (%d -> %d)" % [chapter, first.par, last.par])


func test_the_loader_rejects_a_future_schema_instead_of_guessing() -> void:
	var d := LevelRepository.to_dict(LevelRepository.load_level(1, 1))
	d["schema"] = LevelRepository.SCHEMA + 1
	assert_null(LevelRepository.from_dict(d))
	# The push_error is the intended behaviour — a newer save or level file is
	# never silently reinterpreted (§18.4) — so it is expected, not a failure.
	assert_push_error("newer than this build understands")


## C-32 added `shape` to the level schema. Every one of the sixty frozen files
## predates it and must keep loading as the hexagon it is — a default that failed
## quietly here would change sixty boards and every par with them.
func test_the_frozen_files_still_load_as_hexagons() -> void:
	LevelRepository.clear_cache()
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			var level := LevelRepository.load_level(chapter, index)
			assert_eq(level.board.shape, "hexagon", "%s changed shape" % level.id)
			assert_eq(level.board.cells(), Hex.hexagon(level.board.radius),
				"%s is no longer the board it was authored as" % level.id)


## A shaped board survives being written out and read back. `radius` in the file
## is the size the shape was *asked* for, not the radius it reaches — writing back
## the reached radius would rebuild a triangle of side 6 as a different board.
func test_a_shaped_level_round_trips_through_json() -> void:
	var cells: Array[Vector3i] = Hex.shape("ring", 4, 1)
	var board := Board.build(
		4, cells[0], [cells[cells.size() - 1]] as Array[Vector3i],
		[] as Array[Vector3i], [], [] as Array[Vector3i], [] as Array[Vector3i],
		"ring", 1
	)
	var level := Level.build(board, [Direction.NE] as Array[int])
	level.id = "shaped_fixture"

	var back := LevelRepository.from_dict(
		JSON.parse_string(JSON.stringify(LevelRepository.to_dict(level))) as Dictionary
	)
	assert_not_null(back)
	assert_eq(back.board.shape, "ring")
	assert_eq(back.board.shape_arg, 1)
	assert_eq(back.board.cells(), board.cells(), "the same hexes, in the same order")
	assert_false(back.board.has(Vector3i.ZERO), "including the hole")

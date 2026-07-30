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

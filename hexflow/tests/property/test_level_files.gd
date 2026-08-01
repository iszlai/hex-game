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


## Every shipped file is **byte-identical** to what [LevelFile] writes.
##
## Four tools write into `src/data/levels/`, and until they were routed through
## one writer they produced three formats between them — unsorted keys, a missing
## trailing newline, and a whole campaign of `"chapter": 1.0` left behind by a
## tool that re-stringified parsed JSON (JSON has no integers, so Godot's parser
## hands every number back as a double).
##
## None of that changes what a level *is*. It changes what a diff looks like:
## `make levels` would have reformatted all sixty files on top of whatever it
## actually changed, and one level saved from the map editor would have been the
## only file in the tree in a different shape. A real change hides in a diff
## nobody can read.
##
## This also asserts, in passing, that `from_dict` → `to_dict` is lossless — which
## is what lets `Apply order` rewrite a level's slot by going through [Level]
## rather than by patching raw JSON.
func test_every_level_file_is_written_in_the_canonical_form() -> void:
	LevelRepository.clear_cache()
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			var path := LevelRepository.path_for(chapter, index)
			var on_disk := FileAccess.get_file_as_string(path)
			var level := LevelFile.read(path)
			assert_not_null(level, "could not read %s" % path)
			if level == null:
				continue
			assert_eq(LevelFile.text_of(level), on_disk,
				"%s is not in the form LevelFile writes — run the writers through it"
					% path.get_file())


## §10's five teaching boards are frozen data on the same terms as the sixty, and
## for a sharper reason: every one of them has words on screen describing the
## route through it, so a board that stopped reproducing its line would leave the
## tutorial telling a first-time player to do something that no longer works.
func test_every_tutorial_file_validates_and_reproduces_its_line() -> void:
	Tutorial.clear_cache()
	for index: int in range(1, Tutorial.COURSE_LENGTH + 1):
		var path := Tutorial.level_path(index)
		assert_true(FileAccess.file_exists(path), "missing %s" % path)
		var lesson := Tutorial.level(index)
		assert_not_null(lesson, "could not load %s" % path)
		if lesson == null:
			continue
		var problems := LevelRepository.verify(lesson)
		assert_eq(problems, [] as Array[String], "%s: %s" % [lesson.id, ", ".join(problems)])
		# The words say "place it on the lit cell", and the lit cell is this line.
		assert_gt(lesson.solution_script.size(), 0, "%s stores no line" % lesson.id)


## And in the same canonical form, written by the same writer — so `make tutorial`
## reformats nothing on top of whatever it actually changed.
func test_every_tutorial_file_is_written_in_the_canonical_form() -> void:
	Tutorial.clear_cache()
	for index: int in range(1, Tutorial.COURSE_LENGTH + 1):
		var path := Tutorial.level_path(index)
		var on_disk := FileAccess.get_file_as_string(path)
		var lesson := LevelFile.read(path)
		assert_not_null(lesson, "could not read %s" % path)
		if lesson == null:
			continue
		assert_eq(LevelFile.text_of(lesson), on_disk,
			"%s is not in the form LevelFile writes" % path.get_file())


## [constant Board.MIN_CELLS] came down to six so §10's boards could be as small
## as one idea, and the campaign's own floor moved here rather than disappearing.
## Nineteen is the radius-2 hexagon §8.4 gives chapter 1; anything under it is a
## board with no room for a route worth playing, and the only reason one would
## appear in the sixty is a bug in the sweep.
func test_the_campaign_keeps_its_own_floor_on_board_size() -> void:
	LevelRepository.clear_cache()
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			var level := LevelRepository.load_level(chapter, index)
			assert_gte(level.board.size(), 19,
				"%s is smaller than a radius-2 hexagon" % level.id)


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


## C-33: the campaign's difficulty curve, checked against what each level was
## *authored to be* rather than re-measured — measuring sixty boards takes minutes
## and this runs on every push.
##
## It replaces a test that compared each chapter's first `par` to its last. That
## test passed on the shipped campaign, which had no difficulty curve at all:
## `par` measures length, chapter 1 peaked in the middle and ended easier, and
## chapter 4 was selected for the shortest levels and turned out to be the widest
## and most forgiving chapter in the game. A test that a broken thing passes is
## not a weak test, it is the wrong test.
func test_the_campaign_follows_its_authored_difficulty_curve() -> void:
	LevelRepository.clear_cache()
	var spikes: Array[int] = []

	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		var routes: Array[int] = []
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			var level := LevelRepository.load_level(chapter, index)
			assert_gt(level.authored_routes, 0,
				"%s was never measured, so nothing knows what it is" % level.id)
			routes.append(level.authored_routes)
		spikes.append(routes[11])

		# The spike: the last level is the narrowest of its chapter, and the one
		# before it is a step back. A chapter that only descends has no moment in
		# it — the hardest level is wherever the line happened to stop.
		assert_lte(routes[11], routes.min(),
			"chapter %d's last level is not its hardest" % chapter)
		assert_gt(routes[10], routes[11],
			"chapter %d drops into its spike from nowhere" % chapter)

		# And it descends overall, allowing for the noise a generator leaves: the
		# back half must be narrower than the front half rather than every step
		# being smaller than the last, which no sweep over real boards achieves.
		var front: int = 0
		var back: int = 0
		for i: int in range(6):
			front += routes[i]
			back += routes[i + 6]
		assert_lt(back, front, "chapter %d does not get harder" % chapter)

	# The rising baseline between chapters, measured at the *spikes* rather than at
	# the openings. Openings cannot carry it on the shipped files: §8.4 gives
	# chapter 1 radius-2 boards for its tutorial levels, and a nineteen-cell board
	# with a three-move ideal is structurally narrow whatever the curve asks for —
	# so chapter 1 opens at three and chapter 3 opens at six, and no sweep can
	# reverse that without making the tutorial harder than the chapter after it.
	#
	# What each chapter *ends* on is the claim that survives and is worth making:
	# every chapter finishes at least as hard as the one before it finished.
	for chapter: int in range(1, LevelRepository.CHAPTERS):
		assert_lte(spikes[chapter], spikes[chapter - 1],
			"chapter %d ends easier than chapter %d" % [chapter + 1, chapter])


func test_the_loader_rejects_a_future_schema_instead_of_guessing() -> void:
	var d := LevelRepository.to_dict(LevelRepository.load_level(1, 1))
	d["schema"] = LevelRepository.SCHEMA + 1
	assert_null(LevelRepository.from_dict(d))
	# The push_error is the intended behaviour — a newer save or level file is
	# never silently reinterpreted (§18.4) — so it is expected, not a failure.
	assert_push_error("newer than this build understands")


## C-34: every level has a permanent name of its own, and no two share one.
##
## `id` names a *slot* — `"c3_l07"` — and the save used to key every star on it,
## so moving a level to another slot left its stars behind for whatever took its
## place: a player would open a level they had never seen already three-starred.
## Progress keys on the uid now, which makes two levels sharing one the way that
## bug comes back — silently, as two boards reporting each other's stars.
func test_every_level_has_a_name_of_its_own() -> void:
	LevelRepository.clear_cache()
	var seen: Dictionary = {}
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			var level := LevelRepository.load_level(chapter, index)
			assert_ne(level.uid, "", "%s has no uid" % level.id)
			assert_ne(level.uid, level.id,
				"%s fell back to its slot id, so it was never stamped" % level.id)
			assert_false(seen.has(level.uid),
				"%s shares a uid with %s" % [level.id, str(seen.get(level.uid, ""))])
			seen[level.uid] = level.id
	assert_eq(seen.size(), LevelRepository.CHAPTERS * LevelRepository.LEVELS_PER_CHAPTER)


## Every shipped level is the board its file says it is. C-33 re-authored the
## campaign with shapes in it, so this replaces a test that asserted all sixty
## were hexagons — true before the re-author, and the wrong claim afterwards.
##
## What is worth checking is not which shape a level is but that the *name* and
## the *cells* agree: a file naming a ring and holding a hexagon would play as a
## hexagon and be described as a ring everywhere else in the game.
func test_every_level_is_the_shape_its_file_claims() -> void:
	LevelRepository.clear_cache()
	var seen: Dictionary = {}
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			var level := LevelRepository.load_level(chapter, index)
			assert_true(Hex.SHAPES.has(level.board.shape),
				"%s names shape %s, which does not exist" % [level.id, level.board.shape])
			assert_eq(level.board.cells(),
				Hex.shape(level.board.shape, level.board.shape_size, level.board.shape_arg),
				"%s is not the board it says it is" % level.id)
			seen[level.board.shape] = true

	# Chapter 1 is the first hour, and a player arriving from §10's course has just
	# learnt what a wall and a gate are — not what a corridor is. The shapes start
	# in chapter 2, where a silhouette is a thing to notice rather than one more
	# unexplained rule.
	for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
		assert_eq(LevelRepository.load_level(1, index).board.shape, "hexagon",
			"chapter 1 level %d is not a plain board" % index)
	assert_gt(seen.size(), 1, "the campaign uses more than one shape")


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

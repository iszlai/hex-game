## @property — Feature: Generation is reproducible (§24.2, §24.4).
##
## The seed sweeps that prove every candidate is *solvable* are the two scripts
## next door; this one covers the other half of §19's promise — that the same
## seed gives the same level, on every machine and in every build.
extends "res://tests/property/soundness.gd"


func test_generation_is_deterministic_for_a_seed() -> void:
	var params := Generator.chapter_params(3, 9)
	for s: int in range(10):
		var a := Generator.generate(77000 + s, params)
		var b := Generator.generate(77000 + s, params)
		assert_eq(a.board.walls(), b.board.walls())
		assert_eq(a.board.goals, b.board.goals)
		assert_eq(a.tiles, b.tiles)
		assert_eq(a.par, b.par)
		assert_eq(a.solution, b.solution)
		assert_eq(a.solution_script, b.solution_script)


## Scenario: The daily puzzle is the same for everyone on a given date.
func test_two_independent_clients_generate_an_identical_daily() -> void:
	var a := Generator.daily("2026-07-30")
	var b := Generator.daily("2026-07-30")
	assert_not_null(a)
	assert_eq(a.board.walls(), b.board.walls())
	assert_eq(a.board.goals, b.board.goals)
	assert_eq(a.tiles, b.tiles)
	assert_eq(a.par, b.par)
	assert_candidate_is_sound(a, "daily 2026-07-30")


func test_different_dates_give_different_dailies() -> void:
	assert_ne(Generator.daily_seed("2026-07-30"), Generator.daily_seed("2026-07-31"))


func test_the_daily_seed_hash_is_pinned() -> void:
	# FNV-1a is specified rather than borrowed from the engine so this value can
	# never drift with a Godot upgrade (§19). If this assertion ever changes,
	# every past daily changes with it.
	assert_eq(Generator.fnv1a_32("hexflow-daily2026-07-30"), Generator.daily_seed("2026-07-30"))
	assert_eq(Generator.fnv1a_32(""), 0x811C9DC5)


func test_a_budgeted_chapter_five_level_is_beatable_within_its_budget() -> void:
	var params := Generator.chapter_params(5, 12)
	var lv := Generator.generate(31337, params)
	assert_not_null(lv)
	assert_true(lv.has_budget())
	assert_eq(lv.budget, lv.par + 2)
	assert_true(lv.par <= lv.budget)


## C-32: the generator can build every shape, not just the hexagon it always did.
## Swept over seeds rather than checked once, because the failure a shape causes
## is intermittent — a start picked in a triangle's corner, or a goal placed in a
## ring's hole — and one lucky seed proves nothing.
func test_every_shape_generates_solvable_boards() -> void:
	var shapes: Array = [
		["hexagon", 3, 0], ["triangle", 6, 0], ["ring", 4, 1],
		["corridor", 9, 4], ["hourglass", 4, 3], ["star", 4, 0],
	]
	for entry: Variant in shapes:
		var spec: Array = entry
		var params := Generator.chapter_params(2, 6)
		params.shape = str(spec[0])
		params.radius = int(spec[1])
		params.shape_arg = int(spec[2])
		params.wall_count = 2
		params.min_distance = 3

		var made: int = 0
		for seed_offset: int in range(6):
			var level := Generator.generate(90000 + seed_offset * 977, params)
			if level == null:
				continue
			made += 1
			var cells: Array[Vector3i] = Hex.shape(
				str(spec[0]), int(spec[1]), int(spec[2]))
			assert_eq(level.board.cells(), cells, "%s built the wrong board" % spec[0])
			assert_true(level.board.has(level.board.start),
				"%s put the start off the board" % spec[0])
			for g: Vector3i in level.board.goals:
				assert_true(level.board.has(g), "%s put a goal off the board" % spec[0])
				assert_false(level.board.is_wall(g), "%s walled its own goal" % spec[0])
			assert_gt(level.par, 0, "%s produced a level with no ideal" % spec[0])
		assert_gt(made, 0, "%s produced nothing across six seeds" % spec[0])

## @property — Feature: Generation invariants (§24.2, §24.4).
##
## This is the single most valuable test in the suite: unsolvable levels are the
## 2016 prototype's signature failure (B2, B3). Every accepted candidate must be
## proven solvable, its own solution must reach WON when replayed through the
## real [GameState], its par must be the solver's optimum, and no wall may sit on
## a start or a goal.
##
## The push gate sweeps [constant SWEEP_SEEDS] seeds; the nightly job raises it
## via `-gtest_param`, per §24.1.
extends GutTest

const SWEEP_SEEDS := 60
const CHAPTERS := [1, 2, 3, 4, 5]


func _assert_candidate_is_sound(lv: Level, context: String) -> void:
	assert_not_null(lv, "%s produced no candidate at all" % context)
	if lv == null:
		return

	assert_eq(lv.validate(), [] as Array[String], "%s must validate" % context)

	# No wall on the start or on a goal — the exact defect B2.
	assert_false(lv.board.is_wall(lv.board.start), "%s walled its own start" % context)
	for g: Vector3i in lv.board.goals:
		assert_false(lv.board.is_wall(g), "%s walled a goal" % context)

	for c: Vector3i in lv.board.cells():
		assert_true(Hex.is_valid(c), "%s: %v breaks the cube invariant" % [context, c])
		assert_true(Hex.length(c) <= lv.board.radius, "%s: %v is off-board" % [context, c])

	# The recorded solution reaches WON, and takes exactly par placements.
	assert_gt(lv.solution.size(), 0, "%s recorded no solution" % context)
	var state := Solver.replay(lv, lv.solution_script)
	assert_eq(state.status, GameState.Status.WON, "%s: the solution must win" % context)
	assert_eq(state.placements, lv.par, "%s: par must equal the placement count" % context)
	assert_eq(Solver.placements_of(lv.solution_script), lv.solution,
		"%s: the stored target order must match its script" % context)

	# Re-running the solver reproduces the stored par (§17.1 loader check).
	assert_eq(Solver.solve(lv).par, lv.par, "%s: par must be reproducible" % context)


func test_every_accepted_candidate_is_solvable_across_all_chapters() -> void:
	for chapter: int in CHAPTERS:
		for i: int in range(SWEEP_SEEDS / CHAPTERS.size()):
			var level_index: int = 1 + (i % 12)
			var params := Generator.chapter_params(chapter, level_index)
			var lv := Generator.generate(1000 + i * 37, params)
			_assert_candidate_is_sound(lv, "ch%d l%d seed %d" % [chapter, level_index, 1000 + i * 37])


func test_consecutive_seeds_all_produce_sound_levels() -> void:
	var params := Generator.chapter_params(2, 6)
	for s: int in range(SWEEP_SEEDS):
		_assert_candidate_is_sound(Generator.generate(500000 + s, params), "seed %d" % (500000 + s))


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
	_assert_candidate_is_sound(a, "daily 2026-07-30")


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

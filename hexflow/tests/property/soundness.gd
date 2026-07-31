## What "a sound generated level" means, shared by the sweeps that assert it.
##
## Not named `test_*`, so GUT never collects it as a suite of its own — it is the
## base the sweep scripts extend.
##
## The sweeps live in separate scripts because the push gate runs one engine
## process per script (`tools/run_tests.sh`), and these two are the longest jobs
## in the suite by an order of magnitude. Together in one file they were a 40 s
## serial floor under a 20 s pool; apart they are two 20 s jobs that run at the
## same time as everything else. The split is a scheduling decision and nothing
## more: neither sweep lost a seed.
extends GutTest

## Seeds each sweep covers on a push. The nightly job raises it via
## `-gtest_param`, per §24.1.
const SWEEP_SEEDS := 60
const CHAPTERS := [1, 2, 3, 4, 5]


## Every invariant B2 and B3 broke: the candidate validates, no wall sits on its
## start or a goal, every cell is a legal on-board cube coordinate, and the
## recorded solution both wins when replayed through the real [GameState] and
## takes exactly the par the solver reproduces.
func assert_candidate_is_sound(lv: Level, context: String) -> void:
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

## @core — the solver (§8.3). Its optimality is what makes par honest, and par is
## what makes ★★★ attainable rather than luck (§5.10).
extends GutTest


func test_the_shortest_route_has_par_six_on_a_radius_three_board() -> void:
	# start and goal are 6 apart, so no radius-3 level can have a par below 6.
	var result := Solver.solve(Fixtures.fixed_level(Fixtures.shortest_route_tiles()))
	assert_true(result.is_solvable())
	assert_eq(result.par, 6)
	assert_eq(result.moves.size(), 6)
	assert_eq(result.moves[result.moves.size() - 1], Fixtures.GOAL)


func test_the_returned_solution_actually_wins_when_replayed() -> void:
	var lv := Fixtures.fixed_level(Fixtures.shortest_route_tiles())
	var result := Solver.solve(lv)
	var state := Solver.replay(lv, result.actions)
	assert_eq(state.status, GameState.Status.WON)
	assert_eq(state.placements, result.par)


func test_a_sealed_goal_is_reported_unsolvable() -> void:
	var walls: Array[Vector3i] = [
		Vector3i(3, -1, -2), Vector3i(2, 0, -2), Vector3i(2, 1, -3)
	]
	var result := Solver.solve(Fixtures.fixed_level(Fixtures.shortest_route_tiles(), walls))
	assert_false(result.is_solvable())
	assert_eq(result.status, Solver.Status.UNSOLVABLE)


func test_a_sequence_too_short_to_reach_the_goal_is_unsolvable() -> void:
	var result := Solver.solve(Fixtures.fixed_level(["NE", "NE", "NE"]))
	assert_false(result.is_solvable())


func test_the_solver_uses_a_discard_when_that_is_the_only_route() -> void:
	# The W tile is placeable but useless; only spending a discard on it leaves
	# enough NE tiles to reach the goal.
	var lv := Fixtures.fixed_level(["NE", "NE", "W", "NE", "NE", "NE", "NE"])
	lv.discards = 1
	var result := Solver.solve(lv)
	assert_true(result.is_solvable())
	assert_eq(result.par, 6, "a discard is not a placement, so par is unchanged")
	assert_eq(result.actions.size(), 7, "six placements and the discard between them")
	assert_eq(Solver.replay(lv, result.actions).status, GameState.Status.WON,
		"a script containing a discard must still replay to a win")


func test_a_portal_shortens_par_below_the_cube_distance() -> void:
	# Entering the portal at (-2,0,2) teleports the frontier next to the goal, so
	# the route is far shorter than the 6-step diagonal.
	var board := Board.build(
		3, Fixtures.START, [Fixtures.GOAL] as Array[Vector3i], [] as Array[Vector3i],
		[[Vector3i(-2, 0, 2), Vector3i(2, 0, -2)]]
	)
	var result := Solver.solve(Level.build(board, Fixtures.dirs(["NE", "NE"])))
	assert_true(result.is_solvable())
	assert_eq(result.par, 2, "one step onto the portal, one step onto the goal")


func test_solving_from_a_live_state_powers_the_hint_system() -> void:
	var lv := Fixtures.fixed_level(Fixtures.shortest_route_tiles())
	var state := GameState.start(lv)
	state.place(Vector3i(-2, 0, 2))
	state.place(Vector3i(-1, 0, 1))
	var result := Solver.solve_state(state)
	assert_true(result.is_solvable())
	assert_eq(result.par, 4, "four placements remain")
	assert_eq(result.moves[0], Vector3i(0, 0, 0), "the hint is the next optimal target")


func test_the_solver_is_deterministic() -> void:
	var lv := Fixtures.seeded_level(918273)
	var a := Solver.solve(lv)
	var b := Solver.solve(lv)
	assert_eq(a.status, b.status)
	assert_eq(a.par, b.par)
	assert_eq(a.moves, b.moves)


func test_a_tight_state_cap_degrades_to_unknown_not_to_a_wrong_answer() -> void:
	var result := Solver.solve(Fixtures.seeded_level(1234), 40)
	assert_ne(result.status, Solver.Status.SOLVABLE,
		"an exhausted budget must never be reported as a proof")

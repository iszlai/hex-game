## @core — Feature: Placement rules (§5.4, §5.6, §6). One test per §24.2 scenario.
extends GutTest

const GATE := Vector3i(0, 0, 0)


func _path(cells: Array) -> Dictionary:
	var out: Dictionary = {}
	for c: Variant in cells:
		out[c as Vector3i] = true
	return out


## Scenario: A drawn direction extends the path from an existing path cell.
func test_a_drawn_direction_extends_the_path_by_one_cell() -> void:
	var board := Fixtures.reference_board()
	var path := _path([Fixtures.START])
	var targets := Rules.legal_targets(board, path, Direction.NE)
	assert_eq(targets, [Vector3i(-2, 0, 2)] as Array[Vector3i])
	assert_eq(Rules.anchor_for(targets[0], Direction.NE), Fixtures.START)


## Scenario: Every legal target has exactly one anchor.
func test_every_legal_target_has_exactly_one_anchor() -> void:
	var board := Fixtures.reference_board()
	var path := _path([
		Vector3i(-3, 0, 3), Vector3i(-2, 0, 2), Vector3i(-1, 0, 1),
		Vector3i(0, 0, 0), Vector3i(1, 0, -1), Vector3i(-2, 1, 1),
	])
	assert_eq(path.size(), 6)
	var targets := Rules.legal_targets(board, path, Direction.E)
	assert_gt(targets.size(), 0)
	var anchors: Dictionary = {}
	for t: Vector3i in targets:
		var a := Rules.anchor_for(t, Direction.E)
		assert_true(path.has(a), "anchor %v must be in the path" % a)
		assert_false(anchors.has(a), "anchor %v must serve exactly one target" % a)
		anchors[a] = true
		assert_false(path.has(t), "target %v must not already be in the path" % t)
		assert_false(board.is_wall(t), "target %v must not be a wall" % t)


## Scenario: Walls can never be entered.
func test_walls_are_never_legal_targets() -> void:
	var blocked := Vector3i(-2, -1, 3)  # start + E
	var board := Fixtures.reference_board([blocked] as Array[Vector3i])
	var path := _path([Fixtures.START])
	assert_true(board.is_wall(blocked))
	assert_eq(Rules.legal_targets(board, path, Direction.E), [] as Array[Vector3i])


## Scenario: A gate requires two path neighbours.
func test_a_gate_needs_two_path_neighbours() -> void:
	var board := Board.build(
		3, Fixtures.START, [Fixtures.GOAL] as Array[Vector3i],
		[] as Array[Vector3i], [], [GATE] as Array[Vector3i]
	)
	var one := _path([Vector3i(-1, 0, 1)])
	assert_eq(Rules.path_neighbour_count(one, GATE), 1)
	assert_false(Rules.gate_satisfied(board, one, GATE))
	assert_false(Rules.legal_targets(board, one, Direction.NE).has(GATE))

	var two := _path([Vector3i(-1, 0, 1), Vector3i(0, -1, 1)])
	assert_eq(Rules.path_neighbour_count(two, GATE), 2)
	assert_true(Rules.gate_satisfied(board, two, GATE))
	assert_true(Rules.legal_targets(board, two, Direction.NE).has(GATE))


## Scenario: The goal condition is reaching every goal cell.
func test_winning_requires_every_goal_cell() -> void:
	var goals: Array[Vector3i] = [Vector3i(-2, 0, 2), Vector3i(-1, 0, 1)]
	var board := Fixtures.reference_board([] as Array[Vector3i], goals)
	assert_false(Rules.is_won(board, _path([Fixtures.START])))
	assert_false(Rules.is_won(board, _path([Fixtures.START, goals[0]])))
	assert_true(Rules.is_won(board, _path([Fixtures.START, goals[0], goals[1]])))


## Scenario: An unreachable goal is a recoverable dead state (the detection half).
func test_a_walled_off_goal_is_detected_as_unreachable() -> void:
	var open_board := Fixtures.reference_board()
	assert_false(Rules.has_unreachable_goal(open_board, _path([Fixtures.START])))

	# The goal's only three on-board neighbours, all sealed.
	var walls: Array[Vector3i] = [
		Vector3i(3, -1, -2), Vector3i(2, 0, -2), Vector3i(2, 1, -3)
	]
	var sealed := Fixtures.reference_board(walls)
	assert_true(Rules.has_unreachable_goal(sealed, _path([Fixtures.START])))


func test_reachability_is_optimistic_and_ignores_direction() -> void:
	var board := Fixtures.reference_board()
	var reach := Rules.reachable(board, _path([Fixtures.START]))
	assert_eq(reach.size(), board.size(), "an open board is entirely reachable")


## Scenario: A goal behind an uncrossable wall is reachable through a portal.
##
## §5.5.3 joins a portal's twin the instant the near end is entered, so the far
## side of a wall the path can never cross is still somewhere the path can get to.
## The flood fill did not follow portals, so §5.8 declared any such board dead on
## the frame it opened — which is the whole of the tutorial's portal lesson, where
## the portal is the *only* way across (C-37).
func test_a_goal_reachable_only_through_a_portal_is_not_a_dead_board() -> void:
	# Three by two: the middle column walled off end to end, so no route crosses.
	var cells: Array[Vector3i] = Hex.shape("corridor", 3, 2)
	var start := Vector3i(0, 0, 0)
	var far := Vector3i(2, -1, -1)
	var near_portal := Vector3i(0, 1, -1)
	var far_portal := Vector3i(2, -2, 0)
	var walls: Array[Vector3i] = [Vector3i(1, 0, -1), Vector3i(1, -1, 0)]
	assert_true(cells.has(far), "the fixture is the board the lesson is drawn on")

	var severed := Board.build(3, start, [far] as Array[Vector3i], walls, [],
		[] as Array[Vector3i], [] as Array[Vector3i], "corridor", 2)
	assert_true(Rules.has_unreachable_goal(severed, _path([start])),
		"with no portal the goal really is walled off")

	var linked := Board.build(3, start, [far] as Array[Vector3i], walls,
		[[near_portal, far_portal]], [] as Array[Vector3i], [] as Array[Vector3i],
		"corridor", 2)
	assert_false(Rules.has_unreachable_goal(linked, _path([start])),
		"the portal is a way across, and the optimistic bound has to say so")
	assert_true(Rules.reachable(linked, _path([start])).has(far))


func test_hops_to_measures_the_optimistic_route_length() -> void:
	var board := Fixtures.reference_board()
	assert_eq(Rules.hops_to(board, _path([Fixtures.START]), Fixtures.GOAL), 6)
	assert_eq(Rules.hops_to(board, _path([Fixtures.GOAL]), Fixtures.GOAL), 0)
	var sealed := Fixtures.reference_board([
		Vector3i(3, -1, -2), Vector3i(2, 0, -2), Vector3i(2, 1, -3)
	] as Array[Vector3i])
	assert_eq(Rules.hops_to(sealed, _path([Fixtures.START]), Fixtures.GOAL), -1)


func test_wild_targets_cover_every_adjacent_enterable_cell() -> void:
	var board := Fixtures.reference_board()
	var targets := Rules.wild_targets(board, _path([Fixtures.START]))
	# The bottom-left corner has three on-board neighbours.
	assert_eq(targets.size(), 3)
	for t: Vector3i in targets:
		assert_eq(Hex.distance(Fixtures.START, t), 1)


func test_legal_targets_come_back_in_canonical_order() -> void:
	var board := Fixtures.reference_board()
	var path := _path([Vector3i(0, 0, 0), Vector3i(1, 0, -1), Vector3i(-1, 0, 1)])
	var targets := Rules.legal_targets(board, path, Direction.E)
	assert_eq(targets, Hex.sort_cells(targets))

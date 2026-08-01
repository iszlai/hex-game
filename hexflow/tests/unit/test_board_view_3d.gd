## @core — the C-18 view's screen surface, and §11.2 riding on it unchanged.
##
## C-18 claims two things that are cheap to say and easy to get wrong: that a
## pointer still resolves to the right cell once the board is oblique (B7's fix
## surviving the move to 3D), and that the ±75° cone and the clockwise cycling need
## no change because they simply follow the camera. Both are asserted here against
## an actual [InputRouter], with the expected cells derived from where things land
## on screen rather than hardcoded — a hardcoded cell would pass just as happily
## with the rotation applied backwards.
extends GutTest

const PLAY := Vector2(880.0, 688.0)

var _view: BoardView3D = null
var _state: GameState = null


func before_each() -> void:
	SettingsService.set_value("reduce_motion", true)   # six real tweens, quickly
	_view = BoardView3D.new()
	add_child_autofree(_view)
	_state = GameState.start(Fixtures.fixed_level(Fixtures.shortest_route_tiles()))
	_view.bind(_state, PLAY)


func after_each() -> void:
	SettingsService.set_value("reduce_motion", false)


func _neighbours_of_centre() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for d: int in Direction.ALL:
		out.append(Direction.delta(d))
	return out


func _feed(router: InputRouter, targets: Array[Vector3i]) -> void:
	router.set_candidates(targets, _view.centres(), _view.centre_on_screen())


## How well [param cell] lines up with straight up on screen, from the board centre.
func _up_alignment(cell: Vector3i) -> float:
	var delta: Vector2 = _view.centre_of(cell) - _view.centre_on_screen()
	return Vector2.UP.dot(delta.normalized())


## The cell a press of "up" must land on: one of the best-aligned candidates. Stated
## as "no candidate is better aligned" rather than by picking a winner, because two
## neighbours can be exactly equally up and which of those the router prefers is its
## own tie-break, not something the camera decides.
func _assert_is_as_up_as_possible(cell: Vector3i, targets: Array[Vector3i]) -> void:
	var best: float = -2.0
	for c: Vector3i in targets:
		best = maxf(best, _up_alignment(c))
	assert_almost_eq(_up_alignment(cell), best, 0.0001,
		"%v is not among the cells most directly above the cursor" % cell)
	assert_lt(_view.centre_of(cell).y, _view.centre_on_screen().y, "%v must be above" % cell)


func test_the_board_is_framed_by_the_projected_fit() -> void:
	assert_eq(int(_view.layout.size), BoardCamera.fit_projected(3, PLAY, BoardView3D.TILE_TOP_RATIO))
	assert_eq(_view.centre_on_screen(), PLAY * 0.5)
	assert_eq(_view.centres().size(), _state.board.cells().size(),
		"every cell has a screen position, not just the candidates (free cursor)")


## B7, in 3D: a click on a cell's own screen position must resolve to that cell —
## and land on its *centre*, not merely somewhere inside it. A cell is ~100 px wide
## at this size, so a systematic bias of a few pixels would round to the right cell
## everywhere except at the edges, where it would round to the wrong one.
func test_every_cell_round_trips_from_its_screen_position() -> void:
	for c: Vector3i in _state.board.cells():
		var at: Vector2 = _view.centre_of(c)
		assert_eq(_view.cell_at(at), c, "%v must round-trip" % c)
		var hit: Vector3 = _view.camera.plane_point(at)
		var want: Vector3 = _view.layout.to_plane(c)
		assert_almost_eq(hit.x, want.x, 0.5, "%v x is off centre" % c)
		assert_almost_eq(hit.z, want.z, 0.5, "%v z is off centre" % c)


## A finger is not a point. Off-centre presses inside a cell must resolve to it too,
## which is what makes the hit-test usable on a touchscreen (§11.4).
func test_off_centre_presses_resolve_to_the_same_cell() -> void:
	# Well inside the projected cell: half a row pitch is the tightest direction
	# once the projection has foreshortened it.
	var reach: float = _view.layout.size * 0.5
	for c: Vector3i in _state.board.cells():
		for offset: Vector2 in [Vector2(reach, 0.0), Vector2(-reach, 0.0),
				Vector2(0.0, reach * 0.6), Vector2(0.0, -reach * 0.6)]:
			assert_eq(_view.cell_at(_view.centre_of(c) + offset), c,
				"%v must own %v from its centre" % [c, offset])


func test_the_hit_test_still_works_after_a_rotation() -> void:
	_view.rotate_by(1)
	assert_true(await wait_for_signal(_view.camera.yaw_settled, 1.0))
	for c: Vector3i in _state.board.cells():
		assert_eq(_view.cell_at(_view.centre_of(c)), c, "%v must round-trip at stop 1" % c)


## The cone follows the camera: "up" means the candidate that is now visually up,
## which after a 60° turn is a different cell.
func test_the_directional_cone_follows_the_camera() -> void:
	var router := InputRouter.new()
	var targets := _neighbours_of_centre()
	_feed(router, targets)
	router.cursor = Vector3i.ZERO          # start in the middle, so all six are reachable
	router.has_cursor = true
	assert_true(router.move(Vector2.UP), "up must find a candidate")
	var before: Vector3i = router.cursor
	_assert_is_as_up_as_possible(before, targets)

	_view.rotate_by(1)
	assert_true(await wait_for_signal(_view.camera.yaw_settled, 1.0))
	_feed(router, targets)
	router.cursor = Vector3i.ZERO
	router.has_cursor = true
	assert_true(router.move(Vector2.UP))
	_assert_is_as_up_as_possible(router.cursor, targets)
	assert_ne(router.cursor, before, "and it is a different cell once the board has turned")


## Cycling stays a rotation rather than becoming an arbitrary order: a 60° turn
## cyclically shifts the clockwise order, it does not scramble it.
func test_clockwise_cycling_rotates_with_the_camera() -> void:
	var router := InputRouter.new()
	var targets := _neighbours_of_centre()
	_feed(router, targets)
	var before: Array[Vector3i] = router.candidates().duplicate()
	assert_eq(before.size(), 6)

	_view.rotate_by(1)
	assert_true(await wait_for_signal(_view.camera.yaw_settled, 1.0))
	_feed(router, targets)
	var after: Array[Vector3i] = router.candidates().duplicate()
	assert_true(_is_cyclic_rotation(before, after),
		"%s must be a cyclic rotation of %s" % [after, before])


func test_six_stops_return_the_cycling_order_to_where_it_started() -> void:
	var router := InputRouter.new()
	var targets := _neighbours_of_centre()
	_feed(router, targets)
	var before: Array[Vector3i] = router.candidates().duplicate()
	for i: int in range(BoardCamera.YAW_STOPS):
		_view.rotate_by(1)
		assert_true(await wait_for_signal(_view.camera.yaw_settled, 1.0), "stop %d" % i)
	_feed(router, targets)
	assert_eq(router.candidates(), before)


## §11.2's positions are recomputed when the yaw changes and at no other time (C4).
## They also jump to the stop being *travelled to*, not the one being left, so a
## press during the tween behaves like the board the player is about to see.
func test_positions_are_recomputed_on_yaw_change_and_not_per_frame() -> void:
	watch_signals(_view)
	var before: Dictionary = _view.centres().duplicate()
	await wait_process_frames(5)
	assert_signal_emit_count(_view, "screen_positions_changed", 0, "idle frames recompute nothing")
	assert_eq(_view.centres(), before, "and change nothing")

	_view.rotate_by(1)
	assert_signal_emit_count(_view, "screen_positions_changed", 1, "one recompute per rotation")
	assert_ne(_view.centres(), before, "positions move with the yaw")
	var mid: Dictionary = _view.centres().duplicate()
	assert_true(_view.camera.is_rotating(), "the camera is still travelling")
	assert_true(await wait_for_signal(_view.camera.yaw_settled, 1.0))
	assert_eq(_view.centres(), mid,
		"the tween landing changes nothing: the positions were already the target's")


## §14.1's flow pulse. One band crosses the tiles *and* the stroke lying on them,
## which is the whole reason it is driven from here rather than from either mesh:
## two tweens would be two clocks, and the tile would brighten a frame apart from
## its own connector.
func test_the_flow_pulse_runs_one_band_across_both_meshes() -> void:
	assert_eq(_view.flow_head(), -1.0, "no band until something is placed")

	_view.play_flow_pulse()
	assert_eq(_view.flow_head(), 0.0, "it starts at the start, not a frame later")
	for mesh: GeometryInstance3D in [_view.tiles, _view.links]:
		assert_eq((mesh.material_override as ShaderMaterial)
			.get_shader_parameter("flow_head"), 0.0, "both meshes take the same head")

	await wait_seconds(Motion.seconds("flow_pulse") + 0.2)
	assert_eq(_view.flow_head(), -1.0, "and parks off the path when it is done")
	assert_eq((_view.tiles.material_override as ShaderMaterial)
		.get_shader_parameter("flow_head"), -1.0, "so no band is left lit")


## C-36: the band travels *to* something, so it discharges into the cell the route
## ends at when it gets there. Detected as the head crossing 1.0 rather than
## scheduled, because the tween is eased and no caller can work out in advance what
## fraction of the duration the far end is reached at.
func test_the_band_discharges_into_the_cell_it_reaches() -> void:
	assert_true(_state.place(_state.legal_targets()[0]), "a route to travel down")
	_view.rebuild()
	assert_eq(_view.tiles.strike_time(), -1.0, "nothing struck yet")

	_view.play_flow_pulse()
	assert_eq(_view.tiles.strike_time(), -1.0, "and nothing struck as it sets off")

	await wait_seconds(Motion.seconds("flow_pulse") + 0.05)
	assert_gte(_view.tiles.strike_time(), 0.0, "the band arrived and the cell was hit")
	assert_ne(_view.tiles.strike_at(), BoardTiles.STRIKE_NOWHERE, "at the route's end")


## A second placement while the first pulse is still travelling restarts it rather
## than running two bands down the same path.
func test_a_second_placement_restarts_the_pulse() -> void:
	_view.play_flow_pulse()
	await wait_process_frames(2)
	_view.play_flow_pulse()
	assert_eq(_view.flow_head(), 0.0, "back to the start")


## §14.2's sequence, in the order the spec lays it out. The beats are checked by
## what they *do* rather than by watching a clock: the flourish is immediate, the
## ripple has not left yet at t=0, and both have happened by the time the flow beat
## is due.
func test_the_goal_sequence_runs_its_beats_in_order() -> void:
	var goal: Vector3i = _state.board.start
	assert_eq(_view.tiles.ripple_time(), -1.0, "no wave before the goal")

	_view.play_goal_reached(goal)
	assert_ne(_view.tiles.pop_scale(goal), 1.0, "the goal cell flourishes at once (t=0)")
	assert_eq(_view.tiles.ripple_time(), -1.0, "and the wave waits its turn (t=120)")

	# The wave outlives its own beat by half a second, so this is the one assertion
	# in the sequence that does not race the frame clock.
	await wait_seconds(Motion.beat_seconds("flow") + 0.05)
	assert_gte(_view.tiles.ripple_time(), 0.0, "the wave has left by the flow beat")


## §14.2 runs that pulse at 2x, which is the difference between the sequence
## reading as one event and as three that happen to overlap.
func test_the_goal_pulse_runs_at_double_speed() -> void:
	_view.play_flow_pulse(Motion.GOAL_FLOW_SPEEDUP)
	await wait_seconds(Motion.seconds("flow_pulse") / 2.0 + 0.15)
	assert_eq(_view.flow_head(), -1.0, "a 2x pulse is over in half the time")


## §14.1's dead-state desaturation, and the half §5.8 adds to it: DEAD is
## *recoverable*, so the drain has an inverse. A board that stayed grey after the
## player undid their way out would be telling them the level was still lost.
func test_a_dead_board_drains_and_comes_back() -> void:
	assert_eq(_view.saturation(), 1.0, "a live board keeps its colour")

	_view.play_dead()
	await wait_seconds(Motion.seconds("dead_desaturate") + 0.15)
	assert_almost_eq(_view.saturation(), BoardView3D.DEAD_SATURATION, 0.001,
		"§14.1's 70%")
	assert_gt(_view.saturation(), 0.0, "70%, not grey — the level is not over")
	for mesh: GeometryInstance3D in [_view.tiles, _view.links, _view.marks]:
		assert_almost_eq(float((mesh.material_override as ShaderMaterial)
			.get_shader_parameter("saturation")), BoardView3D.DEAD_SATURATION, 0.001,
			"the whole board drains, not part of it")

	_view.clear_dead()
	await wait_seconds(Motion.seconds("dead_desaturate") + 0.15)
	assert_almost_eq(_view.saturation(), 1.0, 0.001, "and undoing brings it back")


## Binding a new level cannot inherit the last one's mood.
func test_a_new_level_is_never_born_dead() -> void:
	_view.play_dead()
	await wait_seconds(Motion.seconds("dead_desaturate") + 0.15)
	_view.bind(GameState.start(Fixtures.fixed_level(Fixtures.shortest_route_tiles())), PLAY)
	assert_eq(_view.saturation(), 1.0, "a fresh level starts in full colour")


## A `Control` that swallows pointer events in the GUI pass is precisely how B7 hid
## for all of M3. This node sits over the whole play area, so it must never do it.
func test_the_container_does_not_swallow_pointer_input() -> void:
	assert_eq(_view.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func _is_cyclic_rotation(a: Array[Vector3i], b: Array[Vector3i]) -> bool:
	if a.size() != b.size():
		return false
	for shift: int in range(a.size()):
		var same := true
		for i: int in range(a.size()):
			if a[i] != b[(i + shift) % b.size()]:
				same = false
				break
		if same:
			return true
	return false


## §14.2's last beat: "t=340 goal cell settles, converts to path colour".
##
## It was the one beat of the six that had never been built, and the reason it was
## easy to miss is that nothing *looked* absent — the cell did end up path-coloured.
## It just did so at t=0, because entering a goal makes it a path cell as far as the
## rules are concerned and the board followed immediately. So the flourish, the
## burst and the ripple all played over a tile that had already stopped looking like
## a goal, and §14.2's whole point is that they play over one that has not.
func test_a_reached_goal_holds_its_colour_until_the_sequence_converts_it() -> void:
	var goal: Vector3i = _state.board.goals[0]
	_view.tiles.hold_goal(goal)

	assert_almost_eq(_view.tiles.settle_ratio(goal), 0.0, 0.001,
		"a goal that has just been reached has not converted at all")
	assert_eq(_view.tiles.tint_of(goal), _view.palette.goal_cell,
		"and is still drawn in the goal's own colour")

	_view.tiles.settle_goal(goal)
	await wait_seconds(float(Motion.GOAL_SETTLE_MS) / 1000.0 + 0.3)

	assert_almost_eq(_view.tiles.settle_ratio(goal), 1.0, 0.001,
		"once settled it is a path cell like any other")
	assert_ne(_view.tiles.tint_of(goal), _view.palette.goal_cell,
		"and has left the goal colour behind")


## The conversion is not optional under §14.5. Reduce Motion shortens a transition
## rather than dropping it — a goal left permanently in its goal colour would read
## as a goal still to reach, which is a lie about the state of the board rather than
## a quieter animation.
func test_reduce_motion_still_arrives_at_path_colour() -> void:
	SettingsService.set_value("reduce_motion", true)
	var goal: Vector3i = _state.board.goals[0]
	_view.tiles.hold_goal(goal)
	_view.tiles.settle_goal(goal)
	await wait_seconds(float(Motion.GOAL_SETTLE_MS) / 1000.0 + 0.3)
	assert_almost_eq(_view.tiles.settle_ratio(goal), 1.0, 0.001,
		"§14.5 makes it quick, not absent")


## The whole sequence, as one run: every beat fires in §14.2's order and the cell
## ends where §14.2 leaves it. Driven through the real entry point rather than the
## pieces, because the ordering is the thing under test.
func test_the_goal_sequence_ends_with_the_cell_converted() -> void:
	SettingsService.set_value("reduce_motion", false)
	var goal: Vector3i = _state.board.goals[0]
	_view.play_goal_reached(goal)

	assert_almost_eq(_view.tiles.settle_ratio(goal), 0.0, 0.001,
		"§14.2 spends its first 340 ms on a cell that is still a goal")

	await wait_seconds(Motion.beat_seconds("settle")
		+ float(Motion.GOAL_SETTLE_MS) / 1000.0 + 0.4)
	assert_almost_eq(_view.tiles.settle_ratio(goal), 1.0, 0.001,
		"and hands back an ordinary path cell")
	SettingsService.set_value("reduce_motion", true)

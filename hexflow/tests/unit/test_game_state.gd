## @core — Features: Placement rules (commit half), Fairness and dead states,
## Undo and determinism (§5.5, §5.7, §5.8, §5.9, §19).
extends GutTest

## start + E. Walling this makes an E draw unplaceable from the opening position.
const BLOCKS_E := Vector3i(-2, -1, 3)


func _count_events(events: Array, type: String) -> int:
	var n: int = 0
	for e: Variant in events:
		if str((e as Dictionary)["type"]) == type:
			n += 1
	return n


# --- placement ---------------------------------------------------------------

## Scenario: A drawn direction extends the path ... and a connector is recorded.
func test_confirming_a_target_joins_it_and_records_a_connector() -> void:
	var state := GameState.start(Fixtures.fixed_level(Fixtures.shortest_route_tiles()))
	assert_eq(state.legal_targets(), [Vector3i(-2, 0, 2)] as Array[Vector3i])
	assert_true(state.place(Vector3i(-2, 0, 2)))
	assert_true(state.path.has(Vector3i(-2, 0, 2)))
	assert_eq(state.placements, 1)
	assert_eq(state.edges.size(), 1)
	assert_eq(state.edges[0], [Fixtures.START, Direction.NE, Vector3i(-2, 0, 2)])


func test_an_illegal_target_changes_nothing() -> void:
	var state := GameState.start(Fixtures.fixed_level(Fixtures.shortest_route_tiles()))
	assert_false(state.place(Vector3i(3, 0, -3)))
	assert_eq(state.placements, 0)
	assert_eq(state.path.size(), 1)
	assert_eq(state.stream.index, 0)


## Scenario: The goal condition is reaching every goal cell.
func test_two_goals_must_both_be_joined_to_win() -> void:
	var goals: Array[Vector3i] = [Vector3i(-2, 0, 2), Vector3i(-1, 0, 1)]
	var lv := Level.build(
		Fixtures.reference_board([] as Array[Vector3i], goals), Fixtures.dirs(["NE", "NE"])
	)
	var state := GameState.start(lv)
	assert_true(state.place(Vector3i(-2, 0, 2)))
	assert_eq(state.status, GameState.Status.PLAYING, "one goal of two is not a win")
	assert_true(state.place(Vector3i(-1, 0, 1)))
	assert_eq(state.status, GameState.Status.WON)


## Scenario: A portal adds its twin to the path.
func test_a_portal_adds_its_twin_and_both_ends_can_grow() -> void:
	var a := Vector3i(0, 0, 0)
	var b := Vector3i(2, -2, 0)
	var board := Board.build(
		3, Fixtures.START, [Fixtures.GOAL] as Array[Vector3i], [] as Array[Vector3i], [[a, b]]
	)
	var state := GameState.start(Level.build(board, Fixtures.dirs(
		["NE", "NE", "NE", "NE", "NE", "NE"]
	)))
	state.place(Vector3i(-2, 0, 2))
	state.place(Vector3i(-1, 0, 1))
	assert_true(state.place(a), "the third NE lands on portal A")
	assert_true(state.path.has(a))
	assert_true(state.path.has(b), "the twin joins immediately")
	assert_eq(state.placements, 3, "a portal link is not a placement")

	var targets := state.legal_targets()
	assert_true(targets.has(Vector3i(1, 0, -1)), "growth continues from portal A")
	assert_true(targets.has(Vector3i(3, -2, -1)), "and from portal B, the new frontier")


func test_a_wild_cell_grants_a_charge_that_places_in_any_direction() -> void:
	var wild := Vector3i(-2, 0, 2)
	var board := Board.build(
		3, Fixtures.START, [Fixtures.GOAL] as Array[Vector3i], [] as Array[Vector3i],
		[], [] as Array[Vector3i], [wild] as Array[Vector3i]
	)
	var state := GameState.start(Level.build(board, Fixtures.dirs(["NE", "NE", "NE"])))
	assert_true(state.place(wild))
	assert_eq(state.wild_charges, 1)

	# The drawn tile is NE, but the charge unlocks every adjacent cell.
	var off_direction := Vector3i(-1, -1, 2)
	assert_false(state.legal_targets().has(off_direction))
	assert_true(state.wild_targets().has(off_direction))
	assert_true(state.place_wild(off_direction))
	assert_eq(state.wild_charges, 0)
	assert_true(state.path.has(off_direction))


func test_a_budget_that_is_used_up_ends_the_run() -> void:
	var lv := Fixtures.fixed_level(Fixtures.shortest_route_tiles())
	lv.budget = 2
	var state := GameState.start(lv)
	state.place(Vector3i(-2, 0, 2))
	assert_eq(state.status, GameState.Status.PLAYING)
	state.place(Vector3i(-1, 0, 1))
	assert_eq(state.status, GameState.Status.DEAD, "exceeding the budget is DEAD")


# --- fairness ----------------------------------------------------------------

## Scenario: An impossible draw costs nothing.
func test_an_impossible_draw_is_skipped_for_free() -> void:
	var lv := Fixtures.fixed_level(["E", "NE", "NE"], [BLOCKS_E] as Array[Vector3i])
	var state := GameState.start(lv)
	assert_eq(state.discards_left, 3, "an auto-skip never costs a charge")
	assert_eq(state.current_tile(), Direction.NE, "the stream advanced past the dead tile")
	assert_eq(state.stream.index, 1)
	assert_eq(_count_events(state.events, GameState.EV_AUTO_SKIPPED), 1,
		"the auto-skip is reported to the view")


## Scenario: A voluntary discard costs a charge.
func test_a_voluntary_discard_costs_a_charge_and_advances_the_stream() -> void:
	var state := GameState.start(Fixtures.fixed_level(["NE", "NE", "NE"]))
	assert_gt(state.legal_targets().size(), 0, "the tile was placeable, so this is voluntary")
	assert_true(state.discard())
	assert_eq(state.discards_left, 2)
	assert_eq(state.stream.index, 1)


## Scenario: Running out of discards does not end the level.
func test_zero_discards_removes_the_option_but_not_the_level() -> void:
	var lv := Fixtures.fixed_level(Fixtures.shortest_route_tiles())
	lv.discards = 0
	var state := GameState.start(lv)
	assert_false(state.can_discard())
	assert_false(state.discard())
	assert_eq(state.status, GameState.Status.PLAYING)
	assert_true(state.place(Vector3i(-2, 0, 2)))


# --- dead states -------------------------------------------------------------

## Scenario: An unreachable goal is a recoverable dead state.
func test_an_unreachable_goal_is_dead_and_loses_no_progress() -> void:
	var walls: Array[Vector3i] = [
		Vector3i(3, -1, -2), Vector3i(2, 0, -2), Vector3i(2, 1, -3)
	]
	var state := GameState.start(Fixtures.fixed_level(Fixtures.shortest_route_tiles(), walls))
	assert_eq(state.status, GameState.Status.DEAD)
	assert_true(state.path.has(Fixtures.START), "the board is intact; nothing was lost")


func test_an_exhausted_tile_sequence_is_dead_and_undoable() -> void:
	var state := GameState.start(Fixtures.fixed_level(["NE"]))
	assert_true(state.place(Vector3i(-2, 0, 2)))
	assert_eq(state.status, GameState.Status.DEAD, "the fixed sequence ran out")
	assert_true(state.can_undo(), "a dead board is a recoverable mistake")
	assert_true(state.undo())
	assert_eq(state.status, GameState.Status.PLAYING)
	assert_eq(state.placements, 0)


# --- undo --------------------------------------------------------------------

## Scenario: Undo restores the exact prior state.
func test_undo_restores_the_exact_prior_state() -> void:
	var state := GameState.start(Fixtures.fixed_level(
		["NE", "NE", "NE", "NE", "W", "E", "NE", "NE"]
	))
	state.place(Vector3i(-2, 0, 2))
	state.place(Vector3i(-1, 0, 1))
	state.place(Vector3i(0, 0, 0))
	var before := state.to_dict()

	assert_true(state.place(Vector3i(1, 0, -1)))
	assert_ne(state.to_dict(), before)
	assert_true(state.undo())
	assert_eq(state.to_dict(), before,
		"path, edges, stream index, discards and wild charges must all match")


## Scenario: Undo rewinds through auto-discards.
func test_undo_rewinds_past_the_auto_discards_that_preceded_the_move() -> void:
	# Two leading E tiles are both unplaceable, so both are skipped for free.
	var lv := Fixtures.fixed_level(["E", "E", "NE", "NE"], [BLOCKS_E] as Array[Vector3i])
	var state := GameState.start(lv)
	assert_eq(state.stream.index, 2, "two tiles auto-skipped")
	assert_eq(state.current_tile(), Direction.NE)

	assert_true(state.place(Vector3i(-2, 0, 2)))
	assert_eq(state.history[0].stream_index_before, 0,
		"the move records the index from before the skips")

	assert_true(state.undo())
	assert_eq(state.path.size(), 1)
	assert_eq(state.current_tile(), Direction.NE,
		"the player faces the tile that was originally placeable")


func test_undo_restores_a_spent_wild_charge() -> void:
	var wild := Vector3i(-2, 0, 2)
	var board := Board.build(
		3, Fixtures.START, [Fixtures.GOAL] as Array[Vector3i], [] as Array[Vector3i],
		[], [] as Array[Vector3i], [wild] as Array[Vector3i]
	)
	var state := GameState.start(Level.build(board, Fixtures.dirs(["NE", "NE", "NE"])))
	state.place(wild)
	assert_eq(state.wild_charges, 1)
	state.place_wild(Vector3i(-1, -1, 2))
	assert_eq(state.wild_charges, 0)
	assert_true(state.undo())
	assert_eq(state.wild_charges, 1, "the charge comes back")


func test_undo_restores_a_portal_twin() -> void:
	var a := Vector3i(-2, 0, 2)
	var b := Vector3i(2, -2, 0)
	var board := Board.build(
		3, Fixtures.START, [Fixtures.GOAL] as Array[Vector3i], [] as Array[Vector3i], [[a, b]]
	)
	var state := GameState.start(Level.build(board, Fixtures.dirs(["NE", "NE", "NE"])))
	state.place(a)
	assert_true(state.path.has(b))
	assert_true(state.undo())
	assert_false(state.path.has(b), "the twin leaves with the move that summoned it")
	assert_eq(state.edges.size(), 0)


# --- determinism -------------------------------------------------------------

## Scenario: A seed plus a move list reproduces a state exactly.
func test_a_seed_plus_a_move_list_reproduces_the_state_exactly() -> void:
	var recorded: Array[Vector3i] = []
	var state := GameState.start(Fixtures.seeded_level(918273))
	for _i: int in range(14):
		if state.status != GameState.Status.PLAYING:
			break
		var targets := state.legal_targets()
		if targets.is_empty():
			break
		recorded.append(targets[0])
		state.place(targets[0])
	assert_gt(recorded.size(), 5, "the fixture must actually play out")

	var replay := GameState.start(Fixtures.seeded_level(918273))
	for t: Vector3i in recorded:
		assert_true(replay.place(t), "replaying %v must be legal" % t)
	assert_eq(replay.to_dict(), state.to_dict())


func test_restart_reproduces_the_opening_position_byte_for_byte() -> void:
	var lv := Fixtures.seeded_level(4242)
	var opening := GameState.start(lv).to_dict()
	var state := GameState.start(lv)
	state.place(state.legal_targets()[0])
	assert_eq(state.restart().to_dict(), opening)


## §5.8's dead state is recoverable, so the banner's job is to say *which* recovery
## the player wants — and there are four different endings. A board that is boxed
## in wants an undo; a queue that has run dry wants a restart. One sentence for all
## four sends the player looking at the wrong half of the screen, which is exactly
## what "No route left" did to a run that had simply spent its tiles.
func test_a_dead_run_says_which_way_it_died() -> void:
	# Out of tiles: the path can still grow, there is just nothing left to grow it.
	var short := Fixtures.fixed_level(["NE"] as Array[String])
	var state := GameState.start(short)
	assert_true(state.place(state.legal_targets()[0]))
	assert_eq(state.status, GameState.Status.DEAD)
	assert_eq(state.dead_reason, GameState.Dead.OUT_OF_TILES,
		"the queue ran out; the board is fine")


## And the reason does not outlive the state it explains. §5.8's whole point is
## that an undo brings the level back, and a stale reason would have the banner
## explaining an ending that has been taken back.
func test_the_reason_is_cleared_by_recovering() -> void:
	var short := Fixtures.fixed_level(["NE"] as Array[String])
	var state := GameState.start(short)
	assert_true(state.place(state.legal_targets()[0]))
	assert_ne(state.dead_reason, GameState.Dead.NONE)

	assert_true(state.undo())
	assert_eq(state.status, GameState.Status.PLAYING)
	assert_eq(state.dead_reason, GameState.Dead.NONE, "the ending was taken back")


## The board draws the edge a placement would cross, and `anchor_of` is what it
## asks. So the contract that matters is not what the function returns on its own —
## it is that the move then *actually comes from there*. A view promising one edge
## while the commit takes another would have the board lying about where the line
## is going, which is worse than saying nothing.
func test_anchor_of_names_the_cell_the_move_really_comes_from() -> void:
	var state := GameState.start(Fixtures.fixed_level(
		["NE", "NE", "E", "E", "E"] as Array[String]))
	for _i: int in range(2):
		assert_true(state.place(state.legal_targets()[0]))

	var targets: Array[Vector3i] = state.legal_targets()
	assert_gt(targets.size(), 1, "a fork is the case worth checking")
	for target: Vector3i in targets:
		var predicted: Vector3i = state.anchor_of(target)
		assert_true(state.path.has(predicted), "%s is entered from off the path" % target)

		var probe := GameState.start(Fixtures.fixed_level(
			["NE", "NE", "E", "E", "E"] as Array[String]))
		for _i: int in range(2):
			probe.place(probe.legal_targets()[0])
		assert_true(probe.place(target))
		var edge: Array = probe.edges[probe.edges.size() - 1]
		assert_eq(edge[0], predicted,
			"%s was promised an entry from %s and took one from %s"
				% [target, predicted, edge[0]])

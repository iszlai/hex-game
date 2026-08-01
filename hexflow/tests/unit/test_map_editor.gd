## @core — Scenario: The map editor draws a board that the game can load
## (MAP-EDITOR §4, §5, §6).
##
## The editor is a developer tool and never ships, which is an argument for
## testing it *more* rather than less: nobody plays it, so nothing else notices
## when it goes wrong. What it writes goes into frozen campaign data, and the
## property test that would catch a bad level runs later, in CI, after the commit.
##
## The UI is not under test here — the model, the constraints and the two refusals
## are. A brush that paints the wrong cell is a bug an author sees immediately; a
## draft that quietly loses a portal's twin is not.
extends GutTest

const START := Vector3i(-2, 0, 2)
const GOAL := Vector3i(2, 0, -2)


func _hexagon(radius: int = 2) -> MapDraft:
	var draft := MapDraft.new()
	draft.apply_shape("hexagon", radius, 0)
	draft.set_content(START, MapDraft.Content.START)
	draft.set_content(GOAL, MapDraft.Content.GOAL)
	return draft


# --- §4.1, the two brushes ------------------------------------------------------

func test_the_board_brush_adds_and_removes_cells() -> void:
	var draft := _hexagon()
	var outside := Vector3i(3, 0, -3)
	assert_false(draft.has(outside))
	assert_true(draft.add_cell(outside), "painting on adds the cell")
	assert_true(draft.has(outside))
	assert_true(draft.remove_cell(outside), "painting off removes it")
	assert_false(draft.has(outside))


## A goal painted into empty space would be an invisible edit — the cell is not
## there to carry it. Refused rather than silently adding the cell, because an
## author who wanted the cell has a brush for that.
func test_contents_cannot_be_painted_off_the_board() -> void:
	var draft := _hexagon()
	assert_false(draft.set_content(Vector3i(4, 0, -4), MapDraft.Content.GOAL))
	assert_eq(draft.content_at(Vector3i(4, 0, -4)), MapDraft.Content.EMPTY)


func test_removing_a_cell_takes_its_contents_with_it() -> void:
	var draft := _hexagon()
	draft.remove_cell(GOAL)
	assert_eq(draft.goals(), [] as Array[Vector3i], "the goal went with the cell")
	assert_string_contains(", ".join(draft.problems()), "no goal")


# --- §4.2, the constraints enforced while drawing --------------------------------

## The solver's path mask is 64 bits (C-19), so sixty-one is not a guideline.
## Refused at the brush rather than reported at Validate: a board over the line
## cannot be built at all, so there would be nothing to report on.
func test_painting_past_sixty_one_cells_is_refused() -> void:
	var draft := MapDraft.new()
	draft.apply_shape("hexagon", 4, 0)
	assert_eq(draft.count(), Hex.MAX_CELLS, "a radius-4 hexagon is exactly the ceiling")
	assert_true(draft.at_ceiling())
	assert_false(draft.add_cell(Vector3i(5, 0, -5)), "and nothing may be added to it")
	assert_eq(draft.count(), Hex.MAX_CELLS)


## Placing a second start *moves* the first. Refusing would mean an author who
## wanted the start elsewhere had to erase before they could draw, which is a rule
## nobody remembers halfway through a board.
func test_a_second_start_moves_the_first() -> void:
	var draft := _hexagon()
	var elsewhere := Vector3i(0, 2, -2)
	draft.set_content(elsewhere, MapDraft.Content.START)
	assert_eq(draft.start, elsewhere)
	assert_eq(draft.content_at(START), MapDraft.Content.EMPTY, "the old start is cleared")
	assert_eq(draft.cells_of(MapDraft.Content.START).size(), 1)


func test_a_lone_portal_is_flagged_until_its_twin_arrives() -> void:
	var draft := _hexagon()
	draft.set_content(Vector3i(0, 1, -1), MapDraft.Content.PORTAL)
	assert_string_contains(", ".join(draft.problems()), "no twin")
	assert_eq(draft.complete_portals().size(), 0, "a half-drawn door never reaches the board")

	draft.set_content(Vector3i(0, -1, 1), MapDraft.Content.PORTAL)
	assert_eq(draft.problems(), [] as Array[String], "the pair closes")
	assert_eq(draft.complete_portals().size(), 1)
	assert_eq(draft.portal_index(Vector3i(0, 1, -1)), draft.portal_index(Vector3i(0, -1, 1)),
		"both ends of one door carry the same number")


func test_erasing_one_end_reopens_the_pair() -> void:
	var draft := _hexagon()
	draft.set_content(Vector3i(0, 1, -1), MapDraft.Content.PORTAL)
	draft.set_content(Vector3i(0, -1, 1), MapDraft.Content.PORTAL)
	draft.clear_content(Vector3i(0, 1, -1))
	assert_string_contains(", ".join(draft.problems()), "no twin")


## Cutting a board in two is a real mistake and never an intent. Flagged rather
## than refused, because it is also what every board looks like one stroke into
## being drawn.
func test_a_board_in_two_pieces_is_flagged() -> void:
	var draft := _hexagon()
	draft.add_cell(Vector3i(4, 0, -4))
	assert_string_contains(", ".join(draft.problems()), "more than one piece")
	draft.remove_cell(Vector3i(4, 0, -4))
	assert_eq(draft.problems(), [] as Array[String])


# --- crossing to the game's types -------------------------------------------------

func test_a_draft_becomes_a_level_the_game_can_load() -> void:
	var draft := _hexagon()
	draft.set_content(Vector3i(0, 0, 0), MapDraft.Content.WALL)
	draft.tiles = [Direction.NE, Direction.E] as Array[int]
	var level := draft.to_level()
	assert_not_null(level)
	assert_eq(level.board.start, START)
	assert_eq(level.board.goals, [GOAL] as Array[Vector3i])
	assert_true(level.board.is_wall(Vector3i.ZERO))
	assert_eq(level.board.size(), Hex.cell_count(2))
	assert_eq(level.validate(), [] as Array[String])


func test_a_draft_with_no_start_has_no_level() -> void:
	var draft := MapDraft.new()
	draft.apply_shape("hexagon", 2, 0)
	assert_null(draft.to_level(), "there is nothing to flag as the start")


## Editing a level keeps its uid (§7.1, C-34): it is the same level with a wall
## moved, and its stars belong to it. Only the sweep mints a new one, because the
## sweep produces a different level at that slot.
func test_loading_and_editing_a_level_keeps_its_uid() -> void:
	LevelRepository.clear_cache()
	var original := LevelRepository.load_level(1, 1)
	assert_not_null(original)
	if original == null:
		return
	var draft := MapDraft.from_level(original)
	assert_eq(draft.uid, original.uid)
	draft.set_content(draft.goals()[0] + Direction.delta(Direction.NW), MapDraft.Content.WALL)
	assert_eq(draft.to_level().uid, original.uid, "a wall moved, not a new level")


func test_a_shipped_level_round_trips_through_the_draft() -> void:
	LevelRepository.clear_cache()
	var original := LevelRepository.load_level(4, 7)
	assert_not_null(original)
	if original == null:
		return
	var rebuilt := MapDraft.from_level(original).to_level()
	assert_eq(rebuilt.board.cells(), original.board.cells())
	assert_eq(rebuilt.board.start, original.board.start)
	assert_eq(rebuilt.board.goals, original.board.goals)
	assert_eq(rebuilt.board.walls(), original.board.walls())
	assert_eq(rebuilt.board.portal_pairs(), original.board.portal_pairs())
	assert_eq(rebuilt.board.cells_with_flag(Board.F_GATE),
		original.board.cells_with_flag(Board.F_GATE))
	assert_eq(rebuilt.tiles, original.tiles)


## The board a `shape` names still writes as three numbers after a trip through
## the editor. If this breaks, every level opened and saved unchanged grows sixty
## lines of coordinates.
func test_an_unedited_shape_still_saves_as_three_numbers() -> void:
	var draft := _hexagon(3)
	assert_true(draft.to_level().board.is_named_shape())
	draft.remove_cell(Vector3i(1, -1, 0))
	assert_false(draft.to_level().board.is_named_shape(), "one cell out and it is a drawing")


# --- §4.4, the tile sequence -------------------------------------------------------

func test_the_sequence_field_rejects_a_typo() -> void:
	var good: Array = TileFiller.parse("NE E  sw")
	assert_eq(good[0], [Direction.NE, Direction.E, Direction.SW] as Array[int])
	assert_eq(str(good[1]), "", "no complaint about a sequence that parsed")

	var bad: Array = TileFiller.parse("NE NORTH E")
	assert_null(bad[0], "one bad token rejects the whole field")
	assert_string_contains(str(bad[1]), "NORTH")


func test_the_sequence_survives_a_round_trip_through_its_text() -> void:
	var tiles: Array[int] = [Direction.NW, Direction.SE, Direction.W]
	assert_eq(TileFiller.parse(TileFiller.to_text(tiles))[0], tiles)


## Fill's whole job: a board plus a deal is a level, and a board plus the wrong
## deal is an unsolvable one. The deal it keeps must survive the solver.
func test_fill_produces_a_deal_the_solver_can_win() -> void:
	var draft := _hexagon()
	draft.chapter = 1
	draft.index = 1
	var deal := TileFiller.try_seed(draft, 0, 1 << 30)
	assert_not_null(deal, "a plain hexagon with one goal should fill on the first seed")
	if deal == null:
		return
	assert_gt(deal.tiles.size(), 0)
	assert_gt(deal.par, 0)
	assert_gte(deal.routes, 0, "an unrankable deal is rejected, not kept")
	assert_gte(deal.forgiving, 0)

	var level := draft.to_level()
	level.tiles = deal.tiles
	assert_true(Solver.solve(level).is_solvable(), "the deal Fill kept is winnable")


## Re-running Fill on an unchanged board must reproduce the same deals, or
## `generator.seed` records nothing and §10 Q4's answer is wrong.
func test_fill_is_reproducible_from_its_seed() -> void:
	var draft := _hexagon()
	var first := TileFiller.try_seed(draft, 0, 1 << 30)
	var second := TileFiller.try_seed(draft, 0, 1 << 30)
	assert_not_null(first)
	if first == null:
		return
	assert_eq(second.seed, first.seed)
	assert_eq(second.tiles, first.tiles)


## Replays a carved route from the start and returns every cell it stands on.
## Only meaningful for a single-goal board, where the route is one leg from the
## start — a second goal forks from wherever the trunk is nearest, so its
## directions do not continue the first leg's line.
func _cells_along(draft: MapDraft, route: Array[int]) -> Array[Vector3i]:
	var out: Array[Vector3i] = [draft.start]
	var at: Vector3i = draft.start
	for dir: int in route:
		at += Direction.delta(dir)
		out.append(at)
	return out


## The carve's walk only ever steps closer to the goal or sideways, which is what
## keeps a route from doubling back and looking generated — and is why a board
## whose way round starts by going the *wrong* way can corner it. Every seed is
## cornered in the same place, so a board like this used to fail all ten and
## report "no deal made this board solvable" about a board with an obvious route.
func test_a_cornered_walk_finishes_the_long_way_round_instead_of_giving_up() -> void:
	var draft := MapDraft.new()
	draft.apply_shape("hexagon", 2, 0)
	draft.set_content(Vector3i(0, 0, 0), MapDraft.Content.START)
	draft.set_content(Vector3i(2, 0, -2), MapDraft.Content.GOAL)
	# Every neighbour of the start that is closer to the goal, or level with it.
	# What is left all leads away, which is what the walk will not do.
	for c: Vector3i in [Vector3i(1, 0, -1), Vector3i(0, 1, -1), Vector3i(1, -1, 0)]:
		draft.set_content(c, MapDraft.Content.WALL)

	for seed_value: int in [0, 1, 7, 99]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var route := TileFiller.carve(draft, rng, 0)
		assert_false(route.is_empty(), "seed %d found no route round the walls" % seed_value)
		var cells := _cells_along(draft, route)
		assert_eq(cells[cells.size() - 1], Vector3i(2, 0, -2), "the route ends on the goal")
		for c: Vector3i in cells:
			assert_true(draft.has(c), "the route left the board at %v" % c)
			assert_ne(draft.content_at(c), MapDraft.Content.WALL, "the route crossed a wall at %v" % c)

	# And end to end, which is the claim an author cares about: Fill has a deal for
	# a board it used to have nothing to say about.
	var deal := TileFiller.try_seed(draft, 0, 1 << 30)
	assert_not_null(deal, "Fill still refuses the board")
	if deal != null:
		var level := draft.to_level()
		level.tiles = deal.tiles
		assert_true(Solver.solve(level).is_solvable(), "and the deal it keeps is winnable")


## A goal an earlier leg already walked over is done, not a leg of length zero.
## The walk was asked to go from the goal to the goal, returned nothing because
## there was nothing to do, and the empty leg was read as a failure — so a board
## whose first route crossed its second goal could not be filled at all.
##
## The route to (2,0,-2) is forced: from the start it is the only line that never
## steps away from it, and it runs straight over the second goal at the centre.
func test_a_goal_the_route_already_crossed_does_not_fail_the_carve() -> void:
	var draft := MapDraft.new()
	draft.apply_shape("hexagon", 2, 0)
	draft.set_content(START, MapDraft.Content.START)
	draft.set_content(Vector3i(2, 0, -2), MapDraft.Content.GOAL)
	draft.set_content(Vector3i(0, 0, 0), MapDraft.Content.GOAL)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var route := TileFiller.carve(draft, rng, 0)
	assert_eq(route, [Direction.NE, Direction.NE, Direction.NE, Direction.NE] as Array[int],
		"one line covers both goals, and the second leg has nothing to add")


## The carve routes around a gate rather than through it: §6's gate needs two path
## neighbours before it opens, and a single-file route arrives with one.
func test_the_carve_avoids_gates() -> void:
	var draft := _hexagon()
	for c: Vector3i in [Vector3i(-1, 0, 1), Vector3i(-1, 1, 0), Vector3i(-2, 1, 1)]:
		draft.set_content(c, MapDraft.Content.GATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var route := TileFiller.carve(draft, rng, 0)
	var at := draft.start
	for dir: int in route:
		at += Direction.delta(dir)
		assert_ne(draft.content_at(at), MapDraft.Content.GATE,
			"the carved route stepped onto a gate at %v" % at)


# --- §4.4, the traced sequence ------------------------------------------------------

## The four steps from the start to the goal of a radius-2 hexagon, which is the
## straight NE line between them.
func _trace_to_goal(draft: MapDraft) -> void:
	var at: Vector3i = draft.start
	for _i: int in range(4):
		at += Direction.delta(Direction.NE)
		assert_eq(draft.trace_step(at), "", "step onto %v was refused" % at)


## The point of the mode: what was drawn *is* the sequence, with no sweep in
## between and nothing to go stale.
func test_a_traced_route_becomes_the_sequence() -> void:
	var draft := _hexagon()
	_trace_to_goal(draft)
	assert_eq(draft.tiles, [Direction.NE, Direction.NE, Direction.NE, Direction.NE] as Array[int])
	assert_false(draft.tiles_stale, "a route drawn on this board is not stale on it")
	assert_eq(draft.trace_goals_left(), 0, "the route reached the goal")


## Why the mode exists at all. Fill sweeps ten seeded random walks and every one
## of them can dead-end, and on a tight board they all do — a traced route cannot,
## because it is a legal play that has already been played.
func test_a_traced_route_is_a_sequence_the_solver_can_win() -> void:
	var draft := _hexagon()
	_trace_to_goal(draft)
	var level := draft.to_level()
	assert_not_null(level)
	assert_true(Solver.solve(level).is_solvable(), "the route drawn is a route that can be played")


## Every refusal is one of [Rules]' own, said out loud. A tile is laid against a
## cell the path already has (§5.4), never into open space.
func test_a_step_must_touch_the_route() -> void:
	var draft := _hexagon()
	var far := Vector3i(2, -2, 0)
	assert_string_contains(draft.trace_step(far), "does not touch the route")
	assert_true(draft.trace.is_empty(), "a refused step is not taken")


func test_a_step_cannot_land_on_a_wall_or_off_the_board() -> void:
	var draft := _hexagon()
	var next := START + Direction.delta(Direction.NE)
	draft.set_content(next, MapDraft.Content.WALL)
	assert_string_contains(draft.trace_step(next), "is a wall")
	assert_string_contains(draft.trace_step(Vector3i(9, 0, -9)), "not on the board")


func test_a_step_cannot_double_back_onto_the_route() -> void:
	var draft := _hexagon()
	_trace_to_goal(draft)
	assert_string_contains(draft.trace_step(START + Direction.delta(Direction.NE)),
		"already there")


## §6's gate needs two path neighbours before it opens, so a route that walks
## straight into one is describing a move the game would not accept.
func test_a_gate_is_refused_until_the_route_reaches_it_twice() -> void:
	var draft := _hexagon()
	var gate := START + Direction.delta(Direction.NE)
	draft.set_content(gate, MapDraft.Content.GATE)
	assert_string_contains(draft.trace_step(gate), "gate")
	# Round its other side first, which leaves the gate with two path neighbours.
	assert_eq(draft.trace_step(START + Direction.delta(Direction.E)), "")
	assert_eq(draft.trace_step(gate), "", "the gate opens on the second approach")


## §5.5.3 — stepping on a portal joins its twin at the same moment, so the next
## tile may be laid at the far end. A route that could not do that would be
## drawing a different game from the one the level is played in.
func test_stepping_on_a_portal_carries_the_route_to_its_twin() -> void:
	var draft := _hexagon()
	var near := START + Direction.delta(Direction.NE)
	var far := Vector3i(2, -1, -1)
	draft.set_content(near, MapDraft.Content.PORTAL)
	draft.set_content(far, MapDraft.Content.PORTAL)
	assert_eq(draft.trace_step(near), "")
	assert_true(draft.on_path(far), "the twin joined without being clicked")
	assert_eq(draft.trace_step(GOAL), "", "the next tile is laid from the far end")
	assert_eq(draft.tiles.size(), 2, "the teleport is not a tile — only the two steps are")


func test_taking_a_step_back_shortens_the_sequence() -> void:
	var draft := _hexagon()
	_trace_to_goal(draft)
	assert_true(draft.undo_trace())
	assert_eq(draft.tiles.size(), 3)
	assert_eq(draft.trace_goals_left(), 1, "the goal is out again")
	assert_false(draft.on_path(GOAL))


func test_taking_a_step_back_from_nothing_does_nothing() -> void:
	assert_false(_hexagon().undo_trace())


## The board can move under a route — painting a wall across one is exactly the
## edit §4.3 wants to allow. The prefix up to the wall is still a legal play, so
## it is kept and the rest goes.
func test_the_route_is_replayed_against_the_board_as_it_is_now() -> void:
	var draft := _hexagon()
	_trace_to_goal(draft)
	draft.set_content(START + Direction.delta(Direction.NE) * 3, MapDraft.Content.WALL)
	assert_eq(draft.revalidate_trace(), 2, "the wall and the step past it")
	assert_eq(draft.tiles, [Direction.NE, Direction.NE] as Array[int])


## Fill and the text field both produce a sequence the route did not, and a line
## left on the canvas under a sequence it does not describe is the canvas lying.
func test_clearing_the_route_leaves_the_sequence_alone() -> void:
	var draft := _hexagon()
	_trace_to_goal(draft)
	var traced: Array[int] = draft.tiles.duplicate()
	draft.clear_trace()
	assert_true(draft.trace.is_empty())
	assert_eq(draft.tiles, traced, "the tiles are the level's; the route was only how they got there")


# --- §5 and §6, validate and the refusal --------------------------------------------

func test_validate_will_not_pass_a_board_with_no_sequence() -> void:
	var draft := _hexagon()
	var report := MapReport.of(draft)
	assert_false(report.ok)
	assert_string_contains(", ".join(report.problems), "no tile sequence")


func test_validate_will_not_pass_an_unsolvable_sequence() -> void:
	var draft := _hexagon()
	# Six steps west from a start on the western rim: every one of them leaves the
	# board, so nothing can ever be placed.
	draft.tiles = [Direction.W, Direction.W, Direction.W, Direction.W] as Array[int]
	var report := MapReport.of(draft)
	assert_false(report.ok)
	assert_string_contains(", ".join(report.problems), "no route")


func test_validate_will_not_pass_a_board_missing_its_start() -> void:
	var draft := MapDraft.new()
	draft.apply_shape("hexagon", 2, 0)
	draft.set_content(GOAL, MapDraft.Content.GOAL)
	var report := MapReport.of(draft)
	assert_false(report.ok)
	assert_string_contains(", ".join(report.problems), "start")


## §6: the one thing this tool must never do is put an unsolvable level into
## frozen data, because the property test that would catch it runs later, in CI,
## after the commit. So a failed report has no level to write, rather than a
## warning next to a working Save button.
func test_a_failed_report_has_nothing_to_stamp() -> void:
	var draft := _hexagon()
	var report := MapReport.of(draft)
	assert_false(report.ok)
	assert_null(report.stamp(draft), "there is no level to write")


## What a passing report stamps is what **it** measured, not a fresh measurement:
## that is what makes a hand-drawn level carry the same authoring record as a
## swept one, and what lets CI's curve check cover both.
func test_a_passing_report_stamps_what_it_measured() -> void:
	LevelRepository.clear_cache()
	var original := LevelRepository.load_level(1, 1)
	assert_not_null(original)
	if original == null:
		return
	var draft := MapDraft.from_level(original)
	var report := MapReport.of(draft)
	assert_true(report.ok)

	var stamped := report.stamp(draft)
	assert_eq(stamped.par, report.par)
	assert_eq(stamped.authored_routes, report.routes)
	assert_eq(stamped.authored_forgiving, report.forgiving)
	assert_eq(stamped.solution_script.size(), report.solution_script.size())
	assert_eq(stamped.uid, original.uid, "and it is still the same level")


## The whole point of the tool: what it writes has to survive the loader that CI
## runs over the frozen campaign. Written to `user://`, because a test that wrote
## into `src/data/levels/` would overwrite a shipped level with a fixture.
func test_a_saved_level_reloads_and_reverifies() -> void:
	LevelRepository.clear_cache()
	var original := LevelRepository.load_level(2, 3)
	assert_not_null(original)
	if original == null:
		return
	var draft := MapDraft.from_level(original)
	var report := MapReport.of(draft)
	assert_true(report.ok, ", ".join(report.problems))

	var path := "user://test_map_editor_save.json"
	assert_true(LevelFile.write(report.stamp(draft), path))

	var reloaded := LevelRepository.from_dict(
		JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary)
	assert_not_null(reloaded)
	assert_eq(LevelRepository.verify(reloaded), [] as Array[String],
		"a saved level passes the check the property test runs on every push")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A board drawn by hand — cells removed — must survive the same trip. This is
## where the `cells` field and the editor meet, and where a silent loss would
## produce a level that is solvable in the editor and not on disk.
func test_a_hand_drawn_board_survives_being_saved() -> void:
	LevelRepository.clear_cache()
	var original := LevelRepository.load_level(1, 6)
	assert_not_null(original)
	if original == null:
		return
	var draft := MapDraft.from_level(original)
	# Cut a corner off, somewhere the route does not go: a rim cell that is not
	# the start, a goal or on the stored solution.
	var removed := Hex.NONE
	for c: Vector3i in original.board.cells():
		if Hex.length(c) == original.board.radius and draft.content_at(c) == MapDraft.Content.EMPTY \
				and not original.solution.has(c):
			removed = c
			break
	assert_ne(removed, Hex.NONE, "the fixture needs a spare rim cell")
	draft.remove_cell(removed)

	var report := MapReport.of(draft)
	if not report.ok:
		# Cutting a cell can genuinely break a level; that is the editor working,
		# not the test failing. What must not happen is a silent pass.
		assert_gt(report.problems.size(), 0, "a broken board says why")
		return
	var path := "user://test_map_editor_drawn.json"
	assert_true(LevelFile.write(report.stamp(draft), path))
	var text := FileAccess.get_file_as_string(path)
	assert_string_contains(text, "\"cells\"")

	var reloaded := LevelRepository.from_dict(JSON.parse_string(text) as Dictionary)
	assert_false(reloaded.board.has(removed), "the hole is still a hole")
	assert_eq(LevelRepository.verify(reloaded), [] as Array[String])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- §6.1, drafts ------------------------------------------------------------------

## §6's refusal follows the destination, not the button. If Save-as could aim at
## `chapter_3/level_07.json` it would be a way *around* the guard rather than an
## alternative to it, so the guard has to recognise the sixty by path.
func test_the_campaign_tree_is_recognised_by_path() -> void:
	assert_true(LevelFile.is_campaign_path(LevelRepository.path_for(3, 7)))
	assert_true(LevelFile.is_campaign_path("res://src/data/levels/chapter_1/level_01.json"))
	assert_false(LevelFile.is_campaign_path(LevelFile.DRAFT_DIR + "/idea.json"))
	assert_false(LevelFile.is_campaign_path("user://scratch.json"))
	assert_false(LevelFile.is_campaign_path("/tmp/elsewhere/level_01.json"))


## A draft is not one of the sixty, so it is not frozen data, so it does not have
## to be finished. It only needs a start — without one there is no [Level] to
## serialise at all.
func test_an_unfinished_board_can_still_be_written_as_a_draft() -> void:
	var draft := _hexagon()
	assert_eq(draft.tiles, [] as Array[int], "no sequence: this would fail Validate")
	assert_false(MapReport.of(draft).ok)

	var path := "user://test_map_editor_draft.json"
	var level := draft.to_level()
	assert_not_null(level, "a start is all a draft needs")
	assert_true(LevelFile.write(level, path))

	var reloaded := LevelFile.read(path)
	assert_eq(reloaded.board.start, draft.start)
	assert_eq(reloaded.board.goals, draft.goals())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The thirty-second constraint, stated: a board with nothing on it is not a
## level and there is nothing to write.
func test_a_board_with_no_start_is_not_a_draft_either() -> void:
	var bare := MapDraft.new()
	bare.apply_shape("hexagon", 2, 0)
	assert_null(bare.to_level())


## Promoting a draft into a slot keeps its name, so a board that was played as a
## draft does not hand its stars to whatever it replaces (C-34).
func test_promoting_a_draft_keeps_its_name() -> void:
	var draft := _hexagon()
	draft.uid = "draftname1"
	draft.chapter = 2
	draft.index = 5
	var level := draft.to_level()
	assert_eq(level.uid, "draftname1")
	assert_eq(level.id, LevelRepository.id_for(2, 5), "but it takes the slot's id")


## Solvable is the floor, not the result. The curve numbers are the point and are
## reported whether or not the author asked for them (§5).
func test_validate_scores_a_shipped_level_against_its_slot() -> void:
	LevelRepository.clear_cache()
	var original := LevelRepository.load_level(1, 1)
	assert_not_null(original)
	if original == null:
		return
	var report := MapReport.of(MapDraft.from_level(original))
	assert_true(report.ok, "a shipped level validates: %s" % ", ".join(report.problems))
	assert_eq(report.par, original.par, "and reproduces its stored ideal")
	assert_gte(report.routes, 0)
	assert_gte(report.forgiving, 0)
	assert_gte(report.distance, 0, "the distance from the curve is always reported")
	assert_string_contains(report.summary(), "slot wants")

## @core — Scenario: A board may be drawn rather than named (MAP-EDITOR §4.3).
##
## The map editor lets an author add and remove cells, and a board that has been
## cut about is not describable in the three numbers — `shape`, `radius`,
## `shape_arg` — that every level file has used until now. So the schema gains an
## optional `cells` list which, when present, **is** the board.
##
## The two halves this guards are the ones that would rot quietly:
##
##   * a swept board must keep costing three numbers, or the sixty frozen files
##     grow sixty lines of coordinates each on the next `make levels` and every
##     diff becomes unreadable;
##   * a hand-drawn board must round-trip *exactly*, because a cell silently
##     dropped on load is a hole in a board the solver already proved solvable.
extends GutTest


func _drawn(cells: Array[Vector3i], start: Vector3i, goal: Vector3i) -> Level:
	var level := Level.build(
		Board.build(3, start, [goal] as Array[Vector3i], [], [], [], [], "hexagon", 0, cells),
		[Direction.NE] as Array[int]
	)
	level.id = "drawn"
	level.uid = "drawn00000"
	return level


## A hexagon with its middle cell taken out — the smallest edit that no shape in
## `Hex.SHAPES` produces, and the one a wall cannot fake.
func _hexagon_with_a_hole() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for c: Vector3i in Hex.hexagon(3):
		if c != Vector3i.ZERO:
			cells.append(c)
	return cells


func test_an_explicit_cell_list_is_the_board() -> void:
	var cells := _hexagon_with_a_hole()
	var board := Board.build(
		3, Vector3i(-3, 0, 3), [Vector3i(3, 0, -3)] as Array[Vector3i],
		[], [], [], [], "hexagon", 0, cells
	)
	assert_eq(board.size(), Hex.cell_count(3) - 1, "the removed cell is gone")
	assert_false(board.has(Vector3i.ZERO), "and it is not on the board")
	assert_eq(board.radius, 3, "the bounding radius still comes from the cells")


func test_an_empty_cell_list_still_builds_the_named_shape() -> void:
	var board := Board.build(
		3, Vector3i(-3, 0, 3), [Vector3i(3, 0, -3)] as Array[Vector3i],
		[], [], [], [], "ring", 1
	)
	assert_eq(board.cells(), Hex.shape("ring", 3, 1), "every caller that predates cells is unchanged")
	assert_true(board.is_named_shape())


## Duplicates are the failure mode of a list assembled by hand or by a paint
## stroke: `size()` is what the solver's 61-cell ceiling is checked against, and a
## cell counted twice would put a board over the line that is not over it.
func test_a_repeated_cell_is_counted_once() -> void:
	var cells: Array[Vector3i] = Hex.hexagon(2)
	cells.append(Vector3i.ZERO)
	cells.append(Vector3i(1, -1, 0))
	var board := Board.build(
		2, Vector3i(-2, 0, 2), [Vector3i(2, 0, -2)] as Array[Vector3i],
		[], [], [], [], "hexagon", 0, cells
	)
	assert_eq(board.size(), Hex.cell_count(2))
	assert_true(board.is_named_shape(), "and it is still exactly the hexagon it names")


func test_a_swept_board_is_written_as_three_numbers() -> void:
	LevelRepository.clear_cache()
	var level := LevelRepository.load_level(1, 1)
	assert_not_null(level, "chapter 1 level 1 is shipped data")
	if level == null:
		return
	assert_false(LevelRepository.to_dict(level).has("cells"),
		"a board that is exactly its shape must not list its cells")


func test_a_drawn_board_is_written_and_read_back_cell_for_cell() -> void:
	var level := _drawn(_hexagon_with_a_hole(), Vector3i(-3, 0, 3), Vector3i(3, 0, -3))
	var d := LevelRepository.to_dict(level)
	assert_true(d.has("cells"), "a board that diverges from its shape lists its cells")

	# Through real JSON, because that is the trip the file actually takes and
	# `Hex.from_array` has to cope with the floats `JSON.parse_string` hands back.
	var reloaded := LevelRepository.from_dict(
		JSON.parse_string(JSON.stringify(d)) as Dictionary
	)
	assert_eq(reloaded.board.cells(), level.board.cells())
	assert_false(reloaded.board.has(Vector3i.ZERO), "the hole survives the round trip")
	assert_eq(reloaded.board.start, level.board.start)
	assert_eq(reloaded.board.goals, level.board.goals)


## `shape` stays in the file, and stays meaningful: it says what the author
## started from. What it must *not* do is override the cells.
func test_the_shape_survives_as_a_label() -> void:
	var level := _drawn(_hexagon_with_a_hole(), Vector3i(-3, 0, 3), Vector3i(3, 0, -3))
	var reloaded := LevelRepository.from_dict(LevelRepository.to_dict(level))
	assert_eq(reloaded.board.shape, "hexagon", "still says where it came from")
	assert_false(reloaded.board.is_named_shape(), "but is not that shape any more")


## The structural checks still apply to a drawn board — this is where an author's
## mistake has to surface, since there is no shape function guaranteeing anything.
func test_a_drawn_board_still_validates_its_start_and_goals() -> void:
	var cells := _hexagon_with_a_hole()
	var level := _drawn(cells, Vector3i.ZERO, Vector3i(3, 0, -3))
	assert_string_contains(", ".join(level.validate()), "start")

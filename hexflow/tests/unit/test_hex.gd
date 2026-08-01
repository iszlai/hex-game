## @core — coordinate algebra (§4).
extends GutTest


func test_board_sizes_match_the_formula() -> void:
	assert_eq(Hex.cell_count(2), 19)
	assert_eq(Hex.cell_count(3), 37)
	assert_eq(Hex.cell_count(4), 61)
	assert_eq(Hex.hexagon(2).size(), 19)
	assert_eq(Hex.hexagon(3).size(), 37)
	assert_eq(Hex.hexagon(4).size(), 61)


func test_every_generated_cell_satisfies_the_cube_invariant() -> void:
	for c: Vector3i in Hex.hexagon(4):
		assert_true(Hex.is_valid(c), "%v must satisfy x + y + z == 0" % c)
		assert_true(Hex.length(c) <= 4, "%v must lie within radius 4" % c)


## Appendix A's reference row layout: 4, 5, 6, 7, 6, 5, 4 from z = +3 up to z = -3.
func test_radius_three_rows_match_the_reference_board() -> void:
	var counts: Dictionary = {}
	for c: Vector3i in Hex.hexagon(3):
		counts[c.z] = int(counts.get(c.z, 0)) + 1
	assert_eq([counts[3], counts[2], counts[1], counts[0], counts[-1], counts[-2], counts[-3]],
		[4, 5, 6, 7, 6, 5, 4])


func test_start_and_goal_are_six_apart() -> void:
	assert_eq(Hex.distance(Fixtures.START, Fixtures.GOAL), 6)


func test_distance_is_symmetric_and_zero_on_itself() -> void:
	var a := Vector3i(2, -1, -1)
	var b := Vector3i(-1, 2, -1)
	assert_eq(Hex.distance(a, b), Hex.distance(b, a))
	assert_eq(Hex.distance(a, a), 0)


func test_neighbours_are_all_distance_one_and_distinct() -> void:
	var seen: Dictionary = {}
	for n: Vector3i in Hex.neighbours(Vector3i.ZERO):
		assert_eq(Hex.distance(Vector3i.ZERO, n), 1)
		assert_false(seen.has(n), "neighbours must be distinct")
		seen[n] = true
	assert_eq(seen.size(), 6)


func test_ring_sizes() -> void:
	assert_eq(Hex.ring(0).size(), 1)
	assert_eq(Hex.ring(1).size(), 6)
	assert_eq(Hex.ring(3).size(), 18)
	for c: Vector3i in Hex.ring(3):
		assert_eq(Hex.length(c), 3)


func test_sort_cells_is_stable_and_total() -> void:
	var a: Array[Vector3i] = Hex.hexagon(3)
	var b: Array[Vector3i] = a.duplicate()
	b.reverse()
	assert_eq(Hex.sort_cells(a), Hex.sort_cells(b))


func test_round_trips_through_json_arrays() -> void:
	var c := Vector3i(-3, 0, 3)
	assert_eq(Hex.from_array(Hex.to_array(c)), c)


# --- board shapes (C-32) ------------------------------------------------------

## Every shape is a set of valid cube cells, connected, inside the solver's
## ceiling, and in the canonical order everything else on the board relies on.
## Asserted as a family rather than one shape at a time, because the way a new
## shape goes wrong is by being *nearly* right — a stray cell off the plane, or a
## silhouette in two pieces with a goal stranded in the far one.
func test_every_shape_is_a_legal_connected_board() -> void:
	var shapes: Dictionary = {
		"hexagon": Hex.hexagon(3),
		"triangle": Hex.triangle(9),
		"ring": Hex.ring_board(4, 1),
		"corridor": Hex.corridor(14, 3),
		"hourglass": Hex.hourglass(4, 3),
		"star": Hex.star(4),
	}
	for name: Variant in shapes:
		var cells: Array[Vector3i] = shapes[name]
		assert_gt(cells.size(), 12, "%s is too small to play on" % name)
		assert_lte(cells.size(), Hex.MAX_CELLS, "%s exceeds the path mask" % name)
		for c: Vector3i in cells:
			assert_true(Hex.is_valid(c), "%s holds %v, which is off the plane" % [name, c])
		assert_eq(cells, Hex.sort_cells(cells), "%s is not in canonical order" % name)
		assert_eq(_connected_count(cells), cells.size(),
			"%s is not one piece — a goal could be stranded" % name)


## The ceiling is the solver's, not a preference: 61 cells is what a 64-bit mask
## holds (C-19). A shape that quietly returned more would fail inside the solver
## as a wrong answer rather than as an error.
func test_a_shape_may_not_outgrow_the_path_mask() -> void:
	assert_eq(Hex.MAX_CELLS, 61)
	assert_eq(Hex.hexagon(4).size(), 61, "radius 4 is exactly the ceiling")
	assert_lte(Hex.triangle(9).size(), Hex.MAX_CELLS)


## What each shape is *for* is its topology, so that is what is checked rather
## than its cell count — a count would pass for any blob of the right size.
func test_each_shape_has_the_property_it_exists_for() -> void:
	# A triangle has corners a route can be trapped in: cells with two neighbours.
	var corners: int = 0
	for c: Vector3i in Hex.triangle(9):
		if _neighbours_within(c, Hex.triangle(9)) == 2:
			corners += 1
	assert_eq(corners, 3, "a triangle has three corners")

	# A ring has a hole, so its centre is *not* part of the board.
	var ring: Array[Vector3i] = Hex.ring_board(4, 1)
	assert_false(ring.has(Vector3i.ZERO), "the hole is the point of a ring")

	# An hourglass pinches: its middle row is narrower than the one beside it.
	var glass: Array[Vector3i] = Hex.hourglass(4, 3)
	assert_lt(_row_width(glass, 0), _row_width(glass, 1), "the waist is the point")

	# A star is six one-wide arms joined near the middle. Cutting the middle out
	# leaves them as separate pieces — which is the property that makes a route
	# down one arm a commitment. Not the origin alone: two hexes on different axes
	# at distance 1 are still neighbours, so the arms only part from distance 2.
	var star: Array[Vector3i] = Hex.star(4)
	assert_true(star.has(Vector3i.ZERO))
	var arms: Array[Vector3i] = []
	for c: Vector3i in star:
		if Hex.length(c) >= 2:
			arms.append(c)
	assert_eq(_connected_count(arms), 3, "an arm is three cells and stands alone")
	assert_eq(arms.size(), 18, "six arms of three")


func _neighbours_within(c: Vector3i, cells: Array[Vector3i]) -> int:
	var n: int = 0
	for d: int in Direction.ALL:
		if cells.has(c + Direction.delta(d)):
			n += 1
	return n


func _row_width(cells: Array[Vector3i], z: int) -> int:
	var n: int = 0
	for c: Vector3i in cells:
		if c.z == z:
			n += 1
	return n


## Cells reachable from the first one, so a shape in two pieces is caught.
func _connected_count(cells: Array[Vector3i]) -> int:
	if cells.is_empty():
		return 0
	var present: Dictionary = {}
	for c: Vector3i in cells:
		present[c] = true
	var seen: Dictionary = {cells[0]: true}
	var queue: Array[Vector3i] = [cells[0]]
	var head: int = 0
	while head < queue.size():
		var c: Vector3i = queue[head]
		head += 1
		for d: int in Direction.ALL:
			var n: Vector3i = c + Direction.delta(d)
			if present.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen.size()

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

## @core — the Appendix A direction table. This test is the regression guard on
## the one mapping that must never be permuted.
extends GutTest


func test_the_table_matches_appendix_a_exactly() -> void:
	var expected := [
		["NW", "SIDE_A", Vector3i(0, 1, -1), 240, "SE"],
		["NE", "SIDE_B", Vector3i(1, 0, -1), 300, "SW"],
		["E", "SIDE_C", Vector3i(1, -1, 0), 0, "W"],
		["SE", "SIDE_D", Vector3i(0, -1, 1), 60, "NW"],
		["SW", "SIDE_E", Vector3i(-1, 0, 1), 120, "NE"],
		["W", "SIDE_F", Vector3i(-1, 1, 0), 180, "E"],
	]
	assert_eq(Direction.ALL.size(), expected.size())
	for i: int in range(expected.size()):
		var row: Array = expected[i]
		assert_eq(Direction.name_of(i), row[0], "name at index %d" % i)
		assert_eq(Direction.LEGACY_NAMES[i], row[1], "legacy name at index %d" % i)
		assert_eq(Direction.delta(i), row[2], "delta at index %d" % i)
		assert_eq(Direction.bearing_degrees(i), row[3], "bearing at index %d" % i)
		assert_eq(Direction.name_of(Direction.opposite(i)), row[4], "opposite at index %d" % i)


func test_deltas_are_valid_cube_vectors() -> void:
	for d: int in Direction.ALL:
		assert_true(Hex.is_valid(Direction.delta(d)))


func test_opposite_is_an_involution_that_cancels_the_delta() -> void:
	for d: int in Direction.ALL:
		assert_eq(Direction.opposite(Direction.opposite(d)), d)
		assert_eq(Direction.delta(d) + Direction.delta(Direction.opposite(d)), Vector3i.ZERO)


func test_between_recovers_the_direction_and_is_total() -> void:
	for d: int in Direction.ALL:
		var a := Vector3i(0, 0, 0)
		assert_eq(Direction.between(a, a + Direction.delta(d)), d)
	assert_eq(Direction.between(Vector3i.ZERO, Vector3i(2, -2, 0)), Direction.NONE)


func test_from_name_is_case_insensitive_and_rejects_junk() -> void:
	assert_eq(Direction.from_name("ne"), Direction.NE)
	assert_eq(Direction.from_name("NE"), Direction.NE)
	assert_eq(Direction.from_name("SIDE_B"), Direction.NONE)

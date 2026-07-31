## @core — the seeded tile stream (§5.3) and determinism (§19).
extends GutTest


func test_each_bag_of_six_contains_every_direction_exactly_once() -> void:
	var s := TileStream.from_seed(918273)
	for bag: int in range(20):
		var seen: Dictionary = {}
		for i: int in range(6):
			seen[s.at(bag * 6 + i)] = true
		assert_eq(seen.size(), 6, "bag %d must contain all six directions" % bag)


func test_the_same_seed_produces_the_same_sequence() -> void:
	var a := TileStream.from_seed(42)
	var b := TileStream.from_seed(42)
	for i: int in range(120):
		assert_eq(a.at(i), b.at(i), "position %d" % i)


func test_different_seeds_diverge() -> void:
	var a := TileStream.from_seed(1)
	var b := TileStream.from_seed(2)
	var same: int = 0
	for i: int in range(60):
		if a.at(i) == b.at(i):
			same += 1
	assert_lt(same, 60, "two seeds must not produce an identical sequence")


func test_peek_shows_the_next_tiles_without_consuming() -> void:
	var s := TileStream.from_seed(7)
	var preview: Array[int] = s.peek(2)
	assert_eq(s.index, 0)
	assert_eq(preview.size(), 2)
	s.advance()
	assert_eq(s.current(), preview[0])
	assert_eq(s.peek(1)[0], preview[1])


## A fixed queue has a bottom, and the preview has to admit it.
##
## It used to pad the tail with `Direction.NONE` so the array was always the length
## asked for, which pushed the "is this real" question onto every caller and got
## the wrong answer in the one that matters: C-18's pile drew a coin per entry, so
## the stack of upcoming tiles stayed full height right up to the last move of a
## level, and the coins that were not there carried arrows.
func test_the_preview_runs_out_when_the_tiles_do() -> void:
	var s := TileStream.from_tiles([0, 1, 2] as Array[int])
	assert_eq(s.peek(5), [1, 2] as Array[int], "two behind the current one, not five")
	s.advance()
	assert_eq(s.peek(5), [2] as Array[int])
	s.advance()
	assert_eq(s.peek(5), [] as Array[int], "nothing behind the last tile")
	assert_eq(s.peek(5).size(), s.remaining() - 1,
		"the preview and the counter agree about what is left")


## The endless bag has no bottom, so nothing above may shorten it.
func test_an_endless_bag_always_previews_in_full() -> void:
	var s := TileStream.from_seed(4)
	for _i: int in range(200):
		s.advance()
	assert_eq(s.peek(8).size(), 8, "a bag never runs out (§5.3)")
	assert_eq(s.remaining(), -1, "and never reports a count")


func test_rewind_reproduces_the_earlier_tile_exactly() -> void:
	var s := TileStream.from_seed(918273)
	var at_three: int = s.at(3)
	for _i: int in range(30):
		s.advance()
	s.rewind_to(3)
	assert_eq(s.index, 3)
	assert_eq(s.current(), at_three)


func test_a_fixed_sequence_overrides_the_bag_and_can_run_out() -> void:
	var s := TileStream.from_tiles(Fixtures.dirs(["NE", "E"]))
	assert_true(s.is_fixed())
	assert_eq(s.current(), Direction.NE)
	s.advance()
	assert_eq(s.current(), Direction.E)
	s.advance()
	assert_true(s.is_exhausted())
	assert_eq(s.current(), Direction.NONE)


func test_a_bag_stream_is_never_exhausted() -> void:
	var s := TileStream.from_seed(3)
	for _i: int in range(500):
		s.advance()
	assert_false(s.is_exhausted())
	assert_eq(s.remaining(), -1)

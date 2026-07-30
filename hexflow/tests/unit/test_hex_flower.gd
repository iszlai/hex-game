## @core — §9's hex-flower map, as geometry.
##
## The layout table is the design: "a radius-1 hex cluster of 7 + a second row of
## 5", read centre-first. A permutation of it silently renumbers every level on
## the map, so it is asserted the way Appendix A's direction table is — by shape,
## not by eye.
extends GutTest

const BOX := Vector2(1280.0, 656.0)

var _flower: HexFlower = null


func before_each() -> void:
	_flower = HexFlower.new()
	add_child_autofree(_flower)
	_flower.size = BOX
	_flower.bind(_rows(), BOX)


func _rows(stars: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(HexFlower.CELLS.size()):
		out.append({"state": HexFlower.State.OPEN, "stars": stars, "hinted": false})
	return out


func test_the_flower_holds_exactly_one_chapter() -> void:
	assert_eq(HexFlower.CELLS.size(), LevelRepository.LEVELS_PER_CHAPTER,
		"§9 lays out a chapter, so the two counts are the same number twice")


func test_no_two_levels_share_a_cell() -> void:
	var seen: Dictionary = {}
	for cell: Vector3i in HexFlower.CELLS:
		assert_false(seen.has(cell), "%v is used twice" % cell)
		seen[cell] = true
	# Cube coordinates, so every cell sums to zero (§4.1).
	for cell: Vector3i in HexFlower.CELLS:
		assert_eq(cell.x + cell.y + cell.z, 0, "%v is not a cube coordinate" % cell)


## "a radius-1 hex cluster of 7": the first seven are the centre and its whole
## ring, and nothing else.
func test_the_first_seven_are_the_centre_and_its_ring() -> void:
	assert_eq(HexFlower.CELLS[0], Vector3i.ZERO, "level 1 is the centre")
	for i: int in range(1, 7):
		assert_eq(Hex.distance(HexFlower.CELLS[i], Vector3i.ZERO), 1,
			"level %d should be on the ring" % (i + 1))
	var ring: Array[Vector3i] = []
	for i: int in range(1, 7):
		ring.append(HexFlower.CELLS[i])
	for step: int in range(6):
		assert_true(ring.has(Hex.neighbour(Vector3i.ZERO, step)),
			"the ring is missing the neighbour in direction %d" % step)


## "+ a second row of 5": five cells, all on one row, evenly spaced, centred
## under the flower. Measured in pixels, because "a row" is a statement about
## where they land on screen and not about their coordinates.
func test_the_last_five_are_one_straight_centred_row() -> void:
	var ys: Array[float] = []
	var xs: Array[float] = []
	for i: int in range(7, 12):
		var p: Vector2 = _flower.layout.to_pixel(HexFlower.CELLS[i])
		ys.append(p.y)
		xs.append(p.x)
	for y: float in ys:
		assert_almost_eq(y, ys[0], 0.001, "the row of five is not level")
	var gap: float = xs[1] - xs[0]
	assert_gt(gap, 0.0, "the row runs left to right, in reading order")
	for i: int in range(1, xs.size()):
		assert_almost_eq(xs[i] - xs[i - 1], gap, 0.001, "the row is not evenly spaced")
	assert_almost_eq(xs[0] + xs[4], 2.0 * _flower.layout.to_pixel(Vector3i.ZERO).x, 0.001,
		"the row is not centred under the flower")
	# And it sits below the cluster rather than through it.
	assert_gt(ys[0], _flower.layout.to_pixel(Vector3i(0, -1, 1)).y,
		"the row of five overlaps the ring")


func test_every_level_round_trips_from_its_own_position() -> void:
	for index: int in range(1, HexFlower.CELLS.size() + 1):
		var at: Vector2 = _flower.layout.to_pixel(HexFlower.cell_for(index))
		assert_eq(_flower.level_at(at), index,
			"level %d does not answer at its own centre" % index)


## The pointer lands on a cell, not merely near one — B7's lesson, in the one
## other place the project converts a screen point into a hex.
func test_a_point_anywhere_inside_a_cell_still_finds_it() -> void:
	var s: float = _flower.layout.size
	for index: int in range(1, HexFlower.CELLS.size() + 1):
		var at: Vector2 = _flower.layout.to_pixel(HexFlower.cell_for(index))
		for offset: Vector2 in [
			Vector2(0.0, -s * 0.5), Vector2(0.0, s * 0.5),
			Vector2(s * 0.4, 0.0), Vector2(-s * 0.4, 0.0),
		]:
			assert_eq(_flower.level_at(at + offset), index,
				"level %d loses a point %v from its centre" % [index, offset])


func test_a_point_outside_the_flower_belongs_to_nobody() -> void:
	assert_eq(_flower.level_at(Vector2(-4000.0, -4000.0)), 0)
	assert_eq(_flower.level_at(Vector2(4000.0, 4000.0)), 0)


## §4.4's fit rule, over this shape's own span: the whole flower plus its margin
## has to be inside the box, at every size the screen can be.
func test_the_whole_flower_fits_inside_its_box_with_the_margin_left() -> void:
	for box: Vector2 in [Vector2(1280, 656), Vector2(800, 480), Vector2(1920, 1080)]:
		var f := HexFlower.new()
		add_child_autofree(f)
		f.size = box
		f.bind(_rows(), box)
		var min_x: float = INF
		var max_x: float = -INF
		var min_y: float = INF
		var max_y: float = -INF
		var s: float = f.layout.size
		for cell: Vector3i in HexFlower.CELLS:
			var p: Vector2 = f.layout.to_pixel(cell)
			min_x = minf(min_x, p.x - s * 0.867)
			max_x = maxf(max_x, p.x + s * 0.867)
			min_y = minf(min_y, p.y - s)
			max_y = maxf(max_y, p.y + s)
		assert_gte(min_x, 0.0, "the flower runs off the left at %v" % box)
		assert_lte(max_x, box.x, "the flower runs off the right at %v" % box)
		assert_gte(min_y, 0.0, "the flower runs off the top at %v" % box)
		assert_lte(max_y, box.y, "the flower runs off the bottom at %v" % box)


func test_the_cursor_never_leaves_the_chapter() -> void:
	_flower.set_cursor(0)
	assert_eq(_flower.cursor(), 1)
	_flower.set_cursor(99)
	assert_eq(_flower.cursor(), LevelRepository.LEVELS_PER_CHAPTER)


## The map navigates on §11.2's cone, which needs a position per candidate. A
## missing one silently sends the cursor to the board centre instead.
func test_every_level_has_a_position_for_the_router() -> void:
	var centres: Dictionary = _flower.centres()
	assert_eq(centres.size(), HexFlower.CELLS.size())
	for cell: Vector3i in HexFlower.CELLS:
		assert_true(centres.has(cell), "%v has no screen position" % cell)

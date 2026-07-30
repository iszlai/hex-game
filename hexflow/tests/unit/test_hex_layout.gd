## @core — the §4.3 conversion and §4.4 fit rule, in both of their outputs.
##
## `HexLayout` had no test of its own: it was exercised only through `BoardView`
## and the e2e playthroughs, which is a thin thread to hang B7's fix on. C-18 now
## adds a second consumer — cube → the ground plane of the orthographic-3D board —
## so the formula is asserted directly, and asserted to be *the same formula* in
## both outputs. A plane that disagrees with the pixel layout by a factor or a sign
## would put the 3D board's start in a different corner from the grey-box's.
extends GutTest

const SQRT3 := 1.7320508075688772
const EPS := 0.0001

var _layout: HexLayout = null


func before_each() -> void:
	_layout = HexLayout.new(53.0, Vector2(440.0, 344.0))


## §4.3's worked example: the centre cell sits on the origin, and one step in each
## of the two axial directions moves by the tabulated pitch.
func test_pixel_conversion_matches_the_tabulated_pitch() -> void:
	assert_eq(_layout.to_pixel(Vector3i.ZERO), _layout.origin)
	var east: Vector2 = _layout.to_pixel(Vector3i(1, -1, 0)) - _layout.origin
	assert_almost_eq(east.x, SQRT3 * 53.0, EPS, "column pitch is sqrt(3)*s")
	assert_almost_eq(east.y, 0.0, EPS, "a +q step never changes the row")
	var down: Vector2 = _layout.to_pixel(Vector3i(0, -1, 1)) - _layout.origin
	assert_almost_eq(down.y, 1.5 * 53.0, EPS, "row pitch is 1.5*s")


## Godot 2D is y-down, so z = +3 is the bottom of the screen. The 2016 prototype's
## layout depends on this: reverse it and every level plays mirrored.
func test_start_renders_bottom_left_and_goal_top_right() -> void:
	var start := _layout.to_pixel(Vector3i(-3, 0, 3))
	var goal := _layout.to_pixel(Vector3i(3, 0, -3))
	assert_lt(start.x, goal.x, "start is left of goal")
	assert_gt(start.y, goal.y, "start is below goal (y-down)")


func test_pixel_round_trips_for_every_cell_of_a_radius_four_board() -> void:
	for c: Vector3i in Hex.hexagon(4):
		assert_eq(_layout.from_pixel(_layout.to_pixel(c)), c, "%v must round-trip" % c)


## A click anywhere inside a cell resolves to that cell, not just a click dead on
## its centre — this is what hit-testing actually does (B7).
func test_pixel_round_trips_from_off_centre_points() -> void:
	var offsets: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(0.4 * SQRT3 * 53.0, 0.0),
		Vector2(-0.4 * SQRT3 * 53.0, 0.0),
		Vector2(0.0, 0.45 * 53.0),
		Vector2(0.0, -0.45 * 53.0),
	]
	for c: Vector3i in Hex.hexagon(3):
		for o: Vector2 in offsets:
			assert_eq(_layout.from_pixel(_layout.to_pixel(c) + o), c,
				"%v must own the point %v from its centre" % [c, o])


## C-18: the plane is the same formula, so it must agree with the pixel layout cell
## for cell once the 2D centring offset is taken out.
func test_plane_is_the_pixel_conversion_without_the_centring_origin() -> void:
	for c: Vector3i in Hex.hexagon(4):
		var px: Vector2 = _layout.to_pixel(c) - _layout.origin
		var plane: Vector3 = _layout.to_plane(c)
		assert_almost_eq(plane.x, px.x, EPS, "%v x" % c)
		assert_almost_eq(plane.z, px.y, EPS, "%v z" % c)
		assert_eq(plane.y, 0.0, "%v must sit on the ground plane" % c)


## The 3D board is centred on the world origin and framed by the camera, so moving
## the 2D origin must not shift the plane under it.
func test_plane_ignores_the_two_dimensional_origin() -> void:
	var moved := HexLayout.new(53.0, Vector2(9999.0, -7.0))
	for c: Vector3i in Hex.hexagon(3):
		assert_eq(moved.to_plane(c), _layout.to_plane(c), "%v must not follow origin" % c)


func test_plane_round_trips_for_every_cell_of_a_radius_four_board() -> void:
	for c: Vector3i in Hex.hexagon(4):
		assert_eq(_layout.from_plane(_layout.to_plane(c)), c, "%v must round-trip" % c)


## The camera ray is intersected with y = 0 in floating point, so the hit lands near
## the plane rather than exactly on it. Height must not change the answer.
func test_from_plane_ignores_height() -> void:
	for c: Vector3i in Hex.hexagon(3):
		var p: Vector3 = _layout.to_plane(c)
		for y: float in [-12.0, -0.001, 0.001, 40.0]:
			assert_eq(_layout.from_plane(Vector3(p.x, y, p.z)), c,
				"%v must resolve at height %f" % [c, y])


## Same orientation on the plane as on screen: +z is toward the bottom of the frame
## at yaw 0, so the start stays bottom-left through the move to 3D.
func test_plane_keeps_the_screen_orientation_of_the_grey_box() -> void:
	var start: Vector3 = _layout.to_plane(Vector3i(-3, 0, 3))
	var goal: Vector3 = _layout.to_plane(Vector3i(3, 0, -3))
	assert_lt(start.x, goal.x, "start is left of goal")
	assert_gt(start.z, goal.z, "start is nearer the camera-side edge")


## §4.4's table, which the camera's fit rule will be checked against in turn.
func test_fit_reproduces_the_reference_sizes() -> void:
	var play_box := Vector2(880.0, 688.0)
	assert_eq(HexLayout.fit(2, play_box), 74)
	assert_eq(HexLayout.fit(3, play_box), 53)
	assert_eq(HexLayout.fit(4, play_box), 42)


func test_fit_leaves_the_margin_free_on_both_axes() -> void:
	var play_box := Vector2(880.0, 688.0)
	for radius: int in [2, 3, 4]:
		var s: int = HexLayout.fit(radius, play_box)
		var f: Vector2 = HexLayout.new(float(s)).footprint(radius)
		assert_lte(f.x + 2.0 * HexLayout.MARGIN, play_box.x, "radius %d width" % radius)
		assert_lte(f.y + 2.0 * HexLayout.MARGIN, play_box.y, "radius %d height" % radius)
		var next: Vector2 = HexLayout.new(float(s + 1)).footprint(radius)
		assert_true(
			next.x + 2.0 * HexLayout.MARGIN > play_box.x
				or next.y + 2.0 * HexLayout.MARGIN > play_box.y,
			"radius %d must be the *largest* size that fits" % radius
		)


## The footprint has to bound the cells it claims to bound, or the margin is a lie.
func test_footprint_bounds_every_cell_centre_plus_its_circumradius() -> void:
	for radius: int in [2, 3, 4]:
		var layout := HexLayout.new(40.0)
		var f: Vector2 = layout.footprint(radius)
		for c: Vector3i in Hex.hexagon(radius):
			var p: Vector3 = layout.to_plane(c)
			assert_lte(absf(p.x) + SQRT3 * 0.5 * 40.0, f.x * 0.5 + EPS, "%v exceeds the width" % c)
			assert_lte(absf(p.z) + 40.0, f.y * 0.5 + EPS, "%v exceeds the height" % c)


func test_fit_never_returns_a_degenerate_size() -> void:
	assert_eq(HexLayout.fit(4, Vector2(10.0, 10.0)), 8, "clamps rather than going to zero")

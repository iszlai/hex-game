## @core — C-18's orthographic-3D camera: framing, the six yaw stops, and the fit.
##
## Two things here are worth more than the rest. "Clockwise" is asserted against
## what a player sees, by unprojecting a cell and checking which way it went on
## screen — a sign error in the orbit would otherwise ship as a control that turns
## the wrong way and reads as correct in every diagram. And the fit is verified by
## an independent sweep of the whole turn rather than by recomputing the fit: the
## board must not clip the play area at any yaw it passes *through*, which is the
## part fitting only the six stops gets wrong.
extends GutTest

## The 1280×800 reference play area of §4.4: viewport minus the rail, top bar and
## banner strip.
const PLAY := Vector2(880.0, 688.0)
const EPS := 0.001

var _viewport: SubViewport = null
var _camera: BoardCamera = null
var _reduce_motion: bool = false


func before_all() -> void:
	_reduce_motion = SettingsService.reduce_motion()


func after_all() -> void:
	SettingsService.set_value("reduce_motion", _reduce_motion)


func before_each() -> void:
	SettingsService.set_value("reduce_motion", false)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(int(PLAY.x), int(PLAY.y))
	add_child_autofree(_viewport)
	_camera = BoardCamera.new()
	_viewport.add_child(_camera)
	_camera.frame_play_area(PLAY)


func _layout(radius: int) -> HexLayout:
	return HexLayout.new(float(BoardCamera.fit_projected(radius, PLAY)))


func test_projection_is_orthographic_and_one_world_unit_is_one_pixel() -> void:
	assert_eq(_camera.projection, Camera3D.PROJECTION_ORTHOGONAL)
	assert_eq(_camera.keep_aspect, Camera3D.KEEP_HEIGHT)
	assert_almost_eq(_camera.size, PLAY.y, EPS, "ortho height is the play box height")
	# 1:1 means the horizontal extent covers the play box's width as well.
	assert_almost_eq(_camera.size * PLAY.x / PLAY.y, PLAY.x, EPS)


func test_the_elevation_is_the_fixed_c21_angle_and_the_camera_never_rolls() -> void:
	for step: int in range(BoardCamera.YAW_STOPS):
		var b: Basis = BoardCamera.basis_at(BoardCamera.YAW_STOP_RADIANS * float(step))
		# basis.z points back toward the camera, so its height is sin(elevation).
		assert_almost_eq(b.z.y, sin(deg_to_rad(BoardCamera.ELEVATION_DEGREES)), EPS,
			"stop %d looks down at the C-21 elevation" % step)
		assert_almost_eq(b.x.y, 0.0, EPS, "screen-right stays level at stop %d" % step)


func test_the_board_centre_projects_to_the_centre_of_the_play_area() -> void:
	assert_almost_eq(_camera.unproject_position(Vector3.ZERO).x, PLAY.x * 0.5, 0.5)
	assert_almost_eq(_camera.unproject_position(Vector3.ZERO).y, PLAY.y * 0.5, 0.5)


## The 3D view must open on the same reading as the grey-box, or every level looks
## mirrored the day the camera lands: +q to the right, +z toward the bottom.
func test_yaw_zero_reads_like_the_grey_box() -> void:
	var layout := _layout(3)
	var centre := _camera.unproject_position(Vector3.ZERO)
	var east := _camera.unproject_position(layout.to_plane(Vector3i(1, -1, 0)))
	var south := _camera.unproject_position(layout.to_plane(Vector3i(0, -1, 1)))
	assert_gt(east.x, centre.x, "+q is to the right")
	assert_almost_eq(east.y, centre.y, 0.5, "a +q step never changes the row")
	assert_gt(south.y, centre.y, "+z is toward the bottom of the screen")
	var start := _camera.unproject_position(layout.to_plane(Vector3i(-3, 0, 3)))
	var goal := _camera.unproject_position(layout.to_plane(Vector3i(3, 0, -3)))
	assert_lt(start.x, goal.x, "start is left of goal")
	assert_gt(start.y, goal.y, "start is below goal")


## Named after what the player sees, not after which way the camera orbits: a point
## out to the right must swing *downward*, the way a clock's hand does at 3.
func test_rotate_cw_turns_the_board_clockwise_on_screen() -> void:
	var probe := Vector3(200.0, 0.0, 0.0)
	var before := _camera.unproject_position(probe)
	_camera.rotate_by(1)
	assert_true(await wait_for_signal(_camera.yaw_settled, 1.0), "rotation must settle")
	var after := _camera.unproject_position(probe)
	assert_lt(after.x, before.x, "swings in from the right")
	assert_gt(after.y, before.y, "and downward — clockwise")


func test_rotate_ccw_is_the_exact_inverse() -> void:
	var probe := Vector3(0.0, 0.0, 200.0)
	var cw: Vector3 = BoardCamera.basis_at(BoardCamera.YAW_STOP_RADIANS).inverse() * probe
	var ccw: Vector3 = BoardCamera.basis_at(-BoardCamera.YAW_STOP_RADIANS).inverse() * probe
	assert_almost_eq(cw.x, -ccw.x, EPS, "mirrored horizontally")
	assert_almost_eq(cw.y, ccw.y, EPS, "and at the same screen height")


func test_yaw_step_wraps_and_six_stops_return_the_exact_starting_transform() -> void:
	# Reduce Motion only to keep six real tweens quick; the identity being asserted
	# does not depend on the duration.
	SettingsService.set_value("reduce_motion", true)
	var start: Transform3D = _camera.transform
	for i: int in range(BoardCamera.YAW_STOPS):
		_camera.rotate_by(1)
		assert_true(await wait_for_signal(_camera.yaw_settled, 1.0), "stop %d settles" % i)
		assert_eq(_camera.yaw_step, (i + 1) % BoardCamera.YAW_STOPS)
	assert_eq(_camera.yaw_step, 0, "six clockwise stops is a whole turn")
	assert_eq(_camera.transform, start, "and lands bit-identical, not merely close")


func test_rotation_is_tweened_rather_than_instant() -> void:
	var start: Transform3D = _camera.transform
	_camera.rotate_by(1)
	assert_true(_camera.is_rotating(), "a rotation is in flight")
	assert_eq(_camera.transform, start, "and has not jumped to the new stop")
	assert_true(await wait_for_signal(_camera.yaw_settled, 1.0))
	assert_false(_camera.is_rotating())
	assert_almost_eq(_camera.yaw_radians(), BoardCamera.YAW_STOP_RADIANS, EPS)


## A player who taps twice quickly means two stops, not one interrupted one.
func test_a_second_press_mid_rotation_adds_a_stop() -> void:
	_camera.rotate_by(1)
	_camera.rotate_by(1)
	assert_eq(_camera.yaw_step, 2)
	assert_true(await wait_for_signal(_camera.yaw_settled, 1.0))
	assert_almost_eq(_camera.yaw_radians(), 2.0 * BoardCamera.YAW_STOP_RADIANS, EPS)


func test_reduce_motion_scales_the_yaw_like_every_other_duration() -> void:
	assert_almost_eq(_camera.yaw_seconds(), BoardCamera.YAW_SECONDS, EPS)
	SettingsService.set_value("reduce_motion", true)
	assert_almost_eq(_camera.yaw_seconds(), BoardCamera.YAW_SECONDS * 0.4, EPS)


## `unproject_at` is a second copy of the camera's projection, kept because the
## rotation is tweened and §11.2 wants the yaw the player is heading for rather than
## the one the camera is passing through. A second copy has to be pinned to the
## first or it drifts, so it is compared against the engine's own answer — at the
## six stops and at two yaws that are not stops.
func test_unproject_at_matches_the_cameras_own_projection() -> void:
	var probes: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(180.0, 0.0, 0.0),
		Vector3(-90.0, 0.0, 240.0),
		Vector3(60.0, 30.0, -150.0),
	]
	var yaws: Array[float] = [17.0, 43.0]
	for step: int in range(BoardCamera.YAW_STOPS):
		yaws.append(rad_to_deg(BoardCamera.YAW_STOP_RADIANS * float(step)))
	for degrees: float in yaws:
		var yaw := deg_to_rad(degrees)
		_camera.transform = BoardCamera.transform_at(yaw)
		for p: Vector3 in probes:
			var mine: Vector2 = _camera.unproject_at(p, yaw)
			var theirs: Vector2 = _camera.unproject_position(p)
			assert_almost_eq(mine.x, theirs.x, 0.01, "%v x at %.0f°" % [p, degrees])
			assert_almost_eq(mine.y, theirs.y, 0.01, "%v y at %.0f°" % [p, degrees])


## The pointer half of C-18: ray ∩ y = 0 must be the exact inverse of the
## projection, or B7 comes back as a click that lands one cell over.
func test_plane_point_inverts_the_projection() -> void:
	for degrees: int in [0, 60, 137]:
		_camera.transform = BoardCamera.transform_at(deg_to_rad(float(degrees)))
		for p: Vector3 in [Vector3.ZERO, Vector3(150.0, 0.0, -220.0), Vector3(-300.0, 0.0, 90.0)]:
			var back: Vector3 = _camera.plane_point(_camera.unproject_position(p))
			assert_almost_eq(back.x, p.x, 0.01, "%v x at %d°" % [p, degrees])
			assert_almost_eq(back.y, 0.0, 0.01, "the hit is on the plane")
			assert_almost_eq(back.z, p.z, 0.01, "%v z at %d°" % [p, degrees])


## The oblique projection foreshortens depth, so the same box holds a bigger board
## than it does head-on. If this ever inverts, the fit is being applied to the
## board's own plane again rather than to what the camera sees.
func test_the_projected_fit_is_larger_than_the_head_on_fit() -> void:
	for radius: int in [2, 3, 4]:
		assert_gt(BoardCamera.fit_projected(radius, PLAY), HexLayout.fit(radius, PLAY),
			"radius %d" % radius)


## The criterion, checked independently of the fit that is supposed to satisfy it:
## nothing the board is made of may leave the play area, at any yaw the rotation
## passes through — not just at the six it stops on.
func test_no_cell_corner_leaves_the_play_area_at_any_yaw() -> void:
	for radius: int in [2, 3, 4]:
		var layout := _layout(radius)
		_assert_board_fits(radius, layout, "radius %d" % radius)


func test_the_projected_fit_is_the_largest_size_that_survives_the_sweep() -> void:
	for radius: int in [2, 3, 4]:
		var s: int = BoardCamera.fit_projected(radius, PLAY)
		var half: Vector2 = BoardCamera.unit_extents(radius) * float(s + 1)
		assert_true(
			half.x + HexLayout.MARGIN > PLAY.x * 0.5 or half.y + HexLayout.MARGIN > PLAY.y * 0.5,
			"radius %d must be the largest size that fits, and %d does not" % [radius, s + 1]
		)


## Rotating must not resize the board: the stops are 60° apart and a hexagon of
## cells is invariant under a 60° turn, so all six must project to the same bounds.
func test_the_board_is_the_same_size_at_every_stop() -> void:
	var layout := _layout(3)
	var first := Vector2.ZERO
	for step: int in range(BoardCamera.YAW_STOPS):
		var extent := _extent_at(layout, 3, BoardCamera.YAW_STOP_RADIANS * float(step))
		if step == 0:
			first = extent
		else:
			assert_almost_eq(extent.x, first.x, 0.01, "stop %d width" % step)
			assert_almost_eq(extent.y, first.y, 0.01, "stop %d height" % step)


## Thickness stands up out of the plane, so it costs screen height and therefore
## cell size. The prisms are not built yet; the fit must already account for them.
func test_tile_thickness_costs_size_rather_than_overflowing_the_box() -> void:
	var flat: int = BoardCamera.fit_projected(3, PLAY)
	var thick: int = BoardCamera.fit_projected(3, PLAY, 0.5)
	assert_lt(thick, flat, "a raised top face must shrink the fit")
	var layout := HexLayout.new(float(thick))
	_assert_board_fits(3, layout, "with thickness", 0.5)


## One assertion per axis over the whole sweep rather than one per point: 130,000
## passing asserts would bury the count that tells a reader how much the suite
## actually checks. The worst offender is reported, which is the one worth naming.
func _assert_board_fits(radius: int, layout: HexLayout, label: String,
		top_ratio: float = 0.0) -> void:
	var top: float = layout.size * top_ratio
	var worst := Vector2.ZERO
	var worst_at := ""
	for degrees: int in range(0, 360, 3):
		var b: Basis = BoardCamera.basis_at(deg_to_rad(float(degrees)))
		for c: Vector3i in Hex.hexagon(radius):
			var centre: Vector3 = layout.to_plane(c)
			for k: Vector2 in layout.corners():
				var v: Vector3 = centre + Vector3(k.x, top, k.y)
				var reach := Vector2(absf(v.dot(b.x)), absf(v.dot(b.y)))
				if reach.x > worst.x or reach.y > worst.y:
					worst_at = "%v at %d°" % [c, degrees]
				worst = worst.max(reach)
	assert_lte(worst.x + HexLayout.MARGIN, PLAY.x * 0.5 + EPS,
		"%s: widest reach is %s" % [label, worst_at])
	assert_lte(worst.y + HexLayout.MARGIN, PLAY.y * 0.5 + EPS,
		"%s: tallest reach is %s" % [label, worst_at])


## §14.3 gives the camera one piece of motion the player did not ask for, and
## states its budget three ways: 2 px maximum, 120 ms, once per level completion —
## "nowhere else". The last of those is the one worth enforcing in code, because it
## is the one a future caller would breach without noticing.
func test_the_shake_is_two_pixels_and_only_ever_once() -> void:
	var camera := BoardCamera.new()
	add_child_autofree(camera)
	camera.frame_play_area(Vector2(880.0, 688.0))

	assert_eq(camera.shake_amount(), 0.0, "still until a level is completed")
	assert_true(camera.shake_once(), "the one completion shakes")
	assert_lte(camera.shake_amount(), Motion.SHAKE_PIXELS, "§14.3's 2 px is a maximum")
	assert_gt(camera.shake_amount(), 0.0, "and it did move")

	assert_false(camera.shake_once(), "a second completion in the same level must not")
	camera.reset_shake()
	assert_true(camera.shake_once(), "but the next level may")


## It moves the board on screen rather than swinging the camera through the world:
## the offset is along the camera's own axes, so the view slides and the board does
## not rotate under it.
func test_the_shake_slides_the_view_without_turning_it() -> void:
	var camera := BoardCamera.new()
	add_child_autofree(camera)
	var steady := camera.transform
	camera.shake_once()
	assert_ne(camera.transform.origin, steady.origin, "the view moved")
	assert_almost_eq(camera.transform.basis.x.dot(steady.basis.x), 1.0, 0.0001,
		"but not by turning")
	# Two pixels of a two-thousand-unit camera distance, so the offset stays tiny.
	assert_lt(camera.transform.origin.distance_to(steady.origin),
		Motion.SHAKE_PIXELS * 2.0, "and only by the budget")


## §14.5: no shake at all. Not a smaller one.
func test_reduce_motion_removes_the_shake_entirely() -> void:
	SettingsService.set_value("reduce_motion", true)
	var camera := BoardCamera.new()
	add_child_autofree(camera)
	assert_false(camera.shake_once(), "§14.5 names shake first among what it removes")
	assert_eq(camera.shake_amount(), 0.0)
	SettingsService.set_value("reduce_motion", false)



func _extent_at(layout: HexLayout, radius: int, yaw: float) -> Vector2:
	var b: Basis = BoardCamera.basis_at(yaw)
	var half := Vector2.ZERO
	for c: Vector3i in Hex.hexagon(radius):
		var centre: Vector3 = layout.to_plane(c)
		for k: Vector2 in layout.corners():
			var v: Vector3 = centre + Vector3(k.x, 0.0, k.y)
			half.x = maxf(half.x, absf(v.dot(b.x)))
			half.y = maxf(half.y, absf(v.dot(b.y)))
	return half

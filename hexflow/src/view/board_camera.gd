## The orthographic-3D board camera of C-18.
##
## Fixed elevation, yaw snapped to the six 60° positions of the hex lattice and
## tweened between them. The board itself never moves — the camera orbits it — so
## the lattice reads identically at every stop (a radius-R hexagon of cells is
## invariant under a 60° turn about its centre) and the six direction glyphs meet
## the eye at the same six fixed angles rather than at arbitrary ones.
##
## The transform written here is the **local** one, so the camera's parent is the
## board's own root and the board is centred on it. That is also what lets
## [method fit_projected] work in board-local coordinates.
##
## The three numbers C-18 left open — the elevation, the tween length, and the
## fact that the fit is swept across the rotation rather than evaluated at the
## stops — are recorded as decision C-21.
class_name BoardCamera
extends Camera3D

## Height angle above the board plane. 90° is the 2D grey-box seen from straight
## above; 0° is edge-on. At 55° the plane's depth is foreshortened to
## sin 55° = 0.82, which still reads unambiguously as a hexagon, while
## cos 55° = 0.57 of a prism's height projects as its visible side, so tile
## thickness and drop shadows have something to occupy (C-21).
const ELEVATION_DEGREES := 55.0

const YAW_STOPS := 6
const YAW_STOP_RADIANS := TAU / float(YAW_STOPS)

## One stop of yaw. Between §14.1's 220 ms placement pop and its 320 ms screen
## transition: the board never leaves the screen, so it does not need the full
## transition length, but the player must be able to see which way it went.
## Reduce Motion scales it by §14.5's ×0.4 like every other duration.
const YAW_SECONDS := 0.26
const REDUCE_MOTION_SCALE := 0.4

## Orthographic projection ignores distance entirely, so this only has to clear
## the board and stay inside [member Camera3D.far].
const DISTANCE := 2000.0

## Yaw samples across one 60° sector — one per degree — used by
## [method fit_projected]. The board's projected bounds are equal at all six
## *stops* by symmetry, but not in between: mid-rotation the hexagon presents its
## corners where it presented its flats, and bulges. Fitting only the stops would
## let the board clip the play area for a tenth of a second every time the player
## rotates (C-21). A degree is far finer than the flooring of the result, and the
## sweep runs once per level, not per frame.
const FIT_SAMPLES := 61

## Emitted once a rotation has settled on [member yaw_step]. Anything cached in
## screen space — §11.2's cone, the cursor ring — recomputes here, not per frame (C4).
signal yaw_settled(step: int)

## Which of the six stops the camera is on, or heading to while a rotation is in
## flight. Always in `0 … YAW_STOPS - 1`.
var yaw_step: int = 0

var _yaw: float = 0.0
var _tween: Tween = null


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	# The play area's *height* is the fixed reference (§4.4 sizes against a box of
	# a known height), so the horizontal extent follows the viewport's aspect.
	keep_aspect = KEEP_HEIGHT
	near = 1.0
	far = DISTANCE * 2.0
	_apply_yaw()


## Sizes the camera to [param box], the §12.3 play area in pixels. One world unit
## is one pixel, which is what keeps §4.4's 48 px margin literally 48 px and lets
## [method fit_projected] answer in the same units as [method HexLayout.fit].
func frame_play_area(box: Vector2) -> void:
	size = maxf(1.0, box.y)


## The largest integer cell circumradius whose **projected** bounds plus
## [constant HexLayout.MARGIN] fit inside [param box] — §4.4's rule, applied after
## the oblique projection rather than to the board's own plane (C-18). Because the
## projection foreshortens depth, this is larger than [method HexLayout.fit]'s
## head-on answer for the same box.
##
## [param top_ratio] is the height of the tallest thing standing on the plane as a
## fraction of the cell circumradius — tile thickness, once the prisms exist. It
## scales with the cells, so the whole fit stays linear in the size being solved for.
static func fit_projected(radius: int, box: Vector2, top_ratio: float = 0.0) -> int:
	var usable := box - Vector2(HexLayout.MARGIN, HexLayout.MARGIN) * 2.0
	var half := unit_extents(radius, top_ratio)
	var by_width: float = usable.x / (2.0 * half.x)
	var by_height: float = usable.y / (2.0 * half.y)
	return maxi(8, int(floor(minf(by_width, by_height))))


## Projected half-extents of a radius-[param radius] board drawn at unit cell size,
## worst case over the rotation. Everything scales linearly in the cell size, so
## one evaluation answers for every size.
static func unit_extents(radius: int, top_ratio: float = 0.0) -> Vector2:
	var layout := HexLayout.new(1.0)
	var corners := layout.corners()
	var cells := Hex.hexagon(radius)
	var half := Vector2.ZERO
	for i: int in range(FIT_SAMPLES):
		var b := basis_at(YAW_STOP_RADIANS * float(i) / float(FIT_SAMPLES - 1))
		var right := b.x
		var up := b.y
		for c: Vector3i in cells:
			var centre := layout.to_plane(c)
			for k: Vector2 in corners:
				var v := centre + Vector3(k.x, 0.0, k.y)
				# `right` has no y component by construction (it is UP × forward),
				# so height can only ever move a point vertically on screen.
				half.x = maxf(half.x, absf(v.dot(right)))
				var vy: float = v.dot(up)
				half.y = maxf(half.y, maxf(absf(vy), absf(vy + top_ratio * up.y)))
	return half


## Where the camera sits for [param yaw], looking at the board centre.
static func position_at(yaw: float, distance: float) -> Vector3:
	var e := deg_to_rad(ELEVATION_DEGREES)
	return Vector3(sin(yaw) * cos(e), sin(e), cos(yaw) * cos(e)) * distance


## The camera basis at [param yaw]: `x` is screen-right, `y` is screen-up, both in
## board space. Computed the same way the camera's own transform is, so a fit done
## through this cannot disagree with what is rendered.
static func basis_at(yaw: float) -> Basis:
	return transform_at(yaw).basis


static func transform_at(yaw: float) -> Transform3D:
	return Transform3D(Basis(), position_at(yaw, DISTANCE)).looking_at(Vector3.ZERO, Vector3.UP)


## Turns the board [param steps] stops clockwise on screen (negative for
## anticlockwise), tweened. Pressing again mid-rotation adds to the target rather
## than restarting it, so two quick presses travel 120° the short way round.
func rotate_by(steps: int) -> void:
	if steps == 0:
		return
	yaw_step = posmod(yaw_step + steps, YAW_STOPS)
	_tween_to(_yaw + YAW_STOP_RADIANS * float(steps))


## Where a pointer at [param screen] meets the board's plane: the camera ray
## intersected with `y = 0` (C-18). Feed the result to
## [method HexLayout.from_plane] — never hit-test in screen coordinates (B7).
##
## The elevation is fixed and well away from edge-on, so the ray always meets the
## plane; the guard exists so a future elevation of 0 fails visibly at the board
## centre rather than by propagating a `null`.
func plane_point(screen: Vector2) -> Vector3:
	var from := project_ray_origin(screen)
	var dir := project_ray_normal(screen)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	if hit == null:
		push_error("board camera is edge-on to its own plane")
		return Vector3.ZERO
	return hit


## Where [param point] lands on screen at [param yaw], without moving the camera.
## The rotation is tweened, so the yaw the player is heading for is not the yaw the
## camera is currently at, and the screen-space positions §11.2 works from want the
## former.
##
## Orthographic, and the camera orbits the board centre — so the position along the
## view axis contributes nothing, and the projection is just the two basis vectors
## and the viewport centre. This is a second copy of a projection, which is exactly
## the kind of thing that drifts, so the test pins it against
## [method Camera3D.unproject_position] at every stop and in between.
func unproject_at(point: Vector3, yaw: float) -> Vector2:
	var b := basis_at(yaw)
	var view := Vector2(get_viewport().size)
	var pixels_per_unit: float = view.y / size
	# Screen y grows downward, world up is `b.y`.
	return view * 0.5 + Vector2(point.dot(b.x), -point.dot(b.y)) * pixels_per_unit


func is_rotating() -> bool:
	return _tween != null and _tween.is_running()


func yaw_radians() -> float:
	return _yaw


## §14.5: every duration is scaled, not just some of them.
func yaw_seconds() -> float:
	var seconds := YAW_SECONDS
	if SettingsService.reduce_motion():
		seconds *= REDUCE_MOTION_SCALE
	return seconds


func _tween_to(target: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_yaw, _yaw, target, yaw_seconds()) \
		.set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_IN_OUT)
	_tween.finished.connect(_on_rotation_finished)


func _set_yaw(radians: float) -> void:
	_yaw = radians
	_apply_yaw()


## Settles on the canonical angle for the stop rather than on whatever the tween
## accumulated. The two differ only by a whole turn, so nothing moves — but it
## keeps the six stops bit-identical however many times the player rotates, which
## is what makes a cached screen-space projection safe to reuse.
func _on_rotation_finished() -> void:
	_yaw = YAW_STOP_RADIANS * float(yaw_step)
	_apply_yaw()
	yaw_settled.emit(yaw_step)


func _apply_yaw() -> void:
	transform = transform_at(_yaw)

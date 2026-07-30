## Cube ↔ pixel conversion for the pointy-top layout (§4.3, §4.4).
##
## This lives in `src/view/` rather than in `hex.gd` on purpose. §16.3 lists pixel
## constants under `hex.gd`, but §19 forbids floats anywhere in `src/core/`, and
## the conversion is irreducibly floating point. Keeping it here leaves the core
## integer-only, so the determinism check over `src/core/` stays trivially
## enforceable. Logged as decision C-13.
class_name HexLayout
extends RefCounted

const SQRT3 := 1.7320508075688772

## Margin reserved on every side of the play area before fitting the board.
const MARGIN := 48.0

## Circumradius in pixels: centre to vertex.
var size: float = 53.0
var origin: Vector2 = Vector2.ZERO

var _corners: PackedVector2Array = PackedVector2Array()


func _init(p_size: float = 53.0, p_origin: Vector2 = Vector2.ZERO) -> void:
	set_size(p_size)
	origin = p_origin


func set_size(p_size: float) -> void:
	size = p_size
	_corners = PackedVector2Array()
	# Pointy-top: vertices at -30°, 30°, 90° … so the flat sides face left/right.
	for i: int in range(6):
		var a: float = deg_to_rad(60.0 * float(i) - 30.0)
		_corners.append(Vector2(cos(a), sin(a)) * size)


## The six corners of a hexagon centred on the origin. Prebuilt and reused, so
## nothing allocates during `_draw` (C4 — the original leaked a texture per tile).
func corners() -> PackedVector2Array:
	return _corners


## `px = s·√3·(q + r/2)`, `py = s·1.5·r`, with axial `q = x`, `r = z`.
## Godot 2D is y-down, so `z = +3` renders at the bottom and `z = -3` at the top:
## start `(-3,0,3)` lands bottom-left and goal `(3,0,-3)` top-right, exactly as
## the 2016 prototype laid them out.
func to_pixel(c: Vector3i) -> Vector2:
	return origin + _offset(c)


## Inverse conversion for mouse and touch, through fractional cube coordinates
## and cube rounding. Always route hit-testing through this rather than raw
## screen coordinates (defect B7).
func from_pixel(p: Vector2) -> Vector3i:
	return _unoffset(p - origin)


## Cube → the ground plane of the orthographic-3D board (C-18), at `y = 0`.
##
## §4.3's formula unchanged, fed straight into world `(x, z)`. [member origin]
## deliberately does **not** apply: the 3D board is centred on the world origin and
## framing is the camera's job (§4.4's fit rule applied to the projected bounds),
## whereas [member origin] exists to centre the 2D board inside a `Control`. Tile
## thickness extrudes upward from here, which is why the plane itself stays at zero.
##
## A camera pitched downward at yaw 0 sees world `+x` to the right and world `+z`
## toward the bottom of the screen — the same handedness as Godot's y-down 2D — so
## the lattice reads identically to the grey-box: start `(-3,0,3)` bottom-left,
## goal `(3,0,-3)` top-right.
func to_plane(c: Vector3i) -> Vector3:
	var p := _offset(c)
	return Vector3(p.x, 0.0, p.y)


## Inverse of [method to_plane], for C-18's camera-ray ∩ `y = 0` hit-test.
## [param p]`.y` is ignored, so a ray hit landing a hair off the plane still
## resolves. The rounding is [method from_pixel]'s own, shared rather than
## reimplemented, so B7's fix survives the move to 3D.
func from_plane(p: Vector3) -> Vector3i:
	return _unoffset(Vector2(p.x, p.z))


## The §4.3 conversion itself, origin-free: the one place the formula is written.
## [method to_pixel] adds the 2D origin, [method to_plane] spreads it over `(x, z)`.
func _offset(c: Vector3i) -> Vector2:
	var q := float(c.x)
	var r := float(c.z)
	return Vector2(size * SQRT3 * (q + r / 2.0), size * 1.5 * r)


func _unoffset(local: Vector2) -> Vector3i:
	var q_f := (local.x * SQRT3 / 3.0 - local.y / 3.0) / size
	var r_f := (local.y * 2.0 / 3.0) / size
	return _cube_round(q_f, -q_f - r_f, r_f)


## Full rendered footprint of a radius-[param radius] board at the current size.
func footprint(radius: int) -> Vector2:
	return Vector2(SQRT3 * size * float(2 * radius + 1), size * float(3 * radius + 2))


## The largest integer circumradius whose footprint plus [constant MARGIN] on
## every side fits inside [param box] (§4.4). At the 1280×800 reference the play
## box is 880×688, giving s = 74 / 53 / 42 for radius 2 / 3 / 4.
static func fit(radius: int, box: Vector2) -> int:
	var usable := box - Vector2(MARGIN, MARGIN) * 2.0
	var by_width: float = usable.x / (SQRT3 * float(2 * radius + 1))
	var by_height: float = usable.y / float(3 * radius + 2)
	return maxi(8, int(floor(minf(by_width, by_height))))


## Centres the board inside [param box]. A hexagonal board is symmetric about its
## centre cell `(0,0,0)`, so centring is just placing the origin at the middle.
func center_in(box: Vector2) -> void:
	origin = box * 0.5


static func _cube_round(xf: float, yf: float, zf: float) -> Vector3i:
	var rx := roundf(xf)
	var ry := roundf(yf)
	var rz := roundf(zf)
	var dx := absf(rx - xf)
	var dy := absf(ry - yf)
	var dz := absf(rz - zf)
	# Correct the component that moved furthest, so the sum returns to zero.
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector3i(int(rx), int(ry), int(rz))

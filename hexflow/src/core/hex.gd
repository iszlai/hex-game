## Cube-coordinate math for a pointy-top hex lattice.
##
## A cell is a [Vector3i] with the invariant `x + y + z == 0`. [Vector3i] is used
## deliberately: it is value-comparable and hashable, which structurally prevents
## the 2016 prototype's fatal defect (B1 — a coordinate type without value
## equality made every grid lookup return null).
##
## Integer-only by construction (§19). Pixel/layout conversion deliberately lives
## in `src/view/hex_layout.gd` so that `src/core/` contains no floats at all and
## the determinism grep stays trivially enforceable.
class_name Hex


## Number of cells on a radius-[param radius] hexagonal board: 3R² + 3R + 1.
## "No cell". `Vector3i.ZERO` is a real cell — the centre of every board — so a
## function that can fail to find one needs a value that is not a coordinate.
## `(1,1,1)` does not sum to zero, which §4.1 requires of every cube coordinate,
## so nothing can ever equal it by accident.
const NONE := Vector3i(1, 1, 1)


static func cell_count(radius: int) -> int:
	return 3 * radius * radius + 3 * radius + 1


static func is_valid(c: Vector3i) -> bool:
	return c.x + c.y + c.z == 0


## Cube distance between two cells.
static func distance(a: Vector3i, b: Vector3i) -> int:
	var d := a - b
	return maxi(maxi(absi(d.x), absi(d.y)), absi(d.z))


## Distance from the origin.
static func length(c: Vector3i) -> int:
	return maxi(maxi(absi(c.x), absi(c.y)), absi(c.z))


## The six neighbours of [param c], in the fixed §4.2 direction order.
static func neighbours(c: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for d: int in Direction.ALL:
		out.append(c + Direction.delta(d))
	return out


static func neighbour(c: Vector3i, dir: int) -> Vector3i:
	return c + Direction.delta(dir)


## All cells of a radius-[param radius] hexagon, in a stable order
## (ascending z, then ascending x) so iteration is deterministic across platforms.
static func hexagon(radius: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for z: int in range(-radius, radius + 1):
		var x_min: int = maxi(-radius, -radius - z)
		var x_max: int = mini(radius, radius - z)
		for x: int in range(x_min, x_max + 1):
			out.append(Vector3i(x, -x - z, z))
	return out


## The cells at exactly cube distance [param r] from the origin, clockwise on screen.
static func ring(radius: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if radius <= 0:
		out.append(Vector3i.ZERO)
		return out
	var c: Vector3i = Direction.delta(Direction.SW) * radius
	for d: int in Direction.ALL:
		for _step: int in range(radius):
			out.append(c)
			c += Direction.delta(d)
	return out


## Sorts a list of cells into a canonical order. Used wherever a Dictionary's
## iteration order would otherwise leak into an outcome (§19, stable iteration).
static func sort_cells(cells: Array[Vector3i]) -> Array[Vector3i]:
	var out: Array[Vector3i] = cells.duplicate()
	out.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.z != b.z:
			return a.z < b.z
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y)
	return out


## Parses `[x, y, z]` from level JSON. Returns [code]false[/code] via
## [param ok] semantics by asserting in debug; callers validate first.
static func from_array(a: Array) -> Vector3i:
	assert(a.size() == 3, "cube coordinate must have 3 components")
	var c := Vector3i(int(a[0]), int(a[1]), int(a[2]))
	assert(is_valid(c), "cube coordinate must satisfy x + y + z == 0")
	return c


static func to_array(c: Vector3i) -> Array:
	return [c.x, c.y, c.z]

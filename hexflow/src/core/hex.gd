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


# --- board shapes (C-32) ------------------------------------------------------
#
# §4.4 sizes a board by radius and the generator has only ever built hexagons, so
# every one of the sixty campaign levels is the same silhouette at one of three
# sizes. That is the whole of the game's visual variety in board terms, and it is
# also the whole of its *topological* variety: a hexagon has no corridors, no
# holes and no pinch points, so the only lever the generator has for making a
# route interesting is where it puts the walls.
#
# Shapes are the alternative to growing the board, and growing the board is not
# available: the solver packs the path into a 64-bit mask, so 61 cells is the
# ceiling (C-19), and a radius-4 board is already too big for the difficulty
# tools to search. Shape costs nothing to measure and, unlike a slightly larger
# hexagon, is something a player can recognise and remember.

## The solver's path mask is 64 bits with two reserved, so no board may exceed
## this. Every shape below asserts it rather than trusting its own arithmetic.
const MAX_CELLS := 61


## A triangle of side [param side]: `(side + 1) * (side + 2) / 2` cells, one
## corner at the origin. Corners are traps — a route that enters one has only the
## way it came — which a hexagon has nothing like.
static func triangle(side: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for x: int in range(side + 1):
		for y: int in range(side + 1 - x):
			out.append(Vector3i(x, y, -x - y))
	return _finish(out)


## A hexagonal annulus: everything of [param radius] except the cells within
## [param hole] of the centre. The hole is the point — a route cannot cut across,
## so two goals on opposite sides force a genuine choice of direction rather than
## a straight line.
static func ring_board(radius: int, hole: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for c: Vector3i in hexagon(radius):
		if length(c) > hole:
			out.append(c)
	return _finish(out)


## A parallelogram [param length] cells long and [param width] deep. Narrow enough
## that the route has nowhere to wander, which is what makes a wrong tile hurt.
static func corridor(length_cells: int, width: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for q: int in range(length_cells):
		for r: int in range(width):
			out.append(Vector3i(q, -q - r, r))
	return _finish(out)


## A hexagon pinched at the middle row, so the two halves meet through a gap of
## [param waist] cells. Everything has to pass the waist, which makes the order
## moves arrive in matter far more than it does on an open board.
static func hourglass(radius: int, waist: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for c: Vector3i in hexagon(radius):
		if c.z == 0 and absi(c.x) >= waist:
			continue
		out.append(c)
	return _finish(out)


## The three axes through the centre — a six-pointed asterisk. Each arm is one
## cell wide, so a route down one has no room to manoeuvre and no way across to
## another except by coming back through the middle. A multi-goal board becomes a
## question of what order to visit the arms in.
##
## The arms are *not* joined only at the origin, which is the tempting thing to
## assume: adjacent axes touch anywhere within one cell of the centre, because two
## hexes on different axes at distance 1 are still neighbours. They separate from
## distance 2 outward.
##
## Not a hexagram: a six-pointed *outline* needs cells outside the hexagon that
## bounds it, and there is no room under [constant MAX_CELLS] for one big enough
## to play on.
static func star(radius: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for c: Vector3i in hexagon(radius):
		if c.x == 0 or c.y == 0 or c.z == 0:
			out.append(c)
	return _finish(out)


## Canonical order and the size ceiling, applied to every shape at the one place
## they all pass through — a shape that silently returned 70 cells would fail much
## later, inside the solver's mask, as a wrong answer rather than as an error.
static func _finish(cells: Array[Vector3i]) -> Array[Vector3i]:
	assert(cells.size() <= MAX_CELLS,
		"a board of %d cells will not fit the solver's 64-bit path mask" % cells.size())
	return sort_cells(cells)

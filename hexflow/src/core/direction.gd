## The six hex directions.
##
## This table is Appendix A of the specification and is verified against the 2016
## tile art (`hex_A.png` … `hex_F.png`). The index order is load-bearing: the tile
## bag (§5.3), every solver and every save file depend on it. Never permute it.
##
## | Index | Enum | Original | Cube delta   | Lit edge    | Bearing |
## |-------|------|----------|--------------|-------------|---------|
## | 0     | NW   | SIDE_A   | ( 0, +1, -1) | upper-left  | 240°    |
## | 1     | NE   | SIDE_B   | (+1,  0, -1) | upper-right | 300°    |
## | 2     | E    | SIDE_C   | (+1, -1,  0) | right       | 0°      |
## | 3     | SE   | SIDE_D   | ( 0, -1, +1) | lower-right | 60°     |
## | 4     | SW   | SIDE_E   | (-1,  0, +1) | lower-left  | 120°    |
## | 5     | W    | SIDE_F   | (-1, +1,  0) | left        | 180°    |
class_name Direction

enum { NW = 0, NE = 1, E = 2, SE = 3, SW = 4, W = 5 }

const COUNT := 6

## Iterate directions through this constant, never through `range(6)` written
## inline, so the fixed order has exactly one definition.
const ALL: Array[int] = [NW, NE, E, SE, SW, W]

const DELTAS: Array[Vector3i] = [
	Vector3i(0, 1, -1),   # NW
	Vector3i(1, 0, -1),   # NE
	Vector3i(1, -1, 0),   # E
	Vector3i(0, -1, 1),   # SE
	Vector3i(-1, 0, 1),   # SW
	Vector3i(-1, 1, 0),   # W
]

const NAMES: Array[String] = ["NW", "NE", "E", "SE", "SW", "W"]

## Original 2016 identifiers, kept for traceability against the prototype art.
const LEGACY_NAMES: Array[String] = [
	"SIDE_A", "SIDE_B", "SIDE_C", "SIDE_D", "SIDE_E", "SIDE_F"
]

## Screen bearing in degrees, y-down, clockwise from +x. Integer by §19; the
## view converts to radians. This is the direction the path travels on screen,
## and also the edge of the source hexagon that is lit.
const BEARINGS: Array[int] = [240, 300, 0, 60, 120, 180]

## Sentinel used in the edge list for a portal link, which joins two cells that
## are not lattice neighbours and therefore has no direction.
const PORTAL := -1

## Sentinel for "the stream is exhausted".
const NONE := -2


static func delta(dir: int) -> Vector3i:
	return DELTAS[dir]


static func opposite(dir: int) -> int:
	return (dir + 3) % COUNT


static func name_of(dir: int) -> String:
	if dir == PORTAL:
		return "PORTAL"
	if dir == NONE:
		return "NONE"
	return NAMES[dir]


static func bearing_degrees(dir: int) -> int:
	return BEARINGS[dir]


## Parses a direction name from level JSON. Returns [constant NONE] if unknown,
## so the loader can report a precise validation error rather than crashing.
static func from_name(n: String) -> int:
	var i: int = NAMES.find(n.to_upper())
	return i if i >= 0 else NONE


## Infers the direction from [param a] to an adjacent [param b].
## Returns [constant NONE] when the cells are not neighbours (wild placements and
## solver code rely on this being total, not an assertion).
static func between(a: Vector3i, b: Vector3i) -> int:
	var d := b - a
	var i: int = DELTAS.find(d)
	return i if i >= 0 else NONE

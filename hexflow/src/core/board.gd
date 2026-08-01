## Immutable level topology: which cells exist, what kind they are, what flags
## they carry. A [Board] is built once and never mutated during play — all
## mutable run state lives in [GameState].
class_name Board
extends RefCounted

enum Kind { EMPTY = 0, WALL = 1 }

## Flags are a bitmask so a cell can be, say, both a GOAL and a GATE.
const F_START := 1
const F_GOAL := 2
const F_PORTAL := 4
const F_GATE := 8
const F_WILD := 16

## How far the furthest cell sits from the centre. Derived from the cells, not
## given: for a hexagon it is the radius it was built with, and for every other
## shape it is whatever that shape turned out to reach.
var radius: int = 3

## §C-32's silhouette, and the number that shapes it. Kept so a level file can
## name a shape rather than list sixty cells, and so `to_dict` can write back what
## `from_dict` read.
var shape: String = "hexagon"
var shape_arg: int = 0
## The size the shape was *asked* for, which is only the same as [member radius]
## for a hexagon.
var shape_size: int = 3
var start: Vector3i = Vector3i.ZERO
var goals: Array[Vector3i] = []

var _kinds: Dictionary = {}      # Vector3i -> Kind
var _flags: Dictionary = {}      # Vector3i -> int bitmask
var _portal_twin: Dictionary = {}  # Vector3i -> Vector3i
var _cells: Array[Vector3i] = []   # stable iteration order


## [param p_shape] and [param p_shape_arg] are last and defaulted, so every caller
## that predates shapes keeps building the hexagon it always built (C-32).
##
## [member radius] is derived from the cells rather than taken from
## [param p_radius], because a shape's size parameter is not its radius — a
## triangle of side 6 is not a radius-6 board — and [member radius] is what §4.4
## fits the board on screen by.
static func build(
	p_radius: int,
	p_start: Vector3i,
	p_goals: Array[Vector3i],
	p_walls: Array[Vector3i] = [],
	p_portal_pairs: Array = [],
	p_gates: Array[Vector3i] = [],
	p_wilds: Array[Vector3i] = [],
	p_shape: String = "hexagon",
	p_shape_arg: int = 0
) -> Board:
	var b := Board.new()
	b.shape = p_shape
	b.shape_arg = p_shape_arg
	b.shape_size = p_radius
	b._cells = Hex.shape(p_shape, p_radius, p_shape_arg)
	b.radius = Hex.bounding_radius(b._cells)
	for c: Vector3i in b._cells:
		b._kinds[c] = Kind.EMPTY
		b._flags[c] = 0

	b.start = p_start
	b._flags[p_start] = int(b._flags.get(p_start, 0)) | F_START

	b.goals = Hex.sort_cells(p_goals)
	for g: Vector3i in b.goals:
		b._flags[g] = int(b._flags.get(g, 0)) | F_GOAL

	for w: Vector3i in p_walls:
		b._kinds[w] = Kind.WALL

	for pair: Variant in p_portal_pairs:
		var a: Vector3i = (pair as Array)[0]
		var t: Vector3i = (pair as Array)[1]
		b._flags[a] = int(b._flags.get(a, 0)) | F_PORTAL
		b._flags[t] = int(b._flags.get(t, 0)) | F_PORTAL
		b._portal_twin[a] = t
		b._portal_twin[t] = a

	for g: Vector3i in p_gates:
		b._flags[g] = int(b._flags.get(g, 0)) | F_GATE

	for w: Vector3i in p_wilds:
		b._flags[w] = int(b._flags.get(w, 0)) | F_WILD

	return b


## Every cell of the board, ascending z then x. Never iterate `_kinds` directly.
func cells() -> Array[Vector3i]:
	return _cells


func size() -> int:
	return _cells.size()


func has(c: Vector3i) -> bool:
	return _kinds.has(c)


func kind(c: Vector3i) -> Kind:
	return _kinds.get(c, Kind.EMPTY)


func is_wall(c: Vector3i) -> bool:
	return _kinds.get(c, Kind.EMPTY) == Kind.WALL


## True when [param c] exists and is not a wall — i.e. could ever join the path.
func is_open(c: Vector3i) -> bool:
	return _kinds.has(c) and _kinds[c] == Kind.EMPTY


func flags(c: Vector3i) -> int:
	return _flags.get(c, 0)


func has_flag(c: Vector3i, flag: int) -> bool:
	return (int(_flags.get(c, 0)) & flag) != 0


func is_goal(c: Vector3i) -> bool:
	return has_flag(c, F_GOAL)


func is_gate(c: Vector3i) -> bool:
	return has_flag(c, F_GATE)


func is_wild(c: Vector3i) -> bool:
	return has_flag(c, F_WILD)


func is_portal(c: Vector3i) -> bool:
	return has_flag(c, F_PORTAL)


## The twin of a portal cell, or [param c] itself when it is not a portal.
func portal_twin(c: Vector3i) -> Vector3i:
	return _portal_twin.get(c, c)


func portal_pairs() -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for c: Vector3i in _cells:
		if not _portal_twin.has(c) or seen.has(c):
			continue
		var t: Vector3i = _portal_twin[c]
		seen[c] = true
		seen[t] = true
		out.append([c, t])
	return out


func walls() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for c: Vector3i in _cells:
		if _kinds[c] == Kind.WALL:
			out.append(c)
	return out


func cells_with_flag(flag: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for c: Vector3i in _cells:
		if has_flag(c, flag):
			out.append(c)
	return out


## Structural validation, per §17.1. Returns a list of human-readable problems;
## empty means valid. The loader fails loudly on this in debug builds.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if radius < 2 or radius > 4:
		problems.append("radius %d out of range 2..4" % radius)
	for c: Vector3i in _kinds.keys():
		if not Hex.is_valid(c):
			problems.append("cell %v violates x + y + z == 0" % c)
		if Hex.length(c) > radius:
			problems.append("cell %v lies outside radius %d" % [c, radius])
	if not has(start):
		problems.append("start %v is not on the board" % start)
	elif is_wall(start):
		problems.append("start %v is a wall" % start)
	if goals.is_empty():
		problems.append("level has no goal")
	for g: Vector3i in goals:
		if not has(g):
			problems.append("goal %v is not on the board" % g)
		elif is_wall(g):
			problems.append("goal %v is a wall" % g)
	for c: Vector3i in _portal_twin.keys():
		var t: Vector3i = _portal_twin[c]
		if _portal_twin.get(t, Vector3i.ZERO) != c:
			problems.append("portal %v is not reciprocally paired" % c)
		if is_wall(c):
			problems.append("portal %v is a wall" % c)
	return problems

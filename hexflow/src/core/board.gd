## Immutable level topology: which cells exist, what kind they are, what flags
## they carry. A [Board] is built once and never mutated during play — all
## mutable run state lives in [GameState].
class_name Board
extends RefCounted

enum Kind { EMPTY = 0, WALL = 1 }

## Flags are a bitmask so a cell can be, say, both a GOAL and a GATE.
## Below this a board has no room for a route worth playing. Not a spec number —
## the smallest shipped board is a radius-2 hexagon at 19 cells.
const MIN_CELLS := 12

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
##
## [param p_cells], when given, **is** the board, and the shape fields become a
## label for what it started as. That is the map editor's case (MAP-EDITOR §4.3):
## a board someone has added cells to or cut cells out of is not describable in
## three numbers, and the alternative — forbidding the edit — would mean a wall
## were the only way to make a hole, which is a different thing on screen. Every
## other caller passes nothing and gets the shape it named.
static func build(
	p_radius: int,
	p_start: Vector3i,
	p_goals: Array[Vector3i],
	p_walls: Array[Vector3i] = [],
	p_portal_pairs: Array = [],
	p_gates: Array[Vector3i] = [],
	p_wilds: Array[Vector3i] = [],
	p_shape: String = "hexagon",
	p_shape_arg: int = 0,
	p_cells: Array[Vector3i] = []
) -> Board:
	var b := Board.new()
	b.shape = p_shape
	b.shape_arg = p_shape_arg
	b.shape_size = p_radius
	b._cells = _dedup(p_cells) if not p_cells.is_empty() \
		else Hex.shape(p_shape, p_radius, p_shape_arg)
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


## True when this board is *exactly* the shape it names, so a level file can say
## `"shape": "ring"` and three numbers instead of listing sixty coordinates.
##
## The comparison is elementwise because both sides are in [method
## Hex.sort_cells]'s canonical order — [method Hex.shape] finishes with it and
## [method build] applies it to an explicit list — so this is a list equality and
## not a set membership test.
func is_named_shape() -> bool:
	var named: Array[Vector3i] = Hex.shape(shape, shape_size, shape_arg)
	if named.size() != _cells.size():
		return false
	for i: int in range(named.size()):
		if named[i] != _cells[i]:
			return false
	return true


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


## An explicit cell list in canonical order, with repeats dropped. A hand-drawn
## board arrives as whatever the author painted and a level file as whatever was
## written; a cell listed twice would make [method size] disagree with the number
## of keys in `_kinds`, and the solver's cell ceiling is checked against
## [method size].
static func _dedup(cells_in: Array[Vector3i]) -> Array[Vector3i]:
	var seen: Dictionary = {}
	var out: Array[Vector3i] = []
	for c: Vector3i in cells_in:
		if not seen.has(c):
			seen[c] = true
			out.append(c)
	return Hex.sort_cells(out)


## Structural validation, per §17.1. Returns a list of human-readable problems;
## empty means valid. The loader fails loudly on this in debug builds.
func validate() -> Array[String]:
	var problems: Array[String] = []
	# The ceiling is the solver's 64-bit path mask (C-19), and "radius 2..4" was
	# only ever a proxy for it — the largest hexagon that fits is radius 4. It stops
	# being a proxy the moment a board is not a hexagon (C-32): a triangle of side 7
	# reaches a bounding radius of 5 and is still only 36 cells, well inside what
	# the solver holds. So the count is checked, which is the thing that actually
	# breaks, rather than the radius, which no longer implies it.
	if _cells.size() > Hex.MAX_CELLS:
		problems.append("%d cells will not fit the solver's path mask (max %d)"
			% [_cells.size(), Hex.MAX_CELLS])
	if _cells.size() < MIN_CELLS:
		problems.append("%d cells is too small to be a level" % _cells.size())
	for c: Vector3i in _kinds.keys():
		if not Hex.is_valid(c):
			problems.append("cell %v violates x + y + z == 0" % c)
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

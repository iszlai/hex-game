## One escalating Endless run (§7.2).
##
## Deliberately introduces no new rules: each stage is an ordinary [Level] on a
## radius-3 board with a bag stream, and the escalation is entirely in the data —
## the reached goal becomes the next start, the path resets, one wall is added,
## and a new goal spawns at least 4 cells away.
##
## Stage seeds are derived from the run seed with the same FNV-1a used for the
## daily (§19), so a run is reproducible from its seed alone. Logged as C-12.
class_name EndlessRun
extends RefCounted

const MIN_GOAL_DISTANCE := 4
const WALL_ATTEMPTS := 64

var seed: int = 0
var goals_reached: int = 0
var total_placements: int = 0

var _start: Vector3i = Vector3i.ZERO
var _goal: Vector3i = Vector3i.ZERO
var _walls: Array[Vector3i] = []
var _rng: RandomNumberGenerator = null
var _radius: int = 3


func _init(p_seed: int) -> void:
	seed = p_seed
	_rng = RandomNumberGenerator.new()
	_rng.seed = p_seed
	var rim: Array[Vector3i] = Hex.ring(_radius)
	_start = rim[_rng.randi_range(0, rim.size() - 1)]
	_goal = _spawn_goal(_start)


func current_level() -> Level:
	var board := Board.build(_radius, _start, [_goal] as Array[Vector3i], _walls)
	var lv := Level.build(board, [] as Array[int], _stage_seed())
	lv.id = "endless_%d" % goals_reached
	lv.discards = 3
	# Par is meaningless in Endless — the score is goals reached (§5.10).
	lv.par = 0
	return lv


## Advances the run after a goal is reached. Called by the director once the
## stage reports WON.
func advance(placements_this_stage: int = 0) -> void:
	goals_reached += 1
	total_placements += placements_this_stage
	_start = _goal
	# The goal is chosen first so the wall placement below can verify against it.
	_goal = _spawn_goal(_start)
	_add_wall()


func score() -> int:
	return goals_reached


func _stage_seed() -> int:
	return Generator.fnv1a_32("endless:%d:%d" % [seed, goals_reached])


func _spawn_goal(from: Vector3i) -> Vector3i:
	var candidates: Array[Vector3i] = []
	for c: Vector3i in Hex.hexagon(_radius):
		if c == from or _walls.has(c):
			continue
		if Hex.distance(from, c) < MIN_GOAL_DISTANCE:
			continue
		candidates.append(c)
	if candidates.is_empty():
		# The board has filled with walls; fall back to any open cell so the run
		# ends on a genuine dead state rather than on a generation failure.
		for c: Vector3i in Hex.hexagon(_radius):
			if c != from and not _walls.has(c):
				candidates.append(c)
	if candidates.is_empty():
		return from
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


## Adds a wall only where it still leaves the board traversable from the new
## start — §7.2's "a new wall spawns on a cell that keeps the next goal reachable".
func _add_wall() -> void:
	var open_cells: Array[Vector3i] = []
	for c: Vector3i in Hex.hexagon(_radius):
		if c == _start or c == _goal or _walls.has(c):
			continue
		open_cells.append(c)
	if open_cells.is_empty():
		return
	for _attempt: int in range(WALL_ATTEMPTS):
		var pick: Vector3i = open_cells[_rng.randi_range(0, open_cells.size() - 1)]
		_walls.append(pick)
		if _keeps_board_connected():
			return
		_walls.pop_back()


func _keeps_board_connected() -> bool:
	var board := Board.build(_radius, _start, [_goal] as Array[Vector3i], _walls)
	return Rules.hops_to(board, {_start: true}, _goal) >= 0

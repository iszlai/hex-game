extends SceneTree
## Authoring tool: builds, verifies and freezes §10's five teaching boards.
##
##     Godot --headless --path . -s res://tools/author_tutorial.gd
##
## The campaign is *swept* — `author_levels.gd` generates thousands of candidates
## and keeps the one that best fits a curve — and none of that applies here. A
## teaching board is not a puzzle that happens to be short: every cell on it is
## there to make one idea unmissable, and the route has to be the only route or
## the lesson is optional. So these five are **drawn by hand**, right here, and
## the tool's job is not to invent them but to prove them: run the solver, check
## the par it finds is the par the lesson needs, and write the files.
##
## That check is the whole point of the tool existing rather than five JSON files
## someone types. `MIN_PAR`/`MAX_PAR` below is the shortest and longest a lesson
## may run, and a board that has drifted outside it — because a rule changed
## under it — fails the run instead of shipping a tutorial that teaches the wrong
## thing.
##
## Output is **frozen data**, committed like the sixty (§9): never regenerated at
## runtime. Not part of the shipped game.

const OUT_DIR := "res://src/data/tutorial"

## A lesson is one idea. Under two placements there is nothing to do; over four
## the player is solving a puzzle instead of reading a board.
const MIN_PAR := 2
const MAX_PAR := 4

## The five boards, in the order they are played.
##
## Cells are `[column, row]`: `[0, 0]` is the shape's top-left cell and `[2, 1]`
## is two to the right and one down, because a hand-drawn board is far easier to
## read as a grid than as cube triples. The offset between that grid and the cube
## coordinates the board is built in is *read off the shape itself* (§4.4 centres
## every shape, so no cell of a corridor is at the origin), never assumed.
##
## `tiles` is a fixed sequence, never a seed: a lesson that dealt a different
## tile on a different run would need different words on screen.
const BOARDS: Array[Dictionary] = [
	{
		"index": 1,
		"name": "First flow",
		# Three by two, no obstacles: the smallest board that can hold a corner-
		# to-corner route with a turn in it, which is all the first lesson is.
		"shape": "corridor", "size": 3, "arg": 2,
		"start": [0, 1],
		"goals": [[2, 0]],
		"tiles": ["NE", "E", "W", "SE"],
	},
	{
		"index": 2,
		"name": "Around the wall",
		# The wall sits directly between the start and the goal, so the straight
		# line is the first thing the player tries and the first thing refused.
		"shape": "corridor", "size": 3, "arg": 2,
		"start": [0, 1],
		"goals": [[2, 1]],
		"walls": [[1, 1]],
		# Start and goal are the two ends of the bottom row and the wall is the
		# cell between them, so the detour is over the top: up, across, back down.
		"tiles": ["NE", "E", "SE", "W"],
	},
	{
		"index": 3,
		"name": "Through the portal",
		# Two walls cut the board in half — no route crosses them, at any length —
		# so the portal is not the short way, it is the only way.
		"shape": "corridor", "size": 3, "arg": 2,
		"start": [0, 1],
		"goals": [[2, 0]],
		"walls": [[1, 0], [1, 1]],
		"portals": [[[0, 0], [2, 1]]],
		"tiles": ["NW", "NW", "E", "SE"],
	},
	{
		"index": 4,
		"name": "Two ways in",
		# The gate is the only door to the goal, and the start is only one of its
		# two neighbours: the player has to build the second before it opens.
		"shape": "corridor", "size": 3, "arg": 2,
		"start": [0, 1],
		"goals": [[2, 0]],
		"walls": [[1, 1], [2, 1]],
		"gates": [[1, 0]],
		"tiles": ["NW", "E", "E", "SE"],
	},
	{
		"index": 5,
		"name": "One free step",
		# The goal touches exactly one open cell — the wild — and no tile in the
		# sequence points that way. The charge is not a shortcut here either.
		"shape": "corridor", "size": 3, "arg": 3,
		"start": [0, 1],
		"goals": [[2, 0]],
		"walls": [[1, 0], [2, 1]],
		"wilds": [[1, 1]],
		"tiles": ["E", "SE", "SE", "SE"],
	},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var written: int = 0
	for spec: Dictionary in BOARDS:
		var level := _build(spec)
		if _write(level, spec):
			written += 1
			print("%s  %-18s %d cells  par %d  tiles %s" % [
				level.id, spec["name"], level.board.size(), level.par,
				", ".join(_tile_names(level)),
			])
	print("wrote %d tutorial level files" % written)
	quit(0 if written == BOARDS.size() else 1)


## Builds the board and asks the solver what it is worth. The solver is the
## authority on both numbers a level file stores about itself: its par, and the
## line that reaches it.
func _build(spec: Dictionary) -> Level:
	var shape: String = str(spec["shape"])
	var size: int = int(spec["size"])
	var arg: int = int(spec.get("arg", 0))
	var corner: Vector3i = _top_left(Hex.shape(shape, size, arg))

	var board := Board.build(
		size,
		_cell(spec["start"], corner),
		_cells(spec.get("goals", []), corner),
		_cells(spec.get("walls", []), corner),
		_pairs(spec.get("portals", []), corner),
		_cells(spec.get("gates", []), corner),
		_cells(spec.get("wilds", []), corner),
		shape, arg
	)

	var tiles: Array[int] = []
	for n: Variant in spec["tiles"]:
		tiles.append(Direction.from_name(str(n)))

	var level := Level.build(board, tiles)
	level.id = "t_l%02d" % int(spec["index"])
	# Fixed rather than minted: a tutorial board records no stars and no bests, so
	# its uid names the lesson rather than standing in for a slot (C-34).
	level.uid = level.id
	level.index = int(spec["index"])
	# No discards and no budget. Both are pressure, and none of the five lessons is
	# about pressure — a player who has just learnt what a wall is does not also
	# need to be learning what running out means.
	level.discards = 0

	var result := Solver.solve(level)
	level.par = result.par
	level.solution = result.moves
	level.solution_script = result.actions
	return level


## Verifies and writes. A board that will not solve, or solves at a par outside
## what the lesson can carry, is a failed run rather than a file: it is easier to
## fix a board here than to find out from a player that the tutorial's third
## screen cannot be finished.
func _write(level: Level, spec: Dictionary) -> bool:
	var problems := LevelRepository.verify(level)
	if level.par < MIN_PAR or level.par > MAX_PAR:
		problems.append("par %d is outside a lesson's %d..%d"
			% [level.par, MIN_PAR, MAX_PAR])
	if not problems.is_empty():
		push_error("%s (%s): %s" % [level.id, spec["name"], ", ".join(problems)])
		return false
	return LevelFile.write(level, "%s/level_%02d.json" % [OUT_DIR, level.index])


## Column 0, row 0 of a rectangular shape, in the cube frame it was built in.
##
## The columns of a corridor run along `x` and its rows along `z`, and centring
## translates the whole set by one vector — so the least `x` on the board is the
## first column and the least `z` is the first row, and their meeting point is the
## cell the table calls `[0, 0]`. Read rather than assumed, so a change to how
## shapes are centred moves these boards with it instead of silently sliding every
## wall one cell sideways.
func _top_left(cells: Array[Vector3i]) -> Vector3i:
	var least_x: int = cells[0].x
	var least_z: int = cells[0].z
	for c: Vector3i in cells:
		least_x = mini(least_x, c.x)
		least_z = mini(least_z, c.z)
	return _at(least_x, least_z)


## `[column, row]` from the table, as a cell of the real board. Cube coordinates
## add componentwise, so a step of `[x, z]` from the corner is exactly that.
func _cell(pair: Variant, corner: Vector3i) -> Vector3i:
	var a: Array = pair
	return corner + _at(int(a[0]), int(a[1]))


## A cell from its column and row; `y` is whatever keeps the three summing to
## zero, which is the only thing it ever is (§4.1).
func _at(x: int, z: int) -> Vector3i:
	return Vector3i(x, -x - z, z)


func _cells(list: Variant, corner: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for pair: Variant in (list as Array):
		out.append(_cell(pair, corner))
	return out


func _pairs(list: Variant, corner: Vector3i) -> Array:
	var out: Array = []
	for pair: Variant in (list as Array):
		var p: Array = pair
		out.append([_cell(p[0], corner), _cell(p[1], corner)])
	return out


func _tile_names(level: Level) -> Array[String]:
	var out: Array[String] = []
	for d: int in level.tiles:
		out.append(Direction.name_of(d))
	return out

## A complete, frozen level: topology plus the level-scoped constraints of §6.
##
## The specification's module table (§16.3) does not name this type — `board.gd`
## owns topology and `game_state.gd` owns run state, which leaves `tiles`,
## `discards`, `budget` and `par` homeless. Per §1.1 C7 the simplest option is
## taken: a plain value object that carries them. Logged as decision C-9.
class_name Level
extends RefCounted

const NO_BUDGET := -1

var id: String = ""
var chapter: int = 0
var index: int = 0
var board: Board = null

## Explicit fixed direction sequence (§5.3). Empty means "use the seeded bag".
var tiles: Array[int] = []
var seed: int = 0

var discards: int = 3
var budget: int = NO_BUDGET
var par: int = 0

## The solver's optimal target order (§17.1). Used by tests and hints, never shown.
var solution: Array[Vector3i] = []

## The full replayable action script behind [member solution] — placements plus
## the voluntary discards and wild spends that a bare target list cannot express.
## Serialised as `solution_script`; §17.1 only specifies the target order, which
## is not sufficient to prove a stored solution still wins.
var solution_script: Array = []

## Provenance only — never read at runtime.
var generator_seed: int = 0

## What the level was *authored to be* (C-33): how many distinct ways there are to
## finish it in `par` moves, and what fraction of wrong turns are recoverable.
##
## Authoring metadata, like [member generator_seed] — written by the sweep that
## chose this candidate over the others, never recomputed at runtime. They exist
## so the shape of the campaign's difficulty curve is checkable in CI without
## re-measuring sixty boards, which takes minutes.
##
## `-1` means unmeasured, which is what every level authored before C-33 is.
var authored_routes: int = -1
var authored_forgiving: int = -1
var generator_params_version: int = 1


static func build(p_board: Board, p_tiles: Array[int] = [], p_seed: int = 0) -> Level:
	var lv := Level.new()
	lv.board = p_board
	lv.tiles = p_tiles
	lv.seed = p_seed
	return lv


func has_fixed_tiles() -> bool:
	return not tiles.is_empty()


func has_budget() -> bool:
	return budget != NO_BUDGET


func make_stream() -> TileStream:
	if has_fixed_tiles():
		return TileStream.from_tiles(tiles)
	return TileStream.from_seed(seed)


## §17.1 loader validation, beyond the structural checks in [method Board.validate].
## Solver-based par verification is a separate, slower step done by the repository.
func validate() -> Array[String]:
	var problems: Array[String] = board.validate() if board != null else ["level has no board"] as Array[String]
	if discards < 0:
		problems.append("discards %d is negative" % discards)
	if has_budget() and budget < par:
		problems.append("budget %d is below par %d" % [budget, par])
	if has_fixed_tiles() and par > 0 and tiles.size() < par:
		problems.append("tiles length %d is below par %d" % [tiles.size(), par])
	for d: int in tiles:
		if d < 0 or d >= Direction.COUNT:
			problems.append("tile %d is not a direction" % d)
	return problems

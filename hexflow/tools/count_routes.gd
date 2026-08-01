extends SceneTree
## Measurement tool: how many *different ways through* does each level have?
##
##     Godot --headless --path . -s res://tools/count_routes.gd -- [chapter]
##
## `tools/measure_difficulty.gd` found that 83–92% of every choice in the game is
## knife-edge for three stars, which means the ideal line is a single thread and
## counting routes *at* the ideal would answer "one" nearly everywhere. So this
## counts the band instead: routes that finish in the ideal number of moves, and
## in one, two or three more.
##
## Three more is not an arbitrary width — §5.10 gives two stars to `ideal + 3`, so
## the +3 column is literally "how many ways are there to get two stars". If that
## column is narrow the two-star band is decoration; if it is wide, it is the real
## game and the third star is a bonus round.
##
## **A route is a set of cells, not an order.** Two lines that light the same
## hexes in a different forced order are the same way through the board as far as
## a player is concerned, and counting orders would report the tile stream's
## shuffling rather than the board's shape.
##
## Reads only. Nothing here writes a level file. Not part of the shipped game.
##
## ## Why it is written the way it is
##
## The first version of this tool ran for twenty-one minutes on 780 MB and had not
## finished the campaign. Two things did that, and both are worth naming because
## they are the obvious way to write it:
##
## 1. **It keyed states on a stringified sorted cell list.** One string per state,
##    each holding a whole path, plus a sort to build it. The key is a *bitmask*
##    now — one integer, no sort, no allocation — which is what `solver.gd` has
##    always done and for the same reason.
## 2. **It cloned a [GameState] per node.** `GameState.start()` runs a full setup
##    including the first turn's resolution. It walks the tree with [method
##    GameState.undo] instead, which §5.9 already guarantees rewinds a placement
##    *and a discard* completely — so the search needs exactly one state object.
##
## Even so, the count can be astronomically large on a radius-4 board, so both a
## state ceiling and a wall-clock budget apply per level and a level that hits
## either reports its numbers as **lower bounds**. The signal wanted here is
## "corridor, puzzle, or stroll" — 1 versus 30 versus 2000 — not an exact figure.

## How far past the ideal to look. §5.10's two-star band is `ideal + 3`.
const OVER := 3

## Ceilings, per level. Either one being hit marks the row `capped`, and a capped
## row's numbers are **lower bounds**.
##
## Exact counting is not achievable deep in the campaign and is not worth chasing:
## the routes through a radius-4 board inside eighteen moves run to millions, and
## the question this tool exists to answer is which of three buckets a level is in
## — corridor (one way through), puzzle (a handful), or stroll (hundreds). A level
## reporting "≥150 000 states, stopped" is a stroll, and knowing whether the true
## figure was four thousand or forty would change no decision.
const MAX_STATES := 150000
const MAX_SECONDS := 10.0

var _index_of: Dictionary = {}   # Vector3i -> bit position
var _visited: Dictionary = {}    # mask -> { packed(index, discards, wild) -> fewest moves }
var _won: Dictionary = {}        # winning mask -> moves it first took
var _budget: int = 0
var _states: int = 0
var _deadline: int = 0
var _capped: bool = false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var only: int = int(args[0]) if args.size() > 0 else 0

	print("ch lv | ideal | at ideal |    +1 |    +2 |    +3 | total | capped")
	var totals: Dictionary = {}

	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		if only > 0 and chapter != only:
			continue
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			var level := LevelRepository.load_level(chapter, index)
			if level == null:
				continue
			var band := _count(level)
			var total: int = band[0] + band[1] + band[2] + band[3]
			print("%2d %2d | %5d | %8d | %5d | %5d | %5d | %5d | %s" % [
				chapter, index, level.par,
				band[0], band[1], band[2], band[3], total,
				"yes" if _capped else "",
			])
			var rows: Array = totals.get(chapter, [])
			rows.append(band)
			totals[chapter] = rows

	print("\nch | mean at ideal | mean +1 | mean +2 | mean +3 | mean total")
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		if not totals.has(chapter):
			continue
		var rows: Array = totals[chapter]
		var sums: Array[float] = [0.0, 0.0, 0.0, 0.0]
		for band: Variant in rows:
			for i: int in range(4):
				sums[i] += float((band as Array)[i])
		var n: float = float(rows.size())
		print("%2d | %13.1f | %7.1f | %7.1f | %7.1f | %10.1f" % [
			chapter, sums[0] / n, sums[1] / n, sums[2] / n, sums[3] / n,
			(sums[0] + sums[1] + sums[2] + sums[3]) / n,
		])
	quit()


func _count(level: Level) -> Array[int]:
	_index_of = {}
	var bit: int = 0
	for c: Vector3i in level.board.cells():
		_index_of[c] = bit
		bit += 1

	_visited = {}
	_won = {}
	_budget = level.par + OVER
	_states = 0
	_capped = false
	_deadline = Time.get_ticks_msec() + int(MAX_SECONDS * 1000.0)

	var state := GameState.start(level)
	_walk(state)

	var band: Array[int] = [0, 0, 0, 0]
	for moves: Variant in _won.values():
		var over: int = int(moves) - level.par
		if over >= 0 and over <= OVER:
			band[over] += 1
	return band


## Depth-first over the same state the solver uses, with [method GameState.undo]
## as the way back up. Nothing is cloned and nothing is allocated per node beyond
## the visited entry itself.
func _walk(state: GameState) -> void:
	if _capped:
		return
	_states += 1
	if _states >= MAX_STATES or Time.get_ticks_msec() > _deadline:
		_capped = true
		return

	for target: Vector3i in state.legal_targets():
		if not state.place(target):
			continue
		if state.status == GameState.Status.WON:
			# A route is the set of cells, so the first time a mask is reached is
			# also its cheapest — depth-first order does not guarantee that, so the
			# smaller count wins if the same route turns up twice.
			var mask: int = _mask_of(state)
			var was: int = int(_won.get(mask, 1 << 30))
			_won[mask] = mini(was, state.placements)
		elif state.status == GameState.Status.PLAYING \
				and state.placements < _budget and _visit(state):
			_walk(state)
		state.undo()
		if _capped:
			return

	# A voluntary discard is a turn but not a move, so it does not spend the move
	# budget — which is exactly why the ideal line takes every one it is given (see
	# `measure_slack.gd`). It still has to be walked, or whole branches of the board
	# go uncounted.
	if state.discards_left > 0 and state.discard():
		if state.status == GameState.Status.PLAYING and _visit(state):
			_walk(state)
		state.undo()


## Whether this state is worth walking: unseen, or seen before only at a move
## count this one beats. Nested by mask the way `solver.gd` nests its own visited
## set, so the outer key is one integer rather than one string per state.
func _visit(state: GameState) -> bool:
	var mask: int = _mask_of(state)
	var inner: Dictionary = _visited.get(mask, {})
	# Stream position, discards and charges all decide what can happen next, so two
	# states with the same cells are not interchangeable without them.
	var packed: int = (state.stream.index << 8) | (state.discards_left << 4) \
		| state.wild_charges
	if inner.has(packed) and int(inner[packed]) <= state.placements:
		return false
	inner[packed] = state.placements
	_visited[mask] = inner
	return true


## The path as one integer, one bit per board cell. Boards are capped at 61 cells
## by the solver's own 64-bit mask (C-19), so this always fits.
func _mask_of(state: GameState) -> int:
	var mask: int = 0
	for c: Vector3i in state.path.keys():
		mask |= 1 << int(_index_of.get(c, 0))
	return mask

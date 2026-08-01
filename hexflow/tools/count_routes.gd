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
## 3. **It searched straight to `ideal + 3` in one pass.** On a big board that
##    means going deep down one branch until the clock runs out, so five chapter-3
##    levels came back with *zero routes* — a failure wearing a number. It counts
##    one depth at a time now (see [method _count]), so running out of time costs
##    the deep columns and never the shallow ones.
## 4. **It had no lower bound.** No placement closes more than one hop of distance
##    to a goal, so a state needing more hops than it has moves left cannot win and
##    its whole subtree can be dropped. `solver.gd` has always used this; without
##    it the walk here was blind. It is the difference between five chapter-3
##    boards timing out with nothing and all twelve reporting a real count.
##
## Even with all four, the deep columns run out on the biggest boards, so a row
## says how far its numbers are trustworthy rather than pretending. The signal
## wanted is "corridor, puzzle, or stroll" — 1 versus 30 versus 2000 — and that
## lives in the first column, which now survives everywhere.

## How far past the ideal to look. §5.10's two-star band is `ideal + 3`.
const OVER := 3

## Ceilings, shared across a level's passes.
##
## Exact counting is not achievable deep in the campaign: the routes through a
## radius-4 board inside eighteen moves run to millions. What matters is that
## running out of time costs the *deep* columns and never the shallow ones — see
## [method _count].
const MAX_STATES := 150000
const MAX_SECONDS := 12.0

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

	print("ch lv | ideal | at ideal |    +1 |    +2 |    +3 | total | exact to")
	var totals: Dictionary = {}

	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		if only > 0 and chapter != only:
			continue
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			var level := LevelRepository.load_level(chapter, index)
			if level == null:
				continue
			var counted := _count(level)
			var band: Array = counted["band"]
			var exact_to: int = int(counted["exact_to"])
			var total: int = 0
			var cells: Array[String] = []
			for i: int in range(4):
				if i <= exact_to:
					total += int(band[i])
					cells.append("%5d" % int(band[i]))
				else:
					cells.append("    ?")
			print("%2d %2d | %5d | %4s     | %s | %s | %s | %5d | %s" % [
				chapter, index, level.par,
				cells[0], cells[1], cells[2], cells[3], total,
				_depth_name(exact_to),
			])
			if exact_to >= 0:
				var rows: Array = totals.get(chapter, [])
				rows.append({"band": band, "exact_to": exact_to})
				totals[chapter] = rows

	# Averaged only over the levels whose pass for that column actually finished, so
	# a chapter's mean is never dragged down by a board the clock beat.
	print("\nch | mean at ideal | mean +1 | mean +2 | mean +3   (n = levels measured)")
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		if not totals.has(chapter):
			continue
		var rows: Array = totals[chapter]
		var line: String = "%2d |" % chapter
		for i: int in range(4):
			var sum: float = 0.0
			var n: int = 0
			for r: Variant in rows:
				if int((r as Dictionary)["exact_to"]) >= i:
					sum += float(((r as Dictionary)["band"] as Array)[i])
					n += 1
			line += "  %8.1f (%2d)" % [sum / float(maxi(1, n)), n] if n > 0 else "        — ( 0)"
		print(line)
	quit()


func _depth_name(exact_to: int) -> String:
	match exact_to:
		0: return "ideal"
		1: return "+1"
		2: return "+2"
		3: return "all"
		_: return "nothing"


## Counts the band one depth at a time — the ideal first, then the ideal plus one,
## and so on — rather than searching to `ideal + 3` in a single pass.
##
## This is the whole point of the rewrite. A single deep pass explores one long
## branch at a time, so running out of time on a big board returned **zero routes**
## for levels that plainly have some: chapter 3 levels 4, 6 and 7 and chapter 5
## levels 9 and 11 all reported nothing at all, which is not a measurement, it is a
## failure wearing a number. Searching shallowest-first means a timeout costs the
## deep columns and never the shallow ones, so "how many perfect routes are there"
## survives on every board in the game.
##
## Each pass redoes the one before it. That is the ordinary cost of iterative
## deepening and it is small here, because the work grows so fast with depth that
## the last pass dominates every earlier one put together.
##
## Returns the four counts and `exact_to`: the highest column whose pass actually
## finished. Columns past it were never reached and are reported as unknown rather
## than as zero.
func _count(level: Level) -> Dictionary:
	_index_of = {}
	var bit: int = 0
	for c: Vector3i in level.board.cells():
		_index_of[c] = bit
		bit += 1

	var band: Array[int] = [0, 0, 0, 0]
	var exact_to: int = -1
	var cumulative: int = 0
	# One deadline for the level, shared by its passes, so a slow board cannot cost
	# more than any other board — later passes simply get whatever is left.
	_deadline = Time.get_ticks_msec() + int(MAX_SECONDS * 1000.0)

	for over: int in range(OVER + 1):
		# Visited has to be cleared between passes: a state pruned in the shallower
		# pass had its subtree cut off by that pass's budget, not by its own merits.
		_visited = {}
		_won = {}
		_states = 0
		_capped = false
		_budget = level.par + over

		_walk(GameState.start(level))
		if _capped:
			break
		# `_won` holds every route finishing in *at most* this budget, so the new
		# column is whatever this pass found beyond the last one.
		band[over] = _won.size() - cumulative
		cumulative = _won.size()
		exact_to = over

	return {"band": band, "exact_to": exact_to}


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

	# The bound the solver has always had and this tool did not: no placement can
	# close more than one hop of distance to a goal, so a state needing more hops
	# than it has moves left can be abandoned whole. Without it the search is blind
	# and five chapter-3 boards timed out before finding a single route — with it
	# they finish. One flood fill per node buys a subtree.
	if state.placements + _hops_left(state) > _budget:
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

	# §6's charge enters *any* cell adjacent to the path, not just the one the drawn
	# direction points at, so it is a different set of options and a separate branch.
	#
	# Leaving it out was not a missing feature, it was a wrong answer: chapter 5
	# levels 1, 5 and 10 are exactly the three whose best line spends a charge, and
	# all three reported **zero routes at the ideal** — a level with a stored ideal
	# and no way to reach it. A search that cannot make one of the game's moves does
	# not report fewer routes, it reports impossible ones.
	if state.wild_charges > 0:
		for target: Vector3i in Rules.wild_targets(state.board, state.path):
			if not state.place_wild(target):
				continue
			if state.status == GameState.Status.WON:
				var wmask: int = _mask_of(state)
				_won[wmask] = mini(int(_won.get(wmask, 1 << 30)), state.placements)
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


## The fewest further placements this state could possibly need: the furthest
## unreached goal, in hops, ignoring direction and gates. Optimistic on purpose —
## an over-estimate would prune a route that exists (§8.2 step 7 treats its own
## bound the same way).
func _hops_left(state: GameState) -> int:
	var worst: int = 0
	for g: Vector3i in state.board.goals:
		if state.path.has(g):
			continue
		var hops: int = Rules.hops_to(state.board, state.path, g)
		if hops < 0:
			return 1 << 20   # unreachable: nothing below here can win
		worst = maxi(worst, hops)
	return worst


## The path as one integer, one bit per board cell. Boards are capped at 61 cells
## by the solver's own 64-bit mask (C-19), so this always fits.
func _mask_of(state: GameState) -> int:
	var mask: int = 0
	for c: Vector3i in state.path.keys():
		mask |= 1 << int(_index_of.get(c, 0))
	return mask

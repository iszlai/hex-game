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
## Reads only. Nothing here writes a level file.
##
## Not part of the shipped game.

## How far past the ideal to look. §5.10's two-star band is `ideal + 3`.
const OVER := 3

## Search ceiling per level. A board with many open cells has a very large state
## space and this tool is a measurement, not an authoring step — a level that hits
## the cap reports its counts as lower bounds rather than pretending to be exact.
const MAX_STATES := 300000


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
			var counts := _count(level)
			var band: Array = counts["band"]
			var total: int = 0
			for n: int in band:
				total += n
			print("%2d %2d | %5d | %8d | %5d | %5d | %5d | %5d | %s" % [
				chapter, index, level.par,
				band[0], band[1], band[2], band[3], total,
				"yes" if counts["capped"] else "",
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


## Every distinct winning cell-set reachable in `ideal + OVER` moves or fewer,
## bucketed by how many moves over the ideal it took.
##
## Breadth-first over the same state the solver uses — `(path mask, stream index,
## discards left, wild charges)` — because a route that reaches the same state by
## a longer road can never do anything the shorter one could not. The *first* time
## a winning mask is seen is therefore its cheapest, which is the bucket it counts
## in: a route is counted once, at its best length, not once per way of walking it.
func _count(level: Level) -> Dictionary:
	var budget: int = level.par + OVER
	var band: Array[int] = [0, 0, 0, 0]
	var won: Dictionary = {}       # winning mask -> true
	var seen: Dictionary = {}      # state key -> cheapest moves seen
	var capped: bool = false

	var start := GameState.start(level)
	var frontier: Array = [start]
	var expanded: int = 0

	while not frontier.is_empty():
		var next_frontier: Array = []
		for s: Variant in frontier:
			var state: GameState = s
			expanded += 1
			if expanded >= MAX_STATES:
				capped = true
				break
			var snapshot: Dictionary = state.to_dict()

			for target: Vector3i in state.legal_targets():
				state.restore(snapshot)
				if not state.place(target):
					continue
				if state.placements > budget:
					continue
				if state.status == GameState.Status.WON:
					var mask: String = _mask_of(state)
					if not won.has(mask):
						won[mask] = true
						band[state.placements - level.par] += 1
					continue
				if state.status == GameState.Status.DEAD:
					continue
				var key: String = _key_of(state)
				if seen.has(key) and int(seen[key]) <= state.placements:
					continue
				seen[key] = state.placements
				next_frontier.append(_clone(state))

			# A voluntary discard is a turn but not a move, so it does not spend the
			# budget — which is exactly why the ideal line takes every one it is
			# given (see `measure_slack.gd`). It still has to be explored or whole
			# branches of the board go uncounted.
			state.restore(snapshot)
			if state.discards_left > 0 and state.discard() \
					and state.status == GameState.Status.PLAYING:
				var dkey: String = _key_of(state)
				if not seen.has(dkey) or int(seen[dkey]) > state.placements:
					seen[dkey] = state.placements
					next_frontier.append(_clone(state))
		if capped:
			break
		frontier = next_frontier

	return {"band": band, "capped": capped}


## The path as a sorted cell list. Two states with the same set of lit hexes are
## the same route however they were walked.
func _mask_of(state: GameState) -> String:
	var cells: Array[Vector3i] = []
	for c: Vector3i in state.path.keys():
		cells.append(c)
	return str(Hex.sort_cells(cells))


## The search state, which is the route so far *plus* everything that decides what
## can happen next. Two states with the same cells but a different stream position
## are not interchangeable.
func _key_of(state: GameState) -> String:
	return "%s|%d|%d|%d" % [
		_mask_of(state), state.stream.index, state.discards_left, state.wild_charges,
	]


func _clone(state: GameState) -> GameState:
	var copy := GameState.start(state.level)
	copy.restore(state.to_dict())
	return copy

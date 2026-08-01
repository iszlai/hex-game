## What a level *is*, measured rather than guessed (C-33).
##
## `par` measures length. These measure difficulty, and the two are not the same
## key: the shipped campaign is ordered by par and has no curve in either of the
## numbers below. This is the one implementation of them — `tools/count_routes.gd`
## and `tools/author_levels.gd` both call it, so a report and the sweep that
## authors against it can never disagree about what a level scores.
##
## Not part of the shipped game.
class_name LevelMetrics

## Ceilings, per measurement. A level that hits either is reported as *at least*
## its count rather than exactly — see [method routes_at_ideal].
const MAX_STATES := 120000
const MAX_SECONDS := 3.0

## Alternatives are probed with a smaller budget than authoring uses: forgiveness
## asks "is there a win down here", not "what is the best one", a few dozen times.
const PROBE_STATES := 30000


var _index_of: Dictionary = {}
var _visited: Dictionary = {}
var _won: Dictionary = {}
var _budget: int = 0
var _states: int = 0
var _deadline: int = 0
var _capped: bool = false


## How many distinct ways there are to finish [param level] in exactly its ideal
## number of moves. **A route is a set of cells, not an order** — two lines that
## light the same hexes in a different forced order are the same way through the
## board, and counting orders would report the tile stream's shuffling rather than
## the shape of the level.
##
## Returns `-1` when the search ran out, which the sweep treats as a rejection: a
## candidate nobody can score is a candidate nobody should ship. That is also the
## practical reason C-32 reaches for shape rather than size — a board big enough
## to defeat this is a board the authoring step cannot rank.
func routes_at_ideal(level: Level) -> int:
	_index_of = {}
	var bit: int = 0
	for c: Vector3i in level.board.cells():
		_index_of[c] = bit
		bit += 1
	_visited = {}
	_won = {}
	_states = 0
	_capped = false
	_budget = level.par
	_deadline = Time.get_ticks_msec() + int(MAX_SECONDS * 1000.0)

	_walk(GameState.start(level))
	return -1 if _capped else _won.size()


## What fraction of wrong turns can still be recovered from, in hundredths.
##
## Replays the stored ideal line and, at every turn with a real choice, asks the
## solver whether each other legal target still leads to a win. High means a
## mistake is survivable; low means the board is a corridor wearing a hexagon.
##
## The ideal line is the spine because it is the one route known to reach the goal
## in `par` — probing an arbitrary playthrough would measure how badly this file
## plays rather than how hard the level is.
func forgiveness(level: Level) -> int:
	var state := GameState.start(level)
	var decisions: int = 0
	var total: int = 0

	for step: Variant in level.solution_script:
		var entry: Array = step
		var kind: int = int(entry[0])
		if state.status != GameState.Status.PLAYING:
			break
		if kind == Solver.ACTION_DISCARD:
			state.discard()
			continue
		if kind == Solver.ACTION_WILD:
			# §6's charge enters any adjacent cell, so its options are a different
			# set from `legal_targets` and it is replayed rather than probed.
			# Skipping it leaves the replay a placement short and, on the levels
			# whose ideal line spends one, silently measures a different level.
			if not state.place_wild(entry[1]):
				return -1
			continue

		var options: Array[Vector3i] = state.legal_targets()
		if options.size() > 1:
			decisions += 1
			var alive: int = 0
			var snapshot: Dictionary = state.to_dict()
			for t: Vector3i in options:
				alive += _survives(state, t)
				state.restore(snapshot)
			total += (alive * 100) / options.size()

		if not state.place(entry[1]):
			return -1

	# A level with no choice in it forgives nothing, because there was nothing to
	# get wrong — reporting 100 would rank a corridor as the gentlest board there is.
	return 0 if decisions == 0 else total / decisions


## One if placing [param target] leaves a win reachable, zero otherwise. Leaves
## [param state] dirty; the caller restores it, because cloning a [GameState] per
## probe would allocate thousands of them over a sweep for no gain.
func _survives(state: GameState, target: Vector3i) -> int:
	if not state.place(target):
		return 0
	if state.status == GameState.Status.WON:
		return 1
	if state.status == GameState.Status.DEAD:
		return 0
	# UNKNOWN counts as unwinnable, the same way §8.2 step 7 treats it — a road the
	# solver could not finish is not one this may call open.
	return 1 if Solver.solve_state(state, PROBE_STATES).is_solvable() else 0


func _walk(state: GameState) -> void:
	if _capped:
		return
	_states += 1
	if _states >= MAX_STATES or Time.get_ticks_msec() > _deadline:
		_capped = true
		return
	# No placement closes more than one hop of distance to a goal, so a state
	# needing more hops than it has moves left cannot win and its whole subtree can
	# go. Without this the walk is blind and the big boards never finish.
	if state.placements + _hops_left(state) > _budget:
		return

	for target: Vector3i in state.legal_targets():
		if not state.place(target):
			continue
		_record(state)
		state.undo()
		if _capped:
			return

	if state.wild_charges > 0:
		for target: Vector3i in Rules.wild_targets(state.board, state.path):
			if not state.place_wild(target):
				continue
			_record(state)
			state.undo()
			if _capped:
				return

	# A voluntary discard is a turn but not a move, so it does not spend the
	# budget — which is why an ideal line takes every one it is given.
	if state.discards_left > 0 and state.discard():
		if state.status == GameState.Status.PLAYING and _visit(state):
			_walk(state)
		state.undo()


func _record(state: GameState) -> void:
	if state.status == GameState.Status.WON:
		var mask: int = _mask_of(state)
		_won[mask] = mini(int(_won.get(mask, 1 << 30)), state.placements)
	elif state.status == GameState.Status.PLAYING \
			and state.placements < _budget and _visit(state):
		_walk(state)


func _visit(state: GameState) -> bool:
	var mask: int = _mask_of(state)
	var inner: Dictionary = _visited.get(mask, {})
	var packed: int = (state.stream.index << 8) | (state.discards_left << 4) \
		| state.wild_charges
	if inner.has(packed) and int(inner[packed]) <= state.placements:
		return false
	inner[packed] = state.placements
	_visited[mask] = inner
	return true


## The fewest further placements this state could need: the furthest unreached
## goal, in hops, ignoring direction and gates. Optimistic on purpose — an
## over-estimate would prune a route that exists.
func _hops_left(state: GameState) -> int:
	var worst: int = 0
	for g: Vector3i in state.board.goals:
		if state.path.has(g):
			continue
		var hops: int = Rules.hops_to(state.board, state.path, g)
		if hops < 0:
			return 1 << 20
		worst = maxi(worst, hops)
	return worst


func _mask_of(state: GameState) -> int:
	var mask: int = 0
	for c: Vector3i in state.path.keys():
		mask |= 1 << int(_index_of.get(c, 0))
	return mask

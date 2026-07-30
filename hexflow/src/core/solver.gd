## Bounded optimal search over the ruleset (§8.3).
##
## Answers "is this level solvable, and in how few placements?" — the question the
## 2016 prototype never asked, which is why it shipped unwinnable boards (B2, B3).
## Nothing here mutates the live [GameState]; the solver runs on its own compact
## representation and is safe to call off the main thread for hints (§12.6).
##
## Representation: the path is a 64-bit mask over board cell indices. A radius-4
## board is 61 cells, so one integer holds any reachable path exactly, which makes
## the visited set cheap enough to explore 200 000 states in GDScript.
##
## Search: A* on `g = placements`, `h = max over goals of the cube distance from
## the nearest path cell`. §8.3 suggests *summing* over goals; a sum is not
## admissible when one placement shortens the route to two goals at once, and an
## inadmissible heuristic would return a par that is not the true optimum — which
## the star bands of §5.10 depend on. `max` is admissible (a placement reduces any
## one goal's distance by at most 1) and still strong. Logged as decision C-10.
class_name Solver

enum Status { SOLVABLE, UNSOLVABLE, UNKNOWN }

const DEFAULT_MAX_STATES := 200_000

## Two full bags. Any window of 12 consecutive bag draws contains a complete bag,
## so 12 consecutive unplaceable tiles proves every direction is blocked and the
## path is frozen for good.
const FROZEN_SKIP_LIMIT := 12

const NO_MOVE := -1

## Action kinds in [member Result.actions].
const ACTION_PLACE := 0
const ACTION_WILD := 1
const ACTION_DISCARD := 2


class Result:
	extends RefCounted
	var status: Solver.Status = Solver.Status.UNSOLVABLE
	var par: int = -1
	## Placement targets only, in order — what §17.1 stores and the hint uses.
	var moves: Array[Vector3i] = []
	## The full replayable action list: `[ACTION_*, target]` entries, including
	## the voluntary discards and wild spends that `moves` cannot express.
	var actions: Array = []
	var states_expanded: int = 0

	func is_solvable() -> bool:
		return status == Solver.Status.SOLVABLE

	func _to_string() -> String:
		return "Solver.Result(%s par=%d moves=%d states=%d)" % [
			["SOLVABLE", "UNSOLVABLE", "UNKNOWN"][int(status)], par, moves.size(), states_expanded
		]


## Compact, immutable view of a board keyed by cell index. Built once per solve.
class Topology:
	extends RefCounted
	var cells: Array[Vector3i] = []
	var index_of: Dictionary = {}                     # Vector3i -> int
	var neighbour: Array = []                         # [i][dir] -> int, or -1
	var open: PackedByteArray = PackedByteArray()
	var gate: PackedByteArray = PackedByteArray()
	var wild: PackedByteArray = PackedByteArray()
	var twin: PackedInt32Array = PackedInt32Array()   # portal twin index, or -1
	var goal_cells: Array[Vector3i] = []
	var goal_mask: int = 0
	var start_index: int = 0

	static func of(board: Board) -> Topology:
		var t := Topology.new()
		t.cells = board.cells()
		assert(t.cells.size() <= 62, "the path mask needs one bit per cell")
		for i: int in range(t.cells.size()):
			t.index_of[t.cells[i]] = i
		t.open.resize(t.cells.size())
		t.gate.resize(t.cells.size())
		t.wild.resize(t.cells.size())
		t.twin.resize(t.cells.size())
		for i: int in range(t.cells.size()):
			var c: Vector3i = t.cells[i]
			t.open[i] = 1 if board.is_open(c) else 0
			t.gate[i] = 1 if board.is_gate(c) else 0
			t.wild[i] = 1 if board.is_wild(c) else 0
			var tw := board.portal_twin(c)
			t.twin[i] = int(t.index_of.get(tw, -1)) if tw != c else -1
			var row := PackedInt32Array()
			for dir: int in Direction.ALL:
				row.append(int(t.index_of.get(c + Direction.delta(dir), -1)))
			t.neighbour.append(row)
		for g: Vector3i in board.goals:
			t.goal_cells.append(g)
			t.goal_mask |= 1 << int(t.index_of[g])
		t.start_index = int(t.index_of[board.start])
		return t

	func can_enter(mask: int, i: int) -> bool:
		if i < 0 or open[i] == 0:
			return false
		if (mask >> i) & 1 == 1:
			return false
		if gate[i] == 1 and path_neighbours(mask, i) < 2:
			return false
		return true

	func path_neighbours(mask: int, i: int) -> int:
		var n: int = 0
		var row: PackedInt32Array = neighbour[i]
		for dir: int in Direction.ALL:
			var j: int = row[dir]
			if j >= 0 and (mask >> j) & 1 == 1:
				n += 1
		return n

	## Adds [param i] and, if it is a portal, its twin. Returns the new mask.
	func enter(mask: int, i: int) -> int:
		var m: int = mask | (1 << i)
		var tw: int = twin[i]
		if tw >= 0 and open[tw] == 1:
			m |= 1 << tw
		return m

	func wild_gain(mask_before: int, mask_after: int) -> int:
		var gained: int = 0
		var added: int = mask_after & ~mask_before
		for i: int in range(cells.size()):
			if (added >> i) & 1 == 1 and wild[i] == 1:
				gained += 1
		return gained


## Solves [param level] from its opening position.
static func solve(level: Level, max_states: int = DEFAULT_MAX_STATES) -> Result:
	var topo := Topology.of(level.board)
	return solve_from(level, topo, 1 << topo.start_index, 0, level.discards, 0, max_states)


## Solves from a live position — what the hint system replays (§12.6).
static func solve_state(state: GameState, max_states: int = DEFAULT_MAX_STATES) -> Result:
	var topo := Topology.of(state.board)
	var mask: int = 0
	for c: Vector3i in state.path.keys():
		mask |= 1 << int(topo.index_of[c])
	return solve_from(
		state.level, topo, mask, state.stream.index,
		state.discards_left, state.wild_charges, max_states
	)


static func solve_from(
	level: Level,
	topo: Topology,
	start_mask: int,
	start_index: int,
	start_discards: int,
	start_wild: int,
	max_states: int
) -> Result:
	var result := Result.new()
	var stream := level.make_stream()
	var goal_count: int = topo.goal_cells.size()
	var cell_count: int = topo.cells.size()

	var max_placements: int = level.tiles.size() if level.has_fixed_tiles() else cell_count
	if level.has_budget():
		max_placements = mini(max_placements, level.budget)

	# Parallel node arrays, indexed by node id. Node id doubles as the FIFO
	# tie-break, so equal-f nodes expand in creation order and every run of the
	# solver on the same input returns the same move list (§19).
	var n_mask: Array[int] = []
	var n_index: Array[int] = []
	var n_discards: Array[int] = []
	var n_wild: Array[int] = []
	var n_g: Array[int] = []
	var n_parent: Array[int] = []
	var n_move: Array[int] = []      # cell index placed, or NO_MOVE for a discard
	var n_kind: Array[int] = []      # ACTION_*
	var n_dist: Array = []           # PackedInt32Array: min distance per goal

	var visited: Dictionary = {}     # mask -> { packed(index, discards, wild) -> best g }
	var heap: Array = []             # [f, node_id]

	var first_dist := PackedInt32Array()
	for gi: int in range(goal_count):
		first_dist.append(_min_distance(topo, start_mask, topo.goal_cells[gi]))

	_add_node(
		n_mask, n_index, n_discards, n_wild, n_g, n_parent, n_move, n_kind, n_dist,
		start_mask, start_index, start_discards, start_wild, 0, -1,
		NO_MOVE, ACTION_DISCARD, first_dist
	)
	_visit(visited, start_mask, start_index, start_discards, start_wild, 0)
	_heap_push(heap, [_heuristic(first_dist), 0])

	while not heap.is_empty():
		var id: int = (_heap_pop(heap) as Array)[1]
		var mask: int = n_mask[id]
		var g: int = n_g[id]

		if mask & topo.goal_mask == topo.goal_mask:
			result.status = Status.SOLVABLE
			result.par = g
			result.actions = _reconstruct(topo, n_parent, n_move, n_kind, id)
			result.moves = placements_of(result.actions)
			result.states_expanded = n_mask.size()
			return result

		if n_mask.size() >= max_states:
			result.status = Status.UNKNOWN
			result.states_expanded = n_mask.size()
			return result

		var index: int = n_index[id]
		var discards: int = n_discards[id]
		var wild: int = n_wild[id]

		var resolved: int = _resolve(topo, stream, mask, index)
		if resolved < 0:
			continue  # dead branch: stream exhausted, or the path is frozen
		var dir: int = stream.at(resolved)
		var next_index: int = resolved + 1

		if g < max_placements:
			# 1. Place the drawn direction. One anchor per target by injectivity.
			for i: int in range(cell_count):
				if (mask >> i) & 1 == 0:
					continue
				var t: int = (topo.neighbour[i] as PackedInt32Array)[dir]
				if not topo.can_enter(mask, t):
					continue
				_expand(
					topo, visited, heap,
					n_mask, n_index, n_discards, n_wild, n_g, n_parent, n_move, n_kind, n_dist,
					id, topo.enter(mask, t), t, ACTION_PLACE, next_index, discards, wild, g + 1
				)

			# 2. Spend a wild charge: any adjacent enterable cell (§6).
			if wild > 0:
				var seen: Dictionary = {}
				for i: int in range(cell_count):
					if (mask >> i) & 1 == 0:
						continue
					var row: PackedInt32Array = topo.neighbour[i]
					for d2: int in Direction.ALL:
						var t2: int = row[d2]
						if t2 < 0 or seen.has(t2) or not topo.can_enter(mask, t2):
							continue
						seen[t2] = true
						_expand(
							topo, visited, heap,
							n_mask, n_index, n_discards, n_wild, n_g, n_parent, n_move, n_kind, n_dist,
							id, topo.enter(mask, t2), t2, ACTION_WILD, next_index,
							discards, wild - 1, g + 1
						)

		# 3. Voluntary discard: costs a charge, never a placement, so g is unchanged.
		if discards > 0 and _visit(visited, mask, next_index, discards - 1, wild, g):
			var did: int = n_mask.size()
			_add_node(
				n_mask, n_index, n_discards, n_wild, n_g, n_parent, n_move, n_kind, n_dist,
				mask, next_index, discards - 1, wild, g, id,
				NO_MOVE, ACTION_DISCARD, n_dist[id] as PackedInt32Array
			)
			_heap_push(heap, [g + _heuristic(n_dist[did] as PackedInt32Array), did])

	result.status = Status.UNSOLVABLE
	result.states_expanded = n_mask.size()
	return result


## Burns free auto-discards (§5.7) and returns the stream index of the first
## placeable tile, or -1 when the branch is dead.
static func _resolve(topo: Topology, stream: TileStream, mask: int, index: int) -> int:
	var i: int = index
	var skipped: int = 0
	var limit: int = 1 << 30 if stream.is_fixed() else FROZEN_SKIP_LIMIT
	while skipped < limit:
		var dir: int = stream.at(i)
		if dir == Direction.NONE:
			return -1
		if _has_target(topo, mask, dir):
			return i
		skipped += 1
		i += 1
	return -1  # every direction blocked: the path is frozen for good


static func _has_target(topo: Topology, mask: int, dir: int) -> bool:
	for i: int in range(topo.cells.size()):
		if (mask >> i) & 1 == 0:
			continue
		if topo.can_enter(mask, (topo.neighbour[i] as PackedInt32Array)[dir]):
			return true
	return false


static func _expand(
	topo: Topology, visited: Dictionary, heap: Array,
	n_mask: Array[int], n_index: Array[int], n_discards: Array[int], n_wild: Array[int],
	n_g: Array[int], n_parent: Array[int], n_move: Array[int], n_kind: Array[int],
	n_dist: Array,
	parent: int, new_mask: int, target_index: int, kind: int, index: int,
	discards: int, wild: int, g: int
) -> void:
	var new_wild: int = wild + topo.wild_gain(n_mask[parent], new_mask)
	if not _visit(visited, new_mask, index, discards, new_wild, g):
		return
	var dist := _advance_distances(topo, n_dist[parent] as PackedInt32Array, n_mask[parent], new_mask)
	var id: int = n_mask.size()
	_add_node(
		n_mask, n_index, n_discards, n_wild, n_g, n_parent, n_move, n_kind, n_dist,
		new_mask, index, discards, new_wild, g, parent, target_index, kind, dist
	)
	_heap_push(heap, [g + _heuristic(dist), id])


static func _add_node(
	n_mask: Array[int], n_index: Array[int], n_discards: Array[int], n_wild: Array[int],
	n_g: Array[int], n_parent: Array[int], n_move: Array[int], n_kind: Array[int],
	n_dist: Array,
	mask: int, index: int, discards: int, wild: int, g: int,
	parent: int, move: int, kind: int, dist: PackedInt32Array
) -> void:
	n_mask.append(mask)
	n_index.append(index)
	n_discards.append(discards)
	n_wild.append(wild)
	n_g.append(g)
	n_parent.append(parent)
	n_move.append(move)
	n_kind.append(kind)
	n_dist.append(dist)


## Records a state, returning [code]false[/code] when an equal-or-better copy has
## already been queued.
static func _visit(
	visited: Dictionary, mask: int, index: int, discards: int, wild: int, g: int
) -> bool:
	var inner: Dictionary = visited.get(mask, {})
	var key: int = (index << 12) | (discards << 6) | wild
	if inner.has(key) and int(inner[key]) <= g:
		return false
	inner[key] = g
	visited[mask] = inner
	return true


## Only the newly joined cells can shorten the route to a goal, so distances
## update in O(goals) instead of a BFS per node.
static func _advance_distances(
	topo: Topology, parent_dist: PackedInt32Array, old_mask: int, new_mask: int
) -> PackedInt32Array:
	var out := parent_dist.duplicate()
	var added: int = new_mask & ~old_mask
	for i: int in range(topo.cells.size()):
		if (added >> i) & 1 == 0:
			continue
		var c: Vector3i = topo.cells[i]
		for gi: int in range(topo.goal_cells.size()):
			out[gi] = mini(out[gi], Hex.distance(c, topo.goal_cells[gi]))
	return out


static func _min_distance(topo: Topology, mask: int, goal: Vector3i) -> int:
	var best: int = 1 << 20
	for i: int in range(topo.cells.size()):
		if (mask >> i) & 1 == 1:
			best = mini(best, Hex.distance(topo.cells[i], goal))
	return best


static func _heuristic(dist: PackedInt32Array) -> int:
	var h: int = 0
	for d: int in dist:
		h = maxi(h, d)
	return h


## Walks the parent chain back to the root, producing the full action script.
## Discards are included: without them the placement list alone desynchronises
## the stream and cannot be replayed.
static func _reconstruct(
	topo: Topology, n_parent: Array[int], n_move: Array[int], n_kind: Array[int], id: int
) -> Array:
	var out: Array = []
	var cur: int = id
	while cur > 0:
		if n_move[cur] == NO_MOVE:
			out.append([ACTION_DISCARD, Vector3i.ZERO])
		else:
			out.append([n_kind[cur], topo.cells[n_move[cur]]])
		cur = n_parent[cur]
	out.reverse()
	return out


## The placement targets of a script, in order (§17.1 `solution`).
static func placements_of(script: Array) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for step: Variant in script:
		var s: Array = step
		if int(s[0]) != ACTION_DISCARD:
			out.append(s[1] as Vector3i)
	return out


## Replays a script through the real [GameState]. This is how the property test
## and the level-file validator prove a stored solution actually wins.
static func replay(level: Level, script: Array) -> GameState:
	var state := GameState.start(level)
	for step: Variant in script:
		var s: Array = step
		match int(s[0]):
			ACTION_PLACE:
				if not state.place(s[1] as Vector3i):
					return state
			ACTION_WILD:
				if not state.place_wild(s[1] as Vector3i):
					return state
			ACTION_DISCARD:
				if not state.discard():
					return state
	return state


# --- binary min-heap on [f, node_id]; node_id is the deterministic tie-break ---

static func _heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var i: int = heap.size() - 1
	while i > 0:
		var parent: int = (i - 1) >> 1
		if _heap_less(heap[i], heap[parent]):
			var tmp: Variant = heap[i]
			heap[i] = heap[parent]
			heap[parent] = tmp
			i = parent
		else:
			break


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i: int = 0
	var n: int = heap.size()
	while true:
		var l: int = 2 * i + 1
		var r: int = l + 1
		var smallest: int = i
		if l < n and _heap_less(heap[l], heap[smallest]):
			smallest = l
		if r < n and _heap_less(heap[r], heap[smallest]):
			smallest = r
		if smallest == i:
			break
		var tmp: Variant = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = tmp
		i = smallest
	return top


static func _heap_less(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	return a[1] < b[1]

## The ruleset of §5, as pure functions.
##
## Nothing here holds state. Every function takes the board and a path set and
## returns a fresh answer, which is what lets the solver (§8.3) explore
## hypothetical futures without touching the live [GameState].
##
## `path` is always a [Dictionary] used as a set: `Vector3i -> true`.
class_name Rules


## The legal targets for direction [param dir] (§5.4).
##
## For a fixed direction the map `anchor -> anchor + delta(dir)` is injective, so
## every returned target has exactly one anchor. That is what makes the player's
## interaction a single confirm on a highlighted cell, with nothing to
## disambiguate — the property the 2016 prototype lacked (B12).
##
## Returned in canonical order so callers never depend on Dictionary iteration.
static func legal_targets(board: Board, path: Dictionary, dir: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if dir < 0 or dir >= Direction.COUNT:
		return out
	var d := Direction.delta(dir)
	for anchor: Vector3i in path.keys():
		var t: Vector3i = anchor + d
		if _can_enter(board, path, t):
			out.append(t)
	return Hex.sort_cells(out)


## The anchor a given target was reached from. Unique by the injectivity above.
static func anchor_for(target: Vector3i, dir: int) -> Vector3i:
	return target - Direction.delta(dir)


## Targets legal when spending a wild charge (§6): any enterable cell adjacent to
## the path, with the direction inferred from anchor to target.
static func wild_targets(board: Board, path: Dictionary) -> Array[Vector3i]:
	var seen: Dictionary = {}
	var out: Array[Vector3i] = []
	for anchor: Vector3i in path.keys():
		for dir: int in Direction.ALL:
			var t: Vector3i = anchor + Direction.delta(dir)
			if seen.has(t):
				continue
			if _can_enter(board, path, t):
				seen[t] = true
				out.append(t)
	return Hex.sort_cells(out)


## A gate may only be entered when doing so leaves it with at least two path
## neighbours. The incoming anchor is already in `path`, so it is counted here —
## meaning the gate needs one *other* connection, i.e. it must be approached
## twice (§6).
static func gate_satisfied(board: Board, path: Dictionary, t: Vector3i) -> bool:
	if not board.is_gate(t):
		return true
	return path_neighbour_count(path, t) >= 2


static func path_neighbour_count(path: Dictionary, c: Vector3i) -> int:
	var n: int = 0
	for dir: int in Direction.ALL:
		if path.has(c + Direction.delta(dir)):
			n += 1
	return n


## Optimistic reachability: every open cell the path could still grow into if
## every future draw were perfect. Ignores direction and ignores gates, which
## makes it an upper bound — so a goal outside it is provably unreachable (§5.8).
##
## **A portal is part of the walk.** §5.5.3 joins the twin the instant the near
## end is entered, so a cell on the far side of a wall the path can never cross is
## still reachable when a portal leads there — and the flood has to say so, or
## §5.8 declares the board dead on the frame it opens. That is not hypothetical:
## it is the whole of the tutorial's portal board, where the portal is the *only*
## way across. Over-approximating is safe here by construction; this is an upper
## bound, and only a goal *outside* it is a claim.
static func reachable(board: Board, path: Dictionary) -> Dictionary:
	var seen: Dictionary = {}
	var frontier: Array[Vector3i] = []
	for c: Vector3i in path.keys():
		seen[c] = true
		frontier.append(c)
	while not frontier.is_empty():
		var c: Vector3i = frontier.pop_back()
		for dir: int in Direction.ALL:
			var n: Vector3i = c + Direction.delta(dir)
			if seen.has(n) or not board.is_open(n):
				continue
			seen[n] = true
			frontier.append(n)
		if not board.is_portal(c):
			continue
		var twin: Vector3i = board.portal_twin(c)
		if twin != c and board.is_open(twin) and not seen.has(twin):
			seen[twin] = true
			frontier.append(twin)
	return seen


## §5.6 — no graph search, just "is every goal joined". O(goals).
static func is_won(board: Board, path: Dictionary) -> bool:
	for g: Vector3i in board.goals:
		if not path.has(g):
			return false
	return true


## §5.8 — some goal has become unreachable even with perfect future draws.
static func has_unreachable_goal(board: Board, path: Dictionary) -> bool:
	var open_set: Dictionary = reachable(board, path)
	for g: Vector3i in board.goals:
		if not open_set.has(g):
			return true
	return false


## Shortest optimistic hop count from the path to [param goal], ignoring
## direction. [code]-1[/code] when unreachable. Backs the solver heuristic.
static func hops_to(board: Board, path: Dictionary, goal: Vector3i) -> int:
	if path.has(goal):
		return 0
	var dist: Dictionary = {}
	var queue: Array[Vector3i] = []
	for c: Vector3i in path.keys():
		dist[c] = 0
		queue.append(c)
	var head: int = 0
	while head < queue.size():
		var c: Vector3i = queue[head]
		head += 1
		var nd: int = int(dist[c]) + 1
		for dir: int in Direction.ALL:
			var n: Vector3i = c + Direction.delta(dir)
			if dist.has(n) or not board.is_open(n):
				continue
			dist[n] = nd
			if n == goal:
				return nd
			queue.append(n)
	return -1


static func _can_enter(board: Board, path: Dictionary, t: Vector3i) -> bool:
	if not board.has(t):
		return false
	if board.is_wall(t):
		return false
	if path.has(t):
		return false
	return gate_satisfied(board, path, t)

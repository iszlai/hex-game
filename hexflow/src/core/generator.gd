## Candidate generation with mandatory verification (§8).
##
## The 2016 prototype had no solvability guarantee at all — it blocked random
## indices `1 … size-1`, which could and did wall off the goal itself (B2, B3).
## Step 7 below makes that class of bug impossible: nothing leaves this file
## without the solver having proved it winnable and having produced its par.
##
## The only other [RandomNumberGenerator] in the game lives in [TileStream] (C2).
class_name Generator

const MAX_ATTEMPTS := 200
const DAILY_SALT := "hexflow-daily"


class Params:
	extends RefCounted
	var radius: int = 3
	var wall_count: int = 0
	var min_distance: int = 5
	var wander: int = 1
	var slack: int = 4
	var discards: int = 3
	var goal_count: int = 1
	var portal_pairs: int = 0
	var gates: int = 0
	var wilds: int = 0
	## Placement cap expressed as par + this. Negative means no budget.
	var budget_over_par: int = -1

	func duplicate_params() -> Params:
		var p := Params.new()
		p.radius = radius
		p.wall_count = wall_count
		p.min_distance = min_distance
		p.wander = wander
		p.slack = slack
		p.discards = discards
		p.goal_count = goal_count
		p.portal_pairs = portal_pairs
		p.gates = gates
		p.wilds = wilds
		p.budget_over_par = budget_over_par
		return p


## The §8.4 difficulty table, one entry per chapter (1-based).
static func chapter_params(chapter: int, level_index: int = 1) -> Params:
	var p := Params.new()
	# Difficulty ramps linearly across the 12 levels of a chapter, in integer
	# arithmetic so no float ever enters `src/core/` (§19).
	var t: int = clampi(level_index - 1, 0, 11)
	match chapter:
		1:
			p.radius = 2 if level_index <= 4 else 3
			p.wall_count = _ramp(0, 2, t)
			p.min_distance = _ramp(3, 5, t)
			p.wander = _ramp(0, 1, t)
			p.slack = 4
			p.discards = 3
		2:
			p.radius = 3
			p.wall_count = _ramp(4, 8, t)
			p.min_distance = _ramp(5, 6, t)
			p.wander = _ramp(1, 2, t)
			p.slack = 4
			p.discards = 3
		3:
			p.radius = 3
			p.wall_count = _ramp(5, 9, t)
			p.min_distance = _ramp(5, 6, t)
			p.wander = 2
			p.slack = 5
			p.discards = 2
			p.goal_count = 2 if level_index <= 8 else 3
		4:
			p.radius = 3
			p.wall_count = _ramp(6, 10, t)
			p.min_distance = 6
			p.wander = _ramp(2, 3, t)
			p.slack = 5
			p.discards = 2
			p.portal_pairs = 1
			p.gates = 1 if level_index <= 6 else 2
		5:
			p.radius = 3 if level_index <= 6 else 4
			p.wall_count = _ramp(8, 14, t)
			p.min_distance = _ramp(6, 7, t)
			p.wander = 3
			p.slack = 3
			p.discards = 2 if level_index <= 6 else 0
			p.goal_count = 2
			p.portal_pairs = 1
			p.gates = 1
			p.wilds = 1
			p.budget_over_par = 2
	return p


static func endless_params(goals_reached: int) -> Params:
	var p := Params.new()
	p.radius = 3
	p.wall_count = goals_reached
	p.min_distance = 4
	p.wander = 2
	p.slack = 0          # an infinite bag; slack is meaningless
	p.discards = 3
	return p


static func daily_params() -> Params:
	var p := Params.new()
	p.radius = 3
	p.wall_count = 7
	p.min_distance = 6
	p.wander = 2
	p.slack = 6
	p.discards = 2
	p.goal_count = 2
	return p


## §7.3 — one puzzle per UTC day, identical for every client on that date.
## The hash is implemented locally rather than via any engine hash, whose
## stability across versions is not guaranteed (§19).
static func daily_seed(utc_date: String) -> int:
	return fnv1a_32(DAILY_SALT + utc_date)


static func daily(utc_date: String) -> Level:
	var lv := generate(daily_seed(utc_date), daily_params())
	if lv != null:
		lv.id = "daily_" + utc_date
	return lv


## FNV-1a over UTF-8 bytes, 32-bit. Chosen for being fully specified and
## trivially reproducible in any language, so a future companion tool agrees.
static func fnv1a_32(s: String) -> int:
	var h: int = 0x811C9DC5
	for b: int in s.to_utf8_buffer():
		h = (h ^ b) & 0xFFFFFFFF
		h = (h * 0x01000193) & 0xFFFFFFFF
	return h


## Generates a verified level, or [code]null[/code] when even relaxed parameters
## fail. Never returns a candidate that skipped verification.
static func generate(p_seed: int, params: Params, max_states: int = Solver.DEFAULT_MAX_STATES) -> Level:
	var active := params.duplicate_params()
	var attempt: int = 0
	while attempt < MAX_ATTEMPTS:
		var candidate := _build_candidate(p_seed + attempt, active)
		if candidate != null:
			# Step 7: verification is not optional. A candidate the solver cannot
			# prove winnable is rejected, including an UNKNOWN from the state cap.
			var result := Solver.solve(candidate, max_states)
			if result.is_solvable():
				candidate.par = result.par
				candidate.solution = result.moves
				candidate.solution_script = result.actions
				candidate.generator_seed = p_seed + attempt
				if params.budget_over_par >= 0:
					candidate.budget = result.par + params.budget_over_par
				return candidate
		attempt += 1
		# Relax gradually: walls are the usual cause of an over-constrained board.
		if attempt % 50 == 0 and active.wall_count > 0:
			active.wall_count -= 1
	return null


static func _build_candidate(p_seed: int, params: Params) -> Level:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed

	var all: Array[Vector3i] = Hex.hexagon(params.radius)
	var all_set: Dictionary = {}
	for c: Vector3i in all:
		all_set[c] = true

	# 2. Start on the outer ring; goals far from it and from each other.
	var rim: Array[Vector3i] = Hex.ring(params.radius)
	var start: Vector3i = rim[rng.randi_range(0, rim.size() - 1)]
	var goals: Array[Vector3i] = []
	for _i: int in range(params.goal_count):
		var pick: Array[Vector3i] = _pick_goal(rng, all, start, goals, params.min_distance)
		if pick.is_empty():
			return null
		goals.append(pick[0])

	# 3. Carve a reserved solution route to each goal. Later goals may branch off
	#    any cell already reserved, which is what makes multi-goal levels forks
	#    rather than detours.
	var reserved: Dictionary = {start: true}
	var route_dirs: Array[int] = []
	for g: Vector3i in goals:
		var origin := _pick_branch_origin(rng, reserved, g)
		var leg := _carve(rng, all_set, reserved, origin, g, params.wander)
		if leg.is_empty():
			return null
		route_dirs.append_array(leg)

	# 4. Walls, from the cells the solution does not need.
	var free: Array[Vector3i] = []
	for c: Vector3i in all:
		if not reserved.has(c):
			free.append(c)
	_shuffle(rng, free)
	var walls: Array[Vector3i] = []
	for i: int in range(mini(params.wall_count, free.size())):
		walls.append(free[i])
	var spare: Array[Vector3i] = free.slice(walls.size())

	# 5. Modifiers, on non-reserved cells only. Gates deliberately never sit on
	#    the reserved route: a gate on the route would need a verified second
	#    approach, and §1.1 C7 says take the simplest option. Logged as C-11.
	var cursor: int = 0
	var portal_pairs: Array = []
	for _i: int in range(params.portal_pairs):
		if cursor + 1 >= spare.size():
			break
		portal_pairs.append([spare[cursor], spare[cursor + 1]])
		cursor += 2
	var gates: Array[Vector3i] = []
	for _i: int in range(params.gates):
		if cursor >= spare.size():
			break
		gates.append(spare[cursor])
		cursor += 1
	var wilds: Array[Vector3i] = []
	for _i: int in range(params.wilds):
		if cursor >= spare.size():
			break
		wilds.append(spare[cursor])
		cursor += 1

	# 6. Tiles: the route's own directions, plus slack. Decoys are interleaved
	#    only up to the discard budget, so a solution provably survives them;
	#    the rest pad the tail and give the player room to recover from a
	#    mistake. Step 7 still has the final say.
	var tiles: Array[int] = route_dirs.duplicate()
	if params.slack > 0:
		var interleave: int = mini(params.discards, params.slack)
		for _i: int in range(interleave):
			var at: int = rng.randi_range(0, tiles.size())
			tiles.insert(at, rng.randi_range(0, Direction.COUNT - 1))
		for _i: int in range(params.slack - interleave):
			tiles.append(rng.randi_range(0, Direction.COUNT - 1))

	var board := Board.build(params.radius, start, goals, walls, portal_pairs, gates, wilds)
	var level := Level.build(board, tiles, p_seed)
	level.discards = params.discards
	return level


static func _pick_goal(
	rng: RandomNumberGenerator,
	all: Array[Vector3i],
	start: Vector3i,
	chosen: Array[Vector3i],
	min_distance: int
) -> Array[Vector3i]:
	var candidates: Array[Vector3i] = []
	for c: Vector3i in all:
		if Hex.distance(start, c) < min_distance:
			continue
		var ok: bool = true
		for g: Vector3i in chosen:
			if Hex.distance(g, c) < 3:
				ok = false
				break
		if ok:
			candidates.append(c)
	if candidates.is_empty():
		return [] as Array[Vector3i]
	return [candidates[rng.randi_range(0, candidates.size() - 1)]] as Array[Vector3i]


## The cell a branch grows from: the reserved cell closest to the new goal, so
## a second goal forks off the trunk rather than restarting from the start.
static func _pick_branch_origin(
	rng: RandomNumberGenerator, reserved: Dictionary, goal: Vector3i
) -> Vector3i:
	var best: Vector3i = Vector3i.ZERO
	var best_d: int = 1 << 20
	var ties: Array[Vector3i] = []
	for c: Vector3i in Hex.sort_cells(_keys(reserved)):
		var d: int = Hex.distance(c, goal)
		if d < best_d:
			best_d = d
			ties = [c]
		elif d == best_d:
			ties.append(c)
	best = ties[rng.randi_range(0, ties.size() - 1)]
	return best


## A random walk from [param origin] to [param goal], biased toward the goal,
## wandering [param wander] extra steps. Returns the direction of each step and
## marks every visited cell reserved. Empty on failure.
static func _carve(
	rng: RandomNumberGenerator,
	all_set: Dictionary,
	reserved: Dictionary,
	origin: Vector3i,
	goal: Vector3i,
	wander: int
) -> Array[int]:
	var dirs: Array[int] = []
	var current: Vector3i = origin
	var wander_left: int = wander
	var guard: int = 0
	while current != goal:
		guard += 1
		if guard > 200:
			return [] as Array[int]
		var closer: Array[int] = []
		var sideways: Array[int] = []
		var d_now: int = Hex.distance(current, goal)
		for dir: int in Direction.ALL:
			var n: Vector3i = current + Direction.delta(dir)
			if not all_set.has(n) or reserved.has(n):
				continue
			var d: int = Hex.distance(n, goal)
			if d < d_now:
				closer.append(dir)
			elif d == d_now:
				sideways.append(dir)
		var pool: Array[int] = closer
		if wander_left > 0 and not sideways.is_empty() and rng.randi_range(0, 1) == 0:
			pool = sideways
			wander_left -= 1
		if pool.is_empty():
			pool = closer if not closer.is_empty() else sideways
		if pool.is_empty():
			return [] as Array[int]
		var chosen: int = pool[rng.randi_range(0, pool.size() - 1)]
		current += Direction.delta(chosen)
		reserved[current] = true
		dirs.append(chosen)
	return dirs


## Canonical descending-index Fisher-Yates, matching [TileStream] (§19).
static func _shuffle(rng: RandomNumberGenerator, arr: Array[Vector3i]) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector3i = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _keys(d: Dictionary) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for k: Variant in d.keys():
		out.append(k as Vector3i)
	return out


## Integer linear ramp from [param a] at step 0 to [param b] at step 11,
## rounded half-up without touching a float.
static func _ramp(a: int, b: int, step: int) -> int:
	return a + ((b - a) * step * 2 + 11) / 22

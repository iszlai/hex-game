## Fill: the tile sequence for a hand-drawn board (MAP-EDITOR §4.4).
##
## **A board is not a level.** §5.3 needs `tiles` — the fixed sequence of
## directions the player is dealt — and you cannot paint that. A board with the
## wrong sequence is unsolvable no matter how good it looks, which is the reason a
## naive hex editor produces unplayable levels.
##
## So Fill **sweeps seeds and keeps the best one**, exactly as
## `tools/author_levels.gd` does for whole levels. For each seed it carves a route
## through the board, turns that route's directions into a sequence the way
## [Generator]'s step 6 does — padded and interleaved with decoys — then measures
## the resulting level with [LevelMetrics] and scores it against the slot's place
## on the curve.
##
## That the sweep is over *deals* and not over boards is the whole point. The same
## board with two different deals is two different levels: one where the tile you
## need arrives a turn early and one where it arrives a turn late. Taking the first
## sequence that happened to work would throw that away, and the author would be
## left tuning the board to compensate for a deal nobody chose.
##
## Not part of the shipped game.
class_name TileFiller
extends RefCounted

## How many deals are tried. Every one is generated *and measured*, and measuring
## is seconds, so this is the whole cost of a Fill. The editor yields between
## seeds so the count is also how long an author waits.
const SEEDS := 10

## Spread between attempts, so consecutive seeds are not consecutive streams.
## `author_levels.gd`'s number, for the same reason.
const SEED_STRIDE := 7919

## How far the carve may retry before calling a goal unreachable.
const CARVE_GUARD := 200


## One measured deal. The board is the author's; this is the part Fill chose.
class Deal:
	extends RefCounted
	var seed: int = 0
	var tiles: Array[int] = []
	var par: int = 0
	var routes: int = -1
	var forgiving: int = -1
	var score: int = 1 << 30
	var solution: Array[Vector3i] = []
	var solution_script: Array = []


## Tries one deal. Returns [code]null[/code] when this seed cannot produce a level
## worth keeping — no route carved, the solver could not prove it winnable, or the
## metrics could not rank it.
##
## An unrankable candidate is **rejected**, not kept with a shrug: §8.2 step 7
## treats the solver's UNKNOWN as a rejection, and a level nobody can score is a
## level nobody should ship (C-33).
##
## [param best_score] is the score to beat, used only to skip the expensive half.
## Forgiveness runs the solver once per alternative at every branching turn; the
## route term of the score cannot fall when forgiveness is added, so a candidate
## already behind on routes cannot come back and need not be measured.
static func try_seed(draft: MapDraft, attempt: int, best_score: int) -> Deal:
	var params := Generator.chapter_params(draft.chapter, draft.index)
	var seed_value: int = base_seed(draft) + attempt * SEED_STRIDE
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var route: Array[int] = carve(draft, rng, params.wander)
	if route.is_empty():
		return null

	var deal := Deal.new()
	deal.seed = seed_value
	deal.tiles = _pad(route, rng, params.slack, draft.discards)

	var level := draft.to_level()
	if level == null:
		return null
	level.tiles = deal.tiles
	level.seed = seed_value

	var result := Solver.solve(level)
	if not result.is_solvable():
		return null
	deal.par = result.par
	deal.solution = result.moves
	deal.solution_script = result.actions

	level.par = result.par
	level.solution = result.moves
	level.solution_script = result.actions

	var metrics := LevelMetrics.new()
	deal.routes = metrics.routes_at_ideal(level)
	if deal.routes < 0:
		return null
	var want_forgiving: int = DifficultyCurve.forgiving_for(draft.chapter, draft.index)
	if DifficultyCurve.distance(draft.chapter, draft.index, deal.routes, want_forgiving) >= best_score:
		return null
	deal.forgiving = metrics.forgiveness(level)
	if deal.forgiving < 0:
		return null
	deal.score = DifficultyCurve.distance(
		draft.chapter, draft.index, deal.routes, deal.forgiving)
	return deal


## The seed a Fill starts from. Derived from the slot rather than from the clock,
## so re-running Fill on an unchanged board reproduces the same ten deals and
## therefore the same winner — which is what makes `generator.seed` a live
## provenance field rather than a decoration (§10 Q4).
static func base_seed(draft: MapDraft) -> int:
	return Generator.fnv1a_32("hexflow:edit:c%d:l%d" % [draft.chapter, draft.index])


## A route from the start through every goal, as the directions of its steps.
##
## This is [Generator]'s carve in shape and not by reuse, because the two want
## different cells. The generator carves *first* and places walls in what is left,
## so nothing can be in its way; here the author has already placed everything, so
## the route has to route around it.
##
## **Gates are avoided.** §6's gate needs two path neighbours before it opens, and
## a single-file carve arrives with one — so a route drawn through a gate would
## describe a sequence that is not legal to play. The solver still has the final
## say and may well find a shorter line that does open one; what this must not do
## is *depend* on one.
static func carve(draft: MapDraft, rng: RandomNumberGenerator, wander: int) -> Array[int]:
	var open: Dictionary = {}
	for c: Variant in draft.cells.keys():
		var kind := draft.content_at(c as Vector3i)
		if kind != MapDraft.Content.WALL and kind != MapDraft.Content.GATE:
			open[c] = true
	if draft.start == Hex.NONE or not open.has(draft.start):
		return [] as Array[int]

	var reserved: Dictionary = {draft.start: true}
	var dirs: Array[int] = []
	for goal: Vector3i in draft.goals():
		if not open.has(goal):
			return [] as Array[int]
		var leg := _walk(rng, open, reserved, _branch_origin(rng, reserved, goal), goal, wander)
		if leg.is_empty() and goal != draft.start:
			return [] as Array[int]
		dirs.append_array(leg)
	return dirs


## The reserved cell closest to the new goal, so a second goal forks off the trunk
## rather than restarting from the start — which is what makes a multi-goal level
## a fork rather than two detours.
static func _branch_origin(
	rng: RandomNumberGenerator, reserved: Dictionary, goal: Vector3i
) -> Vector3i:
	var best: int = 1 << 20
	var ties: Array[Vector3i] = []
	for c: Vector3i in Hex.sort_cells(_keys(reserved)):
		var d: int = Hex.distance(c, goal)
		if d < best:
			best = d
			ties = [c]
		elif d == best:
			ties.append(c)
	return ties[rng.randi_range(0, ties.size() - 1)]


## A random walk from [param origin] to [param goal], biased toward it and
## wandering [param wander] extra steps. Marks every cell it visits reserved, so a
## later leg cannot cross back over this one and make the route self-touching.
static func _walk(
	rng: RandomNumberGenerator,
	open: Dictionary,
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
		if guard > CARVE_GUARD:
			return [] as Array[int]
		var closer: Array[int] = []
		var sideways: Array[int] = []
		var d_now: int = Hex.distance(current, goal)
		for dir: int in Direction.ALL:
			var n: Vector3i = current + Direction.delta(dir)
			if not open.has(n) or reserved.has(n):
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


## [Generator] step 6, on a route that was carved rather than generated. Decoys
## are interleaved only up to the discard budget, so the solution provably
## survives them; the rest pad the tail and give the player room to recover.
static func _pad(
	route: Array[int], rng: RandomNumberGenerator, slack: int, discards: int
) -> Array[int]:
	var tiles: Array[int] = route.duplicate()
	if slack <= 0:
		return tiles
	var interleave: int = mini(discards, slack)
	for _i: int in range(interleave):
		var at: int = rng.randi_range(0, tiles.size())
		tiles.insert(at, rng.randi_range(0, Direction.COUNT - 1))
	for _i: int in range(slack - interleave):
		tiles.append(rng.randi_range(0, Direction.COUNT - 1))
	return tiles


## Parses §4.4's text field: direction names, separated by anything that is not
## one. Returns [code]null[/code] on the first token that is not a direction, so
## a typo is reported rather than silently dropped — a sequence one tile short is
## a different level, and a *silently* different level is the whole class of bug
## this tool exists to avoid.
static func parse(text: String) -> Array:
	var out: Array[int] = []
	for token: String in text.to_upper().replace(",", " ").split(" ", false):
		var dir: int = Direction.from_name(token.strip_edges())
		if dir == Direction.NONE:
			return [null, "'%s' is not a direction" % token]
		out.append(dir)
	return [out, ""]


static func to_text(tiles: Array[int]) -> String:
	var names: PackedStringArray = PackedStringArray()
	for t: int in tiles:
		names.append(Direction.name_of(t))
	return " ".join(names)


static func _keys(d: Dictionary) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for k: Variant in d.keys():
		out.append(k as Vector3i)
	return out

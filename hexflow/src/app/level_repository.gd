## Loads, validates and caches frozen campaign levels (§17.1).
##
## Campaign levels are **data**, never generated at runtime: a re-seed on load
## would change the tile sequence and silently invalidate every stored par, star
## and comparison (§9, §27). The generator produces these files once, offline,
## and `tools/author_levels.gd` writes them.
##
## Not an autoload — §16.5 fixes the singleton list at six. Callers use the static
## API and the shared cache.
class_name LevelRepository

const SCHEMA := 1
const ROOT := "res://src/data/levels"
const CHAPTERS := 5
const LEVELS_PER_CHAPTER := 12

## `chapter_N/level_MM.json` id -> Level.
static var _cache: Dictionary = {}


static func path_for(chapter: int, index: int) -> String:
	return "%s/chapter_%d/level_%02d.json" % [ROOT, chapter, index]


static func id_for(chapter: int, index: int) -> String:
	return "c%d_l%02d" % [chapter, index]


## The inverse of [method id_for], for anything that stored an id rather than a
## pair — a resumed run (§18.2) is the first, and a level-select deep link will be
## the next. Returns `null` for anything that is not a campaign id, so a stale or
## hand-edited save cannot make the loader guess.
static func load_by_id(id: String) -> Level:
	var at: Vector2i = locate(id)
	if at.x <= 0:
		return null
	return load_level(at.x, at.y)


## `c3_l07` → `(3, 7)`, or `(0, 0)` for anything that is not one.
static func locate(id: String) -> Vector2i:
	var parts: PackedStringArray = id.split("_")
	if parts.size() != 2 or not parts[0].begins_with("c") or not parts[1].begins_with("l"):
		return Vector2i.ZERO
	var chapter: String = parts[0].substr(1)
	var index: String = parts[1].substr(1)
	if not chapter.is_valid_int() or not index.is_valid_int():
		return Vector2i.ZERO
	return Vector2i(int(chapter), int(index))


static func exists(chapter: int, index: int) -> bool:
	return ResourceLoader.exists(path_for(chapter, index)) \
		or FileAccess.file_exists(path_for(chapter, index))


## Loads a campaign level, or [code]null[/code] when it is missing or invalid.
## Debug builds fail loudly on a validation problem; release builds skip the
## level and log, so one bad file can never brick a player's campaign (§17.1).
static func load_level(chapter: int, index: int) -> Level:
	var key := id_for(chapter, index)
	if _cache.has(key):
		return _cache[key]
	var path := path_for(chapter, index)
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("level %s is not valid JSON" % path)
		return null

	var level := from_dict(parsed as Dictionary)
	if level == null:
		return null
	var problems := level.validate()
	if not problems.is_empty():
		var message := "level %s failed validation: %s" % [path, ", ".join(problems)]
		assert(false, message)
		push_error(message)
		return null
	_cache[key] = level
	return level


static func clear_cache() -> void:
	_cache.clear()


## Something playable when the campaign data is missing or unreadable — the
## reference board of Appendix A, whose straight six-step solution always works.
##
## §17.1 says one bad file must never brick a player's campaign, and the honest
## end of that sentence is that the *whole tree* being unreadable must not either:
## a fresh install with a failed download, or a Steam verify mid-flight, should
## reach a board and a warning rather than a screen with nothing on it. It lived
## in `boot.gd` until the boot screen stopped opening levels; it is here now
## because knowing what to do when a level file will not load is this file's job.
static func fallback_level() -> Level:
	push_warning("campaign data unavailable; falling back to the reference board")
	var board := Board.build(3, Vector3i(-3, 0, 3), [Vector3i(3, 0, -3)] as Array[Vector3i])
	var six_ne: Array[int] = [
		Direction.NE, Direction.NE, Direction.NE, Direction.NE, Direction.NE, Direction.NE
	]
	var level := Level.build(board, six_ne)
	level.id = "fallback"
	level.par = 6
	return level


## Deserialises a level file. Rejects an unknown higher schema with a clear
## error rather than guessing at its meaning.
static func from_dict(d: Dictionary) -> Level:
	var schema: int = int(d.get("schema", 0))
	if schema > SCHEMA:
		push_error("level schema %d is newer than this build understands (%d)" % [schema, SCHEMA])
		return null

	var walls: Array[Vector3i] = _cells(d.get("walls", []))
	var gates: Array[Vector3i] = _cells(d.get("gates", []))
	var wilds: Array[Vector3i] = _cells(d.get("wilds", []))
	var portals: Array = []
	for pair: Variant in d.get("portals", []):
		var p: Array = pair
		portals.append([Hex.from_array(p[0] as Array), Hex.from_array(p[1] as Array)])

	var board := Board.build(
		int(d.get("radius", 3)),
		Hex.from_array(d.get("start", [0, 0, 0]) as Array),
		_cells(d.get("goals", [])),
		walls, portals, gates, wilds
	)

	var tiles: Array[int] = []
	for n: Variant in d.get("tiles", []):
		tiles.append(Direction.from_name(str(n)))

	var level := Level.build(board, tiles, int(d.get("seed", 0)))
	level.id = str(d.get("id", ""))
	level.chapter = int(d.get("chapter", 0))
	level.index = int(d.get("index", 0))
	level.discards = int(d.get("discards", 3))
	var budget: Variant = d.get("budget")
	level.budget = int(budget) if budget != null else Level.NO_BUDGET
	level.par = int(d.get("par", 0))
	level.solution = _cells(d.get("solution", []))
	level.solution_script = _script_from(d.get("solution_script", []))
	var provenance: Dictionary = d.get("generator", {})
	level.generator_seed = int(provenance.get("seed", 0))
	level.generator_params_version = int(provenance.get("params_version", 1))
	return level


static func to_dict(level: Level) -> Dictionary:
	var walls: Array = []
	for w: Vector3i in level.board.walls():
		walls.append(Hex.to_array(w))
	var goals: Array = []
	for g: Vector3i in level.board.goals:
		goals.append(Hex.to_array(g))
	var portals: Array = []
	for pair: Variant in level.board.portal_pairs():
		var p: Array = pair
		portals.append([Hex.to_array(p[0]), Hex.to_array(p[1])])
	var gates: Array = []
	for g: Vector3i in level.board.cells_with_flag(Board.F_GATE):
		gates.append(Hex.to_array(g))
	var wilds: Array = []
	for w: Vector3i in level.board.cells_with_flag(Board.F_WILD):
		wilds.append(Hex.to_array(w))
	var tiles: Array = []
	for t: int in level.tiles:
		tiles.append(Direction.name_of(t))
	var solution: Array = []
	for s: Vector3i in level.solution:
		solution.append(Hex.to_array(s))
	var script: Array = []
	for step: Variant in level.solution_script:
		var s: Array = step
		script.append([int(s[0]), Hex.to_array(s[1] as Vector3i)])

	return {
		"schema": SCHEMA,
		"id": level.id,
		"chapter": level.chapter,
		"index": level.index,
		"radius": level.board.radius,
		"start": Hex.to_array(level.board.start),
		"goals": goals,
		"walls": walls,
		"portals": portals,
		"gates": gates,
		"wilds": wilds,
		"tiles": tiles,
		"discards": level.discards,
		"budget": level.budget if level.has_budget() else null,
		"par": level.par,
		"solution": solution,
		"solution_script": script,
		"generator": {
			"seed": level.generator_seed,
			"params_version": level.generator_params_version,
		},
	}


## The expensive half of §17.1 validation: re-run the solver and confirm the
## stored par and solution still hold. Used by the level-file property test and
## by the authoring tool, not on the hot load path.
static func verify(level: Level) -> Array[String]:
	var problems := level.validate()
	var result := Solver.solve(level)
	if not result.is_solvable():
		problems.append("solver could not prove %s solvable" % level.id)
		return problems
	if result.par != level.par:
		problems.append("stored par %d but solver says %d" % [level.par, result.par])
	var replayed := Solver.replay(level, level.solution_script)
	if replayed.status != GameState.Status.WON:
		problems.append("the stored solution does not reach WON")
	return problems


static func _cells(list: Variant) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for a: Variant in (list as Array):
		out.append(Hex.from_array(a as Array))
	return out


static func _script_from(list: Variant) -> Array:
	var out: Array = []
	for step: Variant in (list as Array):
		var s: Array = step
		out.append([int(s[0]), Hex.from_array(s[1] as Array)])
	return out

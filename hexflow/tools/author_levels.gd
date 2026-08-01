extends SceneTree
## Authoring tool: generates, verifies and freezes the campaign level files (§9).
##
##     Godot --headless --path . -s res://tools/author_levels.gd -- [chapter]
##
## Sweeps a seed range per level slot, keeps the first candidate whose par falls
## in the chapter's target band, and writes it to
## `src/data/levels/chapter_N/level_MM.json`. Generated levels are then **frozen
## data** — never regenerated at runtime, never re-seeded on load.
##
## Not part of the shipped game. Autoloads are unavailable in a `-s` MainLoop
## script, so everything here goes through the pure core and the static
## [LevelRepository] API.

## Seeds tried per slot, per shape. Every one is generated *and measured*, so this
## is the sweep's whole cost: 60 slots x shapes x this, at a few hundred
## milliseconds each.
const SEEDS_PER_SLOT := 10
const OUT_ROOT := "res://src/data/levels"

## What the winning candidate scored, for the line printed about it. Held here
## rather than returned because `_author` already returns the level and a second
## return value would be a Dictionary nobody reads twice.
## Names already issued in this run, so two slots cannot collide.
var _minted: Dictionary = {}

var _scored_routes: int = -1
var _scored_forgiving: int = -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var only_chapter: int = int(args[0]) if args.size() > 0 else 0

	var written: int = 0
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		if only_chapter > 0 and chapter != only_chapter:
			continue
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path("%s/chapter_%d" % [OUT_ROOT, chapter])
		)
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			var level := _author(chapter, index)
			if level == null:
				push_error("chapter %d level %d: no candidate met its par band" % [chapter, index])
				continue
			_write(level)
			written += 1
			print("c%d l%02d  %-9s ideal %2d  routes %3d (want %2d)  forgiving %3d (want %3d)  walls %2d  goals %d" % [
				chapter, index, level.board.shape, level.par,
				_scored_routes, DifficultyCurve.routes_for(chapter, index),
				_scored_forgiving, DifficultyCurve.forgiving_for(chapter, index),
				level.board.walls().size(), level.board.goals.size()
			])
	print("wrote %d level files" % written)
	quit()


## Picks the candidate closest to the slot's place on the curve (C-33).
##
## The old sweep kept the first candidate whose **par** landed in a band, and par
## measures length. Three measurements say that is the wrong key: the shipped
## sixty have no difficulty curve in either dial, and chapter 4 — the one selected
## for the shortest levels — turned out to be the *widest* and most forgiving
## chapter in the game.
##
## So every candidate is generated **and measured**, and the best-scoring one
## wins rather than the first acceptable one. Two consequences worth stating:
## the sweep is far slower than it was, because measuring is the expensive part
## and it now happens per candidate rather than never; and a candidate the metrics
## cannot score inside their budget is **rejected outright**, because a level
## nobody can rank is a level nobody should ship.
func _author(chapter: int, index: int) -> Level:
	var base_seed: int = Generator.fnv1a_32("hexflow:c%d:l%d" % [chapter, index])
	var metrics := LevelMetrics.new()
	var best: Level = null
	var best_score: int = 1 << 30
	var fallback: Level = null

	for shape: Variant in DifficultyCurve.shapes_for(chapter):
		var params := Generator.chapter_params(chapter, index)
		params.shape = str(shape)
		params.shape_arg = _shape_arg(str(shape))
		params.radius = _shape_size(str(shape), params.radius)

		for attempt: int in range(SEEDS_PER_SLOT):
			var level := Generator.generate(base_seed + attempt * 7919, params)
			if level == null:
				continue
			if fallback == null:
				fallback = level
			var routes: int = metrics.routes_at_ideal(level)
			if routes < 0:
				continue   # unmeasurable, therefore unrankable, therefore not shipped

			# Forgiveness is the expensive half — it runs the solver once per
			# alternative at every branching turn — so it is only measured for a
			# candidate whose route count alone could still win. The route term of
			# the score cannot fall when forgiveness is added, so a candidate
			# already behind on routes cannot come back.
			if DifficultyCurve.distance(chapter, index, routes,
					DifficultyCurve.forgiving_for(chapter, index)) >= best_score:
				continue
			var forgiving: int = metrics.forgiveness(level)
			if forgiving < 0:
				continue
			var score: int = DifficultyCurve.distance(chapter, index, routes, forgiving)
			if score < best_score:
				best_score = score
				best = level
				_scored_routes = routes
				_scored_forgiving = forgiving

	if best != null:
		return _stamp(best, chapter, index)
	# Any verified level beats no level: the curve is a preference, solvability is
	# the requirement (§8.2 step 7).
	_scored_routes = -1
	_scored_forgiving = -1
	return _stamp(fallback, chapter, index) if fallback != null else null


## Each shape's second parameter, and the size that keeps it inside the solver's
## 61-cell ceiling while still being worth playing on (C-32).
## A permanent name for a level. `randi()` is fine here — C2 bans it in `src/`,
## where determinism is the requirement; this is an authoring step whose output is
## committed and read back as frozen data.
func _mint() -> String:
	var chars := "abcdefghijklmnopqrstuvwxyz0123456789"
	while true:
		var out: String = ""
		for _i: int in range(10):
			out += chars[randi() % chars.length()]
		if not _minted.has(out):
			_minted[out] = true
			return out
	return ""


func _shape_arg(shape: String) -> int:
	match shape:
		"ring": return 1
		"corridor": return 4
		"hourglass": return 3
		"zed": return 3          # rows between the bars
		_: return 0


func _shape_size(shape: String, radius: int) -> int:
	match shape:
		"triangle": return radius + 3   # side, not radius: side 6 is 28 cells
		"corridor": return radius + 6   # length, and the arg is its width
		"zed": return radius + 4        # the length of each bar
		_: return radius


func _stamp(level: Level, chapter: int, index: int) -> Level:
	# A fresh uid, never the one already at this slot (C-34). The sweep produces a
	# *different level*, and inheriting the old name would hand a player's stars to
	# a board they have never seen — which is the exact bug uids exist to prevent,
	# arriving from the other direction. The map editor does the opposite and keeps
	# the uid, because there it is the same level being tweaked.
	level.uid = _mint()
	level.authored_routes = _scored_routes
	level.authored_forgiving = _scored_forgiving
	level.id = LevelRepository.id_for(chapter, index)
	level.chapter = chapter
	level.index = index
	return level


func _write(level: Level) -> void:
	var path := LevelRepository.path_for(level.chapter, level.index)
	var problems := LevelRepository.verify(level)
	if not problems.is_empty():
		push_error("%s failed verification: %s" % [path, ", ".join(problems)])
		return
	# Through the one writer, so the sweep and the map editor produce byte-
	# comparable files (MAP-EDITOR §6). This used to write unsorted keys and no
	# trailing newline, which meant every `make levels` reformatted the whole
	# campaign on top of whatever it actually changed.
	LevelFile.write(level, path)

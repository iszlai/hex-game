extends SceneTree
## Measurement tool: what would granting the player discard slack actually cost?
##
##     Godot --headless --path . -s res://tools/measure_slack.gd -- [extra]
##
## D1 of `docs/DESIGN-GAPS.md` asks for a second scoring axis in tension with
## brevity, and the obvious candidate — "finish with a discard unspent" — is dead
## on the shipped levels: the solver's optimal line spends the level's *entire*
## discard budget on 44 of 60, and 6 levels grant none at all. So the axis has
## nothing to measure.
##
## The cheap fix would be to grant one more discard per level rather than
## re-author the boards. But a discard is not free to the *par*: more discards
## means more reachable lines, so the solver optimum can drop, and a par that
## moves silently invalidates every star already earned on that level.
##
## This answers the only question that matters before choosing: **on how many
## levels does granting slack move par?** Boards and tile sequences are never
## touched — only `discards` is raised, and the level is re-solved.
##
## Not part of the shipped game.

const OUT_ROOT := "res://src/data/levels"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var extra: int = int(args[0]) if args.size() > 0 else 1

	print("granting +%d discard(s); boards and tile sequences unchanged\n" % extra)
	print("ch lv | discards | par | par+slack | optimum spends | slack left")

	var moved: int = 0
	var total: int = 0
	var now_has_slack: int = 0
	var unsolvable: int = 0

	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			var level := LevelRepository.load_level(chapter, index)
			if level == null:
				continue
			total += 1
			var before: int = level.par
			var granted: int = level.discards + extra
			level.discards = granted

			var result := Solver.solve(level)
			if result.status != Solver.Status.SOLVABLE:
				unsolvable += 1
				print("%2d %2d | %8d | %3d | %9s | %14s | %s"
					% [chapter, index, granted, before, "?", "?", "UNSOLVED"])
				continue

			var spends: int = _discards_in(result.actions)
			var left: int = granted - spends
			if left > 0:
				now_has_slack += 1
			if result.par != before:
				moved += 1
			print("%2d %2d | %8d | %3d | %9d | %14d | %d%s"
				% [chapter, index, granted, before, result.par, spends, left,
					"   <-- par moved" if result.par != before else ""])

	print("\n--- %d levels ---" % total)
	print("par moves:               %d" % moved)
	print("gain a spare discard:    %d" % now_has_slack)
	print("solver gave up:          %d" % unsolvable)
	print("\nA par that moves invalidates the stars already earned on that level.")
	quit()


## Voluntary discards in an optimal line. `actions` records a discard as its own
## entry (C-14), which is the only reason this is countable at all — `moves` holds
## placement targets and cannot express one.
func _discards_in(actions: Array) -> int:
	var n: int = 0
	for step: Variant in actions:
		if int((step as Array)[0]) == Solver.ACTION_DISCARD:
			n += 1
	return n

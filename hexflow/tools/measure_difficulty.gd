extends SceneTree
## Measurement tool: how *hard* is each shipped level, as against how *long*.
##
##     Godot --headless --path . -s res://tools/measure_difficulty.gd -- [chapter]
##
## §9 orders the campaign by `par`, and `par` measures length. A par-14 board with
## fifty optimal lines is a stroll; a par-8 board with one is vicious. So the
## curve §9 describes and the curve a player *feels* are not the same curve, and
## nothing in the repo could tell them apart.
##
## What this reports, per level:
##
##   decisions   turns where more than one legal target existed. A turn with one
##               option is not a decision, however long the level is.
##   forgiving   mean fraction of those options that keep the level winnable at
##               all. High means wrong turns are recoverable; low means the board
##               is a corridor wearing a hexagon.
##   on-par      the same fraction, but counting only options that keep three
##               stars reachable. This is the one a player chasing par feels.
##   knife       turns where exactly one option keeps par alive. The spikes.
##
## Reads only. Nothing here writes a level file, and no shipped data changes —
## every number is derived by replaying the stored optimal line and asking the
## solver what would have happened down each road not taken.
##
## Not part of the shipped game.

## Alternatives are probed with a smaller budget than authoring uses: this asks
## "is there a win down here", not "what is the best one", and it asks it a few
## thousand times.
const PROBE_STATES := 40000


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var only: int = int(args[0]) if args.size() > 0 else 0

	print("ch lv | par | decisions | forgiving | on-par | knife | branch")
	var by_chapter: Dictionary = {}

	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		if only > 0 and chapter != only:
			continue
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			var level := LevelRepository.load_level(chapter, index)
			if level == null:
				continue
			var m: Dictionary = _profile(level)
			if m.is_empty():
				print("%2d %2d | %3d | (no stored optimal line)" % [chapter, index, level.par])
				continue
			print("%2d %2d | %3d | %9d | %8.2f | %6.2f | %5d | %6.2f" % [
				chapter, index, level.par, int(m["decisions"]),
				float(m["forgiving"]), float(m["on_par"]),
				int(m["knife"]), float(m["branch"]),
			])
			var rows: Array = by_chapter.get(chapter, [])
			rows.append(m)
			by_chapter[chapter] = rows

	print("\nch | levels | mean decisions | mean forgiving | mean on-par | mean knife")
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		if not by_chapter.has(chapter):
			continue
		var rows: Array = by_chapter[chapter]
		print("%2d | %6d | %14.1f | %14.2f | %11.2f | %10.1f" % [
			chapter, rows.size(),
			_mean(rows, "decisions"), _mean(rows, "forgiving"),
			_mean(rows, "on_par"), _mean(rows, "knife"),
		])
	quit()


## Replays [param level]'s stored optimal line and, at every turn, asks what each
## other legal target would have cost. The line itself is the spine because it is
## the one route known to reach the goal in `par` — probing an arbitrary playthrough
## would measure how badly this tool plays rather than how hard the level is.
func _profile(level: Level) -> Dictionary:
	var state := GameState.start(level)
	var decisions: int = 0
	var knife: int = 0
	var branch_total: int = 0
	var forgiving_total: float = 0.0
	var on_par_total: float = 0.0

	for step: Variant in level.solution_script:
		var entry: Array = step
		var kind: int = int(entry[0])
		if state.status != GameState.Status.PLAYING:
			break
		if kind == Solver.ACTION_DISCARD:
			# A discard is a turn, but not a choice between cells.
			state.discard()
			continue
		if kind == Solver.ACTION_WILD:
			# §6's charge enters any adjacent cell, so its options are a different
			# set from `legal_targets` and it is replayed rather than probed. Not
			# skipping it is the point: skipping left the replay one placement short
			# on every chapter-5 level whose optimum spends one, and on two of them
			# the *next* stored target was then illegal and the whole level was
			# reported as having no optimal line at all.
			if not state.place_wild(entry[1]):
				return {}
			continue

		var chosen: Vector3i = entry[1]
		var options: Array[Vector3i] = state.legal_targets()
		if options.size() > 1:
			decisions += 1
			branch_total += options.size()
			var alive: int = 0
			var on_par: int = 0
			var snapshot: Dictionary = state.to_dict()
			for t: Vector3i in options:
				var verdict: Vector2i = _probe(state, t, level.par)
				alive += verdict.x
				on_par += verdict.y
				state.restore(snapshot)
			forgiving_total += float(alive) / float(options.size())
			on_par_total += float(on_par) / float(options.size())
			if on_par <= 1:
				knife += 1

		if not state.place(chosen):
			return {}

	if decisions == 0:
		return {"decisions": 0, "forgiving": 1.0, "on_par": 1.0, "knife": 0, "branch": 0.0}
	return {
		"decisions": decisions,
		"forgiving": forgiving_total / float(decisions),
		"on_par": on_par_total / float(decisions),
		"knife": knife,
		"branch": float(branch_total) / float(decisions),
	}


## Places [param target] and asks the solver what is left. Returns `(winnable,
## still on par)` as ones and zeroes, so the caller can sum both in one pass.
##
## [param state] is left dirty — the caller restores it. Cloning a [GameState] per
## probe would allocate several thousand of them over a run for no gain.
func _probe(state: GameState, target: Vector3i, par: int) -> Vector2i:
	if not state.place(target):
		return Vector2i.ZERO
	if state.status == GameState.Status.WON:
		return Vector2i(1, 1 if state.placements <= par else 0)
	if state.status == GameState.Status.DEAD:
		return Vector2i.ZERO
	var result := Solver.solve_state(state, PROBE_STATES)
	if not result.is_solvable():
		# UNKNOWN counts as unwinnable here, the same way §8.2 step 7 treats it —
		# a road the solver could not finish is not one this tool may call open.
		return Vector2i.ZERO
	return Vector2i(1, 1 if state.placements + result.par <= par else 0)


func _mean(rows: Array, key: String) -> float:
	var total: float = 0.0
	for r: Variant in rows:
		total += float((r as Dictionary)[key])
	return total / float(maxi(1, rows.size()))

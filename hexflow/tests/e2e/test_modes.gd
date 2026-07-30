## @e2e — §7.2 and §7.3's modes, and §23's promise that Steam is never load-bearing.
##
## These are three of M9's exit criteria, and all three are about *logic* that
## already exists rather than about the mode screens that do not. Endless and daily
## have been reachable through `GameDirector` since M9's first commit and nothing
## has ever played them end to end, so what is asserted here is the behaviour a
## player would notice: a run that gets harder, a puzzle that is the same puzzle for
## everyone on the same day, and a game that does not care whether Steam answered.
extends GutTest


func before_each() -> void:
	SaveService.data = {"campaign": {}, "in_progress": null,
		"stats": {"undos": 0}, "achievements_mirror": []}


func after_each() -> void:
	GameDirector.state = null
	GameDirector.level = null
	GameDirector.mode = GameDirector.Mode.CAMPAIGN


## Plays [param state] greedily until it stops being playable, and says how many
## placements it took. Greedy is enough: §7.2's escalation is about the board, not
## about playing it well.
func _play_out(limit: int = 400) -> int:
	var moves := 0
	while GameDirector.state != null \
			and GameDirector.state.status == GameState.Status.PLAYING \
			and moves < limit:
		var targets: Array[Vector3i] = GameDirector.state.legal_targets()
		if targets.is_empty():
			break
		EventBus.place_requested.emit(targets[0])
		moves += 1
	return moves


## §7.2: an Endless run escalates. Each stage is a new board off a seed derived
## from the run's own (C-12), so the run is reproducible from one number and still
## gets harder as it goes.
func test_an_endless_run_escalates_and_stays_reproducible() -> void:
	GameDirector.start_endless(20260730)
	assert_eq(GameDirector.mode, GameDirector.Mode.ENDLESS)
	var first: Level = GameDirector.level
	assert_not_null(first, "a run opens on a board")

	var run := EndlessRun.new(20260730)
	var walls: Array[int] = []
	for stage: int in range(4):
		walls.append(run.current_level().board.walls().size())
		run.advance(6)
	assert_gt(walls[walls.size() - 1], walls[0],
		"§7.2 escalates walls: stage %d had %d, the first had %d"
			% [walls.size() - 1, walls[walls.size() - 1], walls[0]])

	# The same seed is the same run, stage for stage — that is what makes a score
	# comparable to anyone else's (§7.2, C-12).
	var replay := EndlessRun.new(20260730)
	for stage: int in range(4):
		assert_eq(replay.current_level().board.walls().size(), walls[stage],
			"stage %d must replay identically" % stage)
		replay.advance(6)


## The run has to *end*, and it ends on a board with nowhere left to go rather than
## on a timer — §5.8's dead state doing the work §7.2 relies on.
func test_an_endless_run_ends_on_a_board_with_nowhere_to_go() -> void:
	GameDirector.start_endless(99)
	var moves: int = _play_out()
	assert_gt(moves, 0, "the run was playable")
	assert_true(GameDirector.state.legal_targets().is_empty()
			or GameDirector.state.status != GameState.Status.PLAYING,
		"a run ends because the board ran out, not because a clock did")


## §7.3: two clients, one day, one puzzle. Generated rather than downloaded, so the
## only thing keeping them identical is determinism (§19).
func test_two_clients_generate_the_same_daily() -> void:
	var a := Generator.daily("2026-07-30")
	var b := Generator.daily("2026-07-30")
	assert_eq(LevelRepository.to_dict(a), LevelRepository.to_dict(b),
		"the same date must be the same puzzle, byte for byte")
	assert_eq(a.par, b.par, "including its par, which the leaderboard is scored against")

	var other := Generator.daily("2026-07-31")
	assert_ne(LevelRepository.to_dict(other), LevelRepository.to_dict(a),
		"and the next day is a different one")


## A daily is playable, not merely generatable — §8.2 verifies solvability at
## generation and this is the end of that promise.
func test_the_daily_is_playable_through_the_director() -> void:
	GameDirector.start_daily("2026-07-30")
	assert_eq(GameDirector.mode, GameDirector.Mode.DAILY)
	assert_not_null(GameDirector.state)
	assert_false(GameDirector.state.legal_targets().is_empty(),
		"a daily nobody can move on is a day nobody can play")
	assert_gt(GameDirector.level.par, 0, "and it knows what a good score is")


## §23.3 and M9's exit criterion: **Steam unavailable never blocks play.** The
## build has no Steam API in it at all yet, which makes this the easiest moment to
## pin the behaviour — everything below runs with `available` false.
func test_steam_being_unavailable_blocks_nothing() -> void:
	assert_false(SteamService.available, "there is no Steam API in this build")

	GameDirector.start_endless(7)
	assert_gt(_play_out(20), 0, "endless plays")
	GameDirector.start_daily("2026-07-30")
	assert_gt(_play_out(20), 0, "the daily plays")
	GameDirector.start_level(LevelRepository.load_level(1, 1))
	assert_gt(_play_out(20), 0, "and so does the campaign")


## Achievements queue locally instead of being lost, so the first launch that finds
## Steam can hand over a backlog rather than an empty list.
func test_achievements_queue_locally_while_steam_is_absent() -> void:
	SteamService.unlock_achievement("first_flow")
	SteamService.unlock_achievement("no_hints")
	var mirror: Array = SaveService.data["achievements_mirror"]
	assert_true(mirror.has("first_flow"), "queued, not dropped")
	assert_true(mirror.has("no_hints"))

	# And unlocking the same one twice does not queue it twice, or the handover
	# would replay it.
	SteamService.unlock_achievement("first_flow")
	var count := 0
	for name: Variant in SaveService.data["achievements_mirror"]:
		if str(name) == "first_flow":
			count += 1
	assert_eq(count, 1, "the queue is a set, not a log")


## A leaderboard submission with nobody listening must be a no-op rather than an
## error — §23.2's boards are M9 work and the call site ships before they do.
func test_a_leaderboard_submission_without_steam_is_harmless() -> void:
	SteamService.submit_leaderboard("endless_best_goals", 12)
	SteamService.sync_pending()
	assert_false(SteamService.available, "still nothing to talk to, and nothing broke")

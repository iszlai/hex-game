## @core — §18.2, picking a run back up where it was left.
##
## Autosave has been writing `in_progress` since M5 and nothing read it: every boot
## opened chapter 1 level 1 whatever the player had been doing. That is the gap
## this closes, and the interesting half is not the happy path.
##
## The payload is untrusted by construction. It is written by an older build,
## truncated by a Deck suspend that lost power, or edited by hand — and §18's
## promise is that a bad save costs you your place, never your game. So every way
## it can be wrong is a test here, and every one of them has to end with a playable
## level rather than a black screen.
extends GutTest

var _saved: Variant = null


func before_each() -> void:
	SaveService.data = {"campaign": {}, "in_progress": null,
		"stats": {"undos": 0}, "achievements_mirror": []}
	_saved = null


func after_each() -> void:
	SaveService.data = {"campaign": {}, "in_progress": null,
		"stats": {"undos": 0}, "achievements_mirror": []}
	GameDirector.state = null
	GameDirector.level = null


## Plays a real campaign level a few moves in and returns what autosave wrote.
func _run_in_progress(steps: int = 3) -> Dictionary:
	GameDirector.start_level(LevelRepository.load_level(1, 1))
	for i: int in range(steps):
		var targets: Array[Vector3i] = GameDirector.state.legal_targets()
		if targets.is_empty():
			break
		EventBus.place_requested.emit(targets[0])
	var payload: Variant = SaveService.data.get("in_progress")
	assert_true(payload is Dictionary, "§18.1 must have written something to resume")
	return payload as Dictionary


func test_a_run_comes_back_exactly_where_it_was_left() -> void:
	var before: Dictionary = _run_in_progress()
	var placements: int = GameDirector.state.placements
	var path: Dictionary = GameDirector.state.path.duplicate()
	assert_gt(placements, 0, "the fixture must actually have played")

	# A fresh boot, with only what was on disk.
	GameDirector.state = null
	GameDirector.level = null
	assert_true(GameDirector.resume_in_progress(), "it resumed")
	assert_eq(GameDirector.level.id, str(before["level_id"]), "the same level")
	assert_eq(GameDirector.state.placements, placements, "the same placements")
	assert_eq(GameDirector.state.path, path, "and the same path, cell for cell")


## The stream has to come back with the state, or the next tile the player is
## handed is not the one they were looking at when they stopped.
func test_the_tile_stream_resumes_with_it() -> void:
	_run_in_progress()
	var tile: int = GameDirector.state.current_tile()
	var upcoming: Array[int] = GameDirector.state.preview(3)

	assert_true(GameDirector.resume_in_progress())
	assert_eq(GameDirector.state.current_tile(), tile, "the same tile is up")
	assert_eq(GameDirector.state.preview(3), upcoming, "and the same ones behind it")


## §5.9 permits undo history not to survive a suspend, and C-16 chose that
## deliberately to keep the save at ~2 KB. It is worth pinning: the level must
## still be playable, just not undoable back past the resume.
func test_undo_history_does_not_come_back_and_that_is_deliberate() -> void:
	_run_in_progress()
	assert_true(GameDirector.resume_in_progress())
	assert_false(GameDirector.undo_available(), "C-16: history is not persisted")
	assert_false(GameDirector.state.legal_targets().is_empty(), "but the level plays on")


func test_nothing_to_resume_is_not_a_failure() -> void:
	assert_false(GameDirector.resume_in_progress(), "a fresh save resumes nothing")


## Every way the payload can be wrong ends the same way: no resume, and a save that
## will not try again.
func test_a_payload_naming_a_level_that_does_not_exist_is_discarded() -> void:
	var payload: Dictionary = _run_in_progress()
	payload["level_id"] = "c9_l99"
	SaveService.set_in_progress(payload)
	assert_false(GameDirector.resume_in_progress(), "no such level")
	assert_null(SaveService.data.get("in_progress"), "and it is cleared rather than retried")


func test_a_payload_that_is_not_a_campaign_run_is_left_alone() -> void:
	var payload: Dictionary = _run_in_progress()
	payload["mode"] = "endless"
	SaveService.set_in_progress(payload)
	assert_false(GameDirector.resume_in_progress(),
		"§18.2 resumes the campaign; endless and daily are their own modes")


func test_a_payload_that_is_not_a_dictionary_at_all_is_survivable() -> void:
	for junk: Variant in [42, "c1_l01", [], null]:
		SaveService.data["in_progress"] = junk
		assert_false(GameDirector.resume_in_progress(), "junk resumes nothing: %s" % [junk])


## A level id that is not a campaign id must not be guessed at.
func test_only_a_real_campaign_id_locates_a_level() -> void:
	assert_eq(LevelRepository.locate("c3_l07"), Vector2i(3, 7))
	assert_eq(LevelRepository.locate("c1_l01"), Vector2i(1, 1))
	for bad: String in ["", "fixture", "c_l1", "cx_ly", "c1", "l1_c1", "c1_l01_extra"]:
		assert_eq(LevelRepository.locate(bad), Vector2i.ZERO, "%s is not a campaign id" % bad)
		assert_null(LevelRepository.load_by_id(bad), "%s must not load anything" % bad)


## §18.3: a level suspended mid-move comes back *identically*. The Deck sleeps
## between moves far more often than a desktop does, and the process may never wake
## — so the run has to be on disk before the suspend, not after it.
##
## Identity is asserted field by field rather than as "it looks about right",
## because the fields that go missing quietly are the ones nobody looks at: the
## stream index, the turn start, the charges.
func test_a_suspended_run_comes_back_identical() -> void:
	_run_in_progress(4)
	var before: GameState = GameDirector.state
	var path: Dictionary = before.path.duplicate()
	var edges: Array = before.edges.duplicate(true)
	var placements: int = before.placements
	var discards: int = before.discards_left
	var charges: int = before.wild_charges
	var stream_index: int = before.stream.index
	var tile: int = before.current_tile()

	GameDirector.suspend()
	GameDirector.state = null
	GameDirector.level = null

	assert_true(GameDirector.resume_in_progress(), "§18.3: it comes back")
	var after: GameState = GameDirector.state
	assert_eq(after.path, path, "path")
	assert_eq(after.edges, edges, "edges")
	assert_eq(after.placements, placements, "placements")
	assert_eq(after.discards_left, discards, "discards left")
	assert_eq(after.wild_charges, charges, "wild charges")
	assert_eq(after.stream.index, stream_index, "stream index")
	assert_eq(after.current_tile(), tile, "and the tile that was up is still up")
	assert_eq(after.status, GameState.Status.PLAYING)


## The suspend has to catch the gap between the last move and the sleep. §18.1
## covers the moves themselves, so what is being checked is that suspending is
## *also* a write rather than only a hope that a move happened recently.
func test_suspending_writes_the_run_down_there_and_then() -> void:
	_run_in_progress(2)
	SaveService.data["in_progress"] = null
	GameDirector.suspend()
	var payload: Variant = SaveService.data.get("in_progress")
	assert_true(payload is Dictionary, "a suspend is a write")
	assert_eq(int((payload as Dictionary)["placements"]), GameDirector.state.placements)


## A run that had already finished has no business being resumed — §18.1 clears it
## on the winning move, and this is what happens if that write never landed.
func test_a_finished_run_is_cleared_rather_than_reopened() -> void:
	var payload: Dictionary = _run_in_progress()
	payload["status"] = GameState.Status.WON
	SaveService.set_in_progress(payload)
	assert_false(GameDirector.resume_in_progress(), "a finished level is not resumed")
	assert_not_null(GameDirector.state, "and the player is left on a playable level")
	assert_eq(GameDirector.state.status, GameState.Status.PLAYING)
	assert_eq(GameDirector.state.placements, 0, "from the top, not mid-run")
	# The finished payload is gone. What is there instead is §18.1 recording the
	# fresh run that just started, which is exactly what it is for.
	var now: Variant = SaveService.data.get("in_progress")
	if now is Dictionary:
		assert_eq(int((now as Dictionary)["status"]), GameState.Status.PLAYING,
			"whatever is stored now, it is not a finished run")

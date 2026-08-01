## @core — what §12.3's top bar says when the level on it is not a campaign level.
##
## Every screen in the game was built against the campaign, and endless and the
## daily borrow the same level screen. Three of its readouts assumed a campaign
## level and had no answer for the other two modes, so they printed one anyway:
## the title fell through to the raw id (`endless_3`), the counter compared the
## player against a par that does not exist (`placements 7 / par 0`), and the star
## band — derived from that par — showed three hollow stars that could never fill.
##
## None of it crashed, and none of it is visible in a campaign playthrough, which
## is why it survived M9. The point of this file is that the top bar is asserted in
## the modes nobody plays while developing.
extends GutTest

const SCENE := "res://src/scenes/level/level.tscn"

var _scene: Control = null


func before_each() -> void:
	SaveService.data = {"campaign": {}, "in_progress": null, "daily": {},
		"endless": {}, "stats": {"undos": 0}, "achievements_mirror": []}


func after_each() -> void:
	_scene = null
	GameDirector.state = null
	GameDirector.level = null
	GameDirector.mode = GameDirector.Mode.CAMPAIGN


func _open() -> void:
	_scene = load(SCENE).instantiate()
	add_child_autofree(_scene)


func _label(name: String) -> Label:
	return _scene.get_node("%" + name) as Label


## §7.2's run has no chapter and no level number, so it says what it does have.
func test_an_endless_run_names_itself_and_scores_itself_by_goals() -> void:
	GameDirector.start_endless(20260731)
	_open()

	assert_string_contains(_label("TitleLabel").text, "Endless")
	assert_false(_label("TitleLabel").text.contains("endless_"),
		"the id is what the save calls it, not what the player reads")

	# §7.2: "Score = goals_reached", tie-broken by placements. Neither is a par.
	assert_string_contains(_label("ScoreLabel").text, "goals")
	assert_false(_label("ScoreLabel").text.contains("ideal"),
		"a run has no ideal to be measured against")
	assert_false(_label("StarsLabel").visible,
		"and no star band, because there is nothing for it to ever award")


## §7.3's puzzle is one day's board. It has a par — it is generated and solved like
## any other level — so the counter and the stars are the campaign's. Only the name
## is different, and it should be the date rather than `daily_2026-07-31`.
func test_the_daily_names_the_day_and_keeps_its_par() -> void:
	GameDirector.start_daily("2026-07-31")
	if GameDirector.level == null:
		return  # §7.3 refuses to navigate on a day generation failed; nothing to assert
	_open()

	assert_string_contains(_label("TitleLabel").text, "2026-07-31")
	assert_false(_label("TitleLabel").text.contains("daily_"),
		"the prefix is part of the id, not part of the day")
	assert_string_contains(_label("ScoreLabel").text, "ideal")
	assert_true(_label("StarsLabel").visible, "a generated level has a real par")


## §5.9 takes undo away outside the campaign for leaderboard integrity, and §5.8's
## banner offered it regardless. A banner naming a key that does nothing is worse
## than one offering a single way out: the player presses it, nothing happens, and
## the reasonable conclusion is that the game is stuck rather than that the offer
## was wrong.
func test_the_dead_banner_only_offers_an_undo_that_exists() -> void:
	GameDirector.start_endless(20260731)
	_open()
	assert_false(GameDirector.undo_available(), "§5.9: no undo in a run")
	EventBus.level_dead.emit(GameState.Dead.PATH_FROZEN)
	assert_false(_label("BannerLabel").text.contains("undo"))
	assert_string_contains(_label("BannerLabel").text, "restart")

	# One placement, because `undo_available()` is also false with nothing to undo —
	# and a banner on move zero offering to take move zero back would be the same
	# defect pointing the other way.
	GameDirector.start_level(LevelRepository.load_level(1, 1))
	EventBus.place_requested.emit(GameDirector.state.legal_targets()[0])
	assert_true(GameDirector.undo_available(), "§5.9: unlimited undo in the campaign")
	EventBus.level_dead.emit(GameState.Dead.PATH_FROZEN)
	assert_string_contains(_label("BannerLabel").text, "undo")

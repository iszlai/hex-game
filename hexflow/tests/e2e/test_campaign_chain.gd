## @e2e — Scenario: the campaign is playable from a cold boot, and finishing a
## level advances the campaign (§26's M6 exit criterion; closes defect B6).
##
## Every screen in §12.1's map now exists, and each has its own test. This one
## exists for the *seams* — the places where one screen's idea of where it is
## meets another's. It follows the director rather than a script: whatever
## `GameDirector.screen` becomes, the scene [constant GameDirector.SCENES] names
## for it is what gets instantiated, so a screen that navigates somewhere the map
## does not go fails here rather than in front of a player.
##
## B6 was "progress never persisted, so the campaign could not advance". The last
## two assertions are that defect, stated as a requirement.
extends GutTest

var _screen: Node = null


func before_each() -> void:
	SaveService.data = {
		"campaign": {}, "in_progress": null,
		"endless": {"best_goals": 0, "best_placements_at_best": 0, "runs": 0},
		"daily": {"history": {}, "streak": 0},
		"stats": {"undos": 0}, "achievements_mirror": [],
	}
	GameDirector.last_result = {}


func after_each() -> void:
	var pending: Variant = GameDirector.get("_transition")
	if pending is Tween and (pending as Tween).is_running():
		(pending as Tween).kill()
	_close()
	for child: Node in get_tree().root.get_children():
		if child.scene_file_path.begins_with("res://src/scenes/"):
			get_tree().root.remove_child(child)
			child.queue_free()
	GameDirector.state = null
	GameDirector.level = null
	GameDirector.hints_used = 0
	GameDirector.mode = GameDirector.Mode.CAMPAIGN
	GameDirector.screen = GameDirector.Screen.LEVEL
	before_each()


func _close() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.get_parent().remove_child(_screen)
		_screen.queue_free()
	_screen = null


## Puts the scene the director is currently pointing at on screen. The transition
## is skipped rather than waited out — §14.1's 320 ms is asserted in
## `test_screen_transition.gd`, and letting the real swap land would drop a second
## copy of every screen into the root.
func _follow() -> void:
	var pending: Variant = GameDirector.get("_transition")
	if pending is Tween and (pending as Tween).is_running():
		(pending as Tween).kill()
	_close()
	var path: String = str(GameDirector.SCENES.get(GameDirector.screen, ""))
	assert_ne(path, "", "the director is on a screen with no scene: %d" % GameDirector.screen)
	_screen = load(path).instantiate()
	add_child_autofree(_screen)
	await wait_process_frames(2)


func _press(action: String) -> void:
	for code: int in InputBindings.keys_of(action):
		var ev := InputEventKey.new()
		ev.keycode = code as Key
		ev.pressed = true
		_screen.get_viewport().push_input(ev)
		break
	await wait_process_frames(1)


func _menu() -> MenuList:
	return _screen.get_node("%Menu") as MenuList


## Plays the level the director is holding, using its own stored solution.
func _play_out() -> void:
	for step: Variant in GameDirector.level.solution_script:
		var s: Array = step
		match int(s[0]):
			Solver.ACTION_PLACE:
				EventBus.place_requested.emit(s[1] as Vector3i)
			Solver.ACTION_WILD:
				EventBus.wild_place_requested.emit(s[1] as Vector3i)
			Solver.ACTION_DISCARD:
				EventBus.discard_requested.emit()
	assert_eq(GameDirector.state.status, GameState.Status.WON)


func _complete(chapter: int, index: int) -> void:
		# Keyed on the level's own name (C-34), which is what [Campaign] reads — the
	# slot id was the key until levels got names, and a fixture still using it
	# would be invisible to the screen under test.
	(SaveService.data["campaign"] as Dictionary)[
		LevelRepository.load_level(chapter, index).progress_key()] = {
		"completed": true, "best_placements": 9, "stars": 3, "hinted": false,
	}


## Boot no longer opens a level; §12.1's first arrow is Boot → MainMenu.
func test_a_cold_boot_reaches_a_playable_campaign() -> void:
	GameDirector.screen = GameDirector.Screen.BOOT
	await _follow()
	# The boot screen leaves on any input or on its own timer; either is fine.
	await _press("menu_accept")
	await wait_seconds(0.1)
	assert_eq(GameDirector.screen, GameDirector.Screen.MAIN_MENU)

	await _follow()
	assert_eq(_menu().focused_id(), "campaign", "§12.2's default focus")
	await _press("menu_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL_SELECT)

	await _follow()
	await _press("menu_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL)
	assert_eq(GameDirector.level.id, LevelRepository.id_for(1, 1),
		"a fresh save opens on chapter 1 level 1")
	assert_not_null(GameDirector.state)


## B6, stated as a requirement: finishing a level records it and moves the
## campaign on. The original prototype never persisted progress, so it could not.
func test_finishing_a_level_records_it_and_advances_the_campaign() -> void:
	GameDirector.start_level(LevelRepository.load_level(1, 1))
	GameDirector.screen = GameDirector.Screen.LEVEL
	await _follow()
	assert_eq(Campaign.next_unplayed(), Vector2i(1, 1))
	assert_false(Campaign.level_unlocked(1, 2), "level 2 is shut before level 1 is done")

	_play_out()
	assert_true(Campaign.is_completed(1, 1), "recorded on the winning move, not on the card")
	assert_eq(Campaign.stars(1, 1), Scoring.MAX_STARS, "the stored solution is the optimum")
	assert_true(Campaign.level_unlocked(1, 2), "and the next level opened")
	assert_eq(Campaign.next_unplayed(), Vector2i(1, 2))

	await wait_seconds(Motion.results_delay_seconds() + 0.3)
	assert_eq(GameDirector.screen, GameDirector.Screen.RESULTS)
	await _follow()
	await _press("menu_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL)
	assert_eq(GameDirector.level.id, LevelRepository.id_for(1, 2),
		"Next opened the level the campaign had just unlocked")


## §7.1's threshold, through the map rather than through `Campaign` directly: the
## unlock has to be visible where the player looks for it.
func test_eight_completions_open_the_next_chapter_on_the_map() -> void:
	for index: int in range(1, 8):
		_complete(1, index)
	GameDirector.start_level(LevelRepository.load_level(1, 8))
	GameDirector.screen = GameDirector.Screen.LEVEL
	await _follow()
	assert_false(Campaign.chapter_unlocked(2), "seven is not eight")

	_play_out()
	assert_true(Campaign.chapter_unlocked(2))

	GameDirector.screen = GameDirector.Screen.LEVEL_SELECT
	await _follow()
	await _press("menu_cycle_next")
	await _press("menu_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL)
	assert_eq(GameDirector.level.id, LevelRepository.id_for(2, 1))


## §18.1 and §18.2 across the seam the map introduced: a run left in the middle is
## where the map opens, and entering it resumes rather than restarts.
func test_a_run_left_in_the_middle_is_the_one_the_map_offers_back() -> void:
	GameDirector.start_level(LevelRepository.load_level(1, 1))
	GameDirector.screen = GameDirector.Screen.LEVEL
	await _follow()
	EventBus.place_requested.emit(GameDirector.state.legal_targets()[0])
	var placements: int = GameDirector.state.placements
	assert_gt(placements, 0)

	# The player leaves. Everything in memory goes; the save is all that is left.
	GameDirector.state = null
	GameDirector.level = null
	GameDirector.screen = GameDirector.Screen.LEVEL_SELECT
	await _follow()
	await _press("menu_accept")
	assert_eq(GameDirector.level.id, LevelRepository.id_for(1, 1))
	assert_eq(GameDirector.state.placements, placements,
		"§18.2 — the map handed the run back, it did not start it over")

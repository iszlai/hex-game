## @e2e — Feature: the main menu (§12.2), through the real scene.
##
## §12.2 does not ask for five buttons; it asks for "Campaign (with % complete),
## Endless (with best), Daily (with streak + timer to reset)". The numbers are the
## requirement, so they are what is asserted — a menu that navigates perfectly and
## shows 0% to a player who has finished two chapters has failed this section.
extends GutTest

const SCENE := "res://src/scenes/main_menu/main_menu.tscn"

var _scene: Control = null


func before_each() -> void:
	SaveService.data = {
		"campaign": {}, "in_progress": null,
		"endless": {"best_goals": 0, "best_placements_at_best": 0, "runs": 0},
		"daily": {"history": {}, "streak": 0},
		"stats": {"undos": 0}, "achievements_mirror": [],
	}


func after_each() -> void:
	var pending: Variant = GameDirector.get("_transition")
	if pending is Tween and (pending as Tween).is_running():
		(pending as Tween).kill()
	_scene = null
	_clear_navigated_scenes()
	GameDirector.state = null
	GameDirector.level = null
	GameDirector.screen = GameDirector.Screen.LEVEL
	before_each()


func _open() -> void:
	GameDirector.screen = GameDirector.Screen.MAIN_MENU
	_scene = load(SCENE).instantiate()
	add_child_autofree(_scene)
	await wait_process_frames(2)


func _menu() -> MenuList:
	return _scene.get_node("%Menu") as MenuList


func _press(action: String) -> void:
	for code: int in InputBindings.keys_of(action):
		var ev := InputEventKey.new()
		ev.keycode = code as Key
		ev.pressed = true
		_scene.get_viewport().push_input(ev)
		break
	await wait_process_frames(1)


func _value_of(id: String) -> String:
	for row: Dictionary in _menu().rows():
		if str(row.get("id", "")) == id:
			return str(row.get("value", ""))
	return "<no such row>"


func test_the_menu_offers_exactly_the_five_ways_out_of_it() -> void:
	await _open()
	var ids: Array[String] = []
	for row: Dictionary in _menu().rows():
		ids.append(str(row.get("id", "")))
	assert_eq(ids, ["campaign", "endless", "daily", "settings", "quit"] as Array[String],
		"§12.2's row list, in §12.1's order")


## §12.2's default focus for this screen is Campaign.
func test_focus_opens_on_campaign() -> void:
	await _open()
	assert_eq(_menu().focused_id(), "campaign")


## §12.5: focus wraps within a list, and there is always exactly one.
func test_focus_wraps_and_is_never_nowhere() -> void:
	await _open()
	for _i: int in range(4):
		await _press("menu_down")
	assert_eq(_menu().focused_id(), "quit")
	await _press("menu_down")
	assert_eq(_menu().focused_id(), "campaign", "the list wraps")
	await _press("menu_up")
	assert_eq(_menu().focused_id(), "quit", "in both directions")


func test_campaign_carries_the_completion_percentage() -> void:
	await _open()
	assert_eq(_value_of("campaign"), "0%")

	for chapter: int in range(1, 3):
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			# Keyed on the level's own name (C-34), which is what [Campaign] reads.
			(SaveService.data["campaign"] as Dictionary)[
				LevelRepository.load_level(chapter, index).progress_key()] = {
				"completed": true, "best_placements": 8, "stars": 3, "hinted": false,
			}
	await _open()
	assert_eq(_value_of("campaign"), "40%", "24 of 60")


func test_endless_carries_the_best_run_once_there_is_one() -> void:
	await _open()
	assert_eq(_value_of("endless"), "new", "and says so rather than showing a zero")
	SaveService.data["endless"] = {"best_goals": 12, "best_placements_at_best": 60, "runs": 3}
	await _open()
	assert_string_contains(_value_of("endless"), "12")


## §7.3 wants a 7-day streak indicator *and* a timer to the reset, and the timer
## is the half that has to be live.
func test_daily_carries_the_streak_and_a_countdown() -> void:
	SaveService.data["daily"] = {"history": {}, "streak": 4}
	await _open()
	var value: String = _value_of("daily")
	assert_string_contains(value, "4")
	assert_true(value.contains(":"), "a countdown, not a date: %s" % value)

	var left: int = int(_scene.call("seconds_to_reset"))
	assert_gt(left, 0, "the day always has time left in it")
	assert_lte(left, 86400, "and never more than a day")


func test_the_countdown_lands_on_the_next_utc_midnight() -> void:
	await _open()
	var now: Dictionary = Time.get_datetime_dict_from_system(true)
	var elapsed: int = int(now["hour"]) * 3600 + int(now["minute"]) * 60 + int(now["second"])
	assert_almost_eq(int(_scene.call("seconds_to_reset")) + elapsed, 86400, 2,
		"§7.3 changes the puzzle at UTC midnight, not at the player's midnight")


func test_campaign_goes_to_the_map_rather_than_to_a_level() -> void:
	await _open()
	await _press("menu_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL_SELECT,
		"§12.1: MainMenu → LevelSelect : Campaign")
	assert_null(GameDirector.level, "the menu picks no level; the map does")


func test_endless_starts_a_run_and_hands_it_to_the_board() -> void:
	await _open()
	await _press("menu_down")
	await _press("menu_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL)
	assert_eq(GameDirector.mode, GameDirector.Mode.ENDLESS)
	assert_not_null(GameDirector.state)
	assert_false(GameDirector.undo_available(), "§7.2 — endless has no undo")


func test_daily_starts_todays_puzzle() -> void:
	await _open()
	await _press("menu_down")
	await _press("menu_down")
	await _press("menu_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL)
	assert_eq(GameDirector.mode, GameDirector.Mode.DAILY)
	assert_not_null(GameDirector.level)


## §12.5 — Back never quits the game. At the top of the state machine there is
## nothing above to go up to, so it does nothing at all rather than something.
func test_back_at_the_top_of_the_machine_does_not_leave() -> void:
	await _open()
	await _press("menu_back")
	assert_eq(GameDirector.screen, GameDirector.Screen.MAIN_MENU)


## §11.4 — asserted on the rendered rect, so a theme or a container cannot squeeze
## a row below the thumb-reachable size.
func test_every_menu_row_meets_the_44px_touch_target() -> void:
	await _open()
	await wait_process_frames(2)
	for button: Button in _menu().buttons():
		if not button.visible:
			continue
		assert_gte(button.size.y, MenuList.TOUCH_TARGET,
			"%s is %d px tall" % [button.text, int(button.size.y)])
		assert_gte(button.size.x, MenuList.TOUCH_TARGET)


## §14.1's transition is a *real* scene change: 160 ms after `go_to`, a tween
## callback swaps the running scene, and in a headless run that scene lands at the
## root and stays there — still answering `_unhandled_input`. Two screens then act
## on the same Space and the one that answers last decides where the game goes,
## which is how this file first reported Replay opening the level *after* the one
## it replayed. Anything the director navigated to is cleared here.
func _clear_navigated_scenes() -> void:
	for child: Node in get_tree().root.get_children():
		if child.scene_file_path.begins_with("res://src/scenes/"):
			get_tree().root.remove_child(child)
			child.queue_free()

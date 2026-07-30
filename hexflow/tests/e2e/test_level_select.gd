## @e2e — Feature: the campaign map (§12.2, §9), through the real scene.
##
## The leg of §24.2's gamepad scenario that the M4 playthrough could not assert:
## "navigate to Campaign, chapter 1, level 1". It needed a map, and there was
## none. Input arrives here as real [InputEvent]s through the viewport, so the
## same path a controller takes is the path under test.
extends GutTest

const SCENE := "res://src/scenes/level_select/level_select.tscn"

var _scene: Control = null


func before_each() -> void:
	SaveService.data = {"campaign": {}, "in_progress": null,
		"stats": {"undos": 0}, "achievements_mirror": []}


func after_each() -> void:
	# §14.1's transition is a *real* scene change: 160 ms after `go_to`, a tween
	# callback swaps the running scene. Left alive, one test's navigation lands in
	# the middle of the next one and `level.gd` helpfully starts a level of its own
	# — which is how this file first went red on a screen it never opened.
	var pending: Variant = GameDirector.get("_transition")
	if pending is Tween and (pending as Tween).is_running():
		(pending as Tween).kill()
	_scene = null
	_clear_navigated_scenes()
	GameDirector.state = null
	GameDirector.level = null
	GameDirector.screen = GameDirector.Screen.LEVEL
	SaveService.data = {"campaign": {}, "in_progress": null,
		"stats": {"undos": 0}, "achievements_mirror": []}


func _open() -> void:
	# The map is opened directly rather than navigated to, so the director is told
	# where we are — otherwise every "did this leave the map" assertion below is
	# comparing against whatever the last test left behind.
	GameDirector.screen = GameDirector.Screen.LEVEL_SELECT
	_scene = load(SCENE).instantiate()
	add_child_autofree(_scene)
	await wait_process_frames(2)


func _complete(chapter: int, index: int, stars: int = 3) -> void:
	(SaveService.data["campaign"] as Dictionary)[LevelRepository.id_for(chapter, index)] = {
		"completed": true, "best_placements": 9, "stars": stars, "hinted": false,
	}


func _press(action: String) -> void:
	for code: int in InputBindings.keys_of(action):
		var ev := InputEventKey.new()
		ev.keycode = code as Key
		ev.pressed = true
		_scene.get_viewport().push_input(ev)
		break
	await wait_process_frames(1)


func _flower() -> HexFlower:
	return _scene.get_node("%Flower") as HexFlower


func test_the_map_claims_the_menu_action_set() -> void:
	await _open()
	assert_eq(InputBindings.active_set, InputBindings.SET_MENU,
		"§11.1 — a screen acts only on its own set")


## §12.2's default focus for this screen is "last played level".
func test_the_map_opens_on_the_level_the_player_was_last_in() -> void:
	_complete(1, 1)
	_complete(1, 2)
	await _open()
	assert_eq(_flower().cursor(), 3, "the next unplayed level")

	SaveService.data["in_progress"] = {"mode": "campaign", "level_id": LevelRepository.id_for(1, 2)}
	await _open()
	assert_eq(_flower().cursor(), 2, "a run in progress is where the player actually was")


## Scenario: navigate to Campaign, chapter 1, level 1 (§24.2) — the leg the M4
## gamepad playthrough had to skip because there was no map to navigate.
func test_a_level_opens_on_accept_and_hands_the_board_the_real_level() -> void:
	await _open()
	assert_eq(_flower().cursor(), 1)
	await _press("menu_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL)
	assert_not_null(GameDirector.level)
	assert_eq(GameDirector.level.id, LevelRepository.id_for(1, 1))
	assert_not_null(GameDirector.state, "and the run has actually started")


## §7.1 unlocks linearly. The map is still allowed to *show* what is coming — a
## player is entitled to look — so the lock is enforced on opening, not on where
## the cursor may rest.
func test_a_locked_level_can_be_looked_at_but_not_entered() -> void:
	await _open()
	var moved: bool = false
	for i: int in range(12):
		await _press("menu_down")
		if _flower().cursor() != 1:
			moved = true
			break
		await _press("menu_right")
		if _flower().cursor() != 1:
			moved = true
			break
	assert_true(moved, "the cursor reaches a second level at all")
	assert_ne(_flower().cursor(), 1)
	await _press("menu_accept")
	assert_null(GameDirector.level, "a locked level must not start")
	assert_ne(GameDirector.screen, GameDirector.Screen.LEVEL)
	var hint: Label = _scene.get_node("%HintLabel") as Label
	assert_string_contains(hint.text.to_lower(), "finish level",
		"and the map says why, rather than doing nothing")


func test_the_bumpers_page_through_the_chapters() -> void:
	await _open()
	var chapter_label: Label = _scene.get_node("%ChapterLabel") as Label
	assert_string_contains(chapter_label.text, "Chapter 1")
	await _press("menu_cycle_next")
	assert_string_contains(chapter_label.text, "Chapter 2")
	await _press("menu_cycle_prev")
	assert_string_contains(chapter_label.text, "Chapter 1")
	# And it does not page off either end.
	await _press("menu_cycle_prev")
	assert_string_contains(chapter_label.text, "Chapter 1")


func test_a_locked_chapter_says_what_it_is_waiting_for() -> void:
	await _open()
	await _press("menu_cycle_next")
	await _press("menu_accept")
	assert_null(GameDirector.level)
	var hint: Label = _scene.get_node("%HintLabel") as Label
	assert_string_contains(hint.text, str(Campaign.CHAPTER_UNLOCK_THRESHOLD),
		"§7.1's threshold is the whole answer, so it is the thing shown")


func test_completing_eight_opens_the_next_chapter_on_the_map() -> void:
	for index: int in range(1, 9):
		_complete(1, index)
	await _open()
	await _press("menu_cycle_next")
	await _press("menu_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL)
	assert_eq(GameDirector.level.id, LevelRepository.id_for(2, 1))


## §12.5 — Back goes up exactly one level of the state machine.
func test_back_goes_to_the_main_menu_and_no_further() -> void:
	await _open()
	await _press("menu_back")
	assert_eq(GameDirector.screen, GameDirector.Screen.MAIN_MENU)


## A pointer opens a level in one gesture, and the keyboard picks up where the
## finger left off — the two input schemes share one cursor (§11.4).
func test_a_tap_opens_the_level_it_landed_on() -> void:
	_complete(1, 1)
	await _open()
	var flower: HexFlower = _flower()
	var at: Vector2 = flower.layout.to_pixel(HexFlower.cell_for(2))
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = at + flower.global_position
	# `true` = the position is already in viewport space; without it Godot applies
	# the window transform and the click lands somewhere else entirely.
	_scene.get_viewport().push_input(ev, true)
	await wait_process_frames(2)
	assert_eq(flower.cursor(), 2)
	assert_eq(GameDirector.level.id, LevelRepository.id_for(1, 2))


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

## @e2e — Feature: pausing (§12.2, §12.5), through the real level scene.
##
## The interesting property is not the menu; it is that the board is still there
## and cannot be played. §11.1's action sets are the whole mechanism, and this is
## the first screen that actually exercises them — before now nothing ever claimed
## `Modal`, so "a set that is not live is not acted on" was a rule with no
## counter-example behind it.
extends GutTest

const SCENE := "res://src/scenes/level/level.tscn"

var _scene: Control = null


func before_each() -> void:
	SaveService.data = {"campaign": {}, "in_progress": null, "tutorial_flags": {},
		"stats": {"undos": 0}, "achievements_mirror": []}
	# §10.1 gives the tutorial first claim on Back and Start while a beat is up, so
	# a save with the tutorial unseen would have Esc skipping T1 rather than opening
	# the pause menu. That is the correct behaviour and it is asserted in
	# `test_tutorial_beats.gd`; here it would only mean these tests never reach a
	# pause menu at all. The tutorial is marked done, which is where a player
	# pressing Start on chapter 1 in anger normally is anyway.
	Tutorial.clear_cache()
	Tutorial.skip_all()
	SettingsService.set_value("hold_to_confirm", true)


func after_each() -> void:
	var pending: Variant = GameDirector.get("_transition")
	if pending is Tween and (pending as Tween).is_running():
		(pending as Tween).kill()
	if _scene != null and is_instance_valid(_scene):
		_scene.get_parent().remove_child(_scene)
		_scene.queue_free()
	_scene = null
	_clear_navigated_scenes()
	GameDirector.state = null
	GameDirector.level = null
	GameDirector.screen = GameDirector.Screen.LEVEL
	GameDirector.mode = GameDirector.Mode.CAMPAIGN
	InputBindings.activate(InputBindings.SET_BOARD)
	SettingsService.set_value("hold_to_confirm", true)


func _open(chapter: int = 1, index: int = 1) -> void:
	GameDirector.start_level(LevelRepository.load_level(chapter, index))
	GameDirector.screen = GameDirector.Screen.LEVEL
	_scene = load(SCENE).instantiate()
	add_child_autofree(_scene)
	await wait_process_frames(2)


func _pause() -> PausePanel:
	return _scene.get_node("%Pause") as PausePanel


func _menu() -> MenuList:
	return _pause().get("_menu") as MenuList


func _press(action: String) -> void:
	for code: int in InputBindings.keys_of(action):
		var ev := InputEventKey.new()
		ev.keycode = code as Key
		ev.pressed = true
		_scene.get_viewport().push_input(ev)
		break
	await wait_process_frames(1)


func _release(action: String) -> void:
	for code: int in InputBindings.keys_of(action):
		var ev := InputEventKey.new()
		ev.keycode = code as Key
		ev.pressed = false
		_scene.get_viewport().push_input(ev)
		break
	await wait_process_frames(1)


func test_escape_pauses_over_a_board_that_is_still_there() -> void:
	await _open()
	assert_false(_pause().visible)
	await _press("board_pause")
	assert_true(_pause().visible)
	assert_eq(GameDirector.screen, GameDirector.Screen.PAUSED)
	assert_eq(InputBindings.active_set, InputBindings.SET_MODAL, "§11.1")
	# The board is not reloaded — §12.2 pauses *over* it, so the run is untouched.
	assert_not_null(GameDirector.state)
	assert_true(_scene.get_node("%Board").visible, "the board is still on screen")


## §12.2's default focus for this screen is Resume.
func test_focus_opens_on_resume() -> void:
	await _open()
	await _press("board_pause")
	assert_eq(_menu().focused_id(), "resume")


## The point of §11.1. A paused board must not be playable, and the check is the
## board's own counters rather than the visuals.
func test_a_paused_board_cannot_be_played() -> void:
	await _open()
	await _press("board_confirm")
	var placements: int = GameDirector.state.placements
	var discards: int = GameDirector.state.discards_left
	await _press("board_pause")
	await _press("board_discard")
	await _press("board_undo")
	assert_eq(GameDirector.state.placements, placements, "no move reached the board")
	assert_eq(GameDirector.state.discards_left, discards, "and no discard did either")
	assert_eq(GameDirector.screen, GameDirector.Screen.PAUSED, "and we are still paused")


## The keys that *are* shared. §11.3 gives `board_confirm` and `modal_accept` the
## same Space and the same A, which is the right answer — while a modal is up,
## confirm means "confirm the modal". The rule that makes it unambiguous is §11.1's
## live set, not the keycode, and this is the case that proves it: the same press
## places a tile on one side of a pause and works the menu on the other.
func test_a_shared_key_belongs_to_whichever_set_is_live() -> void:
	await _open()
	var placements: int = GameDirector.state.placements
	await _press("board_pause")
	assert_eq(_menu().focused_id(), "resume")
	await _press("board_confirm")
	assert_eq(GameDirector.state.placements, placements, "Space did not place a tile")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL, "it pressed Resume")


func test_resume_returns_to_the_board_without_reloading_it() -> void:
	await _open()
	await _press("board_confirm")
	var placements: int = GameDirector.state.placements
	assert_gt(placements, 0)

	await _press("board_pause")
	await _press("modal_accept")
	assert_false(_pause().visible)
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL)
	assert_eq(InputBindings.active_set, InputBindings.SET_BOARD)
	assert_eq(GameDirector.state.placements, placements, "the run is exactly as it was")


## §12.5 — Back goes up exactly one level: out of the modal, not out of the game.
func test_back_leaves_the_modal_and_nothing_else() -> void:
	await _open()
	await _press("board_pause")
	await _press("modal_back")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL)
	assert_false(_pause().visible)


## §11.3 — nothing destructive on a single press. A tap of accept on Restart must
## leave the run alone.
func test_restart_is_never_a_single_press() -> void:
	await _open()
	await _press("board_confirm")
	var placements: int = GameDirector.state.placements
	await _press("board_pause")
	await _press("modal_down")
	assert_eq(_menu().focused_id(), "restart")
	await _press("modal_accept")
	await _release("modal_accept")
	assert_eq(GameDirector.state.placements, placements, "a tap did not restart")
	assert_eq(GameDirector.screen, GameDirector.Screen.PAUSED)


func test_holding_restart_restarts_and_returns_to_the_board() -> void:
	await _open()
	await _press("board_confirm")
	assert_gt(GameDirector.state.placements, 0)
	await _press("board_pause")
	await _press("modal_down")
	await _press("modal_accept")
	await wait_seconds(InputBindings.HOLD_RESTART + 0.2)
	assert_eq(GameDirector.state.placements, 0, "the hold restarted the level")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL, "and put the player back on it")


## §21's hold-to-confirm toggle: a player who cannot hold gets the same guarantee
## through a second press instead. Still never one press.
func test_the_hold_toggle_swaps_the_gesture_without_weakening_it() -> void:
	SettingsService.set_value("hold_to_confirm", false)
	await _open()
	await _press("board_confirm")
	var placements: int = GameDirector.state.placements
	await _press("board_pause")
	await _press("modal_down")
	await _press("modal_accept")
	assert_eq(GameDirector.state.placements, placements, "the first press only arms")
	await _press("modal_accept")
	assert_eq(GameDirector.state.placements, 0, "the second commits")


## An armed destructive action that survives the player looking elsewhere is a
## trap: the next accept would restart something they had stopped thinking about.
func test_moving_off_restart_disarms_it() -> void:
	SettingsService.set_value("hold_to_confirm", false)
	await _open()
	await _press("board_confirm")
	var placements: int = GameDirector.state.placements
	await _press("board_pause")
	await _press("modal_down")
	await _press("modal_accept")
	await _press("modal_up")
	await _press("modal_down")
	await _press("modal_accept")
	assert_eq(GameDirector.state.placements, placements, "the arming did not survive the move")


## §12.2's "Quit to map" — and §18.3, which says the run is on disk before the
## player is taken off it.
func test_quitting_writes_the_run_down_and_goes_to_the_map() -> void:
	await _open()
	await _press("board_confirm")
	SaveService.data["in_progress"] = null
	await _press("board_pause")
	for _i: int in range(3):
		await _press("modal_down")
	assert_eq(_menu().focused_id(), "quit")
	await _press("modal_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL_SELECT)
	assert_true(SaveService.data.get("in_progress") is Dictionary,
		"§18.3 — leaving mid-level costs no more than a suspend")


## §12.1 draws Endless and Daily straight off the main menu, so leaving one has no
## map to go back to.
func test_quitting_an_endless_run_goes_to_the_menu_instead() -> void:
	await _open()
	GameDirector.start_endless(1234)
	await wait_process_frames(1)
	await _press("board_pause")
	for _i: int in range(3):
		await _press("modal_down")
	await _press("modal_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.MAIN_MENU)


## §11.4 — the modal's rows are thumb-reachable like every other affordance.
func test_every_pause_row_meets_the_44px_touch_target() -> void:
	await _open()
	await _press("board_pause")
	await wait_process_frames(2)
	for button: Button in _menu().buttons():
		if not button.visible:
			continue
		assert_gte(button.size.y, MenuList.TOUCH_TARGET,
			"%s is %d px tall" % [button.text, int(button.size.y)])


func _clear_navigated_scenes() -> void:
	for child: Node in get_tree().root.get_children():
		if child.scene_file_path.begins_with("res://src/scenes/"):
			get_tree().root.remove_child(child)
			child.queue_free()

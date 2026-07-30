## @e2e — Feature: Playing a level end to end (§24.2), through the real scene
## tree with injected [InputEvent]s.
##
## §24 states the preference explicitly: end-to-end scenarios covering full flows
## over unit tests. These drive the actual level scene, not a mock of it.
extends GutTest

const LEVEL_SCENE := "res://src/scenes/level/level.tscn"

var _scene: Control = null


func before_each() -> void:
	SaveService.data = {"campaign": {}, "stats": {"undos": 0}, "achievements_mirror": []}


func after_each() -> void:
	_scene = null
	GameDirector.state = null
	GameDirector.level = null


func _open(level: Level) -> void:
	GameDirector.start_level(level)
	_scene = load(LEVEL_SCENE).instantiate()
	add_child_autofree(_scene)
	await wait_process_frames(2)


func _press(keycode: Key, shift: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	ev.shift_pressed = shift
	_scene.get_viewport().push_input(ev)
	await wait_process_frames(1)


func _release(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = false
	_scene.get_viewport().push_input(ev)
	await wait_process_frames(1)


## A destructive action is never a single press (§11.3), so its test has to wait
## out the real hold. Seconds, not frames: headless frames are far shorter than a
## player's, and the gesture is measured in wall time.
func _hold(keycode: Key, seconds: float) -> void:
	await _press(keycode)
	await wait_seconds(seconds)
	await _release(keycode)


func _straight_level() -> Level:
	var lv := Fixtures.fixed_level(Fixtures.shortest_route_tiles())
	lv.id = "e2e_straight"
	lv.par = 6
	return lv


## Scenario: Completing a campaign level (keyboard column of §11.3; M4 adds the
## gamepad and touch variants of this same flow).
func test_a_radius_three_level_is_completable_with_the_keyboard() -> void:
	await _open(_straight_level())
	assert_eq(GameDirector.state.status, GameState.Status.PLAYING)

	for _i: int in range(6):
		await _press(KEY_SPACE)

	assert_eq(GameDirector.state.status, GameState.Status.WON)
	assert_eq(GameDirector.state.placements, 6)
	assert_true(SaveService.data["campaign"].has("e2e_straight"), "completion is recorded")
	assert_eq(int(SaveService.data["campaign"]["e2e_straight"]["stars"]), 3,
		"placements equal par, so three stars")


func test_undo_returns_the_board_to_the_previous_position() -> void:
	await _open(_straight_level())
	await _press(KEY_SPACE)
	await _press(KEY_SPACE)
	assert_eq(GameDirector.state.placements, 2)

	await _press(KEY_Z)
	assert_eq(GameDirector.state.placements, 1)
	assert_eq(int(SaveService.data["stats"]["undos"]), 1)


func test_restart_returns_to_the_opening_position() -> void:
	await _open(_straight_level())
	await _press(KEY_SPACE)
	await _press(KEY_SPACE)

	# A tap is not enough: restart is destructive (§11.3).
	await _press(KEY_R)
	await _release(KEY_R)
	assert_eq(GameDirector.state.placements, 2, "a tap on restart must do nothing")

	await _hold(KEY_R, InputBindings.HOLD_RESTART + 0.2)
	assert_eq(GameDirector.state.placements, 0)
	assert_eq(GameDirector.state.path.size(), 1)


func test_a_dead_board_is_reported_and_is_recoverable() -> void:
	# One tile, six needed: the sequence runs out and the board goes DEAD.
	var lv := Fixtures.fixed_level(["NE"])
	lv.id = "e2e_dead"
	await _open(lv)
	await _press(KEY_SPACE)

	assert_eq(GameDirector.state.status, GameState.Status.DEAD)
	await _press(KEY_Z)
	assert_eq(GameDirector.state.status, GameState.Status.PLAYING,
		"a dead board is a recoverable mistake, never a failure state")


## Scenario: Bumper cycling always reaches every legal target.
func test_cycling_visits_every_legal_target_and_wraps() -> void:
	var lv := Fixtures.fixed_level(["E", "E", "E", "E"])
	# Grow the path first so the E draw offers several anchors.
	await _open(lv)
	var targets := GameDirector.state.legal_targets()
	assert_gt(targets.size(), 0)

	var seen: Dictionary = {}
	for _i: int in range(targets.size()):
		seen[_cursor()] = true
		await _press(KEY_E)
	assert_eq(seen.size(), targets.size(), "every target was visited")
	assert_true(seen.has(_cursor()), "one more press wraps back to a visited target")


## Mouse and trackpad. M3 ticked "mouse click-to-place" on the strength of the
## code existing; it never worked, because the root Control's default
## `mouse_filter` swallowed every pointer event before `_unhandled_input` saw one.
## Hence this test.
func test_a_mouse_click_places_on_the_clicked_cell() -> void:
	await _open(_straight_level())
	var board: BoardView3D = _scene.get_node("%Board")
	var target := Fixtures.START + Direction.delta(Direction.NE)
	assert_true(GameDirector.state.legal_targets().has(target))

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = board.screen_position_of(target)
	_scene.get_viewport().push_input(click, true)
	await wait_process_frames(1)

	assert_eq(GameDirector.state.placements, 1)
	assert_true(GameDirector.state.path.has(target), "the clicked cell joined the path")


## Scenario: Snap navigation never lands on an illegal cell.
##
## Lives in `test_snap_navigation.gd`, at the full 200 inputs §24.2 asks for and
## across every input device rather than the keyboard alone.


func test_the_hint_points_at_an_optimal_next_move() -> void:
	await _open(_straight_level())
	await _hold(KEY_H, InputBindings.HOLD_HINT + 0.2)
	assert_eq(_cursor(), Vector3i(-2, 0, 2))
	assert_eq(GameDirector.hints_used, 1, "hints are unlimited but counted (§12.6)")


func _cursor() -> Vector3i:
	return (_scene.get("_router") as InputRouter).cursor

## @e2e — Feature: Playing a level end to end, gamepad only (§24.2).
##
## Controller is the *primary* input (§11), so this is the playthrough that
## matters most. Every input here is a real [InputEventJoypadButton] or
## [InputEventJoypadMotion] pushed through the viewport: no keyboard fallback, no
## direct calls into the router. If a binding is missing from the §11.3 table, or
## resolves to the wrong action, these tests are what notice.
##
## Deferred by design: the §24.2 scenario opens with "navigate to Campaign,
## chapter 1, level 1", which needs the main menu and level select of M6. The
## navigation leg is asserted there; what is asserted here is that a level plays
## start to finish on the pad alone.
extends GutTest

const LEVEL_SCENE := "res://src/scenes/level/level.tscn"

var _scene: Control = null

## A counter a lambda can actually increment: GDScript captures a local by
## *value*, so `var n := 0` mutated inside a closure would only ever change the
## closure's own copy. A member is reached through `self` and survives.
var _pause_requests: int = 0


func before_each() -> void:
	SaveService.data = {"campaign": {}, "stats": {"undos": 0}, "achievements_mirror": []}
	InputBindings.install()
	_pause_requests = 0
	# EventBus outlives the test, so the subscription is scoped to it explicitly.
	EventBus.pause_requested.connect(_count_pause)


func after_each() -> void:
	EventBus.pause_requested.disconnect(_count_pause)
	_scene = null
	GameDirector.state = null
	GameDirector.level = null


func _open(level: Level) -> void:
	GameDirector.start_level(level)
	_scene = load(LEVEL_SCENE).instantiate()
	add_child_autofree(_scene)
	await wait_process_frames(2)


# --- gamepad input only -------------------------------------------------------

func _button(index: JoyButton, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = index
	ev.pressed = pressed
	_scene.get_viewport().push_input(ev)
	await wait_process_frames(1)


func _tap(index: JoyButton) -> void:
	await _button(index, true)
	await _button(index, false)


func _axis(axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis
	ev.axis_value = value
	_scene.get_viewport().push_input(ev)
	await wait_process_frames(1)


## Holds a button for real time — a destructive action is never a single press.
func _hold_button(index: JoyButton, seconds: float) -> void:
	await _button(index, true)
	await wait_seconds(seconds)
	await _button(index, false)


func _straight_level() -> Level:
	var lv := Fixtures.fixed_level(Fixtures.shortest_route_tiles())
	lv.id = "e2e_pad_straight"
	lv.par = 6
	return lv


## Two NE steps first, so the following E draw has three anchors and the cursor
## has somewhere to cycle. At the opening position a board has exactly one path
## cell, hence exactly one target, and a cycling test would prove nothing.
func _open_with_several_targets() -> void:
	await _open(Fixtures.fixed_level(["NE", "NE", "E", "E", "E", "E"]))
	await _tap(JOY_BUTTON_A)
	await _tap(JOY_BUTTON_A)
	assert_gt(GameDirector.state.legal_targets().size(), 1,
		"the fixture must offer several targets")


## A wild cell one NE step from the start, so a charge is in hand after one press.
func _wild_level() -> Level:
	var board := Board.build(
		3, Fixtures.START, [Fixtures.GOAL] as Array[Vector3i], [], [], [],
		[Vector3i(-2, 0, 2)] as Array[Vector3i]
	)
	var lv := Level.build(board, Fixtures.dirs(Fixtures.shortest_route_tiles()))
	lv.id = "e2e_pad_wild"
	lv.discards = 3
	lv.par = 6
	return lv


func _router() -> InputRouter:
	return _scene.get("_router") as InputRouter


func _cursor() -> Vector3i:
	return _router().cursor


## Scenario: Completing a campaign level with a gamepad only.
func test_completing_a_campaign_level_with_a_gamepad_only() -> void:
	await _open(_straight_level())
	assert_eq(GameDirector.state.status, GameState.Status.PLAYING)

	for _i: int in range(6):
		await _tap(JOY_BUTTON_A)

	assert_eq(GameDirector.state.status, GameState.Status.WON)
	assert_eq(GameDirector.state.placements, 6)
	assert_true(SaveService.data["campaign"].has("e2e_pad_straight"),
		"completion is recorded")
	assert_eq(int(SaveService.data["campaign"]["e2e_pad_straight"]["stars"]), 3,
		"placements equal par, so three stars")


## Scenario: Bumper cycling always reaches every legal target.
##
## Asserted against the router's own clockwise order rather than "all of them in
## any order", because §11.2 promises a rotation — an arbitrary permutation that
## happens to be exhaustive would still feel broken under the thumb.
func test_bumper_cycling_visits_every_target_in_clockwise_order_and_wraps() -> void:
	await _open_with_several_targets()
	var expected := _router().candidates()

	var start_at := expected.find(_cursor())
	assert_gte(start_at, 0, "the cursor starts on a candidate")

	var visited: Array[Vector3i] = [_cursor()]
	for _i: int in range(expected.size() - 1):
		await _tap(JOY_BUTTON_RIGHT_SHOULDER)
		visited.append(_cursor())

	var rotated: Array[Vector3i] = []
	for i: int in range(expected.size()):
		rotated.append(expected[(start_at + i) % expected.size()])
	assert_eq(visited, rotated, "R1 steps clockwise through every target in order")

	await _tap(JOY_BUTTON_RIGHT_SHOULDER)
	assert_eq(_cursor(), visited[0], "one more press wraps to the first")


func test_the_left_bumper_cycles_the_other_way() -> void:
	await _open_with_several_targets()
	var first := _cursor()
	await _tap(JOY_BUTTON_RIGHT_SHOULDER)
	assert_ne(_cursor(), first)
	await _tap(JOY_BUTTON_LEFT_SHOULDER)
	assert_eq(_cursor(), first, "L1 undoes exactly one R1 step")


func test_the_dpad_and_the_left_stick_both_move_the_cursor() -> void:
	await _open_with_several_targets()
	var targets := GameDirector.state.legal_targets()

	for _i: int in range(6):
		await _button(JOY_BUTTON_DPAD_UP, true)
		await _button(JOY_BUTTON_DPAD_UP, false)
		assert_true(targets.has(_cursor()), "the D-pad left the legal set")

	await _axis(JOY_AXIS_LEFT_Y, 1.0)
	await _axis(JOY_AXIS_LEFT_Y, 0.0)
	assert_true(targets.has(_cursor()), "the stick left the legal set")


func test_y_undoes_and_x_discards() -> void:
	await _open(_straight_level())
	await _tap(JOY_BUTTON_A)
	await _tap(JOY_BUTTON_A)
	assert_eq(GameDirector.state.placements, 2)

	await _tap(JOY_BUTTON_Y)
	assert_eq(GameDirector.state.placements, 1, "Y is undo (§11.3)")

	var before := GameDirector.state.discards_left
	await _tap(JOY_BUTTON_X)
	assert_eq(GameDirector.state.discards_left, before - 1, "X is discard (§11.3)")


## L2 + A spends a charge — and the charge is only spendable because arming the
## modifier widens the cursor's reachable set to `wild_targets()`. In snap mode
## the cursor otherwise never leaves `legal_targets`, and every cell a wild charge
## exists to reach would be unreachable.
func test_the_left_trigger_plus_a_spends_a_wild_charge_on_a_normally_illegal_cell() -> void:
	await _open(_wild_level())
	await _tap(JOY_BUTTON_A)
	assert_eq(GameDirector.state.wild_charges, 1, "the wild cell granted a charge")

	var legal := GameDirector.state.legal_targets()
	await _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	assert_gt(_router().candidates().size(), legal.size(),
		"arming the wild widens the reachable set (§6)")

	# Step onto a cell that a normal placement could never reach.
	var stepped := false
	for _i: int in range(_router().candidates().size()):
		if not legal.has(_cursor()):
			stepped = true
			break
		await _tap(JOY_BUTTON_RIGHT_SHOULDER)
	assert_true(stepped, "a wild target outside the legal set is reachable")

	var target := _cursor()
	var placements := GameDirector.state.placements
	await _tap(JOY_BUTTON_A)
	assert_eq(GameDirector.state.wild_charges, 0, "the charge was spent")
	assert_eq(GameDirector.state.placements, placements + 1)
	assert_true(GameDirector.state.path.has(target), "the wild cell joined the path")


func test_releasing_the_trigger_narrows_the_set_back() -> void:
	await _open(_wild_level())
	await _tap(JOY_BUTTON_A)
	var legal := GameDirector.state.legal_targets()

	await _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	assert_gt(_router().candidates().size(), legal.size())

	await _axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	assert_eq(_router().candidates().size(), legal.size(),
		"letting go of L2 puts the cursor back on legal moves only")


## §11.3: "Hold gestures for destructive actions are mandatory."
func test_restart_needs_select_held_and_a_tap_shows_the_legend_instead() -> void:
	await _open(_straight_level())
	await _tap(JOY_BUTTON_A)
	await _tap(JOY_BUTTON_A)
	assert_eq(GameDirector.state.placements, 2)

	var legend: LegendPanel = _scene.get_node("%Legend")
	assert_false(legend.visible, "the legend starts hidden")

	# A tap is the legend, never a restart.
	await _tap(JOY_BUTTON_BACK)
	assert_eq(GameDirector.state.placements, 2, "a tap on Select must not restart")
	assert_true(legend.visible, "a tap on Select toggles the legend (§11.3)")

	await _tap(JOY_BUTTON_BACK)
	assert_false(legend.visible, "and toggles it back")

	# A one-second hold is the restart, and does not also toggle the legend.
	await _hold_button(JOY_BUTTON_BACK, InputBindings.HOLD_RESTART + 0.2)
	assert_eq(GameDirector.state.placements, 0, "holding Select restarts")
	assert_false(legend.visible, "the restart consumed the press")


func test_the_right_trigger_must_be_held_to_hint() -> void:
	await _open(_straight_level())

	await _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	assert_eq(GameDirector.hints_used, 0, "a brushed trigger is not a hint request")

	await _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await wait_seconds(InputBindings.HOLD_HINT + 0.2)
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	assert_eq(GameDirector.hints_used, 1, "holding R2 asks the solver (§12.6)")
	assert_eq(_cursor(), Vector3i(-2, 0, 2), "and points at the optimal move")


## Rewritten when the pause menu arrived. Both buttons still only ask to go up one
## level and neither leaves the game — but Start now opens something, so B's job on
## the second press is to close it rather than to ask again. Asserting two pause
## requests in a row was only ever possible because nothing was listening.
func test_start_and_b_both_ask_to_leave_without_quitting() -> void:
	await _open(_straight_level())
	await _tap(JOY_BUTTON_START)
	assert_eq(_pause_requests, 1, "Start pauses (§11.3)")
	assert_eq(GameDirector.screen, GameDirector.Screen.PAUSED)

	await _tap(JOY_BUTTON_B)
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL,
		"B goes up exactly one level — out of the modal (§12.5)")

	await _tap(JOY_BUTTON_B)
	assert_eq(_pause_requests, 2, "and from the board it asks to leave, never quitting")
	assert_eq(GameDirector.state.status, GameState.Status.PLAYING)


## §11.1 — a set that is not active is not acted on. This is what stops a modal
## from being played through underneath itself.
func test_board_input_is_ignored_while_another_action_set_is_active() -> void:
	await _open(_straight_level())
	InputBindings.activate(InputBindings.SET_MODAL)

	await _tap(JOY_BUTTON_A)
	assert_eq(GameDirector.state.placements, 0,
		"A belongs to the Board set and must do nothing in a Modal")

	InputBindings.activate(InputBindings.SET_BOARD)
	await _tap(JOY_BUTTON_A)
	assert_eq(GameDirector.state.placements, 1, "and works again once Board is live")


func _count_pause() -> void:
	_pause_requests += 1

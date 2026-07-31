## @core — the §11.3 binding table and the §11.1 action sets.
##
## §11 opens with "Controller is the **primary** input … No interaction may be
## exclusive to one device", which is a claim a test can actually check: every
## board action must carry both a keyboard and a gamepad binding. That assertion
## is the one that would have caught M3 shipping arrow-keys-only movement.
extends GutTest

const KEYBOARD_ONLY_EXEMPT: Array[String] = []


func before_all() -> void:
	InputBindings.install()


func test_every_action_is_registered_in_the_input_map() -> void:
	for action: String in InputBindings.ACTIONS:
		assert_true(InputMap.has_action(action), "%s is not in the InputMap" % action)


func test_install_is_idempotent() -> void:
	var before := InputMap.action_get_events("board_confirm").size()
	InputBindings.install()
	assert_eq(InputMap.action_get_events("board_confirm").size(), before,
		"a second install must replace the events, not append them")


## §11: no interaction is exclusive to one device.
func test_every_action_is_bound_on_both_the_keyboard_and_the_gamepad() -> void:
	for action: String in InputBindings.ACTIONS:
		var spec: Dictionary = InputBindings.ACTIONS[action]
		var keys: Array = spec["keys"]
		var pad: int = (spec["buttons"] as Array).size() + (spec["axes"] as Array).size()
		assert_gt(keys.size(), 0, "%s has no keyboard binding" % action)
		assert_gt(pad, 0, "%s has no gamepad binding" % action)


func test_every_action_belongs_to_one_of_the_three_action_sets() -> void:
	var sets := [InputBindings.SET_MENU, InputBindings.SET_BOARD, InputBindings.SET_MODAL]
	for action: String in InputBindings.ACTIONS:
		assert_true(sets.has((InputBindings.ACTIONS[action] as Dictionary)["set"]),
			"%s is in no §11.1 action set" % action)
	# All three sets are populated — §11.1 lists three, not one with two labels.
	for set_name: String in sets:
		assert_gt(InputBindings.actions_in(set_name).size(), 0,
			"the %s set is empty" % set_name)


## The §11.3 gamepad column, row by row. This is the table, so it is asserted
## like `test_direction.gd` asserts Appendix A.
func test_the_gamepad_column_of_the_bindings_table() -> void:
	var expected := {
		"board_confirm": JOY_BUTTON_A,
		"board_back": JOY_BUTTON_B,
		"board_discard": JOY_BUTTON_X,
		"board_undo": JOY_BUTTON_Y,
		"board_cycle_prev": JOY_BUTTON_LEFT_SHOULDER,
		"board_cycle_next": JOY_BUTTON_RIGHT_SHOULDER,
		"board_pause": JOY_BUTTON_START,
		"board_legend": JOY_BUTTON_BACK,
		"board_restart": JOY_BUTTON_BACK,
	}
	for action: String in expected:
		var buttons: Array = (InputBindings.ACTIONS[action] as Dictionary)["buttons"]
		assert_true(buttons.has(expected[action]),
			"%s should be on button %d" % [action, expected[action]])


## L2 + A spends a wild charge, R2 hints: both are analogue triggers, so both are
## axis bindings rather than buttons.
func test_the_triggers_are_bound_as_axes() -> void:
	assert_eq((InputBindings.ACTIONS["board_wild_modifier"] as Dictionary)["axes"],
		[[JOY_AXIS_TRIGGER_LEFT, 1]])
	assert_eq((InputBindings.ACTIONS["board_hint"] as Dictionary)["axes"],
		[[JOY_AXIS_TRIGGER_RIGHT, 1]])


## The M3 leftover: §11.3 wants arrows *and* WASD, which the grey-box never had
## because `D` was Discard. C-20 moved discard to `X` and freed the row.
func test_movement_is_bound_to_both_the_arrows_and_wasd() -> void:
	var rows := {
		"board_move_up": [KEY_UP, KEY_W],
		"board_move_down": [KEY_DOWN, KEY_S],
		"board_move_left": [KEY_LEFT, KEY_A],
		"board_move_right": [KEY_RIGHT, KEY_D],
	}
	for action: String in rows:
		var keys := InputBindings.keys_of(action)
		for code: int in (rows[action] as Array):
			assert_true(keys.has(code), "%s is missing key %d" % [action, code])
	assert_false(InputBindings.keys_of("board_discard").has(KEY_D),
		"D is movement now; discard moved to X (C-20)")
	assert_true(InputBindings.keys_of("board_discard").has(KEY_X))


## §11.3: "Hold gestures for destructive actions are mandatory. Nothing
## destructive on a single press."
func test_only_restart_and_hint_are_holds() -> void:
	assert_eq(InputBindings.hold_seconds("board_restart"), 1.0)
	assert_eq(InputBindings.hold_seconds("board_hint"), 0.5)
	for action: String in InputBindings.ACTIONS:
		if action == "board_restart" or action == "board_hint":
			assert_true(InputBindings.is_hold(action))
		else:
			assert_false(InputBindings.is_hold(action), "%s should fire on press" % action)


## Two physical inputs carry two actions each, by design (§11.3). Any *other*
## collision is a mistake, so the intended ones are pinned here.
func test_the_only_shared_inputs_are_the_ones_the_spec_asks_for() -> void:
	var by_key: Dictionary = {}
	for action: String in InputBindings.actions_in(InputBindings.SET_BOARD):
		for code: int in InputBindings.keys_of(action):
			if not by_key.has(code):
				by_key[code] = [] as Array[String]
			(by_key[code] as Array[String]).append(action)

	var shared: Array[String] = []
	for code: Variant in by_key:
		var actions: Array[String] = by_key[code]
		if actions.size() > 1:
			actions.sort()
			shared.append(",".join(actions))
	shared.sort()
	assert_eq(shared, ["board_back,board_pause"] as Array[String],
		"Esc is deliberately pause-and-back; nothing else may share a key")

	# Select carries both, on the gamepad side.
	assert_eq(
		(InputBindings.ACTIONS["board_legend"] as Dictionary)["buttons"],
		(InputBindings.ACTIONS["board_restart"] as Dictionary)["buttons"],
		"a tap on Select shows the legend, a hold restarts (§11.3)"
	)


## §11.1 — a set that is not active is not acted on, which is what stops a modal
## from being played through.
func test_only_the_active_set_reports_as_active() -> void:
	InputBindings.activate(InputBindings.SET_BOARD)
	assert_true(InputBindings.is_active("board_confirm"))
	assert_false(InputBindings.is_active("menu_accept"))
	assert_false(InputBindings.is_active("modal_back"))

	InputBindings.activate(InputBindings.SET_MODAL)
	assert_false(InputBindings.is_active("board_confirm"))
	assert_true(InputBindings.is_active("modal_back"))

	InputBindings.activate(InputBindings.SET_MENU)
	assert_true(InputBindings.is_active("menu_accept"))
	assert_false(InputBindings.is_active("board_confirm"))

	InputBindings.activate(InputBindings.SET_BOARD)


func test_an_unknown_action_is_never_active_and_never_a_hold() -> void:
	assert_false(InputBindings.is_active("board_teleport"))
	assert_false(InputBindings.is_hold("board_teleport"))
	assert_eq(InputBindings.glyph_slot("board_teleport"), "")


## Bound in M4 so the C-18 camera does not have to rewrite the table in M7.
func test_the_rotation_actions_exist_ready_for_the_c18_camera() -> void:
	assert_true(InputMap.has_action("board_rotate_cw"))
	assert_true(InputMap.has_action("board_rotate_ccw"))
	assert_eq((InputBindings.ACTIONS["board_rotate_cw"] as Dictionary)["axes"],
		[[JOY_AXIS_RIGHT_X, 1]])


## §11.2 on a real thumb: a stick is not a button.
##
## It emits a fresh event on every change in its axis, and a thumb resting past the
## deadzone changes it constantly — so a single flick landed three or four moves
## and the cursor shot across the board. The router rate-limits analogue input the
## way a keyboard rate-limits a held key: immediate, then a pause, then a steady
## repeat.
func _router_over_a_row() -> InputRouter:
	# Four candidates in a line, cursor seeded on the leftmost, so "right" always
	# has somewhere to go and the geometry is not what is under test.
	var router := InputRouter.new()
	var cells: Array[Vector3i] = [
		Vector3i(0, 0, 0), Vector3i(1, -1, 0), Vector3i(2, -2, 0), Vector3i(3, -3, 0)]
	var positions: Dictionary = {}
	for i: int in range(cells.size()):
		positions[cells[i]] = Vector2(float(i) * 60.0, 0.0)
	router.set_candidates(cells, positions, Vector2(90.0, 0.0))
	router.cursor = cells[0]
	router.has_cursor = true
	return router


func test_a_held_stick_repeats_rather_than_streaming() -> void:
	var router := _router_over_a_row()
	assert_true(router.move(Vector2.RIGHT, true), "the first push moves at once")
	assert_false(router.move(Vector2.RIGHT, true), "and the stream behind it does not")
	assert_false(router.move(Vector2.RIGHT, true), "however many events arrive")


## The gate is for sticks only. A D-pad and a key are discrete: every press is a
## press, and §11 does not let one device be worse to play on than another.
func test_a_dpad_or_a_key_is_never_rate_limited() -> void:
	var router := _router_over_a_row()
	var moved := 0
	for _i: int in range(3):
		if router.move(Vector2.RIGHT):
			moved += 1
	assert_eq(moved, 3, "three presses are three moves")

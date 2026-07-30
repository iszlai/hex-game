## @e2e — Feature: snap navigation over a hex lattice (§11.2, §24.2).
##
## The §11.2 promise is absolute: "The cursor only ever occupies a cell in
## `legal_targets`". Directional input on six-way geometry is the hard problem of
## this game's input, and a cone that mis-picks is the kind of bug that survives
## every unit test and ruins the game in the hand — so it is fuzzed.
extends GutTest

const LEVEL_SCENE := "res://src/scenes/level/level.tscn"

## §24.2: "When I send 200 random directional inputs".
const FUZZ_INPUTS := 200

## Interleave a confirm now and then, so the candidate set actually changes
## underneath the cursor. Fuzzing a static set proves almost nothing.
const CONFIRM_EVERY := 7

var _scene: Control = null
var _illegal_attempts: int = 0
var _saved_cursor_mode: String = "snap"


func before_each() -> void:
	SaveService.data = {"campaign": {}, "stats": {"undos": 0}, "achievements_mirror": []}
	InputBindings.install()
	_illegal_attempts = 0
	_saved_cursor_mode = str(SettingsService.get_value("cursor_mode"))
	EventBus.illegal_move_attempted.connect(_count_illegal)


func after_each() -> void:
	EventBus.illegal_move_attempted.disconnect(_count_illegal)
	SettingsService.set_value("cursor_mode", _saved_cursor_mode)
	_scene = null
	GameDirector.state = null
	GameDirector.level = null


func _open(level: Level) -> void:
	GameDirector.start_level(level)
	_scene = load(LEVEL_SCENE).instantiate()
	add_child_autofree(_scene)
	await wait_process_frames(2)


func _router() -> InputRouter:
	return _scene.get("_router") as InputRouter


func _cursor() -> Vector3i:
	return _router().cursor


func _key(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	_scene.get_viewport().push_input(down)
	await wait_process_frames(1)


func _pad(index: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = index
	ev.pressed = true
	_scene.get_viewport().push_input(ev)
	await wait_process_frames(1)


func _stick(axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis
	ev.axis_value = value
	_scene.get_viewport().push_input(ev)
	await wait_process_frames(1)


## One random directional input, from a random device. Which device it came from
## must not matter — that is half of what is being asserted.
func _random_direction(rng: RandomNumberGenerator) -> void:
	match rng.randi_range(0, 11):
		0: await _key(KEY_UP)
		1: await _key(KEY_DOWN)
		2: await _key(KEY_LEFT)
		3: await _key(KEY_RIGHT)
		4: await _key(KEY_W)
		5: await _key(KEY_S)
		6: await _pad(JOY_BUTTON_DPAD_UP)
		7: await _pad(JOY_BUTTON_DPAD_DOWN)
		8: await _pad(JOY_BUTTON_DPAD_LEFT)
		9: await _pad(JOY_BUTTON_DPAD_RIGHT)
		10: await _stick(JOY_AXIS_LEFT_Y, rng.randf_range(-1.0, -0.6))
		11: await _stick(JOY_AXIS_LEFT_X, rng.randf_range(0.6, 1.0))


## Scenario: Snap navigation never lands on an illegal cell.
func test_two_hundred_random_directional_inputs_never_leave_the_legal_set() -> void:
	# A seeded bag rather than a fixed tile list, so the stream never runs dry
	# under 200 inputs and the board keeps offering fresh geometry.
	await _open(Fixtures.seeded_level(918273))

	var rng := RandomNumberGenerator.new()
	rng.seed = 918273
	var checks := 0
	var restarts := 0

	for i: int in range(FUZZ_INPUTS):
		if GameDirector.state.status != GameState.Status.PLAYING:
			EventBus.restart_requested.emit()
			await wait_process_frames(1)
			restarts += 1

		await _random_direction(rng)

		if GameDirector.state.status != GameState.Status.PLAYING:
			continue
		var legal := GameDirector.state.legal_targets()
		if legal.is_empty():
			continue
		assert_true(legal.has(_cursor()),
			"input %d put the cursor on %v, which is not a legal target" % [i, _cursor()])
		checks += 1

		if i % CONFIRM_EVERY == CONFIRM_EVERY - 1:
			await _key(KEY_SPACE)

	assert_gt(checks, FUZZ_INPUTS / 2,
		"the fuzz must actually have checked a live board, not a finished one")
	assert_eq(_illegal_attempts, 0, "no illegal placement was ever committed")
	gut.p("fuzz: %d inputs, %d cursor checks, %d restarts" % [FUZZ_INPUTS, checks, restarts])


## §11.2 — the cursor holds still and ticks when nothing is inside the cone.
func test_an_input_with_no_candidate_in_the_cone_leaves_the_cursor_where_it_was() -> void:
	await _open(Fixtures.fixed_level(Fixtures.shortest_route_tiles()))
	assert_eq(GameDirector.state.legal_targets().size(), 1,
		"the opening position offers exactly one target")

	var before := _cursor()
	await _key(KEY_DOWN)
	assert_eq(_cursor(), before, "there is nowhere legal to go, so nothing moves")


## §11.2 — "3 failed cone rejections in a row → surface a hint toast", naming the
## input that always works.
func test_three_cone_rejections_surface_the_bumper_cycling_hint() -> void:
	await _open(Fixtures.fixed_level(Fixtures.shortest_route_tiles()))
	var banner: PanelContainer = _scene.get_node("%Banner")
	var banner_label: Label = _scene.get_node("%BannerLabel")
	banner.visible = false

	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	assert_false(banner.visible, "two rejections is not yet a struggle")

	await _key(KEY_DOWN)
	assert_true(banner.visible, "the third rejection surfaces the hint (§11.2)")
	assert_string_contains(banner_label.text, InputGlyphs.label_for("board_cycle_prev"))
	assert_string_contains(banner_label.text, InputGlyphs.label_for("board_cycle_next"))


## The free-cursor scheme of §11.2 is a Settings option. The screen itself is M5,
## so what is verified here is that the router follows the setting live — which is
## all the Settings screen will have to do.
func test_the_cursor_mode_follows_the_setting_without_a_reload() -> void:
	await _open(Fixtures.fixed_level(Fixtures.shortest_route_tiles()))
	assert_eq(_router().mode, InputRouter.Mode.SNAP, "snap is the default (§11.2)")

	SettingsService.set_value("cursor_mode", "free")
	await wait_process_frames(1)
	assert_eq(_router().mode, InputRouter.Mode.FREE)

	SettingsService.set_value("cursor_mode", "snap")
	await wait_process_frames(1)
	assert_eq(_router().mode, InputRouter.Mode.SNAP)


func _count_illegal(_cell: Vector3i) -> void:
	_illegal_attempts += 1

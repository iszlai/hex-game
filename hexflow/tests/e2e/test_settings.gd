## @e2e — Feature: settings (§12.2's five tabs), through the real scene.
##
## A settings screen is easy to build and easy to build *wrong*: the failure mode
## is a control that moves on screen and changes nothing, or one that writes a key
## nothing reads. So every assertion below goes from a key press to
## [SettingsService] and, where the setting does something else as well, to the
## thing it does.
extends GutTest

const SCENE := "res://src/scenes/settings/settings.tscn"

var _scene: Control = null
var _saved: Dictionary = {}


func before_each() -> void:
	# Settings persist to disk by design (§17.3), so the values are put back
	# afterwards rather than left as whatever the last assertion set them to.
	_saved = {}
	for key: Variant in SettingsService.DEFAULTS:
		_saved[key] = SettingsService.get_value(str(key))


func after_each() -> void:
	var pending: Variant = GameDirector.get("_transition")
	if pending is Tween and (pending as Tween).is_running():
		(pending as Tween).kill()
	if _scene != null and is_instance_valid(_scene):
		_scene.get_parent().remove_child(_scene)
		_scene.queue_free()
	_scene = null
	_clear_navigated_scenes()
	for key: Variant in _saved:
		SettingsService.set_value(str(key), _saved[key])
	# Putting `custom_bindings` back is not enough on its own: the `InputMap` still
	# holds whatever the last rebind installed, and the next test would then press
	# a key that no longer means what it says.
	InputBindings.install()
	GameDirector.state = null
	GameDirector.level = null
	GameDirector.screen = GameDirector.Screen.LEVEL


func _open() -> void:
	GameDirector.screen = GameDirector.Screen.SETTINGS
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


## Moves focus onto a row by id, however many presses that takes.
func _focus(id: String) -> void:
	for _i: int in range(InputBindings.ACTIONS.size() + 8):
		if _menu().focused_id() == id:
			return
		await _press("menu_down")
	assert_eq(_menu().focused_id(), id, "never reached the %s row" % id)


func _to_tab(name: String) -> void:
	for _i: int in range(_scene.get("TABS").size()):
		if str(_scene.call("tab_name")) == name:
			return
		await _press("menu_cycle_next")
	assert_eq(str(_scene.call("tab_name")), name)


func test_all_five_tabs_are_there_and_the_first_is_the_default() -> void:
	await _open()
	assert_eq(_scene.get("TABS"),
		["Gameplay", "Controls", "Video", "Audio", "Accessibility"] as Array[String],
		"§12.2's five, in its order")
	assert_eq(str(_scene.call("tab_name")), "Gameplay", "§12.2: default focus is the first tab")


func test_the_bumpers_page_through_the_tabs_and_wrap() -> void:
	await _open()
	await _press("menu_cycle_next")
	assert_eq(str(_scene.call("tab_name")), "Controls")
	await _press("menu_cycle_prev")
	assert_eq(str(_scene.call("tab_name")), "Gameplay")
	await _press("menu_cycle_prev")
	assert_eq(str(_scene.call("tab_name")), "Accessibility", "tabs wrap; §12.5's list rule")


## Every row of every tab must name a real settings key or a real action. A typo
## here is a control that moves and changes nothing, which is the exact failure a
## settings screen is prone to.
func test_every_row_names_something_that_exists() -> void:
	await _open()
	for tab: String in _scene.get("TABS"):
		for row: Variant in _scene.call("rows_of", tab):
			var spec: Dictionary = row
			var key: String = str(spec.get("key", ""))
			if key == "":
				assert_ne(str(spec.get("action", "")), "",
					"a row in %s stores nothing and does nothing" % tab)
				continue
			assert_true(SettingsService.DEFAULTS.has(key),
				"%s names a settings key that does not exist: %s" % [tab, key])
			# And the value it displays is derived from the live setting, never a
			# placeholder, so what is on screen is what is stored.
			assert_ne(str(_scene.call("value_text", spec)), "",
				"%s in %s shows nothing" % [key, tab])


func test_a_toggle_writes_the_setting_it_names() -> void:
	await _open()
	await _focus("hold_to_confirm")
	var before: bool = bool(SettingsService.get_value("hold_to_confirm"))
	await _press("menu_left")
	assert_eq(bool(SettingsService.get_value("hold_to_confirm")), not before)
	await _press("menu_right")
	assert_eq(bool(SettingsService.get_value("hold_to_confirm")), before)


## The one already wired to gameplay: §11.2's cursor mode, which `level.gd` has
## been following on `SettingsService.changed` since M4 with nothing to write it.
func test_the_cursor_mode_this_screen_writes_is_the_one_the_board_reads() -> void:
	await _open()
	await _focus("cursor_mode")
	assert_eq(str(SettingsService.get_value("cursor_mode")), "snap")
	await _press("menu_right")
	assert_eq(str(SettingsService.get_value("cursor_mode")), "free")

	var level: Control = load("res://src/scenes/level/level.tscn").instantiate()
	GameDirector.start_level(LevelRepository.load_level(1, 1))
	add_child_autofree(level)
	await wait_process_frames(2)
	var router: InputRouter = level.get("_router") as InputRouter
	assert_eq(router.mode, InputRouter.Mode.FREE, "the board opened in the mode that was set")


func test_a_range_steps_and_stops_at_its_ends() -> void:
	await _open()
	await _to_tab("Audio")
	await _focus("music_volume")
	SettingsService.set_value("music_volume", 100)
	await _press("menu_right")
	assert_eq(int(SettingsService.get_value("music_volume")), 100, "and does not wrap past the top")
	await _press("menu_left")
	assert_lt(int(SettingsService.get_value("music_volume")), 100)

	SettingsService.set_value("music_volume", 0)
	await _press("menu_left")
	assert_eq(int(SettingsService.get_value("music_volume")), 0, "nor below the bottom")


## §21: text scaling 100–150%, "applied to every string". The proof is that the
## theme on the window actually changes, not that a number in a dictionary did.
func test_text_scale_reaches_the_type_it_is_supposed_to_scale() -> void:
	await _open()
	await _to_tab("Accessibility")
	await _focus("text_scale")
	SettingsService.set_value("text_scale", 1.0)
	GameDirector.apply_typography()
	var before: int = get_tree().root.theme.get_font_size(
		"font_size", Typography.variation_for(Typography.Role.BODY)
	)
	await _press("menu_right")
	assert_gt(float(SettingsService.get_value("text_scale")), 1.0)
	var after: int = get_tree().root.theme.get_font_size(
		"font_size", Typography.variation_for(Typography.Role.BODY)
	)
	assert_gt(after, before, "the window's own theme grew with the setting")


## §21's range is 1.0–1.5 and nothing this screen offers may leave it.
func test_no_offered_text_scale_is_outside_the_range_the_spec_allows() -> void:
	await _open()
	for row: Variant in _scene.call("rows_of", "Accessibility"):
		var spec: Dictionary = row
		if str(spec.get("key", "")) != "text_scale":
			continue
		for value: Variant in (spec["values"] as Array):
			assert_between(float(value), Typography.MIN_SCALE, Typography.MAX_SCALE)


## §21: "a reset-to-default is always one press away".
func test_resetting_the_bindings_is_one_press_away() -> void:
	SettingsService.set_value("custom_bindings", {"board_undo": {"keys": [KEY_J]}})
	await _open()
	await _to_tab("Controls")
	await _focus("reset_bindings")
	await _press("menu_accept")
	assert_eq(SettingsService.get_value("custom_bindings"), {},
		"one press, from a row that is always on the Controls tab")


## §12.5 — Back goes up exactly one level, and Settings has two parents. Which one
## is the door it was opened by, never a guess from whether a run happens to exist.
func test_back_returns_through_the_door_it_was_opened_by() -> void:
	GameDirector.screen = GameDirector.Screen.MAIN_MENU
	GameDirector.open_settings()
	await _open()
	await _press("menu_back")
	assert_eq(GameDirector.screen, GameDirector.Screen.MAIN_MENU)

	# Opened from the pause modal instead: back goes to the board, not the menu —
	# even though a `state` left lying around would have said "menu" either way.
	GameDirector.start_level(LevelRepository.load_level(1, 1))
	GameDirector.screen = GameDirector.Screen.PAUSED
	GameDirector.open_settings()
	await _open()
	await _press("menu_back")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL)


func _clear_navigated_scenes() -> void:
	for child: Node in get_tree().root.get_children():
		if child.scene_file_path.begins_with("res://src/scenes/"):
			get_tree().root.remove_child(child)
			child.queue_free()


## §21: "Every action rebindable per device". Every action means
## [InputBindings]' table, not a hand-kept copy of it — a list that would rot the
## first time an action was added.
func test_the_controls_tab_offers_every_action_there_is() -> void:
	await _open()
	var bound: Array[String] = []
	for row: Variant in _scene.call("rows_of", "Controls"):
		var spec: Dictionary = row
		if str(spec.get("kind", "")) == "bind":
			bound.append(str(spec["action"]))
	for action: String in InputBindings.ACTIONS:
		assert_true(bound.has(action), "%s cannot be rebound" % action)


## The rebind, end to end: a key press while capturing becomes the binding, and
## the binding is what `InputMap` answers with afterwards — not just what the save
## file says.
func test_rebinding_an_action_changes_what_the_key_does() -> void:
	await _open()
	await _to_tab("Controls")
	await _focus("board_undo")
	assert_eq(InputBindings.keys_of("board_undo")[0], KEY_Z)

	await _press("menu_accept")
	await _key(KEY_J)
	assert_eq(InputBindings.keys_of("board_undo")[0], KEY_J)

	var ev := InputEventKey.new()
	ev.keycode = KEY_J
	ev.pressed = true
	assert_true(ev.is_action_pressed("board_undo"), "and the InputMap agrees")


## §11.3 shares Esc and Select on purpose. A collision the *player* creates by
## accident is different: it leaves a control unresponsive with no way to find out
## why, so it is refused and named.
func test_a_collision_inside_one_action_set_is_refused_and_named() -> void:
	await _open()
	await _to_tab("Controls")
	await _focus("board_undo")
	await _press("menu_accept")
	await _key(KEY_X)
	assert_eq(InputBindings.keys_of("board_undo")[0], KEY_Z, "the rebind was refused")
	var hint: Label = _scene.get_node("%HintLabel") as Label
	assert_string_contains(hint.text, "discard", "and the screen says who has it")


## Cross-set collisions are the whole point of §11.1 — Space means confirm on the
## board and accept in a modal — so they must not be refused.
func test_a_collision_across_action_sets_is_allowed() -> void:
	await _open()
	await _to_tab("Controls")
	await _focus("menu_cycle_next")
	await _press("menu_accept")
	await _key(KEY_H)
	assert_eq(InputBindings.keys_of("menu_cycle_next")[0], KEY_H,
		"board_hint also uses H, in another set, which is not a conflict")


func test_escape_cancels_a_capture_without_binding_it() -> void:
	await _open()
	await _to_tab("Controls")
	await _focus("board_undo")
	await _press("menu_accept")
	await _key(KEY_ESCAPE)
	assert_eq(InputBindings.keys_of("board_undo")[0], KEY_Z)
	# And the screen is a screen again rather than a capture.
	await _press("menu_cycle_prev")
	assert_eq(str(_scene.call("tab_name")), "Gameplay")


## §21's reset, over a rebind that actually happened.
func test_reset_puts_every_binding_back_where_the_table_says() -> void:
	await _open()
	await _to_tab("Controls")
	await _focus("board_undo")
	await _press("menu_accept")
	await _key(KEY_J)
	assert_eq(InputBindings.keys_of("board_undo")[0], KEY_J)

	await _focus("reset_bindings")
	await _press("menu_accept")
	assert_eq(InputBindings.keys_of("board_undo")[0], KEY_Z,
		"the default is the §11.3 table, never a copy of it kept elsewhere")


## Sends a raw key, bypassing the action lookup — during a capture the point is
## that the *keycode* is what matters, not what it is currently bound to.
func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	_scene.get_viewport().push_input(ev)
	await wait_process_frames(1)


## §21: "a reset-to-default is always one press away." The Controls tab has had one
## since rebinding landed; it belongs on every tab that can be changed — a player
## who has moved four sliders and can no longer hear the game needs a way back that
## does not involve remembering what 85 was.
func test_every_changeable_tab_offers_a_reset() -> void:
	await _open()
	for tab: String in ["Gameplay", "Video", "Audio", "Accessibility"]:
		var found: bool = false
		for row: Variant in _scene.call("rows_of", tab):
			if str((row as Dictionary).get("action", "")).begins_with("reset"):
				found = true
		assert_true(found, "%s cannot be put back" % tab)


## Per tab, not per screen. Resetting the volumes must not also take away the
## palette and the text size — the two settings a player is least likely to have
## changed by accident, and the two it would hurt most to lose.
func test_a_reset_puts_back_its_own_tab_and_nothing_else() -> void:
	SettingsService.set_value("music_volume", 5)
	SettingsService.set_value("sfx_volume", 10)
	SettingsService.set_value("text_scale", 1.5)
	SettingsService.set_value("palette", "high_contrast")

	await _open()
	await _to_tab("Audio")
	await _focus("reset_tab")
	await _press("menu_accept")

	assert_eq(int(SettingsService.get_value("music_volume")),
		int(SettingsService.DEFAULTS["music_volume"]), "the tab is back")
	assert_eq(int(SettingsService.get_value("sfx_volume")),
		int(SettingsService.DEFAULTS["sfx_volume"]))
	assert_eq(float(SettingsService.get_value("text_scale")), 1.5,
		"and the accessibility tab was left alone")
	assert_eq(str(SettingsService.get_value("palette")), "high_contrast")

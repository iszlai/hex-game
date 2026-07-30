## @e2e — Feature: persistence (§18), and §12.5's Steam-overlay pause.
##
## M5's exit criterion, and the half of it that cannot be checked by reading the
## code: a save that has gone wrong has to leave the player somewhere playable,
## and a run has to survive being walked away from — from *any* screen, not only
## the one the happy path leaves by.
extends GutTest

var _screen: Node = null


func before_each() -> void:
	_clear()
	SaveService.data = SaveService._defaults()
	GameDirector.last_result = {}


func after_each() -> void:
	var pending: Variant = GameDirector.get("_transition")
	if pending is Tween and (pending as Tween).is_running():
		(pending as Tween).kill()
	_clear()
	GameDirector.state = null
	GameDirector.level = null
	GameDirector.screen = GameDirector.Screen.LEVEL
	GameDirector.mode = GameDirector.Mode.CAMPAIGN
	SaveService.data = SaveService._defaults()
	_erase_save()


func _clear() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.get_parent().remove_child(_screen)
		_screen.queue_free()
	_screen = null
	for child: Node in get_tree().root.get_children():
		if child.scene_file_path.begins_with("res://src/scenes/"):
			get_tree().root.remove_child(child)
			child.queue_free()


func _erase_save() -> void:
	for path: String in [SaveService.PATH, SaveService.PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_save(text: String) -> void:
	var f := FileAccess.open(SaveService.PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _follow() -> void:
	var pending: Variant = GameDirector.get("_transition")
	if pending is Tween and (pending as Tween).is_running():
		(pending as Tween).kill()
	_clear()
	var path: String = str(GameDirector.SCENES.get(GameDirector.screen, ""))
	if path == "":
		return
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


## §18.5 — back up, notify **once**, continue with defaults. Never crash.
func test_a_corrupted_save_reaches_the_menu_with_defaults_and_notifies_once() -> void:
	_write_save("{ this is not json")
	var notices: Array[String] = []
	var handler := func(reason: String) -> void: notices.append(reason)
	SaveService.save_recovered.connect(handler)
	SaveService.data = SaveService._defaults()
	SaveService.load_from_disk()
	SaveService.save_recovered.disconnect(handler)

	assert_eq(notices.size(), 1, "once, not once per read")
	assert_eq(SaveService.data["campaign"], {}, "and the defaults are what is left")
	assert_true(FileAccess.file_exists("user://save.corrupt.bak"),
		"§18.5 keeps the bad file rather than deleting the player's history")

	# And the game is playable from it: the menu opens and the campaign is there.
	GameDirector.screen = GameDirector.Screen.MAIN_MENU
	await _follow()
	await _press("menu_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL_SELECT)


## §18.4 — a save from a newer build is never silently overwritten.
func test_a_newer_save_is_quarantined_rather_than_downgraded() -> void:
	_write_save(JSON.stringify({"schema": SaveService.SCHEMA + 5, "campaign": {"c1_l01": {}}}))
	SaveService.data = SaveService._defaults()
	SaveService.load_from_disk()
	assert_eq(SaveService.data["schema"], SaveService.SCHEMA)
	assert_eq(SaveService.data["campaign"], {}, "the newer file was not read into this build")
	assert_true(FileAccess.file_exists("user://save.schema_%d.bak" % (SaveService.SCHEMA + 5)))


## §18.3 — the run is on disk before the player is gone, from every screen that
## can take them off the board. Each of these is a different exit and each was a
## different chance to lose the run.
func test_progress_survives_a_quit_from_three_different_screens() -> void:
	for exit: String in ["suspend", "pause_quit", "window_close"]:
		SaveService.data = SaveService._defaults()
		GameDirector.start_level(LevelRepository.load_level(1, 1))
		GameDirector.screen = GameDirector.Screen.LEVEL
		EventBus.place_requested.emit(GameDirector.state.legal_targets()[0])
		var placements: int = GameDirector.state.placements
		SaveService.data["in_progress"] = null

		match exit:
			"suspend":
				GameDirector.suspend()
			"pause_quit":
				GameDirector.pause()
				await _follow()
				GameDirector.suspend()
				GameDirector.go_to(GameDirector.level_exit_screen())
			"window_close":
				GameDirector._notification(NOTIFICATION_WM_CLOSE_REQUEST)

		var payload: Variant = SaveService.data.get("in_progress")
		assert_true(payload is Dictionary, "%s lost the run" % exit)
		assert_eq(int((payload as Dictionary)["placements"]), placements, "%s" % exit)
		_clear()


## §12.5: "Opening the Steam overlay must pause gameplay automatically."
func test_the_steam_overlay_pauses_the_game() -> void:
	GameDirector.start_level(LevelRepository.load_level(1, 1))
	GameDirector.screen = GameDirector.Screen.LEVEL
	await _follow()
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL)

	SteamService.notify_overlay(true)
	await wait_process_frames(1)
	assert_eq(GameDirector.screen, GameDirector.Screen.PAUSED)
	assert_eq(InputBindings.active_set, InputBindings.SET_MODAL, "and the board is not playable")


## Closing the overlay deliberately does not unpause: the player was taken out of
## the game by something that was not the game, and dropping them straight back
## onto a live board is how a move gets made by somebody reading a chat message.
func test_closing_the_overlay_does_not_hand_the_board_back_unasked() -> void:
	GameDirector.start_level(LevelRepository.load_level(1, 1))
	GameDirector.screen = GameDirector.Screen.LEVEL
	await _follow()
	SteamService.notify_overlay(true)
	SteamService.notify_overlay(false)
	await wait_process_frames(1)
	assert_eq(GameDirector.screen, GameDirector.Screen.PAUSED)


## §23.1 — Steam being absent is the normal case for a launch outside Steam, and
## it must not turn the overlay wiring into an error.
func test_the_overlay_wiring_is_harmless_with_no_steam_at_all() -> void:
	assert_false(SteamService.available, "there is no Steam API in this build yet")
	GameDirector.screen = GameDirector.Screen.MAIN_MENU
	SteamService.notify_overlay(true)
	await wait_process_frames(1)
	assert_eq(GameDirector.screen, GameDirector.Screen.MAIN_MENU,
		"nothing to pause on a menu, and nothing that errors either")

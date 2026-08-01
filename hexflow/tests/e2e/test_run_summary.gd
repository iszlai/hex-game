## @e2e — Feature: the endless run summary (§12.2, §12.1's
## `Endless → RunSummary : DEAD`).
##
## The arrow §12.1 draws for endless and nothing implemented: a dead board was a
## recoverable banner in all three modes, which is right for the campaign (§5.8)
## and wrong for a run with no undo (§7.2). This is where a run stops.
extends GutTest

const SCENE := "res://src/scenes/run_summary/run_summary.tscn"

var _scene: Control = null


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
	if _scene != null and is_instance_valid(_scene):
		_scene.get_parent().remove_child(_scene)
		_scene.queue_free()
	_scene = null
	_clear_navigated_scenes()
	GameDirector.state = null
	GameDirector.level = null
	GameDirector.mode = GameDirector.Mode.CAMPAIGN
	GameDirector.screen = GameDirector.Screen.LEVEL
	before_each()


func _open() -> void:
	GameDirector.screen = GameDirector.Screen.RUN_SUMMARY
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


## Plays a run out until the board it dies on. Bounded, because a test that could
## loop forever on a bad generator is worse than a failing one.
##
## A won stage has to be waved on (C-35): reaching a goal no longer replaces the
## board on the same frame, so a loop that stopped at "not PLAYING" would stop at
## the first goal and never see a death.
func _run_to_death(p_seed: int = 4242) -> void:
	GameDirector.start_endless(p_seed)
	for _i: int in range(1200):
		if GameDirector.state.status == GameState.Status.DEAD:
			return
		if GameDirector.state.status == GameState.Status.WON:
			EventBus.advance_requested.emit()
			await wait_process_frames(2)
			continue
		var targets: Array[Vector3i] = GameDirector.state.legal_targets()
		if targets.is_empty():
			EventBus.discard_requested.emit()
			continue
		EventBus.place_requested.emit(targets[0])
	assert_eq(GameDirector.state.status, GameState.Status.DEAD,
		"the run has to actually end for anything below to mean something")


## §12.1's arrow. §14.1's dead-state desaturation runs first, so the player sees
## the board they died on before the card takes it away.
func test_a_dead_endless_board_ends_the_run() -> void:
	await _run_to_death()
	assert_eq(GameDirector.state.status, GameState.Status.DEAD)
	assert_ne(GameDirector.screen, GameDirector.Screen.RUN_SUMMARY, "not instantly")
	await wait_seconds(Motion.seconds("dead_desaturate") + 0.3)
	assert_eq(GameDirector.screen, GameDirector.Screen.RUN_SUMMARY)


## §5.8 makes a dead board recoverable, and it still is — everywhere the mode has
## a way back out of one. Only §7.2's run, which has no undo, actually ends.
func test_a_dead_campaign_board_is_still_only_a_banner() -> void:
	GameDirector.start_level(LevelRepository.load_level(1, 1))
	GameDirector.screen = GameDirector.Screen.LEVEL
	EventBus.level_dead.emit(GameState.Dead.PATH_FROZEN)
	await wait_seconds(Motion.seconds("dead_desaturate") + 0.3)
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL)


func test_the_run_is_recorded_when_it_ends() -> void:
	await _run_to_death()
	var endless: Dictionary = SaveService.data["endless"]
	assert_eq(int(endless["runs"]), 1, "the run counted")
	assert_eq(int(endless["best_goals"]), int(GameDirector.last_result["goals"]))


## §7.2: "Score = goals_reached". The placement count is the tie-break, not the
## score, so it does not get to be the big number.
func test_the_card_reports_goals_and_the_personal_best() -> void:
	GameDirector.last_result = {
		"mode": GameDirector.Mode.ENDLESS, "goals": 7, "placements": 61, "best": true,
	}
	SaveService.data["endless"] = {"best_goals": 7, "best_placements_at_best": 61, "runs": 3}
	await _open()
	assert_string_contains((_scene.get_node("%ScoreLabel") as Label).text, "7 goals")
	assert_string_contains((_scene.get_node("%BestLabel") as Label).text.to_lower(),
		"personal best")

	GameDirector.last_result["best"] = false
	SaveService.data["endless"]["best_goals"] = 12
	await _open()
	assert_string_contains((_scene.get_node("%BestLabel") as Label).text, "12",
		"a run that is not the best still says what the best is")


## §12.2's default focus for this screen is Retry.
func test_focus_opens_on_retry() -> void:
	await _open()
	assert_eq(_menu().focused_id(), "retry")


func test_retry_starts_a_new_run_rather_than_the_dead_one_again() -> void:
	await _run_to_death()
	# The dead run itself, not its placement count: a stage can die on its opening
	# frame, so "placements changed" is not the same claim as "this is a new run".
	var dead: GameState = GameDirector.state
	await _open()
	await _press("menu_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL)
	assert_eq(GameDirector.mode, GameDirector.Mode.ENDLESS)
	assert_ne(GameDirector.state, dead, "a new run, not the dead one handed back")
	assert_eq(GameDirector.state.status, GameState.Status.PLAYING)


## §12.1 draws Endless straight off the main menu, so that is the one level up.
func test_menu_and_back_both_return_to_the_main_menu() -> void:
	await _open()
	await _press("menu_back")
	assert_eq(GameDirector.screen, GameDirector.Screen.MAIN_MENU)

	await _open()
	await _press("menu_down")
	await _press("menu_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.MAIN_MENU)


## §23's Steam-absent path: the slice §12.2 asks for needs a leaderboard *read*,
## which does not exist until GodotSteam links. It says so rather than showing
## three invented names, which is the version that survives into a store build.
func test_the_leaderboard_slice_admits_it_is_waiting_for_steam() -> void:
	await _open()
	var board: Label = _scene.get_node("%BoardLabel") as Label
	assert_string_contains(board.text, "Steam")


func _clear_navigated_scenes() -> void:
	for child: Node in get_tree().root.get_children():
		if child.scene_file_path.begins_with("res://src/scenes/"):
			get_tree().root.remove_child(child)
			child.queue_free()

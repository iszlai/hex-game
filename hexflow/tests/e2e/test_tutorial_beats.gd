## @e2e — Feature: §10's tutorial, on the real level screen.
##
## `test_tutorial.gd` checks the table; this checks that the beats in it actually
## reach a player. Those are different failures: a beat can be perfectly specified
## and still never fire, which looks exactly like no tutorial at all.
##
## §26's exit criterion for M8 is "a first-time player completes chapter 1 with no
## external explanation — verified by an actual naive playtest, not a
## self-assessment". Nothing here is that. What is here is everything that would
## make such a playtest worth running.
extends GutTest

const SCENE := "res://src/scenes/level/level.tscn"

var _scene: Control = null


func before_each() -> void:
	SaveService.data = {"campaign": {}, "in_progress": null, "tutorial_flags": {},
		"endless": {"best_goals": 0}, "daily": {"history": {}, "streak": 0},
		"stats": {"undos": 0}, "achievements_mirror": []}
	Tutorial.clear_cache()
	SettingsService.set_value("reduce_motion", false)


func after_each() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.get_parent().remove_child(_scene)
		_scene.queue_free()
	_scene = null
	GameDirector.state = null
	GameDirector.level = null
	GameDirector.mode = GameDirector.Mode.CAMPAIGN
	GameDirector.screen = GameDirector.Screen.LEVEL
	before_each()


func _open(chapter: int, index: int) -> void:
	GameDirector.start_level(LevelRepository.load_level(chapter, index))
	GameDirector.screen = GameDirector.Screen.LEVEL
	_scene = load(SCENE).instantiate()
	add_child_autofree(_scene)
	await wait_process_frames(2)


func _banner() -> Label:
	return _scene.get_node("%BannerLabel") as Label


func _beat_id() -> String:
	return str((_scene.get("_beat") as Dictionary).get("id", ""))


## The move the gate will actually accept: whatever the board says is legal. Not
## the stored optimum — chapter 1 level 1's optimal line opens with a *discard*,
## and T1 is teaching the player to place.
func _first_move() -> Vector3i:
	return GameDirector.state.legal_targets()[0]


func _press(action: String) -> void:
	for code: int in InputBindings.keys_of(action):
		var ev := InputEventKey.new()
		ev.keycode = code as Key
		ev.pressed = true
		_scene.get_viewport().push_input(ev)
		break
	await wait_process_frames(1)


## T1 is on screen on the first frame, and says the direction the player is
## actually holding rather than a direction the spec assumed.
func test_the_first_beat_greets_a_new_player() -> void:
	await _open(1, 1)
	assert_eq(_beat_id(), "T1")
	assert_true((_scene.get_node("%Banner") as Control).visible)
	# The direction is the level's, not a constant: this said "north-east" because
	# that is what chapter 1 level 1 opened on before C-33 re-authored it, which is
	# precisely the lie the beat's placeholder exists to prevent. Asserting the
	# *shape* of the sentence keeps the test about the beat rather than the board.
	var text: String = _banner().text.to_lower()
	assert_false(text.contains("{"), "the placeholder was filled in")
	assert_true(
		text.contains("north") or text.contains("south")
			or text.contains("east") or text.contains("west"),
		"T1 names a compass direction, not a code: %s" % text)


## §10.1: "Beat 1 gates input to the single correct cell." The gate is the level's
## own stored solution, which is the solver's verified optimum — so the tutorial
## cannot teach a move the game does not think is best.
func test_the_first_beat_gates_input_to_one_cell() -> void:
	await _open(1, 1)
	var router: InputRouter = _scene.get("_router") as InputRouter
	assert_eq(router.candidates().size(), 1, "§10.1 gates T1 to one cell")
	assert_eq(router.candidates()[0], GameDirector.state.legal_targets()[0],
		"§10.2: the one cell is the one legal target")

	# The gate lifts the moment the beat is done, and the board is a board again.
	EventBus.place_requested.emit(_first_move())
	await wait_process_frames(1)
	assert_ne(_beat_id(), "T1", "placing ends it")
	assert_gt(router.candidates().size(), 1, "and the rest of the board comes back")


## §10.1: "Non-blocking after the first beat." T2 follows T1 on the same level and
## does not gate.
func test_the_second_beat_follows_and_does_not_gate() -> void:
	await _open(1, 1)
	EventBus.place_requested.emit(_first_move())
	await wait_process_frames(1)
	assert_eq(_beat_id(), "T2")
	var router: InputRouter = _scene.get("_router") as InputRouter
	assert_gt(router.candidates().size(), 0)
	assert_eq(router.candidates().size(), GameDirector.state.legal_targets().size(),
		"a later beat highlights; it does not restrict")


## §10: a flag per beat, so it never repeats — across a whole reopening of the
## level, which is the case a screen-local variable would get wrong.
func test_a_beat_never_greets_the_same_player_twice() -> void:
	await _open(1, 1)
	assert_eq(_beat_id(), "T1")
	EventBus.place_requested.emit(_first_move())
	await wait_process_frames(1)
	assert_true(Tutorial.seen("T1"), "and it is written down, not just dismissed")

	await _open(1, 1)
	assert_ne(_beat_id(), "T1", "a second visit is not a first one")


## §10.1: "Skippable at any time with a single Back press." Back means pause
## everywhere else on this screen, so the beat gets first claim on it — and only
## while one is actually up.
func test_back_skips_the_whole_tutorial_while_a_beat_is_up() -> void:
	var pauses: Array[int] = []
	var watcher := func() -> void: pauses.append(1)
	EventBus.pause_requested.connect(watcher)

	await _open(1, 1)
	assert_eq(_beat_id(), "T1")
	await _press("board_back")
	assert_eq(_beat_id(), "", "the beat is gone")
	assert_eq(pauses.size(), 0, "and Back did not also open the pause menu")
	assert_true(Tutorial.complete(), "§10.1: skipping sets *all* flags seen")

	# With no beat up, Back is the pause it is everywhere else (§12.5).
	await _press("board_back")
	assert_eq(pauses.size(), 1)
	EventBus.pause_requested.disconnect(watcher)


## §10.2's timed completions. T3 ends after two seconds whether or not the player
## does anything, and a beat waiting on an action still has to let go eventually —
## a player who never presses undo must not read T5 for the rest of the level.
func test_a_timed_beat_lets_go_on_its_own() -> void:
	await _open(1, 2)
	assert_eq(_beat_id(), "T3")
	var seconds: float = float(Tutorial.beat("T3").get("seconds", 0))
	assert_gt(seconds, 0.0)
	await wait_seconds(seconds + 0.4)
	assert_eq(_beat_id(), "", "T3 ends on its own clock")


## §10 weaves the tutorial into the campaign. A player in endless or the daily has
## been through chapter 1 already, and a beat firing there teaches nobody.
func test_no_beat_interrupts_endless_or_the_daily() -> void:
	GameDirector.start_endless(4242)
	GameDirector.screen = GameDirector.Screen.LEVEL
	_scene = load(SCENE).instantiate()
	add_child_autofree(_scene)
	await wait_process_frames(2)
	assert_eq(_beat_id(), "", "endless is not a lesson")
	assert_false(Tutorial.seen("T1"), "and it did not consume the campaign's first beat")


## §10.2's "undo button glows", on the real rail. The row is lit while the beat is
## up and back to itself the moment it is not — a highlight that outlived its beat
## would be the game pointing at something it has stopped talking about.
func test_a_beat_lights_the_rail_row_it_is_about() -> void:
	Tutorial.mark_seen("T1")
	Tutorial.mark_seen("T2")
	await _open(1, 4)
	var undo: Control = _scene.get_node("%UndoButton")
	assert_eq(undo.modulate, Color.WHITE, "nothing is lit before the beat")

	EventBus.place_requested.emit(_first_move())
	await wait_process_frames(2)
	assert_eq(_beat_id(), "T5", "the beat that says undo is free")
	assert_ne(undo.modulate, Color.WHITE, "and the row it is about is lit")

	EventBus.undo_requested.emit()
	await wait_process_frames(1)
	assert_eq(_beat_id(), "", "the beat is done")
	assert_eq(undo.modulate, Color.WHITE, "and the rail is itself again")


## §14.5 stops the loop and leaves the row **held bright**. The emphasis is
## feedback, and reducing motion is not removing what the player is being told —
## the distinction §14.5 draws itself.
func test_reduce_motion_holds_the_glow_rather_than_dropping_it() -> void:
	SettingsService.set_value("reduce_motion", true)
	Tutorial.mark_seen("T1")
	Tutorial.mark_seen("T2")
	await _open(1, 4)
	EventBus.place_requested.emit(_first_move())
	await wait_process_frames(2)
	assert_eq(_beat_id(), "T5")
	assert_ne(_scene.get_node("%UndoButton").modulate, Color.WHITE,
		"§14.5 stops the pulse; it does not stop the pointing")
	SettingsService.set_value("reduce_motion", false)

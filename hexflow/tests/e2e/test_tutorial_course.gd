## @e2e — Feature: §10's tutorial, on the real level screen.
##
## `test_tutorial.gd` checks the table and the five boards; this checks that what
## is in them actually reaches a player. Those are different failures: a lesson
## can be perfectly specified and still never fire, which looks exactly like no
## tutorial at all.
##
## §26's exit criterion for M8 is "a first-time player completes the tutorial and
## chapter 1 with no external explanation — verified by an actual naive playtest,
## not a self-assessment". Nothing here is that. What is here is everything that
## would make such a playtest worth running.
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


func _open_course(index: int = 0) -> void:
	GameDirector.start_tutorial(index)
	GameDirector.screen = GameDirector.Screen.LEVEL
	_scene = load(SCENE).instantiate()
	add_child_autofree(_scene)
	await wait_process_frames(2)


## Tears the screen down *now* rather than on the next idle frame. A test that
## opens one lesson after another has to, or the outgoing screen is still
## connected to `state_reset` when the next board arrives and binds a board view
## that is no longer in the tree.
func _close() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.get_parent().remove_child(_scene)
		_scene.free()
	_scene = null


func _coach() -> Label:
	return _scene.get_node("%CoachLabel") as Label


func _beat_id() -> String:
	return str((_scene.get("_beat") as Dictionary).get("id", ""))


func _router() -> InputRouter:
	return _scene.get("_router") as InputRouter


## The one cell the live beat has left, which is the move the lesson is teaching.
func _gated_cell() -> Vector3i:
	return _router().candidates()[0]


func _press(action: String) -> void:
	for code: int in InputBindings.keys_of(action):
		var ev := InputEventKey.new()
		ev.keycode = code as Key
		ev.pressed = true
		_scene.get_viewport().push_input(ev)
		break
	await wait_process_frames(1)


## Plays a lesson through, one gated move at a time — which is exactly what a
## player following the words does.
func _follow_the_lesson() -> void:
	for _step: int in range(8):
		if GameDirector.state == null \
				or GameDirector.state.status != GameState.Status.PLAYING:
			return
		var cell: Vector3i = _gated_cell()
		if bool(_scene.get("_wild_armed")):
			EventBus.wild_place_requested.emit(cell)
		else:
			EventBus.place_requested.emit(cell)
		await wait_process_frames(2)


# --- getting there ---------------------------------------------------------------

## §10.1, C-37: the very first launch goes to the course rather than to the menu.
## A main menu is five words about things a player who has never seen the game
## does not yet know the meaning of.
func test_a_first_launch_goes_straight_into_the_course() -> void:
	var boot: Node = load("res://src/scenes/boot/boot.tscn").instantiate()
	add_child_autofree(boot)
	await wait_process_frames(2)
	boot._leave()
	await wait_process_frames(1)

	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL)
	assert_eq(GameDirector.mode, GameDirector.Mode.TUTORIAL)
	assert_eq(GameDirector.level.id, Tutorial.level_id(1))
	boot.get_parent().remove_child(boot)
	boot.free()


## And a save that has been through it goes where it always went (§12.1's first
## arrow, Boot → MainMenu). This is the branch that has to die after one use.
func test_a_taught_player_boots_to_the_menu_as_before() -> void:
	Tutorial.finish()
	var boot: Node = load("res://src/scenes/boot/boot.tscn").instantiate()
	add_child_autofree(boot)
	await wait_process_frames(2)
	boot._leave()
	await wait_process_frames(1)

	assert_eq(GameDirector.screen, GameDirector.Screen.MAIN_MENU)
	assert_ne(GameDirector.mode, GameDirector.Mode.TUTORIAL)
	boot.get_parent().remove_child(boot)
	boot.free()


# --- the first board -----------------------------------------------------------

## The course opens on lesson 1, with words on screen that name the tile the
## player is actually holding.
func test_the_course_greets_a_new_player_on_its_first_board() -> void:
	await _open_course()
	assert_eq(GameDirector.mode, GameDirector.Mode.TUTORIAL)
	assert_eq(GameDirector.level.id, Tutorial.level_id(1))
	assert_true((_scene.get_node("%Coach") as Control).visible, "the card is up")
	var text: String = _coach().text.to_lower()
	assert_false(text.contains("{"), "the placeholder was filled in")
	assert_true(
		text.contains("north") or text.contains("south")
			or text.contains("east") or text.contains("west"),
		"the opening beat names a compass direction, not a code: %s" % text)


## §10.1: the beat holds input to the single correct cell, and puts the cursor on
## it so a player on a pad has nothing to hunt for.
func test_a_beat_gates_input_to_one_cell_and_points_at_it() -> void:
	await _open_course()
	assert_eq(_router().candidates().size(), 1, "§10.1 gates to one cell")
	assert_eq(_router().candidates()[0], GameDirector.state.legal_targets()[0],
		"and the one cell is the one legal target")
	assert_true(_router().has_cursor, "the cursor is on it")
	assert_eq(_router().cursor, _router().candidates()[0])


## The gate follows the line rather than staying on its first step (C-37): the
## beat after a placement lights the *next* cell of the stored solution, not the
## one already filled.
func test_the_gate_moves_along_the_line_with_the_player() -> void:
	await _open_course()
	var first: Vector3i = _gated_cell()
	EventBus.place_requested.emit(first)
	await wait_process_frames(2)

	assert_ne(_beat_id(), "", "a second beat followed the placement")
	assert_eq(_router().candidates().size(), 1, "and it gates too")
	assert_ne(_gated_cell(), first, "at the next cell of the line, not the last one")
	assert_true(GameDirector.state.legal_targets().has(_gated_cell()),
		"and at something the tile in hand can actually reach")


# --- through the course ---------------------------------------------------------

## Finishing a lesson brings on the next one with no results card in between — the
## screen stays where it is and the board changes under it.
func test_finishing_a_lesson_brings_on_the_next() -> void:
	await _open_course()
	await _follow_the_lesson()
	assert_eq(GameDirector.state.status, GameState.Status.WON, "lesson 1 is finished")

	# C-35 holds the finished board until the player says go; the player says go.
	EventBus.advance_requested.emit()
	await wait_process_frames(4)
	assert_eq(GameDirector.level.id, Tutorial.level_id(2), "lesson 2 arrived")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL, "without a card in between")
	assert_ne(_beat_id(), "", "and it has something of its own to say")


## Every one of the five boards can be finished by doing exactly what it says.
## This is the claim the whole course rests on: a lesson that cannot be completed
## by following it strands the player it was written for.
func test_every_lesson_can_be_finished_by_following_the_words() -> void:
	for index: int in range(1, Tutorial.COURSE_LENGTH + 1):
		await _open_course(index)
		assert_ne(_beat_id(), "", "lesson %d opens with guidance" % index)
		await _follow_the_lesson()
		assert_eq(GameDirector.state.status, GameState.Status.WON,
			"lesson %d cannot be finished by following it" % index)
		_close()


## §6's charge is spent on purpose, never by accident — except on the one board
## whose subject is the charge, where the beat arms it so the lit cell is a cell
## the player can actually take.
func test_the_wild_board_arms_the_charge_for_the_player() -> void:
	await _open_course(5)
	assert_false(bool(_scene.get("_wild_armed")), "not before the charge is picked up")
	EventBus.place_requested.emit(_gated_cell())
	await wait_process_frames(2)

	assert_eq(GameDirector.state.wild_charges, 1, "the star gave a charge")
	assert_true(bool(_scene.get("_wild_armed")), "and the beat armed it")
	assert_eq(_router().candidates().size(), 1, "one cell, and it is the goal")
	assert_true(GameDirector.level.board.is_goal(_gated_cell()))
	assert_false(GameDirector.state.legal_targets().has(_gated_cell()),
		"a cell no tile in the sequence could reach — which is the lesson")


## The last lesson ends the course and hands the player to the main menu, with the
## whole thing written down so it never interrupts again.
func test_the_last_lesson_ends_the_course_at_the_menu() -> void:
	for index: int in range(1, Tutorial.COURSE_LENGTH):
		Tutorial.mark_level_done(index)
	await _open_course()
	assert_eq(GameDirector.level.id, Tutorial.level_id(Tutorial.COURSE_LENGTH))
	await _follow_the_lesson()
	EventBus.advance_requested.emit()
	await wait_process_frames(4)

	assert_true(Tutorial.done(), "the course is over")
	assert_false(Tutorial.pending(), "and it does not come back")
	assert_eq(GameDirector.screen, GameDirector.Screen.MAIN_MENU)


# --- leaving it ------------------------------------------------------------------

## §10.1: "Skippable at any time with a single Back press." In a course of its own
## that means leaving it — and leaving it for good, because a player who skips has
## said something about the tutorial and not about the board they were on.
func test_back_leaves_the_whole_course() -> void:
	var pauses: Array[int] = []
	var watcher := func() -> void: pauses.append(1)
	EventBus.pause_requested.connect(watcher)

	await _open_course()
	await _press("board_back")
	assert_eq(_beat_id(), "", "the card is gone")
	assert_eq(pauses.size(), 0, "and Back did not also open the pause menu")
	assert_true(Tutorial.done(), "§10.1: skipping ends the whole tutorial")
	assert_eq(GameDirector.screen, GameDirector.Screen.MAIN_MENU)
	EventBus.pause_requested.disconnect(watcher)


## A restart teaches the board again. A player who restarts a lesson is asking to
## be shown it — guidance spent once per visit to the level screen would leave
## them on a board with no words on it and no idea what went wrong.
func test_restarting_a_lesson_teaches_it_again() -> void:
	await _open_course()
	var opening: String = _beat_id()
	EventBus.place_requested.emit(_gated_cell())
	await wait_process_frames(2)
	assert_ne(_beat_id(), opening)

	EventBus.restart_requested.emit()
	await wait_process_frames(2)
	assert_eq(_beat_id(), opening, "the board opens with its first words again")
	assert_eq(_router().candidates().size(), 1, "and gates from the top")


## §10's course is its own five boards, so nothing it says can arrive over a
## campaign level, an endless run or the daily.
func test_no_beat_interrupts_the_rest_of_the_game() -> void:
	GameDirector.start_level(LevelRepository.load_level(1, 1))
	GameDirector.screen = GameDirector.Screen.LEVEL
	_scene = load(SCENE).instantiate()
	add_child_autofree(_scene)
	await wait_process_frames(2)
	assert_eq(_beat_id(), "", "a campaign level is not a lesson")
	assert_false((_scene.get_node("%Coach") as Control).visible)
	assert_true(Tutorial.pending(), "and it did not consume the course")


## §10.2's Interaction column, on the real rail: the row a beat is about is lit
## while it is up and back to itself the moment it is not — a highlight that
## outlived its beat would be the game pointing at something it has stopped
## talking about.
func test_a_beat_lights_the_rail_row_it_is_about() -> void:
	await _open_course(5)
	var wild: Control = _scene.get_node("%WildButton")
	assert_eq(wild.modulate, Color.WHITE, "nothing is lit before the beat")

	EventBus.place_requested.emit(_gated_cell())
	await wait_process_frames(2)
	assert_ne(wild.modulate, Color.WHITE, "the row the beat is about is lit")

	EventBus.wild_place_requested.emit(_gated_cell())
	await wait_process_frames(2)
	assert_eq(wild.modulate, Color.WHITE, "and the rail is itself again")


## §14.5 stops the loop and leaves the row **held bright**. The emphasis is
## feedback, and reducing motion is not removing what the player is being told —
## the distinction §14.5 draws itself.
func test_reduce_motion_holds_the_glow_rather_than_dropping_it() -> void:
	SettingsService.set_value("reduce_motion", true)
	await _open_course(5)
	EventBus.place_requested.emit(_gated_cell())
	await wait_process_frames(2)
	assert_ne(_scene.get_node("%WildButton").modulate, Color.WHITE,
		"§14.5 stops the pulse; it does not stop the pointing")
	assert_true((_scene.get_node("%Coach") as Control).visible,
		"and the words are there without the fade that brings them in")
	SettingsService.set_value("reduce_motion", false)

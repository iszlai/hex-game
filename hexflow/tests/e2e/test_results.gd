## @e2e — Feature: the results card (§12.2, §12.1's `Level → Results : WON`).
##
## Includes the last clause of §24.2's gamepad scenario, which M4 could only
## assert half of: "the results screen offers Next with default focus". There was
## no results screen.
extends GutTest

const SCENE := "res://src/scenes/results/results.tscn"

var _scene: Control = null


func before_each() -> void:
	SaveService.data = {"campaign": {}, "in_progress": null,
		"endless": {"best_goals": 0}, "daily": {"history": {}, "streak": 0},
		"stats": {"undos": 0}, "achievements_mirror": []}
	GameDirector.last_result = {}


func after_each() -> void:
	var pending: Variant = GameDirector.get("_transition")
	if pending is Tween and (pending as Tween).is_running():
		(pending as Tween).kill()
	_close()
	_clear_navigated_scenes()
	GameDirector.state = null
	GameDirector.level = null
	GameDirector.hints_used = 0
	GameDirector.mode = GameDirector.Mode.CAMPAIGN
	GameDirector.screen = GameDirector.Screen.LEVEL
	before_each()


## Plays a campaign level to its stored optimum through the real intent path, so
## `last_result` is filled by [GameDirector] rather than by the test.
func _win(chapter: int, index: int, hints: int = 0) -> void:
	var level: Level = LevelRepository.load_level(chapter, index)
	GameDirector.start_level(level)
	# After the level starts, because that is when a hint happens — `start_level`
	# zeroes the counter, so setting it beforehand sets it for nobody.
	GameDirector.hints_used = hints
	for step: Variant in level.solution_script:
		var s: Array = step
		match int(s[0]):
			Solver.ACTION_PLACE:
				EventBus.place_requested.emit(s[1] as Vector3i)
			Solver.ACTION_WILD:
				EventBus.wild_place_requested.emit(s[1] as Vector3i)
			Solver.ACTION_DISCARD:
				EventBus.discard_requested.emit()
	assert_eq(GameDirector.state.status, GameState.Status.WON,
		"the stored solution has to actually win, or nothing below means anything")


## Opens a fresh card, closing any previous one *first*. A results card left in
## the tree keeps answering `_unhandled_input`: two cards both act on the same
## Space, and whichever runs last decides where the game goes — which is how this
## file first reported Replay opening the level after the one it replayed.
func _open() -> void:
	_close()
	GameDirector.screen = GameDirector.Screen.RESULTS
	_scene = load(SCENE).instantiate()
	add_child_autofree(_scene)
	await wait_process_frames(2)


func _close() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.get_parent().remove_child(_scene)
		_scene.queue_free()
	_scene = null


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


func _complete(chapter: int, index: int) -> void:
	(SaveService.data["campaign"] as Dictionary)[LevelRepository.id_for(chapter, index)] = {
		"completed": true, "best_placements": 9, "stars": 3, "hinted": false,
	}


## §12.1's arrow, with §14.2's t=700 in front of it — the card waits for the goal
## flourish, the burst, the ripple and the flow pulse to finish.
func test_winning_a_level_lands_on_results_but_not_immediately() -> void:
	_win(1, 1)
	assert_ne(GameDirector.screen, GameDirector.Screen.RESULTS,
		"§14.2 puts the card at t=700, not at t=0")
	await wait_seconds(Motion.beat_seconds("results") + 0.2)
	assert_eq(GameDirector.screen, GameDirector.Screen.RESULTS)


## A player who restarts during those 700 ms has left; a card for a run they walked
## away from would arrive out of nowhere.
func test_a_restart_during_the_celebration_cancels_the_card() -> void:
	_win(1, 1)
	EventBus.restart_requested.emit()
	await wait_seconds(Motion.beat_seconds("results") + 0.2)
	assert_ne(GameDirector.screen, GameDirector.Screen.RESULTS)


func test_the_card_reports_the_run_that_was_just_played() -> void:
	_win(1, 1)
	var level: Level = GameDirector.level
	await _open()
	var score: Label = _scene.get_node("%ScoreLabel") as Label
	assert_string_contains(score.text, str(level.par))
	assert_eq(int(GameDirector.last_result["stars"]), Scoring.MAX_STARS,
		"the stored solution is the optimum, so it is worth three (§5.10)")


## §24.2: "the results screen offers Next with default focus".
func test_next_has_the_default_focus() -> void:
	_win(1, 1)
	await _open()
	assert_eq(_menu().focused_id(), "next")


## §7.1 will not let the player into a locked chapter, so Next must not offer it —
## and focus must not sit on a row that cannot be pressed (§12.5).
func test_next_is_refused_and_unfocused_when_there_is_nowhere_to_go() -> void:
	_win(1, LevelRepository.LEVELS_PER_CHAPTER)
	await _open()
	assert_false(_menu().enabled("next"), "chapter 2 is not open on one completion")
	assert_eq(_menu().focused_id(), "replay", "focus falls to something pressable")
	await _press("menu_accept")
	assert_eq(GameDirector.level.id, LevelRepository.id_for(1, 12), "Replay replays")


func test_next_opens_the_level_after_this_one() -> void:
	_win(1, 1)
	await _open()
	await _press("menu_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL)
	assert_eq(GameDirector.level.id, LevelRepository.id_for(1, 2))
	assert_eq(GameDirector.state.placements, 0, "from the top")


func test_replay_reopens_the_same_level_from_the_start() -> void:
	_win(1, 1)
	await _open()
	await _press("menu_down")
	await _press("menu_accept")
	assert_eq(GameDirector.level.id, LevelRepository.id_for(1, 1))
	assert_eq(GameDirector.state.placements, 0)


func test_map_and_back_both_go_up_exactly_one_level() -> void:
	_win(1, 1)
	await _open()
	await _press("menu_back")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL_SELECT, "§12.1: Results → LevelSelect")

	await _open()
	await _press("menu_down")
	await _press("menu_down")
	await _press("menu_accept")
	assert_eq(GameDirector.screen, GameDirector.Screen.LEVEL_SELECT, "and the Map row agrees")


## §12.6 — one hint marks the level's star display with a dot, for good.
func test_a_hinted_run_carries_the_dot() -> void:
	_win(1, 1)
	await _open()
	assert_false((_scene.get_node("%Stars/HintDot") as Label).visible)

	_win(1, 1, 1)
	await _open()
	assert_true((_scene.get_node("%Stars/HintDot") as Label).visible)
	assert_true(Campaign.hinted(1, 1), "and the save remembers it, not just this card")


## §12.1 draws Daily off the main menu, not off the map, so that is where its
## results card goes back to. §7.3's retries are unlimited and on the same board.
func test_a_daily_result_goes_back_to_the_menu_rather_than_the_map() -> void:
	GameDirector.start_daily("2026-07-30")
	assert_not_null(GameDirector.level, "the daily has to generate at all")
	GameDirector.last_result = {
		"mode": GameDirector.Mode.DAILY, "level_id": GameDirector.level.id,
		"chapter": 0, "index": 0, "placements": 9,
		"par": GameDirector.level.par, "stars": 2, "hinted": false,
	}
	await _open()
	assert_false(_menu().enabled("next"), "there is no level after today")
	var title: Label = _scene.get_node("%TitleLabel") as Label
	assert_string_contains(title.text, "Daily")

	await _press("menu_down")
	await _press("menu_accept")
	assert_eq(GameDirector.mode, GameDirector.Mode.DAILY)
	assert_eq(GameDirector.level.id, "daily_2026-07-30", "a retry is on the same board")


## §14.1's transition is a *real* scene change: 160 ms after `go_to`, a tween
## callback swaps the running scene, and in a headless run that scene lands at the
## root and stays there — still answering `_unhandled_input`. Two screens then act
## on the same Space and the one that answers last decides where the game goes,
## which is how this file first reported Replay opening the level *after* the one
## it replayed. Anything the director navigated to is cleared here.
func _clear_navigated_scenes() -> void:
	for child: Node in get_tree().root.get_children():
		if child.scene_file_path.begins_with("res://src/scenes/"):
			get_tree().root.remove_child(child)
			child.queue_free()


## §14.1's last unwitnessed row: three stars at 260 ms, `BACK`/`EASE_OUT`, staggered
## 140 ms apart.
##
## The animation was built and nothing had ever watched it run, which is the state
## the checklist rule exists for — code existing is not the criterion. What is
## asserted is the part a player would notice if it broke: the stars arrive **one
## after another** rather than together, and each lands at full size.
func test_the_stars_arrive_one_at_a_time() -> void:
	SettingsService.set_value("reduce_motion", false)
	_win(1, 1)
	await wait_seconds(Motion.beat_seconds("results") + 0.2)
	await _open()

	var labels: Array = _scene.get("_star_labels")
	var earned: int = int(GameDirector.last_result["stars"])
	assert_eq(earned, Scoring.MAX_STARS, "the solution script plays par")
	assert_eq(labels.size(), Scoring.MAX_STARS, "three slots, always")

	# The stagger itself is **not** raced here. A headless frame is longer than
	# 140 ms, so a mid-flight sample lands wherever the frame boundary falls, and
	# `BACK`/`EASE_OUT` overshoots past 1.0 on the way — two ways to read a settled
	# star as a moving one and vice versa. The table's stagger is asserted in
	# `test_motion.gd`; what this test is for is that the row plays at all and
	# lands where it should.
	await wait_seconds(
		float(Motion.RESULTS_STAR_STAGGER_MS * Scoring.MAX_STARS) / 1000.0
		+ Motion.seconds("results_star") + 0.3)
	for i: int in range(earned):
		assert_almost_eq((labels[i] as Label).scale.x, 1.0, 0.02,
			"star %d settles at full size" % i)


## An unearned star is drawn hollow and at rest. §14.1 animates what was *earned* —
## a star that arrived and then turned out not to be there is a promise the card
## cannot keep.
func test_an_unearned_star_is_shown_but_never_played() -> void:
	SettingsService.set_value("reduce_motion", false)
	GameDirector.last_result = {
		"mode": GameDirector.Mode.CAMPAIGN, "chapter": 1, "index": 1,
		"placements": 99, "par": 4, "stars": 1, "hints": 0, "won": true,
	}
	await _open()

	var labels: Array = _scene.get("_star_labels")
	await wait_seconds(
		float(Motion.RESULTS_STAR_STAGGER_MS * Scoring.MAX_STARS) / 1000.0
		+ Motion.seconds("results_star") + 0.3)
	assert_eq((labels[0] as Label).text, "★", "the one that was earned is filled")
	for i: int in range(1, Scoring.MAX_STARS):
		assert_eq((labels[i] as Label).text, "☆", "star %d is hollow" % i)
		assert_almost_eq((labels[i] as Label).scale.x, 1.0, 0.001,
			"and sits at rest rather than having been played")

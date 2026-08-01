## @core — §10's tutorial: the five teaching boards and the table spoken over them.
##
## The table is the design here, the way Appendix A's directions and §14.1's
## timings are, so it is checked the same way: against the section that specifies
## it rather than against whatever it happens to say. §10.1's twelve-word ceiling
## is the clearest example — it is a hard number in the spec, and it is the first
## thing that goes when someone edits a beat to explain one more thing.
extends GutTest


func before_each() -> void:
	SaveService.data = {"campaign": {}, "in_progress": null, "tutorial_flags": {},
		"stats": {"undos": 0}, "achievements_mirror": []}
	Tutorial.clear_cache()


func after_each() -> void:
	before_each()


# --- the five boards -----------------------------------------------------------

## §10.2's course: flow, wall, portal, gate, wild. Five boards, and every one of
## them ships — a lesson whose file is missing is a course that stops in the
## middle, which is worse than one that was never offered.
func test_all_five_lessons_ship_and_load() -> void:
	assert_eq(Tutorial.COURSE_LENGTH, 5, "§10.2 teaches five ideas")
	for index: int in range(1, Tutorial.COURSE_LENGTH + 1):
		var lesson: Level = Tutorial.level(index)
		assert_not_null(lesson, "tutorial lesson %d does not load" % index)
		if lesson == null:
			continue
		assert_eq(lesson.id, Tutorial.level_id(index))
		assert_eq(Tutorial.index_of(lesson.id), index, "and the id maps back")


## Each board teaches exactly the mechanic it is there for, and the one before it
## has not already used it. A wall on the portal board is a board teaching two
## things, which §10.1's "show, don't explain" cannot survive.
func test_each_lesson_introduces_its_own_mechanic() -> void:
	var portal_board: Board = Tutorial.level(3).board
	var gate_board: Board = Tutorial.level(4).board
	var wild_board: Board = Tutorial.level(5).board

	assert_true(Tutorial.level(1).board.walls().is_empty(),
		"the first lesson is the move and nothing else")
	assert_false(Tutorial.level(2).board.walls().is_empty(), "lesson 2 is the wall")
	assert_false(portal_board.portal_pairs().is_empty(), "lesson 3 is the portal")
	assert_false(gate_board.cells_with_flag(Board.F_GATE).is_empty(), "lesson 4 is the gate")
	assert_false(wild_board.cells_with_flag(Board.F_WILD).is_empty(), "lesson 5 is the wild")

	assert_true(gate_board.portal_pairs().is_empty(), "and the gate board has no portal on it")
	assert_true(wild_board.cells_with_flag(Board.F_GATE).is_empty(),
		"nor the wild board a gate")


## §10.2: "the portal is the only way across". A lesson whose point can be walked
## round is a lesson the player never learns — they will simply take the long way
## and never find out what the twin cells were.
func test_the_portal_lesson_cannot_be_solved_by_going_around() -> void:
	var lesson: Level = Tutorial.level(3)
	var board: Board = lesson.board
	# The flood fill without the portal: every open cell reachable from the start
	# by ordinary steps, which is what a player with perfect draws could ever hope
	# to touch.
	var seen: Dictionary = {board.start: true}
	var frontier: Array[Vector3i] = [board.start]
	while not frontier.is_empty():
		var c: Vector3i = frontier.pop_back()
		for dir: int in Direction.ALL:
			var n: Vector3i = c + Direction.delta(dir)
			if seen.has(n) or not board.is_open(n):
				continue
			seen[n] = true
			frontier.append(n)
	for goal: Vector3i in board.goals:
		assert_false(seen.has(goal),
			"the goal can be walked to; the portal is decoration")


## §6 spends a wild charge on a direction the tile in hand does not offer, and the
## fifth lesson exists to make that the difference between winning and not.
func test_the_wild_lesson_cannot_be_solved_without_the_charge() -> void:
	var lesson: Level = Tutorial.level(5)
	var spends_wild: bool = false
	for step: Variant in lesson.solution_script:
		if int((step as Array)[0]) == Solver.ACTION_WILD:
			spends_wild = true
	assert_true(spends_wild, "the stored line spends the charge")

	# And nothing else reaches the goal: the only open neighbour of the goal is the
	# cell the charge is standing on.
	var board: Board = lesson.board
	var open_neighbours: int = 0
	for dir: int in Direction.ALL:
		if board.is_open(board.goals[0] + Direction.delta(dir)):
			open_neighbours += 1
	assert_eq(open_neighbours, 1, "one door to the goal, and the charge holds it")


# --- where the player is in the course ------------------------------------------

## §10: the course runs once, on a save that has never seen it.
func test_a_fresh_save_is_sent_to_the_first_lesson() -> void:
	assert_true(Tutorial.pending(), "a new player has not been taught")
	assert_eq(Tutorial.next_index(), 1)
	assert_false(Tutorial.done())


## A player who stops after two boards comes back to the third. The course is
## short, but not so short that being sent to the beginning is nothing.
func test_the_course_resumes_where_it_was_left() -> void:
	Tutorial.mark_level_done(1)
	Tutorial.mark_level_done(2)
	assert_eq(Tutorial.next_index(), 3)
	assert_true(Tutorial.pending())


## Finishing the last lesson ends the course, and a finished course never
## interrupts again.
func test_finishing_ends_the_course_for_good() -> void:
	for index: int in range(1, Tutorial.COURSE_LENGTH + 1):
		Tutorial.mark_level_done(index)
	assert_eq(Tutorial.next_index(), 0, "nothing left to teach")
	Tutorial.finish()
	assert_true(Tutorial.done())
	assert_false(Tutorial.pending())


## §10.1: "Skippable at any time with a single Back press." Skipping ends the
## whole tutorial, not the board it happened on — a player who skips has said
## something about the tutorial.
func test_skipping_ends_the_whole_course_not_just_this_board() -> void:
	Tutorial.finish()
	assert_true(Tutorial.done())
	assert_false(Tutorial.pending())
	assert_eq(Tutorial.next_index(), 0)


## §10.1's "Replay tutorial … resets the tutorial flags **only**". The emphasis is
## the spec's, so the test is that everything else survives.
func test_replaying_resets_the_flags_and_nothing_else() -> void:
	SaveService.data["campaign"]["c1_l01"] = {"completed": true, "stars": 3}
	SaveService.data["stats"]["undos"] = 7
	Tutorial.finish()

	Tutorial.reset()
	assert_false(Tutorial.done())
	assert_eq(Tutorial.next_index(), 1, "and it starts from the first lesson")
	assert_true((SaveService.data["campaign"] as Dictionary).has("c1_l01"),
		"a replay is not a new save")
	assert_eq(int(SaveService.data["stats"]["undos"]), 7)


## A save with no `tutorial_flags` at all — an older build's, or one edited by
## hand — is simply a player who has not been taught yet.
func test_a_save_with_no_flags_is_simply_a_new_player() -> void:
	SaveService.data.erase("tutorial_flags")
	assert_true(Tutorial.pending())
	assert_eq(Tutorial.next_index(), 1)
	Tutorial.mark_level_done(1)
	assert_eq(Tutorial.next_index(), 2)


# --- the beat table -------------------------------------------------------------

## Every beat belongs to a board that ships, and every board that ships has
## something to say. A beat pointing at a level id the course does not have is a
## beat that can never run, which looks exactly like no tutorial at all.
func test_every_board_has_beats_and_every_beat_has_a_board() -> void:
	assert_gt(Tutorial.beats().size(), 0, "the table loaded")
	var ids: Dictionary = {}
	for entry: Variant in Tutorial.beats():
		var spec: Dictionary = entry
		var id: String = str(spec.get("id", ""))
		assert_false(ids.has(id), "%s appears twice" % id)
		ids[id] = true
		var index: int = Tutorial.index_of(str(spec.get("level", "")))
		assert_gt(index, 0, "%s names %s, which is not a lesson"
			% [id, spec.get("level", "")])
		assert_not_null(Tutorial.level(index), "%s names a lesson that does not ship" % id)
	for index: int in range(1, Tutorial.COURSE_LENGTH + 1):
		assert_gt(Tutorial.for_level(Tutorial.level_id(index)).size(), 0,
			"lesson %d says nothing" % index)


## §10.1: "Never more than 12 words on screen at once." A hard number, and the
## first thing to go when a beat is edited to explain one more thing.
func test_no_beat_says_more_than_twelve_words() -> void:
	for entry: Variant in Tutorial.beats():
		var spec: Dictionary = entry
		var text: String = Tutorial.text_of(spec, Direction.NE)
		var words: int = text.split(" ", false).size()
		assert_lte(words, Tutorial.MAX_WORDS,
			"%s says %d words: \"%s\"" % [spec.get("id", ""), words, text])
		assert_gt(words, 0, "%s says nothing" % spec.get("id", ""))


## Every beat has to name a trigger and a completion the screen can actually
## produce. A typo here is a beat that never fires, which looks like nothing at
## all and is therefore the failure mode nobody notices.
func test_every_beat_names_a_trigger_and_completion_that_exist() -> void:
	for entry: Variant in Tutorial.beats():
		var spec: Dictionary = entry
		assert_true(Tutorial.TRIGGERS.has(str(spec.get("trigger", ""))),
			"%s waits on a trigger nothing emits: %s" % [spec.get("id", ""), spec.get("trigger", "")])
		assert_true(Tutorial.COMPLETIONS.has(str(spec.get("done", ""))),
			"%s ends on something nothing reports: %s" % [spec.get("id", ""), spec.get("done", "")])
		assert_true(Tutorial.HIGHLIGHTS.has(Tutorial.highlight_of(spec)),
			"%s points at something the rail does not have: %s"
				% [spec.get("id", ""), Tutorial.highlight_of(spec)])
		# A beat whose completion is an action still needs a way out for a player
		# who never performs it, unless the board holds input until they do.
		if str(spec.get("done", "")) == "time":
			assert_gt(int(spec.get("seconds", 0)), 0,
				"%s ends on time but names no time" % spec.get("id", ""))


## Every beat on a teaching board holds input to the cell it is about (C-37).
##
## §10.1 used to allow that for the first beat only, which was right for guidance
## laid over a level somebody was there to *play*. A course is not that: its route
## is the only route, and a player who wanders off it reaches a dead board and a
## lesson nobody finished.
func test_a_beat_that_waits_for_a_placement_gates_the_board() -> void:
	for entry: Variant in Tutorial.beats():
		var spec: Dictionary = entry
		if str(spec.get("done", "")) != "place":
			continue
		assert_true(Tutorial.gates(spec),
			"%s waits for a placement without saying which one" % spec.get("id", ""))


## Only the wild board arms a charge, and only the beat that is about the charge.
## Arming one anywhere else would spend the player's charge on a move they chose
## for themselves (§6).
func test_only_the_wild_beat_arms_the_charge() -> void:
	for entry: Variant in Tutorial.beats():
		var spec: Dictionary = entry
		if not Tutorial.arms_wild(spec):
			continue
		assert_eq(str(spec.get("level", "")), Tutorial.level_id(5),
			"%s arms the wild off the wild board" % spec.get("id", ""))
		assert_eq(Tutorial.highlight_of(spec), "wild",
			"%s arms the charge without pointing at it" % spec.get("id", ""))


## One at a time, in table order: a board with two beats on the same trigger shows
## the earlier one first and the later one when the earlier is done.
func test_beats_arrive_one_at_a_time_in_table_order() -> void:
	var first: Dictionary = Tutorial.next_for(Tutorial.level_id(1), "level_start")
	assert_false(first.is_empty(), "the first board opens with something")
	Tutorial.mark_spoken(str(first.get("id", "")))
	assert_eq(Tutorial.next_for(Tutorial.level_id(1), "level_start"), {},
		"it has been said; it is not said again")

	var second: Dictionary = Tutorial.next_for(Tutorial.level_id(1), "after_place")
	assert_false(second.is_empty(), "and the next one follows the placement")
	assert_ne(str(second.get("id", "")), str(first.get("id", "")))


## What has been said is forgotten when the board starts again. A player who
## restarts a lesson is asking to be taught it — a flag that outlived the run
## would answer a question nobody asked.
func test_restarting_a_lesson_teaches_it_again() -> void:
	var first: Dictionary = Tutorial.next_for(Tutorial.level_id(1), "level_start")
	Tutorial.mark_spoken(str(first.get("id", "")))
	Tutorial.begin_level()
	assert_eq(str(Tutorial.next_for(Tutorial.level_id(1), "level_start").get("id", "")),
		str(first.get("id", "")), "the board says it again")


## A beat only answers its own board and its own trigger.
func test_a_beat_only_answers_its_own_board_and_trigger() -> void:
	var opening: Dictionary = Tutorial.next_for(Tutorial.level_id(1), "level_start")
	assert_ne(str(opening.get("id", "")), "",
		"a beat exists for the first board's opening")
	assert_eq(Tutorial.next_for(Tutorial.level_id(1), "wild_gained"), {},
		"a trigger this board's beats do not wait on")
	assert_eq(Tutorial.next_for("c1_l01", "level_start"), {},
		"and a campaign level is no longer a place a beat can fire")


## §10.2 writes the opening beat as "Your tile points north-east", which is true
## of the board that ships today and would become a lie the first time it was
## re-drawn. It is filled in from the tile the player is actually holding.
func test_the_first_beat_names_the_direction_the_player_actually_has() -> void:
	var spec: Dictionary = Tutorial.next_for(Tutorial.level_id(1), "level_start")
	assert_string_contains(Tutorial.text_of(spec, Direction.NE), "north-east")
	assert_string_contains(Tutorial.text_of(spec, Direction.SW), "south-west")

	var lesson: Level = Tutorial.level(1)
	var opening: String = Tutorial.text_of(spec, lesson.tiles[0])
	assert_false(opening.contains("{"), "the lesson's own tile filled the placeholder")
	assert_true(
		opening.contains("north") or opening.contains("south")
			or opening.contains("east") or opening.contains("west"),
		"the beat names the tile the player is holding, not a code")

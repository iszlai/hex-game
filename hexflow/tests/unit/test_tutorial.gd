## @core — §10's tutorial data and the rules over it.
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


func test_all_twelve_beats_of_the_spec_are_present_and_unique() -> void:
	var ids: Array[String] = []
	for entry: Variant in Tutorial.beats():
		ids.append(str((entry as Dictionary).get("id", "")))
	assert_eq(ids.size(), 12, "§10.2 tabulates T1 through T12")
	for n: int in range(1, 13):
		assert_true(ids.has("T%d" % n), "§10.2's T%d is missing" % n)


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
## produce. A typo here is a beat that never fires, which looks like nothing at all
## and is therefore the failure mode nobody notices.
func test_every_beat_names_a_trigger_and_completion_that_exist() -> void:
	for entry: Variant in Tutorial.beats():
		var spec: Dictionary = entry
		assert_true(Tutorial.TRIGGERS.has(str(spec.get("trigger", ""))),
			"%s waits on a trigger nothing emits: %s" % [spec.get("id", ""), spec.get("trigger", "")])
		assert_true(Tutorial.COMPLETIONS.has(str(spec.get("done", ""))),
			"%s ends on something nothing reports: %s" % [spec.get("id", ""), spec.get("done", "")])
		# A beat whose completion is an action still needs a way out for a player who
		# never performs it, or the twelve words stay up for the rest of the level.
		if str(spec.get("done", "")) == "time":
			assert_gt(int(spec.get("seconds", 0)), 0,
				"%s ends on time but names no time" % spec.get("id", ""))


## Every beat is pinned to a level that exists. §10.2 spreads them over five
## chapters, and a beat pointing at a level id the campaign does not have is a beat
## that can never run.
func test_every_beat_belongs_to_a_real_campaign_level() -> void:
	for entry: Variant in Tutorial.beats():
		var spec: Dictionary = entry
		var at: Vector2i = LevelRepository.locate(str(spec.get("level", "")))
		assert_gt(at.x, 0, "%s names %s, which is not a level id"
			% [spec.get("id", ""), spec.get("level", "")])
		assert_not_null(LevelRepository.load_level(at.x, at.y),
			"%s names %s, which does not ship" % [spec.get("id", ""), spec.get("level", "")])


## §10.1: "Beat 1 gates input to the single correct cell; every later beat merely
## highlights and lets the player ignore it."
func test_only_the_first_beat_gates_input() -> void:
	for entry: Variant in Tutorial.beats():
		var spec: Dictionary = entry
		var expected: bool = str(spec.get("id", "")) == "T1"
		assert_eq(Tutorial.gates(spec), expected,
			"%s gates input; §10.1 allows only T1 to" % spec.get("id", ""))


## §10: a flag per beat, so nothing repeats.
func test_a_seen_beat_never_comes_back() -> void:
	var first: Dictionary = Tutorial.next_for("c1_l01", "level_start")
	assert_eq(str(first.get("id", "")), "T1")
	Tutorial.mark_seen("T1")
	assert_true(Tutorial.seen("T1"))
	assert_eq(Tutorial.next_for("c1_l01", "level_start"), {},
		"T1 has been shown; it does not show again")


func test_a_beat_only_answers_its_own_level_and_trigger() -> void:
	assert_eq(Tutorial.next_for("c1_l02", "level_start").get("id", ""), "T3")
	assert_eq(Tutorial.next_for("c1_l01", "after_place").get("id", ""), "T2")
	assert_eq(Tutorial.next_for("c1_l01", "wild_gained"), {},
		"a trigger this level's beats do not wait on")
	assert_eq(Tutorial.next_for("c5_l12", "level_start"), {},
		"a level with no beats of its own")


## §10.1: "Skippable at any time with a single Back press; skipping sets all flags
## seen" — all of them, not the rest of this level's. A player who skips has said
## something about the whole tutorial.
func test_skipping_ends_the_whole_tutorial_not_just_this_level() -> void:
	Tutorial.skip_all()
	assert_true(Tutorial.complete())
	for level: String in ["c1_l01", "c2_l02", "c5_l01"]:
		assert_eq(Tutorial.next_for(level, "level_start"), {})


## §10.1: "Replay tutorial … resets the tutorial flags **only**". The emphasis is
## the spec's, so the test is that everything else survives.
func test_replaying_resets_the_flags_and_nothing_else() -> void:
	SaveService.data["campaign"]["c1_l01"] = {"completed": true, "stars": 3}
	SaveService.data["stats"]["undos"] = 7
	Tutorial.skip_all()

	Tutorial.reset()
	assert_false(Tutorial.seen("T1"))
	assert_false(Tutorial.complete())
	assert_true((SaveService.data["campaign"] as Dictionary).has("c1_l01"),
		"a replay is not a new save")
	assert_eq(int(SaveService.data["stats"]["undos"]), 7)


## §10.2 writes T1's words as "Your tile points north-east", which is true of the
## level that ships today and would become a lie the first time `make levels`
## reseeded chapter 1. It is filled in from the tile the player is holding.
func test_the_first_beat_names_the_direction_the_player_actually_has() -> void:
	var spec: Dictionary = Tutorial.beat("T1")
	assert_string_contains(Tutorial.text_of(spec, Direction.NE), "north-east")
	assert_string_contains(Tutorial.text_of(spec, Direction.SW), "south-west")
	assert_false(Tutorial.text_of(spec, Direction.W).contains("{"),
		"no placeholder survives into what the player reads")

	# And it agrees with the level that ships, which is what §10.2 asserted directly.
	var level: Level = LevelRepository.load_level(1, 1)
	assert_string_contains(Tutorial.text_of(spec, level.tiles[0]), "north-east",
		"chapter 1 level 1 still opens on NE, as §10.2 assumes")


## A save with no `tutorial_flags` at all — an older build's, or one edited by
## hand — behaves as a fresh one rather than failing.
func test_a_save_with_no_flags_is_simply_a_new_player() -> void:
	SaveService.data.erase("tutorial_flags")
	assert_false(Tutorial.seen("T1"))
	assert_eq(str(Tutorial.next_for("c1_l01", "level_start").get("id", "")), "T1")
	Tutorial.mark_seen("T1")
	assert_true(Tutorial.seen("T1"))


## §10.2's Interaction column, for the four beats whose emphasis lands in the rail.
## A beat that says "undo is free" while nothing on screen indicates which thing
## undo *is* has stated a fact rather than taught anything.
func test_the_beats_that_point_at_the_rail_name_a_real_element() -> void:
	for entry: Variant in Tutorial.beats():
		var spec: Dictionary = entry
		assert_true(Tutorial.HIGHLIGHTS.has(Tutorial.highlight_of(spec)),
			"%s points at something the rail does not have: %s"
				% [spec.get("id", ""), Tutorial.highlight_of(spec)])


## And the four §10.2 names are the four that point. This is the column read back:
## T3 "shown here", T5 "undo button glows", T8 "discard button glows", T12 "HUD
## charge slot fills".
func test_the_pointing_beats_are_the_ones_the_spec_says_point() -> void:
	var pointing: Dictionary = {}
	for entry: Variant in Tutorial.beats():
		var spec: Dictionary = entry
		if Tutorial.highlight_of(spec) != "":
			pointing[str(spec.get("id", ""))] = Tutorial.highlight_of(spec)
	assert_eq(pointing, {"T3": "next", "T5": "undo", "T8": "discard", "T12": "wild"})

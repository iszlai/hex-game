## @core — §23.1's twenty achievements and the conditions that earn them.
##
## Nineteen of the twenty had no detection anywhere: §23.1 listed them, the mirror
## and the local queue worked, and the only `unlock_achievement` call in the build
## was `first_flow`. Nothing failed, because an achievement nobody can earn looks
## exactly like an achievement nobody has earned yet.
##
## So the api names are asserted against §23.1's table the way Appendix A's
## directions are: a name that drifts from what is registered on the partner site
## is an achievement that silently never fires, and no playthrough would show it.
extends GutTest

const PERFECT := Scoring.MAX_STARS


func before_each() -> void:
	SaveService.data = {"campaign": {}, "in_progress": null, "daily": {"history": {}},
		"endless": {}, "stats": {"undos": 0, "undo_free_streak": 0},
		"achievements_mirror": []}


## Marks [param count] levels of [param chapter] complete, with [param stars] each.
## Keyed on the level's uid (C-34), like the game does — a fixture written under
## the slot id would be invisible to [Campaign] and every assertion below would
## pass for the wrong reason.
func _complete(chapter: int, count: int, stars: int = PERFECT, hinted: bool = false) -> void:
	for index: int in range(1, count + 1):
		var level: Level = LevelRepository.load_level(chapter, index)
		if level == null:
			continue
		SaveService.data["campaign"][level.uid] = {
			"completed": true, "best_placements": 1, "stars": stars, "hinted": hinted,
		}


func _uid(chapter: int, index: int) -> String:
	return LevelRepository.load_level(chapter, index).uid


func _earned(chapter: int, placements: int = 1, par: int = 1,
		discards: int = 1, undo: bool = true) -> Array[String]:
	return Achievements.for_campaign_completion(chapter, placements, par, discards, undo)


## §23.1's table has twenty rows and the names are the contract with Steamworks.
func test_the_table_is_the_twenty_the_spec_lists() -> void:
	assert_eq(Achievements.ALL.size(), 20, "§23.1 lists twenty")
	for ch: int in range(1, Campaign.CHAPTERS + 1):
		assert_true(Achievements.ALL.has("chapter_%d_clear" % ch))
		assert_true(Achievements.ALL.has("chapter_%d_perfect" % ch))
	for name: String in ["first_flow", "all_stars", "no_discard", "no_hints_chapter",
			"undo_free", "endless_10", "endless_25", "endless_50", "daily_7",
			"the_long_way"]:
		assert_true(Achievements.ALL.has(name), "§23.1 lists %s" % name)
	var unique: Dictionary = {}
	for name: String in Achievements.ALL:
		unique[name] = true
	assert_eq(unique.size(), 20, "and no name appears twice")


func test_any_completion_earns_the_first_one() -> void:
	assert_true(_earned(1).has("first_flow"))


## "Complete all 12 levels of chapter N" — eleven is not twelve, and the twelfth
## does not have to be the one just played.
func test_a_chapter_clears_at_twelve_and_not_at_eleven() -> void:
	_complete(2, 11)
	assert_false(_earned(2).has("chapter_2_clear"), "eleven of twelve")
	_complete(2, 12)
	assert_true(_earned(2).has("chapter_2_clear"))
	assert_false(_earned(2).has("chapter_3_clear"), "and only the chapter that is done")


## "3 stars on all 12" — a chapter finished with a two-star level in it is cleared
## but not perfect.
func test_a_chapter_is_perfect_only_at_three_stars_throughout() -> void:
	_complete(3, 12, PERFECT)
	SaveService.data["campaign"][_uid(3, 7)]["stars"] = 2
	assert_true(_earned(3).has("chapter_3_clear"))
	assert_false(_earned(3).has("chapter_3_perfect"), "one two-star level is enough")

	SaveService.data["campaign"][_uid(3, 7)]["stars"] = PERFECT
	assert_true(_earned(3).has("chapter_3_perfect"))


func test_all_stars_needs_the_whole_campaign() -> void:
	for ch: int in range(1, Campaign.CHAPTERS + 1):
		_complete(ch, Campaign.LEVELS_PER_CHAPTER, PERFECT)
	assert_eq(Campaign.total_stars(), Achievements.ALL_STARS, "§23.1's 180")
	assert_true(_earned(5).has("all_stars"))

	SaveService.data["campaign"][_uid(1, 1)]["stars"] = 2
	assert_false(_earned(5).has("all_stars"), "179 is not 180")


## §23.1 scopes this to chapter 5, which is where §8.4 hands out 0–2 discards.
func test_no_discard_is_a_chapter_five_condition() -> void:
	assert_true(_earned(5, 1, 1, 0).has("no_discard"))
	assert_false(_earned(5, 1, 1, 1).has("no_discard"), "one spent charge is enough")
	assert_false(_earned(1, 1, 1, 0).has("no_discard"), "and only in chapter 5")


## `hinted` marks the level and is ORed across attempts, so this is a claim about
## the chapter rather than about the last run at it.
func test_a_hinted_level_costs_the_chapter_its_hint_free_award() -> void:
	_complete(4, 12, PERFECT, false)
	assert_true(_earned(4).has("no_hints_chapter"))
	SaveService.data["campaign"][_uid(4, 5)]["hinted"] = true
	assert_false(_earned(4).has("no_hints_chapter"))


## "12 consecutive levels without undo". The streak is a counter because nothing
## in the save recorded whether a level was finished with an undo — `stats.undos`
## is a lifetime total and cannot answer a question about consecutive levels.
func test_the_undo_free_run_counts_consecutively_and_breaks_on_an_undo() -> void:
	for _i: int in range(Achievements.UNDO_FREE_RUN - 1):
		Achievements.record_undo_use(false)
	assert_false(_earned(1, 1, 1, 1, false).has("undo_free"), "eleven clean levels")

	Achievements.record_undo_use(false)
	assert_true(_earned(1, 1, 1, 1, false).has("undo_free"), "and the twelfth earns it")

	# One undo resets it, which is what "consecutive" means.
	Achievements.record_undo_use(true)
	assert_eq(Achievements.undo_free_streak(), 0)
	assert_false(_earned(1, 1, 1, 1, false).has("undo_free"))


## The hidden, affectionate one: par + 15 placements or worse.
func test_the_long_way_needs_fifteen_over_par() -> void:
	assert_false(_earned(1, 20, 6).has("the_long_way"), "14 over is not 15")
	assert_true(_earned(1, 21, 6).has("the_long_way"))


## §7.2's thresholds are cumulative — a 25-goal run also passed 10.
func test_an_endless_run_earns_every_threshold_it_passed() -> void:
	assert_eq(Achievements.for_endless_run(9), [] as Array[String])
	assert_eq(Achievements.for_endless_run(10), ["endless_10"] as Array[String])
	assert_eq(Achievements.for_endless_run(30),
		["endless_10", "endless_25"] as Array[String])
	assert_eq(Achievements.for_endless_run(50),
		["endless_10", "endless_25", "endless_50"] as Array[String])


## "Complete 7 dailies (not necessarily consecutive)". Counted off the stored
## history rather than a counter, so §7.3's unlimited retries cannot inflate it.
func test_seven_dailies_are_seven_days_and_not_seven_attempts() -> void:
	var history: Dictionary = SaveService.data["daily"]["history"]
	for day: int in range(1, 7):
		history["2026-07-%02d" % day] = {"placements": 9}
	assert_eq(Achievements.for_daily(), [] as Array[String], "six days")

	history["2026-07-06"] = {"placements": 4}  # a retry of a day already counted
	assert_eq(Achievements.for_daily(), [] as Array[String], "a retry is not a day")

	history["2026-07-07"] = {"placements": 9}
	assert_true(Achievements.for_daily().has("daily_7"))

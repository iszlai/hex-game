## @core — §7.1's progression rules.
##
## The interesting cases are all at the boundaries, and all of them are ways a
## player gets *stuck*: a chapter that will not open at 7 of 12, a Next button
## that points into a locked chapter, a map that puts its cursor on a level the
## player may not enter. §7.1's whole reason for the 8-of-12 rule is that "a stuck
## player is never fully blocked", so each of those is a test rather than a
## reading of the code.
extends GutTest


func before_each() -> void:
	SaveService.data = {"campaign": {}, "in_progress": null,
		"stats": {"undos": 0}, "achievements_mirror": []}


func after_each() -> void:
	SaveService.data = {"campaign": {}, "in_progress": null,
		"stats": {"undos": 0}, "achievements_mirror": []}


## Marks a level complete without touching the disk, which `record_completion`
## would do on every call.
## Progress is keyed on the level's own uid (C-34), not on its slot. Writing the
## slot id here would build a fixture the game cannot read — which is exactly the
## mismatch uids were introduced to remove, so the fixture has to move with it.
func _complete(chapter: int, index: int, stars: int = 3, hinted: bool = false) -> void:
	var level: Level = LevelRepository.load_level(chapter, index)
	if level == null:
		return
	var campaign: Dictionary = SaveService.data["campaign"]
	campaign[level.uid] = {
		"completed": true, "best_placements": 10, "stars": stars, "hinted": hinted,
	}


func _complete_chapter(chapter: int, count: int) -> void:
	for index: int in range(1, count + 1):
		_complete(chapter, index)


func test_a_fresh_save_opens_exactly_one_level() -> void:
	assert_true(Campaign.chapter_unlocked(1), "chapter 1 is always open")
	assert_true(Campaign.level_unlocked(1, 1))
	assert_false(Campaign.level_unlocked(1, 2), "levels unlock linearly (§7.1)")
	assert_false(Campaign.chapter_unlocked(2))
	assert_eq(Campaign.next_unplayed(), Vector2i(1, 1))
	assert_eq(Campaign.completion_percent(), 0)


func test_a_level_unlocks_the_one_after_it() -> void:
	_complete(1, 1)
	assert_true(Campaign.level_unlocked(1, 2))
	assert_false(Campaign.level_unlocked(1, 3))
	assert_eq(Campaign.next_unplayed(), Vector2i(1, 2))


## §7.1's threshold is 8 of 12 and not 12 of 12 on purpose — a player stuck on one
## level must not be blocked out of the rest of the game.
func test_a_chapter_opens_at_eight_of_twelve_not_twelve() -> void:
	_complete_chapter(1, 7)
	assert_false(Campaign.chapter_unlocked(2), "7 of 12 is not enough")
	_complete(1, 8)
	assert_true(Campaign.chapter_unlocked(2), "8 of 12 opens the next chapter")
	assert_true(Campaign.level_unlocked(2, 1))
	assert_false(Campaign.level_unlocked(2, 2), "linear inside the new chapter too")


func test_the_eight_do_not_have_to_be_the_first_eight() -> void:
	# Levels unlock linearly, so in practice they will be — but the rule is stated
	# as a count, and a future skip or a hand-edited save must not confuse it.
	for index: int in [2, 3, 4, 5, 6, 7, 11, 12]:
		_complete(1, index)
	assert_eq(Campaign.completed_in_chapter(1), 8)
	assert_true(Campaign.chapter_unlocked(2))


func test_a_locked_chapter_never_reports_a_level_as_unlocked() -> void:
	assert_false(Campaign.level_unlocked(3, 1))
	assert_false(Campaign.level_unlocked(5, 12))
	# Out of range in both directions, so a stale save cannot index past the data.
	assert_false(Campaign.level_unlocked(1, 0))
	assert_false(Campaign.level_unlocked(1, LevelRepository.LEVELS_PER_CHAPTER + 1))
	assert_false(Campaign.chapter_unlocked(LevelRepository.CHAPTERS + 1))


func test_next_walks_the_chapter_then_crosses_only_if_the_next_is_open() -> void:
	assert_eq(Campaign.after(1, 1), Vector2i(1, 2))
	# Chapter 1 finished except for the last level: 11 of 12 is over the threshold,
	# so completing 12 leads into chapter 2.
	_complete_chapter(1, 11)
	assert_eq(Campaign.after(1, 12), Vector2i(2, 1))


## The case §7.1 leaves implicit: the last level of a chapter, finished by a player
## who has not met the threshold. Next has nowhere honest to point.
func test_next_is_empty_when_the_following_chapter_is_still_locked() -> void:
	_complete(1, 12)
	assert_eq(Campaign.completed_in_chapter(1), 1)
	assert_eq(Campaign.after(1, 12), Vector2i.ZERO, "must not offer a locked level")
	# And at the very end of the campaign there is nothing after by construction.
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		_complete_chapter(chapter, LevelRepository.LEVELS_PER_CHAPTER)
	assert_eq(Campaign.after(LevelRepository.CHAPTERS, LevelRepository.LEVELS_PER_CHAPTER),
		Vector2i.ZERO)


func test_percent_and_stars_count_the_whole_campaign() -> void:
	_complete_chapter(1, 12)
	_complete_chapter(2, 12)
	assert_eq(Campaign.completed_levels(), 24)
	assert_eq(Campaign.completion_percent(), 40, "24 of 60")
	assert_eq(Campaign.total_stars(), 24 * Scoring.MAX_STARS)
	assert_eq(Campaign.stars_in_chapter(1), 12 * Scoring.MAX_STARS)


## Rounding rather than truncation, so the last level is what takes the number to
## 100 and the one before it does not already read 100.
func test_only_the_last_level_reads_a_hundred_percent() -> void:
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		_complete_chapter(chapter, LevelRepository.LEVELS_PER_CHAPTER)
	assert_eq(Campaign.completion_percent(), 100)
	SaveService.data["campaign"].erase(LevelRepository.load_level(5, 12).uid)
	assert_lt(Campaign.completion_percent(), 100, "59 of 60 is not finished")


func test_the_hint_dot_survives_a_later_clean_completion() -> void:
	_complete(1, 1, 3, true)
	assert_true(Campaign.hinted(1, 1), "§12.6 marks the level, not the attempt")
	assert_eq(Campaign.stars(1, 1), 3)


func test_the_map_opens_on_the_run_that_was_interrupted() -> void:
	_complete_chapter(1, 4)
	assert_eq(Campaign.last_played(), Vector2i(1, 5), "without a run, the next unplayed")
	SaveService.data["in_progress"] = {"mode": "campaign", "level_id": LevelRepository.id_for(1, 2)}
	assert_eq(Campaign.last_played(), Vector2i(1, 2), "a live run is the last played level")


func test_a_nonsense_in_progress_id_does_not_move_the_cursor() -> void:
	SaveService.data["in_progress"] = {"mode": "campaign", "level_id": "not-a-level"}
	assert_eq(Campaign.last_played(), Vector2i(1, 1))
	# A well-formed id for a level the player may not enter is equally not theirs.
	SaveService.data["in_progress"] = {"mode": "campaign", "level_id": LevelRepository.id_for(4, 9)}
	assert_eq(Campaign.last_played(), Vector2i(1, 1))


func test_a_finished_campaign_still_has_somewhere_to_point() -> void:
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		_complete_chapter(chapter, LevelRepository.LEVELS_PER_CHAPTER)
	assert_eq(Campaign.next_unplayed(), Vector2i.ZERO, "nothing is unplayed")
	assert_eq(Campaign.last_played(), Vector2i(1, 1), "but the map still opens somewhere")

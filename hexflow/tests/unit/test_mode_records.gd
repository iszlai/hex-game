## @core — what §7.2 and §7.3 write down.
##
## Both modes had rules and no memory: `endless.best_goals` and `daily.streak`
## were in the save schema from M0 and nothing ever set them, so the main menu's
## "best" and "streak" were structurally zero. The streak is the interesting half,
## because it is a statement about *dates* and the ways it goes wrong are all
## calendar edges.
extends GutTest


func before_each() -> void:
	SaveService.data = {
		"campaign": {}, "in_progress": null,
		"endless": {"best_goals": 0, "best_placements_at_best": 0, "runs": 0},
		"daily": {"history": {}, "streak": 0},
		"stats": {"undos": 0}, "achievements_mirror": [],
	}


func after_each() -> void:
	before_each()


func _endless() -> Dictionary:
	return SaveService.data["endless"]


func _daily() -> Dictionary:
	return SaveService.data["daily"]


func test_the_first_endless_run_is_always_a_best() -> void:
	assert_true(SaveService.record_endless_run(4, 30))
	assert_eq(int(_endless()["best_goals"]), 4)
	assert_eq(int(_endless()["runs"]), 1)


## §5.10: endless ranks on goals, ties broken by fewer placements.
func test_a_run_is_better_only_on_more_goals_or_fewer_placements() -> void:
	SaveService.record_endless_run(4, 30)
	assert_false(SaveService.record_endless_run(3, 10), "fewer goals is not better")
	assert_eq(int(_endless()["best_goals"]), 4)

	assert_false(SaveService.record_endless_run(4, 31), "same goals, more placements")
	assert_true(SaveService.record_endless_run(4, 22), "same goals, fewer placements")
	assert_eq(int(_endless()["best_placements_at_best"]), 22)

	assert_true(SaveService.record_endless_run(9, 200), "more goals wins outright")
	assert_eq(int(_endless()["best_goals"]), 9)
	assert_eq(int(_endless()["runs"]), 5, "every run counts, best or not")


func test_a_daily_played_two_days_running_is_a_streak_of_two() -> void:
	SaveService.record_daily("2026-07-29", 12, 2)
	assert_eq(int(_daily()["streak"]), 1)
	SaveService.record_daily("2026-07-30", 10, 3)
	assert_eq(int(_daily()["streak"]), 2)


## §7.3 allows unlimited retries. A streak you can grind in an afternoon measures
## nothing, so a second attempt on the same date does not extend it.
func test_retrying_the_same_day_does_not_extend_the_streak() -> void:
	SaveService.record_daily("2026-07-30", 12, 2)
	SaveService.record_daily("2026-07-30", 9, 3)
	assert_eq(int(_daily()["streak"]), 1)
	# But the better attempt is the one kept.
	var today: Dictionary = (_daily()["history"] as Dictionary)["2026-07-30"]
	assert_eq(int(today["placements"]), 9, "fewer placements is better (§5.10)")
	assert_eq(int(today["stars"]), 3)


func test_a_missed_day_resets_the_streak_to_one() -> void:
	SaveService.record_daily("2026-07-27", 12, 2)
	SaveService.record_daily("2026-07-28", 12, 2)
	assert_eq(int(_daily()["streak"]), 2)
	SaveService.record_daily("2026-07-30", 12, 2)
	assert_eq(int(_daily()["streak"]), 1, "the 29th was missed")


## The calendar edges, which is the whole reason the previous day is computed
## through the epoch rather than by subtracting one from the day number.
func test_the_day_before_is_right_across_months_and_leap_years() -> void:
	assert_eq(SaveService.previous_date("2026-08-01"), "2026-07-31")
	assert_eq(SaveService.previous_date("2026-01-01"), "2025-12-31")
	assert_eq(SaveService.previous_date("2026-03-01"), "2026-02-28")
	assert_eq(SaveService.previous_date("2024-03-01"), "2024-02-29", "2024 is a leap year")


func test_a_streak_survives_a_month_boundary() -> void:
	SaveService.record_daily("2026-07-31", 12, 2)
	SaveService.record_daily("2026-08-01", 12, 2)
	assert_eq(int(_daily()["streak"]), 2)


## §7.3's seven-day indicator, as data: seven days ending today, oldest first.
func test_the_seven_day_window_ends_today_and_marks_what_was_played() -> void:
	SaveService.record_daily("2026-07-30", 12, 2)
	SaveService.record_daily("2026-07-28", 12, 2)
	var days: Array[bool] = SaveService.daily_streak_days("2026-07-30")
	assert_eq(days.size(), 7)
	assert_true(days[6], "today is the last mark")
	assert_true(days[4], "two days ago")
	assert_false(days[5], "yesterday was missed")
	assert_false(days[0], "and a week ago was not played at all")

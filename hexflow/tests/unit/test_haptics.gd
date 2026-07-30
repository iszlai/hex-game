## @core — the §11.5 haptics table and its slider.
##
## No controller is present in CI, so what is asserted is the table and the
## scaling, not the rumble. That is the part a player can tell is wrong: a pattern
## with the wrong pulse count feels like a different event.
extends GutTest

var _haptics: Haptics = null
var _saved_strength: int = 70


func before_each() -> void:
	_saved_strength = int(SettingsService.get_value("haptics"))
	_haptics = Haptics.new()
	add_child_autofree(_haptics)


func after_each() -> void:
	SettingsService.set_value("haptics", _saved_strength)


## §11.5, row by row: the pulse counts and durations are the feel.
func test_the_patterns_match_the_table() -> void:
	assert_eq(Haptics.PATTERNS["cursor_move"], [[8, Haptics.WEAK, 0.0]],
		"cursor move: 8 ms, weak")
	assert_eq((Haptics.PATTERNS["cursor_reject"] as Array).size(), 3,
		"rejection: two pulses with a gap between them")
	assert_eq((Haptics.PATTERNS["cursor_reject"] as Array)[1], [40, 0.0, 0.0],
		"the pulses are 40 ms apart")
	assert_eq((Haptics.PATTERNS["commit"] as Array).size(), 2,
		"commit: 18 ms medium plus a 60 ms weak tail")
	assert_eq((Haptics.PATTERNS["commit"] as Array)[1], [60, Haptics.WEAK, 0.0])
	assert_eq(Haptics.PATTERNS["auto_discard"], [[12, Haptics.WEAK, 0.0]])
	assert_eq(_total_ms("goal"), 160, "goal: 40 ms then a 120 ms ramp-down")
	assert_eq(_pulses("dead"), 3, "dead state: three pulses")
	assert_eq(_total_ms("dead"), 140)


func test_a_pattern_is_recorded_and_queued_when_played() -> void:
	SettingsService.set_value("haptics", 70)
	_haptics.play("commit")
	assert_eq(_haptics.history, ["commit"] as Array[String])
	assert_eq(_haptics.pending_steps(), 1, "one step consumed, one still queued")


## §11.5: "disabled at 0".
func test_zero_strength_plays_nothing_at_all() -> void:
	SettingsService.set_value("haptics", 0)
	_haptics.play("commit")
	_haptics.play("goal")
	assert_eq(_haptics.history, [] as Array[String])
	assert_eq(_haptics.pending_steps(), 0)


func test_strength_follows_the_slider() -> void:
	SettingsService.set_value("haptics", 100)
	assert_almost_eq(_haptics.strength(), 1.0, 0.001)
	SettingsService.set_value("haptics", 70)
	assert_almost_eq(_haptics.strength(), 0.7, 0.001)
	SettingsService.set_value("haptics", 0)
	assert_almost_eq(_haptics.strength(), 0.0, 0.001)


func test_the_default_slider_position_is_seventy_percent() -> void:
	assert_eq(int(SettingsService.DEFAULTS["haptics"]), 70)


func test_an_unknown_pattern_warns_instead_of_crashing() -> void:
	SettingsService.set_value("haptics", 70)
	_haptics.play("nonexistent")
	assert_eq(_haptics.history, [] as Array[String])


## An idle board must cost nothing per frame (C4).
func test_processing_is_off_while_idle() -> void:
	assert_false(_haptics.is_processing(), "nothing queued, nothing ticking")
	SettingsService.set_value("haptics", 70)
	_haptics.play("dead")
	assert_true(_haptics.is_processing())


func _pulses(id: String) -> int:
	var count := 0
	for entry: Variant in (Haptics.PATTERNS[id] as Array):
		var step: Array = entry
		if float(step[1]) > 0.0 or float(step[2]) > 0.0:
			count += 1
	return count


func _total_ms(id: String) -> int:
	var total := 0
	for entry: Variant in (Haptics.PATTERNS[id] as Array):
		total += int((entry as Array)[0])
	return total

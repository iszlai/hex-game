## @core — §14.1's timing table, and §14.5 applied to it.
##
## §14 opens with "every timing below is a requirement, not a suggestion", so this
## reads like the direction table's test: the numbers are asserted row by row
## against the spec rather than against whatever the code currently says. If a
## timing here is wrong, the retune was a spec change and §14.1 needs editing too.
##
## The §14.5 half is the one with a trap in it. "All durations × 0.4" is not the
## whole rule — the same section names 120 ms for screen transitions outright, and
## says the loops stop rather than shorten. A blanket multiplier passes a careless
## test and gets both of those wrong.
extends GutTest


func after_each() -> void:
	SettingsService.set_value("reduce_motion", false)


func _reduced() -> void:
	SettingsService.set_value("reduce_motion", true)


## §14.1, row for row.
func test_every_timing_matches_the_spec_table() -> void:
	var spec := {
		"cursor_snap": [80, Tween.TRANS_CUBIC, Tween.EASE_OUT],
		"placement_pop": [220, Tween.TRANS_BACK, Tween.EASE_OUT],
		"connector_draw": [160, Tween.TRANS_CUBIC, Tween.EASE_OUT],
		"flow_pulse": [300, Tween.TRANS_SINE, Tween.EASE_IN_OUT],
		"queue_advance": [180, Tween.TRANS_CUBIC, Tween.EASE_OUT],
		"auto_discard": [260, Tween.TRANS_QUAD, Tween.EASE_IN],
		"illegal_shake": [120, Tween.TRANS_ELASTIC, Tween.EASE_OUT],
		"candidate_breathing": [1800, Tween.TRANS_SINE, Tween.EASE_IN_OUT],
		"goal_pulse": [2000, Tween.TRANS_SINE, Tween.EASE_IN_OUT],
		"goal_reached": [700, Tween.TRANS_CUBIC, Tween.EASE_OUT],
		"board_ripple": [500, Tween.TRANS_CUBIC, Tween.EASE_OUT],
		"screen_transition": [320, Tween.TRANS_CUBIC, Tween.EASE_IN_OUT],
		"results_star": [260, Tween.TRANS_BACK, Tween.EASE_OUT],
		"dead_desaturate": [400, Tween.TRANS_CUBIC, Tween.EASE_OUT],
	}
	assert_eq(Motion.TIMINGS.size(), spec.size(), "§14.1 has fourteen rows")
	for name: Variant in spec:
		var want: Array = spec[name]
		assert_true(Motion.TIMINGS.has(name), "§14.1 row %s is missing" % name)
		assert_eq(Motion.milliseconds(str(name)), int(want[0]), "%s duration" % name)
		assert_eq(Motion.transition(str(name)), want[1], "%s transition" % name)
		assert_eq(Motion.ease_type(str(name)), want[2], "%s ease" % name)


func test_seconds_is_the_same_number_in_the_unit_a_tween_wants() -> void:
	assert_almost_eq(Motion.seconds("placement_pop"), 0.22, 0.0001)
	assert_almost_eq(Motion.seconds("candidate_breathing"), 1.8, 0.0001)


## §14.5: all of them, not most of them.
func test_reduce_motion_scales_every_duration() -> void:
	_reduced()
	for name: Variant in Motion.TIMINGS:
		if str(name) == "screen_transition":
			continue
		var full: int = int(Motion.TIMINGS[name]["ms"])
		assert_eq(Motion.milliseconds(str(name)), int(round(float(full) * 0.4)),
			"%s is not scaled" % name)


## The trap: §14.5 names 120 ms for transitions, and 320 × 0.4 is 128.
func test_the_screen_transition_takes_the_number_the_spec_names() -> void:
	_reduced()
	assert_eq(Motion.milliseconds("screen_transition"), 120,
		"§14.5 says 120 ms cross-fades, not a scaled 320")
	assert_ne(Motion.milliseconds("screen_transition"), int(round(320.0 * 0.4)))


## The other trap: a loop under Reduce Motion does not run faster, it stops. A
## candidate breathing at 720 ms is still breathing.
func test_loops_stop_rather_than_shorten() -> void:
	for name: String in Motion.LOOPS:
		assert_true(Motion.loops(name), "%s loops at full motion" % name)
	_reduced()
	for name: String in Motion.LOOPS:
		assert_false(Motion.loops(name), "%s must stop under Reduce Motion (§14.5)" % name)
	# And a one-shot was never a loop to begin with.
	assert_false(Motion.loops("placement_pop"))


func test_the_loops_are_the_ones_the_spec_marks_as_loops() -> void:
	assert_eq(Motion.LOOPS, ["candidate_breathing", "goal_pulse"] as Array[String],
		"§14.1 marks exactly these two as loops")


## §14.2's beats, as offsets from the moment the goal is entered.
func test_the_goal_sequence_matches_the_spec_beats() -> void:
	var spec := {"cell_flourish": 0, "burst": 60, "ripple": 120, "flow": 200,
		"settle": 340, "results": 700}
	assert_eq(Motion.GOAL_SEQUENCE, spec, "§14.2 beat for beat")
	assert_eq(Motion.GOAL_FLOURISH_SCALE, 1.25, "§14.2: 1.0 -> 1.25 -> 1.0")
	assert_eq(Motion.GOAL_FLOURISH_MS, 340)
	assert_eq(Motion.GOAL_FLOW_SPEEDUP, 2.0, "§14.2 runs the flow pulse at 2x")
	# In order, and none of them at the same moment as another.
	var last := -1
	for beat: String in ["cell_flourish", "burst", "ripple", "flow", "settle", "results"]:
		assert_gt(int(Motion.GOAL_SEQUENCE[beat]), last, "%s must come after the one before" % beat)
		last = int(Motion.GOAL_SEQUENCE[beat])


func test_the_goal_beats_scale_with_reduce_motion() -> void:
	assert_almost_eq(Motion.beat_seconds("ripple"), 0.12, 0.0001)
	_reduced()
	assert_almost_eq(Motion.beat_seconds("ripple"), 0.048, 0.0001,
		"a sequence whose beats did not scale would run past its own animations")


## The ripple's per-cell delay scales too. A wave whose front slowed while its body
## sped up would tear.
func test_the_ripple_step_scales_with_everything_else() -> void:
	assert_almost_eq(Motion.ripple_step_seconds(), 0.028, 0.0001)
	_reduced()
	assert_almost_eq(Motion.ripple_step_seconds(), 0.0112, 0.0001)


## §14.3's shake budget is the whole allowance for camera motion the player did not
## ask for: 2 px, 120 ms, once per completion, nowhere else.
func test_the_shake_budget_is_the_one_in_the_spec() -> void:
	assert_eq(Motion.SHAKE_PIXELS, 2.0)
	assert_eq(Motion.SHAKE_MS, 120)


## §14.4: four emitters, and a cap that no combination of them can breach.
func test_the_particle_budget_fits_under_its_own_cap() -> void:
	assert_eq(Motion.PARTICLE_BUDGET.size(), 4, "§14.4 names four emitters")
	var total := 0
	for emitter: Variant in Motion.PARTICLE_BUDGET:
		total += int(Motion.PARTICLE_BUDGET[emitter])
	assert_eq(total, 54, "8 + 24 + 12 + 10")
	assert_lt(total, Motion.PARTICLE_CAP, "one of each fits inside the cap")
	assert_eq(Motion.PARTICLE_CAP, 120)


## §14.5 disables all four emitters, which is a stronger statement than scaling
## their durations.
func test_reduce_motion_turns_particles_off_entirely() -> void:
	assert_true(Motion.particles_allowed())
	_reduced()
	assert_false(Motion.particles_allowed(), "§14.5: no particles")


## A caller takes the duration *and* the curve from the table, or §14.1 is only
## half enforced.
func test_shaping_a_tween_applies_the_row_it_was_given() -> void:
	var tween := create_tween()
	assert_same(Motion.shape(tween, "placement_pop"), tween, "shaping returns the tween")
	tween.kill()

## @core — §14.5, all of it, in one place.
##
## Reduce Motion is spread across a dozen files by construction: every animation
## asks [Motion] for its own duration, the board asks before it shakes, the
## emitters ask before they fire. That is the right shape and it has one cost —
## nothing was checking the *promise*, only the pieces. A row switched off in
## eleven places and left on in the twelfth is a setting that does not work, and it
## fails silently for exactly the players who turned it on.
##
## §14.5 makes four claims. Each is a test here, stated as the spec states it.
extends GutTest


func before_each() -> void:
	SettingsService.set_value("reduce_motion", false)


func after_each() -> void:
	SettingsService.set_value("reduce_motion", false)


## "All durations × 0.4" — every row of §14.1's table, with the one exception the
## section names itself.
func test_every_duration_is_scaled_and_the_named_exception_is_not() -> void:
	var full: Dictionary = {}
	for name: Variant in Motion.TIMINGS:
		full[name] = Motion.milliseconds(str(name))

	SettingsService.set_value("reduce_motion", true)
	for name: Variant in Motion.TIMINGS:
		var row: String = str(name)
		if row == "screen_transition":
			continue
		assert_eq(Motion.milliseconds(row),
			int(round(float(full[row]) * Motion.REDUCE_MOTION_SCALE)),
			"%s is not scaled" % row)

	# §14.5 names 120 ms outright, and 320 × 0.4 is 128 — so a blanket multiplier
	# would be wrong here specifically.
	assert_eq(Motion.milliseconds("screen_transition"), Motion.REDUCED_TRANSITION_MS,
		"the transition takes the number the spec names, not a scaled one")


## "No breathing loops." §14.5 stops them rather than shortening them: a breathing
## stroke at 720 ms is still breathing.
func test_the_loops_stop_rather_than_hurry() -> void:
	for name: String in Motion.LOOPS:
		assert_true(Motion.loops(name), "%s loops at full motion" % name)
	SettingsService.set_value("reduce_motion", true)
	for name: String in Motion.LOOPS:
		assert_false(Motion.loops(name), "%s still loops under §14.5" % name)


## "No particles." All four of §14.4's emitters, off — and a burst asked for while
## it is on does nothing at all rather than firing a shorter one.
func test_no_emitter_fires() -> void:
	var particles := BoardParticles.new()
	add_child_autofree(particles)
	particles.bind(HexLayout.new(40.0, Vector2.ZERO))

	SettingsService.set_value("reduce_motion", true)
	particles.set_motion()
	assert_false(Motion.particles_allowed())
	for name: Variant in Motion.PARTICLE_BUDGET:
		particles.burst(str(name), Vector3.ZERO)
		assert_false(particles.emitter(str(name)).emitting,
			"%s still fires under §14.5" % name)


## "No shake." §14.3's two pixels are the whole camera budget and they are the
## first thing §14.5 takes away.
func test_the_camera_refuses_to_shake() -> void:
	var camera := BoardCamera.new()
	add_child_autofree(camera)
	assert_true(camera.shake_once(), "it shakes once at full motion")

	camera.reset_shake()
	SettingsService.set_value("reduce_motion", true)
	assert_false(camera.shake_once(), "and not at all under §14.5")


## "No parallax." There is none to switch off — §13.7 forbids the backdrop from
## animating on its own, and it is a still image. Asserted rather than assumed,
## because "we did not build one" is exactly the kind of guarantee that lapses the
## day somebody builds one.
func test_the_backdrop_does_not_move() -> void:
	var root := Control.new()
	add_child_autofree(root)
	root.size = Vector2(1280, 800)
	var backdrop: Backdrop = Backdrop.install(root)
	if backdrop == null:
		return  # No art in this build; there is certainly no parallax.

	var was: Vector2 = backdrop.position
	var modulated: Color = backdrop.modulate
	await wait_seconds(0.6)
	assert_eq(backdrop.position, was, "the backdrop drifted")
	assert_eq(backdrop.modulate, modulated, "the backdrop pulsed")


## §14.5 is a motion *reduction*, not a feedback removal — the distinction the
## spec draws itself. What a player is told must survive; only the travelling does.
func test_feedback_survives_what_movement_does_not() -> void:
	SettingsService.set_value("reduce_motion", true)
	for name: Variant in Motion.TIMINGS:
		assert_gt(Motion.milliseconds(str(name)), 0,
			"%s was reduced to nothing; §14.5 shortens, it does not delete" % name)
	assert_gt(Motion.focus_ring_seconds(), 0.0,
		"§12.5's ring is never invisible, and an instant ring is still a ring")

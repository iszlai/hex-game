## @core — §15.2's effects and §15.3's mixing.
##
## The spec singles out one decision here: "the pentatonic ascent turns a long path
## into a melody and makes the core loop feel good on its own". So that is what is
## tested hardest — the scale climbs while a path grows, steps *down* on undo, and
## starts over on a new level, which is the difference between a melody and a
## sequence of unrelated notes.
##
## What cannot be tested is whether any of it sounds good. The effects are
## synthesised from a table in `tools/make_sfx.gd`; a composer would do better, and
## the point of the table is that replacing them changes no code.
extends GutTest


func before_each() -> void:
	EventBus.state_reset.emit(null)


## §15.2 names sixteen, and every one of them has to exist — a missing file is a
## silent event rather than a crash, which is the kind of gap nobody notices.
func test_every_effect_the_spec_names_is_present() -> void:
	assert_eq(AudioDirector.SFX.size(), 16, "§15.2's table has sixteen rows")
	for id: Variant in AudioDirector.SFX:
		assert_true(AudioDirector.has_stream(str(id)), "%s has no audio" % id)


## §15.3's three buses, each with its own slider, all under Master.
func test_the_three_buses_exist_under_master() -> void:
	for bus: Variant in AudioDirector.BUSES:
		var idx: int = AudioServer.get_bus_index(str(bus))
		assert_gte(idx, 0, "§15.3 requires a %s bus" % bus)
		assert_eq(AudioServer.get_bus_send(idx), StringName("Master"), "%s → Master" % bus)


func test_every_effect_is_routed_to_a_real_bus() -> void:
	for id: Variant in AudioDirector.SFX:
		var bus: String = str(AudioDirector.SFX[id])
		assert_true(AudioDirector.BUSES.has(bus), "%s names bus %s" % [id, bus])
	# And the UI family is on the UI bus rather than lumped in with gameplay, or
	# the two sliders §15.3 asks for would move the same sounds.
	for id: String in ["ui.move", "ui.confirm", "ui.back", "ui.reject"]:
		assert_eq(str(AudioDirector.SFX[id]), "UI", "%s belongs to the UI slider" % id)


func test_a_volume_slider_moves_its_own_bus() -> void:
	AudioDirector.set_bus_volume("SFX", 50)
	var idx: int = AudioServer.get_bus_index("SFX")
	assert_almost_eq(AudioServer.get_bus_volume_db(idx), linear_to_db(0.5), 0.01)
	AudioDirector.set_bus_volume("SFX", 100)
	assert_almost_eq(AudioServer.get_bus_volume_db(idx), 0.0, 0.01)


## The decision the spec calls the most important one: the ascent.
func test_the_scale_climbs_with_the_path_and_steps_back_down_on_undo() -> void:
	assert_eq(AudioDirector.placement_note_index(), 0, "a level starts at the root")

	for i: int in range(4):
		EventBus.cell_joined.emit(Vector3i.ZERO, Vector3i.ZERO, 0)
	assert_eq(AudioDirector.placement_note_index(), 4, "four placements, four steps up")

	EventBus.move_undone.emit()
	assert_eq(AudioDirector.placement_note_index(), 3, "§15.2: undo steps *down*")

	EventBus.state_reset.emit(null)
	assert_eq(AudioDirector.placement_note_index(), 0, "and a new level starts over")


## It cannot go below the root however much is undone, or the pitch would invert.
func test_undoing_past_the_start_stays_at_the_root() -> void:
	for i: int in range(5):
		EventBus.move_undone.emit()
	assert_eq(AudioDirector.placement_note_index(), 0)
	assert_almost_eq(AudioDirector.note_pitch(0), 1.0, 0.0001, "the root is the sample's own pitch")


## Major pentatonic, and rising: every step is higher than the last, and the sixth
## is the octave of the first — which is what makes it a scale rather than five
## arbitrary pitches.
func test_the_scale_is_pentatonic_and_rises() -> void:
	assert_eq(AudioDirector.PENTATONIC, [0, 2, 4, 7, 9], "major pentatonic")
	var last := 0.0
	for i: int in range(AudioDirector.PENTATONIC_STEPS * AudioDirector.MAX_OCTAVES):
		var pitch: float = AudioDirector.note_pitch(i)
		assert_gt(pitch, last, "step %d must be higher than step %d" % [i, i - 1])
		last = pitch
	assert_almost_eq(AudioDirector.note_pitch(AudioDirector.PENTATONIC_STEPS), 2.0, 0.0001,
		"the sixth note is the octave")


## A path longer than the scale must not climb out of hearing.
func test_a_long_path_stops_climbing_rather_than_running_away() -> void:
	var top: float = AudioDirector.note_pitch(
		AudioDirector.PENTATONIC_STEPS * AudioDirector.MAX_OCTAVES - 1)
	assert_eq(AudioDirector.note_pitch(500), top, "capped at three octaves")
	assert_lt(top, 9.0, "and three octaves is still a pitch a speaker can render")


## §15.3 caps `place.*` at four voices with stealing on the oldest. A fast player
## commits faster than a 420 ms note decays, so this is reachable in normal play.
func test_placement_voices_are_capped_at_four() -> void:
	for i: int in range(12):
		AudioDirector.play_sfx("place.note")
	assert_lte(AudioDirector.place_voices(), AudioDirector.MAX_PLACE_VOICES,
		"§15.3: four voices, oldest stolen")


## An id that is not in the table is ignored. A missing sound must never be the
## reason a placement fails to register.
func test_an_unknown_effect_is_ignored_rather_than_fatal() -> void:
	AudioDirector.play_sfx("does.not.exist")
	assert_true(true, "and we are still here")

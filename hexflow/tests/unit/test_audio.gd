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


## §15.1's beds. Six tracks, one per chapter plus the menu, each a seamless loop —
## a bed that stopped at the end of its window would be worse than silence.
func test_every_chapter_has_a_bed_and_every_bed_loops() -> void:
	var keys: Array[String] = [AudioDirector.MUSIC_MENU]
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		keys.append("chapter_%d" % chapter)
	for key: String in keys:
		var stream: AudioStream = AudioDirector.call("_music_stream", key)
		assert_not_null(stream, "§15.1 has no bed for %s" % key)
		if stream is AudioStreamOggVorbis:
			assert_true((stream as AudioStreamOggVorbis).loop, "%s does not loop" % key)
		assert_gt(stream.get_length(), 30.0, "%s is too short to sit under a level" % key)


## §15.1: one bed replaces another by cross-fading, never by cutting — the same
## rule §14.1 applies to screens. And asking for the bed already playing does
## nothing, which is what lets every screen call this in `_ready` without the music
## restarting each time the player opens the settings and comes back.
func test_a_bed_changes_by_fading_and_never_restarts_itself() -> void:
	AudioDirector.play_music("chapter_1")
	assert_eq(AudioDirector.music_key(), "chapter_1")
	var players: Array = AudioDirector.get("_music")
	var live: int = int(AudioDirector.get("_playing"))

	AudioDirector.play_music("chapter_1")
	assert_eq(int(AudioDirector.get("_playing")), live, "the same bed is not restarted")

	AudioDirector.play_music("chapter_2")
	assert_eq(AudioDirector.music_key(), "chapter_2")
	assert_ne(int(AudioDirector.get("_playing")), live, "the next bed comes up on the other player")
	assert_true((players[live] as AudioStreamPlayer).playing,
		"and the outgoing one is still sounding while it fades")
	AudioDirector.stop_music()


## A key with no track costs the player the music and never the game (§13.6's
## replaceability rule, applied to audio).
func test_a_missing_bed_is_silence_rather_than_an_error() -> void:
	AudioDirector.play_music("chapter_1")
	AudioDirector.play_music("a_chapter_that_does_not_exist")
	assert_eq(AudioDirector.music_key(), "", "nothing is claimed to be playing")
	AudioDirector.stop_music()


## §15.1: "Music ducks −6 dB for 600 ms on the goal-reached sequence." It returns
## to the *slider's* level rather than to whatever the bus was at, so ducking twice
## in quick succession cannot ratchet the music down and leave it there.
func test_the_goal_ducks_the_music_and_gives_it_back() -> void:
	var bus: int = AudioServer.get_bus_index("Music")
	# The *setting*, not the bus. `duck` returns the music to where the player's own
	# slider says it belongs — pushing the bus directly and expecting the duck to
	# honour it would be testing a design the setting deliberately does not have.
	var was: Variant = SettingsService.get_value("music_volume")
	SettingsService.set_value("music_volume", 100)
	AudioDirector.set_bus_volume("Music", 100)
	var level: float = AudioServer.get_bus_volume_db(bus)

	AudioDirector.duck()
	assert_almost_eq(AudioServer.get_bus_volume_db(bus), level + AudioDirector.DUCK_DB, 0.01,
		"the bed steps out of the goal's way")

	AudioDirector.duck()
	assert_almost_eq(AudioServer.get_bus_volume_db(bus), level + AudioDirector.DUCK_DB, 0.01,
		"a second duck does not stack on the first")

	await wait_seconds(AudioDirector.DUCK_SECONDS + AudioDirector.MUSIC_CROSSFADE)
	assert_almost_eq(AudioServer.get_bus_volume_db(bus), level, 0.5, "and it comes back")
	SettingsService.set_value("music_volume", was)


## §15.2 names an event for each of its sixteen effects, and ten of them were wired
## to nothing: the game won, died, reached a goal, opened a gate, linked a portal
## and picked up a wild in silence, with the WAV loaded and the bus assigned the
## whole time. Nothing failed, because a sound nobody plays looks exactly like a
## sound nobody hears — which is why this asserts the *wiring*, one row of §15.2's
## table at a time, rather than the files.
func test_every_event_the_spec_names_actually_makes_its_sound() -> void:
	var cases: Array = [
		["goal.reach", func() -> void: EventBus.goal_reached.emit(Vector3i.ZERO)],
		["gate.open", func() -> void: EventBus.gate_opened.emit(Vector3i.ZERO)],
		["level.win", func() -> void: EventBus.level_won.emit(6, 6, 3)],
		["level.dead", func() -> void: EventBus.level_dead.emit(0)],
		["portal.link", func() -> void:
			EventBus.portal_linked.emit(Vector3i.ZERO, Vector3i.ONE)],
		["tile.discard", func() -> void: EventBus.tile_discarded.emit(0, 2)],
		["tile.autoskip", func() -> void: EventBus.tile_auto_skipped.emit(0)],
		["tile.advance", func() -> void: EventBus.tile_advanced.emit(0, [])],
	]
	for case: Variant in cases:
		var id: String = str((case as Array)[0])
		AudioDirector.history.clear()
		((case as Array)[1] as Callable).call()
		assert_true(AudioDirector.history.has(id),
			"§15.2's %s event played %s" % [id, AudioDirector.history])


## The bell belongs to a wild being *gained*. The signal carries the running total
## and is emitted for a spend too, so a handler that simply plays on every change
## would ring while the charge is being used up.
func test_the_wild_bell_rings_on_a_gain_and_not_on_a_spend() -> void:
	EventBus.state_reset.emit(null)

	AudioDirector.history.clear()
	EventBus.wild_charges_changed.emit(1)
	assert_true(AudioDirector.history.has("wild.pickup"), "gaining a charge rings")

	AudioDirector.history.clear()
	EventBus.wild_charges_changed.emit(0)
	assert_false(AudioDirector.history.has("wild.pickup"), "spending it does not")

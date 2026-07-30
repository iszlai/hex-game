## @core — §14.4's four emitters and the cap over them.
##
## The budget is the whole of §14.4, so it is asserted against the spec's own
## numbers rather than against the code's. The other half is §14.5: "Reduce Motion
## disables all four" is a stronger statement than shortening a lifetime, and an
## emitter that merely ran briefly would still be motion on screen for a player who
## asked for none.
extends GutTest

const PLAY := Vector2(880.0, 688.0)

var _view: BoardView3D = null
var _particles: BoardParticles = null
var _state: GameState = null


func before_each() -> void:
	_state = GameState.start(Fixtures.modifier_level())
	_view = BoardView3D.new()
	add_child_autofree(_view)
	_view.bind(_state, PLAY)
	_particles = _view.particles


func after_each() -> void:
	SettingsService.set_value("reduce_motion", false)


func test_there_are_four_emitters_and_they_are_the_spec_ones() -> void:
	assert_eq(BoardParticles.EMITTERS.size(), 4, "§14.4 names four")
	for name: String in ["placement_sparks", "goal_burst", "flow_motes", "wild_pickup"]:
		assert_not_null(_particles.emitter(name), "%s is missing" % name)
		assert_eq(_particles.emitter(name).amount, int(Motion.PARTICLE_BUDGET[name]),
			"%s is not at its §14.4 budget" % name)


## The cap is a hard one, so it is checked against what every emitter could hold at
## once rather than against what usually happens.
func test_every_emitter_at_once_fits_under_the_cap() -> void:
	var total := 0
	for name: Variant in BoardParticles.EMITTERS:
		total += _particles.emitter(str(name)).amount
	assert_eq(total, BoardParticles.live_budget(), "the table and the emitters agree")
	assert_lte(total, Motion.PARTICLE_CAP, "§14.4's hard cap of 120")
	# And with room for a second burst on top, which is what a cap is for.
	assert_lte(total + int(Motion.PARTICLE_BUDGET["goal_burst"]), Motion.PARTICLE_CAP)


## Built once, at bind, rather than one system per event — a particle system
## created the moment something happens is an allocation in that frame (C4).
func test_the_emitters_are_built_once_and_reused() -> void:
	var before: GPUParticles3D = _particles.emitter("placement_sparks")
	_particles.burst("placement_sparks", Vector3.ZERO)
	_particles.burst("placement_sparks", Vector3(10.0, 0.0, 10.0))
	assert_same(_particles.emitter("placement_sparks"), before, "same node both times")
	assert_eq(_particles.get_child_count(), 4, "and four in total, still")


func test_a_burst_happens_where_it_was_asked_for() -> void:
	var at := Vector3(12.0, 3.0, -8.0)
	_particles.burst("goal_burst", at)
	assert_eq(_particles.emitter("goal_burst").position, at)
	assert_true(_particles.emitter("goal_burst").emitting, "and is actually running")


## The one-shots are one-shots: a spark burst that looped would be ambient motion
## §14.4 did not budget for.
func test_only_the_ambient_emitter_runs_continuously() -> void:
	for name: Variant in BoardParticles.EMITTERS:
		var ambient: bool = bool(BoardParticles.EMITTERS[name]["ambient"])
		assert_eq(_particles.emitter(str(name)).one_shot, not ambient,
			"%s one_shot" % name)
	assert_true(_particles.emitter("flow_motes").emitting, "the motes are the ambient one")


## §14.5: all four off, and a burst asked for while it is on does nothing at all
## rather than firing a shorter one.
func test_reduce_motion_silences_every_emitter() -> void:
	SettingsService.set_value("reduce_motion", true)
	assert_false(_particles.emitter("flow_motes").emitting, "ambient motes stop")

	_particles.burst("goal_burst", Vector3.ZERO)
	assert_false(_particles.emitter("goal_burst").emitting,
		"§14.5 disables all four — a burst must not fire at all")

	SettingsService.set_value("reduce_motion", false)
	assert_true(_particles.emitter("flow_motes").emitting, "and they come back")


## Every emitter's colour is a palette token, so §21's four palettes reach the
## particles too rather than stopping at the board.
func test_every_emitter_is_coloured_from_the_palette() -> void:
	var palette: Palette = load("res://src/data/palettes/neon_dark.tres")
	for name: Variant in BoardParticles.EMITTERS:
		var token: String = str(BoardParticles.EMITTERS[name]["token"])
		var mat := _particles.emitter(str(name)).process_material as ParticleProcessMaterial
		assert_eq(mat.color, palette.get(token) as Color, "%s takes %s" % [name, token])


## §6's wild is the one cell that hands the player something, and §14.4 gives it
## its own emitter — so entering one has to fire it and entering anything else
## must not.
func test_entering_a_wild_fires_its_own_emitter() -> void:
	var wild := Vector3i(-2, 1, 1)
	assert_true(_state.board.is_wild(wild), "fixture sanity")
	_view.play_placement(Vector3i(-1, 0, 1))
	assert_false(_particles.emitter("wild_pickup").emitting, "not on an ordinary cell")
	_view.play_placement(wild)
	assert_true(_particles.emitter("wild_pickup").emitting)
	assert_true(_particles.emitter("placement_sparks").emitting,
		"and the ordinary sparks fire either way")

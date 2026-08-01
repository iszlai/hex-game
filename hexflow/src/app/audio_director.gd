extends Node
## §15's mixing, playback and the pentatonic placement index. Decides nothing about
## gameplay: it hears the same facts the view sees and makes a noise.
##
## Three buses under Master (§15.3), each with its own slider. Every effect names
## the bus it belongs on in [constant SFX], so a UI tick and a placement note stay
## independently mixable without any call site knowing which is which.
##
## The pentatonic ascent is the piece the spec singles out — "the single most
## important audio decision" — because it is what turns a long path into a melody.
## It is **one sample, pitched**: the scale lives here as ratios rather than as
## sixteen recorded notes, so retuning it re-renders nothing.

const SFX_DIR := "res://assets/sfx/"
const MUSIC_DIR := "res://assets/music/"

## §15.1's beds: one per chapter plus a menu track. Keyed by role, like §13.6's
## art manifest and for the same reason — a screen asks for "chapter 3", never for
## a filename, so the tracks can be replaced without a script changing.
const MUSIC_MENU := "menu"

## §15.1: "1.5 s cross-fade". One bed replaces another by fading, never by cutting,
## which is the same rule §14.1 applies to screens.
const MUSIC_CROSSFADE := 1.5

## §15.1's three stems, in the order they are laid out per deck.
const STEMS: Array[String] = ["base", "layer", "extra"]

## §15.1: the layer "fades in as board fill % rises above 40%, out below 30%".
## The numbers are the spec's; what is measured against them is not (C-41) — see
## [method GameDirector.music_intensity].
const LAYER_IN := 0.40
const LAYER_OUT := 0.30

## §15.1: endless "adds a third stem that enters every 5 goals".
const EXTRA_EVERY := 5

## Where a stem sits when it is up. Zero: the mix was balanced when the three were
## rendered (`tools/make_music.gd` normalises their *sum*), so the game's job is to
## bring a stem to the level it was written at and not to mix it again.
const STEM_DB := 0.0

## §15.1: "Music ducks −6 dB for 600 ms on the goal-reached sequence." The goal is
## the loudest thing the game does and the bed has to get out of its way.
const DUCK_DB := -6.0
const DUCK_SECONDS := 0.6

## §15.2's sixteen, and the §15.3 bus each belongs on.
const SFX := {
	"ui.move": "UI",
	"ui.confirm": "UI",
	"ui.back": "UI",
	"ui.reject": "UI",
	"place.note": "SFX",
	"place.connector": "SFX",
	"tile.advance": "SFX",
	"tile.discard": "SFX",
	"tile.autoskip": "SFX",
	"goal.reach": "SFX",
	"level.win": "SFX",
	"level.dead": "SFX",
	"star.award": "SFX",
	"wild.pickup": "SFX",
	"portal.link": "SFX",
	"gate.open": "SFX",
}

## §15.3's buses and their default sliders.
const BUSES := {"Music": 70, "SFX": 85, "UI": 85}

## Major pentatonic, in semitones. Five degrees and then the octave, which is what
## makes a long path climb rather than wander.
const PENTATONIC := [0, 2, 4, 7, 9]
const PENTATONIC_STEPS := 5

## §15.3: at most four `place.*` voices, stealing the oldest.
const MAX_PLACE_VOICES := 4

## Three octaves covers any path a radius-4 board can hold and stops a long one
## climbing out of hearing.
const MAX_OCTAVES := 3

## Voices for everything that is not a placement. Six is comfortably more than the
## number of non-placement sounds that can overlap.
const GENERAL_VOICES := 6

## Every effect played, in order. Test-facing, and never read by the game.
var history: Array[String] = []

var _scale_index: int = 0

## Last wild total seen, so a gain can be told from a spend (§15.2's bell is for
## the gain). Rewound by an undo the same way the charges themselves are, because
## the signal reports the total after the rewind.
var _wild_charges: int = 0
## Two players so a bed can cross-fade into another one; `_playing` is which of
## them currently holds the live track, and `_music_key` is what it is.
var _music: Array[AudioStreamPlayer] = []
var _playing: int = 0
var _music_key: String = ""
var _music_tween: Tween = null
## Which of §15.1's adaptive stems are up, and the tween riding each one. Kept per
## stem so a layer arriving does not cancel a bed change already in flight.
var _layer_up: bool = false
var _extra_up: bool = false
var _stem_tweens: Dictionary = {}
var _duck_tween: Tween = null
var _streams: Dictionary = {}                    # id -> AudioStream
var _general: Array[AudioStreamPlayer] = []
var _place_voices: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_ensure_buses()
	_load_streams()
	_build_voices()
	EventBus.cell_joined.connect(_on_cell_joined)
	EventBus.move_undone.connect(_on_move_undone)
	EventBus.state_reset.connect(_on_state_reset)
	_build_music()
	# §15.1's duck belongs to the goal beat, so it rides the same fact the flourish,
	# the burst and the ripple all ride.
	EventBus.goal_reached.connect(func(_cell: Vector3i) -> void:
		play_sfx("goal.reach")
		duck())

	# §15.2 names an event for each of its sixteen effects. Ten of them had a WAV,
	# a bus and an entry in [constant SFX] and were played by nothing — the game
	# won, died, picked up a wild and opened a gate in silence. Each one is wired
	# to the [EventBus] fact that *is* the event §15.2 names, so a sound cannot
	# drift away from the moment it reports.
	EventBus.level_won.connect(func(_p: int, _par: int, _s: int) -> void:
		play_sfx("level.win"))
	EventBus.level_dead.connect(func(_reason: int) -> void: play_sfx("level.dead"))
	EventBus.portal_linked.connect(func(_from: Vector3i, _to: Vector3i) -> void:
		play_sfx("portal.link"))
	EventBus.gate_opened.connect(func(_cell: Vector3i) -> void: play_sfx("gate.open"))
	EventBus.tile_discarded.connect(func(_dir: int, _left: int) -> void:
		play_sfx("tile.discard"))
	EventBus.tile_auto_skipped.connect(func(_dir: int) -> void: play_sfx("tile.autoskip"))
	EventBus.tile_advanced.connect(_on_tile_advanced)
	EventBus.wild_charges_changed.connect(_on_wild_charges_changed)


# --- music (§15.1) -------------------------------------------------------------

## Two decks of three, so a bed can cross-fade into the next one rather than
## cutting, and each bed can bring its own stems up and down while it plays.
##
## Built once at boot: a music player created when a screen changes is a player
## created during a fade, which is the worst moment to allocate one.
func _build_music() -> void:
	for deck: int in range(2):
		for stem: String in STEMS:
			var player := AudioStreamPlayer.new()
			player.name = "Music%d_%s" % [deck, stem]
			player.bus = "Music"
			player.volume_db = -80.0
			add_child(player)
			_music.append(player)


## Plays the bed for [param key] — "menu", "chapter_3" — cross-fading over §15.1's
## 1.5 s. Asking for the bed that is already playing does nothing, which is what
## lets every screen call this in `_ready` without the music restarting each time
## the player opens the settings and comes back.
func play_music(key: String) -> void:
	if key == _music_key:
		return
	var base: AudioStream = _music_stream(key, "base")
	_music_key = key if base != null else ""
	if _music.size() < STEMS.size() * 2:
		return

	var next: int = 1 - _playing
	if _music_tween != null and _music_tween.is_running():
		_music_tween.kill()
	# A stem still riding up belongs to the bed being replaced. Left running it
	# would fight the cross-fade for the same property on the same player, and the
	# outgoing layer would climb while everything else was leaving.
	for tween: Variant in _stem_tweens.values():
		if tween is Tween and (tween as Tween).is_running():
			(tween as Tween).kill()
	_stem_tweens.clear()

	# The three stems are started on the same frame and never touched again, which
	# is what keeps them in step: they are one performance cut into three files
	# (§15.1), so the only thing that may differ between them is level. Seeking or
	# restarting one of them is the one way to break that, so nothing here does.
	if base != null:
		for stem: String in STEMS:
			var player: AudioStreamPlayer = _deck(next, stem)
			player.stream = base if stem == "base" else _music_stream(key, stem)
			player.volume_db = -80.0
			if player.stream != null:
				player.play()
	_playing = next
	# A new bed starts at its base and earns the rest: a level opening at 60% fill
	# would otherwise arrive with the layer already up, which reads as the music
	# being loud rather than as the board being full.
	_layer_up = false
	_extra_up = false

	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	for stem: String in STEMS:
		var incoming: AudioStreamPlayer = _deck(next, stem)
		var outgoing: AudioStreamPlayer = _deck(1 - next, stem)
		if base != null and incoming.stream != null and stem == "base":
			_music_tween.tween_property(incoming, "volume_db", 0.0, MUSIC_CROSSFADE)
		_music_tween.tween_property(outgoing, "volume_db", -80.0, MUSIC_CROSSFADE)
		_music_tween.chain().tween_callback(outgoing.stop)


## §15.1's adaptive layer: in above 40%, out below 30%, over 1.5 s.
##
## Two thresholds rather than one, because a single one at 40% would fade the
## layer in and out on every placement made near it — the player would hear the
## music breathing in time with their own indecision. The gap is the spec's, and
## it is the difference between an adaptive bed and a wobbling one.
##
## [param intensity] is 0..1 and the audio layer does not ask what it counts;
## [method GameDirector.music_intensity] decides that, and C-41 is why it is not
## the board's fill.
func set_intensity(intensity: float) -> void:
	if _layer_up and intensity < LAYER_OUT:
		_layer_up = false
		_fade_stem("layer", false)
	elif not _layer_up and intensity > LAYER_IN:
		_layer_up = true
		_fade_stem("layer", true)


## §15.1's third stem, which endless brings in every five goals. On once it is on:
## a run is an escalation, and a layer that came and went with the count would be
## reporting the arithmetic rather than the escalation.
func set_goals(goals: int) -> void:
	var wanted: bool = goals >= EXTRA_EVERY
	if wanted == _extra_up:
		return
	_extra_up = wanted
	_fade_stem("extra", wanted)


## Whether a stem is currently up, which is the honest thing for a test to ask.
func stem_up(stem: String) -> bool:
	if stem == "layer":
		return _layer_up
	return _extra_up if stem == "extra" else _music_key != ""


func _deck(deck: int, stem: String) -> AudioStreamPlayer:
	return _music[deck * STEMS.size() + STEMS.find(stem)]


## Rides one stem of the live deck up or down over §15.1's cross-fade. Its own
## tween per stem, so a layer arriving does not cancel a bed change already in
## flight — and the outgoing deck is never touched, because it is on its way out
## with everything it holds.
func _fade_stem(stem: String, up: bool) -> void:
	var player: AudioStreamPlayer = _deck(_playing, stem)
	if player.stream == null:
		return
	if not player.playing:
		player.play()
	var tween: Tween = _stem_tweens.get(stem)
	if tween != null and tween.is_running():
		tween.kill()
	tween = create_tween()
	tween.tween_property(player, "volume_db", STEM_DB if up else -80.0, MUSIC_CROSSFADE)
	_stem_tweens[stem] = tween


## Stops the bed, fading rather than cutting.
func stop_music() -> void:
	play_music("")


func music_key() -> String:
	return _music_key


## §15.1: −6 dB for 600 ms on the goal-reached sequence, then back. On the *bus*
## rather than on the players, so it survives a cross-fade landing mid-duck.
func duck() -> void:
	var bus: int = AudioServer.get_bus_index("Music")
	if bus < 0:
		return
	if _duck_tween != null and _duck_tween.is_running():
		_duck_tween.kill()
	# The slider's own level is where the duck returns to, so a player who has the
	# music at 40% does not get it handed back at 100%.
	var level: float = _slider_db("Music")
	var set_db := func(db: float) -> void: AudioServer.set_bus_volume_db(bus, db)
	AudioServer.set_bus_volume_db(bus, level + DUCK_DB)
	_duck_tween = create_tween()
	# Held down for §15.1's 600 ms, then let back up. `AudioServer` is not a `Node`,
	# so the bus is driven by a method tween rather than a property one.
	_duck_tween.tween_interval(DUCK_SECONDS)
	_duck_tween.tween_method(set_db, level + DUCK_DB, level, MUSIC_CROSSFADE * 0.5)


## The bed for a key, or `null` when the build has no music for it. §13.6's
## replaceability rule applies to audio too: a missing track costs the player the
## music and never the game.
func _music_stream(key: String, stem: String = "base") -> AudioStream:
	if key == "":
		return null
	var path: String = "%s%s_%s.ogg" % [MUSIC_DIR, key, stem]
	if not ResourceLoader.exists(path):
		# Only the base falls back. A build whose music arrived as one file per bed
		# still plays, with the adaptive layer simply never arriving — §13.6's
		# replaceability rule applied to a half-finished asset drop rather than to
		# a missing one.
		if stem != "base":
			return null
		path = MUSIC_DIR + key + ".ogg"
		if not ResourceLoader.exists(path):
			return null
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		# A bed that stopped at the end of its 48 seconds would be worse than none.
		(stream as AudioStreamOggVorbis).loop = true
	return stream


## Where a bus *should* sit, from the player's own slider — not where it currently
## sits, which may be mid-duck. Ducking twice in 600 ms would otherwise ratchet the
## music down six decibels at a time and never bring it back.
func _slider_db(name: String) -> float:
	var percent: int = int(SettingsService.get_value(name.to_lower() + "_volume"))
	return linear_to_db(clampf(float(percent) / 100.0, 0.0, 1.0))


## The rising pentatonic ascent. Resets per level, steps down on undo.
func placement_note_index() -> int:
	return _scale_index


## The pitch [param index] of the ascent sounds at, as a playback ratio: degree
## within the scale, then octave, capped so a long path does not climb away.
func note_pitch(index: int) -> float:
	var capped: int = clampi(index, 0, PENTATONIC_STEPS * MAX_OCTAVES - 1)
	@warning_ignore("integer_division")
	var octave: int = capped / PENTATONIC_STEPS
	var degree: int = capped % PENTATONIC_STEPS
	return pow(2.0, float(int(PENTATONIC[degree]) + 12 * octave) / 12.0)


## Plays [param id] from §15.2's table. An unknown id is ignored rather than fatal:
## a sound is never worth taking a screen down for.
func play_sfx(id: String) -> void:
	if not _streams.has(id):
		return
	# Recorded the way [Haptics] records its patterns, and for the same reason: CI
	# has no speakers, so "did the win make a sound" is otherwise a question only a
	# person with headphones can answer — which is how ten of §15.2's sixteen came
	# to be wired to nothing without a test noticing.
	history.append(id)
	var player: AudioStreamPlayer = _claim_voice(id)
	if player == null:
		return
	player.stream = _streams[id]
	player.bus = str(SFX[id])
	player.pitch_scale = note_pitch(_scale_index) if id == "place.note" else 1.0
	player.play()


func set_bus_volume(bus: String, percent: int) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(percent / 100.0, 0.0, 1.0)))


## How many `place.*` voices are sounding. §15.3 caps this at four, and a cap is
## worth being able to read rather than infer.
func place_voices() -> int:
	var live := 0
	for player: AudioStreamPlayer in _place_voices:
		if player.playing:
			live += 1
	return live


func has_stream(id: String) -> bool:
	return _streams.has(id)


## §15.3's voice limit, with stealing on the oldest. Only `place.*` is capped: the
## spec names that family, because it is the one a fast player triggers four times
## in a second.
func _claim_voice(id: String) -> AudioStreamPlayer:
	if not id.begins_with("place."):
		for player: AudioStreamPlayer in _general:
			if not player.playing:
				return player
		return _general[0] if not _general.is_empty() else null
	for player: AudioStreamPlayer in _place_voices:
		if not player.playing:
			_place_voices.erase(player)
			_place_voices.append(player)
			return player
	# All four sounding: take the one that started first.
	var oldest: AudioStreamPlayer = _place_voices[0]
	_place_voices.erase(oldest)
	_place_voices.append(oldest)
	oldest.stop()
	return oldest


## §15.3's three buses under Master. Built here rather than as a `.tres` layout so
## the names and their defaults sit beside the table that uses them.
func _ensure_buses() -> void:
	for bus: Variant in BUSES:
		if AudioServer.get_bus_index(str(bus)) < 0:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, str(bus))
			AudioServer.set_bus_send(idx, "Master")
		var key: String = "%s_volume" % str(bus).to_lower()
		var stored: Variant = SettingsService.get_value(key)
		set_bus_volume(str(bus), int(stored) if stored != null else int(BUSES[bus]))


func _load_streams() -> void:
	for id: Variant in SFX:
		var path: String = SFX_DIR + str(id).replace(".", "_") + ".wav"
		if not ResourceLoader.exists(path):
			push_warning("§15.2 names %s but %s is missing; run `make sfx`" % [id, path])
			continue
		_streams[id] = load(path)


## A fixed pool, allocated once. A sound effect must never allocate on the frame
## the thing it is reporting happened (C4).
func _build_voices() -> void:
	for i: int in range(MAX_PLACE_VOICES):
		_place_voices.append(_new_player("PlaceVoice%d" % i))
	for i: int in range(GENERAL_VOICES):
		_general.append(_new_player("Voice%d" % i))


func _new_player(name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = name
	add_child(player)
	return player


func _on_cell_joined(_target: Vector3i, _anchor: Vector3i, _dir: int) -> void:
	# The note first, then the swell §15.2 layers *under* it.
	play_sfx("place.note")
	play_sfx("place.connector")
	_scale_index += 1


func _on_move_undone() -> void:
	# §15.2: undo plays the note one step *down*, which is what makes taking a move
	# back sound like taking it back rather than like making another one.
	_scale_index = maxi(0, _scale_index - 1)
	play_sfx("place.note")


## §15.2's "light paper/glass slide", under the queue-advance animation of §14.1.
## [signal EventBus.tile_advanced] is only ever emitted from a publish, so it
## already means "the player did something and the queue moved" and never fires on
## a level opening.
func _on_tile_advanced(_current: int, _preview: Array) -> void:
	play_sfx("tile.advance")


## §15.2 gives the bell to a wild being *gained*. The signal carries the running
## total and is emitted for a spend as well, which sounds identical from here — so
## the direction is what decides, not the fact.
func _on_wild_charges_changed(charges: int) -> void:
	if charges > _wild_charges:
		play_sfx("wild.pickup")
	_wild_charges = charges


func _on_state_reset(_state: GameState) -> void:
	_scale_index = 0
	_wild_charges = 0

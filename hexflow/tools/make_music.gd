extends SceneTree
## Offline authoring step: **composes** §15.1's six beds and renders each one as
## three stems that line up sample for sample. Run it with `make music`; the
## output is committed.
##
##     Godot --headless --path . -s res://tools/make_music.gd -- [track]
##
## ## Why this exists rather than a folder of downloads
##
## §15.1 does not ask for six pieces of music. It asks for six pieces **exported
## three times**: a `base` that always plays, a `layer` that fades in as the level
## fills, and a third that endless brings in every five goals. The three have to be
## the same performance, because they are played *together* — and two renders of
## "the same" piece are two performances. They phase, they drift, and nothing makes
## their bars line up. That is not a quality problem a better generator fixes; it
## is what "render" means.
##
## The beds before these were cut from two finished recordings, which is why the
## layer never arrived: there was no session to go back to. A generator will
## happily produce another variation and cannot produce *the same take with the
## piano muted*, because it never had takes.
##
## So the music is written down here as a **score** — chords, a bar grid, one entry
## per part — and rendered by the synthesiser below. Muting a part is then exactly
## what it sounds like: the same clock, the same chords, the same decay tails, one
## fewer voice. Three stems out of one pass over one score, aligned by construction
## rather than by luck.
##
## ## What it sounds like, and why
##
## Lo-fi jazz: a Rhodes comping sevenths and ninths over an upright bass, tape
## noise underneath, everything on a swung eighth grid.
##
## The first version of this file was **pads** — sustained sine stacks held for a
## whole bar — and the note that came back was that it sounded like an organ. It
## did, for a structural reason worth writing down: a chord that starts and does not
## stop *is* an organ, whatever it is voiced with. What makes a Rhodes a Rhodes is
## that every note decays, so the harmony is re-struck rather than held, and the gap
## between strikes is where the room and the hiss live.
##
## The other half is the chords. Triads are hymns; sevenths and ninths, voiced
## without their root — the bass has that — and spread over an octave, are the
## sound the note was asking for.
##
## §15.1 forbids percussion in the campaign, so there are no drums: the swing is
## carried by the comping and the bass. The vinyl bed is texture rather than a
## beat, which is what keeps it on the right side of that rule and also what makes
## it work.
##
## ## What comes out
##
## `assets/music/<track>_<stem>.wav`, 44.1 kHz stereo, seamlessly loopable, and the
## Makefile encodes them to `.ogg` with ffmpeg — Godot cannot write Vorbis and a
## 2-minute stereo WAV is 21 MB.
##
## Not part of the shipped game.

const RATE := 44100
const OUT_DIR := "res://assets/music/"

## §15.1: `base` always, `layer` as the level fills, and a third for endless.
const STEMS: Array[String] = ["base", "layer", "extra"]

## Bars per loop, and how long a chord is held.
##
## Two bars a chord rather than one: the single loudest thing you can do to make a
## piece feel unhurried is to change the harmony half as often. Eight chords at two
## bars each is a 16-bar cycle, so the loop is 48 bars — three turns, landing
## between 2:30 and 2:45, inside §15.1's 2–3 minutes and never cutting a phrase in
## half.
const BARS := 48
const BARS_PER_CHORD := 2
const BEATS_PER_BAR := 4

## How long the last bar is allowed to ring past the end before being folded back
## over the beginning. Longer than the longest decay below, or a chord would be cut
## off at the seam — which is the click a loop is judged by.
const TAIL_SECONDS := 6.0

## Equal temperament from A4, which is the only tuning fact in the file.
const A4 := 440.0

## How far the second eighth of each beat is pushed, as a fraction of the beat. 0.5
## is straight and 0.667 is a hard triplet swing; 0.60 is the lazy, behind-the-beat
## feel this is after, and it is applied to *every* part — swing is not an effect on
## one instrument, it is where the whole band agrees the off-beat is.
const SWING := 0.60

## Chord qualities, as semitones from the chord's root. Every one of them has its
## seventh, because a triad in this style is a hymn.
const QUALITIES := {
	"min7":  [0, 3, 7, 10],
	"min9":  [0, 3, 7, 10, 14],
	"maj7":  [0, 4, 7, 11],
	"maj9":  [0, 4, 7, 11, 14],
	"dom9":  [0, 4, 7, 10, 14],
	"m7b5":  [0, 3, 6, 10],
	"min11": [0, 3, 7, 10, 17],
}

## What the melody draws from, relative to the *key*: the minor pentatonic, which
## is the safe pool over a ii–V–i and can be leaned on precisely because the line
## is slow and sparse.
const PENTATONIC: Array[int] = [0, 3, 5, 7, 10]

## The six beds. One row is a whole piece: what key it is in, how fast, and the
## eight chords it turns on — `[semitones above the key root, quality]`.
##
## They are ii–V–i loops with the odd substitution, which is the harmony this style
## is made of. Tempos sit at the bottom of §15.1's 70–85 BPM and rise a little
## across the campaign, which is the cheapest way for five beds to feel like a
## sequence rather than a set. `bright` is how much tine the Rhodes has: chapter 5
## is the tense one and gets the least.
const TRACKS := {
	"menu": {
		"root": 57, "bpm": 70, "bright": 0.45,          # A minor
		"chords": [[2, "m7b5"], [7, "dom9"], [0, "min9"], [0, "min9"],
			[5, "maj9"], [7, "dom9"], [0, "min9"], [10, "maj9"]],
	},
	"chapter_1": {
		"root": 60, "bpm": 70, "bright": 0.55,          # C major, warm
		"chords": [[0, "maj9"], [9, "min9"], [2, "min9"], [7, "dom9"],
			[0, "maj9"], [9, "min9"], [5, "maj7"], [7, "dom9"]],
	},
	"chapter_2": {
		"root": 58, "bpm": 72, "bright": 0.48,          # B♭ major
		"chords": [[2, "min9"], [7, "dom9"], [0, "maj9"], [5, "maj7"],
			[2, "min9"], [7, "dom9"], [0, "maj9"], [9, "min7"]],
	},
	"chapter_3": {
		"root": 55, "bpm": 72, "bright": 0.40,          # G minor
		"chords": [[0, "min9"], [5, "dom9"], [10, "maj9"], [3, "maj7"],
			[2, "m7b5"], [7, "dom9"], [0, "min9"], [0, "min11"]],
	},
	"chapter_4": {
		"root": 52, "bpm": 74, "bright": 0.34,          # E minor, darker
		"chords": [[0, "min9"], [0, "min9"], [8, "maj9"], [10, "dom9"],
			[2, "m7b5"], [7, "dom9"], [0, "min9"], [3, "maj7"]],
	},
	"chapter_5": {
		"root": 50, "bpm": 76, "bright": 0.28,          # D minor, tense
		"chords": [[0, "min9"], [7, "m7b5"], [10, "dom9"], [0, "min11"],
			[5, "min7"], [10, "dom9"], [0, "min9"], [7, "dom9"]],
	},
}

## §15.3's integrated target, reached the only way a renderer can reach it without a
## loudness meter: RMS, with the offset between the two measured on this material.
## −18.2 dBFS RMS lands at −16 LUFS — checked with `ffmpeg -af ebur128` on all six.
##
## Measured on `base + layer`, because that is the mix a player hears for most of a
## level; the base alone is quieter on purpose and the third stem is endless-only.
const MIX_RMS_DB := -18.2

## And the ceiling, on all three at once. §15.3 wants −1 dBTP; −2 leaves the encoder
## room to overshoot a sample peak on the way to Vorbis. Loudness gives way to this
## rather than the other way round: a bed 1 dB quiet is nobody's problem and a
## clipped one is everybody's.
const SUM_PEAK_DB := -2.0

var _bar_samples: int = 0
var _tail_samples: int = 0
var _total: int = 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var only: String = str(args[0]) if args.size() > 0 else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	for name: String in TRACKS:
		if only != "" and name != only:
			continue
		_render_track(name, TRACKS[name])
	print("stems are frozen assets — the Makefile encodes them, commit the .ogg")
	quit()


## One pass over one score, three buffers out. Every note is written into the stem
## its part belongs to and into no other, so the three files are the same
## performance with parts muted — which is the whole point of the exercise.
func _render_track(name: String, spec: Dictionary) -> void:
	var bpm: float = float(spec["bpm"])
	var beat: float = 60.0 / bpm
	_bar_samples = int(beat * float(BEATS_PER_BAR) * float(RATE))
	_tail_samples = int(TAIL_SECONDS * float(RATE))
	_total = _bar_samples * BARS

	var stems: Dictionary = {}
	for stem: String in STEMS:
		var buffer := PackedFloat32Array()
		buffer.resize((_total + _tail_samples) * 2)
		buffer.fill(0.0)
		stems[stem] = buffer

	# Deterministic, and seeded off the track's own name: two runs of this tool
	# produce byte-identical files, which is what lets the output be committed and
	# diffed rather than re-listened to (§19's argument, applied to audio).
	var rng := RandomNumberGenerator.new()
	rng.seed = _fnv1a(name)

	var bright: float = float(spec["bright"])

	# The tape underneath everything, laid down first because it is continuous and
	# has no bars — the one part of the piece that is not notes.
	_write_vinyl(stems["base"], rng)

	# Every note of the piece, decided once. The renderer below plays it and
	# `_write_midi` writes the same list out as a `.mid`, so what a composer opens
	# in a DAW is what the game is playing rather than a transcription of it.
	var score: Array = _score(spec, rng)
	for entry: Variant in score:
		var note: Dictionary = entry
		var at: int = int((float(note["beat"]) * beat) * float(RATE))
		var hz: float = _hz(int(note["midi"]))
		var seconds: float = float(note["ring"]) * beat
		match str(note["part"]):
			"rhodes":
				_rhodes(stems["base"], at, hz, seconds,
					float(note["gain"]), bright, float(note["pan"]))
			"bass":
				_pluck_bass(stems["base"], at, hz, seconds, float(note["gain"]))
			"melody":
				_reed(stems["layer"], at, hz, seconds,
					float(note["gain"]), float(note["pan"]))
			"counter":
				_reed(stems["extra"], at, hz, seconds,
					float(note["gain"]), float(note["pan"]))
	_write_midi(name, spec, score)

	for stem: String in STEMS:
		stems[stem] = _saturate(_soften(_fold_tail(stems[stem])))
	_normalise(stems)

	for stem: String in STEMS:
		_write_wav("%s%s_%s.wav" % [OUT_DIR, name, stem], stems[stem])
	print("%-10s %d bars at %d BPM  ·  %.1f s  ·  3 stems"
		% [name, BARS, int(bpm), float(_total) / float(RATE)])


# --- the score --------------------------------------------------------------------

## Which stem each part belongs to. The reason the whole tool exists is on this
## line: muting a part is muting a *file*, and the three files were played at once.
const PART_STEM := {
	"rhodes": "base", "bass": "base", "melody": "layer", "counter": "extra",
}

## General MIDI programs for the parts, for the `.mid` export. Nobody has to keep
## these — a DAW will put a real Rhodes on the track — but a file that opens
## playing something close to the intention is worth four numbers.
const PART_PROGRAM := {"rhodes": 4, "bass": 32, "melody": 73, "counter": 71}


## Every note in the piece: `{part, beat, midi, ring, gain, pan}`, with `beat`
## counted from the start of the loop and `ring` in beats.
##
## Notes rather than samples, and one list rather than four passes, because two
## different things have to read it — the synthesiser and the MIDI writer — and a
## second walk of the same decisions would drift from the first the moment anything
## random is involved. Both consumers see the same list, or the `.mid` is a lie
## about what the game plays.
func _score(spec: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var root: int = int(spec["root"])
	var chords: Array = spec["chords"]
	for bar: int in range(BARS):
		var chord: Array = chords[(bar / BARS_PER_CHORD) % chords.size()]
		var chord_root: int = root + int(chord[0])
		var quality: String = str(chord[1])
		var at: float = float(bar * BEATS_PER_BAR)
		out.append_array(_comp_notes(at, chord_root, quality, bar, rng))
		out.append_array(_bass_notes(at, chord_root, quality, bar, rng))
		out.append_array(_melody_notes(at, root, chord_root, quality, bar, rng))
		out.append_array(_counter_notes(at, chord_root, quality, bar))
	return out


func _note(part: String, beat: float, midi: int, ring: float,
		gain: float, pan: float = 0.0) -> Dictionary:
	return {"part": part, "beat": beat, "midi": midi, "ring": ring,
		"gain": gain, "pan": pan}


# --- the parts ------------------------------------------------------------------

## The Rhodes, comping the chord: one strike where the chord changes, and a quiet
## answer on the swung "and" of two — but only on the bar that starts a chord, so
## the second bar of every chord is left to ring.
##
## Sparser than the plain jazz comping figure on purpose. What makes a bed feel
## unhurried is the *gaps*: the chord is struck twice as often as the harmony
## changes and no more, which leaves whole bars where nothing is played and the
## tape and the decay are the only things happening.
##
## The voicing has no root in it — the bass has that — and no octave doubling. What
## is left is the third, the seventh and whatever colour the quality carries, which
## is the sound of the *chord* rather than the sound of a keyboard.
func _comp_notes(at: float, chord_root: int, quality: String, bar: int,
		rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var voicing: Array[int] = _voicing(chord_root, quality)
	var opening: bool = bar % BARS_PER_CHORD == 0
	var hits: Array[float] = []
	if opening:
		hits.append(0.0)
		hits.append(_swung(3))
	elif bar % 4 == 3:
		# One late answer every other chord, so the held bar is not always empty.
		hits.append(_swung(5))
	for h: int in range(hits.size()):
		var strong: bool = h == 0 and opening
		for i: int in range(voicing.size()):
			# Notes of a chord are never struck at exactly the same instant by a
			# hand. A few milliseconds of spread is most of what separates a played
			# chord from a triggered one.
			var spread: float = 0.006 * float(i) + rng.randf() * 0.008
			var pan: float = -0.22 + 0.44 * (float(i) / maxf(1.0, float(voicing.size() - 1)))
			out.append(_note("rhodes", at + hits[h] + spread, voicing[i],
				4.6 if strong else 3.0, 0.115 if strong else 0.070, pan))
	return out


## The upright, on one and three, a hair behind the beat — the whole feel of the
## style is the bass being late and the chord being later. Every other bar it walks
## a note into the chord that is coming, which is the difference between a bass
## line and a drone.
func _bass_notes(at: float, chord_root: int, quality: String, bar: int,
		rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var root: int = _in_octave(chord_root, 36, 47)
	# Behind the beat, always. The whole feel of the style is the bass being late
	# and the chord being later.
	var late: float = 0.017
	out.append(_note("bass", at + late, root, 2.4, 0.30))
	# The third beat only on the bar the chord lands on, and a walking note only on
	# the way into the next one. Two notes a bar was a bass *line*; this is a bass
	# leaning on a wall.
	if bar % BARS_PER_CHORD == 0:
		out.append(_note("bass", at + 2.0 + late, root, 1.6, 0.21))
	elif bar % BARS_PER_CHORD == BARS_PER_CHORD - 1:
		var intervals: Array = QUALITIES[quality]
		var step: int = int(intervals[rng.randi_range(1, 2)])
		out.append(_note("bass", at + _swung(7), _in_octave(chord_root + step, 36, 47),
			1.0, 0.17))
	return out


## §15.1's layer: the tune. Three or four notes a bar at most, on the swung grid,
## from the key's pentatonic, with an echo a dotted eighth later.
##
## It never enters on a downbeat. This stem arrives *mid-level*, while the player is
## thinking about a move, and a melody that starts on the "one" announces itself as
## something new; one that starts off the beat is taken as something that was
## already there.
func _melody_notes(at: float, key_root: int, chord_root: int, quality: String,
		bar: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var pool: Array[int] = []
	for step: int in PENTATONIC:
		pool.append(key_root + step + 12)
		pool.append(key_root + step + 24)
	# The chord's own top note, so the line lands on the harmony rather than beside
	# it.
	var intervals: Array = QUALITIES[quality]
	pool.append(_in_octave(chord_root + int(intervals[intervals.size() - 1]), 72, 84))

	for slot: int in range(1, BEATS_PER_BAR * 2):
		if rng.randf() > (0.20 if bar % 2 == 0 else 0.11):
			continue
		var midi: int = pool[rng.randi_range(0, pool.size() - 1)]
		var start: float = at + _swung(slot)
		# Long notes rather than short ones: a held note is a phrase, and four short
		# ones in a bar is a solo. Nobody wants to be soloed at while they think.
		var length: float = 2.6 if rng.randf() < 0.55 else 1.4
		var pan: float = -0.25 + 0.5 * rng.randf()
		out.append(_note("melody", start, midi, length, 0.072, pan))
		# The echo, written as a second quiet note a dotted eighth later rather than
		# run as a delay line: one pass, no state, and it exports to MIDI as what it
		# is — a note somebody played.
		out.append(_note("melody", start + 0.75, midi, length * 0.8, 0.026, -pan))
	return out


## §15.1's third stem, for endless: a second voice under the tune, moving half as
## often. It has to be recognisable on its own — the player is told a fifth goal
## happened by hearing it — and plain enough that it never argues with the melody.
func _counter_notes(at: float, chord_root: int, quality: String, bar: int) -> Array:
	if bar % 2 == 1:
		return []
	var intervals: Array = QUALITIES[quality]
	var third: int = _in_octave(chord_root + int(intervals[1]), 60, 71)
	var seventh: int = _in_octave(chord_root + int(intervals[intervals.size() - 2]), 60, 71)
	return [
		_note("counter", at + _swung(2), third, 2.4, 0.075, -0.3),
		_note("counter", at + _swung(5), seventh, 2.0, 0.060, 0.3),
	]


## The tape the whole thing is playing off: a dull hiss with a slow wobble in it,
## and a crackle every so often.
##
## This is most of what the word "lo-fi" points at, and it costs one pass of noise.
## It is texture rather than percussion — nothing here is on the grid and nothing
## here can be counted — which is what keeps it on the right side of §15.1's "no
## percussion in campaign".
func _write_vinyl(buffer: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var frames: int = buffer.size() / 2
	var smoothed: float = 0.0
	for n: int in range(frames):
		var t: float = float(n) / float(RATE)
		# One pole of smoothing turns white noise into the dull hiss of a room,
		# which is what a record sounds like and white noise does not.
		smoothed = smoothed * 0.86 + (rng.randf() * 2.0 - 1.0) * 0.14
		var hiss: float = smoothed * 0.030 * (0.7 + 0.3 * sin(TAU * 0.13 * t))
		buffer[n * 2] += hiss
		buffer[n * 2 + 1] += hiss * 0.92
	# The crackle: a few hundred short pops over two minutes, placed by the same
	# seeded generator so they land in the same places every run.
	for _i: int in range(int(float(frames) / float(RATE) * 7.0)):
		var at: int = rng.randi_range(0, frames - 200)
		var gain: float = 0.02 + rng.randf() * 0.05
		var pan: float = rng.randf() * 2.0 - 1.0
		for n: int in range(120):
			var v: float = (rng.randf() * 2.0 - 1.0) * exp(-float(n) / 22.0) * gain
			buffer[(at + n) * 2] += v * (0.5 - pan * 0.5)
			buffer[(at + n) * 2 + 1] += v * (0.5 + pan * 0.5)


# --- the instruments --------------------------------------------------------------

## A Rhodes-ish tine: a sine body that decays slowly, a bell partial two octaves up
## that decays four times faster, and a short FM "bark" at the strike.
##
## The bark is the whole trick. A sine under an envelope is a flute; the same sine
## with a fast, high, quickly-collapsing modulation over its first 30 ms is a struck
## metal tine, and the ear names the instrument from that alone.
func _rhodes(buffer: PackedFloat32Array, at: int, hz: float, seconds: float,
		gain: float, bright: float, pan: float) -> void:
	var length: int = int(seconds * float(RATE))
	var frames: int = buffer.size() / 2
	var left: float = gain * sqrt(clampf(0.5 - pan * 0.5, 0.0, 1.0))
	var right: float = gain * sqrt(clampf(0.5 + pan * 0.5, 0.0, 1.0))
	var attack: int = maxi(1, int(0.009 * float(RATE)))

	for n: int in range(length):
		var index: int = at + n
		if index >= frames or index < 0:
			continue
		var t: float = float(n) / float(RATE)
		# Wow and flutter: the pitch drifts by a fraction of a percent, slowly.
		# Inaudible as pitch, audible as *tape*.
		var drift: float = 1.0 + 0.0016 * sin(TAU * 0.6 * t) + 0.0007 * sin(TAU * 5.7 * t)
		var phase: float = TAU * hz * drift * t
		# A softer strike and a longer body than a real Rhodes has: the bark is what
		# says "struck", and past a certain amount it also says "loud".
		var bark: float = exp(-t * 30.0) * (0.55 + bright * 0.8)
		var sample: float = sin(phase + bark * sin(phase * 7.0)) * exp(-t * 0.78)
		sample += sin(phase * 4.0) * exp(-t * 4.2) * (0.06 + 0.10 * bright)
		if n < attack:
			sample *= float(n) / float(attack)
		buffer[index * 2] += sample * left
		buffer[index * 2 + 1] += sample * right


## The upright: a fundamental with a little second harmonic, a fast attack, a
## rounded decay and the thump of a finger on a wound string.
func _pluck_bass(buffer: PackedFloat32Array, at: int, hz: float, seconds: float,
		gain: float) -> void:
	var length: int = int(seconds * float(RATE))
	var frames: int = buffer.size() / 2
	var attack: int = maxi(1, int(0.010 * float(RATE)))
	for n: int in range(length):
		var index: int = at + n
		if index >= frames or index < 0:
			continue
		var t: float = float(n) / float(RATE)
		var env: float = exp(-t * 2.1)
		var sample: float = sin(TAU * hz * t) * env
		sample += sin(TAU * hz * 2.0 * t) * env * 0.16
		sample += sin(TAU * hz * 5.0 * t) * exp(-t * 60.0) * 0.10
		if n < attack:
			sample *= float(n) / float(attack)
		# The one voice kept in the middle: a low note panned off-centre is a low
		# note half the speakers cannot help with.
		buffer[index * 2] += sample * gain * 0.707
		buffer[index * 2 + 1] += sample * gain * 0.707


## The melody voice: breathy and soft-edged, between a flute and a muted horn. A
## slow attack and a little vibrato, so it sits behind the Rhodes rather than
## announcing itself.
func _reed(buffer: PackedFloat32Array, at: int, hz: float, seconds: float,
		gain: float, pan: float) -> void:
	var length: int = int(seconds * float(RATE))
	var frames: int = buffer.size() / 2
	var attack: int = maxi(1, int(0.055 * float(RATE)))
	var release: int = maxi(1, int(float(length) * 0.55))
	var left: float = gain * sqrt(clampf(0.5 - pan * 0.5, 0.0, 1.0))
	var right: float = gain * sqrt(clampf(0.5 + pan * 0.5, 0.0, 1.0))
	for n: int in range(length):
		var index: int = at + n
		if index >= frames or index < 0:
			continue
		var t: float = float(n) / float(RATE)
		var vibrato: float = 1.0 + 0.004 * sin(TAU * 4.8 * t) * minf(1.0, t * 3.0)
		var phase: float = TAU * hz * vibrato * t
		var sample: float = sin(phase) + sin(phase * 2.0) * 0.18 + sin(phase * 3.0) * 0.06
		var env: float = 1.0
		if n < attack:
			env = float(n) / float(attack)
		elif n > length - release:
			env = float(length - n) / float(release)
		buffer[index * 2] += sample * env * left
		buffer[index * 2 + 1] += sample * env * right


# --- the grid and the harmony -------------------------------------------------------

## Where the [param slot]-th eighth of a bar falls, **in beats**, swung.
##
## Beats rather than seconds so one number serves the renderer and the MIDI file: a
## `.mid` carries a tempo and positions in ticks, and swing baked into seconds
## would arrive in a DAW as notes slightly off the grid rather than as a shuffle.
func _swung(slot: int) -> float:
	return float(slot / 2) + (SWING if slot % 2 == 1 else 0.0)


## A rootless voicing: everything above the root, packed into the octave and a half
## where a keyboard's right hand actually sits.
##
## Rootless because the bass is playing the root, and two instruments on the same
## note an octave apart is the muddiest sound in this style.
func _voicing(chord_root: int, quality: String) -> Array[int]:
	var intervals: Array = QUALITIES[quality]
	var out: Array[int] = []
	for i: int in range(1, intervals.size()):
		out.append(_in_octave(chord_root + int(intervals[i]), 58, 76))
	out.sort()
	return out


## Moves [param midi] by octaves until it lands inside [param low]..[param high].
## Voicings are written as intervals and have to be *played* somewhere; this is the
## "somewhere", and it is why a chord never leaps an octave between bars.
func _in_octave(midi: int, low: int, high: int) -> int:
	var out: int = midi
	while out < low:
		out += 12
	while out > high:
		out -= 12
	return out


func _hz(midi: int) -> float:
	return A4 * pow(2.0, float(midi - 69) / 12.0)


# --- the loop, the level and the file ------------------------------------------------

## Folds the ring-out back over the opening bar and returns the loop.
##
## This is what makes the file seamless. The last chord is still sounding when the
## loop point arrives, so the tail past the end is added to the beginning — where
## the next turn of the progression is starting, because the progression divides
## into the bar count. The seam then has nothing to click on, and nothing was
## cross-faded: the music is not ducked at the join, it simply continues.
func _fold_tail(buffer: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_total * 2)
	for i: int in range(_total * 2):
		out[i] = buffer[i]
	for i: int in range(_tail_samples * 2):
		out[i] += buffer[_total * 2 + i]
	return out


## The cassette: one pole of low-pass, per channel, rolling off above about 4 kHz.
##
## The last of the five things that make a bed sound relaxed, and the one that is
## purely a filter: brightness reads as *effort*. A Rhodes with all its top end is
## a Rhodes being played at you; the same take with the air taken off is one being
## played in the next room, which is where a bed belongs.
##
## Applied before the saturation, in the order a tape machine would: the signal is
## dulled on the way to the head, not after it.
func _soften(buffer: PackedFloat32Array) -> PackedFloat32Array:
	# One-pole coefficient for a ~4 kHz corner at this rate.
	var a: float = 1.0 - exp(-TAU * 4000.0 / float(RATE))
	var left: float = 0.0
	var right: float = 0.0
	for i: int in range(0, buffer.size(), 2):
		left += (buffer[i] - left) * a
		right += (buffer[i + 1] - right) * a
		buffer[i] = left
		buffer[i + 1] = right
	return buffer


## Tape, as arithmetic: a gentle `tanh` curve that rounds the peaks and adds a
## little warmth.
##
## Here for a reason that is half sound and half level. A struck piano has a far
## higher crest factor than the pads this replaced — the peaks are several times the
## average — so §15.3's peak ceiling was reached nearly 2 LU before its −16 LUFS
## target and the bed came out quiet. Rounding the peaks is what a tape machine does
## about exactly that, and it is also the sound the style is named after.
##
## Per stem rather than on the sum, because there is no sum to work on: the three
## are separate files. A real multitrack does the same — each part hits its own tape
## — and the stems stay aligned, because this is a memoryless curve applied sample
## by sample.
func _saturate(buffer: PackedFloat32Array) -> PackedFloat32Array:
	var drive: float = 1.6
	var correction: float = 1.0 / tanh(drive)
	for i: int in range(buffer.size()):
		buffer[i] = tanh(buffer[i] * drive) * correction
	return buffer


## Scales all three stems by **one** factor, so the mix is what the score says and
## every bed is as loud as every other.
##
## Normalising each stem to its own level would be the obvious thing and would
## silently rewrite the arrangement: the piano-and-bass `base` and the sparse
## `layer` do not have the same energy, and making them equal would bring the
## melody in at the piano's level. And normalising each *track* to its own peak —
## which the first version did — leaves six beds up to 1.5 LU apart, so changing
## chapter sounds like the volume moved rather than like the scene did.
##
## So: loudness first, measured on the campaign mix, and the peak of all three as a
## ceiling that can only make it quieter.
func _normalise(stems: Dictionary) -> void:
	var samples: int = (stems[STEMS[0]] as PackedFloat32Array).size()
	var base: PackedFloat32Array = stems["base"]
	var layer: PackedFloat32Array = stems["layer"]
	var energy: float = 0.0
	var peak: float = 0.0
	for i: int in range(samples):
		var mix: float = base[i] + layer[i]
		energy += mix * mix
		var all_three: float = mix + (stems["extra"] as PackedFloat32Array)[i]
		peak = maxf(peak, absf(all_three))
	var rms: float = sqrt(energy / float(samples))
	if rms <= 0.0 or peak <= 0.0:
		return

	var scale: float = db_to_linear(MIX_RMS_DB) / rms
	var ceiling: float = db_to_linear(SUM_PEAK_DB)
	if peak * scale > ceiling:
		scale = ceiling / peak
	for stem: String in STEMS:
		var buffer: PackedFloat32Array = stems[stem]
		for i: int in range(buffer.size()):
			buffer[i] *= scale


# --- the MIDI export ----------------------------------------------------------------

## Ticks per quarter note in the exported `.mid`. 480 is what every DAW opens with,
## and it divides the swing cleanly: 0.60 of a beat is 288 ticks exactly, so the
## shuffle arrives as a shuffle rather than as notes a hair off the grid.
const TICKS := 480

## Where the editable copies go. Outside `src/`, so nothing ships them, and
## alongside the hand-drawn level drafts for the same reason: this is the file you
## open when you want to *change* the music rather than play it.
const MIDI_DIR := "res://drafts/music/"

## Writes the piece as a Standard MIDI File — one track per part, at the score's
## own tempo, with the parts named after the stem they belong to.
##
## This is the door out of this file. The synthesiser here is a placeholder and
## always was; the *notes* are the thing worth keeping, and a `.mid` is what a
## person opens in GarageBand, Reaper, Logic or MuseScore to put a real Rhodes on
## the piano track and a real bass under it.
##
## The track names carry the rule that matters, because it is the rule the whole
## arrangement depends on: whatever comes back has to be **one session exported
## three times**, muting `layer` and `extra` for the first file, `extra` for the
## second, nothing for the third. Three separate renders will phase (C-40).
func _write_midi(name: String, spec: Dictionary, score: Array) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MIDI_DIR))
	var parts: Array[String] = ["rhodes", "bass", "melody", "counter"]
	var chunks: Array[PackedByteArray] = [_tempo_track(float(spec["bpm"]))]
	for part: String in parts:
		chunks.append(_part_track(part, score))

	var out := PackedByteArray()
	out.append_array("MThd".to_ascii_buffer())
	_push32(out, 6)
	_push16(out, 1)                  # format 1: parallel tracks, one tempo map
	_push16(out, chunks.size())
	_push16(out, TICKS)
	for chunk: PackedByteArray in chunks:
		out.append_array(chunk)

	var f := FileAccess.open("%s%s.mid" % [MIDI_DIR, name], FileAccess.WRITE)
	if f == null:
		push_error("cannot write the midi for " + name)
		return
	f.store_buffer(out)
	f.close()


## Track 0: the tempo and the time signature, which is where format 1 keeps them.
func _tempo_track(bpm: float) -> PackedByteArray:
	var body := PackedByteArray()
	var microseconds: int = int(60_000_000.0 / bpm)
	body.append_array(PackedByteArray([0x00, 0xFF, 0x51, 0x03]))
	body.append((microseconds >> 16) & 0xFF)
	body.append((microseconds >> 8) & 0xFF)
	body.append(microseconds & 0xFF)
	# 4/4, 24 clocks per beat, 8 demisemiquavers per quarter — the defaults, stated
	# rather than left out, because a DAW that has to guess draws the bars wrong.
	body.append_array(PackedByteArray([0x00, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08]))
	body.append_array(PackedByteArray([0x00, 0xFF, 0x2F, 0x00]))
	return _chunk(body)


## One track per part, named `stem — part` so the muting is obvious on sight.
func _part_track(part: String, score: Array) -> PackedByteArray:
	var channel: int = ["rhodes", "bass", "melody", "counter"].find(part)
	var label: String = "%s — %s" % [PART_STEM[part], part]
	var body := PackedByteArray()
	body.append_array(PackedByteArray([0x00, 0xFF, 0x03]))
	_push_var(body, label.to_utf8_buffer().size())
	body.append_array(label.to_utf8_buffer())
	body.append_array(PackedByteArray([0x00, 0xC0 | channel, int(PART_PROGRAM[part])]))

	# Note on and note off are two events at two times, so the track is built as a
	# flat list and sorted — writing them in note order would put an off after an on
	# that has not happened yet.
	var events: Array = []
	for entry: Variant in score:
		var note: Dictionary = entry
		if str(note["part"]) != part:
			continue
		var on: int = int(round(float(note["beat"]) * float(TICKS)))
		# A ring of several beats is how long the *sound* lasts, which is not how
		# long a key is held. Held notes are capped so a DAW's piano roll reads like
		# a performance rather than like a wall.
		var off: int = on + int(round(minf(float(note["ring"]), 2.0) * float(TICKS)))
		events.append([on, 0x90 | channel, int(note["midi"]), _velocity(float(note["gain"]))])
		events.append([off, 0x80 | channel, int(note["midi"]), 0])
	events.sort_custom(func(a: Array, b: Array) -> bool:
		# Offs before ons at the same tick, so a repeated note is re-struck rather
		# than silenced by the tail of the one before it.
		return a[0] < b[0] if a[0] != b[0] else (a[1] & 0xF0) < (b[1] & 0xF0))

	var last: int = 0
	for entry: Variant in events:
		var e: Array = entry
		_push_var(body, int(e[0]) - last)
		last = int(e[0])
		body.append(int(e[1]))
		body.append(int(e[2]))
		body.append(int(e[3]))
	body.append_array(PackedByteArray([0x00, 0xFF, 0x2F, 0x00]))
	return _chunk(body)


## The renderer's gain as a MIDI velocity. The curve is rough on purpose: what a
## sampled Rhodes does with velocity has nothing to do with what the sine stack
## here does with amplitude, and a composer will re-balance anyway.
func _velocity(gain: float) -> int:
	return clampi(int(round(gain * 620.0)) + 24, 20, 110)


func _chunk(body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array("MTrk".to_ascii_buffer())
	_push32(out, body.size())
	out.append_array(body)
	return out


## MIDI's variable-length quantity: seven bits at a time, high bit set on every
## byte but the last.
func _push_var(into: PackedByteArray, value: int) -> void:
	var v: int = maxi(0, value)
	var stack: Array[int] = [v & 0x7F]
	v >>= 7
	while v > 0:
		stack.push_front((v & 0x7F) | 0x80)
		v >>= 7
	for byte: int in stack:
		into.append(byte)


func _push16(into: PackedByteArray, value: int) -> void:
	into.append((value >> 8) & 0xFF)
	into.append(value & 0xFF)


func _push32(into: PackedByteArray, value: int) -> void:
	into.append((value >> 24) & 0xFF)
	into.append((value >> 16) & 0xFF)
	into.append((value >> 8) & 0xFF)
	into.append(value & 0xFF)


## The same hash the generator seeds off (§19, C-12), so a track's music is as
## reproducible as its levels.
func _fnv1a(text: String) -> int:
	var hash: int = 0x811c9dc5
	for byte: int in text.to_utf8_buffer():
		hash = (hash ^ byte) & 0xffffffff
		hash = (hash * 0x01000193) & 0xffffffff
	return hash


## 44.1 kHz, 16-bit, **stereo** — §15.3 asks for mono SFX and says nothing about the
## music, and a piano with no width is a piano in a phone speaker.
func _write_wav(path: String, samples: PackedFloat32Array) -> void:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		pcm.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32760.0))

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + path)
		return
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + pcm.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)                  # PCM
	f.store_16(2)                  # stereo
	f.store_32(RATE)
	f.store_32(RATE * 4)           # byte rate
	f.store_16(4)                  # block align
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(pcm.size())
	f.store_buffer(pcm)
	f.close()

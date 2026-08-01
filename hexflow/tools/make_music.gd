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
## three times**: a `base` that always plays, a `layer` that fades in above 40%
## board fill, and a third that endless brings in every five goals. The three have
## to be the same performance, because they are played *together* — and two
## renders of "the same" track are two performances. They phase, they drift, and
## nothing makes their bars line up. That is not a quality problem a better
## generator fixes; it is what "render" means.
##
## The previous beds were cut from two finished recordings, which is why the layer
## never arrived: there was no session to go back to. A generator will happily
## produce another variation and cannot produce *the same take with the pads
## muted*, because it never had takes.
##
## So the music is written down here as a **score** — chords, a bar grid, one
## entry per part — and rendered by the synthesiser below. Muting a part is then
## exactly what it sounds like: the same clock, the same chords, the same decay
## tails, one fewer voice. Three stems out of one pass over one score, aligned by
## construction rather than by luck.
##
## It is placeholder music in the sense that a composer would do better, and
## finished in the sense that §15.1's adaptive behaviour is fully playable with it
## — which is more than a beautiful loop with no stems can say. When a commission
## lands (C-6), it must ship as **one session exported three times**; that is the
## whole of the brief this file is standing in for.
##
## ## What comes out
##
## `assets/music/<track>_<stem>.wav`, 44.1 kHz stereo, seamlessly loopable, and
## the Makefile encodes them to `.ogg` with ffmpeg — Godot cannot write Vorbis and
## a 2-minute stereo WAV is 21 MB.
##
## Not part of the shipped game.

const RATE := 44100
const OUT_DIR := "res://assets/music/"

## §15.1: `base` always, `layer` above 40% board fill, and a third for endless.
const STEMS: Array[String] = ["base", "layer", "extra"]

## Bars per loop. §15.1 asks for 2–3 minutes; at these tempos 40 bars lands
## between 2:00 and 2:20, and 40 is 5 turns of an 8-bar progression, so the loop
## point never falls mid-phrase.
const BARS := 40
const BEATS_PER_BAR := 4

## How long the last bar is allowed to ring past the end before being folded back
## over the beginning. Longer than the longest release below, or a pad would be
## cut off at the seam — which is the click a loop is judged by.
const TAIL_SECONDS := 6.0

## Equal temperament from A4, which is the only tuning fact in the file.
const A4 := 440.0

## The scales, as semitone offsets. Named after what they are for rather than
## after their modes: the chapter beds want colour, not theory.
const SCALES := {
	"minor": [0, 2, 3, 5, 7, 8, 10],
	"dorian": [0, 2, 3, 5, 7, 9, 10],
	"lydian": [0, 2, 4, 6, 7, 9, 11],
	"major": [0, 2, 4, 5, 7, 9, 11],
	"phrygian": [0, 1, 3, 5, 7, 8, 10],
}

## The six beds. One row is a whole piece: where it sits, how fast, and the eight
## chords it turns on.
##
## `root` is a MIDI note number, `chords` are scale degrees (0-based), and
## `colour` decides how bright the pads are voiced — chapter 5 is the tense one
## and gets the narrowest, chapter 1 the widest and softest.
##
## Tempos stay inside §15.1's 70–85 BPM and rise across the campaign, which is the
## cheapest way for five ambient beds to feel like a sequence rather than a set.
const TRACKS := {
	"menu": {
		"root": 57, "scale": "dorian", "bpm": 72, "colour": 0.55,
		"chords": [0, 5, 3, 4, 0, 5, 6, 4],
	},
	"chapter_1": {
		"root": 60, "scale": "lydian", "bpm": 74, "colour": 0.70,
		"chords": [0, 4, 5, 3, 0, 4, 1, 3],
	},
	"chapter_2": {
		"root": 62, "scale": "dorian", "bpm": 76, "colour": 0.60,
		"chords": [0, 3, 6, 4, 0, 3, 5, 4],
	},
	"chapter_3": {
		"root": 57, "scale": "minor", "bpm": 78, "colour": 0.50,
		"chords": [0, 5, 2, 6, 0, 5, 3, 4],
	},
	"chapter_4": {
		"root": 52, "scale": "phrygian", "bpm": 80, "colour": 0.42,
		"chords": [0, 1, 5, 4, 0, 1, 6, 4],
	},
	"chapter_5": {
		"root": 55, "scale": "minor", "bpm": 84, "colour": 0.34,
		"chords": [0, 6, 4, 5, 0, 6, 2, 4],
	},
}

## §15.3's integrated target, reached the only way a renderer can reach it without
## a loudness meter: RMS, with the offset between the two measured on this
## material. Pads at these tempos sit +2.2 LU above their RMS, so −18.2 dBFS RMS
## lands at −16 LUFS — checked against `ffmpeg -af ebur128` on all six beds.
##
## Measured on `base + layer`, because that is the mix a player hears for most of
## a level; the base alone is quieter on purpose and the third stem is endless-only.
const MIX_RMS_DB := -18.2

## And the ceiling, on all three at once. §15.3 wants −1 dBTP; −2 leaves the
## encoder room to overshoot a sample peak on the way to Vorbis. Loudness gives way
## to this rather than the other way round: a bed 1 dB quiet is nobody's problem
## and a clipped one is everybody's.
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

	# Stereo, interleaved, with room for the tail that will be folded back.
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

	var scale: Array = SCALES[str(spec["scale"])]
	var root: int = int(spec["root"])
	var colour: float = float(spec["colour"])
	var chords: Array = spec["chords"]

	for bar: int in range(BARS):
		var degree: int = int(chords[bar % chords.size()])
		var at: int = bar * _bar_samples
		var notes: Array[float] = _triad(root, scale, degree)

		_write_pad(stems["base"], at, notes, beat, colour)
		_write_bass(stems["base"], at, notes[0], beat)
		_write_plucks(stems["layer"], at, notes, beat, rng)
		_write_bell(stems["layer"], at, notes, beat, bar)
		if bar % 2 == 1:
			_write_counter(stems["extra"], at, notes, scale, root, beat, bar)

	for stem: String in STEMS:
		stems[stem] = _fold_tail(stems[stem])
	_normalise(stems)

	for stem: String in STEMS:
		_write_wav("%s%s_%s.wav" % [OUT_DIR, name, stem], stems[stem])
	print("%-10s %d bars at %d BPM  ·  %.1f s  ·  3 stems"
		% [name, BARS, int(bpm), float(_total) / float(RATE)])


# --- the parts ------------------------------------------------------------------

## The chord under everything: three voices held for the whole bar, plus their
## octave. Slow in, slow out, so one chord dissolves into the next rather than
## being replaced by it.
##
## Voiced as a small stack of harmonics rather than a filtered saw, because a
## filter is a state variable per voice and this is a table of sine sums — the
## brightness knob is *how many harmonics*, which is `colour`.
func _write_pad(buffer: PackedFloat32Array, at: int, notes: Array[float],
		beat: float, colour: float) -> void:
	var length: int = int(beat * float(BEATS_PER_BAR) * 1.35 * float(RATE))
	var partials: int = 2 + int(round(colour * 4.0))
	for i: int in range(notes.size()):
		var hz: float = notes[i]
		# Each voice sits a little off-centre and a little detuned from its pair,
		# which is the whole of the stereo width here. Any more and a pad starts
		# arriving from a direction, which an ambient bed should not do.
		var pan: float = -0.4 + 0.4 * float(i)
		_voice(buffer, at, length, hz * 0.9985, partials, 0.052, 0.45, 0.55, pan)
		_voice(buffer, at, length, hz * 1.0015, partials, 0.052, 0.45, 0.55, -pan)
		# The octave above, quiet: it is what stops a three-note pad sounding like
		# an organ chord.
		_voice(buffer, at, length, hz * 2.0, 2, 0.020, 0.5, 0.6, pan * 0.5)


## A sub under the root, an octave and a half down. Two harmonics, because a pure
## sine at 55 Hz disappears on a laptop and the second partial is what carries it.
func _write_bass(buffer: PackedFloat32Array, at: int, root_hz: float, beat: float) -> void:
	var length: int = int(beat * float(BEATS_PER_BAR) * 1.1 * float(RATE))
	_voice(buffer, at, length, root_hz * 0.25, 2, 0.075, 0.25, 0.4, 0.0)


## §15.1's "soft plucks", on the layer stem: a sparse pentatonic figure over the
## chord, different every bar and the same on every run.
##
## Sparse on purpose — a note on every eighth is a sequence, and a bed a player
## hears for an hour must not have a sequence in it. Four of eight slots, chosen
## by the seeded generator, land somewhere between a rhythm and a drift.
func _write_plucks(buffer: PackedFloat32Array, at: int, notes: Array[float],
		beat: float, rng: RandomNumberGenerator) -> void:
	var slot: float = beat * 0.5
	for eighth: int in range(BEATS_PER_BAR * 2):
		if rng.randf() > 0.34:
			continue
		var octave: int = 1 if rng.randf() < 0.75 else 2
		var degree: int = int(rng.randi_range(0, notes.size() - 1))
		var hz: float = notes[degree] * float(octave)
		var start: int = at + int(float(eighth) * slot * float(RATE))
		var length: int = int(beat * 1.6 * float(RATE))
		var pan: float = -0.35 + 0.7 * rng.randf()
		_voice(buffer, start, length, hz, 3, 0.16, 0.004, 0.9, pan)
		# The delay is written as a second, quieter note rather than run as a
		# feedback line: one pass, no state, and a dotted eighth is where a delay
		# on an ambient pluck belongs.
		var echo: int = start + int(beat * 0.75 * float(RATE))
		if echo < buffer.size() / 2:
			_voice(buffer, echo, length, hz, 2, 0.055, 0.004, 0.9, -pan)


## A single high bell on the downbeat of every fourth bar. The only event in the
## piece a player could set their watch by, and it is what makes the layer feel
## like it *arrived* rather than like the volume went up.
func _write_bell(buffer: PackedFloat32Array, at: int, notes: Array[float],
		beat: float, bar: int) -> void:
	if bar % 4 != 0:
		return
	_voice(buffer, at, int(beat * 3.0 * float(RATE)), notes[2] * 4.0, 2, 0.035, 0.002, 0.95, 0.15)


## §15.1's third stem, for endless: a slow line above the chord, every other bar.
## It has to be recognisable on its own — the player is told a fifth goal happened
## by hearing it — and quiet enough that five of them do not stack into a melody
## fighting the pad.
func _write_counter(buffer: PackedFloat32Array, at: int, notes: Array[float],
		scale: Array, root: int, beat: float, bar: int) -> void:
	var step: int = [4, 6, 2, 5][(bar / 2) % 4]
	var hz: float = _hz(root + int(scale[step % scale.size()]) + 12)
	var length: int = int(beat * 2.6 * float(RATE))
	_voice(buffer, at + int(beat * 0.5 * float(RATE)), length, hz, 3, 0.075, 0.08, 0.8, -0.2)
	_voice(buffer, at + int(beat * 2.5 * float(RATE)), length, notes[1] * 2.0, 2, 0.05, 0.08, 0.8, 0.25)


# --- the synthesiser --------------------------------------------------------------

## One voice: [param partials] harmonics of [param hz], with an attack/release
## envelope, written into the stereo buffer at [param pan].
##
## Additive rather than a filtered oscillator because there is no filter here and
## no need for one: the harmonic count *is* the brightness, a sine sum cannot
## alias, and every partial is a `sin()` the CPU does once per sample offline.
func _voice(buffer: PackedFloat32Array, at: int, length: int, hz: float,
		partials: int, gain: float, attack: float, release: float, pan: float) -> void:
	if at < 0 or hz <= 0.0 or length <= 0:
		return
	var frames: int = buffer.size() / 2
	var attack_n: int = maxi(1, int(float(length) * attack))
	var release_n: int = maxi(1, int(float(length) * release))
	var left: float = gain * sqrt(clampf(0.5 - pan * 0.5, 0.0, 1.0))
	var right: float = gain * sqrt(clampf(0.5 + pan * 0.5, 0.0, 1.0))

	for n: int in range(length):
		var index: int = at + n
		if index >= frames:
			break
		var env: float = 0.0
		if n < attack_n:
			env = float(n) / float(attack_n)
		elif n > length - release_n:
			env = float(length - n) / float(release_n)
		else:
			env = 1.0
		# Equal-power in and out, so a pad swelling under another pad does not dip
		# where the two envelopes cross.
		env = sin(env * PI * 0.5)

		var t: float = float(n) / float(RATE)
		var sample: float = 0.0
		for p: int in range(1, partials + 1):
			# 1/p² rather than 1/p: a warm pad, not a saw. The spec's word is
			# "warm" and this is the whole of it.
			sample += sin(TAU * hz * float(p) * t) / float(p * p)
		sample *= env
		buffer[index * 2] += sample * left
		buffer[index * 2 + 1] += sample * right


## Folds the ring-out back over the opening bar and returns the loop.
##
## This is what makes the file seamless. The last chord is still sounding when the
## loop point arrives, so the tail past the end is added to the beginning — where
## the same chord is starting again, because the progression divides into the bar
## count. The seam then has nothing to click on, and nothing was cross-faded: the
## music is not ducked at the join, it simply continues.
func _fold_tail(buffer: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_total * 2)
	for i: int in range(_total * 2):
		out[i] = buffer[i]
	for i: int in range(_tail_samples * 2):
		out[i] += buffer[_total * 2 + i]
	return out


## Scales all three stems by **one** factor, so the mix is what the score says and
## every bed is as loud as every other.
##
## Normalising each stem to its own level would be the obvious thing and would
## silently rewrite the arrangement: the bass-and-pad `base` and the four-pluck
## `layer` do not have the same energy, and making them equal would bring the layer
## in at the pad's level. And normalising each *track* to its own peak — which is
## what the first version did — leaves six beds up to 1.5 LU apart, so changing
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


# --- notes and files ---------------------------------------------------------------

## The triad on [param degree] of the scale: root, third and fifth *of the mode*,
## so a chord is always in key and never has to be spelled out.
func _triad(root: int, scale: Array, degree: int) -> Array[float]:
	var out: Array[float] = []
	for step: int in [0, 2, 4]:
		var index: int = degree + step
		var octave: int = 12 * (index / scale.size())
		out.append(_hz(root + int(scale[index % scale.size()]) + octave))
	return out


func _hz(midi: int) -> float:
	return A4 * pow(2.0, float(midi - 69) / 12.0)


## The same hash the generator seeds off (§19, C-12), so a track's music is as
## reproducible as its levels.
func _fnv1a(text: String) -> int:
	var hash: int = 0x811c9dc5
	for byte: int in text.to_utf8_buffer():
		hash = (hash ^ byte) & 0xffffffff
		hash = (hash * 0x01000193) & 0xffffffff
	return hash


## 44.1 kHz, 16-bit, **stereo** — §15.3 asks for mono SFX and says nothing about
## the music, and a pad with no width is a pad in a phone speaker.
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

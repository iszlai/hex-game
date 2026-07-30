extends SceneTree
## Offline authoring step: renders §15.2's sixteen sound effects to
## `assets/sfx/*.wav`. Run it with `make sfx`; the output is committed.
##
## Synthesised rather than sourced, for the same reason §13.1 draws the board
## procedurally: no external artist, no licence to track, and every sound is a few
## numbers in a table that can be retuned without a download. They are placeholders
## in the sense that a composer would do better, and finished in the sense that the
## game is fully playable and fully audible with them.
##
## Everything is mono, 22.05 kHz, 16-bit — §15.3 asks for mono SFX, and a UI tick
## has nothing above 10 kHz worth keeping.
##
## Not part of the shipped game.

const RATE := 22050
const OUT_DIR := "res://assets/sfx/"

## §15.2's table, one row per ID, with the character column turned into numbers.
##
##   wave   sine | tri | noise | fm
##   f0/f1  start and end frequency in Hz (a sweep when they differ)
##   ms     length
##   atk    attack as a fraction of the length; the rest decays
##   gain   peak amplitude, headroom left for §15.3's -1 dBTP ceiling
##   chord  extra intervals in semitones, sounded together
const SFX := {
	# Short soft tick, 40 ms.
	"ui.move": {"wave": "sine", "f0": 1320.0, "f1": 1180.0, "ms": 40, "atk": 0.05, "gain": 0.22},
	# Warm two-tone blip: a fifth, up.
	"ui.confirm": {"wave": "tri", "f0": 587.0, "f1": 880.0, "ms": 120, "atk": 0.04, "gain": 0.34},
	# Downward blip.
	"ui.back": {"wave": "tri", "f0": 660.0, "f1": 440.0, "ms": 120, "atk": 0.04, "gain": 0.30},
	# Muted low thud, "no harshness" — so a sine, not noise.
	"ui.reject": {"wave": "sine", "f0": 165.0, "f1": 110.0, "ms": 180, "atk": 0.02, "gain": 0.38},
	# Glass/marimba: a bright partial over the fundamental. Pitched at playback, so
	# this is the root of the pentatonic scale rather than one note of it.
	"place.note": {"wave": "fm", "f0": 523.0, "f1": 523.0, "ms": 420, "atk": 0.005,
		"gain": 0.40, "chord": [12, 19]},
	# Soft airy swell, under the note.
	"place.connector": {"wave": "noise", "f0": 900.0, "f1": 1600.0, "ms": 200, "atk": 0.5,
		"gain": 0.10},
	# Light paper/glass slide.
	"tile.advance": {"wave": "noise", "f0": 2400.0, "f1": 1400.0, "ms": 110, "atk": 0.08,
		"gain": 0.13},
	# Short descending sweep.
	"tile.discard": {"wave": "tri", "f0": 720.0, "f1": 300.0, "ms": 220, "atk": 0.02, "gain": 0.30},
	# Airy upward whoosh — deliberately NOT a failure sound (§15.2 says so twice).
	"tile.autoskip": {"wave": "noise", "f0": 700.0, "f1": 2600.0, "ms": 260, "atk": 0.45,
		"gain": 0.16},
	# Resolving major chord + shimmer.
	"goal.reach": {"wave": "sine", "f0": 523.0, "f1": 523.0, "ms": 620, "atk": 0.01,
		"gain": 0.34, "chord": [4, 7, 12]},
	# Four-note motif. The sweep carries it; the chord gives it a body.
	"level.win": {"wave": "tri", "f0": 523.0, "f1": 1046.0, "ms": 900, "atk": 0.02,
		"gain": 0.36, "chord": [7]},
	# Single low sustained tone, no sting.
	"level.dead": {"wave": "sine", "f0": 98.0, "f1": 92.0, "ms": 900, "atk": 0.12, "gain": 0.30},
	# Rising chime.
	"star.award": {"wave": "fm", "f0": 880.0, "f1": 1320.0, "ms": 320, "atk": 0.005,
		"gain": 0.32, "chord": [12]},
	# Bright bell.
	"wild.pickup": {"wave": "fm", "f0": 1174.0, "f1": 1174.0, "ms": 480, "atk": 0.003,
		"gain": 0.34, "chord": [12, 19]},
	# Reverse-reverb pop: the attack *is* the reverse, so nearly all of it.
	"portal.link": {"wave": "noise", "f0": 400.0, "f1": 2200.0, "ms": 340, "atk": 0.9,
		"gain": 0.20},
	# Two-stage mechanical click.
	"gate.open": {"wave": "noise", "f0": 1800.0, "f1": 900.0, "ms": 150, "atk": 0.02,
		"gain": 0.22, "double": 0.55},
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var written := 0
	for id: Variant in SFX:
		var samples: PackedFloat32Array = _render(SFX[id] as Dictionary)
		var path: String = OUT_DIR + str(id).replace(".", "_") + ".wav"
		_write_wav(path, samples)
		written += 1
		print("  %-18s %5d ms  %s" % [id, int(SFX[id]["ms"]), path])
	print("wrote %d of §15.2's 16 effects" % written)
	if written != 16:
		push_error("§15.2 names 16 effects; the table has %d" % written)
	quit()


## One effect, as floats in -1 … 1.
func _render(spec: Dictionary) -> PackedFloat32Array:
	var count: int = int(float(RATE) * float(spec["ms"]) / 1000.0)
	var out := PackedFloat32Array()
	out.resize(count)
	var intervals: Array = [0]
	intervals.append_array(spec.get("chord", []) as Array)
	var rng := RandomNumberGenerator.new()
	# Seeded: §19's determinism applies to the assets too, so re-running this
	# produces byte-identical files rather than a diff every time.
	rng.seed = hash(str(spec))

	for i: int in range(count):
		var t: float = float(i) / float(count)
		var phase_hz: float = lerpf(float(spec["f0"]), float(spec["f1"]), t)
		var value := 0.0
		for semitones: Variant in intervals:
			var hz: float = phase_hz * pow(2.0, float(semitones) / 12.0)
			value += _wave(str(spec["wave"]), float(i) / float(RATE), hz, rng)
		value /= float(intervals.size())
		out[i] = value * _envelope(t, float(spec["atk"])) * float(spec["gain"])

	if spec.has("double"):
		# §15.2's "two-stage" click: the same shape again, quieter, part-way in.
		var offset: int = int(float(count) * float(spec["double"]))
		for i: int in range(offset, count):
			out[i] = clampf(out[i] + out[i - offset] * 0.6, -1.0, 1.0)
	return out


func _wave(kind: String, seconds: float, hz: float, rng: RandomNumberGenerator) -> float:
	match kind:
		"sine":
			return sin(TAU * hz * seconds)
		"tri":
			return asin(sin(TAU * hz * seconds)) * (2.0 / PI)
		"fm":
			# A bright inharmonic partial decaying faster than the fundamental is
			# what makes a struck-glass timbre rather than an organ one.
			return sin(TAU * hz * seconds + 2.4 * sin(TAU * hz * 2.76 * seconds))
		_:
			# Band-passed noise, roughly: noise shaped by a resonant tone.
			return rng.randf_range(-1.0, 1.0) * 0.6 + sin(TAU * hz * seconds) * 0.4


## Attack then exponential decay. [param attack] is a fraction of the whole length,
## so a 0.9 attack is §15.2's reverse-reverb pop and a 0.005 one is a struck bell.
func _envelope(t: float, attack: float) -> float:
	if t < attack:
		return t / maxf(attack, 0.0001)
	var fell: float = (t - attack) / maxf(1.0 - attack, 0.0001)
	return exp(-4.0 * fell) * (1.0 - fell * 0.15)


## A minimal RIFF/WAVE file: 16-bit signed mono. Written by hand because the engine
## exports audio but does not author it, and a committed `.wav` imports as an
## `AudioStreamWAV` with no import settings to get wrong.
func _write_wav(path: String, samples: PackedFloat32Array) -> void:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		var v: int = int(clampf(samples[i], -1.0, 1.0) * 32760.0)
		pcm.encode_s16(i * 2, v)

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + path)
		return
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + pcm.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)                 # PCM header size
	f.store_16(1)                  # format: PCM
	f.store_16(1)                  # channels: mono (§15.3)
	f.store_32(RATE)
	f.store_32(RATE * 2)           # byte rate
	f.store_16(2)                  # block align
	f.store_16(16)                 # bits per sample
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(pcm.size())
	f.store_buffer(pcm)
	f.close()

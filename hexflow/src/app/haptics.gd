## The §11.5 haptics table, scaled by the Settings slider.
##
## A `Node` rather than a static helper because the patterns are *sequences* —
## "2 × 6 ms, 40 ms apart" needs a clock — but deliberately **not** an autoload:
## §16.5 fixes the singleton list at six, so the screen that produces the events
## owns one of these as a child.
##
## Processing is switched off while idle, so an idle board costs nothing per frame
## (C4). Every pattern is also recorded in [member history], which is what lets a
## headless test assert the table without a controller in the room.
class_name Haptics
extends Node

## Amplitudes for the table's "weak" and "medium". §11.5 names no strong pattern:
## a puzzle game that jolts the player's hands is a puzzle game they put down.
const WEAK := 0.35
const MEDIUM := 0.7

## §11.5, verbatim. Each step is `[milliseconds, weak, strong]`; a step with both
## amplitudes at zero is a silence, which is how "40 ms apart" is expressed.
##
## Two readings the spec leaves open, taken here: "40 ms apart" is a 40 ms gap
## between pulses, and the dead-state triple uses that same gap so the two
## rejection-flavoured patterns feel related.
const PATTERNS := {
	"cursor_move": [[8, WEAK, 0.0]],
	"cursor_reject": [[6, WEAK, 0.0], [40, 0.0, 0.0], [6, WEAK, 0.0]],
	"commit": [[18, 0.0, MEDIUM], [60, WEAK, 0.0]],
	"auto_discard": [[12, WEAK, 0.0]],
	"goal": [
		[40, 0.0, MEDIUM],
		[40, 0.0, MEDIUM * 0.66],
		[40, 0.0, MEDIUM * 0.33],
		[40, WEAK * 0.5, 0.0],
	],
	"dead": [
		[20, 0.0, MEDIUM],
		[40, 0.0, 0.0],
		[20, 0.0, MEDIUM],
		[40, 0.0, 0.0],
		[20, 0.0, MEDIUM],
	],
}

## Pattern ids played this session, oldest first. Tests read this; nothing else
## should depend on it.
var history: Array[String] = []

var _queue: Array = []
var _wait: float = 0.0


func _ready() -> void:
	set_process(false)


## Strength from the Settings slider (§11.5): 0–100%, default 70, off at 0.
func strength() -> float:
	return clampf(float(SettingsService.get_value("haptics")) / 100.0, 0.0, 1.0)


## Plays a §11.5 pattern. Silently ignores an unknown id rather than crashing a
## player's session over a feedback cue.
func play(id: String) -> void:
	if not PATTERNS.has(id):
		push_warning("no haptic pattern named %s" % id)
		return
	if strength() <= 0.0:
		return
	history.append(id)
	_queue = (PATTERNS[id] as Array).duplicate()
	_wait = 0.0
	_advance()


func pending_steps() -> int:
	return _queue.size()


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_advance()


func _advance() -> void:
	if _queue.is_empty():
		set_process(false)
		_stop()
		return

	var step: Array = _queue.pop_front()
	var seconds := float(step[0]) / 1000.0
	var scale := strength()
	var weak := float(step[1]) * scale
	var strong := float(step[2]) * scale
	_wait = seconds
	set_process(true)

	if weak <= 0.0 and strong <= 0.0:
		_stop()
		return
	for device: int in Input.get_connected_joypads():
		Input.start_joy_vibration(device, weak, strong, seconds)


func _stop() -> void:
	for device: int in Input.get_connected_joypads():
		Input.stop_joy_vibration(device)

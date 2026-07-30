## A press-and-hold gate. §11.3: "Nothing destructive on a single press."
##
## Event-driven rather than polling `Input`, so an injected [InputEvent] in a test
## exercises exactly the path a player's thumb does — a hold that only works
## against the live `Input` singleton is a hold no test can prove.
##
## Exactly one hold is in flight at a time. A new press replaces an older one,
## which is also what a player expects when they roll off one button onto another.
## That single-slot design is deliberate: [method tick] runs every frame while a
## hold is live and must not allocate (C4).
##
## Not a Node and not an autoload — the screen that reads the input owns one.
class_name HoldGesture
extends RefCounted

## The hold reached its threshold. Fired once; continuing to hold does not repeat.
signal completed(action: String)

## Released, or displaced by another press, before reaching the threshold.
signal cancelled(action: String)

## The action being held, or "" when idle.
var action: String = ""
var elapsed: float = 0.0
var threshold: float = 0.0


func active() -> bool:
	return action != ""


## 0.0 → 1.0 across the hold, for a progress indicator.
func ratio() -> float:
	if threshold <= 0.0:
		return 0.0
	return clampf(elapsed / threshold, 0.0, 1.0)


func begin(p_action: String, seconds: float) -> void:
	if seconds <= 0.0:
		return
	if action != "" and action != p_action:
		cancelled.emit(action)
	action = p_action
	threshold = seconds
	elapsed = 0.0


## Aborts [param p_action] if it is the one in flight. Returns whether a live
## hold was actually cancelled — a caller distinguishes "released early" from
## "already completed" by that answer, which is how a tap on Select toggles the
## legend while a 1 s hold restarts instead (§11.3).
func cancel(p_action: String) -> bool:
	if action == "" or action != p_action:
		return false
	var was := action
	_clear()
	cancelled.emit(was)
	return true


func tick(delta: float) -> void:
	if action == "":
		return
	elapsed += delta
	if elapsed < threshold:
		return
	var done := action
	_clear()
	completed.emit(done)


func _clear() -> void:
	action = ""
	elapsed = 0.0
	threshold = 0.0

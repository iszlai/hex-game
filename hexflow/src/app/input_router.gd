## Cursor navigation over a hex lattice (§11.2).
##
## The hard problem is directional input on six-way geometry. Two schemes ship;
## snap is the default because it makes every press land on a legal move.
##
## Deliberately not an autoload — §16.5 fixes the singleton list at six. The level
## scene owns one of these and feeds it the current candidates and their screen
## positions, so the logic stays testable without a scene tree.
class_name InputRouter
extends RefCounted

enum Mode { SNAP, FREE }

## A directional press only moves the cursor to a candidate within this cone of
## the input vector; outside it, the cursor holds and a rejection tick plays.
const ACCEPTANCE_CONE_DEG := 75.0

## Three cone rejections in a row surfaces the bumper-cycling hint (§11.2).
const REJECTIONS_BEFORE_HINT := 3

## Auto-repeat for a **held analogue stick**, in milliseconds: how long it must be
## held before it starts repeating, and how fast it repeats after that.
##
## A stick is not a button. It emits a fresh event on every change in its axis, and
## a thumb resting past the deadzone changes it constantly — so one flick was
## landing three or four moves and the cursor shot across the board. A D-pad press
## and a key press are discrete and are left alone; this applies only where the
## input is continuous, which is why [method move] has to be told which it was.
##
## The shape is a keyboard's, because that is the behaviour a thumb already
## expects: the first move is immediate, then a pause, then a steady rate.
const STICK_REPEAT_FIRST_MS := 340
const STICK_REPEAT_MS := 130

## How closely a new direction must match the last for it to count as the *same*
## hold rather than a fresh push. A thumb on a stick wanders; a cone stops that
## wander restarting the repeat clock and firing early.
const STICK_SAME_DIRECTION := 0.87

var _stick_last_ms: int = 0
var _stick_last_dir: Vector2 = Vector2.ZERO
var _stick_repeating: bool = false

signal cursor_moved(cell: Vector3i)
signal cursor_rejected()
signal cycling_hint_wanted()

var mode: Mode = Mode.SNAP
var cursor: Vector3i = Vector3i.ZERO
var has_cursor: bool = false

var _candidates: Array[Vector3i] = []
var _positions: Dictionary = {}   # Vector3i -> Vector2
var _center: Vector2 = Vector2.ZERO
var _rejections: int = 0


## Feeds the router the current legal targets and where they sit on screen.
## Keeps the cursor if it is still legal, otherwise snaps to the candidate
## nearest the board centre so the opening frame always has a valid focus.
func set_candidates(targets: Array[Vector3i], positions: Dictionary, center: Vector2) -> void:
	_candidates = _sort_clockwise(targets, positions, center)
	_positions = positions
	_center = center
	if _candidates.is_empty():
		has_cursor = false
		return
	if not has_cursor or not _candidates.has(cursor):
		cursor = _candidates[0]
		has_cursor = true
		cursor_moved.emit(cursor)


func candidates() -> Array[Vector3i]:
	return _candidates


## Whether a held stick has waited long enough to move again.
func _stick_may_move(input: Vector2) -> bool:
	var now: int = Time.get_ticks_msec()
	var dir: Vector2 = input.normalized()
	var elapsed: int = now - _stick_last_ms
	# Let go for longer than the first delay and it is a new push, whichever way it
	# points — otherwise a player who pauses and pushes again waits twice.
	var fresh: bool = elapsed > STICK_REPEAT_FIRST_MS \
		or dir.dot(_stick_last_dir) < STICK_SAME_DIRECTION
	if not fresh:
		if elapsed < (STICK_REPEAT_MS if _stick_repeating else STICK_REPEAT_FIRST_MS):
			return false
		_stick_repeating = true
	else:
		_stick_repeating = false
	_stick_last_ms = now
	_stick_last_dir = dir
	return true


## Directional input. Picks the candidate whose screen bearing from the cursor
## best matches [param input], preferring the nearest on ties.
##
## [param analogue] says the input came from a stick rather than from a D-pad or a
## key. Only then is it rate-limited — see [constant STICK_REPEAT_FIRST_MS]. It
## defaults to false so that a caller which does not care, and every test that
## drives this directly, behaves exactly as it always did.
func move(input: Vector2, analogue: bool = false) -> bool:
	if _candidates.is_empty() or input.length() < 0.01:
		return false
	if analogue and not _stick_may_move(input):
		return false
	if mode == Mode.FREE:
		return _move_free(input)

	var want := input.normalized()
	var best: Vector3i = cursor
	var best_score: float = -1.0
	var best_distance: float = INF
	var from: Vector2 = _positions.get(cursor, _center)

	for c: Vector3i in _candidates:
		if c == cursor:
			continue
		var to: Vector2 = _positions.get(c, _center)
		var delta := to - from
		if delta.length() < 0.01:
			continue
		var dot := want.dot(delta.normalized())
		if dot < cos(deg_to_rad(ACCEPTANCE_CONE_DEG)):
			continue
		var d := delta.length()
		if dot > best_score or (is_equal_approx(dot, best_score) and d < best_distance):
			best_score = dot
			best_distance = d
			best = c

	if best == cursor:
		_reject()
		return false
	_rejections = 0
	cursor = best
	cursor_moved.emit(cursor)
	return true


## `L1`/`R1`. Steps through the candidates in clockwise bearing order from the
## board centre. Always available in both schemes and guaranteed to reach every
## legal target, which makes it the reliable fallback when the cone frustrates.
func cycle(step: int) -> void:
	if _candidates.is_empty():
		return
	var i: int = _candidates.find(cursor)
	if i < 0:
		i = 0
	else:
		i = posmod(i + step, _candidates.size())
	cursor = _candidates[i]
	has_cursor = true
	_rejections = 0
	cursor_moved.emit(cursor)


## Mouse and touch. Returns whether the cell under [param cell] is selectable.
func point_at(cell: Vector3i) -> bool:
	if not _candidates.has(cell):
		return false
	cursor = cell
	has_cursor = true
	cursor_moved.emit(cursor)
	return true


func _move_free(input: Vector2) -> bool:
	# Free cursor moves over every board cell, not just the candidates; the level
	# scene supplies the full cell set through `_positions`.
	var want := input.normalized()
	var from: Vector2 = _positions.get(cursor, _center)
	var best: Vector3i = cursor
	var best_distance: float = INF
	for key: Variant in _positions.keys():
		var c: Vector3i = key
		if c == cursor:
			continue
		var delta: Vector2 = (_positions[c] as Vector2) - from
		if delta.length() < 0.01 or want.dot(delta.normalized()) < cos(deg_to_rad(ACCEPTANCE_CONE_DEG)):
			continue
		if delta.length() < best_distance:
			best_distance = delta.length()
			best = c
	if best == cursor:
		_reject()
		return false
	cursor = best
	cursor_moved.emit(cursor)
	return true


func _reject() -> void:
	_rejections += 1
	cursor_rejected.emit()
	if _rejections >= REJECTIONS_BEFORE_HINT:
		_rejections = 0
		cycling_hint_wanted.emit()


## Clockwise by screen bearing from the board centre, so cycling reads as a
## rotation rather than an arbitrary order. Ties break on cube order for
## determinism (§19).
static func _sort_clockwise(
	targets: Array[Vector3i], positions: Dictionary, center: Vector2
) -> Array[Vector3i]:
	var out: Array[Vector3i] = targets.duplicate()
	out.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		var pa: Vector2 = (positions.get(a, center) as Vector2) - center
		var pb: Vector2 = (positions.get(b, center) as Vector2) - center
		var aa := fposmod(pa.angle(), TAU)
		var ab := fposmod(pb.angle(), TAU)
		if not is_equal_approx(aa, ab):
			return aa < ab
		return pa.length_squared() < pb.length_squared())
	return out

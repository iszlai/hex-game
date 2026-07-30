## One entry of the undo history (§5.5, §5.9).
##
## A move records everything needed to invert itself exactly: the cells it added,
## how many edges it appended, and the scalar counters as they were *before* the
## turn began. `stream_index_before` is the index before that turn's run of free
## auto-discards, not the index of the placed tile — which is what makes undo
## rewind through auto-discards as §5.9 requires.
class_name Move
extends RefCounted

enum Kind { PLACE, DISCARD, WILD }

var kind: Kind = Kind.PLACE
var target: Vector3i = Vector3i.ZERO
var anchor: Vector3i = Vector3i.ZERO
var dir: int = Direction.NONE

## Cells this move joined to the path: the target, plus a portal twin if one fired.
var added: Array[Vector3i] = []
var edges_added: int = 0

var stream_index_before: int = 0
var discards_before: int = 0
var wild_before: int = 0
var placements_before: int = 0


func _to_string() -> String:
	match kind:
		Kind.DISCARD:
			return "Move(DISCARD @stream %d)" % stream_index_before
		Kind.WILD:
			return "Move(WILD %v <- %v)" % [target, anchor]
		_:
			return "Move(PLACE %v <- %v %s)" % [target, anchor, Direction.name_of(dir)]

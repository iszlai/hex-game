## The mutable run state (§5.1) and the only place the rules are applied.
##
## Holds no engine dependency beyond [RefCounted]: no nodes, no signals, no
## [Input]. The view learns what happened by draining [member events] after each
## call — facts, never intents (§16.2).
##
## `path` is an invariant tree rooted at `start`: every placement attaches exactly
## one new cell (plus, for a portal, its twin) to a cell already in the path.
## Connectivity therefore never needs recomputing, and winning is a counter check.
class_name GameState
extends RefCounted

enum Status { PLAYING, WON, DEAD }

## Event type keys pushed onto [member events].
const EV_PLACED := "placed"
const EV_PORTAL := "portal_linked"
const EV_WILD_GAINED := "wild_gained"
const EV_WILD_SPENT := "wild_spent"
const EV_DISCARDED := "discarded"
const EV_AUTO_SKIPPED := "auto_skipped"
const EV_GOAL_REACHED := "goal_reached"
const EV_WON := "won"
const EV_DEAD := "dead"

## Why a run ended (§5.8). There are four ways to reach `DEAD` and they ask the
## player for different things — a board that is boxed in wants an undo, a queue
## that has run dry wants a restart — so the banner cannot say one sentence for all
## of them without pointing at the wrong half of the screen. Integers, so §19's
## ban on floats and engine types in `src/core/` is untouched.
enum Dead { NONE, BUDGET, UNREACHABLE_GOAL, PATH_FROZEN, OUT_OF_TILES }
const EV_UNDONE := "undone"

var level: Level = null
var board: Board = null
var path: Dictionary = {}          # Vector3i -> true
var edges: Array = []              # [from: Vector3i, dir: int, to: Vector3i]
var stream: TileStream = null
var discards_left: int = 0
var wild_charges: int = 0
var placements: int = 0
var history: Array[Move] = []
var status: Status = Status.PLAYING
## Why, when [member status] is `DEAD`. Reset by every fresh resolution, so an undo
## out of a dead board does not leave the last reason lying around.
var dead_reason: Dead = Dead.NONE

## Facts produced by the last mutation, oldest first. Drain, do not clear blindly.
var events: Array = []

## Stream index at the start of the current turn, before any free auto-discards.
var _turn_start_index: int = 0


## §5.2 setup. Resolves the first turn, so a level that opens on an unplaceable
## tile has already skipped it by the time the view sees the state.
static func start(p_level: Level) -> GameState:
	var s := GameState.new()
	s.level = p_level
	s.board = p_level.board
	s.stream = p_level.make_stream()
	s.discards_left = p_level.discards
	s.path = {p_level.board.start: true}
	s._turn_start_index = 0
	s._resolve_turn()
	return s


# --- queries -----------------------------------------------------------------

func current_tile() -> int:
	return stream.current()


func preview(n: int = 2) -> Array[int]:
	return stream.peek(n)


func legal_targets() -> Array[Vector3i]:
	if status != Status.PLAYING:
		return [] as Array[Vector3i]
	return Rules.legal_targets(board, path, current_tile())


func wild_targets() -> Array[Vector3i]:
	if status != Status.PLAYING or wild_charges <= 0:
		return [] as Array[Vector3i]
	return Rules.wild_targets(board, path)


func can_undo() -> bool:
	return not history.is_empty()


func can_discard() -> bool:
	return status == Status.PLAYING and discards_left > 0


func par() -> int:
	return level.par if level != null else 0


func drain_events() -> Array:
	var out: Array = events
	events = []
	return out


# --- mutations ---------------------------------------------------------------

## Commits the current tile onto [param target] (§5.5).
## Returns [code]false[/code] and changes nothing when the move is illegal.
func place(target: Vector3i) -> bool:
	if status != Status.PLAYING:
		return false
	var dir: int = current_tile()
	if not legal_targets().has(target):
		return false
	_commit(Move.Kind.PLACE, target, Rules.anchor_for(target, dir), dir)
	return true


## Commits [param target] by spending a wild charge (§6). The direction is
## inferred from anchor to target, so any adjacent enterable cell is legal.
## Spending is explicit and never implicit, so it cannot happen by accident.
func place_wild(target: Vector3i) -> bool:
	if status != Status.PLAYING or wild_charges <= 0:
		return false
	if not wild_targets().has(target):
		return false
	var anchor := _pick_wild_anchor(target)
	var dir: int = Direction.between(anchor, target)
	events.append({"type": EV_WILD_SPENT, "target": target})
	_commit(Move.Kind.WILD, target, anchor, dir)
	return true


## Voluntary discard (§5.7). Costs a charge; free auto-discards do not go through
## here and never touch [member discards_left].
func discard() -> bool:
	if not can_discard():
		return false
	var m := _begin_move(Move.Kind.DISCARD)
	history.append(m)
	discards_left -= 1
	events.append({"type": EV_DISCARDED, "dir": current_tile(), "left": discards_left})
	stream.advance()
	_turn_start_index = stream.index
	_resolve_turn()
	return true


## §5.9 — rewinds one move completely, including the stream index, discard count,
## portal twin and wild charges, and re-runs the auto-discards that preceded it.
func undo() -> bool:
	if history.is_empty():
		return false
	var m: Move = history.pop_back()
	for c: Vector3i in m.added:
		path.erase(c)
	for _i: int in range(m.edges_added):
		edges.pop_back()
	discards_left = m.discards_before
	wild_charges = m.wild_before
	placements = m.placements_before
	stream.rewind_to(m.stream_index_before)
	_turn_start_index = m.stream_index_before
	status = Status.PLAYING
	events.append({"type": EV_UNDONE, "move": m})
	_resolve_turn()
	return true


## §5.9 — a byte-identical reset. Restart of a seeded level reproduces it exactly.
func restart() -> GameState:
	return GameState.start(level)


# --- internals ---------------------------------------------------------------

func _begin_move(kind: Move.Kind) -> Move:
	var m := Move.new()
	m.kind = kind
	m.stream_index_before = _turn_start_index
	m.discards_before = discards_left
	m.wild_before = wild_charges
	m.placements_before = placements
	return m


func _commit(kind: Move.Kind, target: Vector3i, anchor: Vector3i, dir: int) -> void:
	var m := _begin_move(kind)
	m.target = target
	m.anchor = anchor
	m.dir = dir

	path[target] = true
	edges.append([anchor, dir, target])
	m.added.append(target)
	m.edges_added = 1
	placements += 1
	events.append({"type": EV_PLACED, "target": target, "anchor": anchor, "dir": dir})

	if kind == Move.Kind.WILD:
		wild_charges -= 1

	# §5.5.3 — a portal teleports the network: the twin joins immediately and
	# becomes a second growth frontier.
	if board.is_portal(target):
		var twin := board.portal_twin(target)
		if twin != target and board.is_open(twin) and not path.has(twin):
			path[twin] = true
			edges.append([target, Direction.PORTAL, twin])
			m.added.append(twin)
			m.edges_added += 1
			events.append({"type": EV_PORTAL, "from": target, "to": twin})

	for c: Vector3i in m.added:
		if board.is_wild(c):
			wild_charges += 1
			events.append({"type": EV_WILD_GAINED, "cell": c, "charges": wild_charges})
		if board.is_goal(c):
			events.append({"type": EV_GOAL_REACHED, "cell": c})

	history.append(m)
	stream.advance()
	_turn_start_index = stream.index
	_resolve_turn()


## Recomputes [member status] and burns free auto-discards until a placeable tile
## is current (§5.7). The player is never charged for an impossible draw.
func _resolve_turn() -> void:
	dead_reason = Dead.NONE
	if Rules.is_won(board, path):
		_set_status(Status.WON)
		return

	if level.has_budget() and placements >= level.budget:
		dead_reason = Dead.BUDGET
		_set_status(Status.DEAD)
		return

	# Optimistic bound: a goal outside the flood fill can never be reached.
	if Rules.has_unreachable_goal(board, path):
		dead_reason = Dead.UNREACHABLE_GOAL
		_set_status(Status.DEAD)
		return

	# The path is frozen — every adjacent cell is a wall or an unsatisfiable gate,
	# so no future draw can ever help. Without this check the auto-discard loop
	# below would spin forever on an infinite bag stream.
	if Rules.wild_targets(board, path).is_empty():
		dead_reason = Dead.PATH_FROZEN
		_set_status(Status.DEAD)
		return

	while true:
		var dir: int = stream.current()
		if dir == Direction.NONE:
			# A fixed tile sequence ran out before the goal (§5.8).
			dead_reason = Dead.OUT_OF_TILES
			_set_status(Status.DEAD)
			return
		if not Rules.legal_targets(board, path, dir).is_empty():
			return
		events.append({"type": EV_AUTO_SKIPPED, "dir": dir})
		stream.advance()


func _set_status(s: Status) -> void:
	status = s
	if s == Status.WON:
		events.append({"type": EV_WON, "placements": placements})
	elif s == Status.DEAD:
		events.append({"type": EV_DEAD, "reason": dead_reason})


## The cell [param target] would actually be entered *from*, and therefore the edge
## a placement would cross — the ordinary anchor for the tile in hand, or the wild's
## canonical one when [param wild] is set.
##
## Public because the board draws that edge. A view computing it a second way would
## be free to light the seam the move does not use, which is worse than lighting
## none: it would be a promise about where the line is going that the rules then
## break.
func anchor_of(target: Vector3i, wild: bool = false) -> Vector3i:
	return _pick_wild_anchor(target) if wild else Rules.anchor_for(target, current_tile())


## Any path neighbour is a valid anchor for a wild placement; the canonical order
## keeps the choice deterministic so replays match.
func _pick_wild_anchor(target: Vector3i) -> Vector3i:
	for dir: int in Direction.ALL:
		var a: Vector3i = target + Direction.delta(dir)
		if path.has(a):
			return a
	return target


# --- persistence (§17.2 `in_progress`) ---------------------------------------

func to_dict() -> Dictionary:
	var path_out: Array = []
	for c: Vector3i in Hex.sort_cells(_path_cells()):
		path_out.append(Hex.to_array(c))
	var edges_out: Array = []
	for e: Variant in edges:
		var edge: Array = e
		edges_out.append([Hex.to_array(edge[0]), int(edge[1]), Hex.to_array(edge[2])])
	return {
		"path": path_out,
		"edges": edges_out,
		"stream_index": stream.index,
		"turn_start_index": _turn_start_index,
		"discards_left": discards_left,
		"wild_charges": wild_charges,
		"placements": placements,
		"status": int(status),
	}


## Restores a suspended run (§18.3). History is intentionally not persisted —
## undo does not survive a suspend, which §5.9 permits and keeps the save at ~2 KB.
func restore(d: Dictionary) -> void:
	path.clear()
	for a: Variant in d.get("path", []):
		path[Hex.from_array(a as Array)] = true
	edges.clear()
	for e: Variant in d.get("edges", []):
		var edge: Array = e
		edges.append([Hex.from_array(edge[0] as Array), int(edge[1]), Hex.from_array(edge[2] as Array)])
	stream.rewind_to(int(d.get("stream_index", 0)))
	_turn_start_index = int(d.get("turn_start_index", stream.index))
	discards_left = int(d.get("discards_left", 0))
	wild_charges = int(d.get("wild_charges", 0))
	placements = int(d.get("placements", 0))
	status = int(d.get("status", Status.PLAYING)) as Status
	history.clear()
	events.clear()


func _path_cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for c: Vector3i in path.keys():
		out.append(c)
	return out

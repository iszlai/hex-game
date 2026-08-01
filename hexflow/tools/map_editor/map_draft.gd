## The board being drawn, and the constraints that hold while it is being drawn
## (MAP-EDITOR §4).
##
## A [Board] is immutable by design — built once, never touched during play — and
## that is exactly wrong for the thing under an author's cursor. This is the
## mutable half: a cell set, one content per cell, and the §4.2 checks that have
## to answer *while the mouse is down* rather than at Validate.
##
## Two brushes, not one (§4.1). **Board** decides whether a hex is part of the
## level at all; **contents** decides what is on it. Conflating them is the usual
## way a hex editor becomes confusing — "erase" then means two different things
## depending on what is under the cursor, and an author who wanted a hole gets a
## wall instead.
##
## Contents are **one per cell**, which the game's flags are not: [Board] stores a
## bitmask and a cell can be both a goal and a gate. That is a deliberate
## narrowing — §3's brush palette is a single-choice list, and a board where a
## mark can hide under another mark is a board an author cannot read. Nothing the
## sweep produces overlaps either: gates, wilds and portals are placed on cells
## the reserved route never touched. [method from_level] says so out loud when it
## meets a file that does overlap, rather than dropping the mark in silence.
##
## Not part of the shipped game.
class_name MapDraft
extends RefCounted

enum Content { EMPTY, WALL, START, GOAL, PORTAL, GATE, WILD }

## What each content is called and what it is drawn as. Letters rather than
## pictograms: §3 allows either, the brush panel spells out which letter is which,
## and a glyph the bundled font has no coverage for is a blank hexagon.
const NAMES: Array[String] = ["empty", "wall", "start", "goal", "portal", "gate", "wild"]
const LETTERS: Array[String] = ["", "#", "S", "G", "P", "K", "*"]

## The brushes offered, in the order §3 lists them. `BOARD` is the odd one — it
## paints membership rather than contents — so it sits outside the enum above.
const BRUSH_BOARD := -1


var cells: Dictionary = {}          ## Vector3i -> true. The board itself.
var content: Dictionary = {}        ## Vector3i -> Content. Absent means EMPTY.
var start: Vector3i = Hex.NONE

## Portal ends, in pairs. An entry of one cell is a lone A: allowed while drawing
## and flagged at rest, because the brush alternates and the author is mid-pair.
var portals: Array = []

var shape: String = "hexagon"
var shape_size: int = 3
var shape_arg: int = 0

var discards: int = 3
var budget: int = Level.NO_BUDGET

## The dealt sequence (§4.4). [member tiles_stale] goes true the moment the board
## changes under it, because a sequence made for a different board is the single
## most expensive thing to not notice.
var tiles: Array[int] = []
var tiles_stale: bool = false

## §4.4's fourth way to get a sequence, **Trace**: the cells an author clicked, in
## order, and the direction each one was entered from. Those directions *are*
## [member tiles].
##
## A traced sequence is a recorded legal play, so it is solvable by construction —
## which is the one thing Fill cannot promise. Fill sweeps ten seeds and each is a
## random walk that can dead-end; on a tight board every one of them can, and then
## there is no sequence at all and nothing to do about it. Drawing the route by
## hand is the answer to that, and it is also the only way to get a route that was
## *chosen* rather than found.
##
## Not saved, and not recoverable from a file: the level records the sequence, and
## the route that produced it is one of the many that sequence allows.
var trace: Array[Vector3i] = []
var trace_dirs: Array[int] = []

## The path the trace has built: the start, every traced cell, and the twin of
## every portal stepped on (§5.5.3). Cached rather than recomputed, because the
## canvas asks once per redraw and once per mouse move.
var _path: Dictionary = {}
## The same cells in the order they joined, newest last. Which anchor a step is
## measured from decides which tile it is, so the order is not decoration.
var _order: Array[Vector3i] = []
## Which of Fill's deals was kept, so re-running Fill with it reproduces the
## level exactly (§10 Q4). Provenance, written to `generator.seed`.
var fill_seed: int = 0

## Kept across an edit (C-34): this is the same level with a wall moved, and its
## stars belong to it. Only the sweep mints a new one.
var uid: String = ""
var chapter: int = 1
var index: int = 1

## Anything [method from_level] had to flatten. Shown once, on load.
var notes: Array[String] = []


# --- building ------------------------------------------------------------------

## Fills the canvas from one of C-32's shapes. A starting point, not a cage (§4.3):
## contents already placed on cells the new shape still has are kept, so changing
## a ring's hole does not throw away the goals around it.
func apply_shape(kind: String, size: int, arg: int) -> void:
	shape = kind
	shape_size = size
	shape_arg = arg
	cells = {}
	for c: Vector3i in Hex.shape(kind, size, arg):
		cells[c] = true
	_drop_contents_off_board()
	_rebuild_path()
	tiles_stale = true


func count() -> int:
	return cells.size()


func at_ceiling() -> bool:
	return cells.size() >= Hex.MAX_CELLS


func has(c: Vector3i) -> bool:
	return cells.has(c)


func content_at(c: Vector3i) -> Content:
	return content.get(c, Content.EMPTY)


## Adds a cell. Refuses at the ceiling — the solver's path mask is 64 bits, so
## sixty-one is not a guideline (C-19). Returns false when nothing changed.
func add_cell(c: Vector3i) -> bool:
	if cells.has(c) or at_ceiling() or not Hex.is_valid(c):
		return false
	cells[c] = true
	tiles_stale = true
	return true


func remove_cell(c: Vector3i) -> bool:
	if not cells.has(c):
		return false
	clear_content(c)
	cells.erase(c)
	tiles_stale = true
	return true


## Paints contents. Only meaningful on a cell that is on the board — painting a
## goal into empty space would be an invisible edit, so it is refused rather than
## silently adding the cell.
func set_content(c: Vector3i, kind: Content) -> bool:
	if not cells.has(c):
		return false
	if kind == Content.EMPTY:
		return clear_content(c)
	if content_at(c) == kind and kind != Content.PORTAL:
		return false

	clear_content(c)
	match kind:
		Content.START:
			# A second start *moves* the first rather than being refused (§4.2).
			# Refusing would mean an author who wanted the start somewhere else had
			# to erase before they could draw, which is a rule nobody remembers.
			if start != Hex.NONE and cells.has(start):
				content.erase(start)
			start = c
		Content.PORTAL:
			_join_portal(c)
	content[c] = kind
	_rebuild_path()
	tiles_stale = true
	return true


func clear_content(c: Vector3i) -> bool:
	if not content.has(c):
		return false
	if content_at(c) == Content.START:
		start = Hex.NONE
	elif content_at(c) == Content.PORTAL:
		_unjoin_portal(c)
	content.erase(c)
	_rebuild_path()
	tiles_stale = true
	return true


## The brush alternates A/B: a portal painted while a pair is half-open closes it,
## and otherwise opens a new one.
func _join_portal(c: Vector3i) -> void:
	for pair: Variant in portals:
		var p: Array = pair
		if p.size() == 1:
			p.append(c)
			return
	portals.append([c] as Array)


func _unjoin_portal(c: Vector3i) -> void:
	for i: int in range(portals.size() - 1, -1, -1):
		var p: Array = portals[i]
		p.erase(c)
		if p.is_empty():
			portals.remove_at(i)


func _drop_contents_off_board() -> void:
	for c: Variant in content.keys():
		if not cells.has(c):
			clear_content(c as Vector3i)


# --- §4.4's trace: drawing the sequence instead of sweeping for it ---------------

## Whether the traced path has reached [param c] — including a portal twin it was
## carried to without being clicked.
func on_path(c: Vector3i) -> bool:
	return _path.has(c)


## The twin of a portal cell, or [param c] itself when it is not one. Only closed
## pairs count: a lone A is not a door yet (§4.2).
func portal_twin(c: Vector3i) -> Vector3i:
	for pair: Variant in portals:
		var p: Array = pair
		if p.size() != 2:
			continue
		if p[0] == c:
			return p[1] as Vector3i
		if p[1] == c:
			return p[0] as Vector3i
	return c


## Which path cell the next step onto [param c] would be measured from, or
## [constant Hex.NONE] when the path does not reach it.
##
## The game grows the path from **any** cell it already has, not only from the end
## of it (§5.4), so a click beside an older cell is legal and means a fork. The
## newest neighbour is preferred because a cell touching two path cells is two
## different tiles, and the one that continues the line being drawn is the one the
## author meant.
func trace_anchor(c: Vector3i) -> Vector3i:
	for i: int in range(_order.size() - 1, -1, -1):
		if Hex.distance(_order[i], c) == 1:
			return _order[i]
	return Hex.NONE


## Why the next step cannot land on [param c], or [code]""[/code] when it can.
##
## This is [Rules] restated in the editor's words rather than reused, because the
## two want different things from it: the game needs a boolean per candidate cell
## and the author needs to be told which rule they just met. Every clause here has
## its counterpart in `Rules._can_enter`, and a step that passes all of them is a
## move the game would accept.
func trace_refusal(c: Vector3i) -> String:
	if start == Hex.NONE or not cells.has(start):
		return "trace: place a start first — the route grows out of it"
	if not cells.has(c):
		return "trace: %v is not on the board" % c
	if content_at(c) == Content.WALL:
		return "trace: %v is a wall" % c
	if _path.has(c):
		return "trace: the route is already there"
	if trace_anchor(c) == Hex.NONE:
		return "trace: %v does not touch the route — a tile is laid against a cell the path already has" % c
	if content_at(c) == Content.GATE and _path_neighbours(c) < 2:
		return "trace: a gate opens only once the path reaches it twice (§6) — come back to it"
	return ""


func can_trace(c: Vector3i) -> bool:
	return trace_refusal(c) == ""


## Takes the next step, and with it the next tile. Returns the refusal, or
## [code]""[/code] when the step was taken.
func trace_step(c: Vector3i) -> String:
	var why := trace_refusal(c)
	if why != "":
		return why
	trace.append(c)
	trace_dirs.append(Direction.between(trace_anchor(c), c))
	_join_path(c)
	_adopt_trace()
	return ""


## Takes the last step back. False when there is nothing to take back.
func undo_trace() -> bool:
	if trace.is_empty():
		return false
	trace.pop_back()
	trace_dirs.pop_back()
	_rebuild_path()
	_adopt_trace()
	return true


## Drops the route and leaves the sequence alone. For the two things that produce
## a sequence some other way — Fill and the text field — because a drawn route
## that no longer matches the tiles beside it is a lie on the canvas.
func clear_trace() -> void:
	trace = []
	trace_dirs = []
	_rebuild_path()


## Replays the route against the board as it stands and drops it from the first
## step that is no longer legal. Returns how many steps went.
##
## The board can move under a route — that is the whole point of being able to
## paint a wall after drawing one — and a route through a wall describes a
## sequence nobody can play. Truncating is not politeness either: the prefix up to
## the wall is still a legal play and still worth keeping.
func revalidate_trace() -> int:
	var wanted: Array[Vector3i] = trace.duplicate()
	trace = []
	trace_dirs = []
	_rebuild_path()
	for c: Vector3i in wanted:
		if trace_step(c) != "":
			break
	return wanted.size() - trace.size()


## How many goals the route has not joined yet. Zero on a board with goals means
## the traced sequence is a complete solution.
func trace_goals_left() -> int:
	var left: int = 0
	for g: Vector3i in goals():
		if not _path.has(g):
			left += 1
	return left


## The route *is* the sequence. Not stale by construction: it was drawn against
## this board, one legal step at a time.
func _adopt_trace() -> void:
	tiles = trace_dirs.duplicate()
	tiles_stale = false


func _rebuild_path() -> void:
	_path = {}
	_order = []
	if start != Hex.NONE and cells.has(start):
		_join_path(start)
	for c: Vector3i in trace:
		_join_path(c)


## §5.5.3 — stepping on a portal joins its twin at the same moment, so the next
## tile may be laid against either end. A route that could not do that would be
## drawing a different game from the one the level is played in.
func _join_path(c: Vector3i) -> void:
	if not _path.has(c):
		_path[c] = true
		_order.append(c)
	var twin: Vector3i = portal_twin(c)
	if twin != c and not _path.has(twin):
		_path[twin] = true
		_order.append(twin)


func _path_neighbours(c: Vector3i) -> int:
	var n: int = 0
	for dir: int in Direction.ALL:
		if _path.has(c + Direction.delta(dir)):
			n += 1
	return n


# --- the constraints of §4.2 ---------------------------------------------------

## What is wrong with the board *right now*. Enforced as you draw, because
## discovering these at Validate is discovering them too late.
##
## The ceiling is not in here: it is refused at [method add_cell] rather than
## reported, since a board over the line cannot be built at all.
func problems() -> Array[String]:
	var out: Array[String] = []
	if cells.size() < Board.MIN_CELLS:
		out.append("%d cells is too small to be a level (min %d)" % [cells.size(), Board.MIN_CELLS])
	if start == Hex.NONE or not cells.has(start):
		out.append("no start")
	elif content_at(start) == Content.WALL:
		out.append("the start is a wall")
	if goals().is_empty():
		out.append("no goal")
	for pair: Variant in portals:
		if (pair as Array).size() == 1:
			out.append("portal at %v has no twin" % ((pair as Array)[0] as Vector3i))
	var loose: int = cells.size() - _largest_island()
	if loose > 0:
		out.append("the board is in more than one piece (%d cells cut off)" % loose)
	return out


## The size of the biggest connected group of cells. A board painted with a cell
## nobody can reach is a real mistake and never an intent — but it is also what
## every board looks like one stroke into being drawn, which is why this is
## reported at rest rather than refused at the brush.
func _largest_island() -> int:
	if cells.is_empty():
		return 0
	var seen: Dictionary = {}
	var best: int = 0
	for seed_cell: Variant in Hex.sort_cells(_cell_list()):
		if seen.has(seed_cell):
			continue
		var reached: int = 0
		var queue: Array[Vector3i] = [seed_cell as Vector3i]
		seen[seed_cell] = true
		while not queue.is_empty():
			var c: Vector3i = queue.pop_back()
			reached += 1
			for dir: int in Direction.ALL:
				var n: Vector3i = c + Direction.delta(dir)
				if cells.has(n) and not seen.has(n):
					seen[n] = true
					queue.append(n)
		best = maxi(best, reached)
	return best


# --- reading the contents ------------------------------------------------------

func cells_of(kind: Content) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for c: Vector3i in Hex.sort_cells(_cell_list()):
		if content_at(c) == kind:
			out.append(c)
	return out


func goals() -> Array[Vector3i]:
	return cells_of(Content.GOAL)


## Only the pairs that are actually pairs. A lone A is flagged by
## [method problems] and left out of the board, so a half-drawn portal cannot
## reach the solver as a one-way door.
func complete_portals() -> Array:
	var out: Array = []
	for pair: Variant in portals:
		var p: Array = pair
		if p.size() == 2:
			out.append([p[0], p[1]])
	return out


## Which pair a portal cell belongs to, 1-based, so the canvas can label the two
## ends of the same door with the same number. Zero when it is not a portal.
func portal_index(c: Vector3i) -> int:
	for i: int in range(portals.size()):
		if (portals[i] as Array).has(c):
			return i + 1
	return 0


func _cell_list() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for c: Variant in cells.keys():
		out.append(c as Vector3i)
	return out


# --- crossing to the game's types ----------------------------------------------

## Builds the real [Level] this draft describes. Always with an explicit cell
## list, so a board that *is* its named shape still round-trips as three numbers —
## [method Board.is_named_shape] decides that, not this.
##
## Returns [code]null[/code] when the draft has no start, because [Board.build]
## flags the start cell and there would be nothing to flag.
func to_level() -> Level:
	if start == Hex.NONE:
		return null
	var board := Board.build(
		shape_size, start, goals(),
		cells_of(Content.WALL), complete_portals(),
		cells_of(Content.GATE), cells_of(Content.WILD),
		shape, shape_arg, Hex.sort_cells(_cell_list())
	)
	var level := Level.build(board, tiles.duplicate(), fill_seed)
	level.discards = discards
	level.budget = budget
	level.uid = uid
	level.chapter = chapter
	level.index = index
	level.id = LevelRepository.id_for(chapter, index)
	level.generator_seed = fill_seed
	return level


static func from_level(level: Level) -> MapDraft:
	var draft := MapDraft.new()
	var board := level.board
	for c: Vector3i in board.cells():
		draft.cells[c] = true
	draft.shape = board.shape
	draft.shape_size = board.shape_size
	draft.shape_arg = board.shape_arg
	draft.discards = level.discards
	draft.budget = level.budget
	draft.tiles = level.tiles.duplicate()
	draft.fill_seed = level.generator_seed
	draft.uid = level.uid
	draft.chapter = level.chapter
	draft.index = level.index

	for c: Vector3i in board.cells():
		var kind := draft._content_for(board, c)
		if kind == Content.EMPTY:
			continue
		if draft._marks_on(board, c) > 1:
			draft.notes.append("%v carried more than one mark; kept %s"
				% [c, NAMES[int(kind)]])
		if kind == Content.PORTAL:
			continue     # placed below, in pairs, so the pairing survives
		draft.content[c] = kind
		if kind == Content.START:
			draft.start = c
	for pair: Variant in board.portal_pairs():
		var p: Array = pair
		draft.portals.append([p[0], p[1]])
		draft.content[p[0] as Vector3i] = Content.PORTAL
		draft.content[p[1] as Vector3i] = Content.PORTAL
	# Loading a sequence is §4.4's third option, **Keep**: the board can then be
	# edited around a deal that already works.
	draft.tiles_stale = false
	# The contents above were placed straight into the dictionaries rather than
	# through `set_content`, so nothing has built the path the trace grows from.
	draft._rebuild_path()
	return draft


## Precedence when a cell carries more than one of the game's flags. Start first
## because there is only ever one and losing it breaks the board; wall last
## because it is the only one that is a [Board.Kind] rather than a flag, and a
## wall under a goal is already a validation error.
func _content_for(board: Board, c: Vector3i) -> Content:
	if board.has_flag(c, Board.F_START):
		return Content.START
	if board.has_flag(c, Board.F_GOAL):
		return Content.GOAL
	if board.is_portal(c):
		return Content.PORTAL
	if board.is_gate(c):
		return Content.GATE
	if board.is_wild(c):
		return Content.WILD
	if board.is_wall(c):
		return Content.WALL
	return Content.EMPTY


func _marks_on(board: Board, c: Vector3i) -> int:
	var n: int = 1 if board.is_wall(c) else 0
	for flag: int in [Board.F_START, Board.F_GOAL, Board.F_PORTAL, Board.F_GATE, Board.F_WILD]:
		if board.has_flag(c, flag):
			n += 1
	return n

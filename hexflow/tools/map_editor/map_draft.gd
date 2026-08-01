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

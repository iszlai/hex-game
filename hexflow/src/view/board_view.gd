## Draws the board. Presentation only — it computes no legality and owns no rules.
##
## M3 grey-box: immediate-mode `_draw` with prebuilt geometry. M7 replaces the
## body of `_draw` with a single `MultiMeshInstance2D` and the SDF shader of
## §13.3; everything above this line (the state it reads, the signals it answers)
## stays the same, which is why the grey-box must keep working through M7.
##
## No allocation happens per frame: the hexagon outline, the per-cell transforms
## and the glyph strings are all built once in [method rebuild] (C4 — the 2016
## prototype allocated a texture per tile draw and never freed it, B5).
class_name BoardView
extends Node2D

const STROKE := 2.0
const CANDIDATE_STROKE := 2.5
const CURSOR_STROKE := 3.0
const CONNECTOR_WIDTH := 0.30   # of the cell circumradius

@export var palette: Palette = null

var layout: HexLayout = null

var _board: Board = null
var _state: GameState = null
var _candidates: Dictionary = {}      # Vector3i -> true
var _cursor: Vector3i = Vector3i.ZERO
var _has_cursor: bool = false
var _depth: Dictionary = {}           # Vector3i -> steps from start, for the gradient

var _centres: Dictionary = {}         # Vector3i -> Vector2
var _outline: PackedVector2Array = PackedVector2Array()
var _font: Font = null


func _ready() -> void:
	if palette == null:
		palette = Palette.current()
	_font = ThemeDB.fallback_font


## Binds a level and sizes the board to [param play_area] (§4.4). Called once per
## level, never per frame.
func bind(state: GameState, play_area: Vector2) -> void:
	_state = state
	_board = state.board
	var s: int = HexLayout.fit(_board.radius, play_area)
	layout = HexLayout.new(float(s), play_area * 0.5)
	_outline = layout.corners()
	_centres.clear()
	for c: Vector3i in _board.cells():
		_centres[c] = layout.to_pixel(c)
	rebuild()


## Recomputes everything derived from the live state. Called after each move, not
## each frame.
func rebuild() -> void:
	_recompute_depth()
	queue_redraw()


func set_candidates(targets: Array[Vector3i]) -> void:
	_candidates.clear()
	for t: Vector3i in targets:
		_candidates[t] = true
	queue_redraw()


func set_cursor(cell: Vector3i, visible_cursor: bool = true) -> void:
	_cursor = cell
	_has_cursor = visible_cursor
	queue_redraw()


func centres() -> Dictionary:
	return _centres


func centre_of(cell: Vector3i) -> Vector2:
	return _centres.get(cell, Vector2.ZERO)


## Hit-testing goes through the layout's inverse conversion, never through raw
## screen coordinates — defect B7 in the original.
func cell_at(local_point: Vector2) -> Vector3i:
	return layout.from_pixel(local_point)


func _draw() -> void:
	if _board == null:
		return
	# Lattice connectors go underneath the cells so the path reads as one
	# continuous stroke rather than as bands laid over the hexes. Portal tethers
	# link non-adjacent cells, so they are drawn on top where they stay visible.
	_draw_connectors()
	for c: Vector3i in _board.cells():
		_draw_cell(c)
	_draw_portal_tethers()
	if _has_cursor and _centres.has(_cursor):
		_draw_outline(_centres[_cursor], palette.focus, CURSOR_STROKE, 1.12)


func _draw_cell(c: Vector3i) -> void:
	var centre: Vector2 = _centres[c]
	var in_path: bool = _state.path.has(c)

	if _board.is_wall(c):
		_draw_fill(centre, palette.wall_fill)
		_draw_outline(centre, palette.wall_stroke, STROKE)
		_draw_hatch(centre)
		return

	if in_path:
		var fill: Color = palette.path_at_depth(int(_depth.get(c, 0)), maxi(1, _depth.size()))
		if c == _board.start:
			fill = palette.start_cell
		_draw_fill(centre, fill)
		_draw_outline(centre, fill.lightened(0.25), STROKE)
	else:
		_draw_fill(centre, palette.cell_empty_fill)
		var is_candidate: bool = _candidates.has(c)
		_draw_outline(
			centre,
			palette.cell_candidate_stroke if is_candidate else palette.cell_empty_stroke,
			CANDIDATE_STROKE if is_candidate else STROKE
		)

	# Every modifier is identified by glyph *and* shape *and* colour, never colour
	# alone (§21). The grey-box uses text glyphs; M7 swaps in the icon atlas.
	if _board.is_goal(c):
		_draw_ring(centre, palette.goal_cell, 0.62)
		_draw_glyph(centre, "◎", palette.goal_cell)
	if _board.is_portal(c):
		_draw_ring(centre, palette.portal, 0.68)
		_draw_ring(centre, palette.portal, 0.46)
	if _board.is_gate(c):
		_draw_ring(centre, palette.gate, 0.58)
		_draw_glyph(centre, "⌸", palette.gate)
	if _board.is_wild(c):
		_draw_glyph(centre, "★", palette.wild)


func _draw_connectors() -> void:
	var width: float = layout.size * CONNECTOR_WIDTH
	for e: Variant in _state.edges:
		var edge: Array = e
		if int(edge[1]) == Direction.PORTAL:
			continue
		var from: Vector3i = edge[0]
		var to: Vector3i = edge[2]
		if not _centres.has(from) or not _centres.has(to):
			continue
		var colour: Color = palette.path_at_depth(int(_depth.get(to, 0)), maxi(1, _depth.size()))
		draw_line(_centres[from], _centres[to], colour, width)


## A portal link is not a lattice step, so it reads as a dashed tether rather
## than a solid connector — the player must see that the two ends are one network.
func _draw_portal_tethers() -> void:
	for e: Variant in _state.edges:
		var edge: Array = e
		if int(edge[1]) != Direction.PORTAL:
			continue
		if _centres.has(edge[0]) and _centres.has(edge[2]):
			_draw_dashed(_centres[edge[0]], _centres[edge[2]], palette.portal)


func _draw_fill(centre: Vector2, colour: Color) -> void:
	draw_colored_polygon(_translated(centre, 1.0), colour)


func _draw_outline(centre: Vector2, colour: Color, width: float, scale: float = 1.0) -> void:
	var pts := _translated(centre, scale)
	pts.append(pts[0])
	draw_polyline(pts, colour, width)


func _draw_ring(centre: Vector2, colour: Color, scale: float) -> void:
	var pts := _translated(centre, scale)
	pts.append(pts[0])
	draw_polyline(pts, colour, STROKE)


func _draw_hatch(centre: Vector2) -> void:
	# 45° hatching: the wall's colour-independent identity (§21).
	var r: float = layout.size * 0.6
	for i: int in range(-2, 3):
		var offset := Vector2(float(i) * r * 0.42, 0.0)
		draw_line(
			centre + offset + Vector2(-r * 0.5, -r * 0.5),
			centre + offset + Vector2(r * 0.5, r * 0.5),
			palette.wall_stroke, 1.5
		)


func _draw_dashed(from: Vector2, to: Vector2, colour: Color) -> void:
	var steps: int = 9
	for i: int in range(0, steps, 2):
		var a := from.lerp(to, float(i) / float(steps))
		var b := from.lerp(to, float(i + 1) / float(steps))
		draw_line(a, b, colour, 2.0)


func _draw_glyph(centre: Vector2, glyph: String, colour: Color) -> void:
	if _font == null:
		return
	var s: int = int(layout.size * 0.7)
	var w: float = _font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	draw_string(
		_font, centre + Vector2(-w * 0.5, float(s) * 0.35), glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1, s, colour
	)


func _translated(centre: Vector2, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in _outline:
		out.append(centre + p * scale)
	return out


## Shared with the C-18 board, so the two views can never disagree about how far
## along the path a cell is.
func _recompute_depth() -> void:
	_depth = PathDepth.of(_state)

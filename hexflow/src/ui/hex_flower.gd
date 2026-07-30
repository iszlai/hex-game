## §9's hex-flower chapter map: one chapter's twelve levels laid out as a
## radius-1 cluster of seven with a row of five beneath it.
##
## §9 asks for "the same board renderer — no separate UI system", and this is as
## close to that as the renderer allows without lying. [BoardView] and
## [BoardView3D] both bind a [GameState]: a cell is empty, walled, on the path or
## a goal, and none of those is what a map cell is. Rendering "level 7, two stars,
## locked" through a game state would mean encoding progression as walls and path
## — cute for one commit, and broken the first time the path gradient or C-22's
## tile heights change under it. So what is reused is the part that actually makes
## this a hex map: [HexLayout]'s §4.3 conversion, its corner geometry and its fit
## rule, plus every colour from [Palette]. There is no second hexagon formula in
## the codebase, which is what §9's sentence is protecting. Logged as **C-25**.
##
## Nothing allocates in `_draw` (C4): every polygon, hatch line and pip position
## is built once in [method bind].
class_name HexFlower
extends Control

## §9: "a radius-1 hex cluster of 7 + a second row of 5". Index `i` holds level
## `i + 1`, so the table *is* the reading order — centre first, then the ring
## clockwise from the top-left, then the row left to right. A permutation here is
## a visible design change and belongs in a diff, not in a loop that computes it.
const CELLS: Array[Vector3i] = [
	Vector3i(0, 0, 0),      # 1  — centre
	Vector3i(0, 1, -1),     # 2  — ring, up-left
	Vector3i(1, 0, -1),     # 3  — ring, up-right
	Vector3i(1, -1, 0),     # 4  — ring, right
	Vector3i(0, -1, 1),     # 5  — ring, down-right
	Vector3i(-1, 0, 1),     # 6  — ring, down-left
	Vector3i(-1, 1, 0),     # 7  — ring, left
	Vector3i(-3, 1, 2),     # 8  — row of five, left to right
	Vector3i(-2, 0, 2),     # 9
	Vector3i(-1, -1, 2),    # 10
	Vector3i(0, -2, 2),     # 11
	Vector3i(1, -3, 2),     # 12
]

## The flower's extent in circumradii, from [constant CELLS]: centres span
## ±3.46 s horizontally and −1.5 s to +3 s vertically, and a pointy-top cell
## reaches 0.866 s sideways and 1 s up and down from its own centre.
const SPAN_X := 8.66
const SPAN_Y := 6.5

const STROKE := 2.0
const CURSOR_STROKE := 3.0
## §21: the focus ring "also scales 1.04×", on top of sitting outside the cell.
const CURSOR_SCALE := 1.12
const CURSOR_GROW := 1.04

enum State { LOCKED, OPEN, DONE }

@export var palette: Palette = null

var layout: HexLayout = null

## `index -> {state, stars, hinted}`, one entry per level, filled by [method bind].
var _rows: Array[Dictionary] = []
var _centres: Dictionary = {}          # Vector3i -> Vector2
var _cell_of: Dictionary = {}          # Vector3i -> level index
var _polygons: Dictionary = {}         # Vector3i -> PackedVector2Array
var _cursor_ring: Dictionary = {}      # Vector3i -> PackedVector2Array
var _hatch: Dictionary = {}            # Vector3i -> PackedVector2Array of line pairs
var _pips: Dictionary = {}             # Vector3i -> PackedVector2Array of pip centres
var _cursor: int = 1
var _font: Font = null
var _font_size: int = 18


func _ready() -> void:
	if palette == null:
		palette = load("res://src/data/palettes/neon_dark.tres")
	# §13.4 by role. Built once — a `FontVariation` per frame would be exactly the
	# per-frame allocation C4 exists to stop.
	_font = Typography.font_of(Typography.Role.NUMERAL)
	# The map is drawn here and *routed* by the screen, exactly as `BoardView3D` is:
	# the screen owns the [InputRouter] and the pointer conversion, so keyboard,
	# gamepad and finger all arrive on one path. A `Control` that ate GUI input on
	# the way is precisely how B7 stayed hidden through all of M3.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Lays the chapter out inside [param box] and reads each level's state from the
## save. Called when the chapter changes, never per frame.
func bind(rows: Array[Dictionary], box: Vector2) -> void:
	_rows = rows
	var s: float = float(fit(box))
	layout = HexLayout.new(s, Vector2.ZERO)
	# The flower is not centred on `(0,0,0)`: its rows run from −1.5 s to +3 s, so
	# centring means shifting by the midpoint of that span rather than by half the
	# box, which is what [method HexLayout.center_in] would do for a board.
	layout.origin = box * 0.5 - Vector2(0.0, s * 0.75)

	_centres.clear()
	_cell_of.clear()
	_polygons.clear()
	_cursor_ring.clear()
	_hatch.clear()
	_pips.clear()
	_font_size = maxi(Typography.FLOOR_PX, int(s * 0.42))

	for i: int in range(CELLS.size()):
		var cell: Vector3i = CELLS[i]
		var centre: Vector2 = layout.to_pixel(cell)
		_centres[cell] = centre
		_cell_of[cell] = i + 1
		_polygons[cell] = _hexagon(centre, 1.0)
		_cursor_ring[cell] = _hexagon(centre, CURSOR_SCALE * CURSOR_GROW)
		_hatch[cell] = _hatch_lines(centre, s)
		_pips[cell] = _pip_centres(centre, s)
	queue_redraw()


## The largest circumradius whose whole flower plus [constant HexLayout.MARGIN]
## on every side fits inside [param box] — §4.4's fit rule, over this shape's own
## span rather than a board's.
static func fit(box: Vector2) -> int:
	var usable := box - Vector2(HexLayout.MARGIN, HexLayout.MARGIN) * 2.0
	return maxi(16, int(floor(minf(usable.x / SPAN_X, usable.y / SPAN_Y))))


func set_cursor(index: int) -> void:
	_cursor = clampi(index, 1, CELLS.size())
	queue_redraw()


func cursor() -> int:
	return _cursor


## Where every level sits, for [InputRouter] — the map navigates on exactly the
## §11.2 cone the board does, so the six-way geometry behaves the same in both.
func centres() -> Dictionary:
	return _centres


static func cell_for(index: int) -> Vector3i:
	return CELLS[clampi(index, 1, CELLS.size()) - 1]


## The level under a point, or 0. Routed through [method HexLayout.from_pixel]
## like every other hit-test in the project (defect B7).
func level_at(local_point: Vector2) -> int:
	if layout == null:
		return 0
	return int(_cell_of.get(layout.from_pixel(local_point), 0))


func _draw() -> void:
	if layout == null or _rows.size() < CELLS.size():
		return
	for i: int in range(CELLS.size()):
		_draw_level(CELLS[i], _rows[i])
	var cell: Vector3i = cell_for(_cursor)
	if _cursor_ring.has(cell):
		draw_polyline(_cursor_ring[cell], palette.focus, CURSOR_STROKE)


## Three states, three silhouettes, so §21's colour-independence holds without a
## legend: a locked level is hatched, an open one is an outline, a completed one
## is filled. The pips underneath say the same thing a second time.
func _draw_level(cell: Vector3i, row: Dictionary) -> void:
	var state: State = row.get("state", State.LOCKED) as State
	var polygon: PackedVector2Array = _polygons[cell]

	match state:
		State.DONE:
			# §9: "completed levels fill with the path colour".
			draw_colored_polygon(polygon, palette.path_core)
			draw_polyline(polygon, palette.path_core.lightened(0.25), STROKE)
		State.OPEN:
			draw_colored_polygon(polygon, palette.cell_empty_fill)
			draw_polyline(polygon, palette.cell_candidate_stroke, STROKE + 0.5)
		State.LOCKED:
			draw_colored_polygon(polygon, palette.wall_fill)
			draw_polyline(polygon, palette.wall_stroke, STROKE)
			var lines: PackedVector2Array = _hatch[cell]
			for i: int in range(0, lines.size(), 2):
				draw_line(lines[i], lines[i + 1], palette.wall_stroke, 1.5)

	if state != State.LOCKED:
		_draw_number(cell, int(_cell_of[cell]), state)
		_draw_pips(cell, int(row.get("stars", 0)), bool(row.get("hinted", false)), state)


func _draw_number(cell: Vector3i, index: int, state: State) -> void:
	var text := str(index)
	# The number sits on the fill, so it takes the surface colour on a completed
	# level and the text colour on an open one.
	var colour: Color = palette.bg_deep if state == State.DONE else palette.text_primary
	var centre: Vector2 = _centres[cell]
	var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
	draw_string(
		_font, centre + Vector2(-w * 0.5, -float(_font_size) * 0.15), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, colour
	)


## §9's "star counts shown as 1–3 pips", plus §12.6's hint dot. A filled pip is a
## star earned and a hollow one is a star still there for the taking, so the
## number of pips never changes and the row can be read at a glance.
func _draw_pips(cell: Vector3i, stars: int, hinted: bool, state: State) -> void:
	var pips: PackedVector2Array = _pips[cell]
	var r: float = layout.size * 0.09
	var earned: Color = palette.bg_deep if state == State.DONE else palette.goal_cell
	var empty: Color = palette.cell_empty_stroke if state == State.DONE else palette.text_secondary
	for i: int in range(Scoring.MAX_STARS):
		if i < stars:
			draw_circle(pips[i], r, earned)
		else:
			draw_arc(pips[i], r, 0.0, TAU, 12, empty, 1.5)
	if hinted:
		# The fourth position is the hint dot, deliberately a different size and off
		# the row of three so it can never be miscounted as a star.
		draw_circle(pips[Scoring.MAX_STARS], r * 0.7, empty)


func _hexagon(centre: Vector2, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in layout.corners():
		out.append(centre + p * scale)
	out.append(out[0])
	return out


## The wall's 45° hatch, same angle and spacing as [BoardView] draws it, because a
## locked level and a wall mean the same thing to the player: not through here.
func _hatch_lines(centre: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var r: float = s * 0.6
	for i: int in range(-2, 3):
		var offset := Vector2(float(i) * r * 0.42, 0.0)
		out.append(centre + offset + Vector2(-r * 0.5, -r * 0.5))
		out.append(centre + offset + Vector2(r * 0.5, r * 0.5))
	return out


## Three star pips centred under the number, plus one slot for the hint dot.
func _pip_centres(centre: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var gap: float = s * 0.26
	var y: float = centre.y + s * 0.45
	for i: int in range(Scoring.MAX_STARS):
		out.append(Vector2(centre.x + (float(i) - 1.0) * gap, y))
	out.append(Vector2(centre.x + 2.1 * gap, y))
	return out

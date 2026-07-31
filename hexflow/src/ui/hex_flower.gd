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

## Drawn a little narrower than the cell, so the surface shows between tiles and a
## body has somewhere to be seen. [BoardTiles.TILE_INSET]'s reason, and a shade
## more of it: the board reads its gaps through an oblique camera that separates
## the rows for it, and the map is head-on.
const TILE_INSET := 0.90

## The surface the tiles stand on, as a scale on each cell. At 1.0 the cells
## tessellate exactly, so their union is a continuous plate in the shape of the
## flower; a hair over it, so no seam can open on a rounding error.
##
## This is the thing the board has for free and the map did not: a board plane.
## Without it every gap between tiles was a window onto whatever the illustration
## was doing there — on chapter 1 that is the sun going down, and a bar of sunset
## between two stone tiles reads as a rendering fault rather than as scenery.
## Opaque rather than a scrim, because overlapping translucent hexagons band where
## they overlap and the banding follows the lattice, which looks like a bug too.
const PLATE_SCALE := 1.03

## How tall each state stands, as a fraction of the circumradius — [BoardTiles]'
## own three heights, so the map's steps are the board's steps rather than a
## second set of numbers that drift apart from them.
##
## What the height *means* is the one thing that differs, and deliberately. On the
## board C-22 puts a tile's **kind** in its height and a wall is the tallest thing
## on it. On the map there are no kinds, only progress, so the same three numbers
## are assigned in progress order: a locked level is a thin plate, an open one
## stands up, a finished one stands proudest. Height still rises with "more", it
## is simply more of something else.
const HEIGHT := {
	State.LOCKED: BoardTiles.EMPTY_TOP,
	State.OPEN: BoardTiles.PATH_TOP,
	State.DONE: BoardTiles.WALL_TOP,
}

## The board's heights are read through §12.3's oblique camera, which foreshortens
## them; the map is head-on, where the same numbers stand a little too tall. The
## ordering and the ratios between the steps are what C-22 is about, and scaling
## preserves both.
const HEIGHT_SCALE := 0.9

## The tallest body, in circumradii — what [method fit] has to leave room for
## below the bottom row.
const MAX_BODY: float = BoardTiles.WALL_TOP * HEIGHT_SCALE

## `assets/art/tile_face.png` is a 2×2 atlas of drawn hexagon faces (C-26).
const FACE_CELLS := 2
## How much of an atlas cell one tile's face samples. A hair under the whole cell,
## so a filtered fetch at the rim cannot reach into the neighbouring drawing.
const FACE_FILL := 0.98
## The drawn face is a **value** map: mid-grey is neutral and the shader doubles it
## before multiplying (`hex_prism.gdshader`'s `texture(face_map, at).r * 2.0`).
## A canvas polygon has no shader to do that in, so the doubling rides in the
## vertex colour instead and the arithmetic comes out the same.
const FACE_GAIN := 1.65

## How far a body is pulled toward `board_tile_side` from the colour of its own
## face. Not all the way: a prism's side is the *same stone* with less light on it,
## and a body in a flat neutral makes every tile look like a sticker on one block.
## This is the 2D reading of what `hex_prism.gdshader` does with `side_ink`.
const BODY_TOWARD_SIDE := 0.62

## How much lighter the right-hand facet is than the left. The board is lit by one
## key light from the upper right (`board_key_light`); two facets at one flat value
## have no light in them at all.
const BODY_LIGHT := 0.12
const BODY_SHADE := 0.22

enum State { LOCKED, OPEN, DONE }

@export var palette: Palette = null

var layout: HexLayout = null

## `index -> {state, stars, hinted}`, one entry per level, filled by [method bind].
var _rows: Array[Dictionary] = []
var _centres: Dictionary = {}          # Vector3i -> Vector2
var _cell_of: Dictionary = {}          # Vector3i -> level index
var _polygons: Dictionary = {}         # Vector3i -> PackedVector2Array
var _plates: Dictionary = {}           # Vector3i -> PackedVector2Array, the surface under it
var _uvs: Dictionary = {}              # Vector3i -> PackedVector2Array into the face atlas
var _body: Dictionary = {}             # Vector3i -> [left quad, right quad]
var _cursor_ring: Dictionary = {}      # Vector3i -> PackedVector2Array
var _hatch: Dictionary = {}            # Vector3i -> PackedVector2Array of line pairs
var _pips: Dictionary = {}             # Vector3i -> PackedVector2Array of pip centres
## Cell indices sorted back to front. A body hangs below its own tile and has to
## be covered by whatever stands in front of it, which on a head-on map is
## whatever is lower down the screen.
var _order: Array[int] = []
var _face: Texture2D = null
var _cursor: int = 1
var _font: Font = null
var _font_size: int = 18


func _ready() -> void:
	if palette == null:
		palette = Palette.current()
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
	_plates.clear()
	_uvs.clear()
	_body.clear()
	_cursor_ring.clear()
	_hatch.clear()
	_pips.clear()
	_font_size = maxi(Typography.FLOOR_PX, int(s * 0.42))
	# C-26's drawn tile top, if this build has one. Optional in exactly the sense
	# every other art file is (§13.6): with no file the map draws the flat faces it
	# always drew and loses nothing it depends on.
	_face = Art.tile_face()

	for i: int in range(CELLS.size()):
		var cell: Vector3i = CELLS[i]
		var centre: Vector2 = layout.to_pixel(cell)
		var state: State = _state_of(i)
		_centres[cell] = centre
		_cell_of[cell] = i + 1
		_polygons[cell] = _hexagon(centre, TILE_INSET)
		_plates[cell] = _hexagon(centre, PLATE_SCALE)
		_uvs[cell] = _face_uvs(i + 1)
		_body[cell] = _body_quads(centre, s * float(HEIGHT[state]) * HEIGHT_SCALE)
		_cursor_ring[cell] = _hexagon(centre, CURSOR_SCALE * CURSOR_GROW)
		_hatch[cell] = _hatch_lines(centre, s)
		_pips[cell] = _pip_centres(centre, s)

	# Back to front, so a body is covered by whatever stands in front of it.
	_order = []
	for i: int in range(CELLS.size()):
		_order.append(i)
	_order.sort_custom(func(a: int, b: int) -> bool:
		return float(_centres[CELLS[a]].y) < float(_centres[CELLS[b]].y))
	queue_redraw()


func _state_of(i: int) -> State:
	if i >= _rows.size():
		return State.LOCKED
	return _rows[i].get("state", State.LOCKED) as State


## The largest circumradius whose whole flower plus [constant HexLayout.MARGIN]
## on every side fits inside [param box] — §4.4's fit rule, over this shape's own
## span rather than a board's.
##
## The vertical span carries [constant MAX_BODY] on top of the geometry now: a
## tile's body hangs below it, and a bottom row whose bodies are cut off by the
## footer is a flower that does not fit however well its centres do.
static func fit(box: Vector2) -> int:
	var usable := box - Vector2(HexLayout.MARGIN, HexLayout.MARGIN) * 2.0
	return maxi(16, int(floor(minf(usable.x / SPAN_X, usable.y / (SPAN_Y + MAX_BODY)))))


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
	# The surface first, whole, before any tile stands on it.
	for cell: Vector3i in CELLS:
		draw_colored_polygon(_plates[cell], palette.bg_panel)
	for i: int in _order:
		_draw_level(CELLS[i], _rows[i])
	var cell: Vector3i = cell_for(_cursor)
	if _cursor_ring.has(cell):
		draw_polyline(_cursor_ring[cell], palette.focus, CURSOR_STROKE)


## One level as one tile, drawn the way the board draws one: a body standing on the
## surface, the drawn stone face on top of it and the board's own ink around it.
##
## Three states still get three *silhouettes*, which is what §21 and C-25 are
## actually asking for — the colour-independent cue is now the height as well as
## the pattern, and height is the cue C-22 already chose for the board. A locked
## level is a thin hatched plate, an open one stands up, a completed one stands
## proudest and takes the path colour §9 asks for.
func _draw_level(cell: Vector3i, row: Dictionary) -> void:
	var state: State = row.get("state", State.LOCKED) as State
	var polygon: PackedVector2Array = _polygons[cell]
	var fill: Color = _fill_of(state)

	_draw_body(cell, fill)

	if _face != null:
		# The value map, doubled in the vertex colour so mid-grey comes out neutral
		# — `hex_prism.gdshader` does the same multiply per pixel.
		var lit := Color(fill.r * FACE_GAIN, fill.g * FACE_GAIN, fill.b * FACE_GAIN, 1.0)
		draw_colored_polygon(polygon, lit, _uvs[cell], _face)
	else:
		draw_colored_polygon(polygon, fill)

	# §6's hatch, on the locked plate, for the same reason a wall carries one: it is
	# the cue that survives colour going away, and the map means the same thing by
	# it that the board does — not through here.
	if state == State.LOCKED:
		var lines: PackedVector2Array = _hatch[cell]
		for i: int in range(0, lines.size(), 2):
			draw_line(lines[i], lines[i + 1], palette.wall_stroke, 1.5)

	draw_polyline(polygon, _stroke_of(state), STROKE)
	_draw_number(cell, int(_cell_of[cell]), state)
	# No pips on a locked level: three hollow circles under every number is a row of
	# nothing repeated eleven times, and the stars it is offering cannot be won yet.
	if state != State.LOCKED:
		_draw_pips(cell, int(row.get("stars", 0)), bool(row.get("hinted", false)), state)


## The two facets below the tile, which is what turns a hexagon into something
## standing on the map rather than a shape printed on it.
func _draw_body(cell: Vector3i, fill: Color) -> void:
	var quads: Array = _body[cell]
	var side: Color = fill.lerp(palette.board_tile_side, BODY_TOWARD_SIDE)
	draw_colored_polygon(quads[0] as PackedVector2Array, side.darkened(BODY_SHADE))
	draw_colored_polygon(quads[1] as PackedVector2Array, side.lightened(BODY_LIGHT))


func _fill_of(state: State) -> Color:
	match state:
		State.DONE:
			return palette.path_core     # §9: "completed levels fill with the path colour"
		State.OPEN:
			return palette.cell_empty_fill
		_:
			return palette.wall_fill


func _stroke_of(state: State) -> Color:
	match state:
		State.DONE:
			return palette.path_core.lightened(0.25)
		State.OPEN:
			return palette.cell_candidate_stroke
		_:
			return palette.wall_stroke


## Every level is numbered, including the locked ones.
##
## They were not, and the result was a chapter that opened as eleven identical
## hatched blanks and one number: a map that will not say which level is which is
## not doing the job of a map. The lock is a *state* of level 7, not a reason to
## stop calling it level 7 — and the cursor is allowed to rest on it and read its
## par out of the footer already.
func _draw_number(cell: Vector3i, index: int, state: State) -> void:
	var text := str(index)
	# The number sits on the fill, so it takes the surface colour on a completed
	# level and the text colour on an open one. A locked level's number is dimmed
	# to the secondary text colour: legible, and plainly not an invitation.
	var colour: Color = palette.bg_deep if state == State.DONE else (
		palette.text_primary if state == State.OPEN else palette.text_secondary)
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


## The tile's body, as the two quads under its lower silhouette.
##
## Two quads rather than one polygon because both are parallelograms and a
## parallelogram needs no triangulation to be right, where the six-point extrusion
## they add up to is concave at the bottom vertex. They are also the two facets the
## light actually falls on differently, so the split is not only arithmetic.
##
## Corner order is [method HexLayout.corners]': index 1 is the lower right, 2 the
## bottom vertex, 3 the lower left. Those three are the whole of what a head-on
## hexagon shows of its own underside.
func _body_quads(centre: Vector2, height: float) -> Array:
	var c: PackedVector2Array = layout.corners()
	var down := Vector2(0.0, height)
	var right: Vector2 = centre + c[1] * TILE_INSET
	var bottom: Vector2 = centre + c[2] * TILE_INSET
	var left: Vector2 = centre + c[3] * TILE_INSET
	return [
		PackedVector2Array([left, bottom, bottom + down, left + down]),
		PackedVector2Array([bottom, right, right + down, bottom + down]),
	]


## Where this tile's face samples `assets/art/tile_face.png` — one of the atlas's
## four drawn hexagons, at one of its six orientations.
##
## Chosen from the level number rather than from an RNG. `src/` has no global
## random at all (C2), and this is a case where the rule and the design agree
## anyway: a map whose stonework reshuffled itself every time the player paged back
## to it would be worse than one that never varied.
##
## A 60° turn maps a hexagon onto itself, so turning the *corners* before
## normalising turns the drawing and leaves the silhouette exactly where it was.
func _face_uvs(index: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if _face == null:
		return out
	var atlas: int = (index * 5) % (FACE_CELLS * FACE_CELLS)
	var turn: float = float((index * 7) % 6) * (TAU / 6.0)
	var cell := Vector2(float(atlas % FACE_CELLS), float(atlas / FACE_CELLS))
	for p: Vector2 in layout.corners():
		# The tile's diameter spans the atlas cell, which is `hex_prism.gdshader`'s
		# own mapping — one convention for the drawn face, in both renderers.
		var f: Vector2 = p.rotated(turn) / (layout.size * 2.0) * FACE_FILL + Vector2(0.5, 0.5)
		out.append((cell + f) / float(FACE_CELLS))
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

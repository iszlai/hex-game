## The hex canvas: flat 2D, pan, zoom, paint (MAP-EDITOR §3).
##
## **Flat 2D is decided, and it is not only the cheaper option.** The editor is
## about *contents* and the game is about *feel*. A board drawn at the game's 55°
## elevation hides half of what an author needs to see — the far side of a tall
## wall, the cell behind a mark — and an editor whose whole job is to show every
## cell exactly should not be fighting a camera to do it.
##
## [HexLayout] is reused for the geometry, so there is still exactly one hexagon
## formula in the repo, and [Palette] for the colours, so an editor board and a
## game board are recognisably the same level.
##
## Nothing allocates per cell in [method _draw]. The six corners are built once by
## [HexLayout] and each hexagon is drawn under [method CanvasItem.draw_set_transform]
## rather than by building a translated polygon — the same rule as C4, for the same
## reason, on a canvas that redraws on every mouse move.
##
## Not part of the shipped game.
class_name MapCanvas
extends Control

## Emitted for each new cell a drag passes over. [param erase] is the right button.
signal painted(cell: Vector3i, erase: bool)
signal hovered(cell: Vector3i)

const MIN_ZOOM := 12.0
const MAX_ZOOM := 90.0
const ZOOM_STEP := 1.12

## How far past the board's edge empty cells are offered to paint on. Two rings:
## one is not enough to grow a board in any useful direction, and the whole plane
## would be a screen of grey outlines with the level lost in it.
const GHOST_RINGS := 2

## How strongly the paintable halo is drawn, against the board's full strength.
const GHOST_ALPHA := 0.35

var draft: MapDraft = null
var brush: int = MapDraft.Content.WALL

var _layout: HexLayout = HexLayout.new(42.0)
var _pan: Vector2 = Vector2.ZERO
var _ghosts: Array[Vector3i] = []
var _hover: Vector3i = Hex.NONE
var _painting: bool = false
var _erasing: bool = false
var _last_painted: Vector3i = Hex.NONE
var _panning: bool = false
var _outline: PackedVector2Array = PackedVector2Array()
var _font: Font = null
## Whether the board has been fitted to a canvas that had a size yet. [method
## bind] runs from `_ready`, where a `Control` is still zero by zero and
## [method HexLayout.fit] can only return its floor — so the first real layout
## pass is what actually frames the board.
var _framed: bool = false


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	_rebuild_outline()
	resized.connect(_recentre)


func bind(p_draft: MapDraft) -> void:
	draft = p_draft
	refresh()
	frame()


## Call after any edit. Recomputes the paintable halo and redraws — cheap enough
## to do per stroke, and the alternative is a canvas that disagrees with the model.
func refresh() -> void:
	_rebuild_ghosts()
	queue_redraw()


## Sizes and centres the board in the view, the way §4.4 fits one on screen. The
## halo of paintable cells is included in the fit, so growing a board outward has
## somewhere to grow into without an immediate scroll.
func frame() -> void:
	_framed = size.x > 1.0 and size.y > 1.0
	_pan = Vector2.ZERO
	if draft == null or draft.cells.is_empty() or not _framed:
		_layout.set_size(42.0)
	else:
		var radius: int = maxi(1, Hex.bounding_radius(_board_cells()) + GHOST_RINGS)
		_layout.set_size(float(HexLayout.fit(radius, size)))
	_rebuild_outline()
	_recentre()


func _recentre() -> void:
	# The first layout pass with a real size is the one that can frame anything.
	# Without this the board is drawn at `HexLayout.fit`'s floor — a thumbnail in
	# the corner of an empty canvas, which is what a zero-sized `Control` asks for.
	if not _framed and size.x > 1.0 and size.y > 1.0:
		frame()
		return
	_layout.origin = size * 0.5 + _pan
	queue_redraw()


func _rebuild_outline() -> void:
	_outline = PackedVector2Array()
	for corner: Vector2 in _layout.corners():
		_outline.append(corner)
	_outline.append(_layout.corners()[0])


## Every cell within [constant GHOST_RINGS] of the board that is not on it — what
## the board brush may add. Without these an author can only ever cut a shape
## down, never grow one, which §4.3 explicitly wants to allow.
func _rebuild_ghosts() -> void:
	_ghosts = []
	if draft == null:
		return
	var seen: Dictionary = {}
	var frontier: Array[Vector3i] = _board_cells()
	for _ring: int in range(GHOST_RINGS):
		var next: Array[Vector3i] = []
		for c: Vector3i in frontier:
			for dir: int in Direction.ALL:
				var n: Vector3i = c + Direction.delta(dir)
				if draft.has(n) or seen.has(n):
					continue
				seen[n] = true
				next.append(n)
		_ghosts.append_array(next)
		frontier = next
	_ghosts = Hex.sort_cells(_ghosts)


func _board_cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if draft == null:
		return out
	for c: Variant in draft.cells.keys():
		out.append(c as Vector3i)
	return Hex.sort_cells(out)


# --- drawing -------------------------------------------------------------------

func _draw() -> void:
	var palette := Palette.current()
	draw_rect(Rect2(Vector2.ZERO, size), palette.bg_deep, true)
	if draft == null:
		return

	# The halo is a hint, not content. At full strength it out-shouts the board it
	# surrounds — there are more ghosts than cells on a small board — so it is the
	# candidate stroke dimmed rather than a colour of its own, and still a palette
	# token so §21's four palettes reach it.
	var ghost := Color(palette.cell_candidate_stroke, GHOST_ALPHA)
	for c: Vector3i in _ghosts:
		draw_set_transform(_layout.to_pixel(c))
		draw_polyline(_outline, ghost, 1.0)

	for c: Vector3i in _board_cells():
		var kind: int = int(draft.content_at(c))
		draw_set_transform(_layout.to_pixel(c))
		draw_colored_polygon(_layout.corners(), _fill_for(palette, kind))
		draw_polyline(_outline, _stroke_for(palette, kind), 2.0)
		_draw_letter(palette, c, kind)

	# The hover ring last, so it sits over whatever it is on top of. Drawn as a
	# heavier stroke rather than a tint: §21's rule that a state is readable
	# without colour is the game's, but an author staring at seven fills all day
	# benefits from it just as much.
	if _hover != Hex.NONE and (draft.has(_hover) or _is_ghost(_hover)):
		draw_set_transform(_layout.to_pixel(_hover))
		draw_polyline(_outline, palette.focus, 3.0)
	draw_set_transform(Vector2.ZERO)


func _draw_letter(palette: Palette, c: Vector3i, kind: int) -> void:
	var text: String = MapDraft.LETTERS[kind]
	if kind == int(MapDraft.Content.PORTAL):
		# Both ends of one door carry the same number, so an author can see *which*
		# portal goes where on a board with two pairs on it. A single "P" on four
		# cells is the version of this that looks finished and answers nothing.
		text += str(draft.portal_index(c))
	if text == "":
		return
	var font_size: int = maxi(8, int(_layout.size * 0.55))
	var half: float = _layout.size
	draw_string(_font, Vector2(-half, float(font_size) * 0.36), text,
		HORIZONTAL_ALIGNMENT_CENTER, half * 2.0, font_size, palette.board_mark_outline)
	draw_string(_font, Vector2(-half, float(font_size) * 0.36 - 1.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, half * 2.0, font_size, palette.text_primary)


func _fill_for(palette: Palette, kind: int) -> Color:
	match kind:
		int(MapDraft.Content.WALL): return palette.wall_fill
		int(MapDraft.Content.START): return palette.start_cell
		int(MapDraft.Content.GOAL): return palette.goal_cell
		int(MapDraft.Content.PORTAL): return palette.portal
		int(MapDraft.Content.GATE): return palette.gate
		int(MapDraft.Content.WILD): return palette.wild
		_: return palette.cell_empty_fill


func _stroke_for(palette: Palette, kind: int) -> Color:
	return palette.wall_stroke if kind == int(MapDraft.Content.WALL) \
		else palette.cell_empty_stroke


func _is_ghost(c: Vector3i) -> bool:
	return _ghosts.has(c)


# --- input ---------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_motion(event as InputEventMouseMotion)


func _on_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom_by(ZOOM_STEP, event.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom_by(1.0 / ZOOM_STEP, event.position)
		MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
			_painting = event.pressed
			_erasing = event.button_index == MOUSE_BUTTON_RIGHT
			if event.pressed:
				grab_focus()
				_last_painted = Hex.NONE
				_paint_at(event.position)
			accept_event()


func _on_motion(event: InputEventMouseMotion) -> void:
	if _panning:
		_pan += event.relative
		_recentre()
		return
	var cell := _layout.from_pixel(event.position)
	if cell != _hover:
		_hover = cell
		hovered.emit(cell)
		queue_redraw()
	if _painting:
		_paint_at(event.position)


## One emission per cell per stroke. A drag crosses the same hexagon on twenty
## motion events, and a brush that toggles would flicker rather than paint.
func _paint_at(where: Vector2) -> void:
	var cell := _layout.from_pixel(where)
	if cell == _last_painted:
		return
	_last_painted = cell
	painted.emit(cell, _erasing)


## Zoom about the cursor, so the cell under the mouse stays under the mouse. The
## naive version zooms about the centre and an author loses their place on every
## scroll.
func _zoom_by(factor: float, at: Vector2) -> void:
	var before := _layout.from_pixel(at)
	var wanted: float = clampf(_layout.size * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(wanted, _layout.size):
		return
	_layout.set_size(wanted)
	_rebuild_outline()
	_recentre()
	_pan += at - _layout.to_pixel(before)
	_recentre()

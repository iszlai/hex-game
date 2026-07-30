## The C-18 board's screen surface: cube ↔ screen through the orthographic camera.
##
## A `SubViewportContainer`, so the 3D board occupies exactly §12.3's play area and
## the sub-viewport's coordinates **are** the coordinates the level screen already
## works in — the same space [method BoardView.centres] answers in and the same
## space its pointer conversion lands in. That is what lets the M7 view drop in
## without [InputRouter] or the level screen learning anything new: they keep
## receiving screen-space positions and simply follow the camera (C-18).
##
## Two directions, deliberately asked of two different yaws:
##
## - **A pointer** is resolved against the *live* camera, so a click lands on the
##   cell that is under the finger at that instant, even mid-rotation.
## - **Directional input** works from the stop the player is *heading to*, so a
##   press during the 260 ms tween behaves like the board they are about to see.
##
## Both are the best available answer, and both are computed once per event — never
## per frame (C4).
##
## The meshes are not here yet: this is the camera, the layout and the screen-space
## mapping. `BoardView`'s grey-box stays the headless/test view until the prisms
## land, per §26's sequencing note.
class_name BoardView3D
extends SubViewportContainer

## Height of a tile above the plane as a fraction of the cell circumradius, which
## the fit has to reserve room for (§4.4 against the projected bounds). Zero until
## the prisms exist.
const TILE_TOP_RATIO := 0.0

## Emitted when the cached screen positions have changed and anything holding them
## — §11.2's candidate set, the cursor ring — needs re-feeding.
signal screen_positions_changed

@export var palette: Palette = null

var camera: BoardCamera = null
var viewport: SubViewport = null
var layout: HexLayout = null

var _board: Board = null
var _state: GameState = null
var _screen: Dictionary = {}     # Vector3i -> Vector2, in sub-viewport pixels


func _ready() -> void:
	if palette == null:
		palette = load("res://src/data/palettes/neon_dark.tres")
	stretch = true
	# A `Control` that keeps Godot's default STOP swallows every mouse and touch
	# event in the GUI pass before `_unhandled_input` sees one. That is exactly the
	# defect that kept pointer input from reaching the level screen through all of
	# M3 (B7): this node must never re-introduce it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_nodes()


## Binds a level and sizes the board to [param play_area] (§4.4, projected). Called
## once per level, never per frame.
func bind(state: GameState, play_area: Vector2) -> void:
	_ensure_nodes()
	_state = state
	_board = state.board
	# `stretch` keeps the sub-viewport exactly this size, synchronously, which is
	# what makes container coordinates and viewport coordinates the same numbers.
	# Never set the viewport's size directly — with stretch on, Godot refuses it.
	size = play_area
	layout = HexLayout.new(float(BoardCamera.fit_projected(_board.radius, play_area,
		TILE_TOP_RATIO)))
	camera.frame_play_area(play_area)
	_recompute_positions(camera.yaw_radians())


## Turns the board a whole number of 60° stops, clockwise for positive (§14.3 as
## amended by C-18). The screen positions jump to the target stop immediately; the
## camera tweens there.
func rotate_by(steps: int) -> void:
	if steps == 0 or camera == null:
		return
	camera.rotate_by(steps)
	_recompute_positions(BoardCamera.YAW_STOP_RADIANS * float(camera.yaw_step))


## Cell → screen position for every cell of the board, which is what [InputRouter]
## wants: §11.2's ±75° cone and its clockwise cycling are both computed from these,
## so rotating the camera rotates the controls with it and neither has to know.
func centres() -> Dictionary:
	return _screen


func centre_of(cell: Vector3i) -> Vector2:
	return _screen.get(cell, centre_on_screen())


## The board's own centre on screen. The camera orbits `(0,0,0)`, so this is the
## middle of the play area at every stop — the fixed point §11.2 sorts bearings
## around.
func centre_on_screen() -> Vector2:
	return Vector2(viewport.size) * 0.5 if viewport != null else Vector2.ZERO


## Hit-testing goes camera ray → `y = 0` → cube rounding, never through raw screen
## coordinates (B7). [param local_point] is in this container's own space, which is
## the sub-viewport's space.
func cell_at(local_point: Vector2) -> Vector3i:
	if camera == null or layout == null:
		return Vector3i.ZERO
	return layout.from_plane(camera.plane_point(local_point))


func _ensure_nodes() -> void:
	if viewport != null:
		return
	viewport = SubViewport.new()
	viewport.name = "BoardViewport"
	# The board gets a world of its own so nothing else in the scene can light it
	# or appear in it by accident.
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	add_child(viewport)
	camera = BoardCamera.new()
	camera.name = "BoardCamera"
	viewport.add_child(camera)


func _recompute_positions(yaw: float) -> void:
	_screen.clear()
	if _board == null:
		return
	for c: Vector3i in _board.cells():
		_screen[c] = camera.unproject_at(layout.to_plane(c), yaw)
	screen_positions_changed.emit()

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

## Height of the tallest tile above the plane as a fraction of the cell
## circumradius, which the fit has to reserve room for (§4.4 against the projected
## bounds). Owned by [BoardTiles], because that is what stands things up.
const TILE_TOP_RATIO := BoardTiles.MAX_TOP

## Emitted when the cached screen positions have changed and anything holding them
## — §11.2's candidate set, the cursor ring — needs re-feeding.
signal screen_positions_changed

@export var palette: Palette = null

var camera: BoardCamera = null
var viewport: SubViewport = null
var tiles: BoardTiles = null
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
	tiles.bind(state, layout)
	_recompute_positions(camera.yaw_radians())


## The rest of [BoardView]'s surface, so the two views are interchangeable to the
## level screen: the same four calls, in the same order, meaning the same things.
func rebuild() -> void:
	tiles.rebuild()


func set_candidates(targets: Array[Vector3i]) -> void:
	tiles.set_candidates(targets)


func set_cursor(cell: Vector3i, visible_cursor: bool = true) -> void:
	tiles.set_cursor(cell, visible_cursor)


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


## A whole-window position — where a click or a finger actually arrives — brought
## into the board's own space. A `Control` has no `to_local`, and subtracting the
## board's offset by hand at the call site is how a screen with a top bar ends up
## hit-testing one row out, so the conversion lives here with the thing it converts.
func local_point(at: Vector2) -> Vector2:
	return at - global_position


## The inverse: where [param cell] is on the window, for aiming a pointer at it.
func screen_position_of(cell: Vector3i) -> Vector2:
	return global_position + centre_of(cell)


func _ensure_nodes() -> void:
	if viewport != null:
		return
	viewport = SubViewport.new()
	viewport.name = "BoardViewport"
	# The board gets a world of its own so nothing else in the scene can light it
	# or appear in it by accident.
	viewport.own_world_3d = true
	add_child(viewport)
	camera = BoardCamera.new()
	camera.name = "BoardCamera"
	viewport.add_child(camera)
	# One node for the whole board, so one draw call covers it (§13.3). The camera
	# orbits the world origin, so board space and world space are the same space.
	tiles = BoardTiles.new()
	tiles.name = "BoardTiles"
	tiles.palette = palette
	viewport.add_child(tiles)
	_add_lighting()


## One key light and one environment, both fixed in world space.
##
## Fixed is the point: the light does not follow the yaw, so turning the board moves
## the shadows across it and the rotation reads as a rotation. It sits high and to
## one side, which is what gives C-22's tile heights something to cast — the height
## *is* the colour-independent channel, and a light straight down would flatten it.
##
## §14.3 is unaffected: this is not camera motion, and nothing here moves at all.
func _add_lighting() -> void:
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_color = palette.board_key_light
	key.light_energy = 1.15
	# Down 50°, and yawed off the camera's opening axis so the prism sides that face
	# the viewer are not the ones in full shadow.
	key.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	key.shadow_enabled = true
	# The tiles are the only casters and they are all within a board's width, so the
	# split can stay tight and the shadows stay sharp.
	key.directional_shadow_max_distance = BoardCamera.DISTANCE * 0.5
	viewport.add_child(key)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = palette.bg_deep
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = palette.board_ambient
	env.ambient_light_energy = 0.95
	var holder := WorldEnvironment.new()
	holder.name = "BoardEnvironment"
	holder.environment = env
	viewport.add_child(holder)


func _recompute_positions(yaw: float) -> void:
	_screen.clear()
	if _board == null:
		return
	for c: Vector3i in _board.cells():
		_screen[c] = camera.unproject_at(layout.to_plane(c), yaw)
	screen_positions_changed.emit()

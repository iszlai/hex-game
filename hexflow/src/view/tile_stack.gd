## The tiles waiting to be played, as physical pieces rather than as words —
## §12.3's NOW tile and NEXT pair, which C-18 turns into a stack.
##
## The same prism the board is built from, seen at the same elevation, in a
## viewport of its own: a piece in the rail and the tile it becomes on the board
## are visibly the same object, which is the whole reason C-18 asked for a stack
## instead of two labels.
##
## The arrow on a piece points where that tile will actually go — including after
## the player turns the board. A direction is a lattice step, and which way a
## lattice step runs on screen depends on the yaw, so the arrows follow the board
## round ([method BoardCamera.screen_angle]). An arrow that always pointed the same
## way would be a lie at five of the six stops.
##
## Two multimeshes, both prebuilt: the pieces and their arrows. Nothing allocates
## after [method bind] and there is no `_process` (C4).
class_name TileStack
extends SubViewportContainer

## Circumradius of the front piece, in this viewport's own world units. The camera
## is sized in the same units, so these numbers are the layout.
const PIECE := 1.0
const PIECE_HEIGHT := 0.30

## How far along the deck each further piece sits, and how much smaller it is.
## Overlapping is what makes it read as a stack rather than as a row.
const SPREAD := 1.04
const RECEDE := 0.22
const SHRINK := 0.12

## World height the camera frames. One piece is 2 units across and the projection
## foreshortens its depth to sin 55°, so this leaves a margin at every slot count.
const FRAME := 2.35

## Arrow radius as a fraction of the piece it sits on.
const ARROW_RATIO := 0.62

## The arrow's silhouette in `hex_mark.gdshader`, which the board's marks share.
## Not a [BoardMarks.Mark]: a direction is not a cell modifier, and §6 ships
## exactly five of those.
const ARROW_GLYPH := 4

@export var palette: Palette = null

## How many upcoming tiles this control shows. One for NOW, more for NEXT.
@export var slots: int = 1

var viewport: SubViewport = null
var camera: Camera3D = null
var pieces: MultiMeshInstance3D = null
var arrows: MultiMeshInstance3D = null

var _tiles: Array[int] = []
var _yaw: float = 0.0


func _ready() -> void:
	if palette == null:
		palette = load("res://src/data/palettes/neon_dark.tres")
	stretch = true
	# Same reason as [BoardView3D]: a `Control` that keeps Godot's default STOP
	# swallows pointer events before `_unhandled_input` ever sees them (B7).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_nodes()
	SettingsService.changed.connect(_on_setting_changed)


## Shows [param tiles] — direction indices, soonest first. Called when the stream
## advances, which is once per move.
func show_tiles(tiles: Array[int]) -> void:
	_ensure_nodes()
	_tiles = tiles
	_rebuild()


## Follows the board: [param yaw] is the board camera's, not this one's.
func set_board_yaw(yaw: float) -> void:
	_yaw = yaw
	_rebuild()


func count() -> int:
	return mini(_tiles.size(), slots)


## Where piece [param i] stands. The soonest tile is the front of the deck, so it
## is the biggest and the one nothing overlaps.
func piece_transform(i: int) -> Transform3D:
	var scale: float = PIECE * (1.0 - SHRINK * float(i))
	return Transform3D(
		Basis().scaled(Vector3(scale, PIECE_HEIGHT * PIECE, scale)),
		Vector3(_slot_x(i), 0.0, -RECEDE * float(i))
	)


## Where the arrow on piece [param i] floats, and how big. Sat on the piece's top
## face, like a cell modifier sits on its tile.
func arrow_transform(i: int) -> Transform3D:
	var t: Transform3D = piece_transform(i)
	var radius: float = t.basis.get_scale().x * ARROW_RATIO
	return Transform3D(
		Basis().scaled(Vector3.ONE * radius),
		t.origin + Vector3.UP * (t.basis.get_scale().y + 0.02)
	)


## The arrow's silhouette and the angle it is drawn at — the direction's angle on
## the **board**, so a turn of the board turns every arrow in the rail with it.
func arrow_custom(i: int) -> Color:
	var delta: Vector3 = HexLayout.new(1.0).to_plane(Direction.delta(_tiles[i]))
	# Negated: [method BoardCamera.screen_angle] answers in the y-down screen space
	# every other position in this project is expressed in, and the shader's glyph
	# space has y up. Without the sign an SE tile draws a NE arrow — which is a lie
	# a player would follow.
	return Color(float(ARROW_GLYPH), 0.0, -BoardCamera.screen_angle(delta, _yaw), 0.0)


## The soonest tile reads as live and the rest as waiting — the same distinction
## the text HUD made with its NOW and NEXT captions, in ink rather than in words.
func piece_tint(i: int) -> Color:
	return palette.path_core if i == 0 else palette.cell_empty_fill.lerp(
		palette.cell_candidate_stroke, 0.55)


func arrow_tint(i: int) -> Color:
	return palette.text_primary if i == 0 else palette.text_secondary


## The rail follows the board (C-24): a piece here is the tile it becomes over
## there, so it cannot still be catching a highlight once the board has stopped.
func set_flat(flat: bool) -> void:
	if pieces != null and pieces.material_override is ShaderMaterial:
		(pieces.material_override as ShaderMaterial).set_shader_parameter("flat_board", flat)


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "flat_board":
		set_flat(bool(value))


func _slot_x(i: int) -> float:
	# Centred on the control, so a stack of one is not off to the left.
	return (float(i) - float(maxi(slots, 1) - 1) * 0.5) * SPREAD * 2.0 * 0.5


func _rebuild() -> void:
	if pieces == null:
		return
	var live: int = count()
	for i: int in range(live):
		pieces.multimesh.set_instance_transform(i, piece_transform(i))
		pieces.multimesh.set_instance_color(i, piece_tint(i))
		pieces.multimesh.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))
		arrows.multimesh.set_instance_transform(i, arrow_transform(i))
		arrows.multimesh.set_instance_color(i, arrow_tint(i))
		arrows.multimesh.set_instance_custom_data(i, arrow_custom(i))
	pieces.multimesh.visible_instance_count = live
	arrows.multimesh.visible_instance_count = live


func _ensure_nodes() -> void:
	if viewport != null:
		return
	viewport = SubViewport.new()
	viewport.name = "StackViewport"
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	add_child(viewport)

	camera = Camera3D.new()
	camera.name = "StackCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = FRAME
	camera.near = 1.0
	camera.far = BoardCamera.DISTANCE * 2.0
	# The board's own elevation, at the board's own opening yaw: a piece here and
	# the tile it becomes over there are drawn at the same angle.
	camera.transform = BoardCamera.transform_at(0.0)
	viewport.add_child(camera)

	pieces = _multimesh("StackPieces", BoardTiles.SHADER, BoardTiles.build_prism_mesh())
	set_flat(SettingsService.flat_board())
	arrows = _multimesh("StackArrows", BoardMarks.SHADER, BoardMarks.build_quad_mesh())
	var mat: ShaderMaterial = arrows.material_override
	mat.set_shader_parameter("outline", palette.board_mark_outline)

	var key := DirectionalLight3D.new()
	key.name = "StackLight"
	key.light_color = palette.board_key_light
	key.light_energy = 1.15
	key.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	viewport.add_child(key)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = palette.board_ambient
	env.ambient_light_energy = 0.95
	var holder := WorldEnvironment.new()
	holder.name = "StackEnvironment"
	holder.environment = env
	viewport.add_child(holder)


func _multimesh(node_name: String, shader: String, mesh: Mesh) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	# Sized for every slot the control will ever show, so advancing the stream
	# rewrites instances and never reallocates (C4).
	mm.instance_count = maxi(slots, 1)
	mm.visible_instance_count = 0
	node.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load(shader)
	node.material_override = mat
	viewport.add_child(node)
	return node

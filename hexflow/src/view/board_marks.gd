## The four cell modifiers of §6 as marks on the C-18 board: goal, portal, gate
## and wild, drawn over the tile they belong to.
##
## This exists to close a C5 gap. [BoardTiles] carries a tile's *kind* in its
## height (C-22), which is a channel a modifier cannot use — a goal is a mark on a
## tile, not a kind of tile, and two of the four sit on tiles that also change
## height as the path grows. So the modifiers get the second channel §21 asks for:
## a distinct **silhouette** per modifier, outlined so it reads against any tile
## colour, in a greyscale palette and in a monochrome screenshot.
##
## One `MultiMesh` again, one instance per mark, so the whole set is a second draw
## call however many marks a level carries (C-23 — a `Label3D` per cell would have
## been one node and one draw call each, and would have needed a font that §13.4
## has not vendored yet). The marks **billboard in the shader** from the camera's
## own basis: a mark is a screen-aligned quad, so it never rotates, shears or
## foreshortens as the board turns, and it is exactly as legible at each of the six
## 60° stops and at every yaw in between. Nothing recomputes per frame to achieve
## that — see `hex_mark.gdshader`.
##
## Marks stack concentrically when one cell carries two of them, the way the
## grey-box's rings did: the flags of §5.1 are a bitmask, so a cell that is both a
## goal and a gate is legal topology and must not draw one mark on top of another.
class_name BoardMarks
extends MultiMeshInstance3D

const SHADER := "res://src/view/shaders/hex_mark.gdshader"

## Mark codes, written into `INSTANCE_CUSTOM.r`. The shader draws one silhouette
## per code, so this is a wire format: append, never renumber.
enum Mark { GOAL = 0, PORTAL = 1, GATE = 2, WILD = 3 }

## Drawing order within a cell, and the order [method marks_on] reports in.
const ORDER: Array[Mark] = [Mark.GOAL, Mark.PORTAL, Mark.GATE, Mark.WILD]

## Half-width of a mark as a fraction of the cell circumradius. The tile top is
## [constant BoardTiles.TILE_INSET] wide and the projection foreshortens its depth
## to sin 55° = 0.82, so this has to clear 0.93 × 0.82 = 0.76 to stay on its own
## tile — and the glyph itself only fills 0.88 of the quad, leaving the outline
## room inside the edge.
const MARK_RATIO := 0.52

## Each further mark on the same cell is drawn inside the last one.
const STACK_SHRINK := 0.62

## Lift off the tile top, as a fraction of the circumradius. The mark does not
## depth-test (it must never be half-swallowed by the tile it labels), so this is
## not about z-fighting: an orthographic camera projects a vertical offset to a
## fixed number of pixels up the screen, and this is what keeps the mark centred
## on the tile *top* rather than on the plane the tile stands on.
const LIFT := 0.02

@export var palette: Palette = null

var _tiles: BoardTiles = null
var _board: Board = null
var _state: GameState = null
var _layout: HexLayout = null
var _marks: Array = []      # of [Vector3i cell, Mark, int ordinal within the cell]


func _ready() -> void:
	if palette == null:
		palette = Palette.current()


## Allocates one instance per mark on [param state]'s board and fills them. The
## marks themselves are topology, so the *set* never changes during a level; what
## changes is how high the tile under a mark stands and whether a gate is open,
## and both go through [method rebuild].
func bind(state: GameState, layout: HexLayout, tiles: BoardTiles) -> void:
	_state = state
	_board = state.board
	_layout = layout
	_tiles = tiles
	_marks = marks_on(_board)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = build_quad_mesh()
	mm.instance_count = _marks.size()
	multimesh = mm

	if material_override == null:
		var mat := ShaderMaterial.new()
		mat.shader = load(SHADER)
		mat.set_shader_parameter("outline", palette.board_mark_outline)
		material_override = mat
	set_motion()

	rebuild()


## §14.1's goal pulse, at §14.5's discretion — the period when it runs and zero
## when Reduce Motion has stopped it, exactly as the tiles' breathing works.
func set_motion() -> void:
	if material_override is ShaderMaterial:
		var period: float = Motion.seconds("goal_pulse") if Motion.loops("goal_pulse") else 0.0
		(material_override as ShaderMaterial).set_shader_parameter("pulse_seconds", period)


## Recomputes everything derived from the live state, in place: the tile under a
## mark may have stood up, and a gate may have become enterable. Called after each
## move, not each frame.
func rebuild() -> void:
	if multimesh == null:
		return
	for i: int in range(_marks.size()):
		multimesh.set_instance_transform(i, transform_of(i))
		multimesh.set_instance_color(i, tint_of(i))
		multimesh.set_instance_custom_data(i, custom_of(i))


## Every mark [param board] carries, as `[cell, Mark, ordinal]` triples in cell
## order and then in [constant ORDER]. `ordinal` counts the marks already on that
## cell, which is what makes the concentric stacking deterministic.
static func marks_on(board: Board) -> Array:
	var out: Array = []
	for c: Vector3i in board.cells():
		var ordinal: int = 0
		for m: Mark in ORDER:
			if not carries(board, c, m):
				continue
			out.append([c, m, ordinal])
			ordinal += 1
	return out


static func carries(board: Board, cell: Vector3i, mark: Mark) -> bool:
	match mark:
		Mark.GOAL:
			return board.is_goal(cell)
		Mark.PORTAL:
			return board.is_portal(cell)
		Mark.GATE:
			return board.is_gate(cell)
		_:
			return board.is_wild(cell)


func count() -> int:
	return _marks.size()


func cell_of(i: int) -> Vector3i:
	return _marks[i][0] as Vector3i


func mark_of(i: int) -> Mark:
	return _marks[i][1] as Mark


## Where mark [param i] floats and how big it is. The scale is uniform because the
## shader reads it as one radius — the quad is rebuilt around the camera's basis,
## so the transform's own orientation is never used and is deliberately left as
## the identity rather than pointing somewhere misleading.
func transform_of(i: int) -> Transform3D:
	var cell: Vector3i = cell_of(i)
	var radius: float = _layout.size * MARK_RATIO * pow(STACK_SHRINK, float(_marks[i][2]))
	var top: float = _tiles.top_of(cell) + _layout.size * LIFT
	return Transform3D(
		Basis().scaled(Vector3.ONE * radius),
		_layout.to_plane(cell) + Vector3.UP * top
	)


## What the mark *is*, for the shader: which silhouette, and whether a gate is
## currently enterable — §6 wants the lock to open the moment its condition
## becomes satisfiable, which is state, not topology.
func custom_of(i: int) -> Color:
	var open: bool = mark_of(i) == Mark.GATE \
		and Rules.gate_satisfied(_board, _state.path, cell_of(i))
	return Color(float(mark_of(i)), 1.0 if open else 0.0, 0.0, 0.0)


## The grey-box's colours, from the same §13.2 tokens, so the two views cannot
## disagree about what a modifier looks like. Colour is the *third* channel here:
## the silhouette and the outline already carry the reading (§21).
func tint_of(i: int) -> Color:
	match mark_of(i):
		Mark.GOAL:
			return palette.goal_cell
		Mark.PORTAL:
			return palette.portal
		Mark.GATE:
			return palette.gate
		_:
			return palette.wild


## The quad every mark is drawn on: `x` and `y` in −1 … 1, `UV` 0 … 1, which is
## what the shader turns into a camera-facing square.
##
## Its AABB is widened to a cube by hand. The vertex shader replaces the corner
## positions outright, so the bounds the engine would derive from the mesh are the
## bounds of a quad that is never actually drawn: the drawn one reaches a full
## radius along whichever way the camera happens to face. Bounds that do not
## contain what is drawn are a culling bug waiting for the first mark to sit near
## the edge of the play area, so they are stated rather than inferred.
static func build_quad_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array[Vector2] = [
		Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0),
		Vector2(-1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0),
	]
	for p: Vector2 in corners:
		st.set_uv((p + Vector2.ONE) * 0.5)
		st.add_vertex(Vector3(p.x, p.y, 0.0))
	var mesh: ArrayMesh = st.commit()
	mesh.custom_aabb = AABB(Vector3.ONE * -1.0, Vector3.ONE * 2.0)
	return mesh

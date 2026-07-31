## The edge a placement would cross, lit as light spilling through it: a soft wash
## laid on each candidate, brightest against the boundary it would be entered
## across and gone before the middle of the cell.
##
## The board already says *where* a tile may go — §14.1's breathing candidate tint,
## on the cells `legal_targets` returned. What it could not say is **which way in**.
## A tile is a direction, so every candidate is reached from exactly one anchor
## across exactly one of its six edges (§5.4's injectivity is what makes that "one"
## rather than "some"), and with three or four candidates spread around a path that
## has doubled back, the cell a given one connects from is genuinely ambiguous.
## Lighting the shared edge answers it without a word of text.
##
## It is a wash rather than a bar. A bar was the first version and the object was
## wrong: it has two hard ends and two hard sides, and at this camera it read as a
## chip wedged into the crevice between two tiles rather than as a way in. What the
## cell should look like is *lit from that side*, so the geometry is a flat quad on
## the candidate's own top face and every edge it has is dissolved by
## `seam_bleed.gdshader` — a falloff inward from the boundary, a taper along it.
##
## On the **candidate**, never on the anchor. It marks the cell you are about to
## fill, not a fence around the one you came from.
##
## Which edge is not decided here. [method GameState.anchor_of] is asked, because it
## is what the commit will use — a second opinion in the view would be free to
## promise an edge the rules then do not take, and a wrong promise about where the
## line is going is worse than no promise at all.
##
## One `MultiMesh`, allocated for the worst case once and shown by
## `visible_instance_count` (C4). No `_process`, no `_draw`.
class_name BoardSeams
extends MultiMeshInstance3D

const SHADER := "res://src/view/shaders/seam_bleed.gdshader"

## A seam spans one hex edge, whose length is the circumradius. Taken in full here —
## the shader tapers the ends, which is a softer job than a shortened quad and does
## not leave two corners of bare tile between neighbouring seams.
const SEAM_SPAN := 1.0

## How far the wash reaches into the candidate, as a fraction of the circumradius.
## A hexagon's inradius is about 0.87 of that, so this dies well before the far
## side and the cell keeps a lit edge rather than becoming a lit cell.
const BLEED_DEPTH := 0.62

## How far off the tile top the wash floats, as a fraction of the circumradius. Just
## enough to beat depth fighting with the face it lies on.
const LIFT := 0.006

## How far the seam is pulled toward white. See [method seam_colour].
const SEAM_LIGHTEN := 0.3

var palette: Palette = null

var _state: GameState = null
var _layout: HexLayout = null
var _tiles: BoardTiles = null
var _seams: Array = []  # [edge midpoint, inward step, colour]


func bind(state: GameState, layout: HexLayout, tiles: BoardTiles) -> void:
	_state = state
	_layout = layout
	_tiles = tiles
	if palette == null:
		palette = Palette.current()

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	# No custom data: the wash reads its colour per instance and everything else
	# out of its own UVs, so a per-instance channel would be a buffer nobody reads.
	mm.mesh = build_bleed_mesh()
	mm.instance_count = capacity_for(state.board)
	mm.visible_instance_count = 0
	multimesh = mm

	if material_override == null:
		var mat := ShaderMaterial.new()
		mat.shader = load(SHADER)
		material_override = mat
	set_flat(SettingsService.flat_board())

	# Same reason as the ribbon's: a bar lying on a tile that shadowed the tile it
	# lies on would be noise across the shadows C-22 asks the player to read heights
	# from.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The most seams a board can ever want.
##
## One per candidate, and a candidate is a cell — `legal_targets` returns at most
## one target per anchor and the wild set is deduplicated, so the board's own size
## bounds both.
static func capacity_for(board: Board) -> int:
	return maxi(1, board.size())


## Lights the edge into each of [param targets]. [param wild] picks which rule
## decides the anchor, because a wild charge enters from a neighbour rather than
## along the tile in hand.
func set_candidates(targets: Array[Vector3i], wild: bool = false) -> void:
	if multimesh == null or _state == null:
		return
	_seams = _build(targets, wild)
	var live: int = mini(_seams.size(), multimesh.instance_count)
	for i: int in range(live):
		multimesh.set_instance_transform(i, transform_of(i))
		multimesh.set_instance_color(i, _seams[i][2] as Color)
	multimesh.visible_instance_count = live


func count() -> int:
	return multimesh.visible_instance_count if multimesh != null else 0


## Where seam [param i] lies: its near edge on the shared boundary, running across
## the step that crosses it, reaching inward over the candidate's own top face.
##
## The quad is anchored at that near edge rather than centred, so the brightest
## line of the wash sits exactly on the boundary whatever [constant BLEED_DEPTH]
## is retuned to.
func transform_of(i: int) -> Transform3D:
	var centre: Vector3 = _seams[i][0]
	var inward: Vector3 = _seams[i][1]
	var depth: float = inward.length()
	var dir: Vector3 = inward / maxf(depth, 0.0001)
	# The quad runs *across* the step: a seam is the edge being crossed, not the
	# crossing. Its own local z is the direction the light spreads.
	var across: Vector3 = dir.cross(Vector3.UP).normalized()
	return Transform3D(
		Basis(across * (_layout.size * SEAM_SPAN), Vector3.UP, dir * depth),
		centre
	)


## Colour: the **path's**, not the candidate's.
##
## `cell_candidate_stroke` was the obvious pick and it was the wrong one — a
## candidate's own tint is that token lerped into the empty fill, so a seam drawn in
## it was gold on gold and read as a rim rather than as an opening. Taking
## `path_core` instead says the true thing: this is where the line is about to
## cross. It is the same colour the connector will be drawn in a moment later, so
## the seam is a ghost of the very bar that replaces it.
func seam_colour() -> Color:
	# Lifted toward white for the same reason the ribbon is (`LINK_LIGHTEN`): the
	# bar sits down in the crevice between two tiles, where it catches little of the
	# board's one key light, and the shader's emission alone left it a muted teal
	# rather than an opening.
	return palette.path_core.lerp(Color.WHITE, SEAM_LIGHTEN)


func set_flat(flat: bool) -> void:
	var mat := material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("flat_board", flat)


func _build(targets: Array[Vector3i], wild: bool) -> Array:
	var out: Array = []
	var colour: Color = seam_colour()
	for target: Vector3i in targets:
		var anchor: Vector3i = _state.anchor_of(target, wild)
		# A wild with no path neighbour returns the target itself, and a tutorial or
		# a portal can hand over a target whose anchor is not on the board. Neither
		# has an edge to draw, and drawing one anyway would put a bar through the
		# middle of a cell.
		if anchor == target or not _state.board.has(anchor):
			continue
		out.append([_midpoint(anchor, target), _step(anchor, target), colour])
	return out


## The middle of the shared edge, at the height of the **candidate's** top face.
##
## Not the taller of the two, which is what a bar standing in the gap wanted: this
## lies on the candidate, so it belongs at the candidate's height. A path tile
## beside it stands taller (C-22) and simply occludes the far sliver of the wash,
## which is what light coming past a raised edge does anyway.
func _midpoint(anchor: Vector3i, target: Vector3i) -> Vector3:
	var a: Vector3 = _layout.to_plane(anchor)
	var t: Vector3 = _layout.to_plane(target)
	return (a + t) * 0.5 + Vector3.UP * (_tiles.top_of(target) + _layout.size * LIFT)


## The direction the wash spreads — anchor to candidate, so it runs *into* the cell
## being offered — scaled to how far it reaches.
func _step(anchor: Vector3i, target: Vector3i) -> Vector3:
	var run: Vector3 = _layout.to_plane(target) - _layout.to_plane(anchor)
	return run.normalized() * (_layout.size * BLEED_DEPTH)


## A unit wash: 1 across on x, reaching from z = 0 at the boundary to z = 1 inward,
## flat on the y = 0 plane and anchored on its near edge rather than its middle.
##
## Built here rather than with a [QuadMesh] because a quad is centred on its own
## origin and faces +z; this has to start at the seam and lie down.
static func build_bleed_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var corners: Array[Vector3] = [
		Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0),
		Vector3(0.5, 0.0, 1.0), Vector3(-0.5, 0.0, 1.0),
	]
	# u runs along the shared edge, v from the boundary inward — the two axes the
	# shader dissolves.
	var uvs: Array[Vector2] = [
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0),
	]
	for tri: Array in [[0, 2, 1], [0, 3, 2]]:
		for k: int in tri:
			st.set_uv(uvs[k])
			st.set_normal(Vector3.UP)
			st.add_vertex(corners[k])
	return st.commit()

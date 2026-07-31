## The edge a placement would cross: one lit bar on the boundary between each
## candidate and the path cell it would be entered from.
##
## The board already says *where* a tile may go — §14.1's breathing candidate tint,
## on the cells `legal_targets` returned. What it could not say is **which way in**.
## A tile is a direction, so every candidate is reached from exactly one anchor
## across exactly one of its six edges (§5.4's injectivity is what makes that "one"
## rather than "some"), and with three or four candidates spread around a path that
## has doubled back, the cell a given one connects from is genuinely ambiguous.
## Lighting the shared edge answers it without a word of text.
##
## The seam is drawn on the **candidate's** side of the boundary and lifted onto the
## taller of the two tiles, so it reads as an opening in the cell you are about to
## fill rather than as a fence around the one you came from.
##
## Which edge is not decided here. [method GameState.anchor_of] is asked, because it
## is what the commit will use — a second opinion in the view would be free to
## promise an edge the rules then do not take, and a wrong promise about where the
## line is going is worse than no promise at all.
##
## One `MultiMesh` of the same bar [BoardLinks] draws its ribbon with, allocated for
## the worst case once and shown by `visible_instance_count` (C4). No `_process`,
## no `_draw`.
class_name BoardSeams
extends MultiMeshInstance3D

const SHADER := "res://src/view/shaders/path_link.gdshader"

## A seam spans one hex edge, whose length is the circumradius — but not quite all
## of it: pulled in a little so two seams meeting at a corner read as two openings
## rather than as one continuous outline.
const SEAM_SPAN := 0.82

## Thicker than a connector ([constant BoardLinks.LINK_WIDTH] is 0.14). A connector
## is a line the eye follows along; a seam is a threshold the eye crosses, and it is
## seen edge-on from this camera rather than lengthwise.
const SEAM_WIDTH := 0.17
const SEAM_HEIGHT := 0.05

## How far off the tile top the bar floats, as a fraction of the cell circumradius,
## before its own thickness is added.
const LIFT := 0.012

## How far the seam is pulled toward white. See [method seam_colour].
const SEAM_LIGHTEN := 0.3

var palette: Palette = null

var _state: GameState = null
var _layout: HexLayout = null
var _tiles: BoardTiles = null
var _seams: Array = []  # [midpoint, along, colour]


func bind(state: GameState, layout: HexLayout, tiles: BoardTiles) -> void:
	_state = state
	_layout = layout
	_tiles = tiles
	if palette == null:
		palette = Palette.current()

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = BoardLinks.build_bar_mesh()
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
		# The ribbon shader reads `r` as its kind and the rest as a dash phase; a
		# seam is a solid bar of the plain kind.
		multimesh.set_instance_custom_data(i, Color(float(BoardLinks.Kind.LINK), 0.0, 0.0, 0.0))
	multimesh.visible_instance_count = live


func count() -> int:
	return multimesh.visible_instance_count if multimesh != null else 0


## Where seam [param i] lies: centred on the shared edge, square to the step that
## crosses it, lying flat on the taller of the two tiles it divides.
func transform_of(i: int) -> Transform3D:
	var centre: Vector3 = _seams[i][0]
	var along: Vector3 = _seams[i][1]
	var span: float = along.length()
	var dir: Vector3 = along / maxf(span, 0.0001)
	var up: Vector3 = Vector3.UP
	# The bar runs *across* the step rather than along it: a seam is the edge being
	# crossed, not the crossing.
	var across: Vector3 = dir.cross(up).normalized()
	return Transform3D(
		Basis(across * span, up * (_layout.size * SEAM_HEIGHT), dir * (_layout.size * SEAM_WIDTH)),
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


## The middle of the shared edge, standing on whichever of the two tiles is taller.
## A seam sunk into the side of a raised path tile would be invisible from this
## camera at exactly the moment it matters.
func _midpoint(anchor: Vector3i, target: Vector3i) -> Vector3:
	var a: Vector3 = _layout.to_plane(anchor)
	var t: Vector3 = _layout.to_plane(target)
	var top: float = maxf(_tiles.top_of(anchor), _tiles.top_of(target))
	return (a + t) * 0.5 + Vector3.UP * (
		top + _layout.size * (LIFT + SEAM_HEIGHT * 0.5))


## The step from anchor to candidate, scaled to the length of the edge it crosses.
## A hexagon's edge is its circumradius, so the span is the cell size less the
## inset that keeps two seams from fusing at a shared corner.
func _step(anchor: Vector3i, target: Vector3i) -> Vector3:
	var run: Vector3 = _layout.to_plane(target) - _layout.to_plane(anchor)
	return run.normalized() * (_layout.size * SEAM_SPAN)

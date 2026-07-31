## The path as one continuous stroke: a ribbon of light laid over the tiles it has
## joined, plus a dashed tether wherever the route jumped through a portal.
##
## §13.3 draws connectors as rounded capsules in a second SDF pass. C-18 has no
## canvas pass to put them in, so they are geometry like everything else on this
## board — one `MultiMesh` of bars, which is the "one MultiMesh for connectors"
## §20's draw-call budget already reserved.
##
## Without them a route reads as a row of separately raised tiles rather than as a
## line: [BoardTiles] can say *which* cells are joined, but not in what order, and
## a path that crosses its own row twice becomes ambiguous. The ribbon carries the
## same depth gradient the grey-box's connectors did (§13.3), so which end is the
## near end survives here too.
##
## The instance buffer is allocated once for the worst case a level can reach and
## the live prefix is shown with `visible_instance_count`, so a placement rewrites
## instances and never reallocates (C4). There is no `_process` and no `_draw`.
class_name BoardLinks
extends MultiMeshInstance3D

const SHADER := "res://src/view/shaders/path_link.gdshader"

## Kind codes, written into `INSTANCE_CUSTOM.r`; the shader lights the two
## differently. A wire format: append, never renumber.
enum Kind { LINK = 0, TETHER = 1 }

## Ribbon width and thickness as fractions of the cell circumradius.
##
## Much thinner than the grey-box's 0.30 stroke, and thinner than this started.
## §13.1 asks for "thin bright strokes" and a path that reads as "a single
## continuous line of light"; a solid bar in three dimensions reads far heavier
## than the same number does in two, and at 0.26 wide and 0.09 thick it was a white
## pipe lying on the board rather than a line drawn on it.
const LINK_WIDTH := 0.14
const LINK_HEIGHT := 0.05

## How far the ribbon is lifted off its own path colour. See [method _colour_at].
## Only just enough to separate: the emission is what makes it read, and lightening
## it any further flattened the depth gradient into one white slash.
const LINK_LIGHTEN := 0.06

## A portal jump is not a lattice step, so it is not drawn like one: dashes, and a
## thinner ribbon. Two channels that are not colour (§21) — the grey-box used the
## same dashes for the same reason.
const TETHER_WIDTH := 0.12
const TETHER_DASHES := 7
## Fraction of each dash's slot left empty, which is what makes it a dash.
const TETHER_GAP := 0.45

## How high the tether arcs over the board at its midpoint, as a fraction of the
## distance it spans.
##
## It arcs rather than running straight for three reasons. A straight bar lying
## across the board reads as a scratch on it rather than as a link between two
## cells; it is chopped up by every wall it passes, because a wall stands taller
## than the tiles the tether's ends rest on; and a portal *is* a jump, so a line
## that leaves the board and comes back down says what the mechanic does. The rise
## clears the tallest thing on the board ([constant BoardTiles.WALL_TOP]) by a wide
## margin at every span a radius-4 board can produce.
const TETHER_RISE := 0.22

## Lift above the tile top, as a fraction of the circumradius. Enough to sit *on*
## the tiles rather than inside them; small enough that the ribbon still reads as
## lying on the board rather than floating over it.
const LIFT := 0.012

@export var palette: Palette = null

var _tiles: BoardTiles = null
var _board: Board = null
var _state: GameState = null
var _layout: HexLayout = null
var _depth: Dictionary = {}

## How much of the route is drawn, 0 to 1.
##
## **One for the whole of play** — the connector is drawn as the placement that
## makes it is made. C-28 had this at zero and revealed the ribbon only on the
## winning move; **amended by C-30**, because the reasoning did not survive being
## looked at. Two filled cells side by side say they are joined *if the path is a
## line*, and §5.1 makes it a tree: on a path that has doubled back, two adjacent
## filled cells are frequently not joined at all. The board already conceded this
## argument for candidates — `board_seams.gd` lights the entry edge precisely
## because "the cell a given candidate connects from is genuinely ambiguous" — and
## the ambiguity does not go away once the move is committed.
##
## [method play_trace] still runs on the winning move. It is a reprise now rather
## than a reveal: the same line, redrawn start to goal, of something the player
## watched grow.
var _traced: float = 1.0
var _segments: Array = []    # of [Vector3 from, Vector3 to, Kind, Color]
## §14.1's connector draw, mid-flight: how much of the newest bar exists yet.
var _drawing: float = 1.0


func _ready() -> void:
	if palette == null:
		palette = Palette.current()


## Allocates the buffer for the longest path [param state]'s board could ever hold
## and fills in whatever it holds now. Called once per level; every later change
## goes through [method rebuild], which allocates no instances.
func bind(state: GameState, layout: HexLayout, tiles: BoardTiles) -> void:
	_state = state
	_board = state.board
	_layout = layout
	_tiles = tiles
	# A fresh board draws whatever route it already has, which on a new level is
	# none — so this is 1.0 rather than 0.0 (C-30). The case the old reset existed
	# for is handled by the route itself being empty: §7.2's endless run rebinds
	# while the same node keeps playing, and the next stage starts with no edges.
	_traced = 1.0

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = build_bar_mesh()
	mm.instance_count = capacity_for(_board)
	multimesh = mm

	if material_override == null:
		var mat := ShaderMaterial.new()
		mat.shader = load(SHADER)
		material_override = mat
	set_flat(SettingsService.flat_board())

	# The ribbon takes light but never casts it. A connector lying on a tile would
	# drop a shadow onto the tile it is lying on, and the tether — which arcs over
	# the board — laid a trail of dark streaks across everything it passed. C-22
	# reads *tile* height from the shadows, so the board's shadows have a job and
	# these were noise in the middle of it.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	rebuild()


## How many instances a level on [param board] can ever need.
##
## Every edge joins exactly one cell that was not in the path before, so a path can
## hold at most `cells - 1` of them; each portal edge costs [constant
## TETHER_DASHES] instead of one, and a pair can be traversed at most once because
## the second entry finds its twin already joined.
static func capacity_for(board: Board) -> int:
	return maxi(1, board.size() - 1 + board.portal_pairs().size() * (TETHER_DASHES - 1))


## Recomputes the whole ribbon from the live path. Called after each move — and
## after an undo, which is why it is rebuilt rather than appended to: `edges` is
## popped on undo, and a ribbon that only ever grew would leave the undone step
## lit.
func rebuild() -> void:
	if multimesh == null or _state == null:
		return
	_depth = PathDepth.of(_state)
	_segments = segments()
	_drawing = 1.0
	var live: int = mini(_segments.size(), multimesh.instance_count)
	for i: int in range(live):
		multimesh.set_instance_transform(i, transform_of(i))
		multimesh.set_instance_color(i, tint_of(i))
		multimesh.set_instance_custom_data(i, custom_of(i))
	# C-28: at rest the board shows tethers only. The lattice connectors are built,
	# ordered and ready, and how many of them are drawn is `_traced`.
	multimesh.visible_instance_count = _visible_count()


## One entry per bar to draw, in path order: `[from, to, kind, colour]` with the
## ends already lifted onto the tile tops they run between. Computed apart from the
## push because instance data cannot be read back under the headless renderer.
## Tethers first, then lattice links ordered by how far along the path they are.
##
## The order is the mechanism (C-28). Tethers are always drawn and links are
## revealed by count, so `visible_instance_count = tethers` is "no line" and
## `tethers + all links` is the whole route — and every value between the two is a
## line running outward from the start, which is the trace itself.
func segments() -> Array:
	var out: Array = _tethers()
	var links: Array = _links()
	links.sort_custom(func(a: Array, b: Array) -> bool: return float(a[4]) < float(b[4]))
	out.append_array(links)
	return out


func _tethers() -> Array:
	var out: Array = []
	for e: Variant in _state.edges:
		var edge: Array = e
		var from: Vector3i = edge[0]
		var to: Vector3i = edge[2]
		if not _board.has(from) or not _board.has(to):
			continue
		var a: Vector3 = _top_of(from)
		var b: Vector3 = _top_of(to)
		if int(edge[1]) != Direction.PORTAL:
			continue
		# A tether spans two cells that are not neighbours, so it is cut into
		# dashes rather than drawn as one long bar — and thrown over the board
		# rather than dragged across it.
		#
		# C-28 removed the lattice connectors from play and kept these: a portal
		# joins two cells that are *not* neighbours, so with no line at all nothing
		# on the board says the path jumped. Every other connection is implied by
		# two filled cells sitting next to each other.
		var rise: float = a.distance_to(b) * TETHER_RISE
		for i: int in range(TETHER_DASHES):
			var t0: float = (float(i) + TETHER_GAP * 0.5) / float(TETHER_DASHES)
			var t1: float = (float(i) + 1.0 - TETHER_GAP * 0.5) / float(TETHER_DASHES)
			out.append([arc_point(a, b, rise, t0), arc_point(a, b, rise, t1),
				Kind.TETHER, palette.portal])
	return out


## The lattice connectors, each carrying the depth of the cell it arrives at so
## `segments` can order them from the start outward.
func _links() -> Array:
	var out: Array = []
	for e: Variant in _state.edges:
		var edge: Array = e
		var from: Vector3i = edge[0]
		var to: Vector3i = edge[2]
		if int(edge[1]) == Direction.PORTAL:
			continue
		if not _board.has(from) or not _board.has(to):
			continue
		out.append([_top_of(from), _top_of(to), Kind.LINK, _colour_at(to),
			float(_depth.get(to, 0))])
	return out


## §14.1's connector draw: the bar that was just added grows from its anchor to its
## target over 160 ms, `CUBIC` / `EASE_OUT`. Only the newest one animates — the rest
## of the ribbon is already there and must not flicker when one more joins it.
func draw_newest() -> void:
	if multimesh == null or _segments.is_empty():
		return
	# Set to zero *now*, not on the tween's first step. A tween does not run until
	# the next idle frame, so the bar would otherwise be drawn at full length for
	# one frame and then snap back to nothing to grow again.
	_set_drawing(0.0)
	var tween := create_tween()
	Motion.shape(tween, "connector_draw")
	tween.tween_method(_set_drawing, 0.0, 1.0, Motion.seconds("connector_draw"))


## How much of the newest bar is drawn, 0 to 1. Always 1 for every other bar.
func draw_progress(i: int) -> float:
	return _drawing if i == _segments.size() - 1 else 1.0


func _set_drawing(value: float) -> void:
	_drawing = value
	if multimesh != null and not _segments.is_empty():
		var last: int = _segments.size() - 1
		multimesh.set_instance_transform(last, transform_of(last))


## A point [param t] of the way along the hop from [param a] to [param b], peaking
## [param rise] above the straight line between them. A plain parabola: it is zero
## at both ends, so the tether still meets the two tiles it belongs to.
static func arc_point(a: Vector3, b: Vector3, rise: float, t: float) -> Vector3:
	return a.lerp(b, t) + Vector3.UP * (rise * 4.0 * t * (1.0 - t))


## Tethers always, plus however much of the route the trace has reached.
func _visible_count() -> int:
	var tethers: int = 0
	for entry: Variant in _segments:
		if (entry as Array)[2] == Kind.TETHER:
			tethers += 1
	var links: int = _segments.size() - tethers
	var shown: int = tethers + int(round(_traced * float(links)))
	return mini(shown, multimesh.instance_count)


## The payoff: on the winning move the connectors arrive in path order, so the
## route the player built redraws itself from the start out to the goal. Under
## C-30 this is a reprise rather than a reveal — the line was there the whole time
## and this is the run of it, in the order it means rather than the order the
## player happened to build it in.
func play_trace() -> void:
	if multimesh == null or _segments.is_empty():
		return
	if Motion.seconds("goal_reached") <= 0.0:
		set_trace(1.0)
		return
	set_trace(0.0)
	var tween := create_tween()
	Motion.shape(tween, "goal_reached")
	tween.tween_method(set_trace, 0.0, 1.0, Motion.seconds("goal_reached"))


func set_trace(value: float) -> void:
	_traced = clampf(value, 0.0, 1.0)
	if multimesh != null:
		multimesh.visible_instance_count = _visible_count()


func traced() -> float:
	return _traced


func count() -> int:
	return _segments.size()


func kind_of(i: int) -> Kind:
	return _segments[i][2] as Kind


## Where bar [param i] runs and how thick it is: length along its own x, thickness
## up, width across. The bar mesh is a unit cube, so the basis is the whole shape.
func transform_of(i: int) -> Transform3D:
	var from: Vector3 = _segments[i][0]
	var full: Vector3 = _segments[i][1]
	var tether: bool = kind_of(i) == Kind.TETHER
	# Orientation comes from the whole segment and only the *length* is animated,
	# so a bar one frame into its 160 ms draw still points where it is going. Taking
	# the direction from the drawn portion instead leaves it undefined at zero.
	var along: Vector3 = full - from
	var span: float = along.length()
	var dir: Vector3 = along / maxf(span, 0.0001)
	var length: float = span * draw_progress(i)
	var to: Vector3 = from + dir * length
	# `side` is horizontal by construction and `up` is square to both, so a bar
	# between tiles of different heights still lies flat rather than rolling.
	var side: Vector3 = dir.cross(Vector3.UP).normalized()
	var up: Vector3 = side.cross(dir).normalized()
	var width: float = _layout.size * (TETHER_WIDTH if tether else LINK_WIDTH)
	var height: float = _layout.size * LINK_HEIGHT
	# The bar mesh is centred on its own origin, so half of it would be sunk into
	# the tile it lies on — and a ribbon the same colour as the tile under it, half
	# buried in it, is a ribbon nobody can see. Lift by half its thickness so it
	# stands *on* the surface.
	return Transform3D(
		Basis(dir * length, up * height, side * width),
		(from + to) * 0.5 + up * height * 0.5
	)


func tint_of(i: int) -> Color:
	return _segments[i][3] as Color


## What the bar *is*, for the shader: which kind, and how far along the path it
## sits — the same 0-to-1 the tiles carry, so §14.1's flow pulse crosses the tile
## and the stroke lying on it at one moment rather than two.
func custom_of(i: int) -> Color:
	return Color(float(kind_of(i)), _depth_ratio_of(i), 0.0, 0.0)


func _depth_ratio_of(i: int) -> float:
	if _depth.size() <= 1 or kind_of(i) == Kind.TETHER:
		return 0.0
	var to: Vector3i = cell_of(i)
	return clampf(float(_depth.get(to, 0)) / float(_depth.size() - 1), 0.0, 1.0)


## The cell a bar arrives at, which is the one whose depth it takes.
## The cell a bar arrives at — what its depth, its colour and C-28's ordering are
## all measured against.
func cell_of(i: int) -> Vector3i:
	var arrives_at: Vector3 = _segments[i][1]
	return _layout.from_plane(arrives_at)


## The same gradient the grey-box's connectors used, from the same tokens: a
## connector takes the colour of the cell it leads *to*, so the stroke darkens
## along the route and the far end of a long path is visibly the far end (§13.3).
##
## Lightened, because in 3D the ribbon lies on tiles that are *already* filled with
## that exact colour (C-22 tinted them the same way) — at the token's own value the
## stroke is invisible on its own path. The grey-box lightened its path outlines by
## the same trick and for the same reason.
func _colour_at(cell: Vector3i) -> Color:
	return palette.path_at_depth(int(_depth.get(cell, 0)), maxi(1, _depth.size())) \
		.lightened(LINK_LIGHTEN)


func _top_of(cell: Vector3i) -> Vector3:
	return _layout.to_plane(cell) + Vector3.UP * (_tiles.top_of(cell) + _layout.size * LIFT)


## A unit bar: 1 long on x, 1 thick on y, 1 wide on z, centred on its own origin so
## a bar is placed by its midpoint. Normals come from
## [method SurfaceTool.generate_normals] for the same reason [BoardTiles]' prism
## does — the winding is then the engine's convention rather than a reading of it.
static func build_bar_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var h := 0.5
	# Six faces, each two triangles, wound counter-clockwise seen from outside.
	var faces: Array = [
		[Vector3(h, -h, -h), Vector3(h, h, -h), Vector3(h, h, h), Vector3(h, -h, h)],
		[Vector3(-h, -h, h), Vector3(-h, h, h), Vector3(-h, h, -h), Vector3(-h, -h, -h)],
		[Vector3(-h, h, -h), Vector3(-h, h, h), Vector3(h, h, h), Vector3(h, h, -h)],
		[Vector3(-h, -h, h), Vector3(-h, -h, -h), Vector3(h, -h, -h), Vector3(h, -h, h)],
		[Vector3(-h, -h, h), Vector3(h, -h, h), Vector3(h, h, h), Vector3(-h, h, h)],
		[Vector3(h, -h, -h), Vector3(-h, -h, -h), Vector3(-h, h, -h), Vector3(h, h, -h)],
	]
	for f: Variant in faces:
		var q: Array = f
		# Reversed, because the quads above are listed anticlockwise seen from
		# outside and Godot's front face is the clockwise one. Every normal came out
		# pointing into the bar until the test above said so.
		for tri: Array in [[0, 2, 1], [0, 3, 2]]:
			for k: int in tri:
				st.add_vertex(q[k] as Vector3)
	st.generate_normals()
	return st.commit()


## §21's escape hatch (C-24): with [param flat] the board takes no light, so a
## tile's colour on screen is its palette colour and a greyscale palette cannot be
## undone by a highlight. A uniform rather than a second shader, so there is one
## place the geometry and the colours are described.
func set_flat(flat: bool) -> void:
	if material_override is ShaderMaterial:
		(material_override as ShaderMaterial).set_shader_parameter("flat_board", flat)

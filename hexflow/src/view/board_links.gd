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
## `TETHER_IDLE` is §6's standing tether — the "faint tether line to twin" a portal
## carries *before* anything travels down it. It had never been drawn: tethers were
## built from `_state.edges`, so a portal only grew its line at the moment it was
## used, and until then nothing on the board said where it went. That is exactly
## the information a player needs to plan a route *through* one.
enum Kind { LINK = 0, TETHER = 1, TETHER_IDLE = 2 }

## Ribbon width and thickness as fractions of the cell circumradius.
##
## Much thinner than the grey-box's 0.30 stroke, and thinner than this started.
## §13.1 asks for "thin bright strokes" and a path that reads as "a single
## continuous line of light"; a solid bar in three dimensions reads far heavier
## than the same number does in two, and at 0.26 wide and 0.09 thick it was a white
## pipe lying on the board rather than a line drawn on it.
const LINK_WIDTH := 0.14
const LINK_HEIGHT := 0.05

## How many slices the bar mesh is cut into along its own length (C-31).
##
## A box has two rings of vertices, and a vertex shader can only bend a stroke
## where it has vertices to bend. Eight is enough for the two-octave wobble in
## `path_link.gdshader` to read as a drawn line rather than as a hinge, and it is
## still one mesh in one MultiMesh in one draw call — the geometry §20 budgeted.
const BAR_SEGMENTS := 8

## How long one pulse takes to run the whole length of the path, in seconds.
##
## §13.1 asks for "a single continuous line of light that **grows and pulses**"
## and §14.1 never gave the pulsing a duration — so this is a chosen number and
## says so, the way C-21's camera angles are. Slow: the pulse is the path being
## alive, not the path demanding attention, and §2.2's first pillar is calm.
const PULSE_SECONDS := 2.6

## How far the ribbon is lifted off its own path colour. See [method _colour_at].
## Only just enough to separate: the emission is what makes it read, and lightening
## it any further flattened the depth gradient into one white slash.
const LINK_LIGHTEN := 0.06

## A portal jump is not a lattice step, so it is not drawn like one: dashes, and a
## thinner ribbon. Two channels that are not colour (§21) — the grey-box used the
## same dashes for the same reason.
const TETHER_WIDTH := 0.12

## §6's standing tether, as a fraction of a used one's width. Thinner, and dimmed
## by [constant TETHER_IDLE_DIM] — **two channels, neither of them colour** (C5),
## because "this portal has been travelled" is a visible state like any other and
## a player who cannot see the difference in hue still has to see it.
const TETHER_IDLE_WIDTH := 0.45
const TETHER_IDLE_DIM := 0.45

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
	set_motion()

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
	# Every pair now draws its tether whether or not the path has used it (§6), so
	# the reservation is a whole set of dashes per pair rather than the extra ones
	# a traversal would have added on top of the edge it already owned.
	return maxi(1, board.size() - 1 + board.portal_pairs().size() * TETHER_DASHES)


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


## One tether per portal **pair on the board**, not per pair the path has used.
##
## §6 gives a portal "a faint tether line to twin" and that line is information the
## player needs *before* deciding to enter one: a portal whose far end is unknown
## is not a route, it is a gamble. Built from `edges` this only appeared at the
## moment it stopped being useful. Harmless while every campaign level ships one
## pair, and unreadable the moment one ships two — which is the case §6 wrote the
## tether for.
##
## A traversed pair keeps the tether it always had. An untraversed one gets the
## same arc, thinner and dimmer (C5: two channels, neither colour).
func _tethers() -> Array:
	var out: Array = []
	var used := _traversed_pairs()
	for pair: Variant in _board.portal_pairs():
		var from: Vector3i = (pair as Array)[0]
		var to: Vector3i = (pair as Array)[1]
		if not _board.has(from) or not _board.has(to):
			continue
		var a: Vector3 = _top_of(from)
		var b: Vector3 = _top_of(to)
		var live: bool = used.has(_pair_key(from, to))
		var kind: Kind = Kind.TETHER if live else Kind.TETHER_IDLE
		var colour: Color = palette.portal if live \
			else palette.portal.darkened(1.0 - TETHER_IDLE_DIM)
		# A tether spans two cells that are not neighbours, so it is cut into
		# dashes rather than drawn as one long bar — and thrown over the board
		# rather than dragged across it.
		var rise: float = a.distance_to(b) * TETHER_RISE
		for i: int in range(TETHER_DASHES):
			var t0: float = (float(i) + TETHER_GAP * 0.5) / float(TETHER_DASHES)
			var t1: float = (float(i) + 1.0 - TETHER_GAP * 0.5) / float(TETHER_DASHES)
			out.append([arc_point(a, b, rise, t0), arc_point(a, b, rise, t1),
				kind, colour])
	return out


## The portal pairs the path has actually jumped through, keyed so the lookup does
## not depend on which end the edge was recorded from.
func _traversed_pairs() -> Dictionary:
	var out: Dictionary = {}
	for e: Variant in _state.edges:
		var edge: Array = e
		if int(edge[1]) == Direction.PORTAL:
			out[_pair_key(edge[0], edge[2])] = true
	return out


static func _pair_key(a: Vector3i, b: Vector3i) -> Array:
	return Hex.sort_cells([a, b] as Array[Vector3i])


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
		if (entry as Array)[2] != Kind.LINK:
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
	var tether: bool = kind_of(i) != Kind.LINK
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
	if kind_of(i) == Kind.TETHER_IDLE:
		width *= TETHER_IDLE_WIDTH
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
	return Color(float(kind_of(i)), _depth_ratio_of(i), seed_of(i), _depth_step())


## How much of the path's whole length one lattice step is worth.
##
## The ratio in `g` is constant per bar, so on its own it can only light a bar at
## a time — a travelling pulse built on it would jump from cell to cell. With the
## step, the shader adds the fraction *along* the bar and gets one continuous
## 0-to-1 coordinate running the length of the route, which is what §13.1's line
## "that grows and pulses" needs in order to pulse along rather than in chunks.
##
## Normalised by the deepest cell rather than by how many cells there are. On a
## branching path those differ — §5.1 makes the path a tree — and dividing by the
## count would leave the wave stopping short of the far end by however much the
## other branches weigh. The colour gradient keeps its own normalisation; this one
## exists to reach 1.0 exactly at the end of the longest branch.
func _depth_step() -> float:
	return 1.0 / float(_max_depth())


func _max_depth() -> int:
	var deepest: int = 1
	for d: Variant in _depth.values():
		deepest = maxi(deepest, int(d))
	return deepest


## A stable 0-to-1 number per bar, so C-31's wobble differs from one stroke to the
## next and a straight run of six steps does not draw as six identical bows.
##
## Taken from *where the bar is* rather than from its index, which is what keeps a
## drawn line from redrawing itself differently every time the ribbon is rebuilt —
## and it is rebuilt on every move and every undo. A hand that redrew the whole
## page each time the player placed a tile would be the one thing more distracting
## than a ruled line.
func seed_of(i: int) -> float:
	var a: Vector3 = _segments[i][0]
	var b: Vector3 = _segments[i][1]
	var h: int = hash(Vector2i(int(round((a.x + b.x) * 8.0)), int(round((a.z + b.z) * 8.0))))
	return float(absi(h) % 1024) / 1024.0


## Where along the whole route a bar *starts* — the depth of the cell it leaves,
## not the one it arrives at. The bar then covers `[g, g + a]`, so consecutive bars
## tile the span with no gap and no overlap and the wave crosses a joint without
## stuttering. It used to report the arrival depth, which put every bar one step
## ahead of itself and started the wave a step in from the beginning.
func _depth_ratio_of(i: int) -> float:
	if _depth.size() <= 1 or kind_of(i) != Kind.LINK:
		return 0.0
	var arrives_at: int = int(_depth.get(cell_of(i), 0))
	return clampf(float(arrives_at - 1) / float(_max_depth()), 0.0, 1.0)


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
	# The two end caps, unchanged: a bar still starts and stops square.
	var caps: Array = [
		[Vector3(h, -h, -h), Vector3(h, h, -h), Vector3(h, h, h), Vector3(h, -h, h)],
		[Vector3(-h, -h, h), Vector3(-h, h, h), Vector3(-h, h, -h), Vector3(-h, -h, -h)],
	]
	for f: Variant in caps:
		_quad(st, f as Array)

	# The four long faces, **sliced along the bar's length** (C-31). A box has two
	# rings of vertices and a shader can only bend what it has vertices for, so a
	# hand-drawn stroke needs the run of the bar to be somewhere the vertex shader
	# can reach. The slices cost geometry and no draw calls — still one MultiMesh,
	# still one call, which is what §20's budget reserved.
	for s: int in range(BAR_SEGMENTS):
		var xa: float = -h + float(s) / float(BAR_SEGMENTS)
		var xb: float = -h + float(s + 1) / float(BAR_SEGMENTS)
		_quad(st, [Vector3(xa, h, -h), Vector3(xa, h, h),
			Vector3(xb, h, h), Vector3(xb, h, -h)])
		_quad(st, [Vector3(xa, -h, h), Vector3(xa, -h, -h),
			Vector3(xb, -h, -h), Vector3(xb, -h, h)])
		_quad(st, [Vector3(xa, -h, h), Vector3(xb, -h, h),
			Vector3(xb, h, h), Vector3(xa, h, h)])
		_quad(st, [Vector3(xb, -h, -h), Vector3(xa, -h, -h),
			Vector3(xa, h, -h), Vector3(xb, h, -h)])
	st.generate_normals()
	return st.commit()


## One quad, listed anticlockwise seen from outside. Reversed on the way in,
## because Godot's front face is the clockwise one — every normal came out
## pointing into the bar until the winding test said so.
static func _quad(st: SurfaceTool, q: Array) -> void:
	for tri: Array in [[0, 2, 1], [0, 3, 2]]:
		for k: int in tri:
			st.add_vertex(q[k] as Vector3)


## §14.5, for the one loop this node owns (C-31). Reduce Motion stops a loop dead
## rather than slowing it (§14.5), and zero seconds is how the shader is told.
##
## Not routed through [method Motion.loops] like the tiles' breathing is, because
## that reads [constant Motion.TIMINGS] and §14.1's table is asserted row for row
## against the spec — it may not grow a fifteenth entry for a duration §13.1 asks
## for and §14.1 never tabulated. The number lives beside the thing it drives.
func set_motion() -> void:
	if material_override is ShaderMaterial:
		var period: float = 0.0 if SettingsService.reduce_motion() else PULSE_SECONDS
		(material_override as ShaderMaterial).set_shader_parameter("pulse_seconds", period)


## §21's escape hatch (C-24): with [param flat] the board takes no light, so a
## tile's colour on screen is its palette colour and a greyscale palette cannot be
## undone by a highlight. A uniform rather than a second shader, so there is one
## place the geometry and the colours are described.
func set_flat(flat: bool) -> void:
	if material_override is ShaderMaterial:
		(material_override as ShaderMaterial).set_shader_parameter("flat_board", flat)

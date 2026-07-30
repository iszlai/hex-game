## Every cell of the board as one hex prism, in a single draw call — §13.3's
## requirement on C-18's geometry instead of its canvas SDF.
##
## One `MultiMesh`, one instance per cell, and the whole of what a tile *is* travels
## per instance: its colour as the instance colour, its kind, cursor flag and depth
## along the path as its custom data. Nothing here allocates after [method bind]:
## a move rewrites the instance buffers in place, and there is no `_process` or
## `_draw` at all (C4 — the 2016 prototype allocated a texture per tile, B5).
##
## §21 without colour: a tile's **height** says what it is. A wall is a block, a
## joined cell stands proud of the board, an empty cell is a thin plate. That
## survives a greyscale palette and a monochrome screenshot, which is the test C5
## actually sets.
class_name BoardTiles
extends MultiMeshInstance3D

const SHADER := "res://src/view/shaders/hex_prism.gdshader"

## Kind codes, written into `INSTANCE_CUSTOM.r`. The shader reads these, so they are
## a wire format: append, never renumber.
enum Kind { EMPTY = 0, CANDIDATE = 1, PATH = 2, START = 3, WALL = 4 }

## Tile heights as a fraction of the cell circumradius, so the board keeps its
## proportions at every §4.4 size. Ordered, and the order is the point (§21).
const EMPTY_TOP := 0.16
const PATH_TOP := 0.28
const WALL_TOP := 0.52

## The tallest thing standing on the plane, which the projected fit has to reserve
## room for — see [constant BoardView3D.TILE_TOP_RATIO].
const MAX_TOP := WALL_TOP

## Prisms are drawn a little narrower than their cell, so the background shows
## between them. This is the 3D board's answer to `cell_empty_stroke`: without it,
## neighbouring tiles meet face to face and a field of empty cells reads as one
## unlit slab. The *hit* region is unaffected — [method BoardView3D.cell_at] rounds
## on the full cell, so a press in the gap still lands on the nearest tile.
const TILE_INSET := 0.93

## §14.1's placement pop starts here and settles at 1.0.
const POP_FROM := 0.82

@export var palette: Palette = null

var _board: Board = null
var _state: GameState = null
var _layout: HexLayout = null
var _index: Dictionary = {}         # Vector3i -> instance index
var _candidates: Dictionary = {}    # Vector3i -> true
var _cursor: Vector3i = Vector3i.ZERO
var _has_cursor: bool = false
var _depth: Dictionary = {}
## Cells mid-pop, and how far through §14.1's 0.82 → 1.0 they are. Empty almost
## always; one entry for the 220 ms after a placement.
var _pop: Dictionary = {}       # Vector3i -> scale factor
## Where the last §14.1 ripple left from. Every cell's distance to it rides in the
## instance data, so the wave needs no per-cell bookkeeping while it travels.
var _ripple_origin: Vector3i = Vector3i.ZERO
var _ripple: Tween = null


func _ready() -> void:
	if palette == null:
		palette = load("res://src/data/palettes/neon_dark.tres")


## Allocates the multimesh for [param state]'s board and fills it. Called once per
## level; every later change goes through [method rebuild], which allocates nothing.
func bind(state: GameState, layout: HexLayout) -> void:
	_state = state
	_board = state.board
	_layout = layout

	var cells: Array[Vector3i] = _board.cells()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = build_prism_mesh()
	mm.instance_count = cells.size()
	multimesh = mm

	_index.clear()
	for i: int in range(cells.size()):
		_index[cells[i]] = i

	if material_override == null:
		var mat := ShaderMaterial.new()
		mat.shader = load(SHADER)
		material_override = mat
		# §6's wall hatch, in the grey-box's own token: the two views cannot then
		# disagree about what a wall looks like.
		mat.set_shader_parameter("hatch_ink", palette.wall_stroke)
		mat.set_shader_parameter("side_ink", palette.board_tile_side)
	set_flat(SettingsService.flat_board())
	set_motion()
	# Or an unset uniform reads back as 0.0, which is a wave sitting on the origin.
	_set_ripple_time(-1.0)

	rebuild()


## Recomputes everything derived from the live state, in place. Called after each
## move, not each frame.
func rebuild() -> void:
	if multimesh == null or _state == null:
		return
	_depth = PathDepth.of(_state)
	for cell: Variant in _index:
		_write(cell as Vector3i)


func set_candidates(targets: Array[Vector3i]) -> void:
	_candidates.clear()
	for t: Vector3i in targets:
		_candidates[t] = true
	if multimesh != null:
		for cell: Variant in _index:
			_write(cell as Vector3i)


func set_cursor(cell: Vector3i, visible_cursor: bool = true) -> void:
	var previous: Vector3i = _cursor
	var had: bool = _has_cursor
	_cursor = cell
	_has_cursor = visible_cursor
	if multimesh == null:
		return
	# Two instances change, so only two are rewritten.
	if had and _index.has(previous):
		_write(previous)
	if _has_cursor and _index.has(_cursor):
		_write(_cursor)


func kind_of(cell: Vector3i) -> Kind:
	if _board == null:
		return Kind.EMPTY
	if _board.is_wall(cell):
		return Kind.WALL
	if cell == _board.start:
		return Kind.START
	if _state != null and _state.path.has(cell):
		return Kind.PATH
	if _candidates.has(cell):
		return Kind.CANDIDATE
	return Kind.EMPTY


## Height of [param kind] as a fraction of the circumradius. The whole §21 argument
## for the 3D board lives in this function being injective on what matters.
static func top_ratio(kind: Kind) -> float:
	match kind:
		Kind.WALL:
			return WALL_TOP
		Kind.PATH, Kind.START:
			return PATH_TOP
		_:
			return EMPTY_TOP


## How high [param cell]'s tile top stands above the plane, in world units. The
## marks of §6 sit on top of the tile they belong to and the tile under a mark can
## stand up mid-level, so [BoardMarks] asks the node that owns C-22's heights
## rather than keeping a second copy of them.
func top_of(cell: Vector3i) -> float:
	return _layout.size * top_ratio(kind_of(cell))


## A unit hex prism: pointy-top, circumradius 1 on the `(x, z)` plane, standing from
## `y = 0` to `y = 1`, so a per-instance scale is all a tile needs.
##
## The normals come from [method SurfaceTool.generate_normals] rather than by hand,
## which pins the winding to the engine's own convention instead of to my reading of
## it — the test then only has to assert that they point outward, and a board built
## inside-out fails headlessly rather than at the first screenshot.
##
## `UV.x` is the radial fraction, 0 at the centre of the top face and 1 at the rim;
## `UV.y` runs 0 at the plane to 1 at the top.
static func build_prism_mesh() -> ArrayMesh:
	var rim: Array[Vector3] = []
	for i: int in range(6):
		var a := deg_to_rad(60.0 * float(i) - 30.0)
		rim.append(Vector3(cos(a), 0.0, sin(a)))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Flat shading: without this, `generate_normals` averages the normals of every
	# face meeting at a corner, and a prism's top face comes out leaning sideways.
	st.set_smooth_group(-1)
	for i: int in range(6):
		var a: Vector3 = rim[i]
		var b: Vector3 = rim[(i + 1) % 6]
		var a_top := a + Vector3.UP
		var b_top := b + Vector3.UP
		# Top face, fanned from the centre.
		_add_triangle(st,
			[Vector3.UP, a_top, b_top],
			[Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 1.0)])
		# Side wall, as two triangles of one quad.
		_add_triangle(st,
			[a_top, a, b],
			[Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(1.0, 0.0)])
		_add_triangle(st,
			[a_top, b, b_top],
			[Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0)])
	st.generate_normals()
	return st.commit()


static func _add_triangle(st: SurfaceTool, points: Array[Vector3], uvs: Array[Vector2]) -> void:
	for i: int in range(3):
		st.set_uv(uvs[i])
		st.add_vertex(points[i])


## §14.1's placement pop: the tile that was just joined scales 0.82 → 1.0 over
## 220 ms, `BACK` / `EASE_OUT`, both taken from [Motion] rather than typed here.
##
## One tween writing one instance, for thirteen frames. It is not a `_process` —
## there is still nothing on this node that runs every frame in the ordinary case,
## which is the property C4 actually cares about.
func pop(cell: Vector3i) -> void:
	if multimesh == null or not _index.has(cell):
		return
	_pop[cell] = POP_FROM
	var tween := create_tween()
	Motion.shape(tween, "placement_pop")
	tween.tween_method(func(v: float) -> void: _set_pop(cell, v),
		POP_FROM, 1.0, Motion.seconds("placement_pop"))
	tween.finished.connect(func() -> void: _clear_pop(cell))


## §14.2's opening beat: the goal cell swells to 1.25 and settles back over 340 ms.
## The same channel the placement pop rides, because a cell can only be one size —
## and a goal that popped *and* flourished at once would fight itself.
func flourish(cell: Vector3i) -> void:
	if multimesh == null or not _index.has(cell):
		return
	# Eagerly, like the pop: a tween's first step lands next frame, and a goal that
	# spent that frame at its ordinary size reads as a stutter before the flourish.
	_set_pop(cell, 1.0 + (Motion.GOAL_FLOURISH_SCALE - 1.0) * 0.01)
	var tween := create_tween()
	Motion.shape(tween, "placement_pop")
	var half: float = float(Motion.GOAL_FLOURISH_MS) / 2000.0
	if SettingsService.reduce_motion():
		half *= Motion.REDUCE_MOTION_SCALE
	tween.tween_method(func(v: float) -> void: _set_pop(cell, v),
		1.0, Motion.GOAL_FLOURISH_SCALE, half)
	tween.tween_method(func(v: float) -> void: _set_pop(cell, v),
		Motion.GOAL_FLOURISH_SCALE, 1.0, half)
	tween.finished.connect(func() -> void: _clear_pop(cell))


## How far through its pop [param cell] is: 1.0 when it is not popping, which is
## what makes [method transform_of] the same function either way.
func pop_scale(cell: Vector3i) -> float:
	return float(_pop.get(cell, 1.0))


func _set_pop(cell: Vector3i, value: float) -> void:
	_pop[cell] = value
	if multimesh != null and _index.has(cell):
		_write(cell)


func _clear_pop(cell: Vector3i) -> void:
	_pop.erase(cell)
	if multimesh != null and _index.has(cell):
		_write(cell)


## Where [param cell]'s prism stands and how tall it is: the layout's plane position,
## scaled to the cell size, with the height its kind earns it — times its pop, which
## is 1.0 unless it was placed in the last 220 ms.
func transform_of(cell: Vector3i) -> Transform3D:
	var pop_factor: float = pop_scale(cell)
	var height: float = _layout.size * top_ratio(kind_of(cell)) * pop_factor
	var width: float = _layout.size * TILE_INSET * pop_factor
	return Transform3D(
		Basis().scaled(Vector3(width, height, width)),
		_layout.to_plane(cell)
	)


## What the tile *is*, for the shader: kind, cursor flag, and how far along the path
## it sits. Not how it looks — that is [method tint_of].
func custom_of(cell: Vector3i) -> Color:
	return Color(
		float(kind_of(cell)),
		1.0 if (_has_cursor and cell == _cursor) else 0.0,
		_depth_ratio(cell),
		float(Hex.distance(cell, _ripple_origin))
	)


## The three values that describe one instance are computed by the methods above and
## only *pushed* here, because instance data cannot be read back under the headless
## dummy renderer — a write goes into the rendering server and comes back as an
## identity transform. Keeping the arithmetic out of the push is what makes any of it
## assertable in CI.
func _write(cell: Vector3i) -> void:
	var i: int = int(_index[cell])
	multimesh.set_instance_transform(i, transform_of(cell))
	multimesh.set_instance_color(i, tint_of(cell))
	multimesh.set_instance_custom_data(i, custom_of(cell))


## The same reading as the grey-box's fills, from the same tokens (§13.2), so the
## two views cannot drift apart on what a cell's colour means.
func tint_of(cell: Vector3i) -> Color:
	match kind_of(cell):
		Kind.WALL:
			return palette.wall_fill
		Kind.START:
			return palette.start_cell
		Kind.PATH:
			return palette.path_at_depth(int(_depth.get(cell, 0)), maxi(1, _depth.size()))
		Kind.CANDIDATE:
			return palette.cell_empty_fill.lerp(palette.cell_candidate_stroke, 0.35)
		_:
			return palette.cell_empty_fill


func _depth_ratio(cell: Vector3i) -> float:
	if not _depth.has(cell) or _depth.size() <= 1:
		return 0.0
	return clampf(float(_depth[cell]) / float(_depth.size() - 1), 0.0, 1.0)


## §14.1's board ripple, leaving [param origin] — normally the goal just reached.
##
## Each cell's distance to the origin is written into the instance data once, up
## front, and the wave itself is a single uniform counting seconds. That is what
## keeps a wave crossing sixty-one cells to one tween and one number, rather than
## sixty-one staggered tweens.
func ripple_from(origin: Vector3i) -> void:
	if multimesh == null:
		return
	_ripple_origin = origin
	for cell: Variant in _index:
		_write(cell as Vector3i)
	if _ripple != null and _ripple.is_running():
		_ripple.kill()
	_set_ripple_time(0.0)
	var mat := material_override as ShaderMaterial
	mat.set_shader_parameter("ripple_step", Motion.ripple_step_seconds())
	# Long enough for the wave to reach the far rim: the tween runs §14.1's own
	# duration *plus* the delay the outermost cell is owed.
	var span: float = Motion.seconds("board_ripple") \
		+ float(_furthest_from(origin)) * Motion.ripple_step_seconds()
	_ripple = create_tween()
	Motion.shape(_ripple, "board_ripple")
	_ripple.tween_method(_set_ripple_time, 0.0, span, span)
	_ripple.finished.connect(func() -> void: _set_ripple_time(-1.0))


func ripple_time() -> float:
	return float((material_override as ShaderMaterial).get_shader_parameter("ripple_time"))


func _furthest_from(origin: Vector3i) -> int:
	var furthest: int = 0
	for cell: Variant in _index:
		furthest = maxi(furthest, Hex.distance(cell as Vector3i, origin))
	return furthest


func _set_ripple_time(value: float) -> void:
	if material_override is ShaderMaterial:
		(material_override as ShaderMaterial).set_shader_parameter("ripple_time", value)


## §21's escape hatch (C-24): with [param flat] the board takes no light, so a
## tile's colour on screen is its palette colour and a greyscale palette cannot be
## undone by a highlight. A uniform rather than a second shader, so there is one
## place the geometry and the colours are described.
func set_flat(flat: bool) -> void:
	if material_override is ShaderMaterial:
		(material_override as ShaderMaterial).set_shader_parameter("flat_board", flat)


## §14.1's candidate breathing, at §14.5's discretion: the period when it runs, and
## zero when Reduce Motion has stopped it. [Motion] owns both answers.
func set_motion() -> void:
	if material_override is ShaderMaterial:
		var period: float = Motion.seconds("candidate_breathing") \
			if Motion.loops("candidate_breathing") else 0.0
		(material_override as ShaderMaterial).set_shader_parameter("breathe_seconds", period)

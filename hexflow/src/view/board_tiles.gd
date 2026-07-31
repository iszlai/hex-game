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
## Thickened once, together, keeping every gap between them: C-22 puts a tile's
## *kind* in its height, so what has to survive a retune is the ordering and the
## fact that each step is visible from the §12.3 camera — not the numbers. A board
## of slabs reads as objects lying on a surface; the old set read as a relief cut
## into one.
const EMPTY_TOP := 0.26
const PATH_TOP := 0.42
const WALL_TOP := 0.74

## The tallest thing standing on the plane, which the projected fit has to reserve
## room for — see [constant BoardView3D.TILE_TOP_RATIO].
const MAX_TOP := WALL_TOP

## How much of the tile's half-width and height the top chamfer takes. Small: it is
## a cut edge, not a dome, and anything larger starts eating the face the §6 marks
## are drawn on.
const CHAMFER := 0.12

## Prisms are drawn a little narrower than their cell, so the background shows
## between them. This is the 3D board's answer to `cell_empty_stroke`: without it,
## neighbouring tiles meet face to face and a field of empty cells reads as one
## unlit slab. The *hit* region is unaffected — [method BoardView3D.cell_at] rounds
## on the full cell, so a press in the gap still lands on the nearest tile.
const TILE_INSET := 0.93

## §14.1's placement pop starts here and settles at 1.0.
const POP_FROM := 0.82

## §14.1's illegal shake: ±4 px sideways, and a red flash at 40% of the way to
## `danger`. The flash is *feedback* rather than motion, which is why §14.5 keeps it
## and drops only the movement.
const SHAKE_PIXELS := 4.0
const SHAKE_FLASH := 0.4

@export var palette: Palette = null

var _board: Board = null
var _state: GameState = null
var _layout: HexLayout = null
var _index: Dictionary = {}         # Vector3i -> instance index
var _candidates: Dictionary = {}    # Vector3i -> true
## Goal cells part-way through §14.2's conversion to path colour: 0 is still a
## goal, 1 is fully path, absent is neither.
var _settling: Dictionary = {}
var _cursor: Vector3i = Vector3i.ZERO
var _has_cursor: bool = false
var _depth: Dictionary = {}
## Cells mid-pop, and how far through §14.1's 0.82 → 1.0 they are. Empty almost
## always; one entry for the 220 ms after a placement.
var _pop: Dictionary = {}       # Vector3i -> scale factor
## Where the last §14.1 ripple left from. Every cell's distance to it rides in the
## instance data, so the wave needs no per-cell bookkeeping while it travels.
var _shake: Dictionary = {}     # Vector3i -> sideways offset in world units
var _shake_axis: Vector3 = Vector3.RIGHT
var _ripple_origin: Vector3i = Vector3i.ZERO
var _ripple: Tween = null


func _ready() -> void:
	if palette == null:
		palette = Palette.current()


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
		# The board's ink, shared with the modifier marks (C-23) rather than given a
		# token of its own — one outline colour is what makes them look drawn by the
		# same hand, and it already inverts with the surfaces in a light palette.
		mat.set_shader_parameter("tile_ink", palette.board_mark_outline)
		_apply_grain(mat)
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
##
## The top is **chamfered** rather than square. A hard 90° edge is what made these
## read as extruded shapes rather than as cut slabs: the top face and the side meet
## on one line, so the only thing separating a tile from the one behind it is
## colour. A chamfer gives the rim its own facet at its own angle to the key light,
## which is the bright line along the near edge of every tile in a drawn board.
##
## Cheaper than rounding the corners, and does the same job at this camera: what
## reads at 1280×800 is the lit facet, not the curvature of the silhouette.
static func build_prism_mesh() -> ArrayMesh:
	var rim: Array[Vector3] = []
	var lip: Array[Vector3] = []
	for i: int in range(6):
		var a := deg_to_rad(60.0 * float(i) - 30.0)
		var out := Vector3(cos(a), 0.0, sin(a))
		rim.append(out)
		lip.append(out * (1.0 - CHAMFER))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Flat shading: without this, `generate_normals` averages the normals of every
	# face meeting at a corner, and a prism's top face comes out leaning sideways.
	st.set_smooth_group(-1)
	var lip_v: float = 1.0 - CHAMFER
	for i: int in range(6):
		var a: Vector3 = rim[i]
		var b: Vector3 = rim[(i + 1) % 6]
		# The chamfer drops from the inset top down and out to the full-width rim.
		var a_lip: Vector3 = lip[i] + Vector3.UP
		var b_lip: Vector3 = lip[(i + 1) % 6] + Vector3.UP
		var a_top: Vector3 = a + Vector3.UP * (1.0 - CHAMFER)
		var b_top: Vector3 = b + Vector3.UP * (1.0 - CHAMFER)
		# Top face, fanned from the centre to the inset lip.
		_add_triangle(st,
			[Vector3.UP, a_lip, b_lip],
			[Vector2(0.0, 1.0), Vector2(lip_v, 1.0), Vector2(lip_v, 1.0)])
		# The chamfer itself, as two triangles of one quad.
		_add_triangle(st,
			[a_lip, a_top, b_top],
			[Vector2(lip_v, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 1.0)])
		_add_triangle(st,
			[a_lip, b_top, b_lip],
			[Vector2(lip_v, 1.0), Vector2(1.0, 1.0), Vector2(lip_v, 1.0)])
		# Side wall, from under the chamfer down to the plane.
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


## §14.1's illegal shake, on the cell that was refused. [param axis] is screen-right
## in board space — the spec says *horizontal*, which after a 60° turn is not the
## world's x any more, so the caller with the camera supplies it.
##
## §14.5 takes the movement and leaves the flash. "This is a motion reduction, not
## a feedback removal": a player who cannot see the board shake still has to be told
## the move was refused.
func shake(cell: Vector3i, axis: Vector3) -> void:
	if multimesh == null or not _index.has(cell):
		return
	_shake_axis = axis.normalized()
	_shake[cell] = SHAKE_PIXELS if not SettingsService.reduce_motion() else 0.0
	_write(cell)
	var tween := create_tween()
	Motion.shape(tween, "illegal_shake")
	tween.tween_method(func(v: float) -> void: _set_shake(cell, v),
		float(_shake[cell]), 0.0, Motion.seconds("illegal_shake"))
	tween.finished.connect(func() -> void: _clear_shake(cell))


## Whether [param cell] is mid-refusal, which is what turns its flash on. Separate
## from the offset because under §14.5 the offset is zero and the flash is not.
func is_shaking(cell: Vector3i) -> bool:
	return _shake.has(cell)


func shake_offset(cell: Vector3i) -> float:
	return float(_shake.get(cell, 0.0))


func _set_shake(cell: Vector3i, value: float) -> void:
	_shake[cell] = value
	if multimesh != null and _index.has(cell):
		_write(cell)


func _clear_shake(cell: Vector3i) -> void:
	_shake.erase(cell)
	if multimesh != null and _index.has(cell):
		_write(cell)


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
		_layout.to_plane(cell) + _shake_axis * shake_offset(cell)
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
	if is_shaking(cell):
		return _fill_of(cell).lerp(palette.danger, SHAKE_FLASH)
	if _settling.has(cell):
		# §14.2's last beat. Entering a goal makes it a path cell at once as far as
		# the rules are concerned, and the board used to show that at once too — so
		# the flourish played on a tile that had *already* stopped being a goal.
		# Held at the goal's own colour until t=340, then crossed over.
		return palette.goal_cell.lerp(_fill_of(cell), float(_settling[cell]))
	return _fill_of(cell)


## Holds [param cell] at the goal colour, from the moment it is entered.
##
## Called on the way *into* §14.2's sequence rather than at its end, because what
## the beat converts from has to still be there to convert.
func hold_goal(cell: Vector3i) -> void:
	if not _index.has(cell):
		return
	_settling[cell] = 0.0
	if multimesh != null:
		_write(cell)


## §14.2 at t=340: "goal cell settles, converts to path colour".
func settle_goal(cell: Vector3i) -> void:
	if not _settling.has(cell) or not _index.has(cell):
		return
	var seconds: float = float(Motion.GOAL_SETTLE_MS) / 1000.0
	if SettingsService.reduce_motion():
		# §14.5 shortens a transition rather than removing it: the cell still has to
		# arrive at path colour, or a reached goal would read as unreached.
		seconds *= Motion.REDUCE_MOTION_SCALE
	var tween := create_tween()
	Motion.shape(tween, "placement_pop")
	tween.tween_method(func(v: float) -> void: _set_settling(cell, v), 0.0, 1.0, seconds)
	tween.finished.connect(func() -> void: _clear_settling(cell))


## How far [param cell] has converted: 0 while it is still a goal, 1 once it is
## path, and absent when it is neither — worth being able to read rather than infer.
func settle_ratio(cell: Vector3i) -> float:
	return float(_settling.get(cell, 1.0))


func _set_settling(cell: Vector3i, value: float) -> void:
	_settling[cell] = value
	if multimesh != null and _index.has(cell):
		_write(cell)


func _clear_settling(cell: Vector3i) -> void:
	_settling.erase(cell)
	if multimesh != null and _index.has(cell):
		_write(cell)


func _fill_of(cell: Vector3i) -> Color:
	match kind_of(cell):
		Kind.WALL:
			return palette.wall_fill
		Kind.START:
			return palette.start_cell
		Kind.PATH:
			return palette.path_at_depth(int(_depth.get(cell, 0)), maxi(1, _depth.size()))
		Kind.CANDIDATE:
			# Barely lifted off an empty cell, and deliberately so. A candidate says
			# "this is reachable" and the cursor says "this is the one" — and when
			# both were loud, and both breathing, the board offered five answers and
			# marked none of them. The cursor keeps its glow; this steps back.
			#
			# What carries the candidate in greyscale is no longer this blend: the
			# seam wash lights the edge it would be entered across, which is a shape
			# and survives colour being taken away (§21).
			return palette.cell_empty_fill.lerp(palette.cell_candidate_stroke, 0.14)
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


## C-26's board material (§13.6), if the build has one. `grain_strength` stays at
## zero without it, which is exactly how the board rendered before — §13.6's
## replaceability rule cuts both ways, and `make art` may never have run here.
##
## How much of the material shows through. Raised from 0.35 once the halftone
## screen arrived: at a third it read as dirt on the tiles rather than as the
## printed surface it is meant to be.
##
## Still bounded by what it must not blur, which is the reason a number here is not
## just taste: §6's wall hatch and C-22's heights are both *cues*, and a material
## loud enough to compete with either would be trading a channel §21 depends on for
## a texture. `test_board_tiles.gd` holds the hatch's own contrast, so pushing this
## too far fails rather than merely looking busy.
const GRAIN_STRENGTH := 0.62


## How much of the drawn face shows.
##
## Not full. The drawing is a *shading* map and it multiplies, so what it costs is
## proportional to how bright the tile under it already is — which is backwards.
## At full strength the dark walls looked right and the near-white cursor and start
## tiles wore every crack and every halftone dot as dirt, because on a pale surface
## a multiply has the whole range to fall through.
##
## Held below the point where a light tile stops reading as lit. The computed rim is
## still suppressed underneath: the two are alternatives, not layers.
const FACE_STRENGTH := 0.5


func _apply_grain(mat: ShaderMaterial) -> void:
	var grain: Texture2D = Art.tile_grain()
	mat.set_shader_parameter("grain_map", grain)
	mat.set_shader_parameter("grain_strength", GRAIN_STRENGTH if grain != null else 0.0)
	# The drawn top (C-26), if the build has one. Optional in the same sense as
	# every other art file here: without it the board draws its computed outline
	# and loses nothing it depends on.
	var face: Texture2D = Art.tile_face()
	mat.set_shader_parameter("face_map", face)
	mat.set_shader_parameter("face_strength", FACE_STRENGTH if face != null else 0.0)


## §21's escape hatch (C-24): with [param flat] the board takes no light, so a
## tile's colour on screen is its palette colour and a greyscale palette cannot be
## undone by a highlight. A uniform rather than a second shader, so there is one
## place the geometry and the colours are described.
func set_flat(flat: bool) -> void:
	if not material_override is ShaderMaterial:
		return
	var mat: ShaderMaterial = material_override
	mat.set_shader_parameter("flat_board", flat)
	# The grain comes off with the lighting. C-24's promise is that a tile on screen
	# *is* its palette colour, and a value map multiplying it is one more thing
	# between the palette and the pixel — which is the whole thing §21 turned this
	# setting on to avoid.
	mat.set_shader_parameter("grain_strength", 0.0 if flat else
		(GRAIN_STRENGTH if Art.tile_grain() != null else 0.0))
	# And the drawn face with it, for the same reason and one more: the drawing
	# carries its own light and shade, and §21's flat board is a request to be shown
	# the palette rather than a rendering of it. What is left is the computed
	# outline, which is a shape rather than a shading.
	mat.set_shader_parameter("face_strength", 0.0 if flat else
		(FACE_STRENGTH if Art.tile_face() != null else 0.0))


## §14.1's candidate breathing, at §14.5's discretion: the period when it runs, and
## zero when Reduce Motion has stopped it. [Motion] owns both answers.
func set_motion() -> void:
	if material_override is ShaderMaterial:
		var period: float = Motion.seconds("candidate_breathing") \
			if Motion.loops("candidate_breathing") else 0.0
		(material_override as ShaderMaterial).set_shader_parameter("breathe_seconds", period)

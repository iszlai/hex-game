## @core — the board as one multimesh of hex prisms (§13.3 on C-18's geometry).
##
## The headless-checkable claims are: one draw call covers every cell, the instances
## stand where the projected layout says they stand, a move rewrites the buffers
## rather than reallocating them, and — the one that matters for §21 — a tile's
## kind is readable from its **height**, so the board survives a greyscale palette.
extends GutTest

const PLAY := Vector2(880.0, 688.0)

var _tiles: BoardTiles = null
var _state: GameState = null
var _layout: HexLayout = null
var _palette: Palette = null


func before_each() -> void:
	_palette = Palette.current()
	# Walls deliberately off the NE diagonal, so the fixture's straight route still
	# plays and the tests can place along it.
	_state = GameState.start(Fixtures.fixed_level(
		Fixtures.shortest_route_tiles(),
		Fixtures.cells([Vector3i(0, 1, -1), Vector3i(1, -1, 0)])
	))
	_layout = HexLayout.new(float(BoardCamera.fit_projected(3, PLAY, BoardTiles.MAX_TOP)))
	_tiles = BoardTiles.new()
	add_child_autofree(_tiles)
	_tiles.bind(_state, _layout)


## Read through the view's own accessors rather than through the multimesh: instance
## data goes into the rendering server, and the headless dummy renderer hands it back
## as an identity transform, so what CI can check is the arithmetic that feeds it.
func _transform_of(cell: Vector3i) -> Transform3D:
	return _tiles.transform_of(cell)


func _custom_of(cell: Vector3i) -> Color:
	return _tiles.custom_of(cell)


func _colour_of(cell: Vector3i) -> Color:
	return _tiles.tint_of(cell)


func _height_of(cell: Vector3i) -> float:
	return _transform_of(cell).basis.get_scale().y


func test_one_multimesh_holds_every_cell() -> void:
	assert_eq(_tiles.multimesh.instance_count, _state.board.cells().size())
	assert_eq(_tiles.multimesh.instance_count, 37, "the reference radius-3 board")
	assert_true(_tiles.multimesh.use_colors, "tint travels per instance")
	assert_true(_tiles.multimesh.use_custom_data, "and so does what the tile is")
	assert_eq(_tiles.get_child_count(), 0, "nothing per cell in the scene tree")


## C4: geometry is prebuilt, and there is no per-frame hook at all to allocate in.
func test_nothing_runs_per_frame() -> void:
	assert_false(_tiles.has_method("_process"), "no _process")
	assert_false(_tiles.has_method("_physics_process"), "no _physics_process")
	assert_false(_tiles.has_method("_draw"), "no _draw")


func test_instances_stand_where_the_layout_puts_them() -> void:
	for c: Vector3i in _state.board.cells():
		var t: Transform3D = _transform_of(c)
		var want: Vector3 = _layout.to_plane(c)
		assert_almost_eq(t.origin.x, want.x, 0.01, "%v x" % c)
		assert_almost_eq(t.origin.z, want.z, 0.01, "%v z" % c)
		assert_almost_eq(t.origin.y, 0.0, 0.01, "%v sits on the plane" % c)
		var scale: Vector3 = t.basis.get_scale()
		var width: float = _layout.size * BoardTiles.TILE_INSET
		assert_almost_eq(scale.x, width, 0.01, "%v is one cell wide, less the gap" % c)
		assert_almost_eq(scale.z, width, 0.01, "%v is one cell deep, less the gap" % c)
		assert_lt(width, _layout.size, "the gap is what separates neighbours (§13.2)")


## §21 / C5, in three dimensions: kind by height, so a greyscale palette or a
## monochrome screenshot still tells a wall from an empty cell from a joined one.
func test_kind_is_readable_from_height_alone() -> void:
	var wall: float = _height_of(Vector3i(0, 1, -1))
	var empty: float = _height_of(Vector3i(-1, 0, 1))
	var joined: float = _height_of(_state.board.start)
	assert_gt(wall, joined, "a wall is a block")
	assert_gt(joined, empty, "a joined cell stands proud of the board")
	# And the heights are proportional to the cell, so this holds at every §4.4 size.
	assert_almost_eq(wall, _layout.size * BoardTiles.WALL_TOP, 0.01)
	assert_almost_eq(empty, _layout.size * BoardTiles.EMPTY_TOP, 0.01)


func test_kinds_and_tints_come_from_the_palette() -> void:
	var wall := Vector3i(0, 1, -1)
	assert_eq(int(_custom_of(wall).r), BoardTiles.Kind.WALL)
	assert_eq(_colour_of(wall), _palette.wall_fill)

	assert_eq(int(_custom_of(_state.board.start).r), BoardTiles.Kind.START)
	assert_eq(_colour_of(_state.board.start), _palette.start_cell)

	var empty := Vector3i(-1, 0, 1)
	assert_eq(int(_custom_of(empty).r), BoardTiles.Kind.EMPTY)
	assert_eq(_colour_of(empty), _palette.cell_empty_fill)


## §6 gives a wall a 45° hatch, and it is the only cue a wall has that is neither
## its colour nor its height: `wall.fill` and `cell.empty.fill` are within 1% of
## each other in luminance, so on a greyscale palette height alone leaves a wall
## and an empty cell a few pixels of side face apart. The pattern itself is a
## screenshot; what CI can hold is that it is drawn in the grey-box's own token,
## so the two views cannot disagree about what a wall looks like.
func test_the_wall_hatch_is_inked_from_the_palette() -> void:
	var mat: ShaderMaterial = _tiles.material_override
	assert_eq(mat.get_shader_parameter("hatch_ink"), _palette.wall_stroke)
	assert_ne(_palette.wall_stroke, _palette.wall_fill,
		"a hatch the colour of its own fill is not a hatch")


func test_candidates_are_marked_and_then_unmarked() -> void:
	var cell := Vector3i(-1, 0, 1)
	_tiles.set_candidates([cell] as Array[Vector3i])
	assert_eq(int(_custom_of(cell).r), BoardTiles.Kind.CANDIDATE)
	assert_ne(_colour_of(cell), _palette.cell_empty_fill, "and reads differently")
	_tiles.set_candidates([] as Array[Vector3i])
	assert_eq(int(_custom_of(cell).r), BoardTiles.Kind.EMPTY)


func test_exactly_one_cell_carries_the_cursor() -> void:
	_tiles.set_cursor(Vector3i(-1, 0, 1))
	var flagged: Array[Vector3i] = []
	for c: Vector3i in _state.board.cells():
		if _custom_of(c).g > 0.5:
			flagged.append(c)
	assert_eq(flagged, [Vector3i(-1, 0, 1)] as Array[Vector3i])
	# Moving it clears the cell it left.
	_tiles.set_cursor(Vector3i(0, -1, 1))
	assert_almost_eq(_custom_of(Vector3i(-1, 0, 1)).g, 0.0, 0.001)
	assert_almost_eq(_custom_of(Vector3i(0, -1, 1)).g, 1.0, 0.001)
	_tiles.set_cursor(Vector3i(0, -1, 1), false)
	assert_almost_eq(_custom_of(Vector3i(0, -1, 1)).g, 0.0, 0.001, "hidden means unflagged")


## A move must rewrite the buffers, not rebuild them: the same allocation, the same
## mesh, one more raised tile.
func test_a_placement_raises_a_tile_without_reallocating() -> void:
	var mm: MultiMesh = _tiles.multimesh
	var mesh: Mesh = mm.mesh
	var target: Vector3i = _state.legal_targets()[0]
	assert_eq(int(_custom_of(target).r), BoardTiles.Kind.EMPTY)
	var before: float = _height_of(target)

	assert_true(_state.place(target), "the fixture's first tile must be placeable")
	_tiles.rebuild()

	assert_same(_tiles.multimesh, mm, "same multimesh")
	assert_same(_tiles.multimesh.mesh, mesh, "same mesh")
	assert_eq(_tiles.multimesh.instance_count, 37, "same instance count")
	assert_eq(int(_custom_of(target).r), BoardTiles.Kind.PATH)
	assert_gt(_height_of(target), before, "and it has stood up")


## The path gradient is the grey-box's, from the same tokens: the far end of a long
## path is a different colour from the near end, and the depth rides along in the
## custom data for the animation layer to use.
func test_the_path_gradient_follows_depth() -> void:
	for i: int in range(4):
		assert_true(_state.place(_state.legal_targets()[0]), "step %d" % i)
	_tiles.rebuild()
	var path: Array[Vector3i] = []
	for c: Vector3i in _state.board.cells():
		if _state.path.has(c) and c != _state.board.start:
			path.append(c)
	assert_gt(path.size(), 2, "a path long enough to have a gradient")
	var deepest: Vector3i = path[0]
	var nearest: Vector3i = path[0]
	for c: Vector3i in path:
		if _custom_of(c).b > _custom_of(deepest).b:
			deepest = c
		if _custom_of(c).b < _custom_of(nearest).b:
			nearest = c
	assert_almost_eq(_custom_of(deepest).b, 1.0, 0.001, "the far end is the far end")
	assert_lt(_custom_of(nearest).b, _custom_of(deepest).b, "and the near end is nearer")
	assert_ne(_colour_of(deepest), _colour_of(nearest),
		"so the gradient is visible along the path")


## §14.1's placement pop, which is the one animation the board owes the player for
## the only action they take. Asserted through the arithmetic rather than by
## watching it: the instance transform is the same function either way, times a
## factor that is 1.0 whenever nothing is popping.
func test_a_placed_tile_pops_from_below_full_size() -> void:
	var target: Vector3i = _state.legal_targets()[0]
	assert_true(_state.place(target), "the fixture's first tile must be placeable")
	_tiles.rebuild()
	var settled: Transform3D = _transform_of(target)

	_tiles.pop(target)
	assert_eq(_tiles.pop_scale(target), BoardTiles.POP_FROM, "§14.1 starts at 0.82")
	var popped: Transform3D = _transform_of(target)
	assert_lt(popped.basis.get_scale().x, settled.basis.get_scale().x, "narrower on the way in")
	assert_lt(popped.basis.get_scale().y, settled.basis.get_scale().y, "and shorter")
	assert_eq(popped.origin, settled.origin, "but in the same place")

	# And it lands exactly where it was, rather than near it.
	await wait_seconds(Motion.seconds("placement_pop") + 0.15)
	assert_eq(_tiles.pop_scale(target), 1.0, "a pop that never finishes is a shrunken tile")
	assert_eq(_transform_of(target), settled)


## Nothing else on the board moves while one tile pops.
func test_a_pop_touches_only_the_tile_that_popped() -> void:
	var target: Vector3i = _state.legal_targets()[0]
	var neighbour: Vector3i = _state.board.start
	var before: Transform3D = _transform_of(neighbour)
	_tiles.pop(target)
	assert_eq(_transform_of(neighbour), before, "%v must not move" % neighbour)
	assert_eq(_tiles.pop_scale(neighbour), 1.0)


## §14.1's board ripple. The wave is one uniform counting seconds and a per-cell
## distance living in the instance data, so what CI can hold is that the distances
## are right and that the wave starts and finishes — the brightness itself is the
## shader's, and a screenshot's.
func test_the_ripple_knows_how_far_every_cell_is_from_its_origin() -> void:
	var origin: Vector3i = _state.board.start
	_tiles.ripple_from(origin)
	for c: Vector3i in _state.board.cells():
		assert_eq(int(_custom_of(c).a), Hex.distance(c, origin),
			"%v is the wrong distance from the wave's origin" % c)
	assert_almost_eq(_tiles.ripple_time(), 0.0, 0.001, "and it leaves at once")


## A second goal starts a second wave from where *it* is, not from the first one.
func test_a_new_ripple_remeasures_from_its_own_origin() -> void:
	var far: Vector3i = Fixtures.GOAL
	_tiles.ripple_from(_state.board.start)
	_tiles.ripple_from(far)
	assert_eq(int(_custom_of(far).a), 0, "the new origin is zero from itself")
	assert_eq(int(_custom_of(_state.board.start).a), Hex.distance(_state.board.start, far))


## The wave has to outlive its own duration: the outermost cell does not start
## until it has been waited for, so a tween that stopped at 500 ms would cut the
## rim off the wave entirely.
func test_the_wave_runs_long_enough_to_reach_the_far_rim() -> void:
	_tiles.ripple_from(_state.board.start)
	var rim: int = 0
	for c: Vector3i in _state.board.cells():
		rim = maxi(rim, Hex.distance(c, _state.board.start))
	assert_gt(rim, 3, "the fixture board has a rim to reach")
	await wait_seconds(Motion.seconds("board_ripple")
		+ float(rim) * Motion.ripple_step_seconds() + 0.2)
	assert_eq(_tiles.ripple_time(), -1.0, "and parks when it is over")


## §14.1's illegal shake, and the half of §14.5 that is easiest to get wrong.
## "This is a motion reduction, not a feedback removal" — so Reduce Motion takes the
## movement and leaves the red flash, because a player who cannot see the board move
## still has to be told the move was refused.
func test_a_refused_cell_shakes_sideways_and_flashes_red() -> void:
	var cell := Vector3i(-1, 0, 1)
	var steady: Vector3 = _transform_of(cell).origin
	var fill: Color = _colour_of(cell)

	_tiles.shake(cell, Vector3.RIGHT)
	assert_eq(_tiles.shake_offset(cell), BoardTiles.SHAKE_PIXELS, "§14.1's 4 px, at once")
	assert_ne(_transform_of(cell).origin, steady, "and it moved")
	assert_almost_eq(_transform_of(cell).origin.y, steady.y, 0.001, "sideways, not upward")
	assert_ne(_colour_of(cell), fill, "with §14.1's red flash on it")

	await wait_seconds(Motion.seconds("illegal_shake") + 0.15)
	assert_eq(_transform_of(cell).origin, steady, "and it comes back exactly")
	assert_eq(_colour_of(cell), fill, "and stops being red")


func test_reduce_motion_keeps_the_flash_and_drops_the_movement() -> void:
	SettingsService.set_value("reduce_motion", true)
	var cell := Vector3i(-1, 0, 1)
	var steady: Vector3 = _transform_of(cell).origin
	var fill: Color = _colour_of(cell)

	_tiles.shake(cell, Vector3.RIGHT)
	assert_eq(_transform_of(cell).origin, steady, "§14.5: no shake")
	assert_ne(_colour_of(cell), fill, "but the refusal is still visible (§14.5)")
	SettingsService.set_value("reduce_motion", false)


## Horizontal means horizontal *on screen*. After a 60° turn the world's x is not
## the screen's, so the axis is the caller's to supply.
func test_the_shake_runs_along_whatever_axis_it_was_given() -> void:
	var cell := Vector3i(-1, 0, 1)
	var steady: Vector3 = _transform_of(cell).origin
	_tiles.shake(cell, Vector3.BACK)
	var moved: Vector3 = _transform_of(cell).origin - steady
	assert_almost_eq(moved.z, BoardTiles.SHAKE_PIXELS, 0.001, "along the axis given")
	assert_almost_eq(moved.x, 0.0, 0.001, "and not along any other")


## The winding is the engine's, not my reading of it: `generate_normals` derives the
## normals from the triangle order, so normals pointing the wrong way is a board
## rendered inside out — caught here rather than at the first screenshot.
func test_the_prism_is_wound_so_its_faces_point_outward() -> void:
	var mesh := BoardTiles.build_prism_mesh()
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_eq(verts.size(), 18 * 3, "6 top triangles and 12 side triangles")
	assert_eq(normals.size(), verts.size())

	var tops := 0
	var sides := 0
	for i: int in range(0, verts.size(), 3):
		var centroid: Vector3 = (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
		var n: Vector3 = normals[i]
		if absf(n.y) > 0.5:
			tops += 1
			assert_almost_eq(n.y, 1.0, 0.001, "the top face must face up")
			assert_almost_eq(centroid.y, 1.0, 0.001, "and be the top")
		else:
			sides += 1
			var outward := Vector3(centroid.x, 0.0, centroid.z).normalized()
			assert_gt(n.dot(outward), 0.9, "a side must face away from the centre")
	assert_eq(tops, 6, "six top triangles")
	assert_eq(sides, 12, "twelve side triangles")


func test_the_prism_is_a_unit_pointy_top_hexagon() -> void:
	var arrays: Array = BoardTiles.build_prism_mesh().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var widest := 0.0
	var tallest := 0.0
	for v: Vector3 in verts:
		widest = maxf(widest, Vector2(v.x, v.z).length())
		tallest = maxf(tallest, v.y)
		assert_gte(v.y, 0.0, "the prism stands on the plane, never below it")
	assert_almost_eq(widest, 1.0, 0.001, "unit circumradius")
	assert_almost_eq(tallest, 1.0, 0.001, "unit height, scaled per instance")
	# Pointy-top: a vertex straight ahead on the z axis, flat sides left and right.
	var has_point := false
	for v: Vector3 in verts:
		if absf(v.x) < 0.001 and absf(absf(v.z) - 1.0) < 0.001:
			has_point = true
	assert_true(has_point, "a corner on the z axis, matching HexLayout's corners")

## @core — the path as one continuous stroke (§13.3 on C-18's geometry).
##
## The connectors carry what the tiles cannot. [BoardTiles] says *which* cells are
## joined; only the ribbon says in what **order** they were joined, which is the
## whole of §13.3's "reads as one continuous stroke" and the only thing that keeps
## a path that doubles back through its own row unambiguous. So the claims here are
## about the run of the ribbon, its gradient, and the fact that it shrinks again on
## undo — plus the buffer discipline that keeps a placement from reallocating.
extends GutTest

const PLAY := Vector2(880.0, 688.0)

var _view: BoardView3D = null
var _links: BoardLinks = null
var _tiles: BoardTiles = null
var _state: GameState = null
var _layout: HexLayout = null
var _palette: Palette = null


func before_each() -> void:
	_palette = load("res://src/data/palettes/neon_dark.tres")
	_state = GameState.start(Fixtures.fixed_level(Fixtures.shortest_route_tiles()))
	_bind(_state)


func _bind(state: GameState) -> void:
	_view = BoardView3D.new()
	add_child_autofree(_view)
	_view.bind(state, PLAY)
	_links = _view.links
	_tiles = _view.tiles
	_layout = _view.layout


## A level whose straight NE route runs into a portal, so the path takes a jump and
## the ribbon has to draw a tether. The fixture board's own portals sit off the
## diagonal on purpose, which is exactly why they cannot serve here.
func _portal_state() -> GameState:
	var board := Board.build(
		3, Fixtures.START, Fixtures.cells([Fixtures.GOAL]), [] as Array[Vector3i],
		[[Vector3i(-1, 0, 1), Vector3i(2, -1, -1)]]
	)
	var level := Level.build(board, Fixtures.dirs(Fixtures.shortest_route_tiles()))
	level.id = "fixture_portal_route"
	return GameState.start(level)


func _place_along_the_route(steps: int) -> void:
	for i: int in range(steps):
		assert_true(_state.place(_state.legal_targets()[0]), "step %d must be placeable" % i)
		_view.rebuild()


func _links_only() -> Array:
	var out: Array = []
	for i: int in range(_links.count()):
		if _links.kind_of(i) == BoardLinks.Kind.LINK:
			out.append(i)
	return out


func test_the_ribbon_starts_empty_and_grows_one_bar_per_placement() -> void:
	assert_eq(_links.count(), 0, "nothing is joined yet, so there is no stroke")
	assert_eq(_links.multimesh.visible_instance_count, 0)
	for i: int in range(4):
		_place_along_the_route(1)
		assert_eq(_links.count(), i + 1, "one bar per step")
		assert_eq(_links.multimesh.visible_instance_count, i + 1,
			"and only the live prefix is drawn")


## C4: the buffer is sized once for the worst case a level can reach, and a
## placement rewrites instances rather than reallocating them.
func test_a_placement_never_reallocates_the_buffer() -> void:
	var mm: MultiMesh = _links.multimesh
	var mesh: Mesh = mm.mesh
	var capacity: int = mm.instance_count
	assert_gte(capacity, _state.board.size() - 1, "room for the longest path")
	_place_along_the_route(5)
	assert_same(_links.multimesh, mm, "same multimesh")
	assert_same(_links.multimesh.mesh, mesh, "same mesh")
	assert_eq(_links.multimesh.instance_count, capacity, "same allocation")


## Every edge joins exactly one previously unjoined cell, so the path can never
## outrun the buffer. Played to exhaustion rather than argued, because an
## off-by-one here is a silently vanishing connector.
func test_the_ribbon_never_outruns_its_buffer() -> void:
	var state := GameState.start(Fixtures.seeded_level(20260730))
	_bind(state)
	var guard: int = 0
	while state.legal_targets().size() > 0 and guard < 200:
		state.place(state.legal_targets()[0])
		_view.rebuild()
		assert_lte(_links.count(), _links.multimesh.instance_count,
			"the ribbon must fit the buffer at %d placements" % state.placements)
		guard += 1
	assert_gt(state.placements, 3, "the fixture must actually have played")


func test_nothing_runs_per_frame() -> void:
	assert_false(_links.has_method("_process"), "no _process")
	assert_false(_links.has_method("_draw"), "no _draw")


## A bar runs from one tile top to the next and stands *on* them. Half-sunk is how
## the first attempt looked on screen: a ribbon the colour of the tile beneath it,
## buried in that tile, is a ribbon nobody can see.
func test_a_bar_runs_between_the_two_tile_tops_it_joins() -> void:
	_place_along_the_route(3)
	var segs: Array = _links.segments()
	for i: int in range(segs.size()):
		var edge: Array = _state.edges[i]
		var from: Vector3i = edge[0]
		var to: Vector3i = edge[2]
		var a: Vector3 = (segs[i] as Array)[0]
		var b: Vector3 = (segs[i] as Array)[1]
		assert_almost_eq(a.x, _layout.to_plane(from).x, 0.01, "bar %d leaves %v" % [i, from])
		assert_almost_eq(b.z, _layout.to_plane(to).z, 0.01, "bar %d arrives at %v" % [i, to])
		assert_gt(a.y, _tiles.top_of(from), "and rides above the tile top, not in it")
		# The instance itself is lifted by half its thickness, so the bar's underside
		# rests on the surface instead of straddling it.
		var origin: Vector3 = _links.transform_of(i).origin
		assert_gt(origin.y, (a.y + b.y) * 0.5, "bar %d stands on the tiles" % i)


func test_a_bar_is_as_long_as_the_step_it_draws() -> void:
	_place_along_the_route(2)
	var neighbours: float = _layout.to_plane(Vector3i.ZERO).distance_to(
		_layout.to_plane(Direction.delta(0)))
	for i: int in _links_only():
		var scale: Vector3 = _links.transform_of(i).basis.get_scale()
		assert_almost_eq(scale.x, neighbours, 0.01, "bar %d spans one lattice step" % i)
		assert_almost_eq(scale.z, _layout.size * BoardLinks.LINK_WIDTH, 0.01, "and its width")


## §13.3: the stroke carries the depth gradient, so which end is the near end
## survives even where the route crosses itself.
func test_the_stroke_carries_the_depth_gradient() -> void:
	_place_along_the_route(5)
	var live: Array = _links_only()
	assert_gt(live.size(), 3, "a stroke long enough to have a gradient")
	assert_ne(_links.tint_of(live[0]), _links.tint_of(live[live.size() - 1]),
		"the far end of the stroke is a different colour from the near end")
	# And it is the palette's gradient, not an invention of this node's.
	var last: Vector3i = (_state.edges[live[live.size() - 1]] as Array)[2]
	var depth: Dictionary = PathDepth.of(_state)
	assert_eq(_links.tint_of(live[live.size() - 1]),
		_palette.path_at_depth(int(depth[last]), maxi(1, depth.size()))
			.lightened(BoardLinks.LINK_LIGHTEN))


## The ribbon has to come back down. `edges` is popped on undo, so a stroke that
## only ever grew would leave the undone step lit — which is the one thing the
## player would read as "that move still counts".
func test_undo_shortens_the_stroke() -> void:
	_place_along_the_route(4)
	var before: int = _links.count()
	assert_true(_state.undo(), "the fixture must be undoable")
	_view.rebuild()
	assert_eq(_links.count(), before - 1, "the undone step is no longer drawn")
	assert_eq(_links.multimesh.visible_instance_count, before - 1)


## A portal jump is not a lattice step and must not draw like one (§6): dashes, and
## a thinner ribbon — two channels that are not colour (§21).
func test_a_portal_jump_draws_as_a_dashed_tether() -> void:
	var state := _portal_state()
	_bind(state)
	# Two NE steps reach the portal at (-1, 0, 1), which drags in its twin.
	for i: int in range(2):
		assert_true(state.place(state.legal_targets()[0]), "step %d" % i)
	_view.rebuild()

	var dashes: Array = []
	for i: int in range(_links.count()):
		if _links.kind_of(i) == BoardLinks.Kind.TETHER:
			dashes.append(i)
	assert_eq(dashes.size(), BoardLinks.TETHER_DASHES, "one tether, cut into dashes")

	var link_width: float = _layout.size * BoardLinks.LINK_WIDTH
	for i: int in dashes:
		assert_lt(_links.transform_of(i).basis.get_scale().z, link_width,
			"a tether is the thinner stroke")
		assert_eq(_links.tint_of(i), _palette.portal, "and it is the portal's own colour")
		assert_almost_eq(_links.custom_of(i).r, float(BoardLinks.Kind.TETHER), 0.001,
			"so the shader can leave it unlit — §6 calls it faint")

	# Dashes, not one long bar: consecutive pieces must not touch.
	var segs: Array = _links.segments()
	var first_end: Vector3 = (segs[dashes[0]] as Array)[1]
	var second_start: Vector3 = (segs[dashes[1]] as Array)[0]
	assert_gt(first_end.distance_to(second_start), 1.0, "there is a gap between dashes")


func test_a_tether_runs_between_its_two_portal_cells() -> void:
	var state := _portal_state()
	_bind(state)
	for i: int in range(2):
		assert_true(state.place(state.legal_targets()[0]), "step %d" % i)
	_view.rebuild()

	var a: Vector3 = _layout.to_plane(Vector3i(-1, 0, 1))
	var b: Vector3 = _layout.to_plane(Vector3i(2, -1, -1))
	var span: float = a.distance_to(b)
	assert_gt(span, _layout.size * 2.0, "the twins are not neighbours, which is the point")
	var segs: Array = _links.segments()
	for i: int in range(_links.count()):
		if _links.kind_of(i) != BoardLinks.Kind.TETHER:
			continue
		for end: Variant in [(segs[i] as Array)[0], (segs[i] as Array)[1]]:
			var p: Vector3 = end as Vector3
			# On the segment between the two portals: the two legs sum to the whole.
			var flat := Vector3(p.x, 0.0, p.z)
			assert_almost_eq(flat.distance_to(a) + flat.distance_to(b), span, 0.5,
				"dash %d strays off the line between the twins" % i)


func test_the_bar_is_a_unit_cube_wound_outward() -> void:
	var mesh := BoardLinks.build_bar_mesh()
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_eq(verts.size(), 36, "six faces of two triangles")
	for v: Vector3 in verts:
		assert_almost_eq(absf(v.x), 0.5, 0.001, "centred on its own origin")
		assert_almost_eq(absf(v.y), 0.5, 0.001)
		assert_almost_eq(absf(v.z), 0.5, 0.001)
	# Winding is the engine's convention rather than a reading of it, as it is for
	# the prism: a bar built inside out fails here instead of on a screenshot.
	for i: int in range(0, verts.size(), 3):
		var centroid: Vector3 = (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
		assert_gt(normals[i].dot(centroid.normalized()), 0.5,
			"face at %v must point away from the centre" % centroid)

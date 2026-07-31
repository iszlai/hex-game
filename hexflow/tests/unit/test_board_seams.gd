## @core — the edge a placement would cross (§12.3's candidate set, made unambiguous).
##
## The claim worth testing is not that bars appear. It is that each bar is on the
## **right edge**: a candidate is entered from exactly one anchor, and the seam is a
## promise about which one. A seam on the wrong boundary would be the board saying
## the line is about to arrive from a cell it will not arrive from — worse than
## drawing nothing, because a player would plan around it.
##
## So the expected edge is never written down here. It is taken from
## [method GameState.anchor_of], which is what the commit itself uses, and the
## geometry is measured against the layout's own cell centres.
extends GutTest

const PLAY := Vector2(880.0, 688.0)

var _view: BoardView3D = null
var _state: GameState = null


func before_each() -> void:
	SettingsService.set_value("reduce_motion", true)
	_state = GameState.start(Fixtures.fixed_level(Fixtures.shortest_route_tiles()))
	_view = BoardView3D.new()
	add_child_autofree(_view)
	_view.bind(_state, PLAY)


func after_each() -> void:
	SettingsService.set_value("reduce_motion", false)


func _targets() -> Array[Vector3i]:
	return _state.legal_targets()


## A path that has doubled back, so several path cells can each reach a *different*
## free neighbour with the tile in hand.
##
## This is the case the seams exist for. A straight run offers exactly one
## candidate, and one candidate has no ambiguity to resolve — the fixture has to be
## bent before the feature has anything to say.
func _fork() -> Array[Vector3i]:
	_state = GameState.start(Fixtures.fixed_level(
		["NE", "NE", "E", "E", "E"] as Array[String]))
	for _i: int in range(2):
		_state.place(_state.legal_targets()[0])
	_view.bind(_state, PLAY)
	var targets: Array[Vector3i] = _state.legal_targets()
	assert_gt(targets.size(), 1, "the fork fixture must offer more than one anchor")
	return targets


func test_one_seam_per_candidate() -> void:
	var targets: Array[Vector3i] = _targets()
	assert_gt(targets.size(), 0, "the fixture has to offer a move to be worth testing")
	_view.set_candidates(targets)
	assert_eq(_view.seams.count(), targets.size(), "every candidate gets its own edge")

	_view.set_candidates([] as Array[Vector3i])
	assert_eq(_view.seams.count(), 0, "and nothing is left lit when there is no move")


## The seam lies on the boundary between the candidate and the cell it is entered
## from — measured as "equidistant from both centres", which is what a shared edge
## is, rather than as a coordinate copied out of the implementation.
func test_each_seam_sits_on_the_boundary_it_promises() -> void:
	var targets: Array[Vector3i] = _targets()
	_view.set_candidates(targets)
	var layout: HexLayout = _view.layout

	for i: int in range(_view.seams.count()):
		var centre: Vector3 = _view.seams.transform_of(i).origin
		var flat := Vector2(centre.x, centre.z)
		var best: float = INF
		var owner: Vector3i = Vector3i.ZERO
		for t: Vector3i in targets:
			var p: Vector3 = layout.to_plane(t)
			var d: float = flat.distance_to(Vector2(p.x, p.z))
			if d < best:
				best = d
				owner = t
		var anchor: Vector3i = _state.anchor_of(owner)
		var a: Vector3 = layout.to_plane(anchor)
		var b: Vector3 = layout.to_plane(owner)
		assert_almost_eq(
			flat.distance_to(Vector2(a.x, a.z)), flat.distance_to(Vector2(b.x, b.z)),
			0.001, "the seam for %s is not on its shared edge with %s" % [owner, anchor])


## A seam runs *across* the step, not along it — it is the edge being crossed
## rather than the crossing. Asserted as a right angle so the test survives the bar
## being retuned.
func test_a_seam_runs_across_the_step_it_marks() -> void:
	var targets: Array[Vector3i] = _targets()
	_view.set_candidates(targets)
	var layout: HexLayout = _view.layout

	for i: int in range(_view.seams.count()):
		var basis: Basis = _view.seams.transform_of(i).basis
		var along: Vector3 = basis.x.normalized()
		var centre: Vector3 = _view.seams.transform_of(i).origin
		var nearest: Vector3i = targets[0]
		var best: float = INF
		for t: Vector3i in targets:
			var d: float = centre.distance_to(layout.to_plane(t))
			if d < best:
				best = d
				nearest = t
		var step: Vector3 = (layout.to_plane(nearest)
			- layout.to_plane(_state.anchor_of(nearest))).normalized()
		assert_almost_eq(along.dot(step), 0.0, 0.001,
			"the seam for %s runs along its step instead of across it" % nearest)


## The wash lies on the **candidate's** own face — it marks the cell being offered,
## so it belongs at that cell's height rather than at the taller neighbour's.
func test_a_seam_lies_on_the_candidate_it_offers() -> void:
	var targets: Array[Vector3i] = _targets()
	_view.set_candidates(targets)
	for i: int in range(_view.seams.count()):
		var centre: Vector3 = _view.seams.transform_of(i).origin
		var nearest: Vector3i = targets[0]
		var best: float = INF
		for t: Vector3i in targets:
			var d: float = centre.distance_to(_view.layout.to_plane(t))
			if d < best:
				best = d
				nearest = t
		var top: float = _view.tiles.top_of(nearest)
		assert_gt(centre.y, top, "the seam for %s is sunk into its own tile" % nearest)
		assert_lt(centre.y, top + _view.layout.size * 0.05,
			"the seam for %s floats above the face it washes" % nearest)


## C4: the buffer is sized for the worst case once, and a new candidate set rewrites
## instances rather than reallocating them.
func test_a_new_candidate_set_never_reallocates() -> void:
	_view.set_candidates(_targets())
	var mm: MultiMesh = _view.seams.multimesh
	var allocated: int = mm.instance_count
	assert_gte(allocated, _view.seams.count())
	_view.set_candidates([] as Array[Vector3i])
	_view.set_candidates(_targets())
	assert_same(_view.seams.multimesh, mm, "same multimesh")
	assert_eq(mm.instance_count, allocated, "same allocation")


func test_nothing_runs_per_frame() -> void:
	assert_false(_view.seams.has_method("_process"), "no _process")
	assert_false(_view.seams.has_method("_draw"), "no _draw")


## §13.2: not one colour in a script. The seam takes the path's token, because it is
## a preview of the connector that replaces it.
func test_the_seam_takes_its_colour_from_the_palette() -> void:
	var palette: Palette = _view.palette
	assert_ne(_view.seams.seam_colour(), palette.cell_candidate_stroke,
		"gold on a gold candidate reads as a rim, not an opening")
	assert_gt(_view.seams.seam_colour().get_luminance(), palette.path_core.get_luminance(),
		"the seam sits in a crevice and has to be lifted out of it")


## The whole point, on a path with more than one anchor: with several candidates
## spread around a route that has doubled back, *which cell each one connects from*
## is exactly what the tint alone cannot say — and every seam still has to land on
## its own boundary.
func test_a_forked_path_gets_one_correct_seam_per_anchor() -> void:
	var targets: Array[Vector3i] = _fork()
	_view.set_candidates(targets)
	assert_eq(_view.seams.count(), targets.size())

	var anchors: Dictionary = {}
	var layout: HexLayout = _view.layout
	for t: Vector3i in targets:
		anchors[_state.anchor_of(t)] = true
		var a: Vector3 = layout.to_plane(_state.anchor_of(t))
		var b: Vector3 = layout.to_plane(t)
		var want := Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
		var found: bool = false
		for i: int in range(_view.seams.count()):
			var o: Vector3 = _view.seams.transform_of(i).origin
			if want.distance_to(Vector2(o.x, o.z)) < 0.001:
				found = true
				break
		assert_true(found, "no seam on the edge %s would be entered by" % t)
	assert_gt(anchors.size(), 1,
		"the fixture is meant to reach these from different cells")


## The wash reaches *into* the candidate, not back over the path cell it came from.
## Its local z is the direction it spreads, and the far end of it has to sit nearer
## the candidate's centre than the boundary does.
func test_the_wash_spreads_into_the_cell_being_offered() -> void:
	var targets: Array[Vector3i] = _fork()
	_view.set_candidates(targets)
	var layout: HexLayout = _view.layout
	for t: Vector3i in targets:
		var anchor: Vector3i = _state.anchor_of(t)
		var a: Vector3 = layout.to_plane(anchor)
		var b: Vector3 = layout.to_plane(t)
		var boundary := Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
		for i: int in range(_view.seams.count()):
			var xf: Transform3D = _view.seams.transform_of(i)
			if boundary.distance_to(Vector2(xf.origin.x, xf.origin.z)) > 0.001:
				continue
			var far: Vector3 = xf.origin + xf.basis.z
			var centre := Vector2(b.x, b.z)
			assert_lt(centre.distance_to(Vector2(far.x, far.z)),
				centre.distance_to(boundary),
				"the wash for %s spreads backwards over %s" % [t, anchor])
			# And it stops short of crossing the cell: a lit edge, not a lit cell.
			assert_lt(xf.basis.z.length(), layout.size * 0.87,
				"the wash for %s reaches past the middle of the cell" % t)

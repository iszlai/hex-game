## @core — the 2D grey-box, which §26 requires to keep working through M7.
##
## It used to be covered transitively: `level.tscn` instantiated it, so every e2e
## playthrough drove it. C-18's board took that slot, and a view nothing exercises
## is a view that rots quietly until the day someone needs it — for a headless
## capture, for a renderer bisect, or because the 3D board is the thing that broke.
## So the grey-box now has its own test, small and about the things the 3D board
## also promises: where cells land, and that a click comes back to the cell clicked.
extends GutTest

const PLAY := Vector2(880.0, 688.0)

var _view: BoardView = null
var _state: GameState = null


func before_each() -> void:
	_view = BoardView.new()
	add_child_autofree(_view)
	_state = GameState.start(Fixtures.fixed_level(Fixtures.shortest_route_tiles()))
	_view.bind(_state, PLAY)


func test_binding_sizes_the_board_by_the_head_on_fit() -> void:
	assert_eq(int(_view.layout.size), HexLayout.fit(3, PLAY))
	assert_eq(_view.centres().size(), _state.board.cells().size())


func test_every_cell_round_trips_from_its_drawn_centre() -> void:
	for c: Vector3i in _state.board.cells():
		assert_eq(_view.cell_at(_view.centre_of(c)), c, "%v must round-trip" % c)


## The depth traversal is shared with the 3D board (`PathDepth`), so this is also
## what stops an edit for one view from silently changing the other.
func test_the_path_gradient_still_follows_the_shared_depth() -> void:
	for i: int in range(3):
		assert_true(_state.place(_state.legal_targets()[0]), "step %d" % i)
	_view.rebuild()
	var depth: Dictionary = PathDepth.of(_state)
	assert_eq(depth.size(), 4, "start plus three placements")
	assert_eq(int(depth[_state.board.start]), 0)


func test_candidates_and_cursor_are_accepted_without_a_state_change() -> void:
	var targets: Array[Vector3i] = _state.legal_targets()
	_view.set_candidates(targets)
	_view.set_cursor(targets[0])
	_view.set_cursor(targets[0], false)
	assert_eq(_state.placements, 0, "a view never changes the game")

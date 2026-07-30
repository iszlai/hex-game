## @core — the rail's tile stack (§12.3 as C-18 rewrote it).
##
## The claim worth testing is not that pieces appear. It is that the arrow on a
## piece points **where that tile will actually go on the board** — including
## after the player has turned the board, when the same direction runs a different
## way across the screen. An arrow that always pointed the same way would be a lie
## at five of the six stops, and the player would follow it.
##
## So the expected angle is never written down here. It is measured from the real
## board's own screen positions, which is the only thing that can disagree with
## the rail.
extends GutTest

const PLAY := Vector2(880.0, 688.0)

var _stack: TileStack = null
var _view: BoardView3D = null
var _state: GameState = null


func before_each() -> void:
	SettingsService.set_value("reduce_motion", true)   # real tweens, quickly
	_state = GameState.start(Fixtures.fixed_level(Fixtures.shortest_route_tiles()))
	_view = BoardView3D.new()
	add_child_autofree(_view)
	_view.bind(_state, PLAY)
	_stack = TileStack.new()
	_stack.slots = 3
	add_child_autofree(_stack)


func after_each() -> void:
	SettingsService.set_value("reduce_motion", false)


func _all_six() -> Array[int]:
	var out: Array[int] = []
	for d: int in Direction.ALL:
		out.append(d)
	return out


## Which way the arrow on piece [param i] points, in the same y-down screen space
## the board's own positions are expressed in. The glyph's space has y up, which
## is the whole reason the angle is negated on the way into the shader.
func _points(i: int) -> Vector2:
	var spin: float = _stack.arrow_custom(i).b
	return Vector2(cos(spin), -sin(spin))


## Which way a step in [param dir] actually runs on screen, taken from the board.
func _board_run(dir: int) -> Vector2:
	var from: Vector2 = _view.centre_of(Vector3i.ZERO)
	var to: Vector2 = _view.centre_of(Direction.delta(dir))
	return (to - from).normalized()


func test_it_shows_the_soonest_tiles_and_no_more_than_its_slots() -> void:
	_stack.show_tiles([0, 1, 2, 3, 4] as Array[int])
	assert_eq(_stack.count(), 3, "three slots hold three tiles")
	assert_eq(_stack.pieces.multimesh.visible_instance_count, 3)
	assert_eq(_stack.arrows.multimesh.visible_instance_count, 3, "one arrow per piece")

	# A stream running out shows what is left, not a gap.
	_stack.show_tiles([0] as Array[int])
	assert_eq(_stack.count(), 1)
	assert_eq(_stack.pieces.multimesh.visible_instance_count, 1)
	_stack.show_tiles([] as Array[int])
	assert_eq(_stack.pieces.multimesh.visible_instance_count, 0, "and nothing when empty")


## C4: the buffer is sized for every slot the control will ever show, so the
## stream advancing rewrites instances rather than reallocating them.
func test_advancing_the_stream_never_reallocates() -> void:
	_stack.show_tiles([0, 1, 2] as Array[int])
	var mm: MultiMesh = _stack.pieces.multimesh
	assert_eq(mm.instance_count, 3, "one slot's worth of allocation, once")
	_stack.show_tiles([3, 4, 5] as Array[int])
	assert_same(_stack.pieces.multimesh, mm, "same multimesh")
	assert_eq(_stack.pieces.multimesh.instance_count, 3, "same allocation")


func test_nothing_runs_per_frame() -> void:
	assert_false(_stack.has_method("_process"), "no _process")
	assert_false(_stack.has_method("_draw"), "no _draw")


## A deck, not a row: the soonest tile is the biggest and the one in front, and
## each further piece steps back and shrinks.
func test_the_soonest_tile_is_the_front_of_the_deck() -> void:
	_stack.show_tiles([0, 1, 2] as Array[int])
	for i: int in range(1, 3):
		var front: Transform3D = _stack.piece_transform(i - 1)
		var behind: Transform3D = _stack.piece_transform(i)
		assert_gt(front.basis.get_scale().x, behind.basis.get_scale().x,
			"piece %d must be smaller than the one in front of it" % i)
		assert_lt(behind.origin.z, front.origin.z, "and stand further back")
		assert_gt(behind.origin.x, front.origin.x, "and along the spread")


func test_an_arrow_sits_on_the_piece_it_belongs_to() -> void:
	_stack.show_tiles([0, 1, 2] as Array[int])
	for i: int in range(3):
		var piece: Transform3D = _stack.piece_transform(i)
		var arrow: Transform3D = _stack.arrow_transform(i)
		assert_almost_eq(arrow.origin.x, piece.origin.x, 0.001, "arrow %d is centred" % i)
		assert_almost_eq(arrow.origin.z, piece.origin.z, 0.001)
		assert_gt(arrow.origin.y, piece.basis.get_scale().y, "and clears the piece's top")
		assert_lt(arrow.basis.get_scale().x, piece.basis.get_scale().x,
			"and fits on it")


## The claim: an arrow points where its tile will go. Checked against the board's
## own screen positions rather than against a written-down angle, for all six
## directions — a table would pass just as happily with the whole thing mirrored.
func test_every_arrow_points_where_its_tile_will_go() -> void:
	for dir: int in _all_six():
		_stack.show_tiles([dir] as Array[int])
		_stack.set_board_yaw(_view.camera.yaw_radians())
		assert_gt(_points(0).dot(_board_run(dir)), 0.999,
			"%s points %v, but on the board it runs %v" %
				[Direction.name_of(dir), _points(0), _board_run(dir)])


## And it keeps pointing there once the board has turned, which is the half a
## fixed glyph would get wrong.
func test_the_arrows_follow_the_board_round() -> void:
	var before: Array[Vector2] = []
	for dir: int in _all_six():
		_stack.show_tiles([dir] as Array[int])
		_stack.set_board_yaw(_view.camera.yaw_radians())
		before.append(_points(0))

	for stop: int in range(1, BoardCamera.YAW_STOPS):
		_view.rotate_by(1)
		assert_true(await wait_for_signal(_view.camera.yaw_settled, 1.0), "stop %d" % stop)
		for i: int in range(before.size()):
			var dir: int = _all_six()[i]
			_stack.show_tiles([dir] as Array[int])
			_stack.set_board_yaw(_view.camera.yaw_radians())
			assert_gt(_points(0).dot(_board_run(dir)), 0.999,
				"%s stopped telling the truth at stop %d" % [Direction.name_of(dir), stop])
			assert_lt(_points(0).dot(before[i]), 0.999,
				"%s must actually have moved by stop %d" % [Direction.name_of(dir), stop])


## Six stops is a whole turn, so every arrow is back where it started — the same
## closure the board's own cycling order has.
func test_six_stops_bring_every_arrow_back() -> void:
	_stack.show_tiles([Direction.ALL[0]] as Array[int])
	_stack.set_board_yaw(0.0)
	var start: Vector2 = _points(0)
	_stack.set_board_yaw(BoardCamera.YAW_STOP_RADIANS * float(BoardCamera.YAW_STOPS))
	assert_gt(_points(0).dot(start), 0.9999, "a whole turn is no turn at all")


## The arrows share `hex_mark.gdshader` with the board's modifier marks, so they
## must not collide with one: §6 ships exactly five modifiers and the arrow is not
## a sixth (C-23).
func test_the_arrow_is_not_one_of_the_five_modifiers() -> void:
	_stack.show_tiles([0] as Array[int])
	for mark: BoardMarks.Mark in BoardMarks.ORDER:
		assert_ne(int(_stack.arrow_custom(0).r), int(mark),
			"the arrow reuses modifier silhouette %d" % int(mark))

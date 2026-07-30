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
	assert_eq(_stack.arrows.multimesh.visible_instance_count, 1,
		"one arrow: the faces underneath are buried")

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


## A pile of coins: the soonest tile is the one on top — the one you would pick up
## — and the rest are directly underneath it, same size, same place.
func test_the_soonest_tile_is_the_top_of_the_pile() -> void:
	_stack.show_tiles([0, 1, 2] as Array[int])
	for i: int in range(1, 3):
		var above: Transform3D = _stack.piece_transform(i - 1)
		var below: Transform3D = _stack.piece_transform(i)
		assert_lt(below.origin.y, above.origin.y, "coin %d sits under the one before it" % i)
		assert_almost_eq(below.origin.x, above.origin.x, 0.001, "in the same column")
		assert_almost_eq(below.origin.z, above.origin.z, 0.001)
		assert_almost_eq(below.basis.get_scale().x, above.basis.get_scale().x, 0.001,
			"coins are all one size")
		assert_lt(below.basis.get_scale().y, below.basis.get_scale().x * 0.5,
			"and are coins rather than blocks")


## The pile is centred on itself, so spending it does not slide it down the rail.
func test_the_pile_stays_put_as_it_is_spent() -> void:
	_stack.show_tiles([0, 1, 2] as Array[int])
	var full: float = _stack.piece_transform(0).origin.y + _stack.piece_transform(2).origin.y
	_stack.show_tiles([0] as Array[int])
	var last: float = _stack.piece_transform(0).origin.y * 2.0
	assert_almost_eq(full, last, 0.001, "the middle of the pile does not move")


## A single coin has to be drawn larger than a pile of five, or §12.3's 140-px NOW
## and 72-px NEXT collapse into two tiles of the same size.
func test_a_lone_coin_is_framed_larger_than_a_pile() -> void:
	var one := TileStack.new()
	one.slots = 1
	add_child_autofree(one)
	assert_lt(one.frame_height(), _stack.frame_height(),
		"a tighter frame is a bigger coin on screen")


## The arrow sits on the only face there is to read, and clears it — the arrows do
## not depth-test, so one buried in the pile would draw straight through the coin
## on top of it.
func test_the_arrow_sits_on_the_face_you_can_see() -> void:
	_stack.show_tiles([0, 1, 2] as Array[int])
	var top: Transform3D = _stack.piece_transform(0)
	var arrow: Transform3D = _stack.arrow_transform(0)
	assert_almost_eq(arrow.origin.x, top.origin.x, 0.001, "centred on the top coin")
	assert_almost_eq(arrow.origin.z, top.origin.z, 0.001)
	assert_gt(arrow.origin.y, top.origin.y + top.basis.get_scale().y,
		"and clears its face")
	assert_lt(arrow.basis.get_scale().x, top.basis.get_scale().x, "and fits on it")


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

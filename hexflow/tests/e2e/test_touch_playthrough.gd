## @e2e — Feature: Touch-only playthrough (§24.2), and the §11.4 touch targets.
##
## The Deck has a touchscreen, so touch is an equal-class input, not an
## afterthought (§11). Every input here is an [InputEventScreenTouch] or a tap on
## a real [Button]: no keyboard, no pad, no mouse.
extends GutTest

const LEVEL_SCENE := "res://src/scenes/level/level.tscn"

## §11.4 — "every on-screen button must have a ≥44 px touch target at 1280×800".
const MIN_TOUCH := 44.0

var _scene: Control = null
var _illegal_attempts: int = 0


func before_each() -> void:
	SaveService.data = {"campaign": {}, "stats": {"undos": 0}, "achievements_mirror": []}
	InputBindings.install()
	_illegal_attempts = 0
	# EventBus is an autoload, so it outlives the test: connect here and let go in
	# after_each, or the second test to subscribe errors as already connected.
	EventBus.illegal_move_attempted.connect(_count_illegal)


func after_each() -> void:
	EventBus.illegal_move_attempted.disconnect(_count_illegal)
	_scene = null
	GameDirector.state = null
	GameDirector.level = null


func _open(level: Level) -> void:
	GameDirector.start_level(level)
	_scene = load(LEVEL_SCENE).instantiate()
	add_child_autofree(_scene)
	await wait_process_frames(2)


func _board() -> BoardView3D:
	return _scene.get_node("%Board") as BoardView3D


## A finger on a cell. The position is derived the same way the board draws it, so
## the test cannot pass by agreeing with a bug in its own arithmetic.
func _tap_cell(cell: Vector3i) -> void:
	var at := _board().screen_position_of(cell)
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = at
	down.pressed = true
	# `true` = the position is already in viewport space. Without it Godot treats
	# it as a window coordinate and applies the stretch transform, which under the
	# test window scales the tap 20× off the board.
	_scene.get_viewport().push_input(down, true)
	await wait_process_frames(1)

	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = at
	up.pressed = false
	_scene.get_viewport().push_input(up, true)
	await wait_process_frames(1)


func _buttons() -> Array[Button]:
	var out: Array[Button] = []
	_collect_buttons(_scene, out)
	return out


func _collect_buttons(node: Node, into: Array[Button]) -> void:
	for child: Node in node.get_children():
		if child is Button:
			into.append(child as Button)
		_collect_buttons(child, into)


func _straight_level() -> Level:
	var lv := Fixtures.fixed_level(Fixtures.shortest_route_tiles())
	lv.id = "e2e_touch_straight"
	lv.par = 6
	return lv


## Scenario: Touch-only playthrough.
func test_completing_a_level_using_only_tap_input() -> void:
	await _open(_straight_level())

	# The straight route: six NE steps from the start toward the goal.
	for step: int in range(1, 7):
		var cell := Fixtures.START + Direction.delta(Direction.NE) * step
		assert_true(GameDirector.state.legal_targets().has(cell),
			"step %d should be legal before it is tapped" % step)
		await _tap_cell(cell)

	assert_eq(GameDirector.state.status, GameState.Status.WON)
	assert_eq(GameDirector.state.placements, 6)
	assert_eq(_illegal_attempts, 0, "no tap was ever mistaken for an illegal move")
	assert_true(SaveService.data["campaign"].has("e2e_touch_straight"),
		"the level is marked complete")


## A tap on a cell that is not a candidate must do nothing at all — not commit,
## and not even report an illegal move, because the cursor never moved there.
func test_tapping_a_cell_that_is_not_a_target_does_nothing() -> void:
	await _open(_straight_level())

	var far := Vector3i(3, -3, 0)
	assert_false(GameDirector.state.legal_targets().has(far), "the fixture cell is illegal")
	await _tap_cell(far)

	assert_eq(GameDirector.state.placements, 0)
	assert_eq(_illegal_attempts, 0)
	assert_eq(GameDirector.state.status, GameState.Status.PLAYING)


## §11.4. Asserted on the rendered rect, not on `custom_minimum_size`, so a theme
## or a layout container cannot squeeze a button below the thumb-reachable size.
func test_every_on_screen_button_meets_the_44px_touch_target() -> void:
	await _open(_straight_level())
	var buttons := _buttons()
	assert_gt(buttons.size(), 0, "the level screen has tappable buttons")

	for button: Button in buttons:
		assert_gte(button.size.x, MIN_TOUCH,
			"%s is %d px wide" % [button.name, int(button.size.x)])
		assert_gte(button.size.y, MIN_TOUCH,
			"%s is %d px tall" % [button.name, int(button.size.y)])


func test_the_rail_buttons_drive_the_same_intents_as_the_pad() -> void:
	await _open(_straight_level())
	await _tap_cell(Fixtures.START + Direction.delta(Direction.NE))
	assert_eq(GameDirector.state.placements, 1)

	# Undo, by finger.
	(_scene.get_node("%UndoButton") as Button).emit_signal("pressed")
	await wait_process_frames(1)
	assert_eq(GameDirector.state.placements, 0, "the Undo button undoes")

	# Discard, by finger.
	var discards := GameDirector.state.discards_left
	(_scene.get_node("%DiscardButton") as Button).emit_signal("pressed")
	await wait_process_frames(1)
	assert_eq(GameDirector.state.discards_left, discards - 1,
		"the Discard button spends a charge")


func test_the_legend_button_toggles_the_legend() -> void:
	await _open(_straight_level())
	var legend: LegendPanel = _scene.get_node("%Legend")
	assert_false(legend.visible)

	(_scene.get_node("%LegendButton") as Button).emit_signal("pressed")
	await wait_process_frames(1)
	assert_true(legend.visible, "there is a touch route to the legend (§11.3)")


## The restart button is destructive, so it holds like every other route to it.
func test_the_restart_button_has_to_be_held() -> void:
	await _open(_straight_level())
	await _tap_cell(Fixtures.START + Direction.delta(Direction.NE))
	assert_eq(GameDirector.state.placements, 1)

	var restart := _scene.get_node("%RestartButton") as Button
	restart.emit_signal("button_down")
	await wait_process_frames(2)
	restart.emit_signal("button_up")
	await wait_process_frames(1)
	assert_eq(GameDirector.state.placements, 1, "a tap on Restart must not restart")

	restart.emit_signal("button_down")
	await wait_seconds(InputBindings.HOLD_RESTART + 0.2)
	assert_eq(GameDirector.state.placements, 0, "holding it does")
	restart.emit_signal("button_up")


## §11.3 spells the touch route to a wild charge "Wild button, then cell".
func test_the_wild_button_arms_a_charge_for_the_next_tap() -> void:
	var board := Board.build(
		3, Fixtures.START, [Fixtures.GOAL] as Array[Vector3i], [], [], [],
		[Vector3i(-2, 0, 2)] as Array[Vector3i]
	)
	var lv := Level.build(board, Fixtures.dirs(Fixtures.shortest_route_tiles()))
	lv.id = "e2e_touch_wild"
	lv.discards = 3
	lv.par = 6
	await _open(lv)

	await _tap_cell(Vector3i(-2, 0, 2))
	assert_eq(GameDirector.state.wild_charges, 1)

	var legal := GameDirector.state.legal_targets()
	(_scene.get_node("%WildButton") as Button).emit_signal("pressed")
	await wait_process_frames(1)

	var wild_only: Array[Vector3i] = []
	for cell: Vector3i in GameDirector.state.wild_targets():
		if not legal.has(cell):
			wild_only.append(cell)
	assert_gt(wild_only.size(), 0, "a charge unlocks cells the tile cannot reach")

	await _tap_cell(wild_only[0])
	assert_eq(GameDirector.state.wild_charges, 0, "the tap spent the charge")
	assert_true(GameDirector.state.path.has(wild_only[0]))


func _count_illegal(_cell: Vector3i) -> void:
	_illegal_attempts += 1

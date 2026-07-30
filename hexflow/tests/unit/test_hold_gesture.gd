## @core — the hold gate of §11.3: nothing destructive on a single press.
extends GutTest

var _gesture: HoldGesture = null
var _completed: Array[String] = []
var _cancelled: Array[String] = []


func before_each() -> void:
	_gesture = HoldGesture.new()
	_completed = []
	_cancelled = []
	_gesture.completed.connect(func(a: String) -> void: _completed.append(a))
	_gesture.cancelled.connect(func(a: String) -> void: _cancelled.append(a))


func test_a_hold_fires_only_after_its_threshold() -> void:
	_gesture.begin("board_restart", 1.0)
	_gesture.tick(0.5)
	assert_eq(_completed, [] as Array[String], "half a hold is not a hold")
	assert_almost_eq(_gesture.ratio(), 0.5, 0.01)

	_gesture.tick(0.6)
	assert_eq(_completed, ["board_restart"] as Array[String])
	assert_false(_gesture.active(), "the gesture clears itself once it fires")


func test_a_hold_fires_exactly_once_however_long_it_is_held() -> void:
	_gesture.begin("board_restart", 1.0)
	for _i: int in range(20):
		_gesture.tick(0.5)
	assert_eq(_completed.size(), 1, "holding longer must not restart twice")


func test_releasing_early_cancels_and_reports_that_it_cancelled() -> void:
	_gesture.begin("board_restart", 1.0)
	_gesture.tick(0.4)
	assert_true(_gesture.cancel("board_restart"), "a live hold reports its cancellation")
	assert_eq(_cancelled, ["board_restart"] as Array[String])
	assert_eq(_completed, [] as Array[String])


## The distinction the Select binding depends on: after the hold has fired there
## is nothing left to cancel, so the release must not also toggle the legend.
func test_cancelling_a_completed_hold_reports_nothing_to_cancel() -> void:
	_gesture.begin("board_restart", 1.0)
	_gesture.tick(1.1)
	assert_eq(_completed, ["board_restart"] as Array[String])
	assert_false(_gesture.cancel("board_restart"))


func test_cancelling_a_different_action_leaves_the_hold_alone() -> void:
	_gesture.begin("board_restart", 1.0)
	assert_false(_gesture.cancel("board_hint"))
	assert_true(_gesture.active())
	_gesture.tick(1.1)
	assert_eq(_completed, ["board_restart"] as Array[String])


func test_a_second_press_displaces_the_first_and_cancels_it() -> void:
	_gesture.begin("board_restart", 1.0)
	_gesture.tick(0.9)
	_gesture.begin("board_hint", 0.5)
	assert_eq(_cancelled, ["board_restart"] as Array[String])

	_gesture.tick(0.6)
	assert_eq(_completed, ["board_hint"] as Array[String],
		"the displaced hold's progress must not carry over")


func test_ticking_while_idle_does_nothing() -> void:
	_gesture.tick(10.0)
	assert_eq(_completed, [] as Array[String])
	assert_eq(_gesture.ratio(), 0.0)


func test_a_zero_length_hold_is_refused() -> void:
	# A hold of no duration would be a single press wearing a disguise.
	_gesture.begin("board_restart", 0.0)
	assert_false(_gesture.active())
	_gesture.tick(1.0)
	assert_eq(_completed, [] as Array[String])

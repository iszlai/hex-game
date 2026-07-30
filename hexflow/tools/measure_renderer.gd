extends SceneTree
## Dev tool: boots a level, plays it a little, and reports frame cost.
##
## C-3 asks which renderer the Linux/Deck export should use, and C-18 made that
## question undeferrable by putting a lit 3D board with shadows on screen. Run it
## once per renderer and compare:
##
##   Godot --path . --rendering-method forward_plus -s res://tools/measure_renderer.gd
##   Godot --path . --rendering-method mobile       -s res://tools/measure_renderer.gd
##
## What it measures is deliberately modest — §20 budgets "≤ 8 ms combined CPU+GPU
## at 60 fps", and a windowed run on a development machine cannot answer that for a
## Deck. What it *can* answer is which of the two is cheaper on the same board, and
## whether the board renders correctly under both at all, which is the failure that
## would otherwise be found at export time.
##
## Not part of the shipped game.

## Frames to let shaders compile and the board settle before timing starts. The
## first frames of a Godot run are dominated by pipeline compilation and would
## swamp the average.
const WARMUP_FRAMES := 120

## Frames to time. At an uncapped rate this is a couple of seconds.
const SAMPLE_FRAMES := 400

var _frames: int = 0
var _level: Node = null
var _process_ms: float = 0.0
var _worst_ms: float = 0.0
var _placements: int = 0


func _initialize() -> void:
	Engine.max_fps = 0
	var scene: PackedScene = load("res://src/scenes/level/level.tscn")
	_level = scene.instantiate()
	root.add_child(_level)


func _process(delta: float) -> bool:
	_frames += 1
	# Not in `_initialize`: under the RenderingDevice backends the swapchain does
	# not exist yet and the request is dropped, which is how the first two runs of
	# this tool came back at exactly 8.333 ms — they were measuring a 120 Hz panel.
	if _frames == 2:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Keep the board doing something: a still board measures a still board.
	if _frames % 30 == 0 and _placements < 8:
		_place_one()
	if _frames < WARMUP_FRAMES:
		return false
	if _frames < WARMUP_FRAMES + SAMPLE_FRAMES:
		var ms: float = delta * 1000.0
		_process_ms += ms
		_worst_ms = maxf(_worst_ms, ms)
		return false
	_report()
	return true


func _place_one() -> void:
	var director: Node = root.get_node_or_null("GameDirector")
	var state: Variant = director.get("state") if director != null else null
	if state == null:
		return
	var targets: Array = state.legal_targets()
	if targets.is_empty():
		return
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	_level.call("_unhandled_input", ev)
	_placements += 1


func _report() -> void:
	var mean: float = _process_ms / float(SAMPLE_FRAMES)
	# The *running* method, not the project's setting — the whole point is to
	# compare an override against the default, and the setting does not move.
	print("renderer      : ", RenderingServer.get_current_rendering_method())
	print("project default: ", ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	print("adapter       : ", RenderingServer.get_video_adapter_name())
	print("frames        : ", SAMPLE_FRAMES, " after ", WARMUP_FRAMES, " warm-up")
	print("mean frame    : %.3f ms  (%.0f fps uncapped)" % [mean, 1000.0 / maxf(mean, 0.001)])
	print("worst frame   : %.3f ms" % _worst_ms)
	print("draw calls    : ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("objects drawn : ", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	print("video memory  : %.1f MB" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))

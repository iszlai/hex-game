extends SceneTree
## Dev tool: boots a scene, lets it settle, and writes a PNG.
## Run non-headless: Godot --path . -s res://tools/screenshot.gd -- <out.png> [presses]
## `presses` is a string of keys sent one per frame — `c` confirm, `z` undo,
## `q`/`e` cycle, `d` discard, `h` hint, `r`/`l` turn the board clockwise and
## anticlockwise. Letters only: Godot drops a whitespace-only command-line
## argument. Not part of the shipped game.

## Frames to let the last press finish animating before the capture. Must outlast
## the longest animation a press can start — currently the 260 ms board yaw (C-21),
## which is ~16 frames at 60 fps.
const SETTLE_FRAMES := 30

var _frames: int = 0
var _out: String = "user://shot.png"
var _presses: String = ""
var _level: Node = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_presses = args[1]
	var scene: PackedScene = load("res://src/scenes/level/level.tscn")
	_level = scene.instantiate()
	root.add_child(_level)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 10:
		return false
	var i: int = _frames - 10
	if i < _presses.length():
		var ev := InputEventKey.new()
		ev.keycode = _key_for(_presses[i])
		ev.physical_keycode = ev.keycode
		ev.pressed = true
		# Drive the handler directly: this is a capture tool, not an input test —
		# `tests/e2e/` covers the real viewport dispatch path.
		_level.call("_unhandled_input", ev)
		return false
	if i < _presses.length() + SETTLE_FRAMES:
		return false
	var img := root.get_texture().get_image()
	img.save_png(_out)
	# Autoloads are not compiled into a `-s` MainLoop script, so reach the
	# director through the tree rather than by its global name.
	var director: Node = root.get_node_or_null("GameDirector")
	var state: Variant = director.get("state") if director != null else null
	print("wrote ", _out, " placements=", state.placements if state != null else -1)
	return true


func _key_for(c: String) -> Key:
	match c:
		"c":
			return KEY_SPACE
		"z":
			return KEY_Z
		"e":
			return KEY_E
		"q":
			return KEY_Q
		"d":
			return KEY_D
		"h":
			return KEY_H
		"r":
			return KEY_BRACKETRIGHT
		"l":
			return KEY_BRACKETLEFT
		_:
			return KEY_SPACE

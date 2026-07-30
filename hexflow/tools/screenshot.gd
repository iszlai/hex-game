extends SceneTree
## Dev tool: boots a scene, lets it settle, and writes a PNG.
## Run non-headless:
##   Godot --path . -s res://tools/screenshot.gd -- <out.png> [presses] [chapter.level] [screen]
## `presses` is a string of keys sent one per frame — `c` confirm, `z` undo,
## `q`/`e` cycle, `d` discard, `h` hint, `r`/`l` turn the board clockwise and
## anticlockwise, `u`/`n`/`i`/`j` the four menu directions. Letters only: Godot
## drops a whitespace-only command-line argument.
##
## The third argument picks the level, because which one is on screen decides what
## can be *seen*: the modifiers of §6 are introduced a chapter at a time, so only
## chapter 5 carries a goal, a portal, a gate and a wild at once — and a capture of
## chapter 1 says nothing at all about whether the other three draw.
##
## The fourth picks the *screen*, by the [GameDirector.Screen] name — `level`
## (default), `level_select`, `main_menu`, `results`, `settings`, `run_summary`.
## A screen that cannot be looked at is a screen nobody checks, and §21's greyscale
## and 150%-text audits are both things you have to see.
##
## Not part of the shipped game.

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
	if args.size() > 2 and args[2].contains("."):
		# Before the scene exists, so `level.gd` finds a level already started and
		# leaves its own standalone default alone.
		var at: PackedStringArray = args[2].split(".")
		var director: Node = root.get_node_or_null("GameDirector")
		if director != null:
			director.call("start_level", LevelRepository.load_level(int(at[0]), int(at[1])))
	var name: String = args[3] if args.size() > 3 and args[3] != "" else "level"
	var scene: PackedScene = load("res://src/scenes/%s/%s.tscn" % [name, name])
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
		"u":
			return KEY_UP
		"n":
			return KEY_DOWN
		"i":
			return KEY_LEFT
		"j":
			return KEY_RIGHT
		_:
			return KEY_SPACE

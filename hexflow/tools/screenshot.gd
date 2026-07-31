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
## The fifth marks the first N levels of the chapter complete before the screen is
## built, because several screens say nothing at all against an empty save: the map
## is twelve locked cells, the main menu is 0%, and neither is the state anyone
## needs a picture of. Stars are derived from the level number rather than picked,
## so the same command gives the same picture twice.
##
## `make shot` runs this with its own `user://` and the seeding writes there, so a
## capture can never see or touch the player's real save. That is deliberate and it
## is the reason the argument exists: the alternative was editing a live save by
## hand before every map capture, and then remembering to put it back.
##
## Not part of the shipped game.

## Frames to let the last press finish animating before the capture. Must outlast
## the longest animation a press can start — currently the 260 ms board yaw (C-21),
## which is ~16 frames at 60 fps.
const SETTLE_FRAMES := 30

var _frames: int = 0
var _out: String = "user://shot.png"
var _presses: String = ""
var _screen: String = "level"
var _at: PackedStringArray = PackedStringArray()
var _progress: int = 0
var _level: Node = null


## Arguments only. Nothing is *done* here: `_initialize` runs before the autoloads
## have had their `_ready`, so a signal emitted from this function reaches a bus
## nobody has connected to yet — which is exactly how the first results capture
## came back showing a level that had never been played.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_presses = args[1]
	if args.size() > 2 and args[2].contains("."):
		_at = args[2].split(".")
	if args.size() > 3 and args[3] != "":
		_screen = args[3]
	if args.size() > 4 and args[4] != "":
		_progress = int(args[4])


## The scene is built on the first frame, once the autoloads are live. The level is
## started before the scene exists, so `level.gd` finds one already going and
## leaves its own standalone default alone.
func _setup() -> void:
	var director: Node = root.get_node_or_null("GameDirector")
	_seed_progress()
	if _at.size() == 2 and director != null:
		director.call("start_level", LevelRepository.load_level(int(_at[0]), int(_at[1])))
	if _screen == "results":
		_win_the_level()
	var scene: PackedScene = load("res://src/scenes/%s/%s.tscn" % [_screen, _screen])
	_level = scene.instantiate()
	root.add_child(_level)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_setup()
		return false
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


## Marks the first `_progress` levels of the chapter complete, so a screen that
## reads a save has something to read.
##
## Written through [SaveService] rather than into a dictionary, so what the capture
## shows is what the game would show — an entry shaped by hand is a picture of the
## fixture rather than of the screen. Stars run 3, 2, 1, 3, … off the level number
## and level three carries §12.6's hint flag, so a map capture exercises a full
## pip row, a partial one and the hint dot without anyone choosing them.
func _seed_progress() -> void:
	if _progress <= 0:
		return
	var save: Node = root.get_node_or_null("SaveService")
	if save == null:
		return
	var chapter: int = int(_at[0]) if _at.size() == 2 else 1
	var levels: int = mini(_progress, LevelRepository.LEVELS_PER_CHAPTER)
	for index: int in range(1, levels + 1):
		var level := LevelRepository.load_level(chapter, index)
		var stars: int = Scoring.MAX_STARS - ((index - 1) % Scoring.MAX_STARS)
		save.call(
			"record_completion", LevelRepository.id_for(chapter, index),
			level.par if level != null else 0, stars, index == 3
		)


## The results card only says anything if there is a run behind it, so capturing
## it means finishing a level first. The stored solution is replayed through the
## real intent path — `EventBus` into [GameDirector] — rather than through
## `Solver.replay`, because it is `GameDirector` that fills in `last_result`, and
## a card fed a hand-built dictionary would be a capture of nothing.
func _win_the_level() -> void:
	var director: Node = root.get_node_or_null("GameDirector")
	# Autoloads are not compiled into a `-s` MainLoop script, so both of these are
	# reached through the tree rather than by their global names.
	var bus: Node = root.get_node_or_null("EventBus")
	if director == null or bus == null:
		return
	var level: Variant = director.get("level")
	if level == null:
		director.call("start_level", LevelRepository.load_level(1, 1))
		level = director.get("level")
	for step: Variant in level.solution_script:
		var s: Array = step
		match int(s[0]):
			Solver.ACTION_PLACE:
				bus.emit_signal("place_requested", s[1] as Vector3i)
			Solver.ACTION_WILD:
				bus.emit_signal("wild_place_requested", s[1] as Vector3i)
			Solver.ACTION_DISCARD:
				bus.emit_signal("discard_requested")


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
		"p":
			return KEY_ESCAPE
		_:
			return KEY_SPACE

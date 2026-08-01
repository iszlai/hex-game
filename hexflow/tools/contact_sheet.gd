extends SceneTree
## Dev tool: one capture of every campaign level, in one run.
##
##     Godot --resolution 1280x800 -s res://tools/contact_sheet.gd -- <out_dir> [moves]
##
## `tools/screenshot.gd` captures one screen per launch, which is right for
## looking at a screen and wrong for looking at the *campaign*: sixty launches is
## twenty minutes of booting Godot to take sixty pictures. This boots once and
## rebinds the level screen sixty times, which is seconds.
##
## Exists because C-33 re-authored all sixty levels against a difficulty curve and
## C-32 gave them six silhouettes. Whether that reads as a campaign — whether the
## boards get visibly tighter, whether the shapes are spread or clumped — is a
## question about the set rather than about any level in it, and the only way to
## answer it is to see them together.
##
## Writes `NN_cCLL_shape.png` per level, ready for `ffmpeg -i ... tile=`.
##
## Not part of the shipped game.

## Frames to let the board settle before the shutter. Must outlast the longest
## animation a rebind starts.
const SETTLE_FRAMES := 12

var _out_dir: String = "."
var _moves: int = 0
var _frames: int = 0
var _slot: int = 0
var _level_scene: Node = null
var _waiting: int = 0
var _written: int = 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_moves = int(args[1])
	DirAccess.make_dir_recursive_absolute(_out_dir)


func _process(_delta: float) -> bool:
	_frames += 1
	# The first frame is the autoloads': a scene built before they are ready binds
	# to a director that does not exist yet.
	if _frames < 2:
		return false

	if _level_scene == null:
		if _slot >= LevelRepository.CHAPTERS * LevelRepository.LEVELS_PER_CHAPTER:
			print("wrote %d captures to %s" % [_written, _out_dir])
			return true
		_open_slot()
		return false

	_waiting += 1
	if _waiting <= SETTLE_FRAMES:
		return false

	_shoot()
	return false


func _open_slot() -> void:
	var chapter: int = _slot / LevelRepository.LEVELS_PER_CHAPTER + 1
	var index: int = _slot % LevelRepository.LEVELS_PER_CHAPTER + 1
	var level: Level = LevelRepository.load_level(chapter, index)
	if level == null:
		_slot += 1
		return

	var director: Node = root.get_node_or_null("GameDirector")
	if director != null:
		director.call("start_level", level)
	_level_scene = load("res://src/scenes/level/level.tscn").instantiate()
	root.add_child(_level_scene)
	_waiting = 0

	# A few placements so the capture shows a path rather than an empty board —
	# an unplayed level looks the same whatever its shape, and the point of the
	# sheet is what the boards *are*.
	# Autoloads are not compiled into a `-s` MainLoop script, so the bus is reached
	# through the tree rather than by its global name — the same reason
	# `screenshot.gd` asks the tree for the director.
	var bus: Node = root.get_node_or_null("EventBus")
	var state: Variant = director.get("state") if director != null else null
	for _i: int in range(_moves):
		if state == null or bus == null or state.status != GameState.Status.PLAYING:
			break
		var targets: Array[Vector3i] = state.legal_targets()
		if targets.is_empty():
			break
		bus.emit_signal("place_requested", targets[0])


func _shoot() -> void:
	var chapter: int = _slot / LevelRepository.LEVELS_PER_CHAPTER + 1
	var index: int = _slot % LevelRepository.LEVELS_PER_CHAPTER + 1
	var level: Level = LevelRepository.load_level(chapter, index)
	var name := "%02d_c%dl%02d_%s.png" % [_slot + 1, chapter, index, level.board.shape]
	root.get_texture().get_image().save_png("%s/%s" % [_out_dir, name])
	_written += 1

	_level_scene.queue_free()
	_level_scene = null
	_slot += 1

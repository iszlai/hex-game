extends SceneTree
## Plays a level file — usually a draft — in the real game (MAP-EDITOR §6.1).
##
##     make play-draft FILE=drafts/idea.json
##     Godot --path . -s res://tools/play_draft.gd -- <path/to/level.json>
##
## §9 puts "playtesting inside the editor" out of scope on the grounds that
## `make run` already plays the level that was just saved. That was true while
## every save landed in a campaign slot. Once a board could be saved to `drafts/`
## instead, the sentence stopped being true of exactly the boards most worth
## playing — the unfinished ones — and there was no way to try a level without
## first spending one of the sixty on it.
##
## **This is not a flag in the game.** It is a `-s` MainLoop, the same arrangement
## `tools/screenshot.gd` uses: it replaces the engine's main loop, sets up the
## real [GameDirector] with the real autoloads, and hands over to the real level
## scene. Nothing in `src/` learns that drafts exist, so §27's non-goal and §8's
## one-way arrow are both untouched — there is no debug path in the shipped build
## to gate, because there is no debug path.
##
## The scene is entered through [method SceneTree.change_scene_to_file] rather
## than by adding a node to the root, so `current_scene` is properly owned and the
## navigation that follows a win — level → results → next — swaps it instead of
## stacking a second screen on top of the first.
##
## Not part of the shipped game.

## Spelled out rather than read from [GameDirector]`.SCENES`, which is the
## tempting version and does not work: preloading `game_director.gd` compiles it
## in a context where the autoload *singletons* are not registered, so its own
## reference to `SettingsService` fails and the whole autoload comes up as a bare
## `Node` with no `start_level` on it. `tools/screenshot.gd` builds its scene path
## by hand for the same reason.
const LEVEL_SCENE := "res://src/scenes/level/level.tscn"

var _path: String = ""
var _level: Level = null


## Arguments only. `_initialize` runs before the autoloads have had their
## `_ready`, so anything that touches the director waits for the first frame —
## the lesson `tools/screenshot.gd` records at the top of its own `_initialize`.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or str(args[0]) == "":
		push_error("usage: make play-draft FILE=drafts/idea.json")
		quit(1)
		return
	_path = str(args[0])
	if not _path.begins_with("res://") and not _path.begins_with("/"):
		_path = "res://" + _path


func _process(_delta: float) -> bool:
	if _level != null:
		return false
	_level = LevelFile.read(_path)
	if _level == null:
		push_error("no level at %s" % _path)
		quit(1)
		return true

	# A draft need never have been validated, so it can arrive with `par` unset —
	# and par is what §5.10's star bands are measured against, so without it every
	# finish is a three-star finish and the run says nothing. Solving here rather
	# than refusing keeps the tool useful on a board that was saved mid-thought;
	# a board the solver cannot win is reported and played anyway, because seeing
	# *why* it cannot be won is the reason to open it.
	if _level.par <= 0:
		var result := Solver.solve(_level)
		if result.is_solvable():
			_level.par = result.par
			_level.solution = result.moves
			_level.solution_script = result.actions
			print("solved on the way in: ideal %d" % result.par)
		else:
			push_warning("this board is not winnable with its sequence — playing it anyway")

	print("playing %s  (%s, %d cells, %d tiles)" % [
		_path, _level.board.shape, _level.board.size(), _level.tiles.size()])

	var director: Node = root.get_node_or_null("GameDirector")
	if director == null:
		push_error("no GameDirector — the autoloads did not start")
		quit(1)
		return true
	director.call("start_level", _level)
	change_scene_to_file(LEVEL_SCENE)
	return false

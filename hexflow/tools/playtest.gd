extends SceneTree
## Puts the game into the state a first-time player finds it in, and puts your own
## save back afterwards.
##
## §26's exit criterion for M8 is "a first-time player completes chapter 1 with no
## external explanation — verified by an actual naive playtest". That is not a
## thing a developer can run against their own profile: every beat writes a flag
## the moment it is shown, and by now those flags have been set by weeks of playing
## and by the test suite itself. Launching the game to watch the tutorial would
## show a tutorial that has already happened.
##
## So: `make playtest` moves your save aside and starts clean, and
## `make playtest-restore` moves it back. Nothing is deleted — the backup lives in
## `user://` beside the original, because "we reset your progress for a playtest" is
## not a sentence anyone should have to read.
##
## Run: godot --headless --path . -s res://tools/playtest.gd -- [reset|restore]

const FILES: Array[String] = ["user://save.json", "user://settings.json"]
const SUFFIX := ".playtest-backup"


func _initialize() -> void:
	var mode: String = "reset"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	if mode == "restore":
		_restore()
	else:
		_reset()
	quit()


## Moves the live files aside. An existing backup is *not* overwritten: two resets
## in a row would otherwise turn the first one's real save into the second one's
## empty one, which is the whole thing this script exists to avoid.
func _reset() -> void:
	for path: String in FILES:
		var backup: String = path + SUFFIX
		if not FileAccess.file_exists(path):
			continue
		if FileAccess.file_exists(backup):
			print("a backup of %s already exists; leaving it alone" % path)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			continue
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup))
		print("moved %s aside" % path)
	print("")
	print("the game will start as a first-time player finds it")
	print("put your own save back with:  make playtest-restore")


func _restore() -> void:
	var found: bool = false
	for path: String in FILES:
		var backup: String = path + SUFFIX
		if not FileAccess.file_exists(backup):
			continue
		found = true
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(backup), ProjectSettings.globalize_path(path))
		print("restored %s" % path)
	if not found:
		print("nothing to restore — there is no playtest backup")

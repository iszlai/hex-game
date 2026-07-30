extends Control
## Boot screen (§12.2): brand mark, 1.2 s max, skippable by any input.
##
## M3 grey-box: boot hands straight to a generated level so the core loop is
## reachable from a cold start. M6 replaces this with the main menu and the
## hex-flower level select.

const MAX_SECONDS := 1.2

var _elapsed: float = 0.0
var _left: bool = false


## §13.2 allows a colour in exactly one place, and a `.tscn` is not it: §21's four
## alternate palettes are a resource swap with no code change, and a literal baked
## into a scene would survive all four of them.
func _ready() -> void:
	var palette: Palette = load("res://src/data/palettes/neon_dark.tres")
	(%Background as ColorRect).color = palette.bg_deep
	(%Title as Label).add_theme_color_override("font_color", palette.path_core)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= MAX_SECONDS:
		_leave()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed():
		_leave()


func _leave() -> void:
	if _left:
		return
	_left = true
	# M6: GameDirector.go_to(GameDirector.Screen.MAIN_MENU)
	GameDirector.start_level(_first_level())
	GameDirector.go_to(GameDirector.Screen.LEVEL)


## Chapter 1, level 1, from the frozen campaign data — never generated at
## runtime, because a re-seed would invalidate its par and every stored star
## (§9, §27).
func _first_level() -> Level:
	var lv := LevelRepository.load_level(1, 1)
	if lv != null:
		return lv
	# The campaign data is missing or unreadable. Rather than leave the player at
	# a black screen, fall back to the reference board of Appendix A, whose
	# straight six-step solution is always playable.
	push_warning("campaign data unavailable; falling back to the reference board")
	var board := Board.build(3, Vector3i(-3, 0, 3), [Vector3i(3, 0, -3)] as Array[Vector3i])
	var six_ne: Array[int] = [
		Direction.NE, Direction.NE, Direction.NE, Direction.NE, Direction.NE, Direction.NE
	]
	var fallback := Level.build(board, six_ne)
	fallback.id = "fallback"
	fallback.par = 6
	return fallback

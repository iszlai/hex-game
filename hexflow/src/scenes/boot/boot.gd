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
	var palette: Palette = Palette.current()
	Backdrop.install(self)
	(%Background as ColorRect).color = Color(palette.bg_deep, 0.0)
	var title := %Title as Label
	title.add_theme_color_override("font_color", palette.path_core)
	title.theme_type_variation = Typography.variation_for(Typography.Role.DISPLAY)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= MAX_SECONDS:
		_leave()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed():
		_leave()


## §12.1 sends Boot to the main menu, and it no longer opens a level itself.
##
## §18.2's in-progress run is not lost by that: the map opens on the level the
## player was in ([method Campaign.last_played]) and entering it *resumes* rather
## than restarts ([method GameDirector.resume_or_start]). A Deck that slept
## mid-level therefore wakes to a menu two presses from exactly where it was,
## which is what a player who has been away for a week wants — the alternative,
## dropping straight onto a board with no idea which one, only serves the player
## who was away for ten seconds.
func _leave() -> void:
	if _left:
		return
	_left = true
	GameDirector.go_to(GameDirector.Screen.MAIN_MENU)

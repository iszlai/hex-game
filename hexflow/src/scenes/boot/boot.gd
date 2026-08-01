extends Control
## Boot screen (§12.2): the title over the chapter-less backdrop, [constant
## MAX_SECONDS] at most, skippable by any input.
##
## This is the **only** splash the game has (C-31). The engine one is switched off
## in `project.godot`, so nothing shows the name twice.

## §12.2's hold. Long enough to be an opening rather than a flicker, short enough
## that a player who has launched the game a hundred times is not waiting on it —
## and they never are, because any press leaves immediately.
const MAX_SECONDS := 3.0

## How long the title takes to arrive. Under §14.5 it does not travel at all: a
## reduced-motion title is simply already there, for the whole of the hold.
const TITLE_FADE_MS := 700

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
	title.add_theme_color_override("font_color", palette.text_primary)
	title.theme_type_variation = Typography.variation_for(Typography.Role.DISPLAY)
	_fade_in(title)


## Three seconds of a picture that never changes reads as a screen that has hung.
## The title arriving out of the backdrop is what makes the hold a beat, so the
## duration and the motion are one decision and belong together.
func _fade_in(title: Label) -> void:
	if SettingsService.reduce_motion():
		return
	title.modulate.a = 0.0
	var tween := create_tween()
	Motion.shape(tween, "screen_transition")
	tween.tween_property(title, "modulate:a", 1.0, float(TITLE_FADE_MS) / 1000.0)


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
##
## The exception is the very first launch (§10.1, C-37). A player who has never
## seen the game gets the course rather than the menu, because a menu is five
## words about things none of which they know the meaning of yet. It is a minute
## long and one Back press ends it for good, and after that this branch is dead
## for the life of the save.
func _leave() -> void:
	if _left:
		return
	_left = true
	if Tutorial.pending():
		GameDirector.start_tutorial()
		GameDirector.go_to(GameDirector.Screen.LEVEL)
		return
	GameDirector.go_to(GameDirector.Screen.MAIN_MENU)

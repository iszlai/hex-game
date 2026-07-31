## @core — §14.1's screen transition, and §12.5's "never a hard cut".
##
## The rule is stated twice in the spec and is easy to satisfy accidentally-wrongly:
## a cross-fade that each screen implements for itself works until a screen that has
## not been built yet is navigated to, and then the player gets a flash of whatever
## was underneath. So the fade lives above every screen and belongs to nobody.
extends GutTest


func after_each() -> void:
	SettingsService.set_value("reduce_motion", false)
	GameDirector.screen = GameDirector.Screen.LEVEL


func _fade() -> ColorRect:
	var layer: CanvasLayer = GameDirector.get_node_or_null("ScreenFade")
	return layer.get_node("Fade") if layer != null else null


func test_a_screen_change_fades_rather_than_cuts() -> void:
	GameDirector.go_to(GameDirector.Screen.LEVEL)
	assert_true(GameDirector.transitioning(), "§12.5: never a hard cut")
	assert_not_null(_fade(), "and there is something doing the fading")

	await wait_seconds(Motion.seconds("screen_transition") + 0.2)
	assert_false(GameDirector.transitioning(), "which then gets out of the way")
	assert_almost_eq(_fade().color.a, 0.0, 0.01, "leaving the screen fully visible")


## The fade is a layer over everything rather than something each screen does to
## itself: a screen that does not exist yet still gets a transition, and the
## outgoing one does not have to cooperate.
func test_the_fade_belongs_to_nobody_and_sits_over_everything() -> void:
	GameDirector.go_to(GameDirector.Screen.LEVEL)
	var fade: ColorRect = _fade()
	assert_not_null(fade)
	var layer: CanvasLayer = fade.get_parent()
	assert_gt(layer.layer, 0, "above the screens, not among them")
	assert_eq(fade.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"a full-rect Control that ate input is exactly how B7 hid for a milestone")


## Built once. A transition that allocated a layer each time would allocate one on
## every screen change forever.
func test_the_fade_layer_is_built_once() -> void:
	GameDirector.go_to(GameDirector.Screen.LEVEL)
	var first: ColorRect = _fade()
	await wait_seconds(Motion.seconds("screen_transition") + 0.2)
	GameDirector.go_to(GameDirector.Screen.LEVEL)
	assert_same(_fade(), first, "the same layer, both times")


## §14.5 names 120 ms for this one outright, and 320 × 0.4 is 128 — so a blanket
## multiplier would be wrong here specifically.
func test_reduce_motion_uses_the_number_the_spec_names() -> void:
	SettingsService.set_value("reduce_motion", true)
	assert_eq(Motion.milliseconds("screen_transition"), 120)
	GameDirector.go_to(GameDirector.Screen.LEVEL)
	assert_true(GameDirector.transitioning())
	await wait_seconds(0.4)
	assert_false(GameDirector.transitioning(), "and it is over well inside a scaled 320")


## The fade takes its colour from the palette rather than from black, so §21's
## swaps reach the one moment the whole screen is one colour.
func test_the_fade_is_a_palette_colour() -> void:
	GameDirector.go_to(GameDirector.Screen.LEVEL)
	var palette: Palette = Palette.current()
	var fade: ColorRect = _fade()
	assert_eq(Color(fade.color, 1.0), palette.bg_deep, "the window's own clear colour")

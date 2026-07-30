## @core — §12.3's dimensioned layout, as numbers rather than as a screenshot.
##
## The diagram in §12.3 carries measurements — 56 px top bar, 400 px rail, 140 px
## NOW, 72 px NEXT, 56 px banner — and a dimensioned diagram is a requirement. The
## rail overflowed its own panel for the whole of M3 because it carried six action
## rows where §12.3 lists four, and the only reason anyone noticed was a capture:
## the fit is what is asserted here, so the next row someone adds fails a test
## instead of quietly pushing the NOW caption off the top.
extends GutTest

const SCENE := "res://src/scenes/level/level.tscn"
## §12.3 is dimensioned at the Deck's own resolution.
const REFERENCE := Vector2(1280.0, 800.0)

var _scene: Control = null


func before_each() -> void:
	SaveService.data = {"campaign": {}, "in_progress": null,
		"stats": {"undos": 0}, "achievements_mirror": []}
	GameDirector.start_level(LevelRepository.load_level(5, 1))
	_scene = load(SCENE).instantiate()
	add_child_autofree(_scene)


func after_each() -> void:
	_scene = null
	GameDirector.state = null
	GameDirector.level = null


func _band(name: String) -> Control:
	return _scene.get_node("%" + name) as Control


func test_the_bands_are_the_sizes_the_spec_draws_them() -> void:
	assert_eq(_scene.get("TOP_BAR"), 56.0, "§12.3's top bar")
	assert_eq(_scene.get("RAIL_WIDTH"), 400.0, "§12.3's right rail")
	assert_eq(_scene.get("BANNER"), 56.0, "§12.3's banner area")
	assert_eq(_scene.get("NOW_TILE"), 140.0, "§12.3's NOW tile")
	assert_eq(_scene.get("NEXT_TILE"), 72.0, "§12.3's NEXT tile")


## "the board area never overlaps the rail" (§12.3), and the banner is reserved
## even while hidden so the board does not resize when one appears.
func test_the_board_never_overlaps_the_rail_or_the_bands() -> void:
	# Against the live viewport rather than the reference, because the rule is
	# "never overlaps" at *any* size and a headless test window is not 1280×800.
	var window: Vector2 = _scene.get_viewport_rect().size
	var area: Vector2 = _scene.call("_play_area")
	assert_lte(area.x, window.x - float(_scene.get("RAIL_WIDTH")) + 0.01,
		"the board is wider than the space left beside the rail")
	assert_lte(area.y,
		window.y - float(_scene.get("TOP_BAR")) - float(_scene.get("BANNER")) + 0.01,
		"the board is taller than the space between the bands")


## The rail has to *hold* what §12.3 puts in it. A column whose minimum height
## exceeds the rail grows in both directions and takes its first row off the top
## of the screen, which is exactly what six action rows did.
func test_the_rail_column_fits_inside_the_rail() -> void:
	await wait_process_frames(3)
	var column: Control = _band("Rail").get_node("Margin/Column")
	# The rail's height at §12.3's reference, computed rather than measured: the
	# headless window is not 1280×800 and the requirement is about 1280×800.
	var available: float = REFERENCE.y - float(_scene.get("TOP_BAR")) \
		- float(_scene.get("BANNER")) - 24.0 * 2.0
	assert_lte(column.get_combined_minimum_size().y, available,
		"the rail's contents do not fit in the rail at 1280×800")


## §12.3 lists four action rows. This is the constraint the fit above depends on,
## stated where someone adding a fifth will read it.
func test_the_rail_carries_four_action_rows() -> void:
	var actions: Control = _band("Rail").get_node("Margin/Column/Actions")
	var rows: int = 0
	for child: Node in actions.get_children():
		if child is Button:
			rows += 1
	assert_eq(rows, 4, "§12.3's rail is Undo, Discard, Wild, Hint")


## §11.4 — the two that left the rail are still reachable by finger. Legend moved
## to the top bar; Restart is a row in the pause menu, which a tap of Menu opens.
func test_legend_and_restart_are_still_reachable_without_a_keyboard() -> void:
	await wait_process_frames(3)
	var legend: Button = _band("LegendButton")
	assert_true(legend.is_visible_in_tree(), "the legend button is on screen")
	assert_gte(legend.custom_minimum_size.y, 44.0, "and thumb-reachable (§11.4)")
	assert_true(_band("MenuButton").is_visible_in_tree(), "and pause is one tap away")

	var pause: PausePanel = _band("Pause")
	pause.open()
	await wait_process_frames(2)
	var ids: Array[String] = []
	for row: Dictionary in (pause.get("_menu") as MenuList).rows():
		ids.append(str(row.get("id", "")))
	assert_true(ids.has("restart"), "restart is in the pause menu, which a tap reaches")

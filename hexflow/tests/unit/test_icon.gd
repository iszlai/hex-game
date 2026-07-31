## @core — §13.5's icon atlas, as geometry.
##
## "Line icons, 2 px stroke, 24×24 grid" is a set of measurements, and the point
## of them is that the nine read as one family. So the family is what is asserted:
## nine icons, every path inside the grid, every icon actually drawing something.
## A shape that wandered off the grid or came back empty would look like a
## rendering bug and be one of these.
extends GutTest

const GRID := 24.0


func test_the_atlas_has_the_nine_icons_the_spec_lists() -> void:
	# undo, cross, star, question, padlock, rings, target, hatch square, hexagon.
	assert_eq(Icon.Kind.size(), 9, "§13.5 lists nine icons")


func test_every_icon_draws_something() -> void:
	for kind: int in Icon.Kind.values():
		var paths: Array = Icon.paths_of(kind as Icon.Kind)
		assert_gt(paths.size(), 0, "%d has no paths" % kind)
		for path: Variant in paths:
			assert_gte((path as Array).size(), 2,
				"a path in %d has fewer than two points, so it draws nothing" % kind)


## The grid is the contract: it is what makes "2 px stroke on a 24 grid" true at
## a rail row's size, at a legend row's size and at §21's 1.5× text scale.
func test_no_icon_leaves_its_twenty_four_unit_grid() -> void:
	for kind: int in Icon.Kind.values():
		for path: Variant in Icon.paths_of(kind as Icon.Kind):
			for p: Vector2 in (path as Array):
				assert_between(p.x, 0.0, GRID, "%d runs off the grid at x=%f" % [kind, p.x])
				assert_between(p.y, 0.0, GRID, "%d runs off the grid at y=%f" % [kind, p.y])


## And each fills enough of the grid to read at 24 px. An icon drawn inside a
## quarter of its box looks like a mistake beside eight that are not.
func test_every_icon_fills_its_box() -> void:
	for kind: int in Icon.Kind.values():
		var min_p := Vector2(INF, INF)
		var max_p := Vector2(-INF, -INF)
		for path: Variant in Icon.paths_of(kind as Icon.Kind):
			for p: Vector2 in (path as Array):
				min_p = min_p.min(p)
				max_p = max_p.max(p)
		var extent: Vector2 = max_p - min_p
		assert_gte(maxf(extent.x, extent.y), GRID * 0.5,
			"%d is drawn too small to sit beside the others" % kind)


## The nine are meant to be distinguishable from each other. Two icons with the
## same path set would be a copy-paste that nobody sees until a player asks why
## Hint and Wild look identical.
func test_no_two_icons_are_the_same_drawing() -> void:
	var seen: Dictionary = {}
	for kind: int in Icon.Kind.values():
		var key: String = str(Icon.paths_of(kind as Icon.Kind))
		assert_false(seen.has(key), "%d draws the same shape as %s" % [kind, str(seen.get(key))])
		seen[key] = kind


## Drawn colour comes from outside, so §21's palette swaps reach the icons too —
## an icon that carried its own colour would keep it in all four palettes.
func test_an_icon_takes_its_colour_from_whoever_places_it() -> void:
	var icon := Icon.new()
	add_child_autofree(icon)
	var palette: Palette = Palette.current()
	icon.colour = palette.path_core
	assert_eq(icon.colour, palette.path_core)
	assert_eq(icon.custom_minimum_size, Vector2(GRID, GRID), "§13.5's 24×24 grid")
	assert_eq(icon.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"an icon inside a button must not eat the button's own taps")

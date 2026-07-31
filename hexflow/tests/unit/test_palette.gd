## @core — §13.2's palette, and the one rule that makes §21 possible.
##
## Four alternate palettes ship as `.tres` swaps with **no code change** (§21). That
## only works if two things hold: every colour the game draws comes from a token,
## and every token is actually written down in the resource. The first is a grep in
## `ci_gate.sh`; the second is here, because a token the resource forgets does not
## fail — it silently falls back to the script's default, so a deuteranopia palette
## would quietly keep one neon-dark colour and nobody would find out until someone
## who needed it did.
extends GutTest

## Every palette in the build, not just the one that happens to be default. There
## are two now (C-26 made `cairn_warm` the default and kept `neon_dark` as a §21
## alternate) and M10 adds four more — the moment this checked only one of them,
## the other five could each ship with a forgotten token.
const DIR := "res://src/data/palettes/"

var _palette: Palette = null


func before_each() -> void:
	_palette = Palette.current()


## Every `.tres` in the palette directory.
func _resources() -> Array[String]:
	var out: Array[String] = []
	for file: String in DirAccess.get_files_at(DIR):
		if file.ends_with(".tres"):
			out.append(DIR + file)
	return out


## Every `@export` on the script, in declaration order.
func _tokens() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in Palette.new().get_property_list():
		if int(entry["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE and entry["type"] == TYPE_COLOR:
			out.append(str(entry["name"]))
	return out


func test_every_shipped_palette_defines_every_token_the_script_declares() -> void:
	assert_gt(_resources().size(), 1, "there is more than one palette to check (C-26)")
	# Or the loop below would pass by finding nothing to check.
	assert_gt(_tokens().size(), 18, "the script's tokens must be discoverable at all")
	for path: String in _resources():
		var text := FileAccess.get_file_as_string(path)
		assert_gt(text.length(), 0, "%s must be readable" % path)
		var missing: Array[String] = []
		for token: String in _tokens():
			if not text.contains(token + " = Color("):
				missing.append(token)
		assert_eq(missing, [] as Array[String],
			"%s declares tokens it never sets; they fall back to the script default" % path)


## §21's swap is a *setting*, so it has to actually be one — and a palette named in
## a save that this build does not have must never leave the player unable to see
## the game. Both halves of C-26's tinting promise depend on this call working.
func test_the_live_palette_follows_the_setting_and_survives_a_bad_one() -> void:
	var was: String = str(SettingsService.get_value("palette"))
	SettingsService.set_value("palette", "neon_dark")
	assert_eq(Palette.current().path_core, (load(DIR + "neon_dark.tres") as Palette).path_core)
	SettingsService.set_value("palette", "cairn_warm")
	assert_eq(Palette.current().path_core, (load(DIR + "cairn_warm.tres") as Palette).path_core,
		"switching palettes is a setting, not an edit")
	SettingsService.set_value("palette", "a-palette-that-was-removed")
	assert_not_null(Palette.current(), "a missing palette never leaves the game unpaintable")
	SettingsService.set_value("palette", was)


## C-26: every texture is *tinted* through a token. A palette whose surface tints
## were left at the script defaults would draw the same picture as every other one,
## which is precisely what §13.1's second kept property forbids.
func test_each_palette_tints_the_art_differently() -> void:
	var tints: Dictionary = {}
	for path: String in _resources():
		var palette: Palette = load(path)
		var key: String = "%s|%s|%s" % [
			palette.backdrop_tint, palette.surface_frame, palette.surface_panel,
		]
		assert_false(tints.has(key),
			"%s tints the art exactly like %s" % [path, str(tints.get(key))])
		tints[key] = path


## §13.2 names the tokens the game is specified in. If one of these disappears, a
## screen somewhere is drawing a colour the spec never gave it.
func test_the_spec_tokens_all_exist() -> void:
	for token: String in ["bg_deep", "bg_panel", "bg_vignette", "cell_empty_fill",
			"cell_empty_stroke", "cell_candidate_stroke", "path_core", "path_glow",
			"path_gradient_far", "start_cell", "goal_cell", "wall_fill", "wall_stroke",
			"portal", "gate", "wild", "danger", "text_primary", "text_secondary", "focus"]:
		assert_true(_palette.get(token) is Color, "§13.2 requires %s" % token)


## The C-18 board added tokens of its own, and each exists because something on the
## board could not be drawn without inventing a colour on the spot.
func test_the_board_tokens_all_exist() -> void:
	for token: String in ["board_key_light", "board_ambient", "board_tile_side",
			"board_mark_outline"]:
		assert_true(_palette.get(token) is Color, "the C-18 board requires %s" % token)


## §13.2 spells `path.glow` as "path.core at 35%", so it has to *be* that — a
## token that drifted off its own definition would put a halo round the path in a
## colour the path is not.
func test_the_glow_is_the_path_at_its_own_colour() -> void:
	assert_eq(Color(_palette.path_glow, 1.0), _palette.path_core, "same hue, same value")
	assert_lt(_palette.path_glow.a, 1.0, "and translucent, or it is not a glow")


## The tokens §21 leans on hardest: a state told apart from another by colour alone
## is already a C5 bug, but two tokens that are literally the same colour make even
## the colour channel useless.
func test_no_two_cell_tokens_are_the_same_colour() -> void:
	var seen: Dictionary = {}
	for token: String in ["cell_empty_fill", "wall_fill", "path_core", "start_cell",
			"goal_cell", "portal", "gate", "wild"]:
		var colour: Color = _palette.get(token)
		assert_false(seen.has(colour), "%s duplicates %s" % [token, seen.get(colour, "")])
		seen[colour] = token

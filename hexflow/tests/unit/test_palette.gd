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

const RESOURCE := "res://src/data/palettes/neon_dark.tres"

var _palette: Palette = null


func before_each() -> void:
	_palette = load(RESOURCE)


## Every `@export` on the script, in declaration order.
func _tokens() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in Palette.new().get_property_list():
		if int(entry["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE and entry["type"] == TYPE_COLOR:
			out.append(str(entry["name"]))
	return out


func test_the_resource_defines_every_token_the_script_declares() -> void:
	var text := FileAccess.get_file_as_string(RESOURCE)
	assert_gt(text.length(), 0, "the shipped palette must be readable")
	# Or the loop below would pass by finding nothing to check.
	assert_gt(_tokens().size(), 18, "the script's tokens must be discoverable at all")
	var missing: Array[String] = []
	for token: String in _tokens():
		if not text.contains(token + " = Color("):
			missing.append(token)
	assert_eq(missing, [] as Array[String],
		"tokens declared but never set in the resource fall back to the script's default")


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

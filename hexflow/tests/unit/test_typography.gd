## @core — §13.4's five type roles.
##
## Three claims worth holding. The **18 px floor** is absolute: the Deck's screen is
## 7 inches and anything smaller fails a legibility self-audit, so no role at any
## §21 text scale may come out under it. The **numerals are tabular**, or a counter
## ticking from 9 to 10 shuffles the text beside it. And every family is **SIL OFL**
## with its licence in the tree, because "open licence only" is a shipping
## condition, not a preference.
extends GutTest

const DIR := "res://assets/fonts/"


func _all_roles() -> Array:
	return Typography.ROLES.keys()


## §13.4's floor, swept rather than spot-checked: every role, every scale §21
## allows. A role is only ever pushed *up* by the scale.
func test_no_role_is_ever_smaller_than_the_floor() -> void:
	for role: Variant in _all_roles():
		for step: int in range(0, 11):
			var scale: float = 1.0 + 0.05 * float(step)
			var px: int = Typography.size_of(role as Typography.Role, scale)
			assert_gte(px, Typography.FLOOR_PX,
				"role %d at scale %.2f came out at %d px" % [int(role), scale, px])


func test_the_caption_role_sits_exactly_on_the_floor() -> void:
	assert_eq(Typography.size_of(Typography.Role.CAPTION), Typography.FLOOR_PX,
		"§13.4's 18 px labels are the floor, so the floor has to be reachable")
	assert_eq(Typography.size_of(Typography.Role.DISPLAY), 48)
	assert_eq(Typography.size_of(Typography.Role.HEADING), 32)
	assert_eq(Typography.size_of(Typography.Role.BODY), 24)
	assert_eq(Typography.size_of(Typography.Role.NUMERAL), 24)


## §21's 100–150%. Out-of-range values are clamped rather than honoured, so a
## corrupted settings file cannot produce a 6 px caption or a 200 px title.
func test_the_scale_is_clamped_to_what_the_layouts_are_tested_at() -> void:
	var body := Typography.size_of(Typography.Role.BODY)
	assert_eq(Typography.size_of(Typography.Role.BODY, 0.2), body, "below 1.0 clamps up")
	assert_eq(Typography.size_of(Typography.Role.BODY, 9.0),
		Typography.size_of(Typography.Role.BODY, Typography.MAX_SCALE), "above 1.5 clamps down")
	assert_gt(Typography.size_of(Typography.Role.BODY, 1.5), body, "and 1.5 is bigger than 1.0")


func test_every_family_ships_with_its_open_licence() -> void:
	var families: Dictionary = {}
	for role: Variant in _all_roles():
		families[str(Typography.ROLES[role]["family"])] = true
	assert_eq(families.size(), 3, "§13.4 names three families")
	for family: Variant in families:
		assert_true(FileAccess.file_exists(DIR + str(family) + ".ttf"),
			"%s.ttf is not vendored" % family)
	# One licence per family, all SIL OFL (§13.4 admits no other kind).
	for licence: String in ["LICENSE-inter.txt", "LICENSE-spacegrotesk.txt",
			"LICENSE-jetbrainsmono.txt"]:
		var path: String = DIR + licence
		assert_true(FileAccess.file_exists(path), "%s is missing" % licence)
		assert_true(FileAccess.get_file_as_string(path).contains("SIL OPEN FONT LICENSE"),
			"%s is not the OFL" % licence)


func test_each_role_loads_at_its_own_weight() -> void:
	for role: Variant in _all_roles():
		var font := Typography.font_of(role as Typography.Role)
		assert_not_null(font.base_font, "role %d has no font" % int(role))
		assert_eq(int(font.variation_opentype["wght"]), int(Typography.ROLES[role]["weight"]),
			"role %d is drawn at the wrong weight" % int(role))
	# Display is bolder than heading, and body bolder than caption — the table is
	# a hierarchy, and a hierarchy that is not ordered is just five fonts.
	assert_gt(int(Typography.ROLES[Typography.Role.DISPLAY]["weight"]),
		int(Typography.ROLES[Typography.Role.HEADING]["weight"]))
	assert_gt(int(Typography.ROLES[Typography.Role.BODY]["weight"]),
		int(Typography.ROLES[Typography.Role.CAPTION]["weight"]))


## §13.4 asks for tabular figures by name, and this is what the phrase means: every
## digit takes the same width, so a counter does not jitter as it climbs.
func test_the_numeral_role_has_tabular_figures() -> void:
	var font := Typography.font_of(Typography.Role.NUMERAL)
	var size := Typography.size_of(Typography.Role.NUMERAL)
	var narrow := font.get_string_size("111", HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var wide := font.get_string_size("999", HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	assert_almost_eq(narrow.x, wide.x, 0.01, "digits must be one width")
	assert_gt(narrow.x, 0.0, "and the font must actually have measured something")


## The theme is what a screen sees, so every role has to arrive through it — a role
## defined here and missing there is a label silently drawn in the default face.
func test_the_theme_carries_every_role() -> void:
	var t := Typography.theme()
	assert_not_null(t.default_font, "the default type is Body")
	assert_eq(t.default_font_size, Typography.size_of(Typography.Role.BODY))
	for role: Variant in _all_roles():
		for type: String in ["Label", "Button"]:
			var name: String = Typography.variation_for(role as Typography.Role, type)
			assert_eq(t.get_type_variation_base(name), StringName(type),
				"%s must vary %s" % [name, type])
			assert_true(t.has_font("font", name), "%s has no font" % name)
			assert_eq(t.get_font_size("font_size", name),
				Typography.size_of(role as Typography.Role), "%s is the wrong size" % name)


## The scale reaches the theme, or §21's setting moves nothing on screen.
func test_scaling_the_theme_scales_every_role_in_it() -> void:
	var small := Typography.theme(1.0)
	var large := Typography.theme(Typography.MAX_SCALE)
	for role: Variant in _all_roles():
		var name: String = Typography.variation_for(role as Typography.Role)
		assert_gt(large.get_font_size("font_size", name), small.get_font_size("font_size", name),
			"%s did not grow with the scale" % name)


## Every character the interface puts on screen has to be one the font can draw.
##
## This is a bug that shows as nothing. A face missing a glyph renders an empty box,
## the build is green, the tests pass, and the only way to find out is to look at
## the right screen. It had been true for a while: Space Grotesk has no ★, so the
## results card drew its three stars as three boxes; the legend's ⬢⬡◍⌸▨⌾ are in
## none of the three vendored faces, so the whole panel was boxes.
##
## The source is scanned rather than a list being kept here, because a list is a
## thing to forget to update and the next decorative character will be added by
## someone who has never read this file.
const SCAN_DIRS := ["res://src/ui/", "res://src/scenes/", "res://src/view/"]


func _decorative_characters() -> Dictionary:
	var found: Dictionary = {}
	for dir: String in SCAN_DIRS:
		_scan(dir, found)
	return found


func _scan(dir: String, found: Dictionary) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		_scan(dir + sub + "/", found)
	for file: String in DirAccess.get_files_at(dir):
		if not file.ends_with(".gd"):
			continue
		for line: String in FileAccess.get_file_as_string(dir + file).split("\n"):
			var trimmed := line.strip_edges()
			if trimmed.begins_with("#"):
				continue  # documentation, never drawn
			var parts: PackedStringArray = line.split("\"")
			for i: int in range(1, parts.size(), 2):
				for c: String in parts[i]:
					# Above the punctuation the prose uses; those are in every face.
					if c.unicode_at(0) > 0x2000:
						found[c] = "%s%s" % [dir.get_file(), file]


func test_every_character_the_interface_draws_can_be_drawn() -> void:
	var found: Dictionary = _decorative_characters()
	assert_gt(found.size(), 0, "the scan found nothing, so it is not scanning")

	var missing: Array[String] = []
	for c: String in found:
		var covered := false
		for role: Variant in Typography.ROLES:
			if Typography.font_of(role).has_char(c.unicode_at(0)):
				covered = true
				break
		if not covered:
			missing.append("%s (U+%04X, %s)" % [c, c.unicode_at(0), found[c]])
	assert_eq(missing, [] as Array[String],
		"no vendored face can draw these, so they render as empty boxes")


## And drawable by the role that actually draws them — a character only Inter has is
## still a box in a heading. The fallback chain is what makes this hold, so this is
## the test that would fail if it were ever dropped.
func test_every_role_can_draw_every_character() -> void:
	var found: Dictionary = _decorative_characters()
	for role: Variant in Typography.ROLES:
		var font := Typography.font_of(role)
		for c: String in found:
			assert_true(font.has_char(c.unicode_at(0)),
				"%s cannot draw %s (U+%04X, from %s)" % [
					Typography.Role.keys()[role], c, c.unicode_at(0), found[c]])

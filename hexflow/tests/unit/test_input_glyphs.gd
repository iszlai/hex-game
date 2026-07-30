## @core — the §11.4 glyph atlas.
##
## "Never hardcode Xbox glyphs" is the requirement; the risk is a HUD that tells a
## Deck player to press Select when their hardware says View. CI has no controller
## attached, so what is asserted here is that the atlas is data, that every slot a
## binding asks for exists in every family, and that the keyboard fallback comes
## from the binding table rather than a second copy of it.
extends GutTest

## Slots that any family must answer, derived from the bindings themselves so a
## new action cannot quietly ship without a glyph.
func _slots_in_use() -> Array[String]:
	var out: Array[String] = []
	for action: String in InputBindings.ACTIONS:
		var slot := InputBindings.glyph_slot(action)
		if slot != "" and not out.has(slot):
			out.append(slot)
	out.sort()
	return out


func _atlas() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(InputGlyphs.PATH)
	)
	assert_true(parsed is Dictionary, "the glyph atlas must be valid JSON")
	return parsed as Dictionary


func test_the_atlas_file_exists_and_parses() -> void:
	assert_true(FileAccess.file_exists(InputGlyphs.PATH))
	assert_gt((_atlas().get("families", []) as Array).size(), 0)


## Every family answers every slot: a missing entry would silently fall through
## to a key name in the middle of a controller HUD.
func test_every_family_covers_every_slot_in_use() -> void:
	var slots := _slots_in_use()
	for entry: Variant in (_atlas()["families"] as Array):
		var family: Dictionary = entry
		var labels: Dictionary = family["labels"]
		for slot: String in slots:
			assert_true(labels.has(slot),
				"family %s has no label for slot %s" % [family["name"], slot])


## §11.4 names this case explicitly: the Deck's own naming for View/Menu.
func test_the_deck_family_uses_the_decks_own_button_names() -> void:
	var labels := _labels_of("deck")
	assert_eq(str(labels["select"]), "View")
	assert_eq(str(labels["start"]), "Menu")


func test_playstation_and_nintendo_do_not_inherit_xbox_names() -> void:
	var ps := _labels_of("playstation")
	assert_eq(str(ps["a"]), "✕", "a DualSense has no A button")
	assert_eq(str(ps["start"]), "Options")

	var nin := _labels_of("nintendo")
	assert_eq(str(nin["l1"]), "L", "a Switch pad has L/R, not LB/RB")
	assert_eq(str(nin["start"]), "+")


func test_families_are_matched_case_insensitively_and_specifically() -> void:
	# Match needles must be lowercase, since Input.get_joy_name is lowercased
	# before comparison.
	for entry: Variant in (_atlas()["families"] as Array):
		var family: Dictionary = entry
		for needle: String in (family["match"] as Array):
			assert_eq(needle, needle.to_lower(),
				"match needle %s in family %s must be lowercase" % [needle, family["name"]])


func test_a_named_default_family_exists() -> void:
	var default_name := str(_atlas().get("default_family", ""))
	assert_ne(default_name, "", "an unrecognised controller still needs labels")
	assert_false(_labels_of(default_name).is_empty())


## With no controller attached, labels come from the binding table — one source of
## truth, so a rebind cannot disagree with the HUD.
func test_the_keyboard_fallback_reads_the_binding_table() -> void:
	assert_eq(InputGlyphs.family(), "", "CI has no controller attached")
	assert_eq(InputGlyphs.label_for("board_discard"), "X")
	assert_eq(InputGlyphs.label_for("board_undo"), "Z")
	assert_eq(InputGlyphs.label_for("board_confirm"), "Space")


## "R" and "hold R" are different promises (§11.3).
func test_a_hold_action_is_labelled_as_a_hold() -> void:
	assert_eq(InputGlyphs.label_for("board_restart"), "hold R")
	assert_eq(InputGlyphs.label_for("board_hint"), "hold H")


func test_an_unknown_action_yields_an_empty_label() -> void:
	assert_eq(InputGlyphs.label_for("board_teleport"), "")


func _labels_of(family_name: String) -> Dictionary:
	for entry: Variant in (_atlas()["families"] as Array):
		var family: Dictionary = entry
		if str(family["name"]) == family_name:
			return family["labels"]
	return {}

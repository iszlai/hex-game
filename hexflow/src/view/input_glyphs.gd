## Resolves an action to the label the player's own controller uses (§11.4).
##
## "Never hardcode Xbox glyphs": the Deck calls Select and Start **View** and
## **Menu**, a DualSense has no A button, and a Switch pad puts L/R where an Xbox
## pad puts LB/RB. So the mapping is data — `src/data/input_glyphs.json`, keyed by
## [method Input.get_joy_name] — and this file is only the lookup.
##
## Keyboard labels are derived from [InputBindings] rather than duplicated, so a
## rebind can never disagree with the HUD.
##
## Static, with a cache, like [LevelRepository]. Not an autoload (§16.5).
class_name InputGlyphs

const PATH := "res://src/data/input_glyphs.json"

static var _atlas: Dictionary = {}


## The family name matched for the connected controller ("deck", "playstation",
## …), or "" when there is no controller and the keyboard is the device.
static func family() -> String:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return ""
	var name := Input.get_joy_name(pads[0]).to_lower()
	for entry: Variant in (_load().get("families", []) as Array):
		var fam: Dictionary = entry
		for needle: String in (fam["match"] as Array):
			if name.contains(needle):
				return str(fam["name"])
	return str(_load().get("default_family", ""))


## The player-facing label for [param action]: a controller glyph when a pad is
## connected, otherwise the key. Hold actions are prefixed, because "R" and
## "hold R" are different promises (§11.3).
static func label_for(action: String) -> String:
	var label := _bare_label(action)
	if label != "" and InputBindings.is_hold(action):
		return "hold %s" % label
	return label


static func _bare_label(action: String) -> String:
	var fam := family()
	if fam != "":
		var slot := InputBindings.glyph_slot(action)
		var labels := _labels_of(fam)
		if labels.has(slot):
			return str(labels[slot])
	var keys := InputBindings.keys_of(action)
	if keys.is_empty():
		return ""
	return OS.get_keycode_string(keys[0] as Key)


static func _labels_of(fam: String) -> Dictionary:
	for entry: Variant in (_load().get("families", []) as Array):
		var candidate: Dictionary = entry
		if str(candidate["name"]) == fam:
			return candidate["labels"]
	return {}


static func clear_cache() -> void:
	_atlas = {}


static func _load() -> Dictionary:
	if not _atlas.is_empty():
		return _atlas
	if not FileAccess.file_exists(PATH):
		push_error("%s is missing; controller glyphs fall back to key names" % PATH)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary):
		push_error("%s is not valid JSON" % PATH)
		return {}
	_atlas = parsed as Dictionary
	return _atlas

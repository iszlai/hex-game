## @core — the asset desk's breakdown, held against the tables the game actually reads.
##
## `tools/asset_manifest.json` tells a person what to make: sixteen sounds, three
## faces, fifty-two glyphs, each with the brief it was written from. That list is
## worth having and it is *not* the game's copy of the truth — `AudioDirector.SFX`
## is, and `Typography.ROLES` is, and `input_glyphs.json` is.
##
## Which makes drift the whole risk. A sound renamed in the game and not in the
## manifest gives an artist a brief for a file nothing will ever load, and the desk
## would report it green. So the manifest is checked against the real tables here
## rather than trusted, and the glyph list — the one that is a pure cross-product —
## is not restated at all: the desk derives it, and what is asserted is that the
## derivation still comes out at §11.4's 52.
extends GutTest

const MANIFEST := "res://tools/asset_manifest.json"
const ATLAS := "res://src/data/input_glyphs.json"


func _manifest() -> Dictionary:
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(MANIFEST)), OK,
		"tools/asset_manifest.json is not valid JSON")
	return json.data as Dictionary


func _group(role: String) -> Dictionary:
	for entry: Variant in (_manifest().get("groups", []) as Array):
		var group: Dictionary = entry
		if str(group["role"]) == role:
			return group
	return {}


func _names(group: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in (group.get("items", []) as Array):
		out.append(str((entry as Dictionary)["name"]))
	return out


## §15.2's sixteen, spelled the way the loader spells them. `AudioDirector` builds a
## path by turning `ui.move` into `ui_move.wav`, so a manifest row named anything
## else describes a file the game will not open.
func test_the_sfx_briefs_name_the_sounds_the_game_loads() -> void:
	var group: Dictionary = _group("sfx")
	assert_false(group.is_empty(), "the manifest has no sfx group")

	var wanted: Array[String] = []
	for id: Variant in AudioDirector.SFX:
		wanted.append(str(id).replace(".", "_"))
	wanted.sort()
	var listed: Array[String] = _names(group)
	listed.sort()
	assert_eq(listed, wanted,
		"the sfx breakdown and AudioDirector.SFX disagree about which sounds exist")
	assert_eq(int(group["want"]), AudioDirector.SFX.size(), "§15.2 ships 16 effects")

	for entry: Variant in (group["items"] as Array):
		var item: Dictionary = entry
		var id: String = str(item["name"]).replace("_", ".")
		assert_eq(str(item["bus"]), str(AudioDirector.SFX[id]),
			"%s is briefed for the %s bus and mixed on another (§15.3)" % [id, item["bus"]])


## §13.4's five roles over three families. The desk renders its specimen at these
## sizes and weights, so a role that moved in `Typography` and not here would show
## an artist a face at a size the game never draws it.
func test_the_type_briefs_match_the_role_table() -> void:
	var group: Dictionary = _group("fonts")
	assert_false(group.is_empty(), "the manifest has no fonts group")

	var listed: Dictionary = {}
	for entry: Variant in (group["items"] as Array):
		var item: Dictionary = entry
		for role: Variant in (item["roles"] as Array):
			listed[str((role as Dictionary)["role"])] = {
				"family": str(item["name"]),
				"size": int((role as Dictionary)["size"]),
				"weight": int((role as Dictionary)["weight"]),
			}

	assert_eq(listed.size(), Typography.ROLES.size(), "§13.4 has five type roles")
	for role: Variant in Typography.ROLES:
		var name: String = str(Typography.Role.keys()[role])
		assert_true(listed.has(name), "%s is in Typography and not in the manifest" % name)
		if not listed.has(name):
			continue
		var spec: Dictionary = Typography.ROLES[role]
		assert_eq(listed[name],
			{"family": str(spec["family"]), "size": int(spec["size"]),
				"weight": int(spec["weight"])},
			"the %s brief and Typography.ROLES disagree" % name)


## §11.4's 52. Derived rather than listed — what can go wrong is not the list going
## stale but a family or a slot being added and the requirement quietly growing.
func test_the_glyph_breakdown_still_comes_out_at_fifty_two() -> void:
	var group: Dictionary = _group("glyphs")
	assert_eq(str(group.get("derive", "")), "glyphs",
		"the glyph breakdown must be derived from the atlas, never restated")

	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(ATLAS)), OK, "%s is unreadable" % ATLAS)
	var files: Dictionary = {}
	for entry: Variant in ((json.data as Dictionary)["families"] as Array):
		var family: Dictionary = entry
		for slot: Variant in (family["labels"] as Dictionary):
			files["%s_%s" % [family["name"], slot]] = true

	assert_eq(files.size(), 52, "§11.4 is 13 slots × 4 families")
	assert_eq(int(group["want"]), files.size(),
		"the manifest's glyph count and the atlas disagree")


## Every group has to be answerable: a folder to put files in, an extension the
## game loads, and a brief that says what the files are for. A row without one is a
## row nobody can act on.
func test_every_group_says_what_to_make_and_where_it_goes() -> void:
	for entry: Variant in (_manifest().get("groups", []) as Array):
		var group: Dictionary = entry
		var role: String = str(group["role"])
		assert_true(str(group.get("dir", "")).ends_with("/"), "%s has no folder" % role)
		assert_true(str(group.get("ext", "")).begins_with("."), "%s has no extension" % role)
		assert_ne(str(group.get("brief", "")), "", "%s has no brief" % role)
		assert_true(DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path("res://" + str(group["dir"]))),
			"%s points at a folder that is not there" % role)


## The desk edits palettes in place, so the three files it reads have to be the
## three that exist. A moved token list or a renamed test would leave it editing
## nothing and reporting no failures — the worst of both.
func test_the_colour_desk_points_at_files_that_exist() -> void:
	var colour: Dictionary = _manifest().get("colour", {})
	assert_false(colour.is_empty(), "the manifest has no colour section")
	for key: String in ["tokens", "checks"]:
		assert_true(FileAccess.file_exists("res://" + str(colour[key])),
			"colour.%s points at %s, which is not there" % [key, colour[key]])
	assert_true(DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path("res://" + str(colour["dir"]))),
		"colour.dir points at %s, which is not there" % colour["dir"])


## §15.1's music, on the desk: three stems for every bed, named the way
## [AudioDirector] looks for them.
##
## The manifest is what an outside composer is handed, and the thing they most need
## from it is the *shape* of the delivery — three files per track, not one. A row
## per stem is how that gets said, and a row that named a file the game does not
## load would be a brief for the wrong deliverable.
func test_the_music_desk_asks_for_three_stems_of_every_bed() -> void:
	var paths: Dictionary = {}
	for entry: Variant in (_manifest()["assets"] as Array):
		var asset: Dictionary = entry
		if str(asset["role"]).begins_with("music_"):
			paths[str(asset["path"])] = true

	for track: String in ["menu", "chapter_1", "chapter_2", "chapter_3", "chapter_4",
			"chapter_5"]:
		for stem: String in AudioDirector.STEMS:
			var want: String = "assets/music/%s_%s.ogg" % [track, stem]
			assert_true(paths.has(want), "the desk does not ask for %s" % want)
			assert_true(FileAccess.file_exists("res://" + want), "%s does not ship" % want)
	assert_eq(paths.size(), 6 * AudioDirector.STEMS.size(),
		"six beds, three stems each, and nothing else on the music desk")

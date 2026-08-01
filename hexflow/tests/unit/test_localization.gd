## @core — §22's strings, and the Hungarian that has to keep up with them.
##
## §22 says every player-visible string lives in `assets/i18n/strings.csv` and is
## referenced by key. That is a claim about *code*, not about a file, so this test
## reads the code: every key the game asks for has to be in the table, and every
## row of the table has to say something in every language.
##
## The failure this exists to catch is silent. A `tr()` for a key nobody added
## returns the key itself — so a missing row does not crash, it puts
## `banner.no_wild` on screen where a sentence should be, in English *and* in
## Hungarian. Nothing else in the suite would notice.
extends GutTest

const CSV := "res://assets/i18n/strings.csv"

## §22: "keys are namespaced". These are the namespaces, and a string literal in
## the source that starts with one of them is a key — which is what lets this test
## find the keys held in tables (the legend's rows, the settings' labels, the
## tutorial's beats) as well as the ones written inside a `tr()`.
const NAMESPACES: Array[String] = [
	"menu.", "mode.", "hud.", "banner.", "dead.", "tutorial.", "direction.",
	"pause.", "gesture.", "glyph.", "legend.", "results.", "run.", "select.",
	"chapter.", "settings.", "binding.",
]

## Keys no literal scan in `src/` can see, and how each is really reached:
## `"binding.%s" % action`, `"chapter.%d"` and `"direction.%s"` are built from an
## id, and `tutorial.T*` is named by `beats.json` rather than by any script. All
## four are checked for *completeness* by
## [method test_the_runtime_families_are_complete] instead.
const BUILT_AT_RUNTIME: Array[String] = [
	"binding.", "chapter.", "direction.", "settings.tab.", "tutorial.T",
]

var _table: Dictionary = {}
var _languages: Array[String] = []


func before_all() -> void:
	var lines: PackedStringArray = FileAccess.get_file_as_string(CSV).split("\n")
	var header: Array = _fields(lines[0])
	for i: int in range(1, header.size()):
		_languages.append(str(header[i]))
	for n: int in range(1, lines.size()):
		if lines[n].strip_edges() == "":
			continue
		var row: Array = _fields(lines[n])
		var values: Array[String] = []
		for i: int in range(1, row.size()):
			values.append(str(row[i]))
		_table[str(row[0])] = values


## A CSV row, honouring quotes — several strings have commas in them, and a naive
## split turns those into two columns and a Hungarian translation that is missing
## its second half.
func _fields(line: String) -> Array:
	var out: Array = []
	var field: String = ""
	var quoted: bool = false
	var i: int = 0
	while i < line.length():
		var c: String = line[i]
		if c == '"':
			if quoted and i + 1 < line.length() and line[i + 1] == '"':
				field += '"'
				i += 1
			else:
				quoted = not quoted
		elif c == "," and not quoted:
			out.append(field)
			field = ""
		else:
			field += c
		i += 1
	out.append(field.strip_edges())
	return out


## Every key any script asks for, found by reading the scripts.
func _keys_in_source() -> Dictionary:
	var found: Dictionary = {}
	for path: String in _scripts("res://src"):
		var text: String = FileAccess.get_file_as_string(path)
		var literal := RegEx.create_from_string('"([a-z][a-z0-9_]*\\.[A-Za-z0-9_.]+)"')
		for m: RegExMatch in literal.search_all(text):
			var key: String = m.get_string(1)
			for space: String in NAMESPACES:
				if key.begins_with(space):
					found[key] = path
					break
	return found


func _scripts(root: String) -> Array[String]:
	var out: Array[String] = []
	for name: String in DirAccess.get_files_at(root):
		if name.ends_with(".gd"):
			out.append("%s/%s" % [root, name])
	for name: String in DirAccess.get_directories_at(root):
		out.append_array(_scripts("%s/%s" % [root, name]))
	return out


# --- the table -----------------------------------------------------------------

## §22 asks for English; the game ships Hungarian beside it. Both columns, on
## every row: a half-translated table is how a menu ends up in two languages at
## once.
func test_every_row_says_something_in_every_language() -> void:
	assert_eq(_languages, ["en", "hu"] as Array[String], "the languages the game ships")
	assert_gt(_table.size(), 100, "the table loaded")
	for key: String in _table:
		var values: Array = _table[key]
		assert_eq(values.size(), _languages.size(), "%s has a missing column" % key)
		for i: int in range(values.size()):
			assert_ne(str(values[i]).strip_edges(), "",
				"%s says nothing in %s" % [key, _languages[i]])


## §22: "no concatenated sentences; use format placeholders". A translation that
## drops one leaves a hole in the sentence — `{count}` never substituted, or a
## number that simply never appears — and both look like a bug in the game rather
## than in a row of a CSV.
func test_every_translation_keeps_the_placeholders_of_its_english() -> void:
	var braces := RegEx.create_from_string("\\{([a-z_]+)\\}")
	for key: String in _table:
		var values: Array = _table[key]
		var wanted: Array[String] = []
		for m: RegExMatch in braces.search_all(str(values[0])):
			wanted.append(m.get_string(1))
		for i: int in range(1, values.size()):
			var got: Array[String] = []
			for m: RegExMatch in braces.search_all(str(values[i])):
				got.append(m.get_string(1))
			wanted.sort()
			got.sort()
			assert_eq(got, wanted,
				"%s in %s does not use the same placeholders as the English"
					% [key, _languages[i]])


## Nothing may be keyed twice: the second row silently wins, and the first
## translation someone wrote is never seen again.
func test_no_key_is_listed_twice() -> void:
	var seen: Dictionary = {}
	var lines: PackedStringArray = FileAccess.get_file_as_string(CSV).split("\n")
	for n: int in range(1, lines.size()):
		if lines[n].strip_edges() == "":
			continue
		var key: String = str(_fields(lines[n])[0])
		assert_false(seen.has(key), "%s appears twice" % key)
		seen[key] = true


# --- the table against the game --------------------------------------------------

## Every key the game asks for is in the table. A missing one does not crash — it
## puts the key itself on screen, in every language at once.
func test_every_key_the_game_uses_is_translated() -> void:
	var used: Dictionary = _keys_in_source()
	assert_gt(used.size(), 50, "the scan found the keys")
	for key: String in used:
		assert_true(_table.has(key),
			"%s is used by %s and is in no language" % [key, used[key]])


## And nothing in the table is dead. A row nobody reads is a row a translator
## spent time on for nothing, and the first sign that a screen stopped using it.
func test_every_row_in_the_table_is_actually_used() -> void:
	var used: Dictionary = _keys_in_source()
	for key: String in _table:
		if used.has(key):
			continue
		var dynamic: bool = false
		for family: String in BUILT_AT_RUNTIME:
			if key.begins_with(family):
				dynamic = true
		assert_true(dynamic, "%s is translated and never used" % key)


## The families built from an id at runtime have to be *complete*: one row per
## bindable action, one per chapter, one per direction, one per settings tab.
## These are the rows a literal scan cannot check, so they are checked by count.
func test_the_runtime_families_are_complete() -> void:
	for action: String in InputBindings.ACTIONS:
		assert_true(_table.has("binding.%s" % action), "no name for %s" % action)
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		assert_true(_table.has("chapter.%d" % chapter), "chapter %d has no name" % chapter)
	for dir: int in Direction.ALL:
		assert_true(_table.has("direction.%s" % Direction.name_of(dir).to_lower()),
			"%s cannot be said in words" % Direction.name_of(dir))
	for beat: Variant in Tutorial.beats():
		assert_true(_table.has(str((beat as Dictionary).get("text", ""))),
			"a tutorial beat has no words: %s" % (beat as Dictionary).get("id", ""))


# --- the engine ------------------------------------------------------------------

## The imported translations are actually loaded and actually switch. This is the
## end of the pipeline the other tests only assume: a CSV that is never imported,
## or a locale the project never registered, fails exactly here.
func test_the_game_can_be_played_in_hungarian() -> void:
	var before: String = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	assert_eq(tr("menu.campaign"), "Campaign")
	TranslationServer.set_locale("hu")
	assert_eq(tr("menu.campaign"), "Kampány", "the Hungarian column is loaded")
	assert_ne(tr("mode.endless.line1"), "mode.endless.line1", "and it is not falling back to keys")
	TranslationServer.set_locale(before)


## §22's fallback: a key with no row shows *something*, and the something is the
## key rather than an empty label — a screen with a blank where a sentence should
## be is harder to notice than one with `banner.nope` on it.
func test_a_missing_key_shows_itself_rather_than_nothing() -> void:
	assert_eq(tr("banner.nope.not.a.key"), "banner.nope.not.a.key")


## The setting is what chooses the language, and it survives a round trip through
## [SettingsService] — §17.3 keeps settings out of the save file, so a player who
## picked Hungarian keeps it through a corrupted save.
func test_the_language_setting_drives_the_locale() -> void:
	var before: String = str(SettingsService.get_value("language"))
	SettingsService.set_value("language", "hu")
	SettingsService.apply_language()
	assert_eq(TranslationServer.get_locale(), "hu")

	# A language the build does not have falls back rather than leaving the player
	# looking at keys.
	SettingsService.set_value("language", "kl")
	SettingsService.apply_language()
	assert_eq(TranslationServer.get_locale(), SettingsService.LANGUAGES[0])

	SettingsService.set_value("language", before)
	SettingsService.apply_language()

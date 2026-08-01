extends Node
## Settings model, applied on change and persisted separately from saves (§17.3),
## so a corrupted save never costs a player their bindings.

signal changed(key: String, value: Variant)

const PATH := "user://settings.json"

## §22's languages, in the order the Settings screen offers them, and what each
## one is called **in itself**. A player who has landed in the wrong language
## cannot read "Hungarian" to get out of it, and every list of languages that has
## ever worked knows this.
const LANGUAGES: Array[String] = ["en", "hu"]
const LANGUAGE_NAMES: Array[String] = ["English", "Magyar"]

const DEFAULTS := {
	"music_volume": 70,
	"sfx_volume": 85,
	"ui_volume": 85,
	"haptics": 70,
	"cursor_mode": "snap",      # snap | free
	"reduce_motion": false,
	# §21 through C-18's lit board: with it on, the board takes no light at all, so
	# a tile's colour on screen is its palette colour and nothing else. Off by
	# default — the key light is what gives C-22's tile heights something to cast.
	"flat_board": false,
	"palette": "cairn_warm",    # cairn_warm | neon_dark | deuter | protan | tritan
	"text_scale": 1.0,          # 1.0 .. 1.5
	"show_glyphs": true,
	"hold_to_confirm": true,
	"language": "en",
	"fps_cap": 60,
	"vsync": true,
	"custom_bindings": {},
}

var _values: Dictionary = {}


func _ready() -> void:
	_values = DEFAULTS.duplicate(true)
	load_from_disk()
	apply_language()


## Puts §22's chosen language on the engine, which is what every `tr()` in the
## game reads.
##
## Here rather than in [GameDirector] with §21's text scale, because this is the
## *first* autoload that knows which language it is: a screen built before the
## locale is set would draw English once and then have to be told. Godot loads
## autoloads in `project.godot` order and this one is second, before anything has
## a label on it.
func apply_language() -> void:
	var chosen: String = str(get_value("language"))
	TranslationServer.set_locale(chosen if LANGUAGES.has(chosen) else LANGUAGES[0])


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	changed.emit(key, value)
	save_to_disk()


func reduce_motion() -> bool:
	return bool(get_value("reduce_motion"))


func flat_board() -> bool:
	return bool(get_value("flat_board"))


func load_from_disk() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		for key: Variant in (parsed as Dictionary).keys():
			if DEFAULTS.has(key):
				_values[key] = (parsed as Dictionary)[key]
	else:
		push_warning("settings.json unreadable; continuing with defaults")


## Atomic write: temp file, then rename (§18.2).
func save_to_disk() -> void:
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("could not write settings")
		return
	f.store_string(JSON.stringify(_values, "  "))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(PATH))

extends Node
## Settings model, applied on change and persisted separately from saves (§17.3),
## so a corrupted save never costs a player their bindings.

signal changed(key: String, value: Variant)

const PATH := "user://settings.json"

const DEFAULTS := {
	"music_volume": 70,
	"sfx_volume": 85,
	"ui_volume": 85,
	"haptics": 70,
	"cursor_mode": "snap",      # snap | free
	"reduce_motion": false,
	"palette": "neon_dark",     # neon_dark | deuter | protan | tritan | high_contrast
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

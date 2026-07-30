extends Control
## Settings (§12.2): five tabs, every control a row, every row adjusted the same
## way on every device.
##
## The whole screen is one table. A setting is `{key, label, kind, …}` and the
## screen knows how to render and step three kinds — a toggle, a choice and a
## range — so adding a setting is a row, not a widget. That matters more than it
## looks: §21 asks for text scaling "applied to every string, with layouts that
## reflow", and a screen made of hand-placed sliders is exactly the screen that
## does not reflow.
##
## Tabs page on the bumpers, as the level select's chapters do, because left and
## right are what adjust the focused row.

## §12.2's five, in its order. The first is the default focus.
const TABS: Array[String] = ["Gameplay", "Controls", "Video", "Audio", "Accessibility"]

const KIND_TOGGLE := "toggle"
const KIND_CHOICE := "choice"
const KIND_RANGE := "range"
const KIND_ACTION := "action"
const KIND_BIND := "bind"

## Every row of every tab. `key` is the [SettingsService] key, except for
## [constant KIND_ACTION] rows, which do something instead of storing something.
const ROWS := {
	"Gameplay": [
		{"key": "cursor_mode", "label": "Cursor", "kind": KIND_CHOICE,
			"values": ["snap", "free"], "names": ["snap to targets", "free"]},
		{"key": "hold_to_confirm", "label": "Destructive actions", "kind": KIND_TOGGLE,
			"names": ["press twice", "hold"]},
		{"key": "show_glyphs", "label": "Controller glyphs", "kind": KIND_TOGGLE},
	],
	"Controls": [
		{"key": "haptics", "label": "Haptics", "kind": KIND_RANGE,
			"min": 0, "max": 100, "step": 5, "suffix": "%"},
		{"key": "", "label": "Reset controls to defaults", "kind": KIND_ACTION,
			"action": "reset_bindings"},
	],
	"Video": [
		{"key": "vsync", "label": "V-Sync", "kind": KIND_TOGGLE},
		{"key": "fps_cap", "label": "Frame cap", "kind": KIND_CHOICE,
			"values": [30, 60, 90, 120, 0], "names": ["30", "60", "90", "120", "uncapped"]},
	],
	"Audio": [
		{"key": "music_volume", "label": "Music", "kind": KIND_RANGE,
			"min": 0, "max": 100, "step": 5, "suffix": "%"},
		{"key": "sfx_volume", "label": "Effects", "kind": KIND_RANGE,
			"min": 0, "max": 100, "step": 5, "suffix": "%"},
		{"key": "ui_volume", "label": "Interface", "kind": KIND_RANGE,
			"min": 0, "max": 100, "step": 5, "suffix": "%"},
	],
	"Accessibility": [
		{"key": "text_scale", "label": "Text size", "kind": KIND_CHOICE,
			"values": [1.0, 1.15, 1.25, 1.4, 1.5],
			"names": ["100%", "115%", "125%", "140%", "150%"]},
		{"key": "reduce_motion", "label": "Reduce motion", "kind": KIND_TOGGLE},
		{"key": "flat_board", "label": "Flat board", "kind": KIND_TOGGLE},
	],
}

@onready var menu: MenuList = %Menu
@onready var tab_label: Label = %TabLabel
@onready var title_label: Label = %TitleLabel
@onready var hint_label: Label = %HintLabel

var _tab: int = 0
var _palette: Palette = null
## The action waiting for its new input, or "" — the whole of the rebind mode's
## state. While it is set, every press is a *binding*, not a command, which is why
## it is checked before anything else in `_unhandled_input`.
var _capturing: String = ""


func _ready() -> void:
	InputBindings.activate(InputBindings.SET_MENU)
	_palette = load("res://src/data/palettes/neon_dark.tres")
	menu.palette = _palette
	(%Background as ColorRect).color = _palette.bg_deep
	_apply_type_roles()
	menu.activated.connect(_on_activated)
	menu.focus_moved.connect(func(_id: String) -> void: AudioDirector.play_sfx("ui.move"))
	_refresh()


func _apply_type_roles() -> void:
	title_label.theme_type_variation = Typography.variation_for(Typography.Role.HEADING)
	tab_label.theme_type_variation = Typography.variation_for(Typography.Role.BODY)
	hint_label.theme_type_variation = Typography.variation_for(Typography.Role.CAPTION)
	hint_label.add_theme_color_override("font_color", _palette.text_secondary)
	tab_label.add_theme_color_override("font_color", _palette.path_core)


func tab_name() -> String:
	return TABS[_tab]


## The rows of a tab. Controls is the one that is not a literal: §21 asks for
## "every action rebindable per device", and "every action" is [InputBindings]'
## table, not a copy of it that would rot the first time an action is added. The
## sets are listed board-first, because that is the order a player looks in.
func rows_of(tab: String) -> Array:
	if tab != "Controls":
		return ROWS[tab] as Array
	var out: Array = [(ROWS[tab] as Array)[0]]
	for set_name: String in [
		InputBindings.SET_BOARD, InputBindings.SET_MENU, InputBindings.SET_MODAL
	]:
		for action: String in InputBindings.actions_in(set_name):
			out.append({"key": "", "label": _action_label(action), "kind": KIND_BIND,
				"action": action})
	out.append((ROWS[tab] as Array)[1])
	return out


## `board_move_up` → "Board · move up". The action name is the id everything else
## uses, so it is also the only place a label can come from without a second table
## to keep in step.
static func _action_label(action: String) -> String:
	var parts: PackedStringArray = action.split("_")
	var group: String = str(parts[0]).capitalize()
	return "%s · %s" % [group, " ".join(parts.slice(1))]


func _unhandled_input(event: InputEvent) -> void:
	if InputBindings.active_set != InputBindings.SET_MENU:
		return
	if _capturing != "":
		if _capture(event):
			get_viewport().set_input_as_handled()
		return
	var handled := true
	if event.is_action_pressed("menu_up", true):
		menu.move(-1)
	elif event.is_action_pressed("menu_down", true):
		menu.move(1)
	elif event.is_action_pressed("menu_left", true):
		_step(-1)
	elif event.is_action_pressed("menu_right", true):
		_step(1)
	elif event.is_action_pressed("menu_cycle_prev"):
		_page_tab(-1)
	elif event.is_action_pressed("menu_cycle_next"):
		_page_tab(1)
	elif event.is_action_pressed("menu_accept"):
		# Accept steps forward too, so a setting is reachable without ever finding
		# left and right — one button gets a player all the way through this screen.
		_step(1)
	elif event.is_action_pressed("menu_back"):
		_leave()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _leave() -> void:
	AudioDirector.play_sfx("ui.back")
	# §12.5 — up exactly one level. Settings has two parents (§12.1 from the main
	# menu, §12.2 from the pause menu), so which one is not this screen's to guess:
	# the director remembers the door it was opened by.
	GameDirector.close_settings()


func _page_tab(step: int) -> void:
	_tab = posmod(_tab + step, TABS.size())
	AudioDirector.play_sfx("ui.move")
	_refresh()


## Moves the focused setting by [param direction]. One code path for all three
## kinds, so a range and a choice cannot drift apart in how they feel.
func _step(direction: int) -> void:
	var row: Dictionary = _focused_row()
	if row.is_empty():
		return
	match str(row["kind"]):
		KIND_ACTION:
			_do_action(str(row.get("action", "")))
			return
		KIND_BIND:
			_begin_capture(str(row["action"]))
			return
		KIND_TOGGLE:
			SettingsService.set_value(str(row["key"]),
				not bool(SettingsService.get_value(str(row["key"]))))
		KIND_CHOICE:
			var values: Array = row["values"]
			var at: int = maxi(0, values.find(SettingsService.get_value(str(row["key"]))))
			SettingsService.set_value(str(row["key"]),
				values[posmod(at + direction, values.size())])
		KIND_RANGE:
			var current: int = int(SettingsService.get_value(str(row["key"])))
			var next: int = clampi(
				current + direction * int(row["step"]), int(row["min"]), int(row["max"])
			)
			if next == current:
				AudioDirector.play_sfx("ui.reject")
				_refresh()
				return
			SettingsService.set_value(str(row["key"]), next)
	AudioDirector.play_sfx("ui.confirm")
	_apply(row)
	_refresh()


## The settings that change something other than themselves. Everything else is
## read where it is used, on the [signal SettingsService.changed] signal.
func _apply(row: Dictionary) -> void:
	var key: String = str(row.get("key", ""))
	match key:
		"music_volume":
			AudioDirector.set_bus_volume("Music", int(SettingsService.get_value(key)))
		"sfx_volume":
			AudioDirector.set_bus_volume("SFX", int(SettingsService.get_value(key)))
		"ui_volume":
			AudioDirector.set_bus_volume("UI", int(SettingsService.get_value(key)))
		"text_scale":
			# §21's scaling is a rebuild of §13.4's theme on the window, so it lands
			# on this screen too — which is the point: a player raising the text size
			# should see it happen to the words they are reading.
			GameDirector.apply_typography()
		"vsync":
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if bool(SettingsService.get_value(key))
				else DisplayServer.VSYNC_DISABLED
			)
		"fps_cap":
			Engine.max_fps = int(SettingsService.get_value(key))


func _do_action(action: String) -> void:
	match action:
		"reset_bindings":
			# §21: "a reset-to-default is always one press away".
			SettingsService.set_value("custom_bindings", {})
			InputBindings.install()
			AudioDirector.play_sfx("ui.confirm")
			_refresh()
		"rebind":
			_begin_capture(str(_focused_row().get("action", "")))


## §21's "every action rebindable per device". The next input decides *which*
## device: a key rebinds the keyboard column, a pad button rebinds the pad column,
## so a player never has to say which one they meant.
func _begin_capture(action: String) -> void:
	if action == "":
		return
	_capturing = action
	AudioDirector.play_sfx("ui.move")
	hint_label.text = "Press an input for %s   ·   %s to cancel" % [
		_action_label(action), OS.get_keycode_string(KEY_ESCAPE),
	]
	_refresh()


## Consumes one input as the new binding. Returns whether it was consumed at all,
## so a stray mouse move does not end the capture.
func _capture(event: InputEvent) -> bool:
	if event is InputEventKey and (event as InputEventKey).pressed:
		var code: int = int((event as InputEventKey).keycode)
		if code == KEY_ESCAPE:
			_end_capture("")
			return true
		_end_capture(InputBindings.rebind(_capturing, [code] as Array[int],
			InputBindings.buttons_of(_capturing)))
		return true
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var index: int = int((event as InputEventJoypadButton).button_index)
		_end_capture(InputBindings.rebind(_capturing, InputBindings.keys_of(_capturing),
			[index] as Array[int]))
		return true
	return false


## [param collision] is the action the input was already taken by, or "".
func _end_capture(collision: String) -> void:
	var action: String = _capturing
	_capturing = ""
	# Refreshed first, because `_refresh` rewrites the hint line with the key
	# prompts — anything said here has to be said after it, or it is said to nobody.
	_refresh()
	if collision == "":
		AudioDirector.play_sfx("ui.confirm")
	elif collision == action:
		# Escape, or an action that does not exist. Neither is a failure to report.
		AudioDirector.play_sfx("ui.back")
	else:
		# §11.3 shares Esc and Select on purpose, but a collision the *player*
		# creates by accident is a control they find unresponsive later with no way
		# to know why. Refused, and named.
		AudioDirector.play_sfx("ui.reject")
		hint_label.text = "Already used by %s" % _action_label(collision)


func _focused_row() -> Dictionary:
	var id: String = menu.focused_id()
	for row: Variant in rows_of(tab_name()):
		if _id_of(row as Dictionary) == id:
			return row as Dictionary
	return {}


## A row's id has to survive a tab change, so it is the key where there is one and
## the action where there is not.
static func _id_of(row: Dictionary) -> String:
	var key: String = str(row.get("key", ""))
	return key if key != "" else str(row.get("action", ""))


func _refresh() -> void:
	var keep: String = menu.focused_id()
	var rows: Array[Dictionary] = []
	for row: Variant in rows_of(tab_name()):
		var spec: Dictionary = row
		rows.append({
			"id": _id_of(spec),
			"label": str(spec["label"]),
			"value": value_text(spec),
			"enabled": true,
		})
	menu.set_rows(rows)
	menu.focus_id(keep)

	title_label.text = "Settings"
	tab_label.text = "  ·  ".join(_tab_strip())
	if _capturing != "":
		return
	hint_label.text = "%s %s change   %s %s tab   %s back" % [
		InputGlyphs.label_for("menu_left"), InputGlyphs.label_for("menu_right"),
		InputGlyphs.label_for("menu_cycle_prev"), InputGlyphs.label_for("menu_cycle_next"),
		InputGlyphs.label_for("menu_back"),
	]


## Which tab is live, said without colour: the current one is bracketed, so §21's
## "never colour alone" holds for the tab strip too.
func _tab_strip() -> Array[String]:
	var out: Array[String] = []
	for i: int in range(TABS.size()):
		out.append("[ %s ]" % TABS[i] if i == _tab else TABS[i])
	return out


## What a row reads as right now. Static-ish and public because it is also the
## honest thing for a test to assert against — the value the player sees.
func value_text(row: Dictionary) -> String:
	var kind: String = str(row["kind"])
	if kind == KIND_ACTION:
		return ""
	if kind == KIND_BIND:
		var action: String = str(row["action"])
		if action == _capturing:
			return "press an input…"
		var keys: Array[int] = InputBindings.keys_of(action)
		return OS.get_keycode_string(keys[0] as Key) if not keys.is_empty() else "unbound"
	var value: Variant = SettingsService.get_value(str(row["key"]))
	var names: Array = row.get("names", [])
	match kind:
		KIND_TOGGLE:
			if names.size() == 2:
				return str(names[1] if bool(value) else names[0])
			return "on" if bool(value) else "off"
		KIND_CHOICE:
			var values: Array = row["values"]
			var at: int = values.find(value)
			if at < 0:
				return str(value)
			return str(names[at]) if at < names.size() else str(values[at])
		KIND_RANGE:
			return "%d%s" % [int(value), str(row.get("suffix", ""))]
	return str(value)


func _on_activated(_id: String) -> void:
	# A tap on a row is the same gesture as pressing accept on it.
	_step(1)

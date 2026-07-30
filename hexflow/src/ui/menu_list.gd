## A vertical list of choices, focused one at a time (§12.5).
##
## Every `Menu` and `Modal` screen is this list with different rows, so the focus
## rules live here once: exactly one focused row at all times, wrapping within the
## list, a ring that is 3 px and never invisible, and — because §21 will not let
## focus be carried by colour — a 1.04× scale on top of it.
##
## Rows are data. A screen hands over `[{id, label, value, enabled}]` and gets an
## `activated(id)` back; it never reaches in for a `Button`. That is what lets the
## pause screen, the settings tabs and the main menu share one keyboard, one
## gamepad and one set of touch targets without sharing a layout.
class_name MenuList
extends VBoxContainer

signal activated(id: String)
signal focus_moved(id: String)

## §11.4 — every on-screen affordance is thumb-reachable at 1280×800.
const TOUCH_TARGET := 44.0

@export var palette: Palette = null

var _rows: Array[Dictionary] = []
var _buttons: Array[Button] = []
var _index: int = 0
var _ring: Tween = null


func _ready() -> void:
	if palette == null:
		palette = load("res://src/data/palettes/neon_dark.tres")
	add_theme_constant_override("separation", 12)


## Replaces the whole list. Buttons are reused where the count matches, so a menu
## that refreshes its values every frame does not rebuild its children (C4).
func set_rows(rows: Array[Dictionary]) -> void:
	_rows = rows
	while _buttons.size() < rows.size():
		_buttons.append(_new_button())
	for i: int in range(_buttons.size()):
		var button: Button = _buttons[i]
		button.visible = i < rows.size()
		if i >= rows.size():
			continue
		var row: Dictionary = rows[i]
		var label: String = str(row.get("label", ""))
		var value: String = str(row.get("value", ""))
		button.text = label if value == "" else "%s      %s" % [label, value]
		button.disabled = not bool(row.get("enabled", true))
	_index = clampi(_index, 0, maxi(0, rows.size() - 1))
	_paint()


func rows() -> Array[Dictionary]:
	return _rows


func buttons() -> Array[Button]:
	return _buttons


func focused_id() -> String:
	if _index < 0 or _index >= _rows.size():
		return ""
	return str(_rows[_index].get("id", ""))


## §12.5: focus wraps within a list. A disabled row is stepped over rather than
## landed on — §12.5 wants exactly one *focused* element, and focus on something
## that cannot be pressed is a dead end a controller cannot see.
func move(step: int) -> bool:
	if _rows.is_empty():
		return false
	var at: int = _index
	for _i: int in range(_rows.size()):
		at = posmod(at + step, _rows.size())
		if bool(_rows[at].get("enabled", true)):
			if at == _index:
				return false
			_index = at
			_paint()
			focus_moved.emit(focused_id())
			return true
	return false


## Puts focus on a row by id, ignoring a request for one that is not there — a
## screen asking for the row it *had* after a refresh is normal, not an error.
func focus_id(id: String) -> void:
	for i: int in range(_rows.size()):
		if str(_rows[i].get("id", "")) == id:
			_index = i
			_paint()
			return


func activate() -> void:
	var id: String = focused_id()
	if id == "" or not bool(_rows[_index].get("enabled", true)):
		AudioDirector.play_sfx("ui.reject")
		return
	AudioDirector.play_sfx("ui.confirm")
	activated.emit(id)


func _new_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(TOUCH_TARGET * 4.0, TOUCH_TARGET)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.theme_type_variation = Typography.variation_for(Typography.Role.BODY, "Button")
	# The pivot is the middle, so §21's 1.04× grows the row about its own centre
	# rather than pushing it down and right.
	button.pivot_offset = button.custom_minimum_size * 0.5
	button.focus_mode = Control.FOCUS_NONE
	var index: int = _buttons.size()
	button.pressed.connect(func() -> void: _on_button_pressed(index))
	add_child(button)
	return button


## A tap both focuses and activates: a finger has no separate "move here" gesture,
## and making it press twice would be a touch-only tax (§11.4).
func _on_button_pressed(index: int) -> void:
	if index >= _rows.size() or not bool(_rows[index].get("enabled", true)):
		AudioDirector.play_sfx("ui.reject")
		return
	_index = index
	_paint()
	activate()


## The ring itself. §12.5 asks for 3 px, the accent colour and 100 ms; §21 adds the
## scale, so a player who cannot see the accent still sees which row is live.
func _paint() -> void:
	for i: int in range(_buttons.size()):
		var button: Button = _buttons[i]
		var focused: bool = i == _index and i < _rows.size()
		button.add_theme_stylebox_override("normal", _box(focused, false))
		button.add_theme_stylebox_override("hover", _box(focused, true))
		button.add_theme_stylebox_override("pressed", _box(focused, true))
		button.add_theme_stylebox_override("disabled", _box(false, false))
		button.add_theme_color_override("font_color",
			palette.text_primary if focused else palette.text_secondary)
		button.add_theme_color_override("font_disabled_color", palette.cell_empty_stroke)
	_animate_ring()


func _animate_ring() -> void:
	if _ring != null and _ring.is_running():
		_ring.kill()
	if _index < 0 or _index >= _buttons.size():
		return
	_ring = create_tween()
	_ring.set_parallel(true)
	for i: int in range(_buttons.size()):
		var want: Vector2 = Vector2.ONE * (Motion.FOCUS_RING_SCALE if i == _index else 1.0)
		if _buttons[i].scale.is_equal_approx(want):
			continue
		_ring.tween_property(_buttons[i], "scale", want, Motion.focus_ring_seconds()) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _box(focused: bool, hovered: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = palette.bg_panel if (focused or hovered) else palette.cell_empty_fill
	box.set_border_width_all(Motion.FOCUS_RING_PX if focused else 1)
	box.border_color = palette.focus if focused else palette.cell_empty_stroke
	box.set_corner_radius_all(6)
	box.content_margin_left = 20.0
	box.content_margin_right = 20.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	return box

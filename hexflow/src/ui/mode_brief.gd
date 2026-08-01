## What Endless and the Daily *are*, said once before either of them starts.
##
## §12.2 gives the main menu five rows and a number beside each, and a number is
## only worth reading by somebody who already knows what it counts. "Endless —
## best 7" and "Daily — ●●○●●●● streak 4" are both perfectly clear to the person
## who built them and mean nothing to a player who has just finished the tutorial:
## neither mode is explained anywhere in the game, and both differ from the
## campaign in a way that matters on the first move (§5.9 takes undo away in both).
## Finding that out by pressing Z and watching nothing happen is the worst way to
## learn it.
##
## So each mode leads with three lines and a Play button. Three, because the modes
## are not complicated — what they are, what makes them end, and the one rule that
## is not the campaign's.
##
## A modal on a menu, built the same way [PausePanel] is: a timber card over the
## screen it belongs to, its own §11.1 action set while it is up, Back going up
## exactly one level (§12.5). It is deliberately **not** a screen — §12.1's map has
## no state for it, and a mode brief that fades the menu out and in is a mode brief
## nobody wants to see twice.
class_name ModeBrief
extends PanelContainer

## Emitted when the player says go. The screen that opened it decides what
## starting that mode means — this panel starts nothing.
signal confirmed(mode_id: String)
signal dismissed()

## The copy, per mode. Three lines each, in the order a player needs them: what it
## is, what ends it, and what is different from the campaign.
##
## Here rather than in a `.tscn`, because §22 extracts strings from code and a
## literal in a scene file survives that (the gate greps for both).
const COPY := {
	"endless": {
		"title": "Endless",
		"lines": [
			"One run that keeps getting harder.",
			"Reach the goal and the board grows a wall.",
			"It ends when no route is left. No undo here.",
		],
	},
	"daily": {
		"title": "Daily puzzle",
		"lines": [
			"One board a day, the same for everyone.",
			"A new board at midnight UTC — retry all you like.",
			"No undo here — restart instead, so scores compare.",
		],
	},
}

@export var palette: Palette = null

var _mode: String = ""
var _title: Label = null
var _lines: Array[Label] = []
var _stat: Label = null
var _menu: MenuList = null
var _hint: Label = null


func _ready() -> void:
	if palette == null:
		palette = Palette.current()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


## §13.7's timber, with the breathing room a card of prose needs.
##
## Public and idempotent because [method Surface.apply_to] walks every
## `PanelContainer` on a screen and gives it the standard panel — and a child's
## `_ready` runs before its parent's, so a card that styles itself in `_ready`
## has already been overwritten by the time the screen is up. The screen states
## its opinion after that call, which is the arrangement `Surface` documents.
func apply_style() -> void:
	var box: StyleBox = Surface.panel(palette)
	box.set_content_margin_all(32.0)
	add_theme_stylebox_override("panel", box)


func _build() -> void:
	apply_style()

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	_title = Label.new()
	_title.theme_type_variation = Typography.variation_for(Typography.Role.HEADING)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	# Three labels, built once and filled on open, rather than one label holding
	# three lines: a line is a thought, and one string with newlines in it wraps
	# into a paragraph at §21's 150% text scale.
	for _i: int in range(3):
		var line := Label.new()
		line.theme_type_variation = Typography.variation_for(Typography.Role.BODY)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(600.0, 0.0)
		column.add_child(line)
		_lines.append(line)

	# The one number the menu row was already showing, kept where the player is
	# now looking. It is the reason to press Play rather than part of the lesson,
	# so it is the caption role and it sits under the lines.
	_stat = Label.new()
	_stat.theme_type_variation = Typography.variation_for(Typography.Role.CAPTION)
	_stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stat.add_theme_color_override("font_color", palette.text_secondary)
	column.add_child(_stat)

	_menu = MenuList.new()
	_menu.palette = palette
	# Two short rows, centred, rather than two rows as wide as the prose above
	# them: §21 scales the focused row 1.04× about its centre, and a row already
	# filling the card grows out through the frame.
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu.activated.connect(_on_activated)
	_menu.focus_moved.connect(func(_id: String) -> void: AudioDirector.play_sfx("ui.move"))
	column.add_child(_menu)

	_hint = Label.new()
	_hint.theme_type_variation = Typography.variation_for(Typography.Role.CAPTION)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", palette.text_secondary)
	column.add_child(_hint)


## Shows the brief for [param mode_id], with focus on Play — a player who has read
## it before gets through it with the same press that opened it.
func open(mode_id: String) -> void:
	if not COPY.has(mode_id):
		return
	_mode = mode_id
	var copy: Dictionary = COPY[mode_id]
	_title.text = str(copy["title"])
	var lines: Array = copy["lines"]
	for i: int in range(_lines.size()):
		_lines[i].text = str(lines[i]) if i < lines.size() else ""
		_lines[i].visible = i < lines.size()
	_stat.text = _stat_line(mode_id)
	_menu.set_rows([
		{"id": "play", "label": "Play", "value": "", "enabled": true},
		{"id": "back", "label": "Back", "value": "", "enabled": true},
	])
	_hint.text = "%s play   ·   %s back" % [
		InputGlyphs.label_for("modal_accept"), InputGlyphs.label_for("modal_back"),
	]
	visible = true
	_menu.focus_id("play")
	# §11.1: a modal owns input while it is up, which is what stops the menu
	# underneath acting on the same press.
	InputBindings.activate(InputBindings.SET_MODAL)


func close() -> void:
	if not visible:
		return
	visible = false
	_mode = ""
	InputBindings.activate(InputBindings.SET_MENU)


func mode() -> String:
	return _mode


## What this mode has to show for itself so far. A first-time player gets the
## sentence that says there is nothing yet, rather than a zero.
func _stat_line(mode_id: String) -> String:
	if mode_id == "endless":
		var best: int = int((SaveService.data.get("endless", {}) as Dictionary).get("best_goals", 0))
		return "Your best: %d goals" % best if best > 0 else "You have not run this one yet"
	var daily: Dictionary = SaveService.data.get("daily", {})
	var streak: int = int(daily.get("streak", 0))
	return "Streak: %d days" % streak if streak > 0 else "No streak going yet"


## Called by the screen this sits on, before its own handling, exactly as the level
## screen calls [method PausePanel.handle_input]. Returns whether the press was
## ours.
func handle_input(event: InputEvent) -> bool:
	if not visible or InputBindings.active_set != InputBindings.SET_MODAL:
		return false
	if event.is_action_pressed("modal_up", true):
		_menu.move(-1)
	elif event.is_action_pressed("modal_down", true):
		_menu.move(1)
	elif event.is_action_pressed("modal_accept"):
		_menu.activate()
	elif event.is_action_pressed("modal_back"):
		# §12.5 — Back goes up exactly one level, and from a modal that is the menu
		# underneath it.
		AudioDirector.play_sfx("ui.back")
		_dismiss()
	else:
		return false
	return true


func _on_activated(id: String) -> void:
	if id == "play":
		var starting: String = _mode
		AudioDirector.play_sfx("ui.confirm")
		close()
		confirmed.emit(starting)
		return
	AudioDirector.play_sfx("ui.back")
	_dismiss()


func _dismiss() -> void:
	close()
	dismissed.emit()

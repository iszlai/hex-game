## The pause menu (§12.2, §12.5), as a modal over a board that is still there.
##
## It is a panel inside the level screen rather than a screen of its own, and
## `GameDirector.Screen.PAUSED` has no scene file, because §12.2 pauses *over* the
## board: swapping scenes would rebuild it, drop every animation in flight and
## charge two 320 ms fades for a menu that should feel instant. What actually
## stops the board being played is §11.1's action set — the level screen ignores
## input the moment the live set is not its own.
##
## Restart is destructive, so it is never a single press (§11.3). §21's
## "hold-to-confirm toggle" is honoured here rather than ignored: a player who
## cannot hold gets press-then-confirm instead, which is the same guarantee by a
## different gesture.
class_name PausePanel
extends PanelContainer

const TOUCH_TARGET := 44.0

@export var palette: Palette = null

var _menu: MenuList = null
var _title: Label = null
var _hint: Label = null
var _holds: HoldGesture = HoldGesture.new()
var _bar: ProgressBar = null
## Press-then-confirm's armed state, used only when §21's hold toggle is off.
var _restart_armed: bool = false


func _ready() -> void:
	if palette == null:
		palette = Palette.current()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_holds.completed.connect(_on_hold_completed)
	_holds.cancelled.connect(func(_a: String) -> void: _bar.visible = false)
	GameDirector.screen_changed.connect(_on_screen_changed)
	EventBus.pause_requested.connect(_on_pause_requested)


func _build() -> void:
	# §13.7: a modal is a panel, made of the same timber as every other surface.
	var box: StyleBox = Surface.panel(palette)
	box.set_content_margin_all(32.0)
	add_theme_stylebox_override("panel", box)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	add_child(column)

	_title = Label.new()
	_title.theme_type_variation = Typography.variation_for(Typography.Role.HEADING)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	_menu = MenuList.new()
	_menu.palette = palette
	_menu.activated.connect(_on_activated)
	_menu.focus_moved.connect(_on_focus_moved)
	column.add_child(_menu)

	# The hold's progress, in the panel rather than in the level's own strip: the
	# board is behind a modal and its banner is not where the player is looking.
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0.0, 6.0)
	_bar.max_value = 1.0
	_bar.step = 0.01
	_bar.show_percentage = false
	_bar.visible = false
	column.add_child(_bar)

	_hint = Label.new()
	_hint.theme_type_variation = Typography.variation_for(Typography.Role.CAPTION)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", palette.text_secondary)
	column.add_child(_hint)


func _on_pause_requested() -> void:
	GameDirector.pause()


func _on_screen_changed(screen: GameDirector.Screen) -> void:
	var paused: bool = screen == GameDirector.Screen.PAUSED
	if paused == visible:
		return
	visible = paused
	if paused:
		open()


## Shows the menu with §12.2's default focus on Resume. Public so the pause is a
## scenario a test can trigger without a window and an Esc key.
func open() -> void:
	_restart_armed = false
	_bar.visible = false
	visible = true
	_title.text = "Paused"
	_refresh()
	_menu.focus_id("resume")


func _refresh() -> void:
	_menu.set_rows([
		{"id": "resume", "label": "Resume", "value": "", "enabled": true},
		{"id": "restart", "label": "Restart", "value": _restart_gesture(), "enabled": true},
		{"id": "settings", "label": "Settings", "value": "", "enabled": true},
		{"id": "quit", "label": "Quit to map", "value": "", "enabled": true},
	])
	_hint.text = "%s back" % InputGlyphs.label_for("modal_back")


## §21's hold-to-confirm toggle, said out loud on the row: whichever gesture is
## live, the player is told which one it is rather than discovering it by holding
## a button that was never going to fill.
func _restart_gesture() -> String:
	if not bool(SettingsService.get_value("hold_to_confirm")):
		return "press twice" if not _restart_armed else "press to confirm"
	return "hold"


func _on_focus_moved(_id: String) -> void:
	# Moving away from Restart disarms it. An armed destructive action that
	# survives the player looking elsewhere is a trap.
	if _restart_armed:
		_restart_armed = false
		_refresh()
	_holds.cancel("modal_restart")
	_bar.visible = false


func handle_input(event: InputEvent) -> bool:
	if not visible or InputBindings.active_set != InputBindings.SET_MODAL:
		return false
	if event.is_action_pressed("modal_up", true):
		_menu.move(-1)
	elif event.is_action_pressed("modal_down", true):
		_menu.move(1)
	elif event.is_action_pressed("modal_accept"):
		_accept_pressed()
	elif event.is_action_released("modal_accept"):
		_holds.cancel("modal_restart")
		_bar.visible = false
	elif event.is_action_pressed("modal_back"):
		# §12.5 — Back goes up exactly one level, and from a modal that is the
		# thing underneath it, never out of the game.
		AudioDirector.play_sfx("ui.back")
		GameDirector.resume()
	else:
		return false
	return true


func _accept_pressed() -> void:
	if _menu.focused_id() != "restart":
		_menu.activate()
		return
	if not bool(SettingsService.get_value("hold_to_confirm")):
		# Press-then-confirm: the first press arms, the second commits (§21).
		if not _restart_armed:
			_restart_armed = true
			_refresh()
			AudioDirector.play_sfx("ui.move")
			return
		_do_restart()
		return
	_holds.begin("modal_restart", InputBindings.HOLD_RESTART)
	_bar.value = 0.0
	_bar.visible = true


func _process(delta: float) -> void:
	if not _holds.active():
		return
	_holds.tick(delta)
	_bar.value = _holds.ratio()


func _on_hold_completed(_action: String) -> void:
	_bar.visible = false
	_do_restart()


func _do_restart() -> void:
	_restart_armed = false
	AudioDirector.play_sfx("ui.confirm")
	EventBus.restart_requested.emit()
	GameDirector.resume()


func _on_activated(id: String) -> void:
	match id:
		"resume":
			GameDirector.resume()
		"settings":
			GameDirector.open_settings()
		"quit":
			# §18.3: the run is written down before the player is taken off it, so
			# leaving mid-level costs no more than a suspend does.
			GameDirector.suspend()
			GameDirector.go_to(GameDirector.level_exit_screen())

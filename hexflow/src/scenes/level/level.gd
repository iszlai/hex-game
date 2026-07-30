extends Control
## The level screen (§12.3). Sends intents up, renders facts coming down.
##
## M4: every §11.3 binding, on every device, through one path. No branch here
## tests a keycode or a button index — the screen asks
## `event.is_action_pressed("board_confirm")` and [InputBindings] decides what
## that means, so keyboard, gamepad, touch and a future rebind all arrive here
## identically. That is what makes a gamepad-only playthrough testable.
##
## M7 replaces the drawing (the C-18 orthographic-3D board) without touching this
## file's logic: the cursor comes from [InputRouter], which works from whatever
## screen-space positions the view hands it.

const RAIL_WIDTH := 400.0
const TOP_BAR := 56.0
## Reserved even while hidden, so the board never resizes when a banner appears.
const BANNER := 56.0

## §11.4 — every on-screen button is at least this tall and wide at 1280×800.
const TOUCH_TARGET := 44.0

## The actions that must be held rather than pressed (§11.3). Restart is
## destructive; the hint is a trigger that a resting finger brushes.
const HOLD_ACTIONS: Array[String] = ["board_restart", "board_hint"]

@onready var board_view: BoardView3D = %Board
@onready var title_label: Label = %TitleLabel
@onready var score_label: Label = %ScoreLabel
@onready var now_label: Label = %NowLabel
@onready var next_label: Label = %NextLabel
@onready var rail_label: Label = %RailLabel
@onready var banner: PanelContainer = %Banner
@onready var banner_label: Label = %BannerLabel
@onready var hold_panel: PanelContainer = %HoldPanel
@onready var hold_label: Label = %HoldLabel
@onready var hold_bar: ProgressBar = %HoldBar
@onready var legend: LegendPanel = %Legend
@onready var undo_button: Button = %UndoButton
@onready var discard_button: Button = %DiscardButton
@onready var wild_button: Button = %WildButton
@onready var hint_button: Button = %HintButton
@onready var legend_button: Button = %LegendButton
@onready var restart_button: Button = %RestartButton
@onready var menu_button: Button = %MenuButton

var _router: InputRouter = InputRouter.new()
var _holds: HoldGesture = HoldGesture.new()
var _haptics: Haptics = null

## The wild modifier being physically held (L2 / Shift) versus armed by one tap
## of the rail button, which §11.3 spells "Wild button, then cell".
var _wild_held: bool = false
var _wild_armed: bool = false

## Select is bound to both legend and restart: a tap toggles, a 1 s hold
## restarts. This says a legend tap is still pending, and the restart completing
## clears it.
var _legend_armed: bool = false


func _ready() -> void:
	# Each screen claims its §11.1 action set. Doing it here rather than only in
	# GameDirector.go_to keeps a directly-run scene (editor F6, the capture tool,
	# an @e2e test) playable.
	InputBindings.activate(InputBindings.SET_BOARD)

	if GameDirector.state == null:
		# Standalone run of this scene: open a real campaign level so the
		# grey-box is exercisable without the menu.
		GameDirector.start_level(LevelRepository.load_level(2, 4))

	_apply_cursor_mode()
	SettingsService.changed.connect(_on_setting_changed)

	_haptics = Haptics.new()
	_haptics.name = "Haptics"
	add_child(_haptics)

	_router.cursor_moved.connect(_on_cursor_moved)
	_router.cursor_rejected.connect(_on_cursor_rejected)
	_router.cycling_hint_wanted.connect(_on_cycling_hint_wanted)
	_holds.completed.connect(_on_hold_completed)
	_holds.cancelled.connect(_on_hold_cancelled)

	EventBus.state_reset.connect(_on_state_reset)
	EventBus.legal_targets_changed.connect(_on_legal_targets_changed)
	EventBus.tile_advanced.connect(_on_tile_advanced)
	EventBus.level_won.connect(_on_level_won)
	EventBus.level_dead.connect(_on_level_dead)
	EventBus.tile_auto_skipped.connect(_on_auto_skipped)
	EventBus.illegal_move_attempted.connect(_on_illegal)
	EventBus.cell_joined.connect(_on_cell_joined)
	EventBus.goal_reached.connect(_on_goal_reached)

	get_viewport().size_changed.connect(_layout_board)
	banner.visible = false
	hold_panel.visible = false
	_wire_buttons()
	_bind_current_state()


func _bind_current_state() -> void:
	var state: GameState = GameDirector.state
	if state == null:
		return
	_layout_board()
	board_view.bind(state, _play_area())
	_refresh_candidates()
	_on_tile_advanced(state.current_tile(), state.preview(2))
	_refresh_hud()


func _play_area() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(maxf(320.0, vp.x - RAIL_WIDTH), maxf(320.0, vp.y - TOP_BAR - BANNER))


func _layout_board() -> void:
	var area := _play_area()
	board_view.position = Vector2(0.0, TOP_BAR)
	if GameDirector.state != null and board_view.layout != null:
		board_view.bind(GameDirector.state, area)


# --- input (§11.3, every column) ----------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# §11.1: input belonging to another action set is not ours to act on.
	if InputBindings.active_set != InputBindings.SET_BOARD:
		return
	if _pointer(event):
		get_viewport().set_input_as_handled()
		return
	# Deliberately not short-circuited: Select is bound to *both* restart and the
	# legend, so one press has to reach both handlers (§11.3).
	var handled := _wild_modifier(event)
	handled = _hold_input(event) or handled
	handled = _action(event) or handled
	if handled:
		get_viewport().set_input_as_handled()


## Mouse, trackpad and touch. A touch arrives here *and*, with Godot's mouse
## emulation on, again as a click — which is harmless by construction: the first
## press takes the cell out of `legal_targets`, so the duplicate finds nothing to
## select and no second placement is ever requested.
func _pointer(event: InputEvent) -> bool:
	var at := Vector2.INF
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		at = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		at = (event as InputEventScreenTouch).position
	if at == Vector2.INF:
		return false
	# Converted by the board itself: it is the only thing that knows where it sits
	# and how a point on the window becomes a cell (§4.3, and B7 for why this never
	# happens in screen coordinates).
	if _router.point_at(board_view.cell_at(board_view.local_point(at))):
		_confirm()
	return true


func _wild_modifier(event: InputEvent) -> bool:
	if event.is_action_pressed("board_wild_modifier"):
		_wild_held = true
		_refresh_candidates()
		return true
	if event.is_action_released("board_wild_modifier"):
		_wild_held = false
		_refresh_candidates()
		return true
	return false


## Starts and aborts the hold gestures. Nothing fires on the press itself; the
## action happens in [method _on_hold_completed] when the threshold is reached.
func _hold_input(event: InputEvent) -> bool:
	var handled := false
	for action: String in HOLD_ACTIONS:
		if event.is_action_pressed(action):
			_begin_hold(action)
			handled = true
		elif event.is_action_released(action):
			_holds.cancel(action)
			handled = true
	return handled


## The hold prompt lives in its own strip, not in the banner: a tap of Select
## must not wipe a dead-state prompt the player still needs to read (§5.8).
func _begin_hold(action: String) -> void:
	_holds.begin(action, InputBindings.hold_seconds(action))
	hold_label.text = "Hold %s to %s" % [
		InputGlyphs.label_for(action),
		"restart" if action == "board_restart" else "show a hint",
	]
	hold_bar.value = 0.0
	hold_panel.visible = true


func _action(event: InputEvent) -> bool:
	# Movement repeats on a held key, so echo is allowed; nothing else is.
	if event.is_action_pressed("board_move_up", true):
		_router.move(Vector2.UP)
	elif event.is_action_pressed("board_move_down", true):
		_router.move(Vector2.DOWN)
	elif event.is_action_pressed("board_move_left", true):
		_router.move(Vector2.LEFT)
	elif event.is_action_pressed("board_move_right", true):
		_router.move(Vector2.RIGHT)
	elif event.is_action_pressed("board_cycle_prev"):
		_router.cycle(-1)
	elif event.is_action_pressed("board_cycle_next"):
		_router.cycle(1)
	elif event.is_action_pressed("board_confirm"):
		_confirm()
	elif event.is_action_pressed("board_undo"):
		EventBus.undo_requested.emit()
	elif event.is_action_pressed("board_discard"):
		EventBus.discard_requested.emit()
	elif event.is_action_pressed("board_legend"):
		# Resolved on release: this same press may turn out to be a restart hold.
		_legend_armed = true
	elif event.is_action_released("board_legend"):
		if _legend_armed:
			_legend_armed = false
			legend.toggle()
	# Pause is resolved before back because §11.3 gives both Esc, and from
	# gameplay both mean "up one level" (§12.5).
	elif event.is_action_pressed("board_pause"):
		EventBus.pause_requested.emit()
	elif event.is_action_pressed("board_back"):
		EventBus.pause_requested.emit()
	elif event.is_action_pressed("board_rotate_cw"):
		_rotate(1)
	elif event.is_action_pressed("board_rotate_ccw"):
		_rotate(-1)
	else:
		return false
	return true


## Turning the board moves every candidate on screen, so the router has to be re-fed
## with the new positions — §11.2 works in screen space and knows nothing about a
## camera. `BoardView3D` has already jumped its positions to the stop it is heading
## for, so this reads the destination rather than the tween.
func _rotate(steps: int) -> void:
	board_view.rotate_by(steps)
	_refresh_candidates()


func _process(delta: float) -> void:
	if not _holds.active():
		if hold_panel.visible:
			hold_panel.visible = false
		return
	# Only reached while a hold is in flight, and allocates nothing (C4).
	_holds.tick(delta)
	hold_bar.value = _holds.ratio()


func _on_hold_completed(action: String) -> void:
	hold_panel.visible = false
	match action:
		"board_restart":
			# The restart consumed the Select press, so no legend toggle follows.
			_legend_armed = false
			EventBus.restart_requested.emit()
		"board_hint":
			_show_hint()


func _on_hold_cancelled(_action: String) -> void:
	hold_panel.visible = false


func _confirm() -> void:
	if not _router.has_cursor:
		return
	var state: GameState = GameDirector.state
	if _wild_active() and state != null and state.wild_charges > 0:
		_wild_armed = false
		EventBus.wild_place_requested.emit(_router.cursor)
		return
	EventBus.place_requested.emit(_router.cursor)


## §12.6 — the hint replays the solver from the live state and points at the
## first move of the optimal continuation. Bounded so it can never stall a frame.
func _show_hint() -> void:
	var state: GameState = GameDirector.state
	if state == null or state.status != GameState.Status.PLAYING:
		return
	var result := Solver.solve_state(state, 40_000)
	if not result.is_solvable() or result.moves.is_empty():
		_flash_banner("No hint available")
		return
	GameDirector.hints_used += 1
	_router.point_at(result.moves[0])
	_flash_banner("Hint: %v" % result.moves[0])


# --- touch (§11.4) -----------------------------------------------------------

## Every rail affordance is a real button, so the touch column of §11.3 needs no
## separate code path. Labels carry the glyph of the *player's* controller (§11.4)
## and are set here rather than in the scene, so the scene holds no literal for
## the §22 gate to catch at M10.
func _wire_buttons() -> void:
	for button: Button in [
		undo_button, discard_button, wild_button,
		hint_button, legend_button, restart_button, menu_button,
	]:
		button.custom_minimum_size = Vector2(TOUCH_TARGET, TOUCH_TARGET)

	undo_button.pressed.connect(func() -> void: EventBus.undo_requested.emit())
	discard_button.pressed.connect(func() -> void: EventBus.discard_requested.emit())
	legend_button.pressed.connect(func() -> void: legend.toggle())
	menu_button.pressed.connect(func() -> void: EventBus.pause_requested.emit())

	# "Wild button, then cell" (§11.3): one tap arms, the next placement spends.
	wild_button.pressed.connect(_on_wild_button)
	# A button press is already deliberate, so the hint needs no hold here. The
	# R2/H hold exists because a trigger is easy to brush, not because hinting is
	# dangerous.
	hint_button.pressed.connect(_show_hint)
	# Restart *is* destructive, so the button holds like every other route to it.
	restart_button.button_down.connect(func() -> void: _begin_hold("board_restart"))
	restart_button.button_up.connect(func() -> void: _holds.cancel("board_restart"))


func _on_wild_button() -> void:
	var state: GameState = GameDirector.state
	if state == null or state.wild_charges <= 0:
		_flash_banner("No wild charge")
		return
	_wild_armed = not _wild_armed
	if _wild_armed:
		_flash_banner("Wild armed — choose a cell")
	else:
		banner.visible = false
	_refresh_candidates()


# --- facts -------------------------------------------------------------------

func _on_state_reset(state: GameState) -> void:
	banner.visible = false
	_router.has_cursor = false
	_wild_armed = false
	board_view.bind(state, _play_area())
	_refresh_hud()


func _on_legal_targets_changed(_targets: Array) -> void:
	# The fact arrives as the plain legal set, but the *reachable* set is wider
	# while a wild charge is armed, so the live state is re-read instead.
	_refresh_candidates()


## Feeds the router and the board the set the cursor may occupy.
##
## §11.2 snaps the cursor to `legal_targets` only, which on its own makes a wild
## charge unspendable: §6 lets a charge enter any cell adjacent to the path, and
## in snap mode the cursor could never get to one of those extra cells. So arming
## the wild widens the candidate set to `wild_targets()` — that is what makes
## "L2 + A" and "Wild button, then cell" actually reach anything.
func _refresh_candidates() -> void:
	var state: GameState = GameDirector.state
	if state == null:
		return
	var targets: Array[Vector3i] = state.legal_targets()
	if _wild_active() and state.wild_charges > 0:
		targets = state.wild_targets()
	board_view.set_candidates(targets)
	_router.set_candidates(targets, board_view.centres(), _play_area() * 0.5)
	board_view.set_cursor(_router.cursor, _router.has_cursor)
	_refresh_hud()


func _wild_active() -> bool:
	return _wild_held or _wild_armed


func _on_cursor_moved(cell: Vector3i) -> void:
	board_view.set_cursor(cell, true)
	_haptics.play("cursor_move")


func _on_cursor_rejected() -> void:
	_haptics.play("cursor_reject")


## §11.2 — three cone rejections in a row means the player is fighting the
## geometry, so name the input that always works.
func _on_cycling_hint_wanted() -> void:
	_flash_banner("Try %s / %s to step through the targets" % [
		InputGlyphs.label_for("board_cycle_prev"),
		InputGlyphs.label_for("board_cycle_next"),
	])


func _on_cell_joined(_target: Vector3i, _anchor: Vector3i, _dir: int) -> void:
	_haptics.play("commit")


func _on_goal_reached(_cell: Vector3i) -> void:
	_haptics.play("goal")


func _on_tile_advanced(_current: int, _preview: Array) -> void:
	board_view.rebuild()
	_refresh_hud()


func _on_auto_skipped(dir: int) -> void:
	# Deliberately not a failure beat: no charge is spent (§5.7).
	_haptics.play("auto_discard")
	_flash_banner("No move — %s skipped, no cost" % Direction.name_of(dir))


func _on_illegal(_cell: Vector3i) -> void:
	# §12.4 gives an illegal confirm the same double haptic as a cone rejection.
	_haptics.play("cursor_reject")
	_flash_banner("Not a legal target")


func _on_level_won(placements: int, par: int, stars: int) -> void:
	_flash_banner("Complete — %d placements, par %d, %s" % [
		placements, par, "★".repeat(stars) + "☆".repeat(Scoring.MAX_STARS - stars)
	])


func _on_level_dead() -> void:
	# Never a hard fail: undo takes the default focus (§5.8).
	_haptics.play("dead")
	_flash_banner("No route left — %s undo · %s restart" % [
		InputGlyphs.label_for("board_undo"), InputGlyphs.label_for("board_restart")
	])


func _on_setting_changed(key: String, _value: Variant) -> void:
	# The Settings screen itself is M5; the router follows the setting the moment
	# something writes it.
	if key == "cursor_mode":
		_apply_cursor_mode()


func _apply_cursor_mode() -> void:
	_router.mode = (
		InputRouter.Mode.FREE
		if str(SettingsService.get_value("cursor_mode")) == "free"
		else InputRouter.Mode.SNAP
	)


func _flash_banner(text: String) -> void:
	banner_label.text = text
	banner.visible = true


func _refresh_hud() -> void:
	var state: GameState = GameDirector.state
	var level: Level = GameDirector.level
	if state == null or level == null:
		return

	title_label.text = level.id if level.id != "" else "Hexflow"
	score_label.text = "placements %d / par %d" % [state.placements, level.par]

	now_label.text = "NOW   %s" % Direction.name_of(state.current_tile())
	var names: Array[String] = []
	for d: int in state.preview(2):
		names.append(Direction.name_of(d))
	next_label.text = "NEXT  %s" % " ".join(names)

	undo_button.text = "↺ Undo        %s" % InputGlyphs.label_for("board_undo")
	undo_button.disabled = not GameDirector.undo_available()
	discard_button.text = "✕ Discard %d   %s" % [
		state.discards_left, InputGlyphs.label_for("board_discard")
	]
	wild_button.text = "%s Wild %d      %s" % [
		"▣" if _wild_active() else "★",
		state.wild_charges,
		InputGlyphs.label_for("board_wild_modifier"),
	]
	hint_button.text = "? Hint        %s" % InputGlyphs.label_for("board_hint")
	legend_button.text = "≡ Legend      %s" % InputGlyphs.label_for("board_legend")
	restart_button.text = "⟳ Restart     %s" % InputGlyphs.label_for("board_restart")
	menu_button.text = "Menu %s" % InputGlyphs.label_for("board_pause")

	var lines: Array[String] = [
		"move   %s" % InputGlyphs.label_for("board_move_up"),
		"cycle  %s / %s" % [
			InputGlyphs.label_for("board_cycle_prev"),
			InputGlyphs.label_for("board_cycle_next"),
		],
		"place  %s" % InputGlyphs.label_for("board_confirm"),
		"wild   %s + %s" % [
			InputGlyphs.label_for("board_wild_modifier"),
			InputGlyphs.label_for("board_confirm"),
		],
	]
	if level.has_budget():
		lines.insert(0, "budget      %d / %d" % [state.placements, level.budget])
	rail_label.text = "\n".join(lines)
	board_view.rebuild()

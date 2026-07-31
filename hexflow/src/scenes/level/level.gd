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

## §12.3's band sizes at the 1280×800 reference, which is also the Deck's screen.
## They are constants rather than numbers in the scene file because the layout is a
## *requirement* — the diagram in §12.3 is dimensioned — and a scene file is where
## a dimension goes to be nudged by accident.
const RAIL_WIDTH := 400.0
const TOP_BAR := 56.0
## Reserved even while hidden, so the board never resizes when a banner appears.
const BANNER := 56.0
## The NOW tile and the NEXT stack. §12.3 draws NOW at 140 px and NEXT at 72; C-18
## turned NEXT into a pile of coins, so 72 is the height of the face on top and the
## pile is allowed the depth underneath it.
const NOW_TILE := 140.0
const NEXT_TILE := 72.0
const NEXT_STACK_DEPTH := 24.0

## §11.4 — every on-screen button is at least this tall and wide at 1280×800.
const TOUCH_TARGET := 44.0

## The actions that must be held rather than pressed (§11.3). Restart is
## destructive; the hint is a trigger that a resting finger brushes.
const HOLD_ACTIONS: Array[String] = ["board_restart", "board_hint"]

@onready var board_view: BoardView3D = %Board
@onready var title_label: Label = %TitleLabel
@onready var score_label: Label = %ScoreLabel
@onready var stars_label: Label = %StarsLabel
@onready var now_label: Label = %NowLabel
@onready var next_label: Label = %NextLabel
@onready var now_stack: TileStack = %NowStack
@onready var next_stack: TileStack = %NextStack
@onready var rail_label: Label = %RailLabel
@onready var banner: PanelContainer = %Banner
@onready var banner_label: Label = %BannerLabel
@onready var hold_panel: PanelContainer = %HoldPanel
@onready var hold_label: Label = %HoldLabel
@onready var hold_bar: ProgressBar = %HoldBar
@onready var legend: LegendPanel = %Legend
@onready var pause_panel: PausePanel = %Pause
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

## Rail button -> the right-hand `Label` carrying its binding. Built once (C4).
var _hints: Dictionary = {}
## Rail button -> its §13.5 line icon, likewise built once.
var _icons: Dictionary = {}

## §14.1's queue advance and auto-discard. Both are tweens on nodes that already
## exist — the flyaway is built once at `_ready` and reused, because a node created
## the moment a tile is discarded is an allocation in that frame (C4).
var _queue_tween: Tween = null
var _flyaway: TileStack = null
var _flyaway_tween: Tween = null

## §10's live beat, or an empty dictionary. The screen owns the *presentation* of a
## beat and [Tutorial] owns which one it is — this holds only what is on screen now
## and how long it has been there.
var _beat: Dictionary = {}
var _beat_seconds: float = 0.0
## §10.2's Interaction column, for the beats that point at the rail. The tween is
## kept so it can be stopped: a highlight that outlived its beat would be the game
## pointing at something it is no longer talking about.
var _glow: Tween = null
var _glowing: Control = null


func _ready() -> void:
	# Each screen claims its §11.1 action set. Doing it here rather than only in
	# GameDirector.go_to keeps a directly-run scene (editor F6, the capture tool,
	# an @e2e test) playable.
	InputBindings.activate(InputBindings.SET_BOARD)

	if GameDirector.state == null:
		# Standalone run of this scene: open a real campaign level so the
		# grey-box is exercisable without the menu.
		GameDirector.start_level(LevelRepository.load_level(2, 4))

	# §13.2: not one colour lives in the scene file, so §21's palette swaps stay a
	# resource change with no code change.
	# §13.7: the board plays over the chapter's painted backdrop. The flat fill
	# stays as the clear colour underneath, at zero alpha, so a build with no art
	# in it (C-27) looks exactly as it did before rather than black.
	Backdrop.install(self, LevelRepository.locate(GameDirector.level.id).x)
	(%Background as ColorRect).color = Color(board_view.palette.bg_deep, 0.0)
	_apply_type_roles()

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
	# §5.8's dead state is recoverable, so the board's colour has to come back with
	# it — an undo out of a dead end is exactly when a grey board would lie.
	EventBus.legal_targets_changed.connect(_on_targets_for_life)
	EventBus.legal_targets_changed.connect(_on_legal_targets_changed)
	EventBus.tile_advanced.connect(_on_tile_advanced)
	EventBus.move_undone.connect(func() -> void: _beat_action("undo"))
	EventBus.level_won.connect(_on_level_won)
	EventBus.level_dead.connect(_on_level_dead)
	EventBus.tile_auto_skipped.connect(_on_auto_skipped)
	EventBus.illegal_move_attempted.connect(_on_illegal)
	EventBus.cell_joined.connect(_on_cell_joined)
	EventBus.goal_reached.connect(_on_goal_reached)

	# The rail's arrows point where a tile will actually travel, so they follow the
	# board round. This is the same signal the cursor's screen positions ride, and
	# it fires with the stop being travelled *to* — so a glance at the rail during
	# the turn already shows the board that is arriving.
	board_view.screen_positions_changed.connect(_on_board_turned)
	get_viewport().size_changed.connect(_layout_board)
	EventBus.tile_discarded.connect(_on_tile_discarded)
	EventBus.wild_charges_changed.connect(_on_wild_charges_changed)
	banner.visible = false
	hold_panel.visible = false
	_wire_buttons()
	_build_flyaway()
	_open_tutorial()
	_bind_current_state()


func _bind_current_state() -> void:
	var state: GameState = GameDirector.state
	if state == null:
		return
	_layout_board()
	board_view.bind(state, _play_area())
	_refresh_candidates()
	_on_board_turned()
	_on_tile_advanced(state.current_tile(), state.preview(2))
	_refresh_hud()


## §13.4 by role, never by size: a screen says what a label *is* and [Typography]
## decides the family and the px, so §21's text scale stays a setting rather than
## an edit in every scene.
func _apply_type_roles() -> void:
	title_label.theme_type_variation = Typography.variation_for(Typography.Role.HEADING)
	# The counters are the numeral role for one reason: tabular figures, so
	# "placements 9" and "placements 10" do not shuffle the text beside them.
	score_label.theme_type_variation = Typography.variation_for(Typography.Role.NUMERAL)
	stars_label.theme_type_variation = Typography.variation_for(Typography.Role.NUMERAL)
	rail_label.theme_type_variation = Typography.variation_for(Typography.Role.NUMERAL)
	for caption: Label in [now_label, next_label]:
		caption.theme_type_variation = Typography.variation_for(Typography.Role.CAPTION)
	banner_label.theme_type_variation = Typography.variation_for(Typography.Role.HEADING)


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
	# The pause menu is a modal *inside* this screen (§12.2 pauses over a board
	# that is still there), so it gets first refusal — and it only answers while
	# the `Modal` set is live, which is the same §11.1 rule stated once more.
	if pause_panel.handle_input(event):
		get_viewport().set_input_as_handled()
		return
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
	# §10.1 gives the tutorial first claim on Back — "skippable at any time with a
	# single Back press". It has to be resolved before the pause branch rather than
	# after it, because §11.3 puts `board_pause` and `board_back` on the same Esc
	# and the pause would otherwise always win on a keyboard. It only claims the
	# press while a beat is actually up.
	if event.is_action_pressed("board_back") or event.is_action_pressed("board_pause"):
		if _skip_tutorial():
			return true
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
	_tick_beat(delta)
	if not _holds.active():
		if hold_panel.visible:
			hold_panel.visible = false
		return
	# Only reached while a hold is in flight, and allocates nothing (C4).
	_holds.tick(delta)
	hold_bar.value = _holds.ratio()


## §10.2's timed completions, and the fallback for the ones that wait on an action:
## a player who never presses undo must not be left reading T5 for the whole level.
## Allocates nothing — it is a float and a comparison (C4).
func _tick_beat(delta: float) -> void:
	if _beat.is_empty():
		return
	var limit: float = float(_beat.get("seconds", 0))
	if limit <= 0.0:
		return
	_beat_seconds += delta
	if _beat_seconds >= limit:
		_finish_beat()


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
	_style_hud()

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


## §12.3's proportions and §13.2's colours, applied in code because neither may
## live in the scene file: the band sizes are a dimensioned requirement, and a
## colour in a `.tscn` survives all four of §21's palette swaps (the gate greps
## for both).
func _style_hud() -> void:
	var palette: Palette = board_view.palette
	now_stack.custom_minimum_size = Vector2(0.0, NOW_TILE)
	next_stack.custom_minimum_size = Vector2(0.0, NEXT_TILE + NEXT_STACK_DEPTH)
	banner.custom_minimum_size = Vector2(0.0, BANNER)

	for panel: PanelContainer in [%TopBar as PanelContainer, %Rail as PanelContainer,
			banner, hold_panel]:
		panel.add_theme_stylebox_override("panel", _panel_box(palette))
	for button: Button in [
		undo_button, discard_button, wild_button,
		hint_button, legend_button, restart_button, menu_button,
	]:
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(state, _rail_box(palette, state))
		button.add_theme_color_override("font_color", palette.text_primary)
		button.add_theme_color_override("font_hover_color", palette.path_core)
		button.add_theme_color_override("font_disabled_color", palette.cell_empty_stroke)
	score_label.add_theme_color_override("font_color", palette.text_primary)
	stars_label.add_theme_color_override("font_color", palette.goal_cell)
	rail_label.add_theme_color_override("font_color", palette.text_secondary)
	for caption: Label in [now_label, next_label]:
		caption.add_theme_color_override("font_color", palette.text_secondary)
	_build_hints(palette)


## §12.3 draws each rail row as a label on the left and its binding on the right,
## and a `Button` has one string. So the binding is a second `Label`, anchored to
## the row's right edge — built **once**, here, because a node created in
## `_refresh_hud` would be a node created on every move (C4). It ignores the
## pointer, so the row underneath is still one tap target (§11.4).
func _build_hints(palette: Palette) -> void:
	if not _hints.is_empty():
		return
	for pair: Array in [
		[undo_button, Icon.Kind.UNDO], [discard_button, Icon.Kind.DISCARD],
		[wild_button, Icon.Kind.WILD], [hint_button, Icon.Kind.HINT],
	]:
		var button: Button = pair[0]
		# §13.5's line icon, on the left of the row where §12.3 draws its glyph. It
		# ignores the pointer, so the row is still one tap target (§11.4).
		var icon := Icon.new()
		icon.kind = pair[1]
		icon.colour = palette.text_primary
		button.add_child(icon)
		icon.set_anchors_preset(Control.PRESET_CENTER_LEFT)
		icon.anchor_right = 0.0
		icon.offset_left = 14.0
		icon.offset_right = 14.0 + Icon.GRID
		icon.offset_top = -Icon.GRID * 0.5
		icon.offset_bottom = Icon.GRID * 0.5
		_icons[button] = icon

		var hint := Label.new()
		hint.name = "Hint"
		hint.theme_type_variation = Typography.variation_for(Typography.Role.CAPTION)
		hint.add_theme_color_override("font_color", palette.text_secondary)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Parented *before* the anchors are set: `set_anchors_preset` computes its
		# offsets against the parent's rect, and a node that has no parent yet has
		# no rect to compute against.
		button.add_child(hint)
		# A centred strip on the row's right edge rather than a full rect: a `Label`
		# filling the button reports the button's height but lays its text out at the
		# top of it, which puts the binding above the action it belongs to.
		hint.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		hint.anchor_left = 0.5
		hint.offset_left = 0.0
		hint.offset_right = -16.0
		hint.offset_top = -12.0
		hint.offset_bottom = 12.0
		_hints[button] = hint


## A rail row: §13.5's icon, the action, and its binding. The label is padded on
## the left because a `Button` centres or left-aligns *its own* text and knows
## nothing about the icon standing in front of it.
func _row(button: Button, label: String, action: String) -> void:
	button.text = "     " + label if _icons.has(button) else label
	var hint: Label = _hints.get(button)
	if hint != null:
		hint.text = InputGlyphs.label_for(action)


## §13.7: a bar or a rail is timber. One builder for every surface in the game
## lives in [Surface], so what a panel is made of is decided in one file.
func _panel_box(palette: Palette) -> StyleBox:
	return Surface.panel(palette)


## A rail row: the reading surface, lit when the pointer or the focus is on it. The
## disabled state is a *dimmer* row rather than a hidden one, because §12.3 shows
## the discard count and the wild charge whether or not either can be spent right
## now — "0 left" is information and an absent row is not.
func _rail_box(palette: Palette, state: String) -> StyleBox:
	return Surface.row(palette, state == "focus", state == "hover" or state == "pressed")


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

## Any move that leaves the player with somewhere to go has left the dead state.
func _on_targets_for_life(targets: Array) -> void:
	if not targets.is_empty():
		board_view.clear_dead()


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
	targets = _tutorial_gate(targets)
	if _branch_available(targets):
		_try_trigger("branch_available")
	board_view.set_candidates(targets)
	_router.set_candidates(targets, board_view.centres(), _play_area() * 0.5)
	board_view.set_cursor(_router.cursor, _router.has_cursor)
	_refresh_hud()


## §10.1: "Beat 1 gates input to the single correct cell." The level's stored
## solution is what "correct" means — the solver's own optimum, verified at
## generation and re-verified on every push, so the tutorial cannot teach a move
## the game does not think is best.
##
## §10.2's own Interaction column is the narrower claim: "only the one legal target
## accepts input". On chapter 1 level 1 there *is* exactly one — one path cell, one
## direction — so the board already satisfies it and this changes nothing. It earns
## its place on the level after that, or on a reseeded one, where there might be two.
##
## The stored optimum is used when it is available and legal, and only then. It
## cannot simply be trusted: the optimal line for chapter 1 level 1 opens with a
## **discard** (C-14 is why the script exists at all), and a beat that reads "your
## tile points north-east" must not gate the player onto a cell that tile cannot
## reach. So the fallback is the ordinary legal set, which is never wrong.
func _tutorial_gate(targets: Array[Vector3i]) -> Array[Vector3i]:
	if _beat.is_empty() or not Tutorial.gates(_beat):
		return targets
	var wanted: Vector3i = _first_scripted_move()
	if wanted != Hex.NONE and targets.has(wanted):
		return [wanted] as Array[Vector3i]
	if targets.size() == 1:
		return targets
	# More than one legal target and no scripted move among them: take the first,
	# so §10.1's "the single correct cell" is still a single cell. They are all
	# legal, so none of them is wrong.
	return [targets[0]] as Array[Vector3i]


## The first cell the stored optimal line places on, or [constant Hex.NONE].
func _first_scripted_move() -> Vector3i:
	var level: Level = GameDirector.level
	if level == null:
		return Hex.NONE
	for step: Variant in level.solution_script:
		var entry: Array = step
		if int(entry[0]) == Solver.ACTION_PLACE:
			return entry[1] as Vector3i
	return Hex.NONE


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


func _on_cell_joined(target: Vector3i, _anchor: Vector3i, _dir: int) -> void:
	_haptics.play("commit")
	# §10.2: a placement both ends the beat that was waiting for one (T1, T4) and
	# is the trigger for the beat that follows it (T2, T5).
	_beat_action("place")
	_try_trigger("after_place")
	# The board has already been rebuilt with the new cell in it; this is §14.1's
	# 220 ms pop and 160 ms connector draw played over the top of that.
	board_view.play_placement(target)


func _on_goal_reached(cell: Vector3i) -> void:
	_haptics.play("goal")
	board_view.play_goal_reached(cell)


func _on_board_turned() -> void:
	var yaw: float = BoardCamera.YAW_STOP_RADIANS * float(board_view.camera.yaw_step)
	now_stack.set_board_yaw(yaw)
	next_stack.set_board_yaw(yaw)


func _on_tile_advanced(_current: int, _preview: Array) -> void:
	board_view.rebuild()
	_refresh_hud()
	_play_queue_advance()


## §14.1: 180 ms, `CUBIC`/`EASE_OUT` — "current flies to board, next slides up and
## scales 72→140 px". The two stacks are laid out by a container, so the tile grows
## into its slot rather than travelling to it: the *sizes* §12.3 names are the ones
## being interpolated between, and the slide is the container's own reflow. What
## the beat has to convey is that the tile in NEXT is now the tile in NOW, and a
## piece arriving at 140 from 72 says that.
func _play_queue_advance() -> void:
	if now_stack == null:
		return
	var seconds: float = Motion.seconds("queue_advance")
	if seconds <= 0.0:
		return
	if _queue_tween != null and _queue_tween.is_running():
		_queue_tween.kill()
	# Grows about its own middle, so the piece expands in place instead of shoving
	# the NEXT caption beneath it.
	now_stack.pivot_offset = now_stack.size * 0.5
	now_stack.scale = Vector2.ONE * (NEXT_TILE / NOW_TILE)
	_queue_tween = create_tween()
	Motion.shape(_queue_tween, "queue_advance")
	_queue_tween.tween_property(now_stack, "scale", Vector2.ONE, seconds)


## §12.4 and §14.1's auto-discard: "tile arcs off-screen right with a fading
## trail", 260 ms, `QUAD`/`EASE_IN`. Built once and reused — a tile is discarded
## often enough that building the node each time would allocate on a beat the
## player triggers by accident (C4).
func _build_flyaway() -> void:
	_flyaway = TileStack.new()
	_flyaway.name = "Flyaway"
	_flyaway.slots = 1
	_flyaway.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flyaway.visible = false
	_flyaway.custom_minimum_size = Vector2(NOW_TILE, NOW_TILE)
	add_child(_flyaway)


func _on_tile_discarded(dir: int, _left: int) -> void:
	_play_flyaway(dir)
	_beat_action("discard")


func _on_auto_skipped(dir: int) -> void:
	# Deliberately not a failure beat: no charge is spent (§5.7).
	_haptics.play("auto_discard")
	_play_flyaway(dir)
	_try_trigger("auto_skipped")
	_flash_banner("No move — %s skipped, no cost" % Direction.name_of(dir))


## The arc itself. §14.5 turns it off rather than shortening it into a twitch: at
## 40% of 260 ms a tile crossing 400 px is a flicker, and §14.5's business is to
## reduce motion, not to make it harder to follow.
func _play_flyaway(dir: int) -> void:
	if _flyaway == null or SettingsService.reduce_motion():
		return
	if _flyaway_tween != null and _flyaway_tween.is_running():
		_flyaway_tween.kill()
	_flyaway.show_tiles([dir] as Array[int])
	_flyaway.set_board_yaw(BoardCamera.YAW_STOP_RADIANS * float(board_view.camera.yaw_step))
	var from: Vector2 = now_stack.global_position
	_flyaway.position = from
	_flyaway.size = Vector2(NOW_TILE, NOW_TILE)
	_flyaway.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_flyaway.visible = true

	var seconds: float = Motion.seconds("auto_discard")
	var span: float = get_viewport_rect().size.x - from.x + NOW_TILE
	_flyaway_tween = create_tween()
	_flyaway_tween.set_parallel(true)
	# The arc: horizontal travel takes §14.1's curve, and the vertical is a single
	# hop over it, so the tile leaves the rail rather than sliding along it.
	Motion.shape(_flyaway_tween, "auto_discard")
	_flyaway_tween.tween_method(
		func(t: float) -> void:
			_flyaway.position = Vector2(from.x + span * t, from.y - 70.0 * sin(t * PI)),
		0.0, 1.0, seconds)
	_flyaway_tween.tween_property(_flyaway, "modulate:a", 0.0, seconds)
	_flyaway_tween.chain().tween_callback(func() -> void: _flyaway.visible = false)


func _on_illegal(cell: Vector3i) -> void:
	# §12.4 gives an illegal confirm the same double haptic as a cone rejection.
	_haptics.play("cursor_reject")
	board_view.play_illegal(cell)
	if GameDirector.level != null and GameDirector.level.board.is_wall(cell):
		# §10.2's T7 — "Walls never open", said at the moment the player has just
		# tried to open one, which is the only moment it is worth saying.
		_try_trigger("wall_targeted")
		if not _beat.is_empty():
			return
	_flash_banner("Not a legal target")


func _on_level_won(placements: int, par: int, stars: int) -> void:
	# §14.3's whole allowance for camera motion nobody asked for, spent here.
	board_view.play_completion()
	_flash_banner("Complete — %d placements, par %d, %s" % [
		placements, par, "★".repeat(stars) + "☆".repeat(Scoring.MAX_STARS - stars)
	])


## §5.8 makes this recoverable, so the banner's job is to tell the player *which*
## recovery they want. "No route left" was said for all four endings, and it points
## at the board — which is the wrong half of the screen when what actually ran out
## is the tile queue.
const DEAD_REASONS := {
	GameState.Dead.BUDGET: "Budget spent",
	GameState.Dead.UNREACHABLE_GOAL: "A goal is walled off",
	GameState.Dead.PATH_FROZEN: "The path is boxed in",
	GameState.Dead.OUT_OF_TILES: "Out of tiles",
}


func _on_level_dead(reason: int) -> void:
	# Never a hard fail: undo takes the default focus (§5.8).
	_haptics.play("dead")
	board_view.play_dead()
	_flash_banner("%s — %s undo · %s restart" % [
		DEAD_REASONS.get(reason, "No route left"),
		InputGlyphs.label_for("board_undo"), InputGlyphs.label_for("board_restart")
	])


# --- tutorial (§10) -----------------------------------------------------------

## The triggers §10.2 waits on that are true the moment a level opens. Checked in
## the table's own order, so a level carrying two of them shows the earlier beat
## first and the later one when the earlier is done.
func _open_tutorial() -> void:
	if GameDirector.level == null or GameDirector.mode != GameDirector.Mode.CAMPAIGN:
		# §10 weaves the tutorial into chapter 1; endless and the daily are not
		# places to be taught, and a beat firing there would be teaching a player
		# who has already been through it.
		return
	_try_trigger("level_start")
	var board: Board = GameDirector.level.board
	if not board.cells_with_flag(Board.F_GATE).is_empty():
		_try_trigger("gate_visible")
	if not board.portal_pairs().is_empty():
		_try_trigger("portal_visible")


## §10.1: "Non-blocking after the first beat" — so a trigger arriving while a beat
## is up is dropped rather than queued. Twelve words on screen, never two beats'.
func _try_trigger(trigger: String) -> void:
	if not _beat.is_empty() or GameDirector.level == null:
		return
	if GameDirector.mode != GameDirector.Mode.CAMPAIGN:
		return
	var spec: Dictionary = Tutorial.next_for(GameDirector.level.id, trigger)
	if spec.is_empty():
		return
	_beat = spec
	_beat_seconds = 0.0
	var state: GameState = GameDirector.state
	var direction: int = state.current_tile() if state != null else Direction.NONE
	_flash_banner(Tutorial.text_of(spec, direction))
	_begin_glow(Tutorial.highlight_of(spec))
	# T1 gates input to the one correct cell, so the candidate set has to shrink
	# *now* rather than on the next refresh.
	if Tutorial.gates(spec):
		_refresh_candidates()


## Ends the live beat and records it, so §10's "never repeats" needs nothing
## remembered by the screen.
func _finish_beat() -> void:
	if _beat.is_empty():
		return
	Tutorial.mark_seen(str(_beat.get("id", "")))
	var was_gate: bool = Tutorial.gates(_beat)
	_beat = {}
	banner.visible = false
	_end_glow()
	if was_gate:
		_refresh_candidates()


## An action the live beat was waiting for, if it was.
func _beat_action(action: String) -> void:
	if _beat.is_empty():
		return
	if str(_beat.get("done", "")) == action:
		_finish_beat()


## §10.1: "Skippable at any time with a single Back press; skipping sets all flags
## seen." Back means pause everywhere else on this screen, so a live beat is the
## one thing that gets first claim on it — and only while one is actually up.
func _skip_tutorial() -> bool:
	if _beat.is_empty():
		return false
	Tutorial.skip_all()
	_beat = {}
	banner.visible = false
	_end_glow()
	_refresh_candidates()
	return true


## §10.2's Interaction column for the four beats that point at the rail: "undo
## button glows", "discard button glows", "HUD charge slot fills", "the tiles to
## come are shown *here*". A beat that says "undo is free" while nothing indicates
## which thing undo *is* has stated a fact rather than taught anything — the
## pointing is the lesson.
##
## It borrows the board's own breathing rather than inventing a second idiom, so
## the rail and the candidates pulse on the same clock and at the same rate. §14.5
## stops the loop and leaves the row **held bright**, which is what §14.5 does to
## every other loop in the game: the emphasis is feedback, and reducing motion does
## not mean removing what the player is being told.
func _begin_glow(what: String) -> void:
	_end_glow()
	_glowing = _rail_element(what)
	if _glowing == null:
		return
	var lit: Color = board_view.palette.goal_cell.lightened(0.35)
	if not Motion.loops("candidate_breathing"):
		_glowing.modulate = lit
		return
	# Half a period each way, so one breath takes the period §14.1 names.
	var half: float = Motion.seconds("candidate_breathing") * 0.5
	_glow = create_tween()
	_glow.set_loops()
	Motion.shape(_glow, "candidate_breathing")
	_glow.tween_property(_glowing, "modulate", lit, half)
	_glow.tween_property(_glowing, "modulate", Color.WHITE, half)


func _end_glow() -> void:
	if _glow != null and _glow.is_running():
		_glow.kill()
	_glow = null
	if _glowing != null:
		_glowing.modulate = Color.WHITE
		_glowing = null


## The rail elements a beat can point at. Names rather than nodes in the data, so
## `tutorial.json` never has to know what the scene tree looks like.
func _rail_element(what: String) -> Control:
	match what:
		"undo": return undo_button
		"discard": return discard_button
		"wild": return wild_button
		"next": return next_stack
	return null


## §10.2's T4 fires on "the first branch opportunity" — two legal targets that are
## not neighbours of each other, which is the board saying the path has become a
## tree rather than a line.
func _branch_available(targets: Array[Vector3i]) -> bool:
	for i: int in range(targets.size()):
		for j: int in range(i + 1, targets.size()):
			if Hex.distance(targets[i], targets[j]) > 1:
				return true
	return false


func _on_wild_charges_changed(charges: int) -> void:
	if charges > 0:
		_try_trigger("wild_gained")


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

	# §12.3's top bar reads "← Ch2 · Level 7", not a level id. The id is what the
	# save and the solver call it; the player never chose it.
	var at: Vector2i = LevelRepository.locate(level.id)
	title_label.text = "Chapter %d · Level %d" % [at.x, at.y] if at.x > 0 \
		else (level.id if level.id != "" else "Hexflow")
	score_label.text = "placements %d / par %d" % [state.placements, level.par]
	# The star band is live and has a label of its own: it shows what the run is
	# worth *now*, so a player one placement from dropping a star can see it before
	# they spend it (§5.10). Its own label because it and the counter grow at
	# different moments, and sharing one string makes the longer of them clip.
	var earned: int = Scoring.stars(maxi(1, state.placements), level.par)
	stars_label.text = "★".repeat(earned) + "☆".repeat(Scoring.MAX_STARS - earned)

	# The pieces say which directions are coming; the captions say how many are
	# left. A count only means anything for a level whose tile array is fixed —
	# the endless and daily bags are unbounded by construction (§5.3, C-18).
	# `Direction.NONE` is a sentinel, not a direction. Printing "NONE" told the
	# player the name of a constant when what they needed to know was that the queue
	# is empty — which is the same information the banner now leads with.
	now_label.text = "NOW   %s" % (Direction.name_of(state.current_tile())
		if state.current_tile() >= 0 else "—")
	next_label.text = "NEXT" if state.stream.remaining() < 0 \
		else "NEXT  %d left" % state.stream.remaining()
	now_stack.show_tiles([state.current_tile()] as Array[int])
	next_stack.show_tiles(state.preview(next_stack.slots))

	# §12.3's rail rows: the action on the left, its binding on the right. Both
	# halves are set here rather than in the scene, so the scene holds no literal
	# for §22's check to catch at M10 and a rebind shows up without the rail
	# knowing rebinding exists.
	_row(undo_button, "Undo", "board_undo")
	undo_button.disabled = not GameDirector.undo_available()
	_row(discard_button, "Discard %d" % state.discards_left, "board_discard")
	_row(wild_button, "Wild %d" % state.wild_charges, "board_wild_modifier")
	# The armed wild is the one row whose *state* has to show: §11.3's "Wild button,
	# then cell" is a mode, and a mode with no indicator is a mode nobody trusts.
	(_icons[wild_button] as Icon).colour = board_view.palette.wild if _wild_active() \
		else board_view.palette.text_primary
	_row(hint_button, "Hint", "board_hint")
	# §12.3's rail is four action rows. Legend and Restart are not among them and
	# do not fit — six rows plus a 140 px NOW tile overflow the 400 px rail, which
	# is how they came to be there in M3 with the key hints displaced into the
	# legend to make room. Legend moves to the top bar; Restart keeps its hold on
	# every device *and* its row in the pause menu, so touch still reaches it
	# without a rail row (§11.4).
	legend_button.text = "≡ %s" % InputGlyphs.label_for("board_legend")
	menu_button.text = "Menu %s" % InputGlyphs.label_for("board_pause")

	# The rail keeps what is *state* — the budget of §6, which nothing else shows.
	# The key hints that used to sit here moved into the legend when the tile stack
	# took the room; §12.3's rail has no block of them either.
	rail_label.text = "budget      %d / %d" % [state.placements, level.budget] \
		if level.has_budget() else ""
	board_view.rebuild()

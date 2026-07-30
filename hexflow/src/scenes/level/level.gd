extends Control
## The level screen (§12.3). Sends intents up, renders facts coming down.
##
## M3 grey-box: real geometry, real rules, real win/dead handling, plain text HUD
## and keyboard input. M4 adds the gamepad and touch paths through the same
## [InputRouter]; M7 replaces the drawing without touching this file's logic.

const RAIL_WIDTH := 400.0
const TOP_BAR := 56.0
## Reserved even while hidden, so the board never resizes when a banner appears.
const BANNER := 56.0

@onready var board_view: BoardView = %BoardView
@onready var title_label: Label = %TitleLabel
@onready var score_label: Label = %ScoreLabel
@onready var now_label: Label = %NowLabel
@onready var next_label: Label = %NextLabel
@onready var rail_label: Label = %RailLabel
@onready var banner: PanelContainer = %Banner
@onready var banner_label: Label = %BannerLabel

var _router: InputRouter = InputRouter.new()


func _ready() -> void:
	if GameDirector.state == null:
		# Standalone run of this scene (editor F6, capture tool): open a real
		# campaign level so the grey-box is exercisable without the menu.
		GameDirector.start_level(LevelRepository.load_level(2, 4))

	_router.mode = (
		InputRouter.Mode.FREE
		if str(SettingsService.get_value("cursor_mode")) == "free"
		else InputRouter.Mode.SNAP
	)
	_router.cursor_moved.connect(_on_cursor_moved)

	EventBus.state_reset.connect(_on_state_reset)
	EventBus.legal_targets_changed.connect(_on_legal_targets_changed)
	EventBus.tile_advanced.connect(_on_tile_advanced)
	EventBus.level_won.connect(_on_level_won)
	EventBus.level_dead.connect(_on_level_dead)
	EventBus.tile_auto_skipped.connect(_on_auto_skipped)
	EventBus.illegal_move_attempted.connect(_on_illegal)

	get_viewport().size_changed.connect(_layout_board)
	banner.visible = false
	_bind_current_state()


func _bind_current_state() -> void:
	var state: GameState = GameDirector.state
	if state == null:
		return
	_layout_board()
	board_view.bind(state, _play_area())
	_on_legal_targets_changed(state.legal_targets())
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


# --- input (§11.3 keyboard column) -------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mouse := event as InputEventMouseButton
		var cell := board_view.cell_at(mouse.position - board_view.position)
		if _router.point_at(cell):
			_confirm()
		get_viewport().set_input_as_handled()
		return

	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var key := (event as InputEventKey).keycode
	var shift := (event as InputEventKey).shift_pressed

	match key:
		KEY_UP, KEY_W:
			_router.move(Vector2.UP)
		KEY_DOWN, KEY_S:
			_router.move(Vector2.DOWN)
		KEY_LEFT, KEY_A:
			_router.move(Vector2.LEFT)
		KEY_RIGHT:
			_router.move(Vector2.RIGHT)
		KEY_Q:
			_router.cycle(-1)
		KEY_E:
			_router.cycle(1)
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if shift:
				_confirm_wild()
			else:
				_confirm()
		KEY_Z, KEY_BACKSPACE:
			EventBus.undo_requested.emit()
		KEY_D:
			EventBus.discard_requested.emit()
		KEY_R:
			EventBus.restart_requested.emit()
		KEY_H:
			_show_hint()
		KEY_ESCAPE:
			EventBus.pause_requested.emit()
		_:
			return
	get_viewport().set_input_as_handled()


func _confirm() -> void:
	if _router.has_cursor:
		EventBus.place_requested.emit(_router.cursor)


func _confirm_wild() -> void:
	var state: GameState = GameDirector.state
	if state == null or state.wild_charges <= 0:
		return
	if _router.has_cursor:
		EventBus.wild_place_requested.emit(_router.cursor)


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


# --- facts -------------------------------------------------------------------

func _on_state_reset(state: GameState) -> void:
	banner.visible = false
	_router.has_cursor = false
	board_view.bind(state, _play_area())
	_refresh_hud()


func _on_legal_targets_changed(targets: Array) -> void:
	var typed: Array[Vector3i] = []
	for t: Variant in targets:
		typed.append(t as Vector3i)
	board_view.set_candidates(typed)
	var positions: Dictionary = board_view.centres()
	_router.set_candidates(typed, positions, _play_area() * 0.5)
	board_view.set_cursor(_router.cursor, _router.has_cursor)
	_refresh_hud()


func _on_cursor_moved(cell: Vector3i) -> void:
	board_view.set_cursor(cell, true)


func _on_tile_advanced(_current: int, _preview: Array) -> void:
	board_view.rebuild()
	_refresh_hud()


func _on_auto_skipped(dir: int) -> void:
	# Deliberately not a failure beat: no charge is spent (§5.7).
	_flash_banner("No move — %s skipped, no cost" % Direction.name_of(dir))


func _on_illegal(_cell: Vector3i) -> void:
	_flash_banner("Not a legal target")


func _on_level_won(placements: int, par: int, stars: int) -> void:
	_flash_banner("Complete — %d placements, par %d, %s" % [
		placements, par, "★".repeat(stars) + "☆".repeat(Scoring.MAX_STARS - stars)
	])


func _on_level_dead() -> void:
	# Never a hard fail: undo takes the default focus (§5.8).
	_flash_banner("No route left — [Z] undo · [R] restart")


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

	var lines: Array[String] = [
		"↺ Undo      Z   %s" % ("available" if GameDirector.undo_available() else "—"),
		"✕ Discard   D   %d" % state.discards_left,
		"★ Wild      ⇧+␣ %d" % state.wild_charges,
		"? Hint      H",
		"⟳ Restart   R",
		"",
		"move  ← ↑ ↓ →     cycle  Q / E",
		"place  space      quit   esc",
	]
	if level.has_budget():
		lines.insert(0, "budget      %d / %d" % [state.placements, level.budget])
	rail_label.text = "\n".join(lines)
	board_view.rebuild()

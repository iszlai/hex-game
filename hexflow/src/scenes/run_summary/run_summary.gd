extends Control
## The endless run summary (§12.2, §12.1's `Endless → RunSummary : DEAD`).
##
## §12.2 asks for four things: goals reached, personal best, a leaderboard slice
## of "top 3 + friends + self", and Retry / Menu with Retry focused. Three of them
## are here. The fourth needs a leaderboard *read*, and [SteamService] has only
## `submit_leaderboard` until GodotSteam links — so the slice says it is waiting
## for Steam rather than showing three invented names, which is the version of
## this screen that would survive into a store build unnoticed.

@onready var menu: MenuList = %Menu
@onready var title_label: Label = %TitleLabel
@onready var score_label: Label = %ScoreLabel
@onready var best_label: Label = %BestLabel
@onready var board_label: Label = %BoardLabel

var _palette: Palette = null
var _result: Dictionary = {}


func _ready() -> void:
	InputBindings.activate(InputBindings.SET_MENU)
	EventBus.language_changed.connect(_refresh)
	_palette = Palette.current()
	menu.palette = _palette
	Backdrop.install(self)
	(%Background as ColorRect).color = Color(_palette.bg_deep, 0.0)
	_result = GameDirector.last_result.duplicate()
	Surface.apply_to(self, _palette)
	_apply_type_roles()
	menu.activated.connect(_on_activated)
	menu.focus_moved.connect(func(_id: String) -> void: AudioDirector.play_sfx("ui.move"))
	_refresh()
	# §12.2's default focus for this screen.
	menu.focus_id("retry")


func _apply_type_roles() -> void:
	title_label.theme_type_variation = Typography.variation_for(Typography.Role.HEADING)
	score_label.theme_type_variation = Typography.variation_for(Typography.Role.DISPLAY)
	best_label.theme_type_variation = Typography.variation_for(Typography.Role.NUMERAL)
	board_label.theme_type_variation = Typography.variation_for(Typography.Role.CAPTION)
	best_label.add_theme_color_override("font_color", _palette.text_secondary)
	board_label.add_theme_color_override("font_color", _palette.text_secondary)


func _refresh() -> void:
	var goals: int = int(_result.get("goals", 0))
	var placements: int = int(_result.get("placements", 0))
	var endless: Dictionary = SaveService.data.get("endless", {})
	var best: int = int(endless.get("best_goals", 0))

	title_label.text = tr("run.title")
	# §7.2: "Score = goals_reached". The placement count is the tie-break (§5.10),
	# so it is shown next to the score rather than as a score of its own.
	score_label.text = tr("run.score").format({"goals": goals})
	if bool(_result.get("best", false)):
		score_label.add_theme_color_override("font_color", _palette.goal_cell)
		best_label.text = tr("run.best_new").format({"placements": placements})
	else:
		score_label.add_theme_color_override("font_color", _palette.path_core)
		best_label.text = tr("run.best").format({"best": best, "placements": placements})

	board_label.text = tr("run.no_steam") if not SteamService.available \
		else "endless_best_goals"

	menu.set_rows([
		{"id": "retry", "label": tr("run.retry"), "value": "", "enabled": true},
		{"id": "menu", "label": tr("run.menu"), "value": "", "enabled": true},
	])


func _unhandled_input(event: InputEvent) -> void:
	if InputBindings.active_set != InputBindings.SET_MENU:
		return
	var handled := true
	if event.is_action_pressed("menu_up", true):
		menu.move(-1)
	elif event.is_action_pressed("menu_down", true):
		menu.move(1)
	elif event.is_action_pressed("menu_accept"):
		menu.activate()
	elif event.is_action_pressed("menu_back"):
		_to_menu()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _on_activated(id: String) -> void:
	match id:
		"retry":
			# A new run, not the same one again: §7.2's escalation is the run, and
			# replaying a dead board's seed would be replaying its ending.
			GameDirector.start_endless(int(Time.get_unix_time_from_system()))
			GameDirector.go_to(GameDirector.Screen.LEVEL)
		"menu":
			_to_menu()


## §12.1 draws Endless straight off the main menu, so that is the one level up.
func _to_menu() -> void:
	AudioDirector.play_sfx("ui.back")
	GameDirector.go_to(GameDirector.Screen.MAIN_MENU)

extends Control
## The main menu (§12.2): the five ways out of it, each carrying the number that
## makes it worth pressing.
##
## §12.2 does not ask for a menu with a progress read-out beside it; it asks for
## "Campaign (with % complete), Endless (with best), Daily (with streak + timer to
## reset)". The numbers are the row, not decoration on it — they are how a player
## picks up a game they left three weeks ago.

const TOUCH_TARGET := 44.0

@onready var menu: MenuList = %Menu
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var footer_label: Label = %FooterLabel

var _palette: Palette = null
var _clock: Timer = null


func _ready() -> void:
	InputBindings.activate(InputBindings.SET_MENU)
	_palette = load("res://src/data/palettes/neon_dark.tres")
	menu.palette = _palette
	(%Background as ColorRect).color = _palette.bg_deep
	_apply_type_roles()

	menu.activated.connect(_on_activated)
	menu.focus_moved.connect(func(_id: String) -> void: AudioDirector.play_sfx("ui.move"))

	# §7.3's "timer to reset" is a live number, so something has to tick it. One
	# second, on a `Timer`, rather than a `_process` that rebuilds five strings a
	# frame to change one of them (C4).
	_clock = Timer.new()
	_clock.name = "DailyClock"
	_clock.wait_time = 1.0
	_clock.timeout.connect(_refresh)
	add_child(_clock)
	_clock.start()

	_refresh()
	# §12.2's default focus for this screen.
	menu.focus_id("campaign")


func _apply_type_roles() -> void:
	title_label.theme_type_variation = Typography.variation_for(Typography.Role.DISPLAY)
	title_label.add_theme_color_override("font_color", _palette.path_core)
	subtitle_label.theme_type_variation = Typography.variation_for(Typography.Role.CAPTION)
	subtitle_label.add_theme_color_override("font_color", _palette.text_secondary)
	footer_label.theme_type_variation = Typography.variation_for(Typography.Role.CAPTION)
	footer_label.add_theme_color_override("font_color", _palette.text_secondary)


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
		# §12.5 — Back "never quits the game from gameplay", and this is not
		# gameplay: the main menu is the top of the state machine, so there is
		# nothing above it to go up to and Back is deliberately inert here.
		AudioDirector.play_sfx("ui.reject")
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _on_activated(id: String) -> void:
	match id:
		"campaign":
			GameDirector.go_to(GameDirector.Screen.LEVEL_SELECT)
		"endless":
			# §7.2 is one escalating run and says nothing about repeating it, so the
			# run seed is the clock: two sessions are different runs, and the stage
			# seeds inside a run stay §19-deterministic off this one number (C-12).
			GameDirector.start_endless(int(Time.get_unix_time_from_system()))
			GameDirector.go_to(GameDirector.Screen.LEVEL)
		"daily":
			GameDirector.start_daily(utc_date())
			GameDirector.go_to(GameDirector.Screen.LEVEL)
		"settings":
			GameDirector.go_to(GameDirector.Screen.SETTINGS)
		"quit":
			# The run is written down first: §18.3's promise is that closing the
			# window costs no more than a suspend does.
			GameDirector.suspend()
			get_tree().quit()


## Today, in UTC — the only clock §7.3 recognises, so a player in Auckland and one
## in Los Angeles are solving the same board on the same calendar day.
static func utc_date() -> String:
	var now: Dictionary = Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02d" % [int(now["year"]), int(now["month"]), int(now["day"])]


## Seconds until the next UTC midnight, which is when §7.3's puzzle changes.
static func seconds_to_reset() -> int:
	var now: Dictionary = Time.get_datetime_dict_from_system(true)
	var elapsed: int = int(now["hour"]) * 3600 + int(now["minute"]) * 60 + int(now["second"])
	return 86400 - elapsed


static func _hms(total: int) -> String:
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]


func _refresh() -> void:
	var endless: Dictionary = SaveService.data.get("endless", {})
	var daily: Dictionary = SaveService.data.get("daily", {})
	var best: int = int(endless.get("best_goals", 0))
	var streak: int = int(daily.get("streak", 0))
	var played_today: bool = (daily.get("history", {}) as Dictionary).has(utc_date())

	menu.set_rows([
		{
			"id": "campaign", "label": "Campaign", "enabled": true,
			"value": "%d%%" % Campaign.completion_percent(),
		},
		{
			"id": "endless", "label": "Endless", "enabled": true,
			"value": "best %d" % best if best > 0 else "new",
		},
		{
			"id": "daily", "label": "Daily", "enabled": true,
			"value": "%s · %s" % [
				"streak %d" % streak if streak > 0 else ("done" if played_today else "new"),
				_hms(seconds_to_reset()),
			],
		},
		{"id": "settings", "label": "Settings", "enabled": true, "value": ""},
		{"id": "quit", "label": "Quit", "enabled": true, "value": ""},
	])

	title_label.text = "HEXFLOW"
	subtitle_label.text = "%d of %d levels · ★ %d" % [
		Campaign.completed_levels(), Campaign.TOTAL_LEVELS, Campaign.total_stars(),
	]
	footer_label.text = "%s select   %s choose" % [
		InputGlyphs.label_for("menu_down"), InputGlyphs.label_for("menu_accept"),
	]

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
@onready var brief: ModeBrief = %ModeBrief

var _palette: Palette = null
var _clock: Timer = null
## Which row opened the mode brief, so leaving it returns the focus there.
var _brief_row: String = "endless"


func _ready() -> void:
	InputBindings.activate(InputBindings.SET_MENU)
	_palette = Palette.current()
	menu.palette = _palette
	Backdrop.install(self)
	(%Background as ColorRect).color = Color(_palette.bg_deep, 0.0)
	Surface.apply_to(self, _palette)
	_apply_type_roles()

	menu.activated.connect(_on_activated)
	# §22: the language can change under a screen that is already drawn, so the
	# screen rewrites its own strings rather than being rebuilt — a rebuild would
	# lose the player's place in the menu they were standing in.
	EventBus.language_changed.connect(_refresh)
	menu.focus_moved.connect(func(_id: String) -> void: AudioDirector.play_sfx("ui.move"))

	brief.palette = _palette
	# After `Surface.apply_to`, which has just walked every panel on this screen
	# and given the card the standard one — a card of prose wants its own margins.
	brief.apply_style()
	brief.confirmed.connect(_start_mode)
	# Leaving the brief puts the focus back on the row it came from, so Back is a
	# true "up one level" (§12.5) rather than a press that loses the player's place
	# in the menu.
	brief.dismissed.connect(func() -> void: menu.focus_id(_brief_row))

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
	# The brand takes the type colour, not the path's. `path_core` is the colour of
	# the *line of light the player draws* — spending it on a word that is never
	# part of the puzzle both weakens it and, under C-26's warm palette, drops a
	# cold accent into a dusk scene.
	title_label.add_theme_color_override("font_color", _palette.text_primary)
	subtitle_label.theme_type_variation = Typography.variation_for(Typography.Role.CAPTION)
	subtitle_label.add_theme_color_override("font_color", _palette.text_secondary)
	footer_label.theme_type_variation = Typography.variation_for(Typography.Role.CAPTION)
	footer_label.add_theme_color_override("font_color", _palette.text_secondary)


func _unhandled_input(event: InputEvent) -> void:
	# The mode brief is a modal *inside* this screen, so it gets first refusal —
	# and it only answers while the `Modal` set is live, which is §11.1's rule
	# stated once more.
	if brief.handle_input(event):
		get_viewport().set_input_as_handled()
		return
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
		"endless", "daily":
			# Neither mode is explained anywhere else in the game, and both take
			# undo away (§5.9) — which a player finds out by pressing Z on a board
			# they cannot take back. Three lines and a Play button first.
			_brief_row = id
			brief.open(id)
		"settings":
			GameDirector.open_settings()
		"quit":
			# The run is written down first: §18.3's promise is that closing the
			# window costs no more than a suspend does.
			GameDirector.suspend()
			get_tree().quit()


## What pressing Play on the brief means. The brief starts nothing itself — it is
## a panel, and §12.1's rule that no screen pushes another screen directly is not
## suspended for a panel inside one.
func _start_mode(mode_id: String) -> void:
	match mode_id:
		"endless":
			# §7.2 is one escalating run and says nothing about repeating it, so the
			# run seed is the clock: two sessions are different runs, and the stage
			# seeds inside a run stay §19-deterministic off this one number (C-12).
			GameDirector.start_endless(int(Time.get_unix_time_from_system()))
			GameDirector.go_to(GameDirector.Screen.LEVEL)
		"daily":
			GameDirector.start_daily(utc_date())
			GameDirector.go_to(GameDirector.Screen.LEVEL)


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


## §7.3's "7-day streak indicator", drawn as seven marks with today on the right.
## A filled mark is a day played and a hollow one is a day missed, so the shape of
## the last week is readable at a glance — which a bare "streak 4" is not: it
## cannot tell you whether today is already done.
func _streak_pips() -> String:
	var out := ""
	for played: bool in SaveService.daily_streak_days(utc_date()):
		# Circles, not the small squares this used to draw. Those rendered correctly
		# once the faces fell back to one another — and still read as seven broken
		# glyphs, because a row of empty squares is what a missing character looks
		# like. A pip that has to be explained is a pip that has failed.
		out += "●" if played else "○"
	return out


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
			"id": "campaign", "label": tr("menu.campaign"), "enabled": true,
			"value": "%d%%" % Campaign.completion_percent(),
		},
		{
			"id": "endless", "label": tr("menu.endless"), "enabled": true,
			"value": tr("menu.best").format({"goals": best}) if best > 0 else tr("menu.new"),
		},
		{
			"id": "daily", "label": tr("menu.daily"), "enabled": true,
			"value": "%s %s · %s" % [
				_streak_pips(),
				tr("menu.streak").format({"days": streak}) if streak > 0 else
					(tr("menu.done_today") if played_today else tr("menu.new")),
				_hms(seconds_to_reset()),
			],
		},
		{"id": "settings", "label": tr("menu.settings"), "enabled": true, "value": ""},
		{"id": "quit", "label": tr("menu.quit"), "enabled": true, "value": ""},
	])

	# The brand is a name, not a word, so it is the one string on this screen with
	# no translation behind it (§22).
	title_label.text = "HEXFLOW"
	subtitle_label.text = tr("menu.subtitle").format({
		"done": Campaign.completed_levels(),
		"total": Campaign.TOTAL_LEVELS,
		"stars": Campaign.total_stars(),
	})
	footer_label.text = tr("menu.footer").format({
		"down": InputGlyphs.label_for("menu_down"),
		"accept": InputGlyphs.label_for("menu_accept"),
	})

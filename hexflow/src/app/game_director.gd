extends Node
## The single screen/mode state machine (§12.1). Owns the live [GameState].
##
## No screen may push another screen directly, and this file contains no rules —
## it forwards intents into [GameState] and republishes the resulting facts on
## [EventBus]. That boundary is the whole point of §16.2: the 2016 prototype
## fused rules into its screen class and became untestable (B4).

enum Screen { BOOT, MAIN_MENU, LEVEL_SELECT, LEVEL, PAUSED, RESULTS, RUN_SUMMARY, SETTINGS }
enum Mode { CAMPAIGN, ENDLESS, DAILY }

signal screen_changed(screen: Screen)

const SCENES := {
	Screen.BOOT: "res://src/scenes/boot/boot.tscn",
	Screen.MAIN_MENU: "res://src/scenes/main_menu/main_menu.tscn",
	Screen.LEVEL_SELECT: "res://src/scenes/level_select/level_select.tscn",
	Screen.LEVEL: "res://src/scenes/level/level.tscn",
	Screen.RESULTS: "res://src/scenes/results/results.tscn",
	Screen.RUN_SUMMARY: "res://src/scenes/run_summary/run_summary.tscn",
	Screen.SETTINGS: "res://src/scenes/settings/settings.tscn",
}

var screen: Screen = Screen.BOOT
var mode: Mode = Mode.CAMPAIGN
var state: GameState = null
var level: Level = null
var hints_used: int = 0

var _endless: EndlessRun = null


## Which §11.1 action set each screen runs under. A screen also claims its own set
## in `_ready`, so a directly-run scene is playable, but this is the map for
## screens that have no scene yet.
const ACTION_SETS := {
	Screen.BOOT: InputBindings.SET_MENU,
	Screen.MAIN_MENU: InputBindings.SET_MENU,
	Screen.LEVEL_SELECT: InputBindings.SET_MENU,
	Screen.LEVEL: InputBindings.SET_BOARD,
	Screen.PAUSED: InputBindings.SET_MODAL,
	Screen.RESULTS: InputBindings.SET_MENU,
	Screen.RUN_SUMMARY: InputBindings.SET_MENU,
	Screen.SETTINGS: InputBindings.SET_MENU,
}


func _ready() -> void:
	# Bindings are registered once, here, before any screen can ask about an
	# action (§11.3). Autoloads are ready before the main scene.
	InputBindings.install()
	# §13.4's five roles, installed once on the window so every screen inherits
	# them — including one run on its own from the editor or a test. §21's text
	# scale rebuilds it, which is why it is a call and not a `.tres`.
	apply_typography()
	SettingsService.changed.connect(_on_setting_changed)
	EventBus.place_requested.connect(_on_place_requested)
	EventBus.wild_place_requested.connect(_on_wild_place_requested)
	EventBus.discard_requested.connect(_on_discard_requested)
	EventBus.undo_requested.connect(_on_undo_requested)
	EventBus.restart_requested.connect(_on_restart_requested)


## Rebuilds §13.4's theme at the current §21 text scale and puts it on the window,
## which every screen inherits from.
func apply_typography() -> void:
	get_tree().root.theme = Typography.theme(float(SettingsService.get_value("text_scale")))


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "text_scale":
		apply_typography()


# --- screens -----------------------------------------------------------------

func go_to(next: Screen) -> void:
	screen = next
	if ACTION_SETS.has(next):
		InputBindings.activate(ACTION_SETS[next])
	screen_changed.emit(next)
	if SCENES.has(next) and ResourceLoader.exists(SCENES[next]):
		get_tree().change_scene_to_file(SCENES[next])


# --- level lifecycle ---------------------------------------------------------

func start_level(p_level: Level) -> void:
	mode = Mode.CAMPAIGN
	_endless = null
	_begin(p_level)


func start_endless(p_seed: int) -> void:
	mode = Mode.ENDLESS
	_endless = EndlessRun.new(p_seed)
	_begin(_endless.current_level())


func start_daily(utc_date: String) -> void:
	mode = Mode.DAILY
	_endless = null
	_begin(Generator.daily(utc_date))


func _begin(p_level: Level) -> void:
	level = p_level
	hints_used = 0
	state = GameState.start(level)
	EventBus.level_loaded.emit(level)
	EventBus.state_reset.emit(state)
	_publish(state.drain_events())


func undo_available() -> bool:
	# Undo is a campaign affordance only — leaderboard integrity (§5.9).
	return mode == Mode.CAMPAIGN and state != null and state.can_undo()


# --- intents -----------------------------------------------------------------

func _on_place_requested(target: Vector3i) -> void:
	if state == null:
		return
	if not state.place(target):
		EventBus.illegal_move_attempted.emit(target)
		return
	_publish(state.drain_events())


func _on_wild_place_requested(target: Vector3i) -> void:
	if state == null:
		return
	if not state.place_wild(target):
		EventBus.illegal_move_attempted.emit(target)
		return
	_publish(state.drain_events())


func _on_discard_requested() -> void:
	if state == null or not state.discard():
		return
	_publish(state.drain_events())


func _on_undo_requested() -> void:
	if not undo_available():
		return
	if state.undo():
		SaveService.data["stats"]["undos"] = int(SaveService.data["stats"]["undos"]) + 1
		_publish(state.drain_events())


func _on_restart_requested() -> void:
	if level == null:
		return
	_begin(level)


# --- fact publication --------------------------------------------------------

## Translates core events into view-facing signals. This is the only place the
## two vocabularies meet.
func _publish(events: Array) -> void:
	for e: Variant in events:
		var ev: Dictionary = e
		match str(ev["type"]):
			GameState.EV_PLACED:
				EventBus.cell_joined.emit(ev["target"], ev["anchor"], ev["dir"])
			GameState.EV_PORTAL:
				EventBus.portal_linked.emit(ev["from"], ev["to"])
			GameState.EV_GOAL_REACHED:
				EventBus.goal_reached.emit(ev["cell"])
			GameState.EV_WILD_GAINED, GameState.EV_WILD_SPENT:
				EventBus.wild_charges_changed.emit(state.wild_charges)
			GameState.EV_DISCARDED:
				EventBus.tile_discarded.emit(ev["dir"], ev["left"])
			GameState.EV_AUTO_SKIPPED:
				EventBus.tile_auto_skipped.emit(ev["dir"])
			GameState.EV_UNDONE:
				EventBus.move_undone.emit()
			GameState.EV_WON:
				_on_won(int(ev["placements"]))
			GameState.EV_DEAD:
				EventBus.level_dead.emit()

	if state != null:
		EventBus.tile_advanced.emit(state.current_tile(), state.preview(2))
		EventBus.legal_targets_changed.emit(state.legal_targets())
		_autosave()


func _on_won(placements: int) -> void:
	var stars := Scoring.stars(placements, level.par)
	EventBus.level_won.emit(placements, level.par, stars)
	match mode:
		Mode.CAMPAIGN:
			SaveService.record_completion(level.id, placements, stars, hints_used > 0)
			SteamService.unlock_achievement("first_flow")
		Mode.ENDLESS:
			if _endless != null:
				_endless.advance()
				_begin(_endless.current_level())
		Mode.DAILY:
			pass


## §18.1 — autosave on every commit, discard and undo. The payload is ~2 KB, so
## the frequency costs nothing and Deck suspend is always covered.
func _autosave() -> void:
	if state == null or mode != Mode.CAMPAIGN:
		return
	if state.status != GameState.Status.PLAYING:
		SaveService.set_in_progress(null)
		return
	var payload := state.to_dict()
	payload["mode"] = "campaign"
	payload["level_id"] = level.id
	SaveService.set_in_progress(payload)

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
var _transition: Tween = null
var _fade: ColorRect = null


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

## §14.1's screen transition: 320 ms, `CUBIC`/`EASE_IN_OUT`, cross-fade — and
## explicitly "never a hard cut". §14.5 shortens it to a flat 120 ms rather than a
## scaled 320, which is the number that section names itself.
##
## The fade is a `CanvasLayer` over everything, so it does not depend on either
## screen cooperating: the outgoing one does not have to fade itself out, and a
## screen that does not exist yet still gets a transition rather than a flash of
## the one behind it. The scene swap happens at full black, where nothing can be
## seen to pop.
func go_to(next: Screen) -> void:
	screen = next
	if ACTION_SETS.has(next):
		InputBindings.activate(ACTION_SETS[next])
	screen_changed.emit(next)
	if not (SCENES.has(next) and ResourceLoader.exists(SCENES[next])):
		return
	_transition_to(SCENES[next])


func _transition_to(scene_path: String) -> void:
	var half: float = Motion.seconds("screen_transition") * 0.5
	var fade := _fade_layer()
	if _transition != null and _transition.is_running():
		_transition.kill()
	_transition = create_tween()
	Motion.shape(_transition, "screen_transition")
	_transition.tween_property(fade, "color:a", 1.0, half)
	_transition.tween_callback(func() -> void: get_tree().change_scene_to_file(scene_path))
	_transition.tween_property(fade, "color:a", 0.0, half)


## Whether a transition is in flight, which is the only thing about it worth
## asking from outside.
func transitioning() -> bool:
	return _transition != null and _transition.is_running()


## One layer, built once, reused for every transition. It sits above every screen
## and ignores input, so a press during a fade reaches the screen underneath rather
## than being swallowed by a rectangle nobody can see (B7's lesson, in a new place).
func _fade_layer() -> ColorRect:
	if _fade != null:
		return _fade
	var layer := CanvasLayer.new()
	layer.name = "ScreenFade"
	layer.layer = 128
	add_child(layer)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(_palette().bg_deep, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)
	return _fade


func _palette() -> Palette:
	return load("res://src/data/palettes/neon_dark.tres")


# --- level lifecycle ---------------------------------------------------------

func start_level(p_level: Level) -> void:
	mode = Mode.CAMPAIGN
	_endless = null
	_begin(p_level)


## Opens a level, picking the run up where §18.2 left it when this is the level
## the save says is in progress, and starting it fresh otherwise.
##
## This is what stops the level select from undoing §18.1. Autosave writes the run
## on every move; the map opens on that very level ([method Campaign.last_played]);
## and if entering it called [method start_level], every one of those writes would
## be thrown away by the one press that was meant to honour them. Restarting is
## still one hold of `R` away, which is where §11.3 puts every destructive action.
func resume_or_start(p_level: Level) -> void:
	var payload: Variant = SaveService.data.get("in_progress")
	if payload is Dictionary \
			and str((payload as Dictionary).get("level_id", "")) == p_level.id \
			and resume_in_progress():
		return
	start_level(p_level)


## §18.2: picks up the campaign level the player was in the middle of, if there is
## one. Returns whether it resumed, so the caller can fall back rather than guess.
##
## Everything about the payload is treated as untrusted. It is written by an
## earlier version of the game, edited by hand, or truncated by a suspend that lost
## power — and none of those may leave the player at a black screen, so every step
## that can fail is checked and any failure clears the payload and returns false.
## §18's promise is that a bad save costs you your place, never your game.
func resume_in_progress() -> bool:
	var payload: Variant = SaveService.data.get("in_progress")
	if not (payload is Dictionary):
		return false
	var saved: Dictionary = payload
	if str(saved.get("mode", "")) != "campaign":
		return false
	var resumed: Level = LevelRepository.load_by_id(str(saved.get("level_id", "")))
	if resumed == null:
		push_warning("in-progress save names a level that does not exist; starting fresh")
		SaveService.set_in_progress(null)
		return false

	mode = Mode.CAMPAIGN
	_endless = null
	_begin(resumed)
	state.restore(saved)
	if state.status != GameState.Status.PLAYING:
		# A finished run has no business being resumed, and §18.1 should already
		# have cleared it — belt and braces, because the alternative is dropping the
		# player into a level that is already over.
		SaveService.set_in_progress(null)
		_begin(resumed)
		return false
	# The state changed under the view's feet, so it is republished rather than
	# left as `_begin` emitted it.
	EventBus.state_reset.emit(state)
	_publish(state.drain_events())
	return true


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


## §18.3: the moments the operating system tells us the player may not be coming
## back — focus lost, the app suspended, the window closing. A Deck goes to sleep
## mid-level far more often than a desktop does, and the process may simply never
## wake: the run has to be on disk before that, not after.
##
## §18.1's autosave already covers every *move*, so this is only the gap between
## the last move and the suspend. It costs one ~2 KB write at a moment when nothing
## is being rendered.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, \
		NOTIFICATION_WM_CLOSE_REQUEST:
			suspend()


## Writes the run down now. Public because §18.3 is a scenario worth being able to
## trigger in a test rather than only by taking focus away from a window.
func suspend() -> void:
	_autosave()
	SaveService.save_to_disk()


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

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
## Undos taken in *this* run, as against `stats.undos`, which is a lifetime total.
## §23.1's `undo_free` is a claim about consecutive levels and a lifetime counter
## cannot answer it.
var undos_used: int = 0
## Seconds-since-boot at the last [method bank_playtime]. See it for why §23.3
## makes this the one stat that has to be right.
var _playtime_marker: int = 0

## How long a finished board is held before the game moves on. Long
## enough to outlast §14.2's 700 ms goal sequence and C-30's route trace with room
## to look at the result, and short enough that a player who does nothing is not
## waiting on the game.
const STAGE_PAUSE_SECONDS := 5.0

## What the run that just finished was worth. Kept here rather than read off the
## live state, because the Results screen is a scene of its own: by the time it is
## looking, a Replay or the next endless stage may already have reset `state` under
## it, and a results card that reports the run *after* the one it is celebrating is
## worse than no card at all.
var last_result: Dictionary = {}

var _endless: EndlessRun = null
var _daily_date: String = ""
var _settings_return: Screen = Screen.MAIN_MENU
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
	# §12.5: opening the Steam overlay pauses gameplay. Closing it deliberately
	# does *not* unpause — the player was taken out of the game by something that
	# was not the game, and putting them straight back on a live board is how a
	# move gets made by somebody who was reading a chat message.
	SteamService.overlay_toggled.connect(func(active: bool) -> void:
		if active:
			pause())
	EventBus.place_requested.connect(_on_place_requested)
	EventBus.wild_place_requested.connect(_on_wild_place_requested)
	EventBus.discard_requested.connect(_on_discard_requested)
	EventBus.undo_requested.connect(_on_undo_requested)
	EventBus.restart_requested.connect(_on_restart_requested)
	# §15.1's beds follow the screen, and the screen is this file's business. A
	# level takes its chapter's bed; everything else takes the menu track — endless
	# and the daily included, since neither belongs to a chapter.
	screen_changed.connect(_on_screen_music)


func _on_screen_music(next: Screen) -> void:
	if next == Screen.LEVEL and mode == Mode.CAMPAIGN and level != null:
		var at: Vector2i = LevelRepository.locate(level.id)
		if at.x > 0:
			AudioDirector.play_music("chapter_%d" % at.x)
			return
	AudioDirector.play_music(AudioDirector.MUSIC_MENU)


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


## §12.5's pause — the one screen change that deliberately does *not* swap scenes.
##
## [constant SCENES] has no `PAUSED` entry on purpose: §12.2 puts the pause menu
## over a board that is still there, and reloading `level.tscn` to come back would
## rebuild the whole board, drop every animation in flight and cost a 320 ms fade
## in each direction for a menu the player expects to be instant. So pausing is a
## claim on the `Modal` action set (§11.1) and nothing more — the level screen
## stops acting on input the moment the set is not its own, which is the mechanism
## §11.1 was built around.
##
## Pausing needs a run to pause and needs not to be paused already. It is
## deliberately *not* conditioned on `screen == LEVEL`: a level scene run on its
## own — editor F6, the capture tool, an `@e2e` test — has never navigated
## anywhere, and a pause menu that only works if you arrived through the main menu
## is a pause menu nobody can test.
func pause() -> void:
	if state == null or screen == Screen.PAUSED:
		return
	go_to(Screen.PAUSED)


## Leaving the pause menu is a *return*, not a navigation, for the same reason.
func resume() -> void:
	if screen != Screen.PAUSED:
		return
	screen = Screen.LEVEL
	InputBindings.activate(ACTION_SETS[Screen.LEVEL])
	screen_changed.emit(Screen.LEVEL)


## Settings has two parents — §12.1 opens it from the main menu, §12.2 from the
## pause menu — and §12.5 says Back goes up exactly *one* level. One level from
## where, then, is not derivable from the state of the game: a player who has
## quit to the menu still has a `state` hanging around, and guessing from that
## would send them back onto a board they had left. So the door is remembered.
##
## Pause resolves to `LEVEL` rather than `PAUSED` on the way back, because
## returning through Settings has already been a scene change: there is nothing
## left to be modal over.
func open_settings() -> void:
	_settings_return = Screen.LEVEL if screen == Screen.PAUSED else screen
	go_to(Screen.SETTINGS)


func close_settings() -> void:
	go_to(_settings_return)


## Where "Quit to map" goes (§12.2). A campaign level came from the map; an
## endless run and a daily did not — §12.1 draws both straight off the main menu,
## so that is where leaving one returns to.
func level_exit_screen() -> Screen:
	return Screen.LEVEL_SELECT if mode == Mode.CAMPAIGN else Screen.MAIN_MENU


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
	return Palette.current()


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


## §7.2's score, live. Zero outside Endless.
func endless_goals() -> int:
	return _endless.goals_reached if _endless != null else 0


## §7.2's tie-break, live: the stages already banked plus the one being played. The
## sum lives here rather than at each place that wants it, because the two halves
## are held by different objects and adding them up in two places is how one of
## them came to be left out.
func endless_placements() -> int:
	if _endless == null:
		return 0
	if state == null:
		return _endless.total_placements
	# A *won* stage has already been handed to `advance()`, so adding the live
	# count again would double it — which it did, for as long as C-35's stage pause
	# lasts, because the board that finished now stays on screen instead of being
	# replaced on the same frame. A dead stage was never banked (`advance` only
	# runs on a win), so its placements still have to be added, and that is the
	# case the run summary reports.
	return _endless.total_placements \
		+ (0 if state.status == GameState.Status.WON else state.placements)


func start_daily(utc_date: String) -> void:
	var daily: Level = Generator.daily(utc_date)
	if daily == null:
		# §7.3 verifies solvability at generation time on the client, so this is the
		# day the verification failed. Better a warning and no navigation than a
		# black screen behind a fade.
		push_warning("the daily puzzle for %s could not be generated" % utc_date)
		return
	mode = Mode.DAILY
	_endless = null
	_daily_date = utc_date
	_begin(daily)


## The UTC date of the daily run in play. Kept so a Replay re-opens *today's*
## board: §7.3 allows unlimited retries, and a retry on a different board is not a
## retry — the whole point of the mode is that everyone is solving the same one.
func daily_date() -> String:
	return _daily_date


func _begin(p_level: Level) -> void:
	level = p_level
	hints_used = 0
	undos_used = 0
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
		undos_used += 1
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
				# Declared in the schema since M0 and incremented by nothing. It
				# counts placements the player *made*, so it rises on a commit and
				# is deliberately not decremented by an undo — `stats.undos` is
				# the record of those, and a lifetime total that can go backwards
				# is not a lifetime total.
				var stats: Dictionary = SaveService.data.get("stats", {})
				stats["total_placements"] = int(stats.get("total_placements", 0)) + 1
				EventBus.cell_joined.emit(ev["target"], ev["anchor"], ev["dir"])
			GameState.EV_PORTAL:
				EventBus.portal_linked.emit(ev["from"], ev["to"])
			GameState.EV_GOAL_REACHED:
				EventBus.goal_reached.emit(ev["cell"])
			GameState.EV_GATE_OPENED:
				EventBus.gate_opened.emit(ev["cell"])
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
				EventBus.level_dead.emit(int(ev.get("reason", GameState.Dead.NONE)))
				_on_dead()

	if state != null:
		EventBus.tile_advanced.emit(state.current_tile(), state.preview(2))
		EventBus.legal_targets_changed.emit(state.legal_targets())
		_autosave()


func _on_won(placements: int) -> void:
	var stars := Scoring.stars(placements, level.par)
	var at: Vector2i = LevelRepository.locate(level.id)
	last_result = {
		"mode": mode,
		"level_id": level.id,
		# The date on its own, because the results card wants to name the day and
		# the id is `daily_2026-07-31` — a prefix the player never needs to read.
		"daily_date": _daily_date,
		"chapter": at.x,
		"index": at.y,
		"placements": placements,
		"par": level.par,
		"stars": stars,
		"hinted": hints_used > 0,
	}
	EventBus.level_won.emit(placements, level.par, stars)
	match mode:
		Mode.CAMPAIGN:
			SaveService.record_completion(level.progress_key(), placements, stars, hints_used > 0)
			# The save is written first, because §23.1's chapter conditions are
			# claims about all twelve levels and this is one of them. Reading them
			# before the completion is recorded asks the question one level early.
			bank_playtime()
			Achievements.record_undo_use(undos_used > 0)
			_unlock(Achievements.for_campaign_completion(
				at.x, placements, level.par, _discards_used(), undos_used > 0))
			_show_results()
		Mode.ENDLESS:
			# §7.2 has no results card between stages: reaching a goal *is* the next
			# stage, and the run only ends on a dead board (§12.1, Endless →
			# RunSummary). But "is the next stage" was taken literally and the board
			# was rebuilt on the same frame the goal was reached — so §14.2's
			# flourish, burst, ripple and the C-30 route trace all played over a
			# board that had already been replaced, and the player never saw the
			# thing they had just done. The campaign gets a results card for exactly
			# this reason; a run needs the beat even without the card.
			if _endless != null:
				# The stage's own placements have to be handed over *before*
				# `_begin` replaces the state that holds them, or §7.2's tie-break
				# only ever counts the stage the run died on.
				_endless.advance(placements)
				await _stage_pause()
				# The run may have been left during the pause — quit to menu, or a
				# restart — and coming back to lay out the next stage of a run
				# nobody is playing would drop a board under whatever screen won.
				if mode == Mode.ENDLESS and _endless != null:
					_begin(_endless.current_level())
		Mode.DAILY:
			# §12.1: Daily → Results : WON. Not recorded against the campaign —
			# §7.3's puzzle is not a campaign level and has no slot there — but it is
			# what feeds the seven-day streak the main menu shows.
			SaveService.record_daily(_daily_date, placements, stars)
			SteamService.submit_leaderboard("daily_" + _daily_date, placements)
			_unlock(Achievements.for_daily())
			_show_results()


## §12.1: `Endless → RunSummary : DEAD`. A dead board only ends anything in
## endless — §5.8 makes it a recoverable banner everywhere else, and the campaign
## and the daily both have a way back out of it. §7.2's run has no undo, so this
## is where it stops.
## Holds on a finished board until the player says go, or [constant
## STAGE_PAUSE_SECONDS] passes. Used by both modes, for the same reason with two
## different things arriving afterwards: the next stage in a run, the results card
## in the campaign.
##
## Both, rather than either: a fixed wait makes a player who is ready sit still,
## and waiting only for input strands one who has put the Deck down mid-run — and
## §7.2's escalation means the next board is already decided, so there is nothing
## to decide and nothing that should block on a decision.
func _stage_pause() -> void:
	var timer := get_tree().create_timer(STAGE_PAUSE_SECONDS)
	var carry_on := [false]
	var on_advance := func() -> void: carry_on[0] = true
	EventBus.advance_requested.connect(on_advance)
	while not carry_on[0] and timer.time_left > 0.0:
		await get_tree().process_frame
	EventBus.advance_requested.disconnect(on_advance)


## §5.7's free auto-discard is not a choice and must not cost the player §23.1's
## `no_discard`, so this counts the charges actually spent rather than the tiles
## that went past.
func _discards_used() -> int:
	if level == null or state == null:
		return 0
	return maxi(0, level.discards - state.discards_left)


## Unlocks each of [param names]. [method SteamService.unlock_achievement] is
## idempotent, so re-earning one on a replay costs nothing and the conditions above
## never have to remember what they have already awarded.
func _unlock(names: Array[String]) -> void:
	for api_name: String in names:
		SteamService.unlock_achievement(api_name)


func _on_dead() -> void:
	if mode != Mode.ENDLESS or _endless == null:
		return
	var goals: int = endless_goals()
	var placements: int = endless_placements()
	last_result = {
		"mode": mode,
		"goals": goals,
		"placements": placements,
		"best": SaveService.record_endless_run(goals, placements),
	}
	# §7.2 posts the run whether or not anyone is listening; §23's Steam-absent
	# path makes a submission with no client a no-op rather than an error.
	SteamService.submit_leaderboard("endless_best_goals", goals, [placements])
	_unlock(Achievements.for_endless_run(goals))
	await get_tree().create_timer(Motion.seconds("dead_desaturate")).timeout
	if state != null and state.status == GameState.Status.DEAD:
		go_to(Screen.RUN_SUMMARY)


## §14.2 puts the Results card at t=700, after the goal flourish, the burst, the
## ripple and the flow pulse have all had their turn. Sending the player away at
## t=0 would cut off the only celebration the game has.
##
## It waits longer than that now. C-28 draws the route as the reward for finishing
## and takes the same 700 ms to do it, so a card on §14.2's beat arrived on the
## frame the last bar landed — the line was drawn and gone in one motion. [Motion]
## owns the arithmetic; §14.2's beat is the floor rather than the answer.
func _show_results() -> void:
	# §14.2's beats and C-30's trace first: this is the minimum, and it is the part
	# the player has not been asked about.
	await get_tree().create_timer(Motion.results_delay_seconds()).timeout
	# Then the board is *theirs to look at* (C-35). The card used to arrive on the
	# 1600 ms tick and take the finished board away with it, which is the one moment
	# the player has any reason to look at the line they just drew — the whole
	# reason C-30 draws it and C-31 lights it. It waits for them now.
	await _stage_pause()
	# The player may have restarted or left while that was running; a results card
	# for a run they walked away from would be a screen arriving out of nowhere.
	if state != null and state.status == GameState.Status.WON:
		go_to(Screen.RESULTS)


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
	bank_playtime()
	_autosave()
	SaveService.save_to_disk()


## Moves the time since the last banking into `stats.playtime_seconds`.
##
## §23.3 makes this load-bearing rather than decorative: Steam Auto-Cloud resolves
## a conflict between two machines' saves by "newest `stats.playtime_seconds`
## wins", and the field had been declared in the schema since M0 and written by
## nothing. A tie-break that is always 0 against 0 does not pick the newer save,
## it picks whichever one the comparison happens to see first — so a player with a
## Deck and a desktop would lose progress at random, and only after release.
##
## Wall clock rather than a per-level timer, because §23.3 wants "which of these
## two saves has more of the player's life in it", not a score. Banked at each
## suspend and at each completion rather than ticked per frame (C4).
func bank_playtime() -> void:
	var now: int = int(Time.get_ticks_msec() / 1000)
	var stats: Dictionary = SaveService.data.get("stats", {})
	stats["playtime_seconds"] = int(stats.get("playtime_seconds", 0)) \
		+ maxi(0, now - _playtime_marker)
	_playtime_marker = now


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

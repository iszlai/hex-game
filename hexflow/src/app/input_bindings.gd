## Every binding of §11.3 and the three action sets of §11.1, as one table.
##
## Actions are registered into `InputMap` at runtime rather than frozen into
## `project.godot`, for three reasons: the table below stays the readable
## authority instead of a wall of serialised `Object(InputEventKey, …)`; a test
## can assert every §11.3 row is bound on **both** the keyboard and the gamepad
## column, which is the M4 exit criterion; and the `custom_bindings` rebinding of
## §17.3 has somewhere to write when M5 needs it.
##
## Because the whole binding lives here, a screen never tests a keycode. It asks
## `event.is_action_pressed("board_confirm")` and the same code serves keyboard,
## gamepad and — through the same actions — a remapped controller.
##
## Deliberately not an autoload: §16.5 fixes the singleton list at six.
## [method install] is called once, by [GameDirector].
class_name InputBindings

## §11.1. Godot has no native notion of an action set, so a set is enforced by
## the screen that owns it: each screen claims its set in `_ready` and ignores
## input belonging to another. Steam Input's own sets are configured to match at
## M9, when GodotSteam links.
const SET_MENU := "Menu"
const SET_BOARD := "Board"
const SET_MODAL := "Modal"

## Axis actions need a deadzone. 0.5 keeps a resting stick from creeping the
## cursor and stops a light touch on an analogue trigger from starting a hold.
const DEADZONE := 0.5

## Seconds of hold for the two gestures §11.3 specifies as holds. Restart is
## destructive, so it is a hold on *every* device, keyboard included — "nothing
## destructive on a single press" is not a gamepad-only rule.
const HOLD_RESTART := 1.0
const HOLD_HINT := 0.5

## The §11.3 table. Per action:
##   set      which §11.1 action set the action belongs to
##   keys     `Key` codes
##   buttons  `JoyButton` indices
##   axes     `[JoyAxis, sign]` pairs; sign selects the half of the axis
##   hold     seconds the input must be held before it fires (absent = instant)
##   glyph    slot name resolved per controller family by [InputGlyphs] (§11.4)
##
## `board_pause` and `board_back` deliberately share Esc: from gameplay both go
## up exactly one level (§12.5), and the screen resolves pause first.
##
## `board_legend` and `board_restart` deliberately share Select: a tap toggles
## the legend, a 1 s hold restarts, exactly as §11.3 tabulates it.
const ACTIONS := {
	"board_move_up": {
		"set": SET_BOARD,
		"keys": [KEY_UP, KEY_W],
		"buttons": [JOY_BUTTON_DPAD_UP],
		"axes": [[JOY_AXIS_LEFT_Y, -1]],
		"glyph": "stick",
	},
	"board_move_down": {
		"set": SET_BOARD,
		"keys": [KEY_DOWN, KEY_S],
		"buttons": [JOY_BUTTON_DPAD_DOWN],
		"axes": [[JOY_AXIS_LEFT_Y, 1]],
		"glyph": "stick",
	},
	"board_move_left": {
		"set": SET_BOARD,
		"keys": [KEY_LEFT, KEY_A],
		"buttons": [JOY_BUTTON_DPAD_LEFT],
		"axes": [[JOY_AXIS_LEFT_X, -1]],
		"glyph": "stick",
	},
	# `D` is move-right, not discard: §11.3 wants full WASD *and* `D` for discard,
	# which collide. Discard moved to `X`, matching its gamepad button (C-20).
	"board_move_right": {
		"set": SET_BOARD,
		"keys": [KEY_RIGHT, KEY_D],
		"buttons": [JOY_BUTTON_DPAD_RIGHT],
		"axes": [[JOY_AXIS_LEFT_X, 1]],
		"glyph": "stick",
	},
	"board_cycle_prev": {
		"set": SET_BOARD,
		"keys": [KEY_Q],
		"buttons": [JOY_BUTTON_LEFT_SHOULDER],
		"axes": [],
		"glyph": "l1",
	},
	"board_cycle_next": {
		"set": SET_BOARD,
		"keys": [KEY_E],
		"buttons": [JOY_BUTTON_RIGHT_SHOULDER],
		"axes": [],
		"glyph": "r1",
	},
	# Turns the C-18 board between its six 60° stops (§14.3 as amended).
	"board_rotate_ccw": {
		"set": SET_BOARD,
		"keys": [KEY_BRACKETLEFT],
		"buttons": [],
		"axes": [[JOY_AXIS_RIGHT_X, -1]],
		"glyph": "rstick",
	},
	"board_rotate_cw": {
		"set": SET_BOARD,
		"keys": [KEY_BRACKETRIGHT],
		"buttons": [],
		"axes": [[JOY_AXIS_RIGHT_X, 1]],
		"glyph": "rstick",
	},
	"board_confirm": {
		"set": SET_BOARD,
		"keys": [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER],
		"buttons": [JOY_BUTTON_A],
		"axes": [],
		"glyph": "a",
	},
	"board_undo": {
		"set": SET_BOARD,
		"keys": [KEY_Z, KEY_BACKSPACE],
		"buttons": [JOY_BUTTON_Y],
		"axes": [],
		"glyph": "y",
	},
	"board_discard": {
		"set": SET_BOARD,
		"keys": [KEY_X],
		"buttons": [JOY_BUTTON_X],
		"axes": [],
		"glyph": "x",
	},
	## Held while confirming to spend a wild charge: `L2 + A`, `Shift + Space`.
	"board_wild_modifier": {
		"set": SET_BOARD,
		"keys": [KEY_SHIFT],
		"buttons": [],
		"axes": [[JOY_AXIS_TRIGGER_LEFT, 1]],
		"glyph": "l2",
	},
	"board_hint": {
		"set": SET_BOARD,
		"keys": [KEY_H],
		"buttons": [],
		"axes": [[JOY_AXIS_TRIGGER_RIGHT, 1]],
		"hold": HOLD_HINT,
		"glyph": "r2",
	},
	"board_legend": {
		"set": SET_BOARD,
		"keys": [KEY_TAB],
		"buttons": [JOY_BUTTON_BACK],
		"axes": [],
		"glyph": "select",
	},
	"board_restart": {
		"set": SET_BOARD,
		"keys": [KEY_R],
		"buttons": [JOY_BUTTON_BACK],
		"axes": [],
		"hold": HOLD_RESTART,
		"glyph": "select",
	},
	"board_pause": {
		"set": SET_BOARD,
		"keys": [KEY_ESCAPE],
		"buttons": [JOY_BUTTON_START],
		"axes": [],
		"glyph": "start",
	},
	"board_back": {
		"set": SET_BOARD,
		"keys": [KEY_ESCAPE],
		"buttons": [JOY_BUTTON_B],
		"axes": [],
		"glyph": "b",
	},

	# --- Menu (§11.1): boot, main menu, level select, settings, results --------
	"menu_up": {
		"set": SET_MENU,
		"keys": [KEY_UP, KEY_W],
		"buttons": [JOY_BUTTON_DPAD_UP],
		"axes": [[JOY_AXIS_LEFT_Y, -1]],
		"glyph": "stick",
	},
	"menu_down": {
		"set": SET_MENU,
		"keys": [KEY_DOWN, KEY_S],
		"buttons": [JOY_BUTTON_DPAD_DOWN],
		"axes": [[JOY_AXIS_LEFT_Y, 1]],
		"glyph": "stick",
	},
	"menu_left": {
		"set": SET_MENU,
		"keys": [KEY_LEFT, KEY_A],
		"buttons": [JOY_BUTTON_DPAD_LEFT],
		"axes": [[JOY_AXIS_LEFT_X, -1]],
		"glyph": "stick",
	},
	"menu_right": {
		"set": SET_MENU,
		"keys": [KEY_RIGHT, KEY_D],
		"buttons": [JOY_BUTTON_DPAD_RIGHT],
		"axes": [[JOY_AXIS_LEFT_X, 1]],
		"glyph": "stick",
	},
	# Pages a menu between sibling collections — the level select's five chapters
	# are the first. The bumpers rather than `menu_left`/`menu_right`, because on
	# the hex-flower map those four already drive §11.2's cone over the twelve
	# levels; the board spends L1/R1 the same way, on "step to the next thing at
	# this level of the hierarchy".
	"menu_cycle_prev": {
		"set": SET_MENU,
		"keys": [KEY_Q],
		"buttons": [JOY_BUTTON_LEFT_SHOULDER],
		"axes": [],
		"glyph": "l1",
	},
	"menu_cycle_next": {
		"set": SET_MENU,
		"keys": [KEY_E],
		"buttons": [JOY_BUTTON_RIGHT_SHOULDER],
		"axes": [],
		"glyph": "r1",
	},
	"menu_accept": {
		"set": SET_MENU,
		"keys": [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER],
		"buttons": [JOY_BUTTON_A],
		"axes": [],
		"glyph": "a",
	},
	"menu_back": {
		"set": SET_MENU,
		"keys": [KEY_ESCAPE],
		"buttons": [JOY_BUTTON_B],
		"axes": [],
		"glyph": "b",
	},

	# --- Modal (§11.1): pause, confirmations, tutorial gate -------------------
	# A modal that holds a list needs to be able to move through it. §11.3 does not
	# tabulate these because it tabulates the *board*, but §12.5's "exactly one
	# focused element at all times in `Menu`/`Modal` sets" is unreachable in a set
	# with no way to change which one.
	"modal_up": {
		"set": SET_MODAL,
		"keys": [KEY_UP, KEY_W],
		"buttons": [JOY_BUTTON_DPAD_UP],
		"axes": [[JOY_AXIS_LEFT_Y, -1]],
		"glyph": "stick",
	},
	"modal_down": {
		"set": SET_MODAL,
		"keys": [KEY_DOWN, KEY_S],
		"buttons": [JOY_BUTTON_DPAD_DOWN],
		"axes": [[JOY_AXIS_LEFT_Y, 1]],
		"glyph": "stick",
	},
	"modal_accept": {
		"set": SET_MODAL,
		"keys": [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER],
		"buttons": [JOY_BUTTON_A],
		"axes": [],
		"glyph": "a",
	},
	"modal_back": {
		"set": SET_MODAL,
		"keys": [KEY_ESCAPE],
		"buttons": [JOY_BUTTON_B],
		"axes": [],
		"glyph": "b",
	},
}

## The set whose input is currently live. Claimed by the screen that owns it.
static var active_set: String = SET_MENU


## Registers the whole table into `InputMap`, replacing anything already there so
## a second call — a test, or a rebind — is idempotent.
##
## §21 asks for "every action rebindable per device", and a rebind is a *layer*
## rather than an edit: `settings.custom_bindings` overrides the table's keys or
## buttons for one action, the table itself is never rewritten, and clearing the
## override is what makes "a reset-to-default is always one press away" true by
## construction rather than by remembering what the default was.
static func install() -> void:
	var custom: Dictionary = SettingsService.get_value("custom_bindings") as Dictionary
	for action: String in ACTIONS:
		var spec: Dictionary = ACTIONS[action]
		# `custom_bindings` is a JSON file a player can edit and an older build can
		# have written, so an entry that is not a dictionary is ignored rather than
		# cast — §18's promise about saves applies to settings for the same reason.
		var raw: Variant = custom.get(action, {})
		var override: Dictionary = raw if raw is Dictionary else {}
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, DEADZONE)

		for code: int in (override.get("keys", spec["keys"]) as Array):
			var key := InputEventKey.new()
			key.keycode = code as Key
			InputMap.action_add_event(action, key)

		for index: int in (override.get("buttons", spec["buttons"]) as Array):
			var button := InputEventJoypadButton.new()
			button.button_index = index as JoyButton
			InputMap.action_add_event(action, button)

		for entry: Variant in (spec["axes"] as Array):
			var pair: Array = entry
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(pair[0]) as JoyAxis
			motion.axis_value = float(pair[1])
			InputMap.action_add_event(action, motion)


## Claims [param set_name] as the live set. Called by a screen in `_ready`.
static func activate(set_name: String) -> void:
	active_set = set_name


## Whether [param action] belongs to the live set. A screen checks this before
## acting, so a modal over the board cannot be played through (§11.1).
static func is_active(action: String) -> bool:
	var spec: Dictionary = ACTIONS.get(action, {})
	return spec.get("set", "") == active_set


## Seconds this action must be held, or 0.0 if it fires on press.
static func hold_seconds(action: String) -> float:
	return float((ACTIONS.get(action, {}) as Dictionary).get("hold", 0.0))


static func is_hold(action: String) -> bool:
	return hold_seconds(action) > 0.0


## The glyph slot ("a", "l2", "select" …) this action occupies on a controller.
static func glyph_slot(action: String) -> String:
	return str((ACTIONS.get(action, {}) as Dictionary).get("glyph", ""))


## The keys bound to an action *right now* — the player's override if there is
## one, the §11.3 table otherwise. The first is the one shown in the HUD when no
## controller is connected, so a rebind shows up in the rail without the rail
## knowing rebinding exists.
static func keys_of(action: String) -> Array[int]:
	var out: Array[int] = []
	for code: int in (live_spec(action).get("keys", []) as Array):
		out.append(code)
	return out


## The buttons bound to an action right now, on the same terms.
static func buttons_of(action: String) -> Array[int]:
	var out: Array[int] = []
	for index: int in (live_spec(action).get("buttons", []) as Array):
		out.append(index)
	return out


## An action's live binding: the §11.3 row with the player's override laid over
## it. Everything that asks "what is this bound to" goes through here, so a rebind
## cannot be visible in one place and invisible in another.
static func live_spec(action: String) -> Dictionary:
	var spec: Dictionary = (ACTIONS.get(action, {}) as Dictionary).duplicate()
	if spec.is_empty():
		return spec
	var custom: Dictionary = SettingsService.get_value("custom_bindings") as Dictionary
	var raw: Variant = custom.get(action, {})
	spec.merge(raw if raw is Dictionary else {}, true)
	return spec


## Rebinds one device column of one action and installs it (§21, §17.3).
##
## Rejected when the input is already spoken for *in the same action set* by a
## different action: §11.3 shares Esc and Select on purpose, but a collision the
## player creates by accident is a control they will find unresponsive later with
## no way to know why. Cross-set collisions are fine and deliberate — the whole
## point of §11.1 is that Space can mean two things in two places.
##
## Returns the action it collided with, or "" on success.
static func rebind(action: String, keys: Array[int], buttons: Array[int]) -> String:
	if not ACTIONS.has(action):
		return action
	var set_name: String = str((ACTIONS[action] as Dictionary)["set"])
	for other: String in actions_in(set_name):
		if other == action:
			continue
		for code: int in keys:
			if keys_of(other).has(code):
				return other
		for index: int in buttons:
			if buttons_of(other).has(index):
				return other

	var custom: Dictionary = (SettingsService.get_value("custom_bindings") as Dictionary).duplicate(true)
	custom[action] = {"keys": keys, "buttons": buttons}
	SettingsService.set_value("custom_bindings", custom)
	install()
	return ""


## Drops one action's override, or every override when [param action] is empty.
## §21: "a reset-to-default is always one press away", and the default is whatever
## the §11.3 table says — never a copy of it kept somewhere else.
static func reset_binding(action: String = "") -> void:
	if action == "":
		SettingsService.set_value("custom_bindings", {})
		install()
		return
	var custom: Dictionary = (SettingsService.get_value("custom_bindings") as Dictionary).duplicate(true)
	custom.erase(action)
	SettingsService.set_value("custom_bindings", custom)
	install()


static func actions_in(set_name: String) -> Array[String]:
	var out: Array[String] = []
	for action: String in ACTIONS:
		if (ACTIONS[action] as Dictionary)["set"] == set_name:
			out.append(action)
	return out

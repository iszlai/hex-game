## §10's tutorial, as data and a state machine over it.
##
## §10 opens by insisting the beats are **data**, "never hardcoded in level
## scripts", and the reason is visible the moment you look at §10.2: twelve beats
## spread over five chapters, each with its own trigger, its own completion
## condition and its own twelve words. Written as code that is twelve `if` blocks
## in a screen that already has enough to do; written as data it is a table
## somebody can read against the spec — which is the same argument Appendix A's
## directions and §14.1's timings already won.
##
## This file holds no strings and no timings of its own. It decides *which* beat is
## live, and the level screen decides what a live beat looks like.
##
## Deliberately not an autoload (§16.5 fixes the list at six) and deliberately not
## in `src/core/` — a beat is a fact about a player's history, and the core is
## ignorant of whether a level has ever been played, exactly as [Campaign] is.
class_name Tutorial
extends RefCounted

const PATH := "res://src/data/tutorial.json"
const SCHEMA := 1

## §10.1: "Never more than 12 words on screen at once."
const MAX_WORDS := 12

## What starts a beat. Each is a fact the level screen already has.
const TRIGGERS: Array[String] = [
	"level_start",       # the first frame of its level
	"after_place",       # any placement has just been committed
	"branch_available",  # two legal targets that are not neighbours of each other
	"auto_skipped",      # §5.7's free skip has just happened
	"wall_targeted",     # the cursor has been aimed into a wall
	"gate_visible",      # the level contains a gate
	"portal_visible",    # the level contains a portal pair
	"wild_gained",       # a charge has just been picked up
]

## What ends one. Every beat also carries `seconds`; where the completion is an
## action, that is a *fallback* so a player who never performs it is not left
## reading the same twelve words for the rest of the level.
const COMPLETIONS: Array[String] = ["place", "undo", "discard", "time"]

static var _beats: Array = []


## The beat table, loaded once. Returns an empty list rather than failing if the
## file is missing or from a newer build: a tutorial that will not load costs the
## player their guidance, and §18's rule is that it must never cost them the game.
static func beats() -> Array:
	if not _beats.is_empty():
		return _beats
	if not FileAccess.file_exists(PATH):
		push_warning("tutorial data missing; the game plays without guidance")
		return []
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(PATH)) != OK or not (json.data is Dictionary):
		push_warning("tutorial data is unreadable; the game plays without guidance")
		return []
	var data: Dictionary = json.data
	if int(data.get("schema", 0)) > SCHEMA:
		push_warning("tutorial data is newer than this build understands")
		return []
	_beats = data.get("beats", []) as Array
	return _beats


static func clear_cache() -> void:
	_beats = []


static func beat(id: String) -> Dictionary:
	for entry: Variant in beats():
		if str((entry as Dictionary).get("id", "")) == id:
			return entry
	return {}


## The beats belonging to [param level_id], in table order. Order matters: T1 gates
## input and T2 follows it, so a screen must not be free to run them the other way
## round.
static func for_level(level_id: String) -> Array:
	var out: Array = []
	for entry: Variant in beats():
		if str((entry as Dictionary).get("level", "")) == level_id:
			out.append(entry)
	return out


# --- what the player has already been shown -----------------------------------

## §10: "Each beat writes a boolean into `save.tutorial_flags` so it never
## repeats." Read through here so the shape of that dictionary is known in one
## place, and so a save with no `tutorial_flags` at all behaves as a fresh one.
static func seen(id: String) -> bool:
	return bool(_flags().get(id, false))


static func mark_seen(id: String) -> void:
	var flags: Dictionary = _flags()
	if bool(flags.get(id, false)):
		return
	flags[id] = true
	SaveService.save_to_disk()


## §10.1: "Skippable at any time with a single Back press; skipping sets all flags
## seen." All of them, not the rest of this level's — a player who skips the
## tutorial has said something about the whole tutorial.
static func skip_all() -> void:
	var flags: Dictionary = _flags()
	for entry: Variant in beats():
		flags[str((entry as Dictionary).get("id", ""))] = true
	SaveService.save_to_disk()


## §10.1's "Replay tutorial", which "resets the tutorial flags **only**" — the
## emphasis is the spec's own, and it is why this clears one key rather than
## reaching for anything that looks like a fresh start.
static func reset() -> void:
	SaveService.data["tutorial_flags"] = {}
	SaveService.save_to_disk()


static func complete() -> bool:
	for entry: Variant in beats():
		if not seen(str((entry as Dictionary).get("id", ""))):
			return false
	return true


static func _flags() -> Dictionary:
	var current: Variant = SaveService.data.get("tutorial_flags")
	if not (current is Dictionary):
		SaveService.data["tutorial_flags"] = {}
	return SaveService.data["tutorial_flags"]


# --- the live beat -------------------------------------------------------------

## The beat this level should start on [param trigger], or an empty dictionary.
## A beat already seen never returns, which is what makes the whole thing
## once-only without any screen remembering anything.
static func next_for(level_id: String, trigger: String) -> Dictionary:
	for entry: Variant in for_level(level_id):
		var spec: Dictionary = entry
		if str(spec.get("trigger", "")) != trigger:
			continue
		if seen(str(spec.get("id", ""))):
			continue
		# In table order, and one at a time: §10.1 allows twelve words on screen,
		# not two beats' worth.
		return spec
	return {}


## §10.2's T1 is the only beat that gates input — "Beat 1 gates input to the single
## correct cell; every later beat merely highlights and lets the player ignore it".
static func gates(spec: Dictionary) -> bool:
	return bool(spec.get("gate", false))


## The words, with the one substitution the table needs. §10.2 writes T1's text as
## "Your tile points north-east", which is true of the level that ships today and
## would quietly become a lie the first time `make levels` reseeded it. The
## direction is filled in from the tile the player is actually holding.
static func text_of(spec: Dictionary, direction: int = Direction.NONE) -> String:
	var raw: String = str(spec.get("text", ""))
	if direction >= 0:
		raw = raw.replace("{direction}", _spoken(direction))
	return raw


## Appendix A's names are compass abbreviations; a player reading a sentence gets
## the words. Twelve of them at most, so the long form has to earn its room — it
## does, because "NE" is a thing you learn from the game and this is the sentence
## teaching it.
static func _spoken(direction: int) -> String:
	match direction:
		Direction.NW: return "north-west"
		Direction.NE: return "north-east"
		Direction.E: return "east"
		Direction.SE: return "south-east"
		Direction.SW: return "south-west"
		Direction.W: return "west"
	return ""

## §10's tutorial: five teaching boards, and the beats spoken over them.
##
## The tutorial used to be guidance sprinkled through chapter 1 — twelve beats
## across five chapters, each waiting for the campaign level that could carry it.
## That put the first lesson and the last four hours apart, taught the wild charge
## on a board that also had walls, gates and a par to beat on it, and meant a
## player who wanted to see it again had to replay the campaign to find it. It is
## a **course** now (C-37): five boards of its own, six to nine cells each, one
## idea per board, played start to finish in about a minute.
##
## What did not change is that the beats are **data** (§10). Written as code they
## are a dozen `if` blocks in a screen that already has enough to do; written as a
## table they are something somebody can read against the spec — the same argument
## Appendix A's directions and §14.1's timings already won.
##
## This file holds no strings and no timings of its own. It decides *which* beat
## is live and *which* board is next; the level screen decides what a live beat
## looks like.
##
## Deliberately not an autoload (§16.5 fixes the list at six) and deliberately not
## in `src/core/` — a lesson is a fact about a player's history, and the core is
## ignorant of whether a level has ever been played, exactly as [Campaign] is.
class_name Tutorial
extends RefCounted

const DIR := "res://src/data/tutorial"
const BEATS_PATH := DIR + "/beats.json"
const SCHEMA := 2

## §10.2's five lessons: flow, wall, portal, gate, wild.
const COURSE_LENGTH := 5

## §10.1: "Never more than 12 words on screen at once."
const MAX_WORDS := 12

## What starts a beat. Each is a fact the level screen already has.
const TRIGGERS: Array[String] = [
	"level_start",   # the first frame of its board
	"after_place",   # a placement has just been committed
	"wild_gained",   # a charge has just been picked up
]

## §10.2's Interaction column, for the beats whose emphasis lands in the rail. A
## beat that says "the wild goes any direction" while nothing on screen indicates
## which thing the wild *is* has told the player a fact and not taught them
## anything — the pointing is the lesson.
const HIGHLIGHTS: Array[String] = ["", "undo", "discard", "wild", "next"]

## What ends one. Every beat also carries `seconds`; where the completion is an
## action, that is a *fallback* so a player who never performs it is not left
## reading the same words for the rest of the board.
const COMPLETIONS: Array[String] = ["place", "undo", "discard", "time"]

static var _beats: Array = []
static var _levels: Dictionary = {}
## The beats already spoken on the board being played. Deliberately **not** on
## disk: a player who restarts a lesson is asking to be taught it again, and a
## flag that outlived the run would answer a question nobody asked.
static var _spoken: Dictionary = {}


# --- the five boards -----------------------------------------------------------

static func level_path(index: int) -> String:
	return "%s/level_%02d.json" % [DIR, index]


static func level_id(index: int) -> String:
	return "t_l%02d" % index


## `t_l03` → 3, and 0 for anything that is not a tutorial id.
static func index_of(id: String) -> int:
	if not id.begins_with("t_l"):
		return 0
	var digits: String = id.substr(3)
	return int(digits) if digits.is_valid_int() else 0


## Loads a lesson, or [code]null[/code]. Frozen data like the campaign's sixty
## (§9): `tools/author_tutorial.gd` writes these offline and the game only ever
## reads them, because a re-drawn board would leave the words on screen describing
## a wall that is no longer there.
static func level(index: int) -> Level:
	if _levels.has(index):
		return _levels[index]
	var path := level_path(index)
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("tutorial level %s is not valid JSON" % path)
		return null
	var loaded := LevelRepository.from_dict(parsed as Dictionary)
	if loaded == null:
		return null
	var problems := loaded.validate()
	if not problems.is_empty():
		# §18's rule stands: a broken tutorial costs the player their guidance and
		# must never cost them the game. The course simply ends here.
		push_error("tutorial level %s failed validation: %s" % [path, ", ".join(problems)])
		return null
	_levels[index] = loaded
	return loaded


static func clear_cache() -> void:
	_beats = []
	_levels = {}
	_spoken = {}


# --- where the player is in the course -----------------------------------------

## §10: the tutorial runs once, on a save that has never seen it, and never
## interrupts again. Everything about "again" goes through [method reset].
static func done() -> bool:
	return bool(_flags().get("done", false))


## The lesson to open next: the first one not finished, or 0 when the course is
## over. A player who quits after board two comes back to board three rather than
## to the beginning — the course is short, but it is not so short that being sent
## back to the start is nothing.
static func next_index() -> int:
	if done():
		return 0
	for index: int in range(1, COURSE_LENGTH + 1):
		if not FileAccess.file_exists(level_path(index)):
			continue
		if not bool(_flags().get(level_id(index), false)):
			return index
	return 0


## Whether a fresh save should be dropped straight into the course (§10.1).
static func pending() -> bool:
	return not done() and next_index() > 0


static func mark_level_done(index: int) -> void:
	var flags: Dictionary = _flags()
	flags[level_id(index)] = true
	SaveService.save_to_disk()


## The course is over — finished or skipped. §10.1: "skippable at any time with a
## single Back press", and skipping ends the *whole* tutorial rather than the
## board it happened on, because a player who skips has said something about the
## tutorial and not about board three.
static func finish() -> void:
	var flags: Dictionary = _flags()
	flags["done"] = true
	_spoken = {}
	SaveService.save_to_disk()


## §10.1's "Replay tutorial", which "resets the tutorial flags **only**" — the
## emphasis is the spec's own, and it is why this clears one key rather than
## reaching for anything that looks like a fresh start.
static func reset() -> void:
	SaveService.data["tutorial_flags"] = {}
	_spoken = {}
	SaveService.save_to_disk()


static func _flags() -> Dictionary:
	var current: Variant = SaveService.data.get("tutorial_flags")
	if not (current is Dictionary):
		SaveService.data["tutorial_flags"] = {}
	return SaveService.data["tutorial_flags"]


# --- the beat table -------------------------------------------------------------

## The beats, loaded once. Returns an empty list rather than failing if the file
## is missing or from a newer build: a tutorial that will not load costs the
## player their guidance, and §18's rule is that it must never cost them the game.
static func beats() -> Array:
	if not _beats.is_empty():
		return _beats
	if not FileAccess.file_exists(BEATS_PATH):
		push_warning("tutorial beats missing; the boards play without guidance")
		return []
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(BEATS_PATH)) != OK or not (json.data is Dictionary):
		push_warning("tutorial beats are unreadable; the boards play without guidance")
		return []
	var data: Dictionary = json.data
	if int(data.get("schema", 0)) > SCHEMA:
		push_warning("tutorial beats are newer than this build understands")
		return []
	_beats = data.get("beats", []) as Array
	return _beats


static func beat(id: String) -> Dictionary:
	for entry: Variant in beats():
		if str((entry as Dictionary).get("id", "")) == id:
			return entry
	return {}


## The beats belonging to [param id], in table order. Order matters: a board's
## opening beat gates input and the one after it follows, so a screen must not be
## free to run them the other way round.
static func for_level(id: String) -> Array:
	var out: Array = []
	for entry: Variant in beats():
		if str((entry as Dictionary).get("level", "")) == id:
			out.append(entry)
	return out


# --- the live beat --------------------------------------------------------------

## Forgets what has been said, because a board is starting. Called when a lesson
## opens and when one is restarted.
static func begin_level() -> void:
	_spoken = {}


static func spoken(id: String) -> bool:
	return bool(_spoken.get(id, false))


static func mark_spoken(id: String) -> void:
	_spoken[id] = true


## The beat this board should start on [param trigger], or an empty dictionary.
## One at a time, in table order: §10.1 allows twelve words on screen, not two
## beats' worth.
static func next_for(id: String, trigger: String) -> Dictionary:
	for entry: Variant in for_level(id):
		var spec: Dictionary = entry
		if str(spec.get("trigger", "")) != trigger:
			continue
		if spoken(str(spec.get("id", ""))):
			continue
		return spec
	return {}


## Which rail element this beat is pointing at, or "" for the ones that point at
## the board instead.
static func highlight_of(spec: Dictionary) -> String:
	return str(spec.get("highlight", ""))


## Whether the beat holds input to the one cell the lesson is about.
##
## §10.1 used to allow this for the first beat only — "every later beat merely
## highlights and lets the player ignore it" — which was the right rule for
## guidance laid over a campaign level somebody was there to *play*. A teaching
## board is not that: it exists to be walked through, its route is the only route,
## and letting the player place somewhere else on it produces a dead board and a
## lesson nobody finished. Every beat that waits on a placement gates (C-37).
static func gates(spec: Dictionary) -> bool:
	return bool(spec.get("gate", false))


## Whether opening this beat should arm the wild charge for the player.
##
## §6 spends a charge only when the player asks — "Wild button, then cell" — and
## that stays true everywhere except the one board whose whole subject is the
## charge. Arming it there is the difference between a lesson and a player pressing
## a lit cell that refuses them for a reason nothing on screen has explained yet.
static func arms_wild(spec: Dictionary) -> bool:
	return bool(spec.get("arm_wild", false))


## The words, with the one substitution the table needs. §10.3 writes the opening
## beat as "Your tile points north-east", which is true of the board that ships
## today and would quietly become a lie the first time it was re-drawn. The
## direction is filled in from the tile the player is actually holding.
##
## The table holds a §22 *key*, not a sentence, so the course speaks whatever
## language the player set — including the direction, which is a word in the
## middle of a sentence and not a code.
static func text_of(spec: Dictionary, direction: int = Direction.NONE) -> String:
	var words: String = TranslationServer.translate(str(spec.get("text", "")))
	if direction >= 0:
		words = words.replace("{direction}", spoken_name(direction))
	return words


## Appendix A's names are compass abbreviations; a player reading a sentence gets
## the words. Twelve of them at most, so the long form has to earn its room — it
## does, because "NE" is a thing you learn from the game and this is the sentence
## teaching it.
static func spoken_name(direction: int) -> String:
	if direction < 0 or direction >= Direction.COUNT:
		return ""
	return TranslationServer.translate(
		"direction.%s" % Direction.name_of(direction).to_lower())

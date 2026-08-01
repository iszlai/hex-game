## §7.1's progression rules, in one place: what is unlocked, what is next, how far
## along the player is.
##
## These are *rules*, and the reason they are not in `src/core/` is that every one
## of them is a question about the save file — which is app state, not board state.
## `src/core/` is deliberately ignorant of whether a level has ever been played.
##
## Three screens need exactly these answers and would otherwise each invent their
## own: the main menu wants a percentage, the level select wants a lock per cell,
## and the results screen wants the level after this one. Three reimplementations
## of "unlocked" is how a campaign ends up letting you into chapter 4 from the map
## but not from Next.
##
## Deliberately not an autoload — §16.5 fixes the singleton list at six, and this
## holds no state of its own. Every answer is derived from [SaveService] on the
## spot, so a completion recorded mid-frame is visible to the next caller.
class_name Campaign

## §7.1: "a chapter unlocks when the previous chapter has 8 of 12 levels completed
## (so a stuck player is never fully blocked)". The parenthesis is the point — this
## is not `12`, and making it `12` would be a design change, not a tightening.
const CHAPTER_UNLOCK_THRESHOLD := 8

const CHAPTERS := LevelRepository.CHAPTERS
const LEVELS_PER_CHAPTER := LevelRepository.LEVELS_PER_CHAPTER
const TOTAL_LEVELS := CHAPTERS * LEVELS_PER_CHAPTER


# --- per level ----------------------------------------------------------------

## The save entry for a level, or an empty dictionary. Every reader below goes
## through this rather than reaching into `SaveService.data["campaign"]`, so the
## shape of a save entry is known in one file.
static func entry(chapter: int, index: int) -> Dictionary:
	# Keyed on the level's own uid rather than its slot (C-34): a level carries its
	# stars with it when the campaign is reordered, instead of leaving them behind
	# for whatever lands in the slot.
	var level: Level = LevelRepository.load_level(chapter, index)
	if level == null:
		return {}
	return SaveService.level_entry(level.progress_key())


static func is_completed(chapter: int, index: int) -> bool:
	return bool(entry(chapter, index).get("completed", false))


static func stars(chapter: int, index: int) -> int:
	return int(entry(chapter, index).get("stars", 0))


## §12.6 — a level completed with at least one hint carries a dot on its star
## display for good. It blocks the `no_hints_chapter` achievement and nothing else.
static func hinted(chapter: int, index: int) -> bool:
	return bool(entry(chapter, index).get("hinted", false))


static func best_placements(chapter: int, index: int) -> int:
	return int(entry(chapter, index).get("best_placements", 0))


# --- unlocking ----------------------------------------------------------------

## Chapter 1 is always open. Every later chapter waits on §7.1's 8 of 12.
static func chapter_unlocked(chapter: int) -> bool:
	if chapter <= 1:
		return true
	if chapter > CHAPTERS:
		return false
	return completed_in_chapter(chapter - 1) >= CHAPTER_UNLOCK_THRESHOLD


## §7.1: "Levels unlock linearly within a chapter". Level 1 of an unlocked chapter
## is open; every later level waits on the one before it — *not* on the one before
## it being three-starred, because §7.1 also says stars "gate achievements only,
## never content".
static func level_unlocked(chapter: int, index: int) -> bool:
	if not chapter_unlocked(chapter) or index < 1 or index > LEVELS_PER_CHAPTER:
		return false
	if index == 1:
		return true
	return is_completed(chapter, index - 1)


# --- progress -----------------------------------------------------------------

static func completed_in_chapter(chapter: int) -> int:
	var count: int = 0
	for index: int in range(1, LEVELS_PER_CHAPTER + 1):
		if is_completed(chapter, index):
			count += 1
	return count


static func stars_in_chapter(chapter: int) -> int:
	var total: int = 0
	for index: int in range(1, LEVELS_PER_CHAPTER + 1):
		total += stars(chapter, index)
	return total


static func completed_levels() -> int:
	var count: int = 0
	for chapter: int in range(1, CHAPTERS + 1):
		count += completed_in_chapter(chapter)
	return count


## The number the main menu puts beside "Campaign" (§12.2). Rounded rather than
## truncated, so finishing the last level reads 100% and the one before it does
## not also read 100%.
static func completion_percent() -> int:
	if TOTAL_LEVELS <= 0:
		return 0
	return int(round(100.0 * float(completed_levels()) / float(TOTAL_LEVELS)))


## Every star the player owns, out of `TOTAL_LEVELS * Scoring.MAX_STARS`. Reuses
## the core's own tally rather than counting again, so the two can never disagree.
static func total_stars() -> int:
	return Scoring.campaign_total_stars(SaveService.data.get("campaign", {}) as Dictionary)


# --- where to go next ---------------------------------------------------------

## The level the campaign should open on: the first unlocked level not yet
## completed. `(0, 0)` only when all 60 are done, which the caller reads as
## "the campaign is finished" rather than as an error.
static func next_unplayed() -> Vector2i:
	for chapter: int in range(1, CHAPTERS + 1):
		if not chapter_unlocked(chapter):
			continue
		for index: int in range(1, LEVELS_PER_CHAPTER + 1):
			if level_unlocked(chapter, index) and not is_completed(chapter, index):
				return Vector2i(chapter, index)
	return Vector2i.ZERO


## The level after this one, for the Results screen's Next button (§12.2).
##
## It steps over a chapter boundary only if the next chapter is actually unlocked,
## which is the case §7.1 leaves implicit: finishing chapter 2 level 12 with only
## 7 of chapter 2 done means Next has nowhere to go, and the honest answer is
## `(0, 0)` so the screen can offer the map instead of a locked level.
static func after(chapter: int, index: int) -> Vector2i:
	if index < LEVELS_PER_CHAPTER:
		return Vector2i(chapter, index + 1)
	if chapter < CHAPTERS and chapter_unlocked(chapter + 1):
		return Vector2i(chapter + 1, 1)
	return Vector2i.ZERO


## Where the level select puts its cursor (§12.2, "Last played level"). The
## in-progress run wins, because that is literally the level the player was last
## in; failing that, the next unplayed one; failing that, chapter 1 level 1, so a
## finished campaign still opens somewhere real.
static func last_played() -> Vector2i:
	var payload: Variant = SaveService.data.get("in_progress")
	if payload is Dictionary:
		var at: Vector2i = LevelRepository.locate(str((payload as Dictionary).get("level_id", "")))
		if at.x > 0 and level_unlocked(at.x, at.y):
			return at
	var next: Vector2i = next_unplayed()
	return next if next.x > 0 else Vector2i(1, 1)

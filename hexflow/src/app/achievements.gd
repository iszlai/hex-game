## §23.1's twenty achievements, and the conditions that earn them.
##
## Every one of them was listed in the spec and nineteen had no detection anywhere
## — the only `unlock_achievement` call in the codebase was `first_flow`. So this
## is the part §23.1 was always missing rather than a new idea: the api names and
## the conditions below are §23.1's table, one row at a time.
##
## Not in `src/core/`, because every condition is a question about the **save
## file** and the core is deliberately ignorant of it (the same reason [Campaign]
## lives here). Not an autoload either — §16.5 fixes the list at six and this holds
## no state. Static functions over `SaveService.data`, returning the names *now*
## earned; unlocking them is [GameDirector]'s, and [SteamService.unlock_achievement]
## is already idempotent, so re-earning one costs nothing.
##
## Deliberately separate from Steam. §23.1 says achievements mirror locally and
## sync later, so detection has to work with no Steam in the build at all — which
## is the only configuration that has ever existed.
class_name Achievements

## §23.1's table, in its order. Asserted against the spec by the tests, the way
## Appendix A's directions and §14.1's timings are: a name that drifts from the
## Steamworks partner site is an achievement that silently never fires.
const ALL: Array[String] = [
	"first_flow",
	"chapter_1_clear", "chapter_2_clear", "chapter_3_clear",
	"chapter_4_clear", "chapter_5_clear",
	"chapter_1_perfect", "chapter_2_perfect", "chapter_3_perfect",
	"chapter_4_perfect", "chapter_5_perfect",
	"all_stars",
	"no_discard",
	"no_hints_chapter",
	"undo_free",
	"endless_10", "endless_25", "endless_50",
	"daily_7",
	"the_long_way",
]

## §23.1: "180/180 stars" — three per level across the whole campaign.
const ALL_STARS := Campaign.TOTAL_LEVELS * Scoring.MAX_STARS

## §23.1: "Complete 12 consecutive levels without undo". Twelve because that is a
## chapter, though §23.1 does not require them to be in one.
const UNDO_FREE_RUN := 12

## §23.1's three endless thresholds, in goals.
const ENDLESS_GOALS: Array[int] = [10, 25, 50]

## §23.1: "Complete 7 dailies (not necessarily consecutive)".
const DAILY_COUNT := 7

## §23.1: "at least par + 15 placements (hidden, affectionate)".
const LONG_WAY_OVER_PAR := 15


## What a campaign level's completion earned. [param discards_used] counts the
## *voluntary* ones — §5.7's free auto-discard is not a choice the player made and
## must not cost them `no_discard`.
static func for_campaign_completion(
	chapter: int,
	placements: int,
	par: int,
	discards_used: int,
	undo_used: bool
) -> Array[String]:
	var out: Array[String] = ["first_flow"]

	# The chapter ones are read back off the save rather than inferred from this
	# completion, because "all 12" includes the eleven that happened on other days
	# — and because a replay of an already-finished level has to be able to earn
	# the chapter award the player missed the first time round.
	for ch: int in range(1, Campaign.CHAPTERS + 1):
		if Campaign.completed_in_chapter(ch) >= Campaign.LEVELS_PER_CHAPTER:
			out.append("chapter_%d_clear" % ch)
		if Campaign.stars_in_chapter(ch) \
				>= Campaign.LEVELS_PER_CHAPTER * Scoring.MAX_STARS:
			out.append("chapter_%d_perfect" % ch)
		if _chapter_finished_without_a_hint(ch):
			out.append("no_hints_chapter")

	if Campaign.total_stars() >= ALL_STARS:
		out.append("all_stars")

	# §23.1 scopes `no_discard` to chapter 5, which is where §8.4 hands out 0–2 of
	# them: spending none is only an achievement where there were barely any.
	if chapter == Campaign.CHAPTERS and discards_used == 0:
		out.append("no_discard")

	if not undo_used and undo_free_streak() >= UNDO_FREE_RUN:
		out.append("undo_free")

	if par > 0 and placements >= par + LONG_WAY_OVER_PAR:
		out.append("the_long_way")

	return out


## What an endless run earned, by §7.2's score.
static func for_endless_run(goals: int) -> Array[String]:
	var out: Array[String] = []
	for threshold: int in ENDLESS_GOALS:
		if goals >= threshold:
			out.append("endless_%d" % threshold)
	return out


## What finishing today's daily earned. Counted off the stored history rather than
## off a counter, so §7.3's unlimited retries cannot inflate it — a day already in
## the history is still one day.
static func for_daily() -> Array[String]:
	var daily: Dictionary = SaveService.data.get("daily", {})
	var history: Dictionary = daily.get("history", {})
	return ["daily_7"] as Array[String] if history.size() >= DAILY_COUNT \
		else [] as Array[String]


# --- the undo-free run (§23.1) ------------------------------------------------
#
# The only condition that cannot be answered from the save as it stands, because
# nothing recorded whether a level was finished with or without an undo — only a
# lifetime `stats.undos` total, which says nothing about consecutive levels. So it
# is a counter, advanced by the completion that earns it.

static func undo_free_streak() -> int:
	return int(_stats().get("undo_free_streak", 0))


## Advances or breaks the run. Called once per campaign completion, before the
## conditions above are read.
static func record_undo_use(undo_used: bool) -> void:
	var stats: Dictionary = _stats()
	stats["undo_free_streak"] = 0 if undo_used else undo_free_streak() + 1
	# Written through, rather than left for whatever saves next: a run of eleven
	# clean levels that a crash turns back into zero is the kind of loss a player
	# never sees happen and never forgives.
	SaveService.save_to_disk()


static func _stats() -> Dictionary:
	if not SaveService.data.has("stats"):
		SaveService.data["stats"] = {}
	return SaveService.data["stats"]


## §23.1's "Complete a full chapter without a hint". `hinted` marks the *level* and
## is ORed on every completion, so it survives a later clean run — which is what
## makes this a claim about the chapter rather than about the last attempt at it.
static func _chapter_finished_without_a_hint(chapter: int) -> bool:
	for index: int in range(1, Campaign.LEVELS_PER_CHAPTER + 1):
		if not Campaign.is_completed(chapter, index):
			return false
		if Campaign.hinted(chapter, index):
			return false
	return true

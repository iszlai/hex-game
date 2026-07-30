## Stars and run scores (§5.10). Integer-only, no state.
class_name Scoring

const MAX_STARS := 3

## `par` is the solver's optimum for the level's exact tile sequence, so three
## stars are always attainable and never luck-dependent in campaign.
static func stars(placements: int, par: int) -> int:
	if placements <= 0 or par <= 0:
		return 0
	if placements <= par:
		return 3
	if placements <= par + 3:
		return 2
	return 1


## Endless ranks on goals reached, ties broken by fewer placements.
## Returns a negative number when [param a] ranks better than [param b].
static func compare_endless(
	a_goals: int, a_placements: int, b_goals: int, b_placements: int
) -> int:
	if a_goals != b_goals:
		return b_goals - a_goals
	return a_placements - b_placements


static func campaign_total_stars(campaign: Dictionary) -> int:
	var total: int = 0
	for key: Variant in campaign.keys():
		var entry: Dictionary = campaign[key]
		total += int(entry.get("stars", 0))
	return total

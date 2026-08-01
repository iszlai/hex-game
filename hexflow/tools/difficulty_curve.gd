extends RefCounted
## The difficulty curve the campaign is authored against (C-33).
##
## §9 orders the sixty levels by `par`, and `par` measures **length**. Three
## independent measurements say that is the wrong key: `tools/count_routes.gd`
## found chapter 4 to be the *widest* chapter in the game, `tools/measure_
## difficulty.gd` found it the most forgiving, and neither correlates with par.
## The campaign as shipped has no curve in either dial — chapter 4 level 6 has
## sixty perfect routes and sits between levels with two and one.
##
## So the curve is written down here, as data, and the sweep authors against it
## rather than against a par band. Two dials, because the measurements showed they
## are nearly independent (`forgiving` predicts route count at +0.44, and every
## cheaper number below +0.2):
##
##   routes      how many ways there are to finish in the ideal number of moves.
##               Falls as a chapter goes on. This is "how many answers are there".
##   forgiving   what fraction of wrong turns can still be recovered from.
##               Falls too, but on its own schedule. This is "what a mistake costs".
##
## **The shape is a sawtooth, not a ramp.** Within a chapter the numbers fall and
## the last level is the spike. Between chapters they reset *part* of the way —
## each chapter opens easier than the last one ended and harder than the last one
## opened — which is what stops a fifty-level slog from feeling monotonous and
## what §9's "monotonic in par" could never express.
##
## Walls and goals are the levers. Chapter 2 is the least forgiving chapter in the
## shipped game despite having the second-shortest levels, because walls make a
## wrong turn fatal; the two multi-goal chapters are the most forgiving, because a
## second goal is a second chance. So the sweep tightens with walls and loosens
## with goals rather than by growing the board — which it cannot do anyway, since
## a radius-4 board is already too big for the tools to measure (C-19, C-32).
##
## Not part of the shipped game: this is authoring data, read by
## `tools/author_levels.gd`.
##
## Named `DifficultyCurve` rather than `Curve` because Godot already has a `Curve`
## resource, and a `class_name` that shadows an engine type is a parse error at
## every call site rather than at the declaration.
class_name DifficultyCurve

const CHAPTERS := 5
const LEVELS := 12

## Target perfect-route count at level 1 and level 12 of each chapter, and the
## floor the chapter's last level spikes to.
##
## Read the first column downwards: 20, 14, 10, 8, 5. Each chapter opens narrower
## than the one before it. Read a row across: it narrows to a near-corridor by the
## twelfth. Between the two, every chapter is a fresh descent from somewhere
## easier than where the last one ended.
const ROUTES: Array = [
	# Chapter 1 opens at six rather than the twenty an even ramp would suggest, and
	# the reason is §8.4: its first levels are radius-2 boards of nineteen cells
	# with an ideal of three or four moves. A board that small does not *have*
	# twenty distinct perfect routes, so a higher target would not make the levels
	# wider, it would make the sweep pick blindly among candidates it could never
	# satisfy — which is what it did, and chapter 1 came back 3, 3, 2, 3, 3, 9, 8,
	# 14 — climbing, because the boards grew before the curve did.
	{"chapter": 1, "first": 6, "last": 2},
	{"chapter": 2, "first": 5, "last": 2},
	{"chapter": 3, "first": 5, "last": 1},
	{"chapter": 4, "first": 4, "last": 1},
	{"chapter": 5, "first": 4, "last": 1},
]

## The same shape for the other dial, in hundredths so `src/core/`'s no-float rule
## is respected even though this file is a tool and need not be.
const FORGIVING: Array = [
	{"chapter": 1, "first": 90, "last": 60},
	{"chapter": 2, "first": 80, "last": 50},
	{"chapter": 3, "first": 75, "last": 45},
	{"chapter": 4, "first": 70, "last": 40},
	{"chapter": 5, "first": 60, "last": 30},
]

## §6's mechanic ladder decides which silhouettes a chapter may use, because a
## shape is a *teaching* device as much as a difficulty one and a player meeting
## the ring and the gate in the same level learns neither.
##
## Chapter 1 stays a hexagon throughout: §10's tutorial runs there, and a beat
## that says "grow from any path cell" over a corridor is teaching the corridor
## instead. Later chapters gain one shape at a time, and chapter 5 may use all of
## them because by then the shape is the puzzle rather than the lesson.
const SHAPES: Array = [
	{"chapter": 1, "allowed": ["hexagon"]},
	{"chapter": 2, "allowed": ["hexagon", "triangle"]},
	{"chapter": 3, "allowed": ["hexagon", "triangle", "hourglass"]},
	{"chapter": 4, "allowed": ["hexagon", "ring", "hourglass", "zed"]},
	{"chapter": 5, "allowed": ["hexagon", "ring", "zed", "star", "triangle"]},
]


## The target route count for one slot.
static func routes_for(chapter: int, index: int) -> int:
	var row: Dictionary = _row(ROUTES, chapter)
	return _shape_of(int(row["first"]), int(row["last"]), index)


## The target forgiveness for one slot, in hundredths.
static func forgiving_for(chapter: int, index: int) -> int:
	var row: Dictionary = _row(FORGIVING, chapter)
	return _shape_of(int(row["first"]), int(row["last"]), index)


## The sawtooth, for either dial.
##
## Levels 1–10 descend from [param first] toward a floor that is deliberately
## *not* the chapter's hardest number. Level 11 steps back up — a breath — and
## level 12 drops to [param last] outright.
##
## The breath is the part worth defending. A chapter that simply gets harder for
## twelve levels has no moment in it: the hardest level is where the line happened
## to end, and the player feels the slope rather than the peak. Stepping back at
## 11 makes 12 a *drop*, and a drop is something you notice. It is the same reason
## §14.2 holds the goal colour for 340 ms before crossing it over — a change needs
## something to be a change from.
static func _shape_of(first: int, last: int, index: int) -> int:
	var step: int = maxi(1, (first - last) / 5)
	var floor_before_spike: int = last + step
	if index >= LEVELS:
		return last
	if index == LEVELS - 1:
		return floor_before_spike + step
	return _ramp(first, floor_before_spike, index, LEVELS - 2)


static func shapes_for(chapter: int) -> Array:
	return _row(SHAPES, chapter)["allowed"]


## How far a candidate is from its slot, as one number the sweep can minimise.
##
## Routes are compared on a **ratio** rather than a difference, because the
## distance from 1 route to 3 is the whole of what makes a level a corridor, and
## the distance from 18 to 20 is nothing at all. A plain subtraction would spend
## the sweep's effort at the easy end where it does not matter.
static func distance(chapter: int, index: int, routes: int, forgiving: int) -> int:
	var want_routes: int = routes_for(chapter, index)
	var want_forgiving: int = forgiving_for(chapter, index)
	var got: int = maxi(1, routes)
	var ratio: int = (got * 100) / want_routes if got >= want_routes \
		else (want_routes * 100) / got
	return (ratio - 100) + absi(forgiving - want_forgiving) * 2


static func _row(table: Array, chapter: int) -> Dictionary:
	for entry: Variant in table:
		var row: Dictionary = entry
		if int(row["chapter"]) == chapter:
			return row
	return table[table.size() - 1] as Dictionary


## Linear from [param first] at level 1 to [param last] at level [param over],
## in integers — no float has any business in a table this small.
static func _ramp(first: int, last: int, index: int, over: int) -> int:
	var t: int = clampi(index - 1, 0, over - 1)
	return first + ((last - first) * t) / (over - 1)

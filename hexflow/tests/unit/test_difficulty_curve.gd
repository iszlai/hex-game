## @core — the campaign's authored difficulty curve (C-33).
##
## The shipped sixty have no curve in either dial: chapter 4 level 6 has sixty
## perfect routes and sits between levels with two and one. The table this tests
## is what replaces "pick candidates by length", so its *shape* is the
## requirement — and a table is exactly the kind of thing that gets edited by one
## number and quietly stops being the shape it was drawn as.
extends GutTest


func _routes(chapter: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in range(1, DifficultyCurve.LEVELS + 1):
		out.append(DifficultyCurve.routes_for(chapter, i))
	return out


## Levels 1 to 10 only ever get harder. This is the part §9 already asked for and
## the shipped campaign does not do.
func test_a_chapter_narrows_as_it_goes() -> void:
	for chapter: int in range(1, DifficultyCurve.CHAPTERS + 1):
		var r: Array[int] = _routes(chapter)
		for i: int in range(1, 10):
			assert_lte(r[i], r[i - 1],
				"chapter %d gets easier from level %d to %d" % [chapter, i, i + 1])


## The breath and the drop. A chapter that simply descends for twelve levels has
## no moment in it — the hardest level is wherever the line happened to stop. The
## step back at 11 is what makes 12 a *drop* rather than one more step down.
func test_the_last_level_is_a_spike_and_the_one_before_it_is_a_breath() -> void:
	for chapter: int in range(1, DifficultyCurve.CHAPTERS + 1):
		var r: Array[int] = _routes(chapter)
		assert_gt(r[10], r[9], "chapter %d has no breath at level 11" % chapter)
		assert_lt(r[11], r[10], "chapter %d has no drop at level 12" % chapter)
		assert_lte(r[11], r[9], "chapter %d's spike is not its hardest" % chapter)


## The rising baseline: each chapter opens harder than the last one opened, and
## easier than the last one ended. Without the second half it is a ramp with the
## levels renumbered; without the first it is five unrelated chapters.
##
## Routes are allowed to *plateau* between chapters and forgiveness is not. The
## whole usable range of route counts is about six down to one — five strictly
## decreasing openings would spend it all on the opening and leave each chapter
## nothing to descend through. Two chapters may therefore start equally wide;
## what makes the later one harder is that a mistake in it costs more.
func test_each_chapter_starts_below_the_last_and_above_its_spike() -> void:
	for chapter: int in range(2, DifficultyCurve.CHAPTERS + 1):
		var previous: Array[int] = _routes(chapter - 1)
		var current: Array[int] = _routes(chapter)
		assert_lte(current[0], previous[0],
			"chapter %d opens wider than chapter %d did" % [chapter, chapter - 1])
		assert_gte(current[0], previous[11],
			"chapter %d opens harder than chapter %d's spike, so there is no relief"
				% [chapter, chapter - 1])
		assert_lt(
			DifficultyCurve.forgiving_for(chapter, 1),
			DifficultyCurve.forgiving_for(chapter - 1, 1),
			"chapter %d forgives as much as chapter %d, so nothing has escalated"
				% [chapter, chapter - 1])


## Both dials move together, because a level with few routes that forgives every
## mistake is not hard, it is fiddly.
func test_forgiveness_follows_the_same_shape() -> void:
	for chapter: int in range(1, DifficultyCurve.CHAPTERS + 1):
		var f: Array[int] = []
		for i: int in range(1, DifficultyCurve.LEVELS + 1):
			f.append(DifficultyCurve.forgiving_for(chapter, i))
		for i: int in range(1, 10):
			assert_lte(f[i], f[i - 1], "chapter %d forgives more at level %d" % [chapter, i + 1])
		assert_gt(f[10], f[9], "chapter %d has no breath in forgiveness" % chapter)
		assert_lt(f[11], f[10], "chapter %d has no drop in forgiveness" % chapter)
		assert_between(f[11], 1, 100, "forgiveness is a percentage")


## §10's tutorial runs in chapter 1, and a beat that says "grow from any path
## cell" over a corridor is teaching the corridor instead. Shapes arrive one at a
## time afterwards, and only chapter 5 gets the lot.
func test_shapes_arrive_one_chapter_at_a_time() -> void:
	assert_eq(DifficultyCurve.shapes_for(1), ["hexagon"],
		"chapter 1 is where the tutorial lives")
	var seen: int = 1
	for chapter: int in range(2, DifficultyCurve.CHAPTERS + 1):
		var allowed: Array = DifficultyCurve.shapes_for(chapter)
		assert_true(allowed.has("hexagon"), "chapter %d drops the plain board" % chapter)
		assert_gte(allowed.size(), seen, "chapter %d offers fewer shapes" % chapter)
		seen = allowed.size()
		for name: Variant in allowed:
			assert_true(Hex.SHAPES.has(str(name)),
				"chapter %d allows %s, which is not a shape" % [chapter, name])


## The score the sweep minimises. Routes are compared as a ratio, because the gap
## from one route to three is the whole of what makes a level a corridor and the
## gap from eighteen to twenty is nothing — a subtraction would spend the sweep's
## effort at the easy end where it does not matter.
func test_the_distance_score_is_zero_on_target_and_grows_away_from_it() -> void:
	var want: int = DifficultyCurve.routes_for(3, 6)
	var forgiving: int = DifficultyCurve.forgiving_for(3, 6)
	assert_eq(DifficultyCurve.distance(3, 6, want, forgiving), 0, "on target is zero")

	var near: int = DifficultyCurve.distance(3, 6, want + 1, forgiving)
	var far: int = DifficultyCurve.distance(3, 6, want + 8, forgiving)
	assert_gt(far, near, "further from the target must score worse")

	# One route against a target of six is a corridor where a puzzle was asked for,
	# and must score worse than six against a target of one — the ratio is the same
	# either way, and being *too hard* at level 6 is the failure worth catching.
	assert_gt(DifficultyCurve.distance(3, 6, 1, forgiving), near)

	# Forgiveness pulls its weight too, or the sweep would ignore it entirely.
	assert_gt(DifficultyCurve.distance(3, 6, want, forgiving - 20),
		DifficultyCurve.distance(3, 6, want, forgiving - 2))

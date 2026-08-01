## Validate: one button that runs what CI runs (MAP-EDITOR §5).
##
## Two things this must not do, and both are the reason it is a class rather than
## four lines in a button handler:
##
##   * **It must not accept `UNKNOWN`.** The solver saying "I could not finish" is
##     a rejection, exactly as §8.2 step 7 treats it. A board nobody can rank is a
##     board nobody should ship (C-33).
##   * **It must not silently pass a board that is merely solvable.** Solvable is
##     the floor. The curve numbers are the point, and they are reported whether or
##     not the author asked for them.
##
## Route count is the one measurement allowed to come back empty-handed. §5 says
## it reports "3 routes — or too big to measure", so an unmeasurable board is
## reported honestly and still saveable; what is *not* allowed is a board whose
## solvability is unknown, which is a different question.
##
## Not part of the shipped game.
class_name MapReport
extends RefCounted

## Whether Save may proceed. §6 makes a failed report a **refusal**, not a warning.
var ok: bool = false
## One line per row of §5's table, in that order, for the status bar.
var lines: Array[String] = []
var problems: Array[String] = []

var par: int = -1
var routes: int = -1
var forgiving: int = -1
var distance: int = -1
var solution: Array[Vector3i] = []
var solution_script: Array = []


## Runs the whole table. Slow — seconds — which is why §5 binds this to a button
## and a key rather than to every edit.
static func of(draft: MapDraft) -> MapReport:
	var report := MapReport.new()

	# The live constraints first: they are the cheap ones and they are the ones an
	# author can act on without reading a solver result.
	report.problems.append_array(draft.problems())
	var level := draft.to_level()
	if level == null:
		report.problems.append("the board has no start, so there is nothing to solve")
		report.lines.append("✗ not a board yet")
		return report
	report.problems.append_array(level.validate())
	if not report.problems.is_empty():
		report.lines.append("✗ " + report.problems[0])
		return report
	report.lines.append("✓ structure")

	if level.tiles.is_empty():
		report.problems.append("no tile sequence — run Fill, or type one")
		report.lines.append("✗ no tiles")
		return report

	var result := Solver.solve(level)
	match result.status:
		Solver.Status.UNSOLVABLE:
			report.problems.append("no route reaches every goal with this sequence")
			report.lines.append("✗ unsolvable")
			return report
		Solver.Status.UNKNOWN:
			report.problems.append(
				"the solver ran out of states — this board cannot be ranked, so it cannot ship")
			report.lines.append("✗ unranked")
			return report
	report.par = result.par
	report.solution = result.moves
	report.solution_script = result.actions
	level.par = result.par
	level.solution = result.moves
	level.solution_script = result.actions
	report.lines.append("✓ solvable · ideal %d" % result.par)

	var metrics := LevelMetrics.new()
	report.routes = metrics.routes_at_ideal(level)
	report.lines.append("%d routes" % report.routes if report.routes >= 0
		else "routes: too big to measure")
	report.forgiving = metrics.forgiveness(level)
	report.lines.append("%d%% of wrong turns recoverable" % report.forgiving
		if report.forgiving >= 0 else "forgiveness: unmeasured")

	# Against the curve, always — this is the half §5 exists for. A level that
	# merely works is the floor; what it is *for* is its slot.
	var want_routes: int = DifficultyCurve.routes_for(draft.chapter, draft.index)
	var want_forgiving: int = DifficultyCurve.forgiving_for(draft.chapter, draft.index)
	if report.routes >= 0 and report.forgiving >= 0:
		report.distance = DifficultyCurve.distance(
			draft.chapter, draft.index, report.routes, report.forgiving)
		report.lines.append("slot wants %d routes and %d%%; this is %d and %d%% (off by %d)"
			% [want_routes, want_forgiving, report.routes, report.forgiving, report.distance])
	else:
		report.lines.append("slot wants %d routes and %d%%; this could not be scored"
			% [want_routes, want_forgiving])

	report.ok = true
	return report


## The status line §3 puts under the canvas.
func summary() -> String:
	return " · ".join(lines)


## The level this report validated, stamped with what it found (§6).
##
## The par, the solution and both curve numbers come from **this** report, not
## from a fresh measurement — so a hand-drawn level carries the same authoring
## record as a swept one and CI's curve check covers both. Returns
## [code]null[/code] on a report that did not pass, which is what makes §6's
## refusal a refusal: there is no level to write.
func stamp(draft: MapDraft) -> Level:
	if not ok:
		return null
	var level := draft.to_level()
	if level == null:
		return null
	level.par = par
	level.solution = solution
	level.solution_script = solution_script
	level.authored_routes = routes
	level.authored_forgiving = forgiving
	return level


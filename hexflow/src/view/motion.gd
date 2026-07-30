## §14.1's timing table, as data.
##
## "Every timing below is a requirement, not a suggestion" — so it lives in one
## table that the view reads, the way Appendix A's directions do, rather than as a
## number typed into whichever script happened to need it. A tween built anywhere
## else is a tween nobody can audit against §14.
##
## Every duration passes through [method seconds], which applies §14.5: Reduce
## Motion scales **all** of them by 0.4, and screen transitions become a flat
## 120 ms rather than a scaled one, because §14.5 names that number itself.
##
## §14.5 is a motion *reduction*, not a feedback removal. The loops of §14.1 —
## candidate breathing, goal pulse — stop moving under it, but what they were
## conveying does not disappear: a candidate holds the bright end of its stroke
## instead of travelling to it. Anything reading this table for a loop must ask
## [method loops] rather than assuming a duration means animation.
class_name Motion

## §14.1, row for row. `t` and `e` are the `Tween` transition and ease the spec
## names; `ms` is at full motion. Do not retune one of these without changing §14.1
## — the table and the spec are meant to be diffable against each other.
const TIMINGS := {
	"cursor_snap": {"ms": 80, "t": Tween.TRANS_CUBIC, "e": Tween.EASE_OUT},
	"placement_pop": {"ms": 220, "t": Tween.TRANS_BACK, "e": Tween.EASE_OUT},
	"connector_draw": {"ms": 160, "t": Tween.TRANS_CUBIC, "e": Tween.EASE_OUT},
	"flow_pulse": {"ms": 300, "t": Tween.TRANS_SINE, "e": Tween.EASE_IN_OUT},
	"queue_advance": {"ms": 180, "t": Tween.TRANS_CUBIC, "e": Tween.EASE_OUT},
	"auto_discard": {"ms": 260, "t": Tween.TRANS_QUAD, "e": Tween.EASE_IN},
	"illegal_shake": {"ms": 120, "t": Tween.TRANS_ELASTIC, "e": Tween.EASE_OUT},
	"candidate_breathing": {"ms": 1800, "t": Tween.TRANS_SINE, "e": Tween.EASE_IN_OUT},
	"goal_pulse": {"ms": 2000, "t": Tween.TRANS_SINE, "e": Tween.EASE_IN_OUT},
	"goal_reached": {"ms": 700, "t": Tween.TRANS_CUBIC, "e": Tween.EASE_OUT},
	"board_ripple": {"ms": 500, "t": Tween.TRANS_CUBIC, "e": Tween.EASE_OUT},
	"screen_transition": {"ms": 320, "t": Tween.TRANS_CUBIC, "e": Tween.EASE_IN_OUT},
	"results_star": {"ms": 260, "t": Tween.TRANS_BACK, "e": Tween.EASE_OUT},
	"dead_desaturate": {"ms": 400, "t": Tween.TRANS_CUBIC, "e": Tween.EASE_OUT},
}

## The rows §14.1 marks as loops. They repeat rather than run once, and §14.5 stops
## them dead instead of shortening them — a breathing stroke at 720 ms is still
## breathing.
const LOOPS: Array[String] = ["candidate_breathing", "goal_pulse"]

## §14.5's global multiplier.
const REDUCE_MOTION_SCALE := 0.4

## §14.5 names this one outright: transitions "become 120 ms cross-fades", which is
## not 320 × 0.4.
const REDUCED_TRANSITION_MS := 120

## §14.1's staggers and per-cell delays, which are timings too even though the
## table states them in prose.
const RESULTS_STAR_STAGGER_MS := 140
const RIPPLE_PER_CELL_MS := 28

## §14.3's entire allowance for camera motion the player did not ask for.
const SHAKE_PIXELS := 2.0
const SHAKE_MS := 120

## §14.4's emitters and the hard cap over all of them.
const PARTICLE_BUDGET := {
	"placement_sparks": 8,
	"goal_burst": 24,
	"flow_motes": 12,
	"wild_pickup": 10,
}
const PARTICLE_CAP := 120


## How long [param name] runs, in seconds, under the live §14.5 setting.
static func seconds(name: String) -> float:
	return float(milliseconds(name)) / 1000.0


static func milliseconds(name: String) -> int:
	var row: Dictionary = TIMINGS[name]
	if not SettingsService.reduce_motion():
		return int(row["ms"])
	if name == "screen_transition":
		return REDUCED_TRANSITION_MS
	return int(round(float(row["ms"]) * REDUCE_MOTION_SCALE))


static func transition(name: String) -> Tween.TransitionType:
	return TIMINGS[name]["t"] as Tween.TransitionType


static func ease_type(name: String) -> Tween.EaseType:
	return TIMINGS[name]["e"] as Tween.EaseType


## Whether [param name] should be animating at all right now. A loop under Reduce
## Motion does not run slowly — it does not run (§14.5).
static func loops(name: String) -> bool:
	return LOOPS.has(name) and not SettingsService.reduce_motion()


## §14.4 and §14.5 together: no particles at all under Reduce Motion, and never
## more than the cap when they are on.
static func particles_allowed() -> bool:
	return not SettingsService.reduce_motion()


## Applies [param name]'s curve to [param tween], so a caller cannot take the
## duration from the table and then invent its own easing.
static func shape(tween: Tween, name: String) -> Tween:
	return tween.set_trans(transition(name)).set_ease(ease_type(name))

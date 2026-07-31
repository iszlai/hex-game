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


## §14.2's goal-reached sequence, as offsets in milliseconds from the moment the
## goal is entered. The beats are a table for the same reason §14.1's rows are:
## a sequence typed into a script is a sequence nobody can diff against the spec.
const GOAL_SEQUENCE := {
	"cell_flourish": 0,
	"burst": 60,
	"ripple": 120,
	"flow": 200,
	"settle": 340,
	"results": 700,
}

## §14.2's own numbers for the goal cell itself: 1.0 → 1.25 → 1.0 over 340 ms.
const GOAL_FLOURISH_SCALE := 1.25
const GOAL_FLOURISH_MS := 340

## §14.2 runs the flow pulse "at 2x speed" over the whole path.
const GOAL_FLOW_SPEEDUP := 2.0

## How long the goal cell takes to convert to path colour once it starts.
##
## §14.2 fixes the *moment* — t=340, as the flourish returns to 1.0 — and not the
## duration, so this is a chosen number and is written down as one. It is a
## cross-fade rather than a swap because a hard colour snap on the tile the player
## is looking at is the exact thing §14.1's table exists to prevent, and it fits
## inside the 360 ms §14.2 leaves before the Results card.
const GOAL_SETTLE_MS := 200

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

## §12.5's focus ring, which is a timing the spec states in prose rather than in
## §14.1's table: "3 px, accent colour, animated in 100 ms, and never invisible".
## It is here rather than in [constant TIMINGS] because that dictionary is asserted
## row for row against §14.1 and is not allowed to grow a fifteenth entry — but a
## number typed into whichever menu happened to need it is exactly what this file
## exists to prevent.
const FOCUS_RING_MS := 100
const FOCUS_RING_PX := 3
## §21: the ring "also scales 1.04×", so focus is never carried by colour alone.
const FOCUS_RING_SCALE := 1.04


## The focus ring's animation, in seconds, under §14.5. Reduce Motion shortens it
## like every other duration — but never to zero, because §12.5 also says the ring
## is *never invisible*, and an instant ring is still a ring.
static func focus_ring_seconds() -> float:
	var ms: float = float(FOCUS_RING_MS)
	if SettingsService.reduce_motion():
		ms *= REDUCE_MOTION_SCALE
	return ms / 1000.0


## The ripple's per-cell delay, in seconds, under §14.5. It scales with everything
## else: a wave whose front slowed while its body sped up would tear.
static func ripple_step_seconds() -> float:
	var ms: float = float(RIPPLE_PER_CELL_MS)
	if SettingsService.reduce_motion():
		ms *= REDUCE_MOTION_SCALE
	return ms / 1000.0


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


## A §14.2 beat's offset in seconds, under §14.5 like every other duration.
static func beat_seconds(beat: String) -> float:
	var ms: float = float(GOAL_SEQUENCE[beat])
	if SettingsService.reduce_motion():
		ms *= REDUCE_MOTION_SCALE
	return ms / 1000.0


## Applies [param name]'s curve to [param tween], so a caller cannot take the
## duration from the table and then invent its own easing.
static func shape(tween: Tween, name: String) -> Tween:
	return tween.set_trans(transition(name)).set_ease(ease_type(name))

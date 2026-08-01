# Design gaps — what stands between this and a game people love

A design critique, opened 2026-07-31 against `324e95e`. Everything in the spec is *specified* and
most of it is *built*. This document asks a different question: **why would anyone play a second
session?**

It is not a status file — [`TODO.md`](../../TODO.md) is the only place project status lives, and
where a finding is tracked there this file points at it rather than opening a second account of it.

Findings sort into three kinds, because they are not equally cheap to act on:

| Kind | Meaning |
|---|---|
| **Defect** | The spec asks for it, the code does not do it. Fix without asking. |
| **Regression** | A later decision undid something the spec had right. Amend the decision in Appendix C. |
| **Open** | The spec never asked. Needs a decision before it needs code. |

---

## Part 1 — closed

The defects and regressions have been fixed. Kept here in one line each, because a critique that
deletes its own findings loses the record of what kind of mistake keeps happening.

| # | Finding | Landed as |
|---|---|---|
| 1 | Ten of §15.2's sixteen SFX had a WAV, a bus, and no caller. Winning was silent | `f35e836` — plus `EV_GATE_OPENED`, which had no moment to attach to, and `AudioDirector.history`, without which CI cannot hear anything |
| 2 | The connectors were not drawn during play, so the line the game is named after was never on screen while it was being made | `68bfde6` — C-28 reversed as **C-30** |
| 3 | The connectors were ruled, straight, one weight; §13.1's "grows **and pulses**" had no pulse | `b44770c` — **C-31** |
| 4 | §6's standing portal tether was never drawn, so where a portal *went* was unknowable until you had used it | `a3b3f2c` |
| 5 | §7.2's tie-break counted one stage: `advance()` had a defaulted argument and the director took the default | `da0d356` |
| 6 | The level screen printed `endless_3`, `par 0` and a permanent `☆☆☆` outside the campaign, and offered an undo §5.9 removes | `32b0ef3` |
| 7 | Nineteen of §23.1's twenty achievements had no detection anywhere | `f141796` |
| 8 | `stats.playtime_seconds`, which §23.3 resolves cloud conflicts with, was never written | `62b1d3f` |
| 9 | §14.1's "banner slides 56 px up" was a bare `visible = true` | `a1a1cdf` |

**The pattern worth noticing:** every one of these is a thing the spec asked for that no test could
see the absence of. A sound nobody plays, an achievement nobody can earn, a stat nobody writes and a
tie-break of 0 against 0 all look exactly like the working version from inside a green suite. Where a
fix added a way to observe the thing — `AudioDirector.history`, the api-name table, the mode HUD
test — that is the actual repair; the wiring was the easy half.

---

## Part 2 — open, one decision each

Nine questions. Each states the problem, the options, a recommendation and what it costs. They are
roughly in order of how much they matter to whether the game has a hook, not of how cheap they are.

### D1 · Scoring is one axis, and it is pass/fail

**Decided 2026-08-01: fold into D2 and build a real second resource into the levels.** What follows
is the measurement taken while choosing, because it changes what D2 has to do.

**The problem.** `placements <= par` (§5.10), where `par` is the solver optimum over a **fixed** tile
sequence (§8.3). Three stars in campaign is not a decision, it is a search — and the loop to reach it
is undo-spam until the sequence is memorised. One number produces a search. Two numbers in tension
produce a game.

**What the shipped levels can support — measured, not guessed** (`tools/measure_slack.gd`):

- The optimal line spends the level's **entire** discard budget on 44 of 60 levels. Six levels grant
  none at all. So "finish with a discard unspent" is *incompatible with par* on 44 levels and
  *automatic* on 6.
- Granting every level one more discard: 32 of 60 gain slack, and **20 pars move**. Granting two: 41
  of 60, and **24 pars move**. A par that moves invalidates every star already earned on that level.
- Wilds exist only in chapter 5 (12 of 60), so "touch every wild" cannot be campaign-wide either.

**The reason, which is not about the levels at all.** `solver.gd:258` — *"Voluntary discard: costs a
charge, never a placement, so `g` is unchanged."* A discard is **free in the objective function**. The
solver will therefore spend every discard it is given, on every board, however the generator is
tuned. `discards` cannot become a resource by re-authoring, because the thing that consumes it is the
definition of par, not the shape of the board.

**So re-authoring alone does not produce the axis.** The correction is to make par count something a
discard costs — a second objective (`turn_par` = fewest `placements + voluntary discards`) computed
by the same solver with the discard branch costing 1 instead of 0. That conflicts with `par` by
construction, needs **no board regeneration and loses no stars**, and stores one integer per level.

**Still open for D2:** whether the second award rides `turn_par` (cheap, works on the shipped 60) or
a re-authored resource (expensive, and still needs the cost-function change to mean anything).

### D2 · Chapter 4 is where the curve collapses

**The problem.** Measured across the 60 shipped files:

| Ch | par | walls | goals | radius |
|---|---|---|---|---|
| 1 | 3–7 | 0–2 | 1 | 2, 3 |
| 2 | 6–8 | 4–8 | 1 | 3 |
| 3 | **10–14** | 5–9 | **2–3** | 3 |
| 4 | **6–9** | 6–10 | **1** | 3 |
| 5 | 10–15 | 8–14 | 2 | 3, 4 |

The hardest puzzle in the game is level 34 of 60. It then gets ~40% easier for twelve levels and
drops multi-goal entirely. §9 also asks for difficulty "monotonic in `par`" *within* a chapter and it
is not — chapter 1 peaks at par 7 and ends at 5, chapter 4 peaks at 9 and ends at 7.

**The genuine ambiguity, which is why this is not just a defect.** §6 says each modifier is
"introduced by one chapter and reused thereafter", and §9 introduces multi-goal at chapter 3 — but
§8.4's parameter table lists chapter 4's modifiers as "portals, gates" with no goal count. So whether
chapter 4 *should* be multi-goal is a question the spec answers twice. Per C7 that is a question, not
a licence.

**Options.** (a) §8.4 wins: chapter 4 stays single-goal and the par band is raised to 10–13 so the
curve still climbs. (b) §9 and §6 win: chapter 4 becomes multi-goal *and* gated/portalled, par 12–16.
(c) Reorder — move chapter 3 after 4, so mechanics arrive before the difficulty does.

**Recommendation: (b)**, with the authoring sweep in `tools/author_levels.gd` changed to enforce a
monotonic band **per slot** rather than one band per chapter, which is what let chapters 1 and 4 end
easier than their own middles.

**Cost.** Regenerating chapter 4 invalidates its stored pars and every star earned in it. That is an
offline `make levels` step and it is fine before release and not after — so this decision has a
deadline the others do not.

---

### D3 · Nothing is ever at stake

**The problem.** Every pillar in §2.2 removes punishment, and the sum removed the reason to care:
unlimited undo (§5.9), no fail state (§5.8), free auto-discard (§5.7), chapters unlocking at 8 of 12
(§7.1) — and **hints that are unlimited, free, and replay the solver** (§12.6). A player can hold `H`
repeatedly and be walked to a guaranteed ★★★; the only consequence is a small dot.

*Calm* and *stakeless* are not the same thing, and the game currently has no third option between "no
pressure" and "punishment".

**Options.** (a) Leave it — this is the stated character and the target player of §2.3 is here for
it. (b) Make the hint dot cost the third star rather than marking it, so a hint is a *choice*.
(c) Give the hint a cooldown or a per-level budget. (d) Keep campaign as-is and let D1's second axis
carry the stakes.

**Recommendation: (d) plus (b).** They compose: a second objective gives something to be careful
about, and a hint that costs the top band gives being careful a price. Neither adds a fail state.

---

### D4 · The board is mud

**The problem.** Empty cells, walls and gates all render as the same brown slab; a wall is separated
by hatching alone. Behind them is a painted backdrop more interesting to look at than the board is.
§2.2's first pillar is "readable in one glance", and the M3 grey-box satisfied it better than the
shipped art does. The C-26 pivot put *texture* where the design needed *signal*.

**Options.** (a) Widen the board's own value range so empty / wall / candidate / path sit at four
clearly different luminances. (b) Push the backdrop back — darker, lower contrast, more blur — and
leave the board as it is. (c) Both.

**Recommendation: (c)**, measured rather than eyeballed. `tests/unit/test_palette_vision.gd` already
simulates dichromacy and measures the decisions the game forces against WCAG 1.4.11's 3:1 floor; the
same harness can measure board-versus-backdrop separation, and it would have caught this.

**Cost.** Palette values plus a backdrop treatment. No structural change — §13.2's indirection means
this is a `.tres` edit and a token or two.

---

### D5 · The lookahead was traded away

**The problem.** §5.3 and §12.3 specify a preview of **current + next 2**. C-18's coin stack shows
current + next 1, because a coin under a coin has no readable face. Lookahead is the mechanism that
turns a random draw into a decision, so the trade cost §2.2's "constraint, not chaos" — the game now
feels *more* luck-driven than designed, in the mode meant to have no luck in it.

**Options.** (a) Find a second readable face — a fanned pair, an edge-on sliver with the arrow on the
rim, a small second slot beside the pile. (b) Accept the regression and amend §5.3 and §12.3 to say
one, so the spec stops claiming two.

**Recommendation: (a).** The fan is the cheapest and keeps the pile.

---

### D6 · Nothing accumulates where the player can see it

**The problem.** Detection and storage now work; display does not.

| Persisted | Shown? |
|---|---|
| Per-level stars / best / hinted | yes |
| Endless `best_goals`, daily streak | yes |
| Endless `runs` | **no** |
| `achievements_mirror` (all 20 now earnable) | **no — there is no achievements UI** |
| `stats.undos`, `playtime_seconds`, `total_placements`, `undo_free_streak` | **no** |

**Options.** (a) An achievements screen only. (b) One "Record" screen carrying achievements *and*
the stats. (c) Fold the numbers into the existing main menu and level select.

**Recommendation: (b).** It is one screen, `GameDirector.SCENES` takes a new entry, and every number
on it already exists in the save. Accumulation the player can see is the cheapest retention there is.

---

### D7 · Endless escalates by one wall and nothing else

**The problem.** Spec C-5 fixes this deliberately — "keep radius 3 and escalate walls only" — so the
shallowness is a decision, not an oversight. But a run that never introduces a gate, a portal, a wild
or a budget ends by attrition rather than by anything happening, and attrition is not a reason to
press Retry. Endless is also where the game's actual fantasy lives (§2.1's "the direction you were
given, not the one you wanted"), and it got the least attention.

**Options.** (a) Hold C-5. (b) Introduce one modifier per threshold — gates at 5 goals, portals at
10, a budget at 15, radius 4 at 20 — reusing the campaign's own ladder. (c) Escalate the *stream*
instead: shrink the bag, so draws get less fair as the run goes on.

**Recommendation: (b).** It reuses §6 exactly, needs no new rules, and gives a run named thresholds
to remember and to tell someone about.

---

### D8 · The daily has no way to compare

**The problem.** §7.3's whole premise is "a shared board is comparable between players". The
comparison mechanism is a leaderboard, and the leaderboard is a stub pending GodotSteam. There is no
share string either, and the spec never asks for one.

**Options.** (a) Wait for Steam. (b) Add a share string — a hex-shaped emoji grid of the solved
route, clipboard-only, no server. (c) Both.

**Recommendation: (c)**, with (b) first, because it does not depend on a GDExtension landing and it
is the cheapest viral loop in puzzle games.

---

### D9 · There is no world

**The problem.** Chapter names are mechanic labels — `"Flow", "Walls", "Branches", "Gates & Portals",
"Pressure"` (`level_select.gd:19`). Levels have no names; the frozen JSON has no field for one. Five
commissioned paintings — forest, coast, mountains, ruins, a castle on the horizon — sit behind the
game with nothing connecting them and nothing to reach.

The only voice in the entire design is §23.1's hidden `the_long_way`, *"complete a level using at
least par + 15 placements (hidden, affectionate)"* — and that one line has more personality than
every other string in the build combined.

**Options.** (a) Leave it abstract. (b) Name the chapters after their places and let the level-select
journey visibly travel toward the castle. (c) (b) plus per-level names in the level files.

**Recommendation: (b).** It costs five strings and a map treatment, needs no new systems, and it is
the difference between five backdrops and a place.

---

## What is already good, and should not be traded away

A list of gaps reads as a verdict, and this one is not:

- **The pentatonic ascent that steps back down on undo** (`audio_director.gd:195-220`). A long path
  becomes a melody and taking a move back *sounds* like taking it back.
- **The daily streak pips** — seven marks with today on the right, so the display answers "have I
  played today" and not merely "how many days".
- **`test_palette_vision.gd`** simulates dichromacy and measures the decisions the game forces
  *after* the simulation. Almost nobody does this, and it found three real defects on its first run.
- **The layering discipline.** Every fix in Part 1 was cheap *because* the rules are a pure core with
  a test suite around them.

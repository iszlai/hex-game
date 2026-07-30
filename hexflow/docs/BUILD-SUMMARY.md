# Hexflow build summary

What exists, what does not, and what was learned building it. Written 2026-07-30.

Companion documents: [`ARCHITECTURE.md`](ARCHITECTURE.md) for the codebase tour,
[`../../HEXFLOW-SPEC.md`](../../HEXFLOW-SPEC.md) for the authoritative design.

---

## 1. Scope delivered

The specification defines twelve milestones for a commercial release. This build covers the first
four plus the data half of the sixth, following the spec's **non-negotiable build order**: the pure
logic core and its tests exist before any rendering, because the 2016 prototype died from the
opposite approach.

| Milestone | State | Exit criterion |
|---|---|---|
| **M0** Skeleton | done | Godot 4.7.1 pinned, §16.4 layout, six autoload stubs, GUT wired, CI running headless |
| **M1** Logic core | done | Every `@core` scenario of §24.2 passes headlessly; banned-API grep clean; zero engine imports in `src/core/` |
| **M2** Generator & solver | done | `@property` sweep green; solver returns par on all fixture levels |
| **M3** Grey-box playable | done | A radius-3 level is completable with a keyboard; win and dead states reachable |
| **M6** Campaign data | half | 60 levels generated, verified and frozen. Level-select map and chapter unlocks not built |
| M4, M5, M7–M11 | not started | — |

### Numbers

| | |
|---|---|
| Tests | 76, all green |
| Assertions | 11,092 |
| Suite runtime | ~50 s (`@core` ~2 s, `@property` ~45 s, `@e2e` ~3 s) |
| Campaign levels | 60, each solver-verified and re-verified on every push |
| Core modules | 11, all headless-testable, zero engine dependencies |

---

## 2. What is playable right now

`make run` boots to chapter 1 level 1 from the frozen campaign data and gives a complete core
loop on the keyboard: cursor navigation with snap-to-candidate, bumper-style cycling, placement,
undo, discard, restart, wild spend, and a working hint that replays the solver from the live
position.

The board renders as untextured hexes: pointy-top layout with start bottom-left and goal top-right
exactly as the 2016 prototype laid them out, the path growing as one continuous shape with a
depth gradient, walls hatched at 45°, goals ringed, portals double-ringed, gates and wilds
glyphed. Every modifier is identified by glyph *and* shape *and* colour, never colour alone.

Win, dead-state and auto-discard all surface in the banner. A dead board offers undo and restart —
campaign has no failure state.

---

## 3. Two defects in the specification

Both were found by the property sweep rather than by reading the spec, which is the argument for
that sweep existing. Both are logged in Appendix C and fixed in the implementation.

### C-10 — the solver heuristic was inadmissible

§8.3 specifies `h = sum over unreached goals of the minimum distance from the path`. Summing is not
admissible when a single placement shortens the route to two goals at once, because it can
overestimate the remaining cost. An inadmissible heuristic makes A* return a path that is not
optimal — so `par` would not have been the true minimum.

That matters because §5.10 defines ★★★ as `placements <= par` and asserts three stars are "always
attainable and never luck-dependent". A too-high par quietly makes every level easier than
designed, and no test would have noticed.

Changed to `max` over goals: admissible, since a placement reduces any one goal's distance by at
most 1, and still a strong bound in practice.

### C-14 — stored solutions were not replayable

§17.1 stores `solution` as "the solver's optimal target order". But an optimal line sometimes has
to spend a voluntary discard on a useless tile, and a bare target list cannot express that. Replay
it and the stream desynchronises at the discard, so every subsequent placement is illegal.

This surfaced as the property sweep failing on 3 of 7 tests with "replaying (0,2,-2) must be
legal". Without the sweep it would have shipped as a level file that claimed a solution it could
not demonstrate.

Added `solution_script`: `[kind, cube]` pairs where kind is place / wild / discard. `solution` is
unchanged and derived from it, so §17.1 still holds.

### Seven smaller underspecifications

Logged as C-9, C-11, C-12, C-13, C-15, C-16 and C-17: where `tiles`/`par` live, gate placement
during generation, Endless stage seeding, float layout math being moved out of the core, whether a
wild spend consumes the drawn tile, undo history across a suspend, and a non-terminating
auto-discard loop when a goal is reachable only through an unsatisfiable gate.

Per constraint C7, each took the simplest workable option and was recorded rather than invented
silently.

---

## 4. How the prototype's defects were closed

Appendix B catalogues twelve real bugs in the 2016 code. They are the traps a re-implementation
falls into, so each one is worth checking against.

| # | Prototype defect | Closed by |
|---|---|---|
| B1 | Coordinate type lost `equals`/`hashCode`; every grid lookup returned null | `Vector3i` keys — value-comparable by construction, so the bug is not expressible |
| B2 | Obstacles sampled from indices including the goal cell | Generator step 7 verification + the `@property` sweep asserting no wall on a start or goal |
| B3 | No solvability check of any kind | `solver.gd`, mandatory before any candidate is accepted; `UNKNOWN` counts as rejection |
| B4 | Rules and rendering lived together in the screen class | `core → app → view` layering, grep-enforced in CI |
| B5 | A new `Texture` allocated per tile draw, never freed | Geometry prebuilt in `bind()`; nothing allocates in `_draw` |
| B6 | Results screen hardcoded `currentLevel = 0` | `GameDirector` owns progression; the `@e2e` playthrough asserts completion is recorded |
| B7 | Touch used raw screen coordinates against a transformed viewport | All hit-testing routes through `HexLayout.from_pixel` |
| B8 | `getRandomSide()` computed `((random * 6) % 10)` | Bag algorithm with canonical Fisher-Yates; global RNG banned and grep-enforced |
| B9 | Row generator produced `length + 1` entries | Board built from the set definition `max(|x|,|y|,|z|) <= R`, not row loops |
| B10 | No fail state, undo, scoring, persistence or audio | Dead state, unlimited undo, stars, save service; audio is M7 |
| B11 | Board dimensions hardcoded in seven `addRow` calls | Radius is a parameter; tests cover radius 2, 3 and 4 |
| B12 | Clicked cell did not join the path; any cell was clickable | §5.4 injectivity — one anchor per target, so a confirm is unambiguous |

---

## 5. Guardrails

`make gate` is what CI runs. It fails a push on any of:

- any `@core`, `@property` or `@e2e` test failing
- a global `randi()` / `randf()` / `randomize()` anywhere in `src/`
- float arithmetic in `src/core/`
- a node, scene, texture or `Input` reference in `src/core/`
- an autoload count other than six
- a script error during headless boot

The greps ignore comments, so a rule stated in a doc comment does not trip the rule it documents.
The gate was verified to actually bite by introducing a `randi()` call into `scoring.gd` and
watching it go red.

Not yet enforced: the §22 string-literal check is scaffolded but skips until `assets/i18n/en.csv`
exists, since UI strings are still literals pending M10.

---

## 6. What is deliberately not built

| Area | Milestone | Note |
|---|---|---|
| Gamepad and touch input, haptics, glyph atlas, Steam Input action sets | M4 | `InputRouter` already implements snap and free cursor modes and clockwise cycling; only the device bindings are missing |
| Settings screens, suspend/resume wiring | M5 | `SaveService` and `SettingsService` exist with atomic writes, migration and corruption recovery; no UI |
| Level-select hex-flower map, chapter unlocks | M6 | The 60 level files exist and load |
| Shaders, palette swaps, typography, all §14 animation, all §15 audio | M7 | `BoardView._draw` is the grey-box that M7 replaces; the seam is the `_draw` body only |
| Tutorial beats T1–T12 | M8 | Must be data-driven from `src/data/tutorial.json`, not hardcoded |
| Endless and Daily screens, achievements, leaderboards, cloud | M9 | The *logic* for both modes exists and is tested; neither has a screen |
| Alternate palettes, text scaling, Reduce Motion, i18n extraction | M10 | The palette resource indirection is already in place for the swap |
| Deck self-audit, store page, depots | M11 | — |

`assets/` is an empty directory tree. No fonts, SFX or music are vendored. §13.4 requires SIL-OFL
fonts embedded in the project before M7.

---

## 7. Suggested next step

**M4, input and Deck.** It is the highest-value increment: the game is already fully playable, so
making it playable on a controller turns a grey-box into something that can be handed to a person
to try. `InputRouter` is written and tested for the hard part — directional input over a hex
lattice — so M4 is mostly bindings, an action-set switch, a glyph atlas and haptics.

M7 should stay where the spec puts it, after content. Polishing a game whose levels do not exist
wastes the polish.

---

## 8. Repository layout note

The 2016 libGDX prototype still occupies the repository root and is preserved on the
`legacy/libgdx-2016` branch. Once `hexflow/` no longer needs the old sources as reference — chiefly
the tile art that Appendix A's direction table is verified against — the legacy tree can be deleted
from `master` and will live on in that branch and in history.

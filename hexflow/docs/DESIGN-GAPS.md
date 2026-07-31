# Design gaps — what stands between this and a game people love

A design critique, written 2026-07-31 against the build at `324e95e`. Everything in the spec is
*specified*; most of it is *built*. This document is about a different question: **why would anyone
play a second session?**

It is deliberately not a status file. [`TODO.md`](../../TODO.md) is the only place project status
lives, and nothing here restates it. Where a gap is already tracked there, this file says so and
points at it rather than opening a second account of the same thing.

Three kinds of item appear below, and the distinction matters because they are not equally cheap to
act on:

| Kind | Meaning |
|---|---|
| **Defect** | The spec asks for it, the code does not do it. Fix without asking. |
| **Regression** | A later decision undid something the spec had right. Amend the decision in Appendix C. |
| **Open design** | The spec never asked for it. Needs a decision before it needs code. |

---

## 1. Nothing flows — *regression*

The elevator pitch (§2.1) is "grow a **glowing path** across a honeycomb board". §13.1 asks for "a
single continuous line of light". §14.1 budgets a 160 ms connector-draw beat for every placement.

None of it is on screen while the player is playing. Two causes:

- **C-28 hides the ribbon until the level is won.** `board_links.gd:225-238` — `draw_newest()`
  returns immediately during play (`if _traced <= 0.0: return`), and the whole route traces itself
  as a victory flourish instead. So §14.1's connector beat never fires while a connector is being
  made.
- **When it does draw, it is 6% brighter than the tile beneath it.** `board_links.gd:40`,
  `LINK_LIGHTEN := 0.06`.

The result is that the player's creation is a scatter of tinted hexes for the entire duration of the
creating, and the one image the game is named after arrives only after every decision is over. The
trace should be a *reprise* of something watched growing, not the first sight of it.

**Do:** draw the connector on commit, at a lightness that reads. Keep the win trace — it is a good
idea in the wrong slot. Amend C-28 rather than deleting it.

## 2. The board is mud — *regression*

Empty cells, walls and gates all render as the same brown slab; a wall is separated by hatching
alone. Behind them is a painted forest that is more interesting to look at than the board is. Pillar
#1 is "readable in one glance" (§2.2) and the grey-box of M3 satisfied it better than the shipped art
does.

This is not an argument for going back to `neon_dark`. It is an argument that the C-26 pivot put
*texture* where the design needed *signal*: the board needs its own value range, clearly separated
from the backdrop, with empty / wall / candidate / path at four genuinely different luminances.
`test_palette_vision.gd` already knows how to measure exactly this — it is the tool for the job.

## 3. The biggest moments are silent — *defect*

**Ten of the sixteen SFX in §15.2 are authored, loaded, indexed in `AudioDirector.SFX`, and never
played by anything:** `goal.reach`, `level.win`, `level.dead`, `tile.advance`, `tile.discard`,
`tile.autoskip`, `wild.pickup`, `portal.link`, `gate.open`.

Winning a level is a 2 px shake, a route trace and a banner, with no sound but the music duck.

This is the cheapest large improvement available and it is a straight defect — the spec names the
event for each one.

## 4. The lookahead was traded away — *regression*

§5.3 and §12.3 specify a preview of **current + next 2**. The C-18 coin stack shows current + next 1,
because a coin under a coin has no readable face, and TODO.md records the trade as deliberate.

Lookahead is the mechanism that converts a random draw into a decision. Trading it for a visual
traded away pillar #2, "constraint, not chaos" — the game now feels *more* luck-driven than it was
designed to be, in the mode that was supposed to have no luck in it at all.

**Do:** find a second readable face — a fanned pair, an edge-on sliver with the arrow on the rim, a
small second slot beside the pile — or accept the regression explicitly in Appendix C rather than
leaving the spec saying two.

---

## 5. Nothing is ever at stake — *open design*

Every pillar in §2.2 is about removing punishment, and the sum of them removed the reason to care:

- unlimited undo (§5.9)
- no fail state — a dead board is a recoverable banner (§5.8)
- free auto-discard on an impossible draw (§5.7)
- chapters unlock at 8 of 12, so nobody is ever blocked (§7.1)
- **hints are unlimited, free, and replay the solver** (§12.6)

That last one dissolves the star economy on its own: a player can hold `H` repeatedly and be walked
to a guaranteed ★★★, and the only consequence is a small dot on the level cell.

None of these should simply be reversed — they are the game's stated character, and they are why the
target player (§2.3) is here. But *calm* and *stakeless* are not the same thing, and right now the
game has no third option between "no pressure" and "punishment".

## 6. Scoring is one axis, and it is pass/fail — *open design*

`placements <= par`, where `par` is the solver optimum over a **fixed** tile sequence (§5.10, §8.3).
So in campaign, three stars is not a decision — it is a search, and the loop to reach it is
undo-spam until the sequence is memorised.

One number produces a search. Two numbers in tension produce a game. Candidates that cost nothing
structurally: touch every wild, finish with discards unspent, a bonus for route length, a par for
*turns* distinct from par for placements.

## 7. The difficulty curve collapses at chapter 4 — *defect*

Measured across the 60 shipped level files:

| Ch | par | walls | goals | radius |
|---|---|---|---|---|
| 1 | 3–7 | 0–2 | 1 | 2, 3 |
| 2 | 6–8 | 4–8 | 1 | 3 |
| 3 | **10–14** | 5–9 | **2–3** | 3 |
| 4 | **6–9** | 6–10 | **1** | 3 |
| 5 | 10–15 | 8–14 | 2 | 3, 4 |

The player's hardest puzzle is level 34 of 60. The game then gets ~40% easier for twelve levels, and
drops multi-goal entirely — which §9 says is introduced in chapter 3 and "reused thereafter".

§9 also asks for difficulty "monotonic in `par`" within a chapter, and it is not: chapter 1 peaks at
par 7 and ends at 5, chapter 4 peaks at 9 and ends at 7.

**Do:** re-author chapter 4 against a par band that sits between 3 and 5 and keeps multi-goal, and
make the authoring sweep in `tools/author_levels.gd` enforce a monotonic band per slot rather than a
single band per chapter. This invalidates chapter 4's stored pars and stars — an offline `make
levels` step, fine before release and not after.

## 8. Nineteen of twenty achievements have no detection — *defect*

§23.1 lists twenty. The only `unlock_achievement` call site in the codebase is
`game_director.gd:419`, `"first_flow"`. There is also no achievements UI anywhere, so
`achievements_mirror` is write-only from the player's side.

On Steam, achievements *are* the retention layer. Detection needs no GodotSteam — the mirror and the
local queue already work, and TODO.md M9 tracks the link separately.

## 9. Nothing accumulates, and what does is not shown — *open design*

| Persisted | Shown? |
|---|---|
| Per-level stars / best / hinted | yes — map and menu |
| Endless `best_goals` | yes — menu row, run summary |
| Daily history and streak | yes — seven pips, the best UI in the build |
| Endless `runs` | **no** |
| `achievements_mirror` | **no** |
| `stats.undos` | **no** |
| `stats.playtime_seconds`, `stats.total_placements` | **never even written** |

There is no profile or stats screen. Longest path, levels three-starred, hint-free completions, best
daily streak — all of it is either already in the save or one counter away, and none of it is
visible. Accumulation the player can see is the cheapest retention there is.

## 10. The daily has no way to compare — *open design*

§7.3's whole premise is "a shared board is comparable between players". The comparison mechanism is a
leaderboard, and the leaderboard is a stub (TODO.md M9). There is no share string either, and the
spec never asks for one — but a hex path is an unusually good fit for the cheapest viral loop in
puzzle games, and it needs no server.

## 11. Endless escalates by one wall and nothing else — *defect, plus open design*

Spec C-5 fixes this deliberately ("keep radius 3 and escalate walls only"), so the shallowness is a
decision rather than an oversight — but three things around it are not:

- **`total_placements` is always zero.** `endless_run.gd:advance()` takes
  `placements_this_stage: int = 0` and the only production call site,
  `game_director.gd:426`, passes nothing. That number is the leaderboard tiebreak.
- **The endless and daily HUD is wrong.** `level.gd:_refresh_hud()` resolves the title through
  `LevelRepository.locate()`, which returns `ZERO` for `endless_3`, so the top bar prints the raw id.
  Score reads `placements 7 / par 0`, and because `Scoring.stars()` returns 0 for `par <= 0` the live
  star band shows a permanent `☆☆☆`.
- **The dead banner offers Undo** in a mode where `undo_available()` is false.

The open-design part is whether C-5 still deserves to hold. A run that never introduces a gate, a
portal, a wild or a budget ends by attrition rather than by anything happening, and attrition is not
a reason to press Retry.

## 12. There is no world — *open design*

Chapter names are mechanic labels: `"Flow", "Walls", "Branches", "Gates & Portals", "Pressure"`
(`level_select.gd:19`). Levels have no names — the frozen JSON has no field for one. Five
commissioned paintings of a forest, a coast, mountains, ruins and a castle on the horizon sit behind
the game with nothing connecting them and nothing to reach.

The only piece of voice in the entire design is a hidden achievement in §23.1 — *"the_long_way:
complete a level using at least par + 15 placements (hidden, affectionate)"* — and it is not
implemented.

Naming the chapters after their places, giving the levels names, and letting the level-select journey
visibly go somewhere costs no new systems and is the difference between five backdrops and a place.

---

## What is already good, and should not be traded away

Worth stating, because a list of gaps reads as a verdict and this one is not:

- **The pentatonic ascent that steps back down on undo** (`audio_director.gd:195-220`). A long path
  becomes a melody and taking a move back *sounds* like taking it back. It is the only thing in the
  build that makes move eight feel different from move two, and it is doing that work alone.
- **The daily streak pips** — seven marks with today on the right, so the display answers "have I
  played today" and not merely "how many days".
- **`test_palette_vision.gd`** simulates dichromacy and measures the decisions the game forces
  *after* the simulation. Almost nobody does this, and it found three real defects on its first run.
- **The layering discipline.** Every gap above is fixable *because* the rules are a pure core with a
  test suite around them.

---

## Suggested order

Cheapest and largest first; the numbers refer to the sections above.

1. §3 — fire the ten dead SFX.
2. §11 — the endless HUD, the tiebreak, the dead banner.
3. §1 — draw the connector during play.
4. §8 — the other nineteen achievements.
5. §2 — separate the board's value range from the backdrop.
6. §9 — write and show the stats that already exist.
7. §6, §7 — the second scoring axis and chapter 4. These decide whether the game has a hook, and
   both need a decision before they need code.
8. §12, §10 — names, places, and a way to compare a daily.

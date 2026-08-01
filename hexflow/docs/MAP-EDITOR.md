# Map editor — specification

A developer tool for drawing campaign boards by hand, checking them, and saving them
into `src/data/levels/`. Not built yet; this is the brief.

---

> **Status:** a **pre-release developer tool**. Levels it produces may ship as ordinary campaign
> content, exactly as the sweep's do — what never ships is the editor itself. See §0 and §8.

## 0. What this is, and what §27 forbids

§27 lists **"Level editor / Steam Workshop"** as an explicit non-goal — *"content-rich scope was
declined; revisit only post-launch if the game sells."*

That non-goal is about a **player-facing** editor: a screen in the shipped game, levels shared between
players, Workshop integration, the moderation and compatibility burden that comes with all of it. None
of that is proposed here.

This is an **authoring tool**, in the same category as `tools/author_levels.gd`, `tools/make_sfx.gd`
and `tools/make_art.gd`: it runs from the repo, it is not in the export, and its output is committed
JSON that the game then treats as frozen data. §9 already describes an authoring workflow; this gives
that workflow a pair of hands.

The distinction has to be enforced, not just asserted — see §8.

---

## 1. Why

`tools/author_levels.gd` generates candidates and scores them against the curve (C-33). It is good at
producing *many* boards and bad at producing a *particular* one. Three things it cannot do:

- **Make a board that means something.** A ring whose two goals sit opposite each other, a Z whose
  portal jumps the diagonal — these are compositions, and a sweep finds them only by accident.
- **Fix one level.** Today the only lever is a different seed, which changes the whole board.
- **Reorder the campaign.** Level order is a design decision and is currently whatever the sweep
  wrote into which filename.

The sweep stays. It is the right tool for filling 50 slots. The editor is for the 10 that carry the
chapter.

---

## 2. Where it lives

```
hexflow/tools/map_editor/map_editor.tscn     the scene
hexflow/tools/map_editor/*.gd                its scripts
make edit-maps                               runs it
```

It runs as a normal Godot scene rather than a `-s` MainLoop script, because it needs input, a UI and a
render — the three things a MainLoop script does not get. It may use the game's autoloads.

**It may not be reachable from the game.** No entry in `GameDirector.Screen`, no row on any menu, and
`tools/` is excluded from the export preset (§8).

---

## 3. Screen

```
┌──────────────────────────────────────────────┬──────────────────┐
│  ← chapter 3 · level 07 ·  ideal 11          │  BRUSH           │
│                                              │   ▢ board        │
│                                              │   ▨ wall         │
│              the hex canvas                  │   ◆ start        │
│              (pan, zoom, paint)              │   ◎ goal         │
│                                              │   ⊙ portal A / B │
│                                              │   ⌸ gate         │
│                                              │   ★ wild         │
│                                              │                  │
│                                              │  BOARD           │
│                                              │   shape  [ring ]│
│                                              │   size   [ 4 ]  │
│                                              │   arg    [ 1 ]  │
│                                              │   discards [2]  │
│                                              │   budget   [–]  │
├──────────────────────────────────────────────┤                  │
│  TILES  NE NE E SE · SW W NE …    [fill]     │  [ validate ]    │
├──────────────────────────────────────────────┤  [ save     ]    │
│  ✓ solvable · ideal 11 · 3 routes · 58% kind │  [ levels…  ]    │
└──────────────────────────────────────────────┴──────────────────┘
```

The canvas draws with the game's own `BoardView3D` if that is cheap, and with a flat 2D hex draw if it
is not. **The renderer is not the point** — the editor may look nothing like the game as long as every
cell's contents are unambiguous. `HexLayout` is reused either way, so there is still exactly one
hexagon formula in the repo.

---

## 4. Editing

### 4.1 Two brushes, not one

There are two different edits and conflating them is the usual way a hex editor becomes confusing:

| Brush | Changes | Notes |
|---|---|---|
| **Board** | whether the hex is part of the level at all | Painting off-board removes the cell; painting on adds it |
| **Contents** | what is on a cell: empty, wall, start, goal, portal, gate, wild | Only meaningful on a cell that is on the board |

Left-drag paints, right-drag erases to the brush's default (off-board, or empty).

### 4.2 The constraints the editor enforces live

Enforced as you draw, because discovering them at Validate is discovering them too late:

- **At most 61 cells.** The solver's path mask is 64-bit (C-19). The count is always on screen and
  turns red at 61; painting past it is refused.
- **Exactly one start.** Placing a second moves the first.
- **At least one goal.** Removing the last one is allowed but flagged.
- **Portals come in pairs.** The brush alternates A/B and a lone A is flagged.
- **The board is one piece.** A cell painted with no neighbour is allowed while drawing and flagged at
  rest — cutting a board in two is a real mistake and never an intent.

### 4.3 Shapes are a starting point, not a cage

Picking a shape from the dropdown fills the canvas with `Hex.shape(kind, size, arg)` (C-32). From
there any cell may be added or removed.

**This forces a schema decision.** A level file today stores `shape`, `radius` and `shape_arg` — three
numbers that regenerate the board. A hand-edited board is not regenerable from three numbers.

> **Proposal:** add an optional `cells: [[x,y,z], …]` to the level schema. When present it *is* the
> board and `shape` becomes a label for what it started as. When absent — every level today — the
> shape fields build the board exactly as they do now. `LevelRepository.from_dict` prefers `cells`;
> `to_dict` writes it only when the board diverges from its named shape, so a sweep-authored ring
> stays three numbers and only hand-drawn boards pay the sixty lines.

### 4.4 The tile sequence

The hardest part, and the reason a naive editor produces unplayable levels.

A board is not a level. §5.3 needs `tiles`: the fixed sequence of directions the player is dealt. You
cannot paint that, and a board with the wrong sequence is unsolvable no matter how good it looks.

Three ways to get one, in the order they should be offered:

1. **Fill** *(the default)* — run the solver on the board with an unbounded bag, take the directions
   of its optimal route, then pad and interleave decoys exactly as `Generator` step 6 does. One
   button, always produces a solvable level, and its `slack` and `discards` come from the panel.
2. **Edit** — the sequence is a text field of direction names. Typing in it is how a level gets a
   *deliberate* rhythm: three norths in a row, or the awkward tile arriving one turn early.
3. **Keep** — loading an existing level keeps its sequence, so the board can be edited around a
   sequence that already works.

Fill must be re-runnable after any board edit, and the editor should say so when the board has changed
since the sequence was made.

---

## 5. Validate

One button. It runs what CI runs, and reports what the campaign is authored against.

| Check | Source | Failure reads |
|---|---|---|
| Structure | `Board.validate()` | "goal at (2,-4,2) is a wall" |
| Solvable | `Solver.solve()` | "no route reaches both goals" |
| Ideal | the same solve | "ideal 11" |
| Ways through | `LevelMetrics.routes_at_ideal()` | "3 routes" — or "too big to measure" |
| Forgiveness | `LevelMetrics.forgiveness()` | "58% of wrong turns recoverable" |
| Against the curve | `DifficultyCurve.distance()` | "slot wants 4 routes and 62%; this is 3 and 58%" |

Two things this must not do:

- **It must not accept `UNKNOWN`.** The solver returning "I could not finish" is a rejection, exactly
  as §8.2 step 7 treats it. A board nobody can rank is a board nobody should ship (C-33).
- **It must not silently pass a board that is merely solvable.** Solvable is the floor. The curve
  numbers are the point, and they are shown whether or not the author asked.

Validate is also bound to a key and runs on demand, not on every edit — the metrics take seconds.

---

## 6. Save

Writes `src/data/levels/chapter_N/level_MM.json` through `LevelRepository.to_dict`, so the editor and
the sweep produce byte-comparable files.

**Save refuses on a failed Validate.** Not a warning — a refusal. The one thing this tool must never
do is put an unsolvable level into frozen data, because the property test that would catch it runs
later, in CI, after the commit.

Saving stamps `metrics.routes` and `metrics.forgiving` from the Validate that passed, so a hand-drawn
level carries the same authoring record as a swept one and CI's curve check covers both.

---

## 7. Levels: pick and reorder

The **levels…** button opens a list of all 60: chapter, index, shape, ideal, routes, forgiveness, and
how far each sits from its slot on the curve.

- **Click** loads a level into the canvas.
- **Drag** reorders, within a chapter or across chapters.
- **Apply order** rewrites the files.

### 7.1 Reordering is safe now and unsafe later — **decided: pre-release only**

The game remembers progress like this:

```
"c3_l07"  ->  3 stars, best 11 moves, hint used
"c3_l08"  ->  2 stars, best 14 moves
```

`c3_l07` means **chapter 3, slot 7**. It names a *position*, not a level — `LevelRepository.id_for`
builds it from the chapter and index, and `SaveService` keys everything on it.

So dragging the level out of slot 7 does not take its stars with it. The stars stay on the slot, and
whatever lands there inherits them. A player who has never seen the new level 7 opens it already
three-starred, and the level they actually earned those stars on now shows blank.

**Before release this costs nothing.** There is one save, it belongs to the developer, and
`make playtest` already moves it aside. Reorder freely.

**After release it is data loss**, and the trap is narrower than it looks:

- **Appending** levels to the end of a chapter is safe. Nothing moves, so no id changes hands.
- **Inserting or reordering** shifts every level after the change, and every one of them swaps
  progress with its neighbour.

So the tool is **pre-release only**, and the rule for shipping content later is *append, never
insert*. `Apply order` refuses when the build is a release build and says why.

If the campaign ever does need reordering after release, the fix is a stable identity: a short `uid`
written into each level file once and never reused, with progress keyed on the uid and position
demoted to presentation. That costs a schema field, a save migration (§18.4 already has the
machinery) and a one-off pass over the existing sixty. Worth paying then, not now — building it
before anything needs it is a migration written against a guess.

## 8. Keeping it out of the game

§27's non-goal is only respected if the tool cannot become a feature by accident:

- `tools/` is added to the export preset's exclude filter, and a test asserts the filter contains it.
- `ci_gate.sh` greps `src/` for references to `tools/` and fails on any. The dependency runs one way,
  the same way `src/core/` → `src/app/` → `src/view/` does.
- The editor may read `src/`. Nothing in `src/` may read the editor.

---

## 9. Deliberately not in scope

| Not doing | Why |
|---|---|
| Undo/redo history | Save-and-reload covers it; a full command stack is most of the tool's cost for a fraction of its value |
| Playtesting inside the editor | `make run` already plays the level that was just saved |
| Editing endless or daily boards | Both are generated from a seed at runtime (§7.2, §7.3); there is nothing to edit |
| Painting the tile sequence graphically | A text field is faster and unambiguous |
| Any player-facing entry point | §27 |

---

## 10. Open questions

- **Q1 — canvas renderer.** Reuse `BoardView3D` (accurate, heavier, and its `bind()` wants a live
  `GameState` the editor does not have) or a flat 2D draw (cheap, and a second way of drawing a board
  to keep in step)? Leaning 2D, since the editor is about *contents* and the game is about *feel*.
- **Q2 — the `cells` schema field** of §4.3: add it now, or keep the editor to shapes-plus-walls until
  a hand-drawn silhouette is actually wanted? Walls can fake almost any shape, and the difference is
  visible: a removed cell has no tile, a wall has a hatched one.
- **Q4 — where a hand-drawn level's `generator.seed` goes.** It has none. Null, or a hash of the
  cells so the field stays non-empty and the file stays diffable?

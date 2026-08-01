# Map editor — specification

A developer tool for drawing campaign boards by hand, checking them, and saving them
into `src/data/levels/`. **Built** — `make edit-maps`, `hexflow/tools/map_editor/`. This stays the
brief: it is what the tool is meant to be, and [`TODO.md`](../../TODO.md) is what is done.

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
│  ← chapter 3 · level 07 ·  ideal 11          │  MODE            │
│                                              │   [paint] [trace]│
│                                              │  BRUSH           │
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
├──────────────────────────────────────────────┤  [ new      ]    │
│  ✓ solvable · ideal 11 · 3 routes · 58% kind │  [ open…    ]    │
└──────────────────────────────────────────────┤  [ save slot]    │
                                               │  [ save as… ]    │
                                               │  [ levels…  ]    │
                                               └──────────────────┘
```

**The canvas is flat 2D — decided.** Coloured hexes, one colour per contents, with the modifier's
letter or glyph on top. It may look nothing like the game.

That is not only the cheaper option, it is the correct one: the editor is about *contents* and the
game is about *feel*. A board drawn at the game's 55° elevation hides half of what an author needs to
see — the far side of a tall wall, the cell behind a mark — and an editor whose job is to show every
cell exactly should not be fighting a camera to do it.

`HexLayout` is reused for the geometry, so there is still exactly one hexagon formula in the repo.
`Palette` is reused for the colours, so an editor board and a game board are recognisably the same
level.

---

## 4. Editing

### 4.1 Two brushes, not one

There are two different edits and conflating them is the usual way a hex editor becomes confusing:

| Brush | Changes | Notes |
|---|---|---|
| **Board** | whether the hex is part of the level at all | Painting off-board removes the cell; painting on adds it |
| **Contents** | what is on a cell: empty, wall, start, goal, portal, gate, wild | Only meaningful on a cell that is on the board |

Left-drag paints, right-drag erases to the brush's default (off-board, or empty).

### 4.1.1 Two modes above the brushes — **added after first use**

A click on the canvas means one of two things, and which one is a **mode**, not a brush:

| Mode | A left click | A right click |
|---|---|---|
| **paint** (1) | paints the selected brush | erases to the brush's default |
| **trace** (2) | lays the next tile of the sequence | takes the last one back |

The brush palette greys out in trace mode rather than disappearing, because a rail that reflows on
a mode switch moves every other button out from under the cursor.

Why a mode and not a brush: the trace is not an edit to a cell. It is an ordered walk over cells
that are already there, it can pass the same cell's neighbours twice, and its right-click undoes
rather than erases. A "route brush" in the §4.1 list would be the third meaning of a left-drag
hiding inside a control that promises two. See §4.4's fourth option for what it produces.

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

**This forces a schema decision, and it is really a design question wearing a schema costume.**

A level file today describes its board in three numbers — `shape`, `radius`, `shape_arg` — which the
game reads to rebuild it. A board that has had cells added or removed by hand is not describable in
three numbers; the file would have to list every hex, up to sixty-one lines of coordinates.

**Decided: an author may remove cells**, so the `cells` field below is required rather than optional
to the design. The two are different things on screen and both are wanted:

| | What the player sees |
|---|---|
| **Removed cell** | Nothing. Empty space, and §13.7's painted backdrop showing through |
| **Wall cell** | A tile *is* there — dark, hatched, standing at C-22's wall height. Part of the board, and unusable |

Walls can fake almost any silhouette, so the board brush of §4.1 is optional in a way the contents
brush is not.

> **The field:** an optional `cells: [[x,y,z], …]`. When present it *is* the board and
> `shape` becomes a label for what it started as. When absent — every level today — the shape fields
> build the board exactly as they do now. `LevelRepository.from_dict` prefers `cells`; `to_dict`
> writes it only when the board diverges from its named shape, so a swept ring stays three numbers
> and only hand-drawn boards pay the sixty lines.

### 4.4 The tile sequence

The hardest part, and the reason a naive editor produces unplayable levels.

A board is not a level. §5.3 needs `tiles`: the fixed sequence of directions the player is dealt. You
cannot paint that, and a board with the wrong sequence is unsolvable no matter how good it looks.

Three ways to get one, in the order they should be offered:

1. **Fill** *(the default)* — **sweeps seeds and keeps the best one**, exactly as
   `tools/author_levels.gd` does for whole levels.

   For each seed it builds a sequence the way `Generator` step 6 does — the directions of the
   solver's optimal route, then padded and interleaved with decoys — then measures the resulting
   level with `LevelMetrics` and scores it against the slot's place on the curve. The winner is kept.

   This matters more than it sounds. The same board with two different deals is two different levels:
   one where the tile you need arrives a turn early and one where it arrives a turn late. A single
   sequence taken from the first seed that worked would throw that away, and the author would be left
   tuning the board to compensate for a deal nobody chose.
2. **Edit** — the sequence is a text field of direction names. Typing in it is how a level gets a
   *deliberate* rhythm: three norths in a row, or the awkward tile arriving one turn early.
3. **Keep** — loading an existing level keeps its sequence, so the board can be edited around a
   sequence that already works.
4. **Trace** *(added after first use)* — draw the route on the board and the tiles are what it
   spells. §4.1.1's second mode.

Fill must be re-runnable after any board edit, and the editor should say so when the board has changed
since the sequence was made.

#### 4.4.1 Trace, and why Fill was not enough

**Fill does not always fill, and cannot be argued with when it doesn't.** Each of its ten seeds is a
biased random walk from the start; a walk that paints itself into a corner is thrown away whole, and
on a board with a tight corridor or a goal behind a doorway all ten do it. What the author gets is
*"no deal made this board solvable"* about a board that is perfectly solvable — they can see the
route with their eye and there is no way to tell the tool about it.

Trace is that way. Every click is checked against the rules the game plays by — the tile is laid
against a cell the path already has (§5.4), never onto a wall or onto itself, a gate only opens on
the second approach (§6), and stepping on a portal carries the path to its twin (§5.5.3). So what
comes out is a **recorded legal play**, and therefore a sequence the solver can win *by
construction*. That is the one promise Fill's sweep cannot make.

It is also the only way to get a route somebody chose. §4.4's text field was meant to be that, and
is not: a list of direction names is not a shape anyone can picture, and it says nothing until
Validate, seconds later, with nothing to point at.

- The route is drawn on the canvas in every mode, numbered by step, with the tip ringed. A route is
  what the sequence beside it *means*, and hiding it when the brush comes back out is how an author
  paints a wall across their own path without noticing.
- The hover ring says yes or no **before** the click, because being told which rule you just met
  after the fact is how an author ends up fighting one they cannot see.
- Entering the mode replays the route against the board as it is now and drops it from the first
  step that is no longer legal. The prefix up to the wall is still a legal play and still worth
  keeping.
- Fill and the text field both **clear** the route, because a drawn line under a sequence it does
  not describe is the canvas lying.
- The route is not saved. The file records the sequence; the route is one of the many plays that
  sequence allows.

A traced sequence has no decoys in it — it is exactly the tiles the route spends. Padding it is
the text field's job, or Fill's on a board where Fill works.

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

### 6.1 Save as — a board that is not one of the sixty

**Added after first use.** Every save above writes into a campaign slot, which means every save
overwrites a shipped level. There was nowhere to put a board that is not ready to be one of the
sixty, and that is most boards for most of the time they exist.

**save as…** writes anywhere, defaulting to `drafts/` — outside `src/`, named in the export
preset's exclude filter, and never read at runtime. **open…** reads one back.

> **The refusal follows the destination, not the button.** Writing into `src/data/levels/` requires
> a passing Validate whichever button got there; writing anywhere else does not require one at all.
> A scratch folder that only accepts finished work is not a scratch folder — the whole point is to
> park a board that is *not* finished. If Save-as could aim at `chapter_3/level_07.json` it would
> be a way around §6 rather than an alternative to it, so the guard is by path.

A draft still needs a **start**, because without one there is no `Level` to serialise. That is the
whole of the constraint.

Promoting a draft is: open it, set chapter and level, Validate, save to slot. It keeps its `uid`,
so §7.1's rule holds across the move.

**new** starts an empty board, behind a confirm — §9 rules undo out of scope because "save-and-reload
covers it", which is true of a mis-drag and not of a press that throws the whole board away. It keeps
the slot and **drops the `uid`**: a fresh board inheriting the last one's name would hand a player's
stars to a level they have never seen, which is the bug uids exist to prevent, and is why the sweep
mints a new one too.

### 6.2 Playing a draft

```sh
make play-draft FILE=drafts/idea.json
```

Opens the level in the **real game** — the real board, the real rail, the real rules — not a preview
inside the editor. A draft that was never validated has no `par`, and par is what §5.10's star bands
are measured against, so it is solved on the way in; a board the solver cannot win is reported and
played anyway, because seeing *why* is the reason to open it.

`tools/play_draft.gd` is a `-s` MainLoop, the same arrangement `tools/screenshot.gd` uses. **Nothing
in `src/` learns that drafts exist**, so there is no debug flag in the shipped build to gate and §8's
one-way arrow is untouched — which is the only reason this does not reopen §27.

---

## 7. Levels: pick and reorder

The **levels…** button opens a list of all 60: chapter, index, shape, ideal, routes, forgiveness, and
how far each sits from its slot on the curve.

- **Click** loads a level into the canvas.
- **Drag** reorders, within a chapter or across chapters.
- **Apply order** rewrites the files.

### 7.1 Reordering is safe, because levels have names — **built, C-34**

The save used to remember progress like this:

```
"c3_l07"  ->  3 stars, best 11 moves, hint used
```

`c3_l07` means **chapter 3, slot 7**. It named a *position*, so dragging a level out of slot 7 did
not take its stars with it — they stayed on the slot, and whatever landed there inherited them.

Every level file now carries a `uid` instead: a ten-character name minted once, stored in the file,
never reused. Progress keys on that, so **a level carries its stars wherever it moves** and position
is only presentation. `Apply order` rewrites `chapter`, `index` and the filenames and touches nothing
else.

Two rules the editor has to keep:

- **Editing a level keeps its uid.** It is the same level with a wall moved.
- **The authoring sweep mints a new one**, because it produces a different level at that slot.
  Inheriting the old name would hand a player's stars to a board they have never seen, which is the
  original bug arriving from the other direction.

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
| Playtesting inside the editor | Still out of scope, but the reason changed. It used to be "`make run` already plays the level that was just saved", which stopped being true the moment a board could be saved somewhere other than a campaign slot — the boards most worth playing are the unfinished ones. `make play-draft FILE=…` plays any level file in the real game, from outside it. See §6.2 |
| Editing endless or daily boards | Both are generated from a seed at runtime (§7.2, §7.3); there is nothing to edit |
| Painting the tile sequence graphically | A text field is faster and unambiguous |
| Any player-facing entry point | §27 |

---

## 10. Open questions

All answered. Kept here because the reasoning is the useful part:

- **Q2 — may an author remove cells?** Yes, so the schema gains `cells`. See §4.3. A removed cell
  shows the backdrop and a wall shows a hatched tile standing at wall height; walls can fake a
  silhouette but they cannot make a hole.

- **Q1 — canvas renderer.** Flat 2D. See §3.
- **Q4 — a hand-drawn level's `generator.seed`.** Searching for a seed that *reproduces* a drawn
  board is a lottery ticket and was the wrong question. The seed records which **tile sequence** Fill
  chose (§4.4): the board is the author's, the seed says which of the deals was kept, and re-running
  Fill with it reproduces the level exactly. A dead provenance field becomes a live one.

# Hexflow codebase guide

For someone who has just cloned the repo. Read this, then [`../../HEXFLOW-SPEC.md`](../../HEXFLOW-SPEC.md)
§4, §5 and §16 — the spec is the authority on *what* the game is; this document is about *where
things live and why*.

Section references like §5.4 point into the specification.

---

## 1. Five minutes to running

```sh
make godot     # fetches the pinned engine into .tools/ — no system install
make run       # play it
make test      # the whole suite, ~1 min (the count lives in TODO.md, not here)
make gate      # everything CI runs; do this before you push
make           # list every target
```

`make status` tells you which engine it found, which branch you are on, and how many level files
exist.

---

## 2. The one rule

```
src/core/  →  src/app/  →  src/view/ + src/scenes/ + src/ui/
```

**The dependency arrow never reverses.** `core` knows nothing about `app`; `app` knows nothing
about specific scenes. The view sends *intents* upward (`place_requested(target)`) and receives
*facts* downward (`cell_joined(target, anchor, dir)`). The view owns no rules.

This is not architectural taste. The 2016 prototype fused its rules into a libGDX `Screen`
subclass, which made every rule unverifiable except by playing the game — and the game did not
run, so nothing was ever verified. It shipped unwinnable levels and a coordinate type without
value equality, and nobody found out. That is defect **B4** in Appendix B, and constraint **C1**
exists to prevent its return.

The rule is enforced mechanically, not by review. `tools/ci_gate.sh` greps `src/core/` for `Node`,
`Control`, `Input`, `Texture`, `PackedScene`, `get_tree`, `get_node` and fails the build on a hit.
Try it: add `var n: Node = null` to any core file and run `make gate`.

### Three more mechanical rules

| Rule | Why | Enforced by |
|---|---|---|
| No global `randi()` / `randf()` / `randomize()` anywhere in `src/` | Daily puzzles, leaderboards, replays and the property tests all need determinism. Only `TileStream` and `Generator` own an RNG, and both are explicitly seeded (C2, §19) | `ci_gate.sh` grep |
| No floats in `src/core/` | Integer logic is reproducible across platforms and engine versions. Pixel math lives in `src/view/hex_layout.gd` instead (decision C-13) | `ci_gate.sh` grep |
| Exactly six autoloads | `EventBus`, `SettingsService`, `SaveService`, `AudioDirector`, `SteamService`, `GameDirector`. Nothing else becomes a singleton (§16.5) | `ci_gate.sh` count |

`InputRouter`, `InputBindings`, `LevelRepository` and `Haptics` look like services but are
deliberately **not** autoloads — the level scene owns a router and a `Haptics` child node, and the
other two are static APIs with a cache.

---

## 3. Directory map

```
hexflow/
├── src/core/       pure logic. No engine, no floats, no RNG. 100% testable headlessly
├── src/app/        services, the six autoloads, input bindings, router, holds, haptics
├── src/view/       drawing: the C-18 3D board (camera, prisms, shader), the 2D
│                grey-box, palette resource, cube↔pixel and cube↔plane layout
├── src/scenes/     screens (boot, level; the rest are M5+)
├── src/ui/         reusable widgets used by more than one screen (the legend panel)
├── src/data/       frozen level JSON, palette .tres, schema docs
├── tests/unit/     @core — pure logic, fast, no scene tree
├── tests/property/ @property — generator, solver and shipped-level invariants
├── tests/e2e/      @e2e — real scenes, injected InputEvents
├── tests/fixtures/ shared level fixtures
└── tools/          offline scripts. Not shipped, not exported
```

---

## 4. The core, module by module

Everything here is a `class_name` with static functions or a plain `RefCounted`. Nothing extends
`Node`.

### `hex.gd` — coordinates

A cell is a **`Vector3i`** with `x + y + z == 0`. That type choice is load-bearing: `Vector3i` is
value-comparable and hashable in Godot, which structurally prevents defect **B1** — the 2016
Java→Scala translation dropped `equals`/`hashCode` on the coordinate type, so every grid lookup
returned null and the game was unplayable. The commit message literally says "there's still NPE".

Never wrap a coordinate in a `RefCounted` and use it as a dictionary key.

`hexagon(radius)` returns cells in a stable order (ascending z, then x). `sort_cells()` gives a
canonical order for anywhere a `Dictionary`'s iteration order would otherwise leak into an outcome.

### `direction.gd` — the six directions

The table in this file is Appendix A of the spec, verified against the 2016 tile art
(`android/assets/hex_A.png` … `hex_F.png`, each a hexagon with one lit edge). **Do not permute
it.** The index order is baked into the tile bag, every solver, and every save file.

`tests/unit/test_direction.gd` asserts the whole table row by row. If you ever need to change it,
that test is the thing that will stop you.

### `board.gd` — immutable topology

Which cells exist, their kind (`EMPTY` / `WALL`) and their flags (`START`, `GOAL`, `PORTAL`,
`GATE`, `WILD`, as a bitmask so a cell can be both a goal and a gate). Built once; never mutated
during play.

### `level.gd` — a level's constraints

Board plus `tiles`, `discards`, `budget`, `par`, `solution`. The spec's module table has no home
for these (decision **C-9**), so this value object holds them.

### `tile_stream.gd` — the seeded direction source

Two modes: an endless sequence of shuffled six-direction bags (prevents droughts, keeps randomness
fair), or an explicit array from a campaign level file. The generated sequence is **memoised**, so
`rewind_to()` is exact and undo can never desynchronise the stream from the state.

The shuffle is canonical descending-index Fisher-Yates, specified precisely so the sequence is
byte-identical on every platform and engine version.

### `rules.gd` — the ruleset, as pure functions

No state. Every function takes a board and a path set and returns a fresh answer — which is exactly
what lets the solver explore hypothetical futures without touching the live `GameState`.

The important one is `legal_targets(board, path, dir)`. For a fixed direction, the map
`anchor → anchor + delta(dir)` is **injective**, so every legal target has exactly one anchor. That
is why the player's interaction is a single confirm on a highlighted cell with nothing to
disambiguate — the property the prototype lacked (**B12**: any cell anywhere was clickable, and the
clicked cell did not itself join the path).

### `game_state.gd` — the mutable run state

The only place rules are applied. `path` is an invariant **tree** rooted at start: every placement
attaches exactly one new cell (plus, for a portal, its twin) to a cell already in the path. So
connectivity never needs recomputing and winning is a counter check, not the prototype's BFS.

It emits no signals and touches no nodes. Callers **drain `events`** after each mutation:

```gdscript
state.place(target)
for e in state.drain_events():
    match e["type"]:
        GameState.EV_PLACED: ...
```

`GameDirector` is the only production caller; it translates those events into `EventBus` signals.

### `solver.gd` — bounded optimal search

Answers "is this level solvable, and in how few placements?" — the question the prototype never
asked, which is why it shipped unwinnable boards (**B2**, **B3**).

The path is a **64-bit mask** over board cell indices. A radius-4 board is 61 cells, so one integer
holds any reachable path exactly, which makes the visited set cheap enough to explore 200 000
states in GDScript.

Search is A* on `g = placements`, `h = max over goals of cube distance from the nearest path cell`.
§8.3 suggests *summing* over goals — that is **not admissible** when one placement shortens the
route to two goals at once, and an inadmissible heuristic returns a par that is not the optimum,
which the star bands of §5.10 depend on. Hence `max` (decision **C-10**).

The solver also powers the hint system: `solve_state()` runs from a live position.

### `generator.gd` — candidates, and the verification that makes them safe

Follows §8.2: pick start and goals, carve a reserved route, scatter walls on cells the route does
not need, place modifiers, build the tile sequence, **then verify with the solver**.

> Step 7 is not optional. Nothing leaves this file without the solver having proved it winnable
> and having produced its par.

An `UNKNOWN` from the state cap counts as a rejection, not as a pass.

### `endless_run.gd`, `scoring.gd`, `move.gd`

Endless escalation (§7.2) with no new rules — each stage is an ordinary `Level`. Star bands.
The undo record.

---

## 5. What happens when the player presses confirm

Worth tracing once; every other interaction follows the same shape.

```
level.gd  _unhandled_input(event.is_action_pressed("board_confirm"))
   └─ EventBus.place_requested.emit(cursor)              intent, upward
        └─ GameDirector._on_place_requested(target)
             └─ GameState.place(target)                  the only rules call
                  ├─ Rules.legal_targets() to validate
                  ├─ path[target] = true; edges.append(...)
                  ├─ portal twin joins if the target is a portal
                  ├─ wild charge granted if the target is wild
                  ├─ stream.advance()
                  └─ _resolve_turn()
                       ├─ won?  budget blown?  goal unreachable?  path frozen?
                       └─ burn free auto-discards until a placeable tile is current
             └─ GameDirector._publish(state.drain_events())
                  ├─ EventBus.cell_joined / goal_reached / tile_auto_skipped / …
                  ├─ EventBus.legal_targets_changed
                  └─ SaveService.set_in_progress(...)     autosave, every move
        └─ level.gd redraws; input_router re-snaps the cursor
```

Two things to notice.

**Auto-discard is free and automatic.** If the current tile has no legal target, `_resolve_turn`
advances the stream at no cost, repeatedly, until a placeable tile appears (§5.7). The player is
never punished for an impossible draw. It is deliberately not a failure beat — the sound is an
airy whoosh, not a buzz.

**A dead board is never a hard fail.** `status = DEAD` shows a banner offering undo and restart.
Campaign has no failure state.

---

## 6. Undo, and the trap in it

Undo rewinds one `Move` completely: path cells, edges, stream index, discard count, wild charges,
portal twin.

The subtle part is auto-discards. A move stores `stream_index_before` = the index *before that
turn's run of free auto-discards*, not the index of the tile actually placed. Undo rewinds to that
index and then re-runs `_resolve_turn`, which burns the same auto-discards again deterministically.
The player ends up facing the tile that was originally placeable, which is what §5.9 requires.

`tests/unit/test_game_state.gd::test_undo_rewinds_past_the_auto_discards_that_preceded_the_move`
is the guard. If you touch turn resolution, that test is the one that will catch you.

---

## 7. Levels are data, and stay data

Campaign levels are **frozen JSON** under `src/data/levels/chapter_N/level_MM.json`, produced
offline and never regenerated or re-seeded at runtime. A re-seed would change the tile sequence and
silently invalidate every stored par, star and comparison.

```sh
make levels              # regenerate all 60 — pars will change, commit the JSON
make levels CHAPTER=3    # one chapter
```

`tools/author_levels.gd` sweeps seeds per level slot, keeps the first candidate whose par lands in
the chapter's target band, verifies it, and writes it. `tests/property/test_level_files.gd`
re-verifies every shipped file on every push: it re-runs the solver, confirms the stored par is
reproduced, and replays the stored solution through the real `GameState` to confirm it still
reaches `WON`.

Schema: [`../src/data/schemas/level.md`](../src/data/schemas/level.md).

One extension beyond §17.1: `solution_script`. The spec's `solution` is a bare target list, which
cannot express the voluntary discards an optimal line sometimes needs — so such a solution is not
replayable and cannot be proven to still win. `solution_script` carries `[kind, cube]` pairs;
`solution` is kept and derived from it (decision **C-14**).

---

## 8. Tests

| Layer | Where | What it is for | Runtime |
|---|---|---|---|
| `@core` | `tests/unit/` | Pure algebra and rules. One test per Gherkin scenario in §24.2 | ~2 s |
| `@property` | `tests/property/` | Generation invariants over a seed sweep, and every shipped level file | ~45 s |
| `@e2e` | `tests/e2e/` | Full flows through the real scene tree with injected `InputEvent`s, one file per input device | ~11 s |

§24 states the preference explicitly: **end-to-end scenarios over unit tests.** Unit tests exist
for the pure core, where they are cheap and catch real algebra bugs. Everything player-facing is
verified end to end.

The property sweep is the most valuable test in the suite, because unsolvable levels are the
prototype's signature failure. It has already earned its keep — it is what caught both spec
defects logged as C-10 and C-14.

```sh
make test-core
make test-property
make test-e2e
make test-file FILE=tests/unit/test_rules.gd
```

---

## 9. GDScript and Godot gotchas

Things that cost time here, so they do not cost you any.

**`script` is a reserved member.** Every `Object` has one. A class member named `script` fails with
"Member redefined (original in native class 'RefCounted')". `Solver.Result` uses `actions`.

**`_ = expr` is not valid GDScript.** There is no bare-underscore discard. Prefix an unused
parameter with `_` in its declaration instead, or just delete the expression.

**Functions returning `Variant` break `:=` inference.** `var x := f()` where `f` returns `Variant`
errors under the project's warnings-as-errors settings. Annotate the type, or make the function
return a typed `Array` of zero or one element (see `Generator._pick_goal`).

**`while true:` defeats return analysis.** "Not all code paths return a value", even when the loop
provably cannot exit. Give the loop a real bound and return after it.

**A new `class_name` is invisible until you reimport.** Add a core file, and every script
referencing it fails to parse until `make import`. This looks like a mysterious "Identifier not
declared" and is not.

**Autoloads do not exist in a `-s` MainLoop script.** Scripts run via `godot -s script.gd` are
compiled *before* autoloads register, so referencing `GameDirector` by name is a compile error.
Reach them through the tree: `root.get_node_or_null("GameDirector")`. This is why `tools/*.gd` use
the pure core and the static `LevelRepository` API.

**Godot drops a whitespace-only command-line argument.** `-- "   "` arrives as nothing. This is why
`tools/screenshot.gd` takes `c` for confirm rather than a space.

**A full-rect `Control` eats every pointer event.** `Control.mouse_filter` defaults to
`MOUSE_FILTER_STOP`, so a screen-sized `Control` consumes mouse *and* touch input in the GUI pass and
`_unhandled_input` never sees it. The symptom is maddeningly specific: the keyboard works perfectly
and clicking does nothing. `level.tscn` sets `mouse_filter = 2` on its root for exactly this reason.
Child `Button`s are still hit-tested normally, so passing the event down costs nothing.

**`Viewport.push_input()` takes *window* coordinates by default.** The second argument is
`in_local_coords`, and it is `false`. With the project's `canvas_items` stretch mode, a position
computed in viewport space gets multiplied by the stretch transform on the way in — under the test
window that scaled a tap 20× off the board. Tests that inject a positional event pass
`push_input(ev, true)`. Key and joypad events are unaffected, which is why this hides until the first
mouse or touch test.

**GDScript lambdas capture locals by value.** `var n := 0` followed by
`sig.connect(func(): n += 1)` increments the *closure's own copy*; the outer `n` stays 0 forever. It
fails silently — no warning, no error, just a counter that never moves. Use a member variable, or a
container (`Array`/`Dictionary`), which is captured by reference.

**MultiMesh instance data cannot be read back headlessly.** `set_instance_transform` and friends
write into the rendering server, and under `--headless` the dummy driver hands every instance back as
an identity transform with a default colour — a direct write followed by a read proves it. So compute
what an instance should be in a testable method (`BoardTiles.transform_of` / `tint_of` / `custom_of`)
and let the write path do nothing but push. Otherwise the whole board layer is untestable in CI.

**`Control` has no `to_local` / `to_global`.** They are `Node2D` methods. A `Control` converts through
`global_position`, which is why `BoardView3D` owns `local_point()` and `screen_position_of()` rather
than leaving callers to subtract the board's offset — the kind of arithmetic that puts a click one row
out on any screen with a top bar.

**`SurfaceTool.generate_normals()` smooths by default.** It averages the normals of every face meeting
at a shared vertex, so a prism's top face comes out leaning sideways. `set_smooth_group(-1)` before
adding vertices gives flat faces. Deriving normals this way is still worth it: it pins the winding to
the engine's own convention instead of to your reading of the docs, so a mesh built inside out fails a
headless test rather than a screenshot.

**A `SubViewportContainer` with `stretch` on owns its viewport's size.** Setting `SubViewport.size`
yourself is refused with a warning; set the container's `size` and the child follows synchronously.
That is what keeps container coordinates and viewport coordinates the same numbers — and note that
this node type is a `Control`, so the full-rect pointer-eating gotcha above applies to it too.

**`assert()` only fires in debug builds.** Loader validation uses `assert` *and* `push_error`, so
debug fails loudly and release skips the level and logs — one bad file can never brick a player's
campaign.

---

## 10. Adding things

**A new rule or mechanic.** Write the Gherkin scenario in §24.2 first, then the test in
`tests/unit/`, then the code in `src/core/`. Then make sure the solver understands it — a mechanic
the solver cannot model makes every generated par wrong, silently. Then the view.

**A new modifier.** §6 says exactly five ship and "do not invent more". Every extra mechanic
multiplies tutorial, art, solver and test cost. If one is genuinely needed: add the flag to
`Board`, the predicate to `Rules`, the mask lane to `Solver.Topology`, the placement to
`Generator`, and the glyph to **both** boards — `BoardView`'s grey-box and `BoardMarks` plus a
silhouette in `hex_mark.gdshader`. Missing any one of those six is a silent bug.

**A new screen.** Add it to `GameDirector.Screen` and `SCENES`, and give it a row in
`GameDirector.ACTION_SETS` so it runs under the right §11.1 action set. No screen may push another
screen directly — the state machine lives in one place (§12.1).

**A new binding.** One row in `InputBindings.ACTIONS`, with a keyboard *and* a gamepad column — §11
forbids any interaction being exclusive to one device, and `test_input_bindings.gd` enforces it. Give
it a `glyph` slot that every family in `src/data/input_glyphs.json` answers. Never test a keycode in a
screen; ask `event.is_action_pressed("…")`. Anything destructive gets a `hold`.

**A colour.** Add it to `src/view/palette.gd` and `src/data/palettes/neon_dark.tres`. Never hardcode
a colour in a script or a scene: the four accessibility palettes of §21 are a `.tres` swap with no
code change, and that only works if every colour is read from the resource.

---

## 11. The grey-box seam

`level.tscn` renders through `BoardView3D` — C-18's orthographic-3D board, two multimeshes and a
camera. `BoardView` is the **grey-box** it replaced: untextured hexes drawn in `_draw`, still alive,
still tested, and still the answer if a 2D fallback is ever wanted.

The seam is what matters here. The two expose the same four calls — `bind`, `rebuild`,
`set_candidates`, `set_cursor` — and both answer in screen-space positions, so swapping one for the
other taught `level.gd` and `InputRouter` nothing. That is why the perspective change of C-18 cost a
view and not a milestone. If an art change breaks the grey-box's tests, the art change is wrong.

The same shape holds for the screens that do not exist yet. `GameDirector.SCENES` already names all
seven, and `go_to()` no-ops on the ones that do not resolve, so adding a screen is a scene file plus
a row — never a change to how screens are switched.

**What is built and what is not:** [`../../TODO.md`](../../TODO.md), which is the single source of
truth for project status. Why things are the way they are: [`BUILD-SUMMARY.md`](BUILD-SUMMARY.md).

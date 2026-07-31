# Hexflow — progress tracker

Living checklist of what is built and what is not. **Must be kept in sync with the code** — see
[`CLAUDE.md`](CLAUDE.md).

- [`HEXFLOW-SPEC.md`](HEXFLOW-SPEC.md) is the authority on *what* to build. This file only tracks
  *how far along* it is. If the two disagree, the spec wins and this file is wrong.
- Milestones and their exit criteria are §26 of the spec. A box is ticked only when the spec's exit
  criterion is **demonstrated**, not when the code looks finished.
- `make gate` is the arbiter. Anything ticked here should survive it.

Last verified: **2026-07-31** — Godot 4.7.1, 517 tests / 16,209 asserts green in ~90 s, 60 frozen
level files re-verified.

---

## Status at a glance

| M | Name | State | Blocking exit criterion still open |
|---|---|---|---|
| M0 | Skeleton | ✅ done | — |
| M1 | Logic core | ✅ done | — |
| M2 | Generator & solver | ✅ done | — |
| M3 | Grey-box playable | ✅ done | — |
| M4 | Input & Deck | ✅ done | — |
| M5 | Persistence & settings | ✅ done | — |
| M6 | Campaign data | ✅ done | — |
| M7 | Art & feel | 🟨 board + rail | greyscale under lighting, fonts, all §14 animation, all §15 audio |
| M8 | Tutorial | 🟨 built, unplayed | the naive playtest, which *is* the exit criterion |
| M9 | Modes & Steam | 🟨 screens done | GodotSteam, achievements, leaderboards |
| M10 | Accessibility & i18n | ⬜ not started | palettes, text scale, Reduce Motion, extraction |
| M11 | Release | ⬜ not started | Deck self-audit, three platform builds, depots |

Legend: ✅ exit criteria met · 🟨 partially built, criteria not met · ⬜ nothing built.

**Next up:** the §14.1 rows that were waiting for §12.3's real layout to sit in — queue advance,
auto-discard arc, results stars — and the last two beats of §14.2's goal sequence. Then M8's
tutorial, whose exit criterion is a **naive playtest nobody has run**; everything for it is built,
and it is the last thing standing between the game and a first-time player.

**Every screen §12.1 draws now exists**, and the map is walkable end to end: boot → main menu →
level select → level → results → next level, with pause over the board and settings reachable from
either side of it. `tests/e2e/test_campaign_chain.gd` follows the *director* rather than a script —
whatever `GameDirector.screen` becomes is what gets instantiated — so a screen that navigates
somewhere §12.1 does not go fails there rather than in front of a player. What is still M3's is the
level screen's *layout*: the rail is a stack of six full-width buttons rather than §12.3's four
action rows, and it only fits because the key hints were moved into the legend.

> **Art direction changed, decided 2026-07-31 (spec Appendix C, C-26).** §13.1's "neon on near-black,
> nothing textured, nothing skeuomorphic, everything drawn with SDF shaders" is superseded by an
> **illustrated, warm, material** direction: painted chapter backdrops, panels built from timber and
> waxed paper, light that comes from somewhere in the scene. Three things are kept — §21's
> colour-independence, §13.2's palette indirection (every texture is *tinted* through a token, so the
> four alternate palettes still reach the art), and the board's whole C-18/C-22/C-23/C-24 stack, which
> only changes surface. The direction adds one rule: **art is data, never code**, so an illustrator can
> replace the look without a script changing. Where the art comes from is **C-27**, open — until it is
> answered the game ships generated placeholder art, committed like `make sfx` and `make levels`
> commit theirs. `neon_dark` is not lost: it becomes one of §21's alternates.

> **Perspective change, decided 2026-07-30 (spec Appendix C, C-18).** The board becomes an oblique
> **orthographic 3D** view that the player can rotate in 60° steps, with the upcoming tiles as a
> physical stack. Nothing in `src/core/` is affected — cells stay cube `Vector3i`, and the rules, the
> solver, every stored par and all 60 frozen level files are perspective-agnostic. It lands in M7,
> whose checklist below is rewritten for it; §13.3's SDF-shader plan was never built. M4 is
> unaffected beyond one binding pair, because `InputRouter` works from screen-space positions the
> view hands it, so the cone and the cycling order simply follow the camera.

---

## M0 — Skeleton ✅

- [x] Godot **4.7.1** pinned in `hexflow/README.md`, `Makefile` and CI — never floats (§16.1, C-2)
- [x] §16.4 directory layout
- [x] Exactly six autoloads: `EventBus`, `SettingsService`, `SaveService`, `AudioDirector`,
      `SteamService`, `GameDirector` (§16.5, count-enforced by `ci_gate.sh`)
- [x] GUT wired, runs headless
- [x] CI running headless — `.github/workflows/hexflow-ci.yml`
- [x] `make godot` fetches the pinned engine; no system install needed

## M1 — Logic core ✅

- [x] `hex.gd` — `Vector3i` cells, value-comparable by construction (§4.1, closes B1)
- [x] `direction.gd` — Appendix A table, asserted row by row; **do not permute**
- [x] `board.gd` — immutable topology, flags as a bitmask (§5.1)
- [x] `level.gd` — `tiles` / `discards` / `budget` / `par` / `solution` (decision C-9)
- [x] `tile_stream.gd` — seeded bag, canonical Fisher-Yates, memoised for exact rewind (§5.3)
- [x] `rules.gd` — pure functions; `legal_targets` injectivity (§5.4, closes B12)
- [x] `game_state.gd` — path as an invariant tree, O(1) win check, event drain (§5.5, §5.6)
- [x] `move.gd` + full undo including stream index, discards, wild charges, portal twin (§5.9)
- [x] Free auto-discard on an unplaceable draw, never a failure beat (§5.7)
- [x] Dead state as a recoverable banner, never a hard fail (§5.8)
- [x] `scoring.gd` — star bands (§5.10)
- [x] Every `@core` scenario of §24.2 passes headlessly
- [x] Banned-API grep clean: no global RNG, no floats in `src/core/`, no engine types in `src/core/`

## M2 — Generator & solver ✅

- [x] `generator.gd` per §8.2, with step-7 verification **mandatory** before acceptance (closes B2/B3)
- [x] `UNKNOWN` from the state cap counts as rejection, not as a pass
- [x] `solver.gd` — A*, 64-bit path mask, `max`-over-goals heuristic (admissible; decision C-10)
- [x] `@property` seed sweep green: every accepted candidate solvable, solution replays to `WON`,
      stored par equals the solver optimum, no wall on a start or goal
- [x] `solution_script` so an optimal line containing a voluntary discard is replayable (C-14)

## M3 — Grey-box playable ✅

- [x] `hex_layout.gd` — pointy-top cube↔pixel both ways, floats kept out of core (C-13)
- [x] `board_view.gd` — `_draw` grey-box, geometry prebuilt in `bind()`, nothing allocates per frame (C4)
- [x] Every modifier readable by glyph **and** shape **and** colour, never colour alone (C5, §21)
- [x] The **edge** a placement would cross, lit on each candidate — `src/view/board_seams.gd`. The
      tint said *where* a tile may go and could not say *which way in*: a tile is a direction, so
      every candidate is entered from exactly one anchor across one of its six edges (§5.4's
      injectivity), and on a path that has doubled back the cell a given candidate connects from is
      genuinely ambiguous. Which edge is not decided in the view — `GameState.anchor_of()` is asked,
      because it is what the commit uses, and a second opinion there could promise an edge the rules
      then do not take. Drawn in `path_core` rather than the candidate token: it is a ghost of the
      connector that replaces it a moment later. A **wash**, not a bar — `seam_bleed.gdshader` lights
      the candidate from that edge and fades inward, because a bar has hard ends and read as a chip
      wedged in the crevice rather than as a way in
- [x] `palette.gd` + `neon_dark.tres` indirection — no hardcoded colours
- [x] `input_router.gd` — snap-to-candidate and free cursor, ±75° cone, clockwise cycling (§11.2)
- [x] Keyboard bindings; mouse click-to-place through `HexLayout.from_pixel` (closes B7) — the
      conversion was right, but **no pointer event ever reached it** until M4 fixed the level root's
      `mouse_filter`; ticked here on the strength of the code existing, which is exactly what the
      "never tick a box because the code exists" rule is about
- [x] Text HUD rail: now/next, undo, discard, wild, hint, restart, budget
- [x] Win, dead and auto-skip surfaced in the banner
- [x] Hint replays the solver from the live state, bounded (§12.6)
- [x] A radius-3 level is completable on the keyboard; win and dead states both reachable
- [x] **Toggle legend** — Tab / Select / a rail button, `src/ui/legend_panel.gd` (done in M4)
- [x] **Full WASD** — `D` collided with Discard; C-20 moved discard to `X` (done in M4)

> `BoardView._draw` is the seam M7 replaces. The grey-box must keep working through M7 — if an art
> change breaks the grey-box tests, the art change is wrong (§26 sequencing note).

## M4 — Input & Deck ✅

Exit: gamepad-only and touch-only playthroughs pass as `@e2e`; snap never selects an illegal cell
over 200 random inputs. **Met** — `tests/e2e/test_gamepad_playthrough.gd`,
`test_touch_playthrough.gd`, `test_snap_navigation.gd`.

Every binding is one table, `src/app/input_bindings.gd`, registered into `InputMap` at runtime. No
screen tests a keycode: it asks `event.is_action_pressed("board_confirm")`, so keyboard, gamepad,
touch and a future rebind all arrive on one path. That is what made the gamepad playthrough testable
at all.

- [x] Full §11.3 gamepad column: A confirm, Y undo, X discard, L2+A wild, R2 hint, Start pause,
      B back, Select legend, hold-Select restart
- [x] Hold gestures for every destructive action — nothing destructive on a single press (§11.3).
      Restart holds on *every* device, keyboard included
- [x] L1/R1 bumper cycling bound to the existing `InputRouter.cycle()`, asserted in clockwise order
- [x] `board_rotate_cw` / `board_rotate_ccw` in the binding table — inert until the C-18 camera (M7)
- [x] Action sets `Menu`, `Board`, `Modal` (§11.1), claimed by the screen that owns them; a set that
      is not live is not acted on. **Steam Input's own** action-set configuration lands with
      GodotSteam in M9 — there is no Steam API in the build yet
- [x] Touch-only path; every on-screen button ≥44 px at 1280×800, asserted on the rendered rect (§11.4)
- [x] Controller glyph atlas, data-driven by `Input.get_joy_name`, Deck names for View/Menu (§11.4) —
      labels **and** icons. `assets/glyphs/`, 52 files at 48×48, drawn by `tools/make_glyphs.gd` from
      this same atlas so a glyph cannot disagree with the label it replaces, and read through
      `InputGlyphs.texture_for()`. `src/ui/glyph_hint.gd` owns the choice between the two, and the
      text is the **floor**: no pad, no binding, or no file for that family all fall back to the word,
      because a rail that went blank over a missing PNG would be worse than the bug it fixed. Wired
      into §12.3's rail rows and the legend's CONTROLS block. **Unverified on hardware** — CI has no
      controller, so what the tests can assert is that every slot in use has a file in every family
      and that nothing ever reads as nothing
- [x] Haptics table and the 0–100% slider, default 70% (§11.5) — pattern table and slider scaling
      verified headlessly. **Rumble on real hardware is unverified**: CI has no controller
- [x] Surface `cycling_hint_wanted` as the toast after 3 cone rejections (§11.2)
- [x] Free-cursor toggle wired live to `SettingsService.changed` — the Settings *screen* is M5 (§12.2)
- [x] `@e2e`: gamepad-only playthrough, touch-only playthrough, 200-input snap fuzz across all three
      input devices, bumper cycling visits all targets in clockwise order

Found and fixed while building, both defects the checklist would not have caught:

- **Pointer input never reached the level screen.** The root `Control` kept Godot's default
  `mouse_filter = STOP`, so it swallowed every mouse and touch event in the GUI pass before
  `_unhandled_input` saw one. Keyboard worked, which is why nobody noticed. Now `mouse_filter = 2`,
  with a mouse test and a touch test standing over it.
- **A wild charge was unspendable.** §11.2 snaps the cursor to `legal_targets` only, and §6 lets a
  charge enter any cell adjacent to the path — so every cell a charge exists to reach was unreachable
  in the default cursor mode. Arming the wild now widens the candidate set to `wild_targets()`.

Deferred, deliberately:

- The §24.2 gamepad scenario opens with "navigate to Campaign, chapter 1, level 1", which needs the
  main menu and level select of **M6**. The navigation leg is asserted there; the playthrough leg is
  asserted here.
- Rebinding writes to `settings.custom_bindings`, which the table is shaped for but nothing reads yet
  (M5, with the Controls tab).

## M5 — Persistence & settings ✅

Exit: persistence `@e2e` scenarios pass, including corrupted-save recovery and suspend/resume
identity. **Met** — `tests/e2e/test_persistence.gd`, `tests/unit/test_resume.gd`.

- [x] `save_service.gd` — atomic write, migration, corruption recovery with backup
- [x] `settings_service.gd` — defaults and typed access
- [x] Autosave of in-progress state on every commit, discard and undo (§18.1)
- [x] **Read it back** (§18.2) — `GameDirector.resume_in_progress()`, called by boot before it falls
      back to chapter 1 level 1. Autosave had been writing `in_progress` since M5 and nothing read
      it. The payload is treated as untrusted throughout, because it is written by an older build,
      truncated by a suspend that lost power, or edited by hand: a level id that names nothing, a
      mode that is not campaign, a run that had already finished, or a value that is not a dictionary
      at all each end with no resume and a playable level rather than a black screen.
      `tests/unit/test_resume.gd` covers every one of those, plus the stream resuming with the state
      — without it the next tile handed to the player is not the one they stopped looking at
- [x] Suspend/resume on focus loss (§18.3); undo history deliberately not persisted (C-16) —
      `GameDirector._notification` writes the run down on focus out, app suspend and window close.
      §18.1 already covers every *move*; this is the gap between the last move and a Deck going to
      sleep, which may simply never wake. `suspend()` is public so §18.3 is a scenario a test can
      trigger rather than one that needs a window to lose focus. Identity is asserted field by field
      — path, edges, placements, discards, charges, stream index, tile — because the fields that go
      missing quietly are the ones nobody looks at
- [x] Settings screen with all five tabs: Gameplay, Controls, Video, Audio, Accessibility (§12.2) —
      `src/scenes/settings/`. The screen is one table: a setting is `{key, label, kind, …}` and four
      kinds (toggle, choice, range, bind) cover every row, so adding a setting is a row rather than a
      widget — which is also what makes §21's "layouts that reflow" reachable at all. Every test goes
      from a key press through to `SettingsService` *and* to the thing the setting does, because the
      failure mode of a settings screen is a control that moves and changes nothing.
      **Rebinding is live** (§21's "every action rebindable per device"): a rebind is a *layer* over
      the §11.3 table in `settings.custom_bindings`, never an edit of it, which is what makes
      reset-to-default true by construction rather than by keeping a second copy of the defaults. The
      next input decides the device — a key rebinds the keyboard column, a pad button the pad column.
      A collision *inside* one action set is refused and named; across sets it is allowed, because
      §11.1's whole point is that Space means confirm on the board and accept in a modal.
      **Not offered:** the palette picker. §21 wants four alternate palettes and only `neon_dark`
      exists — a picker with one entry is not a picker. It lands in M10 with the `.tres` files
- [x] Pause screen: Resume, Restart (hold), Settings, Quit to map (§12.2) — `src/ui/pause_panel.gd`,
      a modal *inside* `level.tscn` rather than a screen of its own. `Screen.PAUSED` has no entry in
      `GameDirector.SCENES` on purpose: §12.2 pauses over a board that is still there, and swapping
      scenes would rebuild it, drop every animation in flight and charge two 320 ms fades for a menu
      that should feel instant. What actually stops the board being played is §11.1's action set,
      which until now had no counter-example behind it — nothing had ever claimed `Modal`. The
      sharpest test is the shared key: §11.3 gives `board_confirm` and `modal_accept` the same Space
      and the same A, and the same press places a tile on one side of a pause and works the menu on
      the other. Restart is never a single press (§11.3), and **§21's hold-to-confirm toggle is
      honoured rather than ignored** — with it off the gesture becomes press-then-confirm, which is
      the same guarantee by a different route, and moving focus off the row disarms it.
      `modal_up`/`modal_down` are new in the binding table: §12.5's "exactly one focused element in
      `Menu`/`Modal`" is unreachable in a set with no way to change which one
- [x] Steam overlay opening auto-pauses gameplay (§12.5) — `SteamService.overlay_toggled`, which
      [GameDirector] turns into a pause. Emitting it is a public call rather than only a relay of
      GodotSteam's own signal, because the requirement is testable *now* and the GDExtension is M9:
      what breaks is the wiring, and it breaks identically whether the overlay was real. Closing the
      overlay deliberately does **not** unpause — the player was taken out of the game by something
      that was not the game, and dropping them back onto a live board is how a move gets made by
      somebody reading a chat message
- [x] `@e2e`: corrupted save reaches the menu with defaults and notifies once; suspend/resume
      identity; progress survives a quit from three different screens — `test_persistence.gd`, and
      the three exits are three different chances to lose a run: `suspend()`, Quit to map from the
      pause modal, and the window close notification. §18.4's newer-schema quarantine is asserted in
      the same file. `load_from_disk` stopped using `JSON.parse_string` while writing it: that call
      pushes an engine error on bad input, and an error the code deliberately recovers from is an
      error nobody looks at twice

## M6 — Campaign data ✅

Exit: every level file validates and reproduces its par; the whole campaign is playable start to
finish. **Met** — `tests/property/test_level_files.gd`, `tests/e2e/test_campaign_chain.gd`.

- [x] 60 generated, verified, frozen level files under `src/data/levels/chapter_N/`
- [x] `tools/author_levels.gd` sweeps seeds per slot against the chapter's par band
- [x] `tests/property/test_level_files.gd` re-verifies every shipped file on every push
- [x] Level schema documented — `src/data/schemas/level.md`
- [x] **Main menu** — Campaign %, Endless best, Daily streak + reset timer, Settings, Quit (§12.2) —
      `src/scenes/main_menu/`, and **boot now hands to it** rather than opening a level, which is what
      §12.1's first arrow has always said. The numbers are the requirement, not decoration: a menu
      that navigates perfectly and shows 0% to a player who has finished two chapters has failed
      §12.2, so `tests/e2e/test_main_menu.gd` asserts each one. The daily countdown is live off a
      1 s `Timer` rather than a `_process` that rebuilds five strings a frame to change one (C4).
      §18.2 survives the change of route: the map opens on the in-progress level and entering it
      calls `GameDirector.resume_or_start`, so re-entering a run does not throw it away — without
      that, boot no longer resuming would have quietly cancelled every autosave since M5
- [x] **`src/ui/menu_list.gd`** — §12.5's focus rules in one place, since every `Menu` and `Modal`
      screen is the same list with different rows: exactly one focused row, wrapping within the list,
      a 3 px ring in the accent colour, and §21's 1.04× scale so focus is never carried by colour
      alone. Disabled rows are stepped over rather than landed on. §12.5's 100 ms is in `Motion`
      beside the §14.1 table, not inside the widget — but *not in* `TIMINGS`, which is asserted row
      for row against §14.1 and may not grow a fifteenth entry
- [x] **Level select** — hex-flower map reusing the board renderer, star pips, chapter progress (§9) —
      `src/scenes/level_select/` plus `src/ui/hex_flower.gd`. §9's "same board renderer" could not be
      taken literally and the reason is **C-25**: both renderers bind a `GameState`, and "level 7, two
      stars, locked" is not a board state. What is reused is the part that makes it a hex map —
      `HexLayout`'s §4.3 conversion, its corners, its `from_pixel` rounding for the hit-test (B7) —
      so there is still exactly one hexagon formula in the codebase. Navigation is `InputRouter`'s
      *unchanged*: the same ±75° cone over the same lattice, so left means the same thing on the map
      as on the board. Three map states, three silhouettes (§21): a locked level is hatched like a
      wall, an open one is an outline, a completed one is filled with the path colour as §9 asks.
      Chapters page on the bumpers — `menu_cycle_prev`/`next`, new in the binding table, because
      left and right are already spoken for by the cone. `tests/unit/test_hex_flower.gd` asserts the
      layout table the way `test_direction.gd` asserts Appendix A (a permutation silently renumbers
      every level), and `tests/e2e/test_level_select.gd` plays §24.2's "navigate to Campaign, chapter
      1, level 1" — the leg the M4 gamepad playthrough had to skip for want of a map
- [x] **Chapter unlocks** — a chapter opens at 8 of 12 completed in the previous one (§7.1) —
      `src/app/campaign.gd`, the one place that answers "is this unlocked", "how far along am I"
      and "what is next". Not in `src/core/` because every one of those is a question about the
      *save file*, which the core is deliberately ignorant of; not an autoload because §16.5 fixes
      the list at six and it holds no state. `tests/unit/test_campaign.gd` stands on the boundaries,
      which are all the ways a player gets stuck: 7 of 12 does not open a chapter, a Next button
      never points into a locked one, and a map cursor never lands on a level the save says is
      shut. The screens that consume it are the three items above and below
- [x] **Results screen** — animated stars, placements vs par, Next / Replay / Map, focus on Next (§12.2)
      — `src/scenes/results/`. The stars are the screen, so they arrive one at a time on §14.1's
      3 × 260 ms `BACK`/`EASE_OUT` staggered 140 ms with a chord note each; a card that simply
      displayed "★★☆" would satisfy the word "stars" in §12.2 and none of the reason it is there.
      The card is scheduled at §14.2's **t=700**, after the flourish, the burst, the ripple and the
      flow pulse, and it is *cancelled* if the player restarts during those 700 ms. Next is disabled
      rather than allowed to fail late when §7.1's threshold leaves nowhere to go, and focus falls to
      Replay — §12.5 wants exactly one focused element and a greyed-out one does not count. This
      closes the last clause of §24.2's gamepad scenario, "the results screen offers Next with
      default focus", which M4 could not assert because there was no results screen
- [x] Hint-used dot on the star display (§12.6) — beside the pips rather than among them, so it can
      never be miscounted as a star, and on the level-select cell too. It marks the *level*, not the
      attempt: `SaveService.record_completion` ORs it in, so a later clean run does not erase it
- [x] `@e2e`: campaign playable boot → credits; completion recorded and progression advances
      (closes B6) — `tests/e2e/test_campaign_chain.gd`. It exists for the *seams*, since every
      screen already has its own test: it follows the **director** rather than a script, so whatever
      `GameDirector.screen` becomes is what gets instantiated, and a screen that navigates somewhere
      §12.1 does not go fails there rather than in front of a player. B6 was "progress never
      persisted, so the campaign could not advance"; that is the last two assertions, stated as a
      requirement. There is no credits screen to reach — §12.1 does not draw one and §12.2 does not
      list one, so "boot → credits" is read as its actual content: a cold boot reaches a playable
      campaign, and finishing a level moves it on

## M7 — Art & feel 🟨

Exit: every §12.4 feedback requirement met against the grey-box; §20 frame budget met at 1280×800.

Rewritten for the orthographic-3D perspective of **C-18**. The 2D grey-box stays alive as a
fallback view; since `level.tscn` no longer instantiates it, it keeps its own test
(`tests/unit/test_board_view.gd`) rather than riding on the e2e playthroughs.

- [x] Cube → ground plane: `hex_layout.gd` gains `(x, z)` output, same §4.3 formula, floats still
      confined to the view (C-13) — `to_plane` / `from_plane`, with the formula written once and
      shared with `to_pixel`, so the 3D board cannot drift from the grey-box.
      `tests/unit/test_hex_layout.gd` is also the layout's *first* direct test: the conversion, both
      round trips, §4.4's size table and the margin the fit rule claims to leave were all covered
      only transitively through `BoardView` before
- [x] `Camera3D`, `projection = ORTHOGONAL`, fixed pitch; yaw snaps to the six 60° lattice positions,
      tweened; §4.4's fit rule applied to the **projected** bounds — `src/view/board_camera.gd`. The
      numbers C-18 left open are now **C-21**: 55° elevation, a 260 ms `CUBIC EASE_IN_OUT` yaw that
      Reduce Motion scales, and a fit swept *across* the rotation rather than evaluated at the six
      stops, because the yaws in between bulge and would clip the board mid-turn. `s` = 82 / 59 / 46
      for radius 2 / 3 / 4 against the head-on 74 / 53 / 42. `tests/unit/test_board_camera.gd`
      pins all of it, including that "clockwise" is clockwise *on screen*
- [x] Pointer hit-test as camera ray ∩ `y = 0`, then the existing `HexLayout.from_pixel` — B7's fix
      must survive the move to 3D — `BoardCamera.plane_point` into `HexLayout.from_plane`, which
      shares `from_pixel`'s rounding rather than forking it. Every cell round-trips from its own
      screen position *and* lands on its centre, not merely somewhere inside it
- [x] `Camera3D.unproject_position` feeds `InputRouter`, recomputed on yaw change, never per frame (C4)
      — `src/view/board_view_3d.gd`, a `SubViewportContainer` whose viewport coordinates *are* the
      space the level screen already works in, so `InputRouter` and `level.gd` learn nothing new.
      Asserted with a real router: the ±75° cone picks a cell that is genuinely up on screen and a
      *different* one after a 60° turn, and clockwise cycling comes back cyclically rotated rather
      than scrambled. Positions jump to the stop being travelled *to*, so a press during the tween
      behaves like the board about to be seen; a pointer still resolves against the live camera.
      `mouse_filter = IGNORE` on the container, pinned by a test — the default `STOP` is exactly
      what hid B7 through all of M3
- [x] One `MultiMeshInstance3D` of hex prisms for the whole board, per-instance custom data, single
      draw call (§13.3's requirement, new geometry) — `src/view/board_tiles.gd` plus
      `src/view/shaders/hex_prism.gdshader`. Colour travels as the instance colour and *what the tile
      is* as custom data (kind, cursor, depth), so the shader holds no colour literal and §21's
      palette swaps stay a `.tres` change. **§21 in 3D is height, not stroke — new decision C-22**:
      empty 0.16, joined 0.28, wall 0.52 of the circumradius, which is what
      `BoardView3D.TILE_TOP_RATIO` reserves in the fit. Instance data cannot be read back under the
      headless renderer, so the arithmetic is separated from the push and CI asserts the arithmetic
      (`tests/unit/test_board_tiles.gd`); the winding is derived by `generate_normals` so a board
      built inside out fails a test instead of a screenshot
- [x] Tile thickness, drop shadows and one `DirectionalLight3D` + `WorldEnvironment` — one key light,
      fixed in world space so turning the board moves the shadows across it, and one environment,
      both coloured from new palette tokens (`board_key_light`, `board_ambient`). Prisms are drawn at
      0.93 of their cell so the background shows between them: that gap is the 3D board's answer to
      `cell_empty_stroke`, without which a field of empty cells reads as one unlit slab. The hit
      region is unchanged — the rounding is still on the full cell
- [x] **`BoardView3D` is live in `level.tscn`** — `make run` is the 3D board, `make shot` captures
      it, and `[` / `]` turn it. Landed early, on request, rather than with the glyphs
- [x] **C5 gap closed.** It was knowingly open for one step: the 3D board drew no modifier glyphs, so
      goals, portals, gates and wilds were invisible on it where the grey-box distinguished all four.
      The glyph item below closed it
- [x] Connectors with the depth gradient, as 3D geometry rather than §13.3's capsule SDF —
      `src/view/board_links.gd` plus `shaders/path_link.gdshader`, the second of the two board
      multimeshes §20's draw-call budget already reserved. A ribbon standing on the tile tops,
      lightened off its own path colour because C-22 had already tinted the tiles underneath it that
      exact colour, and emissive so §13.1's "single continuous line of light" survives the shadowed
      side of a turn. Portal jumps draw as the grey-box's dashed tether, thinner and unlit (§6 calls
      it faint) — two channels that are not colour. The buffer is sized once for the longest path the
      board can hold and drawn with `visible_instance_count`, so a placement rewrites instances and
      an undo shortens the stroke rather than leaving the undone step lit.
      **Not built:** §6 also gives a portal a standing "faint tether line to twin", visible before it
      is used. Only *traversed* jumps are drawn, as in the grey-box. Harmless while every campaign
      level ships exactly one pair, ambiguous the moment one ships two
- [x] NEXT becomes a stack of upcoming tiles; remaining count shown for a campaign level's fixed tile
      array only, never for the unbounded endless/daily bag (C-18) — `src/view/tile_stack.gd`, the
      board's own prism seen at the board's own elevation in a viewport of its own, so a piece in the
      rail and the tile it becomes are visibly the same object. The arrow on a piece points where
      that tile will actually travel **and follows the board round**: a direction is a lattice step,
      so which way it runs on screen depends on the yaw, and a fixed glyph would be lying at five of
      the six stops (`BoardCamera.screen_angle`). The arrow is a fifth silhouette in
      `hex_mark.gdshader` and deliberately not a [BoardMarks.Mark] — §6 ships five modifiers and a
      direction is not a sixth. `tests/unit/test_tile_stack.gd` measures every arrow against the real
      board's screen positions rather than a written-down table, at all six stops; the count rule is
      `@e2e`, on the real screen. The stack is a literal **pile of coins**, soonest on top: you read
      the next direction off the one face there is, and the pile's height says roughly how many are
      left. §12.3's two-tile lookahead is deliberately given up for it — a coin under a coin has no
      face to read — so NEXT previews one tile, not two
- [x] Glyph legibility through rotation — billboarded, and still readable at every one of the six
      stops. **Closed the C5 gap above**: goal, portal, gate and wild all have their mark back —
      `src/view/board_marks.gd` plus `shaders/hex_mark.gdshader`, a second multimesh of one instance
      per mark, billboarded **in the vertex shader** from the camera's basis. Decision **C-23**:
      shader billboarding rather than a `Label3D` per cell, which costs a node and a draw call each
      and needs a font §13.4 has not vendored; procedural SDF silhouettes rather than §13.5's atlas,
      which is what §13.1 asks for and stays crisp at every §4.4 size. Each modifier is a different
      *shape* first (§21): reticle, two rings, padlock, star — ring-and-dot for the goal reads as
      "concentric circles" in greyscale, which is exactly what a portal is, so it gained four ticks.
      §6's lock opens live off `Rules.gate_satisfied`. Verified as a **greyscale** capture at two yaw
      stops, not only by test: `make shot LEVEL=5.1` is the one board carrying all four at once
- [x] Unshaded material path so §21's greyscale requirement survives lighting (C-18) — a `flat_board`
      setting, off by default, as a `uniform bool` in both board shaders rather than a second pair of
      shaders. `ALBEDO` goes to zero and the tile is emitted at its own colour, so every lit term
      multiplies out and a tile on screen *is* its palette colour. Decision **C-24** for the part
      C-18 left open: fully flat would have taken C-22's heights with it, so the side faces still
      step down by a fixed fraction of the face's own normal. Live rather than on the next load, and
      the key light stops casting while it is on (§20). `tests/unit/test_flat_board.gd`
- [x] **The wall hatch of §6**, found missing while checking the above in greyscale: `wall.fill` and
      `cell.empty.fill` are within 1% of each other in luminance, so with colour gone a wall and an
      empty cell were told apart *only* by how tall they stand — at 55° a band a few pixels deep on a
      near-black tile. The grey-box drew a hatch and the 3D board never got one. Now on the wall's
      top face in `hex_prism.gdshader`, 45° in board space so it turns with the board rather than
      swimming across it, inked from the grey-box's own `wall.stroke` token. Verified in a greyscale
      capture: hatched walls, flat everything else
- [x] `board_rotate_cw` / `board_rotate_ccw` given an effect — bound in M4, live now. Turning re-feeds
      `InputRouter` with the new screen positions, so the cone and the cycling turn with the board
- [x] Full palette token set audited — never a colour in a script or scene (§13.2). Three literals
      were baked into scene files (`boot.tscn`'s background and title, `level.tscn`'s background) and
      §13.2's `path.glow` had no token at all. All four fixed, and the audit is now **grep-enforced**
      in `ci_gate.sh` rather than remembered: any colour property in a `.tscn`, or a hex `Color("…")`
      outside `palette.gd`, fails the gate. The float form is deliberately not scanned in scripts —
      `set_instance_custom_data` takes a `Color` that is four floats of state, not a colour.
      `tests/unit/test_palette.gd` also holds the resource to the script: a token declared and then
      forgotten in the `.tres` does not fail, it silently falls back to the neon-dark default, which
      is exactly how one of §21's four palettes would ship with a wrong colour in it
- [x] Fonts vendored, SIL-OFL only: Space Grotesk, Inter, JetBrains Mono; 18 px absolute floor (§13.4)
      — `assets/fonts/`, three TTFs and three licences. All three are **variable** fonts, so one file
      per family carries every weight on a `wght` axis and Medium/Bold are a `FontVariation` rather
      than a second file. `src/view/typography.gd` holds §13.4's table and builds the theme
      `GameDirector` puts on the window, so a screen asks for a *role* ("this is a caption") and
      never for a size — which is what makes §21's 1.0–1.5 text scale a setting rather than an edit
      in every scene, and what makes the 18 px floor enforceable in one place. `test_typography.gd`
      sweeps every role at every scale in §21's range against the floor, and asserts the numerals are
      genuinely tabular by measuring `111` against `999`.
      **Not done:** §13.6's subsetting to Latin-Extended. The three full variable fonts are 1.2 MB
      together, nowhere near §20's 250 MB build budget, and subsetting needs a tool the repo does not
      vendor. Worth doing before the store build, not before the next feature
- [x] Icon atlas, 9 line icons on a 24×24 grid (§13.5) — `src/ui/icon.gd`. §13.5 offers a choice,
      "drawn as vector paths or an SVG-imported atlas", and the paths win for C-23's reason: an atlas
      is a raster at one size, and the same nine shapes are drawn at a rail row's size, at a legend
      row's size and at §21's 1.0–1.5 text scale on top of both. No import step, no texture memory
      (§20), no second file to keep in step with the palette. The grid is the contract — every path
      is written in 24×24 units and scaled once, so "2 px stroke on a 24 grid" holds at every drawn
      size, and `tests/unit/test_icon.gd` asserts the family: nine icons, none off the grid, none too
      small to sit beside the others, and no two the same drawing. The four rail icons are live;
      the legend's rows still use text glyphs
- [x] Real §12.3 HUD layout: 56 px top bar, 400 px rail, 140 px NOW tile, 72 px NEXT, 56 px banner —
      the last thing on the level screen that was still M3's. The band sizes are constants in
      `level.gd` rather than numbers in the scene, because §12.3's diagram is *dimensioned* and a
      scene file is where a dimension goes to be nudged by accident; `tests/unit/test_hud_layout.gd`
      asserts them, asserts the board never overlaps the rail, and asserts the rail's column **fits
      inside the rail**. That last one is the bug this step actually found: six action rows plus a
      140 px NOW tile overflow a 400 px rail, a `PanelContainer` whose minimum height exceeds its
      rect grows in *both* directions, and the NOW caption had been pushed off the top of the screen
      — visible only in a capture. §12.3 lists **four** rows, so Legend moved to the top bar and
      Restart to the pause menu, where §11.4's touch route already was. Each row is the action on
      the left and its binding on the right, as §12.3 draws it, and the top bar carries a **live**
      star band: what the run is worth right now, so a player one placement from dropping a star can
      see it before they spend it
- [ ] Every §14.1 timing, exactly as tabulated — **the table is built and pinned**, the animations
      mostly are not. `src/view/motion.gd` holds all fourteen rows as data the way Appendix A's
      directions are, so a tween built anywhere reads its duration *and* its curve from one place;
      `tests/unit/test_motion.gd` asserts every row against §14.1 and would fail a silent retune.
      **Wired so far:** candidate breathing and the goal pulse, both in the shader off `TIME` so
      every candidate breathes in phase for free; the placement pop and the connector draw, both as
      one tween writing one instance for a fifth of a second; the flow pulse, one band crossing the
      tiles *and* the stroke lying on them off a single uniform; and the board ripple, whose per-cell
      delay rides a distance written once into the instance data so a wave over sixty-one cells is
      still one tween and one number. and the illegal shake, whose red flash survives Reduce Motion even
      though its movement does not — §14.5 is a motion reduction, not a feedback removal. and the dead-state desaturation, which §5.8 makes reversible because a
      dead board is recoverable and a board still grey after an undo would be lying. and the screen transition, as a fade layer above every
      screen rather than something each screen does to itself — a screen that does not exist yet
      still gets a transition instead of a flash of the one behind it, and the swap happens at full
      black where nothing can be seen to pop. Still to do: queue advance, auto-discard arc and
      results stars — all of them rail or screen animations that want §12.3's real layout under them
      first
- [ ] Goal-reached sequence §14.2; camera limited to §14.3 (2 px shake, once per completion) —
      **four of the six beats run**: the goal cell flourishes 1.0 → 1.25 → 1.0 at t=0, the board
      ripples out of it at t=120, and the whole path pulses at double speed at t=200, all off
      `Motion.GOAL_SEQUENCE` so the sequence is diffable against §14.2 rather than typed into a
      script. Missing: the 24-spark burst at t=60 (§14.4's particle work) and the Results card at
      t=700 (a screen M6 has not built). §14.3's 2 px shake is not wired either — it belongs to the
      burst beat. **The burst now runs**: §14.4's emitter fires at t=60 where §14.2 puts it, and
      §14.3's shake is wired to level completion with its whole budget enforced in code — 2 px, 120
      ms, and "once per level completion, nowhere else" as a flag that only a new level resets
- [x] Four GPU emitters, hard cap 120 live particles (§14.4) — `src/view/board_particles.gd`. All
      four built once at bind and reused, never one system per event: a particle system created the
      moment something happens is an allocation in that frame (C4). 8 + 24 + 12 + 10 = 54 against the
      cap of 120, which leaves room for two bursts to overlap. §14.5 turns all four off outright
      rather than shortening them — a burst asked for while it is on does nothing at all. Every
      emitter takes its colour from a palette token, so §21's swaps reach the particles too.
      **Simplified:** §14.4 calls the motes "path flow motes" and they currently drift over the whole
      board rather than following the path, which needs an emission shape rebuilt per move
- [x] Reduce Motion path: durations ×0.4, no shake/parallax/particles/breathing, still fully legible
      (§14.5) — **the rule is implemented, and it is not just a multiplier**: §14.5 also names 120 ms
      for screen transitions outright (not a scaled 320), and says the loops *stop* rather than
      shorten. `Motion` gets all three right and the test names the two traps. Verified on screen for
      the loops: two captures 0.9 s apart are byte-identical with it on and differ with it off.
      Outstanding until the animations that do not exist yet do — shake, parallax, particles
- [🟨] Audio: 5 chapter beds + menu track, two stems, ducking (§15.1) — **beds and ducking are in;
      the second stem is not.** Six 48-second loops cut from **two** supplied tracks — the menu takes its own
      piece and the later chapters take the remix, because §15.1 asks for "5 chapter beds + menu
      track", six *tracks*, and six windows of one recording is one track wearing six hats, made seamless
      by mixing each window's last three seconds over its first three, so the end already contains
      the beginning and the seam has nothing to click on. 3 MB for the set. Beds cross-fade over
      §15.1's 1.5 s and never cut, a bed already playing is not restarted (so every screen can ask in
      `_ready`), and a key with no track is silence rather than an error. The goal-reached duck is
      −6 dB for 600 ms **on the bus**, returning to the *slider's* level rather than to wherever the
      bus happened to be — otherwise two goals in quick succession ratchet the music down and leave
      it there. **Still owed:** §15.1's `base`/`layer` stems. The remix cannot be the layer — it is 178.9 s
      against the original's 165.6 s, so it is an independent render, and two independent renders do
      not layer, they phase and fight because nothing makes their bars line up. A stem pair has to
      come out of one session with one clock: the same piece exported twice, once with the pads
      muted. **That is the thing to ask for next — not another variation, a pads-only export of a
      track that already exists.** And §15.3's −16 LUFS / −1
      dBTP, which needs a meter over a real mix
- [x] All 16 SFX (§15.2); `place.note` pentatonic ascent, resets per level, steps **down** on undo —
      `assets/sfx/`, 16 mono WAVs, 328 KB, **synthesised** by `tools/make_sfx.gd` from a table of a
      few numbers per effect (`make sfx`, output committed like `make levels`). No external artist,
      no licence to track, and retuning one is an edit rather than a download. The ascent is one
      sample *pitched* rather than sixteen recorded notes, so the scale lives in code as ratios:
      major pentatonic, capped at three octaves so a long path cannot climb out of hearing.
      **Unverified:** I cannot hear them. The table is the point — replacing any effect with a
      recorded one changes no code
- [ ] Buses and sliders, −16 LUFS / −1 dBTP, `place.*` voice cap 4 (§15.3) — **buses, sliders and the
      voice cap are built**: Master → Music / SFX / UI, each effect naming its own bus so the two
      sliders move different sounds, and `place.*` capped at four voices with the oldest stolen. The
      loudness targets are not measured — that needs a meter over a real mix and belongs with the
      music, which is still blocked on C-6
- [ ] Renderer measured Forward+ vs Mobile for the Deck export, result documented (C-3) — **harness
      built, partly measured, not decided**. `make measure METHOD=…` and `tools/measure_renderer.gd`.
      Three findings, recorded on C-3 in Appendix C. The project has been running **`gl_compatibility`**
      since M0 — neither of the two renderers C-3 asks about — so the whole C-18 board was authored
      under a third one. All three compile every shader in `src/view/shaders/` and draw the board
      correctly, which was the export-time failure worth finding early. And §20's budgets already
      bite: Mobile draws **42** calls against a limit of 40, Forward+ sits at 100 MB video memory
      against a ceiling of 100, on a board that has no HUD art on it yet.
      **Blocked on hardware:** macOS/Metal ignores the vsync disable, so both RenderingDevice
      backends come back pinned to the panel's 8.33 ms and their frame *cost* is unmeasured. Needs a
      Deck, or a Linux box where vsync can actually be turned off

## M8 — Tutorial 🟨

Exit: a first-time player completes chapter 1 with no external explanation — verified by an actual
naive playtest, not a self-assessment. **Everything is built; the exit criterion is not met**, because
the playtest is the criterion and nobody has run one. Do not tick this milestone on the strength of
the checklist below.

**To run it: `make playtest`**, which moves your own save aside — every beat writes a flag the moment
it is shown, and yours have been set by weeks of playing and by the test suite, so launching normally
shows a tutorial that has already happened. `make playtest-restore` puts it back; nothing is deleted.
The protocol, and what each beat has to actually *achieve* rather than merely display, is
[`hexflow/docs/PLAYTEST.md`](hexflow/docs/PLAYTEST.md). **Write the result here when it happens** —
including a failure, which is the more useful of the two outcomes because it names the next thing to
build rather than leaving it to be guessed at.

- [x] `src/data/tutorial.json` — beats are **data**, never hardcoded in level scripts (§10) — twelve
      rows in a table `tests/unit/test_tutorial.gd` diffs against §10.2, the way Appendix A's
      directions and §14.1's timings are. `src/app/tutorial.gd` decides *which* beat is live and the
      level screen decides what a live beat looks like; it holds no strings and no timings of its own
- [x] T1–T12 (§10.2), each ≤12 words, diegetic, non-blocking after T1 — the word count is asserted,
      because it is a hard number in §10.1 and the first thing to go when a beat is edited to explain
      one more thing. A trigger arriving while a beat is up is **dropped**, not queued: §10.1 allows
      twelve words on screen, not two beats' worth. **One divergence:** §10.2 writes T1 as "Your tile
      points north-east", which is true of the level that ships and would become a lie the first time
      `make levels` reseeded chapter 1 — the direction is filled in from the tile the player is
      actually holding
- [x] Beat flags in `save.tutorial_flags` so nothing repeats — including across a reopening of the
      level, which is the case a screen-local variable gets wrong
- [x] Settings → "Replay tutorial" resets the flags only — §10.1's emphasis is the spec's own, so the
      test is that the campaign and the stats survive it
- [x] Skippable at any time with one Back press — resolved **before** the pause branch, because
      §11.3 puts `board_pause` and `board_back` on the same Esc and the pause would otherwise always
      win on a keyboard. It only claims the press while a beat is actually up

**§10.2's *Interaction* column, in part.** The four beats that point at the rail now light the row
they are about — T3 the NEXT stack, T5 Undo, T8 Discard, T12 the wild charge. A beat that says "undo
is free" while nothing indicates *which* thing undo is has stated a fact rather than taught anything;
the pointing is the lesson. It borrows the board's own breathing rather than inventing a second
idiom, so the rail and the candidates pulse on one clock, and §14.5 stops the loop and leaves the row
**held bright** — the emphasis is feedback, and reducing motion is not removing what the player is
being told. T1's candidate pulse, T6's flyaway and T7's wall shake come free from animations that
already exist.

**Still owed, beyond the playtest:** T10's two ghost stubs on a gate and T3's preview scaling 1.15×
specifically (the NEXT stack is lit, not scaled). Both are board-side emphasis and both are worth
waiting for a playtest to justify — if nobody is confused by gates, the stubs are decoration. T1's candidate pulse, T6's
flyaway and T7's wall shake come free from animations that already exist.

Two things the wiring turned up. T1's gate cannot simply follow the stored optimum: chapter 1 level
1's optimal line **opens with a discard** (which is what C-14's `solution_script` exists to record),
and a beat reading "your tile points north-east" must not gate the player onto a cell that tile cannot
reach — so the gate is §10.2's own narrower claim, "only the one legal target accepts input", with the
optimum used when it is available and legal. And the tutorial does not run in endless or the daily: a
player there has been through chapter 1, and a beat firing would be teaching nobody.

## M9 — Modes & Steam 🟨

Exit: mode `@e2e` scenarios pass, including the Steam-unavailable path.

- [x] `endless_run.gd` — §7.2 escalation, stage seeds as `fnv1a_32("endless:<seed>:<goals>")` (C-12)
- [x] `Generator.daily(utc_date)` — one puzzle per UTC day, verified solvable at generation
- [x] Both tested; `GameDirector.start_endless` / `start_daily` exist
- [x] Endless screen and Run summary: goals, PB, leaderboard slice, Retry / Menu (§12.2) —
      `src/scenes/run_summary/`, and §12.1's `Endless → RunSummary : DEAD` arrow, which nothing
      implemented: a dead board was a recoverable banner in all three modes, right for the campaign
      (§5.8) and wrong for a run with no undo. It waits out §14.1's dead-state desaturation first,
      so the player sees the board they died on. `SaveService.record_endless_run` is new — `runs`
      and `best_goals` were in the schema from M0 and nothing ever set them, so the menu's "best"
      was structurally zero. **Not done:** §12.2's leaderboard slice (top 3 + friends + self) needs
      a leaderboard *read* and `SteamService` has only `submit_leaderboard` until GodotSteam links.
      The card says it is waiting for Steam rather than showing three invented names, which is the
      version that would survive into a store build unnoticed
- [x] Daily screen: 7-day streak indicator, timer to reset, restart-only (§7.3) — all three live on
      the main menu's Daily row, which is where §12.2 puts the daily's entry (there is no separate
      Daily screen row in its table; §12.1 sends the daily straight to the board and then to
      Results). The indicator is seven marks with today on the right, filled for played — a bare
      "streak 4" cannot tell you whether today is already done. `SaveService.record_daily` counts
      consecutive *dates*, so a retry does not extend a streak (§7.3 allows unlimited retries and a
      streak you can grind in an afternoon measures nothing), and the day before is computed through
      the epoch so month ends and leap years are the calendar's problem. Restart-only was already
      true — `GameDirector.undo_available` has been campaign-only since M1
- [ ] GodotSteam GDExtension linked, matched to the pinned engine (§16.1, C-2)
- [ ] Achievements; `endless_best_goals` and rolling daily leaderboards
- [ ] Steam Auto-Cloud for saves (no code)
- [x] `@e2e`: Endless escalates and ends on a dead board; two clients generate an identical daily;
      **Steam unavailable never blocks play** and achievements queue locally — `tests/e2e/test_modes.gd`.
      All three were logic that had existed since M9's first commit and had never been played end to
      end. The Steam one is easiest to pin *now*, while there is no Steam API in the build at all:
      every mode plays with `available` false, achievements queue as a set rather than a log so a
      later handover cannot replay them, and a leaderboard submission with nobody listening is a
      no-op rather than an error

## M10 — Accessibility & i18n ⬜

Exit: accessibility `@e2e` scenarios pass; greyscale playthrough verified; 150% scale shows no clipping.

- [x] Four alternate palettes as `.tres` swaps, zero code change (§21) — `deuter`, `protan`, `tritan`,
      `high_contrast`, plus `cairn_warm` and `neon_dark`. Surfaced in Settings → Accessibility and
      applied **live**, because the moment a player picking a colour-blind palette needs to see it
      work is while they are picking it. `tests/unit/test_palette_vision.gd` is the part that makes
      the word "safe" mean anything: it *simulates* each deficiency (Viénot's linear dichromacy
      approximation) and measures the decisions the game forces — path/goal/wild, portal/gate,
      candidate/empty, focus/surface — **after** the simulation, against WCAG 1.4.11's 3:1 non-text
      floor. An author cannot check this claim by looking, since the whole point is that they see
      something the player will not.
      It immediately found three defects in the two palettes that already shipped: `neon_dark`'s
      candidate stroke sat at 1.67:1 against an empty one (and the candidate *breathes*, which §14.5
      stops under Reduce Motion, leaving brightness alone), and §6's wall hatch was under 3:1 against
      its own wall in both `neon_dark` and `cairn_warm` — the hatch being the one cue a wall has that
      is neither colour nor height. All three are fixed. **Still owed:** a person who actually has
      one of these conditions looking at a real board
- [ ] Text scaling 1.0–1.5× across every font role (§13.4, §21)
- [ ] Reduce Motion toggle wired to the M7 animation layer
- [ ] String extraction to `assets/i18n/en.csv`, then **enable the §22 literal check in `ci_gate.sh`**
      — it is scaffolded and currently skips
- [ ] Pseudo-locale for clipping tests (§22)
- [ ] Greyscale playthrough of a chapter 4 level containing walls, gates, portals and two goals

## M11 — Release ⬜

Exit: §23.4 checklist ticked on hardware; three platform builds from CI; a clean install completes
chapter 1 without incident.

- [ ] Export presets: Linux/X11 x86_64 (primary), Windows x86_64, macOS universal (§25)
- [ ] macOS codesign + notarize, documented in `README.md`
- [ ] Deck Verified self-audit against §23.4 — re-read Valve's live docs first (C-8)
- [ ] Store page: capsules, 1280×800 screenshots, 30–60 s trailer, <300-char description
- [ ] Depots per platform, `default` + `beta` branch, tag-triggered release job
- [ ] Semver surfaced in Settings → About and written into every save
- [ ] Name and trademark check before the page goes live (C-1); price decided (C-4)

---

## Cross-cutting debt

- [ ] `assets/i18n/` is still empty, pending the M10 extraction. The rest of the tree is populated:
      `fonts/` (3 vendored), `sfx/` (16 synthesised), `music/` (6 beds, stems still owed),
      `art/` (6 painted backdrops, 3 generated surfaces, the logo) and `glyphs/` (52 placeholders).
      `icons/` stays empty by design — §13.5's nine are vector paths drawn in code.
      `make assets` is the answer to what is here; `make assets-ui` is the one with the pictures in it
- [ ] `src/scenes/{main_menu,level_select,results,run_summary,settings}/` are empty directories.
      `GameDirector.SCENES` names all seven screens and `go_to()` silently no-ops on the five that
      do not resolve — harmless now, a silent dead end once something calls them.
- [ ] UI strings are literals pending the M10 extraction, which is why the §22 gate check skips.
- [x] Legacy 2016 libGDX tree **removed from `master`** — 83 files, preserved at the `libgdx-2016`
      tag and on `legacy/libgdx-2016`. The condition was the tile art no longer being needed as the
      Appendix A reference, and it is not: the direction table is written out in full in the spec and
      asserted row by row by `tests/unit/test_direction.gd`, which is what makes the *table* the
      authority and the art merely its provenance. Appendix B describes the prototype's defects in
      prose and never by reference to its sources. The root `.gitignore` shrank with it — it was
      almost entirely Java, GWT, Gradle and Eclipse rules for a build that is gone.
- [ ] Music licensing route still undecided (C-6); daily scoring model still defaulted (C-7).

## Open spec questions

**Board radius is capped at 4 (C-19).** Growth up to there is free — radius is already a `Board`
parameter and the campaign ships radius 2, 3 and 4 — but `solver.gd`'s 64-bit path mask holds at most
62 cells, and radius 5 is 91. Late-game difficulty escalates walls, goals, gates and budget instead.

Unresolved items live in **Appendix C** of the spec (C-1 … C-8, C-19). Decisions already taken during
M0–M7 are recorded there too (C-9 … C-18, C-20 … C-24) — add to that table rather than inventing an
answer, per constraint C7.

---

## Keeping this file honest

1. Do not tick a box because the code exists. Tick it when the spec's exit criterion is
   demonstrated — usually a passing test named after the §24.2 scenario.
2. Update this file in the **same commit** as the work it describes.
3. This is the **only** place project status lives. `hexflow/docs/BUILD-SUMMARY.md` and
   `ARCHITECTURE.md` point here rather than restating it; keep it that way, so status can never
   disagree with itself.
4. Re-run `make gate` before ticking anything, and refresh the "Last verified" date above.

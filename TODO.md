# Hexflow — progress tracker

Living checklist of what is built and what is not. **Must be kept in sync with the code** — see
[`CLAUDE.md`](CLAUDE.md).

- [`HEXFLOW-SPEC.md`](HEXFLOW-SPEC.md) is the authority on *what* to build. This file only tracks
  *how far along* it is. If the two disagree, the spec wins and this file is wrong.
- Milestones and their exit criteria are §26 of the spec. A box is ticked only when the spec's exit
  criterion is **demonstrated**, not when the code looks finished.
- `make gate` is the arbiter. Anything ticked here should survive it.

Last verified: **2026-07-30** — Godot 4.7.1, 188 tests / 13,447 asserts green in ~60 s, 60 frozen
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
| M5 | Persistence & settings | 🟨 services only | resume-on-boot; settings and pause screens |
| M6 | Campaign data | 🟨 data only | level select, chapter unlocks, results screen |
| M7 | Art & feel | 🟨 board only | modifier glyphs (C5 gap), connectors, fonts, all §14 animation, all §15 audio |
| M8 | Tutorial | ⬜ not started | T1–T12 data-driven, naive playtest |
| M9 | Modes & Steam | 🟨 logic only | mode screens, GodotSteam, leaderboards |
| M10 | Accessibility & i18n | ⬜ not started | palettes, text scale, Reduce Motion, extraction |
| M11 | Release | ⬜ not started | Deck self-audit, three platform builds, depots |

Legend: ✅ exit criteria met · 🟨 partially built, criteria not met · ⬜ nothing built.

**Next up:** the modifier glyphs (M7). The C-18 board is on screen and playable — `make run` shows
prisms, `[` / `]` turn it — but it cannot yet draw a goal, a portal, a gate or a wild, which is a C5
gap against the grey-box it replaced. Nothing else in M7 goes in front of it.

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
      **labels**, not icons; the 24×24 icon textures are M7's §13.5 atlas, on these same slots
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

## M5 — Persistence & settings 🟨

Exit: persistence `@e2e` scenarios pass, including corrupted-save recovery and suspend/resume identity.

- [x] `save_service.gd` — atomic write, migration, corruption recovery with backup
- [x] `settings_service.gd` — defaults and typed access
- [x] Autosave of in-progress state on every commit, discard and undo (§18.1)
- [ ] **Read it back** — boot always restarts chapter 1 level 1; `in_progress` is written and never
      resumed (§18.2)
- [ ] Suspend/resume on focus loss (§18.3); undo history deliberately not persisted (C-16)
- [ ] Settings screen with all five tabs: Gameplay, Controls, Video, Audio, Accessibility (§12.2).
      Three controls are already wired and only need surfacing: cursor mode (snap/free), the haptics
      slider, and `custom_bindings` rebinding against `InputBindings.ACTIONS`
- [ ] Pause screen: Resume, Restart (hold), Settings, Quit to map (§12.2)
- [ ] Steam overlay opening auto-pauses gameplay (§12.5)
- [ ] `@e2e`: corrupted save reaches the menu with defaults and notifies once; suspend/resume
      identity; progress survives a quit from three different screens

## M6 — Campaign data 🟨

Exit: every level file validates and reproduces its par; the whole campaign is playable start to finish.

- [x] 60 generated, verified, frozen level files under `src/data/levels/chapter_N/`
- [x] `tools/author_levels.gd` sweeps seeds per slot against the chapter's par band
- [x] `tests/property/test_level_files.gd` re-verifies every shipped file on every push
- [x] Level schema documented — `src/data/schemas/level.md`
- [ ] **Main menu** — Campaign %, Endless best, Daily streak + reset timer, Settings, Quit (§12.2)
- [ ] **Level select** — hex-flower map reusing the board renderer, star pips, chapter progress (§9)
- [ ] **Chapter unlocks** — a chapter opens at 8 of 12 completed in the previous one (§7.1)
- [ ] **Results screen** — animated stars, placements vs par, Next / Replay / Map, focus on Next (§12.2)
- [ ] Hint-used dot on the star display (§12.6)
- [ ] `@e2e`: campaign playable boot → credits; completion recorded and progression advances (closes B6)

## M7 — Art & feel ⬜

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
      for radius 2 / 3 / 4 against the head-on 74 / 53 / 42. **Not in `level.tscn` yet**: a camera
      with no meshes to render would black out the grey-box, so the scene wiring lands with the
      `MultiMeshInstance3D` below. What is demonstrated is the camera itself —
      `tests/unit/test_board_camera.gd`, including that "clockwise" is clockwise *on screen*
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
- [ ] **C5 gap, knowingly open**: the 3D board draws no modifier glyphs, so goals, portals, gates and
      wilds are currently invisible on it — the grey-box distinguished all four. The glyph item below
      closes it. Nothing else in M7 should land before it
- [ ] Connectors with the depth gradient, as 3D geometry rather than §13.3's capsule SDF
- [ ] NEXT becomes a stack of upcoming tiles; remaining count shown for a campaign level's fixed tile
      array only, never for the unbounded endless/daily bag (C-18)
- [ ] Glyph legibility through rotation — billboarded, and still readable at every one of the six
      stops. **Closes the C5 gap above**, so it comes before anything else in M7: goal, portal, gate
      and wild all need their mark back
- [ ] Unshaded material path so §21's greyscale requirement survives lighting (C-18)
- [x] `board_rotate_cw` / `board_rotate_ccw` given an effect — bound in M4, live now. Turning re-feeds
      `InputRouter` with the new screen positions, so the cone and the cycling turn with the board
- [ ] Full palette token set audited — never a colour in a script or scene (§13.2)
- [ ] Fonts vendored, SIL-OFL only: Space Grotesk, Inter, JetBrains Mono; 18 px absolute floor (§13.4)
- [ ] Icon atlas, 9 line icons on a 24×24 grid (§13.5)
- [ ] Real §12.3 HUD layout: 56 px top bar, 400 px rail, 140 px NOW tile, 72 px NEXT, 56 px banner
- [ ] Every §14.1 timing, exactly as tabulated
- [ ] Goal-reached sequence §14.2; camera limited to §14.3 (2 px shake, once per completion)
- [ ] Four GPU emitters, hard cap 120 live particles (§14.4)
- [ ] Reduce Motion path: durations ×0.4, no shake/parallax/particles/breathing, still fully legible (§14.5)
- [ ] Audio: 5 chapter beds + menu track, two stems, ducking (§15.1)
- [ ] All 16 SFX (§15.2); `place.note` pentatonic ascent, resets per level, steps **down** on undo
      — `AudioDirector` already keeps the index, playback is what is missing
- [ ] Buses and sliders, −16 LUFS / −1 dBTP, `place.*` voice cap 4 (§15.3)
- [ ] Renderer measured Forward+ vs Mobile for the Deck export, result documented (C-3) — now with 3D
      shadows in the measurement, and no longer deferrable (C-18)

## M8 — Tutorial ⬜

Exit: a first-time player completes chapter 1 with no external explanation — verified by an actual
naive playtest, not a self-assessment.

- [ ] `src/data/tutorial.json` — beats are **data**, never hardcoded in level scripts (§10)
- [ ] T1–T12 (§10.2), each ≤12 words, diegetic, non-blocking after T1
- [ ] Beat flags in `save.tutorial_flags` so nothing repeats
- [ ] Settings → "Replay tutorial" resets the flags only
- [ ] Skippable at any time with one Back press

## M9 — Modes & Steam 🟨

Exit: mode `@e2e` scenarios pass, including the Steam-unavailable path.

- [x] `endless_run.gd` — §7.2 escalation, stage seeds as `fnv1a_32("endless:<seed>:<goals>")` (C-12)
- [x] `Generator.daily(utc_date)` — one puzzle per UTC day, verified solvable at generation
- [x] Both tested; `GameDirector.start_endless` / `start_daily` exist
- [ ] Endless screen and Run summary: goals, PB, leaderboard slice, Retry / Menu (§12.2)
- [ ] Daily screen: 7-day streak indicator, timer to reset, restart-only (§7.3)
- [ ] GodotSteam GDExtension linked, matched to the pinned engine (§16.1, C-2)
- [ ] Achievements; `endless_best_goals` and rolling daily leaderboards
- [ ] Steam Auto-Cloud for saves (no code)
- [ ] `@e2e`: Endless escalates and ends on a dead board; two clients generate an identical daily;
      **Steam unavailable never blocks play** and achievements queue locally

## M10 — Accessibility & i18n ⬜

Exit: accessibility `@e2e` scenarios pass; greyscale playthrough verified; 150% scale shows no clipping.

- [ ] Four alternate palettes as `.tres` swaps, zero code change (§21)
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

- [ ] `assets/` is an empty tree — `fonts/`, `sfx/`, `music/`, `icons/`, `glyphs/`, `i18n/` all
      unpopulated. §13.4 requires the fonts vendored before M7.
- [ ] `src/scenes/{main_menu,level_select,results,run_summary,settings}/` are empty directories.
      `GameDirector.SCENES` names all seven screens and `go_to()` silently no-ops on the five that
      do not resolve — harmless now, a silent dead end once something calls them.
- [ ] UI strings are literals pending the M10 extraction, which is why the §22 gate check skips.
- [ ] Legacy 2016 libGDX tree still occupies the repo root. Delete from `master` once the tile art
      is no longer needed as the Appendix A reference; it lives on in `legacy/libgdx-2016`.
- [ ] Music licensing route still undecided (C-6); daily scoring model still defaulted (C-7).

## Open spec questions

**Board radius is capped at 4 (C-19).** Growth up to there is free — radius is already a `Board`
parameter and the campaign ships radius 2, 3 and 4 — but `solver.gd`'s 64-bit path mask holds at most
62 cells, and radius 5 is 91. Late-game difficulty escalates walls, goals, gates and budget instead.

Unresolved items live in **Appendix C** of the spec (C-1 … C-8, C-19). Decisions already taken during
M0–M7 are recorded there too (C-9 … C-18, C-20 … C-22) — add to that table rather than inventing an
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

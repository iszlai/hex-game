# Hexflow — progress tracker

Living checklist of what is built and what is not. **Must be kept in sync with the code** — see
[`CLAUDE.md`](CLAUDE.md).

- [`HEXFLOW-SPEC.md`](HEXFLOW-SPEC.md) is the authority on *what* to build. This file only tracks
  *how far along* it is. If the two disagree, the spec wins and this file is wrong.
- Milestones and their exit criteria are §26 of the spec. A box is ticked only when the spec's exit
  criterion is **demonstrated**, not when the code looks finished.
- `make gate` is the arbiter. Anything ticked here should survive it.

Last verified: **2026-07-30** — Godot 4.7.1, 76 tests / 11,092 asserts green in ~48 s, 60 frozen
level files re-verified.

---

## Status at a glance

| M | Name | State | Blocking exit criterion still open |
|---|---|---|---|
| M0 | Skeleton | ✅ done | — |
| M1 | Logic core | ✅ done | — |
| M2 | Generator & solver | ✅ done | — |
| M3 | Grey-box playable | ✅ done | — (two §11.3 bindings missing, listed below) |
| M4 | Input & Deck | ⬜ not started | gamepad-only and touch-only `@e2e` playthroughs |
| M5 | Persistence & settings | 🟨 services only | resume-on-boot; settings and pause screens |
| M6 | Campaign data | 🟨 data only | level select, chapter unlocks, results screen |
| M7 | Art & feel | ⬜ not started | shaders, fonts, all §14 animation, all §15 audio |
| M8 | Tutorial | ⬜ not started | T1–T12 data-driven, naive playtest |
| M9 | Modes & Steam | 🟨 logic only | mode screens, GodotSteam, leaderboards |
| M10 | Accessibility & i18n | ⬜ not started | palettes, text scale, Reduce Motion, extraction |
| M11 | Release | ⬜ not started | Deck self-audit, three platform builds, depots |

Legend: ✅ exit criteria met · 🟨 partially built, criteria not met · ⬜ nothing built.

**Next up:** M4. The game is already playable, so controller support is what turns the grey-box into
something handable to a person, and `InputRouter` already solves the hard part (directional input
over a hex lattice).

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
- [x] Keyboard bindings, mouse click-to-place through `HexLayout.from_pixel` (closes B7)
- [x] Text HUD rail: now/next, undo, discard, wild, hint, restart, budget
- [x] Win, dead and auto-skip surfaced in the banner
- [x] Hint replays the solver from the live state, bounded (§12.6)
- [x] A radius-3 level is completable on the keyboard; win and dead states both reachable
- [ ] **Toggle legend** — §11.3 binds it to Tab / Select; no legend exists yet
- [ ] **Full WASD** — `D` is Discard, so "move right" is arrow-key only (§11.3 wants both)

> `BoardView._draw` is the seam M7 replaces. The grey-box must keep working through M7 — if an art
> change breaks the grey-box tests, the art change is wrong (§26 sequencing note).

## M4 — Input & Deck ⬜

Exit: gamepad-only and touch-only playthroughs pass as `@e2e`; snap never selects an illegal cell
over 200 random inputs.

- [ ] Full §11.3 gamepad column: A confirm, Y undo, X discard, L2+A wild, R2 hint, Start pause,
      B back, Select legend, hold-Select restart
- [ ] Hold gestures for every destructive action — nothing destructive on a single press (§11.3)
- [ ] L1/R1 bumper cycling bound to the existing `InputRouter.cycle()`
- [ ] Steam Input action sets: `Menu`, `Board`, `Modal` (§11.1)
- [ ] Touch-only path; every on-screen button ≥44 px at 1280×800 (§11.4)
- [ ] Controller glyph atlas, data-driven by `Input.get_joy_name`, Deck names for View/Menu (§11.4)
- [ ] Haptics table and the 0–100% slider, default 70% (§11.5)
- [ ] Surface `cycling_hint_wanted` as the toast after 3 cone rejections (§11.2)
- [ ] Free-cursor toggle exposed in Settings (the router mode already exists)
- [ ] `@e2e`: gamepad-only playthrough, touch-only playthrough, 200-input snap fuzz, bumper
      cycling visits all targets in clockwise order

## M5 — Persistence & settings 🟨

Exit: persistence `@e2e` scenarios pass, including corrupted-save recovery and suspend/resume identity.

- [x] `save_service.gd` — atomic write, migration, corruption recovery with backup
- [x] `settings_service.gd` — defaults and typed access
- [x] Autosave of in-progress state on every commit, discard and undo (§18.1)
- [ ] **Read it back** — boot always restarts chapter 1 level 1; `in_progress` is written and never
      resumed (§18.2)
- [ ] Suspend/resume on focus loss (§18.3); undo history deliberately not persisted (C-16)
- [ ] Settings screen with all five tabs: Gameplay, Controls, Video, Audio, Accessibility (§12.2)
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

- [ ] `src/shaders/hex_cell.gdshader` — pointy-top SDF, fill / stroke / glow (§13.3)
- [ ] One `MultiMeshInstance2D` for the whole board, per-instance custom data, single draw call
- [ ] Connector pass as rounded capsules with the depth gradient (§13.3)
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
- [ ] Renderer measured Forward+ vs Mobile for the Deck export, result documented (C-3)

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

Unresolved items live in **Appendix C** of the spec (C-1 … C-8). Decisions already taken during
M0–M3 are recorded there too (C-9 … C-17) — add to that table rather than inventing an answer, per
constraint C7.

---

## Keeping this file honest

1. Do not tick a box because the code exists. Tick it when the spec's exit criterion is
   demonstrated — usually a passing test named after the §24.2 scenario.
2. Update this file in the **same commit** as the work it describes.
3. This is the **only** place project status lives. `hexflow/docs/BUILD-SUMMARY.md` and
   `ARCHITECTURE.md` point here rather than restating it; keep it that way, so status can never
   disagree with itself.
4. Re-run `make gate` before ticking anything, and refresh the "Last verified" date above.

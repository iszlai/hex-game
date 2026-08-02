# CLAUDE.md

Guidance for Claude Code working in this repository.

## Keep TODO.md in sync — always

[`TODO.md`](TODO.md) is the progress tracker for the whole build. It is only useful if it is true.

- **Any change that starts, finishes or invalidates a checklist item updates `TODO.md` in the same
  commit as the code.** Not afterwards, not in a follow-up.
- **Never tick a box because the code exists.** Tick it when the spec's exit criterion for that
  milestone (§26 of [`HEXFLOW-SPEC.md`](HEXFLOW-SPEC.md)) is *demonstrated* — normally a passing test
  named after the §24.2 scenario it covers.
- **Run `make gate` before ticking anything**, and refresh the "Last verified" date at the top.
- Discovering that something believed done is not done is a normal outcome: un-tick it, note why.
- **`TODO.md` is the only place project status lives.** The other docs deliberately point at it
  instead of restating it. Keep it that way — do not reintroduce a milestone table, a "what is not
  built" list or a test count anywhere else, or the next reader gets two answers and no way to tell
  which one rotted.

## Git workflow

Single developer, so there is no review to wait for and no branch protection to route around.

- **Commit and push directly to `master` after every step.** No feature branches, no pull requests.
  Do not ask first — landing work is the expected end of a step.
- **One concern per commit.** A commit is a step someone could revert on its own: the rule change and
  its test together, the doc that describes it in the same commit, an unrelated cleanup in its own.
  Never bundle two ideas because they happened in the same session.
- **Descriptive messages.** Subject line in the imperative under ~70 characters, then a body that
  says *why* — what was wrong, what the alternative was, what a reader would otherwise have to
  reconstruct from the diff. The diff already shows what changed.
- **`make gate` before every push.** `master` is releasable (§25); a red `master` is worse than an
  unpushed commit.

## Read these before writing code

| Document | For |
|---|---|
| [`hexflow/docs/ARCHITECTURE.md`](hexflow/docs/ARCHITECTURE.md) | Where things live and why. Start here. §9 lists the GDScript gotchas that cost real time |
| [`HEXFLOW-SPEC.md`](HEXFLOW-SPEC.md) §4, §5, §16, §24 | Coordinate math, ruleset, layering, acceptance criteria. The spec is the authority on *what* the game is |
| [`TODO.md`](TODO.md) | What is done, what is next |
| [`hexflow/docs/ASSET-REQUIREMENTS.md`](hexflow/docs/ASSET-REQUIREMENTS.md) | Every image, colour, sound and setting someone outside the repo has to provide, and what stands in for it today |
| [`hexflow/docs/DESIGN-GAPS.md`](hexflow/docs/DESIGN-GAPS.md) | What stands between a spec-complete build and a game someone plays twice. Separates defects from decisions that need making |
| [`hexflow/docs/MAP-EDITOR.md`](hexflow/docs/MAP-EDITOR.md) | Brief for the hand-authoring tool — `make edit-maps`. Includes why it does not violate §27's "no level editor", and §8's rules that keep it that way |
| [`hexflow/docs/MUSIC-HANDOFF.md`](hexflow/docs/MUSIC-HANDOFF.md) | How to replace §15.1's beds by hand from the exported MIDI. Self-contained, written for somebody outside this repository |
| [`hexflow/docs/MUSIC-REWORK.md`](hexflow/docs/MUSIC-REWORK.md) | Why the six beds are one recording copied six times, and the order to fix it in. Read before touching the music |

The spec outranks every other document. If code and spec disagree, the code is a bug. If the **spec**
is wrong, log it in Appendix C and fix it there — do not silently diverge (constraint C7).

## Where the work happens

`hexflow/` is the game, and now the only code in the tree. The 2016 libGDX prototype that used to
sit beside it was removed from `master`; it lives at the `libgdx-2016` tag if you ever need to look.

```sh
make godot   # fetch the pinned engine into .tools/
make run     # play it
make test    # whole suite, ~50 s
make gate    # everything CI runs — before every push
make playtest # play as a first-time player; your save is moved aside, not deleted
make edit-maps # draw a campaign board by hand
make play-draft FILE=drafts/x.json  # play any level file in the real game
make         # list targets
```

## Non-negotiable rules

These are grep-enforced by `hexflow/tools/ci_gate.sh`, not by review. Each maps to a real defect in
the 2016 prototype (Appendix B).

- `src/core/` → `src/app/` → `src/view/` + `src/scenes/`. **The arrow never reverses.** No `Node`,
  `Control`, `Input`, `Texture`, `PackedScene`, `get_tree` or `get_node` in `src/core/` (C1, B4).
- **No floats in `src/core/`.** Pixel math lives in `src/view/hex_layout.gd` (C3, C-13).
- **No global `randi()` / `randf()` / `randomize()` anywhere in `src/`.** Only `TileStream` and
  `Generator` own an RNG, both explicitly seeded (C2, B8).
- **Exactly six autoloads.** `InputRouter` and `LevelRepository` are deliberately not singletons.
- **Nothing allocates in `_process` / `_draw`** — prebuild geometry in `bind()` (C4, B5).
- **Cells are `Vector3i`.** Never wrap a coordinate in a `RefCounted` and use it as a key (B1).
- **Every visible state is distinguishable without colour** — glyph, shape or stroke weight (C5).
- **Never regenerate campaign levels at runtime.** They are frozen JSON; a re-seed invalidates every
  stored par and star. `make levels` is an offline authoring step whose output gets committed.
- **Do not permute the direction table.** Its index order is baked into the bag, the solver and every
  save file. `tests/unit/test_direction.gd` will stop you.
- **Do not add a sixth modifier.** §6 ships exactly five and says so.
- **Nothing in `src/` may reference `tools/`.** The map editor reads the game; the game never
  reads the editor, and `tools/` is excluded from the export preset. That one-way arrow is the
  whole reason an authoring tool is not the level editor §27 declined (MAP-EDITOR §8).

## Adding things

New rule or mechanic: Gherkin scenario in §24.2 → test in `tests/unit/` → code in `src/core/` →
teach the solver (a mechanic it cannot model makes every generated par silently wrong) → then the
view. New screen: add to `GameDirector.Screen` and `SCENES`; no screen pushes another screen
directly. New colour: `src/view/palette.gd` plus the `.tres`, never inline.

# Hexflow

A calm, controller-first hex-path puzzler for Steam Deck and desktop. Rebuild of the 2016
`com.hexgame` libGDX prototype, specified in [`../HEXFLOW-SPEC.md`](../HEXFLOW-SPEC.md).

You are dealt one direction at a time. Grow a glowing path across a honeycomb board to reach the
goal — using the direction you were given, not the one you wanted.

## Pinned versions

Both are pinned exactly, never floated (§16.1, §25).

| Component | Version |
|---|---|
| Godot | **4.7.1-stable** |
| GUT (vendored in `addons/gut`) | **9.7.1** |
| Renderer | GL Compatibility (2D-only game; re-measure against Forward+ at M7, decision C-3) |

Download the matching editor from
`https://github.com/godotengine/godot/releases/tag/4.7.1-stable`.

## Layout

```
src/core/     pure logic: no node, scene, texture or Input reference, no floats, no global RNG
src/app/      services and the six autoloads
src/view/     board rendering, palette, hex↔pixel layout
src/scenes/   screens
src/data/     frozen level files, palettes
tests/        unit (core), property (generator/solver/level files), e2e (real scenes)
tools/        offline authoring and capture scripts — not shipped
```

The dependency arrow never reverses: `core → app → view`. The view sends *intents* and receives
*facts*; it owns no rules. This boundary is the whole point — the 2016 prototype fused rules into
its screen class and became untestable (defect B4).

## Running

Everything goes through the Makefile at the repository root.

```sh
make godot          # fetch Godot 4.7.1 into .tools/ — no system install
make run            # play at the 1280x800 Deck reference resolution
make test           # @core, @property and @e2e
make gate           # the full push gate; run this before pushing
make                # list every target
```

To use an engine you already have, pass it in: `make test GODOT=/path/to/Godot`.

Raw equivalents, if you would rather not use make:

```sh
GODOT=/path/to/Godot                       # 4.7.1-stable

$GODOT --path . --resolution 1280x800
$GODOT --headless -s res://addons/gut/gut_cmdln.gd \
    -gdir=res://tests -ginclude_subdirs -gexit -gprefix=test_
GODOT=$GODOT ./tools/ci_gate.sh
```

## Documentation

| Document | What it is for |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | **Start here if you are new.** Codebase tour, layering rules, data flow, gotchas |
| [`docs/BUILD-SUMMARY.md`](docs/BUILD-SUMMARY.md) | What is built, what is not, what was learned |
| [`src/data/schemas/level.md`](src/data/schemas/level.md) | The level file format |
| [`../HEXFLOW-SPEC.md`](../HEXFLOW-SPEC.md) | The authoritative design specification |

## Authoring campaign levels

Campaign levels are **frozen data**, generated offline and then never regenerated or re-seeded at
runtime — a re-seed would change the tile sequence and silently invalidate every stored par, star
and comparison (§9, §27).

```sh
make levels             # all 60
make levels CHAPTER=3   # one chapter
```

Every candidate is proved solvable by the solver before it is written, and
`tests/property/test_level_files.gd` re-verifies each shipped file on every push.

## Capturing a screenshot

```sh
make shot OUT=board.png PRESSES=cceccc
```

The press string sends one key per frame: `c` confirm, `z` undo, `q`/`e` cycle, `d` discard,
`h` hint. Letters only — Godot drops a whitespace-only command-line argument.

## Status

| Milestone | State |
|---|---|
| M0 Skeleton | done |
| M1 Logic core | done — every `@core` scenario of §24.2 passes headlessly |
| M2 Generator & solver | done — `@property` sweep green, no unverified candidate can be accepted |
| M3 Grey-box playable | done — a level is completable with the keyboard; win and dead states reachable |
| M6 Campaign data | levels generated and frozen; level select and chapter unlocks still to build |
| M4, M5, M7–M11 | not started |

Full detail, including the two specification defects found during the build, is in
[`docs/BUILD-SUMMARY.md`](docs/BUILD-SUMMARY.md).

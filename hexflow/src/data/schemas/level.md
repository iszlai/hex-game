# Level file schema (v1)

`src/data/levels/chapter_N/level_MM.json`. Corresponds to §17.1 of the specification.

Campaign levels are **frozen data**. They are produced offline by
`tools/author_levels.gd`, verified by the solver before they are written, and re-verified by
`tests/property/test_level_files.gd` on every push. They are never regenerated or re-seeded at
runtime: a re-seed would change the tile sequence and silently invalidate every stored par, star
and comparison.

```json
{
  "schema": 1,
  "id": "c2_l07",
  "chapter": 2,
  "index": 7,
  "radius": 3,
  "start": [-3, 0, 3],
  "goals": [[3, 0, -3]],
  "walls": [[-1, 1, 0]],
  "portals": [[[0, 0, 0], [2, -2, 0]]],
  "gates": [],
  "wilds": [],
  "tiles": ["NE", "E", "NW"],
  "discards": 3,
  "budget": null,
  "par": 9,
  "solution": [[-2, 0, 2], [-1, -1, 2]],
  "solution_script": [[0, [-2, 0, 2]], [2, [0, 0, 0]], [0, [-1, -1, 2]]],
  "generator": { "seed": 918273, "params_version": 1 }
}
```

| Field | Type | Notes |
|---|---|---|
| `schema` | int | A file with a higher schema than the build understands is **rejected with a clear error**, never reinterpreted |
| `radius` | int | The size the shape was *asked* for, which is only its radius when it is a hexagon. 61 cells is the ceiling however they are arranged — the limit the solver's 64-bit path mask allows |
| `shape`, `shape_arg` | string, int | C-32's silhouette and the number that shapes it: the ring's hole, the corridor's width, the hourglass's waist. Absent means `hexagon`, which every file written before C-32 is |
| `cells` | cube triples, optional | **When present it is the board**, and `shape` is only a label for what it started as. Written by the map editor for a board that has had cells added or removed by hand, and by nothing else — the sweep's boards are exactly their shape, so they stay three numbers |
| `start`, `goals`, `walls`, `gates`, `wilds` | cube triples | Every coordinate satisfies `x + y + z == 0` and lies within `radius` |
| `portals` | array of pairs | Each pair is two cube triples; pairing is reciprocal |
| `tiles` | direction names | `NW NE E SE SW W` — the fixed sequence, consumed in order. Exhausting it ends the level |
| `discards` | int | Voluntary discard charges. Free auto-discards never consume one |
| `budget` | int or `null` | Hard placement cap; exceeding it is `DEAD` |
| `par` | int | The solver's optimum for this exact tile sequence, so ★★★ is always attainable |
| `solution` | cube triples | The optimal placement targets, in order. Used by tests and hints, never shown |
| `solution_script` | `[kind, cube]` pairs | Extension beyond §17.1. `kind` is `0` place, `1` wild, `2` discard. The bare target list of `solution` cannot express the voluntary discards an optimal line may need, so it is not replayable on its own — this is why the field exists |
| `generator` | object | Provenance for reproducing the level. Never read at runtime |

## Validation

`Level.validate()` runs on every load and checks structure: coordinates on-board and cube-valid,
start and goals not walls, portals reciprocally paired, `tiles` at least as long as `par`,
`budget` not below `par`.

`LevelRepository.verify()` adds the expensive half — it re-runs the solver, confirms the stored
par is reproduced, and replays `solution_script` through the real `GameState` to confirm it still
reaches `WON`. Debug builds assert on a validation failure; release builds skip the level and log,
so one bad file can never brick a player's campaign.

# hex-game

Hexflow — a hex-lattice puzzle game for Steam Deck and desktop, built in Godot.

## `hexflow/` — the game

Godot 4.7.1, GDScript, targeting Steam Deck and desktop. It is the whole of this branch.

```sh
make godot     # fetch the pinned engine into .tools/ — no system install needed
make run       # play it
make test      # the whole suite
make           # list every target
```

| Document | What it is for |
|---|---|
| [`hexflow/docs/ARCHITECTURE.md`](hexflow/docs/ARCHITECTURE.md) | **Start here if you are new.** Codebase tour, layering rules, data flow, gotchas |
| [`TODO.md`](TODO.md) | Progress tracker — every milestone, ticked against its exit criteria |
| [`hexflow/docs/BUILD-SUMMARY.md`](hexflow/docs/BUILD-SUMMARY.md) | What is built, what is not, what was learned |
| [`HEXFLOW-SPEC.md`](HEXFLOW-SPEC.md) | The authoritative design and build specification |
| [`CLAUDE.md`](CLAUDE.md) | Working rules for agents, including the `TODO.md` sync obligation |
| [`hexflow/README.md`](hexflow/README.md) | Pinned versions and the raw commands behind the Makefile |

## The 2016 prototype — removed

The repository began as `com.hexgame`, a ~770-line libGDX 1.9.2 prototype: Java, machine-translated
to Scala 2.11, targeting desktop/Android/iOS/GWT. It never became playable. It is no longer in this
branch — `master` holds the Godot game and nothing else.

```sh
git checkout libgdx-2016    # the prototype, exactly as it was
```

It is preserved at the **`libgdx-2016` tag** and on the `legacy/libgdx-2016` branch. Nothing here
depends on it:

- Its tile art (`android/assets/hex_A.png` … `hex_F.png`) was the *provenance* of the direction
  table in Appendix A of the specification. That table is now written out in full there and asserted
  row by row by `tests/unit/test_direction.gd`, which is what makes it the authority.
- Its defects are catalogued in Appendix B — each one a trap the rebuild is explicitly designed to
  avoid. They are described in prose, not by reference to the sources.

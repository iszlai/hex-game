# hex-game

This repository holds two things: a 2016 libGDX prototype, and the Godot rebuild that replaces it.

## `hexflow/` — the current game

The active project. Godot 4.7.1, GDScript, targeting Steam Deck and desktop. See
[`hexflow/README.md`](hexflow/README.md) to run it, and [`HEXFLOW-SPEC.md`](HEXFLOW-SPEC.md) for the
full design and build specification.

## The 2016 prototype — being retired

Everything else at the top level (`core/`, `desktop/`, `android/`, `ios/`, `html/`, the Gradle
build) is the original `com.hexgame` libGDX prototype: Java, machine-translated to Scala,
never playable. It is kept only until the rebuild no longer needs it as a reference.

**Migration plan.** The prototype is preserved on the `legacy/libgdx-2016` branch, which is pinned
at the last commit that contains it. Once `hexflow/` no longer needs the old sources for reference,
the legacy tree is deleted from `master` and lives on only in that branch and in history.

```sh
git checkout legacy/libgdx-2016    # the 2016 prototype, exactly as it was
```

Its art (`android/assets/hex_A.png` … `hex_F.png`) is the authority for the direction table in
Appendix A of the specification, and its defects are catalogued in Appendix B — each one is a trap
the rebuild is explicitly designed to avoid.

![The 2016 prototype](game.png?raw=true "The 2016 prototype")

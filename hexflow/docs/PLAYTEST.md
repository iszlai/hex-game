# The M8 playtest

§26's exit criterion for the tutorial is the only one in the whole spec that a
machine cannot check:

> A first-time player completes chapter 1 with **no external explanation** — verified by an actual
> naive playtest, not a self-assessment.

Everything else in M8 is built and tested. This is what is left, and it needs one person who has
never seen the game and about twenty minutes.

---

## Running it

```sh
make playtest          # moves your save aside, launches at 1280×800
make playtest-restore  # puts your save back
```

Your save is **moved, not deleted** — the backup sits beside it in `user://`. Two resets in a row
will not overwrite it.

You need a fresh save because every beat writes a flag the moment it is shown. Yours have been set by
weeks of playing and by the test suite. Launching normally would show a tutorial that has already
happened.

---

## The one rule

**Say nothing.** Not "try clicking there", not "you can undo", not a hum of approval when they get it
right. The criterion is *no external explanation*, and a hint from the person who built it
invalidates the run — you cannot ship yourself standing behind every player.

If they ask a direct question, write it down and say "I want to see what you'd do." If they are truly
stuck and frustrated after two full minutes, end the session. **That is a result, not a failure of
the session.**

---

## What to write down

Only two things matter, and both are observations rather than opinions.

**1. Where they hesitated.** Every pause over three seconds, and what they were looking at. A pause is
the tutorial not having said something yet, or having said it somewhere they were not looking.

**2. What they did that the game did not expect.** Clicking a wall. Trying to drag. Pressing Escape
to mean "back". Looking for the tile queue on the left. Each one is a thing the interface implied and
did not mean.

Do **not** record whether they liked it. A tutorial that is enjoyable and leaves someone unable to
play has failed this criterion; one that is dry and leaves them playing has passed.

---

## The twelve beats, and what each one has to actually achieve

The beat fires either way — what is being tested is whether it *lands*. Watch for the behaviour, not
for the player reading the words.

| | Level | The words | Passed if |
|---|---|---|---|
| T1 | 1-1 | Your tile points *north-east*. | They place without being told to click |
| T2 | 1-1 | The path grows. Reach the goal. | They aim at the goal rather than wandering |
| T3 | 1-2 | The tiles to come are shown here. | They look at the rail again later, unprompted |
| T4 | 1-3 | Grow from any path cell. | They branch, rather than only extending the tip |
| T5 | 1-4 | Undo is free. Always. | They undo at some later point without hesitating |
| T6 | 1-5 | No legal move — tile skipped, no cost. | They do **not** think they were punished |
| T7 | 2-1 | Walls never open. | They stop aiming at walls |
| T8 | 2-2 | Discard a tile you cannot use. | They discard on purpose, at least once |
| T9 | 3-1 | Two goals. Plan the fork. | They notice the second goal before running out |
| T10 | 4-1 | Gates need two connections. | They approach a gate twice rather than once |
| T11 | 4-4 | Portals link both ends. | They use a portal deliberately |
| T12 | 5-1 | Wild: choose any direction once. | They spend the charge rather than hoarding it |

The criterion is **chapter 1** — T1 to T6. The rest are worth watching if the session runs on, but
they are not what M8 is blocked on.

---

## The result

Whatever happens, write it into [`TODO.md`](../../TODO.md) under M8 — how many people, what they got
stuck on, and whether chapter 1 was completed without help.

- **Completed without help** → M8's exit criterion is met. Tick it.
- **Stuck** → M8 stays open, and the note says where. That is the more useful outcome of the two: it
  names the next thing to build instead of leaving it to be guessed at.

Two known gaps to compare against, both deliberately unbuilt pending exactly this session — §10.2's
T10 asks for *two ghost stubs* on a gate and T3 for the preview *scaling* 1.15×. If nobody is
confused by gates, the stubs are decoration and should stay unbuilt.

**One playtester is enough to find a blocking problem. It is not enough to prove there isn't one** —
if the first person sails through, that is worth knowing, and a second person is still worth finding.

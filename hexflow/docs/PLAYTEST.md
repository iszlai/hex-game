# The M8 playtest

§26's exit criterion for the tutorial is the only one in the whole spec that a
machine cannot check:

> A first-time player completes the tutorial and chapter 1 with **no external explanation** —
> verified by an actual naive playtest, not a self-assessment.

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

You need a fresh save because §10's course runs **once per save**, on the first launch, straight out
of the boot screen. Yours has been through it, so launching normally goes to the main menu and the
five teaching boards are never seen.

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

## The five boards, and what each one has to actually achieve

Every board can be finished by pressing confirm on the lit cell, so **finishing is not the test** —
what is being tested is whether the idea lands somewhere the player can use it afterwards. Watch the
behaviour on the campaign levels that follow, not the reading of the words.

| | Board | The idea | Passed if |
|---|---|---|---|
| 1 | First flow | A tile points a direction | They place without being told to click, and aim at the goal |
| 2 | Around the wall | A wall never opens | They stop aiming at walls in chapter 1 |
| 3 | Through the portal | A portal joins both ends | They use a portal deliberately when one appears |
| 4 | Two ways in | A gate wants two neighbours | They approach a gate twice rather than once |
| 5 | One free step | A charge goes any direction | They spend a charge rather than hoarding it |

Two things the course deliberately does **not** teach, because §10.1 allows one idea per board: the
free auto-skip and the voluntary discard. Watch for both in chapter 1 — a player who thinks a skipped
tile was a punishment, or who never discards, has found the next lesson worth writing.

The criterion is **the course and chapter 1**. Everything past that is worth watching if the session
runs on, but it is not what M8 is blocked on.

---

## The result

Whatever happens, write it into [`TODO.md`](../../TODO.md) under M8 — how many people, what they got
stuck on, and whether chapter 1 was completed without help.

- **Completed without help** → M8's exit criterion is met. Tick it.
- **Stuck** → M8 stays open, and the note says where. That is the more useful outcome of the two: it
  names the next thing to build instead of leaving it to be guessed at.

One known gap to compare against, deliberately unbuilt pending exactly this session: nothing on the
board *draws* what a gate wants — §10.3's T7 says two neighbours and the board shows a ring, not two
ghost stubs. If nobody is confused by gates, the stubs are decoration and should stay unbuilt.

**One playtester is enough to find a blocking problem. It is not enough to prove there isn't one** —
if the first person sails through, that is worth knowing, and a second person is still worth finding.

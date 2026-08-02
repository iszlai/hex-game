# Reworking the music

**Brief for a fresh session.** What the six beds are today, why that is not where they should stop,
and the order to do it in. [`MUSIC-HANDOFF.md`](MUSIC-HANDOFF.md) is the *how* — the DAW workflow,
step by step. This is the *what and why*, and it assumes you have read neither.

Status lives in [`TODO.md`](../../TODO.md), not here. If the two disagree, `TODO.md` wins.

---

## 1. Where it stands

`assets/music/` holds eighteen `.ogg` files: six beds × three stems. **All six beds are currently
the same recording** — chapter 1's — copied across. That was a deliberate stopgap so the game has
coherent music everywhere while the real work waits for a session with time for it.

| | What it is |
|---|---|
| `chapter_1_*` | A real performance: chapter 1's own score, played in GarageBand |
| `menu_*`, `chapter_2..5_*` | Byte-identical copies of the above |

Every row in `TRACKS` (`tools/make_music.gd`) is marked `handmade: true`, so `make music` rewrites
the `.mid` files and leaves the audio alone. That flag is currently telling a half-truth for five of
the six: it is protecting a *copy*, not a performance. It is set that way on purpose — the
alternative is `make music` silently replacing the good recording with the synthesiser — but it is
the first thing to correct as each real bed lands.

**The menu bed that was played for the menu score still exists**, at commit `23c262a`. It is the only
one with drums, it was made and then overwritten by the copy, and restoring it is one command:

```sh
git checkout 23c262a -- hexflow/assets/music/menu_base.ogg \
                        hexflow/assets/music/menu_layer.ogg \
                        hexflow/assets/music/menu_extra.ogg
```

Do that before anything else if the plan is to keep it.

---

## 2. The thing actually worth fixing

The melody. It is why this document exists.

`layer — melody` is the stem that fades in mid-level as a run gets past about 40% of par — §15.1's
adaptive half, and the game's main signal that the player is getting somewhere. The person who
performed these beds found it **irritating**, and mixed it 12–15 LU below the bed to get away from
it. That works, in the sense that you stop noticing it. It also means the feature is inaudible, which
is the state it spent most of its life in.

**Turning it down is treating the symptom.** The line itself is the problem, and it is a defect in
`_melody_notes` rather than a matter of taste:

- Notes are drawn **at random from a two-octave pool**, so consecutive notes leap unpredictably.
- Every note gets an **echo a dotted eighth later**, doubling the event count.
- The result reads as somebody soloing, which is the one thing a bed must never do.

The file's own comment says *"nobody wants to be soloed at while they think"*, and then the code
does exactly that. A line that wanders keeps pulling attention back; a line that steps gently is
furniture. That difference is what decides whether the melody can be left audible.

### The proposed change

In `_melody_notes` (`tools/make_music.gd`):

| Now | Change to |
|---|---|
| Random draw across two octaves | One octave |
| Any note may follow any note | Pick a **neighbour** of the previous note — steps, not leaps |
| Echo on every note | No echo |
| 3–4 notes a bar | Fewer, longer, more space between phrases |

Take the same care with `_counter_notes`, which has the same shape and the same problem an octave
down.

**Do not simply lower the gains.** The point is a melody that can sit at the composed beds' ~5 LU
under the bed and still be welcome. If it still wants to be 15 LU down after the rewrite, the rewrite
did not work.

There is a worked precedent for this kind of fix in the file's history: `git log` for the pads → lo-fi
jazz change (C-42) and the handpan experiment that followed it. Both were cases where the *structure*
of the writing was wrong and no amount of mixing would have rescued it.

---

## 3. The order to do it in

1. **Restore the menu bed** from `23c262a`, if it is being kept (§1).
2. **Rewrite `_melody_notes` and `_counter_notes`** (§2).
3. **`make music`** — this rewrites all six `.mid` files from the new score. It will not touch audio
   while the rows are marked `handmade`.
4. **Listen to the new line first.** Temporarily clear `handmade` on one row, render it, and play the
   synthesised version. The synth is a placeholder and sounds it, but you are judging the *notes*.
   Iterate here — it costs 90 seconds a go, against an hour a go in the DAW.
5. **Only then re-export**, bed by bed, following `MUSIC-HANDOFF.md`.
6. **Set `handmade: true` with an honest comment** on each row as its real performance lands, and
   delete the placeholder note.

Step 4 is the whole reason this is worth doing in this order. Every DAW round trip in the session
that produced these beds cost roughly an hour; every generator round trip costs a minute and a half.
Settle the notes before anyone opens GarageBand.

---

## 4. What the DAW work costs, and the traps in it

All of these were hit for real. `MUSIC-HANDOFF.md` now warns about each, but they are worth knowing
before you start rather than after.

| Trap | What happens | Guard now in place |
|---|---|---|
| **Auto Normalize** | GarageBand normalises each export separately, so the quiet `layer` is lifted to full scale and arrives louder than the piano. Every stem sounds correct alone; only the balance is destroyed | `import_music.sh` refuses a set whose stems all peak alike. `MUSIC-HANDOFF.md` §6.1 |
| **Project tempo** | GarageBand opens at 120 BPM and often ignores the file's tempo | Length check derives the expected duration from the tempo |
| **Two tracks called "Vibraphone"** | The melody and counter arrive on identical patches; muting the wrong one during export is invisible until the game plays it | Rename tracks to match their regions, `MUSIC-HANDOFF.md` §6 step 3 |
| **Bass transposed +12** | GarageBand may shift a region an octave to fit the instrument's range. Sounds "fine but wrong" | Not automatable — check by ear, solo the bass |
| **The doubling and cycle** | Setting a cycle over bars 49–97 identically three times is the hardest manual step, and it went wrong twice | **Removed.** Export the whole song; `import_music.sh` takes the second pass by arithmetic |

The reason for the doubling is worth keeping in mind even though the manual step is gone: the loop's
ring-*in* comes from the first pass, which is what makes the seam inaudible without a cross-fade. The
arrangement still has to be played twice. Only the export selection was automated away.

---

## 5. Per-bed parameters

From `TRACKS` in `tools/make_music.gd`, which is the authority. Keys are §15.1's.

| File | Tempo | Key | Drums |
|---|---|---|---|
| `menu.mid` | 70 | A minor | **yes** — 5 tracks |
| `chapter_1.mid` | 70 | C major | no — 4 tracks |
| `chapter_2.mid` | 72 | B♭ major | no |
| `chapter_3.mid` | 72 | G minor | no |
| `chapter_4.mid` | 74 | E minor | no |
| `chapter_5.mid` | 76 | D minor | no |

Only `menu` may have drums. §15.1 says "no percussion in campaign", and the menu bed — which also
plays behind endless and the daily — is not a campaign bed. That reading is deliberate and it is the
whole reason the menu has a beat; a `chapter_*` row that sets `beat` is a spec violation rather than
a style choice.

Instruments that were chosen and liked: **Classic Suitcase Mk IV** on the piano, **Upright Studio
Bass**, vibraphone on both melodic parts, a soft kit on the menu's drums.

---

## 6. Levels

`import_music.sh` applies **one** gain across all three stems to reach §15.3's −16 LUFS, capped so
the three together stay under −1 dBTP. One gain, not one per stem: `base` and `layer` are not meant
to be equally loud, and normalising them separately is a remix rather than a level correction.

A mix that comes back a few decibels hot is therefore not worth a re-export. A mix whose *balance*
is wrong is, because nothing downstream can recover it.

Two known faults in what is committed, both raised at the time and both accepted:

- The beds sit around −18 LUFS against the composed ones' −16.6.
- The layer sits 12–15 LU under the base where the composed beds use about 5 — §2's problem, seen
  from the mixing end.

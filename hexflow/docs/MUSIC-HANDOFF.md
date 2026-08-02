# Replacing the music by hand

**Read this first if you are helping somebody turn `drafts/music/*.mid` into the game's soundtrack.**
Everything needed is here; you do not need the rest of the repository, the spec, or any prior
conversation.

---

## 1. What exists today

The game ships six pieces of music, **composed in the repository** by `tools/make_music.gd` and
rendered by a small synthesiser written in the same file. It is deliberate placeholder work: the notes
are honest and the instruments are sine waves. A real instrument on the same notes is a large
improvement for very little work, and that is the whole job here.

Two outputs come out of every render:

| Path | What it is |
|---|---|
| `hexflow/assets/music/*.ogg` | **18 files** — what the game loads |
| `hexflow/drafts/music/*.mid` | **6 files** — the same notes, editable. Not shipped |

`drafts/` is excluded from the game's export filter, so nothing there ever reaches a player.

---

## 2. The one rule that everything else follows

Each piece is delivered as **three files that play at the same time**:

| File | Contains | When the game plays it |
|---|---|---|
| `<track>_base.ogg` | piano + bass | Always |
| `<track>_layer.ogg` | the melody | Fades in past the middle of a level, out if the player undoes back |
| `<track>_extra.ogg` | the counter-line | Endless mode only, from 5 goals onward |

They are mixed live, on top of each other. So:

> **One project, exported three times, muting parts between exports.**
> Never three separate renders, three separate takes, or three variations — however good each one
> sounds on its own. Two renders of "the same" piece drift apart by milliseconds and phase against
> each other. This is not a quality problem a better performance fixes.

If only one file per track comes back, name it `<track>_base.ogg` and the game will play it with no
adaptive layer. That is a valid, lesser delivery.

---

## 3. The six pieces

Bars are 4/4. Every piece is **48 bars**, which is three turns of a 16-bar chord loop.

| MIDI file | Tempo | Key | Where it plays |
|---|---|---|---|
| `menu.mid` | 70 BPM | A minor | Menus, endless, daily |
| `chapter_1.mid` | 70 BPM | C major | Chapter 1 — bright, the opening hour |
| `chapter_2.mid` | 72 BPM | B♭ major | Chapter 2 — walls |
| `chapter_3.mid` | 72 BPM | G minor | Chapter 3 — branching |
| `chapter_4.mid` | 74 BPM | E minor | Chapter 4 — gates and portals, darker |
| `chapter_5.mid` | 76 BPM | D minor | Chapter 5 — pressure, the tense one |

**GarageBand does not always adopt a MIDI file's tempo.** Set it by hand from this table, or the
swing will land in the wrong places and the loop length will be wrong.

### The tracks inside each file

Four tracks, named after the stem they belong to so the muting is unambiguous:

| Track name in the MIDI | Suggested instrument | Stem |
|---|---|---|
| `base — rhodes` | Electric piano (Rhodes) | base |
| `base — bass` | Upright / acoustic bass | base |
| `layer — melody` | Something soft: flute, muted horn, soft synth lead | layer |
| `extra — counter` | Similar to the melody, darker or lower | extra |

The melody deliberately never starts on a downbeat: it fades in while the player is mid-thought, and
a line that begins on the "one" announces itself as something new.

---

## 4. What the music is for

- It plays for **hours** under a quiet puzzle game. Nothing may demand attention.
- Style is **lo-fi jazz**: electric piano comping sevenths and ninths, upright bass, tape noise,
  swung eighths, plenty of space.
- **No drums in the campaign.** This is a hard constraint, not a preference. Vinyl crackle and hiss
  are fine — they are texture, not a beat.
- Tempo must stay in **70–85 BPM**.
- The player can hear one piece for an hour. Sparse beats busy every time.

---

## 5. Making the loop seamless

This is the part that is easy to get wrong and impossible to miss once wrong.

The file loops forever with no gap. If the last chord is still ringing when the file ends, the loop
point clicks. Cross-fading is **not** the fix — it audibly ducks the music every two minutes.

**The trick, in any DAW:**

1. Arrange the piece once, 48 bars.
2. Copy the whole arrangement so it plays **twice**: bars 1–48 and 49–96.
3. Export **only bars 49–96**.

The second pass starts with the first pass's reverb and decay already ringing into it, which is
exactly what the loop needs — the tail that runs off the end is already present at the beginning.

In GarageBand: turn on the Cycle area, drag it to cover bars 49–96, and tick **"Export cycle area
only"** in the export dialog.

All three exports must use the same cycle region so the files are the same length to the sample.

---

## 6. Exporting from GarageBand, step by step

1. Drag `menu.mid` into an empty GarageBand project. Four software-instrument tracks appear.
2. Set the project tempo from the table in §3.
3. Assign instruments per track (§3).
4. Duplicate the arrangement to play twice; set the cycle area over the second pass (§5).
5. Balance it. The piano and bass are the bed; the melody sits **under** them, not over.
6. Export three times — `Share ▸ Export Song to Disk…`, **AIFF or WAV**, 44.1 kHz:

| Export | Mute these tracks | Save as |
|---|---|---|
| 1 | `layer — melody`, `extra — counter` | `menu_base.wav` |
| 2 | `base — rhodes`, `base — bass`, `extra — counter` | `menu_layer.wav` |
| 3 | `base — rhodes`, `base — bass`, `layer — melody` | `menu_extra.wav` |

Do not change volume, tempo, effects or the cycle region between exports. Only mutes.

7. Repeat for the other five pieces.

---

## 7. Levels

| Target | Value | Measured on |
|---|---|---|
| Integrated loudness | **−16 LUFS** | `base` + `layer` together |
| True peak | **≤ −1 dBTP** | all three together |

The `base` alone will measure quieter than −16, and that is correct — it is not what the player hears
most of the time.

Check a finished pair:

```sh
ffmpeg -i menu_base.wav -i menu_layer.wav \
  -filter_complex "amix=inputs=2:normalize=0,ebur128=peak=true" -f null /dev/null
```

Read `I:` (integrated) and `Peak:` from the summary it prints.

Do not add a limiter chasing loudness. The game has its own volume slider, ducks the music on every
goal, and quiet is the point.

---

## 8. Getting the files into the game

Encode each WAV to Ogg Vorbis and put it in `hexflow/assets/music/`:

```sh
ffmpeg -i menu_base.wav -c:a libvorbis -q:a 4 -ar 44100 \
  hexflow/assets/music/menu_base.ogg
```

If ffmpeg has no `libvorbis`, use the built-in encoder instead:

```sh
ffmpeg -i menu_base.wav -c:a vorbis -strict -2 -q:a 3 -ar 44100 \
  hexflow/assets/music/menu_base.ogg
```

The eighteen filenames the game looks for, exactly:

```
menu_base.ogg       menu_layer.ogg       menu_extra.ogg
chapter_1_base.ogg  chapter_1_layer.ogg  chapter_1_extra.ogg
chapter_2_base.ogg  chapter_2_layer.ogg  chapter_2_extra.ogg
chapter_3_base.ogg  chapter_3_layer.ogg  chapter_3_extra.ogg
chapter_4_base.ogg  chapter_4_layer.ogg  chapter_4_extra.ogg
chapter_5_base.ogg  chapter_5_layer.ogg  chapter_5_extra.ogg
```

Then, from the repository root:

```sh
make import     # Godot picks up the new files
make run        # play it
```

> ⚠️ **Do not run `make music` afterwards.** It recomposes the beds and would overwrite the
> hand-made files with generated ones. If the hand-made music is staying, say so — the tool should be
> changed to refuse to overwrite, and that is a two-line change nobody has made yet.

---

## 9. Checking it in the game

```sh
make run
```

- **Main menu** → the `menu` bed, base only.
- **Play a campaign level** → that chapter's bed. Past roughly the middle of the level the melody
  fades in over 1.5 s; undo back down and it fades out.
- **Endless** → the menu bed; the third stem enters at 5 goals and stays.
- Reaching a goal ducks the music by 6 dB for 600 ms. That is the game's doing, not the file's.

If the layer never arrives, the most likely cause is a filename typo — the game falls back to the
base and carries on silently rather than failing.

---

## 10. Definition of done

- [ ] 18 `.ogg` files in `hexflow/assets/music/`, named exactly as in §8
- [ ] Each piece's three stems are **the same length to the sample**
- [ ] Each loops with no audible click (listen across the join twice)
- [ ] `base + layer` measures about −16 LUFS, peaks under −1 dBTP
- [ ] `make run` plays them, and the layer arrives mid-level
- [ ] The `.mid` sources you worked from are kept, so the next revision does not start over

---

## 11. If something is unclear

The generated music is still in git history, so nothing here is destructive — `git checkout
hexflow/assets/music` restores the placeholder beds at any point.

The score that produced the MIDI is the table at the top of `hexflow/tools/make_music.gd`: six rows of
key, tempo and chords. If the *notes* are the problem rather than the sound, that table is the thing
to change, and re-running `make music` regenerates both the audio and the MIDI.

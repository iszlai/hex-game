# Asset requirements

Everything a person outside this repository would have to **provide** or **configure** before Hexflow
is finished, with what exists today standing in its place.

This list is derived from the spec, not from taste: each row names the section that requires it. If a
row disagrees with [`HEXFLOW-SPEC.md`](../../HEXFLOW-SPEC.md), the spec is right and this file is
stale. Progress lives in [`TODO.md`](../../TODO.md), not here.

## Check it, and fill it in

```sh
make assets-ui     the desk in a browser — every slot, with previews; drop files onto them
make assets        the same thing as a table, for a terminal
make assets ROLE=glyphs    one group, file by file: what each is for and what to make
make assets-add FILE=~/Downloads/x.png AS=chapter_3
```

`make assets-ui` is the one to use when the question is "which chapter does this
painting belong to" — it shows them. It has five desks, because it is five
different questions:

| Desk | Answers |
|---|---|
| **Art** | which painting is which chapter, and is it big enough |
| **Glyphs** | which of §11.4's 52 files is which button, one tile per file |
| **Sound** | what each of §15.2's sixteen is *for*, playable, with the brief beside it |
| **Type** | what the three faces look like, rendered in the file actually on disk at §13.4's role sizes |
| **Colour** | every palette token, edited in place, measured live against §21's floors |

The terminal version is better when the question is "what is still missing".

Both read `tools/asset_manifest.json`, which is this document in the form a machine can check — it names every
role, whether the file is there, its real dimensions and what is still wanted.
`assets-add` puts a file where the game looks for it and **copies rather than
moves**, so the original stays in your Downloads folder.

Where a breakdown already exists inside the project, both tools **read** it rather
than restate it: the glyph list comes from `src/data/input_glyphs.json`, the colour
tokens from `src/view/palette.gd`, and the palette checks from the test that
enforces them. What is left over — the sixteen sound briefs, the three type roles —
is held against the game's own tables by `tests/unit/test_asset_manifest.gd`, so a
brief for a file nothing loads fails the build rather than wasting your afternoon.

Prose goes stale silently; the command cannot. Where the two disagree, run the
command.

## How to read the status column

| | Meaning |
|---|---|
| **Placeholder** | Something is on screen and the game is complete without you. Replacing it is an improvement, not a repair. Drop the file in and nothing else changes |
| **Missing** | Nothing exists. The feature is not finished until it arrives |
| **Config** | No file to make — a decision, an account, or a value to set |

---

## The one rule that governs every image

**The tint is a multiplier, so what you paint is what the default palette shows.**

Every image is multiplied by a palette token at runtime (§13.2). The default palette's
`backdrop_tint` is white, so a *painted* backdrop appears exactly as delivered — paint it in colour.
The accessibility palettes then use that token to pull it down: high contrast tints it grey and
raises the scrim, which is the correct behaviour, because a player on that palette wants the
backdrop out of the way rather than faithfully reproduced.

**The panel and board textures are the exception and must stay neutral.** Those are *surfaces*, and
their colour is the palette's job — a timber frame that arrived already brown would be brown in all
five palettes, which is the thing §13.2 exists to prevent. Paint value, contrast and grain there; the
hue comes from the token.

Rule of thumb: **a picture carries its own colour; a material does not.**

### Nine-slice panels — the two rules a drawing has to obey

A panel is *stretched* to whatever it has to hold, and 24 px is sliced off each side.
That constrains the art in a way no image generator manages unprompted:

- **The drawn border has to land on the slice line.** A frame whose timber is a tenth
  of its width gets cut through the middle of the wood. `make panels-cut` measures the
  border and sizes the output so the two agree — which is why `panel_frame.png` is
  192×192 and `panel_fill.png` is 96×96 rather than both being one size.
- **The strips between the corners may not vary along their length.** They stretch, so
  a knot in the top rail is drawn as a smear across the whole rail. The cutter
  *collapses* each strip along the direction it stretches, keeping the bevel's
  cross-section and discarding the rest.

The four corners are the only part kept as drawn, because they are the only part never
stretched. Ask for ornament there and nowhere else.

### The board material — why mid-grey is the whole brief

`tile_grain.png` is not a picture. The shader reads its red channel, doubles it and
*multiplies* the tile's colour by the result, so **128 grey means "leave this tile
alone"**. An image that averages brighter lightens every tile on the board; darker
darkens them. The sheet this was written for came back at 149 — a 17% lightening
applied everywhere, fighting the palette in all six variants.

`make grain-cut` re-centres it on 128, holds the swing inside ±32, removes the
generator's signature from the bright tail, and cross-fades the borders into their
mirrors so it wraps. Ask for **an even all-over field** with no composition: one tile
samples about 90% of the texture, so anything large enough to be a feature appears on
every tile at once.

The second rule: **filenames are the contract.** Nothing in the code names an image except
[`src/view/art.gd`](../src/view/art.gd). Match the names below and no script changes.

---

## 1. Images

All under `hexflow/assets/art/`. PNG, sRGB. Godot imports them automatically; commit the `.import`
files it writes beside them.

| Asset | File | Size | Count | Tinted by | Status | What exists now |
|---|---|---|---|---|---|---|
| Chapter backdrops | `menu.png`, `chapter_1…5.png` | 1920×1200 preferred | 6 | `backdrop_tint` | **Provided** | Painted illustrations, 1312×816. `make art` will never overwrite a backdrop that exists |
| Panel frame | `panel_frame.png` | 9-slice inset **24 px**; size follows the drawn border | 1 | `surface_frame` | **Provided** | Carved timber with scrolled corners, 192×192. Cut by `make panels-cut` |
| Panel fill | `panel_fill.png` | 9-slice inset **24 px** | 1 | `surface_panel` | **Provided** | Quiet reading surface, 96×96 |
| Board material | `tile_grain.png` | 256×256, **seamlessly tiling**, mid-grey average | 1 | not tinted — a *value* map | **Provided** | Halftone-screened stone, cut by `make grain-cut`. Sampled **per tile**, turned by a hash of the tile's own position, so every slab is its own piece of stone. Off entirely under §21's flat-board setting |
| Controller glyphs | `assets/glyphs/<family>_<slot>.png` | 48×48 | **52** (13 slots × 4 families) | `text_primary` | **Placeholder** | Drawn by `make glyphs`: the outline a thumb looks for, plus 1–4 letters taken from `src/data/input_glyphs.json`. **Nothing loads them yet** — the HUD still shows the text label |
| Brand mark | `logo.png` | 512×512 raster preferred | 1 | — | **Provided** | A painted title card, 1024×1024. A vector `logo.svg` is still worth having for the store page |
| App icon | `assets/icons/icon.png` | Square, ≥512 | 1 | — | **Provided** | Derived, not drawn: the whole logo less an 8% margin, at 512. `make icon` re-cuts it — replace `logo.png`, re-run, commit. Deliberately *not* a crop of the picture: the name is the part that makes a window findable in a taskbar |

### Backdrops — the detail that matters

- **1920×1200 is what to aim for.** The game runs at 1280×800 on a Deck and crops to fill anything
  wider. The six provided are 1312×816 — enough to cover the reference resolution with a little to
  spare, and they get scaled up on a larger window. Not a problem today; worth more pixels next time.
- Keep the **top-left quadrant and the right 400 px quiet**. The menu's title block sits in one and
  §12.3's rail sits over the other. A busy area behind either is dimmed by the scrim anyway, so the
  detail is simply lost.
- The board floats over the centre-left of the level screen. A horizon roughly 60% down reads well
  behind it; that is where the generated ones put theirs.
- A **4.5:1 contrast floor** applies to any text over the backdrop (§13.7). It is held by a scrim of
  known opacity laid over the picture, so you do not have to hit it yourself — but the darker and
  calmer the backdrop, the less scrim is needed and the more of your painting survives.
- The backdrop **carries no information**. A player who cannot see it loses nothing. It must not be
  the only thing saying which chapter this is (§13.7).

### Controller glyphs — the 52

Four families — `deck`, `playstation`, `nintendo`, `xbox` — and thirteen slots each:
`a`, `b`, `x`, `y`, `l1`, `l2`, `r1`, `r2`, `start`, `select`, `stick`, `rstick`, `dpad`.

§11.4 forbids hardcoding Xbox glyphs: the Deck calls Select and Start **View** and **Menu**, a
DualSense has no A button. That is also why the placeholder set is *generated from the atlas* rather
than drawn by hand — a glyph cannot end up disagreeing with the label it replaces.

`make glyphs` renders all 52 and **never overwrites a file that exists**, so a licensed pack replaces
them by landing in the folder, one file or all of them. `make glyphs FRESH=1` re-renders over the top
when you actually mean to. Run `make assets ROLE=glyphs` for the file-by-file list, or drop them onto
the tiles in `make assets-ui`.

What is drawn is legible before it is pretty: a circle for a face button, a bumper for a shoulder, a
pill for View/Menu, four arrows for the D-pad, and PlayStation's ✕○□△ and the Switch's −/+ as the
shapes those buttons actually are. White on transparent, because `text_primary` colours them.

Licensing differs per platform holder — check before shipping any pack, including this one.

---

## 2. Colour

No files. A palette is a Godot resource of **29 tokens**; the list of tokens is fixed by
[`src/view/palette.gd`](../src/view/palette.gd) and may not shrink.

Because there is nothing to deliver, the Colour desk in `make assets-ui` **edits them in place**:
pick a palette, pick a token, and the value is written straight into the `.tres`. It shows the same
pairs the test below measures — simulating the deficiency each palette is for — so a change that
breaks a floor says so before `make test` does. Only the test is the gate; the desk is the fast
answer.

| Palette | File | Status | Notes |
|---|---|---|---|
| Default (warm) | `cairn_warm.tres` | **Placeholder** | Authored for C-26. Warm timber, dusk, honey goal, pale-cyan path |
| Neon dark | `neon_dark.tres` | Done | The original direction, kept as an alternate |
| Deuteranopia-safe | `deuter.tres` | **Placeholder** | §21 |
| Protanopia-safe | `protan.tres` | **Placeholder** | §21 |
| Tritanopia-safe | `tritan.tres` | **Placeholder** | §21 |
| High contrast | `high_contrast.tres` | **Placeholder** | §21 |

**What a palette has to get right.** These pairs must be distinguishable *in the palette you are
authoring*, because they are the pairs the game asks a player to tell apart:

- `path_core` vs `goal_cell` vs `wild` — the three things that glow
- `portal` vs `gate` — two modifiers that sit next to each other in chapter 4
- `wall_fill` vs `cell_empty_fill` — a wall and an empty cell were within 1% luminance once, and only
  a hatch pattern saved them
- `text_primary` and `text_secondary` against `surface_panel`, at 4.5:1
- `focus` against everything it can be drawn on

Colour is never the *only* channel (§21, C5) — every state also has a glyph, a shape, and on the board
a height — so a palette that is hard to read is a bug, not a failure of the design.

`tests/unit/test_palette.gd` fails a palette that forgets a token or tints the art the same as another
one. `tests/unit/test_palette_vision.gd` goes further: it **simulates** the deficiency each palette is
for (Viénot's linear dichromacy approximation) and measures the pairs above *afterwards*, against
WCAG 1.4.11's 3:1 non-text floor and §13.7's 4.5:1 for text. "Deuteranopia-safe" is a claim an author
cannot check by looking — the whole point is that they see something the player will not — so it is
checked by machine instead.

All six palettes exist and pass. The four alternates are **placeholders in the same sense as the
art**: correct by measurement, not reviewed by anyone who needs them. A player with the condition
looking at a real board is still the test that matters.

---

## 3. Audio

### Sound effects — under `hexflow/assets/sfx/`, mono WAV

**16 files, all Placeholder.** Synthesised by `make sfx` from a table of a few numbers each (§15.2).
328 KB total. Replace any one file and no code changes; the table is in `tools/make_sfx.gd`.

`ui_move` · `ui_confirm` · `ui_back` · `ui_reject` · `place_note` · `place_connector` ·
`tile_advance` · `tile_discard` · `tile_autoskip` · `goal_reach` · `level_win` · `level_dead` ·
`star_award` · `wild_pickup` · `portal_link` · `gate_open`

> `place_note` is **one sample, pitched** — the game plays it up a major pentatonic scale as the path
> grows and back down on undo, capped at three octaves. Supply a single clean tone, not sixteen notes.

### Music — **Placeholder**, composed in the repository (§15.1, C-6 and C-40)

| | Requirement | What ships |
|---|---|---|
| Tracks | 6 — one per chapter, plus a menu track | 6, composed by `tools/make_music.gd` |
| Stems per track | 2 — `base` (always) and `layer` (fades in above 40% board fill, out below 30%, 1.5 s cross-fade) | 3 |
| Extra | Endless takes a **third** stem, entering every 5 goals | shipped for every bed |
| Files | **13+** loops | 18 |
| Length | 2–3 minutes, **seamlessly looping** | 2:03–2:14, seam measured |
| Tempo | 70–85 BPM | 72–84, rising across the campaign |
| Instrumentation | Warm pads, soft plucks. **No percussion in campaign** | lo-fi jazz: Rhodes + upright + tape noise, melody on the layer. No drums (C-42) |
| Behaviour | Ducks −6 dB for 600 ms on the goal-reached sequence | done |
| Loudness | −16 LUFS integrated, −1 dBTP (§15.3) | −16.6 LUFS on `base + layer`, peaks under −2 dBFS |

**If you replace it, replace it as one session exported three times.** That is the whole brief. The
stems are played *together*, so three separate renders — however good each one is — will phase against
each other and cannot be used. This is why the beds are composed here rather than sourced: a music
generator will give you another variation and cannot give you the same take with the pads muted.

`make music` recomposes everything; `make music TRACK=chapter_3` does one, in about 50 seconds. The
score is at the top of `tools/make_music.gd` — six rows of key, tempo, chords and colour, which is
also the thing to hand a composer.

#### Editing it by hand

Every render also writes `drafts/music/<track>.mid` — the same notes the game is playing, as a
Standard MIDI File, one track per part, named after the stem it belongs to. That is the file to open
when the answer is "play it properly" rather than "change a number".

| Tool | Cost | Use it when |
|---|---|---|
| **GarageBand** | free, already on a Mac | You want to *hear* it with real instruments. Drop the `.mid` in, put a Rhodes on the piano track and an upright on the bass, and it is a different thing immediately |
| **Reaper** | $60, unlimited evaluation | You want to keep working on it. Best per-track export in the business, which is exactly what this needs |
| **Logic / Ableton / FL** | — | Any of them is fine. Nothing here is special |
| **MuseScore** | free | You would rather read and write it as notation than as a piano roll |
| **Audacity / ocenaudio** | free | You only want to top-and-tail or EQ the finished `.ogg` files. Not for arranging — it has no idea what a track is |

**However you edit it, export it as one session, three times**, muting as you go:

| File | Mute | Contains |
|---|---|---|
| `<track>_base.ogg` | `layer`, `extra` | The piano and the bass — always playing |
| `<track>_layer.ogg` | `base`, `extra` | The melody — fades in as a level fills |
| `<track>_extra.ogg` | `base`, `layer` | The counter-line — endless only, from five goals |

Three separate *renders* will not do, however good each one sounds: the stems are played on top of
each other and two renders of the same piece drift apart (C-40). One project, three exports, same
length, same tempo.

Then encode and drop them in:

```sh
ffmpeg -i base.wav -c:a vorbis -strict -2 -q:a 3 hexflow/assets/music/chapter_1_base.ogg
```

A commission or a licensed library is still the ceiling (C-6), and a written commercial licence would
have to end up in the repository.

---

## 4. Type — done, one item outstanding

Four fonts are vendored under `hexflow/assets/fonts/`, three SIL OFL and one Font Monkey, all with their licences:
**Belligerent Madness** (display), **Caveat** (headings), **Inter** (body, captions), **JetBrains Mono**
(numerals, tabular). C-30 changed the first two: §13.4's original Space Grotesk belonged to the
minimalist direction C-26 replaced, and the game had become carved timber and painted stone with an
interface lettered like a dashboard.

**Character goes where it is seen; legibility keeps what is read.** Display and headings are
characterful. Body and captions are not, and that is the constraint rather than an oversight — the
18 px floor exists because the Deck's screen is seven inches, and a handwritten face at 18 px fails
the audit the floor is there to pass.

A characterful face carries almost no symbols, so **the families fall back to one another**: a glyph
missing from one is drawn by another rather than as an empty box. That had already bitten before it
was noticed — Space Grotesk has no ★, so the results card drew three empty boxes and nothing failed.
`tests/unit/test_typography.gd` scans the source for drawn characters and holds every role to being
able to render each one; a character *no* face has fails there, because a fallback cannot invent one.

If you replace a family it must be SIL OFL or equivalent, must carry a real `wght` axis (Medium and
Bold are a variation, not a second file), and the numeral face must have **tabular figures** or every
counter in the game jitters as it counts.

Outstanding: **subsetting to Latin-Extended** (§13.6). Needs a tool this repo does not vendor. Worth
doing before the store build; nowhere near §20's 250 MB budget today.

## 5. Text

| | Status | Notes |
|---|---|---|
| English strings | **Provided** | Extracted: every player-visible string is a key in `assets/i18n/strings.csv`. The CI check that fails a literal left in a scene is live |
| Translations | **Provided (2 of n)** | English and Hungarian, a column each in `strings.csv`. A third language is one more column and nothing else — keys are namespaced (`menu.campaign`, `hud.moves`, `tutorial.T4`, `binding.board_undo`) |
| Tutorial copy | **Provided** | 11 beats over five teaching boards, **≤12 words each**, diegetic (§10.3). The beats are data, in `src/data/tutorial/beats.json`, and their words are keys in `strings.csv` |
| Store description | **Missing** | Under 300 characters (§25) |

Anything you write must survive **150% text scale without clipping** (§21) and a pseudo-locale that
lengthens every string.

---

## 6. Steam and store — all Config

| | Status | Notes |
|---|---|---|
| Steam app ID + Steamworks account | **Config** | Nothing exists; the game runs fully with Steam absent and always must (§23.1) |
| Achievements | **Config** | Names, descriptions and **64×64 + 32×32 icons** each. `first_flow` and `no_hints_chapter` are referenced in code today |
| Leaderboards | **Config** | `endless_best_goals`, plus one rolling board per daily date |
| Store capsules | **Missing** | 6 sizes per Steamworks spec — confirm current sizes at page setup, they change |
| Screenshots | **Missing** | 1280×800, the Deck's own resolution |
| Trailer | **Missing** | 30–60 s |
| Price | **Config** | €/$6.99 pencilled in (C-4), not decided |
| Name and trademark check | **Config** | "Hexflow" is a working title and has never been checked (C-1) |
| macOS signing identity | **Config** | Codesign + notarisation for the macOS build (§25) |

---

## 7. What you do **not** need to provide

- **The nine UI icons** (undo, cross, star, question, padlock, rings, target, hatch square, hexagon).
  They are vector paths on a 24 grid, drawn in code — crisp at any size and at 150% text scale, and
  deliberately not painted: an icon is read at a glance at 24 px, the one size where illustration
  loses to a clean line (§13.5).
- **The board itself.** Hex prisms, connectors, modifier marks, particles and the level-select map are
  all geometry plus palette tokens. Only the *material* on them is an asset, and only if you want one.
- **Level content.** 60 levels are generated, solver-verified and frozen as committed JSON.

---

## Sizes, so far

Run `make assets` for the live figure; these go stale.

| | Size |
|---|---|
| Art (10 files) | 16.5 MB — six painted backdrops and a 1024² logo, none downsampled yet |
| Music (6 beds) | 2.9 MB |
| Fonts (3 families) | 1.2 MB |
| Controller glyphs (52) | 208 KB |
| Sound effects (16) | 264 KB |
| **Budget** | §20: ≤ 100 MB texture memory, ≤ 250 MB per platform build |

The painted art is now the whole story: 16.5 MB of PNG against a 250 MB build budget is comfortable,
but it is seven files at more than 2 MB each and none has been through a compressor. §20's texture
row was rewritten by C-26 to stop claiming this was free, and it still has not been measured on a
Deck.

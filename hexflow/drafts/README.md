# Drafts

Boards from the map editor that are **not** one of the sixty.

`make edit-maps` → **save as…** writes here by default. Anything in this folder is a level file in
the ordinary format — `LevelFile` writes it and the editor's **open…** reads it back — but nothing
loads it at runtime, `LevelRepository` never looks here, and the export preset excludes the whole
directory.

## What it is for

Two things the sixty slots cannot do:

- **Park an unfinished board.** Saving into a campaign slot refuses on a failed Validate, because
  frozen data must never hold an unsolvable level. A draft has no such rule: it only needs a start,
  so a board can sit here half-drawn for a week. That is the difference between a scratch folder
  and a second campaign.
- **Try a level without spending a slot.** Three versions of chapter 3's opener can live here at
  once and be compared before one of them takes the slot.

## Promoting a draft

Open it, set **chapter** and **level**, Validate, and **save to slot**. It keeps its `uid`, so if it
had ever been played its stars follow it (C-34) — and the slot's old level is overwritten, which is
what the levels list is for checking first.

Drafts are committed rather than ignored: a board worth keeping across a week is worth keeping in
the repository, and they are a couple of kilobytes each.

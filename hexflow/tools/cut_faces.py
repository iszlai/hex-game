#!/usr/bin/env python3
"""Turn a sheet of drawn hex tiles into the board's face atlas.

    python3 tools/cut_faces.py ~/Downloads/tiles.png

`tile_face.png` is the drawn top of a tile: its ink outline, its rim, the
light/shadow split and the halftone screening the shadow, all baked in as
**values**. The shader samples it across the tile's own face, so what the player
sees is a drawing rather than a lit polygon — and because it is a value map, the
palette still supplies the colour, which is how one drawing becomes the brown
walls, the gold goals and the pale path.

Four cells in a 2x2 grid, because a board of sixty tiles all wearing the same
crack reads as a pattern rather than as stone. The shader picks between them by
the tile's own position and turns each one by a multiple of 60 degrees, which a
hexagon is symmetric under — so four drawings cover twenty-four appearances.

What this has to fix, none of which a generator does:

  * **Mid-grey is the identity.** Same rule as the board material: the value
    multiplies the palette's colour, so a sheet averaging brighter lightens every
    tile on the board. Measured over the drawing itself, not the sheet, or the
    grey card behind it drags the average.
  * **The drawing has to fill the cell.** A hexagon drawn small inside its cell
    would land small on the tile, with a ring of card around it.
  * **Grid lines and card are not art.** They are trimmed.

Standard library only.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from cut_marks import read_png, write_png  # noqa: E402

## Cells across and down, and the size of one in the output.
GRID = 2
CELL = 512

## What the shader treats as "no change" — see `cut_grain.py`, same contract.
NEUTRAL = 128

## How far from neutral the face is allowed to swing. Wider than the tiling grain,
## because this one carries the drawing's own light and shade rather than a
## texture, and flattening that is flattening the whole point of it.
SWING = 74

## How far a pixel must sit from the card behind the drawing to count as ink.
CONTENT = 12

## Pixels ignored at each edge of a cell.
##
## The sheet is drawn with a black border and black cross-dividers, ~6 px of solid
## ink each. The drawing's own outline is near-black too, so darkness cannot tell
## them apart — only position can, and this is that. Measured, not guessed: at a
## 2 px inset every cell reported a drawing exactly the size of the cell, which is
## the divider being read as art.
BORDER = 16


def cells_of(width, height, rows):
    """The four quadrants, with the sheet's border and divider lines trimmed."""
    out = []
    half_w, half_h = width // GRID, height // GRID
    for row in range(GRID):
        for col in range(GRID):
            x0, y0 = col * half_w, row * half_h
            out.append((x0, y0, x0 + half_w, y0 + half_h))
    return out


def card_value(rows, box):
    """The flat grey the drawing sits on, taken from the cell's own corner."""
    x0, y0, x1, y1 = box
    samples = []
    for dy in range(BORDER, BORDER + 24):
        for dx in range(BORDER, BORDER + 24):
            samples.append(rows[y0 + dy][(x0 + dx) * 4])
    samples.sort()
    return samples[len(samples) // 2]


def content_box(rows, box, card):
    """The drawing's own extent inside its cell, ignoring card and grid lines."""
    x0, y0, x1, y1 = box
    left, right, top, bottom = x1, x0, y1, y0
    for y in range(y0 + BORDER, y1 - BORDER):
        row = rows[y]
        for x in range(x0 + BORDER, x1 - BORDER):
            v = row[x * 4]
            if abs(v - card) >= CONTENT:
                if x < left:
                    left = x
                if x > right:
                    right = x
                if y < top:
                    top = y
                if y > bottom:
                    bottom = y
    return (left, top, right, bottom)


def face_only(box):
    """The drawing's hexagon, whichever way up it was drawn.

    A regular hexagon is `sqrt(3)/2` in one axis against the other, and which axis
    says how it is oriented: **taller than wide is pointy-top** — a vertex at the
    top and bottom, which is the lattice's own orientation — and wider than tall is
    flat-top, which has to be turned a half-step to fit.

    This is measured rather than assumed because assuming it wrong is not subtle
    and does not look like a rotation error. The first pass here took the sheet for
    flat-top and cropped the bottom `1 - sqrt(3)/2` of every tile as if it were the
    slab's own side — which sliced the bottom vertex clean off four pointy-top
    hexagons and left them with a flat bottom edge, on top of turning each one 30
    degrees out of true.

    Returns the box and whether it needs the half-step.
    """
    left, top, right, bottom = box
    w, h = right - left, bottom - top
    pointy = h >= w
    ideal = w / 0.8660254 if pointy else w * 0.8660254
    # Anything much taller than the hexagon itself is the drawn slab's side, and
    # that is the mesh's job — it has real thickness, real height per kind (C-22)
    # and its own lit chamfer. Trimmed, but only when there is something to trim.
    if h > ideal * 1.06:
        bottom = top + int(ideal)
    return (left, top, right, bottom), pointy


def scale_into(rows, box, size):
    """Box-filter a source rectangle into a size x size block of luminance.

    Fitted along its **long** axis, because that is the one whose extent is the
    hexagon's circumradius — and the circumradius is what the shader's sampling
    box is a square of. Fitting the short axis instead would inflate the drawing
    past the tile it is drawn on.
    """
    x0, y0, x1, y1 = box
    sw, sh = max(1, x1 - x0), max(1, y1 - y0)
    if sh >= sw:
        dst_h, dst_w = size, max(1, int(size * sw / float(sh)))
    else:
        dst_w, dst_h = size, max(1, int(size * sh / float(sw)))
    left = (size - dst_w) // 2
    top = (size - dst_h) // 2

    block = [[NEUTRAL] * size for _ in range(size)]
    for dy in range(dst_h):
        if not (0 <= top + dy < size):
            continue
        sy0 = y0 + dy * sh // dst_h
        sy1 = max(sy0 + 1, y0 + (dy + 1) * sh // dst_h)
        line = block[top + dy]
        for dx in range(dst_w):
            sx0 = x0 + dx * sw // dst_w
            sx1 = max(sx0 + 1, x0 + (dx + 1) * sw // dst_w)
            total = n = 0
            for sy in range(sy0, sy1):
                row = rows[sy]
                for sx in range(sx0, sx1):
                    total += row[sx * 4]
                    n += 1
            line[left + dx] = total // max(n, 1)
    return block


def recentre(block, card):
    """Put the drawing's average on neutral and hold its swing.

    Measured over the drawing rather than the whole block: the card behind it is
    not art, and letting it into the average would pull every tile toward the
    colour of a background that is never drawn.
    """
    ink = [v for line in block for v in line if abs(v - card) >= CONTENT]
    if not ink:
        return block
    mean = sum(ink) / len(ink)
    ink.sort()
    low, high = ink[len(ink) // 100], ink[99 * len(ink) // 100]
    reach = max(1.0, (high - low) / 2.0)
    scale = min(1.0, SWING / reach)
    for line in block:
        for i, v in enumerate(line):
            line[i] = max(0, min(255, int(NEUTRAL + (v - mean) * scale)))
    return mean, scale


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: python3 tools/cut_faces.py <sheet.png> [out.png]")
    source = os.path.expanduser(sys.argv[1])
    target = sys.argv[2] if len(sys.argv) > 2 else "assets/art/tile_face.png"

    width, height, rows = read_png(source)
    print("read %d×%d" % (width, height))

    size = CELL * GRID
    atlas = [bytearray(size * 4) for _ in range(size)]
    for i, box in enumerate(cells_of(width, height, rows)):
        card = card_value(rows, box)
        content, pointy = face_only(content_box(rows, box, card))
        block = scale_into(rows, content, CELL)
        mean, scale = recentre(block, card)
        cw = content[2] - content[0]
        ch = content[3] - content[1]
        print("  cell %d  %s hexagon %d×%d, mean %.0f → %d, swing ×%.2f"
              % (i, "pointy-top" if pointy else "flat-top", cw, ch, mean, NEUTRAL, scale))

        ox, oy = (i % GRID) * CELL, (i // GRID) * CELL
        for y in range(CELL):
            line = atlas[oy + y]
            for x in range(CELL):
                v = block[y][x]
                o = (ox + x) * 4
                line[o] = line[o + 1] = line[o + 2] = v
                line[o + 3] = 255

    write_png(target, size, size, atlas)
    print("wrote %s — %d×%d, %d cells of %d" % (target, size, size, GRID * GRID, CELL))


if __name__ == "__main__":
    main()

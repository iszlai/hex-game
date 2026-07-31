#!/usr/bin/env python3
"""Turn a sheet of drawn icons into C-29's modifier atlas.

An image generator hands back one wide picture: four icons in a row, on white,
at whatever size and spacing it felt like. The game wants `assets/art/marks.png`
— four 256x256 cells, evenly cut, transparent outside the ink. This does that
conversion, and does it repeatably, because the sheet gets regenerated every time
the art is not quite right and hand-cutting it four times is how a cell ends up
two pixels off.

    python3 tools/cut_marks.py ~/Downloads/sheet.png

What it does, and the reasoning where it is not obvious:

  * **Background by flood fill, not by keying white.** Keying every white pixel
    punches holes through the middle of anything with a highlight in it — the
    portal's swirl is mostly white — so what is removed is the white *connected
    to the border*, which is the background by definition.
  * **Icons found by their own gaps.** The columns that contain ink are grouped;
    a run of empty columns is a cell boundary. Even quarters would be wrong,
    because a generator does not space things evenly and one icon here trails a
    smear well past its own body.
  * **Each icon scaled on its own** to fill its cell to the same margin, so four
    drawings at four sizes come out as one set. It is the thing an atlas most
    needs and the thing a generator is least able to do.

The one thing it cannot do is guess. White *enclosed* by ink — the middle of a
reticle, the opening under a padlock's shackle — is not connected to the border
and is therefore not background by the rule above, so it stays white. That is the
correct reading of an ambiguous picture: a white centre may well be painted. If
those holes matter, the fix is upstream, not here — ask the generator for a sheet
with a real alpha channel, which this then keeps untouched.

Standard library only, like the asset desk beside it: no pip, no build step.
"""

import struct
import sys
import zlib

CELLS = ["goal", "portal", "gate", "wild"]
CELL = 256

## Fraction of a cell left empty around an icon. The marks are drawn on tiles and
## a mark that reached its own cell edge would touch the next tile.
MARGIN = 0.06

## How close to white counts as background, and how much alpha an ink pixel needs
## before it is allowed to widen an icon's bounding box. The second one matters:
## this sheet's portal trails a pale smear a long way left of its body, and a box
## drawn around the smear would scale the portal down to fit a cell it never
## actually filled.
## How far a pixel may sit from a learned background colour and still be background,
## and how coarsely colours are bucketed while learning them. Both are sized for
## compression noise on a flat fill, which is a few levels either way.
BACKGROUND_TOLERANCE = 16
BUCKET = 8
INK_FOR_BOUNDS = 40


# --- PNG ------------------------------------------------------------------------

def read_png(path):
    """Decode to (width, height, rows of RGBA bytes). Enough PNG for this job."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("%s is not a PNG" % path)

    idat, width, height, depth, colour, interlace = b"", 0, 0, 0, 0, 0
    i = 8
    while i < len(data):
        length = struct.unpack(">I", data[i:i + 4])[0]
        kind = data[i + 4:i + 8]
        body = data[i + 8:i + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        i += 12 + length

    if depth != 8 or interlace != 0 or colour not in (2, 6):
        raise SystemExit(
            "need an 8-bit non-interlaced RGB or RGBA PNG; this is depth %d, type %d"
            % (depth, colour))

    channels = 4 if colour == 6 else 3
    raw = zlib.decompress(idat)
    stride = width * channels
    rows, previous, pos = [], bytearray(stride), 0
    for _ in range(height):
        filt = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        _unfilter(line, previous, filt, channels)
        previous = line
        if channels == 4:
            rows.append(bytearray(line))
        else:
            out = bytearray(width * 4)
            for x in range(width):
                out[x * 4:x * 4 + 3] = line[x * 3:x * 3 + 3]
                out[x * 4 + 3] = 255
            rows.append(out)
    return width, height, rows


def _unfilter(line, previous, filt, channels):
    if filt == 0:
        return
    for x in range(len(line)):
        a = line[x - channels] if x >= channels else 0
        b = previous[x]
        c = previous[x - channels] if x >= channels else 0
        if filt == 1:
            line[x] = (line[x] + a) & 255
        elif filt == 2:
            line[x] = (line[x] + b) & 255
        elif filt == 3:
            line[x] = (line[x] + (a + b) // 2) & 255
        elif filt == 4:
            p = a + b - c
            pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            pick = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
            line[x] = (line[x] + pick) & 255


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(kind, body):
        block = kind + body
        return struct.pack(">I", len(body)) + block + struct.pack(">I", zlib.crc32(block))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


# --- the work -------------------------------------------------------------------

def already_cut_out(width, height, rows):
    """Whether the sheet arrived with a real alpha channel rather than a background.

    Judged at the **corners**, not over the whole image: a drawing can legitimately
    contain soft edges everywhere, but if the four corners are transparent then
    something has already separated the art from its background and this tool
    should keep its hands off. A checkerboard *drawn into* the pixels — which is
    what a screenshot of a transparency preview looks like — is opaque there, and
    correctly falls through to the flood fill.
    """
    probe = 8
    for y in (0, height - 1):
        for x in (0, width - 1):
            for dy in range(probe):
                for dx in range(probe):
                    px = min(max(x + (dx if x == 0 else -dx), 0), width - 1)
                    py = min(max(y + (dy if y == 0 else -dy), 0), height - 1)
                    if rows[py][px * 4 + 3] > 8:
                        return False
    return True


def background_colours(width, height, rows):
    """The one or two flat colours the art is sitting on, learned from the border.

    A generator asked for transparency will often hand back a *picture of*
    transparency — the grey checkerboard its own preview draws, flattened into the
    pixels. That is two colours in a regular grid rather than one, so the background
    cannot be assumed to be white, and it cannot be assumed to be a single value
    either. Both are read off the border, where the art is not.
    """
    # Tallied in coarse buckets, not by exact value. A generated sheet is
    # compressed, so its flat background is not one number — this one's two greys
    # arrive spread over #9b9b9b…#9f9f9f and #bdbdbd…#c0c0c0. Counting exact
    # colours splits each background across half a dozen entries, none of which
    # then looks common enough to *be* the background, and the fill clears almost
    # nothing.
    tally = {}
    samples = 0
    def note(x, y):
        nonlocal samples
        p = rows[y][x * 4:x * 4 + 3]
        key = (p[0] // BUCKET, p[1] // BUCKET, p[2] // BUCKET)
        tally[key] = tally.get(key, 0) + 1
        samples += 1

    for x in range(0, width, 3):
        for y in (0, 1, height - 2, height - 1):
            note(x, y)
    for y in range(0, height, 3):
        for x in (0, 1, width - 2, width - 1):
            note(x, y)

    ranked = sorted(tally.items(), key=lambda kv: -kv[1])
    picked, covered = [], 0
    for bucket, count in ranked[:4]:
        # Keep taking colours until the border is accounted for. A checkerboard
        # needs two; a plain white sheet needs one; a stray pixel of art touching
        # the edge needs none of them and never gets that far.
        if covered >= samples * 0.9:
            break
        if count * 8 < samples:
            break
        picked.append(tuple(v * BUCKET + BUCKET // 2 for v in bucket))
        covered += count
    return picked or [(255, 255, 255)]


def is_checkerboard(palette):
    """Whether the learned background is a transparency *preview* rather than a fill.

    Two or more flat neutral greys is not something art is laid on; it is the
    checkerboard an image tool draws behind nothing. The distinction earns its keep
    below — it is what says whether background enclosed by ink may be removed.
    """
    if len(palette) < 2:
        return False
    for c in palette:
        if max(c) - min(c) > 6:
            return False
    return True


def drop_background(width, height, rows):
    """Clear the background, and grade the pixels that are partly it.

    Two modes, and which applies is not a preference — it is what the picture can be
    *known* to mean.

      * A **checkerboard** is removed everywhere, enclosed or not. Nothing is drawn
        on a checkerboard, so grey inside a portal's centre or under a padlock's
        shackle is the preview showing through and never paint.
      * A **flat colour** is removed only where it connects to the border. White in
        the middle of a reticle may well be painted, and this cannot tell; so it
        keeps it, and the module docstring says so.

    Either way the edge is graded rather than cut: a pixel sitting between the art
    and the background — the outside of a soft glow — gets partial alpha in
    proportion to how far it has travelled from the background colour. Without that,
    the glows come away with a rind of half-erased checkerboard around them.

    Eight-connected, in the flood-fill case. On a checkerboard the squares of one
    colour meet only at their corners, so a four-connected fill cannot leave the
    square it starts in.
    """
    palette = background_colours(width, height, rows)
    checker = is_checkerboard(palette)
    print("  background: %s%s" % (", ".join("#%02x%02x%02x" % c for c in palette),
                                  " (a transparency checkerboard)" if checker else ""))

    def distance(x, y):
        p = rows[y][x * 4:x * 4 + 3]
        best = 255
        for c in palette:
            best = min(best, max(abs(p[0] - c[0]), abs(p[1] - c[1]), abs(p[2] - c[2])))
        return best

    keep = None
    if not checker:
        keep = bytearray(b"\x01" * (width * height))
        stack = []
        for x in range(width):
            stack.extend([(x, 0), (x, height - 1)])
        for y in range(height):
            stack.extend([(0, y), (width - 1, y)])
        while stack:
            x, y = stack.pop()
            if x < 0 or y < 0 or x >= width or y >= height:
                continue
            if keep[y * width + x] == 0 or distance(x, y) > BACKGROUND_TOLERANCE * 2:
                continue
            keep[y * width + x] = 0
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1),
                           (1, 1), (1, -1), (-1, 1), (-1, -1)):
                stack.append((x + dx, y + dy))

    cleared = 0
    for y in range(height):
        row = rows[y]
        base = y * width
        for x in range(width):
            if keep is not None and keep[base + x]:
                continue
            d = distance(x, y)
            if d <= BACKGROUND_TOLERANCE:
                row[x * 4 + 3] = 0
                cleared += 1
            elif d < BACKGROUND_TOLERANCE * 3:
                # Part background, part art: the outside of a glow. Faded rather
                # than chosen between, or every soft edge keeps a rind of preview.
                span = BACKGROUND_TOLERANCE * 2
                row[x * 4 + 3] = min(row[x * 4 + 3],
                                     int(255 * (d - BACKGROUND_TOLERANCE) / span))
    print("  cleared %d%% of the sheet" % (cleared * 100 // (width * height)))
    return rows


def soften(width, height, rows):
    """One pass of blur on **alpha only**.

    The flood fill leaves a hard, aliased boundary. Smoothing the colour as well
    would drag white in from the background and leave every icon with a pale halo,
    so the ink keeps its own colour and only the coverage is feathered.
    """
    alpha = [bytes(rows[y][3::4]) for y in range(height)]
    for y in range(height):
        row = rows[y]
        up = alpha[max(y - 1, 0)]
        down = alpha[min(y + 1, height - 1)]
        here = alpha[y]
        for x in range(width):
            left = here[max(x - 1, 0)]
            right = here[min(x + 1, width - 1)]
            row[x * 4 + 3] = (here[x] * 4 + left + right + up[x] + down[x]) // 8
    return rows


def column_mass(width, height, rows):
    """How much ink stands in each column."""
    mass = []
    for x in range(width):
        n = 0
        for y in range(height):
            if rows[y][x * 4 + 3] >= INK_FOR_BOUNDS:
                n += 1
        mass.append(n)
    return mass


def _spans(mass, floor, min_width):
    out, start = [], None
    for x, m in enumerate(list(mass) + [0]):
        if m >= floor and start is None:
            start = x
        elif m < floor and start is not None:
            if x - start >= min_width:
                out.append((start, x - 1))
            start = None
    return out


def find_icons(width, height, rows):
    """Bounding boxes, left to right.

    The split point is found by **raising a floor until the right number of groups
    appears**, rather than by cutting the sheet into even quarters or by looking for
    empty columns. Neither of those works on a real sheet: a generator does not
    space its icons evenly, and this one's portal trails a pale smear far enough
    left to touch the goal, so at any floor low enough to keep faint ink the two are
    one group.

    The floor decides *where the boundaries are* and nothing else. Each icon's own
    box is then measured inside its region at the low threshold, so raising the
    floor never crops the thing it was only meant to separate.
    """
    mass = column_mass(width, height, rows)
    min_width = width // 50

    groups = []
    for floor in range(1, max(mass) + 1):
        found = _spans(mass, floor, min_width)
        if len(found) == len(CELLS):
            groups = found
            print("  split at a floor of %d px of ink per column" % floor)
            break
    if not groups:
        print("  column ink, sampled every %d px:" % max(1, width // 40))
        print("  " + " ".join(str(mass[x]) for x in range(0, width, max(1, width // 40))))
        return _spans(mass, 1, min_width)

    # Boundaries at the middle of each gap, so a smear stays with whichever icon it
    # belongs to rather than being cut off at the group edge.
    edges = [0]
    for i in range(len(groups) - 1):
        edges.append((groups[i][1] + groups[i + 1][0]) // 2)
    edges.append(width - 1)

    boxes = []
    for i in range(len(CELLS)):
        left, right = edges[i], edges[i + 1]
        x0, x1, y0, y1 = right, left, height, -1
        for y in range(height):
            row = rows[y]
            for x in range(left, right + 1):
                if row[x * 4 + 3] >= INK_FOR_BOUNDS:
                    x0, x1 = min(x0, x), max(x1, x)
                    y0, y1 = min(y0, y), max(y1, y)
        boxes.append((x0, y0, x1, y1))
    return boxes


def scale_into_cell(rows, box):
    """Box-filter the crop down into one cell, centred, keeping its aspect ratio."""
    x0, y0, x1, y1 = box
    src_w, src_h = x1 - x0 + 1, y1 - y0 + 1
    room = int(CELL * (1.0 - MARGIN * 2.0))
    scale = min(room / float(src_w), room / float(src_h))
    dst_w, dst_h = max(1, int(src_w * scale)), max(1, int(src_h * scale))
    off_x, off_y = (CELL - dst_w) // 2, (CELL - dst_h) // 2

    cell = [bytearray(CELL * 4) for _ in range(CELL)]
    for dy in range(dst_h):
        sy0 = y0 + int(dy * src_h / dst_h)
        sy1 = max(sy0 + 1, y0 + int((dy + 1) * src_h / dst_h))
        for dx in range(dst_w):
            sx0 = x0 + int(dx * src_w / dst_w)
            sx1 = max(sx0 + 1, x0 + int((dx + 1) * src_w / dst_w))
            r = g = b = a = n = 0
            for sy in range(sy0, sy1):
                row = rows[sy]
                for sx in range(sx0, sx1):
                    p = row[sx * 4:sx * 4 + 4]
                    # Premultiplied while averaging, or a transparent white pixel
                    # drags the edge of the ink toward white.
                    r += p[0] * p[3]
                    g += p[1] * p[3]
                    b += p[2] * p[3]
                    a += p[3]
                    n += 1
            if n == 0 or a == 0:
                continue
            o = (off_x + dx) * 4
            cell[off_y + dy][o] = min(255, r // a)
            cell[off_y + dy][o + 1] = min(255, g // a)
            cell[off_y + dy][o + 2] = min(255, b // a)
            cell[off_y + dy][o + 3] = min(255, a // n)
    return cell


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: python3 tools/cut_marks.py <sheet.png> [out.png]")
    source = sys.argv[1].replace("~", __import__("os").path.expanduser("~"))
    target = sys.argv[2] if len(sys.argv) > 2 else "assets/art/marks.png"

    width, height, rows = read_png(source)
    print("read %d×%d" % (width, height))
    if already_cut_out(width, height, rows):
        # A sheet that arrives with real alpha has had this done properly by
        # whatever drew it. Flood-filling it again would find no white to remove and
        # softening it again would eat a pixel off every edge for nothing.
        print("  already transparent — keeping the alpha it came with")
    else:
        rows = drop_background(width, height, rows)
        rows = soften(width, height, rows)

    boxes = find_icons(width, height, rows)
    print("found %d icons" % len(boxes))
    if len(boxes) != len(CELLS):
        for i, box in enumerate(boxes):
            print("  %d  %s" % (i, box))
        raise SystemExit(
            "expected %d icons in a row (%s). Re-generate the sheet, or crop it so "
            "there is clear background between each one."
            % (len(CELLS), ", ".join(CELLS)))

    atlas = [bytearray(CELL * len(CELLS) * 4) for _ in range(CELL)]
    for i, box in enumerate(boxes):
        cell = scale_into_cell(rows, box)
        print("  %-7s from x %d…%d, y %d…%d" % (CELLS[i], box[0], box[2], box[1], box[3]))
        for y in range(CELL):
            atlas[y][i * CELL * 4:(i + 1) * CELL * 4] = cell[y]

    write_png(target, CELL * len(CELLS), CELL, atlas)
    print("wrote %s — %d×%d, %s in that order"
          % (target, CELL * len(CELLS), CELL, ", ".join(CELLS)))
    print("run `make import`, then look at it with `make assets ROLE=marks`")


if __name__ == "__main__":
    main()

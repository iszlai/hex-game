#!/usr/bin/env python3
"""Turn a drawn panel into a nine-slice texture the UI can stretch.

    python3 tools/cut_panel.py ~/Downloads/frame.png assets/art/panel_frame.png

A nine-slice is stretched, and that puts two demands on the art that no image
generator meets on its own:

  * **The drawn border has to land exactly on the slice line.** `Surface` slices
    24 px off every side, so a texture whose timber is a tenth of its width gets
    cut through the middle of the wood. The band is measured here and the output
    is sized so the two agree — a band at an eighth of the side becomes a 192 px
    texture, and the code's 24 px margin then falls precisely where the wood ends.
  * **The strips between the corners must not vary along their length.** They are
    stretched to whatever the panel is wide, so a knot or a plank end in the top
    rail is drawn as a horizontal smear across the whole rail. Each strip is
    therefore *collapsed* — averaged along the direction it stretches — which
    keeps its cross-section (the bevel, the shadow under the lip) and discards the
    variation that cannot survive.

The four corners are the only part kept as drawn, because they are the only part
never stretched.

Two smaller things it does, both for the same reason as the marks cutter — an
image tool's output is not an asset until someone has checked these:

  * Forces true greyscale. These are **materials**: the palette multiplies them
    (§13.2), so a hue left in the file would be a hue in all six palettes.
  * Flattens the centre. It stretches in both directions at once, so anything
    drawn there is smeared twice — and it is what text is read against.

Standard library only.
"""

import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))
from cut_marks import read_png, write_png  # noqa: E402

## Slice inset, in output pixels. Must match `Art.PANEL_CORNER`, which is what
## `Surface` hands to `set_texture_margin_all`.
MARGIN = 24

## Output sizes to choose between. The one that best matches the *drawn* band is
## used, so the slice line lands where the artist put the edge of the material
## rather than somewhere through the middle of it.
SIZES = [96, 128, 192, 256, 384]


def greyscale(width, height, rows):
    for y in range(height):
        row = rows[y]
        for x in range(width):
            v = (row[x * 4] * 299 + row[x * 4 + 1] * 587 + row[x * 4 + 2] * 114) // 1000
            row[x * 4] = row[x * 4 + 1] = row[x * 4 + 2] = v
    return rows


def band_width(width, height, rows):
    """How thick the drawn border is, found where the picture stops varying.

    A frame's border carries grain, a bevel and a shadow, so its columns have
    structure down their length; the flat middle has almost none. The first column
    whose variation collapses is where the material ends.
    """
    profile = []
    step = max(1, height // 200)
    for x in range(width // 2):
        vals = [rows[y][x * 4] for y in range(height // 4, 3 * height // 4, step)]
        mean = sum(vals) / len(vals)
        profile.append((sum((v - mean) ** 2 for v in vals) / len(vals)) ** 0.5)

    peak = max(profile) if profile else 0.0
    if peak < 2.0:
        return 0  # a plain surface with no border to find

    # The **last** column that still varies, not the first that does not. A plank
    # has a flat face, so there are quiet columns in the middle of the timber, and
    # stopping at the first of them measured the border as half its real width —
    # which flattened most of the wood into the middle and left the corners as
    # specks.
    quiet = max(1.0, peak * 0.12)
    edge = 0
    for x, v in enumerate(profile):
        if v > quiet:
            edge = x
    return min(edge + 1, width // 3)


def sample(rows, x0, y0, x1, y1):
    """Mean luminance of a source rectangle."""
    total = n = 0
    step_x = max(1, (x1 - x0) // 16)
    step_y = max(1, (y1 - y0) // 16)
    for y in range(y0, y1, step_y):
        row = rows[y]
        for x in range(x0, x1, step_x):
            total += row[x * 4]
            n += 1
    return total // max(n, 1)


def resize_region(rows, src, dst_w, dst_h):
    """Box-filter one source rectangle into a dst_w x dst_h block of luminance."""
    x0, y0, x1, y1 = src
    sw, sh = max(1, x1 - x0), max(1, y1 - y0)
    out = []
    for dy in range(dst_h):
        line = []
        sy0 = y0 + dy * sh // dst_h
        sy1 = max(sy0 + 1, y0 + (dy + 1) * sh // dst_h)
        for dx in range(dst_w):
            sx0 = x0 + dx * sw // dst_w
            sx1 = max(sx0 + 1, x0 + (dx + 1) * sw // dst_w)
            line.append(sample(rows, sx0, sy0, sx1, sy1))
        out.append(line)
    return out


def collapse(block, along_x):
    """Average a strip along the axis it will be stretched on.

    This is the whole point of the tool. The cross-section is what carries the
    bevel and the shadow under the lip, and it is kept exactly; the variation
    *along* the run is what a stretch turns into a smear, and it goes.
    """
    if along_x:
        for row in block:
            mean = sum(row) // len(row)
            for i in range(len(row)):
                row[i] = mean
    else:
        for i in range(len(block[0])):
            mean = sum(block[y][i] for y in range(len(block))) // len(block)
            for y in range(len(block)):
                block[y][i] = mean
    return block


def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: python3 tools/cut_panel.py <source.png> <out.png>")
    source, target = sys.argv[1], sys.argv[2]

    width, height, rows = read_png(source)
    rows = greyscale(width, height, rows)
    band = band_width(width, height, rows)
    print("read %d×%d, drawn border %d px (%.1f%% of the side)"
          % (width, height, band, 100.0 * band / width))

    if band < width // 100:
        # A plain surface. Give it the smallest useful texture and a border of the
        # margin's own width, which is what the fill wants anyway.
        size, band = 96, max(1, width // 8)
        print("  no distinct border — treating it as a flat surface")
    else:
        want = MARGIN * width / float(band)
        size = min(SIZES, key=lambda s: abs(s - want))
        print("  %d px of margin wants a %d px texture; using %d" % (MARGIN, int(want), size))

    inner = size - MARGIN * 2
    if inner < 8:
        raise SystemExit("a %d px texture leaves no middle at a %d px margin"
                         % (size, MARGIN))

    xs = [0, band, width - band, width]
    ys = [0, band, height - band, height]
    out_x = [0, MARGIN, size - MARGIN, size]
    out_y = [0, MARGIN, size - MARGIN, size]

    canvas = [bytearray(size * 4) for _ in range(size)]
    for row in range(3):
        for col in range(3):
            dw = out_x[col + 1] - out_x[col]
            dh = out_y[row + 1] - out_y[row]
            block = resize_region(
                rows, (xs[col], ys[row], xs[col + 1], ys[row + 1]), dw, dh)
            if row == 1 and col == 1:
                flat = sum(sum(r) for r in block) // (dw * dh)
                block = [[flat] * dw for _ in range(dh)]
            elif row == 1:
                block = collapse(block, along_x=False)   # left/right stretch on y
            elif col == 1:
                block = collapse(block, along_x=True)    # top/bottom stretch on x
            for dy in range(dh):
                line = canvas[out_y[row] + dy]
                for dx in range(dw):
                    v = block[dy][dx]
                    o = (out_x[col] + dx) * 4
                    line[o] = line[o + 1] = line[o + 2] = v
                    line[o + 3] = 255

    write_png(target, size, size, canvas)
    print("wrote %s — %d×%d, nine-sliced at %d px" % (target, size, size, MARGIN))
    print("  corners kept as drawn; edges collapsed along their stretch; middle flat")


if __name__ == "__main__":
    main()

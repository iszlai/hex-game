#!/usr/bin/env python3
"""Turn a drawn stone texture into the board's material map.

    python3 tools/cut_grain.py ~/Downloads/stone.png

`tile_grain.png` is not a picture. The shader reads its red channel, doubles it,
and *multiplies* the tile's own colour by the result:

    g = texture(grain_map, ...).r * 2.0
    base *= mix(1.0, g, grain_strength)

which makes **mid-grey the identity**. 128 means "leave this tile alone"; darker
darkens it and lighter lightens it. So the one thing that matters more than what
the texture depicts is what it *averages*, and no image generator has any reason
to land on 128 — the sheet this was written for came back at 149, which is a 17%
lightening applied to every tile on the board and would have fought the palette
everywhere.

Four passes, in this order:

  * **Greyscale**, because only `.r` is ever read and a hue in the file is a hue
    nobody can see but everybody inherits.
  * **Despeckle** the bright tail. A generator signs its work, and a watermark in
    a tiling texture is a watermark repeated across the whole board. Anything far
    above the field is replaced from a ring around it rather than clamped, so the
    hole is filled with the texture's own material.
  * **Re-centre on mid-grey**, then hold the contrast inside a range the multiply
    can survive.
  * **Make it wrap**, by cross-fading each border into its mirror. Guarantees the
    first column equals the last by construction. On a fine even field it cannot
    be seen; on anything with structure it would be obvious, which is why the
    brief asks for a field.

Standard library only.
"""

import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))
from cut_marks import read_png, write_png  # noqa: E402

SIZE = 256

## What the shader treats as "no change".
NEUTRAL = 128

## How far from neutral the texture is allowed to swing, in 0-255 levels. The
## multiply doubles whatever is here, so ±32 is a 0.75x-1.25x range on the tile —
## enough to read as a material, not enough to argue with the palette.
SWING = 32

## A pixel this far above the field is not the field. Sized to catch a watermark
## and to leave real speckle alone.
SPECKLE_OVER = 26

## Fraction of the side spent cross-fading each border into its mirror.
WRAP = 0.07


def luminance(width, height, rows):
    out = bytearray(width * height)
    for y in range(height):
        row = rows[y]
        base = y * width
        for x in range(width):
            out[base + x] = (row[x * 4] * 299 + row[x * 4 + 1] * 587
                             + row[x * 4 + 2] * 114) // 1000
    return out


def despeckle(lum, width, height):
    """Replace anything far brighter than the field with the field around it."""
    ordered = sorted(lum[::7])
    high = ordered[len(ordered) * 99 // 100]
    ceiling = high + SPECKLE_OVER
    reach = max(8, width // 40)
    fixed = 0
    for y in range(height):
        base = y * width
        for x in range(width):
            if lum[base + x] <= ceiling:
                continue
            # A ring, not a disc: the neighbours immediately around a mark are
            # part of the mark, and the point is to borrow clean material.
            total = n = 0
            for dx, dy in ((reach, 0), (-reach, 0), (0, reach), (0, -reach),
                           (reach, reach), (-reach, -reach),
                           (reach, -reach), (-reach, reach)):
                sx, sy = (x + dx) % width, (y + dy) % height
                v = lum[sy * width + sx]
                if v <= ceiling:
                    total += v
                    n += 1
            if n:
                lum[base + x] = total // n
                fixed += 1
    if fixed:
        print("  despeckled %d px above %d — a signature, most likely" % (fixed, ceiling))
    return lum


def recentre(lum):
    """Put the average on neutral and hold the swing inside SWING."""
    mean = sum(lum) / len(lum)
    spread = sorted(lum[::7])
    low = spread[len(spread) // 100]
    high = spread[99 * len(spread) // 100]
    reach = max(1.0, (high - low) / 2.0)
    scale = min(1.0, SWING / reach)
    print("  mean %.1f → %d, swing ±%.0f → ±%.0f"
          % (mean, NEUTRAL, reach, reach * scale))
    for i, v in enumerate(lum):
        lum[i] = max(0, min(255, int(NEUTRAL + (v - mean) * scale)))
    return lum


def make_wrap(lum, width, height):
    """Cross-fade each border into its own mirror, so the edges meet exactly."""
    border = max(2, int(width * WRAP))
    for y in range(height):
        base = y * width
        for x in range(border):
            a = 0.5 * (1.0 - x / float(border))
            left, right = lum[base + x], lum[base + width - 1 - x]
            lum[base + x] = int(left * (1 - a) + right * a)
            lum[base + width - 1 - x] = int(right * (1 - a) + left * a)
    for x in range(width):
        for y in range(border):
            a = 0.5 * (1.0 - y / float(border))
            top, bottom = lum[y * width + x], lum[(height - 1 - y) * width + x]
            lum[y * width + x] = int(top * (1 - a) + bottom * a)
            lum[(height - 1 - y) * width + x] = int(bottom * (1 - a) + top * a)
    return lum


def downsample(lum, width, height, size):
    out = [bytearray(size * 4) for _ in range(size)]
    for dy in range(size):
        sy0, sy1 = dy * height // size, max(dy * height // size + 1, (dy + 1) * height // size)
        for dx in range(size):
            sx0, sx1 = dx * width // size, max(dx * width // size + 1, (dx + 1) * width // size)
            total = n = 0
            for sy in range(sy0, sy1):
                base = sy * width
                for sx in range(sx0, sx1):
                    total += lum[base + sx]
                    n += 1
            v = total // max(n, 1)
            o = dx * 4
            out[dy][o] = out[dy][o + 1] = out[dy][o + 2] = v
            out[dy][o + 3] = 255
    return out


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: python3 tools/cut_grain.py <source.png> [out.png]")
    # `~` survives make's quoting and would otherwise arrive as a literal.
    source = __import__("os").path.expanduser(sys.argv[1])
    target = sys.argv[2] if len(sys.argv) > 2 else "assets/art/tile_grain.png"

    width, height, rows = read_png(source)
    print("read %d×%d" % (width, height))
    lum = luminance(width, height, rows)
    lum = despeckle(lum, width, height)
    lum = recentre(lum)
    lum = make_wrap(lum, width, height)

    out = downsample(lum, width, height, SIZE)
    check = [out[y][x * 4] for y in range(SIZE) for x in range(SIZE)]
    seam_x = sum(abs(out[y][0] - out[y][(SIZE - 1) * 4]) for y in range(SIZE)) / SIZE
    seam_y = sum(abs(out[0][x * 4] - out[SIZE - 1][x * 4]) for x in range(SIZE)) / SIZE
    print("  final mean %.1f (neutral is %d), seam %.1f across / %.1f down"
          % (sum(check) / len(check), NEUTRAL, seam_x, seam_y))

    write_png(target, SIZE, SIZE, out)
    print("wrote %s — %d×%d, a value map" % (target, SIZE, SIZE))


if __name__ == "__main__":
    main()

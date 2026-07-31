extends SceneTree
## Renders §13.7's backdrops and panel surfaces into `assets/art/`, and the output
## is **committed** — the same arrangement as `make sfx` and `make levels`.
##
## C-27 is open: this project has no illustrator and no budget line for one, and
## C-26's direction needs both. What unblocks it is §13.6's rule that every art
## file is replaceable without a code change, so the game ships generated art now
## and swaps in painted art later without a script changing. That is the whole
## reason the direction was written that way round.
##
## What is generated is deliberately *scene*, not decoration: a dusk sky, a sun
## low in it, ridgelines receding into haze. It is enough to tell whether the
## contrast floor of §13.7 holds and whether the interface reads on top of a
## picture — which is the question the placeholder exists to answer.
##
## Colour is **not** baked in. Every image is rendered neutral-warm and tinted at
## runtime through a palette token (§13.2), so §21's four palettes reach the art.
##
## Run: godot --headless --path . -s res://tools/make_art.gd

const OUT_DIR := "res://assets/art/"

## §13.6: 1920×1200 is 1280×800 with room to crop on a wider window.
const BACKDROP := Vector2i(1920, 1200)

## §13.7 gives one backdrop per chapter plus one for the menus. The seed is what
## makes each chapter a different place while the whole set stays one painting.
const SCENES := {
	"menu": 1,
	"chapter_1": 2,
	"chapter_2": 3,
	"chapter_3": 4,
	"chapter_4": 5,
	"chapter_5": 6,
}

## The 9-slice panel surfaces. A frame carries the material, a fill carries the
## reading surface (§13.7).
const PANEL := Vector2i(96, 96)
const PANEL_CORNER := 24

## The board's own material (§13.6). Sampled in board space and tiled across every
## prism, so it has to be **seamless**: built from sines at whole-number
## frequencies over the 0–1 domain, which are periodic by construction rather than
## by a blend at the edges that would show up as a grid on a board of sixty tiles.
const GRAIN := Vector2i(256, 256)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for name: String in SCENES:
		var image := _backdrop(int(SCENES[name]))
		_save(image, name + ".png")
	_save(_frame(), "panel_frame.png")
	_save(_fill(), "panel_fill.png")
	_save(_grain(), "tile_grain.png")
	print("wrote ", SCENES.size() + 3, " art files to ", OUT_DIR)
	quit()


func _save(image: Image, file: String) -> void:
	image.save_png(ProjectSettings.globalize_path(OUT_DIR + file))


## A dusk sky with a low sun and receding ridges. Rendered in greys and warm
## neutrals only: the palette tints it, so a hue baked in here would survive all
## four of §21's swaps (§13.2).
func _backdrop(scene_seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = scene_seed * 7919
	var image := Image.create(BACKDROP.x, BACKDROP.y, false, Image.FORMAT_RGB8)

	# Sky: a vertical ramp from deep at the top to bright at the horizon, with the
	# sun's glow added radially so the light in the scene comes from somewhere in it.
	var horizon: float = BACKDROP.y * 0.62
	var sun := Vector2(BACKDROP.x * (0.18 + 0.64 * rng.randf()), horizon - 40.0)
	for y: int in range(BACKDROP.y):
		var t: float = clampf(float(y) / horizon, 0.0, 1.0)
		var sky: float = lerpf(0.06, 0.52, pow(t, 1.6))
		for x: int in range(BACKDROP.x):
			var d: float = Vector2(float(x), float(y)).distance_to(sun)
			var glow: float = exp(-d / 420.0) * 0.55
			var v: float = clampf(sky + glow, 0.0, 1.0)
			image.set_pixel(x, y, Color(v, v * 0.94, v * 0.86))

	# Ridges: each is a 1-D value-noise silhouette, darker and sharper as it comes
	# forward, so depth reads without any colour doing the work.
	var ridges: int = 4
	for r: int in range(ridges):
		var depth: float = float(r) / float(ridges - 1)
		var base: float = horizon - 190.0 * (1.0 - depth) - 40.0
		var amplitude: float = 90.0 * (1.0 - depth) + 30.0
		var value: float = lerpf(0.30, 0.045, depth)
		var profile := _ridge_profile(rng, amplitude)
		for x: int in range(BACKDROP.x):
			var top: int = int(base + profile[x])
			for y: int in range(maxi(0, top), BACKDROP.y):
				# A little vertical falloff keeps the near ridges from reading flat.
				var shade: float = value * (1.0 - 0.25 * float(y - top) / float(BACKDROP.y))
				image.set_pixel(x, y, Color(shade, shade * 0.95, shade * 0.9))
	return image


## Value noise over the width, summed at three octaves. Deterministic from the
## seeded generator it is handed — §19 keeps global RNG out of `src/`, and a tool
## that produced a different picture every run could not have its output committed.
func _ridge_profile(rng: RandomNumberGenerator, amplitude: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(BACKDROP.x)
	var octaves: Array[PackedFloat32Array] = []
	var scales: Array[int] = [7, 17, 41]
	for count: int in scales:
		var points := PackedFloat32Array()
		for i: int in range(count + 1):
			points.append(rng.randf() * 2.0 - 1.0)
		octaves.append(points)

	for x: int in range(BACKDROP.x):
		var total: float = 0.0
		var weight: float = 1.0
		for o: int in range(octaves.size()):
			var points: PackedFloat32Array = octaves[o]
			var span: float = float(BACKDROP.x) / float(scales[o])
			var at: float = float(x) / span
			var i: int = int(at)
			var f: float = at - float(i)
			# Smoothstep between control points, so a ridge has no visible corners.
			var e: float = f * f * (3.0 - 2.0 * f)
			total += lerpf(points[i], points[i + 1], e) * weight
			weight *= 0.45
		out[x] = total * amplitude
	return out


## The frame: a bevelled border with a grain around a plain middle, drawn white so
## the tint decides its colour.
##
## The middle is *opaque* rather than cut out, because a `StyleBoxTexture` takes
## one texture: a hollow frame would need a second layer behind it and a second
## node to hold it. One image per surface, one tint per image — the frame texture
## is the timber of a bar or rail, the fill texture is the paper of a row, and
## §13.7's "frame carries the material, fill carries the reading surface" is
## expressed by *which* surface takes which, not by stacking them.
func _frame() -> Image:
	var image := Image.create(PANEL.x, PANEL.y, false, Image.FORMAT_RGBA8)
	for y: int in range(PANEL.y):
		for x: int in range(PANEL.x):
			var edge: int = mini(mini(x, y), mini(PANEL.x - 1 - x, PANEL.y - 1 - y))
			if edge >= PANEL_CORNER - 6:
				# The interior: the same grain, without the bevel.
				var flat: float = 0.72 + 0.05 * sin(float(x) * 0.9 + float(y) * 1.7)
				image.set_pixel(x, y, Color(flat, flat, flat, 1.0))
				continue
			# Bright on the top and left, dark on the bottom and right: a bevel is
			# the cheapest thing that reads as a material rather than a rectangle.
			var lit: float = 1.0 if (x < PANEL.x / 2 and x <= y) or (y < PANEL.y / 2 and y <= x) \
				else 0.62
			var grain: float = 0.90 + 0.10 * sin(float(x) * 0.7 + float(y) * 2.3)
			var v: float = clampf(lit * grain, 0.0, 1.0)
			image.set_pixel(x, y, Color(v, v, v, 1.0))
	return image


## The board's grain. Mid-grey at rest — the shader multiplies by it, so 0.5 is
## "no change" and the texture only ever lightens or darkens a tile that already
## has its palette colour. Never tinted: this one carries value, not hue.
func _grain() -> Image:
	var image := Image.create(GRAIN.x, GRAIN.y, false, Image.FORMAT_RGB8)
	for y: int in range(GRAIN.y):
		var v: float = float(y) / float(GRAIN.y) * TAU
		for x: int in range(GRAIN.x):
			var u: float = float(x) / float(GRAIN.x) * TAU
			# Three octaves, each an integer number of cycles across the tile.
			var n: float = 0.5 \
				+ 0.030 * sin(u * 3.0 + sin(v * 2.0) * 1.7) \
				+ 0.022 * sin(v * 7.0 + sin(u * 5.0) * 1.1) \
				+ 0.014 * sin((u + v) * 11.0)
			var g: float = clampf(n, 0.0, 1.0)
			image.set_pixel(x, y, Color(g, g, g))
	return image


## The fill: a flat surface with a faint fibre, so a panel is a made thing rather
## than a rectangle of colour. White for the same tinting reason.
func _fill() -> Image:
	var image := Image.create(PANEL.x, PANEL.y, false, Image.FORMAT_RGBA8)
	for y: int in range(PANEL.y):
		for x: int in range(PANEL.x):
			var fibre: float = 0.94 \
				+ 0.04 * sin(float(y) * 1.9 + sin(float(x) * 0.21) * 2.0) \
				+ 0.02 * sin(float(x) * 3.7)
			var v: float = clampf(fibre, 0.0, 1.0)
			image.set_pixel(x, y, Color(v, v, v, 1.0))
	return image

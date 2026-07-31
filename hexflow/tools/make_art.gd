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
		# **Never overwrite a backdrop that already exists.** C-27's whole shape is
		# that real art replaces the generated set by dropping files in, and a
		# generator that clobbered them would make `make art` — a command someone
		# runs to refresh the panel textures — destroy an illustrator's work.
		if FileAccess.file_exists(OUT_DIR + name + ".png"):
			print("kept ", name, ".png (already provided)")
			continue
		_save(_backdrop(int(SCENES[name])), name + ".png")
	_save(_frame(), "panel_frame.png")
	_save(_fill(), "panel_fill.png")
	_save(_grain(), "tile_grain.png")
	print("wrote ", SCENES.size() + 3, " art files to ", OUT_DIR)
	quit()


func _save(image: Image, file: String) -> void:
	image.save_png(ProjectSettings.globalize_path(OUT_DIR + file))


## A dusk sky with a low sun and receding ridges.
##
## Everything here is **value**. The palette supplies the hue (§13.2), so a dusk
## has to be built out of brightness alone: a sky that darkens upward, a sun low
## enough to rake the ridges, haze pooling where each ridge meets the one behind
## it, stars where the sky is dark enough to hold them, and a vignette that pulls
## the corners down. Those are the same cues a painter uses; none of them needs a
## colour to work.
##
## The vignette is not only atmosphere. §13.7 puts a contrast floor over this
## picture and the scrim holds it — but the corners are where the title block and
## the rail sit, so darkening them means the scrim has less to do and more of the
## painting survives underneath the interface.
func _backdrop(scene_seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = scene_seed * 7919
	var image := Image.create(BACKDROP.x, BACKDROP.y, false, Image.FORMAT_RGB8)

	var horizon: float = BACKDROP.y * 0.62
	var sun := Vector2(BACKDROP.x * (0.18 + 0.64 * rng.randf()), horizon - 40.0)
	var centre := Vector2(BACKDROP.x, BACKDROP.y) * 0.5
	var radius: float = centre.length()

	for y: int in range(BACKDROP.y):
		var t: float = clampf(float(y) / horizon, 0.0, 1.0)
		var sky: float = lerpf(0.05, 0.55, pow(t, 1.7))
		for x: int in range(BACKDROP.x):
			var here := Vector2(float(x), float(y))
			var glow: float = exp(-here.distance_to(sun) / 430.0) * 0.60
			var v: float = clampf(sky + glow, 0.0, 1.0)
			image.set_pixel(x, y, Color(v, v * 0.94, v * 0.86))

	_stars(image, rng, horizon)
	_moon(image, rng, horizon)

	# Ridges, back to front. Each lays a band of haze along its own crest before it
	# is filled, which is what separates one ridge from the next without an outline.
	var ridges: int = 5
	for r: int in range(ridges):
		var depth: float = float(r) / float(ridges - 1)
		var base: float = horizon - 210.0 * (1.0 - depth) - 30.0
		var amplitude: float = 100.0 * (1.0 - depth) + 26.0
		var value: float = lerpf(0.34, 0.035, depth)
		var haze: float = lerpf(0.16, 0.02, depth)
		var profile := _ridge_profile(rng, amplitude)
		for x: int in range(BACKDROP.x):
			var top: int = int(base + profile[x])
			# Haze sits *above* the crest, brightest at it, fading upward.
			for hy: int in range(maxi(0, top - 90), maxi(0, top)):
				var lift: float = haze * (1.0 - float(top - hy) / 90.0)
				var c: Color = image.get_pixel(x, hy)
				image.set_pixel(x, hy, Color(
					clampf(c.r + lift, 0.0, 1.0),
					clampf(c.g + lift * 0.95, 0.0, 1.0),
					clampf(c.b + lift * 0.88, 0.0, 1.0)))
			for y: int in range(maxi(0, top), BACKDROP.y):
				var shade: float = value * (1.0 - 0.28 * float(y - top) / float(BACKDROP.y))
				image.set_pixel(x, y, Color(shade, shade * 0.95, shade * 0.9))

	# The vignette, last, over everything.
	for y: int in range(BACKDROP.y):
		for x: int in range(BACKDROP.x):
			var d: float = Vector2(float(x), float(y)).distance_to(centre) / radius
			var fall: float = 1.0 - 0.55 * pow(clampf(d, 0.0, 1.0), 2.2)
			var c: Color = image.get_pixel(x, y)
			image.set_pixel(x, y, Color(c.r * fall, c.g * fall, c.b * fall))
	return image


## Stars, only where the sky is dark enough to keep them. Sized in whole pixels
## because a star is one or two pixels or it is a smudge.
func _stars(image: Image, rng: RandomNumberGenerator, horizon: float) -> void:
	var count: int = 140
	for _i: int in range(count):
		var x: int = rng.randi_range(0, BACKDROP.x - 1)
		var y: int = rng.randi_range(0, int(horizon * 0.72))
		var here: Color = image.get_pixel(x, y)
		if here.r > 0.32:
			continue
		var bright: float = clampf(here.r + rng.randf_range(0.18, 0.55), 0.0, 1.0)
		image.set_pixel(x, y, Color(bright, bright, bright))
		if rng.randf() > 0.75 and x + 1 < BACKDROP.x:
			image.set_pixel(x + 1, y, Color(bright * 0.6, bright * 0.6, bright * 0.6))


## A crescent: one disc of light with a second, offset disc cut back out of it.
## The offset decides which way it faces, and the seed decides the offset, so the
## six backdrops do not all show the same night.
func _moon(image: Image, rng: RandomNumberGenerator, horizon: float) -> void:
	var r: float = rng.randf_range(34.0, 52.0)
	var at := Vector2(
		rng.randf_range(r * 3.0, float(BACKDROP.x) - r * 3.0),
		rng.randf_range(r * 2.5, horizon * 0.5))
	var shift := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 0.6)).normalized() * r * 0.62
	for y: int in range(int(at.y - r - 2.0), int(at.y + r + 2.0)):
		if y < 0 or y >= BACKDROP.y:
			continue
		for x: int in range(int(at.x - r - 2.0), int(at.x + r + 2.0)):
			if x < 0 or x >= BACKDROP.x:
				continue
			var p := Vector2(float(x), float(y))
			var inside: float = r - p.distance_to(at)
			if inside <= 0.0:
				continue
			if p.distance_to(at + shift) < r * 0.94:
				continue
			var edge: float = clampf(inside, 0.0, 1.5) / 1.5
			var c: Color = image.get_pixel(x, y)
			var lit: float = lerpf(c.r, 0.96, edge)
			image.set_pixel(x, y, Color(lit, lit * 0.98, lit * 0.94))


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

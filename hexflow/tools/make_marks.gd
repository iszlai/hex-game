extends SceneTree
## Renders C-29's illustrated modifier atlas into `assets/art/marks.png`, and the
## output is **committed** — the same arrangement as `make sfx`, `make art`,
## `make glyphs` and `make levels`.
##
## What this is for is narrower than it looks. C-29's illustrated set is the *nice*
## presentation and C-23's silhouettes are the floor, so a generated stand-in for
## the nice one is not closing a gap — the board is complete without it. What it
## closes is a **pipeline** question: four cells in the right order, transparent
## background, alpha that composites, colour that survives not being tinted. Those
## are the things that would otherwise be discovered the day real art arrives, and
## discovered as "the padlock is in the wild's slot".
##
## So it is deliberately the same four shapes the shader already draws, in colour
## and with an outline. It looks like what it is: a proof that the slot works.
## Replacing it with something painted is the point, and `make assets ROLE=marks`
## states what to paint.
##
## Unlike every other image in the project these carry their **own colour** — the
## board does not tint them (C-29) — so the palette tokens below are read once, at
## authoring time, from the default palette rather than applied at runtime.
##
## Run: godot --headless --path . -s res://tools/make_marks.gd

const OUT := "res://assets/art/marks.png"

## One square cell per mark, in `BoardMarks.Mark` order. The shader divides the
## atlas by this count, so the two must agree — `tests/unit/test_board_marks.gd`
## holds them together.
const CELL := 256
const MARKS := ["goal", "portal", "gate", "wild"]

## Drawn at final size. There is no supersample here and there does not need to be:
## the coverage below comes from the distance field itself, which is a better edge
## than averaging four samples of a hard one — and a million per-pixel SDF calls in
## GDScript is a minute of waiting for a worse result.
const SS := 1

## Outline width in cell units, and the ink it is drawn in. Every mark carries its
## own, because a mark sits on tiles of several colours and heights and the outline
## is the only thing that keeps its silhouette against all of them.
const OUTLINE := 0.075


func _initialize() -> void:
	var fresh: bool = OS.get_cmdline_user_args().has("fresh")
	if FileAccess.file_exists(OUT) and not fresh:
		print("kept ", OUT, " (already provided) — `make marks FRESH=1` overwrites")
		quit()
		return

	# Typed `Resource`, not `Palette`. A `-s` tool script runs before the global
	# class cache is available, so the `.tres` comes back as a plain resource with
	# `palette.gd` attached and a typed assignment fails — which, in a SceneTree
	# script, means `_initialize` throws before it reaches `quit()` and the process
	# then sits there forever. Read the tokens through `get()` instead.
	var palette: Resource = load("res://src/data/palettes/cairn_warm.tres")
	if palette == null:
		push_error("cairn_warm.tres is missing; nothing to take colours from")
		quit(1)
		return
	var atlas := Image.create(CELL * MARKS.size(), CELL, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.0, 0.0, 0.0, 0.0))
	for i: int in range(MARKS.size()):
		var cell := _render(str(MARKS[i]), palette)
		atlas.blit_rect(cell, Rect2i(0, 0, CELL, CELL), Vector2i(i * CELL, 0))

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUT.get_base_dir()))
	atlas.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote %d×%d — %s, in that order" % [
		CELL * MARKS.size(), CELL, ", ".join(MARKS)])
	print("  a stand-in: replace it with painted art (`make assets ROLE=marks`)")
	quit()


func _fill_of(mark: String, palette: Resource) -> Color:
	match mark:
		"goal":
			return palette.get("goal_cell") as Color
		"portal":
			return palette.get("portal") as Color
		"gate":
			return palette.get("gate") as Color
		_:
			return palette.get("wild") as Color


## One cell, drawn from its own signed-distance field so the edge and the outline
## come out at the same quality the shader gets.
func _render(mark: String, palette: Resource) -> Image:
	var big: int = CELL * SS
	var image := Image.create(big, big, false, Image.FORMAT_RGBA8)
	var fill: Color = _fill_of(mark, palette)
	var ink: Color = palette.get("board_mark_outline") as Color
	# One pixel wide in cell units, which is where a distance field wants its edge.
	var aa: float = 1.0 / float(big)

	for y: int in range(big):
		for x: int in range(big):
			# Cell space: -1 … 1, y up, so the shapes read the way they are written.
			var p := Vector2(
				(float(x) + 0.5) / float(big) * 2.0 - 1.0,
				1.0 - (float(y) + 0.5) / float(big) * 2.0)
			var d: float = _sdf(mark, p)
			var shell: float = _step(d - OUTLINE, aa)
			if shell <= 0.0:
				continue
			var body: float = _step(d, aa)
			var c: Color = ink.lerp(fill, body)
			image.set_pixel(x, y, Color(c.r, c.g, c.b, shell))

	if big != CELL:
		image.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
	return image


## 1 inside, 0 outside, smooth across [param aa].
func _step(d: float, aa: float) -> float:
	return clampf((aa - d) / (2.0 * aa), 0.0, 1.0)


func _sdf(mark: String, p: Vector2) -> float:
	match mark:
		"goal":
			# A reticle: an outer ring, a centre disc, and four ticks — the same
			# reading as §6's goal, which is "aim here".
			var d: float = _ring(p, 0.74, 0.15)
			d = minf(d, _disc(p, 0.20))
			for i: int in range(4):
				var a: float = deg_to_rad(90.0 * float(i))
				var dir := Vector2(cos(a), sin(a))
				d = minf(d, _segment(p, dir * 0.44, dir * 0.62, 0.075))
			return d
		"portal":
			# Two concentric rings — a pair, because a portal always is one.
			return minf(_ring(p, 0.78, 0.14), _ring(p, 0.42, 0.14))
		"gate":
			# A padlock: shackle over body. The shackle is a half ring, cut by
			# taking only what stands above the body's top edge.
			var body: float = _round_box(p - Vector2(0.0, -0.24), Vector2(0.52, 0.40), 0.14)
			var shackle: float = maxf(
				_ring(p - Vector2(0.0, 0.16), 0.34, 0.13), -p.y + 0.16)
			return minf(body, shackle)
		_:
			return _star5(p, 0.92, 0.42)


func _disc(p: Vector2, r: float) -> float:
	return p.length() - r


func _ring(p: Vector2, r: float, w: float) -> float:
	return absf(p.length() - r) - w * 0.5


func _round_box(p: Vector2, half: Vector2, r: float) -> float:
	var q: Vector2 = p.abs() - half + Vector2(r, r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


func _segment(p: Vector2, a: Vector2, b: Vector2, w: float) -> float:
	var ba: Vector2 = b - a
	var t: float = clampf((p - a).dot(ba) / ba.length_squared(), 0.0, 1.0)
	return (p - (a + ba * t)).length() - w * 0.5


## Five-pointed star, [param rf] being the inner radius as a fraction of the outer.
## Folded across three mirrors rather than built from ten vertices, which is what
## keeps it a distance field the outline can be grown from.
func _star5(p: Vector2, r: float, rf: float) -> float:
	var k1 := Vector2(0.809016994375, -0.587785252292)
	var k2 := Vector2(-k1.x, k1.y)
	var q := Vector2(absf(p.x), p.y)
	q -= k1 * (2.0 * maxf(q.dot(k1), 0.0))
	q -= k2 * (2.0 * maxf(q.dot(k2), 0.0))
	q = Vector2(absf(q.x), q.y - r)
	var ba: Vector2 = Vector2(-k1.y, k1.x) * rf - Vector2(0.0, 1.0)
	var h: float = clampf(q.dot(ba) / ba.length_squared(), 0.0, r)
	return (q - ba * h).length() * signf(q.y * ba.x - q.x * ba.y)

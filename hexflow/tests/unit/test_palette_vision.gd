## @core — §21's alternate palettes, checked by **simulating** the vision they are
## for rather than by trusting whoever picked the colours.
##
## "Deuteranopia-safe" is a claim, and a palette author has no way to verify it by
## looking: the whole point is that they see something the player will not. So the
## deficiency is simulated here (Viénot, Brettel & Mollon's linear approximation)
## and the pairs the game actually asks a player to tell apart are measured
## *afterwards*.
##
## The pairs are not arbitrary — each is a decision the game forces:
##   path / goal / wild     the three things that glow at once on a chapter-5 board
##   portal / gate          two modifiers that stand side by side from chapter 4
##   wall / empty           once within 1% luminance; only §6's hatch saved them
##   text / surface         §13.7's 4.5:1 reading floor
##
## §21 is explicit that colour is never the *only* channel — every one of these
## also differs in glyph, shape and, on the board, height. That is what makes this
## a floor rather than the whole answer: it stops a palette from making two states
## identical, it does not promise a beautiful one.
extends GutTest

const DIR := "res://src/data/palettes/"

## Which deficiency each palette is *for*. `cairn_warm` and `neon_dark` are the two
## unconstrained ones — they are checked in greyscale only, which every palette has
## to pass because §21 asks for a greyscale playthrough regardless.
const FOR := {
	"deuter": "deuter",
	"protan": "protan",
	"tritan": "tritan",
	"high_contrast": "grey",
	"cairn_warm": "grey",
	"neon_dark": "grey",
}

## Two colours are "apart" if either channel separates them: a real luminance step,
## or enough remaining chroma difference after the simulation. One is enough,
## because either alone is a cue a player can use.
const MIN_LUMA := 0.10
const MIN_DISTANCE := 0.22

## The reading floor of §13.7, as a WCAG contrast ratio.
const MIN_TEXT_CONTRAST := 4.5

## The floor for a cue that is not text — a focus ring, a candidate's stroke, a
## wall's hatch. WCAG 1.4.11's non-text minimum, and a *ratio* rather than an
## absolute luminance step on purpose: luminance is compressed at the dark end, so
## a flat difference asks far more of a near-black palette than of a bright one and
## would quietly rule out the dark boards this game is made of.
const MIN_UI_CONTRAST := 3.0


func _palettes() -> Array[String]:
	var out: Array[String] = []
	for file: String in DirAccess.get_files_at(DIR):
		if file.ends_with(".tres"):
			out.append(file.get_basename())
	return out


## The pairs where **colour** is one of the cues, so a palette that collapses them
## has thrown a channel away.
##
## `wall_fill` / `cell_empty_fill` is deliberately **not** here. §6 gives a wall a
## 45° hatch precisely because the two fills sit within 1% of each other in
## luminance in the shipped palette — the pattern *is* the cue, and demanding a
## colour difference as well would be inventing a requirement the design does not
## have. What is checked instead is that the hatch can be seen against the wall it
## is drawn on, which is the thing that would actually break.
func _pairs() -> Array:
	return [
		["path_core", "goal_cell"],
		["path_core", "wild"],
		["goal_cell", "wild"],
		["portal", "gate"],
		["cell_candidate_stroke", "cell_empty_stroke"],
		["start_cell", "goal_cell"],
		["focus", "surface_panel"],
	]


## The pairs that have **no second channel at all** and therefore need luminance on
## its own. Everything in `_pairs` above also differs by glyph or shape — a goal
## carries a reticle, a wild a star, a portal two rings, a gate a padlock — so a
## greyscale player still has those. These two do not:
##
##   candidate / empty stroke   the candidate *breathes*, and §14.5 stops the loop
##                              under Reduce Motion, leaving brightness alone
##   focus / the surface        §12.5: the ring is "never invisible"
func _greyscale_pairs() -> Array:
	return [
		["cell_candidate_stroke", "cell_empty_stroke"],
		["focus", "surface_panel"],
	]


func test_every_palette_keeps_its_decisions_apart() -> void:
	for name: String in _palettes():
		var palette: Palette = load(DIR + name + ".tres")
		var mode: String = str(FOR.get(name, "grey"))
		for pair: Variant in _pairs():
			var tokens: Array = pair
			var a: Color = _simulate(palette.get(tokens[0]) as Color, mode)
			var b: Color = _simulate(palette.get(tokens[1]) as Color, mode)
			assert_true(_apart(a, b),
				"%s: %s and %s collapse together under %s (Δluma %.3f, Δrgb %.3f)" % [
					name, tokens[0], tokens[1], mode, absf(_luma(a) - _luma(b)), _distance(a, b)
				])


## §21 asks for a full level played in greyscale. Most of what that needs is glyph
## and shape, which other tests stand over; what *this* one covers is the handful
## of pairs where brightness is the only cue left once colour is gone.
func test_every_palette_survives_greyscale() -> void:
	for name: String in _palettes():
		var palette: Palette = load(DIR + name + ".tres")
		for pair: Variant in _greyscale_pairs():
			var tokens: Array = pair
			var contrast: float = _contrast(
				palette.get(tokens[0]) as Color, palette.get(tokens[1]) as Color)
			assert_gte(contrast, MIN_UI_CONTRAST,
				"%s: %s against %s is %.2f:1 in greyscale, under WCAG's %.1f:1" % [
					name, tokens[0], tokens[1], contrast, MIN_UI_CONTRAST
				])


## §6's hatch is what tells a wall from an empty cell when colour is gone, so the
## hatch has to be visible *on the wall*. This is the pair `_pairs` exempts, checked
## the way the design actually solves it.
func test_the_wall_hatch_is_visible_on_the_wall_it_marks() -> void:
	for name: String in _palettes():
		var palette: Palette = load(DIR + name + ".tres")
		var contrast: float = _contrast(palette.wall_stroke, palette.wall_fill)
		assert_gte(contrast, MIN_UI_CONTRAST,
			"%s: the wall hatch is %.2f:1 against its own wall (§6, §21)" % [name, contrast])


## §13.7's reading floor, on the surface the text is actually drawn on.
func test_text_meets_the_reading_floor_on_its_own_panel() -> void:
	for name: String in _palettes():
		var palette: Palette = load(DIR + name + ".tres")
		for token: String in ["text_primary", "text_secondary"]:
			var ratio: float = _contrast(palette.get(token) as Color, palette.surface_panel)
			assert_gte(ratio, MIN_TEXT_CONTRAST,
				"%s: %s on surface_panel is %.2f:1, under §13.7's %.1f:1" % [
					name, token, ratio, MIN_TEXT_CONTRAST
				])


## §21 names four alternates to the default. All four have to exist to be swapped
## to, and the Accessibility tab can only offer what is in the build.
func test_all_four_alternates_ship() -> void:
	for required: String in ["deuter", "protan", "tritan", "high_contrast"]:
		assert_true(_palettes().has(required), "§21's %s palette is missing" % required)


# --- simulation ----------------------------------------------------------------

## Viénot, Brettel & Mollon's linear dichromacy approximation, applied in linear
## RGB. Close enough for a floor test and small enough to read — the alternative
## is a dependency this project would then have to vendor and pin.
func _simulate(colour: Color, mode: String) -> Color:
	if mode == "grey":
		return colour
	var c: Vector3 = Vector3(
		_to_linear(colour.r), _to_linear(colour.g), _to_linear(colour.b)
	)
	var out := c
	match mode:
		"protan":
			out = Vector3(
				0.11238 * c.x + 0.88762 * c.y + 0.0 * c.z,
				0.11238 * c.x + 0.88762 * c.y + 0.0 * c.z,
				0.00401 * c.x - 0.00401 * c.y + 1.0 * c.z)
		"deuter":
			out = Vector3(
				0.29275 * c.x + 0.70725 * c.y + 0.0 * c.z,
				0.29275 * c.x + 0.70725 * c.y + 0.0 * c.z,
				-0.02234 * c.x + 0.02234 * c.y + 1.0 * c.z)
		"tritan":
			out = Vector3(
				1.0 * c.x + 0.14461 * c.y - 0.14461 * c.z,
				0.0 * c.x + 0.86124 * c.y + 0.13876 * c.z,
				0.0 * c.x + 0.86124 * c.y + 0.13876 * c.z)
	return Color(
		_to_srgb(clampf(out.x, 0.0, 1.0)),
		_to_srgb(clampf(out.y, 0.0, 1.0)),
		_to_srgb(clampf(out.z, 0.0, 1.0)))


func _apart(a: Color, b: Color) -> bool:
	return absf(_luma(a) - _luma(b)) >= MIN_LUMA or _distance(a, b) >= MIN_DISTANCE


func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## Relative luminance, sRGB coefficients on linearised channels — the same figure
## WCAG's contrast ratio is built from, so the two tests agree about brightness.
func _luma(c: Color) -> float:
	return 0.2126 * _to_linear(c.r) + 0.7152 * _to_linear(c.g) + 0.0722 * _to_linear(c.b)


func _contrast(a: Color, b: Color) -> float:
	var la: float = _luma(a)
	var lb: float = _luma(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _to_linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


func _to_srgb(v: float) -> float:
	return v * 12.92 if v <= 0.0031308 else 1.055 * pow(v, 1.0 / 2.4) - 0.055

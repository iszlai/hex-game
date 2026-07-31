## §13.4's five type roles, as one theme.
##
## Three families ship, all SIL OFL, all **variable** — one file each carries every
## weight on a `wght` axis, so Medium and Bold are a [FontVariation] rather than a
## second file. That is why `assets/fonts/` holds three TTFs and not six.
##
## Roles rather than sizes at the call site. A screen says a label is a caption; it
## does not say 18. That is what makes §21's 1.0–1.5 text scaling a setting rather
## than an edit — and what keeps §13.4's floor enforceable in one place, because
## the floor is a property of the role table, not of each screen's memory of it.
##
## The floor is the point: **18 px absolute, at every scale**. The Deck's screen is
## 7 inches, and anything under 18 fails a legibility self-audit (§13.4, §21).
class_name Typography

const DIR := "res://assets/fonts/"

## §13.4's table. `weight` is the variable axis; `size` is the px at 1.0 scale and
## at 1280×800, which §21's text scale then multiplies.
enum Role { DISPLAY, HEADING, BODY, CAPTION, NUMERAL }

const ROLES := {
	Role.DISPLAY: {"family": "SpaceGrotesk", "weight": 700, "size": 48},
	Role.HEADING: {"family": "SpaceGrotesk", "weight": 500, "size": 32},
	Role.BODY: {"family": "Inter", "weight": 500, "size": 24},
	Role.CAPTION: {"family": "Inter", "weight": 400, "size": 18},
	Role.NUMERAL: {"family": "JetBrainsMono", "weight": 500, "size": 24},
}

## The name each role answers to as a `theme_type_variation`, so a scene can ask
## for a role without knowing a font or a number.
const VARIATIONS := {
	Role.DISPLAY: "Display",
	Role.HEADING: "Heading",
	Role.BODY: "Body",
	Role.CAPTION: "Caption",
	Role.NUMERAL: "Numeral",
}

## Never smaller, whatever the scale does (§13.4).
const FLOOR_PX := 18

## §21's range. Below 1.0 would breach the floor; above 1.5 reflows past what the
## layouts are tested at.
const MIN_SCALE := 1.0
const MAX_SCALE := 1.5


## The px a role is drawn at under [param scale]. Rounded, then floored — a role
## can only ever be pushed *up* by the scale, never below §13.4's minimum.
static func size_of(role: Role, scale: float = 1.0) -> int:
	var base: int = int(ROLES[role]["size"])
	return maxi(FLOOR_PX, int(round(float(base) * clampf(scale, MIN_SCALE, MAX_SCALE))))


## The font for [param role] at its weight. A [FontVariation] over the family's one
## variable file, so a weight costs nothing but a resource.
static func font_of(role: Role) -> FontVariation:
	var base := FontFile.new()
	base.load_dynamic_font(DIR + str(ROLES[role]["family"]) + ".ttf")
	base.fallbacks = _fallbacks(str(ROLES[role]["family"]))
	var variation := FontVariation.new()
	variation.base_font = base
	variation.variation_opentype = {"wght": int(ROLES[role]["weight"])}
	if role == Role.NUMERAL:
		# Tabular figures, so a counter ticking from 9 to 10 does not shift the
		# glyphs beside it (§13.4). JetBrains Mono is monospaced anyway; asking is
		# what keeps that true if the numeral family is ever changed.
		var ts := TextServerManager.get_primary_interface()
		variation.opentype_features = {ts.name_to_tag("tnum"): 1}
	return variation


## The other two families, behind whichever one this role uses.
##
## Not a nicety. A display face is chosen for its letters and carries almost no
## symbols: Space Grotesk has no ★, so the results card — which is set in Display —
## drew its three stars as three empty boxes, and nothing failed. The legend, the
## streak pips and the legend button were the same story in other faces.
##
## A fallback chain is the general answer rather than hunting for characters every
## face happens to share, and it is what makes §13.4's families *replaceable*: the
## next display face will have its own gaps and they will be covered the same way.
## What it cannot cover is a character no vendored face has at all —
## `tests/unit/test_typography.gd` is what catches those, because they are silent.
static func _fallbacks(family: String) -> Array[Font]:
	var out: Array[Font] = []
	for other: String in ["Inter", "JetBrainsMono", "SpaceGrotesk"]:
		if other == family:
			continue
		var font := FontFile.new()
		font.load_dynamic_font(DIR + other + ".ttf")
		out.append(font)
	return out


## One theme carrying all five roles: the default type is Body, and each other role
## is a named variation a `Control` can opt into.
static func theme(scale: float = 1.0) -> Theme:
	var t := Theme.new()
	t.default_font = font_of(Role.BODY)
	t.default_font_size = size_of(Role.BODY, scale)
	for role: Variant in ROLES:
		var name: String = VARIATIONS[role]
		var font: FontVariation = font_of(role as Role)
		var px: int = size_of(role as Role, scale)
		# Both, because a `Label` and a `Button` do not share a theme type and the
		# rail is made of both.
		for type: String in ["Label", "Button"]:
			t.set_type_variation(name + type, type)
			t.set_font("font", name + type, font)
			t.set_font_size("font_size", name + type, px)
	return t


## What a `Control` puts in `theme_type_variation` to take [param role].
static func variation_for(role: Role, type: String = "Label") -> String:
	return str(VARIATIONS[role]) + type

## Palette tokens (§13.2), defined once as a resource.
##
## Never hardcode a colour in a script or a scene — the four accessibility
## palettes of §21 are a `.tres` swap with no code change, and that only works if
## every colour is read from here.
class_name Palette
extends Resource

@export_group("Surfaces")
@export var bg_deep: Color = Color("0A0E14")
@export var bg_panel: Color = Color("121821")
@export var bg_vignette: Color = Color("060910")

@export_group("Cells")
@export var cell_empty_fill: Color = Color("131A24")
@export var cell_empty_stroke: Color = Color("263241")
@export var cell_candidate_stroke: Color = Color("3E5470")

@export_group("Path")
@export var path_core: Color = Color("34E5C4")
@export var path_gradient_far: Color = Color("7C6BFF")
@export var start_cell: Color = Color("7CF3FF")
@export var goal_cell: Color = Color("FFB43D")

@export_group("Modifiers")
@export var wall_fill: Color = Color("1A1620")
@export var wall_stroke: Color = Color("4A3A52")
@export var portal: Color = Color("B078FF")
@export var gate: Color = Color("6F8CFF")
@export var wild: Color = Color("F7F16B")

@export_group("Board 3D")
## The single key light of the C-18 board and the ambient it sits in. Tokens rather
## than literals for the same reason every other colour is: §21's palettes swap the
## `.tres`, and a light hardcoded in a script would keep the neon cast in all four.
@export var board_key_light: Color = Color("FFF6E8")
@export var board_ambient: Color = Color("2A3A55")
## Outline carried by every modifier mark (C-23). A mark is drawn on top of a tile
## whose own colour is a palette token too, so a mark and its tile can be a similar
## luminance under a greyscale or high-contrast palette — the outline is what keeps
## the glyph's silhouette readable regardless, which is the half of §21 that shape
## alone does not cover. It must invert with the surfaces in a light palette, so it
## is its own token rather than a reuse of `bg.deep`.
@export var board_mark_outline: Color = Color("070B12")

@export_group("Feedback")
@export var danger: Color = Color("FF5470")
@export var text_primary: Color = Color("EAF2FF")
@export var text_secondary: Color = Color("8FA3BF")
@export var focus: Color = Color("FFFFFF")


## Path colour at [param depth] of [param max_depth] steps from the start, so a
## long path reads as a gradient rather than a flat stroke (§13.3).
func path_at_depth(depth: int, max_depth: int) -> Color:
	if max_depth <= 0:
		return path_core
	return path_core.lerp(path_gradient_far, clampf(float(depth) / float(max_depth), 0.0, 1.0))

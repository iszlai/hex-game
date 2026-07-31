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
## §13.2's `path.glow`: `path.core` at 35%, for the additive bloom around the path
## and the §14.4 emitters. A token rather than an alpha applied at the call site,
## so a palette that wants a different glow can say so.
@export var path_glow: Color = Color("34E5C4", 0.35)
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
## The colour a tile's **side** is pulled toward, so a prism reads as an object
## standing on the board rather than as a flat fill with a dimmer edge. This is the
## 3D board's inheritance of `cell.empty.stroke`: in two dimensions a cell was told
## from its neighbour by an outline, and in three the side face *is* that outline.
## It matters more than it looks — C-22 puts a tile's kind in its height, and a
## height you cannot see the side of is a height nobody can read.
@export var board_tile_side: Color = Color("1B2331")

## Outline carried by every modifier mark (C-23). A mark is drawn on top of a tile
## whose own colour is a palette token too, so a mark and its tile can be a similar
## luminance under a greyscale or high-contrast palette — the outline is what keeps
## the glyph's silhouette readable regardless, which is the half of §21 that shape
## alone does not cover. It must invert with the surfaces in a light palette, so it
## is its own token rather than a reuse of `bg.deep`.
@export var board_mark_outline: Color = Color("070B12")

@export_group("Surfaces (C-26)")
## The illustrated direction's materials, every one a **tint** rather than a
## colour: §13.6's art files are drawn neutral and multiplied by these, which is
## the only way §21's four palettes can reach a texture at all. A texture carrying
## its own final colour would look identical in all four.
@export var surface_frame: Color = Color("2A2118")
@export var surface_panel: Color = Color("161C26")
@export var surface_ink: Color = Color("6B7A90")
## What a chapter's backdrop is multiplied by, and the dim laid over it behind a
## panel. §13.7 makes the contrast floor a property of the scrim's alpha rather
## than of whichever illustration happens to be behind it.
@export var backdrop_tint: Color = Color("FFFFFF")
@export var backdrop_scrim: Color = Color("0A0E14", 0.72)

## Whether this palette exists for a **vision requirement** rather than for taste.
##
## §21's four alternates do; `cairn_warm` and `neon_dark` are the two unconstrained
## looks. The board reads it to decide how the §6 modifiers are drawn: an assistive
## palette gets C-23's procedural silhouettes, whose whole job is to stay legible
## once colour is gone, and the others may use illustrated art that carries its own
## colour and therefore cannot be tinted (C-29).
##
## It lives on the palette rather than in a list somewhere because a palette is the
## thing that knows what it is for — a new one declares its own nature and nothing
## else has to be told about it.
@export var assistive: bool = false

@export_group("Feedback")
@export var danger: Color = Color("FF5470")
@export var text_primary: Color = Color("EAF2FF")
@export var text_secondary: Color = Color("8FA3BF")
@export var focus: Color = Color("FFFFFF")


## The palette the player is actually playing in (§21). Read through here rather
## than by loading a path, so switching palettes is a setting rather than an edit
## in twenty files — and so C-26's tints reach every texture in the game at once.
##
## Cached, because this is called from `_ready` on every screen and from the board
## every time it rebinds; the cache is dropped when the setting changes.
static var _current: Palette = null
static var _current_name: String = ""

const DIR := "res://src/data/palettes/"
const FALLBACK := "cairn_warm"


static func current() -> Palette:
	var wanted: String = str(SettingsService.get_value("palette"))
	if _current != null and wanted == _current_name:
		return _current
	var path: String = DIR + wanted + ".tres"
	if not ResourceLoader.exists(path):
		# A palette named in the settings that is not in the build — an older save,
		# a hand-edited file, or one removed between versions. §21's promise is that
		# a palette choice can never leave the player unable to see the game.
		push_warning("palette '%s' is not in this build; using %s" % [wanted, FALLBACK])
		path = DIR + FALLBACK + ".tres"
	_current = load(path)
	_current_name = wanted
	return _current


## Path colour at [param depth] of [param max_depth] steps from the start, so a
## long path reads as a gradient rather than a flat stroke (§13.3).
func path_at_depth(depth: int, max_depth: int) -> Color:
	if max_depth <= 0:
		return path_core
	return path_core.lerp(path_gradient_far, clampf(float(depth) / float(max_depth), 0.0, 1.0))

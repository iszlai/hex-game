## §13.6's art manifest: every image in the game, declared once by **role**.
##
## The rule the whole of C-26 rests on is that art is data. Nothing anywhere else
## names an image file; a screen asks for "the backdrop for chapter 3" and gets
## whatever is currently standing in that role. That is what lets C-27 be answered
## later — an illustrator replaces eight PNGs and no script changes.
##
## Each entry also names the palette token its image is **tinted** by, because
## §13.2 does not stop applying to a texture: the files are rendered neutral and
## coloured at runtime, so §21's four palettes reach the art (§13.1's second kept
## property).
class_name Art

const DIR := "res://assets/art/"

## §13.7: one backdrop per chapter plus one for the menus.
const BACKDROP_MENU := "menu"

## Tint tokens, by role. Named rather than inlined so a palette that wants its
## backdrop tinted differently from its panels can say so.
const TINT_BACKDROP := "backdrop_tint"
const TINT_FRAME := "surface_frame"
const TINT_FILL := "surface_panel"

const TILE_GRAIN := DIR + "tile_grain.png"
## C-26's drawn tile top: a 2x2 atlas of hexagon faces, ink and screentone baked
## in as values. Optional — with no file the board keeps its procedural outline.
const TILE_FACE := DIR + "tile_face.png"
const PANEL_FRAME := DIR + "panel_frame.png"
const PANEL_FILL := DIR + "panel_fill.png"
## §13.7's 9-slice inset, matching the corner `tools/make_art.gd` draws.
const PANEL_CORNER := 24


## The backdrop for a chapter, or the menu backdrop for anything that is not one.
## A missing file returns `null` rather than failing: §13.6's replaceability rule
## means art can be swapped out mid-development, and a screen with no picture
## behind it is a screen that still plays.
static func backdrop(chapter: int = 0) -> Texture2D:
	var key: String = "chapter_%d" % chapter if chapter >= 1 and chapter <= 5 else BACKDROP_MENU
	return _load(DIR + key + ".png")


## §13.6's board material. A *value* map, never tinted — the tile's colour is the
## palette's and this only says how the light falls on it.
static func tile_grain() -> Texture2D:
	return _load(TILE_GRAIN)


static func tile_face() -> Texture2D:
	return _load(TILE_FACE)


static func panel_frame() -> Texture2D:
	return _load(PANEL_FRAME)


static func panel_fill() -> Texture2D:
	return _load(PANEL_FILL)


## Whether the art set is present at all. False in a build where `make art` has
## never run, which every screen has to survive — C-27 is an open decision and the
## files it produces are placeholders by construction.
static func available() -> bool:
	return backdrop() != null


static func _load(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

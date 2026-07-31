## §13.7's painted backdrop, plus the scrim that makes its contrast floor true.
##
## The backdrop carries **no information**. A player who cannot see it at all
## loses nothing, which is the property that lets an illustration sit behind a
## puzzle without breaking §21 — and it is why the chapter is also named in words
## in the top bar rather than only implied by the picture.
##
## The scrim is the load-bearing half. §13.7 asks for 4.5:1 contrast against the
## brightest pixel the text covers, and the honest way to get that is not to hope
## for a dark illustration: it is to lay a known opacity of a known colour over an
## unknown picture, so the floor is a property of the scrim and can be reasoned
## about without looking at the art.
class_name Backdrop
extends TextureRect


## Builds the backdrop and inserts it *behind* everything already in [param root].
## One call per screen, in `_ready`, so no scene file has to know art exists —
## which is the same reason §13.6 keeps the manifest out of the scenes.
static func install(root: Control, chapter: int = 0) -> Backdrop:
	var texture: Texture2D = Art.backdrop(chapter)
	if texture == null:
		# No art in this build (C-27 is open, and `make art` may never have run).
		# The screen keeps its own background colour and plays exactly as before.
		return null
	var node := Backdrop.new()
	node.name = "Backdrop"
	node.texture = texture
	node.bind(Palette.current())
	root.add_child(node)
	root.move_child(node, 0)
	return node


func _init() -> void:
	# Covers the window whatever its aspect: 1920×1200 is 1280×800 with room to
	# crop, so a wider window shows more sky rather than a stretched horizon.
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Applies §13.2's tint and lays the scrim. Both come from the palette, so §21's
## swaps reach the picture — a backdrop that carried its own final colour would
## look identical in all four palettes, which is exactly what §13.1 forbids.
func bind(palette: Palette) -> void:
	modulate = palette.backdrop_tint
	var scrim: ColorRect = get_node_or_null("Scrim") as ColorRect
	if scrim == null:
		scrim = ColorRect.new()
		scrim.name = "Scrim"
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(scrim)
		scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = palette.backdrop_scrim

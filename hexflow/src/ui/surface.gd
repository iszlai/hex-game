## §13.7's surfaces, as `StyleBox`es: the one place a panel, a bar or a row learns
## what it is made of.
##
## C-26 made the interface material rather than flat, and the failure mode of that
## is twenty screens each inventing their own texture, margin and tint. There is
## one builder here per §13.7 role, so a change to how a surface reads is a change
## in this file — and so is the fallback, which matters more than it sounds: C-27
## is open, `make art` may never have run in a given checkout, and every one of
## these has to return something usable when there is no texture at all.
class_name Surface

## The 9-slice inset, matching the corner `tools/make_art.gd` draws.
const CORNER := Art.PANEL_CORNER


## A bar, rail or panel: the timber a screen is built from (§13.7's "frame carries
## the material"), tinted by `surface_frame`.
static func panel(palette: Palette) -> StyleBox:
	return _textured(Art.panel_frame(), palette.surface_frame, palette.bg_panel, 0.0)


## A row inside one: the reading surface, tinted by `surface_panel`. [param accent]
## draws the focus ring §12.5 asks for; pass a null colour for none.
static func row(palette: Palette, focused: bool = false, lit: bool = false) -> StyleBox:
	var tint: Color = palette.surface_panel
	if lit:
		# A hovered or pressed row lifts toward the frame's own colour, so the two
		# materials stay related rather than becoming two unrelated greys.
		tint = tint.lerp(palette.surface_frame, 0.45)
	var box: StyleBox = _textured(Art.panel_fill(), tint, palette.cell_empty_fill, 14.0)
	if box is StyleBoxTexture and focused:
		# A `StyleBoxTexture` has no border of its own, so §12.5's 3 px ring is the
		# texture's own margin doing double duty — the ring is drawn by the row
		# beneath it in `MenuList`, which is where focus is already known.
		(box as StyleBoxTexture).modulate_color = tint.lightened(0.18)
	return box


## Gives every panel on a screen the material, in one call.
##
## In this game a `PanelContainer` **is** a panel — a bar, a rail, a card or a
## modal — so walking for them is not magic, it is the type doing what it says.
## The alternative is each screen listing its own bars by unique name, which is
## four lines per screen that exist only to be forgotten on the fifth: the level
## screen had the treatment and the other five did not, and the seam between a
## timber top bar and a default-grey card is exactly what makes a game read as
## several games.
##
## Anything that has already been styled by hand keeps what it was given: a screen
## with an opinion about one of its panels states it *after* this call.
static func apply_to(root: Node, palette: Palette) -> void:
	for node: Node in _panels(root):
		(node as PanelContainer).add_theme_stylebox_override("panel", panel(palette))


static func _panels(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in root.get_children():
		if child is PanelContainer:
			out.append(child)
		out.append_array(_panels(child))
	return out


## The fallback, and the shape every builder above returns when the art is absent:
## a flat box in the same tokens. §13.6's replaceability rule cuts both ways — art
## can be swapped in, and it can be missing.
static func flat(fill: Color, border: Color, width: int, margin: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_border_width_all(width)
	box.border_color = border
	box.set_corner_radius_all(6)
	box.content_margin_left = margin + 6.0
	box.content_margin_right = margin + 6.0
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box


static func _textured(
	texture: Texture2D, tint: Color, fallback: Color, margin: float
) -> StyleBox:
	if texture == null:
		return flat(fallback, tint, 1, margin)
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.set_texture_margin_all(CORNER)
	# The middle stretches and the edges hold their size, which is what makes one
	# 96 px image serve a 44 px row and a 688 px rail.
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	# §13.2's whole point: the image is neutral and the token colours it, so §21's
	# palettes reach the texture instead of stopping at the text on top of it.
	box.modulate_color = tint
	box.content_margin_left = margin + 6.0
	box.content_margin_right = margin + 6.0
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box

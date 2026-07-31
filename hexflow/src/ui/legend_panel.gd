## The cell-state legend, toggled by Tab / Select (§11.3).
##
## Its real job is §21 and constraint C5: every visible state must be readable
## **without colour**, so each row names the glyph *and* the shape cue the board
## actually draws. If a row here cannot describe a shape, that state is a C5 bug
## in [BoardView], not a gap in this panel.
##
## It also carries the bindings that no rail button shows — moving, cycling and
## placing. Those lived in the rail as a block of hint text until the tile stack
## needed the room; the legend is where a player already looks to ask "what is
## this and what do I press", and §12.3's rail has no such block.
##
## Rows are built in code so the scene file carries no player-visible literal —
## the §22 gate turns that check on at M10 and this panel should not be what
## fails it.
class_name LegendPanel
extends PanelContainer

## `[icon, name, colour-independent cue, palette token]`. The palette token is the
## *colour* channel only; the icon and the cue are what carry the meaning.
##
## The first column is an [Icon] — §13.5's vector paths — and not a character.
## It used to be `⬢ ⬡ ◍ ⌸ ▨ ⌾`, and **none of those is in any face this project
## vendors**, so the entire panel drew as empty boxes and nothing failed. Which is
## the argument for the icons in the first place: a drawing does not depend on
## whether a type designer thought a hexagon was worth including.
##
## Path, Target and Cursor share the hexagon, because what tells them apart on the
## board is fill and stroke weight rather than shape — so the cue column says so,
## and that is the channel §21 asks for.
const ROWS := [
	[Icon.Kind.GOAL, "Goal", "inner ring + target glyph", "goal_cell"],
	[Icon.Kind.WALL, "Wall", "45° hatching, never enterable", "wall_stroke"],
	[Icon.Kind.GATE, "Gate", "single ring; needs two path neighbours", "gate"],
	[Icon.Kind.PORTAL, "Portal", "two concentric rings, dashed tether to its twin", "portal"],
	[Icon.Kind.WILD, "Wild", "star glyph; grants a charge when entered", "wild"],
	[Icon.Kind.HEXAGON, "Path", "filled, gradient deepening from the start", "path_core"],
	[Icon.Kind.HEXAGON, "Target", "heavier stroke — a legal move for this tile",
		"cell_candidate_stroke"],
	[Icon.Kind.HEXAGON, "Cursor", "outline standing outside the cell", "focus"],
]

## `[name, action]`, or `[name, modifier, action]` for a chord. The glyph column
## is filled from [InputGlyphs], so a rebind or a different controller family
## changes what is shown here without touching this table (§11.4).
const CONTROLS := [
	["Move", "board_move_up"],
	["Cycle", "board_cycle_prev", "board_cycle_next"],
	["Place", "board_confirm"],
	["Wild", "board_wild_modifier", "board_confirm"],
	# C-18 gave the board six 60° stops and M4 bound the two actions that turn it,
	# and nothing in the game has ever said so. A control the player cannot discover
	# is a control that does not exist for them — and turning the board is how you
	# see behind a tall wall, so it is not a garnish.
	["Turn board", "board_rotate_ccw", "board_rotate_cw"],
]

@export var palette: Palette = null

var _rows: VBoxContainer = null


func _ready() -> void:
	if palette == null:
		palette = Palette.current()
	visible = false
	_build()


func toggle() -> void:
	visible = not visible


func _build() -> void:
	# §13.7: the legend is a panel like every other, made of the same timber.
	add_theme_stylebox_override("panel", Surface.panel(palette))
	if _rows != null:
		return
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	margin.add_child(_rows)

	var title := Label.new()
	title.text = "LEGEND"
	title.add_theme_color_override("font_color", palette.text_secondary)
	_rows.add_child(title)

	for entry: Variant in ROWS:
		var row: Array = entry
		_rows.add_child(_row(row))

	_rows.add_child(HSeparator.new())
	var controls := Label.new()
	controls.text = "CONTROLS"
	controls.add_theme_color_override("font_color", palette.text_secondary)
	_rows.add_child(controls)
	for entry: Variant in CONTROLS:
		var row: Array = entry
		_rows.add_child(_control_row(str(row[0]), row.slice(1)))


func _row(row: Array) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)

	var glyph := Icon.new()
	glyph.kind = row[0] as Icon.Kind
	glyph.colour = _colour(str(row[3]))
	glyph.custom_minimum_size = Vector2(28.0, Icon.GRID)
	box.add_child(glyph)

	var name_label := Label.new()
	name_label.text = str(row[1])
	name_label.custom_minimum_size = Vector2(76.0, 0.0)
	name_label.add_theme_color_override("font_color", palette.text_primary)
	box.add_child(name_label)

	var cue := Label.new()
	cue.text = str(row[2])
	cue.add_theme_color_override("font_color", palette.text_secondary)
	box.add_child(cue)
	return box


## A CONTROLS row: the same three columns as a legend row, but the cue is built out
## of [GlyphHint]s rather than out of a joined string.
##
## The join is why this cannot be one hint with a longer label — §11.3's wild
## modifier is `L2` *and* `A`, two buttons, and two buttons are two pictures with a
## `+` between them. The first column is an empty spacer rather than a glyph:
## a control has no board mark to show, and the names still have to line up with the
## modifier rows above.
func _control_row(name: String, actions: Array) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(28.0, 0.0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

	var name_label := Label.new()
	name_label.text = name
	name_label.custom_minimum_size = Vector2(76.0, 0.0)
	name_label.add_theme_color_override("font_color", palette.text_primary)
	box.add_child(name_label)

	for i: int in range(actions.size()):
		if i > 0:
			var plus := Label.new()
			plus.text = "+"
			plus.add_theme_color_override("font_color", palette.text_secondary)
			box.add_child(plus)
		var hint := GlyphHint.new()
		hint.palette = palette
		box.add_child(hint)
		hint.show_action(str(actions[i]))
	return box


func _colour(token: String) -> Color:
	var value: Variant = palette.get(token)
	return value as Color if value is Color else palette.text_primary

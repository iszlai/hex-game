## @core — the legend (§21, C5, and the bindings §12.3's rail has no room for).
##
## Two claims, and neither is about how it looks.
##
## **C5**: every visible board state must be readable without colour, so every row
## has to name a glyph *and* a shape cue. A row that describes only a colour is a
## row that fails a greyscale player, and the panel is where that promise is
## written down — so it is where it is checked.
##
## **§11.4**: the CONTROLS block is the only place moving, cycling and placing are
## explained. It builds its cues from [GlyphHint], which means a player on a pad
## sees their own buttons — and it means a broken build shows an *empty* legend
## rather than a crash, which nothing would catch, because the panel is hidden
## until Tab is pressed and no screenshot of the board contains it.
extends GutTest

var _panel: LegendPanel = null


func before_each() -> void:
	_panel = LegendPanel.new()
	add_child_autofree(_panel)
	_panel.toggle()


## Every hint the CONTROLS block puts on screen says something. Built rather than
## inspected as a table: the rows are constructed in code, and it is the
## construction that broke when the cue stopped being a string.
func test_every_control_row_explains_itself() -> void:
	var hints: Array[GlyphHint] = _hints_in(_panel)
	assert_gt(hints.size(), 0, "the CONTROLS block built no hints at all")
	for hint: GlyphHint in hints:
		assert_ne(hint.reads_as(), "",
			"a control is listed with nothing said about how to press it")


## One hint per action named in the table, chords included — §11.3's wild modifier
## is two buttons and has to show as two.
func test_there_is_a_hint_for_every_action_named() -> void:
	var wanted: int = 0
	for entry: Variant in LegendPanel.CONTROLS:
		wanted += (entry as Array).size() - 1
	assert_eq(_hints_in(_panel).size(), wanted,
		"the legend shows a different number of buttons than CONTROLS names")


## C5: colour is never the only channel, so a row that cannot describe a shape is a
## bug in the board rather than a gap here.
func test_every_state_is_described_without_colour() -> void:
	for entry: Variant in LegendPanel.ROWS:
		var row: Array = entry
		assert_ne(str(row[0]), "", "%s has no glyph" % row[1])
		assert_ne(str(row[2]), "", "%s is described by colour alone (C5, §21)" % row[1])


func _hints_in(node: Node) -> Array[GlyphHint]:
	var out: Array[GlyphHint] = []
	for child: Node in node.get_children():
		if child is GlyphHint:
			out.append(child)
		out.append_array(_hints_in(child))
	return out

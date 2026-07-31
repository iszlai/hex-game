## @core — the control that answers "which button is this?" (§11.4).
##
## The interesting claim is not that an icon appears — CI has no controller, so it
## cannot. It is the opposite one: **the hint is never blank.** §11.4's glyph set is
## an improvement layered over a text answer that already worked, and the failure
## worth guarding against is a rail that shows nothing at all because a PNG is
## missing, a pad is unplugged, or a family has no file. That failure is invisible
## in a screenshot taken on a machine where everything is present.
##
## So what is asserted is the floor: for every action the rail and the legend put on
## screen, something readable comes out, and it is the same word `label_for` gives —
## one source of truth, so a rebind cannot disagree with the HUD.
extends GutTest

var _hint: GlyphHint = null


func before_each() -> void:
	_hint = GlyphHint.new()
	add_child_autofree(_hint)


## Every action §12.3's rail and the legend's CONTROLS block name.
func _actions_on_screen() -> Array[String]:
	var out: Array[String] = [
		"board_undo", "board_discard", "board_wild_modifier", "board_hint",
	]
	for entry: Variant in LegendPanel.CONTROLS:
		var row: Array = entry
		for i: int in range(1, row.size()):
			if not out.has(str(row[i])):
				out.append(str(row[i]))
	return out


func test_no_action_the_hud_shows_ever_reads_as_nothing() -> void:
	for action: String in _actions_on_screen():
		_hint.show_action(action)
		assert_ne(_hint.reads_as(), "",
			"%s is on screen and the player is told nothing about it" % action)


## With no pad attached the hint is the key name, taken from the binding table
## rather than from a second copy of it.
func test_without_a_controller_it_reads_the_binding_table() -> void:
	assert_eq(InputGlyphs.family(), "", "CI has no controller attached")
	for action: String in _actions_on_screen():
		_hint.show_action(action)
		assert_false(_hint.showing_icon(), "%s has no pad to take an icon from" % action)
		assert_eq(_hint.reads_as(), InputGlyphs.label_for(action),
			"%s: the hint and the label disagree" % action)


## §11.3 draws a real distinction between "R" and "hold R", and a picture of a
## button cannot carry it — so the word survives whichever form is shown.
func test_a_hold_action_still_says_hold() -> void:
	_hint.show_action("board_hint")
	assert_string_contains(_hint.reads_as(), "hold")
	_hint.show_action("board_restart")
	assert_string_contains(_hint.reads_as(), "hold")


## An action with no binding at all draws nothing rather than an empty box.
func test_an_unbound_action_draws_nothing() -> void:
	_hint.show_action("board_teleport")
	assert_eq(_hint.reads_as(), "")
	assert_false(_hint.showing_icon())


## C4: the nodes are built once. A HUD refresh runs on every move and must rewrite
## properties rather than allocate.
func test_showing_a_new_action_builds_no_nodes() -> void:
	_hint.show_action("board_undo")
	var count: int = _hint.get_child_count()
	for action: String in _actions_on_screen():
		_hint.show_action(action)
	assert_eq(_hint.get_child_count(), count, "the hint reuses its own nodes")

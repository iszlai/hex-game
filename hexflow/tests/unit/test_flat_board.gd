## @core — §21's escape hatch from the lit board (C-18, C-24).
##
## C-18 lit the board and, in the same breath, flagged what that costs: §21 wants
## every state readable on a greyscale or high-contrast palette, and a lit surface
## is its palette colour times whatever the key light and the shadows are doing to
## it. `flat_board` takes the light out of the loop, so a tile on screen is its
## palette colour and nothing else.
##
## What CI can check is that the switch reaches everything that draws the board,
## follows a live change rather than waiting for the next level, and is off by
## default. What it cannot check is the picture — that is a greyscale capture, and
## the one thing this *cannot* do is hide C-22's heights, which is why the flat
## path still steps the side faces down.
extends GutTest

const PLAY := Vector2(880.0, 688.0)

var _view: BoardView3D = null
var _stack: TileStack = null


func before_each() -> void:
	_view = BoardView3D.new()
	add_child_autofree(_view)
	_view.bind(GameState.start(Fixtures.fixed_level(Fixtures.shortest_route_tiles())), PLAY)
	_stack = TileStack.new()
	add_child_autofree(_stack)
	_stack.show_tiles([0] as Array[int])


func after_each() -> void:
	SettingsService.set_value("flat_board", false)


func _flag_on(node: GeometryInstance3D) -> Variant:
	return (node.material_override as ShaderMaterial).get_shader_parameter("flat_board")


func _key_light() -> DirectionalLight3D:
	return _view.viewport.get_node("KeyLight")


## Off by default: the lighting is what gives C-22's tile heights something to
## cast, so the board ships lit and a player opts out.
func test_the_board_is_lit_until_asked_otherwise() -> void:
	assert_false(SettingsService.flat_board(), "default")
	assert_false(bool(_flag_on(_view.tiles)), "tiles take light")
	assert_false(bool(_flag_on(_view.links)), "and so does the ribbon")
	assert_true(_key_light().shadow_enabled, "and the key light casts")


## Everything that draws a board surface, or the setting is a half-measure: a lit
## ribbon lying on an unlit tile would be worse than either.
func test_it_reaches_every_surface_of_the_board() -> void:
	_view.set_flat(true)
	assert_true(bool(_flag_on(_view.tiles)), "tiles")
	assert_true(bool(_flag_on(_view.links)), "connectors and tethers")
	assert_false(_key_light().shadow_enabled,
		"a shadow pass over a board that takes no light renders nothing (§20)")

	_view.set_flat(false)
	assert_false(bool(_flag_on(_view.tiles)), "and back again")
	assert_true(_key_light().shadow_enabled)


## The rail's pieces are the board's tiles seen up close, so they cannot still be
## catching a highlight once the board has stopped.
func test_the_rail_follows_the_board() -> void:
	SettingsService.set_value("flat_board", true)
	assert_true(bool(_flag_on(_stack.pieces)), "the stack's pieces went flat too")


## Live, not on the next level load. A player turning this on is usually turning
## it on *because* they cannot read the board in front of them.
func test_a_live_change_reaches_a_board_already_on_screen() -> void:
	assert_false(bool(_flag_on(_view.tiles)), "lit to begin with")
	SettingsService.set_value("flat_board", true)
	assert_true(bool(_flag_on(_view.tiles)), "flat without rebinding the level")
	assert_true(bool(_flag_on(_view.links)))
	SettingsService.set_value("flat_board", false)
	assert_false(bool(_flag_on(_view.tiles)), "and back, still without a reload")


## A board bound while the setting is already on must come up flat — otherwise the
## next level silently undoes the player's choice.
func test_a_level_opened_flat_stays_flat() -> void:
	SettingsService.set_value("flat_board", true)
	var view := BoardView3D.new()
	add_child_autofree(view)
	view.bind(GameState.start(Fixtures.fixed_level(Fixtures.shortest_route_tiles())), PLAY)
	assert_true(bool(_flag_on(view.tiles)), "bound flat")
	assert_true(bool(_flag_on(view.links)))

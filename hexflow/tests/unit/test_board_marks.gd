## @core — the §6 modifiers as marks on the C-18 board (C-23).
##
## This exists for C5. [BoardTiles] spent height on a tile's *kind* (C-22), and a
## modifier is a mark on a tile rather than a kind of tile, so the four modifiers
## need a channel of their own: a distinct silhouette each. What CI can check is
## that every modifier gets exactly one mark, that the four are told apart by
## something that is not their colour, and that a mark stays on its own tile as
## the board turns and as the tile under it stands up. What CI cannot check is the
## shape the shader draws — that is a screenshot. What it *can* check is the quad
## that shape is drawn on, which is the half of "legible at every stop" that the
## billboarding is responsible for.
extends GutTest

const PLAY := Vector2(880.0, 688.0)

## Cells of [method Fixtures.modifier_level]. Named rather than indexed, because a
## test that says "mark 3" stops meaning anything the moment the fixture changes.
const GOAL_A := Fixtures.GOAL
const GOAL_B := Vector3i(0, 3, -3)
const PORTAL_A := Vector3i(0, 2, -2)
const PORTAL_B := Vector3i(0, -2, 2)
const GATE := Vector3i(2, 1, -3)
const WILD := Vector3i(-2, 1, 1)

var _view: BoardView3D = null
var _marks: BoardMarks = null
var _tiles: BoardTiles = null
var _state: GameState = null
var _layout: HexLayout = null
var _palette: Palette = null


## Through the real view rather than a hand-assembled pair of nodes: the marks have
## to be told where the tiles' tops are, and that wiring is part of what is under
## test here.
func before_each() -> void:
	SettingsService.set_value("reduce_motion", true)   # six real tweens, quickly
	_palette = Palette.current()
	_state = GameState.start(Fixtures.modifier_level())
	_view = BoardView3D.new()
	add_child_autofree(_view)
	_view.bind(_state, PLAY)
	_marks = _view.marks
	_tiles = _view.tiles
	_layout = _view.layout


func after_each() -> void:
	SettingsService.set_value("reduce_motion", false)


## Read through the view's own accessors, never through the multimesh: instance
## data goes into the rendering server and the headless dummy renderer hands it
## back as an identity transform, so the arithmetic is what CI can assert.
func _index_of(cell: Vector3i, mark: BoardMarks.Mark) -> int:
	for i: int in range(_marks.count()):
		if _marks.cell_of(i) == cell and _marks.mark_of(i) == mark:
			return i
	return -1


func _origin_of(cell: Vector3i, mark: BoardMarks.Mark) -> Vector3:
	return _marks.transform_of(_index_of(cell, mark)).origin


func _radius_of(cell: Vector3i, mark: BoardMarks.Mark) -> float:
	return _marks.transform_of(_index_of(cell, mark)).basis.get_scale().x


## The two on-board neighbours of [param cell], which is what a gate needs before
## §6 lets it be entered. Taken from the board rather than written down, so the
## test does not silently start asserting about cells off the rim.
func _two_neighbours_of(cell: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for dir: int in Direction.ALL:
		var n: Vector3i = cell + Direction.delta(dir)
		if _state.board.has(n) and out.size() < 2:
			out.append(n)
	return out


## The C5 gap this closes: before it, all four of these drew as nothing at all.
func test_every_modifier_on_the_board_gets_exactly_one_mark() -> void:
	var want: Array = [
		[GOAL_A, BoardMarks.Mark.GOAL],
		[GOAL_B, BoardMarks.Mark.GOAL],
		[PORTAL_A, BoardMarks.Mark.PORTAL],
		[PORTAL_B, BoardMarks.Mark.PORTAL],
		[GATE, BoardMarks.Mark.GATE],
		[WILD, BoardMarks.Mark.WILD],
	]
	assert_eq(_marks.count(), want.size(), "one mark per modifier and no others")
	for pair: Variant in want:
		assert_ne(_index_of((pair as Array)[0], (pair as Array)[1]), -1,
			"%v has no mark of kind %d" % [(pair as Array)[0], int((pair as Array)[1])])
	assert_eq(_marks.multimesh.instance_count, want.size(), "one draw call covers them all")
	assert_eq(_marks.get_child_count(), 0, "nothing per mark in the scene tree")


## C4, and the reason this is a multimesh rather than a [Label3D] per marked cell.
func test_nothing_runs_per_frame() -> void:
	assert_false(_marks.has_method("_process"), "no _process")
	assert_false(_marks.has_method("_draw"), "no _draw")


## §21: the four modifiers must be told apart by something that survives a
## greyscale palette. The silhouette is that something, and the id is what selects
## it — so the ids have to be injective before the shapes can be.
func test_the_four_modifiers_carry_four_different_silhouettes() -> void:
	var seen: Dictionary = {}
	for pair: Variant in [[GOAL_A, BoardMarks.Mark.GOAL], [PORTAL_A, BoardMarks.Mark.PORTAL],
			[GATE, BoardMarks.Mark.GATE], [WILD, BoardMarks.Mark.WILD]]:
		var id: float = _marks.custom_of(_index_of((pair as Array)[0], (pair as Array)[1])).r
		assert_false(seen.has(id), "silhouette %d is used twice" % int(id))
		seen[id] = true
	assert_eq(seen.size(), 4)


func test_colour_is_the_third_channel_not_the_only_one() -> void:
	assert_eq(_marks.tint_of(_index_of(GOAL_A, BoardMarks.Mark.GOAL)), _palette.goal_cell)
	assert_eq(_marks.tint_of(_index_of(PORTAL_A, BoardMarks.Mark.PORTAL)), _palette.portal)
	assert_eq(_marks.tint_of(_index_of(GATE, BoardMarks.Mark.GATE)), _palette.gate)
	assert_eq(_marks.tint_of(_index_of(WILD, BoardMarks.Mark.WILD)), _palette.wild)


## A mark labels one cell, so it stands over that cell's centre and fits inside its
## top face. Too big and it would overhang its neighbour, which at 55° is exactly
## how a mark ends up looking like it belongs to the tile in front of it.
func test_a_mark_stands_on_the_tile_it_labels() -> void:
	# The tile top is TILE_INSET wide and the projection foreshortens its depth to
	# sin 55°; a mark has to clear the tighter of the two.
	var tightest: float = _layout.size * BoardTiles.TILE_INSET \
		* sin(deg_to_rad(BoardCamera.ELEVATION_DEGREES))
	for i: int in range(_marks.count()):
		var cell: Vector3i = _marks.cell_of(i)
		var t: Transform3D = _marks.transform_of(i)
		var want: Vector3 = _layout.to_plane(cell)
		assert_almost_eq(t.origin.x, want.x, 0.01, "%v x" % cell)
		assert_almost_eq(t.origin.z, want.z, 0.01, "%v z" % cell)
		assert_gte(t.origin.y, _tiles.top_of(cell), "%v sits on top of its tile" % cell)
		assert_lt(t.basis.get_scale().x, tightest, "%v's mark must fit on its own tile" % cell)


## The mark follows its tile up. A goal cell is a thin plate until the path reaches
## it and a raised tile afterwards (C-22), so a mark pinned to the plane would sink
## into its own tile the moment the cell it labels was joined.
func test_a_mark_rises_with_the_tile_under_it() -> void:
	var before: float = _origin_of(PORTAL_B, BoardMarks.Mark.PORTAL).y
	assert_almost_eq(before, _layout.size * (BoardTiles.EMPTY_TOP + BoardMarks.LIFT), 0.01,
		"an unjoined cell's mark sits on an empty tile's top")

	_state.path[PORTAL_B] = true      # as a placement would leave it
	_view.rebuild()
	assert_gt(_origin_of(PORTAL_B, BoardMarks.Mark.PORTAL).y, before, "and rises with it")
	for i: int in range(_marks.count()):
		assert_gte(_marks.transform_of(i).origin.y, _tiles.top_of(_marks.cell_of(i)),
			"%v's mark is inside its tile" % _marks.cell_of(i))


## §6: the lock opens the moment the gate's condition becomes satisfiable. That is
## run state rather than topology, so it has to move in both directions — a gate
## that opened must be able to shut again on undo.
func test_the_gate_opens_when_it_becomes_enterable() -> void:
	var at: int = _index_of(GATE, BoardMarks.Mark.GATE)
	assert_almost_eq(_marks.custom_of(at).g, 0.0, 0.001, "shut with nothing around it")

	# Two path neighbours is exactly Rules.gate_satisfied's condition (§6).
	var around: Array[Vector3i] = _two_neighbours_of(GATE)
	assert_eq(around.size(), 2, "fixture sanity: the gate has two neighbours on the board")
	for n: Vector3i in around:
		_state.path[n] = true
	_view.rebuild()
	assert_true(Rules.gate_satisfied(_state.board, _state.path, GATE), "fixture sanity")
	assert_almost_eq(_marks.custom_of(at).g, 1.0, 0.001, "open once it is enterable")

	_state.path.erase(around[0])
	_view.rebuild()
	assert_almost_eq(_marks.custom_of(at).g, 0.0, 0.001, "and shut again when it is not")


## Only a gate is ever drawn open: [method Rules.gate_satisfied] answers `true` for
## every cell that is *not* a gate, so reading it unguarded would fling every other
## mark open too.
func test_no_other_mark_is_ever_drawn_open() -> void:
	for i: int in range(_marks.count()):
		if _marks.mark_of(i) == BoardMarks.Mark.GATE:
			continue
		assert_almost_eq(_marks.custom_of(i).g, 0.0, 0.001,
			"%v is not a gate" % _marks.cell_of(i))


## §5.1's flags are a bitmask, so one cell can legally carry two modifiers. They
## must not then draw on top of each other — the grey-box nested its rings, and
## this nests the marks the same way.
func test_two_modifiers_on_one_cell_nest_instead_of_overlapping() -> void:
	var board := Board.build(3, Fixtures.START, Fixtures.cells([Fixtures.GOAL]),
		[] as Array[Vector3i], [], Fixtures.cells([Fixtures.GOAL]))
	var both := BoardMarks.marks_on(board)
	assert_eq(both.size(), 2, "a cell that is both a goal and a gate has two marks")
	assert_eq(both[0][0] as Vector3i, Fixtures.GOAL)
	assert_eq(int(both[0][1]), int(BoardMarks.Mark.GOAL), "drawn in a fixed order")
	assert_eq(int(both[1][1]), int(BoardMarks.Mark.GATE))
	assert_eq(int(both[0][2]), 0)
	assert_eq(int(both[1][2]), 1, "and the second one is drawn inside the first")
	assert_lt(BoardMarks.STACK_SHRINK, 1.0, "which is what makes it visible at all")


## The claim the milestone item is really about: a mark is *equally* legible at all
## six 60° stops. The shader rebuilds the quad around the camera's basis every
## frame, so what has to hold is that this basis gives a screen-aligned square of a
## constant size at every yaw. The three projections below are that vertex shader,
## written in GDScript; if they stop agreeing with `hex_mark.gdshader` the glyph
## starts leaning as the board turns.
func test_a_mark_is_the_same_upright_square_at_every_yaw() -> void:
	var at: int = _index_of(WILD, BoardMarks.Mark.WILD)
	var centre: Vector3 = _marks.transform_of(at).origin
	var radius: float = _radius_of(WILD, BoardMarks.Mark.WILD)
	var first_width := 0.0

	# Every stop, and the yaws halfway between them, because C-21's tween spends
	# most of its 260 ms nowhere near a stop.
	for i: int in range(BoardCamera.YAW_STOPS * 2 + 1):
		var yaw: float = BoardCamera.YAW_STOP_RADIANS * float(i) * 0.5
		var basis := BoardCamera.basis_at(yaw)
		var middle: Vector2 = _view.camera.unproject_at(centre, yaw)
		var right: Vector2 = _view.camera.unproject_at(centre + basis.x * radius, yaw)
		var up: Vector2 = _view.camera.unproject_at(centre + basis.y * radius, yaw)

		assert_almost_eq((right - middle).y, 0.0, 0.01,
			"the glyph's own x axis must be flat on screen at yaw %.2f" % yaw)
		assert_almost_eq((up - middle).x, 0.0, 0.01,
			"and its y axis straight up at yaw %.2f" % yaw)
		var width: float = (right - middle).length()
		assert_almost_eq(width, (up - middle).length(), 0.01,
			"square, never foreshortened, at yaw %.2f" % yaw)
		if i == 0:
			first_width = width
			assert_gt(first_width, 20.0, "and big enough to read at §4.4's fit")
		assert_almost_eq(width, first_width, 0.01,
			"and the same size as at every other yaw (%.2f)" % yaw)


## A mark tracks its own cell across a rotation. The camera orbits the board centre
## and the projection is orthographic, so a mark's screen position is its tile's
## screen position at every stop — the lift that keeps it clear of the tile top
## moves it up the screen, never sideways off its cell.
func test_a_mark_stays_over_its_own_cell_through_a_rotation() -> void:
	for stop: int in range(BoardCamera.YAW_STOPS):
		for i: int in range(_marks.count()):
			var cell: Vector3i = _marks.cell_of(i)
			var on_screen: Vector2 = _view.camera.unproject_at(
				_marks.transform_of(i).origin, _view.camera.yaw_radians())
			assert_almost_eq(on_screen.x, _view.centre_of(cell).x, 0.5,
				"%v's mark drifted off its cell at stop %d" % [cell, stop])
			assert_lt(on_screen.y, _view.centre_of(cell).y,
				"%v's mark stands above the plane, not on it" % cell)
		_view.rotate_by(1)
		assert_true(await wait_for_signal(_view.camera.yaw_settled, 1.0), "stop %d" % stop)


func test_the_quad_is_a_unit_square_with_bounds_the_shader_cannot_outgrow() -> void:
	var mesh := BoardMarks.build_quad_mesh()
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), 6, "two triangles")
	for v: Vector3 in verts:
		assert_almost_eq(absf(v.x), 1.0, 0.001)
		assert_almost_eq(absf(v.y), 1.0, 0.001)
		assert_almost_eq(v.z, 0.0, 0.001, "flat: the vertex shader orients it")
	# The shader moves the corners out of the quad's own plane, so the bounds have
	# to cover a sphere rather than a plate: bounds that do not contain what is
	# drawn are a culling bug waiting for a mark to sit near the edge of the play
	# area.
	var aabb: AABB = mesh.custom_aabb
	assert_true(aabb.has_point(Vector3(0.0, 0.0, 1.0)), "bounds must cover the depth axis")
	assert_true(aabb.has_point(Vector3(0.0, 0.0, -1.0)))


## C-29: two complete presentations of the same four modifiers, and the drawn-in-
## code silhouette is the **floor**.
##
## The illustrated set carries its own colour, so it cannot be tinted — which is
## precisely why an assistive palette may not have it. §21's four alternates exist
## so a player who cannot separate two hues gets a board that does not ask them to,
## and art that looked identical in all four would quietly undo that.
##
## Asserted rather than trusted because the failure is invisible: with no art file
## on disk the board looks correct under every palette, and the bug only appears the
## day someone drops one in.
func test_an_assistive_palette_never_takes_the_illustrated_marks() -> void:
	for name: String in ["deuter", "protan", "tritan", "high_contrast"]:
		var palette: Palette = load("res://src/data/palettes/%s.tres" % name)
		assert_true(palette.assistive,
			"%s exists for a vision requirement and has to say so" % name)

		var marks := BoardMarks.new()
		marks.palette = palette
		add_child_autofree(marks)
		marks.bind(_state, _layout, _tiles)
		assert_false(marks.illustrated(),
			"%s must keep C-23's silhouettes, whatever art is on disk" % name)


## And the two unconstrained looks are free to take it — they are a matter of taste,
## not of vision, so nothing is lost by illustrating them.
func test_the_unconstrained_palettes_are_allowed_the_art() -> void:
	for name: String in ["cairn_warm", "neon_dark"]:
		var palette: Palette = load("res://src/data/palettes/%s.tres" % name)
		assert_false(palette.assistive, "%s is a look, not an accommodation" % name)


## With no file there is nothing to choose, and the board draws what it always drew.
## The art is an improvement layered over something that already works, so its
## absence has to be silent rather than a hole.
func test_the_marks_draw_whether_or_not_the_art_is_there() -> void:
	var marks := BoardMarks.new()
	marks.palette = load("res://src/data/palettes/cairn_warm.tres")
	add_child_autofree(marks)
	marks.bind(_state, _layout, _tiles)
	assert_eq(marks.illustrated(), ResourceLoader.exists(BoardMarks.ART),
		"the illustrated set is used exactly when there is one")
	assert_gt(marks.multimesh.instance_count, 0, "and the marks draw either way")

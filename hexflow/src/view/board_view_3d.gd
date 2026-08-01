## The C-18 board's screen surface: cube ↔ screen through the orthographic camera.
##
## A `SubViewportContainer`, so the 3D board occupies exactly §12.3's play area and
## the sub-viewport's coordinates **are** the coordinates the level screen already
## works in — the same space [method BoardView.centres] answers in and the same
## space its pointer conversion lands in. That is what lets the M7 view drop in
## without [InputRouter] or the level screen learning anything new: they keep
## receiving screen-space positions and simply follow the camera (C-18).
##
## Two directions, deliberately asked of two different yaws:
##
## - **A pointer** is resolved against the *live* camera, so a click lands on the
##   cell that is under the finger at that instant, even mid-rotation.
## - **Directional input** works from the stop the player is *heading to*, so a
##   press during the 260 ms tween behaves like the board they are about to see.
##
## Both are the best available answer, and both are computed once per event — never
## per frame (C4).
##
## What it holds: the camera, the layout, the screen-space mapping, and three
## multimeshes — [BoardTiles] for the cells, [BoardLinks] for the path laid over
## them and [BoardMarks] for the §6 modifiers standing on them.
class_name BoardView3D
extends SubViewportContainer

## §14.1's dead board: 70% saturation, not zero. It is a recoverable state, and a
## board drained to grey would read as a finished one.
const DEAD_SATURATION := 0.7

## The bloom around the path (§13.1's "line of light"). Chosen numbers, like
## C-21's camera angles: §14 tabulates timings and §13 tabulates colours, and
## neither gives a glow a value.
##
## The threshold is the load-bearing one. The board's tiles are *lit* and top out
## well below 1.0, so a threshold above that catches only what the path shader
## emits — set it lower and the whole scene hazes over, backdrop included.
const GLOW_THRESHOLD := 0.92
const GLOW_INTENSITY := 1.15
const GLOW_BLOOM := 0.20
const GLOW_STRENGTH := 1.20

## How far past the far end of the path the band travels before it is done, so the
## last cell gets a full pass rather than a half one.
const FLOW_TAIL := 0.25

## Height of the tallest tile above the plane as a fraction of the cell
## circumradius, which the fit has to reserve room for (§4.4 against the projected
## bounds). Owned by [BoardTiles], because that is what stands things up.
const TILE_TOP_RATIO := BoardTiles.MAX_TOP

## Emitted when the cached screen positions have changed and anything holding them
## — §11.2's candidate set, the cursor ring — needs re-feeding.
signal screen_positions_changed

@export var palette: Palette = null

var camera: BoardCamera = null
var viewport: SubViewport = null
var tiles: BoardTiles = null
var links: BoardLinks = null
var marks: BoardMarks = null
var seams: BoardSeams = null
var particles: BoardParticles = null
var layout: HexLayout = null

var _board: Board = null
var _state: GameState = null
var _screen: Dictionary = {}     # Vector3i -> Vector2, in sub-viewport pixels
var _flow: Tween = null
var _flow_head: float = -1.0
var _drain: Tween = null
var _saturation: float = 1.0


func _ready() -> void:
	if palette == null:
		palette = Palette.current()
	stretch = true
	# A `Control` that keeps Godot's default STOP swallows every mouse and touch
	# event in the GUI pass before `_unhandled_input` sees one. That is exactly the
	# defect that kept pointer input from reaching the level screen through all of
	# M3 (B7): this node must never re-introduce it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_nodes()
	SettingsService.changed.connect(_on_setting_changed)


## Binds a level and sizes the board to [param play_area] (§4.4, projected). Called
## once per level, never per frame.
func bind(state: GameState, play_area: Vector2) -> void:
	_ensure_nodes()
	_state = state
	_board = state.board
	# `stretch` keeps the sub-viewport exactly this size, synchronously, which is
	# what makes container coordinates and viewport coordinates the same numbers.
	# Never set the viewport's size directly — with stretch on, Godot refuses it.
	size = play_area
	# Measured against the board's own cells rather than its radius (C-32): a
	# corridor's bounding radius counts its length, and fitting the hexagon that
	# would contain one draws it at a fraction of the room it has.
	layout = HexLayout.new(float(BoardCamera.fit_cells(_board.cells(), play_area,
		TILE_TOP_RATIO)))
	camera.frame_play_area(play_area)
	tiles.bind(state, layout)
	links.bind(state, layout, tiles)
	marks.bind(state, layout, tiles)
	seams.bind(state, layout, tiles)
	particles.bind(layout)
	# C-36: one clock for the bolt and for what it lands on. The view carries the
	# number across because it is the only thing that holds both meshes — neither of
	# them may reach for the other.
	tiles.set_pulse_seconds(BoardLinks.pulse_period())
	# A new level is a new completion, so §14.3's once-per-level budget resets here.
	camera.reset_shake()
	# A new level is never dead, whatever the last one was.
	_saturation = 1.0
	_set_saturation(1.0)
	_recompute_positions(camera.yaw_radians())


## The rest of [BoardView]'s surface, so the two views are interchangeable to the
## level screen: the same four calls, in the same order, meaning the same things.
func rebuild() -> void:
	tiles.rebuild()
	# After the tiles, always: both of these sit on top of the tiles, so they have
	# to be told where the tops are *after* a placement has raised them.
	links.rebuild()
	marks.rebuild()


## §14.1's placement feedback, in the order the eye reads it: the tile pops and the
## connector that reached it draws. Called by the screen when a cell joins, because
## a view is told what happened — it does not listen for it.
func play_placement(cell: Vector3i) -> void:
	tiles.pop(cell)
	links.draw_newest()
	play_flow_pulse()
	particles.burst("placement_sparks", _above(cell))
	# §6 grants a charge for entering a wild, and §14.4 gives that its own emitter —
	# the one moment on the board that hands the player something.
	if _board != null and _board.is_wild(cell):
		particles.burst("wild_pickup", _above(cell))


## §14.1's flow pulse: one band, travelling the whole path from the start to the
## cell just joined, over 300 ms.
##
## Driven from here rather than from either mesh because it crosses both — a tile
## and the stroke lying on top of it have to brighten at the same instant, and two
## tweens would be two clocks. The band's position is a single uniform; where each
## instance sits along the path is a number it already carries.
func play_flow_pulse(speed: float = 1.0) -> void:
	if _flow != null and _flow.is_running():
		_flow.kill()
	# At the start *now*, not on the tween's first step: a tween does not run until
	# the next idle frame, and the band would otherwise be a frame late — and would
	# still be sitting wherever the last pulse left it for that frame.
	_set_flow_head(0.0)
	_flow = create_tween()
	Motion.shape(_flow, "flow_pulse")
	_flow.tween_method(_set_flow_head, 0.0, 1.0 + FLOW_TAIL,
		Motion.seconds("flow_pulse") / maxf(speed, 0.01))
	# Parked well outside 0…1 so no band is drawn until the next placement.
	_flow.finished.connect(func() -> void: _set_flow_head(-1.0))


func flow_head() -> float:
	return _flow_head


func _set_flow_head(value: float) -> void:
	# C-36: the band arrives. Detected as a crossing rather than scheduled, because
	# the tween is eased — the head does not reach the end of the route at any
	# fraction of the duration a caller could work out in advance.
	var arrived: bool = value >= 1.0 and _flow_head < 1.0
	_flow_head = value
	if arrived and tiles != null:
		tiles.electrify()
	for mesh: GeometryInstance3D in [tiles, links]:
		if mesh != null and mesh.material_override is ShaderMaterial:
			(mesh.material_override as ShaderMaterial).set_shader_parameter("flow_head", value)


## §14.2's goal-reached sequence, beat for beat off [constant
## Motion.GOAL_SEQUENCE]: the goal cell flourishes at once, the board ripples out
## of it at 120 ms, and the whole path pulses at double speed at 200 ms.
##
## All five of the beats the board owns now run. The sixth, the Results card at
## t=700, belongs to [GameDirector] — a screen is not the board's to raise.
##
## The intervals are differences between table entries rather than durations typed
## here, so the sequence stays diffable against §14.2 line by line: move a beat in
## the table and it moves on screen, and no two of them can drift apart.
func play_goal_reached(cell: Vector3i) -> void:
	# Before the flourish, not after: t=340 converts the cell *from* the goal
	# colour, so the goal colour has to still be on it to convert from. The rules
	# made this a path cell the instant it was entered, and the board followed at
	# once — which meant the whole flourish played on a tile that had already
	# stopped looking like a goal.
	tiles.hold_goal(cell)
	tiles.flourish(cell)
	var sequence := create_tween()
	sequence.tween_interval(Motion.beat_seconds("burst"))
	sequence.tween_callback(func() -> void: particles.burst("goal_burst", _above(cell)))
	sequence.tween_interval(Motion.beat_seconds("ripple") - Motion.beat_seconds("burst"))
	sequence.tween_callback(func() -> void: tiles.ripple_from(cell))
	sequence.tween_interval(Motion.beat_seconds("flow") - Motion.beat_seconds("ripple"))
	sequence.tween_callback(func() -> void: play_flow_pulse(Motion.GOAL_FLOW_SPEEDUP))
	sequence.tween_interval(Motion.beat_seconds("settle") - Motion.beat_seconds("flow"))
	sequence.tween_callback(func() -> void: tiles.settle_goal(cell))


## §14.3, on the one event it is budgeted for. Returns whether it actually shook,
## because "once per level completion, nowhere else" is a claim worth being able to
## check rather than assume.
func play_completion() -> bool:
	# C-28: the route draws itself, start to goal, once — the only time the line
	# exists at all, which is what makes it worth watching.
	links.play_trace()
	return camera.shake_once()


## §14.1's refusal, on the cell that was refused. Horizontal means horizontal *on
## screen*, so the axis comes from the camera the player is looking through rather
## than from the world.
func play_illegal(cell: Vector3i) -> void:
	tiles.shake(cell, camera.global_transform.basis.x)


## §14.1's dead-state desaturation: the board drains to 70% saturation over 400 ms.
##
## §5.8 makes DEAD recoverable — an undo or a restart brings the level back — so
## this has an inverse and uses it. A board that stayed grey after the player undid
## their way out would be telling them the level was still lost.
func play_dead() -> void:
	_drain_to(DEAD_SATURATION)


func clear_dead() -> void:
	_drain_to(1.0)


func saturation() -> float:
	return _saturation


func _drain_to(target: float) -> void:
	if _drain != null and _drain.is_running():
		_drain.kill()
	if is_equal_approx(_saturation, target):
		return
	_drain = create_tween()
	Motion.shape(_drain, "dead_desaturate")
	_drain.tween_method(_set_saturation, _saturation, target,
		Motion.seconds("dead_desaturate"))


func _set_saturation(value: float) -> void:
	_saturation = value
	for mesh: GeometryInstance3D in [tiles, links, marks, seams]:
		if mesh != null and mesh.material_override is ShaderMaterial:
			(mesh.material_override as ShaderMaterial).set_shader_parameter("saturation", value)


func set_candidates(targets: Array[Vector3i], wild: bool = false) -> void:
	tiles.set_candidates(targets)
	seams.set_candidates(targets, wild)


func set_cursor(cell: Vector3i, visible_cursor: bool = true) -> void:
	tiles.set_cursor(cell, visible_cursor)


## Turns the board a whole number of 60° stops, clockwise for positive (§14.3 as
## amended by C-18). The screen positions jump to the target stop immediately; the
## camera tweens there.
func rotate_by(steps: int) -> void:
	if steps == 0 or camera == null:
		return
	camera.rotate_by(steps)
	_recompute_positions(BoardCamera.YAW_STOP_RADIANS * float(camera.yaw_step))


## Cell → screen position for every cell of the board, which is what [InputRouter]
## wants: §11.2's ±75° cone and its clockwise cycling are both computed from these,
## so rotating the camera rotates the controls with it and neither has to know.
func centres() -> Dictionary:
	return _screen


func centre_of(cell: Vector3i) -> Vector2:
	return _screen.get(cell, centre_on_screen())


## The board's own centre on screen. The camera orbits `(0,0,0)`, so this is the
## middle of the play area at every stop — the fixed point §11.2 sorts bearings
## around.
func centre_on_screen() -> Vector2:
	return Vector2(viewport.size) * 0.5 if viewport != null else Vector2.ZERO


## Hit-testing goes camera ray → `y = 0` → cube rounding, never through raw screen
## coordinates (B7). [param local_point] is in this container's own space, which is
## the sub-viewport's space.
func cell_at(local_point: Vector2) -> Vector3i:
	if camera == null or layout == null:
		return Vector3i.ZERO
	return layout.from_plane(camera.plane_point(local_point))


## A whole-window position — where a click or a finger actually arrives — brought
## into the board's own space. A `Control` has no `to_local`, and subtracting the
## board's offset by hand at the call site is how a screen with a top bar ends up
## hit-testing one row out, so the conversion lives here with the thing it converts.
func local_point(at: Vector2) -> Vector2:
	return at - global_position


## The inverse: where [param cell] is on the window, for aiming a pointer at it.
func screen_position_of(cell: Vector3i) -> Vector2:
	return global_position + centre_of(cell)


## A little above [param cell]'s tile top, which is where a spark should leave from
## rather than from inside the prism.
func _above(cell: Vector3i) -> Vector3:
	return layout.to_plane(cell) + Vector3.UP * (tiles.top_of(cell) + layout.size * 0.1)


func _ensure_nodes() -> void:
	if viewport != null:
		return
	viewport = SubViewport.new()
	viewport.name = "BoardViewport"
	# The board gets a world of its own so nothing else in the scene can light it
	# or appear in it by accident.
	viewport.own_world_3d = true
	# §13.7: the board plays *over* the chapter's painted backdrop, so the viewport
	# clears to nothing rather than to a colour. Without this the board is an opaque
	# 880-px rectangle and the picture behind it is only ever visible in the margins.
	viewport.transparent_bg = true
	add_child(viewport)
	camera = BoardCamera.new()
	camera.name = "BoardCamera"
	viewport.add_child(camera)
	# One node for the whole board, so one draw call covers it (§13.3). The camera
	# orbits the world origin, so board space and world space are the same space.
	tiles = BoardTiles.new()
	tiles.name = "BoardTiles"
	tiles.palette = palette
	viewport.add_child(tiles)
	# The path itself, as the ribbon of §13.3 — the second of the two multimeshes
	# §20's draw-call budget reserves for the board.
	links = BoardLinks.new()
	links.name = "BoardLinks"
	links.palette = palette
	viewport.add_child(links)
	# The §6 modifiers, in a third: they are marks on tiles rather than kinds of
	# tile, so they cannot ride C-22's height channel and cannot share either mesh
	# (C-23).
	marks = BoardMarks.new()
	marks.name = "BoardMarks"
	marks.palette = palette
	viewport.add_child(marks)
	# The edge a placement would cross, in a fourth. Not part of [BoardTiles]
	# because a seam belongs to the *boundary* between two cells and every instance
	# there is one cell.
	seams = BoardSeams.new()
	seams.name = "BoardSeams"
	seams.palette = palette
	viewport.add_child(seams)
	# §14.4's four emitters, built once and reused — never one per event.
	particles = BoardParticles.new()
	particles.name = "BoardParticles"
	particles.palette = palette
	viewport.add_child(particles)
	_add_lighting()


## One key light and one environment, both fixed in world space.
##
## Fixed is the point: the light does not follow the yaw, so turning the board moves
## the shadows across it and the rotation reads as a rotation. It sits high and to
## one side, which is what gives C-22's tile heights something to cast — the height
## *is* the colour-independent channel, and a light straight down would flatten it.
##
## §14.3 is unaffected: this is not camera motion, and nothing here moves at all.
func _add_lighting() -> void:
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_color = palette.board_key_light
	key.light_energy = 1.15
	# Down 50°, and yawed off the camera's opening axis so the prism sides that face
	# the viewer are not the ones in full shadow.
	key.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	key.shadow_enabled = true
	# The tiles are the only casters and they are all within a board's width, so the
	# split can stay tight and the shadows stay sharp.
	key.directional_shadow_max_distance = BoardCamera.DISTANCE * 0.5
	viewport.add_child(key)

	var env := Environment.new()
	# `BG_CANVAS` rather than `BG_COLOR`: a colour background would paint over the
	# transparency the viewport was just given. The tiles still light normally —
	# what changes is only what is behind them (C-26, §13.7).
	env.background_mode = Environment.BG_CANVAS
	env.background_color = palette.bg_deep
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = palette.board_ambient
	env.ambient_light_energy = 0.95
	_light_the_path(env)
	var holder := WorldEnvironment.new()
	holder.name = "BoardEnvironment"
	holder.environment = env
	viewport.add_child(holder)


## §13.1 asks the path to read as "a line of light", and light does not stop at
## the edge of the thing emitting it. Without a bloom the stroke was lit *up to*
## its ink edge and dark one pixel outside it, which reads as a painted highlight
## rather than as something glowing on the board.
##
## Thresholded well above the board's own brightness so only the path blooms: the
## tiles are lit, not emissive, and a threshold low enough to catch them would put
## a haze over the whole scene and take §13.7's painted backdrop with it. The
## budget is one post-process pass, which §20 has room for at 1280×800 — and it is
## off entirely under the flat board (C-24), where nothing is emissive by design.
func _light_the_path(env: Environment) -> void:
	env.glow_enabled = true
	env.glow_intensity = GLOW_INTENSITY
	env.glow_bloom = GLOW_BLOOM
	env.glow_strength = GLOW_STRENGTH
	env.glow_hdr_threshold = GLOW_THRESHOLD
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# The near levels are the tight halo that hugs the stroke; the wider ones are
	# the spill. Skipping the widest keeps the bloom local to the line rather than
	# washing the board it lies on.
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 0.7)
	env.set_glow_level(3, 0.35)


## §21's escape hatch, live: a player turning it on mid-level sees the board go
## flat under them rather than on the next load (C-24). The key light stops
## casting too — with the board taking no light, a shadow pass would render
## nothing anyone can see and still cost what it costs (§20).
func set_flat(flat: bool) -> void:
	tiles.set_flat(flat)
	links.set_flat(flat)
	seams.set_flat(flat)
	var key: DirectionalLight3D = viewport.get_node_or_null("KeyLight")
	if key != null:
		key.shadow_enabled = not flat


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "flat_board":
		set_flat(bool(value))
	elif key == "reduce_motion":
		# §14.5 reaches a board already on screen: the loops stop where they are
		# rather than at the next level, and the emitters go quiet with them.
		tiles.set_motion()
		tiles.set_pulse_seconds(BoardLinks.pulse_period())
		marks.set_motion()
		particles.set_motion()


func _recompute_positions(yaw: float) -> void:
	_screen.clear()
	if _board == null:
		return
	for c: Vector3i in _board.cells():
		_screen[c] = camera.unproject_at(layout.to_plane(c), yaw)
	screen_positions_changed.emit()

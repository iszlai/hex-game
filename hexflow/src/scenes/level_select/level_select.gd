extends Control
## The campaign map (§12.2, §9): one chapter's hex flower, its progress, and the
## way back.
##
## Navigation over the twelve levels is [InputRouter]'s, unchanged — the same
## ±75° cone, the same clockwise cycling, over the same [HexLayout] geometry the
## board uses. A hex map is a hex map, and inventing a second scheme for it would
## give the player two different answers to "what does left mean here".
##
## Chapters page on the bumpers rather than on left/right, because left and right
## are already spoken for by the cone.

const TOP_BAR := 56.0
const FOOTER := 88.0
const TOUCH_TARGET := 44.0

## §9's chapter names. Data, so the map and any future chapter card read the same
## list; the levels themselves are frozen JSON and carry no name of their own.
const CHAPTER_NAMES: Array[String] = [
	"Flow", "Walls", "Branches", "Gates & Portals", "Pressure",
]

@onready var flower: HexFlower = %Flower
@onready var chapter_label: Label = %ChapterLabel
@onready var progress_label: Label = %ProgressLabel
@onready var detail_label: Label = %DetailLabel
@onready var hint_label: Label = %HintLabel
@onready var back_button: Button = %BackButton
@onready var prev_button: Button = %PrevButton
@onready var next_button: Button = %NextButton

var _chapter: int = 1
var _router: InputRouter = InputRouter.new()
var _palette: Palette = null


func _ready() -> void:
	InputBindings.activate(InputBindings.SET_MENU)
	_palette = load("res://src/data/palettes/neon_dark.tres")
	flower.palette = _palette
	(%Background as ColorRect).color = _palette.bg_deep
	_apply_type_roles()

	# §12.2's default focus: the last played level, which is the run in progress if
	# there is one. It decides the chapter as well as the cell.
	var at: Vector2i = Campaign.last_played()
	_chapter = clampi(at.x, 1, LevelRepository.CHAPTERS)
	_router.cursor = HexFlower.cell_for(at.y)
	_router.has_cursor = true

	_router.cursor_moved.connect(_on_cursor_moved)
	back_button.pressed.connect(_leave)
	prev_button.pressed.connect(func() -> void: _page_chapter(-1))
	next_button.pressed.connect(func() -> void: _page_chapter(1))
	for button: Button in [back_button, prev_button, next_button]:
		button.custom_minimum_size = Vector2(TOUCH_TARGET, TOUCH_TARGET)
	get_viewport().size_changed.connect(_relayout)
	_relayout()


func _apply_type_roles() -> void:
	chapter_label.theme_type_variation = Typography.variation_for(Typography.Role.HEADING)
	progress_label.theme_type_variation = Typography.variation_for(Typography.Role.NUMERAL)
	detail_label.theme_type_variation = Typography.variation_for(Typography.Role.NUMERAL)
	hint_label.theme_type_variation = Typography.variation_for(Typography.Role.CAPTION)
	hint_label.add_theme_color_override("font_color", _palette.text_secondary)
	detail_label.add_theme_color_override("font_color", _palette.text_secondary)


func _map_area() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(maxf(320.0, vp.x), maxf(320.0, vp.y - TOP_BAR - FOOTER))


func _relayout() -> void:
	flower.position = Vector2(0.0, TOP_BAR)
	flower.size = _map_area()
	_refresh()


# --- input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if InputBindings.active_set != InputBindings.SET_MENU:
		return
	if _pointer(event):
		get_viewport().set_input_as_handled()
		return
	var handled := true
	if event.is_action_pressed("menu_up", true):
		_move(Vector2.UP)
	elif event.is_action_pressed("menu_down", true):
		_move(Vector2.DOWN)
	elif event.is_action_pressed("menu_left", true):
		_move(Vector2.LEFT)
	elif event.is_action_pressed("menu_right", true):
		_move(Vector2.RIGHT)
	elif event.is_action_pressed("menu_cycle_prev"):
		_page_chapter(-1)
	elif event.is_action_pressed("menu_cycle_next"):
		_page_chapter(1)
	elif event.is_action_pressed("menu_accept"):
		_open(flower.cursor())
	elif event.is_action_pressed("menu_back"):
		_leave()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


## Mouse, trackpad and finger. A pointer lands on a cell and opens it in one
## gesture, and the cursor follows, so the keyboard picks up where the finger left
## off. The conversion is [HexFlower]'s, which is [HexLayout]'s — never a
## comparison of screen rectangles (defect B7).
func _pointer(event: InputEvent) -> bool:
	var at := Vector2.INF
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		at = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		at = (event as InputEventScreenTouch).position
	if at == Vector2.INF:
		return false
	var index: int = flower.level_at(at - flower.global_position)
	if index > 0:
		_router.cursor = HexFlower.cell_for(index)
		_router.has_cursor = true
		flower.set_cursor(index)
		_open(index)
	return true


func _move(direction: Vector2) -> void:
	if not _router.move(direction):
		AudioDirector.play_sfx("ui.reject")


func _on_cursor_moved(cell: Vector3i) -> void:
	AudioDirector.play_sfx("ui.move")
	flower.set_cursor(_index_of(cell))
	_refresh_detail()


## §12.5 — Back goes up exactly one level of the state machine, never further.
func _leave() -> void:
	AudioDirector.play_sfx("ui.back")
	GameDirector.go_to(GameDirector.Screen.MAIN_MENU)


func _page_chapter(step: int) -> void:
	var next: int = clampi(_chapter + step, 1, LevelRepository.CHAPTERS)
	if next == _chapter:
		AudioDirector.play_sfx("ui.reject")
		return
	_chapter = next
	AudioDirector.play_sfx("ui.move")
	# The cursor goes to where the player left *this* chapter, not to the cell it
	# happened to be on in the last one. §12.2's "last played level" is a rule about
	# what the map should be pointing at, and it does not stop applying because the
	# player arrived by paging: holding position means a page into a fresh chapter
	# lands on a locked level nine times out of twelve.
	_router.cursor = HexFlower.cell_for(_resume_index())
	_router.has_cursor = true
	_refresh()


## The first level of this chapter still to be played, or its last if it is done.
func _resume_index() -> int:
	for index: int in range(1, Campaign.LEVELS_PER_CHAPTER + 1):
		if not Campaign.is_completed(_chapter, index):
			return index
	return Campaign.LEVELS_PER_CHAPTER


func _open(index: int) -> void:
	if not Campaign.level_unlocked(_chapter, index):
		AudioDirector.play_sfx("ui.reject")
		hint_label.text = _locked_reason(index)
		return
	var level: Level = LevelRepository.load_level(_chapter, index)
	if level == null:
		# The campaign data is missing or unreadable; say so rather than fading to
		# a screen that will not load (§17.1 — one bad file never bricks a save).
		AudioDirector.play_sfx("ui.reject")
		hint_label.text = "Level %d is unavailable" % index
		return
	AudioDirector.play_sfx("ui.confirm")
	GameDirector.start_level(level)
	GameDirector.go_to(GameDirector.Screen.LEVEL)


func _locked_reason(index: int) -> String:
	if not Campaign.chapter_unlocked(_chapter):
		return "Chapter %d opens at %d of %d in chapter %d" % [
			_chapter, Campaign.CHAPTER_UNLOCK_THRESHOLD,
			Campaign.LEVELS_PER_CHAPTER, _chapter - 1,
		]
	return "Finish level %d first" % (index - 1)


# --- painting -----------------------------------------------------------------

func _refresh() -> void:
	var rows: Array[Dictionary] = []
	var positions: Dictionary = {}
	var open: Array[Vector3i] = []
	for index: int in range(1, Campaign.LEVELS_PER_CHAPTER + 1):
		var unlocked: bool = Campaign.level_unlocked(_chapter, index)
		var done: bool = Campaign.is_completed(_chapter, index)
		rows.append({
			"state": (HexFlower.State.DONE if done
				else HexFlower.State.OPEN if unlocked
				else HexFlower.State.LOCKED),
			"stars": Campaign.stars(_chapter, index),
			"hinted": Campaign.hinted(_chapter, index),
		})
	flower.bind(rows, flower.size)

	# The cursor may rest on a locked level — the map is a map, and a player is
	# entitled to look at what is coming. Every cell is therefore a candidate; the
	# lock is enforced on `_open`, not on where the cursor may go.
	for index: int in range(1, Campaign.LEVELS_PER_CHAPTER + 1):
		open.append(HexFlower.cell_for(index))
	positions = flower.centres()
	_router.set_candidates(open, positions, flower.size * 0.5)
	flower.set_cursor(_index_of(_router.cursor))

	chapter_label.text = "Chapter %d · %s" % [_chapter, CHAPTER_NAMES[_chapter - 1]]
	progress_label.text = "%d / %d   ★ %d / %d" % [
		Campaign.completed_in_chapter(_chapter), Campaign.LEVELS_PER_CHAPTER,
		Campaign.stars_in_chapter(_chapter),
		Campaign.LEVELS_PER_CHAPTER * Scoring.MAX_STARS,
	]
	back_button.text = "← Back  %s" % InputGlyphs.label_for("menu_back")
	prev_button.text = "‹ %s" % InputGlyphs.label_for("menu_cycle_prev")
	next_button.text = "%s ›" % InputGlyphs.label_for("menu_cycle_next")
	prev_button.disabled = _chapter <= 1
	next_button.disabled = _chapter >= LevelRepository.CHAPTERS
	_refresh_detail()


func _refresh_detail() -> void:
	var index: int = flower.cursor()
	if not Campaign.level_unlocked(_chapter, index):
		detail_label.text = "Level %d   locked" % index
		hint_label.text = _locked_reason(index)
		return
	var level: Level = LevelRepository.load_level(_chapter, index)
	var par: int = level.par if level != null else 0
	var best: int = Campaign.best_placements(_chapter, index)
	detail_label.text = "Level %d   par %d%s" % [
		index, par, "   best %d" % best if best > 0 else "",
	]
	hint_label.text = "%s open   %s chapter   %s back" % [
		InputGlyphs.label_for("menu_accept"),
		InputGlyphs.label_for("menu_cycle_next"),
		InputGlyphs.label_for("menu_back"),
	]


func _index_of(cell: Vector3i) -> int:
	var i: int = HexFlower.CELLS.find(cell)
	return i + 1 if i >= 0 else 1

extends Control
## The results card (§12.2): what the run was worth, and the three things to do
## about it.
##
## The stars are the screen. §14.1 gives them 3 × 260 ms on a `BACK`/`EASE_OUT`
## curve, staggered 140 ms apart, "each with a chord note" — so they arrive one at
## a time and the third landing is the moment the player is here for. A card that
## simply displayed "★★☆" would satisfy the word "stars" in §12.2 and none of the
## reason it is there.

@onready var menu: MenuList = %Menu
@onready var title_label: Label = %TitleLabel
@onready var score_label: Label = %ScoreLabel
@onready var detail_label: Label = %DetailLabel
@onready var stars_row: HBoxContainer = %Stars

var _palette: Palette = null
var _star_labels: Array[Label] = []
var _result: Dictionary = {}


func _ready() -> void:
	InputBindings.activate(InputBindings.SET_MENU)
	_palette = Palette.current()
	menu.palette = _palette
	Backdrop.install(self, int(GameDirector.last_result.get("chapter", 0)))
	(%Background as ColorRect).color = Color(_palette.bg_deep, 0.0)
	_result = GameDirector.last_result.duplicate()

	Surface.apply_to(self, _palette)
	_apply_type_roles()
	_build_stars()
	menu.activated.connect(_on_activated)
	menu.focus_moved.connect(func(_id: String) -> void: AudioDirector.play_sfx("ui.move"))
	_refresh()
	# §12.2's default focus for this screen is Next — and when there is no next
	# (§7.1's threshold unmet, or the campaign finished), focus falls to Replay
	# rather than resting on a row that cannot be pressed. §12.5 wants exactly one
	# focused element, and a disabled one does not count.
	menu.focus_id("next" if menu.enabled("next") else "replay")
	_play_stars()


func _apply_type_roles() -> void:
	title_label.theme_type_variation = Typography.variation_for(Typography.Role.HEADING)
	score_label.theme_type_variation = Typography.variation_for(Typography.Role.NUMERAL)
	detail_label.theme_type_variation = Typography.variation_for(Typography.Role.CAPTION)
	detail_label.add_theme_color_override("font_color", _palette.text_secondary)


## One label per star, built once. They start at zero scale and are grown by the
## tween below, so the card never shows its answer before it has told it.
func _build_stars() -> void:
	for i: int in range(Scoring.MAX_STARS):
		var label := Label.new()
		label.theme_type_variation = Typography.variation_for(Typography.Role.DISPLAY)
		label.text = "★"
		# The pivot is set once the label has a size, which is a frame away; until
		# then it grows from its top-left, which nobody sees at scale zero.
		label.scale = Vector2.ZERO
		stars_row.add_child(label)
		_star_labels.append(label)
	# §12.6's dot, which marks the *level* rather than the attempt. Its own node so
	# it is a separate mark beside the stars and can never be counted as one.
	var dot := Label.new()
	dot.name = "HintDot"
	dot.theme_type_variation = Typography.variation_for(Typography.Role.CAPTION)
	dot.text = "•"
	dot.visible = false
	dot.add_theme_color_override("font_color", _palette.text_secondary)
	stars_row.add_child(dot)


func _stars_earned() -> int:
	return int(_result.get("stars", 0))


func _refresh() -> void:
	var mode: int = int(_result.get("mode", GameDirector.Mode.CAMPAIGN))
	var chapter: int = int(_result.get("chapter", 0))
	var index: int = int(_result.get("index", 0))
	var placements: int = int(_result.get("placements", 0))
	var par: int = int(_result.get("par", 0))

	if mode == GameDirector.Mode.DAILY:
		title_label.text = "Daily · %s" % str(_result.get("level_id", ""))
	elif chapter > 0:
		title_label.text = "Chapter %d · Level %d" % [chapter, index]
	else:
		title_label.text = "Complete"

	score_label.text = "placements %d / par %d" % [placements, par]
	detail_label.text = _band_text(placements, par)
	(stars_row.get_node("HintDot") as Label).visible = bool(_result.get("hinted", false))

	# §7.1: a Next that pointed into a locked chapter would be offering something
	# the map itself refuses, so it is disabled rather than allowed to fail late.
	var next: Vector2i = Vector2i.ZERO
	if mode == GameDirector.Mode.CAMPAIGN and chapter > 0:
		next = Campaign.after(chapter, index)
	menu.set_rows([
		{"id": "next", "label": "Next level", "value": "", "enabled": next.x > 0},
		{"id": "replay", "label": "Replay", "value": "", "enabled": true},
		{"id": "map", "label": "Map", "value": "", "enabled": true},
	])


## Why this many stars, in the terms §5.10 states them — so a two-star result says
## what the third one would have cost rather than leaving it to be inferred.
func _band_text(placements: int, par: int) -> String:
	if _stars_earned() >= Scoring.MAX_STARS:
		return "par met"
	if placements <= par + Scoring.MAX_STARS:
		return "%d over par · %d fewer for three stars" % [placements - par, placements - par]
	return "%d over par" % (placements - par)


## §14.1: 3 × 260 ms, `BACK`/`EASE_OUT`, staggered 140 ms, a chord note each.
## Only the stars actually earned are played — an unearned star arriving and then
## not being there is a promise the card cannot keep.
func _play_stars() -> void:
	var earned: int = _stars_earned()
	for i: int in range(_star_labels.size()):
		var label: Label = _star_labels[i]
		if i >= earned:
			# Still drawn, so the row always reads "x of three" — hollow, at rest.
			label.text = "☆"
			label.scale = Vector2.ONE
			label.add_theme_color_override("font_color", _palette.cell_empty_stroke)
			continue
		label.add_theme_color_override("font_color", _palette.goal_cell)
		var tween := create_tween()
		Motion.shape(tween, "results_star")
		tween.tween_interval(float(i * Motion.RESULTS_STAR_STAGGER_MS) / 1000.0)
		tween.tween_callback(func() -> void: AudioDirector.play_sfx("star.award"))
		tween.tween_property(label, "scale", Vector2.ONE, Motion.seconds("results_star"))


func _unhandled_input(event: InputEvent) -> void:
	if InputBindings.active_set != InputBindings.SET_MENU:
		return
	var handled := true
	if event.is_action_pressed("menu_up", true):
		menu.move(-1)
	elif event.is_action_pressed("menu_down", true):
		menu.move(1)
	elif event.is_action_pressed("menu_accept"):
		menu.activate()
	elif event.is_action_pressed("menu_back"):
		# §12.5 — up exactly one level: Results sits over the map (§12.1).
		_to_map()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _on_activated(id: String) -> void:
	match id:
		"next":
			var at: Vector2i = Campaign.after(
				int(_result.get("chapter", 0)), int(_result.get("index", 0))
			)
			_start(at.x, at.y)
		"replay":
			if int(_result.get("mode", 0)) == GameDirector.Mode.DAILY:
				# §7.3 — unlimited retries, on *today's* board. A retry on a
				# different board is not a retry.
				GameDirector.start_daily(GameDirector.daily_date())
				GameDirector.go_to(GameDirector.Screen.LEVEL)
				return
			_start(int(_result.get("chapter", 0)), int(_result.get("index", 0)))
		"map":
			_to_map()


func _start(chapter: int, index: int) -> void:
	var level: Level = LevelRepository.load_level(chapter, index)
	if level == null:
		_to_map()
		return
	GameDirector.start_level(level)
	GameDirector.go_to(GameDirector.Screen.LEVEL)


func _to_map() -> void:
	AudioDirector.play_sfx("ui.back")
	# A daily run has no place on the campaign map, so it goes back where it came
	# from (§12.1 draws Daily off the main menu, not off the map).
	if int(_result.get("mode", GameDirector.Mode.CAMPAIGN)) == GameDirector.Mode.DAILY:
		GameDirector.go_to(GameDirector.Screen.MAIN_MENU)
		return
	GameDirector.go_to(GameDirector.Screen.LEVEL_SELECT)

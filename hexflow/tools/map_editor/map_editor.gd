## The map editor (MAP-EDITOR.md): draw a campaign board by hand, check it, save
## it into `src/data/levels/`.
##
## `tools/author_levels.gd` is good at producing *many* boards and bad at
## producing a *particular* one. It cannot make a board that means something — a
## ring whose two goals sit opposite each other, a Z whose portal jumps the
## diagonal are compositions, and a sweep finds them only by accident. It cannot
## fix one level, because the only lever is a different seed and that changes the
## whole board. This is for the ten levels that carry a chapter; the sweep stays,
## and is still the right tool for filling fifty slots.
##
## **This is not the level editor §27 declined.** That non-goal is a player-facing
## screen in the shipped game, levels shared between players, Workshop, and the
## moderation burden behind all of it. This is an authoring tool in the same
## category as `make sfx` and `make levels`: it runs from the repo, it is excluded
## from the export, and its output is committed JSON the game treats as frozen
## data. §8 of the brief is how that stays true rather than being merely asserted.
##
## The UI is built in code rather than laid out in the `.tscn`. A forty-node scene
## file is the harder thing to review and the easier thing to break silently — a
## renamed node in a tool nobody has a test for is discovered by an author, at the
## keyboard, with a board on screen. `map_editor.tscn` exists because §2 needs a
## scene to run (input, a UI and a render, which a `-s` MainLoop script does not
## get) and holds exactly this script.
##
## Run: `make edit-maps`
extends Control

const PANEL_WIDTH := 260
const UID_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789"
const UID_LENGTH := 10

## §3's brush list, in order. `null` marks the board brush, which paints
## membership rather than contents and is the one that is not a [MapDraft.Content].
## The mode switch. Painting a board and drawing the route through it are two
## different jobs on the same canvas, and a click has to mean one of them.
const MODES: Array = [
	{"label": "paint  (1)", "mode": MapCanvas.Mode.PAINT},
	{"label": "trace  (2)", "mode": MapCanvas.Mode.TRACE},
]

const PAINT_HINT := "left paints · right erases · middle-drag pans · wheel zooms"
const TRACE_HINT := "left lays the next tile · right takes one back · the route is the sequence"

const BRUSHES: Array = [
	{"label": "board", "brush": MapDraft.BRUSH_BOARD},
	{"label": "wall  #", "brush": MapDraft.Content.WALL},
	{"label": "start  S", "brush": MapDraft.Content.START},
	{"label": "goal  G", "brush": MapDraft.Content.GOAL},
	{"label": "portal  P", "brush": MapDraft.Content.PORTAL},
	{"label": "gate  K", "brush": MapDraft.Content.GATE},
	{"label": "wild  *", "brush": MapDraft.Content.WILD},
]

var _draft: MapDraft = MapDraft.new()
## The last Validate, or null when the board has changed since. Save reads this,
## which is what makes §6's refusal a refusal rather than a warning.
var _report: MapReport = null
var _filling: bool = false
var _mode: int = MapCanvas.Mode.PAINT

var _canvas: MapCanvas = null
var _mode_buttons: Array[Button] = []
var _brush_buttons: Array[Button] = []
var _hint: Label = null
var _header: Label = null
var _status: Label = null
var _tiles_field: LineEdit = null
var _fill_button: Button = null
var _save_button: Button = null
var _shape: OptionButton = null
var _size: SpinBox = null
var _arg: SpinBox = null
var _discards: SpinBox = null
var _budget: SpinBox = null
var _chapter: SpinBox = null
var _index: SpinBox = null
var _browser: LevelBrowser = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_draft.apply_shape("hexagon", 3, 0)
	_canvas.bind(_draft)
	_sync_fields()
	_invalidate()


# --- layout ---------------------------------------------------------------------

func _build_ui() -> void:
	var margins := MarginContainer.new()
	margins.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 10)
	add_child(margins)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	margins.add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)

	_header = Label.new()
	left.add_child(_header)

	_canvas = MapCanvas.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.painted.connect(_on_painted)
	left.add_child(_canvas)

	var tiles_row := HBoxContainer.new()
	left.add_child(tiles_row)
	tiles_row.add_child(_label("TILES"))
	_tiles_field = LineEdit.new()
	_tiles_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tiles_field.placeholder_text = "NE NE E SE SW W — or press Fill"
	_tiles_field.text_submitted.connect(_on_tiles_typed)
	tiles_row.add_child(_tiles_field)
	_fill_button = _button("fill", _fill)
	tiles_row.add_child(_fill_button)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 44)
	left.add_child(_status)

	columns.add_child(_build_panel())

	_browser = LevelBrowser.new()
	_browser.chosen.connect(_on_level_chosen)
	_browser.reordered.connect(func(_n: int) -> void: _invalidate())
	add_child(_browser)
	_browser.hide()


## The right-hand rail: everything above the action buttons scrolls, and the three
## buttons do not. Seven brushes and six fields are taller than a 900 px window at
## the default theme's row height, and the first version of this pushed Save off
## the bottom of the screen — a tool whose Save you cannot reach is a tool that
## does nothing.
func _build_panel() -> Control:
	var rail := VBoxContainer.new()
	rail.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	rail.add_theme_constant_override("separation", 8)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rail.add_child(scroll)

	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 6)
	scroll.add_child(panel)

	# Two columns, because seven full-width rows are the tallest thing in the rail
	# and the fields below them ended up scrolled out of sight behind it. A brush
	# palette is a grid everywhere else for the same reason.
	# The mode switch sits above the brushes because it decides whether they mean
	# anything: in trace mode a click lays a tile and the brush under it is not
	# consulted at all.
	panel.add_child(_label("MODE"))
	var modes := GridContainer.new()
	modes.columns = 2
	panel.add_child(modes)
	var mode_group := ButtonGroup.new()
	for entry: Variant in MODES:
		var spec: Dictionary = entry
		var button := Button.new()
		button.text = str(spec["label"])
		button.toggle_mode = true
		button.button_group = mode_group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mode: int = int(spec["mode"])
		button.pressed.connect(func() -> void: _set_mode(mode))
		_mode_buttons.append(button)
		modes.add_child(button)
	_mode_buttons[MapCanvas.Mode.PAINT].button_pressed = true

	panel.add_child(_label("BRUSH"))
	var brushes := GridContainer.new()
	brushes.columns = 2
	panel.add_child(brushes)
	var group := ButtonGroup.new()
	for entry: Variant in BRUSHES:
		var spec: Dictionary = entry
		var button := Button.new()
		button.text = str(spec["label"])
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var brush: int = int(spec["brush"])
		button.pressed.connect(func() -> void: _canvas.brush = brush)
		if brush == int(MapDraft.Content.WALL):
			button.button_pressed = true
		_brush_buttons.append(button)
		brushes.add_child(button)

	# The one thing about the brushes that is not on a button, and the first thing
	# anyone asks. §4.1 gives right-drag a different meaning per brush — off-board
	# for the board brush, empty for the rest — and neither is guessable. Trace mode
	# gives it a third meaning, so the line is rewritten rather than added to.
	_hint = _label(PAINT_HINT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_hint)

	panel.add_child(_label("BOARD"))
	var grid := GridContainer.new()
	grid.columns = 2
	panel.add_child(grid)

	# The slot first. It is the field that decides which file Save writes and which
	# curve target Validate scores against, and it was the field that ended up
	# below the fold when the panel was ordered by how much it looked like a
	# drawing tool.
	_chapter = _spin(grid, "chapter", 1, LevelRepository.CHAPTERS)
	_index = _spin(grid, "level", 1, LevelRepository.LEVELS_PER_CHAPTER)

	_shape = OptionButton.new()
	for kind: String in Hex.SHAPES:
		_shape.add_item(kind)
	_shape.item_selected.connect(func(_i: int) -> void: _on_shape_changed())
	grid.add_child(_label("shape"))
	grid.add_child(_shape)

	_size = _spin(grid, "size", 1, 12)
	_arg = _spin(grid, "arg", 0, 8)
	_discards = _spin(grid, "discards", 0, 9)
	# -1 is §5.7's "no budget", which is what [constant Level.NO_BUDGET] is. A
	# spinbox showing -1 reads oddly and reads *unambiguously*, which is the
	# trade a tool should take over a checkbox and a second field.
	_budget = _spin(grid, "budget (-1 none)", -1, 99)

	_size.value_changed.connect(func(_v: float) -> void: _on_shape_changed())
	_arg.value_changed.connect(func(_v: float) -> void: _on_shape_changed())
	_discards.value_changed.connect(func(v: float) -> void:
		_draft.discards = int(v); _draft.tiles_stale = true; _invalidate())
	_budget.value_changed.connect(func(v: float) -> void:
		_draft.budget = int(v); _invalidate())
	# The slot is not decoration: it decides which curve target Validate scores
	# against and which file Save writes, so changing it invalidates a report the
	# same way moving a wall does.
	_chapter.value_changed.connect(func(v: float) -> void: _draft.chapter = int(v); _invalidate())
	_index.value_changed.connect(func(v: float) -> void: _draft.index = int(v); _invalidate())

	rail.add_child(_button("validate  (F5)", _validate))
	rail.add_child(HSeparator.new())
	rail.add_child(_button("new  (Ctrl+N)", _new_board))
	rail.add_child(_button("open…  (Ctrl+O)", _open_file))
	_save_button = _button("save to slot  (Ctrl+S)", _save)
	rail.add_child(_save_button)
	rail.add_child(_button("save as…  (Ctrl+Shift+S)", _save_as))
	rail.add_child(_button("levels…", _open_browser))
	return rail


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b


func _spin(grid: GridContainer, label: String, low: int, high: int) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = low
	box.max_value = high
	box.step = 1
	grid.add_child(_label(label))
	grid.add_child(box)
	return box


# --- editing --------------------------------------------------------------------

## Switches what a click on the canvas means (§4.4).
##
## **Why there is a second mode at all.** Fill sweeps ten seeds and every one of
## them is a random walk that can dead-end; on a board with a tight corridor or a
## fenced-in goal all ten can, and then Fill has nothing to offer and no way to be
## argued with. Tracing is the answer to that — and it is also the only way to get
## a route somebody *chose*, which §4.4 wanted from the text field and never really
## got, because a sequence of direction names is not a shape anyone can picture.
##
## Entering the mode replays the route against the board as it is now, because the
## board may well have moved while the brush was out.
func _set_mode(mode: int) -> void:
	_mode = mode
	_canvas.mode = mode
	_mode_buttons[mode].button_pressed = true
	# Greyed rather than hidden: the palette staying where it is says the brushes
	# are still there and not applicable, and a rail that reflows on a mode switch
	# moves every other button out from under the cursor.
	for button: Button in _brush_buttons:
		button.disabled = mode == MapCanvas.Mode.TRACE
	_hint.text = TRACE_HINT if mode == MapCanvas.Mode.TRACE else PAINT_HINT
	if mode != MapCanvas.Mode.TRACE:
		_canvas.refresh()
		_refresh()
		return

	var dropped: int = _draft.revalidate_trace()
	_canvas.refresh()
	# The replay can shorten the sequence, so the last Validate is about a level
	# that no longer exists.
	_invalidate()
	if _draft.start == Hex.NONE:
		_note("trace: place a start first — the route grows out of it")
	elif dropped > 0:
		_note("trace: dropped %d step%s the board no longer allows · %s"
			% [dropped, "" if dropped == 1 else "s", _trace_status()])
	else:
		_note("trace: click a cell next to the route · " + _trace_status())


## Where the route has got to, in the terms the author is thinking in: how many
## tiles it has spent and how many goals are still out.
func _trace_status() -> String:
	var head: String = "%d tiles traced" % _draft.trace.size()
	if _draft.goals().is_empty():
		return head + " · no goal to reach yet"
	var left: int = _draft.trace_goals_left()
	if left == 0:
		return head + " · every goal joined, so this sequence is a solution"
	return head + " · %d goal%s still out" % [left, "" if left == 1 else "s"]


func _on_painted(cell: Vector3i, erase: bool) -> void:
	if _mode == MapCanvas.Mode.TRACE:
		_on_traced(cell, erase)
		return
	var brush: int = _canvas.brush
	if brush == MapDraft.BRUSH_BOARD:
		if erase:
			_draft.remove_cell(cell)
		elif not _draft.add_cell(cell) and _draft.at_ceiling():
			# §4.2's ceiling is the solver's 64-bit path mask (C-19), so painting
			# past it is refused rather than warned about.
			_note("%d cells is the ceiling — the solver's path mask is 64 bits"
				% Hex.MAX_CELLS)
			return
	elif erase:
		_draft.clear_content(cell)
	else:
		_draft.set_content(cell, brush as MapDraft.Content)
	_canvas.refresh()
	_invalidate()


## One step of the route, forwards or back.
##
## Every step is checked against the same rules the game plays by, so what comes
## out is a **recorded legal play** and therefore a sequence the solver can win by
## construction. That is the difference between this and the text field of §4.4:
## typing six direction names produces a sequence that may be unplayable and only
## says so at Validate, seconds later, with nothing to point at.
func _on_traced(cell: Vector3i, erase: bool) -> void:
	if erase:
		if not _draft.undo_trace():
			_note("trace: nothing to take back")
			return
	else:
		var refusal: String = _draft.trace_step(cell)
		if refusal != "":
			_canvas.refresh()
			_note(refusal)
			return
	_canvas.refresh()
	_invalidate()
	_note(_trace_status())


func _on_shape_changed() -> void:
	_draft.apply_shape(
		Hex.SHAPES[_shape.selected], int(_size.value), int(_arg.value))
	_canvas.bind(_draft)
	_invalidate()


func _on_tiles_typed(text: String) -> void:
	var parsed: Array = TileFiller.parse(text)
	if parsed[0] == null:
		_note(str(parsed[1]))
		return
	_draft.tiles = parsed[0] as Array[int]
	_draft.tiles_stale = false
	# A typed sequence is not the drawn one any more, and a route left on the canvas
	# under a sequence it does not describe is the canvas lying.
	_draft.clear_trace()
	_canvas.refresh()
	_invalidate()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_1:
		_set_mode(MapCanvas.Mode.PAINT)
		accept_event()
	elif key.keycode == KEY_2:
		_set_mode(MapCanvas.Mode.TRACE)
		accept_event()
	elif key.keycode == KEY_F5:
		_validate()
		accept_event()
	elif key.keycode == KEY_S and key.is_command_or_control_pressed():
		if key.shift_pressed:
			_save_as()
		else:
			_save()
		accept_event()
	elif key.keycode == KEY_O and key.is_command_or_control_pressed():
		_open_file()
		accept_event()
	elif key.keycode == KEY_N and key.is_command_or_control_pressed():
		_new_board()
		accept_event()


# --- fill, validate, save --------------------------------------------------------

## §4.4's sweep. Awaits a frame between deals so the count on screen moves — each
## one runs the solver and both metrics, which is seconds, and a tool that freezes
## for half a minute without saying why looks broken.
func _fill() -> void:
	if _filling:
		return
	var blockers := _draft.problems()
	if not blockers.is_empty():
		_note("cannot fill: " + blockers[0])
		return
	_filling = true
	_fill_button.disabled = true

	var best: TileFiller.Deal = null
	var best_score: int = 1 << 30
	for attempt: int in range(TileFiller.SEEDS):
		_status.text = "filling… deal %d of %d" % [attempt + 1, TileFiller.SEEDS]
		await get_tree().process_frame
		var deal := TileFiller.try_seed(_draft, attempt, best_score)
		if deal != null and deal.score < best_score:
			best_score = deal.score
			best = deal

	_filling = false
	_fill_button.disabled = false
	if best == null:
		_note("no deal made this board solvable — check the route is not walled off")
		return
	_draft.tiles = best.tiles
	_draft.fill_seed = best.seed
	_draft.tiles_stale = false
	# Fill's route is not the drawn one — same reason as a typed sequence.
	_draft.clear_trace()
	_canvas.refresh()
	_invalidate()
	_note("kept deal %d: ideal %d · %d routes · %d%% forgiving"
		% [best.seed, best.par, best.routes, best.forgiving])


func _validate() -> void:
	if _filling:
		return
	_status.text = "validating…"
	await get_tree().process_frame
	_report = MapReport.of(_draft)
	_refresh()
	_status.text = _report.summary()


func _save() -> void:
	_save_to(LevelRepository.path_for(_draft.chapter, _draft.index))


## Save, wherever it is going.
##
## §6's refusal follows the **destination**, not the button. Into one of the sixty
## it is absolute: the one thing this tool must never do is put an unsolvable
## level into frozen data, because the property test that would catch it runs
## later, in CI, after the commit. Anywhere else it does not apply at all — a
## draft is for parking a board that is not finished yet, and a scratch folder
## that only accepts finished work is not a scratch folder.
##
## What a draft still needs is a start, because without one there is no [Level] to
## serialise. That is the whole of the constraint, and it is thirty seconds of
## work rather than a rule to design around.
func _save_to(path: String) -> void:
	if _filling:
		return
	var to_campaign := LevelFile.is_campaign_path(path)
	if to_campaign and _report == null:
		_note("validate first — a campaign slot will not take a board nobody has checked")
		return
	if to_campaign and not _report.ok:
		_note("refusing to save: " + ", ".join(_report.problems))
		return

	# Minted before stamping, so the level carries it: an edit keeps the uid it
	# arrived with (§7.1) and only a level that never had one gets a new name.
	if _draft.uid == "":
		_draft.uid = _mint_uid()
	# A validated board is written as its report measured it; an unvalidated draft
	# is written as it stands, with whatever `par` and metrics it already carried.
	# It has to be one or the other — stamping a report onto a board that has moved
	# since is how a level acquires a par nobody can reproduce.
	var level := _report.stamp(_draft) if _report != null and _report.ok else _draft.to_level()
	if level == null:
		_note("nothing to save yet — a board needs a start before it is a level")
		return

	if not LevelFile.write(level, path):
		_note("could not write %s" % path)
		return
	LevelRepository.clear_cache()
	_note("wrote %s (%s)%s" % [
		path, level.uid,
		"" if to_campaign else "  — a draft, not one of the sixty",
	])


## An empty board to start from.
##
## Behind a confirm, which is not politeness. §9 rules undo out of scope on the
## grounds that "save-and-reload covers it" — that is true of a mis-drag and not
## true of this, which throws the whole board away in one press. It is the same
## reasoning §11.3 applies to Restart in the game.
func _new_board() -> void:
	if _filling:
		return
	var confirm := ConfirmationDialog.new()
	confirm.title = "New board"
	confirm.dialog_text = "Start a new board?\n\nThere is no undo. Anything not saved is lost."
	confirm.ok_button_text = "New board"
	confirm.confirmed.connect(_reset_draft)
	for signal_name: String in ["confirmed", "canceled", "close_requested"]:
		confirm.connect(signal_name, confirm.queue_free)
	add_child(confirm)
	confirm.popup_centered()


## The slot is kept and everything else is dropped.
##
## **The uid goes.** A fresh board that inherited the last one's name would hand a
## player's stars to a level they have never seen, which is the exact bug uids
## exist to prevent (C-34) — the sweep mints a new one for the same reason. It
## stays empty until the first save, which is where the collision check lives.
func _reset_draft() -> void:
	var chapter: int = _draft.chapter
	var index: int = _draft.index
	_draft = MapDraft.new()
	_draft.chapter = chapter
	_draft.index = index
	_draft.apply_shape("hexagon", 3, 0)
	_canvas.bind(_draft)
	_sync_fields()
	_invalidate()
	_note("new board · slot %d-%02d kept · it is named when it is first saved"
		% [chapter, index])


## §6.1's Save as. Defaults to `drafts/` and will go anywhere, including — with a
## passing Validate — straight into a campaign slot.
func _save_as() -> void:
	if _filling:
		return
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(LevelFile.DRAFT_DIR))
	var dialog := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, _save_to)
	dialog.current_file = "%s.json" % (_draft.uid if _draft.uid != "" else "draft")
	dialog.popup_centered_ratio(0.7)


## Opens any level file, draft or campaign. Save-as without this would be a
## one-way door: a board parked in `drafts/` with no way back is not parked.
func _open_file() -> void:
	if _filling:
		return
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(LevelFile.DRAFT_DIR))
	_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, _load_path).popup_centered_ratio(0.7)


func _load_path(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		_note("%s is not a level file" % path)
		return
	_on_level_chosen(parsed as Dictionary, path)


## Built per use and freed after. A `FileDialog` kept around remembers the folder
## it was last in, which sounds like a convenience and means Save-as quietly aims
## at wherever Open last looked.
func _file_dialog(mode: FileDialog.FileMode, action: Callable) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	# The whole filesystem, not just `res://`: §6.1 says a custom folder, and an
	# author who wants their drafts outside the repository should not be argued
	# with. `drafts/` is only where it starts.
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.current_dir = ProjectSettings.globalize_path(LevelFile.DRAFT_DIR)
	dialog.add_filter("*.json", "Level files")
	dialog.use_native_dialog = false
	dialog.file_selected.connect(action)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.file_selected.connect(func(_p: String) -> void: dialog.queue_free())
	add_child(dialog)
	return dialog


## A permanent name for a level, minted once and never reused (C-34). Checked
## against every file on disk, because a duplicate would put two levels on one row
## of the player's progress — the same bug uids exist to prevent.
##
## `randi()` is fine here: C2 bans it in `src/`, where determinism is the
## requirement. This is an authoring step whose output is committed.
func _mint_uid() -> String:
	var taken: Dictionary = {}
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			_claim_uid(LevelRepository.path_for(chapter, index), taken)
	# Drafts count. Two drafts sharing a name would be harmless right up until both
	# were promoted into slots, at which point they share a row of progress — which
	# is the exact bug uids exist to prevent (C-34).
	var drafts := DirAccess.open(LevelFile.DRAFT_DIR)
	if drafts != null:
		for name: String in drafts.get_files():
			if name.ends_with(".json"):
				_claim_uid(LevelFile.DRAFT_DIR + "/" + name, taken)
	while true:
		var out: String = ""
		for _i: int in range(UID_LENGTH):
			out += UID_CHARS[randi() % UID_CHARS.length()]
		if not taken.has(out):
			return out
	return ""


func _claim_uid(path: String, taken: Dictionary) -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		taken[str((parsed as Dictionary).get("uid", ""))] = true


# --- the levels list --------------------------------------------------------------

func _open_browser() -> void:
	_browser.reload()
	_browser.popup_centered()


func _on_level_chosen(data: Dictionary, path: String) -> void:
	var level := LevelRepository.from_dict(data)
	if level == null:
		_note("could not read %s" % path)
		return
	_draft = MapDraft.from_level(level)
	_canvas.bind(_draft)
	_sync_fields()
	_invalidate()
	# §4.4's third option, Keep: the sequence comes with the level, so the board
	# can be edited around a deal that already works.
	var note := "loaded %s — %d tiles kept" % [path.get_file(), _draft.tiles.size()]
	if not _draft.notes.is_empty():
		note += " · " + ", ".join(_draft.notes)
	_note(note)


# --- refresh ---------------------------------------------------------------------

## Pushes the draft back into the fields, after a load. Signals are blocked so
## setting a value does not re-enter the handler that reshapes the board.
func _sync_fields() -> void:
	for node: Node in [_shape, _size, _arg, _discards, _budget, _chapter, _index]:
		node.set_block_signals(true)
	_shape.selected = maxi(0, Hex.SHAPES.find(_draft.shape))
	_size.value = _draft.shape_size
	_arg.value = _draft.shape_arg
	_discards.value = _draft.discards
	_budget.value = _draft.budget
	_chapter.value = _draft.chapter
	_index.value = _draft.index
	for node: Node in [_shape, _size, _arg, _discards, _budget, _chapter, _index]:
		node.set_block_signals(false)
	_tiles_field.text = TileFiller.to_text(_draft.tiles)


## Drops the last Validate. Called by every edit, which is what stops Save
## writing a report that was true about a different board — §6's refusal only
## means anything if the thing it consults is current.
func _invalidate() -> void:
	_report = null
	_refresh()


func _refresh() -> void:
	_save_button.disabled = _report == null or not _report.ok
	_header.text = "chapter %d · level %02d · %d cells%s" % [
		_draft.chapter, _draft.index, _draft.count(),
		"  (ceiling)" if _draft.at_ceiling() else "",
	]
	_tiles_field.text = TileFiller.to_text(_draft.tiles)

	var problems := _draft.problems()
	var parts: PackedStringArray = PackedStringArray()
	if _mode == MapCanvas.Mode.TRACE:
		# While tracing, "no tile sequence" is both true and useless: the sequence is
		# being drawn, and how far it has got is the thing worth saying.
		parts.append(_trace_status())
	elif _draft.tiles.is_empty():
		parts.append("no tile sequence")
	elif _draft.tiles_stale:
		parts.append("the board changed since the sequence was made — re-run Fill")
	parts.append_array(problems)
	_status.text = " · ".join(parts) if not parts.is_empty() \
		else "ready — validate to score it against the curve"


## [method _refresh], then a message over the top of it. Used by everything that
## has something to say about what just happened; the header and the buttons are
## still brought up to date underneath.
func _note(message: String) -> void:
	_refresh()
	_status.text = message

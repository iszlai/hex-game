## Levels: pick and reorder (MAP-EDITOR §7).
##
## A list of all sixty — chapter, index, shape, ideal, routes, forgiveness, and
## how far each sits from its slot on the curve. Rows drag to reorder, within a
## chapter or across chapters, and `Apply order` rewrites the files.
##
## **Reordering is safe because levels have names (§7.1, C-34).** The save used to
## key progress on `c3_l07`, which names a *position*, so dragging a level out of
## slot 7 left its stars behind for whatever landed there. Every file now carries a
## `uid` minted once and never reused, and progress keys on that — so a level
## carries its stars wherever it moves and position is only presentation.
##
## Which is why this rewrites the **raw JSON** rather than round-tripping through
## [Level]. §7.1 promises `Apply order` touches `chapter`, `index` and the
## filenames and nothing else, and the only way to promise that is to not
## re-serialise the rest. A round trip through `to_dict` would be *nearly*
## lossless, and "nearly" across sixty frozen files is how a par quietly changes.
##
## Not part of the shipped game.
class_name LevelBrowser
extends Window

## The chosen level's parsed JSON and the path it came from.
signal chosen(data: Dictionary, path: String)
signal reordered(count: int)

const COLUMNS: Array[String] = [
	"slot", "name", "shape", "ideal", "routes", "forgiving", "off curve"
]

## The flat campaign, in list order. Each entry is `{path, data}`; position in
## this array *is* the level's slot once `Apply order` runs.
var _rows: Array = []

var _tree: Tree = null
var _status: Label = null


func _init() -> void:
	title = "Levels"
	size = Vector2i(760, 620)
	unresizable = false
	close_requested.connect(hide)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.columns = COLUMNS.size()
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.drop_mode_flags = Tree.DROP_MODE_INBETWEEN
	_tree.set_drag_forwarding(_drag_data, _can_drop, _drop_row)
	# Double-click or Enter, not a single click: a single click is also the first
	# half of a drag, and loading the canvas the moment a row is touched would
	# throw away whatever the author had drawn on it.
	_tree.item_activated.connect(_on_activated)
	for i: int in range(COLUMNS.size()):
		_tree.set_column_title(i, COLUMNS[i])
		_tree.set_column_expand(i, i <= 2)
	root.add_child(_tree)

	var buttons := HBoxContainer.new()
	root.add_child(buttons)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_status)
	buttons.add_child(_button("Load", _on_activated))
	buttons.add_child(_button("Apply order", _apply_order))
	buttons.add_child(_button("Close", hide))


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b


## Reads every level file that exists. Raw JSON rather than [LevelRepository],
## because this list is about the campaign's *shape* and never plays a level —
## and because loading sixty through the validating loader takes long enough to
## notice for a list that is being opened to look at.
func reload() -> void:
	_rows = []
	for chapter: int in range(1, LevelRepository.CHAPTERS + 1):
		for index: int in range(1, LevelRepository.LEVELS_PER_CHAPTER + 1):
			var path := LevelRepository.path_for(chapter, index)
			if not FileAccess.file_exists(path):
				continue
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_rows.append({"path": path, "data": parsed as Dictionary})
	_rebuild()


func _rebuild() -> void:
	_tree.clear()
	var root := _tree.create_item()
	for i: int in range(_rows.size()):
		var data: Dictionary = (_rows[i] as Dictionary)["data"]
		var metrics: Dictionary = data.get("metrics", {})
		var routes: int = int(metrics.get("routes", -1))
		var forgiving: int = int(metrics.get("forgiving", -1))
		# Against the slot the row is in *now*, so dragging a level shows
		# immediately whether it belongs where it was dropped.
		var chapter: int = i / LevelRepository.LEVELS_PER_CHAPTER + 1
		var index: int = i % LevelRepository.LEVELS_PER_CHAPTER + 1

		var item := _tree.create_item(root)
		item.set_text(0, "%d · %02d" % [chapter, index])
		item.set_text(1, str(data.get("uid", "—")))
		item.set_text(2, str(data.get("shape", "hexagon")))
		item.set_text(3, str(int(data.get("par", 0))))
		item.set_text(4, str(routes) if routes >= 0 else "—")
		item.set_text(5, "%d%%" % forgiving if forgiving >= 0 else "—")
		item.set_text(6, str(DifficultyCurve.distance(chapter, index, routes, forgiving))
			if routes >= 0 and forgiving >= 0 else "—")
		item.set_metadata(0, i)
	_status.text = "%d levels" % _rows.size()


# --- drag to reorder -----------------------------------------------------------

func _drag_data(_at: Vector2) -> Variant:
	var item := _tree.get_selected()
	if item == null:
		return null
	var preview := Label.new()
	preview.text = "%s  %s" % [item.get_text(0), item.get_text(1)]
	_tree.set_drag_preview(preview)
	return {"row": int(item.get_metadata(0))}


func _can_drop(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("row")


func _drop_row(at: Vector2, data: Variant) -> void:
	var from: int = int((data as Dictionary)["row"])
	var onto := _tree.get_item_at_position(at)
	if onto == null:
		return
	var to: int = int(onto.get_metadata(0))
	# -1 is above the row under the cursor, +1 below, 0 is on it.
	if _tree.get_drop_section_at_position(at) > 0:
		to += 1
	if from < to:
		to -= 1
	if from == to:
		return
	var moved: Variant = _rows[from]
	_rows.remove_at(from)
	_rows.insert(clampi(to, 0, _rows.size()), moved)
	_rebuild()


func _on_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var row: Dictionary = _rows[int(item.get_metadata(0))]
	chosen.emit(row["data"] as Dictionary, str(row["path"]))
	hide()


# --- apply -----------------------------------------------------------------

## Rewrites `chapter`, `index`, `id` and the filename of every level whose slot
## changed, and nothing else. Every file is read before any is written — the new
## path of one level is the old path of another, so writing as it goes would
## overwrite a file it had not read yet.
func _apply_order() -> void:
	var written: int = 0
	for i: int in range(_rows.size()):
		var row: Dictionary = _rows[i]
		var data: Dictionary = row["data"]
		var chapter: int = i / LevelRepository.LEVELS_PER_CHAPTER + 1
		var index: int = i % LevelRepository.LEVELS_PER_CHAPTER + 1
		var path := LevelRepository.path_for(chapter, index)
		var id := LevelRepository.id_for(chapter, index)
		if int(data.get("chapter", 0)) == chapter and int(data.get("index", 0)) == index \
				and str(row["path"]) == path:
			continue
		data["chapter"] = chapter
		data["index"] = index
		data["id"] = id
		row["path"] = path
		written += 1

	if written == 0:
		_status.text = "nothing moved"
		return
	for row: Variant in _rows:
		var entry: Dictionary = row
		_write(str(entry["path"]), entry["data"] as Dictionary)
	LevelRepository.clear_cache()
	_status.text = "rewrote %d levels" % written
	reordered.emit(written)
	_rebuild()


## Sorted keys and a trailing newline, matching `tools/stamp_uids.gd` and what is
## on disk — a level that only moved slot must not also show up in the diff as
## reformatted.
static func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % path)
		return
	file.store_string(JSON.stringify(data, "  ", true) + "\n")
	file.close()

extends SceneTree
## The asset desk: what the game wants, what it has, and where a new file goes.
##
## A dev tool, not part of the game. It lives in `tools/`, which no export preset
## ships (§25), and nothing in `src/` imports it.
##
## It exists because `docs/ASSET-REQUIREMENTS.md` is prose — good for handing to an
## illustrator, useless for answering "did that land in the right place". The table
## below is the same requirements in a form a machine can check, and it is the one
## that can go stale silently, so it is the one that gets run.
##
##   make assets                          what is here, what is missing
##   make assets-add FILE=~/x.png AS=chapter_3
##
## `add` copies rather than moves: the thing in your Downloads folder stays there,
## because a tool that eats the original is a tool you use once and then stop
## trusting.

## The manifest is **shared**, not duplicated: `tools/asset_manifest.json` is read
## by this and by the browser tool beside it. Two copies of "what the game wants"
## is one copy that quietly stops being true, and the whole point of a checker is
## that it cannot.
const MANIFEST := "res://tools/asset_manifest.json"

## Where the glyph breakdown is derived from, for the same reason.
const GLYPH_ATLAS := "res://src/data/input_glyphs.json"

static var _manifest: Dictionary = {}


static func manifest() -> Dictionary:
	if not _manifest.is_empty():
		return _manifest
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(MANIFEST)) != OK:
		push_error("tools/asset_manifest.json is unreadable")
		return {}
	_manifest = json.data
	return _manifest


static func assets() -> Array:
	return manifest().get("assets", []) as Array


static func groups() -> Array:
	return manifest().get("groups", []) as Array


## Every file a group wants, as `{name, for, make}`.
##
## A group with `derive` names a file that already knows the answer, and that file
## wins: §11.4's 52 glyphs are 13 slots × 4 families *because `input_glyphs.json`
## says so*, and a manifest that listed them separately would be a second opinion
## the game never reads. Everything else carries its own `items`, which
## `tests/unit/test_asset_manifest.gd` holds against the game's own tables.
static func items_of(group: Dictionary) -> Array:
	if str(group.get("derive", "")) == "glyphs":
		return glyph_items()
	return group.get("items", []) as Array


static func glyph_items() -> Array:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(GLYPH_ATLAS)) != OK:
		push_error("%s is unreadable" % GLYPH_ATLAS)
		return []
	var out: Array = []
	for entry: Variant in ((json.data as Dictionary).get("families", []) as Array):
		var family: Dictionary = entry
		var labels: Dictionary = family["labels"]
		for slot: Variant in labels:
			out.append({
				"name": "%s_%s" % [family["name"], slot],
				"for": str(slot),
				"make": 'the button the game writes as "%s"' % labels[slot],
			})
	return out


static func extensions() -> Dictionary:
	return manifest().get("extensions", {}) as Dictionary


## Manifest paths are project-relative; the engine wants `res://`.
static func res(path: String) -> String:
	return "res://" + path





func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var command: String = args[0] if args.size() > 0 else "status"
	match command:
		"add":
			_add(args[1] if args.size() > 1 else "", args[2] if args.size() > 2 else "")
		_:
			var role: String = args[1] if args.size() > 1 else ""
			if role != "":
				_breakdown(role)
			else:
				_status()
	quit()


# --- status --------------------------------------------------------------------

func _status() -> void:
	print("")
	print("  ROLE               STATUS      DETAIL")
	print("  ─────────────────────────────────────────────────────────────────────")
	var missing: Array[String] = []
	var bytes: int = 0
	for entry: Variant in assets():
		var spec: Dictionary = entry
		var path: String = res(str(spec["path"]))
		if not FileAccess.file_exists(path):
			missing.append(str(spec["role"]))
			print("  %-18s %-11s %s" % [spec["role"], "missing", spec["note"]])
			continue
		bytes += _size_of(path)
		print("  %-18s %-11s %s" % [spec["role"], "here", _detail(spec)])

	for entry: Variant in groups():
		var group: Dictionary = entry
		var absent: Array[String] = _absent(group)
		var want: int = items_of(group).size()
		var found: int = want - absent.size()
		var state: String = "here" if absent.is_empty() else ("%d of %d" % [found, want])
		if not absent.is_empty():
			missing.append(str(group["role"]))
		bytes += _bytes_in(res(str(group["dir"])))
		print("  %-18s %-11s %s" % [group["role"], state, group["note"]])
		# The count alone answers "is it done" and not "what do I make next", which
		# is the question someone reading this actually has.
		if not absent.is_empty():
			print("  %-18s %-11s %s" % ["", "", "missing: " + _wrap(absent)])
		var extra: Array[String] = _extras(group)
		if not extra.is_empty():
			print("  %-18s %-11s %s" % ["", "", "nothing asked for: " + _wrap(extra)])

	print("")
	print("  a group's own breakdown, file by file:  make assets ROLE=glyphs")
	print("")
	print("  %d of %d roles present · %.1f MB on disk"
		% [assets().size() + groups().size() - missing.size(),
			assets().size() + groups().size(), float(bytes) / 1048576.0])
	if missing.is_empty():
		print("  nothing missing")
	else:
		print("  still wanted: %s" % ", ".join(missing))
		print("")
		print("  add one with:  make assets-add FILE=~/somewhere/file.png AS=<role>")
	print("")


func _detail(spec: Dictionary) -> String:
	var path: String = res(str(spec["path"]))
	var size: String = "%.0f KB" % (float(_size_of(path)) / 1024.0)
	if str(spec["kind"]) != "image":
		return "%s · %s" % [size, spec["note"]]
	var got: Vector2i = _png_size(path)
	if got == Vector2i.ZERO:
		return "%s · unreadable" % size
	var want := Vector2i(int((spec["want"] as Array)[0]), int((spec["want"] as Array)[1]))
	var warn: String = "" if got.x >= want.x and got.y >= want.y \
		else "  (under %dx%d)" % [want.x, want.y]
	return "%dx%d · %s%s" % [got.x, got.y, size, warn]


# --- breakdown -----------------------------------------------------------------

## One group, file by file — what each slot is for and what to make for it.
##
## `make assets` says "52 of 52 glyphs"; this says which file is `deck_select` and
## that it stands for the button the Deck calls **View**. The browser desk shows the
## same thing with the pictures in it (`make assets-ui`), and both read this table,
## because the two disagreeing would be worse than either alone.
func _breakdown(role: String) -> void:
	var group: Dictionary = _group_for(role)
	if group.is_empty():
		print("no such group: %s" % role)
		print("groups: %s" % ", ".join(_group_roles()))
		return

	var items: Array = items_of(group)
	print("")
	print("  %s — %s" % [group["role"], group["note"]])
	if group.has("brief"):
		print("  %s" % group["brief"])
	print("")
	print("  FILE                          FOR                  WHAT TO MAKE")
	print("  ─────────────────────────────────────────────────────────────────────────────")
	for entry: Variant in items:
		var item: Dictionary = entry
		var file: String = str(item["name"]) + str(group["ext"])
		var path: String = res(str(group["dir"]) + file)
		var mark: String = " " if FileAccess.file_exists(path) else "*"
		print("  %s %-27s %-20s %s" % [mark, file, item["for"], item["make"]])
	print("")
	print("  * = not here yet · drop one in with")
	print("    cp yourfile%s %s%s" % [group["ext"], group["dir"], "<file above>"])
	print("")


func _group_for(role: String) -> Dictionary:
	for entry: Variant in groups():
		if str((entry as Dictionary)["role"]) == role:
			return entry
	return {}


func _group_roles() -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in groups():
		out.append(str((entry as Dictionary)["role"]))
	return out


## The files a group wants and does not have.
func _absent(group: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in items_of(group):
		var file: String = str((entry as Dictionary)["name"]) + str(group["ext"])
		if not FileAccess.file_exists(res(str(group["dir"]) + file)):
			out.append(file)
	return out


## Files in the folder that the manifest never asked for. Usually a name typo, and
## a typo the game will silently ignore is exactly what a checker is for.
func _extras(group: Dictionary) -> Array[String]:
	var wanted: Dictionary = {}
	for entry: Variant in items_of(group):
		wanted[str((entry as Dictionary)["name"]) + str(group["ext"])] = true
	var dir: String = res(str(group["dir"]))
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return []
	var out: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(str(group["ext"])) and not wanted.has(file):
			out.append(file)
	return out


## A list that stays inside a terminal: the first few, then a count.
func _wrap(names: Array[String]) -> String:
	if names.size() <= 6:
		return ", ".join(names)
	return "%s … and %d more" % [", ".join(names.slice(0, 6)), names.size() - 6]


# --- add -----------------------------------------------------------------------

func _add(source: String, role: String) -> void:
	if source == "":
		print("usage: make assets-add FILE=~/somewhere/file.png AS=<role>")
		_roles()
		return
	source = source.replace("~", OS.get_environment("HOME"))
	if not FileAccess.file_exists(source):
		print("no such file: %s" % source)
		return

	var spec: Dictionary = _spec_for(role)
	if spec.is_empty():
		if role == "":
			print("which role is this? name one with AS=")
		else:
			print("no such role: %s" % role)
		_roles()
		return

	var ext: String = "." + source.get_extension().to_lower()
	var allowed: Array = extensions()[str(spec["kind"])]
	if not allowed.has(ext):
		print("%s wants %s, and that is a %s file" % [role, " or ".join(allowed), ext])
		return

	var target: String = res(str(spec["path"]))
	var wanted_ext: String = "." + target.get_extension()
	if ext != wanted_ext:
		# An .ogg where a .wav is expected, or the other way round: the role decides
		# the name, so say so rather than writing a file the game will not look for.
		print("%s is loaded as %s; convert it first" % [role, wanted_ext])
		return

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(target.get_base_dir()))
	var replacing: bool = FileAccess.file_exists(target)
	# Copied, not moved: the file in your Downloads folder stays where it was.
	var err: int = DirAccess.copy_absolute(source, ProjectSettings.globalize_path(target))
	if err != OK:
		print("could not copy: error %d" % err)
		return

	print("%s %s" % ["replaced" if replacing else "added", target])
	if str(spec["kind"]) == "image":
		print("  %s" % _detail(spec))
		if bool(spec.get("material", false)):
			print("  reminder: this one is a *material* — it is tinted by the palette,")
			print("  so colour baked into it survives all five (docs/ASSET-REQUIREMENTS.md)")
	print("  run `make import` so Godot picks it up, then commit it")


func _spec_for(role: String) -> Dictionary:
	for entry: Variant in assets():
		if str((entry as Dictionary)["role"]) == role:
			return entry
	return {}


func _roles() -> void:
	print("")
	print("roles:")
	for entry: Variant in assets():
		var spec: Dictionary = entry
		var mark: String = " " if FileAccess.file_exists(res(str(spec["path"]))) else "*"
		print("  %s %-18s %s" % [mark, spec["role"], spec["note"]])
	print("")
	print("  * = not here yet")


# --- filesystem ----------------------------------------------------------------

## A PNG's dimensions, from its header. Read by hand rather than through
## `Image.load_from_file`, which warns on every call that loading an image this way
## "will not work on export" — true, and irrelevant to a tool that never ships, but
## a report that prints nine engine warnings is a report nobody reads to the end.
##
## The IHDR width and height are two big-endian 32-bit integers at byte 16.
func _png_size(path: String) -> Vector2i:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 24:
		return Vector2i.ZERO
	f.seek(16)
	f.big_endian = true
	return Vector2i(int(f.get_32()), int(f.get_32()))


func _size_of(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0


func _count(dir: String, ext: String) -> int:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return 0
	var n: int = 0
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(ext):
			n += 1
	return n


func _bytes_in(dir: String) -> int:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return 0
	var total: int = 0
	for file: String in DirAccess.get_files_at(dir):
		if not file.ends_with(".import"):
			total += _size_of(dir + file)
	return total

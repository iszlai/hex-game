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
		var found: int = _count(res(str(group["dir"])), str(group["ext"]))
		var want: int = int(group["want"])
		var state: String = "here" if found >= want else ("%d of %d" % [found, want])
		if found < want:
			missing.append(str(group["role"]))
		bytes += _bytes_in(res(str(group["dir"])))
		print("  %-18s %-11s %s" % [group["role"], state, group["note"]])

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

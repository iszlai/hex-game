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

## Every asset the game looks for, by the **role** it plays. `kind` decides what is
## checked; `want` is the shape the requirements ask for, and is advice rather than
## a gate — a picture that is smaller than ideal should land with a warning, not be
## refused.
const ASSETS := [
	{"role": "menu", "path": "res://assets/art/menu.png", "kind": "image",
		"want": Vector2i(1920, 1200), "note": "backdrop behind the menus"},
	{"role": "chapter_1", "path": "res://assets/art/chapter_1.png", "kind": "image",
		"want": Vector2i(1920, 1200), "note": "backdrop · Flow"},
	{"role": "chapter_2", "path": "res://assets/art/chapter_2.png", "kind": "image",
		"want": Vector2i(1920, 1200), "note": "backdrop · Walls"},
	{"role": "chapter_3", "path": "res://assets/art/chapter_3.png", "kind": "image",
		"want": Vector2i(1920, 1200), "note": "backdrop · Branches"},
	{"role": "chapter_4", "path": "res://assets/art/chapter_4.png", "kind": "image",
		"want": Vector2i(1920, 1200), "note": "backdrop · Gates & Portals"},
	{"role": "chapter_5", "path": "res://assets/art/chapter_5.png", "kind": "image",
		"want": Vector2i(1920, 1200), "note": "backdrop · Pressure"},

	{"role": "panel_frame", "path": "res://assets/art/panel_frame.png", "kind": "image",
		"want": Vector2i(96, 96), "note": "9-slice timber · deliver NEUTRAL"},
	{"role": "panel_fill", "path": "res://assets/art/panel_fill.png", "kind": "image",
		"want": Vector2i(96, 96), "note": "9-slice surface · deliver NEUTRAL"},
	{"role": "tile_grain", "path": "res://assets/art/tile_grain.png", "kind": "image",
		"want": Vector2i(256, 256), "note": "tiling board material · deliver NEUTRAL"},
	{"role": "logo", "path": "res://assets/art/logo.png", "kind": "image",
		"want": Vector2i(512, 512), "note": "brand mark"},

	{"role": "music_menu", "path": "res://assets/music/menu.ogg", "kind": "audio",
		"want": Vector2i(0, 0), "note": "bed · menus"},
	{"role": "music_chapter_1", "path": "res://assets/music/chapter_1.ogg", "kind": "audio",
		"want": Vector2i(0, 0), "note": "bed · chapter 1"},
	{"role": "music_chapter_2", "path": "res://assets/music/chapter_2.ogg", "kind": "audio",
		"want": Vector2i(0, 0), "note": "bed · chapter 2"},
	{"role": "music_chapter_3", "path": "res://assets/music/chapter_3.ogg", "kind": "audio",
		"want": Vector2i(0, 0), "note": "bed · chapter 3"},
	{"role": "music_chapter_4", "path": "res://assets/music/chapter_4.ogg", "kind": "audio",
		"want": Vector2i(0, 0), "note": "bed · chapter 4"},
	{"role": "music_chapter_5", "path": "res://assets/music/chapter_5.ogg", "kind": "audio",
		"want": Vector2i(0, 0), "note": "bed · chapter 5"},
]

## Whole groups the game wants and cannot yet name file by file — 52 controller
## glyphs and 13 music stems would bury the table above in rows that all say the
## same thing. Counted rather than listed.
const GROUPS := [
	{"role": "sfx", "dir": "res://assets/sfx/", "ext": ".wav", "want": 16,
		"note": "§15.2's sixteen effects (synthesised placeholders)"},
	{"role": "fonts", "dir": "res://assets/fonts/", "ext": ".ttf", "want": 3,
		"note": "§13.4's three families"},
	{"role": "glyphs", "dir": "res://assets/glyphs/", "ext": ".png", "want": 52,
		"note": "§11.4 · 13 slots × 4 controller families"},
]

const EXTS := {"image": [".png"], "audio": [".ogg", ".wav"]}


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
	for entry: Variant in ASSETS:
		var spec: Dictionary = entry
		var path: String = str(spec["path"])
		if not FileAccess.file_exists(path):
			missing.append(str(spec["role"]))
			print("  %-18s %-11s %s" % [spec["role"], "missing", spec["note"]])
			continue
		bytes += _size_of(path)
		print("  %-18s %-11s %s" % [spec["role"], "here", _detail(spec)])

	for entry: Variant in GROUPS:
		var group: Dictionary = entry
		var found: int = _count(str(group["dir"]), str(group["ext"]))
		var want: int = int(group["want"])
		var state: String = "here" if found >= want else ("%d of %d" % [found, want])
		if found < want:
			missing.append(str(group["role"]))
		bytes += _bytes_in(str(group["dir"]))
		print("  %-18s %-11s %s" % [group["role"], state, group["note"]])

	print("")
	print("  %d of %d roles present · %.1f MB on disk"
		% [ASSETS.size() + GROUPS.size() - missing.size(),
			ASSETS.size() + GROUPS.size(), float(bytes) / 1048576.0])
	if missing.is_empty():
		print("  nothing missing")
	else:
		print("  still wanted: %s" % ", ".join(missing))
		print("")
		print("  add one with:  make assets-add FILE=~/somewhere/file.png AS=<role>")
	print("")


func _detail(spec: Dictionary) -> String:
	var path: String = str(spec["path"])
	var size: String = "%.0f KB" % (float(_size_of(path)) / 1024.0)
	if str(spec["kind"]) != "image":
		return "%s · %s" % [size, spec["note"]]
	var got: Vector2i = _png_size(path)
	if got == Vector2i.ZERO:
		return "%s · unreadable" % size
	var want: Vector2i = spec["want"]
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
	var allowed: Array = EXTS[str(spec["kind"])]
	if not allowed.has(ext):
		print("%s wants %s, and that is a %s file" % [role, " or ".join(allowed), ext])
		return

	var target: String = str(spec["path"])
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
		if str(spec["note"]).contains("NEUTRAL"):
			print("  reminder: this one is a *material* — it is tinted by the palette,")
			print("  so colour baked into it survives all five (docs/ASSET-REQUIREMENTS.md)")
	print("  run `make import` so Godot picks it up, then commit it")


func _spec_for(role: String) -> Dictionary:
	for entry: Variant in ASSETS:
		if str((entry as Dictionary)["role"]) == role:
			return entry
	return {}


func _roles() -> void:
	print("")
	print("roles:")
	for entry: Variant in ASSETS:
		var spec: Dictionary = entry
		var mark: String = " " if FileAccess.file_exists(str(spec["path"])) else "*"
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

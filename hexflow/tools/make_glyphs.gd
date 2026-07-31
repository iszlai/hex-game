extends SceneTree
## Renders §11.4's 52 controller glyphs into `assets/glyphs/`, and the output is
## **committed** — the same arrangement as `make sfx`, `make art` and `make levels`.
##
## The 52 were the one row of `docs/ASSET-REQUIREMENTS.md` that was flatly Missing:
## a pad-holding player got the *word* "View" where every other game shows a shape.
## A licensed pack (Xelu, Kenney, a platform holder's own) is still the right answer
## and none of them is free of a licence to read, so this draws the placeholder set
## the same way §13.1 draws the board — from a table, in code, replaceable by one
## file drop.
##
## What is drawn is deliberately **legible before it is pretty**: the outline a
## thumb looks for (a circle for a face button, a bumper for a shoulder, a pill for
## View/Menu) and one to four letters taken from `src/data/input_glyphs.json` — the
## same file the text labels come from, so a glyph can never disagree with the
## label it replaces. PlayStation's four symbols and the Switch's `−`/`+` are drawn
## as geometry instead, because that is what those buttons *are*.
##
## Colour is not baked in: everything is white on transparent, tinted at runtime by
## `text_primary` (§13.2), so §21's palettes reach the glyphs like they reach the art.
##
## An existing file is **kept**, never overwritten — the whole point is that a real
## pack replaces this one by landing in the folder. `make glyphs FRESH=1` re-renders
## over the top when you actually mean to.
##
## Run: godot --headless --path . -s res://tools/make_glyphs.gd

## The atlas is the source of truth for which glyphs exist and what each one says.
## Read, never restated: 52 is 13 slots × 4 families *because that file says so*.
const ATLAS := "res://src/data/input_glyphs.json"
const OUT_DIR := "res://assets/glyphs/"

## 48 px for a 24 px slot (§13.5's icon grid), so the set survives a desktop at 2×
## without a second file. Drawn at 4× that and downsampled, which is the entire
## anti-aliasing budget — cheaper than a rasteriser and exact at these sizes.
const SIZE := 48
const SS := 4
const CANVAS := SIZE * SS

## Slot → outline. The shape carries the *kind* of button, which is what a player
## reads first and the only part that survives being 24 px tall (C5: never colour
## alone, and here never a letter alone either).
const FACE := ["a", "b", "x", "y"]
const SHOULDER := ["l1", "r1", "l2", "r2"]
const BADGE := ["select", "start"]
const STICK := ["stick", "rstick"]

## Labels too long to draw at 24 px, shortened rather than dropped. Everything else
## is used as it stands: "A", "L1", "ZR", "View", "Menu" already fit.
const SHORT := {
	"L-Stick": "LS",
	"R-Stick": "RS",
	"D-Pad": "",  # drawn as a cross; four arrows need no caption
	"Options": "OPT",
	"Create": "CRE",
}

## The symbols that are not letters. A DualSense's ✕ is a shape, not the letter X,
## and the Switch's − and + are the whole button.
const SYMBOLS := ["✕", "○", "□", "△", "−", "+"]

## A 3×5 uppercase face, written so the letterforms are visible in the source. At
## four letters this is 2 px per cell on the 48 px glyph and still reads; at one it
## is 5. Bitmap rather than a real font because `Font.draw_string` needs a canvas
## item, and a headless authoring step has none.
const FONT := {
	# A, V, X and Y are drawn flat-topped and cross-barred rather than pointed. The
	# pointed forms put a single cell diagonally adjacent to the rest of the letter,
	# which is invisible at one pixel per cell and reads as a **floating dot** at
	# five — an "A" that looks like an "Å".
	"A": ["###", "#_#", "###", "#_#", "#_#"],
	"B": ["##_", "#_#", "##_", "#_#", "##_"],
	"C": ["_##", "#__", "#__", "#__", "_##"],
	"D": ["##_", "#_#", "#_#", "#_#", "##_"],
	"E": ["###", "#__", "##_", "#__", "###"],
	"F": ["###", "#__", "##_", "#__", "#__"],
	"G": ["_##", "#__", "#_#", "#_#", "_##"],
	"H": ["#_#", "#_#", "###", "#_#", "#_#"],
	"I": ["###", "_#_", "_#_", "_#_", "###"],
	"J": ["__#", "__#", "__#", "#_#", "_#_"],
	"K": ["#_#", "#_#", "##_", "#_#", "#_#"],
	"L": ["#__", "#__", "#__", "#__", "###"],
	"M": ["###", "###", "###", "#_#", "#_#"],
	"N": ["#_#", "###", "###", "###", "#_#"],
	"O": ["_#_", "#_#", "#_#", "#_#", "_#_"],
	"P": ["##_", "#_#", "##_", "#__", "#__"],
	"Q": ["_#_", "#_#", "#_#", "###", "_##"],
	"R": ["##_", "#_#", "##_", "#_#", "#_#"],
	"S": ["_##", "#__", "_#_", "__#", "##_"],
	"T": ["###", "_#_", "_#_", "_#_", "_#_"],
	"U": ["#_#", "#_#", "#_#", "#_#", "###"],
	"V": ["#_#", "#_#", "#_#", "###", "_#_"],
	"W": ["#_#", "#_#", "###", "###", "#_#"],
	# X keeps its diagonal join. The letter *is* two diagonals, so a corner-to-corner
	# contact at the waist reads as an X rather than as a gap — barring it the way A's
	# apex is barred turns it into a bowtie.
	"X": ["#_#", "#_#", "_#_", "#_#", "#_#"],
	"Y": ["#_#", "###", "_#_", "_#_", "_#_"],
	"Z": ["###", "__#", "_#_", "#__", "###"],
	"0": ["###", "#_#", "#_#", "#_#", "###"],
	"1": ["_#_", "##_", "_#_", "_#_", "###"],
	"2": ["##_", "__#", "_#_", "#__", "###"],
	"3": ["##_", "__#", "_#_", "__#", "##_"],
	"4": ["#_#", "#_#", "###", "__#", "__#"],
	"5": ["###", "#__", "##_", "__#", "##_"],
	"6": ["_##", "#__", "##_", "#_#", "_#_"],
	"7": ["###", "__#", "_#_", "#__", "#__"],
	"8": ["_#_", "#_#", "_#_", "#_#", "_#_"],
	"9": ["_#_", "#_#", "_##", "__#", "##_"],
}

const INK := Color(1.0, 1.0, 1.0, 1.0)


func _initialize() -> void:
	var fresh: bool = OS.get_cmdline_user_args().has("fresh")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var families: Array = _atlas().get("families", [])
	if families.is_empty():
		push_error("%s has no families; nothing to draw" % ATLAS)
		quit(1)
		return

	var written := 0
	var kept := 0
	for entry: Variant in families:
		var family: Dictionary = entry
		var labels: Dictionary = family["labels"]
		for slot: Variant in labels:
			var file: String = "%s_%s.png" % [family["name"], slot]
			if FileAccess.file_exists(OUT_DIR + file) and not fresh:
				kept += 1
				continue
			var image := _glyph(str(slot), str(labels[slot]))
			image.save_png(ProjectSettings.globalize_path(OUT_DIR + file))
			written += 1

	print("  %d glyphs written, %d kept  →  %s" % [written, kept, OUT_DIR])
	if kept > 0 and not fresh:
		print("  (a file that exists is never overwritten; `make glyphs FRESH=1` forces it)")
	var total: int = written + kept
	if total != 52:
		push_error("§11.4 asks for 52 glyphs; the atlas produced %d" % total)
	quit()


func _atlas() -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(ATLAS)) != OK:
		push_error("%s is unreadable" % ATLAS)
		return {}
	return json.data as Dictionary


# --- one glyph -----------------------------------------------------------------

## Coordinates below are in **48 px space** whatever `SS` is; the primitives scale.
func _glyph(slot: String, label: String) -> Image:
	var image := _blank()

	if SYMBOLS.has(label):
		_symbol(image, label)
	elif slot == "dpad":
		_dpad(image)
	else:
		# Outline and label are drawn on separate sheets so they can be *checked*
		# against each other before they are merged. "CRE" ran straight through the
		# side of its pill in the first render and looked, at a glance, like a
		# letterform rather than a mistake — which is exactly the kind of defect a
		# generator should not be able to emit twice.
		var frame := _blank()
		var box: Rect2 = _outline(frame, slot)
		var text := _blank()
		_text(text, _short(label), box)
		# Clearance, not merely "no overlap". Letters that stop one pixel short of
		# the stroke still merge into it once the downsample blurs both, which is
		# what "CRE" did — it passed a touching test and looked wrong anyway.
		var touching: int = _overlap(frame, _grow(text, CLEARANCE * SS))
		if touching > 0:
			push_error("%s_%s: the label crowds its own outline at %d places"
				% [slot, label, touching])
		_merge(image, frame)
		_merge(image, text)

	image.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
	return image


func _blank() -> Image:
	var image := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	return image


## How much white space a label has to keep around it, in 48 px units.
const CLEARANCE := 2


## [param mask] spread outwards by [param radius]. Two 1-D passes rather than a
## disc, because a square grow is stricter than a round one and this is a floor.
func _grow(mask: Image, radius: int) -> Image:
	var wide := _blank()
	for y: int in range(CANVAS):
		for x: int in range(CANVAS):
			if mask.get_pixel(x, y).a > 0.0:
				for d: int in range(maxi(x - radius, 0), mini(x + radius + 1, CANVAS)):
					wide.set_pixel(d, y, INK)
	var out := _blank()
	for y: int in range(CANVAS):
		for x: int in range(CANVAS):
			if wide.get_pixel(x, y).a > 0.0:
				for d: int in range(maxi(y - radius, 0), mini(y + radius + 1, CANVAS)):
					out.set_pixel(x, d, INK)
	return out


## Pixels drawn on both sheets. Exact, because everything is still a hard-edged
## mask at this point — the anti-aliasing happens in the downsample afterwards.
func _overlap(a: Image, b: Image) -> int:
	var count := 0
	for y: int in range(CANVAS):
		for x: int in range(CANVAS):
			if a.get_pixel(x, y).a > 0.0 and b.get_pixel(x, y).a > 0.0:
				count += 1
	return count


func _merge(into: Image, from: Image) -> void:
	for y: int in range(CANVAS):
		for x: int in range(CANVAS):
			if from.get_pixel(x, y).a > 0.0:
				into.set_pixel(x, y, INK)


## Draws the outline for [param slot] and returns the box a label has to fit
## **inside** it.
##
## The box is the point. Sizing the text to its own length alone was the first
## version and it was wrong in both directions at once: a lone "L" swelled until it
## broke out of the bumper it sits in, and "VIEW" stayed at a width the pill does
## not have. The shape knows how much room it has; the label does not.
func _outline(image: Image, slot: String) -> Rect2:
	if SHOULDER.has(slot):
		_round_rect(image, Rect2(4, 10, 40, 28), 8.0, 3.0)
		# Inset well past the corner radius: a rounded box's *corners* are the part
		# a centred label reaches first, not its sides.
		return Rect2(10, 15, 28, 18)
	if BADGE.has(slot):
		# The widest label in the set lands here — "VIEW", "MENU" — so the pill is
		# the biggest shape drawn, and its box is inset well clear of the rounded
		# ends rather than of the bounding rectangle it does not fill.
		_round_rect(image, Rect2(1, 12, 46, 24), 12.0, 3.0)
		return Rect2(9, 15, 30, 18)
	# Face buttons, sticks, and anything new: a ring. The box is the square that
	# fits inside it with the stroke allowed for, not the ring's own diameter.
	_ring(image, Vector2(24, 24), 21.0, 3.0)
	return Rect2(11, 11, 26, 26)


## The four buttons a DualSense has instead of letters, and the Switch's two.
func _symbol(image: Image, label: String) -> void:
	match label:
		"✕":
			_line(image, Vector2(13, 13), Vector2(35, 35), 4.5)
			_line(image, Vector2(35, 13), Vector2(13, 35), 4.5)
		"○":
			_ring(image, Vector2(24, 24), 11.0, 4.5)
		"□":
			_round_rect(image, Rect2(13, 13, 22, 22), 2.0, 4.5)
		"△":
			_line(image, Vector2(24, 11), Vector2(35, 34), 4.5)
			_line(image, Vector2(35, 34), Vector2(13, 34), 4.5)
			_line(image, Vector2(13, 34), Vector2(24, 11), 4.5)
		"−":
			_line(image, Vector2(13, 24), Vector2(35, 24), 5.0)
		"+":
			_line(image, Vector2(13, 24), Vector2(35, 24), 5.0)
			_line(image, Vector2(24, 13), Vector2(24, 35), 5.0)


## A cross on a round plate.
##
## The cross alone was the first version, and on a Switch pad it came out as the
## same silhouette as `start` — which is a `+`. Two buttons that look identical is
## the exact failure §11.4 is about, so the plate is not decoration: it is the
## thing that tells them apart at a glance.
func _dpad(image: Image) -> void:
	_ring(image, Vector2(24, 24), 21.0, 3.0)
	_fill_rect(image, Rect2(19.5, 10, 9, 28))
	_fill_rect(image, Rect2(10, 19.5, 28, 9))


func _short(label: String) -> String:
	if SHORT.has(label):
		return str(SHORT[label])
	var out := ""
	for c: String in label.to_upper():
		if FONT.has(c):
			out += c
	return out.substr(0, 4)


func _text(image: Image, label: String, box: Rect2) -> void:
	if label == "":
		return
	# 3 cells per character, one between: the gap is a cell so the whole word
	# scales as one thing rather than crowding at four letters. The cell is then
	# whatever both the box's width and its height allow — never less than 1, or a
	# long label in a short shape would render as nothing at all.
	var cells_wide: int = label.length() * 4 - 1
	var cell: int = maxi(1, mini(
		int(box.size.x) / cells_wide, int(box.size.y) / 5))
	var width: float = float(cells_wide * cell)
	var x: float = box.position.x + (box.size.x - width) / 2.0
	var y: float = box.position.y + (box.size.y - float(5 * cell)) / 2.0
	for c: String in label:
		var rows: Array = FONT[c]
		for row: int in range(5):
			var bits: String = rows[row]
			for col: int in range(3):
				if bits[col] == "#":
					_fill_rect(image, Rect2(
						x + float(col * cell), y + float(row * cell),
						float(cell), float(cell)))
		x += float(4 * cell)


# --- primitives ----------------------------------------------------------------
#
# Each walks the whole supersampled canvas once. 192² is 36 000 tests and this runs
# 52 times offline, so clarity beats a bounding box.

func _ring(image: Image, centre: Vector2, radius: float, width: float) -> void:
	for y: int in range(CANVAS):
		for x: int in range(CANVAS):
			if absf(_at(x, y).distance_to(centre) - radius) <= width / 2.0:
				image.set_pixel(x, y, INK)


func _round_rect(image: Image, rect: Rect2, corner: float, width: float) -> void:
	var centre: Vector2 = rect.position + rect.size / 2.0
	var half: Vector2 = rect.size / 2.0 - Vector2(corner, corner)
	for y: int in range(CANVAS):
		for x: int in range(CANVAS):
			var d: Vector2 = (_at(x, y) - centre).abs() - half
			var outside: Vector2 = Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0))
			var signed: float = outside.length() + minf(maxf(d.x, d.y), 0.0) - corner
			if absf(signed) <= width / 2.0:
				image.set_pixel(x, y, INK)


func _line(image: Image, a: Vector2, b: Vector2, width: float) -> void:
	var span: Vector2 = b - a
	var length_sq: float = span.length_squared()
	for y: int in range(CANVAS):
		for x: int in range(CANVAS):
			var p: Vector2 = _at(x, y)
			var t: float = 0.0 if length_sq == 0.0 \
				else clampf((p - a).dot(span) / length_sq, 0.0, 1.0)
			if p.distance_to(a + span * t) <= width / 2.0:
				image.set_pixel(x, y, INK)


func _fill_rect(image: Image, rect: Rect2) -> void:
	var from := Vector2i((rect.position * float(SS)).round())
	var to := Vector2i(((rect.position + rect.size) * float(SS)).round())
	for y: int in range(maxi(from.y, 0), mini(to.y, CANVAS)):
		for x: int in range(maxi(from.x, 0), mini(to.x, CANVAS)):
			image.set_pixel(x, y, INK)


## The centre of canvas pixel [param x],[param y] in 48 px space.
func _at(x: int, y: int) -> Vector2:
	return Vector2(float(x) + 0.5, float(y) + 0.5) / float(SS)

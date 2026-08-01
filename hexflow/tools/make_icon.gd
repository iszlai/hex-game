extends SceneTree
## Cuts the application icon out of `assets/art/logo.png`, and the output is
## **committed** — the same arrangement as `make art` and `make marks`.
##
## The window and dock icon used to be Godot's, because `application/config/icon`
## was never set: the project had a logo and no icon, which are not the same file.
## A logo is read at 1024 px and an icon is recognised at 32, so the icon is the
## one element of the logo that survives being shrunk to a tab — with the border,
## the title lettering and the landscape cropped away. All of that is legible at
## full size and none of it survives the dock (C-31).
##
## Derived rather than drawn, so an illustrator who replaces `logo.png` re-runs
## this and is done. If the composition moves, the three numbers below are what
## there is to retune — and they *do* move: the crop was the middle 55% while the
## logo was a hex cluster centred in its frame, and the campfire it now points at
## is neither centred nor that big.
##
## Run: godot --headless --path . -s res://tools/make_icon.gd

const SOURCE := "res://assets/art/logo.png"
const OUT_DIR := "res://assets/icons/"
const OUT := OUT_DIR + "icon.png"

## The fraction of the source's shorter side the icon keeps, and where that square
## sits relative to the middle of the image, as a fraction of the full size.
##
## The subject is the **campfire**: at 32 px a fire is a bright warm blob against
## dark stone, which is the one thing in this logo that still reads as something
## rather than as texture. The lettering is the obvious alternative and is the
## wrong one — a word cropped to a square becomes two letters, and two letters of
## a name nobody knows yet is not a mark.
##
## The square is deliberately tight. A wider one reaches the title above and the
## frame's branches to the left, and both arrive as noise at icon size.
const CROP := 0.32
const CROP_OFFSET_X := -0.10
const CROP_OFFSET_Y := 0.205

## 256 is the largest size any of the three platforms asks a PNG for, and Godot
## downsamples it for the window and the dock. Below 128 the engine warns.
const SIZE := 256


func _init() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if source == null:
		push_error("no %s — run `make art` or put the logo back" % SOURCE)
		quit(1)
		return

	var side: int = int(mini(source.get_width(), source.get_height()) * CROP)
	var region := Rect2i(
		int((source.get_width() - side) / 2 + source.get_width() * CROP_OFFSET_X),
		int((source.get_height() - side) / 2 + source.get_height() * CROP_OFFSET_Y),
		side, side
	)
	var icon := source.get_region(region)
	# LANCZOS rather than the default: this is one big downsample, which is
	# precisely the case bilinear turns to mush.
	icon.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var err := icon.save_png(ProjectSettings.globalize_path(OUT))
	if err != OK:
		push_error("could not write %s: %d" % [OUT, err])
		quit(1)
		return
	print("wrote %s (%d×%d, from a %d px crop of the logo)" % [OUT, SIZE, SIZE, side])
	quit(0)

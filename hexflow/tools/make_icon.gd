extends SceneTree
## Cuts the application icon out of `assets/art/logo.png`, and the output is
## **committed** — the same arrangement as `make art` and `make marks`.
##
## The window and dock icon used to be Godot's, because `application/config/icon`
## was never set: the project had a logo and no icon, which are not the same file.
## A logo is read at 1024 px and an icon is recognised at 32, so the icon is the
## logo's *middle* — the hex cluster and the cairn on it — with the border, the
## title lettering and the trees cropped away. All of that is legible at full size
## and none of it survives the dock (C-31).
##
## Derived rather than drawn, so an illustrator who replaces `logo.png` re-runs
## this and is done. If the composition ever moves, [constant CROP] is the one
## number to retune.
##
## Run: godot --headless --path . -s res://tools/make_icon.gd

const SOURCE := "res://assets/art/logo.png"
const OUT_DIR := "res://assets/icons/"
const OUT := OUT_DIR + "icon.png"

## The fraction of the source's width and height the icon keeps, centred. The
## logo's frame and lettering occupy the outer third; the hex cluster sits inside
## the middle 55%, a little low in the frame, so the crop is nudged down to centre
## on the cluster rather than on the image.
const CROP := 0.55
const CROP_OFFSET_Y := 0.03

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
		(source.get_width() - side) / 2,
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

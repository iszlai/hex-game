extends SceneTree
## Makes the application icon out of `assets/art/logo.png`, and the output is
## **committed** — the same arrangement as `make art` and `make marks`.
##
## The window and dock icon used to be Godot's, because `application/config/icon`
## was never set: the project had a logo and no icon, which are not the same file.
##
## This used to cut a tight square out of the campfire and throw the rest away, on
## the argument that a logo is read at 1024 px and an icon is recognised at 32, so
## only one element of the picture can survive the dock. That is a fair argument
## about a *wide* logo with a word across it — and this logo is not one. It is
## already square, the lettering is the biggest thing in it, and the framed scene
## reads at a glance. Cropping it produced an icon nobody could tell was this game:
## a fire on some rocks, with the name deleted.
##
## So the icon is the whole logo now. It keeps the name, which is what makes a
## taskbar entry findable, and the fire is still the brightest thing in it at any
## size.
##
## Derived rather than drawn, so an illustrator who replaces `logo.png` re-runs
## this and is done.
##
## Run: godot --headless --path . -s res://tools/make_icon.gd

const SOURCE := "res://assets/art/logo.png"
const OUT_DIR := "res://assets/icons/"
const OUT := OUT_DIR + "icon.png"

## How much of each edge is dropped, as a fraction of the source's side.
##
## Not a crop of the composition — a trim of the dead space around it. The logo is
## painted with a soft vignette outside its branch frame, and an icon is a small
## square with a hard edge: every pixel of that margin is a pixel the picture is
## not using. Small enough that the frame's corners survive, because the frame is
## what stops the icon reading as a screenshot.
const TRIM := 0.08

## 512 rather than 256: macOS wants 512 for a retina dock, every platform
## downsamples happily, and this stays one committed file rather than a size per
## target. Below 128 the engine warns.
const SIZE := 512


func _init() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if source == null:
		push_error("no %s — run `make art` or put the logo back" % SOURCE)
		quit(1)
		return

	# The square the icon keeps: the whole picture less its margin, centred. Sized
	# off the shorter side, so a logo that is not square loses its overhang rather
	# than being squashed into the frame.
	var side: int = int(mini(source.get_width(), source.get_height()) * (1.0 - TRIM * 2.0))
	var region := Rect2i(
		int((source.get_width() - side) / 2),
		int((source.get_height() - side) / 2),
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
	print("wrote %s (%d×%d, the logo less a %d%% margin)" % [OUT, SIZE, SIZE, int(TRIM * 100.0)])
	quit(0)

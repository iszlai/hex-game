extends SceneTree
## Not a Godot tool — a note about one that is not.
##
## The six beds in `assets/music/` were cut from a single 2:45 source with
## `ffmpeg`, because Godot cannot encode Vorbis and shelling out to a codec from a
## `SceneTree` script would be a build dependency this repo does not want.
##
## The command that made them, kept here so the next batch is reproducible:
##
##   for each (name, start) in
##       menu 0 · chapter_1 22 · chapter_2 45 · chapter_3 68 · chapter_4 91 · chapter_5 114
##
##   ffmpeg -i SOURCE.wav -filter_complex "
##       [0:a]atrim=start=S:duration=45,asetpts=N/SR/TB[a];
##       [0:a]atrim=start=S+45:duration=3,asetpts=N/SR/TB[b];
##       [0:a]atrim=start=S:duration=3,asetpts=N/SR/TB[c];
##       [b][c]amix=inputs=2:duration=shortest[x];
##       [a][x]concat=n=2:v=0:a=1[out]"
##     -map "[out]" -c:a vorbis -strict -2 -q:a 5 -ar 44100 assets/music/NAME.ogg
##
## The last three lines of the filter are what makes the loop seamless: the final
## three seconds are mixed over the first three, so the end of the window already
## contains the beginning and the seam has nothing to click on.
##
## Windows overlap on purpose. §15.1 asks for 2–3 minute loops and a 2:45 source
## cannot yield six of those; six 27-second slices would loop audibly. Overlapping
## 48-second windows give each chapter its own material while staying long enough
## not to nag.
##
## **What is still owed:** §15.1's second stem. Each chapter wants a `base` that
## always plays and a `layer` that fades in above 40% board fill — that is two
## *separately rendered* parts, and a single mixed track cannot be split into them.
## It needs the composer, not a cut.


func _initialize() -> void:
	print("see the comment at the top of tools/make_music.gd")
	quit()

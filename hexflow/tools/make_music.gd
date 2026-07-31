extends SceneTree
## Not a Godot tool — a note about one that is not.
##
## The six beds in `assets/music/` were cut from a single 2:45 source with
## `ffmpeg`, because Godot cannot encode Vorbis and shelling out to a codec from a
## `SceneTree` script would be a build dependency this repo does not want.
##
## The command that made them, kept here so the next batch is reproducible:
##
##   source A = "Focus Quest - Main Menu.wav"          (165.6 s)
##   source B = "Focus Quest - Main Menu (Remix).wav"  (178.9 s)
##
##   menu       B @ 0     chapter_1  A @ 10    chapter_2  A @ 55
##   chapter_3  A @ 100   chapter_4  B @ 60    chapter_5  B @ 118
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
## The menu takes its own piece rather than a window of the chapters' one, because
## §15.1 asks for "5 chapter beds + menu track" — six *tracks*, and six windows of
## one recording is one track wearing six hats. The later chapters take the remix
## for the same reason: a playthrough should not sit on one loop for an hour.
##
## **What is still owed:** §15.1's second stem. Each chapter wants a `base` that
## always plays and a `layer` that fades in above 40% board fill.
##
## The remix cannot be that layer, and the reason is worth writing down so nobody
## tries it again: it is 178.9 s against the original's 165.6 s, so it is an
## independent render rather than a stem of the same performance. Two independent
## renders played together do not layer — they phase, drift and fight, because
## nothing makes their bars line up. A stem pair has to come out of one session
## with one clock: the same piece exported twice, once with the pads muted.
##
## Which is also the thing to ask for next: not another variation, but a
## **pads-only export of a track that already exists**.


func _initialize() -> void:
	print("see the comment at the top of tools/make_music.gd")
	quit()

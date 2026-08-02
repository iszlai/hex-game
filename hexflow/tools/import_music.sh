#!/usr/bin/env bash
# Check hand-made music exports and install them into the game.
#
# Reads WAV/AIFF stems from drafts/music/wav/, verifies the things that are easy
# to get wrong in a DAW and impossible to notice afterwards, then encodes to Ogg
# Vorbis in assets/music/. See docs/MUSIC-HANDOFF.md — this script is §7, §8 and
# most of §10 in one command.
#
#     tools/import_music.sh            # every track found
#     tools/import_music.sh menu       # one track
#     CHECK_ONLY=1 tools/import_music.sh   # verify, encode nothing
#
# It refuses rather than warns. A stem that is one sample longer than its
# siblings drifts out of phase over a two-minute loop, and that is not something
# a listener reports as "the music is slightly wrong".

set -euo pipefail

# Every number here is parsed as well as printed, and a locale that writes 3,0 for
# three-and-a-bit turns "%.1f" into something awk will not read back. This script
# talks to ffmpeg, not to a person's spreadsheet.
export LC_ALL=C

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$here/drafts/music/wav"
dst="$here/assets/music"

# §3's table. 48 bars of 4/4 is 192 beats, so the expected length follows from
# the tempo — which is the check that catches GarageBand quietly ignoring the
# MIDI's tempo, and catches a cycle region set over the wrong bars.
tempo_of() {
  case "$1" in
    menu|chapter_1) echo 70 ;;
    chapter_2|chapter_3) echo 72 ;;
    chapter_4) echo 74 ;;
    chapter_5) echo 76 ;;
    *) echo "" ;;
  esac
}

TRACKS="menu chapter_1 chapter_2 chapter_3 chapter_4 chapter_5"
STEMS="base layer extra"

command -v ffmpeg >/dev/null || { echo "needs ffmpeg on PATH"; exit 1; }

# Godot cannot write Vorbis, so this is the encoder either way — but which one is
# available depends on how the local ffmpeg was built. Homebrew's has shipped both
# with and without libvorbis; the built-in encoder is always there and is what the
# Makefile's `music` target already uses.
if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q ' libvorbis'; then
  VORBIS="-c:a libvorbis -q:a 4"
else
  VORBIS="-c:a vorbis -strict -2 -q:a 3"
fi

fail=0
note() { printf '  %s\n' "$*"; }
bad()  { printf '  ✗ %s\n' "$*"; fail=1; }
ok()   { printf '  ✓ %s\n' "$*"; }

# Locate a stem's source file, whatever the DAW called the extension.
find_stem() {
  local track=$1 stem=$2 f
  for f in "$src/${track}_${stem}".wav "$src/${track}_${stem}".aif \
           "$src/${track}_${stem}".aiff "$src/${track}_${stem}".WAV; do
    [ -f "$f" ] && { echo "$f"; return 0; }
  done
  return 1
}

samples_of() {
  local ts rate
  ts=$(ffprobe -v error -select_streams a:0 -show_entries stream=duration_ts \
       -of csv=p=0 "$1")
  rate=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate \
         -of csv=p=0 "$1")
  echo "$ts $rate"
}

# Integrated loudness and true peak of any number of inputs mixed together,
# which is how the player hears them. normalize=0 keeps amix from scaling the
# sum down and reporting a level nobody will hear.
## A sample count as bars, to one decimal — for talking to a person about a file.
bars_of() {
  awk -v n="$1" -v b="$bar_samples" 'BEGIN{printf "%.1f", n/b}'
}

## Integrated loudness of one file, or nothing if there is no file.
loudness_of() {
  [ -n "${1:-}" ] && [ -f "${1:-}" ] || return 0
  ffmpeg -hide_banner -nostats -i "$1" -af ebur128 -f null - 2>&1 \
    | tail -14 | sed -n 's/.*I: *\(-*[0-9.]*\).*/\1/p' | tail -1
}

measure() {
  local args=() i
  for i in "$@"; do args+=(-i "$i"); done
  ffmpeg -hide_banner -nostats "${args[@]}" \
    -filter_complex "amix=inputs=$#:normalize=0,ebur128=peak=true" \
    -f null - 2>&1 | tail -20
}

for track in ${1:-$TRACKS}; do
  tempo=$(tempo_of "$track")
  [ -n "$tempo" ] || { echo "unknown track: $track"; exit 1; }

  files=()
  missing=()
  for stem in $STEMS; do
    if f=$(find_stem "$track" "$stem"); then files+=("$f"); else missing+=("$stem"); fi
  done

  [ ${#files[@]} -eq 0 ] && continue
  echo "$track"

  if [ ${#missing[@]} -gt 0 ]; then
    # §2: one stem alone is a valid, lesser delivery — but only if it is base.
    if [ ${#files[@]} -eq 1 ] && [ -n "$(find_stem "$track" base || true)" ]; then
      note "base only — the game will play it with no adaptive layer (§2)"
    else
      bad "missing stem(s): ${missing[*]}"
    fi
  fi

  # 48 bars of 4/4 is 192 beats, so the loop's exact length follows from the tempo.
  # Every stem is cut to precisely this, which is what makes them line up.
  expected=$(awk -v t="$tempo" 'BEGIN{printf "%.0f", 192*60/t*44100}')
  bar_samples=$(awk -v t="$tempo" 'BEGIN{printf "%.0f", 4*60/t*44100}')

  # Where the loop starts inside each file, worked out rather than insisted upon.
  #
  # §5 asks for the arrangement played twice with only the second pass exported,
  # because the second pass has the first one's decay already ringing into its
  # first bar — which is exactly what a seamless loop needs and what no amount of
  # cross-fading supplies. Setting a cycle region over bars 49–97 three times
  # without nudging it is, in practice, the hardest step in the whole document.
  #
  # It does not have to be done in the DAW. A whole-song export contains both
  # passes, and the second one starts at a sample position that follows from the
  # tempo — so exporting the lot and taking the back half here is the same audio,
  # arrived at by arithmetic instead of by dragging. Both deliveries are accepted:
  # roughly one loop long means the cycle was set, roughly two means it was not.
  #
  # Either way a DAW appends the tail of whatever was unmuted, so the three files
  # come back three different lengths. All correct — what matters is that they
  # *start* together, and both routes guarantee that.
  starts=()
  for f in "${files[@]}"; do
    read -r ts rate <<<"$(samples_of "$f")"
    [ "$rate" = "44100" ] || bad "$(basename "$f"): ${rate} Hz, needs 44100"

    if [ "$ts" -ge $(( 2 * expected - 4410 )) ]; then
      start=$expected
      whole="both passes — taking the second"
    else
      start=0
      whole="cycle area"
    fi
    starts+=("$start")

    have=$(( ts - start ))
    if [ "$have" -lt $(( expected - 4410 )) ]; then
      bad "$(basename "$f"): only $(bars_of $have) bars after the loop point, need 48 at ${tempo} BPM"
      note "check the project tempo — GarageBand starts at 120 and often ignores the file's"
      continue
    fi

    excess=$(( have - expected ))
    if [ "$excess" -le 4410 ]; then
      ok "$(basename "$f"): 48 bars at ${tempo} BPM, ${whole}"
      continue
    fi
    # Whatever is being cut has to be a tail. If it is as loud as the music, the
    # arrangement is not the length this expects and real bars would be discarded.
    # The field after the colon, and only that: `grep -o` on the whole line also
    # matches the digits in ffmpeg's filter address and its timestamps.
    tail_peak=$(ffmpeg -hide_banner -nostats -i "$f" \
      -af "atrim=start_sample=$(( start + expected )),astats=metadata=1:reset=0" \
      -f null - 2>&1 \
      | sed -n 's/.*Peak level dB: *\(-*[0-9.]*\|-inf\)$/\1/p' | tail -1)
    [ -n "$tail_peak" ] || tail_peak="-inf"
    if [ "$tail_peak" != "-inf" ] && awk -v p="$tail_peak" 'BEGIN{exit !(p > -12.0)}'; then
      bad "$(basename "$f"): $(bars_of $excess) bars past the loop peaking at ${tail_peak} dB — too loud to be a tail"
      note "the arrangement is not 48 bars, or is not doubled; music would be cut off"
    else
      ok "$(basename "$f"): 48 bars at ${tempo} BPM, ${whole}, $(bars_of $excess) bars of tail trimmed"
    fi
  done

  # Everything from here works on the trimmed copies, so what is measured is what
  # the game will actually play.
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  trimmed=()
  for i in "${!files[@]}"; do
    f="${files[$i]}"
    s="${starts[$i]}"
    t="$work/$(basename "${f%.*}").wav"
    ffmpeg -hide_banner -loglevel error -y -i "$f" \
      -af "atrim=start_sample=${s}:end_sample=$(( s + expected ))" \
      -c:a pcm_s16le -ar 44100 "$t"
    trimmed+=("$t")
  done
  trimmed_stem() {
    local p="$work/${track}_$1.wav"
    [ -f "$p" ] && echo "$p"
  }

  # Did the DAW normalise each export on its own?
  #
  # This is the one failure that survives every other check in this file. The stems
  # are the right length, they line up, they loop, each one sounds correct alone —
  # and the balance between them, which is the only thing three files can get wrong
  # that one file cannot, is gone. GarageBand ships with "Auto Normalize" on by
  # default and it applies to every export, so the `layer` — one quiet instrument,
  # written to sit *under* the bed — is lifted to full scale on its way out and
  # arrives louder than the piano.
  #
  # Two tells, either of which is conclusive:
  peaks=""
  for f in "${trimmed[@]}"; do
    peaks="$peaks $(ffmpeg -hide_banner -nostats -i "$f" -af "astats=metadata=1:reset=0" \
      -f null - 2>&1 | sed -n 's/.*Peak level dB: *\(-*[0-9.]*\)$/\1/p' | tail -1)"
  done
  spread=$(echo "$peaks" | awk '{m=$1;x=$1;for(i=2;i<=NF;i++){if($i<m)m=$i;if($i>x)x=$i}
    printf "%.3f", x-m}')
  if [ ${#trimmed[@]} -gt 1 ] && awk -v s="$spread" 'BEGIN{exit !(s < 0.05)}'; then
    bad "every stem peaks at the same level (within ${spread} dB) — they were normalised separately"
    note "GarageBand ▸ Settings ▸ Advanced ▸ untick \"Auto Normalize\", then export all three again"
  fi

  # Is the layer actually going to be audible when it arrives?
  #
  # Not a loudness check — a *balance* one, and the only thing here that judges the
  # mix rather than the file. The `layer` fades in mid-level and is the game's main
  # signal that a run is getting somewhere; buried, the adaptive half of §15.1 is
  # built, shipped, and silent, which is the state it spent most of its life in.
  #
  # The brief says the melody sits under the bed, and it is easy to read that as
  # "as far under as possible". The composed beds put it about 5 LU down. Past
  # about 8 the fade-in stops registering as an event.
  #
  # It reports rather than instructs, and never fails. Where exactly the melody
  # sits is the composer's to decide and they may well have decided it; the number
  # is here so that decision is made with it in view rather than by accident.
  lb=$(loudness_of "$(trimmed_stem base || true)")
  ll=$(loudness_of "$(trimmed_stem layer || true)")
  if [ -n "$lb" ] && [ -n "$ll" ]; then
    drop=$(awk -v b="$lb" -v l="$ll" 'BEGIN{printf "%.1f", b-l}')
    if awk -v d="$drop" 'BEGIN{exit !(d > 8.0)}'; then
      note "layer sits ${drop} LU under the bed; the composed beds use about 5"
    else
      ok "layer sits ${drop} LU under the bed"
    fi
  fi

  # §7's levels, reached the way tools/make_music.gd reaches them: **one** gain,
  # applied to all three stems.
  #
  # Not one gain per stem. `base` and `layer` do not have the same energy and are
  # not meant to — the bed is louder than the tune. Normalising them separately
  # would make them equal, which is not a level correction, it is a remix.
  #
  # So a mix that came back a few decibels hot is not something to send back to the
  # DAW. Everything here is linear: scaling three files by one factor changes
  # nothing about their balance, their timing or their phase.
  b=$(trimmed_stem base || true)
  l=$(trimmed_stem layer || true)
  peak=$(measure "${trimmed[@]}" | sed -n 's/.*Peak: *\(-*[0-9.]*\).*/\1/p' | tail -1)
  gain=0
  if [ -n "$b" ] && [ -n "$l" ]; then
    lufs=$(measure "$b" "$l" | sed -n 's/.*I: *\(-*[0-9.]*\).*/\1/p' | tail -1)
    gain=$(awk -v v="$lufs" 'BEGIN{printf "%.2f", -16.0 - v}')
    note "base+layer measures ${lufs} LUFS, true peak ${peak} dBTP"
  else
    note "no layer yet — loudness needs base+layer, so only the peak is being held"
  fi
  # §7's ceiling wins over its loudness target: a bed a decibel quiet is nobody's
  # problem and a clipped one is everybody's. −1.5 rather than −1 leaves the Vorbis
  # encoder room to overshoot a sample peak on the way out.
  cap=$(awk -v p="$peak" 'BEGIN{printf "%.2f", -1.5 - p}')
  if awk -v g="$gain" -v c="$cap" 'BEGIN{exit !(g > c)}'; then
    note "held down by the peak ceiling rather than the loudness target"
    gain=$cap
  fi
  ok "applying ${gain} dB to all three stems"

  if [ "$fail" = 0 ] && [ -z "${CHECK_ONLY:-}" ]; then
    for f in "${trimmed[@]}"; do
      out="$dst/$(basename "${f%.*}").ogg"
      ffmpeg -hide_banner -loglevel error -y -i "$f" \
        -af "volume=${gain}dB" $VORBIS -ar 44100 "$out"
      ok "→ ${out#$here/}"
    done
  fi
  rm -rf "$work"; trap - EXIT
done

if [ "$fail" != 0 ]; then
  echo
  echo "nothing was installed. Fix the above and run again."
  exit 1
fi

echo
if [ -n "${CHECK_ONLY:-}" ]; then
  echo "checks passed. Drop CHECK_ONLY to encode."
else
  echo "run 'make import' then 'make run' to hear them in the game."
fi

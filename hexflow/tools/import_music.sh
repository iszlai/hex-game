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

  # Same length to the sample (§10). Compared against base when present.
  expected=$(awk -v t="$tempo" 'BEGIN{printf "%.0f", 192*60/t*44100}')
  ref=""
  for f in "${files[@]}"; do
    read -r ts rate <<<"$(samples_of "$f")"
    [ "$rate" = "44100" ] || bad "$(basename "$f"): ${rate} Hz, needs 44100"
    if [ -z "$ref" ]; then ref=$ts; ref_name=$(basename "$f"); fi
    if [ "$ts" != "$ref" ]; then
      bad "$(basename "$f"): $ts samples, but $ref_name has $ref — stems must match exactly"
    fi
  done

  drift=$(( ref > expected ? ref - expected : expected - ref ))
  if [ "$drift" -gt 4410 ]; then
    bad "length $ref samples, expected ~$expected for 48 bars at ${tempo} BPM"
    note "check the project tempo and that the cycle area covers bars 49–96 (§5)"
  else
    ok "48 bars at ${tempo} BPM, $ref samples, stems aligned"
  fi

  # §7's levels. base+layer for loudness, all three for peak.
  b=$(find_stem "$track" base || true)
  l=$(find_stem "$track" layer || true)
  if [ -n "$b" ] && [ -n "$l" ]; then
    sum=$(measure "$b" "$l")
    lufs=$(echo "$sum" | grep -oE 'I: *-?[0-9.]+' | tail -1 | grep -oE '\-?[0-9.]+')
    [ -n "$lufs" ] && {
      off=$(awk -v v="$lufs" 'BEGIN{d=v+16; print (d<0?-d:d)}')
      if awk -v o="$off" 'BEGIN{exit !(o>2.0)}'; then
        bad "base+layer is ${lufs} LUFS, target −16 (±2)"
      else
        ok "base+layer ${lufs} LUFS"
      fi
    }
  fi
  peaksum=$(measure "${files[@]}")
  peak=$(echo "$peaksum" | grep -oE 'Peak: *-?[0-9.]+' | tail -1 | grep -oE '\-?[0-9.]+')
  [ -n "$peak" ] && {
    if awk -v p="$peak" 'BEGIN{exit !(p > -1.0)}'; then
      bad "true peak ${peak} dBTP, must stay under −1"
    else
      ok "true peak ${peak} dBTP"
    fi
  }

  if [ "$fail" = 0 ] && [ -z "${CHECK_ONLY:-}" ]; then
    for f in "${files[@]}"; do
      out="$dst/$(basename "${f%.*}").ogg"
      ffmpeg -hide_banner -loglevel error -y -i "$f" \
        -c:a libvorbis -q:a 4 -ar 44100 "$out"
      ok "→ ${out#$here/}"
    done
  fi
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

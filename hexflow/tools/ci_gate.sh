#!/usr/bin/env bash
# The push gate of §24.3. A push is red if any of these fail.
#
# Usage: GODOT=/path/to/Godot ./tools/ci_gate.sh
set -uo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
status=0

fail() { echo "GATE FAILED: $*" >&2; status=1; }

# Scans GDScript for a pattern, ignoring comments — a rule stated in a doc
# comment must not trip the rule it documents. POSIX ERE, so no \b: guard word
# boundaries with [^_[:alnum:]] explicitly.
scan() {
  local dir="$1" pattern="$2"
  find "$dir" -name '*.gd' -print0 \
    | xargs -0 awk -v RE="$pattern" '{ sub(/#.*/, ""); if ($0 ~ RE) printf "%s:%d:%s\n", FILENAME, FNR, $0 }'
}

echo "== §19 determinism: no global RNG in src/ =="
# Only TileStream and Generator may own a RandomNumberGenerator, and both are
# seeded explicitly. Global randi()/randf()/randomize() are banned.
hits=$(scan src '(^|[^_[:alnum:].])(randi|randf|randi_range|randf_range|randomize)[(]')
if [ -n "$hits" ]; then echo "$hits"; fail "global RNG call in src/ (§19, C2)"; fi

echo "== §19 integer logic: no floats in src/core/ =="
hits=$(scan src/core '(: *float|-> *float|(^|[^_[:alnum:].])(float|lerpf|sqrt|cos|sin|deg_to_rad)[(])')
if [ -n "$hits" ]; then echo "$hits"; fail "float arithmetic in src/core/ (§19)"; fi

echo "== C1 layering: src/core/ touches no node, scene, texture or Input API =="
hits=$(scan src/core '(^|[^_[:alnum:].])(Node|Node2D|Control|Input|InputEvent|Texture|PackedScene|Viewport|get_tree|get_node|queue_redraw)([^_[:alnum:]]|$)')
if [ -n "$hits" ]; then echo "$hits"; fail "engine dependency in src/core/ (C1)"; fi

echo "== §13.2 palette: no colour outside the palette =="
# Two ways a colour gets hardcoded in practice. In scenes, any colour property;
# in scripts, a hex literal. The float form is *not* scanned in scripts, because
# `MultiMesh.set_instance_custom_data` takes a `Color` that is not a colour at all
# — it is four floats of per-instance state, and the board pushes three of those.
hits=$(grep -rn "= Color(" --include="*.tscn" src 2>/dev/null)
if [ -n "$hits" ]; then echo "$hits"; fail "colour literal in a scene (§13.2, §21)"; fi
hits=$(scan src 'Color[(]"' | grep -v 'src/view/palette.gd')
if [ -n "$hits" ]; then echo "$hits"; fail "hex colour literal outside palette.gd (§13.2, §21)"; fi

echo "== §16.5 autoloads: exactly six =="
count=$(sed -n '/^\[autoload\]/,/^\[[a-z]/p' project.godot | grep -cE '^[A-Za-z][A-Za-z0-9_]*=')
if [ "$count" -ne 6 ]; then fail "expected 6 autoloads, found $count (§16.5)"; fi

echo "== §22 localization: no literal UI strings in scene files =="
# Permissive until the M10 string extraction: once assets/i18n/en.csv exists,
# every player-visible string must be a key, not a literal.
if [ -f assets/i18n/en.csv ]; then
  hits=$(grep -rn 'text = "' src/scenes/ src/ui/ 2>/dev/null | grep -v 'text = ""')
  if [ -n "$hits" ]; then echo "$hits"; fail "literal UI string in a scene (§22)"; fi
else
  echo "   skipped: assets/i18n/en.csv does not exist yet (M10)"
fi

echo "== tests: @core, @property, @e2e =="
out=$("$GODOT" --headless -s res://addons/gut/gut_cmdln.gd \
    -gdir=res://tests -ginclude_subdirs -gexit -gprefix=test_ 2>&1)
echo "$out" | grep -E "^(Scripts|Tests|Passing|Failing|Asserts|Time) " || true
if ! echo "$out" | grep -q "All tests passed"; then
  echo "$out" | grep -E "\[Failed\]" | head -40
  fail "test suite red"
fi

echo "== headless boot smoke test =="
boot=$("$GODOT" --headless --path . --quit-after 120 2>&1)
if echo "$boot" | grep -q "SCRIPT ERROR"; then
  echo "$boot" | grep -A2 "SCRIPT ERROR" | head -20
  fail "boot produced a script error"
fi

if [ "$status" -eq 0 ]; then
  echo
  echo "ALL GATES GREEN"
fi
exit "$status"

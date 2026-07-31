#!/usr/bin/env bash
# The suite, run as one Godot process per test script, several at a time.
#
# The gate used to spend 103 s of wall clock on 101 s of tests, almost all of it
# one core waiting on another. Nothing in the suite reads another test's output,
# so the only thing making it serial was the single engine process. This runs a
# pool instead.
#
# Two things have to be true for that to be safe, and both are arranged here:
#
#   * `user://` is per process. Tests write real save files on purpose —
#     `tests/e2e/test_persistence.gd` corrupts one to prove the recovery path —
#     and eight processes sharing one save directory is a flake generator. Godot
#     resolves `user://` underneath `$HOME`, so each script gets its own.
#   * `.godot/` is imported once, before the fan-out, by a single process. After
#     that the workers only read it; letting eight of them race to build the
#     import cache is how you get a corrupt one.
#
# Scripts are dispatched slowest-group-first — property, then e2e, then unit —
# because a pool's wall time is set by when its longest job *starts*, not by the
# order of the queue.
#
# Usage: GODOT=/path/to/godot ./tools/run_tests.sh [tests/unit tests/e2e ...]
#        JOBS=4 ./tools/run_tests.sh          # override the pool size
set -uo pipefail

# Absolute, because the pool `cd`s into the project before dispatching back here.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
GODOT="${GODOT:-godot}"
GUT_ARGS=(--headless -s res://addons/gut/gut_cmdln.gd -gexit -gprefix=test_)

# --- the worker ----------------------------------------------------------------
# Re-entry point: the pool dispatches back into this same script, one test script
# per invocation, which saves exporting a shell function through xargs.
if [ "${1:-}" = "--one" ]; then
  script="$2"
  home="$(mktemp -d)"
  trap 'rm -rf "$home"' EXIT
  HOME="$home" XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" \
    XDG_CACHE_HOME="$home/cache" \
    "$GODOT" "${GUT_ARGS[@]}" -gtest="res://$script" \
    > "$RUN_TESTS_LOGS/$(echo "$script" | tr / _).log" 2>&1
  code=$?
  if [ "$code" -eq 0 ]; then echo "  ok    $script"; else echo "  FAIL  $script"; fi
  exit "$code"
fi

# --- the pool ------------------------------------------------------------------
cd "$(dirname "$0")/.."

JOBS="${JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"
dirs=("$@")
[ "${#dirs[@]}" -eq 0 ] && dirs=(tests)

RUN_TESTS_LOGS="$(mktemp -d)"
export RUN_TESTS_LOGS GODOT
trap 'rm -rf "$RUN_TESTS_LOGS"' EXIT

# One process builds the import cache; the pool then only reads it.
"$GODOT" --headless --import >/dev/null 2>&1

# Longest group first. `sort -u` keeps an explicit `tests/property tests` from
# running the same script twice.
scripts=$(
  for group in property e2e unit; do
    for dir in "${dirs[@]}"; do
      find "$dir" -path "*/$group/*" -name 'test_*.gd' 2>/dev/null
    done
  done | awk '!seen[$0]++'
)
[ -z "$scripts" ] && { echo "no test scripts under: ${dirs[*]}" >&2; exit 1; }

echo "$scripts" | xargs -P "$JOBS" -I{} "$SELF" --one {}
pool=$?

# --- the summary ---------------------------------------------------------------
# One set of totals rather than fifty-four, so the output still reads like a
# single run of the suite.
awk '
  /^Tests +[0-9]+$/         { tests   += $2 }
  /^Passing Tests +[0-9]+$/ { passing += $3 }
  /^Failing Tests +[0-9]+$/ { failing += $3 }
  /^Pending +[0-9]+$/       { pending += $2 }
  END {
    printf "Scripts %d   Tests %d   Passing %d   Failing %d   Pending %d\n",
      scripts, tests, passing, failing, pending
  }
' scripts="$(echo "$scripts" | wc -l | tr -d ' ')" "$RUN_TESTS_LOGS"/*.log

if [ "$pool" -ne 0 ]; then
  # A failing script's own output, so a red pool says *why* without a re-run.
  for log in "$RUN_TESTS_LOGS"/*.log; do
    grep -q "All tests passed" "$log" && continue
    echo
    echo "--- $(basename "$log" .log | tr _ /) ---"
    grep -E "\[Failed\]|SCRIPT ERROR|^ *at line" "$log" | head -20
  done
  exit 1
fi

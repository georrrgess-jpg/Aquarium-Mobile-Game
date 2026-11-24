#!/usr/bin/env bash
# Headless rules tests (no display needed). GODOT=/path/to/godot dev/run_tests.sh
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
rc=0
for t in test_core test_reef test_tide; do
  [ -f "tests/$t.gd" ] || continue
  out=$("$GODOT" --headless --path . --script "res://tests/$t.gd" 2>&1 | grep -v -E "ALSA|audio_driver|dummy driver|initialize \(servers|^$|Godot Engine") || true
  echo "$out"
  # engine script errors abort a test silently, so they count as failures too
  if echo "$out" | grep -q -E "SCRIPT ERROR|Parse Error|FAIL"; then rc=1; fi
done
exit $rc

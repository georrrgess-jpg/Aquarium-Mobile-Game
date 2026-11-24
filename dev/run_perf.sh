#!/usr/bin/env bash
# Run the identical benchmark on the current tree and (optionally) on a baseline checkout.
#   GODOT=/path/to/godot dev/run_perf.sh [baseline-dir]      # e.g. a `git worktree` of the Update 1 commit
# Prints headless (script cost, capped at 60 fps) and windowed (software GL under Xvfb) results.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
run_one() {  # dir mode scenario
  local dir="$1" mode="$2" sc="$3"
  ( cd "$dir"
    "$GODOT" --headless --path . --import >/dev/null 2>&1
    if [ "$mode" = headless ]; then
      "$GODOT" --headless --path . -- --playtest=perfbench --scenario="$sc" --save=perf_bench --fresh 2>&1
    else
      xvfb-run -a -s "-screen 0 405x720x24" "$GODOT" --rendering-driver opengl3 --path . --resolution 405x720 -- --playtest=perfbench --scenario="$sc" --save=perf_bench --fresh 2>&1
    fi | grep -E "\[bench\]" )
}
for dir in "${@:-.}"; do
  echo "######## $dir"
  for mode in headless windowed; do
    echo "--- $mode"
    for sc in pool reef; do run_one "$dir" "$mode" "$sc"; done
  done
  echo "--- micro (headless)"
  run_one "$dir" headless micro
done

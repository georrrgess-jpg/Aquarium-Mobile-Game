#!/usr/bin/env bash
# Run the whole UI review (dev/ui_review.gd) at one viewport and print only failures.
#   GODOT=... dev/run_ui_review.sh 405x720 [--safe=48,34]     (default safe area 48,34; screenshots in dev/out/rv_*)
set -uo pipefail
SIZE="${1:-405x720}"; SAFE="${2:---safe=48,34}"
cd "$(dirname "$0")/.."
DAY=(rv_hub_first rv_guided rv_guided_misc rv_hub rv_hub_visitor rv_tides rv_pool rv_toasts rv_flood rv_reduced rv_results
     rv_trial_wrap rv_trial_chain rv_trial_space rv_calm rv_help_done rv_book rv_arrival_long rv_hub_help_tight rv_swell)
run() { # clock, scenarios...
  local clock="$1"; shift
  for s in "$@"; do
    echo "=== $s $SIZE"
    PT_SCRIPT=ui_review dev/run_playtest.sh "$s" "$SIZE" --fresh "$SAFE" --clock="$clock" --tz=0 2>&1 | grep -E "FAIL|SCRIPT ERROR|Parse Error|done:"
  done
}
run 2026-11-24T12:00 "${DAY[@]}"
run 2026-11-24T22:00 rv_night

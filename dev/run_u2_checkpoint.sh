#!/usr/bin/env bash
# Update 2 checkpoint: one real session, then four relaunches with the clock moved forward.
#   GODOT=/path/to/godot dev/run_u2_checkpoint.sh
set -uo pipefail
cd "$(dirname "$0")/.."
export PT_SAVE=pt_u2_checkpoint
UD="$HOME/.local/share/godot/app_userdata/Tidepool Tycoon"
rm -f "${UD:?}/${PT_SAVE:?}.json"
echo "== A: play, Current preview, Surge, releases, buy decoration"
dev/run_playtest.sh u2_checkpoint_a 405x720 --fresh --speed=2 2>&1 | grep -E "playtest\].*(ok|FAIL|done)"
for spec in "1 +3 hours" "2 +20 hours" "3 +45 hours" "4 +46 hours"; do
  set -- $spec; stage=$1; shift
  clk=$(date -u -d "$*" +%Y-%m-%dT%H:%M)
  echo "== relaunch stage $stage at clock $clk (UTC, --tz=0)"
  dev/run_playtest.sh u2_stage 405x720 --stage=$stage --tz=0 --clock=$clk 2>&1 | grep -E "playtest\].*(ok|FAIL|done)"
done
echo "== Update 1 save migration (copied fixture)"
cp tests/fixtures/save_v1_midrun.json "${UD:?}/pt_u2_migrate.json"
PT_SAVE=pt_u2_migrate dev/run_playtest.sh u2_migrate 405x720 --speed=2 2>&1 | grep -E "playtest\].*(ok|FAIL|done)"

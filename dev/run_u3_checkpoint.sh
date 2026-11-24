#!/usr/bin/env bash
# Update 3 checkpoint with the clock moved by launch flags:
#   visitor accepted at 06:30 (A), reopened at 09:00 after the window closed and finished (B),
#   reopened the next day (C); then all earlier saves are opened by the Update 3 build.
#   GODOT=/path/to/godot dev/run_u3_checkpoint.sh
set -uo pipefail
cd "$(dirname "$0")/.."
export PT_SAVE=pt_u3_visitor
UD="$HOME/.local/share/godot/app_userdata/Tidepool Tycoon"
rm -f "${UD:?}/${PT_SAVE:?}.json"
today=$(date -u +%Y-%m-%d); tomorrow=$(date -u -d "+1 day" +%Y-%m-%d)
echo "== A: 06:30, accept the Lantern Ray, make the tier 4 (window still open)"
dev/run_playtest.sh u3_visitor_a 405x720 --fresh --speed=2 --tz=0 --clock=${today}T06:30 2>&1 | grep -E "playtest\].*(ok|FAIL|done)"
echo "== B: relaunch at 09:00 (window closed): finish, ray granted"
dev/run_playtest.sh u3_visitor_b 405x720 --stage=1 --tz=0 --clock=${today}T09:00 2>&1 | grep -E "playtest\].*(ok|FAIL|done)"
echo "== C: relaunch next day 06:40 (a new Dawn window): still exactly one ray"
dev/run_playtest.sh u3_visitor_b 405x720 --stage=2 --tz=0 --clock=${tomorrow}T06:40 2>&1 | grep -E "playtest\].*(ok|FAIL|done)"
echo "== earlier saves (v1, v2) in the Update 3 build"
cp tests/fixtures/save_v1_midrun.json "${UD:?}/pt_u3_mig1.json"
cp tests/fixtures/save_v2_checkpoint.json "${UD:?}/pt_u3_mig2.json"
for n in 1 2; do
  PT_SAVE=pt_u3_mig$n dev/run_playtest.sh u3_migrate 405x720 --speed=2 2>&1 | grep -E "playtest\].*(ok|FAIL|done)"
done

#!/usr/bin/env bash
# Run a live-UI playtest scenario under a virtual display.
#   dev/run_playtest.sh SCENARIO [WIDTHxHEIGHT] [extra game args...]
# Needs: GODOT=/path/to/godot (4.3), xvfb-run. Screenshots land in dev/out/.
set -euo pipefail
SCENARIO="${1:-smoke}"; SIZE="${2:-405x720}"; shift $(( $# > 1 ? 2 : $# )) || true
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
W="${SIZE%x*}"; H="${SIZE#*x}"
if [ -n "${HEADLESS:-}" ]; then
  RUN=("$GODOT" --headless --path .)            # script-only timing, no rendering
else
  RUN=(xvfb-run -a -s "-screen 0 ${W}x${H}x24" "$GODOT" --rendering-driver opengl3 --path . --resolution "${W}x${H}")
fi
"${RUN[@]}" -- --playtest=playtest --scenario="$SCENARIO" --save="${PT_SAVE:-pt_${SCENARIO}}" "$@" 2>&1 | grep -v -E "ALSA|audio_driver|dummy driver|snd_|init_output|initialize \(servers"

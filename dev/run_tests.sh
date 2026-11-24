#!/usr/bin/env bash
# Headless rules tests (no display needed). GODOT=/path/to/godot dev/run_tests.sh
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --script res://tests/test_core.gd 2>&1 | grep -v -E "ALSA|audio_driver|dummy driver|initialize \(servers|^$|Godot Engine"

#!/usr/bin/env bash
# Rebuild the playable web build into docs/ (served by GitHub Pages).
# Needs Godot 4.3 and its export templates (web_nothreads_release.zip) installed.
#   GODOT=/path/to/godot dev/export_web.sh
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
mkdir -p docs
"$GODOT" --headless --path . --export-release "Web" docs/index.html
# Godot 4.3 bug: no-threads exports still list index.worker.js in the service
# worker's pre-cache, which does not exist, so offline install fails. Drop it.
if [ ! -f docs/index.worker.js ]; then
  sed -i 's/"index.worker.js",//' docs/index.service.worker.js
fi
touch docs/.nojekyll docs/.gdignore
ls -la docs

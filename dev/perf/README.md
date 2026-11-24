# Performance measurements

Scenarios (identical for every build, `dev/perfbench.gd`, run with `dev/run_perf.sh [dir]`):

* **pool** – a fixed 14-step action sequence on a 32-creature board: selection taps (no turn), a Current preview
  opened and cancelled, slides, pair merges (some chain) and three Surges (preview + landing). Frames where the
  benchmark itself was planning its next input are excluded.
* **reef** – 30 residents idle for 10 s on the reef view, then 10 s on the pool's reef strip.

Environment (both builds): Godot 4.3, **desktop measurements only**: Linux container, no GPU.
*headless* = script cost only, frame rate capped at 60 (anything over 16.7 ms is a script hitch);
*windowed* = 405x720 Xvfb window, software GL (llvmpipe), so absolute numbers are far slower than a phone GPU and
mostly measure rasterisation; use them for relative comparison only.

Files: `update1_baseline_same_harness.txt` (commit e0d72cb, before) · `update2_after_first_pass.txt` · `update2_final.txt`.
`baseline_update1.txt` is an earlier run of a first version of the harness (kept for the record).

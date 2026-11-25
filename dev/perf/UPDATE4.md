# Update 4 performance: Update 3 build vs the final Update 4 build

Same harness (`dev/perfbench.gd`, `dev/run_perf.sh`), same scenarios, median [min-max] of 3 runs. **Desktop only**: Linux
container, Godot 4.3. *headless* = script cost with the frame rate capped at 60 (16.67 ms = on budget); *windowed* = a
405x720 Xvfb window with **software GL (llvmpipe)**, so absolute numbers are several times slower than a phone GPU and mostly
measure rasterisation; use them as a relative comparison. No device, GPU or hardware profiler was available.

What the numbers say (honestly):
* **Script cost** (headless): unchanged or better everywhere (largest hitch 31 -> 21 ms in the dense-board sequence;
  per-action refresh 55 -> 37 us).
* **Populated reef** (30 residents) windowed: 21.8 -> 16.7 ms average, p95 54 -> 22 ms, frames over 33 ms 139 -> 0.
* **Pool idle with the reef strip**: 19.6 -> 17.5 ms average, p95 34 -> 29 ms.
* **Dense-board action sequence, windowed: slower** (31.6 -> 40.1 ms average, p95 45 -> 51 ms, worst hitch 64 -> 72 ms).
  The new creature art has far more triangles than the old flat discs and 36 of them are rasterised every frame in software.
  This is the one regression; on a real GPU it should be much smaller but that could not be measured here.
* How the art was kept affordable: static scenery (backdrop, reef terrain, board frame and tiles) is baked into textures
  and re-rendered only when the tide, layout or tile occupancy changes; creature meshes are cached per size; animated layers
  run at 12-15 fps and rest while hidden, busy or in reduced motion; at most 10 residents animate. During this work the
  idle pool was 53 ms before baking and a per-frame setter that queued a redraw every frame cost another ~7 ms
  (found by hiding layers one at a time with `--hide=...` / `--nobd` in `perfbench.gd`).

| scenario | mode | metric | before (Update 3 build) | after (Update 4) |
|---|---|---|---|---|
| pool_dense_sequence | headless | frame avg ms | 16.67 [16.67-16.67] | 16.67 [16.67-16.67] |
| pool_dense_sequence | headless | frame p95 ms | 17.17 [17.12-17.59] | 17.13 [17.00-17.17] |
| pool_dense_sequence | headless | max hitch ms | 31.08 [21.36-34.38] | 21.15 [20.53-21.28] |
| pool_dense_sequence | headless | frames >33 ms (of N) | 0.0 [0.0-1.0] | 0.0 [0.0-0.0] of ~910 / ~934 |
| pool_with_reef_strip_30_idle | headless | frame avg ms | 16.67 [16.67-16.67] | 16.67 [16.67-16.67] |
| pool_with_reef_strip_30_idle | headless | frame p95 ms | 16.77 [16.77-16.80] | 16.80 [16.78-16.85] |
| pool_with_reef_strip_30_idle | headless | max hitch ms | 20.56 [18.00-21.28] | 18.13 [17.91-18.33] |
| pool_with_reef_strip_30_idle | headless | frames >33 ms (of N) | 0.0 [0.0-0.0] | 0.0 [0.0-0.0] of ~599 / ~600 |
| reef_populated_30_idle | headless | frame avg ms | 16.67 [16.67-16.67] | 16.67 [16.67-16.67] |
| reef_populated_30_idle | headless | frame p95 ms | 16.80 [16.77-16.87] | 16.83 [16.83-16.83] |
| reef_populated_30_idle | headless | max hitch ms | 21.38 [18.39-25.00] | 19.68 [19.63-19.78] |
| reef_populated_30_idle | headless | frames >33 ms (of N) | 0.0 [0.0-0.0] | 0.0 [0.0-0.0] of ~599 / ~599 |
| pool._refresh_all (runs after every action) | script | µs per call | 54.8 [38.5-57.6] | 37.0 [29.3-56.2] |
| pool._update_prompt (runs on every selection change) | script | µs per call | 3.5 [2.9-3.8] | 3.0 [2.8-4.0] |
| session.is_stuck | script | µs per call | 4.2 [3.6-6.5] | 4.0 [3.4-4.1] |
| session.preview_current (one line) | script | µs per call | 128.8 [116.6-187.5] | 100.9 [99.5-119.6] |
| session.save (JSON + atomic write) | script | µs per call | 548.7 [540.0-744.5] | 462.6 [397.0-518.3] |
| session.valid_targets | script | µs per call | 28.8 [27.3-29.9] | 22.9 [22.7-25.6] |
| pool_dense_sequence | windowed | frame avg ms | 31.62 [31.33-32.75] | 40.12 [35.56-40.37] |
| pool_dense_sequence | windowed | frame p95 ms | 44.92 [44.63-45.15] | 50.71 [46.04-51.82] |
| pool_dense_sequence | windowed | max hitch ms | 64.11 [59.44-70.67] | 72.08 [61.34-85.20] |
| pool_dense_sequence | windowed | frames >33 ms (of N) | 229.0 [220.0-260.0] | 466.0 [381.0-477.0] of ~579 / ~522 |
| pool_with_reef_strip_30_idle | windowed | frame avg ms | 19.55 [19.26-20.31] | 17.47 [17.30-17.67] |
| pool_with_reef_strip_30_idle | windowed | frame p95 ms | 34.33 [32.76-34.84] | 29.30 [28.88-30.00] |
| pool_with_reef_strip_30_idle | windowed | max hitch ms | 59.18 [45.14-64.12] | 46.30 [37.33-48.85] |
| pool_with_reef_strip_30_idle | windowed | frames >33 ms (of N) | 41.0 [21.0-45.0] | 4.0 [4.0-7.0] of ~514 / ~572 |
| reef_populated_30_idle | windowed | frame avg ms | 21.76 [20.21-22.26] | 16.67 [16.66-16.67] |
| reef_populated_30_idle | windowed | frame p95 ms | 54.43 [51.69-57.94] | 21.89 [21.73-22.60] |
| reef_populated_30_idle | windowed | max hitch ms | 72.85 [65.01-80.84] | 32.44 [32.42-34.26] |
| reef_populated_30_idle | windowed | frames >33 ms (of N) | 139.0 [139.0-143.0] | 0.0 [0.0-1.0] of ~460 / ~600 |

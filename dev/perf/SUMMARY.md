| scenario | mode | metric | before (Update 1) | after |
|---|---|---|---|---|
| pool_dense_sequence | headless | frame avg ms | 16.67 [16.67-16.67] | 16.67 [16.67-16.67] |
| pool_dense_sequence | headless | frame p95 ms | 16.89 [16.85-16.99] | 17.18 [17.15-17.24] |
| pool_dense_sequence | headless | max hitch ms | 24.76 [23.96-34.31] | 20.92 [20.89-22.97] |
| pool_dense_sequence | headless | frames >33 ms (of N) | 0.0 [0.0-1.0] | 0.0 [0.0-0.0] of ~894 / ~917 |
| pool_with_reef_strip_30_idle | headless | frame avg ms | 16.67 [16.67-16.67] | 16.67 [16.67-16.67] |
| pool_with_reef_strip_30_idle | headless | frame p95 ms | 16.75 [16.74-16.75] | 16.78 [16.78-16.78] |
| pool_with_reef_strip_30_idle | headless | max hitch ms | 22.23 [19.24-23.90] | 17.91 [17.79-27.99] |
| pool_with_reef_strip_30_idle | headless | frames >33 ms (of N) | 0.0 [0.0-0.0] | 0.0 [0.0-0.0] of ~599 / ~599 |
| reef_populated_30_idle | headless | frame avg ms | 16.67 [16.67-16.67] | 16.67 [16.67-16.67] |
| reef_populated_30_idle | headless | frame p95 ms | 16.74 [16.73-16.75] | 16.76 [16.75-16.78] |
| reef_populated_30_idle | headless | max hitch ms | 17.64 [17.12-18.54] | 18.52 [17.91-22.55] |
| reef_populated_30_idle | headless | frames >33 ms (of N) | 0.0 [0.0-0.0] | 0.0 [0.0-0.0] of ~599 / ~599 |
| pool._refresh_all (runs after every action) | script | µs per call | 3047.3 [3025.6-3462.9] | 33.9 [32.3-39.1] |
| pool._update_prompt (runs on every selection change) | script | µs per call | 3067.8 [2988.9-3203.2] | 3.3 [3.0-5.1] |
| session.is_stuck | script | µs per call | 5.3 [4.0-5.3] | 4.2 [4.2-6.3] |
| session.preview_current (one line) | script | µs per call | 111.0 [110.6-117.0] | 123.1 [111.3-199.1] |
| session.save (JSON + atomic write) | script | µs per call | 252.9 [217.2-294.3] | 390.9 [370.3-532.7] |
| session.valid_targets | script | µs per call | 27.6 [27.4-35.4] | 30.4 [27.1-41.9] |
| pool_dense_sequence | windowed | frame avg ms | 33.28 [31.05-33.56] | 29.28 [28.47-29.54] |
| pool_dense_sequence | windowed | frame p95 ms | 45.75 [40.76-45.97] | 40.79 [39.84-41.04] |
| pool_dense_sequence | windowed | max hitch ms | 57.44 [51.23-65.71] | 60.06 [57.23-67.21] |
| pool_dense_sequence | windowed | frames >33 ms (of N) | 252.0 [205.0-266.0] | 149.0 [146.0-162.0] of ~557 / ~608 |
| pool_with_reef_strip_30_idle | windowed | frame avg ms | 40.91 [40.77-42.22] | 17.47 [17.46-18.65] |
| pool_with_reef_strip_30_idle | windowed | frame p95 ms | 54.84 [52.78-55.67] | 30.28 [29.91-31.81] |
| pool_with_reef_strip_30_idle | windowed | max hitch ms | 67.41 [63.16-69.78] | 61.37 [37.85-63.49] |
| pool_with_reef_strip_30_idle | windowed | frames >33 ms (of N) | 213.0 [208.0-216.0] | 5.0 [3.0-14.0] of ~243 / ~572 |
| reef_populated_30_idle | windowed | frame avg ms | 27.07 [25.90-29.58] | 20.86 [19.50-22.26] |
| reef_populated_30_idle | windowed | frame p95 ms | 37.73 [35.16-41.54] | 50.33 [45.62-52.37] |
| reef_populated_30_idle | windowed | max hitch ms | 48.97 [45.68-53.79] | 61.67 [60.44-62.72] |
| reef_populated_30_idle | windowed | frames >33 ms (of N) | 51.0 [37.0-91.0] | 180.0 [179.0-183.0] of ~369 / ~480 |

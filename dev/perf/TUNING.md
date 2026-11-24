# Update 4 tuning: the swell

**Problem measured.** `dev/tune_sim.gd` plays reproducible standard runs headlessly (60 seeds each, through the real
`GameSession`, the run's own cadence / Surge size / spawn table). Three bots share the Hint's priorities
(release, chain, line, merge, Current, slide, advance the tide) but follow the Hint only part of the time:
*casual* (25 % of turns, releases 40 % of tier 4+), *mid* (50 % / 60 %) and *expert* (always).
With the baseline rules (a 3-creature Surge every 3rd turn, 6x7 board, start with 12 creatures) **no bot flooded within
300 turns**, whatever the skill. Ordinary merges (one pair = one cell freed, a chain = more) and the free Reef Gate
cancel the one-creature-per-turn Surge, so there was no late pressure and a run never had to end.

| bot | before: turns | before: flooded | before: empty cells at a Surge (avg / first Surge) |
|---|---|---|---|
| casual | 300 (cap hit by all 60) | 0 / 60 | 23.0 / 32.3 |
| mid | 300 (cap hit by all 60) | 0 / 60 | 31.9 / 32.8 |
| expert | 300 (cap hit by all 60) | 0 / 60 | 38.3 / 34.3 |

No early flood and no stall existed (0 of 60 before turn 15; no bot ever lacked a legal action), so the opening was
left alone: the first Surge arrives with ~33 of 42 cells free.

**Change (configurable, `config/game_config.gd`).** *The swell*: a standard run's Surge grows later on.
`SWELL_START = 20`, `SWELL_EVERY = 20`, `SWELL_MAX = 3`: 3 creatures until turn 20, 4 from turn 20, 5 from 40, 6 from 60.
Cadence (every 3rd turn), board size, start layout and spawn weights are unchanged. The values are copied onto each run
when it starts (`RunState.swell_*`), so changing the config never alters a run in progress; a run saved by an older build
has `swell_max = 0` and keeps its old rules for its whole life. The guided first run, Calm Pool and Trials never swell.
The Surge readout ("N creatures drop on empty cells") and the flood message report the current size.

| bot | after: turns avg / median / min / max | after: flooded | empty cells at a Surge (avg / first Surge) | releases / run | merges / run |
|---|---|---|---|---|---|
| casual | 69.5 / 69 / 57 / 90 | 60 / 60 | 21.0 / 32.3 | 12.5 | 47.4 |
| mid | 110.2 / 99 / 69 / 300 | 59 / 60 | 20.9 / 32.8 | 30.6 | 94.5 |
| expert | 140.7 / 138 / 93 / 240 | 60 / 60 | 25.1 / 34.3 | 47.5 | 147.8 |

At the ~4 s per turn measured in the live-UI bot run this is about **4.5 minutes for a casual player** (the 3-5 minute
target), 6-7 minutes for a mid player and 9 minutes for an expert; nobody floods before turn 15 (shortest run 57 turns),
and nobody stalls. A swell of 30/30/2 was also tried (casual 195 turns, 20 % of mid runs still unfinished at 300) and
24/24/3 (casual 76, mid 96): both left casual runs well above 5 minutes, so 20/20/3 was kept.

Alternatives rejected: a shorter cadence (2) ended only 12 % of runs by 200 turns; heavier tier-2/3 spawn weights
(x2 / x4) *increased* empty space because the extra tier-2/3 pieces merge up into releasable creatures faster.

Reproduce: `godot --headless --path . --script res://dev/tune_sim.gd -- --n=60 --cap=300 --skill=0.5 --relp=0.6 --swell=20,20,3`
(`--swell=0,0,0` is the before rules). Raw output: `dev/perf/tuning_sim_raw.txt`.

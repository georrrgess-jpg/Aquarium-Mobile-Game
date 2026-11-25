# Tidepool Tycoon · handoff for Update 4 (visual overhaul and gameplay)

Update 4 is implemented, verified and committed **locally** (nothing pushed; the earlier handoff asked to keep work local, and
the web build in `docs/` was re-exported but not published). Older Update 2/3 notes are kept below.
Commits: `81c4495` pass 1 (first run, input) · `a506fb4` pass 2 (art) · `e5bcb52` pass 3 (progression) · then tuning, review fixes.

## Launch
```bash
godot --path .                                        # Godot 4.3
godot --path . -- --clock=2026-11-24T06:30 --tz=0     # fake local time: Dawn (and the Lantern Ray window)
godot --path . -- --fresh                             # delete the save first (new-player experience)
godot --path . -- --safe=48,34                        # simulate notch / home-indicator insets
```
Other flags: `--seed=N --save=NAME --speed=X`. Web: `dev/export_web.sh` (re-exported, not pushed).

## What shipped
**Art.** Original procedural vector art (no image files): Shrimp and Starfish at all six tiers and the Lantern Ray, drawn with
growth shown by body shape, claws, arms and markings, one key light, readable at board size and reused on the board, reef,
results, arrival card and Book. Redrawn coins, pearls, Current token, Reef Gate, chest, five decorations (each changes the reef
when placed: light pool, bubble stream, lantern glow, light shaft...) with available / selected / locked / unaffordable / owned
card states reused in the shop. New reef (far hills, coral clusters, kelp, rays) and pool backdrop (detail outside the grid, framed
board, tiles distinct under Dawn / Midday / Dusk / Night). Merge reads contact -> evolution flash -> settle; chains draw links to
the cells that took part. Reef residents have per-family idle loops and a drop-in arrival.
**Onboarding.** A new profile sees a living reef and one Play button, then a deterministic guided pool: merge a pair (first
merge about 2 s of scripted play), a previewed Current that makes a line, read the first Surge, release the tier 4 through
the Reef Gate (about 9 s scripted; about 25-60 s at a human pace). Tap and drag both work; recovery bar offers a restart when
the player leaves the path; restart is reward-free until finished and grants the first-release milestone once; Skip and a
replayable Help (separate board, no payout); arrival card (resident, income, route back, affordable first decoration);
saved with the board; existing players skip all of it.
**Pool readability.** Surge countdown, Current charges and Reef Gate stay put; marks use shapes, not colour only; five
distinct rejection looks (invalid, capped, spent Current, resolving, ended); cancel on Back / Esc / focus loss; reduced motion
keeps the same information; optional **Hint** (release > chain > line > merge > Current; never mutates the board or RNG).
**Repeat play.** One optional **Tide Goal** per standard run (saved with the run, paid once, shown above the grid); **Tidepool
Book** (13 entries, silhouettes for reachable tiers, field notes, backfilled from residents); **Calm Pool** (Surge every 5
turns, own resumable board, reset instead of flood, no currency / releases / Book / goal / daily / visitor progress);
**three Trials** (Wrap, Chain, Room) each proved winnable and losable by an exhaustive solver on the real rules, first clear pays
once, retries free; **results screen** with best merge, releases, longest chain, goal result, **Play Again** / **Visit Reef**.
Hub tabs: Residents · Decor · Goals · Modes (Trials + Calm Pool) · Book. No timers, energy or mandatory dailies.
**Save format v4** (v1-v3 migrate; Book backfilled; old Trial flags moved).

## Final tuning values (`config/game_config.gd`; details and before/after in `dev/perf/TUNING.md`)
Board 6x7, Surge every 3 turns, Surge size 3, 12 start creatures, spawn weights: **unchanged**.
**New: the swell** `SWELL_START=20, SWELL_EVERY=20, SWELL_MAX=3` (Surge 3 -> 4 at turn 20 -> 5 at 40 -> 6 at 60; the guided start
begins counting when it finishes). Before it, 180 simulated runs of three bot skill levels never flooded in 300 turns; after,
casual runs end at median 69 turns (~4.5 min at 4 s/turn), mid 99, expert 138; no flood before turn 15, no stalls. Values are
copied onto each run at its start, so runs in progress (and old saves) keep their rules. Tide Goal pays 80 coins + 2 pearls;
Trials pay 150+3 / 120+2 / 120+2 once.

## Verification (all on this Linux container; Godot 4.3)
* `dev/run_tests.sh`: **134 + 73 + 114 + 70 + 81 = 472 headless checks** (rules, economy and migration, tides / visitor / goals,
  onboarding and Hint, progression incl. Trial solver, swell). Engine script errors count as failures.
* Live-UI scenarios with injected mouse/touch input (`dev/playtest.gd`, `dev/ui_review.gd`): guided first run, Skip, Help replay,
  reload during onboarding, restart, existing save, repeated taps and cancelled drags (24 input checks), Current preview and
  commit, failed Surge / flood, release, chest claim, mode switching with a regular run suspended (Trials and Calm, board
  untouched), goals and rewards surviving reload without a second payout, Book, results. All pass.
* **Session run** (`dev/session.gd`, bot following the Hint through the live UI, 1 turn = 4 s human pace): 23.6 minutes over 2 full
  runs of 144 and 159 turns (both flooded, the expert bot's ~10-11 min each), reef visits, two decoration purchases, a Chain
  Trial and a Calm Pool visit; first release at 13 s of play; no stalls; goal "make a tier 4" completed in run 2. Worst frame
  150 ms (software GL), 34 of 8,693 frames over 100 ms. Casual players: ~4.5 min per run (tuning table).
* **Performance** (`dev/perf/UPDATE4.md`, same harness, Update 3 build vs this one, median of 3, desktop only): script cost
  same or better; populated reef 21.8 -> 16.7 ms avg (p95 54 -> 22); idle pool 19.6 -> 17.5; **dense-board action
  sequence in software GL is slower: 31.6 -> 40.1 ms avg, p95 45 -> 51** (richer creature art rasterised in software; a real GPU
  was not available to measure).
* **Final UI review** (`dev/run_ui_review.sh SIZE`, 21 scenarios, objective checks for overlap, tap size >= 44 px, text fit and
  safe-area insets plus every screenshot viewed): 280x653 and 405x720 with `--safe=48,34`, plus 320x568 and 412x915 spot
  checks, no-safe-area runs at 280x653 and 405x720, Dawn / Midday / Dusk / Night palettes. Screens: first-run reef + help, guided
  steps 1-4 + arrival card + Skip + Help + recovery bar, hub with all five tabs / chest / visitor banners / long creature names /
  123 billion coins, standard pool (goal strip, Hint, Current mode, Surge and swell Surge, every rejection toast, 3-line
  toast, flood notice, reduced motion), results (goal done / missed / many survivors / huge numbers), the three Trials (start,
  hint, win, lose), Calm Pool, Help sandbox, Night. 12 defects found and fixed (hub overflow with two banners, unusable Help
  Close, roster name shrink, toasts covering the board, results text collisions, Dawn badge contrast, sub-44 px buttons, Calm
  prompt text...). Final run after fixes: 42 of 42 scenario runs pass.

## Playtest routes (5 minutes each)
**New player:** `godot --path . -- --fresh`. Tap Play, follow the on-board labels (drag or tap; try Hint, Skip, Help, or play
out of order to see the recovery bar), release the tier 4, read the arrival card, Visit the reef (Decor tab opens with the Coral
Fan ready), Play to continue as a standard run (Tide Goal strip appears on later runs).
**Returning player:** launch with an existing save: reef first with Resume run; try the Modes tab (Wrap / Chain / Room Trials, Calm
Pool), then Resume run (your board is exactly as left); finish a run for the results screen (Play Again / Visit Reef); open the Book
tab. `--clock=2026-11-24T06:30 --tz=0` also shows Dawn and the Lantern Ray.
Before / after screenshots: `docs/screenshots/update4_before/` (Update 3 build) and `docs/screenshots/update4_after/` (30 images at
280 and 405 px wide; also `dev/out/rv_*`).

## Not done / could not be checked
* No physical device: real touch hardware, notch / home-indicator insets (simulated with `--safe`), haptics and audio, GPU frame
  rate. Touch was tested through the engine's touch events and mouse emulation.
* **Larger text settings: not supported** by the game (fixed logical font sizes), so that review item could not be run. The
  smallest text is 13-14 logical px (a few shrink-to-fit fallbacks to 11-12); at a 280 px wide phone that is about 7 px
  physical, judged legible by eye only.
* Row / column Current tabs are 26 px on the short side (an edge-drag tab; the alternative route is Current then drag along
  a line); widening them would steal edge-cell drags (`BoardView.TAB`).
* The first guided on-board label still partly covers one bystander shrimp at 405x720 (it never covers the cells to use).
* An occasional engine message "Invalid polygon data, triangulation failed" from the animated art; nothing visibly breaks.
* Dense-board windowed frame time regression noted above. Pearls still have no use; mutations, tools, zones, monetisation out
  of scope.

---

# Tidepool Tycoon · handoff for Updates 2 and 3

Both updates are implemented, verified and committed **locally** (nothing was pushed; the owner asked for local work).
The game launches (`godot --path .`), the Update 1 pool loop is unchanged, and old saves load.

## What shipped

**Update 2 · smoother pool, living reef**
* One teal-water / warm-sand / coral style across pool, HUD, reef and hub. Selected piece, legal targets and incoming
  Surge cells are marked with **shapes** (corner brackets, diamond / dotted-circle marks, dashed outlines with an
  arrow tab) as well as colour; the Surge countdown sits above the grid; Currents and the Reef Gate keep fixed homes.
* **Current preview** reuses the real Current rules and now also brackets the exact pieces that would form the
  three-in-a-row and marks the result cell. Preview, change of direction and cancel are free.
* **Input**: pointer is tracked live; one rejection response; drags are cancelled by right click, Esc, the pointer
  leaving the window, focus loss, hiding the view, or input locking (a Surge starting). Input during an animation,
  a Surge preview or the flood notice is ignored and restored at the end.
* **Reef hub** (start screen *and* reef): aquarium with decorations and a resident roster (newest first, **NEW**
  highlight until you leave the reef), income per hour, offline chest, Play / Resume / Back button. At most 18
  residents are drawn and 10 animated; everyone is in the roster.
* **Passive income** `5 x 1.8^(tier-1)` per resident per hour x `(1 + Beauty/100)`, fractions carried, settled at the old
  rate before a release or purchase. **Offline chest** capped at 8 h *across* relaunches; claim = pay + clear in one save.
* **Five decorations** (coral fan 120 · bubble column 450 · sea lantern 1,200 · sunken statue 3,000 · light shaft
  7,000 coins; Beauty 3/5/8/12/18) with marked spots, a ghost preview and the cost + income change shown before buying.
  A repeat press or retry never double-charges. The first one is affordable by turn 4 of the first run.
* Haptics (toggle), sound and motion toggles on the hub; summary leads to the reef (highlighted when something new
  was released) or the next pool.

**Update 3 · tide cycles, visitor, Trial, goals**
* **Tide** by local time (Dawn 06-10, Midday 10-17, Dusk 17-21, Night 21-06): reef lighting + screen background;
  each *new run* records its phase's spawn bias and keeps it (also its pending Surge) across reload and phase changes.
* **Lantern Ray** (original art, swim-in arrival): offered in the first 90 min of Dawn and Dusk; tap to accept a
  request for the tide's featured family (make a tier 4+, release it). Persists across reload and window close;
  completion grants one permanent Lantern Ray resident, once, in the same save as the release.
* **Tide Trial**: fixed board, 2 moves, one Current, wraparound required (proved by an exhaustive solver), repeatable
  hint, free retries, first-clear reward (150 coins + 3 pearls) once. Runs on its own session: a suspended pool is
  untouched and nothing earned there counts toward goals or merges. Results return straight to the reef.
* **Daily goals**: make 8 merges (60 coins + 1 pearl), use a Current (40), release a tier 4+ (100 coins + 2 pearls);
  once per local day, reset at local midnight, reward and completion saved together.
* Reef hub tabs: Residents · Decor · Goals · Trial, plus the visitor banner; nothing covers the aquarium.

## Not done / deferred
* No real-device run: Android/iOS export, real haptics and a hardware-GPU profile were not possible here.
* Pearls still have no use. Mutations, tools, zones, live services, monetisation: out of scope as briefed.
* The "no legal move" tide-advance button still cannot occur naturally (see README); it is exercised by a test flag.
* The hub's per-frame cost in the *software* renderer rose (see performance). No caching rewrite was attempted.

## Launch
```bash
godot --path .                                   # Godot 4.3
godot --path . -- --clock=2026-11-24T06:30 --tz=0   # pretend it is 06:30 local: Dawn + the Lantern Ray window
```
Other flags: `--seed=N --fresh --save=NAME --speed=X`. Web build: `dev/export_web.sh` rebuilds `docs/` (re-exported at
this checkpoint, **not pushed**, so the GitHub Pages link still serves the Update 1 build until you push).

## Five-minute playtest route
1. Start with `--clock=2026-11-24T06:30 --tz=0 --fresh`. The reef shows **Dawn** lighting and the **Lantern Ray**
   swimming in. Tap it: *Step 1 of 2: make a tier 4+ Shrimp*.
2. **Dive in**. Follow the prompts: merge the glowing shrimp (chain, +1 Current), then tap a row tab, pick *Left*,
   and read the **preview** (brackets on the three pieces, gold wrap arrows) before *Shift* (tier 4 Starfish).
3. Merge the two tier 3 Shrimp (tier 4 Shrimp: toast says release it for the Lantern Ray); drag each tier 4 to the
   **Reef Gate**. The 3rd turn triggers a **Surge** preview. The Ray joins the reef ("joins your reef!").
4. **Reef** button: the NEW residents are highlighted. *Decor* tab -> Coral Fan -> a marked spot -> read the income
   change -> *Buy*. *Goals* tab: Current and release goals are done. *Residents* shows the Ray.
5. *Trial* tab -> **Start the Tide Trial**: use *Hint*, waste two moves to see *Retry*, then wrap row 3 left to clear it
   (+150 coins). *Return to the reef*, then **Resume run**: your pool is exactly where you left it.
6. For the chest and tides: relaunch with `--clock=2026-11-24T17:30 --tz=0` (Dusk, Starfish request) or a time hours
   later than your last session to see the **offline chest**.

## Verification performed (all on this Linux container, Godot 4.3)
* `dev/run_tests.sh`: **320 headless checks** (133 rules, 73 economy/migration, 114 tide/visitor/goals/trial). Includes
  all phase boundaries, spawn biases, run weights across a phase change + reload, every visitor window and transition
  (before/after reload, acceptance before close, completion after close, missed window, exactly one ray), goals incl.
  midnight rollover with a non-UTC zone, the Trial solver (every action sequence within budget: winnable, shortest
  solution = Current row 3 left, **no sequence makes a line without a wrap**), isolation of the Trial from a suspended
  run (board, turn, Currents, RNG, stats, balances and the save file unchanged), first-clear reward once, WCAG contrast.
* Live UI with injected mouse and touch events + screenshots (`dev/playtest.gd`): tutorial, touch, rule cases, flood
  and summary, reduced motion, **24 input-robustness checks** (cancel by right click / Esc / window exit / input lock,
  rapid input during animation, Surge preview and flood), Update 3 tide/visitor/Trial/goals flows.
* Multi-process checkpoints: `dev/run_u2_checkpoint.sh` (play, preview, Surge, release, buy + double-press, then 4
  relaunches at +3 h, +20 h, +45 h, +46 h: **8 h cap held with no stacking, double claim paid once**) and
  `dev/run_u3_checkpoint.sh` (accepted 06:30 -> relaunched 09:00 and finished -> relaunched next day: one ray).
* Layout/overlap, no element off screen or overlapping, text fits: pool, hub (all 4 tabs, 3 tide states, visitor +
  chest banners), Trial, results panel at **280x653, 320x568, 360x640, 412x915**.
* Web build: loads, no console errors, saves persist across reload; local time zone read correctly from the browser
  in Tokyo / Los Angeles / London.
* A full bot-played run still reaches a flood summary and carries rewards (60 turns, 3 Currents, 1 chain).

## Save migration
`user://tidepool_save.json` is **version 3**. v1 -> v2 -> v3 is chained and tested on real saves written by the Update 1
and Update 2 builds (`tests/fixtures/`): active run (board, turn, Currents, RNG), balances, every resident, decorations
all survive; unknown future versions are quarantined to `.corrupt` instead of crashing. The reef income clock starts at
the moment of upgrade (no retroactive windfall). A pre-tide run keeps rolling Surges from the base spawn table.

## Performance (before = Update 1 commit e0d72cb, after = this build; identical scenarios, median of 3 runs)
Scenarios (`dev/perfbench.gd`): a fixed 14-step action sequence on a dense board, and 30 residents idle. **Desktop
measurements only**: headless = script cost with frame rate capped at 60 (anything over 16.7 ms is a script hitch);
windowed = 405x720 Xvfb with *software* GL (llvmpipe), so absolute numbers are ~2-3x slower than a phone GPU and
mostly measure rasterisation. No device or hardware profiler was available. Full table: `dev/perf/SUMMARY.md`.

| measure | before | after |
|---|---|---|
| cost of a selection tap (prompt/hint refresh) | 3,068 µs | **3.3 µs** |
| cost of the post-action refresh | 3,047 µs | **34 µs** |
| dense-board sequence, headless: largest hitch | 24.8 ms | **20.9 ms** |
| dense-board sequence, headless: p95 frame | 16.89 ms | 17.18 ms (same within noise) |
| dense-board sequence, windowed: avg / p95 | 33.3 / 45.8 ms | **29.3 / 40.8 ms** |
| dense-board sequence, windowed: frames > 33 ms | 252 of ~557 | **149 of ~608** |
| pool with reef strip idle, windowed: avg / p95 | 40.9 / 54.8 ms | **17.5 / 30.3 ms** |
| reef hub, 30 residents, windowed: avg | 27.1 ms | 20.9 ms |
| reef hub, 30 residents, windowed: p95 / share of frames > 33 ms | 37.7 ms / 14% | **50.3 ms / 37% (worse)** |

Fixed hotspots: the coach hint scanned 26 Current previews on every selection tap (now cached per committed state and
amortised over frames); per-draw style-box allocations (cached); the reef redrew 60x/s (now layered: static scenery and
non-animated residents redraw only on change, 15-20 fps for the animated layer, 12 fps and paused while busy for the
pool strip); low-processor mode so a still screen costs nothing; Night tint moved off the animated layer; saves stay
at committed actions only. **Regression:** each redraw frame of the (much richer) hub costs more in the software
renderer, and the largest single hitch in the pool sequence did not improve in the windowed run (57 -> 60 ms).
With the visitor, five decorations and 30 residents the hub is ~23 ms avg / ~54 ms p95 windowed and 16.8 / 19 ms headless.

## Rule / balance defaults that changed or were decided
* Pool merge, chain, wrap, Surge and flood rules are **unchanged** (the 133 original rule checks still pass).
* Surge weights (and the random layout of runs after the first) now depend on the tide phase at run creation (small
  biases: Shrimp x1.5 Dawn, tier 2 x1.8 Midday, Starfish x1.5 Dusk, tier 3 x1.7 Night); the first-run starter layout is fixed.
* Daily goals and the Trial add coins on top of merge rewards (up to 200 coins + 3 pearls per day, 150 + 3 once).
* Lantern Ray resident = tier 4, so it earns like any tier 4 (29.2 coins/h) and has no extra Beauty.
* The visitor is one-time: after the ray lives in the reef it never returns. Visitor progress needs the tier 4+ to be
  *made after* accepting; releasing one that already existed does not count.
* "Away" = a gap of more than 90 s between income settlements; shorter gaps pay straight to the balance.
* Trial: 2 moves, 1 Current, row 3 Shrimp; clock-independent. Prices/Beauty/rates are all in `config/game_config.gd`.

## Environment limitations
* No physical device, GPU or profiler; all timings are desktop. Haptics (`Input.vibrate_handheld`) and audio cannot be
  heard or felt here (audio falls back to a dummy driver).
* Touch was tested through the engine's touch-to-mouse emulation, not a touchscreen.
* DST: the web build uses the browser's *current* UTC offset for every time it converts, so a fake clock set across a
  DST change is off by an hour there; real play is unaffected.
* Update 2 commit is `74b8057`; Update 3 is the commit after it (work kept local).

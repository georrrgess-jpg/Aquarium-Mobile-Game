# Tidepool Tycoon · first playable

## ▶ [Play in your browser](https://georrrgess-jpg.github.io/Aquarium-Mobile-Game/)

The playable web build lives in [`docs/`](docs/) and is served by GitHub Pages
from this branch. It installs as a home-screen app and works offline after the
first load; your progress is saved in the browser.

**Add it to your home screen**
* **iPhone / iPad (Safari):** open the link, tap **Share** → **Add to Home Screen**.
* **Android (Chrome):** open the link, tap **⋮** → **Add to Home screen** / **Install app**.

It then opens full-screen in portrait like a normal app. After a new build is
pushed, close and reopen it once to pick up the update.

**One-time setup (repo owner):** *Settings → Pages → Build and deployment →
Source: Deploy from a branch → Branch: `claude/funny-volta-q63lzq`, folder
`/docs` → Save.* The site appears at the link above a minute or two later.

**Rebuilding the web version:** `GODOT=/path/to/godot dev/export_web.sh`
(needs Godot 4.3 with its export templates installed), then commit `docs/`.

---

A portrait mobile merge puzzle. Waves crowd a tidal pool; the creatures you
make can be released through the **Reef Gate** and become permanent residents of
your reef. Godot 4.3, typed GDScript, GL Compatibility renderer.

## Launch

1. Install [Godot 4.3](https://godotengine.org/download) (standard build).
2. Open the folder as a project (`project.godot`) and press **Play**, or from a shell:
   ```bash
   godot --path .
   ```
   The window opens portrait (405x720). Resize it freely; the layout adapts.
3. Optional command-line flags (after `--`):
   | flag | effect |
   |---|---|
   | `--seed=N` | base seed for all random rolls (repeatable playtests) |
   | `--fresh` | delete the save first |
   | `--save=NAME` | use `user://NAME.json` instead of the default slot |
   | `--speed=X` | animation speed multiplier |
   | `--clock=YYYY-MM-DDTHH:MM` | start the game clock at that LOCAL time, then run normally (tide phases, visitor windows, goals, offline chest) |
   | `--tz=MINUTES` | treat local time as this many minutes east of UTC (e.g. `--tz=0`) |

   e.g. `godot --path . -- --seed=42 --fresh`

The save lives at `user://tidepool_save.json` (Godot's per-user data folder).

## How to play

* **Merge:** tap a creature, then an identical one anywhere on the board (the
  matches glow); or drag one onto the other. Same family and tier. The target
  holds the next tier.
* **Slide:** tap/drag a creature into an orthogonally adjacent empty cell.
* **Current** (starts with 2): press *Current*, or just tap a row/column tab at
  the board edge, then pick *Left/Right* (*Up/Down*). The line, direction and
  where each creature will land are previewed (gold arrows mark the wrap round
  the edge) and the prompt says whether it makes a merge. *Shift* commits. You
  can also drag along a line to preview. A shift that changes nothing is free.
* **Reef Gate:** any tier 4+ creature can be dragged onto the gate, or selected
  and the gate tapped. It leaves the board at once, becomes exactly one reef
  resident and costs no turn.
* **Surge:** after every third turn three creatures land. The three cells and
  tiers are shown first. If fewer than three cells are empty the wave cannot fit
  and the pool **floods**: the run ends with a summary (release survivors, then
  start a fresh run; coins, pearls and residents carry over).
* Illegal moves are rejected with a short message and never cost a turn.

Special merges, resolved automatically after your action:

* **Three in a row** (horizontal/vertical) -> one creature **two tiers up** in the middle cell.
* **Adjacent trio:** a merge result with two same-family-and-tier orthogonal
  neighbours consumes all three -> next tier at the result cell.
* Tier 6 is the cap: a merge that would exceed it is not eligible (a tier 6 pair,
  three tier 5s in a line, three tier 6s side by side all stay as they are).

## The reef, tides, visitors and goals (Updates 2 and 3)

* **Reef hub** (start screen, and the *Reef* button in the pool). The aquarium sits on top; below it the income strip,
  tabs *Residents* (every resident, newest first with a NEW tag), *Decor*, *Goals*, *Trial*, and one big
  Play / Resume / Back button. Residents earn passive coins: `5 x 1.8^(tier-1)` per hour each, times
  `1 + Beauty/100`. Fractions carry; income is settled at the old rate before a release or purchase.
* **Offline chest.** Time away is banked (not paid live) up to **8 hours in total**, however often you relaunch.
  Claiming pays and clears it in one save; claiming twice pays once.
* **Decorations.** Five (coral fan 120, bubble column 450, sea lantern 1200, sunken statue 3000, light shaft 7000
  coins). Pick one, tap a marked spot, see cost and income change, then buy. A repeat press never double-charges.
* **Tides** (local time): Dawn 06-10, Midday 10-17, Dusk 17-21, Night 21-06. The reef is lit to match. Each new run
  records its phase's spawn bias (Dawn Shrimp, Midday more tier 2, Dusk Starfish, Night slightly more tier 3) and keeps
  it for the whole run, even across a phase change or a reload.
* **Lantern Ray** visits during the first 90 minutes of Dawn and Dusk. Tap it to accept: make a tier 4+ creature of
  the featured family (Shrimp at Dawn, Starfish at Dusk), then release it. The request survives reload and the window
  closing. Finishing grants one permanent Lantern Ray resident, once.
* **Tide Trial** (Trial tab): a fixed board, 2 moves, one Current. Wrap row 3 round the edge to make a three in a
  row. Hint button (unlimited), free retries, +150 coins +3 pearls for the first clear only. It runs on its own
  session: a suspended pool is untouched and nothing earned in the Trial counts toward merges or goals.
* **Daily goals** (Goals tab): make 8 merges, use a Current, release a tier 4+. Each pays once per local day when it
  completes and resets at local midnight.

## Where things are

```
config/game_config.gd   ALL tunables: board, spawn weights, surge cadence, Currents, rewards, chain
                        rounding, reef income (5 x 1.8^(tier-1), Beauty), offline cap, decoration
                        prices/Beauty, tide phases and spawn biases, visitor window, trial budget/reward,
                        daily goals, timings, the first-run starter layout
core/                   rules, state and save, no UI:
  board creature merge_rules rewards seeded_rng        board + rules
  run_state profile save_store game_session            state, versioned atomic save (v3), action front door
  game_clock reef_economy                              injectable clock; passive income, offline chest, decor
  tide visitor daily_goals tide_trial                  Update 3 systems
ui/                     screens and widgets (all drawn procedurally; no art assets)
  main pool_screen reef_hub summary_screen             screens (the hub is the start screen AND the reef)
  board_view reef_view roster_view gate_view ...       widgets;  creature_art decor_art = vector art
tests/                  headless rules tests (test_core, test_reef, test_tide) and save fixtures (v1, v2)
dev/                    playtest driver, perf benchmark, balance simulation, run scripts
docs/                   exported web build (GitHub Pages) and screenshots
```

`GameSession` is the single entry point for actions. Each action is resolved
completely (merges, payouts, Current refund, turn, Surge choice) and saved in
**one** atomic write of `{version, profile, run}`; the UI only replays the
returned events as animation. A reload therefore always lands on the resolved
state and cannot repeat a payout or a release. A Surge that is previewing is saved
as pending (cells and tiers chosen from the seeded RNG, whose state is saved too)
and is replayed and landed once on resume.

## Rules decisions worth knowing

The brief left some details open; these are the choices made:

* **Resolution order.** After a pair merge, look for a line through the result
  (horizontal before vertical), else an adjacent trio (neighbour order N, E, S, W),
  repeating from each new result. If nothing follows from the last result, any
  remaining line that **contains a cell the action changed** is resolved (for
  Currents and slides). Lines already sitting on the board (starter layout,
  Surges) stay dormant until something touches them. Windows are scanned by their
  first cell top-to-bottom, left-to-right; a run of four therefore resolves the
  first window containing a changed cell.
* **Payout.** Every merge pays coins **and** pearls, looked up by the tier it
  produces. Step 0 is 1x; each automatic follow-up multiplies both by 1.5 again.
  Integer maths, **round half up**, defined once in `Rewards.scale()`. The pearl
  sprite flying to the balance is cosmetic; the balance itself is saved with the action.
* **Chain / refund.** A chain is a merge whose *result* triggers another merge.
  An independent second line produced by the same Current starts again at 1x. One
  Current is earned back per turn, only if some result caused a follow-up.
* **Stuck.** "Advance the tide" is offered when there is no pair, no slide, no
  effective Current and nothing releasable. With 12 creature types this cannot
  happen in normal play (a full board must repeat a creature, and repeats are
  either pairs or releasable), so it is a safety net, exercised through a test flag.

## Tests

```bash
GODOT=/path/to/godot dev/run_tests.sh            # headless rules/economy/tide tests (320 checks)
GODOT=/path/to/godot dev/run_playtest.sh tutorial 405x720 --fresh   # live UI with injected input + screenshots (needs xvfb-run)
GODOT=/path/to/godot dev/run_u2_checkpoint.sh    # Update 2: real session + 4 relaunches with the clock moved forward
GODOT=/path/to/godot dev/run_u3_checkpoint.sh    # Update 3: visitor across relaunches, v1/v2 saves in the v3 build
GODOT=/path/to/godot dev/run_perf.sh . [baseline-dir]   # same benchmark on any checkout
```

Playtest scenarios (`dev/playtest.gd`): `tutorial touch rules_ui tide reduced_motion free_current input layout
hub_layout hub u2_* u3_tide u3_visitor u3_trial u3_goals u3_layout full_run ...`. Screenshots go to `dev/out/`.
`dev/sim.gd` is a rules-only balance probe; `dev/perfbench.gd` the benchmark (see `dev/perf/README.md`).

## Not built yet

Mutations, tools, additional zones, live services and monetisation. Coins and pearls are banked; coins now
buy decorations (pearls have no use yet).

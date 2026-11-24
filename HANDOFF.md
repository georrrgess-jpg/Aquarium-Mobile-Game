# Tidepool Tycoon · handoff (work in progress)

## Update 2 checkpoint (local commit)
Shipped: smoother pool + unified teal/sand/coral style, Current preview that marks the exact three-in-a-row,
gesture cancel/rapid-input guards, reef hub (aquarium, roster, decorations, income, offline chest),
passive income `5 x 1.8^(tier-1)` x `(1 + Beauty/100)`, 8 h chest cap, five decorations, save v1 -> v2 migration,
perf pass (see dev/perf/).
Checks: `dev/run_tests.sh` (133 + 73 rules checks), `dev/run_u2_checkpoint.sh` (5 relaunches with fake clock),
`dev/playtest.gd` scenarios `tutorial touch rules_ui tide reduced_motion free_current input layout hub_layout`.

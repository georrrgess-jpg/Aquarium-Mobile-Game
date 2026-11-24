extends "res://dev/playtest.gd"
## A long visit played through the live UI by a bot that follows the Hint, spanning several runs,
## the hub, a decoration purchase, a Trial and Calm Pool. One human turn is counted as 4 s, so a
## "20 minute session" here means 300 turns at human pace (the animations run faster with --speed).
##   dev/run_playtest.sh session 405x720 --fresh --speed=8
## Prints per-run lengths, floods, stalls, first-release time, goal results and the worst frames.

const SECS_PER_TURN: float = 4.0
const TARGET_SECS: float = 1200.0

var human_secs: float = 0.0
var worst_frame: float = 0.0
var hitches: int = 0
var frames_seen: int = 0

func _process(delta: float) -> void:
	frames_seen += 1
	if frames_seen > 30:
		worst_frame = maxf(worst_frame, delta)
		if delta > 0.1:
			hitches += 1

func _bot_step() -> String:
	var se: GameSession = session()
	var h: Dictionary = Hints.suggest(se)
	match String(h["kind"]):
		"release":
			await drag(cell_center(int(h["src"])), gate_center())
		"chain", "merge", "line", "slide":
			await drag(cell_center(int(h["src"])), cell_center(int(h["dst"])))
		"current":
			var c: Dictionary = h["current"]
			await click_btn(pool().btn_current)
			await click(tab_pos(int(c["axis"]), int(c["index"])))
			await click_btn(pool().btn_dir_a if int(c["dir"]) < 0 else pool().btn_dir_b)
			await click_btn(pool().btn_confirm)
		"tide":
			await click_btn(pool().btn_tide)
		_:
			return "stall"
	await idle()
	if pool().arrival.visible:
		await click(pool().arrival.btn_keep.get_global_rect().get_center())
		await idle()
	return String(h["kind"])

func scenario_session() -> void:
	var se: GameSession = session()
	var runs: Array = []
	var first_release_s: float = -1.0
	var stalls: int = 0
	var visits: PackedStringArray = PackedStringArray()
	# the guided first run: Play from the new reef, then the bot follows the Hint
	await click_btn(main.hub.btn_play)
	var run_no: int = 0
	var t_play: float = human_secs
	while human_secs < TARGET_SECS:
		run_no += 1
		var turns0: int = 0
		var first_rel: float = -1.0
		var steps: int = 0
		var kinds: Dictionary = {}
		while main.current == "pool" and steps < 900:
			steps += 1
			var turn_before: int = se.run.turn
			var k: String = await _bot_step()
			if k == "stall":
				stalls += 1
				break
			kinds[k] = int(kinds.get(k, 0)) + 1
			if se.run != null and se.run.turn > turn_before:
				human_secs += SECS_PER_TURN
			else:
				human_secs += 1.0                      # a release or a rejected action still takes a second
			if first_rel < 0.0 and k == "release":
				first_rel = human_secs - t_play
			if first_release_s < 0.0 and k == "release":
				first_release_s = human_secs
		var r: RunState = se.run
		var goal_txt: String = "none"
		if r != null and not r.goal.is_empty():
			goal_txt = "%s %s" % [r.goal["id"], "done" if bool(r.goal["done"]) else "missed (%d/%d)" % [int(r.goal["progress"]), int(r.goal["target"])]]
		runs.append({"run": run_no, "turns": (r.turn if r != null else 0), "flooded": main.current == "summary", "releases": (int(r.stats["releases"]) if r != null else 0),
			"first_release_s": first_rel, "goal": goal_txt, "min": human_secs - t_play})
		print("[session] run %d: %d turns, %s, %d releases, goal %s, human time %.1f min, kinds %s" % [run_no, runs[-1]["turns"], "FLOODED" if runs[-1]["flooded"] else "ended otherwise", runs[-1]["releases"], goal_txt, (human_secs - t_play) / 60.0, str(kinds)])
		if main.current != "summary":
			break
		# between runs: a visit to the reef, a Trial attempt and a few Calm turns (every other run)
		await click_btn(main.summary_screen.btn_reef)
		visits.append("reef")
		var p: Profile = se.profile
		for i in GameConfig.DECORATIONS.size():
			var def: Dictionary = GameConfig.DECORATIONS[i]
			if not ReefEconomy.owns(p, String(def["id"])) and p.coins >= int(def["price"]):
				for slot in GameConfig.DECOR_SLOTS.size():
					if ReefEconomy.can_purchase(p, String(def["id"]), slot)["ok"]:
						se.purchase_decoration(String(def["id"]), slot)
						visits.append("bought " + String(def["name"]))
						break
				break
		human_secs += 20.0
		if run_no % 2 == 0:
			await click_btn(main.hub.tab_buttons[3])
			await click(main.hub.modes_list.row_center_global("calm"))
			var cp: PoolScreen = main.calm_screen
			for m in 8:
				var cb: Board = cp.session.run.board
				var did: bool = false
				for i in cb.cells.size():
					if cb.code_at(i) == 0 or did:
						continue
					var tg: Dictionary = cp.session.valid_targets(i)
					if (tg["merge"] as PackedInt32Array).size() > 0:
						await drag(cp.board_view.cell_center_global(i), cp.board_view.cell_center_global(int((tg["merge"] as PackedInt32Array)[0])))
						did = true
				await idle()
				while cp.busy:
					await get_tree().process_frame
				human_secs += SECS_PER_TURN
			visits.append("calm %d turns" % cp.session.run.turn)
			await click_btn(cp.btn_home)
		else:
			await click_btn(main.hub.tab_buttons[3])
			await click(main.hub.modes_list.row_center_global("chain"))
			var tp: PoolScreen = main.trial_screen
			for st in 2:
				var g: Dictionary = tp.trial.hint_guide()
				if g.is_empty():
					break
				await drag(tp.board_view.cell_center_global(int(g["from"])), tp.board_view.cell_center_global(int(g["to"])))
				await idle()
				while tp.busy and not tp.results_panel.visible:
					await get_tree().process_frame
			visits.append("chain trial " + ("cleared" if tp.trial.status == TideTrial.WON else "not cleared"))
			human_secs += 30.0
			await click(tp.btn_res_back.get_global_rect().get_center())
		await click_btn(main.hub.btn_play)
		if main.current == "summary":
			await click_btn(main.summary_screen.btn_new)
		elif main.current != "pool":
			break
	print("[session] ---- summary ----")
	print("[session] human-paced time %.1f min over %d runs, stalls %d, visits: %s" % [human_secs / 60.0, runs.size(), stalls, ", ".join(visits)])
	var floods: int = 0
	var lens: PackedStringArray = PackedStringArray()
	for r2 in runs:
		if bool(r2["flooded"]):
			floods += 1
		lens.append(str(r2["turns"]))
	print("[session] run lengths (turns): %s | floods %d/%d | first release at %.0f s of play" % [", ".join(lens), floods, runs.size(), first_release_s - t_play])
	print("[session] worst frame %.0f ms, frames over 100 ms: %d of %d (software GL, desktop only)" % [worst_frame * 1000.0, hitches, frames_seen])
	check(runs.size() >= 3, "the session spans several runs (%d)" % runs.size())
	check(stalls == 0, "no stall: the bot always had a legal action")

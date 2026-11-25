extends "res://dev/playtest.gd"
## Final UI review driver: reaches every player-facing screen/overlay, takes a screenshot and
## runs objective layout checks (safe area, tap size, overlap, text fit). Run with:
##   PT_SCRIPT=ui_review GODOT=... dev/run_playtest.sh SCENARIO 405x720 --fresh --safe=48,34
## Screenshots: dev/out/rv_<name>_<width>.png

const MIN_TAP: float = 40.0

func W() -> int:
	return int(DisplayServer.window_get_size().x)

func rshot(name: String) -> void:
	await shot("rv_%s_%d" % [name, W()])

# --- generic audit ---------------------------------------------------------------------------

func active_screen() -> Control:
	for sc in [main.hub, main.pool_screen, main.trial_screen, main.help_screen, main.calm_screen, main.summary_screen]:
		if (sc as Control).visible:
			return sc
	return null

## The part of a widget the player can see: clipped to any ScrollContainer it lives in.
func visible_rect(c: Control) -> Rect2:
	var r: Rect2 = c.get_global_rect()
	var p: Node = c.get_parent()
	while p != null:
		if p is ScrollContainer:
			r = r.intersection((p as ScrollContainer).get_global_rect())
		p = p.get_parent()
	return r

func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control:
			var cc: Control = c
			if not cc.visible:
				continue
			if cc is PillButton or cc is HudWidgets.Chip or cc is HudWidgets.SurgeStrip or cc is HudWidgets.GoalStrip:
				out.append(cc)
			_collect(cc, out)

func safe_rect() -> Rect2:
	var vp: Rect2 = get_viewport().get_visible_rect()
	return Rect2(vp.position.x, vp.position.y + main.safe_top, vp.size.x, vp.size.y - main.safe_top - main.safe_bottom)

## Safe area, tap size, text fit and overlap of the widgets of the visible screen. `only` limits the
## audit to the descendants of one overlay (help sheet, arrival card, results panel).
func audit(label: String, only: Control = null, min_tap: float = MIN_TAP) -> void:
	var scr: Control = active_screen()
	var root: Node = only if only != null else scr
	var items: Array = []
	if only != null and (only is PillButton):
		items.append(only)
	_collect(root, items)
	var safe: Rect2 = safe_rect().grow(0.5)
	var bad: PackedStringArray = PackedStringArray()
	for c in items:
		var cc: Control = c
		var r: Rect2 = visible_rect(cc)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue          # scrolled out of view
		if not safe.encloses(r):
			bad.append("%s %s leaves the safe area %s" % [cc.get_class(), _nm(cc), r])
		if cc is PillButton:
			var pb: PillButton = cc
			if minf(r.size.x, r.size.y) < min_tap:
				bad.append("tap target '%s' only %.0fx%.0f" % [pb.text, r.size.x, r.size.y])
			if not pb.content_fits():
				bad.append("button '%s' content does not fit" % pb.text)
		elif cc is HudWidgets.Chip:
			if not (cc as HudWidgets.Chip).text_fits():
				bad.append("chip '%s' does not fit" % (cc as HudWidgets.Chip).value)
		elif cc is HudWidgets.GoalStrip:
			if not (cc as HudWidgets.GoalStrip).fits():
				bad.append("goal strip text does not fit")
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Control = items[i]
			var b: Control = items[j]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			var inter: float = visible_rect(a).intersection(visible_rect(b)).get_area()
			if inter > 1.0:
				bad.append("%s overlaps %s (%.0f px2)" % [_nm(a), _nm(b), inter])
	check(bad.is_empty(), "audit[%s @%d] %d widgets%s" % [label, W(), items.size(), "" if bad.is_empty() else "  -> " + "; ".join(bad)])

func _nm(c: Control) -> String:
	if c is PillButton:
		return "btn('%s')" % (c as PillButton).text
	if c is HudWidgets.Chip:
		return "chip(%s)" % (c as HudWidgets.Chip).label
	return c.get_class()

## A toast must lie inside the safe area and (for required targets) not cover given rects.
func audit_toast(sc: PoolScreen, label: String, keep_clear: Array = []) -> void:
	var t: Control = sc.toast
	var bad: PackedStringArray = PackedStringArray()
	if not t.visible:
		check(false, "toast[%s] is not visible" % label)
		return
	var r: Rect2 = t.get_global_rect()
	if not safe_rect().grow(0.5).encloses(r):
		bad.append("toast leaves safe area %s" % r)
	if r.size.x > 500.0 or r.size.y > 140.0:
		bad.append("toast is huge %s" % r.size)
	for kc in keep_clear:
		var kr: Rect2 = kc
		if r.intersects(kr):
			bad.append("toast covers a required target %s" % kr)
	for b in [sc.btn_current, sc.btn_confirm, sc.btn_dir_a, sc.btn_dir_b, sc.btn_hint, sc.btn_help, sc.btn_skip]:
		var bb: Control = b
		if bb.is_visible_in_tree() and r.intersects(bb.get_global_rect()):
			bad.append("toast covers button '%s'" % (bb as PillButton).text)
	check(bad.is_empty(), "toast[%s @%d] %.0fx%.0f at y=%.0f%s" % [label, W(), r.size.x, r.size.y, r.position.y, "" if bad.is_empty() else " -> " + "; ".join(bad)])

func cells_rects(sc: PoolScreen, cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		out.append(sc.board_view.get_global_transform() * sc.board_view.cell_rect(int(c)))
	return out

func cell_global_rect(sc: PoolScreen, c: int) -> Rect2:
	var r: Rect2 = sc.board_view.cell_rect(c)
	return Rect2(sc.board_view.get_global_transform() * r.position, r.size)

func guide_clear(sc: PoolScreen, label: String) -> void:
	var g: Dictionary = sc.board_view.guide
	if g.is_empty():
		return
	var lr: Rect2 = sc.board_view.guide_label_rect
	var bad: bool = false
	if lr.size.x > 0.0:
		for c in g.get("cells", []):
			if lr.intersects(sc.board_view.cell_rect(int(c))):
				bad = true
	check(not bad, "guide label '%s' clear of its cells [%s @%d]" % [g.get("label", ""), label, W()])

func prompt_fits(sc: PoolScreen, label: String) -> void:
	var pl: Label = sc.prompt_label
	var lines: int = pl.get_line_count()
	var fits: bool = lines <= 2 and pl.get_minimum_size().y <= pl.size.y + 1.0
	check(fits, "prompt fits 2 lines [%s @%d] (%d lines, %.0f of %.0f px): '%s'" % [label, W(), lines, pl.get_minimum_size().y, pl.size.y, pl.text])

func tier_board_full() -> Board:
	var rows: Array = []
	for r in GameConfig.ROWS:
		var toks: PackedStringArray = PackedStringArray()
		for c in GameConfig.COLS:
			toks.append("S1" if (r + c) % 2 == 0 else "F2")
		rows.append(" ".join(toks))
	return rows_board(rows)

func established(coins: int = 54321) -> GameSession:
	var se: GameSession = session()
	se.profile.tutorial = {"done": true, "skipped": true, "milestone": true, "restarts": 0}
	se.profile.coins = coins
	se.save()
	return se

func long_residents() -> Array:
	var out: Array = []
	var id: int = 1
	for spec in [[2, 5], [1, 4], [2, 6], [1, 5], [2, 4], [1, 6], [2, 5], [3, 4], [1, 4], [2, 4], [1, 5], [2, 6]]:
		out.append({"id": id, "code": Creature.make(int(spec[0]), int(spec[1])), "family": int(spec[0]), "tier": int(spec[1]), "run": 1})
		id += 1
	return out

# --- 1. first-run reef ---------------------------------------------------------------------------

func scenario_rv_hub_first() -> void:
	var h: ReefHub = main.hub
	check(h.is_minimal() and h.btn_play.visible and h.btn_play.text == "Play", "first run: one Play button")
	var vis: PackedStringArray = PackedStringArray()
	for b in [h.btn_play, h.btn_motion, h.btn_sound, h.btn_haptics, h.btn_help]:
		if (b as Control).visible:
			vis.append((b as PillButton).text if (b as PillButton).text != "" else "(help icon)")
	print("[review] visible buttons on first run: ", vis)
	await rshot("01_first_run_reef")
	audit("first-run reef")
	check(not h.chip_coins.visible and not h.panel.visible, "no panel, chips or tabs yet")
	await click_btn(h.btn_motion)
	await click_btn(h.btn_sound)
	await click_btn(h.btn_haptics)
	check(h.btn_motion.text == "Motion: reduced" and h.btn_sound.text == "Sound: off" and h.btn_haptics.text == "Haptics: off", "settings toggles flip")
	audit("first-run reef toggled")
	await rshot("01b_first_run_toggled")
	await click_btn(h.btn_motion)
	await click_btn(h.btn_sound)
	await click_btn(h.btn_haptics)
	await click_btn(h.btn_help)
	check(h.help_sheet.visible, "the hub Help sheet opens")
	var hs: Rect2 = h.help_sheet.get_global_rect()
	check(safe_rect().encloses(hs) and hs.encloses(h.help_sheet.btn_replay.get_global_rect()) and hs.encloses(h.help_sheet.btn_close.get_global_rect()), "help sheet and its buttons are inside the safe area")
	audit("hub help sheet", h.help_sheet)
	await rshot("01c_hub_help_sheet")
	await click_btn(h.help_sheet.btn_close)

# --- 2. guided pool ---------------------------------------------------------------------------------

func scenario_rv_guided() -> void:
	var se: GameSession = session()
	await click_btn(main.hub.btn_play)
	await frames(8)
	var sc: PoolScreen = pool()
	await rshot("02a_step1_pair")
	audit("guided step 1")
	prompt_fits(sc, "step 1")
	guide_clear(sc, "step 1")
	var lab: Rect2 = board().guide_label_rect
	print("[review] step1 label rect ", lab, " cells ", board().guide.get("cells", []))
	# the on-board label must not hide the tutorial's own cells or the gate
	await drag(cell_center(i_(4, 1)), cell_center(i_(4, 2)))
	await idle()
	await frames(6)
	await rshot("02b_step2_current_prompt")
	audit("guided step 2")
	prompt_fits(sc, "step 2")
	await click_btn(sc.btn_current)
	await rshot("02c_current_mode_tabs")
	prompt_fits(sc, "current picked")
	await click(tab_pos(Board.AXIS_ROW, 1))
	await rshot("02d_current_row_chosen")
	audit("guided row chosen")
	await click_btn(sc.btn_dir_a)
	await frames(4)
	await rshot("02e_current_preview")
	audit("guided current preview")
	prompt_fits(sc, "preview")
	await click_btn(sc.btn_confirm)
	await frames(6)
	await rshot("02f_step3_merge")
	prompt_fits(sc, "step 3")
	guide_clear(sc, "step 3")
	var g2: Dictionary = board().guide
	await click(cell_center(int(g2["cells"][0])))
	await click(cell_center(int(g2["cells"][1])))
	await get_tree().create_timer(0.7).timeout
	await rshot("02g_first_surge_preview")
	audit("first surge preview")
	prompt_fits(sc, "surge")
	await idle()
	await frames(6)
	await rshot("02h_step4_release")
	audit("guided step 4")
	prompt_fits(sc, "step 4")
	guide_clear(sc, "step 4")
	var rel: int = -1
	for i in se.run.board.cells.size():
		if Creature.tier_of(se.run.board.code_at(i)) >= 4:
			rel = i
	# the label for step 4 must not sit on the cell or the gate
	var lr4: Rect2 = board().guide_label_rect
	var gate_local: Rect2 = Rect2(board().get_global_transform().affine_inverse() * pool().gate.get_global_rect().position, pool().gate.size)
	check(lr4.size.x == 0.0 or not lr4.intersects(gate_local), "step 4 label does not cover the Reef Gate")
	await drag(cell_center(rel), gate_center())
	await idle()
	await frames(10)
	await rshot("02i_arrival_card")
	check(sc.arrival.visible, "arrival card shows")
	var ar: Rect2 = sc.arrival.get_global_rect()
	check(safe_rect().encloses(ar) and ar.encloses(sc.arrival.btn_visit.get_global_rect()) and ar.encloses(sc.arrival.btn_keep.get_global_rect()), "arrival card and its buttons are inside the safe area / card")
	audit("arrival card", sc.arrival)
	print("[review] arrival font size ", sc.arrival._fs, " lines ", sc.arrival._lines.size(), " size ", sc.arrival.size)

## Skip two-tap, Help sheet and practice, recovery bar.
func scenario_rv_guided_misc() -> void:
	var se: GameSession = session()
	await click_btn(main.hub.btn_play)
	await drag(cell_center(i_(4, 1)), cell_center(i_(4, 2)))
	await idle()
	var sc: PoolScreen = pool()
	await click_btn(sc.btn_skip)
	await frames(4)
	check(sc.btn_skip.text == "Sure?", "Skip armed")
	await rshot("02j_skip_armed")
	audit("skip armed")
	audit_toast(sc, "skip", cells_rects(sc, board().guide.get("cells", [])))
	prompt_fits(sc, "skip armed")
	await get_tree().create_timer(2.8).timeout
	await click_btn(sc.btn_help)
	await rshot("02k_help_sheet")
	audit("pool help sheet", sc.help_sheet)
	var hs: Rect2 = sc.help_sheet.get_global_rect()
	check(safe_rect().encloses(hs), "help sheet inside the safe area")
	print("[review] help sheet font ", sc.help_sheet._fs, " lines ", sc.help_sheet._lines.size(), " size ", sc.help_sheet.size)
	await click_btn(sc.help_sheet.btn_replay)
	await frames(8)
	await rshot("02l_help_practice")
	var hp: PoolScreen = main.help_screen
	audit("help practice")
	prompt_fits(hp, "help practice")
	await click(hp.btn_home.get_global_rect().get_center())
	await click_btn(main.hub.btn_play)
	# recovery bar
	se.run.board = Board.from_text(["S1 F1 S2 F2 S3 F3"])
	se.run.currents = 0
	se.run.tut_flags = {"pair": false, "current": false, "surge": false, "release": false}
	sc._recovery_version = -1
	sc._refresh_all()
	await frames(4)
	check(sc._recovery and sc.btn_restart_guided.visible, "recovery bar visible")
	await rshot("02m_recovery_bar")
	audit("recovery bar")
	prompt_fits(sc, "recovery")

# --- 3. established hub ------------------------------------------------------------------------------

func setup_established_hub(chest: bool, dec_n: int = 2) -> void:
	var se: GameSession = established(12345)
	GameClock.set_tz_bias_seconds(0)
	GameClock.freeze(at(12, 0))
	se.profile.residents = long_residents()
	se.profile.next_resident_id = 13
	se.profile.unseen_residents = [12, 11]
	var decs: Array = [{"id": "coral_fan", "slot": 1}, {"id": "sea_lantern", "slot": 4}]
	se.profile.decorations = decs.slice(0, dec_n)
	se.profile.income_stamp = GameClock.now() - (6 * 3600 if chest else 0)
	se.settle_income()
	for code in [11, 12, 13, 14, 21, 22, 23, 24]:
		Book.note_made(se.profile, code)
	Book.note_released(se.profile, 14)

func scenario_rv_hub() -> void:
	var se: GameSession = established(12345)
	setup_established_hub(true)
	main.show_screen("start")
	await frames(8)
	var h: ReefHub = main.hub
	# Residents (+ chest banner, long names)
	await click_btn(h.tab_buttons[0])
	await rshot("03a_residents_chest")
	check(h.chest_banner.visible, "the chest banner is shown")
	audit("hub residents+chest")
	check_hub_layout("residents+chest")
	# Decor: nothing chosen, then each state of the buy button
	await click_btn(h.tab_buttons[1])
	await rshot("03b_decor_none")
	audit("decor none")
	h._select_decor(2)               # Bubble Column? (index 2 = sea lantern is owned) -> pick an unowned one
	await frames(3)
	var unowned: int = -1
	for i in GameConfig.DECORATIONS.size():
		if not ReefEconomy.owns(se.profile, String(GameConfig.DECORATIONS[i]["id"])):
			unowned = i
			break
	h._cancel_placement()
	h.toast.hide_now()
	h._select_decor(4)               # light shaft 7,000: not affordable at 12k? coins set below
	se.profile.coins = 300
	h._refresh_numbers()
	h._refresh_decor()
	await frames(3)
	h.toast.hide_now()
	await rshot("03c_decor_pick_spot")
	check(h.btn_buy.text == "Pick a spot", "buy state: Pick a spot")
	audit("decor pick a spot")
	var slot: int = 0
	for s in range(0, 8):
		var taken: bool = false
		for d in se.profile.decorations:
			if int(d["slot"]) == s:
				taken = true
		if not taken:
			slot = s
			break
	h._select_slot(slot)
	await frames(3)
	await rshot("03d_decor_cant_afford")
	check(h.btn_buy.text == "Not enough coins", "buy state: Not enough coins")
	audit("decor cant afford")
	check(h.decor_summary.get_line_count() <= 3, "decor summary fits (%d lines)" % h.decor_summary.get_line_count())
	se.profile.coins = 123456789012
	h._refresh_numbers()
	h._refresh_decor()
	await frames(3)
	await rshot("03e_decor_buy_huge_coins")
	check(h.btn_buy.text.begins_with("Buy for"), "buy state: Buy for ...")
	audit("decor buy, huge balance")
	check_hub_layout("decor buy huge coins")
	h._cancel_placement()
	se.profile.coins = 12345
	h._refresh_numbers()
	# Goals incl. the Tide Goal row (needs a run)
	await click_btn(h.tab_buttons[2])
	await rshot("03f_goals_no_run")
	audit("goals no run")
	se.start_run()
	main.show_screen("start")
	await frames(6)
	await click_btn(h.tab_buttons[2])
	await rshot("03g_goals_tide_goal")
	audit("goals with Tide Goal")
	# Modes
	await click_btn(h.tab_buttons[3])
	await rshot("03h_modes")
	audit("modes")
	# Book
	await click_btn(h.tab_buttons[4])
	await rshot("03i_book")
	audit("book")
	check_hub_layout("book")
	GameClock.reset()

func scenario_rv_hub_visitor() -> void:
	var se: GameSession = established(12345)
	setup_established_hub(false)
	GameClock.freeze(at(6, 30))
	main.show_screen("start")
	await frames(12)
	var h: ReefHub = main.hub
	check(h.visitor_banner.visible, "visitor banner visible at dawn")
	await click_btn(h.tab_buttons[0])
	await rshot("03j_visitor_offer")
	audit("visitor offered")
	check_hub_layout("visitor offered")
	await click_btn(h.btn_accept)
	await frames(10)
	await rshot("03k_visitor_accepted_toast")
	audit("visitor accepted")
	check(h.toast.visible, "accept toast visible")
	var tr: Rect2 = h.toast.get_global_rect()
	check(not tr.intersects(h.reef.get_global_rect()), "hub toast %s stays off the aquarium %s" % [tr, h.reef.get_global_rect()])
	check(safe_rect().encloses(tr), "hub toast inside the safe area")
	# chest + visitor + long banner text
	se.profile.income_stamp = GameClock.now() - 6 * 3600
	se.settle_income()
	main.show_screen("start")
	await frames(10)
	await rshot("03l_visitor_and_chest")
	print("[review] panel ", h.panel.get_global_rect(), " scroll ", h.roster_scroll.get_global_rect(), " tab ", h._active_tab)
	audit("visitor + chest")
	check_hub_layout("visitor + chest")
	GameClock.reset()

func scenario_rv_tides() -> void:
	var se: GameSession = established(12345)
	setup_established_hub(true)
	for spec in [[6, 30, "dawn"], [12, 0, "midday"], [17, 30, "dusk"], [22, 0, "night"]]:
		GameClock.freeze(at(int(spec[0]), int(spec[1])))
		se.profile.income_stamp = GameClock.now() - 3600
		main._apply_tide(true)
		main.show_screen("start")
		await frames(12)
		await click_btn(main.hub.tab_buttons[0])
		await rshot("03m_tide_%s" % spec[2])
		audit("hub " + spec[2])
		check_hub_layout("tide " + spec[2])
		await click_btn(main.hub.tab_buttons[1])
		await rshot("03n_tide_%s_decor" % spec[2])
	GameClock.reset()

# --- 4. standard pool ------------------------------------------------------------------------------------

func scenario_rv_pool() -> void:
	var se: GameSession = established()
	GameClock.set_tz_bias_seconds(0)
	main.hub.refresh("start")
	await click_btn(main.hub.btn_play)
	var sc: PoolScreen = pool()
	check(sc.goal_strip.visible, "Tide Goal strip shown")
	await rshot("04a_pool_tide_goal")
	audit("pool tide goal")
	check(sc.goal_strip.fits(), "goal strip text fits")
	# long goal text
	se.run.goal = {"id": "release_family", "label": "Release a tier 4+ Starfish", "short": "Merge with a Current", "family": 2, "target": 12, "progress": 11, "done": false, "coins": 80, "pearls": 2}
	sc._refresh_all()
	await frames(3)
	check(sc.goal_strip.fits(), "goal strip text fits with a progress counter")
	await rshot("04b_pool_goal_progress")
	# Hint
	load_board(rows_board(["S1 . . . . S1", ". F1 F1 . . .", ". . . . . .", "S3 . . . . ."]), 2, 2)
	await click_btn(sc.btn_hint)
	await frames(4)
	await rshot("04c_hint_marks")
	audit("hint")
	prompt_fits(sc, "hint")
	guide_clear(sc, "hint")
	# Current mode: row/col tabs, directions, confirm
	await click_btn(sc.btn_current)
	await rshot("04d_current_mode")
	prompt_fits(sc, "current mode")
	await click(tab_pos(Board.AXIS_COL, 2))
	await rshot("04e_current_col_chosen")
	audit("current col chosen")
	prompt_fits(sc, "col chosen")
	await click_btn(sc.btn_dir_b)
	await frames(4)
	await rshot("04f_current_col_preview")
	audit("current col preview")
	prompt_fits(sc, "col preview")
	await click_btn(sc.btn_current)    # cancel
	# line preview that makes a merge
	load_board(rows_board([". . . . . .", "S2 . . . S2 S2", ". . . . . ."]), 2, 2)
	await click_btn(sc.btn_current)
	await click(tab_pos(Board.AXIS_ROW, 1))
	await click_btn(sc.btn_dir_a)
	await frames(4)
	await rshot("04g_line_preview_merge")
	audit("line preview merge")
	prompt_fits(sc, "line preview merge")
	sc._exit_current_mode()
	# Surge preview
	load_board(rows_board(["S1 F1 S2 . . .", ". . . . . ."]), 2, 2)
	var res: Dictionary = se.try_drop(i_(0, 2), i_(0, 3))
	sc._play_result(res)
	await get_tree().create_timer(0.8).timeout
	await rshot("04h_surge_preview")
	audit("surge preview")
	prompt_fits(sc, "surge preview")
	await idle()

func scenario_rv_toasts() -> void:
	var se: GameSession = established()
	main.hub.refresh("start")
	await click_btn(main.hub.btn_play)
	var sc: PoolScreen = pool()
	load_board(rows_board(["S1 F2 S6 . S6 .", ". . . . . ."]), 0, 0)
	var cases: Array = [
		["Only identical creatures merge", "invalid"],
		["Top tier! Send it through the Reef Gate", "capped"],
		["No Currents left. A chain earns one back.", "nocurrent"],
		["A Surge is landing", "resolving"],
		["The pool has flooded", "ended"],
		["Creatures slide one cell at a time", "invalid"],
		["The Reef Gate wants tier 4 or higher", "invalid"],
		["Select a tier 4+ creature, then tap the Reef Gate.", "info"],
		["Tap Skip again to leave the guided start. Rewards you earned are kept.", "info"],
		["Guided board restarted. Practice earns nothing until you finish; your rewards are safe.", "info"],
		["Chain! +1 Current", "info"],
		["Reduced motion on", "info"],
	]
	var n: int = 0
	for cs in cases:
		sc.toast.show_kind(String(cs[0]), String(cs[1]), 6.0)
		await frames(4)
		if n < 6 or n == 9:
			await rshot("04i_toast_%02d_%s" % [n, cs[1]])
		audit_toast(sc, "%s: %s" % [cs[1], String(cs[0]).left(24)])
		n += 1
	# long multi-line: goal complete + tide goal + Book + visitor
	var multi: String = "The Lantern Ray joins your reef!\nTide Goal complete: Release a Starfish  +80 coins +2 pearls\n+3 more: see the Goals and Book tabs"
	sc.toast.show_text(multi, 8.0)
	await frames(5)
	await rshot("04j_toast_multiline")
	audit_toast(sc, "5-line announce")
	var keys: Array = [sc.gate.get_global_rect()]
	print("[review] multiline toast rect ", sc.toast.get_global_rect(), " board ", sc.board_view.get_global_rect(), " prompt ", sc.prompt_panel.get_global_rect())
	# real flow: tier-4 goal done + a Book entry
	sc.toast.hide_now()
	se.run.goal = {"id": "tier4", "label": "Make a tier 4 creature", "short": "Make a tier 4", "family": 0, "target": 1, "progress": 0, "done": false, "coins": GameConfig.TIDE_GOAL_COINS, "pearls": GameConfig.TIDE_GOAL_PEARLS}
	load_board(rows_board(["S3 . . . . S3", ". . . . . .", ". . . . F1 F1"]), 0, 2)
	await drag_cells(i_(0, 0), i_(0, 5))
	await frames(6)
	await rshot("04k_toast_goal_done_real")
	audit("goal done real")
	audit_toast(sc, "goal done real")
	print("[review] real toast text: ", sc.toast.label.text.replace("\n", " | "))

func scenario_rv_flood() -> void:
	var se: GameSession = established()
	main.hub.refresh("start")
	await click_btn(main.hub.btn_play)
	var sc: PoolScreen = pool()
	var fb: Board = tier_board_full()
	fb.set_code(i_(6, 4), 0)
	fb.set_code(i_(6, 5), 0)
	load_board(fb, 2, 2)
	await drag(cell_center(i_(6, 3)), cell_center(i_(6, 4)))
	await get_tree().create_timer(0.5).timeout
	await rshot("04l_flood_notice")
	audit("flood notice")
	prompt_fits(sc, "flood")
	var ssr: Rect2 = sc.surge_strip.get_global_rect()
	var font: Font = ThemeDB.fallback_font
	var tx: float = 16.0 + float(sc.surge_strip.cadence) * 26.0 + 6.0
	var need: float = font.get_string_size(sc.surge_strip.message, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	check(tx + need <= sc.surge_strip.size.x - 8.0, "flood message fits its strip (%.0f of %.0f)" % [tx + need, sc.surge_strip.size.x - 8.0])

func scenario_rv_reduced() -> void:
	var se: GameSession = established()
	await click_btn(main.hub.btn_motion)
	main.hub.refresh("start")
	await click_btn(main.hub.btn_play)
	var sc: PoolScreen = pool()
	check(sc.reduced_motion, "reduced motion is on in the pool")
	load_board(rows_board(["S1 F1 S2 . . .", ". . . . . ."]), 2, 2)
	await click_btn(sc.btn_motion)
	await frames(4)
	await rshot("04m_reduced_toggle_toast")
	audit_toast(sc, "reduced motion toggle")
	await click_btn(sc.btn_motion)
	var res: Dictionary = se.try_drop(i_(0, 2), i_(0, 3))
	sc._play_result(res)
	await get_tree().create_timer(0.8).timeout
	await rshot("04n_reduced_surge_preview")
	audit("reduced surge preview")
	await idle()

# --- 5. results ----------------------------------------------------------------------------------------------

func scenario_rv_results() -> void:
	var se: GameSession = established(123456789012)
	se.profile.pearls = 98765432101
	main.hub.refresh("start")
	await click_btn(main.hub.btn_play)
	se.run.goal = {"id": "merges", "label": "Release a tier 4+ Harlequin Shrimp or Sunflower Starfish", "short": "12 merges", "family": 0, "target": 12, "progress": 5, "done": false, "coins": 80, "pearls": 2}
	var fb: Board = tier_board_full()
	fb.set_code(i_(6, 4), 0)
	fb.set_code(i_(6, 5), 0)
	for k in [[0, 0, 1, 4], [0, 1, 2, 5], [0, 2, 1, 6], [0, 3, 2, 4], [0, 4, 1, 5], [0, 5, 2, 6], [1, 0, 1, 4]]:
		fb.set_code(i_(int(k[0]), int(k[1])), Creature.make(int(k[2]), int(k[3])))
	se.run.stats["best_merge_code"] = Creature.make(Creature.STAR, 5)
	se.run.stats["best_merge_tier"] = 5
	se.run.stats["best_chain"] = 12
	se.run.stats["releases"] = 123456
	se.run.stats["merges"] = 98765
	se.run.stats["coins"] = 123456789012
	se.run.stats["pearls"] = 98765432101
	load_board(fb, 2, 2)
	await drag(cell_center(i_(6, 3)), cell_center(i_(6, 4)))
	await idle_until_summary()
	var sc: SummaryScreen = main.summary_screen
	await frames(6)
	await rshot("05a_results_goal_missed_many_survivors")
	audit("results missed", sc.panel)
	check_results(sc, "missed")
	se.run.goal["done"] = true
	se.run.goal["label"] = "Make a merge with a Current"
	sc.refresh()
	await frames(4)
	await rshot("05b_results_goal_done")
	check_results(sc, "done")
	# release one survivor -> NEW reef button; then release all -> no survivors
	await frames(2)
	sc.btn_all.pressed.emit()
	await frames(6)
	await rshot("05c_results_released_all")
	print("[review] surv_title ", sc.surv_title.get_global_rect(), " scroll ", sc.surv_scroll.get_global_rect(), " text '", sc.surv_title.text, "' vis ", sc.btn_all.visible)
	check_results(sc, "released all")
	audit("results released", sc.panel)
	# the plain case: no survivors, no goal
	se.run.goal = {}
	sc.refresh()
	await frames(3)
	await rshot("05d_results_no_goal")
	check_results(sc, "no goal")

func check_results(sc: SummaryScreen, label: String) -> void:
	var bad: PackedStringArray = PackedStringArray()
	var pr: Rect2 = sc.panel.get_global_rect()
	if not safe_rect().grow(0.5).encloses(pr):
		bad.append("panel leaves safe area %s" % pr)
	var blocks: Array = [sc.title_label, sc.stats_label, sc.band, sc.goal_label, sc.banked_label, sc.surv_title, sc.surv_scroll, sc.btn_new, sc.btn_reef, sc.btn_home]
	if sc.btn_all.visible:
		blocks.append(sc.btn_all)
	for l in [sc.title_label, sc.stats_label, sc.goal_label, sc.banked_label, sc.surv_title]:
		var lb: Label = l
		if lb.visible and lb.get_minimum_size().y > lb.size.y + 1.0:
			bad.append("label '%s' needs %.0f px but has %.0f" % [lb.text.left(24), lb.get_minimum_size().y, lb.size.y])
	for a in blocks:
		var ca: Control = a
		if not ca.visible:
			continue
		for b2 in blocks:
			var cb: Control = b2
			if ca == cb or not cb.visible or str(ca.get_instance_id()) >= str(cb.get_instance_id()):
				continue
			if ca.get_global_rect().intersection(cb.get_global_rect()).get_area() > 1.0:
				bad.append("%s overlaps %s" % [ca.get_class() + ":" + (ca as Label).text.left(16) if ca is Label else ca.get_class(), cb.get_class() + ":" + (cb as Label).text.left(16) if cb is Label else cb.get_class()])
	# buttons
	var btns: Array = [sc.btn_new, sc.btn_reef, sc.btn_home]
	if sc.btn_all.visible:
		btns.append(sc.btn_all)
	for b in btns:
		var pb: PillButton = b
		if not pb.content_fits():
			bad.append("button '%s' does not fit" % pb.text)
		if not pr.encloses(pb.get_global_rect()):
			bad.append("button '%s' leaves the panel" % pb.text)
		if minf(pb.size.x, pb.size.y) < MIN_TAP:
			bad.append("button '%s' tap target %.0fx%.0f" % [pb.text, pb.size.x, pb.size.y])
	# survivors: each Release button reachable (scroll) and big enough
	var small: int = 0
	for card in sc.surv_flow.get_children():
		for k in card.get_children():
			if k is PillButton and (k as PillButton).size.y < MIN_TAP:
				small += 1
	if small > 0:
		bad.append("%d survivor Release buttons are shorter than %.0f px" % [small, MIN_TAP])
	# scroll area must not overlap the action buttons
	var scr: Rect2 = sc.surv_scroll.get_global_rect()
	if scr.intersects(sc.btn_new.get_global_rect()):
		bad.append("survivor list overlaps Play Again")
	var br: Rect2 = sc.band.get_global_rect()
	if br.intersects(sc.goal_label.get_global_rect()) and sc.goal_label.visible:
		bad.append("band overlaps goal label")
	check(bad.is_empty(), "results[%s @%d]%s" % [label, W(), "" if bad.is_empty() else " -> " + "; ".join(bad)])

# --- 6. trials ------------------------------------------------------------------------------------------------------

func play_trial(id: String) -> void:
	var se: GameSession = session()
	main.hub.refresh("start")
	await click_btn(main.hub.tab_buttons[3])
	await click(main.hub.modes_list.row_center_global(id))
	var tp: PoolScreen = main.trial_screen
	check(main.current == "trial" and tp.trial.id == id, "trial %s opened" % id)
	await frames(6)
	await rshot("06_%s_a_start" % id)
	audit("trial %s start" % id)
	prompt_fits(tp, "trial %s start" % id)
	check(tp.surge_strip.custom_text != "", "trial goal text '%s'" % tp.surge_strip.custom_text)
	# hint
	await click_btn(tp.btn_hint)
	await frames(4)
	await rshot("06_%s_b_hint" % id)
	audit("trial %s hint" % id)
	audit_toast(tp, "trial %s hint" % id, cells_rects(tp, tp.board_view.guide.get("cells", [])))
	prompt_fits(tp, "trial %s hint" % id)
	# lose: burn the moves on any legal slide (never the hinted winning line)
	tp.toast.hide_now()
	var spent: int = 0
	var guard: int = 0
	while tp.trial.status == TideTrial.PLAYING and guard < 6:
		guard += 1
		var done: bool = false
		for i in tp.session.run.board.cells.size():
			if done or tp.session.run.board.code_at(i) == 0:
				continue
			var tg: Dictionary = tp.session.valid_targets(i)
			var mv: PackedInt32Array = tg["move"]
			if mv.size() > 0 and tp.trial.moves_left > 0:
				await _drag_in(tp, i, int(mv[mv.size() - 1]))
				done = true
		if not done:
			break
	var guard2: int = 0
	while not tp.results_panel.visible and guard2 < 300:
		await get_tree().process_frame
		guard2 += 1
	if tp.results_panel.visible and tp.trial.status == TideTrial.LOST:
		await frames(4)
		await rshot("06_%s_c_lost" % id)
		check_trial_panel(tp, "%s lost" % id)
		await click(tp.btn_res_retry.get_global_rect().get_center())
		await frames(4)
	else:
		print("[review] %s: could not lose by random slides (status %d); skipping lost panel" % [id, tp.trial.status])
		await click_btn(tp.btn_retry)
	# win with the hint sequence
	var steps: int = 0
	while tp.trial.status == TideTrial.PLAYING and steps < 4:
		steps += 1
		if id == "wrap":
			await click_btn(tp.btn_current)
			await click(tp.board_view.get_global_transform() * Vector2(BoardView.TAB * 0.5, BoardView.TAB + 2.5 * tp.board_view.cs))
			await click_btn(tp.btn_dir_a)
			await frames(3)
			await rshot("06_wrap_d_preview")
			audit("trial wrap preview")
			await click_btn(tp.btn_confirm)
		else:
			var g: Dictionary = tp.trial.hint_guide()
			await _drag_in(tp, int(g["from"]), int(g["to"]))
	var guard3: int = 0
	while not tp.results_panel.visible and guard3 < 400:
		await get_tree().process_frame
		guard3 += 1
	await frames(6)
	await rshot("06_%s_e_won" % id)
	check(tp.trial.status == TideTrial.WON, "trial %s won" % id)
	check_trial_panel(tp, "%s won" % id)
	await click(tp.btn_res_back.get_global_rect().get_center())

func check_trial_panel(tp: PoolScreen, label: String) -> void:
	var bad: PackedStringArray = PackedStringArray()
	var rp: Rect2 = tp.results_panel.get_global_rect()
	if not safe_rect().grow(0.5).encloses(rp):
		bad.append("panel leaves safe area %s" % rp)
	for b in [tp.btn_res_retry, tp.btn_res_back]:
		var pb: PillButton = b
		if not rp.encloses(pb.get_global_rect()):
			bad.append("'%s' outside the panel" % pb.text)
		if not pb.content_fits():
			bad.append("'%s' does not fit" % pb.text)
		if pb.size.y < MIN_TAP:
			bad.append("'%s' only %.0f px tall" % [pb.text, pb.size.y])
	var lb: Label = tp.results_body
	var lh: float = 18.0 * 1.25
	if float(lb.get_line_count()) * lh > lb.size.y + 2.0:
		bad.append("body text wraps to %d lines (%.0f px) in %.0f px" % [lb.get_line_count(), float(lb.get_line_count()) * lh, lb.size.y])
	var tl: Label = tp.results_title
	if float(tl.get_line_count()) * 38.0 > tl.size.y + 2.0:
		bad.append("title wraps to %d lines" % tl.get_line_count())
	# the panel must not hide the hint/retry buttons the player may need? (it only covers the board)
	check(bad.is_empty(), "trial panel[%s @%d]%s" % [label, W(), "" if bad.is_empty() else " -> " + "; ".join(bad)])

func scenario_rv_trial_wrap() -> void:
	established()
	await play_trial("wrap")

func scenario_rv_trial_chain() -> void:
	established()
	await play_trial("chain")

func scenario_rv_trial_space() -> void:
	established()
	await play_trial("space")

# --- 7. calm pool ------------------------------------------------------------------------------------------------------

func scenario_rv_calm() -> void:
	established()
	main.hub.refresh("start")
	await click_btn(main.hub.tab_buttons[3])
	await click(main.hub.modes_list.row_center_global("calm"))
	var cp: PoolScreen = main.calm_screen
	check(main.current == "calm", "calm pool opens")
	await frames(6)
	await rshot("07a_calm_start")
	audit("calm start")
	prompt_fits(cp, "calm start")
	var cb: Board = cp.session.run.board
	var moved: bool = false
	for i in cb.cells.size():
		if cb.code_at(i) == 0 or moved:
			continue
		var tg: Dictionary = cp.session.valid_targets(i)
		if (tg["move"] as PackedInt32Array).size() > 0:
			await _drag_in(cp, i, int((tg["move"] as PackedInt32Array)[0]))
			moved = true
	await click_btn(cp.btn_retry)
	await frames(4)
	await rshot("07b_calm_new_board")
	audit("calm new board")
	cp.toast.show_text("The pool filled up, so Calm Pool made a fresh board. No harm done.", 6.0)
	await frames(4)
	await rshot("07c_calm_reset_toast")
	audit_toast(cp, "calm reset")
	await click_btn(cp.btn_hint)
	await frames(4)
	await rshot("07d_calm_hint")
	audit("calm hint")
	prompt_fits(cp, "calm hint")

# --- 8. help-replay sandbox (also in guided_misc); finish screen ----------------------------------------------------

func scenario_rv_help_done() -> void:
	main.show_screen("help")
	await frames(8)
	var hp: PoolScreen = main.help_screen
	await rshot("08a_help_practice_start")
	audit("help start")
	prompt_fits(hp, "help start")
	await drag(hp.board_view.cell_center_global(i_(4, 1)), hp.board_view.cell_center_global(i_(4, 2)))
	await idle()
	await click_btn(hp.btn_current)
	await click(hp.board_view.get_global_transform() * Vector2(BoardView.TAB * 0.5, BoardView.TAB + 1.5 * hp.board_view.cs))
	await click_btn(hp.btn_dir_a)
	await click_btn(hp.btn_confirm)
	await click(hp.board_view.cell_center_global(i_(1, 4)))
	await click(hp.board_view.cell_center_global(i_(2, 4)))
	await get_tree().create_timer(2.2).timeout
	await idle()
	var rc: int = -1
	for i in hp.session.run.board.cells.size():
		if Creature.tier_of(hp.session.run.board.code_at(i)) >= 4:
			rc = i
	await drag(hp.board_view.cell_center_global(rc), hp.gate.get_global_rect().get_center())
	await idle()
	await frames(6)
	await rshot("08b_help_done_panel")
	check_trial_panel(hp, "help done")

# --- 9. night palette ------------------------------------------------------------------------------------------------------

func scenario_rv_night() -> void:
	var se: GameSession = established()
	await click_btn(main.hub.btn_play)
	var sc: PoolScreen = pool()
	await frames(10)
	await rshot("09a_night_pool")
	audit("night pool")
	load_board(rows_board(["S1 F1 S2 F2 S3 F3", "F4 S5 . . S6 F6", ". . . . . .", "S1 . S2 . F3 ."]), 5, 12)
	await click_btn(sc.btn_hint)
	await frames(4)
	await rshot("09b_night_hint")
	await click_btn(sc.btn_current)
	await click(tab_pos(Board.AXIS_ROW, 1))
	await click_btn(sc.btn_dir_b)
	await frames(4)
	await rshot("09c_night_preview")
	sc._exit_current_mode()
	load_board(rows_board(["S1 F1 S2 . . .", ". . . . . ."]), 2, 2)
	var res: Dictionary = se.try_drop(i_(0, 2), i_(0, 3))
	sc._play_result(res)
	await get_tree().create_timer(0.8).timeout
	await rshot("09d_night_surge")
	await idle()
	sc.toast.show_kind("Only identical creatures merge", "invalid", 6.0)
	await frames(4)
	await rshot("09e_night_toast")
	await click_btn(sc.btn_home)
	await frames(8)
	await rshot("09f_night_hub")
	audit("night hub")
	main.show_screen("summary")
	await frames(6)
	await rshot("09g_night_summary")

# --- 10. more states: Book, long names, huge numbers, hub Help with banners up, the swell ---------------------

func scenario_rv_book() -> void:
	var se: GameSession = established(12345)
	GameClock.set_tz_bias_seconds(0)
	GameClock.freeze(at(12, 0))
	for code in [11, 12, 13, 14, 15, 16, 21, 22, 23, 24, 25]:
		Book.note_made(se.profile, code)
	Book.note_released(se.profile, 14)
	Book.note_released(se.profile, 25)
	se.profile.residents = [{"id": 1, "code": 14, "family": 1, "tier": 4, "run": 1}, {"id": 2, "code": 25, "family": 2, "tier": 5, "run": 1}]
	main.hub.refresh("start")
	await frames(6)
	var h: ReefHub = main.hub
	await click_btn(h.tab_buttons[4])
	var bv: Control = h.book_view
	await rshot("03o_book_discovered")
	audit("book discovered")
	# select the long-named entries
	var rects: Dictionary = bv.call("tile_rects")
	print("[review] book tiles visible: ", rects.keys())
	if rects.has(25):
		bv.call("tap", (rects[25] as Rect2).get_center() - bv.get_global_rect().position)
		await frames(4)
		await rshot("03p_book_sunflower_starfish")
	# an undiscovered tile shows the toast
	rects = bv.call("tile_rects")
	for k in rects:
		if int(k) == 26 or int(k) == 16:
			bv.call("tap", (rects[k] as Rect2).get_center() - bv.get_global_rect().position)
	await frames(4)
	await rshot("03q_book_hidden_toast")
	var small: int = 0
	for k in bv.call("tile_rects"):
		var r: Rect2 = (bv.call("tile_rects") as Dictionary)[k]
		if r.size.x < 43.5 or r.size.y < 43.5:
			small += 1
	check(small == 0, "every Book tile >= 44 logical px (%d visible)" % bv.call("tile_rects").size())
	check_hub_layout("book discovered")
	GameClock.reset()

## Arrival card with the longest creature names, and the huge-number chips of a pool.
func scenario_rv_arrival_long() -> void:
	var se: GameSession = established(123456789012)
	se.profile.pearls = 98765432101
	main.hub.refresh("start")
	await click_btn(main.hub.btn_play)
	var sc: PoolScreen = pool()
	se.run.turn = 1234567
	se.run.currents = 99999
	sc._refresh_all()
	await frames(4)
	audit("pool huge numbers")
	await rshot("04o_pool_huge_numbers")
	for code in [Creature.make(2, 5), Creature.make(1, 4), Creature.make(3, 4)]:
		sc.arrival.open(code, 1234.5, "You can afford a Coral Fan (120 coins). Visit the reef to place it.", false)
		await frames(8)
		await rshot("02n_arrival_%d" % code)
		var ar: Rect2 = sc.arrival.get_global_rect()
		check(safe_rect().encloses(ar) and ar.encloses(sc.arrival.btn_visit.get_global_rect()) and ar.encloses(sc.arrival.btn_keep.get_global_rect()), "arrival card for %s inside safe area (font %d, %d lines)" % [Creature.full_name(code), sc.arrival._fs, sc.arrival._lines.size()])
		audit("arrival " + str(code), sc.arrival)
		sc.arrival.visible = false

## Hub help sheet with chest + visitor banners (tight vertical space), and a decor toast.
func scenario_rv_hub_help_tight() -> void:
	var se: GameSession = established(12345)
	setup_established_hub(true)
	GameClock.freeze(at(6, 30))
	main.show_screen("start")
	await frames(10)
	var h: ReefHub = main.hub
	await click_btn(h.btn_help)
	await frames(4)
	await rshot("03r_hub_help_tight")
	var hs: Rect2 = h.help_sheet.get_global_rect()
	check(safe_rect().grow(0.5).encloses(hs) and hs.encloses(h.help_sheet.btn_replay.get_global_rect()) and hs.encloses(h.help_sheet.btn_close.get_global_rect()), "hub help sheet and buttons inside the safe area %s" % hs)
	audit("hub help tight", h.help_sheet)
	await click_btn(h.help_sheet.btn_close)
	check(not h.help_sheet.visible, "Close is reachable and closes the hub help sheet with the banners up")
	await click_btn(h.tab_buttons[1])
	h._select_decor(0)
	await frames(3)
	h._select_decor(0)
	await frames(2)
	await rshot("03s_decor_toast_owned")
	audit("decor toast")
	var tr: Rect2 = h.toast.get_global_rect()
	check(safe_rect().grow(0.5).encloses(tr) and not tr.intersects(h.reef.get_global_rect()), "hub toast %s inside safe area and off the aquarium" % tr)
	GameClock.reset()

## The swell: a late Surge brings 4-6 creatures. Strip, board marks and flood notice must still fit.
func scenario_rv_swell() -> void:
	var se: GameSession = established()
	main.hub.refresh("start")
	await click_btn(main.hub.btn_play)
	var sc: PoolScreen = pool()
	load_board(rows_board(["S1 F1 S2 . . .", ". . . . . ."]), 2, 2)
	se.run.turn = GameConfig.SWELL_START + 2 * GameConfig.SWELL_EVERY + 2
	sc._refresh_all()
	await frames(3)
	check(se.run.surge_size_now() == 6, "the Surge is at its largest (%d)" % se.run.surge_size_now())
	await rshot("04p_swell_next_surge")
	audit("swell next surge")
	var items: Array = []
	var empties: Array = []
	for i in se.run.board.cells.size():
		if se.run.board.code_at(i) == 0:
			empties.append(i)
	for k in 6:
		items.append({"cell": int(empties[k * 5]), "code": Creature.make(1 + (k % 2), 1 + (k % 3))})
	se.run.pending_surge = items
	sc._run_surge_sequence()
	await get_tree().create_timer(0.8).timeout
	await rshot("04q_swell_surge_preview")
	audit("swell surge preview")
	prompt_fits(sc, "swell surge")
	# the strip's slots must not run into its own text
	var strip: HudWidgets.SurgeStrip = sc.surge_strip
	var font: Font = ThemeDB.fallback_font
	var tx: float = 16.0 + float(strip.cadence) * 26.0 + 6.0
	var text_end: float = tx + font.get_string_size("incoming", HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 6.0
	var slot: float = minf(strip.size.y - 8.0, 44.0)
	var gx: float = strip.size.x - 10.0 - 6.0 * (slot + 6.0)
	check(gx >= text_end, "six incoming slots start at x=%.0f, after the strip text ends at %.0f" % [gx, text_end])
	await idle()
	strip.danger = true
	strip.message = "Only 5 free cells; the wave needs 6"
	strip.refresh()
	sc.prompt_label.text = "The wave cannot fit! The pool floods. Your rewards are safe."
	await frames(3)
	await rshot("04r_swell_flood_notice")
	var need: float = font.get_string_size(strip.message, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	check(tx + need <= strip.size.x - 8.0, "flood message fits the strip (%.0f of %.0f)" % [tx + need, strip.size.x - 8.0])
	strip.danger = false

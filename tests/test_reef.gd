extends SceneTree
## Update 2 economy tests (clock, passive income, chest, decorations, migration).
##   godot --headless --path . --script res://tests/test_reef.gd

var passed: int = 0
var failed: int = 0
const T0: int = 1795000000          # arbitrary fixed unix time
const PATH: String = "user://test_reef.json"

func _initialize() -> void:
	GameClock.set_tz_bias_seconds(0)
	_run_all()
	GameClock.reset()
	print("\n==== reef: %d passed, %d failed ====" % [passed, failed])
	quit(1 if failed > 0 else 0)

func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("  ok   - ", msg)
	else:
		failed += 1
		print("  FAIL - ", msg)

func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _profile_with(tiers: Array) -> Profile:
	var p := Profile.new()
	for i in tiers.size():
		p.residents.append({"id": i + 1, "code": Creature.make(1, int(tiers[i])), "family": 1, "tier": int(tiers[i]), "run": 1})
	p.next_resident_id = tiers.size() + 1
	return p

func _session(tiers: Array) -> GameSession:
	_rm(PATH)
	var s := GameSession.new()
	s.save_path = PATH
	s.profile = _profile_with(tiers)
	s.profile.income_stamp = GameClock.now()
	s.start_run(Board.from_text(["S1 . . . . ."]))
	var done: Dictionary = {}
	for g in GameConfig.DAILY_GOALS:
		done[String(g["id"])] = true
	s.profile.daily = {"day": GameClock.local_day_key(), "progress": {}, "done": done}   # goals have their own tests
	s.profile.runs_started = 5
	return s

func _run_all() -> void:
	GameClock.freeze(T0)
	t_rates()
	t_fraction_carry()
	t_old_rate_before_release()
	t_chest_and_cap()
	t_negative_clock()
	t_claim_and_reload()
	t_purchase()
	t_first_item_affordable()
	t_migration()
	t_unseen()
	t_preview_steps()

func t_rates() -> void:
	print("[rates]")
	check(is_equal_approx(ReefEconomy.resident_rate(1), 5.0), "tier 1 = 5 coins/h")
	check(is_equal_approx(ReefEconomy.resident_rate(2), 9.0), "tier 2 = 5 x 1.8 = 9")
	check(is_equal_approx(ReefEconomy.resident_rate(4), 5.0 * 1.8 * 1.8 * 1.8), "tier 4 = 5 x 1.8^3 = 29.16")
	check(absf(ReefEconomy.resident_rate(6) - 94.4784) < 0.001, "tier 6 = 94.4784")
	var p: Profile = _profile_with([4, 5])
	var base: float = 29.16 + 52.488
	check(absf(ReefEconomy.rate_per_hour(p) - base) < 0.001, "no decorations -> multiplier 1.0")
	p.decorations = [{"id": "coral_fan", "slot": 0}, {"id": "sea_lantern", "slot": 1}]
	check(ReefEconomy.total_beauty(p) == 11, "Beauty adds up (3 + 8)")
	check(absf(ReefEconomy.rate_per_hour(p) - base * 1.11) < 0.001, "reef multiplier = 1 + Beauty/100")

func t_fraction_carry() -> void:
	print("[fractional accrual]")
	var s := _session([4])           # 29.16 coins/h
	GameClock.freeze(T0)
	s.profile.income_stamp = T0
	for i in 60:                      # one hour in 60-second live ticks
		GameClock.advance(60)
		s.settle_income()
	check(s.profile.coins == 29, "one hour of live ticks pays 29 whole coins")
	check(absf(s.profile.income_frac - 0.16) < 0.001, "the .16 left over is carried, not lost (%.4f)" % s.profile.income_frac)
	for i in 60:
		GameClock.advance(60)
		s.settle_income()
	check(s.profile.coins == 58 and absf(s.profile.income_frac - 0.32) < 0.001, "two hours: 58 coins + .32 carried")

func t_old_rate_before_release() -> void:
	print("[settle at the old rate before a rate change]")
	var s := _session([4])
	GameClock.freeze(T0)
	s.profile.income_stamp = T0
	s.profile.coins = 0
	s.profile.income_frac = 0.0
	GameClock.advance(80)             # 80 s live gap, NOT yet settled
	s.run.board.set_code(0, Creature.make(1, 6))
	var rate_before: float = ReefEconomy.rate_per_hour(s.profile)
	var res: Dictionary = s.try_release(0)
	var expected: float = rate_before * 80.0 / 3600.0
	check(res["ok"], "release ok")
	check(absf(float(s.profile.coins) + s.profile.income_frac - expected) < 0.0001, "80 s were paid at the OLD rate (%.4f vs %.4f)" % [float(s.profile.coins) + s.profile.income_frac, expected])
	check(ReefEconomy.rate_per_hour(s.profile) > rate_before, "the new resident raises the rate afterwards")
	GameClock.advance(60)
	var before_total: float = float(s.profile.coins) + s.profile.income_frac
	s.settle_income()
	var gained: float = float(s.profile.coins) + s.profile.income_frac - before_total
	check(absf(gained - ReefEconomy.rate_per_hour(s.profile) * 60.0 / 3600.0) < 0.0001, "later time earns at the NEW rate")

func t_chest_and_cap() -> void:
	print("[offline chest + 8h cap]")
	var s := _session([4, 4])        # 58.32 /h
	GameClock.freeze(T0)
	s.profile.income_stamp = T0
	s.profile.coins = 10
	s.save()
	var rate: float = ReefEconomy.rate_per_hour(s.profile)
	GameClock.advance(3 * 3600)
	var r: Dictionary = s.settle_income()
	check(r["away"] and s.profile.coins == 10, "3 h away goes to the chest, balance untouched")
	check(absf(s.profile.chest_coins - rate * 3.0) < 0.001, "chest holds 3 h of income (%.2f)" % s.profile.chest_coins)
	check(ReefEconomy.chest_amount(s.profile) == int(floor(rate * 3.0)), "displayed chest amount")
	# 20 more hours away -> cap at 8 h total
	GameClock.advance(20 * 3600)
	s.settle_income()
	check(s.profile.chest_secs == 8 * 3600 and absf(s.profile.chest_coins - rate * 8.0) < 0.001, "capped at exactly 8 h of income (%.2f)" % s.profile.chest_coins)
	check(ReefEconomy.chest_full(s.profile), "chest reports full")
	# relaunch repeatedly without claiming: must not stack
	for i in 4:
		s.save()
		GameClock.advance(30 * 3600)
		var s2 := GameSession.new()
		s2.save_path = PATH
		s2.load_or_new()
		s = s2
	check(absf(s.profile.chest_coins - rate * 8.0) < 0.001 and s.profile.chest_secs == 8 * 3600, "four more long relaunches do not stack full chests")
	# claim, then a new absence can fill it again
	var paid: int = s.claim_chest()
	check(paid == int(floor(rate * 8.0)), "claim pays the 8 h chest (%d)" % paid)
	check(s.profile.chest_coins == 0.0 and s.profile.chest_secs == 0, "chest cleared")
	check(s.claim_chest() == 0, "claiming again pays nothing")
	GameClock.advance(2 * 3600)
	s.settle_income()
	check(absf(s.profile.chest_coins - rate * 2.0) < 0.001, "a new absence starts a fresh chest")

func t_negative_clock() -> void:
	print("[negative elapsed time]")
	var s := _session([4])
	GameClock.freeze(T0)
	s.profile.income_stamp = T0
	s.profile.coins = 5
	GameClock.advance(-7200)         # clock set back two hours
	var r: Dictionary = s.settle_income()
	check(r["clamped"] and s.profile.coins == 5 and s.profile.chest_coins == 0.0, "negative gap earns nothing and creates no chest")
	check(s.profile.income_stamp == GameClock.now(), "income re-anchors to the new clock")
	GameClock.advance(60)
	s.settle_income()
	check(s.profile.income_frac > 0.0, "income resumes normally afterwards")

func t_claim_and_reload() -> void:
	print("[claim is atomic; pending chest survives reload]")
	var s := _session([5])
	GameClock.freeze(T0)
	s.profile.income_stamp = T0
	s.profile.coins = 100
	s.save()
	GameClock.advance(5 * 3600)
	var s2 := GameSession.new()
	s2.save_path = PATH
	s2.load_or_new()                 # launch after 5 h away -> chest
	var pending: float = s2.profile.chest_coins
	check(pending > 0.0 and s2.profile.coins == 100, "chest pending after relaunch")
	s2.save()
	var s3 := GameSession.new()
	s3.save_path = PATH
	s3.load_or_new()                 # reload again, no time passes
	check(absf(s3.profile.chest_coins - pending) < 0.0001, "pending chest preserved through another reload")
	var paid: int = s3.claim_chest()
	var s4 := GameSession.new()
	s4.save_path = PATH
	s4.load_or_new()
	check(s4.profile.coins == 100 + paid and s4.profile.chest_coins == 0.0 and s4.profile.chest_secs == 0, "balance and cleared chest were saved together (%d paid)" % paid)
	check(s4.claim_chest() == 0 and s4.profile.coins == 100 + paid, "reloading and claiming again does not double-pay")

func t_purchase() -> void:
	print("[decorations]")
	var s := _session([4])
	GameClock.freeze(T0)
	s.profile.income_stamp = T0
	s.profile.coins = 500
	var rate0: float = s.income_rate()
	var coral: Dictionary = ReefEconomy.decoration_def("coral_fan")
	var r1: Dictionary = s.purchase_decoration("coral_fan", 2)
	check(r1["ok"] and s.profile.coins == 500 - int(coral["price"]), "buying charges the price once")
	check(s.profile.decorations.size() == 1 and s.profile.decorations[0]["slot"] == 2, "placed on the chosen spot")
	check(s.income_rate() > rate0 and absf(s.income_rate() - rate0 * 1.03) < 0.0001, "Beauty 3 -> x1.03 income")
	var r2: Dictionary = s.purchase_decoration("coral_fan", 3)
	check(not r2["ok"] and s.profile.coins == 500 - int(coral["price"]) and s.profile.decorations.size() == 1, "retrying the same purchase charges nothing and adds nothing")
	var r3: Dictionary = s.purchase_decoration("bubble_column", 2)
	check(not r3["ok"] and s.profile.decorations.size() == 1, "a taken spot is refused")
	var r4: Dictionary = s.purchase_decoration("sunken_statue", 4)
	check(not r4["ok"] and s.profile.coins == 500 - int(coral["price"]), "too expensive: refused, no charge")
	check(not s.purchase_decoration("nope", 1)["ok"] and not s.purchase_decoration("bubble_column", 99)["ok"], "unknown item / bad spot refused")
	# reopen the game: still exactly one
	var s2 := GameSession.new()
	s2.save_path = PATH
	s2.load_or_new()
	check(s2.profile.decorations.size() == 1 and s2.profile.coins == 500 - int(coral["price"]), "after reload: one item, charged once")
	check(not s2.purchase_decoration("coral_fan", 5)["ok"] and s2.profile.coins == 500 - int(coral["price"]), "retry after reload is still a no-op")
	# purchase settles at the old rate first
	var s3 := _session([4])
	GameClock.freeze(T0)
	s3.profile.income_stamp = T0
	s3.profile.coins = 1000
	GameClock.advance(60)
	var rate_old: float = s3.income_rate()
	s3.purchase_decoration("coral_fan", 0)
	var earned: float = float(s3.profile.coins) + s3.profile.income_frac - (1000.0 - 120.0)
	check(absf(earned - rate_old * 60.0 / 3600.0) < 0.0001, "60 s before the purchase were paid at the old rate")
	# preview helpers
	var gain: float = ReefEconomy.rate_with_decoration(s3.profile, "bubble_column") - s3.income_rate()
	check(gain > 0.0, "income change is computable before buying (+%.2f/h)" % gain)
	# prices escalate, Beauty modest
	var last: int = 0
	var esc: bool = true
	var modest: bool = true
	for d in GameConfig.DECORATIONS:
		esc = esc and int(d["price"]) > last
		last = int(d["price"])
		modest = modest and int(d["beauty"]) <= 20
	check(esc and modest and GameConfig.DECORATIONS.size() == 5 and GameConfig.DECOR_SLOTS.size() >= 5, "five decorations, escalating prices, modest Beauty, enough marked spots")

func t_first_item_affordable() -> void:
	print("[first decoration is affordable early]")
	var s := GameSession.new()
	s.autosave = false
	s.start_run()
	s.try_pair(Board.idx(4, 1), Board.idx(4, 2))                       # opening merge + chain
	s.try_current(Board.AXIS_ROW, 1, -1)                              # wrapped Current -> tier 4
	s.try_pair(Board.idx(4, 2), Board.idx(6, 4))                      # S3 + S3 -> S4
	var cheapest: int = int(GameConfig.DECORATIONS[0]["price"])
	check(s.profile.coins >= cheapest, "after the first-run prompts (3 turns) coins %d >= first decoration %d" % [s.profile.coins, cheapest])

func t_migration() -> void:
	print("[Update 1 save -> Update 2]")
	for name in ["midrun", "flooded"]:
		var src: String = "res://tests/fixtures/save_v1_%s.json" % name
		var dst: String = "user://test_mig_%s.json" % name
		_rm(dst)
		DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst))
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(src))
		GameClock.freeze(T0)
		var s := GameSession.new()
		s.save_path = dst
		s.load_or_new()
		var rr: Dictionary = raw["run"]
		check(int(raw["version"]) == 1, "[%s] fixture really is version 1" % name)
		check(s.profile.coins == int(raw["profile"]["coins"]) and s.profile.pearls == int(raw["profile"]["pearls"]), "[%s] balances survive (%d coins, %d pearls)" % [name, s.profile.coins, s.profile.pearls])
		check(s.profile.residents.size() == raw["profile"]["residents"].size() and s.profile.residents.size() > 0, "[%s] all %d residents survive" % [name, s.profile.residents.size()])
		var same_res: bool = true
		for i in s.profile.residents.size():
			same_res = same_res and int(s.profile.residents[i]["id"]) == int(raw["profile"]["residents"][i]["id"]) and int(s.profile.residents[i]["code"]) == int(raw["profile"]["residents"][i]["code"])
		check(same_res, "[%s] resident ids and creatures identical" % name)
		check(s.run != null and s.run.turn == int(rr["turn"]) and s.run.currents == int(rr["currents"]) and s.run.status == int(rr["status"]), "[%s] active run: turn %d, Currents %d" % [name, s.run.turn, s.run.currents])
		check(str(s.run.board.to_array()) == str(rr["board"]), "[%s] board identical" % name)
		check(s.run.rng.state == int(rr["rng_state"]) and s.run.seed_value == int(rr["seed"]), "[%s] random state preserved" % name)
		check(s.profile.runs_started == int(raw["profile"]["runs_started"]), "[%s] run counters preserved" % name)
		check(s.profile.decorations.is_empty() and s.profile.chest_coins == 0.0 and s.profile.income_stamp == T0, "[%s] new reef fields default sanely; income clock starts at upgrade" % name)
		s.save()
		var up: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dst))
		check(int(up["version"]) == GameConfig.SAVE_VERSION, "[%s] re-saved in the new format (v%d)" % [name, int(up["version"])])
		var s2 := GameSession.new()
		s2.save_path = dst
		s2.load_or_new()
		check(s2.profile.residents.size() == s.profile.residents.size() and str(s2.run.board.to_array()) == str(rr["board"]), "[%s] reload of the migrated save is stable" % name)
		_rm(dst)
	check(FileAccess.file_exists("res://tests/fixtures/save_v1_midrun.json"), "original fixture left untouched")
	# a save from the future / garbage is quarantined, not crashed on
	var bad: String = "user://test_mig_bad.json"
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("{\"version\": 99, \"profile\": {}}")
	f.close()
	var s3 := GameSession.new()
	s3.save_path = bad
	s3.load_or_new()
	check(s3.run == null and s3.profile.residents.is_empty(), "unknown future version starts fresh instead of crashing")
	_rm(bad)
	_rm(bad + ".corrupt")

func t_unseen() -> void:
	print("[newest resident highlight]")
	var s := _session([])
	s.run.board.set_code(0, Creature.make(2, 4))
	s.run.board.set_code(1, Creature.make(1, 5))
	s.try_release(0)
	s.try_release(1)
	check(s.profile.unseen_residents == [1, 2], "two releases -> two unseen residents")
	var s2 := GameSession.new()
	s2.save_path = PATH
	s2.load_or_new()
	check(s2.profile.unseen_residents == [1, 2], "unseen list persists")
	s2.acknowledge_residents()
	var s3 := GameSession.new()
	s3.save_path = PATH
	s3.load_or_new()
	check(s3.profile.unseen_residents.is_empty(), "acknowledging clears it (saved)")

func t_preview_steps() -> void:
	print("[Current preview exposes the line it would make]")
	var s := _session([])
	s.run.board = Board.from_text([". . . . . .", "F2 . . . F2 F2"])
	var pv: Dictionary = s.preview_current(Board.AXIS_ROW, 1, -1)
	check(pv["changes"] and pv["steps"].size() == 1, "one merge step reported")
	var st: Dictionary = pv["steps"][0]
	var srcs: PackedInt32Array = st["sources"]
	check(st["kind"] == "line" and srcs.has(Board.idx(1, 3)) and srcs.has(Board.idx(1, 5)) and int(st["result_cell"]) == Board.idx(1, 4), "line sources and result cell are the post-shift cells")

extends SceneTree
## Balance simulation: a greedy bot (the same priorities as the Hint: release, chain, line, merge,
## Current, then slide / advance the tide) plays many reproducible standard runs headlessly.
##   godot --headless --path . --script res://dev/tune_sim.gd -- --n=60 --cadence=3 --size=3 --w2=1 --w3=1 --cap=400 --label=baseline
## Prints run length, flood rate, floods before turn 15, empty cells at each Surge, stuck/tide
## advances, releases and the turn of the first release. Rules come from the run's own fields, so
## the same code path (cadence / surge size / spawn table per run) as the real game is used.

func _arg(name: String, dflt: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return dflt

func _initialize() -> void:
	GameClock.set_tz_bias_seconds(0)
	GameClock.freeze(1795000000 + 12 * 3600)
	var n: int = int(_arg("n", "60"))
	var cadence: int = int(_arg("cadence", str(GameConfig.SURGE_CADENCE)))
	var size: int = int(_arg("size", str(GameConfig.SURGE_SIZE)))
	var w2: float = float(_arg("w2", "1"))
	var w3: float = float(_arg("w3", "1"))
	var cap: int = int(_arg("cap", "400"))
	var label: String = _arg("label", "run")
	var skill: float = float(_arg("skill", "1"))          # chance a turn follows the Hint, else a casual random legal action
	var rel_p: float = float(_arg("relp", "1"))           # chance a tier 4+ is released when the bot sees one
	var rng := RandomNumberGenerator.new()
	var turns: Array = []
	var floods: int = 0
	var early_floods: int = 0
	var capped: int = 0
	var empties: Array = []
	var empties_first: Array = []
	var tides: int = 0
	var releases: Array = []
	var first_rel: Array = []
	var merges: Array = []
	var stuck_runs: int = 0
	for k in n:
		var s := GameSession.new()
		s.autosave = false
		s.profile.tutorial = {"done": true, "skipped": true, "milestone": true, "restarts": 0}
		s.base_seed = 1000 + k * 37
		s.start_run()
		var run: RunState = s.run
		run.cadence = cadence
		run.surge_size = size
		var sw: PackedStringArray = _arg("swell", "%d,%d,%d" % [GameConfig.SWELL_START, GameConfig.SWELL_EVERY, GameConfig.SWELL_MAX]).split(",")
		run.swell_start = int(sw[0])
		run.swell_every = int(sw[1])
		run.swell_max = int(sw[2])
		var table: Array = []
		for e in run.spawn_table:
			var w: float = float(e[2])
			if int(e[1]) == 2:
				w *= w2
			elif int(e[1]) == 3:
				w *= w3
			table.append([int(e[0]), int(e[1]), int(round(w))])
		run.spawn_table = table
		var first_release_turn: int = -1
		var run_tides: int = 0
		var surge_no: int = 0
		var guard: int = 0
		while run.status == RunState.ACTIVE and run.turn < cap and guard < cap * 6:
			guard += 1
			rng.seed = 777 + k * 131 + guard
			var h: Dictionary = Hints.suggest(s)
			if String(h["kind"]) == "release" and rng.randf() > rel_p:
				h = _casual(s, rng)
			elif String(h["kind"]) != "release" and rng.randf() > skill:
				h = _casual(s, rng)
			var res: Dictionary = {}
			match String(h["kind"]):
				"release":
					res = s.try_release(int(h["src"]))
					if bool(res["ok"]) and first_release_turn < 0:
						first_release_turn = run.turn
				"chain", "merge", "line":
					res = s.try_pair(int(h["src"]), int(h["dst"]))
				"current":
					var c: Dictionary = h["current"]
					res = s.try_current(int(c["axis"]), int(c["index"]), int(c["dir"]))
				"slide":
					res = s.try_move(int(h["src"]), int(h["dst"]))
				"tide":
					res = s.advance_tide()
					run_tides += 1
				_:
					res = {}
			if res.is_empty() or not bool(res.get("ok", false)):
				# nothing legal: count as a stall and end the run
				stuck_runs += 1
				break
			if not (res.get("surge", []) as Array).is_empty() or bool(res.get("flood", false)):
				surge_no += 1
				var free: int = run.board.empty_cells().size()
				empties.append(free)
				if surge_no == 1:
					empties_first.append(free)
			if not run.pending_surge.is_empty():
				s.land_surge()
		turns.append(run.turn)
		merges.append(int(run.stats["merges"]))
		releases.append(int(run.stats["releases"]))
		if first_release_turn >= 0:
			first_rel.append(first_release_turn)
		tides += run_tides
		if run.status == RunState.FLOODED:
			floods += 1
			if run.turn < 15:
				early_floods += 1
		elif run.turn >= cap:
			capped += 1
	GameClock.reset()
	print("[sim] %-14s n=%d cadence=%d size=%d w2=%.2f w3=%.2f | turns avg %.1f med %d min %d max %d | flooded %d/%d (before turn 15: %d) capped %d stalls %d tide-advances %d" % [
		label, n, cadence, size, w2, w3, _avg(turns), _med(turns), turns.min(), turns.max(), floods, n, early_floods, capped, stuck_runs, tides])
	print("[sim] %-14s empty cells at a Surge: avg %.1f (first Surge avg %.1f, min %d) | merges avg %.1f | releases avg %.1f | first release turn avg %.1f" % [
		label, _avg(empties), _avg(empties_first), (empties.min() if not empties.is_empty() else 0), _avg(merges), _avg(releases), _avg(first_rel)])
	quit(0)

func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t: float = 0.0
	for v in a:
		t += float(v)
	return t / float(a.size())

func _med(a: Array) -> int:
	var b: Array = a.duplicate()
	b.sort()
	return int(b[b.size() / 2]) if not b.is_empty() else 0

## A casual player's move: a random legal merge, slide or Current (never a release).
func _casual(s: GameSession, rng: RandomNumberGenerator) -> Dictionary:
	var b: Board = s.run.board
	var pairs: Array = []
	var slides: Array = []
	for i in b.cells.size():
		var c: int = b.code_at(i)
		if c == 0:
			continue
		for j in b.cells.size():
			if i != j and MergeRules.can_pair(b, i, j):
				pairs.append([i, j])
		for nb in b.neighbors(i):
			if nb >= 0 and b.code_at(nb) == 0:
				slides.append([i, nb])
	var roll: float = rng.randf()
	if roll < 0.45 and not pairs.is_empty():
		var p: Array = pairs[rng.randi() % pairs.size()]
		return {"kind": "merge", "src": p[0], "dst": p[1]}
	if roll < 0.9 and not slides.is_empty():
		var m: Array = slides[rng.randi() % slides.size()]
		return {"kind": "slide", "src": m[0], "dst": m[1]}
	if s.run.currents > 0:
		var axis: int = rng.randi() % 2
		var idx: int = rng.randi() % (GameConfig.ROWS if axis == 0 else GameConfig.COLS)
		return {"kind": "current", "current": {"axis": axis, "index": idx, "dir": -1 if rng.randf() < 0.5 else 1}}
	return Hints.suggest(s)

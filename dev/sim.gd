extends SceneTree
## Headless balance probe (core rules only, no UI):
##   godot --headless --path . --script res://dev/sim.gd
## Plays many seeded runs with simple policies and reports how long they last.

func _initialize() -> void:
	for policy in ["random", "casual60", "casual40", "casual25", "casual10", "greedy"]:
		var lens: Array = []
		var floods: int = 0
		var chains: int = 0
		for seed_v in range(1, 41):
			var r: Dictionary = _play(policy, seed_v)
			lens.append(r["turns"])
			if r["flood"]:
				floods += 1
			chains += int(r["chains"])
		lens.sort()
		print("%-9s runs=40 flooded=%d  turns min=%d median=%d max=%d  chains/run=%.1f" % [policy, floods, lens[0], lens[lens.size() / 2], lens[lens.size() - 1], float(chains) / 40.0])
	quit()

func _play(policy: String, seed_v: int) -> Dictionary:
	var s := GameSession.new()
	s.autosave = false
	s.base_seed = seed_v
	s.profile.runs_started = 1   # skip the tutorial layout: random start
	s.start_run()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 31
	var guard: int = 0
	while s.run.status == RunState.ACTIVE and guard < 400:
		guard += 1
		if not s.run.pending_surge.is_empty():
			s.land_surge()
			continue
		_take_turn(s, policy, rng)
	return {"turns": s.run.turn, "flood": s.run.status == RunState.FLOODED, "chains": s.run.stats["chains"]}

func _pairs(s: GameSession) -> Array:
	var out: Array = []
	var b: Board = s.run.board
	for i in b.cells.size():
		for j in range(i + 1, b.cells.size()):
			if MergeRules.can_pair(b, i, j):
				out.append([i, j])
	return out

func _slides(s: GameSession) -> Array:
	var out: Array = []
	var b: Board = s.run.board
	for i in b.cells.size():
		if b.code_at(i) == 0:
			continue
		for n in b.neighbors(i):
			if n >= 0 and b.code_at(n) == 0:
				out.append([i, n])
	return out

func _take_turn(s: GameSession, policy: String, rng: RandomNumberGenerator) -> void:
	var b: Board = s.run.board
	# always release tier 4+ (free)
	for i in b.cells.size():
		if b.code_at(i) != 0 and Creature.tier_of(b.code_at(i)) >= GameConfig.RELEASE_MIN_TIER:
			s.try_release(i)
	var pairs: Array = _pairs(s)
	var slides: Array = _slides(s)
	var p_merge: float = {"random": 0.0, "casual60": 0.6, "casual40": 0.4, "casual25": 0.25, "casual10": 0.10, "casual85": 0.85, "greedy": 1.0}[policy]
	if policy == "random":
		var all: Array = pairs + slides
		if all.is_empty():
			s.force_stuck_for_testing = true
			s.advance_tide()
			s.force_stuck_for_testing = false
			return
		var m: Array = all[rng.randi() % all.size()]
		s.try_drop(m[0], m[1])
		return
	if not pairs.is_empty() and rng.randf() < p_merge:
		# prefer the highest tier pair
		pairs.sort_custom(func(x: Array, y: Array) -> bool: return b.code_at(x[0]) > b.code_at(y[0]))
		s.try_pair(pairs[0][0], pairs[0][1])
		return
	if s.run.currents > 0 and policy == "greedy":
		for axis in [0, 1]:
			var n: int = GameConfig.ROWS if axis == 0 else GameConfig.COLS
			for idx in n:
				for dir in [-1, 1]:
					var pv: Dictionary = s.preview_current(axis, idx, dir)
					if pv["changes"] and pv["merges"] > 0:
						s.try_current(axis, idx, dir)
						return
	if not slides.is_empty():
		var m2: Array = slides[rng.randi() % slides.size()]
		s.try_drop(m2[0], m2[1])
	elif not pairs.is_empty():
		s.try_pair(pairs[0][0], pairs[0][1])
	else:
		s.force_stuck_for_testing = true
		s.advance_tide()
		s.force_stuck_for_testing = false

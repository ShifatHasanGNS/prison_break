extends AIController
class_name FuzzyController

var _config: FuzzyConfig = null
var _grid: Node = null
var _cost_map: RefCounted = null
var _exit_rotator: Node = null
var _all_agents: Array = []
var _occupied: Dictionary = {}

func _init() -> void:
	_config = load("res://data/ai/fuzzy_config.tres") as FuzzyConfig
	if _config == null:
		_config = FuzzyConfig.new()

func choose_action(agent: Node2D, grid: Node, cost_map: RefCounted, exit_rotator: Node, all_agents: Array) -> Action:
	_grid = grid
	_cost_map = cost_map
	_exit_rotator = exit_rotator
	_all_agents = all_agents
	_occupied = get_occupied_positions(all_agents, agent.agent_id)

	record_position(agent.grid_pos)

	var prisoners: Array[Vector2i] = get_prisoner_positions(all_agents)
	if prisoners.is_empty():
		return _make_wait_action()

	# Stagnation override
	if is_stagnant():
		var rnd: Vector2i = get_random_legal_move(agent, grid, _occupied)
		var legal_moves: Array[Vector2i] = filter_unoccupied(grid.get_neighbours(agent.grid_pos), _occupied)
		rnd = pick_stable_move(legal_moves, rnd)
		EventBus.emit_signal("fuzzy_decision", agent.agent_id, {}, [], "stagnation_break", rnd)
		return _make_move_action(rnd)

	var active_exit: Vector2i = exit_rotator.get_active_exit()
	var cctv_hint_ticks: int = int(agent.get("cctv_alert_ticks"))
	var cctv_hint: Vector2i = agent.get("cctv_alert_target") if cctv_hint_ticks > 0 else Vector2i(-1, -1)

	var nearest_prisoner: Vector2i = prisoners[0]
	var min_dist: int = manhattan(agent.grid_pos, prisoners[0])
	for i in range(1, prisoners.size()):
		var d: int = manhattan(agent.grid_pos, prisoners[i])
		if d < min_dist:
			min_dist = d
			nearest_prisoner = prisoners[i]
	if cctv_hint.x >= 0:
		var hint_dist: int = manhattan(agent.grid_pos, cctv_hint)
		if hint_dist < min_dist + 3:
			nearest_prisoner = cctv_hint
			min_dist = hint_dist

	var dist_to_prisoner: float = float(min_dist)
	var dist_to_exit: float = float(manhattan(agent.grid_pos, active_exit))

	var prisoner_visibility: float = 0.0
	for a in all_agents:
		if a._role != "police" and a.is_active:
			if grid.raycast(agent.grid_pos, a.grid_pos):
				var d: float = float(manhattan(agent.grid_pos, a.grid_pos))
				if d <= float(agent.stats.vision_range):
					prisoner_visibility = maxf(prisoner_visibility, 1.0 - d / float(agent.stats.vision_range))

	var noise_level: float = 0.0
	for a in all_agents:
		if a._role != "police" and a.is_active:
			var d: int = manhattan(agent.grid_pos, a.grid_pos)
			var effective_noise: int = a.get_effective_noise()
			if d <= effective_noise:
				noise_level = maxf(noise_level, float(effective_noise - d))

	var threat_level: float = 0.0
	if cost_map != null:
		for p: Vector2i in prisoners:
			threat_level += cost_map.get_cost(p)
			if threat_level >= 1e30:
				threat_level = 10.0
	threat_level = clampf(threat_level, 0.0, 10.0)

	var inputs: Dictionary = {
		"dist_to_prisoner": dist_to_prisoner,
		"dist_to_exit": dist_to_exit,
		"prisoner_visibility": prisoner_visibility,
		"noise_level": noise_level,
		"threat_level": threat_level
	}

	var dist_close_m: float = _trap_high(dist_to_prisoner, _config.dist_close, _config.dist_medium)
	var dist_medium_m: float = _trap_mid(dist_to_prisoner, _config.dist_close, _config.dist_medium, _config.dist_far)
	var dist_far_m: float = _trap_low(dist_to_prisoner, _config.dist_medium, _config.dist_far)

	var vis_low_m: float = _trap_high(prisoner_visibility, _config.vis_low, _config.vis_medium)
	var vis_high_m: float = _trap_low(prisoner_visibility, _config.vis_medium, _config.vis_high)

	var noise_quiet_m: float = _trap_high(noise_level, _config.noise_quiet, _config.noise_medium)
	var noise_loud_m: float = _trap_low(noise_level, _config.noise_medium, _config.noise_loud)

	var threat_low_m: float = _trap_high(threat_level, _config.threat_low, _config.threat_medium)
	var threat_high_m: float = _trap_low(threat_level, _config.threat_medium, _config.threat_high)

	var rule_activations: Array = []

	var patrol_strength: float = minf(dist_far_m, minf(vis_low_m, noise_quiet_m)) * _config.w_patrol
	rule_activations.append({"rule": "patrol", "strength": patrol_strength})

	var investigate_strength: float = minf(dist_medium_m, maxf(noise_loud_m * 0.5, vis_low_m * 0.5)) * _config.w_investigate
	rule_activations.append({"rule": "investigate", "strength": investigate_strength})

	var chase_strength: float = minf(dist_close_m, vis_high_m) * _config.w_chase
	rule_activations.append({"rule": "chase", "strength": chase_strength})

	var prisoner_near_exit: float = 0.0
	for p: Vector2i in prisoners:
		var pe: float = float(manhattan(p, active_exit))
		prisoner_near_exit = maxf(prisoner_near_exit, _trap_high(pe, 3.0, 8.0))
	var intercept_strength: float = minf(prisoner_near_exit, threat_high_m) * _config.w_intercept
	rule_activations.append({"rule": "intercept", "strength": intercept_strength})

	rule_activations.sort_custom(func(a, b): return a["strength"] > b["strength"])
	var chosen_behaviour: String = rule_activations[0]["rule"]

	# BFS fallback: if no exit is reachable via A*, the police should still move purposefully
	var baseline: Array[Vector2i] = get_baseline_path(agent, _grid, _cost_map, _exit_rotator)
	var _bfs_active: bool = baseline.is_empty()

	var target_pos: Vector2i = _execute_behaviour(chosen_behaviour, agent, nearest_prisoner, active_exit, prisoners)
	if cctv_hint.x >= 0 and (chosen_behaviour == "investigate" or chosen_behaviour == "patrol"):
		target_pos = _move_toward(agent, cctv_hint)

	# If A* couldn't reach any exit and behaviour yielded no progress, use BFS fallback
	if _bfs_active and target_pos == agent.grid_pos:
		var prisoner_positions: Array[Vector2i] = get_prisoner_positions(_all_agents)
		var bfs_target: Vector2i = bfs_closest_target_fallback(agent, _grid, prisoner_positions)
		target_pos = _move_toward(agent, bfs_target)

	var free_moves: Array[Vector2i] = filter_unoccupied(_grid.get_neighbours(agent.grid_pos), _occupied)
	target_pos = pick_stable_move(free_moves, target_pos, nearest_prisoner)

	EventBus.emit_signal("fuzzy_decision", agent.agent_id, inputs, rule_activations, chosen_behaviour, target_pos)

	return _make_move_action(target_pos)

func _execute_behaviour(behaviour: String, agent: Node2D, nearest_prisoner: Vector2i, active_exit: Vector2i, prisoners: Array[Vector2i]) -> Vector2i:
	match behaviour:
		"chase":
			return _move_toward(agent, nearest_prisoner)
		"intercept":
			return _move_toward(agent, active_exit)
		"investigate":
			return _move_toward(agent, nearest_prisoner)
		"patrol":
			return _patrol_move(agent, active_exit, prisoners)
		_:
			return agent.grid_pos

func _move_toward(agent: Node2D, target: Vector2i) -> Vector2i:
	var path: Array[Vector2i] = _grid.astar(agent.grid_pos, target, _cost_map)
	if path.size() > 1:
		var next_step: Vector2i = path[1]
		if not _occupied.has(next_step):
			return next_step
		# A* next step is occupied — try later steps or greedy fallback
		for i in range(2, path.size()):
			if not _occupied.has(path[i]):
				# Find unoccupied neighbour closest to that waypoint
				var neighbours: Array[Vector2i] = _grid.get_neighbours(agent.grid_pos)
				var free: Array[Vector2i] = filter_unoccupied(neighbours, _occupied)
				if not free.is_empty():
					var best: Vector2i = free[0]
					var best_d: int = manhattan(free[0], path[i])
					for n: Vector2i in free:
						var d: int = manhattan(n, path[i])
						if d < best_d:
							best_d = d
							best = n
					return best
				break

	# Greedy fallback: pick free neighbour closest to target
	var neighbours: Array[Vector2i] = _grid.get_neighbours(agent.grid_pos)
	var free: Array[Vector2i] = filter_unoccupied(neighbours, _occupied)
	if free.is_empty():
		if neighbours.is_empty():
			return agent.grid_pos
		return SimRandom.choice(neighbours)

	var best: Vector2i = free[0]
	var best_dist: int = manhattan(free[0], target)
	for n: Vector2i in free:
		var d: int = manhattan(n, target)
		if d < best_dist:
			best_dist = d
			best = n
	return best

func _patrol_move(agent: Node2D, active_exit: Vector2i, prisoners: Array[Vector2i]) -> Vector2i:
	var mid: Vector2i = active_exit
	if not prisoners.is_empty():
		var sx: int = 0
		var sy: int = 0
		for p: Vector2i in prisoners:
			sx += p.x
			sy += p.y
		mid = Vector2i(sx / prisoners.size(), sy / prisoners.size())
		mid = Vector2i((mid.x + active_exit.x) / 2, (mid.y + active_exit.y) / 2)

	return _move_toward(agent, mid)

func _trap_high(value: float, low_end: float, high_start: float) -> float:
	if value <= low_end:
		return 1.0
	if value >= high_start:
		return 0.0
	var denom := high_start - low_end
	if denom < 0.001:
		return 0.5
	return (high_start - value) / denom

func _trap_low(value: float, low_end: float, high_start: float) -> float:
	if value >= high_start:
		return 1.0
	if value <= low_end:
		return 0.0
	var denom := high_start - low_end
	if denom < 0.001:
		return 0.5
	return (value - low_end) / denom

func _trap_mid(value: float, low: float, mid: float, high: float) -> float:
	if value <= low or value >= high:
		return 0.0
	if value <= mid:
		var denom := mid - low
		if denom < 0.001:
			return 1.0
		return (value - low) / denom
	var denom := high - mid
	if denom < 0.001:
		return 1.0
	return (high - value) / denom

extends AIController
class_name MinimaxController

var _config: MinimaxConfig = null
var _zobrist_cache: Dictionary = {}
var _grid: Node = null
var _cost_map: RefCounted = null
var _danger_map: RefCounted = null
var _exit_rotator: Node = null
var _all_agents: Array = []

func _init() -> void:
	_config = load("res://data/ai/minimax_config.tres") as MinimaxConfig
	if _config == null:
		_config = MinimaxConfig.new()

func clear_cache() -> void:
	_zobrist_cache.clear()

func choose_action(agent: Node2D, grid: Node, cost_map: RefCounted, exit_rotator: Node, all_agents: Array) -> Action:
	_grid = grid
	_cost_map = cost_map
	_exit_rotator = exit_rotator
	_all_agents = all_agents

	# Clear Zobrist cache every tick for freshness
	_zobrist_cache.clear()

	record_position(agent.grid_pos)

	var active_exit: Vector2i = exit_rotator.get_active_exit()
	var occupied: Dictionary = get_occupied_positions(all_agents, agent.agent_id)

	# Already at active exit — WAIT for Phase 14 escape resolution
	if agent.grid_pos == active_exit:
		_emit_decision(agent, [], agent.grid_pos)
		return _make_wait_action()

	var legal_moves: Array[Vector2i] = grid.get_neighbours(agent.grid_pos)
	var free_moves: Array[Vector2i] = filter_unoccupied(legal_moves, occupied)

	if free_moves.is_empty():
		_emit_decision(agent, [], agent.grid_pos)
		if legal_moves.is_empty():
			return _make_wait_action()
		# All neighbours occupied — pick any legal move (collision resolve will handle)
		return _make_move_action(SimRandom.choice(legal_moves))

	# Stagnation override: been stuck in same spot too long
	if is_stagnant():
		var rnd: Vector2i = get_random_legal_move(agent, grid, occupied)
		rnd = pick_stable_move(free_moves, rnd, active_exit)
		_emit_decision(agent, [], rnd)
		return _make_move_action(rnd)

	# BFS fallback: if no exit is reachable via A*, move toward tile farthest from police
	var baseline: Array[Vector2i] = get_baseline_path(agent, grid, cost_map, exit_rotator)
	if baseline.is_empty():
		var police_positions: Array[Vector2i] = get_police_positions(all_agents)
		var bfs_target: Vector2i = bfs_fallback(agent, grid, police_positions)
		var best_move: Vector2i = free_moves[0]
		var best_d: int = manhattan(free_moves[0], bfs_target)
		for m: Vector2i in free_moves:
			var d: int = manhattan(m, bfs_target)
			if d < best_d:
				best_d = d
				best_move = m
		best_move = pick_stable_move(free_moves, best_move, bfs_target)
		_emit_decision(agent, [], best_move)
		return _make_move_action(best_move)

	var police_pos: Vector2i = Vector2i(-1, -1)
	for a in all_agents:
		if a._role == "police" and a.is_active:
			police_pos = a.grid_pos
			break

	var candidates: Array = []
	for move: Vector2i in free_moves:
		var score: float = _alphabeta(move, police_pos, active_exit, agent, maxi(_config.max_depth - 1, 0), -INF, INF, false)
		score -= movement_memory_penalty(move) * 1.25
		candidates.append({"pos": move, "score": score})

	candidates.sort_custom(func(a, b): return a["score"] > b["score"])

	var chosen_pos: Vector2i = candidates[0]["pos"]

	chosen_pos = pick_stable_move(free_moves, chosen_pos, active_exit)

	_emit_decision(agent, candidates, chosen_pos)

	if _zobrist_cache.size() > _config.cache_cap:
		_zobrist_cache.clear()

	return _make_move_action(chosen_pos)

func _alphabeta(red_pos: Vector2i, police_pos: Vector2i, exit: Vector2i, agent: Node2D, depth: int, alpha: float, beta: float, maximising: bool) -> float:
	var cache_key: int = _zobrist_key(red_pos, police_pos, depth, maximising)
	if _zobrist_cache.has(cache_key):
		return _zobrist_cache[cache_key]

	if depth == 0 or red_pos == exit:
		var val: float = _evaluate(red_pos, police_pos, exit, agent)
		_zobrist_cache[cache_key] = val
		return val

	if maximising:
		var max_eval: float = -INF
		var moves: Array[Vector2i] = _grid.get_neighbours(red_pos)
		if moves.is_empty():
			moves = [red_pos]
		for m: Vector2i in moves:
			var eval_score: float = _alphabeta(m, police_pos, exit, agent, depth - 1, alpha, beta, false)
			max_eval = maxf(max_eval, eval_score)
			alpha = maxf(alpha, eval_score)
			if beta <= alpha:
				break
		_zobrist_cache[cache_key] = max_eval
		return max_eval
	else:
		var min_eval: float = INF
		var moves: Array[Vector2i] = _grid.get_neighbours(police_pos)
		if moves.is_empty():
			moves = [police_pos]
		for m: Vector2i in moves:
			var eval_score: float = _alphabeta(red_pos, m, exit, agent, depth - 1, alpha, beta, true)
			min_eval = minf(min_eval, eval_score)
			beta = minf(beta, eval_score)
			if beta <= alpha:
				break
		_zobrist_cache[cache_key] = min_eval
		return min_eval

func _evaluate(red_pos: Vector2i, police_pos: Vector2i, exit: Vector2i, agent: Node2D) -> float:
	var dist_exit: float = float(manhattan(red_pos, exit))
	var dist_police: float = float(manhattan(red_pos, police_pos))
	var danger: float = 0.0
	if _cost_map != null:
		danger = _cost_map.get_cost(red_pos)
		if danger >= 1e30:
			danger = 50.0
	var stam: float = agent.stamina / agent.stats.max_stamina if agent.stats != null else 0.5

	return _config.w_exit * (-dist_exit) + _config.w_risk * (-danger) + _config.w_opp * (-1.0 / maxf(dist_police, 1.0)) + _config.w_stam * stam

func _zobrist_key(red_pos: Vector2i, police_pos: Vector2i, depth: int, maximising: bool) -> int:
	var h: int = red_pos.x * 73856093
	h ^= red_pos.y * 19349663
	h ^= police_pos.x * 83492791
	h ^= police_pos.y * 50331653
	h ^= depth * 15485863
	if maximising:
		h ^= 2654435761
	return h

func _emit_decision(agent: Node2D, candidates: Array, chosen_pos: Vector2i) -> void:
	var top3: Array = []
	var chosen_in_top: bool = false
	for i in range(mini(candidates.size(), 3)):
		top3.append(candidates[i])
		if candidates[i].get("pos", Vector2i(-1, -1)) == chosen_pos:
			chosen_in_top = true
	if not chosen_in_top:
		for c in candidates:
			if c.get("pos", Vector2i(-1, -1)) == chosen_pos:
				if top3.size() >= 3:
					top3[2] = c
				else:
					top3.append(c)
				break
	var chosen_dict: Dictionary = {"pos": chosen_pos}
	EventBus.emit_signal("minimax_decision", agent.agent_id, top3, chosen_dict)

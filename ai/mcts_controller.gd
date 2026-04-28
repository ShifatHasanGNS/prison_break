extends AIController
class_name MctsController

var _config: MctsConfig = null
var _grid: Node = null
var _cost_map: RefCounted = null
var _danger_map: RefCounted = null
var _exit_rotator: Node = null
var _all_agents: Array = []

func _init() -> void:
	_config = load("res://data/ai/mcts_config.tres") as MctsConfig
	if _config == null:
		_config = MctsConfig.new()

func choose_action(agent: Node2D, grid: Node, cost_map: RefCounted, exit_rotator: Node, all_agents: Array) -> Action:
	_grid = grid
	_cost_map = cost_map
	_exit_rotator = exit_rotator
	_all_agents = all_agents

	record_position(agent.grid_pos)

	var active_exit: Vector2i = exit_rotator.get_active_exit()
	var occupied: Dictionary = get_occupied_positions(all_agents, agent.agent_id)

	# Already at active exit — WAIT for Phase 14 escape resolution
	if agent.grid_pos == active_exit:
		_emit_decision(agent, [], agent.grid_pos, 0)
		return _make_wait_action()

	var legal_moves: Array[Vector2i] = grid.get_neighbours(agent.grid_pos)
	var free_moves: Array[Vector2i] = filter_unoccupied(legal_moves, occupied)

	if free_moves.is_empty():
		_emit_decision(agent, [], agent.grid_pos, 0)
		if legal_moves.is_empty():
			return _make_wait_action()
		return _make_move_action(SimRandom.choice(legal_moves))

	# Stagnation override
	if is_stagnant():
		var rnd: Vector2i = get_random_legal_move(agent, grid, occupied)
		rnd = pick_stable_move(free_moves, rnd, active_exit)
		_emit_decision(agent, [], rnd, 0)
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
		_emit_decision(agent, [], best_move, 0)
		return _make_move_action(best_move)

	# MCTS tree: root children = free (unoccupied) legal moves
	var visit_counts: Dictionary = {}
	var total_scores: Dictionary = {}
	for m: Vector2i in free_moves:
		visit_counts[m] = 0
		total_scores[m] = 0.0

	var total_visits: int = 0

	for _iter in range(_config.max_iterations):
		var selected: Vector2i = _uct_select(free_moves, visit_counts, total_scores, total_visits)
		var score: float = _rollout(selected, active_exit, agent)
		visit_counts[selected] += 1
		total_scores[selected] += score
		total_visits += 1

	var candidates: Array = []
	for m: Vector2i in free_moves:
		var avg: float = total_scores[m] / maxf(float(visit_counts[m]), 1.0)
		var decision_score: float = avg + (1.0 / (1.0 + float(manhattan(m, active_exit)))) * 0.25
		decision_score -= movement_memory_penalty(m) * 0.18
		candidates.append({
			"pos": m,
			"visits": visit_counts[m],
			"avg_score": avg,
			"uct": _uct_value(total_scores[m], visit_counts[m], total_visits),
			"decision_score": decision_score
		})

	candidates.sort_custom(func(a, b): return a["decision_score"] > b["decision_score"])

	var chosen_pos: Vector2i = candidates[0]["pos"]
	chosen_pos = pick_stable_move(free_moves, chosen_pos, active_exit)

	_emit_decision(agent, candidates, chosen_pos, total_visits)

	return _make_move_action(chosen_pos)

func _uct_select(moves: Array[Vector2i], visits: Dictionary, scores: Dictionary, total: int) -> Vector2i:
	var best: Vector2i = moves[0]
	var best_uct: float = -INF

	for m: Vector2i in moves:
		if visits[m] == 0:
			return m
		var uct: float = _uct_value(scores[m], visits[m], total)
		if uct > best_uct:
			best_uct = uct
			best = m

	return best

func _uct_value(total_score: float, visit_count: int, parent_visits: int) -> float:
	if visit_count == 0:
		return INF
	var exploit: float = total_score / float(visit_count)
	var explore: float = _config.exploration_constant * sqrt(log(float(parent_visits)) / float(visit_count))
	return exploit + explore

func _rollout(start_pos: Vector2i, exit: Vector2i, agent: Node2D) -> float:
	var pos: Vector2i = start_pos
	var previous_pos: Vector2i = agent.grid_pos
	var police_positions: Array[Vector2i] = get_police_positions(_all_agents)

	for _step in range(_config.rollout_depth):
		if pos == exit:
			return 1.0

		for pp: Vector2i in police_positions:
			if manhattan(pos, pp) <= 1:
				return 0.0

		var neighbours: Array[Vector2i] = _grid.get_neighbours(pos)
		if neighbours.is_empty():
			break

		var next_pos: Vector2i
		if SimRandom.randf() < _config.low_danger_bias:
			next_pos = _pick_best_rollout_step(pos, previous_pos, neighbours, exit, police_positions)
		else:
			next_pos = SimRandom.choice(neighbours)
		previous_pos = pos
		pos = next_pos

	var dist_exit: float = float(manhattan(pos, exit))
	var min_police_dist: float = 999.0
	for pp: Vector2i in police_positions:
		min_police_dist = minf(min_police_dist, float(manhattan(pos, pp)))

	var exit_score: float = 1.0 / (1.0 + dist_exit * 0.1)
	var safety_score: float = minf(min_police_dist / 10.0, 1.0)
	return (exit_score + safety_score) * 0.5

func _pick_best_rollout_step(current: Vector2i, previous: Vector2i, neighbours: Array[Vector2i], exit: Vector2i, police_positions: Array[Vector2i]) -> Vector2i:
	var best: Vector2i = neighbours[0]
	var best_score: float = -INF
	for n: Vector2i in neighbours:
		var score: float = 0.0
		score -= float(manhattan(n, exit)) * 0.35
		if n == previous:
			score -= 1.0
		var danger: float = _cost_map.get_cost(n) if _cost_map != null else 1.0
		if danger >= 1e30:
			score -= 100.0
		else:
			score -= danger * 0.08
		for pp: Vector2i in police_positions:
			score += minf(float(manhattan(n, pp)), 8.0) * 0.08
		score += SimRandom.randf() * 0.02
		if score > best_score:
			best_score = score
			best = n
	return best

func _pick_lowest_danger(neighbours: Array[Vector2i]) -> Vector2i:
	var best: Vector2i = neighbours[0]
	var best_cost: float = INF
	for n: Vector2i in neighbours:
		var c: float = _cost_map.get_cost(n) if _cost_map != null else 1.0
		if c < best_cost:
			best_cost = c
			best = n
	return best

func _emit_decision(agent: Node2D, candidates: Array, chosen_pos: Vector2i, root_visits: int) -> void:
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
	EventBus.emit_signal("mcts_decision", agent.agent_id, root_visits, top3, chosen_dict)

extends AIController
class_name MinimaxController

# ─── CRITICAL #4 FIX: All distance constants converted to tiles ───────────────
# Before: CATCH_RADIUS_PX=100px (≈2.08 tiles), GUARD_PRESSURE_ZONE_PX=250px
#         Mixed with tile-unit dist_exit — heuristic was incoherent.
# After:  Everything in tiles. Guard pressure is proportional to exit reward.
const CATCH_RADIUS_TILES: float    = 2.0   # was CATCH_RADIUS_PX=100 / 48
const GUARD_PRESSURE_ZONE_TILES: float = 5.0   # was GUARD_PRESSURE_ZONE_PX=250 / 48 ≈ 5.2
const PENALTY_GUARD: float  = 800.0
const PENALTY_FIRE: float   = 600.0
const PENALTY_WALL: float   = 300.0
# Guard pressure gradient capped at 60 (proportional to w_exit×3=3×tile reward)
const GRAD_PRESSURE_MAX: float = 60.0

# Keep for _world_dist_px — only used in legacy cache key; not in evaluation.
const TILE_SIZE_PX: float = 48.0

var _config: MinimaxConfig = null
var _zobrist_cache: Dictionary = {}
var _grid: Node = null
var _cost_map: RefCounted = null
var _danger_map: RefCounted = null
var _exit_rotator: Node = null
var _all_agents: Array = []
var _pruned_count: int = 0
var _evaluated_count: int = 0

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

	# MINOR #3 FIX: _zobrist_cache.clear() removed from here.
	# Clearing every call defeated the entire purpose of the transposition table —
	# no states were ever reused. The cap-based clearing in _minimax() is sufficient.
	# The cache now persists valid entries across ticks for meaningful speedup.

	record_position(agent.grid_pos)

	var active_exit: Vector2i = exit_rotator.get_active_exit()
	var occupied: Dictionary = get_occupied_positions(all_agents, agent.agent_id)

	if agent.grid_pos == active_exit:
		_emit_decision(agent, [], agent.grid_pos)
		return _make_wait_action()

	var legal_moves: Array[Vector2i] = grid.get_neighbours(agent.grid_pos)
	var free_moves: Array[Vector2i] = filter_unoccupied(legal_moves, occupied)

	if free_moves.is_empty():
		_emit_decision(agent, [], agent.grid_pos)
		if legal_moves.is_empty():
			return _make_wait_action()
		return _make_move_action(SimRandom.choice(legal_moves))

	if is_stagnant():
		var rnd: Vector2i = get_random_legal_move(agent, grid, occupied)
		rnd = pick_stable_move(free_moves, rnd, active_exit)
		_emit_decision(agent, [], rnd)
		return _make_move_action(rnd)

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
	# FIX #2: Also capture Blue's position so the minimising player can model
	# the real dual-prisoner problem instead of a simplified one-on-one pursuit.
	var blue_pos: Vector2i = Vector2i(-1, -1)
	for a in all_agents:
		if a._role == "police" and a.is_active:
			police_pos = a.grid_pos
		elif a._role == "sneaky_blue" and a.is_active:
			blue_pos = a.grid_pos

	var candidates: Array = []
	_pruned_count = 0
	_evaluated_count = 0
	for move: Vector2i in free_moves:
		var score: float = _alphabeta(move, police_pos, blue_pos, active_exit, agent, maxi(_config.max_depth - 1, 0), -INF, INF, false)
		score -= movement_memory_penalty(move) * 1.25

		# Capture police responses (minimizer layer) so they can be visualized.
		# Re-run one minimizer ply to collect each police counter-move and score.
		var police_responses: Array = []
		if police_pos.x >= 0:
			var police_moves: Array[Vector2i] = _grid.get_neighbours(police_pos)
			if police_moves.is_empty():
				police_moves = [police_pos]
			var response_scores: Array = []
			for pm: Vector2i in police_moves:
				var r_score: float = _alphabeta(move, pm, blue_pos, active_exit, agent, maxi(_config.max_depth - 2, 0), -INF, INF, true)
				var dist_red_pm: int = manhattan(pm, move)
				var dist_blue_pm: int = 9999 if blue_pos.x < 0 else manhattan(pm, blue_pos)
				var dual: float = minf(float(dist_red_pm), float(dist_blue_pm) * 1.1)
				r_score -= dual * 0.08
				response_scores.append({"tile": pm, "score": r_score})
			# Sort ascending: minimizer picks lowest score (worst for Red first)
			response_scores.sort_custom(func(a, b): return float(a["score"]) < float(b["score"]))
			for ri in range(mini(response_scores.size(), 3)):
				var rs: Dictionary = Dictionary(response_scores[ri])
				police_responses.append({
					"tile": rs.get("tile", police_pos),
					"score": rs.get("score", 0.0),
					"is_worst": ri == 0,
				})

		candidates.append({"pos": move, "score": score, "police_responses": police_responses})

	candidates.sort_custom(func(a, b): return a["score"] > b["score"])

	var chosen_pos: Vector2i = candidates[0]["pos"]
	chosen_pos = pick_stable_move(free_moves, chosen_pos, active_exit)

	_emit_decision(agent, candidates, chosen_pos)

	if _zobrist_cache.size() > _config.cache_cap:
		_zobrist_cache.clear()

	return _make_move_action(chosen_pos)

func _alphabeta(
		red_pos: Vector2i,
		police_pos: Vector2i,
		blue_pos: Vector2i,
		exit: Vector2i,
		agent: Node2D,
		depth: int,
		alpha: float,
		beta: float,
		maximising: bool) -> float:
	# FIX #2: blue_pos is now threaded through the whole tree so the minimising
	# player can compute min(dist_to_red, dist_to_blue × 1.1) when choosing moves.
	var dist_police_tiles: float = float(manhattan(red_pos, police_pos))
	var cache_key: int = _zobrist_key(red_pos, police_pos, depth, maximising)
	if _zobrist_cache.has(cache_key):
		return _zobrist_cache[cache_key]

	if depth == 0 or red_pos == exit or dist_police_tiles <= CATCH_RADIUS_TILES:
		var val: float = _evaluate(red_pos, police_pos, exit, agent)
		_zobrist_cache[cache_key] = val
		return val

	if maximising:
		var max_eval: float = -INF
		var moves: Array[Vector2i] = _grid.get_neighbours(red_pos)
		if moves.is_empty():
			moves = [red_pos]
		for m: Vector2i in moves:
			var eval_score: float = _alphabeta(m, police_pos, blue_pos, exit, agent, depth - 1, alpha, beta, false)
			max_eval = maxf(max_eval, eval_score)
			alpha = maxf(alpha, eval_score)
			if beta <= alpha:
				_pruned_count += moves.size() - (moves.find(m) + 1)
				break
		_zobrist_cache[cache_key] = max_eval
		return max_eval
	else:
		var min_eval: float = INF
		var moves: Array[Vector2i] = _grid.get_neighbours(police_pos)
		if moves.is_empty():
			moves = [police_pos]
		for m: Vector2i in moves:
			# FIX #2: Police minimises over both prisoners simultaneously.
			# It moves toward whichever target is cheaper to close in on,
			# weighting Blue 10% lower so Red (the explicit tree agent) stays primary.
			var dist_red: int  = manhattan(m, red_pos)
			var dist_blue: int = 9999
			if blue_pos.x >= 0:
				dist_blue = manhattan(m, blue_pos)
			var dual_threat: float = minf(float(dist_red), float(dist_blue) * 1.1)
			var eval_score: float = _alphabeta(red_pos, m, blue_pos, exit, agent, depth - 1, alpha, beta, true)
			# Blend alphabeta score with dual-threat pressure so the tree
			# prefers police moves that threaten both prisoners.
			eval_score -= dual_threat * 0.08
			min_eval = minf(min_eval, eval_score)
			beta = minf(beta, eval_score)
			if beta <= alpha:
				_pruned_count += moves.size() - (moves.find(m) + 1)
				break
		_zobrist_cache[cache_key] = min_eval
		return min_eval

# ─── CRITICAL #4 FIX: _evaluate now fully in tiles — no pixel math ───────────
# Old: guard_penalty used _world_dist_px() (pixels) mixed with tile exit score.
# New: dist_police is manhattan tile count throughout. Gradient pressure
#      is (zone - dist) / zone * GRAD_PRESSURE_MAX, proportional to exit reward.
func _evaluate(red_pos: Vector2i, police_pos: Vector2i, exit: Vector2i, agent: Node2D) -> float:
	var dist_exit: float   = float(manhattan(red_pos, exit))
	var dist_police: float = float(manhattan(red_pos, police_pos))
	var danger: float      = 0.0
	var wall_penalty: float = 0.0
	var fire_penalty: float = 0.0

	if _cost_map != null:
		danger = _cost_map.get_cost(red_pos)
		if danger >= 1e30:
			wall_penalty = PENALTY_WALL
			danger = 50.0
		elif danger >= 14.0:
			fire_penalty = PENALTY_FIRE

	var stam: float = agent.stamina / agent.stats.max_stamina if agent.stats != null else 0.5

	var guard_penalty: float = 0.0
	# Hard capture penalty — same as before
	if dist_police <= CATCH_RADIUS_TILES:
		guard_penalty += PENALTY_GUARD
	# Gradient pressure — now in tiles, proportional to exit reward (w_exit × tiles)
	if dist_police <= GUARD_PRESSURE_ZONE_TILES:
		guard_penalty += ((GUARD_PRESSURE_ZONE_TILES - dist_police) / GUARD_PRESSURE_ZONE_TILES) * GRAD_PRESSURE_MAX

	# Exit rotation timing penalty: if the exit will rotate before Red can reach it,
	# penalize heading for this exit — it will be gone by the time Red arrives.
	# Encourages the tree to find alternative paths rather than sprinting to a soon-to-rotate exit.
	if _exit_rotator != null:
		var ticks_left: int = _exit_rotator.ticks_until_next_rotation()
		if ticks_left > 0 and int(dist_exit) > ticks_left:
			guard_penalty += 80.0  # current exit unreachable before rotation

	return _config.w_exit * (-dist_exit) \
		+ _config.w_risk * (-danger) \
		+ _config.w_opp * (-1.0 / maxf(dist_police, 1.0)) \
		+ _config.w_stam * stam \
		- guard_penalty - fire_penalty - wall_penalty

func _world_dist_px(a: Vector2i, b: Vector2i) -> float:
	# Retained only for any external callers; not used in _evaluate anymore.
	return Vector2(a).distance_to(Vector2(b)) * TILE_SIZE_PX

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
	var top_candidates: Array = []
	var chosen_in_top: bool = false
	var chosen_score: float = 0.0
	for i in range(mini(candidates.size(), 5)):
		top_candidates.append(candidates[i])
		if candidates[i].get("pos", Vector2i(-1, -1)) == chosen_pos:
			chosen_in_top = true
			chosen_score = float(candidates[i].get("score", 0.0))
	if not chosen_in_top:
		for c in candidates:
			if c.get("pos", Vector2i(-1, -1)) == chosen_pos:
				if top_candidates.size() >= 5:
					top_candidates[4] = c
				else:
					top_candidates.append(c)
				chosen_score = float(c.get("score", 0.0))
				break
	var total_branches: int = 0
	for cand in candidates:
		total_branches += 1
		if cand.get("police_responses", []).size() > 0:
			total_branches += cand.get("police_responses", []).size()
	var chosen_dict: Dictionary = {
		"pos": chosen_pos,
		"score": chosen_score,
		"reason": _describe_choice_reason(agent, chosen_pos),
		"pruned_branches": _pruned_count,
		"evaluated_nodes": total_branches,
		"search_depth": _config.max_depth if _config != null else 4,
	}
	EventBus.emit_signal("minimax_decision", agent.agent_id, top_candidates, chosen_dict)

func _describe_choice_reason(agent: Node2D, chosen_pos: Vector2i) -> String:
	if _exit_rotator == null:
		return "best score"
	var exit_tile: Vector2i = _exit_rotator.get_active_exit()
	var now_exit_dist: int = manhattan(agent.grid_pos, exit_tile)
	var next_exit_dist: int = manhattan(chosen_pos, exit_tile)
	var police_dist: int = 99
	for entity in _all_agents:
		var police_agent: Agent = entity as Agent
		if police_agent == null:
			continue
		if police_agent._role != "police":
			continue
		if not police_agent.is_active:
			continue
		police_dist = manhattan(chosen_pos, police_agent.grid_pos)
		break
	var danger: float = 0.0
	if _cost_map != null:
		danger = float(_cost_map.get_cost(chosen_pos))
		if danger >= 1e30:
			danger = 50.0
	if next_exit_dist < now_exit_dist:
		if police_dist >= 5:
			return "exit progress · police far"
		return "exit progress · risk accepted"
	if danger <= 1.4:
		return "safer lane · score lead"
	return "best score branch"

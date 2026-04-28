extends RefCounted
class_name AIController

var _position_history: Array[Vector2i] = []
const HISTORY_SIZE: int = 8
const OSCILLATION_LOOKBACK: int = 4
const STAGNATION_THRESHOLD: int = 3
const NO_TARGET: Vector2i = Vector2i(-99999, -99999)

func choose_action(_agent: Node2D, _grid: Node, _cost_map: RefCounted, _exit_rotator: Node, _all_agents: Array) -> Action:
	return _make_wait_action()

# --- AI Robustness Contract helpers ---

func get_baseline_path(agent: Node2D, grid: Node, cost_map: RefCounted, exit_rotator: Node) -> Array[Vector2i]:
	var active_exit: Vector2i = exit_rotator.get_active_exit()
	var path: Array[Vector2i] = grid.astar(agent.grid_pos, active_exit, cost_map)
	if path.size() > 1:
		return path

	var exits: Array[Vector2i] = exit_rotator.get_exits()
	for ex: Vector2i in exits:
		if ex == active_exit:
			continue
		path = grid.astar(agent.grid_pos, ex, cost_map)
		if path.size() > 1:
			return path

	return []

func bfs_fallback(agent: Node2D, grid: Node, police_positions: Array[Vector2i]) -> Vector2i:
	var start: Vector2i = agent.grid_pos
	var visited: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var farthest: Vector2i = start
	var best_dist: int = 0

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var min_police_dist: int = 999
		for pp: Vector2i in police_positions:
			var d: int = absi(current.x - pp.x) + absi(current.y - pp.y)
			if d < min_police_dist:
				min_police_dist = d
		if min_police_dist > best_dist:
			best_dist = min_police_dist
			farthest = current

		for nb: Vector2i in grid.get_neighbours(current):
			if not visited.has(nb):
				visited[nb] = true
				queue.append(nb)

	return farthest

func bfs_closest_target_fallback(agent: Node2D, grid: Node, targets: Array[Vector2i]) -> Vector2i:
	var start: Vector2i = agent.grid_pos
	if targets.is_empty():
		return start

	var visited: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var best: Vector2i = start
	var best_dist: int = _nearest_target_distance(start, targets)

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var target_dist: int = _nearest_target_distance(current, targets)
		if target_dist < best_dist:
			best_dist = target_dist
			best = current

		for nb: Vector2i in grid.get_neighbours(current):
			if not visited.has(nb):
				visited[nb] = true
				queue.append(nb)

	return best

func record_position(pos: Vector2i) -> void:
	_position_history.append(pos)
	if _position_history.size() > HISTORY_SIZE:
		_position_history.pop_front()

func clear_history() -> void:
	_position_history.clear()

func _is_oscillating_old(next_pos: Vector2i) -> bool:
	# Detect actual ping-pong patterns (A→B→A→B) rather than simple recurrence
	# which triggers false positives for legitimate backtracking through corridors
	var h := _position_history
	var n := h.size()
	if n < 2:
		return false
	# Pattern: current→next matches two steps ago→one step ago (A→B→A→B)
	if n >= 2 and h[n - 2] == next_pos and h[n - 1] == h[n - 2]:
		return true
	# Pattern: A→B→A — next_pos is where we were 2 steps ago, and we just moved away
	if n >= 3 and h[n - 3] == next_pos and h[n - 1] == next_pos:
		return true
	# Pattern: extended oscillation — same two positions alternating for 4+ steps
	if n >= 4:
		var a: Vector2i = h[n - 1]
		var b: Vector2i = h[n - 2]
		if a != b and h[n - 3] == a and h[n - 4] == b and next_pos == b:
			return true
	return false

func is_oscillating(next_pos: Vector2i) -> bool:
	var h := _position_history
	var n := h.size()
	if n < 2:
		return false

	var current: Vector2i = h[n - 1]
	if next_pos == current:
		return is_stagnant()
	if h[n - 2] == next_pos:
		return true
	if n >= 4 and h[n - 1] == h[n - 3] and h[n - 2] == h[n - 4] and next_pos == h[n - 2]:
		return true
	if n >= 3 and h[n - 3] == next_pos:
		return true
	return false

func pick_stable_move(moves: Array[Vector2i], preferred: Vector2i, target: Vector2i = NO_TARGET) -> Vector2i:
	if moves.is_empty():
		return preferred
	if not moves.has(preferred):
		preferred = moves[0]
	if not is_oscillating(preferred) and _recent_visit_count(preferred) <= 1:
		return preferred

	var best: Vector2i = preferred
	var best_score: float = -INF
	for move: Vector2i in moves:
		var score: float = 0.0
		if move == preferred:
			score += 2.0
		if is_oscillating(move):
			score -= 10.0
		score -= float(_recent_visit_count(move)) * 2.5
		if target != NO_TARGET:
			score -= float(manhattan(move, target)) * 0.35
		score += SimRandom.randf() * 0.01
		if score > best_score:
			best_score = score
			best = move
	return best

func movement_memory_penalty(pos: Vector2i) -> float:
	var penalty := float(_recent_visit_count(pos))
	if is_oscillating(pos):
		penalty += 4.0
	return penalty

func is_stagnant() -> bool:
	if _position_history.size() < STAGNATION_THRESHOLD:
		return false
	var last: Vector2i = _position_history[_position_history.size() - 1]
	var start_idx: int = _position_history.size() - STAGNATION_THRESHOLD
	for i in range(start_idx, _position_history.size()):
		if _position_history[i] != last:
			return false
	return true

func get_occupied_positions(all_agents: Array, exclude_id: int) -> Dictionary:
	var occupied: Dictionary = {}
	for a in all_agents:
		if a.get("agent_id") != exclude_id and a.get("is_active"):
			occupied[a.get("grid_pos")] = true
	return occupied

func filter_unoccupied(moves: Array[Vector2i], occupied: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for m: Vector2i in moves:
		if not occupied.has(m):
			result.append(m)
	return result

func get_random_legal_move(agent: Node2D, grid: Node, occupied: Dictionary = {}) -> Vector2i:
	var neighbours: Array[Vector2i] = grid.get_neighbours(agent.grid_pos)
	var free: Array[Vector2i] = filter_unoccupied(neighbours, occupied)
	if free.is_empty():
		if neighbours.is_empty():
			return agent.grid_pos
		return SimRandom.choice(neighbours)
	return SimRandom.choice(free)

func get_police_positions(all_agents: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for a in all_agents:
		if a._role == "police" and a.is_active:
			result.append(a.grid_pos)
	return result

func get_prisoner_positions(all_agents: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for a in all_agents:
		if a._role != "police" and a.is_active:
			result.append(a.grid_pos)
	return result

func _make_move_action(target: Vector2i) -> Action:
	var a := Action.new()
	a.type = Action.Type.MOVE
	a.target_pos = target
	a.noise_generated = 3
	return a

func _make_wait_action() -> Action:
	var a := Action.new()
	a.type = Action.Type.WAIT
	a.target_pos = Vector2i.ZERO
	return a

func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _recent_visit_count(pos: Vector2i) -> int:
	var count: int = 0
	for old_pos: Vector2i in _position_history:
		if old_pos == pos:
			count += 1
	return count

func _nearest_target_distance(pos: Vector2i, targets: Array[Vector2i]) -> int:
	var best: int = 99999
	for target: Vector2i in targets:
		best = mini(best, manhattan(pos, target))
	return best

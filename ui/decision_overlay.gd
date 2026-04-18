# UPDATED — overlay strict typing hardening
extends Node2D
class_name DecisionOverlay

const TILE_SIZE: int = 48
const PAD: float = 5.0
const MIN_WEIGHT: float = 0.18
const CHOSEN_WEIGHT: float = 1.0

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, -1),
	Vector2i(0, 1),
]

var _agents: Array = []
var _grid: GridEngine = null
var _decisions: Dictionary = {}

func setup(agents: Array, grid: GridEngine) -> void:
	_agents = agents
	_grid = grid
	EventBus.minimax_decision.connect(_on_minimax_decision)
	EventBus.mcts_decision.connect(_on_mcts_decision)
	EventBus.fuzzy_decision.connect(_on_fuzzy_decision)
	EventBus.tick_ended.connect(_on_tick_ended)
	EventBus.agent_action_chosen.connect(_on_action_chosen)
	queue_redraw()

func _process(_delta: float) -> void:
	if not _decisions.is_empty():
		queue_redraw()

func _on_minimax_decision(id: int, candidates: Array, chosen: Dictionary) -> void:
	var chosen_pos: Vector2i = chosen.get("pos", Vector2i(-1, -1))
	_store_decision(id, candidates, chosen_pos, "score")

func _on_mcts_decision(id: int, _root_visits: int, candidates: Array, chosen: Dictionary) -> void:
	var chosen_pos: Vector2i = chosen.get("pos", Vector2i(-1, -1))
	_store_decision(id, candidates, chosen_pos, "visits")

func _on_fuzzy_decision(id: int, _inputs: Dictionary, _rule_activations: Array, _output: String, chosen_pos: Vector2i) -> void:
	_store_decision(id, [], chosen_pos, "")

func _on_tick_ended(_n: int) -> void:
	queue_redraw()

func _on_action_chosen(id: int, action: String) -> void:
	if action == "STUNNED":
		var agent: Agent = _agent_for(id)
		_store_decision(id, [], agent.grid_pos if agent != null else Vector2i(-1, -1), "")

func _store_decision(id: int, candidates: Array, chosen_pos: Vector2i, metric: String) -> void:
	var agent: Agent = _agent_for(id)
	if agent == null:
		return
	var origin: Vector2i = agent.grid_pos
	var weights: Dictionary = _base_weights(origin, chosen_pos)
	_apply_candidate_weights(weights, candidates, metric)
	if chosen_pos.x >= 0:
		weights[chosen_pos] = CHOSEN_WEIGHT
	_decisions[id] = {"origin": origin, "chosen": chosen_pos, "weights": weights}
	queue_redraw()

func _base_weights(origin: Vector2i, chosen_pos: Vector2i) -> Dictionary:
	var weights: Dictionary = {}
	for dir in DIRS:
		var pos: Vector2i = origin + dir
		var weight: float = MIN_WEIGHT
		if pos == chosen_pos:
			weight = CHOSEN_WEIGHT
		weights[pos] = weight
	return weights

func _apply_candidate_weights(weights: Dictionary, candidates: Array, metric: String) -> void:
	if candidates.is_empty():
		return
	var max_abs: float = 0.1
	var min_score: float = INF
	var max_score: float = -INF
	var max_visits: float = 1.0
	for row in candidates:
		if metric == "visits":
			max_visits = maxf(max_visits, float(row.get("visits", 0)))
		elif metric == "score":
			var score: float = float(row.get("score", 0.0))
			min_score = minf(min_score, score)
			max_score = maxf(max_score, score)
			max_abs = maxf(max_abs, absf(score))
	for row in candidates:
		var pos: Vector2i = row.get("pos", Vector2i(-1, -1))
		if not weights.has(pos):
			continue
		var norm: float = MIN_WEIGHT
		if metric == "visits":
			norm = maxf(MIN_WEIGHT, float(row.get("visits", 0)) / max_visits)
		elif metric == "score":
			var score2: float = float(row.get("score", 0.0))
			var spread: float = max_score - min_score
			if spread > 0.001:
				norm = (score2 - min_score) / spread
			else:
				norm = (score2 + max_abs) / (2.0 * max_abs)
			norm = maxf(MIN_WEIGHT, clampf(norm, 0.0, 1.0))
		weights[pos] = norm

func _draw() -> void:
	if _grid == null:
		return
	for agent in _agents:
		if not agent.is_active:
			continue
		var data: Dictionary = _decisions.get(agent.agent_id, {})
		var origin: Vector2i = data.get("origin", agent.grid_pos)
		var chosen: Vector2i = data.get("chosen", Vector2i(-1, -1))
		var weights: Dictionary = data.get("weights", _base_weights(origin, chosen))
		var color: Color = _agent_color(agent)
		for dir in DIRS:
			var pos: Vector2i = origin + dir
			var weight: float = clampf(float(weights.get(pos, MIN_WEIGHT)), MIN_WEIGHT, 1.0)
			_draw_tile_choice(pos, color, weight, pos == chosen)

func _draw_tile_choice(pos: Vector2i, color: Color, weight: float, chosen: bool) -> void:
	var tile: GridTileData = _grid.get_tile(pos)
	var in_bounds: bool = tile != null
	if not in_bounds:
		return
	var walkable: bool = tile.walkable
	var alpha: float = 0.12 + weight * 0.26
	if chosen:
		alpha = 0.58
	elif not walkable:
		alpha *= 0.38
	var x: float = float(pos.x * TILE_SIZE)
	var y: float = float(pos.y * TILE_SIZE)
	var rect: Rect2 = Rect2(x + PAD, y + PAD, TILE_SIZE - PAD * 2.0, TILE_SIZE - PAD * 2.0)
	draw_rect(rect, Color(color.r, color.g, color.b, alpha))
	draw_rect(rect, Color(color.r, color.g, color.b, 0.95 if chosen else 0.38), false, 2.0 if chosen else 1.0)
	if chosen:
		var center: Vector2 = rect.get_center()
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
		draw_arc(center, TILE_SIZE * (0.32 + pulse * 0.05), 0.0, TAU, 24, Color(color.r, color.g, color.b, 0.70), 2.0)
	elif not walkable:
		draw_line(rect.position + Vector2(5.0, 5.0), rect.end - Vector2(5.0, 5.0), Color(color.r, color.g, color.b, 0.30), 1.0)

func _agent_color(agent: Agent) -> Color:
	match agent._role:
		"rusher_red": return Color(0.94, 0.27, 0.27)
		"sneaky_blue": return Color(0.18, 1.00, 0.92)
		"police": return Color(1.00, 0.86, 0.24)
		_: return Color.WHITE

func _agent_for(id: int) -> Agent:
	for agent in _agents:
		if agent.agent_id == id:
			return agent
	return null

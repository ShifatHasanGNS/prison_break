extends Node
class_name ScoringSystem

const TICK_SECONDS: float = 0.25

const FIRST_ESCAPE_BONUS: float = 420.0
const SECOND_ESCAPE_BONUS: float = 260.0
const PROGRESS_CELL_BONUS: float = 10.0
const SURVIVAL_PER_SECOND: float = 0.8

const DOG_ZONE_PENALTY_PER_SECOND: float = -8.0
const CAMERA_HIT_PENALTY: float = -7.0
const WALL_HIT_PENALTY: float = -3.0
const FIRE_ELIMINATION_PENALTY: float = -45.0
const CAPTURE_PENALTY: float = -65.0

const CAPTURE_BONUS: float = 130.0
const DOG_ASSIST_BONUS: float = 18.0
const CCTV_ASSIST_BONUS: float = 12.0
const FIRE_ASSIST_BONUS: float = 10.0
const PRESSURE_PER_SECOND: float = 1.8
const ESCAPE_ALLOWED_PENALTY: float = -220.0
const FULL_CONTAINMENT_BONUS: float = 850.0

const DOG_ZONE_STEALTH_DRAIN_PER_SECOND: float = 8.0
const CAMERA_STEALTH_DROP: float = 7.0
const CAPTURE_HEALTH_LOSS: float = 25.0
const CAPTURE_STEALTH_RESET: float = 50.0

var _agents: Array[Agent] = []
var _exit_rotator: ExitRotator = null
var _dog_npc: DogNPC = null
var _camera_system: CCTVCameraSystem = null

var _escape_order: Array[int] = []
var _base_exit_dist: Dictionary = {}
var _best_progress_cells: Dictionary = {}
var _last_camera_tick: Dictionary = {}

func setup(agents: Array[Agent], exit_rotator: ExitRotator, dog_npc: DogNPC, camera_system: CCTVCameraSystem) -> void:
	_agents = agents
	_exit_rotator = exit_rotator
	_dog_npc = dog_npc
	_camera_system = camera_system
	_escape_order.clear()
	_base_exit_dist.clear()
	_best_progress_cells.clear()
	_last_camera_tick.clear()

	for agent in _agents:
		_ensure_metrics(agent)
		if agent._role != "police":
			var base_dist: int = _closest_exit_distance(agent.grid_pos)
			_base_exit_dist[agent.agent_id] = maxi(1, base_dist)
			_best_progress_cells[agent.agent_id] = 0

	EventBus.agent_escaped.connect(_on_agent_escaped)
	EventBus.agent_captured.connect(_on_agent_captured)
	EventBus.agent_blocked_move.connect(_on_agent_blocked_move)
	EventBus.agent_eliminated_by_fire.connect(_on_agent_eliminated_by_fire)
	EventBus.camera_detection.connect(_on_camera_detection)
	EventBus.dog_spotted_prisoner.connect(_on_dog_spotted_prisoner)

func tick() -> void:
	for agent in _agents:
		_ensure_metrics(agent)
		if agent._role == "police":
			_tick_police(agent)
		else:
			_tick_prisoner(agent)
		_update_performance(agent)

func apply_final_bonuses(outcome: String, escaped_count: int) -> void:
	if outcome == "police_wins" and escaped_count == 0:
		var police: Agent = _get_police()
		if police != null:
			_add_score(police, FULL_CONTAINMENT_BONUS, "full_containment_bonus")
			_update_performance(police)

func _tick_prisoner(agent: Agent) -> void:
	if agent.is_active:
		_add_score(agent, SURVIVAL_PER_SECOND * TICK_SECONDS, "survival")

		var base_dist: int = int(_base_exit_dist.get(agent.agent_id, _closest_exit_distance(agent.initial_pos)))
		var current_dist: int = _closest_exit_distance(agent.grid_pos)
		var progress_cells: int = maxi(0, base_dist - current_dist)
		var old_best: int = int(_best_progress_cells.get(agent.agent_id, 0))
		if progress_cells > old_best:
			var gained: int = progress_cells - old_best
			_best_progress_cells[agent.agent_id] = progress_cells
			agent.metrics["best_progress_cells"] = progress_cells
			_add_score(agent, float(gained) * PROGRESS_CELL_BONUS, "progress_gain")

		var in_dog_zone: bool = _is_in_dog_zone(agent)
		if in_dog_zone:
			agent.metrics["dog_zone_time"] = float(agent.metrics.get("dog_zone_time", 0.0)) + TICK_SECONDS
			_add_score(agent, DOG_ZONE_PENALTY_PER_SECOND * TICK_SECONDS, "dog_zone_penalty")
			agent.stealth_level = clampf(agent.stealth_level - DOG_ZONE_STEALTH_DRAIN_PER_SECOND * TICK_SECONDS, 0.0, 100.0)

func _tick_police(agent: Agent) -> void:
	if not agent.is_active:
		return
	if _is_pressuring_prisoner(agent):
		_add_score(agent, PRESSURE_PER_SECOND * TICK_SECONDS, "pressure")

func _on_agent_escaped(agent_id: int) -> void:
	var escaped: Agent = _find_agent(agent_id)
	if escaped == null:
		return
	if not _escape_order.has(agent_id):
		_escape_order.append(agent_id)
	var rank: int = _escape_order.size()
	if rank == 1:
		_add_score(escaped, FIRST_ESCAPE_BONUS, "first_escape")
	elif rank == 2:
		_add_score(escaped, SECOND_ESCAPE_BONUS, "second_escape")

	var police: Agent = _get_police()
	if police != null:
		police.metrics["escapes_allowed"] = int(police.metrics.get("escapes_allowed", 0)) + 1
		_add_score(police, ESCAPE_ALLOWED_PENALTY, "escape_allowed")
		_update_performance(police)
	_update_performance(escaped)

func _on_agent_captured(agent_id: int) -> void:
	var prisoner: Agent = _find_agent(agent_id)
	if prisoner == null:
		return
	_add_score(prisoner, CAPTURE_PENALTY, "captured")
	prisoner.health = maxf(0.0, prisoner.health - CAPTURE_HEALTH_LOSS)
	prisoner.stealth_level = CAPTURE_STEALTH_RESET
	_update_performance(prisoner)

	var police: Agent = _get_police()
	if police != null:
		police.metrics["captures_made"] = int(police.metrics.get("captures_made", 0)) + 1
		_add_score(police, CAPTURE_BONUS, "capture_bonus")
		_update_performance(police)

func _on_agent_blocked_move(agent_id: int, _from: Vector2i, _target: Vector2i, _reason: String) -> void:
	var prisoner: Agent = _find_agent(agent_id)
	if prisoner == null or prisoner._role == "police":
		return
	prisoner.metrics["wall_hits"] = int(prisoner.metrics.get("wall_hits", 0)) + 1
	_add_score(prisoner, WALL_HIT_PENALTY, "blocked_move")
	_update_performance(prisoner)

func _on_agent_eliminated_by_fire(agent_id: int) -> void:
	var prisoner: Agent = _find_agent(agent_id)
	if prisoner == null:
		return
	_add_score(prisoner, FIRE_ELIMINATION_PENALTY, "fire_elimination")
	_update_performance(prisoner)

	var police: Agent = _get_police()
	if police != null:
		police.metrics["fire_assists"] = int(police.metrics.get("fire_assists", 0)) + 1
		_add_score(police, FIRE_ASSIST_BONUS, "fire_assist")
		_update_performance(police)

func _on_camera_detection(_camera_id: int, agent_id: int, visible: bool, tile: Vector2i, detail: Dictionary) -> void:
	if not visible:
		return
	var prisoner: Agent = _find_agent(agent_id)
	if prisoner == null:
		return
	var tick_now: int = int(detail.get("tick", 0))
	var key: String = str(agent_id)
	var allow_tick: int = int(_last_camera_tick.get(key, -9999)) + 1
	if tick_now < allow_tick:
		return
	_last_camera_tick[key] = tick_now
	_add_score(prisoner, CAMERA_HIT_PENALTY, "camera_detection")
	prisoner.metrics["camera_hits"] = int(prisoner.metrics.get("camera_hits", 0)) + 1
	prisoner.stealth_level = clampf(prisoner.stealth_level - CAMERA_STEALTH_DROP, 0.0, 100.0)
	_update_performance(prisoner)

	var police: Agent = _get_police()
	if police != null:
		police.metrics["cctv_assists"] = int(police.metrics.get("cctv_assists", 0)) + 1
		_add_score(police, CCTV_ASSIST_BONUS, "cctv_assist")
		_update_performance(police)
		police.cctv_alert_target = tile
		police.cctv_alert_ticks = 10

func _on_dog_spotted_prisoner(agent_id: int, _tile: Vector2i) -> void:
	var prisoner: Agent = _find_agent(agent_id)
	if prisoner == null:
		return
	var police: Agent = _get_police()
	if police != null:
		police.metrics["dog_assists"] = int(police.metrics.get("dog_assists", 0)) + 1
		_add_score(police, DOG_ASSIST_BONUS, "dog_assist")
		_update_performance(police)

func _update_performance(agent: Agent) -> void:
	var raw: float = float(agent.metrics.get("raw_score", 0.0))
	var perf: float
	if agent._role == "police":
		var captures: int = int(agent.metrics.get("captures_made", 0))
		var dog_assists: int = int(agent.metrics.get("dog_assists", 0))
		var cctv_assists: int = int(agent.metrics.get("cctv_assists", 0))
		var escapes_allowed: int = int(agent.metrics.get("escapes_allowed", 0))
		perf = 50.0 + 0.04 * raw + 10.0 * float(captures) + 2.5 * float(dog_assists) + 1.5 * float(cctv_assists) - 15.0 * float(escapes_allowed)
	else:
		var best_progress: int = int(agent.metrics.get("best_progress_cells", 0))
		var camera_hits: int = int(agent.metrics.get("camera_hits", 0))
		var wall_hits: int = int(agent.metrics.get("wall_hits", 0))
		perf = 50.0 + 0.06 * raw + 0.5 * float(best_progress) - 1.4 * float(camera_hits) - 1.0 * float(wall_hits) + 0.18 * (agent.health - 50.0) + 0.10 * (agent.stealth_level - 50.0)
	agent.metrics["performance"] = clampf(perf, 0.0, 100.0)

func _add_score(agent: Agent, delta: float, reason: String) -> void:
	if absf(delta) < 0.0001:
		return
	agent.metrics["raw_score"] = float(agent.metrics.get("raw_score", 0.0)) + delta
	if reason in ["survival", "pressure", "dog_zone_penalty"]:
		return
	var team: String = "police" if agent._role == "police" else "prisoner"
	EventBus.emit_signal("score_event", agent.agent_id, delta, reason, team)

func _closest_exit_distance(pos: Vector2i) -> int:
	if _exit_rotator == null:
		return 0
	var exits: Array[Vector2i] = _exit_rotator.get_exits()
	if exits.is_empty():
		return 0
	var best: int = 99999
	for ex in exits:
		best = mini(best, _manhattan(pos, ex))
	return best

func _is_in_dog_zone(agent: Agent) -> bool:
	if _dog_npc == null:
		return false
	var radius: int = _dog_npc.get_danger_radius()
	return _manhattan(agent.grid_pos, _dog_npc.grid_pos) <= radius

func _is_pressuring_prisoner(police: Agent) -> bool:
	for agent in _agents:
		if agent._role == "police" or not agent.is_active:
			continue
		var world_dist: float = police.position.distance_to(agent.position)
		if world_dist <= 300.0:
			return true
	var alert_level: float = float(police.metrics.get("alert_level", 0.0))
	return alert_level > 0.35

func _ensure_metrics(agent: Agent) -> void:
	if not agent.metrics.has("raw_score"):
		agent.metrics["raw_score"] = 0.0
	if not agent.metrics.has("performance"):
		agent.metrics["performance"] = 50.0
	if not agent.metrics.has("best_progress_cells"):
		agent.metrics["best_progress_cells"] = 0
	if not agent.metrics.has("dog_zone_time"):
		agent.metrics["dog_zone_time"] = 0.0
	if not agent.metrics.has("camera_hits"):
		agent.metrics["camera_hits"] = 0
	if not agent.metrics.has("wall_hits"):
		agent.metrics["wall_hits"] = 0
	if not agent.metrics.has("dog_assists"):
		agent.metrics["dog_assists"] = 0
	if not agent.metrics.has("cctv_assists"):
		agent.metrics["cctv_assists"] = 0
	if not agent.metrics.has("fire_assists"):
		agent.metrics["fire_assists"] = 0
	if not agent.metrics.has("escapes_allowed"):
		agent.metrics["escapes_allowed"] = 0
	if not agent.metrics.has("captures_made"):
		agent.metrics["captures_made"] = 0
	if not agent.metrics.has("alert_level"):
		agent.metrics["alert_level"] = 0.0

func _get_police() -> Agent:
	for agent in _agents:
		if agent._role == "police":
			return agent
	return null

func _find_agent(agent_id: int) -> Agent:
	for agent in _agents:
		if agent.agent_id == agent_id:
			return agent
	return null

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

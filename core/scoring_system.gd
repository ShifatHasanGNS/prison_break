extends Node
class_name ScoringSystem

const TICK_SECONDS: float = 0.25

# ── PRISONER SCORING ──────────────────────────────────────────────────────────
# Escape bonuses (reduced to lower overall prisoner ceiling)
const FIRST_ESCAPE_BONUS:    float = 300.0
const SECOND_ESCAPE_BONUS:   float = 190.0

# Progress & survival (smaller per-cell to avoid drowning capture significance)
const PROGRESS_CELL_BONUS:   float = 6.0
const SURVIVAL_PER_SECOND:   float = 0.5

# Hazard penalties (slightly harsher to make risky play costly)
const DOG_ZONE_PENALTY_PER_SECOND: float = -12.0
const CAMERA_HIT_PENALTY:          float = -10.0
const WALL_HIT_PENALTY:            float = -4.0
const FIRE_ELIMINATION_PENALTY:    float = -55.0
const CAPTURE_PENALTY:             float = -75.0
# MODERATE #2 FIX: Timeout is a lighter penalty than a real capture — the
# prisoner was not actively caught, just ran out of time.
const TIMEOUT_PENALTY:             float = -35.0

# Attribute effects on capture
const CAPTURE_HEALTH_LOSS:    float = 25.0
const CAPTURE_STEALTH_RESET:  float = 50.0
const DOG_ZONE_STEALTH_DRAIN_PER_SECOND: float = 9.0
const CAMERA_STEALTH_DROP:    float = 8.0

# ── POLICE SCORING ────────────────────────────────────────────────────────────
# MODERATE #3 FIX: POLICE_START_BONUS removed — it inflated police performance
# even when idle (54/100 with zero captures). Replaced with PATROL_COVERAGE_BONUS
# (+0.5 per unique tile visited) so active, coverage-seeking police score well
# while idle police score poorly.
const PATROL_COVERAGE_BONUS:  float = 0.5

const CAPTURE_BONUS:          float = 190.0
const DOG_ASSIST_BONUS:       float = 24.0
const CCTV_ASSIST_BONUS:      float = 15.0
const FIRE_ASSIST_BONUS:      float = 20.0
const PRESSURE_PER_SECOND:    float = 2.0

# Escape allowed penalty (reduced so two escapes don't instantly nuke police)
const ESCAPE_ALLOWED_PENALTY: float = -70.0

# Full containment jackpot
const FULL_CONTAINMENT_BONUS: float = 900.0

# Repeat-capture bonus: police gets extra points for catching the same prisoner twice
const REPEAT_CAPTURE_BONUS:   float = 65.0

# ─────────────────────────────────────────────────────────────────────────────

var _agents: Array[Agent] = []
var _exit_rotator: ExitRotator = null
var _dog_npc: DogNPC = null
var _camera_system: CCTVCameraSystem = null

var _escape_order: Array[int] = []
var _base_exit_dist: Dictionary = {}
var _best_progress_cells: Dictionary = {}
var _last_camera_tick: Dictionary = {}
var _capture_count_per_prisoner: Dictionary = {}   # agent_id -> times captured

func setup(agents: Array[Agent], exit_rotator: ExitRotator, dog_npc: DogNPC, camera_system: CCTVCameraSystem) -> void:
	_agents = agents
	_exit_rotator = exit_rotator
	_dog_npc = dog_npc
	_camera_system = camera_system
	_escape_order.clear()
	_base_exit_dist.clear()
	_best_progress_cells.clear()
	_last_camera_tick.clear()
	_capture_count_per_prisoner.clear()

	for agent in _agents:
		_ensure_metrics(agent)
		if agent._role == "police":
			# MODERATE #3 FIX: No start bonus — patrol coverage is earned by moving.
			agent.metrics["patrol_tiles_visited"] = {}
		else:
			var base_dist: int = _closest_exit_distance(agent.grid_pos)
			_base_exit_dist[agent.agent_id] = maxi(1, base_dist)
			_best_progress_cells[agent.agent_id] = 0

	EventBus.agent_escaped.connect(_on_agent_escaped)
	EventBus.agent_captured.connect(_on_agent_captured)
	# MODERATE #2 FIX: timeout is handled separately so capture_count stays clean.
	EventBus.agent_timed_out.connect(_on_agent_timed_out)
	EventBus.agent_blocked_move.connect(_on_agent_blocked_move)
	EventBus.agent_entered_fire.connect(_on_agent_entered_fire)
	EventBus.agent_eliminated_by_fire.connect(_on_agent_eliminated_by_fire)
	EventBus.camera_detection.connect(_on_camera_detection)
	EventBus.dog_engaged_prisoner.connect(_on_dog_engaged_prisoner)

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
	# MODERATE #3 FIX: Award patrol coverage bonus for each unique tile visited.
	# This incentivises active coverage-seeking play over standing still.
	var patrol_tiles: Dictionary = agent.metrics.get("patrol_tiles_visited", {})
	var tile_key: String = str(agent.grid_pos)
	if not patrol_tiles.has(tile_key):
		patrol_tiles[tile_key] = true
		agent.metrics["patrol_tiles_visited"] = patrol_tiles
		_add_score(agent, PATROL_COVERAGE_BONUS, "patrol_coverage")
	if _is_pressuring_prisoner(agent):
		_add_score(agent, PRESSURE_PER_SECOND * TICK_SECONDS, "pressure")

func _on_agent_escaped(agent_id: int) -> void:
	var escaped: Agent = _find_agent(agent_id)
	if escaped == null:
		return
	if not _escape_order.has(agent_id):
		_escape_order.append(agent_id)
	var rank: int = _escape_order.size()
	escaped.metrics["escape_rank"] = rank
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
	prisoner.metrics["captured"] = true
	prisoner.metrics["capture_count"] = int(prisoner.metrics.get("capture_count", 0)) + 1
	_add_score(prisoner, CAPTURE_PENALTY, "captured")
	prisoner.health = maxf(0.0, prisoner.health - CAPTURE_HEALTH_LOSS)
	prisoner.stealth_level = CAPTURE_STEALTH_RESET
	_update_performance(prisoner)

	var police: Agent = _get_police()
	if police != null:
		# CRITICAL #1 FIX: Do NOT independently increment captures_made here.
		# simulation_loop.gd now increments police.capture_count AND sets
		# police.metrics["captures_made"] = police.capture_count synchronously.
		# Reading from police.capture_count ensures a single source of truth.
		# We still update the score and other metrics.
		_add_score(police, CAPTURE_BONUS, "capture_bonus")
		# Repeat-capture bonus
		var prev: int = int(_capture_count_per_prisoner.get(agent_id, 0))
		_capture_count_per_prisoner[agent_id] = prev + 1
		if prev >= 1:
			_add_score(police, REPEAT_CAPTURE_BONUS, "repeat_capture_bonus")
		_update_performance(police)

func _on_agent_timed_out(agent_id: int) -> void:
	# MODERATE #2 FIX: Called instead of _on_agent_captured when time expires.
	# Applies a lighter score penalty and does NOT award the police a capture bonus,
	# because the police did not actively catch this prisoner.
	var prisoner: Agent = _find_agent(agent_id)
	if prisoner == null:
		return
	prisoner.metrics["timed_out"] = true
	_add_score(prisoner, TIMEOUT_PENALTY, "timed_out")
	prisoner.stealth_level = 0.0
	_update_performance(prisoner)
	# Police gets a smaller "containment" reward for keeping prisoners from escaping.
	var police: Agent = _get_police()
	if police != null:
		_add_score(police, CAPTURE_BONUS * 0.40, "timeout_containment")
		_update_performance(police)

func _on_agent_blocked_move(agent_id: int, _from: Vector2i, _target: Vector2i, reason: String) -> void:
	var prisoner: Agent = _find_agent(agent_id)
	if prisoner == null or prisoner._role == "police":
		return
	match reason:
		"unwalkable":
			prisoner.metrics["wall_hits"] = int(prisoner.metrics.get("wall_hits", 0)) + 1
			_add_score(prisoner, WALL_HIT_PENALTY, "wall_hit")
		"locked_door":
			prisoner.metrics["locked_door_hits"] = int(prisoner.metrics.get("locked_door_hits", 0)) + 1
			_add_score(prisoner, WALL_HIT_PENALTY, "locked_door_hit")
		"occupied":
			prisoner.metrics["blocked_by_agent_hits"] = int(prisoner.metrics.get("blocked_by_agent_hits", 0)) + 1
		_:
			pass
	_update_performance(prisoner)

func _on_agent_entered_fire(agent_id: int, _tile: Vector2i) -> void:
	var prisoner: Agent = _find_agent(agent_id)
	if prisoner == null or prisoner._role == "police":
		return
	prisoner.metrics["fire_hits"] = int(prisoner.metrics.get("fire_hits", 0)) + 1
	prisoner.metrics["fire_damage_taken"] = float(prisoner.metrics.get("fire_damage_taken", 0.0)) + float(FireHazard.DAMAGE_PER_TICK)
	_update_performance(prisoner)

func _on_agent_eliminated_by_fire(agent_id: int) -> void:
	var prisoner: Agent = _find_agent(agent_id)
	if prisoner == null or prisoner._role == "police":
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
	if prisoner == null or prisoner._role == "police":
		return
	var tick_now: int = int(detail.get("tick", 0))
	var key: String = str(agent_id)
	var allow_tick: int = int(_last_camera_tick.get(key, -9999)) + 1
	if tick_now < allow_tick:
		return
	_last_camera_tick[key] = tick_now
	_add_score(prisoner, CAMERA_HIT_PENALTY, "camera_detection")
	prisoner.metrics["camera_hits"] = int(prisoner.metrics.get("camera_hits", 0)) + 1
	prisoner.metrics["last_camera_id"] = int(detail.get("camera_id", -1))
	prisoner.stealth_level = clampf(prisoner.stealth_level - CAMERA_STEALTH_DROP, 0.0, 100.0)
	_update_performance(prisoner)

	var police: Agent = _get_police()
	if police != null:
		police.metrics["cctv_assists"] = int(police.metrics.get("cctv_assists", 0)) + 1
		_add_score(police, CCTV_ASSIST_BONUS, "cctv_assist")
		_update_performance(police)
		police.cctv_alert_target = tile
		police.cctv_alert_ticks = 10

func _on_dog_engaged_prisoner(agent_id: int, _duration_ticks: int) -> void:
	var prisoner: Agent = _find_agent(agent_id)
	if prisoner == null or prisoner._role == "police":
		return
	prisoner.metrics["dog_latch_engagements"] = int(prisoner.metrics.get("dog_latch_engagements", 0)) + 1
	var police: Agent = _get_police()
	if police != null:
		police.metrics["dog_assists"] = int(police.metrics.get("dog_assists", 0)) + 1
		_add_score(police, DOG_ASSIST_BONUS, "dog_assist")
		_update_performance(police)

func _update_performance(agent: Agent) -> void:
	var raw: float = float(agent.metrics.get("raw_score", 0.0))
	var perf: float
	if agent._role == "police":
		# CRITICAL #1 FIX: Read captures from agent.capture_count (single source),
		# which simulation_loop.gd increments synchronously. agent.metrics["captures_made"]
		# is kept in sync by simulation_loop as well, but capture_count is authoritative.
		var captures: int     = agent.capture_count
		var dog_assists: int  = int(agent.metrics.get("dog_assists",    0))
		var cctv_assists: int = int(agent.metrics.get("cctv_assists",   0))
		var fire_assists: int = int(agent.metrics.get("fire_assists",   0))
		var escapes: int      = int(agent.metrics.get("escapes_allowed",0))

		# Mission-based hunter score: raw contribution + captures + assists - escapes.
		perf = 30.0 \
			+ 0.055 * maxf(raw, 0.0) \
			+ 9.0   * float(captures) \
			+ 2.5   * float(dog_assists) \
			+ 1.25  * float(cctv_assists) \
			+ 2.0   * float(fire_assists) \
			- 7.0   * float(escapes)

		if captures >= 2:
			perf += 8.0
		elif captures == 1:
			perf += 4.0
	else:
		var best_progress: int = int(agent.metrics.get("best_progress_cells", 0))
		var camera_hits: int   = int(agent.metrics.get("camera_hits", 0))
		var wall_hits: int     = int(agent.metrics.get("wall_hits", 0))
		var fire_hits: int     = int(agent.metrics.get("fire_hits", 0))
		var escape_rank: int   = int(agent.metrics.get("escape_rank", -1))
		var captures_taken: int = int(agent.metrics.get("capture_count", agent.capture_count))

		var escaped_bonus: float = 0.0
		if escape_rank == 1:
			escaped_bonus = 14.0
		elif escape_rank == 2:
			escaped_bonus = 10.0

		perf = 46.0 \
			+ 0.045 * raw \
			+ 0.45  * float(best_progress) \
			+ escaped_bonus \
			+ 0.09  * (agent.health - 50.0) \
			+ 0.07  * (agent.stealth_level - 50.0) \
			- 8.0   * float(captures_taken) \
			- 1.6   * float(camera_hits) \
			- 1.0   * float(wall_hits) \
			- 2.0   * float(fire_hits)
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
		if _manhattan(police.grid_pos, agent.grid_pos) <= 6:
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
	if not agent.metrics.has("locked_door_hits"):
		agent.metrics["locked_door_hits"] = 0
	if not agent.metrics.has("blocked_by_agent_hits"):
		agent.metrics["blocked_by_agent_hits"] = 0
	if not agent.metrics.has("dog_assists"):
		agent.metrics["dog_assists"] = 0
	if not agent.metrics.has("dog_latch_engagements"):
		agent.metrics["dog_latch_engagements"] = 0
	if not agent.metrics.has("captured_while_dog_latched"):
		agent.metrics["captured_while_dog_latched"] = 0
	if not agent.metrics.has("captures_while_dog_latched"):
		agent.metrics["captures_while_dog_latched"] = 0
	if not agent.metrics.has("cctv_assists"):
		agent.metrics["cctv_assists"] = 0
	if not agent.metrics.has("last_camera_id"):
		agent.metrics["last_camera_id"] = -1
	if not agent.metrics.has("fire_hits"):
		agent.metrics["fire_hits"] = 0
	if not agent.metrics.has("fire_damage_taken"):
		agent.metrics["fire_damage_taken"] = 0.0
	if not agent.metrics.has("fire_assists"):
		agent.metrics["fire_assists"] = 0
	if not agent.metrics.has("escapes_allowed"):
		agent.metrics["escapes_allowed"] = 0
	if not agent.metrics.has("captures_made"):
		agent.metrics["captures_made"] = 0
	if not agent.metrics.has("capture_count"):
		agent.metrics["capture_count"] = agent.capture_count
	if not agent.metrics.has("captured"):
		agent.metrics["captured"] = false
	if not agent.metrics.has("escape_rank"):
		agent.metrics["escape_rank"] = -1
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

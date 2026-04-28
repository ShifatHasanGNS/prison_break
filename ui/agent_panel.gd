# UPDATED — visual/UI support and strict typing hardening
extends RefCounted
class_name AgentPanel

const LOG_MAX: int = 5

var agent_id: int = 0
var role: String = ""
var label: String = ""
var ai_label: String = ""
var role_color: Color = Color.WHITE

var health: float = 100.0
var max_health: float = 100.0
var stamina: float = 100.0
var max_stamina: float = 100.0
var display_health: float = 100.0
var display_stamina: float = 100.0

var action_text: String = "-"
var status_text: String = "none"
var is_active: bool = true
var is_escaped: bool = false
var is_eliminated: bool = false
var capture_count: int = 0
var camera_hits: int = 0
var performance_score: float = 0.0
var raw_score: float = 0.0
var stealth: float = 100.0
var alert_level: float = 0.0
var best_progress_cells: int = 0
var dog_zone_time: float = 0.0
var wall_hits: int = 0
var dog_assists: int = 0
var cctv_assists: int = 0
var fire_assists: int = 0
var escapes_allowed: int = 0
var captures_made: int = 0

var candidates: Array = []
var decision_log: Array[String] = []
var grid_pos: Vector2i = Vector2i(-1, -1)
var next_pos: Vector2i = Vector2i(-1, -1)
var decision_kind: String = ""

func setup(agent: Agent) -> void:
	agent_id = agent.agent_id
	role = agent._role
	match role:
		"rusher_red":
			label = "Rusher Red"
			ai_label = "MINIMAX"
			role_color = Color(0.937, 0.267, 0.267)
		"sneaky_blue":
			label = "Sneaky Blue"
			ai_label = "MCTS"
			role_color = Color(0.18, 1.00, 0.92)
		"police":
			label = "Police Hunter"
			ai_label = "FUZZY"
			role_color = Color(1.0, 0.86, 0.24)
		_:
			label = role
			ai_label = "AI"
			role_color = Color.WHITE

	if agent.stats != null:
		max_health = agent.stats.max_health
		max_stamina = agent.stats.max_stamina
	health = agent.health
	stamina = agent.stamina
	display_health = health
	display_stamina = stamina

func update_from_agent(agent: Agent) -> void:
	health = agent.health
	stamina = agent.stamina
	status_text = agent.status_summary()
	is_active = agent.is_active
	grid_pos = agent.grid_pos
	capture_count = agent.capture_count
	camera_hits = int(agent.metrics.get("camera_hits", 0))
	is_escaped = agent.escape_rank > 0
	is_eliminated = agent.elimination_tick >= 0
	raw_score = float(agent.metrics.get("raw_score", 0.0))
	stealth = agent.stealth_level
	alert_level = clampf(float(agent.metrics.get("alert_level", 0.0)), 0.0, 1.0)
	best_progress_cells = int(agent.metrics.get("best_progress_cells", 0))
	dog_zone_time = float(agent.metrics.get("dog_zone_time", 0.0))
	wall_hits = int(agent.metrics.get("wall_hits", 0))
	dog_assists = int(agent.metrics.get("dog_assists", 0))
	cctv_assists = int(agent.metrics.get("cctv_assists", 0))
	fire_assists = int(agent.metrics.get("fire_assists", 0))
	escapes_allowed = int(agent.metrics.get("escapes_allowed", 0))
	captures_made = int(agent.metrics.get("captures_made", agent.metrics.get("captures_inflicted", 0)))
	performance_score = float(agent.metrics.get("performance", 0.0))

func add_log(entry: String) -> void:
	decision_log.push_front(entry)
	if decision_log.size() > LOG_MAX:
		decision_log.resize(LOG_MAX)

func lerp_displays(delta: float) -> void:
	var speed: float = minf(delta * 8.0, 1.0)
	display_health = lerpf(display_health, health, speed)
	display_stamina = lerpf(display_stamina, stamina, speed)

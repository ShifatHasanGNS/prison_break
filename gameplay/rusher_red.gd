# UPDATED — strict typing hardening
extends Agent
class_name RusherRed

func _init() -> void:
	_role = "rusher_red"
	_ai_controller = MinimaxController.new()
	_abilities = [AbilitySprintBurst.new(), AbilityBrawl.new(), AbilityForceDoor.new()]

static func make_stats(id: int) -> AgentStats:
	var s: AgentStats = AgentStats.new()
	s.agent_id = id
	s.max_health = 100.0
	s.max_stamina = 100.0
	s.stealth = 2
	s.base_noise = 6
	s.vision_range = 5
	s.base_speed = 1
	s.sprint_speed = 3
	s.stamina_regen = 5.0
	s.stamina_sprint_cost = 10.0
	return s

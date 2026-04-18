extends Agent
class_name SneakyBlue

func _init() -> void:
	_role = "sneaky_blue"
	_ai_controller = MctsController.new()
	_abilities = [
		AbilityHide.new(),
		AbilitySilentStep.new(),
		AbilityPeek.new(),
	]

static func make_stats(id: int) -> AgentStats:
	var s := AgentStats.new()
	s.agent_id        = id
	s.max_health      = 100.0
	s.max_stamina     = 50.0
	s.stealth         = 9
	s.base_noise      = 1
	s.vision_range    = 8
	s.base_speed      = 1
	s.sprint_speed    = 2
	s.stamina_regen   = 5.0
	s.stamina_sprint_cost = 10.0
	return s

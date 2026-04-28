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
	# MINOR #4 FIX: Raised max_stamina 50→70 and stamina_regen 5.0→7.0.
	# With max_stamina=50 and MOVE_STAMINA_COST=1.0 per tick, Blue exhausted
	# its stamina after ~50 moves (12.5 s), making sprint almost never usable.
	# Regen was 5.0/tick × 0.25s = 1.25/s vs sprint cost of 10 → 8s between
	# sprints. Raising both gives Blue meaningful sprint access during a 60s match.
	s.max_stamina     = 70.0
	s.stealth         = 9
	s.base_noise      = 1
	s.vision_range    = 8
	s.base_speed      = 1
	s.sprint_speed    = 2
	s.stamina_regen   = 7.0
	s.stamina_sprint_cost = 10.0
	return s

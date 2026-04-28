# UPDATED — strict typing hardening
extends Agent
class_name PoliceHunter

func _init() -> void:
	_role = "police"
	_ai_controller = FuzzyController.new()
	_abilities = [AbilitySprintChase.new(), AbilityCapture.new(), AbilityAlertSignal.new()]

func _ready() -> void:
	super._ready()
	if not is_in_group("police"):
		add_to_group("police")
	if OS.is_debug_build():
		print("PoliceHunter groups:", get_groups())

static func make_stats(id: int) -> AgentStats:
	var s: AgentStats = AgentStats.new()
	s.agent_id = id
	s.max_health = 100.0
	s.max_stamina = 75.0
	s.stealth = 5
	s.base_noise = 4
	s.vision_range = 7
	s.base_speed = 2
	s.sprint_speed = 3
	s.stamina_regen = 5.0
	s.stamina_sprint_cost = 10.0
	return s

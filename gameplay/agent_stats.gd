extends Resource
class_name AgentStats

@export var agent_id: int = 0
@export var max_health: float = 100.0
@export var max_stamina: float = 100.0
@export var stealth: int = 5          # 1–10
@export var base_noise: int = 4
@export var vision_range: int = 6
@export var base_speed: int = 1
@export var sprint_speed: int = 2
@export var stamina_regen: float = 5.0
@export var stamina_sprint_cost: float = 10.0
# MINOR #4 FIX: Per-agent move stamina cost. Default 0 means the simulation
# uses the global MOVE_STAMINA_COST constant. Set > 0 to override per-agent
# (e.g. Blue could be tuned to 0.5 for lighter stamina drain on each move).
@export var stamina_move_cost: float = 0.0

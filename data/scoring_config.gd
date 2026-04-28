extends Resource
class_name ScoringConfig
# MODERATE #4 FIX: All scoring tuning constants exposed as @export vars so they
# can be adjusted in the Godot inspector without recompilation.

# Prisoner escape bonuses
@export var first_escape_bonus: float = 300.0
@export var second_escape_bonus: float = 190.0

# Prisoner progress & survival
@export var progress_cell_bonus: float = 6.0
@export var survival_per_second: float = 0.5

# Prisoner hazard penalties
@export var dog_zone_penalty_per_second: float = -12.0
@export var camera_hit_penalty: float = -10.0
@export var wall_hit_penalty: float = -4.0
@export var fire_elimination_penalty: float = -55.0
@export var capture_penalty: float = -75.0
@export var timeout_penalty: float = -35.0

# Police scoring
@export var patrol_coverage_bonus: float = 0.5
@export var capture_bonus: float = 190.0
@export var dog_assist_bonus: float = 24.0
@export var cctv_assist_bonus: float = 15.0
@export var fire_assist_bonus: float = 20.0
@export var pressure_per_second: float = 2.0
@export var escape_allowed_penalty: float = -70.0
@export var full_containment_bonus: float = 900.0
@export var repeat_capture_bonus: float = 65.0

extends Resource
class_name SimulationConfig
# MODERATE #4 FIX: All simulation tuning constants exposed as @export vars so they
# can be adjusted in the Godot inspector without recompilation.

@export var match_duration_seconds: float = 375.0
@export var tick_seconds: float = 0.25
@export var max_captures_before_elimination: int = 3
@export var danger_weight: float = 2.0
@export var wait_stamina_bonus: float = 8.0
@export var move_stamina_cost: float = 1.0
@export var sneak_stamina_cost: float = 2.0
@export var alert_on_bark: float = 0.80
@export var alert_on_fire: float = 0.65
@export var alert_decay_per_second: float = 0.10
@export var alert_camera_scale: float = 0.65

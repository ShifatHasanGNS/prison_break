extends RefCounted
class_name Action

enum Type { MOVE = 0, SPRINT = 1, SNEAK = 2, WAIT = 3, INTERACT = 4, ABILITY_USE = 5 }

var type: int = Type.WAIT
var stamina_cost: float = 0.0
var cooldown_ticks: int = 0
var noise_generated: int = 0
var target_pos: Vector2i = Vector2i.ZERO

var _cooldown_remaining: int = 0

## Override in concrete actions. Returns true if the action succeeded.
func execute(agent: Node2D) -> bool:
	return false

## Returns false while on cooldown.
func is_available(agent: Node2D) -> bool:
	return _cooldown_remaining <= 0

## Call once per tick to count down active cooldown.
func tick_cooldown() -> void:
	if _cooldown_remaining > 0:
		_cooldown_remaining -= 1

func start_cooldown() -> void:
	_cooldown_remaining = cooldown_ticks

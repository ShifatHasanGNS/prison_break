extends RefCounted
class_name Ability

var ability_name: String = ""
var stamina_cost: float = 0.0
var cooldown_ticks: int = 0
var _cooldown_remaining: int = 0

## Returns true when the ability can be triggered right now.
func is_available(agent: Node2D) -> bool:
	return _cooldown_remaining <= 0 and agent.get("stamina") >= stamina_cost

## Attempt to use the ability. Returns true on success.
## context keys: grid, danger_map, all_agents, target_pos (Vector2i)
func use(agent: Node2D, context: Dictionary = {}) -> bool:
	if not is_available(agent):
		return false
	agent.stamina -= stamina_cost
	_cooldown_remaining = cooldown_ticks
	_on_use(agent, context)
	EventBus.emit_signal("agent_action_chosen", agent.get("agent_id"), ability_name)
	return true

## Override in subclass to implement the ability effect.
func _on_use(agent: Node2D, context: Dictionary) -> void:
	pass

## Called every tick by SimulationLoop to count cooldown down.
func tick_cooldown() -> void:
	if _cooldown_remaining > 0:
		_cooldown_remaining -= 1

func get_cooldown_remaining() -> int:
	return _cooldown_remaining

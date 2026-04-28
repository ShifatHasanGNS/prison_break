extends StatusEffect
class_name EffectSpeedBoost

var speed_bonus: int = 2

func _init(bonus: int = 2, duration: int = 3) -> void:
	super._init("speed_boost", duration)
	speed_bonus = bonus

func on_apply(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, true)

func on_remove(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, false)

## Speed bonus is consumed in agent.get_effective_speed() by checking has_status("speed_boost").
## The bonus value is retrieved via agent.get_speed_bonus() or by finding this effect directly.
func apply_tick(agent: Node2D) -> void:
	super.apply_tick(agent)

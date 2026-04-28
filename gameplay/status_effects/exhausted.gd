extends StatusEffect
class_name EffectExhausted

const STAMINA_THRESHOLD: float = 30.0  # effect lifts once stamina exceeds this

func _init() -> void:
	super._init("exhausted", -1)  # condition-based: no fixed duration

func on_apply(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, true)

func on_remove(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, false)

func apply_tick(agent: Node2D) -> void:
	pass  # Speed penalty enforced in action resolution (checks has_status("exhausted"))

## Expires as soon as stamina rises above the threshold.
func is_expired(agent: Node2D) -> bool:
	var stamina: float = agent.get("stamina")
	return stamina > STAMINA_THRESHOLD

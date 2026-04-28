extends StatusEffect
class_name EffectSilentStep

func _init() -> void:
	super._init("silent_step", 1)

func on_apply(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, true)

func on_remove(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, false)

## Next move noise = 0. Checked in action resolution via has_status("silent_step").
func apply_tick(agent: Node2D) -> void:
	super.apply_tick(agent)

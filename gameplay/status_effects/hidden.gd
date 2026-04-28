extends StatusEffect
class_name EffectHidden

# Duration is set by the Hide ability; -1 means indefinite until cancelled.
func _init(duration: int = -1) -> void:
	super._init("hidden", duration)

func on_apply(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, true)

func on_remove(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, false)

func apply_tick(agent: Node2D) -> void:
	# stealth=10 and noise=0 enforced during perception / action-noise calculation
	# by checking agent.has_status("hidden")
	super.apply_tick(agent)

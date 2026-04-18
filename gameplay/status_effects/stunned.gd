extends StatusEffect
class_name EffectStunned

const DEFAULT_DURATION: int = 2

func _init() -> void:
	super._init("stunned", DEFAULT_DURATION)

func on_apply(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, true)

func on_remove(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, false)

func apply_tick(agent: Node2D) -> void:
	# Action skip enforced in _collect_actions(): agent.has_status("stunned") → WAIT
	super.apply_tick(agent)

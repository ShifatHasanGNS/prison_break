extends StatusEffect
class_name EffectDogPinned

const DEFAULT_DURATION: int = 20

var speed_factor: float = 0.5

func _init(duration: int = DEFAULT_DURATION, slow_factor: float = 0.5) -> void:
	super._init("dog_pinned", duration)
	speed_factor = clampf(slow_factor, 0.1, 1.0)

func on_apply(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, true)

func on_remove(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, false)

func apply_tick(agent: Node2D) -> void:
	super.apply_tick(agent)

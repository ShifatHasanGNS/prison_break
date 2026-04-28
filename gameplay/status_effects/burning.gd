extends StatusEffect
class_name EffectBurning

const DAMAGE_PER_TICK: float = 5.0
const NOISE_BONUS: int = 4
const DEFAULT_DURATION: int = 4

func _init() -> void:
	super._init("burning", DEFAULT_DURATION)

func on_apply(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, true)

func on_remove(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, false)

func apply_tick(agent: Node2D) -> void:
	# Deal damage each tick
	var current_hp: float = agent.get("health")
	agent.set("health", maxf(current_hp - DAMAGE_PER_TICK, 0.0))
	super.apply_tick(agent)

extends StatusEffect
class_name EffectDetected

const DANGER_RADIUS: int = 8   # danger added in this tile radius
const DEFAULT_DURATION: int = 5

func _init() -> void:
	super._init("detected", DEFAULT_DURATION)

func on_apply(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, true)

func on_remove(agent: Node2D) -> void:
	EventBus.emit_signal("agent_status_changed", agent.get("agent_id"), effect_name, false)

func apply_tick(agent: Node2D) -> void:
	# Danger-radius contribution is injected by SimulationLoop._rebuild_maps()
	# which checks for this effect on all agents each tick. No direct map access here.
	super.apply_tick(agent)

extends Ability
class_name AbilityAlertSignal

# Police: +6 danger in radius-3 for 5 ticks, triggers dog alert

const DANGER_RADIUS: int = 3
const DANGER_VALUE: float = 6.0
const EFFECT_DURATION: int = 5

var _ticks_active: int = 0
var _signal_pos: Vector2i = Vector2i(-1, -1)

func _init() -> void:
	ability_name = "alert_signal"
	stamina_cost = 20.0
	cooldown_ticks = 6

func _on_use(agent: Node2D, context: Dictionary) -> void:
	_signal_pos = agent.get("grid_pos")
	_ticks_active = EFFECT_DURATION

	var danger_map = context.get("danger_map", null)
	if danger_map != null:
		_apply_danger(danger_map)

	# Notify dog system (Phase 9) via EventBus — use dog ID 0, not the police agent's ID
	EventBus.emit_signal("dog_state_changed", 0, "ALERT")

	print("  [%s] Alert Signal at %s! +%.0f danger r=%d for %d ticks (stamina=%.0f, cd=%d)" % [
		agent.get("_role"), _signal_pos, DANGER_VALUE, DANGER_RADIUS,
		EFFECT_DURATION, agent.stamina, cooldown_ticks
	])

func tick_cooldown() -> void:
	super.tick_cooldown()
	if _ticks_active > 0:
		_ticks_active -= 1

## Called by SimulationLoop each tick while the signal is active to re-apply danger.
func apply_danger_tick(danger_map) -> void:
	if _ticks_active > 0 and _signal_pos.x >= 0:
		_apply_danger(danger_map)

func is_signal_active() -> bool:
	return _ticks_active > 0

func _apply_danger(danger_map) -> void:
	for dy in range(-DANGER_RADIUS, DANGER_RADIUS + 1):
		for dx in range(-DANGER_RADIUS, DANGER_RADIUS + 1):
			danger_map.add(_signal_pos + Vector2i(dx, dy), DANGER_VALUE)

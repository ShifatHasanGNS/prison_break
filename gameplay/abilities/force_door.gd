extends Ability
class_name AbilityForceDoor

# Red: break locked door in 1 tick (vs 3 for others), noise+8

const FORCE_NOISE: int = 8

func _init() -> void:
	ability_name = "force_door"
	stamina_cost = 10.0
	cooldown_ticks = 3

func _on_use(agent: Node2D, context: Dictionary) -> void:
	var target_pos: Vector2i = context.get("target_pos", agent.get("grid_pos"))

	# Phase 9 will handle actual door state change via DoorInteractable.
	# Emit signal so door system (Phase 9) can react.
	EventBus.emit_signal("door_state_changed", target_pos, "force_break")

	print("  [%s] Force Door at %s! noise+%d (stamina=%.0f, cd=%d)" % [
		agent.get("_role"), target_pos, FORCE_NOISE, agent.stamina, cooldown_ticks
	])

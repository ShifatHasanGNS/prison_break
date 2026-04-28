extends Ability
class_name AbilityPeek

# Blue: reveal tiles around a corner without moving, stamina-5

const PEEK_RADIUS: int = 3

func _init() -> void:
	ability_name = "peek"
	stamina_cost = 5.0
	cooldown_ticks = 3

func _on_use(agent: Node2D, context: Dictionary) -> void:
	var grid = context.get("grid", null)
	var target_pos: Vector2i = context.get("target_pos", agent.get("grid_pos"))

	# Phase 12 (VisionOverlay) will render revealed tiles.
	var revealed: int = 0
	if grid != null:
		for dy in range(-PEEK_RADIUS, PEEK_RADIUS + 1):
			for dx in range(-PEEK_RADIUS, PEEK_RADIUS + 1):
				var check_pos: Vector2i = target_pos + Vector2i(dx, dy)
				if grid.is_walkable(check_pos):
					revealed += 1

	print("  [%s] Peek around %s — %d tiles revealed (stamina=%.0f, cd=%d)" % [
		agent.get("_role"), target_pos, revealed, agent.stamina, cooldown_ticks
	])

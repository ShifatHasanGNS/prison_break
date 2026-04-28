extends Ability
class_name AbilitySprintChase

# Police: speed+2 for 4 ticks, stamina-15

const SPEED_BONUS: int = 2
const DURATION_TICKS: int = 4

func _init() -> void:
	ability_name = "sprint_chase"
	stamina_cost = 15.0
	cooldown_ticks = 5

func _on_use(agent: Node2D, _context: Dictionary) -> void:
	agent.apply_effect(EffectSpeedBoost.new(SPEED_BONUS, DURATION_TICKS))
	print("  [%s] Sprint Chase! speed+%d for %d ticks (stamina=%.0f, cd=%d)" % [
		agent.get("_role"), SPEED_BONUS, DURATION_TICKS, agent.stamina, cooldown_ticks
	])

extends Ability
class_name AbilitySprintBurst

# Red: speed+2 for 3 ticks, stamina-20, noise+4

const SPEED_BONUS: int = 2
const DURATION_TICKS: int = 3
const EXTRA_NOISE: int = 4

func _init() -> void:
	ability_name = "sprint_burst"
	stamina_cost = 20.0
	cooldown_ticks = 5

func _on_use(agent: Node2D, _context: Dictionary) -> void:
	agent.apply_effect(EffectSpeedBoost.new(SPEED_BONUS, DURATION_TICKS))
	# Noise burst is handled at resolve time by checking has_status("speed_boost") in the action
	print("  [%s] Sprint Burst! speed+%d for %d ticks (stamina=%.0f, cd=%d)" % [
		agent.get("_role"), SPEED_BONUS, DURATION_TICKS, agent.stamina, cooldown_ticks
	])

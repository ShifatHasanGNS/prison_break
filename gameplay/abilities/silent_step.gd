extends Ability
class_name AbilitySilentStep

# Blue: next move costs 0 noise, stamina-5

func _init() -> void:
	ability_name = "silent_step"
	stamina_cost = 5.0
	cooldown_ticks = 2

func _on_use(agent: Node2D, _context: Dictionary) -> void:
	agent.apply_effect(EffectSilentStep.new())
	print("  [%s] Silent Step! next move noise=0 (stamina=%.0f, cd=%d)" % [
		agent.get("_role"), agent.stamina, cooldown_ticks
	])

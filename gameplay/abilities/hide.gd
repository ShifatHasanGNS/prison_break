extends Ability
class_name AbilityHide

# Blue: grants Hidden status for HIDE_DURATION ticks, stamina-10

const HIDE_DURATION: int = 5

func _init() -> void:
	ability_name = "hide"
	stamina_cost = 10.0
	cooldown_ticks = 8

func _on_use(agent: Node2D, _context: Dictionary) -> void:
	agent.apply_effect(EffectHidden.new(HIDE_DURATION))
	print("  [%s] Hide! stealth=10 noise=0 for %d ticks (stamina=%.0f, cd=%d)" % [
		agent.get("_role"), HIDE_DURATION, agent.stamina, cooldown_ticks
	])

extends Ability
class_name AbilityBrawl

# Red: stun adjacent agent 2 ticks, stamina-15

const STUN_DURATION: int = 2

func _init() -> void:
	ability_name = "brawl"
	stamina_cost = 15.0
	cooldown_ticks = 4

func _on_use(agent: Node2D, context: Dictionary) -> void:
	var all_agents: Array = context.get("all_agents", [])

	var hit: bool = false
	for other in all_agents:
		if other.get("agent_id") == agent.get("agent_id"):
			continue
		if not other.get("is_active"):
			continue
		var dist: Vector2i = other.get("grid_pos") - agent.get("grid_pos")
		if absi(dist.x) <= 1 and absi(dist.y) <= 1:
			other.apply_effect(EffectStunned.new())
			hit = true
			print("  [%s] Brawl → stunned [%s] for %d ticks (stamina=%.0f)" % [
				agent.get("_role"), other.get("_role"), STUN_DURATION, agent.stamina
			])
			break

	if not hit:
		print("  [%s] Brawl — no adjacent target (stamina=%.0f)" % [
			agent.get("_role"), agent.stamina
		])

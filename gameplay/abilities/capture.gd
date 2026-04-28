extends Ability
class_name AbilityCapture

# Police: immobilise adjacent prisoner, ends game for that agent

func _init() -> void:
	ability_name = "capture"
	stamina_cost = 0.0
	cooldown_ticks = 1

func _on_use(agent: Node2D, context: Dictionary) -> void:
	var all_agents: Array = context.get("all_agents", [])

	for other in all_agents:
		if other.get("_role") == "police":
			continue
		if not other.get("is_active"):
			continue
		if other.capture_cooldown_ticks > 0:
			continue   # post-respawn immunity
		var dist: Vector2i = other.get("grid_pos") - agent.get("grid_pos")
		if absi(dist.x) <= 1 and absi(dist.y) <= 1:
			other.capture_count += 1
			EventBus.emit_signal("agent_captured", other.get("agent_id"))
			SoundManager.play("capture")
			# Always respawn — prisoners never disappear from the game
			other.respawn()
			SoundManager.play("alert")
			print("  [%s] CAPTURED [%s] (capture #%d) — respawning" % [
				agent.get("_role"), other.get("_role"), other.capture_count
			])
			return

	print("  [%s] Capture — no adjacent prisoner" % agent.get("_role"))

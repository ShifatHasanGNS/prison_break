extends Node2D
class_name SimulationLoop

const DANGER_WEIGHT: float = 2.0
const TICK_LIMIT: int = 1500
const MAX_CAPTURES_BEFORE_ELIMINATION: int = 3
const CYCLE_SUMMARY_INTERVAL: int = 3
const WAIT_STAMINA_BONUS: float = 8.0
const MOVE_STAMINA_COST: float = 1.0
const SNEAK_STAMINA_COST: float = 2.0

var _grid: GridEngine = null
var _map_data: Dictionary = {}

var _danger_map: DangerMap = DangerMap.new()
var _cost_map: CostMap = CostMap.new()
var _agents: Array[Agent] = []

var _exit_rotator: ExitRotator = null
var _fire_hazard: FireHazard = null
var _dog_npc: DogNPC = null
var _doors: Array = []
var _camera_system: CCTVCameraSystem = null
var _scoring_system: ScoringSystem = null

var _pending_actions: Array = []
var replay_exporter = null

var _game_over: bool = false
var _current_tick: int = 0
var _total_actions: int = 0
var _escaped_agents: Array[int] = []
var _captured_agents: Array[int] = []
var _eliminated_agents: Array[int] = []
var _escape_tick: int = 0
var _cycle_summaries: Array = []
var _latest_cycle_summary: Dictionary = {}

func setup(grid: GridEngine, map_data: Dictionary) -> void:
	_grid = grid
	_map_data = map_data

	if not EventBus.danger_map_updated.is_connected(_on_danger_map_updated):
		EventBus.danger_map_updated.connect(_on_danger_map_updated)
	if not EventBus.exit_activated.is_connected(_on_exit_activated):
		EventBus.exit_activated.connect(_on_exit_activated)
	if not EventBus.exit_deactivated.is_connected(_on_exit_deactivated):
		EventBus.exit_deactivated.connect(_on_exit_deactivated)

	_spawn_agents()
	_setup_exit_rotator()
	_setup_hazards()
	_setup_cameras()
	_setup_scoring()
	_rebuild_maps()
	EventBus.emit_signal("simulation_started")

func _spawn_agents() -> void:
	var red := RusherRed.new()
	red.setup(0, _map_data["red_spawn"], RusherRed.make_stats(0))
	add_child(red)

	var blue := SneakyBlue.new()
	blue.setup(1, _map_data["blue_spawn"], SneakyBlue.make_stats(1))
	add_child(blue)

	var police := PoliceHunter.new()
	police.setup(2, _map_data["police_spawn"], PoliceHunter.make_stats(2))
	add_child(police)

	_agents = [police, red, blue]
	print("Agents spawned: %s@%s  %s@%s  %s@%s" % [
		red._role, red.grid_pos,
		blue._role, blue.grid_pos,
		police._role, police.grid_pos,
	])

func _setup_exit_rotator() -> void:
	_exit_rotator = ExitRotator.new()
	add_child(_exit_rotator)
	_exit_rotator.setup(_map_data.get("exits", []))

func _setup_hazards() -> void:
	_fire_hazard = FireHazard.new()
	_fire_hazard.setup(_map_data.get("fire_tiles", []), _grid)
	add_child(_fire_hazard)

	_dog_npc = DogNPC.new()
	_dog_npc.setup(_map_data.get("dog_waypoints", []), _grid, _map_data.get("exits", []), _doors)
	add_child(_dog_npc)

	for pos in _map_data.get("door_tiles", []):
		var door := DoorInteractable.new()
		door.setup(pos as Vector2i, _grid)
		_doors.append(door)

func _setup_cameras() -> void:
	_camera_system = CCTVCameraSystem.new()
	_camera_system.setup(_map_data.get("camera_tiles", []), _grid)
	add_child(_camera_system)

func _setup_scoring() -> void:
	_scoring_system = ScoringSystem.new()
	_scoring_system.setup(_agents, _exit_rotator, _dog_npc, _camera_system)
	add_child(_scoring_system)

func on_tick(n: int) -> void:
	if _game_over:
		return
	_current_tick = n
	_update_perception()
	_rebuild_maps() # fresh CCTV/dog danger for this planning phase
	_collect_actions()
	_resolve_actions()
	_update_hazards()
	_rebuild_maps() # post-move state for overlays + next tick
	if _scoring_system != null:
		_scoring_system.tick()
	_check_wins()
	_record_metrics()
	_record_cycle_summary_if_needed()
	_record_snapshot(n)

func _update_perception() -> void:
	if _camera_system != null:
		_camera_system.tick(_agents, _current_tick)
		var hot_count: int = 0
		for cam_state in _camera_system.get_camera_states():
			if not Array(cam_state.get("visible_targets", [])).is_empty():
				hot_count += 1
		for agent in _agents:
			if agent._role == "police":
				agent.metrics["alert_level"] = clampf(float(hot_count) / 2.0, 0.0, 1.0)

func _collect_actions() -> void:
	_pending_actions.clear()
	for agent: Agent in _agents:
		if not agent.is_active:
			_pending_actions.append(null)
			continue
		if agent.has_status("stunned"):
			_pending_actions.append(null)
			EventBus.emit_signal("agent_action_chosen", agent.agent_id, "STUNNED")
			continue
		if agent._ai_controller == null:
			_pending_actions.append(null)
			continue
		var action: Action = agent._ai_controller.choose_action(
			agent, _grid, _cost_map, _exit_rotator, _agents
		)
		_pending_actions.append(action)
		_total_actions += 1
		var action_name: String = _action_type_name(action.type) if action != null else "WAIT"
		EventBus.emit_signal("agent_action_chosen", agent.agent_id, action_name)

func _resolve_actions() -> void:
	for i in range(_agents.size()):
		var agent: Agent = _agents[i]
		var action: Action = _pending_actions[i] if i < _pending_actions.size() else null
		if action == null or not agent.is_active:
			continue

		if action.type == Action.Type.MOVE or action.type == Action.Type.SPRINT or action.type == Action.Type.SNEAK:
			_resolve_movement(agent, action)
		elif action.type == Action.Type.INTERACT:
			for door in _doors:
				if door.grid_pos == action.target_pos:
					door.interact(agent)
					print("  [%s] interact door at %s" % [agent._role, action.target_pos])
					break
		elif action.type == Action.Type.ABILITY_USE:
			_resolve_ability(agent, action)
		elif action.type == Action.Type.WAIT:
			agent.record_wait()
			if agent.stats != null:
				agent.stamina = minf(agent.stats.max_stamina, agent.stamina + WAIT_STAMINA_BONUS)

func _resolve_movement(agent: Agent, action: Action) -> void:
	var target: Vector2i = action.target_pos
	if target == agent.grid_pos:
		agent.record_wait()
		EventBus.emit_signal("agent_blocked_move", agent.agent_id, agent.grid_pos, target, "same_tile")
		return
	for other: Agent in _agents:
		if other.agent_id != agent.agent_id and other.is_active and other.grid_pos == target:
			print("  [%s] blocked at %s → WAIT" % [agent._role, target])
			agent.record_wait()
			EventBus.emit_signal("agent_blocked_move", agent.agent_id, agent.grid_pos, target, "occupied")
			return
	if not _grid.is_walkable(target):
		print("  [%s] target %s unwalkable → WAIT" % [agent._role, target])
		agent.record_wait()
		EventBus.emit_signal("agent_blocked_move", agent.agent_id, agent.grid_pos, target, "unwalkable")
		return
	for door in _doors:
		if door.grid_pos == target and not door.is_passable():
			print("  [%s] blocked by locked door at %s → WAIT" % [agent._role, target])
			agent.record_wait()
			EventBus.emit_signal("agent_blocked_move", agent.agent_id, agent.grid_pos, target, "locked_door")
			return

	if action.type == Action.Type.SPRINT:
		if not _can_agent_sprint(agent):
			print("  [%s] sprint denied (stamina/dog zone)" % [agent._role])
			agent.record_wait()
			return
		agent.record_sprint()
		var sprint_cost := agent.stats.stamina_sprint_cost if agent.stats != null else 10.0
		agent.stamina = maxf(0.0, agent.stamina - sprint_cost)
	elif action.type == Action.Type.SNEAK:
		agent.stamina = maxf(0.0, agent.stamina - SNEAK_STAMINA_COST)
	else:
		agent.stamina = maxf(0.0, agent.stamina - MOVE_STAMINA_COST)

	agent.move_to(target)
	print("  [%s] moved to %s" % [agent._role, target])

func _can_agent_sprint(agent: Agent) -> bool:
	var required := agent.stats.stamina_sprint_cost if agent.stats != null else 10.0
	if agent.stamina < required:
		return false
	if _dog_npc != null and _manhattan(agent.grid_pos, _dog_npc.grid_pos) <= 2:
		return false
	return true

func _resolve_ability(agent: Agent, action: Action) -> void:
	var context: Dictionary = {
		"all_agents": _agents,
		"grid": _grid,
		"cost_map": _cost_map,
		"danger_map": _danger_map,
		"exit_rotator": _exit_rotator,
		"target_pos": action.target_pos,
	}
	for ability in agent._abilities:
		if ability.is_available(agent):
			if ability.use(agent, context):
				agent.record_ability_use()
				print("  [%s] used ability %s" % [agent._role, ability.ability_name])
				break

func _update_hazards() -> void:
	for agent: Agent in _agents:
		agent.tick_status_effects()
		agent.tick_ability_cooldowns()

	for door in _doors:
		door.tick()
	if _dog_npc != null:
		_dog_npc.tick(_agents)
	if _fire_hazard != null:
		_fire_hazard.tick(_agents)

func _rebuild_maps() -> void:
	if _grid == null:
		return
	_danger_map.reset()

	for agent: Agent in _agents:
		if agent.has_status("detected"):
			for dy in range(-EffectDetected.DANGER_RADIUS, EffectDetected.DANGER_RADIUS + 1):
				for dx in range(-EffectDetected.DANGER_RADIUS, EffectDetected.DANGER_RADIUS + 1):
					_danger_map.add(agent.grid_pos + Vector2i(dx, dy), 1.0)

	for agent: Agent in _agents:
		for ability in agent._abilities:
			if ability is AbilityAlertSignal:
				ability.apply_danger_tick(_danger_map)

	if _fire_hazard != null:
		_fire_hazard.seed_danger(_danger_map)
	if _dog_npc != null:
		_dog_npc.seed_danger(_danger_map)
	if _camera_system != null:
		_camera_system.seed_danger(_danger_map)

	if _exit_rotator != null:
		for ex: Vector2i in _exit_rotator.get_exits():
			if _exit_rotator.is_active_exit(ex):
				_danger_map.set_danger(ex, 0.0)
			else:
				_danger_map.set_danger(ex, 5.0)

	_cost_map.rebuild(_grid, _danger_map, DANGER_WEIGHT)
	EventBus.emit_signal("danger_map_updated")

func _check_wins() -> void:
	if _game_over:
		return

	if _exit_rotator != null:
		var active_exit: Vector2i = _exit_rotator.get_active_exit()
		for agent: Agent in _agents:
			if agent._role == "police" or not agent.is_active:
				continue
			if agent.grid_pos == active_exit and not (agent.agent_id in _escaped_agents):
				agent.is_active = false
				agent.escape_rank = _escaped_agents.size() + 1
				_escaped_agents.append(agent.agent_id)
				if _escape_tick <= 0:
					_escape_tick = _current_tick
				EventBus.emit_signal("agent_escaped", agent.agent_id)
				print("  *** [%s] ESCAPED at tick %d (rank %d) ***" % [agent._role, _current_tick, agent.escape_rank])
				SoundManager.play("escape")

	if _exit_rotator != null:
		for agent: Agent in _agents:
			if agent._role == "police" or not agent.is_active:
				continue
			if _exit_rotator.is_decoy_exit(agent.grid_pos) and not agent.has_status("detected"):
				agent.apply_effect(EffectDetected.new())
				print("  [%s] decoy penalty at %s" % [agent._role, agent.grid_pos])

	for prisoner: Agent in _agents:
		if prisoner._role == "police" or not prisoner.is_active:
			continue
		if prisoner.health <= 0.0:
			prisoner.is_active = false
			prisoner.elimination_tick = _current_tick
			if not (prisoner.agent_id in _eliminated_agents):
				_eliminated_agents.append(prisoner.agent_id)
			EventBus.emit_signal("agent_eliminated", prisoner.agent_id)
			EventBus.emit_signal("agent_eliminated_by_fire", prisoner.agent_id)
			print("  *** [%s] eliminated by fire ***" % prisoner._role)

	for police_agent: Agent in _agents:
		if police_agent._role != "police" or not police_agent.is_active:
			continue
		for prisoner: Agent in _agents:
			if prisoner._role == "police" or not prisoner.is_active:
				continue
			if prisoner.capture_cooldown_ticks > 0:
				continue
			var d: int = _manhattan(police_agent.grid_pos, prisoner.grid_pos)
			if d <= 1:
				prisoner.capture_count += 1
				_captured_agents.append(prisoner.agent_id)
				police_agent.metrics["captures_inflicted"] = int(police_agent.metrics.get("captures_inflicted", 0)) + 1
				EventBus.emit_signal("agent_captured", prisoner.agent_id)
				SoundManager.play("capture")
				if prisoner.capture_count >= MAX_CAPTURES_BEFORE_ELIMINATION:
					prisoner.is_active = false
					prisoner.elimination_tick = _current_tick
					if not (prisoner.agent_id in _eliminated_agents):
						_eliminated_agents.append(prisoner.agent_id)
					EventBus.emit_signal("agent_eliminated", prisoner.agent_id)
					print("  *** [%s] eliminated after %d captures ***" % [prisoner._role, prisoner.capture_count])
				else:
					prisoner.respawn()
					SoundManager.play("alert")
					print("  *** [%s] caught (capture #%d) — respawning ***" % [prisoner._role, prisoner.capture_count])
				break

	if _all_prisoners_resolved():
		_finalize_game()
	elif _current_tick >= TICK_LIMIT:
		_finalize_game()

func _all_prisoners_resolved() -> bool:
	for agent in _agents:
		if agent._role == "police":
			continue
		if agent.is_active:
			return false
	return true

func _record_metrics() -> void:
	for agent in _agents:
		agent.metrics["camera_hits"] = int(agent.metrics.get("camera_hits", 0))
		agent.metrics["wall_hits"] = int(agent.metrics.get("wall_hits", 0))

func _record_cycle_summary_if_needed() -> void:
	if _current_tick <= 0 or _current_tick % CYCLE_SUMMARY_INTERVAL != 0:
		return
	var summary_agents: Array = []
	for agent in _agents:
		summary_agents.append({
			"id": agent.agent_id,
			"role": agent._role,
			"health": snappedf(agent.health, 0.1),
			"stamina": snappedf(agent.stamina, 0.1),
			"captures": agent.capture_count,
			"camera_hits": int(agent.metrics.get("camera_hits", 0)),
			"performance": snappedf(float(agent.metrics.get("performance", 0.0)), 0.1),
			"escaped": agent.agent_id in _escaped_agents,
			"eliminated": agent.agent_id in _eliminated_agents,
			"active": agent.is_active,
		})
	var summary := {
		"cycle_index": int(_current_tick / CYCLE_SUMMARY_INTERVAL),
		"tick": _current_tick,
		"escaped": _escaped_agents.duplicate(),
		"eliminated": _eliminated_agents.duplicate(),
		"captured_count": _captured_agents.size(),
		"agent_metrics": summary_agents,
		"camera_events": _camera_system.get_recent_events(4) if _camera_system != null else [],
	}
	_cycle_summaries.append(summary)
	if _cycle_summaries.size() > 24:
		_cycle_summaries.pop_front()
	_latest_cycle_summary = summary
	EventBus.emit_signal("cycle_summary_generated", summary)

func _finalize_game() -> void:
	if _game_over:
		return
	_game_over = true
	var escaped: int = _escaped_agents.size()
	var eliminated: int = _eliminated_agents.size()
	var outcome: String = "timeout"
	if escaped > 0:
		outcome = "prisoners_win"
	elif eliminated >= 2:
		outcome = "police_wins"

	print("=== GAME OVER: %s (tick %d) escaped=%d eliminated=%d captured=%d ===" % [
		outcome, _current_tick, escaped, eliminated, _captured_agents.size()
	])
	if _scoring_system != null:
		_scoring_system.apply_final_bonuses(outcome, escaped)
	if outcome == "prisoners_win":
		SoundManager.play("game_over_win")
	else:
		SoundManager.play("game_over_lose")

	var agent_results: Array = []
	for agent: Agent in _agents:
		agent_results.append({
			"id": agent.agent_id,
			"role": agent._role,
			"health": agent.health,
			"stealth": agent.stealth_level,
			"stamina": agent.stamina,
			"is_active": agent.is_active,
			"escape_rank": agent.escape_rank,
			"elimination_tick": agent.elimination_tick,
			"capture_cooldown_ticks": agent.capture_cooldown_ticks,
			"moves": int(agent.metrics.get("moves", 0)),
			"waits": int(agent.metrics.get("waits", 0)),
			"abilities": int(agent.metrics.get("abilities", 0)),
			"sprints": int(agent.metrics.get("sprints", 0)),
			"raw_score": snappedf(float(agent.metrics.get("raw_score", 0.0)), 0.1),
			"escaped": agent.agent_id in _escaped_agents,
			"captured": agent.agent_id in _captured_agents,
			"eliminated": agent.agent_id in _eliminated_agents,
			"captures": agent.capture_count,
			"captures_made": int(agent.metrics.get("captures_made", agent.metrics.get("captures_inflicted", 0))),
			"camera_hits": int(agent.metrics.get("camera_hits", 0)),
			"wall_hits": int(agent.metrics.get("wall_hits", 0)),
			"best_progress_cells": int(agent.metrics.get("best_progress_cells", 0)),
			"dog_zone_time": snappedf(float(agent.metrics.get("dog_zone_time", 0.0)), 0.1),
			"dog_assists": int(agent.metrics.get("dog_assists", 0)),
			"cctv_assists": int(agent.metrics.get("cctv_assists", 0)),
			"fire_assists": int(agent.metrics.get("fire_assists", 0)),
			"escapes_allowed": int(agent.metrics.get("escapes_allowed", 0)),
			"alert_level": snappedf(float(agent.metrics.get("alert_level", 0.0)), 0.01),
			"performance": snappedf(float(agent.metrics.get("performance", 0.0)), 0.1),
			"metrics": agent.metrics.duplicate(true),
		})

	var result: Dictionary = {
		"outcome": outcome,
		"escape_tick": _escape_tick,
		"escaped_count": escaped,
		"captured_count": _captured_agents.size(),
		"eliminated_count": eliminated,
		"total_actions": _total_actions,
		"total_ticks": _current_tick,
		"agent_results": agent_results,
		"cycle_summaries": _cycle_summaries.duplicate(true),
		"camera_stats": _camera_system.get_agent_detection_counts() if _camera_system != null else {},
		"camera_logs": _camera_system.get_recent_events(12) if _camera_system != null else [],
	}
	EventBus.emit_signal("simulation_ended", result)

func is_game_over() -> bool:
	return _game_over

func get_exit_rotator() -> ExitRotator:
	return _exit_rotator

func get_camera_system() -> CCTVCameraSystem:
	return _camera_system

func get_scoring_system() -> ScoringSystem:
	return _scoring_system

func get_cycle_summaries() -> Array:
	return _cycle_summaries

func _record_snapshot(n: int) -> void:
	if replay_exporter == null:
		return
	var dog_pos := _dog_npc.grid_pos if _dog_npc != null else Vector2i(-1, -1)
	var dog_state := _dog_npc.get_state_name() if _dog_npc != null else "NONE"
	var active_exit := _exit_rotator.get_active_exit() if _exit_rotator != null else Vector2i(-1, -1)
	var cameras := _camera_system.get_camera_states() if _camera_system != null else []
	replay_exporter.record_snapshot(n, _agents, dog_pos, dog_state, active_exit, cameras)

func _action_type_name(t: int) -> String:
	match t:
		Action.Type.MOVE: return "MOVE"
		Action.Type.SPRINT: return "SPRINT"
		Action.Type.SNEAK: return "SNEAK"
		Action.Type.WAIT: return "WAIT"
		Action.Type.INTERACT: return "INTERACT"
		Action.Type.ABILITY_USE: return "ABILITY"
		_: return "UNKNOWN"

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _on_danger_map_updated() -> void:
	var peak_pos := Vector2i(-1, -1)
	var peak_val: float = 0.0
	for pos: Vector2i in _danger_map.get_all():
		var d: float = _danger_map.get_danger(pos)
		if d > peak_val:
			peak_val = d
			peak_pos = pos
	if peak_val > 0.0:
		print("Danger peak: %.1f @ %s" % [peak_val, peak_pos])

func _on_exit_activated(_tile: Vector2i) -> void:
	for agent in _agents:
		agent.on_exit_changed(_tile)

func _on_exit_deactivated(_tile: Vector2i) -> void:
	pass

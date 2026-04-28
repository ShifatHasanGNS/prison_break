extends Node2D
class_name SimulationLoop

# Pipeline order per CLAUDE.md:
# update_perception → collect_actions → resolve_actions →
# update_hazards → rebuild_maps → check_wins → record_metrics → record_snapshot

const DANGER_WEIGHT: float = 2.0

var _grid: GridEngine = null
var _map_data: Dictionary = {}

var _danger_map: DangerMap = DangerMap.new()
var _cost_map: CostMap = CostMap.new()

# Agents in action-resolution priority order: Police → Red → Blue
var _agents: Array[Agent] = []

var _exit_rotator: ExitRotator = null

# Phase 9 hazards
var _fire_hazard: FireHazard = null
var _dog_npc: DogNPC = null
var _doors: Array = []  # Array of DoorInteractable

# Pending actions keyed by agent index (matches _agents order)
var _pending_actions: Array = []

# Phase 15 -- optional replay capture (set by game.gd before first tick)
var replay_exporter = null   # ReplayExporter

var _game_over       : bool       = false
var _current_tick    : int        = 0
var _total_actions   : int        = 0
var _escaped_agents  : Array[int] = []
var _captured_agents : Array[int] = []
var _escape_tick     : int        = 0

const TICK_LIMIT: int = 1500

# -------------------------------------------------------------------------

func setup(grid: GridEngine, map_data: Dictionary) -> void:
	_grid = grid
	_map_data = map_data

	EventBus.danger_map_updated.connect(_on_danger_map_updated)
	EventBus.exit_activated.connect(_on_exit_activated)
	EventBus.exit_deactivated.connect(_on_exit_deactivated)

	_spawn_agents()
	_setup_exit_rotator()
	_setup_hazards()

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

	# Resolution priority: Police → Red → Blue
	_agents = [police, red, blue]

	print("Agents spawned: %s@%s  %s@%s  %s@%s" % [
		red._role,    red.grid_pos,
		blue._role,   blue.grid_pos,
		police._role, police.grid_pos,
	])

func _setup_exit_rotator() -> void:
	_exit_rotator = ExitRotator.new()
	add_child(_exit_rotator)
	_exit_rotator.setup(_map_data.get("exits", []))

func _setup_hazards() -> void:
	# Fire hazard — fixed tiles, no spread
	_fire_hazard = FireHazard.new()
	_fire_hazard.setup(_map_data.get("fire_tiles", []), _grid)
	add_child(_fire_hazard)

	# Dog NPC — patrols waypoints, hunts by noise/sight
	_dog_npc = DogNPC.new()
	_dog_npc.setup(_map_data.get("dog_waypoints", []), _grid, _map_data.get("exits", []), _doors)
	add_child(_dog_npc)

	# Door interactables — locked by default, block movement + LOS
	for pos in _map_data.get("door_tiles", []):
		var door := DoorInteractable.new()
		door.setup(pos as Vector2i, _grid)
		_doors.append(door)

	print("Hazards: %d fire tiles, %d dog waypoints, %d doors" % [
		_map_data.get("fire_tiles", []).size(),
		_map_data.get("dog_waypoints", []).size(),
		_doors.size()
	])

# -------------------------------------------------------------------------

func on_tick(n: int) -> void:
	if _game_over:
		return
	_current_tick = n
	print("Tick %d" % n)
	_update_perception()
	_collect_actions()
	_resolve_actions()
	_update_hazards()
	_rebuild_maps()
	_check_wins()
	_record_metrics()
	_record_snapshot(n)

# --- Pipeline ---

func _update_perception() -> void:
	pass  # Phase 7+: FOV / noise detection

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
		var action_name: String = _action_type_name(action.type)
		EventBus.emit_signal("agent_action_chosen", agent.agent_id, action_name)

func _resolve_actions() -> void:
	var occupied: Dictionary = {}
	for agent: Agent in _agents:
		if agent.is_active:
			occupied[agent.grid_pos] = agent.agent_id

	# Resolve in priority order: Police(0) → Red(1) → Blue(2)
	for i in range(_agents.size()):
		var agent: Agent = _agents[i]
		var action: Action = _pending_actions[i] if i < _pending_actions.size() else null
		if action == null or not agent.is_active:
			continue

		if action.type == Action.Type.MOVE or action.type == Action.Type.SPRINT or action.type == Action.Type.SNEAK:
			var target: Vector2i = action.target_pos

			# Collision: another agent occupies target
			var blocked: bool = false
			for other: Agent in _agents:
				if other.agent_id != agent.agent_id and other.is_active and other.grid_pos == target:
					blocked = true
					break
			if blocked:
				print("  [%s] blocked at %s → WAIT" % [agent._role, target])
				continue

			if not _grid.is_walkable(target):
				print("  [%s] target %s unwalkable → WAIT" % [agent._role, target])
				continue

			# Door check: locked doors block movement
			var door_blocked: bool = false
			for door in _doors:
				if door.grid_pos == target and not door.is_passable():
					door_blocked = true
					print("  [%s] blocked by locked door at %s → WAIT" % [agent._role, target])
					break
			if door_blocked:
				continue

			occupied.erase(agent.grid_pos)
			agent.move_to(target)
			occupied[target] = agent.agent_id

			# Stamina cost by action type
			if action.type == Action.Type.SPRINT:
				var cost: float = agent.stats.stamina_sprint_cost if agent.stats != null else 10.0
				agent.stamina = maxf(0.0, agent.stamina - cost)
			elif action.type == Action.Type.SNEAK:
				agent.stamina = maxf(0.0, agent.stamina - 3.0)

			print("  [%s] moved to %s" % [agent._role, target])

		elif action.type == Action.Type.INTERACT:
			# Door interaction at target_pos
			for door in _doors:
				if door.grid_pos == action.target_pos:
					door.interact(agent)
					print("  [%s] interact door at %s" % [agent._role, action.target_pos])
					break

		elif action.type == Action.Type.ABILITY_USE:
			# Find and execute the ability specified in the action
			var context: Dictionary = {
				"all_agents": _agents,
				"grid": _grid,
				"cost_map": _cost_map,
				"danger_map": _danger_map,
				"exit_rotator": _exit_rotator,
				"target_pos": action.target_pos,
			}
			# Try each ability — the AI chose ABILITY_USE so one should fire
			for ability in agent._abilities:
				if ability.is_available(agent):
					ability.use(agent, context)
					print("  [%s] used ability %s" % [agent._role, ability.ability_name])
					break

		elif action.type == Action.Type.WAIT:
			pass

func _update_hazards() -> void:
	for agent: Agent in _agents:
		agent.tick_status_effects()
		agent.tick_ability_cooldowns()

	# Tick door states (opening animation)
	for door in _doors:
		door.tick()

	# Dog NPC tick — state machine + movement
	if _dog_npc != null:
		_dog_npc.tick(_agents)

	# Fire damage — applied to agents standing on fire tiles
	if _fire_hazard != null:
		_fire_hazard.tick(_agents)

func _rebuild_maps() -> void:
	if _grid == null:
		return

	_danger_map.reset()

	# Detected-effect danger halos
	for agent: Agent in _agents:
		if agent.has_status("detected"):
			for dy in range(-EffectDetected.DANGER_RADIUS, EffectDetected.DANGER_RADIUS + 1):
				for dx in range(-EffectDetected.DANGER_RADIUS, EffectDetected.DANGER_RADIUS + 1):
					_danger_map.add(agent.grid_pos + Vector2i(dx, dy), 1.0)

	# AlertSignal persistent danger (Police ability)
	for agent: Agent in _agents:
		for ability in agent._abilities:
			if ability is AbilityAlertSignal:
				ability.apply_danger_tick(_danger_map)

	# Fire static danger (+8 on tile, +4 adjacent)
	if _fire_hazard != null:
		_fire_hazard.seed_danger(_danger_map)

	# Dog dynamic danger (radius based on state)
	if _dog_npc != null:
		_dog_npc.seed_danger(_danger_map)

	# Seed danger around active exit (low-cost) and decoys (+5)
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

	# ── Escape check: FIRST prisoner on active exit wins team immediately ──
	if _exit_rotator != null:
		var active_exit: Vector2i = _exit_rotator.get_active_exit()
		for agent: Agent in _agents:
			if agent._role == "police" or not agent.is_active:
				continue
			if agent.grid_pos == active_exit:
				agent.is_active = false
				_escaped_agents.append(agent.agent_id)
				_escape_tick = _current_tick
				EventBus.emit_signal("agent_escaped", agent.agent_id)
				print("  *** [%s] ESCAPED — PRISONERS WIN at tick %d ***" % [agent._role, _current_tick])
				SoundManager.play("escape")
				_finalize_game()
				return

	# ── Decoy-exit penalty ──────────────────────────────────────────────
	if _exit_rotator != null:
		for agent: Agent in _agents:
			if agent._role == "police" or not agent.is_active:
				continue
			if _exit_rotator.is_decoy_exit(agent.grid_pos):
				if not agent.has_status("detected"):
					agent.apply_effect(EffectDetected.new())
					print("  [%s] decoy penalty at %s" % [agent._role, agent.grid_pos])

	# ── Capture check: police adjacent ≤1 to prisoner ──────────────────
	# Prisoners are NEVER eliminated — they always respawn.
	# capture_cooldown_ticks prevents immediate re-capture after a respawn.
	for police_agent: Agent in _agents:
		if police_agent._role != "police" or not police_agent.is_active:
			continue
		for prisoner: Agent in _agents:
			if prisoner._role == "police" or not prisoner.is_active:
				continue
			if prisoner.capture_cooldown_ticks > 0:
				continue   # still in post-respawn immunity window
			var d: int = absi(police_agent.grid_pos.x - prisoner.grid_pos.x) \
			           + absi(police_agent.grid_pos.y - prisoner.grid_pos.y)
			if d <= 1:
				prisoner.capture_count += 1
				_captured_agents.append(prisoner.agent_id)
				EventBus.emit_signal("agent_captured", prisoner.agent_id)
				SoundManager.play("capture")
				# Always respawn — prisoners never disappear from the game
				prisoner.respawn()
				SoundManager.play("alert")
				print("  *** [%s] caught (capture #%d) — respawning ***" % [
					prisoner._role, prisoner.capture_count
				])
				break   # one capture per police per tick

	# ── Tick-limit check ─────────────────────────────────────────────────
	if _current_tick >= TICK_LIMIT:
		_finalize_game()

func _finalize_game() -> void:
	if _game_over:
		return
	_game_over = true

	var escaped: int = _escaped_agents.size()
	var captured: int = _captured_agents.size()

	# Prisoners are never eliminated — they always respawn.
	# Outcome: prisoners_win = any escape; police_wins = timeout with captures, no escapes;
	# timeout = tick limit with no escapes and no captures.
	var outcome: String
	if escaped > 0:
		outcome = "prisoners_win"
	elif captured > 0:
		outcome = "police_wins"
	else:
		outcome = "timeout"

	print("=== GAME OVER: %s (tick %d) escaped=%d captured=%d ===" % [
		outcome, _current_tick, escaped, captured
	])

	if outcome == "prisoners_win":
		SoundManager.play("game_over_win")
	else:
		SoundManager.play("game_over_lose")

	# Build per-agent summary for results screen
	var agent_results: Array = []
	for agent: Agent in _agents:
		agent_results.append({
			"id"     : agent.agent_id,
			"role"   : agent._role,
			"health" : agent.health,
			"stamina": agent.stamina,
			"escaped": agent.agent_id in _escaped_agents,
			"captured": agent.agent_id in _captured_agents,
		})

	var result: Dictionary = {
		"outcome"        : outcome,
		"escape_tick"    : _escape_tick,
		"escaped_count"  : escaped,
		"captured_count" : captured,
		"total_actions"  : _total_actions,
		"total_ticks"    : _current_tick,
		"agent_results"  : agent_results,
	}
	EventBus.emit_signal("simulation_ended", result)

func is_game_over() -> bool:
	return _game_over

func get_exit_rotator() -> ExitRotator:
	return _exit_rotator

func _record_metrics() -> void:
	pass  # Metrics collected by BenchmarkRunner via simulation_ended result dict

func _record_snapshot(n: int) -> void:
	if replay_exporter == null:
		return
	var dog_pos := _dog_npc.grid_pos if _dog_npc != null else Vector2i(-1, -1)
	var dog_state := _dog_npc.get_state_name() if _dog_npc != null else "NONE"
	var active_exit := _exit_rotator.get_active_exit() if _exit_rotator != null else Vector2i(-1, -1)
	replay_exporter.record_snapshot(n, _agents, dog_pos, dog_state, active_exit)

func _action_type_name(t: int) -> String:
	match t:
		Action.Type.MOVE: return "MOVE"
		Action.Type.SPRINT: return "SPRINT"
		Action.Type.SNEAK: return "SNEAK"
		Action.Type.WAIT: return "WAIT"
		Action.Type.INTERACT: return "INTERACT"
		Action.Type.ABILITY_USE: return "ABILITY"
		_: return "UNKNOWN"

# --- EventBus listeners ---

func _on_danger_map_updated() -> void:
	var peak_pos := Vector2i(-1, -1)
	var peak_val: float = 0.0
	for pos: Vector2i in _danger_map.get_all():
		var d: float = _danger_map.get_danger(pos)
		if d > peak_val:
			peak_val = d
			peak_pos = pos
	if peak_pos.x >= 0:
		print("  DangerMap peak: %s  danger=%.1f  cost=%.1f" % [
			peak_pos, peak_val, _cost_map.get_cost(peak_pos)
		])

func _on_exit_activated(new_exit: Vector2i) -> void:
	print("  EventBus → exit_activated %s" % new_exit)
	for agent: Agent in _agents:
		if agent._role != "police":
			agent.on_exit_changed(new_exit)
		if agent._ai_controller is MinimaxController:
			agent._ai_controller.clear_cache()

func _on_exit_deactivated(old_exit: Vector2i) -> void:
	print("  EventBus → exit_deactivated %s" % old_exit)

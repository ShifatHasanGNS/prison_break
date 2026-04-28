extends RefCounted
class_name AIDecisionRecorder

const MAX_HISTORY_PER_AGENT: int = 36

var _tick: int = 0
var _agents_by_id: Dictionary = {}
var _history_by_id: Dictionary = {}
var _last_action_by_id: Dictionary = {}

var _exit_rotator: ExitRotator = null
var _dog_npc: DogNPC = null
var _camera_system: CCTVCameraSystem = null
var _fire_hazard: FireHazard = null

func setup(
		agents: Array[Agent],
		exit_rotator: ExitRotator,
		dog_npc: DogNPC,
		camera_system: CCTVCameraSystem,
		fire_hazard: FireHazard) -> void:
	_exit_rotator = exit_rotator
	_dog_npc = dog_npc
	_camera_system = camera_system
	_fire_hazard = fire_hazard
	_agents_by_id.clear()
	_history_by_id.clear()
	_last_action_by_id.clear()
	_tick = 0
	for agent: Agent in agents:
		_agents_by_id[agent.agent_id] = agent
		_history_by_id[agent.agent_id] = []

	if not EventBus.tick_ended.is_connected(_on_tick_ended):
		EventBus.tick_ended.connect(_on_tick_ended)
	if not EventBus.agent_action_chosen.is_connected(_on_agent_action_chosen):
		EventBus.agent_action_chosen.connect(_on_agent_action_chosen)
	if not EventBus.minimax_decision.is_connected(_on_minimax_decision):
		EventBus.minimax_decision.connect(_on_minimax_decision)
	if not EventBus.mcts_decision.is_connected(_on_mcts_decision):
		EventBus.mcts_decision.connect(_on_mcts_decision)
	if not EventBus.fuzzy_decision.is_connected(_on_fuzzy_decision):
		EventBus.fuzzy_decision.connect(_on_fuzzy_decision)

func _on_tick_ended(n: int) -> void:
	_tick = n

func _on_agent_action_chosen(id: int, action: String) -> void:
	_last_action_by_id[id] = action

func _on_minimax_decision(id: int, candidates: Array, chosen: Dictionary) -> void:
	var agent: Agent = _agent_from_id(id)
	if agent == null:
		return
	var chosen_tile: Vector2i = Vector2i(chosen.get("pos", agent.grid_pos))
	var candidate_nodes: Array = []
	var best_score: float = -INF
	var worst_score: float = INF
	for i in range(mini(candidates.size(), 5)):
		var c: Dictionary = Dictionary(candidates[i])
		var tile: Vector2i = Vector2i(c.get("pos", agent.grid_pos))
		var score: float = float(c.get("score", 0.0))
		best_score = maxf(best_score, score)
		worst_score = minf(worst_score, score)
		var is_chosen: bool = tile == chosen_tile
		var police_resp: Array = Array(c.get("police_responses", []))
		candidate_nodes.append({
			"action": _infer_action(agent.grid_pos, tile),
			"tile": tile,
			"score": score,
			"risk": _risk_label(_estimate_risk(agent, tile)),
			"chosen": is_chosen,
			"children": [],
			"police_responses": police_resp,
		})

	var entry: Dictionary = _make_common_entry(agent, "Minimax", chosen_tile)
	entry["chosen_action"] = _infer_action(agent.grid_pos, chosen_tile)
	entry["chosen_score"] = float(chosen.get("score", 0.0))
	entry["candidate_count"] = candidates.size()
	entry["branch_count"] = candidate_nodes.size()
	entry["score_span"] = {
		"best": snappedf(best_score, 0.01),
		"worst": snappedf(worst_score, 0.01),
	}
	entry["risk_snapshot"] = _risk_snapshot(agent, chosen_tile)
	entry["candidates"] = candidate_nodes
	var minimax_reason: String = str(chosen.get("reason", "")).strip_edges()
	if minimax_reason == "":
		minimax_reason = _minimax_reason_fallback(agent, chosen_tile, float(chosen.get("score", 0.0)))
	entry["reason"] = minimax_reason
	entry["pruned_branches"] = int(chosen.get("pruned_branches", 0))
	entry["evaluated_nodes"] = int(chosen.get("evaluated_nodes", candidate_nodes.size()))
	entry["search_depth"] = int(chosen.get("search_depth", 4))
	entry["pruned_note"] = "α-β pruned %d branches (evaluated %d)" % [int(chosen.get("pruned_branches", 0)), int(chosen.get("evaluated_nodes", candidate_nodes.size()))]
	_append_entry(id, entry)

func _on_mcts_decision(id: int, root_visits: int, candidates: Array, chosen: Dictionary) -> void:
	var agent: Agent = _agent_from_id(id)
	if agent == null:
		return
	var chosen_tile: Vector2i = Vector2i(chosen.get("pos", agent.grid_pos))
	var candidate_nodes: Array = []
	var best_reward: float = -INF
	var best_visits: int = 0
	for i in range(mini(candidates.size(), 5)):
		var c: Dictionary = Dictionary(candidates[i])
		var tile: Vector2i = Vector2i(c.get("pos", agent.grid_pos))
		var visits: int = int(c.get("visits", 0))
		var avg_score: float = float(c.get("avg_score", 0.0))
		var danger_score: float = _estimate_risk(agent, tile)
		best_reward = maxf(best_reward, avg_score)
		best_visits = maxi(best_visits, visits)
		# Store UCT breakdown so results screen can show exploit vs explore bars
		var uct_total: float = float(c.get("uct", 0.0))
		var uct_exploit: float = avg_score
		var uct_explore: float = maxf(uct_total - uct_exploit, 0.0)
		# Infer rollout outcome and a human-readable summary from the avg_score.
		# avg_score near 1.0 = escaped quickly; near 0.0 = caught; middle = timed out.
		# dist_exit is used to estimate how far from exit this branch ends.
		var dist_exit_tiles: int = int(c.get("dist_exit", -1))
		if dist_exit_tiles < 0:
			dist_exit_tiles = _estimate_exit_dist(tile)
		var rollout_outcome: String
		var rollout_summary: String
		if avg_score >= 0.85:
			rollout_outcome = "escaped"
			var steps_est: int = maxi(1, int((1.0 - avg_score) / 0.015 + 1.5))
			rollout_summary = "Escaped in ~%d steps (exit ~%d tiles)" % [steps_est, dist_exit_tiles]
		elif avg_score <= 0.12:
			rollout_outcome = "caught"
			rollout_summary = "Caught before reaching exit (%d tiles away)" % dist_exit_tiles
		else:
			rollout_outcome = "timed_out"
			rollout_summary = "Timed out, ~%d tiles from exit (reward %.2f)" % [dist_exit_tiles, avg_score]
		candidate_nodes.append({
			"action": _infer_action(agent.grid_pos, tile),
			"tile": tile,
			"visits": visits,
			"avg_reward": avg_score,
			"ucb": uct_total,
			"uct_exploit": uct_exploit,
			"uct_explore": uct_explore,
			"uct_total": uct_total,
			"danger": _risk_label(danger_score),
			"chosen": tile == chosen_tile,
			"rollout_summary": rollout_summary,
			"rollout_outcome": rollout_outcome,
		})

	var entry: Dictionary = _make_common_entry(agent, "MCTS", chosen_tile)
	entry["chosen_action"] = _infer_action(agent.grid_pos, chosen_tile)
	entry["chosen_tile"] = chosen_tile
	entry["candidate_count"] = candidates.size()
	entry["rollouts"] = root_visits
	entry["branch_count"] = candidate_nodes.size()
	entry["best_reward"] = snappedf(best_reward, 0.01)
	entry["best_visits"] = best_visits
	entry["chosen_visits"] = int(chosen.get("visits", 0))
	entry["candidates"] = candidate_nodes
	var mcts_reason: String = str(chosen.get("reason", "")).strip_edges()
	if mcts_reason == "":
		mcts_reason = _mcts_reason_fallback(chosen_tile, int(chosen.get("visits", 0)), best_visits, root_visits)
	entry["reason"] = mcts_reason
	_append_entry(id, entry)

func _on_fuzzy_decision(id: int, inputs: Dictionary, rule_activations: Array, output: String, chosen_pos: Vector2i) -> void:
	var agent: Agent = _agent_from_id(id)
	if agent == null:
		return
	var target_id: int = int(inputs.get("target_id", -1))
	var target_agent: Agent = _agent_from_id(target_id)
	var target_name: String = _agent_name(target_agent)
	var selected_tile: Vector2i = chosen_pos if chosen_pos != Vector2i(-1, -1) else agent.grid_pos

	var rules: Array = []
	for i in range(mini(rule_activations.size(), 6)):
		var rule_dict: Dictionary = Dictionary(rule_activations[i])
		rules.append({
			"label": str(rule_dict.get("rule", "rule")),
			"strength": float(rule_dict.get("strength", 0.0)),
		})

	var red_agent: Agent = _agent_by_role("rusher_red")
	var blue_agent: Agent = _agent_by_role("sneaky_blue")
	var red_distance: int = _distance_between(agent, red_agent)
	var blue_distance: int = _distance_between(agent, blue_agent)
	var red_exit_distance: int = _exit_distance_for_agent(red_agent)
	var blue_exit_distance: int = _exit_distance_for_agent(blue_agent)
	var red_stealth: float = _stealth_for_agent(red_agent)
	var blue_stealth: float = _stealth_for_agent(blue_agent)
	var cctv_confidence: float = clampf(float(inputs.get("cctv_hint_conf", 0.0)), 0.0, 1.0)
	var alert_level: float = clampf(float(agent.metrics.get("alert_level", 0.0)), 0.0, 1.0)

	var red_target_score: float = _target_score(red_distance, red_exit_distance, red_stealth, cctv_confidence)
	var blue_target_score: float = _target_score(blue_distance, blue_exit_distance, blue_stealth, cctv_confidence)

	var fuzzy_inputs: Dictionary = {
		"red_distance": red_distance,
		"blue_distance": blue_distance,
		"red_exit_distance": red_exit_distance,
		"blue_exit_distance": blue_exit_distance,
		"red_stealth": int(round(red_stealth)),
		"blue_stealth": int(round(blue_stealth)),
		"alert_level": int(round(alert_level * 100.0)),
		"cctv_confidence": snappedf(cctv_confidence, 0.01),
	}

	var entry: Dictionary = _make_common_entry(agent, "Fuzzy", selected_tile)
	entry["chosen_behavior"] = output.to_upper()
	entry["chosen_target"] = target_name
	entry["target_agent_id"] = target_id
	entry["target_agent"] = target_name
	entry["target_scores"] = {
		"red": snappedf(red_target_score, 0.01),
		"blue": snappedf(blue_target_score, 0.01),
	}
	entry["comparison"] = {
		"red": {
			"distance_to_police": red_distance,
			"distance_to_exit": red_exit_distance,
			"stealth": int(round(red_stealth)),
			"score": snappedf(red_target_score, 0.01),
		},
		"blue": {
			"distance_to_police": blue_distance,
			"distance_to_exit": blue_exit_distance,
			"stealth": int(round(blue_stealth)),
			"score": snappedf(blue_target_score, 0.01),
		},
		"winner": target_name,
	}
	# MAJOR #2 FIX: Merge the rich fuzzy scores from fuzzy_controller.gd (passed via
	# inputs) into the stored entry so results_screen can draw the real police decision
	# tree. Keys like chase_score, intercept_score, investigate_score, patrol_score,
	# red_target_score, blue_target_score are now available for tree rendering.
	var merged_inputs: Dictionary = fuzzy_inputs.duplicate()
	for key in inputs.keys():
		merged_inputs[key] = inputs[key]
	entry["inputs"] = merged_inputs
	entry["scores"] = {
		"red_target_score": snappedf(float(inputs.get("red_target_score", red_target_score)), 0.01),
		"blue_target_score": snappedf(float(inputs.get("blue_target_score", blue_target_score)), 0.01),
	}
	entry["rules"] = rules
	entry["rule_count"] = rules.size()
	var fuzzy_reason: String = str(inputs.get("target_reason", "")).strip_edges()
	if fuzzy_reason == "":
		var chosen_target_score: float = red_target_score
		if target_name == "Sneaky Blue":
			chosen_target_score = blue_target_score
		fuzzy_reason = _fuzzy_reason_fallback(output, target_name, chosen_target_score)
	entry["reason"] = fuzzy_reason
	_append_entry(id, entry)

func _minimax_reason_fallback(agent: Agent, chosen_tile: Vector2i, chosen_score: float) -> String:
	var action: String = _infer_action(agent.grid_pos, chosen_tile)
	var risk: String = _risk_label(_estimate_risk(agent, chosen_tile))
	return "%s toward %s (score %.2f, risk %s)" % [action, str(chosen_tile), chosen_score, risk]

func _mcts_reason_fallback(chosen_tile: Vector2i, chosen_visits: int, best_visits: int, root_visits: int) -> String:
	var confidence: float = 0.0
	if root_visits > 0:
		confidence = float(chosen_visits) / float(root_visits)
	return "Selected %s with %d/%d visits (best branch %d, confidence %.0f%%)" % [str(chosen_tile), chosen_visits, root_visits, best_visits, confidence * 100.0]

func _fuzzy_reason_fallback(output: String, target_name: String, target_score: float) -> String:
	return "%s behavior favored %s (priority %.2f)" % [output.to_upper(), target_name, target_score]

func _make_common_entry(agent: Agent, algorithm: String, chosen_tile: Vector2i) -> Dictionary:
	var police_distance: int = _nearest_police_distance(agent)
	var visible_threats: int = _visible_threat_count(agent.agent_id)
	var risk_data: Dictionary = _risk_snapshot(agent, chosen_tile)
	var entry: Dictionary = {
		"tick": _tick,
		"agent_id": agent.agent_id,
		"agent_name": _agent_name(agent),
		"algorithm": algorithm,
		"current_tile": agent.grid_pos,
		"chosen_tile": chosen_tile,
		"chosen_action": str(_last_action_by_id.get(agent.agent_id, _infer_action(agent.grid_pos, chosen_tile))),
		"visible_threats": visible_threats,
		"exit_distance": _exit_distance_for_agent(agent),
		"police_distance": police_distance,
		"dog_risk": int(risk_data.get("dog_distance", -1)),
		"fire_risk": bool(risk_data.get("fire_on_tile", false)),
		"cctv_risk": bool(risk_data.get("cctv_visible", false)),
		"risk_level": str(risk_data.get("risk_level", "LOW")),
	}
	return entry

func _append_entry(agent_id: int, entry: Dictionary) -> void:
	var history: Array = _history_by_id.get(agent_id, [])
	history.append(entry)
	if history.size() > MAX_HISTORY_PER_AGENT:
		history.pop_front()
	_history_by_id[agent_id] = history

func export_for_result() -> Dictionary:
	var by_role: Dictionary = {
		"rusher_red": _build_role_export("rusher_red", "MINIMAX"),
		"sneaky_blue": _build_role_export("sneaky_blue", "MCTS / MONTE CARLO"),
		"police": _build_role_export("police", "FUZZY"),
	}
	var counts: Dictionary = {}
	for id_key in _history_by_id.keys():
		var hist: Array = _history_by_id[id_key]
		counts[str(id_key)] = hist.size()
	return {
		"tick": _tick,
		"decision_counts": counts,
		"by_role": by_role,
	}

func _build_role_export(role: String, algorithm_name: String) -> Dictionary:
	var agent: Agent = _agent_by_role(role)
	if agent == null:
		return {
			"agent_id": -1,
			"agent_name": role,
			"algorithm": algorithm_name,
			"decision_count": 0,
			"final_decision": {},
			"selected_decision": {},
			"selected_decision_note": "No decisions recorded",
			"timeline": [],
		}
	var history: Array = _history_by_id.get(agent.agent_id, [])
	var final_decision: Dictionary = history[history.size() - 1] if not history.is_empty() else {}
	var selected_decision: Dictionary = _pick_meaningful_decision(history)
	var selected_note: String = ""
	if selected_decision.is_empty():
		selected_note = "No meaningful decision recorded"
	elif final_decision == selected_decision:
		selected_note = "Final decision"
	else:
		selected_note = "Last meaningful decision: T%d" % int(selected_decision.get("tick", -1))
	var timeline: Array = []
	var from_index: int = maxi(0, history.size() - 8)
	for i in range(from_index, history.size()):
		timeline.append(history[i])
	return {
		"agent_id": agent.agent_id,
		"agent_name": _agent_name(agent),
		"algorithm": algorithm_name,
		"decision_count": history.size(),
		"final_decision": final_decision,
		"selected_decision": selected_decision,
		"selected_decision_note": selected_note,
		"timeline": timeline,
	}

func _pick_meaningful_decision(history: Array) -> Dictionary:
	if history.is_empty():
		return {}
	for i in range(history.size() - 1, -1, -1):
		var item: Dictionary = Dictionary(history[i])
		var candidates: Array = Array(item.get("candidates", []))
		if candidates.size() >= 2:
			return item
		if str(item.get("algorithm", "")) == "Fuzzy" and not Array(item.get("rules", [])).is_empty():
			return item
	return Dictionary(history[history.size() - 1])

func _agent_from_id(agent_id: int) -> Agent:
	var value: Variant = _agents_by_id.get(agent_id, null)
	return value as Agent

func _agent_by_role(role: String) -> Agent:
	for value in _agents_by_id.values():
		var agent: Agent = value as Agent
		if agent != null and agent._role == role:
			return agent
	return null

func _agent_name(agent: Agent) -> String:
	if agent == null:
		return "Unknown"
	match agent._role:
		"rusher_red":
			return "Rusher Red"
		"sneaky_blue":
			return "Sneaky Blue"
		"police":
			return "Police Hunter"
		_:
			return agent._role

func _infer_action(from_tile: Vector2i, to_tile: Vector2i) -> String:
	if to_tile == from_tile:
		return "WAIT"
	var d: Vector2i = to_tile - from_tile
	if d.x > 0:
		return "MOVE_RIGHT"
	if d.x < 0:
		return "MOVE_LEFT"
	if d.y > 0:
		return "MOVE_DOWN"
	if d.y < 0:
		return "MOVE_UP"
	return "MOVE"

func _estimate_exit_dist(tile: Vector2i) -> int:
	# Manhattan distance to the active exit via _exit_rotator.
	if _exit_rotator == null:
		return 99
	var ae: Vector2i = _exit_rotator.get_active_exit()
	if ae.x < 0:
		return 99
	return absi(tile.x - ae.x) + absi(tile.y - ae.y)

func _estimate_risk(agent: Agent, tile: Vector2i) -> float:
	var score: float = 0.0
	var dog_distance: int = _dog_distance(tile)
	if dog_distance >= 0 and dog_distance <= 2:
		score += 1.0
	if _is_fire_tile(tile):
		score += 1.0
	if _is_camera_visible_for_agent(tile, agent.agent_id):
		score += 0.8
	return score

func _risk_snapshot(agent: Agent, tile: Vector2i) -> Dictionary:
	var risk_value: float = _estimate_risk(agent, tile)
	return {
		"dog_distance": _dog_distance(tile),
		"fire_on_tile": _is_fire_tile(tile),
		"cctv_visible": _is_camera_visible_for_agent(tile, agent.agent_id),
		"risk_level": _risk_label(risk_value),
	}

func _risk_label(v: float) -> String:
	if v >= 2.0:
		return "HIGH"
	if v >= 1.0:
		return "MED"
	return "LOW"

func _visible_threat_count(agent_id: int) -> int:
	if _camera_system == null:
		return 0
	var count: int = 0
	var states: Array = _camera_system.get_camera_states()
	for state_variant in states:
		var state: Dictionary = Dictionary(state_variant)
		var visible_targets: Array = Array(state.get("visible_targets", []))
		if visible_targets.has(agent_id):
			count += 1
	return count

func _exit_distance_for_agent(agent: Agent) -> int:
	if agent == null or _exit_rotator == null:
		return -1
	var active_exit: Vector2i = _exit_rotator.get_active_exit()
	return _manhattan(agent.grid_pos, active_exit)

func _nearest_police_distance(agent: Agent) -> int:
	if agent == null:
		return -1
	var best: int = 9999
	for value in _agents_by_id.values():
		var other: Agent = value as Agent
		if other == null or other._role != "police" or not other.is_active:
			continue
		best = mini(best, _manhattan(agent.grid_pos, other.grid_pos))
	if best == 9999:
		return -1
	return best

func _distance_between(a: Agent, b: Agent) -> int:
	if a == null or b == null:
		return -1
	return _manhattan(a.grid_pos, b.grid_pos)

func _stealth_for_agent(agent: Agent) -> float:
	if agent == null:
		return 0.0
	return agent.stealth_level

func _dog_distance(tile: Vector2i) -> int:
	if _dog_npc == null:
		return -1
	return _manhattan(tile, _dog_npc.grid_pos)

func _is_fire_tile(tile: Vector2i) -> bool:
	if _fire_hazard == null:
		return false
	var fire_tiles: Array = _fire_hazard.get_fire_tiles()
	for fire_tile_variant in fire_tiles:
		var fire_tile: Vector2i = fire_tile_variant
		if fire_tile == tile:
			return true
	return false

func _is_camera_visible_for_agent(tile: Vector2i, agent_id: int) -> bool:
	if _camera_system == null:
		return false
	var states: Array = _camera_system.get_camera_states()
	for state_variant in states:
		var state: Dictionary = Dictionary(state_variant)
		var visible_targets: Array = Array(state.get("visible_targets", []))
		if visible_targets.has(agent_id):
			return true
		var scan_pos: Vector2i = Vector2i(state.get("pos", Vector2i(-1, -1)))
		if scan_pos == tile and visible_targets.has(agent_id):
			return true
	return false

func _target_score(distance_to_police: int, distance_to_exit: int, stealth: float, cctv_confidence: float) -> float:
	var distance_term: float = 1.0 / (1.0 + maxf(1.0, float(distance_to_police)))
	var exit_term: float = 1.0 / (1.0 + maxf(1.0, float(distance_to_exit)))
	var low_stealth_term: float = clampf((100.0 - stealth) / 100.0, 0.0, 1.0)
	var score: float = distance_term * 0.35 + exit_term * 0.35 + low_stealth_term * 0.20 + cctv_confidence * 0.10
	return clampf(score, 0.0, 1.0)

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

extends AIController
class_name FuzzyController

var _config: FuzzyConfig = null
var _grid: Node = null
var _cost_map: RefCounted = null
var _exit_rotator: Node = null
var _all_agents: Array = []
var _occupied: Dictionary = {}

# Target commitment / memory
var current_target_id: int = -1
var target_lock_ticks: int = 0
var last_seen_pos_by_agent: Dictionary = {}
var last_seen_tick_by_agent: Dictionary = {}
var _decision_tick: int = 0

# Soft CCTV hint
var _cctv_hint: Dictionary = {
	"agent_id": -1,
	"tile": Vector2i(-1, -1),
	"tick": -99999,
	"confidence": 0.0,
}

# Patrol target cache
var _patrol_target: Vector2i = Vector2i(-1, -1)
var _patrol_refresh_tick: int = -99999

const TARGET_LOCK_DURATION_TICKS: int = 5
const TARGET_SWITCH_MARGIN: float = 2.0
const CCTV_HINT_MAX_AGE_TICKS: int = 4
const CCTV_HINT_REACHED_RADIUS: int = 1
const CCTV_HIGH_CONFIDENCE: float = 0.72
const PATROL_REFRESH_TICKS: int = 4
const INTERCEPT_AHEAD_MIN: int = 2
const INTERCEPT_AHEAD_MAX: int = 4
const CHASE_SPRINT_RANGE: int = 4
const TARGET_SWITCH_RATIO: float = 1.12

func _init() -> void:
	_config = load("res://data/ai/fuzzy_config.tres") as FuzzyConfig
	if _config == null:
		_config = FuzzyConfig.new()

# ─── CRITICAL #1 FIX: ALL membership constants now read from _config ──────────
# No more hardcoded duplicates. _config is the single source of truth.
func _near_full()          -> float: return _config.dist_close
func _near_zero()          -> float: return _config.dist_near_zero
func _medium_low()         -> float: return _config.dist_medium_low
func _medium_peak()        -> float: return _config.dist_medium_peak
func _medium_high()        -> float: return _config.dist_medium_high
func _far_zero()           -> float: return _config.dist_far_zero
func _far_full()           -> float: return _config.dist_far
func _alert_suspicious()   -> float: return _config.alert_suspicious
func _alert_alarmed()      -> float: return _config.alert_alarmed

# Exit-threat membership constants. Escape urgency is 0..10:
# 0 = prisoner is not close to escaping, 10 = prisoner is at/near active exit.
func _exit_low_full()      -> float: return _config.exit_low_full
func _exit_low_zero()      -> float: return _config.exit_low_zero
func _exit_medium_low()    -> float: return _config.exit_medium_low
func _exit_medium_peak()   -> float: return _config.exit_medium_peak
func _exit_medium_high()   -> float: return _config.exit_medium_high
func _exit_high_zero()     -> float: return _config.exit_high_zero
func _exit_high_full()     -> float: return _config.exit_high_full

# CCTV-confidence membership constants. CCTV confidence is 0..1.
func _cctv_weak_full()     -> float: return _config.cctv_weak_full
func _cctv_weak_zero()     -> float: return _config.cctv_weak_zero
func _cctv_medium_low()    -> float: return _config.cctv_medium_low
func _cctv_medium_peak()   -> float: return _config.cctv_medium_peak
func _cctv_medium_high()   -> float: return _config.cctv_medium_high
func _cctv_strong_zero()   -> float: return _config.cctv_strong_zero
func _cctv_strong_full()   -> float: return _config.cctv_strong_full

func choose_action(agent: Node2D, grid: Node, cost_map: RefCounted, exit_rotator: Node, all_agents: Array) -> Action:
	_decision_tick += 1
	_grid = grid
	_cost_map = cost_map
	_exit_rotator = exit_rotator
	_all_agents = all_agents
	_occupied = get_occupied_positions(all_agents, agent.agent_id)

	record_position(agent.grid_pos)

	var active_prisoners: Array[Agent] = _get_active_prisoners(all_agents)
	if active_prisoners.is_empty():
		_emit_decision_debug(agent, "idle", -1, "no_active_prisoners", agent.grid_pos, false)
		return _make_wait_action()

	var active_exit: Vector2i = exit_rotator.get_active_exit()
	_update_observations(agent, active_prisoners)
	_update_cctv_hint(agent, active_prisoners)
	var threat_inputs: Dictionary = _build_threat_inputs(agent, active_prisoners, active_exit)

	# CRITICAL #2 FIX: _select_target now calls _target_priority(), not _escape_threat_score()
	var selection: Dictionary = _select_target(agent, active_prisoners, active_exit)
	var target_agent: Agent = selection.get("target", null)
	if target_agent == null:
		var patrol_only_tile: Vector2i = _get_patrol_target(agent, active_exit, active_prisoners)
		var patrol_move: Vector2i = _move_toward(agent, patrol_only_tile, null)
		_emit_decision_debug(agent, "patrol", -1, "fallback_no_target", patrol_move, false, threat_inputs)
		return _make_move_action(patrol_move)

	var changed_target: bool = bool(selection.get("changed", false))
	var target_reason: String = str(selection.get("reason", "priority"))

	var chosen_behaviour: String = _choose_behaviour(agent, target_agent, active_exit)

	# If adjacent, keep pressure for passive capture instead of stepping away.
	if manhattan(agent.grid_pos, target_agent.grid_pos) <= 1:
		_emit_decision_debug(agent, chosen_behaviour, target_agent.agent_id, "adjacent_hold_pressure", agent.grid_pos, changed_target, threat_inputs)
		return _make_wait_action()

	var strategic_tile: Vector2i = _choose_strategic_tile(chosen_behaviour, agent, target_agent, active_exit, active_prisoners)
	var chosen_move: Vector2i = _move_toward(agent, strategic_tile, target_agent)

	if is_stagnant() and chosen_move == agent.grid_pos:
		var tactical: Vector2i = _pick_pressure_tile(agent, target_agent.grid_pos)
		if tactical != agent.grid_pos:
			chosen_move = tactical
		else:
			var rnd: Vector2i = get_random_legal_move(agent, grid, _occupied)
			var legal_moves: Array[Vector2i] = filter_unoccupied(grid.get_neighbours(agent.grid_pos), _occupied)
			chosen_move = pick_stable_move(legal_moves, rnd, target_agent.grid_pos)

	var should_sprint: bool = _should_sprint(agent, target_agent, chosen_behaviour)
	_emit_decision_debug(agent, chosen_behaviour, target_agent.agent_id, target_reason, chosen_move, changed_target, threat_inputs)

	if should_sprint:
		var sprint_action: Action = Action.new()
		sprint_action.type = Action.Type.SPRINT
		sprint_action.target_pos = chosen_move
		sprint_action.noise_generated = 6
		return sprint_action

	return _make_move_action(chosen_move)

# behaviour → strategic tile dispatch (canonical path; _execute_behaviour deleted)
func _move_toward(agent: Node2D, target: Vector2i, target_agent: Agent = null) -> Vector2i:
	if target == Vector2i(-1, -1):
		return agent.grid_pos

	var goal: Vector2i = target
	if target_agent != null:
		goal = _pick_capture_approach_goal(agent.grid_pos, target_agent.grid_pos)

	var path: Array[Vector2i] = _grid.astar(agent.grid_pos, target, _cost_map)
	if goal != target:
		path = _grid.astar(agent.grid_pos, goal, _cost_map)
	if path.size() > 1:
		var next_step: Vector2i = path[1]
		if not _occupied.has(next_step):
			return next_step

	var blocked: Dictionary = _occupied.duplicate(true)
	var occupied_path: Array[Vector2i] = _path_with_dynamic_blocked(agent.grid_pos, goal, blocked)
	if occupied_path.size() > 1:
		return occupied_path[1]

	var pressure_step: Vector2i = _pick_pressure_tile(agent, goal)
	if pressure_step != agent.grid_pos:
		return pressure_step

	var neighbours: Array[Vector2i] = _grid.get_neighbours(agent.grid_pos)
	var free: Array[Vector2i] = filter_unoccupied(neighbours, _occupied)
	if free.is_empty():
		if neighbours.is_empty():
			return agent.grid_pos
		return SimRandom.choice(neighbours)

	var best: Vector2i = free[0]
	var best_dist: int = manhattan(free[0], goal)
	for n: Vector2i in free:
		var d: int = manhattan(n, goal)
		if d < best_dist:
			best_dist = d
			best = n
	return best

func _patrol_move(agent: Node2D, active_exit: Vector2i, prisoners: Array[Vector2i]) -> Vector2i:
	var patrol_target: Vector2i = _get_patrol_target(agent, active_exit, _get_active_prisoners(_all_agents))
	return _move_toward(agent, patrol_target, null)

func _get_active_prisoners(all_agents: Array) -> Array[Agent]:
	var out: Array[Agent] = []
	for a in all_agents:
		if a._role != "police" and a.is_active:
			out.append(a)
	return out

func _update_observations(police: Node2D, prisoners: Array[Agent]) -> void:
	for p in prisoners:
		var dist: int = manhattan(police.grid_pos, p.grid_pos)
		var visible: bool = _grid.raycast(police.grid_pos, p.grid_pos) and dist <= int(police.stats.vision_range)
		var noisy: bool = dist <= int(p.get_effective_noise())
		if visible or noisy:
			last_seen_pos_by_agent[p.agent_id] = p.grid_pos
			last_seen_tick_by_agent[p.agent_id] = _decision_tick

func _update_cctv_hint(police: Node2D, prisoners: Array[Agent]) -> void:
	var hint_ticks: int = int(police.get("cctv_alert_ticks"))
	var hint_tile: Vector2i = police.get("cctv_alert_target") if hint_ticks > 0 else Vector2i(-1, -1)

	if hint_ticks > 0 and hint_tile.x >= 0:
		var hinted_id: int = _infer_prisoner_id_from_hint(hint_tile, prisoners)
		_cctv_hint = {
			"agent_id": hinted_id,
			"tile": hint_tile,
			"tick": _decision_tick,
			"confidence": clampf(float(hint_ticks) / 10.0, 0.0, 1.0),
		}
		return

	var old_conf: float = float(_cctv_hint.get("confidence", 0.0))
	if old_conf > 0.0:
		_cctv_hint["confidence"] = old_conf * 0.75

func _infer_prisoner_id_from_hint(hint_tile: Vector2i, prisoners: Array[Agent]) -> int:
	var best_id: int = -1
	var best_dist: int = 99999
	for p in prisoners:
		var d: int = manhattan(p.grid_pos, hint_tile)
		if d < best_dist:
			best_dist = d
			best_id = p.agent_id
	if best_dist <= 4:
		return best_id
	return -1

# ─── CRITICAL #2 FIX: _select_target now uses _target_priority() ─────────────
# _target_priority() already contains exit proximity + police distance as
# sub-components (exit_threat, police_distance_cost), so nothing is lost.
# All richer signals — visibility confidence, CCTV confidence, stealth bonus,
# capture opportunity — are now active at every targeting decision.
func _select_target(police: Node2D, prisoners: Array[Agent], active_exit: Vector2i) -> Dictionary:
	var best: Dictionary = {"target": null, "score": -INF, "reason": "priority", "changed": false}
	for p in prisoners:
		var s: float = _target_priority(police, p, active_exit)  # FIX: was _escape_threat_score
		if s > float(best.get("score", -INF)):
			best["target"] = p
			best["score"] = s

	var current: Agent = _find_prisoner_by_id(prisoners, current_target_id)
	if current != null:
		var current_score: float = _target_priority(police, current, active_exit)  # FIX: consistent
		var challenger: Agent = best.get("target", null)
		var challenger_score: float = float(best.get("score", -INF))
		var urgent_switch: bool = _is_urgent_switch(police, current, challenger, active_exit)

		if target_lock_ticks > 0 and not urgent_switch and challenger_score <= current_score * TARGET_SWITCH_RATIO:
			best["target"] = current
			best["score"] = current_score
			best["reason"] = "locked"
			best["changed"] = false
			target_lock_ticks -= 1
			return best

	if best.get("target", null) != null:
		var selected: Agent = best.get("target", null)
		best["changed"] = selected.agent_id != current_target_id
		if bool(best.get("changed", false)):
			current_target_id = selected.agent_id
			target_lock_ticks = TARGET_LOCK_DURATION_TICKS
			best["reason"] = "threat_switch"
		else:
			best["reason"] = "threat_keep"
			target_lock_ticks = maxi(0, target_lock_ticks - 1)

	return best

func _escape_threat_score(police: Node2D, prisoner: Agent, active_exit: Vector2i) -> float:
	# Kept for _build_threat_inputs HUD display — not used for targeting decisions.
	var dist_exit: float = maxf(1.0, float(manhattan(prisoner.grid_pos, active_exit)))
	var dist_police: float = maxf(1.0, float(manhattan(police.grid_pos, prisoner.grid_pos)))
	return (1.0 / dist_exit) * (1.0 / dist_police)

func _build_threat_inputs(police: Node2D, prisoners: Array[Agent], active_exit: Vector2i) -> Dictionary:
	var out: Dictionary = {
		"red_threat": 0.0,
		"blue_threat": 0.0,
	}
	for p in prisoners:
		var t: float = _escape_threat_score(police, p, active_exit)
		if p._role == "rusher_red":
			out["red_threat"] = snappedf(t, 0.0001)
		elif p._role == "sneaky_blue":
			out["blue_threat"] = snappedf(t, 0.0001)
	return out

# ─── CRITICAL #1 FIX: This function now uses _config fields throughout ────────
func _target_priority(police: Node2D, prisoner: Agent, active_exit: Vector2i) -> float:
	var dist_police: int = manhattan(police.grid_pos, prisoner.grid_pos)
	var dist_exit: int = manhattan(prisoner.grid_pos, active_exit)
	var stealth_norm: float = clampf(prisoner.stealth_level / 100.0, 0.0, 1.0)

	var visible_conf: float = 0.0
	if _grid.raycast(police.grid_pos, prisoner.grid_pos):
		var vr: int = int(police.stats.vision_range)
		if dist_police <= vr:
			visible_conf = 1.0 - float(dist_police) / maxf(1.0, float(vr))
	var noise_conf: float = 0.0
	var n: int = int(prisoner.get_effective_noise())
	if dist_police <= n:
		noise_conf = clampf(float(n - dist_police) / maxf(1.0, float(n)), 0.0, 1.0)
	var visibility_conf: float = maxf(visible_conf, noise_conf * 0.75)

	# CCTV is now a real fuzzy input. The raw confidence is fuzzified into
	# Weak / Medium / Strong and then used in target priority.
	var cctv_conf: float = _cctv_confidence_for(prisoner, police)
	var cctv_weak_mu: float = 0.0
	var cctv_medium_mu: float = 0.0
	var cctv_strong_mu: float = 0.0
	if cctv_conf > 0.0:
		cctv_weak_mu = _trap_high(cctv_conf, _cctv_weak_full(), _cctv_weak_zero())
		cctv_medium_mu = _trap_mid(cctv_conf, _cctv_medium_low(), _cctv_medium_peak(), _cctv_medium_high())
		cctv_strong_mu = _trap_low(cctv_conf, _cctv_strong_zero(), _cctv_strong_full())
	var cctv_priority: float = cctv_weak_mu * 0.25 + cctv_medium_mu * 1.05 + cctv_strong_mu * 1.90

	var capture_opportunity: float = 0.0
	if dist_police <= 1:
		capture_opportunity = 4.2
	elif dist_police == 2:
		capture_opportunity = 1.8

	# Exit threat is now a real fuzzy input. Convert distance-to-exit into
	# escape urgency from 0..10, then fuzzify it into Low / Medium / High.
	var exit_urgency: float = clampf(10.0 - float(mini(dist_exit, 10)), 0.0, 10.0)

	# If the prisoner cannot reach this active exit before it rotates, reduce
	# urgency before fuzzification.
	if _exit_rotator != null:
		var ticks_left: int = _exit_rotator.ticks_until_next_rotation()
		if ticks_left > 0 and dist_exit > ticks_left:
			exit_urgency *= 0.5

	var exit_low_mu: float = _trap_high(exit_urgency, _exit_low_full(), _exit_low_zero())
	var exit_medium_mu: float = _trap_mid(exit_urgency, _exit_medium_low(), _exit_medium_peak(), _exit_medium_high())
	var exit_high_mu: float = _trap_low(exit_urgency, _exit_high_zero(), _exit_high_full())
	var exit_threat: float = exit_low_mu * 0.25 + exit_medium_mu * 1.65 + exit_high_mu * 3.0

	var low_stealth_bonus: float = (1.0 - stealth_norm) * 2.2
	var police_distance_cost: float = float(dist_police) * 0.35
	var target_switch_penalty: float = 0.0
	if current_target_id >= 0 and prisoner.agent_id != current_target_id:
		target_switch_penalty = 1.1 + float(maxi(0, target_lock_ticks)) * 0.25

	return capture_opportunity + exit_threat + visibility_conf * 2.0 + cctv_priority + low_stealth_bonus - police_distance_cost - target_switch_penalty

func _cctv_confidence_for(prisoner: Agent, police: Node2D) -> float:
	var hint_conf: float = float(_cctv_hint.get("confidence", 0.0))
	if hint_conf <= 0.0:
		return 0.0
	var hint_tick: int = int(_cctv_hint.get("tick", -99999))
	var age: int = _decision_tick - hint_tick
	if age > CCTV_HINT_MAX_AGE_TICKS:
		return 0.0
	if not prisoner.is_active:
		return 0.0
	var hint_tile: Vector2i = _cctv_hint.get("tile", Vector2i(-1, -1))
	if manhattan(police.grid_pos, hint_tile) <= CCTV_HINT_REACHED_RADIUS:
		return 0.0
	if _grid.raycast(police.grid_pos, prisoner.grid_pos) and manhattan(police.grid_pos, prisoner.grid_pos) <= int(police.stats.vision_range):
		return 0.0
	if int(_cctv_hint.get("agent_id", -1)) >= 0 and int(_cctv_hint.get("agent_id", -1)) != prisoner.agent_id:
		return 0.0
	var decay: float = clampf(1.0 - float(age) / float(CCTV_HINT_MAX_AGE_TICKS + 1), 0.0, 1.0)
	return hint_conf * decay

func _is_urgent_switch(police: Node2D, current: Agent, challenger: Agent, active_exit: Vector2i) -> bool:
	if challenger == null:
		return false
	if not current.is_active:
		return true
	if manhattan(challenger.grid_pos, active_exit) + 2 < manhattan(current.grid_pos, active_exit):
		return true
	if challenger.stealth_level + 25.0 < current.stealth_level:
		return true
	var ch_conf: float = _cctv_confidence_for(challenger, police)
	if ch_conf >= CCTV_HIGH_CONFIDENCE and challenger.agent_id != current.agent_id:
		return true
	var current_reachable: bool = _is_reachable(police.grid_pos, _pick_capture_approach_goal(police.grid_pos, current.grid_pos))
	if not current_reachable:
		return true
	return false

func _is_reachable(start: Vector2i, goal: Vector2i) -> bool:
	var path: Array[Vector2i] = _grid.astar(start, goal, _cost_map)
	return path.size() > 1

func _find_prisoner_by_id(prisoners: Array[Agent], aid: int) -> Agent:
	for p in prisoners:
		if p.agent_id == aid:
			return p
	return null

# ─── CRITICAL #3 FIX: Early-return hard bypasses removed ──────────────────────
# The two blocks:
#   if alert_level >= 0.50 and d <= 7: return "chase"
#   if alert_level >= 0.35 and d <= 9: return "investigate"
# are DELETED. Alert level influence is now a smooth weight on chase_score
# via _config.alert_chase_weight, keeping the full fuzzy architecture active.
func _choose_behaviour(police: Node2D, target: Agent, active_exit: Vector2i) -> String:
	var d: int = manhattan(police.grid_pos, target.grid_pos)
	var target_exit_d: int = manhattan(target.grid_pos, active_exit)
	var alert_level: float = clampf(float(police.metrics.get("alert_level", 0.0)), 0.0, 1.0)
	var dist_v: float = float(d)

	# Distance and alert fuzzy inputs.
	var near_mu: float       = _trap_high(dist_v, _near_full(), _near_zero())
	var medium_mu: float     = _trap_mid(dist_v, _medium_low(), _medium_peak(), _medium_high())
	var far_mu: float        = _trap_low(dist_v, _far_zero(), _far_full())
	var suspicious_mu: float = _trap_mid(alert_level, 0.20, _alert_suspicious(), 0.75)
	var alarmed_mu: float    = _trap_low(alert_level, _alert_alarmed(), 0.90)

	# Exit threat fuzzy input, matching Fig 8.
	# Distance to exit -> escape urgency scale 0..10.
	var exit_urgency: float = clampf(10.0 - float(mini(target_exit_d, 10)), 0.0, 10.0)
	if _exit_rotator != null:
		var ticks_left: int = _exit_rotator.ticks_until_next_rotation()
		if ticks_left > 0 and target_exit_d > ticks_left:
			exit_urgency *= 0.5
	var exit_low_mu: float = _trap_high(exit_urgency, _exit_low_full(), _exit_low_zero())
	var exit_medium_mu: float = _trap_mid(exit_urgency, _exit_medium_low(), _exit_medium_peak(), _exit_medium_high())
	var exit_high_mu: float = _trap_low(exit_urgency, _exit_high_zero(), _exit_high_full())

	# CCTV confidence fuzzy input, matching Fig 9.
	var cctv_conf: float = _cctv_confidence_for(target, police)
	var cctv_weak_mu: float = 0.0
	var cctv_medium_mu: float = 0.0
	var cctv_strong_mu: float = 0.0
	if cctv_conf > 0.0:
		cctv_weak_mu = _trap_high(cctv_conf, _cctv_weak_full(), _cctv_weak_zero())
		cctv_medium_mu = _trap_mid(cctv_conf, _cctv_medium_low(), _cctv_medium_peak(), _cctv_medium_high())
		cctv_strong_mu = _trap_low(cctv_conf, _cctv_strong_zero(), _cctv_strong_full())

	# Rule base / behaviour scores.
	# Multiple rules can activate at the same time; winner-takes-all chooses output.
	var chase_score: float = \
		near_mu * _config.w_chase + \
		medium_mu * alarmed_mu + \
		alert_level * _config.alert_chase_weight + \
		_config.alert_chase_base_bias * alert_level + \
		cctv_strong_mu * _config.w_cctv_strong_chase

	var investigate_score: float = \
		medium_mu * maxf(suspicious_mu, alarmed_mu * 0.60) + \
		far_mu * suspicious_mu * 0.65 + \
		exit_medium_mu * _config.w_exit_medium_investigate + \
		cctv_weak_mu * _config.w_cctv_weak_investigate + \
		cctv_medium_mu * _config.w_cctv_medium_investigate

	var intercept_score: float = \
		far_mu * maxf(alarmed_mu, 0.35) + \
		exit_medium_mu * _config.w_exit_medium_intercept + \
		exit_high_mu * _config.w_exit_high_intercept + \
		cctv_strong_mu * _config.w_cctv_strong_intercept

	var patrol_score: float = \
		far_mu * maxf(0.0, 1.0 - alert_level) + \
		exit_low_mu * _config.w_exit_low_patrol + \
		0.10

	# Extra tactical bonuses remain as crisp helper rules.
	if d > 3 and d <= 5:
		chase_score += 0.45
	if target_exit_d <= 4:
		intercept_score += 0.55
	if d <= 2:
		chase_score += 0.75

	# Recent sighting nudges investigation.
	var seen_tick: int = int(last_seen_tick_by_agent.get(target.agent_id, -99999))
	if _decision_tick - seen_tick <= 3:
		investigate_score += 0.25

	# Winner-takes-all defuzzification.
	if chase_score >= intercept_score and chase_score >= investigate_score and chase_score >= patrol_score:
		return "chase"
	if intercept_score >= investigate_score and intercept_score >= patrol_score:
		return "intercept"
	if investigate_score >= patrol_score:
		return "investigate"
	return "patrol"

func _choose_strategic_tile(behaviour: String, police: Node2D, target: Agent, active_exit: Vector2i, prisoners: Array[Agent]) -> Vector2i:
	match behaviour:
		"chase":
			return target.grid_pos
		"intercept":
			return _choose_intercept_tile(police, target, active_exit)
		"investigate":
			return Vector2i(last_seen_pos_by_agent.get(target.agent_id, target.grid_pos))
		"patrol":
			return _get_patrol_target(police, active_exit, prisoners)
		_:
			return target.grid_pos

func _choose_intercept_tile(police: Node2D, target: Agent, active_exit: Vector2i) -> Vector2i:
	var path_to_exit: Array[Vector2i] = _grid.astar(target.grid_pos, active_exit, _cost_map)
	if path_to_exit.size() <= 1:
		return target.grid_pos

	var best_tile: Vector2i = target.grid_pos
	var best_score: float = -INF
	for ahead in range(INTERCEPT_AHEAD_MIN, INTERCEPT_AHEAD_MAX + 1):
		var idx: int = mini(path_to_exit.size() - 1, ahead)
		var tile: Vector2i = path_to_exit[idx]
		var p_path: Array[Vector2i] = _grid.astar(police.grid_pos, tile, _cost_map)
		if p_path.size() <= 1:
			continue
		var police_steps: int = p_path.size() - 1
		var prisoner_steps: int = idx
		var score: float = 0.0
		if police_steps <= prisoner_steps + 1:
			score += 3.0
		score -= float(police_steps) * 0.25
		score += float(prisoner_steps) * 0.20
		if score > best_score:
			best_score = score
			best_tile = tile

	return best_tile

func _get_patrol_target(police: Node2D, active_exit: Vector2i, prisoners: Array[Agent]) -> Vector2i:
	var should_refresh: bool = (_decision_tick - _patrol_refresh_tick) >= PATROL_REFRESH_TICKS
	if _patrol_target.x < 0:
		should_refresh = true
	if should_refresh:
		_patrol_refresh_tick = _decision_tick
		if prisoners.is_empty():
			_patrol_target = active_exit
		else:
			var most_threat: Agent = prisoners[0]
			var best_exit_d: int = manhattan(prisoners[0].grid_pos, active_exit)
			for p in prisoners:
				var ed: int = manhattan(p.grid_pos, active_exit)
				if ed < best_exit_d:
					best_exit_d = ed
					most_threat = p
			_patrol_target = _choose_intercept_tile(police, most_threat, active_exit)
	_patrol_target = _sanitize_patrol_target(police, _patrol_target, active_exit, prisoners)
	return _patrol_target

func _sanitize_patrol_target(police: Node2D, desired: Vector2i, active_exit: Vector2i, prisoners: Array[Agent]) -> Vector2i:
	if _is_walkable_reachable(police.grid_pos, desired):
		return desired
	if _is_walkable_reachable(police.grid_pos, active_exit):
		return active_exit
	for p in prisoners:
		if p != null and p.is_active and _is_walkable_reachable(police.grid_pos, p.grid_pos):
			return p.grid_pos
	for nb in _grid.get_neighbours(police.grid_pos):
		if _grid.is_walkable(nb):
			return nb
	return police.grid_pos

func _is_walkable_reachable(from_tile: Vector2i, target_tile: Vector2i) -> bool:
	if _grid == null:
		return false
	if from_tile == target_tile:
		return _grid.is_walkable(target_tile)
	if not _grid.is_walkable(target_tile):
		return false
	var path: Array[Vector2i] = _grid.astar(from_tile, target_tile, _cost_map)
	return path.size() > 1

func _pick_capture_approach_goal(police_pos: Vector2i, prisoner_pos: Vector2i) -> Vector2i:
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	var best: Vector2i = prisoner_pos
	var best_d: int = 99999
	for d in dirs:
		var t: Vector2i = prisoner_pos + d
		if not _grid.is_walkable(t):
			continue
		if _occupied.has(t):
			continue
		var md: int = manhattan(police_pos, t)
		if md < best_d:
			best_d = md
			best = t
	return best

func _path_with_dynamic_blocked(start: Vector2i, goal: Vector2i, blocked: Dictionary) -> Array[Vector2i]:
	var q: Array[Vector2i] = [start]
	var came: Dictionary = {start: Vector2i(-9999, -9999)}
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		if cur == goal:
			break
		for nb in _grid.get_neighbours(cur):
			if came.has(nb):
				continue
			if blocked.has(nb) and nb != goal:
				continue
			came[nb] = cur
			q.append(nb)

	if not came.has(goal):
		return []

	var path_rev: Array[Vector2i] = []
	var p: Vector2i = goal
	while p != Vector2i(-9999, -9999):
		path_rev.append(p)
		p = Vector2i(came.get(p, Vector2i(-9999, -9999)))
	path_rev.reverse()
	return path_rev

func _pick_pressure_tile(agent: Node2D, goal: Vector2i) -> Vector2i:
	var neighbours: Array[Vector2i] = _grid.get_neighbours(agent.grid_pos)
	var free: Array[Vector2i] = filter_unoccupied(neighbours, _occupied)
	if free.is_empty():
		return agent.grid_pos
	var best: Vector2i = free[0]
	var best_score: float = INF
	for n in free:
		var s: float = float(manhattan(n, goal))
		s += movement_memory_penalty(n) * 0.8
		if s < best_score:
			best_score = s
			best = n
	return best

func _should_sprint(agent: Node2D, target: Agent, behaviour: String) -> bool:
	if behaviour != "chase" and behaviour != "intercept":
		return false
	if agent.has_status("exhausted"):
		return false
	var dist: int = manhattan(agent.grid_pos, target.grid_pos)
	if dist > CHASE_SPRINT_RANGE:
		return false
	if agent.stats == null:
		return false
	return agent.stamina >= agent.stats.stamina_sprint_cost

func _emit_debug(agent: Node2D, behaviour: String, target_id: int, reason: String, final_move: Vector2i, changed: bool) -> void:
	var hint_tick: int = int(_cctv_hint.get("tick", -99999))
	var hint_age: int = _decision_tick - hint_tick
	var hint_conf: float = float(_cctv_hint.get("confidence", 0.0))
	var hint_tile: Vector2i = _cctv_hint.get("tile", Vector2i(-1, -1))
	print("[POLICE_AI] beh=%s target=%d reason=%s from=%s hint=(age:%d conf:%.2f tile:%s) changed=%s move=%s" % [
		behaviour,
		target_id,
		reason,
		agent.grid_pos,
		hint_age,
		hint_conf,
		hint_tile,
		str(changed),
		final_move,
	])

func _emit_decision_debug(agent: Node2D, behaviour: String, target_id: int, reason: String, final_move: Vector2i, changed: bool, threat_inputs: Dictionary = {}) -> void:
	_emit_debug(agent, behaviour, target_id, reason, final_move, changed)
	var inputs: Dictionary = {
		"target_id":      target_id,
		"target_reason":  reason,
		"target_changed": changed,
		"cctv_hint_age":  _decision_tick - int(_cctv_hint.get("tick", -99999)),
		"cctv_hint_conf": float(_cctv_hint.get("confidence", 0.0)),
		"cctv_hint_tile": _cctv_hint.get("tile", Vector2i(-1, -1)),
	}
	for k in threat_inputs.keys():
		inputs[k] = threat_inputs[k]
	if target_id >= 0:
		var selected_role: String = ""
		for p in _all_agents:
			if p._role != "police" and p.agent_id == target_id:
				selected_role = p._role
				break
		if selected_role == "rusher_red":
			inputs["selected_threat"] = float(inputs.get("red_threat", 0.0))
		elif selected_role == "sneaky_blue":
			inputs["selected_threat"] = float(inputs.get("blue_threat", 0.0))

	# FIX #4: Re-compute defuzzified scores from the last _choose_behaviour call
	# and emit them so the HUD can display live fuzzy membership bars.
	# We find the target agent to recompute the same values shown in _choose_behaviour.
	var chase_score:     float = 0.0
	var investigate_score: float = 0.0
	var intercept_score: float = 0.0
	var patrol_score:    float = 0.0
	var alert_level:     float = clampf(float(agent.metrics.get("alert_level", 0.0)), 0.0, 1.0)
	for p in _all_agents:
		if p._role != "police" and p.agent_id == target_id:
			var d: int              = manhattan(agent.grid_pos, p.grid_pos)
			var target_exit_d: int  = manhattan(p.grid_pos, _exit_rotator.get_active_exit() if _exit_rotator != null else Vector2i(0,0))
			var dist_v: float       = float(d)
			var near_mu: float      = _trap_high(dist_v, _near_full(), _near_zero())
			var medium_mu: float    = _trap_mid(dist_v, _medium_low(), _medium_peak(), _medium_high())
			var far_mu: float       = _trap_low(dist_v, _far_zero(), _far_full())
			var suspicious_mu: float = _trap_mid(alert_level, 0.20, _alert_suspicious(), 0.75)
			var alarmed_mu: float    = _trap_low(alert_level, _alert_alarmed(), 0.90)
			var exit_urgency: float = clampf(10.0 - float(mini(target_exit_d, 10)), 0.0, 10.0)
			if _exit_rotator != null:
				var ticks_left: int = _exit_rotator.ticks_until_next_rotation()
				if ticks_left > 0 and target_exit_d > ticks_left:
					exit_urgency *= 0.5
			var exit_low_mu: float = _trap_high(exit_urgency, _exit_low_full(), _exit_low_zero())
			var exit_medium_mu: float = _trap_mid(exit_urgency, _exit_medium_low(), _exit_medium_peak(), _exit_medium_high())
			var exit_high_mu: float = _trap_low(exit_urgency, _exit_high_zero(), _exit_high_full())
			var cctv_conf: float = _cctv_confidence_for(p, agent)
			var cctv_weak_mu: float = 0.0
			var cctv_medium_mu: float = 0.0
			var cctv_strong_mu: float = 0.0
			if cctv_conf > 0.0:
				cctv_weak_mu = _trap_high(cctv_conf, _cctv_weak_full(), _cctv_weak_zero())
				cctv_medium_mu = _trap_mid(cctv_conf, _cctv_medium_low(), _cctv_medium_peak(), _cctv_medium_high())
				cctv_strong_mu = _trap_low(cctv_conf, _cctv_strong_zero(), _cctv_strong_full())
			chase_score      = near_mu * _config.w_chase + medium_mu * alarmed_mu + alert_level * _config.alert_chase_weight + _config.alert_chase_base_bias * alert_level + cctv_strong_mu * _config.w_cctv_strong_chase
			investigate_score = medium_mu * maxf(suspicious_mu, alarmed_mu * 0.60) + far_mu * suspicious_mu * 0.65 + exit_medium_mu * _config.w_exit_medium_investigate + cctv_weak_mu * _config.w_cctv_weak_investigate + cctv_medium_mu * _config.w_cctv_medium_investigate
			intercept_score   = far_mu * maxf(alarmed_mu, 0.35) + exit_medium_mu * _config.w_exit_medium_intercept + exit_high_mu * _config.w_exit_high_intercept + cctv_strong_mu * _config.w_cctv_strong_intercept
			patrol_score      = far_mu * maxf(0.0, 1.0 - alert_level) + exit_low_mu * _config.w_exit_low_patrol + 0.10
			if target_exit_d <= 4:
				intercept_score += 0.55
			if d <= 2:
				chase_score += 0.75
			var seen_tick: int = int(last_seen_tick_by_agent.get(target_id, -99999))
			if _decision_tick - seen_tick <= 3:
				investigate_score += 0.25
			break

	# Bug 3 fix: emit raw (unclamped) scores so HUD can normalize bars by max
	var max_score: float = maxf(maxf(chase_score, intercept_score), maxf(investigate_score, patrol_score))
	inputs["chase_score_raw"]       = chase_score
	inputs["intercept_score_raw"]   = intercept_score
	inputs["investigate_score_raw"] = investigate_score
	inputs["patrol_score_raw"]      = patrol_score
	inputs["max_behaviour_score"]   = max_score

	# FIX #4: Emit fuzzy_debug so HUD panels can draw live defuzz bar charts.
	# Bug 3 fix: bar values normalized relative to max_score so dominant behaviour
	# is always visually distinguishable from a marginal win.
	var bar_max: float = maxf(maxf(chase_score, intercept_score), maxf(investigate_score, patrol_score))
	bar_max = maxf(bar_max, 0.001)
	EventBus.emit_signal("fuzzy_debug", {
		"chase":       chase_score / bar_max,
		"investigate": investigate_score / bar_max,
		"intercept":   intercept_score / bar_max,
		"patrol":      patrol_score / bar_max,
		"alert":       alert_level,
		"behaviour":   behaviour,
		"agent_id":    agent.agent_id,
	})

	# MAJOR #2 FIX: Emit full fuzzy scores so results_screen can draw a real
	# police decision tree with all four behaviour scores and target scores.
	# Previously only one fake rule {rule: behaviour, strength: 1.0} was emitted,
	# giving the UI no data to build actual branches.
	var target_agent_obj: Agent = null
	for p in _all_agents:
		if p._role != "police" and p.agent_id == target_id:
			target_agent_obj = p
			break
	var red_score: float = 0.0
	var blue_score: float = 0.0
	for p in _all_agents:
		if p._role == "rusher_red" and p.is_active:
			red_score = snappedf(_target_priority(agent, p, _exit_rotator.get_active_exit() if _exit_rotator != null else Vector2i(0,0)), 0.01)
		elif p._role == "sneaky_blue" and p.is_active:
			blue_score = snappedf(_target_priority(agent, p, _exit_rotator.get_active_exit() if _exit_rotator != null else Vector2i(0,0)), 0.01)

	inputs["alert_level"] = int(round(alert_level * 100.0))
	inputs["red_target_score"] = red_score
	inputs["blue_target_score"] = blue_score
	inputs["chase_score"] = snappedf(chase_score, 0.01)
	inputs["intercept_score"] = snappedf(intercept_score, 0.01)
	inputs["investigate_score"] = snappedf(investigate_score, 0.01)
	inputs["patrol_score"] = snappedf(patrol_score, 0.01)

	if target_agent_obj != null:
		var active_exit: Vector2i = _exit_rotator.get_active_exit() if _exit_rotator != null else Vector2i(0,0)
		inputs["red_distance"] = manhattan(agent.grid_pos, target_agent_obj.grid_pos) if target_agent_obj._role == "rusher_red" else -1
		inputs["blue_distance"] = manhattan(agent.grid_pos, target_agent_obj.grid_pos) if target_agent_obj._role == "sneaky_blue" else -1
		inputs["red_exit_distance"] = manhattan(target_agent_obj.grid_pos, active_exit) if target_agent_obj._role == "rusher_red" else -1
		inputs["blue_exit_distance"] = manhattan(target_agent_obj.grid_pos, active_exit) if target_agent_obj._role == "sneaky_blue" else -1
		inputs["red_stealth"] = int(target_agent_obj.stealth_level) if target_agent_obj._role == "rusher_red" else 0
		inputs["blue_stealth"] = int(target_agent_obj.stealth_level) if target_agent_obj._role == "sneaky_blue" else 0
		for p in _all_agents:
			if p._role != "police" and p.is_active and p.agent_id != target_agent_obj.agent_id:
				if p._role == "rusher_red":
					inputs["red_distance"] = manhattan(agent.grid_pos, p.grid_pos)
					inputs["red_exit_distance"] = manhattan(p.grid_pos, active_exit)
					inputs["red_stealth"] = int(p.stealth_level)
				elif p._role == "sneaky_blue":
					inputs["blue_distance"] = manhattan(agent.grid_pos, p.grid_pos)
					inputs["blue_exit_distance"] = manhattan(p.grid_pos, active_exit)
					inputs["blue_stealth"] = int(p.stealth_level)

	var rules: Array = [
		{"rule": "CHASE",       "label": "Chase",       "strength": chase_score       / maxf(max_score, 0.001)},
		{"rule": "INTERCEPT",   "label": "Intercept",   "strength": intercept_score   / maxf(max_score, 0.001)},
		{"rule": "INVESTIGATE", "label": "Investigate", "strength": investigate_score / maxf(max_score, 0.001)},
		{"rule": "PATROL",      "label": "Patrol",      "strength": patrol_score      / maxf(max_score, 0.001)},
	]
	EventBus.emit_signal("fuzzy_decision", agent.agent_id, inputs, rules, behaviour, final_move)

# ── Fuzzy membership functions ─────────────────────────────────────────────────
func _trap_high(value: float, low_end: float, high_start: float) -> float:
	if value <= low_end:
		return 1.0
	if value >= high_start:
		return 0.0
	var denom := high_start - low_end
	if denom < 0.001:
		return 0.5
	return (high_start - value) / denom

func _trap_low(value: float, low_end: float, high_start: float) -> float:
	if value >= high_start:
		return 1.0
	if value <= low_end:
		return 0.0
	var denom := high_start - low_end
	if denom < 0.001:
		return 0.5
	return (value - low_end) / denom

func _trap_mid(value: float, low: float, mid: float, high: float) -> float:
	if value <= low or value >= high:
		return 0.0
	if value <= mid:
		var denom := mid - low
		if denom < 0.001:
			return 1.0
		return (value - low) / denom
	var denom := high - mid
	if denom < 0.001:
		return 1.0
	return (high - value) / denom

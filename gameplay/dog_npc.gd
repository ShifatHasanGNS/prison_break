extends Node2D
class_name DogNPC

enum State { IDLE, PATROL, ALERT, SNIFF, CHASE, LATCHED, RELEASE_COOLDOWN }
const STATE_NAMES: Array = ["IDLE", "PATROL", "ALERT", "SNIFF", "CHASE", "LATCHED", "RELEASE_COOLDOWN"]

const TILE_SIZE: int = 48
const DOG_LATCH_DURATION: float = 5.0
const DOG_RELEASE_COOLDOWN: float = 1.5
const DOG_TICK_SECONDS: float = 0.25

const DANGER_RADIUS_PATROL: int = 2
const DANGER_RADIUS_ALERT : int = 3
const DANGER_RADIUS_CHASE : int = 4
const DANGER_VALUE        : float = 3.0

const IDLE_TICKS_BEFORE_PATROL : int = 3
const ALERT_TICKS_BEFORE_SNIFF : int = 3
const SNIFF_TICKS_BEFORE_PATROL: int = 5
const NOISE_DETECT_RADIUS      : int = 5
const LATCH_DURATION_TICKS     : int = int(round(DOG_LATCH_DURATION / DOG_TICK_SECONDS))
const LATCH_RANGE              : int = 1
const RELEASE_COOLDOWN_TICKS   : int = int(round(DOG_RELEASE_COOLDOWN / DOG_TICK_SECONDS))
const DOG_SLOW_MULTIPLIER      : float = 0.45

var grid_pos      : Vector2i = Vector2i.ZERO
var _state        : int      = State.IDLE
var _grid         : Node     = null
var _waypoints    : Array[Vector2i] = []
var _waypoint_idx : int = 0
var _state_ticks  : int = 0
var _alert_pos    : Vector2i = Vector2i(-1, -1)
var _facing       : Vector2i = Vector2i(1, 0)   # directional facing for draw
var _exit_tiles   : Array[Vector2i] = []
var _tick_agents  : Array = []   # snapshot of agents for this tick (collision check)
var _doors        : Array = []   # DoorInteractable refs for locked-door check
var _visual_target_pos: Vector2 = Vector2.ZERO
var _anim_phase: float = 0.0
var _tick_index: int = 0
var _spot_cooldown_by_agent: Dictionary = {}
var _latched_agent_id: int = -1
var _latch_ticks_remaining: int = 0
var _release_cooldown_ticks_remaining: int = 0
var _latched_agent_ref: Agent = null

# -------------------------------------------------------------------------

func setup(waypoints: Array, grid: Node, exit_tiles: Array = [], doors: Array = []) -> void:
	z_index = 1   # renders below agents (z=2)
	_grid = grid
	_waypoints.clear()
	for wp in waypoints:
		_waypoints.append(wp as Vector2i)
	_exit_tiles.clear()
	for et in exit_tiles:
		_exit_tiles.append(et as Vector2i)
	_doors = doors

	if not _waypoints.is_empty():
		grid_pos = _waypoints[0]
		_visual_target_pos = Vector2(grid_pos.x * TILE_SIZE + TILE_SIZE / 2.0, grid_pos.y * TILE_SIZE + TILE_SIZE / 2.0)
		position = _visual_target_pos

	print("DogNPC: %d waypoints, starting at %s" % [_waypoints.size(), grid_pos])
	_change_state(State.PATROL)

## Called every tick from SimulationLoop._update_hazards().
func tick(agents: Array) -> void:
	_tick_agents = agents
	_tick_index += 1
	_state_ticks += 1

	if _latch_ticks_remaining > 0:
		_tick_latch(agents)
		return

	if _release_cooldown_ticks_remaining <= 0 and _try_latch_prisoner(agents):
		return

	match _state:
		State.IDLE:   _tick_idle()
		State.PATROL: _tick_patrol()
		State.ALERT:  _tick_alert(agents)
		State.SNIFF:  _tick_sniff()
		State.CHASE:  _tick_chase(agents)
		State.RELEASE_COOLDOWN: _tick_release_cooldown(agents)

	if _state != State.CHASE and _state != State.RELEASE_COOLDOWN:
		_check_senses(agents)

func get_state_name() -> String:
	return STATE_NAMES[_state] if _state < STATE_NAMES.size() else "UNKNOWN"

## Seed danger tiles into DangerMap. Called from SimulationLoop._rebuild_maps().
func seed_danger(danger_map: DangerMap) -> void:
	var radius: int = get_danger_radius()

	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			danger_map.add(grid_pos + Vector2i(dx, dy), DANGER_VALUE)

func get_danger_radius() -> int:
	match _state:
		State.CHASE, State.ALERT, State.LATCHED: return DANGER_RADIUS_CHASE
		State.SNIFF: return DANGER_RADIUS_ALERT
		_: return DANGER_RADIUS_PATROL

# -------------------------------------------------------------------------
# Animation
# -------------------------------------------------------------------------

func _process(delta: float) -> void:
	var move_delta: Vector2 = Vector2.ZERO
	if _latch_ticks_remaining > 0 and _latched_agent_ref != null and is_instance_valid(_latched_agent_ref):
		var attach_offset: Vector2 = Vector2(-10.0, 8.0)
		var facing: Vector2i = Vector2i.RIGHT
		var facing_value: Variant = _latched_agent_ref.get("_facing")
		if facing_value is Vector2i:
			facing = facing_value
		if facing.x < 0:
			attach_offset = Vector2(10.0, 8.0)
		elif facing.y < 0:
			attach_offset = Vector2(-8.0, 12.0)
		move_delta = (_latched_agent_ref.position + attach_offset) - position
		position = _latched_agent_ref.position + attach_offset
		_visual_target_pos = position
	else:
		move_delta = _visual_target_pos - position
		position += move_delta * minf(1.0, delta * 10.0)
	_anim_phase += delta * (10.0 if move_delta.length() > 0.4 else 4.0)
	queue_redraw()

# =========================================================================
# DRAWING  (pixel-art dog)
# =========================================================================

func _draw() -> void:
	var is_danger: bool = _state == State.ALERT or _state == State.SNIFF or _state == State.CHASE
	if is_danger:
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.004)
		var d_rad: float = float((DANGER_RADIUS_CHASE if _state == State.CHASE else DANGER_RADIUS_ALERT) * 48)
		draw_circle(Vector2.ZERO, d_rad, Color(0.90, 0.18, 0.05, 0.05 + pulse * 0.05))
		draw_circle(Vector2.ZERO, d_rad * 0.65, Color(0.98, 0.36, 0.08, 0.03 + pulse * 0.03))
		draw_arc(Vector2.ZERO, d_rad, 0.0, TAU, 48, Color(0.95, 0.22, 0.05, 0.18 + pulse * 0.14), 1.8)
	if _facing.x < 0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))
	elif _facing.y > 0:
		draw_set_transform(Vector2.ZERO, PI / 2.0, Vector2.ONE)
	elif _facing.y < 0:
		draw_set_transform(Vector2.ZERO, -PI / 2.0, Vector2.ONE)
	else:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_dog_body()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font: Font = ThemeDB.fallback_font
	if (_state == State.ALERT or _state == State.CHASE or _state == State.LATCHED) and font != null:
		draw_string(font, Vector2(-5.0, -31.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.00, 0.50, 0.10))

func _draw_dog_body() -> void:
	var t_ms: float = float(Time.get_ticks_msec())
	var is_alert: bool = _state == State.ALERT or _state == State.CHASE
	var is_chase: bool = _state == State.CHASE
	var lean: float = 3.0 if is_chase else 0.0
	var leg_anim: float = sin(_anim_phase)
	var tail_lift: float = sin(_anim_phase * 0.7) * 3.0
	var outline: Color = Color(0.08, 0.07, 0.06)
	var dark_fur: Color = Color(0.18, 0.13, 0.08)
	var tan_fur: Color = Color(0.73, 0.55, 0.30)
	var gold_fur: Color = Color(0.88, 0.67, 0.34)
	var harness: Color = Color(0.08, 0.16, 0.24)
	var sensor: Color = Color(0.00, 0.90, 0.95)

	draw_circle(Vector2(0.0, 11.0), 18.0, Color(0, 0, 0, 0.18))
	draw_line(Vector2(-17.0, -3.0), Vector2(-28.0, -11.0 + tail_lift), outline, 5.0)
	draw_line(Vector2(-17.0, -3.0), Vector2(-28.0, -11.0 + tail_lift), tan_fur, 3.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-20.0 + lean, -11.0), Vector2(4.0 + lean, -14.0), Vector2(20.0 + lean, -6.0),
		Vector2(18.0 + lean, 10.0), Vector2(-18.0 + lean, 12.0), Vector2(-23.0 + lean, 1.0),
	]), outline)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-16.0 + lean, -8.0), Vector2(4.0 + lean, -11.0), Vector2(17.0 + lean, -4.0),
		Vector2(14.0 + lean, 8.0), Vector2(-14.0 + lean, 9.0), Vector2(-19.0 + lean, 1.0),
	]), tan_fur)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-12.0 + lean, -8.0), Vector2(5.0 + lean, -10.0), Vector2(14.0 + lean, -4.0),
		Vector2(6.0 + lean, 2.0), Vector2(-14.0 + lean, 2.0),
	]), dark_fur)
	draw_rect(Rect2(-4.0 + lean, -4.0, 15.0, 8.0), harness)
	draw_rect(Rect2(6.0 + lean, -4.0, 5.0, 8.0), sensor)
	draw_rect(Rect2(12.0 + lean, -1.0, 5.0, 9.0), gold_fur)

	var leg_data: Array = [
		[-13.0, 8.0 + leg_anim * 2.0],
		[-3.0, 9.0 - leg_anim * 2.0],
		[8.0, 8.0 - leg_anim * 2.0],
		[15.0, 7.0 + leg_anim * 2.0],
	]
	for leg in leg_data:
		draw_line(Vector2(float(leg[0]) + lean, float(leg[1])), Vector2(float(leg[0]) + lean - 1.0, 18.0), outline, 4.0)
		draw_line(Vector2(float(leg[0]) + lean, float(leg[1])), Vector2(float(leg[0]) + lean - 1.0, 18.0), tan_fur, 2.5)

	draw_colored_polygon(PackedVector2Array([
		Vector2(15.0 + lean, -8.0), Vector2(27.0 + lean, -8.0), Vector2(31.0 + lean, 0.0),
		Vector2(25.0 + lean, 9.0), Vector2(14.0 + lean, 7.0),
	]), outline)
	draw_colored_polygon(PackedVector2Array([
		Vector2(17.0 + lean, -6.0), Vector2(27.0 + lean, -6.0), Vector2(29.0 + lean, 0.0),
		Vector2(24.0 + lean, 7.0), Vector2(16.0 + lean, 5.0),
	]), gold_fur)
	draw_colored_polygon(PackedVector2Array([
		Vector2(22.0 + lean, -8.0), Vector2(27.0 + lean, -16.0), Vector2(31.0 + lean, -6.0),
	]), dark_fur)
	draw_colored_polygon(PackedVector2Array([
		Vector2(18.0 + lean, -7.0), Vector2(22.0 + lean, -14.0), Vector2(24.0 + lean, -6.0),
	]), dark_fur)
	draw_circle(Vector2(28.0 + lean, 0.0), 1.6, Color.WHITE)
	draw_circle(Vector2(28.5 + lean, 0.0), 0.8, Color(0.05, 0.05, 0.05))
	if is_alert:
		draw_circle(Vector2(28.0 + lean, 0.0), 2.0, Color(1.00, 0.20, 0.12, 0.55))
	draw_circle(Vector2(31.0 + lean, 4.0), 1.6, Color(0.10, 0.06, 0.05))
	draw_line(Vector2(31.0 + lean, 2.0), Vector2(36.0 + lean, 0.0), Color(0.10, 0.06, 0.05), 2.0)

func _tick_idle() -> void:
	if _state_ticks >= IDLE_TICKS_BEFORE_PATROL:
		_change_state(State.PATROL)

func _tick_patrol() -> void:
	if _waypoints.is_empty():
		return
	var target: Vector2i = _waypoints[_waypoint_idx]
	if grid_pos == target:
		_waypoint_idx = (_waypoint_idx + 1) % _waypoints.size()
		return
	_step_toward(target)

func _tick_alert(agents: Array) -> void:
	for agent in agents:
		if agent.get("_role") == "police" or not agent.get("is_active"):
			continue
		if _can_see(agent.get("grid_pos")):
			_emit_spotted(agent)
			_change_state(State.CHASE)
			return

	if _state_ticks >= ALERT_TICKS_BEFORE_SNIFF:
		if _alert_pos.x >= 0 and grid_pos != _alert_pos:
			_step_toward(_alert_pos)
		else:
			_change_state(State.SNIFF)

func _tick_sniff() -> void:
	if _state_ticks >= SNIFF_TICKS_BEFORE_PATROL:
		_alert_pos = Vector2i(-1, -1)
		_change_state(State.PATROL)

func _tick_chase(agents: Array) -> void:
	var nearest     : Vector2i = Vector2i(-1, -1)
	var nearest_dist: int      = 999

	for agent in agents:
		if agent.get("_role") == "police" or not agent.get("is_active"):
			continue
		var apos: Vector2i = agent.get("grid_pos")
		var d   : int      = absi(apos.x - grid_pos.x) + absi(apos.y - grid_pos.y)
		if d < nearest_dist:
			nearest_dist = d
			nearest      = apos

	if nearest.x < 0:
		_change_state(State.PATROL)
		return

	if _can_see(nearest) or nearest_dist <= NOISE_DETECT_RADIUS:
		_step_toward(nearest)
	else:
		_alert_pos = nearest
		_change_state(State.SNIFF)

func _tick_latch(agents: Array) -> void:
	var prisoner: Agent = _find_prisoner_by_id(agents, _latched_agent_id)
	if prisoner == null or prisoner._role == "police" or not prisoner.is_active:
		_release_latch(agents)
		return

	# Stick to target while pinned.
	var old_pos: Vector2i = grid_pos
	grid_pos = prisoner.grid_pos
	var dir: Vector2i = grid_pos - old_pos
	if dir != Vector2i.ZERO:
		_facing = dir
	_visual_target_pos = Vector2(grid_pos.x * TILE_SIZE + TILE_SIZE / 2.0, grid_pos.y * TILE_SIZE + TILE_SIZE / 2.0)
	position = _visual_target_pos

	_latch_ticks_remaining -= 1
	if _latch_ticks_remaining <= 0:
		_release_latch(agents)

func _tick_release_cooldown(agents: Array) -> void:
	_release_cooldown_ticks_remaining = maxi(0, _release_cooldown_ticks_remaining - 1)
	if _release_cooldown_ticks_remaining <= 0:
		_change_state(State.CHASE)
	else:
		_tick_chase(agents)

func _check_senses(agents: Array) -> void:
	for agent in agents:
		if agent.get("_role") == "police" or not agent.get("is_active"):
			continue
		var apos : Vector2i = agent.get("grid_pos")
		var noise: int      = agent.get_effective_noise() if agent.has_method("get_effective_noise") else 4
		var dist : int      = absi(apos.x - grid_pos.x) + absi(apos.y - grid_pos.y)

		if dist <= NOISE_DETECT_RADIUS and noise > 0:
			if _state == State.PATROL or _state == State.IDLE:
				_alert_pos = apos
				_emit_spotted(agent)
				_change_state(State.ALERT)
				return

		if _can_see(apos):
			if _state != State.ALERT:
				_alert_pos = apos
				_emit_spotted(agent)
				_change_state(State.ALERT)
			return

func _try_latch_prisoner(agents: Array) -> bool:
	for agent in agents:
		if agent._role == "police" or not agent.is_active:
			continue
		var d: int = absi(agent.grid_pos.x - grid_pos.x) + absi(agent.grid_pos.y - grid_pos.y)
		if d <= LATCH_RANGE:
			_engage_latch(agent)
			return true
	return false

func _engage_latch(prisoner: Agent) -> void:
	if prisoner == null:
		return
	_latched_agent_id = prisoner.agent_id
	_latched_agent_ref = prisoner
	_latch_ticks_remaining = LATCH_DURATION_TICKS
	_release_cooldown_ticks_remaining = 0
	_change_state(State.LATCHED)
	prisoner.apply_effect(EffectDogPinned.new(LATCH_DURATION_TICKS, DOG_SLOW_MULTIPLIER))
	if prisoner.has_method("apply_temporary_slow"):
		prisoner.apply_temporary_slow("dog_latch", DOG_SLOW_MULTIPLIER)
	EventBus.emit_signal("dog_engaged_prisoner", prisoner.agent_id, LATCH_DURATION_TICKS)

func _release_latch(agents: Array) -> void:
	if _latched_agent_id >= 0:
		var prisoner: Agent = _find_prisoner_by_id(agents, _latched_agent_id)
		if prisoner != null and prisoner.has_method("remove_status"):
			prisoner.remove_status("dog_pinned")
		if prisoner != null and prisoner.has_method("clear_temporary_slow"):
			prisoner.clear_temporary_slow("dog_latch")
		EventBus.emit_signal("dog_released_prisoner", _latched_agent_id)
	_latched_agent_ref = null
	_latched_agent_id = -1
	_latch_ticks_remaining = 0
	_release_cooldown_ticks_remaining = RELEASE_COOLDOWN_TICKS
	_change_state(State.RELEASE_COOLDOWN)

func is_latching_agent(agent_id: int) -> bool:
	if _state != State.LATCHED:
		return false
	if _latch_ticks_remaining <= 0:
		return false
	return _latched_agent_id == agent_id

func is_latched() -> bool:
	return _state == State.LATCHED and _latched_agent_id >= 0 and _latch_ticks_remaining > 0

func get_latched_agent_id() -> int:
	return _latched_agent_id

func force_release_latch(agents: Array = []) -> void:
	if not is_latched():
		return
	var context_agents: Array = agents if not agents.is_empty() else _tick_agents
	_release_latch(context_agents)

func _find_prisoner_by_id(agents: Array, aid: int) -> Agent:
	for agent in agents:
		if agent.agent_id == aid:
			return agent
	return null

func _emit_spotted(agent: Node2D) -> void:
	if agent == null:
		return
	var aid: int = int(agent.get("agent_id"))
	var next_allowed: int = int(_spot_cooldown_by_agent.get(aid, -99999))
	if _tick_index < next_allowed:
		return
	_spot_cooldown_by_agent[aid] = _tick_index + 4
	EventBus.emit_signal("dog_spotted_prisoner", aid, agent.get("grid_pos"))

func _can_see(target: Vector2i) -> bool:
	if _grid == null:
		return false
	var dist: int = absi(target.x - grid_pos.x) + absi(target.y - grid_pos.y)
	if dist > 6:
		return false
	return _grid.raycast(grid_pos, target)

func _is_exit_tile(pos: Vector2i) -> bool:
	if pos in _exit_tiles:
		return true
	if _grid == null:
		return false
	var tile: GridTileData = _grid.get_tile(pos)
	if tile == null:
		return false
	return tile.interactable_type == GridTileData.INTERACTABLE_EXIT

func _step_toward(target: Vector2i) -> void:
	if _grid == null:
		return
	var path: Array[Vector2i] = _grid.astar(grid_pos, target)

	# Build a set of agent-occupied tiles for quick lookup
	var agent_occupied: Dictionary = {}
	for agent in _tick_agents:
		if agent.is_active:
			agent_occupied[agent.grid_pos] = true

	# Try the A* next step first; if blocked by an agent try cardinal neighbours
	var candidates: Array[Vector2i] = []
	if path.size() > 1:
		candidates.append(path[1])
	# Add all 4 cardinal neighbours as fallbacks (sorted by Manhattan dist to target)
	var dirs: Array[Vector2i] = [
		Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)
	]
	for d in dirs:
		var nb: Vector2i = grid_pos + d
		if nb != (path[1] if path.size() > 1 else Vector2i(-999,-999)):
			candidates.append(nb)

	for next_pos in candidates:
		if not _grid.is_walkable(next_pos):
			continue
		if _is_exit_tile(next_pos):
			continue
		if agent_occupied.has(next_pos):
			continue   # occupied by an active agent
		# Locked doors block the dog just like they block agents
		var door_blocked: bool = false
		for door in _doors:
			if door.grid_pos == next_pos and not door.is_passable():
				door_blocked = true
				break
		if door_blocked:
			continue
		# Valid step found
		var old_pos: Vector2i = grid_pos
		grid_pos    = next_pos
		var dir: Vector2i = grid_pos - old_pos
		if dir != Vector2i.ZERO:
			_facing = dir
		_visual_target_pos = Vector2(grid_pos.x * TILE_SIZE + TILE_SIZE / 2.0, grid_pos.y * TILE_SIZE + TILE_SIZE / 2.0)
		position = _visual_target_pos
		return
	# All moves blocked — dog stays put this tick

func _change_state(new_state: int) -> void:
	if _state == new_state:
		return
	var old_name: String = STATE_NAMES[_state]
	_state       = new_state
	_state_ticks = 0
	EventBus.emit_signal("dog_state_changed", 0, STATE_NAMES[_state])
	print("  DogNPC: %s → %s at %s" % [old_name, STATE_NAMES[_state], grid_pos])

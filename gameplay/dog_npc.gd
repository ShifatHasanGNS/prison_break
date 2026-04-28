extends Node2D
class_name DogNPC

enum State { IDLE, PATROL, ALERT, SNIFF, CHASE }
const STATE_NAMES: Array = ["IDLE", "PATROL", "ALERT", "SNIFF", "CHASE"]

const DANGER_RADIUS_PATROL: int = 2
const DANGER_RADIUS_ALERT : int = 3
const DANGER_RADIUS_CHASE : int = 4
const DANGER_VALUE        : float = 3.0

const IDLE_TICKS_BEFORE_PATROL : int = 3
const ALERT_TICKS_BEFORE_SNIFF : int = 3
const SNIFF_TICKS_BEFORE_PATROL: int = 5
const NOISE_DETECT_RADIUS      : int = 5

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
		position = Vector2(grid_pos.x * 48 + 24.0, grid_pos.y * 48 + 24.0)

	print("DogNPC: %d waypoints, starting at %s" % [_waypoints.size(), grid_pos])
	_change_state(State.PATROL)

## Called every tick from SimulationLoop._update_hazards().
func tick(agents: Array) -> void:
	_tick_agents = agents
	_state_ticks += 1

	match _state:
		State.IDLE:   _tick_idle()
		State.PATROL: _tick_patrol()
		State.ALERT:  _tick_alert(agents)
		State.SNIFF:  _tick_sniff()
		State.CHASE:  _tick_chase(agents)

	if _state != State.CHASE:
		_check_senses(agents)

func get_state_name() -> String:
	return STATE_NAMES[_state] if _state < STATE_NAMES.size() else "UNKNOWN"

## Seed danger tiles into DangerMap. Called from SimulationLoop._rebuild_maps().
func seed_danger(danger_map: DangerMap) -> void:
	var radius: int
	match _state:
		State.CHASE, State.ALERT: radius = DANGER_RADIUS_CHASE
		State.SNIFF:              radius = DANGER_RADIUS_ALERT
		_:                        radius = DANGER_RADIUS_PATROL

	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			danger_map.add(grid_pos + Vector2i(dx, dy), DANGER_VALUE)

# -------------------------------------------------------------------------
# Animation
# -------------------------------------------------------------------------

func _process(_delta: float) -> void:
	queue_redraw()

# =========================================================================
# DRAWING  (pixel-art dog)
# =========================================================================

func _draw() -> void:
	# Danger aura — drawn first in world space (no transform)
	var is_danger := _state == State.ALERT or _state == State.SNIFF or _state == State.CHASE
	if is_danger:
		var pulse  := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.004)
		var d_rad  := float((DANGER_RADIUS_CHASE if _state == State.CHASE else DANGER_RADIUS_ALERT) * 48)
		draw_circle(Vector2.ZERO, d_rad,
			Color(0.90, 0.15, 0.05, 0.06 + pulse * 0.05))
		draw_arc(Vector2.ZERO, d_rad, 0.0, TAU, 48,
			Color(0.90, 0.20, 0.05, 0.25 + pulse * 0.15), 1.5)

	# Mirror/rotate the dog body to face the movement direction.
	# Always drawn "facing right" internally.
	# Left-facing uses a horizontal flip (scale x=-1) instead of PI rotation,
	# which would flip both axes and render the dog upside-down.
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

	# Alert indicator drawn AFTER transform reset so text stays upright
	var is_alert := _state == State.ALERT or _state == State.CHASE
	var font := ThemeDB.fallback_font
	if is_alert and font != null:
		draw_string(font, Vector2(-4.0, -30.0), "!",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.00, 0.50, 0.10))

func _draw_dog_body() -> void:
	var t_ms := float(Time.get_ticks_msec())
	var is_alert := _state == State.ALERT or _state == State.CHASE
	var is_chase := _state == State.CHASE
	var lean := 3.0 if is_chase else 0.0
	var leg_anim := sin(t_ms * 0.012)
	var tail_lift := sin(t_ms * 0.008) * 3.0

	var outline := Color(0.08, 0.07, 0.06)
	var dark_fur := Color(0.18, 0.13, 0.08)
	var tan_fur := Color(0.73, 0.55, 0.30)
	var gold_fur := Color(0.88, 0.67, 0.34)
	var collar := Color(0.70, 0.08, 0.08)

	draw_line(Vector2(-17.0, -3.0), Vector2(-28.0, -11.0 + tail_lift), outline, 5)
	draw_line(Vector2(-17.0, -3.0), Vector2(-28.0, -11.0 + tail_lift), tan_fur, 3)

	draw_colored_polygon(PackedVector2Array([
		Vector2(-19.0 + lean, -11.0),
		Vector2(5.0 + lean, -14.0),
		Vector2(20.0 + lean, -6.0),
		Vector2(17.0 + lean, 10.0),
		Vector2(-17.0 + lean, 12.0),
		Vector2(-23.0 + lean, 1.0),
	]), outline)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-16.0 + lean, -8.0),
		Vector2(4.0 + lean, -11.0),
		Vector2(17.0 + lean, -4.0),
		Vector2(14.0 + lean, 8.0),
		Vector2(-14.0 + lean, 9.0),
		Vector2(-19.0 + lean, 1.0),
	]), tan_fur)

	draw_colored_polygon(PackedVector2Array([
		Vector2(-11.0 + lean, -9.0),
		Vector2(4.0 + lean, -11.0),
		Vector2(13.0 + lean, -5.0),
		Vector2(7.0 + lean, 2.0),
		Vector2(-13.0 + lean, 2.0),
	]), dark_fur)
	draw_rect(Rect2(12.0 + lean, -1.0, 5.0, 9.0), gold_fur)

	var leg_data := [
		[-13.0, 8.0 + leg_anim * 2.0],
		[-3.0, 9.0 - leg_anim * 2.0],
		[8.0, 8.0 - leg_anim * 2.0],
		[15.0, 7.0 + leg_anim * 2.0],
	]
	for leg in leg_data:
		var lx: float = float(leg[0]) + lean
		var ly: float = float(leg[1])
		draw_rect(Rect2(lx - 2.0, ly, 5.0, 11.0), outline)
		draw_rect(Rect2(lx - 1.0, ly, 3.0, 9.0), tan_fur)
		draw_rect(Rect2(lx - 3.0, ly + 8.0, 7.0, 4.0), outline)

	var head_x := 20.0 + lean
	draw_rect(Rect2(head_x - 5.0, -12.0, 4.0, 17.0), collar)
	draw_colored_polygon(PackedVector2Array([
		Vector2(head_x - 2.0, -19.0),
		Vector2(head_x + 10.0, -14.0),
		Vector2(head_x + 16.0, -4.0),
		Vector2(head_x + 9.0, 7.0),
		Vector2(head_x - 4.0, 3.0),
		Vector2(head_x - 8.0, -8.0),
	]), outline)
	draw_colored_polygon(PackedVector2Array([
		Vector2(head_x, -16.0),
		Vector2(head_x + 9.0, -12.0),
		Vector2(head_x + 13.0, -4.0),
		Vector2(head_x + 7.0, 4.0),
		Vector2(head_x - 3.0, 1.0),
		Vector2(head_x - 6.0, -8.0),
	]), gold_fur)
	draw_colored_polygon(PackedVector2Array([
		Vector2(head_x - 6.0, -14.0),
		Vector2(head_x - 3.0, -27.0),
		Vector2(head_x + 2.0, -14.0),
	]), outline)
	draw_colored_polygon(PackedVector2Array([
		Vector2(head_x + 3.0, -14.0),
		Vector2(head_x + 8.0, -26.0),
		Vector2(head_x + 11.0, -11.0),
	]), outline)
	draw_rect(Rect2(head_x + 11.0, -6.0, 9.0, 6.0), outline)
	draw_rect(Rect2(head_x + 11.0, -5.0, 6.0, 4.0), gold_fur)
	draw_rect(Rect2(head_x + 18.0, -5.0, 4.0, 3.0), Color(0.02, 0.02, 0.02))
	if is_chase:
		draw_rect(Rect2(head_x + 13.0, 0.0, 7.0, 3.0), Color(0.55, 0.04, 0.04))

	var eye_col := Color(1.0, 0.16, 0.08) if is_alert else Color(0.98, 0.92, 0.70)
	draw_rect(Rect2(head_x + 6.0, -10.0, 4.0, 4.0), outline)
	draw_rect(Rect2(head_x + 7.0, -9.0, 2.0, 2.0), eye_col)

func _draw_dog_body_old() -> void:
	# All coordinates are in "facing-right" space; rotation is applied by caller.
	var t_ms     := float(Time.get_ticks_msec())
	var is_alert := _state == State.ALERT or _state == State.CHASE
	var is_chase := _state == State.CHASE
	var lean     := 3.0 if is_chase else 0.0
	var tail_wag := sin(t_ms * 0.008) * 5.0
	var leg_anim := sin(t_ms * 0.012)   # -1 to +1

	# --- Tail (left/back of body) ---
	var tail_base := Vector2(-18.0, 3.0)
	var tail_tip  := tail_base + Vector2(-12.0, -6.0 + tail_wag)
	draw_line(tail_base, tail_tip, Color(0.60, 0.46, 0.26), 3)

	# --- Body (tan rect, 38×26) ---
	draw_rect(Rect2(-19.0 + lean, -13.0, 38.0, 26.0), Color(0.76, 0.62, 0.38))

	# --- Legs (4 small rects, alternating-pair animation) ---
	var ll := leg_anim * 2.5
	var lr := -leg_anim * 2.5
	var leg_col := Color(0.60, 0.46, 0.26)
	draw_rect(Rect2(-13.0, 12.0, 5.0, maxf(4.0, 9.0 + ll)), leg_col)
	draw_rect(Rect2( -4.0, 12.0, 5.0, maxf(4.0, 9.0 + lr)), leg_col)
	draw_rect(Rect2(  5.0, 12.0, 5.0, maxf(4.0, 9.0 + lr)), leg_col)
	draw_rect(Rect2( 12.0, 12.0, 5.0, maxf(4.0, 9.0 + ll)), leg_col)

	# --- Head (lighter circle, offset forward) ---
	var head_pos := Vector2(16.0 + lean, -4.0)
	draw_circle(head_pos, 13.0, Color(0.82, 0.68, 0.44))

	# --- Ears (two dark triangles on top of head) ---
	var ear_col := Color(0.30, 0.22, 0.12)
	var hx := head_pos.x
	var hy := head_pos.y - 13.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(hx - 7.0, hy),
		Vector2(hx - 2.0, hy - 9.0),
		Vector2(hx + 1.0, hy),
	]), ear_col)
	draw_colored_polygon(PackedVector2Array([
		Vector2(hx + 2.0, hy),
		Vector2(hx + 6.0, hy - 9.0),
		Vector2(hx + 9.0, hy),
	]), ear_col)

	# --- Snout (small rect protruding forward) ---
	var snout_col := Color(0.72, 0.58, 0.38)
	draw_rect(Rect2(head_pos.x + 10.0, head_pos.y - 1.0, 8.0, 5.0), snout_col)
	if is_chase:
		# Open mouth gap in CHASE state
		draw_rect(Rect2(head_pos.x + 11.0, head_pos.y + 1.0, 6.0, 4.0),
			Color(0.50, 0.10, 0.10))

	# --- Eyes ---
	var eye_col   := Color(0.90, 0.10, 0.10) if is_alert else Color.WHITE
	var pupil_col := Color(0.05, 0.05, 0.05)
	var eye_pos   := Vector2(head_pos.x + 5.0, head_pos.y - 3.0)
	draw_circle(eye_pos, 4.0, eye_col)
	draw_circle(eye_pos + Vector2(1.5, 0.0), 2.0, pupil_col)

# -------------------------------------------------------------------------
# State machine
# -------------------------------------------------------------------------

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
				_change_state(State.ALERT)
				return

		if _can_see(apos):
			if _state != State.ALERT:
				_alert_pos = apos
				_change_state(State.ALERT)
			return

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
	var tile = _grid.get_tile(pos)
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
		var nb := grid_pos + d
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
		var old_pos := grid_pos
		grid_pos    = next_pos
		var dir := grid_pos - old_pos
		if dir != Vector2i.ZERO:
			_facing = dir
		position = Vector2(grid_pos.x * 48 + 24.0, grid_pos.y * 48 + 24.0)
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

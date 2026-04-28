# UPDATED — cinematic CCTV rendering while preserving detection logic
extends Node2D
class_name CCTVCameraSystem

const TILE_SIZE: int = 48
const DETECTED_TICKS: int = 2
const CAMERA_STAMINA_PENALTY: float = 5.0
const DETECTION_COOLDOWN_TICKS: int = 4
const TARGET_CAMERA_COUNT: int = 3

var _grid: GridEngine = null
var _cameras: Array = []
var _logs: Array = []
var _recent_events: Array = []
var _agent_detection_counts: Dictionary = {}
var _last_visibility: Dictionary = {}
var _next_detect_tick: Dictionary = {}
var _tick: int = 0
var _visual_angles: Dictionary = {}

func setup(camera_data: Array, grid: GridEngine) -> void:
	_grid = grid
	_cameras.clear()
	var normalized_data: Array = _normalize_camera_data(camera_data)
	var idx: int = 0
	for cam in normalized_data:
		var pos: Vector2i = cam.get("pos", Vector2i.ZERO)
		var facing: Vector2i = cam.get("facing", Vector2i.RIGHT)
		_cameras.append({
			"id": idx,
			"pos": pos,
			"facing": facing,
			"base_facing": facing,
			"range": int(cam.get("range", 6)),
			"fov_deg": float(cam.get("fov_deg", 72.0)),
			"rotates": bool(cam.get("rotates", true)),
			"sweep_interval": int(cam.get("sweep_interval", 3)),
			"visible_targets": [],
		})
		_visual_angles[idx] = _dir_to_angle(facing)
		idx += 1
	z_index = 1
	queue_redraw()

func _normalize_camera_data(camera_data: Array) -> Array:
	var out: Array = []
	for i in range(mini(TARGET_CAMERA_COUNT, camera_data.size())):
		out.append(camera_data[i])

	if out.size() >= TARGET_CAMERA_COUNT:
		return out

	var fallback_positions: Array[Vector2i] = [
		Vector2i(4, 4),
		Vector2i(23, 4),
		Vector2i(14, 10),
		Vector2i(4, 15),
		Vector2i(23, 15),
	]
	var used_positions: Dictionary = {}
	for cam in out:
		var p: Vector2i = cam.get("pos", Vector2i.ZERO)
		used_positions[p] = true

	for fp in fallback_positions:
		if out.size() >= TARGET_CAMERA_COUNT:
			break
		if used_positions.has(fp):
			continue
		if _grid != null and _grid.get_tile(fp) != null and _grid.is_walkable(fp):
			out.append({
				"pos": fp,
				"facing": Vector2i.RIGHT,
				"range": 6,
				"fov_deg": 78.0,
				"rotates": true,
				"sweep_interval": 3,
			})
			used_positions[fp] = true

	if out.size() >= TARGET_CAMERA_COUNT:
		return out

	if _grid != null:
		for y in range(1, 19):
			for x in range(1, 27):
				if out.size() >= TARGET_CAMERA_COUNT:
					break
				var pos: Vector2i = Vector2i(x, y)
				if used_positions.has(pos):
					continue
				if _grid.get_tile(pos) == null or not _grid.is_walkable(pos):
					continue
				out.append({
					"pos": pos,
					"facing": Vector2i.RIGHT,
					"range": 6,
					"fov_deg": 78.0,
					"rotates": true,
					"sweep_interval": 3,
				})
				used_positions[pos] = true
			if out.size() >= TARGET_CAMERA_COUNT:
				break

	return out

func tick(agents: Array, tick: int) -> void:
	_tick = tick
	_recent_events.clear()
	for i in range(_cameras.size()):
		var cam: Dictionary = _cameras[i]
		_update_camera_facing(cam, tick)
		cam["visible_targets"] = []
		for agent in agents:
			if agent._role == "police" or not agent.is_active:
				continue
			var visible: bool = _camera_sees_tile(cam, agent.grid_pos)
			var key: String = "%d:%d" % [int(cam["id"]), agent.agent_id]
			var was_visible: bool = bool(_last_visibility.get(key, false))
			var next_tick: int = int(_next_detect_tick.get(key, -99999))
			if visible:
				cam["visible_targets"].append(agent.agent_id)
				if not was_visible and _tick >= next_tick:
					_apply_detection(cam, agent)
					_emit_camera_event(cam, agent, true)
					_next_detect_tick[key] = _tick + DETECTION_COOLDOWN_TICKS
			elif was_visible:
				_emit_camera_event(cam, agent, false)
			_last_visibility[key] = visible
		_cameras[i] = cam
	EventBus.emit_signal("camera_sweep_updated", get_camera_states())
	queue_redraw()

func seed_danger(danger_map: DangerMap) -> void:
	for cam in _cameras:
		for tile in _get_visible_tiles(cam):
			var existing: float = danger_map.get_danger(tile)
			var dist: int = maxi(1, _manhattan(cam["pos"], tile))
			var add: float = 5.5 - float(dist) * 0.55
			if add > existing:
				danger_map.set_danger(tile, add)

func get_recent_events(limit: int = 6) -> Array:
	var out: Array = []
	for i in range(mini(limit, _logs.size())):
		out.append(_logs[_logs.size() - 1 - i])
	return out

func get_camera_states() -> Array:
	var states: Array = []
	for cam in _cameras:
		states.append({
			"id": cam["id"],
			"pos": cam["pos"],
			"facing": cam["facing"],
			"range": cam["range"],
			"fov_deg": cam["fov_deg"],
			"visible_targets": cam["visible_targets"].duplicate(),
		})
	return states

func get_agent_detection_counts() -> Dictionary:
	return _agent_detection_counts.duplicate()

func _apply_detection(cam: Dictionary, agent: Agent) -> void:
	var effect: EffectDetected = EffectDetected.new()
	effect.refresh(DETECTED_TICKS)
	agent.apply_effect(effect)
	agent.stamina = maxf(0.0, agent.stamina - CAMERA_STAMINA_PENALTY)
	_agent_detection_counts[agent.agent_id] = int(_agent_detection_counts.get(agent.agent_id, 0)) + 1

func _emit_camera_event(cam: Dictionary, agent: Agent, visible: bool) -> void:
	var detail: Dictionary = {
		"tick": _tick,
		"camera_id": cam["id"],
		"camera_pos": cam["pos"],
		"agent_id": agent.agent_id,
		"agent_role": agent._role,
		"visible": visible,
	}
	_logs.append(detail)
	if _logs.size() > 64:
		_logs.pop_front()
	_recent_events.append(detail)
	EventBus.emit_signal("camera_detection", cam["id"], agent.agent_id, visible, agent.grid_pos, detail)

func _update_camera_facing(cam: Dictionary, tick: int) -> void:
	if not bool(cam.get("rotates", true)):
		cam["facing"] = cam.get("base_facing", cam.get("facing", Vector2i.RIGHT))
		return
	var dirs: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	var current: Vector2i = cam.get("base_facing", Vector2i.RIGHT)
	var start_idx: int = 0
	for i in range(dirs.size()):
		if dirs[i] == current:
			start_idx = i
			break
	var interval: int = maxi(1, int(cam.get("sweep_interval", 3)))
	var step: int = int(floor(float(tick) / float(interval))) % dirs.size()
	cam["facing"] = dirs[(start_idx + step) % dirs.size()]

func _camera_sees_tile(cam: Dictionary, tile: Vector2i) -> bool:
	var origin: Vector2i = cam["pos"]
	if tile == origin:
		return true
	var dist: int = _manhattan(origin, tile)
	if dist > int(cam.get("range", 6)):
		return false
	if _grid != null and not _grid.raycast(origin, tile):
		return false
	var dir: Vector2 = Vector2(tile - origin)
	if dir == Vector2.ZERO:
		return true
	var facing: Vector2 = Vector2(cam.get("facing", Vector2i.RIGHT))
	var angle_deg: float = rad_to_deg(acos(clampf(facing.normalized().dot(dir.normalized()), -1.0, 1.0)))
	return angle_deg <= float(cam.get("fov_deg", 72.0)) * 0.5

func _get_visible_tiles(cam: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var origin: Vector2i = cam["pos"]
	var r: int = int(cam.get("range", 6))
	for y in range(origin.y - r, origin.y + r + 1):
		for x in range(origin.x - r, origin.x + r + 1):
			var pos: Vector2i = Vector2i(x, y)
			if _grid == null or _grid.get_tile(pos) == null:
				continue
			if _camera_sees_tile(cam, pos):
				out.append(pos)
	return out

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _process(delta: float) -> void:
	for cam in _cameras:
		var cam_id: int = int(cam.get("id", 0))
		var target_angle: float = _dir_to_angle(cam.get("facing", Vector2i.RIGHT))
		var current_angle: float = float(_visual_angles.get(cam_id, target_angle))
		_visual_angles[cam_id] = lerp_angle(current_angle, target_angle, minf(1.0, delta * 8.0))
	queue_redraw()

func _draw() -> void:
	for cam in _cameras:
		_draw_camera_cone(cam)
	for cam in _cameras:
		_draw_camera_body(cam)

func _draw_camera_cone(cam: Dictionary) -> void:
	var tiles: Array[Vector2i] = _get_visible_tiles(cam)
	var hot: bool = not Array(cam.get("visible_targets", [])).is_empty()
	var base_col: Color = Color(0.00, 0.92, 0.58, 0.07) if not hot else Color(1.00, 0.32, 0.18, 0.09)

	for tile in tiles:
		var rect: Rect2 = Rect2(float(tile.x * TILE_SIZE) + 4.0, float(tile.y * TILE_SIZE) + 4.0, TILE_SIZE - 8.0, TILE_SIZE - 8.0)
		draw_rect(rect, base_col)
		if tile != cam["pos"]:
			draw_rect(rect, Color(base_col.r, base_col.g, base_col.b, 0.028), false)

	var origin: Vector2 = _tile_center(cam["pos"])
	var cam_id: int = int(cam.get("id", 0))
	var angle: float = float(_visual_angles.get(cam_id, _dir_to_angle(cam.get("facing", Vector2i.RIGHT))))
	var fov: float = deg_to_rad(float(cam.get("fov_deg", 72.0)))
	var reach: float = float(cam.get("range", 6)) * float(TILE_SIZE) * 0.72
	var wobble: float = sin(float(Time.get_ticks_msec()) * 0.0035 + float(cam.get("id", 0)) * 1.2) * 0.10
	var start_ang: float = angle - fov * 0.5 + wobble
	var end_ang: float = angle + fov * 0.5 + wobble

	var cone: PackedVector2Array = PackedVector2Array([origin])
	for i in range(16):
		var a: float = lerpf(start_ang, end_ang, float(i) / 15.0)
		cone.append(origin + Vector2(cos(a), sin(a)) * reach)
	draw_colored_polygon(cone, Color(base_col.r, base_col.g, base_col.b, 0.06))

	draw_line(origin, origin + Vector2(cos(start_ang), sin(start_ang)) * reach, Color(base_col.r, base_col.g, base_col.b, 0.32), 1.4)
	draw_line(origin, origin + Vector2(cos(end_ang), sin(end_ang)) * reach, Color(base_col.r, base_col.g, base_col.b, 0.32), 1.4)
	draw_line(origin, origin + Vector2(cos(angle + wobble), sin(angle + wobble)) * reach, Color(0.80, 1.00, 0.94, 0.30 if not hot else 0.56), 2.2)

	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006 + float(cam.get("id", 0)))
	for i in range(4):
		var rr: float = 12.0 + float(i) * 8.0 + pulse * 2.0
		draw_arc(origin, rr, 0.0, TAU, 18, Color(base_col.r, base_col.g, base_col.b, 0.05 - float(i) * 0.01), 1.0)

func _draw_camera_body(cam: Dictionary) -> void:
	var center: Vector2 = _tile_center(cam["pos"])
	var cam_id: int = int(cam.get("id", 0))
	var body_angle: float = float(_visual_angles.get(cam_id, _dir_to_angle(cam.get("facing", Vector2i.RIGHT))))
	var facing: Vector2 = Vector2(cos(body_angle), sin(body_angle))
	var tip: Vector2 = center + facing * 15.0
	var hot: bool = not Array(cam.get("visible_targets", [])).is_empty()
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.005 + float(cam.get("id", 0)))

	draw_circle(center, 15.0 + pulse * 2.0, Color(0.00, 0.95, 0.65, 0.05 if not hot else 0.09))
	draw_circle(center, 10.0, Color(0.04, 0.10, 0.12, 0.98))
	draw_circle(center, 6.2, Color(0.10, 0.94, 0.72, 0.92) if not hot else Color(1.0, 0.38, 0.18, 0.92))
	draw_line(center, tip, Color(0.78, 0.96, 1.0, 0.92), 3.0)
	draw_rect(Rect2(center.x - 5.0, center.y + 8.0, 10.0, 6.0), Color(0.06, 0.12, 0.16, 0.95))
	draw_arc(center, 14.0, 0.0, TAU, 18, Color(0.50, 0.78, 0.86, 0.28), 1.0)
	if hot:
		draw_arc(center, 18.0, 0.0, TAU, 22, Color(1.0, 0.32, 0.18, 0.82), 2.0)
	var font: Font = ThemeDB.fallback_font
	if font != null:
		draw_string(font, center + Vector2(-8.0, -12.0), str(int(cam.get("id", 0)) + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.90, 1.0, 0.95, 0.72))

func _tile_center(pos: Vector2i) -> Vector2:
	return Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + TILE_SIZE * 0.5)

func _dir_to_angle(dir: Vector2i) -> float:
	var v: Vector2 = Vector2(dir)
	if v == Vector2.ZERO:
		v = Vector2.RIGHT
	v = v.normalized()
	return atan2(v.y, v.x)

extends RefCounted
class_name ReplayExporter

var _header: Dictionary = {}
var _snapshots: Array = []

func start_recording(map_data: Dictionary, seed_val: int) -> void:
	_snapshots.clear()
	_header = {
		"seed": seed_val,
		"fire_tiles": _vec2i_array_to_json(map_data.get("fire_tiles", [])),
		"door_tiles": _vec2i_array_to_json(map_data.get("door_tiles", [])),
		"exits": _vec2i_array_to_json(map_data.get("exits", [])),
		"dog_waypoints": _vec2i_array_to_json(map_data.get("dog_waypoints", [])),
		"red_spawn": _v2i(map_data.get("red_spawn", Vector2i.ZERO)),
		"blue_spawn": _v2i(map_data.get("blue_spawn", Vector2i.ZERO)),
		"police_spawn": _v2i(map_data.get("police_spawn", Vector2i.ZERO)),
		"camera_tiles": _camera_array_to_json(map_data.get("camera_tiles", [])),
	}

func record_snapshot(n: int, agents: Array, dog_pos: Vector2i, dog_state: String, active_exit: Vector2i, camera_states: Array = []) -> void:
	var agent_arr: Array = []
	for agent in agents:
		agent_arr.append({
			"id": agent.agent_id,
			"role": agent._role,
			"x": agent.grid_pos.x,
			"y": agent.grid_pos.y,
			"hp": snappedf(agent.health, 0.1),
			"stamina": snappedf(agent.stamina, 0.1),
			"active": agent.is_active,
			"captures": agent.capture_count,
			"camera_hits": int(agent.metrics.get("camera_hits", 0)),
		})
	_snapshots.append({
		"tick": n,
		"agents": agent_arr,
		"dog_x": dog_pos.x,
		"dog_y": dog_pos.y,
		"dog_state": dog_state,
		"exit_x": active_exit.x,
		"exit_y": active_exit.y,
		"cameras": _camera_array_to_json(camera_states),
	})

func export_to_file(path: String) -> bool:
	var data := {"header": _header, "snapshots": _snapshots}
	var text := JSON.stringify(data)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ReplayExporter: cannot write to %s (err %d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(text)
	f.close()
	print("ReplayExporter: saved %d snapshots to %s" % [_snapshots.size(), path])
	return true

func get_snapshot_count() -> int:
	return _snapshots.size()

func get_header() -> Dictionary:
	return _header.duplicate()

func _v2i(v: Vector2i) -> Dictionary:
	return {"x": v.x, "y": v.y}

func _vec2i_array_to_json(arr: Array) -> Array:
	var out: Array = []
	for item in arr:
		var v: Vector2i = item as Vector2i
		out.append({"x": v.x, "y": v.y})
	return out

func _camera_array_to_json(arr: Array) -> Array:
	var out: Array = []
	for item in arr:
		var pos: Variant = item.get("pos", Vector2i.ZERO)
		var facing: Variant = item.get("facing", Vector2i.RIGHT)
		out.append({
			"id": item.get("id", 0),
			"pos": _v2i(pos),
			"facing": _v2i(facing),
			"range": item.get("range", 0),
			"fov_deg": item.get("fov_deg", 0.0),
			"visible_targets": item.get("visible_targets", []),
		})
	return out

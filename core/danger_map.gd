extends RefCounted
class_name DangerMap

var _values: Dictionary = {}  # Vector2i -> float

func reset() -> void:
	_values.clear()

func add(pos: Vector2i, val: float) -> void:
	_values[pos] = _values.get(pos, 0.0) + val

func set_danger(pos: Vector2i, val: float) -> void:
	_values[pos] = val

func get_danger(pos: Vector2i) -> float:
	return _values.get(pos, 0.0)

func get_all() -> Dictionary:
	return _values

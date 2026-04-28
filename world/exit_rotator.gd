extends Node
class_name ExitRotator

var _exits: Array[Vector2i] = []
var _active_exit: Vector2i = Vector2i(-1, -1)
var _timer: float = 0.0
var _rotation_interval: float = 6.0

# -------------------------------------------------------------------------

func setup(exits: Array) -> void:
	_exits.clear()
	for ex in exits:
		_exits.append(ex as Vector2i)

	if _exits.is_empty():
		push_warning("ExitRotator: no exits provided")
		return

	# Randomly designate initial active exit
	_active_exit = SimRandom.choice(_exits)
	_rotation_interval = SimRandom.randf_range(5.0, 7.0)

	EventBus.emit_signal("exit_activated", _active_exit)

	var decoys: Array[Vector2i] = _exits.filter(func(e): return e != _active_exit)
	print("ExitRotator: active=%s  decoys=%s  (next rotation in %.1fs)" % [
		_active_exit, decoys, _rotation_interval
	])

func get_active_exit() -> Vector2i:
	return _active_exit

func get_exits() -> Array[Vector2i]:
	return _exits

func get_time_remaining() -> float:
	return maxf(0.0, _rotation_interval - _timer)

func is_active_exit(pos: Vector2i) -> bool:
	return pos == _active_exit

func is_decoy_exit(pos: Vector2i) -> bool:
	return pos in _exits and pos != _active_exit

# -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _exits.size() < 2:
		return
	_advance(_timer + delta)

## Called by BenchmarkRunner to drive exit rotation without _process.
func advance_time(dt: float) -> void:
	if _exits.size() < 2:
		return
	_advance(_timer + dt)

func _advance(new_timer: float) -> void:
	_timer = new_timer
	if _timer >= _rotation_interval - 0.001:
		_timer -= _rotation_interval
		if _timer < 0.0:
			_timer = 0.0
		_rotate()

func _rotate() -> void:
	var old_exit: Vector2i = _active_exit

	# Pick a different exit — never the same as current (spec: "never same twice in a row")
	var candidates: Array[Vector2i] = []
	for ex: Vector2i in _exits:
		if ex != _active_exit:
			candidates.append(ex)
	if candidates.is_empty():
		return

	_active_exit = SimRandom.choice(candidates)
	_rotation_interval = SimRandom.randf_range(5.0, 7.0)

	EventBus.emit_signal("exit_deactivated", old_exit)
	EventBus.emit_signal("exit_activated", _active_exit)

	print("ExitRotator: deactivated %s → activated %s  (next in %.1fs)" % [
		old_exit, _active_exit, _rotation_interval
	])

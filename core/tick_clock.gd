extends Node
class_name TickClock

signal tick_fired(n: int)

var ticks_per_second: float = 4.0

var _tick_count: int = 0
var _accumulator: float = 0.0
var _paused: bool = false
var _step_pending: bool = false

func _process(delta: float) -> void:
	if _step_pending:
		_step_pending = false
		_fire_tick()
		return

	if _paused:
		return

	_accumulator += delta
	var interval: float = 1.0 / ticks_per_second
	while _accumulator >= interval:
		_accumulator -= interval
		_fire_tick()

func _fire_tick() -> void:
	_tick_count += 1
	EventBus.emit_signal("tick_started", _tick_count)
	emit_signal("tick_fired", _tick_count)
	EventBus.emit_signal("tick_ended", _tick_count)

func pause() -> void:
	_paused = true
	_accumulator = 0.0

func resume() -> void:
	_paused = false
	_accumulator = 0.0

func step_once() -> void:
	if _paused:
		_step_pending = true

func get_tick_count() -> int:
	return _tick_count

func is_paused() -> bool:
	return _paused

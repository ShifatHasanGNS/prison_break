extends RefCounted
class_name StatusEffect

var effect_name: String = ""
var _ticks_remaining: int = -1  # -1 = condition-based, never expires by count

func _init(name: String, duration: int = -1) -> void:
	effect_name = name
	_ticks_remaining = duration

## Called once when the effect is first applied to an agent.
func on_apply(agent: Node2D) -> void:
	pass

## Called once when the effect expires or is manually removed.
func on_remove(agent: Node2D) -> void:
	pass

## Called every tick while active. Apply per-tick consequences here.
## Base implementation counts down duration; override to add extra behaviour.
func apply_tick(agent: Node2D) -> void:
	if _ticks_remaining > 0:
		_ticks_remaining -= 1

## Returns true when the effect should be removed.
## Override for condition-based expiry (e.g. Exhausted checks stamina).
func is_expired(agent: Node2D) -> bool:
	return _ticks_remaining == 0

## Refresh duration without double-applying on_apply.
func refresh(duration: int = -1) -> void:
	if duration >= 0:
		_ticks_remaining = duration

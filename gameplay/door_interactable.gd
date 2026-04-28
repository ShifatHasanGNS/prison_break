extends RefCounted
class_name DoorInteractable

enum State { LOCKED, UNLOCKED, OPENING, OPEN }

const STATE_NAMES: Array = ["locked", "unlocked", "opening", "open"]

var grid_pos: Vector2i = Vector2i.ZERO
var _state: int = State.LOCKED
var _grid: Node = null
var _open_ticks: int = 0  # counts down while opening

# -------------------------------------------------------------------------

func setup(pos: Vector2i, grid: Node) -> void:
	grid_pos = pos
	_grid = grid
	_apply_state_to_tile()
	EventBus.emit_signal("door_state_changed", grid_pos, STATE_NAMES[_state])
	print("Door placed at %s (locked)" % grid_pos)

func get_state() -> String:
	return STATE_NAMES[_state]

func get_state_enum() -> int:
	return _state

## Returns true if an agent may move through this tile right now.
func is_passable() -> bool:
	return _state != State.LOCKED

## Try to interact: locked → start opening (takes 3 ticks for normal agents).
## Red's ForceDoor ability calls force_open() to bypass the delay.
func interact(agent: Node2D) -> void:
	if _state == State.LOCKED:
		_set_state(State.UNLOCKED)

## Immediately break open (used by ForceDoor ability).
func force_open() -> void:
	if _state == State.LOCKED or _state == State.UNLOCKED:
		_set_state(State.OPEN)

func tick() -> void:
	if _state == State.UNLOCKED:
		_open_ticks += 1
		if _open_ticks >= 3:
			_set_state(State.OPENING)
	elif _state == State.OPENING:
		_set_state(State.OPEN)

# -------------------------------------------------------------------------

func _set_state(new_state: int) -> void:
	if _state == new_state:
		return
	_state = new_state
	_open_ticks = 0
	_apply_state_to_tile()
	EventBus.emit_signal("door_state_changed", grid_pos, STATE_NAMES[_state])
	print("  Door %s → %s" % [grid_pos, STATE_NAMES[_state]])

func _apply_state_to_tile() -> void:
	if _grid == null:
		return
	var tile: GridTileData = _grid.get_tile(grid_pos)
	if tile == null:
		return
	match _state:
		State.LOCKED:
			# walkable=true so A* routes through when no alternative (AI Robustness Contract)
			# Actual movement is blocked in SimulationLoop._resolve_actions() via is_passable()
			tile.walkable = true
			tile.visibility_block = true
			tile.movement_cost = 9
		State.UNLOCKED, State.OPENING:
			tile.walkable = true
			tile.visibility_block = false
			tile.movement_cost = 9
		State.OPEN:
			tile.walkable = true
			tile.visibility_block = false
			tile.movement_cost = 1

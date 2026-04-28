extends Node2D
class_name PathOverlay

## Draws the current A* planned path from each agent to the active exit.
## World-space Node2D — coordinates match GridRenderer exactly.
## Toggle visibility with F1 via OverlayManager.

const TILE_SIZE: int = 48
const HALF: float    = TILE_SIZE / 2.0

# Per-role draw colours (semi-transparent so game is still visible)
const COL_RED    := Color(0.94, 0.27, 0.27, 0.85)
const COL_BLUE   := Color(0.38, 0.65, 0.98, 0.85)
const COL_POLICE := Color(0.23, 0.51, 0.96, 0.85)

var _grid         : GridEngine  = null
var _exit_rotator : ExitRotator = null
var _agents       : Array       = []

# Cached paths: agent_id → Array[Vector2i]
var _paths: Dictionary = {}

# -------------------------------------------------------------------------

func setup(agents: Array, grid: GridEngine, exit_rotator: ExitRotator) -> void:
	_agents       = agents
	_grid         = grid
	_exit_rotator = exit_rotator

	EventBus.agent_moved.connect(_on_agent_moved)
	EventBus.exit_activated.connect(_on_exit_changed)

	# Compute initial paths
	_refresh_all()

# -------------------------------------------------------------------------

func _on_agent_moved(id: int, _from: Vector2i, to: Vector2i) -> void:
	_refresh_for_agent_id(id, to)
	if visible:
		queue_redraw()

func _on_exit_changed(_tile: Vector2i) -> void:
	_refresh_all()
	if visible:
		queue_redraw()

func _refresh_all() -> void:
	for agent in _agents:
		_refresh_for_agent_id(agent.agent_id, agent.grid_pos)

func _refresh_for_agent_id(id: int, from_pos: Vector2i) -> void:
	if _grid == null or _exit_rotator == null:
		_paths[id] = []
		return
	var active_exit: Vector2i = _exit_rotator.get_active_exit()
	if active_exit.x < 0:
		_paths[id] = []
		return
	var path: Array[Vector2i] = _grid.astar(from_pos, active_exit)
	_paths[id] = path

# -------------------------------------------------------------------------

func _draw() -> void:
	for agent in _agents:
		if not agent.is_active:
			continue
		var path = _paths.get(agent.agent_id, [])
		if path.size() < 2:
			continue

		var col: Color
		match agent._role:
			"rusher_red":  col = COL_RED
			"sneaky_blue": col = COL_BLUE
			_:             col = COL_POLICE   # police + fallback

		# Dashed line: draw even-index segments, skip odd
		for i in range(path.size() - 1):
			if i % 2 == 0:
				var a := _tile_centre(path[i])
				var b := _tile_centre(path[i + 1])
				draw_line(a, b, col, 2.5)

		# Directional arrow ticks every 3 steps
		for i in range(2, path.size() - 1, 3):
			var a    := _tile_centre(path[i - 1])
			var b    := _tile_centre(path[i])
			var dir  := (b - a).normalized()
			if dir == Vector2.ZERO:
				continue
			var perp := Vector2(-dir.y, dir.x)
			var tip  := b
			var al   := 5.0   # arrow half-width
			var ab   := 9.0   # arrow tail length
			draw_colored_polygon(PackedVector2Array([
				tip,
				tip - dir * ab + perp * al,
				tip - dir * ab - perp * al,
			]), Color(col.r, col.g, col.b, 0.70))

		# Small dot at each waypoint (skip first — agent is already drawn there)
		for i in range(1, path.size()):
			draw_circle(_tile_centre(path[i]), 3.0, Color(col.r, col.g, col.b, 0.65))

		# Larger arrowhead at final destination
		var last := _tile_centre(path[path.size() - 1])
		draw_circle(last, 7.0, col)
		draw_circle(last, 5.0, Color(col.r, col.g, col.b, 0.40))

func _tile_centre(p: Vector2i) -> Vector2:
	return Vector2(p.x * TILE_SIZE + HALF, p.y * TILE_SIZE + HALF)

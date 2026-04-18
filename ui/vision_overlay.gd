extends Node2D
class_name VisionOverlay

## Draws filled polygon vision cones for each agent via ray-marching.
## World-space Node2D — coordinates match GridRenderer exactly.
## Toggle visibility with F2 via OverlayManager.

const TILE_SIZE : int   = 48
const RAY_COUNT : int   = 96     # rays cast per agent (more = smoother cone)
const RAY_STEP  : float = 0.45   # march step size in tile units

const COL_RED    := Color(0.94, 0.27, 0.27)
const COL_BLUE   := Color(0.38, 0.65, 0.98)
const COL_POLICE := Color(0.23, 0.51, 0.96)

var _grid   : GridEngine = null
var _agents : Array      = []

# -------------------------------------------------------------------------

func setup(agents: Array, grid: GridEngine) -> void:
	_agents = agents
	_grid   = grid
	EventBus.tick_ended.connect(_on_tick_ended)

func _on_tick_ended(_n: int) -> void:
	if visible:
		queue_redraw()

# -------------------------------------------------------------------------

func _draw() -> void:
	if _grid == null:
		return

	for agent in _agents:
		if not agent.is_active:
			continue
		var col: Color
		match agent._role:
			"rusher_red":  col = COL_RED
			"sneaky_blue": col = COL_BLUE
			_:             col = COL_POLICE
		_draw_cone(agent, col)

func _draw_cone(agent, base_col: Color) -> void:
	var T        := float(TILE_SIZE)
	var v_range  := float(agent.stats.vision_range if agent.stats != null else 5)
	# Extend slightly beyond vision range so edges look clean
	var max_dist := v_range * T + T * 0.5
	var center   := Vector2(
		(agent.grid_pos.x + 0.5) * T,
		(agent.grid_pos.y + 0.5) * T
	)

	var pts   := PackedVector2Array()
	var cols  := PackedColorArray()
	var fill  := Color(base_col.r, base_col.g, base_col.b, 0.13)
	pts.append(center)
	cols.append(fill)

	var steps_per_ray := int(max_dist / (RAY_STEP * T)) + 2

	for i in range(RAY_COUNT + 1):
		var angle := float(i) / float(RAY_COUNT) * TAU
		var dir   := Vector2(cos(angle), sin(angle))
		var hit   := center + dir * max_dist   # default: full range

		for s in range(1, steps_per_ray + 1):
			var dist   := float(s) * RAY_STEP * T
			var sample := center + dir * dist
			# Convert to tile coordinates (floor division)
			var tx := int(sample.x / T)
			var ty := int(sample.y / T)
			var tile := _grid.get_tile(Vector2i(tx, ty))
			if tile == null or not tile.walkable:
				# Stop just before the wall
				hit = center + dir * maxf(0.0, dist - RAY_STEP * T)
				break
			if dist >= max_dist:
				hit = center + dir * max_dist
				break

		pts.append(hit)
		cols.append(fill)

	# Filled cone polygon
	draw_colored_polygon(pts, fill)

	# Soft boundary outline (skip index 0 = center)
	for i in range(1, pts.size() - 1):
		draw_line(pts[i], pts[i + 1],
			Color(base_col.r, base_col.g, base_col.b, 0.22), 1.0)

	# Bright origin ring marking agent position
	draw_arc(center, T * 0.28, 0.0, TAU, 24,
		Color(base_col.r, base_col.g, base_col.b, 0.60), 2.0)

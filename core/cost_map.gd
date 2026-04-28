extends RefCounted
class_name CostMap

var _costs: Dictionary = {}       # Vector2i -> float  (terrain + weighted danger)
var _flat_costs: Dictionary = {}  # Vector2i -> float  (terrain only, no danger)

## Rebuild both cost tables from the current grid and danger values.
## weight: how much each unit of danger adds to traversal cost.
func rebuild(grid: GridEngine, danger: DangerMap, weight: float) -> void:
	_costs.clear()
	_flat_costs.clear()

	for y in range(grid.get_height()):
		for x in range(grid.get_width()):
			var pos := Vector2i(x, y)
			var tile: GridTileData = grid.get_tile(pos)
			if tile == null or not tile.walkable:
				_costs[pos] = INF
				_flat_costs[pos] = INF
			else:
				var base: float = float(tile.movement_cost)
				_flat_costs[pos] = base
				_costs[pos] = base + weight * danger.get_danger(pos)

## Full cost at pos (terrain + danger). Returns INF for walls / out-of-bounds.
func get_cost(pos: Vector2i) -> float:
	return _costs.get(pos, INF)

## Terrain-only cost at pos (ignores danger). Returns INF for walls.
func get_flat_cost(pos: Vector2i) -> float:
	return _flat_costs.get(pos, INF)

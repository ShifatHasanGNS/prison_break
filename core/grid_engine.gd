extends Node
class_name GridEngine

const WIDTH: int = 28
const HEIGHT: int = 20

var _tiles: Dictionary = {}
var _width: int = WIDTH
var _height: int = HEIGHT

func init(config: Dictionary = {}) -> void:
	_width = config.get("width", WIDTH)
	_height = config.get("height", HEIGHT)
	_tiles.clear()

func load_generated(tiles: Dictionary) -> void:
	_tiles = tiles
	if _tiles.is_empty():
		_width = WIDTH
		_height = HEIGHT
		return

	var min_x: int =  1 << 30
	var min_y: int =  1 << 30
	var max_x: int = -(1 << 30)
	var max_y: int = -(1 << 30)
	for pos_key in _tiles.keys():
		var pos: Vector2i = pos_key
		min_x = mini(min_x, pos.x)
		min_y = mini(min_y, pos.y)
		max_x = maxi(max_x, pos.x)
		max_y = maxi(max_y, pos.y)

	_width = maxi(1, max_x - min_x + 1)
	_height = maxi(1, max_y - min_y + 1)

func get_tile(pos: Vector2i) -> GridTileData:
	return _tiles.get(pos, null)

func get_width() -> int:
	return _width

func get_height() -> int:
	return _height

func is_walkable(pos: Vector2i) -> bool:
	var tile: GridTileData = get_tile(pos)
	return tile != null and tile.walkable

func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < _width and pos.y >= 0 and pos.y < _height

func get_neighbours(pos: Vector2i, diagonal: bool = false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	if diagonal:
		dirs.append_array([Vector2i(1,1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(-1,-1)])
	for d: Vector2i in dirs:
		var np: Vector2i = pos + d
		if _in_bounds(np) and is_walkable(np):
			result.append(np)
	return result

func get_all_neighbours(pos: Vector2i, diagonal: bool = false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	if diagonal:
		dirs.append_array([Vector2i(1,1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(-1,-1)])
	for d: Vector2i in dirs:
		var np: Vector2i = pos + d
		if _in_bounds(np):
			result.append(np)
	return result

func raycast(from: Vector2i, to: Vector2i) -> bool:
	var x0: int = from.x
	var y0: int = from.y
	var x1: int = to.x
	var y1: int = to.y
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy

	while true:
		var pos := Vector2i(x0, y0)
		if pos != from:
			var tile: GridTileData = get_tile(pos)
			if tile == null or tile.visibility_block:
				return false
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy

	return true

func astar(from: Vector2i, to: Vector2i, cost_map = null) -> Array[Vector2i]:
	if not _in_bounds(from) or not _in_bounds(to):
		return []
	if not is_walkable(from) or not is_walkable(to):
		return []
	if from == to:
		return [from]

	# open_set entries: [f_score, pos]
	var open_set: Array = [[_heuristic(from, to), from]]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {from: 0.0}
	var in_open: Dictionary = {from: true}

	while not open_set.is_empty():
		var min_idx: int = 0
		for i in range(1, open_set.size()):
			if open_set[i][0] < open_set[min_idx][0]:
				min_idx = i

		var current: Vector2i = open_set[min_idx][1]
		open_set.remove_at(min_idx)
		in_open.erase(current)

		if current == to:
			return _reconstruct_path(came_from, current)

		for nb: Vector2i in get_neighbours(current):
			var step: float
			if cost_map != null:
				step = cost_map.get_cost(nb)
				if step >= 1e30:
					continue
			else:
				var tile: GridTileData = get_tile(nb)
				step = float(tile.movement_cost) if tile != null else 1.0

			var tentative_g: float = g_score.get(current, INF) + step
			if tentative_g < g_score.get(nb, INF):
				came_from[nb] = current
				g_score[nb] = tentative_g
				var f: float = tentative_g + _heuristic(nb, to)
				if in_open.has(nb):
					for item in open_set:
						if item[1] == nb:
							item[0] = f
							break
				else:
					open_set.append([f, nb])
					in_open[nb] = true

	return []

func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return float(absi(a.x - b.x) + absi(a.y - b.y))

func _reconstruct_path(came_from: Dictionary, end: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [end]
	var current: Vector2i = end
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path

extends Node
class_name MapGenerator

const WIDTH: int = 28
const HEIGHT: int = 20

# --- Public API ---

func generate() -> Dictionary:
	for _attempt in range(60):
		var result: Dictionary = _try_generate()
		if result.get("valid", false):
			return result
	print("MapGenerator: all 60 attempts exhausted, using fallback map")
	return _fallback_map()

# --- Generation pipeline ---

func _try_generate() -> Dictionary:
	var tiles: Dictionary = {}

	# Step 1: All floor
	for y in range(HEIGHT):
		for x in range(WIDTH):
			tiles[Vector2i(x, y)] = _make_floor()

	# Step 2: Border walls
	for x in range(WIDTH):
		tiles[Vector2i(x, 0)] = _make_wall()
		tiles[Vector2i(x, HEIGHT - 1)] = _make_wall()
	for y in range(HEIGHT):
		tiles[Vector2i(0, y)] = _make_wall()
		tiles[Vector2i(WIDTH - 1, y)] = _make_wall()

	# Step 3: Room carving + corridors
	var rooms: Array[Rect2i] = _carve_rooms(tiles)

	# Step 4a: Interior wall structures - loose partitions
	_place_interior_walls(tiles)

	# Step 4b: Extra walls - light scatter only
	_scatter_walls(tiles)
	_scatter_top_half_walls(tiles)

	# Step 5: Exits first (so spawns can keep distance from them)
	var exits: Array[Vector2i] = _place_exits(tiles)
	if exits.size() < 2:
		return {}
	_carve_exit_approaches(tiles, exits)

	# Step 6: Agent spawns — prisoners in bottom half, police in top area
	# Passing exits ensures a minimum distance check filters candidates.
	var inner_left: int = 1
	var inner_right: int = WIDTH - 2
	var center_x: int = WIDTH / 2
	var prisoner_y_min: int = maxi(2, int(floor(float(HEIGHT) * 0.60)))
	var prisoner_y_max: int = HEIGHT - 3
	var police_y_min: int = 2
	var police_y_max: int = maxi(police_y_min, int(floor(float(HEIGHT) * 0.42)))

	var red_spawn: Vector2i = _find_spawn(
		tiles,
		inner_left,
		maxi(inner_left, center_x - 3),
		prisoner_y_min,
		prisoner_y_max,
		exits
	)
	var blue_spawn: Vector2i = _find_spawn(
		tiles,
		mini(inner_right, center_x + 3),
		inner_right,
		prisoner_y_min,
		prisoner_y_max,
		exits
	)
	var police_spawn: Vector2i = _find_spawn(
		tiles,
		maxi(inner_left, center_x - 4),
		mini(inner_right, center_x + 4),
		police_y_min,
		police_y_max,
		[]
	)

	if red_spawn.x < 0 or blue_spawn.x < 0 or police_spawn.x < 0:
		return {}

	# Step 7: Hazards + CCTV
	var spawns: Array[Vector2i] = [red_spawn, blue_spawn, police_spawn]
	var fire_tiles: Array[Vector2i] = _place_fire(tiles, spawns, exits)
	var door_tiles: Array[Vector2i] = _place_doors(tiles, exits)
	var dog_waypoints: Array[Vector2i] = _find_dog_waypoints(tiles, spawns, exits)
	var camera_tiles: Array = _place_cameras(tiles, spawns, exits, fire_tiles, door_tiles)

	# Step 8: Visual variants
	_assign_variants(tiles)

	# Step 9: Validate
	if not _validate(tiles, red_spawn, blue_spawn, police_spawn, exits, fire_tiles, door_tiles, dog_waypoints):
		return {}

	return {
		"valid": true,
		"tiles": tiles,
		"red_spawn": red_spawn,
		"blue_spawn": blue_spawn,
		"police_spawn": police_spawn,
		"exits": exits,
		"dog_waypoints": dog_waypoints,
		"fire_tiles": fire_tiles,
		"door_tiles": door_tiles,
		"camera_tiles": camera_tiles,
	}

# --- Room carving ---

func _carve_rooms(tiles: Dictionary) -> Array[Rect2i]:
	var rooms: Array[Rect2i] = []
	var target: int = SimRandom.randi_range(6, 10)
	var attempts: int = 0

	while rooms.size() < target and attempts < 120:
		attempts += 1
		var w: int = SimRandom.randi_range(4, 8)
		var h: int = SimRandom.randi_range(4, 6)
		var x: int = SimRandom.randi_range(1, WIDTH - w - 1)
		var y: int = SimRandom.randi_range(1, HEIGHT - h - 1)
		var new_room := Rect2i(x, y, w, h)

		var overlap: bool = false
		for room: Rect2i in rooms:
			var expanded := Rect2i(room.position - Vector2i(1, 1), room.size + Vector2i(2, 2))
			if expanded.intersects(new_room):
				overlap = true
				break

		if overlap:
			continue

		for ry in range(y, y + h):
			for rx in range(x, x + w):
				tiles[Vector2i(rx, ry)] = _make_floor()

		if not rooms.is_empty():
			var nearest: Rect2i = rooms[0]
			var min_dist: float = INF
			for room: Rect2i in rooms:
				var d: float = Vector2(room.get_center()).distance_to(Vector2(new_room.get_center()))
				if d < min_dist:
					min_dist = d
					nearest = room
			_carve_corridor(tiles, nearest.get_center(), new_room.get_center())

		rooms.append(new_room)

	return rooms

func _carve_corridor(tiles: Dictionary, from: Vector2i, to: Vector2i) -> void:
	if SimRandom.randi_range(0, 1) == 0:
		for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
			tiles[Vector2i(x, from.y)] = _make_floor()
		for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
			tiles[Vector2i(to.x, y)] = _make_floor()
	else:
		for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
			tiles[Vector2i(from.x, y)] = _make_floor()
		for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
			tiles[Vector2i(x, to.y)] = _make_floor()

# --- Interior wall structures ---

## Creates loose partitions across the interior.
## Uses fewer strips, more gaps, and short blockers so paths stay readable.
func _place_interior_walls(tiles: Dictionary) -> void:
	# Horizontal partitions with broad gaps.
	var row_a: int = clampi(int(round(float(HEIGHT) * 0.32)), 3, HEIGHT - 4)
	var row_b: int = clampi(int(round(float(HEIGHT) * 0.68)), 4, HEIGHT - 3)
	if row_b <= row_a:
		row_b = mini(HEIGHT - 3, row_a + 3)
	var h_rows: Array[int] = [row_a, row_b]
	for row_y: int in h_rows:
		_place_wall_strip_h(tiles, row_y, 2, WIDTH - 2, 4)

	# Vertical partitions with broad gaps.
	var col_a: int = clampi(int(round(float(WIDTH) * 0.34)), 3, WIDTH - 4)
	var col_b: int = clampi(int(round(float(WIDTH) * 0.66)), 4, WIDTH - 3)
	if col_b <= col_a:
		col_b = mini(WIDTH - 3, col_a + 4)
	var v_cols: Array[int] = [col_a, col_b]
	for col_x: int in v_cols:
		_place_wall_strip_v(tiles, col_x, 2, HEIGHT - 2, 4)

	# Additional short horizontal walls between main strips
	var extra_h: int = SimRandom.randi_range(3, 5)
	for _i in range(extra_h):
		var ry: int = SimRandom.randi_range(3, HEIGHT - 4)
		var rx: int = SimRandom.randi_range(2, WIDTH - 7)
		var rlen: int = SimRandom.randi_range(2, 4)
		_place_wall_strip_h(tiles, ry, rx, rx + rlen, 2)

	# Additional short vertical walls
	var extra_v: int = SimRandom.randi_range(3, 5)
	for _i in range(extra_v):
		var cx2: int = SimRandom.randi_range(3, WIDTH - 4)
		var cy2: int = SimRandom.randi_range(2, HEIGHT - 7)
		var clen: int = SimRandom.randi_range(2, 4)
		_place_wall_strip_v(tiles, cx2, cy2, cy2 + clen, 2)

## Place a horizontal wall run from x=x_start to x=x_end at row y,
## leaving num_gaps random single-tile gaps so corridors pass through.
func _place_wall_strip_h(tiles: Dictionary, y: int, x_start: int, x_end: int, num_gaps: int) -> void:
	if x_end - x_start <= 0:
		return
	var positions: Array[int] = []
	for xi in range(x_start, x_end):
		positions.append(xi)
	SimRandom.shuffle(positions)
	var gap_positions: Array[int] = []
	for gi in range(mini(num_gaps, positions.size())):
		gap_positions.append(positions[gi])
	for xi in range(x_start, x_end):
		if xi in gap_positions:
			continue
		var pos := Vector2i(xi, y)
		if _in_bounds(pos) and _walkable_at(tiles, pos):
			if not _would_form_large_cluster(tiles, pos):
				tiles[pos] = _make_wall()

## Place a vertical wall run from y=y_start to y=y_end at column x,
## leaving num_gaps random single-tile gaps so corridors pass through.
func _place_wall_strip_v(tiles: Dictionary, x: int, y_start: int, y_end: int, num_gaps: int) -> void:
	if y_end - y_start <= 0:
		return
	var positions: Array[int] = []
	for yi in range(y_start, y_end):
		positions.append(yi)
	SimRandom.shuffle(positions)
	var gap_positions: Array[int] = []
	for gi in range(mini(num_gaps, positions.size())):
		gap_positions.append(positions[gi])
	for yi in range(y_start, y_end):
		if yi in gap_positions:
			continue
		var pos := Vector2i(x, yi)
		if _in_bounds(pos) and _walkable_at(tiles, pos):
			if not _would_form_large_cluster(tiles, pos):
				tiles[pos] = _make_wall()

# --- Extra walls ---

func _scatter_walls(tiles: Dictionary) -> void:
	var count: int = SimRandom.randi_range(10, 18)
	_scatter_walls_in_rect(tiles, Rect2i(2, 2, WIDTH - 4, HEIGHT - 4), count, 200)

func _scatter_top_half_walls(tiles: Dictionary) -> void:
	var count: int = SimRandom.randi_range(16, 24)
	_scatter_walls_in_rect(tiles, Rect2i(2, 2, WIDTH - 4, 7), count, 260)

func _scatter_walls_in_rect(tiles: Dictionary, area: Rect2i, count: int, max_attempts: int) -> void:
	var placed: int = 0
	var attempts: int = 0

	while placed < count and attempts < max_attempts:
		attempts += 1
		var x: int = SimRandom.randi_range(area.position.x, area.position.x + area.size.x - 1)
		var y: int = SimRandom.randi_range(area.position.y, area.position.y + area.size.y - 1)
		var pos := Vector2i(x, y)
		if not _can_place_extra_wall(tiles, pos):
			continue
		tiles[pos] = _make_wall()
		placed += 1

func _can_place_extra_wall(tiles: Dictionary, pos: Vector2i) -> bool:
	var tile: GridTileData = tiles.get(pos, null)
	if tile == null or not tile.walkable:
		return false
	if pos.x <= 1 or pos.x >= WIDTH - 2 or pos.y <= 1 or pos.y >= HEIGHT - 2:
		return false
	if _walkable_neighbour_count(tiles, pos) < 3:
		return false
	if _would_form_large_cluster(tiles, pos):
		return false
	var opposite_pairs: int = 0
	if _walkable_at(tiles, pos + Vector2i(1, 0)) and _walkable_at(tiles, pos + Vector2i(-1, 0)):
		opposite_pairs += 1
	if _walkable_at(tiles, pos + Vector2i(0, 1)) and _walkable_at(tiles, pos + Vector2i(0, -1)):
		opposite_pairs += 1
	return opposite_pairs > 0

func _would_form_large_cluster(tiles: Dictionary, pos: Vector2i) -> bool:
	# Check if all tiles in any 3x3 block containing pos would be walls after placing
	for oy in range(-2, 1):
		for ox in range(-2, 1):
			var all_wall: bool = true
			for dy in range(3):
				for dx in range(3):
					var np := Vector2i(pos.x + ox + dx, pos.y + oy + dy)
					if np == pos:
						continue
					var t: GridTileData = tiles.get(np, null)
					if t == null or t.walkable:
						all_wall = false
						break
				if not all_wall:
					break
			if all_wall:
				return true
	return false

# --- Agent spawns ---

func _find_spawn(tiles: Dictionary, x_min: int, x_max: int, y_min: int, y_max: int,
		exits: Array[Vector2i] = [], min_exit_dist: int = 8) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for y in range(y_min, y_max + 1):
		for x in range(x_min, x_max + 1):
			var pos := Vector2i(x, y)
			if not _walkable_at(tiles, pos):
				continue
			if _walkable_neighbour_count(tiles, pos) < 2:
				continue
			# Minimum distance from any exit (keeps prisoners far from exits at game start)
			if not exits.is_empty():
				var too_close: bool = false
				for ex: Vector2i in exits:
					if absi(pos.x - ex.x) + absi(pos.y - ex.y) < min_exit_dist:
						too_close = true
						break
				if too_close:
					continue
			candidates.append(pos)

	if candidates.is_empty():
		return Vector2i(-1, -1)
	return SimRandom.choice(candidates)

# --- Exits ---

func _place_exits(tiles: Dictionary) -> Array[Vector2i]:
	var num_exits: int = SimRandom.randi_range(2, 3)
	var exits: Array[Vector2i] = []

	# Exits are placed on the top edge and the UPPER portion of side edges only.
	# Police spawns in rows 2–8 (top area), prisoners spawn in rows 12–17 (bottom area).
	# Limiting side-edge exits to y <= 7 keeps exits firmly in police territory,
	# so prisoners must travel the full map length to reach them.
	var candidates: Array[Vector2i] = []
	for x in range(2, WIDTH - 2):
		candidates.append(Vector2i(x, 0))              # top edge
	for y in range(2, 8):
		candidates.append(Vector2i(0, y))              # left edge — upper third only
		candidates.append(Vector2i(WIDTH - 1, y))      # right edge — upper third only
	SimRandom.shuffle(candidates)

	for candidate: Vector2i in candidates:
		if exits.size() >= num_exits:
			break
		var edge: String = _get_edge(candidate)
		var same_edge: bool = false
		for ex: Vector2i in exits:
			if _get_edge(ex) == edge:
				same_edge = true
				break
		if same_edge:
			continue
		# The tile adjacent to the border (1 step inward) must be walkable
		var inward: Vector2i = _inward_step(candidate)
		if not _walkable_at(tiles, inward):
			continue
		tiles[candidate] = _make_exit()
		exits.append(candidate)

	return exits

func _carve_exit_approaches(tiles: Dictionary, exits: Array[Vector2i]) -> void:
	for ex: Vector2i in exits:
		var dir: Vector2i = _inward_step(ex) - ex
		tiles[ex] = _make_exit()
		for depth in range(1, 5):
			var lane_pos: Vector2i = ex + dir * depth
			if not _in_bounds(lane_pos):
				continue
			tiles[lane_pos] = _make_floor()
			if depth <= 3:
				var side := Vector2i(-dir.y, dir.x)
				for shoulder in [-1, 1]:
					var shoulder_pos: Vector2i = lane_pos + side * int(shoulder)
					if _in_bounds(shoulder_pos) and not _is_border(shoulder_pos):
						tiles[shoulder_pos] = _make_floor()

func _get_edge(pos: Vector2i) -> String:
	if pos.y == 0: return "top"
	if pos.y == HEIGHT - 1: return "bottom"
	if pos.x == 0: return "left"
	return "right"

func _inward_step(pos: Vector2i) -> Vector2i:
	if pos.y == 0: return pos + Vector2i(0, 1)
	if pos.y == HEIGHT - 1: return pos + Vector2i(0, -1)
	if pos.x == 0: return pos + Vector2i(1, 0)
	return pos + Vector2i(-1, 0)

func _is_border(pos: Vector2i) -> bool:
	return pos.x == 0 or pos.x == WIDTH - 1 or pos.y == 0 or pos.y == HEIGHT - 1

# --- Hazards ---

func _place_fire(tiles: Dictionary, spawns: Array[Vector2i], exits: Array[Vector2i]) -> Array[Vector2i]:
	var fire: Array[Vector2i] = []
	var count: int = SimRandom.randi_range(3, 5)
	var attempts: int = 0

	while fire.size() < count and attempts < 200:
		attempts += 1
		var x: int = SimRandom.randi_range(1, WIDTH - 2)
		var y: int = SimRandom.randi_range(1, HEIGHT - 2)
		var pos := Vector2i(x, y)
		if not _walkable_at(tiles, pos):
			continue
		# At least 4 tiles from any spawn (Manhattan)
		var too_close: bool = false
		for sp: Vector2i in spawns:
			if absi(pos.x - sp.x) + absi(pos.y - sp.y) < 4:
				too_close = true
				break
		if too_close:
			continue
		for ex: Vector2i in exits:
			if absi(pos.x - ex.x) + absi(pos.y - ex.y) < 4:
				too_close = true
				break
		if too_close:
			continue
		fire.append(pos)

	return fire

func _place_doors(tiles: Dictionary, exits: Array[Vector2i]) -> Array[Vector2i]:
	var doors: Array[Vector2i] = []
	# Locked doors currently block movement resolution while A* still sees them as
	# walkable high-cost tiles. Leave procedural doors out until planning is door-aware.
	var count: int = 0
	var attempts: int = 0

	while doors.size() < count and attempts < 200:
		attempts += 1
		var x: int = SimRandom.randi_range(1, WIDTH - 2)
		var y: int = SimRandom.randi_range(1, HEIGHT - 2)
		var pos := Vector2i(x, y)
		if not _walkable_at(tiles, pos):
			continue
		if pos in exits:
			continue
		# Corridor chokepoint: exactly 2 walkable cardinal neighbours
		var walkable_nb: int = 0
		for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			if _walkable_at(tiles, pos + d):
				walkable_nb += 1
		if walkable_nb != 2:
			continue
		var door: GridTileData = _make_floor()
		door.interactable_type = GridTileData.INTERACTABLE_DOOR
		door.movement_cost = 9  # High cost but not INF (doors passable per AI robustness)
		tiles[pos] = door
		doors.append(pos)

	return doors

func _find_dog_waypoints(tiles: Dictionary, spawns: Array[Vector2i], exits: Array[Vector2i] = []) -> Array[Vector2i]:
	# Pick one floor tile per map quadrant (roughly), forming a patrol loop.
	# Exit tiles are excluded so the dog never patrols onto them.
	var left_min: int = 2
	var left_max: int = maxi(left_min, (WIDTH / 2) - 1)
	var right_min: int = mini(WIDTH - 3, left_max + 1)
	var right_max: int = WIDTH - 3
	var top_min: int = 2
	var top_max: int = maxi(top_min, (HEIGHT / 2) - 1)
	var bot_min: int = mini(HEIGHT - 3, top_max + 1)
	var bot_max: int = HEIGHT - 3
	var quadrants: Array = [
		[left_min, left_max, top_min, top_max],      # top-left
		[right_min, right_max, top_min, top_max],    # top-right
		[right_min, right_max, bot_min, bot_max],    # bottom-right
		[left_min, left_max, bot_min, bot_max],      # bottom-left
	]
	var waypoints: Array[Vector2i] = []

	for qi in range(quadrants.size()):
		var q = quadrants[qi]
		var candidates: Array[Vector2i] = []
		for y in range(q[2], q[3] + 1):
			for x in range(q[0], q[1] + 1):
				var pos := Vector2i(x, y)
				if pos in exits:
					continue   # skip exit tiles
				if _walkable_at(tiles, pos):
					candidates.append(pos)
		if not candidates.is_empty():
			waypoints.append(SimRandom.choice(candidates))
		else:
			# Try adjacent quadrant's candidates before duplicating
			var found_adjacent: bool = false
			for offset in [1, -1, 2, -2]:
				var adj_idx: int = (qi + offset) % quadrants.size()
				if adj_idx < 0:
					adj_idx += quadrants.size()
				var aq = quadrants[adj_idx]
				var adj_candidates: Array[Vector2i] = []
				for y in range(aq[2], aq[3] + 1):
					for x in range(aq[0], aq[1] + 1):
						var pos := Vector2i(x, y)
						if pos in exits:
							continue
						if _walkable_at(tiles, pos):
							# Avoid picking a tile already chosen as a waypoint
							if pos not in waypoints:
								adj_candidates.append(pos)
				if not adj_candidates.is_empty():
					waypoints.append(SimRandom.choice(adj_candidates))
					found_adjacent = true
					break
			if not found_adjacent and not waypoints.is_empty():
				waypoints.append(waypoints[0])  # absolute last resort duplicate

	return waypoints

# --- Visual variants ---

func _assign_variants(tiles: Dictionary) -> void:
	for pos: Vector2i in tiles:
		var t: GridTileData = tiles[pos]
		t.visual_variant = SimRandom.randi_range(0, 3)

# --- Validation ---

func _validate(
	tiles: Dictionary,
	red_spawn: Vector2i, blue_spawn: Vector2i, police_spawn: Vector2i,
	exits: Array[Vector2i],
	fire_tiles: Array[Vector2i], door_tiles: Array[Vector2i],
	dog_waypoints: Array[Vector2i]
) -> bool:

	# Each spawn can reach every exit via A*
	for spawn: Vector2i in [red_spawn, blue_spawn, police_spawn]:
		for ex: Vector2i in exits:
			if _astar_check(tiles, spawn, ex).is_empty():
				return false

	# Minimum exit distance for prisoners (game must last long enough)
	const MIN_PRISONER_EXIT_DIST: int = 10
	var red_dist: int    = _min_dist_to_exits(tiles, red_spawn,    exits)
	var blue_dist: int   = _min_dist_to_exits(tiles, blue_spawn,   exits)
	var police_dist: int = _min_dist_to_exits(tiles, police_spawn, exits)
	if red_dist  < MIN_PRISONER_EXIT_DIST: return false
	if blue_dist < MIN_PRISONER_EXIT_DIST: return false

	# Balanced spawn distances: Red/Blue distance to nearest exit within 10 tiles
	if absi(red_dist - blue_dist) > 10:
		return false

	# Police MUST be closer to exits than both prisoners — this is the key
	# territorial advantage. Exits are placed in police territory (rows 0–7).
	if police_dist >= red_dist or police_dist >= blue_dist:
		return false

	# Police equidistant to both prisoners (±10 tiles)
	var police_to_red: int  = _astar_check(tiles, police_spawn, red_spawn).size()
	var police_to_blue: int = _astar_check(tiles, police_spawn, blue_spawn).size()
	if absi(police_to_red - police_to_blue) > 10:
		return false

	# At least 2 distinct routes for each prisoner spawn to at least one exit
	if not _has_two_routes_to_any_exit(tiles, red_spawn, exits):
		return false
	if not _has_two_routes_to_any_exit(tiles, blue_spawn, exits):
		return false

	# Dog patrol loop fully walkable
	for wp: Vector2i in dog_waypoints:
		if not _walkable_at(tiles, wp):
			return false

	# Fire tiles and doors not the sole path to any exit
	var blocked: Dictionary = {}
	for ft: Vector2i in fire_tiles:
		blocked[ft] = true
	for dt: Vector2i in door_tiles:
		blocked[dt] = true

	for spawn: Vector2i in [red_spawn, blue_spawn]:
		var has_clear: bool = false
		for ex: Vector2i in exits:
			if not _astar_check(tiles, spawn, ex, blocked).is_empty():
				has_clear = true
				break
		if not has_clear:
			return false

	return true

func _min_dist_to_exits(tiles: Dictionary, from: Vector2i, exits: Array[Vector2i]) -> int:
	var best: int = 99999
	for ex: Vector2i in exits:
		var p: Array[Vector2i] = _astar_check(tiles, from, ex)
		if not p.is_empty() and p.size() < best:
			best = p.size()
	return best

func _has_two_routes_to_any_exit(tiles: Dictionary, from: Vector2i, exits: Array[Vector2i]) -> bool:
	for ex: Vector2i in exits:
		var path1: Array[Vector2i] = _astar_check(tiles, from, ex)
		if path1.is_empty():
			continue
		# Block interior tiles of path1 and find path2
		var blocked: Dictionary = {}
		for i in range(1, path1.size() - 1):
			blocked[path1[i]] = true
		var path2: Array[Vector2i] = _astar_check(tiles, from, ex, blocked)
		if path2.is_empty():
			continue
		# Count tiles in path2 not in path1
		var p1_set: Dictionary = {}
		for p: Vector2i in path1:
			p1_set[p] = true
		var unique: int = 0
		for p: Vector2i in path2:
			if not p1_set.has(p):
				unique += 1
		if unique >= 2:
			return true
	return false

# --- Internal A* (used only during generation/validation) ---

func _astar_check(tiles: Dictionary, from: Vector2i, to: Vector2i, blocked: Dictionary = {}) -> Array[Vector2i]:
	if not _walkable_at(tiles, from) or not _walkable_at(tiles, to):
		return []
	if blocked.has(from) or blocked.has(to):
		return []
	if from == to:
		return [from]

	var open_set: Array = [[_heur(from, to), from]]
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
			var path: Array[Vector2i] = [current]
			var c: Vector2i = current
			while came_from.has(c):
				c = came_from[c]
				path.push_front(c)
			return path

		var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
		for d: Vector2i in dirs:
			var nb: Vector2i = current + d
			if not _in_bounds(nb) or blocked.has(nb):
				continue
			if not _walkable_at(tiles, nb):
				continue
			var tile: GridTileData = tiles.get(nb, null)
			var cost: float = 1.0 if tile == null else float(tile.movement_cost)
			var tent_g: float = g_score.get(current, INF) + cost
			if tent_g < g_score.get(nb, INF):
				came_from[nb] = current
				g_score[nb] = tent_g
				var f: float = tent_g + _heur(nb, to)
				if in_open.has(nb):
					for item in open_set:
						if item[1] == nb:
							item[0] = f
							break
				else:
					open_set.append([f, nb])
					in_open[nb] = true

	return []

func _heur(a: Vector2i, b: Vector2i) -> float:
	return float(absi(a.x - b.x) + absi(a.y - b.y))

# --- Tile factories ---

func _make_floor() -> GridTileData:
	var t := GridTileData.new()
	t.walkable = true
	t.movement_cost = 1
	t.visibility_block = false
	t.interactable_type = GridTileData.INTERACTABLE_NONE
	return t

func _make_wall() -> GridTileData:
	var t := GridTileData.new()
	t.walkable = false
	t.movement_cost = 999
	t.visibility_block = true
	t.interactable_type = GridTileData.INTERACTABLE_NONE
	return t

func _make_exit() -> GridTileData:
	var t := GridTileData.new()
	t.walkable = true
	t.movement_cost = 1
	t.visibility_block = false
	t.interactable_type = GridTileData.INTERACTABLE_EXIT
	return t

# --- Helpers ---

func _walkable_at(tiles: Dictionary, pos: Vector2i) -> bool:
	var t: GridTileData = tiles.get(pos, null)
	return t != null and t.walkable

func _walkable_neighbour_count(tiles: Dictionary, pos: Vector2i) -> int:
	var count: int = 0
	for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		if _walkable_at(tiles, pos + d):
			count += 1
	return count

func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < WIDTH and pos.y >= 0 and pos.y < HEIGHT

func _place_cameras(tiles: Dictionary, spawns: Array, exits: Array, fire_tiles: Array, door_tiles: Array) -> Array:
	var reserved: Array[Vector2i] = []
	for s in spawns:
		reserved.append(s as Vector2i)
	for e in exits:
		reserved.append(e as Vector2i)
	for f in fire_tiles:
		reserved.append(f as Vector2i)
	for d in door_tiles:
		reserved.append(d as Vector2i)

	var candidates: Array = []
	var dirs: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	for y in range(2, HEIGHT - 2):
		for x in range(2, WIDTH - 2):
			var pos := Vector2i(x, y)
			if not _walkable_at(tiles, pos):
				continue
			if _too_close_to_any(pos, reserved, 3):
				continue
			var best_dir := Vector2i.ZERO
			var best_depth := 0
			for d in dirs:
				var depth := _camera_corridor_depth(tiles, pos, d)
				if depth > best_depth:
					best_depth = depth
					best_dir = d
			if best_depth < 5:
				continue
			candidates.append({
				"pos": pos,
				"facing": best_dir,
				"range": mini(7, maxi(5, best_depth)),
				"fov_deg": 78.0,
				"rotates": true,
				"sweep_interval": SimRandom.randi_range(2, 4),
			})

	SimRandom.shuffle(candidates)
	var picked: Array = []
	const TARGET_CAMERA_COUNT: int = 3
	for c in candidates:
		var pos: Vector2i = c["pos"]
		var too_close := false
		for other in picked:
			if _manhattan(pos, other["pos"]) < 5:
				too_close = true
				break
		if too_close:
			continue
		picked.append(c)
		if picked.size() >= TARGET_CAMERA_COUNT:
			break

	if picked.size() < TARGET_CAMERA_COUNT:
		var fallback_positions: Array[Vector2i] = [Vector2i(4, 4), Vector2i(WIDTH - 5, 4), Vector2i(4, HEIGHT - 5), Vector2i(WIDTH - 5, HEIGHT - 5)]
		for fp in fallback_positions:
			if not _walkable_at(tiles, fp):
				continue
			var crowded: bool = false
			for reserved_pos in reserved:
				if _manhattan(fp, reserved_pos) <= 2:
					crowded = true
					break
			if crowded:
				continue
			var duplicate: bool = false
			for other in picked:
				if other["pos"] == fp:
					duplicate = true
					break
			if duplicate:
				continue
			picked.append({
				"pos": fp,
				"facing": Vector2i.RIGHT,
				"range": 6,
				"fov_deg": 78.0,
				"rotates": true,
				"sweep_interval": 3,
			})
			if picked.size() >= TARGET_CAMERA_COUNT:
				break

	if picked.size() < TARGET_CAMERA_COUNT:
		for y in range(1, HEIGHT - 1):
			for x in range(1, WIDTH - 1):
				var p: Vector2i = Vector2i(x, y)
				if not _walkable_at(tiles, p):
					continue
				var taken: bool = false
				for other in picked:
					if other["pos"] == p:
						taken = true
						break
				if taken:
					continue
				picked.append({
					"pos": p,
					"facing": Vector2i.RIGHT,
					"range": 6,
					"fov_deg": 78.0,
					"rotates": true,
					"sweep_interval": 3,
				})
				if picked.size() >= TARGET_CAMERA_COUNT:
					break
			if picked.size() >= TARGET_CAMERA_COUNT:
				break
	return picked

func _camera_corridor_depth(tiles: Dictionary, pos: Vector2i, dir: Vector2i) -> int:
	var depth := 0
	for i in range(1, 9):
		var probe := pos + dir * i
		if not _in_bounds(probe) or not _walkable_at(tiles, probe):
			break
		depth += 1
	return depth

func _too_close_to_any(pos: Vector2i, others: Array, dist: int) -> bool:
	for other in others:
		if _manhattan(pos, other as Vector2i) <= dist:
			return true
	return false

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# --- Fallback map (guaranteed valid) ---

func _fallback_map() -> Dictionary:
	var tiles: Dictionary = {}
	var center_x: int = WIDTH / 2
	var left_x: int = 3
	var right_x: int = WIDTH - 4
	var spawn_y: int = HEIGHT - 4
	var police_y: int = 2

	# All floor
	for y in range(HEIGHT):
		for x in range(WIDTH):
			tiles[Vector2i(x, y)] = _make_floor()

	# Border walls
	for x in range(WIDTH):
		tiles[Vector2i(x, 0)] = _make_wall()
		tiles[Vector2i(x, HEIGHT - 1)] = _make_wall()
	for y in range(HEIGHT):
		tiles[Vector2i(0, y)] = _make_wall()
		tiles[Vector2i(WIDTH - 1, y)] = _make_wall()

	# Two loose dividers with multiple gaps.
	var divider_14_gaps: Array[int] = [3, center_x - 4, center_x + 3, WIDTH - 4]
	var divider_9_gaps: Array[int] = [2, center_x - 5, center_x + 2, WIDTH - 5]
	SimRandom.shuffle(divider_14_gaps)
	SimRandom.shuffle(divider_9_gaps)
	divider_14_gaps.resize(SimRandom.randi_range(3, 4))
	divider_9_gaps.resize(SimRandom.randi_range(3, 4))
	for x in range(1, WIDTH - 1):
		if x not in divider_14_gaps:
			tiles[Vector2i(x, 14)] = _make_wall()

	for x in range(1, WIDTH - 1):
		if x not in divider_9_gaps:
			tiles[Vector2i(x, 9)] = _make_wall()

	# Short vertical walls add shape without forcing single-file movement.
	var blockers: Array = [
		[Vector2i(center_x, 15), Vector2i(center_x, 16)],
		[Vector2i(5, 10), Vector2i(5, 11)],
		[Vector2i(WIDTH - 6, 10), Vector2i(WIDTH - 6, 11)],
		[Vector2i(center_x - 1, 3), Vector2i(center_x - 1, 4), Vector2i(center_x - 1, 5)],
		[Vector2i(WIDTH - 4, 4), Vector2i(WIDTH - 4, 5), Vector2i(WIDTH - 4, 6)],
		[Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6)],
		[Vector2i(center_x + 2, 3), Vector2i(center_x + 3, 3), Vector2i(center_x + 4, 3)],
	]
	SimRandom.shuffle(blockers)
	for i in range(SimRandom.randi_range(4, blockers.size())):
		for pos: Vector2i in blockers[i]:
			tiles[pos] = _make_wall()

	# Exits on top edge and upper side edges only — police spawns at (10,2) so all
	# exits are within 5–12 tiles of police, vs 12–18 tiles for prisoners at bottom.
	var exit_candidates: Array[Vector2i] = [
		Vector2i(5,  0),
		Vector2i(WIDTH - 6, 0),
		Vector2i(center_x, 0),
		Vector2i(0,  4),
		Vector2i(WIDTH - 1, 4),
		Vector2i(0,  7),
		Vector2i(WIDTH - 1, 7),
	]
	SimRandom.shuffle(exit_candidates)
	var exits: Array[Vector2i] = []
	var exit_count: int = SimRandom.randi_range(2, 3)
	for i in range(exit_count):
		exits.append(exit_candidates[i])
	for ex: Vector2i in exits:
		tiles[ex] = _make_exit()
	_carve_exit_approaches(tiles, exits)

	# Assign variants
	for pos: Vector2i in tiles:
		var t: GridTileData = tiles[pos]
		t.visual_variant = SimRandom.randi_range(0, 3)

	return {
		"valid": true,
		"tiles": tiles,
		# Prisoners in bottom corners — minimum ~16 tiles from nearest exit via dividers
		"red_spawn":    Vector2i(left_x,  spawn_y),
		"blue_spawn":   Vector2i(right_x, spawn_y),
		# Police in top-center — near exits, blocks prisoner routes
		"police_spawn": Vector2i(center_x, police_y),
		"exits": exits,
		"dog_waypoints": _find_dog_waypoints(tiles, [Vector2i(left_x, spawn_y), Vector2i(right_x, spawn_y), Vector2i(center_x, police_y)], exits),
		"fire_tiles":    _place_fire(tiles, [Vector2i(left_x, spawn_y), Vector2i(right_x, spawn_y), Vector2i(center_x, police_y)], exits),
		"door_tiles":    [],
		"camera_tiles": _place_cameras(tiles, [Vector2i(left_x, spawn_y), Vector2i(right_x, spawn_y), Vector2i(center_x, police_y)], exits, [], []),
	}

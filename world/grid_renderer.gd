extends Node2D
class_name GridRenderer

const TILE_SIZE: int = 48

const C_BG           := Color(0.055, 0.078, 0.125)
const C_WALL         := Color(0.110, 0.129, 0.188)
const C_FLOOR        := Color(0.169, 0.196, 0.259)
const C_HIGHLIGHT    := Color(0.290, 0.855, 0.502)
const C_WARNING      := Color(0.984, 0.749, 0.141)

var _grid: GridEngine = null
var _exit_rotator: ExitRotator = null
var _doors: Array = []

# Exit pulse animation (alpha 0.4 ↔ 1.0 every 0.8 s via Tween)
var _exit_glow_alpha: float = 0.4
var _exit_tween: Tween = null

# -------------------------------------------------------------------------

func setup(grid: GridEngine, exit_rotator: ExitRotator = null, doors: Array = []) -> void:
	_grid = grid
	_exit_rotator = exit_rotator
	_doors = doors
	_start_exit_pulse()
	EventBus.exit_activated.connect(_on_exit_event)
	EventBus.exit_deactivated.connect(_on_exit_event)
	EventBus.door_state_changed.connect(_on_door_changed)
	queue_redraw()

func _start_exit_pulse() -> void:
	if _exit_tween != null and _exit_tween.is_valid():
		_exit_tween.kill()
	_exit_tween = create_tween().set_loops()
	_exit_tween.tween_property(self, "_exit_glow_alpha", 1.0, 0.4)
	_exit_tween.tween_property(self, "_exit_glow_alpha", 0.4, 0.4)

func _on_exit_event(_pos: Vector2i) -> void:
	queue_redraw()

func _on_door_changed(_pos: Vector2i, _state: String) -> void:
	queue_redraw()

func _process(_delta: float) -> void:
	# Drive exit pulse and any per-frame animation every frame
	queue_redraw()

# -------------------------------------------------------------------------

func _draw() -> void:
	if _grid == null:
		return

	var map_pw := float(_grid.get_width()  * TILE_SIZE)
	var map_ph := float(_grid.get_height() * TILE_SIZE)

	# Full background behind and around the map
	draw_rect(Rect2(-500.0, -500.0, map_pw + 1000.0, map_ph + 1000.0), C_BG)

	# Draw every tile
	for y in range(_grid.get_height()):
		for x in range(_grid.get_width()):
			var tile: GridTileData = _grid.get_tile(Vector2i(x, y))
			if tile == null:
				continue
			_draw_tile(x, y, tile)

	# Exit overlays on top of tiles
	if _exit_rotator != null:
		for ex: Vector2i in _exit_rotator.get_exits():
			_draw_exit(ex)

	# Door overlays on top of everything
	for door in _doors:
		_draw_door_visual(door)

# -------------------------------------------------------------------------

func _draw_tile(x: int, y: int, tile: GridTileData) -> void:
	var rx := float(x * TILE_SIZE)
	var ry := float(y * TILE_SIZE)
	var T  := float(TILE_SIZE)

	if tile.walkable:
		# Gap frame — C_BG shows through between tiles as a 1 px dark grid line
		draw_rect(Rect2(rx, ry, T, T), C_BG)
		# Tile body — inset 1 px on all sides
		var I := 1.0
		draw_rect(Rect2(rx+I, ry+I, T-I*2, T-I*2), C_FLOOR)
		# Top-left inner highlight (stone depth)
		draw_line(Vector2(rx+I+1, ry+I+1), Vector2(rx+T-I-2, ry+I+1), Color(1,1,1,0.07), 1)
		draw_line(Vector2(rx+I+1, ry+I+1), Vector2(rx+I+1, ry+T-I-2), Color(1,1,1,0.07), 1)
		# Bottom-right shadow
		draw_line(Vector2(rx+I+1, ry+T-I-1), Vector2(rx+T-I-1, ry+T-I-1), Color(0,0,0,0.20), 1)
		draw_line(Vector2(rx+T-I-1, ry+I+1), Vector2(rx+T-I-1, ry+T-I-1), Color(0,0,0,0.20), 1)
		# Tile border (inset)
		draw_rect(Rect2(rx+I, ry+I, T-I*2, T-I*2), Color(1,1,1,0.04), false)
		# Variant corner marks
		if tile.visual_variant % 2 == 1:
			draw_rect(Rect2(rx+I+2, ry+I+2, 3, 3), Color(1,1,1,0.08))
			draw_rect(Rect2(rx+T-I-5, ry+T-I-5, 3, 3), Color(1,1,1,0.08))
	else:
		# Wall base
		draw_rect(Rect2(rx, ry, T, T), C_WALL)
		# Top face highlight — wider for stronger 2.5D look
		draw_rect(Rect2(rx, ry, T, 8), Color(0.20, 0.24, 0.36, 1.0))
		# Left face strip — side-face illusion
		draw_rect(Rect2(rx, ry+8, 3, T-8), Color(0.16, 0.19, 0.28, 1.0))
		# Horizontal brick mortar lines
		var mortar := Color(0.08, 0.09, 0.13, 0.70)
		for row: int in [12, 24, 36]:
			draw_line(Vector2(rx, ry + row), Vector2(rx + T, ry + row), mortar, 1)
		# Vertical mortar — alternating offset per visual variant
		var ofs: int = 24 if tile.visual_variant % 2 == 0 else 0
		draw_line(Vector2(rx + ofs,            ry + 8),  Vector2(rx + ofs,            ry + 12), mortar, 1)
		draw_line(Vector2(rx + ofs + 24,       ry + 8),  Vector2(rx + ofs + 24,       ry + 12), mortar, 1)
		draw_line(Vector2(rx + (ofs + 12) % 48, ry + 13), Vector2(rx + (ofs + 12) % 48, ry + 24), mortar, 1)
		draw_line(Vector2(rx + (ofs + 36) % 48, ry + 13), Vector2(rx + (ofs + 36) % 48, ry + 24), mortar, 1)
		draw_line(Vector2(rx + ofs,            ry + 25), Vector2(rx + ofs,            ry + 36), mortar, 1)
		draw_line(Vector2(rx + ofs + 24,       ry + 25), Vector2(rx + ofs + 24,       ry + 36), mortar, 1)
		# Right + bottom edge shadows
		draw_rect(Rect2(rx + T - 3, ry + 8, 3, T - 8), Color(0, 0, 0, 0.28))
		draw_rect(Rect2(rx, ry + T - 3, T, 3),          Color(0, 0, 0, 0.28))

func _draw_exit(pos: Vector2i) -> void:
	if _exit_rotator == null:
		return
	var rx := float(pos.x * TILE_SIZE)
	var ry := float(pos.y * TILE_SIZE)
	var T  := float(TILE_SIZE)
	var font := ThemeDB.fallback_font

	if _exit_rotator.is_active_exit(pos):
		# Active exit — richer green fill + inward chevrons + triple glow rings
		draw_rect(Rect2(rx, ry, T, T),
			Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, 0.38))
		# Left chevron (points right, into tile)
		var pts_l := PackedVector2Array([
			Vector2(rx + T * 0.12, ry + T * 0.50),
			Vector2(rx + T * 0.32, ry + T * 0.36),
			Vector2(rx + T * 0.32, ry + T * 0.64),
		])
		draw_polygon(pts_l, PackedColorArray([C_HIGHLIGHT, C_HIGHLIGHT, C_HIGHLIGHT]))
		# Right chevron (points left, into tile)
		var pts_r := PackedVector2Array([
			Vector2(rx + T * 0.88, ry + T * 0.50),
			Vector2(rx + T * 0.68, ry + T * 0.36),
			Vector2(rx + T * 0.68, ry + T * 0.64),
		])
		draw_polygon(pts_r, PackedColorArray([C_HIGHLIGHT, C_HIGHLIGHT, C_HIGHLIGHT]))
		# Solid inner border
		draw_rect(Rect2(rx + 1, ry + 1, T - 2, T - 2), C_HIGHLIGHT, false)
		# Triple pulsing glow rings (ga driven by _exit_tween)
		var ga := _exit_glow_alpha
		draw_rect(Rect2(rx - 2, ry - 2, T + 4, T + 4),
			Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, ga), false)
		draw_rect(Rect2(rx - 5, ry - 5, T + 10, T + 10),
			Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, ga * 0.50), false)
		draw_rect(Rect2(rx - 9, ry - 9, T + 18, T + 18),
			Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, ga * 0.18), false)
		# Cross-hair lines from tile centre
		var mc := Vector2(rx + T * 0.5, ry + T * 0.5)
		var ch_col := Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, 0.80)
		draw_line(mc + Vector2(-T*0.42, 0), mc + Vector2(-T*0.20, 0), ch_col, 1)
		draw_line(mc + Vector2( T*0.20, 0), mc + Vector2( T*0.42, 0), ch_col, 1)
		draw_line(mc + Vector2(0, -T*0.42), mc + Vector2(0, -T*0.20), ch_col, 1)
		draw_line(mc + Vector2(0,  T*0.20), mc + Vector2(0,  T*0.42), ch_col, 1)
		# EXIT label
		if font != null:
			draw_string(font, Vector2(rx + 3, ry + T - 4), "EXIT",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_HIGHLIGHT)
	else:
		# Decoy exit — dim amber fill, static border, ? label
		draw_rect(Rect2(rx, ry, T, T),
			Color(C_WARNING.r, C_WARNING.g, C_WARNING.b, 0.20))
		draw_rect(Rect2(rx + 1, ry + 1, T - 2, T - 2),
			Color(C_WARNING.r, C_WARNING.g, C_WARNING.b, 0.50), false)
		if font != null:
			draw_string(font, Vector2(rx + T * 0.38, ry + T - 6), "?",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(C_WARNING.r, C_WARNING.g, C_WARNING.b, 0.80))

func _draw_door_visual(door: DoorInteractable) -> void:
	var pos: Vector2i = door.grid_pos
	var rx := float(pos.x * TILE_SIZE)
	var ry := float(pos.y * TILE_SIZE)
	var T  := float(TILE_SIZE)
	var state_enum: int = door.get_state_enum()

	# Door frame — 4-px thick border drawn as stacked outlines
	var frame_col := Color(0.25, 0.27, 0.35)
	for i in range(4):
		draw_rect(Rect2(rx + i, ry + i, T - i * 2, T - i * 2), frame_col, false)

	match state_enum:
		DoorInteractable.State.LOCKED:
			# Dark red-brown panel
			draw_rect(Rect2(rx + 4, ry + 4, T - 8, T - 8), Color(0.55, 0.18, 0.12))
			# Padlock body (gold rect)
			draw_rect(Rect2(rx + T * 0.35, ry + T * 0.48, T * 0.30, T * 0.24),
				Color(0.85, 0.75, 0.20))
			# Padlock arc handle
			draw_arc(Vector2(rx + T * 0.50, ry + T * 0.48),
				T * 0.11, PI, TAU, 12, Color(0.85, 0.75, 0.20), 2)
			# Door handle (latch side)
			draw_circle(Vector2(rx + T * 0.72, ry + T * 0.50), 3.0, Color(0.80, 0.70, 0.20))
			# Hinges (hinge side = left)
			draw_rect(Rect2(rx + 5, ry + 8,      6, 5), Color(0.18, 0.18, 0.22))
			draw_rect(Rect2(rx + 5, ry + T - 13, 6, 5), Color(0.18, 0.18, 0.22))
		DoorInteractable.State.UNLOCKED:
			# Wood brown panel
			draw_rect(Rect2(rx + 4, ry + 4, T - 8, T - 8), Color(0.42, 0.35, 0.22))
			draw_circle(Vector2(rx + T * 0.72, ry + T * 0.50), 3.0, Color(0.75, 0.65, 0.25))
			draw_rect(Rect2(rx + 5, ry + 8,      6, 5), Color(0.18, 0.18, 0.22))
			draw_rect(Rect2(rx + 5, ry + T - 13, 6, 5), Color(0.18, 0.18, 0.22))
		DoorInteractable.State.OPENING:
			# Panel half-slid open (width = 50%)
			draw_rect(Rect2(rx + 4, ry + 4, (T - 8) * 0.5, T - 8), Color(0.42, 0.35, 0.22))
			draw_rect(Rect2(rx + 5, ry + 8,      6, 5), Color(0.18, 0.18, 0.22))
			draw_rect(Rect2(rx + 5, ry + T - 13, 6, 5), Color(0.18, 0.18, 0.22))
		DoorInteractable.State.OPEN:
			# Panel gone — only frame and hinges remain
			draw_rect(Rect2(rx + 5, ry + 8,      6, 5), Color(0.18, 0.18, 0.22))
			draw_rect(Rect2(rx + 5, ry + T - 13, 6, 5), Color(0.18, 0.18, 0.22))

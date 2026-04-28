# UPDATED — cinematic prison surveillance map rendering
extends Node2D
class_name GridRenderer

const TILE_SIZE: int = 48

const C_BG := Color(0.035, 0.045, 0.075)
const C_PANEL_GLOW := Color(0.00, 0.90, 1.00, 0.08)
const C_FLOOR_A := Color(0.13, 0.19, 0.28)
const C_FLOOR_B := Color(0.16, 0.22, 0.32)
const C_FLOOR_LINE := Color(0.56, 0.72, 0.88, 0.065)
const C_WALL_FACE := Color(0.10, 0.14, 0.20)
const C_WALL_TOP := Color(0.20, 0.26, 0.35)
const C_WALL_EDGE := Color(0.25, 0.34, 0.44, 0.55)
const C_WALL_GLOW := Color(0.00, 0.90, 1.00, 0.06)
const C_HIGHLIGHT := Color(0.00, 0.90, 0.48)
const C_WARNING := Color(1.00, 0.82, 0.22)
const C_DOOR_LOCK := Color(0.62, 0.20, 0.14)

var _grid: GridEngine = null
var _exit_rotator: ExitRotator = null
var _doors: Array = []
var _exit_glow_alpha: float = 0.4
var _exit_tween: Tween = null
var _hover_tile: Vector2i = Vector2i(-1, -1)
var _selected_tile: Vector2i = Vector2i(-1, -1)
var _click_ripples: Array[Dictionary] = []

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
	_exit_tween.tween_property(self, "_exit_glow_alpha", 1.0, 0.55)
	_exit_tween.tween_property(self, "_exit_glow_alpha", 0.30, 0.55)

func _on_exit_event(_pos: Vector2i) -> void:
	queue_redraw()

func _on_door_changed(_pos: Vector2i, _state: String) -> void:
	queue_redraw()

func _process(delta: float) -> void:
	for i in range(_click_ripples.size() - 1, -1, -1):
		var ripple: Dictionary = _click_ripples[i]
		ripple["t"] = float(ripple.get("t", 0.0)) + delta
		_click_ripples[i] = ripple
		if float(ripple.get("t", 0.0)) > 0.45:
			_click_ripples.remove_at(i)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if _grid == null:
		return
	if event is InputEventMouseMotion:
		var m: InputEventMouseMotion = event
		var tile := _mouse_to_tile(m.position)
		if tile != _hover_tile:
			_hover_tile = tile
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var tile := _mouse_to_tile(mb.position)
			if _tile_in_bounds(tile):
				_selected_tile = tile
				_click_ripples.append({
					"tile": tile,
					"t": 0.0,
				})
				while _click_ripples.size() > 5:
					_click_ripples.pop_front()
				queue_redraw()

func _draw() -> void:
	if _grid == null:
		return
	var map_pw: float = float(_grid.get_width() * TILE_SIZE)
	var map_ph: float = float(_grid.get_height() * TILE_SIZE)

	draw_rect(Rect2(-900.0, -900.0, map_pw + 1800.0, map_ph + 1800.0), C_BG)
	_draw_backdrop(map_pw, map_ph)
	_draw_global_light_wells(map_pw, map_ph)
	_draw_volumetric_fog(map_pw, map_ph)

	for y in range(_grid.get_height()):
		for x in range(_grid.get_width()):
			var tile: GridTileData = _grid.get_tile(Vector2i(x, y))
			if tile == null:
				continue
			_draw_tile(x, y, tile)

	_draw_sector_overlays(map_pw, map_ph)

	if _exit_rotator != null:
		for ex: Vector2i in _exit_rotator.get_exits():
			_draw_exit(ex)

	for door in _doors:
		_draw_door_visual(door)

	_draw_interaction_feedback()

	_draw_global_vignette(map_pw, map_ph)
	draw_rect(Rect2(-4.0, -4.0, map_pw + 8.0, map_ph + 8.0), Color(0.16, 0.31, 0.46, 0.34), false)
	draw_rect(Rect2(-12.0, -12.0, map_pw + 24.0, map_ph + 24.0), Color(0.00, 0.90, 1.00, 0.08), false)

func _draw_interaction_feedback() -> void:
	if _grid == null:
		return
	var t: float = float(TILE_SIZE)

	if _tile_in_bounds(_hover_tile):
		var hx: float = float(_hover_tile.x * TILE_SIZE)
		var hy: float = float(_hover_tile.y * TILE_SIZE)
		var hover_pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.008)
		draw_rect(Rect2(hx - 1.0, hy - 1.0, t + 2.0, t + 2.0), Color(0.78, 0.90, 1.0, 0.24 + hover_pulse * 0.10), false)
		draw_rect(Rect2(hx + 3.0, hy + 3.0, t - 6.0, t - 6.0), Color(0.78, 0.90, 1.0, 0.06 + hover_pulse * 0.03), false)

	if _tile_in_bounds(_selected_tile):
		var sx: float = float(_selected_tile.x * TILE_SIZE)
		var sy: float = float(_selected_tile.y * TILE_SIZE)
		draw_rect(Rect2(sx - 3.0, sy - 3.0, t + 6.0, t + 6.0), Color(0.00, 0.96, 1.0, 0.50), false)
		draw_rect(Rect2(sx + 1.0, sy + 1.0, t - 2.0, t - 2.0), Color(0.00, 0.96, 1.0, 0.20), false)

	for ripple in _click_ripples:
		var rp_tile: Vector2i = ripple.get("tile", Vector2i(-1, -1))
		if not _tile_in_bounds(rp_tile):
			continue
		var progress: float = clampf(float(ripple.get("t", 0.0)) / 0.45, 0.0, 1.0)
		var cx: float = float(rp_tile.x * TILE_SIZE) + t * 0.5
		var cy: float = float(rp_tile.y * TILE_SIZE) + t * 0.5
		var radius: float = lerpf(4.0, t * 0.95, progress)
		var alpha: float = (1.0 - progress) * 0.50
		draw_arc(Vector2(cx, cy), radius, 0.0, TAU, 24, Color(0.60, 0.92, 1.0, alpha), 2.0)
		draw_circle(Vector2(cx, cy), 2.0 + (1.0 - progress) * 2.0, Color(0.80, 0.98, 1.0, alpha * 0.7))

func _mouse_to_tile(_screen_pos: Vector2) -> Vector2i:
	var world_pos: Vector2 = to_local(get_global_mouse_position())
	return Vector2i(int(floor(world_pos.x / float(TILE_SIZE))), int(floor(world_pos.y / float(TILE_SIZE))))

func _tile_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < _grid.get_width() and tile.y >= 0 and tile.y < _grid.get_height()

func _draw_backdrop(map_pw: float, map_ph: float) -> void:
	var t_ms: float = float(Time.get_ticks_msec())
	for i in range(10):
		var inset: float = float(i) * 24.0
		var alpha: float = 0.11 - float(i) * 0.009
		if alpha <= 0.0:
			continue
		draw_rect(Rect2(-inset, -inset, map_pw + inset * 2.0, map_ph + inset * 2.0), Color(0.05, 0.10, 0.16, alpha), false)
	for i in range(26):
		var y: float = -160.0 + float(i) * 54.0 + fmod(t_ms * 0.018, 54.0)
		draw_line(Vector2(-240.0, y), Vector2(map_pw + 240.0, y), Color(0.10, 0.28, 0.42, 0.035), 1.0)
	for i in range(18):
		var x: float = -120.0 + float(i) * 72.0 + fmod(t_ms * 0.012, 72.0)
		draw_line(Vector2(x, -180.0), Vector2(x, map_ph + 180.0), Color(0.10, 0.28, 0.42, 0.018), 1.0)
	var cx: float = map_pw * 0.5
	var cy: float = map_ph * 0.5
	for r in [map_pw * 0.55, map_pw * 0.40, map_pw * 0.24]:
		draw_arc(Vector2(cx, cy), r, 0.0, TAU, 72, Color(0.00, 0.65, 1.00, 0.02), 1.0)

func _draw_global_light_wells(map_pw: float, map_ph: float) -> void:
	_draw_light_pool(Vector2(map_pw * 0.50, map_ph * 0.45), 340.0, Color(0.00, 0.55, 0.95, 0.055))
	_draw_light_pool(Vector2(map_pw * 0.80, map_ph * 0.72), 220.0, Color(1.00, 0.43, 0.00, 0.045))
	_draw_light_pool(Vector2(map_pw * 0.12, map_ph * 0.18), 180.0, Color(0.00, 0.90, 0.48, 0.04))

func _draw_volumetric_fog(map_pw: float, map_ph: float) -> void:
	if UserSettings != null and not UserSettings.volumetric_fog_enabled:
		return
	var t: float = float(Time.get_ticks_msec()) * 0.00018
	for i in range(6):
		var yy: float = -80.0 + float(i) * (map_ph / 5.2) + sin(t + float(i) * 0.8) * 14.0
		draw_rect(Rect2(-120.0, yy, map_pw + 240.0, 64.0), Color(0.36, 0.52, 0.68, 0.028 - float(i) * 0.002))
	for i in range(4):
		var xx: float = -70.0 + float(i) * (map_pw / 3.1) + cos(t * 1.2 + float(i) * 1.1) * 10.0
		draw_rect(Rect2(xx, -110.0, 56.0, map_ph + 220.0), Color(0.26, 0.40, 0.60, 0.014))

func _draw_tile(x: int, y: int, tile: GridTileData) -> void:
	var rx: float = float(x * TILE_SIZE)
	var ry: float = float(y * TILE_SIZE)
	var t: float = float(TILE_SIZE)
	var outer: Rect2 = Rect2(rx, ry, t, t)
	var map_w: float = float(maxi(1, _grid.get_width() * TILE_SIZE))
	var map_h: float = float(maxi(1, _grid.get_height() * TILE_SIZE))
	var nx: float = (rx + t * 0.5) / map_w
	var ny: float = (ry + t * 0.5) / map_h
	var to_center: float = clampf(1.0 - Vector2(nx - 0.5, ny - 0.5).length() * 1.28, 0.0, 1.0)
	var t_ms: float = float(Time.get_ticks_msec())

	if tile.walkable:
		var floor_col: Color = C_FLOOR_A if ((x + y + tile.visual_variant) % 2 == 0) else C_FLOOR_B
		var tint: float = _hash01(x, y, tile.visual_variant)
		floor_col = floor_col.lerp(Color(0.18, 0.23, 0.30), to_center * 0.18 + tint * 0.04)

		draw_rect(outer, Color(0.01, 0.03, 0.06, 1.0))
		var inner: Rect2 = outer.grow(-2.0)
		draw_rect(inner, floor_col)
		draw_rect(Rect2(inner.position, Vector2(inner.size.x, 4.0)), Color(1, 1, 1, 0.035 + to_center * 0.035))
		draw_rect(Rect2(inner.position + Vector2(0.0, inner.size.y - 5.0), Vector2(inner.size.x, 5.0)), Color(0, 0, 0, 0.18))
		draw_rect(inner, Color(1, 1, 1, 0.03), false)

		var core: Rect2 = inner.grow(-4.0)
		draw_rect(core, Color(floor_col.r + 0.01, floor_col.g + 0.01, floor_col.b + 0.02, 0.18))
		draw_line(Vector2(core.position.x, core.position.y + core.size.y * 0.55), Vector2(core.end.x, core.position.y + core.size.y * 0.52), Color(1, 1, 1, 0.018), 1.0)

		for n in range(5):
			var noise: float = _hash01(x, y, n)
			var px: float = inner.position.x + 5.0 + noise * (inner.size.x - 10.0)
			var py: float = inner.position.y + 5.0 + _hash01(y, x, n + 19) * (inner.size.y - 10.0)
			draw_rect(Rect2(px, py, 1.2 + noise * 1.6, 1.0 + noise * 1.0), Color(1, 1, 1, 0.012 + noise * 0.022))
		if (x + y + tile.visual_variant) % 3 == 0:
			for n in range(3):
				var lx: float = inner.position.x + 6.0 + float(n) * 10.0
				draw_line(Vector2(lx, inner.position.y + 8.0), Vector2(lx + 8.0, inner.position.y + inner.size.y - 8.0), Color(1, 1, 1, 0.015), 1.0)
		if x > 0:
			draw_line(Vector2(rx, ry + 3.0), Vector2(rx, ry + t - 3.0), C_FLOOR_LINE, 1.0)
		if y > 0:
			draw_line(Vector2(rx + 3.0, ry), Vector2(rx + t - 3.0, ry), C_FLOOR_LINE, 1.0)
		if _hash01(x, y, 91) > 0.62:
			var stain: Rect2 = Rect2(rx + 10.0 + _hash01(x, y, 92) * 8.0, ry + 11.0 + _hash01(x, y, 93) * 8.0, 9.0 + _hash01(x, y, 94) * 8.0, 4.0 + _hash01(x, y, 95) * 5.0)
			draw_rect(stain, Color(0.0, 0.0, 0.0, 0.045))
	else:
		draw_rect(outer, Color(0.03, 0.04, 0.06, 1.0))
		draw_rect(Rect2(rx + 1.0, ry + 1.0, t - 2.0, t - 2.0), Color(C_WALL_GLOW.r, C_WALL_GLOW.g, C_WALL_GLOW.b, 0.05 + to_center * 0.03))
		draw_rect(Rect2(rx + 2.0, ry + 3.0, t - 4.0, t - 5.0), C_WALL_FACE)
		draw_rect(Rect2(rx + 2.0, ry + 2.0, t - 4.0, 9.0), C_WALL_TOP)
		draw_rect(Rect2(rx + 2.0, ry + 11.0, 6.0, t - 15.0), Color(0.05, 0.07, 0.10))
		draw_rect(Rect2(rx + t - 8.0, ry + 11.0, 6.0, t - 15.0), Color(0, 0, 0, 0.24))
		draw_rect(Rect2(rx + 2.0, ry + t - 7.0, t - 4.0, 5.0), Color(0, 0, 0, 0.26))
		draw_rect(Rect2(rx + 1.0, ry + 1.0, t - 2.0, t - 2.0), Color(C_WALL_EDGE.r, C_WALL_EDGE.g, C_WALL_EDGE.b, 0.36), false)
		draw_rect(Rect2(rx + 4.0, ry + 5.0, t - 8.0, 2.0), Color(1, 1, 1, 0.05))
		for row in PackedFloat32Array([14.0, 24.0, 34.0]):
			draw_line(Vector2(rx + 3.0, ry + row), Vector2(rx + t - 3.0, ry + row), Color(0.02, 0.02, 0.03, 0.42), 1.0)
		var offset: float = 16.0 if tile.visual_variant % 2 == 0 else 8.0
		for i in range(3):
			var xline: float = rx + offset + float(i) * 10.0
			draw_line(Vector2(xline, ry + 12.0), Vector2(xline, ry + t - 9.0), Color(0.02, 0.02, 0.03, 0.32), 1.0)
		for rivet in [Vector2(9.0, 8.0), Vector2(t - 9.0, 8.0), Vector2(9.0, t - 9.0), Vector2(t - 9.0, t - 9.0)]:
			draw_circle(Vector2(rx, ry) + rivet, 1.4, Color(0.35, 0.42, 0.50, 0.52))
		var shine_y: float = 8.0 + fmod(t_ms * 0.012 + float(x + y) * 4.0, t - 12.0)
		draw_line(Vector2(rx + 6.0, ry + shine_y), Vector2(rx + t - 6.0, ry + shine_y - 3.0), Color(1, 1, 1, 0.05), 1.0)

func _draw_sector_overlays(map_pw: float, map_ph: float) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var sectors: Array = [
		{"name": "CELL BLOCK A", "rect": Rect2(0.0, 0.0, map_pw * 0.34, map_ph * 0.26), "col": Color(0.16, 0.42, 0.82, 0.085)},
		{"name": "MAIN CORRIDOR", "rect": Rect2(map_pw * 0.12, map_ph * 0.40, map_pw * 0.76, map_ph * 0.12), "col": Color(0.00, 0.90, 1.00, 0.05)},
		{"name": "SECURE YARD", "rect": Rect2(map_pw * 0.55, map_ph * 0.60, map_pw * 0.28, map_ph * 0.20), "col": Color(1.00, 0.43, 0.00, 0.045)},
	]
	for sector in sectors:
		var rect: Rect2 = sector["rect"]
		var col: Color = sector["col"]
		draw_rect(rect, col)
		draw_rect(rect, Color(col.r, col.g, col.b, 0.14), false)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4.0)), Color(col.r, col.g, col.b, 0.15))
		draw_string(font, rect.position + Vector2(12.0, 18.0), str(sector["name"]), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, 11, Color(col.r + 0.22, col.g + 0.22, col.b + 0.22, 0.55))
		if str(sector["name"]).begins_with("CELL"):
			_draw_cell_bar_region(rect)

func _draw_cell_bar_region(rect: Rect2) -> void:
	var cell_w: float = 56.0
	var shine_x: float = rect.position.x + fmod(float(Time.get_ticks_msec()) * 0.03, cell_w)
	for x in range(int(rect.position.x + 10.0), int(rect.end.x - 8.0), int(cell_w)):
		for i in range(4):
			var bx: float = float(x) + 8.0 + float(i) * 10.0
			draw_line(Vector2(bx, rect.position.y + 28.0), Vector2(bx, rect.end.y - 10.0), Color(0.60, 0.72, 0.88, 0.16), 1.0)
			draw_line(Vector2(bx + 1.0, rect.position.y + 28.0), Vector2(bx + 1.0, rect.end.y - 10.0), Color(1, 1, 1, 0.06), 1.0)
	draw_rect(Rect2(shine_x, rect.position.y + 26.0, 4.0, rect.size.y - 38.0), Color(1, 1, 1, 0.05))

func _draw_global_vignette(map_pw: float, map_ph: float) -> void:
	for i in range(16):
		var inset: float = float(i) * 14.0
		var alpha: float = 0.010 + float(i) / 16.0 * 0.028
		draw_rect(Rect2(-inset, -inset, map_pw + inset * 2.0, map_ph + inset * 2.0), Color(0.0, 0.0, 0.0, alpha), false)
	_draw_light_pool(Vector2(map_pw * 0.50, map_ph * 0.50), map_pw * 0.18, Color(0.00, 0.90, 1.00, 0.03))

func _draw_exit(pos: Vector2i) -> void:
	if _exit_rotator == null:
		return
	var rx: float = float(pos.x * TILE_SIZE)
	var ry: float = float(pos.y * TILE_SIZE)
	var t: float = float(TILE_SIZE)
	var font: Font = ThemeDB.fallback_font
	var pulse: float = _exit_glow_alpha
	if _exit_rotator.is_active_exit(pos):
		_draw_light_pool(Vector2(rx + t * 0.5, ry + t * 0.5), 54.0, Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, 0.08 + pulse * 0.04))
		draw_rect(Rect2(rx - 10.0, ry - 10.0, t + 20.0, t + 20.0), Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, pulse * 0.08))
		draw_rect(Rect2(rx, ry, t, t), Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, 0.18))
		draw_rect(Rect2(rx + 2.0, ry + 2.0, t - 4.0, t - 4.0), Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, 0.88), false)
		draw_rect(Rect2(rx - 4.0, ry - 4.0, t + 8.0, t + 8.0), Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, pulse * 0.44), false)
		var chevron_a: PackedVector2Array = PackedVector2Array([Vector2(rx + 8.0, ry + t * 0.5), Vector2(rx + 18.0, ry + 16.0), Vector2(rx + 18.0, ry + t - 16.0)])
		var chevron_b: PackedVector2Array = PackedVector2Array([Vector2(rx + t - 8.0, ry + t * 0.5), Vector2(rx + t - 18.0, ry + 16.0), Vector2(rx + t - 18.0, ry + t - 16.0)])
		draw_colored_polygon(chevron_a, C_HIGHLIGHT)
		draw_colored_polygon(chevron_b, C_HIGHLIGHT)
		if font != null:
			draw_string(font, Vector2(rx + 4.0, ry + t - 5.0), "EXIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_HIGHLIGHT)
	else:
		draw_rect(Rect2(rx, ry, t, t), Color(C_WARNING.r, C_WARNING.g, C_WARNING.b, 0.12))
		draw_rect(Rect2(rx + 2.0, ry + 2.0, t - 4.0, t - 4.0), Color(C_WARNING.r, C_WARNING.g, C_WARNING.b, 0.40), false)
		if font != null:
			draw_string(font, Vector2(rx + t * 0.36, ry + t - 6.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_WARNING)

func _draw_door_visual(door: DoorInteractable) -> void:
	var pos: Vector2i = door.grid_pos
	var rx: float = float(pos.x * TILE_SIZE)
	var ry: float = float(pos.y * TILE_SIZE)
	var t: float = float(TILE_SIZE)
	var state_enum: int = door.get_state_enum()
	for i in range(4):
		draw_rect(Rect2(rx + float(i), ry + float(i), t - float(i) * 2.0, t - float(i) * 2.0), Color(0.24, 0.28, 0.34), false)
	match state_enum:
		DoorInteractable.State.LOCKED:
			draw_rect(Rect2(rx + 4.0, ry + 4.0, t - 8.0, t - 8.0), C_DOOR_LOCK)
			_draw_hazard_stripes(Rect2(rx + 4.0, ry + 4.0, t - 8.0, 6.0))
			draw_rect(Rect2(rx + t * 0.35, ry + t * 0.48, t * 0.30, t * 0.22), Color(0.88, 0.75, 0.22))
			draw_arc(Vector2(rx + t * 0.50, ry + t * 0.48), t * 0.11, PI, TAU, 12, Color(0.88, 0.75, 0.22), 2.0)
			draw_circle(Vector2(rx + t * 0.72, ry + t * 0.52), 3.0, Color(0.85, 0.75, 0.20))
		DoorInteractable.State.UNLOCKED:
			draw_rect(Rect2(rx + 4.0, ry + 4.0, t - 8.0, t - 8.0), Color(0.35, 0.28, 0.18))
			draw_rect(Rect2(rx + 10.0, ry + 8.0, 2.0, t - 16.0), Color(0.15, 0.10, 0.06))
			draw_rect(Rect2(rx + 18.0, ry + 8.0, 2.0, t - 16.0), Color(0.15, 0.10, 0.06))
			draw_circle(Vector2(rx + t * 0.72, ry + t * 0.52), 3.0, Color(0.78, 0.68, 0.24))
		DoorInteractable.State.OPENING:
			draw_rect(Rect2(rx + 4.0, ry + 4.0, (t - 8.0) * 0.45, t - 8.0), Color(0.35, 0.28, 0.18))
			_draw_hazard_stripes(Rect2(rx + t * 0.52, ry + 6.0, t * 0.18, t - 12.0))
		DoorInteractable.State.OPEN:
			_draw_hazard_stripes(Rect2(rx + t * 0.18, ry + 6.0, t * 0.64, t - 12.0))

func _draw_hazard_stripes(rect: Rect2) -> void:
	draw_rect(rect, Color(0.08, 0.08, 0.08, 0.88))
	var step: float = 8.0
	var x: float = rect.position.x - rect.size.y
	while x < rect.end.x:
		var pts: PackedVector2Array = PackedVector2Array([
			Vector2(x, rect.position.y),
			Vector2(x + 6.0, rect.position.y),
			Vector2(x + rect.size.y + 6.0, rect.end.y),
			Vector2(x + rect.size.y, rect.end.y),
		])
		draw_colored_polygon(pts, C_WARNING)
		x += step

func _draw_light_pool(center: Vector2, radius: float, color: Color) -> void:
	var bloom_mul: float = 1.0
	if UserSettings != null:
		bloom_mul = 1.35 if UserSettings.bloom_glow_enabled else 0.72
	for i in range(6):
		var k: float = 1.0 - float(i) / 6.0
		draw_circle(center, radius * k, Color(color.r, color.g, color.b, color.a * k * 0.55 * bloom_mul))

func _hash01(x: int, y: int, seed: int = 0) -> float:
	var n: int = x * 928371 + y * 689287 + seed * 283923
	n = int(abs(sin(float(n)) * 43758.5453) * 10000.0)
	return fmod(float(n), 1000.0) / 1000.0

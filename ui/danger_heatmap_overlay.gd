extends Node2D
class_name DangerHeatmapOverlay

## Colours each tile by its current danger value from DangerMap.
## World-space Node2D — coordinates match GridRenderer exactly.
## Toggle visibility with F3 via OverlayManager.

const TILE_SIZE : int   = 48
const MAX_DANGER: float = 12.0   # value at which colour saturates to full red

var _danger_map: DangerMap = null
var _grid: GridEngine = null

# -------------------------------------------------------------------------

func setup(danger_map: DangerMap, grid: GridEngine = null) -> void:
	_danger_map = danger_map
	_grid = grid
	EventBus.danger_map_updated.connect(_on_danger_map_updated)

# -------------------------------------------------------------------------

func _on_danger_map_updated() -> void:
	if visible:
		queue_redraw()

# -------------------------------------------------------------------------

func _draw() -> void:
	if _danger_map == null:
		return

	for pos: Vector2i in _danger_map.get_all():
		var val: float = _danger_map.get_danger(pos)
		if val <= 0.0:
			continue

		var t: float = clampf(val / MAX_DANGER, 0.0, 1.0)

		# Gradient: low danger = dim yellow, high danger = vivid red
		var r: float = 1.0
		var g: float = lerpf(0.75, 0.0, t)
		var a: float = lerpf(0.10, 0.50, t)
		var col := Color(r, g, 0.0, a)

		var rx := float(pos.x * TILE_SIZE)
		var ry := float(pos.y * TILE_SIZE)
		draw_rect(Rect2(rx, ry, TILE_SIZE, TILE_SIZE), col)

	# Legend strip — bottom-left of the map area (screen-space would need CanvasLayer,
	# so we draw it in world space just below the grid)
	_draw_legend()

func _draw_legend() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var lx : float = 4.0
	var map_h_tiles: int = _grid.get_height() if _grid != null else 20
	var ly : float = float(map_h_tiles * TILE_SIZE) + 8.0
	var lw : float = 160.0
	var lh : float = 10.0

	# Gradient bar
	for i in range(int(lw)):
		var t  := float(i) / lw
		var r  := 1.0
		var g  := lerpf(0.75, 0.0, t)
		draw_line(Vector2(lx + i, ly), Vector2(lx + i, ly + lh), Color(r, g, 0.0, 0.70), 1.0)

	# Border
	draw_rect(Rect2(lx, ly, lw, lh), Color(1, 1, 1, 0.25), false)

	# Labels
	draw_string(font, Vector2(lx, ly + lh + 13.0), "danger",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.9, 0.9, 0.80))
	draw_string(font, Vector2(lx + lw - 10.0, ly + lh + 13.0),
		str(int(MAX_DANGER)) + "+",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.9, 0.9, 0.80))

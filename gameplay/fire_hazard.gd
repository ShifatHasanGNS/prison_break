extends Node2D
class_name FireHazard

# Fire tiles are FIXED at map load — they never spread.
# Danger seeded once and re-applied every rebuild_maps call.

const TILE_SIZE        : int   = 48
const DAMAGE_PER_TICK  : float = 8.0
const TILE_DANGER      : float = 8.0
const ADJACENT_DANGER  : float = 4.0
const FIRE_ALERT_DURATION: int = 2

var _fire_tiles: Array[Vector2i] = []
var _grid: Node = null

# Tracks which agents were on fire last tick to detect entry
var _agents_on_fire: Dictionary = {}  # agent_id -> true

# -------------------------------------------------------------------------

func setup(fire_tiles: Array, grid: Node) -> void:
	_grid = grid
	_fire_tiles.clear()
	for ft in fire_tiles:
		_fire_tiles.append(ft as Vector2i)
	print("FireHazard: %d fixed fire tiles placed" % _fire_tiles.size())

## Called every tick from SimulationLoop._update_hazards().
## Applies fire damage and emits entry events.
func tick(agents: Array) -> void:
	var currently_on_fire: Dictionary = {}

	for agent in agents:
		if not agent.get("is_active"):
			continue
		var pos: Vector2i = agent.get("grid_pos")
		if pos in _fire_tiles:
			var id: int = agent.get("agent_id")
			currently_on_fire[id] = true

			# First-entry detection
			if not _agents_on_fire.has(id):
				EventBus.emit_signal("agent_entered_fire", id, pos)
				# Apply alert (Detected) effect for FIRE_ALERT_DURATION ticks
				var alert_effect := EffectDetected.new()
				alert_effect.refresh(FIRE_ALERT_DURATION)
				agent.apply_effect(alert_effect)
				print("  [%s] entered fire at %s!" % [agent.get("_role"), pos])

			# Damage per tick while on fire
			var hp: float = agent.get("health")
			agent.set("health", maxf(hp - DAMAGE_PER_TICK, 0.0))
			print("  [%s] fire damage -%.0f hp → %.0f" % [
				agent.get("_role"), DAMAGE_PER_TICK, agent.get("health")
			])

	_agents_on_fire = currently_on_fire

## Re-apply static fire danger to DangerMap each rebuild cycle.
## Called from SimulationLoop._rebuild_maps().
func seed_danger(danger_map: DangerMap) -> void:
	var dirs: Array[Vector2i] = [
		Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)
	]
	for ft: Vector2i in _fire_tiles:
		danger_map.set_danger(ft, TILE_DANGER)
		for d: Vector2i in dirs:
			var adj: Vector2i = ft + d
			# Only add adjacent danger; don't overwrite a higher fire-tile value
			var existing: float = danger_map.get_danger(adj)
			if existing < ADJACENT_DANGER:
				danger_map.set_danger(adj, ADJACENT_DANGER)

func get_fire_tiles() -> Array[Vector2i]:
	return _fire_tiles

# =========================================================================
# DRAWING  (procedural flame animation — runs every frame)
# =========================================================================

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if _fire_tiles.is_empty():
		return
	var t_ms := float(Time.get_ticks_msec())
	var T    := float(TILE_SIZE)

	for ft: Vector2i in _fire_tiles:
		_draw_fire_tile(ft, T, t_ms)

func _draw_fire_tile(ft: Vector2i, T: float, t_ms: float) -> void:
	var rx := float(ft.x * TILE_SIZE)
	var ry := float(ft.y * TILE_SIZE)

	# --- Outer glow (drawn first, slightly larger than tile) ---
	draw_rect(Rect2(rx - 3, ry - 3, T + 6, T + 6),
		Color(0.90, 0.40, 0.05, 0.12))

	# --- Dark red base ---
	draw_rect(Rect2(rx, ry, T, T), Color(0.45, 0.08, 0.02, 0.92))

	# --- Flame tongue heights (sin-driven per-tile flicker) ---
	var lh := T * clampf(0.52 + 0.16 * sin(t_ms * 0.0038),           0.28, 0.72)
	var ch := T * clampf(0.68 + 0.16 * sin(t_ms * 0.0029 + 1.6),     0.38, 0.88)
	var rh := T * clampf(0.58 + 0.14 * sin(t_ms * 0.0051 + 3.1),     0.30, 0.76)

	# Left tongue — orange triangle
	draw_colored_polygon(PackedVector2Array([
		Vector2(rx + T * 0.04, ry + T),
		Vector2(rx + T * 0.32, ry + T),
		Vector2(rx + T * 0.16, ry + T - lh),
	]), Color(0.95, 0.42, 0.05))

	# Centre tongue — bright yellow-orange, tallest
	draw_colored_polygon(PackedVector2Array([
		Vector2(rx + T * 0.24, ry + T),
		Vector2(rx + T * 0.76, ry + T),
		Vector2(rx + T * 0.50, ry + T - ch),
	]), Color(1.00, 0.72, 0.10))
	# Bright inner highlight on centre tongue
	draw_colored_polygon(PackedVector2Array([
		Vector2(rx + T * 0.34, ry + T),
		Vector2(rx + T * 0.66, ry + T),
		Vector2(rx + T * 0.50, ry + T - ch * 0.55),
	]), Color(1.00, 0.95, 0.50, 0.70))

	# Right tongue — orange
	draw_colored_polygon(PackedVector2Array([
		Vector2(rx + T * 0.68, ry + T),
		Vector2(rx + T * 0.94, ry + T),
		Vector2(rx + T * 0.80, ry + T - rh),
	]), Color(0.95, 0.42, 0.05))

	# --- Ember particles (4 per tile, each toggled by time slot) ---
	var em_x := [T * 0.18, T * 0.38, T * 0.58, T * 0.78]
	for i in range(4):
		var phase := fmod(t_ms * 0.001 + float(i) * 0.62, 1.0)
		if phase > 0.45:
			var ey := ry + T * (0.20 + 0.18 * sin(t_ms * 0.0022 + float(i) * 1.4))
			draw_rect(Rect2(rx + em_x[i] - 1.0, ey - 1.0, 2.5, 2.5),
				Color(1.00, 0.88, 0.20))

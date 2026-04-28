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
		# Police are not harmed by fire — they know the prison layout
		if agent.get("_role") == "police":
			continue
		var pos: Vector2i = agent.get("grid_pos")
		if pos in _fire_tiles:
			var id: int = agent.get("agent_id")
			currently_on_fire[id] = true

			# First-entry detection
			if not _agents_on_fire.has(id):
				EventBus.emit_signal("agent_entered_fire", id, pos)
				# Apply alert (Detected) effect for FIRE_ALERT_DURATION ticks
				var alert_effect: EffectDetected = EffectDetected.new()
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
	var t_ms: float = float(Time.get_ticks_msec())
	var t: float = float(TILE_SIZE)
	for ft: Vector2i in _fire_tiles:
		var rx := float(ft.x * TILE_SIZE)
		var ry := float(ft.y * TILE_SIZE)
		var pulse := 0.5 + 0.5 * sin(t_ms * 0.004 + float(ft.x + ft.y))
		var center := Vector2(rx + t * 0.5, ry + t * 0.58)

		for i in range(5):
			var radius := t * (0.28 + float(i) * 0.10) + pulse * 2.0
			draw_circle(center, radius, Color(1.00, 0.36, 0.04, 0.05 - float(i) * 0.008))
		draw_rect(Rect2(rx, ry, t, t), Color(0.18, 0.03, 0.02, 0.92))
		draw_rect(Rect2(rx + 4.0, ry + 4.0, t - 8.0, t - 8.0), Color(0.35, 0.07, 0.03, 0.22 + pulse * 0.08))

		for s in range(4):
			var smoke_x := rx + t * (0.20 + float(s) * 0.18)
			var smoke_y := ry + t * (0.24 - 0.08 * sin(t_ms * 0.0018 + float(s)))
			draw_circle(Vector2(smoke_x, smoke_y), 4.0 + float(s), Color(0.12, 0.12, 0.12, 0.12))

		var h1 := t * clampf(0.54 + 0.18 * sin(t_ms * 0.0038), 0.28, 0.78)
		var h2 := t * clampf(0.72 + 0.14 * sin(t_ms * 0.0027 + 1.4), 0.36, 0.88)
		var h3 := t * clampf(0.58 + 0.16 * sin(t_ms * 0.0049 + 2.8), 0.28, 0.80)
		draw_colored_polygon(PackedVector2Array([
			Vector2(rx + t * 0.08, ry + t),
			Vector2(rx + t * 0.34, ry + t),
			Vector2(rx + t * 0.18, ry + t - h1),
		]), Color(0.96, 0.40, 0.06))
		draw_colored_polygon(PackedVector2Array([
			Vector2(rx + t * 0.24, ry + t),
			Vector2(rx + t * 0.78, ry + t),
			Vector2(rx + t * 0.50, ry + t - h2),
		]), Color(1.00, 0.72, 0.10))
		draw_colored_polygon(PackedVector2Array([
			Vector2(rx + t * 0.36, ry + t),
			Vector2(rx + t * 0.64, ry + t),
			Vector2(rx + t * 0.50, ry + t - h2 * 0.56),
		]), Color(1.00, 0.95, 0.55, 0.82))
		draw_colored_polygon(PackedVector2Array([
			Vector2(rx + t * 0.66, ry + t),
			Vector2(rx + t * 0.94, ry + t),
			Vector2(rx + t * 0.80, ry + t - h3),
		]), Color(0.96, 0.38, 0.05))

		for i in range(5):
			var phase := fmod(t_ms * 0.001 + float(i) * 0.43, 1.0)
			if phase > 0.40:
				var ex := rx + t * (0.14 + float(i) * 0.15)
				var ey := ry + t * (0.16 + 0.20 * sin(t_ms * 0.002 + float(i) * 1.2))
				draw_rect(Rect2(ex - 1.0, ey - 1.0, 2.5, 2.5), Color(1.00, 0.88, 0.22, 0.88))

extends Node2D
class_name Agent

const TILE_SIZE: int = 48

var agent_id: int = -1
var grid_pos: Vector2i = Vector2i.ZERO
var initial_pos: Vector2i = Vector2i.ZERO
var stats: AgentStats = null

var health: float = 100.0
var stamina: float = 100.0
var stealth_level: float = 100.0
var is_active: bool = true
var capture_count: int = 0
var escape_rank: int = -1
var elimination_tick: int = -1
var camera_detections: int = 0
## MINOR #2 FIX: camera_detections is now per-life (reset on respawn).
## total_camera_detections accumulates across all lives for the results screen.
var total_camera_detections: int = 0
var cctv_alert_target: Vector2i = Vector2i(-1, -1)
var cctv_alert_ticks: int = 0
var metrics: Dictionary = {
	"moves": 0,
	"waits": 0,
	"abilities": 0,
	"sprints": 0,
	# FIX #5: captures_inflicted removed — agent.capture_count is the single
	# source of truth, always incremented synchronously in simulation_loop.
	"raw_score": 0.0,
	"performance": 50.0,
	"best_progress_cells": 0,
	"dog_zone_time": 0.0,
	"camera_hits": 0,
	"wall_hits": 0,
	"dog_assists": 0,
	"cctv_assists": 0,
	"fire_assists": 0,
	"escapes_allowed": 0,
	"captures_made": 0,
	"alert_level": 0.0,
}

var capture_cooldown_ticks: int = 0

var _status_effects: Array[StatusEffect] = []
var _abilities: Array[Ability] = []
var _ai_controller: AIController = null

var _role: String = ""
var _facing: Vector2i = Vector2i(1, 0)
var _bob: float = 0.0
var _visual_target_pos: Vector2 = Vector2.ZERO
var _step_phase: float = 0.0
var _trail_points: Array[Vector2] = []
const TRAIL_MAX: int = 7
var movement_speed_multiplier: float = 1.0
var _temporary_slows: Dictionary = {}
var _movement_tick_accumulator: float = 0.0

# --- Pathfinding ---
var _needs_replan: bool = false

# -------------------------------------------------------------------------
# Lifecycle
# -------------------------------------------------------------------------

func _ready() -> void:
	z_index = 2   # renders above dog (z=1) and grid
	add_to_group("agents")  # FIX #6: allows respawn BFS to find police positions
	# Transient visual effects spawned in response to simulation events
	EventBus.agent_status_changed.connect(_on_status_changed_fx)
	EventBus.agent_captured.connect(_on_captured_fx)
	EventBus.agent_escaped.connect(_on_escaped_fx)
	EventBus.agent_entered_fire.connect(_on_fire_fx)
	EventBus.agent_action_chosen.connect(_on_action_chosen_fx)
	EventBus.camera_detection.connect(_on_camera_detection)

func _process(delta: float) -> void:
	var move_delta: Vector2 = _visual_target_pos - position
	var visual_speed: float = maxf(0.2, movement_speed_multiplier)
	position += move_delta * minf(1.0, delta * 10.0 * visual_speed)
	_step_phase += delta * (12.0 if move_delta.length() > 0.5 else 4.0)
	_bob = sin(_step_phase)
	if move_delta.length() > 0.25:
		if _trail_points.is_empty() or _trail_points[_trail_points.size() - 1].distance_to(global_position) > 4.0:
			_trail_points.append(global_position)
			if _trail_points.size() > TRAIL_MAX:
				_trail_points.pop_front()
	queue_redraw()

# -------------------------------------------------------------------------
# Setup / movement
# -------------------------------------------------------------------------

func setup(id: int, pos: Vector2i, agent_stats: AgentStats) -> void:
	agent_id = id
	grid_pos = pos
	initial_pos = pos
	stats = agent_stats
	health = stats.max_health
	stamina = stats.max_stamina
	stealth_level = 100.0
	set_grid_visual_pos()

func set_grid_visual_pos() -> void:
	_visual_target_pos = Vector2(
		grid_pos.x * TILE_SIZE + TILE_SIZE / 2.0,
		grid_pos.y * TILE_SIZE + TILE_SIZE / 2.0
	)
	position = _visual_target_pos
	queue_redraw()

func respawn() -> void:
	# FIX #6: Pick a safe respawn tile that is farthest from the nearest police
	# so the police cannot camp initial_pos and chain-capture.
	grid_pos = _pick_safe_respawn_pos()
	initial_pos = grid_pos  # update so future respawns also use a rotated safe point
	var max_hp: float = stats.max_health if stats != null else 100.0
	health = maxf(1.0, max_hp - 25.0)
	stamina = stats.max_stamina if stats != null else 100.0
	stealth_level = 50.0
	# FIX #6: 20 ticks (~5 s at 4 Hz) instead of 10 (~2.5 s).
	# Police base_speed=2 can reach 5 tiles in ~1.25 s, so 10 ticks was
	# frequently not enough to clear the spawn zone before immunity expired.
	capture_cooldown_ticks = 20
	_status_effects.clear()
	# MINOR #2 FIX: Reset per-life camera_detections; accumulate into total.
	total_camera_detections += camera_detections
	camera_detections = 0
	cctv_alert_target = Vector2i(-1, -1)
	cctv_alert_ticks = 0
	movement_speed_multiplier = 1.0
	_temporary_slows.clear()
	_movement_tick_accumulator = 0.0
	if _ai_controller != null and _ai_controller.has_method("clear_history"):
		_ai_controller.clear_history()
	set_grid_visual_pos()
	EventBus.emit_signal("agent_respawned", agent_id)
	print("  [%s] RESPAWNED at %s (total captures: %d)" % [_role, grid_pos, capture_count])

# FIX #6: Find the walkable tile reachable from initial_pos that is farthest
# from any active police agent.  Falls back to initial_pos if no grid is available.
func _pick_safe_respawn_pos() -> Vector2i:
	# We don't store a reference to the grid or agents directly on Agent, so we
	# read police positions from the scene tree via the EventBus agent list.
	# Use a BFS from initial_pos to enumerate nearby walkable tiles, then pick
	# the one with maximum minimum-distance to any police position.
	var police_tiles: Array[Vector2i] = []
	for node in get_tree().get_nodes_in_group("agents"):
		var a: Agent = node as Agent
		if a != null and a._role == "police" and a.is_active:
			police_tiles.append(a.grid_pos)

	# If no police found or no grid, return original spawn point.
	var grid_node: Node = get_node_or_null("/root/Game/GridEngine")
	if grid_node == null:
		grid_node = get_node_or_null("/root/Main/Game/GridEngine")
	if grid_node == null or police_tiles.is_empty():
		return initial_pos

	# BFS to collect candidate tiles within radius 6 of initial_pos.
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [initial_pos]
	visited[initial_pos] = true
	var candidates: Array[Vector2i] = []
	var max_radius: int = 6

	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		candidates.append(cur)
		for nb in grid_node.get_neighbours(cur):
			if visited.has(nb):
				continue
			if not grid_node.is_walkable(nb):
				continue
			if abs(nb.x - initial_pos.x) + abs(nb.y - initial_pos.y) > max_radius:
				continue
			visited[nb] = true
			queue.append(nb)

	if candidates.is_empty():
		return initial_pos

	# Pick candidate farthest from nearest police.
	var best_tile: Vector2i = initial_pos
	var best_dist: int = -1
	for c in candidates:
		var min_pd: int = 999999
		for pt in police_tiles:
			var d: int = abs(c.x - pt.x) + abs(c.y - pt.y)
			if d < min_pd:
				min_pd = d
		if min_pd > best_dist:
			best_dist = min_pd
			best_tile = c
	return best_tile

func move_to(pos: Vector2i) -> void:
	var old_pos: Vector2i = grid_pos
	var dir: Vector2i = pos - old_pos
	if dir != Vector2i.ZERO:
		_facing = dir
		metrics["moves"] = int(metrics.get("moves", 0)) + 1
	grid_pos = pos
	_visual_target_pos = Vector2(
		grid_pos.x * TILE_SIZE + TILE_SIZE / 2.0,
		grid_pos.y * TILE_SIZE + TILE_SIZE / 2.0
	)
	queue_redraw()
	EventBus.emit_signal("agent_moved", agent_id, old_pos, pos)

# -------------------------------------------------------------------------
# Status effects
# -------------------------------------------------------------------------

func tick_status_effects() -> void:
	if capture_cooldown_ticks > 0:
		capture_cooldown_ticks -= 1
	if cctv_alert_ticks > 0:
		cctv_alert_ticks -= 1
		if cctv_alert_ticks <= 0:
			cctv_alert_target = Vector2i(-1, -1)

	var to_remove: Array = []
	for effect in _status_effects:
		effect.apply_tick(self)
		if effect.is_expired(self):
			to_remove.append(effect)
	for effect in to_remove:
		_remove_effect(effect)

	if stats != null:
		var regen: float = stats.stamina_regen
		if has_status("exhausted"):
			regen *= 0.5
		stamina = minf(stamina + regen, stats.max_stamina)

	if stamina <= 0.0 and not has_status("exhausted"):
		apply_effect(EffectExhausted.new())

func apply_effect(effect: StatusEffect) -> void:
	for existing in _status_effects:
		if existing.effect_name == effect.effect_name:
			existing.refresh(effect._ticks_remaining)
			return
	_status_effects.append(effect)
	effect.on_apply(self)   # effect subclass emits agent_status_changed

func _remove_effect(effect: StatusEffect) -> void:
	_status_effects.erase(effect)
	effect.on_remove(self)  # effect subclass emits agent_status_changed

func has_status(name: String) -> bool:
	for e in _status_effects:
		if e.effect_name == name:
			return true
	return false

func remove_status(name: String) -> void:
	var to_remove: Array[StatusEffect] = []
	for e in _status_effects:
		if e.effect_name == name:
			to_remove.append(e)
	for e in to_remove:
		_remove_effect(e)

func apply_temporary_slow(source: String, multiplier: float) -> void:
	_temporary_slows[source] = clampf(multiplier, 0.1, 1.0)
	_recompute_speed_multiplier()

func clear_temporary_slow(source: String) -> void:
	if _temporary_slows.has(source):
		_temporary_slows.erase(source)
	_recompute_speed_multiplier()

func _recompute_speed_multiplier() -> void:
	var mult: float = 1.0
	for key in _temporary_slows.keys():
		mult *= float(_temporary_slows[key])
	movement_speed_multiplier = clampf(mult, 0.1, 1.0)

func can_execute_movement_this_tick() -> bool:
	if movement_speed_multiplier >= 0.999:
		_movement_tick_accumulator = 0.0
		return true
	_movement_tick_accumulator += movement_speed_multiplier
	if _movement_tick_accumulator >= 1.0:
		_movement_tick_accumulator -= 1.0
		return true
	return false

func status_summary() -> String:
	if _status_effects.is_empty():
		return "none"
	var parts: Array[String] = []
	for e in _status_effects:
		var remaining: String = str(e._ticks_remaining) if e._ticks_remaining >= 0 else "∞"
		parts.append("%s(%s)" % [e.effect_name, remaining])
	return ", ".join(parts)

# -------------------------------------------------------------------------
# Stats helpers
# -------------------------------------------------------------------------

func get_effective_stealth() -> int:
	if has_status("hidden"):
		return 10
	return stats.stealth if stats != null else 5

func get_effective_noise() -> int:
	if has_status("hidden"):
		return 0
	return stats.base_noise if stats != null else 4

func get_effective_speed() -> int:
	var speed: int = stats.base_speed if stats != null else 1
	if has_status("exhausted"):
		speed = maxi(1, speed / 2)
	if has_status("speed_boost"):
		speed += get_speed_bonus()
	if has_status("dog_pinned"):
		speed = maxi(1, int(round(float(speed) * get_dog_pinned_speed_factor())))
	return speed

func get_speed_bonus() -> int:
	for e in _status_effects:
		if e.effect_name == "speed_boost":
			return e.speed_bonus
	return 0

func get_dog_pinned_speed_factor() -> float:
	for e in _status_effects:
		if e.effect_name == "dog_pinned":
			return float(e.speed_factor)
	return 1.0

func tick_ability_cooldowns() -> void:
	for ability in _abilities:
		ability.tick_cooldown()

func get_ability(name: String) -> Variant:
	for ability in _abilities:
		if ability.ability_name == name:
			return ability
	return null

func on_exit_changed(new_exit: Vector2i) -> void:
	_needs_replan = true
	print("  [%s] replan flagged → new exit %s" % [_role, new_exit])

func record_wait() -> void:
	metrics["waits"] = int(metrics.get("waits", 0)) + 1

func record_ability_use() -> void:
	metrics["abilities"] = int(metrics.get("abilities", 0)) + 1

func record_sprint() -> void:
	metrics["sprints"] = int(metrics.get("sprints", 0)) + 1

# =========================================================================
# DRAWING  (pixel-art quality — all shapes, no sprites)
# =========================================================================

func _draw() -> void:
	if not is_active:
		return
	var t := float(TILE_SIZE)
	var bob: float = _bob * 1.6
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.004)
	var glow_col: Color = _role_glow_color()
	if UserSettings != null and UserSettings.motion_trails_enabled:
		_draw_motion_trails()
	draw_circle(Vector2(0.0, bob * 0.20), t * 0.48, Color(glow_col.r, glow_col.g, glow_col.b, 0.10 + pulse * 0.04))
	draw_circle(Vector2(0.0, bob * 0.20), t * 0.34, Color(glow_col.r, glow_col.g, glow_col.b, 0.06 + pulse * 0.03))
	_draw_ellipse(Vector2(0.0, t * 0.31), Vector2(t * 0.32, t * 0.10), Color(0, 0, 0, 0.36))
	_draw_ellipse(Vector2(0.0, t * 0.29), Vector2(t * 0.22, t * 0.05), Color(0, 0, 0, 0.12))
	match _role:
		"rusher_red":
			_draw_rusher(bob)
		"sneaky_blue":
			_draw_sneaky(bob)
		"police":
			_draw_police(bob)
	_draw_status_indicators(bob)

func _draw_rusher(bob: float) -> void:
	var t := float(TILE_SIZE)
	var skin: Color = Color(0.67, 0.38, 0.22)
	var orange: Color = Color(0.90, 0.28, 0.10)
	var orange_dark: Color = Color(0.72, 0.18, 0.05)
	var outline: Color = Color(0.08, 0.05, 0.04)
	var boots: Color = Color(0.09, 0.08, 0.08)
	var eye_shift: float = t * 0.025 * _facing_sign()
	var sway: float = sin(float(Time.get_ticks_msec()) * 0.007) * 1.2

	_draw_block(Rect2(-t*0.21, t*0.03 + bob, t*0.17, t*0.27), orange_dark, outline)
	_draw_block(Rect2( t*0.04, t*0.03 + bob, t*0.17, t*0.27), orange, outline)
	_draw_block(Rect2(-t*0.23, t*0.29 + bob, t*0.20, t*0.08), boots, outline)
	_draw_block(Rect2( t*0.03, t*0.29 + bob, t*0.20, t*0.08), boots, outline)

	_draw_block(Rect2(-t*0.31, -t*0.18 + bob, t*0.62, t*0.34), orange, outline)
	_draw_block(Rect2(-t*0.16, -t*0.12 + bob, t*0.32, t*0.10), Color(0.99, 0.80, 0.68), outline)
	draw_line(Vector2(0.0, -t*0.16 + bob), Vector2(0.0, t*0.14 + bob), Color(0.55, 0.12, 0.05), 2.0)
	var font: Font = ThemeDB.fallback_font
	if font != null:
		draw_string(font, Vector2(-t*0.04, -t*0.02 + bob), "47", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.88))

	_draw_block(Rect2(-t*0.39, -t*0.15 + bob, t*0.13, t*0.22), orange_dark, outline)
	_draw_block(Rect2( t*0.26, -t*0.15 + bob, t*0.13, t*0.22), orange, outline)
	draw_rect(Rect2(-t*0.40, t*0.04 + bob + sway, t*0.12, t*0.07), skin)
	draw_rect(Rect2( t*0.28, t*0.04 + bob - sway, t*0.12, t*0.07), skin)

	draw_rect(Rect2(-t*0.05, -t*0.24 + bob, t*0.10, t*0.06), skin)
	_draw_ellipse(Vector2(0.0, -t*0.33 + bob), Vector2(t*0.19, t*0.17), Color(0.16, 0.09, 0.05))
	_draw_ellipse(Vector2(0.0, -t*0.30 + bob), Vector2(t*0.17, t*0.15), skin)
	draw_line(Vector2(-t*0.12, -t*0.36 + bob), Vector2(-t*0.03, -t*0.32 + bob), outline, 2.0)
	draw_line(Vector2( t*0.12, -t*0.36 + bob), Vector2( t*0.03, -t*0.32 + bob), outline, 2.0)
	draw_circle(Vector2(-t*0.06 + eye_shift, -t*0.31 + bob), 2.2, Color.WHITE)
	draw_circle(Vector2( t*0.06 + eye_shift, -t*0.31 + bob), 2.2, Color.WHITE)
	draw_circle(Vector2(-t*0.06 + eye_shift * 1.5, -t*0.31 + bob), 1.0, outline)
	draw_circle(Vector2( t*0.06 + eye_shift * 1.5, -t*0.31 + bob), 1.0, outline)
	draw_line(Vector2(-t*0.07, -t*0.24 + bob), Vector2(t*0.07, -t*0.23 + bob), Color(0.34, 0.10, 0.08), 2.0)

func _draw_sneaky(bob: float) -> void:
	var t := float(TILE_SIZE)
	var skin := Color(0.76, 0.55, 0.34)
	var blue := Color(0.14, 0.56, 0.86)
	var blue_dark := Color(0.07, 0.32, 0.66)
	var outline := Color(0.05, 0.07, 0.10)
	var shoes := Color(0.08, 0.10, 0.12)
	var eye_shift := t * 0.022 * _facing_sign()
	var sway := sin(float(Time.get_ticks_msec()) * 0.006 + 0.9) * 1.0

	_draw_block(Rect2(-t*0.20, t*0.03 + bob, t*0.16, t*0.27), blue_dark, outline)
	_draw_block(Rect2( t*0.04, t*0.03 + bob, t*0.16, t*0.27), blue, outline)
	_draw_block(Rect2(-t*0.22, t*0.29 + bob, t*0.19, t*0.08), shoes, outline)
	_draw_block(Rect2( t*0.03, t*0.29 + bob, t*0.19, t*0.08), shoes, outline)

	_draw_block(Rect2(-t*0.28, -t*0.17 + bob, t*0.56, t*0.33), blue, outline)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-t*0.06, -t*0.17 + bob),
		Vector2( t*0.06, -t*0.17 + bob),
		Vector2( t*0.02, -t*0.05 + bob),
		Vector2(-t*0.02, -t*0.05 + bob),
	]), Color(0.96, 0.98, 1.00))
	_draw_block(Rect2(-t*0.16, -t*0.02 + bob, t*0.14, t*0.07), blue_dark, outline)

	_draw_block(Rect2(-t*0.38, -t*0.14 + bob + sway, t*0.12, t*0.20), blue_dark, outline)
	_draw_block(Rect2( t*0.26, -t*0.14 + bob - sway, t*0.12, t*0.20), blue, outline)
	draw_rect(Rect2(-t*0.39, t*0.02 + bob + sway, t*0.11, t*0.07), skin)
	draw_rect(Rect2( t*0.28, t*0.02 + bob - sway, t*0.11, t*0.07), skin)

	draw_rect(Rect2(-t*0.05, -t*0.24 + bob, t*0.10, t*0.06), skin)
	_draw_ellipse(Vector2(0.0, -t*0.33 + bob), Vector2(t*0.18, t*0.16), Color(0.15, 0.08, 0.03))
	_draw_ellipse(Vector2(0.0, -t*0.30 + bob), Vector2(t*0.16, t*0.14), skin)
	draw_circle(Vector2(-t*0.05 + eye_shift, -t*0.31 + bob), 2.0, Color.WHITE)
	draw_circle(Vector2( t*0.05 + eye_shift, -t*0.31 + bob), 2.0, Color.WHITE)
	draw_circle(Vector2(-t*0.05 + eye_shift * 1.4, -t*0.31 + bob), 0.9, outline)
	draw_circle(Vector2( t*0.05 + eye_shift * 1.4, -t*0.31 + bob), 0.9, outline)
	draw_line(Vector2(-t*0.08, -t*0.25 + bob), Vector2(t*0.08, -t*0.25 + bob), Color(0.43, 0.21, 0.12), 1.5)
	draw_line(Vector2(-t*0.09, -t*0.35 + bob), Vector2(-t*0.02, -t*0.34 + bob), outline, 1.5)
	draw_line(Vector2(t*0.09, -t*0.35 + bob), Vector2(t*0.02, -t*0.34 + bob), outline, 1.5)

func _draw_police(bob: float) -> void:
	var t := float(TILE_SIZE)
	var skin := Color(0.78, 0.52, 0.30)
	var navy := Color(0.12, 0.19, 0.42)
	var navy_dark := Color(0.07, 0.12, 0.24)
	var vest := Color(0.05, 0.08, 0.17)
	var outline := Color(0.05, 0.05, 0.08)
	var boots := Color(0.06, 0.06, 0.08)
	var eye_shift := t * 0.020 * _facing_sign()
	var sway := sin(float(Time.get_ticks_msec()) * 0.006 + 2.0) * 1.0

	_draw_block(Rect2(-t*0.19, t*0.04 + bob, t*0.15, t*0.26), navy_dark, outline)
	_draw_block(Rect2( t*0.04, t*0.04 + bob, t*0.15, t*0.26), navy, outline)
	_draw_block(Rect2(-t*0.21, t*0.29 + bob, t*0.18, t*0.08), boots, outline)
	_draw_block(Rect2( t*0.03, t*0.29 + bob, t*0.18, t*0.08), boots, outline)

	_draw_block(Rect2(-t*0.27, -t*0.17 + bob, t*0.54, t*0.34), navy, outline)
	_draw_block(Rect2(-t*0.22, -t*0.13 + bob, t*0.44, t*0.24), vest, outline)
	draw_rect(Rect2(-t*0.20, -t*0.01 + bob, t*0.40, t*0.05), Color(0.03, 0.05, 0.08))
	draw_circle(Vector2(-t*0.10, -t*0.09 + bob), 2.0, Color(1.00, 0.84, 0.24))
	draw_rect(Rect2(-t*0.13, -t*0.04 + bob, t*0.10, t*0.06), Color(0.04, 0.07, 0.11))
	draw_rect(Rect2( t*0.03, -t*0.04 + bob, t*0.10, t*0.06), Color(0.04, 0.07, 0.11))

	_draw_block(Rect2(-t*0.37, -t*0.14 + bob + sway, t*0.12, t*0.22), navy_dark, outline)
	_draw_block(Rect2( t*0.25, -t*0.14 + bob - sway, t*0.12, t*0.22), navy, outline)
	draw_rect(Rect2(-t*0.38, t*0.04 + bob + sway, t*0.11, t*0.07), skin)
	draw_rect(Rect2( t*0.27, t*0.04 + bob - sway, t*0.11, t*0.07), skin)

	draw_rect(Rect2(-t*0.05, -t*0.24 + bob, t*0.10, t*0.06), skin)
	_draw_ellipse(Vector2(0.0, -t*0.33 + bob), Vector2(t*0.18, t*0.16), Color(0.10, 0.05, 0.02))
	_draw_ellipse(Vector2(0.0, -t*0.30 + bob), Vector2(t*0.16, t*0.14), skin)
	_draw_block(Rect2(-t*0.19, -t*0.42 + bob, t*0.38, t*0.07), Color(0.07, 0.10, 0.18), outline)
	draw_circle(Vector2(-t*0.05 + eye_shift, -t*0.31 + bob), 2.0, Color.WHITE)
	draw_circle(Vector2( t*0.05 + eye_shift, -t*0.31 + bob), 2.0, Color.WHITE)
	draw_circle(Vector2(-t*0.05 + eye_shift * 1.4, -t*0.31 + bob), 0.9, outline)
	draw_circle(Vector2( t*0.05 + eye_shift * 1.4, -t*0.31 + bob), 0.9, outline)
	draw_line(Vector2(-t*0.08, -t*0.35 + bob), Vector2(-t*0.02, -t*0.33 + bob), outline, 1.7)
	draw_line(Vector2(t*0.08, -t*0.35 + bob), Vector2(t*0.02, -t*0.33 + bob), outline, 1.7)
	draw_line(Vector2(-t*0.05, -t*0.24 + bob), Vector2(t*0.05, -t*0.24 + bob), Color(0.34, 0.18, 0.10), 1.6)

func _draw_status_indicators(bob: float) -> void:
	var y := -float(TILE_SIZE) * 0.58 + bob
	var x := -float(TILE_SIZE) * 0.22
	for effect in _status_effects:
		var col := Color(1.0, 1.0, 1.0, 0.95)
		match effect.effect_name:
			"detected": col = Color(1.0, 0.35, 0.20, 0.95)
			"hidden": col = Color(0.30, 0.95, 0.90, 0.95)
			"stunned": col = Color(1.0, 0.86, 0.22, 0.95)
			"exhausted": col = Color(0.90, 0.74, 0.12, 0.95)
			"dog_pinned": col = Color(1.00, 0.52, 0.12, 0.95)
		draw_rect(Rect2(x, y, 8.0, 8.0), col)
		draw_rect(Rect2(x, y, 8.0, 8.0), Color(0, 0, 0, 0.45), false)
		x += 10.0
	if camera_detections > 0:
		draw_arc(Vector2(0.0, -float(TILE_SIZE) * 0.62 + bob), float(TILE_SIZE) * 0.18, PI * 1.1, PI * 1.9, 12, Color(0.40, 1.0, 0.92, 0.65), 2.0)

func _draw_motion_trails() -> void:
	if _trail_points.is_empty():
		return
	var n: int = _trail_points.size()
	for i in range(n):
		var p: Vector2 = _trail_points[i]
		var rel: Vector2 = p - global_position
		var k: float = float(i + 1) / float(n)
		var a: float = 0.04 + k * 0.12
		var glow: Color = _role_glow_color()
		_draw_ellipse(rel + Vector2(0.0, 8.0), Vector2(3.0 + k * 5.0, 1.6 + k * 1.8), Color(0, 0, 0, a * 0.75))
		draw_circle(rel, 1.5 + k * 2.2, Color(glow.r, glow.g, glow.b, a * 0.55))

func _draw_block(rect: Rect2, fill: Color, outline: Color) -> void:
	draw_rect(rect, outline)
	var inner := rect.grow(-2.0)
	if inner.size.x > 0.0 and inner.size.y > 0.0:
		draw_rect(inner, fill)

func _role_glow_color() -> Color:
	match _role:
		"rusher_red":
			return Color(0.96, 0.28, 0.26)
		"sneaky_blue":
			return Color(0.18, 0.76, 0.96)
		"police":
			return Color(1.00, 0.84, 0.24)
		_:
			return Color.WHITE

func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(20):
		var a := TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, color)

func _facing_sign() -> float:
	if _facing == Vector2i.ZERO:
		return 1.0
	if absf(float(_facing.x)) >= absf(float(_facing.y)):
		return 1.0 if _facing.x >= 0 else -1.0
	return 1.0

func _on_camera_detection(camera_id: int, id: int, visible: bool, _tile: Vector2i, _detail: Dictionary) -> void:
	if id != agent_id or not visible:
		return
	camera_detections += 1
	# total_camera_detections is accumulated in respawn() to avoid double-counting.
	print("  [%s] spotted by CCTV #%d" % [_role, camera_id])

func _on_status_changed_fx(_id: int, _effect: String, _added: bool) -> void:
	pass

func _on_captured_fx(_id: int) -> void:
	pass

func _on_escaped_fx(_id: int) -> void:
	pass

func _on_fire_fx(_id: int, _tile: Vector2i) -> void:
	pass

func _on_action_chosen_fx(_id: int, _action: String) -> void:
	pass

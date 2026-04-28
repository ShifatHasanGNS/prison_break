extends Node2D
class_name Agent

const TILE_SIZE: int = 48

# Theme colours used in drawing
const C_HIGHLIGHT := Color(0.290, 0.855, 0.502)

# -------------------------------------------------------------------------
# Identity & state
# -------------------------------------------------------------------------

var agent_id : int       = 0
var grid_pos : Vector2i  = Vector2i.ZERO
var health   : float     = 100.0
var stamina  : float     = 100.0
var is_active              : bool      = true
var initial_pos            : Vector2i  = Vector2i.ZERO
var capture_count          : int       = 0
## Ticks remaining before this prisoner can be captured again (respawn protection).
var capture_cooldown_ticks : int       = 0

var stats            : AgentStats = null
var _status_effects  : Array      = []
var _ai_controller   : Variant    = null
var _abilities       : Array      = []

# --- Visual state ---
var _role   : String   = ""
var _facing : Vector2i = Vector2i(1, 0)
var _bob    : float    = 0.0

# --- Pathfinding ---
var _needs_replan: bool = false

# -------------------------------------------------------------------------
# Lifecycle
# -------------------------------------------------------------------------

func _ready() -> void:
	z_index = 2   # renders above dog (z=1) and grid
	# Transient visual effects spawned in response to simulation events
	EventBus.agent_status_changed.connect(_on_status_changed_fx)
	EventBus.agent_captured.connect(_on_captured_fx)
	EventBus.agent_escaped.connect(_on_escaped_fx)
	EventBus.agent_entered_fire.connect(_on_fire_fx)
	EventBus.agent_action_chosen.connect(_on_action_chosen_fx)

func _process(_delta: float) -> void:
	_bob = sin(Time.get_ticks_msec() * 0.003)
	queue_redraw()

# -------------------------------------------------------------------------
# Setup / movement
# -------------------------------------------------------------------------

func setup(id: int, pos: Vector2i, agent_stats: AgentStats) -> void:
	agent_id    = id
	grid_pos    = pos
	initial_pos = pos
	stats       = agent_stats
	health      = stats.max_health
	stamina     = stats.max_stamina
	set_grid_visual_pos()

func set_grid_visual_pos() -> void:
	position = Vector2(
		grid_pos.x * TILE_SIZE + TILE_SIZE / 2.0,
		grid_pos.y * TILE_SIZE + TILE_SIZE / 2.0
	)
	queue_redraw()

func respawn() -> void:
	grid_pos               = initial_pos
	health                 = stats.max_health if stats != null else 100.0
	stamina                = stats.max_stamina if stats != null else 100.0
	capture_cooldown_ticks = 10   # ~2.5 s at 4 Hz — immunity after respawn
	_status_effects.clear()
	if _ai_controller != null and _ai_controller.has_method("clear_history"):
		_ai_controller.clear_history()
	set_grid_visual_pos()
	EventBus.emit_signal("agent_respawned", agent_id)
	print("  [%s] RESPAWNED at %s (total captures: %d)" % [_role, initial_pos, capture_count])

func move_to(pos: Vector2i) -> void:
	var old_pos : Vector2i = grid_pos
	var dir     : Vector2i = pos - old_pos
	if dir != Vector2i.ZERO:
		_facing = dir
	grid_pos = pos
	set_grid_visual_pos()
	EventBus.emit_signal("agent_moved", agent_id, old_pos, pos)

# -------------------------------------------------------------------------
# Status effects
# -------------------------------------------------------------------------

func tick_status_effects() -> void:
	if capture_cooldown_ticks > 0:
		capture_cooldown_ticks -= 1

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
	return speed

func get_speed_bonus() -> int:
	for e in _status_effects:
		if e.effect_name == "speed_boost":
			return e.speed_bonus
	return 0

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

# =========================================================================
# DRAWING  (pixel-art quality — all shapes, no sprites)
# =========================================================================

func _draw() -> void:
	# Escaped prisoners (game already over) don't need to render.
	# Captured-but-respawned prisoners are always active, so this only hides escapees.
	if not is_active:
		return

	var T   := float(TILE_SIZE)
	var bob := _bob * 1.5   # ±1.5 px vertical idle bob

	# Colored glow ring — drawn first so it's behind everything
	var glow_col: Color
	match _role:
		"rusher_red":  glow_col = Color(0.94, 0.27, 0.27, 0.22)
		"sneaky_blue": glow_col = Color(0.10, 0.95, 0.95, 0.20)
		"police":      glow_col = Color(0.98, 0.82, 0.18, 0.18)
		_:             glow_col = Color(1.0, 1.0, 1.0, 0.15)
	draw_circle(Vector2(0.0, bob * 0.3), T * 0.40, glow_col)
	draw_circle(Vector2(0.0, bob * 0.3), T * 0.30,
		Color(glow_col.r, glow_col.g, glow_col.b, glow_col.a * 0.45))

	# Drop shadow (ellipse beneath the agent)
	_draw_ellipse(Vector2(0.0, T * 0.30), Vector2(T * 0.28, T * 0.08), Color(0, 0, 0, 0.35))

	match _role:
		"rusher_red":  _draw_rusher(bob)
		"sneaky_blue": _draw_sneaky(bob)
		"police":      _draw_police(bob)

	_draw_status_indicators(bob)

# -------------------------------------------------------------------------
# Role-specific draw routines
# -------------------------------------------------------------------------

func _draw_rusher(bob: float) -> void:
	var T := float(TILE_SIZE)
	var skin := Color(0.86, 0.66, 0.50)
	var orange := Color(0.92, 0.43, 0.09)
	var orange_dark := Color(0.62, 0.22, 0.04)
	var outline := Color(0.08, 0.06, 0.04)
	var boots := Color(0.12, 0.09, 0.06)
	var ex := T * 0.06 * _facing_sign()

	draw_rect(Rect2(-T*0.20, T*0.08+bob, T*0.16, T*0.25), outline)
	draw_rect(Rect2( T*0.04, T*0.08+bob, T*0.16, T*0.25), outline)
	draw_rect(Rect2(-T*0.17, T*0.10+bob, T*0.11, T*0.19), orange_dark)
	draw_rect(Rect2( T*0.07, T*0.10+bob, T*0.11, T*0.19), orange_dark)
	draw_rect(Rect2(-T*0.22, T*0.29+bob, T*0.19, T*0.08), boots)
	draw_rect(Rect2( T*0.03, T*0.29+bob, T*0.19, T*0.08), boots)

	draw_rect(Rect2(-T*0.26, -T*0.17+bob, T*0.52, T*0.31), outline)
	draw_rect(Rect2(-T*0.22, -T*0.14+bob, T*0.44, T*0.26), orange)
	draw_line(Vector2(0, -T*0.14+bob), Vector2(0, T*0.12+bob), orange_dark, 2)
	draw_rect(Rect2(-T*0.11, -T*0.10+bob, T*0.22, T*0.09), Color(1.0, 0.68, 0.26))
	draw_rect(Rect2(-T*0.07, -T*0.085+bob, T*0.04, T*0.035), orange_dark)
	draw_rect(Rect2(T*0.02, -T*0.085+bob, T*0.05, T*0.035), orange_dark)

	draw_rect(Rect2(-T*0.38, -T*0.13+bob, T*0.14, T*0.23), outline)
	draw_rect(Rect2( T*0.24, -T*0.13+bob, T*0.14, T*0.23), outline)
	draw_rect(Rect2(-T*0.35, -T*0.10+bob, T*0.10, T*0.17), orange)
	draw_rect(Rect2( T*0.25, -T*0.10+bob, T*0.10, T*0.17), orange)
	draw_rect(Rect2(-T*0.36, T*0.04+bob, T*0.11, T*0.08), skin)
	draw_rect(Rect2( T*0.25, T*0.04+bob, T*0.11, T*0.08), skin)

	draw_rect(Rect2(-T*0.18, -T*0.44+bob, T*0.36, T*0.28), outline)
	draw_rect(Rect2(-T*0.15, -T*0.40+bob, T*0.30, T*0.23), skin)
	draw_rect(Rect2(-T*0.16, -T*0.45+bob, T*0.32, T*0.11), Color(0.17, 0.10, 0.06))
	draw_rect(Rect2(-T*0.12, -T*0.27+bob, T*0.24, T*0.04), Color(0.52, 0.26, 0.14))
	draw_rect(Rect2(ex - T*0.08, -T*0.32+bob, T*0.05, T*0.05), Color.WHITE)
	draw_rect(Rect2(ex + T*0.04, -T*0.32+bob, T*0.05, T*0.05), Color.WHITE)
	draw_rect(Rect2(ex - T*0.065 + T*0.01*_facing.x, -T*0.305+bob, T*0.025, T*0.025), outline)
	draw_rect(Rect2(ex + T*0.055 + T*0.01*_facing.x, -T*0.305+bob, T*0.025, T*0.025), outline)

func _draw_rusher_old(bob: float) -> void:
	var T := float(TILE_SIZE)
	# Legs
	draw_rect(Rect2(-T*0.18, T*0.10+bob, T*0.14, T*0.22), Color(0.75, 0.35, 0.10))
	draw_rect(Rect2( T*0.04, T*0.10+bob, T*0.14, T*0.22), Color(0.75, 0.35, 0.10))
	# Boots
	draw_rect(Rect2(-T*0.20, T*0.28+bob, T*0.16, T*0.07), Color(0.22, 0.15, 0.08))
	draw_rect(Rect2( T*0.04, T*0.28+bob, T*0.16, T*0.07), Color(0.22, 0.15, 0.08))
	# Torso — wide orange jumpsuit
	draw_rect(Rect2(-T*0.22, -T*0.14+bob, T*0.44, T*0.26), Color(0.87, 0.42, 0.10))
	# Prison number patch
	draw_rect(Rect2(-T*0.08, -T*0.10+bob, T*0.16, T*0.09), Color(0.95, 0.60, 0.20, 0.60))
	# Arms
	draw_rect(Rect2(-T*0.36, -T*0.13+bob, T*0.15, T*0.20), Color(0.87, 0.42, 0.10))
	draw_rect(Rect2( T*0.21, -T*0.13+bob, T*0.15, T*0.20), Color(0.87, 0.42, 0.10))
	# Hands
	draw_circle(Vector2(-T*0.30, bob),        T*0.07, Color(0.85, 0.65, 0.50))
	draw_circle(Vector2( T*0.30, bob),        T*0.07, Color(0.85, 0.65, 0.50))
	# Head
	draw_circle(Vector2(0, -T*0.28+bob),      T*0.17, Color(0.85, 0.65, 0.50))
	# Hair (dark skullcap)
	draw_rect(Rect2(-T*0.14, -T*0.44+bob, T*0.28, T*0.13), Color(0.18, 0.12, 0.08))
	# Eyes — offset based on facing direction
	var ex := T * 0.06 * _facing_sign()
	draw_circle(Vector2(ex - T*0.04, -T*0.28+bob), T*0.04, Color.WHITE)
	draw_circle(Vector2(ex + T*0.04, -T*0.28+bob), T*0.04, Color.WHITE)
	draw_circle(Vector2(ex - T*0.04 + T*0.01*_facing.x, -T*0.28+bob), T*0.02, Color(0.10, 0.10, 0.10))
	draw_circle(Vector2(ex + T*0.04 + T*0.01*_facing.x, -T*0.28+bob), T*0.02, Color(0.10, 0.10, 0.10))

func _draw_sneaky(bob: float) -> void:
	var T := float(TILE_SIZE)
	var cr := 1.0 if has_status("hidden") else 0.0
	var cy := T * 0.08 * cr
	var outline := Color(0.02, 0.07, 0.10)
	var suit := Color(0.02, 0.28, 0.34)
	var suit_hi := Color(0.07, 0.62, 0.70)
	var cyan := Color(0.18, 1.00, 0.92)
	var scarf := Color(0.95, 0.92, 0.30)
	var skin := Color(0.70, 0.55, 0.43)

	var leg_h := T * 0.20 * (1.0 - cr * 0.45)
	draw_rect(Rect2(-T*0.18, T*0.08+bob+cy, T*0.13, leg_h + T*0.06), outline)
	draw_rect(Rect2( T*0.05, T*0.08+bob+cy, T*0.13, leg_h + T*0.06), outline)
	draw_rect(Rect2(-T*0.15, T*0.09+bob+cy, T*0.08, leg_h), suit)
	draw_rect(Rect2( T*0.07, T*0.09+bob+cy, T*0.08, leg_h), suit)
	draw_rect(Rect2(-T*0.18, T*0.25+bob+cy, T*0.15, T*0.07), outline)
	draw_rect(Rect2( T*0.03, T*0.25+bob+cy, T*0.15, T*0.07), outline)

	draw_colored_polygon(PackedVector2Array([
		Vector2(-T*0.22, -T*0.17+bob+cy),
		Vector2( T*0.22, -T*0.17+bob+cy),
		Vector2( T*0.18,  T*0.12+bob+cy),
		Vector2(-T*0.18,  T*0.12+bob+cy),
	]), outline)
	draw_rect(Rect2(-T*0.18, -T*0.14+bob+cy, T*0.36, T*0.24), suit)
	draw_rect(Rect2(-T*0.17, -T*0.12+bob+cy, T*0.08, T*0.20), suit_hi)
	draw_rect(Rect2(T*0.09, -T*0.10+bob+cy, T*0.05, T*0.18), suit_hi)
	draw_rect(Rect2(-T*0.03, -T*0.14+bob+cy, T*0.06, T*0.24), Color(0.00, 0.12, 0.16))
	draw_rect(Rect2(-T*0.17, -T*0.01+bob+cy, T*0.34, T*0.05), scarf)

	draw_rect(Rect2(-T*0.32, -T*0.13+bob+cy, T*0.12, T*0.20), outline)
	draw_rect(Rect2( T*0.20, -T*0.13+bob+cy, T*0.12, T*0.20), outline)
	draw_rect(Rect2(-T*0.29, -T*0.10+bob+cy, T*0.08, T*0.15), suit)
	draw_rect(Rect2( T*0.21, -T*0.10+bob+cy, T*0.08, T*0.15), suit)
	draw_rect(Rect2(-T*0.31, T*0.04+bob+cy, T*0.09, T*0.06), skin)
	draw_rect(Rect2( T*0.22, T*0.04+bob+cy, T*0.09, T*0.06), skin)

	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -T*0.49+bob+cy),
		Vector2(T*0.22, -T*0.38+bob+cy),
		Vector2(T*0.18, -T*0.18+bob+cy),
		Vector2(0, -T*0.11+bob+cy),
		Vector2(-T*0.18, -T*0.18+bob+cy),
		Vector2(-T*0.22, -T*0.38+bob+cy),
	]), outline)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -T*0.45+bob+cy),
		Vector2(T*0.16, -T*0.35+bob+cy),
		Vector2(T*0.13, -T*0.21+bob+cy),
		Vector2(0, -T*0.16+bob+cy),
		Vector2(-T*0.13, -T*0.21+bob+cy),
		Vector2(-T*0.16, -T*0.35+bob+cy),
	]), suit)
	draw_rect(Rect2(-T*0.15, -T*0.34+bob+cy, T*0.30, T*0.08), cyan)
	draw_rect(Rect2(-T*0.03 + T*0.04*_facing_sign(), -T*0.325+bob+cy, T*0.05, T*0.035), outline)
	draw_line(Vector2(-T*0.18, -T*0.23+bob+cy), Vector2(T*0.18, -T*0.23+bob+cy), cyan, 1)

	if cr > 0.5:
		draw_arc(Vector2(0, bob + cy), T*0.40, 0.0, TAU, 32,
			Color(0.37, 0.78, 1.0, 0.45 * cr), 2)
		draw_rect(Rect2(-T*0.27, -T*0.20+bob+cy, T*0.54, T*0.45), Color(0.37, 0.78, 1.0, 0.07))

func _draw_sneaky_old(bob: float) -> void:
	var T  := float(TILE_SIZE)
	var cr := 1.0 if has_status("hidden") else 0.0   # crouch factor
	var cy := T * 0.08 * cr                           # vertical crouch offset
	# Legs (shrink when crouched)
	var leg_h := T * 0.20 * (1.0 - cr * 0.40)
	draw_rect(Rect2(-T*0.16, T*0.08+bob+cy, T*0.12, leg_h), Color(0.18, 0.28, 0.55))
	draw_rect(Rect2( T*0.04, T*0.08+bob+cy, T*0.12, leg_h), Color(0.18, 0.28, 0.55))
	# Torso (slim, dark blue — slightly brighter for visibility)
	draw_rect(Rect2(-T*0.18, -T*0.16+bob+cy, T*0.36, T*0.26), Color(0.20, 0.32, 0.62))
	# Arms
	draw_rect(Rect2(-T*0.30, -T*0.14+bob+cy, T*0.13, T*0.18), Color(0.20, 0.32, 0.62))
	draw_rect(Rect2( T*0.18, -T*0.14+bob+cy, T*0.13, T*0.18), Color(0.20, 0.32, 0.62))
	# Hood / balaclava — subtle bright outline for contrast against dark floor
	draw_circle(Vector2(0, -T*0.30+bob+cy), T*0.16 + 1.5, Color(0.30, 0.50, 0.80, 0.50))
	draw_circle(Vector2(0, -T*0.30+bob+cy), T*0.16, Color(0.12, 0.18, 0.36))
	# Eye slit (bright cyan-blue, wider for readability)
	draw_rect(Rect2(-T*0.11, -T*0.33+bob+cy, T*0.22, T*0.055), Color(0.45, 0.75, 1.00, 1.0))
	# Stealth shimmer ring when hidden
	if cr > 0.5:
		draw_arc(Vector2(0, bob + cy), T*0.38, 0.0, TAU, 32,
			Color(0.37, 0.65, 0.98, 0.35 * cr), 2)

func _draw_police(bob: float) -> void:
	var T := float(TILE_SIZE)
	var outline := Color(0.04, 0.05, 0.10)
	var navy := Color(0.02, 0.07, 0.20)
	var blue := Color(0.08, 0.20, 0.52)
	var blue_hi := Color(0.42, 0.63, 1.00)
	var cap_white := Color(0.88, 0.92, 0.96)
	var skin := Color(0.85, 0.70, 0.55)
	var gold := Color(0.96, 0.82, 0.18)

	draw_rect(Rect2(-T*0.19, T*0.08+bob, T*0.14, T*0.25), outline)
	draw_rect(Rect2( T*0.05, T*0.08+bob, T*0.14, T*0.25), outline)
	draw_rect(Rect2(-T*0.16, T*0.10+bob, T*0.09, T*0.19), navy)
	draw_rect(Rect2( T*0.07, T*0.10+bob, T*0.09, T*0.19), navy)
	draw_rect(Rect2(-T*0.21, T*0.29+bob, T*0.18, T*0.08), outline)
	draw_rect(Rect2( T*0.03, T*0.29+bob, T*0.18, T*0.08), outline)

	draw_rect(Rect2(-T*0.25, -T*0.18+bob, T*0.50, T*0.32), outline)
	draw_rect(Rect2(-T*0.21, -T*0.15+bob, T*0.42, T*0.26), blue)
	draw_rect(Rect2(-T*0.03, -T*0.15+bob, T*0.06, T*0.26), navy)
	draw_rect(Rect2(-T*0.21, T*0.03+bob, T*0.42, T*0.07), navy)
	draw_rect(Rect2(-T*0.10, -T*0.13+bob, T*0.20, T*0.12), gold)
	draw_rect(Rect2(-T*0.06, -T*0.10+bob, T*0.12, T*0.06), Color(0.98, 0.93, 0.45))
	draw_rect(Rect2(-T*0.17, -T*0.13+bob, T*0.06, T*0.09), blue_hi)
	draw_rect(Rect2(T*0.13, -T*0.13+bob, T*0.05, T*0.09), Color(0.95, 0.95, 0.95))

	draw_rect(Rect2(-T*0.36, -T*0.14+bob, T*0.14, T*0.22), outline)
	draw_rect(Rect2( T*0.22, -T*0.14+bob, T*0.14, T*0.22), outline)
	draw_rect(Rect2(-T*0.33, -T*0.11+bob, T*0.09, T*0.16), blue)
	draw_rect(Rect2( T*0.24, -T*0.11+bob, T*0.09, T*0.16), blue)
	draw_rect(Rect2(T*0.33, -T*0.08+bob, T*0.05, T*0.28), outline)
	draw_rect(Rect2(T*0.345, -T*0.07+bob, T*0.025, T*0.25), Color(0.05, 0.05, 0.06))
	draw_rect(Rect2(-T*0.34, T*0.03+bob, T*0.10, T*0.08), skin)
	draw_rect(Rect2( T*0.24, T*0.03+bob, T*0.10, T*0.08), skin)

	draw_rect(Rect2(-T*0.18, -T*0.43+bob, T*0.36, T*0.27), outline)
	draw_rect(Rect2(-T*0.15, -T*0.39+bob, T*0.30, T*0.21), skin)
	draw_rect(Rect2(-T*0.22, -T*0.49+bob, T*0.44, T*0.15), cap_white)
	draw_rect(Rect2(-T*0.19, -T*0.47+bob, T*0.38, T*0.07), navy)
	draw_rect(Rect2(-T*0.30, -T*0.37+bob, T*0.60, T*0.08), outline)
	draw_rect(Rect2(-T*0.23, -T*0.36+bob, T*0.46, T*0.04), cap_white)
	draw_rect(Rect2(-T*0.17, -T*0.46+bob, T*0.34, T*0.05), blue_hi)
	draw_rect(Rect2(-T*0.04, -T*0.47+bob, T*0.08, T*0.05), gold)
	draw_rect(Rect2(-T*0.10, -T*0.30+bob, T*0.06, T*0.05), Color.WHITE)
	draw_rect(Rect2( T*0.05, -T*0.30+bob, T*0.06, T*0.05), Color.WHITE)
	draw_rect(Rect2(-T*0.08 + T*0.01*_facing.x, -T*0.285+bob, T*0.025, T*0.025), outline)
	draw_rect(Rect2( T*0.07 + T*0.01*_facing.x, -T*0.285+bob, T*0.025, T*0.025), outline)
	draw_rect(Rect2(-T*0.07, -T*0.22+bob, T*0.14, T*0.035), Color(0.48, 0.25, 0.17))

func _draw_police_old(bob: float) -> void:
	var T := float(TILE_SIZE)
	# Legs (dark navy trousers)
	draw_rect(Rect2(-T*0.17, T*0.09+bob, T*0.13, T*0.23), Color(0.10, 0.16, 0.38))
	draw_rect(Rect2( T*0.04, T*0.09+bob, T*0.13, T*0.23), Color(0.10, 0.16, 0.38))
	# Boots
	draw_rect(Rect2(-T*0.19, T*0.28+bob, T*0.15, T*0.07), Color(0.08, 0.08, 0.12))
	draw_rect(Rect2( T*0.04, T*0.28+bob, T*0.15, T*0.07), Color(0.08, 0.08, 0.12))
	# Torso (police blue shirt)
	draw_rect(Rect2(-T*0.21, -T*0.15+bob, T*0.42, T*0.26), Color(0.23, 0.51, 0.96))
	# Badge (gold rect + dark outline)
	draw_rect(Rect2(-T*0.06, -T*0.12+bob, T*0.12, T*0.08), Color(0.95, 0.80, 0.15))
	draw_rect(Rect2(-T*0.06, -T*0.12+bob, T*0.12, T*0.08), Color(0, 0, 0, 0.30), false)
	# Arms
	draw_rect(Rect2(-T*0.34, -T*0.14+bob, T*0.14, T*0.20), Color(0.23, 0.51, 0.96))
	draw_rect(Rect2( T*0.20, -T*0.14+bob, T*0.14, T*0.20), Color(0.23, 0.51, 0.96))
	# Hands
	draw_circle(Vector2(-T*0.28, T*0.01+bob), T*0.07, Color(0.85, 0.70, 0.55))
	draw_circle(Vector2( T*0.28, T*0.01+bob), T*0.07, Color(0.85, 0.70, 0.55))
	# Head
	draw_circle(Vector2(0, -T*0.29+bob), T*0.16, Color(0.85, 0.70, 0.55))
	# Peaked cap — dome + brim
	draw_rect(Rect2(-T*0.20, -T*0.44+bob, T*0.40, T*0.12), Color(0.10, 0.16, 0.38))
	draw_rect(Rect2(-T*0.24, -T*0.36+bob, T*0.48, T*0.05), Color(0.08, 0.12, 0.28))
	# Eyes (small white dots)
	draw_circle(Vector2(-T*0.05, -T*0.29+bob), T*0.03, Color.WHITE)
	draw_circle(Vector2( T*0.05, -T*0.29+bob), T*0.03, Color.WHITE)

# -------------------------------------------------------------------------
# Status-effect indicators (drawn above head)
# -------------------------------------------------------------------------

func _draw_status_indicators(bob: float) -> void:
	var T    := float(TILE_SIZE)
	var htop := -T * 0.52 + bob   # just above the tallest head point
	var font := ThemeDB.fallback_font

	# Burning — orange flame triangle above head
	if has_status("burning"):
		var pts := PackedVector2Array([
			Vector2(0,        htop - T*0.12),
			Vector2(-T*0.07,  htop),
			Vector2( T*0.07,  htop),
		])
		draw_colored_polygon(pts, Color(1.00, 0.45, 0.05))
		var pts2 := PackedVector2Array([
			Vector2(0,        htop - T*0.08),
			Vector2(-T*0.03,  htop - T*0.01),
			Vector2( T*0.03,  htop - T*0.01),
		])
		draw_colored_polygon(pts2, Color(1.00, 0.82, 0.15))

	# Stunned — 3 yellow circles in an arc
	if has_status("stunned"):
		for i in range(3):
			var a := -PI * 0.30 + float(i) * PI * 0.30
			draw_circle(
				Vector2(cos(a) * T*0.16, htop + sin(a) * T*0.04 + T*0.02),
				T * 0.04, Color(1.00, 0.90, 0.10)
			)

	# Hidden — dashed blue ring around agent
	if has_status("hidden"):
		var ring_r := T * 0.42
		var segs   := 12
		for i in range(segs):
			if i % 2 == 0:
				draw_arc(Vector2(0, bob), ring_r,
					float(i) / segs * TAU,
					float(i + 1) / segs * TAU,
					4, Color(0.37, 0.65, 0.98, 0.80), 2)

	# Detected — flashing orange ! (toggles at ~2 Hz)
	if has_status("detected"):
		if fmod(Time.get_ticks_msec() * 0.001, 0.50) < 0.25:
			if font != null:
				draw_string(font, Vector2(-T*0.06, htop + T*0.02), "!",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.00, 0.50, 0.10))

	# SpeedBoost — green motion lines behind agent in facing direction
	if has_status("speed_boost"):
		var dir := Vector2(float(-_facing.x), float(-_facing.y))
		if dir == Vector2.ZERO:
			dir = Vector2(-1.0, 0.0)
		var perp := Vector2(-dir.y, dir.x)
		for i in range(3):
			var base   := Vector2(0, bob) + dir * T * (0.20 + float(i) * 0.10)
			var spread := 1.0 - float(i) * 0.25
			draw_line(
				base - perp * T * 0.08 * spread,
				base + perp * T * 0.08 * spread,
				Color(0.29, 0.85, 0.50, 0.70 - float(i) * 0.20), 2
			)

	# Role label — always drawn above the agent so they're identifiable
	if font != null:
		var label: String
		var label_col: Color
		match _role:
			"rusher_red":
				label = "R"
				label_col = Color(1.0, 0.55, 0.15)
			"sneaky_blue":
				label = "B"
				label_col = Color(0.18, 1.0, 0.92)
			"police":
				label = "P"
				label_col = Color(1.0, 0.86, 0.24)
			_:
				label = "?"
				label_col = Color.WHITE
		# Small dark backdrop for readability
		draw_rect(Rect2(-T*0.12, htop - T*0.22, T*0.24, T*0.18),
			Color(0.05, 0.05, 0.10, 0.70))
		draw_string(font, Vector2(-T*0.08, htop - T*0.06), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, label_col)

# -------------------------------------------------------------------------
# Drawing helpers
# -------------------------------------------------------------------------

func _draw_ellipse(center: Vector2, radii: Vector2, color: Color, segments: int = 16) -> void:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := float(i) / float(segments) * TAU
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, color)

func _facing_sign() -> float:
	if _facing.x > 0: return  1.0
	if _facing.x < 0: return -1.0
	return 0.0

# =========================================================================
# TRANSIENT EFFECTS (EventBus callbacks → spawn at scene root)
# =========================================================================

func _on_status_changed_fx(id: int, effect: String, added: bool) -> void:
	if id != agent_id or not added:
		return
	match effect:
		"detected": _spawn_effect(TransientEffect.Type.ALERT)
		"burning":  _spawn_effect(TransientEffect.Type.FLAME)
		"stunned":  _spawn_effect(TransientEffect.Type.SPARKLE)

func _on_captured_fx(id: int) -> void:
	if id == agent_id:
		_spawn_effect(TransientEffect.Type.CAPTURE)

func _on_escaped_fx(id: int) -> void:
	if id == agent_id:
		_spawn_effect(TransientEffect.Type.ESCAPE)

func _on_fire_fx(id: int, _tile: Vector2i) -> void:
	if id == agent_id:
		_spawn_effect(TransientEffect.Type.FLAME)

func _on_action_chosen_fx(id: int, action: String) -> void:
	if id == agent_id and action == "brawl":
		_spawn_effect(TransientEffect.Type.SMOKE)

func _spawn_effect(type: int) -> void:
	if not is_inside_tree():
		return
	var effect := TransientEffect.new()
	get_tree().current_scene.add_child(effect)
	effect.activate(type, global_position)

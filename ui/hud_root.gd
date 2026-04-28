extends Node2D
class_name HudRoot

# ── Layout ────────────────────────────────────────────────────────────────────
# Panels narrowed so the gameplay map gets more horizontal space while the full
# HUD still fits within 16:9 without clipping the bottom rows.
const LEFT_PANEL_W:  float = 300.0
const RIGHT_PANEL_W: float = 300.0
const HEADER_H:      float = 68.0
const MAP_TOOLBAR_H: float = 38.0
const PANEL_PAD:     float = 10.0
const SAFE_PAD:      float = 12.0
const BOTTOM_SAFE:   float = 18.0
const TILE_SIZE:     float = 48.0
const PRISONER_DECISION_INTERVAL_SEC: float = 0.25
const POLICE_DECISION_INTERVAL_SEC: float = 0.25

# ── Palette ───────────────────────────────────────────────────────────────────
const C_BG_DEEP     := Color(0.02, 0.03, 0.06, 0.93)
const C_BG_PANEL    := Color(0.04, 0.07, 0.12, 0.97)
const C_PANEL_INNER := Color(0.05, 0.09, 0.15, 0.99)
const C_BORDER      := Color(0.10, 0.22, 0.36, 1.0)
const C_BORDER_GLOW := Color(0.16, 0.42, 0.65, 0.55)
const C_CYAN        := Color(0.00, 0.90, 1.00)
const C_ORANGE      := Color(1.00, 0.43, 0.00)
const C_RED         := Color(1.00, 0.12, 0.28)
const C_GREEN       := Color(0.00, 0.90, 0.45)
const C_YELLOW      := Color(1.00, 0.84, 0.25)
const C_TEXT        := Color(0.82, 0.91, 1.00)
const C_DIM         := Color(0.32, 0.50, 0.65)
const C_SOFT        := Color(0.55, 0.75, 0.90, 0.30)

# ── State ─────────────────────────────────────────────────────────────────────
var _panels:          Array = []
var _agents:          Array = []
var _exit_rotator:    ExitRotator      = null
var _sim:             SimulationLoop   = null
var _camera_system:   CCTVCameraSystem = null
var _overlay_manager: OverlayManager   = null

var _active_exit:     Vector2i = Vector2i(-1, -1)
var _countdown:       float    = 0.0
var _tick:            int      = 0
var _camera_states:   Array    = []
var _cycle_summaries: Array    = []
var _activity_log:    Array    = []
var _ui_pulse:        float    = 0.0
var _display_threat:  float    = 0.18
var _alert_flash:     float    = 0.0
var _system_levels:   Dictionary = {
	"detection": 0.0,
	"comm":      0.92,
	"locks":     0.85,
	"response":  0.35,
}
var _toolbar_buttons: Array[Dictionary] = []
var _toolbar_hover_idx: int = -1
var _dog_lock_agent_id: int = -1
var _dog_lock_ticks: int = 0
var _captured_while_latched_once: Dictionary = {}
var _last_ai_activity_tick: Dictionary = {}

# ── Setup ─────────────────────────────────────────────────────────────────────
func setup(
		agents: Array,
		exit_rotator: ExitRotator,
		sim: SimulationLoop = null,
		camera_system: CCTVCameraSystem = null,
		overlay_manager: OverlayManager = null) -> void:
	_agents        = agents
	_exit_rotator  = exit_rotator
	_sim           = sim
	_camera_system = camera_system
	_overlay_manager = overlay_manager

	for agent in agents:
		var p: AgentPanel = AgentPanel.new()
		p.setup(agent)
		p.update_from_agent(agent)
		_panels.append(p)

	if exit_rotator != null:
		_active_exit = exit_rotator.get_active_exit()
		_countdown   = exit_rotator.get_time_remaining()
	if _camera_system != null:
		_camera_states = _camera_system.get_camera_states()

	_push_activity("Surveillance command center online",            "info")
	_push_activity("Viewport locked to widescreen tactical layout", "info")

	EventBus.agent_action_chosen.connect(_on_action_chosen)
	EventBus.tick_ended.connect(_on_tick_ended)
	EventBus.exit_activated.connect(_on_exit_activated)
	EventBus.minimax_decision.connect(_on_minimax_decision)
	EventBus.mcts_decision.connect(_on_mcts_decision)
	EventBus.fuzzy_decision.connect(_on_fuzzy_decision)
	EventBus.camera_detection.connect(_on_camera_detection)
	EventBus.camera_sweep_updated.connect(_on_camera_sweep_updated)
	EventBus.cycle_summary_generated.connect(_on_cycle_summary_generated)
	EventBus.score_event.connect(_on_score_event)
	EventBus.agent_captured.connect(_on_agent_captured)
	EventBus.agent_escaped.connect(
		func(id): _push_activity("%s escaped"  % _role_name_from_id(id), "alert"))
	EventBus.agent_eliminated.connect(
		func(id): _push_activity("%s eliminated" % _role_name_from_id(id), "warning"))
	EventBus.dog_engaged_prisoner.connect(_on_dog_engaged_prisoner)
	EventBus.dog_released_prisoner.connect(_on_dog_released_prisoner)
	EventBus.police_captured_while_dog_latched.connect(_on_police_captured_while_dog_latched)

# ── Process ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_countdown   = maxf(0.0, _countdown - delta)
	_ui_pulse   += delta
	_alert_flash = maxf(0.0, _alert_flash - delta * 2.5)

	var threat_target: float = _threat_level()
	_display_threat = lerpf(_display_threat, threat_target, minf(1.0, delta * 3.2))

	_system_levels["detection"] = lerpf(
		float(_system_levels.get("detection", 0.0)),
		clampf(float(_camera_states.size()) / 3.0, 0.0, 1.0),
		minf(1.0, delta * 4.0))
	_system_levels["comm"] = lerpf(
		float(_system_levels.get("comm", 0.92)),
		0.92,
		minf(1.0, delta * 2.2))
	_system_levels["locks"] = lerpf(
		float(_system_levels.get("locks", 0.85)),
		0.55 if _countdown > 0.0 else 0.85,
		minf(1.0, delta * 3.0))
	_system_levels["response"] = lerpf(
		float(_system_levels.get("response", 0.35)),
		clampf(0.35 + float(_hot_camera_count()) * 0.18, 0.25, 0.98),
		minf(1.0, delta * 3.0))

	for p in _panels:
		(p as AgentPanel).lerp_displays(delta)
	if _dog_lock_ticks > 0:
		_dog_lock_ticks -= 1
		if _dog_lock_ticks <= 0:
			_dog_lock_agent_id = -1
	_toolbar_hover_idx = _toolbar_index_at(get_viewport().get_mouse_position())
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_toolbar_hover_idx = _toolbar_index_at(event.position)
		return
	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var idx: int = _toolbar_index_at(event.position)
	if idx < 0 or idx >= _toolbar_buttons.size():
		return
	var action_name: String = str(_toolbar_buttons[idx].get("action", ""))
	_handle_toolbar_action(action_name)

# ── Event handlers (agent logic untouched) ────────────────────────────────────
func _on_action_chosen(id: int, action: String) -> void:
	for p in _panels:
		var ap: AgentPanel = p as AgentPanel
		if ap.agent_id == id:
			ap.action_text = action
			ap.add_log(action)
			return

func _on_tick_ended(n: int) -> void:
	_tick = n
	for i in range(_panels.size()):
		if i < _agents.size():
			(_panels[i] as AgentPanel).update_from_agent(_agents[i])
	if _sim != null:
		_cycle_summaries = _sim.get_cycle_summaries()
	if _camera_system != null:
		_camera_states = _camera_system.get_camera_states()

func _on_exit_activated(tile: Vector2i) -> void:
	_active_exit = tile
	if _exit_rotator != null:
		_countdown = _exit_rotator.get_time_remaining()
	_push_activity("Active exit moved to %s" % _tile_text(tile), "warning")
	_alert_flash = 1.0

func _on_minimax_decision(id: int, candidates: Array, chosen: Dictionary) -> void:
	for p in _panels:
		var ap: AgentPanel = p as AgentPanel
		if ap.agent_id != id:
			continue
		ap.candidates.clear()
		ap.decision_kind = "Minimax"
		var max_abs: float = 0.1
		for c in candidates:
			max_abs = maxf(max_abs, absf(float(c.get("score", 0.0))))
		var chosen_pos: Vector2i = chosen.get("pos", Vector2i(-1, -1))
		for i in range(mini(candidates.size(), 3)):
			var c = candidates[i]
			var pos: Vector2i = c.get("pos", Vector2i(-1, -1))
			var sc: float = float(c.get("score", 0.0))
			ap.candidates.append({
				"pos":    pos,
				"score":  sc,
				"norm":   (sc + max_abs) / (2.0 * max_abs),
				"chosen": pos == chosen_pos,
				"type":   "mm"
			})
		ap.next_pos = chosen_pos
		var best_score: float = float(chosen.get("score", 0.0))
		var reason: String = str(chosen.get("reason", "best score"))
		ap.add_log("pick %s S%.2f %s" % [_tile_text(chosen_pos), best_score, reason])
		_push_ai_activity_once(id, "RED/MINIMAX %s S%.2f · %s" % [_tile_text(chosen_pos), best_score, reason])
		return

func _on_mcts_decision(id: int, root_visits: int, candidates: Array, chosen: Dictionary) -> void:
	for p in _panels:
		var ap: AgentPanel = p as AgentPanel
		if ap.agent_id != id:
			continue
		ap.candidates.clear()
		ap.decision_kind = "Search"
		var max_v: float = 1.0
		for c in candidates:
			max_v = maxf(max_v, float(c.get("visits", 0)))
		var chosen_pos: Vector2i = chosen.get("pos", Vector2i(-1, -1))
		for i in range(mini(candidates.size(), 3)):
			var c = candidates[i]
			var pos: Vector2i = c.get("pos", Vector2i(-1, -1))
			var v: int = int(c.get("visits", 0))
			ap.candidates.append({
				"pos":    pos,
				"visits": v,
				"norm":   float(v) / max_v,
				"chosen": pos == chosen_pos,
				"type":   "mcts"
			})
		ap.next_pos = chosen_pos
		var selected_visits: int = int(chosen.get("visits", 0))
		var reason: String = str(chosen.get("reason", "safest rollout"))
		ap.add_log("%d sims V%d → %s %s" % [root_visits, selected_visits, _tile_text(chosen_pos), reason])
		_push_ai_activity_once(id, "BLUE/MCTS %s V%d/%d · %s" % [_tile_text(chosen_pos), selected_visits, root_visits, reason])
		return

func _on_fuzzy_decision(
		id: int,
		inputs: Dictionary,
		rules: Array,
		output: String,
		chosen_pos: Vector2i = Vector2i(-1, -1)) -> void:
	for p in _panels:
		var ap: AgentPanel = p as AgentPanel
		if ap.agent_id != id:
			continue
		ap.candidates.clear()
		ap.decision_kind = "Fuzzy"
		for i in range(mini(rules.size(), 3)):
			var r = rules[i]
			var rn: String = str(r.get("rule", "?"))
			var rs: float  = float(r.get("strength", 0.0))
			ap.candidates.append({
				"rule":   rn,
				"score":  rs,
				"norm":   rs,
				"chosen": rn == output,
				"type":   "fuzzy"
			})
		ap.next_pos = chosen_pos
		var target_id: int = int(inputs.get("target_id", -1))
		var target_name: String = _role_name_from_id(target_id)
		var reason: String = str(inputs.get("target_reason", "fuzzy blend"))
		var red_threat: float = float(inputs.get("red_threat", 0.0))
		var blue_threat: float = float(inputs.get("blue_threat", 0.0))
		var threat_str: String = "R %.4f · B %.4f" % [red_threat, blue_threat]
		ap.add_log("%s → %s (%s | %s)" % [output, target_name, reason, threat_str])
		_push_ai_activity_once(id, "POLICE/FUZZY %s %s · %s · %s" % [output.to_upper(), target_name, reason, threat_str])
		return

func _push_ai_activity_once(agent_id: int, text: String) -> void:
	var last_tick: int = int(_last_ai_activity_tick.get(agent_id, -99999))
	if _tick - last_tick < 2:
		return
	_last_ai_activity_tick[agent_id] = _tick
	_push_activity(text, "info")

func _on_camera_detection(
		camera_id: int,
		agent_id: int,
		visible: bool,
		tile: Vector2i,
		_detail: Dictionary) -> void:
	if visible:
		_push_activity(
			"CAM %d locked %s @ %s" % [camera_id + 1, _role_name_from_id(agent_id), _tile_text(tile)],
			"alert")
		_alert_flash = 0.6
	else:
		_push_activity("CAM %d lost %s" % [camera_id + 1, _role_name_from_id(agent_id)], "info")

func _on_camera_sweep_updated(states: Array) -> void:
	_camera_states = states

func _on_agent_captured(agent_id: int) -> void:
	var latched: bool = bool(_captured_while_latched_once.get(agent_id, false))
	if latched:
		_captured_while_latched_once.erase(agent_id)
		_push_activity("POLICE captured %s while dog-latched" % _role_name_from_id(agent_id), "alert")
		return
	_push_activity("%s captured" % _role_name_from_id(agent_id), "alert")

func _on_police_captured_while_dog_latched(prisoner_id: int) -> void:
	_captured_while_latched_once[prisoner_id] = true

func _on_dog_engaged_prisoner(agent_id: int, duration_ticks: int) -> void:
	_dog_lock_agent_id = agent_id
	_dog_lock_ticks = maxi(0, duration_ticks)
	_push_activity("DOG latched %s for %0.1fs" % [_role_name_from_id(agent_id), float(duration_ticks) * 0.25], "alert")
	_alert_flash = 0.8

func _on_dog_released_prisoner(agent_id: int) -> void:
	if _dog_lock_agent_id == agent_id:
		_dog_lock_agent_id = -1
		_dog_lock_ticks = 0
	_push_activity("DOG released %s" % _role_name_from_id(agent_id), "info")

func _on_cycle_summary_generated(summary: Dictionary) -> void:
	_cycle_summaries.append(summary)
	if _cycle_summaries.size() > 8:
		_cycle_summaries.pop_front()
	_push_activity("Cycle %d summary recorded" % int(summary.get("cycle_index", 0)), "info")

func _on_score_event(agent_id: int, delta: float, reason: String, _team: String) -> void:
	var sign: String = "+" if delta >= 0.0 else ""
	var kind: String = "info"
	if delta < 0.0:
		kind = "warning"
	if reason in ["first_escape", "second_escape", "full_containment_bonus"]:
		kind = "alert"
	_push_activity("%s %s%.1f (%s)" % [_role_name_from_id(agent_id), sign, delta, reason], kind)

func _push_activity(text: String, kind: String = "info") -> void:
	_activity_log.push_front({
		"tick": _tick,
		"text": text,
		"kind": kind,
		"born": _ui_pulse,
	})
	if _activity_log.size() > 14:
		_activity_log.resize(14)

# ═══════════════════════════════════════════════════════════════════════════════
# DRAW PIPELINE
# ═══════════════════════════════════════════════════════════════════════════════
func _draw() -> void:
	var vp:   Rect2 = get_viewport_rect()
	var font: Font  = ThemeDB.fallback_font
	_draw_screen_chrome(vp)
	_draw_header_bar(vp, font)
	_draw_map_toolbar(vp, font)
	_draw_left_column(vp, font)
	_draw_right_column(vp, font)

func _layout_metrics(vp: Rect2) -> Dictionary:
	var header_h: float = clampf(vp.size.y * 0.085, 56.0, HEADER_H)
	var toolbar_h: float = 34.0 if vp.size.y < 900.0 else MAP_TOOLBAR_H
	var side_w: float = clampf(vp.size.x * 0.20, 232.0, 320.0)
	var usable_w: float = vp.size.x - SAFE_PAD * 2.0
	var center_min_w: float = 480.0
	if usable_w - side_w * 2.0 < center_min_w:
		side_w = maxf(214.0, (usable_w - center_min_w) * 0.5)
	var left_x: float = SAFE_PAD
	var right_x: float = vp.size.x - SAFE_PAD - side_w
	var center_x: float = left_x + side_w
	var center_w: float = maxf(320.0, right_x - center_x)
	var body_top: float = header_h + PANEL_PAD
	var body_bottom: float = vp.size.y - BOTTOM_SAFE
	return {
		"header_h": header_h,
		"toolbar_h": toolbar_h,
		"side_w": side_w,
		"left_x": left_x,
		"right_x": right_x,
		"center_x": center_x,
		"center_w": center_w,
		"body_top": body_top,
		"body_bottom": body_bottom,
	}

# ─── Screen chrome ────────────────────────────────────────────────────────────
func _draw_screen_chrome(vp: Rect2) -> void:
	var lm: Dictionary = _layout_metrics(vp)
	var header_h: float = float(lm.get("header_h", HEADER_H))
	var side_w: float = float(lm.get("side_w", LEFT_PANEL_W))
	var left_x: float = float(lm.get("left_x", SAFE_PAD))
	var right_x: float = float(lm.get("right_x", vp.size.x - SAFE_PAD - RIGHT_PANEL_W))
	var center_rect := Rect2(
		float(lm.get("center_x", LEFT_PANEL_W)),
		header_h,
		float(lm.get("center_w", vp.size.x - LEFT_PANEL_W - RIGHT_PANEL_W)),
		vp.size.y - header_h)

	# Solid panel backgrounds
	draw_rect(Rect2(0.0, 0.0, left_x + side_w, vp.size.y),
		Color(0.02, 0.03, 0.06, 0.97))
	draw_rect(Rect2(right_x, 0.0, vp.size.x - right_x, vp.size.y),
		Color(0.02, 0.03, 0.06, 0.97))
	draw_rect(Rect2(0.0, 0.0, vp.size.x, header_h),
		Color(0.02, 0.05, 0.09, 0.99))

	# Left panel edge strip (cyan glow)
	draw_rect(Rect2(center_rect.position.x - 2.0, header_h, 2.0, vp.size.y - header_h),
		Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.20))
	draw_rect(Rect2(center_rect.position.x, header_h, 6.0, vp.size.y - header_h),
		Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.04))

	# Right panel edge strip (red glow)
	draw_rect(Rect2(center_rect.end.x, header_h, 2.0, vp.size.y - header_h),
		Color(C_RED.r, C_RED.g, C_RED.b, 0.15))
	draw_rect(Rect2(center_rect.end.x - 6.0, header_h, 6.0, vp.size.y - header_h),
		Color(C_RED.r, C_RED.g, C_RED.b, 0.04))

	# Centre gameplay glass overlay
	draw_rect(center_rect, Color(0.00, 0.02, 0.04, 0.022))

	# Nested frame glow lines
	for i in range(4):
		var a: float = 0.020 - float(i) * 0.004
		if a <= 0.0:
			continue
		draw_rect(
			Rect2(float(i) * 16.0, float(i) * 16.0,
				  vp.size.x - float(i) * 32.0, vp.size.y - float(i) * 32.0),
			Color(0.06, 0.14, 0.22, a), false)

	# Subtle gameplay grid
	for gx in range(int(center_rect.position.x), int(center_rect.end.x), 48):
		draw_line(
			Vector2(float(gx), center_rect.position.y),
			Vector2(float(gx), vp.size.y),
			Color(0.10, 0.28, 0.42, 0.018), 1.0)
	for gy in range(int(center_rect.position.y), int(vp.size.y), 48):
		draw_line(
			Vector2(center_rect.position.x, float(gy)),
			Vector2(center_rect.end.x,      float(gy)),
			Color(0.10, 0.28, 0.42, 0.016), 1.0)

	# Animated scan bar
	var scan_y: float = center_rect.position.y \
		+ fposmod(_ui_pulse * 42.0, center_rect.size.y + 180.0) - 90.0
	draw_rect(Rect2(center_rect.position.x, scan_y, center_rect.size.x, 2.0),
		Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.030))
	draw_rect(Rect2(center_rect.position.x, scan_y + 2.0, center_rect.size.x, 8.0),
		Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.010))

	# CRT scanlines across full screen
	for sl in range(0, int(vp.size.y), 3):
		draw_rect(Rect2(0.0, float(sl), vp.size.x, 1.0), Color(0.0, 0.0, 0.0, 0.045))

	# Header rule + animated shimmer
	draw_rect(Rect2(0.0, header_h - 2.0, vp.size.x, 2.0),
		Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.22))
	var shim_x: float = fposmod(_ui_pulse * 280.0, vp.size.x + 200.0) - 100.0
	draw_rect(Rect2(shim_x, header_h - 2.0, 100.0, 2.0), Color(1.0, 1.0, 1.0, 0.15))

	_draw_corner_brackets(center_rect, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.40))

	# Atmospheric light wells
	var wa := Vector2(
		center_rect.position.x + center_rect.size.x * 0.50,
		center_rect.position.y + center_rect.size.y * 0.42)
	for i in range(5):
		draw_circle(wa, 220.0 - float(i) * 32.0,
			Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.006 - float(i) * 0.0008))

	var wb := Vector2(
		center_rect.position.x + center_rect.size.x * 0.86,
		center_rect.position.y + center_rect.size.y * 0.76)
	for i in range(4):
		draw_circle(wb, 120.0 - float(i) * 18.0,
			Color(C_ORANGE.r, C_ORANGE.g, C_ORANGE.b, 0.006 - float(i) * 0.0009))

	# Alert vignette flash on camera detection / exit rotation
	if _alert_flash > 0.001:
		draw_rect(Rect2(0.0, 0.0, vp.size.x, vp.size.y),
			Color(C_RED.r, C_RED.g, C_RED.b, _alert_flash * 0.12))
		draw_rect(Rect2(0.0, 0.0, vp.size.x, 4.0),
			Color(C_RED.r, C_RED.g, C_RED.b, _alert_flash * 0.80))
		draw_rect(Rect2(0.0, vp.size.y - 4.0, vp.size.x, 4.0),
			Color(C_RED.r, C_RED.g, C_RED.b, _alert_flash * 0.80))
		draw_rect(Rect2(0.0, 0.0, 4.0, vp.size.y),
			Color(C_RED.r, C_RED.g, C_RED.b, _alert_flash * 0.80))
		draw_rect(Rect2(vp.size.x - 4.0, 0.0, 4.0, vp.size.y),
			Color(C_RED.r, C_RED.g, C_RED.b, _alert_flash * 0.80))

	# Corner vignette darkening
	var corner_positions: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(vp.size.x, 0.0),
		Vector2(0.0, vp.size.y),
		vp.size,
	]
	for cp in corner_positions:
		draw_circle(cp, 180.0, Color(0.0, 0.0, 0.0, 0.22))

# ─── Header bar ───────────────────────────────────────────────────────────────
func _draw_header_bar(vp: Rect2, font: Font) -> void:
	if font == null:
		return
	var lm: Dictionary = _layout_metrics(vp)
	var header_h: float = float(lm.get("header_h", HEADER_H))
	var side_w: float = float(lm.get("side_w", LEFT_PANEL_W))
	var left_x: float = float(lm.get("left_x", SAFE_PAD))
	var right_x: float = float(lm.get("right_x", vp.size.x - SAFE_PAD - RIGHT_PANEL_W))
	var pulse: float = 0.5 + 0.5 * sin(_ui_pulse * 2.0)

	# Logo box
	var logo_h: float = clampf(header_h - 20.0, 36.0, 46.0)
	var logo_rect: Rect2 = Rect2(left_x + 8.0, 10.0, 54.0, logo_h)
	draw_rect(logo_rect, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.12 + pulse * 0.04))
	draw_rect(Rect2(logo_rect.position, Vector2(logo_rect.size.x, 4.0)),
		Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.35))
	draw_rect(logo_rect, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.36 + pulse * 0.06), false)
	draw_rect(Rect2(logo_rect.position + Vector2(3.0, 3.0), logo_rect.size - Vector2(6.0, 6.0)),
		Color(0.03, 0.08, 0.16, 0.98))
	draw_string(font, logo_rect.position + Vector2(14.0, logo_rect.size.y * 0.62),
		"PB", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, C_CYAN)

	# Title
	var title_x: float = logo_rect.end.x + 12.0
	var title_size: int = 26 if vp.size.x < 1440.0 else 30
	draw_string(font, Vector2(title_x, 27.0) + Vector2(0.0, 4.0),
		"PRISON BREAK", HORIZONTAL_ALIGNMENT_LEFT, -1, 30,
		Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.22 + pulse * 0.12))
	draw_string(font, Vector2(title_x, 27.0),
		"PRISON BREAK", HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(0.95, 0.99, 1.0))
	if vp.size.x >= 1360.0:
		draw_string(font, Vector2(title_x, 48.0),
		"SURVEILLANCE COMMAND CENTER — MAXIMUM SECURITY",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_DIM)

	# Agent count badges
	var counts:  Dictionary = _role_counts()
	var stat_w:  float = clampf(side_w * 0.26, 62.0, 76.0)
	var center_mid: float = left_x + side_w + float(lm.get("center_w", 560.0)) * 0.5
	var start_x: float = center_mid - stat_w * 1.5 - 12.0
	var hdr_colors: Array = [C_YELLOW, Color(0.31, 0.76, 0.97), C_ORANGE]
	var hdr_labels: Array = ["OFFICERS", "BLUE", "RED"]
	var hdr_values: Array = [
		counts.get("police",      0),
		counts.get("sneaky_blue", 0),
		counts.get("rusher_red",  0),
	]
	for i in range(3):
		var r: Rect2   = Rect2(start_x + float(i) * (stat_w + 8.0), 14.0, stat_w, header_h - 24.0)
		var cc: Color  = hdr_colors[i]
		draw_rect(Rect2(r.position + Vector2(3.0, 4.0), r.size), Color(0.0, 0.0, 0.0, 0.28))
		draw_rect(r, Color(cc.r, cc.g, cc.b, 0.10))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 4.0)), Color(cc.r, cc.g, cc.b, 0.32))
		draw_rect(r, Color(cc.r, cc.g, cc.b, 0.30 + pulse * 0.05), false)
		draw_string(font, r.position + Vector2(8.0, 15.0),
			hdr_labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_DIM)
		draw_string(font, r.position + Vector2(8.0, minf(r.size.y - 7.0, 31.0)),
			str(hdr_values[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cc)

	# Alert banner
	var alert:      Dictionary = _alert_banner_data()
	var alert_text: String     = str(alert.get("text",  "SURVEILLANCE NOMINAL"))
	var ac:         Color      = alert.get("color", C_CYAN)
	var tick_w: float = 236.0
	var alert_w: float = clampf(side_w * 0.94, 220.0, 286.0)
	var ar:         Rect2      = Rect2(right_x - alert_w - 16.0, 14.0, alert_w, header_h - 24.0)
	draw_rect(Rect2(ar.position + Vector2(3.0, 4.0), ar.size), Color(0.0, 0.0, 0.0, 0.30))
	draw_rect(ar, Color(ac.r, ac.g, ac.b, 0.10 + pulse * 0.06))
	draw_rect(Rect2(ar.position, Vector2(ar.size.x, 4.0)), Color(ac.r, ac.g, ac.b, 0.30))
	draw_rect(ar, Color(ac.r, ac.g, ac.b, 0.58 + pulse * 0.10), false)
	draw_string(font, ar.position + Vector2(10.0, minf(23.0, ar.size.y * 0.65)),
		alert_text, HORIZONTAL_ALIGNMENT_LEFT, ar.size.x - 16.0, 11, ac)

	# Match timer + tick/exit counter
	var remain_s: float = 0.0
	if _sim != null:
		remain_s = _sim.get_time_remaining_seconds()
	var timer_text: String = "%04.1fs" % remain_s
	var timer_col: Color = C_GREEN if remain_s > 12.0 else (C_YELLOW if remain_s > 6.0 else C_RED)
	var tr: Rect2 = Rect2(right_x + side_w - tick_w - 8.0, 12.0, tick_w, header_h - 20.0)
	draw_rect(Rect2(tr.position + Vector2(3.0, 4.0), tr.size), Color(0.0, 0.0, 0.0, 0.28))
	draw_rect(tr, Color(0.00, 0.00, 0.00, 0.30))
	draw_rect(Rect2(tr.position, Vector2(tr.size.x, 4.0)),
		Color(timer_col.r, timer_col.g, timer_col.b, 0.30))
	draw_rect(tr, Color(timer_col.r, timer_col.g, timer_col.b, 0.44), false)
	draw_string(font, tr.position + Vector2(12.0, 15.0),
		"MATCH TIMER", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_DIM)
	draw_string(font, tr.position + Vector2(12.0, 36.0),
		timer_text, HORIZONTAL_ALIGNMENT_LEFT, tr.size.x - 16.0, 28, timer_col)
	draw_string(font, tr.position + Vector2(12.0, minf(tr.size.y - 6.0, 52.0)),
		"%03d   ·   %s" % [_tick, _tile_text(_active_exit)],
		HORIZONTAL_ALIGNMENT_LEFT, tr.size.x - 16.0, 12, C_CYAN)

# ─── Map toolbar ──────────────────────────────────────────────────────────────
func _draw_map_toolbar(vp: Rect2, font: Font) -> void:
	if font == null:
		return
	var lm: Dictionary = _layout_metrics(vp)
	var center_x: float = float(lm.get("center_x", LEFT_PANEL_W))
	var center_w: float = float(lm.get("center_w", vp.size.x - LEFT_PANEL_W - RIGHT_PANEL_W))
	var header_h: float = float(lm.get("header_h", HEADER_H))
	var toolbar_h: float = float(lm.get("toolbar_h", MAP_TOOLBAR_H))
	var rect: Rect2 = Rect2(
		center_x + 10.0,
		header_h + 8.0,
		center_w - 20.0,
		toolbar_h)
	draw_rect(rect, Color(0.02, 0.06, 0.10, 0.94))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4.0)),
		Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.20))
	draw_rect(rect, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.20), false)

	# Shimmer bar
	var shim: float = fposmod(_ui_pulse * 220.0, rect.size.x + 80.0) - 40.0
	draw_rect(Rect2(rect.position.x + shim, rect.position.y + 4.0, 40.0, rect.size.y - 4.0),
		Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.018))

	var buttons: Array = _toolbar_button_data(rect)
	var bx: float = rect.position.x + 10.0
	var buttons_end: float = bx
	for i in range(buttons.size()):
		var b: Dictionary = buttons[i]
		var label_str: String = str(b.get("label", "BTN"))
		var w: float   = 108.0 if label_str.length() > 8 else 82.0
		var br: Rect2  = Rect2(bx, rect.position.y + 5.0, w, rect.size.y - 10.0)
		var is_on: bool = bool(b.get("active", false))
		var is_hover: bool = i == _toolbar_hover_idx
		var col: Color = C_CYAN if is_on else C_DIM
		if is_hover:
			col = col.lerp(Color.WHITE, 0.35)
		_toolbar_buttons[i]["rect"] = br
		draw_rect(Rect2(br.position + Vector2(2.0, 3.0), br.size), Color(0.0, 0.0, 0.0, 0.22))
		draw_rect(br, Color(col.r, col.g, col.b, 0.16 if is_hover else 0.10))
		draw_rect(Rect2(br.position, Vector2(br.size.x, 3.0)), Color(col.r, col.g, col.b, 0.24))
		draw_rect(br, Color(col.r, col.g, col.b, 0.48 if is_hover else 0.32), false)
		if is_on:
			draw_rect(Rect2(br.position.x, br.end.y - 2.0, br.size.x, 2.0),
				Color(col.r, col.g, col.b, 0.60))
		draw_string(font, br.position + Vector2(9.0, br.size.y * 0.56 + 5.0),
			label_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		bx += w + 8.0
		buttons_end = br.end.x

	var info: String = "TRACKING %d ENTITIES   ·   ACTIVE EXIT %s   ·   AI CYCLE POL %.2fs / PRIS %.2fs" % [
		_active_entities_count(), _tile_text(_active_exit), POLICE_DECISION_INTERVAL_SEC, PRISONER_DECISION_INTERVAL_SEC]
	var info_w: float = font.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var info_x: float = rect.end.x - info_w - 10.0
	if info_x > buttons_end + 14.0:
		draw_string(font, Vector2(info_x, rect.position.y + rect.size.y * 0.60),
			info, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)

func _toolbar_button_data(_toolbar_rect: Rect2) -> Array:
	if _toolbar_buttons.size() != 4:
		_toolbar_buttons = [
			{"label": "LIVE FEED", "action": "live",   "active": true,  "rect": Rect2()},
			{"label": "HEAT MAP", "action": "danger", "active": false, "rect": Rect2()},
			{"label": "PATROL ROUTES", "action": "path", "active": false, "rect": Rect2()},
			{"label": "ALERTS", "action": "vision", "active": false, "rect": Rect2()},
		]
	for i in range(_toolbar_buttons.size()):
		var action_name: String = str(_toolbar_buttons[i].get("action", ""))
		if action_name in ["danger", "path", "vision"] and _overlay_manager != null:
			_toolbar_buttons[i]["active"] = _overlay_manager.is_overlay_visible(action_name)
		elif action_name == "live":
			_toolbar_buttons[i]["active"] = true
	return _toolbar_buttons

func _toolbar_index_at(pos: Vector2) -> int:
	var vp: Rect2 = get_viewport_rect()
	var lm: Dictionary = _layout_metrics(vp)
	var center_x: float = float(lm.get("center_x", LEFT_PANEL_W))
	var center_w: float = float(lm.get("center_w", vp.size.x - LEFT_PANEL_W - RIGHT_PANEL_W))
	var header_h: float = float(lm.get("header_h", HEADER_H))
	var toolbar_h: float = float(lm.get("toolbar_h", MAP_TOOLBAR_H))
	var toolbar_rect: Rect2 = Rect2(
		center_x + 10.0,
		header_h + 8.0,
		center_w - 20.0,
		toolbar_h)
	var buttons: Array = _toolbar_button_data(toolbar_rect)
	var bx: float = toolbar_rect.position.x + 10.0
	for i in range(buttons.size()):
		var label_str: String = str(buttons[i].get("label", "BTN"))
		var w: float = 108.0 if label_str.length() > 8 else 82.0
		_toolbar_buttons[i]["rect"] = Rect2(bx, toolbar_rect.position.y + 5.0, w, toolbar_rect.size.y - 10.0)
		bx += w + 8.0
	for i in range(_toolbar_buttons.size()):
		var br: Rect2 = _toolbar_buttons[i].get("rect", Rect2())
		if br.has_point(pos):
			return i
	return -1

func _handle_toolbar_action(action_name: String) -> void:
	match action_name:
		"live":
			_push_activity("Live CCTV feed selected", "info")
		"danger", "path", "vision":
			if _overlay_manager == null:
				_push_activity("Overlay manager unavailable", "warning")
				return
			var now_visible: bool = _overlay_manager.toggle_overlay_by_name(action_name)
			var mode_label: String = action_name.to_upper()
			_push_activity("%s %s" % [mode_label, "ON" if now_visible else "OFF"], "info")
			queue_redraw()

# ─── Column layout ────────────────────────────────────────────────────────────
func _draw_left_column(vp: Rect2, font: Font) -> void:
	var lm: Dictionary = _layout_metrics(vp)
	var x: float = float(lm.get("left_x", SAFE_PAD)) + PANEL_PAD * 0.5
	var y: float = float(lm.get("body_top", HEADER_H + PANEL_PAD))
	var w: float = float(lm.get("side_w", LEFT_PANEL_W)) - PANEL_PAD
	var body_bottom: float = float(lm.get("body_bottom", vp.size.y - BOTTOM_SAFE))
	var gap: float = 8.0
	var available_h: float = body_bottom - y
	var compact: bool = available_h < 860.0
	var cam_h: float = clampf(available_h * (0.45 if compact else 0.52), 170.0, 470.0)
	var min_agents_h: float = 250.0 if compact else 300.0
	if available_h - cam_h - gap < min_agents_h:
		cam_h = maxf(170.0, available_h - min_agents_h - gap)
	_draw_panel_shell(Rect2(x, y, w, cam_h), "CC CAMERAS", C_CYAN, font)
	_draw_camera_stack(Rect2(x + 8.0, y + 36.0, w - 16.0, cam_h - 46.0), font)
	y += cam_h + gap

	var agents_h: float = maxf(120.0, body_bottom - y)
	_draw_panel_shell(Rect2(x, y, w, agents_h), "AGENTS ON MAP", C_ORANGE, font)
	_draw_agent_stack(Rect2(x + 8.0, y + 36.0, w - 16.0, agents_h - 46.0), font)

func _draw_right_column(vp: Rect2, font: Font) -> void:
	var lm: Dictionary = _layout_metrics(vp)
	var side_w: float = float(lm.get("side_w", RIGHT_PANEL_W))
	var x: float = float(lm.get("right_x", vp.size.x - SAFE_PAD - RIGHT_PANEL_W)) + PANEL_PAD * 0.5
	var y: float = float(lm.get("body_top", HEADER_H + PANEL_PAD))
	var w: float = side_w - PANEL_PAD
	var body_bottom: float = float(lm.get("body_bottom", vp.size.y - BOTTOM_SAFE))
	var gap: float = 8.0
	var available_h: float = body_bottom - y
	var compact: bool = available_h < 860.0
	var inner_h: float = maxf(220.0, available_h - gap * 2.0)

	var log_h: float = clampf(inner_h * (0.42 if compact else 0.46), 170.0, 340.0)
	var threat_h: float = clampf(inner_h * (0.21 if compact else 0.24), 120.0, 210.0)
	var status_h: float = inner_h - log_h - threat_h
	if status_h < 130.0:
		var deficit: float = 130.0 - status_h
		var reduce_log: float = minf(deficit, maxf(0.0, log_h - 170.0))
		log_h -= reduce_log
		deficit -= reduce_log
		var reduce_threat: float = minf(deficit, maxf(0.0, threat_h - 120.0))
		threat_h -= reduce_threat
		status_h = inner_h - log_h - threat_h

	_draw_panel_shell(Rect2(x, y, w, log_h), "INCIDENT LOG", C_RED, font)
	_draw_activity_panel(Rect2(x + 8.0, y + 36.0, w - 16.0, log_h - 46.0), font)
	y += log_h + gap

	_draw_panel_shell(Rect2(x, y, w, threat_h), "THREAT LEVEL", C_YELLOW, font)
	_draw_threat_panel(Rect2(x + 8.0, y + 34.0, w - 16.0, threat_h - 44.0), font)
	y += threat_h + gap

	_draw_panel_shell(Rect2(x, y, w, status_h), "SECTOR STATUS", C_GREEN, font)
	_draw_sector_status(Rect2(x + 10.0, y + 36.0, w - 20.0, status_h - 46.0), font)

# ─── Panel shell ──────────────────────────────────────────────────────────────
func _draw_panel_shell(rect: Rect2, title: String, accent: Color, font: Font) -> void:
	# Drop shadow
	draw_rect(Rect2(rect.position + Vector2(5.0, 7.0), rect.size), Color(0, 0, 0, 0.40))
	# Panel body layers
	draw_rect(rect, C_BG_PANEL)
	draw_rect(Rect2(rect.position + Vector2(1.0, 1.0), rect.size - Vector2(2.0, 2.0)),
		C_PANEL_INNER)
	# Metallic top accent strip
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 5.0)),
		Color(accent.r, accent.g, accent.b, 0.28))
	# Title underline
	draw_rect(Rect2(rect.position + Vector2(4.0, 34.0), Vector2(rect.size.x - 8.0, 1.0)),
		Color(accent.r, accent.g, accent.b, 0.20))
	# Main border
	draw_rect(rect, Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.78), false)
	# Outer glow halos
	for i in range(3):
		var ha: float = 0.022 - float(i) * 0.007
		draw_rect(
			Rect2(rect.position - Vector2(float(i), float(i)),
				  rect.size + Vector2(float(i) * 2.0, float(i) * 2.0)),
			Color(accent.r, accent.g, accent.b, ha), false)
	# Inner bevel
	draw_rect(Rect2(rect.position + Vector2(2.0, 2.0), rect.size - Vector2(4.0, 4.0)),
		Color(1.0, 1.0, 1.0, 0.020), false)

	# Rivets at top corners
	var rivet_pts: Array[Vector2] = [
		rect.position + Vector2(8.0, 10.0),
		Vector2(rect.end.x - 8.0, rect.position.y + 10.0),
	]
	for rp in rivet_pts:
		draw_circle(rp, 3.0, Color(0.12, 0.20, 0.32, 0.95))
		draw_circle(rp, 2.0, Color(0.08, 0.14, 0.24, 1.0))
		draw_circle(rp + Vector2(-0.5, -0.5), 0.8, Color(0.40, 0.55, 0.70, 0.60))

	_draw_corner_brackets(rect, accent)

	if font != null:
		draw_circle(rect.position + Vector2(20.0, 17.0), 3.5, accent)
		draw_circle(rect.position + Vector2(20.0, 17.0), 2.0,
			Color(accent.r, accent.g, accent.b, 0.30))
		draw_string(font, rect.position + Vector2(30.0, 20.0),
			title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, accent)

func _draw_corner_brackets(rect: Rect2, accent: Color) -> void:
	var arm: float = 14.0
	# Top-left
	draw_line(rect.position, rect.position + Vector2(arm, 0.0),  accent, 1.5)
	draw_line(rect.position, rect.position + Vector2(0.0, arm),  accent, 1.5)
	# Top-right
	draw_line(Vector2(rect.end.x, rect.position.y),
			  Vector2(rect.end.x - arm, rect.position.y), accent, 1.5)
	draw_line(Vector2(rect.end.x, rect.position.y),
			  Vector2(rect.end.x, rect.position.y + arm), accent, 1.5)
	# Bottom-left
	draw_line(Vector2(rect.position.x, rect.end.y),
			  Vector2(rect.position.x + arm, rect.end.y), accent, 1.5)
	draw_line(Vector2(rect.position.x, rect.end.y),
			  Vector2(rect.position.x, rect.end.y - arm), accent, 1.5)
	# Bottom-right
	draw_line(rect.end, rect.end - Vector2(arm, 0.0), accent, 1.5)
	draw_line(rect.end, rect.end - Vector2(0.0, arm), accent, 1.5)

# ─── Camera previews ──────────────────────────────────────────────────────────
func _draw_camera_stack(rect: Rect2, font: Font) -> void:
	var feed_count: int = 3
	var gap: float = 6.0 if rect.size.y < 320.0 else 8.0
	var feed_h: float = (rect.size.y - gap * float(feed_count - 1)) / float(feed_count)
	for i in range(feed_count):
		var feed_rect: Rect2 = Rect2(
			rect.position.x,
			rect.position.y + float(i) * (feed_h + gap),
			rect.size.x, feed_h)
		var state: Dictionary = _camera_states[i] if i < _camera_states.size() else {}
		_draw_camera_preview(feed_rect, state, i, font)

func _draw_camera_preview(rect: Rect2, state: Dictionary, index: int, font: Font) -> void:
	var has_targets: bool  = not Array(state.get("visible_targets", [])).is_empty()
	var accent: Color      = C_RED if has_targets else C_GREEN

	draw_rect(rect, Color(0.00, 0.01, 0.01, 0.94))
	draw_rect(Rect2(rect.position + Vector2(2.0, 2.0), rect.size - Vector2(4.0, 4.0)),
		Color(C_GREEN.r, C_GREEN.g, C_GREEN.b, 0.04))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.22), false)

	var inner: Rect2 = rect.grow(-5.0)
	draw_rect(inner, Color(0.00, 0.04, 0.03, 0.96))
	_draw_preview_scene(inner, state)

	# CRT scanlines
	for sy in range(int(inner.position.y), int(inner.end.y), 3):
		draw_rect(Rect2(inner.position.x, float(sy), inner.size.x, 1.0),
			Color(0, 0, 0, 0.12))
	# Noise grain
	for i in range(28):
		var nx: float = inner.position.x \
			+ fposmod(float(i * 19) + _ui_pulse * 37.0, inner.size.x)
		var ny: float = inner.position.y \
			+ fposmod(float(i * 11) + _ui_pulse * 23.0, inner.size.y)
		draw_rect(Rect2(nx, ny, 1.0, 1.0), Color(1, 1, 1, 0.022))
	# Sweep line
	var scan_y: float = inner.position.y \
		+ fposmod(_ui_pulse * 44.0 + float(index) * 24.0, maxf(6.0, inner.size.y - 2.0))
	draw_rect(Rect2(inner.position.x, scan_y, inner.size.x, 2.0),
		Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.16))
	draw_rect(Rect2(inner.position.x, scan_y + 2.0, inner.size.x, 8.0),
		Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.04))

	# Detection flash frame
	if has_targets:
		var flash: float = 0.5 + 0.5 * sin(_ui_pulse * 8.0)
		draw_rect(inner, Color(C_RED.r, C_RED.g, C_RED.b, 0.10 * flash))
		draw_rect(inner, Color(C_RED.r, C_RED.g, C_RED.b, 0.60 * flash), false)

	if font != null:
		draw_rect(Rect2(rect.position.x + 6.0, rect.position.y + 6.0, 130.0, 16.0),
			Color(0, 0, 0, 0.60))
		draw_string(font, rect.position + Vector2(10.0, 18.0),
			"CAM-%02d / CCTV NODE" % (index + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, accent)
		draw_rect(Rect2(rect.end.x - 52.0, rect.position.y + 6.0, 42.0, 16.0),
			Color(0, 0, 0, 0.60))
		var rec_alpha: float = 0.6 + 0.4 * sin(_ui_pulse * 3.0 + float(index) * 1.5)
		draw_circle(Vector2(rect.end.x - 40.0, rect.position.y + 14.0), 3.5,
			Color(accent.r, accent.g, accent.b, rec_alpha))
		draw_string(font, rect.position + Vector2(rect.size.x - 30.0, 18.0),
			"REC", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, accent)
		draw_string(font,
			Vector2(rect.end.x - 126.0, rect.end.y - 7.0),
			"T%03d  %02d:%02d" % [
				_tick,
				int(fmod(_ui_pulse * 12.0, 60.0)),
				int(fmod(_ui_pulse * 60.0, 60.0))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.40))

func _draw_preview_scene(rect: Rect2, state: Dictionary) -> void:
	if _sim == null or _sim._grid == null:
		return
	var cam_pos:    Vector2i = state.get("pos",     Vector2i(10, 10))
	var cam_facing: Vector2i = state.get("facing",  Vector2i.RIGHT)
	var cam_range:  int      = int(state.get("range",   6))
	var cam_fov:    float    = float(state.get("fov_deg", 72.0))
	var visible_targets: Array = Array(state.get("visible_targets", []))
	var half_x: int = 3
	var half_y: int = 2
	var tile_px: float = floor(minf(rect.size.x / 7.0, rect.size.y / 5.0))
	var ox: float = rect.position.x + (rect.size.x - tile_px * 7.0) * 0.5
	var oy: float = rect.position.y + (rect.size.y - tile_px * 5.0) * 0.5

	for ty in range(-half_y, half_y + 1):
		for tx in range(-half_x, half_x + 1):
			var pos: Vector2i       = cam_pos + Vector2i(tx, ty)
			var tile: GridTileData  = _sim._grid.get_tile(pos)
			if tile == null:
				continue
			var rx: float = ox + float(tx + half_x) * tile_px
			var ry: float = oy + float(ty + half_y) * tile_px
			var vis: bool = _preview_camera_sees_tile(cam_pos, cam_facing, cam_range, cam_fov, pos)
			var r: Rect2  = Rect2(rx, ry, tile_px, tile_px)
			if tile.walkable:
				var floor_col: Color = Color(0.02, 0.16, 0.10, 0.90) \
					if (pos.x + pos.y) % 2 == 0 else Color(0.03, 0.12, 0.08, 0.90)
				draw_rect(r, floor_col)
				draw_rect(Rect2(r.position, Vector2(r.size.x, 2.0)), Color(1, 1, 1, 0.05))
				draw_rect(r.grow(-1.0), Color(0.05, 0.24, 0.14, 0.16), false)
			else:
				draw_rect(r, Color(0.05, 0.10, 0.10, 1.0))
				draw_rect(Rect2(r.position, Vector2(r.size.x, 4.0)), Color(0.10, 0.20, 0.18))
				draw_rect(Rect2(r.position + Vector2(0.0, r.size.y - 4.0), Vector2(r.size.x, 4.0)),
					Color(0.01, 0.02, 0.02, 0.55))
			if not vis:
				draw_rect(r, Color(0.0, 0.0, 0.0, 0.46))

	# Sweep beam
	var sweep_origin: Vector2 = Vector2(
		ox + (float(half_x) + 0.5) * tile_px,
		oy + (float(half_y) + 0.5) * tile_px)
	var base_ang:  float = atan2(float(cam_facing.y), float(cam_facing.x))
	var wobble:    float = sin(_ui_pulse * 1.8 + float(int(state.get("id", 0))) * 0.7) * 0.22
	var sweep_len: float = tile_px * float(mini(cam_range + 1, 5))
	draw_line(sweep_origin,
		sweep_origin + Vector2(cos(base_ang + wobble), sin(base_ang + wobble)) * sweep_len,
		Color(0.55, 1.0, 0.88, 0.50), 2.0)
	draw_arc(sweep_origin, 7.0, 0.0, TAU, 14, Color(0.55, 1.0, 0.88, 0.32), 1.0)

	# Fire hazard tiles
	var fire_tiles: Array = []
	if _sim._fire_hazard != null:
		fire_tiles = _sim._fire_hazard.get_fire_tiles()
	for fire_tile in fire_tiles:
		var ft: Vector2i = fire_tile
		if absi(ft.x - cam_pos.x) > half_x or absi(ft.y - cam_pos.y) > half_y:
			continue
		if not _preview_camera_sees_tile(cam_pos, cam_facing, cam_range, cam_fov, ft):
			continue
		var fx: float = ox + float(ft.x - cam_pos.x + half_x) * tile_px
		var fy: float = oy + float(ft.y - cam_pos.y + half_y) * tile_px
		draw_rect(Rect2(fx + 1.0, fy + 1.0, tile_px - 2.0, tile_px - 2.0),
			Color(0.45, 0.08, 0.02, 0.62))
		draw_circle(Vector2(fx + tile_px * 0.5, fy + tile_px * 0.55),
			tile_px * 0.32, Color(1.0, 0.42, 0.08, 0.14))
		draw_colored_polygon(PackedVector2Array([
			Vector2(fx + tile_px * 0.18, fy + tile_px * 0.90),
			Vector2(fx + tile_px * 0.50, fy + tile_px * 0.16),
			Vector2(fx + tile_px * 0.80, fy + tile_px * 0.90),
		]), Color(1.00, 0.72, 0.16, 0.86))

	# Dog NPC
	if _sim._dog_npc != null:
		var dp: Vector2i = _sim._dog_npc.grid_pos
		if absi(dp.x - cam_pos.x) <= half_x and absi(dp.y - cam_pos.y) <= half_y:
			if _preview_camera_sees_tile(cam_pos, cam_facing, cam_range, cam_fov, dp):
				var dx: float = ox + float(dp.x - cam_pos.x + half_x) * tile_px + tile_px * 0.5
				var dy: float = oy + float(dp.y - cam_pos.y + half_y) * tile_px + tile_px * 0.5
				draw_circle(Vector2(dx, dy), tile_px * 0.18, Color(0.85, 0.62, 0.30, 0.95))
				draw_circle(Vector2(dx + tile_px * 0.18, dy), tile_px * 0.08,
					Color(0.10, 0.08, 0.06))

	# Agents
	for agent in _agents:
		var pos: Vector2i = agent.grid_pos
		if absi(pos.x - cam_pos.x) > half_x or absi(pos.y - cam_pos.y) > half_y:
			continue
		if not _preview_camera_sees_tile(cam_pos, cam_facing, cam_range, cam_fov, pos):
			continue
		var tile_xf: float = float(pos.x) + 0.5
		var tile_yf: float = float(pos.y) + 0.5
		if agent is Node2D:
			tile_xf = float(agent.position.x) / TILE_SIZE
			tile_yf = float(agent.position.y) / TILE_SIZE
		var ax: float = ox + (tile_xf - float(cam_pos.x) + float(half_x)) * tile_px
		var ay: float = oy + (tile_yf - float(cam_pos.y) + float(half_y)) * tile_px
		var col: Color = _role_color(agent._role)
		draw_circle(Vector2(ax, ay), tile_px * 0.22, col)
		_draw_ellipse(
			Vector2(ax, ay + tile_px * 0.20),
			Vector2(tile_px * 0.16, tile_px * 0.06),
			Color(0, 0, 0, 0.35))
		draw_circle(Vector2(ax, ay - tile_px * 0.13), tile_px * 0.08, Color(1, 1, 1, 0.85))
		if visible_targets.has(agent.agent_id):
			draw_rect(
				Rect2(ax - tile_px * 0.34, ay - tile_px * 0.48,
					  tile_px * 0.68, tile_px * 0.86),
				Color(C_RED.r, C_RED.g, C_RED.b, 0.60), false)

func _preview_camera_sees_tile(
		cam_pos: Vector2i,
		facing: Vector2i,
		range_tiles: int,
		fov_deg: float,
		tile_pos: Vector2i) -> bool:
	if _sim == null or _sim._grid == null:
		return false
	if tile_pos == cam_pos:
		return true
	if manhattan(cam_pos, tile_pos) > range_tiles:
		return false
	if not _sim._grid.raycast(cam_pos, tile_pos):
		return false
	var dir: Vector2 = Vector2(tile_pos - cam_pos)
	if dir == Vector2.ZERO:
		return true
	var f: Vector2 = Vector2(facing)
	if f == Vector2.ZERO:
		f = Vector2.RIGHT
	return rad_to_deg(acos(clampf(f.normalized().dot(dir.normalized()), -1.0, 1.0))) <= fov_deg * 0.5

func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(16):
		var a := TAU * float(i) / 16.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, color)

func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

# ─── Agent card stack ─────────────────────────────────────────────────────────
func _draw_agent_stack(rect: Rect2, font: Font) -> void:
	var count: int = mini(_panels.size(), 3)
	if count <= 0:
		return
	var gap: float = 6.0 if rect.size.y < 320.0 else 8.0
	var card_h: float = (rect.size.y - gap * float(count - 1)) / float(count)
	for i in range(count):
		var r: Rect2 = Rect2(
			rect.position.x,
			rect.position.y + float(i) * (card_h + gap),
			rect.size.x, card_h)
		_draw_agent_card(_panels[i] as AgentPanel, r, font)

func _draw_agent_card(ap: AgentPanel, rect: Rect2, font: Font) -> void:
	var pulse: float = 0.5 + 0.5 * sin(_ui_pulse * 3.0 + float(ap.agent_id))
	var compact: bool = rect.size.y < 118.0
	var micro: bool = rect.size.y < 96.0

	# Drop shadow + body
	draw_rect(Rect2(rect.position + Vector2(3.0, 4.0), rect.size), Color(0, 0, 0, 0.40))
	draw_rect(rect, Color(0.03, 0.06, 0.12, 0.97))
	draw_rect(Rect2(rect.position + Vector2(2.0, 2.0), rect.size - Vector2(4.0, 4.0)),
		Color(ap.role_color.r, ap.role_color.g, ap.role_color.b, 0.05))
	# Left accent bar + inner glow
	draw_rect(Rect2(rect.position, Vector2(4.0, rect.size.y)),
		Color(ap.role_color.r, ap.role_color.g, ap.role_color.b, 0.90))
	draw_rect(Rect2(rect.position + Vector2(4.0, 0.0), Vector2(8.0, rect.size.y)),
		Color(ap.role_color.r, ap.role_color.g, ap.role_color.b, 0.06))
	draw_rect(rect, Color(ap.role_color.r, ap.role_color.g, ap.role_color.b,
		0.24 + pulse * 0.06), false)

	var portrait_w: float = 40.0 if micro else (44.0 if compact else 50.0)
	var portrait_rect: Rect2 = Rect2(rect.position.x + 8.0, rect.position.y + 8.0, portrait_w, rect.size.y - 16.0)
	_draw_portrait(portrait_rect, ap.role)

	# Compact status badge
	var status_col: Color = ap.role_color
	var status_text: String = "OK"
	if ap.is_eliminated:
		status_text = "K.O"
		status_col  = C_RED
	elif ap.is_escaped:
		status_text = "OUT"
		status_col  = C_ORANGE
	elif not ap.is_active:
		status_text = "HOLD"
		status_col  = C_YELLOW

	var text_x: float = portrait_rect.end.x + 8.0
	var text_w: float = rect.end.x - text_x - 8.0
	var badge_w: float = 40.0 if micro else 46.0
	var top_y: float = rect.position.y + 8.0
	var title_y: float = top_y + 14.0
	var sub_y: float = top_y + (24.0 if compact else 30.0)
	var stat_row_y: float = top_y + (32.0 if compact else 40.0)
	var score_y: float = top_y + (52.0 if compact else 78.0)
	var detail_y: float = top_y + (66.0 if compact else 93.0)
	draw_string(font, Vector2(text_x, title_y),
		ap.label, HORIZONTAL_ALIGNMENT_LEFT, text_w - badge_w - 8.0, 12 if micro else 13, ap.role_color)
	draw_string(font, Vector2(text_x, sub_y),
		"%s controller" % ap.ai_label,
		HORIZONTAL_ALIGNMENT_LEFT, text_w - badge_w - 8.0, 9 if micro else 10, C_DIM)

	var badge: Rect2 = Rect2(rect.end.x - badge_w - 8.0, top_y, badge_w, 18.0)
	draw_rect(badge, Color(status_col.r, status_col.g, status_col.b, 0.12 + pulse * 0.06))
	draw_rect(Rect2(badge.position, Vector2(badge.size.x, 3.0)),
		Color(status_col.r, status_col.g, status_col.b, 0.30))
	draw_rect(badge, Color(status_col.r, status_col.g, status_col.b, 0.36), false)
	draw_string(font, badge.position + Vector2(7.0, 12.0),
		status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9 if micro else 10, status_col)

	var chip_gap: float = 6.0
	var chip_w: float = (text_w - chip_gap) * 0.5
	_draw_info_chip(
		Rect2(text_x, stat_row_y, chip_w, 14.0 if micro else 15.0),
		"HP",
		"%d/%d" % [int(round(ap.display_health)), int(round(ap.max_health))],
		Color(0.92, 0.36, 0.32),
		font
	)
	var stamina_name: String = "STM"
	var stamina_value: int = int(round(ap.display_stamina))
	var stamina_max: int = int(round(ap.max_stamina))
	if ap.role == "sneaky_blue":
		stamina_name = "STL"
		stamina_value = int(round(ap.stealth))
		stamina_max = 100
	elif ap.role == "police":
		stamina_name = "ALERT"
		stamina_value = int(round(ap.alert_level * 100.0))
		stamina_max = 100
	_draw_info_chip(
		Rect2(text_x + chip_w + chip_gap, stat_row_y, chip_w, 14.0 if micro else 15.0),
		stamina_name,
		"%d/%d" % [stamina_value, stamina_max],
		C_YELLOW,
		font
	)

	draw_string(font, Vector2(text_x, score_y),
		"SCORE %d  PERF %d" % [int(ap.raw_score), int(ap.performance_score)],
		HORIZONTAL_ALIGNMENT_LEFT, text_w, 8 if micro else 9, C_TEXT)
	if not compact and ap.role == "police":
		draw_string(font, Vector2(text_x, detail_y),
			"CAP %d  DOG %d  CCTV %d" % [
				ap.captures_made, ap.dog_assists, ap.cctv_assists],
			HORIZONTAL_ALIGNMENT_LEFT, text_w, 8 if micro else 9, C_DIM)
	elif not compact:
		draw_string(font, Vector2(text_x, detail_y),
			"STL %d  PROG %d  CAM %d" % [
				int(ap.stealth), ap.best_progress_cells, ap.camera_hits],
			HORIZONTAL_ALIGNMENT_LEFT, text_w, 8 if micro else 9, C_DIM)
	var decision_text: String = ap.decision_log[0] if not ap.decision_log.is_empty() else "awaiting decision"
	draw_string(font, Vector2(text_x, detail_y + (0.0 if compact else 12.0)),
		"AI: %s" % decision_text,
		HORIZONTAL_ALIGNMENT_LEFT, text_w, 8 if micro else 9, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.84))

func _draw_portrait(rect: Rect2, role: String) -> void:
	draw_rect(rect, Color(0.01, 0.03, 0.07, 0.97))
	draw_rect(rect, Color(1, 1, 1, 0.06), false)
	var cx: float  = rect.position.x + rect.size.x * 0.5
	var cy: float  = rect.position.y + rect.size.y * 0.5 + 4.0
	var col: Color = _role_color(role)
	draw_circle(Vector2(cx, cy + 18.0), 14.0, Color(col.r, col.g, col.b, 0.18))
	draw_rect(Rect2(cx - 12.0, cy - 2.0, 24.0, 24.0), col)
	draw_rect(Rect2(cx - 10.0, cy + 20.0, 8.0, 10.0), Color(0.08, 0.08, 0.10))
	draw_rect(Rect2(cx + 2.0,  cy + 20.0, 8.0, 10.0), Color(0.08, 0.08, 0.10))
	var skin: Color = Color(0.78, 0.55, 0.36)
	if role == "sneaky_blue":
		skin = Color(0.76, 0.66, 0.48)
	elif role == "police":
		skin = Color(0.80, 0.56, 0.34)
	draw_circle(Vector2(cx, cy - 12.0), 10.0, skin)
	var hair: Color = Color(0.16, 0.10, 0.06)
	if role == "police":
		hair = Color(0.10, 0.06, 0.03)
	draw_rect(Rect2(cx - 10.0, cy - 20.0, 20.0, 8.0), hair)
	if role == "police":
		draw_rect(Rect2(cx - 14.0, cy - 7.0, 28.0, 4.0), Color(0.08, 0.12, 0.18))
	if role == "rusher_red":
		draw_string(ThemeDB.fallback_font, Vector2(cx - 6.0, cy + 13.0),
			"47", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.86))

# ─── Sector status ────────────────────────────────────────────────────────────
func _draw_sector_status(rect: Rect2, font: Font) -> void:
	if font == null:
		return
	var compact: bool = rect.size.y < 190.0
	var row_step: float = 28.0 if compact else 34.0
	var bar_h: float = 9.0 if compact else 11.0
	var k9_label: String = "OFFLINE"
	if _sim != null and _sim._dog_npc != null:
		k9_label = _sim._dog_npc.get_state_name()
	var k9_fill: float = 1.0 if (_sim != null and _sim._dog_npc != null) else 0.0

	var sectors: Array = [
		["EXIT ROTATOR",   _countdown / maxf(1.0, _countdown + 6.0),
			C_YELLOW, "%.1fs" % _countdown],
		["3-CAMERA GRID", clampf(float(_camera_states.size()) / 3.0, 0.2, 1.0),
			C_GREEN,  "3 online" if _camera_states.size() >= 3 else "%d online" % _camera_states.size()],
		["HAZARD CONTAIN", clampf(1.0 - float(_fire_count()) * 0.10, 0.12, 1.0),
			C_RED,    "%d fires" % _fire_count()],
		["K9 RESPONSE",    k9_fill,
			Color(0.55, 0.76, 0.94), k9_label],
	]
	var y: float = rect.position.y + 4.0
	for sec in sectors:
		var sc: Color = sec[2]
		# Indicator dot
		draw_circle(Vector2(rect.position.x + 5.0, y - 4.0), 3.5, sc)
		draw_circle(Vector2(rect.position.x + 5.0, y - 4.0), 2.0,
			Color(sc.r, sc.g, sc.b, 0.40))
		draw_string(font, Vector2(rect.position.x + 14.0, y),
			str(sec[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)
		draw_string(font, Vector2(rect.end.x - 76.0, y),
			str(sec[3]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, sc)
		# Progress bar with chevron pattern
		var bar: Rect2   = Rect2(rect.position.x, y + 7.0, rect.size.x, bar_h)
		var fill_w: float = bar.size.x * float(sec[1])
		draw_rect(bar, Color(0.04, 0.07, 0.11, 1.0))
		draw_rect(Rect2(bar.position, Vector2(fill_w, bar.size.y)),
			Color(sc.r, sc.g, sc.b, 0.85))
		for i in range(0, int(fill_w), 12):
			draw_line(
				Vector2(bar.position.x + float(i),       bar.position.y),
				Vector2(bar.position.x + float(i) + 8.0, bar.end.y),
				Color(1, 1, 1, 0.08), 1.0)
		draw_rect(bar, Color(1, 1, 1, 0.06), false)
		y += row_step

	if _dog_lock_agent_id >= 0 and _dog_lock_ticks > 0 and y + 42.0 <= rect.end.y:
		var lock_rect := Rect2(rect.position.x, y + 2.0, rect.size.x, 38.0)
		draw_rect(lock_rect, Color(0.20, 0.06, 0.02, 0.86))
		draw_rect(lock_rect, Color(1.00, 0.45, 0.20, 0.45), false)
		draw_circle(lock_rect.position + Vector2(8.0, 10.0), 3.0, Color(1.00, 0.54, 0.22))
		draw_string(font, lock_rect.position + Vector2(16.0, 13.0),
			"K9 LOCKED: %s" % _role_name_from_id(_dog_lock_agent_id),
			HORIZONTAL_ALIGNMENT_LEFT, lock_rect.size.x - 20.0, 10, Color(1.00, 0.74, 0.58))
		draw_string(font, lock_rect.position + Vector2(16.0, 28.0),
			"Slow active %.1fs" % (float(_dog_lock_ticks) * 0.25),
			HORIZONTAL_ALIGNMENT_LEFT, lock_rect.size.x - 20.0, 10, Color(1.00, 0.90, 0.76))
		y += 42.0

	# Active routing note with sweep animation
	var note_h: float = 44.0
	if _sim != null and y + note_h + 4.0 <= rect.end.y:
		var note_y: float = rect.end.y - note_h + 4.0
		draw_rect(Rect2(rect.position.x, note_y - 6.0, rect.size.x, 50.0),
			Color(C_GREEN.r, C_GREEN.g, C_GREEN.b, 0.04))
		draw_rect(Rect2(rect.position.x, note_y - 6.0, rect.size.x, 1.0),
			Color(C_GREEN.r, C_GREEN.g, C_GREEN.b, 0.15))
		var rshim: float = fposmod(_ui_pulse * 180.0, rect.size.x + 60.0) - 30.0
		draw_rect(Rect2(rect.position.x + rshim, note_y - 6.0, 30.0, 50.0),
			Color(C_GREEN.r, C_GREEN.g, C_GREEN.b, 0.03))
		draw_string(font, Vector2(rect.position.x, note_y),
			"ACTIVE ROUTING", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_GREEN)
		draw_string(font, Vector2(rect.position.x, note_y + 15.0),
			"3 live feed panels engaged",
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 10, C_TEXT)
		draw_string(font, Vector2(rect.position.x, note_y + 30.0),
			"3-camera detection grid active",
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 9, C_DIM)

# ─── Activity / incident log ──────────────────────────────────────────────────
func _draw_activity_panel(rect: Rect2, font: Font) -> void:
	if font == null:
		return
	var y: float = rect.position.y + 5.0
	var row_h: float = 26.0 if rect.size.y < 220.0 else 29.0
	var max_rows: int = maxi(1, int(floor((rect.size.y - 4.0) / row_h)))
	for i in range(mini(_activity_log.size(), max_rows)):
		var item: Dictionary = _activity_log[i]
		var age:    float = maxf(0.0, _ui_pulse - float(item.get("born", _ui_pulse)))
		var appear: float = clampf(age * 6.0, 0.0, 1.0)
		var eased:  float = appear * appear * (3.0 - 2.0 * appear)
		var kind:   String = str(item.get("kind", "info"))
		var col:    Color  = C_CYAN
		if kind == "alert":
			col = C_RED
		elif kind == "warning":
			col = C_YELLOW
		var fade: float = (1.0 - float(i) * 0.07) * eased
		var row: Rect2  = Rect2(rect.position.x + (1.0 - eased) * 14.0, y, rect.size.x, row_h - 2.0)
		draw_rect(row, Color(0.02, 0.05, 0.10, 0.92 * fade))
		draw_rect(Rect2(row.position.x, row.position.y, 3.0, row.size.y), col)
		draw_rect(Rect2(row.position.x + 4.0, row.position.y + 1.0,
			row.size.x - 4.0, row.size.y - 2.0),
			Color(col.r, col.g, col.b, 0.055 * fade))
		draw_string(font, row.position + Vector2(9.0, 14.0),
			"T%03d" % int(item.get("tick", 0)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(C_DIM.r, C_DIM.g, C_DIM.b, fade))
		draw_string(font, row.position + Vector2(54.0, 14.0),
			str(item.get("text", "")),
			HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 60.0, 10,
			Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, fade))
		y += row_h

# ─── Threat gauge ─────────────────────────────────────────────────────────────
func _draw_threat_panel(rect: Rect2, font: Font) -> void:
	var threat: float = _display_threat
	var compact: bool = rect.size.y < 150.0
	var cx: float     = rect.position.x + rect.size.x * 0.5
	var cy: float     = rect.position.y + rect.size.y * (0.44 if compact else 0.48)
	var r:  float     = minf(48.0 if compact else 54.0, minf(rect.size.x * 0.26, rect.size.y * (0.24 if compact else 0.30)))

	# Background arc
	draw_arc(Vector2(cx, cy), r, PI * 0.75, PI * 2.25, 48,
		Color(0.12, 0.20, 0.30, 0.95), 12.0)

	# Coloured threat arc (green → yellow → red)
	var end_ang: float = PI * 0.75 + PI * 1.5 * threat
	var seg:     int   = 42
	for i in range(seg):
		var t0: float = float(i)     / float(seg)
		var t1: float = float(i + 1) / float(seg)
		var a0: float = PI * 0.75 + (end_ang - PI * 0.75) * t0
		var a1: float = PI * 0.75 + (end_ang - PI * 0.75) * t1
		var col: Color = C_GREEN \
			.lerp(C_YELLOW, minf(t1 * 1.8, 1.0)) \
			.lerp(C_RED, maxf((t1 - 0.5) * 2.0, 0.0))
		draw_arc(Vector2(cx, cy), r, a0, a1, 2, col, 12.0)

	# Tick marks
	for i in range(11):
		var a:       float = PI * 0.75 + PI * 1.5 * float(i) / 10.0
		var inner_r: float = r - 18.0
		var outer_r: float = r - (7.0 if i % 5 == 0 else 12.0)
		draw_line(
			Vector2(cx, cy) + Vector2(cos(a), sin(a)) * inner_r,
			Vector2(cx, cy) + Vector2(cos(a), sin(a)) * outer_r,
			Color(0.50, 0.62, 0.72, 0.55), 1.0)

	# Bloom glow on high threat
	if threat > 0.65:
		var glow_a: float = (threat - 0.65) * 0.20 * (0.6 + 0.4 * sin(_ui_pulse * 4.0))
		draw_circle(Vector2(cx, cy), r + 12.0,
			Color(C_RED.r, C_RED.g, C_RED.b, glow_a))

	if font != null:
		var tc: Color = C_RED.lerp(C_YELLOW, 1.0 - threat)
		draw_string(font, Vector2(cx - 20.0, cy - 8.0),
			"%d" % int(threat * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 22 if compact else 26, tc)
		draw_string(font, Vector2(cx - 36.0, cy + 14.0),
			"THREAT %", HORIZONTAL_ALIGNMENT_LEFT, -1, 9 if compact else 10, C_DIM)
		draw_string(font, Vector2(rect.position.x + 6.0, rect.end.y - 22.0),
			_threat_label(threat), HORIZONTAL_ALIGNMENT_LEFT, -1, 9 if compact else 10, C_TEXT)
		draw_string(font, Vector2(rect.position.x + 6.0, rect.end.y - 8.0),
			"Visible targets %d   ·   Cameras hot %d" % [
				_visible_target_count(), _hot_camera_count()],
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8.0, 8 if compact else 9, C_DIM)

# ─── Legend ───────────────────────────────────────────────────────────────────
func _draw_legend_panel(rect: Rect2, font: Font) -> void:
	if font == null:
		return
	var items: Array = [
		[Color(0.12, 0.18, 0.25), "Wall tile"],
		[Color(0.17, 0.24, 0.33), "Floor tile"],
		[C_YELLOW,                "Police hunter"],
		[Color(0.18, 0.74, 0.92), "Sneaky Blue"],
		[C_ORANGE,                "Rusher Red"],
		[C_GREEN,                 "CCTV sweep"],
	]
	var y: float = rect.position.y + 4.0
	for item in items:
		var ic: Color = item[0]
		draw_rect(Rect2(rect.position.x, y - 8.0, 10.0, 10.0), ic)
		draw_rect(Rect2(rect.position.x, y - 8.0, 10.0, 10.0), Color(1, 1, 1, 0.12), false)
		draw_string(font, Vector2(rect.position.x + 16.0, y),
			str(item[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_TEXT)
		y += 16.0

# ─── System status ────────────────────────────────────────────────────────────
func _draw_system_panel(rect: Rect2, font: Font) -> void:
	if font == null:
		return
	var bars: Array = [
		["DETECTION GRID", float(_system_levels.get("detection", 0.0)), C_GREEN],
		["COMM NETWORK",   float(_system_levels.get("comm",      0.92)), C_GREEN],
		["LOCK SYSTEMS",   float(_system_levels.get("locks",     0.85)), C_YELLOW],
		["GUARD RESPONSE", float(_system_levels.get("response",  0.35)), C_RED],
	]
	var y: float = rect.position.y + 4.0
	for idx in range(bars.size()):
		var bar_data: Array = bars[idx]
		draw_string(font, Vector2(rect.position.x, y),
			str(bar_data[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)
		var bar: Rect2    = Rect2(rect.position.x, y + 6.0, rect.size.x, 10.0)
		var bc: Color     = bar_data[2]
		var fill_w: float = bar.size.x * float(bar_data[1])
		draw_rect(bar, Color(0.05, 0.08, 0.12))
		draw_rect(Rect2(bar.position, Vector2(fill_w, bar.size.y)),
			Color(bc.r, bc.g, bc.b, 0.85))
		# Moving shimmer on fill
		if fill_w > 0.0:
			var shim: float = fposmod(_ui_pulse * 160.0 + float(idx) * 40.0, fill_w + 30.0) - 15.0
			draw_rect(Rect2(bar.position.x + shim, bar.position.y, 15.0, bar.size.y),
				Color(1.0, 1.0, 1.0, 0.18))
		for i in range(0, int(fill_w), 12):
			draw_line(
				Vector2(bar.position.x + float(i),       bar.position.y),
				Vector2(bar.position.x + float(i) + 8.0, bar.end.y),
				Color(1, 1, 1, 0.08), 1.0)
		draw_rect(bar, Color(1, 1, 1, 0.06), false)
		# Critical pulse on low values
		if float(bar_data[1]) < 0.35:
			draw_rect(bar,
				Color(bc.r, bc.g, bc.b, 0.20 * (0.5 + 0.5 * sin(_ui_pulse * 4.0))), false)
		y += 28.0

	var cameras_live: int = mini(3, _camera_states.size())
	draw_string(font, Vector2(rect.position.x, rect.end.y - 38.0),
		"CAM PREVIEWS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_CYAN)
	draw_string(font, Vector2(rect.position.x, rect.end.y - 22.0),
		"%d live feed panels engaged" % cameras_live,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_TEXT)
	draw_string(font, Vector2(rect.position.x, rect.end.y - 8.0),
		"Wide layout — panels narrowed for max map coverage",
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 9, C_DIM)

# ─── Value bar ────────────────────────────────────────────────────────────────
func _draw_value_bar(
		pos: Vector2,
		width: float,
		value: float,
		max_value: float,
		color: Color,
		font: Font,
		label: String) -> void:
	draw_string(font, pos + Vector2(0.0, 8.0),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_DIM)
	var bar: Rect2 = Rect2(pos.x + 28.0, pos.y, width - 28.0, 10.0)
	draw_rect(bar, Color(0.05, 0.07, 0.10, 1.0))
	if max_value > 0.0:
		var fill_w: float = bar.size.x * clampf(value / max_value, 0.0, 1.0)
		draw_rect(Rect2(bar.position, Vector2(fill_w, bar.size.y)), color)
		for i in range(0, int(fill_w), 10):
			draw_line(
				Vector2(bar.position.x + float(i),      bar.position.y),
				Vector2(bar.position.x + float(i) + 7.0, bar.end.y),
				Color(1, 1, 1, 0.08), 1.0)
	draw_rect(bar, Color(1, 1, 1, 0.05), false)

func _draw_info_chip(rect: Rect2, label: String, value_text: String, accent: Color, font: Font) -> void:
	draw_rect(rect, Color(0.03, 0.06, 0.10, 0.95))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.36), false)
	draw_string(font, rect.position + Vector2(4.0, 9.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8.0, 8, C_DIM)
	draw_string(font, rect.position + Vector2(4.0, rect.size.y - 2.0), value_text,
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8.0, 9, Color(accent.r, accent.g, accent.b, 0.96))

# ─── Pure helpers ─────────────────────────────────────────────────────────────
func _role_counts() -> Dictionary:
	var counts: Dictionary = {"police": 0, "rusher_red": 0, "sneaky_blue": 0}
	for agent in _agents:
		var role: String = str(agent._role)
		counts[role] = int(counts.get(role, 0)) + 1
	return counts

func _active_entities_count() -> int:
	var total: int = 0
	for agent in _agents:
		if agent.is_active:
			total += 1
	if _sim != null and _sim._dog_npc != null:
		total += 1
	return total

func _fire_count() -> int:
	if _sim == null or _sim._fire_hazard == null:
		return 0
	return _sim._fire_hazard.get_fire_tiles().size()

func _visible_target_count() -> int:
	var count: int = 0
	for state in _camera_states:
		count += Array(state.get("visible_targets", [])).size()
	return count

func _hot_camera_count() -> int:
	var hot: int = 0
	for state in _camera_states:
		if not Array(state.get("visible_targets", [])).is_empty():
			hot += 1
	return hot

func _threat_level() -> float:
	var threat: float = 0.18
	threat += float(_hot_camera_count()) * 0.22
	threat += float(_fire_count()) * 0.08
	for ap in _panels:
		var p: AgentPanel = ap as AgentPanel
		if p.is_escaped:
			threat += 0.25
		elif p.role != "police" and p.is_active:
			threat += 0.06
		if p.camera_hits > 0:
			threat += 0.05
	return clampf(threat, 0.08, 0.99)

func _threat_label(v: float) -> String:
	if v >= 0.78:
		return "Critical prisoner movement detected"
	if v >= 0.56:
		return "Elevated surveillance pressure"
	return "Facility under controlled watch"

func _alert_banner_data() -> Dictionary:
	if _hot_camera_count() > 0:
		return {"text": "ESCAPE ALERT ACTIVE",    "color": C_RED}
	if _countdown < 6.0:
		return {"text": "EXIT ROTATION IMMINENT", "color": C_YELLOW}
	return {"text": "SURVEILLANCE NOMINAL", "color": C_CYAN}

func _tile_text(tile: Vector2i) -> String:
	return "(%d,%d)" % [tile.x, tile.y]

func _role_name_from_id(id: int) -> String:
	for agent in _agents:
		if agent.agent_id == id:
			return _short_role(agent._role)
	return "Agent %d" % id

func _short_role(role: String) -> String:
	match role:
		"rusher_red":  return "RED"
		"sneaky_blue": return "BLUE"
		"police":      return "HUNTER"
		_:             return role.to_upper()

func _role_color(role: String) -> Color:
	match role:
		"rusher_red":  return Color(0.94, 0.27, 0.27)
		"sneaky_blue": return Color(0.18, 0.74, 0.92)
		"police":      return Color(1.0,  0.86, 0.24)
		_:             return Color.WHITE

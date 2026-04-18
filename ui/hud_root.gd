extends Node2D
class_name HudRoot

const LEFT_PANEL_W: float = 292.0
const RIGHT_PANEL_W: float = 292.0
const HEADER_H: float = 72.0
const PANEL_PAD: float = 12.0
const TILE_SIZE: float = 48.0

const C_BG_DEEP := Color(0.02, 0.03, 0.06, 0.90)
const C_BG_PANEL := Color(0.05, 0.08, 0.14, 0.96)
const C_PANEL_INNER := Color(0.06, 0.10, 0.17, 0.98)
const C_BORDER := Color(0.10, 0.22, 0.36, 1.0)
const C_BORDER_GLOW := Color(0.16, 0.42, 0.65, 0.55)
const C_CYAN := Color(0.00, 0.90, 1.00)
const C_ORANGE := Color(1.00, 0.43, 0.00)
const C_RED := Color(1.00, 0.12, 0.28)
const C_GREEN := Color(0.00, 0.90, 0.45)
const C_YELLOW := Color(1.00, 0.84, 0.25)
const C_TEXT := Color(0.82, 0.91, 1.00)
const C_DIM := Color(0.32, 0.50, 0.65)
const C_SOFT := Color(0.55, 0.75, 0.90, 0.30)

var _panels: Array = []
var _agents: Array = []
var _exit_rotator: ExitRotator = null
var _sim: SimulationLoop = null
var _camera_system: CCTVCameraSystem = null

var _active_exit: Vector2i = Vector2i(-1, -1)
var _countdown: float = 0.0
var _tick: int = 0
var _camera_states: Array = []
var _cycle_summaries: Array = []
var _activity_log: Array = []
var _ui_pulse: float = 0.0
var _display_threat: float = 0.18
var _system_levels: Dictionary = {
	"detection": 0.0,
	"comm": 0.92,
	"locks": 0.85,
	"response": 0.35,
}

func setup(agents: Array, exit_rotator: ExitRotator, sim: SimulationLoop = null, camera_system: CCTVCameraSystem = null) -> void:
	_agents = agents
	_exit_rotator = exit_rotator
	_sim = sim
	_camera_system = camera_system

	for agent in agents:
		var p: AgentPanel = AgentPanel.new()
		p.setup(agent)
		p.update_from_agent(agent)
		_panels.append(p)

	if exit_rotator != null:
		_active_exit = exit_rotator.get_active_exit()
		_countdown = exit_rotator.get_time_remaining()
	if _camera_system != null:
		_camera_states = _camera_system.get_camera_states()

	_push_activity("Surveillance command center online", "info")
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
	EventBus.agent_captured.connect(func(id): _push_activity("%s captured" % _role_name_from_id(id), "alert"))
	EventBus.agent_escaped.connect(func(id): _push_activity("%s escaped" % _role_name_from_id(id), "alert"))
	EventBus.agent_eliminated.connect(func(id): _push_activity("%s eliminated" % _role_name_from_id(id), "warning"))

func _process(delta: float) -> void:
	_countdown = maxf(0.0, _countdown - delta)
	_ui_pulse += delta
	var threat_target: float = _threat_level()
	_display_threat = lerpf(_display_threat, threat_target, minf(1.0, delta * 3.2))
	_system_levels["detection"] = lerpf(float(_system_levels.get("detection", 0.0)), clampf(float(_camera_states.size()) / 2.0, 0.0, 1.0), minf(1.0, delta * 4.0))
	_system_levels["comm"] = lerpf(float(_system_levels.get("comm", 0.92)), 0.92, minf(1.0, delta * 2.2))
	_system_levels["locks"] = lerpf(float(_system_levels.get("locks", 0.85)), 0.55 if _countdown > 0.0 else 0.85, minf(1.0, delta * 3.0))
	_system_levels["response"] = lerpf(float(_system_levels.get("response", 0.35)), clampf(0.35 + float(_hot_camera_count()) * 0.18, 0.25, 0.98), minf(1.0, delta * 3.0))
	for p in _panels:
		(p as AgentPanel).lerp_displays(delta)
	queue_redraw()

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
			ap.candidates.append({"pos": pos, "score": sc, "norm": (sc + max_abs) / (2.0 * max_abs), "chosen": pos == chosen_pos, "type": "mm"})
		ap.next_pos = chosen_pos
		ap.add_log("pick %s" % _tile_text(chosen_pos))
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
			ap.candidates.append({"pos": pos, "visits": v, "norm": float(v) / max_v, "chosen": pos == chosen_pos, "type": "mcts"})
		ap.next_pos = chosen_pos
		ap.add_log("%d sims → %s" % [root_visits, _tile_text(chosen_pos)])
		return

func _on_fuzzy_decision(id: int, _inputs: Dictionary, rules: Array, output: String, chosen_pos: Vector2i = Vector2i(-1, -1)) -> void:
	for p in _panels:
		var ap: AgentPanel = p as AgentPanel
		if ap.agent_id != id:
			continue
		ap.candidates.clear()
		ap.decision_kind = "Fuzzy"
		for i in range(mini(rules.size(), 3)):
			var r = rules[i]
			var rn: String = str(r.get("rule", "?"))
			var rs: float = float(r.get("strength", 0.0))
			ap.candidates.append({"rule": rn, "score": rs, "norm": rs, "chosen": rn == output, "type": "fuzzy"})
		ap.next_pos = chosen_pos
		ap.add_log("rule %s" % output)
		return

func _on_camera_detection(camera_id: int, agent_id: int, visible: bool, tile: Vector2i, _detail: Dictionary) -> void:
	if visible:
		_push_activity("CAM %d locked %s @ %s" % [camera_id + 1, _role_name_from_id(agent_id), _tile_text(tile)], "alert")
	else:
		_push_activity("CAM %d lost %s" % [camera_id + 1, _role_name_from_id(agent_id)], "info")

func _on_camera_sweep_updated(states: Array) -> void:
	_camera_states = states

func _on_cycle_summary_generated(summary: Dictionary) -> void:
	_cycle_summaries.append(summary)
	if _cycle_summaries.size() > 8:
		_cycle_summaries.pop_front()
	_push_activity("Cycle %d summary recorded" % int(summary.get("cycle_index", 0)), "info")

func _on_score_event(agent_id: int, delta: float, reason: String, _team: String) -> void:
	var role_name: String = _role_name_from_id(agent_id)
	var sign: String = "+" if delta >= 0.0 else ""
	var kind: String = "info"
	if delta < 0.0:
		kind = "warning"
	if reason == "first_escape" or reason == "second_escape" or reason == "full_containment_bonus":
		kind = "alert"
	_push_activity("%s %s%.1f (%s)" % [role_name, sign, delta, reason], kind)

func _push_activity(text: String, kind: String = "info") -> void:
	_activity_log.push_front({
		"tick": _tick,
		"text": text,
		"kind": kind,
		"born": _ui_pulse,
	})
	if _activity_log.size() > 14:
		_activity_log.resize(14)

func _draw() -> void:
	var vp: Rect2 = get_viewport_rect()
	var font: Font = ThemeDB.fallback_font
	_draw_screen_chrome(vp)
	_draw_header_bar(vp, font)
	_draw_map_toolbar(vp, font)
	_draw_left_column(vp, font)
	_draw_right_column(vp, font)

func _draw_screen_chrome(vp: Rect2) -> void:
	var center_rect := Rect2(LEFT_PANEL_W, HEADER_H, vp.size.x - LEFT_PANEL_W - RIGHT_PANEL_W, vp.size.y - HEADER_H)

	# Keep the gameplay viewport visible. Panels stay dense, center stays mostly transparent.
	draw_rect(Rect2(0.0, 0.0, LEFT_PANEL_W, vp.size.y), Color(0.02, 0.03, 0.06, 0.96))
	draw_rect(Rect2(vp.size.x - RIGHT_PANEL_W, 0.0, RIGHT_PANEL_W, vp.size.y), Color(0.02, 0.03, 0.06, 0.96))
	draw_rect(Rect2(0.0, 0.0, vp.size.x, HEADER_H), Color(0.02, 0.05, 0.09, 0.98))

	# Transparent center treatment: subtle HUD glass, not a blackout layer.
	draw_rect(center_rect, Color(0.00, 0.02, 0.04, 0.035))
	for i in range(6):
		var alpha: float = 0.026 - float(i) * 0.003
		if alpha <= 0.0:
			continue
		draw_rect(Rect2(float(i) * 18.0, float(i) * 18.0, vp.size.x - float(i) * 36.0, vp.size.y - float(i) * 36.0), Color(0.06, 0.12, 0.18, alpha), false)

	for x in range(int(center_rect.position.x), int(center_rect.end.x), 48):
		draw_line(Vector2(float(x), center_rect.position.y), Vector2(float(x), vp.size.y), Color(0.10, 0.28, 0.42, 0.020), 1.0)
	for y in range(int(center_rect.position.y), int(vp.size.y), 48):
		draw_line(Vector2(center_rect.position.x, float(y)), Vector2(center_rect.end.x, float(y)), Color(0.10, 0.28, 0.42, 0.018), 1.0)

	var scan_y: float = center_rect.position.y + fposmod(_ui_pulse * 42.0, center_rect.size.y + 180.0) - 90.0
	draw_rect(Rect2(center_rect.position.x, scan_y, center_rect.size.x, 2.0), Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.028))
	draw_rect(Rect2(center_rect.position.x, scan_y + 2.0, center_rect.size.x, 7.0), Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.010))

	draw_rect(Rect2(0.0, HEADER_H - 2.0, vp.size.x, 2.0), Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.16))
	draw_line(Vector2(LEFT_PANEL_W, 0.0), Vector2(LEFT_PANEL_W, vp.size.y), Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.12), 1.0)
	draw_line(Vector2(vp.size.x - RIGHT_PANEL_W, 0.0), Vector2(vp.size.x - RIGHT_PANEL_W, vp.size.y), Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.12), 1.0)
	_draw_corner_brackets(center_rect, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.35))

	var well_a := Vector2(center_rect.position.x + center_rect.size.x * 0.50, center_rect.position.y + center_rect.size.y * 0.42)
	for i in range(5):
		draw_circle(well_a, 220.0 - float(i) * 32.0, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.005 - float(i) * 0.0006))
	var well_b := Vector2(center_rect.position.x + center_rect.size.x * 0.86, center_rect.position.y + center_rect.size.y * 0.76)
	for i in range(4):
		draw_circle(well_b, 120.0 - float(i) * 18.0, Color(C_ORANGE.r, C_ORANGE.g, C_ORANGE.b, 0.005 - float(i) * 0.0007))

func _draw_header_bar(vp: Rect2, font: Font) -> void:
	if font == null:
		return
	var pulse: float = 0.5 + 0.5 * sin(_ui_pulse * 2.0)

	var logo_rect: Rect2 = Rect2(18.0, 14.0, 54.0, 42.0)
	draw_rect(logo_rect, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.10 + pulse * 0.03))
	draw_rect(logo_rect, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.34), false)
	draw_rect(Rect2(logo_rect.position + Vector2(4.0, 4.0), logo_rect.size - Vector2(8.0, 8.0)), Color(0.04, 0.10, 0.18, 0.95))
	draw_string(font, logo_rect.position + Vector2(16.0, 27.0), "PB", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_CYAN)

	var title_pos: Vector2 = Vector2(84.0, 29.0)
	draw_string(font, title_pos + Vector2(0.0, 4.0), "PRISON BREAK", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.20 + pulse * 0.10))
	draw_string(font, title_pos, "PRISON BREAK", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.95, 0.99, 1.0))
	draw_string(font, Vector2(84.0, 51.0), "SURVEILLANCE COMMAND CENTER — MAXIMUM SECURITY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_DIM)

	var counts: Dictionary = _role_counts()
	var stat_w: float = 78.0
	var start_x: float = vp.size.x * 0.5 - stat_w * 1.5 - 16.0
	var colors: Array = [C_YELLOW, Color(0.31, 0.76, 0.97), C_ORANGE]
	var labels: Array = ["OFFICERS", "BLUE", "RED"]
	var values: Array = [counts.get("police", 0), counts.get("sneaky_blue", 0), counts.get("rusher_red", 0)]
	for i in range(3):
		var r: Rect2 = Rect2(start_x + float(i) * (stat_w + 12.0), 16.0, stat_w, 40.0)
		draw_rect(Rect2(r.position + Vector2(3.0, 4.0), r.size), Color(0.0, 0.0, 0.0, 0.22))
		draw_rect(r, Color(colors[i].r, colors[i].g, colors[i].b, 0.10))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 4.0)), Color(colors[i].r, colors[i].g, colors[i].b, 0.26))
		draw_rect(r, Color(colors[i].r, colors[i].g, colors[i].b, 0.28 + pulse * 0.04), false)
		draw_string(font, r.position + Vector2(8.0, 15.0), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_DIM)
		draw_string(font, r.position + Vector2(8.0, 31.0), str(values[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, colors[i])

	var alert: Dictionary = _alert_banner_data()
	var alert_text: String = str(alert.get("text", "SURVEILLANCE NOMINAL"))
	var alert_color: Color = alert.get("color", C_CYAN)
	var alert_rect: Rect2 = Rect2(vp.size.x - 500.0, 16.0, 274.0, 36.0)
	draw_rect(alert_rect, Color(alert_color.r, alert_color.g, alert_color.b, 0.09 + pulse * 0.05))
	draw_rect(Rect2(alert_rect.position, Vector2(alert_rect.size.x, 4.0)), Color(alert_color.r, alert_color.g, alert_color.b, 0.26))
	draw_rect(alert_rect, Color(alert_color.r, alert_color.g, alert_color.b, 0.55), false)
	draw_string(font, alert_rect.position + Vector2(12.0, 23.0), alert_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, alert_color)

	var tick_rect: Rect2 = Rect2(vp.size.x - 208.0, 14.0, 186.0, 40.0)
	draw_rect(tick_rect, Color(0.00, 0.00, 0.00, 0.28))
	draw_rect(Rect2(tick_rect.position, Vector2(tick_rect.size.x, 4.0)), Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.20))
	draw_rect(tick_rect, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.32), false)
	draw_string(font, tick_rect.position + Vector2(12.0, 15.0), "TICK / EXIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_DIM)
	draw_string(font, tick_rect.position + Vector2(12.0, 31.0), "%03d   ·   %s" % [_tick, _tile_text(_active_exit)], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_CYAN)

func _draw_map_toolbar(vp: Rect2, font: Font) -> void:
	if font == null:
		return
	var rect: Rect2 = Rect2(LEFT_PANEL_W + 12.0, HEADER_H + 8.0, vp.size.x - LEFT_PANEL_W - RIGHT_PANEL_W - 24.0, 36.0)
	draw_rect(rect, Color(0.02, 0.06, 0.10, 0.92))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4.0)), Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.18))
	draw_rect(rect, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.18), false)

	var buttons: Array = [
		["LIVE FEED", true],
		["HEAT MAP", false],
		["PATROL ROUTES", false],
		["ALERTS", false],
	]
	var bx: float = rect.position.x + 10.0
	for b in buttons:
		var w: float = 112.0 if str(b[0]).length() > 8 else 88.0
		var br: Rect2 = Rect2(bx, rect.position.y + 6.0, w, 24.0)
		var active: bool = bool(b[1])
		var col: Color = C_CYAN if active else C_DIM
		draw_rect(br, Color(col.r, col.g, col.b, 0.10))
		draw_rect(Rect2(br.position, Vector2(br.size.x, 3.0)), Color(col.r, col.g, col.b, 0.22))
		draw_rect(br, Color(col.r, col.g, col.b, 0.28), false)
		draw_string(font, br.position + Vector2(10.0, 16.0), str(b[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		bx += w + 8.0
	var info: String = "TRACKING %d ENTITIES   ·   ACTIVE EXIT %s" % [_active_entities_count(), _tile_text(_active_exit)]
	draw_string(font, Vector2(rect.end.x - 286.0, rect.position.y + 20.0), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)

func _draw_left_column(vp: Rect2, font: Font) -> void:
	var x: float = PANEL_PAD
	var y: float = HEADER_H + PANEL_PAD
	var w: float = LEFT_PANEL_W - PANEL_PAD * 2.0

	var cam_h: float = 332.0
	_draw_panel_shell(Rect2(x, y, w, cam_h), "CC CAMERAS", C_CYAN, font)
	_draw_camera_stack(Rect2(x + 10.0, y + 36.0, w - 20.0, cam_h - 46.0), font)
	y += cam_h + 12.0

	var agents_h: float = 334.0
	_draw_panel_shell(Rect2(x, y, w, agents_h), "AGENTS ON MAP", C_ORANGE, font)
	_draw_agent_stack(Rect2(x + 10.0, y + 36.0, w - 20.0, agents_h - 46.0), font)
	y += agents_h + 12.0

	var status_h: float = vp.size.y - y - PANEL_PAD
	_draw_panel_shell(Rect2(x, y, w, status_h), "SECTOR STATUS", C_GREEN, font)
	_draw_sector_status(Rect2(x + 12.0, y + 36.0, w - 24.0, status_h - 46.0), font)

func _draw_right_column(vp: Rect2, font: Font) -> void:
	var x: float = vp.size.x - RIGHT_PANEL_W + PANEL_PAD
	var y: float = HEADER_H + PANEL_PAD
	var w: float = RIGHT_PANEL_W - PANEL_PAD * 2.0

	var log_h: float = 328.0
	_draw_panel_shell(Rect2(x, y, w, log_h), "INCIDENT LOG", C_RED, font)
	_draw_activity_panel(Rect2(x + 10.0, y + 36.0, w - 20.0, log_h - 46.0), font)
	y += log_h + 12.0

	var threat_h: float = 212.0
	_draw_panel_shell(Rect2(x, y, w, threat_h), "THREAT LEVEL", C_YELLOW, font)
	_draw_threat_panel(Rect2(x + 10.0, y + 34.0, w - 20.0, threat_h - 44.0), font)
	y += threat_h + 12.0

	var legend_h: float = 146.0
	_draw_panel_shell(Rect2(x, y, w, legend_h), "MAP LEGEND", C_CYAN, font)
	_draw_legend_panel(Rect2(x + 12.0, y + 36.0, w - 24.0, legend_h - 46.0), font)
	y += legend_h + 12.0

	var sys_h: float = vp.size.y - y - PANEL_PAD
	_draw_panel_shell(Rect2(x, y, w, sys_h), "SYSTEM STATUS", C_GREEN, font)
	_draw_system_panel(Rect2(x + 12.0, y + 36.0, w - 24.0, sys_h - 46.0), font)

func _draw_panel_shell(rect: Rect2, title: String, accent: Color, font: Font) -> void:
	draw_rect(Rect2(rect.position + Vector2(6.0, 8.0), rect.size), Color(0, 0, 0, 0.34))
	draw_rect(rect, C_BG_PANEL)
	draw_rect(Rect2(rect.position + Vector2(1.0, 1.0), rect.size - Vector2(2.0, 2.0)), C_PANEL_INNER)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 5.0)), Color(accent.r, accent.g, accent.b, 0.24))
	draw_rect(Rect2(rect.position + Vector2(4.0, 34.0), Vector2(rect.size.x - 8.0, 1.0)), Color(accent.r, accent.g, accent.b, 0.18))
	draw_rect(rect, Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.72), false)
	_draw_corner_brackets(rect, accent)
	for i in range(3):
		draw_rect(Rect2(rect.position - Vector2(float(i), float(i)), rect.size + Vector2(float(i) * 2.0, float(i) * 2.0)), Color(accent.r, accent.g, accent.b, 0.02 - float(i) * 0.005), false)
	if font != null:
		draw_circle(rect.position + Vector2(14.0, 17.0), 3.0, accent)
		draw_string(font, rect.position + Vector2(24.0, 20.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, accent)

func _draw_corner_brackets(rect: Rect2, accent: Color) -> void:
	var arm: float = 12.0
	draw_line(rect.position, rect.position + Vector2(arm, 0.0), accent, 1.0)
	draw_line(rect.position, rect.position + Vector2(0.0, arm), accent, 1.0)
	draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x - arm, rect.position.y), accent, 1.0)
	draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.position.y + arm), accent, 1.0)
	draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x + arm, rect.end.y), accent, 1.0)
	draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x, rect.end.y - arm), accent, 1.0)
	draw_line(rect.end, rect.end - Vector2(arm, 0.0), accent, 1.0)
	draw_line(rect.end, rect.end - Vector2(0.0, arm), accent, 1.0)

func _draw_camera_stack(rect: Rect2, font: Font) -> void:
	var feed_h: float = (rect.size.y - 10.0) * 0.5 - 4.0
	for i in range(2):
		var feed_rect: Rect2 = Rect2(rect.position.x, rect.position.y + float(i) * (feed_h + 10.0), rect.size.x, feed_h)
		var state: Dictionary = _camera_states[i] if i < _camera_states.size() else {}
		_draw_camera_preview(feed_rect, state, i, font)

func _draw_camera_preview(rect: Rect2, state: Dictionary, index: int, font: Font) -> void:
	var accent: Color = C_GREEN if Array(state.get("visible_targets", [])).is_empty() else C_RED
	draw_rect(rect, Color(0.00, 0.01, 0.01, 0.92))
	draw_rect(Rect2(rect.position + Vector2(2.0, 2.0), rect.size - Vector2(4.0, 4.0)), Color(C_GREEN.r, C_GREEN.g, C_GREEN.b, 0.05))
	draw_rect(rect, Color(C_GREEN.r, C_GREEN.g, C_GREEN.b, 0.14), false)
	var inner: Rect2 = rect.grow(-6.0)
	draw_rect(inner, Color(0.00, 0.04, 0.03, 0.95))
	_draw_preview_scene(inner, state)

	for y in range(int(inner.position.y), int(inner.end.y), 4):
		draw_line(Vector2(inner.position.x, float(y)), Vector2(inner.end.x, float(y)), Color(0, 0, 0, 0.10), 1.0)
	for i in range(36):
		var nx: float = inner.position.x + fposmod(float(i * 17) + _ui_pulse * 33.0, inner.size.x)
		var ny: float = inner.position.y + fposmod(float(i * 9) + _ui_pulse * 21.0, inner.size.y)
		draw_rect(Rect2(nx, ny, 1.0, 1.0), Color(1, 1, 1, 0.025))
	var scan_y: float = inner.position.y + fposmod(_ui_pulse * 44.0 + float(index) * 24.0, maxf(6.0, inner.size.y - 2.0))
	draw_rect(Rect2(inner.position.x, scan_y, inner.size.x, 2.0), Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.14))
	draw_rect(Rect2(inner.position.x, scan_y + 2.0, inner.size.x, 8.0), Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.03))

	if font != null:
		draw_rect(Rect2(rect.position.x + 8.0, rect.position.y + 8.0, 128.0, 16.0), Color(0, 0, 0, 0.54))
		draw_string(font, rect.position + Vector2(12.0, 20.0), "CAM-%02d / CCTV NODE" % (index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_GREEN)
		draw_rect(Rect2(rect.end.x - 56.0, rect.position.y + 8.0, 44.0, 16.0), Color(0, 0, 0, 0.54))
		draw_circle(Vector2(rect.end.x - 44.0, rect.position.y + 16.0), 3.0, accent)
		draw_string(font, rect.position + Vector2(rect.size.x - 35.0, 20.0), "REC", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, accent)
		draw_string(font, Vector2(rect.end.x - 126.0, rect.end.y - 8.0), "T%03d  %02d:%02d" % [_tick, int(fmod(_ui_pulse * 12.0, 60.0)), int(fmod(_ui_pulse * 60.0, 60.0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.42))

func _draw_preview_scene(rect: Rect2, state: Dictionary) -> void:
	if _sim == null or _sim._grid == null:
		return
	var cam_pos: Vector2i = state.get("pos", Vector2i(10, 10))
	var cam_facing: Vector2i = state.get("facing", Vector2i.RIGHT)
	var cam_range: int = int(state.get("range", 6))
	var cam_fov: float = float(state.get("fov_deg", 72.0))
	var visible_targets: Array = Array(state.get("visible_targets", []))
	var half_x: int = 3
	var half_y: int = 2
	var tile_px: float = floor(minf(rect.size.x / 7.0, rect.size.y / 5.0))
	var ox: float = rect.position.x + (rect.size.x - tile_px * 7.0) * 0.5
	var oy: float = rect.position.y + (rect.size.y - tile_px * 5.0) * 0.5

	for ty in range(-half_y, half_y + 1):
		for tx in range(-half_x, half_x + 1):
			var pos: Vector2i = cam_pos + Vector2i(tx, ty)
			var tile: GridTileData = _sim._grid.get_tile(pos)
			var rx: float = ox + float(tx + half_x) * tile_px
			var ry: float = oy + float(ty + half_y) * tile_px
			if tile == null:
				continue
			var visible_by_cam: bool = _preview_camera_sees_tile(cam_pos, cam_facing, cam_range, cam_fov, pos)
			var r: Rect2 = Rect2(rx, ry, tile_px, tile_px)
			if tile.walkable:
				var floor_col: Color = Color(0.02, 0.16, 0.10, 0.90) if ((pos.x + pos.y) % 2 == 0) else Color(0.03, 0.12, 0.08, 0.90)
				draw_rect(r, floor_col)
				draw_rect(Rect2(r.position, Vector2(r.size.x, 2.0)), Color(1, 1, 1, 0.05))
				draw_rect(r.grow(-1.0), Color(0.05, 0.24, 0.14, 0.18), false)
			else:
				draw_rect(r, Color(0.05, 0.10, 0.10, 1.0))
				draw_rect(Rect2(r.position, Vector2(r.size.x, 4.0)), Color(0.10, 0.20, 0.18), true)
				draw_rect(Rect2(r.position + Vector2(0.0, r.size.y - 4.0), Vector2(r.size.x, 4.0)), Color(0.01, 0.02, 0.02, 0.55), true)
			if not visible_by_cam:
				draw_rect(r, Color(0.0, 0.0, 0.0, 0.42))

	# Cinematic sweep beam aligned to camera facing
	var sweep_origin: Vector2 = Vector2(ox + (float(half_x) + 0.5) * tile_px, oy + (float(half_y) + 0.5) * tile_px)
	var base_ang: float = atan2(float(cam_facing.y), float(cam_facing.x))
	var wobble: float = sin(_ui_pulse * 1.8 + float(int(state.get("id", 0))) * 0.7) * 0.22
	var sweep_ang: float = base_ang + wobble
	var sweep_len: float = tile_px * float(mini(cam_range + 1, 5))
	draw_line(
		sweep_origin,
		sweep_origin + Vector2(cos(sweep_ang), sin(sweep_ang)) * sweep_len,
		Color(0.55, 1.0, 0.88, 0.42),
		2.0
	)
	draw_arc(sweep_origin, 7.0, 0.0, TAU, 14, Color(0.55, 1.0, 0.88, 0.28), 1.0)

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
		draw_rect(Rect2(fx + 1.0, fy + 1.0, tile_px - 2.0, tile_px - 2.0), Color(0.45, 0.08, 0.02, 0.62))
		draw_circle(Vector2(fx + tile_px * 0.5, fy + tile_px * 0.55), tile_px * 0.32, Color(1.0, 0.42, 0.08, 0.14))
		draw_colored_polygon(PackedVector2Array([
			Vector2(fx + tile_px * 0.18, fy + tile_px * 0.90),
			Vector2(fx + tile_px * 0.50, fy + tile_px * 0.16),
			Vector2(fx + tile_px * 0.80, fy + tile_px * 0.90),
		]), Color(1.00, 0.72, 0.16, 0.86))

	if _sim._dog_npc != null:
		var dp: Vector2i = _sim._dog_npc.grid_pos
		if absi(dp.x - cam_pos.x) <= half_x and absi(dp.y - cam_pos.y) <= half_y:
			if _preview_camera_sees_tile(cam_pos, cam_facing, cam_range, cam_fov, dp):
				var dx: float = ox + float(dp.x - cam_pos.x + half_x) * tile_px + tile_px * 0.5
				var dy: float = oy + float(dp.y - cam_pos.y + half_y) * tile_px + tile_px * 0.5
				draw_circle(Vector2(dx, dy), tile_px * 0.18, Color(0.85, 0.62, 0.30, 0.95))
				draw_circle(Vector2(dx + tile_px * 0.18, dy), tile_px * 0.08, Color(0.10, 0.08, 0.06))

	for agent in _agents:
		var pos: Vector2i = agent.grid_pos
		if absi(pos.x - cam_pos.x) > half_x or absi(pos.y - cam_pos.y) > half_y:
			continue
		if not _preview_camera_sees_tile(cam_pos, cam_facing, cam_range, cam_fov, pos):
			continue

		# Smooth movement in CCTV feed: use interpolated world-space position when available.
		var tile_xf: float = float(pos.x) + 0.5
		var tile_yf: float = float(pos.y) + 0.5
		if agent is Node2D:
			tile_xf = float(agent.position.x) / TILE_SIZE
			tile_yf = float(agent.position.y) / TILE_SIZE

		var ax: float = ox + (tile_xf - float(cam_pos.x) + float(half_x)) * tile_px
		var ay: float = oy + (tile_yf - float(cam_pos.y) + float(half_y)) * tile_px
		var col: Color = _role_color(agent._role)
		draw_circle(Vector2(ax, ay), tile_px * 0.22, col)
		_draw_ellipse(Vector2(ax, ay + tile_px * 0.20), Vector2(tile_px * 0.16, tile_px * 0.06), Color(0, 0, 0, 0.35))
		draw_circle(Vector2(ax, ay - tile_px * 0.13), tile_px * 0.08, Color(1, 1, 1, 0.85))
		if visible_targets.has(agent.agent_id):
			draw_rect(Rect2(ax - tile_px * 0.34, ay - tile_px * 0.48, tile_px * 0.68, tile_px * 0.86), Color(C_RED.r, C_RED.g, C_RED.b, 0.54), false)

func _preview_camera_sees_tile(cam_pos: Vector2i, facing: Vector2i, range_tiles: int, fov_deg: float, tile_pos: Vector2i) -> bool:
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
	var angle_deg: float = rad_to_deg(acos(clampf(f.normalized().dot(dir.normalized()), -1.0, 1.0)))
	return angle_deg <= fov_deg * 0.5

func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(16):
		var a := TAU * float(i) / 16.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, color)

func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _draw_agent_stack(rect: Rect2, font: Font) -> void:
	var card_h: float = 94.0
	for i in range(mini(_panels.size(), 3)):
		var r: Rect2 = Rect2(rect.position.x, rect.position.y + float(i) * (card_h + 8.0), rect.size.x, card_h)
		_draw_agent_card(_panels[i] as AgentPanel, r, font)

func _draw_agent_card(ap: AgentPanel, rect: Rect2, font: Font) -> void:
	var pulse: float = 0.5 + 0.5 * sin(_ui_pulse * 3.0 + float(ap.agent_id))
	draw_rect(rect, Color(0.03, 0.06, 0.12, 0.96))
	draw_rect(Rect2(rect.position + Vector2(2.0, 2.0), rect.size - Vector2(4.0, 4.0)), Color(ap.role_color.r, ap.role_color.g, ap.role_color.b, 0.04))
	draw_rect(Rect2(rect.position, Vector2(5.0, rect.size.y)), Color(ap.role_color.r, ap.role_color.g, ap.role_color.b, 0.82))
	draw_rect(rect, Color(ap.role_color.r, ap.role_color.g, ap.role_color.b, 0.22 + pulse * 0.05), false)

	var portrait: Rect2 = Rect2(rect.position.x + 8.0, rect.position.y + 8.0, 54.0, 68.0)
	_draw_portrait(portrait, ap.role)

	var status_col: Color = ap.role_color
	var status_text: String = "ACTIVE"
	if ap.is_eliminated:
		status_text = "ELIM"
		status_col = C_RED
	elif ap.is_escaped:
		status_text = "ESC"
		status_col = C_ORANGE
	elif not ap.is_active:
		status_text = "LOCKED"
		status_col = C_YELLOW

	draw_string(font, rect.position + Vector2(74.0, 22.0), ap.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ap.role_color)
	draw_string(font, rect.position + Vector2(74.0, 38.0), ap.ai_label + " controller", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)

	var badge: Rect2 = Rect2(rect.end.x - 90.0, rect.position.y + 10.0, 80.0, 18.0)
	draw_rect(badge, Color(status_col.r, status_col.g, status_col.b, 0.12 + pulse * 0.06))
	draw_rect(badge, Color(status_col.r, status_col.g, status_col.b, 0.32), false)
	draw_string(font, badge.position + Vector2(8.0, 13.0), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, status_col)

	_draw_value_bar(rect.position + Vector2(74.0, 46.0), rect.size.x - 154.0, ap.display_health, ap.max_health, Color(0.92, 0.23, 0.23), font, "HP")
	_draw_value_bar(rect.position + Vector2(74.0, 62.0), rect.size.x - 154.0, ap.display_stamina, ap.max_stamina, C_YELLOW, font, "STM")
	draw_string(font, rect.position + Vector2(74.0, 77.0), "SCORE %d  PERF %d" % [int(ap.raw_score), int(ap.performance_score)], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_TEXT)
	if ap.role == "police":
		draw_string(font, rect.position + Vector2(74.0, 86.0), "CAP %d  DOG %d  CCTV %d  FIRE %d  ESC %d" % [ap.captures_made, ap.dog_assists, ap.cctv_assists, ap.fire_assists, ap.escapes_allowed], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 84.0, 8, C_DIM)
	else:
		draw_string(font, rect.position + Vector2(74.0, 86.0), "STL %d  PROG %d  DOG %.1fs  CCTV %d  WALL %d" % [int(ap.stealth), ap.best_progress_cells, ap.dog_zone_time, ap.camera_hits, ap.wall_hits], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 84.0, 8, C_DIM)

	var chips: Array = [["CAP", str(ap.capture_count), C_YELLOW], ["CCTV", str(ap.camera_hits), C_CYAN], ["P", str(int(ap.performance_score)), ap.role_color]]
	var cx: float = rect.end.x - 90.0
	for i in range(chips.size()):
		var cr: Rect2 = Rect2(cx - 26.0 * float(2 - i), rect.position.y + 52.0, 24.0, 20.0)
		var cc: Color = chips[i][2]
		draw_rect(cr, Color(cc.r, cc.g, cc.b, 0.12))
		draw_rect(cr, Color(cc.r, cc.g, cc.b, 0.28), false)
		draw_string(font, cr.position + Vector2(4.0, 8.0), str(chips[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, C_DIM)
		draw_string(font, cr.position + Vector2(5.0, 17.0), str(chips[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, cc)

func _draw_portrait(rect: Rect2, role: String) -> void:
	draw_rect(rect, Color(0.01, 0.03, 0.07, 0.96))
	draw_rect(rect, Color(1, 1, 1, 0.06), false)
	var cx: float = rect.position.x + rect.size.x * 0.5
	var cy: float = rect.position.y + rect.size.y * 0.5 + 4.0
	var col: Color = _role_color(role)
	draw_circle(Vector2(cx, cy + 18.0), 14.0, Color(col.r, col.g, col.b, 0.18))
	draw_rect(Rect2(cx - 12.0, cy - 2.0, 24.0, 24.0), col)
	draw_rect(Rect2(cx - 10.0, cy + 20.0, 8.0, 10.0), Color(0.08, 0.08, 0.10))
	draw_rect(Rect2(cx + 2.0, cy + 20.0, 8.0, 10.0), Color(0.08, 0.08, 0.10))
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
		draw_string(ThemeDB.fallback_font, Vector2(cx - 6.0, cy + 13.0), "47", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1,1,1,0.86))

func _draw_sector_status(rect: Rect2, font: Font) -> void:
	if font == null:
		return
	var sectors: Array = [
		["EXIT ROTATOR", _countdown / maxf(1.0, _countdown + 6.0), C_YELLOW, "%.1fs" % _countdown],
		["DETECTION GRID", clampf(float(_camera_states.size()) / 2.0, 0.2, 1.0), C_GREEN, "%d online" % _camera_states.size()],
		["HAZARD CONTAINMENT", clampf(1.0 - float(_fire_count()) * 0.10, 0.12, 1.0), C_RED, "%d fires" % _fire_count()],
		["K9 RESPONSE", 1.0 if _sim != null and _sim._dog_npc != null else 0.0, Color(0.55, 0.76, 0.94), _sim._dog_npc.get_state_name() if _sim != null and _sim._dog_npc != null else "OFFLINE"],
	]
	var y: float = rect.position.y + 4.0
	for sec in sectors:
		draw_string(font, Vector2(rect.position.x, y), str(sec[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)
		draw_string(font, Vector2(rect.end.x - 90.0, y), str(sec[3]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, sec[2])
		var bar: Rect2 = Rect2(rect.position.x, y + 8.0, rect.size.x, 12.0)
		draw_rect(bar, Color(0.05, 0.08, 0.12, 1.0))
		var sec_color: Color = sec[2] as Color
		var fill_w: float = bar.size.x * float(sec[1])
		draw_rect(Rect2(bar.position, Vector2(fill_w, bar.size.y)), Color(sec_color.r, sec_color.g, sec_color.b, 0.85))
		for i in range(0, int(fill_w), 12):
			draw_line(Vector2(bar.position.x + float(i), bar.position.y), Vector2(bar.position.x + float(i) + 8.0, bar.end.y), Color(1, 1, 1, 0.08), 1.0)
		draw_rect(bar, Color(1, 1, 1, 0.06), false)
		y += 36.0
	if _sim != null:
		var note_y: float = rect.end.y - 52.0
		draw_string(font, Vector2(rect.position.x, note_y), "ACTIVE ROUTING", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_CYAN)
		draw_string(font, Vector2(rect.position.x, note_y + 16.0), "Map centered for widescreen command coverage", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 11, C_TEXT)
		draw_string(font, Vector2(rect.position.x, note_y + 34.0), "All logic preserved — visuals upgraded only", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 10, C_DIM)

func _draw_activity_panel(rect: Rect2, font: Font) -> void:
	if font == null:
		return
	var y: float = rect.position.y + 6.0
	for i in range(mini(_activity_log.size(), 10)):
		var item: Dictionary = _activity_log[i]
		var age: float = maxf(0.0, _ui_pulse - float(item.get("born", _ui_pulse)))
		var appear: float = clampf(age * 6.0, 0.0, 1.0)
		var eased: float = appear * appear * (3.0 - 2.0 * appear)
		var kind: String = str(item.get("kind", "info"))
		var col: Color = C_CYAN
		if kind == "alert":
			col = C_RED
		elif kind == "warning":
			col = C_YELLOW
		var row: Rect2 = Rect2(rect.position.x + (1.0 - eased) * 12.0, y, rect.size.x, 24.0)
		var fade: float = (1.0 - float(i) * 0.07) * eased
		draw_rect(row, Color(0.02, 0.05, 0.10, 0.90 * fade))
		draw_rect(Rect2(row.position.x, row.position.y, 3.0, row.size.y), col)
		draw_rect(Rect2(row.position.x + 4.0, row.position.y + 1.0, row.size.x - 4.0, row.size.y - 2.0), Color(col.r, col.g, col.b, 0.05 * fade))
		draw_string(font, row.position + Vector2(10.0, 15.0), "T%03d" % int(item.get("tick", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(C_DIM.r, C_DIM.g, C_DIM.b, fade))
		draw_string(font, row.position + Vector2(58.0, 15.0), str(item.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 64.0, 11, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, fade))
		y += 27.0

func _draw_threat_panel(rect: Rect2, font: Font) -> void:
	var threat: float = _display_threat
	var cx: float = rect.position.x + rect.size.x * 0.5
	var cy: float = rect.position.y + rect.size.y * 0.52
	var r: float = 58.0
	draw_arc(Vector2(cx, cy), r, PI * 0.75, PI * 2.25, 48, Color(0.14, 0.22, 0.32, 0.95), 12.0)
	var end_ang: float = PI * 0.75 + PI * 1.5 * threat
	var points: int = 40
	for i in range(points):
		var t0: float = float(i) / float(points)
		var t1: float = float(i + 1) / float(points)
		var a0: float = PI * 0.75 + (end_ang - PI * 0.75) * t0
		var a1: float = PI * 0.75 + (end_ang - PI * 0.75) * t1
		var mix: float = t1
		var col: Color = C_GREEN.lerp(C_YELLOW, minf(mix * 1.8, 1.0)).lerp(C_RED, maxf((mix - 0.5) * 2.0, 0.0))
		draw_arc(Vector2(cx, cy), r, a0, a1, 2, col, 12.0)
	for i in range(0, 11):
		var a: float = PI * 0.75 + PI * 1.5 * float(i) / 10.0
		var inner: float = r - 18.0
		var outer: float = r - (8.0 if i % 5 == 0 else 12.0)
		draw_line(Vector2(cx, cy) + Vector2(cos(a), sin(a)) * inner, Vector2(cx, cy) + Vector2(cos(a), sin(a)) * outer, Color(0.50, 0.62, 0.72, 0.50), 1.0)
	if font != null:
		draw_string(font, Vector2(cx - 22.0, cy - 10.0), "%d" % int(threat * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, C_RED.lerp(C_YELLOW, 1.0 - threat))
		draw_string(font, Vector2(cx - 38.0, cy + 14.0), "THREAT %", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)
		draw_string(font, Vector2(rect.position.x + 8.0, rect.end.y - 24.0), _threat_label(threat), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TEXT)
		draw_string(font, Vector2(rect.position.x + 8.0, rect.end.y - 10.0), "Visible targets %d   ·   Cameras hot %d" % [_visible_target_count(), _hot_camera_count()], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)

func _draw_legend_panel(rect: Rect2, font: Font) -> void:
	if font == null:
		return
	var items: Array = [
		[Color(0.12, 0.18, 0.25), "Wall tile"],
		[Color(0.17, 0.24, 0.33), "Floor tile"],
		[C_YELLOW, "Police hunter"],
		[Color(0.18, 0.74, 0.92), "Sneaky Blue"],
		[C_ORANGE, "Rusher Red"],
		[C_GREEN, "CCTV sweep"],
	]
	var y: float = rect.position.y + 4.0
	for item in items:
		draw_rect(Rect2(rect.position.x, y - 8.0, 10.0, 10.0), item[0])
		draw_string(font, Vector2(rect.position.x + 18.0, y), str(item[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_TEXT)
		y += 16.0

func _draw_system_panel(rect: Rect2, font: Font) -> void:
	if font == null:
		return
	var bars: Array = [
		["DETECTION GRID", float(_system_levels.get("detection", 0.0)), C_GREEN],
		["COMM NETWORK", float(_system_levels.get("comm", 0.92)), C_GREEN],
		["LOCK SYSTEMS", float(_system_levels.get("locks", 0.85)), C_YELLOW],
		["GUARD RESPONSE", float(_system_levels.get("response", 0.35)), C_RED],
	]
	var y: float = rect.position.y + 4.0
	for bar_data in bars:
		draw_string(font, Vector2(rect.position.x, y), str(bar_data[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)
		var bar: Rect2 = Rect2(rect.position.x, y + 7.0, rect.size.x, 10.0)
		draw_rect(bar, Color(0.06, 0.08, 0.12))
		var bar_color: Color = bar_data[2] as Color
		var fill_w: float = bar.size.x * float(bar_data[1])
		draw_rect(Rect2(bar.position, Vector2(fill_w, bar.size.y)), Color(bar_color.r, bar_color.g, bar_color.b, 0.85))
		for i in range(0, int(fill_w), 12):
			draw_line(Vector2(bar.position.x + float(i), bar.position.y), Vector2(bar.position.x + float(i) + 8.0, bar.end.y), Color(1, 1, 1, 0.08), 1.0)
		draw_rect(bar, Color(1, 1, 1, 0.06), false)
		y += 30.0
	var cameras_live: int = mini(2, _camera_states.size())
	draw_string(font, Vector2(rect.position.x, rect.end.y - 42.0), "CAM PREVIEWS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_CYAN)
	draw_string(font, Vector2(rect.position.x, rect.end.y - 26.0), "%d live feed panels engaged" % cameras_live, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TEXT)
	draw_string(font, Vector2(rect.position.x, rect.end.y - 10.0), "Wide layout mirrors the supplied surveillance UI", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 10, C_DIM)

func _draw_value_bar(pos: Vector2, width: float, value: float, max_value: float, color: Color, font: Font, label: String) -> void:
	draw_string(font, pos + Vector2(0.0, 8.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, C_DIM)
	var bar: Rect2 = Rect2(pos.x + 26.0, pos.y, width - 26.0, 8.0)
	draw_rect(bar, Color(0.05, 0.07, 0.10, 1.0))
	if max_value > 0.0:
		var fill: float = clampf(value / max_value, 0.0, 1.0)
		var fill_w: float = bar.size.x * fill
		draw_rect(Rect2(bar.position, Vector2(fill_w, bar.size.y)), color)
		for i in range(0, int(fill_w), 10):
			draw_line(Vector2(bar.position.x + float(i), bar.position.y), Vector2(bar.position.x + float(i) + 7.0, bar.end.y), Color(1, 1, 1, 0.08), 1.0)
	draw_rect(bar, Color(1, 1, 1, 0.05), false)

func _role_counts() -> Dictionary:
	var counts: Dictionary = {
		"police": 0,
		"rusher_red": 0,
		"sneaky_blue": 0,
	}
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
		return {"text": "ESCAPE ALERT ACTIVE", "color": C_RED}
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
		"rusher_red": return "RED"
		"sneaky_blue": return "BLUE"
		"police": return "HUNTER"
		_: return role.to_upper()

func _role_color(role: String) -> Color:
	match role:
		"rusher_red": return Color(0.94, 0.27, 0.27)
		"sneaky_blue": return Color(0.18, 0.74, 0.92)
		"police": return Color(1.0, 0.86, 0.24)
		_: return Color.WHITE

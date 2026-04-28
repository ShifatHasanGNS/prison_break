extends Node2D
class_name HudRoot

## Right-column HUD — drawn with _draw() only; zero ProgressBar / Label nodes.
## This Node2D is added as the sole child of a CanvasLayer (layer 5) created
## in main.gd, so all coordinates here are screen-space (origin = screen top-left).

# -------------------------------------------------------------------------
# Layout constants
# -------------------------------------------------------------------------

const PANEL_X   : float = 1560.0   # left edge of HUD column
const PANEL_W   : float = 360.0    # HUD column width
const PANEL_H   : float = 1080.0   # full screen height

const STRIP_H   : float = 36.0     # game-area top status strip height
const BANNER_H  : float = 72.0     # compact HUD header
const AGENT_H   : float = 288.0    # each agent panel
const AGENT_GAP : float = 12.0     # gap between panels
const START_Y   : float = BANNER_H + 12.0

# -------------------------------------------------------------------------
# Theme colours (matches CLAUDE.md)
# -------------------------------------------------------------------------

const C_BG           := Color(0.055, 0.078, 0.125)
const C_HIGHLIGHT    := Color(0.290, 0.855, 0.502)
const C_WARNING      := Color(0.984, 0.749, 0.141)
const C_PANEL_BG     := Color(0.055, 0.078, 0.125, 0.93)
const C_PANEL_BORDER := Color(0.0,   0.7,   1.0,   0.50)
const C_TEXT         := Color(0.88, 0.92, 0.94)
const C_DIM          := Color(0.52, 0.62, 0.68)
const C_HP           := Color(0.90, 0.20, 0.20)
const C_ST           := Color(0.90, 0.74, 0.12)

# -------------------------------------------------------------------------
# Runtime state
# -------------------------------------------------------------------------

var _panels       : Array          = []   # Array[AgentPanel]
var _agents       : Array          = []   # live Agent references
var _exit_rotator : ExitRotator    = null

var _active_exit  : Vector2i       = Vector2i(-1, -1)
var _countdown    : float          = 0.0
var _tick         : int            = 0

# -------------------------------------------------------------------------

func setup(agents: Array, exit_rotator: ExitRotator) -> void:
	_agents       = agents
	_exit_rotator = exit_rotator

	for agent in agents:
		var p := AgentPanel.new()
		p.setup(agent)
		p.update_from_agent(agent)
		_panels.append(p)

	# Seed initial exit / countdown
	if exit_rotator != null:
		_active_exit = exit_rotator.get_active_exit()
		_countdown   = exit_rotator.get_time_remaining()

	EventBus.agent_action_chosen.connect(_on_action_chosen)
	EventBus.tick_ended.connect(_on_tick_ended)
	EventBus.exit_activated.connect(_on_exit_activated)
	EventBus.minimax_decision.connect(_on_minimax_decision)
	EventBus.mcts_decision.connect(_on_mcts_decision)
	EventBus.fuzzy_decision.connect(_on_fuzzy_decision)

# -------------------------------------------------------------------------
# Lifecycle
# -------------------------------------------------------------------------

func _process(delta: float) -> void:
	_countdown = maxf(0.0, _countdown - delta)
	for p in _panels:
		(p as AgentPanel).lerp_displays(delta)
	queue_redraw()

# -------------------------------------------------------------------------
# EventBus callbacks
# -------------------------------------------------------------------------

func _on_action_chosen(id: int, action: String) -> void:
	for p in _panels:
		var ap := p as AgentPanel
		if ap.agent_id == id:
			ap.action_text = action
			return

func _on_tick_ended(n: int) -> void:
	_tick = n
	for i in range(_panels.size()):
		if i < _agents.size():
			(_panels[i] as AgentPanel).update_from_agent(_agents[i])

func _on_exit_activated(tile: Vector2i) -> void:
	_active_exit = tile
	if _exit_rotator != null:
		_countdown = _exit_rotator.get_time_remaining()

func _on_minimax_decision(id: int, candidates: Array, chosen: Dictionary) -> void:
	for p in _panels:
		var ap := p as AgentPanel
		if ap.agent_id != id:
			continue
		ap.candidates.clear()
		ap.decision_kind = "Minimax score"
		# Compute normalisation range (shift all scores to 0–1)
		var max_abs: float = 0.1
		for c in candidates:
			max_abs = maxf(max_abs, absf(float(c.get("score", 0.0))))
		var chosen_pos: Vector2i = chosen.get("pos", Vector2i(-1, -1))
		for i in range(mini(candidates.size(), 3)):
			var c = candidates[i]
			var pos: Vector2i = c.get("pos", Vector2i(-1, -1))
			var sc: float = float(c.get("score", 0.0))
			ap.candidates.append({
				"pos": pos,
				"score": sc,
				"norm": (sc + max_abs) / (2.0 * max_abs),
				"chosen": pos == chosen_pos,
				"type": "mm",
			})
		ap.next_pos = chosen_pos
		ap.add_log("pick %s" % _tile_text(chosen_pos))
		return

func _on_mcts_decision(id: int, root_visits: int, candidates: Array, chosen: Dictionary) -> void:
	for p in _panels:
		var ap := p as AgentPanel
		if ap.agent_id != id:
			continue
		ap.candidates.clear()
		ap.decision_kind = "MCTS visits"
		var max_v: float = 1.0
		for c in candidates:
			max_v = maxf(max_v, float(c.get("visits", 0)))
		var chosen_pos: Vector2i = chosen.get("pos", Vector2i(-1, -1))
		for i in range(mini(candidates.size(), 3)):
			var c = candidates[i]
			var pos: Vector2i = c.get("pos", Vector2i(-1, -1))
			var v: int = int(c.get("visits", 0))
			var avg: float = float(c.get("avg_score", 0.0))
			ap.candidates.append({
				"pos": pos,
				"visits": v,
				"avg": avg,
				"norm": float(v) / max_v,
				"chosen": pos == chosen_pos,
				"type": "mcts",
			})
		ap.next_pos = chosen_pos
		ap.add_log("pick %s / %d sims" % [_tile_text(chosen_pos), root_visits])
		return

func _on_fuzzy_decision(id: int, _inputs: Dictionary, rule_activations: Array, output: String, chosen_pos: Vector2i = Vector2i(-1, -1)) -> void:
	for p in _panels:
		var ap := p as AgentPanel
		if ap.agent_id != id:
			continue
		ap.candidates.clear()
		ap.decision_kind = "Fuzzy rules"
		for i in range(mini(rule_activations.size(), 4)):
			var r   = rule_activations[i]
			var rn  : String = str(r.get("rule", "?"))
			var rs  : float  = float(r.get("strength", 0.0))
			ap.candidates.append({
				"rule":   rn,
				"score":  rs,
				"norm":   rs,
				"chosen": rn == output,
				"type":   "fuzzy",
			})
		ap.next_pos = chosen_pos
		ap.add_log("rule %s" % output)
		return

# =========================================================================
# DRAWING  — all in screen space (this node is a child of CanvasLayer)
# =========================================================================

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(PANEL_X, 0.0, PANEL_W, PANEL_H), C_PANEL_BG)
	draw_line(Vector2(PANEL_X, 0.0), Vector2(PANEL_X, PANEL_H), C_PANEL_BORDER, 2.0)
	_draw_exit_banner(font)
	for compact_panel_idx in range(_panels.size()):
		var compact_panel_y := START_Y + float(compact_panel_idx) * (AGENT_H + AGENT_GAP)
		_draw_agent_panel(_panels[compact_panel_idx] as AgentPanel,
			PANEL_X + 12.0, compact_panel_y, PANEL_W - 24.0, AGENT_H, font)
	_draw_hints(font)
	return

	# ── Game-area top status strip (spans game area, not HUD column) ──
	_draw_top_strip(font)

	# ── Column background ──────────────────────────────────────────────
	draw_rect(Rect2(PANEL_X, 0.0, PANEL_W, PANEL_H), C_PANEL_BG)
	# Left border line
	draw_line(Vector2(PANEL_X, 0.0), Vector2(PANEL_X, PANEL_H), C_PANEL_BORDER, 2.0)

	# ── Active-exit banner ────────────────────────────────────────────
	_draw_exit_banner(font)

	# ── Three agent panels ─────────────────────────────────────────────
	for i in range(_panels.size()):
		var py := START_Y + float(i) * (AGENT_H + AGENT_GAP)
		_draw_agent_panel(_panels[i] as AgentPanel,
			PANEL_X + 6.0, py, PANEL_W - 12.0, AGENT_H, font)

	# ── Bottom hints strip ─────────────────────────────────────────────
	_draw_hints(font)

# -------------------------------------------------------------------------

func _draw_top_strip(font: Font) -> void:
	var w := PANEL_X   # 1560 px — game area width only
	# Background
	draw_rect(Rect2(0.0, 0.0, w, STRIP_H),
		Color(0.04, 0.06, 0.10, 0.85))
	# Bottom border line
	draw_line(Vector2(0.0, STRIP_H - 1.0), Vector2(w, STRIP_H - 1.0),
		Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.45), 1.0)
	# Left accent strip
	draw_rect(Rect2(0.0, 0.0, 3.0, STRIP_H),
		Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, 0.70))

	if font == null:
		return

	# Left: game title
	draw_string(font, Vector2(12.0, 23.0), "PRISON BREAK",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_HIGHLIGHT)

	# Centre: active exit info
	var exit_str: String
	if _active_exit.x >= 0:
		exit_str = "EXIT  [%d, %d]   \u00B7   next: %ds" % [
			_active_exit.x, _active_exit.y, int(ceil(_countdown))]
	else:
		exit_str = "EXIT: \u2014"
	var ex_off := float(exit_str.length()) * 13.0 * 0.30
	draw_string(font, Vector2(w * 0.5 - ex_off, 23.0), exit_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_HIGHLIGHT)

	# Right: overlay toggle hints
	draw_string(font, Vector2(w - 272.0, 23.0),
		"F1: paths   F2: vision   F3: danger",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.58, 0.70, 0.70))

# -------------------------------------------------------------------------

func _draw_exit_banner(font: Font) -> void:
	var bx  := PANEL_X
	var bh  := BANNER_H
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.003)

	draw_rect(Rect2(bx, 0.0, PANEL_W, bh),
		Color(0.00, 0.14, 0.06, 0.90 + pulse * 0.08))
	draw_rect(Rect2(bx, 0.0, PANEL_W, bh),
		Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, 0.35 + pulse * 0.30),
		false)

	if font == null:
		return

	draw_string(font, Vector2(bx + 12.0, 24.0), "AI STATUS", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_TEXT)
	draw_string(font, Vector2(bx + PANEL_W - 80.0, 23.0), "TICK %d" % _tick,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_DIM)
	var exit_text := "Exit %s  next %ds" % [_tile_text(_active_exit), int(ceil(_countdown))]
	draw_string(font, Vector2(bx + 12.0, 52.0), exit_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_HIGHLIGHT)
	return

	if _active_exit.x >= 0:
		draw_string(font,
			Vector2(bx + 10.0, 22.0),
			"ACTIVE EXIT  [%d, %d]" % [_active_exit.x, _active_exit.y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_HIGHLIGHT)
		draw_string(font,
			Vector2(bx + 10.0, 44.0),
			"next change in %ds" % int(ceil(_countdown)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.65, 0.90, 0.65))
	else:
		draw_string(font,
			Vector2(bx + 10.0, 32.0),
			"ACTIVE EXIT: —",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.60, 0.80, 0.60))

# -------------------------------------------------------------------------

func _draw_agent_panel(ap: AgentPanel, x: float, y: float, w: float, h: float, font: Font) -> void:
	# Card background
	draw_rect(Rect2(x, y, w, h), Color(0.07, 0.10, 0.17, 0.96))
	# Colored top strip (6 px header bar)
	draw_rect(Rect2(x, y, w, 6.0), ap.role_color)
	# Role-colour accent strip (6 px left edge, below top strip)
	draw_rect(Rect2(x, y + 6.0, 6.0, h - 6.0), ap.role_color)
	# Card border
	draw_rect(Rect2(x, y, w, h),
		Color(ap.role_color.r, ap.role_color.g, ap.role_color.b, 0.45), false)
	# Inner highlight edges
	draw_line(Vector2(x + 1.0, y + 7.0), Vector2(x + w - 2.0, y + 7.0), Color(1,1,1,0.08), 1.0)
	draw_line(Vector2(x + 1.0, y + 7.0), Vector2(x + 1.0, y + h - 2.0), Color(1,1,1,0.06), 1.0)

	if font == null:
		return

	var compact_x := x + 12.0
	var compact_y := y + 25.0
	draw_string(font, Vector2(compact_x, compact_y), ap.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ap.role_color)
	draw_string(font, Vector2(x + w - 74.0, compact_y - 1.0), ap.ai_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_DIM)

	compact_y += 18.0
	_draw_bar(compact_x, compact_y, w - 24.0, 12.0, ap.display_health, ap.max_health, C_HP, font)
	compact_y += 18.0
	_draw_bar(compact_x, compact_y, w - 24.0, 12.0, ap.display_stamina, ap.max_stamina, C_ST, font)

	compact_y += 25.0
	var compact_route_text := "Move  %s  %s  %s" % [_tile_text(ap.grid_pos), _dir_arrow(ap.grid_pos, ap.next_pos), _tile_text(ap.next_pos)]
	draw_string(font, Vector2(compact_x, compact_y), compact_route_text, HORIZONTAL_ALIGNMENT_LEFT, w - 24.0, 13, C_TEXT)
	compact_y += 17.0
	draw_string(font, Vector2(compact_x, compact_y), "Action: %s" % ap.action_text, HORIZONTAL_ALIGNMENT_LEFT, w - 24.0, 12, C_DIM)
	compact_y += 15.0
	draw_string(font, Vector2(compact_x, compact_y), "Status: %s" % ap.status_text, HORIZONTAL_ALIGNMENT_LEFT, w - 24.0, 12, C_DIM)

	compact_y += 22.0
	draw_string(font, Vector2(compact_x, compact_y), "Decision tree", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ap.role_color)
	if ap.decision_kind != "":
		draw_string(font, Vector2(x + w - 122.0, compact_y), ap.decision_kind, HORIZONTAL_ALIGNMENT_LEFT, 110.0, 12, C_DIM)
	compact_y += 24.0

	if ap.candidates.is_empty():
		draw_string(font, Vector2(compact_x, compact_y), "waiting for next decision", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.46, 0.56, 0.55))
	else:
		for compact_candidate_idx in range(mini(ap.candidates.size(), 4)):
			var compact_candidate = ap.candidates[compact_candidate_idx]
			var compact_chosen := bool(compact_candidate.get("chosen", false))
			var compact_norm := clampf(float(compact_candidate.get("norm", 0.0)), 0.0, 1.0)
			if compact_chosen:
				draw_rect(Rect2(compact_x - 4.0, compact_y - 12.0, w - 16.0, 20.0), Color(ap.role_color.r, ap.role_color.g, ap.role_color.b, 0.11))
			draw_rect(Rect2(compact_x, compact_y - 4.0, 86.0, 7.0), Color(0.12, 0.15, 0.20))
			draw_rect(Rect2(compact_x, compact_y - 4.0, 86.0 * compact_norm, 7.0), Color(ap.role_color.r, ap.role_color.g, ap.role_color.b, 0.85 if compact_chosen else 0.45))
			draw_rect(Rect2(compact_x, compact_y - 4.0, 86.0, 7.0), Color(1, 1, 1, 0.08), false)

			var compact_marker := ">" if compact_chosen else "-"
			var compact_row_text: String
			match str(compact_candidate.get("type", "")):
				"fuzzy":
					compact_row_text = "%s %-10s %.2f" % [compact_marker, str(compact_candidate.get("rule", "?")), float(compact_candidate.get("score", 0.0))]
				"mcts":
					var compact_mcts_pos: Vector2i = compact_candidate.get("pos", Vector2i(-1, -1))
					compact_row_text = "%s %s %s  visits %d" % [compact_marker, _dir_arrow(ap.grid_pos, compact_mcts_pos), _tile_text(compact_mcts_pos), int(compact_candidate.get("visits", 0))]
				_:
					var compact_mm_pos: Vector2i = compact_candidate.get("pos", Vector2i(-1, -1))
					compact_row_text = "%s %s %s  score %.1f" % [compact_marker, _dir_arrow(ap.grid_pos, compact_mm_pos), _tile_text(compact_mm_pos), float(compact_candidate.get("score", 0.0))]
			draw_string(font, Vector2(compact_x + 96.0, compact_y + 3.0), compact_row_text, HORIZONTAL_ALIGNMENT_LEFT, w - 120.0, 12,
				Color(0.86, 0.93, 0.90, 1.0 if compact_chosen else 0.68))
			compact_y += 24.0

	compact_y = y + h - 42.0
	draw_line(Vector2(compact_x, compact_y - 10.0), Vector2(x + w - 12.0, compact_y - 10.0), Color(1.0, 1.0, 1.0, 0.07), 1.0)
	for compact_log_idx in range(mini(ap.decision_log.size(), 2)):
		draw_string(font, Vector2(compact_x, compact_y + float(compact_log_idx) * 15.0), ap.decision_log[compact_log_idx],
			HORIZONTAL_ALIGNMENT_LEFT, w - 24.0, 12, Color(0.58, 0.72, 0.64, 0.86))
	return

	var cx := x + 12.0   # content left (past accent strip + small margin)
	var cy := y + 8.0    # start below the top strip

	# ── Agent name & status badge ──────────────────────────────────────
	draw_string(font, Vector2(cx, cy + 18.0), ap.label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ap.role_color)

	var badge_col := C_HIGHLIGHT if ap.is_active else Color(0.90, 0.30, 0.30)
	var badge_str := "ACTIVE" if ap.is_active else "  OUT "
	draw_rect(Rect2(x + w - 58.0, cy + 3.0, 52.0, 17.0),
		Color(badge_col.r, badge_col.g, badge_col.b, 0.18))
	draw_string(font, Vector2(x + w - 55.0, cy + 16.0), badge_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, badge_col)
	cy += 24.0

	# ── Health bar ─────────────────────────────────────────────────────
	draw_string(font, Vector2(cx, cy + 13.0), "HP",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.80, 0.50, 0.50))
	_draw_bar(cx + 24.0, cy, w - 36.0, 14.0,
		ap.display_health, ap.max_health, Color(0.90, 0.20, 0.20), font)
	cy += 20.0

	# ── Stamina bar ────────────────────────────────────────────────────
	draw_string(font, Vector2(cx, cy + 13.0), "ST",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.80, 0.75, 0.40))
	_draw_bar(cx + 24.0, cy, w - 36.0, 14.0,
		ap.display_stamina, ap.max_stamina, Color(0.90, 0.75, 0.10), font)
	cy += 22.0

	# ── Action & status ────────────────────────────────────────────────
	draw_string(font, Vector2(cx, cy + 13.0),
		"Act: " + ap.action_text,
		HORIZONTAL_ALIGNMENT_LEFT, w - 16.0, 13, Color(0.85, 0.85, 0.85))
	cy += 17.0
	draw_string(font, Vector2(cx, cy + 13.0),
		"Sts: " + ap.status_text,
		HORIZONTAL_ALIGNMENT_LEFT, w - 16.0, 12, Color(0.70, 0.70, 0.70))
	cy += 19.0

	_draw_divider(x, cy, w)
	cy += 7.0

	# ── AI Candidates ─────────────────────────────────────────────────
	draw_string(font, Vector2(cx, cy + 12.0), "Candidates:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.50, 0.80, 0.55))
	cy += 15.0

	if ap.candidates.is_empty():
		draw_string(font, Vector2(cx + 4.0, cy + 11.0), "waiting...",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.35, 0.45, 0.40))
		cy += 14.0
	else:
		var bar_track_w : float = (w - 28.0) * 0.42
		var bar_h       : float = 7.0
		var row_h       : float = 18.0

		for ci in range(ap.candidates.size()):
			var c       = ap.candidates[ci]
			var chosen  : bool   = bool(c.get("chosen", false))
			var norm    : float  = clampf(float(c.get("norm", 0.0)), 0.0, 1.0)
			var ctype   : String = str(c.get("type", ""))

			# Subtle row highlight for chosen candidate
			if chosen:
				draw_rect(Rect2(x + 1.0, cy - 1.0, w - 2.0, row_h),
					Color(ap.role_color.r, ap.role_color.g, ap.role_color.b, 0.13))

			# ▶ / · marker
			var marker_col := ap.role_color if chosen else Color(0.40, 0.55, 0.45, 0.75)
			draw_string(font, Vector2(cx, cy + 11.0),
				"\u25B6" if chosen else "\u00B7",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, marker_col)

			# Mini score bar
			var bar_col := Color(ap.role_color.r, ap.role_color.g, ap.role_color.b,
								 0.85 if chosen else 0.45)
			draw_rect(Rect2(cx + 10.0, cy + 4.0, bar_track_w, bar_h), Color(0.10, 0.14, 0.22))
			if norm > 0.01:
				draw_rect(Rect2(cx + 10.0, cy + 4.0, bar_track_w * norm, bar_h), bar_col)
			draw_rect(Rect2(cx + 10.0, cy + 4.0, bar_track_w, bar_h), Color(1,1,1,0.07), false)

			# Label text (direction arrow + coords, or rule name)
			var lbl: String
			if ctype == "fuzzy":
				var rn : String = str(c.get("rule", "?"))
				var sc : float  = float(c.get("score", 0.0))
				lbl = "%-11s%.2f" % [rn, sc]
			else:
				var pos : Vector2i = c.get("pos", Vector2i(-1, -1))
				var arrow : String = _dir_arrow(ap.grid_pos, pos)
				if ctype == "mcts":
					lbl = "%s(%d,%d) v=%d" % [arrow, pos.x, pos.y, int(c.get("visits", 0))]
				else:
					lbl = "%s(%d,%d) %.1f" % [arrow, pos.x, pos.y, float(c.get("score", 0.0))]

			var lbl_alpha : float = 1.0 if chosen else 0.68
			draw_string(font, Vector2(cx + 14.0 + bar_track_w + 2.0, cy + 11.0),
				lbl, HORIZONTAL_ALIGNMENT_LEFT, w - (24.0 + bar_track_w + 4.0), 12,
				Color(0.80, 0.92, 0.82, lbl_alpha))

			cy += row_h

	_draw_divider(x, cy, w)
	cy += 7.0

	# ── Decision log ───────────────────────────────────────────────────
	draw_string(font, Vector2(cx, cy + 12.0), "Log:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.50, 0.80, 0.55))
	cy += 16.0

	for li in range(mini(ap.decision_log.size(), 5)):
		var alpha := 1.0 - float(li) * 0.16
		draw_string(font, Vector2(cx + 4.0, cy + 12.0),
			ap.decision_log[li],
			HORIZONTAL_ALIGNMENT_LEFT, w - 20.0, 12,
			Color(0.50, 0.72, 0.58, alpha))
		cy += 14.0

# -------------------------------------------------------------------------

func _draw_bar(x: float, y: float, w: float, h: float,
               value: float, max_val: float, color: Color, font: Font) -> void:
	# Track
	draw_rect(Rect2(x, y, w, h), Color(0.10, 0.13, 0.20))
	# Fill
	if max_val > 0.0:
		var fill_w := w * clampf(value / max_val, 0.0, 1.0)
		if fill_w >= 1.0:
			draw_rect(Rect2(x, y, fill_w, h), color)
			# Bright 2-px highlight strip on top of fill
			draw_rect(Rect2(x, y, fill_w, 2.0), Color(1.0, 1.0, 1.0, 0.18))
	# Value text
	if font != null:
		draw_string(font,
			Vector2(x + w - 38.0, y + h - 1.0),
			"%d/%d" % [int(value), int(max_val)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 1.0, 1.0, 0.50))
	# Border
	draw_rect(Rect2(x, y, w, h), Color(1.0, 1.0, 1.0, 0.12), false)

func _draw_divider(x: float, y: float, w: float) -> void:
	draw_line(Vector2(x + 6.0, y + 1.0), Vector2(x + w - 6.0, y + 1.0),
		Color(1.0, 1.0, 1.0, 0.07), 1.0)

func _draw_hints(font: Font) -> void:
	if font == null:
		return
	var hy := PANEL_H - 26.0
	draw_rect(Rect2(PANEL_X, hy - 6.0, PANEL_W, 32.0), Color(0.04, 0.06, 0.10, 0.80))
	draw_string(font,
		Vector2(PANEL_X + 8.0, hy + 12.0),
		"F1 paths  F2 vision  F3 danger",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.58, 0.70, 0.75))

func _tile_text(pos: Vector2i) -> String:
	if pos.x < 0:
		return "--"
	return "(%d,%d)" % [pos.x, pos.y]

func _dir_arrow(from: Vector2i, to: Vector2i) -> String:
	if from.x < 0 or to.x < 0:
		return "->"
	var d := to - from
	if d == Vector2i(0, -1): return "up"
	if d == Vector2i(0, 1): return "down"
	if d == Vector2i(-1, 0): return "left"
	if d == Vector2i(1, 0): return "right"
	if d == Vector2i.ZERO: return "wait"
	return "->"
	if from.x < 0 or to.x < 0:
		return ""
	var dx : int = to.x - from.x
	var dy : int = to.y - from.y
	if dx == 0 and dy < 0: return "\u2191"   # ↑
	if dx == 0 and dy > 0: return "\u2193"   # ↓
	if dy == 0 and dx < 0: return "\u2190"   # ←
	if dy == 0 and dx > 0: return "\u2192"   # →
	if dx < 0 and dy < 0:  return "\u2196"   # ↖
	if dx > 0 and dy < 0:  return "\u2197"   # ↗
	if dx < 0 and dy > 0:  return "\u2199"   # ↙
	return "\u2198"                           # ↘

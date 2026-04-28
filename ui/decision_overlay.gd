# UPDATED — overlay strict typing hardening
extends Node2D
class_name DecisionOverlay

const TILE_SIZE: int = 48
const PAD: float = 5.0
const MIN_WEIGHT: float = 0.18
const CHOSEN_WEIGHT: float = 1.0

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, -1),
	Vector2i(0, 1),
]

var _agents: Array = []
var _grid: GridEngine = null
var _decisions: Dictionary = {}

# FIX #4: Store latest fuzzy defuzz scores so _draw() can render live bars.
var _fuzzy_scores: Dictionary = {}
# Countdown seconds remaining — set externally by HUD or game scene.
var time_remaining_seconds: float = -1.0

func setup(agents: Array, grid: GridEngine) -> void:
	_agents = agents
	_grid = grid
	EventBus.minimax_decision.connect(_on_minimax_decision)
	EventBus.mcts_decision.connect(_on_mcts_decision)
	EventBus.fuzzy_decision.connect(_on_fuzzy_decision)
	# FIX #4: Subscribe to the new fuzzy_debug signal for live score bars.
	EventBus.fuzzy_debug.connect(_on_fuzzy_debug)
	EventBus.tick_ended.connect(_on_tick_ended)
	EventBus.agent_action_chosen.connect(_on_action_chosen)
	queue_redraw()

func _process(_delta: float) -> void:
	if not _decisions.is_empty():
		queue_redraw()

func _on_minimax_decision(id: int, candidates: Array, chosen: Dictionary) -> void:
	var chosen_pos: Vector2i = chosen.get("pos", Vector2i(-1, -1))
	_store_decision(id, candidates, chosen_pos, "score")

func _on_mcts_decision(id: int, _root_visits: int, candidates: Array, chosen: Dictionary) -> void:
	var chosen_pos: Vector2i = chosen.get("pos", Vector2i(-1, -1))
	_store_decision(id, candidates, chosen_pos, "visits")

func _on_fuzzy_decision(id: int, _inputs: Dictionary, _rule_activations: Array, _output: String, chosen_pos: Vector2i) -> void:
	_store_decision(id, [], chosen_pos, "")

# FIX #4: Cache the latest defuzzified scores keyed by agent_id.
func _on_fuzzy_debug(data: Dictionary) -> void:
	var aid: int = int(data.get("agent_id", -1))
	if aid >= 0:
		_fuzzy_scores[aid] = data
	queue_redraw()

func _on_tick_ended(_n: int) -> void:
	queue_redraw()

func _on_action_chosen(id: int, action: String) -> void:
	if action == "STUNNED":
		var agent: Agent = _agent_for(id)
		_store_decision(id, [], agent.grid_pos if agent != null else Vector2i(-1, -1), "")

func _store_decision(id: int, candidates: Array, chosen_pos: Vector2i, metric: String) -> void:
	var agent: Agent = _agent_for(id)
	if agent == null:
		return
	var origin: Vector2i = agent.grid_pos
	var weights: Dictionary = _base_weights(origin, chosen_pos)
	_apply_candidate_weights(weights, candidates, metric)
	if chosen_pos.x >= 0:
		weights[chosen_pos] = CHOSEN_WEIGHT
	_decisions[id] = {"origin": origin, "chosen": chosen_pos, "weights": weights}
	queue_redraw()

func _base_weights(origin: Vector2i, chosen_pos: Vector2i) -> Dictionary:
	var weights: Dictionary = {}
	for dir in DIRS:
		var pos: Vector2i = origin + dir
		var weight: float = MIN_WEIGHT
		if pos == chosen_pos:
			weight = CHOSEN_WEIGHT
		weights[pos] = weight
	return weights

func _apply_candidate_weights(weights: Dictionary, candidates: Array, metric: String) -> void:
	if candidates.is_empty():
		return
	var max_abs: float = 0.1
	var min_score: float = INF
	var max_score: float = -INF
	var max_visits: float = 1.0
	for row in candidates:
		if metric == "visits":
			max_visits = maxf(max_visits, float(row.get("visits", 0)))
		elif metric == "score":
			var score: float = float(row.get("score", 0.0))
			min_score = minf(min_score, score)
			max_score = maxf(max_score, score)
			max_abs = maxf(max_abs, absf(score))
	for row in candidates:
		var pos: Vector2i = row.get("pos", Vector2i(-1, -1))
		if not weights.has(pos):
			continue
		var norm: float = MIN_WEIGHT
		if metric == "visits":
			norm = maxf(MIN_WEIGHT, float(row.get("visits", 0)) / max_visits)
		elif metric == "score":
			var score2: float = float(row.get("score", 0.0))
			var spread: float = max_score - min_score
			if spread > 0.001:
				norm = (score2 - min_score) / spread
			else:
				norm = (score2 + max_abs) / (2.0 * max_abs)
			norm = maxf(MIN_WEIGHT, clampf(norm, 0.0, 1.0))
		weights[pos] = norm

func _draw() -> void:
	if _grid == null:
		return
	for agent in _agents:
		if not agent.is_active:
			continue
		var data: Dictionary = _decisions.get(agent.agent_id, {})
		var origin: Vector2i = data.get("origin", agent.grid_pos)
		var chosen: Vector2i = data.get("chosen", Vector2i(-1, -1))
		var weights: Dictionary = data.get("weights", _base_weights(origin, chosen))
		var color: Color = _agent_color(agent)
		for dir in DIRS:
			var pos: Vector2i = origin + dir
			var weight: float = clampf(float(weights.get(pos, MIN_WEIGHT)), MIN_WEIGHT, 1.0)
			_draw_tile_choice(pos, color, weight, pos == chosen)

	# FIX #4: Draw live fuzzy defuzzification bars for the police agent.
	_draw_fuzzy_bars()

	# FIX #4: Draw countdown timer overlay in the top-right of the game viewport.
	_draw_countdown_timer()

func _draw_fuzzy_bars() -> void:
	# Find police agent to anchor the bar chart near them.
	var police_agent: Agent = null
	for a in _agents:
		if a._role == "police" and a.is_active:
			police_agent = a
			break
	if police_agent == null:
		return
	var scores: Dictionary = _fuzzy_scores.get(police_agent.agent_id, {})
	if scores.is_empty():
		return

	var behaviour: String = str(scores.get("behaviour", ""))
	var px: float = float(police_agent.grid_pos.x * TILE_SIZE) + TILE_SIZE * 1.2
	var py: float = float(police_agent.grid_pos.y * TILE_SIZE) - TILE_SIZE * 2.8

	var font: Font = ThemeDB.fallback_font

	var bar_labels: Array = ["CHASE", "INTCPT", "INVEST", "PATROL"]
	var bar_keys:   Array = ["chase", "intercept", "investigate", "patrol"]
	var bar_colors: Array = [
		Color(1.0, 0.22, 0.22),
		Color(1.0, 0.65, 0.10),
		Color(0.18, 0.74, 1.00),
		Color(0.30, 0.90, 0.45),
	]

	# ── Absolute-scale bars ───────────────────────────────────────────────────
	# Bar width is score / MAX_POSSIBLE_SCORE (3.5) so the examiner can see
	# whether the winner is decisive (fills most of the bar) or marginal.
	# Previously bars were normalized to winner=100%, hiding confidence entirely.
	const MAX_POSSIBLE_SCORE: float = 3.5

	# Collect raw scores and find winner + second-place for margin display
	var raw_scores: Array = []
	var winner_score: float  = -INF
	var second_score: float  = -INF
	var winner_idx: int      = -1
	for i in range(bar_keys.size()):
		var raw: float = float(scores.get(bar_keys[i], 0.0))
		raw_scores.append(raw)
		if raw > winner_score:
			second_score = winner_score
			winner_score = raw
			winner_idx   = i
		elif raw > second_score:
			second_score = raw

	# Two-column layout:
	#   col_label  col_bar            col_score  [← WINNER]
	# widths chosen so the whole panel fits in ~200px
	var col_label_w: float = 46.0
	var col_bar_w:   float = 90.0   # represents 0..MAX_POSSIBLE_SCORE
	var col_score_w: float = 30.0
	var panel_w:     float = col_label_w + col_bar_w + col_score_w + 16.0
	var bar_row_h:   float = 16.0
	var panel_h:     float = 14.0 + float(bar_labels.size()) * (bar_row_h + 2.0) + 18.0 + 14.0

	# Panel background
	draw_rect(Rect2(px - 4.0, py - 4.0, panel_w + 8.0, panel_h + 8.0),
		Color(0.0, 0.0, 0.0, 0.78))
	draw_rect(Rect2(px - 4.0, py - 4.0, panel_w + 8.0, panel_h + 8.0),
		Color(1.0, 0.86, 0.24, 0.52), false)

	draw_string(font, Vector2(px, py + 10.0), "FUZZY LOGIC — POLICE AI",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.86, 0.24))

	var bar_y: float = py + 18.0
	for i in range(bar_labels.size()):
		var raw: float      = raw_scores[i]
		var is_winner: bool = str(bar_keys[i]) == behaviour
		var bc: Color       = bar_colors[i]
		# Absolute fill: score / MAX_POSSIBLE_SCORE, capped at 1.0
		var fill_ratio: float = clampf(raw / MAX_POSSIBLE_SCORE, 0.0, 1.0)
		var bw: float         = col_bar_w * fill_ratio

		# Label column
		draw_string(font, Vector2(px, bar_y + bar_row_h - 3.0),
			bar_labels[i],
			HORIZONTAL_ALIGNMENT_LEFT, col_label_w, 9,
			Color(bc.r, bc.g, bc.b, 1.0 if is_winner else 0.60))

		# Bar column background + fill
		var bar_x: float = px + col_label_w
		draw_rect(Rect2(bar_x, bar_y, col_bar_w, bar_row_h),
			Color(0.08, 0.08, 0.12, 0.90))
		draw_rect(Rect2(bar_x, bar_y, bw, bar_row_h),
			Color(bc.r, bc.g, bc.b, 0.88))
		if is_winner:
			draw_rect(Rect2(bar_x, bar_y, col_bar_w, bar_row_h),
				Color(bc.r, bc.g, bc.b, 0.92), false, 2.0)

		# Score column (raw absolute value)
		var score_x: float = bar_x + col_bar_w + 4.0
		draw_string(font, Vector2(score_x, bar_y + bar_row_h - 3.0),
			"%.2f" % raw,
			HORIZONTAL_ALIGNMENT_LEFT, col_score_w, 9,
			Color(1.0, 1.0, 1.0, 1.0 if is_winner else 0.55))

		# WINNER tag
		if is_winner:
			draw_string(font, Vector2(score_x + col_score_w - 2.0, bar_y + bar_row_h - 3.0),
				"<WIN",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(bc.r * 1.2, bc.g * 1.2, bc.b * 1.2, 0.95))

		bar_y += bar_row_h + 2.0

	# Margin line: shows decisiveness — examiner can instantly see chase=3.20 vs 0.10
	var margin: float = winner_score - second_score
	var margin_col: Color = Color(0.90, 0.90, 0.90) if margin >= 0.5 else Color(1.0, 0.70, 0.20)
	draw_string(font, Vector2(px, bar_y + 10.0),
		"margin %.2f" % margin,
		HORIZONTAL_ALIGNMENT_LEFT, panel_w * 0.5, 9,
		Color(margin_col.r, margin_col.g, margin_col.b, 0.80))

	# Alert level strip
	var alert: float = clampf(float(scores.get("alert", 0.0)), 0.0, 1.0)
	draw_rect(Rect2(px + panel_w * 0.5, bar_y + 2.0, panel_w * 0.5, 10.0),
		Color(0.08, 0.08, 0.12, 0.90))
	draw_rect(Rect2(px + panel_w * 0.5, bar_y + 2.0, (panel_w * 0.5) * alert, 10.0),
		Color(1.0, 0.30, 0.10, 0.85))
	draw_string(font, Vector2(px + panel_w * 0.5 + 3.0, bar_y + 11.0),
		"ALERT %.0f%%" % (alert * 100.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.75, 0.40))

func _draw_countdown_timer() -> void:
	if time_remaining_seconds < 0.0:
		return
	var secs: int  = int(ceilf(time_remaining_seconds))
	var mins: int  = secs / 60
	var s: int     = secs % 60
	var label: String = "%d:%02d" % [mins, s]
	var urgent: bool = time_remaining_seconds <= 15.0
	var flash: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.015)
	var font: Font = ThemeDB.fallback_font
	# Position: top-right corner of screen; viewport size not trivially available
	# here so we use a fixed offset from origin.
	var vp: Vector2 = get_viewport_rect().size
	var tx: float = vp.x - 120.0
	var ty: float = 14.0
	# Background
	draw_rect(Rect2(tx - 8.0, ty - 2.0, 108.0, 28.0), Color(0.0, 0.0, 0.0, 0.72))
	var tc: Color = Color(1.0, 0.22, 0.22) if urgent else Color(0.90, 0.90, 0.90)
	if urgent:
		tc.a = 0.55 + flash * 0.45
		draw_rect(Rect2(tx - 8.0, ty - 2.0, 108.0, 28.0),
			Color(1.0, 0.10, 0.10, 0.22 * flash), false)
	draw_string(font, Vector2(tx, ty + 8.0), "TIME", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.6, 0.6))
	draw_string(font, Vector2(tx, ty + 22.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, tc)

func _draw_tile_choice(pos: Vector2i, color: Color, weight: float, chosen: bool) -> void:
	var tile: GridTileData = _grid.get_tile(pos)
	var in_bounds: bool = tile != null
	if not in_bounds:
		return
	var walkable: bool = tile.walkable
	var alpha: float = 0.12 + weight * 0.26
	if chosen:
		alpha = 0.58
	elif not walkable:
		alpha *= 0.38
	var x: float = float(pos.x * TILE_SIZE)
	var y: float = float(pos.y * TILE_SIZE)
	var rect: Rect2 = Rect2(x + PAD, y + PAD, TILE_SIZE - PAD * 2.0, TILE_SIZE - PAD * 2.0)
	draw_rect(rect, Color(color.r, color.g, color.b, alpha))
	draw_rect(rect, Color(color.r, color.g, color.b, 0.95 if chosen else 0.38), false, 2.0 if chosen else 1.0)
	if chosen:
		var center: Vector2 = rect.get_center()
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
		draw_arc(center, TILE_SIZE * (0.32 + pulse * 0.05), 0.0, TAU, 24, Color(color.r, color.g, color.b, 0.70), 2.0)
	elif not walkable:
		draw_line(rect.position + Vector2(5.0, 5.0), rect.end - Vector2(5.0, 5.0), Color(color.r, color.g, color.b, 0.30), 1.0)

func _agent_color(agent: Agent) -> Color:
	match agent._role:
		"rusher_red": return Color(0.94, 0.27, 0.27)
		"sneaky_blue": return Color(0.18, 1.00, 0.92)
		"police": return Color(1.00, 0.86, 0.24)
		_: return Color.WHITE

func _agent_for(id: int) -> Agent:
	for agent in _agents:
		if agent.agent_id == id:
			return agent
	return null

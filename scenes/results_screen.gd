extends Node2D
class_name ResultsScreen

## Shows outcome, per-agent stats, and metrics after a run ends.
## Receives data via the static `pending_result` dictionary (set by game.gd).

# -- Static storage -- game.gd writes here before changing scene ----------
static var pending_result: Dictionary = {}

# -- Theme ----------------------------------------------------------------
const C_BG           := Color(0.055, 0.078, 0.125)
const C_HIGHLIGHT    := Color(0.290, 0.855, 0.502)
const C_WARNING      := Color(0.984, 0.749, 0.141)
const C_POLICE       := Color(0.231, 0.510, 0.965)
const C_RED_AG       := Color(0.937, 0.267, 0.267)
const C_BLUE_AG      := Color(0.376, 0.647, 0.980)
const C_PANEL_BG     := Color(0.07,  0.10,  0.17,  0.95)
const C_PANEL_BORDER := Color(0.0,   0.70,  1.0,   0.45)
const C_TEXT         := Color(0.88,  0.90,  0.94)
const C_DIM          := Color(0.55,  0.60,  0.68)

# -- Button ids -----------------------------------------------------------
const BTN_REPLAY : int = 0
const BTN_TITLE  : int = 1
const BTN_AI_ANALYSIS: int = 2
const BTN_BACK_RESULTS: int = 3
const BTN_TAB_RED: int = 4
const BTN_TAB_BLUE: int = 5
const BTN_TAB_POLICE: int = 6

enum ViewMode {
	RESULTS,
	AI_ANALYSIS,
}

var _btn_rects  : Array[Rect2] = [Rect2(), Rect2(), Rect2(), Rect2(), Rect2(), Rect2(), Rect2()]
var _mouse_pos  : Vector2      = Vector2.ZERO
var _hover_btn  : int          = -1

var _result     : Dictionary   = {}
var _view_mode: int = ViewMode.RESULTS
var _analysis_role: String = "rusher_red"
var _timeline_scroll: int  = 0
var _timeline_rect: Rect2  = Rect2()

# -- Entry animation: 0->1 over ~0.6 s, drives fade-in -------------------
var _show_t     : float        = 0.0
var _anim_t     : float        = 0.0

# -------------------------------------------------------------------------

func _ready() -> void:
	_result = pending_result.duplicate()

func _process(delta: float) -> void:
	_show_t    = minf(_show_t + delta / 0.6, 1.0)
	_anim_t   += delta
	_mouse_pos = get_viewport().get_mouse_position()
	_refresh_nav_regions()
	_hover_btn = _find_button_at(_mouse_pos)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _view_mode == ViewMode.AI_ANALYSIS and _timeline_rect.has_point(event.position):
				_timeline_scroll = maxi(0, _timeline_scroll - 1)
				queue_redraw()
				return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _view_mode == ViewMode.AI_ANALYSIS and _timeline_rect.has_point(event.position):
				_timeline_scroll += 1
				queue_redraw()
				return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_refresh_nav_regions()
		var clicked: int = _find_button_at(event.position)
		match clicked:
			BTN_REPLAY:
				_play_again()
			BTN_TITLE:
				_go_title()
			BTN_AI_ANALYSIS:
				_view_mode = ViewMode.AI_ANALYSIS
				queue_redraw()
			BTN_BACK_RESULTS:
				_view_mode = ViewMode.RESULTS
				queue_redraw()
			BTN_TAB_RED:
				_analysis_role = "rusher_red"
				_timeline_scroll = 0
				queue_redraw()
			BTN_TAB_BLUE:
				_analysis_role = "sneaky_blue"
				_timeline_scroll = 0
				queue_redraw()
			BTN_TAB_POLICE:
				_analysis_role = "police"
				_timeline_scroll = 0
				queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_A:
		_view_mode = ViewMode.AI_ANALYSIS if _view_mode == ViewMode.RESULTS else ViewMode.RESULTS
		queue_redraw()
		return
	if _view_mode == ViewMode.AI_ANALYSIS:
		match event.keycode:
			KEY_1:
				_analysis_role = "rusher_red"
				queue_redraw()
				return
			KEY_2:
				_analysis_role = "sneaky_blue"
				queue_redraw()
				return
			KEY_3:
				_analysis_role = "police"
				queue_redraw()
				return
			KEY_BACKSPACE:
				_view_mode = ViewMode.RESULTS
				queue_redraw()
				return
	match event.keycode:
		KEY_ENTER, KEY_SPACE, KEY_R: _play_again()
		KEY_ESCAPE, KEY_T:           _go_title()

func _play_again() -> void:
	pending_result = {}
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _go_title() -> void:
	pending_result = {}
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")

# =========================================================================
# DRAWING
# =========================================================================

func _draw() -> void:
	_draw_professional_results()
	return

	var vp    := get_viewport_rect()
	var cx    := vp.size.x * 0.5
	var font  := ThemeDB.fallback_font
	var alpha := _show_t

	# Background
	draw_rect(vp, C_BG)
	_draw_bg_grid(vp, alpha * 0.03)

	# Corner brackets
	_draw_corner_brackets(vp, alpha)

	# Resolve outcome early so top strip can use its color
	var outcome  : String = _result.get("outcome", "unknown")
	var out_text : String
	var out_col  : Color
	match outcome:
		"prisoners_win":
			out_text = "PRISONERS ESCAPED!"
			out_col  = C_HIGHLIGHT
		"police_wins":
			out_text = "CAPTURED -- POLICE WIN"
			out_col  = C_RED_AG
		"partial_escape":
			# MINOR #5 FIX: Explicit partial_escape display text.
			out_text = "PARTIAL ESCAPE"
			out_col  = C_WARNING
		"timeout":
			out_text = "TIME LIMIT REACHED"
			out_col  = C_WARNING
		_:
			# MINOR #5 FIX: Generic fallback for any future outcome strings.
			out_text = outcome.to_upper().replace("_", " ")
			out_col  = C_WARNING

	# Top decorative color strip (fades to transparent downward)
	draw_rect(Rect2(0.0, 0.0, vp.size.x, 6.0),
		Color(out_col.r, out_col.g, out_col.b, 0.55 * alpha))
	draw_rect(Rect2(0.0, 6.0, vp.size.x, 2.0),
		Color(out_col.r, out_col.g, out_col.b, 0.20 * alpha))
	draw_rect(Rect2(0.0, 8.0, vp.size.x, 2.0),
		Color(out_col.r, out_col.g, out_col.b, 0.07 * alpha))

	if _result.is_empty():
		if font != null:
			var emp_off := 15.0 * 18.0 * 0.30
			draw_string(font, Vector2(cx - emp_off, vp.size.y * 0.5),
				"No result data.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_DIM)
		_draw_nav_buttons(cx, vp.size.y * 0.75, font, alpha)
		return

	# -- Outcome banner -------------------------------------------------------
	# banner_y pushed down to 160 to better fill vertical space at 1080px
	var banner_y := 160.0
	if font != null:
		# Per-string half-width: char_count * 56 * 0.30
		var banner_off := float(out_text.length()) * 56.0 * 0.30
		# Wide glow
		draw_string(font, Vector2(cx - banner_off, banner_y + 5.0), out_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 56,
			Color(out_col.r, out_col.g, out_col.b, 0.10 * alpha))
		# Tight glow
		draw_string(font, Vector2(cx - banner_off, banner_y + 2.0), out_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 56,
			Color(out_col.r, out_col.g, out_col.b, 0.22 * alpha))
		# Main text
		draw_string(font, Vector2(cx - banner_off, banner_y), out_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 56,
			Color(out_col.r, out_col.g, out_col.b, alpha))

	# Thin divider below banner
	var banner_div_y := banner_y + 18.0
	draw_line(Vector2(cx - 420.0, banner_div_y), Vector2(cx + 420.0, banner_div_y),
		Color(out_col.r, out_col.g, out_col.b, 0.25 * alpha), 1.0)

	# -- Metrics row ----------------------------------------------------------
	var my := banner_y + 32.0
	if font != null:
		var ticks    : int = _result.get("total_ticks",   0)
		var actions  : int = _result.get("total_actions", 0)
		var esc_tick : int = _result.get("escape_tick",   0)
		var metrics_str := "Ticks: %d   \u00B7   Actions: %d" % [ticks, actions]
		if outcome == "prisoners_win":
			metrics_str += "   \u00B7   Escaped at tick: %d" % esc_tick
		var met_off := float(metrics_str.length()) * 18.0 * 0.30
		draw_string(font, Vector2(cx - met_off, my), metrics_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, alpha * 0.90))

	# -- Agent result cards ---------------------------------------------------
	var agent_results: Array = _result.get("agent_results", [])
	agent_results = _ranked_results(agent_results)
	var card_w   := 380.0
	var card_h   := 200.0
	var card_gap := 28.0
	var total_w  := float(agent_results.size()) * card_w \
				  + float(maxf(float(agent_results.size()) - 1.0, 0.0)) * card_gap
	var start_x  := cx - total_w * 0.5
	var card_y   := my + 28.0

	for i in range(agent_results.size()):
		var ar  : Dictionary = agent_results[i]
		var cx2 := start_x + float(i) * (card_w + card_gap)
		_draw_agent_card(ar, cx2, card_y, card_w, card_h, font, alpha)

	# -- Outcome description --------------------------------------------------
	var desc_y := card_y + card_h + 20.0
	draw_line(Vector2(cx - 300.0, desc_y - 8.0), Vector2(cx + 300.0, desc_y - 8.0),
		Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.30 * alpha), 1.0)
	if font != null:
		var desc     := _outcome_description(outcome, _result)
		var desc_off := float(desc.length()) * 16.0 * 0.30
		draw_string(font, Vector2(cx - desc_off, desc_y), desc,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(C_DIM.r, C_DIM.g, C_DIM.b, alpha * 0.9))

	# -- Navigation buttons ---------------------------------------------------
	_draw_nav_buttons(cx, desc_y + 46.0, font, alpha)

# -------------------------------------------------------------------------

func _draw_agent_card(ar: Dictionary, x: float, y: float, w: float, h: float,
		font: Font, alpha: float) -> void:
	var role : String = ar.get("role", "?")
	var hp   : float  = ar.get("health",  0.0)
	var st   : float  = ar.get("stamina", 0.0)
	var esc  : bool   = ar.get("escaped",  false)
	var cap  : bool   = ar.get("captured", false)

	var role_col   : Color
	var algo_label : String
	match role:
		"rusher_red":
			role_col   = C_RED_AG
			algo_label = "MINIMAX"
		"sneaky_blue":
			role_col   = C_BLUE_AG
			algo_label = "MCTS"
		_:
			role_col   = C_POLICE
			algo_label = "FUZZY"

	# Drop shadow
	draw_rect(Rect2(x + 4, y + 4, w, h), Color(0.0, 0.0, 0.0, 0.40 * alpha))

	# Card body
	draw_rect(Rect2(x, y, w, h),
		Color(C_PANEL_BG.r, C_PANEL_BG.g, C_PANEL_BG.b, alpha * 0.97))

	# Top colored strip (6px)
	draw_rect(Rect2(x, y, w, 6.0),
		Color(role_col.r, role_col.g, role_col.b, alpha))

	# Left accent strip (below top strip)
	draw_rect(Rect2(x, y + 6.0, 7.0, h - 6.0),
		Color(role_col.r, role_col.g, role_col.b, alpha * 0.85))

	# Border
	draw_rect(Rect2(x, y, w, h),
		Color(role_col.r, role_col.g, role_col.b, 0.38 * alpha), false)

	# Top inner highlight
	draw_line(Vector2(x + 1, y + 7), Vector2(x + w - 1, y + 7),
		Color(1, 1, 1, 0.08 * alpha), 1)

	if font == null:
		return

	var tx := x + 16.0
	var ty := y + 6.0   # below top strip

	# Role name
	var role_label: String
	match role:
		"rusher_red":  role_label = "Rusher Red"
		"sneaky_blue": role_label = "Sneaky Blue"
		_:             role_label = "Police Hunter"
	draw_string(font, Vector2(tx, ty + 26.0), role_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
		Color(role_col.r, role_col.g, role_col.b, alpha))

	# AI algorithm badge
	var badge_x := tx
	var badge_y := ty + 32.0
	var badge_w := float(algo_label.length()) * 10.0 + 14.0
	draw_rect(Rect2(badge_x, badge_y, badge_w, 16.0),
		Color(role_col.r * 0.22, role_col.g * 0.22, role_col.b * 0.22, alpha * 0.90))
	draw_rect(Rect2(badge_x, badge_y, badge_w, 16.0),
		Color(role_col.r, role_col.g, role_col.b, 0.40 * alpha), false)
	draw_string(font, Vector2(badge_x + 6.0, badge_y + 12.0), algo_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(role_col.r, role_col.g, role_col.b, alpha))

	# Status badge (top-right text)
	var badge_str: String
	var badge_col: Color
	if esc:
		badge_str = "ESCAPED"
		badge_col = C_HIGHLIGHT
	elif cap:
		badge_str = "CAPTURED"
		badge_col = C_RED_AG
	else:
		badge_str = "ACTIVE"
		badge_col = C_WARNING
	draw_string(font, Vector2(x + w - 86.0, ty + 26.0), badge_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(badge_col.r, badge_col.g, badge_col.b, alpha))

	# Status icon (checkmark or X) using draw_line
	var icon_x := x + w - 16.0
	var icon_y := ty + 13.0
	if esc:
		draw_line(Vector2(icon_x - 6.0, icon_y + 3.0),
				  Vector2(icon_x - 2.0, icon_y + 7.0),
			Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, alpha), 2.0)
		draw_line(Vector2(icon_x - 2.0, icon_y + 7.0),
				  Vector2(icon_x + 4.0, icon_y - 1.0),
			Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, alpha), 2.0)
	elif cap:
		draw_line(Vector2(icon_x - 5.0, icon_y),
				  Vector2(icon_x + 5.0, icon_y + 8.0),
			Color(C_RED_AG.r, C_RED_AG.g, C_RED_AG.b, alpha), 2.0)
		draw_line(Vector2(icon_x + 5.0, icon_y),
				  Vector2(icon_x - 5.0, icon_y + 8.0),
			Color(C_RED_AG.r, C_RED_AG.g, C_RED_AG.b, alpha), 2.0)

	# HP bar
	var bar_ty := ty + 56.0
	draw_string(font, Vector2(tx, bar_ty + 14), "HP",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.85, 0.50, 0.50, alpha))
	_draw_bar(tx + 28, bar_ty, w - 52.0, 15,
		hp, 100.0, Color(0.90, 0.20, 0.20, alpha), font, alpha)
	bar_ty += 24.0

	# Stamina bar
	draw_string(font, Vector2(tx, bar_ty + 14), "ST",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.82, 0.76, 0.42, alpha))
	_draw_bar(tx + 28, bar_ty, w - 52.0, 15,
		st, 100.0, Color(0.90, 0.75, 0.10, alpha), font, alpha)
	bar_ty += 26.0

	# Role description with proper separator
	var role_desc: String
	match role:
		"rusher_red":  role_desc = "Minimax  \u00B7  Sprint Burst"
		"sneaky_blue": role_desc = "MCTS  \u00B7  Hide & Silent Step"
		_:             role_desc = "Fuzzy Logic  \u00B7  Sprint Chase"
	draw_string(font, Vector2(tx, bar_ty + 13), role_desc,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(C_DIM.r, C_DIM.g, C_DIM.b, alpha * 0.80))

func _draw_bar(x: float, y: float, w: float, h: float,
		value: float, max_v: float, color: Color, font: Font, alpha: float) -> void:
	draw_rect(Rect2(x, y, w, h), Color(0.10, 0.13, 0.20, alpha * 0.90))
	if max_v > 0.0:
		var fw := w * clampf(value / max_v, 0.0, 1.0)
		if fw >= 1.0:
			draw_rect(Rect2(x, y, fw, h), color)
			draw_rect(Rect2(x, y, fw, 2.0), Color(1, 1, 1, 0.18 * alpha))
	if font != null:
		draw_string(font, Vector2(x + w - 38, y + h - 1),
			"%d/%d" % [int(value), int(max_v)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(1, 1, 1, 0.50 * alpha))
	draw_rect(Rect2(x, y, w, h), Color(1, 1, 1, 0.12 * alpha), false)

func _draw_nav_buttons(cx: float, y: float, font: Font, alpha: float) -> void:
	var btn_w := 280.0
	var btn_h := 58.0
	var gap   := 28.0
	var bx0   := cx - btn_w - gap * 0.5
	var bx1   := cx + gap * 0.5

	_btn_rects[BTN_REPLAY] = Rect2(bx0, y, btn_w, btn_h)
	_btn_rects[BTN_TITLE]  = Rect2(bx1, y, btn_w, btn_h)

	_draw_button(_btn_rects[BTN_REPLAY], "PLAY AGAIN",
		BTN_REPLAY == _hover_btn, C_HIGHLIGHT, font, alpha)
	_draw_button(_btn_rects[BTN_TITLE],  "MAIN MENU",
		BTN_TITLE  == _hover_btn, Color(0.50, 0.62, 0.80), font, alpha)

	if font != null:
		# ~40 chars x 13px x 0.30 = 156 half-width
		var hint_off := 40.0 * 13.0 * 0.30
		draw_string(font, Vector2(cx - hint_off, y + btn_h + 22.0),
			"Enter / R: play again   \u00B7   Esc / T: menu",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(C_DIM.r, C_DIM.g, C_DIM.b, alpha * 0.70))

func _draw_button(rect: Rect2, label: String, hovered: bool,
		accent: Color, font: Font, alpha: float) -> void:
	var r    := rect
	var bg_a := (0.88 if hovered else 0.58) * alpha
	var bd_a := (0.85 if hovered else 0.42) * alpha

	if hovered:
		var pad := r.size * 0.03
		r = Rect2(r.position - pad, r.size * 1.06)

	# Shadow
	draw_rect(Rect2(r.position + Vector2(4, 4), r.size), Color(0, 0, 0, 0.45 * alpha))
	# Body fill
	draw_rect(r, Color(accent.r * 0.20, accent.g * 0.20, accent.b * 0.20, bg_a))
	# Left accent strip
	draw_rect(Rect2(r.position, Vector2(6.0, r.size.y)),
		Color(accent.r, accent.g, accent.b, alpha))
	# Border
	draw_rect(r, Color(accent.r, accent.g, accent.b, bd_a), false)
	# Top inner highlight
	draw_line(r.position + Vector2(1, 1), r.position + Vector2(r.size.x - 1, 1),
		Color(1, 1, 1, 0.15 * alpha if hovered else 0.08 * alpha), 1.0)
	# Diagonal glint on hover
	if hovered:
		draw_line(r.position + Vector2(r.size.x * 0.3, 0),
				  r.position + Vector2(r.size.x * 0.55, r.size.y),
			Color(1, 1, 1, 0.07 * alpha), 8.0)

	if font == null:
		return

	# Properly centred label: char_count * font_size * 0.30
	var fs       := 20
	var text_off := float(label.length()) * float(fs) * 0.30
	var tc       := (Color(accent.r * 1.25, accent.g * 1.25, accent.b * 1.25) \
					if hovered else accent).clamp()
	draw_string(font,
		Vector2(r.position.x + r.size.x * 0.5 - text_off, r.position.y + r.size.y * 0.65),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(tc.r, tc.g, tc.b, alpha))

func _draw_bg_grid(vp: Rect2, line_alpha: float) -> void:
	var spacing := 60.0
	var col     := Color(1.0, 1.0, 1.0, line_alpha)
	for i in range(int(vp.size.x / spacing) + 1):
		draw_line(Vector2(i * spacing, 0), Vector2(i * spacing, vp.size.y), col, 1)
	for i in range(int(vp.size.y / spacing) + 1):
		draw_line(Vector2(0, i * spacing), Vector2(vp.size.x, i * spacing), col, 1)

func _draw_corner_brackets(vp: Rect2, alpha: float) -> void:
	var arm    := 40.0
	var thick  := 2.0
	var margin := 18.0
	var col    := Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.65 * alpha)
	draw_line(Vector2(margin, margin), Vector2(margin + arm, margin), col, thick)
	draw_line(Vector2(margin, margin), Vector2(margin, margin + arm), col, thick)
	draw_line(Vector2(vp.size.x - margin, margin),
			  Vector2(vp.size.x - margin - arm, margin), col, thick)
	draw_line(Vector2(vp.size.x - margin, margin),
			  Vector2(vp.size.x - margin, margin + arm), col, thick)
	draw_line(Vector2(margin, vp.size.y - margin),
			  Vector2(margin + arm, vp.size.y - margin), col, thick)
	draw_line(Vector2(margin, vp.size.y - margin),
			  Vector2(margin, vp.size.y - margin - arm), col, thick)
	draw_line(Vector2(vp.size.x - margin, vp.size.y - margin),
			  Vector2(vp.size.x - margin - arm, vp.size.y - margin), col, thick)
	draw_line(Vector2(vp.size.x - margin, vp.size.y - margin),
			  Vector2(vp.size.x - margin, vp.size.y - margin - arm), col, thick)

func _outcome_description(outcome: String, result: Dictionary) -> String:
	var esc : int = result.get("escaped_count",  0)
	var cap : int = result.get("captured_count", 0)
	var burned: int = int(result.get("eliminated_count", 0))
	var base: String = "%d escaped  ·  %d caught" % [esc, cap]
	if burned > 0:
		base += "  ·  %d burned" % burned
	match outcome:
		"prisoners_win":
			return base
		"police_wins":
			return base
		"partial_escape":
			# MINOR #5 FIX: Explicit partial_escape description.
			return "Partial prison break  ·  %s" % base
		"timeout":
			return "Tick limit reached  ·  %s" % base
		_:
			# MINOR #5 FIX: Generic fallback — show the raw outcome string so
			# new outcomes added in development are always visible on screen.
			return "(%s)  ·  %s" % [outcome, base]

func _prisoner_total_count() -> int:
	var total: int = 0
	for item_var in Array(_result.get("agent_results", [])):
		var item: Dictionary = Dictionary(item_var)
		if str(item.get("role", "")) != "police":
			total += 1
	return maxi(total, 2)

func _resolved_outcome_key() -> String:
	var escaped: int = int(_result.get("escaped_count", 0))
	var prisoner_total: int = _prisoner_total_count()
	var raw_outcome: String = str(_result.get("outcome", "unknown"))

	# CRITICAL #2 FIX: Check escaped counts BEFORE checking captured count.
	# Previously "if captured >= 1: return police_wins" would fire even when
	# one prisoner escaped and one was captured — overriding the correct
	# "partial_escape" outcome from the simulation.
	if escaped >= prisoner_total:
		return "prisoners_win"

	if escaped > 0:
		return "partial_escape"

	match raw_outcome:
		"prisoners_win", "police_wins", "partial_escape", "timeout":
			return raw_outcome

	return raw_outcome

func _resolved_outcome_presentation() -> Dictionary:
	var key: String = _resolved_outcome_key()
	var escaped: int = int(_result.get("escaped_count", 0))
	var captured: int = int(_result.get("captured_count", 0))
	var burned: int = int(_result.get("eliminated_count", 0))
	var heading: String = "%d ESCAPED  ·  %d CAPTURED" % [escaped, captured]
	var sub: String = ""
	if burned > 0:
		sub = "%d burned by fire" % burned
	match key:
		"prisoners_win":
			return {
				"key": key,
				"title": heading,
				"subtitle": sub,
				"accent": C_HIGHLIGHT,
			}
		"police_wins":
			return {
				"key": key,
				"title": heading,
				"subtitle": sub,
				"accent": C_POLICE,
			}
		"partial_escape":
			# MINOR #5 FIX: partial_escape — one prisoner out, one caught.
			# Uses a blended warning/highlight colour to signal the mixed result.
			return {
				"key": key,
				"title": heading,
				"subtitle": ("Partial break — " + sub) if sub != "" else "Partial break",
				"accent": C_WARNING,
			}
		_:
			# MINOR #5 FIX: Generic fallback — any new outcome string added during
			# development is shown explicitly rather than silently mapping to timeout.
			return {
				"key": key,
				"title": heading,
				"subtitle": ("(%s)" % key) if key != "timeout" else sub,
				"accent": C_WARNING,
			}

func _content_bounds(vp: Rect2) -> Rect2:
	var margin_x: float = maxf(24.0, vp.size.x * 0.025)
	var margin_top: float = maxf(20.0, vp.size.y * 0.024)
	var margin_bottom: float = maxf(40.0, vp.size.y * 0.045)
	return Rect2(
		margin_x,
		margin_top,
		vp.size.x - margin_x * 2.0,
		vp.size.y - margin_top - margin_bottom
	)

func _draw_professional_results() -> void:
	_refresh_nav_regions()
	var vp: Rect2 = get_viewport_rect()
	var font: Font = ThemeDB.fallback_font
	var alpha: float = _show_t
	var cx: float = vp.size.x * 0.5
	var compact: bool = vp.size.y < 860.0

	draw_rect(vp, Color(0.035, 0.055, 0.075))
	_draw_results_backdrop(vp, alpha)

	var outcome_view: Dictionary = _resolved_outcome_presentation()
	var outcome_key: String = str(outcome_view.get("key", "timeout"))
	var out_text: String = str(outcome_view.get("title", "RUN SUMMARY"))
	var out_col: Color = Color(outcome_view.get("accent", C_WARNING))

	draw_rect(Rect2(0.0, 0.0, vp.size.x, 6.0), Color(out_col.r, out_col.g, out_col.b, 0.72 * alpha))

	if _view_mode == ViewMode.AI_ANALYSIS:
		_draw_ai_analysis_view(vp, font, alpha, out_text)
		return

	if _result.is_empty():
		if font != null:
			_draw_results_centered_text(font, "No Result Data", Vector2(cx, vp.size.y * 0.46), 32,
				Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, alpha))
			_draw_results_centered_text(font, "Return to the menu and start a new run.",
				Vector2(cx, vp.size.y * 0.51), 16, Color(C_DIM.r, C_DIM.g, C_DIM.b, alpha))
		_draw_results_nav(cx, vp.size.y * 0.62, font, alpha)
		return

	var container: Rect2 = _content_bounds(vp)
	var content_w: float = container.size.x
	var top_y: float = container.position.y
	var header_h: float = clampf(container.size.y * (0.18 if compact else 0.20), 120.0, 170.0)
	var header: Rect2 = Rect2(container.position.x, top_y, content_w, header_h)
	_draw_results_header(header, out_text, out_col, font, alpha, str(outcome_view.get("subtitle", "")))
	_draw_results_button(_btn_rects[BTN_AI_ANALYSIS], "VIEW AI ANALYSIS", BTN_AI_ANALYSIS == _hover_btn, Color(0.18, 0.84, 1.00), font, alpha)

	var agent_results: Array = _display_ordered_results(_result.get("agent_results", []), outcome_key)
	var block_gap: float = maxf(12.0, container.size.y * 0.015)
	var cards_top: float = header.end.y + block_gap
	var summary_h: float = clampf(container.size.y * 0.13, 86.0, 122.0)
	var nav_h: float = clampf(container.size.y * 0.13, 86.0, 122.0)
	var cards_h: float = maxf(250.0, container.end.y - cards_top - summary_h - nav_h - block_gap * 2.0)
	var cards_rect: Rect2 = Rect2(container.position.x, cards_top, content_w, cards_h)

	var card_gap: float = maxf(14.0, content_w * 0.012)
	var card_w: float = (cards_rect.size.x - card_gap * 2.0) / 3.0
	for i in range(mini(3, agent_results.size())):
		var card_rect: Rect2 = Rect2(
			cards_rect.position.x + float(i) * (card_w + card_gap),
			cards_rect.position.y,
			card_w,
			cards_rect.size.y
		)
		_draw_results_agent_card(Dictionary(agent_results[i]), card_rect, i + 1, font, alpha)

	var footer_y: float = cards_rect.end.y + block_gap
	_draw_results_summary(Rect2(header.position.x, footer_y, content_w, summary_h), outcome_key, font, alpha)
	_draw_results_nav(cx, footer_y + summary_h + block_gap, font, alpha)

func _draw_results_backdrop(vp: Rect2, alpha: float) -> void:
	var line_col := Color(0.75, 0.88, 0.92, 0.035 * alpha)
	var spacing := 80.0
	for ix in range(int(vp.size.x / spacing) + 1):
		draw_line(Vector2(float(ix) * spacing, 0.0), Vector2(float(ix) * spacing, vp.size.y), line_col, 1.0)
	for iy in range(int(vp.size.y / spacing) + 1):
		draw_line(Vector2(0.0, float(iy) * spacing), Vector2(vp.size.x, float(iy) * spacing), line_col, 1.0)

	var col := Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.36 * alpha)
	var margin := 30.0
	var arm := 56.0
	draw_line(Vector2(margin, margin), Vector2(margin + arm, margin), col, 2.0)
	draw_line(Vector2(margin, margin), Vector2(margin, margin + arm), col, 2.0)
	draw_line(Vector2(vp.size.x - margin, margin), Vector2(vp.size.x - margin - arm, margin), col, 2.0)
	draw_line(Vector2(vp.size.x - margin, margin), Vector2(vp.size.x - margin, margin + arm), col, 2.0)
	draw_line(Vector2(margin, vp.size.y - margin), Vector2(margin + arm, vp.size.y - margin), col, 2.0)
	draw_line(Vector2(margin, vp.size.y - margin), Vector2(margin, vp.size.y - margin - arm), col, 2.0)
	draw_line(Vector2(vp.size.x - margin, vp.size.y - margin), Vector2(vp.size.x - margin - arm, vp.size.y - margin), col, 2.0)
	draw_line(Vector2(vp.size.x - margin, vp.size.y - margin), Vector2(vp.size.x - margin, vp.size.y - margin - arm), col, 2.0)

	var scan_y: float = fposmod(_anim_t * 92.0, maxf(1.0, vp.size.y))
	draw_rect(Rect2(0.0, scan_y, vp.size.x, 2.0), Color(0.12, 0.90, 1.0, 0.05 * alpha))

func _draw_results_header(rect: Rect2, outcome_text: String, accent: Color, font: Font, alpha: float, subtitle: String = "") -> void:
	draw_rect(Rect2(rect.position + Vector2(8.0, 10.0), rect.size), Color(0, 0, 0, 0.34 * alpha))
	draw_rect(rect, Color(0.045, 0.075, 0.095, 0.92 * alpha))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 5.0)), Color(accent.r, accent.g, accent.b, alpha))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.36 * alpha), false, 2.0)
	if font == null:
		return

	_draw_results_centered_text(font, outcome_text, Vector2(rect.get_center().x, rect.position.y + 62.0),
		44, Color(accent.r, accent.g, accent.b, alpha))
	if subtitle != "":
		_draw_results_centered_text(font, subtitle,
			Vector2(rect.get_center().x, rect.position.y + 98.0), 18, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.92 * alpha))

	var ticks: int = _result.get("total_ticks", 0)
	var actions: int = _result.get("total_actions", 0)
	var escaped: int = _result.get("escaped_count", 0)
	var captured: int = _result.get("captured_count", 0)
	var metrics := [
		["TICKS", str(ticks)],
		["ACTIONS", str(actions)],
		["ESCAPED", str(escaped)],
		["CAPTURED", str(captured)],
	]
	var box_w := 142.0
	var gap := 18.0
	var total_w := box_w * 4.0 + gap * 3.0
	var x0 := rect.get_center().x - total_w * 0.5
	var y := rect.position.y + 118.0
	for i in range(metrics.size()):
		var r := Rect2(x0 + float(i) * (box_w + gap), y, box_w, 38.0)
		draw_rect(r, Color(0.02, 0.04, 0.05, 0.58 * alpha))
		draw_rect(r, Color(accent.r, accent.g, accent.b, 0.22 * alpha), false)
		_draw_results_centered_text(font, str(metrics[i][0]), Vector2(r.get_center().x, r.position.y + 14.0),
			10, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.72 * alpha))
		_draw_results_centered_text(font, str(metrics[i][1]), Vector2(r.get_center().x, r.position.y + 31.0),
			16, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, alpha))

func _draw_results_agent_card(ar: Dictionary, rect: Rect2, rank: int, font: Font, alpha: float) -> void:
	var role: String = str(ar.get("role", "?"))
	var hp: float = float(ar.get("health", 0.0))
	var stamina: float = float(ar.get("stamina", 0.0))
	var stealth: float = float(ar.get("stealth", 100.0))
	var escaped: bool = bool(ar.get("escaped", false))
	var captured: bool = bool(ar.get("captured", false))
	var eliminated: bool = bool(ar.get("eliminated", false))
	var camera_hits: int = int(ar.get("camera_hits", 0))
	var wall_hits: int = int(ar.get("wall_hits", 0))
	var locked_door_hits: int = int(ar.get("locked_door_hits", 0))
	var dog_latch_engagements: int = int(ar.get("dog_latch_engagements", 0))
	var fire_hits: int = int(ar.get("fire_hits", 0))
	var raw_score: float = float(ar.get("raw_score", 0.0))
	var performance: float = float(ar.get("performance", 0.0))
	var escape_rank: int = int(ar.get("escape_rank", -1))
	var captures_taken: int = int(ar.get("captures", 0))
	var captures_made: int = int(ar.get("captures_made", ar.get("captures", 0)))
	var dog_assists: int = int(ar.get("dog_assists", 0))
	var cctv_assists: int = int(ar.get("cctv_assists", 0))
	var fire_assists: int = int(ar.get("fire_assists", 0))
	var escapes_allowed: int = int(ar.get("escapes_allowed", 0))
	var alert_level: float = float(ar.get("alert_level", 0.0))
	var captures_while_dog_latched: int = int(ar.get("captures_while_dog_latched", 0))
	var captured_while_dog_latched: int = int(ar.get("captured_while_dog_latched", 0))

	var role_col: Color = C_POLICE
	var role_name: String = "Police Hunter"
	var algo: String = "Fuzzy Logic"
	var stamina_max: float = 75.0
	if role == "rusher_red":
		role_col = C_RED_AG
		role_name = "Rusher Red"
		algo = "Minimax"
		stamina_max = 100.0
	elif role == "sneaky_blue":
		role_col = Color(0.18, 1.00, 0.92)
		role_name = "Sneaky Blue"
		algo = "Monte Carlo Search"
		# MINOR #4 FIX: Updated from 50.0 to match new max_stamina=70.
		stamina_max = 70.0

	var delay: float = 0.16 * float(rank - 1)
	var appear: float = clampf((_show_t - delay) / 0.52, 0.0, 1.0)
	var eased: float = appear * appear * (3.0 - 2.0 * appear)
	var card_alpha: float = alpha * eased
	if card_alpha <= 0.001:
		return
	var slide: float = (1.0 - eased) * 28.0
	var card_rect: Rect2 = Rect2(rect.position + Vector2(0.0, slide), rect.size)

	var outcome_key: String = _resolved_outcome_key()
	var winner: bool = (outcome_key == "prisoners_win" and role != "police" and escaped) or (outcome_key == "police_wins" and role == "police")
	var wide_card: bool = rect.size.x > rect.size.y * 1.65
	var pulse: float = 0.5 + 0.5 * sin(_anim_t * 2.8 + float(rank))
	if winner:
		var winner_col: Color = C_HIGHLIGHT if role != "police" else C_POLICE
		draw_rect(card_rect.grow(5.0), Color(winner_col.r, winner_col.g, winner_col.b, (0.18 + pulse * 0.10) * card_alpha), false)
	draw_rect(Rect2(card_rect.position + Vector2(5.0, 7.0), card_rect.size), Color(0, 0, 0, 0.32 * card_alpha))
	draw_rect(card_rect, Color(0.055, 0.085, 0.105, 0.94 * card_alpha))
	draw_rect(Rect2(card_rect.position, Vector2(card_rect.size.x, 6.0)), Color(role_col.r, role_col.g, role_col.b, card_alpha))
	draw_rect(card_rect, Color(role_col.r, role_col.g, role_col.b, 0.34 * card_alpha), false)
	var local_scan: float = card_rect.position.y + fposmod(_anim_t * 60.0 + float(rank) * 42.0, maxf(2.0, card_rect.size.y - 4.0))
	draw_rect(Rect2(card_rect.position.x + 1.0, local_scan, card_rect.size.x - 2.0, 1.5), Color(0.18, 0.95, 1.0, 0.06 * card_alpha))
	if font == null:
		return

	var pad: float = 16.0
	var portrait_w: float = clampf(card_rect.size.x * (0.30 if wide_card else 0.36), 124.0, 250.0)
	var portrait_h: float = card_rect.size.y - 52.0
	var portrait_rect: Rect2 = Rect2(card_rect.position.x + pad, card_rect.position.y + 28.0, portrait_w, portrait_h)
	_draw_results_character_preview(portrait_rect, role, role_col, card_alpha)
	var rank_badge_w: float = clampf(card_rect.size.x * (0.16 if wide_card else 0.24), 112.0, 180.0)
	_draw_results_rank_badge(Rect2(card_rect.position.x + pad, card_rect.position.y + 6.0, rank_badge_w, 34.0), rank, role_col, font, card_alpha)

	var tx: float = portrait_rect.end.x + 14.0
	var tw: float = card_rect.end.x - tx - pad
	var name_size: int = 34 if winner else 28
	var algo_size: int = 13 if winner else 12
	draw_string(font, Vector2(tx, card_rect.position.y + 54.0), role_name,
		HORIZONTAL_ALIGNMENT_LEFT, tw, name_size, Color(role_col.r, role_col.g, role_col.b, card_alpha))
	draw_string(font, Vector2(tx, card_rect.position.y + 80.0), _strategy_label(role),
		HORIZONTAL_ALIGNMENT_LEFT, tw, algo_size, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.88 * card_alpha))

	var status_info: Dictionary = _status_for_card(role, escaped, captured, eliminated, captures_made)
	var status: String = str(status_info.get("text", ""))
	var status_col: Color = Color(status_info.get("color", C_WARNING))
	var status_font: int = 14 if wide_card else 13
	var status_w: float = font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, status_font).x
	var status_rect: Rect2 = Rect2(card_rect.end.x - status_w - pad - 16.0, card_rect.position.y + 28.0, status_w + 14.0, 22.0)
	draw_rect(status_rect, Color(status_col.r, status_col.g, status_col.b, 0.15 * card_alpha))
	draw_rect(status_rect, Color(status_col.r, status_col.g, status_col.b, 0.48 * card_alpha), false)
	draw_string(font, Vector2(status_rect.position.x + 5.0, status_rect.position.y + 13.0), status,
		HORIZONTAL_ALIGNMENT_LEFT, -1, status_font, Color(status_col.r, status_col.g, status_col.b, card_alpha))

	var hp_y: float = card_rect.position.y + 104.0
	var second_y: float = hp_y + 38.0
	var stamina_label: String = "Stamina"
	var stamina_value: float = stamina
	var stamina_limit: float = stamina_max
	if role == "sneaky_blue":
		stamina_label = "Stealth"
		stamina_value = stealth
		stamina_limit = 100.0
	elif role == "police":
		stamina_label = "Alert"
		stamina_value = alert_level * 100.0
		stamina_limit = 100.0
	var shown_raw: int = int(round(raw_score * eased))
	var shown_perf: int = int(round(performance * eased))
	var shown_hp: int = int(round(hp * eased))
	var shown_stm: int = int(round(stamina_value * eased))
	var assist_total: int = dog_assists + cctv_assists + fire_assists
	var pill_gap: float = 10.0
	var pill_w: float = (card_rect.size.x - pad * 2.0 - pill_gap) * 0.5
	_draw_stat_pill(
		Rect2(card_rect.position.x + pad, hp_y, pill_w, 34.0),
		"HP",
		"%d/100" % int(round(hp * eased)),
		Color(0.86, 0.32, 0.30),
		font,
		card_alpha
	)
	_draw_stat_pill(
		Rect2(card_rect.position.x + pad + pill_w + pill_gap, hp_y, pill_w, 34.0),
		stamina_label,
		"%d/%d" % [int(round(stamina_value * eased)), int(round(stamina_limit))],
		Color(0.88, 0.72, 0.22),
		font,
		card_alpha
	)
	_draw_stat_pill(
		Rect2(card_rect.position.x + pad, second_y, pill_w, 30.0),
		"Performance",
		str(shown_perf),
		Color(0.24, 0.90, 0.72),
		font,
		card_alpha
	)
	_draw_stat_pill(
		Rect2(card_rect.position.x + pad + pill_w + pill_gap, second_y, pill_w, 30.0),
		"Raw Score",
		str(shown_raw),
		Color(0.22, 0.86, 1.0),
		font,
		card_alpha
	)

	var chip_rows: int = 2
	var chips_per_row: int = 3
	var chip_gap: float = 8.0
	var chip_h: float = 26.0
	var chips_y0: float = card_rect.end.y - (float(chip_rows) * chip_h + float(chip_rows - 1) * chip_gap) - 14.0
	var chip_w: float = (card_rect.size.x - pad * 2.0 - chip_gap * float(chips_per_row - 1)) / float(chips_per_row)
	var chips: Array[Dictionary] = []
	if role == "police":
		chips.append({"label": "Captures", "value": captures_made, "accent": Color(0.92, 0.84, 0.30)})
		chips.append({"label": "Team Assists", "value": assist_total, "accent": Color(0.42, 0.72, 0.98)})
		chips.append({"label": "Escapes Allowed", "value": escapes_allowed, "accent": Color(0.96, 0.56, 0.36)})
		chips.append({"label": "CCTV Uses", "value": cctv_assists, "accent": Color(0.32, 0.88, 1.0)})
		chips.append({"label": "Tracking Uses", "value": dog_assists, "accent": Color(1.00, 0.72, 0.22)})
		chips.append({"label": "Perf Rank", "value": rank, "accent": Color(0.46, 0.86, 0.72)})
	else:
		chips.append({"label": "CCTV Uses", "value": camera_hits, "accent": Color(0.32, 0.88, 1.0)})
		chips.append({"label": "Dog Uses", "value": dog_latch_engagements, "accent": Color(1.00, 0.72, 0.22)})
		chips.append({"label": "Fire Uses", "value": fire_hits, "accent": Color(1.00, 0.42, 0.22)})
		chips.append({"label": "Wall Breaks", "value": wall_hits, "accent": Color(0.62, 0.72, 0.84)})
		chips.append({"label": "Blocks", "value": locked_door_hits, "accent": Color(0.72, 0.72, 0.82)})
		chips.append({"label": "Escape Rank", "value": maxi(0, escape_rank), "accent": Color(0.46, 0.86, 0.72)})

	for i in range(mini(chips.size(), chip_rows * chips_per_row)):
		var row_idx: int = i / chips_per_row
		var col_idx: int = i % chips_per_row
		var chip_rect: Rect2 = Rect2(
			card_rect.position.x + pad + float(col_idx) * (chip_w + chip_gap),
			chips_y0 + float(row_idx) * (chip_h + chip_gap),
			chip_w,
			chip_h
		)
		var chip_data: Dictionary = Dictionary(chips[i])
		_draw_results_metric_chip(
			chip_rect,
			str(chip_data.get("label", "M")),
			int(chip_data.get("value", 0)),
			Color(chip_data.get("accent", C_TEXT)),
			font,
			card_alpha
		)

func _draw_results_character_preview(rect: Rect2, role: String, accent: Color, alpha: float) -> void:
	draw_rect(rect.grow(2.0), Color(accent.r, accent.g, accent.b, 0.16 * alpha), false)
	draw_rect(rect, Color(0.01, 0.03, 0.05, 0.98 * alpha))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.52 * alpha), false)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3.0)), Color(accent.r, accent.g, accent.b, 0.88 * alpha))
	var bob: float = sin(_anim_t * 2.0 + rect.position.x * 0.01) * 3.0
	var facing_sign: float = 1.0 if sin(_anim_t * 1.15 + rect.position.y * 0.01) >= 0.0 else -1.0
	var inner_rect: Rect2 = rect.grow(-1.0)
	inner_rect.position.y += bob
	CharacterPreview.draw_role(self, inner_rect, role, _anim_t, alpha, facing_sign)

func _draw_results_rank_badge(rect: Rect2, rank: int, accent: Color, font: Font, alpha: float) -> void:
	var pulse: float = 0.72 + 0.28 * (0.5 + 0.5 * sin(_anim_t * 3.2 + float(rank)))
	draw_rect(rect, Color(accent.r * 0.20, accent.g * 0.20, accent.b * 0.20, 0.94 * alpha * pulse))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.64 * alpha), false, 2.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4.0)), Color(accent.r, accent.g, accent.b, 0.95 * alpha))
	if font != null:
		draw_string(font, rect.position + Vector2(8.0, 13.0), "PERF RANK", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, 10, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.90 * alpha))
		var text: String = _rank_ordinal(rank)
		draw_string(font, rect.position + Vector2(8.0, rect.size.y - 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, 18, Color(accent.r, accent.g, accent.b, alpha))

func _draw_results_value_bar(pos: Vector2, width: float, label: String, value: float, max_value: float, color: Color, font: Font, alpha: float) -> void:
	draw_string(font, pos + Vector2(0.0, -10.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.78 * alpha))
	var ratio := clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	var r := Rect2(pos + Vector2(0.0, 4.0), Vector2(width, 18.0))
	draw_rect(r, Color(0.02, 0.04, 0.05, 0.82 * alpha))
	draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)), Color(color.r, color.g, color.b, 0.88 * alpha))
	draw_rect(r, Color(1, 1, 1, 0.12 * alpha), false)
	var value_text := "%d/%d" % [int(value), int(max_value)]
	var value_w := font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, Vector2(r.end.x - value_w, pos.y - 8.0), value_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.88 * alpha))

func _draw_results_metric_chip(rect: Rect2, label: String, value: int, accent: Color, font: Font, alpha: float) -> void:
	draw_rect(rect, Color(0.02, 0.04, 0.05, 0.84 * alpha))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.34 * alpha), false)
	if font != null:
		draw_string(font, rect.position + Vector2(6.0, 11.0), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, 10, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.86 * alpha))
		draw_string(font, rect.position + Vector2(6.0, rect.size.y - 5.0), str(value), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, 14, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.96 * alpha))

func _draw_stat_pill(rect: Rect2, label: String, value_text: String, accent: Color, font: Font, alpha: float) -> void:
	draw_rect(rect, Color(0.03, 0.06, 0.09, 0.92 * alpha))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.44 * alpha), false)
	if font == null:
		return
	draw_string(font, rect.position + Vector2(8.0, 12.0), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, 11, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.90 * alpha))
	draw_string(font, rect.position + Vector2(8.0, rect.size.y - 8.0), value_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, 17, Color(accent.r, accent.g, accent.b, 0.98 * alpha))

func _draw_results_summary(rect: Rect2, outcome: String, font: Font, alpha: float) -> void:
	draw_rect(rect, Color(0.045, 0.075, 0.095, 0.70 * alpha))
	draw_rect(rect, Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.20 * alpha), false)
	if font == null:
		return
	var presentation: Dictionary = _resolved_outcome_presentation()
	var verdict: String = str(presentation.get("title", "RUN SUMMARY"))
	_draw_results_centered_text(font, "FINAL VERDICT: %s" % verdict, Vector2(rect.get_center().x, rect.position.y + 26.0),
		20, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.94 * alpha))
	var escaped: int = int(_result.get("escaped_count", 0))
	var captured: int = int(_result.get("captured_count", 0))
	var burned: int = int(_result.get("eliminated_count", 0))
	var prisoner_total: int = _prisoner_total_count()
	var status_line: String = "%d/%d escaped  ·  %d capture events" % [escaped, prisoner_total, captured]
	if burned > 0:
		status_line += "  ·  %d burned" % burned
	_draw_results_centered_text(font, status_line, Vector2(rect.get_center().x, rect.position.y + 48.0),
		16, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.92 * alpha))

	var red: Dictionary = _agent_result_for_role("rusher_red")
	var blue: Dictionary = _agent_result_for_role("sneaky_blue")
	var police: Dictionary = _agent_result_for_role("police")
	var red_status: String = str(_status_for_card("rusher_red", bool(red.get("escaped", false)), bool(red.get("captured", false)), bool(red.get("eliminated", false)), int(red.get("captures_made", 0))).get("text", "-"))
	var blue_status: String = str(_status_for_card("sneaky_blue", bool(blue.get("escaped", false)), bool(blue.get("captured", false)), bool(blue.get("eliminated", false)), int(blue.get("captures_made", 0))).get("text", "-"))
	var police_status: String = str(_status_for_card("police", bool(police.get("escaped", false)), bool(police.get("captured", false)), bool(police.get("eliminated", false)), int(police.get("captures_made", 0))).get("text", "-"))
	_draw_results_centered_text(font, "Red: %s   ·   Blue: %s   ·   Hunter: %s" % [red_status, blue_status, police_status], Vector2(rect.get_center().x, rect.position.y + 68.0),
		14, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.88 * alpha))

	var ranked: Array = _ranked_results(_result.get("agent_results", []))
	if ranked.size() >= 3:
		var r0: Dictionary = ranked[0]
		var r1: Dictionary = ranked[1]
		var r2: Dictionary = ranked[2]
		var line := "Performance Rank: 1) %s %d   ·   2) %s %d   ·   3) %s %d" % [
			_role_short(str(r0.get("role", "?"))), int(float(r0.get("performance", 0.0))),
			_role_short(str(r1.get("role", "?"))), int(float(r1.get("performance", 0.0))),
			_role_short(str(r2.get("role", "?"))), int(float(r2.get("performance", 0.0))),
		]
		_draw_results_centered_text(font, line, Vector2(rect.get_center().x, rect.position.y + 88.0), 14, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.86 * alpha))
	_draw_results_centered_text(font, "Tip: Open AI Analysis to review why each controller made its final move.",
		Vector2(rect.get_center().x, rect.position.y + 108.0), 13, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.74 * alpha))

func _draw_ai_analysis_view(vp: Rect2, font: Font, alpha: float, outcome_text: String) -> void:
	var container: Rect2 = _content_bounds(vp)
	var cx: float = container.get_center().x
	var header_h: float = clampf(container.size.y * (0.18 if vp.size.y < 860.0 else 0.20), 120.0, 168.0)
	var header_rect: Rect2 = Rect2(container.position.x, container.position.y, container.size.x, header_h)
	var accent: Color = Color(0.22, 0.86, 1.0)

	draw_rect(Rect2(header_rect.position + Vector2(8.0, 9.0), header_rect.size), Color(0, 0, 0, 0.32 * alpha))
	draw_rect(header_rect, Color(0.045, 0.075, 0.095, 0.94 * alpha))
	draw_rect(Rect2(header_rect.position, Vector2(header_rect.size.x, 5.0)), accent)
	draw_rect(header_rect, Color(accent.r, accent.g, accent.b, 0.33 * alpha), false, 2.0)

	_draw_results_button(_btn_rects[BTN_BACK_RESULTS], "BACK TO RESULTS", BTN_BACK_RESULTS == _hover_btn, C_WARNING, font, alpha)

	if font != null:
		_draw_results_centered_text(font, "AI DECISION ANALYSIS", Vector2(cx, header_rect.position.y + 48.0), 42, accent)
		_draw_results_centered_text(font, "How Minimax, Monte Carlo, and Fuzzy Logic competed this match", Vector2(cx, header_rect.position.y + 78.0), 16, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.95 * alpha))
		_draw_results_centered_text(font, "Outcome: %s" % outcome_text, Vector2(cx, header_rect.position.y + 102.0), 15, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.92 * alpha))

	var ticks: int = int(_result.get("total_ticks", 0))
	var actions: int = int(_result.get("total_actions", 0))
	var escaped: int = int(_result.get("escaped_count", 0))
	var captured: int = int(_result.get("captured_count", 0))
	var chips: Array = [
		["TICKS", str(ticks)],
		["ACTIONS", str(actions)],
		["ESCAPED", str(escaped)],
		["CAPTURED", str(captured)],
	]
	var chip_w: float = clampf(header_rect.size.x * 0.135, 118.0, 196.0)
	var chip_h: float = 32.0
	var chip_gap: float = maxf(12.0, header_rect.size.x * 0.012)
	var total_chip_w: float = chip_w * 4.0 + chip_gap * 3.0
	var chip_x0: float = cx - total_chip_w * 0.5
	var chip_y: float = header_rect.end.y - chip_h - 10.0
	for i in range(chips.size()):
		var chip_rect: Rect2 = Rect2(chip_x0 + float(i) * (chip_w + chip_gap), chip_y, chip_w, chip_h)
		draw_rect(chip_rect, Color(0.02, 0.04, 0.05, 0.82 * alpha))
		draw_rect(chip_rect, Color(accent.r, accent.g, accent.b, 0.28 * alpha), false)
		_draw_results_centered_text(font, str(chips[i][0]), Vector2(chip_rect.get_center().x, chip_rect.position.y + 13.0), 10, C_DIM)
		_draw_results_centered_text(font, str(chips[i][1]), Vector2(chip_rect.get_center().x, chip_rect.position.y + 27.0), 12, C_TEXT)

	_draw_analysis_tab(_btn_rects[BTN_TAB_RED], "RED MINIMAX", _analysis_role == "rusher_red", C_RED_AG, font, alpha)
	_draw_analysis_tab(_btn_rects[BTN_TAB_BLUE], "BLUE MCTS", _analysis_role == "sneaky_blue", Color(0.18, 1.00, 0.92), font, alpha)
	_draw_analysis_tab(_btn_rects[BTN_TAB_POLICE], "POLICE FUZZY", _analysis_role == "police", C_POLICE, font, alpha)

	var main_top: float = _btn_rects[BTN_TAB_RED].end.y + maxf(10.0, container.size.y * 0.012)
	var nav_top: float = _btn_rects[BTN_REPLAY].position.y
	var main_rect: Rect2 = Rect2(container.position.x, main_top, container.size.x, maxf(440.0, nav_top - main_top - 12.0))
	draw_rect(main_rect, Color(0.04, 0.07, 0.11, 0.82 * alpha))
	draw_rect(main_rect, Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.24 * alpha), false)

	var analysis_data: Dictionary = _analysis_role_data(_analysis_role)
	var selected_decision: Dictionary = Dictionary(analysis_data.get("selected_decision", {}))
	var selected_note: String = str(analysis_data.get("selected_decision_note", ""))
	var timeline: Array = Array(analysis_data.get("timeline", []))
	var chosen_from_timeline: bool = false
	var resolved_decision: Dictionary = _resolve_selected_decision_for_view(_analysis_role, selected_decision, timeline)
	if not resolved_decision.is_empty() and resolved_decision != selected_decision:
		chosen_from_timeline = true
		selected_decision = resolved_decision
		selected_note = "Using latest visualizable decision (T%d)" % int(selected_decision.get("tick", -1))
	else:
		selected_decision = resolved_decision
	var agent_name: String = str(analysis_data.get("agent_name", _role_short(_analysis_role)))
	var algo: String = str(analysis_data.get("algorithm", "AI"))
	var role_color: Color = _analysis_role_color(_analysis_role)

	# ── Decision tick context ────────────────────────────────────────────────────
	# Extract tick metadata so the examiner knows how representative the tree is.
	# A decision from tick 12 in a 180-tick match is nearly meaningless on its own.
	var decision_tick: int  = int(selected_decision.get("tick", -1))
	var total_ticks: int    = int(_result.get("total_ticks", 0))
	var tick_pct: float     = 100.0 * float(decision_tick) / maxf(float(total_ticks), 1.0) if decision_tick >= 0 else -1.0
	# Positional context: where was the agent, where was the exit, where was police
	var agent_tile: Vector2i  = Vector2i(selected_decision.get("current_tile", Vector2i(-1, -1)))
	var chosen_tile_ctx: Vector2i = Vector2i(selected_decision.get("chosen_tile", Vector2i(-1, -1)))
	# Police position is stored differently per algorithm
	var police_tile: Vector2i = Vector2i(selected_decision.get("police_tile",
		selected_decision.get("police_pos", Vector2i(-1, -1))))
	var exit_tile_ctx: Vector2i = Vector2i(selected_decision.get("exit_tile", Vector2i(-1, -1)))

	if font != null:
		draw_string(font, main_rect.position + Vector2(18.0, 30.0), "%s — %s" % [agent_name, algo], HORIZONTAL_ALIGNMENT_LEFT, -1, 25, role_color)
		draw_string(font, main_rect.position + Vector2(18.0, 52.0), selected_note, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.90 * alpha))
		if chosen_from_timeline:
			draw_string(font, main_rect.position + Vector2(430.0, 52.0), "(auto-picked from timeline)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(C_WARNING.r, C_WARNING.g, C_WARNING.b, 0.86 * alpha))

		# Tick context line — shown prominently so examiner can judge representativeness
		if decision_tick >= 0:
			var tick_line: String
			if tick_pct >= 0.0:
				tick_line = "Decision from tick T%d / %d  (%.0f%% through match)" % [decision_tick, total_ticks, tick_pct]
			else:
				tick_line = "Decision from tick T%d" % decision_tick
			_draw_results_centered_text(font, tick_line,
				Vector2(main_rect.get_center().x, main_rect.position.y + 52.0), 14,
				Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.96 * alpha))

		# Positional context line — agent tile, exit, police so examiner can read the tree
		var ctx_parts: Array = []
		if agent_tile.x >= 0:
			ctx_parts.append("Agent %s" % _tile_str(agent_tile))
		if exit_tile_ctx.x >= 0:
			ctx_parts.append("Exit %s" % _tile_str(exit_tile_ctx))
		if police_tile.x >= 0:
			ctx_parts.append("Police %s" % _tile_str(police_tile))
		if ctx_parts.size() > 0:
			var ctx_line: String = "  ·  ".join(ctx_parts)
			_draw_results_centered_text(font, ctx_line,
				Vector2(main_rect.get_center().x, main_rect.position.y + 69.0), 12,
				Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.88 * alpha))

	var decision_rect: Rect2 = Rect2(main_rect.position.x + 12.0, main_rect.position.y + 82.0, main_rect.size.x * 0.68 - 18.0, main_rect.size.y - 94.0)
	var timeline_rect: Rect2 = Rect2(decision_rect.end.x + 10.0, main_rect.position.y + 82.0, main_rect.end.x - decision_rect.end.x - 22.0, main_rect.size.y - 94.0)
	draw_rect(decision_rect, Color(0.01, 0.03, 0.05, 0.95 * alpha))
	draw_rect(decision_rect, Color(role_color.r, role_color.g, role_color.b, 0.28 * alpha), false)
	draw_rect(timeline_rect, Color(0.01, 0.03, 0.05, 0.95 * alpha))
	draw_rect(timeline_rect, Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.28 * alpha), false)

	match _analysis_role:
		"rusher_red":
			_draw_minimax_analysis(decision_rect, selected_decision, font, alpha)
		"sneaky_blue":
			_draw_mcts_analysis(decision_rect, selected_decision, font, alpha)
		_:
			_draw_fuzzy_analysis(decision_rect, selected_decision, font, alpha)

	_timeline_rect = timeline_rect
	_draw_decision_timeline(timeline_rect, timeline, font, alpha)
	_draw_results_nav(container.get_center().x, _btn_rects[BTN_REPLAY].position.y, font, alpha)

func _draw_analysis_tab(rect: Rect2, label: String, selected: bool, accent: Color, font: Font, alpha: float) -> void:
	if rect.size == Vector2.ZERO:
		return
	var pulse: float = 0.65 + 0.35 * (0.5 + 0.5 * sin(_anim_t * 3.2))
	draw_rect(rect, Color(accent.r * 0.15, accent.g * 0.15, accent.b * 0.15, (0.96 if selected else 0.62) * alpha))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, (0.86 * pulse if selected else 0.34) * alpha), false, 2.0)
	if selected:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4.0)), Color(accent.r, accent.g, accent.b, alpha))
		draw_rect(rect.grow(2.0), Color(accent.r, accent.g, accent.b, 0.24 * alpha), false)
	if font != null:
		_draw_results_centered_text(font, label, Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.62), 14, Color(accent.r, accent.g, accent.b, 0.98 * alpha))

func _analysis_role_data(role: String) -> Dictionary:
	var ai_analysis: Dictionary = Dictionary(_result.get("ai_analysis", {}))
	var by_role: Dictionary = Dictionary(ai_analysis.get("by_role", {}))
	return Dictionary(by_role.get(role, {}))

func _analysis_role_color(role: String) -> Color:
	match role:
		"rusher_red":
			return C_RED_AG
		"sneaky_blue":
			return Color(0.18, 1.00, 0.92)
		_:
			return C_POLICE

func _resolve_selected_decision_for_view(role: String, selected_decision: Dictionary, timeline: Array) -> Dictionary:
	if _decision_is_visualizable(role, selected_decision):
		return selected_decision
	for i in range(timeline.size() - 1, -1, -1):
		var item: Dictionary = Dictionary(timeline[i])
		if _decision_is_visualizable(role, item):
			return item
	return selected_decision

func _decision_is_visualizable(role: String, decision: Dictionary) -> bool:
	if decision.is_empty():
		return false
	if role == "police":
		var behavior: String = str(decision.get("chosen_behavior", "")).strip_edges()
		return not Array(decision.get("rules", [])).is_empty() or behavior != ""
	return not Array(decision.get("candidates", [])).is_empty()

func _draw_minimax_analysis(rect: Rect2, decision: Dictionary, font: Font, alpha: float) -> void:
	if font == null:
		return
	var root_tile: Vector2i = Vector2i(decision.get("current_tile", Vector2i(-1, -1)))
	var chosen_tile: Vector2i = Vector2i(decision.get("chosen_tile", Vector2i(-1, -1)))
	var reason: String = str(decision.get("reason", "Not recorded"))
	var candidates: Array = Array(decision.get("candidates", []))
	var root_rect: Rect2 = Rect2(rect.position.x + rect.size.x * 0.5 - 150.0, rect.position.y + 16.0, 300.0, 76.0)
	_draw_tree_node(root_rect, "ROOT NODE", "Red @ %s" % _tile_str(root_tile), C_RED_AG, font, alpha, true)
	var exit_distance: int = int(decision.get("exit_distance", -1))
	var police_distance: int = int(decision.get("police_distance", -1))
	_draw_results_centered_text(font, "Minimax (4-ply):  Root → Red moves → Police response → Leaf", Vector2(rect.get_center().x, root_rect.end.y + 16.0), 12, C_DIM)
	_draw_results_centered_text(font, "Exit %d   •   Police %d   •   Branches %d" % [exit_distance, police_distance, candidates.size()], Vector2(rect.get_center().x, root_rect.end.y + 34.0), 11, C_DIM)

	var count: int = mini(5, candidates.size())
	if count <= 0:
		draw_string(font, rect.position + Vector2(16.0, 96.0), "No minimax candidates recorded", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_DIM)
		draw_string(font, rect.position + Vector2(16.0, 118.0), reason, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 12, C_TEXT)
		return

	var spacing: float = (rect.size.x - 38.0) / float(count)
	var candidate_y: float = rect.position.y + 126.0
	var candidate_h: float = 82.0
	# Police response row sits between the Red move nodes and the leaf scores
	var police_y: float = candidate_y + candidate_h + 12.0
	var police_h: float = 54.0
	var leaf_y: float = police_y + police_h + 10.0
	var leaf_h: float = 44.0

	# Legend
	var legend_rect: Rect2 = Rect2(rect.position.x + 14.0, rect.end.y - 76.0, rect.size.x - 28.0, 22.0)
	draw_rect(legend_rect, Color(0.03, 0.06, 0.10, 0.86 * alpha))
	draw_rect(legend_rect, Color(0.32, 0.44, 0.58, 0.28 * alpha), false)
	draw_string(font, legend_rect.position + Vector2(8.0, 16.0), "Legend: Root → Red move nodes → Police response (orange=worst for Red) → Leaf  |  Green = chosen path", HORIZONTAL_ALIGNMENT_LEFT, legend_rect.size.x - 12.0, 10, C_DIM)

	for i in range(count):
		var c: Dictionary = Dictionary(candidates[i])
		var node_rect: Rect2 = Rect2(rect.position.x + 14.0 + spacing * float(i), candidate_y, spacing - 12.0, candidate_h)
		var is_chosen: bool = bool(c.get("chosen", false)) or Vector2i(c.get("tile", Vector2i(-1, -1))) == chosen_tile
		var risk_label: String = str(c.get("risk", "LOW"))
		var risk_col: Color = Color(0.62, 0.72, 0.84)
		if risk_label == "HIGH":
			risk_col = Color(0.96, 0.34, 0.28)
		elif risk_label == "MED":
			risk_col = Color(0.92, 0.68, 0.28)
		var ac: Color = C_HIGHLIGHT if is_chosen else risk_col
		_draw_tree_link(Vector2(root_rect.get_center().x, root_rect.end.y), Vector2(node_rect.get_center().x, node_rect.position.y), ac, 3.0 if is_chosen else 2.0, alpha)
		_draw_tree_node(
			node_rect,
			str(c.get("action", "MOVE")),
			"Tile %s | S %.0f | %s" % [_tile_str(Vector2i(c.get("tile", Vector2i(-1, -1)))), float(c.get("score", 0.0)), risk_label],
			ac, font, alpha, is_chosen
		)

		# ── Police response row ─────────────────────────────────────────────────
		# Shows the minimizer's best counter-move for each Red candidate.
		# Orange border = worst-for-Red response (the one minimax actually assumes).
		var responses: Array = Array(c.get("police_responses", []))
		var police_node_rect: Rect2 = Rect2(node_rect.position.x, police_y, node_rect.size.x, police_h)
		if responses.size() > 0:
			var resp: Dictionary = Dictionary(responses[0])  # worst for Red = first after ascending sort
			var r_score: float = float(resp.get("score", 0.0))
			var is_worst: bool = bool(resp.get("is_worst", true))
			var r_col: Color = Color(1.0, 0.55, 0.15) if is_worst else Color(0.55, 0.64, 0.74)
			_draw_tree_link(Vector2(node_rect.get_center().x, node_rect.end.y), Vector2(police_node_rect.get_center().x, police_node_rect.position.y), r_col, 2.0 if is_chosen else 1.5, alpha)
			draw_rect(police_node_rect, Color(0.08, 0.04, 0.02, 0.95 * alpha))
			draw_rect(police_node_rect, Color(r_col.r, r_col.g, r_col.b, (0.80 if is_worst else 0.38) * alpha), false, 2.0)
			draw_rect(Rect2(police_node_rect.position, Vector2(police_node_rect.size.x, 3.0)), Color(r_col.r, r_col.g, r_col.b, 0.85 * alpha))
			draw_string(font, police_node_rect.position + Vector2(6.0, 16.0), "POLICE COUNTERS" if is_worst else "Police responds", HORIZONTAL_ALIGNMENT_LEFT, police_node_rect.size.x - 8.0, 9, Color(r_col.r, r_col.g, r_col.b, 0.98 * alpha))
			var r_tile_str: String = _tile_str(Vector2i(resp.get("tile", Vector2i(-1,-1))))
			draw_string(font, police_node_rect.position + Vector2(6.0, 30.0), "→ %s  score %.0f" % [r_tile_str, r_score], HORIZONTAL_ALIGNMENT_LEFT, police_node_rect.size.x - 8.0, 10, C_TEXT)
			if is_worst:
				draw_string(font, police_node_rect.position + Vector2(6.0, 45.0), "worst for Red (α-β)", HORIZONTAL_ALIGNMENT_LEFT, police_node_rect.size.x - 8.0, 9, Color(1.0, 0.55, 0.15, 0.80 * alpha))
		else:
			# No response data — show pruned indicator
			_draw_dashed_line(node_rect.get_center(), police_node_rect.get_center(), Color(0.40, 0.44, 0.50, 0.35 * alpha), 1.5, 6.0)
			draw_rect(police_node_rect, Color(0.06, 0.06, 0.08, 0.70 * alpha))
			draw_rect(police_node_rect, Color(0.30, 0.34, 0.40, 0.28 * alpha), false)
			draw_string(font, police_node_rect.position + Vector2(6.0, 22.0), "α-β pruned", HORIZONTAL_ALIGNMENT_LEFT, police_node_rect.size.x - 8.0, 10, C_DIM)

		# ── Leaf score ──────────────────────────────────────────────────────────
		var leaf_rect: Rect2 = Rect2(node_rect.position.x + 4.0, leaf_y, node_rect.size.x - 8.0, leaf_h)
		if is_chosen:
			_draw_tree_link(Vector2(police_node_rect.get_center().x, police_node_rect.end.y), Vector2(leaf_rect.get_center().x, leaf_rect.position.y), C_HIGHLIGHT, 2.5, alpha)
			_draw_tree_leaf(leaf_rect, "Chosen leaf", "%.0f" % float(c.get("score", 0.0)), C_HIGHLIGHT, font, alpha)
		else:
			_draw_dashed_line(police_node_rect.get_center(), leaf_rect.get_center(), Color(0.56, 0.62, 0.70, 0.40 * alpha), 1.5, 7.0)
			_draw_tree_leaf(leaf_rect, "Leaf", "%.0f" % float(c.get("score", 0.0)), Color(0.55, 0.64, 0.74), font, alpha)

	draw_string(font, rect.position + Vector2(16.0, rect.end.y - 52.0), "Why chosen", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0, 11, C_DIM)
	draw_string(font, rect.position + Vector2(16.0, rect.end.y - 38.0), reason if reason != "" else "reason not recorded", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0, 12, C_TEXT)

func _draw_mcts_analysis(rect: Rect2, decision: Dictionary, font: Font, alpha: float) -> void:
	if font == null:
		return
	var root_tile: Vector2i = Vector2i(decision.get("current_tile", Vector2i(-1, -1)))
	var reason: String = str(decision.get("reason", "Not recorded"))
	var rollouts: int = int(decision.get("rollouts", 0))
	var candidates: Array = Array(decision.get("candidates", []))
	var root_rect: Rect2 = Rect2(rect.position.x + rect.size.x * 0.5 - 150.0, rect.position.y + 16.0, 300.0, 76.0)
	_draw_tree_node(root_rect, "ROOT NODE", "Blue @ %s | Rollouts %d" % [_tile_str(root_tile), rollouts], Color(0.18, 1.00, 0.92), font, alpha, true)
	_draw_results_centered_text(font, "MCTS selects moves by UCT = exploit (reward) + explore (bonus)", Vector2(rect.get_center().x, root_rect.end.y + 16.0), 12, C_DIM)

	var count: int = mini(5, candidates.size())
	if count <= 0:
		draw_string(font, rect.position + Vector2(16.0, 94.0), "No MCTS candidates recorded", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_DIM)
		draw_string(font, rect.position + Vector2(16.0, 116.0), reason, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 12, C_TEXT)
		return
	var spacing: float = (rect.size.x - 38.0) / float(count)
	var y: float = rect.position.y + 126.0
	var node_h: float = 165.0  # taller to fit UCT breakdown bars + rollout outcome badge
	var max_visits: int = 1
	var max_uct: float = 0.001
	for c_var in candidates:
		var c_dict: Dictionary = Dictionary(c_var)
		max_visits = maxi(max_visits, int(c_dict.get("visits", 0)))
		max_uct = maxf(max_uct, float(c_dict.get("uct_total", float(c_dict.get("ucb", 0.0)))))

	for i in range(count):
		var c: Dictionary = Dictionary(candidates[i])
		var node_rect: Rect2 = Rect2(rect.position.x + 14.0 + spacing * float(i), y, spacing - 12.0, node_h)
		var is_chosen: bool = bool(c.get("chosen", false))
		var ac: Color = Color(0.18, 1.00, 0.92) if is_chosen else Color(0.49, 0.68, 0.80)
		_draw_tree_link(Vector2(root_rect.get_center().x, root_rect.end.y), Vector2(node_rect.get_center().x, node_rect.position.y), ac, 3.0 if is_chosen else 2.0, alpha)
		draw_rect(node_rect, Color(0.02, 0.05, 0.08, 0.96 * alpha))
		draw_rect(node_rect, Color(ac.r, ac.g, ac.b, (0.80 if is_chosen else 0.32) * alpha), false, 2.0)
		var visits: int = int(c.get("visits", 0))
		var avg_reward: float = float(c.get("avg_reward", 0.0))
		var uct_exploit: float = float(c.get("uct_exploit", avg_reward))
		var uct_explore: float = float(c.get("uct_explore", 0.0))
		var uct_total: float = float(c.get("uct_total", float(c.get("ucb", 0.0))))
		var visit_ratio: float = clampf(float(visits) / float(max_visits), 0.0, 1.0)
		var reward_ratio: float = clampf((avg_reward + 1.0) * 0.5, 0.0, 1.0)

		# Action label + tile
		draw_string(font, node_rect.position + Vector2(8.0, 16.0), str(c.get("action", "MOVE")), HORIZONTAL_ALIGNMENT_LEFT, node_rect.size.x - 10.0, 12, Color(ac.r, ac.g, ac.b, 0.98 * alpha))
		draw_string(font, node_rect.position + Vector2(8.0, 30.0), "Tile %s" % _tile_str(Vector2i(c.get("tile", Vector2i(-1, -1)))), HORIZONTAL_ALIGNMENT_LEFT, node_rect.size.x - 10.0, 10, C_TEXT)

		# Visit bar
		draw_string(font, node_rect.position + Vector2(8.0, 46.0), "Visits %d" % visits, HORIZONTAL_ALIGNMENT_LEFT, node_rect.size.x - 10.0, 10, C_TEXT)
		draw_rect(Rect2(node_rect.position.x + 8.0, node_rect.position.y + 50.0, node_rect.size.x - 16.0, 8.0), Color(0.08, 0.12, 0.16, 0.95))
		draw_rect(Rect2(node_rect.position.x + 8.0, node_rect.position.y + 50.0, (node_rect.size.x - 16.0) * visit_ratio, 8.0), Color(0.20, 0.86, 1.0, 0.88))

		# Avg reward bar
		draw_string(font, node_rect.position + Vector2(8.0, 70.0), "Avg Reward %.2f" % avg_reward, HORIZONTAL_ALIGNMENT_LEFT, node_rect.size.x - 10.0, 10, C_TEXT)
		draw_rect(Rect2(node_rect.position.x + 8.0, node_rect.position.y + 74.0, node_rect.size.x - 16.0, 8.0), Color(0.08, 0.12, 0.16, 0.95))
		draw_rect(Rect2(node_rect.position.x + 8.0, node_rect.position.y + 74.0, (node_rect.size.x - 16.0) * reward_ratio, 8.0), Color(0.18, 1.00, 0.66, 0.88))

		# UCT breakdown: stacked exploit (blue) + explore (green) bars
		# This directly answers "why was this chosen over a more-visited branch?"
		var bar_w: float = node_rect.size.x - 16.0
		var total_ratio: float  = clampf(uct_total  / max_uct, 0.0, 1.0) if max_uct > 0.0 else 0.0
		var exploit_ratio: float = total_ratio * (uct_exploit / maxf(uct_total, 0.0001))
		var explore_ratio: float = total_ratio * (uct_explore / maxf(uct_total, 0.0001))
		draw_string(font, node_rect.position + Vector2(8.0, 94.0), "UCT = exploit + explore", HORIZONTAL_ALIGNMENT_LEFT, node_rect.size.x - 10.0, 9, Color(0.80, 0.88, 1.0, 0.90 * alpha))
		# Background
		draw_rect(Rect2(node_rect.position.x + 8.0, node_rect.position.y + 98.0, bar_w, 10.0), Color(0.06, 0.08, 0.12, 0.95))
		# Exploit portion (blue)
		draw_rect(Rect2(node_rect.position.x + 8.0, node_rect.position.y + 98.0, bar_w * exploit_ratio, 10.0), Color(0.20, 0.50, 1.0, 0.90))
		# Explore portion stacked on top of exploit (green)
		var explore_start_x: float = node_rect.position.x + 8.0 + bar_w * exploit_ratio
		draw_rect(Rect2(explore_start_x, node_rect.position.y + 98.0, bar_w * explore_ratio, 10.0), Color(0.18, 0.90, 0.44, 0.90))
		# Total UCT label
		draw_string(font, node_rect.position + Vector2(8.0, 121.0), "%.2f exploit + %.2f explore = %.2f" % [uct_exploit, uct_explore, uct_total], HORIZONTAL_ALIGNMENT_LEFT, node_rect.size.x - 10.0, 9, C_TEXT)

		# Rollout outcome badge — gives examiner instant understanding of what each branch modelled
		var rollout_outcome: String = str(c.get("rollout_outcome", ""))
		var rollout_summary: String = str(c.get("rollout_summary", ""))
		var badge_color: Color
		var badge_text: String = ""
		if rollout_outcome == "escaped":
			badge_color = Color(0.18, 0.90, 0.44)
			badge_text = "✓ Escaped"
		elif rollout_outcome == "caught":
			badge_color = Color(0.96, 0.28, 0.28)
			badge_text = "✗ Caught"
		elif rollout_outcome == "timed_out":
			badge_color = Color(0.55, 0.60, 0.68)
			badge_text = "~ Timeout"
		if badge_text != "":
			var badge_rect: Rect2 = Rect2(node_rect.position.x + 4.0, node_rect.position.y + 126.0, node_rect.size.x - 8.0, 14.0)
			draw_rect(badge_rect, Color(badge_color.r * 0.25, badge_color.g * 0.25, badge_color.b * 0.25, 0.92 * alpha))
			draw_rect(badge_rect, Color(badge_color.r, badge_color.g, badge_color.b, 0.72 * alpha), false)
			_draw_results_centered_text(font, badge_text, badge_rect.get_center() + Vector2(0.0, 5.0), 9, Color(badge_color.r, badge_color.g, badge_color.b, 0.98 * alpha))
		if rollout_summary != "":
			draw_string(font, Vector2(node_rect.position.x + 4.0, node_rect.end.y + 14.0), rollout_summary, HORIZONTAL_ALIGNMENT_LEFT, node_rect.size.x + 20.0, 9, C_DIM)

		# Risk + chosen annotation
		draw_string(font, node_rect.position + Vector2(8.0, 137.0), "Risk %s" % str(c.get("danger", "LOW")), HORIZONTAL_ALIGNMENT_LEFT, node_rect.size.x - 10.0, 9, C_DIM)
		if is_chosen:
			draw_rect(node_rect.grow(2.0), Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, 0.22 * alpha), false)
			draw_string(font, Vector2(node_rect.position.x + 8.0, node_rect.end.y + 14.0), "Chosen: highest UCT", HORIZONTAL_ALIGNMENT_LEFT, node_rect.size.x + 10.0, 10, C_HIGHLIGHT)

	draw_string(font, rect.position + Vector2(16.0, rect.end.y - 36.0), "Why chosen", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 11, C_DIM)
	draw_string(font, rect.position + Vector2(16.0, rect.end.y - 16.0), reason if reason != "" else "reason not recorded", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 12, C_TEXT)


func _draw_tree_node(rect: Rect2, title: String, subtitle: String, accent: Color, font: Font, alpha: float, selected: bool) -> void:
	draw_rect(rect, Color(0.03, 0.06, 0.10, 0.95 * alpha))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, (0.80 if selected else 0.38) * alpha), false, 2.0)
	if selected:
		draw_rect(rect.grow(2.0), Color(accent.r, accent.g, accent.b, 0.18 * alpha), false)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4.0)), Color(accent.r, accent.g, accent.b, 0.90 * alpha))
	draw_string(font, rect.position + Vector2(8.0, 22.0), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, 12, Color(accent.r, accent.g, accent.b, 0.98 * alpha))
	draw_string(font, rect.position + Vector2(8.0, 43.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, 10, C_TEXT)

func _draw_tree_leaf(rect: Rect2, title: String, score_text: String, accent: Color, font: Font, alpha: float) -> void:
	draw_rect(rect, Color(0.08, 0.04, 0.05, 0.90 * alpha))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.44 * alpha), false)
	_draw_results_centered_text(font, title, Vector2(rect.get_center().x, rect.position.y + 16.0), 10, C_DIM)
	_draw_results_centered_text(font, score_text, Vector2(rect.get_center().x, rect.position.y + 34.0), 12, Color(accent.r, accent.g, accent.b, 0.98 * alpha))

func _draw_tree_link(from_pos: Vector2, to_pos: Vector2, accent: Color, thickness: float, alpha: float) -> void:
	draw_line(from_pos, to_pos, Color(accent.r, accent.g, accent.b, 0.76 * alpha), thickness)
	_draw_arrow(from_pos, to_pos, Color(accent.r, accent.g, accent.b, 0.50 * alpha), 9.0)

func _draw_fuzzy_analysis(rect: Rect2, decision: Dictionary, font: Font, alpha: float) -> void:
	if font == null:
		return
	var behavior: String = str(decision.get("chosen_behavior", "PATROL"))
	var target_agent: String = str(decision.get("target_agent", "Unknown"))
	var reason: String = str(decision.get("reason", "Not recorded"))
	var inputs: Dictionary = Dictionary(decision.get("inputs", {}))
	var rules: Array = Array(decision.get("rules", []))
	var chosen_color: Color = Color(0.20, 0.90, 1.0) if target_agent.find("Blue") >= 0 else C_RED_AG
	var behavior_color: Color = _behavior_color(behavior)

	# MAJOR #2 FIX: Draw a real police decision tree using the full fuzzy data
	# now emitted by fuzzy_controller.gd (chase/intercept/investigate/patrol scores
	# plus red/blue target scores). Previously only one fake rule was available.

	# -- Root node ---
	var root_rect: Rect2 = Rect2(rect.position.x + rect.size.x * 0.5 - 150.0, rect.position.y + 14.0, 300.0, 66.0)
	_draw_tree_node(root_rect, "POLICE ROOT", "Hunter fuzzy evaluation", C_POLICE, font, alpha, true)

	var tree_area_y: float = root_rect.end.y + 10.0
	var tree_area_h: float = rect.end.y - tree_area_y - 12.0
	var col_w: float = (rect.size.x - 28.0) / 3.0

	# -- Column 1: Target Selection ---
	var col1_x: float = rect.position.x + 8.0
	var col1_header: Rect2 = Rect2(col1_x, tree_area_y, col_w - 8.0, 28.0)
	draw_rect(col1_header, Color(0.04, 0.08, 0.14, 0.92 * alpha))
	draw_rect(col1_header, Color(C_POLICE.r, C_POLICE.g, C_POLICE.b, 0.40 * alpha), false)
	draw_string(font, col1_header.position + Vector2(8.0, 18.0), "Target Selection", HORIZONTAL_ALIGNMENT_LEFT, col1_header.size.x - 12.0, 12, C_POLICE)
	_draw_tree_link(root_rect.get_center(), Vector2(col1_header.get_center().x, col1_header.position.y), C_POLICE, 2.0, alpha)

	var red_score: float = float(inputs.get("red_target_score", 0.0))
	var blue_score: float = float(inputs.get("blue_target_score", 0.0))
	var red_card: Rect2 = Rect2(col1_x, col1_header.end.y + 6.0, col_w - 8.0, 80.0)
	var blue_card: Rect2 = Rect2(col1_x, red_card.end.y + 6.0, col_w - 8.0, 80.0)
	var red_chosen: bool = target_agent.find("Red") >= 0
	var blue_chosen: bool = target_agent.find("Blue") >= 0
	_draw_fuzzy_target_card(red_card, "RED", C_RED_AG, red_score,
		int(inputs.get("red_distance", -1)), int(inputs.get("red_exit_distance", -1)),
		int(inputs.get("red_stealth", 0)), red_chosen, font, alpha)
	_draw_fuzzy_target_card(blue_card, "BLUE", Color(0.20, 0.90, 1.0), blue_score,
		int(inputs.get("blue_distance", -1)), int(inputs.get("blue_exit_distance", -1)),
		int(inputs.get("blue_stealth", 0)), blue_chosen, font, alpha)

	# -- FIX #5: Dashed arrow from winning target card → col2 header (left edge)
	# Shows HOW the target choice feeds into the behaviour scoring step.
	var winning_target_card: Rect2 = red_card if red_chosen else blue_card
	var winning_target_color: Color = C_RED_AG if red_chosen else Color(0.20, 0.90, 1.0)

	# -- Column 2: Behaviour Evaluation ---
	var col2_x: float = rect.position.x + 8.0 + col_w
	var col2_header: Rect2 = Rect2(col2_x, tree_area_y, col_w - 8.0, 28.0)
	draw_rect(col2_header, Color(0.04, 0.08, 0.14, 0.92 * alpha))
	draw_rect(col2_header, Color(C_POLICE.r, C_POLICE.g, C_POLICE.b, 0.40 * alpha), false)
	draw_string(font, col2_header.position + Vector2(8.0, 18.0), "Behaviour Evaluation", HORIZONTAL_ALIGNMENT_LEFT, col2_header.size.x - 12.0, 12, C_POLICE)
	_draw_tree_link(root_rect.get_center(), Vector2(col2_header.get_center().x, col2_header.position.y), C_POLICE, 2.5, alpha)

	var behaviour_names: Array = ["chase", "intercept", "investigate", "patrol"]
	var score_keys: Array = ["chase_score", "intercept_score", "investigate_score", "patrol_score"]
	var beh_item_h: float = (tree_area_h - 34.0) / 4.0 - 4.0
	for bi in range(4):
		var bname: String = behaviour_names[bi]
		var bscore: float = float(inputs.get(score_keys[bi], 0.0))
		var is_winner: bool = bname == behavior.to_lower()
		var bcol: Color = _behavior_color(bname.to_upper())
		var bnode_rect: Rect2 = Rect2(col2_x, col2_header.end.y + 6.0 + float(bi) * (beh_item_h + 4.0), col_w - 8.0, beh_item_h)
		draw_rect(bnode_rect, Color(0.03, 0.06, 0.10, 0.95 * alpha))
		draw_rect(bnode_rect, Color(bcol.r, bcol.g, bcol.b, (0.78 if is_winner else 0.30) * alpha), false, 2.0)
		if is_winner:
			draw_rect(Rect2(bnode_rect.position, Vector2(bnode_rect.size.x, 3.0)), Color(bcol.r, bcol.g, bcol.b, 0.90 * alpha))
		draw_string(font, bnode_rect.position + Vector2(8.0, 16.0), bname.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, bnode_rect.size.x - 12.0, 12, Color(bcol.r, bcol.g, bcol.b, 0.98 * alpha))
		var bar_rect: Rect2 = Rect2(bnode_rect.position.x + 8.0, bnode_rect.position.y + 22.0, bnode_rect.size.x - 16.0, 8.0)
		draw_rect(bar_rect, Color(0.08, 0.12, 0.16, 0.95))
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * clampf(bscore, 0.0, 1.0), bar_rect.size.y)), Color(bcol.r, bcol.g, bcol.b, 0.92))
		draw_string(font, bnode_rect.position + Vector2(8.0, bnode_rect.size.y - 4.0), "Score %.2f%s" % [bscore, " ← WINNER" if is_winner else ""], HORIZONTAL_ALIGNMENT_LEFT, bnode_rect.size.x - 12.0, 9, C_TEXT)

	# -- Column 3: Final Decision ---
	var col3_x: float = rect.position.x + 8.0 + col_w * 2.0
	var col3_header: Rect2 = Rect2(col3_x, tree_area_y, col_w - 8.0, 28.0)
	draw_rect(col3_header, Color(0.04, 0.08, 0.14, 0.92 * alpha))
	draw_rect(col3_header, Color(behavior_color.r, behavior_color.g, behavior_color.b, 0.50 * alpha), false)
	draw_string(font, col3_header.position + Vector2(8.0, 18.0), "Final Decision", HORIZONTAL_ALIGNMENT_LEFT, col3_header.size.x - 12.0, 12, behavior_color)
	_draw_tree_link(root_rect.get_center(), Vector2(col3_header.get_center().x, col3_header.position.y), behavior_color, 2.0, alpha)

	var chosen_tile_str: String = _tile_str(Vector2i(decision.get("chosen_tile", Vector2i(-1, -1))))
	var final_rect: Rect2 = Rect2(col3_x, col3_header.end.y + 6.0, col_w - 8.0, 72.0)
	_draw_tree_node(final_rect, behavior.to_upper(), "Move to %s" % chosen_tile_str, behavior_color, font, alpha, true)

	var reason_rect: Rect2 = Rect2(col3_x, final_rect.end.y + 6.0, col_w - 8.0, 60.0)
	draw_rect(reason_rect, Color(0.02, 0.04, 0.06, 0.92 * alpha))
	draw_rect(reason_rect, Color(behavior_color.r, behavior_color.g, behavior_color.b, 0.28 * alpha), false)
	draw_string(font, reason_rect.position + Vector2(8.0, 14.0), "Why this decision", HORIZONTAL_ALIGNMENT_LEFT, reason_rect.size.x - 12.0, 10, C_DIM)
	draw_string(font, reason_rect.position + Vector2(8.0, 30.0), reason if reason != "" else "reason not recorded", HORIZONTAL_ALIGNMENT_LEFT, reason_rect.size.x - 12.0, 10, C_TEXT)

	var target_display: String = target_agent if target_agent != "Unknown" else "—"
	draw_string(font, reason_rect.position + Vector2(8.0, 52.0), "Target: %s" % target_display, HORIZONTAL_ALIGNMENT_LEFT, reason_rect.size.x - 12.0, 10, chosen_color)

	# -- FIX #5: Draw linking arrows between columns so examiner can trace decision path --
	# Dashed arrow: winning target card right edge → col2 header left edge
	# Shows: "chosen target score feeds into behaviour evaluation"
	var target_card_right: Vector2 = Vector2(winning_target_card.end.x, winning_target_card.get_center().y)
	var col2_left: Vector2 = Vector2(col2_header.position.x, col2_header.get_center().y)
	_draw_dashed_line(target_card_right, col2_left, Color(winning_target_color.r, winning_target_color.g, winning_target_color.b, 0.70 * alpha), 1.5, 5.0)

	# Solid arrow: winning behaviour node right edge → col3 header left edge
	# Shows: "winning behaviour → final decision"
	var winner_bi: int = behaviour_names.find(behavior.to_lower())
	if winner_bi < 0:
		winner_bi = 0
	var winner_bnode_y: float = col2_header.end.y + 6.0 + float(winner_bi) * (beh_item_h + 4.0)
	var winner_bnode_rect: Rect2 = Rect2(col2_x, winner_bnode_y, col_w - 8.0, beh_item_h)
	var winner_behavior_right: Vector2 = Vector2(winner_bnode_rect.end.x, winner_bnode_rect.get_center().y)
	var col3_left: Vector2 = Vector2(final_rect.position.x, final_rect.get_center().y)
	_draw_tree_link(winner_behavior_right, col3_left, behavior_color, 2.0, alpha)

func _draw_fuzzy_target_card(rect: Rect2, label: String, accent: Color, threat_score: float, dist_police: int, dist_exit: int, stealth: int, chosen: bool, font: Font, alpha: float) -> void:
	draw_rect(rect, Color(0.03, 0.06, 0.10, 0.94 * alpha))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, (0.58 if chosen else 0.32) * alpha), false)
	if chosen:
		draw_rect(rect.grow(1.0), Color(accent.r, accent.g, accent.b, 0.20 * alpha), false)
	draw_string(font, Vector2(rect.position.x + 8.0, rect.position.y + 17.0), "%s TARGET" % label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 14.0, 11, Color(accent.r, accent.g, accent.b, 0.96 * alpha))
	draw_string(font, Vector2(rect.position.x + 8.0, rect.position.y + 33.0), "Police dist %d   Exit dist %d   Stealth %d" % [dist_police, dist_exit, stealth], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 14.0, 10, C_DIM)
	var bar_rect: Rect2 = Rect2(rect.position.x + 8.0, rect.position.y + 43.0, rect.size.x - 16.0, 10.0)
	draw_rect(bar_rect, Color(0.08, 0.12, 0.16, 0.95))
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * clampf(threat_score, 0.0, 1.0), bar_rect.size.y)), Color(accent.r, accent.g, accent.b, 0.92 * alpha))
	draw_string(font, Vector2(rect.position.x + 8.0, rect.position.y + 70.0), "Threat score %.2f" % threat_score, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 14.0, 11, C_TEXT)
	if chosen:
		draw_string(font, Vector2(rect.position.x + rect.size.x - 90.0, rect.position.y + 17.0), "WINNER", HORIZONTAL_ALIGNMENT_LEFT, 82.0, 10, C_HIGHLIGHT)

func _behavior_color(behavior: String) -> Color:
	var upper: String = behavior.to_upper()
	if upper.find("CHASE") >= 0:
		return Color(0.96, 0.50, 0.24)
	if upper.find("INTERCEPT") >= 0:
		return Color(0.98, 0.78, 0.20)
	if upper.find("INVESTIGATE") >= 0:
		return Color(0.40, 0.82, 1.0)
	if upper.find("PATROL") >= 0:
		return Color(0.58, 0.82, 0.72)
	return C_POLICE

func _infer_rule_support(label: String, fallback_behavior: String, target_name: String) -> Dictionary:
	var upper: String = label.to_upper()
	var target: String = "NEUTRAL"
	if upper.find("RED") >= 0:
		target = "SUPPORTS RED"
	elif upper.find("BLUE") >= 0:
		target = "SUPPORTS BLUE"
	elif target_name.to_upper().find("RED") >= 0:
		target = "SUPPORTS RED"
	elif target_name.to_upper().find("BLUE") >= 0:
		target = "SUPPORTS BLUE"

	var behavior: String = fallback_behavior.to_upper()
	for b in ["CHASE", "INTERCEPT", "INVESTIGATE", "PATROL"]:
		if upper.find(b) >= 0:
			behavior = b
			break
	return {
		"target": target,
		"behavior": behavior,
	}

func _draw_bar_with_label(pos: Vector2, width: float, label: String, value01: float, accent: Color, font: Font, alpha: float) -> void:
	var clamped_value: float = clampf(value01, 0.0, 1.0)
	draw_string(font, pos + Vector2(0.0, 0.0), label, HORIZONTAL_ALIGNMENT_LEFT, width, 10, C_DIM)
	var bar_rect: Rect2 = Rect2(pos.x, pos.y + 4.0, width, 10.0)
	draw_rect(bar_rect, Color(0.08, 0.12, 0.16, 0.95 * alpha))
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * clamped_value, bar_rect.size.y)), Color(accent.r, accent.g, accent.b, 0.90 * alpha))
	draw_rect(bar_rect, Color(1, 1, 1, 0.10 * alpha), false)
	draw_string(font, Vector2(bar_rect.end.x - 34.0, bar_rect.position.y + 9.0), "%d%%" % int(round(clamped_value * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_TEXT)

func _draw_decision_timeline(rect: Rect2, timeline: Array, font: Font, alpha: float) -> void:
	if font == null:
		return

	var header_h: float = 26.0
	draw_string(font, rect.position + Vector2(10.0, 16.0), "Decision Timeline",
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0, 14, C_HIGHLIGHT)

	if timeline.is_empty():
		draw_string(font, rect.position + Vector2(10.0, 38.0), "No decisions recorded",
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0, 11, C_DIM)
		return

	var card_h:    float = 64.0
	var card_gap:  float = 8.0
	var sb_w:      float = 6.0
	var content_top: float = rect.position.y + header_h + 10.0
	var content_h:   float = rect.size.y - header_h - 10.0
	var total:       int   = timeline.size()
	var visible_count: int = maxi(1, int(content_h / (card_h + card_gap)))
	var max_scroll:  int   = maxi(0, total - visible_count)
	_timeline_scroll = clampi(_timeline_scroll, 0, max_scroll)

	# Count / scroll hint
	var showing_end: int = mini(_timeline_scroll + visible_count, total)
	var showing_start: int = _timeline_scroll + 1
	var has_scroll: bool = total > visible_count
	if has_scroll:
		var hint: String = "%d–%d of %d  ·  scroll wheel" % [showing_start, showing_end, total]
		draw_string(font, rect.position + Vector2(10.0, 24.0), hint,
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0, 9, C_DIM)

	var card_w: float = rect.size.x - 16.0 - (sb_w + 6.0 if has_scroll else 0.0)
	var y: float = content_top

	for slot in range(visible_count):
		# slot 0 = newest visible item (top of list = highest tick)
		var arr_idx: int = total - 1 - _timeline_scroll - slot
		if arr_idx < 0:
			break
		if y + card_h > rect.end.y + 2.0:
			break

		var item: Dictionary = Dictionary(timeline[arr_idx])
		var tick: int = int(item.get("tick", -1))
		var chosen_action: String = str(item.get("chosen_action", "MOVE"))
		if item.has("chosen_behavior"):
			chosen_action = "%s %s" % [str(item.get("chosen_behavior", "PATROL")), str(item.get("chosen_target", ""))]
		var reason: String = str(item.get("reason", "Not recorded"))
		var newest: bool = arr_idx == total - 1

		var card_rect: Rect2 = Rect2(rect.position.x + 8.0, y, card_w, card_h)
		var accent: Color = Color(0.20, 0.85, 1.0)
		draw_rect(card_rect, Color(0.03, 0.06, 0.10, 0.94 * alpha))
		draw_rect(card_rect, Color(accent.r, accent.g, accent.b, (0.46 if newest else 0.24) * alpha), false)
		draw_rect(Rect2(card_rect.position.x, card_rect.position.y, 4.0, card_rect.size.y),
			Color(accent.r, accent.g, accent.b, (0.88 if newest else 0.62) * alpha))

		var algorithm_label: String = str(item.get("algorithm", "AI"))
		draw_string(font, Vector2(card_rect.position.x + 10.0, card_rect.position.y + 16.0),
			"T%d  %s" % [tick, chosen_action],
			HORIZONTAL_ALIGNMENT_LEFT, card_w - 90.0, 12, C_TEXT)
		draw_string(font, Vector2(card_rect.end.x - 84.0, card_rect.position.y + 16.0),
			algorithm_label, HORIZONTAL_ALIGNMENT_LEFT, 78.0, 10, C_DIM)
		draw_string(font, Vector2(card_rect.position.x + 10.0, card_rect.position.y + 34.0),
			reason if reason != "" else "reason not recorded",
			HORIZONTAL_ALIGNMENT_LEFT, card_w - 16.0, 10, C_DIM)

		var metric_line: String = ""
		if item.has("chosen_score"):
			metric_line = "Score %.2f" % float(item.get("chosen_score", 0.0))
			var pruned:    int = int(item.get("pruned_branches", -1))
			var evaluated: int = int(item.get("evaluated_nodes", 0))
			var depth:     int = int(item.get("search_depth", 0))
			if pruned >= 0:
				metric_line += "  ·  pruned %d  depth %d" % [pruned, depth]
				if evaluated > 0:
					metric_line += " (%d nodes)" % evaluated
		elif item.has("chosen_visits"):
			metric_line = "Visits %d" % int(item.get("chosen_visits", 0))
		elif item.has("chosen_behavior"):
			metric_line = "%s → %s" % [str(item.get("chosen_behavior", "-")), str(item.get("chosen_target", "-"))]
		if metric_line != "":
			draw_string(font, Vector2(card_rect.position.x + 10.0, card_rect.position.y + 54.0),
				metric_line, HORIZONTAL_ALIGNMENT_LEFT, card_w - 16.0, 10, C_TEXT)

		y += card_h + card_gap

	# Scrollbar track + thumb
	if has_scroll:
		var sb_x: float    = rect.end.x - sb_w - 4.0
		var track_h: float = content_h - card_gap
		var track: Rect2   = Rect2(sb_x, content_top, sb_w, track_h)
		draw_rect(track, Color(0.08, 0.12, 0.18, 0.80 * alpha))
		var thumb_h: float  = maxf(18.0, track_h * float(visible_count) / float(total))
		var travel:  float  = track_h - thumb_h
		var thumb_y: float  = content_top + travel * (float(_timeline_scroll) / float(max_scroll))
		draw_rect(Rect2(sb_x, thumb_y, sb_w, thumb_h), Color(0.22, 0.86, 1.0, 0.78 * alpha))
		draw_rect(Rect2(sb_x, thumb_y, sb_w, thumb_h), Color(0.50, 0.96, 1.0, 0.40 * alpha), false)

func _draw_arrow(from_pos: Vector2, to_pos: Vector2, color: Color, size: float) -> void:
	var dir: Vector2 = (to_pos - from_pos)
	if dir.length() < 0.001:
		return
	var n: Vector2 = dir.normalized()
	var p: Vector2 = Vector2(-n.y, n.x)
	var tip: Vector2 = to_pos
	var a: Vector2 = tip - n * size + p * (size * 0.45)
	var b: Vector2 = tip - n * size - p * (size * 0.45)
	draw_colored_polygon(PackedVector2Array([tip, a, b]), color)

func _draw_dashed_line(from_pos: Vector2, to_pos: Vector2, color: Color, width: float, dash_len: float) -> void:
	var dir: Vector2 = to_pos - from_pos
	var length: float = dir.length()
	if length <= 0.001:
		return
	var n: Vector2 = dir / length
	var step: float = maxf(2.0, dash_len)
	var draw_dash: bool = true
	var t: float = 0.0
	while t < length:
		var seg_start: Vector2 = from_pos + n * t
		var seg_end: Vector2 = from_pos + n * minf(length, t + step)
		if draw_dash:
			draw_line(seg_start, seg_end, color, width)
		draw_dash = not draw_dash
		t += step

func _tile_str(tile: Vector2i) -> String:
	return "(%d,%d)" % [tile.x, tile.y]

func _display_ordered_results(agent_results: Array, _outcome_key: String) -> Array:
	# Cards follow actual performance ranking.
	return _ranked_results(agent_results)

func _status_for_card(role: String, escaped: bool, captured: bool, eliminated: bool, captures_made: int) -> Dictionary:
	var outcome_key: String = _resolved_outcome_key()
	if role == "police":
		var targets: int = maxi(captures_made, int(_result.get("captured_count", 0)))
		var escaped_count: int = int(_result.get("escaped_count", 0))
		if outcome_key == "police_wins":
			return {"text": "CAPTURED %d TARGETS" % targets, "color": C_POLICE}
		if outcome_key == "prisoners_win":
			if targets > 0:
				return {"text": "%d CAPTURES / %d ESCAPED" % [targets, escaped_count], "color": C_WARNING}
			return {"text": "NO CAPTURES", "color": C_RED_AG}
		return {"text": "HUNTER SURVIVED", "color": C_WARNING}
	if escaped:
		return {"text": "ESCAPED", "color": C_HIGHLIGHT}
	if captured:
		return {"text": "CAUGHT", "color": C_RED_AG}
	if eliminated:
		return {"text": "ELIMINATED", "color": C_RED_AG}
	if outcome_key == "police_wins":
		return {"text": "LOCKED DOWN", "color": C_WARNING}
	return {"text": "SURVIVED", "color": C_WARNING}

func _strategy_label(role: String) -> String:
	match role:
		"rusher_red":
			return "AI Strategy: Minimax"
		"sneaky_blue":
			return "AI Strategy: Monte Carlo Search"
		_:
			return "AI Strategy: Fuzzy Logic"

func _agent_result_for_role(role: String) -> Dictionary:
	for item_var in Array(_result.get("agent_results", [])):
		var item: Dictionary = Dictionary(item_var)
		if str(item.get("role", "")) == role:
			return item
	return {}

func _ranked_results(agent_results: Array) -> Array:
	var out: Array = []
	for item in agent_results:
		out.append(item)
	out.sort_custom(func(a, b):
		var pa: float = float(a.get("performance", 0.0))
		var pb: float = float(b.get("performance", 0.0))
		if is_equal_approx(pa, pb):
			return float(a.get("raw_score", 0.0)) > float(b.get("raw_score", 0.0))
		return pa > pb
	)
	return out

func _role_short(role: String) -> String:
	match role:
		"rusher_red":
			return "RED"
		"sneaky_blue":
			return "BLUE"
		"police":
			return "POLICE"
		_:
			return role

func _int_or_dash(v: int) -> String:
	if v < 0:
		return "-"
	return str(v)

func _draw_results_nav(cx: float, y: float, font: Font, alpha: float) -> void:
	var replay_rect: Rect2 = _btn_rects[BTN_REPLAY]
	var title_rect: Rect2 = _btn_rects[BTN_TITLE]
	if replay_rect.size == Vector2.ZERO or title_rect.size == Vector2.ZERO:
		replay_rect = Rect2(cx - 280.0, y, 260.0, 54.0)
		title_rect = Rect2(cx + 20.0, y, 260.0, 54.0)
	_draw_results_button(replay_rect, "PLAY AGAIN", BTN_REPLAY == _hover_btn, C_HIGHLIGHT, font, alpha)
	_draw_results_button(title_rect, "MAIN MENU", BTN_TITLE == _hover_btn, Color(0.55, 0.68, 0.80), font, alpha)
	if font != null:
		var btn_h: float = replay_rect.size.y
		_draw_results_centered_text(font, "Enter/R replay   Esc/T menu   A analysis   1/2/3 tabs",
			Vector2(cx, replay_rect.position.y + btn_h + 26.0), 15, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.74 * alpha))

func _draw_results_button(rect: Rect2, label: String, hovered: bool, accent: Color, font: Font, alpha: float) -> void:
	var r: Rect2 = rect
	if hovered:
		r = Rect2(r.position - Vector2(4.0, 4.0), r.size + Vector2(8.0, 8.0))
	draw_rect(Rect2(r.position + Vector2(4.0, 5.0), r.size), Color(0, 0, 0, 0.36 * alpha))
	draw_rect(r, Color(accent.r * 0.16, accent.g * 0.16, accent.b * 0.16, (0.88 if hovered else 0.66) * alpha))
	draw_rect(Rect2(r.position, Vector2(6.0, r.size.y)), Color(accent.r, accent.g, accent.b, alpha))
	draw_rect(r, Color(accent.r, accent.g, accent.b, (0.88 if hovered else 0.46) * alpha), false, 2.0)
	if font != null:
		_draw_results_centered_text(font, label, Vector2(r.get_center().x, r.position.y + r.size.y * 0.64),
			22, Color(accent.r * 1.15, accent.g * 1.15, accent.b * 1.15, alpha).clamp())

func _draw_results_centered_text(font: Font, text: String, pos: Vector2, size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(pos.x - width * 0.5, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _refresh_nav_regions() -> void:
	var vp: Rect2 = get_viewport_rect()
	var cx: float = vp.size.x * 0.5
	var y: float = vp.size.y * 0.62
	var compact: bool = vp.size.y < 860.0
	var container: Rect2 = _content_bounds(vp)
	var content_w: float = container.size.x
	var header_y: float = container.position.y
	var header_h: float = clampf(container.size.y * (0.18 if compact else 0.20), 120.0, 168.0)
	var header_x: float = container.position.x
	_btn_rects[BTN_AI_ANALYSIS] = Rect2(header_x + content_w - 258.0, header_y + 10.0, 230.0, 40.0)

	if _view_mode == ViewMode.AI_ANALYSIS:
		_btn_rects[BTN_BACK_RESULTS] = Rect2(header_x + 20.0, header_y + 12.0, 194.0, 40.0)
		var tab_y: float = header_y + header_h + maxf(10.0, container.size.y * 0.012)
		var tab_w: float = clampf(container.size.x * 0.19, 176.0, 286.0)
		var tab_gap: float = maxf(10.0, container.size.x * 0.010)
		_btn_rects[BTN_TAB_RED] = Rect2(header_x, tab_y, tab_w, 46.0)
		_btn_rects[BTN_TAB_BLUE] = Rect2(header_x + tab_w + tab_gap, tab_y, tab_w, 46.0)
		_btn_rects[BTN_TAB_POLICE] = Rect2(header_x + (tab_w + tab_gap) * 2.0, tab_y, tab_w, 46.0)
		y = container.end.y - 88.0
	elif not _result.is_empty():
		var block_gap: float = maxf(12.0, container.size.y * 0.015)
		var cards_top: float = header_y + header_h + block_gap
		var summary_h: float = clampf(container.size.y * 0.13, 86.0, 122.0)
		var nav_h: float = clampf(container.size.y * 0.13, 86.0, 122.0)
		var cards_h: float = maxf(250.0, container.end.y - cards_top - summary_h - nav_h - block_gap * 2.0)
		var footer_y: float = cards_top + cards_h + block_gap
		y = footer_y + summary_h + block_gap - 18.0
		_btn_rects[BTN_BACK_RESULTS] = Rect2()
		_btn_rects[BTN_TAB_RED] = Rect2()
		_btn_rects[BTN_TAB_BLUE] = Rect2()
		_btn_rects[BTN_TAB_POLICE] = Rect2()

	var btn_w: float = clampf(container.size.x * 0.24, 260.0, 410.0)
	var btn_h: float = clampf(container.size.y * 0.095, 60.0, 84.0)
	var gap: float = maxf(18.0, container.size.x * 0.018)
	_btn_rects[BTN_REPLAY] = Rect2(cx - btn_w - gap * 0.5, y, btn_w, btn_h)
	_btn_rects[BTN_TITLE] = Rect2(cx + gap * 0.5, y, btn_w, btn_h)

func _rank_ordinal(rank: int) -> String:
	if rank == 1:
		return "1ST"
	if rank == 2:
		return "2ND"
	if rank == 3:
		return "3RD"
	return "%dTH" % rank

func _find_button_at(pos: Vector2) -> int:
	for i in range(_btn_rects.size()):
		if _btn_rects[i].has_point(pos):
			return i
	return -1

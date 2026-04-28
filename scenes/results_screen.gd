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

var _btn_rects  : Array[Rect2] = [Rect2(), Rect2()]
var _mouse_pos  : Vector2      = Vector2.ZERO
var _hover_btn  : int          = -1

var _result     : Dictionary   = {}

# -- Entry animation: 0->1 over ~0.6 s, drives fade-in -------------------
var _show_t     : float        = 0.0

# -------------------------------------------------------------------------

func _ready() -> void:
	_result = pending_result.duplicate()

func _process(delta: float) -> void:
	_show_t    = minf(_show_t + delta / 0.6, 1.0)
	_mouse_pos = get_viewport().get_mouse_position()
	_hover_btn = -1
	for i in range(_btn_rects.size()):
		if _btn_rects[i].has_point(_mouse_pos):
			_hover_btn = i
			break
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		match _hover_btn:
			BTN_REPLAY: _play_again()
			BTN_TITLE:  _go_title()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
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
		"timeout":
			out_text = "TIME LIMIT REACHED"
			out_col  = C_WARNING
		_:
			out_text = "PARTIAL RESULT"
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
	match outcome:
		"prisoners_win":
			return "%d prisoner(s) made it out alive." % esc
		"police_wins":
			return "All %d prisoner(s) were captured." % cap
		"timeout":
			return "Tick limit reached -- %d escaped, %d captured." % [esc, cap]
		_:
			return "%d escaped  \u00B7  %d captured." % [esc, cap]

func _draw_professional_results() -> void:
	var vp := get_viewport_rect()
	var font := ThemeDB.fallback_font
	var alpha := _show_t
	var cx := vp.size.x * 0.5

	draw_rect(vp, Color(0.035, 0.055, 0.075))
	_draw_results_backdrop(vp, alpha)

	var outcome: String = _result.get("outcome", "unknown")
	var out_text: String
	var out_col: Color
	match outcome:
		"prisoners_win":
			out_text = "Prisoners Escaped"
			out_col = C_HIGHLIGHT
		"police_wins":
			out_text = "Police Secured The Yard"
			out_col = C_RED_AG
		"timeout":
			out_text = "Time Limit Reached"
			out_col = C_WARNING
		_:
			out_text = "Run Summary"
			out_col = C_WARNING

	draw_rect(Rect2(0.0, 0.0, vp.size.x, 6.0), Color(out_col.r, out_col.g, out_col.b, 0.72 * alpha))

	if _result.is_empty():
		if font != null:
			_draw_results_centered_text(font, "No Result Data", Vector2(cx, vp.size.y * 0.46), 32,
				Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, alpha))
			_draw_results_centered_text(font, "Return to the menu and start a new run.",
				Vector2(cx, vp.size.y * 0.51), 16, Color(C_DIM.r, C_DIM.g, C_DIM.b, alpha))
		_draw_results_nav(cx, vp.size.y * 0.62, font, alpha)
		return

	var content_w := minf(1180.0, vp.size.x - 120.0)
	var top_y := 112.0
	var header := Rect2(cx - content_w * 0.5, top_y, content_w, 170.0)
	_draw_results_header(header, out_text, out_col, font, alpha)

	var agent_results: Array = _result.get("agent_results", [])
	var card_gap := 24.0
	var card_w := (content_w - card_gap * 2.0) / 3.0
	var card_h := 218.0
	var card_y := header.end.y + 34.0
	for i in range(agent_results.size()):
		var card_x := header.position.x + float(i) * (card_w + card_gap)
		var agent_result: Dictionary = agent_results[i]
		_draw_results_agent_card(agent_result, Rect2(card_x, card_y, card_w, card_h), font, alpha)

	var footer_y := card_y + card_h + 34.0
	_draw_results_summary(Rect2(header.position.x, footer_y, content_w, 90.0), outcome, font, alpha)
	_draw_results_nav(cx, footer_y + 122.0, font, alpha)

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

func _draw_results_header(rect: Rect2, outcome_text: String, accent: Color, font: Font, alpha: float) -> void:
	draw_rect(Rect2(rect.position + Vector2(8.0, 10.0), rect.size), Color(0, 0, 0, 0.34 * alpha))
	draw_rect(rect, Color(0.045, 0.075, 0.095, 0.92 * alpha))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 5.0)), Color(accent.r, accent.g, accent.b, alpha))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.36 * alpha), false, 2.0)
	if font == null:
		return

	_draw_results_centered_text(font, outcome_text, Vector2(rect.get_center().x, rect.position.y + 62.0),
		44, Color(accent.r, accent.g, accent.b, alpha))
	var outcome_name: String = str(_result.get("outcome", "unknown"))
	_draw_results_centered_text(font, _outcome_description(outcome_name, _result),
		Vector2(rect.get_center().x, rect.position.y + 98.0), 16, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.88 * alpha))

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

func _draw_results_agent_card(ar: Dictionary, rect: Rect2, font: Font, alpha: float) -> void:
	var role: String = ar.get("role", "?")
	var hp: float = ar.get("health", 0.0)
	var stamina: float = ar.get("stamina", 0.0)
	var escaped: bool = ar.get("escaped", false)
	var captured: bool = ar.get("captured", false)
	var role_col := C_POLICE
	var role_name := "Police Hunter"
	var algo := "FUZZY"
	var stamina_max := 75.0
	if role == "rusher_red":
		role_col = C_RED_AG
		role_name = "Rusher Red"
		algo = "MINIMAX"
		stamina_max = 100.0
	elif role == "sneaky_blue":
		role_col = Color(0.18, 1.00, 0.92)
		role_name = "Sneaky Blue"
		algo = "MCTS"
		stamina_max = 50.0

	draw_rect(Rect2(rect.position + Vector2(5.0, 7.0), rect.size), Color(0, 0, 0, 0.32 * alpha))
	draw_rect(rect, Color(0.055, 0.085, 0.105, 0.94 * alpha))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 5.0)), Color(role_col.r, role_col.g, role_col.b, alpha))
	draw_rect(rect, Color(role_col.r, role_col.g, role_col.b, 0.34 * alpha), false)
	if font == null:
		return

	var pad := 22.0
	draw_string(font, rect.position + Vector2(pad, 42.0), role_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(role_col.r, role_col.g, role_col.b, alpha))
	draw_string(font, rect.position + Vector2(pad, 68.0), algo,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.80 * alpha))

	var status := "ACTIVE"
	var status_col := C_WARNING
	if escaped:
		status = "ESCAPED"
		status_col = C_HIGHLIGHT
	elif captured:
		status = "CAPTURED"
		status_col = C_RED_AG
	var status_w := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, Vector2(rect.end.x - status_w - pad, rect.position.y + 42.0), status,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(status_col.r, status_col.g, status_col.b, alpha))

	_draw_results_value_bar(rect.position + Vector2(pad, 102.0), rect.size.x - pad * 2.0,
		"HEALTH", hp, 100.0, Color(0.90, 0.20, 0.20), font, alpha)
	_draw_results_value_bar(rect.position + Vector2(pad, 148.0), rect.size.x - pad * 2.0,
		"STAMINA", stamina, stamina_max, Color(0.90, 0.75, 0.10), font, alpha)

func _draw_results_value_bar(pos: Vector2, width: float, label: String, value: float, max_value: float, color: Color, font: Font, alpha: float) -> void:
	draw_string(font, pos + Vector2(0.0, -8.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.78 * alpha))
	var ratio := clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	var r := Rect2(pos + Vector2(0.0, 4.0), Vector2(width, 14.0))
	draw_rect(r, Color(0.02, 0.04, 0.05, 0.82 * alpha))
	draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)), Color(color.r, color.g, color.b, 0.88 * alpha))
	draw_rect(r, Color(1, 1, 1, 0.12 * alpha), false)
	var value_text := "%d/%d" % [int(value), int(max_value)]
	var value_w := font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, Vector2(r.end.x - value_w, pos.y - 8.0), value_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.82 * alpha))

func _draw_results_summary(rect: Rect2, outcome: String, font: Font, alpha: float) -> void:
	draw_rect(rect, Color(0.045, 0.075, 0.095, 0.70 * alpha))
	draw_rect(rect, Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.20 * alpha), false)
	if font == null:
		return
	var summary := _outcome_description(outcome, _result)
	_draw_results_centered_text(font, summary, Vector2(rect.get_center().x, rect.position.y + 38.0),
		18, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.90 * alpha))
	_draw_results_centered_text(font, "Replay to test a new generated facility.",
		Vector2(rect.get_center().x, rect.position.y + 66.0), 13, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.72 * alpha))

func _draw_results_nav(cx: float, y: float, font: Font, alpha: float) -> void:
	var btn_w := 270.0
	var btn_h := 54.0
	var gap := 24.0
	_btn_rects[BTN_REPLAY] = Rect2(cx - btn_w - gap * 0.5, y, btn_w, btn_h)
	_btn_rects[BTN_TITLE] = Rect2(cx + gap * 0.5, y, btn_w, btn_h)
	_draw_results_button(_btn_rects[BTN_REPLAY], "PLAY AGAIN", BTN_REPLAY == _hover_btn, C_HIGHLIGHT, font, alpha)
	_draw_results_button(_btn_rects[BTN_TITLE], "MAIN MENU", BTN_TITLE == _hover_btn, Color(0.55, 0.68, 0.80), font, alpha)
	if font != null:
		_draw_results_centered_text(font, "Enter / R to replay    Esc / T for menu",
			Vector2(cx, y + btn_h + 30.0), 13, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.72 * alpha))

func _draw_results_button(rect: Rect2, label: String, hovered: bool, accent: Color, font: Font, alpha: float) -> void:
	var r := rect
	if hovered:
		r = Rect2(r.position - Vector2(4.0, 4.0), r.size + Vector2(8.0, 8.0))
	draw_rect(Rect2(r.position + Vector2(4.0, 5.0), r.size), Color(0, 0, 0, 0.36 * alpha))
	draw_rect(r, Color(accent.r * 0.16, accent.g * 0.16, accent.b * 0.16, (0.88 if hovered else 0.66) * alpha))
	draw_rect(Rect2(r.position, Vector2(6.0, r.size.y)), Color(accent.r, accent.g, accent.b, alpha))
	draw_rect(r, Color(accent.r, accent.g, accent.b, (0.88 if hovered else 0.46) * alpha), false, 2.0)
	if font != null:
		_draw_results_centered_text(font, label, Vector2(r.get_center().x, r.position.y + r.size.y * 0.64),
			18, Color(accent.r * 1.15, accent.g * 1.15, accent.b * 1.15, alpha).clamp())

func _draw_results_centered_text(font: Font, text: String, pos: Vector2, size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(pos.x - width * 0.5, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

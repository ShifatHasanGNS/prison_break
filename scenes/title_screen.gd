extends Node2D
class_name TitleScreen

## Fullscreen title screen. C_BG background, procedural _draw().
## No Label or Button nodes -- everything drawn with draw_* calls.

const C_BG           := Color(0.055, 0.078, 0.125)
const C_HIGHLIGHT    := Color(0.290, 0.855, 0.502)
const C_WARNING      := Color(0.984, 0.749, 0.141)
const C_RED_AG       := Color(0.937, 0.267, 0.267)
const C_PANEL_BG     := Color(0.08,  0.11,  0.18,  0.95)
const C_PANEL_BORDER := Color(0.0,   0.70,  1.0,   0.45)
const C_TEXT         := Color(0.90,  0.92,  0.96)
const C_DIM          := Color(0.55,  0.60,  0.68)

const BTN_PLAY : int = 0
const BTN_SETTINGS : int = 1
const BTN_QUIT : int = 2

const OPT_SOUND: int = 0
const OPT_MUSIC: int = 1
const OPT_SHAKE: int = 2
const OPT_TRAILS: int = 3
const OPT_BLOOM: int = 4
const OPT_FOG: int = 5

var _btn_rects : Array[Rect2] = [Rect2(), Rect2(), Rect2()]
var _option_rects: Array[Rect2] = []
var _mouse_pos : Vector2      = Vector2.ZERO
var _hover_btn : int          = -1
var _focus_btn: int           = BTN_PLAY
var _hover_opt: int           = -1
var _show_options: bool       = false
var _time_ms   : float        = 0.0
var _options_panel_rect: Rect2 = Rect2()

# -------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time_ms += delta * 1000.0
	_mouse_pos = get_viewport().get_mouse_position()
	_refresh_hit_regions()
	_hover_btn = -1
	_hover_opt = -1
	if not _show_options:
		_hover_btn = _find_button_at(_mouse_pos)
		if _hover_btn >= 0:
			_focus_btn = _hover_btn
	if _show_options:
		_hover_opt = _find_option_at(_mouse_pos)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_refresh_hit_regions()
		var click_pos: Vector2 = event.position
		if _show_options:
			var clicked_opt_only: int = _find_option_at(click_pos)
			if clicked_opt_only >= 0:
				_toggle_option(clicked_opt_only)
				queue_redraw()
				return
			if not _options_panel_rect.has_point(click_pos):
				_show_options = false
				queue_redraw()
				return
			return
		var clicked_opt: int = _find_option_at(click_pos)
		if _show_options and clicked_opt >= 0:
			_toggle_option(clicked_opt)
			queue_redraw()
			return
		var clicked_btn: int = _find_button_at(click_pos)
		if _show_options and clicked_btn < 0 and not _options_panel_rect.has_point(click_pos):
			_show_options = false
			queue_redraw()
			return
		if clicked_btn >= 0:
			_focus_btn = clicked_btn
			_activate_button(clicked_btn)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if _show_options:
		match event.keycode:
			KEY_O, KEY_S, KEY_ESCAPE:
				_show_options = false
				queue_redraw()
			KEY_F1:
				_toggle_option(OPT_SOUND)
			KEY_F2:
				_toggle_option(OPT_MUSIC)
		return
	match event.keycode:
		KEY_LEFT, KEY_UP:
			_cycle_focus(-1)
			queue_redraw()
		KEY_RIGHT, KEY_DOWN, KEY_TAB:
			_cycle_focus(1)
			queue_redraw()
		KEY_ENTER, KEY_SPACE:
			_activate_button(_focus_btn)
		KEY_O, KEY_S:
			_show_options = not _show_options
			queue_redraw()
		KEY_F1: _toggle_option(OPT_SOUND)
		KEY_F2: _toggle_option(OPT_MUSIC)
		KEY_ESCAPE:           get_tree().quit()

func _activate_button(btn_id: int) -> void:
	match btn_id:
		BTN_PLAY:
			_start_game()
		BTN_SETTINGS:
			_show_options = not _show_options
			queue_redraw()
		BTN_QUIT:
			get_tree().quit()

func _cycle_focus(step: int) -> void:
	_focus_btn = wrapi(_focus_btn + step, 0, _btn_rects.size())

func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")

# =========================================================================
# DRAWING
# =========================================================================

func _draw() -> void:
	_draw_professional_title()

# -------------------------------------------------------------------------
# Background helpers
# -------------------------------------------------------------------------

func _draw_bg_grid(vp: Rect2) -> void:
	var spacing  := 60.0
	var grid_col := Color(1.0, 1.0, 1.0, 0.03)
	for i in range(int(vp.size.x / spacing) + 1):
		draw_line(Vector2(i * spacing, 0.0), Vector2(i * spacing, vp.size.y), grid_col, 1.0)
	for i in range(int(vp.size.y / spacing) + 1):
		draw_line(Vector2(0.0, i * spacing), Vector2(vp.size.x, i * spacing), grid_col, 1.0)

func _draw_prison_bars(vp: Rect2) -> void:
	var bar_col   := Color(0.10, 0.14, 0.22, 0.90)
	var bar_w     := 20.0
	var bar_gap   := 50.0
	var bar_count := 5

	for side in [0, 1]:
		for i in range(bar_count):
			var bx: float
			if side == 0:
				bx = 8.0 + float(i) * bar_gap
			else:
				bx = vp.size.x - 8.0 - float(i + 1) * bar_gap

			# Base fill
			draw_rect(Rect2(bx, 0.0, bar_w, vp.size.y), bar_col)
			# Left edge bright line
			draw_line(Vector2(bx + 2.0, 0.0), Vector2(bx + 2.0, vp.size.y),
				Color(0.35, 0.45, 0.65, 0.55), 1.0)
			# Center wide highlight
			draw_line(Vector2(bx + bar_w * 0.5, 0.0), Vector2(bx + bar_w * 0.5, vp.size.y),
				Color(0.50, 0.62, 0.80, 0.28), 2.0)
			# Right edge sheen
			draw_line(Vector2(bx + bar_w - 3.0, 0.0), Vector2(bx + bar_w - 3.0, vp.size.y),
				Color(0.28, 0.36, 0.52, 0.38), 1.0)
			# Border outline
			draw_rect(Rect2(bx, 0.0, bar_w, vp.size.y), Color(0.20, 0.30, 0.50, 0.45), false)

func _draw_vignette(vp: Rect2) -> void:
	for i in range(8):
		var t     := float(i) / 8.0
		var inset := t * 180.0
		var alpha := (1.0 - t) * 0.55
		var col   := Color(0.0, 0.0, 0.0, alpha)
		var strip := (180.0 - inset) * 0.5
		draw_rect(Rect2(inset, inset, vp.size.x - inset * 2.0, strip), col)
		draw_rect(Rect2(inset, vp.size.y - inset - strip, vp.size.x - inset * 2.0, strip), col)
		draw_rect(Rect2(inset, inset, strip, vp.size.y - inset * 2.0), col)
		draw_rect(Rect2(vp.size.x - inset - strip, inset, strip, vp.size.y - inset * 2.0), col)

func _draw_corner_brackets(vp: Rect2) -> void:
	var arm    := 40.0
	var thick  := 2.0
	var margin := 18.0
	var col    := Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.65)
	# Top-left
	draw_line(Vector2(margin, margin), Vector2(margin + arm, margin), col, thick)
	draw_line(Vector2(margin, margin), Vector2(margin, margin + arm), col, thick)
	# Top-right
	draw_line(Vector2(vp.size.x - margin, margin), Vector2(vp.size.x - margin - arm, margin), col, thick)
	draw_line(Vector2(vp.size.x - margin, margin), Vector2(vp.size.x - margin, margin + arm), col, thick)
	# Bottom-left
	draw_line(Vector2(margin, vp.size.y - margin), Vector2(margin + arm, vp.size.y - margin), col, thick)
	draw_line(Vector2(margin, vp.size.y - margin), Vector2(margin, vp.size.y - margin - arm), col, thick)
	# Bottom-right
	draw_line(Vector2(vp.size.x - margin, vp.size.y - margin),
			  Vector2(vp.size.x - margin - arm, vp.size.y - margin), col, thick)
	draw_line(Vector2(vp.size.x - margin, vp.size.y - margin),
			  Vector2(vp.size.x - margin, vp.size.y - margin - arm), col, thick)

func _draw_ambient_dots(vp: Rect2, t_sec: float) -> void:
	var dots := [
		[0.18, 0.35, 12.0, 8.0,  0.0],
		[0.82, 0.55, 8.0,  14.0, 2.1],
		[0.50, 0.82, 10.0, 6.0,  4.2],
	]
	for d in dots:
		var dx := vp.size.x * float(d[0]) + sin(t_sec * 0.7 + float(d[4])) * float(d[2])
		var dy := vp.size.y * float(d[1]) + cos(t_sec * 0.5 + float(d[4])) * float(d[3])
		draw_circle(Vector2(dx, dy), 2.5, Color(1.0, 1.0, 1.0, 0.07))
		draw_circle(Vector2(dx, dy), 1.2, Color(1.0, 1.0, 1.0, 0.13))

func _draw_button(rect: Rect2, label: String, hovered: bool, accent: Color, font: Font) -> void:
	var r := rect

	if hovered:
		var pad := (r.size * (1.06 - 1.0)) * 0.5
		r = Rect2(r.position - pad, r.size * 1.06)

	var bg_alpha := 0.88 if hovered else 0.58
	var bd_alpha := 0.85 if hovered else 0.42

	# Drop shadow
	draw_rect(Rect2(r.position + Vector2(4, 4), r.size), Color(0.0, 0.0, 0.0, 0.45))
	# Body fill
	draw_rect(r, Color(accent.r * 0.20, accent.g * 0.20, accent.b * 0.20, bg_alpha))
	# Left accent strip
	draw_rect(Rect2(r.position, Vector2(6.0, r.size.y)), accent)
	# Border
	draw_rect(r, Color(accent.r, accent.g, accent.b, bd_alpha), false)
	# Top inner highlight
	draw_line(r.position + Vector2(1, 1), r.position + Vector2(r.size.x - 1, 1),
		Color(1, 1, 1, 0.15 if hovered else 0.08), 1.0)
	# Diagonal glint on hover
	if hovered:
		draw_line(r.position + Vector2(r.size.x * 0.3, 0),
				  r.position + Vector2(r.size.x * 0.55, r.size.y),
			Color(1, 1, 1, 0.07), 8.0)

	if font == null:
		return

	# Centred label: char_count * font_size * 0.30 = approximate half-width
	var fs       := 22
	var text_off := float(label.length()) * float(fs) * 0.30
	var tc       := (Color(accent.r * 1.25, accent.g * 1.25, accent.b * 1.25) \
					if hovered else accent).clamp()
	draw_string(font,
		Vector2(r.position.x + r.size.x * 0.5 - text_off, r.position.y + r.size.y * 0.65),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)

func _draw_professional_title() -> void:
	_refresh_hit_regions()
	var vp: Rect2 = get_viewport_rect()
	var font: Font = ThemeDB.fallback_font
	var t_sec: float = _time_ms * 0.001
	var pulse: float = 0.5 + 0.5 * sin(t_sec * 1.6)
	var cx: float = vp.size.x * 0.5
	var outer_margin: float = clampf(vp.size.x * 0.024, 24.0, 36.0)
	var frame: Rect2 = Rect2(
		outer_margin,
		outer_margin,
		vp.size.x - outer_margin * 2.0,
		vp.size.y - outer_margin * 2.0
	)
	var header_h: float = clampf(vp.size.y * 0.20, 138.0, 188.0)
	var footer_h: float = clampf(vp.size.y * 0.24, 152.0, 206.0)
	var content_gap: float = clampf(vp.size.y * 0.014, 10.0, 16.0)
	var header_rect: Rect2 = Rect2(frame.position.x, frame.position.y, frame.size.x, header_h)
	var footer_rect: Rect2 = Rect2(frame.position.x, frame.end.y - footer_h, frame.size.x, footer_h)
	var content_rect: Rect2 = Rect2(
		frame.position.x,
		header_rect.end.y + content_gap,
		frame.size.x,
		footer_rect.position.y - (header_rect.end.y + content_gap) - content_gap
	)

	draw_rect(vp, Color(0.030, 0.040, 0.060))
	_draw_title_backdrop(vp, t_sec)
	_draw_title_frame(vp)
	_draw_title_panel(frame, pulse)
	_draw_rounded_panel(header_rect, 12.0, Color(0.02, 0.06, 0.09, 0.76), Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.26), 1.0)
	_draw_rounded_panel(content_rect, 12.0, Color(0.02, 0.05, 0.08, 0.82), Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.28), 1.0)
	_draw_rounded_panel(footer_rect, 12.0, Color(0.02, 0.05, 0.07, 0.76), Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.26), 1.0)
	_draw_scanline_overlay(header_rect, t_sec)

	if font != null:
		var title_size: int = int(clampf(vp.size.y * 0.080, 54.0, 92.0))
		var subtitle_size: int = int(clampf(vp.size.y * 0.030, 21.0, 32.0))
		var tag_size: int = int(clampf(vp.size.y * 0.022, 15.0, 21.0))
		_draw_centered_text(font, "PRISON BREAK", Vector2(cx, header_rect.position.y + header_rect.size.y * 0.36), title_size, C_HIGHLIGHT)
		_draw_centered_text(font, "DUAL ESCAPE SHOWDOWN", Vector2(cx, header_rect.position.y + header_rect.size.y * 0.62), subtitle_size, C_WARNING)
		_draw_centered_text(font, "⚠ FACILITY STATUS: LOCKDOWN ACTIVE  ·  EXIT ROTATION: LIVE", Vector2(cx, header_rect.position.y + header_rect.size.y * 0.80), 15, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.84))
		_draw_centered_text(font, "Three minds. One exit. No clean way out.", Vector2(cx, header_rect.position.y + header_rect.size.y * 0.93), tag_size, C_DIM)

	if not _show_options:
		_draw_title_character_lineup(content_rect, font, pulse)

	var btn_gap: float = clampf(vp.size.x * 0.014, 10.0, 18.0)
	var btn_h: float = clampf(footer_rect.size.y * 0.48, 64.0, 86.0)
	var btn_w: float = (footer_rect.size.x - btn_gap * 2.0 - 34.0) / 3.0
	var btn_y: float = footer_rect.position.y + clampf(footer_rect.size.y * 0.16, 14.0, 30.0)
	var btn_x0: float = footer_rect.position.x + 17.0
	_btn_rects[BTN_PLAY] = Rect2(btn_x0, btn_y, btn_w, btn_h)
	_btn_rects[BTN_SETTINGS] = Rect2(btn_x0 + btn_w + btn_gap, btn_y, btn_w, btn_h)
	_btn_rects[BTN_QUIT] = Rect2(btn_x0 + (btn_w + btn_gap) * 2.0, btn_y, btn_w, btn_h)
	_draw_menu_button(_btn_rects[BTN_PLAY], "PLAY", BTN_PLAY == _hover_btn, _focus_btn == BTN_PLAY, C_HIGHLIGHT, font, true)
	_draw_menu_button(_btn_rects[BTN_SETTINGS], "SETTINGS", BTN_SETTINGS == _hover_btn, _focus_btn == BTN_SETTINGS, C_WARNING, font, false)
	_draw_menu_button(_btn_rects[BTN_QUIT], "QUIT", BTN_QUIT == _hover_btn, _focus_btn == BTN_QUIT, Color(0.78, 0.28, 0.24), font, false)

	if _show_options:
		draw_rect(vp, Color(0.0, 0.0, 0.0, 0.44))
		_draw_options_panel(frame, font)

	if font != null:
		_draw_centered_text(font, "[ENTER/SPACE] PLAY   [S] SETTINGS   [ESC] QUIT   [TAB/ARROWS] MOVE FOCUS",
			Vector2(cx, footer_rect.end.y - 18.0), 16, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.96))
		_draw_centered_text(font, "Build 0.4.2  ·  Security Grid Online", Vector2(frame.end.x - 180.0, frame.end.y - 8.0), 12, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.70))

func _draw_title_backdrop(vp: Rect2, t_sec: float) -> void:
	var grid_col := Color(0.70, 0.84, 0.90, 0.045)
	var spacing := 72.0
	for ix in range(int(vp.size.x / spacing) + 2):
		var x := float(ix) * spacing + fmod(t_sec * 5.0, spacing)
		draw_line(Vector2(x, 0.0), Vector2(x, vp.size.y), grid_col, 1.0)
	for iy in range(int(vp.size.y / spacing) + 2):
		var y := float(iy) * spacing
		draw_line(Vector2(0.0, y), Vector2(vp.size.x, y), grid_col, 1.0)

	for side in [0, 1]:
		for i in range(4):
			var x_pos := 30.0 + float(i) * 58.0
			if side == 1:
				x_pos = vp.size.x - 54.0 - float(i) * 58.0
			draw_rect(Rect2(x_pos, 0.0, 18.0, vp.size.y),
				Color(0.09, 0.13, 0.18, 0.78))
			draw_line(Vector2(x_pos + 4.0, 0.0), Vector2(x_pos + 4.0, vp.size.y),
				Color(0.52, 0.64, 0.72, 0.22), 1.0)

	for i in range(10):
		var inset := float(i) * 24.0
		var alpha := 0.22 * (1.0 - float(i) / 10.0)
		draw_rect(Rect2(inset, inset, vp.size.x - inset * 2.0, vp.size.y - inset * 2.0),
			Color(0.0, 0.0, 0.0, alpha), false, 8.0)

func _draw_title_frame(vp: Rect2) -> void:
	var col := Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.48)
	var m := 28.0
	var arm := 54.0
	draw_line(Vector2(m, m), Vector2(m + arm, m), col, 2.0)
	draw_line(Vector2(m, m), Vector2(m, m + arm), col, 2.0)
	draw_line(Vector2(vp.size.x - m, m), Vector2(vp.size.x - m - arm, m), col, 2.0)
	draw_line(Vector2(vp.size.x - m, m), Vector2(vp.size.x - m, m + arm), col, 2.0)
	draw_line(Vector2(m, vp.size.y - m), Vector2(m + arm, vp.size.y - m), col, 2.0)
	draw_line(Vector2(m, vp.size.y - m), Vector2(m, vp.size.y - m - arm), col, 2.0)
	draw_line(Vector2(vp.size.x - m, vp.size.y - m), Vector2(vp.size.x - m - arm, vp.size.y - m), col, 2.0)
	draw_line(Vector2(vp.size.x - m, vp.size.y - m), Vector2(vp.size.x - m, vp.size.y - m - arm), col, 2.0)

func _draw_title_panel(panel: Rect2, pulse: float) -> void:
	draw_rect(Rect2(panel.position + Vector2(8.0, 10.0), panel.size), Color(0, 0, 0, 0.36))
	draw_rect(panel, Color(0.045, 0.075, 0.095, 0.92))
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 5.0)), C_HIGHLIGHT)
	draw_rect(panel, Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.32 + pulse * 0.12), false, 2.0)
	var upper_divider_y: float = panel.position.y + clampf(panel.size.y * 0.25, 170.0, 240.0)
	var lower_divider_y: float = panel.end.y - clampf(panel.size.y * 0.22, 150.0, 220.0)
	draw_line(Vector2(panel.position.x + 28.0, upper_divider_y), Vector2(panel.end.x - 28.0, upper_divider_y),
		Color(1, 1, 1, 0.10), 1.0)
	draw_line(Vector2(panel.position.x + 28.0, lower_divider_y), Vector2(panel.end.x - 28.0, lower_divider_y),
		Color(1, 1, 1, 0.08), 1.0)

func _draw_mode_tags(content_rect: Rect2, font: Font) -> void:
	var labels: Array[String] = ["MINIMAX RED", "MCTS BLUE", "FUZZY POLICE"]
	var cols: Array[Color] = [C_RED_AG, Color(0.18, 1.00, 0.92), C_WARNING]
	var gap: float = clampf(content_rect.size.x * 0.012, 10.0, 18.0)
	var tag_h: float = clampf(content_rect.size.y * 0.16, 40.0, 56.0)
	var tag_w: float = (content_rect.size.x - gap * 2.0 - 34.0) / 3.0
	var x0: float = content_rect.position.x + 17.0
	var y: float = content_rect.position.y + 16.0
	for i in range(3):
		var r: Rect2 = Rect2(x0 + float(i) * (tag_w + gap), y, tag_w, tag_h)
		draw_rect(r, Color(cols[i].r * 0.16, cols[i].g * 0.16, cols[i].b * 0.16, 0.82))
		draw_rect(Rect2(r.position, Vector2(5.0, r.size.y)), cols[i])
		draw_rect(r, Color(cols[i].r, cols[i].g, cols[i].b, 0.36), false)
		if font != null:
			_draw_centered_text(font, labels[i], Vector2(r.get_center().x, r.position.y + r.size.y * 0.64), 18, cols[i])

func _draw_title_character_lineup(content_rect: Rect2, font: Font, pulse: float) -> void:
	var gap: float = clampf(content_rect.size.x * 0.012, 10.0, 18.0)
	var card_w: float = (content_rect.size.x - gap * 2.0 - 34.0) / 3.0
	var card_top: float = content_rect.position.y + 18.0
	var card_h: float = content_rect.end.y - card_top - 18.0
	var y: float = card_top
	var x0: float = content_rect.position.x + 17.0
	var roles: Array[String] = ["rusher_red", "sneaky_blue", "police"]
	var titles: Array[String] = ["Rusher Red", "Sneaky Blue", "Police Hunter"]
	var ai_tags: Array[String] = ["MINIMAX", "MCTS / MONTE CARLO", "FUZZY"]
	var taglines: Array[String] = [
		"aggressive escape artist",
		"cautious route planner",
		"adaptive jailor",
	]
	var role_icons: Array[String] = ["⚡", "🧠", "🛡"]
	for i in range(3):
		var rect: Rect2 = Rect2(x0 + float(i) * (card_w + gap), y, card_w, card_h)
		var role_col: Color = C_WARNING
		if roles[i] == "rusher_red":
			role_col = C_RED_AG
		elif roles[i] == "sneaky_blue":
			role_col = Color(0.18, 1.00, 0.92)
		var center_boost: float = 1.0 + (0.05 * pulse if roles[i] == "police" else 0.0)
		var draw_rect_card: Rect2 = rect
		if roles[i] == "police":
			var grow: float = 4.0 * center_boost
			draw_rect_card = Rect2(rect.position - Vector2(grow, grow * 0.6), rect.size + Vector2(grow * 2.0, grow * 1.2))
		draw_rect(Rect2(draw_rect_card.position + Vector2(5.0, 6.0), draw_rect_card.size), Color(0, 0, 0, 0.34))
		_draw_rounded_panel(draw_rect_card, 10.0, Color(0.02, 0.05, 0.08, 0.94), Color(role_col.r, role_col.g, role_col.b, 0.42), 1.0)
		var header_h: float = 38.0
		draw_rect(Rect2(draw_rect_card.position, Vector2(draw_rect_card.size.x, header_h)), Color(role_col.r * 0.18, role_col.g * 0.18, role_col.b * 0.18, 0.96))
		draw_rect(Rect2(draw_rect_card.position, Vector2(draw_rect_card.size.x, 5.0)), role_col)
		draw_rect(Rect2(draw_rect_card.position.x + 8.0, draw_rect_card.position.y + header_h - 1.0, draw_rect_card.size.x - 16.0, 1.0), Color(1, 1, 1, 0.12))
		if font != null:
			draw_string(font, draw_rect_card.position + Vector2(10.0, 25.0), "%s %s" % [role_icons[i], ai_tags[i]], HORIZONTAL_ALIGNMENT_LEFT, draw_rect_card.size.x - 20.0, 16, role_col)
		var portrait_w: float = clampf(draw_rect_card.size.x * 0.42, 150.0, 210.0)
		var portrait_rect: Rect2 = Rect2(draw_rect_card.position.x + 12.0, draw_rect_card.position.y + header_h + 8.0, portrait_w, draw_rect_card.size.y - header_h - 20.0)
		_draw_character_preview(portrait_rect, roles[i], role_col)
		if font != null:
			var tx: float = portrait_rect.end.x + 14.0
			var tw: float = draw_rect_card.end.x - tx - 12.0
			draw_string(font, Vector2(tx, draw_rect_card.position.y + header_h + 34.0), titles[i], HORIZONTAL_ALIGNMENT_LEFT, tw, 30, role_col)
			draw_string(font, Vector2(tx, draw_rect_card.position.y + header_h + 60.0), taglines[i], HORIZONTAL_ALIGNMENT_LEFT, tw, 17, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.90))
			var chip_labels: Array[String] = ["⚡ SPD", "👣 STL", "🧨 RISK"]
			if roles[i] == "police":
				chip_labels = ["🛡 CTRL", "🚨 ALERT", "🎯 CAP"]
			var chip_w: float = clampf((tw - 22.0) / 3.0, 78.0, 110.0)
			var chip_h: float = 38.0
			var chip_y: float = draw_rect_card.end.y - chip_h - 16.0
			for c in range(3):
				draw_string(font, Vector2(tx + float(c) * (chip_w + 8.0), chip_y - 7.0), chip_labels[c], HORIZONTAL_ALIGNMENT_LEFT, chip_w, 12, C_DIM)
			_draw_chip(Rect2(tx + 0.0, chip_y, chip_w, chip_h), _chip_for_role(roles[i], "c1"), role_col, font)
			_draw_chip(Rect2(tx + chip_w + 8.0, chip_y, chip_w, chip_h), _chip_for_role(roles[i], "c2"), role_col, font)
			_draw_chip(Rect2(tx + (chip_w + 8.0) * 2.0, chip_y, chip_w, chip_h), _chip_for_role(roles[i], "c3"), role_col, font)

func _chip_for_role(role: String, kind: String) -> String:
	if role == "rusher_red":
		if kind == "c1":
			return "92"
		if kind == "c2":
			return "38"
		return "88"
	if role == "sneaky_blue":
		if kind == "c1":
			return "71"
		if kind == "c2":
			return "95"
		return "44"
	if kind == "c1":
		return "90"
	if kind == "c2":
		return "82"
	return "94"

func _draw_chip(rect: Rect2, label: String, accent: Color, font: Font) -> void:
	_draw_rounded_panel(rect, 7.0, Color(accent.r * 0.15, accent.g * 0.15, accent.b * 0.15, 0.92), Color(accent.r, accent.g, accent.b, 0.52), 1.0)
	if font != null:
		draw_rect(Rect2(rect.position.x + 2.0, rect.position.y + 2.0, rect.size.x - 4.0, 4.0), Color(1, 1, 1, 0.12))
		_draw_centered_text(font, label, Vector2(rect.get_center().x, rect.position.y + 25.0), 18, Color(accent.r, accent.g, accent.b, 0.98))

func _draw_character_preview(rect: Rect2, role: String, accent: Color) -> void:
	var t_sec: float = _time_ms * 0.001
	var drift: float = sin(t_sec * 1.7) * 2.4
	var glow_rect: Rect2 = rect.grow(3.0)
	_draw_rounded_panel(glow_rect, 9.0, Color(accent.r * 0.12, accent.g * 0.12, accent.b * 0.12, 0.18), Color(accent.r, accent.g, accent.b, 0.20), 1.0)
	var body_rect: Rect2 = Rect2(rect.position.x + 2.0, rect.position.y + 2.0, rect.size.x - 4.0, rect.size.y - 4.0)
	_draw_rounded_panel(rect, 8.0, Color(0.01, 0.03, 0.05, 0.98), Color(accent.r, accent.g, accent.b, 0.42), 1.0)
	draw_rect(Rect2(body_rect.position.x, body_rect.position.y + body_rect.size.y * 0.52, body_rect.size.x, 2.0), Color(1.0, 1.0, 1.0, 0.10))
	draw_rect(Rect2(body_rect.position.x + 4.0, body_rect.position.y + 4.0, body_rect.size.x - 8.0, 3.0), Color(accent.r, accent.g, accent.b, 0.34))
	_draw_scanline_overlay(body_rect, t_sec)
	var role_rect: Rect2 = body_rect.grow(-1.0)
	role_rect.position.y += drift
	var facing_sign: float = 1.0 if sin(t_sec * 1.2) >= 0.0 else -1.0
	CharacterPreview.draw_role(self, role_rect, role, t_sec, 1.0, facing_sign)

func _draw_scanline_overlay(rect: Rect2, t_sec: float) -> void:
	var y: float = rect.position.y + fposmod(t_sec * 90.0, maxf(1.0, rect.size.y - 6.0))
	draw_rect(Rect2(rect.position.x, y, rect.size.x, 2.0), Color(0.20, 0.95, 1.0, 0.06))

func _draw_menu_button(rect: Rect2, label: String, hovered: bool, focused: bool, accent: Color, font: Font, primary: bool) -> void:
	var r: Rect2 = rect
	var t_sec: float = _time_ms * 0.001
	var breathe: float = 1.0 + (0.014 * sin(t_sec * 3.4 + float(label.length())))
	if hovered or focused:
		r = Rect2(r.position - Vector2(6.0, 6.0), r.size + Vector2(12.0, 12.0))
	var pulse_scale: float = 1.05 if hovered or focused else breathe
	var pad: Vector2 = (r.size * (pulse_scale - 1.0)) * 0.5
	r = Rect2(r.position - pad, r.size * pulse_scale)
	var shadow_rect: Rect2 = Rect2(r.position + Vector2(5.0, 6.0), r.size)
	_draw_rounded_panel(shadow_rect, 11.0, Color(0, 0, 0, 0.40), Color(0, 0, 0, 0.0), 0.0)
	var fill_boost: float = 0.20 if primary else 0.14
	var fill_alpha: float = 0.96 if hovered or focused else 0.78
	_draw_rounded_panel(r, 11.0, Color(accent.r * fill_boost, accent.g * fill_boost, accent.b * fill_boost, fill_alpha), Color(accent.r, accent.g, accent.b, 0.94 if hovered or focused else 0.52), 2.0)
	_draw_rounded_panel(Rect2(r.position.x, r.position.y, 8.0, r.size.y), 5.0, accent, Color(accent.r, accent.g, accent.b, 0.0), 0.0)
	if hovered or focused:
		var shine_w: float = r.size.x * 0.33
		draw_rect(Rect2(r.position.x + r.size.x * 0.06, r.position.y + 3.0, shine_w, 5.0), Color(1, 1, 1, 0.14))
	if focused:
		draw_rect(r.grow(2.0), Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, 0.30), false, 2.0)
	if font != null:
		var icon: String = ""
		if label == "PLAY":
			icon = "▶"
		elif label == "SETTINGS":
			icon = "⚙"
		elif label == "QUIT":
			icon = "⏻"
		draw_string(font, Vector2(r.position.x + 14.0, r.position.y + r.size.y * 0.66), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(accent.r * 1.20, accent.g * 1.20, accent.b * 1.20).clamp())
		_draw_centered_text(font, label, Vector2(r.get_center().x + 10.0, r.position.y + r.size.y * 0.64),
			24, Color(accent.r * 1.20, accent.g * 1.20, accent.b * 1.20).clamp())

func _draw_centered_text(font: Font, text: String, pos: Vector2, size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(pos.x - width * 0.5, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw_options_panel(_panel: Rect2, font: Font) -> void:
	if font == null:
		return
	_refresh_hit_regions()
	var rect: Rect2 = _options_panel_rect
	_draw_rounded_panel(rect, 12.0, Color(0.02, 0.04, 0.06, 0.94), Color(0.18, 0.42, 0.60, 0.58), 2.0)
	_draw_centered_text(font, "SETTINGS", Vector2(rect.get_center().x, rect.position.y + 34.0), 24, C_WARNING)
	_draw_centered_text(font, "Esc / S to close", Vector2(rect.get_center().x, rect.position.y + rect.size.y - 16.0), 16, C_DIM)

	var items: Array[String] = [
		"SFX",
		"MUSIC",
		"SHAKE",
		"TRAILS",
		"BLOOM",
		"FOG",
	]
	var values: Array[bool] = [
		UserSettings.sound_enabled,
		UserSettings.music_enabled,
		UserSettings.screen_shake_enabled,
		UserSettings.motion_trails_enabled,
		UserSettings.bloom_glow_enabled,
		UserSettings.volumetric_fog_enabled,
	]

	_draw_scanline_overlay(rect, _time_ms * 0.001)
	for i in range(items.size()):
		var r: Rect2 = _option_rects[i]
		var hover: bool = i == _hover_opt
		var on: bool = values[i]
		var accent: Color = C_HIGHLIGHT if on else Color(0.46, 0.54, 0.64)
		_draw_rounded_panel(r, 8.0, Color(accent.r * 0.18, accent.g * 0.18, accent.b * 0.18, 0.94 if hover else 0.78), Color(accent.r, accent.g, accent.b, 0.92 if hover else 0.52), 1.0)
		_draw_centered_text(font, items[i], Vector2(r.get_center().x, r.position.y + 21.0), 13, C_DIM)
		_draw_centered_text(font, "ON" if on else "OFF", Vector2(r.get_center().x, r.position.y + 46.0), 20, accent)

func _toggle_option(idx: int) -> void:
	match idx:
		OPT_SOUND:
			UserSettings.toggle_sound_enabled()
		OPT_MUSIC:
			UserSettings.toggle_music_enabled()
		OPT_SHAKE:
			UserSettings.toggle_screen_shake_enabled()
		OPT_TRAILS:
			UserSettings.toggle_motion_trails_enabled()
		OPT_BLOOM:
			UserSettings.toggle_bloom_glow_enabled()
		OPT_FOG:
			UserSettings.toggle_volumetric_fog_enabled()

func _refresh_hit_regions() -> void:
	var vp: Rect2 = get_viewport_rect()
	var outer_margin: float = clampf(vp.size.x * 0.024, 24.0, 36.0)
	var frame: Rect2 = Rect2(
		outer_margin,
		outer_margin,
		vp.size.x - outer_margin * 2.0,
		vp.size.y - outer_margin * 2.0
	)
	var footer_h: float = clampf(vp.size.y * 0.22, 136.0, 188.0)
	var footer_rect: Rect2 = Rect2(frame.position.x, frame.end.y - footer_h, frame.size.x, footer_h)

	var btn_gap: float = clampf(vp.size.x * 0.014, 10.0, 18.0)
	var btn_h: float = clampf(footer_rect.size.y * 0.44, 58.0, 78.0)
	var btn_w: float = (footer_rect.size.x - btn_gap * 2.0 - 34.0) / 3.0
	var btn_y: float = footer_rect.position.y + clampf(footer_rect.size.y * 0.18, 18.0, 36.0)
	var btn_x0: float = footer_rect.position.x + 17.0
	_btn_rects[BTN_PLAY] = Rect2(btn_x0, btn_y, btn_w, btn_h)
	_btn_rects[BTN_SETTINGS] = Rect2(btn_x0 + btn_w + btn_gap, btn_y, btn_w, btn_h)
	_btn_rects[BTN_QUIT] = Rect2(btn_x0 + (btn_w + btn_gap) * 2.0, btn_y, btn_w, btn_h)

	var options_w: float = clampf(frame.size.x * 0.56, 520.0, 860.0)
	var options_h: float = clampf(frame.size.y * 0.56, 330.0, 500.0)
	var options_x: float = frame.position.x + (frame.size.x - options_w) * 0.5
	var options_y: float = frame.position.y + (frame.size.y - options_h) * 0.5
	_options_panel_rect = Rect2(options_x, options_y, options_w, options_h)
	_option_rects.resize(6)
	var cols: int = 2
	var gap_x: float = 14.0
	var gap_y: float = 12.0
	var inset_x: float = 18.0
	var inset_y: float = 62.0
	var option_w: float = (_options_panel_rect.size.x - inset_x * 2.0 - gap_x * float(cols - 1)) / float(cols)
	var option_h: float = clampf((_options_panel_rect.size.y - inset_y - 56.0 - gap_y * 2.0) / 3.0, 70.0, 98.0)
	var option_y: float = _options_panel_rect.position.y + inset_y
	for i in range(6):
		var col_idx: int = i % cols
		var row_idx: int = i / cols
		_option_rects[i] = Rect2(
			_options_panel_rect.position.x + inset_x + float(col_idx) * (option_w + gap_x),
			option_y + float(row_idx) * (option_h + gap_y),
			option_w,
			option_h
		)

func _draw_rounded_panel(rect: Rect2, radius: float, fill_color: Color, border_color: Color, border_width: float) -> void:
	var r: float = clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	if r <= 0.0:
		draw_rect(rect, fill_color)
		if border_width > 0.0 and border_color.a > 0.0:
			draw_rect(rect, border_color, false, border_width)
		return

	var core: Rect2 = Rect2(rect.position.x + r, rect.position.y, rect.size.x - r * 2.0, rect.size.y)
	var side_l: Rect2 = Rect2(rect.position.x, rect.position.y + r, r, rect.size.y - r * 2.0)
	var side_r: Rect2 = Rect2(rect.end.x - r, rect.position.y + r, r, rect.size.y - r * 2.0)
	draw_rect(core, fill_color)
	draw_rect(side_l, fill_color)
	draw_rect(side_r, fill_color)
	draw_circle(rect.position + Vector2(r, r), r, fill_color)
	draw_circle(Vector2(rect.end.x - r, rect.position.y + r), r, fill_color)
	draw_circle(Vector2(rect.position.x + r, rect.end.y - r), r, fill_color)
	draw_circle(rect.end - Vector2(r, r), r, fill_color)

	if border_width > 0.0 and border_color.a > 0.0:
		draw_arc(rect.position + Vector2(r, r), r, PI, PI * 1.5, 14, border_color, border_width)
		draw_arc(Vector2(rect.end.x - r, rect.position.y + r), r, PI * 1.5, TAU, 14, border_color, border_width)
		draw_arc(Vector2(rect.position.x + r, rect.end.y - r), r, PI * 0.5, PI, 14, border_color, border_width)
		draw_arc(rect.end - Vector2(r, r), r, 0.0, PI * 0.5, 14, border_color, border_width)
		draw_line(Vector2(rect.position.x + r, rect.position.y), Vector2(rect.end.x - r, rect.position.y), border_color, border_width)
		draw_line(Vector2(rect.position.x + r, rect.end.y), Vector2(rect.end.x - r, rect.end.y), border_color, border_width)
		draw_line(Vector2(rect.position.x, rect.position.y + r), Vector2(rect.position.x, rect.end.y - r), border_color, border_width)
		draw_line(Vector2(rect.end.x, rect.position.y + r), Vector2(rect.end.x, rect.end.y - r), border_color, border_width)

func _find_button_at(pos: Vector2) -> int:
	for i in range(_btn_rects.size()):
		if _btn_rects[i].has_point(pos):
			return i
	return -1

func _find_option_at(pos: Vector2) -> int:
	if not _show_options:
		return -1
	for i in range(_option_rects.size()):
		if _option_rects[i].has_point(pos):
			return i
	return -1

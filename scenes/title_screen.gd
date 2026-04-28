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
const BTN_QUIT : int = 1

var _btn_rects : Array[Rect2] = [Rect2(), Rect2()]
var _mouse_pos : Vector2      = Vector2.ZERO
var _hover_btn : int          = -1
var _time_ms   : float        = 0.0

# -------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time_ms += delta * 1000.0
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
			BTN_PLAY: _start_game()
			BTN_QUIT: get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ENTER, KEY_SPACE: _start_game()
		KEY_ESCAPE:           get_tree().quit()

func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")

# =========================================================================
# DRAWING
# =========================================================================

func _draw() -> void:
	_draw_professional_title()
	return

	var vp    := get_viewport_rect()
	var cx    := vp.size.x * 0.5
	var cy    := vp.size.y * 0.5
	var font  := ThemeDB.fallback_font
	var t_sec := _time_ms * 0.001
	var pulse := sin(t_sec * 1.8) * 0.5 + 0.5   # 0.0-1.0 slow pulse

	# Full background
	draw_rect(vp, C_BG)

	# Subtle background grid
	_draw_bg_grid(vp)

	# Prison bars with metallic sheen
	_draw_prison_bars(vp)

	# Radial vignette overlay
	_draw_vignette(vp)

	# Corner bracket decorations
	_draw_corner_brackets(vp)

	# -- Title block ----------------------------------------------------------
	if font != null:
		var title_y := cy - 180.0

		# "PRISON BREAK" 12 chars x 72px x 0.30 = 259 half-width approx
		var title_off := 12.0 * 72.0 * 0.30
		# Wide outer glow
		draw_string(font, Vector2(cx - title_off, title_y + 6.0), "PRISON BREAK",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 72,
			Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, 0.08 + pulse * 0.05))
		# Inner glow
		draw_string(font, Vector2(cx - title_off, title_y + 3.0), "PRISON BREAK",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 72,
			Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, 0.18 + pulse * 0.06))
		# Main title
		draw_string(font, Vector2(cx - title_off, title_y), "PRISON BREAK",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 72, C_HIGHLIGHT)

		# "TRIPLE THREAT ESCAPE CHALLENGE" 30 chars x 24px x 0.30 = 216
		var sub_off := 30.0 * 24.0 * 0.30
		draw_string(font, Vector2(cx - sub_off, title_y + 52.0),
			"TRIPLE THREAT ESCAPE CHALLENGE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, C_WARNING)

		# Tagline -- "3 agents  .  3 AI strategies  .  1 way out" ~44 chars x 17px x 0.30 = 224
		var tag_off := 44.0 * 17.0 * 0.30
		draw_string(font, Vector2(cx - tag_off, title_y + 84.0),
			"3 agents  \u00B7  3 AI strategies  \u00B7  1 way out",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, C_DIM)

	# -- Horizontal divider ---------------------------------------------------
	var div_y := cy - 80.0
	draw_line(Vector2(cx - 340.0, div_y), Vector2(cx + 340.0, div_y),
		Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.35), 1.0)
	draw_line(Vector2(cx - 200.0, div_y - 1.0), Vector2(cx + 200.0, div_y - 1.0),
		Color(C_HIGHLIGHT.r, C_HIGHLIGHT.g, C_HIGHLIGHT.b, 0.08), 1.0)

	# -- Buttons --------------------------------------------------------------
	var btn_w  := 280.0
	var btn_h  := 58.0
	var btn_x  := cx - btn_w * 0.5
	var btn_y0 := cy - 40.0
	var btn_y1 := cy + 30.0

	_btn_rects[BTN_PLAY] = Rect2(btn_x, btn_y0, btn_w, btn_h)
	_btn_rects[BTN_QUIT] = Rect2(btn_x, btn_y1, btn_w, btn_h)

	_draw_button(_btn_rects[BTN_PLAY], "PLAY", BTN_PLAY == _hover_btn, C_HIGHLIGHT, font)
	_draw_button(_btn_rects[BTN_QUIT], "QUIT", BTN_QUIT == _hover_btn, Color(0.75, 0.30, 0.30), font)

	# -- Key hints ------------------------------------------------------------
	if font != null:
		# ~38 chars x 14px x 0.30 = 160 half-width
		var hint_off := 38.0 * 14.0 * 0.30
		draw_string(font, Vector2(cx - hint_off, btn_y1 + btn_h + 22.0),
			"Enter / Space to play  \u00B7  Esc to quit",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_DIM)

	# -- Ambient animated dots ------------------------------------------------
	_draw_ambient_dots(vp, t_sec)

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
	var vp := get_viewport_rect()
	var font := ThemeDB.fallback_font
	var t_sec := _time_ms * 0.001
	var pulse := 0.5 + 0.5 * sin(t_sec * 1.6)
	var cx := vp.size.x * 0.5
	var cy := vp.size.y * 0.5

	draw_rect(vp, Color(0.035, 0.055, 0.075))
	_draw_title_backdrop(vp, t_sec)
	_draw_title_frame(vp)

	var panel_w := minf(720.0, vp.size.x - 96.0)
	var panel_h := 520.0
	var panel := Rect2(cx - panel_w * 0.5, cy - panel_h * 0.5, panel_w, panel_h)
	_draw_title_panel(panel, pulse)

	if font != null:
		_draw_centered_text(font, "PRISON BREAK", Vector2(cx, panel.position.y + 104.0), 68, C_HIGHLIGHT)
		_draw_centered_text(font, "TRIPLE THREAT ESCAPE", Vector2(cx, panel.position.y + 154.0), 22, C_WARNING)
		_draw_centered_text(font, "Three minds. One exit. No clean way out.", Vector2(cx, panel.position.y + 190.0), 16, C_DIM)

	_draw_mode_tags(panel, font)

	var btn_w := 320.0
	var btn_h := 56.0
	var btn_x := cx - btn_w * 0.5
	var play_y := panel.position.y + 328.0
	var quit_y := play_y + 72.0
	_btn_rects[BTN_PLAY] = Rect2(btn_x, play_y, btn_w, btn_h)
	_btn_rects[BTN_QUIT] = Rect2(btn_x, quit_y, btn_w, btn_h)
	_draw_menu_button(_btn_rects[BTN_PLAY], "PLAY", BTN_PLAY == _hover_btn, C_HIGHLIGHT, font)
	_draw_menu_button(_btn_rects[BTN_QUIT], "QUIT", BTN_QUIT == _hover_btn, Color(0.78, 0.28, 0.24), font)

	if font != null:
		_draw_centered_text(font, "Enter / Space to play    Esc to quit",
			Vector2(cx, panel.position.y + panel.size.y - 34.0), 13, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.82))

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
	draw_line(panel.position + Vector2(28.0, 224.0), panel.position + Vector2(panel.size.x - 28.0, 224.0),
		Color(1, 1, 1, 0.10), 1.0)

func _draw_mode_tags(panel: Rect2, font: Font) -> void:
	var labels: Array[String] = ["MINIMAX RED", "MCTS BLUE", "FUZZY POLICE"]
	var cols: Array[Color] = [C_RED_AG, Color(0.18, 1.00, 0.92), C_WARNING]
	var tag_w := 176.0
	var gap := 18.0
	var total := tag_w * 3.0 + gap * 2.0
	var x0 := panel.position.x + panel.size.x * 0.5 - total * 0.5
	var y := panel.position.y + 246.0
	for i in range(3):
		var r := Rect2(x0 + float(i) * (tag_w + gap), y, tag_w, 42.0)
		draw_rect(r, Color(cols[i].r * 0.16, cols[i].g * 0.16, cols[i].b * 0.16, 0.82))
		draw_rect(Rect2(r.position, Vector2(5.0, r.size.y)), cols[i])
		draw_rect(r, Color(cols[i].r, cols[i].g, cols[i].b, 0.36), false)
		if font != null:
			_draw_centered_text(font, labels[i], Vector2(r.get_center().x, r.position.y + 27.0), 12, cols[i])

func _draw_menu_button(rect: Rect2, label: String, hovered: bool, accent: Color, font: Font) -> void:
	var r := rect
	if hovered:
		r = Rect2(r.position - Vector2(4.0, 4.0), r.size + Vector2(8.0, 8.0))
	draw_rect(Rect2(r.position + Vector2(4.0, 5.0), r.size), Color(0, 0, 0, 0.38))
	draw_rect(r, Color(accent.r * 0.15, accent.g * 0.15, accent.b * 0.15, 0.90 if hovered else 0.68))
	draw_rect(Rect2(r.position, Vector2(6.0, r.size.y)), accent)
	draw_rect(r, Color(accent.r, accent.g, accent.b, 0.90 if hovered else 0.48), false, 2.0)
	if font != null:
		_draw_centered_text(font, label, Vector2(r.get_center().x, r.position.y + r.size.y * 0.64),
			20, Color(accent.r * 1.15, accent.g * 1.15, accent.b * 1.15).clamp())

func _draw_centered_text(font: Font, text: String, pos: Vector2, size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(pos.x - width * 0.5, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

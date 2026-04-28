extends Node2D
class_name PauseOverlay

signal resume_requested()
signal title_requested()

const BTN_RESUME: int = 0
const BTN_SOUND: int = 1
const BTN_MUSIC: int = 2
const BTN_SHAKE: int = 3
const BTN_TRAILS: int = 4
const BTN_TITLE: int = 5

var _btn_rects: Array[Rect2] = [Rect2(), Rect2(), Rect2(), Rect2(), Rect2(), Rect2()]
var _hover_btn: int = -1
var _mouse_pos: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _panel_rect: Rect2 = Rect2()

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func show_menu() -> void:
	visible = true
	_hover_btn = -1
	_mouse_pos = get_viewport().get_mouse_position()
	_refresh_layout()
	queue_redraw()

func hide_menu() -> void:
	visible = false

func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_mouse_pos = get_viewport().get_mouse_position()
	_refresh_layout()
	_hover_btn = _find_button_at(_mouse_pos)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
			emit_signal("resume_requested")
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_refresh_layout()
		match _find_button_at(event.position):
			BTN_RESUME:
				emit_signal("resume_requested")
			BTN_SOUND:
				UserSettings.toggle_sound_enabled()
			BTN_MUSIC:
				UserSettings.toggle_music_enabled()
			BTN_SHAKE:
				UserSettings.toggle_screen_shake_enabled()
			BTN_TRAILS:
				UserSettings.toggle_motion_trails_enabled()
			BTN_TITLE:
				emit_signal("title_requested")

func _draw() -> void:
	if not visible:
		return
	var vp: Rect2 = get_viewport_rect()
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return

	draw_rect(vp, Color(0.0, 0.0, 0.0, 0.55))
	var pulse: float = 0.5 + 0.5 * sin(_time * 2.0)
	_refresh_layout()
	var panel := _panel_rect
	draw_rect(panel, Color(0.03, 0.07, 0.12, 0.96))
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 6.0)), Color(0.0, 0.9, 1.0, 0.85))
	draw_rect(panel, Color(0.0, 0.9, 1.0, 0.32 + pulse * 0.10), false, 2.0)
	_draw_centered(font, "PAUSED", Vector2(panel.get_center().x, panel.position.y + 54.0), 36, Color(0.9, 0.98, 1.0))
	_draw_centered(font, "Simulation is halted. Visual settings can still be changed.", Vector2(panel.get_center().x, panel.position.y + 82.0), 12, Color(0.56, 0.66, 0.78))

	var labels: Array[String] = [
		"RESUME",
		"SFX: " + ("ON" if UserSettings.sound_enabled else "OFF"),
		"MUSIC: " + ("ON" if UserSettings.music_enabled else "OFF"),
		"SHAKE: " + ("ON" if UserSettings.screen_shake_enabled else "OFF"),
		"TRAILS: " + ("ON" if UserSettings.motion_trails_enabled else "OFF"),
		"MAIN MENU",
	]
	var accents: Array[Color] = [
		Color(0.0, 0.9, 0.45),
		Color(1.0, 0.84, 0.25),
		Color(1.0, 0.84, 0.25),
		Color(0.55, 0.76, 0.94),
		Color(0.55, 0.76, 0.94),
		Color(1.0, 0.34, 0.30),
	]

	for i in range(_btn_rects.size()):
		var r := _btn_rects[i]
		var hover: bool = i == _hover_btn
		var a: Color = accents[i]
		draw_rect(r, Color(a.r * 0.16, a.g * 0.16, a.b * 0.16, 0.90 if hover else 0.72))
		draw_rect(Rect2(r.position, Vector2(5.0, r.size.y)), a)
		draw_rect(r, Color(a.r, a.g, a.b, 0.82 if hover else 0.38), false)
		_draw_centered(font, labels[i], Vector2(r.get_center().x, r.position.y + 27.0), 15, a)

	_draw_centered(font, "Esc / P to resume", Vector2(panel.get_center().x, panel.end.y - 18.0), 12, Color(0.56, 0.66, 0.78))

func _draw_centered(font: Font, text: String, pos: Vector2, size: int, color: Color) -> void:
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(pos.x - width * 0.5, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _refresh_layout() -> void:
	var vp: Rect2 = get_viewport_rect()
	_panel_rect = Rect2(vp.size.x * 0.5 - 260.0, vp.size.y * 0.5 - 220.0, 520.0, 440.0)
	var y: float = _panel_rect.position.y + 110.0
	for i in range(_btn_rects.size()):
		_btn_rects[i] = Rect2(_panel_rect.position.x + 58.0, y, _panel_rect.size.x - 116.0, 42.0)
		y += 50.0

func _find_button_at(pos: Vector2) -> int:
	for i in range(_btn_rects.size()):
		if _btn_rects[i].has_point(pos):
			return i
	return -1

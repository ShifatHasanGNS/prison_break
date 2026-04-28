extends RefCounted
class_name CharacterPreview

const BASE_TILE: float = 48.0

static func draw_role(canvas: CanvasItem, rect: Rect2, role: String, time_sec: float, alpha: float = 1.0, facing_sign: float = 1.0) -> void:
	if canvas == null:
		return
	var side: float = minf(rect.size.x, rect.size.y)
	var scale: float = maxf(0.28, side / (BASE_TILE * 1.08))
	var center: Vector2 = rect.get_center() + Vector2(0.0, rect.size.y * 0.06)
	var bob: float = sin(time_sec * 3.6) * 1.1

	canvas.draw_set_transform(center, 0.0, Vector2(scale, scale))
	_draw_ellipse(canvas, Vector2(0.0, BASE_TILE * 0.31), Vector2(BASE_TILE * 0.32, BASE_TILE * 0.10), Color(0.0, 0.0, 0.0, 0.34 * alpha))
	_draw_ellipse(canvas, Vector2(0.0, BASE_TILE * 0.29), Vector2(BASE_TILE * 0.22, BASE_TILE * 0.05), Color(0.0, 0.0, 0.0, 0.12 * alpha))

	match role:
		"rusher_red":
			_draw_rusher(canvas, bob, time_sec, alpha, facing_sign)
		"sneaky_blue":
			_draw_sneaky(canvas, bob, time_sec, alpha, facing_sign)
		_:
			_draw_police(canvas, bob, time_sec, alpha, facing_sign)

	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func _draw_rusher(canvas: CanvasItem, bob: float, time_sec: float, alpha: float, facing_sign: float) -> void:
	var t: float = BASE_TILE
	var skin: Color = Color(0.67, 0.38, 0.22, alpha)
	var orange: Color = Color(0.90, 0.28, 0.10, alpha)
	var orange_dark: Color = Color(0.72, 0.18, 0.05, alpha)
	var outline: Color = Color(0.08, 0.05, 0.04, alpha)
	var boots: Color = Color(0.09, 0.08, 0.08, alpha)
	var eye_shift: float = t * 0.025 * facing_sign
	var sway: float = sin(time_sec * 5.0) * 1.2

	_draw_block(canvas, Rect2(-t * 0.21, t * 0.03 + bob, t * 0.17, t * 0.27), orange_dark, outline)
	_draw_block(canvas, Rect2(t * 0.04, t * 0.03 + bob, t * 0.17, t * 0.27), orange, outline)
	_draw_block(canvas, Rect2(-t * 0.23, t * 0.29 + bob, t * 0.20, t * 0.08), boots, outline)
	_draw_block(canvas, Rect2(t * 0.03, t * 0.29 + bob, t * 0.20, t * 0.08), boots, outline)

	_draw_block(canvas, Rect2(-t * 0.31, -t * 0.18 + bob, t * 0.62, t * 0.34), orange, outline)
	_draw_block(canvas, Rect2(-t * 0.16, -t * 0.12 + bob, t * 0.32, t * 0.10), Color(0.99, 0.80, 0.68, alpha), outline)
	canvas.draw_line(Vector2(0.0, -t * 0.16 + bob), Vector2(0.0, t * 0.14 + bob), Color(0.55, 0.12, 0.05, alpha), 2.0)
	var font: Font = ThemeDB.fallback_font
	if font != null:
		canvas.draw_string(font, Vector2(-t * 0.04, -t * 0.02 + bob), "47", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.88 * alpha))

	_draw_block(canvas, Rect2(-t * 0.39, -t * 0.15 + bob, t * 0.13, t * 0.22), orange_dark, outline)
	_draw_block(canvas, Rect2(t * 0.26, -t * 0.15 + bob, t * 0.13, t * 0.22), orange, outline)
	canvas.draw_rect(Rect2(-t * 0.40, t * 0.04 + bob + sway, t * 0.12, t * 0.07), skin)
	canvas.draw_rect(Rect2(t * 0.28, t * 0.04 + bob - sway, t * 0.12, t * 0.07), skin)

	canvas.draw_rect(Rect2(-t * 0.05, -t * 0.24 + bob, t * 0.10, t * 0.06), skin)
	_draw_ellipse(canvas, Vector2(0.0, -t * 0.33 + bob), Vector2(t * 0.19, t * 0.17), Color(0.16, 0.09, 0.05, alpha))
	_draw_ellipse(canvas, Vector2(0.0, -t * 0.30 + bob), Vector2(t * 0.17, t * 0.15), skin)
	canvas.draw_line(Vector2(-t * 0.12, -t * 0.36 + bob), Vector2(-t * 0.03, -t * 0.32 + bob), outline, 2.0)
	canvas.draw_line(Vector2(t * 0.12, -t * 0.36 + bob), Vector2(t * 0.03, -t * 0.32 + bob), outline, 2.0)
	canvas.draw_circle(Vector2(-t * 0.06 + eye_shift, -t * 0.31 + bob), 2.2, Color(1, 1, 1, alpha))
	canvas.draw_circle(Vector2(t * 0.06 + eye_shift, -t * 0.31 + bob), 2.2, Color(1, 1, 1, alpha))
	canvas.draw_circle(Vector2(-t * 0.06 + eye_shift * 1.5, -t * 0.31 + bob), 1.0, outline)
	canvas.draw_circle(Vector2(t * 0.06 + eye_shift * 1.5, -t * 0.31 + bob), 1.0, outline)

static func _draw_sneaky(canvas: CanvasItem, bob: float, time_sec: float, alpha: float, facing_sign: float) -> void:
	var t: float = BASE_TILE
	var skin: Color = Color(0.76, 0.55, 0.34, alpha)
	var blue: Color = Color(0.14, 0.56, 0.86, alpha)
	var blue_dark: Color = Color(0.07, 0.32, 0.66, alpha)
	var outline: Color = Color(0.05, 0.07, 0.10, alpha)
	var shoes: Color = Color(0.08, 0.10, 0.12, alpha)
	var eye_shift: float = t * 0.022 * facing_sign
	var sway: float = sin(time_sec * 4.4 + 0.9) * 1.0

	_draw_block(canvas, Rect2(-t * 0.20, t * 0.03 + bob, t * 0.16, t * 0.27), blue_dark, outline)
	_draw_block(canvas, Rect2(t * 0.04, t * 0.03 + bob, t * 0.16, t * 0.27), blue, outline)
	_draw_block(canvas, Rect2(-t * 0.22, t * 0.29 + bob, t * 0.19, t * 0.08), shoes, outline)
	_draw_block(canvas, Rect2(t * 0.03, t * 0.29 + bob, t * 0.19, t * 0.08), shoes, outline)

	_draw_block(canvas, Rect2(-t * 0.28, -t * 0.17 + bob, t * 0.56, t * 0.33), blue, outline)
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(-t * 0.06, -t * 0.17 + bob),
		Vector2(t * 0.06, -t * 0.17 + bob),
		Vector2(t * 0.02, -t * 0.05 + bob),
		Vector2(-t * 0.02, -t * 0.05 + bob),
	]), Color(0.96, 0.98, 1.00, alpha))
	_draw_block(canvas, Rect2(-t * 0.16, -t * 0.02 + bob, t * 0.14, t * 0.07), blue_dark, outline)

	_draw_block(canvas, Rect2(-t * 0.38, -t * 0.14 + bob + sway, t * 0.12, t * 0.20), blue_dark, outline)
	_draw_block(canvas, Rect2(t * 0.26, -t * 0.14 + bob - sway, t * 0.12, t * 0.20), blue, outline)
	canvas.draw_rect(Rect2(-t * 0.39, t * 0.02 + bob + sway, t * 0.11, t * 0.07), skin)
	canvas.draw_rect(Rect2(t * 0.28, t * 0.02 + bob - sway, t * 0.11, t * 0.07), skin)

	canvas.draw_rect(Rect2(-t * 0.05, -t * 0.24 + bob, t * 0.10, t * 0.06), skin)
	_draw_ellipse(canvas, Vector2(0.0, -t * 0.33 + bob), Vector2(t * 0.18, t * 0.16), Color(0.15, 0.08, 0.03, alpha))
	_draw_ellipse(canvas, Vector2(0.0, -t * 0.30 + bob), Vector2(t * 0.16, t * 0.14), skin)
	canvas.draw_circle(Vector2(-t * 0.05 + eye_shift, -t * 0.31 + bob), 2.0, Color(1, 1, 1, alpha))
	canvas.draw_circle(Vector2(t * 0.05 + eye_shift, -t * 0.31 + bob), 2.0, Color(1, 1, 1, alpha))
	canvas.draw_circle(Vector2(-t * 0.05 + eye_shift * 1.4, -t * 0.31 + bob), 0.9, outline)
	canvas.draw_circle(Vector2(t * 0.05 + eye_shift * 1.4, -t * 0.31 + bob), 0.9, outline)

static func _draw_police(canvas: CanvasItem, bob: float, time_sec: float, alpha: float, facing_sign: float) -> void:
	var t: float = BASE_TILE
	var skin: Color = Color(0.78, 0.52, 0.30, alpha)
	var navy: Color = Color(0.12, 0.19, 0.42, alpha)
	var navy_dark: Color = Color(0.07, 0.12, 0.24, alpha)
	var vest: Color = Color(0.05, 0.08, 0.17, alpha)
	var outline: Color = Color(0.05, 0.05, 0.08, alpha)
	var boots: Color = Color(0.06, 0.06, 0.08, alpha)
	var eye_shift: float = t * 0.020 * facing_sign
	var sway: float = sin(time_sec * 4.4 + 2.0) * 1.0

	_draw_block(canvas, Rect2(-t * 0.19, t * 0.04 + bob, t * 0.15, t * 0.26), navy_dark, outline)
	_draw_block(canvas, Rect2(t * 0.04, t * 0.04 + bob, t * 0.15, t * 0.26), navy, outline)
	_draw_block(canvas, Rect2(-t * 0.21, t * 0.29 + bob, t * 0.18, t * 0.08), boots, outline)
	_draw_block(canvas, Rect2(t * 0.03, t * 0.29 + bob, t * 0.18, t * 0.08), boots, outline)

	_draw_block(canvas, Rect2(-t * 0.27, -t * 0.17 + bob, t * 0.54, t * 0.34), navy, outline)
	_draw_block(canvas, Rect2(-t * 0.22, -t * 0.13 + bob, t * 0.44, t * 0.24), vest, outline)
	canvas.draw_rect(Rect2(-t * 0.20, -t * 0.01 + bob, t * 0.40, t * 0.05), Color(0.03, 0.05, 0.08, alpha))
	canvas.draw_circle(Vector2(-t * 0.10, -t * 0.09 + bob), 2.0, Color(1.00, 0.84, 0.24, alpha))
	canvas.draw_rect(Rect2(-t * 0.13, -t * 0.04 + bob, t * 0.10, t * 0.06), Color(0.04, 0.07, 0.11, alpha))
	canvas.draw_rect(Rect2(t * 0.03, -t * 0.04 + bob, t * 0.10, t * 0.06), Color(0.04, 0.07, 0.11, alpha))

	_draw_block(canvas, Rect2(-t * 0.37, -t * 0.14 + bob + sway, t * 0.12, t * 0.22), navy_dark, outline)
	_draw_block(canvas, Rect2(t * 0.25, -t * 0.14 + bob - sway, t * 0.12, t * 0.22), navy, outline)
	canvas.draw_rect(Rect2(-t * 0.38, t * 0.04 + bob + sway, t * 0.11, t * 0.07), skin)
	canvas.draw_rect(Rect2(t * 0.27, t * 0.04 + bob - sway, t * 0.11, t * 0.07), skin)

	canvas.draw_rect(Rect2(-t * 0.05, -t * 0.24 + bob, t * 0.10, t * 0.06), skin)
	_draw_ellipse(canvas, Vector2(0.0, -t * 0.33 + bob), Vector2(t * 0.18, t * 0.16), Color(0.10, 0.05, 0.02, alpha))
	_draw_ellipse(canvas, Vector2(0.0, -t * 0.30 + bob), Vector2(t * 0.16, t * 0.14), skin)
	_draw_block(canvas, Rect2(-t * 0.19, -t * 0.42 + bob, t * 0.38, t * 0.07), Color(0.07, 0.10, 0.18, alpha), outline)
	canvas.draw_circle(Vector2(-t * 0.05 + eye_shift, -t * 0.31 + bob), 2.0, Color(1, 1, 1, alpha))
	canvas.draw_circle(Vector2(t * 0.05 + eye_shift, -t * 0.31 + bob), 2.0, Color(1, 1, 1, alpha))
	canvas.draw_circle(Vector2(-t * 0.05 + eye_shift * 1.4, -t * 0.31 + bob), 0.9, outline)
	canvas.draw_circle(Vector2(t * 0.05 + eye_shift * 1.4, -t * 0.31 + bob), 0.9, outline)

static func _draw_block(canvas: CanvasItem, rect: Rect2, fill: Color, outline: Color) -> void:
	canvas.draw_rect(rect, outline)
	var inner: Rect2 = rect.grow(-2.0)
	if inner.size.x > 0.0 and inner.size.y > 0.0:
		canvas.draw_rect(inner, fill)

static func _draw_ellipse(canvas: CanvasItem, center: Vector2, radii: Vector2, color: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(20):
		var a: float = TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	canvas.draw_colored_polygon(pts, color)

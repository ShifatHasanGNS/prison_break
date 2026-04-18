extends Node2D
class_name TransientEffect

## Short-lived visual effect spawned as a child of the Game scene root.
## Each effect animates via a single Tween, then calls queue_free().

enum Type { ALERT, SMOKE, SPARKLE, FLAME, CAPTURE, ESCAPE }

var _type    : int   = Type.ALERT
var _progress: float = 0.0   # 0 → 1 over the effect's lifetime
var _alpha   : float = 1.0   # 1 → 0 (fade out)

# -------------------------------------------------------------------------

## Activate this effect at a world-space position. Must be called after
## add_child() so that create_tween() works.
func activate(type: int, world_pos: Vector2) -> void:
	_type    = type
	position = world_pos

	var duration: float = _get_duration(type)
	var tween := create_tween()
	tween.tween_property(self, "_progress", 1.0, duration)
	tween.parallel().tween_property(self, "_alpha", 0.0, duration)
	tween.tween_callback(queue_free)

func _get_duration(type: int) -> float:
	match type:
		Type.ALERT:   return 0.6
		Type.SMOKE:   return 0.9
		Type.SPARKLE: return 0.5
		Type.FLAME:   return 0.7
		Type.CAPTURE: return 0.8
		Type.ESCAPE:  return 0.8
	return 0.6

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	match _type:
		Type.ALERT:   _draw_alert()
		Type.SMOKE:   _draw_smoke()
		Type.SPARKLE: _draw_sparkle()
		Type.FLAME:   _draw_flame()
		Type.CAPTURE: _draw_capture()
		Type.ESCAPE:  _draw_escape()

# -------------------------------------------------------------------------
# Per-type draw implementations
# -------------------------------------------------------------------------

func _draw_alert() -> void:
	# Orange ! glyph rising upward + expanding ring
	var col  := Color(1.00, 0.50, 0.10, _alpha)
	var font := ThemeDB.fallback_font
	var rise := _progress * 10.0
	if font != null:
		draw_string(font, Vector2(-5.0, -14.0 - rise), "!",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
	var ring_r := 6.0 + _progress * 22.0
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 24, col, 2)

func _draw_smoke() -> void:
	# Three grey circles drifting upward and fading
	var offsets := [Vector2(-8.0, 0.0), Vector2(0.0, -5.0), Vector2(8.0, 2.0)]
	for i in range(3):
		var drift := Vector2(0.0, -_progress * 20.0 - float(i) * 4.0)
		var r     := 5.0 + float(i) * 2.0
		var col   := Color(0.60, 0.60, 0.65, _alpha * (1.0 - float(i) * 0.25))
		draw_circle(offsets[i] + drift, r, col)

func _draw_sparkle() -> void:
	# Four yellow lines radiating outward, shrinking and fading
	var length := 14.0 * (1.0 - _progress)
	var col    := Color(1.00, 0.90, 0.15, _alpha)
	var dirs   := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
	for d in dirs:
		draw_line(d * 4.0, d * (4.0 + length), col, 2)

func _draw_flame() -> void:
	# Orange triangle drifting upward and fading
	var drift := Vector2(0.0, -_progress * 18.0)
	var col   := Color(0.95, 0.45, 0.05, _alpha)
	var pts   := PackedVector2Array([
		Vector2(0.0, -10.0) + drift,
		Vector2(-6.0,  3.0) + drift,
		Vector2( 6.0,  3.0) + drift,
	])
	draw_colored_polygon(pts, col)
	# Bright inner tip
	var pts2 := PackedVector2Array([
		Vector2(0.0, -7.0) + drift,
		Vector2(-3.0, 1.0) + drift,
		Vector2( 3.0, 1.0) + drift,
	])
	draw_colored_polygon(pts2, Color(1.00, 0.82, 0.15, _alpha))

func _draw_capture() -> void:
	# Red X scaling up and fading
	var size := 8.0 + _progress * 8.0
	var col  := Color(0.94, 0.27, 0.27, _alpha)
	draw_line(Vector2(-size, -size), Vector2(size,  size), col, 3)
	draw_line(Vector2( size, -size), Vector2(-size, size), col, 3)

func _draw_escape() -> void:
	# Green star burst — 8 lines expanding outward
	var size := 6.0 + _progress * 14.0
	var col  := Color(0.29, 0.85, 0.50, _alpha)
	for i in range(8):
		var a := float(i) / 8.0 * TAU
		var d := Vector2(cos(a), sin(a))
		draw_line(d * 4.0, d * size, col, 2)

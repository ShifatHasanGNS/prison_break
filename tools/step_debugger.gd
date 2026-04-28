extends Node2D
class_name StepDebugger

## Bottom-left bar: shows current tick + pause state. F5 = pause/resume, F6 = step.
## Placed in world scene (not CanvasLayer). Draws at a fixed screen position by
## converting screen coordinates to world/canvas space via draw_set_transform_matrix.

const BAR_H   : float = 44.0
const HUD_W   : float = 360.0

const C_BG     := Color(0.04, 0.06, 0.10, 0.93)
const C_BORDER := Color(0.0,  0.70, 1.0,  0.35)
const C_TEXT   := Color(0.80, 0.85, 0.90, 1.0)
const C_PAUSED := Color(0.98, 0.75, 0.14, 1.0)
const C_RUN    := Color(0.29, 0.85, 0.50, 1.0)

var _clock        : TickClock = null
var _bench_runner             = null   # BenchmarkRunner
var _tick_n       : int       = 0

# -------------------------------------------------------------------------

func setup(clock: TickClock, bench_runner = null) -> void:
	_clock        = clock
	_bench_runner = bench_runner
	EventBus.tick_ended.connect(_on_tick_ended)

func _on_tick_ended(n: int) -> void:
	_tick_n = n
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

# =========================================================================
# DRAWING
# =========================================================================

func _draw() -> void:
	var vp    := get_viewport_rect()
	var ct    := get_canvas_transform()
	# Apply inverse canvas transform so subsequent draw calls use screen coords
	draw_set_transform_matrix(ct.affine_inverse())

	var bar_w := vp.size.x - HUD_W
	var bar_y := vp.size.y - BAR_H

	# Background
	draw_rect(Rect2(0.0, bar_y, bar_w, BAR_H), C_BG)
	# Top border line
	draw_line(Vector2(0.0, bar_y), Vector2(bar_w, bar_y), C_BORDER, 1.0)
	draw_rect(Rect2(0.0, bar_y, bar_w, BAR_H), C_BORDER, false)

	var font := ThemeDB.fallback_font
	if font == null:
		draw_set_transform_matrix(Transform2D.IDENTITY)
		return

	var ty := bar_y + 28.0

	# Tick counter
	draw_string(font, Vector2(12.0, ty),
		"Tick: %d" % _tick_n,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_TEXT)

	# Pause / running state
	var is_paused := _clock != null and _clock.is_paused()
	var state_str := "[ PAUSED ]" if is_paused else "[ RUNNING ]"
	var state_col := C_PAUSED    if is_paused else C_RUN
	draw_string(font, Vector2(110.0, ty), state_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, state_col)

	# Bench state indicator
	if _bench_runner != null and _bench_runner.is_running:
		draw_string(font, Vector2(250.0, ty), "[ BENCHMARKING... ]",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.98, 0.75, 0.14, 1.0))

	# Hint text
	draw_string(font, Vector2(bar_w - 380.0, ty),
		"F5: pause/resume    F6: step    F8: benchmark (50 runs)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.58, 0.70, 0.70))

	draw_set_transform_matrix(Transform2D.IDENTITY)

# =========================================================================
# KEY INPUT
# =========================================================================

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if _clock == null:
		return
	match event.keycode:
		KEY_F5:
			if _clock.is_paused():
				_clock.resume()
			else:
				_clock.pause()
			queue_redraw()
		KEY_F6:
			if _clock.is_paused():
				_clock.step_once()
		KEY_F8:
			if _bench_runner != null and not _bench_runner.is_running:
				_clock.pause()
				_bench_runner.run_benchmark(BenchmarkRunner.DEFAULT_RUNS)

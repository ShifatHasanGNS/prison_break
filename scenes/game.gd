extends Node2D

const TILE_SIZE: int = 48
const GRID_SIZE: int = 20
const LEFT_PANEL_W: float = 292.0
const RIGHT_PANEL_W: float = 292.0
const HEADER_H: float = 72.0
const MAP_TOOLBAR_H: float = 46.0
const MAP_PX: float = float(GRID_SIZE * TILE_SIZE)
const PADDING: float = 52.0
const DECISION_OVERLAY_SCRIPT = preload("res://ui/decision_overlay.gd")
const PAUSE_OVERLAY_SCRIPT = preload("res://ui/pause_overlay.gd")

var _camera: Camera2D = null
var _grid_renderer: GridRenderer = null
var _path_overlay: PathOverlay = null
var _vision_overlay: VisionOverlay = null
var _danger_overlay: DangerHeatmapOverlay = null
var _decision_overlay: Node2D = null
var _overlay_mgr: OverlayManager = null
var _hud_root: HudRoot = null
var _step_debugger: StepDebugger = null
var _clock: TickClock = null
var _sim: SimulationLoop = null
var _replay_exporter = null
var _bench_runner = null
var _pause_overlay: PauseOverlay = null
var _camera_base_pos: Vector2 = Vector2.ZERO
var _shake_time: float = 0.0
var _shake_amp: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	var seed_value: int = SimRandom.reseed_from_time()
	print("Game: random seed %d" % seed_value)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = int(seed_value)

	_camera = Camera2D.new()
	_camera.name = "MainCamera"
	_camera.enabled = true
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 7.5
	_camera.zoom = Vector2.ONE
	add_child(_camera)
	get_viewport().size_changed.connect(_update_camera)

	var mg := MapGenerator.new()
	add_child(mg)
	var result: Dictionary = mg.generate()
	if not result.get("valid", false):
		push_error("Game: map generation failed")
		return

	var grid := GridEngine.new()
	add_child(grid)
	grid.load_generated(result["tiles"])

	_grid_renderer = GridRenderer.new()
	_grid_renderer.name = "GridRenderer"
	add_child(_grid_renderer)

	_sim = SimulationLoop.new()
	_sim.name = "SimulationLoop"
	_sim.setup(grid, result)
	add_child(_sim)

	_replay_exporter = ReplayExporter.new()
	_replay_exporter.start_recording(result, SimRandom.get_seed())
	_sim.replay_exporter = _replay_exporter

	_grid_renderer.setup(grid, _sim._exit_rotator, _sim._doors)

	_decision_overlay = DECISION_OVERLAY_SCRIPT.new()
	_decision_overlay.name = "DecisionOverlay"
	_decision_overlay.z_index = 1
	add_child(_decision_overlay)
	_decision_overlay.setup(_sim._agents, grid)

	_path_overlay = PathOverlay.new()
	_path_overlay.name = "PathOverlay"
	add_child(_path_overlay)
	_path_overlay.setup(_sim._agents, grid, _sim._exit_rotator)

	_vision_overlay = VisionOverlay.new()
	_vision_overlay.name = "VisionOverlay"
	add_child(_vision_overlay)
	_vision_overlay.setup(_sim._agents, grid)

	_danger_overlay = DangerHeatmapOverlay.new()
	_danger_overlay.name = "DangerHeatmapOverlay"
	add_child(_danger_overlay)
	_danger_overlay.setup(_sim._danger_map)

	_overlay_mgr = OverlayManager.new()
	_overlay_mgr.name = "OverlayManager"
	add_child(_overlay_mgr)
	_overlay_mgr.setup(_path_overlay, _vision_overlay, _danger_overlay)

	_update_camera()

	_clock = TickClock.new()
	_clock.ticks_per_second = 4.0
	add_child(_clock)
	_clock.tick_fired.connect(_sim.on_tick)

	var hud_layer := CanvasLayer.new()
	hud_layer.name = "HudLayer"
	hud_layer.layer = 5
	add_child(hud_layer)

	_hud_root = HudRoot.new()
	_hud_root.name = "HudRoot"
	hud_layer.add_child(_hud_root)
	_hud_root.setup(_sim._agents, _sim._exit_rotator, _sim, _sim.get_camera_system())

	var pause_layer := CanvasLayer.new()
	pause_layer.name = "PauseLayer"
	pause_layer.layer = 20
	add_child(pause_layer)
	_pause_overlay = PAUSE_OVERLAY_SCRIPT.new()
	pause_layer.add_child(_pause_overlay)
	_pause_overlay.resume_requested.connect(_on_pause_resume_requested)
	_pause_overlay.title_requested.connect(_on_pause_title_requested)

	_bench_runner = BenchmarkRunner.new()
	_bench_runner.name = "BenchmarkRunner"
	add_child(_bench_runner)

	_step_debugger = StepDebugger.new()
	_step_debugger.name = "StepDebugger"
	add_child(_step_debugger)
	_step_debugger.setup(_clock, _bench_runner)

	EventBus.simulation_ended.connect(_on_simulation_ended)
	EventBus.agent_captured.connect(func(_id): _trigger_shake(0.16, 10.0))
	EventBus.agent_escaped.connect(func(_id): _trigger_shake(0.22, 14.0))
	EventBus.agent_entered_fire.connect(func(_id, _tile): _trigger_shake(0.12, 8.0))
	EventBus.door_state_changed.connect(func(_tile, state):
		if state == "broken":
			_trigger_shake(0.14, 9.0)
	)

func _process(delta: float) -> void:
	if _camera == null:
		return
	if UserSettings != null and UserSettings.screen_shake_enabled and _shake_time > 0.0:
		_shake_time -= delta
		var f: float = clampf(_shake_time / 0.25, 0.0, 1.0)
		var amp: float = _shake_amp * f
		var offset := Vector2(_rng.randf_range(-amp, amp), _rng.randf_range(-amp, amp))
		_camera.position = _camera_base_pos + offset
	else:
		_shake_time = 0.0
		_camera.position = _camera_base_pos

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
		_toggle_pause_menu()

func _update_camera() -> void:
	if _camera == null:
		return
	var vp_size := get_viewport().get_visible_rect().size
	var avail_w := maxf(320.0, vp_size.x - LEFT_PANEL_W - RIGHT_PANEL_W)
	var avail_h := maxf(320.0, vp_size.y - HEADER_H - MAP_TOOLBAR_H)
	var zoom_val := minf((avail_w - PADDING) / MAP_PX, (avail_h - PADDING) / MAP_PX)
	_camera.zoom = Vector2(zoom_val, zoom_val)

	var screen_center := vp_size * 0.5
	var target_center := Vector2(LEFT_PANEL_W + avail_w * 0.5, HEADER_H + MAP_TOOLBAR_H + avail_h * 0.5)
	var world_center := Vector2(MAP_PX * 0.5, MAP_PX * 0.5)
	_camera_base_pos = world_center + (screen_center - target_center) / zoom_val
	if _shake_time <= 0.0:
		_camera.position = _camera_base_pos

func _on_simulation_ended(result: Dictionary) -> void:
	if _bench_runner != null and _bench_runner.is_running:
		return
	if _pause_overlay != null:
		_pause_overlay.hide_menu()
	get_tree().paused = false
	if _clock != null:
		_clock.pause()
	if _replay_exporter != null:
		_replay_exporter.export_to_file("user://replay_latest.json")
	ResultsScreen.pending_result = result
	var t := get_tree().create_timer(1.8)
	t.timeout.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/results_screen.tscn")
	)

func _toggle_pause_menu() -> void:
	if _pause_overlay == null:
		return
	if _pause_overlay.visible:
		_on_pause_resume_requested()
		return
	if _clock != null:
		_clock.pause()
	get_tree().paused = true
	_pause_overlay.show_menu()

func _on_pause_resume_requested() -> void:
	if _pause_overlay != null:
		_pause_overlay.hide_menu()
	get_tree().paused = false
	if _clock != null:
		_clock.resume()

func _on_pause_title_requested() -> void:
	if _pause_overlay != null:
		_pause_overlay.hide_menu()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")

func _trigger_shake(duration: float, amplitude: float) -> void:
	if UserSettings != null and not UserSettings.screen_shake_enabled:
		return
	_shake_time = maxf(_shake_time, duration)
	_shake_amp = maxf(_shake_amp, amplitude)

extends Node2D

## Full game scene. Launched from TitleScreen, transitions to ResultsScreen on end.

const TILE_SIZE : int   = 48
const GRID_SIZE : int   = 20
const HUD_WIDTH : float = 360.0
const MAP_PX    : float = float(GRID_SIZE * TILE_SIZE)   # 960.0
const PADDING   : float = 64.0
const DECISION_OVERLAY_SCRIPT = preload("res://ui/decision_overlay.gd")

var _camera          : Camera2D             = null
var _grid_renderer   : GridRenderer         = null
var _path_overlay    : PathOverlay          = null
var _vision_overlay  : VisionOverlay        = null
var _danger_overlay  : DangerHeatmapOverlay = null
var _decision_overlay: Node2D               = null
var _overlay_mgr     : OverlayManager       = null
var _hud_root        : HudRoot              = null
var _step_debugger   : StepDebugger         = null
var _clock           : TickClock            = null
var _sim             : SimulationLoop       = null
var _replay_exporter = null   # ReplayExporter
var _bench_runner    = null   # BenchmarkRunner

# -------------------------------------------------------------------------

func _ready() -> void:
	var seed_value: int = SimRandom.reseed_from_time()
	print("Game: random seed %d" % seed_value)

	# ?? Camera ??????????????????????????????????????????????????????????
	_camera = Camera2D.new()
	_camera.name = "MainCamera"
	add_child(_camera)
	get_viewport().size_changed.connect(_update_camera)

	# ?? Map ?????????????????????????????????????????????????????????????
	var mg := MapGenerator.new()
	add_child(mg)
	var result: Dictionary = mg.generate()
	if not result.get("valid", false):
		push_error("Game: map generation failed")
		return

	var grid := GridEngine.new()
	add_child(grid)
	grid.load_generated(result["tiles"])

	# ?? GridRenderer (before sim -- drawn behind agents) ??????????????????
	_grid_renderer = GridRenderer.new()
	_grid_renderer.name = "GridRenderer"
	add_child(_grid_renderer)

	# ?? SimulationLoop ??????????????????????????????????????????????????
	_sim = SimulationLoop.new()
	_sim.name = "SimulationLoop"
	_sim.setup(grid, result)
	add_child(_sim)

	# -- Replay exporter (records every tick to user://replay_latest.json) --
	_replay_exporter = ReplayExporter.new()
	_replay_exporter.start_recording(result, SimRandom.get_seed())
	_sim.replay_exporter = _replay_exporter

	_grid_renderer.setup(grid, _sim._exit_rotator, _sim._doors)

	# ?? Overlays (world-space, drawn after sim) ??????????????????????????
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

	# ?? Camera zoom / position ???????????????????????????????????????????
	_update_camera()

	# ?? TickClock ????????????????????????????????????????????????????????
	_clock = TickClock.new()
	_clock.ticks_per_second = 4.0
	add_child(_clock)
	_clock.tick_fired.connect(_sim.on_tick)

	# ?? HUD ??????????????????????????????????????????????????????????????
	var hud_layer := CanvasLayer.new()
	hud_layer.name  = "HudLayer"
	hud_layer.layer = 5
	add_child(hud_layer)

	_hud_root = HudRoot.new()
	_hud_root.name = "HudRoot"
	hud_layer.add_child(_hud_root)
	_hud_root.setup(_sim._agents, _sim._exit_rotator)

	# -- BenchmarkRunner (F8 to trigger 50-run headless benchmark) --
	_bench_runner = BenchmarkRunner.new()
	_bench_runner.name = "BenchmarkRunner"
	add_child(_bench_runner)

	_step_debugger = StepDebugger.new()
	_step_debugger.name = "StepDebugger"
	add_child(_step_debugger)
	_step_debugger.setup(_clock, _bench_runner)

	# -- Win/lose --
	EventBus.simulation_ended.connect(_on_simulation_ended)

# -------------------------------------------------------------------------

func _update_camera() -> void:
	if _camera == null:
		return
	var vp_size   := get_viewport().get_visible_rect().size
	var avail_w   := vp_size.x - HUD_WIDTH
	var avail_h   := vp_size.y
	var zoom_val  := minf((avail_w - PADDING) / MAP_PX, (avail_h - PADDING) / MAP_PX)
	_camera.zoom  = Vector2(zoom_val, zoom_val)
	var screen_cx := vp_size.x / 2.0
	var area_cx   := avail_w   / 2.0
	var cam_x     := MAP_PX / 2.0 + (screen_cx - area_cx) / zoom_val
	_camera.position = Vector2(cam_x, MAP_PX / 2.0)

# -------------------------------------------------------------------------

func _on_simulation_ended(result: Dictionary) -> void:
	# Ignore if this came from a headless benchmark sub-simulation
	if _bench_runner != null and _bench_runner.is_running:
		return

	# Stop the clock so the simulation freezes on the final frame
	if _clock != null:
		_clock.pause()

	# Save replay to disk
	if _replay_exporter != null:
		_replay_exporter.export_to_file("user://replay_latest.json")

	# Store result for ResultsScreen, then transition after a brief pause
	# so the player can see the final state (escape flash / capture X)
	ResultsScreen.pending_result = result

	var t := get_tree().create_timer(1.8)
	t.timeout.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/results_screen.tscn")
	)

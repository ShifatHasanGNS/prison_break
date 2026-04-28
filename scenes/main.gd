extends Node2D

const TILE_SIZE : int   = 48
const GRID_SIZE : int   = 20
const HUD_WIDTH : float = 360.0
const MAP_PX    : float = float(GRID_SIZE * TILE_SIZE)   # 960.0
const PADDING   : float = 64.0                            # 32 px each side
const DECISION_OVERLAY_SCRIPT = preload("res://ui/decision_overlay.gd")

var _camera          : Camera2D             = null
var _grid_renderer   : GridRenderer         = null
var _path_overlay    : PathOverlay          = null
var _vision_overlay  : VisionOverlay        = null
var _danger_overlay  : DangerHeatmapOverlay = null
var _decision_overlay: Node2D               = null
var _overlay_manager : OverlayManager       = null
var _hud_root        : HudRoot              = null
var _step_debugger   : StepDebugger         = null

# -------------------------------------------------------------------------

func _ready() -> void:
	# Camera2D — must exist before any child that triggers queue_redraw
	_camera = Camera2D.new()
	_camera.name = "MainCamera"
	add_child(_camera)

	# Recompute zoom + position on every window resize
	get_viewport().size_changed.connect(_update_camera)

	# ----------------------------------------------------------------
	# Phase 2 — map + A* validation
	# ----------------------------------------------------------------
	print("=== Phase 2 Test ===")
	print("Main test: random seed %d" % SimRandom.reseed_from_time())

	var mg := MapGenerator.new()
	add_child(mg)
	var result: Dictionary = mg.generate()

	if not result.get("valid", false):
		push_error("Phase 2 FAIL: map generation returned invalid result")
		return

	var grid := GridEngine.new()
	add_child(grid)
	grid.load_generated(result["tiles"])

	var walkable_count: int = 0
	for pos: Vector2i in result["tiles"]:
		if grid.is_walkable(pos):
			walkable_count += 1
	print("Walkable tiles: %d" % walkable_count)

	var red_spawn : Vector2i = result["red_spawn"]
	var exits     : Array    = result["exits"]
	var path      : Array[Vector2i] = grid.astar(red_spawn, exits[0])

	if path.size() > 0:
		print("A* path Red→Exit[0]: %d steps" % path.size())
	else:
		push_error("Phase 2 FAIL: no A* path found")
		return
	print("=== Phase 2 PASS ===")

	# ----------------------------------------------------------------
	# GridRenderer — add BEFORE SimulationLoop so it's drawn behind agents
	# ----------------------------------------------------------------
	_grid_renderer = GridRenderer.new()
	_grid_renderer.name = "GridRenderer"
	add_child(_grid_renderer)

	# ----------------------------------------------------------------
	# Phase 3 — SimulationLoop + TickClock
	# ----------------------------------------------------------------
	print("=== Phase 3 Test — ticking at 4 Hz (watch console) ===")

	var sim := SimulationLoop.new()
	sim.setup(grid, result)
	add_child(sim)

	# Wire GridRenderer now that sim._exit_rotator and sim._doors exist
	_grid_renderer.setup(grid, sim._exit_rotator, sim._doors)

	# ----------------------------------------------------------------
	# Phase 12 — Overlays (world-space Node2D children, NOT CanvasLayer)
	# Added AFTER sim so they draw on top of agents.
	# ----------------------------------------------------------------
	_decision_overlay = DECISION_OVERLAY_SCRIPT.new()
	_decision_overlay.name = "DecisionOverlay"
	_decision_overlay.z_index = 1
	add_child(_decision_overlay)
	_decision_overlay.setup(sim._agents, grid)

	_path_overlay = PathOverlay.new()
	_path_overlay.name = "PathOverlay"
	add_child(_path_overlay)
	_path_overlay.setup(sim._agents, grid, sim._exit_rotator)

	_vision_overlay = VisionOverlay.new()
	_vision_overlay.name = "VisionOverlay"
	add_child(_vision_overlay)
	_vision_overlay.setup(sim._agents, grid)

	_danger_overlay = DangerHeatmapOverlay.new()
	_danger_overlay.name = "DangerHeatmapOverlay"
	add_child(_danger_overlay)
	_danger_overlay.setup(sim._danger_map)

	_overlay_manager = OverlayManager.new()
	_overlay_manager.name = "OverlayManager"
	add_child(_overlay_manager)
	_overlay_manager.setup(_path_overlay, _vision_overlay, _danger_overlay)

	# ----------------------------------------------------------------
	# Camera — compute zoom/position for this viewport
	# ----------------------------------------------------------------
	_update_camera()

	# ----------------------------------------------------------------
	# TickClock
	# ----------------------------------------------------------------
	var clock := TickClock.new()
	clock.ticks_per_second = 4.0
	add_child(clock)
	clock.tick_fired.connect(sim.on_tick)
	clock.tick_fired.connect(_phase8_ability_test.bind(sim))

	# ----------------------------------------------------------------
	# Phase 13 — HUD (CanvasLayer + HudRoot Node2D)
	# HudRoot extends Node2D; it lives inside a CanvasLayer so all its
	# draw calls are in screen space. It must be set up AFTER the clock
	# exists so tick_ended signals flow into it.
	# ----------------------------------------------------------------
	var hud_layer := CanvasLayer.new()
	hud_layer.name  = "HudLayer"
	hud_layer.layer = 5
	add_child(hud_layer)

	_hud_root = HudRoot.new()
	_hud_root.name = "HudRoot"
	hud_layer.add_child(_hud_root)
	_hud_root.setup(sim._agents, sim._exit_rotator)

	# StepDebugger — world-space Node2D; draws at screen bottom via
	# draw_set_transform_matrix(canvas_transform.inverse()).
	_step_debugger = StepDebugger.new()
	_step_debugger.name = "StepDebugger"
	add_child(_step_debugger)
	_step_debugger.setup(clock)

# -------------------------------------------------------------------------
# Camera helpers
# -------------------------------------------------------------------------

## Zoom and position Camera2D so the 960×960 map fills the available
## left 1560 px area (right 360 px is reserved for the HUD).
## Called once at startup and again on every viewport resize.
func _update_camera() -> void:
	if _camera == null:
		return

	var vp_size  : Vector2 = get_viewport().get_visible_rect().size
	var avail_w  : float   = vp_size.x - HUD_WIDTH
	var avail_h  : float   = vp_size.y

	# Fit map with 32 px padding on each side
	var zoom_val : float = minf((avail_w - PADDING) / MAP_PX,
	                             (avail_h - PADDING) / MAP_PX)
	_camera.zoom = Vector2(zoom_val, zoom_val)

	# Place camera so map center appears at the centre of the available region.
	#   screen_cx  = centre of the full viewport (e.g. 960)
	#   area_cx    = centre of the available area (e.g. 780)
	#   The camera must sit (screen_cx - area_cx)/zoom world-units to the
	#   RIGHT of the map centre so the map centre renders at area_cx.
	var screen_cx : float = vp_size.x / 2.0
	var area_cx   : float = avail_w   / 2.0
	var cam_x     : float = MAP_PX / 2.0 + (screen_cx - area_cx) / zoom_val
	_camera.position = Vector2(cam_x, MAP_PX / 2.0)

# -------------------------------------------------------------------------
# Phase 8 — ability test (fires once at tick 2)
# -------------------------------------------------------------------------
func _phase8_ability_test(n: int, sim: SimulationLoop) -> void:
	if n != 2:
		return
	print("=== Phase 8 Ability Test (tick %d) ===" % n)
	var context: Dictionary = {
		"grid"       : sim._grid,
		"danger_map" : sim._danger_map,
		"all_agents" : sim._agents,
	}
	for agent: Agent in sim._agents:
		if agent._abilities.is_empty():
			continue
		var ability: Ability = agent._abilities[0]
		var before : float   = agent.stamina
		var ok     : bool    = ability.use(agent, context)
		if ok:
			print("  [%s] %s used: stamina %.0f→%.0f  cd=%d" % [
				agent._role, ability.ability_name, before, agent.stamina,
				ability.get_cooldown_remaining()
			])
			var blocked: bool = not ability.use(agent, context)
			print("  [%s] %s reuse blocked=%s (cd=%d)" % [
				agent._role, ability.ability_name, str(blocked),
				ability.get_cooldown_remaining()
			])
		else:
			print("  [%s] %s not available (stamina=%.0f, cd=%d)" % [
				agent._role, ability.ability_name, agent.stamina,
				ability.get_cooldown_remaining()
			])
	print("=== Phase 8 PASS ===")

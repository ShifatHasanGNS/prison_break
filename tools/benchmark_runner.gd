extends Node
class_name BenchmarkRunner

## Runs N headless simulations (no rendering) and writes results to:
##   user://benchmark_results.csv
##   user://benchmark_results.json
##
## Trigger: call run_benchmark() from a parent node.
## Each run uses a deterministic seed (1..n_runs) and drives ticks manually.
## Exits are advanced at 0.25 s/tick (matching 4 ticks/sec default clock rate).
##
## F8 in StepDebugger triggers run_benchmark() on the BenchmarkRunner child.

const DEFAULT_RUNS   : int   = 50
const BENCH_TICK_CAP : int   = 400   # per-run tick limit (shorter than game's 500)
const SECS_PER_TICK  : float = 0.25  # 1/4 of a second at 4 ticks/sec

var _results : Array = []   # Array of per-run metric Dictionaries

# Set to true while benchmark is running (used by StepDebugger for display)
var is_running : bool = false

# -------------------------------------------------------------------------

## Start a benchmark of `n_runs` headless simulations.
## Yields between runs so the UI stays responsive.
## On completion writes CSV + JSON and prints a summary.
func run_benchmark(n_runs: int = DEFAULT_RUNS) -> void:
	if is_running:
		push_warning("BenchmarkRunner: already running")
		return
	is_running = true
	_results.clear()
	print("=== BenchmarkRunner: starting %d runs ===" % n_runs)

	for i in range(n_runs):
		var seed_val := i + 1
		SimRandom.set_seed(seed_val)
		var t_start := Time.get_ticks_msec()
		var metrics := _run_single(i, seed_val)
		metrics["ms_elapsed"] = Time.get_ticks_msec() - t_start
		_results.append(metrics)
		EventBus.emit_signal("benchmark_run_completed", i, metrics)
		print("  Run %d/%d  seed=%d  outcome=%s  ticks=%d  ms=%d" % [
			i + 1, n_runs,
			seed_val,
			metrics.get("outcome", "?"),
			metrics.get("total_ticks", 0),
			metrics.get("ms_elapsed", 0),
		])
		# Yield between runs to keep the engine responsive
		await get_tree().process_frame

	_export_csv()
	_export_json()
	_print_summary()
	is_running = false

# -------------------------------------------------------------------------
# Single-run driver

func _run_single(run_idx: int, seed_val: int) -> Dictionary:
	# --- Build temporary scene sub-tree ---
	var run_root := Node2D.new()
	run_root.name = "BenchRun_%d" % run_idx
	add_child(run_root)

	# Map generation
	var mg := MapGenerator.new()
	run_root.add_child(mg)
	var map_result: Dictionary = mg.generate()
	if not map_result.get("valid", false):
		run_root.queue_free()
		return _fail_metrics(seed_val, "map_gen_failed")

	# Grid
	var grid := GridEngine.new()
	run_root.add_child(grid)
	grid.load_generated(map_result["tiles"])

	# Simulation (no replay exporter for benchmarks)
	var sim := SimulationLoop.new()
	sim.name = "BenchSim"
	sim.setup(grid, map_result)
	run_root.add_child(sim)

	# Capture simulation_ended result via an Array (reference type -- safe in closures)
	# bench_data[0] = done flag (bool), bench_data[1] = result dict
	var bench_data : Array = [false, {}]
	var _on_ended := func(r: Dictionary) -> void:
		bench_data[0] = true
		bench_data[1] = r
	EventBus.simulation_ended.connect(_on_ended, CONNECT_ONE_SHOT)

	# Drive ticks manually (bypasses TickClock -- no real-time dependency)
	var tick_n : int = 0
	while not bench_data[0] and tick_n < BENCH_TICK_CAP:
		tick_n += 1
		sim.on_tick(tick_n)
		# Advance exit rotation timer at equivalent real-time rate
		var er := sim.get_exit_rotator()
		if er != null:
			er.advance_time(SECS_PER_TICK)

	# Clean up -- frees all child nodes including sim and agents
	run_root.queue_free()

	# Disconnect if game ended by tick cap without emitting (defensive)
	if EventBus.simulation_ended.is_connected(_on_ended):
		EventBus.simulation_ended.disconnect(_on_ended)

	if bench_data[0]:
		var m : Dictionary = (bench_data[1] as Dictionary).duplicate()
		m["seed"] = seed_val
		return m
	else:
		# Tick cap reached without game over (shouldn't happen often)
		return {
			"seed"          : seed_val,
			"outcome"       : "tick_cap",
			"total_ticks"   : tick_n,
			"escaped_count" : 0,
			"captured_count": 0,
			"total_actions" : 0,
			"escape_tick"   : 0,
		}

func _fail_metrics(seed_val: int, reason: String) -> Dictionary:
	return {
		"seed"          : seed_val,
		"outcome"       : reason,
		"total_ticks"   : 0,
		"escaped_count" : 0,
		"captured_count": 0,
		"total_actions" : 0,
		"escape_tick"   : 0,
		"ms_elapsed"    : 0,
	}

# -------------------------------------------------------------------------
# Output

func _export_csv() -> void:
	var path := "user://benchmark_results.csv"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("BenchmarkRunner: cannot write %s" % path)
		return
	# Header row
	f.store_line("run_idx,seed,outcome,total_ticks,escaped_count,captured_count,total_actions,escape_tick,ms_elapsed")
	for i in range(_results.size()):
		var r : Dictionary = _results[i]
		f.store_line("%d,%d,%s,%d,%d,%d,%d,%d,%d" % [
			i,
			r.get("seed",           0),
			r.get("outcome",        "unknown"),
			r.get("total_ticks",    0),
			r.get("escaped_count",  0),
			r.get("captured_count", 0),
			r.get("total_actions",  0),
			r.get("escape_tick",    0),
			r.get("ms_elapsed",     0),
		])
	f.close()
	print("BenchmarkRunner: CSV written to %s" % path)

func _export_json() -> void:
	var path := "user://benchmark_results.json"
	var data := {
		"runs"     : _results,
		"n_runs"   : _results.size(),
		"summary"  : _build_summary(),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("BenchmarkRunner: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	print("BenchmarkRunner: JSON written to %s" % path)

func _build_summary() -> Dictionary:
	if _results.is_empty():
		return {}
	var n       : int   = _results.size()
	var wins    : int   = 0
	var losses  : int   = 0
	var timeouts: int   = 0
	var total_ms: int   = 0
	var total_ticks: int = 0
	for r in _results:
		match r.get("outcome", ""):
			"prisoners_win": wins    += 1
			"police_wins":   losses  += 1
			"timeout":       timeouts += 1
		total_ms    += r.get("ms_elapsed",  0)
		total_ticks += r.get("total_ticks", 0)
	return {
		"n_runs"          : n,
		"prisoners_win"   : wins,
		"police_wins"     : losses,
		"timeouts"        : timeouts,
		"prisoner_win_pct": snappedf(float(wins) / float(n) * 100.0, 0.1),
		"avg_ticks"       : snappedf(float(total_ticks) / float(n), 0.1),
		"avg_ms_per_run"  : snappedf(float(total_ms) / float(n), 0.1),
	}

func _print_summary() -> void:
	var s := _build_summary()
	print("=== BenchmarkRunner SUMMARY ===")
	print("  Runs          : %d" % s.get("n_runs", 0))
	print("  Prisoners win : %d (%.1f%%)" % [s.get("prisoners_win",0), s.get("prisoner_win_pct",0.0)])
	print("  Police win    : %d" % s.get("police_wins",  0))
	print("  Timeouts      : %d" % s.get("timeouts",     0))
	print("  Avg ticks/run : %.1f" % s.get("avg_ticks",       0.0))
	print("  Avg ms/run    : %.1f" % s.get("avg_ms_per_run",  0.0))
	print("================================")

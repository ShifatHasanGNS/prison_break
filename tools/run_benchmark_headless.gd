extends SceneTree

## Headless benchmark entrypoint.
## Run with: godot --headless --script res://tools/run_benchmark_headless.gd
##
## Exits with code 0 on success, 1 on failure.

var _runner  : BenchmarkRunner = null
var _done    : bool            = false

func _initialize() -> void:
	print("--- Headless Benchmark Start ---")
	# Create a minimal root node so add_child works inside BenchmarkRunner
	var root_node := Node.new()
	root_node.name = "BenchRoot"
	get_root().add_child(root_node)

	_runner = BenchmarkRunner.new()
	_runner.name = "BenchmarkRunner"
	root_node.add_child(_runner)

	# Run asynchronously -- _idle will keep the loop alive until done
	_runner.run_benchmark(BenchmarkRunner.DEFAULT_RUNS)

func _idle(delta: float) -> bool:
	# Keep running until BenchmarkRunner finishes
	if _runner == null:
		return false  # quit
	if not _runner.is_running and _done == false:
		# Give one extra frame after completion for final writes
		_done = true
		return true
	if _done:
		print("--- Headless Benchmark Complete ---")
		quit(0)
		return false
	return true   # continue running

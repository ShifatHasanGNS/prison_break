extends Node

## Headless benchmark launcher. Attached to benchmark_main.tscn.
## Run with:  godot --headless res://tools/benchmark_main.tscn

const _RunnerScript = preload("res://tools/benchmark_runner.gd")

func _ready() -> void:
	print("=== benchmark_main: _ready fired ===")
	var runner = _RunnerScript.new()
	runner.name = "BenchmarkRunner"
	add_child(runner)
	_do_run(runner)

func _do_run(runner) -> void:
	await runner.run_benchmark(50)
	get_tree().quit(0)

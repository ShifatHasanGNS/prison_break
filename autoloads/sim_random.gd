extends Node

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	randomize()

func set_seed(s: int) -> void:
	_rng.seed = s

func reseed_from_time() -> int:
	randomize()
	var seed_value: int = int(Time.get_ticks_usec())
	seed_value ^= int(Time.get_unix_time_from_system() * 1000.0)
	seed_value ^= randi()
	_rng.seed = seed_value
	return seed_value

func get_seed() -> int:
	return _rng.seed

func randf() -> float:
	return _rng.randf()

func randf_range(lo: float, hi: float) -> float:
	return _rng.randf_range(lo, hi)

func randi_range(lo: int, hi: int) -> int:
	return _rng.randi_range(lo, hi)

func choice(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]

func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

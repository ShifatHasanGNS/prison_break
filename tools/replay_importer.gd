extends Node
class_name ReplayImporter

## Loads a replay JSON file and plays back snapshots at configurable speed.
## Connect to `snapshot_ready(snap: Dictionary)` to receive each frame.
## The header (fire_tiles, exits, etc.) is available after load via get_header().

signal snapshot_ready(snap: Dictionary)
signal playback_finished()

var _header    : Dictionary = {}
var _snapshots : Array      = []

var _current_idx : int   = 0
var _playing     : bool  = false
var _speed_mult  : float = 1.0   # 0.5 = half-speed, 2.0 = double-speed
var _accumulator : float = 0.0

## Seconds between snapshots at 1x speed, matching game's 4 ticks/sec default.
const BASE_INTERVAL : float = 0.25

# -------------------------------------------------------------------------

## Returns true if the file loaded successfully.
func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("ReplayImporter: file not found: %s" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("ReplayImporter: cannot open %s" % path)
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("ReplayImporter: invalid JSON in %s" % path)
		return false
	_header    = parsed.get("header",    {})
	_snapshots = parsed.get("snapshots", [])
	_current_idx = 0
	_playing     = false
	print("ReplayImporter: loaded %d snapshots (seed=%s) from %s" % [
		_snapshots.size(), _header.get("seed", "?"), path])
	return true

## Start / resume playback. speed_mult: 0.5 = half, 1.0 = normal, 2.0 = double.
func play(speed_mult: float = 1.0) -> void:
	_speed_mult  = maxf(speed_mult, 0.01)
	_playing     = true
	_accumulator = 0.0

func pause() -> void:
	_playing = false

func stop() -> void:
	_playing     = false
	_current_idx = 0
	_accumulator = 0.0

func is_playing() -> bool:
	return _playing

func get_snapshot_count() -> int:
	return _snapshots.size()

func get_current_index() -> int:
	return _current_idx

## Get header data (fire_tiles, exits, spawns, seed).
func get_header() -> Dictionary:
	return _header.duplicate()

## Seek to a specific snapshot index without emitting the signal.
func seek(idx: int) -> void:
	_current_idx = clampi(idx, 0, _snapshots.size() - 1)

# -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _playing or _snapshots.is_empty():
		return

	_accumulator += delta
	var interval := BASE_INTERVAL / _speed_mult

	while _accumulator >= interval:
		_accumulator -= interval
		if _current_idx >= _snapshots.size():
			_playing = false
			emit_signal("playback_finished")
			return
		emit_signal("snapshot_ready", _snapshots[_current_idx])
		_current_idx += 1

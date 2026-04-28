extends Node

var _cache: Dictionary = {}

func atlas(path: String, col: int, row: int) -> AtlasTexture:
	var key := "%s_%d_%d" % [path, col, row]
	if _cache.has(key):
		return _cache[key]

	if not FileAccess.file_exists(path):
		return null

	var tex: Texture2D = load(path)
	if tex == null:
		return null

	var quad := tex.get_width() / 2.0

	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = Rect2(col * quad, row * quad, quad, quad)
	a.margin = Rect2()
	_cache[key] = a
	return a

func frame_to_col_row(frame: int) -> Vector2i:
	return Vector2i(frame % 2, frame / 2)

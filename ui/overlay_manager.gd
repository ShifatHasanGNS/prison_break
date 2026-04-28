extends Node
class_name OverlayManager

## Handles F1–F4 keyboard shortcuts that toggle the three world-space overlays.
##
##   F1 — PathOverlay          (A* paths to active exit)
##   F2 — VisionOverlay        (agent FOV tiles)
##   F3 — DangerHeatmapOverlay (danger gradient per tile)
##   F4 — Hide all overlays
##
## Added directly to the Game scene — NOT inside a CanvasLayer.

var _path_overlay   : PathOverlay           = null
var _vision_overlay : VisionOverlay         = null
var _danger_overlay : DangerHeatmapOverlay  = null

# -------------------------------------------------------------------------

func setup(
	path_overlay   : PathOverlay,
	vision_overlay : VisionOverlay,
	danger_overlay : DangerHeatmapOverlay
) -> void:
	_path_overlay   = path_overlay
	_vision_overlay = vision_overlay
	_danger_overlay = danger_overlay

	# All overlays start hidden; player presses F1–F3 to reveal them
	if _path_overlay   != null: _path_overlay.visible   = false
	if _vision_overlay != null: _vision_overlay.visible = false
	if _danger_overlay != null: _danger_overlay.visible = false

	print("OverlayManager ready — F1:path  F2:vision  F3:danger  F4:hide-all")

# -------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_F1: _toggle(_path_overlay,   "path")
		KEY_F2: _toggle(_vision_overlay, "vision")
		KEY_F3: _toggle(_danger_overlay, "danger")
		KEY_F4: _hide_all()

func _toggle(overlay: Node2D, overlay_name: String) -> void:
	if overlay == null:
		return
	overlay.visible = not overlay.visible
	# Force an immediate redraw when switching on
	if overlay.visible:
		overlay.queue_redraw()
	EventBus.emit_signal("overlay_toggled", overlay_name, overlay.visible)
	print("Overlay '%s' → %s" % [overlay_name, "ON" if overlay.visible else "OFF"])

func toggle_overlay_by_name(overlay_name: String) -> bool:
	var overlay: Node2D = _overlay_from_name(overlay_name)
	if overlay == null:
		return false
	_toggle(overlay, overlay_name)
	return overlay.visible

func set_overlay_visible(overlay_name: String, is_visible: bool) -> void:
	var overlay: Node2D = _overlay_from_name(overlay_name)
	if overlay == null:
		return
	if overlay.visible == is_visible:
		return
	_toggle(overlay, overlay_name)

func is_overlay_visible(overlay_name: String) -> bool:
	var overlay: Node2D = _overlay_from_name(overlay_name)
	return overlay != null and overlay.visible

func _overlay_from_name(overlay_name: String) -> Node2D:
	match overlay_name:
		"path":
			return _path_overlay
		"vision":
			return _vision_overlay
		"danger":
			return _danger_overlay
		_:
			return null

func _hide_all() -> void:
	for pair in [
		[_path_overlay,   "path"],
		[_vision_overlay, "vision"],
		[_danger_overlay, "danger"],
	]:
		var overlay: Node2D = pair[0]
		var oname: String   = pair[1]
		if overlay != null:
			overlay.visible = false
			EventBus.emit_signal("overlay_toggled", oname, false)
	print("All overlays hidden (F4)")

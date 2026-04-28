extends Control
class_name IntroScreen

signal intro_finished

const INTRO_VIDEO_PATH: String = "res://prison_break_intro.ogv"
const TITLE_SCENE_PATH: String = "res://scenes/title_screen.tscn"

@onready var player: VideoStreamPlayer = $VideoStreamPlayer

var _finished: bool = false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

	if not ResourceLoader.exists(INTRO_VIDEO_PATH):
		push_warning("IntroScreen: missing intro video at %s" % INTRO_VIDEO_PATH)
		_finish_intro()
		return

	var stream: Resource = load(INTRO_VIDEO_PATH)
	if stream == null or not stream is VideoStream:
		push_warning("IntroScreen: failed to load intro video stream")
		_finish_intro()
		return

	player.stream = stream
	player.finished.connect(_on_video_finished)
	player.play()

func _input(event: InputEvent) -> void:
	if _finished:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_skip_intro()
		return
	if event is InputEventMouseButton and event.pressed:
		_skip_intro()

func _skip_intro() -> void:
	if _finished:
		return
	if player != null and player.playing:
		player.stop()
	_finish_intro()

func _on_video_finished() -> void:
	_finish_intro()

func _finish_intro() -> void:
	if _finished:
		return
	_finished = true
	emit_signal("intro_finished")
	get_tree().change_scene_to_file(TITLE_SCENE_PATH)

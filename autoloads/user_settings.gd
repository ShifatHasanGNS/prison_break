extends Node

const CONFIG_PATH: String = "user://user_settings.cfg"
const SEC_AUDIO: String = "audio"
const SEC_VISUAL: String = "visual"

var sound_enabled: bool = true
var music_enabled: bool = true
var master_volume_db: float = 0.0

var screen_shake_enabled: bool = true
var motion_trails_enabled: bool = true
var bloom_glow_enabled: bool = true
var volumetric_fog_enabled: bool = true

signal settings_changed()

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(CONFIG_PATH)
	if err != OK:
		emit_signal("settings_changed")
		return

	sound_enabled = bool(cfg.get_value(SEC_AUDIO, "sound_enabled", sound_enabled))
	music_enabled = bool(cfg.get_value(SEC_AUDIO, "music_enabled", music_enabled))
	master_volume_db = float(cfg.get_value(SEC_AUDIO, "master_volume_db", master_volume_db))

	screen_shake_enabled = bool(cfg.get_value(SEC_VISUAL, "screen_shake_enabled", screen_shake_enabled))
	motion_trails_enabled = bool(cfg.get_value(SEC_VISUAL, "motion_trails_enabled", motion_trails_enabled))
	bloom_glow_enabled = bool(cfg.get_value(SEC_VISUAL, "bloom_glow_enabled", bloom_glow_enabled))
	volumetric_fog_enabled = bool(cfg.get_value(SEC_VISUAL, "volumetric_fog_enabled", volumetric_fog_enabled))

	emit_signal("settings_changed")

func save_settings() -> void:
	var cfg := ConfigFile.new()

	cfg.set_value(SEC_AUDIO, "sound_enabled", sound_enabled)
	cfg.set_value(SEC_AUDIO, "music_enabled", music_enabled)
	cfg.set_value(SEC_AUDIO, "master_volume_db", master_volume_db)

	cfg.set_value(SEC_VISUAL, "screen_shake_enabled", screen_shake_enabled)
	cfg.set_value(SEC_VISUAL, "motion_trails_enabled", motion_trails_enabled)
	cfg.set_value(SEC_VISUAL, "bloom_glow_enabled", bloom_glow_enabled)
	cfg.set_value(SEC_VISUAL, "volumetric_fog_enabled", volumetric_fog_enabled)

	var err: int = cfg.save(CONFIG_PATH)
	if err != OK:
		push_warning("UserSettings: failed to save %s" % CONFIG_PATH)
	emit_signal("settings_changed")

func toggle_sound_enabled() -> void:
	sound_enabled = not sound_enabled
	save_settings()

func toggle_music_enabled() -> void:
	music_enabled = not music_enabled
	save_settings()

func toggle_screen_shake_enabled() -> void:
	screen_shake_enabled = not screen_shake_enabled
	save_settings()

func toggle_motion_trails_enabled() -> void:
	motion_trails_enabled = not motion_trails_enabled
	save_settings()

func toggle_bloom_glow_enabled() -> void:
	bloom_glow_enabled = not bloom_glow_enabled
	save_settings()

func toggle_volumetric_fog_enabled() -> void:
	volumetric_fog_enabled = not volumetric_fog_enabled
	save_settings()

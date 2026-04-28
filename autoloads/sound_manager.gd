extends Node

## Full procedural audio engine.
## All SFX are synthesised at runtime via AudioStreamWAV (PCM).
## Background music streams from res://assets/audio/prison_ambience_loop.ogg in a loop.
## All methods fail silently — never crash on missing audio.

const SAMPLE_RATE: int = 22050

var _sfx: Dictionary = {}      # name → AudioStreamPlayer (pre-loaded)
var _music: AudioStreamPlayer = null

# -------------------------------------------------------------------------

func _ready() -> void:
	_build_all_sfx()
	_connect_events()
	if UserSettings != null:
		UserSettings.settings_changed.connect(_apply_user_settings)
		_apply_user_settings()
	call_deferred("_start_music")

# =========================================================================
# Public API
# =========================================================================

func play(sound_name: String) -> void:
	if UserSettings != null and not UserSettings.sound_enabled:
		return
	var player: AudioStreamPlayer = _sfx.get(sound_name, null)
	if player == null:
		return
	if player.playing:
		player.stop()
	player.play()

func stop_all() -> void:
	for player in _sfx.values():
		player.stop()
	if _music != null:
		_music.stop()

func _apply_user_settings() -> void:
	if UserSettings == null:
		return
	for player in _sfx.values():
		if player is AudioStreamPlayer:
			player.volume_db = UserSettings.master_volume_db
	if _music != null:
		_music.volume_db = -10.0 + UserSettings.master_volume_db
		if not UserSettings.music_enabled and _music.playing:
			_music.stop()
		elif UserSettings.music_enabled and not _music.playing:
			_music.play()

# =========================================================================
# EventBus connections
# =========================================================================

func _connect_events() -> void:
	EventBus.tick_started.connect(func(_n): play("tick"))
	EventBus.agent_moved.connect(func(_id, _f, _t): play("footstep"))
	EventBus.agent_captured.connect(func(_id): play("capture"))
	EventBus.agent_escaped.connect(func(_id): play("escape"))
	EventBus.agent_respawned.connect(func(_id): play("agent_respawned"))
	EventBus.dog_state_changed.connect(func(_id, state):
		if state == "ALERT" or state == "CHASE":
			play("dog_bark")
		elif state == "SNIFF":
			play("dog_growl")
	)
	EventBus.door_state_changed.connect(func(_t, state):
		if state == "open":
			play("door_open")
		elif state == "broken":
			play("door_break")
	)
	EventBus.exit_activated.connect(func(_t): play("exit_activate"))
	EventBus.exit_deactivated.connect(func(_t): play("exit_deactivate"))
	EventBus.agent_entered_fire.connect(func(_id, _t): play("fire_crackle"))
	EventBus.agent_status_changed.connect(func(_id, effect, added):
		if added and effect == "detected":
			play("alert")
	)
	EventBus.simulation_ended.connect(func(result):
		if result.get("outcome") == "prisoners_win":
			play("game_over_win")
		else:
			play("game_over_lose")
	)

# =========================================================================
# Build all SFX
# =========================================================================

func _build_all_sfx() -> void:
	var sounds: Dictionary = {
		"tick":           _synth_tone(880,  0.05, 0.30, 8.0),
		"footstep":       _synth_footstep(),
		"sprint":         _synth_sprint(),
		"brawl":          _synth_brawl(),
		"alert":          _synth_sweep(440,  880,  0.20, 0.45),
		"capture":        _synth_capture(),
		"escape":         _synth_arpeggio([523, 659, 784, 1047],        0.10, 0.50),
		"door_open":      _synth_door_open(),
		"door_break":     _synth_noise(0.18, 0.55, 12.0),
		"dog_bark":       _synth_dog_bark(),
		"dog_growl":      _synth_dog_growl(),
		"fire_crackle":   _synth_fire_crackle(),
		"exit_activate":  _synth_arpeggio([523, 659, 784],              0.12, 0.55),
		"exit_deactivate":_synth_arpeggio([784, 659, 523],              0.12, 0.40),
		"game_over_win":  _synth_arpeggio([523, 659, 784, 1047, 1319],  0.12, 0.60),
		"game_over_lose": _synth_arpeggio([440, 370, 294, 220],         0.15, 0.55),
		"agent_respawned":_synth_sweep(220,  660,  0.15, 0.35),
	}

	for name: String in sounds:
		var stream: AudioStreamWAV = sounds[name]
		if stream == null:
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = 0.0
		player.bus = "Master"
		add_child(player)
		_sfx[name] = player

# =========================================================================
# PCM synthesis helpers
# =========================================================================

## Sine wave with exponential decay envelope.
func _synth_tone(freq: float, dur: float, vol: float, decay: float = 6.0) -> AudioStreamWAV:
	var n: int = int(SAMPLE_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = exp(-decay * t)
		var sample: float = vol * env * sin(TAU * freq * t)
		var s: int = clampi(int(sample * 32767.0), -32768, 32767)
		data[i * 2]     = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	return _make_wav(data, n)

## White noise with exponential decay envelope.
func _synth_noise(dur: float, vol: float, decay: float = 8.0) -> AudioStreamWAV:
	var n: int = int(SAMPLE_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = exp(-decay * t)
		var sample: float = vol * env * rng.randf_range(-1.0, 1.0)
		var s: int = clampi(int(sample * 32767.0), -32768, 32767)
		data[i * 2]     = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	return _make_wav(data, n)

## Linear frequency sweep (chirp).
func _synth_sweep(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
	var n: int = int(SAMPLE_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var frac: float = t / dur
		var freq: float = f0 + (f1 - f0) * frac
		var env: float  = 1.0 - frac * 0.5   # mild fade
		var sample: float = vol * env * sin(TAU * freq * t)
		var s: int = clampi(int(sample * 32767.0), -32768, 32767)
		data[i * 2]     = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	return _make_wav(data, n)

## Sequence of sine tones, each note_dur seconds long.
func _synth_arpeggio(freqs: Array, note_dur: float, vol: float) -> AudioStreamWAV:
	var note_samples: int = int(SAMPLE_RATE * note_dur)
	var total: int = note_samples * freqs.size()
	var data := PackedByteArray()
	data.resize(total * 2)
	for ni in range(freqs.size()):
		var freq: float = float(freqs[ni])
		for i in range(note_samples):
			var t: float = float(i) / float(SAMPLE_RATE)
			var env: float = exp(-5.0 * t)
			var sample: float = vol * env * sin(TAU * freq * t)
			var s: int = clampi(int(sample * 32767.0), -32768, 32767)
			var idx: int = (ni * note_samples + i) * 2
			data[idx]     = s & 0xFF
			data[idx + 1] = (s >> 8) & 0xFF
	return _make_wav(data, total)

## Concatenate two AudioStreamWAV streams.
func _concat_wav(a: AudioStreamWAV, b: AudioStreamWAV) -> AudioStreamWAV:
	if a == null:
		return b
	if b == null:
		return a
	var da: PackedByteArray = a.data
	var db: PackedByteArray = b.data
	var combined := PackedByteArray()
	combined.resize(da.size() + db.size())
	for i in range(da.size()):
		combined[i] = da[i]
	for i in range(db.size()):
		combined[da.size() + i] = db[i]
	return _make_wav(combined, (da.size() + db.size()) / 2)

func _make_wav(data: PackedByteArray, _sample_count: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo   = false
	wav.data     = data
	return wav

# =========================================================================
# Compound SFX
# =========================================================================

func _synth_footstep() -> AudioStreamWAV:
	# Low-pass approximation: halve every other sample to remove high freq harshness
	var base := _synth_noise(0.08, 0.18, 10.0)
	var d: PackedByteArray = base.data
	for i in range(0, d.size() / 2, 2):
		var idx: int = i * 2
		var lo: int = d[idx]
		var hi: int = d[idx + 1]
		var s: int = lo | (hi << 8)
		if s > 32767: s -= 65536
		s = s / 2
		d[idx]     = s & 0xFF
		d[idx + 1] = (s >> 8) & 0xFF
	base.data = d
	return base

func _synth_sprint() -> AudioStreamWAV:
	# Three rapid noise bursts
	var burst := _synth_noise(0.06, 0.28, 10.0)
	var gap_n: int = int(SAMPLE_RATE * 0.02) * 2   # 20ms silent gap in bytes
	var gap := PackedByteArray()
	gap.resize(gap_n)
	var bd: PackedByteArray = burst.data
	var combined := PackedByteArray()
	combined.resize(bd.size() * 3 + gap_n * 2)
	var offset: int = 0
	for _rep in range(3):
		for i in range(bd.size()):
			combined[offset + i] = bd[i]
		offset += bd.size()
		if _rep < 2:
			for i in range(gap_n):
				combined[offset + i] = 0
			offset += gap_n
	return _make_wav(combined, combined.size() / 2)

func _synth_brawl() -> AudioStreamWAV:
	# Noise punch + low thud layered
	var noise := _synth_noise(0.10, 0.40, 8.0)
	var thud  := _synth_tone(120, 0.08, 0.25, 12.0)
	var nd: PackedByteArray = noise.data
	var td: PackedByteArray = thud.data
	var shorter: int = mini(nd.size(), td.size())
	var combined := nd.duplicate()
	for i in range(0, shorter, 2):
		var s1_lo: int = nd[i];     var s1_hi: int = nd[i+1]
		var s2_lo: int = td[i];     var s2_hi: int = td[i+1]
		var s1: int = s1_lo | (s1_hi << 8)
		var s2: int = s2_lo | (s2_hi << 8)
		if s1 > 32767: s1 -= 65536
		if s2 > 32767: s2 -= 65536
		var mixed: int = clampi((s1 + s2) / 2, -32768, 32767)
		combined[i]   = mixed & 0xFF
		combined[i+1] = (mixed >> 8) & 0xFF
	return _make_wav(combined, combined.size() / 2)

func _synth_capture() -> AudioStreamWAV:
	var descend := _synth_sweep(660, 220, 0.15, 0.50)
	var hit     := _synth_noise(0.08, 0.30, 12.0)
	return _concat_wav(descend, hit)

func _synth_door_open() -> AudioStreamWAV:
	var rumble := _synth_sweep(80, 200, 0.12, 0.30)
	var creak  := _synth_noise(0.10, 0.20, 6.0)
	return _concat_wav(rumble, creak)

func _synth_dog_bark() -> AudioStreamWAV:
	var b1 := _synth_tone(280, 0.07, 0.50, 10.0)
	var b2 := _synth_tone(220, 0.06, 0.40, 10.0)
	return _concat_wav(b1, b2)

func _synth_dog_growl() -> AudioStreamWAV:
	# Noise with slow tremolo
	var dur: float = 0.40
	var n: int = int(SAMPLE_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99999
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = exp(-2.0 * t)
		var tremolo: float = 0.5 + 0.5 * sin(float(i) * 0.05)
		var sample: float = 0.20 * env * tremolo * rng.randf_range(-1.0, 1.0)
		var s: int = clampi(int(sample * 32767.0), -32768, 32767)
		data[i * 2]     = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	return _make_wav(data, n)

func _synth_fire_crackle() -> AudioStreamWAV:
	# 6 short noise bursts at slightly random intervals
	var burst_dur: float = 0.02
	var gap_dur: float   = 0.015
	var burst_n: int = int(SAMPLE_RATE * burst_dur)
	var gap_n: int   = int(SAMPLE_RATE * gap_dur)
	var total: int   = (burst_n + gap_n) * 6
	var data := PackedByteArray()
	data.resize(total * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77777
	var offset: int = 0
	for rep in range(6):
		var vol: float = rng.randf_range(0.15, 0.30)
		var decay: float = rng.randf_range(8.0, 14.0)
		for i in range(burst_n):
			var t: float = float(i) / float(SAMPLE_RATE)
			var env: float = exp(-decay * t)
			var sample: float = vol * env * rng.randf_range(-1.0, 1.0)
			var s: int = clampi(int(sample * 32767.0), -32768, 32767)
			var idx: int = offset + i * 2
			if idx + 1 < data.size():
				data[idx]     = s & 0xFF
				data[idx + 1] = (s >> 8) & 0xFF
		offset += burst_n * 2
		offset += gap_n * 2  # silent gap
	return _make_wav(data, total)

# =========================================================================
# Background music
# =========================================================================

func _start_music() -> void:
	if UserSettings != null and not UserSettings.music_enabled:
		return
	if _music != null and is_instance_valid(_music):
		if not _music.playing:
			_music.play()
		return

	var path := "res://assets/audio/prison_ambience_loop.ogg"
	var stream = load(path)
	if stream == null:
		push_warning("SoundManager: could not load music from %s" % path)
		return

	if stream is AudioStreamOggVorbis:
		stream.loop = true

	_music = AudioStreamPlayer.new()
	_music.name = "BackgroundMusic"
	_music.stream = stream
	_music.volume_db = -10.0
	_music.bus = "Master"
	add_child(_music)
	_music.finished.connect(_on_music_finished)
	_apply_user_settings()
	_music.play()

func _on_music_finished() -> void:
	if _music != null and is_instance_valid(_music):
		_music.play()

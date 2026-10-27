class_name Soundscape
extends Node

var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var phase: float = 0.0
var noise: float = 0.0
var grit: float = 0.0
var random: RandomNumberGenerator = RandomNumberGenerator.new()
var muted: bool = false
var shutting_down: bool = false
var impact_remaining: float = 0.0

func impact() -> void:
	impact_remaining = 0.24

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	shutting_down = true
	if player != null:
		player.stop()
		player.stream = null
	playback = null

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	random.seed = 71293
	var stream: AudioStreamGenerator = AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.15
	player = AudioStreamPlayer.new()
	# Web's Sample backend cannot play AudioStreamGenerator procedural audio.
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	player.stream = stream
	player.volume_db = -17.0
	add_child(player)
	player.play()
	playback = player.get_stream_playback() as AudioStreamGeneratorPlayback

func fill(speed: float, falling: bool, paused: bool, quiet: bool = false, surface: String = "stone", raining: bool = false, stamina: float = 100.0, slip: float = 0.0, simulation_elapsed: float = 0.0, action: String = "rest") -> void:
	if playback == null or shutting_down:
		return
	# Stone rings, soil absorbs impacts, and loose gravel crackles. Rain adds
	# a fine hiss and softens the roll while remaining fixed for the run.
	var tone: float = 78.0
	var impact_gain: float = 0.35
	var grain_gain: float = 0.035
	if surface in ["soil", "mud"]:
		tone = 43.0
		impact_gain = 0.14
		grain_gain = 0.014
	elif surface == "gravel":
		tone = 115.0
		impact_gain = 0.26
		grain_gain = 0.16
	var motion: float = minf(absf(speed) * 0.12, 3.0)
	var frames: int = mini(playback.get_frames_available(), 4096)
	for index: int in range(frames):
		phase += 1.0 / 22050.0
		noise = noise * 0.985 + random.randf_range(-1.0, 1.0) * 0.015
		grit = grit * 0.35 + random.randf_range(-1.0, 1.0) * 0.65
		var wind: float = noise * 0.75
		var drone: float = (sin(phase * TAU * 55.0) + sin(phase * TAU * 82.6)) * 0.05
		var roll: float = (noise + grit * grain_gain + sin(phase * TAU * tone) * 0.025) * motion
		var knock_phase: float = fmod(phase * (4.7 if surface == "gravel" else 2.6), 1.0)
		var knock: float = sin(knock_phase * tone * 2.7) * exp(-knock_phase * 22.0) * impact_gain if falling else 0.0
		var rain: float = grit * 0.052 + noise * 0.2 if raining else 0.0
		var value: float = wind + roll * (0.78 if raining else 1.0) + knock + rain + (0.0 if falling or quiet else drone)
		if not falling and not quiet:
			var breath_phase: float = fmod(simulation_elapsed + float(index) / 22050.0, 6.0)
			var breath: float = sin(breath_phase / 2.0 * PI) * 0.45 if breath_phase < 2.0 else (sin((breath_phase - 3.0) / 3.0 * PI) if breath_phase >= 3.0 else 0.0)
			var fatigue: float = 1.0 + clampf((50.0 - stamina) / 50.0, 0.0, 1.0) * 3.0
			value += (noise * 0.55 + grit * 0.013) * breath * fatigue
			var step_phase: float = fmod((simulation_elapsed + float(index) / 22050.0) * 2.4, 1.0)
			if action in ["push", "exert"] and absf(speed) > 0.03:
				value += sin(step_phase * 240.0) * exp(-step_phase * 38.0) * 0.07
			value += grit * clampf((slip - 40.0) / 60.0, 0.0, 1.0) * 0.12
			if impact_remaining > 0.0:
				value += sin((0.24 - impact_remaining) * TAU * 68.0) * impact_remaining * 1.3
		if not paused:
			impact_remaining = maxf(0.0, impact_remaining - 1.0 / 22050.0)
		if quiet:
			value = wind
		if muted or paused:
			value = 0.0
		playback.push_frame(Vector2(value, value))

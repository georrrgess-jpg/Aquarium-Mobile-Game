class_name Sfx
extends Node
## Placeholder audio synthesised at start-up (no asset files). Chains rise in
## pitch along a pentatonic ladder.

const RATE: int = 22050
const LADDER: Array = [1.0, 1.122, 1.26, 1.498, 1.682, 2.0, 2.244, 2.52]

var enabled: bool = true
var _streams: Dictionary = {}
var _players: Array = []

func _ready() -> void:
	_streams["pop"] = _tone([[520.0, 760.0]], 0.16, 0.5)
	_streams["select"] = _tone([[640.0, 640.0]], 0.07, 0.3)
	_streams["reject"] = _tone([[220.0, 150.0]], 0.18, 0.4, true)
	_streams["release"] = _tone([[400.0, 1100.0]], 0.4, 0.45)
	_streams["surge"] = _tone([[160.0, 90.0]], 0.55, 0.5, true)
	_streams["land"] = _tone([[300.0, 180.0]], 0.14, 0.4)
	_streams["shift"] = _tone([[300.0, 520.0]], 0.2, 0.35)
	_streams["flood"] = _tone([[300.0, 70.0]], 0.9, 0.5, true)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

func play(name: String, pitch: float = 1.0) -> void:
	if not enabled or not _streams.has(name):
		return
	for p in _players:
		var pl: AudioStreamPlayer = p
		if not pl.playing:
			pl.stream = _streams[name]
			pl.pitch_scale = pitch
			pl.play()
			return

## Merge pop; `step` is the chain step (0 = initial merge) and raises the pitch.
func pop(step: int) -> void:
	play("pop", float(LADDER[mini(step, LADDER.size() - 1)]))

func _tone(sweeps: Array, dur: float, vol: float, noisy: bool = false) -> AudioStreamWAV:
	var n: int = int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var phase: float = 0.0
	var f0: float = float(sweeps[0][0])
	var f1: float = float(sweeps[0][1])
	for i in n:
		var t: float = float(i) / float(n)
		var f: float = lerpf(f0, f1, t)
		phase += TAU * f / float(RATE)
		var env: float = pow(1.0 - t, 2.0) * minf(1.0, t * 40.0)
		var v: float = sin(phase)
		if noisy:
			v = v * 0.6 + rng.randf_range(-0.4, 0.4)
		data.encode_s16(i * 2, int(clampf(v * env * vol, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav

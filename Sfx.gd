extends Node
## Autoload "Sfx". All sound effects are synthesized at startup (no asset
## files): little PCM recipes baked into AudioStreamWAVs, played through a
## small pool of players. Sfx.play("coin"). Engine rumble loops separately.

const RATE := 22050

var _sounds: Dictionary = {}
var _pool: Array = []
var _pool_i: int = 0
var _pool3d: Array = []
var _pool3d_i: int = 0
var _engine: AudioStreamPlayer
var _alien: AudioStreamPlayer

func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_pool.append(p)

	_sounds["explode"] = _bake(0.4, func(t: float, n: float) -> float:
		return (randf() * 2.0 - 1.0) * exp(-6.0 * n))
	_sounds["nuke"] = _bake(5.5, func(t: float, n: float) -> float:
		# sub punch, blast wall, long rolling rumble, echo cracks
		var sub := sin(TAU * lerpf(52.0, 21.0, n) * t) * exp(-n * 2.0) * 1.5
		var blast := (randf() * 2.0 - 1.0) * exp(-n * 4.0) * 1.3
		var rumble := (randf() * 2.0 - 1.0) * 0.55 * exp(-n * 1.1) \
			* (0.55 + 0.45 * sin(TAU * 2.6 * t))
		var crack := (randf() * 2.0 - 1.0) * exp(-fmod(n * 4.0, 1.0) * 9.0) \
			* 0.3 * exp(-n * 1.8)
		return clampf(sub + blast + rumble + crack, -1.0, 1.0))
	_sounds["coin"] = _bake(0.16, func(t: float, n: float) -> float:
		var f := 880.0 if n < 0.5 else 1320.0
		return sin(TAU * f * t) * 0.6 * exp(-3.0 * n))
	_sounds["shoot"] = _bake(0.12, func(t: float, n: float) -> float:
		var f := lerpf(1400.0, 220.0, n)
		return signf(sin(TAU * f * t)) * 0.25 * exp(-4.0 * n))
	_sounds["click"] = _bake(0.04, func(t: float, n: float) -> float:
		return sin(TAU * 950.0 * t) * 0.5 * exp(-9.0 * n))
	# the OLD hurt was a raw sawtooth -- a harsh machine-gun rattle that
	# genuinely hurt at god volumes. Now: a soft round THUMP, sine-based,
	# quick and low, with the faintest knock of noise up front.
	# ONE soft, LONG whoomp -- rapid damage ticks used to re-fire a
	# short thump into a machine-gun burst that hurt real ears
	_sounds["hurt"] = _bake(0.9, func(t: float, n: float) -> float:
		var f := lerpf(140.0, 52.0, n)
		return sin(TAU * f * t) * 0.22 * (1.0 - n) * (1.0 - n))
	_sounds["eat"] = _bake(0.2, func(t: float, n: float) -> float:
		var f := 500.0 + 200.0 * sin(n * 9.0)
		return sin(TAU * f * t) * 0.4 * exp(-2.5 * n))
	_sounds["place"] = _bake(0.18, func(t: float, n: float) -> float:
		return sin(TAU * 120.0 * t) * 0.8 * exp(-7.0 * n))
	_sounds["warp"] = _bake(0.7, func(t: float, n: float) -> float:
		var f := lerpf(180.0, 1600.0, n * n)
		return sin(TAU * f * t) * 0.4 * (1.0 - n))
	_sounds["learn"] = _bake(0.5, func(t: float, n: float) -> float:
		var f: float = [523.0, 659.0, 784.0, 1047.0][mini(int(n * 4.0), 3)]
		return sin(TAU * f * t) * 0.4 * exp(-1.5 * fposmod(n * 4.0, 1.0)))
	_sounds["denied"] = _bake(0.25, func(t: float, n: float) -> float:
		return signf(sin(TAU * 160.0 * t)) * 0.2 * exp(-2.0 * n))
	_sounds["smelt"] = _bake(0.5, func(t: float, n: float) -> float:
		return ((randf() * 2.0 - 1.0) * 0.3 + sin(TAU * 300.0 * t) * 0.3) * exp(-2.2 * n))

	_sounds["rumble"] = _bake(1.1, func(t: float, n: float) -> float:
		var env := sin(PI * n)   # swell in, fade out
		return ((randf() * 2.0 - 1.0) * 0.35 + sin(TAU * 42.0 * t) * 0.5 + sin(TAU * 63.0 * t) * 0.25) * env)

	# 3D positional pool (worm breaches etc.)
	for i in 6:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 14.0
		p3.max_distance = 260.0
		add_child(p3)
		_pool3d.append(p3)

	# alien drive: wobbling theremin hum + sub throb. very UFO.
	_alien = AudioStreamPlayer.new()
	_alien.volume_db = -12.0
	var awav := _bake(1.2, func(t: float, n: float) -> float:
		var wob := 180.0 + 45.0 * sin(TAU * t * 5.0)
		return sin(TAU * wob * t) * 0.35 \
			+ sin(TAU * wob * 2.01 * t) * 0.18 \
			+ sin(TAU * 55.0 * t) * 0.3 \
			+ (randf() * 2.0 - 1.0) * 0.05)
	awav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	awav.loop_end = int(1.2 * RATE)
	_alien.stream = awav
	add_child(_alien)

	# looping engine rumble
	_engine = AudioStreamPlayer.new()
	_engine.volume_db = -14.0
	var noise := _bake(0.5, func(t: float, n: float) -> float:
		return (randf() * 2.0 - 1.0) * 0.5 + sin(TAU * 60.0 * t) * 0.3)
	noise.loop_mode = AudioStreamWAV.LOOP_FORWARD
	noise.loop_end = int(0.5 * RATE)
	_engine.stream = noise
	add_child(_engine)

func _bake(dur: float, f: Callable) -> AudioStreamWAV:
	var frames := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / RATE
		var n := float(i) / float(frames)
		var v := clampf(f.call(t, n), -1.0, 1.0)
		var s := int(v * 32000.0)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav

func play(name: String, vol_db: float = -8.0) -> void:
	if not _sounds.has(name):
		return
	var p: AudioStreamPlayer = _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = _sounds[name]
	p.volume_db = vol_db + Settings.sfx_db()
	p.play()

## Positional one-shot: rumbles from WHERE it happened.
func play_at(name: String, pos: Vector3, vol_db: float = 0.0) -> void:
	if not _sounds.has(name):
		return
	var p: AudioStreamPlayer3D = _pool3d[_pool3d_i]
	_pool3d_i = (_pool3d_i + 1) % _pool3d.size()
	p.global_position = pos
	p.stream = _sounds[name]
	p.volume_db = vol_db + Settings.sfx_db()
	p.play()

func engine(on: bool) -> void:
	if on and not _engine.playing:
		_engine.play()
	elif not on and _engine.playing:
		_engine.stop()

## The starship's drive: pitch bends with thrust for maximum saucer.
func alien_engine(on: bool, pitch: float = 1.0) -> void:
	_alien.pitch_scale = clampf(pitch, 0.6, 2.2)
	if on and not _alien.playing:
		_alien.play()
	elif not on and _alien.playing:
		_alien.stop()

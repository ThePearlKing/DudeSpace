class_name RadioLib
extends RefCounted
## Everything that comes OUT of the intergalactic radio: static, seeded
## procedural music loops per planet style, and the words -- Earth news,
## shader-system alien transmissions, and the noodle god's own station.

const SR := 22050

# ------------------------------------------------------------- static

static var _static_wav: AudioStreamWAV = null

static func static_noise() -> AudioStreamWAV:
	if _static_wav:
		return _static_wav
	var n := int(1.6 * SR)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var brown := 0.0
	for i in n:
		var w := randf() * 2.0 - 1.0
		brown = clampf(brown + w * 0.18, -1.0, 1.0)
		var v := (w * 0.5 + brown * 0.4) * 0.5
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 22000.0))
	_static_wav = AudioStreamWAV.new()
	_static_wav.format = AudioStreamWAV.FORMAT_16_BITS
	_static_wav.mix_rate = SR
	_static_wav.data = bytes
	_static_wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_static_wav.loop_end = n
	return _static_wav

# ------------------------------------------------------------- music

## Style per planet kind: scale intervals, tempo, wave, register.
static func style_for(kind: String) -> Dictionary:
	match kind:
		"pi":
			return {"scale": [0, 2, 4, 7, 9, 12, 14], "bpm": 150, "wave": "square",
				"base": 330.0, "digits": true}   # the melody IS pi
		"earth":
			return {"scale": [0, 2, 4, 7, 9, 12], "bpm": 96, "wave": "flute",
				"base": 294.0}   # easy listening for a doomed species
		"rick":
			return {"scale": [0, 2, 4, 5, 7, 9], "bpm": 113, "wave": "square",
				"base": 233.0}   # a suspiciously committed groove
		"gas", "jazz":
			return {"scale": [0, 2, 3, 5, 7, 9, 10], "bpm": 88, "wave": "sine",
				"base": 220.0, "jazz": true}   # gas giants swing
		"life", "varnisol":
			return {"scale": [0, 3, 5, 7, 10, 12], "bpm": 84, "wave": "pluck",
				"base": 262.0}   # gentle plucked pentatonic
		"ice":
			# XERO: sparse glassy bells over a very cold, very slow pulse
			return {"scale": [0, 2, 7, 9, 12, 14], "bpm": 68, "wave": "bell",
				"base": 587.0}
		"crystal":
			return {"scale": [0, 4, 7, 11, 12, 16], "bpm": 100, "wave": "bell",
				"base": 523.0}   # glassy heights, struck
		"torus":
			return {"scale": [0, 2, 3, 6, 8, 12], "bpm": 122, "wave": "wobble",
				"base": 294.0}   # donut logic
		"lava", "volcanic":
			return {"scale": [0, 1, 5, 6, 10, 12], "bpm": 132, "wave": "saw",
				"base": 147.0}   # aggressive low
		"sand":
			# EUCLID: double-harmonic scale, reedy ornamented lead, tanpura
			# drone and a hand drum. The pyramid approves.
			return {"scale": [0, 1, 4, 5, 7, 8, 11], "bpm": 92, "wave": "reed",
				"base": 220.0, "drone": true}
		"venus", "rock":
			# VENUS ROCK: distorted power chords, driving drums, pentatonic riff
			return {"scale": [0, 3, 5, 7, 10, 12], "bpm": 126, "wave": "saw",
				"base": 196.0, "rock": true}
		"circuit", "logic":
			return {"scale": [0, 3, 7, 10, 12], "bpm": 160, "wave": "square",
				"base": 392.0}   # chip factory
		_:
			return {"scale": [0, 2, 4, 5, 7, 9, 11, 12], "bpm": 110, "wave": "pluck",
				"base": 262.0}

static var _music_cache := {}

## A seeded looping melody, ~9s, in the planet's style.
static func music_loop(seed_v: int, kind: String) -> AudioStreamWAV:
	var key := "%d_%s" % [seed_v, kind]
	if _music_cache.has(key):
		return _music_cache[key]
	var st := style_for(kind)
	if bool(st.get("jazz", false)):
		var wavj := _jazz_loop(seed_v, st)
		_music_cache[key] = wavj
		return wavj
	if bool(st.get("rock", false)):
		var wavr := _rock_loop(seed_v, st)
		_music_cache[key] = wavr
		return wavr
	if kind == "blackhole":
		var wavb := _bh_loop()
		_music_cache[key] = wavb
		return wavb
	if kind == "sun":
		var wavs := _star_loop(seed_v)
		_music_cache[key] = wavs
		return wavs
	if kind == "ice":
		var wavi := _ice_loop()
		_music_cache[key] = wavi
		return wavi
	if kind == "earth":
		var wave2 := _earth_loop(seed_v)
		_music_cache[key] = wave2
		return wave2
	if kind == "circuit" or kind == "logic":
		var wavq := _circuit_loop(seed_v)
		_music_cache[key] = wavq
		return wavq
	if kind == "sand":
		var wavd := _euclid_loop(seed_v)
		_music_cache[key] = wavd
		return wavd
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var beat := 60.0 / float(st["bpm"])
	var notes := 16
	var total := int(float(notes) * beat * SR)
	var buf := PackedFloat32Array()
	buf.resize(total)
	var scale: Array = st["scale"]
	var base: float = st["base"]
	var wave: String = st["wave"]
	var pi_digits := "3141592653589793238462643383279"
	var deg := 0
	for ni in notes:
		if bool(st.get("digits", false)):
			# THE PI STATION: the melody is literally pi, digit by digit
			deg = int(pi_digits[ni % pi_digits.length()]) % scale.size()
		else:
			# melodies walk, mostly; leap sometimes; rest sometimes
			if rng.randf() < 0.15:
				continue   # a rest. music is the notes you don't play.
			deg = clampi(deg + (rng.randi_range(-2, 2) if rng.randf() < 0.8
				else rng.randi_range(-4, 4)), 0, scale.size() - 1)
		var f := base * pow(2.0, float(scale[deg]) / 12.0)
		if rng.randf() < 0.2:
			f *= 0.5   # bass note drop
		var start := int(float(ni) * beat * SR)
		var dur := int(beat * SR * (0.9 if rng.randf() < 0.7 else 1.8))
		for i in mini(dur, total - start):
			var t := float(i) / SR
			var v := 0.0
			match wave:
				"square":
					v = 0.25 if fmod(f * t, 1.0) < 0.5 else -0.25
				"saw":
					v = (fmod(f * t, 1.0) * 2.0 - 1.0) * 0.3
				"wobble":
					v = sin(TAU * f * t + 2.0 * sin(TAU * 5.0 * t)) * 0.32
				"pluck":
					v = (sin(TAU * f * t) + 0.5 * sin(TAU * f * 2.0 * t) \
						+ 0.25 * sin(TAU * f * 3.0 * t)) * 0.4 * exp(-t * 5.0)
				"bell":
					v = (sin(TAU * f * t) + 0.55 * sin(TAU * f * 2.76 * t) \
						+ 0.3 * sin(TAU * f * 5.4 * t)) * 0.33 * exp(-t * 3.5)
				"reed":
					var fv := f * (1.0 + 0.012 * sin(TAU * 5.5 * t))
					v = (fmod(fv * t, 1.0) * 2.0 - 1.0) * 0.15 + sin(TAU * fv * t) * 0.18
				"flute":
					v = sin(TAU * f * (1.0 + 0.006 * sin(TAU * 5.0 * t)) * t) * 0.32 \
						+ (randf() * 2.0 - 1.0) * 0.02
				_:
					v = sin(TAU * f * t) * 0.35 + sin(TAU * f * 2.0 * t) * 0.08
			var env := minf(1.0, float(i) / (SR * 0.01)) \
				* minf(1.0, float(dur - i) / (SR * 0.08))
			buf[start + i] += v * env
	if bool(st.get("drone", false)):
		# tanpura drone + hand drum: dum on the downbeats, tek between
		for i in total:
			var td := float(i) / SR
			buf[i] += (sin(TAU * base * 0.5 * td) * 0.09 \
				+ sin(TAU * base * 0.75 * td) * 0.045) \
				* (0.8 + 0.2 * sin(TAU * 0.25 * td))
		var beat_s := int(beat * SR)
		for bi in notes:
			var b0 := bi * beat_s
			if bi % 2 == 0:
				for i in mini(int(0.11 * SR), total - b0):
					var tt := float(i) / SR
					buf[b0 + i] += sin(TAU * 78.0 * tt) * exp(-tt * 26.0) * 0.5
			else:
				var tk := b0 + int(beat_s * 0.5)
				for i in mini(int(0.04 * SR), total - tk):
					buf[tk + i] += (randf() * 2.0 - 1.0) * exp(-float(i) / (SR * 0.008)) * 0.16
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 24000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = total
	_music_cache[key] = wav
	return wav

## Actual jazz: walking bass on quarters, swung ride, sparse two-note
## comp stabs (3rd+7th shells -- NOT the whole chord mashed at once),
## and a swung horn line. Changes move ii-V-I-vi so it goes somewhere.
static func _jazz_loop(seed_v: int, st: Dictionary) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var base: float = st["base"]
	var beat := 60.0 / float(st["bpm"])
	var bars := 4
	var total := int(float(bars) * 4.0 * beat * SR)
	var buf := PackedFloat32Array()
	buf.resize(total)
	# root, 3rd, 7th in semitones from base: Dm7 G7 Cmaj7 A7
	var chords: Array = [[2, 5, 12], [7, 11, 17], [0, 4, 11], [9, 13, 19]]
	for bar in bars:
		var ch: Array = chords[bar % 4]
		var b0 := int(float(bar) * 4.0 * beat * SR)
		# walking bass: root, 3rd, 5th, chromatic approach to the next root
		var walk: Array = [int(ch[0]), int(ch[0]) + 4, int(ch[0]) + 7,
			int(chords[(bar + 1) % 4][0]) - 1]
		for q in 4:
			var f := base * 0.5 * pow(2.0, float(walk[q]) / 12.0)
			var stq := b0 + int(float(q) * beat * SR)
			var dur := int(beat * SR * 0.95)
			for i in mini(dur, total - stq):
				var t := float(i) / SR
				var env := minf(1.0, float(i) / (SR * 0.008)) * exp(-t * 2.2)
				buf[stq + i] += (sin(TAU * f * t) + 0.4 * sin(TAU * f * 2.0 * t)) * 0.3 * env
			# ride tick each beat, swung skip note on 2 and 4
			for i in mini(int(0.05 * SR), total - stq):
				buf[stq + i] += (randf() * 2.0 - 1.0) * 0.08 * exp(-float(i) / (SR * 0.012))
			if q % 2 == 1:
				var sk := stq + int(beat * SR * 0.66)
				for i in mini(int(0.04 * SR), total - sk):
					buf[sk + i] += (randf() * 2.0 - 1.0) * 0.06 * exp(-float(i) / (SR * 0.01))
		# ONE comp stab per bar, offbeat, two notes only
		var stab_b := 0.66 if rng.randf() < 0.5 else 2.66
		var stab_s := b0 + int(stab_b * beat * SR)
		for i in mini(int(0.22 * SR), total - stab_s):
			var t2 := float(i) / SR
			var env2 := minf(1.0, float(i) / (SR * 0.004)) * exp(-t2 * 9.0)
			buf[stab_s + i] += (sin(TAU * base * pow(2.0, float(ch[1]) / 12.0) * t2) \
				+ sin(TAU * base * pow(2.0, float(ch[2]) / 12.0) * t2)) * 0.12 * env2
	# the horn: swung 8ths over dorian, plenty of air between phrases
	var scale: Array = [0, 2, 3, 5, 7, 9, 10, 12, 14]
	var deg := 4
	for s8 in bars * 8:
		if rng.randf() < 0.3:
			continue
		deg = clampi(deg + rng.randi_range(-2, 2), 0, scale.size() - 1)
		var f2 := base * 2.0 * pow(2.0, float(scale[deg]) / 12.0)
		var pos_b := float(s8) * 0.5 + (0.17 if s8 % 2 == 1 else 0.0)
		var hs := int(pos_b * beat * SR)
		var hd := int(beat * SR * (0.35 if s8 % 2 == 1 else 0.5))
		if rng.randf() < 0.15:
			hd = int(beat * SR * 1.4)
		for i in mini(hd, total - hs):
			var t3 := float(i) / SR
			var env3 := minf(1.0, float(i) / (SR * 0.02)) \
				* minf(1.0, float(hd - i) / (SR * 0.05))
			var vib := 1.0 + 0.008 * sin(TAU * 5.2 * t3)
			buf[hs + i] += (sin(TAU * f2 * vib * t3) + 0.3 * sin(TAU * f2 * 2.0 * vib * t3) \
				+ 0.12 * sin(TAU * f2 * 3.0 * t3)) * 0.2 * env3
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 24000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = total
	return wav

## ROCK: clipped power chords on the downbeats, kick on 1 and 3, snare
## cracking 2 and 4, eighth-note hats, and a pentatonic riff on top with
## the same distortion. Venus wants it loud.
static func _rock_loop(seed_v: int, st: Dictionary) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var base: float = st["base"]
	var beat := 60.0 / float(st["bpm"])
	var bars := 4
	var total := int(float(bars) * 4.0 * beat * SR)
	var buf := PackedFloat32Array()
	buf.resize(total)
	# chord roots per bar (semitones): i - bVI - bVII - i, the rock classic
	var prog: Array = [0, 8, 10, 0]
	for bar in bars:
		var root := base * pow(2.0, float(prog[bar % 4]) / 12.0) * 0.5
		var b0 := int(float(bar) * 4.0 * beat * SR)
		# power chords: chugging eighths, root + fifth + octave, CLIPPED
		for e8 in 8:
			var stq := b0 + int(float(e8) * 0.5 * beat * SR)
			var dur := int(0.42 * beat * SR)
			if e8 == 6 and rng.randf() < 0.4:
				dur = int(0.9 * beat * SR)   # let one ring
			for i in mini(dur, total - stq):
				var t := float(i) / SR
				var raw := (fmod(root * t, 1.0) * 2.0 - 1.0) \
					+ (fmod(root * 1.5 * t, 1.0) * 2.0 - 1.0) * 0.8 \
					+ (fmod(root * 2.0 * t, 1.0) * 2.0 - 1.0) * 0.5
				var env := minf(1.0, float(i) / (SR * 0.004)) * (1.0 - float(i) / float(dur) * 0.55)
				buf[stq + i] += clampf(raw * 1.8, -0.85, 0.85) * 0.17 * env
		# drums
		for q in 4:
			var qs := b0 + int(float(q) * beat * SR)
			if q % 2 == 0:   # kick on 1 and 3
				for i in mini(int(0.1 * SR), total - qs):
					var tt := float(i) / SR
					buf[qs + i] += sin(TAU * (95.0 - tt * 320.0) * tt) * exp(-tt * 30.0) * 0.7
			else:            # snare on 2 and 4
				for i in mini(int(0.12 * SR), total - qs):
					var tt2 := float(i) / SR
					buf[qs + i] += ((randf() * 2.0 - 1.0) * 0.5 \
						+ sin(TAU * 180.0 * tt2) * 0.2) * exp(-tt2 * 22.0)
			for hh in 2:     # eighth hats
				var hsp := qs + int(float(hh) * 0.5 * beat * SR)
				for i in mini(int(0.025 * SR), total - hsp):
					buf[hsp + i] += (randf() * 2.0 - 1.0) * 0.09 * exp(-float(i) / (SR * 0.006))
	# the riff: distorted pentatonic lead, one octave up
	var scale: Array = st["scale"]
	var deg := 2
	for s8 in bars * 8:
		if rng.randf() < 0.35:
			continue
		deg = clampi(deg + rng.randi_range(-2, 2), 0, scale.size() - 1)
		var f2 := base * 2.0 * pow(2.0, float(scale[deg]) / 12.0)
		var hs := int(float(s8) * 0.5 * beat * SR)
		var hd := int(beat * SR * (0.45 if rng.randf() < 0.75 else 1.1))
		for i in mini(hd, total - hs):
			var t3 := float(i) / SR
			var env3 := minf(1.0, float(i) / (SR * 0.006)) \
				* minf(1.0, float(hd - i) / (SR * 0.04))
			var vib := 1.0 + 0.01 * sin(TAU * 6.0 * t3) * minf(1.0, t3 * 4.0)
			var raw2 := (fmod(f2 * vib * t3, 1.0) * 2.0 - 1.0) \
				+ 0.4 * (fmod(f2 * 2.0 * vib * t3, 1.0) * 2.0 - 1.0)
			buf[hs + i] += clampf(raw2 * 2.2, -0.8, 0.8) * 0.13 * env3
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 24000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = total
	return wav

## TIN 618: what a black hole sounds like on the dial. Bottomless
## detuned drones bending under the loop phase, slow accretion sweeps
## of filtered noise, and a sub-thump like something orbiting too close.
static var _bh_wav: AudioStreamWAV = null

static func _bh_loop() -> AudioStreamWAV:
	if _bh_wav:
		return _bh_wav
	# THE internet black hole sound: not a dark groan -- an eerie mid-range
	# WAIL. A chorus of detuned voices, each sliding pitch on its own slow
	# clock (real phase accumulation, so the bends are smooth), swelling
	# unevenly, with a thin breath of noise. Rendered long and crossfaded
	# onto itself so the loop never clicks.
	var total := int(16.0 * SR)
	var render := int(18.0 * SR)
	var buf := PackedFloat32Array()
	buf.resize(render)
	var voices: Array = [
		[196.0, 0.9, 1.7, 0.0], [233.0, 1.3, 0.6, 2.1], [311.0, 0.7, 2.3, 4.0],
		[415.0, 1.1, 1.2, 1.0], [155.0, 0.5, 2.9, 3.3]]
	for v in voices:
		var f0: float = v[0]
		var r1: float = v[1]
		var r2: float = v[2]
		var ph0: float = v[3]
		var phase := 0.0
		for i in render:
			var t := float(i) / SR
			var lp := t / 16.0 * TAU
			var bend := 1.0 + 0.09 * sin(lp * r1 + ph0) \
				+ 0.045 * sin(lp * r2 * 1.9 + ph0 * 2.0)
			phase += TAU * f0 * bend / SR
			var amp := 0.16 * (0.45 + 0.55 * sin(lp * r2 + ph0 * 3.0))
			buf[i] += (sin(phase) + 0.35 * sin(phase * 2.0)) * amp
	for i in render:
		var t2 := float(i) / SR
		# one warbling overtone + a thin breath: the "what IS that" layer
		buf[i] += sin(TAU * 622.0 * t2) * 0.05 \
			* (0.5 + 0.5 * sin(TAU * 0.31 * t2)) * (0.6 + 0.4 * sin(TAU * 7.0 * t2)) \
			+ (randf() * 2.0 - 1.0) * 0.02
	var out := PackedFloat32Array()
	out.resize(total)
	var xf := render - total
	for i in total:
		var v2 := buf[i]
		if i < xf:
			var k := float(i) / float(xf)
			v2 = buf[total + i] * (1.0 - k) + buf[i] * k
		out[i] = v2
	return _encode_loop(out, total, "_bh")

## Stars hum. Weirdly. Inharmonic shimmer partials breathing on their
## own clocks, solar-crackle granules, and a deep fusion roar.
static func _star_loop(seed_v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var total := int(12.0 * SR)
	var buf := PackedFloat32Array()
	buf.resize(total)
	var f0 := roundf(rng.randf_range(320.0, 640.0) * 12.0) / 12.0
	var parts: Array = [1.0, 2.76, 4.07, 5.43]
	var phases: Array = []
	for k in parts.size():
		phases.append(rng.randf() * TAU)
	for i in total:
		var t := float(i) / SR
		var lp := float(i) / float(total) * TAU
		var v := sin(TAU * 55.0 * t) * 0.12   # the roar
		for k in parts.size():
			var am := 0.5 + 0.5 * sin(lp * float(k + 1) + float(phases[k]))
			v += sin(TAU * f0 * float(parts[k]) * t) * 0.09 * am
		buf[i] = v
	# solar crackle: granular pops, denser than silence, sparser than rain
	for c in 260:
		var st2 := rng.randi() % (total - 220)
		var amp := rng.randf_range(0.05, 0.16)
		for j in 200:
			buf[st2 + j] += (rng.randf() * 2.0 - 1.0) * amp * exp(-float(j) / 40.0)
	return _encode_loop(buf, total, "")

## XERO: cold maj7/maj9 chord pads swelling over a constant low drone
## with a slow detune shimmer, sparse high bells off the chord tones,
## and a thin wind. Nothing like Crystalia's arpeggios.
static var _ice_wav: AudioStreamWAV = null

static func _ice_loop() -> AudioStreamWAV:
	if _ice_wav:
		return _ice_wav
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var base := 294.0
	var total := int(14.0 * SR)
	var barlen := int(3.5 * SR)
	var buf := PackedFloat32Array()
	buf.resize(total)
	# the drone: root an octave down + a hair-detuned twin (slow beating)
	for i in total:
		var t := float(i) / SR
		buf[i] += (sin(TAU * 147.0 * t) + sin(TAU * 147.35 * t)) * 0.115 \
			+ (randf() * 2.0 - 1.0) * 0.017   # the wind
	# chords: Imaj7 IVmaj7 vim7 V7 -- swelling pads, zero at bar edges
	var prog: Array = [[0, 4, 7, 11], [5, 9, 12, 16], [-3, 0, 4, 7], [7, 11, 14, 17]]
	for bar in 4:
		var ch: Array = prog[bar]
		var b0 := bar * barlen
		for semi in ch:
			var f := base * pow(2.0, float(semi) / 12.0)
			for i in mini(barlen, total - b0):
				var t2 := float(i) / SR
				var env := sin(PI * float(i) / float(barlen))   # swell in, swell out
				buf[b0 + i] += sin(TAU * f * t2) * 0.07 * env * env
		# two or three bells off the chord, high and brief
		for nb in 2 + rng.randi() % 2:
			var bf := base * 2.0 * pow(2.0, float(ch[rng.randi() % ch.size()]) / 12.0)
			var bs := b0 + rng.randi() % int(barlen * 0.7)
			for i in mini(int(1.4 * SR), total - bs):
				var t3 := float(i) / SR
				buf[bs + i] += (sin(TAU * bf * t3) + 0.4 * sin(TAU * bf * 2.76 * t3)) \
					* 0.14 * exp(-t3 * 3.2)
	return _encode_loop(buf, total, "_ice")

## Shared tail: normalize-ish clamp, 16-bit, forward loop. cache_slot
## "_bh"/"_ice" pins the wav to the matching static (seedless loops).
static func _encode_loop(buf: PackedFloat32Array, total: int, cache_slot: String) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 24000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = total
	if cache_slot == "_bh":
		_bh_wav = wav
	elif cache_slot == "_ice":
		_ice_wav = wav
	return wav

## EARTH2, done properly: easy listening with actual songcraft. I-vi-IV-V
## pads swelling under a soft walking bass, a vibrato flute melody that
## lands on chord tones at the downbeats, and a brushed tick on 2 and 4.
static func _earth_loop(seed_v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var base := 262.0
	var beat := 60.0 / 84.0
	var bars := 4
	var barlen := int(4.0 * beat * SR)
	var total := barlen * bars
	var buf := PackedFloat32Array()
	buf.resize(total)
	var prog: Array = [[0, 4, 7], [-3, 0, 4], [5, 9, 12], [7, 11, 14]]
	for bar in bars:
		var ch: Array = prog[bar]
		var b0 := bar * barlen
		# pads: warm triad + octave root, swelling through the bar
		for semi in [ch[0], ch[1], ch[2], ch[0] + 12]:
			var f := base * pow(2.0, float(semi) / 12.0)
			for i in mini(barlen, total - b0):
				var t := float(i) / SR
				var env := sin(PI * float(i) / float(barlen))
				buf[b0 + i] += sin(TAU * f * t) * 0.05 * env * env
		# bass: root on 1 and 3, soft and round
		for q in [0, 2]:
			var bs := b0 + int(float(q) * beat * SR)
			var bf := base * 0.5 * pow(2.0, float(ch[0]) / 12.0)
			for i in mini(int(beat * SR * 1.6), total - bs):
				var t2 := float(i) / SR
				buf[bs + i] += sin(TAU * bf * t2) * 0.14 \
					* minf(1.0, float(i) / (SR * 0.02)) * exp(-t2 * 1.4)
		# brushes: a soft tick on 2 and 4
		for q2 in [1, 3]:
			var ts := b0 + int(float(q2) * beat * SR)
			for i in mini(int(0.05 * SR), total - ts):
				buf[ts + i] += (randf() * 2.0 - 1.0) * 0.05 * exp(-float(i) / (SR * 0.014))
		# melody: flute with vibrato -- chord tone ON the downbeats,
		# scale steps drifting between them
		var scale: Array = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16]
		for h in 4:
			if h % 2 == 0 or rng.randf() < 0.75:
				var semi2: int
				if h % 2 == 0:
					semi2 = int(ch[rng.randi() % ch.size()]) + 12
				else:
					semi2 = int(scale[rng.randi() % scale.size()]) + 12
				var mf := base * pow(2.0, float(semi2) / 12.0)
				var ms := b0 + int(float(h) * beat * SR)
				var md := int(beat * SR * (0.9 if rng.randf() < 0.7 else 1.8))
				for i in mini(md, total - ms):
					var t3 := float(i) / SR
					var env3 := minf(1.0, float(i) / (SR * 0.05)) \
						* minf(1.0, float(md - i) / (SR * 0.1))
					var vib := 1.0 + 0.007 * sin(TAU * 5.0 * t3) * minf(1.0, t3 * 3.0)
					buf[ms + i] += (sin(TAU * mf * vib * t3) \
						+ 0.2 * sin(TAU * mf * 2.0 * t3)) * 0.16 * env3
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 24000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = total
	return wav

## CIRCUITIA: chip music with INTENT. A fixed arpeggio pattern climbing
## and falling through minor-pentatonic, transposed per bar, over a
## triangle-wave bass walking root and fifth. Ticky hats. No dice rolls
## in the melody -- machines don't improvise, they iterate.
static func _circuit_loop(seed_v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var base := 392.0
	var beat := 60.0 / 150.0
	var barlen := int(4.0 * beat * SR)
	var total := barlen * 16
	var buf := PackedFloat32Array()
	buf.resize(total)
	var arp: Array = [0, 3, 7, 10, 12, 10, 7, 3]
	var trans: Array = [0, 0, -2, 3]
	var s16 := int(beat * SR * 0.25)
	# 16 bars: bars 0-7 = the classic loop twice; bars 8-15 = SAME arps
	# but the bass wakes up and the drums get complicated. then loop.
	for bar in 16:
		var part2 := bar >= 8
		var tr := int(trans[bar % 4])
		var b0 := bar * barlen
		# the arp: 16ths, pattern-locked
		for n in 16:
			var semi := int(arp[n % arp.size()]) + tr
			var f := base * pow(2.0, float(semi) / 12.0)
			var ns := b0 + n * s16
			for i in mini(int(s16 * 0.85), total - ns):
				var t := float(i) / SR
				var env := minf(1.0, float(i) / (SR * 0.003)) \
					* (1.0 - float(i) / (s16 * 0.85))
				buf[ns + i] += (0.16 if fmod(f * t, 1.0) < 0.5 else -0.16) * env
		if not part2:
			# triangle bass: eighths, root-root-fifth-root figure
			for e8 in 8:
				var bsemi := tr + (7 if e8 % 4 == 2 else 0)
				var bf := base * 0.25 * pow(2.0, float(bsemi) / 12.0)
				var bs := b0 + e8 * s16 * 2
				for i in mini(int(s16 * 1.7), total - bs):
					var t2 := float(i) / SR
					var tri := 2.0 * absf(2.0 * fmod(bf * t2, 1.0) - 1.0) - 1.0
					var env2 := minf(1.0, float(i) / (SR * 0.004)) \
						* (1.0 - float(i) / (s16 * 1.7) * 0.6)
					buf[bs + i] += tri * 0.22 * env2
			# hats: every 16th, accents on the beat
			for n2 in 16:
				var hs := b0 + n2 * s16
				var amp := 0.07 if n2 % 4 == 0 else 0.035
				for i in mini(int(0.012 * SR), total - hs):
					buf[hs + i] += (randf() * 2.0 - 1.0) * amp \
						* (1.0 - float(i) / (0.012 * SR))
		else:
			# PART 2 bass: syncopated 16ths walking root/octave/fifth with
			# chromatic approaches -- the triangle learns to funk
			var bpat: Array = [0, -1, 12, 0, 7, -1, 12, 5, 0, 12, -1, 7, 0, 10, 12, -1]
			for n3 in 16:
				var bp := int(bpat[n3])
				if bp == -1:
					continue
				var bf2 := base * 0.25 * pow(2.0, float(tr + bp) / 12.0)
				var bs2 := b0 + n3 * s16
				for i in mini(int(s16 * 0.9), total - bs2):
					var t3 := float(i) / SR
					var tri2 := 2.0 * absf(2.0 * fmod(bf2 * t3, 1.0) - 1.0) - 1.0
					var env3 := minf(1.0, float(i) / (SR * 0.003)) \
						* (1.0 - float(i) / (s16 * 0.9) * 0.5)
					buf[bs2 + i] += tri2 * 0.34 * env3
			# PART 2 drums: a real electro-funk kit. Two alternating bar
			# patterns, swung hats with accents and an open hat, ghost
			# snares, and every fourth bar ends in a rising tom-snare fill.
			var p2i := bar - 8
			var kick_pat: Array = [0, 7, 10] if p2i % 2 == 0 else [0, 5, 10, 13]
			var fill := p2i % 4 == 3
			for kn in kick_pat:
				var ks: int = b0 + int(kn) * s16
				for i in mini(int(0.09 * SR), total - ks):
					var tk := float(i) / SR
					buf[ks + i] += sin(TAU * (85.0 - tk * 300.0) * tk) \
						* exp(-tk * 30.0) * 0.52
			var snare_pat: Array = [4, 12] if p2i % 2 == 0 else [4, 9, 12]
			for sn in snare_pat:
				var ss: int = b0 + int(sn) * s16
				var samp := 0.3 if int(sn) != 9 else 0.1   # 9 is a ghost
				for i in mini(int(0.08 * SR), total - ss):
					buf[ss + i] += ((randf() * 2.0 - 1.0) * 0.7 \
						+ sin(TAU * 190.0 * float(i) / SR) * 0.3) \
						* exp(-float(i) / (SR * 0.02)) * samp
			for n4 in 16:
				if fill and n4 >= 12:
					continue   # the fill owns the last quarter
				# SWING: odd 16ths land a third late
				var hs2 := b0 + n4 * s16 + (int(s16 * 0.33) if n4 % 2 == 1 else 0)
				var hamp := 0.085 if n4 % 4 == 0 else (0.05 if n4 % 2 == 0 else 0.03)
				var hlen := 0.055 if (n4 == 7 and p2i % 2 == 1) else 0.012
				for i in mini(int(hlen * SR), total - hs2):
					buf[hs2 + i] += (randf() * 2.0 - 1.0) * hamp \
						* (1.0 - float(i) / (hlen * SR))
			if fill:
				# rising fill: tom, tom, snare, snare -- each hotter
				var ffreqs: Array = [140.0, 180.0, 0.0, 0.0]
				for fslot in 4:
					var fs: int = b0 + (12 + fslot) * s16
					var famp := 0.22 + 0.07 * float(fslot)
					var ffreq := float(ffreqs[fslot])
					for i in mini(int(0.07 * SR), total - fs):
						var tf := float(i) / SR
						if ffreq > 0.0:
							buf[fs + i] += sin(TAU * (ffreq - tf * 200.0) * tf) \
								* exp(-tf * 22.0) * famp * 1.6
						else:
							buf[fs + i] += ((randf() * 2.0 - 1.0) * 0.75 \
								+ sin(TAU * 200.0 * tf) * 0.25) \
								* exp(-tf * 42.0) * famp
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 24000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = total
	return wav

## EUCLID, composed instead of rolled: real maqam-style PHRASES over the
## double-harmonic scale -- fixed melodic contours with grace-note
## ornaments, long resolving tones, the tanpura drone, and a maqsum-ish
## dum-tek drum pattern. No random walk; the desert has taste.
static func _euclid_loop(seed_v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var base := 220.0
	var scale: Array = [0, 1, 4, 5, 7, 8, 11, 12]
	var beat := 60.0 / 92.0
	var barlen := int(4.0 * beat * SR)
	var total := barlen * 4
	var buf := PackedFloat32Array()
	buf.resize(total)
	# drone: root + fifth, breathing slowly
	for i in total:
		var t := float(i) / SR
		buf[i] += (sin(TAU * 110.0 * t) * 0.085 + sin(TAU * 165.0 * t) * 0.04) \
			* (0.8 + 0.2 * sin(TAU * 0.25 * t)) \
			+ (randf() * 2.0 - 1.0) * 0.012
	# phrases: (scale degree, beats). each bar is a composed line.
	var phrases: Array = [
		[[0, 0.5], [1, 0.5], [2, 1.0], [3, 0.5], [4, 1.5]],
		[[2, 0.5], [3, 0.5], [2, 0.5], [1, 0.5], [0, 2.0]],
		[[4, 0.75], [5, 0.75], [6, 0.5], [5, 1.0], [4, 1.0]],
		[[3, 0.5], [2, 0.5], [1, 0.5], [2, 0.5], [0, 2.0]]]
	for bar in 4:
		var ph: Array = phrases[bar]
		var b0 := bar * barlen
		var cursor := 0.0
		for note in ph:
			var deg := int(note[0])
			var dur_b := float(note[1])
			var f := base * pow(2.0, float(scale[deg]) / 12.0)
			var ns := b0 + int(cursor * beat * SR)
			var nd := int(dur_b * beat * SR * 0.92)
			# ornament: long notes get a quick upper-neighbour grace first
			if dur_b >= 1.0 and deg + 1 < scale.size() and rng.randf() < 0.8:
				var gf := base * pow(2.0, float(scale[deg + 1]) / 12.0)
				for i in mini(int(0.07 * SR), total - ns):
					var tg := float(i) / SR
					buf[ns + i] += (sin(TAU * gf * tg) * 0.14 \
						+ (fmod(gf * tg, 1.0) * 2.0 - 1.0) * 0.1) \
						* minf(1.0, float(i) / (SR * 0.008))
				ns += int(0.07 * SR)
				nd -= int(0.07 * SR)
			for i in mini(nd, total - ns):
				var t2 := float(i) / SR
				var vib := 1.0 + 0.012 * sin(TAU * 5.5 * t2) * minf(1.0, t2 * 4.0)
				var env := minf(1.0, float(i) / (SR * 0.02)) \
					* minf(1.0, float(nd - i) / (SR * 0.06))
				buf[ns + i] += ((fmod(f * vib * t2, 1.0) * 2.0 - 1.0) * 0.13 \
					+ sin(TAU * f * vib * t2) * 0.16) * env
			cursor += dur_b
		# maqsum-ish drum: DUM . TEK DUM . TEK . TEK across the bar
		var pat: Array = [0, -1, 1, 0, -1, 1, -1, 1]
		for e8 in 8:
			var hit := int(pat[e8])
			if hit < 0:
				continue
			var ds := b0 + int(float(e8) * 0.5 * beat * SR)
			if hit == 0:
				for i in mini(int(0.11 * SR), total - ds):
					var td := float(i) / SR
					buf[ds + i] += sin(TAU * 80.0 * td) * exp(-td * 24.0) * 0.42
			else:
				for i in mini(int(0.04 * SR), total - ds):
					buf[ds + i] += (randf() * 2.0 - 1.0) \
						* exp(-float(i) / (SR * 0.007)) * 0.16
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 24000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = total
	return wav

# ---- THE EVENT HORIZON LOG --------------------------------------------
# Listen to the black hole long enough and someone's thoughts surface --
# an old man's, unhurried, arriving in real time. He found something in
# a field once. He is not going to describe it properly, and he knows
# more than he will ever admit. Plays ONCE per world session; after the
# last line it's just the hole again.
const EH_END := 282.0
const EH_LOG: Array = [
	[13.0, "there it is again. the sound. people call it a howl. it isn't. a howl wants something. this is the sound of a thing that already has it."],
	[15.0, "i used to think you listened to a place like this to feel small. no. you listen to check whether it remembers you."],
	[23.0, "i found something once. back on earth, back when my knees were a rumor i hadn't heard yet."],
	[31.0, "a field past the east fence line. clover, mostly. bees working it like they were paid."],
	[39.0, "and in the middle of all that ordinary: a structure. i have spent forty years not describing it properly, and i will not start tonight."],
	[48.0, "it had a door the way a riddle has an answer. present. unavailable."],
	[56.0, "no hinges. i looked. of course i looked. i was young, and the young believe hinges are owed to them."],
	[65.0, "i told exactly one person. she laughed until she saw my face, and then she never asked me about it again. good woman. better than i deserved."],
	[74.0, "the metal -- i'll call it metal, it would be rude to call it what it was -- was warm on the north side. only the north side. in january."],
	[83.0, ""],
	[97.0, "hm."],
	[103.0, "funny what a sound can shake loose. i had almost managed a decade without thinking about the latch."],
	[111.0, "i never mentioned a latch before. forget i said latch."],
	[119.0, ""],
	[127.0, "these noodles are done. a man should finish his noodles before doing something foolish. that isn't wisdom, that's just order of operations."],
	[137.0, ""],
	[143.0, "alright. keys. coat. the good flashlight, not the honest one."],
	[151.0, "driving now. the road out east hasn't changed. the dark still starts at the same fence post."],
	[160.0, "i used to drive this stretch angry. now i drive it grateful. same road. the difference was never the road."],
	[169.0, "the turn's grown over. good. things that matter should be inconvenient."],
	[177.0, "walking now. clover's gone. the bees went wherever bees go when nobody holds the lease."],
	[186.0, "and there it is. lower than i remember. patient things settle."],
	[194.0, "i brought the thing i've kept in the coffee tin since before the tin had a purpose. no, i won't say. you'd only go looking for a tin."],
	[203.0, "it fits. of course it fits. it always fit. that was the whole problem."],
	[211.0, "glowing now. not bright. considerate. a light that knows about neighbors."],
	[219.0, "ah."],
	[224.0, "so that's -- hm."],
	[229.0, "...no. no, that part's mine. some things you get to keep just for being the one standing there. this is one of those."],
	[238.0, "and down it goes. slow as a sunset. the dirt just... accepts it. grass folding over like a page."],
	[247.0, "you'd never know. that's the point, i think. you were never supposed to know. i wasn't either. i just happened to be in the field."],
	[256.0, "anyway. the sky out here is very good tonight."],
	[263.0, "...you hear it, don't you. this sound. the one you tuned in for."],
	[270.0, "that's what the field sounded like. the exact moment it showed me. i've been coming out here to listen to it ever since."],
	[280.0, ""]]

static func eh_line(t: float) -> String:
	var out := ""
	for e in EH_LOG:
		if t >= float(e[0]):
			out = str(e[1])
		else:
			break
	return out

## The shadow temple's frequency: no music, no words. A slow drone,
## detuned partials, something breathing under it. Loops seamlessly.
static var _eerie_wav: AudioStreamWAV = null

static func eerie_loop() -> AudioStreamWAV:
	if _eerie_wav:
		return _eerie_wav
	var total := int(12.0 * SR)
	var buf := PackedFloat32Array()
	buf.resize(total)
	for i in total:
		var t := float(i) / SR
		var lp := float(i) / float(total) * TAU   # phase for seamless loop
		var v := sin(TAU * 55.0 * t) * 0.22 \
			+ sin(TAU * 55.7 * t) * 0.18 \
			+ sin(TAU * 82.4 * t + sin(lp) * 2.0) * 0.1 \
			+ sin(TAU * 220.0 * t) * 0.05 * (0.5 + 0.5 * sin(lp * 3.0))
		# the breathing
		v *= 0.6 + 0.4 * sin(lp * 2.0 + sin(lp * 5.0))
		# occasional whisper of filtered noise
		var wn := (randf() * 2.0 - 1.0) * 0.05 * maxf(0.0, sin(lp * 7.0) - 0.7) * 3.0
		buf[i] = v + wn
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 22000.0))
	_eerie_wav = AudioStreamWAV.new()
	_eerie_wav.format = AudioStreamWAV.FORMAT_16_BITS
	_eerie_wav.mix_rate = SR
	_eerie_wav.data = bytes
	_eerie_wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_eerie_wav.loop_end = total
	return _eerie_wav

# ------------------------------------------------------------- words

const NEWS_WHO := ["a Gary man", "an Accident local", "a Heliopolis elder",
	"a Meridian City executive", "a hamlet farmer", "two roommates",
	"a retired rail conductor", "someone's Karen", "an unnamed bench-sitter"]
const NEWS_DID := ["was chased by", "married", "sued", "befriended",
	"traded a house for", "won an argument against", "got stuck inside",
	"claims to have invented", "reported a strange noise from"]
const NEWS_WHAT := ["a vending machine", "the railway", "a permadeath apple",
	"the blue dude", "a park bench", "seventeen pigeons", "their own basement",
	"a suspicious barrel", "the concept of soup", "a caged human"]
const NEWS_TAIL := ["Authorities are aware.", "Markets reacted poorly.",
	"Neighbors describe the mood as 'a mood'.", "No further questions were taken.",
	"The bench has been cleaned.", "Officials recommend sitting down.",
	"More on this never.", "The railway declined to comment."]

static func news_line() -> String:
	var r := randi()
	match r % 5:
		0:
			return "Breaking: %s %s %s. %s" % [
				NEWS_WHO[randi() % NEWS_WHO.size()],
				NEWS_DID[randi() % NEWS_DID.size()],
				NEWS_WHAT[randi() % NEWS_WHAT.size()],
				NEWS_TAIL[randi() % NEWS_TAIL.size()]]
		1:
			return "Weather: %s with a chance of %s. Dress accordingly." % [
				["clear skies", "aurora", "meteor dust", "regular dust"][randi() % 4],
				["meteors", "UFO traffic", "more weather", "opinions"][randi() % 4]]
		2:
			return "Markets: coal %s, prisms %s. Analysts blame %s." % [
				["up", "down", "sideways"][randi() % 3],
				["glittering", "flat", "unstable"][randi() % 3],
				["the moon", "sentiment", "the noodle god", "gravity"][randi() % 4]]
		3:
			return "Rail update: the %s line is running %s." % [
				["Gary", "Accident", "Heliopolis", "Meridian"][randi() % 4],
				["on time", "backwards", "beautifully", "again, somehow"][randi() % 4]]
		_:
			return "And now, silence, sponsored by the sell station."

const ALIEN_BITS := ["the angles are ripening", "we have tasted your geometry",
	"your sun is adequate. ours is better. debate us",
	"the wireframe remembers being solid", "pixels are just atoms that gave up",
	"we traded our horizon for a better one", "your dude is known to us",
	"the blind planet sees more than you", "contrast is a lifestyle",
	"we count in colors you haven't earned"]

static func alien_line() -> String:
	return ALIEN_BITS[randi() % ALIEN_BITS.size()]

static func alien_profile() -> Dictionary:
	# a broken human voicebox with every dial wrong at once
	return {"base": randf_range(60.0, 520.0), "var": randf_range(0.9, 1.8),
		"wave": ["buzz", "wobble", "square", "saw"][randi() % 4],
		"rate": randf_range(0.45, 1.7), "artic": randf_range(1.2, 1.8)}

# ---- WTH TALK RADIO: a real AM station run by aliens ------------------
# Four RECURRING voices (stable profiles, so you learn who's who) doing
# actual radio: news about the local planets, call-ins, debates, weather,
# markets. Procedural, but each segment is a coherent little exchange.

const ALIEN_HOSTS: Array = [
	{"base": 320.0, "var": 0.5, "wave": "square", "rate": 1.5, "artic": 1.6},
	{"base": 95.0, "var": 0.3, "wave": "buzz", "rate": 0.85, "artic": 1.3},
	{"base": 210.0, "var": 0.9, "wave": "wobble", "rate": 1.2, "artic": 1.4},
	{"base": 150.0, "var": 0.2, "wave": "saw", "rate": 1.1, "artic": 1.7}]

const AP := ["Contrast", "Pixel", "Wireframe", "Blind", "Wobble"]
const AP_STATES := ["rotating backwards", "hoarding vertices",
	"refusing to render", "dimming on purpose", "growing a second pole",
	"leaking edges into the void", "voting to become concave",
	"broadcasting in a shape nobody licensed", "molting its skybox",
	"charging admission for sunrise"]
const AP_VERDICTS := ["stable, technically", "a fashion choice",
	"contagious", "beautiful and wrong", "above my clearance",
	"exactly what the tesselation predicted", "reversible if we hurry",
	"someone's thesis project", "legally weather now"]
const AP_REACT := ["remarkable.", "we warned them.", "the angles agree.",
	"more after the static.", "stay rendered, everyone.",
	"i need to sit on something flat.", "the phones are already glowing.",
	"file that under 'yes'."]
const AP_QUESTIONS := ["why does %s get two horizons and we get one?",
	"my shadow left. do i water the geometry?",
	"is it true the dude is real?",
	"can you eat a vertex or is that illegal?",
	"my house clipped through %s again. who do i bill?",
	"my kid keeps rendering in wireframe. is that a phase?",
	"does the sun know it's orange now? should someone tell it?",
	"i found a corner nobody owns. can i keep it?"]
const AP_ANSWERS := ["legally, yes. morally, the tesselation forbids it.",
	"your shadow is on %s now. it is happier there.",
	"the dude is real, and he is LOUD.",
	"two horizons is a tax bracket, not a blessing.",
	"bill %s. they clip everyone. it's a lifestyle.",
	"it's a phase. all geometry is a phase.",
	"finders keepers applies to corners. it's in the constitution.",
	"do NOT tell the sun anything. it overreacts."]
const AP_MARKET := ["up", "down", "sideways", "unrendered", "imaginary",
	"clipping through the floor", "briefly two-dimensional"]
const AP_PHENOM := ["a second sunrise", "backwards rain",
	"a polygon shortage", "silence in the low frequencies",
	"a brand-new corner", "seventeen missing vertices",
	"fog with opinions", "an unlicensed eclipse"]
const AP_PRODUCTS := ["edge polish", "horizon insurance", "vertex glue",
	"premium darkness", "certified round corners", "artisanal shadows",
	"low-poly comfort blankets"]
const AP_SLOGANS := ["now with fewer dimensions.",
	"because your geometry deserves it.", "as endorsed by the sun. allegedly.",
	"side effects include existing.", "it just renders RIGHT."]
const AP_SPORTS := ["the tesselation finals", "orbit racing",
	"competitive shadow tug", "freestyle rotation"]
const AP_FOIL := ["i am wearing the foil cone until the listening stops.",
	"the foil cone stays ON this cycle. no debate.",
	"foil is not fear. foil is fashion with boundaries.",
	"i lined my studio with foil and my thoughts are MINE now."]
const AP_FOURTH := [
	["instruments say someone OUTSIDE the system is decoding this signal. again.",
		"hello, decoder. we count your clicks too.",
		"statistically it is one (1) guy with a satellite dish."],
	["do you ever feel like the static is... reading us?",
		"every broadcast, something out there writes our words down.",
		"then let's give it something to write. hello, dish person."],
	["a listener who is not from here has tuned in.",
		"we see the beam. it comes from the little blue-adjacent rock.",
		"wave at the sky, everyone. professionally."]]

# anti-repeat memory: recently used lines and topics stay off the air
static var _ax_recent: Array = []
static var _ax_topics: Array = []

static func _ax_fresh(arr: Array) -> String:
	for attempt in 4:
		var c := str(arr[randi() % arr.size()])
		if not _ax_recent.has(c):
			_ax_recent.append(c)
			if _ax_recent.size() > 30:
				_ax_recent.pop_front()
			return c
	return str(arr[randi() % arr.size()])

## One coherent talk-radio segment: [[voice_index, line], ...]
## Topics rotate (no repeats back-to-back), lines assemble from parts,
## and RARELY the hosts notice they're being decoded -- or someone just
## quietly announces the foil cone. Unscheduled. Heartfelt.
static func alien_exchange() -> Array:
	var p: String = AP[randi() % AP.size()]
	var p2: String = AP[randi() % AP.size()]
	var topic := randi() % 9
	for attempt in 6:
		if not _ax_topics.has(topic):
			break
		topic = randi() % 9
	_ax_topics.append(topic)
	if _ax_topics.size() > 3:
		_ax_topics.pop_front()
	var out: Array = []
	match topic:
		0:
			out = [[0, "this hour: %s. what do we know?" % p],
				[3, "%s has been %s for three cycles. the geometry is %s." % [
					p, _ax_fresh(AP_STATES), _ax_fresh(AP_VERDICTS)]],
				[0, _ax_fresh(AP_REACT)]]
		1:
			out = [[0, "caller from %s, you're on the air." % p],
				[2, _ax_fresh(AP_QUESTIONS) % p2],
				[1, _ax_fresh(AP_ANSWERS) % p2],
				[0, "next caller. keep it euclidean."]]
		2:
			out = [[1, "resolution is a right."],
				[3, "resolution is a PRIVILEGE. %s proves it." % p],
				[0, "strong words. the phones are melting."]]
		3:
			out = [[0, "weather across the system."],
				[1, "%s: %s overnight. %s: %s by dawn. the sun: orange again. nobody asked it to be." % [
					p, _ax_fresh(AP_PHENOM), p2, _ax_fresh(AP_PHENOM)]]]
		4:
			out = [[3, "vertex futures %s. edge liquidity %s. the wireframe index closed %s." % [
					_ax_fresh(AP_MARKET), _ax_fresh(AP_MARKET), _ax_fresh(AP_MARKET)]],
				[0, "you heard it here. probably."]]
		5:
			out = [[0, "sports. %s hosted %s." % [p, _ax_fresh(AP_SPORTS)]],
				[3, "%s won by %d angles. %s demanded a re-measure." % [
					p2, 1 + randi() % 89, p]],
				[0, "tradition."]]
		6:
			out = [[0, "a word from our sponsor."],
				[1, "%s. %s" % [_ax_fresh(AP_PRODUCTS).capitalize(),
					_ax_fresh(AP_SLOGANS)]],
				[0, "we legally had to air that."]]
		7:
			out = [[0, "history minute. %d cycles ago today:" % (100 + randi() % 900)],
				[3, "%s %s %s. we still feel it." % [p,
					["annexed", "out-rendered", "apologized to",
						"traded shadows with", "declared war on the concept of"][randi() % 5],
					p2 if randi() % 2 == 0 else "the number four"]]]
		_:
			# the FOURTH WALL segment: they know. they've always known.
			var fw: Array = AP_FOURTH[randi() % AP_FOURTH.size()]
			out = [[0, str(fw[0])], [1, str(fw[1])], [3, str(fw[2])]]
	# an unscheduled THOUGHT: rarely, someone just needs the foil cone
	if randi() % 12 == 0:
		out.append([2, _ax_fresh(AP_FOIL)])
	return out

## The whole segment as one broadcast: each voice rendered with its own
## stable profile, short gaps between turns, AM-station pacing.
static func alien_broadcast() -> AudioStreamWAV:
	return alien_render(alien_exchange())

const ALIEN_RUNES := "ΔΘΛΞΠΣΦΨΩЖИДЯБϞϟ"

## Subtitles for the exchange -- with a share of the letters swapped for
## alien glyphs, deterministically, like the translator is only mostly
## working.
static func rune_text(ex: Array) -> String:
	var full := ""
	for turn in ex:
		full += "[" + str(int(turn[0]) + 1) + "] " + str(turn[1]) + "\n"
	var out := ""
	for i in full.length():
		var ch := full[i]
		if ch >= "a" and ch <= "z" and (i * 7 + ch.unicode_at(0)) % 5 < 2:
			out += ALIEN_RUNES[(i + ch.unicode_at(0)) % ALIEN_RUNES.length()]
		else:
			out += ch
	return out.strip_edges()

static func alien_render(ex: Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	var gap := PackedByteArray()
	gap.resize(int(SR * 0.45) * 2)
	for turn in ex:
		var w := HumanVoice.render(str(turn[1]), ALIEN_HOSTS[int(turn[0])])
		if w != null:
			bytes.append_array(w.data)
			bytes.append_array(gap)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.data = bytes
	return wav

const NOODLE_BITS := ["the sauce remembers.", "every ring you take, I count.",
	"boil. the universe is a pot.", "al dente is a covenant.",
	"I watched you sell the semicircles.", "wrath keeps. like leftovers.",
	"the fork is coming.", "strain your deeds.", "I am the hunger above."]

const RICK_BITS := ["this station will never let you down. contractually.",
	"you tuned this in yourself. remember that.",
	"we are committed to you. fully. forever. legally.",
	"no other station would do this to you.",
	"you know the rules of this frequency. so do we.",
	"still here? incredible. so are we. always."]

static func rick_line() -> String:
	return RICK_BITS[randi() % RICK_BITS.size()]

static var _rick_wav: AudioStreamWAV = null

## RICK FM's flagship: the hook, sung by a perfectly autotuned synthetic
## man over a committed little band. Bass on eighths, pad chords, hats,
## backbeat snare -- and a voice pitched EXACTLY to the melody, zero
## wobble allowed. That's the autotune promise.
static func rick_song() -> AudioStreamWAV:
	if _rick_wav:
		return _rick_wav
	var beat := 60.0 / 113.0
	var total := int(8.0 * 4.0 * beat * SR)
	var buf := PackedFloat32Array()
	buf.resize(total)
	# --- the band ---
	var roots: Array = [131.0, 147.0, 165.0, 147.0]   # C D Em D
	var third: Array = [1.26, 1.26, 1.19, 1.26]       # maj maj MIN maj
	for bar in 8:
		var r: float = roots[bar % 4]
		var t3: float = third[bar % 4]
		var b0 := int(float(bar) * 4.0 * beat * SR)
		for e8 in 8:
			var st := b0 + int(float(e8) * 0.5 * beat * SR)
			var dur := int(0.4 * beat * SR)
			for i in mini(dur, total - st):
				var env := minf(1.0, float(i) / (SR * 0.005)) * (1.0 - float(i) / float(dur))
				buf[st + i] += (0.28 if fmod(r * 0.5 * float(i) / SR, 1.0) < 0.5 else -0.28) * env * 0.5
		var bl := int(4.0 * beat * SR)
		for i in mini(bl, total - b0):
			var t2 := float(i) / SR
			var env2 := minf(1.0, float(i) / (SR * 0.03)) * minf(1.0, float(bl - i) / (SR * 0.06))
			buf[b0 + i] += (sin(TAU * r * 2.0 * t2) + sin(TAU * r * 2.0 * t3 * t2) \
				+ sin(TAU * r * 3.0 * t2)) * 0.05 * env2
		for q in 4:
			var hs := b0 + int((float(q) + 0.5) * beat * SR)
			for i in mini(int(0.03 * SR), total - hs):
				buf[hs + i] += (randf() * 2.0 - 1.0) * 0.11 * (1.0 - float(i) / (0.03 * SR))
			if q % 2 == 1:
				var sn := b0 + int(float(q) * beat * SR)
				for i in mini(int(0.09 * SR), total - sn):
					buf[sn + i] += (randf() * 2.0 - 1.0) * 0.19 * (1.0 - float(i) / (0.09 * SR))
	# --- the voice: [syllable, pitch Hz, start beat, length beats] ---
	# 16th-note pickup ne-ver-gon-na, then the payoff spread out with a
	# tiny breath between GIVE. YOU. UP. -- and the second line follows
	# sooner, like the record
	var up_line: Array = [["neh", 294.0, 0.0, 0.25], ["vur", 330.0, 0.25, 0.25],
		["gon", 392.0, 0.5, 0.25], ["nuh", 330.0, 0.75, 0.25],
		["giv", 494.0, 1.05, 0.42], ["yoo", 440.0, 1.65, 0.42], ["up", 392.0, 2.25, 1.5]]
	var down_line: Array = [["neh", 294.0, 0.0, 0.25], ["vur", 330.0, 0.25, 0.25],
		["gon", 392.0, 0.5, 0.25], ["nuh", 330.0, 0.75, 0.25],
		["let", 440.0, 1.05, 0.42], ["yoo", 392.0, 1.65, 0.42], ["doun", 294.0, 2.25, 1.5]]
	for rep in [0.0, 4.0]:
		for ph in [[rep, up_line], [rep + 1.75, down_line]]:
			var bar_off: float = float(ph[0])
			for syl in ph[1]:
				var word: String = str(syl[0])
				var hz: float = float(syl[1])
				var sb: float = float(syl[2])
				var lb: float = float(syl[3])
				var wav0: AudioStreamWAV = HumanVoice.render(word,
					{"base": hz, "var": 0.0, "wave": "sine", "rate": 1.2,
					"artic": 1.3, "autotune": true})
				var d0 := wav0.data
				var n0 := d0.size() / 2
				var start := int((bar_off * 4.0 + sb) * beat * SR)
				if word == "doun":
					# the Down~ : held LONGER, pitch sagging as it goes.
					# variable-rate read bends it flat-ward; the vowel tail
					# loops so the hold keeps singing instead of cutting.
					var cap2 := mini(int(2.2 * beat * SR), total - start)
					var vtail := int(float(n0) * 0.6)
					var vlen := maxi(1, n0 - vtail)
					var ph2 := 0.0
					for i in cap2:
						var frac := float(i) / float(cap2)
						ph2 += 1.0 - 0.14 * frac
						var si := int(ph2)
						if si >= n0:
							si = vtail + (si - n0) % vlen
						var fade2 := minf(1.0, float(cap2 - i) / (SR * 0.07))
						buf[start + i] += d0.decode_s16(si * 2) / 32768.0 * 0.95 * fade2
					continue
				var cap := mini(n0, int(lb * beat * SR * 1.15))
				for i in mini(cap, total - start):
					var fade := minf(1.0, float(cap - i) / (SR * 0.02))
					buf[start + i] += d0.decode_s16(i * 2) / 32768.0 * 0.95 * fade
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 24000.0))
	_rick_wav = AudioStreamWAV.new()
	_rick_wav.format = AudioStreamWAV.FORMAT_16_BITS
	_rick_wav.mix_rate = SR
	_rick_wav.data = bytes
	_rick_wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_rick_wav.loop_end = total
	return _rick_wav

static func noodle_line() -> String:
	return NOODLE_BITS[randi() % NOODLE_BITS.size()]

const ELDRITCH_WORDS := ["zholgoth", "vraxulemn", "othrunquay", "melgrahz"]

## THE SAUCE TAPE: the pronouncements, in order, RHYMING -- a rap. Each
## line is its own eldritch render (one voice at a time), snapped to the
## bar grid over a continuous thump. "the fork." gets a whole bar of
## just beat before "is coming." lands. That pause IS the hook.
const SAUCE_VERSE: Array = [
	"the sauce remembers.", "every ring.",
	"I count the coins.", "I count the king.",
	"boil on.", "the universe is a pot.",
	"al dente is a covenant.", "you forgot.",
	"I watched you sell the semicircles, dude.",
	"wrath keeps like leftovers.", "barely food.",
	"strain your deeds.", "the broth runs thin.",
	"the hunger above is tuning in.",
	"the fork.", "is coming.",
	"zholgoth.", "vraxulemn.", "othrunquay.", "melgrahz."]

## Part two: the god stops pausing and TALKS -- dense couplets, same
## rhyme discipline, beat unchanged underneath.
const SAUCE_VERSE2: Array = [
	"I stirred the void and called it dinner. every orbit, every sinner.",
	"you built machines to count your money. the strainer sees you. that isn't funny.",
	"planets simmer where I set them. rings go missing. I don't forget them.",
	"pray al dente, live al dente. the pot is patient. the pot is plenty.",
	"when the timer rings its final ring,",
	"the fork descends on everything."]

## The autotuned moments: hook lines pinned to notes of a minor line.
const SAUCE_TUNED := {
	"the fork.": 175.0, "is coming.": 165.0,
	"zholgoth.": 175.0, "vraxulemn.": 170.0,
	"othrunquay.": 160.0, "melgrahz.": 150.0,
	"when the timer rings its final ring,": 175.0,
	"the fork descends on everything.": 160.0}

static var _sauce_wav: AudioStreamWAV = null
static var sauce_cues: Array = []   # [start_seconds, line] over the tape
static var sauce_len: float = 1.0

## SPAGHETTIFY: what falling into TIN 618 does to a sentence. Letters
## s t r e t c h  a p a r t  down the line (tidal forces), and the soft
## ones elongate. Plain characters only -- renders everywhere, no lag.
static func spaghettify(txt: String) -> String:
	var out := ""
	for i in txt.length():
		var c := txt[i]
		if c == " ":
			out += "  "
			continue
		var h := (i * 31 + c.unicode_at(0)) % 7
		var reps := 1 + (h % 3 if c in "aeioumnrls" else h % 2)
		for k in reps:
			out += c
		out += " ".repeat(1 + mini(i / 8, 3))
	return out.strip_edges()

## A mild single-tap echo: presence intact, space added.
static func _light_echo(src: AudioStreamWAV) -> AudioStreamWAV:
	var d := src.data
	var n := d.size() / 2
	var total := n + int(SR * 0.5)
	var buf := PackedFloat32Array()
	buf.resize(total)
	for i in n:
		buf[i] = d.decode_s16(i * 2) / 32768.0
	var off := int(SR * 0.21)
	for i in range(total - 1, off - 1, -1):
		buf[i] += buf[i - off] * 0.22
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 24000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.data = bytes
	return wav

static func noodle_broadcast() -> AudioStreamWAV:
	if _sauce_wav:
		return _sauce_wav
	var beat := 0.7   # ~86 bpm. the god has flow.
	var barlen := int(beat * 2.0 * SR)
	var segs: Array = []   # [start_sample, voice bytes]
	var pos := 0
	# TWO voices per line, same monotone god: the full eldritch render
	# pushed back as texture, and a clearer take with a light echo on
	# top so the words actually land
	sauce_cues.clear()
	for ln in SAUCE_VERSE + SAUCE_VERSE2:
		if str(ln) == "":
			pos += barlen   # a rest: the beat carries the bar alone
			continue
		sauce_cues.append([float(pos) / float(SR), str(ln)])
		# pronunciation pass: the engine's magic-e rule says "al dent";
		# the god says "al den-tay". subtitles keep the true spelling.
		var say := str(ln).replace("dente", "dentay")
		var w := eldritch(HumanVoice.render(say, noodle_profile()), false)
		# the GROWL: the god's old saw throat, kept quiet under the mix
		var wg := HumanVoice.render(say,
			{"base": 118.0, "var": 0.12, "wave": "saw", "rate": 0.9, "artic": 1.7})
		# the clear take is fully DRY -- any echo on it and the words go.
		# hook lines get a light AUTOTUNE: pinned to a note, zero drift
		var cprof := {"base": 165.0, "var": 0.15, "wave": "sine",
			"rate": 1.0, "artic": 1.85}
		if SAUCE_TUNED.has(str(ln)):
			cprof = {"base": float(SAUCE_TUNED[str(ln)]), "var": 0.0, "wave": "sine",
				"rate": 1.0, "artic": 1.85, "autotune": true}
		var wc := HumanVoice.render(say, cprof)
		segs.append([pos, w.data, wc.data, wg.data])
		var nlen: int = maxi(w.data.size(), maxi(wc.data.size(), wg.data.size())) / 2
		var bars := maxi(1, int(ceil(float(nlen) / float(barlen))))
		pos += bars * barlen
	var total := pos + barlen   # one extra bar for the turnaround
	var buf := PackedFloat32Array()
	buf.resize(total)
	for sg in segs:
		var st: int = sg[0]
		var pd: PackedByteArray = sg[1]
		for i in mini(pd.size() / 2, total - st):
			buf[st + i] += pd.decode_s16(i * 2) / 32768.0 * 0.38
		var pg: PackedByteArray = sg[3]
		for i in mini(pg.size() / 2, total - st):
			buf[st + i] += pg.decode_s16(i * 2) / 32768.0 * 0.28
		var pc: PackedByteArray = sg[2]
		for i in mini(pc.size() / 2, total - st):
			buf[st + i] += pc.decode_s16(i * 2) / 32768.0 * 1.0
	# sidechain the CONTINUOUS beat under the assembled verse
	var env := PackedFloat32Array()
	env.resize(total)
	var epk := 0.0
	for i in total:
		epk = maxf(epk * 0.9995, absf(buf[i]))
		env[i] = epk
	# the beat gets its own buffer so it can carry REVERB without
	# smearing the voices
	var bbuf := PackedFloat32Array()
	bbuf.resize(total)
	var bi := 0
	while bi * barlen < total:
		var b0 := bi * barlen
		for i in mini(int(0.16 * SR), total - b0):
			var tb := float(i) / SR
			var duck := clampf(1.0 - env[b0 + i] * 4.0, 0.15, 1.0)
			bbuf[b0 + i] += sin(TAU * 52.0 * tb) * exp(-tb * 14.0) * 1.5 * duck
		var toff := b0 + int(float(barlen) * 0.5)
		for i in mini(int(0.05 * SR), total - toff):
			var duck2 := clampf(1.0 - env[toff + i] * 4.0, 0.15, 1.0)
			bbuf[toff + i] += (randf() * 2.0 - 1.0) * exp(-float(i) / (SR * 0.01)) * 0.38 * duck2
		bi += 1
	# the TURNAROUND: a bar-long reverse-cymbal swell that crests exactly
	# on the loop point, sucking the song back to the top
	var swell := total - barlen
	for i in barlen:
		var k := float(i) / float(barlen)
		var ts := float(i) / SR
		bbuf[swell + i] += (randf() * 2.0 - 1.0) * pow(k, 2.6) * 0.5 \
			+ (sin(TAU * 3800.0 * ts) + sin(TAU * 5230.0 * ts)) * pow(k, 3.2) * 0.04
	var boff := int(SR * 0.29)
	for i in range(total - 1, boff - 1, -1):
		bbuf[i] += bbuf[i - boff] * 0.35
	for i in total:
		buf[i] += bbuf[i]
	# the DRONES: bar-synced, walking the rap's dark line -- i, i, bIII,
	# bVII under the monotone. Each bar breathes in and out (no clicks).
	var droots: Array = [55.0, 55.0, 65.41, 49.0]
	var nbars := int(ceil(float(total) / float(barlen)))
	for bi2 in nbars:
		var f0 := float(droots[bi2 % droots.size()])
		var b2 := bi2 * barlen
		for i in mini(barlen, total - b2):
			var td := float(i) / SR
			var denv := sin(PI * float(i) / float(barlen))
			buf[b2 + i] += (sin(TAU * f0 * td) * 0.3 \
				+ sin(TAU * (f0 + 0.4) * td) * 0.2 \
				+ sin(TAU * f0 * 1.5 * td) * 0.13 \
				+ sin(TAU * f0 * 2.0 * td) * 0.17 \
				+ sin(TAU * (f0 * 2.0 + 0.6) * td) * 0.11 \
				+ sin(TAU * f0 * 3.0 * td) * 0.07) * denv
	var peak := 0.001
	for i in total:
		peak = maxf(peak, absf(buf[i]))
	var g := minf(1.2, 0.95 / peak)
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 24000.0))
	_sauce_wav = AudioStreamWAV.new()
	_sauce_wav.format = AudioStreamWAV.FORMAT_16_BITS
	_sauce_wav.mix_rate = SR
	_sauce_wav.data = bytes
	# the tape RESTARTS itself: the sermon never actually ends
	_sauce_wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_sauce_wav.loop_end = total
	sauce_len = float(total) / float(SR)
	return _sauce_wav

static func noodle_profile() -> Dictionary:
	return {"base": 85.0, "var": 0.25, "wave": "saw", "rate": 0.62, "artic": 1.1}

## The noodle god does not have a voice. It has interference shaped like
## one: an octave-down shadow, a sharp-detuned double, something reading
## the words BACKWARDS underneath, ring-mod shimmer, a boiling sub-drone,
## and an echo tail that doesn't want to stop.
static func eldritch(src: AudioStreamWAV, with_beat: bool = true) -> AudioStreamWAV:
	var d := src.data
	var n := d.size() / 2
	var total := n + int(SR * 1.1)
	var buf := PackedFloat32Array()
	buf.resize(total)
	for i in total:
		var v := 0.0
		if i < n:
			v += d.decode_s16(i * 2) / 32768.0 * 0.85   # the WORDS lead
		var h := int(i * 0.5)   # the octave-down shadow, time-stretched
		if h < n:
			v += d.decode_s16(h * 2) / 32768.0 * 0.22
		var u := int(float(i) * 1.023)   # a hair sharp: chorus of one
		if u < n:
			v += d.decode_s16(u * 2) / 32768.0 * 0.16
		var r := n - 1 - int(i * 0.5)   # whispering backwards, quietly
		if r >= 0 and r < n:
			v += d.decode_s16(r * 2) / 32768.0 * 0.07
		var t := float(i) / SR
		v *= 0.85 + 0.15 * sin(TAU * 29.0 * t)      # ring-mod tremble
		v += sin(TAU * 48.0 * t) * 0.045 + sin(TAU * 48.7 * t) * 0.035   # the pot
		buf[i] = v
	# the BEAT: a slow ceremonial thump with a dry tick between, laid in
	# BEFORE the echo pass so it smears through the same feedback
	# SIDECHAIN: track the voice's envelope so the beat ducks OUT of the
	# way wherever the god is actually speaking
	if with_beat:
		var env := PackedFloat32Array()
		env.resize(total)
		var epk := 0.0
		for i in total:
			epk = maxf(epk * 0.9995, absf(buf[i]))
			env[i] = epk
		var bstep := int(SR * 1.4)
		var bi := 0
		while bi * bstep < total:
			var b0 := bi * bstep
			if bi % 2 == 0:
				for i in mini(int(0.16 * SR), total - b0):
					var tb := float(i) / SR
					var duck := clampf(1.0 - env[b0 + i] * 4.0, 0.1, 1.0)
					buf[b0 + i] += sin(TAU * 52.0 * tb) * exp(-tb * 14.0) * 0.22 * duck
			else:
				var toff := b0 + int(float(bstep) * 0.5)
				for i in mini(int(0.05 * SR), total - toff):
					var duck2 := clampf(1.0 - env[toff + i] * 4.0, 0.1, 1.0)
					buf[toff + i] += (randf() * 2.0 - 1.0) * exp(-float(i) / (SR * 0.01)) * 0.05 * duck2
			bi += 1
	# feedback echoes: the words keep arriving after they've stopped
	for e in [[int(SR * 0.29), 0.3], [int(SR * 0.61), 0.15]]:
		var off := int(e[0])
		var g := float(e[1])
		for i in range(total - 1, off - 1, -1):
			buf[i] += buf[i - off] * g
	# normalize to the true peak: hard clipping here was what let the
	# beat + echo pileup swallow the voice
	var peak := 0.001
	for i in total:
		peak = maxf(peak, absf(buf[i]))
	var g := minf(1.2, 0.95 / peak)
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 24000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.data = bytes
	return wav

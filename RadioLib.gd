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
	if kind == "abyss":
		var wavn := _abyss_loop(seed_v)
		_music_cache[key] = wavn
		return wavn
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
	if kind == "lava" or kind == "volcanic":
		# SANUS: the fire is in the band, and you can HEAR it. Roar bed
		# (lp-filtered noise, breathing), deep 46Hz pulse, real crackle
		# pops, and slow flame whooshes -- star-crackle DNA, hotter.
		var frng := RandomNumberGenerator.new()
		frng.seed = seed_v + 77
		var lpn := 0.0
		for i in total:
			var t3 := float(i) / SR
			lpn += ((frng.randf() * 2.0 - 1.0) - lpn) * 0.06
			buf[i] += lpn * 0.95 * (0.65 + 0.35 * sin(TAU * 0.35 * t3)) \
				+ sin(TAU * 46.0 * t3) * 0.12 * (0.6 + 0.4 * sin(TAU * 0.21 * t3 + 1.7))
		# the star-station HOWL: singing inharmonic partials with slow
		# crossing swells, pitched low and molten. Frequencies snapped to
		# whole cycles per loop so the seam stays silent.
		var dur := float(total) / SR
		var f0 := frng.randf_range(220.0, 420.0)
		var hphases: Array = []
		for k in 4:
			hphases.append(frng.randf() * TAU)
		var hparts: Array = [1.0, 2.76, 4.07, 5.43]
		var hfreqs: Array = []
		for k2 in hparts.size():
			hfreqs.append(roundf(f0 * float(hparts[k2]) * dur) / dur)
		for i in total:
			var t4 := float(i) / SR
			var lp2 := float(i) / float(total) * TAU
			var hv := 0.0
			for k3 in hfreqs.size():
				var am := 0.5 + 0.5 * sin(lp2 * float(k3 + 1) + float(hphases[k3]))
				hv += sin(TAU * float(hfreqs[k3]) * t4) * 0.07 * am
			buf[i] += hv
		# whooshes: six slow gusts of flame across the loop
		var wlen := int(0.6 * SR)
		for wsh in 6:
			var wst := frng.randi() % (total - wlen)
			var wlp := 0.0
			for j3 in wlen:
				wlp += ((frng.randf() * 2.0 - 1.0) - wlp) * 0.12
				var wenv := sin(PI * float(j3) / float(wlen))
				buf[wst + j3] += wlp * 0.5 * wenv * wenv
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

static var _bh_presence_wav: AudioStreamWAV = null

## The hole IN PERSON: the radio wail pitched down into god register
## (voices an octave and a half deep, slower clocks), with layered
## drones under it -- a beating sub root, a bare fifth, a slow-breathing
## pressure pulse. What the dish politely calls EVENT HORIZON.
static func bh_presence() -> AudioStreamWAV:
	if _bh_presence_wav:
		return _bh_presence_wav
	var total := int(22.0 * SR)
	var render := int(25.0 * SR)
	var buf := PackedFloat32Array()
	buf.resize(render)
	# one voice sings the octave ABOVE, one hums the octave BELOW,
	# the middle three stay put -- the chorus spreads three octaves
	var voices: Array = [
		[55.0, 0.5, 0.9, 0.0], [130.8, 0.7, 0.35, 2.1], [349.2, 0.4, 1.2, 4.0],
		[233.1, 0.6, 0.7, 1.0], [87.3, 0.3, 1.5, 3.3]]
	for v in voices:
		var f0: float = v[0]
		var r1: float = v[1]
		var r2: float = v[2]
		var ph0: float = v[3]
		var phase := 0.0
		for i in render:
			var t := float(i) / SR
			var lp := t / 22.0 * TAU
			var bend := 1.0 + 0.07 * sin(lp * r1 + ph0) \
				+ 0.035 * sin(lp * r2 * 1.9 + ph0 * 2.0)
			phase += TAU * f0 * bend / SR
			var amp := 0.15 * (0.5 + 0.5 * sin(lp * r2 + ph0 * 3.0))
			buf[i] += (sin(phase) + 0.4 * sin(phase * 2.0)) * amp
	# the drone stack: beating sub root, bare fifth, breathing pressure
	for i in render:
		var t2 := float(i) / SR
		buf[i] += (sin(TAU * 55.0 * t2) + sin(TAU * 55.4 * t2)) * 0.11 \
			+ sin(TAU * 82.4 * t2) * 0.07 * (0.6 + 0.4 * sin(TAU * 0.09 * t2 + 2.0)) \
			+ sin(TAU * 41.2 * t2) * 0.08 * (0.5 + 0.5 * sin(TAU * 0.045 * t2)) \
			+ sin(TAU * 311.0 * t2) * 0.02 \
			* (0.5 + 0.5 * sin(TAU * 0.21 * t2)) * (0.6 + 0.4 * sin(TAU * 5.0 * t2)) \
			+ (randf() * 2.0 - 1.0) * 0.012
	var out := PackedFloat32Array()
	out.resize(total)
	var xf := render - total
	for i in total:
		var v2 := buf[i]
		if i < xf:
			var k := float(i) / float(xf)
			v2 = buf[total + i] * (1.0 - k) + buf[i] * k
		out[i] = v2
	_bh_presence_wav = _encode_loop(out, total, "_bhp")
	return _bh_presence_wav

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
			# part one keeps it simple: JUST a clean backbeat snare
			for sn1 in [4, 12]:
				var ss1: int = b0 + int(sn1) * s16
				for i in mini(int(0.14 * SR), total - ss1):
					buf[ss1 + i] += ((randf() * 2.0 - 1.0) * 0.7 \
						+ sin(TAU * 195.0 * float(i) / SR) * 0.3) \
						* exp(-float(i) / (SR * 0.035)) * 0.4
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
			# PART 2 drums: an actually complicated kit. Four rotating
			# syncopated kick patterns, backbeat snares with a GHOST
			# NETWORK and flams, swung velocity hats with 32nd-note
			# RATCHETS and open-hat pushes, syncopated toms on odd bars,
			# and every fourth bar ends in a rising cascade fill.
			var p2i := bar - 8
			var kick_pat: Array = [[0, 6, 10], [0, 3, 6, 11, 14],
				[0, 7, 8, 10], [0, 5, 10, 12, 13]][p2i % 4]
			var fill := p2i % 4 == 3
			for kn in kick_pat:
				var ks: int = b0 + int(kn) * s16
				for i in mini(int(0.16 * SR), total - ks):
					var tk := float(i) / SR
					buf[ks + i] += sin(TAU * (85.0 - tk * 300.0) * tk) \
						* exp(-tk * 16.0) * 1.0
			# snares: backbeat + a shifting web of ghosts + occasional flam
			for sn in [4, 12]:
				var ss: int = b0 + int(sn) * s16
				for i in mini(int(0.18 * SR), total - ss):
					buf[ss + i] += ((randf() * 2.0 - 1.0) * 0.7 \
						+ sin(TAU * 190.0 * float(i) / SR) * 0.3) \
						* exp(-float(i) / (SR * 0.045)) * 0.7
				if int(sn) == 12 and rng.randf() < 0.5:
					var fs2: int = ss + int(0.03 * SR)   # the FLAM
					for i in mini(int(0.1 * SR), total - fs2):
						buf[fs2 + i] += (randf() * 2.0 - 1.0) \
							* exp(-float(i) / (SR * 0.03)) * 0.4
			for gn in [[3, 0.09], [7, 0.11], [9, 0.08], [11, 0.07], [15, 0.1]]:
				if rng.randf() < 0.55:
					var gs: int = b0 + int(gn[0]) * s16
					for i in mini(int(0.08 * SR), total - gs):
						buf[gs + i] += (randf() * 2.0 - 1.0) \
							* exp(-float(i) / (SR * 0.025)) * float(gn[1]) * 2.4
			# toms answer on odd bars: syncopated two-note figures
			if p2i % 2 == 1:
				for tspec in [[11, 150.0], [13, 118.0]]:
					var ts2: int = b0 + int(tspec[0]) * s16
					for i in mini(int(0.14 * SR), total - ts2):
						var tt3 := float(i) / SR
						buf[ts2 + i] += sin(TAU * (float(tspec[1]) - tt3 * 160.0) * tt3) \
							* exp(-tt3 * 14.0) * 0.6
			for n4 in 16:
				if fill and n4 >= 12:
					continue   # the fill owns the last quarter
				# SWING: odd 16ths land a third late
				var hs2 := b0 + n4 * s16 + (int(s16 * 0.33) if n4 % 2 == 1 else 0)
				var hamp := 0.16 if n4 % 4 == 0 else (0.1 if n4 % 2 == 0 else 0.06)
				var hlen := 0.1 if (n4 == 7 and p2i % 2 == 1) else 0.016
				for i in mini(int(hlen * SR), total - hs2):
					buf[hs2 + i] += (randf() * 2.0 - 1.0) * hamp \
						* (1.0 - float(i) / (hlen * SR))
				# RATCHET: sometimes a 16th bursts into a 32nd-note roll
				if rng.randf() < 0.12:
					for rk in 3:
						var rs2: int = hs2 + (rk + 1) * s16 / 4
						var ramp2 := hamp * (0.8 - 0.2 * float(rk))
						for i in mini(int(0.008 * SR), total - rs2):
							buf[rs2 + i] += (randf() * 2.0 - 1.0) * ramp2 \
								* (1.0 - float(i) / (0.008 * SR))
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
	# normalize: the hot kit was clipping into mush, which read as QUIET
	var peak := 0.001
	for i in total:
		peak = maxf(peak, absf(buf[i]))
	var g2 := minf(1.4, 0.95 / peak)
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i] * g2, -1.0, 1.0) * 24000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = total
	return wav

## NEPTUNE: deep-sea documentary ambience. Pressure-drone underneath,
## two lush chords breathing into each other, WHALE CALLS -- real pitch
## glides with vibrato, phase-accumulated so they bend smoothly -- and a
## tiny sonar ping with its own echo. Blue planet, blue sound.
static func _abyss_loop(seed_v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var total := int(20.0 * SR)
	var buf := PackedFloat32Array()
	buf.resize(total)
	# the pressure: sub drone breathing once per loop
	for i in total:
		var t := float(i) / SR
		var lp := float(i) / float(total) * TAU
		buf[i] += sin(TAU * 49.0 * t) * 0.13 * (0.7 + 0.3 * sin(lp)) \
			+ (randf() * 2.0 - 1.0) * 0.012
	# two chords breathing into each other: i(add9) and VI(maj7)
	var half := total / 2
	var chords: Array = [[0, 3, 7, 14], [-4, 3, 8, 15]]
	for ci in 2:
		var ch: Array = chords[ci]
		var c0 := ci * half
		for semi in ch:
			var f := 98.0 * pow(2.0, float(semi) / 12.0)
			for i in mini(half + int(SR), total - c0):
				var t2 := float(i) / SR
				var env := sin(PI * float(i) / float(half + SR))
				buf[c0 + i] += (sin(TAU * f * t2) + 0.3 * sin(TAU * f * 2.0 * t2)) \
					* 0.05 * env * env
	# WHALES: three calls, each a smooth pitch bend with slow vibrato
	for wc in 3:
		var start := int(float(wc) * 6.5 * SR + rng.randf_range(0.0, 1.5) * SR)
		var dur := int(rng.randf_range(1.6, 2.6) * SR)
		var f1 := rng.randf_range(180.0, 260.0)
		var f2 := f1 * rng.randf_range(0.55, 0.8)
		if rng.randf() < 0.4:
			f2 = f1 * rng.randf_range(1.3, 1.6)   # some calls rise
		var phase := 0.0
		for i in mini(dur, total - start):
			var k := float(i) / float(dur)
			var fr := lerpf(f1, f2, k * k)
			fr *= 1.0 + 0.015 * sin(TAU * 4.0 * float(i) / SR)
			phase += TAU * fr / SR
			var env := sin(PI * k)
			buf[start + i] += (sin(phase) + 0.4 * sin(phase * 2.0)) * 0.16 * env * env
	# sonar: a tiny ping and its lonelier echo, twice a loop
	for pn in 2:
		var ps := int((4.0 + float(pn) * 10.0) * SR)
		for eo in [[0, 0.09], [int(0.8 * SR), 0.04]]:
			var pstart: int = ps + int(eo[0])
			for i in mini(int(0.25 * SR), total - pstart):
				var t3 := float(i) / SR
				buf[pstart + i] += sin(TAU * 1180.0 * t3) * float(eo[1]) * exp(-t3 * 14.0)
	return _encode_loop(buf, total, "")

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
const EH_END := 317.0
const EH_LOG: Array = [
	[13.0, "there it is again. the sound. people call it a howl. it isn't. a howl wants something. this is the sound of a thing that already has it."],
	[23.0, "i used to think you listened to a place like this to feel small. no. you listen to check whether it remembers you."],
	[32.0, "i found something once. back on earth, back when my knees were a rumor i hadn't heard yet."],
	[41.0, "a field past the east fence line. clover, mostly. bees working it like they were paid."],
	[50.0, "and in the middle of all that ordinary: a structure. i have spent forty years not describing it properly, and i will not start tonight."],
	[61.0, "it had a door the way a riddle has an answer. present. unavailable."],
	[69.0, "no hinges. i looked. of course i looked. i was young, and the young believe hinges are owed to them."],
	[79.0, "i told exactly one person. she laughed until she saw my face, and then she never asked me about it again. good woman. better than i deserved."],
	[90.0, "the metal -- i'll call it metal, it would be rude to call it what it was -- was warm on the north side. only the north side. in january."],
	[101.0, "..."],
	[115.0, "hm."],
	[121.0, "funny what a sound can shake loose. i had almost managed a decade without thinking about the latch."],
	[131.0, "i never mentioned a latch before. forget i said latch."],
	[139.0, ""],
	[147.0, "these noodles are done. a man should finish his noodles before doing something foolish. that isn't wisdom, that's just order of operations."],
	[157.0, ""],
	[163.0, "alright. keys. coat. the good flashlight, not the honest one."],
	[171.0, "driving now. the road out east hasn't changed. the dark still starts at the same fence post."],
	[180.0, "i used to drive this stretch angry. now i drive it grateful. same road. the difference was never the road."],
	[190.0, "the turn's grown over. good. things that matter should be inconvenient."],
	[198.0, "walking now. clover's gone. the bees went wherever bees go when nobody holds the lease."],
	[207.0, "and there it is. lower than i remember. patient things settle."],
	[215.0, "i brought the thing i've kept in the coffee tin since before the tin had a purpose. no, i won't say. you'd only go looking for a tin."],
	[226.0, "it fits. of course it fits. it always fit. that was the whole problem."],
	[235.0, "glowing now. not bright. considerate. a light that knows about neighbors."],
	[244.0, "ah."],
	[249.0, "so that's -- hm."],
	[255.0, "...no. no, that part's mine. some things you get to keep just for being the one standing there. this is one of those."],
	[266.0, "and down it goes. slow as a sunset. the dirt just... accepts it. grass folding over like a page."],
	[276.0, "you'd never know. that's the point, i think. you were never supposed to know. i wasn't either. i just happened to be in the field."],
	[287.0, "anyway. the sky out here is very good tonight."],
	[295.0, "...you hear it, don't you. this sound. the one you tuned in for."],
	[303.0, "that's what the field sounded like. the exact moment it showed me. i've been coming out here to listen to it ever since."],
	[315.0, ""]]

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
# the WIDER universe: out-system subjects the desk also covers --
# including the humans themselves as a recurring beat
const AX_FAR := ["Earth", "Jupiter", "Venus", "Mars", "the Moon",
	"Pi", "Euclid", "Crystalia", "Sanus", "Varnisol", "Xero", "Home",
	"TIN 618", "the humans"]
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
# little personality collisions: injectable mid-segment, any topic
const AX_BANTER := [
	[[0, "you're humming again."], [1, "the hum is LOAD-BEARING."]],
	[[1, "i have a chart for this."], [0, "you have a chart for everything."],
		[1, "and yet."]],
	[[2, "can i say something?"], [0, "no."], [2, "understood."]],
	[[1, "my other job is calling."], [0, "you don't have another job."],
		[1, "not with THAT attitude."]],
	[[1, "correction from earlier: everything i said stands."]],
	[[2, "is the studio spinning, or is that me?"], [1, "both. it's always both."]],
	[[0, "we are NOT doing the jingle."], [2, "we never do the jingle."],
		[0, "and morale has never been higher."]],
	[[3, "i counted the ceiling tiles during the break."],
		[1, "we don't have ceiling tiles."], [3, "i know what i counted."]],
	[[0, "producer says wrap it up."], [3, "the producer is a lamp."],
		[0, "a lamp with a SCHEDULE."]]]

const AP_FOIL := ["i am wearing the foil cone until the listening stops.",
	"the foil cone stays ON this cycle. no debate.",
	"foil is not fear. foil is fashion with boundaries.",
	"i lined my studio with foil and my thoughts are MINE now."]
# fourth wall, ROOM edition: someone is physically standing in the
# studio -- these only air for the live in-person show, never the dish
const AP_FOURTH_ROOM := [
	["the dude is in the studio right now.",
		"we see you, dude. the sofas are for you.",
		"statistically, the dude walked here on purpose."],
	["do not adjust your eyes. the dude is really standing there.",
		"hello, dude. blink twice for geometry.",
		"it came down the hole. the dude always comes down the hole."],
	["security says the dude is unarmed. mostly.",
		"dude, leave the table alone. it is load-bearing. emotionally.",
		"wave at the dude, everyone. professionally."]]

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

const AX_HUM_OPEN := [
	"the human feed is doing something again.",
	"i watched the bipeds all cycle and i need to say words about it.",
	"update from the blue-adjacent rock: the humans remain committed.",
	"you will not believe what the soft ones did during the break.",
	"my monitors flagged human activity. all of it.",
	"the ones with the removable hats are at it again."]
const AX_HUM_CLOSE := [
	"tragic. beautiful. more after these vertices.",
	"and somehow, they are winning.",
	"we will never be done studying them.",
	"and they OUTNUMBER their ladders.",
	"file it with the rest. the cabinet is full.",
	"send the anthropology drone another apology."]

const AP_HUMAN_DUMB := [
	"a human will walk PAST a ladder to fall off a cliff.",
	"they invented the meeting. then the meeting about meetings.",
	"a human once traded a working rocket for a hat. we watched.",
	"they store their food NEXT to the machine that destroys food.",
	"one of them punched a mountain today. the mountain is fine.",
	"they sleep through a third of their own lives. voluntarily.",
	"a human said 'you too' to a sunset. we have it on tape."]

# COMPOSITIONAL parts: sentences are assembled subject/verb/object/
# qualifier at air time, so almost every line broadcast is new -- while
# every part is written to make sense next to every other part.
const AX_VERBS := ["annexed", "out-rendered", "quietly measured",
	"re-zoned", "audited", "apologized to", "filed a complaint against",
	"traded shadows with", "publicly doubted", "tried to rotate",
	"sold advertising space on", "refused to acknowledge"]
const AX_OBJS := ["an entire horizon", "the concept of corners",
	"two of my best vertices", "the morning broadcast",
	"a licensed eclipse", "the far side of itself", "a load-bearing angle",
	"the intermission", "everyone's favorite meridian"]
const AX_QUALS := ["again", "on record", "without a permit",
	"during peak rendering hours", "and nobody stopped it",
	"which is legal now, apparently", "for the third cycle running",
	"in front of the interns", "citing 'vibes'"]
const AX_HEADS := ["if you ask me,", "statistically,", "off the record,",
	"and frankly,", "per the charter,", "as foretold by the fine print,"]
const AX_ADJ := ["concerning", "overdue", "geometry at its finest",
	"a fashion choice", "above my clearance", "how it starts",
	"technically beautiful", "someone's fault", "not my department"]

## One composed, sensible event sentence -- unique nearly every time.
static func _ax_sentence(p: String, p2: String) -> String:
	var subs: Array = [p, p2, "the sun", "the tesselation board",
		"my producer", "the number four"]
	var subj := str(subs[randi() % subs.size()])
	var objs: Array = AX_OBJS.duplicate()
	objs.append(p2 if p2 != subj else p)
	var obj := str(objs[randi() % objs.size()])
	if obj == subj:
		obj = "itself"
	return "%s %s %s %s." % [subj, _ax_fresh(AX_VERBS), obj, _ax_fresh(AX_QUALS)]

## A composed opinion to hang after any event.
static func _ax_opinion() -> String:
	return "%s that's %s." % [_ax_fresh(AX_HEADS), _ax_fresh(AX_ADJ)]

# CONCEPT COMPOSITION: the hosts "think of" a subject, then a DOMAIN
# (taxes, sports, crime...), then sometimes a TWIST layered on top --
# pixel + taxes + fraud -- and the segment is assembled from the parts.
# Each domain carries its own vocabulary so the result stays smart.
const AX_DOMAINS := {
	"tax": {"thing": ["the vertex levy", "shadow duty", "the horizon tithe",
			"the rendering tax", "corner registration fees"],
		"event": ["was raised by %d percent", "went missing entirely",
			"was declared imaginary", "now applies to reflections",
			"doubled overnight"],
		"react": ["the auditors are circling.", "receipts are being invented as we speak.",
			"the abacus caught fire."]},
	"sports": {"thing": ["the tesselation finals", "orbit racing",
			"competitive shadow tug", "freestyle rotation", "the angle relays"],
		"event": ["ended %d to %d", "was cancelled mid-spin",
			"set a record nobody can measure", "ran into overtime for a full cycle",
			"was won by the away geometry"],
		"react": ["fans rotated in protest.", "the referee demolecularized.",
			"tickets are now a currency."]},
	"crime": {"thing": ["a corner heist", "shadow smuggling",
			"an unlicensed eclipse ring", "vertex counterfeiting"],
		"event": ["was foiled by %d interns", "went exactly as planned",
			"turned out to be performance art", "was an inside job"],
		"react": ["the perimeter is a suggestion now.",
			"witnesses report seeing nothing, beautifully.",
			"the evidence refuses to render."]},
	"construction": {"thing": ["a fourth horizon", "the new meridian bypass",
			"a municipal dodecahedron", "scaffolding around the sunrise"],
		"event": ["is %d cycles behind schedule",
			"finished early and nobody trusts it", "is structurally smug",
			"collapsed upward"],
		"react": ["the permits were written in circles.",
			"engineers blame the concept of load.",
			"residents love it. loudly. at night."]},
	"romance": {"thing": ["two parallel lines", "a binary star couple",
			"the moon and someone's satellite"],
		"event": ["finally intersected", "announced a merger",
			"broke up over axis differences", "eloped past the skybox"],
		"react": ["mathematically it was never going to work.",
			"we wish them convergence.", "the tabloids are spiraling."]},
	"cuisine": {"thing": ["boiled starlight", "crescent stew",
			"artisanal vacuum", "deep-fried meridians"],
		"event": ["won %d awards", "was banned at the equator",
			"is just circles again", "achieved sentience mid-simmer"],
		"react": ["critics called it 'food-adjacent'.", "the recipe is classified.",
			"reservations now require coordinates."]},
	"science": {"thing": ["a new corner", "the missing vertex cache",
			"a frequency that tastes purple", "proof the sky is load-bearing"],
		"event": ["was discovered by accident", "was un-discovered by committee",
			"replicated itself out of spite", "is %d percent confirmed"],
		"react": ["peer review is hiding.", "the lab denies having walls.",
			"funding has been re-imagined."]},
	"employment": {"thing": ["the intern program", "the night shift on the dark side",
			"middle management", "the union of unpaired vertices"],
		"event": ["went on strike for %d minutes", "was automated, then un-automated",
			"got a corner office. an actual corner.", "unionized with the weather"],
		"react": ["morale is measurable and we measured it.",
			"the suggestion box achieved escape velocity.",
			"benefits now include a horizon."]},
	"art": {"thing": ["an invisible mural", "a statue of the concept of waiting",
			"minimalist skybox art", "a fountain that runs upward"],
		"event": ["sold for %d shadows", "was critiqued into another dimension",
			"is on loan from nobody", "vandalized itself, artistically"],
		"react": ["the critics wept in wireframe.", "attendance is mandatory and low.",
			"the artist remains a rumor."]}}
const AX_TWIST := ["and now there's talk of FRAUD.",
	"authorities suspect it was rigged from the start.",
	"a shortage followed within the hour.",
	"a festival has been scheduled to celebrate or mourn, depending.",
	"it has since been banned, which made it popular.",
	"records were broken. also furniture.",
	"an anonymous tip blames %s.",
	"insurance refuses to define it."]

# DEBATE parts: subject x claim x counter x verdict, composed per airing
const AX_DEB_SUBJ := ["resolution", "shadow ownership", "corner access",
	"gravity", "the skybox", "rendering order", "silence", "symmetry",
	"the intermission", "horizon rights"]
const AX_DEB_PRO := ["%s is a right.", "%s belongs to everyone.",
	"%s should be free at the point of use.", "you cannot OWN %s.",
	"%s built this system. show respect."]
const AX_DEB_CON := ["%s is a PRIVILEGE.", "%s must be earned.",
	"%s is a finite resource and %s is hoarding it.",
	"unlimited %s is how we lost the second sun.",
	"regulate %s or drown in it."]
const AX_DEB_OUT := ["strong words. the phones are melting.",
	"we'll settle this off-air. with rulers.",
	"the board will hear both of you. reluctantly.",
	"and THAT'S why we can't have nice geometry.",
	"take it to the comment dimension."]
const AX_CALL_IN := ["caller from %s, you're on the air.",
	"the phones. %s, go ahead.", "we have %s on line one, allegedly.",
	"next voice, courtesy of %s."]
const AX_CALL_OUT := ["next caller. keep it euclidean.",
	"hang up gently. the lines are heritage.",
	"and that's why we screen calls.", "thank you, mystery shape."]
const AX_WEATHER_IN := ["weather across the system.",
	"skies, everyone. skies.", "the atmospheric minute.",
	"what's falling, and where:"]
const AX_AD_IN := ["a word from our sponsor.",
	"this broadcast is paid for by:", "and now, commerce.",
	"capitalism break:"]
const AX_AD_OUT := ["we legally had to air that.",
	"no refunds. anywhere. ever.", "the sponsor is watching. wave.",
	"back to the show, allegedly."]
const AX_HIST_IN := ["history minute. %d cycles ago today:",
	"from the archive, %d cycles back:",
	"the past is calling. %d cycles, collect:"]

static var _ax_doms: Array = []

## Subject -> domain -> optional twist -> assembled segment. No two
## airings share a domain back-to-back, and every sentence is composed.
static func _ax_story(p: String, p2: String, foreign: bool = false) -> Array:
	var keys: Array = AX_DOMAINS.keys()
	var dom := str(keys[randi() % keys.size()])
	for attempt in 5:
		if not _ax_doms.has(dom):
			break
		dom = str(keys[randi() % keys.size()])
	_ax_doms.append(dom)
	if _ax_doms.size() > 3:
		_ax_doms.pop_front()
	var d: Dictionary = AX_DOMAINS[dom]
	var thing := _ax_fresh(d["thing"])
	var ev := _ax_fresh(d["event"])
	var nums := ev.count("%d")
	if nums == 2:
		ev = ev % [1 + randi() % 98, 1 + randi() % 98]
	elif nums == 1:
		ev = ev % (1 + randi() % 98)
	# a SECOND concept from a different domain: minds wander, and the
	# conversation follows the wandering
	var keys2: Array = AX_DOMAINS.keys()
	var dom2 := str(keys2[randi() % keys2.size()])
	for attempt2 in 4:
		if dom2 != dom:
			break
		dom2 = str(keys2[randi() % keys2.size()])
	var thing2: String = _ax_fresh(AX_DOMAINS[dom2]["thing"])
	var out: Array = []
	if foreign and randi() % 2 == 0:
		out.append([0, "from the OUT-SYSTEM desk:"])
	out.append([0, "%s news from %s: %s %s." % [dom, p, thing, ev]])
	# turn 2: a RESPONSE to the actual fact, carrying the nouns forward
	match randi() % 4:
		0:
			out.append([3, "hold on. %s? the SAME %s from last cycle's news?" % [thing, thing]])
		1:
			out.append([3, "i was there when %s first came to %s. nobody listened then either." % [thing, p]])
		2:
			out.append([3, "and %s just LETS this happen to %s. of course they do." % [p, thing]])
		_:
			out.append([3, _ax_fresh(d["react"])])
	# turns 3-4: someone drags the second concept in, someone connects them
	if randi() % 10 < 6:
		match randi() % 3:
			0:
				out.append([2, "question: does this affect %s?" % thing2])
			1:
				out.append([2, "wait. is that why %s has been weird all cycle?" % thing2])
			_:
				out.append([2, "my cousin works in %s. should they worry about %s?" % [dom2, thing]])
		match randi() % 3:
			0:
				out.append([1, "everything affects %s. that is its whole personality." % thing2])
			1:
				out.append([1, "%s and %s are officially unrelated. OFFICIALLY." % [thing, thing2]])
			_:
				out.append([1, "if %s ever reaches %s, we go to the bunker. the round one." % [thing, thing2]])
	# an optional twist, pinned to the thing it's about
	if randi() % 10 < 4:
		var tw := _ax_fresh(AX_TWIST)
		if tw.find("%s") >= 0:
			tw = tw % p2
		out.append([3, "and regarding %s: %s" % [thing, tw]])
	# outro recaps what was actually discussed
	match randi() % 3:
		0:
			out.append([0, "%s. %s. not one apology. that's the %s report." % [p, thing, dom]])
		1:
			out.append([0, "keep an eye on %s. and on %s. and on everything." % [thing, thing2]])
		_:
			out.append([0, "we'll follow %s until it follows back." % thing])
	return out

# PERSONALITIES: four smart aliens, four registers. Flavor is applied
# as a light per-host pass over composed lines -- word habits, not
# different content. 0 = the crisp anchor. 1 = the deadpan veteran.
# 2 = the sincere wonderer. 3 = the precise analyst.
const AX_VOICE_PRE := {
	0: ["moving on:", "for the record:", "in summary:"],
	1: ["per my chart,", "point of order:", "actuarially speaking,"],
	2: ["oh --", "wait, wait --", "okay but --"],
	3: ["mm.", "again?", "noted."]}
const AX_VOICE_POST := {
	0: [" -- next item.", " and that's confirmed.", " stay with us."],
	1: [" margin of error: yes.", " i have the figures.",
		" the data agrees, reluctantly."],
	2: [" ...isn't that something?", " i think about that a lot.",
		" the universe is so much."],
	3: [" as it always was.", " nothing changes.", " i've said my piece."]}

## Safe single-slot format: lines without a %s pass through untouched
## (several call-in lines have no blank -- forcing % on them crashed).
static func _fmt1(t: String, a: String) -> String:
	return t % a if t.find("%s") >= 0 else t

## The personality pass: ~one line in four picks up its speaker's habit.
static func _ax_voice(host: int, line: String) -> String:
	if randi() % 4 != 0:
		return line
	if randi() % 2 == 0 and AX_VOICE_PRE.has(host):
		var pre: Array = AX_VOICE_PRE[host]
		return str(pre[randi() % pre.size()]) + " " + line
	if AX_VOICE_POST.has(host):
		var post: Array = AX_VOICE_POST[host]
		return line + str(post[randi() % post.size()])
	return line

# anti-repeat memory: recently used lines and topics stay off the air
static var _ax_recent: Array = []
static var _ax_topics: Array = []
# what the last exchange was ABOUT -- the studio TV reads this
static var last_alien_meta := {"topic": -1, "planet": ""}

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
static func alien_exchange(in_room: bool = false) -> Array:
	# subjects: mostly the local shader system, but the desk follows the
	# whole universe -- Earth, Jupiter, the humans, even the hole
	var pool: Array = AP if randi() % 10 < 6 else AX_FAR
	var p: String = pool[randi() % pool.size()]
	var pool2: Array = AP + AX_FAR
	var p2: String = pool2[randi() % pool2.size()]
	for attempt in 4:
		if p2 != p:
			break
		p2 = pool2[randi() % pool2.size()]
	var topic := randi() % 10
	for attempt in 6:
		if not _ax_topics.has(topic):
			break
		topic = randi() % 10
	_ax_topics.append(topic)
	if _ax_topics.size() > 3:
		_ax_topics.pop_front()
	last_alien_meta = {"topic": topic, "planet": p, "planet2": p2}
	var out: Array = []
	match topic:
		0:
			out = _ax_story(p, p2, not AP.has(p))
		1:
			out = [[0, _fmt1(_ax_fresh(AX_CALL_IN), p)],
				[2, _fmt1(_ax_fresh(AP_QUESTIONS), p2)],
				[1, _fmt1(_ax_fresh(AP_ANSWERS), p2)],
				[0, _ax_fresh(AX_CALL_OUT)]]
		2:
			# a COMPOSED debate: fresh subject, fresh claim, fresh counter,
			# evidence assembled on the spot -- never the same argument
			var ds := _ax_fresh(AX_DEB_SUBJ)
			var con := _ax_fresh(AX_DEB_CON)
			con = con % [ds, p] if con.count("%s") == 2 else con % ds
			out = [[1, _ax_fresh(AX_DEB_PRO) % ds],
				[3, con],
				[1, "exhibit A: %s" % _ax_sentence(p, p2)],
				[2, _ax_opinion()],
				[0, _ax_fresh(AX_DEB_OUT)]]
		3:
			out = [[0, _ax_fresh(AX_WEATHER_IN)],
				[1, "%s: %s overnight. %s: %s by dawn. the sun: orange again. nobody asked it to be." % [
					p, _ax_fresh(AP_PHENOM), p2, _ax_fresh(AP_PHENOM)]]]
		4:
			out = _ax_story(p, p2, not AP.has(p))
		5:
			out = _ax_story(p, p2, not AP.has(p))
		6:
			var prod := _ax_fresh(AP_PRODUCTS)
			var slog := _ax_fresh(AP_SLOGANS)
			last_alien_meta["product"] = prod
			last_alien_meta["slogan"] = slog
			out = [[0, _ax_fresh(AX_AD_IN)],
				[1, "%s. %s" % [prod.capitalize(), slog]],
				[0, _ax_fresh(AX_AD_OUT)]]
		7:
			out = [[0, _ax_fresh(AX_HIST_IN) % (100 + randi() % 900)],
				[3, "%s we still feel it." % _ax_sentence(p, p2)],
				[2, _ax_opinion()]]
		8:
			# the FOURTH WALL segment: they know. they've always known.
			# in the ROOM, they address the person standing there; over
			# the dish, they address the decoder. never crossed.
			if in_room:
				if randi() % 2 == 0:
					var fwr: Array = AP_FOURTH_ROOM[randi() % AP_FOURTH_ROOM.size()]
					out = [[0, str(fwr[0])], [1, str(fwr[1])], [3, str(fwr[2])]]
				else:
					out = [[0, "to the dude standing in our studio: %s" % _ax_sentence(p, p2)],
						[3, "yes, YOU, dude. the one by the sofas."],
						[1, _ax_opinion()]]
			elif randi() % 2 == 0:
				var fw: Array = AP_FOURTH[randi() % AP_FOURTH.size()]
				out = [[0, str(fw[0])], [1, str(fw[1])], [3, str(fw[2])]]
			else:
				out = [[0, "to whoever is decoding this: %s" % _ax_sentence(p, p2)],
					[3, "write THAT down, dish person."],
					[1, _ax_opinion()]]
		_:
			# HUMANS: dumb, inefficient, endlessly watchable. the segment
			# opens like a field report, not a talk-show card
			out = [[0, _ax_fresh(AX_HUM_OPEN)],
				[3, _ax_fresh(AP_HUMAN_DUMB)],
				[1, "that's nothing. " + _ax_fresh(AP_HUMAN_DUMB)],
				[2, _ax_opinion()],
				[0, _ax_fresh(AX_HUM_CLOSE)]]
	# BANTER: the four of them are coworkers, and it shows. ~1 in 4
	# segments gets a little personality collision woven in.
	if randi() % 4 == 0:
		var banter: Array = AX_BANTER[randi() % AX_BANTER.size()]
		var at := 1 + randi() % maxi(1, out.size() - 1)
		for bi in range(banter.size() - 1, -1, -1):
			out.insert(at, banter[bi])
	# an unscheduled THOUGHT: rarely, someone just needs the foil cone
	if randi() % 12 == 0:
		out.append([2, _ax_fresh(AP_FOIL)])
	# CROSSTALK: sometimes a host just has to react to what was said --
	# agreement, doubt, a stray feeling -- and sometimes the original
	# speaker claps back. capped so it stays a show, not a brawl.
	var inserts := 0
	var ti2 := 0
	while ti2 < out.size() - 1 and inserts < 2:
		var spoke := int(out[ti2][0])
		# purple's tangents are irresistible: twice as likely to draw fire
		var roll := 3 if spoke == 2 else 6
		if randi() % roll == 0:
			var reactor := randi() % 4
			for attempt3 in 3:
				if reactor != spoke:
					break
				reactor = randi() % 4
			var rline := ""
			if spoke == 2:
				# responding to PURPLE is its own genre
				match reactor:
					0:
						rline = _ax_fresh(["we are NOT doing 'what if' hour again.",
							"save it for the overnight slot.",
							"and that's the sound of a segment ending."])
					1:
						rline = _ax_fresh(["you feel something every 4.2 minutes. i have the figures.",
							"i charted your tangents. they orbit.",
							"that is not a data point. it never is."])
					_:
						rline = _ax_fresh(["no.",
							"the break is in two minutes. hold it in.",
							"i miss the silence. it was straightforward."])
				out.insert(ti2 + 1, [reactor, rline])
				inserts += 1
				if randi() % 5 < 2:
					out.insert(ti2 + 2, [2, _ax_fresh(["you'll all think about it later.",
						"the sofa understands me.", "noted. feeling it anyway."])])
				ti2 += 2
				ti2 += 1
				continue
			match reactor:
				0:
					rline = _ax_fresh(["that's one interpretation.",
						"we will fact-check that never.",
						"careful. that's how segments start."])
				1:
					rline = _ax_fresh(["the numbers disagree, politely.",
						"correlation, causation, chaos. pick two.",
						"i ran the projection. don't ask."])
				2:
					rline = _ax_fresh(["that made me feel something. reporting it.",
						"do you ever just... agree with things? me neither.",
						"what if WE'RE the news?"])
				_:
					rline = _ax_fresh(["no.", "sure.",
						"heard it before. it was wrong then too.",
						"bold. wrong, but bold."])
			out.insert(ti2 + 1, [reactor, rline])
			inserts += 1
			if randi() % 5 < 2:
				out.insert(ti2 + 2, [spoke, _ax_fresh(["i stand by it.",
					"noted and ignored.", "put THAT on a chart.",
					"the sofa agrees with me."])])
			ti2 += 2
		ti2 += 1
	# the personality pass: every line filtered through its speaker
	for ti in out.size():
		out[ti] = [int(out[ti][0]), _ax_voice(int(out[ti][0]), str(out[ti][1]))]
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
			buf[b2 + i] += (sin(TAU * f0 * td) * 0.45 \
				+ sin(TAU * (f0 + 0.4) * td) * 0.3 \
				+ sin(TAU * f0 * 1.5 * td) * 0.2 \
				+ sin(TAU * f0 * 2.0 * td) * 0.26 \
				+ sin(TAU * (f0 * 2.0 + 0.6) * td) * 0.17 \
				+ sin(TAU * f0 * 3.0 * td) * 0.11) * denv
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

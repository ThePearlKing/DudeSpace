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
	"the fork.": 196.0, "is coming.": 165.0,
	"zholgoth.": 220.0, "vraxulemn.": 196.0,
	"othrunquay.": 175.0, "melgrahz.": 147.0,
	"when the timer rings its final ring,": 196.0,
	"the fork descends on everything.": 165.0}

static var _sauce_wav: AudioStreamWAV = null

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
	for ln in SAUCE_VERSE + SAUCE_VERSE2:
		if str(ln) == "":
			pos += barlen   # a rest: the beat carries the bar alone
			continue
		var w := eldritch(HumanVoice.render(str(ln), noodle_profile()), false)
		# the GROWL: the god's old saw throat, kept quiet under the mix
		var wg := HumanVoice.render(str(ln),
			{"base": 118.0, "var": 0.12, "wave": "saw", "rate": 0.9, "artic": 1.7})
		# the clear take is fully DRY -- any echo on it and the words go.
		# hook lines get a light AUTOTUNE: pinned to a note, zero drift
		var cprof := {"base": 165.0, "var": 0.15, "wave": "sine",
			"rate": 1.0, "artic": 1.85}
		if SAUCE_TUNED.has(str(ln)):
			cprof = {"base": float(SAUCE_TUNED[str(ln)]), "var": 0.0, "wave": "sine",
				"rate": 1.0, "artic": 1.85, "autotune": true}
		var wc := HumanVoice.render(str(ln), cprof)
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
			bbuf[b0 + i] += sin(TAU * 52.0 * tb) * exp(-tb * 14.0) * 0.38 * duck
		var toff := b0 + int(float(barlen) * 0.5)
		for i in mini(int(0.05 * SR), total - toff):
			var duck2 := clampf(1.0 - env[toff + i] * 4.0, 0.15, 1.0)
			bbuf[toff + i] += (randf() * 2.0 - 1.0) * exp(-float(i) / (SR * 0.01)) * 0.09 * duck2
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

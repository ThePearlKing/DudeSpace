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
			return {"scale": [0, 2, 4, 7, 9, 12], "bpm": 96, "wave": "sine",
				"base": 294.0}   # easy listening for a doomed species
		"rick":
			return {"scale": [0, 2, 4, 5, 7, 9], "bpm": 113, "wave": "square",
				"base": 233.0}   # a suspiciously committed groove
		"gas", "jazz":
			return {"scale": [0, 2, 3, 5, 7, 9, 10], "bpm": 88, "wave": "sine",
				"base": 220.0, "jazz": true}   # gas giants swing
		"life", "varnisol":
			return {"scale": [0, 3, 5, 7, 10, 12], "bpm": 84, "wave": "sine",
				"base": 262.0}   # gentle pentatonic
		"crystal":
			return {"scale": [0, 4, 7, 11, 12, 16], "bpm": 100, "wave": "sine",
				"base": 523.0}   # glassy heights
		"torus":
			return {"scale": [0, 2, 3, 6, 8, 12], "bpm": 122, "wave": "wobble",
				"base": 294.0}   # donut logic
		"lava", "volcanic":
			return {"scale": [0, 1, 5, 6, 10, 12], "bpm": 132, "wave": "saw",
				"base": 147.0}   # aggressive low
		"sand":
			return {"scale": [0, 1, 4, 5, 7, 8, 11], "bpm": 92, "wave": "sine",
				"base": 220.0}   # desert modal
		"circuit", "logic":
			return {"scale": [0, 3, 7, 10, 12], "bpm": 160, "wave": "square",
				"base": 392.0}   # chip factory
		_:
			return {"scale": [0, 2, 4, 5, 7, 9, 11, 12], "bpm": 110, "wave": "sine",
				"base": 262.0}

static var _music_cache := {}

## A seeded looping melody, ~9s, in the planet's style.
static func music_loop(seed_v: int, kind: String) -> AudioStreamWAV:
	var key := "%d_%s" % [seed_v, kind]
	if _music_cache.has(key):
		return _music_cache[key]
	var st := style_for(kind)
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
	var jazz: bool = bool(st.get("jazz", false))
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
		if jazz and ni % 2 == 1:
			start += int(beat * SR * 0.16)   # the swing. essential.
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
				_:
					v = sin(TAU * f * t) * 0.35 + sin(TAU * f * 2.0 * t) * 0.08
			var env := minf(1.0, float(i) / (SR * 0.01)) \
				* minf(1.0, float(dur - i) / (SR * 0.08))
			buf[start + i] += v * env
			if jazz and ni % 4 == 0:
				# a lush chord under the downbeats: root + 3rd + 7th
				var t2 := float(i) / SR
				buf[start + i] += (sin(TAU * f * 1.26 * t2)
					+ sin(TAU * f * 1.78 * t2)) * 0.14 * env
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

static func noodle_line() -> String:
	return NOODLE_BITS[randi() % NOODLE_BITS.size()]

static func noodle_profile() -> Dictionary:
	return {"base": 85.0, "var": 0.25, "wave": "saw", "rate": 0.62, "artic": 1.1}

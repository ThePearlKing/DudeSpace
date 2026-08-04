class_name HumanVoice
## Experimental formant TTS: it TRIES to say the sentence in English.
## Vowels are stacks of formant tones riding a glottal pulse, F and S
## and TH are real noise, plosives are little bursts, M and N hum.
## Not perfect. Recognizably trying. Like the humans themselves.
##
## The voice profile (from personality) bends it: pitch, monotone-ness,
## the glottal waveform (nerd square, sour saw, weird wobble, and the
## mosquito buzz for face_017), and talking speed.

const SR := 22050

## Build the phrase into a WAV and play it from `parent`. Returns the
## player so the caller can cut a voice off when new words replace old.
static func speak(parent: Node3D, text: String, prof: Dictionary) -> AudioStreamPlayer3D:
	var segs := _parse(text.to_lower())
	if segs.is_empty():
		return null
	var pitch0 := clampf(float(prof.get("base", 300.0)) * 0.55, 70.0, 280.0)
	var vary := float(prof.get("var", 0.4))
	var wave := str(prof.get("wave", "sine"))
	var rate := float(prof.get("rate", 1.0))
	var qmark := text.ends_with("?")
	var buf := PackedFloat32Array()
	var word := 0
	var total := segs.size()
	for idx in total:
		var sg: Dictionary = segs[idx]
		var dur := float(sg.get("d", 0.06)) * rate
		if sg["t"] == "sp":
			word += 1
			_silence(buf, dur)
			continue
		# sentence melody: starts a touch high, settles at the end;
		# questions bend UP. monotone voices barely move at all.
		var prog := float(idx) / maxf(1.0, float(total - 1))
		var contour := 1.0 + (0.06 - 0.16 * prog) * clampf(vary * 2.5, 0.15, 1.0)
		if qmark and prog > 0.75:
			contour += (prog - 0.75) * 0.8 * clampf(vary * 2.5, 0.3, 1.0)
		var pitch := pitch0 * contour \
			* (1.0 + vary * 0.2 * sin(float(word) * 1.7 + float(idx) * 0.35))
		match sg["t"]:
			"v":
				var f: Array = sg["f"]
				_vowel(buf, float(f[0]), float(f[1]), dur, pitch, wave)
			"f":
				_fric(buf, bool(sg["b"]), bool(sg["vo"]), dur, pitch)
			"p":
				_plosive(buf, bool(sg["vo"]), pitch)
			"n":
				_nasal(buf, dur, pitch)
	if buf.is_empty():
		return null
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.data = bytes
	var pl := AudioStreamPlayer3D.new()
	pl.stream = wav
	# close-range voice: falls off fast with distance and goes fully
	# silent past ~18m -- you hear YOUR corner of the city, not all of it
	pl.unit_size = 3.5
	pl.max_distance = 18.0
	pl.max_db = -6.0
	pl.volume_db = -8.0
	parent.add_child(pl)
	pl.finished.connect(pl.queue_free)
	pl.play()
	return pl

## Text -> rough phoneme segments. Digraphs first (th/sh/ch/ee/oo/ng),
## then letter classes. English spelling is lies, but close enough.
static func _parse(t: String) -> Array:
	var out: Array = []
	var i := 0
	while i < t.length() and out.size() < 90:
		var two := t.substr(i, 2)
		var c := t.substr(i, 1)
		if two == "ee" or two == "ea":
			out.append({"t": "v", "f": [300.0, 2200.0], "d": 0.085})
			i += 2
			continue
		if two == "oo":
			out.append({"t": "v", "f": [320.0, 880.0], "d": 0.085})
			i += 2
			continue
		if two == "th":
			out.append({"t": "f", "b": false, "vo": false, "d": 0.06})
			i += 2
			continue
		if two == "sh" or two == "ch":
			out.append({"t": "f", "b": true, "vo": false, "d": 0.08})
			i += 2
			continue
		if two == "ng":
			out.append({"t": "n", "d": 0.07})
			i += 2
			continue
		i += 1
		match c:
			"a":
				out.append({"t": "v", "f": [660.0, 1220.0], "d": 0.07})
			"e":
				out.append({"t": "v", "f": [530.0, 1680.0], "d": 0.07})
			"i":
				out.append({"t": "v", "f": [390.0, 1990.0], "d": 0.07})
			"o":
				out.append({"t": "v", "f": [500.0, 900.0], "d": 0.075})
			"u":
				out.append({"t": "v", "f": [420.0, 1000.0], "d": 0.07})
			"l", "r", "w", "y":
				out.append({"t": "v", "f": [440.0, 1300.0], "d": 0.05})
			"f", "h":
				out.append({"t": "f", "b": false, "vo": false, "d": 0.06})
			"v":
				out.append({"t": "f", "b": false, "vo": true, "d": 0.055})
			"s", "x":
				out.append({"t": "f", "b": true, "vo": false, "d": 0.07})
			"z", "j":
				out.append({"t": "f", "b": true, "vo": true, "d": 0.06})
			"c", "k", "q", "t", "p":
				out.append({"t": "p", "vo": false})
			"b", "d", "g":
				out.append({"t": "p", "vo": true})
			"m", "n":
				out.append({"t": "n", "d": 0.06})
			" ":
				out.append({"t": "sp", "d": 0.045})
			".", ",", "?", "!":
				out.append({"t": "sp", "d": 0.1})
	return out

static func _env(i: int, n: int, atk: float, rel: float) -> float:
	return minf(1.0, float(i) / (SR * atk)) * minf(1.0, float(n - i) / (SR * rel))

static func _silence(buf: PackedFloat32Array, dur: float) -> void:
	for i in int(dur * SR):
		buf.append(0.0)

## A vowel, done properly-ish: build ONE cycle of the waveform from the
## harmonics of the pitch, each harmonic weighted by how close it sits
## to the vowel's formant resonances. "A" comes out sounding like AH,
## "ee" like EE. Then loop the cycle for the duration. Cheap AND vowel.
static func _vowel(buf: PackedFloat32Array, f1: float, f2: float,
		dur: float, pitch: float, wave: String) -> void:
	if wave == "buzz":
		pitch *= 1.35   # the mosquito registers
	var period := maxi(8, int(SR / pitch))
	var tbl := PackedFloat32Array()
	tbl.resize(period)
	var nh := mini(26, int((SR * 0.45) / pitch))
	for k in range(1, nh + 1):
		var fk := float(k) * pitch
		# glottal rolloff by voice type, then the vocal-tract filter
		var src := 1.0 / float(k)
		if wave == "square" and k % 2 == 0:
			src *= 0.15   # hollow odd-harmonic nerd timbre
		elif wave == "sine":
			src = 1.0 if k == 1 else 1.0 / float(k * k)   # soft and round
		var amp := src * (0.22 \
			+ 1.0 * exp(-pow((fk - f1) / 220.0, 2.0)) \
			+ 0.8 * exp(-pow((fk - f2) / 320.0, 2.0)) \
			+ 0.25 * exp(-pow((fk - 2600.0) / 400.0, 2.0)))
		for i in period:
			tbl[i] += sin(TAU * float(k) * float(i) / float(period)) * amp
	var peak := 0.001
	for i in period:
		peak = maxf(peak, absf(tbl[i]))
	var n := int(dur * SR)
	for i in n:
		var idx := i
		if wave == "wobble":   # vibrato that never settles
			idx = int(float(i) * (1.0 + 0.06 * sin(TAU * 5.0 * float(i) / SR)))
		var s := tbl[idx % period] / peak * 0.5
		if wave == "buzz":     # wing-flutter tremolo
			s *= 0.65 + 0.35 * sin(TAU * 26.0 * float(i) / SR)
		buf.append(s * _env(i, n, 0.012, 0.03))

## Fricatives: noise, shaped crudely. Bright = hissy (s/sh/ch),
## dull = breathy wash (f/th/h). Voiced ones hum underneath (v/z).
static func _fric(buf: PackedFloat32Array, bright: bool, voiced: bool,
		dur: float, pitch: float) -> void:
	var n := int(dur * SR)
	var prev := 0.0
	for i in n:
		var w := randf() * 2.0 - 1.0
		var s: float
		if bright:
			s = (w - prev) * 0.3        # crude high-pass: hiss
		else:
			s = (w + prev) * 0.5 * 0.24  # crude low-pass: breath
		prev = w
		if voiced:
			s += sin(TAU * pitch * float(i) / SR) * 0.18
		buf.append(s * _env(i, n, 0.008, 0.02))

## Plosives: a beat of closure, then the little explosion.
static func _plosive(buf: PackedFloat32Array, voiced: bool, pitch: float) -> void:
	_silence(buf, 0.018)
	var n := int(0.035 * SR)
	for i in n:
		var fall := 1.0 - float(i) / float(n)
		var s := (randf() * 2.0 - 1.0) * 0.5 * fall
		if voiced:
			s += sin(TAU * pitch * float(i) / SR) * 0.25 * fall
		buf.append(s)

## Nasals: lips shut, everything comes out the nose. A dark hum.
static func _nasal(buf: PackedFloat32Array, dur: float, pitch: float) -> void:
	var n := int(dur * SR)
	for i in n:
		var t := float(i) / SR
		var s := sin(TAU * pitch * t) * 0.3 + sin(TAU * 240.0 * t) * 0.25 \
			+ sin(TAU * 2.2 * pitch * t) * 0.08
		buf.append(s * _env(i, n, 0.015, 0.03))

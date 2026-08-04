class_name HumanVoice
## Experimental formant TTS: it TRIES to say the sentence in English.
## Vowels are harmonic wavetables shaped by formant resonances, F and S
## and TH are real noise, plosives are little bursts, M and N hum.
## Adjacent voiced sounds CONNECT: one continuous voicing run with the
## mouth-shape gliding between letters -- "arctic", not "a-r-c-t-i-c".
##
## The voice profile (from personality) bends it: pitch, monotone-ness,
## the glottal timbre (nerd square, sour saw, weird wobble, and the
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
	var artic := float(prof.get("artic", 1.0))   # consonant emphasis
	var qmark := text.ends_with("?")
	if wave == "saw":
		pitch0 *= 0.78   # the grump register: lower than it needs to be
	# first pass: give every segment its pitch (the sentence melody)
	# and final duration
	var total := segs.size()
	var word := 0
	for idx in total:
		var sg: Dictionary = segs[idx]
		sg["d"] = float(sg.get("d", 0.06)) * rate
		var prog := float(idx) / maxf(1.0, float(total - 1))
		var contour := 1.0 + (0.06 - 0.16 * prog) * clampf(vary * 2.5, 0.15, 1.0)
		if qmark and prog > 0.75:
			contour += (prog - 0.75) * 0.8 * clampf(vary * 2.5, 0.3, 1.0)
		if sg["t"] == "sp":
			word += 1
		sg["pitch"] = pitch0 * contour \
			* (1.0 + vary * 0.2 * sin(float(word) * 1.7 + float(idx) * 0.35))
	# second pass: synth. voiced neighbours fuse into runs.
	var buf := PackedFloat32Array()
	var i := 0
	while i < segs.size():
		var sg: Dictionary = segs[i]
		match sg["t"]:
			"sp":
				_silence(buf, float(sg["d"]))
				i += 1
			"f":
				_fric(buf, bool(sg["b"]), bool(sg["vo"]),
					float(sg["d"]) * (1.0 + (artic - 1.0) * 0.4),
					float(sg["pitch"]), artic)
				i += 1
			"p":
				_plosive(buf, bool(sg["vo"]), float(sg["pitch"]), artic)
				i += 1
			_:
				var run: Array = []
				while i < segs.size() and (segs[i]["t"] == "v" or segs[i]["t"] == "n"):
					run.append(segs[i])
					i += 1
				_voiced_run(buf, run, wave)
	if buf.is_empty():
		return null
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for j in buf.size():
		bytes.encode_s16(j * 2, int(clampf(buf[j], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.data = bytes
	var pl := AudioStreamPlayer3D.new()
	pl.stream = wav
	# close-range voice: inverse-SQUARE falloff, so a few steps away is
	# already noticeably quieter, and fully silent past ~18m -- you hear
	# YOUR corner of the city, not all of it
	pl.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	pl.unit_size = 2.5
	pl.max_distance = 18.0
	pl.max_db = -6.0
	pl.volume_db = -8.0
	parent.add_child(pl)
	pl.finished.connect(pl.queue_free)
	pl.play()
	return pl

## Text -> rough phoneme segments, with actual English spelling rules:
## Y after a consonant says EE (society, happy) but glides before a
## vowel (yes, you). Final silent e says nothing (like, made) except in
## tiny words where it says EE (he, we). Soft c before e/i/y says S.
## ai/ay, ou/ow, igh become real diphthongs -- two vowels glided.
## Doubled consonants collapse. tion says shun. Each word leans on its
## first vowel. English spelling is lies, but these are the big lies.
static func _is_letter(c: String) -> bool:
	return c >= "a" and c <= "z"

## The magic-e rule: vowel + one consonant + word-final silent e makes
## the vowel say its NAME. made=AY, here=EE, like=EYE, alone=OH.
static func _magic_e(t: String, i: int) -> bool:
	if i + 2 >= t.length():
		return false
	var cons := t.substr(i + 1, 1)
	if not _is_letter(cons) or cons in ["a", "e", "i", "o", "u"]:
		return false
	if t.substr(i + 2, 1) != "e":
		return false
	return i + 3 >= t.length() or not _is_letter(t.substr(i + 3, 1))

static func _parse(t: String) -> Array:
	var out: Array = []
	var i := 0
	var wlen := 0        # letters so far in the current word
	var stressed := false   # has this word leaned on a vowel yet
	while i < t.length() and out.size() < 88:
		var c := t.substr(i, 1)
		if not _is_letter(c):
			wlen = 0
			stressed = false
			if c == " ":
				out.append({"t": "sp", "d": 0.045})
			elif c == "." or c == "," or c == "?" or c == "!":
				out.append({"t": "sp", "d": 0.1})
			i += 1
			continue
		var nextc := t.substr(i + 1, 1) if i + 1 < t.length() else ""
		# doubled consonants say themselves once
		if c == nextc and not (c in ["a", "e", "i", "o", "u"]):
			i += 1
			wlen += 1
			continue
		var two := t.substr(i, 2)
		var vf: Array = []      # queued vowel sound(s): [f1, f2, dur]
		var post: Array = []    # segments that follow the vowel (tion's n)
		var adv := 1
		if t.substr(i, 4) == "tion":
			out.append({"t": "f", "b": true, "vo": false, "d": 0.08})
			vf = [[500.0, 1200.0, 0.05]]
			post = [{"t": "n", "d": 0.065}]
			adv = 4
		elif t.substr(i, 3) == "igh":   # night, right: the EYE diphthong
			vf = [[800.0, 1100.0, 0.055], [270.0, 2400.0, 0.06]]
			adv = 3
		elif two == "ee" or two == "ea":
			vf = [[270.0, 2400.0, 0.1]]
			adv = 2
		elif two == "oo":
			vf = [[300.0, 750.0, 0.1]]
			adv = 2
		elif two == "ai" or two == "ay":   # day: EH gliding into EE
			vf = [[580.0, 1900.0, 0.055], [270.0, 2400.0, 0.06]]
			adv = 2
		elif two == "ou" or two == "ow":   # out, now: AH gliding into OO
			vf = [[800.0, 1100.0, 0.055], [300.0, 750.0, 0.06]]
			adv = 2
		elif two == "oa":   # boat
			vf = [[450.0, 750.0, 0.1]]
			adv = 2
		elif two == "th":
			out.append({"t": "f", "b": false, "vo": false, "d": 0.06})
			adv = 2
		elif two == "sh" or two == "ch":
			out.append({"t": "f", "b": true, "vo": false, "d": 0.08})
			adv = 2
		elif two == "ng":
			out.append({"t": "n", "d": 0.07})
			adv = 2
		elif two == "ck":
			out.append({"t": "p", "vo": false})
			adv = 2
		elif two == "ph":   # phone: f
			out.append({"t": "f", "b": false, "vo": false, "d": 0.06})
			adv = 2
		elif two == "wh":   # what: w
			vf = [[420.0, 1350.0, 0.055]]
			adv = 2
		elif two == "qu":   # quick: k + w
			out.append({"t": "p", "vo": false})
			vf = [[420.0, 1350.0, 0.04]]
			adv = 2
		else:
			var word_end := nextc == "" or not _is_letter(nextc)
			match c:
				"a":
					if _magic_e(t, i):   # made, place: AY
						vf = [[580.0, 1900.0, 0.055], [270.0, 2400.0, 0.065]]
					else:
						# the AE of apple and am -- bright and flat, not
						# the dark AH of otter (that one lives in O)
						vf = [[680.0, 1750.0, 0.09]]
				"e":
					# final silent e says nothing (like, made)...
					if _magic_e(t, i):   # here, these: EE
						vf = [[270.0, 2400.0, 0.1]]
					elif word_end and wlen >= 3:
						pass
					elif word_end:
						vf = [[270.0, 2400.0, 0.08]]   # ...but he/we say EE
					else:
						vf = [[580.0, 1900.0, 0.085]]  # EH, as in bed
				"i":
					if wlen == 0 and word_end:   # the word I (and I'm): EYE
						vf = [[800.0, 1100.0, 0.06], [270.0, 2400.0, 0.07]]
					elif word_end:               # hi, sci-fi: EYE at word end
						vf = [[800.0, 1100.0, 0.06], [270.0, 2400.0, 0.07]]
					elif _magic_e(t, i):         # like, time: EYE
						vf = [[800.0, 1100.0, 0.055], [270.0, 2400.0, 0.065]]
					elif t.substr(i + 1, 2) == "nd" or t.substr(i + 1, 2) == "ld":
						vf = [[800.0, 1100.0, 0.055], [270.0, 2400.0, 0.065]]   # find, wild
					else:
						# IH as in bit: its own vowel, NOT a copy of EE
						vf = [[400.0, 1900.0, 0.08]]
				"o":
					if _magic_e(t, i):   # alone: OH, held longer
						vf = [[450.0, 750.0, 0.11]]
					else:
						vf = [[450.0, 750.0, 0.09]]
				"u":
					if _magic_e(t, i):   # tune: OO
						vf = [[300.0, 750.0, 0.1]]
					else:
						vf = [[320.0, 850.0, 0.085]]
				"y":
					# society, happy: y after a consonant (or ending a
					# word) is a vowel and says EE. yes/you: a glide.
					if word_end or not (nextc in ["a", "e", "i", "o", "u"]):
						vf = [[270.0, 2400.0, 0.095]]   # long enough to HEAR
					else:
						vf = [[420.0, 1350.0, 0.055]]
				"l", "r", "w":
					vf = [[420.0, 1350.0, 0.055]]
				"c":
					# soft c: society, city, cycle -> S. otherwise K.
					if nextc in ["e", "i", "y"]:
						out.append({"t": "f", "b": true, "vo": false, "d": 0.07})
					else:
						out.append({"t": "p", "vo": false})
				"f", "h":
					out.append({"t": "f", "b": false, "vo": false, "d": 0.06})
				"v":
					out.append({"t": "f", "b": false, "vo": true, "d": 0.055})
				"s", "x":
					out.append({"t": "f", "b": true, "vo": false, "d": 0.07})
				"z", "j":
					out.append({"t": "f", "b": true, "vo": true, "d": 0.06})
				"k", "q", "t", "p":
					out.append({"t": "p", "vo": false})
				"b", "d", "g":
					out.append({"t": "p", "vo": true})
				"m", "n":
					out.append({"t": "n", "d": 0.065})
		if not vf.is_empty():
			if not stressed:
				vf[0][2] *= 1.3   # each word leans on its first vowel
				stressed = true
			for v in vf:
				out.append({"t": "v", "f": [v[0], v[1]], "d": v[2]})
		for pseg in post:
			out.append(pseg)
		wlen += adv
		i += adv
	return out

## One glottal cycle with the harmonics weighted by the vocal tract:
## sharp resonances at F1/F2 (plus a hint of F3) so each vowel has its
## OWN color. Source rolloff sets the personality timbre.
static func _table(f1: float, f2: float, pitch: float, wave: String,
		gain: float) -> PackedFloat32Array:
	if wave == "buzz":
		pitch *= 1.35   # the mosquito registers
	var period := maxi(8, int(SR / pitch))
	var tbl := PackedFloat32Array()
	tbl.resize(period)
	var nh := mini(30, int((SR * 0.45) / pitch))
	for k in range(1, nh + 1):
		var fk := float(k) * pitch
		var src := 1.0 / float(k)
		if wave == "square" and k % 2 == 0:
			src *= 0.15   # hollow odd-harmonic nerd timbre
		elif wave == "sine":
			src = 1.0 if k == 1 else 1.0 / float(k * k)   # soft and round
		elif wave == "saw":
			src *= exp(-fk / 2200.0)   # dark chest voice: highs eaten by scowl
		var amp := src * (0.06 \
			+ 1.0 * exp(-pow((fk - f1) / 130.0, 2.0)) \
			+ 0.95 * exp(-pow((fk - f2) / 180.0, 2.0)) \
			+ 0.15 * exp(-pow((fk - 3000.0) / 350.0, 2.0)))
		for i in period:
			tbl[i] += sin(TAU * float(k) * float(i) / float(period)) * amp
	var peak := 0.001
	for i in period:
		peak = maxf(peak, absf(tbl[i]))
	for i in period:
		tbl[i] = tbl[i] / peak * 0.5 * gain
	return tbl

## A run of connected voiced sounds: ONE unbroken voicing, the mouth
## shape crossfading from letter to letter at every joint. This is what
## turns a-r-c-t-i-c into arctic.
static func _voiced_run(buf: PackedFloat32Array, run: Array, wave: String) -> void:
	var tbls: Array = []
	var lens: Array = []
	for ev in run:
		var f1: float
		var f2: float
		var gain := 1.0
		if ev["t"] == "n":
			f1 = 260.0
			f2 = 1100.0
			gain = 0.5   # nasal: dark and muted, everything via the nose
		else:
			var f: Array = ev["f"]
			f1 = float(f[0])
			f2 = float(f[1])
		tbls.append(_table(f1, f2, float(ev["pitch"]), wave, gain))
		lens.append(int(float(ev["d"]) * SR))
	var xf := int(0.032 * SR)   # formant glide window at each joint
	var start := buf.size()
	var pos := 0
	for si in run.size():
		var tbl: PackedFloat32Array = tbls[si]
		var p := tbl.size()
		var has_next := si + 1 < run.size()
		var nxt: PackedFloat32Array = tbls[si + 1] if has_next else tbl
		var pn := nxt.size()
		var n: int = lens[si]
		for j in n:
			var idx := pos
			if wave == "wobble":   # vibrato that never settles
				idx = int(float(pos) * (1.0 + 0.06 * sin(TAU * 5.0 * float(pos) / SR)))
			var s := tbl[idx % p]
			var rem := n - j
			if has_next and rem < xf:   # glide the mouth to the next letter
				var m := 1.0 - float(rem) / float(xf)
				s = s * (1.0 - m) + nxt[idx % pn] * m
			if wave == "buzz":   # wing-flutter tremolo
				s *= 0.65 + 0.35 * sin(TAU * 26.0 * float(pos) / SR)
			elif wave == "saw":  # the growl: low vocal-fry flutter
				s *= 0.76 + 0.24 * sin(TAU * 52.0 * float(pos) / SR)
			buf.append(s)
			pos += 1
	# envelope over the WHOLE run -- letters inside it stay joined
	var rn := buf.size() - start
	for j in rn:
		buf[start + j] *= minf(1.0, float(j) / (SR * 0.012)) \
			* minf(1.0, float(rn - j) / (SR * 0.03))

static func _env(i: int, n: int, atk: float, rel: float) -> float:
	return minf(1.0, float(i) / (SR * atk)) * minf(1.0, float(n - i) / (SR * rel))

static func _silence(buf: PackedFloat32Array, dur: float) -> void:
	for i in int(dur * SR):
		buf.append(0.0)

## Fricatives: noise, shaped crudely. Bright = hissy (s/sh/ch),
## dull = breathy wash (f/th/h). Voiced ones hum underneath (v/z).
static func _fric(buf: PackedFloat32Array, bright: bool, voiced: bool,
		dur: float, pitch: float, artic: float = 1.0) -> void:
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
		buf.append(s * artic * _env(i, n, 0.008, 0.02))

## Plosives: a beat of closure, then the little explosion.
static func _plosive(buf: PackedFloat32Array, voiced: bool, pitch: float,
		artic: float = 1.0) -> void:
	_silence(buf, 0.014)
	var n := int(0.032 * SR)
	for i in n:
		var fall := 1.0 - float(i) / float(n)
		var s := (randf() * 2.0 - 1.0) * 0.5 * artic * fall
		if voiced:
			s += sin(TAU * pitch * float(i) / SR) * 0.25 * fall
		buf.append(s)

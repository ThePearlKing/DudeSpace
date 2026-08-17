class_name ChipSound
extends Node
## THE SOUND CHIP. Eight voices, and not one of them is a bare square
## wave unless you ask for one. Every voice has a filter with its own
## envelope, an LFO on pitch and another on pulse width, a noise blend
## for drums, its own place in the stereo field, and sends into a shared
## delay and a small room. That is the difference between a chiptune
## that beeps and one somebody wants to listen to.
##
## Runs on its own thread like the modular synth does, pushing into an
## AudioStreamGenerator on the cabinet itself, so the music comes from
## the machine and gets quieter as you walk away.

const SR := 22050.0
const BLK := 128                  # samples per block (5.8ms)
const CHANS := 8

# waveforms
const W_PULSE := 0
const W_TRI := 1
const W_SAW := 2
const W_SINE := 3
const W_NOISE := 4
const W_METAL := 5                # two shift registers, for hats and clangs
const W_SAMPLE := 6               # a rendered modular-synth patch
const WAVE_NAMES := ["PULSE", "TRI", "SAW", "SINE", "NOISE", "METAL", "PATCH"]

# ------------------------------------------------------------ instrument
## One voice recipe. Everything a note needs to know about how to sound.
class Inst extends RefCounted:
	var name: String = "LEAD"
	var wave: int = W_PULSE
	var duty: float = 0.5
	var pwm_rate: float = 0.0      # Hz, pulse-width wobble
	var pwm_depth: float = 0.0
	var atk: float = 0.005         # seconds
	var dec: float = 0.10
	var sus: float = 0.7           # 0..1
	var rel: float = 0.12
	var pitch_env: float = 0.0     # semitones added at note-on...
	var pitch_time: float = 0.05   # ...decaying away over this long
	var vib_rate: float = 5.5
	var vib_depth: float = 0.0     # semitones
	var vib_delay: float = 0.12
	var cut: float = 1.0           # filter cutoff, 0..1 of nyquist
	var res: float = 0.0
	var cut_env: float = 0.0       # cutoff swing at note-on
	var cut_time: float = 0.12
	var noise_mix: float = 0.0     # blend noise over the wave: snares
	var pan: float = 0.0           # -1 left, +1 right
	var vol: float = 0.8
	var delay_send: float = 0.0
	var room_send: float = 0.0
	var sample := PackedFloat32Array()   # W_SAMPLE: one rendered note
	var sample_base: float = 48.0        # what semitone that sample IS
	var sample_loop: bool = true

	func to_dict() -> Dictionary:
		var d := {"name": name, "wave": wave, "duty": duty, "pwm_rate": pwm_rate,
			"pwm_depth": pwm_depth, "atk": atk, "dec": dec, "sus": sus,
			"rel": rel, "pitch_env": pitch_env, "pitch_time": pitch_time,
			"vib_rate": vib_rate, "vib_depth": vib_depth, "vib_delay": vib_delay,
			"cut": cut, "res": res, "cut_env": cut_env, "cut_time": cut_time,
			"noise_mix": noise_mix, "pan": pan, "vol": vol,
			"delay_send": delay_send, "room_send": room_send,
			"sample_base": sample_base, "sample_loop": sample_loop}
		if sample.size() > 0:
			# a rendered patch rides along with the instrument
			var b := PackedByteArray()
			b.resize(sample.size() * 2)
			for i in sample.size():
				var v := int(clampf(sample[i], -1.0, 1.0) * 32767.0)
				b.encode_s16(i * 2, v)
			d["sample"] = Marshalls.raw_to_base64(b)
		return d

	static func from_dict(d: Dictionary) -> Inst:
		var i := Inst.new()
		i.name = str(d.get("name", "LEAD"))
		i.wave = int(d.get("wave", W_PULSE))
		i.duty = float(d.get("duty", 0.5))
		i.pwm_rate = float(d.get("pwm_rate", 0.0))
		i.pwm_depth = float(d.get("pwm_depth", 0.0))
		i.atk = float(d.get("atk", 0.005))
		i.dec = float(d.get("dec", 0.1))
		i.sus = float(d.get("sus", 0.7))
		i.rel = float(d.get("rel", 0.12))
		i.pitch_env = float(d.get("pitch_env", 0.0))
		i.pitch_time = float(d.get("pitch_time", 0.05))
		i.vib_rate = float(d.get("vib_rate", 5.5))
		i.vib_depth = float(d.get("vib_depth", 0.0))
		i.vib_delay = float(d.get("vib_delay", 0.12))
		i.cut = float(d.get("cut", 1.0))
		i.res = float(d.get("res", 0.0))
		i.cut_env = float(d.get("cut_env", 0.0))
		i.cut_time = float(d.get("cut_time", 0.12))
		i.noise_mix = float(d.get("noise_mix", 0.0))
		i.pan = float(d.get("pan", 0.0))
		i.vol = float(d.get("vol", 0.8))
		i.delay_send = float(d.get("delay_send", 0.0))
		i.room_send = float(d.get("room_send", 0.0))
		i.sample_base = float(d.get("sample_base", 48.0))
		i.sample_loop = bool(d.get("sample_loop", true))
		if d.has("sample"):
			var raw := Marshalls.base64_to_raw(str(d["sample"]))
			i.sample.resize(raw.size() / 2)
			for k in i.sample.size():
				i.sample[k] = float(raw.decode_s16(k * 2)) / 32767.0
		return i

# --------------------------------------------------------------- channel
class Chan extends RefCounted:
	var inst: int = 0
	var note: float = -1.0         # semitone, -1 = silent
	var target_note: float = -1.0  # portamento destination
	var vol: float = 1.0
	var phase: float = 0.0
	var env: float = 0.0
	var stage: int = 0             # 0 off 1 atk 2 dec 3 sus 4 rel
	var t_on: float = 0.0
	var lfo: float = 0.0
	var pwm_phase: float = 0.0
	var lp1: float = 0.0           # state-variable filter memory
	var bp1: float = 0.0
	var lfsr: int = 0x7FFF
	var lfsr2: int = 0x1234
	var pan: float = 0.0
	var fx: int = 0
	var fx_p: int = 0
	var arp_i: int = 0
	var slide: float = 0.0
	var mute: bool = false
	var last_out: float = 0.0      # what the meters draw
	var samp_pos: float = 0.0
	## Control-rate cache. Pitch envelopes, vibrato and filter sweeps are
	## recomputed every CTL samples rather than every sample -- at 1.5ms
	## resolution nobody can hear the difference, and it is the whole
	## reason eight voices fit in a fraction of a core.
	var ctl_i: int = 0
	var c_step: float = 0.0        # phase increment
	var c_fc: float = 1.0
	var c_duty: float = 0.5

# ------------------------------------------------------------------ song
## A pattern is rows x 8 cells; a cell is [note, inst, vol, fx, param].
## note: 0 empty, 1 note-off, 2.. = semitone + 2.
const CELL_LEN := 5

class Song extends RefCounted:
	var title: String = "UNTITLED"
	var bpm: int = 125
	var speed: int = 6             # ticks per row
	var rows: int = 64
	## Time signature. rows_per_beat is what makes it mean anything: at
	## 4 rows to the beat and 4 beats to the bar, every 16th row starts a
	## bar and the grid says so.
	var sig_num: int = 4
	var sig_den: int = 4
	var rows_per_beat: int = 4
	var patterns: Array = []       # Array of PackedInt32Array
	var order: Array = [0]
	var insts: Array = []          # Array[Inst]
	var delay_time: float = 0.22
	var delay_fb: float = 0.35
	var room: float = 0.25

	func pattern(i: int) -> PackedInt32Array:
		while patterns.size() <= i:
			var p := PackedInt32Array()
			p.resize(rows * CHANS * CELL_LEN)
			patterns.append(p)
		return patterns[i]

	func cell(pat: int, row: int, ch: int) -> Array:
		var p := pattern(pat)
		var o := (row * CHANS + ch) * CELL_LEN
		return [p[o], p[o + 1], p[o + 2], p[o + 3], p[o + 4]]

	func set_cell(pat: int, row: int, ch: int, vals: Array) -> void:
		var p := pattern(pat)
		var o := (row * CHANS + ch) * CELL_LEN
		for i in mini(CELL_LEN, vals.size()):
			p[o + i] = int(vals[i])
		patterns[pat] = p

	func to_dict() -> Dictionary:
		var pats: Array = []
		for p in patterns:
			pats.append(Marshalls.raw_to_base64(
				(p as PackedInt32Array).to_byte_array()))
		var ins: Array = []
		for i in insts:
			ins.append((i as Inst).to_dict())
		return {"kind": "song", "title": title, "bpm": bpm, "speed": speed,
			"rows": rows, "sig_num": sig_num, "sig_den": sig_den,
			"rows_per_beat": rows_per_beat,
			"patterns": pats, "order": order.duplicate(),
			"insts": ins, "delay_time": delay_time, "delay_fb": delay_fb,
			"room": room}

	static func from_dict(d: Dictionary) -> Song:
		var s := Song.new()
		s.title = str(d.get("title", "UNTITLED"))
		s.bpm = int(d.get("bpm", 125))
		s.speed = int(d.get("speed", 6))
		s.rows = int(d.get("rows", 64))
		s.sig_num = int(d.get("sig_num", 4))
		s.sig_den = int(d.get("sig_den", 4))
		s.rows_per_beat = int(d.get("rows_per_beat", 4))
		s.delay_time = float(d.get("delay_time", 0.22))
		s.delay_fb = float(d.get("delay_fb", 0.35))
		s.room = float(d.get("room", 0.25))
		s.patterns = []
		for b in (d.get("patterns", []) as Array):
			var raw := Marshalls.base64_to_raw(str(b))
			var p := PackedInt32Array()
			p.resize(s.rows * CHANS * CELL_LEN)
			for i in mini(p.size(), raw.size() / 4):
				p[i] = raw.decode_s32(i * 4)
			s.patterns.append(p)
		var od = d.get("order", [0])
		s.order = (od as Array).duplicate() if od is Array else [0]
		s.insts = []
		for i in (d.get("insts", []) as Array):
			s.insts.append(Inst.from_dict(i as Dictionary))
		if s.insts.is_empty():
			s.insts = ChipSound.default_bank()
		return s

# =============================================================== the bank
## Thirteen instruments that between them cover a song: leads with real
## envelopes, a filtered bass, a pad that opens, and drums built out of
## pitch envelopes and filtered noise rather than a single click.
static func default_bank() -> Array:
	var out: Array = []
	var i := Inst.new()
	i.name = "PULSE LEAD"
	i.wave = W_PULSE
	i.duty = 0.35
	i.pwm_rate = 0.7
	i.pwm_depth = 0.12
	i.atk = 0.004
	i.dec = 0.09
	i.sus = 0.75
	i.rel = 0.10
	i.vib_depth = 0.22
	i.cut = 0.75
	i.res = 0.15
	i.delay_send = 0.25
	out.append(i)

	i = Inst.new()
	i.name = "SOFT PULSE"
	i.wave = W_PULSE
	i.duty = 0.18
	i.atk = 0.02
	i.dec = 0.2
	i.sus = 0.55
	i.rel = 0.2
	i.cut = 0.45
	i.res = 0.2
	i.cut_env = 0.35
	i.cut_time = 0.25
	i.pan = -0.25
	i.room_send = 0.3
	out.append(i)

	i = Inst.new()
	i.name = "TRI BASS"
	i.wave = W_TRI
	i.atk = 0.002
	i.dec = 0.14
	i.sus = 0.85
	i.rel = 0.08
	i.cut = 0.32
	i.res = 0.1
	i.vol = 0.95
	out.append(i)

	i = Inst.new()
	i.name = "SAW LEAD"
	i.wave = W_SAW
	i.atk = 0.01
	i.dec = 0.18
	i.sus = 0.6
	i.rel = 0.16
	i.cut = 0.5
	i.res = 0.35
	i.cut_env = 0.4
	i.cut_time = 0.2
	i.vib_depth = 0.15
	i.delay_send = 0.3
	i.pan = 0.2
	out.append(i)

	i = Inst.new()
	i.name = "PAD"
	i.wave = W_SAW
	i.atk = 0.35
	i.dec = 0.5
	i.sus = 0.6
	i.rel = 0.6
	i.cut = 0.22
	i.res = 0.25
	i.cut_env = 0.3
	i.cut_time = 1.2
	i.vib_rate = 3.0
	i.vib_depth = 0.1
	i.room_send = 0.6
	i.vol = 0.5
	out.append(i)

	i = Inst.new()
	i.name = "ORGAN"
	i.wave = W_PULSE
	i.duty = 0.5
	i.atk = 0.008
	i.dec = 0.04
	i.sus = 0.9
	i.rel = 0.06
	i.cut = 0.6
	i.room_send = 0.25
	out.append(i)

	i = Inst.new()
	i.name = "BELL"
	i.wave = W_SINE
	i.atk = 0.001
	i.dec = 0.5
	i.sus = 0.0
	i.rel = 0.4
	i.pitch_env = 12.0
	i.pitch_time = 0.03
	i.delay_send = 0.45
	i.room_send = 0.4
	out.append(i)

	i = Inst.new()
	i.name = "KICK"
	i.wave = W_SINE
	i.atk = 0.001
	i.dec = 0.16
	i.sus = 0.0
	i.rel = 0.05
	i.pitch_env = 34.0            # the thump: a fast fall in pitch
	i.pitch_time = 0.045
	i.cut = 0.5
	i.noise_mix = 0.06
	i.vol = 1.0
	out.append(i)

	i = Inst.new()
	i.name = "SNARE"
	i.wave = W_TRI
	i.atk = 0.001
	i.dec = 0.13
	i.sus = 0.0
	i.rel = 0.08
	i.pitch_env = 8.0
	i.pitch_time = 0.03
	i.noise_mix = 0.72            # body plus a wash of noise, not just noise
	i.cut = 0.72
	i.res = 0.2
	i.room_send = 0.35
	out.append(i)

	i = Inst.new()
	i.name = "HAT"
	i.wave = W_METAL
	i.atk = 0.001
	i.dec = 0.045
	i.sus = 0.0
	i.rel = 0.02
	i.cut = 0.95
	i.noise_mix = 0.5
	i.vol = 0.5
	i.pan = 0.3
	out.append(i)

	i = Inst.new()
	i.name = "OPEN HAT"
	i.wave = W_METAL
	i.atk = 0.001
	i.dec = 0.22
	i.sus = 0.0
	i.rel = 0.12
	i.cut = 0.9
	i.noise_mix = 0.6
	i.vol = 0.45
	i.pan = -0.3
	i.room_send = 0.2
	out.append(i)

	i = Inst.new()
	i.name = "CLAP"
	i.wave = W_NOISE
	i.atk = 0.002
	i.dec = 0.1
	i.sus = 0.0
	i.rel = 0.09
	i.cut = 0.66
	i.res = 0.3
	i.room_send = 0.5
	i.vol = 0.7
	out.append(i)

	i = Inst.new()
	i.name = "TOM"
	i.wave = W_SINE
	i.atk = 0.001
	i.dec = 0.2
	i.sus = 0.0
	i.rel = 0.1
	i.pitch_env = 16.0
	i.pitch_time = 0.09
	i.noise_mix = 0.15
	i.cut = 0.6
	out.append(i)
	return out

# ============================================================== playback

var song: Song = null
var chans: Array = []
var playing: bool = false
var order_i: int = 0
var row: int = 0
var tick: int = 0
var volume: float = 0.7
var follow: bool = true            # tracker cursor rides the playhead
## A stock cabinet runs half the chip: four voices, no filters, no LFOs,
## no sends. The expansion board wakes the rest of it up.
var expanded: bool = false

func voices() -> int:
	return CHANS if expanded else 4
var cart_sfx: Array = []

var _ply: AudioStreamPlayer3D
var _gen: AudioStreamGenerator
var _pb: AudioStreamGeneratorPlayback = null
var _thread: Thread = null
var _mx := Mutex.new()
var _alive: bool = false
var _mix := PackedVector2Array()
var _tick_acc: float = 0.0
var _samples_per_tick: float = 200.0

# master effects
var _dl := PackedVector2Array()    # delay line
var _dl_i: int = 0
var _room := PackedFloat32Array()  # a small room, three combs and an allpass
var _room_i: int = 0
const ROOM_TAPS := [1123, 1523, 1877]
var _room_bufs: Array = []
var _ap := PackedFloat32Array()
var _ap_i: int = 0

func _ready() -> void:
	for i in CHANS:
		chans.append(Chan.new())
	_mix.resize(BLK)
	_dl.resize(int(SR))            # a full second of delay to draw from
	for tap in ROOM_TAPS:
		var b := PackedFloat32Array()
		b.resize(tap)
		_room_bufs.append(b)
	_ap.resize(331)
	song = demo_song()
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = SR
	_gen.buffer_length = 0.09
	_ply = AudioStreamPlayer3D.new()
	_ply.stream = _gen
	_ply.unit_size = 9.0
	_ply.max_distance = 34.0
	_ply.volume_db = -4.0
	add_child(_ply)
	_ply.play()
	_pb = _ply.get_stream_playback()
	_recalc_tempo()
	_alive = true
	_thread = Thread.new()
	_thread.start(_loop, Thread.PRIORITY_NORMAL)

func _exit_tree() -> void:
	_alive = false
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

func _recalc_tempo() -> void:
	# BPM means beats, not tracker rows: a beat is rows_per_beat rows and
	# a row is `speed` ticks, so a 3/4 song at 90 actually runs at 90.
	var rpb := float(maxi(1, song.rows_per_beat))
	var spd := float(maxi(1, song.speed))
	_samples_per_tick = SR * 60.0 / (float(maxi(20, song.bpm)) * rpb * spd)

## The audio thread. Everything below runs off the main loop, which is
## why a busy frame in the game never stutters the music.
func _loop() -> void:
	while _alive:
		if _pb == null:
			OS.delay_msec(20)
			continue
		var pushed := 0
		while _pb.get_frames_available() >= BLK and pushed < 6:
			_mx.lock()
			_block()
			_mx.unlock()
			_pb.push_buffer(_mix)
			pushed += 1
		if pushed == 0:
			OS.delay_msec(4)

var _pan_l := PackedFloat32Array()
var _pan_r := PackedFloat32Array()
var _vbuf := PackedFloat32Array()      # one voice, one block

## A block is rendered voice by voice rather than sample by sample: the
## instrument, its wave, its envelope times and its pan are read ONCE per
## voice per block instead of once per sample. Same output, a fraction of
## the work -- and eight voices with filters then fit in a few percent of
## a core.
func _block() -> void:
	if _pan_l.size() != CHANS:
		_pan_l.resize(CHANS)
		_pan_r.resize(CHANS)
	if _vbuf.size() != BLK:
		_vbuf.resize(BLK)
	# tick boundaries land on block boundaries; at 5.8ms a block that is
	# finer than any tracker row anybody writes
	_tick_acc += float(BLK)
	while _tick_acc >= _samples_per_tick:
		_tick_acc -= _samples_per_tick
		_do_tick()
	for i in BLK:
		_mix[i] = Vector2.ZERO
	var dl_l := PackedFloat32Array()
	var dl_r := PackedFloat32Array()
	var room := PackedFloat32Array()
	dl_l.resize(BLK)
	dl_r.resize(BLK)
	room.resize(BLK)
	for ci in voices():
		var c: Chan = chans[ci]
		if c.stage == 0 or c.mute:
			c.last_out = 0.0
			continue
		var inst: Inst = _inst(c.inst)
		var pan := clampf(inst.pan + c.pan, -1.0, 1.0)
		var lg := sqrt(0.5 * (1.0 - pan))
		var rg := sqrt(0.5 * (1.0 + pan))
		_render_voice(c, inst)
		var ds := inst.delay_send if expanded else 0.0
		var rs := inst.room_send if expanded else 0.0
		var peak := 0.0
		for i in BLK:
			var v := _vbuf[i]
			peak = maxf(peak, absf(v))
			_mix[i] += Vector2(v * lg, v * rg)
			if ds > 0.0:
				dl_l[i] += v * lg * ds
				dl_r[i] += v * rg * ds
			if rs > 0.0:
				room[i] += v * rs
		c.last_out = peak
	# --- master: delay, room, soft clip
	var dtaps := maxi(64, int(song.delay_time * SR))
	var fb := clampf(song.delay_fb, 0.0, 0.85)
	var dsize := _dl.size()
	var rsize := ROOM_TAPS.size()
	for i in BLK:
		var di := (_dl_i - dtaps + dsize) % dsize
		var echo: Vector2 = _dl[di]
		var l := _mix[i].x + echo.x
		var r := _mix[i].y + echo.y
		_dl[_dl_i] = Vector2(clampf(dl_l[i] + echo.y * fb, -3.0, 3.0),
			clampf(dl_r[i] + echo.x * fb, -3.0, 3.0))
		_dl_i = (_dl_i + 1) % dsize
		if expanded and song.room > 0.001:
			var wet := 0.0
			for k in rsize:
				var buf: PackedFloat32Array = _room_bufs[k]
				var idx := _room_i % buf.size()
				var v2 := buf[idx]
				wet += v2
				buf[idx] = clampf(room[i] + v2 * 0.72, -3.0, 3.0)
				_room_bufs[k] = buf
			wet *= 0.33
			var ai := _ap_i % _ap.size()
			var av := _ap[ai]
			var out_ap := -wet + av
			_ap[ai] = wet + av * 0.5
			_ap_i += 1
			l += out_ap * song.room
			r += out_ap * song.room * 0.9
		_room_i += 1
		l = _soft(l * volume)
		r = _soft(r * volume)
		if not is_finite(l):
			l = 0.0
		if not is_finite(r):
			r = 0.0
		_mix[i] = Vector2(l, r)

## One voice, one block, straight into _vbuf.
func _render_voice(c: Chan, inst: Inst) -> void:
	var dt := 1.0 / SR
	var wave := inst.wave
	var nmix := inst.noise_mix
	var ivol := inst.vol
	var atk := maxf(0.0005, inst.atk)
	var dec := maxf(0.0005, inst.dec)
	var sus := inst.sus
	var rel := maxf(0.0005, inst.rel)
	var has_filter: bool = expanded and (inst.cut < 0.99 or inst.cut_env != 0.0)
	var samp_n := inst.sample.size()
	var samp_ratio := 1.0
	if wave == W_SAMPLE and samp_n > 4:
		samp_ratio = 1.0 / (440.0 * pow(2.0, (inst.sample_base - 57.0) / 12.0))
	for i in BLK:
		if c.stage == 0:
			_vbuf[i] = 0.0
			continue
		c.t_on += dt
		# --- control rate
		if c.ctl_i <= 0:
			c.ctl_i = CTL
			var semi := c.note
			var mods := expanded
			if c.slide != 0.0 and c.target_note >= 0.0:
				var d := c.slide * dt * float(CTL)
				if c.note < c.target_note:
					c.note = minf(c.target_note, c.note + d)
				else:
					c.note = maxf(c.target_note, c.note - d)
				semi = c.note
			if inst.pitch_env != 0.0:
				semi += inst.pitch_env * exp(-c.t_on / maxf(0.001, inst.pitch_time))
			if mods and inst.vib_depth > 0.0 and c.t_on > inst.vib_delay:
				c.lfo += TAU * inst.vib_rate * dt * float(CTL)
				semi += sin(c.lfo) * inst.vib_depth
			var f0 := clampf(440.0 * pow(2.0, (semi - 57.0) / 12.0), 8.0, SR * 0.48)
			c.c_step = f0 / SR
			var fc0 := inst.cut
			if inst.cut_env != 0.0:
				fc0 = clampf(fc0 + inst.cut_env
					* exp(-c.t_on / maxf(0.001, inst.cut_time)), 0.02, 1.0)
			c.c_fc = minf(0.9, 2.0 * sin(PI * clampf(fc0, 0.005, 0.32) * 0.5))
			c.c_duty = inst.duty
			if mods and inst.pwm_depth > 0.0:
				c.pwm_phase += TAU * inst.pwm_rate * dt * float(CTL)
				c.c_duty = clampf(inst.duty + sin(c.pwm_phase) * inst.pwm_depth,
					0.05, 0.95)
		c.ctl_i -= 1
		# --- oscillator
		var s := 0.0
		if wave == W_SAMPLE and samp_n > 4:
			c.samp_pos += c.c_step * SR * samp_ratio
			if c.samp_pos >= float(samp_n):
				if inst.sample_loop:
					c.samp_pos = fmod(c.samp_pos, float(samp_n))
				else:
					c.samp_pos = float(samp_n - 1)
			s = inst.sample[int(c.samp_pos)]
		else:
			c.phase += c.c_step
			if c.phase >= 1.0:
				c.phase -= floor(c.phase)
			if wave == W_PULSE:
				s = 1.0 if c.phase < c.c_duty else -1.0
			elif wave == W_TRI:
				s = 4.0 * absf(c.phase - 0.5) - 1.0
			elif wave == W_SAW:
				s = 2.0 * c.phase - 1.0
			elif wave == W_SINE:
				s = sin(TAU * c.phase)
			elif wave == W_NOISE:
				c.lfsr = _lfsr_step(c.lfsr)
				s = 1.0 if (c.lfsr & 1) != 0 else -1.0
			else:
				c.lfsr = _lfsr_step(c.lfsr)
				c.lfsr2 = _lfsr_step2(c.lfsr2)
				s = 1.0 if ((c.lfsr ^ c.lfsr2) & 1) != 0 else -1.0
		if nmix > 0.0:
			c.lfsr = _lfsr_step(c.lfsr)
			var n := 1.0 if (c.lfsr & 1) != 0 else -1.0
			s = lerpf(s, n, nmix)
		# --- envelope
		if c.stage == 1:
			c.env += dt / atk
			if c.env >= 1.0:
				c.env = 1.0
				c.stage = 2
		elif c.stage == 2:
			c.env -= dt / dec * (1.0 - sus)
			if c.env <= sus:
				c.env = sus
				c.stage = 3 if sus > 0.001 else 0
		elif c.stage == 4:
			c.env -= dt / rel
			if c.env <= 0.0:
				c.env = 0.0
				c.stage = 0
		s *= c.env * c.vol * ivol
		# --- filter
		if has_filter:
			var f := c.c_fc
			var q := clampf(1.0 - inst.res * 0.9, 0.12, 1.0)
			c.lp1 += f * c.bp1
			var hp := s - c.lp1 - q * c.bp1
			c.bp1 += f * hp
			if absf(c.lp1) > 8.0 or absf(c.bp1) > 8.0 or not is_finite(c.lp1):
				c.lp1 = 0.0
				c.bp1 = 0.0
			s = c.lp1
		_vbuf[i] = 0.0 if not is_finite(s) else clampf(s, -1.6, 1.6)

static func _soft(x: float) -> float:
	if x > 1.0 or x < -1.0:
		return signf(x) * (1.0 - 1.0 / (1.0 + absf(x)))
	return x - x * x * x * 0.16

func _inst(i: int) -> Inst:
	if song == null or song.insts.is_empty():
		return Inst.new()
	return song.insts[clampi(i, 0, song.insts.size() - 1)]

## One sample of one voice: oscillator, noise blend, envelopes, filter.
const CTL := 16                   # samples between control updates

static func _lfsr_step(v: int) -> int:
	var bit := ((v >> 0) ^ (v >> 1)) & 1
	return ((v >> 1) | (bit << 14)) & 0x7FFF

static func _lfsr_step2(v: int) -> int:
	var bit := ((v >> 0) ^ (v >> 6)) & 1
	return ((v >> 1) | (bit << 14)) & 0x7FFF

# ---------------------------------------------------------------- ticks

func _do_tick() -> void:
	if not playing or song == null:
		_tick_fx()
		return
	if tick == 0:
		_play_row()
	_tick_fx()
	tick += 1
	if tick >= maxi(1, song.speed):
		tick = 0
		row += 1
		if row >= song.rows:
			row = 0
			order_i += 1
			if order_i >= song.order.size():
				order_i = 0
	_jump_pending()

var _jump_to: int = -1
var _break_to: int = -1

func _jump_pending() -> void:
	if _jump_to >= 0:
		order_i = clampi(_jump_to, 0, maxi(0, song.order.size() - 1))
		row = 0
		_jump_to = -1
	if _break_to >= 0:
		row = clampi(_break_to, 0, song.rows - 1)
		order_i = (order_i + 1) % maxi(1, song.order.size())
		_break_to = -1

func _play_row() -> void:
	var pat := int(song.order[clampi(order_i, 0, song.order.size() - 1)])
	for ch in CHANS:
		var cell := song.cell(pat, row, ch)
		var c: Chan = chans[ch]
		var n := int(cell[0])
		c.fx = int(cell[3])
		c.fx_p = int(cell[4])
		if int(cell[1]) > 0:
			c.inst = int(cell[1]) - 1
		if int(cell[2]) > 0:
			c.vol = clampf(float(cell[2] - 1) / 64.0, 0.0, 1.0)
		if n == 1:
			c.stage = 4                     # note off: into release
		elif n >= 2:
			var semi := float(n - 2)
			if c.fx == 3:                   # portamento: glide, do not retrigger
				c.target_note = semi
				c.slide = float(maxi(1, c.fx_p)) * 0.6
			else:
				_trigger(c, semi)
		if c.fx == 8:
			c.pan = clampf(float(c.fx_p - 32) / 32.0, -1.0, 1.0)
		if c.fx == 11:
			_jump_to = c.fx_p
		if c.fx == 13:
			_break_to = c.fx_p
		if c.fx == 15 and c.fx_p > 0:
			song.speed = c.fx_p
			_recalc_tempo()
		c.arp_i = 0

func _trigger(c: Chan, semi: float) -> void:
	c.note = semi
	c.target_note = semi
	c.slide = 0.0
	c.stage = 1
	c.env = 0.0
	c.t_on = 0.0
	c.lfo = 0.0
	c.samp_pos = 0.0
	c.phase = 0.0
	c.ctl_i = 0

## Per-tick effects: the ones that move something between rows.
func _tick_fx() -> void:
	for ch in CHANS:
		var c: Chan = chans[ch]
		if c.stage == 0:
			continue
		match c.fx:
			0:
				# arpeggio: three notes rotating every tick
				if c.fx_p > 0:
					var x := (c.fx_p >> 4) & 0xF
					var y := c.fx_p & 0xF
					c.arp_i = (c.arp_i + 1) % 3
					var base := c.target_note
					c.note = base + (0.0 if c.arp_i == 0 else
						(float(x) if c.arp_i == 1 else float(y)))
			1:
				c.note += float(c.fx_p) * 0.06
			2:
				c.note -= float(c.fx_p) * 0.06
			10:
				var up := (c.fx_p >> 4) & 0xF
				var dn := c.fx_p & 0xF
				c.vol = clampf(c.vol + float(up) * 0.02 - float(dn) * 0.02, 0.0, 1.0)
			12:
				if c.fx_p > 0 and tick >= c.fx_p:
					c.stage = 4

# =============================================================== the api

func load_cart(cart: ArcadeCart) -> void:
	_mx.lock()
	if cart.song.is_empty():
		song = demo_song()
	else:
		song = Song.from_dict(cart.song)
	cart_sfx = cart.sfx
	_recalc_tempo()
	_mx.unlock()

func set_song(s: Song) -> void:
	_mx.lock()
	song = s
	_recalc_tempo()
	_mx.unlock()

func play_music(from_order: int = 0, _fade: float = 0.0) -> void:
	_mx.lock()
	order_i = clampi(from_order, 0, maxi(0, song.order.size() - 1))
	row = 0
	tick = 0
	playing = true
	_mx.unlock()

func stop_music() -> void:
	_mx.lock()
	playing = false
	for c in chans:
		(c as Chan).stage = 4
	_mx.unlock()

func toggle() -> void:
	if playing:
		stop_music()
	else:
		play_music(order_i)

## A cartridge sound effect: a short run of notes on a spare channel.
func play_sfx(n: int, chan: int = -1) -> void:
	_mx.lock()
	var ch := chan if chan >= 0 else CHANS - 1
	var c: Chan = chans[ch % CHANS]
	var d: Dictionary = {}
	if n >= 0 and n < cart_sfx.size() and cart_sfx[n] is Dictionary:
		d = cart_sfx[n]
	c.inst = int(d.get("inst", 6))
	c.vol = float(d.get("vol", 0.7))
	_trigger(c, float(d.get("note", 60)))
	_mx.unlock()

func play_note(ch: int, semi: float, vol: float, inst: int = 0) -> void:
	_mx.lock()
	var c: Chan = chans[clampi(ch, 0, CHANS - 1)]
	c.inst = clampi(inst, 0, maxi(0, song.insts.size() - 1))
	c.vol = clampf(vol, 0.0, 1.0)
	_trigger(c, semi)
	_mx.unlock()

## Audition one note from the tracker, without disturbing playback.
func preview(inst: int, semi: float) -> void:
	play_note(CHANS - 1, semi, 0.8, inst)

func meters() -> Array:
	var out: Array = []
	for c in chans:
		out.append(absf((c as Chan).last_out))
	return out

func position() -> Array:
	return [order_i, row, tick]

# ------------------------------------------------------- the demo song
## Something the machine can play the moment it is switched on: drums,
## a bass line, a pad and a lead, four patterns of it.
static func demo_song() -> Song:
	var s := Song.new()
	s.title = "ATTRACT"
	s.bpm = 124
	s.speed = 6
	s.rows = 64
	s.rows_per_beat = 4
	s.sig_num = 4
	s.insts = default_bank()
	s.order = [0, 1, 0, 2]
	# widen the mix: the drums hold the middle, everything else has a
	# side of the room to sit on
	s.insts[1].pan = -0.45          # soft pulse, left
	s.insts[3].pan = 0.4            # saw lead, right
	s.insts[4].pan = -0.2           # pad, a little left
	s.insts[6].pan = 0.35           # bell, right
	s.insts[9].pan = 0.5            # hat
	s.insts[10].pan = -0.5          # open hat
	s.insts[11].pan = 0.3           # clap
	for p in 3:
		s.pattern(p)
	var bass := [36, 36, 43, 36, 39, 39, 34, 34]
	var lead := [72, 75, 79, 75, 77, 72, 70, 67]
	for p in 3:
		for r in 64:
			if r % 8 == 0:
				s.set_cell(p, r, 0, [36 + 2, 8, 0, 0, 0])
			if r % 16 == 8:
				s.set_cell(p, r, 1, [48 + 2, 9, 0, 0, 0])
			if r % 4 == 2:
				s.set_cell(p, r, 2, [60 + 2, 10, 40, 0, 0])
			if r % 32 == 30 and p > 0:
				s.set_cell(p, r, 1, [50 + 2, 12, 0, 0, 0])
			if r % 4 == 0:
				var bn: int = int(bass[(r / 4) % 8]) + 2
				# every fourth bass note glides into the next one
				var fx := 3 if (r / 4) % 4 == 3 else 0
				s.set_cell(p, r, 3, [bn, 3, 0, fx, 6 if fx == 3 else 0])
			if r % 16 == 0:
				var root: int = int(bass[(r / 4) % 8]) + 12
				s.set_cell(p, r, 4, [root + 2, 5, 30, 0, 0])
				s.set_cell(p, r, 5, [root + 7 + 2, 5, 26, 0, 0])
			if p > 0 and r % 8 == 4:
				# the lead arpeggiates on the long notes
				var ln: int = int(lead[(r / 8) % 8]) + 2
				s.set_cell(p, r, 6, [ln, 1, 48, 0 if r % 16 == 4 else 0,
					0x37 if r % 16 == 4 else 0])
			if p == 2 and r % 8 == 6:
				s.set_cell(p, r, 7, [int(lead[(r / 8) % 8]) - 12 + 2, 4, 36, 0, 0])
	return s

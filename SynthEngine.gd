class_name SynthEngine
extends RefCounted
## THE DSP. A real modular synthesizer: every module is a block of
## samples, every cable is a pointer from one module's output block to
## another's input, and the whole rack is evaluated in dependency order
## once per audio block. Patch a feedback loop and you get exactly what
## a feedback loop gives you -- last block's signal, one block late.
##
## Signals are VOLTS, eurorack style: audio swings +-5V, pitch is
## 1V/octave with 0V = C4, gates are 0V/5V. Nothing is normalised away.
##
## Runs on its own thread and pushes into an AudioStreamGenerator, so
## the game never hitches for the sound. All patch edits go through
## methods that take the same mutex the audio loop holds -- edit the
## rack live while it plays.

const SR := 22050.0
const BLK := 64          # samples per processing block (2.9 ms)
const MAXIN := 8
const MAXOUT := 6
const SUB := 16          # coefficient update rate inside a block
const C4 := 261.6256
## What counts as a gate. Real gear calls anything over about a volt
## high; the old test was "> 1.0", which meant a CONSTANTS module left
## at its default 1.0 V sat exactly ON the threshold and never opened
## anything -- an arpeggiator held open by one read as permanently shut.
const GATE_HI := 0.8

class Mod extends RefCounted:
	var id: String = "vca"
	var brand: String = "dude"
	var row: int = 0
	var hp: int = 0                        # left edge, in HP
	var p := PackedFloat32Array()          # knobs, 0..1
	var sw := PackedInt32Array()           # switch positions
	var st := PackedFloat32Array()         # widget data (sequencer steps...)
	var s := PackedFloat32Array()          # scalar DSP state
	var d := PackedFloat32Array()          # delay lines / scope ring
	var kv := PackedFloat32Array()         # knobs converted to real units
	var kdirty := true
	var led: float = 0.0                   # panel activity lamp, 0..1
	var name_tag: String = ""
	## The faceplate's own artwork seed. Rolled when the panel is built
	## and carried in the save: moving a module around the rack must not
	## repaint it, and the same panel must look the same tomorrow.
	var art: int = 0

	func width() -> int:
		return int(SynthMods.def(id)["hp"])

var mods: Array = []          # Array[Mod]
var cables: Array = []        # {sm, so, dm, di, col}
var version: int = 0          # bumped on every structural change

var _bus := PackedFloat32Array()
var _src := PackedInt32Array()      # per module input -> bus block offset
var _pat := PackedByteArray()       # ...and whether it is patched at all
var _order := PackedInt32Array()
var _outL := PackedFloat32Array()
var _outR := PackedFloat32Array()
var _mix := PackedVector2Array()
var _rng := RandomNumberGenerator.new()
var _mx := Mutex.new()
var _thread: Thread = null
var _alive := false
var _pb: AudioStreamGeneratorPlayback = null
## Radios listening to this rack's broadcast. Each gets its own playback
## fed the same master mix, so a station is heard AT the listening set.
var _casts: Array = []
var cast_level: float = 0.0
## Module ids the DSP does not implement. Empty is the only acceptable
## value; CTD_TEST=27 checks it.
var unhandled: Dictionary = {}
## Case capacity. A Mk1 case is three rows of 84 HP; the Mk2 is twice as
## wide and one row taller, and the rack simply asks the engine how big
## it is rather than hard-coding a size anywhere.
var rows: int = SynthMods.ROWS
var row_hp: int = SynthMods.ROW_HP

var master: float = 1.0             # machine-side fade (power, distance)
## NEAR, TIME, POWER, WRATH -- written by the machine each frame, read
## by any WORLD SENSOR panel in the rack.
var world := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var cpu: float = 0.0                # fraction of realtime the DSP eats
var _blocks: int = 0
var running := false

## Patch format. 1 = before the CV-jack rework (jack order changed), 2 =
## after it, 3 = cables carry jack NAMES so no future reorder can move a
## cable onto the wrong socket again.
const PATCH_VERSION := 3

## Where each module's inputs MOVED in the CV-jack rework. Old index ->
## new index, so a rack patched before it still plays after it.
const LEGACY_IN := {
	"vcf": [3, 0, 1], "vca": [1, 0], "vco": [0, 2, 3, 4], "lfo": [0, 3],
	"adsr": [4, 5], "drum": [4, 5, 0], "delay": [3, 0], "reverb": [3],
}
## How many inputs those panels had BEFORE the rework. A patch that
## uses a higher input index than this was clearly built AFTER it, and
## must not be remapped -- doing that moved audio cables onto CV jacks
## and left the voice silent while self-contained modules kept playing.
const LEGACY_IN_COUNT := {
	"vcf": 3, "vca": 2, "vco": 4, "lfo": 2, "adsr": 2, "drum": 3,
	"delay": 2, "reverb": 1,
}
const LEGACY_KNOB := {
	"vcf": [0, 1, -1, 2], "delay": [0, 1, 2, -1], "roll": [0, 2, 3],
}

const CABLE_COLS: Array[Color] = [Color("#ff5964"), Color("#ffd166"),
	Color("#3aff6a"), Color("#5ad0ff"), Color("#b388ff"), Color("#ff7ce9"),
	Color("#ffffff"), Color("#ff9a3c")]

func _init() -> void:
	_rng.randomize()
	_outL.resize(BLK)
	_outR.resize(BLK)
	_mix.resize(BLK)

# ============================================================ patch edits

func mod_count() -> int:
	return mods.size()

## Room for a module of `hp` width in `row`, at or after `want_hp`.
func free_slot(w: int, want_row: int = -1, want_hp: int = -1) -> Vector2i:
	for r in rows:
		var row: int = (want_row + r) % rows if want_row >= 0 else r
		var occ := PackedByteArray()
		occ.resize(row_hp)
		occ.fill(0)
		for m in mods:
			if m.row != row:
				continue
			for x in range(m.hp, mini(m.hp + m.width(), row_hp)):
				occ[x] = 1
		var start: int = maxi(0, want_hp) if (r == 0 and want_hp >= 0) else 0
		for pass_i in 2:
			var x0: int = start if pass_i == 0 else 0
			var x := x0
			while x + w <= row_hp:
				var ok := true
				for k in w:
					if occ[x + k] == 1:
						ok = false
						x += k + 1
						break
				if ok:
					return Vector2i(row, x)
			if want_hp < 0:
				break
	return Vector2i(-1, -1)

func make_mod(id: String, brand: String = "dude") -> Mod:
	var d := SynthMods.def(id)
	var m := Mod.new()
	m.id = id
	m.brand = brand
	m.art = _rng.randi() % 1000000
	var kn: Array = d["knobs"]
	m.p.resize(kn.size())
	for i in kn.size():
		m.p[i] = SynthMods.knob_norm(kn[i], float(kn[i]["def"]))
	var sws: Array = d["sw"]
	m.sw.resize(sws.size())
	for i in sws.size():
		m.sw[i] = int(sws[i]["def"])
	m.kv.resize(kn.size())
	m.s.resize(48)      # the analysers keep twelve bands up in the top half
	m.s.fill(0.0)
	match str(d["widget"]):
		"seq8":
			m.st.resize(16)
			for i in 8:
				m.st[i] = 0.5             # pitch, 0..1
				m.st[8 + i] = 1.0         # gate on
		"column":
			# ...plus one slot on the end holding which column is selected
			var nsc: int = int(d.get("steps", 8)) * int(d.get("patterns", 1))
			m.st.resize(nsc + 1)
			m.st.fill(0.0)
			for i in [0, 3, 5]:
				m.st[i] = 1.0
		"kit":
			m.st.resize(8 * 16)
			m.st.fill(0.0)
			for i in [0, 4, 8, 12]:
				m.st[i] = 1.0                    # kick on the beat
			for i in [4, 12]:
				m.st[16 + i] = 1.0               # snare on 2 and 4
			for i in range(0, 16, 2):
				m.st[32 + i] = 1.0               # closed hat on eighths
		"dseq":
			m.st.resize(64)
			m.st.fill(0.0)
			for i in [0, 4, 8, 12]:
				m.st[i] = 1.0             # a kick on every beat, to start
		"grid":
			# four lanes of sixteen WEIGHTS, four patterns deep
			m.st.resize(4 * 16 * 4)
			m.st.fill(0.0)
			for i in [0, 4, 8, 12]:
				m.st[i] = 1.0                    # lane 1: certain, on the beat
			for i in [4, 12]:
				m.st[16 + i] = 0.85              # lane 2: nearly always
			for i in range(0, 16, 2):
				m.st[32 + i] = 0.55              # lane 3: a coin toss on eighths
			for i in [3, 7, 10, 14]:
				m.st[48 + i] = 0.3               # lane 4: now and then
		"muse":
			# sixteen notes and sixteen gates of whatever it last wrote
			m.st.resize(32)
			m.st.fill(0.0)
		"chords":
			m.st.resize(8)                       # the degrees of the progression
			m.st.fill(0.0)
		"seqn":
			var ns: int = int(d.get("steps", 8))
			m.st.resize(ns * 2)
			for i in ns:
				m.st[i] = 0.5
				m.st[ns + i] = 1.0
		"roll":
			var npat: int = int(d.get("patterns", 1))
			m.st.resize(16 * npat)
			m.st.fill(-1.0)
			for i in [0, 4, 8, 12]:
				m.st[i] = 0.0
		"bars":
			var nb2: int = int(d.get("steps", 20))
			m.st.resize(nb2)
			for i in nb2:
				m.st[i] = 1.0 / float(i + 1)      # a saw, to start
		"desk":
			m.st.resize(6)          # one mute per channel
			m.st.fill(0.0)
		"buttons":
			m.st.resize(4)
			m.st.fill(0.0)
		"xy":
			m.st.resize(3)
			m.st[0] = 0.5
			m.st[1] = 0.5
		"vkeys":
			m.st.resize(3)
			m.st[0] = -1.0
			m.st[2] = 0.0        # octave, set by the slider across the top
		"keys":
			m.st.resize(2)
			m.st[0] = -1.0
	match id:
		"delay":
			m.d.resize(int(SR * 2.0) + 4)
		"reverb":
			m.d.resize(_rev_total())
		"scope", "vector", "analyser":
			m.d.resize(1024)
		"waterfall":
			m.d.resize(12 * 64)      # twelve bands, sixty-four columns of history
		"cosmic":
			m.d.resize(_cosmic_total())
		"tape", "grains", "slab":
			m.d.resize(int(SR * 2.0) + 4)
		"freeze", "dustgate":
			m.d.resize(int(SR * 1.2) + 4)
		"resonator":
			m.d.resize(2048 * 3)
	if m.d.size() > 0:
		m.d.fill(0.0)
	return m

func add_mod(id: String, brand: String = "dude", row: int = -1, hp: int = -1) -> int:
	if not SynthMods.has(id):
		return -1
	var m := make_mod(id, brand)
	var slot := free_slot(m.width(), row, hp)
	if slot.x < 0:
		return -1
	m.row = slot.x
	m.hp = slot.y
	_mx.lock()
	mods.append(m)
	_compile()
	_mx.unlock()
	return mods.size() - 1

## Clone a panel -- same house, same knobs, same switches, same pattern
## data -- into the first free space in the rack.
func duplicate_mod(mi: int) -> int:
	if mi < 0 or mi >= mods.size():
		return -1
	var src: Mod = mods[mi]
	var m := make_mod(src.id, src.brand)
	for i in mini(src.p.size(), m.p.size()):
		m.p[i] = src.p[i]
	for i in mini(src.sw.size(), m.sw.size()):
		m.sw[i] = src.sw[i]
	m.art = _rng.randi() % 1000000
	if src.st.size() == m.st.size():
		for i in src.st.size():
			m.st[i] = src.st[i]
	var slot := free_slot(m.width(), src.row, src.hp + src.width())
	if slot.x < 0:
		return -1
	m.row = slot.x
	m.hp = slot.y
	_mx.lock()
	mods.append(m)
	_compile()
	_mx.unlock()
	return mods.size() - 1

func remove_mod(mi: int) -> void:
	if mi < 0 or mi >= mods.size():
		return
	_mx.lock()
	for c in cables.duplicate():
		if int(c["sm"]) == mi or int(c["dm"]) == mi:
			cables.erase(c)
	mods.remove_at(mi)
	for c in cables:
		if int(c["sm"]) > mi:
			c["sm"] = int(c["sm"]) - 1
		if int(c["dm"]) > mi:
			c["dm"] = int(c["dm"]) - 1
	_compile()
	_mx.unlock()

func move_mod(mi: int, row: int, hp: int) -> bool:
	if mi < 0 or mi >= mods.size():
		return false
	var m: Mod = mods[mi]
	var w := m.width()
	hp = clampi(hp, 0, row_hp - w)
	row = clampi(row, 0, rows - 1)
	for o in mods:
		if o == m or o.row != row:
			continue
		if hp < o.hp + o.width() and o.hp < hp + w:
			return false
	_mx.lock()
	m.row = row
	m.hp = hp
	version += 1
	_mx.unlock()
	return true

func set_brand(mi: int, brand: String) -> void:
	if mi < 0 or mi >= mods.size() or not SynthMods.BRANDS.has(brand):
		return
	_mx.lock()
	mods[mi].brand = brand
	mods[mi].kdirty = true
	version += 1
	_mx.unlock()

## One cable per INPUT jack (stack with a mult, like the real thing);
## an output may fan out to as many inputs as you like.
func patch(sm: int, so: int, dm: int, di: int) -> bool:
	if sm < 0 or dm < 0 or sm >= mods.size() or dm >= mods.size():
		return false
	var sd := SynthMods.def(mods[sm].id)
	var dd := SynthMods.def(mods[dm].id)
	if so < 0 or so >= (sd["outs"] as Array).size():
		return false
	if di < 0 or di >= (dd["ins"] as Array).size():
		return false
	_mx.lock()
	for c in cables.duplicate():
		if int(c["dm"]) == dm and int(c["di"]) == di:
			cables.erase(c)
	cables.append({"sm": sm, "so": so, "dm": dm, "di": di,
		"col": cables.size() % CABLE_COLS.size()})
	_compile()
	_mx.unlock()
	return true

## Yank every cable touching a jack. Returns how many died.
func unpatch(mi: int, is_input: bool, ji: int) -> int:
	var n := 0
	_mx.lock()
	for c in cables.duplicate():
		if is_input and int(c["dm"]) == mi and int(c["di"]) == ji:
			cables.erase(c)
			n += 1
		elif not is_input and int(c["sm"]) == mi and int(c["so"]) == ji:
			cables.erase(c)
			n += 1
	if n > 0:
		_compile()
	_mx.unlock()
	return n

func clear_cables() -> void:
	_mx.lock()
	cables.clear()
	_compile()
	_mx.unlock()

func clear_patch() -> void:
	_mx.lock()
	mods.clear()
	cables.clear()
	_compile()
	_mx.unlock()

func set_knob(mi: int, ki: int, v: float) -> void:
	if mi < 0 or mi >= mods.size():
		return
	var m: Mod = mods[mi]
	if ki < 0 or ki >= m.p.size():
		return
	m.p[ki] = clampf(v, 0.0, 1.0)
	m.kdirty = true

func set_sw(mi: int, si: int, v: int) -> void:
	if mi < 0 or mi >= mods.size():
		return
	var m: Mod = mods[mi]
	if si < 0 or si >= m.sw.size():
		return
	m.sw[si] = v
	m.kdirty = true

func set_step(mi: int, i: int, v: float) -> void:
	if mi < 0 or mi >= mods.size():
		return
	var m: Mod = mods[mi]
	if i < 0 or i >= m.st.size():
		return
	m.st[i] = v

## The panel keyboard: note is a semitone index, -1 releases. `vel` is
## how hard it was struck, 0..1 (the vertical keyboard reads it off how
## far along the key you clicked).
func key_press(mi: int, note: float, on: bool, vel: float = 0.8) -> void:
	if mi < 0 or mi >= mods.size():
		return
	var m: Mod = mods[mi]
	if not (m.id == "keys" or m.id == "vkeys") or m.st.size() < 2:
		return
	if m.st.size() > 2:
		m.st[2] = clampf(vel, 0.05, 1.0)
	if on:
		m.st[0] = note
		m.st[1] = 1.0
	else:
		m.st[1] = 0.0

## A panel button: momentary gate, plus a latch that flips on press.
func press_button(mi: int, bi: int, on: bool) -> void:
	if mi < 0 or mi >= mods.size():
		return
	var m: Mod = mods[mi]
	if m.id != "button" or m.st.size() < 4:
		return
	var gi := bi * 2
	if on and m.st[gi] <= 0.5:
		m.st[gi + 1] = 0.0 if m.st[gi + 1] > 0.5 else 1.0
	m.st[gi] = 1.0 if on else 0.0

## The XY pad's puck, in 0..1 panel coordinates.
func set_xy(mi: int, x: float, y: float, held: bool) -> void:
	if mi < 0 or mi >= mods.size():
		return
	var m: Mod = mods[mi]
	if m.id != "xy" or m.st.size() < 3:
		return
	m.st[0] = clampf(x, 0.0, 1.0)
	m.st[1] = clampf(y, 0.0, 1.0)
	m.st[2] = 1.0 if held else 0.0

func knob_value(mi: int, ki: int) -> float:
	var m: Mod = mods[mi]
	var kn: Array = SynthMods.def(m.id)["knobs"]
	return SynthMods.knob_val(kn[ki], m.p[ki])

## Live voltage on a jack, for the editor's probe readout.
func jack_volts(mi: int, is_input: bool, ji: int) -> float:
	if mi < 0 or mi >= mods.size():
		return 0.0
	if is_input:
		var srci := _src[mi * MAXIN + ji] if mi * MAXIN + ji < _src.size() else 0
		if srci <= 0:
			return 0.0
		return _bus[srci + BLK - 1]
	var base := (1 + mi * MAXOUT + ji) * BLK
	if base + BLK - 1 >= _bus.size():
		return 0.0
	return _bus[base + BLK - 1]

func cable_at_input(mi: int, di: int) -> Dictionary:
	for c in cables:
		if int(c["dm"]) == mi and int(c["di"]) == di:
			return c
	return {}

# ============================================================== compiling

func _compile() -> void:
	var nm := mods.size()
	_bus.resize((1 + nm * MAXOUT) * BLK)
	_bus.fill(0.0)
	_src.resize(nm * MAXIN)
	_src.fill(0)
	_pat.resize(nm * MAXIN)
	_pat.fill(0)
	for c in cables:
		var dm := int(c["dm"])
		var di := int(c["di"])
		var sm := int(c["sm"])
		var so := int(c["so"])
		if dm >= nm or sm >= nm:
			continue
		_src[dm * MAXIN + di] = (1 + sm * MAXOUT + so) * BLK
		_pat[dm * MAXIN + di] = 1
	# dependency order: depth-first, cycles simply read last block's
	# values -- which is precisely what a patched feedback loop does
	var mark := PackedByteArray()
	mark.resize(nm)
	mark.fill(0)
	var ord: Array[int] = []
	for i in nm:
		if mark[i] == 0:
			_visit(i, mark, ord)
	_order.resize(ord.size())
	for i in ord.size():
		_order[i] = ord[i]
	for m in mods:
		m.kdirty = true
	version += 1

func _visit(i: int, mark: PackedByteArray, ord: Array[int]) -> void:
	if mark[i] != 0:
		return
	mark[i] = 1                    # on the stack
	for k in MAXIN:
		var s := _src[i * MAXIN + k]
		if s <= 0:
			continue
		var srcm := (s / BLK - 1) / MAXOUT
		if srcm >= 0 and srcm < mods.size() and mark[srcm] == 0:
			_visit(srcm, mark, ord)
	mark[i] = 2
	ord.append(i)

func _refresh_kv(m: Mod) -> void:
	var kn: Array = SynthMods.def(m.id)["knobs"]
	for i in mini(kn.size(), m.p.size()):
		m.kv[i] = SynthMods.knob_val(kn[i], m.p[i])
	m.kdirty = false

# ============================================================== the sound

func start(pb: AudioStreamGeneratorPlayback) -> void:
	_pb = pb
	if _thread != null:
		return
	_alive = true
	_thread = Thread.new()
	_thread.start(_loop, Thread.PRIORITY_HIGH)

func stop() -> void:
	_alive = false
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_pb = null

func _loop() -> void:
	while _alive:
		var pb := _pb
		if pb == null or not running:
			OS.delay_msec(20)
			continue
		var pushed := 0
		# never run more than a handful of blocks ahead of the speakers --
		# a deep queue is pure latency between a step lighting up and the
		# note arriving
		while pb.get_frames_available() >= BLK and pushed < 4:
			var t0 := Time.get_ticks_usec()
			_mx.lock()
			_block()
			_mx.unlock()
			pb.push_buffer(_mix)
			_feed_casts()
			var dt := float(Time.get_ticks_usec() - t0) / 1000000.0
			cpu = lerpf(cpu, dt / (float(BLK) / SR), 0.02)
			pushed += 1
		if pushed == 0:
			OS.delay_msec(3)

func add_cast(pb) -> void:
	if pb == null:
		return
	_mx.lock()
	if not _casts.has(pb):
		_casts.append(pb)
	_mx.unlock()

func remove_cast(pb) -> void:
	_mx.lock()
	_casts.erase(pb)
	_mx.unlock()

func cast_count() -> int:
	return _casts.size()

func _feed_casts() -> void:
	if _casts.is_empty():
		return
	_mx.lock()
	for pb in _casts:
		if pb != null and pb.get_frames_available() >= BLK:
			pb.push_buffer(_mix)
	_mx.unlock()

## One block: every module, in order, then whatever reached OUTPUT.
func _block() -> void:
	_blocks += 1
	for i in BLK:
		_outL[i] = 0.0
		_outR[i] = 0.0
	for oi in _order:
		_proc(oi)
	var g := master
	var pk2 := 0.0
	for i in BLK:
		var l := _outL[i] * g
		var r := _outR[i] * g
		# the speaker is not a wire: hard limit, softly
		l = l / (1.0 + absf(l) * 0.3)
		r = r / (1.0 + absf(r) * 0.3)
		_mix[i] = Vector2(clampf(l, -1.0, 1.0), clampf(r, -1.0, 1.0))
		pk2 = maxf(pk2, absf(l))
	cast_level = pk2

func _rev_total() -> int:
	var t := 0
	for n in REV_COMB:
		t += n + REV_SPREAD + 2
		t += n + 2
	for n in REV_AP:
		t += n + REV_SPREAD + 2
		t += n + 2
	return t

## The cosmic tank is longer than the plain one: six combs per side at
## nearly a tenth of a second each, plus a shimmer buffer.
const COS_COMB: Array[int] = [1731, 1867, 2029, 2131, 2287, 2411]
const COS_AP: Array[int] = [521, 383, 271, 193]
const COS_SHIM := 4096

## The scope captures more than it shows so the frame can be SLID into the
## position that best matches the frame before it. A trigger alone holds a
## picture still only when the signal repeats exactly; anything chaotic (or
## with several crossings per cycle) triggers on a different crossing every
## refresh and the trace crawls. Matching each frame against the last one
## holds it still whatever the signal does.
const CAP_LEN := 384                   # 256 shown + 128 of slack to slide in
const CAP_SLACK := CAP_LEN - 256

static func _align_frame(d: PackedFloat32Array, have_prev: bool) -> void:
	var best := 0
	if have_prev:
		var bestscore := -1e30
		var o := 0
		while o <= CAP_SLACK:
			var sc := 0.0
			var k := 0
			while k < 256:
				sc += d[k] * d[256 + o + k]
				k += 4             # every fourth point: same peak, quarter the cost
			# a slight pull toward the trigger point, so a silent or flat
			# input does not wander off chasing noise
			sc -= absf(float(o) - float(CAP_SLACK) * 0.5) * 0.00001
			if sc > bestscore:
				bestscore = sc
				best = o
			o += 1
	for k in 256:
		d[k] = d[256 + best + k]


static func _cosmic_total() -> int:
	var t := COS_SHIM
	for n in COS_COMB:
		t += (n + 64) + (n + 23 + 64)
	for n in COS_AP:
		t += (n + 64) + (n + 23 + 64)
	return t + 64

const REV_COMB: Array[int] = [558, 594, 638, 678, 717, 761]
const REV_AP: Array[int] = [278, 220, 174, 131]
const REV_SPREAD := 23

func _bl(t: float, dt: float) -> float:
	# polyBLEP: rounds off the discontinuity so a saw is a saw, not a
	# bucket of aliases
	if t < dt:
		var x := t / dt
		return x + x - x * x - 1.0
	if t > 1.0 - dt:
		var x2 := (t - 1.0) / dt
		return x2 * x2 + x2 + x2 + 1.0
	return 0.0

func _proc(mi: int) -> void:
	var m: Mod = mods[mi]
	if m.kdirty:
		_refresh_kv(m)
	var b := _bus
	var kv := m.kv
	var s := m.s
	var o0 := (1 + mi * MAXOUT) * BLK
	var i0 := _src[mi * MAXIN + 0]
	var i1 := _src[mi * MAXIN + 1]
	var i2 := _src[mi * MAXIN + 2]
	var i3 := _src[mi * MAXIN + 3]
	var peak := 0.0
	match m.id:
		# ------------------------------------------------------- sources
		"vco":
			var rng_off: float = [-5.0, 0.0, 2.0][clampi(m.sw[0], 0, 2)]
			var drift := _brand_drift(m)
			var base: float = C4 * pow(2.0, kv[0] + kv[1] / 12.0 + rng_off + drift)
			var fm: float = kv[2]
			var pw0: float = kv[3]
			var ph: float = s[0]
			var subph: float = s[1]
			var lsync: float = s[2]
			var sat := _brand_sat(m)
			var i4v := _src[mi * MAXIN + 4]
			for i in BLK:
				var f: float = base * pow(2.0, b[i0 + i] + b[i1 + i] / 12.0
					+ fm * b[i2 + i])
				f = clampf(f, 0.01, SR * 0.47)
				var dt: float = f / SR
				var syn: float = b[i4v + i]
				if syn > GATE_HI and lsync <= GATE_HI:
					ph = 0.0
					subph = 0.0
				lsync = syn
				ph += dt
				if ph >= 1.0:
					ph -= 1.0
					subph = 1.0 - subph
				var pw: float = clampf(pw0 + b[i3 + i] * 0.1, 0.02, 0.98)
				var saw: float = 2.0 * ph - 1.0 - _bl(ph, dt)
				var sq: float = 1.0 if ph < pw else -1.0
				sq += _bl(ph, dt)
				sq -= _bl(fmod(ph + (1.0 - pw), 1.0), dt)
				var tri: float = 4.0 * absf(ph - 0.5) - 1.0
				var sn: float = sin(TAU * ph)
				if sat > 0.0:
					saw = saw - sat * saw * saw * saw * 0.3
					sq = sq / (1.0 + sat * 0.2)
				b[o0 + i] = saw * 5.0
				b[o0 + BLK + i] = sq * 5.0
				b[o0 + BLK * 2 + i] = tri * 5.0
				b[o0 + BLK * 3 + i] = sn * 5.0
				b[o0 + BLK * 4 + i] = (5.0 if subph > 0.5 else -5.0)
			s[0] = ph
			s[1] = subph
			s[2] = lsync
			peak = 1.0
		"lfo":
			# RANGE gears the rate knob down without moving it: existing
			# patches keep the tempo they were saved with, and anyone who
			# wants glacial can have it on the second switch
			var rate: float = kv[0] * [1.0, 0.025, 0.001][clampi(m.sw[1], 0, 2)]
			var amp: float = kv[1]
			var ofs: float = kv[2]
			var ph2: float = s[0]
			var lr: float = s[1]
			for i in BLK:
				var f2: float = clampf(rate * pow(2.0, b[i0 + i]), 0.00002, 400.0)
				# DEPTH: the same shape at a tenth or a hundredth of the
				# size, for when a whole volt is far too much
				var amp2: float = clampf((amp + b[i1 + i])
					* [1.0, 0.1, 0.01][clampi(m.sw[0], 0, 2)], -10.0, 10.0)
				var ofs2: float = clampf(ofs + b[i2 + i], -10.0, 10.0)
				var rst: float = b[i3 + i]
				if rst > GATE_HI and lr <= GATE_HI:
					ph2 = 0.0
				lr = rst
				ph2 = fmod(ph2 + f2 / SR, 1.0)
				var tri2: float = (4.0 * absf(ph2 - 0.5) - 1.0)
				b[o0 + i] = tri2 * amp2 + ofs2
				b[o0 + BLK + i] = (1.0 if ph2 < 0.5 else -1.0) * amp2 + ofs2
				b[o0 + BLK * 2 + i] = (2.0 * ph2 - 1.0) * amp2 + ofs2
				b[o0 + BLK * 3 + i] = sin(TAU * ph2) * amp2 + ofs2
			s[0] = ph2
			s[1] = lr
			peak = 0.5 + 0.5 * sin(TAU * ph2)
		"noise":
			var lvl: float = kv[0]
			var rr: float = kv[1]
			var b0: float = s[0]
			var b1: float = s[1]
			var b2: float = s[2]
			var rph: float = s[3]
			var rv: float = s[4]
			for i in BLK:
				var w: float = _rng.randf() * 2.0 - 1.0
				b0 = 0.99765 * b0 + w * 0.0990460
				b1 = 0.96300 * b1 + w * 0.2965164
				b2 = 0.57000 * b2 + w * 1.0526913
				rph += rr / SR
				if rph >= 1.0:
					rph -= 1.0
					rv = _rng.randf() * 2.0 - 1.0
				b[o0 + i] = w * lvl
				b[o0 + BLK + i] = clampf((b0 + b1 + b2 + w * 0.1848) * 0.28, -1.0, 1.0) * lvl
				b[o0 + BLK * 2 + i] = rv * lvl
			s[0] = b0
			s[1] = b1
			s[2] = b2
			s[3] = rph
			s[4] = rv
			peak = 0.6
		"drum":
			var kind: int = clampi(m.sw[0], 0, 4)
			var tune: float = kv[0]
			var dec: float = kv[1]
			var tone: float = kv[2]
			var lvl2: float = kv[3]
			var t: float = s[0]
			var ph3: float = s[1]
			var lt: float = s[2]
			var acc: float = s[3]
			var hp1: float = s[4]
			var i4d := _src[mi * MAXIN + 4]
			var i5d := _src[mi * MAXIN + 5]
			for i in BLK:
				var trg: float = b[i4d + i]
				if trg > GATE_HI and lt <= GATE_HI:
					t = 0.0
					ph3 = 0.0
					acc = 1.0 + clampf(b[i5d + i] / 5.0, 0.0, 1.0) * 0.8
				lt = trg
				var v := 0.0
				var env: float = exp(-t / maxf(dec * pow(2.0, b[i1 + i]), 0.005))
				var tf: float = tune * pow(2.0, b[i0 + i])
				tone = clampf(kv[2] + b[i2 + i] * 0.2, 0.0, 1.0)
				lvl2 = clampf(kv[3] + b[i3 + i] * 0.2, 0.0, 2.0)
				match kind:
					0:   # KICK
						var pf: float = tf * (1.0 + 5.0 * exp(-t * 42.0))
						ph3 += pf / SR
						v = sin(TAU * ph3) * env
						v += (_rng.randf() * 2.0 - 1.0) * exp(-t * 220.0) * tone * 0.6
					1:   # SNARE
						ph3 += tf * 3.2 / SR
						var nz: float = _rng.randf() * 2.0 - 1.0
						hp1 = nz - hp1 * 0.2
						v = sin(TAU * ph3) * env * (1.0 - tone) * 0.9 \
							+ hp1 * exp(-t / maxf(dec * 0.7, 0.005)) * tone
					2:   # HAT
						var nz2: float = _rng.randf() * 2.0 - 1.0
						hp1 = 0.5 * (nz2 - hp1)
						v = hp1 * exp(-t / maxf(dec * 0.35, 0.004)) * 2.0
					3:   # CLAP
						var burst: float = exp(-fmod(t, 0.012) * 260.0) if t < 0.05 else 1.0
						var nz3: float = _rng.randf() * 2.0 - 1.0
						hp1 = nz3 - hp1 * 0.15
						v = hp1 * exp(-t / maxf(dec * 0.6, 0.005)) * burst
					_:   # TOM
						var pf2: float = tf * (1.0 + 1.6 * exp(-t * 16.0))
						ph3 += pf2 / SR
						v = sin(TAU * ph3) * env
				t += 1.0 / SR
				b[o0 + i] = clampf(v * acc * lvl2, -1.2, 1.2) * 5.0
			s[0] = t
			s[1] = ph3
			s[2] = lt
			s[3] = acc
			s[4] = hp1
			peak = exp(-s[0] * 6.0)
		"vkeys":
			# the rack keyboard: pitch and gate, nothing else on the panel
			var nv: float = m.st[0] if m.st.size() > 0 else -1.0
			var gv2: float = m.st[1] if m.st.size() > 1 else 0.0
			# the slider, plus whatever the octave port is being fed
			var octv: float = kv[0] + b[i0 + BLK - 1]
			var tgtv: float = nv / 12.0 + octv
			var curv: float = s[0]
			for i in BLK:
				if nv >= 0.0:
					curv += (tgtv - curv) * 0.02      # just enough to not click
				b[o0 + i] = curv
				b[o0 + BLK + i] = 5.0 if gv2 > 0.5 else 0.0
			s[0] = curv
			peak = gv2
		"keys":
			var note: float = m.st[0] if m.st.size() > 0 else -1.0
			var gate: float = m.st[1] if m.st.size() > 1 else 0.0
			var target: float = (note + kv[0] * 12.0) / 12.0
			var gl: float = kv[1]
			var cur: float = s[0]
			var a: float = 1.0 - exp(-1.0 / maxf(0.0005, gl * 0.35) / SR)
			for i in BLK:
				if note >= 0.0:
					cur += (target - cur) * a
				b[o0 + i] = cur
				b[o0 + BLK + i] = 5.0 if gate > 0.5 else 0.0
			s[0] = cur
			peak = gate
		# ------------------------------------------------------ shapers
		"vcf":
			var slope24: bool = m.sw[0] == 1
			var res: float = clampf(kv[1], 0.0, 0.99)
			var k: float = 2.0 - 1.96 * res
			var drv: float = kv[2] * (1.0 + _brand_sat(m) * 0.5)
			var ic1: float = s[0]
			var ic2: float = s[1]
			var ic3: float = s[2]
			var ic4: float = s[3]
			var g := 0.0
			var a1 := 0.0
			var a2 := 0.0
			var a3 := 0.0
			for i in BLK:
				if i % SUB == 0:
					var fc: float = kv[0] * pow(2.0, b[i0 + i] * 2.0)
					fc = clampf(fc, 12.0, SR * 0.45)
					var kk: float = clampf(k - b[i1 + i] * 0.3, 0.04, 2.0)
					g = tan(PI * fc / SR)
					a1 = 1.0 / (1.0 + g * (g + kk))
					a2 = g * a1
					a3 = g * a2
					k = 2.0 - 1.96 * res
				var x: float = b[i3 + i]
				var dv2: float = clampf(drv + b[i2 + i] * 0.5, 0.2, 12.0)
				if dv2 > 1.01:
					x = tanh(x * dv2 / 5.0) * 5.0
				var v3: float = x - ic2
				var v1: float = a1 * ic1 + a2 * v3
				var v2: float = ic2 + a2 * ic1 + a3 * v3
				ic1 = 2.0 * v1 - ic1
				ic2 = 2.0 * v2 - ic2
				var lp: float = v2
				var bp: float = v1
				var hp: float = x - k * v1 - v2
				if slope24:
					var v3b: float = lp - ic4
					var v1b: float = a1 * ic3 + a2 * v3b
					var v2b: float = ic4 + a2 * ic3 + a3 * v3b
					ic3 = 2.0 * v1b - ic3
					ic4 = 2.0 * v2b - ic4
					lp = v2b
					bp = v1b
					hp = lp - k * v1b - v2b
				b[o0 + i] = clampf(lp, -12.0, 12.0)
				b[o0 + BLK + i] = clampf(bp, -12.0, 12.0)
				b[o0 + BLK * 2 + i] = clampf(hp, -12.0, 12.0)
				b[o0 + BLK * 3 + i] = clampf(lp + hp, -12.0, 12.0)
			s[0] = ic1
			s[1] = ic2
			s[2] = ic3
			s[3] = ic4
			peak = clampf(absf(ic2) / 5.0, 0.0, 1.0)
		"vca":
			var expo: bool = m.sw[0] == 1
			var gsm: float = s[0]
			var cvamt: float = kv[1]
			var patched: bool = _pat[mi * MAXIN + 0] == 1
			for i in BLK:
				var g2: float = kv[0]
				if patched:
					g2 += cvamt * b[i0 + i] / 5.0
				g2 = clampf(g2, 0.0, 1.6)
				if expo:
					g2 = g2 * g2 * g2
				gsm += (g2 - gsm) * 0.02
				b[o0 + i] = b[i1 + i] * gsm
			s[0] = gsm
			peak = clampf(gsm, 0.0, 1.0)
		"mix4":
			var mst: float = kv[4]
			for i in BLK:
				var v4: float = (b[i0 + i] * kv[0] + b[i1 + i] * kv[1]
					+ b[i2 + i] * kv[2] + b[i3 + i] * kv[3]) * mst
				v4 = clampf(v4, -12.0, 12.0)
				b[o0 + i] = v4
				b[o0 + BLK + i] = -v4
			peak = clampf(absf(b[o0 + BLK - 1]) / 5.0, 0.0, 1.0)
		"atten":
			for i in BLK:
				var va: float = clampf(b[i0 + i] * kv[0] + kv[1], -10.0, 10.0)
				var vb: float = clampf(b[i1 + i] * kv[2] + kv[3], -10.0, 10.0)
				b[o0 + i] = va
				b[o0 + BLK + i] = va
				b[o0 + BLK * 2 + i] = vb
				b[o0 + BLK * 3 + i] = vb
			peak = 0.4
		"const":
			for k2 in 4:
				var v5: float = kv[k2]
				var base2 := o0 + BLK * k2
				for i in BLK:
					b[base2 + i] = v5
			peak = 0.25
		"ring":
			for i in BLK:
				b[o0 + i] = clampf((b[i0 + i] + kv[1]) * b[i1 + i] / 5.0 * kv[0], -10.0, 10.0)
			peak = clampf(absf(b[o0 + BLK - 1]) / 5.0, 0.0, 1.0)
		"fold":
			for i in BLK:
				var v6: float = b[i0 + i] / 5.0 * (kv[0] + b[i1 + i] * kv[2]) + kv[1]
				for _f in 6:
					if v6 > 1.0:
						v6 = 2.0 - v6
					elif v6 < -1.0:
						v6 = -2.0 - v6
					else:
						break
				b[o0 + i] = v6 * 5.0
			peak = clampf(absf(b[o0 + BLK - 1]) / 5.0, 0.0, 1.0)
		"drive":
			var lp2: float = s[0]
			for i in BLK:
				var dr: float = kv[0] * (1.0 + b[i1 + i] * 0.2)
				var x2: float = tanh(b[i0 + i] / 5.0 * dr)
				lp2 += (x2 - lp2) * 0.35
				var mixt: float = kv[1]
				b[o0 + i] = ((x2 - lp2) * mixt + lp2 * (1.0 - mixt) + x2 * 0.5) * kv[2] * 5.0
			s[0] = lp2
			peak = clampf(absf(b[o0 + BLK - 1]) / 5.0, 0.0, 1.0)
		# --------------------------------------------------- modulation
		"adsr":
			var lin: bool = m.sw[0] == 1
			var i4 := _src[mi * MAXIN + 4]
			var i5 := _src[mi * MAXIN + 5]
			var stg: float = s[0]
			var lvl3: float = s[1]
			var lg: float = s[2]
			var lrt: float = s[3]
			var eoc: float = 0.0
			# nothing patched into GATE or RETRIG at all: the envelope has
			# no business firing, so make sure it is shut
			if _pat[mi * MAXIN + 4] == 0 and _pat[mi * MAXIN + 5] == 0:
				stg = 0.0
				lvl3 = 0.0
			# each stage knob has a CV jack under it: one volt doubles
			# (or halves) the time, sustain shifts a fifth of a volt
			var ta: float = clampf(kv[0] * pow(2.0, b[i0 + BLK - 1]), 0.0005, 60.0)
			var td: float = clampf(kv[1] * pow(2.0, b[i1 + BLK - 1]), 0.0005, 60.0)
			var trr: float = clampf(kv[3] * pow(2.0, b[i3 + BLK - 1]), 0.0005, 60.0)
			var sus: float = clampf(kv[2] + b[i2 + BLK - 1] * 0.2, 0.0, 1.0)
			var ra: float = 1.0 - exp(-1.0 / ta / SR)
			var rd: float = 1.0 - exp(-1.0 / td / SR)
			var rr2: float = 1.0 - exp(-1.0 / trr / SR)
			for i in BLK:
				var gt: float = b[i4 + i]
				var rt: float = b[i5 + i]
				if (gt > GATE_HI and lg <= GATE_HI) or (rt > GATE_HI and lrt <= GATE_HI):
					stg = 1.0
				elif gt <= GATE_HI and lg > GATE_HI:
					stg = 4.0
				lg = gt
				lrt = rt
				if stg == 1.0:
					if lin:
						lvl3 += 1.0 / ta / SR
					else:
						lvl3 += (1.25 - lvl3) * ra
					if lvl3 >= 1.0:
						lvl3 = 1.0
						stg = 2.0
				elif stg == 2.0:
					if lin:
						lvl3 -= (1.0 - sus) / td / SR
					else:
						lvl3 += (sus - 0.02 - lvl3) * rd
					if lvl3 <= sus:
						lvl3 = sus
						stg = 3.0
				elif stg == 3.0:
					# SUSTAIN only holds while the gate is actually held.
					# Restoring a patch saved mid-note used to land here
					# with nothing holding the gate, and the envelope sat
					# open forever -- an ADSR "working" with no gate.
					if gt <= GATE_HI:
						stg = 4.0
					else:
						lvl3 = sus
				elif stg == 4.0:
					if lin:
						lvl3 -= 1.0 / trr / SR
					else:
						lvl3 += (-0.02 - lvl3) * rr2
					if lvl3 <= 0.0005:
						lvl3 = 0.0
						stg = 0.0
						eoc = 5.0
				lvl3 = clampf(lvl3, 0.0, 1.0)
				b[o0 + i] = lvl3 * 5.0
				b[o0 + BLK + i] = -lvl3 * 5.0
				b[o0 + BLK * 2 + i] = eoc
			s[0] = stg
			s[1] = lvl3
			s[2] = lg
			s[3] = lrt
			peak = lvl3
		"slew":
			var cur2: float = s[0]
			var rise: float = 10.0 / maxf(kv[0], 0.0002) / SR
			var fall: float = 10.0 / maxf(kv[1], 0.0002) / SR
			var moving := 0.0
			for i in BLK:
				var tgt: float = b[i0 + i]
				var dlt: float = tgt - cur2
				if dlt > 0.0:
					cur2 += minf(dlt, rise)
				else:
					cur2 += maxf(dlt, -fall)
				moving = 5.0 if absf(tgt - cur2) > 0.01 else 0.0
				b[o0 + i] = cur2
				b[o0 + BLK + i] = moving
			s[0] = cur2
			peak = clampf(absf(cur2) / 5.0, 0.0, 1.0)
		"sh":
			var held: float = s[0]
			var lt2: float = s[1]
			var smooth: float = s[2]
			var pat_in: bool = _pat[mi * MAXIN + 0] == 1
			var a2s: float = 1.0 - exp(-1.0 / maxf(0.0004, kv[0] * 0.4) / SR)
			for i in BLK:
				var tg: float = b[i1 + i]
				if tg > GATE_HI and lt2 <= GATE_HI:
					held = (b[i0 + i] if pat_in else (_rng.randf() * 10.0 - 5.0)) * kv[1]
				lt2 = tg
				smooth += (held - smooth) * a2s
				var v7: float = smooth if kv[0] > 0.001 else held
				b[o0 + i] = v7
				b[o0 + BLK + i] = -v7
			s[0] = held
			s[1] = lt2
			s[2] = smooth
			peak = clampf(absf(held) / 5.0, 0.0, 1.0)
		"quant":
			var scale: PackedInt32Array = _scale(m.sw[0])
			var root: int = int(round(kv[0]))
			var tr: float = round(kv[1])
			var lastn: float = s[0]
			var trg2: float = 0.0
			var vin: float = b[i0 + BLK - 1]
			var semi: float = vin * 12.0
			var oct: float = floor(semi / 12.0)
			var pc: float = semi - oct * 12.0
			var bestd := 99.0
			var bestv := 0.0
			for sc in scale:
				for oo in [-12.0, 0.0, 12.0]:
					var cand: float = float(sc) + float(root) + oo
					var dd: float = absf(cand - pc)
					if dd < bestd:
						bestd = dd
						bestv = cand
			var outn: float = (oct * 12.0 + bestv) / 12.0 + tr
			if absf(outn - lastn) > 0.001:
				trg2 = 5.0
			s[0] = outn
			for i in BLK:
				b[o0 + i] = outn
				b[o0 + BLK + i] = trg2
			peak = 0.3 + 0.7 * (1.0 if trg2 > 0.0 else 0.0)
		# -------------------------------------------------------- clocks
		"clock":
			var run: bool = m.sw[0] == 1
			if _pat[mi * MAXIN + 0] == 1:
				run = b[i0 + BLK - 1] > GATE_HI
			var ext: bool = _pat[mi * MAXIN + 1] == 1
			var ph4: float = s[0]
			var cnt: float = s[1]
			var lext: float = s[2]
			var lrst: float = s[3]
			var high: float = s[4]
			var rstpulse := 0.0
			var rin: float = b[i2 + BLK - 1]
			if rin > GATE_HI and lrst <= GATE_HI:
				cnt = 0.0
				ph4 = 0.0
			lrst = rin
			var stepped := false
			if run:
				if ext:
					var e: float = b[i1 + BLK - 1]
					if e > GATE_HI and lext <= GATE_HI:
						stepped = true
					lext = e
					high = 1.0 if b[i1 + BLK - 1] > GATE_HI else 0.0
				else:
					var rate2: float = kv[0] / 60.0 * 4.0
					var sw2: float = kv[1] * 0.5
					var per: float = 1.0 + (sw2 if int(cnt) % 2 == 1 else -sw2)
					ph4 += float(BLK) / SR * rate2 / maxf(per, 0.2)
					if ph4 >= 1.0:
						ph4 -= 1.0
						stepped = true
					# PHASE slides the pulse without touching the count,
					# so two clocks can share a tempo and never line up
					high = 1.0 if fposmod(ph4 - kv[3], 1.0) < kv[2] else 0.0
			else:
				high = 0.0
			if stepped:
				cnt += 1.0
				if int(cnt) % 16 == 0:
					rstpulse = 5.0
			var c0: float = 5.0 if high > 0.5 else 0.0
			var ci: int = int(cnt)
			for i in BLK:
				b[o0 + i] = c0
				b[o0 + BLK + i] = c0 if ci % 2 == 0 else 0.0
				b[o0 + BLK * 2 + i] = c0 if ci % 4 == 0 else 0.0
				b[o0 + BLK * 3 + i] = c0 if ci % 8 == 0 else 0.0
				b[o0 + BLK * 4 + i] = rstpulse
			s[0] = ph4
			s[1] = cnt
			s[2] = lext
			s[3] = lrst
			s[4] = high
			peak = high
		"cdiv":
			var cnt2: float = s[0]
			var lc: float = s[1]
			var lr2: float = s[2]
			var cin: float = b[i0 + BLK - 1]
			var rin2: float = b[i1 + BLK - 1]
			if rin2 > GATE_HI and lr2 <= GATE_HI:
				cnt2 = 0.0
			lr2 = rin2
			if cin > GATE_HI and lc <= GATE_HI:
				cnt2 += 1.0
			lc = cin
			var hi: float = 5.0 if cin > GATE_HI else 0.0
			var c2 := int(cnt2)
			for i in BLK:
				b[o0 + i] = hi if c2 % 2 == 0 else 0.0
				b[o0 + BLK + i] = hi if c2 % 3 == 0 else 0.0
				b[o0 + BLK * 2 + i] = hi if c2 % 4 == 0 else 0.0
				b[o0 + BLK * 3 + i] = hi if c2 % 8 == 0 else 0.0
				b[o0 + BLK * 4 + i] = hi if c2 % 16 == 0 else 0.0
			s[0] = cnt2
			s[1] = lc
			s[2] = lr2
			peak = hi / 5.0
		"logic":
			var th: float = kv[0]
			var av: bool = b[i0 + BLK - 1] > th
			var bv: bool = b[i1 + BLK - 1] > th
			var cvv: bool = b[i2 + BLK - 1] > th
			var la: float = s[0]
			var flip: float = s[1]
			if av and la <= 0.5:
				flip = 0.0 if flip > 0.5 else 1.0
			s[0] = 1.0 if av else 0.0
			s[1] = flip
			var andv: float = 5.0 if (av and bv and (cvv or _pat[mi * MAXIN + 2] == 0)) else 0.0
			var orv: float = 5.0 if (av or bv or cvv) else 0.0
			var xorv: float = 5.0 if (av != bv) else 0.0
			var notv: float = 0.0 if av else 5.0
			var flv: float = 5.0 if flip > 0.5 else 0.0
			for i in BLK:
				b[o0 + i] = andv
				b[o0 + BLK + i] = orv
				b[o0 + BLK * 2 + i] = xorv
				b[o0 + BLK * 3 + i] = notv
				b[o0 + BLK * 4 + i] = flv
			peak = orv / 5.0
		"comp":
			var thv: float = kv[0] + b[i1 + BLK - 1]
			var win: float = kv[1]
			var lgt: float = s[0]
			var x3: float = b[i0 + BLK - 1]
			var gt2: float = 5.0 if x3 > thv else 0.0
			var lt3: float = 0.0 if x3 > thv else 5.0
			var wv: float = 5.0 if absf(x3 - thv) < win else 0.0
			var tv: float = 5.0 if (gt2 > 0.0 and lgt <= 0.0) else 0.0
			s[0] = gt2
			for i in BLK:
				b[o0 + i] = gt2
				b[o0 + BLK + i] = lt3
				b[o0 + BLK * 2 + i] = wv
				b[o0 + BLK * 3 + i] = tv
			peak = gt2 / 5.0
		# ---------------------------------------------------- sequencers
		"seq8":
			var len8: int = clampi(int(round(kv[0])), 1, 8)
			var dir: int = clampi(m.sw[0], 0, 3)
			var step: float = s[0]
			var lc2: float = s[1]
			var lr3: float = s[2]
			var updir: float = s[3]
			var glide: float = s[4]
			var eoc2 := 0.0
			var cin2: float = b[i0 + BLK - 1]
			var rin3: float = b[i1 + BLK - 1]
			var hold: bool = _pat[mi * MAXIN + 2] == 1 and b[i2 + BLK - 1] > GATE_HI
			if rin3 > GATE_HI and lr3 <= GATE_HI:
				step = 0.0
			lr3 = rin3
			if cin2 > GATE_HI and lc2 <= GATE_HI and not hold:
				match dir:
					0:
						step += 1.0
						if step >= float(len8):
							step = 0.0
							eoc2 = 5.0
					1:
						step -= 1.0
						if step < 0.0:
							step = float(len8 - 1)
							eoc2 = 5.0
					2:
						step += 1.0 if updir >= 0.0 else -1.0
						if step >= float(len8 - 1):
							step = float(maxi(len8 - 1, 0))
							updir = -1.0
							eoc2 = 5.0
						elif step <= 0.0:
							step = 0.0
							updir = 1.0
							eoc2 = 5.0
					_:
						step = float(_rng.randi() % len8)
			lc2 = cin2
			var si: int = clampi(int(step), 0, 7)
			var pitch: float = (m.st[si] * 2.0 - 1.0) * kv[2]
			var gon: bool = m.st[8 + si] > 0.5
			var gv: float = 5.0 if (gon and cin2 > GATE_HI) else 0.0
			var ga: float = 1.0 - exp(-1.0 / maxf(0.0005, kv[1] * 0.3) / SR)
			for i in BLK:
				glide += (pitch - glide) * ga
				b[o0 + i] = glide if kv[1] > 0.001 else pitch
				b[o0 + BLK + i] = gv
				b[o0 + BLK * 2 + i] = eoc2
			s[0] = step
			s[1] = lc2
			s[2] = lr3
			s[3] = updir
			s[4] = glide
			peak = 1.0 if gv > 0.0 else 0.15
		"dseq":
			var len16: int = clampi(int(round(kv[0])), 1, 16)
			var stp: float = s[0]
			var lc3: float = s[1]
			var lr4: float = s[2]
			var cin3: float = b[i0 + BLK - 1]
			var rin4: float = b[i1 + BLK - 1]
			if rin4 > GATE_HI and lr4 <= GATE_HI:
				stp = 0.0
			lr4 = rin4
			if cin3 > GATE_HI and lc3 <= GATE_HI:
				stp = fmod(stp + 1.0, float(len16))
			lc3 = cin3
			var si2: int = clampi(int(stp), 0, 15)
			var anyhit := 0.0
			for lane in 4:
				var on: bool = m.st[lane * 16 + si2] > 0.5
				var v8: float = 5.0 if (on and cin3 > GATE_HI) else 0.0
				if v8 > 0.0:
					anyhit = 1.0
				var base3 := o0 + BLK * lane
				for i in BLK:
					b[base3 + i] = v8
			s[0] = stp
			s[1] = lc3
			s[2] = lr4
			peak = anyhit
		"chancegrid":
			# every cell is odds, not a switch. A step at 0.4 fires four
			# times in ten -- so the pattern is recognisable and never the
			# same twice. DICE decides whether the coin is thrown fresh
			# each pass (FREE), thrown once and kept (LOCKED), or kept
			# with the odd cell quietly re-thrown (DRIFT).
			var lenG: int = clampi(int(round(kv[0])), 1, 16)
			var biasG: float = clampf(kv[1] + b[i2 + BLK - 1] * 0.2, -1.0, 1.0)
			var patG: int = clampi(int(round(kv[2] + b[i3 + BLK - 1] * 0.6)) - 1, 0, 3)
			var swG: float = kv[3]
			var holdG: bool = kv[4] > 0.5
			var diceG: int = clampi(m.sw[0], 0, 2)
			var stpG: float = s[0]
			var lcG: float = s[1]
			var lrG: float = s[2]
			var swphG: float = s[3]
			var eocG := 0.0
			var cinG: float = b[i0 + BLK - 1]
			var rinG: float = b[i1 + BLK - 1]
			if rinG > GATE_HI and lrG <= GATE_HI:
				stpG = 0.0
				for lane in 4:
					s[8 + lane] = 0.0
			lrG = rinG
			var stepped := false
			if cinG > GATE_HI and lcG <= GATE_HI:
				var lateG: float = swG * (1.0 if int(stpG) % 2 == 1 else 0.0)
				if lateG > 0.001 and swphG <= 0.0:
					swphG = lateG * 0.12
				else:
					swphG = 0.0
					var nxt: float = stpG + 1.0
					if nxt >= float(lenG):
						nxt = 0.0
						eocG = 5.0
					stpG = nxt
					stepped = true
			if swphG > 0.0:
				swphG = maxf(0.0, swphG - float(BLK) / SR)
				if swphG <= 0.0:
					var nxt2: float = stpG + 1.0
					if nxt2 >= float(lenG):
						nxt2 = 0.0
						eocG = 5.0
					stpG = nxt2
					stepped = true
			lcG = cinG
			var siG: int = clampi(int(stpG), 0, 15)
			if stepped:
				for lane in 4:
					var idxG: int = patG * 64 + lane * 16 + siG
					var wgt: float = clampf(m.st[idxG] + biasG, 0.0, 1.0)
					var fire := false
					match diceG:
						1:      # LOCKED: one throw per cell, kept until it changes
							var bits: int = int(s[16 + lane])
							var known: int = int(s[20 + lane])
							if (known >> siG) & 1 == 0:
								fire = _rng.randf() < wgt
								s[20 + lane] = float(known | (1 << siG))
								s[16 + lane] = float((bits & ~(1 << siG))
									| ((1 if fire else 0) << siG))
							else:
								fire = ((bits >> siG) & 1) == 1
								# a cell whose weight moved gets re-thrown
								if (wgt <= 0.001 and fire) or (wgt >= 0.999 and not fire):
									fire = wgt >= 0.999
									s[16 + lane] = float((bits & ~(1 << siG))
										| ((1 if fire else 0) << siG))
						2:      # DRIFT: mostly kept, one cell in ten re-thrown
							var bits2: int = int(s[16 + lane])
							var known2: int = int(s[20 + lane])
							if (known2 >> siG) & 1 == 0 or _rng.randf() < 0.1:
								fire = _rng.randf() < wgt
								s[20 + lane] = float(known2 | (1 << siG))
								s[16 + lane] = float((bits2 & ~(1 << siG))
									| ((1 if fire else 0) << siG))
							else:
								fire = ((bits2 >> siG) & 1) == 1
						_:
							fire = _rng.randf() < wgt
					s[8 + lane] = 5.0 if fire else 0.0
			var anyG := 0.0
			for lane in 4:
				var live: bool = s[8 + lane] > 1.0
				var vG: float = 0.0
				if live:
					vG = 5.0 if (holdG or cinG > GATE_HI) else 0.0
				if vG > 0.0:
					anyG = 5.0
				var baseG := o0 + BLK * lane
				for i in BLK:
					b[baseG + i] = vG
			for i in BLK:
				b[o0 + BLK * 4 + i] = anyG
				b[o0 + BLK * 5 + i] = eocG
			s[0] = stpG
			s[1] = lcG
			s[2] = lrG
			s[3] = swphG
			s[4] = float(patG)
			peak = clampf(anyG / 5.0, 0.0, 1.0)
		"muse":
			# a melody WRITER. It composes a phrase, plays it, and rewrites
			# a slice of it every time round: VARY at zero is a loop, VARY
			# at full is a new tune every bar. SEED makes any tune findable
			# again, because every note comes out of a hash of
			# (seed, generation, position) and not a free-running dice.
			var lenM: int = clampi(int(round(kv[1])), 2, 16)
			var seedM: int = int(round(kv[0] + b[i3 + BLK - 1] * 60.0)) & 0xFFFF
			var rootM: float = round(kv[2])
			var rangeM: int = clampi(int(round(kv[3])), 1, 4)
			var densM: float = kv[4]
			var varyM: float = kv[5]
			var glideM: float = kv[6]
			var scM: PackedInt32Array = _muse_scale(m.sw[0])
			var contM: int = clampi(m.sw[1], 0, 4)
			var stpM: float = s[0]
			var lcM: float = s[1]
			var lrM: float = s[2]
			var lmM: float = s[3]
			var genM: int = int(s[4])
			var cvM: float = s[5]
			var eopM := 0.0
			var cinM: float = b[i0 + BLK - 1]
			var rinM: float = b[i1 + BLK - 1]
			var minM: float = b[i2 + BLK - 1]
			if s[6] < 0.5:
				_muse_write(m.st, seedM, genM, lenM, scM.size(), rangeM,
					densM, contM, 1.0)
				s[6] = 1.0
			if rinM > GATE_HI and lrM <= GATE_HI:
				stpM = 0.0
			lrM = rinM
			if minM > GATE_HI and lmM <= GATE_HI:
				genM += 1
				_muse_write(m.st, seedM, genM, lenM, scM.size(), rangeM,
					densM, contM, 1.0)
			lmM = minM
			if cinM > GATE_HI and lcM <= GATE_HI:
				stpM += 1.0
				if stpM >= float(lenM):
					stpM = 0.0
					eopM = 5.0
					genM += 1
					if varyM > 0.001:
						_muse_write(m.st, seedM, genM, lenM, scM.size(),
							rangeM, densM, contM, varyM)
			lcM = cinM
			var siM: int = clampi(int(stpM), 0, 15)
			var degM: int = int(m.st[siM])
			var gateM: float = m.st[16 + siM]
			var octM: int = degM / maxi(1, scM.size())
			var stepIdx: int = degM % maxi(1, scM.size())
			var semiM: float = float(scM[stepIdx]) + float(octM) * 12.0 + rootM
			var wantM: float = semiM / 12.0
			var gl: float = 1.0 - pow(0.0008, 1.0 / maxf(glideM * SR * 0.25, 1.0)) \
				if glideM > 0.001 else 1.0
			var accM: float = 5.0 if gateM > 1.5 else 0.0
			var gv: float = 5.0 if (gateM > 0.5 and cinM > GATE_HI) else 0.0
			for i in BLK:
				cvM += (wantM - cvM) * gl
				b[o0 + i] = cvM
				b[o0 + BLK + i] = gv
				b[o0 + BLK * 2 + i] = accM
				b[o0 + BLK * 3 + i] = eopM
			s[0] = stpM
			s[1] = lcM
			s[2] = lrM
			s[3] = lmM
			s[4] = float(genM)
			s[5] = cvM
			peak = clampf(gv / 5.0, 0.0, 1.0)
		"chords":
			# four voltages that agree with each other. Everything the rack
			# plays through these is in the same key by construction.
			var keyC2: float = round(kv[0] + b[i3 + BLK - 1] * 2.0)
			var barsC: int = clampi(int(round(kv[1])), 1, 8)
			var spreadC: float = kv[2]
			var seedC: int = int(round(kv[3])) & 0xFFFF
			var scC: PackedInt32Array = _muse_scale([0, 1, 2, 5][clampi(m.sw[0], 0, 3)])
			var moveC: int = clampi(m.sw[1], 0, 4)
			var voiceC: int = clampi(m.sw[2], 0, 3)
			var barC: float = s[0]
			var beatC: float = s[1]
			var lcC: float = s[2]
			var lrC: float = s[3]
			var chgC := 0.0
			var cinC: float = b[i0 + BLK - 1]
			var rinC: float = b[i1 + BLK - 1]
			if rinC > GATE_HI and lrC <= GATE_HI:
				barC = 0.0
				beatC = 0.0
			lrC = rinC
			if cinC > GATE_HI and lcC <= GATE_HI:
				beatC += 1.0
				if beatC >= float(barsC) * 4.0:
					beatC = 0.0
					barC = fmod(barC + 1.0, 4.0)
					chgC = 5.0
			lcC = cinC
			var bi: int = clampi(int(barC), 0, 3)
			var degC: int = 0
			match moveC:
				0: degC = [0, 4, 5, 3][bi]              # I - V - vi - IV
				1: degC = [0, 5, 2, 6][bi]              # i - VI - III - VII
				2: degC = [0, 3, 4, 0][bi]              # i - iv - v - i
				3: degC = int(_hash01(seedC * 977 + bi * 31 + int(barC)) * 7.0) % 7
				_: degC = 0
			var nsC: int = maxi(1, scC.size())
			var tones: Array = [0, 2, 4, 6]
			match voiceC:
				2: tones = [0, 3, 4, 6]                 # SUS
				3: tones = [0, 2, 4, 6]                 # WIDE: spread by octaves below
				_: tones = [0, 2, 4, 6]
			for t in 4:
				var dg: int = degC + int(tones[t])
				var oc: int = dg / nsC
				if voiceC == 3:
					oc += t                              # WIDE: pull them apart
				var sm: float = float(scC[dg % nsC]) + float(oc) * 12.0 + keyC2
				if voiceC == 0 and t == 3:
					sm -= 12.0                           # TRIAD: the 7th drops out of the way
				var vv: float = sm / 12.0 + spreadC * float(t) * 0.0
				for i in BLK:
					b[o0 + BLK * t + i] = vv
				s[8 + t] = vv
			# TRACK: whatever melody you feed in, pulled onto this chord
			var tin: float = b[i2 + BLK - 1]
			var bestC := 0.0
			var bdC := 99.0
			for t in 4:
				for oo in [-24.0, -12.0, 0.0, 12.0, 24.0]:
					var cand: float = s[8 + t] + oo / 12.0
					var dd2: float = absf(cand - tin)
					if dd2 < bdC:
						bdC = dd2
						bestC = cand
			for i in BLK:
				b[o0 + BLK * 4 + i] = bestC
				b[o0 + BLK * 5 + i] = chgC
			s[0] = barC
			s[1] = beatC
			s[2] = lcC
			s[3] = lrC
			s[4] = float(degC)
			peak = 0.35 + 0.15 * float(bi)
		"drunk":
			# a random walk that keeps its direction more often than not,
			# so it wanders somewhere instead of just twitching
			var posD: float = s[0]
			var dirD: float = s[1] if absf(s[1]) > 0.01 else 1.0
			var lcD: float = s[2]
			var slD: float = s[3]
			var turnD := 0.0
			var stepD: float = clampf(kv[0] + b[i1 + BLK - 1] * 0.2, 0.0, 3.0)
			var rangeD: float = kv[1]
			var biasD: float = kv[2]
			var slewD: float = kv[3]
			var cinD: float = b[i0 + BLK - 1]
			if cinD > GATE_HI and lcD <= GATE_HI:
				if _rng.randf() < 0.3:
					dirD = -dirD
				var mv: float = _rng.randf() * stepD * dirD + biasD * stepD * 0.5
				posD += mv
				if posD > rangeD:
					posD = rangeD - (posD - rangeD) * 0.5
					dirD = -absf(dirD)
					turnD = 5.0
				elif posD < -rangeD:
					posD = -rangeD - (posD + rangeD) * 0.5
					dirD = absf(dirD)
					turnD = 5.0
			lcD = cinD
			var gD: float = 1.0 if slewD < 0.001 else \
				1.0 - pow(0.0008, 1.0 / maxf(slewD * SR * 0.5, 1.0))
			for i in BLK:
				slD += (posD - slD) * gD
				b[o0 + i] = clampf(slD, -10.0, 10.0)
				b[o0 + BLK + i] = clampf(-slD, -10.0, 10.0)
				b[o0 + BLK * 2 + i] = turnD
			s[0] = posD
			s[1] = dirD
			s[2] = lcD
			s[3] = slD
			peak = clampf(absf(slD) / maxf(rangeD, 0.5), 0.0, 1.0)
		"coin":
			# one trigger in, a coin, two ways out
			var lcK: float = s[0]
			var sideK: float = s[1]
			var probK: float = clampf(kv[0] + b[i1 + BLK - 1] * 0.2, 0.0, 1.0)
			var modeK: int = clampi(m.sw[0], 0, 2)
			var tinK: float = b[i0 + BLK - 1]
			if tinK > GATE_HI and lcK <= GATE_HI:
				match modeK:
					1:      # LATCH: the coin only decides when it comes up heads
						if _rng.randf() < probK:
							sideK = 0.0 if sideK > 0.5 else 1.0
					2:      # TOGGLE: strict alternation, sometimes skipped
						sideK = 0.0 if sideK > 0.5 else 1.0
						if _rng.randf() > probK:
							sideK = 0.0 if sideK > 0.5 else 1.0
					_:
						sideK = 0.0 if _rng.randf() < probK else 1.0
			lcK = tinK
			var liveK: float = 5.0 if tinK > GATE_HI else 0.0
			for i in BLK:
				b[o0 + i] = liveK if sideK < 0.5 else 0.0
				b[o0 + BLK + i] = liveK if sideK >= 0.5 else 0.0
			s[0] = lcK
			s[1] = sideK
			peak = clampf(liveK / 5.0, 0.0, 1.0)
		"ratchet":
			# one beat in, sometimes several out, packed inside the beat --
			# the burst is timed from the MEASURED clock period, so it
			# always finishes before the next beat lands
			var lcR: float = s[0]
			var perR: float = maxf(s[1], 0.02 * SR)
			var sinceR: float = s[2]
			var leftR: float = s[3]
			var gapR: float = s[4]
			var timR: float = s[5]
			var pulseR: float = s[6]
			var chR: float = clampf(kv[0] + b[i1 + BLK - 1] * 0.2, 0.0, 1.0)
			var maxR: int = clampi(int(round(kv[1])), 2, 8)
			var sprR: float = kv[2]
			var cinR: float = b[i0 + BLK - 1]
			sinceR += float(BLK)
			if cinR > GATE_HI and lcR <= GATE_HI:
				if sinceR > 8.0 and sinceR < SR * 4.0:
					perR = perR * 0.5 + sinceR * 0.5
				sinceR = 0.0
				var n: int = 1
				if _rng.randf() < chR:
					n = 2 + int(_rng.randf() * float(maxR - 1))
				leftR = float(n)
				# SPREAD squeezes the burst toward the front of the beat
				gapR = perR / float(n) * (1.0 - sprR * 0.45)
				timR = 0.0
				pulseR = 0.0
			lcR = cinR
			var burstR: float = 5.0 if leftR > 1.5 else 0.0
			for i in BLK:
				if leftR > 0.0 and timR <= 0.0:
					pulseR = SR * 0.004
					leftR -= 1.0
					timR = gapR
				timR -= 1.0
				var outR := 0.0
				if pulseR > 0.0:
					pulseR -= 1.0
					outR = 5.0
				b[o0 + i] = outR
				b[o0 + BLK + i] = burstR
			s[0] = lcR
			s[1] = perR
			s[2] = sinceR
			s[3] = leftR
			s[4] = gapR
			s[5] = timR
			s[6] = pulseR
			peak = clampf(burstR / 5.0, 0.0, 1.0)
		"euclid":
			var steps: int = clampi(int(round(kv[0])), 1, 32)
			var fill: int = clampi(int(round(kv[1])), 0, steps)
			var rot: int = int(round(kv[2]))
			var cnt3: float = s[0]
			var lc4: float = s[1]
			var lr5: float = s[2]
			var eoc3 := 0.0
			var cin4: float = b[i0 + BLK - 1]
			var rin5: float = b[i1 + BLK - 1]
			if rin5 > GATE_HI and lr5 <= GATE_HI:
				cnt3 = 0.0
			lr5 = rin5
			if cin4 > GATE_HI and lc4 <= GATE_HI:
				cnt3 += 1.0
				if int(cnt3) % steps == 0:
					eoc3 = 5.0
			lc4 = cin4
			var idx: int = posmod(int(cnt3) + rot, steps)
			var hit: bool = fill > 0 and ((idx * fill) % steps) < fill
			var hv: float = 5.0 if (hit and cin4 > GATE_HI) else 0.0
			var iv: float = 0.0 if hit else (5.0 if cin4 > GATE_HI else 0.0)
			s[0] = cnt3
			s[1] = lc4
			s[2] = lr5
			s[5] = float(idx)
			for i in BLK:
				b[o0 + i] = hv
				b[o0 + BLK + i] = iv
				b[o0 + BLK * 2 + i] = eoc3
			peak = hv / 5.0
		"turing":
			var lenR: int = clampi(int(round(kv[1])), 2, 16)
			var loop: float = kv[0]
			var lc5: float = s[1]
			var cin5: float = b[i0 + BLK - 1]
			if cin5 > GATE_HI and lc5 <= GATE_HI:
				# the register turns: the oldest bit comes back round,
				# and LOOP decides how often the universe rewrites it
				var outbit: float = s[8 + (lenR - 1)]
				var newbit: float = outbit
				var pflip: float = 1.0 - loop
				if _pat[mi * MAXIN + 1] == 1 and b[i1 + BLK - 1] > GATE_HI:
					newbit = 1.0 if _rng.randf() > 0.5 else 0.0
				elif _rng.randf() < pflip:
					newbit = 0.0 if outbit > 0.5 else 1.0
				for k3 in range(lenR - 1, 0, -1):
					s[8 + k3] = s[8 + k3 - 1]
				s[8] = newbit
				var acc2 := 0.0
				for k4 in 8:
					if s[8 + k4] > 0.5:
						acc2 += pow(2.0, float(7 - k4))
				s[0] = (acc2 / 255.0) * kv[2] + kv[3]
			s[1] = cin5
			var cvv2: float = s[0]
			var pv: float = 5.0 if (s[8] > 0.5 and cin5 > GATE_HI) else 0.0
			for i in BLK:
				b[o0 + i] = cvv2
				b[o0 + BLK + i] = pv
				b[o0 + BLK * 2 + i] = -cvv2
			peak = pv / 5.0
		# ------------------------------------------------------------ fx
		"phaser":
			var lph: float = s[0]
			var fb: float = s[1]
			var rate3: float = kv[0] * pow(2.0, b[i1 + BLK - 1] * 0.5)
			var coefa := 0.0
			for i in BLK:
				if i % SUB == 0:
					lph = fmod(lph + rate3 * float(SUB) / SR, 1.0)
					var mod2: float = 0.5 + 0.5 * sin(TAU * lph)
					var fc2: float = clampf(kv[4] * pow(2.0, mod2 * kv[1] * 3.0), 30.0, SR * 0.42)
					var g3: float = tan(PI * fc2 / SR)
					coefa = (1.0 - g3) / (1.0 + g3)
				var x4: float = b[i0 + i] + fb * kv[2]
				var y := x4
				for st2 in 6:
					var z: float = s[10 + st2]
					var o: float = coefa * (y + z) - s[16 + st2]
					s[10 + st2] = y
					s[16 + st2] = o
					y = o
				fb = y
				b[o0 + i] = b[i0 + i] * (1.0 - kv[3]) + y * kv[3]
			s[0] = lph
			s[1] = clampf(fb, -10.0, 10.0)
			peak = 0.5 + 0.5 * sin(TAU * lph)
		"cosmic":
			# six modulated delay lines, read with interpolation and
			# written at a FIXED pointer. Modulating the write index
			# scatters samples and that is what made it glitch; and the
			# feedback is now hard-capped below unity, because a tank at
			# 1.006 does not decay, it grows until it is the only thing
			# you can hear.
			var dC := m.d
			var spaceC: int = clampi(m.sw[0], 0, 2)
			var sizeC: float = clampf(kv[0] + b[i0 + BLK - 1] * 0.1, 0.0, 1.0)
			var fbk: float = clampf((0.62 + sizeC * 0.32)
				* [0.94, 0.98, 1.0][spaceC], 0.2, 0.955)
			var shimC: float = clampf(kv[1] + b[i1 + BLK - 1] * 0.15, 0.0, 1.0)
			var mixC: float = clampf(kv[2] + b[i2 + BLK - 1] * 0.15, 0.0, 1.0)
			var dampC: float = clampf(kv[3], 0.0, 1.0) * 0.7
			var driftC: float = kv[4]
			var widthC: float = kv[5]
			var tickC: int = int(s[4])
			var lfoC: float = s[5]
			var shw: int = int(s[6])
			var shph: float = s[14]
			for i in BLK:
				lfoC = fmod(lfoC + 0.23 / SR, 1.0)
				var inpC: float = b[i3 + i] * 0.20
				# the shimmer voice: the tail read at double speed, so an
				# octave up, fed back in gently and damped
				# TWO read heads half a buffer apart, crossfaded on a
				# triangle: a read head running at 2x through a buffer
				# that is being written crosses the write pointer every
				# lap, and that crossing is an audible tear. Two heads
				# mean one is always far from the seam.
				# the read head runs one sample per sample AHEAD of the
				# write head (rate 2.0 = an octave up); that lead is what
				# has to be remembered between blocks
				shph = fmod(shph + 1.0, float(COS_SHIM))
				var shA: float = fposmod(float(shw) - shph, float(COS_SHIM))
				var shB: float = fposmod(shA + float(COS_SHIM) * 0.5, float(COS_SHIM))
				var xf: float = 1.0 - absf(2.0 * shph / float(COS_SHIM) - 1.0)
				var a0: int = int(shA)
				var a1: int = (a0 + 1) % COS_SHIM
				var af: float = shA - floor(shA)
				var b0: int = int(shB)
				var b1: int = (b0 + 1) % COS_SHIM
				var bf: float = shB - floor(shB)
				var shvA: float = dC[a0] * (1.0 - af) + dC[a1] * af
				var shvB: float = dC[b0] * (1.0 - bf) + dC[b1] * bf
				var shv: float = (shvA * xf + shvB * (1.0 - xf)) * shimC * 0.5
				var accL := 0.0
				var accR := 0.0
				var off := COS_SHIM
				for ci in COS_COMB.size():
					var n: int = COS_COMB[ci]
					var nL: int = n + 64
					var wob: float = sin(TAU * (lfoC + float(ci) * 0.17)) * driftC * 9.0
					# LEFT: fixed write pointer, interpolated modulated read
					var wp: int = tickC % n
					# read the OLDEST sample in the line, not the one
					# about to be overwritten: wp - n wraps straight back
					# onto wp, which is a delay of ZERO samples and turns
					# the tank into a screaming zero-length feedback loop
					var rpf: float = float(wp) + 1.0 + wob
					while rpf < 0.0:
						rpf += float(n)
					rpf = fmod(rpf, float(n))
					var r0i: int = int(rpf) % n
					var r1i: int = (r0i + 1) % n
					var frq: float = rpf - floor(rpf)
					var vL: float = dC[off + r0i] * (1.0 - frq) + dC[off + r1i] * frq
					s[8 + ci] = vL * (1.0 - dampC) + s[8 + ci] * dampC
					dC[off + wp] = clampf(inpC + shv + s[8 + ci] * fbk, -8.0, 8.0)
					accL += vL
					off += nL
					# RIGHT: same line, offset so the two sides differ
					var n2: int = n + 23
					var wp2: int = tickC % n2
					var rpf2: float = float(wp2) + 1.0 - wob
					while rpf2 < 0.0:
						rpf2 += float(n2)
					rpf2 = fmod(rpf2, float(n2))
					var r0j: int = int(rpf2) % n2
					var r1j: int = (r0j + 1) % n2
					var frq2: float = rpf2 - floor(rpf2)
					var vR: float = dC[off + r0j] * (1.0 - frq2) + dC[off + r1j] * frq2
					s[16 + ci] = vR * (1.0 - dampC) + s[16 + ci] * dampC
					dC[off + wp2] = clampf(inpC + shv + s[16 + ci] * fbk, -8.0, 8.0)
					accR += vR
					off += n2 + 64
				accL *= 0.20
				accR *= 0.20
				for ai in COS_AP.size():
					var na: int = COS_AP[ai]
					var ia: int = tickC % na
					var bufv: float = dC[off + ia]
					var outv: float = -accL + bufv
					dC[off + ia] = clampf(accL + bufv * 0.5, -8.0, 8.0)
					accL = outv
					off += na + 64
					var nb: int = na + 23
					var ib: int = tickC % nb
					var bufv2: float = dC[off + ib]
					var outv2: float = -accR + bufv2
					dC[off + ib] = clampf(accR + bufv2 * 0.5, -8.0, 8.0)
					accR = outv2
					off += nb + 64
				# DC blocker: a tank this long integrates any offset
				var wetsum: float = (accL + accR) * 0.5
				s[7] = s[7] * 0.9995 + wetsum * 0.0005
				accL -= s[7]
				accR -= s[7]
				dC[shw] = clampf(wetsum - s[7], -8.0, 8.0)
				shw = (shw + 1) % COS_SHIM
				tickC += 1
				if tickC > 100000000:
					tickC = 0
				var dry2: float = b[i3 + i]
				var wl2: float = clampf(accL, -8.0, 8.0)
				var wr2: float = clampf(accL * (1.0 - widthC) + accR * widthC, -8.0, 8.0)
				b[o0 + i] = clampf(dry2 * (1.0 - mixC) + wl2 * mixC, -10.0, 10.0)
				b[o0 + BLK + i] = clampf(dry2 * (1.0 - mixC) + wr2 * mixC, -10.0, 10.0)
			s[4] = float(tickC)
			s[5] = lfoC
			s[6] = float(shw)
			s[14] = shph
			peak = clampf(absf(b[o0 + BLK - 1]) / 5.0, 0.0, 1.0)
		"reverb":
			var fbk: float = 0.72 + kv[0] * 0.26
			var damp: float = kv[1] * 0.55
			var wet: float = kv[2]
			var wide: float = kv[3]
			var dv := m.d
			var tick: int = int(s[4])
			for i in BLK:
				fbk = clampf(0.72 + (kv[0] + b[i0 + i] * 0.15) * 0.26, 0.2, 0.985)
				damp = clampf((kv[1] + b[i1 + i] * 0.15) * 0.55, 0.0, 0.9)
				wet = clampf(kv[2] + b[i2 + i] * 0.2, 0.0, 1.0)
				var inp: float = b[i3 + i] * 0.28
				var accL := 0.0
				var accR := 0.0
				var off := 0
				for ci in REV_COMB.size():
					var n: int = REV_COMB[ci]
					var idxL: int = tick % n
					var vL: float = dv[off + idxL]
					s[20 + ci] = vL * (1.0 - damp) + s[20 + ci] * damp
					dv[off + idxL] = inp + s[20 + ci] * fbk
					accL += vL
					off += n + 2
					var n2: int = n + REV_SPREAD
					var idxR: int = tick % n2
					var vR: float = dv[off + idxR]
					s[26 + ci] = vR * (1.0 - damp) + s[26 + ci] * damp
					dv[off + idxR] = inp + s[26 + ci] * fbk
					accR += vR
					off += n2 + 2
				accL *= 0.24
				accR *= 0.24
				for ai in REV_AP.size():
					var na: int = REV_AP[ai]
					var ia: int = tick % na
					var bufv: float = dv[off + ia]
					var outv: float = -accL + bufv
					dv[off + ia] = accL + bufv * 0.5
					accL = outv
					off += na + 2
					var nb: int = na + REV_SPREAD
					var ib: int = tick % nb
					var bufv2: float = dv[off + ib]
					var outv2: float = -accR + bufv2
					dv[off + ib] = accR + bufv2 * 0.5
					accR = outv2
					off += nb + 2
				tick += 1
				if tick > 100000000:
					tick = 0
				var dry: float = b[i3 + i]
				var wl: float = accL
				var wr: float = accL * (1.0 - wide) + accR * wide
				b[o0 + i] = clampf(dry * (1.0 - wet) + wl * wet, -12.0, 12.0)
				b[o0 + BLK + i] = clampf(dry * (1.0 - wet) + wr * wet, -12.0, 12.0)
			s[4] = float(tick)
			peak = clampf(absf(b[o0 + BLK - 1]) / 5.0, 0.0, 1.0)
		"delay":
			var d2 := m.d
			var n3: int = d2.size() - 2
			var wi: int = int(s[0])
			var fbv: float = kv[1]
			var mixv: float = kv[2]
			for i in BLK:
				var tm: float = clampf(kv[0] * pow(2.0, b[i0 + i]), 0.001, 1.99)
				fbv = clampf(kv[1] + b[i1 + i] * 0.15, 0.0, 0.99)
				mixv = clampf(kv[2] + b[i2 + i] * 0.2, 0.0, 1.0)
				var dl: float = tm * SR
				var rp: float = float(wi) - dl
				while rp < 0.0:
					rp += float(n3)
				var r0: int = int(rp) % n3
				var r1: int = (r0 + 1) % n3
				var fr: float = rp - floor(rp)
				var wetv: float = d2[r0] * (1.0 - fr) + d2[r1] * fr
				d2[wi] = clampf(b[i3 + i] + wetv * fbv, -12.0, 12.0)
				wi = (wi + 1) % n3
				b[o0 + i] = b[i3 + i] * (1.0 - mixv) + wetv * mixv
				b[o0 + BLK + i] = wetv
			s[0] = float(wi)
			peak = clampf(absf(b[o0 + BLK - 1]) / 5.0, 0.0, 1.0)
		# ------------------------------------------------------ terminal
		"scope":
			var d3 := m.d
			var wp: int = int(s[0])
			var win2: float = kv[0]
			var stride: int = maxi(1, int(win2 * SR / 256.0))
			var cnt4: int = int(s[1])
			for i in BLK:
				cnt4 += 1
				if cnt4 >= stride:
					cnt4 = 0
					d3[wp] = b[i0 + i]
					d3[512 + wp] = b[i1 + i]
					wp = (wp + 1) % 512
				b[o0 + i] = b[i0 + i]
			s[0] = float(wp)
			s[1] = float(cnt4)
			peak = clampf(absf(b[i0 + BLK - 1]) / 5.0, 0.0, 1.0)
		# --------------------------------------------------------- input
		"button":
			var lvl4: float = kv[0]
			for bi in 2:
				var gv2: float = lvl4 if m.st[bi * 2] > 0.5 else 0.0
				var lv2: float = lvl4 if m.st[bi * 2 + 1] > 0.5 else 0.0
				var gb := o0 + BLK * (bi * 2)
				var lb := o0 + BLK * (bi * 2 + 1)
				for i in BLK:
					b[gb + i] = gv2
					b[lb + i] = lv2
			peak = 1.0 if (m.st[0] > 0.5 or m.st[2] > 0.5) else 0.1
		"xy":
			var spring: bool = m.sw[0] == 1
			var held2: bool = m.st[2] > 0.5
			var tx: float = (m.st[0] * 2.0 - 1.0) * kv[0]
			var ty: float = ((1.0 - m.st[1]) * 2.0 - 1.0) * kv[1]
			if spring and not held2:
				tx = 0.0
				ty = 0.0
			var ax: float = 1.0 - exp(-1.0 / maxf(0.0004, kv[2] * 0.4) / SR)
			var cxv: float = s[0]
			var cyv: float = s[1]
			for i in BLK:
				cxv += (tx - cxv) * ax
				cyv += (ty - cyv) * ax
				b[o0 + i] = cxv
				b[o0 + BLK + i] = cyv
				b[o0 + BLK * 2 + i] = 5.0 if held2 else 0.0
			s[0] = cxv
			s[1] = cyv
			peak = 1.0 if held2 else 0.15
		"cast":
			# s[0] granted freq · s[1] bumped · s[2] listeners · s[3] level
			s[3] = cast_level
			peak = clampf(cast_level * 2.0, 0.0, 1.0) if m.sw[0] == 1 else 0.05
		"world":
			var gain2: float = kv[0]
			var aw: float = 1.0 - exp(-1.0 / maxf(0.0005, kv[1] * 2.0) / SR)
			for k5 in 4:
				var tgt: float = world[k5] * gain2
				var cw: float = s[k5]
				var base4 := o0 + BLK * k5
				for i in BLK:
					cw += (tgt - cw) * aw
					b[base4 + i] = cw
				s[k5] = cw
			peak = clampf(absf(s[0]) / 5.0, 0.0, 1.0)
		"polyrhythm":
			# one counter per lane: four different lengths, one clock
			var cinS: float = b[i0 + BLK - 1]
			var rinS: float = b[i1 + BLK - 1]
			var lcS: float = s[4]
			var lrS: float = s[5]
			var stepped2 := false
			if rinS > GATE_HI and lrS <= GATE_HI:
				for k8 in 4:
					s[k8] = 0.0
			lrS = rinS
			if cinS > GATE_HI and lcS <= GATE_HI:
				stepped2 = true
			lcS = cinS
			var anyS := 0.0
			for lane in 4:
				var lenL: int = clampi(int(round(kv[lane])), 1, 16)
				if stepped2:
					s[lane] = fmod(s[lane] + 1.0, float(lenL))
				var siL: int = clampi(int(s[lane]), 0, 15)
				var onL: bool = m.st[lane * 16 + siL] > 0.5
				var vL2: float = 5.0 if (onL and cinS > GATE_HI) else 0.0
				if vL2 > 0.0:
					anyS = 1.0
				var baseL := o0 + BLK * lane
				for i in BLK:
					b[baseL + i] = vL2
			s[4] = lcS
			s[5] = lrS
			peak = anyS
		"stonetrig":
			# eight stones per column, four columns, read downwards
			var nS8 := 8
			var lenC: int = clampi(int(round(kv[0])), 1, nS8)
			var chainLen := 1
			var stpC: float = s[0]
			var lcC: float = s[1]
			var lrC: float = s[2]
			var firedC: float = s[3]
			var barC: float = s[6]
			var eocC := 0.0
			var cinC: float = b[i0 + BLK - 1]
			var rinC: float = b[i1 + BLK - 1]
			var chC: float = clampf(kv[1] + b[i2 + BLK - 1] / 5.0, 0.0, 1.0)
			if rinC > GATE_HI and lrC <= GATE_HI:
				stpC = 0.0
				barC = 0.0
			lrC = rinC
			# the selected column lives in the pattern data, not on a
			# knob: this panel has no room for one
			var patC: int = clampi(int(m.st[32]) if m.st.size() > 32 else 0, 0, 3)
			if _pat[mi * MAXIN + 3] == 1:
				patC = clampi(int(b[i3 + BLK - 1] / 5.0 * 4.0), 0, 3)
			if cinC > GATE_HI and lcC <= GATE_HI:
				stpC += 1.0
				if stpC >= float(lenC):
					stpC = 0.0
					eocC = 5.0
					barC = 0.0
				var siC: int = clampi(int(stpC), 0, nS8 - 1)
				firedC = 1.0 if (m.st[patC * nS8 + siC] > 0.5
					and _rng.randf() <= chC) else 0.0
			lcC = cinC
			s[7] = float(patC)
			var hvC: float = 5.0 if (firedC > 0.5 and cinC > GATE_HI) else 0.0
			var ivC: float = 0.0 if hvC > 0.0 else (5.0 if cinC > GATE_HI else 0.0)
			for i in BLK:
				b[o0 + i] = hvC
				b[o0 + BLK + i] = ivC
				b[o0 + BLK * 2 + i] = eocC
			s[0] = stpC
			s[1] = lcC
			s[2] = lrC
			s[3] = firedC
			s[6] = barC
			peak = hvC / 5.0
		"slab":
			# prime-ratio delay whose repeats come back reversed
			var dS := m.d
			var nS: int = dS.size() - 2
			var wS: int = int(s[0])
			var primes2 := [2.0, 3.0, 5.0, 7.0, 11.0]
			var pr: float = float(primes2[clampi(m.sw[0], 0, 4)]) / 4.0
			for i in BLK:
				var tmS: float = clampf(kv[0] * pow(2.0, b[i0 + i] * 0.5) * pr, 0.02, 1.9)
				var win: float = maxf(tmS * SR, 64.0)
				var ph6: float = fmod(float(wS), win) / win
				var rp4: float = float(wS) - win * (2.0 - ph6)
				while rp4 < 0.0:
					rp4 += float(nS)
				var wetS: float = dS[int(rp4) % nS]
				var fbS: float = clampf(kv[1] + b[i1 + i] * 0.1, 0.0, 0.97)
				dS[wS] = clampf(b[i2 + i] + wetS * fbS, -12.0, 12.0)
				wS = (wS + 1) % nS
				b[o0 + i] = b[i2 + i] * (1.0 - kv[2]) + wetS * kv[2]
				b[o0 + BLK + i] = wetS
			s[0] = float(wS)
			peak = clampf(absf(b[o0 + BLK - 1]) / 5.0, 0.0, 1.0)
		"gravity":
			# a voltage dropped into a well: it orbits, and sometimes it
			# gets out again
			var pos: float = s[0]
			var vel: float = s[1]
			var lkick: float = s[2]
			var esc := 0.0
			var centre: float = kv[0] + b[i0 + BLK - 1]
			var mass: float = kv[1]
			var drag: float = kv[2]
			var kickv: float = b[i1 + BLK - 1]
			if kickv > GATE_HI and lkick <= GATE_HI:
				vel += kv[3] * (1.0 if _rng.randf() > 0.5 else -1.0)
			lkick = kickv
			for i in BLK:
				vel += (centre - pos) * mass * 0.0006
				vel *= (1.0 - drag * 0.0009)
				pos += vel
				if absf(pos - centre) > 9.0:
					esc = 5.0
					pos = clampf(pos, centre - 9.0, centre + 9.0)
					vel = -vel * 0.4
				b[o0 + i] = clampf(pos, -10.0, 10.0)
				b[o0 + BLK + i] = clampf(vel * 40.0, -10.0, 10.0)
				b[o0 + BLK * 2 + i] = esc
			s[0] = pos
			s[1] = vel
			s[2] = lkick
			peak = clampf(absf(pos) / 5.0, 0.0, 1.0)
		"freeze":
			# catch a moment of sound and refuse to give it back
			var dF := m.d
			var nF: int = dF.size() - 2
			var wF: int = int(s[0])
			var rF: float = s[1]
			var held: bool = (kv[0] > 0.5) or (b[i0 + BLK - 1] > GATE_HI)
			var drop: float = [0.5, 0.667, 1.0][clampi(m.sw[0], 0, 2)]
			var winF: float = clampf(kv[1] * SR, 400.0, float(nF) - 8.0)
			for i in BLK:
				if not held:
					dF[wF] = b[i1 + i]
					wF = (wF + 1) % nF
					rF = float(wF)
					b[o0 + i] = b[i1 + i]
				else:
					rF += drop
					if rF >= float(wF):
						rF -= winF
					if rF < float(wF) - winF:
						rF += winF
					var ri: int = int(rF) % nF
					if ri < 0:
						ri += nF
					var vF: float = dF[ri]
					var ri2: int = int(float(wF) - fmod(float(wF) - rF, winF) * 0.5) % nF
					if ri2 < 0:
						ri2 += nF
					vF += dF[ri2] * kv[2] * 0.6
					b[o0 + i] = b[i1 + i] * (1.0 - kv[3]) + clampf(vF, -12.0, 12.0) * kv[3]
			s[0] = float(wF)
			s[1] = rF
			peak = 1.0 if held else clampf(absf(b[o0 + BLK - 1]) / 5.0, 0.0, 1.0)
		"dustgate":
			# every so often a sliver of the signal gets stuck
			var dD := m.d
			var nD: int = dD.size() - 2
			var wD: int = int(s[0])
			var stut: float = s[1]
			var slen: float = s[2]
			var spos: float = s[3]
			var chD: float = clampf(kv[0] + b[i0 + BLK - 1] / 5.0, 0.0, 1.0)
			var szD: float = clampf(kv[1] * pow(2.0, b[i1 + BLK - 1] * 0.5), 0.005, 0.4)
			for i in BLK:
				dD[wD] = b[i2 + i]
				wD = (wD + 1) % nD
				if stut <= 0.0:
					b[o0 + i] = b[i2 + i]
					if _rng.randf() < chD * 0.0006:
						slen = maxf(szD * SR, 32.0)
						spos = 0.0
						stut = slen * round(kv[2])
				else:
					var rd: int = int(float(wD) - slen + fmod(spos, slen))
					while rd < 0:
						rd += nD
					b[o0 + i] = dD[rd % nD]
					spos += 1.0
					stut -= 1.0
				b[o0 + BLK + i] = 5.0 if stut > 0.0 else 0.0
			s[0] = float(wD)
			s[1] = stut
			s[2] = slen
			s[3] = spos
			peak = 1.0 if stut > 0.0 else 0.2
		"watcher":
			# partials stacked, then notched OUT: carving, not filtering
			var nP2: int = [4, 8, 12][clampi(m.sw[0], 0, 2)]
			var i3w := _src[mi * MAXIN + 3]
			var baseW: float = C4 * pow(2.0, kv[0] + _brand_drift(m))
			var phW: float = s[0]
			var subW: float = s[1]
			var lsW: float = s[2]
			var driftW: float = s[3]
			for i in BLK:
				var chis: float = clampf(kv[1] + b[i1 + i] * 0.15, 0.0, 1.0)
				var grain: float = clampf(kv[2] + b[i2 + i] * 0.15, 0.0, 1.0)
				var fW: float = clampf(baseW * pow(2.0, b[i0 + i]), 0.5, SR * 0.45)
				var syn2: float = b[i3w + i]
				if syn2 > GATE_HI and lsW <= GATE_HI:
					phW = 0.0
					subW = 0.0
				lsW = syn2
				phW += fW / SR
				if phW >= 1.0:
					phW -= 1.0
					subW = 1.0 - subW
				var acc7 := 0.0
				for k in nP2:
					var kn2 := float(k + 1)
					if fW * kn2 > SR * 0.45:
						break
					# the chisel cuts a moving notch through the stack
					var cut: float = 1.0 - chis * absf(sin(kn2 * (0.6 + chis * 2.4)))
					acc7 += sin(TAU * phW * kn2) * (cut / kn2)
				acc7 += (_rng.randf() * 2.0 - 1.0) * grain * 0.35
				b[o0 + i] = clampf(acc7 * 3.2, -10.0, 10.0)
				b[o0 + BLK + i] = (4.0 if subW > 0.5 else -4.0)
				b[o0 + BLK * 2 + i] = 5.0 if phW < 0.5 else -5.0
			s[0] = phW
			s[1] = subW
			s[2] = lsW
			s[3] = driftW
			peak = 0.8
		"mystery":
			# it was already doing this when the dudes got here
			var xM: float = s[0] if absf(s[0]) > 0.0001 else 0.137
			var yM: float = s[1] if absf(s[1]) > 0.0001 else -0.41
			var zM: float = s[2] if absf(s[2]) > 0.0001 else 0.62
			# the three jacks under the knobs lean on the knobs themselves
			var i3m := _src[mi * MAXIN + 3]
			var i4m := _src[mi * MAXIN + 4]
			var i5m := _src[mi * MAXIN + 5]
			var la: float = clampf(kv[0] + b[i3m + BLK - 1] * 0.2, 0.0, 1.0)
			var ps: float = clampf(kv[1] + b[i4m + BLK - 1] * 0.2, 0.0, 1.0)
			var om: float = clampf(kv[2] + b[i5m + BLK - 1] * 0.2, 0.0, 1.0)
			var e_c := 2.718281828459045
			for i in BLK:
				var ia: float = b[i0 + i] * 0.2
				var ib: float = b[i1 + i] * 0.2
				var ic: float = b[i2 + i] * 0.2
				var nx2: float = sin((yM + ic) * e_c * (0.5 + la * 3.0)) \
					- zM * tanh(xM * (1.0 + ia))
				var ny2: float = tanh((xM + ia) * (zM + 1.4) * (0.3 + ps * 2.2)) \
					+ cos(yM * e_c) * 0.35
				var nz2: float = fposmod(zM + xM * yM * (0.2 + om * 1.6)
					+ ib * 0.1 + 1.0, 2.0) - 1.0
				xM = clampf(nx2, -2.0, 2.0)
				yM = clampf(ny2, -2.0, 2.0)
				zM = clampf(nz2, -2.0, 2.0)
				b[o0 + i] = clampf(xM * 4.0, -10.0, 10.0)
				b[o0 + BLK + i] = clampf(yM * 4.0, -10.0, 10.0)
				b[o0 + BLK * 2 + i] = clampf(zM * 4.0, -10.0, 10.0)
			s[0] = xM
			s[1] = yM
			s[2] = zM
			# a scribbled trace for the display, ring-buffered
			var wi3: int = int(s[3]) % 24
			s[8 + wi3] = xM
			s[3] = float((wi3 + 1) % 24)
			peak = clampf(absf(xM), 0.0, 1.0)
		"wrathtap":
			# the stone is listening to something older than the rack
			var gW: float = kv[0]
			var aW: float = 1.0 - exp(-1.0 / maxf(0.0005, kv[1] * 2.0) / SR)
			var wr: float = world[3] * gW
			var ch2: float = (world[4] if world.size() > 4 else 0.0) * gW
			var omen := 0.0
			if absf(ch2 - s[2]) > 0.01 or absf(wr - s[3]) > 0.4:
				omen = 5.0
			s[2] = ch2
			s[3] = wr
			var cw: float = s[0]
			var cc: float = s[1]
			for i in BLK:
				cw += (wr - cw) * aW
				cc += (ch2 - cc) * aW
				b[o0 + i] = cw
				b[o0 + BLK + i] = cc
				b[o0 + BLK * 2 + i] = omen
			s[0] = cw
			s[1] = cc
			peak = clampf(cw / 5.0, 0.0, 1.0)
		"roll":
			var lenR2: int = clampi(int(round(kv[0])), 1, 16)
			var bank: int = clampi(int(round(kv[2])), 1, 8)
			var order: int = clampi(m.sw[0], 0, 4)
			var chainB: int = [1, 2, 4][clampi(m.sw[1], 0, 2)]
			var stepR: float = s[0]
			var lcR: float = s[1]
			var lrR: float = s[2]
			var glR: float = s[3]
			var barR: float = s[6]        # position in the song
			var dirR: float = s[5]        # ping-pong direction
			var barsHeld: float = s[4]    # bars spent on this pattern
			var eocR := 0.0
			var cinR: float = b[i0 + BLK - 1]
			var rinR: float = b[i1 + BLK - 1]
			if rinR > GATE_HI and lrR <= GATE_HI:
				stepR = 0.0
				barR = 0.0
				barsHeld = 0.0
			lrR = rinR
			if cinR > GATE_HI and lcR <= GATE_HI:
				stepR += 1.0
				if stepR >= float(lenR2):
					stepR = 0.0
					eocR = 5.0
					barsHeld += 1.0
					if barsHeld >= float(chainB):
						barsHeld = 0.0
						match order:
							1: barR = fmod(barR + 1.0, float(bank))
							2: barR = fmod(barR - 1.0 + float(bank), float(bank))
							3:
								if dirR >= 0.0:
									barR += 1.0
									if barR >= float(bank - 1):
										barR = float(maxi(bank - 1, 0))
										dirR = -1.0
								else:
									barR -= 1.0
									if barR <= 0.0:
										barR = 0.0
										dirR = 1.0
							4: barR = float(_rng.randi() % bank)
			lcR = cinR
			var patR: int = clampi(int(round(kv[1])) - 1, 0, 7)
			if _pat[mi * MAXIN + 3] == 1:
				patR = clampi(int(b[i3 + BLK - 1] / 5.0 * float(bank)), 0, bank - 1)
			if order != 0:
				patR = (patR + int(barR)) % bank
			s[7] = float(patR)
			var siR: int = clampi(int(stepR), 0, 15)
			var note2: float = m.st[patR * 16 + siR]
			var restR: bool = note2 < 0.0
			var pitchR: float = (note2 / 12.0) + kv[3] + b[i2 + BLK - 1]
			var gvR: float = 5.0 if (not restR and cinR > GATE_HI) else 0.0
			var gaR: float = 1.0 - exp(-1.0 / maxf(0.0005, kv[4] * 0.3) / SR)
			for i in BLK:
				if not restR:
					glR += (pitchR - glR) * gaR
				b[o0 + i] = glR if kv[4] > 0.001 else (glR if restR else pitchR)
				b[o0 + BLK + i] = gvR
				b[o0 + BLK * 2 + i] = eocR
			s[0] = stepR
			s[1] = lcR
			s[2] = lrR
			s[3] = glR
			s[4] = barsHeld
			s[5] = dirR
			s[6] = barR
			peak = 1.0 if gvR > 0.0 else 0.15
		"beatbox":
			# eight voices, each with its own lane and its own character
			var lenB: int = 16
			var stpB: float = s[0]
			var lcB: float = s[1]
			var lrB: float = s[2]
			var swB: float = s[3]              # swing phase carry
			var cinB: float = b[i0 + BLK - 1]
			var rinB: float = b[i1 + BLK - 1]
			var accB: float = clampf(b[i2 + BLK - 1] / 5.0, 0.0, 1.0)
			if rinB > GATE_HI and lrB <= GATE_HI:
				stpB = 0.0
			lrB = rinB
			if cinB > GATE_HI and lcB <= GATE_HI:
				# SWING: odd sixteenths arrive late by up to 70% of a step
				var late: float = kv[3] * (1.0 if int(stpB) % 2 == 0 else 0.0)
				if late > 0.001 and swB <= 0.0:
					swB = late * 0.12          # hold this step back a moment
				else:
					swB = 0.0
					stpB = fmod(stpB + 1.0, float(lenB))
					var siN: int = clampi(int(stpB), 0, 15)
					for lane in 8:
						if m.st[lane * 16 + siN] > 0.5:
							s[8 + lane] = 0.0     # (re)strike that voice
							s[16 + lane] = 0.0    # ...and reset its phase
			if swB > 0.0:
				swB = maxf(0.0, swB - float(BLK) / SR)
			lcB = cinB
			var siB2: int = clampi(int(stpB), 0, 15)
			var kit: int = clampi(m.sw[0], 0, 2)
			var tuneB: float = kv[0] * [1.0, 1.25, 0.72][kit]
			var decB: float = kv[1] * [1.0, 0.6, 1.6][kit]
			var snapB: float = kv[2]
			var sprd2: float = kv[4]
			var lvlB: float = kv[5] * (1.0 + accB * 0.6)
			var hpB: float = s[24]
			# per-lane decay and pan: a kit, not four copies of one drum
			var lane_dec := [1.0, 0.7, 0.22, 0.75, 0.5, 1.1, 0.18, 0.9]
			var lane_pan := [0.0, -0.15, 0.35, -0.4, 0.45, -0.55, 0.6, -0.7]
			for i in BLK:
				var mixL := 0.0
				var mixR := 0.0
				var busK := 0.0
				var busS := 0.0
				var busH := 0.0
				var busP := 0.0
				for lane in 8:
					var tB: float = s[8 + lane]
					if tB > 3.0:
						continue
					var dcy: float = maxf(decB * float(lane_dec[lane]), 0.008)
					var envB: float = exp(-tB / dcy)
					var vB := 0.0
					match lane:
						0:   # KICK: sine with a hard pitch drop
							s[16] += tuneB * (1.0 + 5.0 * exp(-tB * 42.0)) / SR
							vB = sin(TAU * s[16]) * envB
						1:   # SNARE: body tone plus filtered noise
							s[17] += tuneB * 3.2 / SR
							var nzB: float = _rng.randf() * 2.0 - 1.0
							hpB = nzB - hpB * 0.2
							vB = sin(TAU * s[17]) * envB * (1.0 - snapB) * 0.9 \
								+ hpB * envB * snapB
						2:   # CLOSED HAT: bright, cut short
							var nz2B: float = _rng.randf() * 2.0 - 1.0
							hpB = 0.5 * (nz2B - hpB)
							vB = hpB * envB * 2.0
						3:   # OPEN HAT: the same metal, left ringing
							var nz3B: float = _rng.randf() * 2.0 - 1.0
							hpB = 0.6 * (nz3B - hpB)
							vB = hpB * envB * 1.6
						4:   # CLAP: a stutter of bursts, then a tail
							var burstB: float = exp(-fmod(tB, 0.011) * 300.0) if tB < 0.045 else 1.0
							var nz4B: float = _rng.randf() * 2.0 - 1.0
							hpB = nz4B - hpB * 0.15
							vB = hpB * envB * burstB
						5:   # TOM: a slower pitch fall
							s[21] += tuneB * 1.6 * (1.0 + 1.6 * exp(-tB * 16.0)) / SR
							vB = sin(TAU * s[21]) * envB
						6:   # RIM: one very short click of tone
							s[22] += tuneB * 7.0 / SR
							vB = (sin(TAU * s[22]) * 0.6
								+ (_rng.randf() * 2.0 - 1.0) * 0.4) * envB
						_:   # COWBELL: two detuned squares, because yes
							s[23] += tuneB * 5.4 / SR
							var sq1: float = 1.0 if fmod(s[23], 1.0) < 0.5 else -1.0
							var sq2: float = 1.0 if fmod(s[23] * 1.48, 1.0) < 0.5 else -1.0
							vB = (sq1 + sq2) * 0.35 * envB
					var pan2: float = float(lane_pan[lane]) * sprd2
					mixL += vB * (1.0 - maxf(pan2, 0.0))
					mixR += vB * (1.0 + minf(pan2, 0.0))
					if lane == 0:
						busK += vB
					elif lane == 1:
						busS += vB
					elif lane == 2 or lane == 3:
						busH += vB
					else:
						busP += vB
					s[8 + lane] = tB + 1.0 / SR
				b[o0 + i] = clampf(mixL * lvlB, -1.4, 1.4) * 5.0
				b[o0 + BLK + i] = clampf(mixR * lvlB, -1.4, 1.4) * 5.0
				b[o0 + BLK * 2 + i] = clampf(busK * lvlB, -1.4, 1.4) * 5.0
				b[o0 + BLK * 3 + i] = clampf(busS * lvlB, -1.4, 1.4) * 5.0
				b[o0 + BLK * 4 + i] = clampf(busH * lvlB, -1.4, 1.4) * 5.0
				b[o0 + BLK * 5 + i] = clampf(busP * lvlB, -1.4, 1.4) * 5.0
			s[0] = stpB
			s[1] = lcB
			s[2] = lrB
			s[3] = swB
			s[24] = hpB
			peak = clampf(absf(b[o0 + BLK - 1]) / 5.0, 0.0, 1.0)
		# --------------------------------------------- house exclusives
		"voice":
			var wv: int = clampi(m.sw[0], 0, 2)
			var basev: float = C4 * pow(2.0, kv[0] + _brand_drift(m))
			var phv: float = s[0]
			var env2: float = s[1]
			var lgv: float = s[2]
			var ic1v: float = s[3]
			var ic2v: float = s[4]
			var dcy: float = exp(-1.0 / maxf(kv[3], 0.01) / SR)
			var kres: float = 2.0 - 1.9 * kv[2]
			var i2v := _src[mi * MAXIN + 2]
			var gv3 := 0.0
			var a1v := 0.0
			var a2v := 0.0
			var a3v := 0.0
			for i in BLK:
				var gt2: float = b[i1 + i]
				if gt2 > GATE_HI and lgv <= GATE_HI:
					env2 = 1.0
				lgv = gt2
				env2 = maxf(env2 * dcy, 0.30 if gt2 > GATE_HI else 0.0)
				var fv: float = clampf(basev * pow(2.0, b[i0 + i]), 0.5, SR * 0.45)
				phv = fmod(phv + fv / SR, 1.0)
				var dtv: float = fv / SR
				var raw: float = 0.0
				if wv == 0:
					raw = 2.0 * phv - 1.0 - _bl(phv, dtv)
				elif wv == 1:
					raw = (1.0 if phv < 0.5 else -1.0) + _bl(phv, dtv) - _bl(fmod(phv + 0.5, 1.0), dtv)
				else:
					raw = 4.0 * absf(phv - 0.5) - 1.0
				if i % SUB == 0:
					var fc3: float = clampf(kv[1] * (0.30 + 0.9 * env2)
						* pow(2.0, b[i2v + i] * 0.6), 20.0, SR * 0.44)
					var g4: float = tan(PI * fc3 / SR)
					a1v = 1.0 / (1.0 + g4 * (g4 + kres))
					a2v = g4 * a1v
					a3v = g4 * a2v
				var x5: float = raw * 5.0
				var v3v: float = x5 - ic2v
				var v1v: float = a1v * ic1v + a2v * v3v
				var v2v: float = ic2v + a2v * ic1v + a3v * v3v
				ic1v = 2.0 * v1v - ic1v
				ic2v = 2.0 * v2v - ic2v
				b[o0 + i] = clampf(v2v * env2 * kv[4], -10.0, 10.0)
			s[0] = phv
			s[1] = env2
			s[2] = lgv
			s[3] = ic1v
			s[4] = ic2v
			peak = env2
		"tape":
			var dt2 := m.d
			var n5: int = dt2.size() - 2
			var wi2: int = int(s[0])
			var wowph: float = s[1]
			var lpT: float = s[2]
			for i in BLK:
				wowph = fmod(wowph + 0.7 / SR, 1.0)
				var wob: float = (sin(TAU * wowph) * 0.6 + sin(TAU * wowph * 3.7) * 0.4) \
					* kv[3] * 0.02
				var tm2: float = clampf(kv[0] * pow(2.0, b[i1 + i] * 0.5) * (1.0 + wob), 0.002, 1.95)
				var rp2: float = float(wi2) - tm2 * SR
				while rp2 < 0.0:
					rp2 += float(n5)
				var r0b: int = int(rp2) % n5
				var r1b: int = (r0b + 1) % n5
				var frb: float = rp2 - floor(rp2)
				var wetv2: float = dt2[r0b] * (1.0 - frb) + dt2[r1b] * frb
				lpT += (wetv2 - lpT) * 0.45          # the tape loses its highs
				var into: float = tanh((b[i0 + i] + lpT * kv[1]) / 5.0 * kv[4]) * 5.0
				dt2[wi2] = clampf(into, -12.0, 12.0)
				wi2 = (wi2 + 1) % n5
				b[o0 + i] = b[i0 + i] * (1.0 - kv[2]) + wetv2 * kv[2]
				b[o0 + BLK + i] = wetv2
			s[0] = float(wi2)
			s[1] = wowph
			s[2] = lpT
			peak = clampf(absf(b[o0 + BLK - 1]) / 5.0, 0.0, 1.0)
		"chaos":
			# Lorenz, integrated at whatever rate you ask for, plus a
			# logistic map that steps on the clock
			var xL: float = s[0] if absf(s[0]) > 0.0001 else 0.1
			var yL: float = s[1]
			var zL: float = s[2]
			var lck: float = s[3]
			var logv: float = s[4] if s[4] > 0.0001 else 0.4
			var rate4: float = kv[0] * pow(2.0, b[i0 + BLK - 1] * 0.5)
			var hstep: float = clampf(rate4 * 0.0006, 0.0, 0.02)
			for i in BLK:
				var dx: float = 10.0 * (yL - xL)
				var dy: float = xL * (28.0 - zL) - yL
				var dz: float = xL * yL - (8.0 / 3.0) * zL
				xL += dx * hstep
				yL += dy * hstep
				zL += dz * hstep
				var ck2: float = b[i1 + i]
				if ck2 > GATE_HI and lck <= GATE_HI:
					logv = clampf(kv[2] * logv * (1.0 - logv), 0.0, 1.0)
				lck = ck2
				var sc: float = kv[1] / 20.0
				b[o0 + i] = clampf(xL * sc + kv[3], -10.0, 10.0)
				b[o0 + BLK + i] = clampf(yL * sc + kv[3], -10.0, 10.0)
				b[o0 + BLK * 2 + i] = clampf((zL - 25.0) * sc + kv[3], -10.0, 10.0)
				b[o0 + BLK * 3 + i] = clampf((logv * 2.0 - 1.0) * kv[1] + kv[3], -10.0, 10.0)
			s[0] = xL
			s[1] = yL
			s[2] = zL
			s[3] = lck
			s[4] = logv
			for k6 in 16:
				s[8 + k6] = 1.0 if fmod(absf(xL) * 3.0 + float(k6), 4.0) > 2.0 else 0.0
			peak = clampf(absf(xL) / 20.0, 0.0, 1.0)
		"poly20":
			var nS: int = 20
			var lenP: int = clampi(int(round(kv[0])), 2, nS)
			var stepP: float = s[0]
			var lcP: float = s[1]
			var lrP: float = s[2]
			var glP: float = s[3]
			var eocP := 0.0
			var cinP: float = b[i0 + BLK - 1]
			var rinP: float = b[i1 + BLK - 1]
			var jmp: float = clampf(kv[1] + b[i2 + BLK - 1] / 5.0, 0.0, 1.0)
			if rinP > GATE_HI and lrP <= GATE_HI:
				stepP = 0.0
			lrP = rinP
			if cinP > GATE_HI and lcP <= GATE_HI:
				if _rng.randf() < jmp:
					stepP = float(_rng.randi() % lenP)   # leap across the solid
				else:
					stepP += 1.0
					if stepP >= float(lenP):
						stepP = 0.0
						eocP = 5.0
			lcP = cinP
			var siP: int = clampi(int(stepP), 0, nS - 1)
			var pitchP: float = (m.st[siP] * 2.0 - 1.0) * kv[2]
			var gonP: bool = m.st[nS + siP] > 0.5
			var gvP: float = 5.0 if (gonP and cinP > GATE_HI) else 0.0
			var gaP: float = 1.0 - exp(-1.0 / maxf(0.0005, kv[3] * 0.3) / SR)
			for i in BLK:
				glP += (pitchP - glP) * gaP
				b[o0 + i] = glP if kv[3] > 0.001 else pitchP
				b[o0 + BLK + i] = gvP
				b[o0 + BLK * 2 + i] = eocP
			s[0] = stepP
			s[1] = lcP
			s[2] = lrP
			s[3] = glP
			peak = 1.0 if gvP > 0.0 else 0.15
		"eyefilter":
			# five resonant bands stacked like a throat, every control
			# with its own jack under its own knob
			var i4e := _src[mi * MAXIN + 4]
			var spread: float = clampf(kv[1] + b[i1 + BLK - 1] * 0.2, 1.02, 4.0)
			var kres2: float = 2.0 - 1.98 * clampf(kv[2] + b[i2 + BLK - 1] * 0.15, 0.0, 0.99)
			var mixE: float = clampf(kv[3] + b[i3 + BLK - 1] * 0.2, 0.0, 1.0)
			var envE: float = s[20]
			var gE := PackedFloat32Array()
			gE.resize(5)
			for bnd in 5:
				var fb2: float = clampf(kv[0] * pow(spread, float(bnd))
					* pow(2.0, b[i0 + BLK - 1] * 0.5), 30.0, SR * 0.44)
				gE[bnd] = tan(PI * fb2 / SR)
			for i in BLK:
				var xin: float = b[i4e + i]
				var acc3 := 0.0
				for bnd in 5:
					var g5: float = gE[bnd]
					var a1e: float = 1.0 / (1.0 + g5 * (g5 + kres2))
					var a2e: float = g5 * a1e
					var a3e: float = g5 * a2e
					var ic1e: float = s[bnd * 2]
					var ic2e: float = s[bnd * 2 + 1]
					var v3e: float = xin - ic2e
					var v1e: float = a1e * ic1e + a2e * v3e
					var v2e: float = ic2e + a2e * ic1e + a3e * v3e
					s[bnd * 2] = 2.0 * v1e - ic1e
					s[bnd * 2 + 1] = 2.0 * v2e - ic2e
					acc3 += v1e * (1.0 - float(bnd) * 0.12)
				var outE: float = clampf(acc3 * 0.55, -12.0, 12.0)
				envE += (absf(outE) - envE) * 0.002
				b[o0 + i] = xin * (1.0 - mixE) + outE * mixE
				b[o0 + BLK + i] = clampf(envE, 0.0, 5.0)
			s[20] = envE
			peak = clampf(envE / 3.0, 0.0, 1.0)
		"obelisk":
			var ext2: bool = m.sw[0] == 1
			var phO: float = s[0]
			var cntO: float = s[1]
			var lcO: float = s[2]
			var lrO: float = s[3]
			var highO: float = s[4]
			var rinO: float = b[i1 + BLK - 1]
			if rinO > GATE_HI and lrO <= GATE_HI:
				cntO = 0.0
				phO = 0.0
			lrO = rinO
			var steppedO := false
			if ext2:
				var eO: float = b[i0 + BLK - 1]
				if eO > GATE_HI and lcO <= GATE_HI:
					steppedO = true
				lcO = eO
				highO = 1.0 if eO > GATE_HI else 0.0
			else:
				var drift: float = 1.0 + sin(float(_blocks) * 0.0007) * kv[1] * 0.25
				phO += float(BLK) / SR * (kv[0] / 60.0 * 2.0) * drift
				if phO >= 1.0:
					phO -= 1.0
					steppedO = true
				highO = 1.0 if phO < kv[2] else 0.0
			if steppedO:
				cntO += 1.0
			var hO: float = 5.0 if highO > 0.5 else 0.0
			var cO := int(cntO)
			var primes := [2, 3, 5, 7, 11]
			for k7 in 5:
				var vP: float = hO if cO % int(primes[k7]) == 0 else 0.0
				var baseP := o0 + BLK * k7
				for i in BLK:
					b[baseP + i] = vP
			s[0] = phO
			s[1] = cntO
			s[2] = lcO
			s[3] = lrO
			s[4] = highO
			peak = highO
		"dudemix":
			var mst2: float = kv[12]
			var il := PackedInt32Array()
			il.resize(6)
			for ch in 6:
				il[ch] = _src[mi * MAXIN + ch]
			var mtr := PackedFloat32Array()
			mtr.resize(6)
			mtr.fill(0.0)
			for i in BLK:
				var l3 := 0.0
				var r3 := 0.0
				for ch in 6:
					var raw3: float = b[il[ch] + i]
					mtr[ch] = maxf(mtr[ch], absf(raw3))
					if m.st.size() > ch and m.st[ch] > 0.5:
						continue        # muted strip
					var v9: float = raw3 * kv[ch]
					var pan: float = clampf(kv[6 + ch], -1.0, 1.0)
					l3 += v9 * (1.0 - maxf(pan, 0.0))
					r3 += v9 * (1.0 + minf(pan, 0.0))
				l3 = clampf(l3 * mst2, -12.0, 12.0)
				r3 = clampf(r3 * mst2, -12.0, 12.0)
				b[o0 + i] = l3
				b[o0 + BLK + i] = r3
				b[o0 + BLK * 2 + i] = (l3 + r3) * 0.5
			for ch in 6:
				# the meters fall back slowly, like meters do
				s[8 + ch] = maxf(mtr[ch] / 5.0, s[8 + ch] - 0.05)
			peak = clampf(absf(b[o0 + BLK - 1]) / 5.0, 0.0, 1.0)
		"squash":
			var i3s := _src[mi * MAXIN + 3]
			var i4s := _src[mi * MAXIN + 4]
			var envS: float = s[0]
			var slow: bool = m.sw[0] == 1
			var atk: float = 1.0 - exp(-1.0 / (0.003 if not slow else 0.03) / SR)
			var rel: float = 1.0 - exp(-1.0 / (0.08 if not slow else 0.4) / SR)
			var sc_patched: bool = _pat[mi * MAXIN + 4] == 1
			for i in BLK:
				var thr: float = clampf(kv[0] + b[i0 + i], -10.0, 0.0)
				var rat: float = clampf(kv[1] + b[i1 + i], 1.0, 40.0)
				var mk: float = clampf(kv[2] + b[i2 + i] * 0.3, 0.1, 16.0)
				var det: float = absf(b[i4s + i] if sc_patched else b[i3s + i])
				envS += (det - envS) * (atk if det > envS else rel)
				var over: float = maxf(0.0, 20.0 * log(maxf(envS, 0.0001) / 5.0)
					/ log(10.0) - thr * 4.0)
				var gr: float = -over * (1.0 - 1.0 / rat)
				var g6: float = pow(10.0, gr / 20.0)
				b[o0 + i] = clampf(b[i3s + i] * g6 * mk, -12.0, 12.0)
				b[o0 + BLK + i] = clampf(-gr * 0.5, 0.0, 5.0)
			s[0] = envS
			peak = clampf(envS / 5.0, 0.0, 1.0)
		"grit":
			var holdv: float = s[0]
			var phc: float = s[1]
			for i in BLK:
				var srate: float = clampf(kv[0] * pow(2.0, b[i0 + i] * 0.5), 100.0, SR)
				var bits: float = clampf(kv[1] + b[i1 + i], 1.0, 16.0)
				phc += srate / SR
				if phc >= 1.0:
					phc -= 1.0
					var steps2: float = pow(2.0, bits)
					holdv = round(b[i2 + i] / 5.0 * steps2) / steps2 * 5.0
				b[o0 + i] = b[i2 + i] * (1.0 - kv[2]) + holdv * kv[2]
			s[0] = holdv
			s[1] = phc
			peak = clampf(absf(holdv) / 5.0, 0.0, 1.0)
		"grains":
			var dg := m.d
			var ng: int = dg.size() - 2
			var wg: int = int(s[0])
			for i in BLK:
				dg[wg] = b[i3 + i]
				wg = (wg + 1) % ng
				var acc4 := 0.0
				for gi in 3:
					var gp: float = s[4 + gi]
					var glen: float = maxf(0.005, kv[0] * pow(2.0, b[i0 + i] * 0.5)) * SR
					var rate5: float = pow(2.0, kv[1] + b[i1 + i])
					gp += rate5
					if gp >= glen:
						gp = 0.0
						var spray: float = clampf(kv[2] + b[i2 + i] * 0.2, 0.0, 1.0)
						var st6: float = float(wg) - _rng.randf() * spray * SR * 1.5 - 200.0
						while st6 < 0.0:
							st6 += float(ng)
						s[8 + gi] = fmod(st6, float(ng))
					s[4 + gi] = gp
					var rpos: int = int(s[8 + gi] + gp) % ng
					var win: float = sin(PI * clampf(gp / glen, 0.0, 1.0))
					acc4 += dg[rpos] * win
				b[o0 + i] = b[i3 + i] * (1.0 - kv[3]) + clampf(acc4 * 0.6, -12.0, 12.0) * kv[3]
			s[0] = float(wg)
			peak = clampf(absf(b[o0 + BLK - 1]) / 5.0, 0.0, 1.0)
		"harmonic":
			var phH: float = s[0]
			var baseH: float = C4 * pow(2.0, kv[0])
			var tilt: float = clampf(kv[1] + b[i1 + BLK - 1] * 0.2, -1.0, 1.0)
			for i in BLK:
				var fH: float = clampf(baseH * pow(2.0, b[i0 + i]), 0.5, SR * 0.45)
				phH = fmod(phH + fH / SR, 1.0)
				var acc5 := 0.0
				for k9 in 20:
					var amp5: float = m.st[k9] if m.st.size() > k9 else 0.0
					if amp5 <= 0.001:
						continue
					if fH * float(k9 + 1) > SR * 0.45:
						break
					var w5: float = pow(float(k9 + 1), -tilt)
					acc5 += sin(TAU * phH * float(k9 + 1)) * amp5 * w5
				b[o0 + i] = clampf(acc5 * 0.6, -10.0, 10.0) * kv[2]
			s[0] = phH
			peak = clampf(absf(b[o0 + BLK - 1]) / 5.0, 0.0, 1.0)
		"arp":
			# hold a note, feed it a clock, and it spins an arpeggio out
			var ordr: int = clampi(m.sw[0], 0, 3)
			var lcA: float = s[1]
			var lgA: float = s[2]
			var stepA: float = s[3]
			var heldA: float = s[4]
			var glA: float = s[5]
			var gA: float = b[i1 + BLK - 1]
			var gate_patched: bool = _pat[mi * MAXIN + 1] == 1
			if not gate_patched:
				gA = 5.0            # no gate patched: run free
			if gA > GATE_HI and lgA <= GATE_HI:
				heldA = b[i0 + BLK - 1]
				stepA = 0.0
			lgA = gA
			var n7: int = maxi(2, int(round(kv[0])) * 2)
			var ckA: float = b[i2 + BLK - 1]
			if ckA > GATE_HI and lcA <= GATE_HI:
				match ordr:
					0:
						stepA = fmod(stepA + 1.0, float(n7))
					1:
						stepA = fmod(stepA - 1.0 + float(n7), float(n7))
					2:
						stepA = fmod(stepA + 1.0, float(maxi(n7 * 2 - 2, 1)))
					_:
						stepA = float(_rng.randi() % n7)
			lcA = ckA
			var stp2: int = int(stepA)
			if ordr == 2 and stp2 >= n7:
				stp2 = n7 * 2 - 2 - stp2
			stp2 = clampi(stp2, 0, n7 - 1)
			var oct2: int = stp2 / 2
			var half: int = stp2 % 2
			var cvA: float = heldA + float(oct2) + (kv[1] / 12.0 if half == 1 else 0.0)
			var gaA: float = 1.0 - exp(-1.0 / maxf(0.0005, kv[2] * 0.3) / SR)
			var gateA: float = 5.0 if (gA > GATE_HI and ckA > GATE_HI) else 0.0
			for i in BLK:
				glA += (cvA - glA) * gaA
				b[o0 + i] = glA if kv[2] > 0.001 else cvA
				b[o0 + BLK + i] = gateA
			s[1] = lcA
			s[2] = lgA
			s[3] = stepA
			s[4] = heldA
			s[5] = glA
			peak = clampf(float(stp2) / float(maxi(n7 - 1, 1)), 0.0, 1.0)
		"drone":
			var ratios: Array = [[1.0, 2.0, 3.0, 4.0], [1.0, 3.0, 5.0, 7.0],
				[2.0, 3.0, 5.0, 8.0]][clampi(m.sw[0], 0, 2)]
			var baseD: float = C4 * pow(2.0, kv[0] + _brand_drift(m))
			var sprd: float = clampf(kv[1] + b[i1 + BLK - 1] * 0.1, 0.0, 1.0)
			var lvlD: float = clampf(kv[2] + b[i2 + BLK - 1] * 0.2, 0.0, 2.0)
			for i in BLK:
				var fD: float = clampf(baseD * pow(2.0, b[i0 + i]), 0.5, SR * 0.2)
				var accD := 0.0
				var subD := 0.0
				for v2 in 4:
					var det: float = 1.0 + sprd * 0.01 * (float(v2) - 1.5)
					var ph5: float = s[v2] + fD * float(ratios[v2]) * det / SR
					if ph5 >= 1.0:
						ph5 -= 1.0
					s[v2] = ph5
					accD += (2.0 * ph5 - 1.0) / float(v2 + 1)
					if v2 == 0:
						subD = 1.0 if ph5 < 0.5 else -1.0
				b[o0 + i] = clampf(accD * 1.6, -10.0, 10.0) * lvlD
				b[o0 + BLK + i] = subD * 4.0 * lvlD
			peak = clampf(lvlD, 0.0, 1.0)
		"oracle":
			var i2o := _src[mi * MAXIN + 2]
			var ltO: float = s[0]
			var burstsLeft: float = s[1]
			var bt: float = s[2]
			var passv := 0.0
			var missv := 0.0
			var chance: float = clampf(kv[0] + b[i0 + BLK - 1] / 5.0, 0.0, 1.0)
			var nburst: int = clampi(int(round(kv[1] + b[i1 + BLK - 1])), 1, 8)
			var tin2: float = b[i2o + BLK - 1]
			if tin2 > GATE_HI and ltO <= GATE_HI:
				if _rng.randf() <= chance:
					burstsLeft = float(nburst)
					bt = 0.0
					passv = 5.0
				else:
					missv = 5.0
			ltO = tin2
			if burstsLeft > 1.0:
				bt += float(BLK) / SR
				if bt >= kv[2]:
					bt = 0.0
					burstsLeft -= 1.0
					passv = 5.0
			for i in BLK:
				b[o0 + i] = passv
				b[o0 + BLK + i] = missv
			s[0] = ltO
			s[1] = burstsLeft
			s[2] = bt
			peak = passv / 5.0
		"resonator":
			var dr := m.d
			var seg2 := 2048
			var three: bool = m.sw[0] == 1
			var mixR: float = kv[2]
			var dampR: float = clampf(kv[1] + b[i1 + BLK - 1] * 0.1, 0.0, 0.98)
			var voices: Array = [1.0, 1.5, 2.0] if three else [1.0]
			for i in BLK:
				var xin2: float = b[i2 + i]
				var accR := 0.0
				for v3 in voices.size():
					var fR: float = clampf(C4 * pow(2.0, kv[0] + b[i0 + i])
						* float(voices[v3]), 25.0, 4000.0)
					var dl2: int = clampi(int(SR / fR), 2, seg2 - 2)
					var wp2: int = int(s[8 + v3])
					var rp3: int = (wp2 - dl2 + seg2) % seg2
					var base5 := v3 * seg2
					var vR: float = dr[base5 + rp3]
					var lpR: float = s[12 + v3]
					lpR = lpR + (vR - lpR) * (1.0 - dampR * 0.9)
					s[12 + v3] = lpR
					dr[base5 + wp2] = clampf(xin2 * 0.35 + lpR * (0.95 - dampR * 0.35),
						-12.0, 12.0)
					s[8 + v3] = float((wp2 + 1) % seg2)
					accR += vR
				b[o0 + i] = xin2 * (1.0 - mixR) + clampf(accR / float(voices.size()),
					-12.0, 12.0) * mixR
			peak = clampf(absf(b[o0 + BLK - 1]) / 5.0, 0.0, 1.0)
		"spectrum", "waterfall":
			# twelve bandpass filters across the range: cheap, honest, and
			# it moves like a real analyser instead of a decoration
			var nb2 := 12
			var low: float = kv[0]
			var span: float = kv[1]
			var vgain: float = kv[2]
			var fall: float = kv[3] if m.id == "spectrum" else 0.4
			var pick: int = clampi(int(round(kv[4])) - 1, 0, 11) if m.id == "spectrum" else 0
			for bnd in nb2:
				var fb3: float = clampf(low * pow(span, float(bnd)), 20.0, SR * 0.45)
				var g7: float = tan(PI * fb3 / SR)
				var a1f: float = 1.0 / (1.0 + g7 * (g7 + 0.6))
				var a2f: float = g7 * a1f
				var a3f: float = g7 * a2f
				var ic1f: float = s[bnd * 2]
				var ic2f: float = s[bnd * 2 + 1]
				var mag := 0.0
				for i in BLK:
					var xin3: float = b[i0 + i]
					var v3f: float = xin3 - ic2f
					var v1f: float = a1f * ic1f + a2f * v3f
					var v2f: float = ic2f + a2f * ic1f + a3f * v3f
					ic1f = 2.0 * v1f - ic1f
					ic2f = 2.0 * v2f - ic2f
					mag = maxf(mag, absf(v1f))
				s[bnd * 2] = ic1f
				s[bnd * 2 + 1] = ic2f
				# the bar heights live in the back half of the state
				var want: float = clampf(mag / 5.0 * vgain, 0.0, 1.0)
				var cur3: float = s[24 + bnd] if bnd + 24 < s.size() else 0.0
				s[24 + bnd] = maxf(want, cur3 - (0.02 + fall * 0.12))
			for i in BLK:
				b[o0 + i] = b[i0 + i]
			if m.id == "spectrum":
				for i in BLK:
					b[o0 + BLK + i] = s[24 + pick] * 5.0
			else:
				# the waterfall scrolls a column of the same bands
				# NOT s[22]/s[23]: twelve bands claim two state slots each,
				# so 0..23 is filter memory. The scroll used to live on top
				# of band 11's integrator -- the column head jumped to
				# wherever the filter happened to be, which is why only a
				# couple of columns ever lit up and jittered.
				s[36] += float(BLK) / SR * (0.5 + kv[3] * 24.0)
				if s[36] >= 1.0:
					s[36] = 0.0
					var col: int = int(s[37]) % 64
					for bnd2 in 12:
						m.d[bnd2 * 64 + col] = s[24 + bnd2]
					s[37] = float((col + 1) % 64)
			peak = clampf(s[24 + 2], 0.0, 1.0)
		"analyser":
			# a measuring instrument. Frequency comes from a SCHMITT
			# trigger (a plain "was below, now above" test misses
			# crossings whenever a sample lands inside the deadband, and
			# every miss doubles the measured period), and the scope
			# capture starts at the INTERPOLATED crossing so a steep edge
			# does not wobble by a sample every refresh.
			var lastx: float = s[0]
			var since: float = s[1]
			var periods: float = s[2]
			var dcacc: float = s[3]
			var armed_f: bool = s[5] > 0.5
			var wp6: int = int(s[20])
			var cap_state: int = int(s[22])     # 0 armed · 1 capturing · 2 holding
			var hold6: float = s[23]
			var acc6: float = s[24]             # samples since the trigger, fractional
			var prevx: float = s[25]
			var sens: float = kv[0]
			var stride3: int = clampi(int(maxf(periods, 8.0) * 2.0 / 256.0), 1, 64)
			var hyst: float = maxf(0.015, s[11] * 0.12)
			var pk4: float = 0.0
			var sumsq: float = 0.0
			var above: float = 0.0
			for i in BLK:
				var x6: float = b[i0 + i]
				dcacc += (x6 - dcacc) * 0.00005
				var xa: float = x6 - dcacc
				pk4 = maxf(pk4, absf(xa))
				sumsq += xa * xa
				if xa > 0.0:
					above += 1.0
				# --- frequency: Schmitt trigger, so nothing is missed
				var crossed := false
				if xa < -hyst:
					armed_f = true
				elif armed_f and xa > hyst:
					armed_f = false
					crossed = true
					if since > 3.0:
						periods = since if periods <= 1.0 else periods * 0.75 + since * 0.25
					since = 0.0
				since += 1.0
				# --- the scope capture, triggered on that same crossing
				if cap_state == 0:
					if crossed:
						cap_state = 1
						wp6 = 0
						# where between the two samples the crossing really
						# happened: start the sweep THERE, not at whichever
						# sample happened to be next
						var denom: float = xa - lastx
						var frac: float = clampf(-lastx / denom, 0.0, 1.0) \
							if absf(denom) > 0.00001 else 0.0
						acc6 = 1.0 - frac
				elif cap_state == 1:
					# capture into scratch, LONGER than the 256 shown, so the
					# frame can be slid into place afterwards
					while wp6 < CAP_LEN and float(wp6 * stride3) <= acc6:
						var t6: float = clampf(float(wp6 * stride3) - (acc6 - 1.0), 0.0, 1.0)
						m.d[256 + wp6] = lerpf(prevx, x6, t6)
						wp6 += 1
					acc6 += 1.0
					if wp6 >= CAP_LEN:
						_align_frame(m.d, s[26] > 0.5)
						s[26] = 1.0
						cap_state = 2
						hold6 = 0.0
				else:
					hold6 += 1.0 / SR
					if hold6 > 0.05:            # ~20 refreshes a second
						cap_state = 0
						armed_f = false          # re-arm on a fresh fall first
				prevx = x6
				lastx = xa
				b[o0 + BLK * 3 + i] = x6         # THRU
			s[0] = lastx
			s[1] = minf(since, SR)
			s[2] = periods
			s[3] = dcacc
			s[5] = 1.0 if armed_f else 0.0
			s[20] = float(wp6)
			s[22] = float(cap_state)
			s[23] = hold6
			s[24] = acc6
			s[25] = prevx
			var rms2: float = sqrt(sumsq / float(BLK))
			var sm: float = clampf(kv[1], 0.0, 1.0) * 0.85 + 0.1
			s[11] = maxf(pk4, s[11] * (0.90 + sm * 0.09))
			s[12] = s[12] * sm + rms2 * (1.0 - sm)
			s[13] = dcacc
			s[14] = above / float(BLK)
			var live: bool = s[12] > sens * 0.2
			var freq: float = SR / maxf(periods, 2.0)
			if live and periods > 2.0 and freq < SR * 0.45:
				s[10] = freq if s[10] <= 1.0 else s[10] * sm + freq * (1.0 - sm)
			var crest: float = s[11] / maxf(s[12], 0.0001)
			s[15] = 0.0
			if crest > 1.20:
				s[15] = 1.0
			if crest > 1.60:
				s[15] = 2.0
			if crest > 2.40:
				s[15] = 3.0
			if not live:
				s[15] = 4.0
			var pitchv: float = log(maxf(s[10], 1.0) / C4) / log(2.0)
			for i in BLK:
				b[o0 + i] = clampf(pitchv, -6.0, 6.0)
				b[o0 + BLK + i] = clampf(s[12], 0.0, 5.0)
				b[o0 + BLK * 2 + i] = 5.0 if live else 0.0
			peak = clampf(s[12] / 5.0, 0.0, 1.0)
		"vector":
			# an X/Y scope: it only has to remember where the beam went
			var vw: int = int(s[0])
			var stride2: int = 3
			var cnt5: int = int(s[1])
			for i in BLK:
				cnt5 += 1
				if cnt5 >= stride2:
					cnt5 = 0
					if m.d.size() >= 1024:
						m.d[vw] = b[i0 + i]
						m.d[512 + vw] = b[i1 + i]
						vw = (vw + 1) % 512
				b[o0 + i] = b[i0 + i]
			s[0] = float(vw)
			s[1] = float(cnt5)
			peak = clampf(absf(b[i0 + BLK - 1]) / 5.0, 0.0, 1.0)
		"vu":
			# four needles, each with a peak that hangs about
			var hold: float = 0.985 + kv[1] * 0.0149
			var anyv := 0.0
			for ch2 in 4:
				var src2 := _src[mi * MAXIN + ch2]
				var mx := 0.0
				for i in BLK:
					mx = maxf(mx, absf(b[src2 + i]))
				var lvl5: float = clampf(mx / 5.0 * kv[0], 0.0, 1.4)
				s[ch2] = maxf(lvl5, s[ch2] - 0.02)          # the needle
				s[4 + ch2] = maxf(lvl5, s[4 + ch2] * hold)   # the peak hold
				anyv = maxf(anyv, lvl5)
			for i in BLK:
				b[o0 + i] = b[i0 + i]
				b[o0 + BLK + i] = 5.0 if anyv > 0.98 else 0.0
			peak = anyv
		"out":
			var vol: float = kv[0] * 0.2
			var pR: bool = _pat[mi * MAXIN + 1] == 1
			var pk := 0.0
			for i in BLK:
				var l2: float = b[i0 + i] * vol
				var r2: float = (b[i1 + i] * vol) if pR else l2
				_outL[i] += l2
				_outR[i] += r2
				pk = maxf(pk, absf(l2))
			peak = clampf(pk, 0.0, 1.0)
		_:
			# a module in the catalogue with no DSP behind it. This has
			# happened once (nine of them, silently) -- never again.
			if not unhandled.has(m.id):
				unhandled[m.id] = true
	m.led = maxf(peak, m.led - 0.25)

## Which house built it changes how it behaves, a little: icosa gear
## runs hot and never quite settles, monolithic gear is heavy and old.
func _brand_drift(m: Mod) -> float:
	match m.brand:
		"icos":
			var t: float = float(_blocks) * float(BLK) / SR
			return (sin(t * 0.37 + float(m.hp)) * 0.5 + sin(t * 1.13) * 0.5) * 0.006
		"mono":
			return -0.004
	return 0.0

func _brand_sat(m: Mod) -> float:
	match m.brand:
		"mono":
			return 0.85
		"icos":
			return 0.35
	return 0.0

## A hash, not a dice: the same seed and the same position always give the
## same note, so a phrase you liked can be found again by dialling SEED
## back to where it was.
static func _hash01(n: int) -> float:
	var x: int = (n * 1103515245 + 12345) & 0x7FFFFFFF
	x = (x ^ (x >> 13)) * 1274126177
	x = x & 0x7FFFFFFF
	return float(x % 1000000) / 1000000.0

## The scales MUSE and CHORD BANK write in, in switch order.
static func _muse_scale(i: int) -> PackedInt32Array:
	match i:
		0: return PackedInt32Array([0, 2, 4, 5, 7, 9, 11])       # MAJOR
		1: return PackedInt32Array([0, 2, 3, 5, 7, 8, 10])       # MINOR
		2: return PackedInt32Array([0, 2, 3, 5, 7, 9, 10])       # DORIAN
		3: return PackedInt32Array([0, 1, 3, 5, 7, 8, 10])       # PHRYGIAN
		4: return PackedInt32Array([0, 2, 4, 6, 7, 9, 11])       # LYDIAN
		5: return PackedInt32Array([0, 2, 4, 5, 7, 9, 10])       # MIXOLYDIAN
		6: return PackedInt32Array([0, 2, 4, 7, 9])              # PENTATONIC +
		7: return PackedInt32Array([0, 3, 5, 7, 10])             # PENTATONIC -
		8: return PackedInt32Array([0, 3, 5, 6, 7, 10])          # BLUES
		9: return PackedInt32Array([0, 2, 4, 6, 8, 10])          # WHOLE TONE
	return PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])

## Write (or partly rewrite) a phrase. `amount` is how much of it is
## replaced -- 1.0 for a fresh tune, VARY for the slow drift that makes the
## melody familiar but never identical. Notes are scale DEGREES, so any
## note it can write is already in key.
static func _muse_write(st: PackedFloat32Array, seed: int, gen: int, ln: int,
		nscale: int, oct_range: int, density: float, contour: int,
		amount: float) -> void:
	var span: int = maxi(1, nscale * oct_range)
	var nrewrite: int = ln if amount >= 0.999 else int(ceil(float(ln) * amount))
	for k in nrewrite:
		# which note gets rewritten: for a partial rewrite, a position
		# picked by the same hash, so the drift is repeatable too
		var i: int = k if amount >= 0.999 else \
			int(_hash01(seed * 7919 + gen * 613 + k * 97) * float(ln)) % maxi(1, ln)
		var r1: float = _hash01(seed * 31 + gen * 1069 + i * 17)
		var r2: float = _hash01(seed * 131 + gen * 5171 + i * 251)
		var pos: float = float(i) / float(maxi(1, ln - 1))
		var shape := 0.0
		match contour:
			1: shape = pos                                   # RISING
			2: shape = 1.0 - pos                             # FALLING
			3: shape = 1.0 - absf(pos - 0.5) * 2.0           # ARCH
			4: shape = 0.0 if r1 < 0.5 else 1.0              # LEAP: low or high, nothing between
			_: shape = 0.5                                   # WANDER
		var wander: float = (r1 - 0.5) * (0.9 if contour == 0 else 0.45)
		var deg: int = clampi(int(round((shape + wander) * float(span - 1))), 0, span - 1)
		# the tonic on the first beat: a phrase needs somewhere to be home
		if i == 0 and r2 < 0.6:
			deg = 0
		st[i] = float(deg)
		var gate: float = 0.0
		if r2 < density:
			gate = 2.0 if r2 < density * 0.25 else 1.0       # 2 = accented
		st[16 + i] = gate

func _scale(i: int) -> PackedInt32Array:
	match i:
		1: return PackedInt32Array([0, 2, 4, 5, 7, 9, 11])
		2: return PackedInt32Array([0, 2, 3, 5, 7, 8, 10])
		3: return PackedInt32Array([0, 3, 5, 7, 10])
		4: return PackedInt32Array([0, 3, 5, 6, 7, 10])
		5: return PackedInt32Array([0, 2, 3, 5, 7, 9, 10])
		6: return PackedInt32Array([0, 2, 3, 5, 7, 8, 11])
		7: return PackedInt32Array([0, 2, 4, 6, 8, 10])
	return PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])

# ============================================================ persistence

func to_dict() -> Dictionary:
	var ms: Array = []
	_mx.lock()
	for m in mods:
		ms.append({"id": m.id, "b": m.brand, "r": m.row, "x": m.hp,
			"p": Array(m.p), "s": Array(m.sw), "t": Array(m.st),
			"n": m.name_tag, "a": m.art,
			# the RUNNING state too: a clock's phase, a sequencer's step,
			# a flip-flop's flip. Without this every clock in the rack
			# restarted at zero on rejoin and patches that depended on
			# two clocks being OUT of phase came back locked together.
			"z": Array(m.s)})
	var cs: Array = []
	for c in cables:
		# jacks are saved BY NAME as well as by index: panels get
		# rearranged as modules grow, and a patch must survive that
		var sn := ""
		var dn := ""
		var smi := int(c["sm"])
		var dmi := int(c["dm"])
		if smi < mods.size():
			var so_l: Array = SynthMods.def(mods[smi].id)["outs"]
			if int(c["so"]) < so_l.size():
				sn = str(so_l[int(c["so"])])
		if dmi < mods.size():
			var di_l: Array = SynthMods.def(mods[dmi].id)["ins"]
			if int(c["di"]) < di_l.size():
				dn = str(di_l[int(c["di"])])
		cs.append([smi, int(c["so"]), dmi, int(c["di"]), int(c["col"]), sn, dn])
	_mx.unlock()
	return {"mods": ms, "cables": cs, "v": PATCH_VERSION}

func from_dict(d: Dictionary) -> void:
	_mx.lock()
	mods.clear()
	cables.clear()
	var ver := int(d.get("v", 1))
	for e in d.get("mods", []):
		var id := str(e.get("id", ""))
		if not SynthMods.has(id):
			continue
		var m := make_mod(id, str(e.get("b", "dude")))
		m.row = clampi(int(e.get("r", 0)), 0, rows - 1)
		m.hp = clampi(int(e.get("x", 0)), 0, row_hp)
		var pa: Array = e.get("p", [])
		var kmap: Array = LEGACY_KNOB.get(id, []) if ver < 2 else []
		for i in pa.size():
			var ki: int = int(kmap[i]) if i < kmap.size() else i
			if ki >= 0 and ki < m.p.size():
				m.p[ki] = clampf(float(pa[i]), 0.0, 1.0)
		var sa: Array = e.get("s", [])
		for i in mini(sa.size(), m.sw.size()):
			m.sw[i] = int(sa[i])
		var ta: Array = e.get("t", [])
		for i in mini(ta.size(), m.st.size()):
			m.st[i] = float(ta[i])
		m.name_tag = str(e.get("n", ""))
		m.art = int(e.get("a", m.art))
		var ra: Array = e.get("z", [])
		for i in mini(ra.size(), m.s.size()):
			m.s[i] = float(ra[i])
		mods.append(m)
	# Is this REALLY an old patch? An unstamped file that already uses
	# the new jack numbering is a patch from the gap between the rework
	# and the version stamp -- remapping it would break it.
	if ver < 2:
		for c0 in d.get("cables", []):
			var cc: Array = c0
			if cc.size() > 6 and str(cc[6]) != "":
				ver = 3          # it has jack names: not legacy at all
				break
			if cc.size() >= 4:
				var dmi := int(cc[2])
				if dmi >= 0 and dmi < mods.size():
					var oc := int(LEGACY_IN_COUNT.get(mods[dmi].id, 99))
					if int(cc[3]) >= oc:
						ver = 2  # uses a jack the old panel never had
						break
	for c in d.get("cables", []):
		var ca: Array = c
		if ca.size() < 4:
			continue
		var sm := int(ca[0])
		var dm := int(ca[2])
		if sm < 0 or sm >= mods.size() or dm < 0 or dm >= mods.size():
			continue
		var so := int(ca[1])
		var di := int(ca[3])
		# 1. names win: the jack called "IN" is the jack called "IN",
		# wherever it has been moved to on the panel
		if ca.size() > 6:
			# an EMPTY name matches every unlabelled jack, which silently
			# collapsed whole patches onto jack 0. A blank name means
			# "trust the index", not "find the first blank".
			var outs_l: Array = SynthMods.def(mods[sm].id)["outs"]
			var ins_l: Array = SynthMods.def(mods[dm].id)["ins"]
			if str(ca[5]) != "":
				var fo := outs_l.find(str(ca[5]))
				if fo >= 0:
					so = fo
			if str(ca[6]) != "":
				var fi := ins_l.find(str(ca[6]))
				if fi >= 0:
					di = fi
		elif ver < 2:
			# 2. a patch from before the rework: replay the jack shuffle
			var mapd: Array = LEGACY_IN.get(mods[dm].id, [])
			if di < mapd.size():
				di = int(mapd[di])
		var nin: int = (SynthMods.def(mods[dm].id)["ins"] as Array).size()
		var nout: int = (SynthMods.def(mods[sm].id)["outs"] as Array).size()
		if so < 0 or so >= nout or di < 0 or di >= nin:
			continue
		cables.append({"sm": sm, "so": so, "dm": dm, "di": di,
			"col": int(ca[4]) if ca.size() > 4 else 0})
	_compile()
	_mx.unlock()

## The rack it ships with: a voice, WIRED -- oscillator into filter into
## amplifier into the speakers, with the envelope already sitting on the
## amp's CV. Not a finished patch: nothing is gating the envelope yet,
## and that first cable is yours to run.
func default_patch() -> void:
	_mx.lock()
	mods.clear()
	cables.clear()
	# lay them out left to right from their REAL widths, so changing a
	# panel's HP can never make the shipped rack overlap itself
	var x := 0
	for id in ["vco", "vcf", "adsr", "vca", "out"]:
		var m := make_mod(id, "dude")
		m.row = 0
		m.hp = x
		x += m.width()
		mods.append(m)
	var link := func(a2: int, ao: int, b2: int, bi: int) -> void:
		cables.append({"sm": a2, "so": ao, "dm": b2, "di": bi,
			"col": cables.size() % CABLE_COLS.size()})
	link.call(0, 0, 1, 3)      # VCO saw   -> VCF audio in
	link.call(1, 0, 3, 1)      # VCF lp    -> VCA audio in
	link.call(2, 0, 3, 0)      # ADSR env  -> VCA cv (under the GAIN knob)
	link.call(3, 0, 4, 0)      # VCA out   -> AUDIO OUT L/MONO
	mods[1].p[0] = 0.62        # filter open enough to hear
	mods[3].p[0] = 0.28        # a little standing gain, so it drones
	_compile()
	_mx.unlock()

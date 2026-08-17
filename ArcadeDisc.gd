class_name ArcadeDisc
extends RefCounted
## FLOPPIES. One format, four kinds of contents, and a rule about which
## way things convert.
##
##   cart   -- a whole cartridge: code, art, map, song
##   script -- loose Lua. The computers write these; the arcade reads
##             them straight into the code editor, and the other way
##             round, because both machines run the same Lua now
##   patch  -- a modular synth patch. Loads back into any modular synth,
##             OR into an arcade cabinet, where it is rendered down into
##             a playable instrument
##   song   -- a chiptune. Loads into any other cabinet's tracker
##
## A patch can become an instrument. A song cannot become a patch: the
## song is the notes, the patch is the machine that made the sound, and
## you cannot get the machine back out of the notes.

const KINDS := ["cart", "script", "patch", "song"]

## Blank shells come out of the cutter in whatever colour the machine
## had loaded, which is to say: whatever it felt like. The colour sticks
## to that disc for the rest of its life -- cut it blue, write a game to
## it, and it is the blue one on the shelf forever.
const SHELL_COLORS := [
	"#2f3440", "#e43b44", "#f77622", "#feae34", "#b6d53c", "#1ebc73",
	"#0b8a8f", "#26c2cd", "#4fa4ff", "#285cc4", "#5a3fd6", "#8b5ce8",
	"#b04ad6", "#e14bd6", "#ff89c9", "#c98f6a", "#e4c9a0", "#97a3b6",
]

static func random_shell() -> int:
	return randi() % SHELL_COLORS.size()

static func shell_color(i: int) -> Color:
	return Color(str(SHELL_COLORS[clampi(i, 0, SHELL_COLORS.size() - 1)]))

## The colour to draw an item in. A blank shows the next shell you would
## write to; a written disc shows the most recent one you wrote.
static func item_color(id: String) -> Color:
	if id == "floppy":
		if Inventory.floppy_blanks.size() > 0:
			return shell_color(int(Inventory.floppy_blanks[
				Inventory.floppy_blanks.size() - 1]))
		return shell_color(0)
	if Inventory.floppy_data.size() > 0:
		var d: Dictionary = Inventory.floppy_data[Inventory.floppy_data.size() - 1]
		return shell_color(int(d.get("shell", 8)))
	return shell_color(8)

static func make(kind: String, name: String, payload: Dictionary) -> Dictionary:
	var d := payload.duplicate(true)
	d["kind"] = kind
	d["name"] = name
	return d

static func kind_of(disc: Dictionary) -> String:
	return str(disc.get("kind", "?"))

static func label(disc: Dictionary) -> String:
	return "[%s] %s" % [kind_of(disc).to_upper(), str(disc.get("name", "untitled"))]

## The palette index closest to this disc's shell, for the pixel UIs.
static func shell_pixel(disc: Dictionary) -> int:
	var want := shell_color(int(disc.get("shell", 8)))
	var cols := Pixel.colors()
	var best := 1
	var bd := 999.0
	for i in cols.size():
		var c: Color = cols[i]
		var dd := absf(c.r - want.r) + absf(c.g - want.g) + absf(c.b - want.b)
		if dd < bd:
			bd = dd
			best = i
	return best

## What can read this disc, in words, for the machine that is holding it.
static func describe(disc: Dictionary) -> String:
	match kind_of(disc):
		"cart": return "a whole cartridge -- plays and edits in any cabinet"
		"script": return "loose Lua -- runs on a computer, or drops into cart code"
		"patch": return "a synth patch -- loads into a modular synth, or becomes an arcade instrument"
		"song": return "a chiptune -- loads into any cabinet's tracker"
	return "unreadable"

static func can_read(disc: Dictionary, machine_kind: String) -> bool:
	var k := kind_of(disc)
	match machine_kind:
		"arcade": return k in ["cart", "script", "patch", "song"]
		"modsynth": return k == "patch"
		"computer": return k == "script"
	return false

# --------------------------------------------------- patch -> instrument

## Play one note through a modular synth patch offline and keep the
## audio. That rendered note IS the arcade instrument: the cabinet has
## no room for a whole modular rack, but it can hold what one sounded
## like and play it back at any pitch.
static func render_patch(disc: Dictionary, semi: float = 48.0,
		secs: float = 0.8) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var pd = disc.get("patch", null)
	if not (pd is Dictionary):
		return out
	var eng := SynthEngine.new()
	eng.from_dict(pd as Dictionary)
	if eng.mods.is_empty():
		return out
	eng.running = true
	var pressed := false
	for i in eng.mods.size():
		var m = eng.mods[i]
		if str(m.id) == "keys" or str(m.id) == "vkeys":
			eng.key_press(i, semi, true, 0.9)
			pressed = true
	var want := int(SynthEngine.SR * secs)
	var guard := 0
	while out.size() < want and guard < 4000:
		guard += 1
		eng._block()
		for v in eng._mix:
			out.append(clampf((v.x + v.y) * 0.5, -1.0, 1.0))
	if pressed:
		for i in eng.mods.size():
			var m2 = eng.mods[i]
			if str(m2.id) == "keys" or str(m2.id) == "vkeys":
				eng.key_press(i, semi, false)
	eng.running = false
	# trim the silence off the front so the instrument starts when it
	# is struck and not a tenth of a second later
	var start := 0
	while start < out.size() and absf(out[start]) < 0.004:
		start += 1
	if start > 0 and start < out.size() - 16:
		out = out.slice(start)
	return out

## Turn a rendered patch into a tracker instrument.
static func patch_to_inst(disc: Dictionary, semi: float = 48.0) -> ChipSound.Inst:
	var i := ChipSound.Inst.new()
	i.name = str(disc.get("name", "PATCH")).substr(0, 12).to_upper()
	i.wave = ChipSound.W_SAMPLE
	i.sample = render_patch(disc, semi)
	i.sample_base = semi
	i.sample_loop = true
	i.atk = 0.002
	i.dec = 0.4
	i.sus = 0.85
	i.rel = 0.18
	i.cut = 1.0
	i.vol = 0.85
	return i

# ------------------------------------------------------------- the bag

## Every written floppy the player is carrying.
static func carried() -> Array:
	return Inventory.floppy_data

static func take(index: int) -> Dictionary:
	if index < 0 or index >= Inventory.floppy_data.size():
		return {}
	var d: Dictionary = Inventory.floppy_data[index]
	return d.duplicate(true)

## Write a payload onto a blank the player is carrying. Returns false if
## there is nothing to write it to.
static func write(disc: Dictionary) -> bool:
	if Inventory.res_count("floppy") <= 0:
		return false
	Inventory.remove_res("floppy", 1)
	var d := disc.duplicate(true)
	# the shell the blank was cut in goes with it
	if Inventory.floppy_blanks.size() > 0:
		d["shell"] = int(Inventory.floppy_blanks.pop_back())
	elif not d.has("shell"):
		d["shell"] = random_shell()
	Inventory.floppy_data.append(d)
	Inventory.give("floppy_data", 1)
	return true

static func erase(index: int) -> void:
	if index < 0 or index >= Inventory.floppy_data.size():
		return
	var d: Dictionary = Inventory.floppy_data[index]
	Inventory.floppy_blanks.append(int(d.get("shell", 0)))
	Inventory.floppy_data.remove_at(index)
	Inventory.remove_res("floppy_data", 1)
	Inventory.give("floppy", 1)

## Cut a fresh blank in a colour of the machine's choosing.
static func cut_blank() -> int:
	var c := random_shell()
	Inventory.floppy_blanks.append(c)
	Inventory.give("floppy", 1)
	return c

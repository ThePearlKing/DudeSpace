class_name SynthMods
extends RefCounted
## THE MODULE CATALOG. One description of every module in the rack --
## its jacks, its knobs, its switches, its faceplate -- shared by the
## three things that have to agree about a modular synth: the DSP
## (SynthEngine), the patch editor (SynthUI) and the physical panel
## bolted into the case (ModSynth's 3D rack). Every jack you see in the
## editor is at the same place on the real panel, and the cable you
## patch is the cable that hangs off the front of the machine.
##
## Panel coordinates are eurorack units: 1 HP = HPW wide, a 3U panel is
## PANEL_H tall, origin top-left of the faceplate.

const HPW := 5.2         # panel units per HP -- real eurorack proportions:
const PANEL_H := 128.0   # a 3U panel is 128.5mm tall and 5.08mm per HP
const ROWS := 3          # rows in the case
const ROW_HP := 84       # HP per row, the classic case width

# --------------------------------------------------------------- brands
# Three houses build eurorack in this universe. They sound slightly
# different because they ARE built differently -- see SynthEngine's
# brand trims (drift, saturation, tuning).

const BRANDS: Array[String] = ["dude", "icos", "mono"]

const BRAND_STYLE := {
	"dude": {
		"name": "DUDE AUDIO",
		"blurb": "Human-built. Clean, honest, slightly grey. Calibrated on a good day.",
		"bg": Color("#2b3340"), "bg2": Color("#3f5f96"),   # panel gradient
		"trim": Color("#8ea6c8"), "text": Color("#e6f0ff"),
		"knob": Color("#20252e"), "cap": Color("#cfd8e6"), "pointer": Color("#7be8ff"),
		"jack": Color("#12151a"), "ring": Color("#9aa8bc"),
		"led": Color("#7be8ff"),
		"motif": "grad",
	},
	"icos": {
		"name": "ICOSA INSTRUMENTS",
		"blurb": "Twenty faces, twenty opinions. Runs hot, drifts on purpose.",
		"bg": Color("#141a2e"), "bg2": Color("#2a1c4a"),
		"trim": Color("#33ff99"), "text": Color("#ffffff"),
		"knob": Color("#0e1220"), "cap": Color("#ffcf40"), "pointer": Color("#141a2e"),
		"jack": Color("#0a0d16"), "ring": Color("#b388ff"),
		"led": Color("#33ff99"),
		"motif": "icosa",
	},
	"mono": {
		"name": "MONOLITHIC",
		"blurb": "Older than the dudes. Nobody carved these either. It watches the patch.",
		"bg": Color("#2a2a2e"), "bg2": Color("#17171a"),
		"trim": Color("#6b6154"), "text": Color("#d8d2c8"),
		"knob": Color("#101012"), "cap": Color("#8a7f70"), "pointer": Color("#c8342a"),
		"jack": Color("#0c0c0e"), "ring": Color("#5a544c"),
		"led": Color("#ff3a2a"),
		"motif": "eye",
	},
}

## The icosa house colours are the colony's own HUES -- same four.
const ICOS_HUES: Array[Color] = [Color("#33ff99"), Color("#ffcf40"),
	Color("#b388ff"), Color("#ff6a6a")]

static func brand_style(b: String) -> Dictionary:
	return BRAND_STYLE.get(b, BRAND_STYLE["dude"])

static func brand_name(b: String) -> String:
	return str(brand_style(b)["name"])

# -------------------------------------------------------------- catalog

static var _cat: Dictionary = {}
static var _ids: Array[String] = []

static func _k(n: String, lo: float, hi: float, d: float, cur: String = "lin") -> Dictionary:
	return {"n": n, "min": lo, "max": hi, "def": d, "cur": cur}

static func _build() -> void:
	if not _cat.is_empty():
		return
	var c := {}

	# ---------------------------------------------------------- sources
	c["vco"] = {"name": "VCO", "grp": "SOURCE", "hp": 15, "col": Color("#ff9a3c"),
		"desc": "Voltage controlled oscillator. 1V/oct, through-zero FM, PWM, hard sync. Band-limited.",
		"ins": ["V/OCT", "FINE CV", "FM", "PWM", "SYNC"], "under": 4,
		"outs": ["SAW", "PULSE", "TRI", "SINE", "SUB"],
		"knobs": [_k("OCT", -4.0, 4.0, 0.0), _k("FINE", -1.0, 1.0, 0.0),
			_k("FM", 0.0, 1.0, 0.0), _k("PW", 0.02, 0.98, 0.5)],
		"sw": [{"n": "RANGE", "opts": ["LFO", "VCO", "HI"], "def": 1}],
		"widget": ""}
	c["lfo"] = {"name": "LFO", "grp": "SOURCE", "hp": 12, "col": Color("#ffd166"),
		"desc": "Low frequency oscillator, four shapes at once. RANGE gears the whole RATE knob down -- NORMAL is 0.02 to 60 Hz, SLOW divides it by forty, GLACIAL by a thousand (one cycle every fourteen hours at the bottom). DEPTH does the same for the output: /10 or /100, so you can dial in a few cents of wobble instead of whole octaves. Right-click any knob to type an exact value.",
		"ins": ["RATE", "AMP CV", "OFS CV", "RESET"], "under": 3,
		"outs": ["TRI", "SQR", "SAW", "SINE"],
		"knobs": [_k("RATE", 0.02, 60.0, 2.0, "exp"), _k("AMP", 0.0, 5.0, 5.0),
			_k("OFFSET", -5.0, 5.0, 0.0)],
		"sw": [{"n": "DEPTH", "opts": ["FULL", "FINE /10", "MICRO /100"], "def": 0},
			{"n": "RANGE", "opts": ["NORMAL", "SLOW /40", "GLACIAL /1000"], "def": 0}],
		"widget": ""}
	c["noise"] = {"name": "NOISE", "grp": "SOURCE", "hp": 6, "col": Color("#b0b6c2"),
		"desc": "White and pink noise, plus a slow random voltage.",
		"ins": [], "outs": ["WHITE", "PINK", "RND"],
		"knobs": [_k("LEVEL", 0.0, 5.0, 5.0), _k("RND RATE", 0.1, 40.0, 6.0, "exp")],
		"sw": [], "widget": ""}
	c["drum"] = {"name": "DRUM VOICE", "grp": "SOURCE", "hp": 15, "col": Color("#ff6a6a"),
		"desc": "One-shot percussion voice. Kick, snare, hat, clap or tom -- trigger it from a sequencer.",
		"ins": ["TUNE", "DECAY CV", "TONE CV", "LEVEL CV", "TRIG", "ACCENT"],
		"under": 4, "outs": ["OUT"],
		"knobs": [_k("TUNE", 20.0, 400.0, 55.0, "exp"), _k("DECAY", 0.03, 2.0, 0.35, "exp"),
			_k("TONE", 0.0, 1.0, 0.5), _k("LEVEL", 0.0, 1.0, 0.8)],
		"sw": [{"n": "KIND", "opts": ["KICK", "SNARE", "HAT", "CLAP", "TOM"], "def": 0}],
		"widget": ""}
	c["keys"] = {"name": "KEYBOARD", "grp": "SOURCE", "hp": 14, "col": Color("#e6f0ff"),
		"desc": "Two octaves of click-and-hold keys. Pitch CV and a gate, straight off the panel.",
		"ins": [], "outs": ["CV", "GATE"],
		"knobs": [_k("OCT", -3.0, 3.0, 0.0), _k("GLIDE", 0.0, 1.0, 0.0)],
		"sw": [], "widget": "keys"}

	# -------------------------------------------------------- processors
	c["vcf"] = {"name": "VCF", "grp": "FILTER", "hp": 15, "col": Color("#7be8ff"),
		"desc": "State-variable filter, 12 or 24 dB/oct, self-oscillating resonance. Every knob has its own CV jack under it, and all four outputs are live at once.",
		"ins": ["CUTOFF", "RES CV", "DRIVE CV", "IN"], "under": 3,
		"outs": ["LP", "BP", "HP", "NOTCH"],
		"knobs": [_k("CUTOFF", 20.0, 11000.0, 1200.0, "exp"), _k("RES", 0.0, 1.0, 0.2),
			_k("DRIVE", 1.0, 6.0, 1.0)],
		"sw": [{"n": "SLOPE", "opts": ["12 dB", "24 dB"], "def": 0}],
		"widget": ""}
	c["vca"] = {"name": "VCA", "grp": "PROCESS", "hp": 8, "col": Color("#7dff9a"),
		"desc": "Voltage controlled amplifier. Linear for audio, exponential for feel.",
		"ins": ["CV", "IN"], "under": 1, "outs": ["OUT"],
		"knobs": [_k("GAIN", 0.0, 1.0, 0.0), _k("CV AMT", 0.0, 1.0, 1.0)],
		"sw": [{"n": "RESP", "opts": ["LIN", "EXP"], "def": 0}], "widget": ""}
	c["mix4"] = {"name": "MIXER", "grp": "PROCESS", "hp": 10, "col": Color("#c8ccd4"),
		"desc": "Four channels in, one out, plus an inverted copy. Works on audio and CV alike.",
		"ins": ["IN 1", "IN 2", "IN 3", "IN 4"], "outs": ["MIX", "INV"],
		"knobs": [_k("LVL 1", 0.0, 1.0, 0.65), _k("LVL 2", 0.0, 1.0, 0.65),
			_k("LVL 3", 0.0, 1.0, 0.65), _k("LVL 4", 0.0, 1.0, 0.65),
			_k("MASTER", 0.0, 1.5, 1.0)],
		"sw": [], "widget": ""}
	c["atten"] = {"name": "ATTENUVERTER", "grp": "UTILITY", "hp": 8, "col": Color("#9aa8bc"),
		"desc": "Two channels of scale-and-offset, each buffered out twice. The most useful module in any rack.",
		"ins": ["IN A", "IN B"], "outs": ["A 1", "A 2", "B 1", "B 2"],
		"knobs": [_k("ATT A", -1.0, 1.0, 1.0), _k("OFF A", -5.0, 5.0, 0.0),
			_k("ATT B", -1.0, 1.0, 1.0), _k("OFF B", -5.0, 5.0, 0.0)],
		"sw": [], "widget": ""}
	c["const"] = {"name": "CONSTANTS", "grp": "UTILITY", "hp": 8, "col": Color("#8a9098"),
		"desc": "Four fixed voltages. Tune something, bias something, hold a gate open forever.",
		"ins": [], "outs": ["V 1", "V 2", "V 3", "V 4"],
		"knobs": [_k("V 1", -5.0, 5.0, 1.0), _k("V 2", -5.0, 5.0, 0.0),
			_k("V 3", -5.0, 5.0, 0.0), _k("V 4", -5.0, 5.0, 5.0)],
		"sw": [], "widget": ""}
	c["adsr"] = {"name": "ADSR", "grp": "MODULATE", "hp": 15, "col": Color("#ffb84d"),
		"desc": "Attack, decay, sustain, release -- each with its own CV jack under the knob. ENV is the output you patch into a VCA's CV.",
		"ins": ["A CV", "D CV", "S CV", "R CV", "GATE", "RETRIG"],
		"under": 4,
		"outs": ["ENV", "INV", "EOC"],
		"knobs": [_k("ATTACK", 0.001, 8.0, 0.01, "exp"), _k("DECAY", 0.002, 8.0, 0.25, "exp"),
			_k("SUSTAIN", 0.0, 1.0, 0.6), _k("RELEASE", 0.002, 10.0, 0.4, "exp")],
		"sw": [{"n": "CURVE", "opts": ["EXP", "LIN"], "def": 0}], "widget": ""}
	c["slew"] = {"name": "SLEW", "grp": "MODULATE", "hp": 6, "col": Color("#ffa040"),
		"desc": "Slew limiter and portamento. Separate rise and fall, with a gate while it's moving.",
		"ins": ["IN"], "outs": ["OUT", "MOVING"],
		"knobs": [_k("RISE", 0.0, 5.0, 0.1, "exp"), _k("FALL", 0.0, 5.0, 0.1, "exp")],
		"sw": [], "widget": ""}
	c["sh"] = {"name": "SAMPLE & HOLD", "grp": "MODULATE", "hp": 8, "col": Color("#b388ff"),
		"desc": "Grabs the input on every trigger and holds it. Unpatched, it samples its own noise.",
		"ins": ["IN", "TRIG"], "outs": ["OUT", "INV"],
		"knobs": [_k("SLEW", 0.0, 1.0, 0.0), _k("RANGE", 0.0, 1.0, 1.0)],
		"sw": [], "widget": ""}
	c["quant"] = {"name": "QUANTIZER", "grp": "UTILITY", "hp": 10, "col": Color("#7df9ff"),
		"desc": "Snaps any voltage onto a scale. Fires a trigger whenever the note actually changes.",
		"ins": ["IN", "TRIG"], "outs": ["CV", "TRIG"],
		"knobs": [_k("ROOT", 0.0, 11.0, 0.0), _k("TRANSPOSE", -3.0, 3.0, 0.0)],
		"sw": [{"n": "SCALE", "opts": ["CHROM", "MAJOR", "MINOR", "PENTA",
			"BLUES", "DORIAN", "HARM MIN", "WHOLE"], "def": 3}], "widget": ""}
	c["ring"] = {"name": "RING MOD", "grp": "PROCESS", "hp": 6, "col": Color("#ff7ce9"),
		"desc": "Four-quadrant multiplier. Two signals go in, their sum and difference come out.",
		"ins": ["X", "Y"], "outs": ["X·Y"],
		"knobs": [_k("DEPTH", 0.0, 1.0, 1.0), _k("X BIAS", -5.0, 5.0, 0.0)],
		"sw": [], "widget": ""}
	c["fold"] = {"name": "WAVEFOLDER", "grp": "PROCESS", "hp": 8, "col": Color("#ff6ac1"),
		"desc": "Folds the peaks back on themselves. A sine goes in, a swarm comes out.",
		"ins": ["IN", "FOLD CV"], "outs": ["OUT"],
		"knobs": [_k("FOLD", 1.0, 9.0, 1.5), _k("SYM", -1.0, 1.0, 0.0), _k("CV AMT", 0.0, 1.0, 0.5)],
		"sw": [], "widget": ""}
	c["drive"] = {"name": "OVERDRIVE", "grp": "PROCESS", "hp": 6, "col": Color("#ff5964"),
		"desc": "Soft-clipping drive with a tone tilt. For when clean was not the assignment.",
		"ins": ["IN", "CV"], "outs": ["OUT"],
		"knobs": [_k("DRIVE", 1.0, 40.0, 4.0, "exp"), _k("TONE", 0.0, 1.0, 0.5),
			_k("LEVEL", 0.0, 1.0, 0.7)],
		"sw": [], "widget": ""}

	# ------------------------------------------------------------ clocks
	c["clock"] = {"name": "CLOCK", "grp": "CLOCK", "hp": 10, "col": Color("#3aff6a"),
		"desc": "Master clock in 16ths, with divisions and a bar reset. PHASE slides this clock's pulses against every other clock in the rack -- two clocks at the same tempo, one turned a quarter round, stay offset forever without a delay module.",
		"ins": ["RUN", "EXT CLK", "RESET"], "outs": ["CLK", "/2", "/4", "/8", "RESET"],
		"knobs": [_k("BPM", 20.0, 300.0, 120.0), _k("SWING", 0.0, 0.7, 0.0),
			_k("WIDTH", 0.05, 0.9, 0.5), _k("PHASE", 0.0, 1.0, 0.0)],
		"sw": [{"n": "RUN", "opts": ["STOP", "RUN"], "def": 1}], "widget": ""}
	c["cdiv"] = {"name": "DIVIDER", "grp": "CLOCK", "hp": 8, "col": Color("#2bff5a"),
		"desc": "Counts incoming pulses and taps off every second, third, fourth, eighth and sixteenth.",
		"ins": ["CLK", "RESET"], "outs": ["/2", "/3", "/4", "/8", "/16"],
		"knobs": [], "sw": [], "widget": ""}
	c["logic"] = {"name": "LOGIC", "grp": "LOGIC", "hp": 6, "col": Color("#5aff3a"),
		"desc": "Boolean gate maths: AND, OR, XOR, NOT and a T flip-flop that halves any clock.",
		"ins": ["A", "B", "C"], "outs": ["AND", "OR", "XOR", "NOT A", "FLIP"],
		"knobs": [_k("THRESH", 0.2, 4.0, 1.0)], "sw": [], "widget": ""}
	c["comp"] = {"name": "COMPARATOR", "grp": "LOGIC", "hp": 8, "col": Color("#8aff3a"),
		"desc": "Turns any voltage into gates: above threshold, below it, or inside a window.",
		"ins": ["IN", "CV"], "outs": ["GT", "LT", "WINDOW", "TRIG"],
		"knobs": [_k("THRESH", -5.0, 5.0, 0.0), _k("WINDOW", 0.0, 5.0, 1.0)],
		"sw": [], "widget": ""}

	# ------------------------------------------------------- sequencers
	c["seq8"] = {"name": "SEQUENCER 8", "grp": "SEQUENCE", "hp": 20, "col": Color("#ffd166"),
		"desc": "Eight steps of pitch with a gate switch each. Forward, reverse, pendulum or random.",
		"ins": ["CLK", "RESET", "HOLD"], "outs": ["CV", "GATE", "EOC"],
		"knobs": [_k("LENGTH", 1.0, 8.0, 8.0), _k("GLIDE", 0.0, 1.0, 0.0),
			_k("RANGE", 0.5, 4.0, 2.0)],
		"sw": [{"n": "DIR", "opts": ["FWD", "REV", "PEND", "RANDOM"], "def": 0}],
		"widget": "seq8"}
	c["dseq"] = {"name": "TRIGGER SEQ", "grp": "SEQUENCE", "hp": 22, "col": Color("#ff9a3c"),
		"desc": "Four lanes, sixteen steps. The drum machine half of the rack.",
		"ins": ["CLK", "RESET"], "outs": ["T 1", "T 2", "T 3", "T 4"],
		"knobs": [_k("LENGTH", 1.0, 16.0, 16.0)], "sw": [], "widget": "dseq"}
	c["euclid"] = {"name": "EUCLIDEAN", "grp": "SEQUENCE", "hp": 10, "col": Color("#ffcf40"),
		"desc": "Spreads N hits as evenly as possible across M steps. Rotate it for a different feel.",
		"ins": ["CLK", "RESET"], "outs": ["TRIG", "INV", "EOC"],
		"knobs": [_k("STEPS", 1.0, 32.0, 16.0), _k("FILL", 0.0, 32.0, 5.0),
			_k("ROTATE", 0.0, 31.0, 0.0)],
		"sw": [], "widget": "euclid"}
	c["turing"] = {"name": "TURING MACHINE", "grp": "SEQUENCE", "hp": 12, "col": Color("#b388ff"),
		"desc": "A looping shift register of random bits. Lock it for a riff, open it for chaos.",
		"ins": ["CLK", "WRITE"], "outs": ["CV", "PULSE", "INV"],
		"knobs": [_k("LOOP", 0.0, 1.0, 1.0), _k("LENGTH", 2.0, 16.0, 8.0),
			_k("RANGE", 0.0, 4.0, 2.0), _k("OFFSET", -2.0, 2.0, 0.0)],
		"sw": [], "widget": "turing"}

	# ------------------------------------------------------------ f/x
	c["phaser"] = {"name": "PHASER", "grp": "FX", "hp": 10, "col": Color("#9a6bff"),
		"desc": "Six all-pass stages swept by their own LFO. Feedback for the jet.",
		"ins": ["IN", "RATE CV"], "outs": ["OUT"],
		"knobs": [_k("RATE", 0.02, 8.0, 0.4, "exp"), _k("DEPTH", 0.0, 1.0, 0.8),
			_k("FEEDBACK", 0.0, 0.9, 0.4), _k("MIX", 0.0, 1.0, 0.5),
			_k("CENTER", 100.0, 4000.0, 700.0, "exp")],
		"sw": [], "widget": ""}
	c["reverb"] = {"name": "REVERB", "grp": "FX", "hp": 15, "col": Color("#7be8ff"),
		"desc": "Comb-and-allpass tank in stereo. Room, hall, or the inside of a moon.",
		"ins": ["SIZE CV", "DAMP CV", "MIX CV", "IN"], "under": 3,
		"outs": ["L", "R"],
		"knobs": [_k("SIZE", 0.0, 1.0, 0.6), _k("DAMP", 0.0, 1.0, 0.4),
			_k("MIX", 0.0, 1.0, 0.35), _k("WIDTH", 0.0, 1.0, 0.8)],
		"sw": [], "widget": ""}
	c["delay"] = {"name": "DELAY", "grp": "FX", "hp": 15, "col": Color("#5ad0ff"),
		"desc": "Two seconds of echo with voltage control over time. Push feedback for runaway.",
		"ins": ["TIME", "FB CV", "MIX CV", "IN"], "under": 3,
		"outs": ["OUT", "WET"],
		"knobs": [_k("TIME", 0.01, 2.0, 0.32, "exp"), _k("FEEDBACK", 0.0, 0.95, 0.4),
			_k("MIX", 0.0, 1.0, 0.4)],
		"sw": [], "widget": ""}

	# ------------------------------------------------------------ INPUT
	# Modules you PLAY, and modules that listen to the world the case is
	# standing in. Nothing upstream of these -- they are where signal
	# enters the rack.
	c["vkeys"] = {"name": "DUDE KEYS", "grp": "INPUT", "hp": 8, "col": Color("#e6f0ff"),
		"only": "dude",
		"desc": "DUDE AUDIO EXCLUSIVE. A real keyboard stood on its end so it fits in a rack: two octaves, black keys down the left. An octave knob sits across the top with its own CV port beside it, and CV and GATE come out the bottom. Hold and drag across the keys to run your hand up them.",
		"ins": ["OCT CV"], "topin": 1, "outs": ["CV", "GATE"],
		"knobs": [_k("OCT", -3.0, 3.0, 0.0)], "toprow": true,
		"sw": [], "widget": "vkeys"}
	c["button"] = {"name": "BUTTONS", "grp": "INPUT", "hp": 8, "col": Color("#ff6a6a"),
		"desc": "Two panel buttons. Each gives a gate while you hold it, a latch that stays where you left it, and a trigger on the press.",
		"ins": [], "outs": ["GATE A", "LATCH A", "GATE B", "LATCH B"],
		"knobs": [_k("LEVEL", 0.0, 10.0, 5.0)], "sw": [], "widget": "buttons"}
	c["xy"] = {"name": "XY PAD", "grp": "INPUT", "hp": 14, "col": Color("#ff7ce9"),
		"desc": "Drag the puck. X and Y come out as voltages, and a gate runs while you are touching it. Let go and it holds where you left it.",
		"ins": [], "outs": ["X", "Y", "GATE"],
		"knobs": [_k("X RANGE", 0.0, 5.0, 5.0), _k("Y RANGE", 0.0, 5.0, 5.0),
			_k("SLEW", 0.0, 1.0, 0.05)],
		"sw": [{"n": "RETURN", "opts": ["HOLD", "SPRING"], "def": 0}], "widget": "xy"}
	c["cast"] = {"name": "BROADCAST", "grp": "UTILITY", "hp": 20, "col": Color("#7be8ff"),
		"desc": "Puts the whole rack on the radio, relayed through the NEXUS STATION array. It needs no cable -- whatever reaches AUDIO OUT is what goes on air. Pick a frequency; if somebody already holds it the claim walks up the band and the panel tells you where you landed. A case standing INSIDE the Nexus array is heard at full strength system-wide; anywhere else it fades with distance. Click the name plate to rename the station.",
		"ins": [], "outs": [],
		"knobs": [_k("FREQ", 88.0, 108.0, 98.0), _k("GAIN", 0.0, 2.0, 1.0)],
		"sw": [{"n": "AIR", "opts": ["OFF AIR", "ON AIR"], "def": 1}],
		"widget": "cast"}
	c["world"] = {"name": "WORLD SENSOR", "grp": "INPUT", "hp": 10, "col": Color("#3aff6a"),
		"desc": "The rack listens to where it is standing: how close you are, the hour of the day, how full the case's own power buffer is, and how annoyed the sky god currently seems.",
		"ins": [], "outs": ["NEAR", "TIME", "POWER", "WRATH"],
		"knobs": [_k("GAIN", 0.0, 2.0, 1.0), _k("SMOOTH", 0.0, 1.0, 0.3)],
		"sw": [], "widget": ""}

	# ------------------------------------------------- HOUSE EXCLUSIVES
	# Panels only one manufacturer will sell you. They cannot be
	# rebranded -- nobody else knows how to build them.
	c["voice"] = {"name": "DUDE VOICE", "grp": "SOURCE", "hp": 14, "col": Color("#7be8ff"),
		"only": "dude",
		"desc": "DUDE AUDIO EXCLUSIVE. A whole voice on one panel: oscillator, filter and envelope, pre-wired inside. Gate it and it plays. For when you want a sound, not a project.",
		"ins": ["V/OCT", "GATE", "CUTOFF"], "outs": ["OUT"],
		"knobs": [_k("TUNE", -3.0, 3.0, 0.0), _k("CUTOFF", 60.0, 9000.0, 1400.0, "exp"),
			_k("RES", 0.0, 1.0, 0.25), _k("DECAY", 0.02, 4.0, 0.5, "exp"),
			_k("LEVEL", 0.0, 1.0, 0.7)],
		"sw": [{"n": "WAVE", "opts": ["SAW", "SQUARE", "TRI"], "def": 0}], "widget": ""}
	c["tape"] = {"name": "TAPE ECHO", "grp": "FX", "hp": 12, "col": Color("#c9a227"),
		"only": "dude",
		"desc": "DUDE AUDIO EXCLUSIVE. A loop of actual tape: wow, flutter, dulling repeats and a head that saturates when you push it.",
		"ins": ["IN", "TIME CV"], "outs": ["OUT", "WET"],
		"knobs": [_k("TIME", 0.03, 1.6, 0.28, "exp"), _k("REPEATS", 0.0, 0.98, 0.45),
			_k("MIX", 0.0, 1.0, 0.4), _k("WOW", 0.0, 1.0, 0.25),
			_k("DRIVE", 1.0, 8.0, 1.6, "exp")],
		"sw": [], "widget": ""}
	c["chaos"] = {"name": "ICOSA CHAOS", "grp": "MODULATE", "hp": 12, "col": Color("#b388ff"),
		"only": "icos",
		"desc": "ICOSA EXCLUSIVE. A strange attractor in a box. Three smooth voltages that never repeat, plus a stepped one that jumps on every clock.",
		"ins": ["RATE", "CLK"], "outs": ["X", "Y", "Z", "STEP"],
		"knobs": [_k("RATE", 0.05, 30.0, 3.0, "exp"), _k("SPREAD", 0.0, 5.0, 3.0),
			_k("CHAOS", 3.2, 4.0, 3.86), _k("OFFSET", -5.0, 5.0, 0.0)],
		"sw": [], "widget": "turing"}
	c["poly20"] = {"name": "POLYFACET 20", "grp": "SEQUENCE", "hp": 30, "col": Color("#33ff99"),
		"only": "icos",
		"desc": "ICOSA EXCLUSIVE. Twenty faces, twenty steps. Feed it a clock and it walks them; raise JUMP and it starts leaping across the solid instead.",
		"ins": ["CLK", "RESET", "JUMP"], "outs": ["CV", "GATE", "EOC"],
		"steps": 20,
		"knobs": [_k("LENGTH", 2.0, 20.0, 20.0), _k("JUMP", 0.0, 1.0, 0.0),
			_k("RANGE", 0.5, 4.0, 2.0), _k("GLIDE", 0.0, 1.0, 0.0)],
		"sw": [], "widget": "seqn"}
	c["stonetrig"] = {"name": "STONE COL", "grp": "SEQUENCE", "hp": 8,
		"col": Color("#c8342a"), "only": "mono",
		"desc": "MONOLITHIC EXCLUSIVE. Eight stones read downwards in the narrowest panel the monoliths ever cut: two HP of steps, four columns stacked behind them, and nothing else. The strip down the right picks which column you are cutting; PATT CV walks them on its own.",
		"ins": ["CLK", "RESET", "CHANCE CV", "PATT CV"], "outs": ["TRIG", "INV", "EOC"],
		"knobs": [_k("LENGTH", 1.0, 8.0, 8.0), _k("CHANCE", 0.0, 1.0, 1.0)],
		"sw": [], "steps": 8, "patterns": 4, "widget": "column"}
	c["polyrhythm"] = {"name": "FACET RHYTHM", "grp": "SEQUENCE", "hp": 24,
		"col": Color("#33ff99"), "only": "icos",
		"desc": "ICOSA EXCLUSIVE. Four trigger lanes, and every lane keeps its OWN length -- run them at 16, 12, 7 and 5 and the pattern will not come back round for over a thousand beats.",
		"ins": ["CLK", "RESET"], "outs": ["T 1", "T 2", "T 3", "T 4"],
		"knobs": [_k("LEN 1", 1.0, 16.0, 16.0), _k("LEN 2", 1.0, 16.0, 12.0),
			_k("LEN 3", 1.0, 16.0, 7.0), _k("LEN 4", 1.0, 16.0, 5.0)],
		"sw": [], "widget": "dseq"}
	c["roll"] = {"name": "FACET ROLL", "grp": "SEQUENCE", "hp": 34,
		"col": Color("#b388ff"), "only": "icos",
		"desc": "ICOSA EXCLUSIVE. A piano roll with eight patterns. BANK sets how many of them are in play, ORDER decides how the song walks them -- forwards, backwards, ping-pong or at random -- and CHAIN sets how many bars pass before it moves on. Click a note in, click it again for a rest, click a number to edit that bar.",
		"ins": ["CLK", "RESET", "TRANSPOSE", "PATT CV"],
		"outs": ["CV", "GATE", "EOC"],
		"knobs": [_k("LENGTH", 1.0, 16.0, 16.0), _k("PATTERN", 1.0, 8.0, 1.0),
			_k("BANK", 1.0, 8.0, 4.0), _k("OCT", -3.0, 3.0, 0.0),
			_k("GLIDE", 0.0, 1.0, 0.0)],
		"sw": [{"n": "ORDER", "opts": ["HOLD", "FORWARD", "BACKWARD", "PING-PONG", "RANDOM"], "def": 0},
			{"n": "CHAIN", "opts": ["1 BAR", "2 BARS", "4 BARS"], "def": 0}],
		"patterns": 8, "widget": "roll"}
	c["chancegrid"] = {"name": "FACET CHANCE", "grp": "SEQUENCE", "hp": 36,
		"col": Color("#33ff99"), "only": "icos",
		"desc": "ICOSA EXCLUSIVE. Not on or off: every one of the sixty-four cells holds a WEIGHT, and a step at 40% fires four times in ten. Drag a cell up and down to set its odds, click the top of it for a certainty, right-click to empty it. Four lanes, four patterns, and a pattern that never plays quite the same twice.",
		"ins": ["CLK", "RESET", "BIAS", "PATT CV"],
		"outs": ["T 1", "T 2", "T 3", "T 4", "ANY", "EOC"],
		"lanes": 4, "steps": 16, "patterns": 4,
		"knobs": [_k("LENGTH", 1.0, 16.0, 16.0), _k("BIAS", -1.0, 1.0, 0.0),
			_k("PATTERN", 1.0, 4.0, 1.0), _k("SWING", 0.0, 0.7, 0.0),
			_k("HOLD", 0.0, 1.0, 0.0)],
		"sw": [{"n": "DICE", "opts": ["FREE", "LOCKED", "DRIFT"], "def": 0}],
		"widget": "grid"}
	c["muse"] = {"name": "DUDE MUSE", "grp": "SEQUENCE", "hp": 28,
		"col": Color("#7be8ff"), "only": "dude",
		"desc": "DUDE AUDIO EXCLUSIVE. A melody writer. It composes a phrase in the scale you pick, plays it, and rewrites a little of it every time round -- VARY at zero is a loop, at full it is a new tune every bar. SEED picks which tune it starts from, so a phrase you like can be found again. CONTOUR is the shape it writes to.",
		"ins": ["CLK", "RESET", "MUTATE", "SEED CV"],
		"outs": ["CV", "GATE", "ACCENT", "EOP"],
		"knobs": [_k("SEED", 0.0, 999.0, 137.0), _k("LENGTH", 2.0, 16.0, 8.0),
			_k("ROOT", -12.0, 12.0, 0.0), _k("RANGE", 1.0, 4.0, 2.0),
			_k("DENSITY", 0.0, 1.0, 0.75), _k("VARY", 0.0, 1.0, 0.15),
			_k("GLIDE", 0.0, 1.0, 0.0)],
		"sw": [{"n": "SCALE", "opts": ["MAJOR", "MINOR", "DORIAN", "PHRYGIAN",
				"LYDIAN", "MIXO", "PENTA +", "PENTA -", "BLUES", "WHOLE", "CHROMA"], "def": 1},
			{"n": "CONTOUR", "opts": ["WANDER", "RISING", "FALLING", "ARCH", "LEAP"], "def": 0}],
		"widget": "muse"}
	c["chords"] = {"name": "CHORD BANK", "grp": "SEQUENCE", "hp": 22,
		"col": Color("#ffd166"),
		"desc": "Four voltages that always agree with each other: root, third, fifth and seventh of a chord, walked through a progression in the key you set. Patch ROOT to a bass and the others to a pad and nothing you write can land wrong. Feed a melody into TRACK and it is pulled onto the chord under it.",
		"ins": ["CLK", "RESET", "TRACK", "KEY CV"],
		"outs": ["ROOT", "3RD", "5TH", "7TH", "TRACK", "CHG"],
		"knobs": [_k("KEY", -12.0, 12.0, 0.0), _k("BARS", 1.0, 8.0, 4.0),
			_k("SPREAD", 0.0, 3.0, 1.0), _k("SEED", 0.0, 999.0, 42.0)],
		"sw": [{"n": "SCALE", "opts": ["MAJOR", "MINOR", "DORIAN", "MIXO"], "def": 1},
			{"n": "MOVE", "opts": ["I-V-vi-IV", "i-VI-III-VII", "i-iv-v-i",
				"DIATONIC RANDOM", "STATIC"], "def": 0},
			{"n": "VOICE", "opts": ["TRIAD", "SEVENTH", "SUS", "WIDE"], "def": 0}],
		"widget": "chords"}
	c["drunk"] = {"name": "DRUNK WALK", "grp": "MODULATE", "hp": 8,
		"col": Color("#b388ff"),
		"desc": "A voltage that wanders. Every clock it takes a step of up to STEP volts in a direction it mostly keeps, turns around when it hits the edge of RANGE, and fires TURN when it does. The lazy way to a melody that goes somewhere.",
		"ins": ["CLK", "STEP CV"], "outs": ["CV", "INV", "TURN"],
		"knobs": [_k("STEP", 0.0, 2.0, 0.4), _k("RANGE", 0.5, 5.0, 3.0),
			_k("BIAS", -1.0, 1.0, 0.0), _k("SLEW", 0.0, 1.0, 0.0)],
		"sw": [], "widget": "meter"}
	c["coin"] = {"name": "COIN TOSS", "grp": "LOGIC", "hp": 6,
		"col": Color("#8aff3a"),
		"desc": "One trigger in, two out, and a coin decides which. At PROB 1.0 everything goes to A, at 0.5 it is an even split -- the cheapest way to make a fixed rhythm stop being fixed.",
		"ins": ["TRIG", "PROB CV"], "outs": ["A", "B"],
		"knobs": [_k("PROB", 0.0, 1.0, 0.5)],
		"sw": [{"n": "MODE", "opts": ["TOSS", "LATCH", "TOGGLE"], "def": 0}],
		"widget": "meter"}
	c["ratchet"] = {"name": "RATCHET", "grp": "CLOCK", "hp": 8,
		"col": Color("#2bff5a"),
		"desc": "Takes one trigger and sometimes gives back two, three or four of them, packed inside the beat. CHANCE decides how often a beat gets subdivided, MAX how far it goes. Rolls and fills, without writing any of them.",
		"ins": ["CLK", "CHANCE CV"], "outs": ["OUT", "BURST"],
		"knobs": [_k("CHANCE", 0.0, 1.0, 0.3), _k("MAX", 2.0, 8.0, 4.0),
			_k("SPREAD", 0.0, 1.0, 0.5)],
		"sw": [], "widget": "meter"}
	c["beatbox"] = {"name": "DUDE BEATBOX", "grp": "SEQUENCE", "hp": 34,
		"col": Color("#7be8ff"), "only": "dude",
		"desc": "DUDE AUDIO EXCLUSIVE. A whole drum machine, not a trigger sequencer: EIGHT voices live inside it -- kick, snare, closed hat, open hat, clap, tom, rim and cowbell -- one lane each. Take the stereo mix straight out, or the kick, snare, hat and perc buses separately. SWING drags the off-beats, SPREAD panies the kit across the stereo field.",
		"ins": ["CLK", "RESET", "ACCENT"],
		"outs": ["MIX L", "MIX R", "KICK", "SNARE", "HAT", "PERC"],
		"lanes": 8,
		"knobs": [_k("TUNE", 30.0, 200.0, 55.0, "exp"), _k("DECAY", 0.05, 1.5, 0.35, "exp"),
			_k("SNAP", 0.0, 1.0, 0.5), _k("SWING", 0.0, 0.7, 0.0),
			_k("SPREAD", 0.0, 1.0, 0.5), _k("LEVEL", 0.0, 1.0, 0.8)],
		"sw": [{"n": "KIT", "opts": ["DUDE 808", "TIN CAN", "DEEP SPACE"], "def": 0}],
		"widget": "kit"}
	c["dudemix"] = {"name": "DUDE DESK", "grp": "PROCESS", "hp": 30,
		"col": Color("#c8ccd4"), "only": "dude",
		"desc": "DUDE AUDIO EXCLUSIVE. A proper channel mixer: six strips, each with a pan pot, a fader you actually drag, a mute button and a meter that moves. Master fader on the right, stereo bus and a mono sum out the bottom.",
		"ins": ["IN 1", "IN 2", "IN 3", "IN 4", "IN 5", "IN 6"],
		"outs": ["L", "R", "MONO"],
		"knobs": [_k("LVL 1", 0.0, 1.0, 0.65), _k("LVL 2", 0.0, 1.0, 0.65),
			_k("LVL 3", 0.0, 1.0, 0.65), _k("LVL 4", 0.0, 1.0, 0.65),
			_k("LVL 5", 0.0, 1.0, 0.65), _k("LVL 6", 0.0, 1.0, 0.65),
			_k("PAN 1", -1.0, 1.0, -0.4), _k("PAN 2", -1.0, 1.0, 0.4),
			_k("PAN 3", -1.0, 1.0, 0.0), _k("PAN 4", -1.0, 1.0, 0.0),
			_k("PAN 5", -1.0, 1.0, -0.8), _k("PAN 6", -1.0, 1.0, 0.8),
			_k("MASTER", 0.0, 1.5, 1.0)],
		"hide_knobs": true, "sw": [], "widget": "desk"}
	c["squash"] = {"name": "SQUASHER", "grp": "PROCESS", "hp": 15, "col": Color("#8ea6c8"),
		"only": "dude",
		"desc": "DUDE AUDIO EXCLUSIVE. A compressor with a sidechain input -- duck the bass under every kick, or just glue the whole mix together. The GR output is the gain reduction as a voltage.",
		"ins": ["THRESH", "RATIO CV", "MAKEUP CV", "IN", "SIDECHAIN"], "under": 3,
		"outs": ["OUT", "GR"],
		"knobs": [_k("THRESH", -5.0, 0.0, -2.0), _k("RATIO", 1.0, 20.0, 4.0, "exp"),
			_k("MAKEUP", 1.0, 8.0, 1.6, "exp")],
		"sw": [{"n": "SPEED", "opts": ["FAST", "SLOW"], "def": 0}], "widget": ""}
	c["grit"] = {"name": "GRIT BOX", "grp": "FX", "hp": 12, "col": Color("#7d8ca3"),
		"only": "dude",
		"desc": "DUDE AUDIO EXCLUSIVE. Throws away sample rate and bits on purpose. Gentle for warmth, hard for a signal that sounds like it came out of a broken vending machine.",
		"ins": ["RATE", "BITS CV", "IN"], "under": 2, "outs": ["OUT"],
		"knobs": [_k("RATE", 300.0, 22000.0, 8000.0, "exp"), _k("BITS", 1.0, 16.0, 8.0),
			_k("MIX", 0.0, 1.0, 1.0)],
		"sw": [], "widget": ""}
	c["cosmic"] = {"name": "COSMIC REVERB", "grp": "FX", "hp": 16, "col": Color("#b388ff"),
		"only": "icos",
		"desc": "ICOSA EXCLUSIVE. Not a room -- a distance. Six modulated tanks, a shimmer that lifts the tail an octave every pass, and a decay long enough to hear a planet go by. Feed it anything and it comes back as weather.",
		"ins": ["SIZE", "SHIMMER CV", "MIX CV", "IN"], "under": 3,
		"outs": ["L", "R"],
		"knobs": [_k("SIZE", 0.0, 1.0, 0.75), _k("SHIMMER", 0.0, 1.0, 0.45),
			_k("MIX", 0.0, 1.0, 0.5), _k("DAMP", 0.0, 1.0, 0.25),
			_k("DRIFT", 0.0, 1.0, 0.35), _k("WIDTH", 0.0, 1.0, 0.9)],
		"sw": [{"n": "SPACE", "opts": ["ORBIT", "NEBULA", "EVENT HORIZON"], "def": 1}],
		"widget": ""}
	c["grains"] = {"name": "FACET GRAINS", "grp": "FX", "hp": 15, "col": Color("#ff6ac1"),
		"only": "icos",
		"desc": "ICOSA EXCLUSIVE. Chops the incoming sound into little grains and throws them back at you out of order, at whatever pitch it feels like.",
		"ins": ["SIZE", "PITCH CV", "SPRAY CV", "IN"], "under": 3, "outs": ["OUT"],
		"knobs": [_k("SIZE", 0.01, 0.4, 0.08, "exp"), _k("PITCH", -2.0, 2.0, 0.0),
			_k("SPRAY", 0.0, 1.0, 0.4), _k("MIX", 0.0, 1.0, 0.6)],
		"sw": [], "widget": ""}
	c["harmonic"] = {"name": "TWENTY VOICES", "grp": "SOURCE", "hp": 28, "col": Color("#ffcf40"),
		"only": "icos",
		"desc": "ICOSA EXCLUSIVE. An additive oscillator with twenty harmonics, one bar each. Draw the spectrum and it plays exactly what you drew -- twenty faces, twenty partials.",
		"ins": ["V/OCT", "TILT CV"], "outs": ["OUT"],
		"knobs": [_k("OCT", -3.0, 3.0, 0.0), _k("TILT", -1.0, 1.0, 0.0),
			_k("LEVEL", 0.0, 1.0, 0.7)],
		"steps": 20, "sw": [], "widget": "bars"}
	c["arp"] = {"name": "SPIN ARP", "grp": "SEQUENCE", "hp": 14, "col": Color("#33ff99"),
		"only": "icos",
		"desc": "ICOSA EXCLUSIVE. Hold a note, feed it a clock, and it spins an arpeggio out of the chord it has been given -- up, down, inside out, or across the solid at random.",
		"ins": ["CV", "GATE", "CLK"], "outs": ["CV", "GATE"],
		"knobs": [_k("RANGE", 1.0, 4.0, 2.0), _k("SPREAD", 0.0, 12.0, 7.0),
			_k("GLIDE", 0.0, 1.0, 0.0)],
		"sw": [{"n": "ORDER", "opts": ["UP", "DOWN", "UP-DOWN", "RANDOM"], "def": 0}],
		"widget": ""}
	c["drone"] = {"name": "OBELISK DRONE", "grp": "SOURCE", "hp": 15, "col": Color("#8a7f70"),
		"only": "mono",
		"desc": "MONOLITHIC EXCLUSIVE. Four voices tuned to whole-number ratios, the way things were tuned before anybody agreed on a piano. Leave it running. It does not stop.",
		"ins": ["V/OCT", "SPREAD CV", "LEVEL CV"], "under": 2, "outs": ["OUT", "SUB"],
		"knobs": [_k("TUNE", -3.0, 3.0, -1.0), _k("SPREAD", 0.0, 1.0, 0.25),
			_k("LEVEL", 0.0, 1.0, 0.6)],
		"sw": [{"n": "RATIOS", "opts": ["1:2:3:4", "1:3:5:7", "2:3:5:8"], "def": 0}],
		"widget": ""}
	c["oracle"] = {"name": "STONE ORACLE", "grp": "LOGIC", "hp": 12, "col": Color("#c8342a"),
		"only": "mono",
		"desc": "MONOLITHIC EXCLUSIVE. Decides whether each trigger deserves to pass -- and sometimes answers a single trigger with a burst of them. What it refuses comes out of MISS.",
		"ins": ["CHANCE", "BURST CV", "TRIG"], "under": 2, "outs": ["PASS", "MISS"],
		"knobs": [_k("CHANCE", 0.0, 1.0, 0.7), _k("BURST", 1.0, 8.0, 1.0),
			_k("SPACING", 0.01, 0.4, 0.06, "exp")],
		"sw": [], "widget": ""}
	c["resonator"] = {"name": "STONE RESONATOR", "grp": "FILTER", "hp": 15,
		"col": Color("#6b6154"), "only": "mono",
		"desc": "MONOLITHIC EXCLUSIVE. Hit it with anything -- a click, a drum, noise -- and the stone rings at the pitch you tuned it to. Struck, not filtered.",
		"ins": ["V/OCT", "DAMP CV", "IN"], "under": 2, "outs": ["OUT"],
		"knobs": [_k("TUNE", -2.0, 3.0, 0.0), _k("DAMP", 0.0, 1.0, 0.35),
			_k("MIX", 0.0, 1.0, 0.8)],
		"sw": [{"n": "VOICES", "opts": ["ONE", "THREE"], "def": 1}], "widget": ""}
	c["slab"] = {"name": "SLAB DELAY", "grp": "FX", "hp": 14, "col": Color("#8a7f70"),
		"only": "mono",
		"desc": "MONOLITHIC EXCLUSIVE. A delay that only knows prime intervals, and plays every repeat BACKWARDS. Whatever you feed it comes back wrong in a way you cannot quite point at.",
		"ins": ["TIME", "FB CV", "IN"], "under": 2, "outs": ["OUT", "REVERSED"],
		"knobs": [_k("TIME", 0.05, 1.2, 0.3, "exp"), _k("REPEATS", 0.0, 0.95, 0.5),
			_k("MIX", 0.0, 1.0, 0.5)],
		"sw": [{"n": "PRIME", "opts": ["x2", "x3", "x5", "x7", "x11"], "def": 1}],
		"widget": ""}
	c["gravity"] = {"name": "GRAVITY WELL", "grp": "MODULATE", "hp": 12,
		"col": Color("#6b6154"), "only": "mono",
		"desc": "MONOLITHIC EXCLUSIVE. Drops a voltage into a well and lets it orbit. Heavy masses fall in and stay; light ones swing out and escape, and ESCAPE fires when one does.",
		"ins": ["TARGET", "KICK"], "outs": ["ORBIT", "VELOCITY", "ESCAPE"],
		"knobs": [_k("CENTRE", -5.0, 5.0, 0.0), _k("MASS", 0.05, 8.0, 1.0, "exp"),
			_k("DRAG", 0.0, 1.0, 0.15), _k("PUSH", 0.0, 5.0, 2.0)],
		"sw": [], "widget": ""}
	c["freeze"] = {"name": "ANCIENT ECHO", "grp": "FX", "hp": 14, "col": Color("#5a544c"),
		"only": "mono",
		"desc": "MONOLITHIC EXCLUSIVE. Catches one second of sound and refuses to let go of it -- looped, dropped an octave, ringing on forever. Hold FREEZE and whatever was playing becomes the room.",
		"ins": ["FREEZE", "IN"], "under": 1, "outs": ["OUT"],
		"knobs": [_k("FREEZE", 0.0, 1.0, 0.0), _k("LENGTH", 0.05, 1.0, 0.4),
			_k("SHIMMER", 0.0, 1.0, 0.4), _k("MIX", 0.0, 1.0, 0.7)],
		"sw": [{"n": "DROP", "opts": ["OCTAVE", "FIFTH", "SAME"], "def": 0}],
		"widget": ""}
	c["dustgate"] = {"name": "DUST GATE", "grp": "FX", "hp": 12, "col": Color("#c8342a"),
		"only": "mono",
		"desc": "MONOLITHIC EXCLUSIVE. Every so often it grabs a sliver of the signal and stutters it, then hands the sound back as if nothing happened. Turn CHANCE up and the stone starts skipping.",
		"ins": ["CHANCE", "SIZE CV", "IN"], "under": 2, "outs": ["OUT", "GLITCHING"],
		"knobs": [_k("CHANCE", 0.0, 1.0, 0.3), _k("SIZE", 0.01, 0.3, 0.06, "exp"),
			_k("REPEATS", 1.0, 8.0, 3.0)],
		"sw": [], "widget": ""}
	c["wrathtap"] = {"name": "WRATH TAP", "grp": "INPUT", "hp": 10, "col": Color("#ff3a2a"),
		"only": "mono",
		"desc": "MONOLITHIC EXCLUSIVE. The stone is listening to something older than you. WRATH follows the sky god's temper, CHAIN follows how far the monolith chain has been walked, and OMEN fires whenever either of them changes.",
		"ins": [], "outs": ["WRATH", "CHAIN", "OMEN"],
		"knobs": [_k("GAIN", 0.0, 2.0, 1.0), _k("SMOOTH", 0.0, 1.0, 0.4)],
		"sw": [], "widget": ""}
	c["watcher"] = {"name": "THE WATCHER", "grp": "SOURCE", "hp": 18,
		"col": Color("#c8342a"), "only": "mono",
		"desc": "MONOLITHIC EXCLUSIVE. An oscillator carved rather than shaped: it stacks partials and then CHISELS notches out of them, so the tone changes by losing harmonics instead of filtering them. GRAIN adds the dust of the stone it was cut from. It drifts, slowly, and it does not care.",
		"ins": ["V/OCT", "CHISEL CV", "GRAIN CV", "SYNC"], "under": 3,
		"outs": ["CARVED", "SUB", "PULSE"],
		"knobs": [_k("TUNE", -3.0, 3.0, 0.0), _k("CHISEL", 0.0, 1.0, 0.35),
			_k("GRAIN", 0.0, 1.0, 0.15)],
		"sw": [{"n": "STACK", "opts": ["4 PARTIALS", "8 PARTIALS", "12 PARTIALS"], "def": 1}],
		"widget": "carve"}
	c["mystery"] = {"name": "?????", "grp": "MODULATE", "hp": 18,
		"col": Color("#8a7f70"), "only": "mono",
		"desc": "Three in. Three out. Three ways to lean on it. It was already doing this when the dudes got here and nobody has worked out what.",
		# the jacks are UNLABELLED on the panel, but they still need names
		# internally: a patch is saved by jack name, and six jacks all
		# called "" collapse onto each other on the next load
		"ins": ["A", "B", "C", "LAMBDA", "PSI", "OMEGA"],
		"side": true, "under_last": 3, "blank_labels": true,
		"outs": ["X", "Y", "Z"],
		"knobs": [_k("\u03bb", 0.0, 1.0, 0.31), _k("\u03c8", 0.0, 1.0, 0.62),
			_k("\u03a9", 0.0, 1.0, 0.5)],
		"sw": [], "widget": "glyph"}
	c["eyefilter"] = {"name": "THE EYE", "grp": "FILTER", "hp": 16,
		"col": Color("#c8342a"), "only": "mono",
		"desc": "MONOLITHIC EXCLUSIVE. Five resonant bands stacked like a throat -- sweep them and whatever you feed it starts forming vowels. Every knob has its own CV jack directly beneath it. The ENV output is the stone listening back.",
		"ins": ["SWEEP", "SPREAD CV", "RES CV", "MIX CV", "IN"], "under": 4,
		"outs": ["OUT", "ENV"],
		"knobs": [_k("SWEEP", 90.0, 2400.0, 420.0, "exp"), _k("SPREAD", 1.1, 3.0, 1.8),
			_k("RES", 0.1, 0.99, 0.8), _k("MIX", 0.0, 1.0, 1.0)],
		"sw": [], "widget": ""}
	c["obelisk"] = {"name": "OBELISK CLOCK", "grp": "CLOCK", "hp": 12, "col": Color("#8a7f70"),
		"only": "mono",
		"desc": "MONOLITHIC EXCLUSIVE. Time divided the old way: by primes. Nothing lines up again until the second, third, fifth, seventh and eleventh all agree.",
		"ins": ["CLK", "RESET"], "outs": ["/2", "/3", "/5", "/7", "/11"],
		"knobs": [_k("BPM", 20.0, 300.0, 96.0), _k("DRIFT", 0.0, 1.0, 0.0),
			_k("WIDTH", 0.05, 0.9, 0.5)],
		"sw": [{"n": "SOURCE", "opts": ["INTERNAL", "EXTERNAL"], "def": 0}], "widget": ""}

	# ---------------------------------------------------------- terminal
	c["scope"] = {"name": "SCOPE", "grp": "VISUAL", "hp": 14, "col": Color("#3aff6a"),
		"desc": "Two-trace oscilloscope. Look at what you built before you believe it.",
		"ins": ["IN A", "IN B"], "outs": ["THRU"],
		"knobs": [_k("TIME", 0.002, 0.3, 0.02, "exp"), _k("GAIN", 0.2, 4.0, 1.0)],
		"sw": [], "widget": "scope"}
	c["spectrum"] = {"name": "SPECTRUM", "grp": "VISUAL", "hp": 20,
		"col": Color("#33ff99"),
		"desc": "Twelve bands of the signal, drawn as bars. Watch a filter sweep, find the frequency that is fighting you, see which voice is eating the mix. THRU passes the signal on untouched.",
		"ins": ["IN"], "outs": ["THRU", "BAND"],
		"knobs": [_k("LOW", 40.0, 800.0, 90.0, "exp"), _k("SPAN", 1.3, 3.0, 2.0),
			_k("GAIN", 0.2, 6.0, 1.4), _k("FALL", 0.0, 1.0, 0.35),
			_k("PICK", 1.0, 12.0, 1.0)],
		"sw": [], "widget": "spectrum"}
	c["vector"] = {"name": "VECTOR SCOPE", "grp": "VISUAL", "hp": 14,
		"col": Color("#b388ff"),
		"desc": "Plots one signal against another instead of against time. Two oscillators at a simple ratio draw a still figure; anything else draws weather. The classic way to SEE tuning.",
		"ins": ["X", "Y"], "outs": ["THRU"],
		"knobs": [_k("GAIN", 0.2, 4.0, 1.0), _k("TRAIL", 0.0, 1.0, 0.6)],
		"sw": [], "widget": "vector"}
	c["vu"] = {"name": "VU METERS", "grp": "VISUAL", "hp": 10, "col": Color("#ffd166"),
		"desc": "Four needles with peak hold, so you can see which channel is clipping before you hear it. Sits across a mixer's sends or straight on the output.",
		"ins": ["IN 1", "IN 2", "IN 3", "IN 4"], "outs": ["THRU 1", "PEAK"],
		"knobs": [_k("GAIN", 0.2, 4.0, 1.0), _k("HOLD", 0.0, 1.0, 0.5)],
		"sw": [], "widget": "vu"}
	c["waterfall"] = {"name": "WATERFALL", "grp": "VISUAL", "hp": 18,
		"col": Color("#7be8ff"),
		"desc": "A spectrogram that scrolls: frequency up the panel, time across it, brightness for how loud. Long evolving patches show their whole shape in here.",
		"ins": ["IN"], "outs": ["THRU"],
		"knobs": [_k("LOW", 40.0, 800.0, 80.0, "exp"), _k("SPAN", 1.3, 3.0, 2.1),
			_k("GAIN", 0.2, 6.0, 1.6), _k("SPEED", 0.05, 1.0, 0.4)],
		"sw": [], "widget": "waterfall"}
	c["analyser"] = {"name": "WAVE ANALYSER", "grp": "VISUAL", "hp": 20,
		"col": Color("#c8ccd4"),
		"desc": "Measures whatever you feed it and tells you in numbers: frequency and the nearest note with its error in cents, peak and RMS volts, DC offset, duty cycle, and its best guess at the shape. PITCH comes out as 1V/oct so you can track one oscillator with another, LEVEL follows the loudness, and GATE goes high whenever there is a signal at all.",
		"ins": ["IN"], "outs": ["PITCH", "LEVEL", "GATE", "THRU"],
		"knobs": [_k("SENS", 0.01, 2.0, 0.15, "exp"), _k("SMOOTH", 0.0, 1.0, 0.35),
			_k("REF", 415.0, 466.0, 440.0)],
		"sw": [], "widget": "analyser"}
	c["out"] = {"name": "AUDIO OUT", "grp": "UTILITY", "hp": 8, "col": Color("#ffffff"),
		"desc": "The speakers. NOTHING is heard unless it is patched in here: L alone plays mono out of both, L+R plays stereo.",
		"ins": ["L / MONO", "R"], "outs": [],
		"knobs": [_k("VOLUME", 0.0, 1.0, 0.7)],
		"sw": [], "widget": "meter"}

	for id in c.keys():
		var d: Dictionary = c[id]
		d["id"] = id
		if not d.has("sw"):
			d["sw"] = []
	_cat = c
	_ids = []
	for id in ["button", "vkeys", "xy", "world", "cast",
			"vco", "lfo", "noise", "drum", "keys", "voice", "harmonic", "drone",
			"vcf", "eyefilter", "resonator", "gravity", "wrathtap",
			"watcher", "mystery", "vca", "dudemix", "squash", "mix4", "atten", "const", "ring", "fold", "drive",
			"adsr", "slew", "sh", "quant", "chaos", "drunk",
			"clock", "cdiv", "obelisk", "ratchet", "logic", "comp", "oracle", "coin",
			"seq8", "dseq", "euclid", "turing", "poly20", "roll", "stonetrig", "polyrhythm", "beatbox", "arp",
			"chancegrid", "muse", "chords",
			"phaser", "reverb", "delay", "tape", "grit", "grains",
			"slab", "freeze", "dustgate", "cosmic",
			"scope", "spectrum", "vector", "vu", "waterfall", "analyser", "out"]:
		_ids.append(id)

static func ids() -> Array[String]:
	_build()
	return _ids

static func def(id: String) -> Dictionary:
	_build()
	return _cat.get(id, _cat["vca"])

## "" = anyone builds it; otherwise only that house does, and its
## panel can never be rebranded.
static func exclusive_to(id: String) -> String:
	return str(def(id).get("only", ""))

static func has(id: String) -> bool:
	_build()
	return _cat.has(id)

## Groups, in palette order.
static func groups() -> Array:
	return ["INPUT", "SOURCE", "FILTER", "PROCESS", "MODULATE", "CLOCK",
		"LOGIC", "SEQUENCE", "FX", "VISUAL", "UTILITY"]

## Knobs whose value is a COUNT, not a sweep: these snap to whole
## numbers so two clocks set to "120" are both at exactly 120 and stay
## in the phase relationship you gave them instead of slowly drifting
## through each other.
const SNAP_KNOBS: Array[String] = ["BPM", "LENGTH", "STEPS", "FILL", "ROTATE",
	"ROOT", "OCT", "TRANSPOSE", "PATTERN", "BANK", "REPEATS", "BURST",
	"LEN 1", "LEN 2", "LEN 3", "LEN 4", "BITS"]

## A knob's real value from its stored 0..1 position.
static func knob_val(kd: Dictionary, norm: float) -> float:
	var lo: float = float(kd["min"])
	var hi: float = float(kd["max"])
	var n := clampf(norm, 0.0, 1.0)
	var v: float
	if str(kd.get("cur", "lin")) == "exp" and lo > 0.0:
		v = lo * pow(hi / lo, n)
	else:
		v = lo + (hi - lo) * n
	if SNAP_KNOBS.has(str(kd.get("n", ""))):
		v = round(v)
	return v

## ...and back, for defaults.
static func knob_norm(kd: Dictionary, v: float) -> float:
	var lo: float = float(kd["min"])
	var hi: float = float(kd["max"])
	if str(kd.get("cur", "lin")) == "exp" and lo > 0.0:
		return clampf(log(maxf(v, lo) / lo) / log(hi / lo), 0.0, 1.0)
	if absf(hi - lo) < 0.0001:
		return 0.0
	return clampf((v - lo) / (hi - lo), 0.0, 1.0)

static func knob_text(kd: Dictionary, norm: float) -> String:
	var v := knob_val(kd, norm)
	var n: String = str(kd["n"])
	if n == "BPM" or n == "LENGTH" or n == "STEPS" or n == "FILL" \
			or n == "ROTATE" or n == "ROOT" or n == "OCT" or n == "TRANSPOSE":
		return "%d" % int(round(v))
	if float(kd["max"]) > 900.0:
		return "%.0f Hz" % v if v < 1000.0 else "%.2f kHz" % (v / 1000.0)
	if n == "RATE" and v < 0.2:
		return "1 per %.0f s" % (1.0 / maxf(v, 0.00001)) if v > 0.017 \
			else "1 per %.1f min" % (1.0 / maxf(v, 0.00001) / 60.0)
	if str(kd.get("cur", "lin")) == "exp" and float(kd["max"]) <= 12.0 and n != "DRIVE":
		return "%.0f ms" % (v * 1000.0) if v < 1.0 else "%.2f s" % v
	return "%.2f" % v

# --------------------------------------------------------------- layout
## ONE panel layout, used by the editor AND by the 3D faceplate, so a
## jack is never in two different places. All positions in panel units,
## origin top-left, y down.

static var _lay: Dictionary = {}

const JACK_R := 3.0
const KNOB_R := 5.0
const KNOB_PITCH_X := 16.0
const KNOB_PITCH_Y := 21.0
const JACK_PITCH_X := 13.0
const JACK_PITCH_Y := 15.0

static func layout(id: String) -> Dictionary:
	if _lay.has(id):
		return _lay[id]
	var d := def(id)
	var w: float = float(int(d["hp"])) * HPW
	var under: int = int(d.get("under", 0))
	var out := {"w": w, "h": PANEL_H, "knobs": [], "sw": [], "jin": [], "jout": [],
		"widget": Rect2(0, 0, 0, 0), "under": under}
	var y := 20.0        # under the silkscreened title
	# a TOP ROW panel puts its first knob and its first input up here,
	# side by side, and starts the widget below them
	var toprow: bool = bool(d.get("toprow", false))
	if toprow:
		out["knobs"].append(Vector2(w * 0.30, 30.0))
		y = 46.0
	# --- widget block (sequencer grid, scope screen, keyboard...)
	var wg := str(d["widget"])
	if wg != "":
		var wh := 30.0
		match wg:
			"seq8": wh = 34.0
			"dseq": wh = 30.0
			"kit": wh = 40.0
			"column": wh = 34.0
			"eye": wh = 24.0
			"carve": wh = 20.0
			"glyph": wh = 52.0
			"scope": wh = 34.0
			"spectrum": wh = 44.0
			"vector": wh = 46.0
			"vu": wh = 40.0
			"waterfall": wh = 52.0
			"analyser": wh = 54.0
			"keys": wh = 26.0
			"euclid": wh = 34.0
			"turing": wh = 14.0
			"meter": wh = 16.0
			"seqn": wh = 34.0
			"buttons": wh = 30.0
			"desk": wh = 72.0
			"vkeys": wh = 62.0
			"xy": wh = 46.0
			"bars": wh = 40.0
			"cast": wh = 44.0
			"roll": wh = 28.0
			"grid": wh = 46.0
			"muse": wh = 34.0
			"chords": wh = 26.0
		# a panel that wears its jacks on the SIDES has to leave those
		# columns clear -- a full-width widget drew straight over the top
		# two jacks and buried them
		if bool(d.get("side", false)):
			out["widget"] = Rect2(14.0, y, w - 28.0, wh)
		else:
			out["widget"] = Rect2(3.0, y, w - 6.0, wh)
		y += wh + 5.0
	# --- knobs, left to right, top to bottom
	var kn: Array = d["knobs"]
	var kcols: int = maxi(1, int((w - 4.0) / KNOB_PITCH_X))
	# some panels lay their own controls out inside the widget (a mixing
	# desk draws faders, not knobs) -- the knobs still exist as the
	# stored values, they simply are not placed on the faceplate
	if bool(d.get("hide_knobs", false)):
		kn = []
	if toprow:
		kn = kn.slice(1)          # knob 0 is already placed up top
	if kn.size() > 0:
		var rows: int = int(ceil(float(kn.size()) / float(kcols)))
		var cw := (w - 4.0) / float(kcols)
		# a row whose knobs carry CV jacks underneath needs the room for
		# them: without this the jacks of row 1 sat inside the knobs of
		# row 2 (the cosmic reverb complaint)
		var row_y: Array = []
		var yy := y + KNOB_R + 2.0
		for r in rows:
			row_y.append(yy)
			yy += KNOB_PITCH_Y
			if r * kcols < under:
				yy += 16.0
		for i in kn.size():
			var r2: int = i / kcols
			var cc: int = i % kcols
			var in_row: int = mini(kcols, kn.size() - r2 * kcols)
			var pad := (w - 4.0 - float(in_row) * cw) * 0.5
			out["knobs"].append(Vector2(2.0 + pad + cw * (float(cc) + 0.5),
				float(row_y[r2])))
		y = yy - KNOB_R + 1.0
	# a jack bolted under each of the first `under` knobs: the CV input
	# for the thing the knob sets, exactly where your eye expects it
	var under_pos: Array = []
	if under > 0:
		for i in mini(under, (out["knobs"] as Array).size()):
			var kpv: Vector2 = out["knobs"][i]
			under_pos.append(Vector2(kpv.x, kpv.y + KNOB_R + 11.0))
		# the room for these was already reserved row by row above
	# --- switches, full width, stacked
	for i in (d["sw"] as Array).size():
		out["sw"].append(Rect2(3.0, y, w - 6.0, 9.0))
		y += 11.0
	# --- jacks: outputs pinned to the bottom, inputs just above them
	# some panels park an input up at the TOP, beside a control that
	# lives in the widget (the keyboard's octave slider does this)
	var topin: int = int(d.get("topin", 0))
	# a few panels wear their jacks on the SIDES instead of the bottom
	if bool(d.get("side", false)):
		var nsi: int = (d["ins"] as Array).size()
		var nso: int = (d["outs"] as Array).size()
		# the LAST few inputs (if any) belong under the knobs instead of
		# on the edge -- a control that has a jack under it is obviously
		# the jack for that control
		var ulast: int = int(d.get("under_last", 0))
		var edge_n: int = maxi(0, nsi - ulast)
		for i in edge_n:
			out["jin"].append(Vector2(7.0, 34.0 + float(i) * 26.0))
		for i in ulast:
			var kpos: Vector2 = out["knobs"][i] if i < (out["knobs"] as Array).size() \
				else Vector2(w * 0.5, 90.0)
			out["jin"].append(Vector2(kpos.x, kpos.y + KNOB_R + 11.0))
		for i in nso:
			out["jout"].append(Vector2(w - 7.0, 34.0 + float(i) * 26.0))
		_lay[id] = out
		return out
	var jc: int = maxi(1, int((w - 2.0) / JACK_PITCH_X))
	var outs: Array = d["outs"]
	var ins: Array = d["ins"]
	var nbot: int = maxi(0, ins.size() - under - topin)   # inputs left for the bottom rows
	var orows: int = int(ceil(float(outs.size()) / float(jc))) if outs.size() > 0 else 0
	var irows: int = int(ceil(float(nbot) / float(jc))) if nbot > 0 else 0
	var jb := PANEL_H - 7.0
	var oy0 := jb - float(maxi(orows - 1, 0)) * JACK_PITCH_Y
	var iy0 := oy0 - (JACK_PITCH_Y if orows > 0 else 0.0) - float(maxi(irows - 1, 0)) * JACK_PITCH_Y
	for pass_i in 2:
		var lst: Array = (ins.slice(under + topin) if pass_i == 0 else outs)
		var y0: float = iy0 if pass_i == 0 else oy0
		var key: String = "jin" if pass_i == 0 else "jout"
		if pass_i == 0:
			for up_p in under_pos:
				out["jin"].append(up_p)
			for t in topin:
				out["jin"].append(Vector2(w - 7.0, 30.0 if toprow else 27.0))
		for i in lst.size():
			var r2: int = i / jc
			var cc2: int = i % jc
			var in_row2: int = mini(jc, lst.size() - r2 * jc)
			var cw2 := (w - 2.0) / float(jc)
			var pad2 := (w - 2.0 - float(in_row2) * cw2) * 0.5
			out[key].append(Vector2(1.0 + pad2 + cw2 * (float(cc2) + 0.5),
				y0 + float(r2) * JACK_PITCH_Y))
	# --- crowding pass. The jack block is pinned to the BOTTOM edge and
	# everything else is stacked from the top, so a busy panel can walk
	# its switches straight into its jacks. Nothing may overlap: give the
	# widget back the difference and lift the controls clear.
	var jack_top: float = (iy0 if irows > 0 else oy0) - JACK_R - 3.0
	var low := 0.0
	for kq in out["knobs"]:
		low = maxf(low, float((kq as Vector2).y) + KNOB_R)
	for sq in out["sw"]:
		low = maxf(low, (sq as Rect2).end.y)
	for uq in under_pos:
		low = maxf(low, float((uq as Vector2).y) + JACK_R)
	var need: float = low - jack_top
	if need > 0.0:
		# the widget is the only element that can afford to give: shrink
		# it, never below a usable height, and lift everything under it
		var wr0: Rect2 = out["widget"]
		var give: float = 0.0
		if wr0.size.y > 0.0:
			give = minf(need, maxf(0.0, wr0.size.y - 18.0))
			wr0.size.y -= give
			out["widget"] = wr0
		var lift: float = give
		if lift > 0.0:
			for i in (out["knobs"] as Array).size():
				out["knobs"][i] = (out["knobs"][i] as Vector2) - Vector2(0.0, lift)
			for i in (out["sw"] as Array).size():
				var sr: Rect2 = out["sw"][i]
				sr.position.y -= lift
				out["sw"][i] = sr
			for i in mini(under + topin, (out["jin"] as Array).size()):
				out["jin"][i] = (out["jin"][i] as Vector2) - Vector2(0.0, lift)
	_lay[id] = out
	return out

## Where the panel's own content ends (used to sanity-check crowding).
static func fits(id: String) -> bool:
	var d0 := def(id)
	if bool(d0.get("side", false)):
		return true          # jacks on the edges: nothing to crowd
	var l := layout(id)
	var top_end := 20.0
	var d := def(id)
	if str(d["widget"]) != "":
		top_end = (l["widget"] as Rect2).end.y
	for k in l["knobs"]:
		top_end = maxf(top_end, float((k as Vector2).y) + KNOB_R + 6.0)
	for s in l["sw"]:
		top_end = maxf(top_end, (s as Rect2).end.y)
	var first_jack := PANEL_H
	var und: int = int(l.get("under", 0)) + int(d0.get("topin", 0))
	var bottom: Array = (l["jin"] as Array).slice(und) + (l["jout"] as Array)
	for k2 in int(l.get("under", 0)):
		top_end = maxf(top_end, float((l["jin"][k2] as Vector2).y) + JACK_R + 4.0)
	for j in bottom:
		first_jack = minf(first_jack, float((j as Vector2).y) - JACK_R - 5.0)
	return top_end <= first_jack

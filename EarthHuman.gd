class_name EarthHuman
extends CharacterBody3D
## Earth's native species: the Human. Observably one of the dumbest
## creatures in the universe -- walks into rocks, stares at nothing,
## jumps for no reason, follows you around. But press F and you get a
## glimpse of the inner life, which is somehow vast. Just like the
## real thing.

const WALK_SPEED := 2.6
const PANIC_SPEED := 6.5

## What they are DOING (visible, dumb). Feet stay on the ground -- they
## are dumb, not astronauts.
const ACTS := ["wander", "stare", "circle", "spin", "follow"]

## Shirt slogans are ASSEMBLED, never pretyped: three word-banks strung
## together into something that almost means something. Like real shirts.
const SHIRT_A := ["I SURVIVED", "PROFESSIONAL", "ASK ME ABOUT", "CERTIFIED",
	"WORLD'S OKAYEST", "POWERED BY", "ALLERGIC TO", "LOCAL", "FORMER",
	"PROUD OWNER OF", "DO NOT TRUST", "SPONSORED BY", "I MISS", "CEO OF",
	"RECOVERING FROM", "VOTED MOST", "OFFICIAL", "IN LOVE WITH",
	"RUNNING FROM", "HAUNTED BY", "FUELED BY", "MARRIED TO", "AFRAID OF",
	"CHAMPION OF", "BANNED FROM", "LOYAL TO", "PRAY FOR", "50% OFF",
	"WARNING:", "FREE", "I BELIEVE IN", "STILL PAYING FOR"]
const SHIRT_B := ["MY OWN", "THE MOON'S", "YESTERDAY'S", "AN UNPAID",
	"A SUSPICIOUS", "THE THIRD", "SOMEBODY'S", "MY DOCTOR'S", "GRAVITY'S",
	"AN IMAGINARY", "ONE (1)", "THE ORIGINAL", "AN EXTREMELY LEGAL",
	"MY LANDLORD'S", "A GOVERNMENT", "THE LAST", "AN AVERAGE",
	"THE NEIGHBOR'S", "A LIMITED EDITION", "MY EMOTIONAL"]
const SHIRT_C := ["OPINIONS", "SOUP", "REGRET", "NAP", "LADDER", "PARADE",
	"HAIRCUT", "BUSINESS PLAN", "NOODLE", "MISTAKE", "SANDWICH", "HOMEWORK",
	"DESTINY", "KNEES", "PONYTAIL", "LASAGNA", "PIGEON", "TAXES",
	"MOUSTACHE", "SITUATION", "CASSEROLE", "PAPERWORK", "TRAMPOLINE",
	"FEELINGS", "INVOICE", "GOOSE", "SIDE HUSTLE", "VIBES", "ELBOW",
	"CONSPIRACY", "LEFTOVERS", "WARRANTY", "DENTIST", "MIXTAPE"]

## Personality axes, 0-100 each. Faces carry these values (set in the
## F9 editor); a human wearing a face THINKS like that face.
const AXES := ["anxious", "confident", "dreamy", "dumb", "grumpy", "goofy", "edgy", "awkward"]

## Personalities come in SHAPES, not dice: axes travel in packs. Each
## human rolls an archetype first, then rolls their axes inside its
## ranges (unlisted axes default low). THE sour one. THE sunshine.
const ARCHETYPES := [
	{"grumpy": [65, 95], "edgy": [55, 90], "confident": [20, 60],
		"goofy": [0, 15], "dreamy": [0, 20]},                        # the sour
	{"edgy": [70, 100], "awkward": [30, 70], "grumpy": [30, 65],
		"dreamy": [20, 55], "goofy": [0, 10]},                       # the gothling
	{"goofy": [55, 90], "dreamy": [45, 85], "confident": [35, 70],
		"dumb": [15, 50], "grumpy": [0, 10], "edgy": [0, 10]},       # the sunshine
	{"anxious": [65, 95], "awkward": [55, 90], "grumpy": [10, 40],
		"dreamy": [15, 45], "confident": [0, 15]},                   # the wreck
	{"dumb": [60, 95], "goofy": [50, 90], "confident": [50, 85],
		"dreamy": [20, 55], "anxious": [0, 15]},                     # the himbo
	{"confident": [70, 100], "grumpy": [15, 50], "edgy": [10, 45],
		"goofy": [15, 45], "awkward": [0, 15], "anxious": [0, 15]},  # the main character
	{"dreamy": [65, 100], "awkward": [25, 60], "dumb": [25, 60],
		"goofy": [20, 55], "grumpy": [0, 15]},                       # the spacecase
	{"anxious": [15, 45], "confident": [15, 45], "dreamy": [15, 45],
		"dumb": [15, 45], "grumpy": [15, 45], "goofy": [15, 45],
		"edgy": [10, 40], "awkward": [15, 45]},                      # the average joe
]

## What they are THINKING (hidden, vast). F to ask. Pools per axis;
## the face's weights decide which pool their mind lives in.
const THOUGHTS := {
	"neutral": [
		"I hunger, therefore I am.",
		"I am 70% water pretending to be busy",
		"one day I will die. anyway, time to walk in circles.",
		"is the blue dude a god? he has a jetpack. gods have jetpacks.",
		"I contain multitudes. mostly snacks.",
	],
	"anxious": [
		"the mortgage isn't real if I don't think about it",
		"did I leave something on? I don't own anything. did I leave it on?",
		"everyone saw me trip on the flat ground. everyone. the sky too.",
		"what if the ground stops. it won't. but what IF.",
		"I should call my mother. do I have a mother? I should call someone.",
		"the eye in the sky knows what I did. I don't even know what I did.",
		"heart rate: elevated. reason: unclear. situation: normal.",
	],
	"confident": [
		"what if I'm the main character. I am. it's me.",
		"I could have been anything. I chose: standing here. nailed it.",
		"the rock moved for ME.",
		"future biographers will want this exact moment. hold the pose.",
		"I've never been wrong. once I thought I was. I was wrong about that.",
		"this planet is lucky to have me on it.",
	],
	"dreamy": [
		"every day the sun leaves and every day I forgive it",
		"sometimes I stand still so the universe can find me",
		"what if the sky is just a very big floor",
		"do the stars know my name? do I know my name? note to self: get a name",
		"circles are just walking that comes back. profound.",
		"the void stares back but honestly it started it",
		"clouds are mountains that gave up. respect.",
		"somewhere out there is a version of me that can fly. hi, me.",
		"if I stand still long enough, maybe I become scenery. maybe that's enough.",
	],
	"dumb": [
		"I have walked into that rock four times. The rock and I have history now.",
		"spinning feels right. I don't question it anymore.",
		"today I will be productive. tomorrow. definitely tomorrow.",
		"tried to count my legs. lost track. more than one, probably.",
		"if I close my eyes the world stops. I checked. it works.",
		"the sun is just the moon doing a good job.",
		"I put my thoughts somewhere and now I can't find them.",
	],
	"grumpy": [
		"my knees hurt in a way that feels philosophical",
		"used to be better here. before. when things were.",
		"the wind is doing it on purpose.",
		"everyone is walking WRONG today.",
		"I was promised nothing and it STILL under-delivered.",
		"kids these days orbit ANYTHING.",
		"whatever that blue dude is selling, I'm not buying it.",
	],
	"goofy": [
		"WOOOO. anyway.",
		"my elbows are for AFTER lunch",
		"if I run fast enough my shirt makes the flappy sound. best sound.",
		"honk. that was me. I did the honk.",
		"today's plan: wiggle. tomorrow: bigger wiggle.",
		"I named both my feet. they hate each other. it's a whole thing.",
		"watch this. (nothing happens) I know RIGHT?",
	],
	"awkward": [
		"was that a wave? were they waving at ME? I waved back at nobody.",
		"said 'you too' when they said 'nice planet'. living with that now.",
		"I've been standing here too long to leave normally.",
		"do I walk past them again or is twice the limit. it's twice. it was twice.",
		"laughed at the wrong moment. committing to it. this is who I am now.",
		"my hands. where do they usually go. what do I usually do with them.",
		"rehearsed saying hi. they said hey. script RUINED.",
	],
	"edgy": [
		"nobody understands me. especially me.",
		"the darkness and I have an arrangement.",
		"I wasn't ignoring you. I was ignoring EVERYTHING.",
		"this planet doesn't deserve my footsteps.",
		"smiling is a scam and I've opted out.",
		"I only walk in circles because straight lines are conformist.",
		"you wouldn't get it. the rock gets it.",
	],
}

## Every human gets a NAME (worn on a nametag, because life is one long
## conference) and an ID (for the code; humans never learn they have one).
const NAMES := ["Kevin", "John", "Greg", "Dave", "Carl", "Gary", "Linda",
	"Susan", "Karen", "Barb", "Doug", "Phil", "Terry", "Marge", "Todd",
	"Brenda", "Craig", "Denise", "Gordon", "Pam", "Randy", "Sheila", "Bert",
	"Gloria", "Frank", "Judy", "Wayne", "Deb", "Marvin", "Rhonda", "Clive",
	"Janet", "Norm", "Cheryl", "Stan", "Ruth", "Larry", "Diane", "Chad",
	"Wanda", "Earl", "Peggy", "Duane", "Lois", "Vern", "Tammy", "Boris",
	"Agnes"]

## SOCIAL: said TO you, out loud, when you get close (or they do).
## Thoughts are the inside; this is the outside. The gap explains a lot.
const SOCIAL := {
	"neutral": [
		"hey. I'm {n}. that's the whole update.",
		"nice gravity today.",
		"we're standing together. this is society.",
		"you're the blue dude. I've heard things. all of them confusing.",
		"good orbit we're having.",
	],
	"anxious": [
		"you walked up SO fast. is something wrong. is it me.",
		"hi. sorry. hi. sorry.",
		"I wasn't doing anything. why, what did you hear.",
		"oh good, company. oh no, company.",
	],
	"confident": [
		"you found me. good instincts.",
		"you're welcome, by the way. for all of this.",
		"{n}. remember the name. everyone will.",
		"stand closer, greatness rubs off.",
	],
	"dreamy": [
		"oh. I thought you were the wind.",
		"do you ever look at the sky and just... yeah. exactly.",
		"you have a good aura. sort of blue. very blue, actually.",
		"if you're here, the universe sent you. tell it thanks.",
	],
	"dumb": [
		"I know you! or a rock that looks like you. either way, hi!",
		"hello!! I had more but it's gone.",
		"are you new? I'm new. I've been here my whole life and I'm new.",
		"wanna watch me count to a number?",
	],
	"grumpy": [
		"you're standing where I was about to stand.",
		"what. WHAT.",
		"in MY day the sky had fewer eyes.",
		"if you're selling something, no. if you're not, also no.",
	],
	"goofy": [
		"HONK. hi. the honk was also hi.",
		"wanna see me wiggle? too late. already happened.",
		"{n}, professional. professional what? EXACTLY.",
		"high five! okay, rain check. the hand stays up though.",
	],
	"edgy": [
		"don't stand so close. people will think we're friends.",
		"I nod. that's all you get.",
		"I was here first. spiritually.",
		"cool jetpack. I'm not impressed. but it's cool. I'm not impressed.",
	],
	"awkward": [
		"hi. hello. both. pick whichever.",
		"I saw you coming and rehearsed this. it went better alone.",
		"is this a conversation now? are we in one?",
		"you too. you didn't say anything yet. I know. you too.",
	],
}

## Insults: assembled fresh per outburst, same tech as the shirts --
## and FLAVORED by who's talking. The goofy insult you with a honk, the
## edgy insult you with the void, the grumpy file a complaint about it.
const INSULTS := {
	"generic": {
		"open": ["you", "listen here, you", "back off, you",
			"outta my face, you", "great. it's you. you", "keep walking, you",
			"and ANOTHER thing, you", "typical. absolutely typical, you"],
		"adj": ["rotten", "soggy", "unwashed", "expired", "second-hand",
			"government-issued", "lukewarm", "off-brand", "unseasoned",
			"clearance-rack", "microwaved", "decaf", "recalled", "bootleg",
			"store-brand", "unsalted", "refurbished", "gas-station"],
		"noun": ["noodle", "casserole", "footstool", "lasagna",
			"pigeon", "invoice", "haircut", "ladder", "doormat", "leftover",
			"trampoline", "sock puppet", "cabbage", "mannequin", "paperweight",
			"gazebo", "traffic cone", "participation trophy"],
	},
	"silly": {   # goofy / dumb: insults that honk
		"open": ["hey you", "honk honk, you", "wow. WOW. you",
			"breaking news: you're a", "beep beep, you", "ha! a"],
		"adj": ["wiggly", "bonk-headed", "goofy-smelling", "banana-shaped",
			"hooting", "upside-down", "boing-boing", "fart-adjacent"],
		"noun": ["goober", "dingus", "wiggle machine", "honk factory",
			"clown shoe", "noodle horn", "gigglesnort", "bumble"],
	},
	"dark": {   # edgy: insults from the abyss (the discount one)
		"open": ["the void called. even IT said you're a",
			"I've seen darkness. nothing like you, you", "begone, you",
			"pathetic. a", "you're nothing. a", "witness yourself, you"],
		"adj": ["hollow", "sunless", "doomed", "forgettable", "gray little",
			"cursed", "soulless", "abandoned"],
		"noun": ["husk", "shadow of a doormat", "candle nobody lit",
			"footnote", "puddle", "echo", "discount abyss", "wilted mall goth"],
	},
	"grump": {   # grumpy: complaints with a target
		"open": ["get off my dirt, you", "typical. ANOTHER",
			"back in line, you", "I'm filing a complaint about you, you",
			"in MY day you'd be FINED, you", "unbelievable. a"],
		"adj": ["lazy", "loud", "no-good", "trespassing", "freeloading",
			"disrespectful", "loitering", "modern"],
		"noun": ["whippersnapper", "porch pest", "lawn hazard",
			"noise machine", "tax dodger", "nuisance", "hooligan",
			"disappointment"],
	},
	"awkward": {   # awkward: insults with an exit ramp
		"open": ["you, um,", "ok here goes: you", "not to be rude but you're a",
			"you -- and I'm saying this --", "this is hard for me. you're a"],
		"adj": ["sort of terrible", "kind of unfortunate", "objectively iffy",
			"mildly upsetting", "vaguely damp", "regrettable"],
		"noun": ["person. sorry. no I'm not.", "situation, honestly.",
			"choice somebody made.", "whole thing.", "lot to process.",
			"misunderstanding."],
	},
	"smug": {   # confident: insults from above
		"open": ["bless your heart, you", "adorable. a real",
			"imagine being a", "I'd explain, but you're a",
			"stay down there, you"],
		"adj": ["bargain-bin", "entry-level", "unremarkable", "beta-tier",
			"aspiring", "budget"],
		"noun": ["understudy", "background character", "rough draft",
			"opening act", "participation ribbon", "before picture"],
	},
	"dreamy": {   # dreamy: tries to insult. cannot. hasn't got it in them.
		"open": ["grr. you", "take THIS: you're a", "I'm mad at you. you",
			"the meanest thing I know: you're a", "and furthermore, you're a"],
		"adj": ["slightly rude", "somewhat cloudy", "not very sparkly",
			"a bit much", "un-twinkly", "rude-ish"],
		"noun": ["cloud", "flower. a rude flower.", "star that shows up late",
			"breeze. a RUDE breeze.", "moonbeam. not the good kind.",
			"raindrop out of order"],
	},
	"anxious": {   # anxious: insults delivered mid-spiral
		"open": ["oh no. oh no no. you're a", "sorry in advance, you",
			"I can't believe I'm saying this: you", "deep breath. you're a",
			"this is going to be a whole thing but you're a"],
		"adj": ["stress-inducing", "alarming", "deeply concerning",
			"heart-rate-raising", "menacing", "unsettling"],
		"noun": ["fire drill", "pop quiz", "unread message", "loose stair",
			"surprise meeting", "ticking sound"],
	},
}

## Compliments: also assembled. Sincerity statistically present.
const NICE_OPEN := ["you know,", "hey,", "for the record,",
	"not to be weird, but", "I've been meaning to say:",
	"somebody had to tell you:", "real talk:", "and I mean this:",
	"don't let it go to your head, but", "the committee agrees:",
	"I told the rocks about you.", "in this economy?"]
const NICE_BIT := ["your shirt is doing great work.",
	"you have excellent standing posture.",
	"the planet is better with you on it. slightly. but measurably.",
	"your hair chose greatness.",
	"you seem like you'd survive things.",
	"you walk like someone with a plan. I respect the lie.",
	"good face. solid face placement.",
	"if I had a lawn, you could stand on it.",
	"you've got the second-best elbows in this city.",
	"gravity works extra hard to keep you around. flattering.",
	"you make standing still look like a career.",
	"your nametag suits you. few can say that.",
	"whatever you're doing with your arms: keep it up.",
	"I'd share a bench with you. that's the highest tier.",
	"the sun checks on you specifically. I've seen it.",
	"you smell like someone with savings."]

## Small talk: an opener, a topic, a take. The economy of it all.
const ST_OPEN := ["been thinking about", "big week for", "can we talk about",
	"I have opinions on", "heard rumors about", "not to alarm you, but:",
	"my neighbor won't shut up about", "the situation with"]
const ST_TOPIC := ["the weather", "taxes", "the blue dude",
	"the eye in the sky", "soup", "gravity", "the moon", "rocks",
	"the economy", "shirts", "napping", "the horizon", "geese",
	"the sun's schedule", "dirt prices"]
const ST_TAKE := ["it's a lot.", "not a fan.", "huge, honestly.",
	"I'm cautiously optimistic.", "somebody should do something.",
	"I stand by that.", "we live in times.", "could go either way.",
	"it knows what it did.", "I've said too much."]

## Getting insulted, for the non-retaliating: the sounds of absorbing
## it -- in your own voice. The grump files a complaint, the edgy adds
## it to the pile, the average just stand there and take it averagely.
const REACTS := {
	"generic": ["ok. wow. ok.", "I'm telling the sky eye.",
		"cool. cool cool cool. (not cool)",
		"my mother warned me about days like this.",
		"noted. hostile. noted.", "and I was having a DAY, too.",
		"wow. in front of the rocks and everything."],
	"silly": ["ha! ...wait.", "honk?? HONK.",
		"I don't get it. I'll laugh anyway. ha. HA.",
		"that's the meanest thing I've half-understood.",
		"my feelings! the little ones!"],
	"dark": ["whatever. pain is my roommate.",
		"I've been called worse by the mirror.",
		"cool. adding it to the pile.",
		"the abyss takes notes. so do I.",
		"you can't hurt what's already hollow."],
	"grump": ["THAT'S IT. that's going in the complaint.",
		"I've been insulted by BETTER.",
		"back in MY day insults had CRAFT.",
		"get off my planet.", "unbelievable. UNBELIEVABLE."],
	"awkward": ["ok. cool. I'm going to think about this for nine years.",
		"ha ha. yes. anyway. bye. no wait--",
		"I had a comeback. it's gone.",
		"you too. NO. wait.", "I'm going to stand somewhere else now."],
	"smug": ["bold words from a background character.",
		"I've decided that didn't happen.",
		"jealousy is a disease. get well soon.",
		"noted. dismissed.", "and yet I'm still the best one here."],
	"dreamy": ["oh. that's... a rain cloud of a thing to say.",
		"the wind will carry that away. eventually.",
		"I forgive you. the sky told me to.",
		"words are just air with opinions.",
		"that made my aura flicker."],
	"anxious": ["ok. OK. this is fine. is this fine??",
		"did everyone hear that? everyone heard that.",
		"I need to sit down. there's nowhere to sit.",
		"adding this to the 3am archive.",
		"my heart rate just filed a complaint."],
}

## Battle cries, in your own voice. Rallying the gang against the blue
## dude sounds different from a grump than from a spacecase.
const RALLY := {
	"generic": ["GET THE BLUE DUDE.", "that's IT. everyone, on him.",
		"blue dude. now. all of us.", "he's had this coming. LET'S GO."],
	"silly": ["GET HIM GET HIM GET HIM. wheee.",
		"DOGPILE ON THE BLUE DUDE.", "honk of WAR. c'mon!",
		"everybody bonk the blue guy!"],
	"dark": ["the void wants him. let's deliver.",
		"tonight the blue dude learns what I know.",
		"end him. quietly. loudly. whatever."],
	"grump": ["THAT'S IT. off my planet, blue dude. BOYS.",
		"I filed the complaint. now we file HIM.",
		"he's loitering. PERMANENTLY. get him."],
	"awkward": ["um. everyone? violence time. sorry. GET HIM.",
		"ok so. group thing. against him. now-ish.",
		"I called some people. this is the people. um. GO."],
	"smug": ["remove him. I'd do it myself but I have people.",
		"the blue era ends today. after you.",
		"he touched greatness. now greatness touches BACK."],
	"dreamy": ["the sky says it's time. sorry, blue one.",
		"friends... assemble. gently. then not gently.",
		"the universe asked for this. probably."],
	"anxious": ["ok ok ok NOW. before I rethink it. GET HIM.",
		"everyone at once so he can't pick ME.",
		"I can't do confrontation alone. GROUP confrontation."],
}

## How the smear gets phrased. The %s %s is filled from the speaker's
## own insult dialect, so grumps spread grump slander.
const GOSSIP := ["the blue dude is a %s %s. pass it on.",
	"heard about the blue dude? total %s %s.",
	"between us: the blue dude? %s %s.",
	"warn the others. the blue dude is a %s %s."]

## The card behind the words: rounded corners, billboarded, fades with
## the thought. This is what makes a speech bubble a BUBBLE.
const BUBBLE_SHADER := "
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled;
uniform vec4 col : source_color = vec4(0.07, 0.07, 0.1, 0.85);
uniform float alpha = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 uv = abs(UV - 0.5) * 2.0;
	float r = 0.35;
	vec2 q = max(uv - (1.0 - r), vec2(0.0));
	float d = length(q) / r;
	ALBEDO = col.rgb;
	ALPHA = col.a * alpha * (1.0 - smoothstep(0.8, 1.0, d));
}"

## The face pool: PNGs drawn in the dev editor (F9). Loaded once,
## reloaded when the editor saves or deletes.
static var _faces: Array = []
static var _faces_loaded := false

static func reload_faces() -> void:
	_faces.clear()
	_faces_loaded = true
	var d := DirAccess.open("user://human_faces")
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".png"):
			var img := Image.new()
			if img.load("user://human_faces/" + f) == OK:
				# sidecar json carries the face's personality weights
				var pers := {}
				var jp := "user://human_faces/" + f.trim_suffix(".png") + ".json"
				if FileAccess.file_exists(jp):
					var parsed = JSON.parse_string(FileAccess.get_file_as_string(jp))
					if parsed is Dictionary:
						pers = parsed
				_faces.append({"tex": ImageTexture.create_from_image(img),
					"pers": pers, "file": f})

## A face AND its soul: {tex, pers} -- or {} when humanity has no faces yet.
static func random_face() -> Dictionary:
	if not _faces_loaded:
		reload_faces()
	if _faces.is_empty():
		return {}
	return _faces[randi() % _faces.size()]

## The exact face back, by filename -- cage releases keep their face.
static func face_by_file(f: String) -> Dictionary:
	if not _faces_loaded:
		reload_faces()
	for fc in _faces:
		if str(fc.get("file", "")) == f:
			return fc
	return {}

var _home = null            # Universe body we live on
var _pers: Dictionary = {}  # axis -> 0..100, from the face's sidecar
var _body: Human
var _dir: Vector3 = Vector3.ZERO
var _act: String = "wander"
var _act_t: float = 0.0
var _panic_t: float = 0.0
var _karen_t: float = 15.0   # time until the next tiny problem
var _bubble: Label3D
var _bubble_t: float = 0.0
var _bg: MeshInstance3D          # the bubble card behind the words
var _bg_mesh: QuadMesh
var _bg_mat: ShaderMaterial
var _ptalk_t: float = 0.0        # player pressed F recently: we're TALKING here
var _voice: Dictionary = {}      # tone-TTS profile: pitch, spread, waveform, speed
var _vp: AudioStreamPlayer3D = null   # the currently-playing voice
var _grounded: bool = false
var _fly_t: float = 0.0     # airborne grace before the slam-down

var human_name: String = ""
var human_id: int = 0           # code-facing. never shown. humans don't know
var _tag: Label3D
var _opinion: Dictionary = {}   # human_id -> -100..100. the social ledger
var _partner: EarthHuman = null
var _convo_wait: float = 999.0  # time until my next line
var _convo_left: int = 0        # lines I still intend to say
var _heard: String = ""         # kind of the last line said at me
var _social_cd: float = 0.0     # cooldown between human-to-human chats
var _greet_cd: float = 0.0      # cooldown between greeting the player
var _scan_t: float = 0.0        # staggered social scan timer (cheap, not laggy)
var _lod_t: float = 0.0         # observer check timer
var _stuck_t: float = 0.0       # walking but going nowhere (chest in face)
var _last_pos: Vector3 = Vector3.ZERO
var _detour_t: float = 0.0      # sidestep override while pathing around things
var _detour: Vector3 = Vector3.ZERO
var _detour_side: float = 1.0   # which way we last dodged
var _redetour_t: float = 0.0    # >0 = last dodge was recent; stuck again = flip
var _active: bool = true        # false = player far away, human unrendered by reality

var hp: float = 30.0
var _dead: bool = false
var _seat: Node3D = null        # the bench spot this human has claimed
var _friend: EarthHuman = null  # current hangout buddy
var _hunt_t: float = 0.0        # ganging up on the blue dude
var _swing_cd: float = 0.0      # time between punches
var _target: EarthHuman = null  # street-fight opponent
var _fight_t: float = 0.0       # fight time remaining
var _phase_t: float = 0.0       # approach/evade phase timer
var _evading: bool = false      # backing off between swings
var _gossip_cd: float = 0.0     # cooldown on bad-mouthing the blue dude
var _los_t: float = 0.0         # sight-check throttle while hunting
var _lost_t: float = 0.0        # how long the prey has been out of sight

const FOOD_HEAL := {"cooked_meat": 10.0, "salad": 8.0, "meat": 6.0,
	"shroom": 5.0, "banana": 4.0}

var inv: Dictionary = {}        # pockets: id -> count. finders keepers.
var _eat_cd: float = 0.0

var age: float = 0.0            # seconds LIVED (only ticks near the player)
var lifespan: float = 1e9       # rolled at birth. nobody checks the number.

var chipped: bool = false       # neuralink chip in the head. unaware.
var minded: bool = false        # actively driven from a terminal
var mind_dir: Vector3 = Vector3.ZERO   # the chip's strafe/walk input
var mind_turn: float = 0.0             # the chip's turn input (rad/s)

var home_city: int = -1         # index into Game.earth_cities. -2 = rural
var my_house = null             # claimed town house (House)
var _goal_house = null          # house being walked to right now
var flat_house = null           # inside a house: flat gravity, cozy
var _house_t: float = 0.0       # time left indoors
var _leg: int = -1              # next rail stop on the current journey
var _moved: bool = false        # already relocated once: settled now
var _travel_to: int = -1        # riding the rail toward this city
var _away_t: float = 0.0        # visiting: time left before homesickness
var _apple: ItemDrop = null     # a spotted permadeath apple. destiny.
var _eat_t: float = 0.0         # chewing countdown. after this, physics

## Cage tech: every random choice that makes this human THIS human is
## recorded here as it's rolled (JSON-safe: hex colors, plain numbers).
## Set it before add_child and the exact same person walks back out --
## name, face, shirt, grudges, all of it.
var saved: Dictionary = {}

## Roll-or-restore: first life rolls the dice and writes them down;
## a released cage human just reads their old answers back.
func _rv(k: String, v):
	if not saved.has(k):
		saved[k] = v
	return saved[k]

func setup(home_body) -> void:
	_home = home_body

static func _v3(a) -> Vector3:
	if a is Array and a.size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ONE

## Everything that makes this human THIS human, boxed for the cage:
## looks (already in `saved`) plus the live state -- name, personality,
## health, and every grudge in the ledger.
func capture() -> Dictionary:
	saved["name"] = human_name
	saved["id"] = human_id
	saved["pers"] = _pers.duplicate()
	saved["op"] = _opinion.duplicate()
	saved["hp"] = hp
	saved["home_city"] = home_city
	saved["moved"] = _moved
	saved["chip"] = chipped
	saved["age"] = age
	saved["life"] = lifespan
	saved["inv"] = inv.duplicate()
	return saved.duplicate()

func _ready() -> void:
	add_to_group("earth_human")
	floor_snap_length = 1.6   # hug the sphere: no curvature hop
	if not saved.has("name"):
		# prefer a name nobody nearby is wearing: draw a few times and
		# keep the first free one (there are only so many Kevins)
		var taken := {}
		for other in get_tree().get_nodes_in_group("earth_human"):
			if other is EarthHuman and other != self:
				taken[other.human_name] = true
		var pick: String = NAMES[randi() % NAMES.size()]
		for attempt in 6:
			if not taken.has(pick):
				break
			pick = NAMES[randi() % NAMES.size()]
		saved["name"] = pick
	human_name = str(_rv("name", NAMES[randi() % NAMES.size()]))
	human_id = int(_rv("id", randi()))
	hp = float(_rv("hp", 30.0))
	age = float(_rv("age", randf_range(0.0, 5000.0)))
	# a LONG life, measured in rendered seconds: many, many sessions
	lifespan = float(_rv("life", randf_range(30000.0, 70000.0)))
	# grudges survive the cage. JSON turns int keys into strings; turn
	# them back or every old enemy becomes a stranger
	home_city = int(saved.get("home_city", -1))
	_moved = bool(saved.get("moved", false))
	chipped = bool(saved.get("chip", false))
	var rinv = saved.get("inv", {})
	if rinv is Dictionary:
		for k2 in rinv:
			inv[str(k2)] = int(rinv[k2])
	if chipped:
		call_deferred("add_chip_visual")
	var rop: Dictionary = saved.get("op", {})
	for k in rop:
		_opinion[int(k)] = float(rop[k])
	# stagger the social clocks so a fresh city doesn't erupt into one
	# giant simultaneous conversation (also: cheaper)
	_social_cd = randf_range(4.0, 25.0)
	_greet_cd = randf_range(0.0, 6.0)
	_scan_t = randf_range(0.0, 0.9)
	_lod_t = randf_range(0.0, 0.5)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.8
	cap.radius = 0.35
	col.shape = cap
	add_child(col)

	_body = Human.new()
	_body.position = Vector3(0, -0.9, 0)
	add_child(_body)
	# actual human skin tones, the full range -- pale to deep brown
	var skin := Color(str(_rv("skin", Color.from_hsv(randf_range(0.05, 0.09),
		randf_range(0.25, 0.55), randf_range(0.35, 0.95)).to_html())))
	# a random face from the hand-drawn pool -- and its PERSONALITY.
	# the face IS the soul: its editor-set weights shape thought and deed.
	var fc: Dictionary
	if saved.has("face"):
		fc = EarthHuman.face_by_file(str(saved["face"]))
	else:
		fc = EarthHuman.random_face()
		saved["face"] = str(fc.get("file", ""))
	_body.build(skin, "none", fc.get("tex", null))
	if saved.has("pers"):
		var rp: Dictionary = saved["pers"]
		for ax in AXES:
			_pers[ax] = float(rp.get(ax, 25.0))
	else:
		# roll WHO they are first (archetype), then roll the axes inside
		# its ranges. the face still tilts the result 50/50 where the
		# editor set a value -- but nobody is eight dice in a trenchcoat.
		var arch: Dictionary = ARCHETYPES[randi() % ARCHETYPES.size()]
		var fp = fc.get("pers", {})
		for ax in AXES:
			var rng: Array = arch.get(ax, [5.0, 30.0])
			var av := randf_range(float(rng[0]), float(rng[1]))
			_pers[ax] = (av + float(fp[ax])) * 0.5 if fp.has(ax) else av
		# and some humans are STILL not well-rounded on top of all that.
		if randf() < 0.25:
			var spike: String = AXES[randi() % AXES.size()]
			_pers[spike] = maxf(float(_pers[spike]), randf_range(75.0, 100.0))
		saved["pers"] = _pers
	# Karens: born, not made. named, actually. the manager will be
	# hearing about all of this.
	if human_name == "Karen":
		_pers["grumpy"] = maxf(float(_pers.get("grumpy", 25.0)), 78.0)
		_pers["confident"] = maxf(float(_pers.get("confident", 25.0)), 85.0)
		_pers["goofy"] = minf(float(_pers.get("goofy", 25.0)), 15.0)
	# proportions: RANDOMIZED. most humans look normal. some rolled badly
	# at the character screen of life and are living with it.
	_body.scale = _v3(_rv("bscale", [randf_range(0.92, 1.04),
		randf_range(0.85, 1.05), randf_range(0.92, 1.04)]))
	if _rv("odd", randf() < 0.3):
		if _rv("belly", randf() < 0.6) and is_instance_valid(_body._torso):
			_body._torso.scale = _v3(_rv("tscale", [randf_range(1.1, 1.35),
				1.0, randf_range(1.1, 1.45)]))   # the belly
		if _rv("bighead", randf() < 0.5) and is_instance_valid(_body._head_m):
			_body._head_m.scale = Vector3.ONE * float(_rv("hscale", randf_range(1.15, 1.5)))
		if _rv("slouch", randf() < 0.5):
			_body.rotation_degrees.x = float(_rv("slouchx", randf_range(3.0, 8.0)))
		if _rv("squat", randf() < 0.4):
			_body.scale.y *= float(_rv("squaty", randf_range(0.72, 0.85)))
	_dress_human()
	_voice = _build_voice()

	_bubble = Label3D.new()
	_bubble.font_size = 22
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.position = Vector3(0, 2.65, 0)
	_bubble.modulate = Color(1, 1, 1, 0.0)
	_bubble.outline_modulate = Color(0, 0, 0, 0.0)
	_bubble.outline_size = 8
	_bubble.width = 420
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# draws over everything -- a thought should never be trapped
	# behind the head that had it
	_bubble.no_depth_test = true
	_bubble.render_priority = 10
	add_child(_bubble)

	# the bubble PART of the speech bubble: rounded dark card behind the
	# words, billboarded, sized to fit whatever gets said
	_bg = MeshInstance3D.new()
	_bg_mesh = QuadMesh.new()
	_bg_mesh.size = Vector2(0.5, 0.3)
	_bg.mesh = _bg_mesh
	_bg.position = Vector3(0, 2.65, 0)
	_bg_mat = ShaderMaterial.new()
	var bsh := Shader.new()
	bsh.code = BUBBLE_SHADER
	_bg_mat.shader = bsh
	_bg_mat.set_shader_parameter("alpha", 0.0)
	_bg_mat.render_priority = 9   # always UNDER the words, never over
	_bg.material_override = _bg_mat
	_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the vertex shader billboards the quad OUT of its original AABB;
	# without a cull margin the engine clips it whenever the body isn't
	# facing the camera -- which looked like 'most bubbles have no card'
	_bg.extra_cull_margin = 6.0
	add_child(_bg)

	# nametag: ALWAYS above the head, clear of the biggest skulls and
	# the tallest rolls on the proportions table
	_tag = Label3D.new()
	_tag.text = human_name
	_tag.font_size = 13
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.position = Vector3(0, 2.1, 0)
	_tag.outline_size = 6
	_tag.modulate = Color(1, 1, 1, 0.85)
	_tag.no_depth_test = true
	_tag.render_priority = 9
	add_child(_tag)

	_pick_act()

## Wardrobe: random t-shirt + pants + hair. Shirts come plain, with a
## "design", or with an assembled slogan. All of it committee-approved
## by no committee.
func _dress_human() -> void:
	var shirt_col := Color(str(_rv("shirt_col", Color.from_hsv(randf(),
		randf_range(0.4, 0.9), randf_range(0.35, 0.95)).to_html())))
	var pants_col := Color(str(_rv("pants_col", [Color("#2b3a5e"),
		Color("#1e1e24"), Color("#4a3a28"), Color("#3a4a3a"),
		Color("#6e6e74"), Color("#5e2b2b")][randi() % 6].to_html())))
	# t-shirt: torso + sleeves. pants: legs.
	var shirt_mat := Destructible.make_material(shirt_col, 0.1)
	if is_instance_valid(_body._torso):
		_body._torso.material_override = shirt_mat
	for arm in [_body._arm_l, _body._arm_r]:
		if is_instance_valid(arm):
			arm.material_override = shirt_mat
	var pants_mat := Destructible.make_material(pants_col, 0.05)
	for leg in [_body._leg_l, _body._leg_r]:
		if is_instance_valid(leg):
			leg.material_override = pants_mat

	# the front of the shirt: plain / weird design / slogan
	var roll := float(_rv("shirt_roll", randf()))
	if roll < 0.05:
		pass   # basic. a classic. says nothing, means nothing.
	elif roll < 0.15 and is_instance_valid(_body._torso):
		# "design": abstract shapes a machine thought were fashion
		for i in randi_range(2, 4):
			var shp := MeshInstance3D.new()
			if randf() < 0.5:
				var bm := BoxMesh.new()
				bm.size = Vector3(randf_range(0.1, 0.3), randf_range(0.05, 0.25), 0.03)
				shp.mesh = bm
			else:
				var smm := SphereMesh.new()
				smm.radius = randf_range(0.05, 0.13)
				smm.height = smm.radius * 2.0
				shp.mesh = smm
			shp.position = Vector3(randf_range(-0.25, 0.25),
				randf_range(-0.3, 0.35), -0.24)
			shp.rotation_degrees.z = randf_range(0, 180)
			shp.material_override = Destructible.make_material(
				Color.from_hsv(randf(), randf_range(0.5, 1.0), randf_range(0.5, 1.0)), 0.3)
			_body._torso.add_child(shp)
	elif is_instance_valid(_body._torso):
		# the slogan shirt: assembled, unreviewed, worn with confidence
		var words: String = SHIRT_A[randi() % SHIRT_A.size()]
		if randf() < 0.6:
			words += " " + SHIRT_B[randi() % SHIRT_B.size()]
		words += " " + SHIRT_C[randi() % SHIRT_C.size()]
		words = str(_rv("slogan", words))   # a caged human keeps the shirt
		var slogan := Label3D.new()
		slogan.text = words
		slogan.font_size = 34
		slogan.pixel_size = 0.004
		slogan.width = 200.0
		slogan.autowrap_mode = TextServer.AUTOWRAP_WORD
		slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slogan.modulate = Color.WHITE if shirt_col.get_luminance() < 0.5 else Color("#1a1a1a")
		slogan.position = Vector3(0, 0.05, -0.3)
		# empirically (screenshot-tested): rotated 180, double-sided on,
		# the text reads correctly from the chest side. don't theorize.
		slogan.rotation_degrees.y = 180.0
		_body._torso.add_child(slogan)

	# hair: one style from the rack, one colour from the bottle
	if not is_instance_valid(_body._head_m):
		return
	var hair_col := Color(str(_rv("hair_col", [Color("#1a1410"),
		Color("#4a3018"), Color("#c8a050"), Color("#8a3a1a"),
		Color("#b8b8bc"), Color("#d84aa0")][
		randi() % 6 if randf() > 0.05 else 5].to_html())))   # 5% dyed pink, as is right
	var hmat := Destructible.make_material(hair_col, 0.05)
	match int(_rv("hair", randi() % 6)):
		0:
			pass   # bald. aerodynamic. honest.
		1:   # flat cap of hair
			var h1 := BoxMesh.new()
			h1.size = Vector3(0.6, 0.14, 0.6)
			_hair(h1, Vector3(0, 0.32, 0), hmat)
		2:   # bowl cut
			var h2 := SphereMesh.new()
			h2.radius = 0.36
			h2.height = 0.4
			h2.is_hemisphere = true
			_hair(h2, Vector3(0, 0.16, 0), hmat)
		3:   # spikes
			for sx in [-0.15, 0.0, 0.15]:
				var h3 := CylinderMesh.new()
				h3.top_radius = 0.0
				h3.bottom_radius = 0.07
				h3.height = 0.22
				_hair(h3, Vector3(sx, 0.36, 0), hmat)
		4:   # mohawk
			var h4 := BoxMesh.new()
			h4.size = Vector3(0.1, 0.24, 0.62)
			_hair(h4, Vector3(0, 0.36, 0), hmat)
		5:   # side swoop
			var h5 := BoxMesh.new()
			h5.size = Vector3(0.62, 0.12, 0.6)
			var sw := _hair(h5, Vector3(0.1, 0.32, 0), hmat)
			sw.rotation_degrees.z = -12.0

func _hair(mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	_body._head_m.add_child(mi)
	return mi

func _pick_act() -> void:
	_release_seat()
	# a free seat nearby? sometimes a human just SITS. peak behavior.
	if randf() < 0.22:
		var best: Node3D = null
		var bd := 900.0   # 30m, squared
		for s in get_tree().get_nodes_in_group("seat"):
			if bool(s.get_meta("taken", false)):
				continue
			var sd := global_position.distance_squared_to(s.global_position)
			if sd < bd:
				bd = sd
				best = s
		if best != null:
			best.set_meta("taken", true)
			_seat = best
			_act = "goseat"
			_act_t = 25.0   # time to get there before giving up
			var up_s := _up()
			var to_s: Vector3 = best.global_position - global_position
			_dir = (to_s - up_s * to_s.dot(up_s)).normalized()
			return
	# city life: home leash and the occasional rail trip. dreamers and
	# goofballs wander more; everyone comes home eventually.
	if _home == Game.earth_body and not Game.earth_cities.is_empty() \
			and flat_house == null:
		if home_city == -1:
			home_city = _nearest_city()
		if home_city >= 0 and _travel_to < 0 and _away_t <= 0.0:
			var wl := 0.02 + float(_pers.get("dreamy", 25.0)) * 0.0008 \
				+ float(_pers.get("goofy", 25.0)) * 0.0004
			if randf() < wl:
				var other := randi() % Game.earth_cities.size()
				if other != home_city:
					_travel_to = other
					_away_t = randf_range(45.0, 90.0)
					return
			# drifted out of town with no trip planned: head home
			var cur3: Vector3 = (global_position - _home.center).normalized()
			var hd: Vector3 = Game.earth_cities[home_city]["dir"]
			if cur3.angle_to(hd) * float(_home.radius) > 55.0:
				_travel_to = home_city
				return
	# home life: claim an empty town house, visit yours sometimes,
	# and sometimes bring a friend over to talk about things
	if flat_house == null and _home == Game.earth_body:
		if my_house != null and not is_instance_valid(my_house):
			my_house = null
		if my_house == null and randf() < 0.2:
			for hn in get_tree().get_nodes_in_group("house"):
				if hn is House and hn.human_home and hn.owner_uid == human_id:
					my_house = hn
					break
			# roommates: a good enough friend with a place beats
			# house-hunting. rent is emotional support
			if my_house == null:
				var fr4 := _best_friend(150.0)
				if fr4 != null and fr4.my_house != null \
						and is_instance_valid(fr4.my_house) \
						and fr4.my_house.roommate_name == "" \
						and fr4.my_house.owner_uid != 0 \
						and _op(fr4.human_id) > 55.0:
					my_house = fr4.my_house
					my_house.roommate_name = human_name
					my_house.refresh_tag()
			if my_house == null:
				var bhd := 3600.0
				var cand = null
				for hn2 in get_tree().get_nodes_in_group("house"):
					if hn2 is House and hn2.human_home and hn2.owner_uid == 0:
						var hdd := global_position.distance_squared_to(hn2.global_position)
						if hdd < bhd:
							bhd = hdd
							cand = hn2
				if cand != null:
					my_house = cand
					my_house.owner_uid = human_id
					my_house.owner_name = human_name
					my_house.refresh_tag()
					my_house.furnish_for(_pers)
		if my_house != null and randf() < 0.08:
			_goal_house = my_house
			_act = "gohouse"
			_act_t = 40.0
			return
	# a good friend somewhere out there? go stand with them. friends
	# drift apart and find each other again. nobody knows how they know.
	if randf() < 0.18:
		var fr := _best_friend(120.0)
		if fr != null:
			_friend = fr
			_act = "friend"
			_act_t = randf_range(10.0, 22.0)
			return
	# personality leaks into behaviour: dreamers stare, the dumb spin,
	# the confident follow you around, the anxious keep moving
	var w := {
		"wander": 1.0 + float(_pers.get("anxious", 25)) * 0.01 \
			+ float(_pers.get("awkward", 25)) * 0.008,
		"stare": 0.8 + float(_pers.get("dreamy", 25)) * 0.02 \
			+ float(_pers.get("edgy", 25)) * 0.012,
		"circle": 0.8 + float(_pers.get("dumb", 25)) * 0.012 \
			+ float(_pers.get("edgy", 25)) * 0.006,
		"spin": 0.4 + float(_pers.get("dumb", 25)) * 0.02 \
			+ float(_pers.get("goofy", 25)) * 0.022,
		"follow": 0.6 + float(_pers.get("confident", 25)) * 0.02 \
			+ float(_pers.get("goofy", 25)) * 0.01 \
			- float(_pers.get("grumpy", 25)) * 0.008 \
			- float(_pers.get("edgy", 25)) * 0.01 \
			- float(_pers.get("awkward", 25)) * 0.012,
	}
	var total := 0.0
	for k in w:
		w[k] = maxf(0.05, w[k])
		total += w[k]
	var roll := randf() * total
	_act = "wander"
	for k in w:
		roll -= w[k]
		if roll <= 0.0:
			_act = k
			break
	_act_t = randf_range(2.5, 7.0)
	var up := _up()
	var tang := up.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)))
	_dir = tang.normalized() if tang.length() > 0.01 else Vector3.ZERO

func _up() -> Vector3:
	if flat_house != null or _home == null:
		return Vector3.UP
	return (global_position - _home.center).normalized()

## Every soul gets a voicebox. Pitch dice come from the id; everything
## else comes from who they are. Monotone for the dumb, the grumpy and
## the edgy. Square-wave nerd voice for the anxious and awkward. Wobble
## for the weird. And the mosquito face buzzes. Obviously.
func _build_voice() -> Dictionary:
	var h := absi(human_id)
	var base := 240.0 + float(h % 200)
	base += float(_pers.get("goofy", 25.0)) * 0.9 + float(_pers.get("anxious", 25.0)) * 0.6
	base -= float(_pers.get("grumpy", 25.0)) * 0.9 + float(_pers.get("edgy", 25.0)) * 0.6
	base = clampf(base, 120.0, 520.0)
	var mono := maxf(float(_pers.get("dumb", 25.0)),
		maxf(float(_pers.get("grumpy", 25.0)), float(_pers.get("edgy", 25.0))))
	var vary := 0.08 if mono > 60.0 else 0.35 + float(_pers.get("dreamy", 25.0)) * 0.004
	var wave := "sine"
	if str(saved.get("face", "")).begins_with("face_017"):
		wave = "buzz"
	elif maxf(float(_pers.get("awkward", 25.0)), float(_pers.get("anxious", 25.0))) > 60.0:
		wave = "square"
	elif maxf(float(_pers.get("grumpy", 25.0)), float(_pers.get("edgy", 25.0))) > 60.0:
		wave = "saw"
	elif float(_pers.get("goofy", 25.0)) > 60.0 or h % 10 == 0:
		wave = "wobble"
	var rate := 1.0
	rate -= float(_pers.get("goofy", 25.0)) * 0.002 + float(_pers.get("anxious", 25.0)) * 0.002
	rate += float(_pers.get("dreamy", 25.0)) * 0.003 + float(_pers.get("dumb", 25.0)) * 0.002
	# articulation: some humans PUNCH their consonants. the confident
	# enunciate at you; nerd voices over-pronounce; a scatter of others
	# just talk like every S is load-bearing
	var artic := 1.0 + float(h % 7) * 0.09
	if wave == "square" or float(_pers.get("confident", 25.0)) > 60.0:
		artic += 0.35
	return {"base": base, "var": vary, "wave": wave,
		"rate": clampf(rate, 0.6, 1.5), "artic": clampf(artic, 1.0, 1.8)}

## Vacate the seat (if any) and get back on official standing business.
func _release_seat() -> void:
	if _seat != null and is_instance_valid(_seat):
		_seat.set_meta("taken", false)
	_seat = null
	if _body:
		_body.pose = 0
	if _act == "sit" or _act == "goseat":
		_act = "wander"

## F: ask what's on their mind. WHICH mind depends on the face.
func use() -> void:
	# weighted draw: each axis pool weighted by the face's value for it,
	# neutral always in the running so nobody is a caricature 100% of
	# the time
	var pools := {"neutral": 35.0}
	for ax in AXES:
		pools[ax] = float(_pers.get(ax, 25.0))
	var total := 0.0
	for k in pools:
		total += pools[k]
	var roll := randf() * total
	var chosen := "neutral"
	for k in pools:
		roll -= pools[k]
		if roll <= 0.0:
			chosen = k
			break
	var lines: Array = THOUGHTS[chosen]
	_say(lines[randi() % lines.size()])
	_ptalk_t = 6.0   # we are TALKING here. the neighbors can wait.
	Sfx.play("click", -20.0)

func take_damage(dmg: float, dir: Vector3) -> void:
	# violence: observably effective, emotionally complicated
	_release_seat()
	hp -= dmg
	if hp <= 0.0:
		_witness(-25.0)   # they all saw that. all of them.
		_die(dir)
		return
	_witness(-10.0)
	_end_convo()
	_op_add(-1, -25.0)   # id -1: the blue dude's page in the ledger
	_panic_t = 0.6 if _hunt_t > 0.0 else 5.0   # hunters shrug it off
	_dir = (dir - _up() * dir.dot(_up())).normalized()
	velocity += dir.normalized() * 6.0 + _up() * 3.0   # shoved, wailing
	# the mean ones go down swinging (verbally). the rest just wail.
	if float(_pers.get("grumpy", 25.0)) + float(_pers.get("edgy", 25.0)) > 90.0 \
			or randf() < 0.3:
		_say(_insult_line())
	else:
		_say("WHY")
	Sfx.play("hurt", -16.0)

## ---- the social brain: names, grudges, conversations ----

const KAREN_OPEN := ["excuse me,", "unbelievable.", "I'm sorry, but",
	"noted. NOTED.", "oh, we're doing THIS now?", "I counted, and"]
const KAREN_GENERIC := ["this grass is at two different heights.",
	"the sun is louder than yesterday.", "this air was fresher on tuesday.",
	"the horizon is crooked and nobody cares.",
	"these clouds are completely unsupervised.",
	"the gravity here feels off-brand.",
	"that rock has been there for DAYS.",
	"somebody's footsteps are still in this dirt.",
	"the railway hums in a tone I didn't agree to."]
const KAREN_BENCH := ["this bench faces the WRONG way.",
	"someone sat on this bench recently. it's still warm. unacceptable.",
	"this bench has four legs and uses all of them. show-off."]
const KAREN_HUMAN := ["%s is standing like that on PURPOSE.",
	"%s's shirt has energy I did not approve.",
	"%s breathed near my property line again."]

## Find the nearest tiny problem and file it verbally.
func _karen_complain() -> void:
	var line := ""
	var bench_near := false
	for bn in get_tree().get_nodes_in_group("bench"):
		if bn is Node3D and is_instance_valid(bn) \
				and global_position.distance_squared_to(bn.global_position) < 64.0:
			bench_near = true
			break
	var victim: EarthHuman = null
	for h in get_tree().get_nodes_in_group("earth_human"):
		if h != self and h is EarthHuman and is_instance_valid(h) and not h._dead \
				and global_position.distance_squared_to(h.global_position) < 64.0:
			victim = h
			break
	var roll := randf()
	if victim != null and roll < 0.4:
		line = KAREN_HUMAN[randi() % KAREN_HUMAN.size()] % victim.human_name
	elif bench_near and roll < 0.65:
		line = KAREN_BENCH[randi() % KAREN_BENCH.size()]
	else:
		line = KAREN_GENERIC[randi() % KAREN_GENERIC.size()]
	if randf() < 0.35:
		line += " the manager will hear about this."
	_say(KAREN_OPEN[randi() % KAREN_OPEN.size()] + " " + line)

func _say(t: String) -> void:
	_bubble.text = t
	# the experimental voice: beeped, not spoken. only within earshot,
	# and new words cut the old ones off mid-beep
	var plr = get_tree().get_first_node_in_group("player")
	if plr != null and global_position.distance_squared_to(plr.global_position) < 196.0:
		if _vp != null and is_instance_valid(_vp):
			_vp.queue_free()
		_vp = HumanVoice.speak(self, t, _voice)
	# words hang around until replaced, but not forever
	_bubble_t = 5.0
	# size the card to the words: rough glyph math, generous padding
	var px: float = t.length() * 11.0
	var w: float = clampf(px + 36.0, 90.0, 440.0)
	var lines: float = ceilf(px / 400.0)
	_bg_mesh.size = Vector2(w, lines * 29.0 + 20.0) * 0.005
	_bg_mat.set_shader_parameter("alpha", 1.0)   # card ON from word one

## The ledger. Positive = friend, negative = that guy. Nobody forgets.
func _op(id: int) -> float:
	return float(_opinion.get(id, 0.0))

func _op_add(id: int, d: float) -> void:
	var v := clampf(_op(id) + d, -100.0, 100.0)
	# friendship has a CAPACITY: about three real friends. past that,
	# no amount of compliments gets a stranger over the line -- they
	# park at 'very pleasant acquaintance' and the roster stays full.
	# hate has no such limit. hate scales beautifully.
	if d > 0.0 and v > 38.0 and _op(id) <= 38.0:
		var friends := 0
		for k in _opinion:
			if k != id and float(_opinion[k]) > 38.0:
				friends += 1
		if friends >= 3:
			v = 38.0
	_opinion[id] = v

## Which insult dialect you speak is who you are. Specialists (any axis
## past 50) insult in their own voice; everyone else gets the classics.
func _insult_flavor() -> String:
	var cand := {
		"silly": maxf(float(_pers.get("goofy", 25.0)), float(_pers.get("dumb", 25.0))),
		"dark": float(_pers.get("edgy", 25.0)),
		"grump": float(_pers.get("grumpy", 25.0)),
		"awkward": float(_pers.get("awkward", 25.0)),
		"smug": float(_pers.get("confident", 25.0)),
		"dreamy": float(_pers.get("dreamy", 25.0)),
		"anxious": float(_pers.get("anxious", 25.0)),
	}
	var best := "generic"
	var bv := 50.0
	for k in cand:
		if cand[k] > bv:
			bv = cand[k]
			best = k
	return best

func _rally_line() -> String:
	var pool: Array = RALLY[_insult_flavor()]
	return pool[randi() % pool.size()]

func _gossip_line() -> String:
	var f: Dictionary = INSULTS[_insult_flavor()]
	var adj: Array = f["adj"]
	var noun: Array = f["noun"]
	return GOSSIP[randi() % GOSSIP.size()] % [adj[randi() % adj.size()],
		noun[randi() % noun.size()]]

func _insult_line(target: String = "") -> String:
	var f: Dictionary = INSULTS[_insult_flavor()]
	var open: Array = f["open"]
	var adj: Array = f["adj"]
	var noun: Array = f["noun"]
	var l := "%s %s %s" % [open[randi() % open.size()],
		adj[randi() % adj.size()], noun[randi() % noun.size()]]
	if target != "" and randf() < 0.45:
		l = target + ". " + l
	return l

func _nice_line() -> String:
	return "%s %s" % [NICE_OPEN[randi() % NICE_OPEN.size()],
		NICE_BIT[randi() % NICE_BIT.size()]]

func _smalltalk_line() -> String:
	return "%s %s. %s" % [ST_OPEN[randi() % ST_OPEN.size()],
		ST_TOPIC[randi() % ST_TOPIC.size()],
		ST_TAKE[randi() % ST_TAKE.size()]]

## Greeting the player: pool picked by personality, same draw as thoughts.
func _social_line() -> String:
	var pools := {"neutral": 35.0}
	for ax in AXES:
		pools[ax] = float(_pers.get(ax, 25.0))
	var total := 0.0
	for k in pools:
		total += pools[k]
	var roll := randf() * total
	var chosen := "neutral"
	for k in pools:
		roll -= pools[k]
		if roll <= 0.0:
			chosen = k
			break
	if human_name == "Karen" and randf() < 0.35:
		return ["I need to speak to whoever MANAGES this planet.",
			"I know the noodle god PERSONALLY.",
			"this is unacceptable. all of it. everything.",
			"I will be leaving a review."][randi() % 4]
	var lines: Array = SOCIAL[chosen]
	var line: String = lines[randi() % lines.size()]
	return line.replace("{n}", human_name)

## Periodic look-around: is the player awkwardly close? is a chat-able
## human nearby? Squared distances, staggered timers -- cities stay cheap.
func _check_social() -> void:
	if _target != null or _hunt_t > 0.0:
		return   # busy. VERY busy.
	# a permadeath apple on the ground outranks every social plan
	if _apple == null and _eat_t <= 0.0:
		for d in get_tree().get_nodes_in_group("itemdrop"):
			if d is ItemDrop and d.id == "permapple" \
					and global_position.distance_squared_to(d.global_position) < 196.0:
				_apple = d
				_end_convo()
				return
	# magpie module: loose items within reach get pocketed. food
	# always; shiny things sometimes. the drop's grace is respected --
	# scavengers, not pickpockets
	if _inv_count() < 8:
		for dp in get_tree().get_nodes_in_group("itemdrop"):
			if dp is ItemDrop and is_instance_valid(dp) and dp._t > 4.0 \
					and global_position.distance_squared_to(dp.global_position) < 12.25:
				# ANYTHING within reach gets pocketed in passing -- raw
				# meat, coal, whatever. Course unchanged: they pocket it
				# and keep walking to wherever they were going.
				inv[dp.id] = int(inv.get(dp.id, 0)) + 1
				dp.count -= 1
				if dp.count <= 0:
					dp.queue_free()
				Sfx.play("click", -26.0)
				break
	if _partner != null:
		return
	# standing with a cross-city friend: sometimes the Conversation
	if _act == "friend" and _friend != null and is_instance_valid(_friend) \
			and global_position.distance_squared_to(_friend.global_position) < 9.0 \
			and randf() < 0.15:
		_maybe_negotiate_move()
	var p = get_tree().get_first_node_in_group("player")
	# the rally: hate the blue dude ENOUGH and you call your best
	# friends -- everyone who already dislikes him comes swinging
	if p != null and _op(-1) < -65.0 and randf() < 0.25 \
			and global_position.distance_squared_to(p.global_position) < 900.0 \
			and _can_see(p):
		_hunt_t = 12.0
		_lost_t = 0.0
		_say(_rally_line())
		for h2 in get_tree().get_nodes_in_group("earth_human"):
			if h2 == self or not (h2 is EarthHuman):
				continue
			var ally: EarthHuman = h2
			if _op(ally.human_id) > 40.0 and ally._op(-1) < -25.0 \
					and global_position.distance_squared_to(ally.global_position) < 2500.0:
				ally._hunt_t = 12.0
		return
	if p and _greet_cd <= 0.0 \
			and global_position.distance_squared_to(p.global_position) < 6.8:
		# a human who watched you hurt humans does not say hi
		_say(_insult_line() if _op(-1) < -30.0 else _social_line())
		_greet_cd = randf_range(18.0, 40.0)
		return
	if _social_cd > 0.0:
		return
	# mid-chat with the player? then no side conversations -- unless
	# this is the kind of person who interrupts. everyone knows one.
	if _ptalk_t > 0.0 and not _interrupts():
		return
	for h in get_tree().get_nodes_in_group("earth_human"):
		if h == self or not (h is EarthHuman):
			continue
		var hh: EarthHuman = h
		if hh._partner != null or hh._panic_t > 0.0:
			continue
		if hh._ptalk_t > 0.0 and not _interrupts():
			continue   # they're busy with the player. manners.
		var d2h := global_position.distance_squared_to(hh.global_position)
		# an ENEMY in range? sometimes it just kicks off. street rules.
		if _op(hh.human_id) < -45.0 and hh._target == null and d2h < 64.0 \
				and randf() < 0.3:
			_start_fight(hh)
			return
		# bad blood travels: humans who hate the blue dude tell OTHERS
		if d2h < 16.0 and _op(-1) < -40.0 and _gossip_cd <= 0.0:
			_gossip_cd = randf_range(20.0, 40.0)
			hh._op_add(-1, -randf_range(8.0, 15.0))
			_say(_gossip_line())
			return
		if d2h < 12.25:
			if randf() < 0.35:
				_start_convo(hh)
			return

## The interrupters: very goofy, very dumb, or very sure the world was
## waiting for them to start talking.
func _interrupts() -> bool:
	return maxf(maxf(float(_pers.get("goofy", 25.0)), float(_pers.get("dumb", 25.0))),
		float(_pers.get("confident", 25.0))) > 65.0

func _start_convo(other: EarthHuman) -> void:
	_partner = other
	other._partner = self
	_convo_left = randi_range(2, 4)
	other._convo_left = randi_range(2, 4)
	_convo_wait = randf_range(0.3, 0.8)
	other._convo_wait = 999.0   # they wait to be spoken to
	_heard = ""
	other._heard = ""

func _end_convo() -> void:
	_social_cd = randf_range(15.0, 40.0)
	_convo_wait = 999.0
	_heard = ""
	if _partner != null and is_instance_valid(_partner) and _partner._partner == self:
		_partner._partner = null
		_partner._social_cd = randf_range(15.0, 40.0)
		_partner._convo_wait = 999.0
	_partner = null

## What comes out of the mouth: personality plus the ledger. A grumpy
## human who hates you opens with insults. A dreamy one compliments
## strangers. Most people small-talk about geese.
func _pick_line_kind() -> String:
	if _partner == null:
		return "smalltalk"
	var op := _op(_partner.human_id)
	var mean := clampf((float(_pers.get("grumpy", 25.0)) - 30.0) * 0.012 \
		+ (float(_pers.get("edgy", 25.0)) - 30.0) * 0.010 - op * 0.012, 0.0, 0.85)
	var nice := clampf((float(_pers.get("dreamy", 25.0)) - 25.0) * 0.010 \
		+ (float(_pers.get("goofy", 25.0)) - 25.0) * 0.005 + op * 0.008, 0.0, 0.8)
	if _heard == "insult":
		# they started it
		return "insult" if randf() < maxf(mean, 0.25) else "react"
	# meanness rolls FIRST: a grumpy human does not mirror your
	# compliment, he has been waiting this whole time
	if randf() < mean:
		return "insult"
	if _heard == "nice" and randf() < 0.5:
		return "nice"
	if randf() < nice:
		return "nice"
	return "smalltalk"

func _speak() -> void:
	if _partner == null:
		return
	# the player is talking to me RIGHT NOW. hold the thought --
	# unless I'm an interrupter, in which case, no I won't.
	if _ptalk_t > 0.0 and not _interrupts():
		_convo_wait = 1.2
		return
	var kind := _pick_line_kind()
	match kind:
		"insult":
			_say(_insult_line(_partner.human_name))
		"nice":
			_say(_nice_line())
		"react":
			var pool: Array = REACTS[_insult_flavor()]
			_say(pool[randi() % pool.size()])
		_:
			_say(_smalltalk_line())
	_convo_left -= 1
	var partner := _partner
	if _convo_left <= 0:
		_end_convo()   # said my piece. the last line hangs in the air.
	else:
		_convo_wait = 999.0   # ball's in their court
	partner.hear(self, kind)

## Words arriving. Update the ledger; maybe reply, maybe escalate,
## maybe get out of there before this becomes a Whole Incident.
func hear(from: EarthHuman, kind: String) -> void:
	match kind:
		"insult":
			_op_add(from.human_id, -randf_range(12.0, 25.0))
		"nice":
			_op_add(from.human_id, randf_range(8.0, 18.0))
		_:
			_op_add(from.human_id, randf_range(-3.0, 5.0))
	_heard = kind
	if kind == "insult" and _op(from.human_id) < -35.0:
		var mean := float(_pers.get("grumpy", 25.0)) + float(_pers.get("edgy", 25.0))
		if mean > 90.0 and randf() < 0.6:
			_punch_human(from)   # words have failed
			return
		if float(_pers.get("anxious", 25.0)) > 40.0 or mean < 60.0:
			_flee_from(from)     # the sane response
			return
	if _partner == from:
		_convo_wait = randf_range(1.8, 2.8)

## Eyes: a straight ray to the target, blocked by anything solid --
## terrain, hills, the planet's own horizon.
func _can_see(p: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + _up() * 0.7,
		p.global_position + _up() * 0.5)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	return hit.is_empty() or hit.get("collider") == p

## The implant, visibly: a little glowing module on the BACK of the
## skull. The one place they can't see it. That's not an accident.
func add_chip_visual() -> void:
	if _body == null or not is_instance_valid(_body._head_m):
		return
	if _body._head_m.has_node("nchip"):
		return
	var chip := MeshInstance3D.new()
	chip.name = "nchip"
	var cm := BoxMesh.new()
	cm.size = Vector3(0.16, 0.16, 0.04)
	chip.mesh = cm
	chip.position = Vector3(0, 0.05, 0.3)
	chip.material_override = Destructible.make_material(Color("#23232a"), 0.1)
	_body._head_m.add_child(chip)
	var led := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.035
	lm.height = 0.07
	led.mesh = lm
	led.position = Vector3(0, 0.05, 0.33)
	led.material_override = Destructible.make_material(Color("#7bffb0"), 3.0)
	_body._head_m.add_child(led)

func _enter_house(h) -> void:
	_release_seat()
	_end_convo()
	_goal_house = null
	flat_house = h
	_house_t = randf_range(30.0, 70.0)
	global_position = h.interior_spawn() + Vector3(randf_range(-1.5, 1.5), 0.2,
		randf_range(-1.5, 0.5))
	velocity = Vector3.ZERO
	_act = "wander"
	_act_t = randf_range(2.0, 5.0)

func _exit_house() -> void:
	var h = flat_house
	flat_house = null
	_house_t = 0.0
	if h != null and is_instance_valid(h):
		global_position = h.global_position \
			- h.global_transform.basis.z * 2.5 + h.global_transform.basis.y * 1.2
	velocity = Vector3.ZERO
	_pick_act()

## What is this human TRYING to do right now, in words. The Neuralink
## reads intent straight off the brain stem. Privacy died in a lab.
func goal_text() -> String:
	if minded:
		return "obeying the chip. (the chip is you.)"
	if _eat_t > 0.0:
		return "eating a permadeath apple. fully committed."
	if _panic_t > 0.0:
		return "fleeing for their life"
	if _hunt_t > 0.0:
		return "hunting the blue dude. (also you.)"
	if _target != null and is_instance_valid(_target):
		return "street-fighting %s" % _target.human_name
	if _apple != null and is_instance_valid(_apple):
		return "beelining for a permadeath apple"
	if _travel_to >= 0 and _travel_to < Game.earth_cities.size():
		var dest := str(Game.earth_cities[_travel_to]["name"])
		if _leg >= 0 and _leg != _travel_to:
			return "riding the rail to %s (via %s)" % [dest,
				str(Game.earth_cities[_leg]["name"])]
		return "riding the rail to %s" % dest
	if flat_house != null and is_instance_valid(flat_house):
		return "relaxing at %s" % flat_house.display_name()
	if _partner != null and is_instance_valid(_partner):
		return "deep in conversation with %s" % _partner.human_name
	var extras := ""
	if hp < 20.0:
		extras = "  ·  hurt, wants food"
	elif _away_t > 0.0:
		extras = "  ·  visiting, will head home"
	match _act:
		"gohouse":
			if _goal_house != null and is_instance_valid(_goal_house):
				return "walking to %s%s" % [_goal_house.display_name(), extras]
			return "walking home" + extras
		"goseat":
			return "heading for a nice place to sit" + extras
		"goexit":
			return "heading for the LEAVE HOUSE button" + extras
		"sit":
			return "sitting. professionally." + extras
		"friend":
			if _friend != null and is_instance_valid(_friend):
				return "going to stand with %s (friend)%s" % [_friend.human_name, extras]
			return "looking for a friend" + extras
		"follow":
			return "following the blue dude around" + extras
		_:
			return "hanging out" + extras

## Chip command: swing at whoever's in arm's reach.
func mind_punch() -> void:
	for h in get_tree().get_nodes_in_group("earth_human"):
		if h == self or not (h is EarthHuman):
			continue
		if global_position.distance_squared_to(h.global_position) < 4.0:
			var pd: Vector3 = (h.global_position - global_position).normalized()
			h.take_fight_hit(self, (pd - _up() * pd.dot(_up())).normalized())
			Sfx.play("hurt", -20.0)
			return
	Sfx.play("click", -26.0)

## Chip autopilot small talk: the terminal talks FOR them.
func mind_talk() -> void:
	_say(_social_line() if randf() < 0.5 else _smalltalk_line())

## Nearest city with NO distance cap: for routing, everywhere is near
## some station.
func _nearest_city_any() -> int:
	if _home == null or Game.earth_cities.is_empty():
		return 0
	var cur: Vector3 = (global_position - _home.center).normalized()
	var best := 0
	var bd := 99.0
	for i in Game.earth_cities.size():
		var a: float = cur.angle_to(Game.earth_cities[i]["dir"])
		if a < bd:
			bd = a
			best = i
	return best

## Which city is this, then. -2 means the countryside: no city within
## ~80m of surface arc, no leash, no civic duties.
func _nearest_city() -> int:
	if _home == null or Game.earth_cities.is_empty():
		return -2
	var cur: Vector3 = (global_position - _home.center).normalized()
	var best := -2
	var bd: float = 80.0 / float(_home.radius)
	for i in Game.earth_cities.size():
		var a: float = cur.angle_to(Game.earth_cities[i]["dir"])
		if a < bd:
			bd = a
			best = i
	return best

## Stepping off the rail somewhere new: if this city's whole VIBE is
## your dominant axis, maybe it was always home. One move per life.
func _maybe_adopt_city() -> void:
	if home_city < 0 or _moved:
		return
	var idx := _nearest_city()
	if idx < 0 or idx == home_city:
		return
	var city: Dictionary = Game.earth_cities[idx]
	if float(_pers.get(str(city["vibe"]), 25.0)) > 70.0 and randf() < 0.15:
		home_city = idx
		_moved = true
		_away_t = 0.0
		_say("this is my city now. it always was.")

## Two friends, two cities, one conversation every friendship has
## eventually. The stubborn one (confident + grumpy) stays put; the
## flexible one packs up. Once you've moved, you're SETTLED.
func _maybe_negotiate_move() -> void:
	if _friend == null or not is_instance_valid(_friend):
		return
	if home_city < 0 or _friend.home_city < 0 or _friend.home_city == home_city:
		return
	if _moved and _friend._moved:
		return
	var stay_me := float(_pers.get("confident", 25.0)) \
		+ float(_pers.get("grumpy", 25.0)) + (60.0 if _moved else 0.0)
	var stay_them := float(_friend._pers.get("confident", 25.0)) \
		+ float(_friend._pers.get("grumpy", 25.0)) + (60.0 if _friend._moved else 0.0)
	var mover: EarthHuman = self if stay_me < stay_them else _friend
	var stayer: EarthHuman = _friend if mover == self else self
	mover.home_city = stayer.home_city
	mover._moved = true
	mover._away_t = 0.0
	var cn := str(Game.earth_cities[stayer.home_city]["name"])
	mover._say("fine. %s has better benches anyway. I'm in." % cn)
	stayer._say("correct choice. %s improves everyone." % cn)

## Best friend in range: highest mutual regard wins. Friendship is a
## ledger that went POSITIVE, which on this planet is remarkable.
func _best_friend(maxd: float) -> EarthHuman:
	var best: EarthHuman = null
	var bop := 40.0
	for h in get_tree().get_nodes_in_group("earth_human"):
		if h == self or not (h is EarthHuman):
			continue
		var hh: EarthHuman = h
		var op := _op(hh.human_id)
		if op > bop and hh._op(human_id) > 25.0 \
				and global_position.distance_to(hh.global_position) < maxd:
			bop = op
			best = hh
	return best

func _start_fight(o: EarthHuman) -> void:
	_end_convo()
	o._end_convo()
	_release_seat()
	_target = o
	o._target = self
	_fight_t = randf_range(8.0, 16.0)
	o._fight_t = _fight_t
	_evading = false
	o._evading = false
	_phase_t = 0.0
	o._phase_t = 0.4
	_say(_insult_line(o.human_name))

## A fight punch: lighter than murder, heavier than words. Friends who
## see it may pile in -- and that's how gang fights are born.
func take_fight_hit(from: EarthHuman, dir: Vector3) -> void:
	_release_seat()
	hp -= randf_range(2.0, 4.0)
	if hp <= 0.0:
		_die(dir)   # fights CAN end badly. meat happens.
		return
	_op_add(from.human_id, -8.0)
	velocity += dir * 3.0 + _up() * 1.5
	Sfx.play("hurt", -22.0)
	if _target == null:   # sucker-punched: now it's a fight
		_target = from
		_fight_t = randf_range(6.0, 12.0)
		_evading = true
		_phase_t = randf_range(0.6, 1.2)
	if randf() < 0.3:
		_say(_insult_line(from.human_name))
	if randf() < 0.35:
		for h in get_tree().get_nodes_in_group("earth_human"):
			if h == self or h == from or not (h is EarthHuman):
				continue
			var hh: EarthHuman = h
			if hh._target == null and hh._hunt_t <= 0.0 \
					and hh._op(human_id) > 40.0 \
					and hh.global_position.distance_squared_to(global_position) < 400.0:
				hh._target = from
				hh._fight_t = randf_range(6.0, 10.0)
				hh._say(hh._insult_line(from.human_name))
				break

## Escalation, physical. The universal language.
func _punch_human(t: EarthHuman) -> void:
	_say(_insult_line(t.human_name))
	_op_add(t.human_id, -10.0)
	var dir: Vector3 = (t.global_position - global_position).normalized()
	_end_convo()
	t.take_punch_from(self, dir)

func take_punch_from(from: EarthHuman, dir: Vector3) -> void:
	_op_add(from.human_id, -30.0)   # oh, THAT'S how it is
	_end_convo()
	_panic_t = 3.0
	_dir = (dir - _up() * dir.dot(_up())).normalized()
	velocity += dir * 2.0 + _up() * 1.2   # a shove, not a launch: the
	# insults have to stay READABLE
	var mean := float(_pers.get("grumpy", 25.0)) + float(_pers.get("edgy", 25.0))
	_say(_insult_line() if mean > 90.0 \
		else "WHY. " + from.human_name.to_upper() + ". WHY.")
	Sfx.play("hurt", -20.0)

func _flee_from(from: EarthHuman) -> void:
	_end_convo()
	_panic_t = 3.5
	var away: Vector3 = global_position - from.global_position
	_dir = (away - _up() * away.dot(_up())).normalized()

## ---- mortality: humans are a byproduct of the universe, not its foundation ----

## Bystanders SEE you. Hurt a human in front of humans and every ledger
## in range turns a page against the blue dude. Kill one and they run.
func _witness(d: float) -> void:
	for h in get_tree().get_nodes_in_group("earth_human"):
		if h == self or not (h is EarthHuman):
			continue
		if global_position.distance_squared_to(h.global_position) < 225.0:
			h._op_add(-1, d)
			if d <= -20.0:
				h._flee_from(self)

func _die(dir: Vector3 = Vector3.UP) -> void:
	if _dead:
		return
	_dead = true
	_release_seat()
	# a human, it turns out, is a few meats waiting to happen
	Destructible.spawn_debris(get_parent(), global_position,
		Vector3(0.7, 1.6, 0.7), Color("#c05050"), dir)
	_drop_meat(randi_range(2, 3))
	_spill_pockets()
	Sfx.play("hurt", -10.0)
	queue_free()

func _inv_count() -> int:
	var n := 0
	for k in inv:
		n += int(inv[k])
	return n

## Death empties the pockets. The next scavenger says thanks.
func _spill_pockets() -> void:
	for k in inv:
		var d := ItemDrop.new()
		d.setup(str(k), int(inv[k]))
		get_parent().add_child(d)
		d.global_position = global_position + Vector3(randf_range(-0.7, 0.7),
			0.3, randf_range(-0.7, 0.7))
	inv.clear()

func _drop_meat(n: int) -> void:
	for i in n:
		var d := ItemDrop.new()
		d.setup("meat", 1)
		get_parent().add_child(d)
		d.global_position = global_position + Vector3(randf_range(-0.8, 0.8),
			0.3, randf_range(-0.8, 0.8))

## Bite taken. Chew. The countdown to consequence is already running.
func _eat_apple() -> void:
	if _apple == null or not is_instance_valid(_apple):
		_apple = null
		return
	_apple.count -= 1
	if _apple.count <= 0:
		_apple.queue_free()
	_apple = null
	_eat_t = 2.4
	_end_convo()
	Sfx.play("eat")
	# the eating animation: hand to mouth, chew, chew, chew. no idea.
	if is_instance_valid(_body) and is_instance_valid(_body._arm_r):
		var tw := create_tween()
		tw.tween_property(_body._arm_r, "rotation:x", -2.5, 0.35)
		for i in 3:
			tw.tween_property(_body._arm_r, "rotation:x", -2.1, 0.25)
			tw.tween_property(_body._arm_r, "rotation:x", -2.5, 0.25)
	if is_instance_valid(_body) and is_instance_valid(_body._head_m):
		var tw2 := create_tween()
		for i in 4:
			tw2.tween_property(_body._head_m, "rotation:x", 0.18, 0.3)
			tw2.tween_property(_body._head_m, "rotation:x", 0.0, 0.3)

## The apple does to a human exactly what it does to you -- minus the
## planets. Planets stay intact. The universe barely files the paperwork.
func _explode() -> void:
	if _dead:
		return
	_dead = true
	_release_seat()
	_burst(Color("#ff4020"), 10.0, 60)
	_burst(Color("#ffffff"), 6.0, 30)
	Sfx.play("explode", -6.0)
	_witness(-25.0)   # everyone saw where that apple came from
	_drop_meat(randi_range(3, 5))
	_spill_pockets()
	queue_free()

func _burst(col: Color, size: float, amount: int) -> void:
	var parts := GPUParticles3D.new()
	parts.amount = amount
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.lifetime = 2.4
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.ZERO
	pm.spread = 180.0
	pm.initial_velocity_min = size * 0.4
	pm.initial_velocity_max = size * 1.3
	pm.gravity = Vector3.ZERO
	pm.scale_min = size * 0.01
	pm.scale_max = size * 0.05
	pm.color = col
	parts.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = Destructible.make_material(col, 3.0)
	parts.draw_pass_1 = mesh
	get_parent().add_child(parts)
	parts.global_position = global_position + _up() * 0.5
	parts.emitting = true
	get_tree().create_timer(3.0).timeout.connect(parts.queue_free)

func _physics_process(delta: float) -> void:
	if _home == null:
		return
	# LOD: a human nobody is near does NOTHING. no walking, no thoughts,
	# no grudges. reality only renders where someone is looking.
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = 0.5
		var pl = get_tree().get_first_node_in_group("player")
		var ppos: Vector3 = pl.global_position if pl != null else Vector3.ZERO
		if pl != null and Game.zone != "" and Game.has_proxy:
			ppos = Game.player_proxy   # player is indoors: count from the door
		var d2 := global_position.distance_squared_to(ppos) \
			if pl != null else INF
		if pl != null and flat_house != null and is_instance_valid(flat_house):
			d2 = minf(d2, flat_house.global_position.distance_squared_to(pl.global_position))
		_active = d2 < 3600.0
		# labels only exist up close: no nametag dots dotting the
		# horizon from the far side of the planet
		var near := d2 < 625.0
		_bubble.visible = near
		_bg.visible = near
		_tag.visible = near
	if not _active:
		return
	# mortality, the slow kind: humans age only while reality renders
	# them. eventually one of these frames is the last one.
	age += delta
	if age > lifespan and not _dead:
		_die(_up())   # of old age, mid-errand. the meat is unaffected.
		return
	var up := _up()

	# neuralink: the chip drives. AI unplugged, body obeys.
	if minded:
		if _bubble_t > 0.0:
			_bubble_t -= delta
			var bam := clampf(_bubble_t / 0.8, 0.0, 1.0)
			_bubble.modulate.a = bam
			_bubble.outline_modulate.a = bam
			_bg_mat.set_shader_parameter("alpha", bam)
		# facing is its own control (Q/E turn); movement STRAFES.
		if _dir.length() < 0.1:
			_dir = -global_transform.basis.z
		if absf(mind_turn) > 0.01:
			_dir = _dir.rotated(up, mind_turn * delta)
		_dir = (_dir - up * _dir.dot(up)).normalized()
		var msp := 0.0
		var mv := mind_dir - up * mind_dir.dot(up)
		if mv.length() > 0.1:
			mv = mv.normalized()
			msp = WALK_SPEED * 1.6
		else:
			mv = Vector3.ZERO
		var mvu := velocity.dot(up) + Universe.gravity_at(global_position).dot(up) * delta
		velocity = mv * msp + up * mvu
		up_direction = up
		move_and_slide()
		_grounded = is_on_floor()
		var xm := _dir.cross(up).normalized()
		global_transform.basis = Basis(xm, up, -_dir).orthonormalized()
		if _body:
			_body.animate(msp, _grounded, delta)
		return

	# riding the rail: glide the great-circle line to the destination.
	# commuters stand. it's the law.
	if _travel_to >= 0:
		if _travel_to >= Game.earth_cities.size():
			_travel_to = -1
			_leg = -1
		else:
			# rail PATHFINDING: the network is a ring. ride it stop by
			# stop the short way around -- nobody cuts across the fields
			var nct := Game.earth_cities.size()
			if _leg < 0:
				var from := _nearest_city_any()
				if from == _travel_to:
					_leg = _travel_to
				else:
					var fwd_hops := (_travel_to - from + nct) % nct
					var back_hops := (from - _travel_to + nct) % nct
					_leg = (from + (1 if fwd_hops <= back_hops else -1) + nct) % nct
			var tgt: Vector3 = Game.earth_cities[_leg]["dir"]
			var cur: Vector3 = (global_position - _home.center).normalized()
			var ang: float = cur.angle_to(tgt)
			if ang < 0.02:
				if _leg != _travel_to:
					# passing through. next stop, please.
					var nct2 := Game.earth_cities.size()
					var fh := (_travel_to - _leg + nct2) % nct2
					var bh := (_leg - _travel_to + nct2) % nct2
					_leg = (_leg + (1 if fh <= bh else -1) + nct2) % nct2
				else:
					_travel_to = -1
					_leg = -1
					velocity = Vector3.ZERO
					_maybe_adopt_city()
			else:
				var step: float = clampf((16.0 * delta) / (float(_home.radius) * ang), 0.0, 1.0)
				var nd: Vector3 = cur.slerp(tgt, step).normalized()
				global_position = _home.center + nd * (_home.radius + 1.15)
				var fwd := nd - cur
				fwd = (fwd - nd * fwd.dot(nd))
				if fwd.length() > 0.0001:
					fwd = fwd.normalized()
					var xr := fwd.cross(nd).normalized()
					global_transform.basis = Basis(xr, nd, -fwd).orthonormalized()
				if _body:
					_body.animate(0.0, true, delta)
			return

	# visiting another city: the clock ticks toward homesickness
	if _away_t > 0.0:
		_away_t -= delta
		if _away_t <= 0.0 and home_city >= 0:
			_travel_to = home_city   # every time. no exceptions.
	var g: Vector3 = Vector3.DOWN * 9.0 if flat_house != null \
		else Universe.gravity_at(global_position)

	# thought bubble fades like the thought itself. the OUTLINE fades in
	# lockstep -- left opaque it lingers as a black ghost of the words
	if _bubble_t > 0.0:
		_bubble_t -= delta
		var ba := clampf(_bubble_t / 0.8, 0.0, 1.0)
		_bubble.modulate.a = ba
		_bubble.outline_modulate.a = ba
		_bg_mat.set_shader_parameter("alpha", ba)

	# the voice cuts through when you're actually LOOKING at the
	# speaker: focus is a volume knob. glance away, it blends back
	# into the crowd
	if _vp != null and is_instance_valid(_vp):
		var pl2 = get_tree().get_first_node_in_group("player")
		if pl2:
			var cam: Camera3D = pl2.camera()
			var to_me: Vector3 = (global_position - cam.global_position).normalized()
			var focus := clampf(-cam.global_transform.basis.z.dot(to_me), 0.0, 1.0)
			_vp.volume_db = lerpf(-16.0, -1.0, pow(focus, 3.0))

	_act_t -= delta
	if _act_t <= 0.0 and _panic_t <= 0.0:
		_pick_act()

	# hurt and holding food? eat it. where the meat came from is not
	# a question anyone asks out loud.
	_eat_cd -= delta
	if hp < 26.0 and _eat_cd <= 0.0 and _panic_t <= 0.0 and _eat_t <= 0.0:
		for fkey in FOOD_HEAL:
			if int(inv.get(fkey, 0)) > 0:
				inv[fkey] = int(inv[fkey]) - 1
				if int(inv[fkey]) <= 0:
					inv.erase(fkey)
				hp = minf(30.0, hp + float(FOOD_HEAL[fkey]))
				_eat_cd = 7.0
				Sfx.play("eat", -20.0)
				if fkey == "meat" and randf() < 0.25:
					_say("tastes familiar.")
				break

	# mid-chew: the countdown between bite and consequence
	if _eat_t > 0.0:
		_eat_t -= delta
		if _eat_t <= 0.0:
			_explode()
			return

	# the social layer: greetings, conversations, grudges. scans are
	# staggered per-human and use squared distances -- crowds stay cheap
	_social_cd -= delta
	_greet_cd -= delta
	_ptalk_t -= delta
	# KARENS: perpetually finding tiny problems. it's a calling.
	if human_name == "Karen":
		_karen_t -= delta
		if _karen_t <= 0.0 and _partner == null and _target == null \
				and _panic_t <= 0.0:
			_karen_t = randf_range(18.0, 40.0)
			_karen_complain()
	_gossip_cd -= delta
	if _partner != null and not is_instance_valid(_partner):
		_partner = null
	if _panic_t <= 0.0 and _eat_t <= 0.0:
		_scan_t -= delta
		if _scan_t <= 0.0:
			_scan_t = randf_range(0.6, 1.0)
			_check_social()
		if _partner != null:
			_convo_wait -= delta
			if _convo_wait <= 0.0:
				_speak()

	var speed := 0.0
	if _panic_t > 0.0:
		_panic_t -= delta
		speed = PANIC_SPEED
	elif _eat_t > 0.0:
		pass   # chewing. busy. transcending.
	elif _apple != null:
		if not is_instance_valid(_apple):
			_apple = null
		else:
			# beelining for the apple. it's SO red. it's SO shiny.
			var to_a: Vector3 = _apple.global_position - global_position
			_dir = (to_a - up * to_a.dot(up)).normalized()
			if to_a.length() < 1.4:
				_eat_apple()
			else:
				speed = WALK_SPEED * 1.25
	elif _hunt_t > 0.0:
		# the gang-up: bad reputation has consequences with fists
		_hunt_t -= delta
		_swing_cd -= delta
		var hp2 = get_tree().get_first_node_in_group("player")
		if hp2 == null or Game.dead or Game.mode != Game.Mode.ON_FOOT:
			_hunt_t = 0.0
		else:
			var to_p2: Vector3 = hp2.global_position - global_position
			# they have to SEE you to keep chasing. duck behind terrain
			# (or the planet's own curve) and stay gone -- they give up.
			_los_t -= delta
			if _los_t <= 0.0:
				_los_t = 0.3
				if _can_see(hp2):
					_lost_t = 0.0
				else:
					_lost_t += 0.3
			if _lost_t > 2.0 or to_p2.length() > 40.0:
				_hunt_t = 0.0
				_lost_t = 0.0
				_say(["where'd he GO.", "he's GONE. typical.",
					"I'll remember this, blue dude.",
					"cowardice. NOTED."][randi() % 4])
			else:
				_dir = (to_p2 - up * to_p2.dot(up)).normalized()
				if to_p2.length() > 1.7:
					speed = PANIC_SPEED * 0.85
				elif _swing_cd <= 0.0:
					_swing_cd = 1.1
					Game.hurt(4.0)
					Sfx.play("hurt", -14.0)
					if randf() < 0.4:
						_say(_insult_line())
	elif _target != null:
		# street fight: swing, back off, talk trash, swing again
		if not is_instance_valid(_target) or _target._dead or _fight_t <= 0.0:
			if _target != null and is_instance_valid(_target) and _target._target == self:
				_target._target = null
				_target._fight_t = 0.0
			_target = null
		else:
			_fight_t -= delta
			_phase_t -= delta
			_swing_cd -= delta
			var to_t: Vector3 = _target.global_position - global_position
			var flat := (to_t - up * to_t.dot(up)).normalized()
			if _evading:
				_dir = -flat
				speed = WALK_SPEED * 1.5
				if _phase_t <= 0.0:
					_evading = false
					if randf() < 0.45:
						_say(_insult_line(_target.human_name))
			else:
				_dir = flat
				if to_t.length() > 1.5:
					speed = PANIC_SPEED * 0.8
				elif _swing_cd <= 0.0:
					_swing_cd = 0.9
					_target.take_fight_hit(self, flat)
					_evading = true
					_phase_t = randf_range(0.8, 1.8)
	elif _partner != null:
		# conversation stance: feet still, eyes locked, every word meant
		var to_p: Vector3 = _partner.global_position - global_position
		if to_p.length() > 0.1:
			_dir = (to_p - up * to_p.dot(up)).normalized()
	else:
		match _act:
			"wander":
				speed = WALK_SPEED
			"stare":
				speed = 0.0
			"circle":
				speed = WALK_SPEED * 0.8
				_dir = _dir.rotated(up, delta * 1.6)   # walking that comes back
			"spin":
				speed = 0.0
				_dir = _dir.rotated(up, delta * 2.4)   # rotating. contemplating.
			"follow":
				var p = get_tree().get_first_node_in_group("player")
				if p and global_position.distance_to(p.global_position) < 40.0:
					var to: Vector3 = p.global_position - global_position
					_dir = (to - up * to.dot(up)).normalized()
					if to.length() > 4.0:
						speed = WALK_SPEED
				else:
					speed = WALK_SPEED   # "following" nothing. still counts.
			"friend":
				if _friend == null or not is_instance_valid(_friend):
					_pick_act()
				else:
					var to_f: Vector3 = _friend.global_position - global_position
					_dir = (to_f - up * to_f.dot(up)).normalized()
					if to_f.length() > 80.0 and _friend.home_city >= 0:
						# different city: that's a rail trip, not a walk
						_travel_to = _friend.home_city
						_away_t = randf_range(40.0, 70.0)
					elif to_f.length() > 2.2:
						speed = WALK_SPEED * 1.1
					# close enough: stand together. chats start on their own
			"gohouse":
				if _goal_house == null or not is_instance_valid(_goal_house):
					_pick_act()
				else:
					var to_h: Vector3 = _goal_house.door_spot() - global_position
					var flat_h := to_h - up * to_h.dot(up)
					_dir = flat_h.normalized()
					if flat_h.length() < 3.0:
						var gh = _goal_house
						_enter_house(gh)
						if gh == my_house and randf() < 0.5:
							var fr3 := _best_friend(80.0)
							if fr3 != null and fr3.flat_house == null \
									and fr3._goal_house == null:
								fr3._goal_house = gh   # you. come see the place.
								fr3._act = "gohouse"
								fr3._act_t = 40.0
					else:
						speed = WALK_SPEED * 1.1
			"goexit":
				if flat_house == null or not is_instance_valid(flat_house):
					_pick_act()
				else:
					var to_x: Vector3 = flat_house.exit_pad - global_position
					var flat_x := to_x - up * to_x.dot(up)
					_dir = flat_x.normalized() if flat_x.length() > 0.01 else Vector3.ZERO
					if flat_x.length() < 1.4:
						_exit_house()   # button pressed. door used. dignity intact.
					elif _act_t <= 0.5:
						_exit_house()   # jammed behind a sofa: fine, phase out
					else:
						speed = WALK_SPEED * 1.05
			"goseat":
				if _seat == null or not is_instance_valid(_seat):
					_pick_act()
				else:
					var to_s: Vector3 = _seat.global_position - global_position
					_dir = (to_s - up * to_s.dot(up)).normalized()
					if to_s.length() < 1.1:
						# arrived. commence sitting. a while.
						_act = "sit"
						_act_t = randf_range(12.0, 30.0)
						if _body:
							_body.pose = 6
					else:
						speed = WALK_SPEED
			"sit":
				speed = 0.0

	# planted on a seat: physics is paused. the universe can wait.
	if _act == "sit":
		if _panic_t > 0.0 or _apple != null or _target != null \
				or _hunt_t > 0.0 or _seat == null \
				or not is_instance_valid(_seat):
			_release_seat()
		else:
			velocity = Vector3.ZERO
			global_transform = Transform3D(
				_seat.global_transform.basis.orthonormalized(),
				_seat.global_position + up * 0.12)
			if _body:
				_body.animate(0.0, true, delta)
			return

	# active detour overrides whatever the act wanted this frame
	_redetour_t = maxf(0.0, _redetour_t - delta)
	if _detour_t > 0.0:
		_detour_t -= delta
		if _dir.length() > 0.01:
			_dir = _detour

	# re-level the walk direction to the CURRENT local up every frame --
	# a stale tangent on a sphere points slowly skyward, which had them
	# hopping off the curvature as they strolled
	if _dir.length() > 0.01:
		_dir = (_dir - up * _dir.dot(up)).normalized()
	var v_up := velocity.dot(up)
	v_up += g.dot(up) * delta
	# scared humans can LEAP as they flee -- properly launched, airborne,
	# briefly free. then the universe remembers them and throws them back.
	# very, very rare: most panics stay on foot like sensible mammals.
	if _panic_t > 0.0 and _grounded and _fly_t <= 0.0 and randf() < 0.0015:
		v_up = randf_range(7.0, 11.0)
		_fly_t = 1.0
	if _fly_t > 0.0:
		_fly_t -= delta
		if _fly_t <= 0.0 and not _grounded:
			v_up = -30.0   # flight privileges revoked
	velocity = _dir * speed + up * v_up
	up_direction = up
	move_and_slide()
	_grounded = is_on_floor()
	# anti-wall-grind: trying to walk but not actually moving? there is
	# a chest, a wall, or a life lesson in the way. turn.
	if speed > 0.5:
		if global_position.distance_to(_last_pos) < speed * delta * 0.25:
			_stuck_t += delta
			if _stuck_t > 1.0:
				_stuck_t = 0.0
				# goal acts re-aim every frame, so a one-frame turn does
				# nothing: hold a sidestep DETOUR for a moment instead.
				# and if the LAST dodge didn't free us, dodge the OTHER
				# way -- no more left, left, face-first into the same
				# tilted wall forever
				if _redetour_t > 0.0:
					_detour_side = -_detour_side
				else:
					_detour_side = 1.0 if randf() < 0.5 else -1.0
				_detour = _dir.rotated(up, deg_to_rad(
					90.0 * _detour_side + randf_range(-25.0, 25.0)))
				_detour_t = 1.1
				_redetour_t = 4.0
		else:
			_stuck_t = 0.0
	_last_pos = global_position
	# indoors: the visit timer. when it's up, home ejects you politely
	if flat_house != null:
		if not is_instance_valid(flat_house):
			flat_house = null
		else:
			_house_t -= delta
			if _house_t <= 0.0 and _act != "goexit":
				# time to go -- but people USE the door button, they
				# don't dematerialize mid-living-room
				if flat_house.exit_pad != Vector3.ZERO:
					_act = "goexit"
					_act_t = 25.0   # give up and phase out if truly stuck
				else:
					_exit_house()
	# leash: calm humans belong on the ground; punched/panicking ones get
	# real air time. only ACTUAL astronauts get snapped back.
	var alt: float = global_position.distance_to(_home.center) - float(_home.radius)
	var leash := 30.0 if _panic_t > 0.0 else 3.0
	if flat_house == null and alt > leash:
		global_position = _home.center + up * (_home.radius + 1.1)
		velocity = Vector3.ZERO

	# face where we walk, feet planted along gravity
	if (speed > 0.1 or _partner != null) and _dir.length() > 0.1:
		var x := _dir.cross(up).normalized()   # RIGHT-handed: no mirror
		global_transform.basis = Basis(x, up, -_dir).orthonormalized()
	else:
		# idle: STILL stand along gravity. cage releases used to walk
		# out sideways and simply live like that. no longer.
		var fwd := -global_transform.basis.z
		fwd = fwd - up * fwd.dot(up)
		if fwd.length() < 0.05:
			fwd = up.cross(Vector3.RIGHT)
		fwd = fwd.normalized()
		var x2 := fwd.cross(up).normalized()
		global_transform.basis = Basis(x2, up, -fwd).orthonormalized()
	if _body and _eat_t <= 0.0:   # mid-bite the tween owns the limbs
		_body.animate(speed, _grounded, delta)

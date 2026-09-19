class_name Echegel
extends Node3D
## AN ECHEGEL. A disk of wet meat with a ring of tentacles under it.
##
## They live IN the continents rather than on them, and they DIVE: down
## through the slime and along under it, whole body submerged, the arms
## doing the work exactly the way you would swim through water, and up
## again somewhere else. The tentacle count varies -- six to ten, no
## number favoured, because a species is not a statistic.
##
## Their mouth is a small stick and it is normally RETRACTED, sitting
## inside the body where you cannot see it. It comes out when one of
## them decides to say something to you, and goes back in afterwards.
##
## They are not friendly and they are not helpful. One of them once told
## a visitor to get off his own spaceship.
##
## Their speech sounds like English right up until you try to write it
## down. Real words in real places, and then something that is not a
## word at all sitting where a noun should be. Nobody has worked out
## whether the numbers are grammar or names or swearing; two of them
## turn up often enough in arguments that it is probably swearing.

const TENT_MIN := 6
const TENT_MAX := 10
const TALK_RANGE := 9.0   # they speak to somebody standing with them

var home_name: String = ""      # which continent it belongs to
var body_r: float = 0.85
## A DEAD ONE. Two of these exist and both are landmarks: the one on
## the sharpest spike of the core, and the one alone on Ex23 Florgus.
## They do not swim, they do not dive and they do not talk -- they sit
## exactly where they were put, grey and gone slack.
var dead: bool = false

var _rng := RandomNumberGenerator.new()
var _disk: MeshInstance3D
var _mouth: Node3D
var _tents: Array = []          # [[segment nodes], phase]
var _bubble: Label3D
var _bubble_t: float = 0.0
var _t: float = 0.0
var _dive: float = 0.0          # 0 = surfaced, 1 = fully under
enum { SURFACED, DOWN, UNDER, UP }
var _phase: int = SURFACED
var _under_t: float = 0.0
var _dive_cd: float = 0.0
var _talk_cd: float = 0.0
var _swim: Vector3 = Vector3.ZERO
var _up: Vector3 = Vector3.UP
## How far the mouth is out, 0..1 of its length. Retracted is the
## resting state; speaking is the only thing that raises it.
const MOUTH_IN := 0.06
var _mouth_out: float = 0.0
var _mouth_hold: float = 0.0
var _pending: String = ""

# ------------------------------------------------------------ language
## The words that are words. Short, common, and load-bearing -- it is
## the frame around the parts you cannot read that makes it sound like
## a language instead of a keyboard falling over.
## THE ENGLISH IN IT IS GRAMMAR AND NOTHING ELSE: you, we, our, this,
## is, some -- the words that hold a sentence together and mean nothing
## you can point at. No action verbs, no nouns for things. Those carry
## meaning, and the whole effect is that you can hear the shape of what
## is being said and never the content. This list had "get", "give",
## "take", "go" and "come" in it, and every one of them told you
## something was happening.
const REAL := ["at", "we", "our", "us", "you", "your", "this", "that",
	"is", "was", "are", "the", "a", "and", "in", "on", "of", "or",
	"for", "my", "it", "its", "not", "to", "with", "they", "their",
	"he", "his", "she", "her", "who", "some", "all", "no", "yes",
	"but", "if", "then", "than", "there", "here", "up", "down", "off",
	"out", "so", "as", "be", "will", "can", "more", "any", "each",
	"which", "when", "while", "from", "has", "very", "too"]

## Tokens that recur often enough to be vocabulary rather than noise.
## Two of these are almost certainly swearing.
const CANON := ["q9", "03", "i2", "39", "7eh", "219", "m03r2n", "sh21",
	"i90o", "Ex23", "0g", "r2", "9th", "z04", "e7", "13o", "q9*", "#03"]
## Words that cannot be the last one in a sentence.
const PARTICLES := ["at", "to", "in", "on", "up", "down", "off", "for",
	"with", "and", "is", "was", "the", "are", "has", "do", "go", "my",
	"our", "your", "his"]
const STEMS := ["m", "r", "n", "sh", "z", "k", "th", "gr", "fl", "q",
	"v", "br", "ch", "dr", "st"]
const TAILS := ["eh", "o", "a", "us", "en", "ir", "ol", "ak", "im", "un"]
## "letters, numbers, and symbols" -- a light sprinkle, not a keysmash
const SYMBOLS := ["*", "#", "~", "'", "-", "/", "!"]

## One Echegel word. Half the time it is a word you have heard them use
## before; the rest of the time it is built the way those were.
static func word(rng: RandomNumberGenerator) -> String:
	if rng.randf() < 0.45:
		return CANON[rng.randi() % CANON.size()]
	# SHORT. q9, 03, i2, 7eh, sh21 -- two to five characters, a stem and
	# a number in some order. The old builder stacked a digit, a stem,
	# two more digits, a tail and another digit and produced "6m58ak",
	# which is longer than anything they have ever been heard to say.
	var stem: String = STEMS[rng.randi() % STEMS.size()]
	var num := str(rng.randi_range(0, 9)) if rng.randf() < 0.55 \
		else str(rng.randi_range(10, 99))
	var w := ""
	match rng.randi() % 4:
		0: w = stem + num
		1: w = num + stem
		2: w = stem + num + TAILS[rng.randi() % TAILS.size()]
		_: w = num + stem + str(rng.randi_range(0, 9))
	if rng.randf() < 0.12:
		w += SYMBOLS[rng.randi() % SYMBOLS.size()]
	return w

## A sentence: real words holding the shape, Echegel words doing the
## work. It reads like you nearly understood it, which is worse.
static func sentence(rng: RandomNumberGenerator) -> String:
	var n := rng.randi_range(4, 8)
	var parts: Array = []
	for i in n:
		# THE SHAPE OF IT. The opening is mostly words you know, so the
		# sentence lands as a sentence; the middle drifts; and the last
		# word is almost always theirs, because the thing being said is
		# the part you were never going to get. A line that ends "up at"
		# reads as a mistake. One that ends "our q9" reads as a language.
		var chance := 0.42
		if i < 2:
			chance = 0.68
		elif i == n - 1:
			chance = 0.16
		var real := rng.randf() < chance
		var w: String = REAL[rng.randi() % REAL.size()] if real else word(rng)
		if not parts.is_empty() and str(parts.back()) == w:
			w = word(rng)   # never the same word twice running
		# and never finish on a particle. "...up at" reads as a line
		# that got cut off; "...our q9" reads as a sentence you were not
		# meant to finish.
		if i == n - 1 and PARTICLES.has(w):
			w = word(rng)
		parts.append(w)
	return " ".join(parts)

# ------------------------------------------------------------- the body

func setup(cont_name: String, seed_i: int) -> void:
	home_name = cont_name
	_rng.seed = hash(cont_name) ^ (seed_i * 7919)

func _ready() -> void:
	add_to_group("echegel")
	if _rng.seed == 0:
		_rng.randomize()
	body_r = _rng.randf_range(0.7, 1.25)
	_build()
	_dive_cd = _rng.randf_range(4.0, 22.0)
	_talk_cd = _rng.randf_range(3.0, 12.0)
	if dead:
		# slack: every arm hanging straight down, mouth folded over
		for t in _tents:
			for seg in t["segs"]:
				if is_instance_valid(seg):
					seg.rotation_degrees = Vector3(_rng.randf_range(-6, 6), 0,
						_rng.randf_range(-6, 6))
		if _mouth != null:
			_mouth.rotation_degrees = Vector3(74.0, 0, 12.0)
			_mouth.scale = Vector3(1.0, MOUTH_IN, 1.0)

func _build() -> void:
	# SLUG. Ochre-brown, wet, and faintly green from living inside a
	# lime continent -- whatever they are, they have taken the colour of
	# the stuff they swim in.
	var skin := Color("#8d8354").lerp(Color("#7fa03a"), _rng.randf_range(0.2, 0.45))
	if dead:
		# the colour goes out of them first, and then the shine
		skin = skin.lerp(Color("#6a6a63"), 0.72)
	var mat := _slick(skin)

	# A DISK, and a flat one. Wider than it is anything else, with a low
	# dome on top -- they kept reading as octopuses because the body was
	# nearly round and the arms hung off the bottom of it like a bell.
	_disk = MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = body_r
	dm.height = body_r * 0.62
	dm.radial_segments = 20
	dm.rings = 9
	_disk.mesh = dm
	_disk.material_override = mat
	_disk.scale = Vector3(1.28, 1.0, 1.28)
	add_child(_disk)
	# a low saddle over the middle, like a slug's mantle
	var mant := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = body_r * 0.66
	mm.height = body_r * 0.46
	mant.mesh = mm
	mant.material_override = _slick(skin.darkened(0.3))
	mant.position = Vector3(0, body_r * 0.14, 0)
	mant.scale = Vector3(1.15, 1.0, 1.15)
	add_child(mant)

	# TENTACLES: SPLAYED, not dangling. They come off the rim and reach
	# outward and a little down, the way a starfish does -- short, stiff
	# and radial. Long arms hanging under a round body is an octopus,
	# and that is exactly what it looked like.
	# HOW MANY ARMS. Anywhere from six to ten and no number favoured:
	# this used to roll seven half the time, which made a species out of
	# a statistic and gave every one of them the same silhouette.
	var n := TENT_MIN + _rng.randi() % (TENT_MAX - TENT_MIN + 1)
	for i in n:
		var a := TAU * float(i) / float(n)
		var outward := Vector3(cos(a), 0, sin(a))
		# how far from straight down each arm reaches out
		var splay := deg_to_rad(_rng.randf_range(58.0, 78.0))
		var reach := (outward * sin(splay) + Vector3.DOWN * cos(splay)).normalized()
		var arm := Node3D.new()
		add_child(arm)
		arm.position = outward * body_r * 1.12 - Vector3(0, body_r * 0.06, 0)
		arm.basis = _basis_from_up(-reach)   # local -Y runs along the arm
		var segs: Array = []
		var prev := arm
		for k in 4:
			var seg := MeshInstance3D.new()
			var sm := CapsuleMesh.new()
			sm.radius = body_r * (0.15 - float(k) * 0.028)
			sm.height = body_r * 0.34
			sm.radial_segments = 7
			seg.mesh = sm
			seg.material_override = mat   # one arm material, not one per joint
			seg.position = Vector3(0, -body_r * 0.24, 0)
			prev.add_child(seg)
			segs.append(seg)
			prev = seg
		_tents.append({"segs": segs, "ph": _rng.randf() * TAU,
			"dir": outward})

	# THE MOUTH. A small stick, and it is NOT normally out: it lives
	# retracted in the body and extends when one of them decides to say
	# something to you. Leaving it permanently up turned a mannerism
	# into anatomy.
	_mouth = Node3D.new()
	_mouth.scale = Vector3(1.0, MOUTH_IN, 1.0)
	add_child(_mouth)
	var stalk := MeshInstance3D.new()
	var stm := CylinderMesh.new()
	stm.top_radius = body_r * 0.075
	stm.bottom_radius = body_r * 0.11
	stm.height = body_r * 2.3
	stm.radial_segments = 7
	stalk.mesh = stm
	stalk.material_override = _slick(skin.lightened(0.18))
	stalk.position = Vector3(0, body_r * 1.15, 0)
	_mouth.add_child(stalk)
	# the tip: a small split cap that works when it speaks
	for sgn in [-1.0, 1.0]:
		var lip := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(body_r * 0.1, body_r * 0.26, body_r * 0.07)
		lip.mesh = lm
		lip.material_override = _slick(Color("#5d4a35"))
		lip.position = Vector3(sgn * body_r * 0.055, body_r * 2.38, 0)
		lip.rotation_degrees = Vector3(0, 0, sgn * 9.0)
		_mouth.add_child(lip)

	# a body for the crosshair to find, so F reaches them at all
	var hit := StaticBody3D.new()
	hit.collision_layer = 1
	hit.collision_mask = 0
	var hcs := CollisionShape3D.new()
	var hsh := SphereShape3D.new()
	hsh.radius = body_r * 1.15
	hcs.shape = hsh
	hit.add_child(hcs)
	add_child(hit)

	_bubble = Label3D.new()
	_bubble.font_size = 24
	_bubble.pixel_size = 0.0075
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.modulate = Color("#d9ff9a")
	_bubble.outline_size = 10
	_bubble.outline_modulate = Color(0, 0, 0, 0.9)
	_bubble.width = 420
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.no_depth_test = true
	_bubble.render_priority = 10
	_bubble.position = Vector3(0, body_r * 3.4, 0)
	_bubble.visible = false
	add_child(_bubble)

static func _basis_from_up(up: Vector3) -> Basis:
	var u := up.normalized()
	var x := u.cross(Vector3(0, 1, 0))
	if x.length() < 0.01:
		x = u.cross(Vector3(1, 0, 0))
	x = x.normalized()
	return Basis(x, u, x.cross(u).normalized())

func _slick(c: Color) -> StandardMaterial3D:
	# wet, always. Low roughness and a rim of its own light, because
	# everything on this planet is covered in the same stuff.
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.62 if dead else 0.14
	m.metallic = 0.0
	m.metallic_specular = 0.9   # `specular` is the Godot 3 name: setting
								# it goes through the compat remapper and
								# warns once for every material made
	m.emission_enabled = true
	m.emission = Color("#3f6a12")
	m.emission_energy_multiplier = 0.0 if dead else 0.12
	return m

# ------------------------------------------------------------ behaviour

func _process(delta: float) -> void:
	if dead:
		return
	_t += delta
	var b = Universe.body_named(home_name)
	if b == null:
		return
	_up = Universe.surface_up(b, global_position)

	# THEY LIVE ON THE SURFACE. Not cruising about underneath it: an
	# Echegel sits on top of its continent and shuffles around, and
	# every so often it decides to go, drops straight through in a
	# quarter of a second, and comes back up. Continuous swimming made
	# octopuses of them.
	if not Universe.slime_contains(b, global_position) and _swim.length() > 0.01:
		var inward: Vector3 = b.center - global_position
		inward = inward - _up * inward.dot(_up)
		if inward.length() > 0.01:
			_swim = inward.normalized()
	elif _swim.length() < 0.01 or _rng.randf() < delta * 0.35:
		var side := _up.cross(Vector3(0.3, 1, 0.7))
		if side.length() < 0.2:
			side = _up.cross(Vector3(1, 0, 0))
		side = side.normalized()
		var fwd := _up.cross(side).normalized()
		_swim = (side * _rng.randf_range(-1, 1)
			+ fwd * _rng.randf_range(-1, 1)).normalized()
	# a shuffle on top; a surge while it is going down or coming up
	global_position += _swim * delta * (1.1 + _dive * 0.9)

	# THE PLUNGE. Nothing for a long while, then all at once: down in
	# about a fifth of a second, a beat under the slime, and back out
	# just as fast.
	_dive_cd -= delta
	match _phase:
		SURFACED:
			if _dive_cd <= 0.0:
				_phase = DOWN
				Sfx.play("break", -24.0)
		DOWN:
			_dive = minf(1.0, _dive + delta * 5.2)
			if _dive >= 1.0:
				_phase = UNDER
				_under_t = _rng.randf_range(0.7, 2.6)
		UNDER:
			_under_t -= delta
			if _under_t <= 0.0:
				_phase = UP
		UP:
			_dive = maxf(0.0, _dive - delta * 4.4)
			if _dive <= 0.0:
				_phase = SURFACED
				_dive_cd = _rng.randf_range(7.0, 22.0)

	# ride the skin, minus however far through it currently is
	var alt := Universe.altitude(b, global_position)
	var want := body_r * 0.42 - _dive * body_r * 3.0
	global_position += _up * (want - alt) * minf(1.0, delta * 8.0)
	var fw := _swim - _up * _swim.dot(_up)
	if fw.length() > 0.01:
		look_at_from_position(global_position, global_position + fw.normalized(),
			_up)

	_animate(delta)
	_talk(delta)

func _animate(delta: float) -> void:
	for t in _tents:
		# idling on the surface the arms barely move; going through the
		# slime they haul, which is the only time they look like the
		# thing doing the work
		var work: float = _dive if _phase != SURFACED else 0.0
		var ph: float = float(t["ph"]) + _t * (1.5 + work * 6.5)
		var segs: Array = t["segs"]
		for k in segs.size():
			var seg: MeshInstance3D = segs[k]
			if not is_instance_valid(seg):
				continue
			# each segment lags the one above it: the whole arm curls
			var amp := (5.0 + float(k) * 2.5) * (1.0 + work * 3.4)
			var curl := sin(ph - float(k) * 0.7) * amp
			seg.rotation_degrees = Vector3(curl, 0,
				cos(ph - float(k) * 0.5) * 4.0 * (1.0 + work * 2.2))
	if _disk != null:
		# the body pulses as it works, because a thing made of slime
		# does not hold a shape
		var s := 1.0 + 0.055 * sin(_t * 2.4)
		_disk.scale = Vector3(1.28 * s, 2.0 - s, 1.28 * s)
	# the words land the moment the stick is all the way out
	if _pending != "" and _mouth_out > 0.93:
		_bubble.text = _pending
		_bubble.visible = true
		_bubble_t = 5.0
		_bubble.modulate.a = 1.0
		_bubble.outline_modulate.a = 1.0
		_pending = ""
	if _mouth != null:
		# EXTEND TO SPEAK, retract when done -- and while it is out it
		# reaches up out of the slime even if the body is under, because
		# that is the part they talk with
		_mouth_hold = maxf(0.0, _mouth_hold - delta)
		var want := 1.0 if _mouth_hold > 0.0 else 0.0
		# SLOWLY out, and slower back. It used to snap out in a fifth of
		# a second, which is a mechanism, not a creature deciding to
		# speak to you.
		_mouth_out = move_toward(_mouth_out, want,
			delta * (1.15 if want > 0.0 else 0.7))
		var ease := _mouth_out * _mouth_out * (3.0 - 2.0 * _mouth_out)
		_mouth.scale = Vector3(1.0, lerpf(MOUTH_IN, 1.0, ease), 1.0)
		_mouth.position = Vector3(0, _dive * body_r * 1.6 * ease, 0)
		_mouth.rotation_degrees = Vector3(sin(_t * 0.7) * 7.0 * ease, 0,
			cos(_t * 0.9) * 5.0 * ease)

func _talk(delta: float) -> void:
	if _bubble_t > 0.0:
		_bubble_t -= delta
		_bubble.modulate.a = clampf(_bubble_t / 0.9, 0.0, 1.0)
		_bubble.outline_modulate.a = _bubble.modulate.a
		if _bubble_t <= 0.0:
			_bubble.visible = false
	var pl = get_tree().get_first_node_in_group("player")
	if pl == null or not is_instance_valid(pl):
		return
	# CLOSE, and only if it feels like it. Thirty-four metres was most
	# of a continent away -- they were talking at nobody.
	var d: float = global_position.distance_to(pl.global_position)
	if d > TALK_RANGE:
		return
	_talk_cd -= delta
	if _talk_cd > 0.0:
		return
	_talk_cd = _rng.randf_range(9.0, 26.0)
	# and it is a decision, not a timer going off
	if _rng.randf() < 0.55:
		say(sentence(_rng))

## F ON AN ECHEGEL. It decides to answer you -- the stick comes out and
## it says something, generated fresh, the way everything they say is.
## The one thing it will not do is be helpful.
func use() -> void:
	if dead:
		return
	_talk_cd = _rng.randf_range(4.0, 10.0)
	say(sentence(_rng))

## Put something in the bubble. Any caller can hand it a line; left to
## itself it generates one.
func say(line: String) -> void:
	if _bubble == null:
		return
	# THE MOUTH GOES FIRST. It comes out, and only once it is out do the
	# words arrive -- saying it while the stick is still unfolding puts
	# the sentence in the air before the thing that makes it.
	_pending = line
	_mouth_hold = 7.0

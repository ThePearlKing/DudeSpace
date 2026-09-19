class_name Echegel
extends Node3D
## AN ECHEGEL. A disk of wet meat with a ring of tentacles under it and
## one thin stick of a mouth sticking up out of the slime.
##
## They live IN the continents rather than on them, and they swim
## through the slime the way you would swim through water -- tentacles
## working, whole body under, the mouth left above the surface because
## that is the part they eat and talk with. Most of the time the only
## Echegel you can see is a stick.
##
## Seven tentacles is the common count. Six and ten both happen.
##
## Their speech sounds like English right up until you try to write it
## down. Real words in real places, and then something that is not a
## word at all sitting where a noun should be. Nobody has worked out
## whether the numbers are grammar or names or swearing; two of them
## turn up often enough in arguments that it is probably swearing.

const TENT_MIN := 6
const TENT_MAX := 10

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
var _dive_goal: float = 0.0
var _dive_cd: float = 0.0
var _talk_cd: float = 0.0
var _swim: Vector3 = Vector3.ZERO
var _up: Vector3 = Vector3.UP

# ------------------------------------------------------------ language
## The words that are words. Short, common, and load-bearing -- it is
## the frame around the parts you cannot read that makes it sound like
## a language instead of a keyboard falling over.
const REAL := ["at", "we", "our", "you", "your", "this", "is", "was",
	"the", "and", "in", "for", "my", "it", "not", "to", "with", "on",
	"they", "he", "has", "who", "here", "off", "get", "give", "take",
	"go", "come", "do", "are", "all", "no", "yes", "up", "down", "his"]
## Tokens that recur often enough to be vocabulary rather than noise.
## Two of these are almost certainly swearing.
const CANON := ["q9", "03", "i2", "39", "7eh", "219", "m03r2n", "sh21",
	"i90o", "Ex23", "0g", "r2", "9th", "z04", "e7", "13o"]
## Words that cannot be the last one in a sentence.
const PARTICLES := ["at", "to", "in", "on", "up", "down", "off", "for",
	"with", "and", "is", "was", "the", "are", "has", "do", "go", "my",
	"our", "your", "his"]
const STEMS := ["m", "r", "n", "sh", "z", "k", "th", "gr", "fl", "q",
	"v", "br", "ch", "dr", "st"]
const TAILS := ["eh", "o", "a", "us", "en", "ir", "ol", "ak", "im", "un"]

## One Echegel word. Half the time it is a word you have heard them use
## before; the rest of the time it is built the way those were.
static func word(rng: RandomNumberGenerator) -> String:
	if rng.randf() < 0.45:
		return CANON[rng.randi() % CANON.size()]
	var w := ""
	if rng.randf() < 0.55:
		w += str(rng.randi_range(0, 9))
	w += STEMS[rng.randi() % STEMS.size()]
	if rng.randf() < 0.7:
		w += str(rng.randi_range(0, 99))
	if rng.randf() < 0.6:
		w += TAILS[rng.randi() % TAILS.size()]
	if rng.randf() < 0.25:
		w += str(rng.randi_range(0, 9))
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
	_dive_cd = _rng.randf_range(4.0, 16.0)
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

func _build() -> void:
	# SLUG. Ochre-brown, wet, and faintly green from living inside a
	# lime continent -- whatever they are, they have taken the colour of
	# the stuff they swim in.
	var skin := Color("#8d8354").lerp(Color("#7fa03a"), _rng.randf_range(0.2, 0.45))
	if dead:
		# the colour goes out of them first, and then the shine
		skin = skin.lerp(Color("#6a6a63"), 0.72)
	var mat := _slick(skin)

	_disk = MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = body_r
	dm.height = body_r * 1.05   # a DISK, not a ball
	dm.radial_segments = 18
	dm.rings = 10
	_disk.mesh = dm
	_disk.material_override = mat
	add_child(_disk)
	# a darker mantle across the top, the way a slug has a saddle
	var mant := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = body_r * 0.72
	mm.height = body_r * 0.66
	mant.mesh = mm
	mant.material_override = _slick(skin.darkened(0.3))
	mant.position = Vector3(0, body_r * 0.16, 0)
	add_child(mant)

	# TENTACLES. Seven is the usual answer. They hang under the disk and
	# they are what it moves with -- each one a little chain that curls.
	var n := TENT_MIN + _rng.randi() % (TENT_MAX - TENT_MIN + 1)
	if _rng.randf() < 0.5:
		n = 7
	for i in n:
		var a := TAU * float(i) / float(n)
		var arm := Node3D.new()
		arm.position = Vector3(cos(a) * body_r * 0.72, -body_r * 0.14,
			sin(a) * body_r * 0.72)
		add_child(arm)
		var segs: Array = []
		var prev := arm
		for k in 4:
			var seg := MeshInstance3D.new()
			var sm := CapsuleMesh.new()
			sm.radius = body_r * (0.16 - float(k) * 0.026)
			sm.height = body_r * 0.5
			sm.radial_segments = 7
			seg.mesh = sm
			seg.material_override = mat   # one arm material, not one per joint
			seg.position = Vector3(0, -body_r * 0.34, 0)
			prev.add_child(seg)
			segs.append(seg)
			prev = seg
		_tents.append({"segs": segs, "ph": _rng.randf() * TAU,
			"dir": Vector3(cos(a), 0, sin(a))})

	# THE MOUTH. A stick. It comes up out of the slime and it is the
	# only part of them most visitors ever see: they eat with it and
	# they talk with it and it does not look like it should do either.
	_mouth = Node3D.new()
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

func _slick(c: Color) -> StandardMaterial3D:
	# wet, always. Low roughness and a rim of its own light, because
	# everything on this planet is covered in the same stuff.
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.62 if dead else 0.14
	m.metallic = 0.0
	m.specular = 0.9
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

	# SWIM. Tentacles working, body wandering across the slime, never in
	# a straight line for long.
	if _swim.length() < 0.01 or _rng.randf() < delta * 0.25:
		var side := _up.cross(Vector3(0.3, 1, 0.7))
		if side.length() < 0.2:
			side = _up.cross(Vector3(1, 0, 0))
		side = side.normalized()
		var fwd := _up.cross(side).normalized()
		_swim = (side * _rng.randf_range(-1, 1)
			+ fwd * _rng.randf_range(-1, 1)).normalized()
	global_position += _swim * delta * 2.4

	# DIVE. They go under and come back up somewhere else; the stick
	# stays above the surface a moment longer than the rest of them.
	_dive_cd -= delta
	if _dive_cd <= 0.0:
		_dive_cd = _rng.randf_range(6.0, 20.0)
		_dive_goal = 1.0 if _dive_goal < 0.5 else 0.0
	_dive = move_toward(_dive, _dive_goal, delta * 0.55)

	# ride the surface: the body sits at skin level, minus however far
	# it has sunk itself
	var alt := Universe.altitude(b, global_position)
	var want := body_r * 0.35 - _dive * body_r * 2.1
	global_position += _up * (want - alt) * minf(1.0, delta * 4.0)
	# upright on the slime, whichever way "up" is out here
	var fw := _swim - _up * _swim.dot(_up)
	if fw.length() > 0.01:
		look_at_from_position(global_position, global_position + fw.normalized(),
			_up)

	_animate(delta)
	_talk(delta)

func _animate(delta: float) -> void:
	for t in _tents:
		var ph: float = float(t["ph"]) + _t * 3.1
		var segs: Array = t["segs"]
		for k in segs.size():
			var seg: MeshInstance3D = segs[k]
			if not is_instance_valid(seg):
				continue
			# each segment lags the one above it: the whole arm curls
			var curl := sin(ph - float(k) * 0.7) * (9.0 + float(k) * 4.0)
			seg.rotation_degrees = Vector3(curl, 0, cos(ph - float(k) * 0.5) * 6.0)
	if _disk != null:
		# the body pulses as it works, because a thing made of slime
		# does not hold a shape
		var s := 1.0 + 0.055 * sin(_t * 2.4)
		_disk.scale = Vector3(s, 2.0 - s, s)
	if _mouth != null:
		# the stick stays up even while the body goes under
		_mouth.position = Vector3(0, _dive * body_r * 1.6, 0)
		_mouth.rotation_degrees = Vector3(sin(_t * 0.7) * 7.0, 0,
			cos(_t * 0.9) * 5.0)

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
	var d: float = global_position.distance_to(pl.global_position)
	if d > 34.0:
		return
	_talk_cd -= delta
	if _talk_cd > 0.0:
		return
	_talk_cd = _rng.randf_range(6.0, 18.0)
	say(sentence(_rng))

## Put something in the bubble. Any caller can hand it a line; left to
## itself it generates one.
func say(line: String) -> void:
	if _bubble == null:
		return
	_bubble.text = line
	_bubble.visible = true
	_bubble_t = 5.0
	_bubble.modulate.a = 1.0
	_bubble.outline_modulate.a = 1.0
	# the mouth works while it speaks, which is the unsettling part
	var tw := create_tween()
	tw.tween_property(_mouth, "scale", Vector3(1.0, 1.22, 1.0), 0.12)
	tw.tween_property(_mouth, "scale", Vector3.ONE, 0.18)

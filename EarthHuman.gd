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
	"RECOVERING FROM", "VOTED MOST"]
const SHIRT_B := ["MY OWN", "THE MOON'S", "YESTERDAY'S", "AN UNPAID",
	"A SUSPICIOUS", "THE THIRD", "SOMEBODY'S", "MY DOCTOR'S", "GRAVITY'S",
	"AN IMAGINARY", "ONE (1)"]
const SHIRT_C := ["OPINIONS", "SOUP", "REGRET", "NAP", "LADDER", "PARADE",
	"HAIRCUT", "BUSINESS PLAN", "NOODLE", "MISTAKE", "SANDWICH", "HOMEWORK",
	"DESTINY", "KNEES", "PONYTAIL", "LASAGNA", "PIGEON", "TAXES"]

## Personality axes, 0-100 each. Faces carry these values (set in the
## F9 editor); a human wearing a face THINKS like that face.
const AXES := ["anxious", "confident", "dreamy", "dumb", "grumpy", "goofy", "edgy", "awkward"]

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

var _home = null            # Universe body we live on
var _pers: Dictionary = {}  # axis -> 0..100, from the face's sidecar
var _body: Human
var _dir: Vector3 = Vector3.ZERO
var _act: String = "wander"
var _act_t: float = 0.0
var _panic_t: float = 0.0
var _bubble: Label3D
var _bubble_t: float = 0.0
var _grounded: bool = false

func setup(home_body) -> void:
	_home = home_body

func _ready() -> void:
	add_to_group("earth_human")
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
	var skin := Color.from_hsv(randf_range(0.05, 0.09),
		randf_range(0.25, 0.55), randf_range(0.35, 0.95))
	# a random face from the hand-drawn pool -- and its PERSONALITY.
	# the face IS the soul: its editor-set weights shape thought and deed.
	var fc := EarthHuman.random_face()
	_body.build(skin, "none", fc.get("tex", null))
	var fp = fc.get("pers", {})
	for ax in AXES:
		_pers[ax] = float(fp.get(ax, randf_range(10.0, 45.0)))
	# proportions: RANDOMIZED. most humans look normal. some rolled badly
	# at the character screen of life and are living with it.
	_body.scale = Vector3(randf_range(0.92, 1.04), randf_range(0.85, 1.05),
		randf_range(0.92, 1.04))
	if randf() < 0.3:
		if randf() < 0.6 and is_instance_valid(_body._torso):
			_body._torso.scale = Vector3(randf_range(1.1, 1.35), 1.0,
				randf_range(1.1, 1.45))   # the belly
		if randf() < 0.5 and is_instance_valid(_body._head_m):
			_body._head_m.scale = Vector3.ONE * randf_range(1.15, 1.5)
		if randf() < 0.5:
			_body.rotation_degrees.x = randf_range(3.0, 8.0)   # the slouch
		if randf() < 0.4:
			_body.scale.y *= randf_range(0.72, 0.85)   # the squat persists
	_dress_human()

## Wardrobe: random t-shirt + pants + hair. Shirts come plain, with a
## "design", or with an assembled slogan. All of it committee-approved
## by no committee.
func _dress_human() -> void:
	var shirt_col := Color.from_hsv(randf(), randf_range(0.4, 0.9), randf_range(0.35, 0.95))
	var pants_col: Color = [Color("#2b3a5e"), Color("#1e1e24"), Color("#4a3a28"),
		Color("#3a4a3a"), Color("#6e6e74"), Color("#5e2b2b")][randi() % 6]
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
	var roll := randf()
	if roll < 0.35:
		pass   # basic. a classic. says nothing, means nothing.
	elif roll < 0.65 and is_instance_valid(_body._torso):
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
		var slogan := Label3D.new()
		slogan.text = words
		slogan.font_size = 34
		slogan.pixel_size = 0.004
		slogan.width = 200.0
		slogan.autowrap_mode = TextServer.AUTOWRAP_WORD
		slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slogan.modulate = Color.WHITE if shirt_col.get_luminance() < 0.5 else Color("#1a1a1a")
		slogan.position = Vector3(0, 0.05, -0.24)
		_body._torso.add_child(slogan)

	# hair: one style from the rack, one colour from the bottle
	if not is_instance_valid(_body._head_m):
		return
	var hair_col: Color = [Color("#1a1410"), Color("#4a3018"), Color("#c8a050"),
		Color("#8a3a1a"), Color("#b8b8bc"), Color("#d84aa0")][
		randi() % 6 if randf() > 0.05 else 5]   # 5% dyed pink, as is right
	var hmat := Destructible.make_material(hair_col, 0.05)
	match randi() % 6:
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

	_bubble = Label3D.new()
	_bubble.font_size = 22
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.position = Vector3(0, 1.6, 0)
	_bubble.modulate = Color(1, 1, 1, 0.0)
	_bubble.outline_size = 8
	_bubble.width = 420
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_bubble)

	_pick_act()

func _pick_act() -> void:
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
	if _home == null:
		return Vector3.UP
	return (global_position - _home.center).normalized()

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
	_bubble.text = lines[randi() % lines.size()]
	_bubble_t = 4.5
	Sfx.play("click", -20.0)

func take_damage(_dmg: float, dir: Vector3) -> void:
	# violence: observably effective, emotionally complicated
	_panic_t = 5.0
	_dir = (dir - _up() * dir.dot(_up())).normalized()
	_bubble.text = "WHY"
	_bubble_t = 2.0
	Sfx.play("hurt", -16.0)

func _physics_process(delta: float) -> void:
	if _home == null:
		return
	var up := _up()
	var g := Universe.gravity_at(global_position)

	# thought bubble fades like the thought itself
	if _bubble_t > 0.0:
		_bubble_t -= delta
		_bubble.modulate.a = clampf(_bubble_t / 0.8, 0.0, 1.0)

	_act_t -= delta
	if _act_t <= 0.0 and _panic_t <= 0.0:
		_pick_act()

	var speed := 0.0
	if _panic_t > 0.0:
		_panic_t -= delta
		speed = PANIC_SPEED
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

	var v_up := velocity.dot(up)
	v_up += g.dot(up) * delta
	# scared humans LEAP as they flee -- brief panicked flight, the
	# ground leash still keeps them out of orbit
	if _panic_t > 0.0 and _grounded and randf() < 0.09:
		v_up = randf_range(4.5, 6.5)
	velocity = _dir * speed + up * v_up
	up_direction = up
	move_and_slide()
	_grounded = is_on_floor()
	# hard leash: whatever physics thinks it's doing, a Human belongs on
	# the ground. no accidental astronauts.
	var alt: float = global_position.distance_to(_home.center) - _home.radius
	if alt > 3.0:
		global_position = _home.center + up * (_home.radius + 1.1)
		velocity = Vector3.ZERO

	# face where we walk, feet planted along gravity
	if speed > 0.1 and _dir.length() > 0.1:
		var x := up.cross(_dir).normalized()
		global_transform.basis = Basis(x, up, -_dir).orthonormalized()
	if _body:
		_body.animate(speed, _grounded, delta)

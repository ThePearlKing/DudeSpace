class_name Animal
extends CharacterBody3D
## A harmless procedural critter. Wanders its planet's surface and flees
## when you get close. Shoot it for coins + a little food (heal).

const WANDER_SPEED := 4.0
const FLEE_SPEED := 9.0
const FLEE_RANGE := 14.0

var _home
var hp: float = 24.0
var _dir: Vector3 = Vector3.ZERO
var _retarget: float = 0.0
var _mats: Array[StandardMaterial3D] = []
var _flash: float = 0.0
var _limbs: Array = []
var _walk_t: float = 0.0
var _flier: bool = false
var _hopper: bool = false
var _ground_only: bool = false
var _hop_t: float = 0.0
var tamed: bool = false
var minded: bool = false               # neuralink: the chip drives
var mind_dir: Vector3 = Vector3.ZERO

## Called when released from a cage on a (possibly different) planet.
func rehome(body) -> void:
	_home = body
	velocity = Vector3.ZERO

var staying: bool = false

## Right-click a pet with anything non-food: sit / follow toggle.
func toggle_stay() -> void:
	staying = not staying
	Sfx.play("click")
	# sit animation: haunches down, nose up (and back again)
	var tw := create_tween()
	if staying:
		tw.tween_property(_mesh_holder(), "rotation:x", -0.35, 0.3)
		tw.parallel().tween_property(_mesh_holder(), "position:y", -0.15, 0.3)
	else:
		tw.tween_property(_mesh_holder(), "rotation:x", 0.0, 0.3)
		tw.parallel().tween_property(_mesh_holder(), "position:y", 0.0, 0.3)

var _holder: Node3D

func _mesh_holder() -> Node3D:
	if _holder == null:
		# re-parent all visuals under one node we can pose
		_holder = Node3D.new()
		add_child(_holder)
		for c in get_children():
			if c is MeshInstance3D:
				c.reparent(_holder)
	return _holder

## Knife: an animal is a few meats waiting to happen.
func harvest() -> void:
	Destructible.spawn_debris(get_parent(), global_position + Vector3(0, 0.5, 0),
		Vector3(0.6, 0.6, 0.6), Color("#c05050"), Vector3.UP)
	Inventory.add_res("meat", randi_range(2, 4))
	Sfx.play("hurt", -14.0)
	queue_free()

func tame() -> void:
	tamed = true
	add_to_group("pet")
	Save.set_pet(true, genome, staying)   # never lose a friend to timing
	# a little heart. it loves you now.
	var h := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.15
	m.height = 0.3
	h.mesh = m
	h.material_override = Destructible.make_material(Color("#ff4d88"), 4.0)
	h.position = Vector3(0, 1.6, 0)
	add_child(h)
	Sfx.play("eat")

var _bug: bool = false
var _fly_chase: bool = false
var genome: int = -1   # deterministic body seed: same genome = same animal

func setup(home_body, ground_only: bool = false, bug: bool = false, genome_in: int = -1) -> void:
	_home = home_body
	_ground_only = ground_only
	_bug = bug
	genome = genome_in if genome_in >= 0 else randi() % 1000000000

func _ready() -> void:
	add_to_group("animal")
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.2 * (0.35 if _bug else 1.0)
	cap.radius = 0.4 * (0.35 if _bug else 1.0)
	col.shape = cap
	add_child(col)
	_build()
	if _bug:
		# TINY mushroom-floor bug: strictly a land animal
		for c in get_children():
			if c is MeshInstance3D:
				c.position *= 0.18
				c.scale *= 0.18
		hp = 6.0
		_flier = false
		_hopper = true

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = genome
	# Procedural SPECIES: bilaterally symmetric body plan (real creatures
	# are). Random proportions, leg-pair count, tail, antennae -> endless
	# variety that still reads as an animal, not a cursed pile.
	var c := Color.from_hsv(rng.randf(), rng.randf_range(0.4, 0.8), rng.randf_range(0.7, 1.0))
	var body_l := rng.randf_range(0.8, 1.8)     # length (Z)
	var body_w := rng.randf_range(0.4, 0.9)
	var body_h := rng.randf_range(0.35, 0.8)
	var stance := rng.randf_range(0.35, 0.75)   # body height off ground
	_part(Vector3(body_w, body_h, body_l), Vector3(0, stance + body_h * 0.5, 0), c, 0.2)

	# head at the front, eyes as a PAIR
	var head_s := rng.randf_range(0.3, 0.6)
	var head_y := stance + body_h * rng.randf_range(0.5, 1.1)
	var head_z := -body_l * 0.5 - head_s * 0.4
	_part(Vector3(head_s, head_s, head_s), Vector3(0, head_y, head_z), c.lightened(0.15), 0.2)
	for sx in [-1.0, 1.0]:
		_part(Vector3(0.1, 0.1, 0.06), Vector3(sx * head_s * 0.28, head_y + head_s * 0.12, head_z - head_s * 0.5), Color("#101010"), 0.0)

	# 1-3 LEG PAIRS, mirrored, antiphase left/right = a real gait
	var pairs := rng.randi_range(1, 3)
	var leg_l := stance + 0.15
	var leg_t := rng.randf_range(0.1, 0.22)
	for pi2 in pairs:
		var z := lerpf(-body_l * 0.35, body_l * 0.35, (float(pi2) + 0.5) / float(pairs))
		for side in [-1.0, 1.0]:
			var mi := _part(Vector3(leg_t, leg_l, leg_t), Vector3(side * (body_w * 0.5 + leg_t * 0.4), stance - leg_l * 0.5 + 0.15, z), c.darkened(0.2), 0.1)
			_limbs.append({
				"node": mi, "base": mi.rotation,
				"phase": (0.0 if side < 0 else PI) + float(pi2) * 0.9,
				"amp": rng.randf_range(0.25, 0.5), "axis": 0,
			})

	# optional tail
	if rng.randf() < 0.7:
		var tl := rng.randf_range(0.4, 1.1)
		var mi := _part(Vector3(0.14, 0.14, tl), Vector3(0, stance + body_h * 0.6, body_l * 0.5 + tl * 0.4), c.darkened(0.1), 0.1)
		mi.rotation.x = rng.randf_range(0.2, 0.6)
		_limbs.append({"node": mi, "base": mi.rotation, "phase": rng.randf() * TAU, "amp": rng.randf_range(0.15, 0.4), "axis": 1})

	# optional paired antennae / horns
	if rng.randf() < 0.5:
		for sx in [-1.0, 1.0]:
			var mi := _part(Vector3(0.06, rng.randf_range(0.3, 0.7), 0.06), Vector3(sx * head_s * 0.25, head_y + head_s * 0.7, head_z), c.lightened(0.3), 0.4)
			_limbs.append({"node": mi, "base": mi.rotation, "phase": rng.randf() * TAU, "amp": 0.2, "axis": 2})

	# forest spawns stay grounded (walkers + tiny hoppers); everything
	# born outside a forest FLIES -- skies full of nonsense around the planet.
	_flier = not _ground_only
	_hopper = _ground_only and rng.randf() < 0.6
	if _flier:
		for sx in [-1.0, 1.0]:
			var wing := _part(Vector3(rng.randf_range(0.8, 1.4), 0.06, rng.randf_range(0.4, 0.7)),
				Vector3(sx * (body_w * 0.5 + 0.5), stance + body_h * 0.9, 0), c.lightened(0.4), 0.5)
			_limbs.append({"node": wing, "base": wing.rotation, "phase": 0.0 if sx < 0 else 0.0, "amp": 0.9, "axis": 2})

func _part(sz: Vector3, pos: Vector3, c: Color, e: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m
	mi.position = pos
	var mat := Destructible.make_material(c, e)
	mi.material_override = mat
	add_child(mi)
	_mats.append(mat)
	return mi

var orbit_t: float = 0.0   # orbit-wand freefall: gravity only, no AI
var orbit_boost: bool = false   # circularize at the top of the arc

func _physics_process(delta: float) -> void:
	if orbit_t > 0.0:
		orbit_t -= delta
		velocity += Universe.gravity_at(global_position) * delta
		if orbit_boost:
			var ob = Universe.nearest(global_position)
			var oup: Vector3 = (global_position - ob.center).normalized()
			var alt: float = global_position.distance_to(ob.center)
			if alt > ob.radius * 1.15 and velocity.dot(oup) <= 0.0:
				var vt := velocity - oup * velocity.dot(oup)
				if vt.length() < 0.5:
					vt = oup.cross(Vector3.UP)
					if vt.length() < 0.05:
						vt = oup.cross(Vector3.RIGHT)
				velocity = vt.normalized() * sqrt(ob.g_surf * ob.radius * ob.radius / alt)
				orbit_boost = false
		move_and_slide()
		if is_on_floor():
			orbit_t = 0.0
		_home = Universe.nearest(global_position)
		return
	if tamed:
		# pets re-home to whatever planet they're on now
		_home = Universe.nearest(global_position)
	var g: float = _home.g_surf
	var up := Universe.surface_up(_home, global_position)
	_align_up(up)

	_retarget -= delta
	var spd := WANDER_SPEED
	var p := get_tree().get_first_node_in_group("player")
	_fly_chase = false
	if minded:
		# neuralink passenger seat: steering wheel installed
		_dir = (mind_dir - up * mind_dir.dot(up)).normalized() \
			if mind_dir.length() > 0.1 else Vector3.ZERO
		spd = FLEE_SPEED * 0.8
		_retarget = 1.0
	elif tamed and staying:
		# sitting. not going anywhere. very good pet.
		_dir = Vector3.ZERO
		_retarget = 0.5
	elif tamed and p:
		var to_p: Vector3 = p.global_position - global_position
		# owner jetpacking overhead? wings out, buddy comes UP
		_fly_chase = to_p.dot(up) > 4.0
		if to_p.length() > 40.0:
			# too far: pop over to your side. loyalty beats physics.
			global_position = p.global_position + up * 1.0
			velocity = Vector3.ZERO
			return
		elif to_p.length() > 5.0:
			_dir = (to_p - up * to_p.dot(up)).normalized()
			spd = FLEE_SPEED
			_retarget = 0.3
		else:
			_dir = Vector3.ZERO
			_retarget = 0.5
	elif p and Game.mode == Game.Mode.ON_FOOT:
		var away: Vector3 = global_position - p.global_position
		if away.length() < FLEE_RANGE:
			_dir = (away - up * away.dot(up)).normalized()
			spd = FLEE_SPEED
			_retarget = 0.4
	if _retarget <= 0.0:
		var a := randf() * TAU
		var t1 := up.cross(Vector3(0, 1, 0))
		if t1.length() < 0.01:
			t1 = up.cross(Vector3(1, 0, 0))
		t1 = t1.normalized()
		var t2 := up.cross(t1).normalized()
		_dir = (t1 * cos(a) + t2 * sin(a)).normalized()
		_retarget = randf_range(1.5, 3.5)

	if _dir.length() > 0.1:
		global_transform.basis = _basis_from(_dir, up)

	var v_up := velocity.dot(up)
	if is_on_floor():
		v_up = maxf(v_up, 0.0)
	if _flier:
		# constant frantic hops = "flight". flap rate matches.
		_hop_t -= delta
		if _hop_t <= 0.0 and is_on_floor():
			_hop_t = randf_range(0.3, 0.8)
			v_up = randf_range(4.0, 8.0)
	elif _hopper and is_on_floor() and _dir.length() > 0.1:
		# tiny low-force hops: forest floor scuttlers
		_hop_t -= delta
		if _hop_t <= 0.0:
			_hop_t = randf_range(0.5, 1.3)
			v_up = randf_range(1.0, 2.0)
	if _fly_chase:
		# any tamed animal sprouts the will to fly when you're overhead
		v_up = minf(v_up + 14.0 * delta, 9.0)
	v_up -= g * delta * (0.4 if (_flier or _fly_chase) else 1.0)
	velocity = _dir * spd + up * v_up
	up_direction = up
	move_and_slide()

	# limbs writhe as it moves, in whatever way its body decided is walking
	_walk_t += delta * (1.5 + spd * 0.5)
	for l in _limbs:
		var ln: MeshInstance3D = l["node"]
		if not is_instance_valid(ln):
			continue
		var w: float = sin(_walk_t + float(l["phase"])) * float(l["amp"])
		var rot: Vector3 = l["base"]
		match int(l["axis"]):
			0: rot.x += w
			1: rot.y += w
			2: rot.z += w
		ln.rotation = rot

	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
		for m in _mats:
			m.emission_energy_multiplier = 0.2 + _flash * 4.0

func take_damage(d: float, push_dir: Vector3) -> void:
	hp -= d
	_flash = 1.0
	if hp <= 0.0:
		var up: Vector3 = (global_position - _home.center).normalized()
		Destructible.spawn_debris(get_parent(), global_position + Vector3(0, 0.5, 0), Vector3(0.6, 0.6, 0.6), _mats[0].albedo_color if _mats.size() > 0 else Color.WHITE, push_dir if push_dir.length() > 0.1 else up)
		Game.heal(10.0)
		Game.register_break(Vector3(1.5, 1.5, 1.5), 8)
		queue_free()

func _align_up(up: Vector3) -> void:
	var cur := global_transform.basis.y
	var axis := cur.cross(up)
	var ang := cur.angle_to(up)
	if axis.length() > 0.0001 and ang > 0.0001:
		global_transform.basis = Basis(axis.normalized(), ang) * global_transform.basis
		global_transform.basis = global_transform.basis.orthonormalized()

func _basis_from(forward: Vector3, up: Vector3) -> Basis:
	var z := -forward.normalized()
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z).orthonormalized()

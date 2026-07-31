class_name Enemy
extends CharacterBody3D
## A procedurally-built evil alien. Walks the surface of its planet under
## local gravity, chases the on-foot player, and melees them. Higher
## level = more HP, damage, speed, and size. Killed by weapons -> coins.

const AGGRO := 55.0
const ATTACK_RANGE := 3.2
const ATTACK_CD := 1.0

var level: int = 1
var hp: float = 30.0
var dmg: float = 8.0
var speed: float = 6.0
var pyramid: bool = false
var tank: bool = false           # green illuminati pyramid: slow, huge HP
var shooter: bool = false        # late game: shoots fast, led projectiles
var flyer: bool = false          # late game: ignores the floor entirely
var burst: int = 1               # bolts per volley
var _home
var _cd: float = 0.0
var _shot_cd: float = 0.0
var _bob_t: float = 0.0
var _mesh_root: Node3D
var _mats: Array[StandardMaterial3D] = []
var _flash: float = 0.0
var _limbs: Array = []       # [{node, base, phase, amp, axis}]
var _walk_t: float = 0.0

func setup(lvl: int, home_body, pyr: bool = false, as_tank: bool = false) -> void:
	level = lvl
	_home = home_body
	pyramid = pyr
	tank = as_tank
	if pyr:
		# temple guardians: jetpack-proof. they fly, they volley.
		hp = 50.0 + float(lvl) * 35.0
		dmg = 8.0 + float(lvl) * 5.0
		speed = 7.0 + float(lvl) * 1.8
		flyer = true
		shooter = true
		burst = 3
		speed *= 2.2   # airborne pursuit must out-run a jetpack
		if tank:
			# the green one: a wall with an eye. slow. barely killable.
			hp *= 3.5
			dmg *= 1.5
			speed *= 0.5
			burst = 1
		return
	hp = 20.0 + float(lvl) * 22.0
	dmg = 5.0 + float(lvl) * 4.0
	speed = 5.0 + float(lvl) * 1.6   # stronger creatures are FASTER
	# late game teeth: some creatures shoot, some fly, some do both
	shooter = lvl >= 4 and randf() < 0.30 + float(lvl) * 0.07
	flyer = lvl >= 5 and randf() < 0.40
	if flyer:
		speed *= 2.2   # airborne pursuit must out-run a jetpack
	if lvl >= 6:
		burst = 1 + randi() % 4   # 1-4 bolts; some spray way more than others

func _ready() -> void:
	add_to_group("enemy")
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 2.0
	cap.radius = 0.5
	col.shape = cap
	add_child(col)
	_build_model()

func _build_model() -> void:
	# NOT a biped. A random alien graph: each limb attaches to a random
	# earlier limb at a random angle, and wiggles as it walks.
	_mesh_root = Node3D.new()
	add_child(_mesh_root)
	var base_hue := randf()
	var col := Color.from_hsv(base_hue, 0.7, 0.9)
	var scale_f := 1.0 + float(level) * 0.12

	if pyramid:
		# temple guardian: a hovering 4-sided pyramid with an eye
		if tank:
			scale_f *= 1.5
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 1.0 * scale_f
		cone.height = 1.8 * scale_f
		cone.radial_segments = 4
		var core := _part(cone, Vector3(0, 0.6, 0), Color("#1f8f3a") if tank else Color("#d8c48a"), 0.5 if tank else 0.4)
		core.rotation_degrees = Vector3(0, 45, 0)
		if tank:
			# the ILLUMINATI EYE: white eye, dark pupil, gold radiance
			var eye_w := MeshInstance3D.new()
			var em2 := SphereMesh.new()
			em2.radius = 0.26 * scale_f
			em2.height = 0.36 * scale_f
			eye_w.mesh = em2
			eye_w.material_override = Destructible.make_material(Color("#f2f2e8"), 2.0)
			eye_w.position = Vector3(0, 0.7, -0.52 * scale_f)
			_mesh_root.add_child(eye_w)
			var pupil := _part(_box(Vector3(0.12, 0.18, 0.06) * scale_f), Vector3(0, 0.7, -0.66 * scale_f), Color("#0a0a0a"), 0.1)
			pupil.rotation_degrees = Vector3(0, 0, 0)
			for ri in 8:
				var ra := TAU * float(ri) / 8.0
				_part(_box(Vector3(0.05, 0.28, 0.03) * scale_f),
					Vector3(cos(ra) * 0.55 * scale_f, 0.7 + sin(ra) * 0.55 * scale_f, -0.55 * scale_f),
					Color("#ffd700"), 3.0).rotation = Vector3(0, 0, ra)
		else:
			_part(_box(Vector3(0.3, 0.3, 0.12)), Vector3(0, 0.7, -0.6 * scale_f), Color("#ff2b2b"), 8.0)
		return

	# core blob
	var core_size := randf_range(0.7, 1.1) * scale_f
	var core := _part(_box(Vector3(core_size, core_size, core_size)), Vector3(0, 0.4, 0), col, 0.3)
	var anchors: Array = [Vector3(0, 0.4, 0)]
	var limbs := 4 + level + randi_range(0, 3)
	for i in limbs:
		# attach to a random existing point, stick out in a random direction
		var from: Vector3 = anchors[randi() % anchors.size()]
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var length := randf_range(0.5, 1.5) * scale_f
		var thick := randf_range(0.12, 0.4) * scale_f
		var pos := from + dir * length * 0.5
		var mi := _part(_box(Vector3(thick, thick, length)), pos, col.lightened(randf_range(-0.2, 0.4)), randf_range(0.1, 0.8))
		mi.look_at_from_position(mi.position, mi.position + dir, Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT)
		_limbs.append({
			"node": mi, "base": mi.rotation,
			"phase": randf() * TAU, "amp": randf_range(0.15, 0.7),
			"axis": randi() % 3,
		})
		anchors.append(from + dir * length)
	# eyes on random anchors (always at least one)
	var eye := Color("#ff2b2b")
	for i in randi_range(1, 3):
		var at: Vector3 = anchors[randi() % anchors.size()]
		_part(_box(Vector3(0.16, 0.16, 0.16)), at, eye, 7.0)

func _box(sz: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = sz
	return m

func _part(mesh: Mesh, pos: Vector3, c: Color, emit: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	var mat := Destructible.make_material(c, emit)
	mi.material_override = mat
	_mesh_root.add_child(mi)
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
		return
	var center: Vector3 = _home.center
	var g: float = _home.g_surf
	var up := (global_position - center).normalized()
	_align_up(up)
	_cd -= delta
	_shot_cd -= delta

	var p := get_tree().get_first_node_in_group("player")
	var to_p := Vector3.ZERO
	var dist: float = 1e9
	var engaged := p != null and Game.mode == Game.Mode.ON_FOOT and not Game.dead
	if engaged:
		to_p = p.global_position - global_position
		dist = to_p.length()
		# ranged/flying hunters notice you from further away
		engaged = dist < (AGGRO * 1.6 if (shooter or flyer) else AGGRO)

	if flyer:
		# free flight: gravity is for the walkers
		var tv := Vector3.ZERO
		if engaged:
			if dist > ATTACK_RANGE * 0.7:
				tv = to_p.normalized() * speed
			var tan2 := to_p - up * to_p.dot(up)
			if tan2.length() > 0.01:
				global_transform.basis = _basis_from(tan2.normalized(), up)
		else:
			tv = -up * 1.5   # sink lazily when bored
		_bob_t += delta
		velocity = velocity.lerp(tv + up * sin(_bob_t * 2.0) * 0.6, delta * 4.5)
	else:
		var v_up := velocity.dot(up)
		if is_on_floor():
			v_up = maxf(v_up, 0.0)
		v_up -= g * delta
		var horiz := Vector3.ZERO
		if engaged:
			var tangent := to_p - up * to_p.dot(up)
			if tangent.length() > 0.01:
				horiz = tangent.normalized() * speed
				global_transform.basis = _basis_from(tangent.normalized(), up)
		velocity = horiz + up * v_up

	if engaged:
		if dist < ATTACK_RANGE and _cd <= 0.0:
			Game.hurt(dmg)
			_cd = ATTACK_CD
		if shooter and dist > ATTACK_RANGE and dist < 60.0 and _shot_cd <= 0.0:
			_shot_cd = maxf(1.2, 2.6 - float(level) * 0.18)
			_shoot(p)

	up_direction = up
	move_and_slide()

	# limbs writhe in an alien-but-natural way, faster while moving
	_walk_t += delta * (2.0 + velocity.length() * 0.6)
	for l in _limbs:
		var n: MeshInstance3D = l["node"]
		if not is_instance_valid(n):
			continue
		var w: float = sin(_walk_t + float(l["phase"])) * float(l["amp"])
		var rot: Vector3 = l["base"]
		match int(l["axis"]):
			0: rot.x += w
			1: rot.y += w
			2: rot.z += w
		n.rotation = rot

	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
		for m in _mats:
			m.emission_energy_multiplier = 0.4 + _flash * 4.0

## Fast bolt volley, aimed at where you're GOING to be.
func _shoot(p: Node3D) -> void:
	var bspeed := 30.0 + float(level) * 3.0
	var origin := global_position + global_transform.basis.y * 1.0
	var pv: Vector3 = p.velocity if p is CharacterBody3D else Vector3.ZERO
	for i in burst:
		var tgt: Vector3 = p.global_position + Vector3(0, 0.8, 0)
		tgt += pv * (origin.distance_to(tgt) / bspeed)   # lead the target
		var dir := (tgt - origin).normalized()
		if burst > 1:
			dir = (dir + Vector3(randf_range(-0.045, 0.045), randf_range(-0.045, 0.045),
				randf_range(-0.045, 0.045))).normalized()
		var b := Bolt.new()
		b.vel = dir * bspeed
		b.dmg = 4.0 + float(level) * 2.0
		get_parent().add_child(b)
		b.global_position = origin + dir * 1.4
	Sfx.play("shoot", -16.0)

## Glowing enemy projectile: fast, dodgeable, expires after 4s.
class Bolt extends Node3D:
	var vel: Vector3
	var dmg: float = 8.0
	var life: float = 4.0

	func _ready() -> void:
		var mi := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 0.22
		m.height = 0.44
		mi.mesh = m
		mi.material_override = Destructible.make_material(Color("#ff3bd4"), 6.0)
		add_child(mi)

	func _process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			queue_free()
			return
		global_position += vel * delta
		var p := get_tree().get_first_node_in_group("player")
		if p and Game.mode == Game.Mode.ON_FOOT and not Game.dead 				and global_position.distance_to(p.global_position) < 1.5:
			Game.hurt(dmg)
			Sfx.play("hurt", -10.0)
			queue_free()

func take_damage(d: float, _from: Vector3) -> void:
	hp -= d
	_flash = 1.0
	if hp <= 0.0:
		var up: Vector3 = (global_position - _home.center).normalized()
		Destructible.spawn_debris(get_parent(), global_position, Vector3(1.2, 1.2, 1.2), Color("#ff4444"), up)
		Game.register_break(Vector3(2, 2, 2), 15 + level * 8)
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

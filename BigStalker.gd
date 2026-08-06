class_name BigStalker
extends StaticBody3D
## The BIG one. Same blood as the stalker-thulhus -- hooded mantle,
## flared skirt, spaghetti tentacles -- but three times the size, TWO
## pale eyes whose pupils never leave you, and none of the little
## ones' politeness: it closes in, it strikes, and it takes a small
## war to put down.

var hp := 400.0
var _t := 0.0
var _phase := 0.0
var _tents: Array = []
var _pupils: Array = []      # [eyeball_pos, pupil_node]
var _strike_cd := 0.0
var _lunge := 0.0
var _dead := false
var _p = null

func _ready() -> void:
	add_to_group("stalker")
	add_to_group("big_stalker")
	_phase = randf() * TAU
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 3.2
	cap.height = 7.5
	cs.shape = cap
	add_child(cs)
	_build()

func _build() -> void:
	var flesh := Destructible.make_material(Color("#151021"), 0.12)
	var flesh2 := Destructible.make_material(Color("#241a38"), 0.2)
	var noodle := Destructible.make_material(Color("#e8d5a0"), 0.3)
	# the mantle, smoother and crowned, with a second inner hood tone
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 3.45
	bm.height = 6.0
	bm.radial_segments = 32
	bm.rings = 16
	body.mesh = bm
	body.material_override = flesh
	add_child(body)
	var hood := MeshInstance3D.new()
	var hm2 := SphereMesh.new()
	hm2.radius = 3.0
	hm2.height = 4.4
	hood.mesh = hm2
	hood.position = Vector3(0, 0.9, 0.4)
	hood.material_override = flesh2
	add_child(hood)
	var skirt := MeshInstance3D.new()
	var skm := CylinderMesh.new()
	skm.top_radius = 3.15
	skm.bottom_radius = 4.5
	skm.height = 2.7
	skm.radial_segments = 24
	skirt.mesh = skm
	skirt.position = Vector3(0, -2.25, 0)
	skirt.material_override = flesh
	add_child(skirt)
	# ridge spines, five now, sweeping back like a crest
	for i in 5:
		var sp := MeshInstance3D.new()
		var spm := CylinderMesh.new()
		spm.top_radius = 0.0
		spm.bottom_radius = 0.24
		spm.height = 1.9 - 0.15 * absf(float(i) - 2.0)
		sp.mesh = spm
		sp.position = Vector3(0, 2.6, -1.1 + 0.65 * float(i))
		sp.rotation_degrees.x = -25.0 + 16.0 * float(i)
		sp.material_override = flesh2
		add_child(sp)
	# faint violet vein glow seaming the mantle
	for vi in 4:
		var vein := MeshInstance3D.new()
		var vm := TorusMesh.new()
		vm.inner_radius = 2.5 + 0.22 * float(vi)
		vm.outer_radius = 2.56 + 0.22 * float(vi)
		vein.mesh = vm
		vein.material_override = Destructible.make_material(Color("#6a4a9e"), 0.9)
		vein.position = Vector3(0, -0.6 - 0.5 * float(vi), 0)
		vein.scale = Vector3(1, 0.25, 1)
		add_child(vein)
	# TWO pale eyes. both looking at you. always.
	for es in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.85
		em.height = 1.7
		eye.mesh = em
		eye.material_override = Destructible.make_material(Color("#ded2a8"), 1.6)
		eye.position = Vector3(es * 1.25, 0.5, -2.75)
		add_child(eye)
		var pupil := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.32
		pm.height = 0.64
		pupil.mesh = pm
		pupil.material_override = Destructible.make_material(Color("#0a0808"), 0.0)
		add_child(pupil)
		pupil.position = eye.position + Vector3(0, 0, -0.62)
		_pupils.append([eye.position, pupil])
	# the SPAGHETTI: twelve tentacles, nine segments, thick to thin
	for ti in 12:
		var ang := TAU * float(ti) / 12.0
		var root := Node3D.new()
		root.position = Vector3(cos(ang) * 2.3, -3.2, sin(ang) * 2.3)
		add_child(root)
		var segs: Array = [root]
		var parent: Node3D = root
		for si in 9:
			var seg := Node3D.new()
			parent.add_child(seg)
			seg.position = Vector3(0, -1.1, 0)
			var mi := MeshInstance3D.new()
			var cm := CapsuleMesh.new()
			cm.radius = 0.3 - 0.026 * float(si)
			cm.height = 1.35
			mi.mesh = cm
			mi.material_override = noodle
			seg.add_child(mi)
			segs.append(seg)
			parent = seg
		_tents.append(segs)

var _departing := false
func depart() -> void:
	_departing = true

func take_damage(d: float, _from: Vector3) -> void:
	if _dead:
		return
	hp -= d
	Sfx.play("hurt", -14.0)
	_lunge = maxf(_lunge, 0.25)   # flinch
	if hp <= 0.0:
		_dead = true
		Sfx.play("explode", -6.0)
		Destructible.spawn_debris(get_parent(), global_position,
			Vector3(4.0, 4.0, 4.0), Color("#241a38"), Vector3.UP)
		for nd9 in 3:
			var drop := ItemDrop.new()
			drop.setup("noodle", 1)
			get_parent().add_child(drop)
			drop.global_position = global_position \
				+ Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		queue_free()

func _process(delta: float) -> void:
	_t += delta
	if _departing:
		scale = scale * maxf(0.0, 1.0 - delta * 1.1)
		if scale.x < 0.04:
			queue_free()
		return
	_strike_cd = maxf(0.0, _strike_cd - delta)
	_lunge = maxf(0.0, _lunge - delta)
	if _p == null or not is_instance_valid(_p):
		_p = get_tree().get_first_node_in_group("player")
	var p = _p
	if p == null or not is_instance_valid(p):
		queue_free()
		return
	var to_me: Vector3 = global_position - p.global_position
	var d := to_me.length()
	var out: Vector3 = to_me / d if d > 0.5 else Vector3(1, 0, 0)
	# it wants 14m. it is not polite about it.
	var want: Vector3 = p.global_position + out * 14.0 \
		+ Vector3(sin(_t * 0.31 + _phase), sin(_t * 0.44 + _phase * 2.0) * 0.6,
			cos(_t * 0.28 + _phase)) * 2.5
	global_position = global_position.lerp(want, minf(1.0, delta * 0.9))
	# STRIKE: inside 20m, every few seconds, a tentacle whip -- the
	# whole thing darts at you and it HURTS
	if d < 20.0 and _strike_cd <= 0.0 and not Game.dead:
		_strike_cd = 3.5
		_lunge = 0.6
		Game.hurt(7.0)
		Sfx.play("hurt", -13.0)
	if _lunge > 0.0:
		global_position -= out * delta * 14.0 * _lunge
	# face the dude, feet toward their down
	if d > 0.6:
		var upl: Vector3 = p.global_transform.basis.y
		var fwd: Vector3 = (p.global_position - global_position).normalized()
		if absf(fwd.dot(upl)) < 0.95:
			var x := upl.cross(fwd).normalized()
			global_transform.basis = Basis(x, upl, -fwd).orthonormalized() \
				* Basis(Vector3.UP, PI)
	# the pupils TRACK: each slides across its eyeball toward you,
	# never wandering, never random
	for pe in _pupils:
		var eyepos: Vector3 = pe[0]
		var pup: Node3D = pe[1]
		var ldir := (to_local(p.global_position) - eyepos).normalized()
		pup.position = eyepos + ldir * 0.62
	# writhe
	for ti in _tents.size():
		var segs: Array = _tents[ti]
		for si in segs.size():
			var seg: Node3D = segs[si]
			seg.rotation = Vector3(
				sin(_t * 2.0 + _phase + float(ti) * 0.9 + float(si) * 0.6)
				* (0.22 + _lunge * 0.5), 0.0,
				cos(_t * 1.7 + _phase * 1.3 + float(ti) * 1.2 + float(si) * 0.55)
				* (0.22 + _lunge * 0.5))

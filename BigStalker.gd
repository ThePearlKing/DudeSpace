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
var _wings: Array = []
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
	cap.radius = 2.6
	cap.height = 13.0
	cs.shape = cap
	add_child(cs)
	_build()

func _build() -> void:
	var flesh := Destructible.make_material(Color("#1a2418"), 0.15)
	var flesh2 := Destructible.make_material(Color("#2a3a26"), 0.25)
	var wingm := Destructible.make_material(Color("#141c12"), 0.1)
	# CTHULHU PROPER: a hulking humanoid TORSO, not a hood
	var torso := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 2.2
	tm.height = 7.0
	torso.mesh = tm
	torso.material_override = flesh
	add_child(torso)
	var chest := MeshInstance3D.new()
	var chm := SphereMesh.new()
	chm.radius = 2.5
	chm.height = 4.2
	chest.mesh = chm
	chest.position = Vector3(0, 1.2, -0.3)
	chest.material_override = flesh2
	add_child(chest)
	# the HEAD: bulbous, wider than tall, eyes forward
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 1.9
	hm.height = 3.2
	head.mesh = hm
	head.position = Vector3(0, 4.6, 0)
	head.material_override = flesh
	add_child(head)
	# TWO eyes. tracking. always.
	for es in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.55
		em.height = 1.1
		eye.mesh = em
		eye.material_override = Destructible.make_material(Color("#ffd9a0"), 1.8)
		eye.position = Vector3(es * 0.85, 5.0, -1.45)
		add_child(eye)
		var pupil := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.22
		pm.height = 0.44
		pupil.mesh = pm
		pupil.material_override = Destructible.make_material(Color("#0a0808"), 0.0)
		add_child(pupil)
		pupil.position = eye.position + Vector3(0, 0, -0.4)
		_pupils.append([eye.position, pupil])
	# the FACE TENTACLES: the beard. eight writhing feelers off the jaw
	for ti in 8:
		var bx := -1.2 + 2.4 * float(ti) / 7.0
		var root := Node3D.new()
		root.position = Vector3(bx, 3.9, -1.3)
		add_child(root)
		var segs: Array = [root]
		var parent: Node3D = root
		for si in 6:
			var seg := Node3D.new()
			parent.add_child(seg)
			seg.position = Vector3(0, -0.55, -0.1)
			var mi := MeshInstance3D.new()
			var cm := CapsuleMesh.new()
			cm.radius = 0.17 - 0.02 * float(si)
			cm.height = 0.7
			mi.mesh = cm
			mi.material_override = flesh2
			seg.add_child(mi)
			segs.append(seg)
			parent = seg
		_tents.append(segs)
	# ARMS: thick, clawed, hanging ready
	for asd in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var am := CapsuleMesh.new()
		am.radius = 0.75
		am.height = 5.2
		arm.mesh = am
		arm.position = Vector3(asd * 2.9, 1.2, 0)
		arm.rotation_degrees = Vector3(0, 0, asd * -14.0)
		arm.material_override = flesh
		add_child(arm)
		for cl in 3:
			var claw := MeshInstance3D.new()
			var clm := CylinderMesh.new()
			clm.top_radius = 0.0
			clm.bottom_radius = 0.14
			clm.height = 0.9
			claw.mesh = clm
			claw.position = Vector3(asd * 3.5 + (float(cl) - 1.0) * 0.3,
				-1.6, -0.2)
			claw.rotation_degrees = Vector3(180, 0, 0)
			claw.material_override = flesh2
			add_child(claw)
	# LEGS: it stands on the void
	for lsd in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var lm := CapsuleMesh.new()
		lm.radius = 0.9
		lm.height = 5.6
		leg.mesh = lm
		leg.position = Vector3(lsd * 1.2, -4.6, 0)
		leg.material_override = flesh
		add_child(leg)
	# THE WINGS: vast ragged membranes, half-folded, slowly beating
	for wsd in [-1.0, 1.0]:
		var wroot := Node3D.new()
		wroot.position = Vector3(wsd * 1.6, 2.8, 1.6)
		add_child(wroot)
		_wings.append(wroot)
		var spar := MeshInstance3D.new()
		var sm := CapsuleMesh.new()
		sm.radius = 0.3
		sm.height = 7.5
		spar.mesh = sm
		spar.position = Vector3(wsd * 3.2, 1.4, 0.6)
		spar.rotation_degrees = Vector3(0, 0, wsd * -62.0)
		spar.material_override = flesh
		wroot.add_child(spar)
		var mem := MeshInstance3D.new()
		var mm := PrismMesh.new()
		mm.size = Vector3(6.4, 5.4, 0.14)
		mem.mesh = mm
		mem.position = Vector3(wsd * 3.6, 0.4, 1.0)
		mem.rotation_degrees = Vector3(8, wsd * 14.0, wsd * -20.0)
		mem.material_override = wingm
		wroot.add_child(mem)

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
		pup.position = eyepos + ldir * 0.4
	# wings: a slow heavy beat, deeper when it lunges
	for wi in _wings.size():
		var wr: Node3D = _wings[wi]
		wr.rotation.z = (1.0 if wi == 0 else -1.0) \
			* (0.12 + 0.10 * sin(_t * 0.9) + _lunge * 0.3)
	# the beard writhes
	for ti in _tents.size():
		var segs: Array = _tents[ti]
		for si in segs.size():
			var seg: Node3D = segs[si]
			seg.rotation = Vector3(
				sin(_t * 2.0 + _phase + float(ti) * 0.9 + float(si) * 0.6)
				* (0.22 + _lunge * 0.5), 0.0,
				cos(_t * 1.7 + _phase * 1.3 + float(ti) * 1.2 + float(si) * 0.55)
				* (0.22 + _lunge * 0.5))

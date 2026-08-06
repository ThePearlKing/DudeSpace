class_name Stalker
extends Node3D
## The stalker-thulhus, back from the old days -- dark hovering things
## with real spaghetti tentacles. They come when the noodle god is
## angry, hang at the edge of your vision, and face you. Always.
## They do not attack. That is somehow worse.

var _t := 0.0
var _phase := 0.0
var _tents: Array = []       # each: Array of segment Node3Ds, base first
var _departing := false
var _p = null   # cached player, validity-checked

func _ready() -> void:
	add_to_group("stalker")
	_phase = randf() * TAU
	_build()

func _build() -> void:
	var flesh := Destructible.make_material(Color("#151021"), 0.12)
	var noodle := Destructible.make_material(Color("#e8d5a0"), 0.3)
	# the mantle: a bulbous hooded dome with a flared skirt
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 1.15
	bm.height = 2.0
	body.mesh = bm
	body.material_override = flesh
	add_child(body)
	var skirt := MeshInstance3D.new()
	var skm := CylinderMesh.new()
	skm.top_radius = 1.05
	skm.bottom_radius = 1.5
	skm.height = 0.9
	skirt.mesh = skm
	skirt.position = Vector3(0, -0.75, 0)
	skirt.material_override = flesh
	add_child(skirt)
	# ridge spines cresting the hood
	for i in 3:
		var sp := MeshInstance3D.new()
		var spm := CylinderMesh.new()
		spm.top_radius = 0.0
		spm.bottom_radius = 0.09
		spm.height = 0.55
		sp.mesh = spm
		sp.position = Vector3(0, 0.85, -0.25 + 0.3 * float(i))
		sp.rotation_degrees.x = -20.0 + 22.0 * float(i)
		sp.material_override = flesh
		add_child(sp)
	# ONE pale eye. it is looking at you.
	var eye := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.34
	em.height = 0.68
	eye.mesh = em
	eye.material_override = Destructible.make_material(Color("#ded2a8"), 1.6)
	eye.position = Vector3(0, 0.15, -0.95)
	add_child(eye)
	var pupil := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.13
	pm.height = 0.26
	pupil.mesh = pm
	pupil.material_override = Destructible.make_material(Color("#0a0808"), 0.0)
	pupil.position = Vector3(0, 0.15, -1.24)
	add_child(pupil)
	# the SPAGHETTI: nine noodly tentacles, seven segments each,
	# tapering, writhing on their own clocks
	for ti in 9:
		var ang := TAU * float(ti) / 9.0
		var root := Node3D.new()
		root.position = Vector3(cos(ang) * 0.75, -1.05, sin(ang) * 0.75)
		add_child(root)
		var segs: Array = [root]
		var parent: Node3D = root
		for si in 7:
			var seg := Node3D.new()
			parent.add_child(seg)
			seg.position = Vector3(0, -0.4, 0)
			var mi := MeshInstance3D.new()
			var cm := CapsuleMesh.new()
			cm.radius = 0.085 - 0.009 * float(si)
			cm.height = 0.52
			mi.mesh = cm
			mi.position = Vector3(0, -0.2, 0)
			mi.material_override = noodle
			seg.add_child(mi)
			segs.append(seg)
			parent = seg
		_tents.append(segs)

func depart() -> void:
	_departing = true

func _process(delta: float) -> void:
	if global_position.length() > Universe.BOUNDARY - 250.0:
		global_position = global_position.normalized() \
			* (Universe.BOUNDARY - 250.0)
	_t += delta
	if _p == null or not is_instance_valid(_p):
		_p = get_tree().get_first_node_in_group("player")
	var p = _p
	if p == null or not is_instance_valid(p):
		queue_free()
		return
	if _departing:
		# fold out of the world
		scale = scale * maxf(0.0, 1.0 - delta * 1.1)
		if scale.x < 0.04:
			queue_free()
			return
	else:
		# hold a slow drifting ring ~17m out, bobbing like kelp
		var to_me: Vector3 = global_position - p.global_position
		var d := to_me.length()
		var out: Vector3 = to_me / d if d > 0.5 else Vector3(1, 0, 0)
		var want: Vector3 = p.global_position + out * 17.0 \
			+ Vector3(sin(_t * 0.37 + _phase), sin(_t * 0.51 + _phase * 2.0) * 0.7,
				cos(_t * 0.33 + _phase)) * 3.0
		global_position = global_position.lerp(want, minf(1.0, delta * 0.7))
		# stared at head-on? it eases back. politely. wrongly.
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null and d > 0.5:
			if (-cam.global_transform.basis.z).dot(-out) > 0.988:
				global_position += out * delta * 3.0
	# face the dude, feet toward the local down
	if global_position.distance_to(p.global_position) > 0.6:
		var upl: Vector3 = p.global_transform.basis.y
		var fwd: Vector3 = (p.global_position - global_position).normalized()
		if absf(fwd.dot(upl)) < 0.95:
			var x := upl.cross(fwd).normalized()
			global_transform.basis = Basis(x, upl, -fwd).orthonormalized() \
				* Basis(Vector3.UP, PI)
	# writhe: every noodle alive on its own clock
	for ti in _tents.size():
		var segs: Array = _tents[ti]
		for si in segs.size():
			var seg: Node3D = segs[si]
			seg.rotation = Vector3(
				sin(_t * 2.1 + _phase + float(ti) * 0.9 + float(si) * 0.65) * 0.24,
				0.0,
				cos(_t * 1.8 + _phase * 1.3 + float(ti) * 1.2 + float(si) * 0.6) * 0.24)

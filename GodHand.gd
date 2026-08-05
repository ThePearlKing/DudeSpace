class_name GodHand
extends Node3D
## The universe god's answer to edge-crossers. No message. A colossal
## lowercase "me" fades into the dark, and a colossal, disturbingly
## realistic hand arrives from deeper space and throws you back toward
## the center of everything. It does not explain itself twice.

var _t := 0.0
var _victim: Node3D = null
var _target := Vector3.ZERO
var _hand: Node3D
var _lbl: Label3D
var _fingers: Array = []
var _thrown := false
var _outdir := Vector3.ZERO

func begin(victim: Node3D, target: Vector3) -> void:
	_victim = victim
	_target = target
	_outdir = (victim.global_position - target).normalized()
	global_position = victim.global_position
	_lbl = Label3D.new()
	_lbl.text = "me"
	_lbl.font_size = 640
	_lbl.pixel_size = 0.6
	_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_lbl.modulate = Color(1, 1, 1, 0.0)
	_lbl.outline_size = 24
	_lbl.outline_modulate = Color(0, 0, 0, 0.0)
	_lbl.no_depth_test = true
	add_child(_lbl)
	_lbl.global_position = victim.global_position + _outdir * 600.0
	_build_hand()
	_hand.global_position = victim.global_position + _outdir * 900.0

## A hand you could believe in: proportioned palm, four fingers of
## three segments each with knuckle joints, opposable thumb, nails.
func _build_hand() -> void:
	_hand = Node3D.new()
	add_child(_hand)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("#d9b08a")
	skin.roughness = 0.65
	var nail := StandardMaterial3D.new()
	nail.albedo_color = Color("#efdcc8")
	nail.roughness = 0.35
	var palm := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(26.0, 30.0, 7.5)
	palm.mesh = pm
	palm.material_override = skin
	_hand.add_child(palm)
	# heel of the palm, slightly thicker
	var heel := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(24.0, 10.0, 9.0)
	heel.mesh = hm
	heel.position = Vector3(0, -17.0, 0)
	heel.material_override = skin
	_hand.add_child(heel)
	# four fingers along the top edge, human length ratios
	var lens: Array = [0.85, 1.0, 0.95, 0.72]
	for fi in 4:
		var fx := -9.5 + 6.3 * float(fi)
		var root := Node3D.new()
		root.position = Vector3(fx, 15.0, 0)
		_hand.add_child(root)
		var seg_parent: Node3D = root
		var segs: Array = []
		for si in 3:
			var seg := Node3D.new()
			seg_parent.add_child(seg)
			if si > 0:
				seg.position = Vector3(0, 9.0 * float(lens[fi]) * (1.0 - 0.18 * float(si - 1)), 0)
			var mi := MeshInstance3D.new()
			var sm := CapsuleMesh.new()
			sm.radius = 2.4 - 0.35 * float(si)
			sm.height = 10.0 * float(lens[fi]) * (1.0 - 0.18 * float(si))
			mi.mesh = sm
			mi.position = Vector3(0, sm.height * 0.45, 0)
			mi.material_override = skin
			seg.add_child(mi)
			# knuckle
			var kn := MeshInstance3D.new()
			var km := SphereMesh.new()
			km.radius = sm.radius * 1.02
			km.height = km.radius * 2.0
			kn.mesh = km
			kn.material_override = skin
			seg.add_child(kn)
			if si == 2:
				var nl := MeshInstance3D.new()
				var nm := BoxMesh.new()
				nm.size = Vector3(sm.radius * 1.2, sm.height * 0.45, 0.6)
				nl.mesh = nm
				nl.position = Vector3(0, sm.height * 0.7, -sm.radius * 0.8)
				nl.material_override = nail
				seg.add_child(nl)
			segs.append(seg)
			seg_parent = seg
		_fingers.append(segs)
	# the thumb: two fat segments off the side, angled across
	var troot := Node3D.new()
	troot.position = Vector3(-14.0, 0.0, 0)
	troot.rotation_degrees = Vector3(0, 0, 48)
	_hand.add_child(troot)
	var tp: Node3D = troot
	var tsegs: Array = []
	for si in 2:
		var seg := Node3D.new()
		tp.add_child(seg)
		if si > 0:
			seg.position = Vector3(0, 8.5, 0)
		var mi := MeshInstance3D.new()
		var sm := CapsuleMesh.new()
		sm.radius = 3.0 - 0.4 * float(si)
		sm.height = 9.5
		mi.mesh = sm
		mi.position = Vector3(0, 4.2, 0)
		mi.material_override = skin
		seg.add_child(mi)
		tsegs.append(seg)
		tp = seg
	_fingers.append(tsegs)

func _process(delta: float) -> void:
	_t += delta
	if _victim == null or not is_instance_valid(_victim):
		queue_free()
		return
	# "me": fades into existence, holds, lets go
	var la := clampf(_t / 1.2, 0.0, 1.0)
	if _t > 3.5:
		la *= maxf(0.0, 1.0 - (_t - 3.5) / 1.2)
	_lbl.modulate.a = la
	_lbl.outline_modulate.a = la
	if not _thrown:
		_lbl.global_position = _victim.global_position + _outdir * 600.0
		# the hand closes the 900m like it was never far
		var k := clampf(_t / 1.4, 0.0, 1.0)
		var kk := k * k * (3.0 - 2.0 * k)
		_hand.global_position = _victim.global_position \
			+ _outdir * lerpf(900.0, 22.0, kk)
		# palm faces the victim, fingers curling as it arrives
		var fwd := -_outdir
		var upv := fwd.cross(Vector3(0, 0, 1))
		if upv.length() < 0.01:
			upv = fwd.cross(Vector3(1, 0, 0))
		upv = upv.normalized()
		_hand.global_transform.basis = Basis(upv.cross(fwd).normalized(), upv, -fwd) \
			.orthonormalized()
		_hand.scale = Vector3.ONE
		for fset in _fingers:
			for si in (fset as Array).size():
				((fset as Array)[si] as Node3D).rotation.x = -kk * (0.35 + 0.2 * float(si))
		if k >= 1.0:
			_thrown = true
			var back := (_target - _victim.global_position).normalized()
			if "vel" in _victim:
				_victim.vel = back * 320.0
			elif "velocity" in _victim:
				_victim.velocity = back * 320.0
	else:
		# follow-through: the hand sweeps past the throw and lets go
		var sw := maxf(0.0, 1.0 - (_t - 1.4) / 0.6)
		_hand.global_position += (_target - global_position).normalized() \
			* 320.0 * delta * sw
		if _t > 2.6:
			_hand.scale = Vector3.ONE * maxf(0.001, 1.0 - (_t - 2.6) / 1.6)
	if _t > 5.2:
		queue_free()

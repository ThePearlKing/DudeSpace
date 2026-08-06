class_name BigStalker
extends StaticBody3D
## THE OG, back from the dead commit: NoodleWrath's body -- a colossal
## pale meatball with two vast red eyes and ten hanging noodle
## tendrils -- rebuilt a notch better (smoother taper, socket rims,
## rounded tips, a living surface tone) but unmistakably ITSELF.
## Unlike the old god-event, this one is a creature: it hunts at deep
## wrath, it hurts, and enough firepower drops it.

var hp := 4000.0
var _t := 0.0
var _phase := 0.0
var _tents: Array = []
var _pupils: Array = []      # [eyeball_pos, pupil_node]
var _strike_cd := 0.0
var _lunge := 0.0
var _dead := false
var _departing := false
var _p = null

const SIZE := 0.5   # half the god-event's scale: huge, still fightable

func depart() -> void:
	_departing = true

func _ready() -> void:
	add_to_group("stalker")
	add_to_group("big_stalker")
	_phase = randf() * TAU
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 30.0 * SIZE
	cs.shape = sph
	add_child(cs)
	_build()

func _build() -> void:
	var meat := Destructible.make_material(Color("#e8cf9a"), 0.4)
	var meat2 := Destructible.make_material(Color("#d9ba82"), 0.3)
	var noodle := Destructible.make_material(Color("#f0d9a8"), 0.3)
	# the core: the colossal pale meatball, with a warmer under-sphere
	# so the mass reads round instead of flat
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 55.0 * SIZE
	cm.height = 110.0 * SIZE
	cm.radial_segments = 48
	cm.rings = 24
	core.mesh = cm
	core.material_override = meat
	add_child(core)
	var under := MeshInstance3D.new()
	var um := SphereMesh.new()
	um.radius = 50.0 * SIZE
	um.height = 100.0 * SIZE
	under.mesh = um
	under.position = Vector3(0, -6.0 * SIZE, 0)
	under.material_override = meat2
	add_child(under)
	# two vast red eyes -- now set in shallow socket rims, pupils live
	for sx in [-22.0, 22.0]:
		var rim := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = 7.2 * SIZE
		rm.outer_radius = 8.6 * SIZE
		rim.mesh = rm
		rim.material_override = meat2
		rim.position = Vector3(sx * SIZE, -12.0 * SIZE, -47.0 * SIZE)
		rim.rotation_degrees = Vector3(90, 0, 0)
		add_child(rim)
		var e := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 7.0 * SIZE
		em.height = 14.0 * SIZE
		e.mesh = em
		e.material_override = Destructible.make_material(Color("#ff2b2b"), 6.0)
		e.position = Vector3(sx * SIZE, -12.0 * SIZE, -48.0 * SIZE)
		add_child(e)
		var pupil := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 2.6 * SIZE
		pm.height = 5.2 * SIZE
		pupil.mesh = pm
		pupil.material_override = Destructible.make_material(Color("#160404"), 0.0)
		add_child(pupil)
		pupil.position = e.position + Vector3(0, 0, -5.2 * SIZE)
		_pupils.append([e.position, pupil])
	# ten hanging noodle tendrils: segmented, tapering smoother than the
	# original, each ending in a rounded tip instead of a raw cut
	for i in 10:
		var ang := TAU * float(i) / 10.0
		var root := Node3D.new()
		root.position = Vector3(cos(ang) * 16.0 * SIZE, -22.0 * SIZE,
			sin(ang) * 16.0 * SIZE)
		add_child(root)
		root.rotate(Vector3(-sin(ang), 0, cos(ang)).normalized(), 0.42)
		var segs: Array = [root]
		var parent: Node3D = root
		for k in 6:
			var seg := Node3D.new()
			parent.add_child(seg)
			seg.position = Vector3(0, (-12.0 if k == 0 else -30.0) * SIZE, 0)
			var mi := MeshInstance3D.new()
			var sm := CylinderMesh.new()
			sm.top_radius = (6.5 - float(k) * 0.85) * SIZE
			sm.bottom_radius = (5.8 - float(k) * 0.85) * SIZE
			sm.height = 32.0 * SIZE
			mi.mesh = sm
			mi.material_override = noodle
			seg.add_child(mi)
			segs.append(seg)
			parent = seg
		var tip := MeshInstance3D.new()
		var tpm := SphereMesh.new()
		tpm.radius = 1.6 * SIZE
		tpm.height = 3.2 * SIZE
		tip.mesh = tpm
		tip.position = Vector3(0, -16.0 * SIZE, 0)
		tip.material_override = noodle
		parent.add_child(tip)
		_tents.append(segs)

func take_damage(d: float, _from: Vector3) -> void:
	if _dead:
		return
	hp -= d
	Sfx.play("hurt", -14.0)
	_lunge = maxf(_lunge, 0.25)
	if hp <= 0.0:
		_dead = true
		Sfx.play("explode", -6.0)
		Destructible.spawn_debris(get_parent(), global_position,
			Vector3(16.0, 16.0, 16.0), Color("#e8cf9a"), Vector3.UP)
		for nd9 in 3:
			var drop := ItemDrop.new()
			drop.setup("noodle", 1)
			get_parent().add_child(drop)
			drop.global_position = global_position \
				+ Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
		queue_free()

func _process(delta: float) -> void:
	_t += delta
	# nothing this holy leaves the universe
	if global_position.length() > Universe.BOUNDARY - 250.0:
		global_position = global_position.normalized() \
			* (Universe.BOUNDARY - 250.0)
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
	# it looms at ~70m, drifting like weather with intent
	var want: Vector3 = p.global_position + out * 70.0 \
		+ Vector3(sin(_t * 0.31 + _phase), sin(_t * 0.44 + _phase * 2.0) * 0.6,
			cos(_t * 0.28 + _phase)) * 8.0
	global_position = global_position.lerp(want, minf(1.0, delta * 0.7))
	# STRIKE: inside 90m a tendril reaches you every few seconds
	if d < 90.0 and _strike_cd <= 0.0 and not Game.dead:
		_strike_cd = 3.5
		_lunge = 0.6
		Game.hurt(7.0)
		Sfx.play("hurt", -14.0)
	if _lunge > 0.0:
		global_position -= out * delta * 30.0 * _lunge
	# face the dude, upright in their gravity
	if d > 0.6:
		var upl: Vector3 = p.global_transform.basis.y
		var fwd: Vector3 = (p.global_position - global_position).normalized()
		if absf(fwd.dot(upl)) < 0.95:
			var x := upl.cross(fwd).normalized()
			global_transform.basis = Basis(x, upl, -fwd).orthonormalized()
	# pupils TRACK across the red
	for pe in _pupils:
		var eyepos: Vector3 = pe[0]
		var pup: Node3D = pe[1]
		var ldir := (to_local(p.global_position) - eyepos).normalized()
		pup.position = eyepos + ldir * 5.2 * SIZE
	# tendrils writhe like the original -- whole-arm sway plus segment
	# ripple, harder mid-lunge
	for ti in _tents.size():
		var segs: Array = _tents[ti]
		for si in segs.size():
			var seg: Node3D = segs[si]
			seg.rotation = Vector3(
				sin(_t * 0.8 + _phase + float(ti) * 0.9 + float(si) * 0.5)
				* (0.15 + _lunge * 0.4), 0.0,
				cos(_t * 0.6 + _phase * 1.3 + float(ti) * 1.2 + float(si) * 0.45)
				* (0.15 + _lunge * 0.4))

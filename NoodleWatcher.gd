class_name NoodleWatcher
extends Node3D
## THE noodle god: a cosmic tangle with one enormous eye, parked in the
## sky no matter where you go. It drifts slowly, it always faces you,
## and its mood is legible at a glance -- calm gold coils when appeased,
## red pulsing glare as wrath climbs. Angry enough, it starts reaching
## into your head: zaps, shoves, scrambled hands. Annoying by design,
## lethal only if you let wrath max out (then it comes DOWN -- see
## NoodleWrath).

const DIST := 12000.0

var _dir: Vector3 = Vector3(0.4, 0.55, -0.73).normalized()
var _eye_mat: StandardMaterial3D
var _pupil: MeshInstance3D
var _coils: Array = []
var _t: float = 0.0
var _mischief_t: float = 20.0

func _ready() -> void:
	# the eye
	var eye := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 620.0
	em.height = 1240.0
	eye.mesh = em
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = Color("#f5eee0")
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color("#ffcf40")
	_eye_mat.emission_energy_multiplier = 0.4
	eye.material_override = _eye_mat
	add_child(eye)
	_pupil = MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 260.0
	pm.height = 520.0
	_pupil.mesh = pm
	_pupil.position = Vector3(0, 0, -420.0)   # bulges toward the viewer
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color("#1a1208")
	_pupil.material_override = pmat
	add_child(_pupil)
	# the tangle: fat noodle coils wreathing the eye
	for i in 12:
		var coil := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = randf_range(520.0, 700.0)
		tm.outer_radius = tm.inner_radius + randf_range(90.0, 150.0)
		coil.mesh = tm
		coil.rotation_degrees = Vector3(randf_range(0, 180), randf_range(0, 180), randf_range(0, 180))
		var cmat := StandardMaterial3D.new()
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cmat.albedo_color = Color("#e8b830")
		cmat.emission_enabled = true
		cmat.emission = Color("#ffcf40")
		cmat.emission_energy_multiplier = 0.25
		coil.material_override = cmat
		add_child(coil)
		_coils.append(coil)

func _process(delta: float) -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	_t += delta
	# slow celestial drift: it circles you like a thought you can't drop
	_dir = _dir.rotated(Vector3.UP, delta * 0.004)
	var wob := sin(_t * 0.05) * 0.06
	var d := (_dir + Vector3(0, wob, 0)).normalized()
	global_position = p.global_position + d * DIST
	look_at(p.global_position, Vector3.UP)

	# mood on its face: gold and sleepy -> red, wide and pulsing
	var w: float = Game.wrath / Game.WRATH_MAX
	_eye_mat.emission = Color("#ffcf40").lerp(Color("#ff2b1a"), w)
	_eye_mat.emission_energy_multiplier = 0.4 + w * (1.6 + sin(_t * 6.0) * 0.8 * w)
	_pupil.scale = Vector3.ONE * (0.55 + w * 0.65)
	for i in _coils.size():
		var coil: MeshInstance3D = _coils[i]
		coil.rotation_degrees += Vector3(delta * (2.0 + w * 14.0), delta * 3.0, 0)
		coil.material_override.emission = _eye_mat.emission

	# --- telepathic mischief: annoying, damaging, never a death sentence ---
	if Game.wrath < 30.0 or Game.dead or Game.mode != Game.Mode.ON_FOOT:
		return
	_mischief_t -= delta
	if _mischief_t > 0.0:
		return
	# angrier god, shorter patience
	_mischief_t = lerpf(28.0, 8.0, w) * randf_range(0.7, 1.3)
	match randi() % 3:
		0:
			# a zap: thin red thought-beam from the eye, small bite of damage
			_beam(p.global_position)
			# stings, never slays: won't take you below 5 hp
			Game.hurt(clampf(Game.health - 5.0, 0.0, 7.0))
		1:
			# a shove: the sky flicks you like a crumb
			if p is CharacterBody3D:
				var kick := Vector3(randf_range(-1, 1), randf_range(0.3, 1), randf_range(-1, 1)).normalized()
				p.velocity += kick * randf_range(6.0, 11.0)
				if "_shake" in p:
					p._shake = 0.35
		2:
			# a scramble: your hand forgets what it was holding
			Inventory.select_slot(randi() % 5)

## Visible line of malice: eye to player, gone in half a second.
class _BeamFx extends Node3D:
	var life := 0.5
	func _process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			queue_free()

func _beam(target: Vector3) -> void:
	var fx := _BeamFx.new()
	get_parent().add_child(fx)
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color("#ff2b1a")
	mat.emission_energy_multiplier = 3.0
	mat.albedo_color = Color("#ff2b1a")
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	im.surface_add_vertex(global_position - Vector3(0, 0, 0))
	im.surface_add_vertex(target)
	im.surface_end()
	mi.mesh = im
	fx.add_child(mi)
	Sfx.play("hurt", -18.0)

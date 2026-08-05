class_name MushroomCloud
extends Node3D
## The consequence. A meltdown's mushroom cloud, scaled by yield:
## fireball flash, rising cap on a growing stem, skirt ring, ground
## shockwave, and a light that briefly owns the neighborhood. If the
## blast killed you, it borrows the camera for a slow funeral orbit.

var _y := 1.0
var _t := 0.0
var _fire: MeshInstance3D
var _cap: MeshInstance3D
var _stem: MeshInstance3D
var _skirt: MeshInstance3D
var _ring: MeshInstance3D
var _light: OmniLight3D
var _cam: Camera3D = null
var _ring_mat: StandardMaterial3D

func setup(yield_s: float, up: Vector3) -> void:
	_y = yield_s
	var x := up.cross(Vector3(0, 0, 1))
	if x.length() < 0.01:
		x = up.cross(Vector3(1, 0, 0))
	x = x.normalized()
	global_transform = Transform3D(Basis(x, up, x.cross(up).normalized() * -1.0)
		.orthonormalized(), global_position)
	var smoke := StandardMaterial3D.new()
	smoke.albedo_color = Color("#2b2320")
	smoke.emission_enabled = true
	smoke.emission = Color("#ff7a20")
	smoke.emission_energy_multiplier = 2.2
	smoke.roughness = 1.0
	_fire = MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 1.0
	fm.height = 2.0
	fm.radial_segments = 24
	fm.rings = 16
	_fire.mesh = fm
	var firemat := StandardMaterial3D.new()
	firemat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	firemat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	firemat.albedo_color = Color(1.0, 0.55, 0.15)
	_fire.material_override = firemat
	add_child(_fire)
	_cap = MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 1.0
	cm.height = 1.4
	cm.radial_segments = 24
	cm.rings = 16
	_cap.mesh = cm
	_cap.material_override = smoke
	add_child(_cap)
	_stem = MeshInstance3D.new()
	var st := CylinderMesh.new()
	st.top_radius = 1.0
	st.bottom_radius = 0.75
	st.height = 1.0
	_stem.mesh = st
	_stem.material_override = smoke
	add_child(_stem)
	_skirt = MeshInstance3D.new()
	var sk := TorusMesh.new()
	sk.inner_radius = 0.9
	sk.outer_radius = 1.5
	_skirt.mesh = sk
	_skirt.material_override = smoke
	add_child(_skirt)
	_ring = MeshInstance3D.new()
	var rg := TorusMesh.new()
	rg.inner_radius = 0.85
	rg.outer_radius = 1.0
	_ring.mesh = rg
	_ring.scale = Vector3(1, 0.06, 1)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(1.0, 0.8, 0.5, 0.7)
	_ring.material_override = _ring_mat
	add_child(_ring)
	_light = OmniLight3D.new()
	_light.light_color = Color("#ff9a40")
	_light.light_energy = 9.0
	_light.omni_range = 110.0 * _y
	add_child(_light)
	_light.position = Vector3(0, 6.0 * _y, 0)

## The blast killed you: the camera pulls out for the view you earned.
func take_camera() -> void:
	_cam = Camera3D.new()
	_cam.far = 120000.0
	add_child(_cam)
	_cam.current = true

func _process(delta: float) -> void:
	_t += delta
	var p := clampf(_t / 9.0, 0.0, 1.0)
	var rise := 1.0 - pow(1.0 - p, 2.2)   # fast liftoff, slowing climb
	var cap_h := (3.0 + 19.0 * _y * rise)
	var cap_r := (1.5 + 8.5 * _y * rise)
	_cap.position = Vector3(0, cap_h, 0)
	_cap.scale = Vector3(cap_r, cap_r * 0.72, cap_r)
	_stem.position = Vector3(0, cap_h * 0.5, 0)
	_stem.scale = Vector3(2.2 * _y * (0.4 + 0.6 * rise), cap_h, 2.2 * _y * (0.4 + 0.6 * rise))
	_skirt.position = Vector3(0, cap_h * 0.62, 0)
	_skirt.scale = Vector3.ONE * (2.6 * _y * (0.3 + 0.7 * rise))
	_skirt.rotation.y += delta * 0.15
	# fireball: brilliant for two seconds, swallowed by its own smoke
	var fb := clampf(1.0 - _t / 2.4, 0.0, 1.0)
	_fire.position = Vector3(0, cap_h, 0)
	_fire.scale = Vector3.ONE * (cap_r * 0.85)
	(_fire.material_override as StandardMaterial3D).albedo_color = \
		Color(1.0, 0.55, 0.15, 1.0) * fb
	_fire.visible = fb > 0.01
	# the cap's inner glow cools from ember to dead soot
	var sm := _cap.material_override as StandardMaterial3D
	sm.emission_energy_multiplier = maxf(0.0, 2.2 * (1.0 - _t / 7.0))
	# shockwave: one expanding gasp along the ground
	var rw := _t * 26.0 * _y + 1.0
	_ring.scale = Vector3(rw, 0.06, rw)
	_ring_mat.albedo_color.a = maxf(0.0, 0.7 - _t * 0.28)
	_ring.visible = _ring_mat.albedo_color.a > 0.01
	_light.light_energy = maxf(0.0, 9.0 * (1.0 - _t / 6.0))
	# funeral orbit: WIDE view, always centered on the blast, high
	# enough to keep the horizon and the cloud in frame together
	if _cam != null:
		var ang := _t * 0.16
		var dist := 55.0 + 30.0 * _y
		_cam.fov = 72.0
		_cam.position = Vector3(cos(ang) * dist,
			cap_h * 0.75 + 16.0 + _t * 1.2, sin(ang) * dist)
		_cam.look_at(global_position + global_transform.basis.y * (cap_h * 0.55),
			global_transform.basis.y)
	# the long fade, then gone
	if _t > 30.0:
		var f := clampf(1.0 - (_t - 30.0) / 6.0, 0.0, 1.0)
		sm.albedo_color.a = f
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if f <= 0.0:
			queue_free()

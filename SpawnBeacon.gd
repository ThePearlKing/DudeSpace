class_name SpawnBeacon
extends StaticBody3D
## A placeable respawn point. Activate with F: glows green when it is your
## current spawn (dim otherwise). Built where you buy it.

var _mat: StandardMaterial3D
var _ring: MeshInstance3D
var _posts: Array = []

func _add_part(mesh: Mesh, pos: Vector3, col: Color, emit: float = 0.2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = Destructible.make_material(col, emit)
	add_child(mi)
	return mi

func _ready() -> void:
	add_to_group("spawn")
	collision_layer = 2   # clickable (F still works), not a wall: spawn ON it
	collision_mask = 0
	# landing pad: riveted octagon rim, glowing core, corner stanchions
	# with marker lights, and a slow holo-ring floating over the core
	var rim := CylinderMesh.new()
	rim.top_radius = 1.35
	rim.bottom_radius = 1.45
	rim.height = 0.14
	rim.radial_segments = 8
	_add_part(rim, Vector3(0, 0.07, 0), Color("#1a2a20"), 0.1)
	var core := CylinderMesh.new()
	core.top_radius = 0.95
	core.bottom_radius = 0.95
	core.height = 0.18
	core.radial_segments = 8
	var core_mi := _add_part(core, Vector3(0, 0.11, 0), Color("#204030"), 0.3)
	_mat = core_mi.material_override
	for ang in [45.0, 135.0, 225.0, 315.0]:
		var a := deg_to_rad(ang)
		var post := BoxMesh.new()
		post.size = Vector3(0.14, 0.8, 0.14)
		_add_part(post, Vector3(cos(a) * 1.25, 0.4, sin(a) * 1.25), Color("#1a2a20"), 0.1)
		var lamp := SphereMesh.new()
		lamp.radius = 0.09
		lamp.height = 0.18
		_posts.append(_add_part(lamp, Vector3(cos(a) * 1.25, 0.85, sin(a) * 1.25),
			Color("#2bff6a"), 0.6))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.55
	ring.outer_radius = 0.68
	_ring = _add_part(ring, Vector3(0, 1.1, 0), Color("#2bff6a"), 1.2)
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(2.6, 0.5, 2.6)
	col.shape = cs
	col.position = Vector3(0, 0.25, 0)
	add_child(col)
	var lbl := Label3D.new()
	lbl.text = "[F]"
	lbl.font_size = 26
	lbl.modulate = Color(1, 1, 1, 0.7)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, 1.7, 0)
	add_child(lbl)

func _process(delta: float) -> void:
	# dormant beacons sit GRAY. the one you claimed (F) burns green --
	# and since there is only one spawn point, claiming one silently
	# retires every other beacon back to gray.
	var mine := global_position.distance_to(Game.spawn_pos) < 2.0
	var glow := Color("#2bff6a") if mine else Color("#5a5f5c")
	_mat.albedo_color = Color("#204030") if mine else Color("#33383a")
	_mat.emission = glow
	_mat.emission_energy_multiplier = 5.0 if mine else 0.12
	if _ring:
		_ring.rotate_y(delta * (2.2 if mine else 0.2))
		_ring.position.y = 1.1 + sin(Time.get_ticks_msec() / 600.0) * (0.12 if mine else 0.02)
		_ring.material_override.emission = glow
		_ring.material_override.albedo_color = glow
		_ring.material_override.emission_energy_multiplier = 2.4 if mine else 0.15
	for p in _posts:
		p.material_override.emission = glow
		p.material_override.albedo_color = glow
		p.material_override.emission_energy_multiplier = 2.0 if mine else 0.15

func destroy(push_dir: Vector3) -> void:
	Net.broadcast_remove(global_position)
	Inventory.give("spawnbeacon", 1)
	Destructible.spawn_debris(get_parent(), global_position + Vector3(0, 0.3, 0), Vector3(1.2, 0.3, 1.2), Color("#204030"), push_dir)
	Sfx.play("explode", -12.0)
	queue_free()

func activate_spawn() -> void:
	var up := global_transform.basis.y
	Game.set_spawn(global_position + up * 1.2, up)

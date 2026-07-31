class_name SpawnBeacon
extends StaticBody3D
## A placeable respawn point. Activate with F: glows green when it is your
## current spawn (dim otherwise). Built where you buy it.

var _mat: StandardMaterial3D

func _ready() -> void:
	add_to_group("spawn")
	collision_layer = 2   # clickable (F still works), not a wall: spawn ON it
	collision_mask = 0
	# flat pad on the floor: dark rim, glowing green core panel
	var rim := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(2.0, 0.12, 2.0)
	rim.mesh = rm
	rim.position = Vector3(0, 0.06, 0)
	rim.material_override = Destructible.make_material(Color("#1a2a20"), 0.1)
	add_child(rim)
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(1.5, 0.16, 1.5)
	mi.mesh = m
	mi.position = Vector3(0, 0.1, 0)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color("#204030")
	_mat.emission_enabled = true
	_mat.emission = Color("#2bff6a")
	_mat.emission_energy_multiplier = 0.3
	mi.material_override = _mat
	add_child(mi)
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(2.0, 0.5, 2.0)
	col.shape = cs
	col.position = Vector3(0, 0.25, 0)
	add_child(col)
	var lbl := Label3D.new()
	lbl.text = "[F]"
	lbl.font_size = 26
	lbl.modulate = Color(1, 1, 1, 0.7)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, 1.0, 0)
	add_child(lbl)

func _process(_delta: float) -> void:
	var mine := global_position.distance_to(Game.spawn_pos) < 2.0
	_mat.emission_energy_multiplier = 5.0 if mine else 0.3

func destroy(push_dir: Vector3) -> void:
	Inventory.give("spawnbeacon", 1)
	Destructible.spawn_debris(get_parent(), global_position + Vector3(0, 0.3, 0), Vector3(1.2, 0.3, 1.2), Color("#204030"), push_dir)
	Sfx.play("explode", -12.0)
	queue_free()

func activate_spawn() -> void:
	var up := global_transform.basis.y
	Game.set_spawn(global_position + up * 1.2, up)

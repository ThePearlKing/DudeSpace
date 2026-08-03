class_name Waypoint
extends StaticBody3D
## A placeable marker. F toggles it on/off. While on, the HUD draws a
## diamond at its position from anywhere in the universe -- planets
## can't hide it. Can be stuck onto a rocket to track it in flight.

var enabled: bool = true
var _mat: StandardMaterial3D
var _mesh: MeshInstance3D

func _ready() -> void:
	add_to_group("waypoint")
	_mesh = MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.55, 0.55, 0.55)
	_mesh.mesh = m
	_mesh.rotation_degrees = Vector3(45, 0, 45)   # gem cut
	_mesh.position = Vector3(0, 0.6, 0)
	_mat = Destructible.make_material(Color("#ffd166"), 2.5)
	_mesh.material_override = _mat
	add_child(_mesh)
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.05
	pm.bottom_radius = 0.05
	pm.height = 0.5
	post.mesh = pm
	post.position = Vector3(0, 0.25, 0)
	post.material_override = Destructible.make_material(Color("#7a5c20"), 0.3)
	add_child(post)
	var col := CollisionShape3D.new()
	var cs := SphereShape3D.new()
	cs.radius = 0.7
	col.shape = cs
	col.position = Vector3(0, 0.55, 0)
	add_child(col)

func _process(delta: float) -> void:
	if _mesh:
		_mesh.rotate_y(delta * 1.5)
	_mat.emission_energy_multiplier = 2.5 if enabled else 0.15

func use() -> void:
	enabled = not enabled
	Sfx.play("click")

func destroy(push_dir: Vector3) -> void:
	Net.broadcast_remove(global_position)
	Inventory.give("waypoint", 1)
	Destructible.spawn_debris(get_parent(), global_position + Vector3(0, 0.5, 0),
		Vector3(0.5, 0.5, 0.5), Color("#ffd166"), push_dir)
	Sfx.play("explode", -16.0)
	queue_free()

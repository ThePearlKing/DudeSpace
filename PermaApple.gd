class_name PermaApple
extends StaticBody3D
## A rare, ominous apple growing on some plants. "Eat" it (shoot/harvest)
## and it is PERMADEATH -- unless an Anti-Permadeath Charm saves you.

func _ready() -> void:
	add_to_group("destructible")
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#8b0000")
	mat.emission_enabled = true
	mat.emission = Color("#ff0033")
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	add_child(mi)
	var stem := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = 0.4
	stem.mesh = cm
	stem.position = Vector3(0, 0.55, 0)
	stem.material_override = Destructible.make_material(Color("#3a2a10"), 0.0)
	add_child(stem)
	var col := CollisionShape3D.new()
	var cs := SphereShape3D.new()
	cs.radius = 0.5
	col.shape = cs
	add_child(col)

## Harvesting it is SAFE -- it goes to your hotbar. EATING it (right-click
## while held) is what ends you.
func destroy(_push_dir: Vector3) -> void:
	if not Inventory.any_space():
		Sfx.play("denied")
		return
	Inventory.give("permapple", 1)
	Sfx.play("coin")
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.flash("you picked the apple. do NOT eat it. seriously.")
	queue_free()

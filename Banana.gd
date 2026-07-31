class_name Banana
extends StaticBody3D
## Grows on plant branches. Shoot/punch to eat. Pottasium.

func _ready() -> void:
	add_to_group("destructible")
	for i in 3:
		var seg := MeshInstance3D.new()
		var m := CapsuleMesh.new()
		m.radius = 0.09
		m.height = 0.28
		seg.mesh = m
		seg.material_override = Destructible.make_material(Color("#ffe135"), 0.8)
		seg.position = Vector3(float(i) * 0.09, absf(float(i) - 1.0) * -0.05, 0)
		seg.rotation_degrees = Vector3(0, 0, 60 - float(i) * 30.0)
		add_child(seg)
	var col := CollisionShape3D.new()
	var cs := SphereShape3D.new()
	cs.radius = 0.35
	col.shape = cs
	add_child(col)

## Bananas are ITEMS: any hit picks one up. Eat it from the hotbar
## (right-click) -> heal + "Pottasium."
func destroy(_push_dir: Vector3) -> void:
	harvest()

func harvest() -> void:
	Inventory.add_res("banana", 1)
	Sfx.play("eat", -14.0)
	queue_free()

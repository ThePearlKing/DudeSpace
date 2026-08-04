class_name NeuralinkTerminal
extends StaticBody3D
## The Neuralink Terminal: browse every creature with a chip in its
## head, look through its eyes, drive it around, rewrite its soul.
## Sold in the Electric tab like it's a normal appliance. It is not.

func _ready() -> void:
	add_to_group("nterm")
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 1.0, 0.6)
	base.mesh = bm
	base.position = Vector3(0, 0.5, 0)
	base.material_override = Destructible.make_material(Color("#23232a"), 0.05)
	add_child(base)
	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.9, 0.6, 0.06)
	screen.mesh = sm
	screen.position = Vector3(0, 1.35, -0.1)
	screen.rotation_degrees.x = -12.0
	screen.material_override = Destructible.make_material(Color("#7bffb0"), 2.2)
	add_child(screen)
	var antenna := MeshInstance3D.new()
	var am := CylinderMesh.new()
	am.top_radius = 0.015
	am.bottom_radius = 0.03
	am.height = 0.7
	antenna.mesh = am
	antenna.position = Vector3(0.4, 1.9, 0.1)
	antenna.material_override = Destructible.make_material(Color("#aab", 1.0), 0.6)
	add_child(antenna)
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(1.1, 1.7, 0.7)
	col.shape = cs
	col.position = Vector3(0, 0.85, 0)
	add_child(col)
	var tag := Label3D.new()
	tag.text = "NEURALINK  [F]"
	tag.font_size = 18
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 2.2, 0)
	tag.modulate = Color(0.6, 1.0, 0.75, 0.9)
	tag.outline_size = 6
	add_child(tag)

func use() -> void:
	if get_tree().get_first_node_in_group("neuralink_ui") != null:
		return
	var ui := NeuralinkUI.new()
	get_tree().current_scene.add_child(ui)
	Sfx.play("click", -16.0)

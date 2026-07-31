class_name UFO
extends Node3D
## The alien trader's saucer. Only parks in the system on Tuesdays (and
## some Saturdays), somewhere different every time. F to trade ZeptoBux
## for alien goods. The pilot is exactly what you think an alien looks
## like: green head, big black ellipse eyes.

func _ready() -> void:
	add_to_group("ufo")
	# saucer: two flattened spheres + rim lights
	var hull := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 9.0
	hm.height = 4.0
	hull.mesh = hm
	hull.material_override = Destructible.make_material(Color("#9aa2b0"), 0.3)
	add_child(hull)
	var dome := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 3.6
	dm.height = 5.0
	dm.is_hemisphere = true
	dome.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.5, 0.9, 0.7, 0.35)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.emission_enabled = true
	dmat.emission = Color("#4dff9a")
	dmat.emission_energy_multiplier = 0.4
	dome.material_override = dmat
	dome.position = Vector3(0, 1.6, 0)
	add_child(dome)
	for i in 10:
		var a := TAU * float(i) / 10.0
		var lightb := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.5
		lm.height = 1.0
		lightb.mesh = lm
		lightb.material_override = Destructible.make_material(
			Color("#ffe066") if i % 2 == 0 else Color("#ff5aa0"), 5.0)
		lightb.position = Vector3(cos(a) * 8.2, -0.6, sin(a) * 8.2)
		add_child(lightb)

	# THE ALIEN: green head, black ellipse eyes, skinny body. classic.
	var alien := Node3D.new()
	alien.position = Vector3(0, 2.2, 0)
	add_child(alien)
	var head := MeshInstance3D.new()
	var hm2 := SphereMesh.new()
	hm2.radius = 0.9
	hm2.height = 2.2
	head.mesh = hm2
	head.material_override = Destructible.make_material(Color("#5ad65a"), 0.4)
	head.position = Vector3(0, 1.2, 0)
	alien.add_child(head)
	for sx in [-0.42, 0.42]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.34
		em.height = 0.44
		eye.mesh = em
		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color(0.02, 0.02, 0.03)
		emat.metallic = 0.8
		emat.roughness = 0.1
		eye.material_override = emat
		eye.position = Vector3(sx, 1.35, -0.62)
		eye.rotation_degrees = Vector3(20, 0, sx * 45.0)
		alien.add_child(eye)
	var bod := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.3
	bm.height = 1.6
	bod.mesh = bm
	bod.material_override = Destructible.make_material(Color("#4ab04a"), 0.2)
	bod.position = Vector3(0, 0, 0)
	alien.add_child(bod)

	var col := CollisionShape3D.new()
	var cs := SphereShape3D.new()
	cs.radius = 9.0
	col.shape = cs
	var body := StaticBody3D.new()
	body.add_child(col)
	add_child(body)

	var lbl := Label3D.new()
	lbl.text = "TRADER  [F]"
	lbl.font_size = 48
	lbl.modulate = Color("#4dff9a")
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, 7.0, 0)
	add_child(lbl)

var _t: float = 0.0

func _process(delta: float) -> void:
	_t += delta
	rotate_y(delta * 0.4)
	position.y += sin(_t * 0.8) * 0.02   # gentle bob

func use() -> void:
	var ui := get_tree().get_first_node_in_group("trader_ui")
	if ui and ui.has_method("open"):
		ui.open()

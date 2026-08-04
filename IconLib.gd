class_name IconLib
extends RefCounted
## Live 3D icons for the menus: the item's actual model, slowly
## spinning, rendered in a tiny private viewport. One viewport per item
## id, shared by every cell that shows that item. The color chip stays
## underneath as the background.

static var _pool := {}   # id -> SubViewport

static func _host(tree: SceneTree) -> Node:
	var root := tree.root
	var h := root.get_node_or_null("IconHost")
	if h == null:
		h = Node.new()
		h.name = "IconHost"
		root.add_child(h)
	return h

## The one true model pipeline: real world object > the player's own
## hand model > curated minis > resource silhouette. Never a bare cube.
static func build_model_world(id: String, tree: SceneTree) -> Node3D:
	var holder := Node3D.new()
	var cs = tree.current_scene
	if cs != null and cs.has_method("_spawn_world_obj"):
		var real = cs._spawn_world_obj(id)
		if real != null:
			real.process_mode = Node.PROCESS_MODE_DISABLED
			holder.add_child(real)
			var ext := 1.4
			if "box_size" in real:
				ext = maxf(real.box_size.x, maxf(real.box_size.y, real.box_size.z))
			var sc := 0.62 / maxf(0.6, ext)
			real.scale = Vector3(sc, sc, sc)
			real.position = Vector3(0, -0.25, 0)
			return holder
	holder.add_child(build_model(id, tree))
	return holder

static func tex(id: String, tree: SceneTree) -> Texture2D:
	if _pool.has(id) and is_instance_valid(_pool[id]):
		return _pool[id].get_texture()
	var vp := SubViewport.new()
	vp.size = Vector2i(96, 96)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_host(tree).add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.position = Vector3(0, 0.5, 1.5)
	cam.look_at_from_position(cam.position, Vector3(0, 0.05, 0), Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 32, 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	var holder := Node3D.new()
	vp.add_child(holder)
	holder.add_child(build_model_world(id, tree))
	# the spin: unhurried, like a furniture showroom
	var tw := holder.create_tween().set_loops()
	tw.tween_property(holder, "rotation:y", TAU, 9.0).from(0.0)
	_pool[id] = vp
	return vp.get_texture()

## The player's own hand model, if it amounts to anything.
static func _hand_model(id: String, tree: SceneTree) -> Node3D:
	var pl = tree.get_first_node_in_group("player")
	if pl == null or not pl.has_method("model_for"):
		return null
	var m: Node3D = pl.model_for(id)
	if m.get_child_count() == 0:
		m.queue_free()
		return null
	return m

static func _bx(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b

static func _cage_bars(r: Node3D, c: Color) -> void:
	for ang in [0, 45, 90, 135]:
		var bar := CylinderMesh.new()
		bar.top_radius = 0.03
		bar.bottom_radius = 0.03
		bar.height = 0.55
		_p(r, bar, Vector3(cos(deg_to_rad(ang)) * 0.22, 0,
			sin(deg_to_rad(ang)) * 0.22), c, 0.3)
		_p(r, bar.duplicate(), Vector3(-cos(deg_to_rad(ang)) * 0.22, 0,
			-sin(deg_to_rad(ang)) * 0.22), c, 0.3)
	var top := CylinderMesh.new()
	top.top_radius = 0.26
	top.bottom_radius = 0.26
	top.height = 0.05
	_p(r, top, Vector3(0, 0.28, 0), c, 0.3)
	_p(r, top.duplicate(), Vector3(0, -0.28, 0), c, 0.3)

static func _color_of(id: String) -> Color:
	if Inventory.items.has(id):
		return Inventory.items[id]["color"]
	if Inventory.weapons.has(id):
		return Inventory.weapons[id]["color"]
	if Inventory.armors.has(id):
		return Inventory.armors[id]["color"]
	return Color("#8890a0")

static func _p(root: Node3D, mesh: Mesh, pos: Vector3, col: Color,
		e := 0.3, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = Destructible.make_material(col, e)
	root.add_child(mi)

## EVERY item gets a real little model -- family by family, with the
## resource silhouettes reused where they exist and a detailed
## fallback (never a bare cube) for the rest.
static func build_model(id: String, tree: SceneTree = null) -> Node3D:
	var r := Node3D.new()
	var c := _color_of(id)
	var box := BoxMesh.new()
	match id:
		"meat", "cooked_meat":
			var slab := BoxMesh.new()
			slab.size = Vector3(0.55, 0.22, 0.4)
			_p(r, slab, Vector3.ZERO, c)
			var bone := CylinderMesh.new()
			bone.top_radius = 0.05
			bone.bottom_radius = 0.05
			bone.height = 0.5
			_p(r, bone, Vector3(0.25, 0, 0), Color("#e8e2d4"), 0.2, Vector3(0, 0, 90))
		"banana":
			for i in 3:
				var seg := CapsuleMesh.new()
				seg.radius = 0.09
				seg.height = 0.34
				_p(r, seg, Vector3(-0.15 + 0.15 * i, [0.0, 0.09, 0.0][i], 0), c,
					0.3, Vector3(0, 0, 55 - 55 * i))
		"shroom":
			var stem := CylinderMesh.new()
			stem.top_radius = 0.09
			stem.bottom_radius = 0.12
			stem.height = 0.3
			_p(r, stem, Vector3(0, -0.1, 0), Color("#e8e0d0"), 0.2)
			var cap := SphereMesh.new()
			cap.radius = 0.24
			cap.height = 0.24
			cap.is_hemisphere = true
			_p(r, cap, Vector3(0, 0.05, 0), c)
		"salad":
			var bowl := SphereMesh.new()
			bowl.radius = 0.3
			bowl.height = 0.3
			bowl.is_hemisphere = true
			_p(r, bowl, Vector3(0, -0.2, 0), Color("#c9b8a0"), 0.15, Vector3(180, 0, 0))
			for i in 4:
				var leaf := SphereMesh.new()
				leaf.radius = 0.1
				leaf.height = 0.16
				_p(r, leaf, Vector3(randf_range(-0.12, 0.12), -0.05,
					randf_range(-0.12, 0.12)), c)
		"apple", "permapple":
			var ap := SphereMesh.new()
			ap.radius = 0.26
			ap.height = 0.48
			_p(r, ap, Vector3.ZERO, c)
			var stem2 := CylinderMesh.new()
			stem2.top_radius = 0.02
			stem2.bottom_radius = 0.03
			stem2.height = 0.16
			_p(r, stem2, Vector3(0, 0.3, 0), Color("#5a3a1a"), 0.1)
		"wire":
			var t := TorusMesh.new()
			t.inner_radius = 0.16
			t.outer_radius = 0.3
			_p(r, t, Vector3.ZERO, c, 0.3, Vector3(60, 0, 0))
		"coil":
			var core := CylinderMesh.new()
			core.top_radius = 0.1
			core.bottom_radius = 0.1
			core.height = 0.5
			_p(r, core, Vector3.ZERO, Color("#6a5a40"), 0.15)
			for i in 3:
				var w2 := TorusMesh.new()
				w2.inner_radius = 0.1
				w2.outer_radius = 0.18
				_p(r, w2, Vector3(0, -0.14 + 0.14 * i, 0), c, 0.5)
		"grenade":
			var body := SphereMesh.new()
			body.radius = 0.24
			body.height = 0.48
			_p(r, body, Vector3.ZERO, c)
			var pin := TorusMesh.new()
			pin.inner_radius = 0.05
			pin.outer_radius = 0.1
			_p(r, pin, Vector3(0.1, 0.3, 0), Color("#c8c8c8"), 0.4, Vector3(90, 0, 0))
		"nchip":
			var chip := BoxMesh.new()
			chip.size = Vector3(0.4, 0.08, 0.4)
			_p(r, chip, Vector3.ZERO, Color("#1a2a1e"), 0.1)
			var led := SphereMesh.new()
			led.radius = 0.07
			led.height = 0.14
			_p(r, led, Vector3(0, 0.09, 0), c, 2.0)
		"caged_human":
			_cage_bars(r, c)
			# the occupant: the NEXT human out of storage, in miniature
			var hdata := {}
			for i in range(Inventory.caged_data.size() - 1, -1, -1):
				var e0 = Inventory.caged_data[i]
				if e0 is Dictionary and e0.has("human"):
					hdata = e0["human"]
					break
			var skin := Color(str(hdata.get("skin", "b58a6a")))
			var shirt := Color(str(hdata.get("shirt_col", "5a7aa0")))
			_p(r, _bx(0.14, 0.14, 0.14), Vector3(0, 0.16, 0), skin, 0.15)
			_p(r, _bx(0.18, 0.22, 0.1), Vector3(0, -0.04, 0), shirt, 0.15)
			for lx2 in [-0.05, 0.05]:
				_p(r, _bx(0.07, 0.18, 0.07), Vector3(lx2, -0.22, 0),
					Color("#2b3a5e"), 0.1)
		"caged_animal":
			_cage_bars(r, c)
			# a small unidentified mammal. it's fine. probably tamed.
			_p(r, _bx(0.26, 0.16, 0.16), Vector3(0, -0.1, 0), Color("#9a8a6a"), 0.15)
			_p(r, _bx(0.12, 0.12, 0.1), Vector3(0.16, 0.0, 0), Color("#9a8a6a"), 0.15)
			for lx3 in [-0.08, 0.08]:
				_p(r, _bx(0.05, 0.1, 0.05), Vector3(lx3, -0.22, 0),
					Color("#7a6a50"), 0.1)
		"cage":
			_cage_bars(r, c)
		"bench":
			var seat := BoxMesh.new()
			seat.size = Vector3(0.6, 0.05, 0.2)
			_p(r, seat, Vector3.ZERO, c)
			var back := BoxMesh.new()
			back.size = Vector3(0.6, 0.18, 0.04)
			_p(r, back, Vector3(0, 0.12, 0.09), c)
		"furnkit":
			var seat2 := BoxMesh.new()
			seat2.size = Vector3(0.42, 0.05, 0.2)
			_p(r, seat2, Vector3(-0.1, 0, 0), c)
			var bed := BoxMesh.new()
			bed.size = Vector3(0.24, 0.1, 0.34)
			_p(r, bed, Vector3(0.22, -0.05, 0), Color("#a04848"), 0.2)
		"housekit":
			var hb := BoxMesh.new()
			hb.size = Vector3(0.45, 0.3, 0.45)
			_p(r, hb, Vector3(0, -0.08, 0), c)
			var roof := CylinderMesh.new()
			roof.top_radius = 0.0
			roof.bottom_radius = 0.38
			roof.height = 0.25
			roof.radial_segments = 4
			_p(r, roof, Vector3(0, 0.2, 0), Color("#7a4a3a"), 0.15, Vector3(0, 45, 0))
		"fuel":
			var can := CylinderMesh.new()
			can.top_radius = 0.18
			can.bottom_radius = 0.18
			can.height = 0.5
			_p(r, can, Vector3.ZERO, c)
			var cap2 := CylinderMesh.new()
			cap2.top_radius = 0.07
			cap2.bottom_radius = 0.07
			cap2.height = 0.1
			_p(r, cap2, Vector3(0, 0.3, 0), Color("#c8c8c8"), 0.3)
		"rocket", "rocket2":
			var hull := CylinderMesh.new()
			hull.top_radius = 0.12
			hull.bottom_radius = 0.16
			hull.height = 0.55
			_p(r, hull, Vector3.ZERO, c)
			var nose := CylinderMesh.new()
			nose.top_radius = 0.0
			nose.bottom_radius = 0.12
			nose.height = 0.2
			_p(r, nose, Vector3(0, 0.37, 0), Color("#ff5964"), 0.4)
		_:
			if Inventory.weapons.has(id) and id != "fists":
				# gun family: body + barrel + grip
				var gb := BoxMesh.new()
				gb.size = Vector3(0.5, 0.16, 0.12)
				_p(r, gb, Vector3.ZERO, c)
				var brl := CylinderMesh.new()
				brl.top_radius = 0.035
				brl.bottom_radius = 0.035
				brl.height = 0.34
				_p(r, brl, Vector3(0.35, 0.03, 0), Color("#2a2a30"), 0.15,
					Vector3(0, 0, 90))
				var grip := BoxMesh.new()
				grip.size = Vector3(0.1, 0.2, 0.1)
				_p(r, grip, Vector3(-0.15, -0.16, 0), Color("#3a2c20"), 0.1)
			elif Inventory.armors.has(id):
				# armor: curved chest plate + shoulder bumps
				var plate := BoxMesh.new()
				plate.size = Vector3(0.44, 0.4, 0.16)
				_p(r, plate, Vector3.ZERO, c)
				for sx in [-0.26, 0.26]:
					var sh2 := SphereMesh.new()
					sh2.radius = 0.11
					sh2.height = 0.22
					_p(r, sh2, Vector3(sx, 0.2, 0), c)
			elif tree != null and _hand_model(id, tree) != null:
				var hm := _hand_model(id, tree)
				hm.scale = Vector3(1.4, 1.4, 1.4)
				r.add_child(hm)
			elif ItemDrop._resource_mesh(id) is BoxMesh:
				# machine/misc fallback: chassis + face panel + little
				# stack, so NOTHING is ever a bare spinning cube
				var ch := BoxMesh.new()
				ch.size = Vector3(0.44, 0.4, 0.44)
				_p(r, ch, Vector3.ZERO, c)
				var panel := BoxMesh.new()
				panel.size = Vector3(0.3, 0.2, 0.03)
				_p(r, panel, Vector3(0, 0.02, -0.23), c.lightened(0.45), 1.2)
				var stack2 := CylinderMesh.new()
				stack2.top_radius = 0.05
				stack2.bottom_radius = 0.07
				stack2.height = 0.2
				_p(r, stack2, Vector3(0.12, 0.3, 0.1), Color("#3a3f46"), 0.1)
			else:
				# a resource with its own silhouette: use it
				var mi2 := MeshInstance3D.new()
				mi2.mesh = ItemDrop._resource_mesh(id)
				mi2.material_override = Destructible.make_material(c, 0.35)
				r.add_child(mi2)
	return r

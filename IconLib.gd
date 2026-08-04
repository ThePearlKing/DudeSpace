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
	var mi := MeshInstance3D.new()
	mi.mesh = ItemDrop._resource_mesh(id)
	var col: Color = Color("#8890a0")
	if Inventory.items.has(id):
		col = Inventory.items[id]["color"]
	elif Inventory.weapons.has(id):
		col = Inventory.weapons[id]["color"]
	elif Inventory.armors.has(id):
		col = Inventory.armors[id]["color"]
	mi.material_override = Destructible.make_material(col, 0.35)
	holder.add_child(mi)
	# the spin: unhurried, like a shopping channel
	var tw := holder.create_tween().set_loops()
	tw.tween_property(holder, "rotation:y", TAU, 4.0).from(0.0)
	_pool[id] = vp
	return vp.get_texture()

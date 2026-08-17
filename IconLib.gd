class_name IconLib
extends RefCounted
## Live 3D icons for the menus: the item's actual model, slowly
## spinning, rendered in a tiny private viewport. One viewport per item
## id, shared by every cell that shows that item. The color chip stays
## underneath as the background.

static var _pool := {}   # id -> SubViewport
static var _used := {}   # id -> when it was last asked for, in msec
## Godot allows 64 viewports per 3D scenario and every spinning icon is
## one of them. Once the shop grew past that the renderer started
## refusing them outright, so the pool is capped and the least recently
## looked-at icon gets recycled.
const MAX_ICONS := 40
const KEEP_MSEC := 4000

## Quit-time hygiene: free the icon viewports before the renderer dies.
static func shutdown(tree: SceneTree) -> void:
	_pool.clear()
	_used.clear()
	var h := tree.root.get_node_or_null("IconHost")
	if h != null:
		h.free()

static func _host(tree: SceneTree) -> Node:
	var root := tree.root
	var h := root.get_node_or_null("IconHost")
	if h == null:
		h = Node.new()
		h.name = "IconHost"
		root.add_child(h)
		# whatever way the game exits (menu quit, window X, --quit-after),
		# the icon viewports die BEFORE the renderer -- no leaked RIDs
		tree.root.tree_exiting.connect(func() -> void:
			_pool.clear()
			var hh := tree.root.get_node_or_null("IconHost")
			if hh != null:
				hh.free())
	return h

## THE ONE MODEL PIPELINE. An item has exactly one model, used for the
## ground drop, the inventory icon, and the hand alike: the real world
## object if it is placeable, else the hand model, else the curated
## registry. There is no icon-only model and there never will be again.
## (Armor keeps its separate WEARING model -- that is the one allowed
## exception.)
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
	var hm := _hand_model(id, tree)
	if hm != null:
		hm.scale = Vector3(1.4, 1.4, 1.4)
		holder.add_child(hm)
		return holder
	holder.add_child(build_model(id, tree))
	return holder

static func tex(id: String, tree: SceneTree) -> Texture2D:
	_used[id] = Time.get_ticks_msec()
	if _pool.has(id) and is_instance_valid(_pool[id]):
		return _pool[id].get_texture()
	if not _make_room():
		return null      # everything on screen is in use: the colour chip stands in
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

## Recycle the icon nobody has looked at for a while. Returns false if
## every icon in the pool is still in active use, in which case the
## caller does without rather than blowing the viewport limit.
static func _make_room() -> bool:
	while _pool.size() >= MAX_ICONS:
		var oldest := ""
		var oldest_t := 9223372036854775807
		for k in _pool.keys():
			var t := int(_used.get(k, 0))
			if t < oldest_t:
				oldest_t = t
				oldest = str(k)
		if oldest == "" or Time.get_ticks_msec() - oldest_t < KEEP_MSEC:
			return false
		var vp = _pool[oldest]
		if is_instance_valid(vp):
			vp.queue_free()
		_pool.erase(oldest)
		_used.erase(oldest)
	return true

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
		"dudemap":
			# the facility map: an amber slate with a glowing route line
			var slate := BoxMesh.new()
			slate.size = Vector3(0.44, 0.05, 0.34)
			_p(r, slate, Vector3.ZERO, Color("#1c2026"), 0.2)
			var tr9 := BoxMesh.new()
			tr9.size = Vector3(0.3, 0.02, 0.03)
			_p(r, tr9, Vector3(0, 0.04, -0.04), Color("#66ff99"), 1.6,
				Vector3(0, 15, 0))
			var tr2 := BoxMesh.new()
			tr2.size = Vector3(0.16, 0.02, 0.03)
			_p(r, tr2, Vector3(0.05, 0.04, 0.07), Color("#ffb000"), 1.6,
				Vector3(0, -30, 0))
		"toothpaste", "ulti_toothpaste", "ultra_toothpaste", "omega_toothpaste":
			# a crimped tube with a screw cap -- it is still toothpaste
			_p(r, _bx(0.2, 0.5, 0.12), Vector3(0, -0.02, 0), c, 0.35)
			_p(r, _bx(0.24, 0.06, 0.03), Vector3(0, 0.24, 0), c.darkened(0.4), 0.2)
			_p(r, _bx(0.16, 0.03, 0.13), Vector3(0, 0.1, 0), c.lightened(0.5), 0.9)
			var tcap := CylinderMesh.new()
			tcap.top_radius = 0.06
			tcap.bottom_radius = 0.06
			tcap.height = 0.1
			_p(r, tcap, Vector3(0, -0.32, 0), c.darkened(0.55), 0.2)
		"timmy":
			# the most complicated material anybody has made: a lit core
			# inside two crossed rings, spinning on nothing
			var core := SphereMesh.new()
			core.radius = 0.2
			core.height = 0.4
			core.radial_segments = 4
			core.rings = 2
			_p(r, core, Vector3.ZERO, c, 2.2)
			for rr in [Vector3.ZERO, Vector3(90, 0, 0), Vector3(0, 0, 90)]:
				var ring0 := TorusMesh.new()
				ring0.inner_radius = 0.26
				ring0.outer_radius = 0.3
				_p(r, ring0, Vector3.ZERO, Color("#7df9ff"), 1.6, rr)
		"liqblackhole":
			# a bottle with a hole in it. The hole is the point
			var jarm := CylinderMesh.new()
			jarm.top_radius = 0.16
			jarm.bottom_radius = 0.2
			jarm.height = 0.46
			_p(r, jarm, Vector3(0, -0.04, 0), Color("#2a2438"), 0.1)
			var evt := SphereMesh.new()
			evt.radius = 0.13
			evt.height = 0.26
			_p(r, evt, Vector3(0, -0.04, 0), Color("#05030a"), 0.0)
			var acc := TorusMesh.new()
			acc.inner_radius = 0.14
			acc.outer_radius = 0.19
			_p(r, acc, Vector3(0, -0.04, 0), Color("#c86bff"), 2.4)
			_p(r, _bx(0.1, 0.08, 0.1), Vector3(0, 0.23, 0), Color("#8a8f9a"), 0.3)
		"dna4d":
			# two strands climbing past each other, rungs between them
			for k in 8:
				var t9 := float(k) / 7.0
				var a9 := t9 * TAU * 1.2
				var bead := SphereMesh.new()
				bead.radius = 0.055
				bead.height = 0.11
				var y9 := -0.28 + t9 * 0.56
				_p(r, bead, Vector3(cos(a9) * 0.13, y9, sin(a9) * 0.13), c, 1.2)
				_p(r, bead.duplicate(), Vector3(-cos(a9) * 0.13, y9,
					-sin(a9) * 0.13), Color("#7be8ff"), 1.2)
				if k % 2 == 0:
					_p(r, _bx(0.26, 0.018, 0.018), Vector3(0, y9, 0),
						Color("#e8f0d8"), 0.6,
						Vector3(0, -rad_to_deg(a9), 0))
		_ when Mats.has(id) and str(Mats.def(id).get("kind", "")) == "liquid":
			# a round-bottom flask, filled to the shoulder, stoppered
			var bulb := SphereMesh.new()
			bulb.radius = 0.22
			bulb.height = 0.42
			_p(r, bulb, Vector3(0, -0.08, 0), Color(c, 0.9), 0.9)
			var neck := CylinderMesh.new()
			neck.top_radius = 0.07
			neck.bottom_radius = 0.09
			neck.height = 0.26
			_p(r, neck, Vector3(0, 0.19, 0), Color("#b8ccd8"), 0.25)
			_p(r, _bx(0.11, 0.06, 0.11), Vector3(0, 0.34, 0), Color("#5a4a3a"), 0.15)
			var lip := TorusMesh.new()
			lip.inner_radius = 0.075
			lip.outer_radius = 0.1
			_p(r, lip, Vector3(0, 0.29, 0), Color("#d8e8f0"), 0.4)
		_ when Mats.has(id) and str(Mats.def(id).get("kind", "")) == "gas":
			# a pressure bottle: shoulder, valve, gauge, and the gas lit
			# up inside the glass window
			var body9 := CylinderMesh.new()
			body9.top_radius = 0.17
			body9.bottom_radius = 0.19
			body9.height = 0.5
			_p(r, body9, Vector3(0, -0.04, 0), Color("#8d97a5"), 0.15)
			var win := CylinderMesh.new()
			win.top_radius = 0.13
			win.bottom_radius = 0.13
			win.height = 0.26
			_p(r, win, Vector3(0, -0.04, 0), c, 1.6)
			var shoulder := SphereMesh.new()
			shoulder.radius = 0.17
			shoulder.height = 0.2
			shoulder.is_hemisphere = true
			_p(r, shoulder, Vector3(0, 0.21, 0), Color("#9aa8bc"), 0.2)
			var valve9 := CylinderMesh.new()
			valve9.top_radius = 0.045
			valve9.bottom_radius = 0.06
			valve9.height = 0.12
			_p(r, valve9, Vector3(0, 0.35, 0), Color("#c8722f"), 0.3)
			var gauge := CylinderMesh.new()
			gauge.top_radius = 0.06
			gauge.bottom_radius = 0.06
			gauge.height = 0.03
			_p(r, gauge, Vector3(0.13, 0.3, 0), Color("#e8e2d0"), 0.5,
				Vector3(0, 0, 90))
		_ when Mats.has(id) and str(Mats.def(id).get("kind", "")) == "solid":
			# a clamp-lid jar with the compound heaped inside it
			var jar := CylinderMesh.new()
			jar.top_radius = 0.21
			jar.bottom_radius = 0.21
			jar.height = 0.4
			_p(r, jar, Vector3(0, -0.06, 0), Color("#aebfcc"), 0.1)
			for k in 5:
				var gr := SphereMesh.new()
				gr.radius = 0.09 - float(k) * 0.008
				gr.height = 0.12 - float(k) * 0.01
				gr.radial_segments = 4
				gr.rings = 2
				var a8 := TAU * float(k) / 5.0
				_p(r, gr, Vector3(cos(a8) * 0.08, -0.12 + (0.05 if k % 2 else 0.0),
					sin(a8) * 0.08), c, 0.7)
			var lid := CylinderMesh.new()
			lid.top_radius = 0.22
			lid.bottom_radius = 0.22
			lid.height = 0.07
			_p(r, lid, Vector3(0, 0.17, 0), Color("#6f7f93"), 0.2)
			_p(r, _bx(0.06, 0.16, 0.03), Vector3(0, 0.09, 0.21),
				Color("#c8ccd4"), 0.3)
		_ when Mats.has(id) and str(Mats.def(id).get("kind", "")) == "ore":
			# a fist of rough rock with the metal showing through
			for ofs in [Vector3(0, -0.02, 0), Vector3(0.11, 0.05, 0.04),
					Vector3(-0.1, 0.03, -0.06), Vector3(0.02, 0.12, -0.05)]:
				var rock := SphereMesh.new()
				rock.radius = 0.15 if ofs.y > 0.0 else 0.2
				rock.height = 0.26 if ofs.y > 0.0 else 0.34
				rock.radial_segments = 5
				rock.rings = 2
				_p(r, rock, ofs, Color("#4a4038").lerp(c, 0.25), 0.1,
					Vector3(ofs.x * 300.0, ofs.z * 400.0, ofs.y * 260.0))
				var vein := BoxMesh.new()
				vein.size = Vector3(0.09, 0.03, 0.03)
				_p(r, vein, ofs + Vector3(0.02, 0.09, 0.05), c, 1.1,
					Vector3(0, ofs.x * 300.0, 25.0))
		_ when Mats.has(id) and str(Mats.def(id).get("kind", "")) == "dust":
			# a little heap of crushed grain on a pan
			var pan := CylinderMesh.new()
			pan.top_radius = 0.3
			pan.bottom_radius = 0.26
			pan.height = 0.06
			_p(r, pan, Vector3(0, -0.14, 0), Color("#2c2f36"), 0.05)
			for k in 7:
				var g := SphereMesh.new()
				g.radius = 0.07 - float(k) * 0.006
				g.height = 0.1 - float(k) * 0.008
				g.radial_segments = 4
				g.rings = 2
				var a := TAU * float(k) / 7.0
				_p(r, g, Vector3(cos(a) * 0.11, -0.06 + (0.05 if k % 2 == 0 else 0.0),
					sin(a) * 0.11), c, 0.35)
			var top := SphereMesh.new()
			top.radius = 0.1
			top.height = 0.13
			top.radial_segments = 5
			top.rings = 2
			_p(r, top, Vector3(0, 0.02, 0), c, 0.4)
		_ when Mats.has(id) and str(Mats.def(id).get("kind", "")) == "alloy":
			# a poured bar with a bevelled top and a hot seam down it
			_p(r, _bx(0.62, 0.16, 0.3), Vector3(0, -0.05, 0), c.darkened(0.25), 0.35)
			_p(r, _bx(0.5, 0.1, 0.22), Vector3(0, 0.06, 0), c, 0.6)
			_p(r, _bx(0.44, 0.02, 0.04), Vector3(0, 0.12, 0), c.lightened(0.5), 1.6)
			_p(r, _bx(0.06, 0.14, 0.24), Vector3(-0.29, -0.03, 0), c.darkened(0.45), 0.2)
			_p(r, _bx(0.06, 0.14, 0.24), Vector3(0.29, -0.03, 0), c.darkened(0.45), 0.2)
		_ when Mats.has(id) and str(Mats.def(id).get("kind", "")) == "ingot":
			# the plain trapezoid bar, stamped
			_p(r, _bx(0.6, 0.15, 0.3), Vector3(0, -0.04, 0), c, 0.4)
			_p(r, _bx(0.46, 0.09, 0.22), Vector3(0, 0.08, 0), c.lightened(0.2), 0.55)
			_p(r, _bx(0.12, 0.02, 0.12), Vector3(0, 0.13, 0), c.darkened(0.4), 0.15)
		"raw_ingot", "raw_irid", "coal", "uranium":
			var lump := SphereMesh.new()
			lump.radius = [0.32, 0.34, 0.24, 0.26][["raw_ingot", "raw_irid",
				"coal", "uranium"].find(id)]
			lump.height = [0.5, 0.4, 0.36, 0.44][["raw_ingot", "raw_irid",
				"coal", "uranium"].find(id)]
			lump.radial_segments = 6 if id == "raw_ingot" else 5
			lump.rings = 3 if id == "raw_ingot" else 2
			_p(r, lump, Vector3.ZERO, c, 0.5)
		"ingot":
			_p(r, _bx(0.62, 0.18, 0.3), Vector3.ZERO, c, 0.4)
		"irid":
			var puck := CylinderMesh.new()
			puck.top_radius = 0.28
			puck.bottom_radius = 0.28
			puck.height = 0.16
			puck.radial_segments = 6
			_p(r, puck, Vector3.ZERO, c, 0.5)
		"ultima":
			var gem := SphereMesh.new()
			gem.radius = 0.26
			gem.height = 0.62
			gem.radial_segments = 4
			gem.rings = 2
			_p(r, gem, Vector3.ZERO, c, 1.0)
		"prism":
			var shard := PrismMesh.new()
			shard.size = Vector3(0.34, 0.6, 0.24)
			_p(r, shard, Vector3.ZERO, c, 0.8)
		"sulfur":
			var wedge := PrismMesh.new()
			wedge.size = Vector3(0.4, 0.34, 0.3)
			_p(r, wedge, Vector3.ZERO, c, 0.4)
		"semicircle":
			var dome := SphereMesh.new()
			dome.radius = 0.32
			dome.height = 0.32
			dome.is_hemisphere = true
			_p(r, dome, Vector3.ZERO, c, 0.5)
		"circle":
			var ring9 := TorusMesh.new()
			ring9.inner_radius = 0.16
			ring9.outer_radius = 0.34
			_p(r, ring9, Vector3.ZERO, c, 0.5)
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
			elif tree != null and Inventory.armors.has(id) \
					and _hand_model(id, tree) != null:
				# armor previews use THE item model -- no separate icon
				var am9 := _hand_model(id, tree)
				am9.scale = Vector3(1.5, 1.5, 1.5)
				r.add_child(am9)
			elif tree != null and _hand_model(id, tree) != null:
				var hm := _hand_model(id, tree)
				hm.scale = Vector3(1.4, 1.4, 1.4)
				r.add_child(hm)
			else:
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
	return r

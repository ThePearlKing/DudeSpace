class_name ItemDrop
extends Node3D
## An item lying in the world (inventory overflow). Spins, glows, and
## hops back in the moment a slot opens and you walk over it.

var id: String = ""
var count: int = 1
var _mesh: MeshInstance3D
var _t: float = 0.0

func setup(id_in: String, n: int) -> void:
	id = id_in
	count = n

func _ready() -> void:
	add_to_group("itemdrop")
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _resource_mesh(id)
	var col: Color = Inventory.items[id]["color"] if Inventory.items.has(id) \
		else (Inventory.weapons[id]["color"] if Inventory.weapons.has(id) else Color("#cccccc"))
	_mesh.material_override = Destructible.make_material(col, 1.2)
	_mesh.position = Vector3(0, 0.5, 0)
	add_child(_mesh)
	var lbl := Label3D.new()
	lbl.text = (Inventory.hotbar_name(id) + (" ×%d" % count if count > 1 else ""))
	lbl.font_size = 20
	lbl.modulate = Color(1, 1, 1, 0.8)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, 1.2, 0)
	add_child(lbl)

## Each ore/resource gets its own silhouette; everything else stays a cube.
static func _resource_mesh(rid: String) -> Mesh:
	match rid:
		"raw_ingot":   # lumpy low-poly ore rock
			var m := SphereMesh.new()
			m.radius = 0.32; m.height = 0.5
			m.radial_segments = 6; m.rings = 3
			return m
		"raw_irid":    # squatter, coarser lump
			var m := SphereMesh.new()
			m.radius = 0.34; m.height = 0.4
			m.radial_segments = 5; m.rings = 2
			return m
		"coal":        # small dark nugget
			var m := SphereMesh.new()
			m.radius = 0.24; m.height = 0.36
			m.radial_segments = 5; m.rings = 2
			return m
		"ingot":       # smelted bar
			var m := BoxMesh.new()
			m.size = Vector3(0.62, 0.18, 0.3)
			return m
		"irid":        # refined hex puck
			var m := CylinderMesh.new()
			m.top_radius = 0.28; m.bottom_radius = 0.28; m.height = 0.16
			m.radial_segments = 6
			return m
		"ultima":      # octahedral gem
			var m := SphereMesh.new()
			m.radius = 0.26; m.height = 0.62
			m.radial_segments = 4; m.rings = 2
			return m
		"prism":       # triangular shard, name says it all
			var m := PrismMesh.new()
			m.size = Vector3(0.34, 0.6, 0.24)
			return m
		"uranium":     # jagged hot pebble -- you can tell it's bad for you
			var m := SphereMesh.new()
			m.radius = 0.26; m.height = 0.44
			m.radial_segments = 5; m.rings = 2
			return m
		"sulfur":      # crumbly yellow crystal wedge
			var m := PrismMesh.new()
			m.size = Vector3(0.4, 0.34, 0.3)
			return m
		"semicircle":  # half a dome
			var m := SphereMesh.new()
			m.radius = 0.32; m.height = 0.32
			m.is_hemisphere = true
			return m
		"circle":      # a perfect ring
			var m := TorusMesh.new()
			m.inner_radius = 0.16; m.outer_radius = 0.34
			return m
		_:
			var m := BoxMesh.new()
			m.size = Vector3(0.5, 0.5, 0.5)
			return m

func _process(delta: float) -> void:
	_t += delta
	_mesh.rotate_y(delta * 2.0)
	_mesh.position.y = 0.5 + sin(_t * 2.5) * 0.1
	# the black hole eats loose items too -- dropped loot drifts in and is gone
	var bh = Universe.body_named("TIN 618")
	if bh:
		var bd: float = global_position.distance_to(bh.center)
		if bd < bh.radius * 1.2:
			queue_free()
			return
		elif bd < bh.radius * 6.0:
			global_position += (bh.center - global_position).normalized() \
				* delta * (bh.radius * 6.0 - bd) * 0.05
	if _t < 1.2:
		return   # grace: a just-dropped item isn't instantly re-grabbed
	var p := get_tree().get_first_node_in_group("player")
	if p and Game.mode == Game.Mode.ON_FOOT and not Game.dead \
			and global_position.distance_to(p.global_position) < 3.0:
		var left := Inventory.give_no_drop(id, count)
		if left < count:
			Sfx.play("coin", -18.0)
		count = left
		if count <= 0:
			queue_free()

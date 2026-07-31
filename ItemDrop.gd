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
	var m := BoxMesh.new()
	m.size = Vector3(0.5, 0.5, 0.5)
	_mesh.mesh = m
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

func _process(delta: float) -> void:
	_t += delta
	_mesh.rotate_y(delta * 2.0)
	_mesh.position.y = 0.5 + sin(_t * 2.5) * 0.1
	var p := get_tree().get_first_node_in_group("player")
	if p and Game.mode == Game.Mode.ON_FOOT and not Game.dead \
			and global_position.distance_to(p.global_position) < 3.0:
		var left := Inventory.give_no_drop(id, count)
		if left < count:
			Sfx.play("coin", -18.0)
		count = left
		if count <= 0:
			queue_free()

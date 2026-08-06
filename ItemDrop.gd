class_name ItemDrop
extends Node3D
## An item lying in the world (inventory overflow). Spins, glows, and
## hops back in the moment a slot opens and you walk over it.

var id: String = ""
var count: int = 1
var _mesh: MeshInstance3D
var _t: float = 0.0
var _vel := Vector3.ZERO
var _rest := false     # landed: physics off until further notice
var _flat := false     # inside a pocket interior: gravity is plain DOWN
var _p = null          # cached player (validity-checked before use)
var _bh = null         # cached TIN 618 body (bodies live for the session)
var _bh_looked := false

func _player_ref():
	if _p == null or not is_instance_valid(_p):
		_p = get_tree().get_first_node_in_group("player")
	return _p

func setup(id_in: String, n: int) -> void:
	id = id_in
	count = n

func _ready() -> void:
	add_to_group("itemdrop")
	# ONE MODEL: ground drops render the item's one true model -- same
	# pipeline as the inventory icon and the hand. No silhouettes, no
	# stand-ins, no exceptions.
	_mesh = MeshInstance3D.new()
	_mesh.position = Vector3(0, 0.5, 0)
	add_child(_mesh)
	var mdl := IconLib.build_model_world(id, get_tree())
	mdl.scale = Vector3(0.85, 0.85, 0.85)
	mdl.position = Vector3(0, 0.1, 0)
	_mesh.add_child(mdl)
	var lbl := Label3D.new()
	lbl.text = (Inventory.hotbar_name(id) + (" ×%d" % count if count > 1 else ""))
	lbl.font_size = 20
	lbl.modulate = Color(1, 1, 1, 0.8)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, 1.2, 0)
	add_child(lbl)
	_flat = Zones.exterior_of(global_position) != global_position

## Dropped items FALL: planet gravity outside, plain down indoors,
## raycast landing. Deep space has nothing to fall toward, so they float.
func _physics_process(delta: float) -> void:
	if _rest:
		return
	var g: Vector3 = Vector3.DOWN * 9.8 if _flat else Universe.gravity_at(global_position)
	if not _flat and g.length() < 0.05:
		_rest = true
		return
	_vel += g * delta
	if _vel.length() > 40.0:
		_vel = _vel.normalized() * 40.0
	var gdir := g.normalized()
	var move := _vel * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position - gdir * 0.5,
		global_position + move + gdir * 0.35)
	var p = _player_ref()
	if p != null:
		q.exclude = [p.get_rid()]
	var hit := space.intersect_ray(q)
	if hit:
		global_position = hit.position - gdir * 0.1
		_vel = Vector3.ZERO
		_rest = true
	else:
		global_position += move

func _process(delta: float) -> void:
	_t += delta
	_mesh.rotate_y(delta * 2.0)
	_mesh.position.y = 0.5 + sin(_t * 2.5) * 0.1
	# the black hole eats loose items too -- dropped loot drifts in and is gone
	if not _bh_looked:
		_bh_looked = true
		_bh = Universe.body_named("TIN 618")
	var bh = _bh
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
	var p = _player_ref()
	if p and Game.mode == Game.Mode.ON_FOOT and not Game.dead \
			and global_position.distance_to(p.global_position) < 3.0:
		var left := Inventory.give_no_drop(id, count)
		if left < count:
			Sfx.play("coin", -18.0)
		count = left
		if count <= 0:
			queue_free()

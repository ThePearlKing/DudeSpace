class_name Furniture
extends StaticBody3D
## Furniture: bench, chair, sofa, carpet, bed. Placed by the Furniture
## Placer tool, usable by every human (and the player, F). A carpet is
## furniture with no ambitions. A bed is a seat you take lying down.

const KINDS := ["bench", "chair", "sofa", "carpet", "bed"]

var kind: String = "bench"
var yaw: float = -1.0

func _ready() -> void:
	add_to_group("bench")   # rides the same save group as benches
	if yaw < 0.0:
		yaw = randf() * TAU
	var wood := Destructible.make_material(Color("#7a5a34"), 0.05)
	var dark := Destructible.make_material(Color("#3a3a3e"), 0.02)
	var cloth := Destructible.make_material(
		Color.from_hsv(randf(), randf_range(0.35, 0.6), randf_range(0.5, 0.8)), 0.06)
	var seats: Array = []
	match kind:
		"chair":
			_m(Vector3(0.6, 0.08, 0.55), Vector3(0, 0.55, 0), wood)
			_m(Vector3(0.6, 0.5, 0.08), Vector3(0, 0.85, 0.28), wood)
			_legs(0.6, dark)
			seats = [Vector3(0, 0.55, 0)]
			_hitbox(Vector3(0.7, 1.1, 0.7), Vector3(0, 0.55, 0))
		"sofa":
			_m(Vector3(2.2, 0.5, 0.8), Vector3(0, 0.35, 0), cloth)
			_m(Vector3(2.2, 0.6, 0.22), Vector3(0, 0.9, 0.32), cloth)
			for ax in [-1.05, 1.05]:
				_m(Vector3(0.22, 0.45, 0.8), Vector3(ax, 0.75, 0), cloth)
			seats = [Vector3(-0.65, 0.62, 0), Vector3(0, 0.62, 0), Vector3(0.65, 0.62, 0)]
			_hitbox(Vector3(2.4, 1.2, 0.9), Vector3(0, 0.6, 0))
		"carpet":
			_m(Vector3(2.6, 0.05, 1.8), Vector3(0, 0.03, 0), cloth)
			_m(Vector3(2.75, 0.04, 1.95), Vector3(0, 0.015, 0),
				Destructible.make_material(cloth.albedo_color.darkened(0.3), 0.03))
			_hitbox(Vector3(2.6, 0.1, 1.8), Vector3(0, 0.05, 0))
		"bed":
			_m(Vector3(1.2, 0.35, 2.3), Vector3(0, 0.28, 0), wood)
			_m(Vector3(1.1, 0.16, 2.1), Vector3(0, 0.53, 0), cloth)
			_m(Vector3(1.0, 0.14, 0.5), Vector3(0, 0.65, -0.75),
				Destructible.make_material(Color("#e8e2d4"), 0.1))
			_m(Vector3(1.2, 0.7, 0.12), Vector3(0, 0.6, -1.15), wood)
			seats = [Vector3(0, 0.62, 0.2)]
			_hitbox(Vector3(1.3, 0.8, 2.4), Vector3(0, 0.4, 0))
		_:   # bench
			_m(Vector3(1.8, 0.08, 0.55), Vector3(0, 0.55, 0), wood)
			_m(Vector3(1.8, 0.5, 0.08), Vector3(0, 0.85, 0.28), wood)
			_legs(1.8, dark)
			seats = [Vector3(-0.45, 0.55, 0), Vector3(0.45, 0.55, 0)]
			_hitbox(Vector3(1.9, 1.1, 0.7), Vector3(0, 0.55, 0))
	for sp in seats:
		var s := Node3D.new()
		s.position = sp
		s.add_to_group("seat")
		s.set_meta("taken", false)
		add_child(s)
	rotate_object_local(Vector3.UP, yaw)

func _m(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)

func _legs(w: float, mat: Material) -> void:
	for lx in [-w * 0.45, w * 0.45]:
		for lz in [-0.22, 0.22]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.07, 0.55, 0.07)
			mi.mesh = bm
			mi.position = Vector3(lx, 0.27, lz)
			mi.material_override = mat
			add_child(mi)

func _hitbox(size: Vector3, pos: Vector3) -> void:
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = size
	col.shape = cs
	col.position = pos
	add_child(col)

## F: sit (or lie, we don't police it) on the nearest free spot.
func use() -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p == null or not p.has_method("sit_on"):
		return
	var best: Node3D = null
	var bd := 1e9
	for c in get_children():
		if c is Node3D and c.is_in_group("seat") and not bool(c.get_meta("taken", false)):
			var d: float = c.global_position.distance_to(p.global_position)
			if d < bd:
				bd = d
				best = c
	if best != null:
		p.sit_on(best)
		Sfx.play("click", -22.0)
	elif kind != "carpet":
		Sfx.play("denied")

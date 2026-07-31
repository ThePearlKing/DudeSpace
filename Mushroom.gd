class_name Mushroom
extends StaticBody3D
## A procedurally GENERATED mushroom -- randomized archetype (classic /
## cluster / shelf / tall / glowing), sizes, bends, colours, spots.
## Shoot to harvest + eat -> heals, drops a few coins.

var _cap_color: Color = Color("#d13a3a")
var _heal: float = 22.0

func _ready() -> void:
	add_to_group("destructible")
	_cap_color = Color.from_hsv(randf(), randf_range(0.5, 0.9), randf_range(0.7, 1.0))
	var kind := randi() % 5
	match kind:
		0: _classic()
		1: _cluster()
		2: _shelf()
		3: _tall()
		_: _glow()
	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.height = 2.2
	cs.radius = 0.9
	col.shape = cs
	col.position = Vector3(0, 1.1, 0)
	add_child(col)

func _stem(h: float, r: float, bend: float) -> Vector3:
	## builds a bent stem out of segments; returns the top position
	var top := Vector3.ZERO
	var lean := Vector3(randf_range(-bend, bend), 0, randf_range(-bend, bend))
	var segs := randi_range(2, 4)
	for s in segs:
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r * (1.0 - float(s + 1) / float(segs) * 0.3)
		cm.bottom_radius = r * (1.0 - float(s) / float(segs) * 0.3)
		cm.height = h / float(segs)
		seg.mesh = cm
		seg.material_override = Destructible.make_material(Color("#efe6cf").lerp(_cap_color, 0.15), 0.1)
		seg.position = top + lean * float(s) + Vector3(0, (h / float(segs)) * 0.5, 0)
		add_child(seg)
		top += lean + Vector3(0, h / float(segs), 0)
	return top

func _cap(at: Vector3, r: float, squash: float, emit: float) -> void:
	var cap := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = r
	cm.height = r * 2.0 * squash
	cm.is_hemisphere = true
	cap.mesh = cm
	cap.material_override = Destructible.make_material(_cap_color, emit)
	cap.position = at
	add_child(cap)
	# spots
	for i in randi_range(0, 6):
		var dot := MeshInstance3D.new()
		var dm := SphereMesh.new()
		dm.radius = r * randf_range(0.08, 0.16)
		dm.height = dm.radius * 2.0
		dot.mesh = dm
		dot.material_override = Destructible.make_material(Color("#fff4e0"), 0.6)
		var a := randf() * TAU
		var rr := randf_range(0.2, 0.75) * r
		dot.position = at + Vector3(cos(a) * rr, r * squash * 0.55, sin(a) * rr)
		add_child(dot)

func _classic() -> void:
	var top := _stem(randf_range(0.8, 1.8), randf_range(0.18, 0.36), 0.12)
	_cap(top, randf_range(0.6, 1.3), randf_range(0.5, 0.8), 0.5)

func _cluster() -> void:
	for i in randi_range(3, 6):
		var off := Vector3(randf_range(-0.7, 0.7), 0, randf_range(-0.7, 0.7))
		var h := randf_range(0.3, 1.0)
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.08
		cm.bottom_radius = 0.11
		cm.height = h
		seg.mesh = cm
		seg.material_override = Destructible.make_material(Color("#efe6cf"), 0.1)
		seg.position = off + Vector3(0, h * 0.5, 0)
		add_child(seg)
		_cap(off + Vector3(0, h, 0), randf_range(0.2, 0.45), 0.7, 0.8)

func _shelf() -> void:
	# flat brackets stacked up an invisible trunk
	for i in randi_range(2, 4):
		var y := 0.3 + float(i) * randf_range(0.3, 0.5)
		var sh := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = randf_range(0.5, 1.0)
		cm.bottom_radius = cm.top_radius * 1.1
		cm.height = 0.14
		sh.mesh = cm
		sh.material_override = Destructible.make_material(_cap_color.lightened(float(i) * 0.1), 0.4)
		sh.position = Vector3(randf_range(-0.2, 0.2), y, randf_range(-0.2, 0.2))
		add_child(sh)

func _tall() -> void:
	var top := _stem(randf_range(2.2, 3.6), randf_range(0.1, 0.2), 0.25)
	_cap(top, randf_range(0.3, 0.6), randf_range(0.9, 1.3), 0.7)

func _glow() -> void:
	var top := _stem(randf_range(0.6, 1.4), randf_range(0.15, 0.3), 0.1)
	_cap(top, randf_range(0.5, 1.0), 0.65, 4.0)   # bioluminescent
	var l := OmniLight3D.new()
	l.light_color = _cap_color
	l.light_energy = 0.8
	l.omni_range = 6.0
	l.position = top + Vector3(0, 0.5, 0)
	add_child(l)

## Knife: harvest the mushroom whole (eat it later, or make salad).
func harvest() -> void:
	Inventory.add_res("shroom", 1)
	Sfx.play("eat", -14.0)
	queue_free()

func destroy(push_dir: Vector3) -> void:
	Game.heal(_heal)
	Sfx.play("eat")
	Destructible.spawn_debris(get_parent(), global_position + Vector3(0, 1, 0), Vector3(0.7, 0.7, 0.7), _cap_color, push_dir)
	Game.register_break(Vector3(1, 1, 1), 4)
	queue_free()
